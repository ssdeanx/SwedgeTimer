-- tests/hunter_window_state.lua: unit tests for the pure hunter ranged-window maths in
-- hunter_window.lua (phase 1 of the SuperSwingTimer hunter port).
-- The module is WoW-free by design, so it needs no client stubs at all: it is loaded
-- under a STRICT sandbox that grants only math/type and errors on every other global
-- access, which makes "pure" an executable property rather than a comment. Every
-- function and boundary is exercised: the fixed cast window (0.5 s, latency never
-- added), hidden windows
-- before and after the cycle end, cast-safety equal/just-above thresholds with the
-- steady 0.5 and multi-shot 0 grace, stopped-position safety moving/before/after the
-- window, time-until-shot with and without the cooldown fallback, the 0.009/0.01/0.011
-- drift rule, the start-dedupe boundaries, the range-state priority ladder, the
-- cast-bar mode priority with inclusive window bounds, the clamped latency-slice
-- fraction and the clip-tint key mapping.
-- Plain Lua 5.1, no WoW client needed. Run from the repo root:
--   lua5.1 tests/hunter_window_state.lua   (any cwd works)

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

--=========================================================================================
-- Strict sandbox: only math and type exist
--=========================================================================================
local st = {}
local env = setmetatable({}, {
    __index = function(_, key)
        error("hunter_window.lua touched the global '" .. tostring(key) .. "'", 2)
    end,
})
env.math = math
env.type = type

local mod = assert(loadfile(ROOT .. "hunter_window.lua"))
setfenv(mod, env)
local ok, err = pcall(function() mod("SwedgeTimer", st) end)
check(ok, "hunter_window.lua loads under the strict (math/type-only) sandbox ("
    .. tostring(err) .. ")")
local hw = st.hunter_window
check(type(hw) == "table", "st.hunter_window table exists")

-- Every exercised call runs through pcall: a purity violation is a failed check with
-- the offending global named, not an aborted script.
local function call(fn, ...)
    local call_ok, a, b, c = pcall(fn, ...)
    if not call_ok then
        checks = checks + 1
        failures = failures + 1
        print("FAIL  a call touched an unexpected global: " .. tostring(a))
        return nil, nil, nil
    end
    return a, b, c
end

--=========================================================================================
-- 0) API surface and constants
--=========================================================================================
for _, name in ipairs({
    "cast_window", "hidden_window", "is_cast_safe", "is_stopped_position_safe",
    "time_until_next_shot", "sync_duration", "should_restart",
    "cast_bar_display", "latency_slice_fraction", "clip_tint", "range_state",
    "hold_seconds",
}) do
    check(type(hw[name]) == "function", "hunter_window." .. name .. " is a function")
end
check(st.hunter_window == hw, "the module registers itself as st.hunter_window")
eq(hw.BASE_CAST_WINDOW, 0.5, "BASE_CAST_WINDOW is 0.5")
eq(hw.STEADY_SHOT_GRACE, 0.5, "STEADY_SHOT_GRACE is 0.5")
eq(hw.MULTI_SHOT_GRACE, 0, "MULTI_SHOT_GRACE is 0")
eq(hw.RANGED_START_DEDUPE_WINDOW, 0.25, "RANGED_START_DEDUPE_WINDOW is 0.25")

--=========================================================================================
-- 1) cast_window: the fixed 0.5 s Auto Shot cast window, at the END of the cycle.
--    Latency is NEVER added (operator ruling 2026-10-22): the red zone is the cast
--    window itself. Latency only makes a cast landing inside it not clip.
--=========================================================================================
eq(call(hw.cast_window, 0), 0.5, "cast_window: zero latency -> the 0.5 window")
eq(call(hw.cast_window, 0.05), 0.5, "cast_window: 0.05 latency is NOT added")
eq(call(hw.cast_window, 0.2), 0.5, "cast_window: 0.2 latency is NOT added")
eq(call(hw.cast_window, 0.12), 0.5, "cast_window: latency never widens the zone")
eq(call(hw.cast_window, nil), 0.5, "cast_window: nil latency -> the fixed window")
eq(call(hw.cast_window, "0.2"), 0.5, "cast_window: non-number latency -> the fixed window")
eq(call(hw.cast_window, -0.5), 0.5, "cast_window: negative latency cannot shrink the zone")
eq(call(hw.cast_window), 0.5, "cast_window: no argument -> the fixed window")

--=========================================================================================
-- 2) hidden_window: the last cast_window seconds before the cycle end
--=========================================================================================
do
    local ws, we = call(hw.hidden_window, 10, 2, 0.5)
    near(ws, 11.5, "hidden_window: start is end - cast window")
    near(we, 12, "hidden_window: end is last_swing + duration")

    ws, we = call(hw.hidden_window, 10, 2, nil)
    near(ws, 11.5, "hidden_window: nil window defaults to the 0.5 base")
    eq(we, 12, "hidden_window: nil window keeps the end")

    ws, we = call(hw.hidden_window, 10, 2, 0)
    near(ws, 11.99, "hidden_window: a zero window is floored at 0.01")
    eq(we, 12, "hidden_window: the 0.01 floor moves only the start")

    local floored_ws, floored_we = call(hw.hidden_window, 10, 2, -5)
    near(floored_ws, 11.99, "hidden_window: a negative window is floored at 0.01")
    eq(floored_we, 12, "hidden_window: a negative window keeps the end")

    -- A realistic hunter cycle: 2.4 s auto shot, ~0.55 s cast window.
    ws, we = call(hw.hidden_window, 100, 2.4, 0.55)
    near(ws, 101.85, "hidden_window: real-cycle start (end - window)")
    near(we, 102.4, "hidden_window: real-cycle end (last_swing + duration)")
    check(ws < we, "hidden_window: start precedes end")

    local nil_ws, nil_we = call(hw.hidden_window, 10, 0, 0.5)
    eq(nil_ws, nil, "hidden_window: zero duration -> nil start")
    eq(nil_we, nil, "hidden_window: zero duration -> nil end")

    nil_ws, nil_we = call(hw.hidden_window, nil, 2, 0.5)
    eq(nil_ws, nil, "hidden_window: nil anchor -> nil start")
    eq(nil_we, nil, "hidden_window: nil anchor -> nil end")
end

--=========================================================================================
-- 3) is_cast_safe: steady 0.5 grace, multi-shot 0 grace, latency floor 0.03
--=========================================================================================
do
    -- Steady Shot, latency 0.1, 1.0 s until the next shot: threshold 1.4.
    eq(call(hw.is_cast_safe, 1.4, 1.0, hw.STEADY_SHOT_GRACE, 0.1), true,
        "steady: remaining exactly at the threshold is safe (<=)")
    eq(call(hw.is_cast_safe, 1.3, 1.0, hw.STEADY_SHOT_GRACE, 0.1), true,
        "steady: remaining under the threshold is safe")
    eq(call(hw.is_cast_safe, 1.4001, 1.0, hw.STEADY_SHOT_GRACE, 0.1), false,
        "steady: remaining just above the threshold is unsafe")

    -- Multi-Shot has 0 grace: the same 1.0 s cast that is safe for Steady Shot is not.
    eq(call(hw.is_cast_safe, 0.9, 1.0, hw.MULTI_SHOT_GRACE, 0.1), true,
        "multi-shot: remaining exactly at the threshold is safe")
    eq(call(hw.is_cast_safe, 0.9001, 1.0, hw.MULTI_SHOT_GRACE, 0.1), false,
        "multi-shot: remaining just above the threshold is unsafe")
    eq(call(hw.is_cast_safe, 1.0, 1.0, hw.MULTI_SHOT_GRACE, 0.1), false,
        "multi-shot: a cast safe under the steady grace is unsafe with 0 grace")

    -- Latency floor: 0 or 0.01 latency still leaves the 0.03 s buffer (threshold 1.07).
    eq(call(hw.is_cast_safe, 1.07, 0.6, hw.STEADY_SHOT_GRACE, 0), true,
        "latency floor: zero latency uses the 0.03 buffer")
    eq(call(hw.is_cast_safe, 1.07, 0.6, hw.STEADY_SHOT_GRACE, 0.01), true,
        "latency floor: 0.01 latency still uses the 0.03 buffer")
    eq(call(hw.is_cast_safe, 1.0701, 0.6, hw.STEADY_SHOT_GRACE, 0.01), false,
        "latency floor: just past the buffered threshold is unsafe")
    eq(call(hw.is_cast_safe, 1.07, 0.6, hw.STEADY_SHOT_GRACE, nil), true,
        "latency floor: nil latency falls back to the 0.03 buffer")

    -- The threshold never goes below 0: a shot due now with no grace still allows a
    -- 0-second cast, and nothing positive.
    eq(call(hw.is_cast_safe, 0, 0, hw.MULTI_SHOT_GRACE, 0.5), true,
        "clamp: a zero-length cast at a past-due shot is safe (threshold floors at 0)")
    eq(call(hw.is_cast_safe, 0.01, 0, hw.MULTI_SHOT_GRACE, 0.5), false,
        "clamp: any remaining cast at a past-due shot is unsafe")

    -- A nil grace reads as the steady-shot default (the reference's `or 0.5`).
    eq(call(hw.is_cast_safe, 1.0, 0.6, nil, 0.1), true,
        "nil grace: defaults to the steady-shot grace (boundary safe)")
    eq(call(hw.is_cast_safe, 1.01, 0.6, nil, 0.1), false,
        "nil grace: defaults to the steady-shot grace (just above unsafe)")

    eq(call(hw.is_cast_safe, nil, 1.0, hw.STEADY_SHOT_GRACE, 0.1), false,
        "invalid remaining cast reports unsafe")
    eq(call(hw.is_cast_safe, 1.0, nil, hw.STEADY_SHOT_GRACE, 0.1), false,
        "an unknown next shot time reports unsafe")
end

--=========================================================================================
-- 4) is_stopped_position_safe: stop at or before the window open is safe
--=========================================================================================
do
    -- Window opens at 10 + 2 - 0.5 = 11.5.
    eq(call(hw.is_stopped_position_safe, false, 1.0, 10, 2, 0.5), true,
        "stopped well before the window -> safe")
    eq(call(hw.is_stopped_position_safe, false, 11.5, 10, 2, 0.5), true,
        "stopped exactly when the window opens -> safe (<= boundary)")
    eq(call(hw.is_stopped_position_safe, false, 11.51, 10, 2, 0.5), false,
        "stopped after the window opened -> unsafe")
    eq(call(hw.is_stopped_position_safe, true, 1.0, 10, 2, 0.5), false,
        "still moving -> unsafe even when stopped early")
    eq(call(hw.is_stopped_position_safe, true, nil, 10, 2, 0.5), false,
        "still moving with no stop stamp -> unsafe")
    eq(call(hw.is_stopped_position_safe, false, nil, 10, 2, 0.5), true,
        "not moving, never stopped this session -> safe")
    eq(call(hw.is_stopped_position_safe, false, "soon", 10, 2, 0.5), true,
        "a non-number stop stamp reads as never stopped (not moving)")

    eq(call(hw.is_stopped_position_safe, false, 1.0, 10, 2, 0), false,
        "no cast window -> unsafe")
    eq(call(hw.is_stopped_position_safe, false, 1.0, 10, 2, nil), false,
        "nil cast window -> unsafe")
    eq(call(hw.is_stopped_position_safe, false, 1.0, 10, 0, 0.5), false,
        "zero duration -> unsafe")
    eq(call(hw.is_stopped_position_safe, false, 1.0, 10, nil, 0.5), false,
        "nil duration -> unsafe")
    eq(call(hw.is_stopped_position_safe, false, 1.0, nil, 2, 0.5), false,
        "nil swing anchor -> unsafe")
end

--=========================================================================================
-- 5) time_until_next_shot: live swing first, cooldown fallback second
--=========================================================================================
do
    eq(call(hw.time_until_next_shot, 10, 10, 2, nil), 2,
        "swing: full cycle remaining")
    near(call(hw.time_until_next_shot, 11.5, 10, 2, nil), 0.5,
        "swing: half the cycle remaining")
    eq(call(hw.time_until_next_shot, 13, 10, 2, nil), 0,
        "swing: past the end clamps to 0")
    eq(call(hw.time_until_next_shot, 11, 10, 2, 99), 1,
        "swing wins over the cooldown fallback")
    eq(call(hw.time_until_next_shot, 3, nil, nil, 5), 2,
        "cooldown fallback: 2 s to the cooldown end")
    eq(call(hw.time_until_next_shot, 6, nil, nil, 5), 0,
        "cooldown fallback: past the cooldown end clamps to 0")
    eq(call(hw.time_until_next_shot, 6, nil, 0, 5), 0,
        "a zero duration reads as 'not swinging' and uses the fallback")
    eq(call(hw.time_until_next_shot, 1, nil, nil, nil), nil,
        "neither source reports a cycle -> nil")
    eq(call(hw.time_until_next_shot, nil, 10, 2, 5), nil,
        "an unknown now reports nil")
end

--=========================================================================================
-- 6) sync_duration: duration/speed mapping and the strict 0.01 s drift rule
--=========================================================================================
do
    local duration, speed, reanchor = call(hw.sync_duration, 0.0, 0.011, 2.4)
    eq(duration, 2.4, "drift 0.011: duration is the cooldown duration")
    eq(speed, 2.4, "drift 0.011: speed mirrors the duration (source t.speed)")
    eq(reanchor, true, "drift 0.011: re-anchor (strictly past 0.01)")

    duration, speed, reanchor = call(hw.sync_duration, 0.0, 0.01, 2.4)
    eq(duration, 2.4, "drift exactly 0.01: duration still applied")
    eq(speed, 2.4, "drift exactly 0.01: speed still applied")
    eq(reanchor, false, "drift exactly 0.01: no re-anchor (strict >)")

    duration, speed, reanchor = call(hw.sync_duration, 0.0, 0.009, 2.4)
    eq(duration, 2.4, "drift 0.009: duration still applied")
    eq(speed, 2.4, "drift 0.009: speed still applied")
    eq(reanchor, false, "drift 0.009: no re-anchor")

    duration, speed, reanchor = call(hw.sync_duration, 10.02, 10.0, 2.4)
    eq(duration, 2.4, "anchor behind the cooldown start: duration applied")
    eq(speed, 2.4, "anchor behind the cooldown start: speed applied")
    eq(reanchor, true, "an anchor behind the cooldown start also drifts past the rule")

    duration, speed, reanchor = call(hw.sync_duration, nil, 100.5, 2.0)
    eq(duration, 2.0, "nil previous anchor: duration applied")
    eq(speed, 2.0, "nil previous anchor: speed mirrors the duration")
    eq(reanchor, false, "nil previous anchor reads as the cooldown start -> no drift")

    duration, speed, reanchor = call(hw.sync_duration, 100.5, 100.5, 2.0)
    eq(duration, 2.0, "anchor already on the cooldown start: duration applied")
    eq(speed, 2.0, "anchor already on the cooldown start: speed applied")
    eq(reanchor, false, "an anchor already on the cooldown start does not re-anchor")

    duration, speed, reanchor = call(hw.sync_duration, 0.0, 0, 2.4)
    eq(duration, 2.4, "a zero cooldown start still syncs the duration")
    eq(speed, 2.4, "a zero cooldown start still syncs the speed")
    eq(reanchor, false, "a zero cooldown start cannot anchor -> no re-anchor")

    duration, speed, reanchor = call(hw.sync_duration, 0.0, nil, 2.4)
    eq(duration, 2.4, "a nil cooldown start still syncs the duration")
    eq(speed, 2.4, "a nil cooldown start still syncs the speed")
    eq(reanchor, false, "a nil cooldown start cannot anchor -> no re-anchor")

    local nil_duration = call(hw.sync_duration, 0.0, 0.5, 0)
    eq(nil_duration, nil, "zero cooldown duration -> nil")
    nil_duration = call(hw.sync_duration, 0.0, 0.5, -2)
    eq(nil_duration, nil, "negative cooldown duration -> nil")
    nil_duration = call(hw.sync_duration, 0.0, 0.5, nil)
    eq(nil_duration, nil, "nil cooldown duration -> nil")
end

--=========================================================================================
-- 7) should_restart: max(0.25, latency + 0.05) dedupe window
--=========================================================================================
do
    eq(call(hw.should_restart, 10, nil, 0), true,
        "no previous start -> restart allowed")
    eq(call(hw.should_restart, 10, 0, 0), true,
        "a zero stamp is 'no start yet' -> restart allowed")
    eq(call(hw.should_restart, 10, 10, 0), false,
        "elapsed 0 (same instant) -> blocked")
    eq(call(hw.should_restart, 10.1, 10, 0), false,
        "elapsed 0.1 -> blocked")
    eq(call(hw.should_restart, 10.249, 10, 0), false,
        "elapsed 0.249 -> blocked (inside the 0.25 window)")
    eq(call(hw.should_restart, 10.25, 10, 0), true,
        "elapsed 0.25 -> allowed (strict < boundary)")
    eq(call(hw.should_restart, 10.251, 10, 0), true,
        "elapsed 0.251 -> allowed")

    eq(call(hw.should_restart, 10.3, 10, 0.3), false,
        "latency 0.3 lifts the window to 0.35: elapsed 0.3 -> blocked")
    eq(call(hw.should_restart, 10.4, 10, 0.3), true,
        "latency 0.3: elapsed 0.4 -> allowed")
    eq(call(hw.should_restart, 10.25, 10, 0.05), true,
        "latency 0.05 does not raise the 0.25 floor: elapsed 0.25 -> allowed")
    eq(call(hw.should_restart, 10.24, 10, nil), false,
        "nil latency uses the 0.25 floor: elapsed 0.24 -> blocked")
    eq(call(hw.should_restart, 9.9, 10, 0), true,
        "negative elapsed (clock skew) -> restart allowed")
    eq(call(hw.should_restart, nil, 10, 0), false,
        "an unknown now reports false rather than guessing")
end

--=========================================================================================
-- 8) range_state: melee > sweet_spot > ranged > out_of_range
--=========================================================================================
do
    eq(call(hw.range_state, true, false, false), "melee",
        "melee in band -> melee")
    eq(call(hw.range_state, true, true, true), "melee",
        "melee wins over the sweet spot and ranged states")
    eq(call(hw.range_state, false, true, true), "sweet_spot",
        "sweet spot wins over ranged")
    eq(call(hw.range_state, false, true, false), "sweet_spot",
        "sweet spot alone -> sweet_spot")
    eq(call(hw.range_state, false, false, true), "ranged",
        "ranged alone -> ranged")
    eq(call(hw.range_state, false, false, false), "out_of_range",
        "no band -> out_of_range")

    -- The classic probes answer 1/0; both spellings must read the same as booleans.
    eq(call(hw.range_state, 1, 0, 0), "melee", "numeric 1 reads as in band")
    eq(call(hw.range_state, 0, 1, 0), "sweet_spot", "numeric 1 works for the sweet spot")
    eq(call(hw.range_state, 0, 0, 1), "ranged", "numeric 1 works for the ranged probe")
    eq(call(hw.range_state, 0, 0, 0), "out_of_range", "numeric 0 reads as out of band")

    -- Unknown probes (nil) and junk read as out of band, never as crashes.
    eq(call(hw.range_state, nil, nil, nil), "out_of_range",
        "all-unknown probes fall through to out_of_range")
    eq(call(hw.range_state, nil, nil, true), "ranged",
        "an unknown melee probe does not block the ranged fallback")
    eq(call(hw.range_state, nil, false, nil), "out_of_range",
        "an answerless sweet spot does not fabricate a band")
    eq(call(hw.range_state, "yes", 0, 0), "out_of_range",
        "a non-boolean probe value is never in band")
end

--=========================================================================================
-- 9) cast_bar_display: live cast > hidden window (inclusive) > hidden
--=========================================================================================
do
    eq(call(hw.cast_bar_display, true, nil, nil, 10), "cast",
        "a live cast wins with no window at all")
    eq(call(hw.cast_bar_display, true, 5, 1, 6), "cast",
        "a live cast wins even inside a window")
    eq(call(hw.cast_bar_display, nil, 5, 1, 6), "window",
        "an explicit true is required for the cast mode")
    eq(call(hw.cast_bar_display, false, 10, 0.5, 10), "window",
        "the window start bound is inclusive")
    eq(call(hw.cast_bar_display, false, 10, 0.5, 10.5), "window",
        "the window end bound is inclusive")
    eq(call(hw.cast_bar_display, false, 10, 0.5, 10.25), "window",
        "inside the window")
    eq(call(hw.cast_bar_display, false, 10, 0.5, 9.999), "hidden",
        "just before the window is hidden")
    eq(call(hw.cast_bar_display, false, 10, 0.5, 10.501), "hidden",
        "just after the window is hidden")
    eq(call(hw.cast_bar_display, false, nil, 0.5, 10), "hidden",
        "no window anchor -> hidden")
    eq(call(hw.cast_bar_display, false, 10, nil, 10), "hidden",
        "no window duration -> hidden")
    eq(call(hw.cast_bar_display, false, 10, 0, 10), "hidden",
        "a zero-length window -> hidden")
    eq(call(hw.cast_bar_display, false, 10, -1, 10), "hidden",
        "a negative window -> hidden")
    eq(call(hw.cast_bar_display, false, 10, 0.5, nil), "hidden",
        "an unknown now -> hidden")
    eq(call(hw.cast_bar_display, false, 10, 0.5, "now"), "hidden",
        "a non-number now -> hidden")
end

--=========================================================================================
-- 9b) hold_seconds: the H1 shot clock over the hidden window
--=========================================================================================
do
    -- The window [10, 10.5]: inside reads the time to the closing edge.
    near(call(hw.hold_seconds, 10, 0.5, 10), 0.5,
        "hold: at the window start the full width remains")
    near(call(hw.hold_seconds, 10, 0.5, 10.25), 0.25,
        "hold: mid-window reads the remaining hold")
    eq(call(hw.hold_seconds, 10, 0.5, 10.5), 0,
        "hold: the closing edge reads 0 (inclusive)")
    eq(call(hw.hold_seconds, 10, 0.5, 9.999), nil,
        "hold: just before the window reads nil (not holding)")
    eq(call(hw.hold_seconds, 10, 0.5, 10.501), nil,
        "hold: just after the window reads nil")
    eq(call(hw.hold_seconds, 10, 0.5, nil), nil,
        "hold: an unknown now reads nil")
    eq(call(hw.hold_seconds, nil, 0.5, 10.25), nil,
        "hold: no window anchor reads nil")
    eq(call(hw.hold_seconds, 10, nil, 10.25), nil,
        "hold: no window width reads nil")
    eq(call(hw.hold_seconds, 10, 0, 10.25), nil,
        "hold: a zero width reads nil")
    eq(call(hw.hold_seconds, 10, -0.5, 10.25), nil,
        "hold: a negative width reads nil")
    eq(call(hw.hold_seconds, "10", 0.5, 10.25), nil,
        "hold: a non-number anchor reads nil")
    eq(call(hw.hold_seconds, 10, 0.5, "now"), nil,
        "hold: a non-number now reads nil")

    -- The kernel and the display share the same bounds: a window the display calls
    -- active always yields a number, a hidden one never does.
    local start, duration = 100, 0.55
    eq(call(hw.cast_bar_display, false, start, duration, 100.4), "window",
        "hold: the display sees the window at 100.4")
    near(call(hw.hold_seconds, start, duration, 100.4), 0.15,
        "hold: the kernel counts the hold at 100.4")
    eq(call(hw.cast_bar_display, false, start, duration, 99.9), "hidden",
        "hold: the display is hidden just before the window")
    eq(call(hw.hold_seconds, start, duration, 99.9), nil,
        "hold: and the kernel reads nil there too")
end

--=========================================================================================
-- 10) latency_slice_fraction: latency_window / duration, clamped to [0, 1]
--=========================================================================================
do
    near(call(hw.latency_slice_fraction, 0.1, 2.0), 0.05,
        "0.1 s of latency over a 2 s cast is a twentieth of the bar")
    near(call(hw.latency_slice_fraction, 0.25, 0.5), 0.5,
        "half the window halves the bar")
    near(call(hw.latency_slice_fraction, 0.5, 0.5), 1,
        "a slice exactly the bar width reports 1")
    near(call(hw.latency_slice_fraction, 1, 0.5), 1,
        "a slice wider than the bar clamps to 1")
    eq(call(hw.latency_slice_fraction, 0, 2), 0,
        "zero latency draws no slice")
    eq(call(hw.latency_slice_fraction, -0.5, 2), 0,
        "a negative latency draws no slice")
    eq(call(hw.latency_slice_fraction, 0.1, 0), 0,
        "a zero duration draws no slice")
    eq(call(hw.latency_slice_fraction, 0.1, -2), 0,
        "a negative duration draws no slice")
    eq(call(hw.latency_slice_fraction, 0.1, nil), 0,
        "a nil duration draws no slice")
    eq(call(hw.latency_slice_fraction, nil, 2), 0,
        "a nil latency draws no slice")
    eq(call(hw.latency_slice_fraction, "0.1", 2), 0,
        "a non-number latency draws no slice")
end

--=========================================================================================
-- 11) clip_tint: only an explicit true is safe
--=========================================================================================
do
    eq(call(hw.clip_tint, true), "clipSafe",
        "a clip-safe cast reads green")
    eq(call(hw.clip_tint, false), "clipZone",
        "a clipping cast reads red")
    eq(call(hw.clip_tint, nil), "clipZone",
        "an unknown safety verdict reads red")
    eq(call(hw.clip_tint, 1), "clipZone",
        "only a boolean true is clip-safe")
    eq(call(hw.clip_tint, "true"), "clipZone",
        "a string is never clip-safe")
end

--=========================================================================================
-- 12) TBC micro-details: effective weapon speed, the Steady ratio band, hit caps
--=========================================================================================
-- docs/research/tbc_minmax.md: quiver 15% x Serpent's Swiftness 20% (BM 1.38,
-- bare quiver 1.15), the 1:1 band at eWS 1.3-1.6 s, the French 5:5:1:1 macro
-- above it, 1:2/1:3 at high haste (~0.62 s stacked), and the 142/126/95/79
-- hit-cap ladder.
do
    eq(hw.QUIVER_HASTE, 0.15, "QUIVER_HASTE is 0.15")
    eq(hw.SERPENT_SWIFTNESS_HASTE, 0.20, "SERPENT_SWIFTNESS_HASTE is 0.20")
    eq(hw.EWS_RATIO_LO, 1.3, "EWS_RATIO_LO is 1.3")
    eq(hw.EWS_RATIO_HI, 1.6, "EWS_RATIO_HI is 1.6")
    eq(hw.HIT_CAP_BASE, 142, "HIT_CAP_BASE is 142")
    eq(hw.HIT_CAP_DRAENEI, 126, "HIT_CAP_DRAENEI is 126")
    eq(hw.HIT_CAP_IFF, 95, "HIT_CAP_IFF is 95")
    eq(hw.HIT_CAP_BOTH, 79, "HIT_CAP_BOTH is 79")

    -- The quiver x talent decomposition: BM 1.15 * 1.20 = 1.38, SV 1.15.
    near(call(hw.effective_weapon_speed, 3.0, 1.15 * 1.20), 3.0 / 1.38,
        "ews: a 3.0 weapon under quiver x Serpent's Swiftness reads WS/1.38 (BM)")
    near(call(hw.effective_weapon_speed, 3.0, 1.15), 3.0 / 1.15,
        "ews: a 3.0 weapon under a bare quiver reads WS/1.15 (SV)")
    near(call(hw.effective_weapon_speed, 2.9, 4.64), 2.9 / 4.64,
        "ews: a 2.9 weapon under the full stacked 4.64 mult reads ~0.62 s")
    check(call(hw.effective_weapon_speed, 2.9, 4.64) < 0.63,
        "ews: the stacked-haste figure lands at the ~0.62 s mark")
    eq(call(hw.effective_weapon_speed, nil, 1.38), nil,
        "ews: a nil base speed reports nil (never guess)")
    eq(call(hw.effective_weapon_speed, 0, 1.38), nil,
        "ews: a zero base speed reports nil")
    eq(call(hw.effective_weapon_speed, -3.0, 1.38), nil,
        "ews: a negative base speed reports nil")
    eq(call(hw.effective_weapon_speed, 3.0, nil), nil,
        "ews: a nil haste multiplier reports nil")
    eq(call(hw.effective_weapon_speed, 3.0, 0), nil,
        "ews: a zero haste multiplier reports nil")
    eq(call(hw.effective_weapon_speed, 3.0, "1.38"), nil,
        "ews: a non-number multiplier reports nil")
    eq(call(hw.effective_weapon_speed, 3.0, 1), 3.0,
        "ews: a 1.0 multiplier reads the base speed back")

    -- The ratio band, inclusive at both edges.
    eq(call(hw.steady_ratio_band, 1.3), "one_to_one",
        "ratio: 1.3 is one_to_one (lower edge inclusive)")
    eq(call(hw.steady_ratio_band, 1.6), "one_to_one",
        "ratio: 1.6 is one_to_one (upper edge inclusive)")
    eq(call(hw.steady_ratio_band, 1.45), "one_to_one",
        "ratio: inside 1.3-1.6 is one_to_one")
    eq(call(hw.steady_ratio_band, 1.29), "one_to_two",
        "ratio: below 1.3 is one_to_two (high haste)")
    eq(call(hw.steady_ratio_band, 0.62), "one_to_two",
        "ratio: the stacked ~0.62 s reads one_to_two")
    eq(call(hw.steady_ratio_band, 1.61), "french",
        "ratio: above 1.6 is french (the standard macro)")
    eq(call(hw.steady_ratio_band, 3.0 / 1.38), "french",
        "ratio: an unhasted BM cycle (3.0/1.38) reads french")
    eq(call(hw.steady_ratio_band, nil), nil,
        "ratio: an unknown eWS reports nil (never guess)")
    eq(call(hw.steady_ratio_band, "1.5"), nil,
        "ratio: a non-number eWS reports nil")

    -- The hit-cap ladder.
    eq(call(hw.hit_cap_rating, false, false), 142,
        "hit: no buffs reads the 142 base")
    eq(call(hw.hit_cap_rating, nil, nil), 142,
        "hit: unknown buffs read the 142 base (never assume the raid)")
    eq(call(hw.hit_cap_rating, true, false), 126,
        "hit: Draenei alone reads 126")
    eq(call(hw.hit_cap_rating, 1, 0), 126,
        "hit: the numeric probe spelling reads the same")
    eq(call(hw.hit_cap_rating, false, true), 95,
        "hit: Improved Faerie Fire alone reads 95")
    eq(call(hw.hit_cap_rating, true, true), 79,
        "hit: both buffs read 79")
end

if failures == 0 then
    print("PASS  hunter_window_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  hunter_window_state.lua: " .. tostring(failures) .. " of "
        .. tostring(checks) .. " checks failed")
    os.exit(1)
end
