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
--   st.api.*            : normalized wrappers for APIs that differ across clients
--
-- On clients where the original global function still exists, each wrapper is a direct
-- pass-through, so WotLK Classic (the regression baseline) behaves exactly as before.
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
-- Normalized API surface
--------------------------------------------------------------------------------

local api = {}
st.api = api

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
if IsSpellKnownOrOverridesKnown then
	spell_known_probes[#spell_known_probes + 1] = IsSpellKnownOrOverridesKnown
end
if IsSpellKnown then
	spell_known_probes[#spell_known_probes + 1] = IsSpellKnown
end
if IsPlayerSpell then
	spell_known_probes[#spell_known_probes + 1] = IsPlayerSpell
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

if GetSpellCooldown then
	api.GetSpellCooldown = GetSpellCooldown
elseif C_Spell and C_Spell.GetSpellCooldown then
	api.GetSpellCooldown = function(spell)
		local info = C_Spell.GetSpellCooldown(spell)
		if not info then
			return 0, 0, 0, 0
		end
		return info.startTime, info.duration, info.isEnabled and 1 or 0, info.modRate
	end
else
	api.GetSpellCooldown = function()
		return 0, 0, 0, 0
	end
end

-- Spell power costs ----------------------------------------------------------------------
-- Classic and retail both return an array of cost structs; entries have a .cost field.

if GetSpellPowerCost then
	api.GetSpellPowerCost = GetSpellPowerCost
elseif C_Spell and C_Spell.GetSpellPowerCost then
	api.GetSpellPowerCost = C_Spell.GetSpellPowerCost
else
	-- Unknown client: a zero-cost entry of the expected shape instead of an error.
	api.GetSpellPowerCost = function()
		return { { cost = 0, minCost = 0 } }
	end
end

-- Spell base cooldowns -------------------------------------------------------------------
-- Classic: GetSpellBaseCooldown(spell) returns the base cooldown in milliseconds.
-- Retail has no replacement; degrade to 0 rather than error.

if GetSpellBaseCooldown then
	api.GetSpellBaseCooldown = GetSpellBaseCooldown
else
	api.GetSpellBaseCooldown = function()
		return 0, 0
	end
end

-- Current spell --------------------------------------------------------------------------
-- Detects on-next-attack abilities queued for the current cast (Maul, Heroic Strike, ...).

if IsCurrentSpell then
	api.IsCurrentSpell = IsCurrentSpell
elseif C_Spell and C_Spell.IsCurrentSpell then
	api.IsCurrentSpell = C_Spell.IsCurrentSpell
else
	api.IsCurrentSpell = function()
		return false
	end
end

-- Auras ----------------------------------------------------------------------------------
-- Classic shape: UnitAura(unit, index, filter) returns
--   name, icon, count, dispelName, duration, expirationTime, sourceUnit, isStealable,
--   nameplateShowPersonal, spellId, ...
-- Retail shape:  C_UnitAuras.GetAuraDataByIndex returns an AuraData table. The field
-- order below matches Blizzard's own AuraUtil.UnpackAuraData back-compat mapping.

if UnitAura then
	api.UnitAura = UnitAura
elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
	api.UnitAura = function(unit, index, filter)
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
		if not aura then
			return nil
		end
		return aura.name, aura.icon, aura.applications, aura.dispelName,
			aura.duration, aura.expirationTime, aura.sourceUnit, aura.isStealable,
			aura.nameplateShowPersonal, aura.spellId
	end
else
	api.UnitAura = function()
		return nil
	end
end

-- Casting and channels -------------------------------------------------------------------
-- Pass-throughs (nil when the client lacks them). The payloads are NOT identical:
-- UnitCastingInfo returns castID before notInterruptible and the spell id 9th, while
-- UnitChannelInfo has no castID and returns the spell id 8th; callers must unpack each
-- accordingly.

api.UnitCastingInfo = UnitCastingInfo or function() return nil end
api.UnitChannelInfo = UnitChannelInfo or function() return nil end

-- Spell haste ----------------------------------------------------------------------------
-- UnitSpellHaste is the current global where available; GetSpellHaste is the older one.
-- Both return a percentage, or nil on clients that lack them.

api.UnitSpellHaste = UnitSpellHaste or function() return nil end
api.GetSpellHaste = GetSpellHaste or function() return nil end

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

if GetActiveTalentGroup then
	api.GetActiveTalentGroup = GetActiveTalentGroup
elseif C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
	api.GetActiveTalentGroup = C_SpecializationInfo.GetActiveSpecGroup
else
	api.GetActiveTalentGroup = function()
		return 1
	end
end

-- Shapeshift form index ------------------------------------------------------------------
-- Classic indices: 1=bear, 3=cat, 4=travel, 5=moonkin/tree/flight, 6=flight.
-- Other families index forms differently; form-dependent visual features will need
-- per-family data with the class modules.

if GetShapeshiftForm then
	api.GetShapeshiftForm = GetShapeshiftForm
elseif C_ShapeshiftForm and C_ShapeshiftForm.GetShapeshiftForm then
	api.GetShapeshiftForm = C_ShapeshiftForm.GetShapeshiftForm
else
	api.GetShapeshiftForm = function()
		return 0
	end
end

-- Weapon speeds --------------------------------------------------------------------------
-- Used to detect whether an offhand/ranged weapon exists.

if UnitAttackSpeed then
	api.UnitAttackSpeed = UnitAttackSpeed
else
	api.UnitAttackSpeed = function()
		return 0, 0
	end
end

if UnitRangedDamage then
	api.UnitRangedDamage = UnitRangedDamage
else
	api.UnitRangedDamage = function()
		return 0
	end
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
