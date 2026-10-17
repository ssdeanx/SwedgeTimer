-- tests/lrc_guard_state.lua: offline execution tests for the vendored LibRangeCheck-2.0
-- guard package (the Mainline-code non-throwing combination).
--
-- The IsEventValid event guards (pinned in tests/secret_guard_state.lua) let the vendored
-- lib's activate() complete on Retail / WoW Forever, which for the first time runs its
-- internals there. Those internals read classic-only globals (GetNumSpellTabs /
-- GetSpellTabInfo, IsSpellInRange, CheckInteractDistance) that are gone on Mainline-code
-- clients. This suite executes the REAL lib file under Mainline-like client stubs and
-- proves the guards are load-bearing: the real file loads, inits and polls without
-- throwing, while a copy written to /tmp/opencode with a guard removed fails the same
-- behaviour (the mutation is the bite-proof; the addon never loads it).
--
-- Covered:
--   1. Static pins: the exact guard counts in the vendored file (1 spellbook guard,
--      4 IsSpellInRange guards + 4 non-number/secret checks, 2 CheckInteractDistance
--      guards, the rawget issecretvalue probe) and the untouched event guards.
--   2. Retail-like profile (no spellbook, no IsSpellInRange; CheckInteractDistance
--      present): the lib loads, activates, and init()/findSpellIndex()/GetRange()/checker
--      calls return without throwing. Bite: the getNumSpells guard removed -> init()
--      throws.
--   3. Mixed profile (spellbook present, IsSpellInRange absent): the harm checker returns
--      nil (unknown). Bite: the IsSpellInRange absence guards removed -> the checker call
--      throws.
--   4. Secret reading (issecretvalue flagged): the checker reports unknown (nil) instead
--      of comparing, while honest readings keep the exact pre-guard results (1 -> true;
--      0 -> the min-range fallback with both return values). Bite: the non-number/secret
--      checks removed -> a secret reading is wrongly treated as an honest reading.
--   5. No CheckInteractDistance: the interact checker returns nil. Bite: the interact
--      guard removed -> the checker call throws.
--
-- Run from the repo root: lua5.1 tests/lrc_guard_state.lua  (any cwd works).

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"
local LIB_PATH = ROOT .. "Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua"
local TMP_DIR = "/tmp/opencode"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL  " .. label)
    end
end
local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

--=========================================================================================
-- Helpers: file text, static counts, mutations, /tmp/opencode copies
--=========================================================================================
local function read_file(path)
    local f = assert(io.open(path, "r"), "cannot read " .. path)
    local text = f:read("*a")
    f:close()
    return text
end

-- Count of a plain-text needle; the static pins below assert exact counts so a guard
-- that silently disappears (or is duplicated) fails loudly.
local function count_plain(src, needle)
    local count, pos = 0, 1
    while true do
        local at = src:find(needle, pos, true)
        if not at then break end
        count = count + 1
        pos = at + #needle
    end
    return count
end

-- Remove every occurrence of a plain-text needle; returns the mutated source and the
-- replacement count so the caller can assert the needle was really there.
local function remove_all(src, needle)
    local parts, count = {}, 0
    local pos = 1
    while true do
        local at = src:find(needle, pos, true)
        if not at then break end
        parts[#parts + 1] = src:sub(pos, at - 1)
        pos = at + #needle
        count = count + 1
    end
    parts[#parts + 1] = src:sub(pos)
    return table.concat(parts), count
end

local function write_tmp(name, source)
    os.execute("mkdir -p " .. TMP_DIR .. " >/dev/null 2>&1")
    local path = TMP_DIR .. "/" .. name
    local f = assert(io.open(path, "wb"), "cannot write " .. path)
    f:write(source)
    f:close()
    return path
end

--=========================================================================================
-- Sandbox: one throwaway Mainline-like client per load
--=========================================================================================
local function make_frame(sb)
    local f = {}
    function f:RegisterEvent(name) sb.events[name] = true end
    function f:RegisterUnitEvent(name) sb.events[name] = true end
    function f:UnregisterEvent(name) sb.events[name] = nil end
    function f:IsEventRegistered(name) return sb.events[name] == true end
    function f:SetScript(script, fn)
        self.scripts = self.scripts or {}
        self.scripts[script] = fn
    end
    function f:Show() end
    function f:Hide() end
    return f
end

-- Profile keys:
--   class            player class for UnitClass (default WARRIOR)
--   spellbook        true -> classic GetNumSpellTabs/GetSpellTabInfo/GetSpellBookItemName
--   spell_name       what GetSpellBookItemName answers (default "Intimidating Shout")
--   is_spell_in_range true -> classic IsSpellInRange global (reads sb.spell_in_range)
--   check_interact   true -> CheckInteractDistance global (reads sb.interact)
--   spell_info       id -> { name, minRange, maxRange } served via C_Spell.GetSpellInfo
--   issecretvalue    the client secret probe (absent on every classic client)
local function make_sb(profile)
    profile = profile or {}
    local sb = { events = {} }
    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.WOW_PROJECT_ID = 1
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_MAINLINE = 1
    env.C_EventUtils = { IsEventValid = function() return true end }
    env.CreateFrame = function() return make_frame(sb) end
    env.UnitClass = function() return "Warrior", profile.class or "WARRIOR" end
    env.UnitRace = function() return "Human", "Human" end
    env.GetInventorySlotInfo = function() return 16 end
    env.GetInventoryItemLink = function() return nil end
    env.GetTime = function() return 100 end
    env.UnitExists = function() return true end
    env.UnitCanAttack = function() return false end
    env.UnitCanAssist = function() return false end
    env.UnitIsDeadOrGhost = function() return false end
    env.UnitIsVisible = function() return true end
    env.BOOKTYPE_SPELL = "spell"
    -- WoW's global aliases (the lib uses the bare globals at load and captures them).
    env.tinsert = table.insert
    env.tremove = table.remove
    env.wipe = function(t)
        for i = #t, 1, -1 do t[i] = nil end
        return t
    end
    env.C_Item = {
        GetItemInfo = function() return nil end,
        IsItemInRange = function() return false end,
    }
    env.C_Spell = {
        GetSpellInfo = function(id)
            local info = profile.spell_info and profile.spell_info[id]
            if not info then return nil end
            return {
                name = info.name,
                minRange = info.minRange or 0,
                maxRange = info.maxRange or 0,
                spellID = id,
            }
        end,
    }
    if profile.spellbook then
        env.GetNumSpellTabs = function() return 1 end
        env.GetSpellTabInfo = function() return "General", nil, 0, 3 end
        env.GetSpellBookItemName = function() return profile.spell_name or "Intimidating Shout" end
    end
    if profile.is_spell_in_range then
        env.IsSpellInRange = function() return sb.spell_in_range end
    end
    if profile.check_interact then
        env.CheckInteractDistance = function() return sb.interact end
    end
    if profile.issecretvalue then
        env.issecretvalue = profile.issecretvalue
    end
    env.LibStub = {
        NewLibrary = function(_, major)
            sb.library = {}
            return sb.library
        end,
    }
    sb.env = env
    return sb
end

-- Compile + run a lib source in the sandbox environment; returns lib or nil + error.
local function load_source(sb, source, chunkname)
    local chunk, err = loadstring(source, chunkname)
    if not chunk then return nil, "compile error: " .. tostring(err) end
    setfenv(chunk, sb.env)
    local ok, load_err = pcall(chunk)
    if not ok then return nil, "load error: " .. tostring(load_err) end
    return sb.library, nil
end

local function load_path(sb, path)
    return load_source(sb, read_file(path), "@" .. path)
end

--=========================================================================================
-- 1) Static pins: the guard counts in the vendored file
--=========================================================================================
local REAL_SRC = read_file(LIB_PATH)
-- The vendored file is uniformly CRLF in the tree; the mutation machinery works on an
-- LF-normalized copy so the multi-line needles below can be written naturally (Lua does
-- not care about line endings, and the /tmp/opencode copies are LF by construction).
local REAL_LF = REAL_SRC:gsub("\r\n", "\n")

eq(count_plain(REAL_SRC, 'type(GetSpellTabInfo) ~= "function" or type(GetNumSpellTabs) ~= "function"'), 1,
    "static pin: one spellbook-absence guard in getNumSpells")
eq(count_plain(REAL_SRC, 'if type(IsSpellInRange) ~= "function" then'), 4,
    "static pin: all four IsSpellInRange sites guard the missing global")
eq(count_plain(REAL_SRC, 'if type(r) ~= "number" or (issecretvalue and issecretvalue(r)) then'), 4,
    "static pin: all four IsSpellInRange sites reject non-number/secret readings")
eq(count_plain(REAL_SRC, 'if type(CheckInteractDistance) ~= "function" then'), 2,
    "static pin: both CheckInteractDistance sites guard the missing global")
eq(count_plain(REAL_SRC, 'local issecretvalue = rawget(_G, "issecretvalue")'), 1,
    "static pin: the lib probes issecretvalue itself (it loads before compat)")
-- The just-landed event guards stay intact (secret_guard_state.lua owns the full pin).
eq(count_plain(REAL_SRC, 'C_EventUtils.IsEventValid("LEARNED_SPELL_IN_TAB")'), 1,
    "static pin: the LEARNED_SPELL_IN_TAB event guard is intact")
eq(count_plain(REAL_SRC, 'C_EventUtils.IsEventValid("PLAYER_TALENT_UPDATE")'), 1,
    "static pin: the PLAYER_TALENT_UPDATE event guard is intact")

--=========================================================================================
-- 2) Retail-like profile: no spellbook, no IsSpellInRange
--=========================================================================================
local profile_retail = {
    spellbook = false,
    is_spell_in_range = false,
    check_interact = true,
    spell_info = { [5246] = { name = "Intimidating Shout", minRange = 0, maxRange = 8 } },
}
do
    local sb = make_sb(profile_retail)
    sb.interact = false
    local lib, err = load_path(sb, LIB_PATH)
    check(lib ~= nil, "retail-like: the real lib loads (" .. tostring(err) .. ")")
    if lib then
        check(sb.events["LEARNED_SPELL_IN_TAB"] == true,
            "retail-like: activate() completed and registered its events")
        local ok, init_err = pcall(lib.init, lib)
        check(ok, "retail-like: init() does not throw (" .. tostring(init_err) .. ")")
        local ok_idx, idx = pcall(lib.findSpellIndex, lib, 5246)
        check(ok_idx, "retail-like: findSpellIndex() does not throw (" .. tostring(idx) .. ")")
        eq(idx, nil, "retail-like: a missing spellbook reports no spell index")
        local ok_range, min_range, max_range = pcall(lib.GetRange, lib, "target")
        check(ok_range, "retail-like: GetRange() does not throw (" .. tostring(min_range) .. ")")
        eq(min_range, 28, "retail-like: the interact checker list still answers (28)")
        eq(max_range, nil, "retail-like: out of every checker reports no max range")
        local checker = lib:GetHarmMinChecker(2)
        check(type(checker) == "function", "retail-like: a harm checker resolves")
        local ok_check, result = pcall(checker, "target")
        check(ok_check, "retail-like: the checker call does not throw (" .. tostring(result) .. ")")
        eq(result, nil, "retail-like: a missing IsSpellInRange reports unknown (nil)")
    end
end

-- Bite: strip the getNumSpells guard; init() must now throw on the same profile.
local guard_spellbook =
    '  if type(GetSpellTabInfo) ~= "function" or type(GetNumSpellTabs) ~= "function" then\n'
    .. '    return 0\n'
    .. '  end\n'
do
    local mutated, removed = remove_all(REAL_LF, guard_spellbook)
    eq(removed, 1, "bite setup: the getNumSpells guard text is present once")
    local tmp = write_tmp("lrc-guard-spellbook.lua", mutated)
    local sb = make_sb(profile_retail)
    sb.interact = false
    local lib, err = load_path(sb, tmp)
    check(lib ~= nil, "bite: the guard-stripped copy still loads (" .. tostring(err) .. ")")
    if lib then
        check(type(lib.init) == "function", "bite: the guard-stripped copy still has init()")
        local ok = pcall(lib.init, lib)
        check(not ok, "bite: with the getNumSpells guard removed, init() throws")
    end
end

--=========================================================================================
-- 3) Mixed profile: spellbook present, IsSpellInRange absent
--=========================================================================================
local profile_mixed = {
    spellbook = true,
    spell_name = "Intimidating Shout",
    is_spell_in_range = false,
    check_interact = true,
    spell_info = { [5246] = { name = "Intimidating Shout", minRange = 0, maxRange = 8 } },
}
do
    local sb = make_sb(profile_mixed)
    sb.interact = false
    local lib, err = load_path(sb, LIB_PATH)
    check(lib ~= nil, "mixed: the real lib loads (" .. tostring(err) .. ")")
    if lib then
        local ok, init_err = pcall(lib.init, lib)
        check(ok, "mixed: init() resolves the spellbook spell without throwing ("
            .. tostring(init_err) .. ")")
        local checker = lib:GetHarmMinChecker(2)
        check(type(checker) == "function", "mixed: a spell harm checker resolves")
        local ok_check, result = pcall(checker, "target")
        check(ok_check, "mixed: the checker call does not throw (" .. tostring(result) .. ")")
        eq(result, nil, "mixed: a missing IsSpellInRange reports unknown (nil)")
    end
end

-- Bite: strip the 6-space IsSpellInRange absence guards (the two checker sites); the
-- checker call must now throw on the same profile.
local guard_isr_6 =
    '      if type(IsSpellInRange) ~= "function" then\n'
    .. '        return nil\n'
    .. '      end\n'
do
    local mutated, removed = remove_all(REAL_LF, guard_isr_6)
    eq(removed, 2, "bite setup: the 6-space IsSpellInRange guard text is present twice")
    local tmp = write_tmp("lrc-guard-isrange.lua", mutated)
    local sb = make_sb(profile_mixed)
    sb.interact = false
    local lib, err = load_path(sb, tmp)
    check(lib ~= nil, "bite: the IsSpellInRange-stripped copy still loads (" .. tostring(err) .. ")")
    if lib then
        local ok = pcall(lib.init, lib)
        check(ok, "bite: the IsSpellInRange-stripped copy still inits")
        local checker = lib:GetHarmMinChecker(2)
        check(type(checker) == "function", "bite: the stripped copy still resolves a checker")
        local ok_check = pcall(checker, "target")
        check(not ok_check, "bite: with the IsSpellInRange guard removed, the checker call throws")
    end
end

--=========================================================================================
-- 4) Secret reading: report unknown instead of comparing; honest readings unchanged
--=========================================================================================
local SECRET_RANGE = 900001
local profile_secret = {
    spellbook = true,
    spell_name = "Charge",
    is_spell_in_range = true,
    check_interact = true,
    spell_info = { [100] = { name = "Charge", minRange = 8, maxRange = 25 } },
    issecretvalue = function(value) return value == SECRET_RANGE end,
}
do
    local sb = make_sb(profile_secret)
    sb.interact = true
    local lib, err = load_path(sb, LIB_PATH)
    check(lib ~= nil, "secret: the real lib loads (" .. tostring(err) .. ")")
    if lib then
        local ok, init_err = pcall(lib.init, lib)
        check(ok, "secret: init() resolves the min-range spell without throwing ("
            .. tostring(init_err) .. ")")
        local checker = lib:GetHarmMinChecker(2)
        check(type(checker) == "function", "secret: the min-range harm checker resolves")

        sb.spell_in_range = 1
        local ok1, result1 = pcall(checker, "target")
        check(ok1, "secret control: an in-range reading does not throw")
        eq(result1, true, "secret control: a non-secret 1 stays exactly true")

        sb.spell_in_range = 0
        local ok0, min_result, marker = pcall(checker, "target")
        check(ok0, "secret control: an out-of-range reading does not throw")
        eq(min_result, true, "secret control: a non-secret 0 falls through to the min-range check")
        eq(marker, true, "secret control: the fall-through keeps its second return")

        sb.spell_in_range = SECRET_RANGE
        local oks, result_secret = pcall(checker, "target")
        check(oks, "secret: a secret reading does not throw")
        eq(result_secret, nil, "secret: a secret reading reports unknown (nil), never compared")
    end
end

-- Bite: strip the non-number/secret checks; a secret reading is then wrongly treated as
-- an honest reading (it falls through to the min-range check instead of reporting nil).
local guard_secret_6 =
    '      if type(r) ~= "number" or (issecretvalue and issecretvalue(r)) then\n'
    .. '        return nil\n'
    .. '      end\n'
do
    local mutated, removed = remove_all(REAL_LF, guard_secret_6)
    eq(removed, 2, "bite setup: the 6-space secret-check text is present twice")
    local tmp = write_tmp("lrc-guard-secret.lua", mutated)
    local sb = make_sb(profile_secret)
    sb.interact = true
    local lib, err = load_path(sb, tmp)
    check(lib ~= nil, "bite: the secret-guard-stripped copy still loads (" .. tostring(err) .. ")")
    if lib then
        local ok = pcall(lib.init, lib)
        check(ok, "bite: the secret-guard-stripped copy still inits")
        local checker = lib:GetHarmMinChecker(2)
        check(type(checker) == "function", "bite: the stripped copy still resolves a checker")
        sb.spell_in_range = SECRET_RANGE
        local ok_check, result = pcall(checker, "target")
        check(ok_check, "bite: the secret-guard-stripped checker call does not throw")
        check(result ~= nil,
            "bite: without the secret checks, a secret reading is wrongly treated as in range")
    end
end

--=========================================================================================
-- 5) No CheckInteractDistance: the interact checker reports unknown
--=========================================================================================
local profile_no_interact = {
    spellbook = false,
    is_spell_in_range = false,
    check_interact = false,
}
do
    local sb = make_sb(profile_no_interact)
    local lib, err = load_path(sb, LIB_PATH)
    check(lib ~= nil, "no-interact: the real lib loads (" .. tostring(err) .. ")")
    if lib then
        local ok, init_err = pcall(lib.init, lib)
        check(ok, "no-interact: init() does not throw (" .. tostring(init_err) .. ")")
        local checker = lib:GetHarmMinChecker(2)
        check(type(checker) == "function", "no-interact: the interact harm checker resolves")
        local ok_check, result = pcall(checker, "target")
        check(ok_check, "no-interact: the checker call does not throw (" .. tostring(result) .. ")")
        eq(result, nil, "no-interact: a missing CheckInteractDistance reports unknown (nil)")
    end
end

-- Bite: strip the interact checker's guard; the checker call must now throw.
local guard_interact =
    '      if type(CheckInteractDistance) ~= "function" then\n'
    .. '        return nil\n'
    .. '      end\n'
do
    local mutated, removed = remove_all(REAL_LF, guard_interact)
    eq(removed, 1, "bite setup: the 6-space CheckInteractDistance guard text is present once")
    local tmp = write_tmp("lrc-guard-interact.lua", mutated)
    local sb = make_sb(profile_no_interact)
    local lib, err = load_path(sb, tmp)
    check(lib ~= nil, "bite: the CheckInteractDistance-stripped copy still loads ("
        .. tostring(err) .. ")")
    if lib then
        local ok = pcall(lib.init, lib)
        check(ok, "bite: the CheckInteractDistance-stripped copy still inits")
        local checker = lib:GetHarmMinChecker(2)
        check(type(checker) == "function", "bite: the stripped copy still resolves a checker")
        local ok_check = pcall(checker, "target")
        check(not ok_check,
            "bite: with the CheckInteractDistance guard removed, the checker call throws")
    end
end

--=========================================================================================
-- Non-vacuity floor
--=========================================================================================
check(checks >= 30, "non-vacuity floor: the suite exercised at least 30 checks")

if failures == 0 then
    print("PASS  lrc_guard_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  lrc_guard_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
