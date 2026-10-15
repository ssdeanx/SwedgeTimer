--=========================================================================================
-- Cross-client compatibility layer.
--
-- SwedgeTimer ships one build for every WoW client family (Classic Era, TBC, Wrath,
-- Cata, Mists, Retail, plus legacy/private clients). This is the single place where
-- client API differences are handled.
--
-- Sets:
--   st.family           : "ERA" | "TBC" | "WRATH" | "CATA" | "MISTS" | "RETAIL" | "UNKNOWN"
--   st.interface_number : the running client's TOC interface version, when knowable
--   st.is_retail        : true on Mainline/Retail clients
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
		if major == 1 then
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

-- Talents --------------------------------------------------------------------------------
-- Classic (Era/TBC/Wrath/Cata): GetTalentInfo(tab, index) returns
--   name, icon, tier, column, rank, maxRank, ...
-- Mists and Retail use different talent systems. The fallback reports rank 0 so that
-- "has talent" checks all evaluate to false instead of erroring.

if GetTalentInfo then
	api.GetTalentInfo = GetTalentInfo
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
