-- tests/practice_progress_state.lua: unit tests for the pure practice progression
-- module (practice_progress.lua) - XP and the level curve, prestige, per-drill
-- mastery and tiers, the streaks, the daily per-drill XP cap, the generic unlock
-- registry (operator order 2026-10-19: cosmetic AND level-gated drill variants),
-- and the SwedgeTimerDB.profile.practice persistence shape (schema_version,
-- migrate, validate/repair).
--
-- The module is WoW-free: the sandbox is a plain table, the dates and durations are
-- injected, and nothing here reads a clock or a random number.
--
-- Expected values are literals computed independently (the level curve from
-- floor(100 * n^1.35), the day ordinals from the civil calendar), so a mutant of the
-- implementation cannot quietly change both sides.
--
-- Run from the repo root: lua5.1 tests/practice_progress_state.lua

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

-- A deep table comparison (used for the drill table and the config default).
local function deep_equal(a, b, path)
    if type(a) ~= type(b) then
        return false, (path or "") .. ": type " .. type(a) .. " vs " .. type(b)
    end
    if type(a) ~= "table" then
        if a ~= b then return false, (path or "") .. ": " .. tostring(a) .. " vs " .. tostring(b) end
        return true
    end
    for key, value in pairs(a) do
        local ok, why = deep_equal(value, b[key], (path or "") .. "." .. tostring(key))
        if not ok then return false, why end
    end
    for key in pairs(b) do
        if a[key] == nil then return false, (path or "") .. "." .. tostring(key) .. ": missing on the left" end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Sandbox: the two pure modules, in their shipped load order
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

local P = st.practice_progress
local S = st.practice_stats
check(type(P) == "table", "st.practice_progress table exists")
check(type(S) == "table", "st.practice_stats table exists")

-- ---------------------------------------------------------------------------
-- Constants and their provenance
-- ---------------------------------------------------------------------------

eq(P.LEVEL_CURVE_BASE, 100, "level curve base is 100")
eq(P.LEVEL_CURVE_EXPONENT, 1.35, "level curve exponent is 1.35")
eq(P.MAX_LEVEL, 50, "level cap is 50")
eq(P.SESSION_BONUS_XP, 25, "session completion bonus is +25")
eq(P.SESSION_BONUS_MIN_ATTEMPTS, 10, "session bonus needs 10 attempts")
eq(P.MASTERY_WINDOW, 100, "mastery window is the last 100 attempts")
eq(P.MASTERY_HALF_LIFE, 30, "mastery half-life is 30 attempts")
eq(P.MASTERY_MIN_ATTEMPTS, 20, "mastery volume gate is 20 attempts")
eq(P.DAILY_CAP_MULTIPLIER, 3, "daily per-drill XP cap is 3x the drill median")
eq(P.SCHEMA_VERSION, 1, "profile schema version is 1")

-- The XP per attempt is the scoring model's own grade points.
eq(P.GRADE_POINTS.S, 100, "GRADE_POINTS.S is 100")
eq(P.GRADE_POINTS.A, 80, "GRADE_POINTS.A is 80")
eq(P.GRADE_POINTS.B, 60, "GRADE_POINTS.B is 60")
eq(P.GRADE_POINTS.C, 40, "GRADE_POINTS.C is 40")
eq(P.GRADE_POINTS.D, 20, "GRADE_POINTS.D is 20")
eq(P.GRADE_POINTS.F, 0, "GRADE_POINTS.F is 0 (a miss earns nothing)")

-- Mastery tiers: accuracy and lifetime attempts.
eq(P.MASTERY_TIERS.bronze.pct, 0.60, "bronze tier needs 60%")
eq(P.MASTERY_TIERS.bronze.attempts, 20, "bronze tier needs 20 attempts")
eq(P.MASTERY_TIERS.silver.pct, 0.75, "silver tier needs 75%")
eq(P.MASTERY_TIERS.silver.attempts, 50, "silver tier needs 50 attempts")
eq(P.MASTERY_TIERS.gold.pct, 0.85, "gold tier needs 85%")
eq(P.MASTERY_TIERS.gold.attempts, 100, "gold tier needs 100 attempts")
eq(P.MASTERY_TIERS.platinum.pct, 0.95, "platinum tier needs 95%")
eq(P.MASTERY_TIERS.platinum.attempts, 200, "platinum tier needs 200 attempts")

-- The live scoring model wins over the mirror when it is loaded. practice.lua is the
-- shipped scoring model (st.practice.GRADE_POINTS / GRADE_RANK).
local pmod = assert(loadfile(ROOT .. "practice.lua"))
setfenv(pmod, env)
local pok, perr = pcall(function() pmod("SwedgeTimer", st) end)
check(pok, "practice.lua loads under the sandbox (" .. tostring(perr) .. ")")
if pok and st.practice and type(st.practice.GRADE_POINTS) == "table" then
    local live, mirror = st.practice.GRADE_POINTS, P.GRADE_POINTS
    local same = true
    for grade, points in pairs(live) do
        if mirror[grade] ~= points then same = false end
    end
    for grade in pairs(mirror) do
        if live[grade] == nil then same = false end
    end
    check(same, "the GRADE_POINTS mirror matches the live st.practice.GRADE_POINTS")
    eq(st.practice.SCORE_WINDOW, 20, "the live SCORE_WINDOW is 20")
end

-- ---------------------------------------------------------------------------
-- Level curve: xp_for_level(n) = floor(100 * n^1.35)
-- ---------------------------------------------------------------------------

eq(P.xp_for_level(1), 100, "xp_for_level(1) == 100")
eq(P.xp_for_level(2), 254, "xp_for_level(2) == 254")
eq(P.xp_for_level(3), 440, "xp_for_level(3) == 440")
eq(P.xp_for_level(4), 649, "xp_for_level(4) == 649")
eq(P.xp_for_level(5), 878, "xp_for_level(5) == 878")
eq(P.xp_for_level(10), 2238, "xp_for_level(10) == 2238")
eq(P.xp_for_level(50), 19661, "xp_for_level(50) == 19661")

-- Cumulative XP to reach a level.
eq(P.xp_total_for_level(1), 0, "level 1 starts at 0 XP")
eq(P.xp_total_for_level(2), 100, "level 2 starts at 100 XP")
eq(P.xp_total_for_level(3), 354, "level 3 starts at 354 XP")
eq(P.xp_total_for_level(4), 794, "level 4 starts at 794 XP")
eq(P.xp_total_for_level(5), 1443, "level 5 starts at 1443 XP")
eq(P.xp_total_for_level(10), 8424, "level 10 starts at 8424 XP")
eq(P.xp_total_for_level(50), 408510, "level 50 starts at 408510 XP")
eq(P.xp_total_for_level(51), 428171, "level 51 starts at 428171 XP")

-- The curve is monotone: every level costs more than the one before.
local monotone = true
for n = 1, 60 do
    if P.xp_for_level(n + 1) <= P.xp_for_level(n) then monotone = false end
end
check(monotone, "the level curve is strictly increasing")

-- level_info: the level implied by an XP total.
local info = P.level_info(0)
eq(info.level, 1, "0 XP is level 1")
eq(info.renown, 0, "0 XP is renown 0")
eq(info.xp_for_next_level, 100, "0 XP needs 100 for the next level")
eq(info.xp_into_level, 0, "0 XP is 0 into the level")
eq(P.level_info(99).level, 1, "99 XP is still level 1")
eq(P.level_info(100).level, 2, "100 XP is level 2")
eq(P.level_info(353).level, 2, "353 XP is still level 2")
eq(P.level_info(354).level, 3, "354 XP is level 3")
eq(P.level_info(354).xp_into_level, 0, "354 XP is 0 into level 3")
eq(P.level_info(354).xp_for_next_level, 440, "level 3 needs 440 for level 4")
eq(P.level_info(454).xp_into_level, 100, "454 XP is 100 into level 3")

-- The level cap and the renown counter past it.
local capped = P.level_info(408510)
eq(capped.level, 50, "the cap holds the level at 50")
eq(capped.renown, 0, "408510 XP is renown 0")
local renown1 = P.level_info(428171)
eq(renown1.level, 50, "past the cap the level stays 50")
eq(renown1.renown, 1, "428171 XP is renown 1")
eq(P.level_info(448364).renown, 2, "448364 XP is renown 2")
eq(P.level_info(408510).xp_for_next_level, 19661, "the step past the cap is the level-50 step")

-- ---------------------------------------------------------------------------
-- Recording attempts: XP, streaks, drill counters
-- ---------------------------------------------------------------------------

local function fresh()
    return P.new_state(), P.new_session()
end

local prog, session = fresh()
P.record_attempt(prog, session, "PALADIN", "paladin_twist", "S", 20000)
eq(session.attempts, 1, "one attempt was recorded")
eq(session.hits, 1, "an S is a hit")
eq(session.streak, 1, "the session streak counts the hit")
eq(session.xp, 100, "an S earns 100 XP")
eq(P.scope_xp(prog, "PALADIN"), 100, "the class scope holds the XP")
eq(P.scope_xp(prog, "GLOBAL"), 100, "the account total is the sum over the classes")

P.record_attempt(prog, session, "PALADIN", "paladin_twist", "A", 20000)
eq(session.xp, 180, "an A earns 80 XP on top")
eq(session.streak, 2, "the streak survives an A")

P.record_attempt(prog, session, "PALADIN", "paladin_twist", "F", 20000)
eq(session.attempts, 3, "an F is still an attempt")
eq(session.hits, 2, "an F is not a hit")
eq(session.streak, 0, "an F breaks the session streak")
eq(session.best_streak, 2, "the session best streak keeps the run before the F")
eq(session.xp, 180, "an F earns nothing")
eq(P.scope_best_streak(prog, "PALADIN"), 2, "the lifetime best streak keeps the run")

-- A grade outside the scoring model's set is not an attempt.
local p2, s2 = fresh()
P.record_attempt(p2, s2, "WARRIOR", "warrior_execute", "Z", 20000)
eq(s2.attempts, 0, "an unknown grade is not an attempt")
eq(P.scope_xp(p2, "WARRIOR"), 0, "an unknown grade earns nothing")

-- L-4 (re-audit 2026-10-20): both pure modules answer the same question about a
-- grade, so the live score (which counts ANY grade it is handed) and the
-- progression can never drift apart.
eq(P.known_grade("S"), true, "L-4: the progress module knows the S grade")
eq(S.known_grade("S"), true, "L-4: the stats module knows the S grade")
eq(P.known_grade("Z"), false, "L-4: an unknown grade is not known")
eq(S.known_grade("Z"), false, "L-4: the stats module does not know it either")
eq(P.known_grade(nil), false, "L-4: a nil grade is not known")
eq(P.known_grade(42), false, "L-4: a non-string grade is not known")
-- The live scoring model's grade set is the truth for both of them.
if pok and st.practice and type(st.practice.GRADE_POINTS) == "table" then
    local live_known = true
    for grade in pairs(st.practice.GRADE_POINTS) do
        if P.known_grade(grade) ~= true or S.known_grade(grade) ~= true then
            live_known = false
        end
    end
    check(live_known, "L-4: every grade of the live scoring model is known to both pure modules")
    check(P.known_grade("Z") == S.known_grade("Z"),
        "L-4: both pure modules agree on an unknown grade")
end
-- An unknown grade is not an attempt on the stats side either.
local p2b = S.new_state()
S.record_attempt(p2b, "WARRIOR", "Z", "warrior_execute")
eq(p2b.global.attempts, 0, "L-4: an unknown grade is not an attempt for the stats either")
eq(p2b.classes.WARRIOR, nil, "L-4: an unknown grade creates no class scope")

-- XP is a class-scoped currency: the classes never share it.
local p3, s3 = fresh()
P.record_attempt(p3, s3, "ROGUE", "rogue_energy_pool", "B", 20000)
eq(P.scope_xp(p3, "ROGUE"), 60, "the rogue scope holds its own XP")
eq(P.scope_xp(p3, "PALADIN"), 0, "the paladin scope is untouched")
eq(P.scope_xp(p3, "GLOBAL"), 60, "the account total is the sum over the classes")

-- ---------------------------------------------------------------------------
-- The daily per-drill XP cap (3x the drill's median attempt XP)
-- ---------------------------------------------------------------------------

-- Six S attempts on one drill: the cap is 3 x 100 = 300, so the fourth S onward
-- earns nothing.
local p4, s4 = fresh()
for _ = 1, 6 do
    P.record_attempt(p4, s4, "WARRIOR", "warrior_execute", "S", 20000)
end
eq(s4.xp, 300, "the daily cap holds the drill at 3x its median")
eq(P.scope_xp(p4, "WARRIOR"), 300, "the capped XP is what the scope holds")

-- A new calendar day resets the cap.
P.record_attempt(p4, s4, "WARRIOR", "warrior_execute", "S", 20001)
eq(s4.xp, 400, "the next day the cap starts over")
eq(P.scope_xp(p4, "WARRIOR"), 400, "the next day the XP flows again")

-- A second drill has its own cap.
local p5, s5 = fresh()
for _ = 1, 4 do
    P.record_attempt(p5, s5, "WARRIOR", "warrior_execute", "S", 20000)
    P.record_attempt(p5, s5, "WARRIOR", "warrior_2", "S", 20000)
end
eq(s5.xp, 600, "each drill has its own daily cap (2 x 300)")

-- The cap follows the drill's median, not a fixed number: a drill of B attempts
-- (60 XP) caps at 180.
local p6, s6 = fresh()
for _ = 1, 5 do
    P.record_attempt(p6, s6, "DRUID", "druid_powershift", "B", 20000)
end
eq(s6.xp, 180, "the cap is 3x the drill's median XP")

-- Without a date there is no day to roll over on, so the cap keeps applying.
local p7, s7 = fresh()
for _ = 1, 4 do
    P.record_attempt(p7, s7, "HUNTER", "hunter_forced_move", "S", nil)
end
eq(s7.xp, 300, "without a date the cap still applies")

-- An attempt with no usable drill id lands in the reserved bucket: its XP is still
-- tracked and still capped, so a caller cannot dodge the anti-grind cap.
local p7b, s7b = fresh()
for _ = 1, 4 do
    P.record_attempt(p7b, s7b, "HUNTER", nil, "S", 20000)
end
eq(s7b.xp, 300, "an attempt without a drill id is still capped")
eq(P.scope_xp(p7b, "HUNTER"), 300, "an attempt without a drill id still earns XP")
check(p7b.classes.HUNTER.drills["_unknown"] ~= nil, "an attempt without a drill id lands in the reserved bucket")

-- ---------------------------------------------------------------------------
-- H-1 (re-audit 2026-10-20): the daily cap must have a floor that cannot be zero
-- ---------------------------------------------------------------------------
--
-- The cap is 3x the drill's median HIT points over the recent window, floored by
-- the best hit in that window. The old cap - 3x the median over EVERY attempt -
-- collapsed to 0 below 50% accuracy (a miss earns nothing, so the median was 0)
-- and every award was swallowed for good: the player needed ~50 consecutive hits
-- to escape, and the tier ladder is accuracy-gated too, so there was no way out.

-- A drill at 40% accuracy: six misses, then four hits. Before the fix the median
-- over the whole window was 0, so the cap was 0 and the hits earned NOTHING.
local h1p, h1s = fresh()
for _ = 1, 6 do
    P.record_attempt(h1p, h1s, "DRUID", "druid_powershift", "F", 20000)
end
eq(h1s.xp, 0, "H-1: a run of misses earns nothing")
P.record_attempt(h1p, h1s, "DRUID", "druid_powershift", "S", 20000)
eq(h1s.xp, 100, "H-1: a hit still earns its points below 50% accuracy")
P.record_attempt(h1p, h1s, "DRUID", "druid_powershift", "F", 20000)
P.record_attempt(h1p, h1s, "DRUID", "druid_powershift", "F", 20000)
P.record_attempt(h1p, h1s, "DRUID", "druid_powershift", "S", 20000)
eq(h1s.xp, 200, "H-1: the hits of a below-50%-accuracy drill keep earning")

local h1drill = h1p.classes.DRUID.drills.druid_powershift
local h1cap = P.drill_daily_cap(h1drill)
eq(h1cap, 300, "H-1: the cap of a below-50%-accuracy drill is 3x its median hit")
check(h1cap > 0, "H-1: the cap of a drill with hits is never zero")
check(h1cap <= 3 * 100, "H-1: the cap never exceeds 3x the best hit in the window")
eq(h1drill.daily_xp, 200, "H-1: the day's XP is what the drill earned")
check(h1drill.daily_xp <= h1cap, "H-1: the day's XP stays inside the cap")

-- The cap still bounds the day: the hits past the cap earn nothing.
for _ = 1, 8 do
    P.record_attempt(h1p, h1s, "DRUID", "druid_powershift", "S", 20000)
end
eq(h1s.xp, 300, "H-1: the cap still bounds the day (the hits past the cap earn nothing)")
check(h1s.xp <= h1cap, "H-1: the day's total never runs past the cap")

-- The day's total stays inside the cap once the completion bonus is added.
local h1r = P.end_session(h1p, h1s, "DRUID", 20000, {})
check(h1r.xp_earned <= h1cap * (1 + P.SESSION_BONUS_XP_SHARE),
    "H-1: the day's total stays within the cap (the bonus is a share of it)")

-- The misses do not drag the median down: the cap is taken over the HITS.
local h1p2, h1s2 = fresh()
P.record_attempt(h1p2, h1s2, "ROGUE", "rogue_ss_window", "F", 20000)
P.record_attempt(h1p2, h1s2, "ROGUE", "rogue_ss_window", "D", 20000)
P.record_attempt(h1p2, h1s2, "ROGUE", "rogue_ss_window", "S", 20000)
eq(P.drill_daily_cap(h1p2.classes.ROGUE.drills.rogue_ss_window), 180,
    "H-1: the median is taken over the hits, not over the misses")
eq(h1s2.xp, 120, "H-1: the hit is worth its own points even against a low median")

-- The floor: on a fresh day a hit earns at least its own points, even when the
-- drill's median is far below it.
local h1p3, h1s3 = fresh()
P.record_attempt(h1p3, h1s3, "ROGUE", "rogue_ss_window", "D", 20000)
P.record_attempt(h1p3, h1s3, "ROGUE", "rogue_ss_window", "D", 20000)
P.record_attempt(h1p3, h1s3, "ROGUE", "rogue_ss_window", "S", 20001)
eq(h1s3.xp, 140, "H-1: a hit earns its own points against a low median (the floor)")

-- A drill with no hit at all has no cap - the first attempt cannot be capped
-- against a median that does not exist yet - and its misses earn nothing.
local h1p4, h1s4 = fresh()
P.record_attempt(h1p4, h1s4, "SHAMAN", "shaman_weave", "F", 20000)
eq(P.drill_daily_cap(h1p4.classes.SHAMAN.drills.shaman_weave), nil,
    "H-1: a drill with no hit has no cap")
eq(h1s4.xp, 0, "H-1: a miss earns nothing")

-- ---------------------------------------------------------------------------
-- L-6 (re-audit 2026-10-20): the day rollover is ONE-DIRECTIONAL
-- ---------------------------------------------------------------------------
--
-- The rollover used to fire on ANY difference between the stored day and the new
-- one, so a backwards clock wiped the day's XP and handed out a free extra day.

local l6p, l6s = fresh()
P.record_attempt(l6p, l6s, "WARRIOR", "warrior_execute", "S", 20000)
P.record_attempt(l6p, l6s, "WARRIOR", "warrior_execute", "S", 20000)
eq(l6s.xp, 200, "L-6: the day holds the XP it earned")
-- A backwards clock must not wipe the day.
P.record_attempt(l6p, l6s, "WARRIOR", "warrior_execute", "S", 19999)
eq(l6s.xp, 300, "L-6: a backwards day does not wipe the day's XP")
-- The same day must not wipe it either.
P.record_attempt(l6p, l6s, "WARRIOR", "warrior_execute", "S", 20000)
eq(l6s.xp, 300, "L-6: the same day does not wipe the day's XP")
-- A later day does start a new day.
P.record_attempt(l6p, l6s, "WARRIOR", "warrior_execute", "S", 20001)
eq(l6s.xp, 400, "L-6: the next day starts a new day")
eq(l6p.classes.WARRIOR.drills.warrior_execute.daily_xp, 100,
    "L-6: the new day starts from zero")

-- ---------------------------------------------------------------------------
-- Mastery: volume gate, recency weighting, tiers
-- ---------------------------------------------------------------------------

-- Below 20 attempts the drill reads Unranked, however good it is.
local p8 = P.new_state()
local s8 = P.new_session()
for _ = 1, 10 do
    P.record_attempt(p8, s8, "SHAMAN", "shaman_weave", "S", 20000)
end
local mastery = P.mastery(p8.classes.SHAMAN.drills.shaman_weave)
eq(mastery.ranked, false, "10 perfect attempts is still unranked")
eq(mastery.tier, "unranked", "10 perfect attempts is Unranked")
eq(mastery.tier_name, "Unranked", "the tier label is Unranked")
near(mastery.mastery_pct, 100, "the weighted accuracy is 100%")

-- 20 attempts of S reach Bronze (60% / 20 attempts).
for _ = 1, 10 do
    P.record_attempt(p8, s8, "SHAMAN", "shaman_weave", "S", 20000)
end
mastery = P.mastery(p8.classes.SHAMAN.drills.shaman_weave)
eq(mastery.ranked, true, "20 attempts passes the volume gate")
eq(mastery.tier, "bronze", "20 perfect attempts is Bronze")
near(mastery.mastery_pct, 100, "the weighted accuracy is still 100%")

-- Recency weighting: a recent miss hurts more than an old miss.
local function weighted_pct(grades)
    local recent = {}
    for i = 1, #grades do recent[i] = grades[i] end
    return P.mastery_pct(recent)
end
check(weighted_pct({ "S", "S", "F" }) < weighted_pct({ "F", "S", "S" }),
    "a recent miss drags the weighted accuracy more than an old one")
-- The half-life: an attempt 30 old weighs half of the newest one.
local half = {}
for i = 1, 31 do half[i] = "S" end
half[31] = "F" -- the newest attempt is the miss
local with_miss = P.mastery_pct(half)
local all_hits = P.mastery_pct({ "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S",
    "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S", "S" })
near(all_hits, 100, "31 hits weigh in as 100%")
check(with_miss > 90 and with_miss < 100, "one recent miss off 31 attempts reads between 90% and 100%")

-- The tier ladder: the accuracy and the volume both gate it.
eq(P.tier_for(59.9, 20), "unranked", "59.9% is below Bronze")
eq(P.tier_for(60, 20), "bronze", "60% over 20 attempts is Bronze")
eq(P.tier_for(74.9, 50), "bronze", "74.9% is still Bronze")
eq(P.tier_for(75, 50), "silver", "75% over 50 attempts is Silver")
eq(P.tier_for(85, 100), "gold", "85% over 100 attempts is Gold")
eq(P.tier_for(95, 200), "platinum", "95% over 200 attempts is Platinum")
eq(P.tier_for(100, 199), "gold", "95%+ but under 200 attempts is Gold, not Platinum")
eq(P.tier_for(100, 19), "unranked", "100% under 20 attempts is Unranked")

-- ---------------------------------------------------------------------------
-- Streaks: session, best, daily
-- ---------------------------------------------------------------------------

local p9, s9 = fresh()
P.record_attempt(p9, s9, "PALADIN", "paladin_twist", "S", 20000)
P.record_attempt(p9, s9, "PALADIN", "paladin_twist", "S", 20000)
P.record_attempt(p9, s9, "PALADIN", "paladin_twist", "F", 20000)
P.record_attempt(p9, s9, "PALADIN", "paladin_twist", "S", 20000)
eq(s9.streak, 1, "the session streak restarts after a miss")
eq(s9.best_streak, 2, "the session best streak keeps the longest run")
eq(P.scope_best_streak(p9, "PALADIN"), 2, "the lifetime best streak keeps the longest run")

-- The daily streak: consecutive days increment, a missed day freezes it.
local p10 = P.new_state()
local function end_day(state, day)
    local sess = P.new_session()
    P.record_attempt(state, sess, "PALADIN", "paladin_twist", "S", day)
    return P.end_session(state, sess, "PALADIN", day, {})
end
local r1 = end_day(p10, 20000)
eq(r1.daily_streak, 1, "the first session day starts the daily streak")
local r2 = end_day(p10, 20001)
eq(r2.daily_streak, 2, "the next day increments the daily streak")
local r3 = end_day(p10, 20001)
eq(r3.daily_streak, 2, "a second session on the same day does not double count")
local r4 = end_day(p10, 20005)
eq(r4.daily_streak, 2, "a missed day does NOT reset the streak (it freezes it)")
local r5 = end_day(p10, 20006)
eq(r5.daily_streak, 3, "the day after the gap counts again")
eq(P.scope_daily_streak(p10, "PALADIN"), 3, "the class scope holds the daily streak")
eq(P.scope_daily_streak(p10, "GLOBAL"), 3, "the account scope tracks the same day run")

-- An empty session is not a completed session: no run, no streak movement.
local p11 = P.new_state()
local empty = P.new_session()
local r6 = P.end_session(p11, empty, "PALADIN", 20000, {})
eq(r6.attempts, 0, "an empty session has no attempts")
eq(r6.bonus_xp, 0, "an empty session earns no completion bonus")
eq(P.scope_daily_streak(p11, "PALADIN"), 0, "an empty session does not move the daily streak")

-- The completion bonus: +25 when a session ends with at least 10 attempts. The ten
-- S attempts are themselves capped by the daily per-drill rule (3 x 100 = 300), so
-- the session XP is 300 + 25.
local p12, s12 = fresh()
for _ = 1, 10 do
    P.record_attempt(p12, s12, "WARRIOR", "warrior_execute", "S", 20000)
end
local r7 = P.end_session(p12, s12, "WARRIOR", 20000, {})
eq(r7.bonus_xp, 25, "a session of 10 attempts earns the +25 completion bonus")
eq(r7.xp_earned, 325, "the session XP is the capped attempts plus the bonus")
eq(r7.level, 2, "325 XP is level 2")

local p13, s13 = fresh()
for _ = 1, 9 do
    P.record_attempt(p13, s13, "WARRIOR", "warrior_execute", "C", 20000)
end
local r8 = P.end_session(p13, s13, "WARRIOR", 20000, {})
eq(r8.bonus_xp, 0, "a session of 9 attempts earns no completion bonus")

-- The factor scales the bonus; the default is the identity.
local p14, s14 = fresh()
for _ = 1, 10 do
    P.record_attempt(p14, s14, "WARRIOR", "warrior_execute", "C", 20000)
end
local r9 = P.end_session(p14, s14, "WARRIOR", 20000, { completion_bonus_factor = 2 })
eq(r9.bonus_xp, 50, "the factor scales the completion bonus")

-- ---------------------------------------------------------------------------
-- M3 (re-audit 2026-10-20): the completion bonus is a SHARE of what the session
-- actually EARNED, not of how many attempts it made - and it is not outside the
-- daily cap. An attempt is any graded attempt, so ten misses are ten attempts and
-- zero XP: the old flat +25 for them was a grind hole, paid on top of a capped day.
-- ---------------------------------------------------------------------------
eq(P.SESSION_BONUS_XP_SHARE, 0.5, "the completion bonus is a share of the awarded XP")

-- A session of misses: ten F grades, no attempt XP, no bonus at all.
local m3p1, m3s1 = fresh()
for _ = 1, 10 do
    P.record_attempt(m3p1, m3s1, "WARRIOR", "warrior_execute", "F", 20000)
end
eq(m3s1.xp, 0, "M3: a session of misses earns no attempt XP")
local m3r1 = P.end_session(m3p1, m3s1, "WARRIOR", 20000, {})
eq(m3r1.bonus_xp, 0, "M3: a session of misses earns no completion bonus")
eq(P.scope_xp(m3p1, "WARRIOR"), 0, "M3: a session of misses adds nothing to the scope")
eq(m3r1.attempts, 10, "M3: the ten misses are still ten recorded attempts")

-- The bonus scales with the AWARDED XP: a thin session earns a proportional
-- bonus, never more than the flat +25 and never more than the share.
local m3p2, m3s2 = fresh()
for i = 1, 10 do
    P.record_attempt(m3p2, m3s2, "WARRIOR", "warrior_execute", i == 1 and "D" or "F", 20000)
end
local m3awarded = m3s2.xp
eq(m3awarded, 20, "M3: the thin session earns only its one attempt's XP")
local m3r2 = P.end_session(m3p2, m3s2, "WARRIOR", 20000, {})
eq(m3r2.bonus_xp, 10, "M3: the bonus is the share of the session's awarded XP")
eq(m3r2.xp_earned, 30, "M3: the session XP is the capped attempts plus the bonus")
check(m3r2.bonus_xp <= math.floor(m3awarded * P.SESSION_BONUS_XP_SHARE),
    "M3: the bonus never exceeds the share of the earned XP")

-- The daily cap still bounds the total: the day's attempt XP is the capped amount
-- and the bonus is a share of it, so the total never runs away from the cap.
local m3p3, m3s3 = fresh()
for _ = 1, 10 do
    P.record_attempt(m3p3, m3s3, "WARRIOR", "warrior_execute", "S", 20000)
end
local m3r3 = P.end_session(m3p3, m3s3, "WARRIOR", 20000, {})
local m3drill = m3p3.classes.WARRIOR.drills.warrior_execute
local m3cap = P.drill_daily_cap(m3drill)
eq(m3drill.daily_xp, m3cap, "M3: the drill's day is capped")
check(m3r3.xp_earned <= m3cap * (1 + P.SESSION_BONUS_XP_SHARE),
    "M3: the daily cap still bounds the total (the bonus is a share of it)")

-- The bonus is paid ONCE per session: a second end pays nothing more.
local m3p4, m3s4 = fresh()
for _ = 1, 10 do
    P.record_attempt(m3p4, m3s4, "WARRIOR", "warrior_execute", "S", 20000)
end
local m3r4 = P.end_session(m3p4, m3s4, "WARRIOR", 20000, {})
eq(m3r4.bonus_xp, 25, "M3: the first end pays the bonus")
local m3r5 = P.end_session(m3p4, m3s4, "WARRIOR", 20000, {})
eq(m3r5.bonus_xp, 0, "M3: a second end pays no bonus again")
eq(P.scope_xp(m3p4, "WARRIOR"), 325, "M3: the scope's XP is paid once")

-- ---------------------------------------------------------------------------
-- The generic unlock registry (operator order 2026-10-19)
-- ---------------------------------------------------------------------------

-- The registry carries the spec's achievements and accepts the two ordered kinds.
check(type(P.UNLOCKS) == "table", "the unlock registry is a table")
local kinds = {}
for _, definition in ipairs(P.unlock_definitions()) do kinds[definition.kind] = true end
check(kinds[P.KIND_ACHIEVEMENT], "the registry carries the achievement kind")
check(P.KIND_COSMETIC == "cosmetic", "the cosmetic kind is named cosmetic")
check(P.KIND_DRILL_VARIANT == "drill_variant", "the drill variant kind is named drill_variant")

-- A cosmetic unlock registers and fires on its requirement.
local cosmetic = P.register_unlock("theme_midnight", {
    kind = P.KIND_COSMETIC,
    label = "Midnight theme",
    requirement = { type = "level", level = 5 },
})
check(type(cosmetic) == "table", "a cosmetic unlock registers")
eq(cosmetic.kind, "cosmetic", "the registered kind is cosmetic")

-- A drill variant unlock must name the NEW scenario it grants.
local variant = P.register_unlock("paladin_twist_hard", {
    kind = P.KIND_DRILL_VARIANT,
    label = "Twist (hard)",
    scenario = "paladin_twist_hard",
    requirement = { type = "level", level = 10 },
})
check(type(variant) == "table", "a drill variant unlock registers")
eq(variant.scenario, "paladin_twist_hard", "the variant names its own scenario")
check(P.register_unlock("broken_variant", { kind = P.KIND_DRILL_VARIANT }) == nil,
    "a drill variant without a scenario is rejected")
check(P.register_unlock("empty_variant", { kind = P.KIND_DRILL_VARIANT, scenario = "" }) == nil,
    "a drill variant with an empty scenario is rejected")

-- L-1 (re-audit 2026-10-20): an unknown kind is REJECTED, not coerced. A typo'd
-- kind used to be stored as a cosmetic, so the definition was accepted and then
-- granted nothing - a silent dead unlock.
local cosmetics_before = #P.unlock_definitions(P.KIND_COSMETIC)
check(P.register_unlock("typo_kind", { kind = "cosmetc", label = "Typo" }) == nil,
    "L-1: an unknown unlock kind is rejected")
check(P.register_unlock("no_kind", { label = "No kind" }) == nil,
    "L-1: a missing unlock kind is rejected")
check(P.UNLOCKS["typo_kind"] == nil, "L-1: a rejected unlock is not registered")
check(P.UNLOCKS["no_kind"] == nil, "L-1: a kind-less unlock is not registered")
eq(#P.unlock_definitions(P.KIND_COSMETIC), cosmetics_before,
    "L-1: a rejected unlock never becomes a cosmetic")

-- The granted scenario is readable through the registry's accessor: only the
-- drill-variant kind names one (the audit's §4.3 - a variant grants a NEW
-- scenario, it never points at an existing drill to modify).
eq(P.unlock_scenario("paladin_twist_hard"), "paladin_twist_hard",
    "the accessor reads the granted scenario")
eq(P.unlock_scenario("theme_midnight"), nil, "a cosmetic unlock grants no scenario")
eq(P.unlock_scenario("level_10"), nil, "an achievement grants no scenario")
eq(P.unlock_scenario("nope"), nil, "an unknown unlock grants no scenario")
eq(P.unlock_scenario(nil), nil, "a nil id grants no scenario")

-- The registry COPIES the requirement: an unlock never reaches into a live table
-- (the hard rule - an unlock never changes how a drill behaves).
local live_requirement = { type = "level", level = 3 }
local copied = P.register_unlock("copy_probe", {
    kind = P.KIND_COSMETIC,
    label = "Copy probe",
    requirement = live_requirement,
})
check(type(copied) == "table", "the probe unlock registers")
eq(copied.requirement.level, 3, "the requirement is stored")
check(copied.requirement ~= live_requirement, "the stored requirement is a copy, not the caller's table")
live_requirement.level = 99
eq(copied.requirement.level, 3, "a later change to the caller's table does not reach the registry")
live_requirement.type = "predicate"
eq(copied.requirement.type, "level", "the stored requirement's type is not rewritten either")

-- The requirements: level, achievement and predicate.
local p15 = P.new_state()
local merged = P.profile_snapshot(p15, S.snapshot(S.new_state()), "PALADIN")
eq(#P.evaluate_unlocks(p15, merged, "PALADIN").newly, 0, "nothing unlocks at level 1")

-- Level-gated: a level 10 variant stays locked below level 10.
local p16 = P.new_state()
p16.classes.PALADIN = { xp = P.xp_total_for_level(10), best_streak = 0, daily_streak = 0,
    last_session_day = nil, drills = {}, unlocks = {} }
local snap16 = P.profile_snapshot(p16, S.snapshot(S.new_state()), "PALADIN")
eq(snap16.level, 10, "the scope is level 10")
local unlocked16 = P.evaluate_unlocks(p16, snap16, "PALADIN")
check(#unlocked16.newly > 0, "the level 10 unlocks fire at level 10")
check(P.is_unlocked(p16, "paladin_twist_hard", "PALADIN"), "the drill variant is unlocked in its class")
check(P.is_unlocked(p16, "level_10", "PALADIN"), "the level 10 achievement is unlocked")
check(not P.is_unlocked(p16, "paladin_twist_hard", "ROGUE"), "a class unlock does not leak into another class")

-- The unlock flags are per scope: the account scope is separate.
local p17 = P.new_state()
p17.classes.ROGUE = { xp = P.xp_total_for_level(10), best_streak = 0, daily_streak = 0,
    last_session_day = nil, drills = {}, unlocks = {} }
local snap17 = P.profile_snapshot(p17, S.snapshot(S.new_state()), "ROGUE")
P.evaluate_unlocks(p17, snap17, "ROGUE")
check(P.is_unlocked(p17, "level_10", "ROGUE"), "the rogue scope unlocks its own level 10")
check(not P.is_unlocked(p17, "level_10", "GLOBAL"), "the account scope is untouched by a class unlock")

-- An achievement-gated requirement reads the scope's unlock set.
P.register_unlock("needs_first_s", {
    kind = P.KIND_COSMETIC,
    label = "Needs an S",
    requirement = { type = "achievement", id = "first_s" },
})
local p18 = P.new_state()
local s18 = P.new_session()
P.record_attempt(p18, s18, "ROGUE", "rogue_ss_window", "S", 20000)
local snap18 = P.profile_snapshot(p18, S.snapshot(S.new_state()), "ROGUE")
snap18.best_grade = "S" -- the stats side supplies the grade
P.evaluate_unlocks(p18, snap18, "ROGUE")
check(P.is_unlocked(p18, "first_s", "ROGUE"), "an S unlocks first_s")
check(P.is_unlocked(p18, "needs_first_s", "ROGUE"), "the achievement-gated unlock follows it")

-- A malformed requirement never fires.
P.register_unlock("broken_requirement", { kind = P.KIND_COSMETIC, requirement = { type = "nonsense" } })
P.register_unlock("broken_test", { kind = P.KIND_COSMETIC, requirement = { type = "predicate", test = 42 } })
local p19 = P.new_state()
local snap19 = P.profile_snapshot(p19, S.snapshot(S.new_state()), "PALADIN")
P.evaluate_unlocks(p19, snap19, "PALADIN")
check(not P.is_unlocked(p19, "broken_requirement", "PALADIN"), "an unknown requirement type never fires")
check(not P.is_unlocked(p19, "broken_test", "PALADIN"), "a non-function predicate never fires")

-- A scope-restricted unlock is only evaluated in its own kind of scope.
P.register_unlock("class_only_theme", {
    kind = P.KIND_COSMETIC,
    label = "Class only theme",
    scope = "class",
    requirement = { type = "level", level = 1 },
})
P.register_unlock("account_only_banner", {
    kind = P.KIND_COSMETIC,
    label = "Account only banner",
    scope = "account",
    requirement = { type = "level", level = 1 },
})
local p19b = P.new_state()
P.evaluate_unlocks(p19b, P.profile_snapshot(p19b, S.snapshot(S.new_state()), P.GLOBAL_SCOPE), P.GLOBAL_SCOPE)
check(not P.is_unlocked(p19b, "class_only_theme", "GLOBAL"), "a class-scoped unlock never fires in the account scope")
check(P.is_unlocked(p19b, "account_only_banner", "GLOBAL"), "an account-scoped unlock fires in the account scope")
P.evaluate_unlocks(p19b, P.profile_snapshot(p19b, S.snapshot(S.new_state()), "PALADIN"), "PALADIN")
check(P.is_unlocked(p19b, "class_only_theme", "PALADIN"), "a class-scoped unlock fires in its class")
check(not P.is_unlocked(p19b, "account_only_banner", "PALADIN"), "an account-scoped unlock never fires in a class")

-- M-2 (re-audit 2026-10-20): the ACCOUNT scope's achievements must be evaluated.
-- The production path evaluated the class scope only, so progress.global.unlocks
-- was never written and every account-scoped achievement could never fire.
local m2p = P.new_state()
local m2s = P.new_session()
P.record_attempt(m2p, m2s, "ROGUE", "rogue_ss_window", "S", 20000)
local m2stats = S.new_state()
S.record_attempt(m2stats, "ROGUE", "S", "rogue_ss_window")
local m2class = P.profile_snapshot(m2p, S.snapshot(m2stats), "ROGUE")
local m2account = P.profile_snapshot(m2p, S.snapshot(m2stats), P.GLOBAL_SCOPE)
eq(m2account.best_grade, "S", "M-2: the account snapshot carries the summed best grade")
local m2res = P.evaluate_unlocks_both(m2p, "ROGUE", m2class, m2account)
check(#m2res.newly > 0, "M-2: the merged evaluation unlocks the class scope's achievements")
check(P.is_unlocked(m2p, "first_s", "ROGUE"), "M-2: the class scope holds its own flag")
check(P.is_unlocked(m2p, "first_s", "GLOBAL"), "M-2: the account scope holds its own flag too")
check(P.is_unlocked(m2p, "account_only_banner", "GLOBAL"),
    "M-2: an account-scoped unlock fires in the account scope")
check(not P.is_unlocked(m2p, "class_only_theme", "GLOBAL"),
    "M-2: a class-scoped unlock stays out of the account scope")
eq(type(m2p.global.unlocks), "table", "M-2: the account scope carries an unlock map")
eq(m2p.global.unlocks.first_s, true, "M-2: the account scope's flag is written")
-- The merged "newly" list holds every id ONCE, even when both scopes earned it.
local m2seen = 0
for _, id in ipairs(m2res.newly) do
    if id == "first_s" then m2seen = m2seen + 1 end
end
eq(m2seen, 1, "M-2: an id unlocked in both scopes is merged once")
-- The merged "unlocked" set is the union of the two scopes.
check(m2res.unlocked["first_s"] == true, "M-2: the merged set holds the class scope's unlock")
check(m2res.unlocked["account_only_banner"] == true, "M-2: the merged set holds the account scope's unlock")
-- The evaluation is idempotent: a second pass finds nothing new.
local m2again = P.evaluate_unlocks_both(m2p, "ROGUE", m2class, m2account)
eq(#m2again.newly, 0, "M-2: a second evaluation finds nothing new")
-- Without the account snapshot the account scope is left alone (the old
-- production behaviour - the account achievements stayed locked for good).
local m2p2 = P.new_state()
P.record_attempt(m2p2, m2s, "ROGUE", "rogue_ss_window", "S", 20000)
P.evaluate_unlocks_both(m2p2, "ROGUE", m2class, nil)
check(not P.is_unlocked(m2p2, "first_s", "GLOBAL"),
    "M-2: without an account snapshot the account scope is not evaluated")

-- The achievement thresholds: each one fires exactly at the number its id names.
local function achievement_fires(id, snapshot)
    local state = P.new_state()
    P.evaluate_unlocks(state, snapshot, "PALADIN")
    return P.is_unlocked(state, id, "PALADIN")
end

-- perfect_ten: ten S in a row.
check(not achievement_fires("perfect_ten", { best_s_streak = 9 }), "nine S in a row is not perfect_ten")
check(achievement_fires("perfect_ten", { best_s_streak = 10 }), "ten S in a row is perfect_ten")

-- hundred_attempts: 100 attempts.
check(not achievement_fires("hundred_attempts", { attempts = 99 }), "99 attempts is not hundred_attempts")
check(achievement_fires("hundred_attempts", { attempts = 100 }), "100 attempts is hundred_attempts")

-- level_10: level 10.
check(not achievement_fires("level_10", { level = 9 }), "level 9 is not level_10")
check(achievement_fires("level_10", { level = 10 }), "level 10 is level_10")

-- week_streak: seven consecutive days.
check(not achievement_fires("week_streak", { daily_streak = 6 }), "a six day streak is not week_streak")
check(achievement_fires("week_streak", { daily_streak = 7 }), "a seven day streak is week_streak")

-- ten_hours: 36000 seconds of active practice.
check(not achievement_fires("ten_hours", { time_active_seconds = 35999 }), "35999 seconds is not ten_hours")
check(achievement_fires("ten_hours", { time_active_seconds = 36000 }), "36000 seconds is ten_hours")

-- first_s: the best single grade is S.
check(not achievement_fires("first_s", { best_grade = "A" }), "an A is not first_s")
check(achievement_fires("first_s", { best_grade = "S" }), "an S is first_s")

-- all_drills_gold: every drill at Gold or better.
check(not achievement_fires("all_drills_gold", { drills = {} }), "no drills is not all_drills_gold")
check(not achievement_fires("all_drills_gold", {
    drills = { a = { tier = "gold" }, b = { tier = "silver" } },
}), "a silver drill is not all_drills_gold")
check(achievement_fires("all_drills_gold", {
    drills = { a = { tier = "gold" }, b = { tier = "platinum" } },
}), "every drill gold or better is all_drills_gold")

-- A predicate that raises is contained: it never unlocks and never throws.
P.register_unlock("raising_predicate", {
    kind = P.KIND_COSMETIC,
    requirement = { type = "predicate", test = function() error("boom") end },
})
local p20 = P.new_state()
local ok20, res20 = pcall(function()
    return P.evaluate_unlocks(p20, P.profile_snapshot(p20, S.snapshot(S.new_state()), "PALADIN"), "PALADIN")
end)
check(ok20, "a raising predicate does not escape the evaluation")
check(res20 and not P.is_unlocked(p20, "raising_predicate", "PALADIN"), "a raising predicate does not unlock")

-- HARD RULE: an unlock never touches a drill. The progression state before and
-- after an unlock is identical, drill rows included.
local p21 = P.new_state()
local s21 = P.new_session()
for _ = 1, 30 do
    P.record_attempt(p21, s21, "PALADIN", "paladin_twist", "S", 20000)
end
local before21 = P.export_payload(p21)
local snap21 = P.profile_snapshot(p21, S.snapshot(S.new_state()), "PALADIN")
P.evaluate_unlocks(p21, snap21, "PALADIN")
local after21 = P.export_payload(p21)
local same21, why21 = deep_equal(before21.classes.PALADIN.drills, after21.classes.PALADIN.drills, "drills")
check(same21, "an unlock does not change the drill table (" .. tostring(why21) .. ")")
eq(before21.classes.PALADIN.drills.paladin_twist.attempts,
    after21.classes.PALADIN.drills.paladin_twist.attempts, "an unlock does not change the drill attempts")
eq(before21.classes.PALADIN.drills.paladin_twist.hits,
    after21.classes.PALADIN.drills.paladin_twist.hits, "an unlock does not change the drill hits")
eq(before21.classes.PALADIN.xp, after21.classes.PALADIN.xp, "an unlock does not change the XP")

-- ---------------------------------------------------------------------------
-- The merged profile snapshot
-- ---------------------------------------------------------------------------

local p22, s22 = fresh()
for _ = 1, 3 do
    P.record_attempt(p22, s22, "PALADIN", "paladin_twist", "S", 20000)
end
local stats22 = S.new_state()
S.record_attempt(stats22, "PALADIN", "S", "paladin_twist")
S.record_attempt(stats22, "PALADIN", "A", "paladin_twist")
S.record_attempt(stats22, "PALADIN", "F", "paladin_twist")
local merged22 = P.profile_snapshot(p22, S.snapshot(stats22), "PALADIN")
eq(merged22.level, 2, "the merged snapshot carries the level")
eq(merged22.xp, 300, "the merged snapshot carries the XP")
eq(merged22.drills.paladin_twist.attempts, 3, "the merged drill row carries the attempts")
eq(merged22.drills.paladin_twist.mastery_pct, 100, "the merged drill row carries the mastery")
eq(merged22.drills.paladin_twist.tier, "unranked", "3 attempts is still under the volume gate")
eq(merged22.stats.attempts, 3, "the merged snapshot carries the stats side")

-- The stats scalars are lifted to the TOP level of the merged snapshot: the
-- achievement predicates read one flat snapshot (the hook lane evaluates them
-- with exactly this shape, so no caller has to merge two read models by hand).
eq(merged22.attempts, 3, "the merged snapshot lifts the attempt count")
eq(merged22.hits, 2, "the merged snapshot lifts the hit count")
eq(merged22.misses, 1, "the merged snapshot lifts the miss count")
eq(merged22.best_grade, "S", "the merged snapshot lifts the best grade")
eq(merged22.best_s_streak, 1, "the merged snapshot lifts the best S-run")
eq(merged22.time_active_seconds, 0, "the merged snapshot lifts the time active")
eq(merged22.runs, 0, "the merged snapshot lifts the run count")
eq(merged22.stats.attempts, merged22.attempts, "the stats sub-table and the lifted count agree")
eq(merged22.stats.best_grade, merged22.best_grade, "the stats sub-table and the lifted grade agree")

-- The lifted values are the scope's own: the account scope aggregates every class.
local stats22b = S.new_state()
S.record_attempt(stats22b, "PALADIN", "S", "paladin_twist")
S.record_attempt(stats22b, "ROGUE", "A", "rogue_energy_pool")
local merged22b = P.profile_snapshot(p22, S.snapshot(stats22b), P.GLOBAL_SCOPE)
eq(merged22b.attempts, 2, "the account scope lifts the summed attempt count")
eq(merged22b.best_grade, "S", "the account scope lifts the best grade")
eq(merged22b.stats.attempts, 2, "the account scope keeps the stats sub-table")

-- A scope with no stats side lifts nothing (an absent value stays absent, never a
-- zero that would read as a real measurement).
local merged22c = P.profile_snapshot(p22, {}, "PALADIN")
eq(merged22c.attempts, nil, "an empty stats side lifts no attempt count")
eq(merged22c.best_grade, nil, "an empty stats side lifts no best grade")
eq(merged22c.level, 2, "the progression side is still there without a stats side")

-- The hook's save / load round trip: the live progress state is written into the
-- profile as-is and read back after a reload, and the load-time repair must not
-- change a single number.
local live_p, live_s = fresh()
for _ = 1, 3 do
    P.record_attempt(live_p, live_s, "PALADIN", "paladin_twist", "S", 20000)
end
P.end_session(live_p, live_s, "PALADIN", 20000, {})
local reloaded_p = P.repair_state(live_p)
eq(reloaded_p.classes.PALADIN.xp, 300, "the round trip keeps the XP")
eq(reloaded_p.classes.PALADIN.best_streak, 3, "the round trip keeps the best streak")
eq(reloaded_p.classes.PALADIN.daily_streak, 1, "the round trip keeps the daily streak")
eq(reloaded_p.classes.PALADIN.drills.paladin_twist.attempts, 3,
    "the round trip keeps the per-drill counters")
eq(reloaded_p.classes.PALADIN.drills.paladin_twist.hits, 3,
    "the round trip keeps the per-drill hits")
eq(reloaded_p.classes.PALADIN.drills.paladin_twist.recent[1], "S",
    "the round trip keeps the mastery window")
eq(P.level_info(P.scope_xp(reloaded_p, "PALADIN")).level, 2,
    "the round trip keeps the level")
eq(reloaded_p.global.daily_streak, 1, "the round trip keeps the account daily streak")

-- ---------------------------------------------------------------------------
-- Persistence: schema_version, migrate, validate/repair
-- ---------------------------------------------------------------------------

local profile = P.new_profile()
eq(profile.schema_version, 1, "a fresh profile is at schema version 1")
check(type(profile.progress) == "table", "a fresh profile carries a progress state")
check(type(profile.stats) == "table", "a fresh profile carries a stats state")
eq(type(profile.progress.classes), "table", "the fresh progress state has no classes yet")
eq(profile.progress.global.daily_streak, 0, "the fresh account scope has no streak")

-- A corrupt blob falls back to a fresh state, without throwing.
local okm, migrated = pcall(P.migrate, "not a table")
check(okm, "migrating a string does not throw")
eq(type(migrated), "table", "a string blob migrates to a table")
eq(migrated.schema_version, 1, "a string blob migrates to the current schema version")
local okm2, migrated2 = pcall(P.migrate, nil)
check(okm2, "migrating nil does not throw")
eq(migrated2.schema_version, 1, "a nil blob migrates to the current schema version")
local okm3, migrated3 = pcall(P.migrate, 42)
check(okm3, "migrating a number does not throw")
eq(migrated3.schema_version, 1, "a number blob migrates to the current schema version")

-- Bad types reset to the defaults; unknown keys are dropped.
local corrupt = {
    schema_version = 1,
    junk_key = "should be dropped",
    progress = {
        classes = {
            PALADIN = {
                xp = "not a number",
                best_streak = -5,
                daily_streak = 3,
                last_session_day = 20000,
                unknown = "dropped",
                drills = {
                    paladin_twist = {
                        attempts = 10,
                        hits = 99,
                        recent = { "S", "A", "F", 42, "Z" },
                        daily_xp = "nope",
                        daily_day = 20000,
                    },
                },
            },
        },
        global = { daily_streak = "bad", unknown = "dropped" },
    },
    stats = { global = { attempts = 5 } },
}
local repaired = P.validate(corrupt)
eq(repaired.schema_version, 1, "the repaired profile keeps the schema version")
eq(repaired.junk_key, nil, "an unknown top-level key is dropped")
eq(repaired.progress.classes.PALADIN.xp, 0, "a bad XP type resets to 0")
eq(repaired.progress.classes.PALADIN.best_streak, 0, "a negative streak resets to 0")
eq(repaired.progress.classes.PALADIN.daily_streak, 3, "a good streak survives the repair")
eq(repaired.progress.classes.PALADIN.unknown, nil, "an unknown scope key is dropped")
eq(repaired.progress.classes.PALADIN.drills.paladin_twist.attempts, 10, "the drill attempts survive")
eq(repaired.progress.classes.PALADIN.drills.paladin_twist.hits, 10, "hits are clamped to the attempts")
eq(repaired.progress.classes.PALADIN.drills.paladin_twist.recent[3], "F", "an F in the ring is kept")
eq(#repaired.progress.classes.PALADIN.drills.paladin_twist.recent, 4,
    "the non-string ring entry is dropped (4 entries survive of 5)")
eq(repaired.progress.classes.PALADIN.drills.paladin_twist.recent[4], "F",
    "an unknown grade in the ring becomes F")
eq(repaired.progress.classes.PALADIN.drills.paladin_twist.daily_xp, 0, "a bad daily XP type resets to 0")
eq(repaired.progress.global.daily_streak, 0, "a bad account streak resets to 0")
eq(repaired.progress.global.unknown, nil, "an unknown account key is dropped")
eq(repaired.stats.global.attempts, 5, "the stats side is repaired by the stats module")

-- The input is never mutated: migrate returns a NEW table.
eq(corrupt.progress.classes.PALADIN.xp, "not a number", "migrate does not mutate its input")
check(P.migrate(corrupt) ~= corrupt, "migrate returns a new table")

-- Other saved variables are never touched: migrate only ever sees the practice blob.
local db_like = { profile = { other_key = "keep me", practice = corrupt } }
local migrated_db = P.migrate(db_like.profile.practice)
db_like.profile.practice = migrated_db
eq(db_like.profile.other_key, "keep me", "a sibling profile key is untouched by the migration")

-- A blob from a newer build is returned unchanged: we never wipe what we do not
-- understand.
local future = { schema_version = 99, progress = { classes = {} } }
local kept = P.migrate(future)
eq(kept.schema_version, 99, "a newer schema version is left alone")
check(kept == future, "a newer blob is returned unchanged")
check(P.is_current(future) == false, "is_current says a newer blob is not ours")
check(P.is_current(corrupt) == true, "is_current says our own blob is current")
check(P.is_current("junk") == false, "is_current says junk is not a blob")

-- The unlock flags of an unknown id are kept: a downgrade must not un-unlock.
local with_unknown_unlock = {
    schema_version = 1,
    progress = { classes = { PALADIN = { unlocks = { theme_midnight = true, mystery = true } } } },
}
local repaired_unlock = P.validate(with_unknown_unlock)
eq(repaired_unlock.progress.classes.PALADIN.unlocks.theme_midnight, true, "a known unlock flag survives")
eq(repaired_unlock.progress.classes.PALADIN.unlocks.mystery, true, "an unknown unlock flag is kept, not dropped")

-- The AceDB default in config_presets.lua must be the same shape as the pure
-- modules' fresh profile: one shape, one source, no drift.
local config_st = {
    DEATHKNIGHT = {}, DRUID = {}, HUNTER = {}, MAGE = {}, PALADIN = {},
    PRIEST = {}, ROGUE = {}, SHAMAN = {}, WARLOCK = {}, WARRIOR = {},
}
local config_env = setmetatable({}, { __index = _G })
config_env.LibStub = function(major)
    if major == "AceAddon-3.0" then
        return { GetAddon = function() return config_st end }
    end
    return {}
end
local cfg = assert(loadfile(ROOT .. "config_presets.lua"))
setfenv(cfg, config_env)
local okcfg, cerr = pcall(cfg, "SwedgeTimer", {})
check(okcfg, "config_presets.lua loads under the sandbox (" .. tostring(cerr) .. ")")

check(type(config_st.PRACTICE_DEFAULTS) == "table", "config_presets.lua declares ST.PRACTICE_DEFAULTS")
if type(config_st.PRACTICE_DEFAULTS) == "table" then
    local same, why = deep_equal(config_st.PRACTICE_DEFAULTS, P.new_profile(), "PRACTICE_DEFAULTS")
    check(same, "the AceDB default matches the pure modules' fresh profile (" .. tostring(why) .. ")")
end

-- config.lua owns ST.defaults: the practice blob must be the AceDB default for the
-- profile key, so a fresh profile starts from a valid, fully-shaped state.
local cfg_defaults = assert(loadfile(ROOT .. "config.lua"))
setfenv(cfg_defaults, config_env)
local okcfg2, cerr2 = pcall(cfg_defaults, "SwedgeTimer", {})
check(okcfg2, "config.lua loads under the sandbox (" .. tostring(cerr2) .. ")")
check(type(config_st.defaults) == "table", "config.lua declares ST.defaults")
if type(config_st.defaults) == "table" and type(config_st.defaults.profile) == "table" then
    check(config_st.defaults.profile.practice ~= nil,
        "ST.defaults.profile carries the practice blob")
    check(config_st.defaults.profile.practice == config_st.PRACTICE_DEFAULTS,
        "ST.defaults.profile.practice IS the AceDB practice default")
    check(config_st.defaults.profile.practice.schema_version == 1,
        "the practice default is at schema version 1")
    check(type(config_st.defaults.profile.practice.progress) == "table",
        "the practice default carries the progress half")
    check(type(config_st.defaults.profile.practice.stats) == "table",
        "the practice default carries the stats half")
else
    check(false, "ST.defaults.profile is missing")
end

-- ---------------------------------------------------------------------------
-- Guards: malformed input degrades, it never raises
-- ---------------------------------------------------------------------------

local bad = { 0 / 0, math.huge, -math.huge, "10", true, {} }
for i = 1, #bad do
    local value = bad[i]
    local okg = pcall(function()
        P.xp_for_level(value)
        P.level_info(value)
        P.scope_xp({}, value)
        P.mastery(value)
        P.mastery_pct(value)
        P.drill_daily_cap(value)
        P.profile_snapshot(value, value, value)
        P.export_payload(value)
        P.repair_state(value)
        P.json_safe(value)
    end)
    check(okg, "a malformed input (" .. i .. ") never raises")
end
eq(P.xp_for_level(0 / 0), 100, "a NaN level falls back to level 1")
eq(P.level_info(0 / 0).level, 1, "a NaN XP total reads as level 1")
eq(P.mastery_pct({}), 0, "an empty window reads 0%")
eq(P.mastery({}).tier, "unranked", "a malformed drill reads Unranked")
eq(P.json_safe(0 / 0), nil, "the JSON sanitizer drops a NaN")
eq(P.json_safe(math.huge), nil, "the JSON sanitizer drops an infinity")
eq(P.json_safe(-math.huge), nil, "the JSON sanitizer drops a negative infinity")
eq(P.json_safe(print), nil, "the JSON sanitizer drops a function")
eq(P.json_safe("text"), "text", "the JSON sanitizer keeps a string")
eq(P.json_safe(42), 42, "the JSON sanitizer keeps a number")

-- A malformed snapshot never breaks the achievement predicates.
for _, definition in ipairs(P.unlock_definitions(P.KIND_ACHIEVEMENT)) do
    local requirement = definition.requirement
    if type(requirement) == "table" and type(requirement.test) == "function" then
        local okp = pcall(requirement.test, nil)
        check(okp, "the " .. definition.id .. " predicate survives a nil snapshot")
        local okp2 = pcall(requirement.test, { attempts = "junk", drills = 5 })
        check(okp2, "the " .. definition.id .. " predicate survives a junk snapshot")
    end
end

-- The whole evaluation survives a junk snapshot.
local junk_progress = P.new_state()
local okjunk = pcall(function()
    P.evaluate_unlocks(junk_progress, { attempts = "junk", drills = 5, level = "x" }, "PALADIN")
    P.evaluate_unlocks(junk_progress, nil, "PALADIN")
    P.evaluate_unlocks(junk_progress, { level = 10 }, "PALADIN")
end)
check(okjunk, "the unlock evaluation survives a junk snapshot")

-- ---------------------------------------------------------------------------
-- The export payload is JSON-safe
-- ---------------------------------------------------------------------------

local payload = P.export_payload(p22)
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
        check(type(key) == "string", "the export payload object keys are strings at " .. path)
        json_safe(item, path .. "." .. tostring(key))
    end
end
json_safe(payload, "progress")
eq(payload.schema_version, 1, "the export payload carries the schema version")
eq(payload.classes.PALADIN.level, 2, "the export payload carries the level")
eq(payload.classes.PALADIN.drills.paladin_twist.mastery_pct, 100, "the export payload carries the mastery")

-- ---------------------------------------------------------------------------
-- The calendar day helper (injected dates only)
-- ---------------------------------------------------------------------------

eq(P.day_ordinal("1970-01-01"), 0, "the epoch day is 0")
eq(P.day_ordinal("1970-01-02"), 1, "the day after the epoch is 1")
eq(P.day_ordinal("2000-01-01"), 10957, "2000-01-01 is day 10957")
eq(P.day_ordinal("2026-10-19"), 20745, "2026-10-19 is day 20745")
eq(P.day_ordinal("2026-10-20"), 20746, "2026-10-20 is day 20746")
eq(P.day_ordinal("2024-02-29"), 19782, "a leap day is a valid date")
eq(P.day_ordinal("2023-02-29"), nil, "a non-leap 29 February is not a date")
eq(P.day_ordinal("2026-13-01"), nil, "month 13 is not a date")
eq(P.day_ordinal("2026-10-32"), nil, "day 32 is not a date")
eq(P.day_ordinal("not a date"), nil, "a malformed date is not a date")
eq(P.day_ordinal(true), nil, "a boolean is not a date")
eq(P.day_ordinal(nil), nil, "nil is not a date")
eq(P.day_ordinal(20745), 20745, "a numeric day counter passes through")

-- Both pure modules must agree on the calendar (one helper, two copies).
for _, day in ipairs({ "1970-01-01", "1999-12-31", "2000-02-29", "2026-10-19", "2027-01-01", "bogus" }) do
    eq(P.day_ordinal(day), S.day_ordinal(day), "both modules read the day " .. tostring(day) .. " the same way")
end

-- ---------------------------------------------------------------------------
-- Load order: the modules load after practice.lua and before practice_ui.lua, and
-- the stats module loads before the progress module (it owns the base layer).
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
    check(index["practice.lua"] ~= nil, toc .. ": lists practice.lua")
    check(index["practice_stats.lua"] ~= nil, toc .. ": lists practice_stats.lua")
    check(index["practice_progress.lua"] ~= nil, toc .. ": lists practice_progress.lua")
    check(index["practice_ui.lua"] ~= nil, toc .. ": lists practice_ui.lua")
    check(index["practice.lua"] < index["practice_stats.lua"], toc .. ": practice.lua before practice_stats.lua")
    check(index["practice_stats.lua"] < index["practice_progress.lua"],
        toc .. ": practice_stats.lua before practice_progress.lua")
    check(index["practice_progress.lua"] < index["practice_ui.lua"],
        toc .. ": practice_progress.lua before practice_ui.lua")
end

print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)
