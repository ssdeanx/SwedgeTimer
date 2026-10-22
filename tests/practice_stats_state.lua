-- tests/practice_stats_state.lua: unit tests for the pure practice stats module
-- (practice_stats.lua) - the lifetime aggregates (runs, attempts, hits, misses,
-- accuracy lifetime / rolling-20 / last session, best session score, best grade,
-- time active from an injected duration), the per-drill attempt table, the bounded
-- 50-session history ring, the snapshot aggregation and the JSON export payload.
--
-- The module is WoW-free: the sandbox is a plain table, the durations and the dates
-- are injected, and nothing here reads a clock or a random number.
--
-- Run from the repo root: lua5.1 tests/practice_stats_state.lua

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL  " .. label) end
end
local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end
local function near(got, want, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > 1e-9 then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

-- ---------------------------------------------------------------------------
-- Sandbox: the pure module (and its progress sibling, for the calendar cross-pin)
-- ---------------------------------------------------------------------------

local st = {}
local env = setmetatable({}, { __index = _G })
env.ST = st

local MODULES = { "practice_stats.lua", "practice_progress.lua" }
for _, path in ipairs(MODULES) do
    local chunk = assert(loadfile(ROOT .. path))
    setfenv(chunk, env)
    local ok, err = pcall(chunk, "SwedgeTimer", st)
    check(ok, path .. " loads under the sandbox (" .. tostring(err) .. ")")
end

local S = st.practice_stats
local P = st.practice_progress
check(type(S) == "table", "st.practice_stats table exists")

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

eq(S.SCORE_WINDOW, 20, "the rolling accuracy window is the last 20 attempts")
eq(S.HISTORY_LIMIT, 50, "the history ring holds the last 50 sessions")
eq(S.STATE_VERSION, 1, "the stats state version is 1")

-- ---------------------------------------------------------------------------
-- Recording attempts
-- ---------------------------------------------------------------------------

local state = S.new_state()
S.record_attempt(state, "PALADIN", "S", "paladin_twist")
S.record_attempt(state, "PALADIN", "A", "paladin_twist")
S.record_attempt(state, "PALADIN", "F", "paladin_twist")

eq(state.classes.PALADIN.attempts, 3, "three attempts were recorded")
eq(state.classes.PALADIN.hits, 2, "two of them were hits")
eq(state.classes.PALADIN.misses, 1, "one of them was a miss")
eq(state.classes.PALADIN.points, 180, "the grade points add up (100 + 80 + 0)")
eq(state.classes.PALADIN.best_grade, "S", "the best grade is S")
eq(state.global.attempts, 3, "the account scope counts the same attempts")
eq(state.global.hits, 2, "the account scope counts the same hits")
eq(state.global.misses, 1, "the account scope counts the same misses")

-- The per-drill attempt table.
eq(state.classes.PALADIN.drills.paladin_twist.attempts, 3, "the drill row counts the attempts")
eq(state.classes.PALADIN.drills.paladin_twist.hits, 2, "the drill row counts the hits")
eq(state.global.drills.paladin_twist.attempts, 3, "the account drill row counts the attempts")

-- A grade outside the scoring model's set is not an attempt.
local state2 = S.new_state()
S.record_attempt(state2, "ROGUE", "Z", "rogue_energy_pool")
eq(state2.global.attempts, 0, "an unknown grade is not an attempt")

-- L-4 (re-audit 2026-10-20): the stats module answers the grade question the
-- same way the progress module does, so the live score (which counts ANY grade it
-- is handed) and the progression can never drift apart.
eq(S.known_grade("S"), true, "L-4: the stats module knows the S grade")
eq(S.known_grade("Z"), false, "L-4: an unknown grade is not known")
eq(S.known_grade(nil), false, "L-4: a nil grade is not known")
eq(S.known_grade(42), false, "L-4: a non-string grade is not known")
if type(st.practice) == "table" and type(st.practice.GRADE_POINTS) == "table" then
    local live_known = true
    for grade in pairs(st.practice.GRADE_POINTS) do
        if S.known_grade(grade) ~= true then live_known = false end
    end
    check(live_known, "L-4: every grade of the live scoring model is known to the stats module")
end

-- The class scopes stay separate; the account scope is the sum.
local state3 = S.new_state()
S.record_attempt(state3, "PALADIN", "S", "paladin_twist")
S.record_attempt(state3, "ROGUE", "B", "rogue_energy_pool")
eq(state3.classes.PALADIN.attempts, 1, "the paladin scope counts its own attempts")
eq(state3.classes.ROGUE.attempts, 1, "the rogue scope counts its own attempts")
eq(state3.global.attempts, 2, "the account scope counts both")

-- The best grade is rank-ordered and never downgrades.
local state4 = S.new_state()
S.record_attempt(state4, "HUNTER", "D", "hunter_forced_move")
eq(state4.classes.HUNTER.best_grade, "D", "a D is the best grade so far")
S.record_attempt(state4, "HUNTER", "B", "hunter_forced_move")
eq(state4.classes.HUNTER.best_grade, "B", "a B beats a D")
S.record_attempt(state4, "HUNTER", "C", "hunter_forced_move")
eq(state4.classes.HUNTER.best_grade, "B", "a C does not downgrade the best grade")

-- The longest run of consecutive S grades.
local state5 = S.new_state()
S.record_attempt(state5, "DRUID", "S", "druid_powershift")
S.record_attempt(state5, "DRUID", "S", "druid_powershift")
S.record_attempt(state5, "DRUID", "A", "druid_powershift")
S.record_attempt(state5, "DRUID", "S", "druid_powershift")
eq(state5.classes.DRUID.best_s_streak, 2, "the best S run is two")
eq(state5.global.best_s_streak, 2, "the account scope tracks the best S run")

-- ---------------------------------------------------------------------------
-- The rolling-20 accuracy
-- ---------------------------------------------------------------------------

local roll = S.new_state()
for _ = 1, 20 do S.record_attempt(roll, "SHAMAN", "S", "shaman_weave") end
near(S.snapshot(roll).global.rolling_accuracy, 1, "20 hits roll at 100%")
S.record_attempt(roll, "SHAMAN", "F", "shaman_weave")
near(S.snapshot(roll).global.rolling_accuracy, 19 / 20, "the 21st attempt evicts the oldest hit")
for _ = 1, 20 do S.record_attempt(roll, "SHAMAN", "S", "shaman_weave") end
near(S.snapshot(roll).global.rolling_accuracy, 1, "the window rolls forward again")
eq(#roll.global.recent, 20, "the rolling window never holds more than 20 attempts")

-- ---------------------------------------------------------------------------
-- Recording sessions
-- ---------------------------------------------------------------------------

local sessions = S.new_state()
S.record_attempt(sessions, "WARRIOR", "S", "warrior_execute")
S.record_attempt(sessions, "WARRIOR", "S", "warrior_execute")
S.record_attempt(sessions, "WARRIOR", "F", "warrior_execute")
S.record_session(sessions, "WARRIOR", { attempts = 3, hits = 2, score = 73, best_grade = "S" }, 42.6, 20745)

eq(sessions.classes.WARRIOR.runs, 1, "the session was counted as a run")
eq(sessions.classes.WARRIOR.attempts, 3, "the session did not double-count the attempts")
eq(sessions.classes.WARRIOR.hits, 2, "the session did not double-count the hits")
eq(sessions.classes.WARRIOR.time_active_seconds, 42, "the injected duration is counted in whole seconds")
eq(sessions.classes.WARRIOR.best_session_score, 73, "the best session score is stored")
eq(sessions.classes.WARRIOR.best_grade, "S", "the best grade from the summary is stored")
eq(sessions.global.runs, 1, "the account scope counts the run too")
eq(sessions.global.time_active_seconds, 42, "the account scope counts the active time too")
eq(#sessions.classes.WARRIOR.history, 1, "the history holds the session")
eq(sessions.classes.WARRIOR.history[1].score, 73, "the history entry keeps the score")
near(sessions.classes.WARRIOR.history[1].accuracy, 2 / 3, "the history entry keeps the accuracy")
eq(sessions.classes.WARRIOR.history[1].day, 20745, "the history entry keeps the day")

-- The last session accuracy reads from the history.
near(S.snapshot(sessions).classes.WARRIOR.last_session_accuracy, 2 / 3, "the last session accuracy is read")
near(S.snapshot(sessions).classes.WARRIOR.accuracy, 2 / 3, "the lifetime accuracy is read")

-- A session with no attempts is not a completed session.
local empty = S.new_state()
S.record_session(empty, "WARRIOR", { attempts = 0, hits = 0, score = 0 }, 30, 20745)
eq(empty.classes.WARRIOR.runs, 0, "an empty session is not a run")
eq(empty.classes.WARRIOR.time_active_seconds, 0, "an empty session adds no active time")
eq(#empty.classes.WARRIOR.history, 0, "an empty session writes no history")

-- A malformed duration adds nothing.
local badtime = S.new_state()
S.record_attempt(badtime, "WARRIOR", "S", "warrior_execute")
S.record_session(badtime, "WARRIOR", { attempts = 1, hits = 1, score = 100 }, -50, 20745)
eq(badtime.classes.WARRIOR.time_active_seconds, 0, "a negative duration adds nothing")
S.record_session(badtime, "WARRIOR", { attempts = 1, hits = 1, score = 100 }, 0 / 0, 20745)
eq(badtime.classes.WARRIOR.time_active_seconds, 0, "a NaN duration adds nothing")
S.record_session(badtime, "WARRIOR", { attempts = 1, hits = 1, score = 100 }, math.huge, 20745)
eq(badtime.classes.WARRIOR.time_active_seconds, 0, "an infinite duration adds nothing")

-- The best session score never drops.
local best = S.new_state()
S.record_attempt(best, "ROGUE", "S", "rogue_ss_window")
S.record_session(best, "ROGUE", { attempts = 1, hits = 1, score = 90 }, 10, 20745)
S.record_attempt(best, "ROGUE", "F", "rogue_ss_window")
S.record_session(best, "ROGUE", { attempts = 1, hits = 0, score = 0 }, 10, 20746)
eq(best.classes.ROGUE.best_session_score, 90, "the best session score keeps the high score")

-- ---------------------------------------------------------------------------
-- The bounded history ring (50 sessions)
-- ---------------------------------------------------------------------------

local hist = S.new_state()
for i = 1, 55 do
    S.record_attempt(hist, "PALADIN", "S", "paladin_twist")
    S.record_session(hist, "PALADIN", { attempts = 1, hits = 1, score = i }, 1, 20745 + i)
end
eq(#hist.classes.PALADIN.history, 50, "the history ring is bounded at 50 sessions")
eq(hist.classes.PALADIN.history[1].score, 6, "the oldest sessions were evicted")
eq(hist.classes.PALADIN.history[50].score, 55, "the newest session is last")
eq(hist.classes.PALADIN.runs, 55, "every session still counted as a run")
eq(#hist.global.history, 50, "the account history ring is bounded too")

-- ---------------------------------------------------------------------------
-- The snapshot
-- ---------------------------------------------------------------------------

local snap = S.snapshot(sessions)
eq(snap.schema_version, 1, "the snapshot carries the schema version")
eq(snap.classes.WARRIOR.runs, 1, "the snapshot carries the runs")
eq(snap.classes.WARRIOR.attempts, 3, "the snapshot carries the attempts")
eq(snap.classes.WARRIOR.hits, 2, "the snapshot carries the hits")
eq(snap.classes.WARRIOR.misses, 1, "the snapshot carries the misses")
eq(snap.classes.WARRIOR.best_session_score, 73, "the snapshot carries the best session score")
eq(snap.classes.WARRIOR.best_grade, "S", "the snapshot carries the best grade")
eq(snap.classes.WARRIOR.best_s_streak, 2, "the snapshot carries the best S run")
eq(snap.classes.WARRIOR.time_active_seconds, 42, "the snapshot carries the active time")
eq(snap.classes.WARRIOR.history_count, 1, "the snapshot counts the history")
eq(snap.classes.WARRIOR.drills.warrior_execute.attempts, 3, "the snapshot carries the per-drill table")
near(snap.classes.WARRIOR.drills.warrior_execute.accuracy, 2 / 3, "the snapshot carries the per-drill accuracy")
eq(snap.global.attempts, 3, "the snapshot carries the account scope")

-- A malformed state degrades to zeros instead of raising.
local okdegraded, degraded = pcall(S.snapshot, "not a state")
check(okdegraded, "the snapshot of a malformed state does not raise")
eq(degraded.global.attempts, 0, "a malformed state reads as zeros")
eq(degraded.classes.PALADIN, nil, "a malformed state has no classes")

-- ---------------------------------------------------------------------------
-- The export payload is JSON-safe
-- ---------------------------------------------------------------------------

local payload = S.export_payload(sessions)
local function json_safe(value, path)
    local t = type(value)
    if t == "number" then
        check(value == value and value ~= math.huge and value ~= -math.huge,
            "the export payload has no NaN or infinity at " .. path)
        return
    end
    if t == "string" or t == "boolean" then return end
    if t ~= "table" then
        check(false, "the export payload holds only JSON types at " .. path)
        return
    end
    local length = #value
    for i = 1, length do
        check(value[i] ~= nil, "the export payload array is dense at " .. path .. "[" .. i .. "]")
        json_safe(value[i], path .. "[" .. i .. "]")
    end
    for key, item in pairs(value) do
        if not (type(key) == "number" and key >= 1 and key <= length and key % 1 == 0) then
            check(type(key) == "string", "the export payload object keys are strings at " .. path)
        end
        json_safe(item, path .. "." .. tostring(key))
    end
end
json_safe(payload, "stats")
eq(payload.schema_version, 1, "the export payload carries the schema version")
eq(payload.global.attempts, 3, "the export payload carries the account scope")
eq(payload.classes.WARRIOR.best_session_score, 73, "the export payload carries the class scope")
eq(payload.classes.WARRIOR.best_grade, "S", "the export payload carries the best grade")
eq(payload.classes.WARRIOR.history[1].day, 20745, "the export payload carries the history")

-- A missing best grade exports as an empty string, never as a hole.
local nograde = S.new_state()
S.record_attempt(nograde, "PALADIN", "F", "paladin_twist")
S.record_session(nograde, "PALADIN", { attempts = 1, hits = 0, score = 0 }, 5, nil)
local payload2 = S.export_payload(nograde)
eq(payload2.global.best_grade, "F", "a lone F is the best grade (the scoring model agrees)")
eq(payload2.global.history[1].day, S.NO_DAY, "a missing day exports as the no-day marker")
json_safe(payload2, "stats2")

-- A state with no attempts at all has no best grade: it exports as an empty string.
local payload3 = S.export_payload(S.new_state())
eq(payload3.global.best_grade, "", "a missing best grade exports as an empty string")
json_safe(payload3, "stats3")

-- ---------------------------------------------------------------------------
-- M-3 (re-audit 2026-10-20): the NO_DAY sentinel survives a signed read
-- ---------------------------------------------------------------------------
--
-- count() clamps a negative to 0, so the "no date recorded" sentinel (-1) was
-- turned into 0 - the epoch - and the "if day < 0" branch was dead code. The
-- history row then rendered as 1970-01-01 instead of "-".

eq(S.NO_DAY, -1, "M-3: the no-day sentinel is -1")
local days = S.repair_state({
    global = {
        history = {
            { score = 1, accuracy = 1, attempts = 1, hits = 1, day = S.NO_DAY, duration = 1 },
            { score = 2, accuracy = 1, attempts = 1, hits = 1, day = -5, duration = 1 },
            { score = 3, accuracy = 1, attempts = 1, hits = 1, day = 0, duration = 1 },
            { score = 4, accuracy = 1, attempts = 1, hits = 1, day = 20745, duration = 1 },
            { score = 5, accuracy = 1, attempts = 1, hits = 1, day = "junk", duration = 1 },
            { score = 6, accuracy = 1, attempts = 1, hits = 1, duration = 1 },
        },
    },
})
eq(days.global.history[1].day, S.NO_DAY, "M-3: the no-day sentinel survives the repair")
eq(days.global.history[2].day, S.NO_DAY, "M-3: a corrupt negative day maps to the no-day marker")
eq(days.global.history[3].day, 0, "M-3: the epoch day is a real day and stays 0")
eq(days.global.history[4].day, 20745, "M-3: a real day survives the repair")
eq(days.global.history[5].day, S.NO_DAY, "M-3: a non-numeric day maps to the no-day marker")
eq(days.global.history[6].day, S.NO_DAY, "M-3: a missing day maps to the no-day marker")

-- The round trip: a session with no date is recorded, repaired and exported with
-- the sentinel intact - the UI renders it as "-", not as 1970-01-01.
local noday = S.new_state()
S.record_attempt(noday, "PALADIN", "S", "paladin_twist")
S.record_session(noday, "PALADIN", { attempts = 1, hits = 1, score = 100 }, 10, nil)
eq(noday.classes.PALADIN.history[1].day, S.NO_DAY, "M-3: a session with no date records the sentinel")
local noday_repaired = S.repair_state(noday)
eq(noday_repaired.classes.PALADIN.history[1].day, S.NO_DAY,
    "M-3: the sentinel survives the repair")
local noday_payload = S.export_payload(noday_repaired)
eq(noday_payload.classes.PALADIN.history[1].day, S.NO_DAY,
    "M-3: the sentinel survives into the export payload")
json_safe(noday_payload, "stats-noday")

-- ---------------------------------------------------------------------------
-- Repair (load-time validation)
-- ---------------------------------------------------------------------------

local repaired = S.repair_state({
    classes = {
        PALADIN = {
            runs = "bad",
            attempts = 10,
            hits = 99,
            misses = -3,
            points = 500,
            best_session_score = 80,
            best_grade = 42,
            best_s_streak = "bad",
            time_active_seconds = 120,
            recent = { 1, 0, "junk", 1 },
            drills = { paladin_twist = { attempts = 4, hits = 99 } },
            unknown = "dropped",
        },
    },
    global = { attempts = 5, unknown = "dropped" },
})
eq(repaired.classes.PALADIN.runs, 0, "a bad run type resets to 0")
eq(repaired.classes.PALADIN.attempts, 10, "good counters survive")
eq(repaired.classes.PALADIN.hits, 10, "hits are clamped to the attempts")
eq(repaired.classes.PALADIN.misses, 0, "a negative miss count resets to 0")
eq(repaired.classes.PALADIN.points, 500, "the points survive")
eq(repaired.classes.PALADIN.best_session_score, 80, "the best session score survives")
eq(repaired.classes.PALADIN.best_grade, nil, "a bad grade type resets to nil")
eq(repaired.classes.PALADIN.best_s_streak, 0, "a bad S run resets to 0")
eq(repaired.classes.PALADIN.time_active_seconds, 120, "the active time survives")
eq(repaired.classes.PALADIN.unknown, nil, "an unknown scope key is dropped")
eq(#repaired.classes.PALADIN.recent, 3, "a junk rolling flag is dropped")
eq(repaired.classes.PALADIN.drills.paladin_twist.hits, 4, "the drill hits are clamped to its attempts")
eq(repaired.global.attempts, 5, "the account scope survives")
eq(repaired.global.unknown, nil, "an unknown account key is dropped")

-- A corrupt state becomes a fresh one.
local okfresh, fresh = pcall(S.repair_state, "not a state")
check(okfresh, "repairing a malformed state does not raise")
eq(fresh.global.attempts, 0, "a malformed state repairs to zeros")
eq(type(fresh.classes), "table", "a malformed state repairs to an empty class map")

-- The history ring is trimmed on repair.
local long_history = {}
for i = 1, 80 do
    long_history[i] = { score = i, accuracy = 1, attempts = 1, hits = 1, day = 20745, duration = 1 }
end
local repaired_history = S.repair_state({ global = { history = long_history } })
eq(#repaired_history.global.history, 50, "the repaired history is trimmed to the bound")

-- The input is never mutated.
local input = { global = { attempts = 5 } }
S.repair_state(input)
eq(input.global.attempts, 5, "repair does not mutate its input")

-- ---------------------------------------------------------------------------
-- Guards: malformed input degrades, it never raises
-- ---------------------------------------------------------------------------

local bad = { 0 / 0, math.huge, -math.huge, "10", true, {}, { nested = { deep = true } } }
for i = 1, #bad do
    local value = bad[i]
    local okg = pcall(function()
        S.record_attempt(value, value, value, value)
        S.record_attempt(S.new_state(), value, value, value)
        S.record_session(value, value, value, value, value)
        S.snapshot(value)
        S.export_payload(value)
        S.repair_state(value)
        S.json_safe(value)
        S.format_duration(value)
    end)
    check(okg, "a malformed input (" .. i .. ") never raises")
end
eq(S.format_duration(3661), "1:01:01", "the duration reads as h:mm:ss")
eq(S.format_duration(0), "0:00:00", "a zero duration reads as 0:00:00")
eq(S.format_duration(-5), "0:00:00", "a negative duration reads as 0:00:00")
eq(S.format_duration(0 / 0), "0:00:00", "a NaN duration reads as 0:00:00")
eq(S.json_safe(0 / 0), nil, "the JSON sanitizer drops a NaN")
eq(S.json_safe(math.huge), nil, "the JSON sanitizer drops an infinity")
eq(S.json_safe(print), nil, "the JSON sanitizer drops a function")
eq(S.json_safe("text"), "text", "the JSON sanitizer keeps a string")
eq(S.json_safe(42), 42, "the JSON sanitizer keeps a number")

-- ---------------------------------------------------------------------------
-- The calendar day helper (injected dates only)
-- ---------------------------------------------------------------------------

eq(S.day_ordinal("1970-01-01"), 0, "the epoch day is 0")
eq(S.day_ordinal("2000-01-01"), 10957, "2000-01-01 is day 10957")
eq(S.day_ordinal("2026-10-19"), 20745, "2026-10-19 is day 20745")
eq(S.day_ordinal("2024-02-29"), 19782, "a leap day is a valid date")
eq(S.day_ordinal("2023-02-29"), nil, "a non-leap 29 February is not a date")
eq(S.day_ordinal("2026-10-32"), nil, "day 32 is not a date")
eq(S.day_ordinal("not a date"), nil, "a malformed date is not a date")
eq(S.day_ordinal(true), nil, "a boolean is not a date")
eq(S.day_ordinal(20745), 20745, "a numeric day counter passes through")

-- Both pure modules must agree on the calendar (one helper, two copies).
for _, day in ipairs({ "1970-01-01", "1999-12-31", "2000-02-29", "2026-10-19", "2027-01-01", "bogus" }) do
    eq(S.day_ordinal(day), P.day_ordinal(day), "both modules read the day " .. tostring(day) .. " the same way")
end

-- ---------------------------------------------------------------------------
-- The load order: the stats module loads before the progress module, both after
-- practice.lua and before practice_ui.lua.
-- ---------------------------------------------------------------------------

local function toc_entries(path)
    local entries = {}
    local file = assert(io.open(ROOT .. path, "r"))
    for line in file:lines() do
        line = line:gsub("\r$", "")
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then entries[#entries + 1] = trimmed end
    end
    file:close()
    return entries
end

local TOCS = {
    "SwedgeTimer.toc", "SwedgeTimer_Vanilla.toc", "SwedgeTimer_TBC.toc",
    "SwedgeTimer_Wrath.toc", "SwedgeTimer_Mainline.toc", "SwedgeTimer_Cata.toc",
    "SwedgeTimer_Mists.toc",
}
for _, toc in ipairs(TOCS) do
    local entries = toc_entries(toc)
    local index = {}
    for i, entry in ipairs(entries) do index[entry] = index[entry] or i end
    check(index["practice_stats.lua"] ~= nil, toc .. ": lists practice_stats.lua")
    check(index["practice_progress.lua"] ~= nil, toc .. ": lists practice_progress.lua")
    check(index["practice.lua"] < index["practice_stats.lua"], toc .. ": practice.lua before practice_stats.lua")
    check(index["practice_stats.lua"] < index["practice_progress.lua"],
        toc .. ": practice_stats.lua before practice_progress.lua")
    check(index["practice_progress.lua"] < index["practice_ui.lua"],
        toc .. ": practice_progress.lua before practice_ui.lua")
end

-- ---------------------------------------------------------------------------
-- The hook's save / load round trip: the live stats state is written into the
-- profile as-is and read back after a reload, and the load-time repair must not
-- change a single number.
-- ---------------------------------------------------------------------------

local live = S.new_state()
S.record_attempt(live, "PALADIN", "S", "paladin_twist")
S.record_attempt(live, "PALADIN", "A", "paladin_twist")
S.record_attempt(live, "PALADIN", "F", "paladin_twist")
S.record_session(live, "PALADIN", { attempts = 3, hits = 2, score = 80, best_grade = "S" }, 120, 20745)
local reloaded = S.repair_state(live)
eq(reloaded.classes.PALADIN.attempts, 3, "the round trip keeps the attempt count")
eq(reloaded.classes.PALADIN.hits, 2, "the round trip keeps the hit count")
eq(reloaded.classes.PALADIN.misses, 1, "the round trip keeps the miss count")
eq(reloaded.classes.PALADIN.runs, 1, "the round trip keeps the run count")
eq(reloaded.classes.PALADIN.time_active_seconds, 120, "the round trip keeps the active time")
eq(reloaded.classes.PALADIN.best_grade, "S", "the round trip keeps the best grade")
eq(reloaded.classes.PALADIN.best_session_score, 80, "the round trip keeps the best session score")
eq(reloaded.classes.PALADIN.drills.paladin_twist.attempts, 3,
    "the round trip keeps the per-drill table")
eq(#reloaded.classes.PALADIN.history, 1, "the round trip keeps the bounded history")
eq(reloaded.classes.PALADIN.history[1].score, 80, "the round trip keeps the history score")
eq(reloaded.global.attempts, 3, "the round trip keeps the account scope")
eq(reloaded.global.time_active_seconds, 120, "the round trip keeps the account active time")
eq(reloaded.global.runs, 1, "the round trip keeps the account run count")

-- The live summary shape (the scoring model's own summary, with its extra
-- readouts) is accepted by the session recorder: it reads attempts / hits /
-- score / best_grade and ignores the rest.
local summary_shaped = {
    attempts = 2, hits = 2, hit_rate = 1.0, mean_points = 100,
    rolling_hit_rate = 1.0, rolling_points = 100, mean_error_ms = 42,
    best_grade = "S", last_grade = "S", score = 100,
}
local shaped = S.new_state()
S.record_session(shaped, "HUNTER", summary_shaped, 30, 20745)
eq(shaped.classes.HUNTER.runs, 1, "the live summary shape records a run")
eq(shaped.classes.HUNTER.time_active_seconds, 30, "the live summary shape records the time")
eq(shaped.classes.HUNTER.best_session_score, 100, "the live summary shape records the score")
eq(shaped.classes.HUNTER.best_grade, "S", "the live summary shape records the best grade")
eq(shaped.classes.HUNTER.history[1].accuracy, 1.0, "the live summary shape records the accuracy")

print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)
