-- tests/lrc_guard_state.lua: offline execution tests for the vendored LibRangeCheck-2.0
-- guard package, AFTER the 2026-10-21 vendored change (no interaction checkers).
--
-- The vendored change deleted every CheckInteractDistance site: that client call is
-- PROTECTED on TBC Anniversary 2.5.x (a blocked call is not catchable and took the whole
-- hunter class hook down), so the library now builds item/spell checkers only and every
-- empty checker list reports "no estimate" (nil). The addon's own range state comes from
-- compat.api.UnitDistance (exact yards); this suite pins the library half.
--
-- Covered:
--   1. Static pins: the exact guard counts in the vendored file, zero
--      CheckInteractDistance calls / interact tables, the two-argument checker builder,
--      and the getRange empty-list guard. The untouched event guards stay intact.
--   2. Empty-list profile (no spellbook, no IsSpellInRange, no item source): the real lib
--      loads, inits, and every checker consumer reports nil without throwing. Bite: the
--      getRange empty-list guard removed -> GetRange() throws on the same profile.
--   3. Retail-like bite: the getNumSpells guard removed -> init() throws.
--   4. Mixed profile (spellbook present, IsSpellInRange absent): the checklist is empty
--      and the spell checker stays unbuilt. Bite: the R2 spell-list guard removed AND the
--      IsSpellInRange guards stripped -> the checker call throws.
--   5. Legacy globals with a live spell list: honest/secret readings (1 -> true,
--      0 -> the item min-range fallback with both return values, secret -> nil). Bite:
--      the non-number/secret checks removed -> a secret reading is treated as honest.
--   6. Modern profile (C_Item + C_Spell present): the blocked item API is NEVER called,
--      no checker is built, all three addon reads answer nil. Bite: the modern-item guard
--      removed -> an item checker is built and the blocked API is called.
--   7. Legacy client (legacy globals, no C_Item): behaviour unchanged - the same 25 item
--      checkers in the same order plus the legacy spell checker, the legacy APIs still
--      called.
--   8. Hybrid guard-isolation profile (C_Item present AND a working legacy
--      IsSpellInRange): init() never builds the item minRangeCheck from HarmItems[15].
--   9. Era/FU-2 profile (legacy IsSpellInRange present AND C_Spell.IsSpellInRange
--      present): neither spell path is built, the list is empty, and no client range API
--      is called.
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
-- Sandbox: one throwaway client per load
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
--   race             player race for UnitRace (default "Human")
--   spellbook        true -> classic GetNumSpellTabs/GetSpellTabInfo/GetSpellBookItemName
--   spell_name       what GetSpellBookItemName answers (default "Intimidating Shout")
--   is_spell_in_range true -> classic IsSpellInRange global (reads sb.spell_in_range,
--                    counts sb.spell_range_calls)
--   modern_spell_range true -> C_Spell.IsSpellInRange present (reads sb.cspell_range,
--                    counts sb.cspell_range_calls) - the FU-2 world where the legacy
--                    global may ALSO exist
--   no_c_spell       true -> no C_Spell at all (the ancient client; GetSpellInfo comes
--                    from the legacy _G.GetSpellInfo)
--   harmful          true -> UnitCanAttack("player", unit) is true, so GetRange reads
--                    harmRC instead of the neutral miscRC
--   item_info        true -> C_Item.GetItemInfo answers a table for every id (so an
--                    unguarded item checker WOULD be built and called)
--   legacy_globals   true -> NO C_Item at all; _G.GetItemInfo and _G.IsItemInRange are
--                    the legacy pair (reads sb.item_range) - the pre-C_Item client
--   spell_info       id -> { name, minRange, maxRange } served via C_Spell.GetSpellInfo
--   issecretvalue    the client secret probe (absent on every classic client)
--
-- Every profile installs a THROWING CheckInteractDistance recorder: the vendored file
-- must never call it again (R2), so a call is both counted and fatal in the sandbox.
local function make_sb(profile)
    profile = profile or {}
    local sb = {
        events = {},
        item_range_calls = 0,
        spell_range_calls = 0,
        cspell_range_calls = 0,
        interact_calls = 0,
    }
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
    env.UnitRace = function() return profile.race or "Human", profile.race or "Human" end
    env.GetInventorySlotInfo = function() return 16 end
    env.GetInventoryItemLink = function() return nil end
    env.GetTime = function() return 100 end
    env.UnitExists = function() return true end
    env.UnitCanAttack = function() return profile.harmful == true end
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
    -- The protected call the vendored change retired: present here only so any call is
    -- observable, counted, and fatal in the sandbox.
    env.CheckInteractDistance = function()
        sb.interact_calls = sb.interact_calls + 1
        error("CheckInteractDistance is protected on TBC Anniversary")
    end
    if not profile.legacy_globals then
        env.C_Item = {
            GetItemInfo = function(id)
                if profile.item_info then return { name = "item" .. tostring(id) } end
                return nil
            end,
            IsItemInRange = function(item, unit)
                -- The spy: a modern client BLOCKS this call for addon code, so any call
                -- here is the bug. The count is what the modern test asserts on.
                sb.item_range_calls = sb.item_range_calls + 1
                return false
            end,
        }
    else
        -- A pre-C_Item client: the legacy globals are the only item API.
        env.GetItemInfo = function() return { name = "legacy item" } end
        env.IsItemInRange = function(item, unit)
            sb.item_range_calls = sb.item_range_calls + 1
            return sb.item_range
        end
        -- ...and the legacy spell-info API instead of C_Spell (old multi-return list).
        env.GetSpellInfo = function(id)
            local info = profile.spell_info and profile.spell_info[id]
            if not info then return nil end
            return info.name, nil, nil, nil, info.minRange or 0, info.maxRange or 0
        end
    end
    if not profile.no_c_spell then
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
            -- The FU-2 world: the client ships the modern range API. The spy counts
            -- calls; R7 must keep this at zero.
            IsSpellInRange = profile.modern_spell_range and function(spell, unit)
                sb.cspell_range_calls = sb.cspell_range_calls + 1
                return sb.cspell_range
            end or nil,
        }
    end
    if profile.spellbook then
        env.GetNumSpellTabs = function() return 1 end
        env.GetSpellTabInfo = function() return "General", nil, 0, 3 end
        env.GetSpellBookItemName = function() return profile.spell_name or "Intimidating Shout" end
    end
    if profile.is_spell_in_range then
        env.IsSpellInRange = function(spellIdx, bookType, unit)
            sb.spell_range_calls = sb.spell_range_calls + 1
            return sb.spell_in_range
        end
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
-- R2 (2026-10-21): no interaction checker exists at all - not even as dead data. The
-- name may appear in comments (the header explains why), but never as a call or table.
eq(count_plain(REAL_SRC, "CheckInteractDistance("), 0,
    "static pin: zero CheckInteractDistance calls in the vendored file")
eq(count_plain(REAL_SRC, "checkers_Interact"), 0,
    "static pin: the interact checker table is gone")
eq(count_plain(REAL_SRC, "DefaultInteractList"), 0,
    "static pin: the default interact list is gone")
eq(count_plain(REAL_SRC, "InteractLists"), 0,
    "static pin: the per-race interact lists are gone")
eq(count_plain(REAL_SRC, "local function createCheckerList(spellList, itemList)"), 1,
    "static pin: the checker builder takes no interact list")
eq(count_plain(REAL_SRC, "createCheckerList(nil, nil, "), 0,
    "static pin: no caller passes an interact list")
eq(count_plain(REAL_SRC, "if not checkerList or #checkerList == 0 then"), 1,
    "static pin: getRange has its empty-list guard")
eq(count_plain(REAL_SRC, 'local issecretvalue = rawget(_G, "issecretvalue")'), 1,
    "static pin: the lib probes issecretvalue itself (it loads before compat)")
-- The just-landed event guards stay intact (secret_guard_state.lua owns the full pin).
eq(count_plain(REAL_SRC, 'C_EventUtils.IsEventValid("LEARNED_SPELL_IN_TAB")'), 1,
    "static pin: the LEARNED_SPELL_IN_TAB event guard is intact")
eq(count_plain(REAL_SRC, 'C_EventUtils.IsEventValid("PLAYER_TALENT_UPDATE")'), 1,
    "static pin: the PLAYER_TALENT_UPDATE event guard is intact")
-- Range fix (2026-10-21, R1+R2): exact counts, so a guard cannot silently vanish or be
-- duplicated. The legacy item API is only a fallback where C_Item does not exist, and the
-- spell list is only built when the legacy spell-range global exists.
eq(count_plain(REAL_SRC, 'local modernItemRange = (C_Item and C_Item.IsItemInRange) ~= nil'), 1,
    "static pin: the modern item-range probe exists once")
eq(count_plain(REAL_SRC, 'local spellRangeAvailable = type(IsSpellInRange) == "function"'), 1,
    "static pin: the spell-range availability probe exists once")
eq(count_plain(REAL_SRC, 'local modernSpellRange = (C_Spell and C_Spell.IsSpellInRange) ~= nil'), 1,
    "static pin: the modern spell-range probe exists once")
eq(count_plain(REAL_SRC, 'if itemList and not modernItemRange then'), 1,
    "static pin: the item list is suppressed where the modern item API exists")
eq(count_plain(REAL_SRC, 'if spellList and spellRangeAvailable and not modernSpellRange then'), 1,
    "static pin: the spell list needs the legacy API and the client NOT shipping the modern one")
eq(count_plain(REAL_SRC, 'if HarmItems[15] and not modernItemRange then'), 1,
    "static pin: the item minRangeCheck is not built where the modern item API exists")

--=========================================================================================
-- 2) Empty-list profile: every consumer reports nil, nothing throws
--=========================================================================================
local profile_empty = {
    spellbook = false,
    is_spell_in_range = false,
    harmful = true,
}
do
    local sb = make_sb(profile_empty)
    local lib, err = load_path(sb, LIB_PATH)
    check(lib ~= nil, "empty: the real lib loads (" .. tostring(err) .. ")")
    if lib then
        check(sb.events["LEARNED_SPELL_IN_TAB"] == true,
            "empty: activate() completed and registered its events")
        local ok, init_err = pcall(lib.init, lib)
        check(ok, "empty: init() does not throw (" .. tostring(init_err) .. ")")
        local ok_idx, idx = pcall(lib.findSpellIndex, lib, 5246)
        check(ok_idx, "empty: findSpellIndex() does not throw (" .. tostring(idx) .. ")")
        eq(idx, nil, "empty: a missing spellbook reports no spell index")
        eq(#lib.harmRC, 0, "empty: the harm checker list is empty")
        eq(#lib.miscRC, 0, "empty: the misc checker list is empty")
        local ok_range, min_range, max_range = pcall(lib.GetRange, lib, "target")
        check(ok_range, "empty: GetRange() does not throw (" .. tostring(min_range) .. ")")
        eq(min_range, nil, "empty: GetRange() reports no estimate")
        eq(max_range, nil, "empty: GetRange() reports no max")
        local checker, band = lib:GetHarmMinChecker(2)
        eq(checker, nil, "empty: GetHarmMinChecker answers no checker")
        eq(band, nil, "empty: GetHarmMinChecker answers no band")
        local max_checker, max_band = lib:GetHarmMaxChecker(30)
        eq(max_checker, nil, "empty: GetHarmMaxChecker answers no checker")
        eq(max_band, nil, "empty: GetHarmMaxChecker answers no band")
        eq(sb.interact_calls, 0, "empty: CheckInteractDistance is never called")
    end
end

-- Bite: strip getRange's empty-list guard; GetRange() must now throw on the same profile.
local guard_empty =
    '  if not checkerList or #checkerList == 0 then\n'
    .. '    return nil\n'
    .. '  end\n'
do
    local mutated, removed = remove_all(REAL_LF, guard_empty)
    eq(removed, 1, "bite setup: the empty-list guard text is present once")
    local tmp = write_tmp("lrc-guard-emptylist.lua", mutated)
    local sb = make_sb(profile_empty)
    local lib, err = load_path(sb, tmp)
    check(lib ~= nil, "bite: the empty-list-stripped copy still loads (" .. tostring(err) .. ")")
    if lib then
        check(pcall(lib.init, lib), "bite: the empty-list-stripped copy still inits")
        local ok = pcall(lib.GetRange, lib, "target")
        check(not ok, "bite: with the empty-list guard removed, GetRange() throws")
    end
end

--=========================================================================================
-- 3) Bite: the getNumSpells guard is load-bearing
--=========================================================================================
local guard_spellbook =
    '  if type(GetSpellTabInfo) ~= "function" or type(GetNumSpellTabs) ~= "function" then\n'
    .. '    return 0\n'
    .. '  end\n'
do
    local mutated, removed = remove_all(REAL_LF, guard_spellbook)
    eq(removed, 1, "bite setup: the getNumSpells guard text is present once")
    local tmp = write_tmp("lrc-guard-spellbook.lua", mutated)
    -- spellbook=false (so getNumSpells is reached) but GetSpellInfo answers for the
    -- warrior's Intimidating Shout id, so init() actually walks the spellbook path.
    local sb = make_sb({
        spellbook = false,
        is_spell_in_range = false,
        harmful = true,
        spell_info = { [5246] = { name = "Intimidating Shout", minRange = 0, maxRange = 8 } },
    })
    local lib, err = load_path(sb, tmp)
    check(lib ~= nil, "bite: the guard-stripped copy still loads (" .. tostring(err) .. ")")
    if lib then
        check(type(lib.init) == "function", "bite: the guard-stripped copy still has init()")
        local ok = pcall(lib.init, lib)
        check(not ok, "bite: with the getNumSpells guard removed, init() throws")
    end
end

--=========================================================================================
-- 4) Mixed profile: spellbook present, IsSpellInRange absent -> list stays empty
--=========================================================================================
local profile_mixed = {
    spellbook = true,
    spell_name = "Intimidating Shout",
    is_spell_in_range = false,
    harmful = true,
    spell_info = { [5246] = { name = "Intimidating Shout", minRange = 0, maxRange = 8 } },
}
do
    local sb = make_sb(profile_mixed)
    local lib, err = load_path(sb, LIB_PATH)
    check(lib ~= nil, "mixed: the real lib loads (" .. tostring(err) .. ")")
    if lib then
        local ok, init_err = pcall(lib.init, lib)
        check(ok, "mixed: init() resolves the spellbook spell without throwing ("
            .. tostring(init_err) .. ")")
        eq(#lib.harmRC, 0, "mixed: the harm list stays empty without the legacy range global")
        local checker = lib:GetHarmMinChecker(2)
        eq(checker, nil, "mixed: no harm checker resolves")
    end
end

-- Bite: with the spell list forced back in (the R2 guard removed) and the two
-- IsSpellInRange absence guards stripped, the checker call must throw on the same
-- profile. Since R2 keeps that dead spell list out of a modern client's checker tables,
-- the absence guard is only reachable through this double mutation - which is exactly
-- what makes the R2 guard load-bearing.
local guard_isr_6 =
    '      if type(IsSpellInRange) ~= "function" then\n'
    .. '        return nil\n'
    .. '      end\n'
do
    local mutated, removed = remove_all(REAL_LF, guard_isr_6)
    eq(removed, 2, "bite setup: the 6-space IsSpellInRange guard text is present twice")
    local rearmed, rearmed_count = remove_all(mutated, ' and spellRangeAvailable')
    eq(rearmed_count, 1, "bite setup: the R2 spell-list guard is present once")
    local tmp = write_tmp("lrc-guard-isrange.lua", rearmed)
    local sb = make_sb(profile_mixed)
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
-- 5) Legacy spell list: honest readings, min-range fallback, secret -> unknown
--=========================================================================================
local SECRET_RANGE = 900001
local profile_secret = {
    legacy_globals = true,
    no_c_spell = true,
    spellbook = true,
    spell_name = "Charge",
    is_spell_in_range = true,
    harmful = true,
    spell_info = { [100] = { name = "Charge", minRange = 8, maxRange = 37 } },
    issecretvalue = function(value) return value == SECRET_RANGE end,
}
do
    local sb = make_sb(profile_secret)
    sb.item_range = true -- the item-based minRangeCheck answers "in range"
    local lib, err = load_path(sb, LIB_PATH)
    check(lib ~= nil, "secret: the real lib loads (" .. tostring(err) .. ")")
    if lib then
        local ok, init_err = pcall(lib.init, lib)
        check(ok, "secret: init() resolves the min-range spell without throwing ("
            .. tostring(init_err) .. ")")
        local checker = lib:GetHarmChecker(37)
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
        eq(sb.interact_calls, 0, "secret: CheckInteractDistance is never called")
    end
end

-- Bite: strip the non-number/secret checks; a secret reading is then wrongly treated as
-- an honest reading (it falls through to the item min-range check instead of reporting
-- nil).
local guard_secret_6 =
    '      if type(r) ~= "number" or (issecretvalue and issecretvalue(r)) then\n'
    .. '        return nil\n'
    .. '      end\n'
do
    local mutated, removed = remove_all(REAL_LF, guard_secret_6)
    eq(removed, 2, "bite setup: the 6-space secret-check text is present twice")
    local tmp = write_tmp("lrc-guard-secret.lua", mutated)
    local sb = make_sb(profile_secret)
    sb.item_range = true
    local lib, err = load_path(sb, tmp)
    check(lib ~= nil, "bite: the secret-guard-stripped copy still loads (" .. tostring(err) .. ")")
    if lib then
        local ok = pcall(lib.init, lib)
        check(ok, "bite: the secret-guard-stripped copy still inits")
        local checker = lib:GetHarmChecker(37)
        check(type(checker) == "function", "bite: the stripped copy still resolves a checker")
        sb.spell_in_range = SECRET_RANGE
        local ok_check, result = pcall(checker, "target")
        check(ok_check, "bite: the secret-guard-stripped checker call does not throw")
        check(result ~= nil,
            "bite: without the secret checks, a secret reading is wrongly treated as in range")
    end
end

--=========================================================================================
-- 6) MODERN profile: no checker is built, the blocked item API is never called
--=========================================================================================
-- The profile is deliberately "would have built the old checkers": C_Item.GetItemInfo
-- answers for every id (so unguarded item checkers WOULD exist) and the spellbook +
-- C_Spell info make an unguarded spell list WOULD exist.
local profile_modern = {
    spellbook = true,
    spell_name = "Taunt",
    is_spell_in_range = false,
    harmful = true,
    item_info = true,
    spell_info = { [355] = { name = "Taunt", minRange = 0, maxRange = 33 } },
}
do
    local sb = make_sb(profile_modern)
    local lib, err = load_path(sb, LIB_PATH)
    check(lib ~= nil, "modern: the real lib loads (" .. tostring(err) .. ")")
    if lib then
        local ok, init_err = pcall(lib.init, lib)
        check(ok, "modern: init() does not throw (" .. tostring(init_err) .. ")")

        eq(#lib.harmRC, 0, "modern: the harm list is empty")
        local max_checker, max_range = lib:GetHarmMaxChecker(30)
        eq(max_checker, nil, "modern: GetHarmMaxChecker(30) answers no checker")
        eq(max_range, nil, "modern: GetHarmMaxChecker(30) answers no band")
        local hmax_checker, hmax_range = lib:GetHarmMaxChecker(35)
        eq(hmax_checker, nil, "modern: GetHarmMaxChecker(35) answers no checker")
        eq(hmax_range, nil, "modern: GetHarmMaxChecker(35) answers no band")
        local min_checker, min_range = lib:GetHarmMinChecker(2)
        eq(min_checker, nil, "modern: GetHarmMinChecker(2) answers no checker")
        eq(min_range, nil, "modern: GetHarmMinChecker(2) answers no band")

        local ok_range, lo, hi = pcall(lib.GetRange, lib, "target")
        check(ok_range, "modern: GetRange() does not throw (" .. tostring(lo) .. ")")
        eq(lo, nil, "modern: the out-of-range bar gets no min")
        eq(hi, nil, "modern: the out-of-range bar gets no max")

        -- The blocked item API is never called.
        eq(sb.item_range_calls, 0, "modern: the blocked item-range API is never called")
        eq(sb.interact_calls, 0, "modern: CheckInteractDistance is never called")
    end
end

-- Bite: remove the modern-item suppression; an item checker must be built and the
-- blocked API called on the same profile.
do
    local mutated, removed = remove_all(REAL_LF, " and not modernItemRange")
    eq(removed, 2, "bite setup: the modern-item suppression text is present twice")
    local tmp = write_tmp("lrc-guard-modernitem.lua", mutated)
    local sb = make_sb(profile_modern)
    local lib, err = load_path(sb, tmp)
    check(lib ~= nil, "bite: the modern-item-stripped copy still loads (" .. tostring(err) .. ")")
    if lib then
        check(pcall(lib.init, lib), "bite: the modern-item-stripped copy still inits")
        check(#lib.harmRC > 0, "bite: without the modern-item guard the harm list is built")
        local ok = pcall(lib.GetRange, lib, "target")
        check(ok, "bite: GetRange() holds on the stripped copy")
        check(sb.item_range_calls > 0,
            "bite: without the modern-item guard the blocked item API is called")
    end
end

--=========================================================================================
-- 7) LEGACY profile (legacy globals, no C_Item, no C_Spell): behaviour is unchanged
--=========================================================================================
-- The pre-C_Item client has the legacy item and spell globals and no modern namespaces at
-- all, so the vendored change (which removes only the interact ladder) must not touch it:
-- the same checkers, same order, same answers, and the legacy APIs are still the ones
-- called. This is the R5 contract (the ancient-client path must keep working).
local profile_legacy = {
    legacy_globals = true,
    no_c_spell = true,
    spellbook = true,
    spell_name = "Taunt",
    is_spell_in_range = true,
    harmful = true,
    spell_info = { [355] = { name = "Taunt", minRange = 0, maxRange = 33 } },
}
local LEGACY_HARM_RANGES = {
    200, 150, 100, 90, 80, 70, 60, 55, 50, 45, 40, 38, 35, 33, 30, 25, 20, 15, 10, 8, 7, 6,
    5, 4, 3, 2,
}
local LEGACY_HARM_INFOS = {
    "item:75208", "item:46954", "item:33119", "item:133925", "item:35278",
    "item:41265", "item:32825", "item:74637", "item:116139", "item:23836",
    "item:28767", "item:140786", "item:24269", "spell:355:Taunt", "item:835",
    "item:24268", "item:10645", "item:33069", "item:32321", "item:34368",
    "item:61323", "item:164766", "item:8149", "item:129055", "item:42732",
    "item:37727",
}
do
    local sb = make_sb(profile_legacy)
    sb.spell_in_range = 0
    sb.item_range = false
    local lib, err = load_path(sb, LIB_PATH)
    check(lib ~= nil, "legacy: the real lib loads (" .. tostring(err) .. ")")
    if lib then
        local ok, init_err = pcall(lib.init, lib)
        check(ok, "legacy: init() does not throw (" .. tostring(init_err) .. ")")

        eq(#lib.harmRC, #LEGACY_HARM_RANGES,
            "legacy: the harm list keeps its 25 item checkers plus the legacy spell checker")
        local ranges_ok, infos_ok = true, true
        for i = 1, #LEGACY_HARM_RANGES do
            local rc = lib.harmRC[i]
            if not rc or rc.range ~= LEGACY_HARM_RANGES[i] then
                ranges_ok = false
                print("  legacy range[" .. i .. "] = " .. tostring(rc and rc.range))
            end
            if not rc or rc.info ~= LEGACY_HARM_INFOS[i] then
                infos_ok = false
                print("  legacy info[" .. i .. "] = " .. tostring(rc and rc.info))
            end
        end
        check(ranges_ok, "legacy: every harm checker keeps its pre-guard range and order")
        check(infos_ok, "legacy: every harm checker is still the same item checker")

        local max_checker, max_range = lib:GetHarmMaxChecker(30)
        check(type(max_checker) == "function", "legacy: GetHarmMaxChecker(30) answers a checker")
        eq(max_range, 30, "legacy: GetHarmMaxChecker(30) answers the 30-yd item checker")
        local _, min_range = lib:GetHarmMinChecker(2)
        eq(min_range, 2, "legacy: GetHarmMinChecker(2) answers the 2-yd item checker")

        local ok_range, lo, hi = pcall(lib.GetRange, lib, "target")
        check(ok_range, "legacy: GetRange() does not throw (" .. tostring(lo) .. ")")
        eq(lo, 200, "legacy: with every checker false the list reports beyond 200")
        eq(hi, nil, "legacy: beyond the largest checker there is no max")

        local calls_before = sb.item_range_calls
        sb.item_range = true
        local ok_max, max_answer = pcall(max_checker, "target")
        check(ok_max, "legacy: the item checker call does not throw")
        eq(max_answer, true, "legacy: the item checker still answers true when in range")
        check(sb.item_range_calls > calls_before,
            "legacy: the legacy item-range global is still the checker being called")

        -- The legacy SPELL path must also still be built and called (R7 must not
        -- suppress it on an ancient client that has no modern range API at all).
        local spell_checker, spell_range = lib:GetHarmMaxChecker(33)
        check(type(spell_checker) == "function", "legacy: the spell checker resolves")
        eq(spell_range, 33, "legacy: the spell checker keeps its 33-yd band")
        local spell_calls_before = sb.spell_range_calls
        sb.spell_in_range = 1
        local ok_spell, spell_answer = pcall(spell_checker, "target")
        check(ok_spell, "legacy: the spell checker call does not throw")
        eq(spell_answer, true, "legacy: the legacy spell checker answers true in range")
        check(sb.spell_range_calls > spell_calls_before,
            "legacy: the legacy spell-range global is still being called")

        local ok_all, lo_all, hi_all = pcall(lib.GetRange, lib, "target")
        check(ok_all, "legacy: GetRange() holds with every checker true")
        eq(lo_all, 0, "legacy: inside every checker the min is 0")
        eq(hi_all, 2, "legacy: inside every checker the max is the smallest band (2)")
        eq(sb.interact_calls, 0, "legacy: CheckInteractDistance is never called")
    end
end

--=========================================================================================
-- 8) HYBRID guard-isolation profile: C_Item present AND a working legacy spell API
--=========================================================================================
-- No shipped client has both, but this is the only way to observe the init guard
-- behaviourally: the min-range spell checker falls through to minRangeCheck, and the item
-- spy would answer "in range" if the guard were missing.
local profile_hybrid = {
    spellbook = true,
    spell_name = "Charge",
    is_spell_in_range = true,
    item_info = true,
    spell_info = { [5246] = { name = "Charge", minRange = 8, maxRange = 33 } },
}
do
    local sb = make_sb(profile_hybrid)
    sb.spell_in_range = 0
    sb.item_range = true -- the legacy-shaped item spy would say "in range"
    local lib, err = load_path(sb, LIB_PATH)
    check(lib ~= nil, "hybrid: the real lib loads (" .. tostring(err) .. ")")
    if lib then
        local ok, init_err = pcall(lib.init, lib)
        check(ok, "hybrid: init() does not throw (" .. tostring(init_err) .. ")")
        -- The item list is suppressed; the spell list is live here (legacy global).
        eq(#lib.harmRC, 1, "hybrid: only the min-range spell checker is in the list")
        eq(lib.harmRC[1] and lib.harmRC[1].info, "spell:5246:Charge",
            "hybrid: the min-range spell checker is the list's only entry")
        local checker = lib:GetHarmChecker(33)
        check(type(checker) == "function", "hybrid: the min-range spell checker resolves")
        local ok_check, answer, marker = pcall(checker, "target")
        check(ok_check, "hybrid: the checker call does not throw")
        eq(answer, nil,
            "hybrid: the out-of-range reading never falls through to a BLOCKED item check")
        eq(marker, nil, "hybrid: no min-range fall-through marker")
        eq(sb.item_range_calls, 0, "hybrid: the blocked item-range API is never called")
        eq(sb.interact_calls, 0, "hybrid: CheckInteractDistance is never called")
    end
end

--=========================================================================================
-- 9) ERA/FU-2 profile: the legacy global IS present AND the client ships the modern API
--=========================================================================================
-- This is the world the operator's instruction covers: the classic branches define no
-- legacy IsSpellInRange in FrameXML, but a client-BINARY global cannot be disproven
-- offline (bench/range_api_matrix_2026-10-21.md FU-2). If it exists, the modernSpellRange
-- probe suppresses the legacy list and the vendored change left no interact fallback, so
-- the result is an empty list and no client range API is called on any family.
local profile_era_legacy_global = {
    spellbook = true,
    spell_name = "Taunt",
    is_spell_in_range = true,
    modern_spell_range = true,
    harmful = true,
    item_info = true,
    spell_info = { [355] = { name = "Taunt", minRange = 0, maxRange = 33 } },
}
do
    local sb = make_sb(profile_era_legacy_global)
    -- Set-up sanity: this really is the "both APIs present" world.
    eq(type(sb.env.IsSpellInRange), "function",
        "era/FU-2: the legacy spell-range global is present")
    eq(type(sb.env.C_Spell and sb.env.C_Spell.IsSpellInRange), "function",
        "era/FU-2: the modern spell-range API is present")

    local lib, err = load_path(sb, LIB_PATH)
    check(lib ~= nil, "era/FU-2: the real lib loads (" .. tostring(err) .. ")")
    if lib then
        local ok, init_err = pcall(lib.init, lib)
        check(ok, "era/FU-2: init() does not throw (" .. tostring(init_err) .. ")")

        eq(#lib.harmRC, 0, "era/FU-2: the harm list is empty (no interact fallback)")
        local max_checker, max_range = lib:GetHarmMaxChecker(30)
        eq(max_checker, nil, "era/FU-2: GetHarmMaxChecker(30) answers no checker")
        eq(max_range, nil, "era/FU-2: GetHarmMaxChecker(30) answers no band")
        local hmax_checker, hmax_range = lib:GetHarmMaxChecker(35)
        eq(hmax_checker, nil, "era/FU-2: GetHarmMaxChecker(35) answers no checker")
        eq(hmax_range, nil, "era/FU-2: GetHarmMaxChecker(35) answers no band")
        local min_checker, min_range = lib:GetHarmMinChecker(2)
        eq(min_checker, nil, "era/FU-2: GetHarmMinChecker(2) answers no checker")
        eq(min_range, nil, "era/FU-2: GetHarmMinChecker(2) answers no band")

        local ok_range, lo, hi = pcall(lib.GetRange, lib, "target")
        check(ok_range, "era/FU-2: GetRange() does not throw (" .. tostring(lo) .. ")")
        eq(lo, nil, "era/FU-2: the out-of-range bar gets no min")
        eq(hi, nil, "era/FU-2: the out-of-range bar gets no max")

        -- ZERO client range calls on this family too.
        eq(sb.spell_range_calls, 0, "era/FU-2: the legacy spell-range global is never called")
        eq(sb.cspell_range_calls, 0, "era/FU-2: the modern spell-range API is never called")
        eq(sb.item_range_calls, 0, "era/FU-2: the blocked item-range API is never called")
        eq(sb.interact_calls, 0, "era/FU-2: CheckInteractDistance is never called")
    end
end

--=========================================================================================
-- Non-vacuity floor
--=========================================================================================
check(checks >= 80, "non-vacuity floor: the suite exercised at least 80 checks")

if failures == 0 then
    print("PASS  lrc_guard_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  lrc_guard_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
