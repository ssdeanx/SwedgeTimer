-- P3 smoke test: family-safe class data.
-- Verifies compat.lua family detection, the talent-info mapping, the family spell-id
-- resolver, and the warrior/druid rage-cost paths under simulated client profiles.
-- Plain Lua 5.1, no WoW client needed. Run from the repo root: lua5.1 tests/smoke.lua
-- (the repo root is derived from this script's own location, so any cwd works).

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if cond then
        print("ok   " .. label)
    else
        failures = failures + 1
        print("FAIL " .. label)
    end
end
local function eq(got, want, label)
    check(got == want, string.format("%s (got %s, want %s)", label, tostring(got), tostring(want)))
end

-- ---------------------------------------------------------------------------
-- Client profile builder
-- ---------------------------------------------------------------------------

-- opts: project (WOW_PROJECT_ID or nil), interface (TOC fallback), globals (extra
-- environment entries), ST (addon table for module tests), module (path to load
-- after compat.lua).
local function build_profile(opts)
    local env = setmetatable({}, { __index = _G })
    env.WOW_PROJECT_ID = opts.project
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    if opts.interface then
        env.GetBuildInfo = function() return "0.0.0", "00000", "today", opts.interface end
    end
    for k, v in pairs(opts.globals or {}) do
        env[k] = v
    end
    local st = {}
    st.utils = {
        -- Same contract as utils.lua's convert_lookup_table.
        convert_lookup_table = function(list)
            local tab = {}
            for i = 1, #list do tab[list[i]] = true end
            return tab
        end,
    }
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    compat("SwedgeTimer", st)
    if opts.module then
        env.LibStub = function(major)
            if major == "AceAddon-3.0" then
                return { GetAddon = function() return opts.ST end }
            end
            return {}
        end
        local mod = assert(loadfile(ROOT .. opts.module))
        setfenv(mod, env)
        mod("SwedgeTimer", st)
    end
    return env, st
end

local function spell_table(ids)
    local known = {}
    for i = 1, #ids do known[ids[i]] = true end
    return function(id)
        if known[id] then return "Spell " .. tostring(id), nil, 1, 0, 0, 0, id end
        return nil
    end
end

local function aura_stub(ids)
    return function(unit, index)
        local id = ids[index]
        if not id then return nil end
        return "Aura " .. tostring(id), nil, nil, nil, nil, nil, nil, nil, nil, id
    end
end

-- Rank lists as they appear in the addon, split by what each client family knows.
local ALL_RANKS = {
    47450, 47449, 30324, 29707, 25286, 11567, 11566, 11565, 11564, 1608, 285, 284, 78,
    47520, 47519, 25231, 20569, 11609, 11608, 7369, 845,
    6807, 6808, 6809, 8972, 9745, 9880, 9881, 26996, 48479, 48480,
}
local ERA_RANKS = {
    25286, 11567, 11566, 11565, 11564, 1608, 285, 284, 78,
    25231, 20569, 11609, 11608, 7369, 845,
    9881, 9880, 9745, 8972, 6809, 6808, 6807,
}
local TBC_RANKS = {
    29707, 25286, 11567, 11566, 11565, 11564, 1608, 285, 284, 78,
    25231, 20569, 11609, 11608, 7369, 845,
    26996, 9881, 9880, 9745, 8972, 6809, 6808, 6807,
}

-- ---------------------------------------------------------------------------
-- Wrath client (regression baseline): pass-throughs, highest rank wins
-- ---------------------------------------------------------------------------
do
    local gti = function() return "talent", 1, 1, 1, 1, 1 end
    local gspc = function() return { { cost = 15 } } end
    local env, st = build_profile({
        project = 11,
        globals = {
            GetSpellInfo = spell_table(ALL_RANKS),
            GetTalentInfo = gti,
            GetSpellPowerCost = gspc,
            -- present but must lose to the global
            C_SpecializationInfo = { GetTalentInfo = function() error("must use the global") end },
        },
    })
    eq(st.family, "WRATH", "wrath: family")
    eq(st.is_retail, false, "wrath: not retail")
    eq(st.gcd_probe_spell_id, 29515, "wrath: gcd probe is 29515")
    check(st.api.GetSpellInfo == env.GetSpellInfo, "wrath: GetSpellInfo pass-through")
    check(st.api.GetTalentInfo == gti, "wrath: GetTalentInfo prefers the global")
    check(st.api.GetSpellPowerCost == gspc, "wrath: GetSpellPowerCost pass-through")
    eq(st.api.get_family_spell_id({78, 47450, 25286}), 47450, "wrath: HS resolves to 47450")
    eq(st.api.get_family_spell_id({6807, 9881, 48480, 26996}), 48480, "wrath: Maul resolves to 48480")
    eq(st.api.get_family_spell_id({47520, 845}), 47520, "wrath: Cleave resolves to 47520")
    eq(st.api.get_family_spell_id({ [78] = true, [47450] = true, [25286] = true }), 47450,
        "wrath: lookup-table form resolves to 47450")
end

-- ---------------------------------------------------------------------------
-- Era client: no global talent API, C_* namespaces present
-- ---------------------------------------------------------------------------
do
    local queried
    local _, st = build_profile({
        project = 2,
        globals = {
            GetSpellInfo = spell_table(ERA_RANKS),
            GetSpellPowerCost = function() return { { cost = 10 } } end,
            C_SpecializationInfo = {
                GetTalentInfo = function(query)
                    queried = query
                    if query.talentIndex == 99 then return nil end
                    return { name = "Moonkin Form", icon = 1, tier = 7, column = 1, rank = 1, maxRank = 1 }
                end,
            },
            C_Spell = {
                GetSpellCooldown = function(id)
                    if id == 29515 then return { startTime = 5, duration = 1.5, isEnabled = true, modRate = 1 } end
                    return nil
                end,
            },
        },
    })
    eq(st.family, "ERA", "era: family")
    eq(st.is_retail, false, "era: not retail")
    eq(st.gcd_probe_spell_id, 29515, "era: gcd probe is 29515")
    local name, _, _, _, rank = st.api.GetTalentInfo(1, 11)
    eq(name, "Moonkin Form", "era: talent name via C_SpecializationInfo")
    eq(rank, 1, "era: talent rank is the 5th return")
    eq(queried.specializationIndex, 1, "era: query.specializationIndex")
    eq(queried.talentIndex, 11, "era: query.talentIndex")
    local a, b, c, d, e = st.api.GetTalentInfo(1, 99)
    check(a == nil and b == nil and c == nil and d == nil and e == 0,
        "era: unknown talent -> nil,nil,nil,nil,0")
    local s, dur, en = st.api.GetSpellCooldown(29515)
    eq(s, 5, "era: cooldown start via C_Spell")
    eq(dur, 1.5, "era: cooldown duration via C_Spell")
    eq(en, 1, "era: enabled mapped to numeric 1")
    eq(st.api.GetActiveTalentGroup(), 1, "era: single-spec fallback returns 1")
    eq(st.api.get_family_spell_id({47450, 30324, 29707, 25286, 78}), 25286, "era: HS resolves to 25286")
    eq(st.api.get_family_spell_id({48480, 48479, 26996, 9881}), 9881, "era: Maul resolves to 9881")
    eq(st.api.get_family_spell_id({48480, 26996}), nil, "era: ids absent from this client -> nil")
end

-- ---------------------------------------------------------------------------
-- Legacy/private client: no WOW_PROJECT_ID, TOC fallback only
-- ---------------------------------------------------------------------------
do
    local _, st = build_profile({
        project = nil,
        interface = 20506,
        globals = { GetSpellInfo = spell_table(TBC_RANKS) },
    })
    eq(st.family, "TBC", "legacy 20506: family falls back to TBC")
    eq(st.interface_number, 20506, "legacy 20506: interface number recorded")
    eq(st.gcd_probe_spell_id, 29515, "legacy 20506: gcd probe is 29515")
    eq(st.api.get_family_spell_id({48480, 26996, 9881}), 26996, "legacy 20506: Maul resolves to 26996")
    eq(st.api.get_family_spell_id({47450, 30324, 29707, 25286}), 29707, "legacy 20506: HS resolves to 29707")
end

-- ---------------------------------------------------------------------------
-- Retail client: C_* wrappers and the modern GCD probe
-- ---------------------------------------------------------------------------
do
    local _, st = build_profile({
        project = 1,
        globals = {
            C_Spell = {
                GetSpellInfo = function(id)
                    if id == 61304 then
                        return {
                            name = "Global Cooldown", originalIconID = 5, castTime = 0,
                            minRange = 0, maxRange = 0, spellID = id,
                        }
                    end
                    return nil
                end,
                GetSpellCooldown = function(id)
                    if id == 61304 then
                        return { startTime = 1, duration = 1.5, isEnabled = true, modRate = 1 }
                    end
                    return nil
                end,
                GetSpellPowerCost = function() return { { cost = 0 } } end,
                IsCurrentSpell = function() return false end,
            },
            C_SpecializationInfo = {
                GetTalentInfo = function() return nil end,
                GetActiveSpecGroup = function() return 2 end,
            },
        },
    })
    eq(st.family, "RETAIL", "retail: family")
    eq(st.is_retail, true, "retail: is_retail")
    eq(st.is_mainline, true, "retail: mainline-code client")
    eq(st.gcd_probe_spell_id, 61304, "retail: gcd probe is 61304")
    local name, _, _, cast_time = st.api.GetSpellInfo(61304)
    eq(name, "Global Cooldown", "retail: GetSpellInfo via C_Spell")
    eq(cast_time, 0, "retail: castTime sits at position 4")
    local a, _, _, _, e = st.api.GetTalentInfo(1, 1)
    check(a == nil and e == 0, "retail: talent fallback -> placeholder rank 0")
    eq(st.api.GetActiveTalentGroup(), 2, "retail: active spec group via C_SpecializationInfo")
    eq(st.api.get_family_spell_id({29515, 61304}), 61304, "retail: id resolution still works")
end

-- ---------------------------------------------------------------------------
-- WoW Forever (Mainline-code client, project 18): no swing engine
-- ---------------------------------------------------------------------------
do
    local _, st = build_profile({ project = 18 })
    eq(st.family, "FOREVER", "forever: family")
    eq(st.is_retail, false, "forever: not retail")
    eq(st.is_mainline, true, "forever: mainline-code client (no swing engine)")
    eq(st.gcd_probe_spell_id, 61304, "forever: gcd probe is 61304")
end

-- ---------------------------------------------------------------------------
-- WoTLK Titanforge (3.80.2): wrath project id, classic probe retained
-- ---------------------------------------------------------------------------
do
    local _, st = build_profile({ project = 11, interface = 38002 })
    eq(st.family, "WRATH", "titan(38002): family via wrath project id")
    eq(st.interface_number, 38002, "titan(38002): interface number recorded")
    eq(st.is_mainline, false, "titan(38002): swing engine still available")
    eq(st.gcd_probe_spell_id, 29515, "titan(38002): gcd probe is 29515")
end

-- ---------------------------------------------------------------------------
-- Warrior rage-cost path
-- ---------------------------------------------------------------------------
do
    local power = { value = 5 }
    local queried_id
    local ST = { WARRIOR = {} }
    build_profile({
        project = 11,
        globals = {
            GetSpellInfo = spell_table(ALL_RANKS),
            GetSpellPowerCost = function(id)
                queried_id = id
                return { { cost = 15 } }
            end,
            UnitPower = function() return power.value end,
        },
        ST = ST,
        module = "classes/warrior.lua",
    })
    local self = { hs_queued = true, cleave_queued = false, insufficient_rage = false, set_bar_color = function() end }
    ST.WARRIOR.on_rage_update(self)
    eq(queried_id, 47450, "warrior(wrath): resolves HS rank 47450 and queries its cost")
    eq(self.insufficient_rage, true, "warrior(wrath): 5 rage < 15 -> insufficient")
    power.value = 20
    ST.WARRIOR.on_rage_update(self)
    eq(self.insufficient_rage, false, "warrior(wrath): 20 rage >= 15 -> sufficient")
    ST.WARRIOR.on_spellcast_succeeded(self, "target", nil, 47450)
    eq(self.hs_queued, false, "warrior(wrath): cast clears the HS queued flag")
end

do
    local power = { value = 5 }
    local queried_id
    local spell_info_calls = 0
    local known = spell_table(ERA_RANKS)
    local ST = { WARRIOR = {} }
    build_profile({
        project = 2,
        globals = {
            GetSpellInfo = function(id)
                spell_info_calls = spell_info_calls + 1
                return known(id)
            end,
            GetSpellPowerCost = function(id)
                queried_id = id
                return { { cost = 10 } }
            end,
            UnitPower = function() return power.value end,
        },
        ST = ST,
        module = "classes/warrior.lua",
    })
    local self = { hs_queued = true, cleave_queued = false, insufficient_rage = false, set_bar_color = function() end }
    ST.WARRIOR.on_rage_update(self)
    eq(queried_id, 25286, "warrior(era): resolves HS rank 25286 and queries its cost")
    eq(self.insufficient_rage, true, "warrior(era): 5 rage < 10 -> insufficient")
    local after_first = spell_info_calls
    power.value = 12
    ST.WARRIOR.on_rage_update(self)
    eq(self.insufficient_rage, false, "warrior(era): 12 rage >= 10 -> sufficient")
    eq(spell_info_calls, after_first, "warrior(era): resolved rank is cached (no re-scan)")
end

do
    local ST = { WARRIOR = {} }
    build_profile({
        project = 2,
        globals = {
            GetSpellInfo = spell_table({}),
            GetSpellPowerCost = function() error("must not be called when no rank resolves") end,
            UnitPower = function() return 0 end,
        },
        ST = ST,
        module = "classes/warrior.lua",
    })
    local self = { hs_queued = true, cleave_queued = false, insufficient_rage = true, set_bar_color = function() end }
    ST.WARRIOR.on_rage_update(self)
    eq(self.insufficient_rage, false, "warrior(no ids known): degrades to sufficient, no crash")
end

-- ---------------------------------------------------------------------------
-- Druid rage-cost path
-- ---------------------------------------------------------------------------
do
    local power = { value = 5 }
    local queried_id
    local ST = { DRUID = {} }
    build_profile({
        project = 11,
        globals = {
            GetSpellInfo = spell_table(ALL_RANKS),
            GetSpellPowerCost = function(id)
                queried_id = id
                return { { cost = 10 } }
            end,
            UnitPower = function() return power.value end,
        },
        ST = ST,
        module = "classes/druid.lua",
    })
    local self = { maul_queued = true, insufficient_rage = false, set_bar_color = function() end }
    ST.DRUID.on_rage_update(self)
    eq(queried_id, 48480, "druid(wrath): resolves Maul rank 48480 and queries its cost")
    eq(self.insufficient_rage, true, "druid(wrath): 5 rage < 10 -> insufficient")
end

do
    local power = { value = 12 }
    local queried_id
    local ST = { DRUID = {} }
    build_profile({
        project = 2,
        globals = {
            GetSpellInfo = spell_table(ERA_RANKS),
            GetSpellPowerCost = function(id)
                queried_id = id
                return { { cost = 10 } }
            end,
            UnitPower = function() return power.value end,
        },
        ST = ST,
        module = "classes/druid.lua",
    })
    local self = { maul_queued = true, insufficient_rage = false, set_bar_color = function() end }
    ST.DRUID.on_rage_update(self)
    eq(queried_id, 9881, "druid(era): resolves Maul rank 9881 and queries its cost")
    eq(self.insufficient_rage, false, "druid(era): 12 rage >= 10 -> sufficient")
end

-- ---------------------------------------------------------------------------
-- Paladin seal detection (all classic ranks)
-- ---------------------------------------------------------------------------
local function paladin_self()
    return {
        is_value_in_array = function(_, value, array)
            for i = 1, #array do
                if array[i] == value then return true end
            end
            return false
        end,
        set_bar_color = function() end,
    }
end

do
    -- Era: every rank id of the pre-Wrath seals must be recognized.
    local auras = { 20920, 20349, 20357, 27155, 31895, 31801 }
    local ST = { PALADIN = {} }
    build_profile({
        project = 2,
        globals = {
            UnitAura = aura_stub(auras),
            GetSpellBaseCooldown = function() return 15000 end,
        },
        ST = ST,
        module = "classes/paladin.lua",
    })
    local self = paladin_self()
    ST.PALADIN.on_aura_change(self)
    eq(self.has_soc, true, "paladin(era): Seal of Command rank 4 (20920) recognized")
    eq(self.has_sol, true, "paladin(era): Seal of Light rank 9 (20349) recognized")
    eq(self.has_sow, true, "paladin(era): Seal of Wisdom (20357) recognized")
    eq(self.has_sor, true, "paladin(era): Seal of Righteousness rank 9 (27155) recognized")
    eq(self.has_soj, true, "paladin(era): Seal of Justice rank 2 (31895) recognized")
    eq(self.has_sov, true, "paladin(era): Seal of Vengeance (31801) recognized")
    eq(self.has_aow, false, "paladin(era): no Art of War aura")
end

do
    -- Wrath: the single-rank ids the module always used must still match.
    local auras = { 20375, 20165, 20166, 21084, 20164, 59578 }
    local ST = { PALADIN = {} }
    build_profile({
        project = 11,
        globals = {
            UnitAura = aura_stub(auras),
            GetSpellBaseCooldown = function() return 15000 end,
        },
        ST = ST,
        module = "classes/paladin.lua",
    })
    local self = paladin_self()
    ST.PALADIN.on_aura_change(self)
    eq(self.has_soc, true, "paladin(wrath): Seal of Command (20375) recognized")
    eq(self.has_sol, true, "paladin(wrath): Seal of Light (20165) recognized")
    eq(self.has_sow, true, "paladin(wrath): Seal of Wisdom (20166) recognized")
    eq(self.has_sor, true, "paladin(wrath): Seal of Righteousness (21084) recognized")
    eq(self.has_soj, true, "paladin(wrath): Seal of Justice (20164) recognized")
    eq(self.has_aow, true, "paladin(wrath): Art of War (59578) recognized")
end

-- ---------------------------------------------------------------------------
-- Hunter raptor-strike queue detection (lookup tables + per-class enable check)
-- ---------------------------------------------------------------------------
do
    local ST = { HUNTER = {} }
    build_profile({
        project = 11,
        globals = {
            GetSpellInfo = spell_table({ 48996 }),
            IsCurrentSpell = function(id) return id == 48996 end,
        },
        ST = ST,
        module = "classes/hunter.lua",
    })
    local self = {
        raptor_strike_queued = false,
        set_bar_color = function() end,
        get_class_table = function() return { enable_raptor_strike_color = true } end,
    }
    ST.HUNTER.on_current_spell_cast_changed(self, false)
    eq(self.raptor_strike_queued, true, "hunter(wrath): queued Raptor Strike (48996) detected")

    self.raptor_strike_queued = true
    ST.HUNTER.on_spellcast_succeeded(self, "target", nil, 48996)
    eq(self.raptor_strike_queued, false, "hunter(wrath): cast clears the raptor strike queued flag")
end

print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
os.exit(0)
