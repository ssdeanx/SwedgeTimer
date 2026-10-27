-- Spell-query family matrix: the state-query TOKEN each client family takes.
--
-- Operator ruling (binding, 2026-10-25): "titanforge aka wotlk doesnt use spell ids
-- either. stop guessing. each has their own client." + "tbc is classic_anniversary
-- and doesnt take spell ids it needs spell names." Each family is gated ON ITS OWN:
--
--   ERA     classic_era 1.15.9 (SoD runes are the SAME client) -> numeric IDS.
--   TBC     classic_anniversary 2.5.6                           -> localized NAMES first.
--   WRATH   classic_titan 3.80.2 (Titanforge)                   -> localized NAMES first.
--   FOREVER 1.60.1                                              -> numeric ids (unchanged).
--
-- The id FALLBACK is operator-approved and binding: "i never banned fallback to ids."
-- On a name family the localized name is tried first, then the id - a cold name must
-- still resolve through the id form, never a nil query. The fallback is pinned here so
-- it cannot be removed again.
--
-- Pins:
--   1. compat api.get_spell_query per family (ERA/TBC/WRATH/FOREVER), SoD id intact,
--      including the nil-name -> id fallback on both name families.
--   2. The rank-existence walk: a known name resolves; a name the client cannot index
--      falls back to its id and still resolves; an id absent from both forms is absent.
--   3. Hunter spell_token: id on ERA, name on TBC, name on WRATH, id when the name is
--      cold (fallback), never nil for a valid id (proved through is_viper_known).
--   4. Hunter queue_tokens: ids on ERA, names on TBC/WRATH, no probe on a cold cache
--      (proved through on_current_spell_cast_changed -> IsCurrentSpell).
--   5. Static: the approved `or <id>` fallback is present in compat and every class
--      token helper (it must not be removed again).
--
-- Plain Lua 5.1, no WoW client needed. Run from the repo root:
--   lua5.1 tests/spell_query_family_state.lua

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

local function read(rel)
    local f = assert(io.open(ROOT .. rel, "r"), "readable: " .. rel)
    local src = f:read("*a")
    f:close()
    return src
end

--=========================================================================================
-- Sandbox builder: the REAL compat.lua over one client profile
--=========================================================================================
-- opts:
--   project      WOW_PROJECT_ID for the profile
--   interface    TOC interface (the fallback family detector)
--   GetSpellInfo the client's spell-data answer (default: knows nothing)
--   IsSpellKnown optional recorder/answer (class legs)
--   current_spell the token IsCurrentSpell answers true for (queue leg)
local function base_env(opts)
    local env = setmetatable({}, { __index = _G })
    env._G = env -- compat reads legacy globals through rawget(_G, ...)
    env.WOW_PROJECT_ID = opts.project
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_CAMELOT = 18
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", opts.interface end
    env.GetTime = function() return 0 end
    env.GetTimePreciseSec = function() return 0 end
    env.GetSpellInfo = opts.GetSpellInfo or function() return nil end
    if opts.IsSpellKnown then env.IsSpellKnown = opts.IsSpellKnown end
    if opts.GetSpellCooldown then env.GetSpellCooldown = opts.GetSpellCooldown end
    if opts.IsCurrentSpell then env.IsCurrentSpell = opts.IsCurrentSpell end
    if opts.IsMounted then env.IsMounted = opts.IsMounted end
    return env
end

local function new_st(env)
    local st = {
        utils = {
            -- Same contract as utils.lua's convert_lookup_table.
            convert_lookup_table = function(list)
                local tab = {}
                for i = 1, #list do tab[list[i]] = true end
                return tab
            end,
        },
    }
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    compat("SwedgeTimer", st)
    return st
end

local function compat_profile(opts)
    local env = base_env(opts)
    return new_st(env), env
end

local PROFILES = {
    ERA = { project = 2, interface = 11509 },
    TBC = { project = 5, interface = 20506 },
    WRATH = { project = 11, interface = 38002 },
    FOREVER = { project = 18, interface = 16001 },
}

--=========================================================================================
-- 1) api.get_spell_query, one family at a time: NAME first, ID fallback
--=========================================================================================
do
    local era = compat_profile(PROFILES.ERA)
    eq(era.family, "ERA", "get_spell_query: the Era profile reports ERA")
    eq(era.api.get_spell_query("Kick", 107), 107,
        "ERA: the state token is the numeric ID")
    eq(era.api.get_spell_query(nil, 107), 107,
        "ERA: an id needs no name (the id IS the query)")
    -- SoD shares the Era client: a rune id is an Era id, passed through untouched.
    eq(era.api.get_spell_query("Molten Blast", 425339), 425339,
        "ERA/SoD: a rune id is an Era id (never rewritten, never substituted)")

    local tbc = compat_profile(PROFILES.TBC)
    eq(tbc.family, "TBC", "get_spell_query: the TBC profile reports TBC")
    eq(tbc.api.get_spell_query("Kick", 107), "Kick",
        "TBC: the state token is the localized NAME")
    eq(tbc.api.get_spell_query(nil, 107), 107,
        "TBC: a missing name falls back to the id (operator-approved fallback)")

    local wrath = compat_profile(PROFILES.WRATH)
    eq(wrath.family, "WRATH", "get_spell_query: the Wrath/Titanforge profile reports WRATH")
    eq(wrath.api.get_spell_query("Kick", 107), "Kick",
        "WRATH/Titanforge: the state token is the localized NAME (operator ruling)")
    eq(wrath.api.get_spell_query(nil, 107), 107,
        "WRATH/Titanforge: a missing name falls back to the id (operator-approved fallback)")

    local forever = compat_profile(PROFILES.FOREVER)
    eq(forever.family, "FOREVER", "get_spell_query: the Forever profile reports FOREVER")
    eq(forever.api.get_spell_query("Kick", 107), 107,
        "FOREVER: the state token is the numeric id (unchanged)")
end

--=========================================================================================
-- 2) The rank-existence walk: name path first, then the id re-probe fallback
--=========================================================================================
-- (a) A real client answers both forms: the name path resolves.
local function both_forms(spell)
    if spell == 29707 or spell == "Heroic Strike" then
        return "Heroic Strike", nil, 1, 0, 0, 0, 29707
    end
    return nil
end
do
    local tbc = compat_profile({ project = 5, interface = 20506, GetSpellInfo = both_forms })
    eq(tbc.api.get_family_spell_id({ 29707, 78 }), 29707,
        "TBC: a known NAME resolves through the name path")
    local wrath = compat_profile({ project = 11, interface = 38002, GetSpellInfo = both_forms })
    eq(wrath.api.get_family_spell_id({ 29707, 78 }), 29707,
        "WRATH: a known NAME resolves through the name path")
end

-- (b) The client answers the id form with a name but does not index the name itself.
-- The name path misses; the approved id re-probe still resolves the rank.
local function id_names_only(spell)
    if spell == 29707 then
        return "Heroic Strike", nil, 1, 0, 0, 0, 29707
    end
    return nil
end
do
    local wrath = compat_profile({ project = 11, interface = 38002,
        GetSpellInfo = id_names_only })
    local id, state = wrath.api.get_family_spell_id_state({ 29707, 78 })
    eq(id, 29707, "WRATH: an unindexed name resolves via the ID fallback")
    eq(state, "resolved", "WRATH: the id fallback reports 'resolved'")

    local tbc = compat_profile({ project = 5, interface = 20506,
        GetSpellInfo = id_names_only })
    local tbc_id, tbc_state = tbc.api.get_family_spell_id_state({ 29707, 78 })
    eq(tbc_id, 29707, "TBC: an unindexed name resolves via the ID fallback")
    eq(tbc_state, "resolved", "TBC: the id fallback reports 'resolved'")

    -- Era control: the id form IS the query there, so it resolves.
    local era = compat_profile({ project = 2, interface = 11509,
        GetSpellInfo = id_names_only })
    eq(era.api.get_family_spell_id({ 29707, 78 }), 29707,
        "ERA control: the same client resolves by ID (the id is the query)")
end

-- (c) Absent from BOTH forms: the client refutes every candidate, so the walk says
-- "absent" (the same verdict HEAD produced through the id re-probe).
do
    local tbc = compat_profile({ project = 5, interface = 20506,
        GetSpellInfo = function() return nil end })
    local id, state = tbc.api.get_family_spell_id_state({ 29707, 78 })
    eq(id, nil, "TBC: an id absent from both forms resolves nil")
    eq(state, "absent", "TBC: an id absent from both forms reports 'absent'")

    local wrath = compat_profile({ project = 11, interface = 38002,
        GetSpellInfo = function() return nil end })
    local w_id, w_state = wrath.api.get_family_spell_id_state({ 29707, 78 })
    eq(w_id, nil, "WRATH: an id absent from both forms resolves nil")
    eq(w_state, "absent", "WRATH: an id absent from both forms reports 'absent'")
end

-- (d) A client that cannot answer either way (the probe throws / is restricted):
-- never "absent", so a caller does not latch a false negative.
do
    local tbc = compat_profile({ project = 5, interface = 20506,
        GetSpellInfo = function() error("restricted") end })
    local id, state = tbc.api.get_family_spell_id_state({ 29707 })
    eq(id, nil, "TBC: an unreadable client resolves nil")
    eq(state, "unresolved", "TBC: an unreadable client is 'unresolved', never 'absent'")
end

--=========================================================================================
-- 3) Hunter spell_token: the per-spell state token, per family
--=========================================================================================
-- Proved through is_viper_known(), whose only client read is
-- api.is_spell_known(spell_token(id)): the recorded probe token IS spell_token's answer.
local function hunter_profile(opts)
    local tokens = { current = {}, known = {} }
    local env = base_env(opts)
    -- BOTH probes are captured by compat.lua at load, so the recorders must be in
    -- place BEFORE the compat load (the shipped load order: compat first).
    env.IsCurrentSpell = function(token)
        tokens.current[#tokens.current + 1] = token
        return token ~= nil and token == opts.current_spell
    end
    env.IsSpellKnown = function(token)
        tokens.known[#tokens.known + 1] = token
        return opts.IsSpellKnown ~= nil and opts.IsSpellKnown(token) == true
    end
    env.IsMounted = function() return false end
    local ST = { HUNTER = {} }
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        end
        return {}
    end
    local st = new_st(env)
    local utils = assert(loadfile(ROOT .. "utils.lua"))
    setfenv(utils, env)
    utils("SwedgeTimer", st)
    local window = assert(loadfile(ROOT .. "hunter_window.lua"))
    setfenv(window, env)
    window("SwedgeTimer", st)
    local mod = assert(loadfile(ROOT .. "classes/hunter.lua"))
    setfenv(mod, env)
    mod("SwedgeTimer", st)
    assert(type(st.class_loaders) == "table"
        and type(st.class_loaders["HUNTER"]) == "function",
        "classes/hunter.lua registers the HUNTER loader")
    st.class_loaders["HUNTER"]()
    return ST, tokens
end

-- The client's own spell data for the tracked families: id -> name, and the name
-- answers back (a real client's spell data is bidirectional).
local HUNTER_SPELLS = {
    [34074] = "Aspect of the Viper",
    [2973] = "Raptor Strike",
    [14260] = "Raptor Strike",
    [14261] = "Raptor Strike",
    [14262] = "Raptor Strike",
    [14263] = "Raptor Strike",
    [14264] = "Raptor Strike",
    [14265] = "Raptor Strike",
    [14266] = "Raptor Strike",
    [27014] = "Raptor Strike",
    [48995] = "Raptor Strike",
    [48996] = "Raptor Strike",
}
local function hunter_data(spell)
    local id = spell
    if type(spell) == "string" then
        for spell_id, name in pairs(HUNTER_SPELLS) do
            if name == spell then
                id = spell_id
                break
            end
        end
    end
    local name = id and HUNTER_SPELLS[id]
    if name then
        return name, nil, "icon_" .. tostring(id), 0, 0, 0, id
    end
    return nil
end

local function token_types(list)
    local strings, numbers = 0, 0
    for i = 1, #list do
        if type(list[i]) == "string" then
            strings = strings + 1
        elseif type(list[i]) == "number" then
            numbers = numbers + 1
        end
    end
    return strings, numbers
end

do
    local era_ST, era_tokens = hunter_profile({ project = 2, interface = 11509,
        GetSpellInfo = hunter_data,
        IsSpellKnown = function(token) return token == 34074 end })
    eq(era_ST.HUNTER.is_viper_known(), true, "hunter ERA: the id token reads known")
    local era_strings, era_numbers = token_types(era_tokens.known)
    eq(era_strings, 0, "hunter ERA: NO name reaches IsSpellKnown")
    check(era_numbers > 0, "hunter ERA: the probe carries the numeric id")

    local tbc_ST, tbc_tokens = hunter_profile({ project = 5, interface = 20506,
        GetSpellInfo = hunter_data,
        IsSpellKnown = function(token) return token == "Aspect of the Viper" end })
    eq(tbc_ST.HUNTER.is_viper_known(), true, "hunter TBC: the name token reads known")
    local tbc_strings, tbc_numbers = token_types(tbc_tokens.known)
    eq(tbc_numbers, 0, "hunter TBC: NO bare id reaches IsSpellKnown while the name resolves")
    check(tbc_strings > 0, "hunter TBC: the probe carries the localized name")

    local wrath_ST, wrath_tokens = hunter_profile({ project = 11, interface = 38002,
        GetSpellInfo = hunter_data,
        IsSpellKnown = function(token) return token == "Aspect of the Viper" end })
    eq(wrath_ST.HUNTER.is_viper_known(), true,
        "hunter WRATH/Titanforge: the name token reads known")
    local wrath_strings, wrath_numbers = token_types(wrath_tokens.known)
    eq(wrath_numbers, 0, "hunter WRATH/Titanforge: NO bare id reaches IsSpellKnown while the name resolves")
    check(wrath_strings > 0, "hunter WRATH/Titanforge: the probe carries the localized name")

    -- Cold name on a name family: the id fallback keeps a valid id probeable
    -- ("i never banned fallback to ids").
    local cold_ST, cold_tokens = hunter_profile({ project = 11, interface = 38002,
        GetSpellInfo = function() return nil end,
        IsSpellKnown = function(token) return token == 34074 end })
    eq(cold_ST.HUNTER.is_viper_known(), true,
        "hunter cold name: the id fallback still reads known (never nil for a valid id)")
    local cold_strings, cold_numbers = token_types(cold_tokens.known)
    eq(cold_strings, 0, "hunter cold name: no name token is invented")
    check(cold_numbers > 0, "hunter cold name: the probe falls back to the numeric id")
end

--=========================================================================================
-- 4) Hunter queue_tokens: the on-next-attack probe token, per family
--=========================================================================================
local function queue_profile(opts)
    local ST, tokens = hunter_profile(opts)
    ST.interfaces_are_initialised = true
    ST.raptor_strike_queued = false
    ST.get_class_table = function()
        return { enable_raptor_strike_color = true, enable_steady_shot_color = false }
    end
    ST.set_bar_color = function() end
    return ST, tokens
end

do
    local era_ST, era_tokens = queue_profile({ project = 2, interface = 11509,
        GetSpellInfo = hunter_data, current_spell = 2973 })
    era_ST.HUNTER.on_current_spell_cast_changed(era_ST, false)
    eq(era_ST.raptor_strike_queued, true, "queue ERA: the rank id detects the queue")
    local era_strings, era_numbers = token_types(era_tokens.current)
    eq(era_strings, 0, "queue ERA: only bare ids reach IsCurrentSpell")
    check(era_numbers > 0, "queue ERA: the probe ran by id")

    local tbc_ST, tbc_tokens = queue_profile({ project = 5, interface = 20506,
        GetSpellInfo = hunter_data, current_spell = "Raptor Strike" })
    tbc_ST.HUNTER.on_current_spell_cast_changed(tbc_ST, false)
    eq(tbc_ST.raptor_strike_queued, true, "queue TBC: the family name detects the queue")
    local tbc_strings, tbc_numbers = token_types(tbc_tokens.current)
    eq(tbc_numbers, 0, "queue TBC: no bare id reaches IsCurrentSpell")
    check(tbc_strings > 0, "queue TBC: the probe ran by name")

    local wrath_ST, wrath_tokens = queue_profile({ project = 11, interface = 38002,
        GetSpellInfo = hunter_data, current_spell = "Raptor Strike" })
    wrath_ST.HUNTER.on_current_spell_cast_changed(wrath_ST, false)
    eq(wrath_ST.raptor_strike_queued, true,
        "queue WRATH/Titanforge: the family name detects the queue")
    local wrath_strings, wrath_numbers = token_types(wrath_tokens.current)
    eq(wrath_numbers, 0, "queue WRATH/Titanforge: no bare id reaches IsCurrentSpell")
    check(wrath_strings > 0, "queue WRATH/Titanforge: the probe ran by name")

    -- The queue helper deliberately stays one token SHAPE per family: an entry whose
    -- name the client cannot resolve is skipped, never replaced by a mixed id token.
    local cold_ST, cold_tokens = queue_profile({ project = 11, interface = 38002,
        GetSpellInfo = function() return nil end, current_spell = "Raptor Strike" })
    cold_ST.HUNTER.on_current_spell_cast_changed(cold_ST, false)
    eq(cold_ST.raptor_strike_queued, false, "queue cold cache: nothing queues from an unknown token")
    eq(#cold_tokens.current, 0, "queue cold cache: an unknown token spends no probe")
end

--=========================================================================================
-- 5) Static: the approved id fallback is present and must stay
--=========================================================================================
-- The operator's fact is binding: "i never banned fallback to ids." Each helper keeps
-- `... or <id>` on its name-family branch. This catches the regression that removed it.
do
    local function has(rel, snippet)
        local src = read(rel):gsub("\r\n", "\n")
        return src:find(snippet, 1, true) ~= nil
    end
    check(has("compat.lua",
        "if client_family == \"TBC\" then\n\t\t-- classic_anniversary 2.5.6: localized NAME first, id fallback.\n\t\treturn name or id"),
        "compat: get_spell_query keeps the TBC id fallback")
    check(has("compat.lua",
        "elseif client_family == \"WRATH\" then\n\t\t-- classic_titan 3.80.2 (Titanforge): localized NAME first, id fallback.\n\t\treturn name or id"),
        "compat: get_spell_query keeps the WRATH id fallback")
    check(has("compat.lua",
        "local query = api.get_spell_query(name, id) or id"),
        "compat: family_spell_exists keeps the id re-probe")
    check(has("classes/paladin.lua",
        "return api.get_spell_query(name, spell_id) or spell_id"),
        "paladin: spell_query keeps the compat id fallback")
    check(has("classes/paladin.lua", "return name or spell_id"),
        "paladin: spell_query keeps the inline id fallback")
    check(has("classes/warrior.lua",
        "return api.get_spell_query(name, spell_id) or spell_id"),
        "warrior: spell_query keeps the compat id fallback")
    check(has("classes/warrior.lua", "return name or spell_id"),
        "warrior: spell_query keeps the inline id fallback")
    check(has("classes/hunter.lua",
        "return api.get_spell_query(name, spell_id) or spell_id"),
        "hunter: spell_token keeps the compat id fallback")
    check(has("classes/hunter.lua", "return name or spell_id"),
        "hunter: spell_token keeps the inline id fallback")
    check(has("classes/rogue.lua", "return entry.name or entry.id"),
        "rogue: rogue_query keeps the id fallback")
    check(has("classes/shaman.lua", "\t\treturn name or id"),
        "shaman: spell_query keeps the id fallback")
    check(has("classes/druid.lua", "        return name or id"),
        "druid: spell_query keeps the id fallback")
end

--=========================================================================================
-- 6) Every class token helper gates WRATH/Titanforge explicitly (one rule per helper)
--=========================================================================================
-- The compat helper is the shared rule; these pins keep each class's own helper on that
-- rule (the inline fallback branches are load-order protection, so they must carry the
-- same family gate). Exact snippets, normalised to LF: a removed WRATH gate is red.
do
    local function has(rel, snippet)
        local src = read(rel):gsub("\r\n", "\n")
        return src:find(snippet, 1, true) ~= nil
    end
    local paladin_gate = "local function spell_query(spell_id)\n"
        .. "    if st.family ~= \"TBC\" and st.family ~= \"WRATH\" then\n"
        .. "        return spell_id"
    check(has("classes/paladin.lua", paladin_gate),
        "paladin: spell_query gates TBC and WRATH separately")
    check(has("classes/warrior.lua", paladin_gate),
        "warrior: spell_query gates TBC and WRATH separately")
    check(has("classes/rogue.lua",
        "if st.family == \"TBC\" or st.family == \"WRATH\" then\n\t\treturn entry.name or entry.id"),
        "rogue: rogue_query resolves the NAME on TBC and WRATH")
    check(has("classes/hunter.lua",
        "local function spell_token(spell_id)\n    if spell_id == nil then\n        return nil\n"
        .. "    end\n    if st.family ~= \"TBC\" and st.family ~= \"WRATH\" then"),
        "hunter: spell_token gates TBC and WRATH separately")
    check(has("classes/hunter.lua",
        "local function queue_tokens(id_table)\n    if st.family ~= \"TBC\" and st.family ~= \"WRATH\" then"),
        "hunter: queue_tokens follows the same rule")
    check(has("classes/shaman.lua",
        "local function spell_query(id, name)\n\tif st.family == \"TBC\" then\n\t\treturn name or id\n"
        .. "\telseif st.family == \"WRATH\" then\n\t\treturn name or id"),
        "shaman: spell_query resolves the NAME on TBC and WRATH")
    check(has("classes/shaman.lua",
        "local function resolve_family_spell(group)\n\tif st.family == \"TBC\" or st.family == \"WRATH\" then"),
        "shaman: the weave catalogue resolves the NAME on TBC and WRATH")
    check(has("classes/druid.lua",
        "local function spell_query(id, name)\n    if st.family == \"TBC\" then\n        return name or id\n"
        .. "    elseif st.family == \"WRATH\" then\n        return name or id"),
        "druid: spell_query resolves the NAME on TBC and WRATH")
    check(has("classes/druid.lua",
        "    if st.family == \"TBC\" or st.family == \"WRATH\" then\n"
        .. "        -- Name-vs-id: a single NAME probe covers all Maul ranks"),
        "druid: the queued-Maul probe resolves the NAME on TBC and WRATH")
end

print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
os.exit(0)
