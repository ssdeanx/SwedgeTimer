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
-- Some compat wrappers read legacy globals through _G (annotation-safe on Mainline-code
-- clients); mirror each profile's stubs into the real _G so those reads resolve here too.
local mirrored_globals = {}

local function build_profile(opts)
    for k in pairs(mirrored_globals) do
        _G[k] = nil
        mirrored_globals[k] = nil
    end
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
    for k, v in pairs(opts.globals or {}) do
        _G[k] = v
        mirrored_globals[k] = true
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
            elseif major == "CallbackHandler-1.0" then
                -- swing_source.lua builds its callback registry at load time.
                return {
                    New = function()
                        return {
                            Fire = function() end,
                            RegisterCallback = function() end,
                            UnregisterCallback = function() end,
                        }
                    end,
                }
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
-- WoW Forever without WOW_PROJECT_ID: interface 16001 must still map to
-- FOREVER (Mainline-code), not the Classic Era bucket
-- ---------------------------------------------------------------------------
do
    local _, st = build_profile({
        project = nil,
        interface = 16001,
    })
    eq(st.family, "FOREVER", "legacy 16001: family falls back to FOREVER")
    eq(st.interface_number, 16001, "legacy 16001: interface number recorded")
    eq(st.is_mainline, true, "legacy 16001: mainline-code client")
    eq(st.gcd_probe_spell_id, 61304, "legacy 16001: gcd probe is 61304")
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
-- Cata (14) / Mists (19) runtime family (proctor G1): the TOC half is pinned by
-- toc_check; this is the runtime half - family mapping, spell resolution, the lust
-- gate, and the engine availability that main.lua's selection ladder reads.
-- ---------------------------------------------------------------------------
do
    local cases = {
        { project = 14, family = "CATA", label = "cata(14)" },
        { project = 19, family = "MISTS", label = "mists(19)" },
    }
    for i = 1, #cases do
        local case = cases[i]
        local _, st = build_profile({
            project = case.project,
            globals = { GetSpellInfo = spell_table(ALL_RANKS) },
            module = "swing_source.lua",
        })
        eq(st.family, case.family, case.label .. ": family")
        eq(st.is_mainline, false, case.label .. ": classic-code client")
        eq(st.gcd_probe_spell_id, 29515, case.label .. ": gcd probe is 29515")
        eq(st.lust_supported, true, case.label .. ": lust window arms (TBC+ spell line)")
        eq(st.api.get_family_spell_id({47450, 30324, 29707, 25286, 78}), 47450,
            case.label .. ": HS resolves the highest known rank")
        eq(st.api.get_family_spell_id({48480, 48479, 26996, 9881}), 48480,
            case.label .. ": Maul resolves the highest known rank")
        eq(st.api.get_family_spell_id({47520, 845}), 47520,
            case.label .. ": Cleave resolves the highest known rank")
        eq(st.api.get_family_spell_id({999991, 999992}), nil,
            case.label .. ": ids absent from this client -> nil")
        -- Engine selection input: the Forever source only reports itself available on
        -- the FOREVER family, and neither Cata nor Mists ships the vendored library
        -- (toc_check:233-255). Both branches of main.lua's ladder are therefore closed
        -- and the remaining branch is the inert stand-in - the boot below proves it.
        eq(st.swing_source.available, false,
            case.label .. ": the Forever swing source stays inert")
    end
end

-- ---------------------------------------------------------------------------
-- Engine selection + player combat continuity (proctor G1/G4): load the REAL
-- main.lua read-only over compat.lua + swing_source.lua (the main_init_state.lua
-- discipline - nothing in main.lua/bars.lua/tocs is touched) with the Cata/Mists
-- profile, then drive the combat events directly.
-- ---------------------------------------------------------------------------
local function boot_main(project, interface, lib_present)
    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.WOW_PROJECT_ID = project
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", interface end
    env.GetTime = function() return 100 end
    env.GetTimePreciseSec = function() return 100 end
    env.UnitClass = function() return "Paladin", "PALADIN" end
    env.UnitAttackSpeed = function() return 2.6, 0 end
    env.UnitRangedDamage = function() return 0 end
    env.C_EventUtils = { IsEventValid = function() return false end }

    local boot = { hooks = 0 }
    local ST, st
    local stub_lib = {
        RegisterCallback = function() end,
        UnregisterCallback = function() end,
    }
    local callback_handler = {
        New = function()
            return {
                Fire = function() end,
                RegisterCallback = function() end,
                UnregisterCallback = function() end,
            }
        end,
    }
    env.LibStub = function(major, silent)
        if major == "AceAddon-3.0" then
            return { NewAddon = function() return ST end }
        elseif major == "CallbackHandler-1.0" then
            return callback_handler
        elseif major == "LibClassicSwingTimerAPI" then
            -- Absent on the Cata/Mists flavors (their tocs ship no vendored library).
            return lib_present and stub_lib or nil
        end
        return stub_lib
    end

    ST = {}
    st = { utils = { print_msg = function() end } }
    local modules = { "compat.lua", "swing_source.lua", "main.lua" }
    for i = 1, #modules do
        local chunk = assert(loadfile(ROOT .. modules[i]))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "SwedgeTimer", st)
        check(ok, "main boot (" .. tostring(project) .. "): " .. modules[i]
            .. " loads (" .. tostring(err) .. ")")
    end
    ST.player_class = "PALADIN"
    ST.PALADIN.on_combat_exit = function() boot.hooks = boot.hooks + 1 end
    boot.env, boot.st, boot.ST = env, st, ST
    return boot
end

do
    -- G1: engine selection on the Cata/Mists flavors. With the vendored library
    -- absent (toc_check pins that for both) and the Forever source probe closed
    -- (swing_source.available false above), main.lua must select the inert stand-in.
    for _, case in ipairs({
        { project = 14, label = "cata(14)" },
        { project = 19, label = "mists(19)" },
    }) do
        local boot = boot_main(case.project, case.project == 14 and 14000 or 19000, false)
        eq(boot.ST.swing_engine, "inert-standin",
            case.label .. ": the lib-absent boot selects the inert stand-in")
        -- Control: the same ladder selects the vendored library when it is present.
        local vendored = boot_main(case.project, case.project == 14 and 14000 or 19000, true)
        eq(vendored.ST.swing_engine, "vendored-lib",
            case.label .. " control: a present library still wins")
    end
end

do
    -- G4: player combat-enter/exit continuity. The cycle is owned by the swing
    -- engine; the combat handlers must flip in_combat exactly and call the class
    -- hook once without touching the mainhand record (no clearing, no fake STOP).
    local boot = boot_main(14, 14000, false)
    local ST = boot.ST
    ST.mainhand = { speed = 2.6, start = 100.0, ends_at = 102.6, is_full = false }
    local cycle = ST.mainhand

    ST:PLAYER_REGEN_DISABLED()
    eq(ST.in_combat, true, "G4: combat enter flips in_combat")
    eq(ST.mainhand, cycle, "G4: combat enter keeps the mainhand record")
    eq(ST.mainhand.speed, 2.6, "G4: the cycle speed is untouched")

    ST:PLAYER_REGEN_ENABLED()
    eq(ST.in_combat, false, "G4: combat exit flips in_combat back")
    eq(ST.mainhand, cycle, "G4: combat exit keeps the mainhand record")
    eq(ST.mainhand.start, 100.0, "G4: the cycle start survives the transition")
    eq(ST.mainhand.ends_at, 102.6, "G4: the cycle end survives the transition")
    eq(ST.mainhand.is_full, false, "G4: the bar is not forced full on exit")
    eq(boot.hooks, 1, "G4: the class combat-exit hook runs exactly once")

    -- A second ride: one more clean transition, no accumulation.
    ST:PLAYER_REGEN_DISABLED()
    ST:PLAYER_REGEN_ENABLED()
    eq(boot.hooks, 2, "G4: each exit fires one hook call")
    eq(ST.mainhand, cycle, "G4: repeated rides keep the same cycle object")
end


-- ---------------------------------------------------------------------------
-- Lust window (C2): family gate, confirmed ids, shared player-aura scan
-- ---------------------------------------------------------------------------

do
    -- Era: Bloodlust/Heroism is TBC+ only (verify_bank §2) - the gate must stay
    -- closed, and the scan must still exist and degrade to nil, nil.
    local _, st = build_profile({ project = 2 })
    eq(st.family, "ERA", "era: family")
    eq(st.lust_supported, false, "era: lust window must not arm on Classic Era")
    local rem, stk = st.api.scan_player_aura(function() return true end)
    check(rem == nil and stk == nil, "era scan: no aura API on the profile -> nil, nil")
end

do
    -- Families where the spells exist: TBC, Wrath, Forever (Mainline-code, but
    -- the spells are not Era-gated away there). UNKNOWN stays off.
    local _, tbc = build_profile({ project = 5 })
    eq(tbc.family, "TBC", "tbc: family")
    eq(tbc.lust_supported, true, "tbc: lust window arms")
    local _, wrath = build_profile({ project = 11 })
    eq(wrath.lust_supported, true, "wrath: lust window arms")
    local _, forever = build_profile({ project = 18 })
    eq(forever.lust_supported, true, "forever: lust window arms")
    local _, unknown = build_profile({ project = nil })
    eq(unknown.lust_supported, false, "unknown family: lust window stays off")
end

do
    -- Id registration: exactly the two CONFIRMED ids on the lust list; the
    -- UNCONFIRMED post-lust debuffs sit in their own table, never mixed in.
    local _, st = build_profile({ project = 5 })
    check(st.lust_spell_ids[1] == 2825 and st.lust_spell_ids[2] == 32182
        and st.lust_spell_ids[3] == nil, "tbc: lust ids are exactly 2825/32182 (CONFIRMED)")
    check(st.post_lust_debuff_ids[1] == 57723 and st.post_lust_debuff_ids[2] == 57724,
        "tbc: post-lust 57723/57724 registered (UNCONFIRMED, no hard dependency)")
end

do
    -- TBC classic path through the aura wrapper: remaining = expirationTime -
    -- now in the GetTime domain, the stacks rules, and the nil paths.
    local function buff_stub(entries)
        return function(unit, index, filter)
            if unit ~= "player" or filter ~= "HELPFUL" then return nil end
            local entry = entries[index]
            if not entry then return nil end
            return "Buff " .. tostring(entry.spell_id), nil, entry.count, nil,
                entry.duration, entry.expiration, nil, nil, nil, entry.spell_id
        end
    end
    local _, st = build_profile({
        project = 5,
        globals = {
            GetTime = function() return 1000 end,
            UnitAura = buff_stub({
                { spell_id = 12345, count = 5 },
                { spell_id = 2825, duration = 40, expiration = 1030 },
            }),
        },
    })
    local remaining, stacks = st.api.scan_player_aura(function(id) return id == 2825 end)
    eq(remaining, 30, "tbc scan: remaining = expirationTime - now (1030-1000)")
    eq(stacks, nil, "tbc scan: non-stacking aura reports nil stacks")
    remaining, stacks = st.api.scan_player_aura(function(id) return id == 12345 end)
    eq(remaining, nil, "tbc scan: entry without expirationTime -> nil remaining")
    eq(stacks, 5, "tbc scan: stacked aura reports its count")
    remaining, stacks = st.api.scan_player_aura(function(id) return id == 999999 end)
    check(remaining == nil and stacks == nil, "tbc scan: unmatched id -> nil, nil")
    remaining, stacks = st.api.scan_player_aura(nil)
    check(remaining == nil and stacks == nil, "tbc scan: nil predicate -> nil, nil")
    local calls, last_name, last_count = 0
    st.api.scan_player_aura(function(id, name, count)
        calls = calls + 1
        last_name, last_count = name, count
        return false
    end)
    eq(calls, 2, "tbc scan: predicate runs once per real aura (nil rows are skipped, not matched)")
    eq(last_name, "Buff 2825", "tbc scan: predicate receives the aura name")
    eq(last_count, nil, "tbc scan: predicate receives the count as-is")
end

do
    -- R2: a secret (nil) entry above the lust buff no longer truncates the scan.
    local function hole_buff_stub(entries)
        return function(unit, index, filter)
            if unit ~= "player" or filter ~= "HELPFUL" then return nil end
            local entry = entries[index]
            if not entry then return nil end
            return "Buff", nil, entry.count, nil,
                entry.duration, entry.expiration, nil, nil, nil, entry.spell_id
        end
    end
    local _, st = build_profile({
        project = 5,
        globals = {
            GetTime = function() return 1000 end,
            -- Index 1 degrades to absent (secret); Bloodlust sits at index 2.
            UnitAura = hole_buff_stub({
                [2] = { spell_id = 2825, duration = 40, expiration = 1030 },
            }),
        },
    })
    local remaining, stacks = st.api.scan_player_aura(function(id) return id == 2825 end)
    eq(remaining, 30, "tbc scan hole: Bloodlust below a secret row is still found")
    eq(stacks, nil, "tbc scan hole: non-stacking aura reports nil stacks")
end

do
    -- R3 probe: classic-line profiles expose the combat-log global, so CLEU
    -- chains can arm; Mainline-code ones (Forever, Retail) do not.
    local _, tbc = build_profile({
        project = 5,
        globals = { CombatLogGetCurrentEventInfo = function() return nil end },
    })
    eq(tbc.cleu_supported, true, "tbc: the combat-log global means CLEU chains can arm")
    local _, forever = build_profile({ project = 18 })
    eq(forever.cleu_supported, false, "forever: no combat-log global, CLEU chains stay inert")
    local _, retail = build_profile({ project = 1 })
    eq(retail.cleu_supported, false, "retail: no combat-log global, CLEU chains stay inert")
end

do
    -- An expired/stale reading must clamp at 0, and a count of 1 is unstacked.
    local _, st = build_profile({
        project = 5,
        globals = {
            GetTime = function() return 1000 end,
            UnitAura = function(unit, index, filter)
                if unit ~= "player" or filter ~= "HELPFUL" or index ~= 1 then
                    return nil
                end
                return "Buff 2825", nil, 1, nil, 40, 990, nil, nil, nil, 2825
            end,
        },
    })
    local remaining, stacks = st.api.scan_player_aura(function() return true end)
    eq(remaining, 0, "tbc scan: stale expiration clamps to 0")
    eq(stacks, nil, "tbc scan: a count of 1 reads as unstacked")
end

do
    -- Mainline C_ path (retail here, Forever shares it): no classic UnitAura
    -- global on this profile, so the scan must run through C_UnitAuras.
    local _, st = build_profile({
        project = 1,
        globals = {
            GetTime = function() return 1000 end,
            C_UnitAuras = {
                GetAuraDataByIndex = function(unit, index, filter)
                    if unit ~= "player" or filter ~= "HELPFUL" or index ~= 1 then
                        return nil
                    end
                    return {
                        name = "Bloodlust", applications = 1, duration = 40,
                        expirationTime = 1030, spellId = 2825,
                    }
                end,
            },
        },
    })
    local remaining, stacks = st.api.scan_player_aura(function(id) return id == 2825 end)
    eq(remaining, 30, "retail scan: C_ path remaining = expirationTime - now")
    eq(stacks, nil, "retail scan: single application reads as unstacked")
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
    self.PALADIN = ST.PALADIN
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
    self.PALADIN = ST.PALADIN
    ST.PALADIN.on_aura_change(self)
    eq(self.has_soc, true, "paladin(wrath): Seal of Command (20375) recognized")
    eq(self.has_sol, true, "paladin(wrath): Seal of Light (20165) recognized")
    eq(self.has_sow, true, "paladin(wrath): Seal of Wisdom (20166) recognized")
    eq(self.has_sor, true, "paladin(wrath): Seal of Righteousness (21084) recognized")
    eq(self.has_soj, true, "paladin(wrath): Seal of Justice (20164) recognized")
    eq(self.has_aow, true, "paladin(wrath): Art of War (59578) recognized")
    eq(self.has_sob, false, "paladin(wrath): no Blood/Martyr aura")
    eq(self.has_sotc, false, "paladin(wrath): no Crusader aura")
end

do
    -- Forever: the classic Righteousness id still latches (unchanged), but a
    -- hypothetical new Forever Righteousness id stays silent until it is
    -- confirmed into sor_forever_ids (empty + UNCONFIRMED, never guessed).
    local ST = { PALADIN = {} }
    local _, fst = build_profile({
        project = 18,
        globals = {
            UnitAura = aura_stub({ 21084 }),
            GetSpellBaseCooldown = function() return 15000 end,
        },
        ST = ST,
        module = "classes/paladin.lua",
    })
    eq(fst.family, "FOREVER", "paladin(forever): project 18 reports FOREVER")
    local self = paladin_self()
    self.PALADIN = ST.PALADIN
    ST.PALADIN.on_aura_change(self)
    eq(self.has_sor, true, "paladin(forever): the classic Righteousness id (21084) still latches")
end

do
    -- Forever with a new (unconfirmed) Righteousness id: silent, never latched.
    local ST = { PALADIN = {} }
    build_profile({
        project = 18,
        globals = {
            UnitAura = aura_stub({ 123456 }),
            GetSpellBaseCooldown = function() return 15000 end,
        },
        ST = ST,
        module = "classes/paladin.lua",
    })
    local self = paladin_self()
    self.PALADIN = ST.PALADIN
    ST.PALADIN.on_aura_change(self)
    eq(self.has_sor, false, "paladin(forever): an unconfirmed Righteousness id stays silent")
end

do
    -- Control: the same unknown id stays silent off Forever too (family gate).
    local ST = { PALADIN = {} }
    build_profile({
        project = 2,
        globals = {
            UnitAura = aura_stub({ 123456 }),
            GetSpellBaseCooldown = function() return 15000 end,
        },
        ST = ST,
        module = "classes/paladin.lua",
    })
    local self = paladin_self()
    self.PALADIN = ST.PALADIN
    ST.PALADIN.on_aura_change(self)
    eq(self.has_sor, false, "paladin(era): the unknown id stays silent off Forever")
end

do
    -- TBC Anniversary: every id in the Blood/Martyr and Crusader seal tables must
    -- be recognized on its own.
    local cases = {
        { id = 31892,  flag = "has_sob",  label = "Seal of Blood (31892)" },
        { id = 348700, flag = "has_sob",  label = "Seal of the Martyr (348700)" },
        { id = 21082,  flag = "has_sotc", label = "Seal of the Crusader rank 1 (21082)" },
        { id = 20162,  flag = "has_sotc", label = "Seal of the Crusader rank 2 (20162)" },
        { id = 20305,  flag = "has_sotc", label = "Seal of the Crusader rank 3 (20305)" },
        { id = 20306,  flag = "has_sotc", label = "Seal of the Crusader rank 4 (20306)" },
        { id = 20307,  flag = "has_sotc", label = "Seal of the Crusader rank 5 (20307)" },
        { id = 20308,  flag = "has_sotc", label = "Seal of the Crusader rank 6 (20308)" },
        { id = 27158,  flag = "has_sotc", label = "Seal of the Crusader TBC rank (27158)" },
    }
    for i = 1, #cases do
        local case = cases[i]
        local ST = { PALADIN = {} }
        build_profile({
            project = 5,
            globals = {
                UnitAura = aura_stub({ case.id }),
                GetSpellBaseCooldown = function() return 15000 end,
            },
            ST = ST,
            module = "classes/paladin.lua",
        })
        local self = paladin_self()
        self.PALADIN = ST.PALADIN
        ST.PALADIN.on_aura_change(self)
        eq(self[case.flag], true, "paladin(tbc): " .. case.label .. " recognized")
    end
end

-- ---------------------------------------------------------------------------
-- Paladin twist detection (runtime-shaped CLEU calls)
-- ---------------------------------------------------------------------------
do
    -- Mirrors exactly what main.lua forwards for COMBAT_LOG_EVENT_UNFILTERED:
    -- (event, timestamp, subevent, hideCaster, sourceGUID, ...) per AceEvent.
    local auras = { 20375, 31892 } -- Seal of Command + Seal of Blood
    local now = 100
    local ST = { PALADIN = {} }
    local env, st = build_profile({
        project = 5,
        globals = {
            UnitAura = aura_stub(auras),
            UnitGUID = function() return "Player-1" end,
            GetTime = function() return now end,
            GetSpellBaseCooldown = function() return 15000 end,
            C_Timer = { After = function() end },
        },
        ST = ST,
        module = "classes/paladin.lua",
    })
    local twist_mod = assert(loadfile(ROOT .. "twist.lua"))
    setfenv(twist_mod, env)
    twist_mod("SwedgeTimer", st)

    ST.get_visuals_frame = function() return nil end
    ST.set_bar_color = function() end
    ST.get_class_table = function() return {} end
    ST.mainhand = {}
    ST.latency = { world_ms = 0 }
    ST.gcd = {}
    ST.PALADIN.post_init(ST)

    local function cleu(event, ...)
        ST.PALADIN.on_combat_log_unfiltered(
            ST, "COMBAT_LOG_EVENT_UNFILTERED", now, event, false,
            "Player-1", "Player", 0, 0, "Target-1", "Target", 0, 0, ...)
    end

    eq(ST.twist_active_seals_count, 2, "twist: two seals counted at post_init")

    -- Two seals at a landing swing => attempt; an unrelated spell does not consume it.
    cleu("SWING_DAMAGE", 10, 0)
    eq(ST.twist_attempt_pending, true, "twist: two seals on SWING_DAMAGE => attempt pending")
    eq(ST.twist_attempt_until, now + 0.25, "twist: attempt feedback window armed")
    cleu("SPELL_DAMAGE", 9999, "Not a proc", 1, 10, 0)
    eq(ST.twist_attempt_pending, true, "twist: unrelated SPELL_DAMAGE keeps the attempt pending")

    -- The Command proc confirms it.
    cleu("SPELL_DAMAGE", 20424, "Seal of Command", 1, 10, 0)
    eq(ST.twist_attempt_pending, false, "twist: SoC proc consumes the pending attempt")
    check((ST.twist_success_until or 0) > now, "twist: success feedback armed")

    -- Extra attacks: amount is honoured, one is consumed per extra swing, and no
    -- twist attempt is registered for an extra swing.
    cleu("SPELL_EXTRA_ATTACKS", 12345, "Windfury", 1, 2)
    eq(ST.twist_extra_attacks_pending, 2, "twist: SPELL_EXTRA_ATTACKS amount=2 counted")
    cleu("SWING_DAMAGE", 10, 0)
    eq(ST.twist_extra_attacks_pending, 1, "twist: extra swing consumes one pending extra")
    eq(ST.twist_attempt_pending, false, "twist: extra swing does not register an attempt")

    -- Combat exit clears orphaned extras.
    ST.PALADIN.on_combat_exit(ST)
    eq(ST.twist_extra_attacks_pending, 0, "twist: combat exit clears orphaned extras")

    -- Single seal => no attempt; restoring the second seal arms it again.
    auras[2] = nil
    cleu("SWING_DAMAGE", 10, 0)
    eq(ST.twist_active_seals_count, 1, "twist: single seal counted")
    eq(ST.twist_attempt_pending, false, "twist: single seal does not register an attempt")
    auras[2] = 31892
    cleu("SWING_DAMAGE", 10, 0)
    eq(ST.twist_attempt_pending, true, "twist: second seal re-arms the attempt")
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
