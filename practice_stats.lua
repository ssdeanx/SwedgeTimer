--=========================================================================================
-- Practice stats (pure): lifetime aggregates, per-drill table, bounded session history.
--
-- Design source: bench/practice_gamification_design_2026-10-19.md (spec §3 stats, §6
-- engineering). This is the FOUNDATION lane (spec §7 step 1): the rules live here,
-- offline and deterministic. The hook lane (step 2) feeds this module from a live
-- session, the stats frame (step 3) reads the snapshot, and the export lane (step 5)
-- writes the payload.
--
-- PURE by construction: no WoW API, no os.time, no randomness, no clock read, no
-- addon-owned state. The caller injects everything time-shaped:
--   * durations -> seconds (a number; negative / NaN / infinite values add nothing)
--   * dates     -> a day ordinal (a number) or a "YYYY-MM-DD" string
-- Every aggregate degrades to zero on malformed input instead of raising, so a
-- corrupt save can never turn into a client error (spec §6 "Guards").
--
-- Ownership split with practice_progress.lua (one owner per number, no duplication):
--   stats    : runs, attempts, hits, misses, accuracy (lifetime / rolling-20 / last
--              session), best session score, best single grade, best S-run, time
--              active, the per-drill attempt table, the 50-session history ring, the
--              stats snapshot and the JSON export payload.
--   progress : xp, level, renown, per-drill mastery + tier, the streaks (session /
--              best / daily), the daily per-drill XP cap, achievement unlock state and
--              the SwedgeTimerDB.profile.practice persistence shape.
-- The merged read model - a level next to the stats numbers, mastery inside the
-- per-drill rows - is st.practice_progress.profile_snapshot (it takes this module's
-- snapshot as data, so the two stay independent).
--
-- Load order: this module loads before practice_progress.lua, which composes the saved
-- profile from both halves. Both are listed after practice.lua and before
-- practice_ui.lua in every flavour toc.
--=========================================================================================
local _, st = ...

st.practice_stats = st.practice_stats or {}
local S = st.practice_stats

--=========================================================================================
-- Constants
--=========================================================================================

-- Bumped when the persisted state shape changes; the persistence layer in
-- practice_progress.lua migrates older blobs forward.
S.STATE_VERSION = 1

-- Rolling window for the "last N attempts" accuracy read: the scoring model's own
-- SCORE_WINDOW (practice.lua:1346). Mirrored here so the module stays standalone;
-- the tests pin it against the live value.
S.SCORE_WINDOW = 20

-- Bounded history: the last 50 sessions (spec §3 "History"). The ring is a hard
-- bound, not a soft one - the 51st session evicts the oldest.
S.HISTORY_LIMIT = 50

-- The grade set the scoring model produces. F is the only zero-point grade and the
-- only miss (practice.lua:1393 grades a hit as anything but "F").
S.GRADES = { S = true, A = true, B = true, C = true, D = true, F = true }

-- Grade points, mirrored from st.practice.GRADE_POINTS (practice.lua:1339). The live
-- table wins at call time so a retune of the scoring model flows into the stats
-- without touching this file; the mirror is the offline fallback.
S.GRADE_POINTS = { S = 100, A = 80, B = 60, C = 40, D = 20, F = 0 }

-- Grade rank for best-grade comparison, mirrored from st.practice.GRADE_RANK
-- (practice.lua:1342). Higher is better; F is the floor.
S.GRADE_RANK = { S = 6, A = 5, B = 4, C = 3, D = 2, F = 1 }

-- Day ordinal used for "no date recorded" in the export payload. Real ordinals are
-- >= 0 (the civil-days algorithm counts from 1970-01-01), so -1 is unambiguous.
S.NO_DAY = -1

--=========================================================================================
-- Guards: malformed input degrades to zero / the default; nothing here raises
--=========================================================================================

-- A finite number, or the fallback. Rejects non-numbers, NaN and the infinities.
local function num(value, fallback)
    if type(value) ~= "number" then return fallback end
    if value ~= value then return fallback end -- NaN
    if value == math.huge or value == -math.huge then return fallback end
    return value
end

-- A finite, non-negative integer counter. Counts saturate at 2^53, the largest
-- exactly representable integer in a double - past that a counter is a corrupt value,
-- not a real count.
local function count(value)
    local v = num(value, 0)
    if v < 0 then return 0 end
    if v > 2 ^ 53 then return 2 ^ 53 end
    return math.floor(v)
end

--=========================================================================================
-- Grade model (the live scoring table wins; the mirror is the fallback)
--=========================================================================================

-- The grade set in force: the live scoring model's keys when it is loaded, else the
-- mirror above. A grade outside the set is not an attempt (the caller only ever
-- passes real grades; a corrupt ring entry is repaired at load time).
local function grade_set()
    local live = st.practice and st.practice.GRADE_POINTS
    if type(live) == "table" then
        local set = {}
        for grade in pairs(live) do
            if type(grade) == "string" then set[grade] = true end
        end
        if next(set) then return set end
    end
    return S.GRADES
end

-- Points for one grade (0 for an unknown grade).
local function grade_points(grade)
    local live = st.practice and st.practice.GRADE_POINTS
    local points
    if type(live) == "table" then points = live[grade] end
    if type(points) ~= "number" then points = S.GRADE_POINTS[grade] end
    if type(points) ~= "number" or points ~= points then return 0 end
    if points == math.huge or points == -math.huge then return 0 end
    return points
end

-- Rank of one grade for best-grade comparison (0 for an unknown grade).
local function grade_rank(grade)
    local live = st.practice and st.practice.GRADE_RANK
    local rank
    if type(live) == "table" then rank = live[grade] end
    if type(rank) ~= "number" then rank = S.GRADE_RANK[grade] end
    if type(rank) ~= "number" or rank ~= rank then return 0 end
    return rank
end

-- A hit is any grade but F - the same definition the scoring model uses
-- (practice.lua:1393). An F still counts as an attempt (it costs nothing, it just
-- does not earn).
local function is_hit(grade)
    return grade ~= "F"
end

-- Is the grade one the scoring model produces? The live scoring model's own grade
-- set is the truth; the mirror above is the offline fallback.
--
-- L-4 (re-audit 2026-10-20): the live score model counts ANY grade it is handed
-- (st.practice.record_attempt), while the pure modules drop a grade outside the
-- set - so a stray grade advanced the session score and vanished from the stats,
-- and the two drifted apart. The caller can now ask the pure side before it
-- records anything, and both pure modules answer the same way.
function S.known_grade(grade)
    return grade_set()[grade] == true
end

--=========================================================================================
-- Calendar day helper (injected dates only - no os.time anywhere in this module)
--=========================================================================================

local MONTH_LENGTHS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function is_leap_year(year)
    return (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
end

local function days_in_month(year, month)
    if month == 2 and is_leap_year(year) then return 29 end
    return MONTH_LENGTHS[month] or 0
end

-- Days since 1970-01-01 from a proleptic Gregorian date (Howard Hinnant's civil
-- calendar algorithm): pure integer maths, no library and no clock.
local function days_from_civil(y, m, d)
    y = y - (m <= 2 and 1 or 0)
    local era = math.floor((y >= 0 and y or y - 399) / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- The day ordinal of an injected date value. Two accepted forms:
--   * a number - an opaque day counter the caller converts the client's calendar
--                 date into; consecutive days differ by exactly 1.
--   * a string - "YYYY-MM-DD", run through the civil calendar above, so month and
--                 year boundaries need no lookup table.
-- Anything else (nil, a boolean, a malformed date) yields nil: the caller has no
-- calendar day, and the day-based rules simply do not advance.
--
-- THE NUMBERING (L-6, re-audit 2026-10-20): one numbering for both forms - the
-- count of civil days since 1970-01-01, which is what the string form produces.
-- A numeric counter in a DIFFERENT numbering (a UTC day count, for instance) can
-- sit one day away from the string form; the two must never be mixed.
local function day_ordinal(day)
    if type(day) == "number" then
        if day ~= day or day == math.huge or day == -math.huge then return nil end
        return math.floor(day)
    end
    if type(day) ~= "string" then return nil end
    local y, m, d = day:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return nil end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or not m or not d then return nil end
    if m < 1 or m > 12 then return nil end
    if d < 1 or d > days_in_month(y, m) then return nil end
    return days_from_civil(y, m, d)
end

S.day_ordinal = day_ordinal

--=========================================================================================
-- State
--=========================================================================================

-- One scope holds a class's (or the account's) lifetime aggregates. The account
-- scope is the sum over the classes: every recorded attempt and session lands in the
-- class scope and in the account scope, so the two can never drift apart.
function S.new_scope()
    return {
        runs = 0,                -- completed sessions (a session with >= 1 attempt)
        attempts = 0,            -- graded attempts
        hits = 0,                -- attempts that were not a miss
        misses = 0,              -- attempts that missed (grade F)
        points = 0,              -- sum of GRADE_POINTS over all attempts
        best_session_score = 0,  -- best 0-100 session score
        best_grade = nil,        -- best single attempt grade, by GRADE_RANK
        best_s_streak = 0,       -- longest run of consecutive S grades
        s_run = 0,               -- live run of consecutive S grades
        time_active_seconds = 0, -- accumulated live-session time (injected)
        drills = {},             -- per-drill attempt table
        recent = {},             -- rolling window of the last SCORE_WINDOW hit flags
        history = {},            -- bounded session history (oldest first)
    }
end

-- A fresh stats state: no classes yet (each scope is created on demand), an empty
-- account scope, and no history.
function S.new_state()
    return {
        version = S.STATE_VERSION,
        classes = {},
        global = S.new_scope(),
    }
end

-- The class scope for a class key, created on demand. nil when the key is unusable.
local function class_scope(state, class_key)
    if type(class_key) ~= "string" or class_key == "" then return nil end
    if type(state.classes) ~= "table" then state.classes = {} end
    local scope = state.classes[class_key]
    if type(scope) ~= "table" then
        scope = S.new_scope()
        state.classes[class_key] = scope
    end
    return scope
end

-- Every scope a call writes to: the class scope (when the key is usable) and the
-- account scope. A caller that passes an unusable class key still keeps the account
-- totals correct.
local function write_scopes(state, class_key)
    local targets = {}
    if type(state.global) ~= "table" then state.global = S.new_scope() end
    local cs = class_scope(state, class_key)
    if cs then targets[#targets + 1] = cs end
    targets[#targets + 1] = state.global
    return targets
end

--=========================================================================================
-- Recording
--=========================================================================================

-- Record one graded attempt into the class scope and the account scope.
--
-- A grade outside the scoring model's set is not an attempt and changes nothing.
-- An F is an attempt: it counts as a miss and earns nothing.
function S.record_attempt(state, class_key, grade, drill_id)
    if type(state) ~= "table" then return state end
    if type(state.classes) ~= "table" then state.classes = {} end
    if not S.known_grade(grade) then return state end

    local hit = is_hit(grade)
    local points = grade_points(grade)
    local rank = grade_rank(grade)

    for _, scope in ipairs(write_scopes(state, class_key)) do
        scope.attempts = count(scope.attempts) + 1
        if hit then
            scope.hits = count(scope.hits) + 1
        else
            scope.misses = count(scope.misses) + 1
        end
        scope.points = count(scope.points) + points

        if rank > 0 and (not scope.best_grade or rank > grade_rank(scope.best_grade)) then
            scope.best_grade = grade
        end

        -- Longest run of consecutive S grades (the "perfect_ten" achievement reads it).
        if grade == "S" then
            scope.s_run = count(scope.s_run) + 1
            if scope.s_run > count(scope.best_s_streak) then
                scope.best_s_streak = scope.s_run
            end
        else
            scope.s_run = 0
        end

        -- Rolling window of hit flags (oldest first): the rolling-20 accuracy read.
        local recent = scope.recent
        if type(recent) ~= "table" then recent = {}; scope.recent = recent end
        recent[#recent + 1] = hit and 1 or 0
        while #recent > S.SCORE_WINDOW do table.remove(recent, 1) end

        -- Per-drill attempt table.
        if type(drill_id) == "string" and drill_id ~= "" then
            if type(scope.drills) ~= "table" then scope.drills = {} end
            local drill = scope.drills[drill_id]
            if type(drill) ~= "table" then
                drill = { attempts = 0, hits = 0 }
                scope.drills[drill_id] = drill
            end
            drill.attempts = count(drill.attempts) + 1
            if hit then drill.hits = count(drill.hits) + 1 end
        end
    end
    return state
end

-- Record one completed session: the session-level aggregates and the bounded history.
--
-- The attempt totals are NOT counted here - record_attempt already counted them, and
-- counting twice would double every lifetime number. A session with no attempts is
-- not a completed session: it adds no run, no history entry and no active time.
--
-- summary is the scoring model's own session summary (practice.score_summary): it
-- carries attempts, hits, score and best_grade. duration_seconds is the injected
-- live-session duration; only live time counts (spec §3: not while the panel idles).
function S.record_session(state, class_key, summary, duration_seconds, day)
    if type(state) ~= "table" then return state end
    if type(state.classes) ~= "table" then state.classes = {} end
    summary = (type(summary) == "table") and summary or {}

    local attempts = count(summary.attempts)
    -- The scopes are resolved first, so a class scope exists after the call even
    -- when the session turns out to be empty.
    local targets = write_scopes(state, class_key)
    if attempts <= 0 then return state end

    local hits = count(summary.hits)
    if hits > attempts then hits = attempts end
    local score = num(summary.score, 0)
    if score < 0 then score = 0 end
    local duration = num(duration_seconds, 0)
    if duration < 0 then duration = 0 end
    duration = math.floor(duration)
    local ordinal = day_ordinal(day)

    for _, scope in ipairs(targets) do
        scope.runs = count(scope.runs) + 1
        scope.time_active_seconds = count(scope.time_active_seconds) + duration

        if score > count(scope.best_session_score) then
            scope.best_session_score = math.floor(score)
        end

        local grade = summary.best_grade
        if type(grade) == "string" and grade_rank(grade) > grade_rank(scope.best_grade) then
            scope.best_grade = grade
        end

        local entry = {
            score = math.floor(score),
            accuracy = (hits / attempts),
            attempts = attempts,
            hits = hits,
            day = ordinal or S.NO_DAY,
            duration = duration,
        }
        local history = scope.history
        if type(history) ~= "table" then history = {}; scope.history = history end
        history[#history + 1] = entry
        while #history > S.HISTORY_LIMIT do table.remove(history, 1) end
    end
    return state
end

--=========================================================================================
-- Read model: snapshot + export payload
--=========================================================================================

-- The rolling-20 accuracy of a scope: hits over the last SCORE_WINDOW attempts.
local function rolling_accuracy(scope)
    local recent = scope.recent
    if type(recent) ~= "table" then return 0 end
    local n = #recent
    if n <= 0 then return 0 end
    local hits = 0
    for i = 1, n do
        if recent[i] == 1 then hits = hits + 1 end
    end
    return hits / n
end

-- The accuracy of the most recent session in the scope's history ring.
local function last_session_accuracy(scope)
    local history = scope.history
    if type(history) ~= "table" then return 0 end
    local last = history[#history]
    if type(last) ~= "table" then return 0 end
    return num(last.accuracy, 0)
end

-- The per-drill attempt table of a scope, as read-only rows.
local function drill_rows(scope)
    local rows = {}
    local drills = scope.drills
    if type(drills) ~= "table" then return rows end
    for id, drill in pairs(drills) do
        if type(drill) == "table" then
            local attempts = count(drill.attempts)
            local hits = count(drill.hits)
            if hits > attempts then hits = attempts end
            rows[id] = {
                attempts = attempts,
                hits = hits,
                accuracy = (attempts > 0) and (hits / attempts) or 0,
            }
        end
    end
    return rows
end

-- The read model of one scope.
local function scope_snapshot(scope)
    if type(scope) ~= "table" then scope = S.new_scope() end
    local attempts = count(scope.attempts)
    local hits = count(scope.hits)
    local history = scope.history
    if type(history) ~= "table" then history = {} end
    return {
        runs = count(scope.runs),
        attempts = attempts,
        hits = hits,
        misses = count(scope.misses),
        accuracy = (attempts > 0) and (hits / attempts) or 0,
        rolling_accuracy = rolling_accuracy(scope),
        last_session_accuracy = last_session_accuracy(scope),
        best_session_score = count(scope.best_session_score),
        best_grade = (type(scope.best_grade) == "string") and scope.best_grade or nil,
        best_s_streak = count(scope.best_s_streak),
        time_active_seconds = count(scope.time_active_seconds),
        drills = drill_rows(scope),
        history_count = #history,
        history = history,
    }
end

-- The full stats snapshot: every class scope plus the account scope, with the
-- bounded history each scope keeps. A malformed state degrades to zeros instead of
-- raising (spec §6 "Guards").
function S.snapshot(state)
    local out = {
        schema_version = S.STATE_VERSION,
        classes = {},
        global = scope_snapshot((type(state) == "table") and state.global or nil),
    }
    if type(state) == "table" and type(state.classes) == "table" then
        for class_key, scope in pairs(state.classes) do
            if type(class_key) == "string" and class_key ~= "" then
                out.classes[class_key] = scope_snapshot(scope)
            end
        end
    end
    return out
end

-- h:mm:ss of an accumulated duration (spec §3 "Time active"). Negative or malformed
-- durations read as 0:00:00.
function S.format_duration(seconds)
    local total = math.floor(num(seconds, 0))
    if total < 0 then total = 0 end
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local secs = total % 60
    return string.format("%d:%02d:%02d", hours, minutes, secs)
end

-- A JSON-safe copy of a value: only finite numbers, strings, booleans, dense arrays
-- and string-keyed objects survive; anything else (functions, NaN, the infinities,
-- mixed tables) is dropped. The export payload rides the addon's settings
-- export/import path (spec §6 "Export"), so it must survive a JSON encoder.
function S.json_safe(value)
    local t = type(value)
    if t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if t == "string" or t == "boolean" then return value end
    if t ~= "table" then return nil end
    local out = {}
    local length = #value
    if length > 0 then
        for i = 1, length do
            local item = S.json_safe(value[i])
            if item == nil then item = false end -- keep the array dense
            out[i] = item
        end
        return out
    end
    for key, item in pairs(value) do
        if type(key) == "string" then
            local safe = S.json_safe(item)
            if safe ~= nil then out[key] = safe end
        end
    end
    return out
end

-- The export payload of a stats state: a JSON-safe table with the account scope,
-- every class scope, and the bounded session history.
function S.export_payload(state)
    local snapshot = S.snapshot(state)
    local payload = {
        schema_version = S.STATE_VERSION,
        global = {
            runs = snapshot.global.runs,
            attempts = snapshot.global.attempts,
            hits = snapshot.global.hits,
            misses = snapshot.global.misses,
            accuracy = snapshot.global.accuracy,
            rolling_accuracy = snapshot.global.rolling_accuracy,
            last_session_accuracy = snapshot.global.last_session_accuracy,
            best_session_score = snapshot.global.best_session_score,
            best_grade = snapshot.global.best_grade or "",
            best_s_streak = snapshot.global.best_s_streak,
            time_active_seconds = snapshot.global.time_active_seconds,
            history_count = snapshot.global.history_count,
            history = snapshot.global.history,
        },
        classes = {},
    }
    for class_key, scope in pairs(snapshot.classes) do
        payload.classes[class_key] = {
            runs = scope.runs,
            attempts = scope.attempts,
            hits = scope.hits,
            misses = scope.misses,
            accuracy = scope.accuracy,
            rolling_accuracy = scope.rolling_accuracy,
            last_session_accuracy = scope.last_session_accuracy,
            best_session_score = scope.best_session_score,
            best_grade = scope.best_grade or "",
            best_s_streak = scope.best_s_streak,
            time_active_seconds = scope.time_active_seconds,
            history_count = scope.history_count,
            drills = scope.drills,
            history = scope.history,
        }
    end
    return S.json_safe(payload)
end

--=========================================================================================
-- Repair (load-time validation: bad types reset to defaults, nothing raises)
--=========================================================================================

-- Repair one scope: every field is re-derived from the saved value or the default.
local function repair_scope(scope)
    local out = S.new_scope()
    if type(scope) ~= "table" then return out end

    out.runs = count(scope.runs)
    out.attempts = count(scope.attempts)
    out.hits = count(scope.hits)
    out.misses = count(scope.misses)
    out.points = count(scope.points)
    out.best_session_score = count(scope.best_session_score)
    out.best_grade = (type(scope.best_grade) == "string") and scope.best_grade or nil
    out.best_s_streak = count(scope.best_s_streak)
    out.s_run = count(scope.s_run)
    out.time_active_seconds = count(scope.time_active_seconds)

    -- attempts is the hard bound: hits and misses can never exceed it.
    if out.hits > out.attempts then out.hits = out.attempts end
    if out.misses > out.attempts - out.hits then out.misses = out.attempts - out.hits end

    -- Rolling window of hit flags.
    if type(scope.recent) == "table" then
        local recent = {}
        for i = 1, #scope.recent do
            local flag = scope.recent[i]
            if flag == 1 or flag == 0 then recent[#recent + 1] = flag end
        end
        while #recent > S.SCORE_WINDOW do table.remove(recent, 1) end
        out.recent = recent
    end

    -- Per-drill table.
    if type(scope.drills) == "table" then
        local drills = {}
        for id, drill in pairs(scope.drills) do
            if type(id) == "string" and id ~= "" and type(drill) == "table" then
                local attempts = count(drill.attempts)
                local hits = count(drill.hits)
                if hits > attempts then hits = attempts end
                drills[id] = { attempts = attempts, hits = hits }
            end
        end
        out.drills = drills
    end

    -- Bounded session history.
    if type(scope.history) == "table" then
        local history = {}
        for i = 1, #scope.history do
            local entry = scope.history[i]
            if type(entry) == "table" then
                local attempts = count(entry.attempts)
                local hits = count(entry.hits)
                if hits > attempts then hits = attempts end
                -- The recorded day, read SIGNED.
                --
                -- M-3 (re-audit 2026-10-20): count() clamps a negative to 0, so the
                -- NO_DAY sentinel (-1, "no date recorded") was turned into 0 - the
                -- epoch - and the "if day < 0" branch below was dead code. The
                -- history row then rendered as 1970-01-01 instead of "-". The read
                -- is signed here, so the sentinel survives to the UI.
                local day = num(entry.day, S.NO_DAY)
                day = math.floor(day)
                if day < 0 then day = S.NO_DAY end
                local duration = count(entry.duration)
                history[#history + 1] = {
                    score = count(entry.score),
                    accuracy = num(entry.accuracy, 0),
                    attempts = attempts,
                    hits = hits,
                    day = day,
                    duration = duration,
                }
            end
        end
        while #history > S.HISTORY_LIMIT do table.remove(history, 1) end
        out.history = history
    end

    return out
end

-- Repair a stats state: unknown keys are dropped, bad types reset to defaults, and
-- a non-table state becomes a fresh one. Never raises.
function S.repair_state(state)
    if type(state) ~= "table" then return S.new_state() end
    local out = S.new_state()
    out.global = repair_scope(state.global)
    if type(state.classes) == "table" then
        for class_key, scope in pairs(state.classes) do
            if type(class_key) == "string" and class_key ~= "" then
                out.classes[class_key] = repair_scope(scope)
            end
        end
    end
    return out
end
