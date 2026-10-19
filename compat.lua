---@diagnostic disable: undefined-global, undefined-field
--=========================================================================================
-- Cross-client compatibility layer.
--
-- SwedgeTimer ships one build for every WoW client family (Classic Era, TBC, Wrath,
-- Cata, Mists, Retail, WoW Forever, plus legacy/private clients). This is the single
-- place where client API differences are handled.
--
-- Sets:
--   st.family           : "ERA" | "TBC" | "WRATH" | "CATA" | "MISTS" | "RETAIL"
--                         | "FOREVER" | "UNKNOWN"
--   st.interface_number : the running client's TOC interface version, when knowable
--   st.is_retail        : true on the Retail (mainline) client
--   st.is_mainline      : true on Mainline-code clients (Retail, WoW Forever): their
--                         classic combat log is gone, so the swing engine cannot run
--   st.gcd_probe_spell_id : spell id whose cooldown reading mirrors the global cooldown
--   st.lust_spell_ids   : confirmed Bloodlust (2825) / Heroism (32182) spell ids
--   st.lust_supported   : true where Bloodlust/Heroism can exist (TBC+; Era: false)
--   st.cleu_supported   : true where the classic combat log exists (classic-line;
--                         Retail/Forever: false, so CLEU-driven chains stay inert)
--   st.api.*            : normalized wrappers for APIs that differ across clients
--
-- On clients where the original global function still exists, each wrapper preserves the
-- global's exact return values, so Titanforge 3.80.2 (the regression baseline) behaves
-- exactly as before. A few wrappers add a secret-value guard on top (see below): where
-- the value is not secret that guard is an exact no-op, and where a restricted read
-- hands back an opaque value it degrades to the documented "unknown" shape instead of
-- raising a Lua error.
-- Retail-only replacements (C_Spell, C_UnitAuras, C_SpecializationInfo) are used only
-- where the globals are gone.
--
-- Rule for the rest of the addon: never call a cross-client API directly - go through
-- st.api. Per-family data (spell IDs, form indices, talent checks) lives with the
-- class modules in classes/.
--=========================================================================================
local addon_name, st = ...

--------------------------------------------------------------------------------
-- Client family detection
--------------------------------------------------------------------------------

local family = "UNKNOWN"
local interface_number

-- WoW Forever ("Camelot") reports WOW_PROJECT_CAMELOT; fall back to its numeric value
-- so the comparison still works on clients where the global does not exist.
local WOW_PROJECT_FOREVER = WOW_PROJECT_CAMELOT or 18

do
	-- Preferred: the WOW_PROJECT_ID constants, present on every official client.
	local project_id = WOW_PROJECT_ID
	if project_id ~= nil then
		if project_id == WOW_PROJECT_CLASSIC then
			family = "ERA"
		elseif project_id == WOW_PROJECT_BURNING_CRUSADE_CLASSIC then
			family = "TBC"
		elseif project_id == WOW_PROJECT_WRATH_CLASSIC then
			family = "WRATH"
		elseif project_id == WOW_PROJECT_CATACLYSM_CLASSIC then
			family = "CATA"
		elseif project_id == WOW_PROJECT_MISTS_CLASSIC then
			family = "MISTS"
		elseif project_id == WOW_PROJECT_MAINLINE then
			family = "RETAIL"
		elseif project_id == WOW_PROJECT_FOREVER then
			family = "FOREVER"
		end
	end

	-- Fallback: the TOC interface version. Legacy/private clients have no project id.
	local get_build_info = GetBuildInfo
	if get_build_info then
		local _, _, _, toc = get_build_info()
		interface_number = tonumber(toc)
	end

	if family == "UNKNOWN" and interface_number then
		local major = math.floor(interface_number / 10000)
		if major == 1 and interface_number >= 16000 then
			-- WoW Forever shares Classic Era's major version (1.60.x -> 16000+)
			-- but runs Mainline client code: never bucket it as Era.
			family = "FOREVER"
		elseif major == 1 then
			family = "ERA"
		elseif major == 2 then
			family = "TBC"
		elseif major == 3 then
			family = "WRATH"
		elseif major == 4 then
			family = "CATA"
		elseif major == 5 then
			family = "MISTS"
		elseif major >= 10 then
			family = "RETAIL"
		end
	end
end

st.family = family
st.interface_number = interface_number
st.is_retail = (family == "RETAIL")
-- Retail and WoW Forever run Mainline client code; the classic combat log is gone
-- there, so the swing engine (LibClassicSwingTimerAPI) cannot work on them.
st.is_mainline = (family == "RETAIL" or family == "FOREVER")

-- GCD probe spell: a spell that has no cooldown of its own, so its cooldown reading
-- mirrors the global cooldown. 29515 ("TEST Scorch") is a vanilla-era test spell
-- present on every classic client; 61304 ("Global Cooldown") is Blizzard's dummy
-- for the same purpose on Mainline clients.
st.gcd_probe_spell_id = 29515
if st.is_mainline then
	st.gcd_probe_spell_id = 61304
end

--------------------------------------------------------------------------------
-- Bloodlust / Heroism (the lust window)
--------------------------------------------------------------------------------
-- Bloodlust (Horde) 2825 and its Alliance twin Heroism 32182 are a first-class
-- haste-window input for the swing tracking (hunter H2, paladin P3). Both ids
-- are CONFIRMED (bench/verify_bank.md §2: Wowhead TBC pages, 40s duration). The
-- spells only exist from TBC onward, so a lust helper must never arm on Classic
-- Era: consumers gate on st.lust_supported, which is derived from st.family
-- (never a version string) and stays false on Era and on the UNKNOWN fallback
-- family - only the confirmed families TBC/WRATH/CATA/MISTS/RETAIL/FOREVER arm.
st.lust_spell_ids = { 2825, 32182 }

st.lust_supported = (family ~= "ERA" and family ~= "UNKNOWN")

-- Post-lust debuff ids, registered for reference only. UNCONFIRMED:
-- bench/verify_bank.md §2 found no primary source for Exhaustion/Sated
-- 57723/57724 (secondary WeakAura mentions only), and the 57723-vs-57724 name
-- mapping is unconfirmed as well. IN-CLIENT CHECK: read the debuff id off the
-- player right after a Bloodlust lands before any caller depends on it. Nothing
-- may hard-depend on these values: matching them must stay on nil-safe paths
-- that degrade to "no debuff" instead of erroring.
st.post_lust_debuff_ids = { 57723, 57724 }

--------------------------------------------------------------------------------
-- Normalized API surface
--------------------------------------------------------------------------------

local api = {}
st.api = api

-- Secret values (Mainline-code clients) ---------------------------------------------------
-- Under the Mainline secret-value regime, restricted reads (cooldowns, power, health,
-- auras, combat stats, casts) can return opaque "secret" values: type() still reports the
-- underlying type, so a type() or "== nil" guard cannot see them, while arithmetic,
-- comparison and table indexing with one raises a Lua error. Feature-detect the probe
-- once; on every classic client it is absent and every guard below is an exact no-op.

local is_secret = issecretvalue or function()
	return false
end

-- Spell info -----------------------------------------------------------------------------
-- Classic shape: name, rank, icon, castTime, minRange, maxRange, spellID
-- Retail shape:  C_Spell.GetSpellInfo returns a SpellInfo table.

if GetSpellInfo then
	api.GetSpellInfo = GetSpellInfo
elseif C_Spell and C_Spell.GetSpellInfo then
	api.GetSpellInfo = function(spell)
		local info = C_Spell.GetSpellInfo(spell)
		if not info then
			return nil
		end
		-- Retail has no "rank"; the remaining units match the classic returns.
		return info.name, nil, info.originalIconID, info.castTime, info.minRange, info.maxRange, info.spellID
	end
else
	-- Unknown client: report a 1.5s cast time so GCD estimation stays sane.
	api.GetSpellInfo = function()
		return nil, nil, nil, 1500, 0, 0, nil
	end
end

-- Spell knowledge ------------------------------------------------------------------------
-- Whether the player knows a spell, used to resolve the highest known rank of a tracked
-- spell family. The probes exist on different client families; the first one that returns
-- a value wins, and a client with none of them reports "unknown" instead of erroring.

local spell_known_probes = {}
if C_Spell and C_Spell.IsSpellKnownOrOverridesKnown then
	spell_known_probes[#spell_known_probes + 1] = C_Spell.IsSpellKnownOrOverridesKnown
end
-- IsSpellKnown is deprecated on modern clients, so resolve it dynamically; this both
-- dodges the deprecation annotation and tolerates clients that removed the global.
local classic_is_spell_known = rawget(_G, "IsSpellKnown")
if C_Spell and C_Spell.IsSpellKnown then
	spell_known_probes[#spell_known_probes + 1] = C_Spell.IsSpellKnown
elseif classic_is_spell_known then
	spell_known_probes[#spell_known_probes + 1] = classic_is_spell_known
end
-- C_SpellBook.IsSpellKnown (documented in SpellBookDocumentation.lua: "Returns true if a
-- player knows a spell") is the probe on the Mainline-code clients, where every probe
-- above is absent. Appended after them on purpose: a client whose chain already answers
-- (the classic clients, with Blizzard's deprecation fallbacks loaded) keeps the exact
-- same answer source, so nothing changes there.
local spell_book_api = rawget(_G, "C_SpellBook")
if spell_book_api and spell_book_api.IsSpellKnown then
	spell_known_probes[#spell_known_probes + 1] = spell_book_api.IsSpellKnown
end

function api.is_spell_known(spell_id)
	for i = 1, #spell_known_probes do
		local known = spell_known_probes[i](spell_id)
		if known ~= nil then
			return known == true
		end
	end
	return false
end

-- Spell cooldowns ------------------------------------------------------------------------
-- Classic shape: start, duration, enabled, modRate (enabled is 1/0)
-- Retail shape:  C_Spell.GetSpellCooldown returns a SpellCooldownInfo table.
--
-- One wrapper for every family instead of a pass-through of the classic global: that
-- global's annotation declares no return values, and inheriting it would make the
-- wrapper's own returns look redundant to the type checker.

local classic_get_spell_cooldown = GetSpellCooldown
local retail_get_spell_cooldown = C_Spell and C_Spell.GetSpellCooldown

function api.GetSpellCooldown(spell)
	local start_time, duration, enabled, mod_rate
	if classic_get_spell_cooldown then
		start_time, duration, enabled, mod_rate = classic_get_spell_cooldown(spell)
	elseif retail_get_spell_cooldown then
		local info = retail_get_spell_cooldown(spell)
		if info then
			-- isEnabled is tested for secrecy before it is coerced, so a restricted
			-- boolean is also caught by the whole-read degrade below.
			local enabled_raw = info.isEnabled
			if is_secret(enabled_raw) then
				return 0, 0, 0, 0
			end
			start_time = info.startTime
			duration = info.duration
			enabled = enabled_raw and 1 or 0
			mod_rate = info.modRate
		end
	end
	-- A secret reading reports "no cooldown" - the shape every caller already treats as
	-- idle (duration == 0 / duration <= 1.51 / no latch). Exact no-op without the probe.
	if is_secret(start_time) or is_secret(duration) or is_secret(enabled) or is_secret(mod_rate) then
		return 0, 0, 0, 0
	end
	return start_time or 0, duration or 0, enabled or 0, mod_rate or 0
end

-- Spell usability ------------------------------------------------------------------------
-- Whether a spell can be cast right now, and specifically whether it is unusable for lack
-- of resources (mana). Every probe shape returns (usable, insufficientPower): the C_Spell
-- form on Mainline and the newer classic clients, the classic IsSpellUsable global, then
-- the older IsUsableSpell. All three are read through _G: they are not in the annotation
-- set of every client family, where naming them directly would be an undefined-global /
-- undefined-field reference. No probe at all: nil, i.e. unknown - callers must treat
-- unknown as "no tint", never as a usable reading.

local spell_usable_probe
do
	local c_spell = rawget(_G, "C_Spell")
	if type(c_spell) == "table" and type(c_spell.IsSpellUsable) == "function" then
		spell_usable_probe = c_spell.IsSpellUsable
	elseif type(rawget(_G, "IsSpellUsable")) == "function" then
		spell_usable_probe = rawget(_G, "IsSpellUsable")
	elseif type(rawget(_G, "IsUsableSpell")) == "function" then
		spell_usable_probe = rawget(_G, "IsUsableSpell")
	end
end

function api.IsSpellUsable(spell)
	if not spell_usable_probe then
		return nil
	end
	local usable, insufficient = spell_usable_probe(spell)
	-- A restricted reading reports unknown (nil), which every caller renders as "no
	-- tint", never as a usable/insufficient claim.
	if is_secret(usable) or is_secret(insufficient) then
		return nil, nil
	end
	return usable, insufficient
end

-- Spell power costs ----------------------------------------------------------------------
-- Classic and retail both return an array of cost structs; entries have a .cost field.

-- Read through _G: the global, and the classic-only C_Spell fields below, are not in the
-- annotation set of Mainline-code clients, where naming them directly would be an
-- undefined-global / undefined-field reference.
local spell_api = rawget(_G, "C_Spell")

local get_spell_power_cost = _G.GetSpellPowerCost
	or (spell_api and spell_api.GetSpellPowerCost)

-- Unknown client: a zero-cost entry of the expected shape instead of an error.
api.GetSpellPowerCost = get_spell_power_cost or function()
	return { { cost = 0, minCost = 0 } }
end

-- Spell base cooldowns -------------------------------------------------------------------
-- Classic: GetSpellBaseCooldown(spell) returns the base cooldown in milliseconds.
-- Retail has no replacement; degrade to 0 rather than error.

if GetSpellBaseCooldown then
	local raw_get_spell_base_cooldown = GetSpellBaseCooldown
	api.GetSpellBaseCooldown = function(spell)
		local first, second = raw_get_spell_base_cooldown(spell)
		-- A restricted reading reports the absent-client shape (0, 0): callers treat a
		-- non-positive base cooldown as "no value" and fall back to their own constant.
		if is_secret(first) or is_secret(second) then
			return 0, 0
		end
		return first, second
	end
else
	api.GetSpellBaseCooldown = function()
		return 0, 0
	end
end

-- Current spell --------------------------------------------------------------------------
-- Detects on-next-attack abilities queued for the current cast (Maul, Heroic Strike, ...).

-- The classic global is read through _G: it is absent on Mainline-code clients, and
-- naming it directly would be an undefined-global reference there.
local is_current_spell = _G.IsCurrentSpell

api.IsCurrentSpell = is_current_spell or (C_Spell and C_Spell.IsCurrentSpell) or function()
		return false
	end

-- Resources (rage, mana, energy) ---------------------------------------------------------
-- UnitPower / UnitPowerMax exist on every supported client (the modern ones prefer
-- UnitPowerType but do not remove the globals). Wrapped for the secret regime: a
-- restricted reading reports nil (unknown), which every caller's type() guard already
-- routes to its "cannot claim" branch. An unknown client keeps reporting 0 so a caller
-- can never error while comparing.

local legacy_unit_power = rawget(_G, "UnitPower")
local legacy_unit_power_max = rawget(_G, "UnitPowerMax")

if legacy_unit_power then
	api.UnitPower = function(unit, power_type)
		local value = legacy_unit_power(unit, power_type)
		if is_secret(value) then
			return nil
		end
		return value
	end
else
	api.UnitPower = function()
		return 0
	end
end
if legacy_unit_power_max then
	api.UnitPowerMax = function(unit, power_type)
		local value = legacy_unit_power_max(unit, power_type)
		if is_secret(value) then
			return nil
		end
		return value
	end
else
	api.UnitPowerMax = function()
		return 0
	end
end

-- Unit power type: UnitPowerType(unit) returns the numeric power-type id (0 mana,
-- 1 rage, 3 energy, ...) and its token. The druid form label maps 3 -> Cat and
-- 1 -> Bear (reference GetDruidFormLabel, SuperSwingTimer_ClassMods.lua:4530-4538) and
-- the energy tick bar only shows for the energy power type. Unknown client: mana (0,
-- "MANA"), the safe default - every mapping then falls through to "Caster" and the
-- energy tick stays hidden. Read through _G for the same undefined-global reason.

local legacy_unit_power_type = rawget(_G, "UnitPowerType")

if legacy_unit_power_type then
	api.UnitPowerType = function(unit)
		local power_type, token = legacy_unit_power_type(unit)
		-- A restricted reading reports unknown (nil), which every mapping falls through
		-- as "Caster" / no energy tick - the same shape an absent client gets.
		if is_secret(power_type) or is_secret(token) then
			return nil
		end
		return power_type, token
	end
else
	api.UnitPowerType = function()
		return 0, "MANA"
	end
end

-- Health ---------------------------------------------------------------------------------
-- UnitHealth / UnitHealthMax exist on every supported client like the power reads above;
-- read through _G for the same undefined-global reason. A client that cannot answer
-- returns nil, which callers read as unknown health - never as zero. A restricted
-- (secret) reading degrades the same way.

local legacy_unit_health = rawget(_G, "UnitHealth")
local legacy_unit_health_max = rawget(_G, "UnitHealthMax")

if legacy_unit_health then
	api.UnitHealth = function(unit)
		local value = legacy_unit_health(unit)
		if is_secret(value) then
			return nil
		end
		return value
	end
else
	api.UnitHealth = function()
		return nil
	end
end
if legacy_unit_health_max then
	api.UnitHealthMax = function(unit)
		local value = legacy_unit_health_max(unit)
		if is_secret(value) then
			return nil
		end
		return value
	end
else
	api.UnitHealthMax = function()
		return nil
	end
end

-- Auras ----------------------------------------------------------------------------------
-- Classic shape: UnitAura(unit, index, filter) returns
--   name, icon, count, dispelName, duration, expirationTime, sourceUnit, isStealable,
--   nameplateShowPersonal, spellId, ...
-- Retail shape:  C_UnitAuras.GetAuraDataByIndex returns an AuraData table. The field
-- order below matches Blizzard's own AuraUtil.UnpackAuraData back-compat mapping.

-- Aura entries are taken whole or not at all: one secret field makes the entry unusable
-- (consumers run arithmetic on durations/expirations, compare names and index spell-id
-- tables), and the existing "name == nil -> stop scanning" loops are the only degrade
-- they can consume, so a secret entry is returned as absent (nil) instead of per-field
-- nils. All three source paths are wrapped, including the classic-global pass-through.

local function aura_entry_is_secret(name, icon, count, dispel_name, duration, expiration,
	source, is_stealable, nameplate_show_personal, spell_id)
	return is_secret(name) or is_secret(icon) or is_secret(count) or is_secret(dispel_name)
		or is_secret(duration) or is_secret(expiration) or is_secret(source)
		or is_secret(is_stealable) or is_secret(nameplate_show_personal) or is_secret(spell_id)
end

if UnitAura then
	api.UnitAura = function(unit, index, filter)
		local name, icon, count, dispel_name, duration, expiration, source, is_stealable,
			nameplate_show_personal, spell_id = UnitAura(unit, index, filter)
		if aura_entry_is_secret(name, icon, count, dispel_name, duration, expiration,
			source, is_stealable, nameplate_show_personal, spell_id) then
			return nil
		end
		return name, icon, count, dispel_name, duration, expiration, source, is_stealable,
			nameplate_show_personal, spell_id
	end
elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
	api.UnitAura = function(unit, index, filter)
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
		if not aura then
			return nil
		end
		local name, icon, count, dispel_name, duration, expiration, source, is_stealable,
			nameplate_show_personal, spell_id = aura.name, aura.icon, aura.applications,
			aura.dispelName, aura.duration, aura.expirationTime, aura.sourceUnit,
			aura.isStealable, aura.nameplateShowPersonal, aura.spellId
		if aura_entry_is_secret(name, icon, count, dispel_name, duration, expiration,
			source, is_stealable, nameplate_show_personal, spell_id) then
			return nil
		end
		return name, icon, count, dispel_name, duration, expiration, source, is_stealable,
			nameplate_show_personal, spell_id
	end
else
	api.UnitAura = function()
		return nil
	end
end

-- Player aura scan: one predicate over the player's own buffs, normalised into
--   duration_remaining_seconds, stacks = api.scan_player_aura(predicate)
-- CONTRACT FROZEN (hunter H2 / paladin P3 code against this exact shape):
--   * predicate(spell_id, name, stacks) returns truthy for a match; first match
--     wins. spell_id can be nil on a client without numeric ids - an id
--     comparison already treats that safely - and stacks follows the same
--     count convention as the wrapper above.
--   * returns nil, nil when not found, when no aura API exists on the client,
--     or when the predicate is not a function. Callers must treat nil as "no
--     window", never as zero.
--   * remaining seconds come from expirationTime on the api.get_time() axis
--     (the domain the rest of the addon compares in), clamped at 0 once
--     expired; nil remaining with a set stacks means found-but-no-time.
--   * stacks is the count for anything above 1 and nil for a non-stacking aura
--     (classic count nil, retail applications 1) - identical on every family.
-- Family paths, all through this file's own wrappers: the classic global on
-- Era/TBC/Wrath (a consumer may re-poll at a 0.05s cadence - this scan holds no
-- state of its own) and the C_UnitAuras read on the Mainline-code clients. A
-- secret entry degrades to absent in the wrapper above and the walk continues
-- past it (no early break): a restricted row above the buff no longer
-- truncates the scan, so a restricted list still reports not found (nil, nil)
-- only when nothing matches.
local scan_player_aura_index_max = 40

function api.scan_player_aura(predicate)
	if type(predicate) ~= "function" then
		return nil, nil
	end
	local now = api.get_time()
	for index = 1, scan_player_aura_index_max do
		local name, _, count, _, _, expiration, _, _, _, spell_id = api.UnitAura(
			"player", index, "HELPFUL")
		-- No early break (R2): nil is simply no match at this index. The
		-- 40-row cap bounds the walk, so the worst-case cost is the same 40
		-- UnitAura calls as before.
		if name ~= nil then
			if predicate(spell_id, name, count) then
				local remaining
				if type(expiration) == "number" then
					remaining = expiration - now
					if remaining < 0 then
						remaining = 0
					end
				end
				local stacks
				if type(count) == "number" and count > 1 then
					stacks = count
				end
				return remaining, stacks
			end
		end
	end
	return nil, nil
end

-- Secret-value regime observability (M5): can restricted (secret) AURA rows be
-- hidden from every aura consumer right now? The whole-entry degrade above stays
-- exactly as it is (E2: one secret field -> the entry reads absent); this probe
-- only makes the regime itself readable so a consumer can tell "no lust" from
-- "the aura list may be restricted". true/false only when C_Secrets answers with a
-- boolean; nil when the API/probe is absent or throws (unknown, never "no" - every
-- classic client is the exact no-op nil here).
function api.auras_may_be_secret()
	local c_secrets = rawget(_G, "C_Secrets")
	if type(c_secrets) ~= "table" then
		return nil
	end
	local probe = rawget(c_secrets, "ShouldAurasBeSecret")
	if type(probe) ~= "function" then
		return nil
	end
	local ok, value = pcall(probe)
	if ok and type(value) == "boolean" then
		return value
	end
	return nil
end

-- Casting and channels -------------------------------------------------------------------
-- Wrapped rather than passed through: a restricted (secret) cast payload degrades to
-- "no cast is running" (nil), the shape every consumer already handles - the classes
-- pack start/end times into arithmetic and match names/spell ids, none of which a secret
-- value survives. The payloads are NOT identical: UnitCastingInfo returns castID before
-- notInterruptible and the spell id 9th, while UnitChannelInfo has no castID and returns
-- the spell id 8th; callers must unpack each accordingly.

local legacy_unit_casting_info = UnitCastingInfo
local legacy_unit_channel_info = UnitChannelInfo

-- name is compared, start/end times are arithmetic (ms/1000, cast windows) and spell_id
-- is matched against tables: if any of them is secret the payload is not usable.
local function cast_payload_is_secret(name, start_ms, end_ms, spell_id)
	return is_secret(name) or is_secret(start_ms) or is_secret(end_ms) or is_secret(spell_id)
end

if legacy_unit_casting_info then
	api.UnitCastingInfo = function(unit)
		local name, text, texture, start_ms, end_ms, is_trade_skill, cast_id,
			not_interruptible, spell_id = legacy_unit_casting_info(unit)
		if cast_payload_is_secret(name, start_ms, end_ms, spell_id) then
			return nil
		end
		return name, text, texture, start_ms, end_ms, is_trade_skill, cast_id,
			not_interruptible, spell_id
	end
else
	api.UnitCastingInfo = function() return nil end
end
if legacy_unit_channel_info then
	api.UnitChannelInfo = function(unit)
		local name, text, texture, start_ms, end_ms, is_trade_skill, not_interruptible,
			spell_id = legacy_unit_channel_info(unit)
		if cast_payload_is_secret(name, start_ms, end_ms, spell_id) then
			return nil
		end
		return name, text, texture, start_ms, end_ms, is_trade_skill, not_interruptible,
			spell_id
	end
else
	api.UnitChannelInfo = function() return nil end
end

-- Folding caster lookup: a live cast first, a channel second, normalised into
--   name, spell_id, start_seconds, end_seconds
-- in the seconds domain of api.get_time() (the clients report startTimeMs/endTimeMs on
-- the GetTime()*1000 axis). The payload arities differ and are documented here because
-- the two source functions cannot be unpacked the same way:
--   UnitCastingInfo: name, text, texture, startTimeMs, endTimeMs, isTradeSkill,
--                    castID, notInterruptible, spellID
--   UnitChannelInfo: name, text, texture, startTimeMs, endTimeMs, isTradeSkill,
--                    notInterruptible, spellID           (no castID; spellID 8th)
-- spell_id is nil when the payload carries no numeric id (older classic clients), so
-- callers must fall back to matching on the name.
function api.UnitCastingSpell(unit)
	if not unit then
		return nil
	end
	local name, _, _, start_ms, end_ms, _, _, _, spell_id = api.UnitCastingInfo(unit)
	if not name then
		name, _, _, start_ms, end_ms, _, _, spell_id = api.UnitChannelInfo(unit)
	end
	if not name then
		return nil
	end
	if type(spell_id) ~= "number" then
		spell_id = nil
	end
	local start_seconds
	if type(start_ms) == "number" then
		start_seconds = start_ms / 1000
	end
	local end_seconds
	if type(end_ms) == "number" then
		end_seconds = end_ms / 1000
	end
	return name, spell_id, start_seconds, end_seconds
end

-- Spell haste ----------------------------------------------------------------------------
-- UnitSpellHaste is the current global where available; GetSpellHaste is the older one,
-- removed from the modern clients entirely, so it is looked up dynamically (never
-- referenced as a bare global) and both return a percentage, or nil where lacking.

local legacy_get_spell_haste = rawget(_G, "GetSpellHaste")

if UnitSpellHaste then
	api.UnitSpellHaste = function(unit)
		local haste = UnitSpellHaste(unit)
		if is_secret(haste) then
			return nil
		end
		return haste
	end
else
	api.UnitSpellHaste = function() return nil end
end
if legacy_get_spell_haste then
	api.GetSpellHaste = function()
		local haste = legacy_get_spell_haste()
		if is_secret(haste) then
			return nil
		end
		return haste
	end
else
	api.GetSpellHaste = function() return nil end
end

-- Talents --------------------------------------------------------------------------------
-- Classic (Era/TBC/Wrath/Cata): GetTalentInfo(tab, index) returns
--   name, icon, tier, column, rank, maxRank, ...
-- The global only exists on clients that expose Blizzard's deprecation fallbacks, so
-- mirror Blizzard's own C_SpecializationInfo mapping (see Blizzard_DeprecatedSpecialization).
-- Mists and Retail use different talent systems. The final fallback reports rank 0 so
-- that "has talent" checks all evaluate to false instead of erroring.

if GetTalentInfo then
	api.GetTalentInfo = GetTalentInfo
elseif C_SpecializationInfo and C_SpecializationInfo.GetTalentInfo then
	api.GetTalentInfo = function(tab, index, isInspect, isPet, groupIndex)
		local query = {
			specializationIndex = tab,
			talentIndex = index,
			isInspect = isInspect,
			isPet = isPet,
			groupIndex = groupIndex,
		}
		local info = C_SpecializationInfo.GetTalentInfo(query)
		if not info then
			return nil, nil, nil, nil, 0
		end
		return info.name, info.icon, info.tier, info.column, info.rank,
			info.maxRank, info.meetsPrereq, info.previewRank,
			info.meetsPreviewPrereq, info.isExceptional, info.hasGoldBorder,
			info.talentID
	end
else
	api.GetTalentInfo = function()
		return nil, nil, nil, nil, 0
	end
end

-- Talent groups / specializations --------------------------------------------------------
-- Classic: GetActiveTalentGroup() returns 1 or 2.
-- Retail:  C_SpecializationInfo.GetActiveSpecGroup() returns the active spec index.

local getActiveTalentGroup
if GetActiveTalentGroup then
	getActiveTalentGroup = GetActiveTalentGroup
elseif C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
	getActiveTalentGroup = C_SpecializationInfo.GetActiveSpecGroup
else
	getActiveTalentGroup = function()
		return 1
	end
end
api.GetActiveTalentGroup = getActiveTalentGroup

-- Shapeshift form index ------------------------------------------------------------------
-- Classic indices: 1=bear, 3=cat, 4=travel, 5=moonkin/tree/flight, 6=flight.
-- Other families index forms differently; form-dependent visual features will need
-- per-family data with the class modules.

-- Read through _G: the global is not in the annotation set of Mainline-code clients, where
-- naming it directly would be an undefined-global reference.
local get_shapeshift_form = _G.GetShapeshiftForm
local shapeshift_form_api = _G.C_ShapeshiftForm

if get_shapeshift_form then
	api.GetShapeshiftForm = get_shapeshift_form
elseif shapeshift_form_api and shapeshift_form_api.GetShapeshiftForm then
	api.GetShapeshiftForm = shapeshift_form_api.GetShapeshiftForm
else
	api.GetShapeshiftForm = function()
		return 0
	end
end

-- Weapon speeds --------------------------------------------------------------------------
-- Used to detect whether an offhand/ranged weapon exists.

if UnitAttackSpeed then
	api.UnitAttackSpeed = function(unit)
		local main_speed, off_speed, ranged_speed = UnitAttackSpeed(unit)
		-- Any restricted speed fails the whole read (nil): an unknown read must never be
		-- mistaken for a weapon reading either way.
		if is_secret(main_speed) or is_secret(off_speed) or is_secret(ranged_speed) then
			return nil
		end
		return main_speed, off_speed, ranged_speed
	end
else
	api.UnitAttackSpeed = function()
		return 0, 0
	end
end

if UnitRangedDamage then
	api.UnitRangedDamage = function(unit)
		local damage = UnitRangedDamage(unit)
		if is_secret(damage) then
			return nil
		end
		return damage
	end
else
	api.UnitRangedDamage = function()
		return 0
	end
end

-- Ranged state and spell range ------------------------------------------------------------
-- Probes for the hunter ranged sync: auto-repeat state (mounted hunters never
-- auto-repeat), mounted state, and spell range. Each degrades to a safe value on a
-- client without the probe.

-- Probe selection: the C_Spell form on Mainline-code clients, the classic global
-- elsewhere; both are pcall-wrapped because their argument forms differ across clients.
-- Neither present -> false. The classic global is read through _G: it is absent on
-- Mainline-code clients, where naming it directly would be an undefined-global
-- reference.
local c_spell_is_auto_repeat = C_Spell and C_Spell.IsAutoRepeatSpell
local classic_is_auto_repeat = rawget(_G, "IsAutoRepeatSpell")

function api.IsAutoRepeatSpell(spell)
	local probe = c_spell_is_auto_repeat or classic_is_auto_repeat
	if not probe then
		return false
	end
	local ok, is_repeating = pcall(probe, spell)
	return ok and is_repeating == true
end

-- Mounted state; false on a client without the global. Read through _G for the same
-- undefined-global reason as above.
local is_mounted = rawget(_G, "IsMounted")

api.IsMounted = is_mounted or function()
	return false
end

-- Spell range: 1/true in range, 0/false out of range, nil UNKNOWN (the spell id is not
-- on the client, or there is no unit, or the client has no global at all). Callers must
-- treat nil as unknown, never as "out of range". The classic global is preferred (the
-- exact pre-existing behaviour); on the Mainline-code clients, where the global is
-- removed, C_Spell.IsSpellInRange (SpellDocumentation.lua: true/false/nil) is used and
-- normalised to 1/0/nil. A restricted reading reports nil (unknown).
local is_spell_in_range = rawget(_G, "IsSpellInRange")
local c_spell_is_spell_in_range = C_Spell and C_Spell.IsSpellInRange

function api.IsSpellInRange(spell, unit)
	if is_spell_in_range then
		local result = is_spell_in_range(spell, unit)
		if is_secret(result) then
			return nil
		end
		return result
	end
	if c_spell_is_spell_in_range then
		local in_range = c_spell_is_spell_in_range(spell, unit)
		if is_secret(in_range) or in_range == nil then
			return nil
		end
		if in_range == true then
			return 1
		end
		if in_range == false then
			return 0
		end
		-- Out-of-contract return: unknown, never a wrong range.
		return nil
	end
	return nil
end

-- Interaction distance: CheckInteractDistance(unit, index) answers whether the unit is
-- inside one of the classic interaction bands. Index 3 is the band SuperSwingTimer uses
-- as the hunter "sweet spot" (HUNTER_SWEET_SPOT_INTERACT_INDEX, see
-- SuperSwingTimer_ClassMods.lua:5533, where the range-helper state ladder tests it
-- between melee and ranged); the exact in-game band still needs in-client confirmation
-- on each family. Returns true/1 in band, false/0 outside, nil when the client has no
-- global at all. Read through _G for the same undefined-global reason as above.
local check_interact_distance = rawget(_G, "CheckInteractDistance")

if check_interact_distance then
	api.CheckInteractDistance = function(unit, index)
		local in_band = check_interact_distance(unit, index)
		if is_secret(in_band) then
			return nil
		end
		return in_band
	end
else
	api.CheckInteractDistance = function()
		return nil
	end
end

-- Unit distance (exact) ------------------------------------------------------------------
-- UnitDistanceSquared(unit) returns the distance in squared yards plus a boolean saying
-- whether the distance was actually checked; Blizzard's own consumer
-- (CompactUnitFrame_UpdateDistance) only trusts the reading when that flag is true.
-- Present on Era 1.15, TBC Anniversary 2.5, Titanforge 3.80, Mists, Retail and WoW
-- Forever 1.60; clients without the global report nil (unknown).
-- The wrapper normalises to exact yards (sqrt of the squared reading). A client without
-- the global, an unchecked reading, a non-number / negative / non-finite value, a
-- restricted (secret) reading and a throwing call all report nil; callers must treat
-- nil as unknown, never as a distance.
local unit_distance_squared = UnitDistanceSquared

function api.UnitDistance(unit)
	if not unit_distance_squared then
		return nil
	end
	local ok, squared, checked = pcall(unit_distance_squared, unit)
	if not ok or is_secret(squared) or is_secret(checked) then
		return nil
	end
	if not checked then
		return nil
	end
	if type(squared) ~= "number" or squared ~= squared or squared < 0
		or squared == math.huge then
		return nil
	end
	return math.sqrt(squared)
end

-- Combat ratings -------------------------------------------------------------------------

if GetCombatRating then
	api.GetCombatRating = GetCombatRating
else
	api.GetCombatRating = function()
		return 0
	end
end

if GetCombatRatingBonus then
	api.GetCombatRatingBonus = GetCombatRatingBonus
else
	api.GetCombatRatingBonus = function()
		return 0
	end
end

-- Network stats --------------------------------------------------------------------------
-- GetNetStats() is global on every family: bandwidthDown, bandwidthUp, latencyHome, latencyWorld.

if GetNetStats then
	api.GetNetStats = GetNetStats
else
	api.GetNetStats = function()
		return 0, 0, 0, 0
	end
end

-- Inventory items (trinket HUD) ----------------------------------------------------------
-- The trinket slots read the equipped item's id, icon and on-use cooldown. The underlying
-- globals are classic-line only and take (unit, slot); the wrappers fix the unit to the
-- player (the only unit the addon ever queries) and take the inventory slot alone. All
-- three are read through _G: they are not in the annotation set of Mainline-code clients,
-- where naming them directly would be an undefined-global reference. Absent global: the
-- id and the texture report nil (unknown item) and the cooldown reports zeros (no
-- cooldown), so a client without them renders an idle trinket slot instead of erroring.

local get_inventory_item_id = rawget(_G, "GetInventoryItemID")
local get_inventory_item_texture = rawget(_G, "GetInventoryItemTexture")
local get_inventory_item_cooldown = rawget(_G, "GetInventoryItemCooldown")

function api.GetInventoryItemID(slot)
	if not get_inventory_item_id then
		return nil
	end
	local item_id = get_inventory_item_id("player", slot)
	if is_secret(item_id) then
		return nil
	end
	return item_id
end

function api.GetInventoryItemTexture(slot)
	if not get_inventory_item_texture then
		return nil
	end
	local texture = get_inventory_item_texture("player", slot)
	if is_secret(texture) then
		return nil
	end
	return texture
end

-- Normalised to start, duration, enabled (the classic multi-return). A client that hands
-- back a SpellCooldownInfo-shaped table instead is unfolded the same way compat's
-- GetSpellCooldown wrapper unfolds it (startTime / duration / isEnabled). A restricted
-- reading reports the idle shape (0, 0, 0), never a secret.

function api.GetInventoryItemCooldown(slot)
	if not get_inventory_item_cooldown then
		return 0, 0, 0
	end
	local start_time, duration, enabled = get_inventory_item_cooldown("player", slot)
	if type(start_time) == "table" then
		local info = start_time
		local enabled_raw = info.isEnabled
		if is_secret(enabled_raw) then
			return 0, 0, 0
		end
		start_time = info.startTime
		duration = info.duration
		enabled = enabled_raw and 1 or 0
	end
	if is_secret(start_time) or is_secret(duration) or is_secret(enabled) then
		return 0, 0, 0
	end
	return start_time or 0, duration or 0, enabled or 0
end

-- Combat log (classic-line clients only) -------------------------------------------------
-- CombatLogGetCurrentEventInfo() reads the current COMBAT_LOG_EVENT_UNFILTERED payload.
-- Mainline-code clients (Retail, WoW Forever) have no classic combat log, so the wrapper
-- returns nil there and callers must treat the payload as absent. Read through _G for the
-- undefined-global reason above.

local get_combat_log_event_info = rawget(_G, "CombatLogGetCurrentEventInfo")

function api.CombatLogGetCurrentEventInfo()
	if not get_combat_log_event_info then
		return nil
	end
	return get_combat_log_event_info()
end

-- Classic combat-log availability (R3): the paladin twist attempt/success chain
-- and the warrior Overpower dodge window arm only where the classic combat log
-- exists. Probed from the same CombatLogGetCurrentEventInfo global the wrapper
-- above reads: classic-line clients expose it, Mainline-code clients (Retail,
-- WoW Forever) do not. Consumers gate on this flag, never on st.is_mainline
-- alone (Forever runs Mainline code but keeps its own swing engine).
st.cleu_supported = get_combat_log_event_info ~= nil

-- Totems -----------------------------------------------------------------------------------
-- GetTotemInfo(slot) reports the totem in a slot:
--   haveTotem, totemName, startTime, duration, icon, modRate, spellID
-- or nothing at all when the slot holds no totem (MayReturnNothing). Slots are
-- 1=Fire, 2=Earth, 3=Water, 4=Air (Blizzard_FrameXMLBase/Constants.lua:239-244); the
-- startTime is on the GetTime() axis, the same domain api.get_time() reports, so a
-- caller can adopt it as a drop stamp directly. On Mainline-code clients the slot
-- can be secret (SecretWhenTotemSlotSecret): one restricted field degrades the whole
-- read to nil (absent), the shape every caller already handles - the same whole-or-
-- nothing rule as the aura entries above. A client without the global, a throwing
-- call and a bad slot all report nil; callers must treat nil as unknown, never as
-- "no totem". Read through _G and pcall-wrapped: the global is absent on some
-- clients and MayReturnNothing means any slot can come back empty.

local get_totem_info = rawget(_G, "GetTotemInfo")

function api.GetTotemInfo(slot)
	if not get_totem_info then
		return nil
	end
	local ok, have_totem, totem_name, start_time, duration, icon, mod_rate, spell_id =
		pcall(get_totem_info, slot)
	if not ok then
		return nil
	end
	if have_totem == nil then
		return nil
	end
	if is_secret(have_totem) or is_secret(totem_name) or is_secret(start_time)
		or is_secret(duration) or is_secret(icon) or is_secret(mod_rate)
		or is_secret(spell_id) then
		return nil
	end
	return have_totem, totem_name, start_time, duration, icon, mod_rate, spell_id
end

--------------------------------------------------------------------------------
-- Clock
--------------------------------------------------------------------------------
-- Swing-relative timing must live in the GetTime() domain: bars.lua and the swing engine
-- compare against GetTime(). GetTimePreciseSec() (where present) ticks on a different
-- epoch, so its readings are converted ONCE into the GetTime() domain via a cached
-- offset. Raw precise time must never leave this wrapper.

do
	local precise = GetTimePreciseSec
	if type(precise) == "function" then
		local offset
		api.get_time = function()
			local precise_now = precise()
			if type(precise_now) ~= "number" then
				return GetTime()
			end
			if offset == nil then
				-- The offset between the two clocks is constant: learn it once on
				-- first use, with GetTime() as the reference domain.
				offset = GetTime() - precise_now
			end
			return precise_now + offset
		end
	elseif type(GetTime) == "function" then
		api.get_time = GetTime
	else
		-- Unknown client (offline harness): a constant clock keeps compares sane.
		api.get_time = function()
			return 0
		end
	end
end

--------------------------------------------------------------------------------
-- Per-family spell data helpers
--------------------------------------------------------------------------------

-- Resolves the candidate rank ids of a spell (mixed across expansions) down to the id
-- that exists on the running client, i.e. the current rank for this game family. Ids
-- from other expansions are absent from the client's spell data. Accepts either a
-- lookup table (st.utils.convert_lookup_table) or a plain list of ids; order does not
-- matter. Returns nil when none of the ids exist on this client.
function api.get_family_spell_id(id_table)
	local best
	for key, value in pairs(id_table) do
		local id
		if type(value) == "number" then
			id = value -- plain list of ids
		else
			id = key -- lookup table keyed by id
		end
		if api.GetSpellInfo(id) and (not best or id > best) then
			best = id
		end
	end
	return best
end
