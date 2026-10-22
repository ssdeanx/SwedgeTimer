--=========================================================================================
-- Practice progression (pure): XP, levels, renown, per-drill mastery, streaks, daily XP
-- cap, the generic unlock registry, and the SwedgeTimerDB.profile.practice shape.
--
-- Design source: bench/practice_gamification_design_2026-10-19.md (spec §2 progression,
-- §4 achievements, §5 rewards, §6 engineering) plus the operator order of 2026-10-19
-- that the unlock registry carries TWO kinds (cosmetic unlocks and level-gated drill
-- variants). Foundation lane (spec §7 step 1): the rules live here, offline and
-- deterministic; the hook lane (step 2) feeds them from a live session, the UI lane
-- (step 3) reads the snapshot, step 5 exports the payload.
--
-- PURE by construction: no WoW API, no os.time, no randomness, no clock read, no
-- addon-owned state. The caller injects everything time-shaped:
--   * durations -> seconds (a number)
--   * dates     -> a day ordinal (a number) or a "YYYY-MM-DD" string (day_ordinal)
-- Malformed input degrades to zero / defaults; nothing here raises on bad data.
--
-- Ownership split with practice_stats.lua (one owner per number, no duplication):
--   progress : xp, level, renown, per-drill mastery + tier, the streaks (session /
--              best / daily), the daily per-drill XP cap, the unlock registry and
--              unlock state, and the saved-profile shape (schema_version / migrate /
--              validate).
--   stats    : lifetime aggregates (runs / attempts / hits / misses / accuracy / best
--              session score / best grade / time active), the per-drill attempt table,
--              the 50-session history ring, the stats snapshot and its export payload.
-- The merged read model - a level next to the stats numbers, mastery inside the
-- per-drill rows - is profile_snapshot below (it takes the stats snapshot as data, so
-- the two modules stay independent).
--
-- Load order: practice_stats.lua loads first (this module composes the saved profile
-- from both halves). Both are listed after practice.lua and before practice_ui.lua in
-- every flavour toc.
--=========================================================================================
local _, st = ...

st.practice_progress = st.practice_progress or {}
local P = st.practice_progress

--=========================================================================================
-- Constants
--=========================================================================================

-- Bumped when the persisted state shape changes; migrate() moves older blobs forward.
P.STATE_VERSION = 1

-- The persisted profile schema version (spec §6 "Persistence").
P.SCHEMA_VERSION = 1

-- Grade points, mirrored from st.practice.GRADE_POINTS (practice.lua:1339). The live
-- table wins at call time so a retune of the scoring model flows into XP without
-- touching this file; the mirror is the offline fallback. An F earns nothing - a
-- miss costs nothing, it just does not earn (spec §2). The grade RANK comparison is
-- not repeated here: the best grade belongs to the stats module, which owns it.
P.GRADE_POINTS = { S = 100, A = 80, B = 60, C = 40, D = 20, F = 0 }
-- The grade set the scoring model produces. F is the only zero-point grade and the
-- only miss (practice.lua:1393 grades a hit as anything but "F").
P.GRADES = { S = true, A = true, B = true, C = true, D = true, F = true }

-- Level curve: xp_for_level(n) = floor(100 * n^1.35) (spec §2 "Level curve") - the
-- XP needed to advance FROM level n TO level n+1. Diminishing returns, no wall.
P.LEVEL_CURVE_BASE = 100
P.LEVEL_CURVE_EXPONENT = 1.35

-- Level cap per class; past it the ladder becomes renown (spec §2 "Level cap"):
-- level 51 is renown 1, level 52 is renown 2.
P.MAX_LEVEL = 50

-- Session completion bonus (spec §2): +25 * completion_bonus_factor when a session
-- ends with at least 10 attempts - it rewards finishing a session, not grinding it.
P.SESSION_BONUS_XP = 25
P.SESSION_BONUS_MIN_ATTEMPTS = 10

-- The factor the spec names but does not value. The identity (1.0) is the flat +25
-- bonus as written; a later design pass may scale it.
P.COMPLETION_BONUS_FACTOR = 1.0

-- The completion bonus is a SHARE of what the session actually EARNED, never of how
-- many attempts it made (M3, re-audit 2026-10-20): an attempt is any graded attempt,
-- so ten misses are ten attempts and zero XP - and a bonus for zero XP is a grind
-- hole. The share is taken from the ALREADY capped awarded XP, so the daily
-- anti-grind cap still bounds the total: the bonus can only ever add a fraction of
-- what the cap allowed, and it never exceeds the flat +25 the spec writes.
P.SESSION_BONUS_XP_SHARE = 0.5

-- Mastery per drill (spec §2): recency-weighted accuracy over the last 100 attempts
-- with an exponential decay of a 30-attempt half-life, gated on 20 attempts of
-- volume (below that the drill reads Unranked - one lucky S never grants mastery).
P.MASTERY_WINDOW = 100
P.MASTERY_HALF_LIFE = 30
P.MASTERY_MIN_ATTEMPTS = 20

-- Mastery tiers: the accuracy and the lifetime attempt count a drill must reach.
P.MASTERY_TIERS = {
    bronze = { pct = 0.60, attempts = 20 },
    silver = { pct = 0.75, attempts = 50 },
    gold = { pct = 0.85, attempts = 100 },
    platinum = { pct = 0.95, attempts = 200 },
}

-- Tier order, for comparisons (a higher rank is a better tier).
P.TIER_RANK = { unranked = 0, bronze = 1, silver = 2, gold = 3, platinum = 4 }

-- The tier labels as they are displayed.
P.TIER_NAMES = {
    unranked = "Unranked",
    bronze = "Bronze",
    silver = "Silver",
    gold = "Gold",
    platinum = "Platinum",
}

-- Anti-grind (spec §2): the XP a single drill can earn per day is capped at 3x the
-- drill's median attempt XP. One drill cannot be farmed for infinite levels.
--
-- H-1 (re-audit 2026-10-20): the median is taken over the drill's HITS, not over
-- every attempt. A miss (F) earns nothing, so a drill below 50% accuracy had a
-- median of 0 and a cap of 0 - and every award was swallowed for good. The cap
-- keeps the spec's meaning (3x what the drill earns) and can no longer collapse.
P.DAILY_CAP_MULTIPLIER = 3

-- The scope key that reads the account scope (the sum over the classes).
P.GLOBAL_SCOPE = "GLOBAL"

-- Unlock kinds (operator order 2026-10-19): the registry carries both a cosmetic
-- kind and a drill-variant kind, and the spec's §4 achievements are the third kind.
P.KIND_ACHIEVEMENT = "achievement"
P.KIND_COSMETIC = "cosmetic"
P.KIND_DRILL_VARIANT = "drill_variant"

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
    return P.GRADES
end

-- Points for one grade (0 for an unknown grade).
local function grade_points(grade)
    local live = st.practice and st.practice.GRADE_POINTS
    local points
    if type(live) == "table" then points = live[grade] end
    if type(points) ~= "number" then points = P.GRADE_POINTS[grade] end
    if type(points) ~= "number" or points ~= points then return 0 end
    if points == math.huge or points == -math.huge then return 0 end
    return points
end

-- A hit is any grade but F - the same definition the scoring model uses
-- (practice.lua:1393).
local function is_hit(grade)
    return grade ~= "F"
end

-- Is the grade one the scoring model produces? The live scoring model's own grade
-- set is the truth; the mirror above is the offline fallback.
--
-- L-4 (re-audit 2026-10-20): the live score model counts ANY grade it is handed
-- (st.practice.record_attempt), while the pure modules drop a grade outside the
-- set - so a stray grade advanced the session score and vanished from the
-- progression, and the two drifted apart. The caller can now ask the pure side
-- before it records anything, and both pure modules answer the same way.
function P.known_grade(grade)
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
-- sit one day away from the string form, and the module cannot detect that: it
-- would roll the day over at the wrong hour and hand out an extra day's worth of
-- XP. The caller must therefore never mix the two forms - one numbering, one
-- source. The rollover itself is one-directional (see record_attempt), so a
-- backwards step can never wipe a day that was already earned.
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

P.day_ordinal = day_ordinal

--=========================================================================================
-- Level curve
--=========================================================================================

-- The XP needed to advance from level n to level n+1: floor(100 * n^1.35).
function P.xp_for_level(level)
    local n = count(level)
    if n < 1 then n = 1 end
    local value = P.LEVEL_CURVE_BASE * (n ^ P.LEVEL_CURVE_EXPONENT)
    if value ~= value then return 0 end
    if value == math.huge or value == -math.huge then return 0 end
    if value > 2 ^ 53 then return 2 ^ 53 end
    return math.floor(value)
end

-- The cumulative XP needed to reach a level from zero (the sum of the steps below it).
local LEVEL_SOLVE_MAX_STEPS = 100000 -- computational guard only, never reached by
-- real progression (level ~1400 needs ~1e9 XP); it stops a corrupt blob from hanging
-- the client.
local function cumulative_xp(level)
    local target = count(level)
    if target < 1 then return 0 end
    local total = 0
    local steps = 0
    while steps < LEVEL_SOLVE_MAX_STEPS and steps < target - 1 do
        total = total + P.xp_for_level(steps + 1)
        steps = steps + 1
    end
    return total
end

-- The cumulative XP needed to reach a level from zero (public form).
function P.xp_total_for_level(level)
    return cumulative_xp(level)
end

-- The level, renown and XP progress implied by an XP total. Past the level cap the
-- level stays at 50 and the renown counter takes over (spec §2 "Level cap").
function P.level_info(xp)
    local total = count(xp)
    local level = 1
    local spent = 0
    local steps = 0
    while steps < LEVEL_SOLVE_MAX_STEPS do
        local step = P.xp_for_level(level)
        if step <= 0 then break end
        if spent + step > total then break end
        spent = spent + step
        level = level + 1
        steps = steps + 1
    end
    local raw = level
    local display = raw
    local renown = 0
    if display > P.MAX_LEVEL then
        renown = display - P.MAX_LEVEL
        display = P.MAX_LEVEL
    end
    local need = P.xp_for_level(raw)
    return {
        level = display,
        renown = renown,
        raw_level = raw,
        xp = total,
        xp_into_level = total - spent,
        xp_for_next_level = need,
        xp_total_for_next = spent + need,
    }
end

--=========================================================================================
-- Mastery per drill
--=========================================================================================

-- The median of a list of numbers: the middle value, or the mean of the two middle
-- values for an even count. The list is sorted in place.
local function median_of(values)
    local n = #values
    if n <= 0 then return nil end
    table.sort(values)
    if n % 2 == 1 then return values[(n + 1) / 2] end
    return (values[n / 2] + values[n / 2 + 1]) / 2
end

-- The hit points of a drill's recent window: the grade points of every attempt that
-- was NOT a miss, with their median and their best.
--
-- H-1 (re-audit 2026-10-20): the cap used to be 3x the median over EVERY attempt in
-- the window. A miss earns nothing, so a drill below 50% accuracy had a median of 0
-- and a cap of 0 - and every award was swallowed for good (the player needed ~50
-- consecutive hits to escape, and the tier ladder is accuracy-gated too, so there
-- was no way out). The cap is now taken over the drill's HITS: a miss earns
-- nothing, so it must not drag the cap down.
--
-- nil when the window holds no hit at all - the first attempt of a drill cannot be
-- capped against a median that does not exist yet.
local function hit_points_window(recent)
    if type(recent) ~= "table" then return nil end
    local values = {}
    for i = 1, #recent do
        local grade = recent[i]
        if is_hit(grade) then
            local points = grade_points(grade)
            if points > 0 then values[#values + 1] = points end
        end
    end
    if #values <= 0 then return nil end
    local median = median_of(values)
    local best = values[#values] -- the list is sorted now
    return { median = median, best = best }
end

-- The recency-weighted accuracy over a drill's recent window, in percent. The
-- weights decay exponentially with a 30-attempt half-life: the newest attempt counts
-- full, one 30 attempts old counts half (spec §2 "Mastery per drill").
function P.mastery_pct(recent)
    if type(recent) ~= "table" then return 0 end
    local n = #recent
    if n <= 0 then return 0 end
    local weighted_hits = 0
    local weight_sum = 0
    for i = 1, n do
        local age = n - i -- 0 for the newest attempt
        local weight = 0.5 ^ (age / P.MASTERY_HALF_LIFE)
        weight_sum = weight_sum + weight
        if is_hit(recent[i]) then weighted_hits = weighted_hits + weight end
    end
    if weight_sum <= 0 then return 0 end
    return (weighted_hits / weight_sum) * 100
end

-- The tier a drill sits in. A drill needs BOTH the accuracy and the lifetime attempt
-- count of a tier; below the first one it reads Unranked (spec §2).
function P.tier_for(mastery_pct, attempts)
    local pct = num(mastery_pct, 0)
    local count_attempts = count(attempts)
    local best = "unranked"
    for name, tier in pairs(P.MASTERY_TIERS) do
        if pct >= (tier.pct * 100) and count_attempts >= tier.attempts then
            if (P.TIER_RANK[name] or 0) > (P.TIER_RANK[best] or 0) then
                best = name
            end
        end
    end
    return best
end

-- The mastery read model of one drill: the weighted accuracy, the tier and the
-- volume gate. The gate is why one lucky S never grants mastery.
function P.mastery(drill)
    if type(drill) ~= "table" then
        return {
            mastery_pct = 0,
            tier = "unranked",
            tier_name = P.TIER_NAMES.unranked,
            ranked = false,
            attempts = 0,
            hits = 0,
        }
    end
    local attempts = count(drill.attempts)
    local hits = count(drill.hits)
    if hits > attempts then hits = attempts end
    local pct = P.mastery_pct(drill.recent)
    local ranked = attempts >= P.MASTERY_MIN_ATTEMPTS
    local tier = "unranked"
    if ranked then tier = P.tier_for(pct, attempts) end
    return {
        mastery_pct = pct,
        tier = tier,
        tier_name = P.TIER_NAMES[tier] or P.TIER_NAMES.unranked,
        ranked = ranked,
        attempts = attempts,
        hits = hits,
    }
end

-- The daily XP cap of a drill: 3x the drill's median HIT points over the recent
-- window, with the best hit in that window as the floor (spec §2 "Anti-grind").
-- nil when the drill has no hit yet - the first attempt cannot be capped against a
-- median that does not exist yet.
--
-- The floor is what makes the guarantee hold: on a fresh day a hit is worth at
-- least its own points (the attempt being recorded is already in the window when
-- the cap is taken, so the floor is never below that attempt's grade points), and
-- the 3x median keeps the anti-grind - the drill cannot be farmed past three
-- times what it earns. The cap never exceeds 3x the best hit in the window.
--
-- The cap is read from the live window, so a low hit can lower it during a day;
-- the day's awards then stop. The day's total never exceeds the cap that was in
-- force when its award was made.
function P.drill_daily_cap(drill)
    if type(drill) ~= "table" then return nil end
    local window = hit_points_window(drill.recent)
    if window == nil then return nil end
    local cap = math.floor(window.median * P.DAILY_CAP_MULTIPLIER)
    if cap < window.best then cap = window.best end
    return cap
end

--=========================================================================================
-- State
--=========================================================================================

-- A fresh drill record: lifetime counters, the recent-grade window that feeds
-- mastery and the median, and today's capped XP.
local function new_drill()
    return {
        attempts = 0,
        hits = 0,
        recent = {},
        daily_xp = 0,
        daily_day = nil,
    }
end

-- A fresh class scope: the class's XP, its streaks, its drills and its unlocks.
local function new_class_scope()
    return {
        xp = 0,
        best_streak = 0,
        daily_streak = 0,
        last_session_day = nil,
        drills = {},
        unlocks = {},
    }
end

-- A fresh progress state: one scope per class (created on demand) plus the account
-- scope, which carries the account-wide day streak and the account-wide unlock flags.
function P.new_state()
    return {
        version = P.STATE_VERSION,
        classes = {},
        global = {
            daily_streak = 0,
            last_session_day = nil,
            unlocks = {},
        },
    }
end

-- A fresh session state: the live streak and the XP earned in this session. The
-- session is owned by the caller (one per practice session).
--
-- bonus_xp is the completion bonus this session has already been paid (M3): the
-- bonus is a share of the session's awarded XP, so the paid amount is what the
-- next end_session has to subtract from the session's XP to find the attempt XP.
function P.new_session()
    return {
        attempts = 0,
        hits = 0,
        streak = 0,
        best_streak = 0,
        xp = 0,
        bonus_xp = 0,
    }
end

-- The class scope for a class key, created on demand. nil when the key is unusable.
local function class_scope(progress, class_key)
    if type(class_key) ~= "string" or class_key == "" then return nil end
    if type(progress.classes) ~= "table" then progress.classes = {} end
    local scope = progress.classes[class_key]
    if type(scope) ~= "table" then
        scope = new_class_scope()
        progress.classes[class_key] = scope
    end
    return scope
end

-- The scope a call reads and writes: a class scope, or the account scope.
-- create = false keeps a read from adding an empty scope to the state.
local function scope_of(progress, scope_key, create)
    if type(progress) ~= "table" then return nil, false end
    if scope_key == P.GLOBAL_SCOPE then
        if type(progress.global) ~= "table" then
            if not create then return nil, true end
            progress.global = { daily_streak = 0, last_session_day = nil, unlocks = {} }
        end
        return progress.global, true
    end
    if create == false then
        local scope = (type(progress.classes) == "table") and progress.classes[scope_key] or nil
        if type(scope) ~= "table" then return nil, false end
        return scope, false
    end
    return class_scope(progress, scope_key), false
end

-- The XP of a scope: a class's own XP, or the account total (the sum over the
-- classes - the account XP is derived, never stored twice).
function P.scope_xp(progress, scope_key)
    if type(progress) ~= "table" then return 0 end
    if scope_key == P.GLOBAL_SCOPE then
        local total = 0
        if type(progress.classes) == "table" then
            for _, scope in pairs(progress.classes) do
                if type(scope) == "table" then total = total + count(scope.xp) end
            end
        end
        return total
    end
    local scope = scope_of(progress, scope_key, false)
    return scope and count(scope.xp) or 0
end

-- The lifetime best session streak of a scope: a class's own, or the account's
-- best over the classes.
function P.scope_best_streak(progress, scope_key)
    if type(progress) ~= "table" then return 0 end
    if scope_key == P.GLOBAL_SCOPE then
        local best = 0
        if type(progress.classes) == "table" then
            for _, scope in pairs(progress.classes) do
                if type(scope) == "table" then
                    local value = count(scope.best_streak)
                    if value > best then best = value end
                end
            end
        end
        return best
    end
    local scope = scope_of(progress, scope_key, false)
    return scope and count(scope.best_streak) or 0
end

-- The daily streak of a scope (consecutive calendar days with a completed session).
function P.scope_daily_streak(progress, scope_key)
    if type(progress) ~= "table" then return 0 end
    local scope = scope_of(progress, scope_key, false)
    if not scope then return 0 end
    return count(scope.daily_streak)
end

--=========================================================================================
-- Streaks
--=========================================================================================

-- Advance a scope's daily streak for a session that ended on the given day.
--
-- The streak counts consecutive calendar days with at least one completed session.
-- A missed day does NOT reset it - it simply stops the increment (spec §2 "Streaks":
-- no punishment for a rest day), so the reference day moves forward and the next
-- consecutive day counts again.
local function bump_daily_streak(scope, ordinal)
    if type(scope) ~= "table" or ordinal == nil then return false end
    local last = scope.last_session_day
    if type(last) ~= "number" then
        scope.daily_streak = 1
        scope.last_session_day = ordinal
        return true
    end
    if ordinal == last then
        return false -- already counted today
    end
    if ordinal == last + 1 then
        scope.daily_streak = count(scope.daily_streak) + 1
        scope.last_session_day = ordinal
        return true
    end
    -- A gap: no increment, no reset.
    scope.last_session_day = ordinal
    return false
end

--=========================================================================================
-- Recording
--=========================================================================================

-- Record one graded attempt: XP (after the daily per-drill cap), the session streak,
-- the drill's counters and its recent-grade window.
--
-- A grade outside the scoring model's set is not an attempt and changes nothing. An
-- F is an attempt: it earns nothing and it breaks the streak.
--
-- progress and session are both mutated in place; the progress state is returned for
-- convenience.
function P.record_attempt(progress, session, class_key, drill_id, grade, day)
    if type(progress) ~= "table" then return progress end
    if not P.known_grade(grade) then return progress end
    local scope = class_scope(progress, class_key)
    if not scope then return progress end
    if type(session) ~= "table" then session = P.new_session() end

    local hit = is_hit(grade)
    local points = grade_points(grade)

    session.attempts = count(session.attempts) + 1
    if hit then session.hits = count(session.hits) + 1 end
    if hit then
        session.streak = count(session.streak) + 1
    else
        session.streak = 0
    end
    if count(session.streak) > count(session.best_streak) then
        session.best_streak = count(session.streak)
    end
    if count(session.streak) > count(scope.best_streak) then
        scope.best_streak = count(session.streak)
    end

    -- The drill record: lifetime counters plus the recent-grade window. An attempt
    -- with no usable drill id lands in the reserved "_unknown" bucket, so its XP is
    -- still tracked and still capped (a caller cannot dodge the anti-grind cap by
    -- dropping the drill id).
    if type(scope.drills) ~= "table" then scope.drills = {} end
    local key = (type(drill_id) == "string" and drill_id ~= "") and drill_id or "_unknown"
    local drill = scope.drills[key]
    if type(drill) ~= "table" then
        drill = new_drill()
        scope.drills[key] = drill
    end
    drill.attempts = count(drill.attempts) + 1
    if hit then drill.hits = count(drill.hits) + 1 end
    local recent = drill.recent
    if type(recent) ~= "table" then recent = {}; drill.recent = recent end
    recent[#recent + 1] = grade
    while #recent > P.MASTERY_WINDOW do table.remove(recent, 1) end

    -- The daily cap: the day's earned XP resets on a new calendar day, and the cap
    -- is 3x the drill's median HIT points over the window above.
    --
    -- L-6 (re-audit 2026-10-20): the rollover used to fire on ANY difference
    -- between the stored day and the new one, so a BACKWARDS clock (a client whose
    -- calendar steps back, or a caller that mixes two day numberings) wiped the
    -- day's XP and handed the player a free extra day. The rollover is now
    -- ONE-DIRECTIONAL: only a day strictly later than the stored one starts a new
    -- day; an earlier or the same day leaves the day's XP alone.
    local ordinal = day_ordinal(day)
    local stored = drill.daily_day
    if ordinal ~= nil and (type(stored) ~= "number" or ordinal > stored) then
        drill.daily_xp = 0
        drill.daily_day = ordinal
    end
    local awarded = points
    local cap = P.drill_daily_cap(drill)
    if cap ~= nil then
        local room = cap - count(drill.daily_xp)
        if room <= 0 then
            awarded = 0
        elseif awarded > room then
            awarded = room
        end
    end
    drill.daily_xp = count(drill.daily_xp) + awarded
    scope.xp = count(scope.xp) + awarded
    session.xp = count(session.xp) + awarded

    return progress
end

-- End a session: the completion bonus, the daily streak of the class scope and of
-- the account scope, and the level the class landed on.
--
-- opts.completion_bonus_factor scales the +25 completion bonus (spec §2); the
-- default is the identity, the flat +25 the spec writes.
function P.end_session(progress, session, class_key, day, opts)
    opts = (type(opts) == "table") and opts or {}
    local result = {
        attempts = 0,
        xp_earned = 0,
        bonus_xp = 0,
        leveled_up = false,
        level = 1,
        renown = 0,
        daily_streak = 0,
    }
    if type(progress) ~= "table" then return result end
    local scope = class_scope(progress, class_key)
    if not scope then return result end
    if type(session) ~= "table" then session = P.new_session() end

    local attempts = count(session.attempts)
    result.attempts = attempts
    if attempts <= 0 then
        -- Nothing was practised: no bonus, and the day streak does not move.
        result.level = P.level_info(P.scope_xp(progress, class_key)).level
        return result
    end

    local before = P.level_info(P.scope_xp(progress, class_key))

    -- Completion bonus: rewards finishing a session, not grinding it.
    --
    -- M3 (re-audit 2026-10-20): the bonus used to be a flat +25 for a session with
    -- ten ATTEMPTS, and it was added straight to the scope's XP - outside the daily
    -- per-drill cap, so it was pure profit on top of a capped day. Ten misses (ten F
    -- grades, zero attempt XP) earned the full bonus.
    --
    -- The bonus is now a SHARE of what the session actually EARNED through the
    -- capped attempt path: never more than the flat +25 the spec writes and never
    -- more than the share of the session's awarded XP. A session that earned
    -- nothing earns no bonus, and because the share comes out of ALREADY capped
    -- XP, the daily cap still bounds the total. The bonus is also paid ONCE per
    -- session: the paid amount is remembered on the session, so a second
    -- end_session on the same session pays nothing more.
    if attempts >= P.SESSION_BONUS_MIN_ATTEMPTS and count(session.bonus_xp) == 0 then
        local factor = num(opts.completion_bonus_factor, P.COMPLETION_BONUS_FACTOR)
        if factor < 0 then factor = 0 end
        local earned = count(session.xp)
        local bonus = math.floor(P.SESSION_BONUS_XP * factor)
        local share = math.floor(earned * P.SESSION_BONUS_XP_SHARE)
        if share < bonus then bonus = share end
        if bonus > 0 then
            scope.xp = count(scope.xp) + bonus
            session.xp = count(session.xp) + bonus
            session.bonus_xp = bonus
            result.bonus_xp = bonus
        end
    end

    -- The daily streak: the class scope and the account scope each track their own
    -- consecutive-day run.
    local ordinal = day_ordinal(day)
    bump_daily_streak(scope, ordinal)
    if type(progress.global) ~= "table" then
        progress.global = { daily_streak = 0, last_session_day = nil, unlocks = {} }
    end
    bump_daily_streak(progress.global, ordinal)

    local after = P.level_info(P.scope_xp(progress, class_key))
    result.xp_earned = count(session.xp)
    result.level = after.level
    result.renown = after.renown
    result.leveled_up = (after.raw_level > before.raw_level)
    result.daily_streak = count(scope.daily_streak)
    return result
end

--=========================================================================================
-- The generic unlock registry
--=========================================================================================
--
-- The registry maps an unlock id to its definition: a requirement, a kind and the
-- unlock state. The spec's §4 achievements are the "achievement" kind; the operator
-- order of 2026-10-19 adds the "cosmetic" kind (themes, popup styles, titles) and
-- the "drill_variant" kind (level-gated harder variants).
--
-- HARD RULE (operator order): an unlock NEVER changes how an existing drill behaves.
-- A drill variant is registered as its OWN scenario by the practice layer; this
-- module only records that the variant is unlocked. There is no grading, timing or
-- sim code here at all, and a drill variant names the new scenario it grants - it
-- never points at an existing drill to modify.
--
-- Requirement forms:
--   { type = "level", level = N }         the scope's level must be at least N
--   { type = "achievement", id = "..." }   that unlock id must already be unlocked
--   { type = "predicate", test = fn }      fn(snapshot) must return a truthy value
-- An unknown or malformed requirement is never met: an unlock the module cannot
-- understand stays locked rather than firing by accident.
--
-- THE SCOPE CONTRACT (M-2, re-audit 2026-10-20): the unlock flags live in the
-- scope they were earned in - a class scope (progress.classes[key].unlocks) or the
-- account scope (progress.global.unlocks). A definition with
-- scope = "class" is only ever evaluated in a class scope, one with
-- scope = "account" only in the account scope, and one with NO scope in BOTH.
--
-- The consequence a caller must honour: an account-scoped achievement can only
-- fire when the ACCOUNT scope is evaluated, and the account scope is a scope of
-- its own. Evaluating only the class scope leaves every account-scoped
-- achievement locked for good (and the account model reports none of them).
-- P.evaluate_unlocks_both does both evaluations and merges the two results - the
-- session-end path uses it.
--
-- The registry: id -> definition. Later lanes add to it through register_unlock.
P.UNLOCKS = {}

-- Register an unlock definition. Returns the stored definition, or nil when the
-- input is unusable.
--
-- spec = {
--   kind        = "cosmetic" | "drill_variant" | "achievement",
--   label       = "display text",
--   requirement = <requirement table>,
--   scenario    = "the NEW scenario key" (drill_variant only),
--   scope       = "class" | "account" (optional; both by default),
-- }
function P.register_unlock(id, spec)
    if type(id) ~= "string" or id == "" then return nil end
    if type(spec) ~= "table" then return nil end
    local kind = spec.kind
    if kind ~= P.KIND_ACHIEVEMENT and kind ~= P.KIND_COSMETIC and kind ~= P.KIND_DRILL_VARIANT then
        -- L-1 (re-audit 2026-10-20): an unknown kind is REJECTED, not coerced. A
        -- typo'd kind used to be stored as a cosmetic, so the definition was
        -- accepted and then granted nothing - a silent dead unlock. A missing kind
        -- is rejected the same way: the kind is not optional.
        return nil
    end
    local scenario = nil
    if kind == P.KIND_DRILL_VARIANT then
        -- A variant must name the scenario it grants. Without it the definition is
        -- unusable, so it is rejected rather than stored half-formed.
        if type(spec.scenario) ~= "string" or spec.scenario == "" then return nil end
        scenario = spec.scenario
    end
    local scope = spec.scope
    if scope ~= "class" and scope ~= "account" then scope = nil end
    -- The requirement is COPIED, never aliased: the registry must not hold a
    -- reference into a live table (the hard rule above - an unlock never reaches
    -- into a drill's own data). A later change to the caller's table cannot
    -- rewrite a registered requirement behind the registry's back.
    local requirement = nil
    if type(spec.requirement) == "table" then
        requirement = {}
        for key, value in pairs(spec.requirement) do
            requirement[key] = value
        end
    end
    local definition = {
        id = id,
        kind = kind,
        label = (type(spec.label) == "string") and spec.label or id,
        requirement = requirement,
        scenario = scenario,
        scope = scope,
    }
    P.UNLOCKS[id] = definition
    return definition
end

-- The registered definitions of one kind (all kinds when kind is nil), sorted by id
-- so the UI can render a stable list.
function P.unlock_definitions(kind)
    local out = {}
    for _, definition in pairs(P.UNLOCKS) do
        if type(definition) == "table" and (kind == nil or definition.kind == kind) then
            out[#out + 1] = definition
        end
    end
    table.sort(out, function(a, b) return (a.id or "") < (b.id or "") end)
    return out
end

-- The scenario key an unlock grants, or nil. Only the drill-variant kind names a
-- scenario: a level-gated harder variant is a NEW scenario (the audit's §4.3
-- requirement - "a drill variant names the new scenario it grants"), never a
-- change to an existing drill. The key is the practice layer's own registry key
-- (the same key space the class drills and the rotation scenarios use), so the
-- unlock lane can point at a drill or a scenario without a second namespace.
function P.unlock_scenario(id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    local definition = P.UNLOCKS[id]
    if type(definition) ~= "table" then
        return nil
    end
    if definition.kind ~= P.KIND_DRILL_VARIANT then
        return nil
    end
    return definition.scenario
end

-- Is a requirement met by a snapshot? See the requirement forms above.
local function requirement_met(requirement, snapshot)
    if type(requirement) ~= "table" then return false end
    local kind = requirement.type
    if kind == "level" then
        local level = num(requirement.level, nil)
        if level == nil then return false end
        local current = num(snapshot and snapshot.level, 0) or 0
        return current >= level
    end
    if kind == "achievement" then
        local id = requirement.id
        if type(id) ~= "string" then return false end
        local unlocked = snapshot and snapshot.unlocks
        if type(unlocked) ~= "table" then return false end
        return unlocked[id] == true
    end
    if kind == "predicate" then
        if type(requirement.test) ~= "function" then return false end
        local ok, passed = pcall(requirement.test, snapshot)
        if not ok then return false end
        return passed and true or false
    end
    return false
end

-- Evaluate the registry against one scope's snapshot and unlock whatever the scope
-- has earned. The unlock flags live in the scope, so a class-level unlock never
-- leaks into another class.
--
-- Returns { newly = {ids}, unlocked = {ids} } - "newly" is what the toast / chat
-- notice lane fires on, "unlocked" is the full set for the scope.
function P.evaluate_unlocks(progress, snapshot, scope_key)
    local out = { newly = {}, unlocked = {} }
    if type(progress) ~= "table" then return out end
    local scope, is_account = scope_of(progress, scope_key, true)
    if not scope then return out end
    if type(scope.unlocks) ~= "table" then scope.unlocks = {} end

    local ids = {}
    for id in pairs(P.UNLOCKS) do ids[#ids + 1] = id end
    table.sort(ids)

    -- The evaluation reads the scope's LIVE unlock flags, not the snapshot's copy:
    -- an achievement-gated unlock must see an achievement unlocked earlier in this
    -- same pass. The caller's snapshot is not mutated - a shallow copy carries the
    -- live map instead.
    local eval_snapshot = snapshot
    if type(snapshot) == "table" then
        eval_snapshot = {}
        for key, value in pairs(snapshot) do eval_snapshot[key] = value end
    elseif snapshot == nil then
        eval_snapshot = {}
    end
    eval_snapshot.unlocks = scope.unlocks

    for _, id in ipairs(ids) do
        local definition = P.UNLOCKS[id]
        if type(definition) == "table" then
            -- A scope-restricted unlock is only evaluated in its own kind of scope.
            local allowed = true
            if definition.scope == "class" then allowed = not is_account end
            if definition.scope == "account" then allowed = is_account end
            if allowed then
                local unlocked = scope.unlocks[id] == true
                if not unlocked and requirement_met(definition.requirement, eval_snapshot) then
                    scope.unlocks[id] = true
                    unlocked = true
                    out.newly[#out.newly + 1] = id
                end
                if unlocked then out.unlocked[id] = true end
            end
        end
    end
    table.sort(out.newly)
    return out
end

-- Evaluate the registry in the CLASS scope and in the ACCOUNT scope and merge the
-- two results.
--
-- M-2 (re-audit 2026-10-20): the production path evaluated the class scope only,
-- so progress.global.unlocks was never written and every account-scoped
-- achievement could never fire - the account model reported none of them. The two
-- scopes carry separate flags, so the account scope needs its own evaluation.
--
-- class_snapshot is the read model of the class scope, account_snapshot the read
-- model of the account scope (both from P.profile_snapshot). The account
-- snapshot is optional: without it only the class scope is evaluated, exactly as
-- P.evaluate_unlocks does.
--
-- Returns { newly = {ids}, unlocked = {ids} } - "newly" is the merge of the two
-- scopes' newly unlocked ids (sorted, no duplicates), "unlocked" the union of the
-- two scopes' unlocked sets. An id unlocked in both scopes appears once.
function P.evaluate_unlocks_both(progress, class_key, class_snapshot, account_snapshot)
    local out = { newly = {}, unlocked = {} }
    local seen = {}
    local function merge(result)
        if type(result) ~= "table" then return end
        if type(result.newly) == "table" then
            for _, id in ipairs(result.newly) do
                if type(id) == "string" and not seen[id] then
                    seen[id] = true
                    out.newly[#out.newly + 1] = id
                end
            end
        end
        if type(result.unlocked) == "table" then
            for id, flag in pairs(result.unlocked) do
                if flag == true then out.unlocked[id] = true end
            end
        end
    end
    merge(P.evaluate_unlocks(progress, class_snapshot, class_key))
    if account_snapshot ~= nil then
        merge(P.evaluate_unlocks(progress, account_snapshot, P.GLOBAL_SCOPE))
    end
    table.sort(out.newly)
    return out
end

-- Is an unlock id unlocked in a scope?
function P.is_unlocked(progress, id, scope_key)
    if type(progress) ~= "table" or type(id) ~= "string" then return false end
    local scope = scope_of(progress, scope_key, false)
    if not scope or type(scope.unlocks) ~= "table" then return false end
    return scope.unlocks[id] == true
end

-- The unlocked ids of a scope, sorted.
function P.unlocked_ids(progress, scope_key)
    local out = {}
    local scope = scope_of(progress, scope_key, false)
    if scope and type(scope.unlocks) == "table" then
        for id, flag in pairs(scope.unlocks) do
            if flag == true then out[#out + 1] = id end
        end
    end
    table.sort(out)
    return out
end

-- The spec's §4 achievements, registered as the "achievement" kind of the registry.
-- The thresholds are the ones the ids name: first_s (one S), perfect_ten (ten S in
-- a row), hundred_attempts (100), level_10 (level 10), week_streak (seven days),
-- ten_hours (36000 seconds), all_drills_gold (every drill at Gold or better).
P.register_unlock("first_s", {
    kind = P.KIND_ACHIEVEMENT,
    label = "First S",
    requirement = {
        type = "predicate",
        test = function(snapshot)
            return type(snapshot) == "table" and snapshot.best_grade == "S"
        end,
    },
})

P.register_unlock("perfect_ten", {
    kind = P.KIND_ACHIEVEMENT,
    label = "Ten S in a row",
    requirement = {
        type = "predicate",
        test = function(snapshot)
            return type(snapshot) == "table" and (num(snapshot.best_s_streak, 0) or 0) >= 10
        end,
    },
})

P.register_unlock("hundred_attempts", {
    kind = P.KIND_ACHIEVEMENT,
    label = "100 attempts",
    requirement = {
        type = "predicate",
        test = function(snapshot)
            return type(snapshot) == "table" and (num(snapshot.attempts, 0) or 0) >= 100
        end,
    },
})

P.register_unlock("all_drills_gold", {
    kind = P.KIND_ACHIEVEMENT,
    label = "Every drill gold",
    requirement = {
        type = "predicate",
        test = function(snapshot)
            if type(snapshot) ~= "table" or type(snapshot.drills) ~= "table" then return false end
            local seen = 0
            for _, row in pairs(snapshot.drills) do
                if type(row) == "table" then
                    seen = seen + 1
                    local rank = P.TIER_RANK[row.tier] or 0
                    if rank < (P.TIER_RANK.gold or 0) then return false end
                end
            end
            return seen > 0
        end,
    },
})

P.register_unlock("level_10", {
    kind = P.KIND_ACHIEVEMENT,
    label = "Level 10",
    requirement = { type = "level", level = 10 },
})

P.register_unlock("week_streak", {
    kind = P.KIND_ACHIEVEMENT,
    label = "Seven day streak",
    requirement = {
        type = "predicate",
        test = function(snapshot)
            return type(snapshot) == "table" and (num(snapshot.daily_streak, 0) or 0) >= 7
        end,
    },
})

P.register_unlock("ten_hours", {
    kind = P.KIND_ACHIEVEMENT,
    label = "Ten hours of practice",
    requirement = {
        type = "predicate",
        test = function(snapshot)
            return type(snapshot) == "table"
                and (num(snapshot.time_active_seconds, 0) or 0) >= 36000
        end,
    },
})

--=========================================================================================
-- The merged read model
--=========================================================================================

-- The per-drill rows of one scope: the progress side (mastery, tier) merged with the
-- stats side (attempts, accuracy).
local function drill_rows(progress, scope_key, stats_scope)
    local rows = {}
    if type(progress) ~= "table" then return rows end
    local stats_drills = (type(stats_scope) == "table") and stats_scope.drills or {}
    local progress_drills = {}
    if scope_key == P.GLOBAL_SCOPE then
        -- The account scope merges every class's drills (drill ids are unique per
        -- class in the shipped registry).
        if type(progress.classes) == "table" then
            for _, scope in pairs(progress.classes) do
                if type(scope) == "table" and type(scope.drills) == "table" then
                    for id, drill in pairs(scope.drills) do
                        progress_drills[id] = drill
                    end
                end
            end
        end
    else
        local scope = scope_of(progress, scope_key, false)
        if scope and type(scope.drills) == "table" then progress_drills = scope.drills end
    end

    local ids = {}
    for id in pairs(progress_drills) do ids[#ids + 1] = id end
    for id in pairs(stats_drills) do
        if progress_drills[id] == nil then ids[#ids + 1] = id end
    end
    table.sort(ids)

    for _, id in ipairs(ids) do
        local mastery = P.mastery(progress_drills[id])
        local stats_row = (type(stats_drills) == "table") and stats_drills[id] or nil
        rows[id] = {
            attempts = mastery.attempts,
            hits = mastery.hits,
            accuracy = (type(stats_row) == "table") and (num(stats_row.accuracy, 0) or 0) or 0,
            stats_attempts = (type(stats_row) == "table") and (num(stats_row.attempts, 0) or 0) or 0,
            mastery_pct = mastery.mastery_pct,
            tier = mastery.tier,
            tier_name = mastery.tier_name,
            ranked = mastery.ranked,
            daily_xp = (type(progress_drills[id]) == "table")
                and (num(progress_drills[id].daily_xp, 0) or 0) or 0,
        }
    end
    return rows
end

-- The merged snapshot of one scope: the progression read model with the stats
-- snapshot merged in. scope_key is a class key or P.GLOBAL_SCOPE (the default).
--
-- The stats scalars are lifted to the TOP level as well as kept under .stats: the
-- achievement predicates read one flat snapshot (best_grade, best_s_streak,
-- attempts, time_active_seconds next to level, daily_streak and the drill rows), so
-- the caller does not have to merge two read models by hand before it can evaluate
-- them. The .stats sub-table keeps the full scope for the Progress page.
function P.profile_snapshot(progress, stats_snapshot, scope_key)
    if scope_key == nil then scope_key = P.GLOBAL_SCOPE end
    stats_snapshot = (type(stats_snapshot) == "table") and stats_snapshot or {}
    local info = P.level_info(P.scope_xp(progress, scope_key))
    local stats_scope
    if scope_key == P.GLOBAL_SCOPE then
        stats_scope = stats_snapshot.global
    else
        stats_scope = (type(stats_snapshot.classes) == "table") and stats_snapshot.classes[scope_key] or nil
    end
    stats_scope = (type(stats_scope) == "table") and stats_scope or {}

    local snapshot = {
        scope = scope_key,
        level = info.level,
        renown = info.renown,
        raw_level = info.raw_level,
        xp = info.xp,
        xp_into_level = info.xp_into_level,
        xp_for_next_level = info.xp_for_next_level,
        xp_total_for_next = info.xp_total_for_next,
        best_streak = P.scope_best_streak(progress, scope_key),
        daily_streak = P.scope_daily_streak(progress, scope_key),
        drills = drill_rows(progress, scope_key, stats_scope),
        unlocks = {},
        stats = stats_scope,
    }
    -- The stats scalars, lifted to the top level (the achievement predicates read
    -- them flat). A missing value stays absent (nil), never a zero that would
    -- read as a real measurement.
    local STATS_FIELDS = {
        "runs", "attempts", "hits", "misses", "accuracy", "rolling_accuracy",
        "last_session_accuracy", "best_session_score", "best_grade", "best_s_streak",
        "time_active_seconds",
    }
    for _, field in ipairs(STATS_FIELDS) do
        local value = stats_scope[field]
        if value ~= nil then
            snapshot[field] = value
        end
    end
    for _, id in ipairs(P.unlocked_ids(progress, scope_key)) do
        snapshot.unlocks[id] = true
    end
    return snapshot
end

-- A JSON-safe copy of a value: only finite numbers, strings, booleans, dense arrays
-- and string-keyed objects survive; anything else is dropped. The export payload
-- rides the addon's settings export/import path (spec §6 "Export").
function P.json_safe(value)
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
            local item = P.json_safe(value[i])
            if item == nil then item = false end
            out[i] = item
        end
        return out
    end
    for key, item in pairs(value) do
        if type(key) == "string" then
            local safe = P.json_safe(item)
            if safe ~= nil then out[key] = safe end
        end
    end
    return out
end

-- The export payload of a progress state: the levels, the streaks, the per-drill
-- mastery and the unlock flags, JSON-safe.
function P.export_payload(progress)
    local payload = {
        schema_version = P.STATE_VERSION,
        classes = {},
        global = {},
    }
    local function scope_payload(scope_key)
        local info = P.level_info(P.scope_xp(progress, scope_key))
        local rows = drill_rows(progress, scope_key, nil)
        return {
            xp = info.xp,
            level = info.level,
            renown = info.renown,
            xp_into_level = info.xp_into_level,
            xp_for_next_level = info.xp_for_next_level,
            best_streak = P.scope_best_streak(progress, scope_key),
            daily_streak = P.scope_daily_streak(progress, scope_key),
            drills = rows,
            unlocks = P.unlocked_ids(progress, scope_key),
        }
    end
    payload.global = scope_payload(P.GLOBAL_SCOPE)
    if type(progress) == "table" and type(progress.classes) == "table" then
        local keys = {}
        for class_key in pairs(progress.classes) do keys[#keys + 1] = class_key end
        table.sort(keys)
        for _, class_key in ipairs(keys) do
            payload.classes[class_key] = scope_payload(class_key)
        end
    end
    return P.json_safe(payload)
end

--=========================================================================================
-- Persistence: SwedgeTimerDB.profile.practice
--=========================================================================================
--
-- The saved blob is a table with a schema_version, the progress state and the stats
-- state. The rules (spec §6 "Persistence"):
--   * unknown keys are ignored (dropped)
--   * a bad type resets to the default
--   * a corrupt blob falls back to a fresh state WITHOUT throwing
--   * other saved variables are never touched - migrate() only ever sees the
--     practice blob and returns a NEW table, so the caller replaces its own key and
--     nothing else.
--
-- A blob written by a NEWER build (schema_version above ours) is returned unchanged:
-- we do not understand it, and we never wipe data we do not understand. The caller
-- can spot that with is_current() and leave the blob alone.

-- A fresh saved profile: the current schema version, an empty progress state and an
-- empty stats state.
function P.new_profile()
    local stats_state = nil
    local stats = st.practice_stats
    if stats and type(stats.new_state) == "function" then
        local ok, state = pcall(stats.new_state)
        if ok and type(state) == "table" then stats_state = state end
    end
    return {
        schema_version = P.SCHEMA_VERSION,
        progress = P.new_state(),
        stats = stats_state or {},
    }
end

-- Is a blob one this build understands (schema_version present and not newer)?
function P.is_current(blob)
    if type(blob) ~= "table" then return false end
    local version = num(blob.schema_version, nil)
    if version == nil then return false end
    return version <= P.SCHEMA_VERSION
end

-- Migrate and repair a saved profile. Never raises; always returns a table.
--
--   non-table blob        -> a fresh profile
--   missing / bad version -> migrated forward from the earliest format and repaired
--   newer version         -> the blob unchanged (a newer build owns it)
function P.migrate(blob)
    if type(blob) ~= "table" then return P.new_profile() end
    local version = num(blob.schema_version, nil)
    if version ~= nil and version > P.SCHEMA_VERSION then
        return blob
    end
    local profile = {
        schema_version = P.SCHEMA_VERSION,
        progress = P.repair_state(blob.progress),
        stats = P.repair_stats(blob.stats),
    }
    return profile
end

-- The load-time validation + repair path (spec §6): the same guarantee as migrate(),
-- named for what the caller does with it.
function P.validate(blob)
    return P.migrate(blob)
end

-- Repair the stats half of a saved profile (delegated to the stats module).
function P.repair_stats(state)
    local stats = st.practice_stats
    if stats and type(stats.repair_state) == "function" then
        local ok, repaired = pcall(stats.repair_state, state)
        if ok and type(repaired) == "table" then return repaired end
    end
    return {}
end

-- Repair one drill record: bad types reset, unknown grades become F (a 0-point
-- miss), the window is trimmed to the mastery window.
local function repair_drill(drill)
    local out = new_drill()
    if type(drill) ~= "table" then return out end
    if type(drill.recent) == "table" then
        local recent = {}
        for i = 1, #drill.recent do
            local grade = drill.recent[i]
            if type(grade) == "string" then
                recent[#recent + 1] = grade_set()[grade] and grade or "F"
            end
        end
        while #recent > P.MASTERY_WINDOW do table.remove(recent, 1) end
        out.recent = recent
    end
    out.attempts = count(drill.attempts)
    if out.attempts < #out.recent then out.attempts = #out.recent end
    out.hits = count(drill.hits)
    if out.hits > out.attempts then out.hits = out.attempts end
    out.daily_xp = count(drill.daily_xp)
    local day = day_ordinal(drill.daily_day)
    if day ~= nil then out.daily_day = day end
    return out
end

-- Repair one class scope: unknown keys are dropped and every field falls back to
-- its default.
local function repair_class_scope(scope)
    local out = new_class_scope()
    if type(scope) ~= "table" then return out end
    out.xp = count(scope.xp)
    out.best_streak = count(scope.best_streak)
    out.daily_streak = count(scope.daily_streak)
    local day = day_ordinal(scope.last_session_day)
    if day ~= nil then out.last_session_day = day end
    if type(scope.drills) == "table" then
        for id, drill in pairs(scope.drills) do
            if type(id) == "string" and id ~= "" then
                out.drills[id] = repair_drill(drill)
            end
        end
    end
    if type(scope.unlocks) == "table" then
        -- An unlock flag the current build does not know about is KEPT, not dropped:
        -- a downgrade must not silently un-unlock a cosmetic or a variant.
        for id, flag in pairs(scope.unlocks) do
            if type(id) == "string" and flag == true then out.unlocks[id] = true end
        end
    end
    return out
end

-- Repair the account scope of a progress state.
local function repair_global_scope(scope)
    local out = { daily_streak = 0, last_session_day = nil, unlocks = {} }
    if type(scope) ~= "table" then return out end
    out.daily_streak = count(scope.daily_streak)
    local day = day_ordinal(scope.last_session_day)
    if day ~= nil then out.last_session_day = day end
    if type(scope.unlocks) == "table" then
        for id, flag in pairs(scope.unlocks) do
            if type(id) == "string" and flag == true then out.unlocks[id] = true end
        end
    end
    return out
end

-- Repair a progress state: unknown keys are dropped, bad types reset to the
-- defaults, and a non-table state becomes a fresh one. Never raises.
function P.repair_state(state)
    if type(state) ~= "table" then return P.new_state() end
    local out = P.new_state()
    if type(state.classes) == "table" then
        for class_key, scope in pairs(state.classes) do
            if type(class_key) == "string" and class_key ~= "" then
                out.classes[class_key] = repair_class_scope(scope)
            end
        end
    end
    out.global = repair_global_scope(state.global)
    return out
end
