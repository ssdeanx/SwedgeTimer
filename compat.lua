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
-- spell family. The probes exist on different client families; the first one that ANSWERS
-- wins (a probe that returns nil declines, and the chain moves on to the next probe).
--
-- CONTRACT (binary, never nil): api.is_spell_known answers true or false and nothing else.
--   true  = a probe answered "the player knows this spell".
--   false = a probe answered "the player does not know it" OR no probe could answer at all
--           (no probe on this client, or every probe declined).
-- A false is therefore NOT the claim "the client says the player does not know the spell":
-- on a client that cannot answer it is the fail-closed answer, not a fact about the player.
-- Every caller in the tree treats only true as affirmative knowledge (== true / ~= true),
-- so a false never turns a row on.
--
-- The two cases ARE told apart by api.is_spell_known_state below - the same shape as
-- api.get_family_spell_id_state (the answer first, the state string second): a caller that
-- must not guess (a row that hides when the client cannot answer) reads the state, never
-- the boolean alone.
--
-- Client note (wow-ui-source, per branch): C_SpellBook.IsSpellKnown is documented on every
-- targeted family (classic_era, classic_anniversary, classic_titan, forever, live) and
-- returns a bool; the classic global IsSpellKnown is Blizzard's deprecated shim over
-- C_SpellBook (Blizzard_DeprecatedSpellBook/Deprecated_SpellBook.lua) and exists only while
-- the loadDeprecationFallbacks CVar is on. So no targeted client is probe-less - the
-- no-probe branch below is the defensive path, not a shape the shipped matrix reaches.

local spell_known_probes = {}
-- IsSpellKnown is deprecated on modern clients, so resolve it dynamically; this both
-- dodges the deprecation annotation and tolerates clients that removed the global.
local classic_is_spell_known = rawget(_G, "IsSpellKnown")
if classic_is_spell_known then
	spell_known_probes[#spell_known_probes + 1] = classic_is_spell_known
end
-- C_SpellBook.IsSpellKnown (SpellBookDocumentation.lua: "Returns true if a player knows
-- a spell"; sibling IsSpellKnownOrInSpellBook beside it) is the probe on the
-- Mainline-code clients, where the global above is absent. NOTE: C_Spell.IsSpellKnown*
-- exists on NO client (absent on era/anniversary/titan/forever/live alike) - the live
-- namespace is C_SpellBook, so nothing probes C_Spell here. Appended after the global
-- on purpose: a client whose chain already answers (the classic clients, with
-- Blizzard's deprecation fallbacks loaded) keeps the exact same answer source, so
-- nothing changes there.
local spell_book_api = rawget(_G, "C_SpellBook")
if spell_book_api then
	if spell_book_api.IsSpellKnown then
		spell_known_probes[#spell_known_probes + 1] = spell_book_api.IsSpellKnown
	end
	if spell_book_api.IsSpellKnownOrInSpellBook then
		spell_known_probes[#spell_known_probes + 1] = spell_book_api.IsSpellKnownOrInSpellBook
	end
end

-- A spell NAME is not a probe argument on the modern clients. TBC Anniversary's
-- IsSpellKnown global is Blizzard's deprecated shim
-- (Blizzard_DeprecatedSpellBook/Deprecated_SpellBook.lua), which forwards its argument
-- to C_SpellBook.IsSpellInSpellBook - an id-only API that throws on a string:
-- "bad argument #1 to 'IsSpellInSpellBook' (outside of expected range ...)",
-- operator in-client BugGrabber evidence 2026-10-21 (hunter post_init, "Kill Shot").
-- The caller's token is therefore probed AS GIVEN first: on the clients where a name is
-- the query form (operator-confirmed name-vs-id rule) that keeps the exact answer source.
-- Only a THROWING probe triggers the one-time name -> id resolution through the ONE compat
-- spell-info path above (api.GetSpellInfo; its 7th return is the id) - no second
-- resolution path - after which the same probe is retried with the id. A name that
-- resolves to nothing is "unknown": never a guess, never a throw.
local function spell_known_name_id(spell_name)
	if type(spell_name) ~= "string" then
		return nil
	end
	local ok, _, _, _, _, _, _, id = pcall(api.GetSpellInfo, spell_name)
	if not ok or is_secret(id) or type(id) ~= "number" then
		return nil
	end
	return id
end

-- The state variant of the probe - the tri-state the boolean above folds away:
--   true,  "known"      a probe answered true
--   false, "not_known"  a probe answered false
--   false, "unknown"    no probe answered - the client cannot answer the question,
--                       or the token did not resolve to a spell id at all
-- Same contract as api.get_family_spell_id_state: the answer first, the state second.
-- Every probe call is pcall-wrapped: a probe that throws is "no answer" (the chain
-- moves on), so a client-side throw costs the answer, never the caller's init. The
-- probe order is unchanged (classic global first, C_SpellBook probes after it).
function api.is_spell_known_state(spell_id)
	-- Neither a spell id nor a spell name can be a probe argument: fail closed before any
	-- client call. pcall would contain the throw, but there is nothing to resolve either.
	if type(spell_id) ~= "number" and type(spell_id) ~= "string" then
		return false, "unknown"
	end
	local fallback_id
	local fallback_ready = false
	for i = 1, #spell_known_probes do
		local ok, known = pcall(spell_known_probes[i], spell_id)
		if not ok then
			if not fallback_ready then
				fallback_id = spell_known_name_id(spell_id)
				fallback_ready = true
			end
			if fallback_id ~= nil then
				ok, known = pcall(spell_known_probes[i], fallback_id)
			end
		end
		if ok and not is_secret(known) then
			if known == true then
				return true, "known"
			end
			if known ~= nil then
				return false, "not_known"
			end
		end
	end
	return false, "unknown"
end

-- The boolean form: the answer half of the state above, unchanged for every caller
-- (true / false, never nil).
function api.is_spell_known(spell_id)
	local known = api.is_spell_known_state(spell_id)
	return known
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

-- Unit aura scan: the player scan above, generalised to any unit and to either
--   aura list. duration_remaining_seconds, stacks = api.scan_unit_aura(unit, predicate, filter)
-- CONTRACT (the same three-way contract as the player scan above - a caller
-- reads nil as "unknown", never as "absent"):
--   * predicate(spell_id, name, stacks) returns truthy for a match; the first
--     match wins. The arguments are exactly the ones the player scan hands
--     over, in the same order: spell_id can be nil on a client without numeric
--     ids (an id comparison already treats that safely - compare the name
--     first when a client resolves by name), and the third argument is the raw
--     count on the wrapper's convention.
--   * filter selects the aura list: "HARMFUL" (the default - a debuff scan) or
--     "HELPFUL" (a buff scan). Any other value falls back to the debuff
--     filter, so a typo can never silently scan the wrong list.
--   * returns nil, nil when not found, when the unit carries no readable aura,
--     when no aura API exists on the client, when the unit is not a usable
--     unit string, or when the predicate is not a function. Callers must treat
--     nil as "unknown", never as "absent" - a target debuff that could not be
--     read is not a target without that debuff.
--   * the row cap, the no-early-break rule, the api.get_time() axis and the
--     whole-entry secret degrade are the player scan's, unchanged: a restricted
--     row reads absent and the walk continues past it, so a restricted list
--     still reports the match that sits below it.
-- Family paths, all through this file's own wrappers: the classic global on
-- Era/TBC/Wrath and the C_UnitAuras read on the Mainline-code clients.
function api.scan_unit_aura(unit, predicate, filter)
	if type(predicate) ~= "function" then
		return nil, nil
	end
	if type(unit) ~= "string" or unit == "" then
		return nil, nil
	end
	if filter ~= "HELPFUL" then
		filter = "HARMFUL"
	end
	local now = api.get_time()
	for index = 1, scan_player_aura_index_max do
		local name, _, count, _, _, expiration, _, _, _, spell_id = api.UnitAura(
			unit, index, filter)
		-- No early break (R2), same as the player scan above: nil is simply no
		-- match at this index. The 40-row cap bounds the walk, so the worst-case
		-- cost is the same 40 UnitAura calls as the player scan.
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
-- naming it directly would be an undefined-global reference. NOTE: there is no
-- C_ShapeshiftForm namespace on any client (absent on era/anniversary/titan/forever/live
-- alike), so no C_ branch is probed here: the bare global answers on the classic-line
-- clients (engine-provided there - RestrictedEnvironment.lua allowlists it on
-- era/anniversary/titan), and every other client reports 0 (unknown form).
local get_shapeshift_form = _G.GetShapeshiftForm

if get_shapeshift_form then
	api.GetShapeshiftForm = get_shapeshift_form
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

-- Interaction distance: REMOVED, deliberately.
-- The client's interaction-distance checker is a protected function on TBC Anniversary
-- 2.5.x: every call raises ADDON_ACTION_BLOCKED (operator in-client BugGrabber evidence,
-- 2026-10-21, hunter range helper on every frame - the error took the whole class hook
-- down through guard.run's quarantine). The standing operator policy is ZERO client
-- range calls on every family, so this module exposes no interaction-distance wrapper
-- at all - not even a nil-returning stub, which would hide why the call is gone.
-- api.UnitDistance below is the only distance source: exact yards, pcall-wrapped,
-- probed per family, nil when the client cannot answer.
--
-- Provenance (wow-ui-source branch classic_anniversary): the only Blizzard caller is
-- secure popup code (Interface/AddOns/Blizzard_UnitPopupShared/UnitPopupSharedUtils.lua:194);
-- the generated API doc
-- (Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua:101) lists the function
-- with NO protection marker, so the protection is runtime/client-side and the in-client log
-- above - not the doc - is the authority. The addon-callable source is UnitDistanceSquared,
-- called from ordinary insecure unit-frame Lua
-- (Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua:1069) and trusted only
-- when checkedDistance is true; api.UnitDistance below normalises exactly that.
-- Evidence: bench/compat_tbc_defects_2026-10-21.md.

-- Unit distance (exact) ------------------------------------------------------------------
-- UnitDistanceSquared(unit) returns the distance in squared yards plus a boolean saying
-- whether the distance was actually checked; Blizzard's own consumer
-- (Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua:1069,
-- classic_anniversary) only trusts the reading when checkedDistance is true - and it calls
-- this from ordinary insecure unit-frame Lua, which is what makes it addon-callable.
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

-- Movement speed and motion (hunter melee-weave prog) ------------------------------------
-- GetUnitSpeed(unit) answers the unit's current movement speed in yards per second as its
-- first return (current, run, flight, swim on every family that exposes the global; the
-- classic-era PaperDoll stat frame destructures the same four returns). Read through _G:
-- the global is absent from some clients' annotation sets, where naming it directly would
-- be an undefined-global reference. A client without the global, a throwing call, a
-- non-number / NaN / infinite / negative reading and a restricted (secret) reading all
-- report nil; callers must treat nil as unknown speed, never as standing still.
local get_unit_speed = rawget(_G, "GetUnitSpeed")

function api.GetUnitSpeed(unit)
	if not get_unit_speed then
		return nil
	end
	local ok, current = pcall(get_unit_speed, unit)
	if not ok or is_secret(current) then
		return nil
	end
	if type(current) ~= "number" or current ~= current or current < 0
		or current == math.huge then
		return nil
	end
	return current
end

-- IsPlayerMoving() answers whether the player is moving (the WA prog's motion leg;
-- present on every supported family). Read through _G for the same undefined-global
-- reason. No probe, a throwing call, a non-boolean or a restricted (secret) reading all
-- report nil; callers must treat nil as unknown motion, never as standing still.
local is_player_moving = rawget(_G, "IsPlayerMoving")

function api.IsPlayerMoving()
	if not is_player_moving then
		return nil
	end
	local ok, moving = pcall(is_player_moving)
	if not ok or is_secret(moving) then
		return nil
	end
	if type(moving) ~= "boolean" then
		return nil
	end
	return moving
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

-- Equipped-item probe: does the player wear a given item id right now?
--   equipped = api.is_item_equipped(item_id)
-- CONTRACT (tri-state, because "unknown" is not "not equipped"):
--   * true  - an equipped slot holds exactly that item id.
--   * false - the equipment read worked and no equipped slot holds that id.
--   * nil   - the read is unavailable (no GetInventoryItemID on this client) or
--     secret (a restricted reading), or the client does not define the
--     INVSLOT_* slot range, or the id is not a number. Unknown is never
--     reported as false: a caller that read false as "not equipped" would act
--     on a guess about the player's gear.
-- The read goes through api.GetInventoryItemID above, so the unit fix ("player"),
-- the absent-global guard and the secret degrade are the wrapper's, not this
-- function's. An empty slot reads nil in that wrapper (the client's own code
-- reads it the same way - Blizzard_FrameXML/Wrath/EquipmentManager.lua:172,
-- "Slot was empty already"), so a slot that holds nothing is not evidence of
-- anything.
--
-- The slot range is the client's own: INVSLOT_FIRST_EQUIPPED ..
-- INVSLOT_LAST_EQUIPPED is 1..19 (INVSLOT_HEAD .. INVSLOT_TABARD) on every
-- client family - classic_era / classic_anniversary / classic_titan
-- :Interface/AddOns/Blizzard_FrameXMLBase/Classic/Constants.lua:173,192,
-- origin/forever :Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:136,155,
-- live :Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:153,172. They are
-- read through _G: they are not in the annotation set of Mainline-code clients,
-- where naming them directly would be an undefined-global reference, and a
-- client that does not define them reports nil (unknown), never false.
function api.is_item_equipped(item_id)
	if type(item_id) ~= "number" then
		return nil
	end
	local first_slot = rawget(_G, "INVSLOT_FIRST_EQUIPPED")
	local last_slot = rawget(_G, "INVSLOT_LAST_EQUIPPED")
	if type(first_slot) ~= "number" or type(last_slot) ~= "number" then
		return nil
	end
	if last_slot < first_slot then
		return nil
	end
	-- One readable slot is what makes the read "readable": a slot that holds
	-- nothing and a restricted reading are both nil, so a client that reports
	-- no equipped id at all answers "unknown" instead of guessing "not equipped".
	local readable = false
	for slot = first_slot, last_slot do
		local equipped_id = api.GetInventoryItemID(slot)
		if equipped_id ~= nil then
			readable = true
			if equipped_id == item_id then
				return true
			end
		end
	end
	if not readable then
		return nil
	end
	return false
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
-- above reads, AND gated on the family: Blizzard's deprecation shim
-- (Blizzard_DeprecatedCombatLog/Deprecated_CombatLog.lua, loadDeprecationFallbacks-gated,
-- identical on every family) can define that global on Mainline-code clients too, where
-- no classic combat log runs behind it - presence alone would arm the chains on
-- Retail/WoW Forever. Consumers gate on this flag, never on st.is_mainline
-- alone (Forever runs Mainline code but keeps its own swing engine).
st.cleu_supported = get_combat_log_event_info ~= nil and not st.is_mainline

-- Totems -----------------------------------------------------------------------------------
-- GetTotemInfo(slot) reports the totem in a slot:
--   haveTotem, totemName, startTime, duration, icon, modRate, spellID
-- or nothing at all when the slot holds no totem (MayReturnNothing). Slots are
-- 1=Fire, 2=Earth, 3=Water, 4=Air (the client's own slot constants: on the classic-line
-- families Interface/AddOns/Blizzard_FrameXMLBase/Classic/Constants.lua:286-289,
-- origin/forever Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:226-229,
-- live Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:241-244 - FIRE_TOTEM_SLOT = 1;
-- EARTH_TOTEM_SLOT = 2; WATER_TOTEM_SLOT = 3; AIR_TOTEM_SLOT = 4; identical values on every
-- branch). Those constants are EVIDENCE only, never a runtime dependency: the addon
-- hard-codes 1/2/3/4 (classes/shaman.lua:226-231), and on WoW Forever they are not even
-- defined as globals - that branch loads its Constants.lua only for the mainline game type
-- (Blizzard_FrameXMLBase.toc:18), and the camelot game type loads Camelot/Constants.lua
-- (toc:16), which defines no totem slots. The startTime is on the GetTime() axis, the
-- same domain api.get_time() reports, so a caller can adopt it as a drop stamp directly.
-- On Mainline-code clients the slot can be secret (SecretWhenTotemSlotSecret - the
-- annotation is on origin/forever and live, not on the classic-line branches): one
-- restricted field degrades the whole read to nil (absent), the shape every caller
-- already handles - the same whole-or-nothing rule as the aura entries above. A client
-- without the global, a throwing call and a bad slot all report nil; callers must treat
-- nil as unknown, never as "no totem". Read through _G and pcall-wrapped: the global is
-- absent on some clients and MayReturnNothing means any slot can come back empty.

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

-- Item probes (items, Thistle Tea) --------------------------------------------------------
-- The classic globals and the C_Item namespace document the same shapes on every supported
-- family (ItemDocumentation.lua: C_Item.GetItemInfo returns the classic multi-return;
-- C_Item.GetItemCount / C_Item.GetItemCooldown the classic count and cooldown triple), so
-- the C_Item form is preferred where it is callable and the global is the fallback - a
-- modern client whose deprecated globals are not loaded still answers. All reads are
-- pcall-wrapped (a cold item database can throw) and a restricted (secret) reading
-- degrades to the documented "unknown" shape; callers must never read unknown as a real
-- item reading.

local item_info_probe, item_count_probe, item_cooldown_probe
do
	local c_item = rawget(_G, "C_Item")
	if type(c_item) == "table" then
		if type(c_item.GetItemInfo) == "function" then
			item_info_probe = c_item.GetItemInfo
		end
		if type(c_item.GetItemCount) == "function" then
			item_count_probe = c_item.GetItemCount
		end
		if type(c_item.GetItemCooldown) == "function" then
			item_cooldown_probe = c_item.GetItemCooldown
		end
	end
	item_info_probe = item_info_probe or rawget(_G, "GetItemInfo")
	item_count_probe = item_count_probe or rawget(_G, "GetItemCount")
	item_cooldown_probe = item_cooldown_probe or rawget(_G, "GetItemCooldown")
end

-- Item info: the classic leading block (name, link, quality, level, minLevel, and the
-- item's type and subtype).
--
-- CONTRACT (one shape, whatever probe answered): api.GetItemInfo returns
--   name, link, quality, level, min_level, item_type, item_sub_type
-- where position 6 is the item's TYPE string and position 7 the item's SUBTYPE string.
-- The two probe shapes put the same two strings in those positions but NAME them
-- differently, so this wrapper normalises the names:
--   * the preferred probe C_Item.GetItemInfo returns them as itemType / itemSubType
--     (ItemDocumentation.lua:621-622 on live, :409-410 on the classic-line branches,
--     :643-644 on origin/forever; the same multi-return is visible in Blizzard's own
--     code at Interface/AddOns/Blizzard_ItemButton/Shared/ItemButtonTemplate.lua:187 on
--     all five branches);
--   * the classic global GetItemInfo (the fallback) calls the same two values class and
--     subclass - the classic C API, which has no Lua definition and no FrameXML call
--     site on any branch, so that naming is the addon's own recorded model.
-- A table-shaped read (defensive; the documented clients return the multi-return) is
-- unfolded to the same positions. No probe, a throwing call, a missing name and any
-- secret field all report nil - callers must treat nil as "cannot tell", never as "not a
-- weapon".
function api.GetItemInfo(item)
	if not item_info_probe then
		return nil
	end
	local ok, name, link, quality, level, min_level, item_type, item_sub_type =
		pcall(item_info_probe, item)
	if not ok or name == nil or is_secret(name) then
		return nil
	end
	if type(name) == "table" then
		local info = name
		if is_secret(info.itemName) or is_secret(info.itemType)
			or is_secret(info.itemSubType) then
			return nil
		end
		return info.itemName, info.itemLink, info.itemQuality, info.itemLevel,
			info.itemMinLevel, info.itemType, info.itemSubType
	end
	if is_secret(link) or is_secret(quality) or is_secret(level) or is_secret(min_level)
		or is_secret(item_type) or is_secret(item_sub_type) then
		return nil
	end
	return name, link, quality, level, min_level, item_type, item_sub_type
end

-- Item count: the classic count, or nil when the client cannot answer (no probe, a
-- throwing call, a restricted reading). Callers must treat nil as unknown, never zero.
function api.GetItemCount(item)
	if not item_count_probe then
		return nil
	end
	local ok, count = pcall(item_count_probe, item)
	if not ok or is_secret(count) or type(count) ~= "number" then
		return nil
	end
	return count
end

-- Item cooldown, normalised to the classic (start, duration, enabled) triple. A client
-- without the probe and a restricted reading both report the idle shape (0, 0, 0) - the
-- shape every consumer already treats as "no cooldown".
function api.GetItemCooldown(item)
	if not item_cooldown_probe then
		return 0, 0, 0
	end
	local ok, start_time, duration, enabled = pcall(item_cooldown_probe, item)
	if not ok or is_secret(start_time) or is_secret(duration) or is_secret(enabled) then
		return 0, 0, 0
	end
	return start_time or 0, duration or 0, enabled or 0
end

-- Weapon enchant presence (poison reminder) ----------------------------------------------
-- GetWeaponEnchantInfo() reports four values per weapon slot:
--   hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID,
--   hasOffHandEnchant, ... (Blizzard's own consumers read hasOffHandEnchant at position 5:
-- SecureGroupHeaders.lua; groups of four: BuffFrame.lua RETURNS_PER_ITEM and the retail
-- Deprecated_12_1_0 shim). The wrapper normalises every family to the two presence
-- booleans a caller needs - has_mainhand, has_offhand. No probe, a throwing call, a
-- non-boolean presence and any restricted (secret) field all report nil, nil - callers
-- must treat nil as unknown, never as "no poison".
local get_weapon_enchant_info = rawget(_G, "GetWeaponEnchantInfo")

function api.GetWeaponEnchantInfo()
	if not get_weapon_enchant_info then
		return nil, nil
	end
	local ok, has_main, _, _, _, has_off = pcall(get_weapon_enchant_info)
	if not ok or is_secret(has_main) or is_secret(has_off) then
		return nil, nil
	end
	if type(has_main) ~= "boolean" or type(has_off) ~= "boolean" then
		return nil, nil
	end
	return has_main, has_off
end

-- Unit identity --------------------------------------------------------------------------
-- UnitGUID(unit) exists on every supported client; read through _G for the same
-- undefined-global reason as above. No probe, a throwing call, a restricted (secret)
-- reading and a non-string value all report nil (unknown identity) - callers must treat
-- nil as "no unit", never as a stable identity to baseline against.
local legacy_unit_guid = rawget(_G, "UnitGUID")

function api.UnitGUID(unit)
	if not legacy_unit_guid then
		return nil
	end
	local ok, guid = pcall(legacy_unit_guid, unit)
	if not ok or is_secret(guid) or type(guid) ~= "string" then
		return nil
	end
	return guid
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

-- The client's own name for a spell id.
--
-- Name-vs-id rule (operator-confirmed 2026-10-19; bench/lessons.md:29-32): the TBC
-- Anniversary client resolves spells by NAME, never by a bare id; Classic Era resolves
-- by id. The name for a candidate id therefore has to come out of the client's own
-- spell data first, because the id form is exactly the form the TBC client does not
-- answer. Two sources, in order:
--
--  1. The native global's id form. On the classic-line clients the global returns the
--     spell name as its first value, and Blizzard's own code reads it that way:
--     classic_anniversary:Interface/AddOns/Blizzard_ObjectAPI/Classic/Spell.lua:39
--     ("return (GetSpellInfo(self:GetSpellID()))" - the spell book's canonical name
--     accessor, loaded through Blizzard_ObjectAPI_Classic.toc, which carries
--     "## AllowLoadGameType: classic").
--  2. The C_Spell namespace, which accepts a spell ID on EVERY branch:
--     classic_era / classic_anniversary / classic_titan
--     :Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua:190-197,
--     origin/forever :...:416-424, live :...:375-383 - the argument is documented as
--     "Spell ID, name, name(subtext), or link" and the answer is a SpellInfo structure
--     whose `name` field is a non-nilable string (.../SpellDocumentation.lua:782-786 on
--     the three classic branches, :1183-1187 on forever, :1109-1113 on live). This is
--     the source that still answers when the global only answers names.
--
-- Both sources read the client's SPELL DATABASE, not the player's spell book - the
-- client documents that split itself: "Returns true if the spell exists, regardless of
-- whether the player has learned it" (DoesSpellExist,
-- classic_anniversary / classic_era :.../SpellDocumentation.lua:21-23). That is why a
-- rank resolved here cannot be lost to a cold book: the answer never depended on the
-- book in the first place.
--
-- Return shape: the name (string) when the client knows the id, nil when it cannot
-- name it (no such spell on this client, or a client that cannot answer).
local function client_spell_name(id)
	local ok, name = pcall(api.GetSpellInfo, id)
	if not ok or is_secret(name) then
		return nil -- the client could not answer, or the answer is restricted
	end
	if type(name) == "string" then
		return name
	end
	if spell_api and spell_api.GetSpellInfo then
		local bridge_ok, info = pcall(spell_api.GetSpellInfo, id)
		if not bridge_ok or is_secret(info) then
			return nil
		end
		if type(info) == "table" and type(info.name) == "string" and not is_secret(info.name) then
			return info.name
		end
	end
	return nil
end

-- One spell-data answer, reduced to what the walk needs:
--   true  - the client answered with this spell's data
--   false - the client answered "not found"
--   nil   - the call threw, or the answer was restricted (secret): a restricted
--           value is never compared, because comparison with one raises in-client.
local function spell_data_present(ok, value)
	if not ok or is_secret(value) then
		return nil
	end
	if value == nil then
		return false
	end
	return true
end

-- Family-correct existence probe for one candidate id.
--   true  - the client confirmed the spell exists on this client
--   false - the client's own spell data refutes it (definitive absence)
--   nil   - the client could not answer either way (cold or unreadable client)
local function family_spell_exists(id)
	if st.family ~= "TBC" then
		local ok, info = pcall(api.GetSpellInfo, id)
		return spell_data_present(ok, info)
	end
	-- TBC: the name path is the query form (operator rule). The name comes from the
	-- client's own data; a name the client does not index falls back to the id form,
	-- so a client whose global answers ids still resolves here too.
	local name = client_spell_name(id)
	local query = api.get_spell_query(name, id) or id
	local ok, info = pcall(api.GetSpellInfo, query)
	local present = spell_data_present(ok, info)
	if present == true then
		return true
	end
	if present == nil then
		return nil
	end
	if query ~= id then
		local id_ok, id_info = pcall(api.GetSpellInfo, id)
		local id_present = spell_data_present(id_ok, id_info)
		if id_present == true then
			return true
		end
		if id_present == nil then
			return nil
		end
	end
	return false
end

-- Resolves the candidate rank ids of a spell (mixed across expansions) down to the id
-- that exists on the running client, i.e. the current rank for this game family. Ids
-- from other expansions are absent from the client's spell data. Accepts either a
-- lookup table (st.utils.convert_lookup_table) or a plain list of ids; order does not
-- matter. Returns nil when none of the ids exist on this client.
--
-- Name-vs-id rule: on TBC the walk asks the client by NAME (the id form is what that
-- client does not answer - bench/lessons.md:29-32), so a rank the client knows
-- resolves there exactly as it does on Era. The state variant below tells "the client
-- says this spell is not here" apart from "the client could not answer", so a caller
-- that latches a negative can tell the two apart and retry instead of caching a false
-- negative.
function api.get_family_spell_id_state(id_table)
	local best
	local refuted = false
	local unknown = false
	local candidates = 0
	for key, value in pairs(id_table) do
		local id
		if type(value) == "number" then
			id = value -- plain list of ids
		else
			id = key -- lookup table keyed by id
		end
		if type(id) == "number" then
			candidates = candidates + 1
			local exists = family_spell_exists(id)
			if exists == true then
				if not best or id > best then
					best = id
				end
			elseif exists == false then
				refuted = true
			else
				unknown = true
			end
		end
	end
	if best then
		return best, "resolved"
	end
	if unknown then
		return nil, "unresolved"
	end
	if refuted or candidates == 0 then
		return nil, "absent"
	end
	return nil, "unresolved"
end

function api.get_family_spell_id(id_table)
	local id = api.get_family_spell_id_state(id_table)
	return id
end

-- Spell query (name-vs-id rule, operator-confirmed 2026-10-19): TBC Anniversary
-- takes spell NAMES, never bare ids; Classic Era needs ids. Returns the
-- family-correct query for GetSpellCooldown / is_spell_known / IsSpellUsable /
-- aura matching: the English name on TBC, the numeric id elsewhere. Callers pass
-- both from their resolved entry; the helper picks. No new client probe, family
-- branching only.
function api.get_spell_query(name, id)
	if st.family == "TBC" then
		return name
	end
	return id
end
