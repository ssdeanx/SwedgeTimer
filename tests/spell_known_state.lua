-- Spell knowledge: the deprecated-shim throw on a spell NAME, and the protected
-- interaction-distance call (compat TBC defects, operator in-client evidence 2026-10-21).
--
-- The sandbox models TBC Anniversary 2.5.x: the classic global IsSpellKnown is Blizzard's
-- deprecated shim over C_SpellBook.IsSpellInSpellBook, which throws unless its argument is
-- a numeric spell id ("bad argument #1 to 'IsSpellInSpellBook' (outside of expected
-- range ...)"). The real compat.lua runs over that sandbox, so every check below is the
-- shipped code path, not a copy of it.
--
-- The resolution is LAZY by design: the caller's token is probed as given first (on the
-- clients where a name is the query form that keeps the exact answer source), and only a
-- THROWING probe triggers the one-time name -> id resolution, after which that same probe
-- is retried with the id. A numeric token is never resolved.
--
-- Pins:
--   1. api.is_spell_known("Kill Shot") does not throw; the name is resolved to the
--      NUMERIC id and the probe answers true/false through the deprecated shim.
--   2. api.is_spell_known("No Such Spell") is false and the state is false, "unknown":
--      no throw, no guess, no id retry.
--   3. api.is_spell_known(<number>) probes with that number (no resolution, no change).
--   4. A throwing probe is skipped and the next probe answers; the caller never sees a
--      throw, and with every probe throwing the state is still false, "unknown".
--   5. A non-(number|string) token is false, "unknown" without touching a probe.
--   6. compat.lua contains no interaction-distance call (static scan), and its comment
--      records why: the function is protected on TBC Anniversary, operator evidence
--      2026-10-21 (the removal cannot silently regress).
--
-- Plain Lua 5.1, no WoW client needed. Run from the repo root:
--   lua5.1 tests/spell_known_state.lua

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

-- Secret sentinels: a restricted id keeps its numeric type (so only the is_secret guard
-- can stop it), and a restricted probe answer must be skipped, not compared.
local SECRET_ID = 987654
local SECRET_ANSWER = "secret-answer"

-- ---------------------------------------------------------------------------
-- Sandbox builder: the real compat.lua over the TBC deprecated-shim profile
-- ---------------------------------------------------------------------------
-- profile switches:
--   known                 table of numeric ids the client answers as learned
--   names                 name -> id map GetSpellInfo resolves (default: Kill Shot)
--   classic_throws        IsSpellKnown throws on every argument
--   classic_declines      IsSpellKnown declines (returns nil, the chain moves on)
--   classic_secret_answer IsSpellKnown returns a restricted (secret) answer
--   book_throws           C_SpellBook.IsSpellKnown throws on a valid id too
--   sibling_throws        C_SpellBook.IsSpellKnownOrInSpellBook throws on a valid id
--   no_classic            no classic global (the Mainline-code shape)
--   no_spellbook          no C_SpellBook namespace at all
--   secret_id             GetSpellInfo answers a restricted numeric id
local function build(profile)
    profile = profile or {}
    local sb = {
        known = profile.known or { [20904] = true },
        names = profile.names or { ["Kill Shot"] = 20904 },
        classic_calls = {},
        shim_calls = {},
        book_calls = {},
        sibling_calls = {},
        get_spell_info_calls = {},
    }
    local by_id = {}
    for name, id in pairs(sb.names) do
        by_id[id] = name
    end

    local env = setmetatable({}, { __index = _G })
    env._G = env -- compat reads legacy globals through rawget(_G, ...)
    env.WOW_PROJECT_ID = profile.project or 5
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.issecretvalue = function(value)
        return value == SECRET_ID or value == SECRET_ANSWER
    end

    -- GetSpellInfo: classic shape (name, rank, icon, castTime, minRange, maxRange, id).
    -- Resolves a known name to its id, answers nil for an unknown name or id.
    env.GetSpellInfo = function(token)
        sb.get_spell_info_calls[#sb.get_spell_info_calls + 1] = token
        if type(token) == "number" then
            local name = by_id[token]
            if name == nil then
                return nil
            end
            return name, nil, 134400, 0, 5, 35, token
        end
        if type(token) == "string" then
            local id = sb.names[token]
            if id == nil then
                return nil
            end
            if profile.secret_id then
                id = SECRET_ID
            end
            return token, nil, 134400, 0, 5, 35, id
        end
        return nil
    end

    -- The client spellbook namespace. Its probes are id-only: a name is not a valid
    -- argument there either (C_SpellBook documents spellID), so every probe below
    -- rejects a non-number BEFORE it can answer.
    env.C_SpellBook = {}
    local function reject_non_id(spell_id, api_name)
        if type(spell_id) ~= "number" then
            error("bad argument #1 to '" .. api_name .. "' (outside of expected range - got "
                .. type(spell_id) .. ")", 3)
        end
        if spell_id ~= math.floor(spell_id) or spell_id < 1 or spell_id > 1000000 then
            error("bad argument #1 to '" .. api_name .. "' (outside of expected range - got "
                .. tostring(spell_id) .. ")", 3)
        end
    end
    env.C_SpellBook.IsSpellInSpellBook = function(spell_id)
        sb.shim_calls[#sb.shim_calls + 1] = spell_id
        reject_non_id(spell_id, "IsSpellInSpellBook")
        return sb.known[spell_id] == true
    end

    if not profile.no_classic then
        env.IsSpellKnown = function(spell_id)
            sb.classic_calls[#sb.classic_calls + 1] = spell_id
            if profile.classic_throws then
                error("the deprecated shim exploded", 2)
            end
            if profile.classic_secret_answer then
                return SECRET_ANSWER
            end
            if profile.classic_declines then
                return nil
            end
            return env.C_SpellBook.IsSpellInSpellBook(spell_id)
        end
    end

    if not profile.no_spellbook then
        env.C_SpellBook.IsSpellKnown = function(spell_id)
            sb.book_calls[#sb.book_calls + 1] = spell_id
            reject_non_id(spell_id, "C_SpellBook.IsSpellKnown")
            if profile.book_throws then
                error("C_SpellBook.IsSpellKnown exploded", 2)
            end
            return sb.known[spell_id] == true
        end
        env.C_SpellBook.IsSpellKnownOrInSpellBook = function(spell_id)
            sb.sibling_calls[#sb.sibling_calls + 1] = spell_id
            reject_non_id(spell_id, "C_SpellBook.IsSpellKnownOrInSpellBook")
            if profile.sibling_throws then
                error("C_SpellBook.IsSpellKnownOrInSpellBook exploded", 2)
            end
            return sb.known[spell_id] == true
        end
    end

    local st = {}
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    local ok, err = pcall(compat, "SwedgeTimer", st)
    check(ok, "compat.lua loads over the deprecated-shim sandbox (" .. tostring(err) .. ")")
    return st.api, sb
end

local function no_probe_calls(sb, label)
    eq(#sb.classic_calls, 0, label .. ": the classic probe was not called")
    eq(#sb.shim_calls, 0, label .. ": the deprecated shim target was not called")
    eq(#sb.book_calls, 0, label .. ": C_SpellBook.IsSpellKnown was not called")
    eq(#sb.sibling_calls, 0, label .. ": the sibling probe was not called")
end

-- Exact call sequence: value and type per position (a name and an id never compare equal
-- by accident: they are different types).
local function only_args(calls, want, label)
    eq(#calls, #want, label .. ": call count")
    for i = 1, #want do
        eq(calls[i], want[i], label .. ": argument #" .. i)
        eq(type(calls[i]), type(want[i]), label .. ": argument #" .. i .. " keeps its type")
    end
end

--=========================================================================================
-- 1. The failing in-client case: a NAME on the TBC deprecated shim
--=========================================================================================
local api1, sb1 = build({})
local ok1, known1 = pcall(api1.is_spell_known, "Kill Shot")
check(ok1, "TBC name: api.is_spell_known('Kill Shot') does not throw (" .. tostring(known1) .. ")")
eq(known1, true, "TBC name: the known spell answers true")
only_args(sb1.classic_calls, { "Kill Shot", 20904 },
    "TBC name: the classic probe got the name, then the resolved id")
only_args(sb1.shim_calls, { "Kill Shot", 20904 },
    "TBC name: the deprecated shim rejected the name, then answered the id")
eq(#sb1.book_calls, 0, "TBC name: C_SpellBook.IsSpellKnown is not consulted when the chain answers")
eq(#sb1.sibling_calls, 0, "TBC name: the sibling probe is not consulted when the chain answers")
eq(#sb1.get_spell_info_calls, 1, "TBC name: exactly one resolution call")
eq(sb1.get_spell_info_calls[1], "Kill Shot", "TBC name: the resolution went through api.GetSpellInfo")

-- The state form: same lazy sequence, tri-state answer.
local api1b, sb1b = build({})
local name_flag, name_state = api1b.is_spell_known_state("Kill Shot")
eq(name_flag, true, "TBC name state: a known spell answers true")
eq(name_state, "known", "TBC name state: a known spell reads the 'known' state")
only_args(sb1b.classic_calls, { "Kill Shot", 20904 },
    "TBC name state: the classic probe got the name, then the resolved id")
eq(#sb1b.get_spell_info_calls, 1, "TBC name state: the state form resolved the name exactly once")

-- The same name, but this player has not learned it: the shim's false is an ANSWER.
local api1c, sb1c = build({})
sb1c.known[20904] = false
local unlearned_flag, unlearned_state = api1c.is_spell_known_state("Kill Shot")
eq(unlearned_flag, false, "TBC name: an unlearned spell answers false")
eq(unlearned_state, "not_known",
    "TBC name: an answered 'no' reads the 'not_known' state, not 'unknown'")
only_args(sb1c.shim_calls, { "Kill Shot", 20904 },
    "TBC name: the shim was asked the name, then the id, and answered false")
eq(#sb1c.book_calls, 0, "TBC name: an answered 'no' ends the chain")

--=========================================================================================
-- 2. A name that resolves to nothing: false, "unknown", never a guess or a throw
--=========================================================================================
local api2, sb2 = build({})
local ok_missing, missing = pcall(api2.is_spell_known, "No Such Spell")
check(ok_missing, "unknown name: api.is_spell_known('No Such Spell') does not throw ("
    .. tostring(missing) .. ")")
eq(missing, false, "unknown name: the answer is false")
eq(type(missing), "boolean", "unknown name: the answer is a boolean, never nil")
eq(#sb2.get_spell_info_calls, 1, "unknown name: the name was resolved exactly once")
eq(sb2.get_spell_info_calls[1], "No Such Spell", "unknown name: the resolution used the name")
only_args(sb2.classic_calls, { "No Such Spell" },
    "unknown name: each probe saw only the original token, never an id retry")
only_args(sb2.shim_calls, { "No Such Spell" }, "unknown name: the shim saw only the name")
only_args(sb2.book_calls, { "No Such Spell" }, "unknown name: the book probe saw only the name")
only_args(sb2.sibling_calls, { "No Such Spell" }, "unknown name: the sibling saw only the name")

local api2b, sb2b = build({})
local missing_flag, missing_state = api2b.is_spell_known_state("No Such Spell")
eq(missing_flag, false, "unknown name state: the answer is false")
eq(missing_state, "unknown", "unknown name state: the state says unknown - no guess")
eq(#sb2b.get_spell_info_calls, 1, "unknown name state: one resolution for the whole probe chain")
only_args(sb2b.classic_calls, { "No Such Spell" },
    "unknown name state: no probe was retried with a nil id")

--=========================================================================================
-- 3. A numeric token keeps the old behaviour: probe with exactly that number, no resolution
--=========================================================================================
local api3, sb3 = build({})
eq(api3.is_spell_known(20904), true, "numeric token: the known id answers true")
only_args(sb3.classic_calls, { 20904 }, "numeric token: the classic probe received the number")
only_args(sb3.shim_calls, { 20904 }, "numeric token: the shim received the same number")
eq(#sb3.get_spell_info_calls, 0, "numeric token: no name resolution was attempted")

local api3b, sb3b = build({ known = {} })
local id_flag, id_state = api3b.is_spell_known_state(20904)
eq(id_flag, false, "numeric token: an unknown id answers false")
eq(id_state, "not_known", "numeric token: the client answered 'no', so not_known")
only_args(sb3b.classic_calls, { 20904 }, "numeric token: the unknown id was probed exactly once")
eq(#sb3b.get_spell_info_calls, 0, "numeric token: an answered 'no' resolves nothing")

-- A numeric token whose first probe throws: a number is never resolved as a name.
local api3c, sb3c = build({ classic_throws = true })
eq(api3c.is_spell_known(20904), true,
    "numeric token + throwing probe: the next probe answers")
only_args(sb3c.classic_calls, { 20904 },
    "numeric token + throwing probe: the number was probed exactly once, never retried")
only_args(sb3c.book_calls, { 20904 },
    "numeric token + throwing probe: the next probe got the number")
eq(#sb3c.get_spell_info_calls, 0,
    "numeric token + throwing probe: a throw never resolves a number as a name")

--=========================================================================================
-- 4. Throwing probes: skipped, the next probe answers, the caller never sees a throw
--=========================================================================================
local api4, sb4 = build({ classic_throws = true })
local ok_throw, throw_known = pcall(api4.is_spell_known, "Kill Shot")
check(ok_throw, "throwing probe: the caller sees no throw (" .. tostring(throw_known) .. ")")
eq(throw_known, true, "throwing probe: the next probe's answer comes back")
only_args(sb4.classic_calls, { "Kill Shot", 20904 },
    "throwing probe: the throwing probe saw the name, then the id retry")
only_args(sb4.book_calls, { "Kill Shot", 20904 },
    "throwing probe: the next probe also saw the name, then the id retry")
eq(#sb4.shim_calls, 0, "throwing probe: the shim never ran (the probe threw before forwarding)")
eq(#sb4.get_spell_info_calls, 1, "throwing probe: one resolution for the whole chain")

-- The modern probe itself throws: the sibling still answers (the classic probe declines).
local api5, sb5 = build({ classic_declines = true, book_throws = true })
local ok_book, book_known = pcall(api5.is_spell_known, "Kill Shot")
check(ok_book, "throwing modern probe: the caller sees no throw (" .. tostring(book_known) .. ")")
eq(book_known, true, "throwing modern probe: the sibling probe's answer comes back")
only_args(sb5.classic_calls, { "Kill Shot" },
    "throwing modern probe: a declining probe is called once and never resolved")
only_args(sb5.book_calls, { "Kill Shot", 20904 },
    "throwing modern probe: the book probe saw the name, then the id retry")
only_args(sb5.sibling_calls, { "Kill Shot", 20904 },
    "throwing modern probe: the sibling received the name, then the id")
eq(#sb5.get_spell_info_calls, 1, "throwing modern probe: the throw triggered the one resolution")

-- Every probe throws: the answer is the fail-closed unknown, still no throw.
local api6, sb6 = build({ classic_throws = true, book_throws = true, sibling_throws = true })
local ok_all, all_known = pcall(api6.is_spell_known, "Kill Shot")
check(ok_all, "all probes throw: the caller sees no throw (" .. tostring(all_known) .. ")")
eq(all_known, false, "all probes throw: the boolean answers false (fail-closed)")
only_args(sb6.classic_calls, { "Kill Shot", 20904 },
    "all probes throw: the classic probe still ran first, name then id")
only_args(sb6.book_calls, { "Kill Shot", 20904 },
    "all probes throw: the book probe ran second, name then id")
only_args(sb6.sibling_calls, { "Kill Shot", 20904 },
    "all probes throw: the sibling probe ran third, name then id")
eq(#sb6.get_spell_info_calls, 1, "all probes throw: resolution happened exactly once")

local api6b, sb6b = build({ classic_throws = true, book_throws = true, sibling_throws = true })
local all_flag, all_state = api6b.is_spell_known_state("Kill Shot")
eq(all_flag, false, "all probes throw: the state answer is false")
eq(all_state, "unknown", "all probes throw: the state says unknown, never a guess")
only_args(sb6b.classic_calls, { "Kill Shot", 20904 },
    "all probes throw state: the same name-then-id sequence")
eq(#sb6b.get_spell_info_calls, 1, "all probes throw state: one resolution for the whole chain")

-- Restricted probe answers are not compared: they are "no answer", so the next probe wins.
local api7, sb7 = build({ classic_secret_answer = true })
local secret_flag, secret_state = api7.is_spell_known_state("Kill Shot")
eq(secret_flag, true, "secret probe answer: the next probe answers instead of comparing a secret")
eq(secret_state, "known", "secret probe answer: the state is the answering probe's")
only_args(sb7.classic_calls, { "Kill Shot" },
    "secret probe answer: the probe answered the name, so it was never retried")
only_args(sb7.book_calls, { "Kill Shot", 20904 },
    "secret probe answer: the next probe saw the name (throw), then the id")
eq(#sb7.get_spell_info_calls, 1, "secret probe answer: resolution came from the next probe's throw")

--=========================================================================================
-- 5. Every non-(number|string) token: false, "unknown", no probe, no throw
--=========================================================================================
local api8, sb8 = build({})
local function unknown_token(token, label)
    local state_ok, token_flag, token_state = pcall(api8.is_spell_known_state, token)
    check(state_ok, label .. ": the state form does not throw")
    eq(token_flag, false, label .. ": the state answer is false")
    eq(token_state, "unknown", label .. ": the state says unknown")
    local bool_ok, bool_answer = pcall(api8.is_spell_known, token)
    check(bool_ok, label .. ": the boolean form does not throw")
    eq(bool_answer, false, label .. ": the boolean form answers false")
    eq(type(bool_answer), "boolean", label .. ": the boolean form is a boolean, never nil")
end
unknown_token(nil, "nil token")
unknown_token(true, "boolean token")
unknown_token({}, "table token")
unknown_token(print, "function token")
no_probe_calls(sb8, "non-token")
eq(#sb8.get_spell_info_calls, 0, "non-token: no name resolution was attempted")

-- A restricted id form is unknown too (a secret value is never probed or compared).
local api9, sb9 = build({ secret_id = true, known = { [SECRET_ID] = true } })
local ok_secret_id, secret_id_bool = pcall(api9.is_spell_known, "Kill Shot")
check(ok_secret_id, "secret id: the boolean form does not throw")
eq(secret_id_bool, false, "secret id: a restricted resolution answers false")
local secret_id_flag, secret_id_state = api9.is_spell_known_state("Kill Shot")
eq(secret_id_flag, false, "secret id: a restricted resolution answers false in the state form")
eq(secret_id_state, "unknown", "secret id: a restricted resolution is unknown, never a guess")
only_args(sb9.classic_calls, { "Kill Shot", "Kill Shot" },
    "secret id: the probes only ever saw the name, never the restricted id")
only_args(sb9.shim_calls, { "Kill Shot", "Kill Shot" },
    "secret id: the shim only ever saw the name")
only_args(sb9.book_calls, { "Kill Shot", "Kill Shot" },
    "secret id: the book probe was called once per state call, never retried")
only_args(sb9.sibling_calls, { "Kill Shot", "Kill Shot" },
    "secret id: the sibling was called once per state call, never retried")
eq(#sb9.get_spell_info_calls, 2, "secret id: each state call resolved the name exactly once")

--=========================================================================================
-- 6. Probe order on the Mainline-code shape (no classic global)
--=========================================================================================
local api10, sb10 = build({ no_classic = true })
local ok10, answer10 = pcall(api10.is_spell_known, "Kill Shot")
check(ok10, "mainline shape: a name does not throw (" .. tostring(answer10) .. ")")
eq(answer10, true, "mainline shape: the name resolves and C_SpellBook answers")
only_args(sb10.book_calls, { "Kill Shot", 20904 },
    "mainline shape: C_SpellBook.IsSpellKnown saw the name (throw), then the id")
eq(#sb10.classic_calls, 0, "mainline shape: no classic probe exists to call")
eq(#sb10.shim_calls, 0, "mainline shape: no classic shim exists to call")
eq(#sb10.sibling_calls, 0, "mainline shape: the sibling is not consulted when the first probe answers")
eq(#sb10.get_spell_info_calls, 1, "mainline shape: the throw triggered the one resolution")

-- A client with no probe at all still answers false, "unknown" (the fail-closed contract).
local api11, sb11 = build({ no_classic = true, no_spellbook = true })
eq(api11.is_spell_known("Kill Shot"), false,
    "probe-less client: the boolean is false (fail-closed)")
local none_flag, none_state = api11.is_spell_known_state("Kill Shot")
eq(none_flag, false, "probe-less client: the state answer is false")
eq(none_state, "unknown", "probe-less client: the state says unknown - the client cannot answer")
eq(#sb11.get_spell_info_calls, 0,
    "probe-less client: nothing threw, so the name was never resolved")

--=========================================================================================
-- 7. Static: the protected interaction-distance call stays gone, and the comments keep WHY
--=========================================================================================
do
    local f = assert(io.open(ROOT .. "compat.lua", "r"))
    local src = f:read("*a")
    f:close()

    check(src:find("CheckInteractDistance", 1, true) == nil,
        "static: compat.lua contains no interaction-distance call (the protected API is gone)")
    check(src:find("api.CheckInteractDistance", 1, true) == nil,
        "static: no api.CheckInteractDistance wrapper exists (not even a nil stub)")

    local distance_start = src:find("-- Interaction distance", 1, true)
    local distance_stop = src:find("-- Unit distance (exact)", 1, true)
    check(distance_start ~= nil and distance_stop ~= nil and distance_stop > distance_start,
        "static: the interaction-distance comment block exists and is bounded")
    local distance_block = src:sub(distance_start or 1, (distance_stop or 1) - 1)
    check(distance_block:find("protected", 1, true) ~= nil,
        "static: the comment records WHY the client function cannot ship (protected)")
    check(distance_block:find("ADDON_ACTION_BLOCKED", 1, true) ~= nil,
        "static: the comment records the in-client failure shape")
    check(distance_block:find("2026-10-21", 1, true) ~= nil,
        "static: the comment carries the operator evidence date")
    check(distance_block:find("UnitDistance", 1, true) ~= nil,
        "static: the comment names the only remaining distance source")
    check(distance_block:find("UnitPopupSharedUtils.lua:194", 1, true) ~= nil,
        "static: the comment cites Blizzard's only caller (secure popup code)")
    check(distance_block:find("classic_anniversary", 1, true) ~= nil,
        "static: the caller citation names the wow-ui-source branch")
    check(distance_block:find("PlayerScriptDocumentation.lua:101", 1, true) ~= nil,
        "static: the comment cites the generated API doc")
    check(distance_block:find("protection marker", 1, true) ~= nil,
        "static: the comment records that the protection is NOT documented")

    local unit_stop = src:find("-- Movement speed and motion", 1, true)
    check(distance_stop ~= nil and unit_stop ~= nil and unit_stop > distance_stop,
        "static: the unit-distance comment block exists and is bounded")
    local unit_block = src:sub(distance_stop or 1, (unit_stop or 1) - 1)
    check(unit_block:find("CompactUnitFrame.lua:1069", 1, true) ~= nil,
        "static: the unit-distance comment cites Blizzard's own consumer")
    check(unit_block:find("checkedDistance", 1, true) ~= nil,
        "static: the unit-distance comment records the checked flag contract")

    local known_start = src:find("-- Spell knowledge", 1, true)
    local known_stop = src:find("-- Spell cooldowns", 1, true)
    check(known_start ~= nil and known_stop ~= nil and known_stop > known_start,
        "static: the spell-knowledge section exists and is bounded")
    local known_block = src:sub(known_start or 1, (known_stop or 1) - 1)
    check(known_block:find("deprecated shim", 1, true) ~= nil,
        "static: the comment names the TBC deprecated shim")
    check(known_block:find("id-only", 1, true) ~= nil,
        "static: the comment records that the shim is id-only")
    check(known_block:find("2026-10-21", 1, true) ~= nil,
        "static: the comment carries the in-client evidence date")
    check(known_block:find("spell_known_name_id", 1, true) ~= nil,
        "static: the one name-resolution helper is named in the section")
    check(known_block:find("pcall(spell_known_probes[i], spell_id)", 1, true) ~= nil,
        "static: the original-token probe call is pcall-wrapped")
    check(known_block:find("pcall(spell_known_probes[i], fallback_id)", 1, true) ~= nil,
        "static: the id-retry probe call is pcall-wrapped")
end

--=========================================================================================
print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)
