-- tests/hunter_guide_state.lua: offline tests for the hunter next-action guide: the pure
-- rule engine (hunter_guide.lua) and the provider glue + drive (classes/hunter.lua) over
-- the real compat.lua + utils.lua + nextaction_ui.lua + hunter_window.lua in a sandbox.
--
-- Pins:
--   * hunter_guide.lua loads with NO WoW API at all (a strict sandbox errors on any
--     global read) and the frozen rule matrix: the live-cast RIDE hold (Steady,
--     Multi and Aimed) winning over the window and the cooldowns, the Wrath
--     cooldown-priority block (Kill Shot execute-gated > MM Chimera > SV
--     Explosive > Aimed > non-SV Arcane > Steady filler, with no window hold
--     and no clip check on any arm), the hidden-window HOLD with its inclusive
--     edges on every family except Wrath, the TBC Kill Command / Bestial Wrath /
--     Rapid Fire priority (in that order, before the weave, behind the window),
--     the Era-SoD Chimera weave (instant rune above the Era weave, behind the
--     window; pet-rune builds read as plain Era), the Era Aimed Shot prompt (3 s cast, shadows Multi while due) with its equality
--     boundaries, the Multi-Shot weave (Era and TBC, 0 grace, shadows Steady while
--     due), the Steady known-rank gate (unknown Steady never prompts: the Era bug
--     fix) and the clip-safe boundaries at exactly is_cast_safe's equality, the
--     queued ride (and rule 6 outranking it), absent ranged state -> no action, the
--     family gates (known=false fires nothing on any other client),
--   * the reused hunter_window maths: synced_duration preferred over speed (both ways),
--     the ends_at-only fallback, and measure-zero style guarding (a missing
--     hunter_window fails closed rather than erroring),
--   * the frozen output fields are overwritten on every call (stale fields can never
--     survive into a reused out table) and nil inputs never error,
--   * the gather into the caller-owned reused table: every frozen input, the live-cast
--     detection through the steady, multi AND aimed rank tables, the cached-or-recomputed
--     hidden window, the GCD-echo filter on every cooldown (1.51/1.52 boundary), the
--     family gates (TBC-only rules known=false off-TBC, the Era Aimed rule
--     known=false off-Era, Steady on its known-rank gate), stale-field overwrites,
--     the compensated-latency basis (calibrated when usable, raw fallback) and
--     the rank-resolution fallback,
--   * the provider contract shape (base slot keys, six slots; the Era three-slot
--     set with its aimed live-cast swipe; the steady cooldown_key resolving into the
--     gathered inputs, possible actions naming declared slots),
--   * the display mapping through the real frame sandbox (action -> slot -> fade targets,
--     the HOLD/RIDE texts, the live-cast-fed swipe and its latch, the option gates),
--   * the config/options parity for every new hunter key and the TOC load order,
--   * the drive wiring (post_init -> ui.init, on_bar_update -> the settings diff +
--     ui.on_bar_update) exercised through the real hooks.
-- Run from the repo root: lua5.1 tests/hunter_guide_state.lua  (any cwd works).

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

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
local function near(got, want, tol, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > tol then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

--=========================================================================================
-- 0) The pure engine: a strict sandbox that errors on any global read
--=========================================================================================
local pure = {}
do
    local strict = {
        type = type, tonumber = tonumber, tostring = tostring,
        pairs = pairs, ipairs = ipairs, math = math, string = string,
    }
    setmetatable(strict, {
        __index = function(_, key)
            error("hunter guide touched a global: " .. tostring(key))
        end,
    })
    -- The reused pure maths first (the engine calls hunter_window at runtime; the real
    -- TOC loads hunter_window.lua later, so nothing is captured at load).
    local window_chunk = assert(loadfile(ROOT .. "hunter_window.lua"))
    setfenv(window_chunk, strict)
    local ok, err = pcall(window_chunk, "SwedgeTimer", pure)
    check(ok, "hunter_window.lua loads into the pure strict sandbox (" .. tostring(err) .. ")")
    local chunk = assert(loadfile(ROOT .. "hunter_guide.lua"))
    setfenv(chunk, strict)
    ok, err = pcall(chunk, "SwedgeTimer", pure)
    check(ok, "hunter_guide.lua loads with no WoW API and no globals (" .. tostring(err) .. ")")
end

local hg = pure.hunter_guide
check(type(hg) == "table", "hunter_guide.lua defines st.hunter_guide")
check(type(hg.evaluate) == "function", "the pure engine is exported")
eq(hg.STEADY_CAST_SECONDS_DEFAULT, 1.5, "the steady cast-time default is 1.5 s")
eq(hg.STEADY_GRACE_DEFAULT, 0.5, "the steady grace default mirrors the reference (0.5)")
eq(hg.MULTI_CAST_SECONDS_DEFAULT, 0.5, "the multi cast-time default is 0.5 s")
eq(hg.MULTI_GRACE_DEFAULT, 0, "the multi grace default is 0 (no grace)")
eq(hg.KILL_SHOT_EXECUTE_FRAC, 0.20, "the Kill Shot execute threshold is 0.20")
eq(hg.SNIPER_CAST_SECONDS_DEFAULT, 4.0, "the Sniper cast-time default is 4.0 s")
eq(hg.HAWK_MAX_ACTIVE, 2, "the Summon Hawk upkeep cap is 2")
check(type(pure.hunter_window) == "table", "the reused hunter_window maths load alongside")

-- The pure clip-margin helper (the practice clip drill's maths): the seconds between
-- the press and the LATEST safe start. Its arithmetic must agree with is_cast_safe
-- exactly, or the drill would grade a cast the engine calls unsafe.
do
    check(type(hg.cast_margin) == "function", "the engine exports the pure cast_margin")
    local margin = hg.cast_margin
    -- A steady cast (1.5 s) under the steady grace (0.5) with no latency: the
    -- deadline is 1.5 + 0 - 0.5 + 0.03 = 1.03 s, so a 2 s window leaves 0.97 s.
    near(margin(1.5, 0, 2.0, 0.5), 0.97, 1e-9,
        "cast_margin: the steady deadline is the cast plus the latency minus the grace")
    -- Exactly on the deadline: the margin is zero (the last safe start).
    near(margin(1.5, 0, 1.03, 0.5), 0, 1e-9, "cast_margin: the deadline is the zero margin")
    -- Past the deadline: negative (the cast would clip).
    check(margin(1.5, 0, 1.0, 0.5) < 0, "cast_margin: a cast past the deadline clips")
    -- The latency floor: is_cast_safe floors its buffer at 0.03 s, so a latency
    -- below the floor still leaves the full buffer (only the cast term grows).
    near(margin(1.5, 0.01, 2.0, 0.5), 0.96, 1e-9,
        "cast_margin: the latency buffer is floored at 0.03 s like is_cast_safe")
    -- The Multi-Shot grace is 0, so its deadline is the cast itself.
    near(margin(0.5, 0, 0.53, 0), 0, 1e-9, "cast_margin: the Multi grace is zero")
    -- The engine's verdict and the margin never disagree: a positive margin is
    -- clip-safe, a negative one is not.
    local window = pure.hunter_window
    for _, ttl in ipairs({ 0.5, 1.0, 1.03, 2.0, 3.5 }) do
        local m = margin(1.5, 0.05, ttl, 0.5)
        local safe = window.is_cast_safe(1.5 + 0.05, ttl, 0.5, 0.05)
        eq((m ~= nil and m >= 0), safe, "cast_margin agrees with is_cast_safe at ttl " .. tostring(ttl))
    end
    -- Unknown inputs never guess.
    eq(margin(nil, 0, 2.0, 0.5), nil, "cast_margin: an unknown cast time reports nil")
    eq(margin(1.5, 0, nil, 0.5), nil, "cast_margin: an unknown window reports nil")
    eq(margin(0 / 0, 0, 2.0, 0.5), nil, "cast_margin: a NaN cast time reports nil")
    eq(margin(1.5, 0, 0 / 0, 0.5), nil, "cast_margin: a NaN window reports nil")
    -- A missing grace reads the steady-shot default (the engine's own fallback).
    near(margin(1.5, 0, 2.0, nil), margin(1.5, 0, 2.0, 0.5), 1e-9,
        "cast_margin: a missing grace reads the steady-shot grace")
end

-- Rule-matrix inputs: everything the frozen input set names, with a baseline that lands
-- on rule 6c (no cast, no window, nothing known/on cooldown, ttl 2 s, cast 1.5 + 0.05
-- fits). The TBC gates default to unknown (known=false), so the baseline runs exactly
-- the old matrix; steady_known defaults to true (a client that knows Steady Shot),
-- aimed_known to false (the Era-only rule). NONE clears a key (a nil literal in an
-- override table is simply absent in Lua).
local NONE = {}
local function inp(overrides)
    local t = {
        now = 100,
        swing_start = 99, swing_speed = 3.0, swing_ends_at = 102,
        synced_duration = nil,
        latency = 0.05,
        hidden_window_start = nil, hidden_window_duration = nil,
        auto_repeat_active = true,
        raptor_strike_queued = false, steady_shot_queued = false,
        casting = false,
        steady_cast_seconds = 1.5,
        steady_known = true,
        steady_remaining = nil, steady_duration = nil,
        steady_remaining_cd = nil,
        multi_remaining = nil, multi_cast_seconds = 0.5, multi_remaining_cd = nil,
        multi_known = false,
        aimed_known = false, aimed_remaining_cd = nil, aimed_cast_seconds = 3.0,
        aimed_remaining = nil, aimed_duration = nil,
        kc_known = false, kc_remaining_cd = nil,
        bw_known = false, bw_remaining_cd = nil,
        rf_known = false, rf_remaining_cd = nil,
        hawk_known = false, hawk_active_count = nil, hawk_remaining_cd = nil,
        sniper_known = false, sniper_remaining_cd = nil, sniper_cast_seconds = 4.0,
        sniper_remaining = nil, sniper_duration = nil,
        killshot_known = false, killshot_remaining_cd = nil, target_hp_frac = nil,
        chimera_known = false, chimera_remaining_cd = nil,
        explosive_known = false, explosive_remaining_cd = nil,
        wrath_aimed_known = false, wrath_aimed_remaining_cd = nil,
        arcane_known = false, arcane_remaining_cd = nil,
        target_in_range = 1,
    }
    for k, v in pairs(overrides or {}) do
        if v == NONE then
            t[k] = nil
        else
            t[k] = v
        end
    end
    return t
end

local function evaluate(overrides)
    local out = {}
    local ret = hg.evaluate(inp(overrides), out)
    eq(ret, out, "evaluate returns the caller's out table")
    return out
end

-- Baseline (rule 6c): nothing else to do -> Steady Shot.
do
    local out = evaluate({})
    eq(out.action, "steady", "baseline: the cast fits clip-safe -> Steady Shot")
    eq(out.hold, false, "baseline: no hold")
    eq(out.hold_text, nil, "baseline: no hold text")
    eq(out.filler_slot, nil, "baseline: filler_slot stays nil")
    eq(out.judge_slot, nil, "baseline: judge_slot stays nil")
    eq(out.rotation_key, nil, "baseline: rotation_key stays nil")
    eq(out.waiting_judgement, false, "baseline: waiting_judgement stays false")
    eq(out.effective_weapon_speed, 3.0,
        "baseline: the eWS output is the live cycle length (swing_speed)")
    eq(out.steady_ratio, "french",
        "baseline: a 3.0 cycle reads the french band")
end

-- The eWS/ratio display pair (never rule inputs): synced_duration preferred
-- over swing_speed, nil without a cycle, closed without hunter_window.
do
    eq(evaluate({ synced_duration = 1.5 }).steady_ratio, "one_to_one",
        "ews: a 1.5 synced cycle reads one_to_one")
    eq(evaluate({ synced_duration = 1.5 }).effective_weapon_speed, 1.5,
        "ews: the output is the synced duration, not the swing speed")
    eq(evaluate({ synced_duration = 1.5, swing_speed = 5.0 }).steady_ratio,
        "one_to_one", "ews: the synced duration wins over the swing speed")
    eq(evaluate({ synced_duration = 1.2 }).steady_ratio, "one_to_two",
        "ews: a 1.2 cycle reads one_to_two (high haste)")
    eq(evaluate({ synced_duration = 2.5 }).steady_ratio, "french",
        "ews: a 2.5 cycle reads french")
    eq(evaluate({ swing_speed = 1.4 }).steady_ratio, "one_to_one",
        "ews: without a synced duration the swing speed times the band")
    eq(evaluate({ swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE, swing_start = NONE }).steady_ratio, nil,
        "ews: absent ranged state yields no ratio (never guess)")
    eq(evaluate({ swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE, swing_start = NONE }).effective_weapon_speed, nil,
        "ews: absent ranged state yields no eWS either")
    eq(evaluate({}).action, "steady",
        "ews: the display pair never diverts the prompt")

    -- A flavor without the reused maths reports no pair and no error.
    local saved_window = pure.hunter_window
    pure.hunter_window = nil
    local degraded = {}
    local ok, err = pcall(hg.evaluate, inp({}), degraded)
    check(ok, "evaluate without hunter_window does not error on the ews path ("
        .. tostring(err) .. ")")
    eq(degraded.steady_ratio, nil,
        "without hunter_window the ratio fails closed (no guess)")
    eq(degraded.effective_weapon_speed, nil,
        "without hunter_window the eWS fails closed too")
    eq(degraded.action, nil,
        "without hunter_window the clip check still fails closed")
    pure.hunter_window = saved_window
    eq(hg.evaluate(inp({})).steady_ratio, "french",
        "restoring hunter_window restores the ratio")
end

-- Rule 1: the live Steady cast.
do
    local out = evaluate({ steady_remaining = 0.5 })
    eq(out.action, nil, "rule 1: a live Steady cast shows no action")
    eq(out.hold, true, "rule 1: a live Steady cast holds")
    eq(out.hold_text, "RIDE", "rule 1: the live Steady cast reads RIDE")
    eq(evaluate({ steady_remaining = 0 }).hold_text, "RIDE",
        "rule 1 boundary: a cast at its last instant is still live")
    eq(evaluate({ steady_remaining = 0.3, hidden_window_start = 99.9,
        hidden_window_duration = 0.5 }).hold_text, "RIDE",
        "rule 1 outranks the hidden window")
    eq(evaluate({ steady_remaining = 0.3, steady_remaining_cd = 5 }).hold_text, "RIDE",
        "rule 1 outranks the Steady cooldown")
    eq(evaluate({ steady_remaining = 0.3, raptor_strike_queued = true }).hold_text, "RIDE",
        "rule 1 outranks the queued ride")
    eq(evaluate({ casting = true }).action, "steady",
        "rule 1: the generic casting flag alone does not hold (the RIDE keys off "
        .. "steady_remaining)")
    eq(evaluate({ casting = true, steady_remaining = 0.4 }).hold_text, "RIDE",
        "rule 1: casting plus a live Steady cast holds")
end

-- Rule 1 extension: the live Multi-Shot cast rides instead of re-prompting itself.
do
    local out = evaluate({ multi_remaining = 0.2 })
    eq(out.action, nil, "rule 1: a live Multi cast shows no action")
    eq(out.hold, true, "rule 1: a live Multi cast holds")
    eq(out.hold_text, "RIDE", "rule 1: the live Multi cast reads RIDE")
    eq(evaluate({ multi_remaining = 0 }).hold_text, "RIDE",
        "rule 1 boundary: a Multi cast at its last instant is still live")
    eq(evaluate({ multi_remaining = 0.2, hidden_window_start = 99.9,
        hidden_window_duration = 0.5 }).hold_text, "RIDE",
        "rule 1: the live Multi cast outranks the hidden window")
    eq(evaluate({ multi_remaining = 0.2, multi_known = true,
        multi_remaining_cd = NONE }).hold_text, "RIDE",
        "rule 1: the live Multi cast outranks its own due prompt")
    eq(evaluate({ steady_remaining = 0.3, multi_remaining = 0.2 }).hold_text, "RIDE",
        "rule 1: both casts live still rides (no error, no action)")
end

-- Rule 1 extension: the live Aimed Shot cast rides instead of re-prompting itself.
do
    local out = evaluate({ aimed_known = true, aimed_remaining = 1.2 })
    eq(out.action, nil, "rule 1: a live Aimed cast shows no action")
    eq(out.hold, true, "rule 1: a live Aimed cast holds")
    eq(out.hold_text, "RIDE", "rule 1: the live Aimed cast reads RIDE")
    eq(evaluate({ aimed_known = true, aimed_remaining = 0 }).hold_text, "RIDE",
        "rule 1 boundary: an Aimed cast at its last instant is still live")
    eq(evaluate({ aimed_known = true, aimed_remaining = 1.2, hidden_window_start = 99.9,
        hidden_window_duration = 0.5 }).hold_text, "RIDE",
        "rule 1: the live Aimed cast outranks the hidden window")
    eq(evaluate({ aimed_known = true, aimed_remaining = 1.2,
        aimed_remaining_cd = NONE }).hold_text, "RIDE",
        "rule 1: the live Aimed cast outranks its own due prompt")
    eq(evaluate({ aimed_known = true, aimed_remaining = 1.2, multi_remaining = 0.2,
        steady_remaining = 0.3 }).hold_text, "RIDE",
        "rule 1: all three casts live still rides (no error, no action)")
end

-- Rule 1 extension: the live Sniper Shot cast rides instead of re-prompting
-- itself (Forever F2's swipe pair).
do
    local out = evaluate({ sniper_known = true, sniper_remaining = 2.0 })
    eq(out.action, nil, "rule 1: a live Sniper cast shows no action")
    eq(out.hold, true, "rule 1: a live Sniper cast holds")
    eq(out.hold_text, "RIDE", "rule 1: the live Sniper cast reads RIDE")
    eq(evaluate({ sniper_known = true, sniper_remaining = 0 }).hold_text, "RIDE",
        "rule 1 boundary: a Sniper cast at its last instant is still live")
    eq(evaluate({ sniper_known = true, sniper_remaining = 2.0,
        hidden_window_start = 99.9, hidden_window_duration = 0.5 }).hold_text, "RIDE",
        "rule 1: the live Sniper cast outranks the hidden window")
    eq(evaluate({ sniper_known = true, sniper_remaining = 2.0,
        sniper_remaining_cd = NONE }).hold_text, "RIDE",
        "rule 1: the live Sniper cast outranks its own due prompt")
    eq(evaluate({ sniper_known = true, sniper_remaining = 2.0,
        steady_remaining = 0.3, multi_remaining = 0.2 }).hold_text, "RIDE",
        "rule 1: every cast live still rides (no error, no action)")
end

-- Rule 6a: the Era Aimed Shot prompt (3 s cast under the steady-shot grace). The 3 s
-- cast only fits a slow (or freshly fired) Auto cycle: every basic pin below runs a
-- 4.0 s synced cycle (ttl 3.0 s), the weapon-speed breakpoint falling out of the
-- clip check itself with no 3.0 s constant anywhere.
do
    eq(evaluate({ aimed_known = true, synced_duration = 4.0 }).action, "aimed",
        "rule 6a: a due Aimed Shot prompts on Era")
    eq(evaluate({ aimed_known = true, synced_duration = 4.0 }).hold, false,
        "rule 6a: the Aimed prompt shows no hold")
    eq(evaluate({ aimed_known = true, synced_duration = 4.0 }).action, "aimed",
        "rule 6a: the 3 s cast fits the slow cycle (breakpoint emerges, no constant)")
    eq(evaluate({ aimed_known = true, multi_known = true,
        synced_duration = 4.0 }).action, "aimed",
        "rule 6a shadows a due Multi-Shot: the primary filler goes first")
    eq(evaluate({ aimed_known = true, aimed_remaining_cd = 4 }).action, "steady",
        "rule 6a: Aimed on cooldown falls through to the steady weave")
    eq(evaluate({ aimed_known = true, aimed_remaining_cd = 4, steady_known = false,
        multi_known = true }).action, "multi",
        "rule 6a: with Steady unknown the fall-through lands on Multi-Shot")
    eq(evaluate({ aimed_known = NONE, aimed_remaining_cd = NONE }).action, "steady",
        "rule 6a: an unknown Aimed gate never fires")
    eq(evaluate({ aimed_known = true, kc_known = true }).action, "kill_command",
        "rule 3 outranks a due Aimed Shot")
    eq(evaluate({ aimed_known = true, hidden_window_start = 99.9,
        hidden_window_duration = 0.5 }).hold_text, "HOLD",
        "rule 2 outranks a due Aimed Shot")
    eq(evaluate({ aimed_known = true, aimed_remaining = 1.2 }).hold_text, "RIDE",
        "rule 1 outranks a due Aimed Shot: the live cast rides")

    -- The Era silence pin: no known shot at all (Era without Aimed/Multi learned,
    -- or Steady's fallback id on a client without the spell) yields no prompt even
    -- with a wide-open window - never the rank-1 fallback.
    eq(evaluate({ steady_known = false }).action, nil,
        "rule 6c: an unknown Steady Shot never prompts (the Era bug fix)")
    eq(evaluate({ steady_known = false }).hold, false,
        "rule 6c: the unknown-Steady silence shows no hold when nothing is queued")
    eq(evaluate({ steady_known = false, aimed_known = false,
        multi_known = false }).action, nil,
        "Era: no known shot yields no action (never guess, never the fallback)")

    -- is_cast_safe's equality boundary with the 3.0 s Aimed cast: latency 0.03 floors
    -- the buffer at 0.03, remaining is 3.03 and ttl must be exactly 2.56. Steady is
    -- gated unknown here (the Era shape), so a withheld Aimed prompt shows nothing.
    eq(evaluate({ aimed_known = true, steady_known = false, latency = 0.03,
        synced_duration = 3.56 }).action,
        "aimed", "rule 6a boundary: remaining == ttl + grace - latency is safe")
    eq(evaluate({ aimed_known = true, steady_known = false, latency = 0.03,
        synced_duration = 3.55 }).action,
        nil, "rule 6a boundary: one hundredth over withholds the aimed prompt")
    eq(evaluate({ aimed_known = true, steady_known = false, latency = 0.03,
        synced_duration = 3.55, raptor_strike_queued = true }).hold_text, "RIDE",
        "rule 6a boundary: the withheld aimed prompt falls through to the queued ride")

    -- Absent ranged state (no ttl): no Aimed prompt, no guess.
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE, aimed_known = true }).action, nil,
        "rule 6a: absent ranged state yields no aimed prompt (never guess)")

    -- A missing Aimed cast time falls back to the frozen 3.0 s default (Steady gated
    -- unknown so the fallback is observed directly).
    eq(evaluate({ aimed_known = true, aimed_cast_seconds = NONE, latency = 0.03,
        steady_known = false, synced_duration = 3.56 }).action, "aimed",
        "rule 6a: a missing Aimed cast time falls back to 3.0 s")
    eq(evaluate({ aimed_known = true, aimed_cast_seconds = NONE, latency = 0.03,
        steady_known = false, synced_duration = 3.55 }).action, nil,
        "rule 6a: the fallback Aimed cast time still obeys the boundary")

    -- A missing latency reads as zero: remaining 3.0 needs ttl 2.53 for the equality.
    eq(evaluate({ aimed_known = true, latency = NONE, steady_known = false,
        synced_duration = 3.53 }).action, "aimed",
        "rule 6a: a missing latency reads as zero (equality)")
    eq(evaluate({ aimed_known = true, latency = NONE, steady_known = false,
        synced_duration = 3.52 }).action, nil,
        "rule 6a: a missing latency reads as zero (unsafe)")

    -- A missing hunter_window fails the aimed check closed too (and Steady with it:
    -- no ttl, no weave at all).
    local saved_window = pure.hunter_window
    pure.hunter_window = nil
    local degraded = {}
    local ok, err = pcall(hg.evaluate, inp({ aimed_known = true }), degraded)
    check(ok, "evaluate without hunter_window does not error on the aimed path ("
        .. tostring(err) .. ")")
    eq(degraded.action, nil,
        "without hunter_window the aimed check fails closed (no guess)")
    pure.hunter_window = saved_window
    eq(hg.evaluate(inp({ aimed_known = true, synced_duration = 4.0 })).action, "aimed",
        "restoring hunter_window restores the aimed prompt")
end

-- Rules 3-5: the TBC cooldown prompts (Kill Command > Bestial Wrath > Rapid Fire).
do
    eq(evaluate({ kc_known = true }).action, "kill_command",
        "rule 3: a ready Kill Command is the #1 prompt")
    eq(evaluate({ kc_known = true }).hold, false,
        "rule 3: the Kill Command prompt shows no hold")
    eq(evaluate({ kc_known = true, steady_remaining = 0.3 }).hold_text, "RIDE",
        "rule 1 outranks Kill Command: a live cast rides first")
    eq(evaluate({ kc_known = true, hidden_window_start = 99.9,
        hidden_window_duration = 0.5 }).hold_text, "HOLD",
        "rule 2 outranks Kill Command: the window holds first")
    eq(evaluate({ kc_known = true, bw_known = true, rf_known = true,
        multi_known = true }).action, "kill_command",
        "rule 3 outranks every later prompt")
    eq(evaluate({ kc_known = true, kc_remaining_cd = 30 }).action, "steady",
        "rule 3: Kill Command on cooldown falls through to the weave")
    eq(evaluate({ kc_known = true, kc_remaining_cd = 30 }).hold, false,
        "rule 3: the cooldown fall-through shows no hold when nothing is queued")
    eq(evaluate({ kc_known = NONE }).action, "steady",
        "rule 3: an unknown KC gate never fires (non-TBC clients unaffected)")

    eq(evaluate({ kc_known = true, kc_remaining_cd = 30, bw_known = true }).action,
        "bestial_wrath", "rule 4: Bestial Wrath fires with Kill Command cooling down")
    eq(evaluate({ bw_known = true, rf_known = true }).action, "bestial_wrath",
        "rule 4 outranks Rapid Fire")
    eq(evaluate({ bw_known = true, bw_remaining_cd = 60 }).action, "steady",
        "rule 4: Bestial Wrath on cooldown falls through to the weave")
    eq(evaluate({ bw_known = NONE, bw_remaining_cd = NONE }).action, "steady",
        "rule 4: an unknown BW gate never fires")

    eq(evaluate({ kc_known = true, kc_remaining_cd = 30, bw_known = true,
        bw_remaining_cd = 60, rf_known = true }).action, "rapid_fire",
        "rule 5: Rapid Fire fires with Kill Command and Bestial Wrath cooling down")
    eq(evaluate({ rf_known = true, rf_remaining_cd = 300,
        multi_known = true }).action, "multi",
        "rule 5: Rapid Fire on cooldown falls through to the weave")
    eq(evaluate({ rf_known = NONE, rf_remaining_cd = NONE }).action, "steady",
        "rule 5: an unknown RF gate never fires")

    -- Absent ranged state with a known, ready Kill Command: the instant needs no
    -- cycle, so the prompt shows (the Retail swing gate keeps this unreachable there:
    -- no TBC family, no known flag).
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE, kc_known = true }).action, "kill_command",
        "rules 3-5: the instants need no ranged cycle")
end

-- Rules W1-W6: the Wrath cooldown-priority block (no window hold, no clip check
-- on any arm). Every pin below runs the WRATH family (save/restore around the
-- block); the gates pin after it shows the same forged inputs run the old
-- matrix anywhere else.
do
    local saved_family = pure.family
    pure.family = "WRATH"

    -- W6 filler baseline: Steady known, nothing else due -> Steady Shot.
    eq(evaluate({}).action, "steady", "wrath: the filler baseline is Steady Shot")
    eq(evaluate({}).hold, false, "wrath: the filler baseline shows no hold")

    -- W1: Kill Shot, execute-gated (0.20 boundary, unknown health never fires).
    eq(evaluate({ killshot_known = true, target_hp_frac = 0.15 }).action, "kill_shot",
        "wrath W1: a ready Kill Shot in execute range prompts")
    eq(evaluate({ killshot_known = true, target_hp_frac = 0.15 }).hold, false,
        "wrath W1: the execute prompt shows no hold")
    eq(evaluate({ killshot_known = true, target_hp_frac = 0.20 }).action, "kill_shot",
        "wrath W1 boundary: exactly 0.20 is execute range (<=)")
    eq(evaluate({ killshot_known = true, target_hp_frac = 0.21 }).action, "steady",
        "wrath W1 boundary: 0.21 falls through to the filler")
    eq(evaluate({ killshot_known = true, target_hp_frac = NONE }).action, "steady",
        "wrath W1: unknown health never prompts the execute (never guess)")
    eq(evaluate({ killshot_known = true, target_hp_frac = 0.15,
        killshot_remaining_cd = 10 }).action, "steady",
        "wrath W1: Kill Shot on cooldown falls through to the filler")
    eq(evaluate({ killshot_known = NONE, killshot_remaining_cd = NONE,
        target_hp_frac = 0.10 }).action, "steady",
        "wrath W1: an unknown Kill Shot gate never fires")
    eq(evaluate({ killshot_known = true, target_hp_frac = 0.15,
        steady_remaining = 0.3 }).hold_text, "RIDE",
        "rule 1 outranks W1: a live cast rides first")
    eq(evaluate({ killshot_known = true, target_hp_frac = 0.15,
        hidden_window_start = 99.9, hidden_window_duration = 0.5 }).action, "kill_shot",
        "wrath: the window never holds a due prompt (no auto-shot management)")

    -- W2/W3: the spec signatures (MM Chimera above SV Explosive).
    eq(evaluate({ chimera_known = true }).action, "chimera",
        "wrath W2: a ready Chimera Shot prompts on MM")
    eq(evaluate({ chimera_known = true, chimera_remaining_cd = 6 }).action, "steady",
        "wrath W2: Chimera on cooldown falls through to the filler")
    eq(evaluate({ chimera_known = NONE, chimera_remaining_cd = NONE }).action, "steady",
        "wrath W2: an unknown Chimera gate never fires")
    eq(evaluate({ explosive_known = true }).action, "explosive",
        "wrath W3: a ready Explosive Shot prompts on SV")
    eq(evaluate({ explosive_known = true, explosive_remaining_cd = 6 }).action, "steady",
        "wrath W3: Explosive on cooldown falls through to the filler")
    eq(evaluate({ killshot_known = true, target_hp_frac = 0.10,
        chimera_known = true, explosive_known = true }).action, "kill_shot",
        "wrath: Kill Shot outranks both signatures")
    eq(evaluate({ chimera_known = true, explosive_known = true }).action, "chimera",
        "wrath: Chimera outranks Explosive while both are due")

    -- W4/W5: the shared Aimed tier, then the MM-only Arcane tier (SV never
    -- Arcanes: Arcane shares its cooldown with Explosive Shot).
    eq(evaluate({ wrath_aimed_known = true }).action, "aimed",
        "wrath W4: a ready Aimed Shot prompts")
    eq(evaluate({ wrath_aimed_known = true, wrath_aimed_remaining_cd = 10 }).action,
        "steady", "wrath W4: Aimed on cooldown falls through to the filler")
    eq(evaluate({ explosive_known = true, wrath_aimed_known = true }).action, "explosive",
        "wrath: Explosive outranks Aimed")
    eq(evaluate({ wrath_aimed_known = true, arcane_known = true }).action, "aimed",
        "wrath: Aimed outranks Arcane")
    eq(evaluate({ arcane_known = true }).action, "arcane",
        "wrath W5: a ready Arcane Shot prompts off-SV")
    eq(evaluate({ arcane_known = true, explosive_known = true }).action, "explosive",
        "wrath W5: a known Explosive suppresses Arcane (the SV shared cooldown)")
    eq(evaluate({ arcane_known = true, explosive_known = true,
        explosive_remaining_cd = 6 }).action, "steady",
        "wrath W5: SV with Explosive cooling down skips Arcane for the filler")
    eq(evaluate({ arcane_known = true, arcane_remaining_cd = 6 }).action, "steady",
        "wrath W5: Arcane on cooldown falls through to the filler")
    eq(evaluate({ arcane_known = NONE, arcane_remaining_cd = NONE }).action, "steady",
        "wrath W5: an unknown Arcane gate never fires")

    -- W6: the demoted filler needs neither a cycle nor a clip window (Auto Shot
    -- fires during the cast on WotLK): it prompts with no ranged state and into
    -- a nearly closed window alike.
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE }).action, "steady",
        "wrath W6: the filler needs no ranged cycle")
    eq(evaluate({ latency = 0.03, synced_duration = 1.0 }).action, "steady",
        "wrath W6: the filler ignores the clip check (unsafe under rule 6c)")
    eq(evaluate({ steady_known = false }).action, nil,
        "wrath W6: an unknown Steady never prompts")
    eq(evaluate({ steady_known = false }).hold, false,
        "wrath W6: the unknown-Steady silence shows no hold")
    eq(evaluate({ steady_known = false, hidden_window_start = 99.9,
        hidden_window_duration = 0.5 }).hold, false,
        "wrath: the window never holds, even with every arm silent")
    eq(evaluate({ steady_known = false, hidden_window_start = 99.9,
        hidden_window_duration = 0.5 }).hold_text, nil,
        "wrath: the relaxed window carries no HOLD text")
    eq(evaluate({ steady_remaining_cd = 2, raptor_strike_queued = true }).hold_text,
        "RIDE", "wrath rule 7: a queue behind a silenced filler still rides")

    -- The family gates: the same forged Wrath inputs run the old matrix off-Wrath.
    pure.family = nil
    eq(evaluate({ killshot_known = true, target_hp_frac = 0.10 }).action, "steady",
        "gates: a forged Kill Shot never prompts off-Wrath")
    eq(evaluate({ chimera_known = true }).action, "steady",
        "gates: a forged Chimera never prompts off-Wrath")
    eq(evaluate({ explosive_known = true }).action, "steady",
        "gates: a forged Explosive never prompts off-Wrath")
    eq(evaluate({ wrath_aimed_known = true }).action, "steady",
        "gates: a forged Wrath Aimed never prompts off-Wrath")
    eq(evaluate({ arcane_known = true }).action, "steady",
        "gates: a forged Arcane never prompts off-Wrath")
    eq(evaluate({ killshot_known = true, target_hp_frac = 0.10,
        hidden_window_start = 99.9, hidden_window_duration = 0.5 }).hold_text, "HOLD",
        "gates: off-Wrath the window still holds over a forged execute")
    pure.family = saved_family
    eq(hg.evaluate(inp({})).action, "steady",
        "restoring the family restores the filler baseline")
end

-- Rule 5b: the Era-SoD Chimera weave (the instant rune above the Era weave,
-- behind the window; pet-rune builds that drop it read as plain Era).
do
    local saved_family = pure.family
    pure.family = "ERA"
    eq(evaluate({ chimera_known = true, synced_duration = 4.0 }).action, "chimera",
        "rule 5b: a ready SoD Chimera weaves above Aimed Shot")
    eq(evaluate({ chimera_known = true, synced_duration = 4.0 }).hold, false,
        "rule 5b: the Chimera weave shows no hold")
    eq(evaluate({ chimera_known = true, chimera_remaining_cd = 6,
        aimed_known = true, synced_duration = 4.0 }).action, "aimed",
        "rule 5b: Chimera on cooldown falls through to the Era weave")
    eq(evaluate({ chimera_known = true, chimera_remaining_cd = 6,
        aimed_known = true, aimed_remaining_cd = 6, multi_known = true }).action, "multi",
        "rule 5b: the fall-through lands on Multi-Shot with Aimed cooling down")
    eq(evaluate({ chimera_known = NONE, chimera_remaining_cd = NONE,
        aimed_known = true, synced_duration = 4.0 }).action, "aimed",
        "rule 5b: an unknown Chimera gate reads as plain Era (pet-rune build)")
    eq(evaluate({ chimera_known = true, kc_known = true }).action, "kill_command",
        "rule 3 outranks the SoD weave")
    eq(evaluate({ chimera_known = true, hidden_window_start = 99.9,
        hidden_window_duration = 0.5 }).hold_text, "HOLD",
        "rule 2 outranks the SoD weave (SoD keeps auto-shot timing)")
    eq(evaluate({ chimera_known = true, steady_remaining = 0.3 }).hold_text, "RIDE",
        "rule 1 outranks the SoD weave: a live cast rides")
    -- The gate: the same forged weave is dead off-Era (and the Wrath arm owns
    -- it on WRATH, pinned above).
    pure.family = nil
    eq(evaluate({ chimera_known = true }).action, "steady",
        "gates: a forged Chimera never weaves off-Era")
    pure.family = saved_family
end

-- Rules F1-F2: the Forever upkeep and cast (behind the window, above the
-- weave). Every pin below runs the FOREVER family (save/restore around the
-- block); the gates pin after it shows the same forged inputs run the old
-- matrix anywhere else.
do
    local saved_family = pure.family
    pure.family = "FOREVER"

    -- F1: Summon Hawk upkeep, strictly below 2 active.
    eq(evaluate({ hawk_known = true, hawk_active_count = 1 }).action, "hawk",
        "forever F1: one hawk prompts the upkeep")
    eq(evaluate({ hawk_known = true, hawk_active_count = 0 }).action, "hawk",
        "forever F1: no hawk prompts the upkeep")
    eq(evaluate({ hawk_known = true, hawk_active_count = 1 }).hold, false,
        "forever F1: the upkeep prompt shows no hold")
    eq(evaluate({ hawk_known = true, hawk_active_count = 2 }).action, "steady",
        "forever F1: two hawks fall through to the weave (cap met)")
    eq(evaluate({ hawk_known = true, hawk_active_count = 3 }).action, "steady",
        "forever F1: over cap still falls through (never un-prompts the weave)")
    eq(evaluate({ hawk_known = true, hawk_active_count = NONE }).action, "steady",
        "forever F1: an unknown count never prompts the upkeep (never guess)")
    eq(evaluate({ hawk_known = true, hawk_active_count = 1,
        hawk_remaining_cd = 30 }).action, "steady",
        "forever F1: the upkeep on cooldown falls through to the weave")
    eq(evaluate({ hawk_known = NONE, hawk_remaining_cd = NONE,
        hawk_active_count = 0 }).action, "steady",
        "forever F1: an unknown hawk gate never fires")
    eq(evaluate({ hawk_known = true, hawk_active_count = 1,
        steady_remaining = 0.3 }).hold_text, "RIDE",
        "rule 1 outranks F1: a live cast rides first")
    eq(evaluate({ hawk_known = true, hawk_active_count = 1,
        hidden_window_start = 99.9, hidden_window_duration = 0.5 }).hold_text, "HOLD",
        "rule 2 outranks F1: the window holds first (conservative)")

    -- F2: Sniper Shot, the 4 s MM cast under the steady-shot grace. Latency
    -- 0.03 floors the buffer at 0.03, remaining is 4.03 and ttl must be exactly
    -- 3.56 (synced 4.56 with the baseline anchor).
    eq(evaluate({ sniper_known = true, latency = 0.03,
        synced_duration = 4.56 }).action, "sniper",
        "forever F2: a due Sniper Shot prompts")
    eq(evaluate({ sniper_known = true, latency = 0.03,
        synced_duration = 4.56 }).hold, false,
        "forever F2 boundary: remaining == ttl + grace - latency is safe")
    eq(evaluate({ sniper_known = true, latency = 0.03,
        synced_duration = 4.55 }).action, "steady",
        "forever F2 boundary: one hundredth over falls through to the weave")
    eq(evaluate({ sniper_known = true, latency = 0.03, steady_known = false,
        synced_duration = 4.55 }).action, nil,
        "forever F2 boundary: with Steady unknown the withheld cast shows nothing")
    eq(evaluate({ sniper_known = true, latency = 0.03, steady_known = false,
        synced_duration = 4.55, raptor_strike_queued = true }).hold_text, "RIDE",
        "forever F2 boundary: the withheld cast falls through to the queued ride")
    eq(evaluate({ sniper_known = true, sniper_remaining_cd = 8,
        synced_duration = 4.56 }).action, "steady",
        "forever F2: Sniper on cooldown falls through to the weave")
    eq(evaluate({ sniper_known = NONE, sniper_remaining_cd = NONE,
        synced_duration = 4.56 }).action, "steady",
        "forever F2: an unknown sniper gate never fires")

    -- Order: the upkeep above the cast, the cast above the weave.
    eq(evaluate({ hawk_known = true, hawk_active_count = 1, sniper_known = true,
        latency = 0.03, synced_duration = 4.56 }).action, "hawk",
        "forever: the upkeep outranks a due Sniper Shot")
    eq(evaluate({ sniper_known = true, multi_known = true, latency = 0.03,
        synced_duration = 4.56 }).action, "sniper",
        "forever F2 shadows a due Multi-Shot: the signature goes first")
    eq(evaluate({ sniper_known = true, sniper_remaining = 2.0 }).hold_text, "RIDE",
        "rule 1 outranks F2: the live Sniper cast rides")

    -- Absent ranged state: the instant upkeep needs no cycle (the Retail swing
    -- gate keeps this unreachable there: no FOREVER family, no known flag),
    -- while the cast needs its clip window like every other weave shot.
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE, hawk_known = true,
        hawk_active_count = 1 }).action, "hawk",
        "forever F1: the upkeep needs no ranged cycle")
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE, sniper_known = true }).action, nil,
        "forever F2: absent ranged state yields no sniper prompt (never guess)")

    -- A missing Sniper cast time falls back to the frozen 4.0 s default.
    eq(evaluate({ sniper_known = true, sniper_cast_seconds = NONE, latency = 0.03,
        synced_duration = 4.56 }).action, "sniper",
        "forever F2: a missing Sniper cast time falls back to 4.0 s")
    eq(evaluate({ sniper_known = true, sniper_cast_seconds = NONE, latency = 0.03,
        synced_duration = 4.55 }).action, "steady",
        "forever F2: the fallback cast time still obeys the boundary")

    -- A missing latency reads as zero: remaining 4.0 needs ttl 3.53.
    eq(evaluate({ sniper_known = true, latency = NONE,
        synced_duration = 4.53 }).action, "sniper",
        "forever F2: a missing latency reads as zero (equality)")
    eq(evaluate({ sniper_known = true, latency = NONE,
        synced_duration = 4.52 }).action, "steady",
        "forever F2: a missing latency reads as zero (unsafe)")

    -- A missing hunter_window fails the sniper check closed (the instant upkeep
    -- needs no maths module and still fires).
    local saved_window = pure.hunter_window
    pure.hunter_window = nil
    local degraded = {}
    local ok, err = pcall(hg.evaluate,
        inp({ sniper_known = true, synced_duration = 4.56 }), degraded)
    check(ok, "evaluate without hunter_window does not error on the sniper path ("
        .. tostring(err) .. ")")
    eq(degraded.action, nil,
        "without hunter_window the sniper check fails closed (no weave: no ttl)")
    eq(hg.evaluate(inp({ hawk_known = true, hawk_active_count = 1 })).action, "hawk",
        "without hunter_window the instant upkeep still fires (no maths needed)")
    pure.hunter_window = saved_window
    eq(hg.evaluate(inp({ sniper_known = true, latency = 0.03,
        synced_duration = 4.56 })).action, "sniper",
        "restoring hunter_window restores the sniper prompt")

    -- The family gates: the same forged Forever inputs run the old matrix
    -- off-Forever (rules 3-5 rely on the gather's TBC gate: a forged Kill
    -- Command still fires, exactly like every other family).
    pure.family = nil
    eq(evaluate({ hawk_known = true, hawk_active_count = 1 }).action, "steady",
        "gates: a forged hawk never prompts off-Forever")
    eq(evaluate({ sniper_known = true, latency = 0.03,
        synced_duration = 4.56 }).action, "steady",
        "gates: a forged Sniper never prompts off-Forever")
    eq(evaluate({ hawk_known = true, hawk_active_count = 1,
        hidden_window_start = 99.9, hidden_window_duration = 0.5 }).hold_text, "HOLD",
        "gates: off-Forever the window still holds over a forged upkeep")
    eq(evaluate({ kc_known = true }).action, "kill_command",
        "gates: rules 3-5 carry no engine family gate (the gather gates TBC)")
    pure.family = saved_family
    eq(hg.evaluate(inp({})).action, "steady",
        "restoring the family restores the filler baseline")
end

--=========================================================================================
-- 0b) The APL UTILITY layer's arms (the utility lane, 2026-10-20)
--=========================================================================================
-- Every line the class's APL asks for now has an engine arm, and every arm
-- reads the live inputs only:
--   * a COOLDOWN line: known on this client and off cooldown.
--   * an AURA line (a buff or a debuff the line maintains): known on this
--     client and the buff is KNOWN DOWN. A buff that is UP is NEVER asked for,
--     and an UNKNOWN buff never prompts (unknown hides).
-- The melee rows also read the weave band ("melee"), the aspect swaps read
-- the mana fraction, and every arm keeps its family gate.
do
    local saved = pure.family

    -- The Serpent Sting upkeep (the ERA APL's i=4, the WotLK i=5/i=7, the
    -- Forever i=8): the sting on the target is KNOWN DOWN.
    pure.family = "ERA"
    eq(evaluate({ serpent_known = true, serpent_active = false }).action, "serpent",
        "utility: the Era Serpent asks when the sting is known down")
    eq(evaluate({ serpent_known = true, serpent_active = true }).action, "steady",
        "utility: the Era Serpent is NEVER asked for while the sting is up")
    eq(evaluate({ serpent_known = true, serpent_active = nil }).action, "steady",
        "utility: an unreadable sting never prompts (unknown hides)")
    eq(evaluate({ serpent_known = false, serpent_active = false }).action, "steady",
        "utility: a client that knows no Serpent rank never asks for it")

    -- The Rapid Fire burst (the ERA APL's i=1, the SOD i=7, the TBC layer).
    eq(evaluate({ rf_known = true, rf_remaining_cd = 0 }).action, "rapid_fire",
        "utility: the Era Rapid Fire pops when it is off cooldown")
    eq(evaluate({ rf_known = true, rf_remaining_cd = 30 }).action, "steady",
        "utility: the Rapid Fire on cooldown leaves the filler baseline")
    eq(evaluate({ rf_known = false, rf_remaining_cd = 0 }).action, "steady",
        "utility: an unknown Rapid Fire never prompts")

    -- The aspect swaps (the TBC mana group, the SoD i=22/i=24, the WotLK i=1/i=2):
    -- the buff is KNOWN DOWN and the mana answers.
    pure.family = "TBC"
    eq(evaluate({ aspect_viper_known = true, aspect_viper_active = false,
        mana_frac = 0.02 }).action, "aspect_viper",
        "utility: the TBC Viper swaps when it is down and the mana is under the start")
    eq(evaluate({ aspect_viper_known = true, aspect_viper_active = true,
        mana_frac = 0.02 }).action, "steady",
        "utility: the TBC Viper is NEVER asked for while the buff is up")
    eq(evaluate({ aspect_viper_known = true, aspect_viper_active = false,
        mana_frac = nil }).action, "steady",
        "utility: an unknown mana never prompts a swap")
    eq(evaluate({ aspect_hawk_known = true, aspect_hawk_active = false,
        mana_frac = 0.6 }).action, "aspect_hawk",
        "utility: the TBC Hawk swaps back when it is down and the mana is over the stop")
    eq(evaluate({ aspect_hawk_known = true, aspect_hawk_active = true,
        mana_frac = 0.6 }).action, "steady",
        "utility: the TBC Hawk is NEVER asked for while the buff is up")

    -- The WotLK arms: the Silencing Shot (i=3), the Serpent (i=5), the Explosive
    -- Trap (i=6), the Black Arrow (SV i=8) and the Multi-Shot (i=9/i=10).
    pure.family = "WRATH"
    eq(evaluate({ chimera_known = true, silencing_shot_known = true,
        silencing_shot_remaining_cd = 0 }).action, "silencing_shot",
        "utility: the WotLK Silencing Shot asks when it is off cooldown")
    eq(evaluate({ chimera_known = true, silencing_shot_known = true,
        silencing_shot_remaining_cd = 12 }).action, "chimera",
        "utility: the Silencing Shot on cooldown hands the step to the Chimera")
    eq(evaluate({ aspect_viper_known = true, aspect_viper_active = false,
        mana_frac = 0.02 }).action, "aspect_viper",
        "utility: the WotLK Viper swaps when it is down and the mana is under 10%")
    eq(evaluate({ aspect_viper_known = true, aspect_viper_active = true,
        mana_frac = 0.02 }).action, "steady",
        "utility: the WotLK Viper is NEVER asked for while the buff is up")
    eq(evaluate({ aspect_dragonhawk_known = true, aspect_dragonhawk_active = false,
        mana_frac = 0.6 }).action, "aspect_dragonhawk",
        "utility: the WotLK Dragonhawk swaps when it is down and the mana is over 30%")
    eq(evaluate({ aspect_dragonhawk_known = true, aspect_dragonhawk_active = true,
        mana_frac = 0.6 }).action, "steady",
        "utility: the WotLK Dragonhawk is NEVER asked for while the buff is up")
    eq(evaluate({ chimera_known = true, explosive_trap_known = true,
        explosive_trap_remaining_cd = 0 }).action, "explosive_trap",
        "utility: the WotLK Explosive Trap asks when it is off cooldown")
    eq(evaluate({ explosive_known = true, explosive_remaining_cd = 6,
        black_arrow_known = true, black_arrow_remaining_cd = 0 }).action, "black_arrow",
        "utility: the WotLK Black Arrow asks when the Explosive Shot is on cooldown")
    eq(evaluate({ utility_multi_known = true, utility_multi_remaining_cd = 0 }).action, "multi",
        "utility: the WotLK Multi-Shot asks when it is off cooldown")
    eq(evaluate({ utility_multi_known = true,
        utility_multi_remaining_cd = 6 }).action, "steady",
        "utility: the WotLK Multi-Shot on cooldown leaves the filler baseline")

    -- The SoD arms: the execute (i=12), the melee rows (i=16/i=17/i=27) and the
    -- Aspect of the Falcon (i=24).
    pure.family = "ERA"
    eq(evaluate({ chimera_known = true, chimera_remaining_cd = 6,
        killshot_known = true, killshot_remaining_cd = 0,
        target_hp_frac = 0.15 }).action, "kill_shot",
        "utility: the SoD execute asks at the E20")
    eq(evaluate({ chimera_known = true, chimera_remaining_cd = 6,
        killshot_known = true, killshot_remaining_cd = 0,
        target_hp_frac = 0.5 }).action, "steady",
        "utility: the SoD execute waits for the execute window")
    eq(evaluate({ chimera_known = true, chimera_remaining_cd = 6,
        raptor_strike_known = true,
        raptor_strike_remaining_cd = 0, weave_band = "melee" }).action, "raptor_strike",
        "utility: the SoD Raptor Strike asks in melee range")
    eq(evaluate({ chimera_known = true, chimera_remaining_cd = 6,
        raptor_strike_known = true,
        raptor_strike_remaining_cd = 0, weave_band = "ranged" }).action, "steady",
        "utility: the SoD Raptor Strike waits for melee range")
    eq(evaluate({ chimera_known = true, chimera_remaining_cd = 6,
        raptor_strike_known = true,
        raptor_strike_remaining_cd = 0 }).action, "steady",
        "utility: an unknown weave band never asks for a melee row")
    eq(evaluate({ chimera_known = true, chimera_remaining_cd = 6,
        aspect_falcon_known = true,
        aspect_falcon_active = false, aspect_viper_known = true,
        aspect_viper_active = false }).action, "aspect_falcon",
        "utility: the SoD Falcon asks when neither the Viper nor the Falcon is up")
    eq(evaluate({ chimera_known = true, chimera_remaining_cd = 6,
        aspect_falcon_known = true,
        aspect_falcon_active = true, aspect_viper_known = true,
        aspect_viper_active = false }).action, "steady",
        "utility: the SoD Falcon is NEVER asked for while the buff is up")

    -- The Forever arms: the Raptor Strike (i=1), the Hunter's Mark (i=2), the
    -- Mongoose Bite (i=3), the Immolation Trap (i=5), the Wing Clip (i=6) and
    -- the Serpent (i=8).
    pure.family = "FOREVER"
    eq(evaluate({ raptor_strike_known = true, raptor_strike_remaining_cd = 0,
        weave_band = "melee" }).action, "raptor_strike",
        "utility: the Forever Raptor Strike asks in melee range")
    eq(evaluate({ hunters_mark_known = true, hunters_mark_active = false }).action, "hunters_mark",
        "utility: the Forever Hunter's Mark asks when the mark is known down")
    eq(evaluate({ hunters_mark_known = true, hunters_mark_active = true }).action, "steady",
        "utility: the Forever Hunter's Mark is NEVER asked for while the mark is up")
    eq(evaluate({ mongoose_bite_known = true, mongoose_bite_remaining_cd = 0,
        weave_band = "melee" }).action, "mongoose_bite",
        "utility: the Forever Mongoose Bite asks in melee range")
    eq(evaluate({ immolation_trap_known = true, immolation_trap_remaining_cd = 0,
        weave_band = "melee" }).action, "immolation_trap",
        "utility: the Forever Immolation Trap asks in melee range")
    eq(evaluate({ wing_clip_known = true, wing_clip_remaining_cd = 0,
        weave_band = "melee" }).action, "wing_clip",
        "utility: the Forever Wing Clip asks in melee range")

    -- The family gates: a forged input never reaches another family's arm.
    pure.family = "FOREVER"
    eq(evaluate({ silencing_shot_known = true,
        silencing_shot_remaining_cd = 0 }).action, "steady",
        "utility: the WotLK Silencing Shot never prompts off-Wrath")
    eq(evaluate({ aspect_hawk_known = true, aspect_hawk_active = false,
        mana_frac = 0.6 }).action, "steady",
        "utility: the TBC Aspect of the Hawk never prompts off-TBC")
    pure.family = "WRATH"
    eq(evaluate({ hunters_mark_known = true, hunters_mark_active = false }).action, "steady",
        "utility: the Forever Hunter's Mark never prompts off-Forever")
    pure.family = "ERA"
    eq(evaluate({ aspect_dragonhawk_known = true,
        aspect_dragonhawk_active = false, mana_frac = 0.6 }).action, "steady",
        "utility: the WotLK Aspect of the Dragonhawk never prompts off-Wrath")
    eq(evaluate({ aspect_falcon_known = true, aspect_falcon_active = false,
        aspect_viper_known = true, aspect_viper_active = false }).action, "steady",
        "utility: the SoD Aspect of the Falcon never prompts on a plain Era client")

    pure.family = saved
    eq(hg.evaluate(inp({})).action, "steady",
        "restoring the family restores the filler baseline")
end

-- Rule 6b: the Multi-Shot weave (Era and TBC, 0 grace, shadows Steady while due).
do
    eq(evaluate({ multi_known = true }).action, "multi",
        "rule 6b: a due Multi-Shot weaves instead of Steady Shot")
    eq(evaluate({ multi_known = true }).hold, false,
        "rule 6b: the Multi prompt shows no hold")
    eq(evaluate({ multi_known = true, multi_remaining_cd = 8 }).action, "steady",
        "rule 6b: Multi-Shot on cooldown leaves the steady-only behaviour intact")
    eq(evaluate({ multi_known = NONE, multi_remaining_cd = NONE }).action, "steady",
        "rule 6b: an unknown Multi gate leaves the steady-only behaviour intact")
    eq(evaluate({ multi_known = true, kc_known = true }).action, "kill_command",
        "rule 3 outranks a due Multi-Shot")
    eq(evaluate({ multi_known = true, bw_known = true,
        bw_remaining_cd = NONE }).action, "bestial_wrath",
        "rule 4 outranks a due Multi-Shot")
    eq(evaluate({ multi_known = true, multi_remaining = 0.2 }).hold_text, "RIDE",
        "rule 1 outranks a due Multi-Shot: the live cast rides")
    eq(evaluate({ multi_known = true, hidden_window_start = 99.9,
        hidden_window_duration = 0.5 }).hold_text, "HOLD",
        "rule 2 outranks a due Multi-Shot")

    -- is_cast_safe's equality boundary with the 0 multi grace: latency 0.03 floors the
    -- buffer at 0.03, the cast is 0.5 s (remaining 0.53) and ttl must be exactly 0.5.
    eq(evaluate({ multi_known = true, latency = 0.03, synced_duration = 1.56 }).action,
        "multi", "rule 6b boundary: remaining == ttl + 0 grace - latency is safe")
    eq(evaluate({ multi_known = true, latency = 0.03, synced_duration = 1.55 }).action,
        nil, "rule 6b boundary: one hundredth over withholds the multi prompt")
    eq(evaluate({ multi_known = true, latency = 0.03, synced_duration = 1.55,
        raptor_strike_queued = true }).hold_text, "RIDE",
        "rule 6b boundary: the withheld multi prompt falls through to the queued ride")

    -- Absent ranged state (no ttl): no Multi prompt, no guess.
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE, multi_known = true }).action, nil,
        "rule 6b: absent ranged state yields no multi prompt (never guess)")

    -- A missing Multi cast time falls back to the frozen 0.5 s default.
    eq(evaluate({ multi_known = true, multi_cast_seconds = NONE, latency = 0.03,
        synced_duration = 1.56 }).action, "multi",
        "rule 6b: a missing Multi cast time falls back to 0.5 s")
    eq(evaluate({ multi_known = true, multi_cast_seconds = NONE, latency = 0.03,
        synced_duration = 1.55 }).action, nil,
        "rule 6b: the fallback Multi cast time still obeys the boundary")

    -- A missing hunter_window fails the multi check closed too.
    local saved_window = pure.hunter_window
    pure.hunter_window = nil
    local degraded = {}
    local ok, err = pcall(hg.evaluate, inp({ multi_known = true }), degraded)
    check(ok, "evaluate without hunter_window does not error on the multi path ("
        .. tostring(err) .. ")")
    eq(degraded.action, nil, "without hunter_window the multi check fails closed")
    pure.hunter_window = saved_window
    eq(hg.evaluate(inp({ multi_known = true })).action, "multi",
        "restoring hunter_window restores the multi prompt")
end

-- Rule 2: the hidden Auto-Shot window (inclusive bounds).
do
    local out = evaluate({ hidden_window_start = 99.9, hidden_window_duration = 0.5 })
    eq(out.action, nil, "rule 2: inside the window no action is shown")
    eq(out.hold, true, "rule 2: inside the window holds")
    eq(out.hold_text, "HOLD", "rule 2: the window reads HOLD")
    eq(evaluate({ hidden_window_start = 100.2, hidden_window_duration = 0.5 }).action,
        "steady", "rule 2: a not-yet-open window does not hold")
    eq(evaluate({ hidden_window_start = 100, hidden_window_duration = 0.5 }).hold_text,
        "HOLD", "rule 2 boundary: the window opens inclusively (now == start)")
    eq(evaluate({ hidden_window_start = 99.5, hidden_window_duration = 0.5 }).hold_text,
        "HOLD", "rule 2 boundary: the window's final instant still holds (now == end)")
    eq(evaluate({ hidden_window_start = 99.49, hidden_window_duration = 0.5 }).action,
        "steady", "rule 2 boundary: just past the end the steady prompt returns")
    eq(evaluate({ hidden_window_start = 99.5, hidden_window_duration = 0 }).action,
        "steady", "rule 2: a zero-length window is never active")
    eq(evaluate({ hidden_window_start = 99.5, hidden_window_duration = -1 }).action,
        "steady", "rule 2: a negative window length is never active")
    eq(evaluate({ hidden_window_start = 99.5, hidden_window_duration = NONE }).action,
        "steady", "rule 2: a window without a length is never active")
    eq(evaluate({ now = NONE, hidden_window_start = 0, hidden_window_duration = 1000 }).action,
        nil, "rule 2: an unknown now can never match the window (and rule 3 needs it too)")
    eq(evaluate({ now = NONE, hidden_window_start = 0,
        hidden_window_duration = 1000 }).hold, false,
        "rule 2: an unknown now shows no hold either")
end

-- Rule 2b: the pre-cast range gate (H4): byte-exact 0 holds before every cast prompt,
-- nil and every other spelling allow.
do
    local out = evaluate({ target_in_range = 0 })
    eq(out.action, nil, "rule 2b: out of range shows no action")
    eq(out.hold, true, "rule 2b: out of range holds")
    eq(out.hold_text, "HOLD", "rule 2b: out of range reads HOLD")

    -- Ahead of the TBC cooldown priority and of the weave.
    eq(evaluate({ target_in_range = 0, kc_known = true }).action, nil,
        "rule 2b outranks the TBC Kill Command priority")
    eq(evaluate({ target_in_range = 0, bw_known = true }).action, nil,
        "rule 2b outranks Bestial Wrath")
    eq(evaluate({ target_in_range = 0, rf_known = true }).action, nil,
        "rule 2b outranks Rapid Fire")
    eq(evaluate({ target_in_range = 0, multi_known = true }).action, nil,
        "rule 2b outranks a due Multi-Shot weave")
    -- Ahead of the queued ride (conservative: out of range nothing fires).
    eq(evaluate({ target_in_range = 0, raptor_strike_queued = true }).hold_text, "HOLD",
        "rule 2b outranks the queued ride")
    -- Behind rule 1: a live cast still rides.
    eq(evaluate({ target_in_range = 0, steady_remaining = 0.3 }).hold_text, "RIDE",
        "rule 1 still outranks the range gate: a live cast rides")

    -- The Wrath arms sit behind the gate too.
    local saved = pure.family
    pure.family = "WRATH"
    eq(evaluate({ target_in_range = 0, killshot_known = true,
        target_hp_frac = 0.10 }).hold_text, "HOLD",
        "rule 2b outranks the Wrath execute")
    eq(evaluate({ target_in_range = 0, chimera_known = true }).hold_text, "HOLD",
        "rule 2b outranks the Wrath MM prompt")
    pure.family = saved
    eq(pure.family, nil, "the pure sandbox carries no family token by default")
    eq(evaluate({ chimera_known = true }).action, "steady",
        "off-Wrath the Chimera arm never prompts (the family gate is back)")

    -- nil = unknown = allowed; numeric 1 and the boolean spellings never hold.
    eq(evaluate({ target_in_range = 1 }).action, "steady",
        "rule 2b: in range allows the prompts (numeric 1)")
    eq(evaluate({ target_in_range = NONE }).action, "steady",
        "rule 2b: an unknown probe allows the prompts (nil = unknown)")
    eq(evaluate({ target_in_range = true }).action, "steady",
        "rule 2b: a boolean true spelling never holds")
    eq(evaluate({ target_in_range = false }).action, "steady",
        "rule 2b: a boolean false spelling is not the byte-exact 0")
end

-- H2 CUT (operator order 2026-10-19, bench/hunter_open_2026-10-19.md section 5):
-- no Bloodlust/Heroism-family suppression anywhere. A live window (a positive
-- lust_remaining overlooked from an older gather) changes nothing: the
-- synced-duration clip math alone decides. Every pin pairs a windowed call
-- against its windowless twin; a reintroduced suppression flips the windowed
-- half back to the Steady spam cue and fails loudly. Source pins at the end
-- prove the machinery is gone from hunter_guide.lua.
do
    -- A due clip-safe Aimed Shot (3 s cast + 0.03 latency vs a 3.06 ttl) fires
    -- with and without a window.
    eq(evaluate({ aimed_known = true, aimed_cast_seconds = 3.0, latency = 0.03,
        synced_duration = 4.06 }).action, "aimed",
        "H2 CUT: a due clip-safe Aimed fires without a window")
    eq(evaluate({ aimed_known = true, aimed_cast_seconds = 3.0, latency = 0.03,
        synced_duration = 4.06, lust_remaining = 30 }).action, "aimed",
        "H2 CUT: the same Aimed fires with a live window (no suppression)")
    -- A due clip-safe Multi-Shot (0.5 s cast vs a 1.06 ttl) fires with and
    -- without a window.
    eq(evaluate({ multi_known = true, latency = 0.03,
        synced_duration = 2.06 }).action, "multi",
        "H2 CUT: a due clip-safe Multi fires without a window")
    eq(evaluate({ multi_known = true, latency = 0.03,
        synced_duration = 2.06, lust_remaining = 30 }).action, "multi",
        "H2 CUT: the same Multi fires with a live window (no suppression)")
    -- The clip math still withholds unsafe casts, window or not: the 6a
    -- equality pair (3.56 safe, 3.55 withheld) under a live window.
    eq(evaluate({ aimed_known = true, steady_known = false, latency = 0.03,
        synced_duration = 3.56, lust_remaining = 30 }).action, "aimed",
        "H2 CUT: the 6a boundary still prompts under a live window when safe")
    eq(evaluate({ aimed_known = true, steady_known = false, latency = 0.03,
        synced_duration = 3.55, lust_remaining = 30 }).action, nil,
        "H2 CUT: the 6a boundary still withholds under a live window when unsafe")
    -- Every spelling is ignored now (never a gate).
    eq(evaluate({ multi_known = true, latency = 0.03,
        synced_duration = 1.56, lust_remaining = 0 }).action, "multi",
        "H2 CUT: a zero reading is not a gate")
    eq(evaluate({ multi_known = true, latency = 0.03,
        synced_duration = 1.56, lust_remaining = -5 }).action, "multi",
        "H2 CUT: a negative reading is not a gate")
    eq(evaluate({ multi_known = true, latency = 0.03,
        synced_duration = 1.56, lust_remaining = NONE }).action, "multi",
        "H2 CUT: an absent reading is not a gate")

    -- Every other rule is unchanged with a window present.
    eq(evaluate({ lust_remaining = 30, kc_known = true }).action, "kill_command",
        "H2 CUT: the TBC Kill Command priority is unchanged in the window")
    eq(evaluate({ lust_remaining = 30, hidden_window_start = 99.9,
        hidden_window_duration = 0.5 }).hold_text, "HOLD",
        "H2 CUT: the hidden-window hold is unchanged in the window")
    eq(evaluate({ lust_remaining = 30, steady_remaining = 0.3 }).hold_text, "RIDE",
        "H2 CUT: the live-cast ride is unchanged in the window")
    eq(evaluate({ lust_remaining = 30, target_in_range = 0 }).hold_text, "HOLD",
        "H2 CUT: the range gate is unchanged in the window")
    local saved = pure.family
    pure.family = "WRATH"
    eq(evaluate({ lust_remaining = 30 }).action, "steady",
        "H2 CUT: the Wrath filler is unchanged in the window")
    pure.family = saved

    -- Source pins: the suppression machinery is gone from the engine (a
    -- reintroduced branch fails here even before behaviour is read).
    do
        local f = assert(io.open(ROOT .. "hunter_guide.lua", "r"))
        local src = f:read("*a")
        f:close()
        check(src:find("lust_window", 1, true) == nil,
            "H2 CUT: no lust window local remains in hunter_guide.lua")
        check(src:find("lust_remaining", 1, true) == nil,
            "H2 CUT: no lust input read remains in hunter_guide.lua")
    end
end

-- Lock and Load, the Serpent guard, TBC Arcane (dormant) and the Sniper-range
-- bypass (bench/hunter_rotation_audit_2026-10-19.md findings 1, 2, 4, 5, 8).
do
    -- W-LnL (SV): the free Explosive ignores the cooldown, below the execute.
    local saved = pure.family
    pure.family = "WRATH"
    eq(evaluate({ lnl_ready = true, explosive_known = true,
        explosive_remaining_cd = 6 }).action, "explosive",
        "W-LnL: a live LnL window fires Explosive past its cooldown")
    eq(evaluate({ lnl_ready = true, explosive_known = true,
        explosive_remaining_cd = 6, killshot_known = true,
        target_hp_frac = 0.10 }).action, "kill_shot",
        "W-LnL: the execute still outranks the free Explosive")
    eq(evaluate({ lnl_ready = true, arcane_known = true,
        arcane_remaining_cd = 6 }).action, "arcane",
        "W-LnL MM: the free window spends Arcane with no Explosive")
    eq(evaluate({ lnl_ready = true, explosive_known = true,
        explosive_remaining_cd = 6, steady_remaining = 0.3 }).hold_text, "RIDE",
        "rule 1 outranks W-LnL: a live cast rides first")
    eq(evaluate({ explosive_known = true, explosive_remaining_cd = 6 }).action, "steady",
        "W-LnL: without the window the cooldown gates as before")
    eq(evaluate({ lnl_ready = true, explosive_known = true,
        explosive_remaining_cd = 6, target_in_range = 0 }).hold_text, "HOLD",
        "rule 2b outranks W-LnL: out of range still holds")

    -- The Serpent guard on W2: a known-down sting withholds the naked Chimera.
    eq(evaluate({ chimera_known = true, serpent_known = true,
        serpent_active = false }).action, "serpent",
        "serpent: a known-down sting withholds the naked Wrath Chimera (the upkeep asks instead)")
    eq(evaluate({ chimera_known = true, serpent_known = true,
        serpent_active = true }).action, "chimera",
        "serpent: a live sting keeps the Wrath Chimera prompt")
    eq(evaluate({ chimera_known = true }).action, "chimera",
        "serpent: unknown sting state allows the Chimera (never guess)")
    -- The knowledge alone must never silence the Chimera: the guard withholds the
    -- prompt only when the sting is KNOWN to be down (serpent_active == false), so
    -- an unknown debuff is "allow" (the header's own wording).
    eq(evaluate({ chimera_known = true, serpent_known = true }).action, "chimera",
        "serpent: a known sting with an unknown debuff keeps the Chimera prompt")
    eq(evaluate({ chimera_known = true, serpent_known = false }).action, "chimera",
        "serpent: an unknown sting keeps the Chimera prompt")
    -- The three-state feed (BS-3) has three states, and only one of them withholds:
    -- an EXPLICIT unknown (nil, the "the scan could not be trusted" state) must
    -- never silence the prompt either.
    eq(evaluate({ chimera_known = true, serpent_known = true,
        serpent_active = nil }).action, "chimera",
        "serpent: an explicit unknown debuff never withholds the Chimera prompt")
    pure.family = saved

    -- SoD-LnL plus the Serpent guard on 5b (ERA family).
    saved = pure.family
    pure.family = "ERA"
    eq(evaluate({ lnl_ready = true, aimed_known = true, aimed_remaining_cd = 6,
        synced_duration = 4.0 }).action, "aimed",
        "SoD-LnL: the free window fires Aimed past its cooldown")
    eq(evaluate({ lnl_ready = true, aimed_known = true, aimed_remaining_cd = 6,
        steady_known = false, aimed_cast_seconds = 3.0, latency = 0.03,
        synced_duration = 3.55 }).action, nil,
        "SoD-LnL: the free Aimed still needs its clip window")
    eq(evaluate({ lnl_ready = true, multi_known = true, multi_remaining_cd = 10,
        latency = 0.03, synced_duration = 1.56 }).action, "multi",
        "SoD-LnL: the free window fires Multi past its cooldown")
    eq(evaluate({ lnl_ready = true, chimera_known = true,
        synced_duration = 4.0 }).action, "chimera",
        "SoD-LnL: Chimera still outranks the free window")
    eq(evaluate({ chimera_known = true, serpent_known = true,
        serpent_active = false, aimed_known = true,
        synced_duration = 4.0 }).action, "aimed",
        "serpent: a known-down sting drops SoD Chimera to the Era weave")
    eq(evaluate({ chimera_known = true, aimed_known = true,
        synced_duration = 4.0 }).action, "chimera",
        "serpent: unknown sting state keeps the SoD Chimera prompt")
    eq(evaluate({ chimera_known = true, serpent_known = true, aimed_known = true,
        synced_duration = 4.0 }).action, "chimera",
        "serpent: a known sting with an unknown debuff keeps the SoD Chimera prompt")
    -- The family gates: forged LnL never prompts off its family.
    pure.family = nil
    eq(evaluate({ lnl_ready = true, explosive_known = true,
        explosive_remaining_cd = 6 }).action, "steady",
        "gates: a forged Wrath LnL never prompts off-Wrath")
    eq(evaluate({ lnl_ready = true, aimed_known = true, aimed_remaining_cd = 6,
        synced_duration = 4.0 }).action, "steady",
        "gates: a forged SoD LnL never prompts off-Era")
    pure.family = saved

    -- 5c TBC Arcane: dormant while the plug is false (ships false).
    eq(hg.TBC_ARCANE_ENABLED, false,
        "5c: the TBC Arcane plug ships false (no default-visible change)")
    saved = pure.family
    pure.family = "TBC"
    eq(evaluate({ arcane_known = true }).action, "steady",
        "5c: a due TBC Arcane stays silent while the plug is false")
    hg.TBC_ARCANE_ENABLED = true
    eq(evaluate({ arcane_known = true }).action, "arcane",
        "5c: with the plug on, a ready TBC Arcane prompts above the weave")
    eq(evaluate({ arcane_known = true, arcane_remaining_cd = 6 }).action, "steady",
        "5c: Arcane on cooldown falls through to the filler")
    eq(evaluate({ arcane_known = true, multi_known = true,
        latency = 0.03, synced_duration = 2.06 }).action, "arcane",
        "5c: the instant Arcane outranks a due Multi-Shot weave")
    eq(evaluate({ arcane_known = true, steady_remaining = 0.3 }).hold_text, "RIDE",
        "rule 1 outranks 5c: a live cast rides first")
    eq(evaluate({ arcane_known = true, hidden_window_start = 99.9,
        hidden_window_duration = 0.5 }).hold_text, "HOLD",
        "rule 2 outranks 5c: the window holds first")
    hg.TBC_ARCANE_ENABLED = false
    eq(evaluate({ arcane_known = true }).action, "steady",
        "5c: restoring false restores the silence")
    pure.family = nil
    hg.TBC_ARCANE_ENABLED = true
    eq(evaluate({ arcane_known = true }).action, "steady",
        "gates: a forged TBC Arcane never prompts off-TBC")
    hg.TBC_ARCANE_ENABLED = false
    pure.family = saved

    -- The Sniper-range bypass on rule 2b (sim TestSniperShotExtendsAutoShotRange).
    eq(evaluate({ target_in_range = 0 }).hold_text, "HOLD",
        "2b: out of range still holds with no buff (unknown-hides)")
    eq(evaluate({ target_in_range = 0,
        sniper_range_buff_active = false }).hold_text, "HOLD",
        "2b: an inactive buff still holds")
    eq(evaluate({ target_in_range = 0, sniper_range_buff_active = true }).action,
        "steady", "2b: a live Sniper buff bypasses the range hold")
    eq(evaluate({ target_in_range = 0, sniper_range_buff_active = true,
        steady_remaining = 0.3 }).hold_text, "RIDE",
        "rule 1 still outranks the bypass: a live cast rides")
end

-- Rule 6c: the Steady cooldown gate and the clip-safe boundary.
do
    eq(evaluate({ steady_remaining_cd = 0 }).action, "steady",
        "rule 6c: a zero cooldown reads ready")
    eq(evaluate({ steady_remaining_cd = -1 }).action, "steady",
        "rule 6c boundary: a negative cooldown reads ready (<= 0)")
    eq(evaluate({ steady_remaining_cd = 2 }).action, nil,
        "rule 6c: a running Steady cooldown withholds the prompt")
    eq(evaluate({ steady_remaining_cd = 2 }).hold, false,
        "rule 6c: the cooldown gate shows no hold when nothing is queued")

    -- is_cast_safe's equality boundary: latency 0.03 floors the buffer at 0.03, the cast
    -- is 1.5 s (remaining 1.53) and ttl must be exactly 1.06 for the equality.
    eq(evaluate({ latency = 0.03, synced_duration = 2.06 }).action, "steady",
        "rule 6c boundary: remaining == ttl + grace - latency is clip-safe (equality)")
    eq(evaluate({ latency = 0.03, synced_duration = 2.05 }).action, nil,
        "rule 6c boundary: one hundredth over the boundary withholds the prompt")
    eq(evaluate({ latency = 0.03, synced_duration = 2.05 }).hold, false,
        "rule 6c boundary: the withheld prompt shows no hold")

    -- synced_duration is the preferred cycle length (the cast bar's own basis).
    eq(evaluate({ latency = 0.03, synced_duration = 2.06, swing_speed = 5.0 }).action,
        "steady", "rule 6c: the synced duration times the cycle")
    eq(evaluate({ latency = 0.03, synced_duration = 2.05, swing_speed = 5.0 }).action,
        nil, "rule 6c: the synced duration wins over the swing speed (unsafe)")
    eq(evaluate({ latency = 0.03, synced_duration = 2.06, swing_speed = 0.05 }).action,
        "steady", "rule 6c: the synced duration wins over the swing speed (safe)")

    -- ends_at alone still times the cycle (the time_until_next_shot cooldown_end arm).
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, synced_duration = NONE,
        latency = 0.03, swing_ends_at = 101.06 }).action, "steady",
        "rule 6c: an ends_at-only cycle still times the clip check (equality)")
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, synced_duration = NONE,
        latency = 0.03, swing_ends_at = 101.05 }).action, nil,
        "rule 6c: and an unsafe ends_at-only cycle withholds the prompt")

    -- Absent ranged state (Retail, no weapon, no auto-repeat): no ttl, no prompt.
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE }).action, nil,
        "rule 6c: absent ranged state yields no action (never guess)")
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE, steady_remaining_cd = NONE }).hold, false,
        "rule 6c: absent ranged state shows no hold when nothing is queued")
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE, latency = 0 }).action, nil,
        "rule 6c: a zero latency cannot rescue an unknown cycle")

    -- A nil latency reads as zero: remaining 1.5 needs ttl 1.03 for the equality.
    eq(evaluate({ latency = NONE, synced_duration = 2.03 }).action, "steady",
        "rule 6c: a missing latency reads as zero (equality)")
    eq(evaluate({ latency = NONE, synced_duration = 2.02 }).action, nil,
        "rule 6c: a missing latency reads as zero (unsafe)")

    -- A missing cast time falls back to the frozen 1.5 s default.
    eq(evaluate({ steady_cast_seconds = NONE, latency = 0.03,
        synced_duration = 2.06 }).action, "steady",
        "rule 6c: a missing cast time falls back to 1.5 s")
    eq(evaluate({ steady_cast_seconds = NONE, latency = 0.03,
        synced_duration = 2.05 }).action, nil,
        "rule 6c: the fallback cast time still obeys the boundary")
    eq(evaluate({ steady_cast_seconds = 0.5, latency = 0.05,
        synced_duration = 1.2 }).action, "steady",
        "rule 6c: a shorter cast fits a nearly closed window")
end

-- Rule 7: the queued ride.
do
    eq(evaluate({ steady_remaining_cd = 3, raptor_strike_queued = true }).action, nil,
        "rule 7: a queued raptor with Steady on cooldown shows no action")
    eq(evaluate({ steady_remaining_cd = 3, raptor_strike_queued = true }).hold_text,
        "RIDE", "rule 7: the queued raptor reads RIDE")
    eq(evaluate({ steady_remaining_cd = 3, steady_shot_queued = true }).hold_text,
        "RIDE", "rule 7: a queued Steady Shot with Steady on cooldown reads RIDE")
    eq(evaluate({ swing_start = 99, synced_duration = 0.05, latency = 0.05,
        raptor_strike_queued = true }).hold_text, "RIDE",
        "rule 7: the ride survives an unsafe clip window")
    eq(evaluate({ raptor_strike_queued = true }).action, "steady",
        "rule 6c outranks a queue: Steady is the next press while the queue rides")
    eq(evaluate({ raptor_strike_queued = true }).hold, false,
        "rule 6c outranks a queue: no hold is shown over the steady prompt")
    eq(evaluate({ steady_shot_queued = true }).action, "steady",
        "rule 6c outranks the queued Steady state too")
    local out = evaluate({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE, raptor_strike_queued = true })
    eq(out.action, nil, "rule 7: a queue without a ranged cycle never produces an action")
    eq(out.hold, true, "rule 7: a queue without a ranged cycle still rides")
end

-- Rule 8 / frozen fields / nil-safety.
do
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE }).action, nil, "rule 8: no action")
    eq(evaluate({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE,
        synced_duration = NONE }).hold_text, nil, "rule 8: no hold text")

    local out = {
        action = "stale", hold = "stale", hold_text = "STALE", filler_slot = "stale",
        judge_slot = "stale", rotation_key = "stale", waiting_judgement = true,
        effective_weapon_speed = 9.9, steady_ratio = "stale",
    }
    hg.evaluate(inp({ steady_remaining_cd = 5 }), out)
    eq(out.action, nil, "a reused out table has action overwritten")
    eq(out.hold, false, "a reused out table has hold overwritten")
    eq(out.hold_text, nil, "a reused out table has hold_text overwritten")
    eq(out.filler_slot, nil, "a reused out table has filler_slot overwritten")
    eq(out.judge_slot, nil, "a reused out table has judge_slot overwritten")
    eq(out.rotation_key, nil, "a reused out table has rotation_key overwritten")
    eq(out.waiting_judgement, false, "a reused out table has waiting_judgement overwritten")
    eq(out.effective_weapon_speed, 3.0,
        "a reused out table has effective_weapon_speed recomputed")
    eq(out.steady_ratio, "french", "a reused out table has steady_ratio recomputed")

    local ok, err = pcall(hg.evaluate)
    check(ok, "evaluate with no arguments does not error (" .. tostring(err) .. ")")
    ok, err = pcall(hg.evaluate, nil, nil)
    check(ok, "evaluate(nil, nil) does not error (" .. tostring(err) .. ")")
    local fallback = hg.evaluate(inp({ steady_remaining = 0.5 }))
    check(type(fallback) == "table" and fallback.hold == true,
        "evaluate can allocate its own out table")

    local frozen = inp({})
    local before_now = frozen.now
    hg.evaluate(frozen, {})
    eq(frozen.now, before_now, "evaluate never writes back into its inputs")

    -- A flavor without the reused maths fails closed: no ttl, no steady prompt, no error.
    local saved_window = pure.hunter_window
    pure.hunter_window = nil
    local degraded = {}
    ok, err = pcall(hg.evaluate, inp({}), degraded)
    check(ok, "evaluate without hunter_window does not error (" .. tostring(err) .. ")")
    eq(degraded.action, nil, "without hunter_window the clip check fails closed")
    eq(degraded.hold, false, "without hunter_window nothing holds on clip grounds")
    pure.hunter_window = saved_window
    eq(hg.evaluate(inp({})).action, "steady", "restoring hunter_window restores the prompt")
end

--=========================================================================================
-- 1) Sandbox: compat + utils + nextaction_ui + hunter_window + hunter_guide + hunter
--=========================================================================================
local SPELL_INFOS = {
    -- The steady table resolves through get_family_spell_id, which picks the highest id
    -- the client knows; only the WotLK rank is on this fixture's "client". Multi-Shot
    -- rank 1 is known too, but the TBC family gate keeps its weave rule inert here
    -- (multi_known=false pins that below). Kill Command / Bestial Wrath / Rapid Fire
    -- stay unknown, pinning the rank-1 fallbacks.
    [49052] = { name = "Steady Shot", icon = "icon_steady", cast_ms = 1500 },
    [2973] = { name = "Raptor Strike", icon = "icon_raptor_r1", cast_ms = 0 },
    [48996] = { name = "Raptor Strike", icon = "icon_raptor", cast_ms = 0 },
    [2643] = { name = "Multi-Shot", icon = "icon_multi_r1", cast_ms = 500 },
}

local MODULES = { "compat.lua", "utils.lua", "guard.lua", "nextaction_ui.lua", "hunter_window.lua",
    "hunter_guide.lua", "classes/hunter.lua" }

local function make_fontstring()
    local f = { hidden = false }
    function f:SetPoint() end
    function f:SetJustifyH() end
    function f:SetShadowColor() end
    function f:SetShadowOffset() end
    function f:SetFont(path, size, flags) f.font = { path, size, flags }; return true end
    function f:SetText(text) f.text = text end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:Hide() f.hidden = true end
    function f:Show() f.hidden = false end
    function f:IsShown() return not f.hidden end
    return f
end

local function make_texture()
    local t = { hidden = true }
    function t:SetAllPoints() end
    function t:SetTexCoord(l, r, top, bottom) t.texcoord = { l, r, top, bottom } end
    function t:SetTexture(tex) t.texture = tex end
    function t:SetColorTexture() end
    function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
    return t
end

local function make_frame(name)
    local f = { name = name, shown = false }
    function f:SetSize(w, h) f.width, f.height = w, h end
    function f:SetPoint(point, anchor, rel_point, x, y)
        f.points = f.points or {}
        f.points[#f.points + 1] = { point, anchor, rel_point, x, y }
    end
    function f:ClearAllPoints() f.points = nil end
    function f:SetFrameStrata() end
    function f:SetClampedToScreen() end
    function f:RegisterForDrag() end
    function f:SetScript(event, fn)
        f.scripts = f.scripts or {}
        f.scripts[event] = fn
    end
    function f:GetScript(event) return f.scripts and f.scripts[event] or nil end
    function f:Show() f.shown = true end
    function f:Hide() f.shown = false end
    function f:IsShown() return f.shown end
    function f:SetAlpha(a) f.alpha = a end
    function f:SetScale(s) f.scale = s end
    function f:GetScale() return f.scale or 1 end
    function f:SetMovable(m) f.movable = m end
    function f:EnableMouse(m) f.mouse = m end
    function f:GetFrameLevel() return 5 end
    function f:SetFrameLevel(l) f.level = l end
    function f:GetName() return f.name end
    function f:GetCenter() return 50, 60 end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:CreateTexture() return make_texture() end
    function f:CreateFontString() return make_fontstring() end
    function f:SetBackdrop(backdrop) f.backdrop = backdrop end
    function f:SetBackdropBorderColor(r, g, b, a) f.border_color = { r, g, b, a } end
    function f:SetCooldown(start, duration)
        f.cooldown_sets = (f.cooldown_sets or 0) + 1
        f.cooldown_start, f.cooldown_duration = start, duration
    end
    function f:SetReverse(reverse) f.reverse = reverse end
    function f:SetHideCountdownNumbers(flag) f.hide_numbers = flag end
    function f:SetAllPoints() end
    return f
end

local function build(opts)
    opts = opts or {}
    local sb = {
        clock = 0,
        frames = 0,
        cooldowns = {},
        hide_spells = false,
        cast = nil,
        is_spell_in_range = nil,
        cast_reads = 0,
        range_queries = 0,
        cooldown_queries = 0,
        health = nil,
        health_max = nil,
        aura_queries = 0,
        player_auras = nil,
        target_auras = nil, -- [{ name, spell_id, count, duration, expiration }] for "target"
        target_aura_queries = 0,
    }

    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.WOW_PROJECT_ID = opts.project or 11
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.GetTimePreciseSec = function() return sb.clock end
    env.GetTime = function() return sb.clock end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.GetLocale = function() return "enUS" end
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", 30300 end
    env.UIParent = make_frame("UIParent")
    env.UIParent.GetCenter = function() return 0, 0 end
    env.CreateFrame = function(...)
        sb.frames = sb.frames + 1
        return make_frame(select(2, ...))
    end
    env.GetSpellInfo = function(spell)
        if sb.hide_spells then
            return nil
        end
        local info = (opts.spell_infos or SPELL_INFOS)[spell]
        if info then
            return info.name, nil, info.icon, info.cast_ms, 0, 0, spell
        end
        return nil
    end
    env.GetSpellCooldown = function(spell)
        sb.cooldown_queries = sb.cooldown_queries + 1
        local cd = sb.cooldowns[spell]
        if not cd and type(spell) == "string" then
            -- TBC queries by localized name (never a bare id): match the id
            -- whose spell data carries that name, mirroring the client's own
            -- mapping. Id-keyed fixtures keep working unchanged.
            for id, entry in pairs(sb.cooldowns) do
                if type(id) == "number" then
                    local info = (opts.spell_infos or SPELL_INFOS)[id]
                    if info and info.name == spell then
                        cd = entry
                        break
                    end
                end
            end
        end
        if cd then
            return cd[1], cd[2], 1, 1
        end
        return 0, 0, 0, 0
    end
    -- UnitCastingInfo's payload shape: name, text, texture, startTimeMs, endTimeMs,
    -- isTradeSkill, castID, notInterruptible, spellID (compat folds it into seconds).
    env.UnitCastingInfo = function()
        sb.cast_reads = sb.cast_reads + 1
        local cast = sb.cast
        if not cast then
            return nil
        end
        return cast.name, "", "icon", (cast.start or 0) * 1000, (cast["end"] or 0) * 1000,
            false, 1, false, cast.spell_id
    end
    env.UnitChannelInfo = function() return nil end
    -- Player auras for the H2 CUT pins (compat's scan_player_aura reads through
    -- this wrapper). The gather spends no scan on TBC or Era: the Lock and Load
    -- probe runs only on the families that have the talent (Wrath, and the SoD
    -- rune on the Era family), and the Bloodlust scan stays cut. Non-player
    -- units answer nil (the hunter badges' pet scan lives in hunter_ui, not in
    -- this sandbox) - except the target's HARMFUL debuffs, which the Serpent
    -- Sting target scan reads (BS-3).
    env.UnitAura = function(unit, index, filter)
        sb.aura_queries = sb.aura_queries + 1
        if unit == "target" and filter == "HARMFUL" then
            sb.target_aura_queries = sb.target_aura_queries + 1
            local debuff = sb.target_auras and sb.target_auras[index]
            if not debuff then
                return nil
            end
            return debuff.name, "", debuff.count or 0, "", debuff.duration, debuff.expiration,
                nil, nil, nil, debuff.spell_id
        end
        if unit ~= "player" then
            return nil
        end
        local aura = sb.player_auras and sb.player_auras[index]
        if not aura then
            return nil
        end
        return aura.name, "", aura.count or 0, "", aura.duration, aura.expiration,
            nil, nil, nil, aura.spell_id
    end
    env.IsCurrentSpell = function() return false end
    env.IsMounted = function() return false end
    env.IsAutoRepeatSpell = function() return true end
    -- Spell knowledge for the Wrath spec detector (Chimera = MM, Explosive = SV)
    -- and the SoD rune detector: opts.known_spells maps id -> true, defaulting
    -- to "nothing learned" so the old fixtures resolve nothing new.
    env.IsSpellKnown = function(spell)
        local known = opts.known_spells
        return known ~= nil and known[spell] == true
    end
    -- Target health for the Wrath Kill Shot execute read (nil = unknown).
    env.UnitHealth = function() return sb.health end
    env.UnitHealthMax = function() return sb.health_max end
    -- The target unit's existence (the Serpent Sting scan's "the scan ran" proof:
    -- no target means there is nothing to scan, so the debuff stays unknown).
    if opts.unit_exists ~= nil then
        env.UnitExists = opts.unit_exists
    end
    env.IsSpellInRange = function()
        sb.range_queries = sb.range_queries + 1
        return sb.is_spell_in_range
    end

    local ST = {
        HUNTER = {},
        player_class = "HUNTER",
        interfaces_are_initialised = true,
        in_combat = false,
        player_guid = "Player-1",
        db = { profile = { enabled = true } },
    }
    local class_db = {
        -- The real HUNTER defaults (config_presets.lua), so a wrong colour is a module
        -- bug and not a fixture bug. The guide keys are the new ones; enabled=true here
        -- so the display half can be exercised (the shipped default false is pinned by
        -- the text parity section below).
        enable_raptor_strike_color = true,
        raptor_strike_color = { 207, 58, 83, 1.0 },
        enable_steady_shot_color = false,
        steady_shot_color = { 211, 145, 12, 1.0 },
        hunter_cast_bar_enabled = true,
        hunter_cast_bar_height = 15,
        hunter_cast_bar_color = { 0.35, 0.65, 0.95, 1.0 },
        hunter_range_helper_enabled = true,
        hunter_rapid_fire_bar_enabled = true,
        hunter_aspect_icon_enabled = true,
        mainhand = { border_width = 2 },
        nextaction_enabled = true,
        nextaction_locked = true,
        nextaction_visibility_key = "in_combat",
        nextaction_icon_size = 45,
        nextaction_x = 0,
        nextaction_y = -180,
    }
    function ST.get_class_table() return class_db end
    function ST.get_hand_table() return class_db.mainhand end
    function ST.get_visuals_frame() return nil end
    function ST.get_bar_visuals_width_and_height() return 100, 20 end
    function ST.get_bar_frame() return nil end
    function ST.convert_color(_, t, new_alpha)
        local r, g, b, a = unpack(t)
        a = new_alpha or a
        return r / 255, g / 255, b / 255, a
    end
    function ST.set_bar_color() return true end

    local LCG = {}
    function LCG.PixelGlow_Start() end
    function LCG.PixelGlow_Stop() end
    local LSM = {}
    function LSM.Fetch(_, mediatype)
        if mediatype == "border" then return "border_tex" end
        if mediatype == "font" then return "Fonts\\FRIZQT__.TTF" end
        return nil
    end
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        elseif major == "LibCustomGlow-1.0" then
            return LCG
        elseif major == "LibSharedMedia-3.0" then
            return LSM
        end
        return {}
    end

    local st = {}
    local modules = opts.modules or MODULES
    for i = 1, #modules do
        local chunk = assert(loadfile(ROOT .. modules[i]))
        setfenv(chunk, env)
        chunk("SwedgeTimer", st)
        -- Class files register their body as a loader (operator order 2026-10-21:
        -- only the selected class executes). This sandbox activates the class it
        -- loads, exactly as main.lua does at init.
        local class = modules[i]:match("classes/(%a+)%.lua")
        if class and type(st.class_loaders) == "table"
            and type(st.class_loaders[class:upper()]) == "function" then
            st.class_loaders[class:upper()]()
        end
    end

    sb.env, sb.st, sb.ST, sb.class_db = env, st, ST, class_db
    function sb.advance(dt) sb.clock = sb.clock + dt end
    return sb
end

--=========================================================================================
-- 2) The provider through the real modules: contract shape, post_init, gather
--=========================================================================================
local sandbox = build()
local ST, st = sandbox.ST, sandbox.st
local class_db = sandbox.class_db

check(type(st.hunter_guide) == "table", "the provider sandbox loads the pure engine")
check(type(st.hunter_window) == "table", "the provider sandbox loads the window maths")
check(type(ST.HUNTER.guide) == "table", "classes/hunter.lua defines ST.HUNTER.guide")
check(type(ST.HUNTER.guide.gather) == "function", "the hunter guide has gather")
check(type(ST.HUNTER.guide.evaluate) == "function", "the hunter guide has evaluate")

-- post_init resolves the rank icons and builds the frame through the real hook.
-- The default sandbox is a Wrath client (project 11) whose spell data carries
-- Steady Shot only: the Wrath six-slot set with five dark prompt slots.
ST.in_combat = true
ST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
ST.HUNTER.post_init(ST)
local ui = st.nextaction_ui
check(ui.frame ~= nil, "post_init builds the guide frame through the real hook")
check(ui.inert ~= true, "the hunter provider is live")
eq(ui.get_provider(ST), ST.HUNTER.guide, "the hunter guide resolves as the frame's provider")

local slots = ST.HUNTER.guide.slots
eq(#slots, 13, "the Wrath slot set covers the APL's whole spine (six arms + seven utility rows)")
eq(slots[1].key, "kill_shot", "Wrath slot 1 is kill_shot (the execute)")
eq(slots[2].key, "chimera", "Wrath slot 2 is chimera (the MM signature)")
eq(slots[3].key, "explosive", "Wrath slot 3 is explosive (the SV signature)")
eq(slots[4].key, "aimed", "Wrath slot 4 is aimed (the instant tier)")
eq(slots[5].key, "arcane", "Wrath slot 5 is arcane (the MM early-phase tier)")
eq(slots[6].key, "steady", "Wrath slot 6 is steady (the demoted filler)")
eq(slots[1].cooldown_key, nil, "the kill_shot slot is a swipe-less prompt")
eq(slots[2].cooldown_key, nil, "the chimera slot is a swipe-less prompt")
eq(slots[3].cooldown_key, nil, "the explosive slot is a swipe-less prompt")
eq(slots[4].cooldown_key, nil, "the Wrath aimed slot carries no swipe (instant)")
eq(slots[5].cooldown_key, nil, "the arcane slot is a swipe-less prompt")
eq(slots[6].cooldown_key, "steady", "the steady slot carries its live-cast swipe key")
eq(slots[6].swipe_duration, 1.5, "the steady slot carries the cast-length swipe fallback")
eq(slots[6].swipe_always, true, "the steady swipe stays armed while the RIDE hold fades the icon")
eq(slots[1].spell_id, 53351, "an unlearned Kill Shot keeps the rank-1 fallback")
eq(slots[2].spell_id, 53209, "an unlearned Chimera keeps the rank-1 fallback")
eq(slots[3].spell_id, 53301, "an unlearned Explosive keeps the rank-1 fallback")
eq(slots[4].spell_id, 49050, "an unlearned Wrath Aimed keeps the rank-1 fallback")
eq(slots[5].spell_id, 49045, "an unlearned Arcane keeps the rank-1 fallback")
eq(slots[6].spell_id, 49052, "post_init resolved steady to the client's current rank")
eq(ST.HUNTER.guide.labels.next_action, "Next action:", "labels.next_action is the default")
eq(ST.HUNTER.guide.labels.hold, "HOLD", "labels.hold is the default")
eq(ST.HUNTER.guide.labels.ride, "RIDE", "labels.ride is the default")
eq(ST.HUNTER.guide.rotation_key, nil, "no rotation text source is declared")
eq(ST.HUNTER.guide.rotation_names, nil, "no rotation name map is declared")

-- The frame: one icon per slot, in order, showing the resolved rank textures.
eq(#ui.icons, 13, "the frame holds one icon per slot")
eq(sandbox.frames, 29, "frame count: group + hold + 13 icons/borders + 1 cooldown")
for i = 1, #slots do
    eq(ui.icons[i].slot, slots[i], "icon " .. i .. " follows the slot declaration order")
end
eq(ui.icons[1].icon.texture.texture, nil,
    "an unresolvable Kill Shot icon simply stays texture-less (no error)")
eq(ui.icons[6].icon.texture.texture, "icon_steady",
    "the steady icon shows the current rank's texture")
eq(ui.frame.label.text, "Next action:", "the label carries the default caption")
eq(ui.icons[6].remaining_key, "steady_remaining", "the swipe field names derive from the key")
eq(ui.icons[6].duration_key, "steady_duration", "the swipe length field derives from the key")
eq(ui.icons[1].remaining_key, nil, "the kill_shot slot carries no swipe fields")
eq(ui.icons[4].remaining_key, nil, "the Wrath aimed slot carries no swipe fields")
eq(ui.icons[1].glow_key, nil, "the hunter slots carry no glow")

-- Every possible action output names a declared slot (through the real provider).
do
    local provider = ST.HUNTER.guide
    local function action_of(overrides)
        local inputs = { now = 100, swing_start = 99, swing_speed = 3.0,
            swing_ends_at = 102, latency = 0.05, steady_cast_seconds = 1.5,
            steady_known = true, aimed_known = false, aimed_cast_seconds = 3.0 }
        for k, v in pairs(overrides or {}) do
            if v == NONE then
                inputs[k] = nil
            else
                inputs[k] = v
            end
        end
        local out = {}
        provider.evaluate(inputs, out)
        return out.action
    end
    local actions = {
        action_of({}),
        action_of({ steady_remaining = 0.4 }),
        action_of({ swing_start = NONE, swing_speed = NONE, swing_ends_at = NONE }),
        action_of({ killshot_known = true, target_hp_frac = 0.10 }),
        action_of({ chimera_known = true }),
        action_of({ explosive_known = true }),
        action_of({ wrath_aimed_known = true }),
        action_of({ arcane_known = true }),
        action_of({ arcane_known = true, explosive_known = true }),
    }
    eq(actions[1], "steady", "the provider delegates to the pure engine (steady filler)")
    eq(actions[2], nil, "the provider delegates to the pure engine (ride, no action)")
    eq(actions[3], "steady", "the Wrath filler needs no ranged cycle (never guess)")
    eq(actions[4], "kill_shot", "the provider delegates to the pure engine (execute)")
    eq(actions[5], "chimera", "the provider delegates to the pure engine (MM)")
    eq(actions[6], "explosive", "the provider delegates to the pure engine (SV)")
    eq(actions[7], "aimed", "the provider delegates to the pure engine (aimed)")
    eq(actions[8], "arcane", "the provider delegates to the pure engine (arcane)")
    eq(actions[9], "explosive",
        "the SV shared cooldown suppresses Arcane through the real provider")
    local all_resolve = true
    for i = 1, #actions do
        if actions[i] ~= nil and ui.slot_index[actions[i]] == nil then
            all_resolve = false
        end
    end
    check(all_resolve, "every action the engine can return names a declared slot")
    local slots_have_keys = true
    for i = 1, #slots do
        if ui.slot_index[slots[i].key] == nil then
            slots_have_keys = false
        end
    end
    check(slots_have_keys, "every declared slot key is frame-addressable")
end

-- The gather into the caller-owned reused table.
sandbox.clock = 100
ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, synced_duration = nil,
    hidden_window_start = nil, hidden_window_duration = nil, auto_repeat_active = true }
ST.latency = { world_ms = 50, calibrated_world_ms = 999 }
ST.raptor_strike_queued = true
ST.steady_shot_queued = false
sandbox.cast = { name = "Steady Shot", spell_id = 49052, start = 99.5, ["end"] = 100.8 }
sandbox.is_spell_in_range = 1
sandbox.cooldowns = { [49052] = { 100, 6 } }
sandbox.cast_reads = 0
sandbox.range_queries = 0
sandbox.cooldown_queries = 0

local gathered_target = {}
local gathered = ST.HUNTER.guide.gather(ST, gathered_target)
eq(gathered, gathered_target, "gather writes into and returns the caller's table")
eq(gathered.now, 100, "gather: now from api.get_time")
eq(gathered.swing_start, 99.0, "gather: swing_start")
eq(gathered.swing_speed, 3.0, "gather: swing_speed")
eq(gathered.swing_ends_at, 102.0, "gather: swing_ends_at")
eq(gathered.synced_duration, nil, "gather: an absent synced duration stays nil")
eq(gathered.auto_repeat_active, true, "gather: auto_repeat_active")
near(gathered.latency, 0.999, 1e-9,
    "gather: the calibrated latency wins when usable (never the twist calibration)")
near(gathered.hidden_window_start, 100.501, 1e-9,
    "gather: the hidden window is recomputed from the live cycle")
near(gathered.hidden_window_duration, 1.499, 1e-9,
    "gather: the window width is the base cast window plus the compensated latency")
eq(gathered.raptor_strike_queued, true, "gather: raptor_strike_queued")
eq(gathered.steady_shot_queued, false, "gather: steady_shot_queued")
eq(gathered.casting, true, "gather: the live cast state")
near(gathered.steady_remaining, 0.8, 1e-9, "gather: the live Steady cast's remaining seconds")
near(gathered.steady_duration, 1.3, 1e-9, "gather: the live Steady cast's full length")
eq(gathered.steady_cast_seconds, 1.5, "gather: the client-reported Steady cast time")
near(gathered.steady_remaining_cd, 6, 1e-9, "gather: the real Steady cooldown")
eq(gathered.target_in_range, 1, "gather: the ranged range probe")
eq(gathered.multi_remaining, nil, "gather: no live Multi cast means no multi remaining")
eq(gathered.multi_cast_seconds, 0.5, "gather: the client-reported Multi cast time")
eq(gathered.multi_known, false,
    "gather: Multi known by the client but gated off outside TBC")
eq(gathered.steady_known, true,
    "gather: the client's Steady rank is known")
eq(gathered.aimed_known, false,
    "gather: the Era Aimed rule stays down off-Era")
eq(gathered.aimed_cast_seconds, nil,
    "gather: no Aimed cast time is read off-Era")
eq(gathered.aimed_remaining, nil,
    "gather: no live Aimed cast is tracked off-Era")
eq(gathered.aimed_duration, nil,
    "gather: no Aimed swipe length is tracked off-Era")
eq(gathered.aimed_remaining_cd, nil,
    "gather: no Aimed cooldown is read off-Era")
eq(gathered.multi_remaining_cd, 0, "gather: the Multi cooldown reads idle")
eq(gathered.kc_known, false, "gather: Kill Command unknown and off-TBC")
eq(gathered.kc_remaining_cd, 0, "gather: the Kill Command cooldown reads idle")
eq(gathered.bw_known, false, "gather: Bestial Wrath unknown and off-TBC")
eq(gathered.bw_remaining_cd, 0, "gather: the Bestial Wrath cooldown reads idle")
eq(gathered.rf_known, false, "gather: Rapid Fire unknown and off-TBC")
eq(gathered.rf_remaining_cd, 0, "gather: the Rapid Fire cooldown reads idle")
eq(gathered.killshot_known, false, "gather: an unlearned Kill Shot never prompts")
eq(gathered.killshot_remaining_cd, 0, "gather: no Kill Shot rank reads idle (no query spent)")
eq(gathered.target_hp_frac, nil, "gather: no Kill Shot rank means no health probe either")
eq(gathered.chimera_known, false, "gather: an unlearned Chimera never prompts (MM detector down)")
eq(gathered.chimera_remaining_cd, 0, "gather: no Chimera rank reads idle (no query spent)")
eq(gathered.explosive_known, false, "gather: an unlearned Explosive never prompts (SV detector down)")
eq(gathered.explosive_remaining_cd, 0, "gather: no Explosive rank reads idle (no query spent)")
eq(gathered.wrath_aimed_known, false, "gather: an unlearned Wrath Aimed never prompts")
eq(gathered.wrath_aimed_remaining_cd, 0, "gather: no Wrath Aimed rank reads idle (no query spent)")
eq(gathered.arcane_known, false, "gather: an unlearned Arcane never prompts")
eq(gathered.arcane_remaining_cd, 0, "gather: no Arcane rank reads idle (no query spent)")
eq(gathered.lnl_ready, nil, "gather: LnL writes nil when the player carries no proc aura")
eq(gathered.serpent_known, nil, "gather: Serpent known writes nil (no known rank)")
eq(gathered.serpent_active, nil, "gather: Serpent active writes nil (no known rank, no scan)")
eq(gathered.sniper_range_buff_active, nil, "gather: the Sniper buff writes nil (no source)")
-- The Lock and Load probe is scoped to the families that have the talent: a
-- TBC or Era client spends no aura scan on it (the audit's H-05 closure).
do
    local tbc_lnl = build({ project = 5 })
    tbc_lnl.ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0 }
    tbc_lnl.clock = 100
    tbc_lnl.player_auras = { { name = "Lock and Load", spell_id = 56344,
        duration = 22, expiration = 120 } }
    tbc_lnl.aura_queries = 0
    local tbc_gathered = tbc_lnl.ST.HUNTER.gather_guide_inputs(tbc_lnl.ST, {})
    eq(tbc_gathered.lnl_ready, nil, "gather: a TBC client reads no Lock and Load window")
    eq(tbc_lnl.aura_queries, 0, "gather: a TBC client spends no Lock and Load scan")
    local era_lnl = build({ project = 2 })
    era_lnl.ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0 }
    era_lnl.clock = 100
    era_lnl.player_auras = { { name = "Lock and Load", spell_id = 415413,
        duration = 20, expiration = 120 } }
    era_lnl.aura_queries = 0
    local era_gathered = era_lnl.ST.HUNTER.gather_guide_inputs(era_lnl.ST, {})
    eq(era_gathered.lnl_ready, nil, "gather: an Era client reads no Lock and Load window")
    eq(era_lnl.aura_queries, 0, "gather: an Era client spends no Lock and Load scan")
end

-- Id-less live Steady Shot (R1 name-carrying payloads): the gather detects the
-- cast through the client's own localized names, Era and TBC separately, while
-- a cold spell cache hides (unknown, never a guess).
do
    local era = build({ project = 2, spell_infos = {
        [56641] = { name = "Steady Shot", icon = "icon_steady", cast_ms = 1500 },
    } })
    era.ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0 }
    era.clock = 100
    era.cast = { name = "Steady Shot", start = 99.5, ["end"] = 100.8 }
    local era_gathered = era.ST.HUNTER.gather_guide_inputs(era.ST, {})
    near(era_gathered.steady_remaining, 0.8, 1e-9,
        "gather: an id-less Era Steady cast still reports its remaining seconds")
    near(era_gathered.steady_duration, 1.3, 1e-9,
        "gather: an id-less Era Steady cast still reports its full length")
    local tbc = build({ project = 5, spell_infos = {
        [34120] = { name = "Steady Shot", icon = "icon_steady", cast_ms = 1500 },
    } })
    tbc.ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0 }
    tbc.clock = 100
    tbc.cast = { name = "Steady Shot", start = 99.5, ["end"] = 100.8 }
    local tbc_gathered = tbc.ST.HUNTER.gather_guide_inputs(tbc.ST, {})
    near(tbc_gathered.steady_remaining, 0.8, 1e-9,
        "gather: an id-less TBC Steady cast still reports its remaining seconds")
    near(tbc_gathered.steady_duration, 1.3, 1e-9,
        "gather: an id-less TBC Steady cast still reports its full length")
    -- Cold spell cache: no name set can build, so the id-less cast hides.
    local cold = build({ project = 5 })
    cold.hide_spells = true
    cold.ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0 }
    cold.clock = 100
    cold.cast = { name = "Steady Shot", start = 99.5, ["end"] = 100.8 }
    local cold_gathered = cold.ST.HUNTER.gather_guide_inputs(cold.ST, {})
    eq(cold_gathered.casting, true, "gather: a cold cache still reports casting")
    eq(cold_gathered.steady_remaining, nil,
        "gather: a cold cache hides the id-less Steady cast (unknown, never a guess)")
end

-- The Serpent Sting target-debuff feed, end to end (BS-3): the gather's three-state
-- scan reaches the naked-Chimera guard, and the guard's semantics are unchanged -
-- only a KNOWN-down sting withholds the prompt, an unknown never does.
do
    -- A Wrath MM client that knows both the Chimera Shot and a Serpent Sting rank.
    local serpent_infos = {}
    for id, info in pairs(SPELL_INFOS) do serpent_infos[id] = info end
    serpent_infos[53209] = { name = "Chimera Shot", icon = "icon_chimera", cast_ms = 0 }
    serpent_infos[13554] = { name = "Serpent Sting", icon = "icon_serpent", cast_ms = 0 }
    local function mm_client(target_auras)
        local sb = build({
            spell_infos = serpent_infos,
            known_spells = { [53209] = true, [13554] = true },
            unit_exists = function() return true end,
        })
        sb.clock = 100
        sb.ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0 }
        sb.target_auras = target_auras
        sb.ST.HUNTER.post_init(sb.ST)
        return sb
    end

    -- The sting is up on the target: the Chimera prompt fires.
    local up = mm_client({ { name = "Serpent Sting", spell_id = 13554, count = 1,
        duration = 16, expiration = 116 } })
    local up_inputs = up.ST.HUNTER.gather_guide_inputs(up.ST, {})
    eq(up_inputs.serpent_known, true, "serpent: the client knows a Serpent rank")
    eq(up_inputs.chimera_known, true, "serpent: the client knows the Chimera Shot")
    eq(up_inputs.serpent_active, true, "serpent: the sting on the target reads as up")
    eq(up.st.hunter_guide.evaluate(up_inputs, {}).action, "chimera",
        "serpent: a live sting keeps the Chimera prompt")

    -- The sting is not on the target: the prompt is withheld (a known-down sting).
    local down = mm_client({ { name = "Corruption", spell_id = 11563, count = 1,
        duration = 6, expiration = 106 } })
    local down_inputs = down.ST.HUNTER.gather_guide_inputs(down.ST, {})
    eq(down_inputs.serpent_active, false, "serpent: a target without the sting reads as down")
    eq(down.st.hunter_guide.evaluate(down_inputs, {}).action, "serpent",
        "serpent: a known-down sting withholds the naked Chimera prompt (the upkeep asks instead)")

    -- No target: the debuff is unknown, so the prompt fires (never guess).
    local no_target = mm_client(nil)
    no_target.env.UnitExists = function() return false end
    local unknown_inputs = no_target.ST.HUNTER.gather_guide_inputs(no_target.ST, {})
    eq(unknown_inputs.serpent_active, nil, "serpent: no target leaves the debuff unknown")
    eq(no_target.st.hunter_guide.evaluate(unknown_inputs, {}).action, "chimera",
        "serpent: an unknown debuff never withholds the Chimera prompt")
end
eq(sandbox.cast_reads, 1, "gather: the live cast is read once per call")
eq(sandbox.range_queries, 1, "gather: the range probe is one client call per call")
eq(sandbox.cooldown_queries, 5, "gather: one cooldown read per prompt (steady/kc/bw/rf/multi)")

-- Every slot's cooldown_key resolves into the gathered inputs.
do
    local cooldowns_resolve = true
    for i = 1, #slots do
        local key = slots[i].cooldown_key
        if key and (gathered[key .. "_remaining"] == nil
            and gathered[key .. "_duration"] == nil) then
            cooldowns_resolve = false
        end
    end
    check(cooldowns_resolve, "every slot cooldown_key resolves into the gathered inputs")
end

-- The compensation fallback ladder: an unusable calibrated reading falls back to
-- raw, and an answerless client reads zero (never a guess, never the twist keys).
ST.latency = { world_ms = 50, calibrated_world_ms = nil }
near(ST.HUNTER.guide.gather(ST, gathered_target).latency, 0.05, 1e-9,
    "gather: a missing calibrated reading falls back to raw world latency")
ST.latency = { world_ms = 50, calibrated_world_ms = 0/0 }
near(ST.HUNTER.guide.gather(ST, gathered_target).latency, 0.05, 1e-9,
    "gather: a NaN calibrated reading falls back to raw world latency")
ST.latency = {}
eq(ST.HUNTER.guide.gather(ST, gathered_target).latency, 0,
    "gather: an answerless latency client reads zero")
ST.latency = { world_ms = 50 }

-- A stale cache (a previous cycle's end) loses to the live recompute and is cleared,
-- so Steady/Auto never hold on a dead window. Fixture: clock 100, live cycle
-- [99, 102]; the cache ends at 100.9, off the live end.
ST.ranged.hidden_window_start = 100.4
ST.ranged.hidden_window_duration = 0.5
local stale_gather = ST.HUNTER.guide.gather(ST, gathered_target)
near(stale_gather.hidden_window_start, 101.45, 1e-9,
    "gather: a stale cache loses to the live-cycle recompute")
near(stale_gather.hidden_window_duration, 0.55, 1e-9,
    "gather: the recomputed width follows the live cycle")
eq(ST.ranged.hidden_window_start, nil,
    "gather: the stale cache is cleared on the ranged state")
eq(ST.ranged.hidden_window_duration, nil,
    "gather: the stale cache width is cleared on the ranged state")

-- The sharper half: `now` sits INSIDE the stale cache, so an inside-only check
-- would still ride it. The cache [99.7, 100.2] ends off the live end (102) and
-- must lose the same way.
ST.ranged.hidden_window_start = 99.7
ST.ranged.hidden_window_duration = 0.5
local stale_inside_gather = ST.HUNTER.guide.gather(ST, gathered_target)
near(stale_inside_gather.hidden_window_start, 101.45, 1e-9,
    "gather: an inside-but-stale cache loses to the live-cycle recompute")
near(stale_inside_gather.hidden_window_duration, 0.55, 1e-9,
    "gather: the recompute wins over an inside-but-stale cache")
eq(ST.ranged.hidden_window_start, nil,
    "gather: the inside-but-stale cache is cleared on the ranged state")
eq(ST.ranged.hidden_window_duration, nil,
    "gather: the inside-but-stale width is cleared on the ranged state")

-- A current-cycle cache (its end on the live cycle's end, now inside) is reused
-- verbatim instead of recomputed: live end 100.5, cache [100, 100.5], now 100.
ST.ranged.start = 97.5
ST.ranged.hidden_window_start = 100.0
ST.ranged.hidden_window_duration = 0.5
local cached_gather = ST.HUNTER.guide.gather(ST, gathered_target)
eq(cached_gather.hidden_window_start, 100.0,
    "gather: a current-cycle cache wins over a recompute")
eq(cached_gather.hidden_window_duration, 0.5,
    "gather: the cached length is reused verbatim")
ST.ranged.start = 99.0
ST.ranged.hidden_window_start = nil
ST.ranged.hidden_window_duration = nil

-- Stale fields are overwritten on the reused table; a cleared state reads nil/0.
ST.ranged = { start = 50.0, speed = 2.0, ends_at = 52.0, synced_duration = 2.0,
    auto_repeat_active = false }
ST.raptor_strike_queued = false
sandbox.cast = nil
sandbox.cooldowns = {}
sandbox.is_spell_in_range = nil
local gathered2 = ST.HUNTER.guide.gather(ST, gathered_target)
eq(gathered2, gathered_target, "the reused table is the same table")
eq(gathered2.raptor_strike_queued, false, "the queue flag is overwritten, not stale")
eq(gathered2.auto_repeat_active, false, "the auto-repeat flag is overwritten, not stale")
eq(gathered2.synced_duration, 2.0, "gather: the synced duration is read when present")
eq(gathered2.casting, false, "the cleared cast reads false")
eq(gathered2.steady_remaining, nil, "the cleared cast removes the stale remaining")
eq(gathered2.steady_duration, nil, "the cleared cast removes the stale duration")
eq(gathered2.steady_remaining_cd, 0, "the dropped cooldown reads as 0")
eq(gathered2.target_in_range, nil, "an answerless range probe stays nil (unknown)")
eq(gathered2.multi_remaining, nil, "the cleared cast removes the stale multi remaining")
eq(gathered2.multi_known, false, "the TBC gate stays down off-TBC")
eq(gathered2.steady_known, true, "the Steady known-rank gate stays up (client knows it)")
eq(gathered2.aimed_known, false, "the Era Aimed gate stays down off-Era")
eq(gathered2.aimed_cast_seconds, nil, "the Aimed cast time stays unread off-Era")
eq(gathered2.aimed_remaining, nil, "the cleared cast removes the stale aimed remaining")
eq(gathered2.aimed_duration, nil, "the cleared cast removes the stale aimed duration")
eq(gathered2.aimed_remaining_cd, nil, "the Aimed cooldown stays unread off-Era")
eq(gathered2.kc_known, false, "the KC gate stays down off-TBC")
eq(gathered2.bw_known, false, "the BW gate stays down off-TBC")
eq(gathered2.rf_known, false, "the RF gate stays down off-TBC")
eq(gathered2.killshot_known, false, "the Kill Shot gate stays down unlearned")
eq(gathered2.target_hp_frac, nil, "the cleared execute read stays nil")
eq(gathered2.chimera_known, false, "the Chimera gate stays down unlearned")
eq(gathered2.explosive_known, false, "the Explosive gate stays down unlearned")
eq(gathered2.wrath_aimed_known, false, "the Wrath Aimed gate stays down unlearned")
eq(gathered2.arcane_known, false, "the Arcane gate stays down unlearned")
eq(gathered2.lnl_ready, nil, "the LnL window stays nil on the reused table")
eq(gathered2.serpent_known, nil, "the Serpent known stays nil on the reused table")
eq(gathered2.serpent_active, nil, "the Serpent active stays nil on the reused table")
eq(gathered2.sniper_range_buff_active, nil, "the Sniper buff stays nil on the reused table")
near(gathered2.hidden_window_start, 51.45, 1e-9,
    "the recomputed window follows the new cycle")

-- The GCD echo is filtered (1.51 s boundary) and a real cooldown reads through.
sandbox.cooldowns = { [49052] = { 100, 1.5 } }
eq(ST.HUNTER.guide.gather(ST, gathered_target).steady_remaining_cd, 0,
    "the ~1.5 s GCD echo is filtered")
sandbox.cooldowns = { [49052] = { 100, 1.51 } }
eq(ST.HUNTER.guide.gather(ST, gathered_target).steady_remaining_cd, 0,
    "the GCD echo filter boundary at 1.51 s")
sandbox.cooldowns = { [49052] = { 100, 1.52 } }
near(ST.HUNTER.guide.gather(ST, gathered_target).steady_remaining_cd, 1.52, 1e-9,
    "a cooldown just past the echo reads through")
sandbox.cooldowns = {}

-- Direct calls without an out table use the module's own reused table.
local own = ST.HUNTER.gather_guide_inputs(ST)
eq(own, ST.HUNTER.guide_inputs, "gather without an out table uses the module's reused table")

-- The rank-1 fallback when nothing resolves on the client.
do
    local fallback = build()
    fallback.hide_spells = true
    fallback.ST.HUNTER.post_init(fallback.ST)
    local fslots = fallback.ST.HUNTER.guide.slots
    eq(#fslots, 13, "the fallback client declares the Wrath spine (project 11)")
    eq(fslots[1].spell_id, 53351, "an unlearned Kill Shot keeps the rank-1 fallback")
    eq(fslots[2].spell_id, 53209, "an unlearned Chimera keeps the rank-1 fallback")
    eq(fslots[3].spell_id, 53301, "an unlearned Explosive keeps the rank-1 fallback")
    eq(fslots[4].spell_id, 49050, "an unlearned Wrath Aimed keeps the rank-1 fallback")
    eq(fslots[5].spell_id, 49045, "an unlearned Arcane keeps the rank-1 fallback")
    eq(fslots[6].spell_id, 49052, "an unresolved Steady rank keeps the family's fallback id")
    local fui = fallback.st.nextaction_ui
    eq(fui.icons[1].icon.texture.texture, nil,
        "an unresolvable icon simply stays texture-less (no error)")
    fallback.ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0 }
    fallback.ST.latency = { world_ms = 50 }
    local fgathered = fallback.ST.HUNTER.guide.gather(fallback.ST, {})
    eq(fgathered.steady_cast_seconds, 1.5, "an unreadable cast time falls back to 1.5 s")
    eq(fgathered.steady_cast_seconds, fallback.ST.HUNTER.CAST_TIME_FALLBACK.steady.WRATH,
        "the Steady fallback rides the per-client table on Wrath")
    eq(fgathered.steady_remaining_cd, 0, "an unresolved rank reads no cooldown")
    eq(fgathered.multi_cast_seconds, 0.5, "an unreadable Multi cast time falls back to 0.5 s")
    eq(fgathered.multi_cast_seconds, fallback.ST.HUNTER.CAST_TIME_FALLBACK.multi.WRATH,
        "the Multi fallback rides the per-client table on Wrath")
    eq(fgathered.multi_known, false, "an unresolved Multi rank never weaves")
    eq(fgathered.kc_known, false, "an unresolved Kill Command never prompts")
    eq(fgathered.bw_known, false, "an unresolved Bestial Wrath never prompts")
    eq(fgathered.rf_known, false, "an unresolved Rapid Fire never prompts")
    eq(fgathered.killshot_known, false, "an unlearned Kill Shot never prompts")
    eq(fgathered.chimera_known, false, "an unlearned Chimera never prompts")
    eq(fgathered.explosive_known, false, "an unlearned Explosive never prompts")
    eq(fgathered.wrath_aimed_known, false, "an unlearned Wrath Aimed never prompts")
    eq(fgathered.arcane_known, false, "an unlearned Arcane never prompts")
    eq(fgathered.target_hp_frac, nil, "no Kill Shot rank means no health probe")
end

-- Cold-cache per-client wiring on TBC and Era: with the spell data hidden, the
-- live probe answers nothing and the per-client table decides (the TBC-name /
-- Era-id queries behind the probe are pinned in §10b of hunter_state.lua).
do
    local cold_tbc = build({ project = 5 })
    cold_tbc.hide_spells = true
    local cST = cold_tbc.ST
    cST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
    cST.latency = { world_ms = 50 }
    local cg = cST.HUNTER.guide.gather(cST, {})
    eq(cg.steady_cast_seconds, 1.5, "TBC cold cache: the Steady fallback reads 1.5 s")
    eq(cg.steady_cast_seconds, cST.HUNTER.CAST_TIME_FALLBACK.steady.TBC,
        "TBC cold cache: the Steady read rides the per-client table")
    eq(cg.multi_cast_seconds, 0.5, "TBC cold cache: the Multi fallback reads 0.5 s")
    eq(cg.multi_cast_seconds, cST.HUNTER.CAST_TIME_FALLBACK.multi.TBC,
        "TBC cold cache: the Multi read rides the per-client table")
    local cold_era = build({ project = 2 })
    cold_era.hide_spells = true
    local eST = cold_era.ST
    eST.ranged = { start = 99.0, speed = 4.0, ends_at = 103.0, auto_repeat_active = true }
    eST.latency = { world_ms = 50 }
    local eg = eST.HUNTER.guide.gather(eST, {})
    eq(eg.multi_cast_seconds, 0.5, "Era cold cache: the Multi fallback reads 0.5 s")
    eq(eg.aimed_cast_seconds, 3.0, "Era cold cache: the Aimed fallback reads 3.0 s")
    eq(eg.steady_cast_seconds, nil,
        "Era cold cache: no Steady fallback (the spell does not exist)")
end

-- H2 CUT gather: no Bloodlust/Heroism-family scan exists. An aura on the player
-- changes nothing: no window is ever written and no scan is spent. A reintroduced
-- producer fails the nil pins; a reintroduced scan fails the query-count pins.
-- Source pins at the end prove the machinery is gone from classes/hunter.lua.
do
    local h2 = build({ project = 5 }) -- TBC armed the old scan; now it must not
    local h2ST = h2.ST
    h2ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
    h2ST.latency = { world_ms = 50 }
    h2ST.raptor_strike_queued = false
    h2ST.steady_shot_queued = false
    h2.clock = 100
    h2.player_auras = {
        { name = "Bloodlust", spell_id = 2825, duration = 40, expiration = 130 },
    }
    h2.aura_queries = 0
    local g = h2ST.HUNTER.guide.gather(h2ST, {})
    eq(g.lust_remaining, nil, "H2 CUT gather: a live Bloodlust writes no window")
    eq(h2.aura_queries, 0, "H2 CUT gather: a live Bloodlust spends no aura scan")
    -- A dropped aura changes nothing either (no throttle state survives).
    h2.player_auras = nil
    h2.clock = 100.6
    eq(h2ST.HUNTER.guide.gather(h2ST, {}).lust_remaining, nil,
        "H2 CUT gather: a dropped aura still writes no window")
    eq(h2.aura_queries, 0, "H2 CUT gather: the re-poll spends no aura scan either")
    -- Heroism and unrelated auras are equally silent.
    h2.player_auras = {
        { name = "Heroism", spell_id = 32182, duration = 40, expiration = 140.6 },
    }
    h2.clock = 101.2
    eq(h2ST.HUNTER.guide.gather(h2ST, {}).lust_remaining, nil,
        "H2 CUT gather: Heroism writes no window either")
    h2.player_auras = {
        { name = "Rapid Fire", spell_id = 3045, duration = 15, expiration = 120 },
    }
    h2.clock = 101.8
    eq(h2ST.HUNTER.guide.gather(h2ST, {}).lust_remaining, nil,
        "H2 CUT gather: an unrelated aura writes no window")
    -- Era never armed the old scan and still spends nothing.
    local era = build({ project = 2 })
    era.ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
    era.ST.latency = { world_ms = 50 }
    era.clock = 50
    era.player_auras = {
        { name = "Bloodlust", spell_id = 2825, duration = 40, expiration = 90 },
    }
    era.aura_queries = 0
    eq(era.ST.HUNTER.guide.gather(era.ST, {}).lust_remaining, nil,
        "H2 CUT gather: Era writes no window")
    eq(era.aura_queries, 0, "H2 CUT gather: Era spends no aura scan")
    -- Source pins: the producer machinery is gone from the class module.
    do
        local f = assert(io.open(ROOT .. "classes/hunter.lua", "r"))
        local src = f:read("*a")
        f:close()
        check(src:find("lust_remaining", 1, true) == nil,
            "H2 CUT: no lust field write remains in classes/hunter.lua")
        check(src:find("hunter_lust", 1, true) == nil,
            "H2 CUT: no lust throttle state remains in classes/hunter.lua")
        check(src:find("LUST_RESCAN_INTERVAL", 1, true) == nil,
            "H2 CUT: no lust rescan interval remains in classes/hunter.lua")
        check(src:find("lust_ids", 1, true) == nil,
            "H2 CUT: no lust id set remains in classes/hunter.lua")
    end
end

--=========================================================================================
-- 2b) The TBC provider: the family gate opens and every new prompt lives
--=========================================================================================
do
    local TBC_SPELLS = {
        [34120] = { name = "Steady Shot", icon = "icon_steady_tbc", cast_ms = 1500 },
        [27014] = { name = "Raptor Strike", icon = "icon_raptor_tbc", cast_ms = 0 },
        [34026] = { name = "Kill Command", icon = "icon_kc", cast_ms = 0 },
        [27021] = { name = "Multi-Shot", icon = "icon_multi", cast_ms = 500 },
        [19574] = { name = "Bestial Wrath", icon = "icon_bw", cast_ms = 0 },
        [3045] = { name = "Rapid Fire", icon = "icon_rf", cast_ms = 0 },
    }
    local tbc = build({ project = 5, spell_infos = TBC_SPELLS })
    eq(tbc.st.family, "TBC", "project 5 resolves the TBC family token")
    local tST, tst = tbc.ST, tbc.st
    tST.in_combat = true
    tST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
    tST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
    tST.HUNTER.post_init(tST)
    local tslots = tST.HUNTER.guide.slots
    eq(#tslots, 8, "the TBC client declares the base set plus its mana-swap slots")
    eq(tslots[1].spell_id, 34120, "TBC steady resolves to the TBC rank")
    eq(tslots[2].spell_id, 27014, "TBC raptor resolves to the TBC rank")
    eq(tslots[3].spell_id, 34026, "TBC Kill Command resolves")
    eq(tslots[4].spell_id, 27021, "TBC multi resolves to the top rank")
    eq(tslots[5].spell_id, 19574, "TBC Bestial Wrath resolves")
    eq(tslots[6].spell_id, 3045, "TBC Rapid Fire resolves")
    local tui = tst.nextaction_ui
    eq(tui.icons[3].icon.texture.texture, "icon_kc", "the KC icon shows its texture")
    eq(tui.icons[4].icon.texture.texture, "icon_multi", "the multi icon shows its texture")
    eq(tui.icons[5].icon.texture.texture, "icon_bw", "the BW icon shows its texture")
    eq(tui.icons[6].icon.texture.texture, "icon_rf", "the RF icon shows its texture")

    -- All cooldowns up: Kill Command wins the tick through the real hook.
    tbc.clock = 100
    tST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, synced_duration = nil,
        hidden_window_start = nil, hidden_window_duration = nil, auto_repeat_active = true }
    tST.latency = { world_ms = 50 }
    tST.raptor_strike_queued = false
    tST.steady_shot_queued = false
    tbc.cast = nil
    tbc.cooldowns = {}
    tbc.is_spell_in_range = 1
    local tgathered = tST.HUNTER.guide.gather(tST, {})
    eq(tgathered.kc_known, true, "TBC gather: Kill Command is known")
    eq(tgathered.kc_remaining_cd, 0, "TBC gather: Kill Command is ready")
    eq(tgathered.bw_known, true, "TBC gather: Bestial Wrath is known")
    eq(tgathered.rf_known, true, "TBC gather: Rapid Fire is known")
    eq(tgathered.multi_known, true, "TBC gather: Multi-Shot is known")
    eq(tgathered.multi_cast_seconds, 0.5, "TBC gather: the Multi cast time reads 0.5 s")
    eq(tgathered.multi_remaining, nil, "TBC gather: no live Multi cast")
    local tout = tST.HUNTER.guide.evaluate(tgathered, {})
    eq(tout.action, "kill_command", "TBC: Kill Command is the #1 prompt on a fresh tick")

    -- Kill Command cooling down: Bestial Wrath, then Rapid Fire, then the weave.
    tbc.cooldowns = { [34026] = { 100, 60 } }
    tgathered = tST.HUNTER.guide.gather(tST, {})
    check(tgathered.kc_remaining_cd > 0, "TBC gather: the KC cooldown reads through")
    eq(tST.HUNTER.guide.evaluate(tgathered, {}).action, "bestial_wrath",
        "TBC: Bestial Wrath fires with Kill Command cooling down")
    tbc.cooldowns = { [34026] = { 100, 60 }, [19574] = { 100, 120 } }
    tgathered = tST.HUNTER.guide.gather(tST, {})
    eq(tST.HUNTER.guide.evaluate(tgathered, {}).action, "rapid_fire",
        "TBC: Rapid Fire fires with Kill Command and Bestial Wrath cooling down")
    tbc.cooldowns = { [34026] = { 100, 60 }, [19574] = { 100, 120 },
        [3045] = { 100, 300 } }
    tgathered = tST.HUNTER.guide.gather(tST, {})
    eq(tST.HUNTER.guide.evaluate(tgathered, {}).action, "multi",
        "TBC: Multi-Shot weaves with every cooldown running")
    tbc.cooldowns = { [34026] = { 100, 60 }, [19574] = { 100, 120 },
        [3045] = { 100, 300 }, [27021] = { 100, 10 } }
    tgathered = tST.HUNTER.guide.gather(tST, {})
    eq(tST.HUNTER.guide.evaluate(tgathered, {}).action, "steady",
        "TBC: Steady Shot weaves with Multi-Shot on cooldown (steady-only intact)")

    -- A live Multi-Shot cast rides through the real gather.
    tbc.cooldowns = {}
    tbc.cast = { name = "Multi-Shot", spell_id = 27021, start = 99.8, ["end"] = 100.3 }
    tgathered = tST.HUNTER.guide.gather(tST, {})
    near(tgathered.multi_remaining, 0.3, 1e-9,
        "TBC gather: the live Multi cast's remaining seconds")
    eq(tgathered.steady_remaining, nil,
        "TBC gather: a live Multi cast is not a live Steady cast")
    eq(tST.HUNTER.guide.evaluate(tgathered, {}).hold_text, "RIDE",
        "TBC: the live Multi cast rides instead of re-prompting")
    tbc.cast = nil
end

--=========================================================================================
-- 2c) The TBC frame mapping through the real hook
--=========================================================================================
do
    local TBC_SPELLS = {
        [34120] = { name = "Steady Shot", icon = "icon_steady_tbc", cast_ms = 1500 },
        [27014] = { name = "Raptor Strike", icon = "icon_raptor_tbc", cast_ms = 0 },
        [34026] = { name = "Kill Command", icon = "icon_kc", cast_ms = 0 },
        [27021] = { name = "Multi-Shot", icon = "icon_multi", cast_ms = 500 },
        [19574] = { name = "Bestial Wrath", icon = "icon_bw", cast_ms = 0 },
        [3045] = { name = "Rapid Fire", icon = "icon_rf", cast_ms = 0 },
    }
    local tbc = build({ project = 5, spell_infos = TBC_SPELLS })
    local tST = tbc.ST
    local tui = tbc.st.nextaction_ui
    tST.in_combat = true
    tST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
    tST.latency = { world_ms = 50 }
    tST.raptor_strike_queued = false
    tST.steady_shot_queued = false
    tbc.clock = 100
    tbc.cast = nil
    tbc.cooldowns = {}
    tST.HUNTER.post_init(tST)
    local function ttarget(key) return tui.icons[tui.slot_index[key]].fade.target end
    local function ttick()
        tST.mainhand = { speed = 3.0, ends_at = tbc.clock + 3.0, start = tbc.clock,
            is_full = false }
        tbc.advance(0.1)
        tST.HUNTER.on_bar_update(tST, "mainhand")
    end
    ttick()
    eq(ttarget("kill_command"), 1, "TBC tick: the KC prompt lights the KC slot")
    eq(ttarget("steady"), 0, "TBC tick: the Steady slot stays dark behind KC")
    eq(tui.frame.hold.fade.target, 0, "TBC tick: the KC prompt shows no hold")
    eq(tui.frame.shown, true, "TBC tick: the frame shows in combat")

    -- KC cooling down: the BW prompt takes the slot through the same hook.
    tbc.cooldowns = { [34026] = { tbc.clock, 60 } }
    ttick()
    eq(ttarget("kill_command"), 0, "TBC tick: KC on cooldown fades out")
    eq(ttarget("bestial_wrath"), 1, "TBC tick: the BW prompt lights the BW slot")

    -- Everything cooling down: the weave prompt lands on the multi slot.
    tbc.cooldowns = { [34026] = { tbc.clock, 60 }, [19574] = { tbc.clock, 120 },
        [3045] = { tbc.clock, 300 } }
    ttick()
    eq(ttarget("multi"), 1, "TBC tick: the weave prompt lights the multi slot")
    eq(ttarget("steady"), 0, "TBC tick: Steady stays dark behind a due Multi")

    -- The hidden window holds the weave prompt end to end (rule 2 on non-Wrath).
    -- Only a current-cycle cache counts, so the tick advances into the live
    -- cycle's window ([101.45, 102] for the [99, 102] cycle) instead of injecting
    -- a synthetic off-cycle cache.
    tbc.advance(1.1)
    ttick()
    eq(tui.frame.hold.fade.target, 1, "TBC tick: the window shows the hold overlay")
    eq(tui.frame.hold.text.text, "HOLD", "TBC tick: the window reads HOLD")
    eq(ttarget("multi"), 0, "TBC tick: the window suppresses the weave prompt")
end

--=========================================================================================
-- 2d) The ERA provider: no Steady fallback, the Aimed + Multi weave, three slots
--=========================================================================================
-- Era has no Steady Shot (the old code prompted the rank-1 fallback 56641, which no
-- Era client resolves): the Era slot set is {aimed, raptor, multi} and rule 6c's
-- known gate keeps the silence. The 4.0-speed cycle below models the slow weapon the
-- 3 s Aimed cast needs; a 3.0-speed cycle never fits it (pinned in the 6a section).
do
    local ERA_SPELLS = {
        [20904] = { name = "Aimed Shot", icon = "icon_aimed", cast_ms = 3000 },
        [14265] = { name = "Raptor Strike", icon = "icon_raptor_era", cast_ms = 0 },
        [14290] = { name = "Multi-Shot", icon = "icon_multi_era", cast_ms = 500 },
    }
    local era = build({ project = 2, spell_infos = ERA_SPELLS })
    eq(era.st.family, "ERA", "project 2 resolves the ERA family token")
    local eST, est = era.ST, era.st
    eST.in_combat = true
    eST.mainhand = { speed = 4.0, ends_at = 4.0, start = 0.0, is_full = false }
    eST.ranged = { start = 99.0, speed = 4.0, ends_at = 103.0, auto_repeat_active = true }
    eST.HUNTER.post_init(eST)
    local eslots = eST.HUNTER.guide.slots
    eq(#eslots, 5, "the Era client declares the Era set with the Rapid Fire and Serpent rows")
    check(#eslots <= 6, "the Era slot set stays at the contract's six or fewer")
    eq(eslots[1].key, "aimed", "Era slot 1 is aimed (the primary filler)")
    eq(eslots[2].key, "raptor", "Era slot 2 is raptor (the melee surface)")
    eq(eslots[3].key, "multi", "Era slot 3 is multi (the weave prompt)")
    eq(eslots[1].cooldown_key, "aimed", "the aimed slot carries its live-cast swipe key")
    eq(eslots[1].swipe_duration, 3.0, "the aimed slot carries the cast-length swipe fallback")
    eq(eslots[1].swipe_always, true, "the aimed swipe stays armed while the RIDE hold fades the icon")
    eq(eslots[2].cooldown_key, nil, "the Era raptor slot carries no swipe")
    eq(eslots[3].cooldown_key, nil, "the Era multi slot is a swipe-less prompt")
    eq(eslots[1].spell_id, 20904, "Era aimed resolves to the top rank")
    eq(eslots[2].spell_id, 14265, "Era raptor resolves to the module top vanilla rank")
    eq(eslots[3].spell_id, 14290, "Era multi resolves to the top rank")
    local eui = est.nextaction_ui
    eq(#eui.icons, 5, "the Era frame holds one icon per slot")
    eq(era.frames, 13, "Era frame count: group + hold + 5 icons/borders + 1 cooldown")
    eq(eui.icons[1].icon.texture.texture, "icon_aimed",
        "the aimed icon shows the current rank's texture")
    eq(eui.icons[1].remaining_key, "aimed_remaining", "the swipe field names derive from the key")
    eq(eui.icons[1].duration_key, "aimed_duration", "the swipe length field derives from the key")
    eq(eui.slot_index.steady, nil, "the Era frame has no steady slot to light (no fallback prompt)")
    eq(eui.slot_index.kill_command, nil, "the Era frame has no Kill Command slot")

    -- The gather on a slow-weapon Era tick: Steady unknown, Multi + Aimed due.
    era.clock = 100
    eST.ranged = { start = 99.0, speed = 4.0, ends_at = 103.0, synced_duration = nil,
        hidden_window_start = nil, hidden_window_duration = nil, auto_repeat_active = true }
    eST.latency = { world_ms = 50 }
    eST.raptor_strike_queued = false
    eST.steady_shot_queued = false
    era.cast = nil
    era.cooldowns = {}
    era.is_spell_in_range = 1
    era.cooldown_queries = 0
    local egathered = eST.HUNTER.guide.gather(eST, {})
    eq(egathered.steady_known, false, "Era gather: Steady Shot is unknown (never prompts)")
    eq(egathered.steady_remaining_cd, 0, "Era gather: the unknown Steady rank reads no cooldown")
    eq(egathered.multi_known, true, "Era gather: Multi-Shot is known")
    eq(egathered.multi_cast_seconds, 0.5, "Era gather: the Multi cast time reads 0.5 s")
    eq(egathered.aimed_known, true, "Era gather: Aimed Shot is known")
    eq(egathered.aimed_cast_seconds, 3.0, "Era gather: the Aimed cast time reads 3.0 s")
    eq(egathered.aimed_remaining_cd, 0, "Era gather: Aimed Shot is ready")
    eq(egathered.aimed_remaining, nil, "Era gather: no live Aimed cast")
    eq(egathered.kc_known, false, "Era gather: Kill Command never prompts")
    eq(egathered.bw_known, false, "Era gather: Bestial Wrath never prompts")
    eq(egathered.rf_known, false, "Era gather: Rapid Fire never prompts")
    -- The family-correct ids changed what the gather SPENDS: a slot for a spell
    -- the running client cannot have carries no id at all (the Era family cell is
    -- empty - the Era client has neither Kill Command nor Bestial Wrath), so the
    -- gather reads no cooldown for it (bench/hunter_hud_family_2026-10-20.md §2).
    eq(era.cooldown_queries, 4, "Era gather: one cooldown read per prompt (steady/rf/multi/aimed)")
    eq(eST.HUNTER.guide.evaluate(egathered, {}).action, "aimed",
        "Era: Aimed Shot is the prompt on a fresh slow-weapon tick")

    -- Aimed cooling down: Multi-Shot, the Era weave.
    era.cooldowns = { [20904] = { 100, 6 } }
    egathered = eST.HUNTER.guide.gather(eST, {})
    check(egathered.aimed_remaining_cd > 0, "Era gather: the Aimed cooldown reads through")
    eq(eST.HUNTER.guide.evaluate(egathered, {}).action, "multi",
        "Era: Multi-Shot weaves with Aimed Shot cooling down")

    -- Both cooling down: silence, never the Steady fallback (the bug fix end to end).
    era.cooldowns = { [20904] = { 100, 6 }, [14290] = { 100, 10 } }
    egathered = eST.HUNTER.guide.gather(eST, {})
    local eout = eST.HUNTER.guide.evaluate(egathered, {})
    eq(eout.action, nil, "Era: both shots cooling down shows no action (never the fallback)")
    eq(eout.hold, false, "Era: the double cooldown shows no hold when nothing is queued")
    eST.raptor_strike_queued = true
    egathered = eST.HUNTER.guide.gather(eST, {})
    eq(eST.HUNTER.guide.evaluate(egathered, {}).hold_text, "RIDE",
        "Era: a queue behind the double cooldown still rides")
    eST.raptor_strike_queued = false
    era.cooldowns = {}

    -- A live Aimed Shot cast rides through the real gather, with the swipe pair.
    era.cast = { name = "Aimed Shot", spell_id = 20904, start = 99.5, ["end"] = 102.5 }
    egathered = eST.HUNTER.guide.gather(eST, {})
    near(egathered.aimed_remaining, 2.5, 1e-9,
        "Era gather: the live Aimed cast's remaining seconds")
    near(egathered.aimed_duration, 3.0, 1e-9,
        "Era gather: the live Aimed cast's full length")
    eq(egathered.steady_remaining, nil,
        "Era gather: a live Aimed cast is not a live Steady cast")
    eq(eST.HUNTER.guide.evaluate(egathered, {}).hold_text, "RIDE",
        "Era: the live Aimed cast rides instead of re-prompting")
    era.cast = nil

    -- Every action the Era engine can return names an Era slot.
    do
        local actions = { "aimed", "multi" }
        local all_resolve = true
        for i = 1, #actions do
            if eui.slot_index[actions[i]] == nil then
                all_resolve = false
            end
        end
        check(all_resolve, "every Era action names a declared Era slot")
    end

    -- The Era tick through the real hook lights the aimed slot.
    local function etarget(key) return eui.icons[eui.slot_index[key]].fade.target end
    local function etick()
        eST.mainhand = { speed = 4.0, ends_at = era.clock + 4.0, start = era.clock,
            is_full = false }
        era.advance(0.1)
        eST.HUNTER.on_bar_update(eST, "mainhand")
    end
    eST.ranged = { start = 99.0, speed = 4.0, ends_at = 103.0, auto_repeat_active = true }
    etick()
    eq(etarget("aimed"), 1, "Era tick: the Aimed prompt lights the aimed slot")
    eq(eui.frame.hold.fade.target, 0, "Era tick: the Aimed prompt shows no hold")
    eq(eui.frame.shown, true, "Era tick: the frame shows in combat")
    era.cooldowns = { [20904] = { era.clock, 6 } }
    etick()
    eq(etarget("aimed"), 0, "Era tick: Aimed on cooldown fades out")
    eq(etarget("multi"), 1, "Era tick: the weave prompt lights the multi slot")
end

--=========================================================================================
-- 2e) The family gates hold when the spell data crosses families
--=========================================================================================
-- A TBC client whose spell data answers an Aimed Shot rank still never prompts it
-- (the Era slot is not declared there and aimed_known stays false); an Era client
-- whose data answers a Steady rank prompts it (known-rank gate, no family test).
do
    local TBC_SPELLS = {
        [34120] = { name = "Steady Shot", icon = "icon_steady_tbc", cast_ms = 1500 },
        [27014] = { name = "Raptor Strike", icon = "icon_raptor_tbc", cast_ms = 0 },
        [34026] = { name = "Kill Command", icon = "icon_kc", cast_ms = 0 },
        [27021] = { name = "Multi-Shot", icon = "icon_multi", cast_ms = 500 },
        [19574] = { name = "Bestial Wrath", icon = "icon_bw", cast_ms = 0 },
        [3045] = { name = "Rapid Fire", icon = "icon_rf", cast_ms = 0 },
        [20904] = { name = "Aimed Shot", icon = "icon_aimed_tbc", cast_ms = 2500 },
    }
    local tbc = build({ project = 5, spell_infos = TBC_SPELLS })
    local tST = tbc.ST
    tST.ranged = { start = 99.0, speed = 4.0, ends_at = 103.0, auto_repeat_active = true }
    tST.latency = { world_ms = 50 }
    tST.raptor_strike_queued = false
    tST.steady_shot_queued = false
    tbc.clock = 100
    tbc.cast = nil
    tbc.cooldowns = {}
    tST.HUNTER.post_init(tST)
    local tgathered = tST.HUNTER.guide.gather(tST, {})
    eq(tgathered.aimed_known, false,
        "TBC gather: a known Aimed rank still never weaves (Era family gate)")
    eq(tgathered.aimed_remaining_cd, nil,
        "TBC gather: no Aimed cooldown is read (query count unchanged)")
    eq(tgathered.steady_known, true, "TBC gather: Steady stays known")
    eq(#tST.HUNTER.guide.slots, 8, "TBC with Aimed data still declares the TBC slot set")
    eq(tST.HUNTER.guide.evaluate(tgathered, {}).action, "kill_command",
        "TBC with Aimed data: Kill Command still wins the fresh tick")
end

--=========================================================================================
-- 2f) The Wrath provider: MM vs SV by spell knowledge, the execute, the filler
--=========================================================================================
-- Spell knowledge (not data presence) detects the spec: Chimera learned = MM,
-- Explosive learned = SV. A Wrath client whose data answers a rank the player
-- never learned resolves nothing and prompts nothing for it.
do
    local WRATH_SPELLS = {
        [49052] = { name = "Steady Shot", icon = "icon_steady_wrath", cast_ms = 1500 },
        [48996] = { name = "Raptor Strike", icon = "icon_raptor_wrath", cast_ms = 0 },
        [53351] = { name = "Kill Shot", icon = "icon_killshot", cast_ms = 0 },
        [53209] = { name = "Chimera Shot", icon = "icon_chimera", cast_ms = 0 },
        [53301] = { name = "Explosive Shot", icon = "icon_explosive", cast_ms = 0 },
        [49050] = { name = "Aimed Shot", icon = "icon_aimed_wrath", cast_ms = 0 },
        [49045] = { name = "Arcane Shot", icon = "icon_arcane", cast_ms = 0 },
    }
    local function fresh_wrath(known)
        local w = build({ project = 11, spell_infos = WRATH_SPELLS, known_spells = known })
        eq(w.st.family, "WRATH", "project 11 resolves the WRATH family token")
        local wST = w.ST
        wST.in_combat = true
        wST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
        wST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
        wST.HUNTER.post_init(wST)
        return w, wST
    end

    -- MM: Chimera learned (plus the trained shots), target healthy.
    local mm, mST = fresh_wrath({ [53209] = true, [49052] = true, [49050] = true,
        [49045] = true, [53351] = true })
    do
        local mslots = mST.HUNTER.guide.slots
        eq(#mslots, 13, "Wrath MM declares the thirteen-slot spine")
        eq(mslots[1].spell_id, 53351, "Wrath MM resolves the Kill Shot icon")
        eq(mslots[2].spell_id, 53209, "Wrath MM resolves the Chimera icon")
        eq(mslots[3].spell_id, 53301, "an unlearned Explosive keeps the rank-1 fallback")
        eq(mslots[4].spell_id, 49050, "Wrath MM resolves the Aimed icon")
        eq(mslots[5].spell_id, 49045, "Wrath MM resolves the Arcane icon")
        eq(mslots[6].spell_id, 49052, "Wrath MM resolves the Steady icon")
        local mui = mm.st.nextaction_ui
        eq(mui.icons[2].icon.texture.texture, "icon_chimera",
            "the Chimera icon shows its texture")
        eq(mui.icons[4].icon.texture.texture, "icon_aimed_wrath",
            "the Wrath Aimed icon shows its texture")

        mm.clock = 100
        mST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, synced_duration = nil,
            hidden_window_start = nil, hidden_window_duration = nil,
            auto_repeat_active = true }
        mST.latency = { world_ms = 50 }
        mST.raptor_strike_queued = false
        mST.steady_shot_queued = false
        mm.cast = nil
        mm.cooldowns = {}
        mm.is_spell_in_range = 1
        mm.health, mm.health_max = 100, 100
        mm.cooldown_queries = 0
        local mgathered = mST.HUNTER.guide.gather(mST, {})
        eq(mgathered.killshot_known, true, "Wrath MM gather: Kill Shot is learned")
        eq(mgathered.killshot_remaining_cd, 0, "Wrath MM gather: Kill Shot is ready")
        eq(mgathered.target_hp_frac, 1, "Wrath MM gather: the target is healthy")
        eq(mgathered.chimera_known, true, "Wrath MM gather: Chimera is learned")
        eq(mgathered.explosive_known, false, "Wrath MM gather: Explosive is unlearned")
        eq(mgathered.wrath_aimed_known, true, "Wrath MM gather: Aimed is learned")
        eq(mgathered.arcane_known, true, "Wrath MM gather: Arcane is learned")
        eq(mm.cooldown_queries, 9,
            "Wrath MM gather: one cooldown read per resolved prompt (steady/kc/bw/rf/multi + kill/chimera/aimed/arcane)")
        eq(mST.HUNTER.guide.evaluate(mgathered, {}).action, "chimera",
            "Wrath MM: Chimera is the prompt with a healthy target")

        -- Execute range: Kill Shot jumps the queue without any window or clip.
        mm.health = 15
        mgathered = mST.HUNTER.guide.gather(mST, {})
        eq(mgathered.target_hp_frac, 0.15, "Wrath MM gather: the execute fraction reads 0.15")
        eq(mST.HUNTER.guide.evaluate(mgathered, {}).action, "kill_shot",
            "Wrath MM: Kill Shot is the prompt in execute range")
        mm.health = 100

        -- Chimera cooling down: Aimed (instant tier), then Arcane, then filler.
        mm.cooldowns = { [53209] = { 100, 6 } }
        mgathered = mST.HUNTER.guide.gather(mST, {})
        check(mgathered.chimera_remaining_cd > 0, "Wrath MM gather: the Chimera cooldown reads through")
        eq(mST.HUNTER.guide.evaluate(mgathered, {}).action, "aimed",
            "Wrath MM: Aimed fires with Chimera cooling down")
        mm.cooldowns = { [53209] = { 100, 6 }, [49050] = { 100, 10 } }
        mgathered = mST.HUNTER.guide.gather(mST, {})
        eq(mST.HUNTER.guide.evaluate(mgathered, {}).action, "arcane",
            "Wrath MM: Arcane fires with Chimera and Aimed cooling down")
        mm.cooldowns = { [53209] = { 100, 6 }, [49050] = { 100, 10 },
            [49045] = { 100, 6 } }
        mgathered = mST.HUNTER.guide.gather(mST, {})
        eq(mST.HUNTER.guide.evaluate(mgathered, {}).action, "steady",
            "Wrath MM: Steady fills with every shot cooling down")
        mm.cooldowns = {}
    end

    -- SV: Explosive learned (plus the trained shots, Arcane included: learned
    -- but suppressed by the shared cooldown).
    local sv, sST = fresh_wrath({ [53301] = true, [49052] = true, [49050] = true,
        [49045] = true })
    do
        eq(sST.HUNTER.guide.slots[3].spell_id, 53301, "Wrath SV resolves the Explosive icon")
        eq(sST.HUNTER.guide.slots[2].spell_id, 53209, "an unlearned Chimera keeps the rank-1 fallback")
        sv.clock = 100
        sST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, synced_duration = nil,
            hidden_window_start = nil, hidden_window_duration = nil,
            auto_repeat_active = true }
        sST.latency = { world_ms = 50 }
        sST.raptor_strike_queued = false
        sST.steady_shot_queued = false
        sv.cast = nil
        sv.cooldowns = {}
        sv.is_spell_in_range = 1
        sv.health, sv.health_max = 100, 100
        sv.cooldown_queries = 0
        local sgathered = sST.HUNTER.guide.gather(sST, {})
        eq(sgathered.explosive_known, true, "Wrath SV gather: Explosive is learned")
        eq(sgathered.chimera_known, false, "Wrath SV gather: Chimera is unlearned")
        eq(sgathered.arcane_known, true, "Wrath SV gather: Arcane is learned (trained)")
        eq(sv.cooldown_queries, 8,
            "Wrath SV gather: one cooldown read per resolved prompt (steady/kc/bw/rf/multi + explosive/aimed/arcane)")
        eq(sST.HUNTER.guide.evaluate(sgathered, {}).action, "explosive",
            "Wrath SV: Explosive is the prompt (Arcane suppressed by the shared cooldown)")

        -- Explosive cooling down: Aimed, never Arcane, then the filler.
        sv.cooldowns = { [53301] = { 100, 6 } }
        sgathered = sST.HUNTER.guide.gather(sST, {})
        eq(sST.HUNTER.guide.evaluate(sgathered, {}).action, "aimed",
            "Wrath SV: Aimed fires with Explosive cooling down (never Arcane)")
        sv.cooldowns = { [53301] = { 100, 6 }, [49050] = { 100, 10 } }
        sgathered = sST.HUNTER.guide.gather(sST, {})
        eq(sST.HUNTER.guide.evaluate(sgathered, {}).action, "steady",
            "Wrath SV: Steady fills with Explosive and Aimed cooling down")
        sv.cooldowns = {}

        -- The SV tick through the real hook lights the explosive slot.
        local sui = sv.st.nextaction_ui
        local function starget(key) return sui.icons[sui.slot_index[key]].fade.target end
        local function stick()
            sST.mainhand = { speed = 3.0, ends_at = sv.clock + 3.0, start = sv.clock,
                is_full = false }
            sv.advance(0.1)
            sST.HUNTER.on_bar_update(sST, "mainhand")
        end
        stick()
        eq(starget("explosive"), 1, "Wrath SV tick: the Explosive prompt lights its slot")
        eq(starget("arcane"), 0, "Wrath SV tick: the Arcane slot stays dark")
        eq(sui.frame.hold.fade.target, 0, "Wrath SV tick: the prompt shows no hold")
    end

    -- Wrath data without knowledge (levelling): the Steady filler alone.
    local lv, lST = fresh_wrath(nil)
    do
        local lgathered = lST.HUNTER.guide.gather(lST, {})
        eq(lgathered.killshot_known, false, "levelling: data without knowledge prompts nothing")
        eq(lgathered.chimera_known, false, "levelling: an unlearned Chimera stays dark")
        eq(lgathered.steady_known, true, "levelling: Steady still resolves from data alone")
        lST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
        lST.latency = { world_ms = 50 }
        lv.clock = 100
        lv.cast = nil
        lv.cooldowns = {}
        lgathered = lST.HUNTER.guide.gather(lST, {})
        eq(lST.HUNTER.guide.evaluate(lgathered, {}).action, "steady",
            "levelling: the Steady filler is the whole matrix")
    end
end

--=========================================================================================
-- 2g) The SoD provider: the rune swaps the Era set, the weave sits above Aimed
--=========================================================================================
-- SoD shares the ERA token: the swap is gated on api.is_spell_known of the
-- SoD-only rune id, never on the family alone. A pet-rune build that drops
-- Chimera keeps the plain Era set and weave.
do
    local SOD_SPELLS = {
        [20904] = { name = "Aimed Shot", icon = "icon_aimed_sod", cast_ms = 3000 },
        [14265] = { name = "Raptor Strike", icon = "icon_raptor_sod", cast_ms = 0 },
        [14290] = { name = "Multi-Shot", icon = "icon_multi_sod", cast_ms = 500 },
        [409433] = { name = "Chimera Shot", icon = "icon_chimera_sod", cast_ms = 0 },
    }
    local sod = build({ project = 2, spell_infos = SOD_SPELLS,
        known_spells = { [409433] = true } })
    eq(sod.st.family, "ERA", "the SoD client carries the ERA family token")
    local sST, sst = sod.ST, sod.st
    sST.in_combat = true
    sST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
    sST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
    sST.HUNTER.post_init(sST)
    local sslots = sST.HUNTER.guide.slots
    eq(#sslots, 13, "SoD declares the thirteen-slot spine")
    check(#sslots >= 4, "the SoD slot set carries the whole spine")
    do
        local keys = {}
        for i = 1, #sslots do keys[#keys + 1] = sslots[i].key end
        eq(table.concat(keys, ","),
            "chimera,aimed,raptor,multi,rapid_fire,bestial_wrath,kill_shot,raptor_strike,"
                .. "wyvern_strike,aspect_viper,arcane,aspect_falcon,wing_clip",
            "SoD slots are the Era set with Chimera first, then the APL's utility spine")
    end
    eq(sslots[1].spell_id, 409433, "SoD resolves the Chimera rune icon")
    eq(sslots[1].cooldown_key, nil, "the SoD Chimera slot is a swipe-less prompt")
    eq(sslots[2].spell_id, 20904, "SoD keeps the Era Aimed rank")
    -- The Bestial Wrath: the SoD client HAS the spell (its own spell data maps
    -- 19574 to the Beast Mastery skill line), so the SoD set declares the slot
    -- the Era-base set drops - with the client's own id.
    eq(sslots[6].key, "bestial_wrath", "SoD declares the Bestial Wrath slot")
    eq(sslots[6].spell_id, 19574, "the SoD Bestial Wrath slot carries the client's own rank")
    local sui = sst.nextaction_ui
    eq(#sui.icons, 13, "the SoD frame holds one icon per slot")
    eq(sod.frames, 29, "SoD frame count: group + hold + 13 icons/borders + 1 cooldown")
    eq(sui.icons[1].icon.texture.texture, "icon_chimera_sod",
        "the Chimera icon shows the rune texture")

    -- The gather on a SoD tick: the rune weaves above the Era pair. The read
    -- count is the Era four plus the rune plus the Bestial Wrath - the SoD
    -- client HAS that spell (its own spell data), so the guide's SoD slot set
    -- declares it and the gather reads its cooldown, exactly like the other
    -- families that carry the Bestial Wrath slot.
    sod.clock = 100
    sST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, synced_duration = nil,
        hidden_window_start = nil, hidden_window_duration = nil, auto_repeat_active = true }
    sST.latency = { world_ms = 50 }
    sST.raptor_strike_queued = false
    sST.steady_shot_queued = false
    sod.cast = nil
    sod.cooldowns = {}
    sod.is_spell_in_range = 1
    sod.cooldown_queries = 0
    local sgathered = sST.HUNTER.guide.gather(sST, {})
    eq(sgathered.chimera_known, true, "SoD gather: the learned rune weaves")
    eq(sgathered.chimera_remaining_cd, 0, "SoD gather: the rune is ready")
    eq(sgathered.steady_known, false, "SoD gather: Steady stays unknown on Era")
    eq(sod.cooldown_queries, 6, "SoD gather: the Era four plus the rune read plus the Bestial Wrath")
    eq(sST.HUNTER.guide.evaluate(sgathered, {}).action, "chimera",
        "SoD: Chimera is the prompt on a fresh tick")

    -- The rune cooling down: the Era weave (Aimed on the slow cycle, else Multi,
    -- else silence - never the Steady fallback).
    sod.cooldowns = { [409433] = { 100, 6 } }
    sgathered = sST.HUNTER.guide.gather(sST, {})
    check(sgathered.chimera_remaining_cd > 0, "SoD gather: the rune cooldown reads through")
    sST.ranged = { start = 99.0, speed = 4.0, ends_at = 103.0, auto_repeat_active = true }
    sgathered = sST.HUNTER.guide.gather(sST, {})
    eq(sST.HUNTER.guide.evaluate(sgathered, {}).action, "aimed",
        "SoD: Aimed weaves with the rune cooling down")
    sod.cooldowns = { [409433] = { 100, 6 }, [20904] = { 100, 6 } }
    sgathered = sST.HUNTER.guide.gather(sST, {})
    eq(sST.HUNTER.guide.evaluate(sgathered, {}).action, "multi",
        "SoD: Multi weaves with the rune and Aimed cooling down")
    sod.cooldowns = { [409433] = { 100, 6 }, [20904] = { 100, 6 },
        [14290] = { 100, 10 } }
    sgathered = sST.HUNTER.guide.gather(sST, {})
    local sout = sST.HUNTER.guide.evaluate(sgathered, {})
    eq(sout.action, nil, "SoD: everything cooling down shows no action (never the fallback)")
    eq(sout.hold, false, "SoD: the triple cooldown shows no hold when nothing is queued")

    -- The SoD tick through the real hook lights the chimera slot.
    sod.cooldowns = {}
    sST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
    local function sotarget(key) return sui.icons[sui.slot_index[key]].fade.target end
    local function sotick()
        sST.mainhand = { speed = 3.0, ends_at = sod.clock + 3.0, start = sod.clock,
            is_full = false }
        sod.advance(0.1)
        sST.HUNTER.on_bar_update(sST, "mainhand")
    end
    sotick()
    eq(sotarget("chimera"), 1, "SoD tick: the Chimera prompt lights the chimera slot")
    eq(sotarget("aimed"), 0, "SoD tick: the Aimed slot stays dark behind Chimera")
    eq(sui.frame.hold.fade.target, 0, "SoD tick: the weave prompt shows no hold")
    sod.cooldowns = { [409433] = { sod.clock, 6 } }
    sST.ranged = { start = 99.0, speed = 4.0, ends_at = 103.0, auto_repeat_active = true }
    sotick()
    eq(sotarget("chimera"), 0, "SoD tick: the rune on cooldown fades out")
    eq(sotarget("aimed"), 1, "SoD tick: the weave prompt lights the aimed slot")

    -- Pet-rune build (rune in data, never learned): the plain Era set and weave.
    local plain = build({ project = 2, spell_infos = SOD_SPELLS })
    local pST = plain.ST
    pST.HUNTER.post_init(pST)
    local pslots = pST.HUNTER.guide.slots
    eq(#pslots, 5, "a pet-rune build keeps the plain Era set")
    eq(pslots[1].key, "aimed", "a pet-rune build opens with the Era Aimed slot")
    plain.clock = 100
    pST.ranged = { start = 99.0, speed = 4.0, ends_at = 103.0, auto_repeat_active = true }
    pST.latency = { world_ms = 50 }
    plain.cast = nil
    plain.cooldowns = {}
    local pgathered = pST.HUNTER.guide.gather(pST, {})
    eq(pgathered.chimera_known, false, "a pet-rune build never weaves Chimera")
    eq(pST.HUNTER.guide.evaluate(pgathered, {}).action, "aimed",
        "a pet-rune build weaves Aimed on the slow cycle")
end

--=========================================================================================
-- 2h) The Forever provider: the upkeep set, silent until the ids confirm
--=========================================================================================
-- The beta guides name Summon Hawk and Sniper Shot but publish no spell ids, so
-- the module's tables are empty: nothing resolves, both prompts stay silent by
-- construction, and the melee surface carries the tick. Multi-Shot data answers
-- but never prompts (the conservative gate).
-- The fixture carries NO Steady Shot: the Forever client has none at all (the
-- corpus correction of 2026-10-20, bench/rotation_gap_vs_apl_2026-10-20.md §0.0
-- H4 - the spell arrived in 2.3 and the Forever spell data carries no
-- SteadyShot table), so the guide declares no Steady slot there and the engine's
-- steady arm can never fire (steady_known is false by construction).
do
    local FOREVER_SPELLS = {
        [27014] = { name = "Raptor Strike", icon = "icon_raptor_forever", cast_ms = 0 },
        [27021] = { name = "Multi-Shot", icon = "icon_multi_forever", cast_ms = 500 },
    }
    local fw = build({ project = 18, spell_infos = FOREVER_SPELLS })
    eq(fw.st.family, "FOREVER", "project 18 resolves the FOREVER family token")
    local fST, fst = fw.ST, fw.st
    fST.in_combat = true
    fST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
    fST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
    fST.HUNTER.post_init(fST)
    local fslots = fST.HUNTER.guide.slots
    eq(#fslots, 11, "the Forever client declares the eleven-slot spine (no Steady Shot)")
    check(#fslots >= 4, "the Forever slot set carries the whole spine")
    do
        local keys = {}
        for i = 1, #fslots do keys[#keys + 1] = fslots[i].key end
        eq(table.concat(keys, ","),
            "hawk,sniper,raptor,raptor_strike,hunters_mark,mongoose_bite,"
                .. "immolation_trap,wing_clip,serpent,arcane,multi",
            "Forever slots are the upkeep, the cast, the melee surface and the APL's spine")
    end
    eq(fslots[1].spell_id, nil, "the hawk slot ships spell-less (UNCONFIRMED id)")
    eq(fslots[1].cooldown_key, nil, "the hawk slot is a swipe-less upkeep prompt")
    eq(fslots[2].spell_id, nil, "the sniper slot ships spell-less (UNCONFIRMED id)")
    eq(fslots[2].cooldown_key, "sniper", "the sniper slot carries its live-cast swipe key")
    eq(fslots[2].swipe_duration, 4.0, "the sniper slot carries the cast-length swipe fallback")
    eq(fslots[2].swipe_always, true, "the sniper swipe stays armed while the RIDE hold fades the icon")
    eq(fslots[3].spell_id, 27014, "Forever raptor resolves to the known rank")
    local steady_slot = nil
    for i = 1, #fslots do
        if fslots[i].key == "steady" then steady_slot = fslots[i] end
    end
    eq(steady_slot, nil,
        "the Forever guide declares NO Steady slot (the client has no Steady Shot)")
    local fui = fst.nextaction_ui
    eq(#fui.icons, 11, "the Forever frame holds one icon per slot")
    eq(fw.frames, 25, "Forever frame count: group + hold + 11 icons/borders + 1 cooldown")
    eq(fui.icons[1].icon.texture.texture, nil,
        "a spell-less hawk icon simply stays texture-less (no error)")
    eq(fui.icons[2].icon.texture.texture, nil,
        "a spell-less sniper icon simply stays texture-less (no error)")
    eq(fui.icons[3].icon.texture.texture, "icon_raptor_forever",
        "the raptor icon shows the current rank's texture")
    eq(fui.icons[2].remaining_key, "sniper_remaining", "the swipe field names derive from the key")
    eq(fui.icons[2].duration_key, "sniper_duration", "the swipe length field derives from the key")
    eq(fui.icons[1].remaining_key, nil, "the hawk slot carries no swipe fields")

    -- The gather on a Forever tick: both UNCONFIRMED gates down and no Steady Shot.
    fw.clock = 100
    fST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, synced_duration = nil,
        hidden_window_start = nil, hidden_window_duration = nil, auto_repeat_active = true }
    fST.latency = { world_ms = 50 }
    fST.raptor_strike_queued = false
    fST.steady_shot_queued = false
    fw.cast = nil
    fw.cooldowns = {}
    fw.is_spell_in_range = 1
    fw.cooldown_queries = 0
    local fgathered = fST.HUNTER.guide.gather(fST, {})
    eq(fgathered.hawk_known, false, "Forever gather: the hawk id is unconfirmed (never prompts)")
    eq(fgathered.hawk_active_count, nil, "Forever gather: the hawk count is unknown (never guessed)")
    eq(fgathered.hawk_remaining_cd, 0, "Forever gather: no hawk rank reads idle (no query spent)")
    eq(fgathered.sniper_known, false, "Forever gather: the sniper id is unconfirmed (never prompts)")
    eq(fgathered.sniper_cast_seconds, 4.0, "Forever gather: the Sniper cast time falls back to 4.0 s")
    eq(fgathered.sniper_remaining_cd, 0, "Forever gather: no sniper rank reads idle (no query spent)")
    eq(fgathered.sniper_remaining, nil, "Forever gather: no live Sniper cast is tracked")
    eq(fgathered.sniper_duration, nil, "Forever gather: no Sniper swipe length is tracked")
    eq(fgathered.multi_known, false, "Forever gather: Multi-Shot data answers but never prompts")
    eq(fgathered.steady_known, false,
        "Forever gather: the client knows no Steady Shot (the corpus correction, §0.0 H4)")
    eq(fgathered.steady_cast_seconds, nil,
        "Forever gather: no Steady Shot means no Steady cast-time fallback either")
    -- The Forever client has no Kill Command (its own hunter spell table carries
    -- no Kill Command entry - wowsims/forever sim/hunter/spell_data_auto_gen.go),
    -- so the family-correct slot carries no id and the gather spends no read for
    -- it (bench/hunter_hud_family_2026-10-20.md §2).
    eq(fw.cooldown_queries, 3, "Forever gather: one cooldown read per old prompt (bw/rf/multi)")
    eq(fST.HUNTER.guide.evaluate(fgathered, {}).action, nil,
        "Forever: no action on a fresh tick (the client has no Steady Shot to fill with)")

    -- Stale fields are overwritten on the reused table.
    fgathered.hawk_known = true
    fgathered.sniper_known = true
    fgathered.sniper_remaining = 1.0
    fgathered = fST.HUNTER.guide.gather(fST, fgathered)
    eq(fgathered.hawk_known, false, "the hawk gate is overwritten, not stale")
    eq(fgathered.sniper_known, false, "the sniper gate is overwritten, not stale")
    eq(fgathered.sniper_remaining, nil, "the cleared cast removes the stale sniper remaining")
    eq(fgathered.sniper_duration, nil, "the cleared cast removes the stale sniper duration")

    -- Every action the Forever engine can return names a Forever slot, and the
    -- Steady Shot is NOT one of them (the client has no Steady Shot at all).
    do
        local actions = { "hawk", "sniper" }
        local all_resolve = true
        for i = 1, #actions do
            if fui.slot_index[actions[i]] == nil then
                all_resolve = false
            end
        end
        check(all_resolve, "every Forever action names a declared Forever slot")
        eq(fui.slot_index["steady"], nil,
            "the Forever frame declares no Steady slot (the client has no Steady Shot)")
    end

    -- The Forever tick through the real hook lights nothing (no Steady Shot to
    -- fill with); the window still holds there (conservative, pinned at the pure
    -- level too).
    local function ftarget(key) return fui.icons[fui.slot_index[key]].fade.target end
    local function any_target_lit()
        for i = 1, #fui.icons do
            if fui.icons[i].fade.target > 0 then return true end
        end
        return false
    end
    local function ftick()
        fST.mainhand = { speed = 3.0, ends_at = fw.clock + 3.0, start = fw.clock,
            is_full = false }
        fw.advance(0.1)
        fST.HUNTER.on_bar_update(fST, "mainhand")
    end
    ftick()
    eq(any_target_lit(), false, "Forever tick: no slot lights (the client has no Steady Shot)")
    eq(ftarget("hawk"), 0, "Forever tick: the unconfirmed hawk slot stays dark")
    eq(ftarget("sniper"), 0, "Forever tick: the unconfirmed sniper slot stays dark")
    eq(fui.frame.hold.fade.target, 0, "Forever tick: no prompt shows no hold")
    eq(fui.frame.shown, true, "Forever tick: the frame shows in combat")
    -- The window still holds there (conservative, pinned at the pure level too).
    -- Only a current-cycle cache counts, so the tick advances into the live
    -- cycle's window instead of injecting a synthetic off-cycle cache.
    fw.advance(1.3)
    ftick()
    eq(fui.frame.hold.fade.target, 1, "Forever tick: the window shows the hold overlay")
    eq(fui.frame.hold.text.text, "HOLD", "Forever tick: the window reads HOLD")
    eq(any_target_lit(), false, "Forever tick: the window suppresses every prompt")
end

--=========================================================================================
-- 3) The display mapping through the real frame and the real hooks
--=========================================================================================
ST.in_combat = true
ST.mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false }
ST.ranged = { start = 0, speed = 3.0, ends_at = 0, auto_repeat_active = true }
ST.latency = { world_ms = 50 }
ST.raptor_strike_queued = false
ST.steady_shot_queued = false
sandbox.cast = nil
sandbox.cooldowns = {}
sandbox.clock = 200

local function tick(advance, ranged_ends_in)
    ST.mainhand.ends_at = sandbox.clock + 3.0
    local ends_in = ranged_ends_in or 2.0
    ST.ranged.start = sandbox.clock + ends_in - 3.0
    ST.ranged.ends_at = sandbox.clock + ends_in
    sandbox.advance(advance or 0.1)
    ST.HUNTER.on_bar_update(ST, "mainhand")
end
local function target(key)
    return ui.icons[ui.slot_index[key]].fade.target
end
local function slot_icon(key)
    return ui.icons[ui.slot_index[key]].icon
end

-- The baseline Steady tick (Wrath filler: nothing else learned on this client).
tick()
eq(target("steady"), 1, "the baseline tick lights the Steady slot through the real hook")
eq(target("chimera"), 0, "the unlearned Chimera slot stays dark")
eq(ui.frame.hold.fade.target, 0, "the steady tick shows no hold overlay")
eq(ui.frame.shown, true, "the in-combat tick shows the frame")

-- The live Steady cast: RIDE, no action icon, and the cast-fed swipe.
sandbox.cast = { name = "Steady Shot", spell_id = 49052,
    start = sandbox.clock + 0.1, ["end"] = sandbox.clock + 0.9 }
tick()
eq(target("steady"), 0, "the live Steady cast suppresses the steady prompt")
eq(target("chimera"), 0, "the unlearned Chimera slot stays dark during the ride")
eq(ui.frame.hold.fade.target, 1, "the live Steady cast shows the hold overlay")
eq(ui.frame.hold.text.text, "RIDE", "the live Steady cast reads RIDE")
eq(slot_icon("steady").cooldown.cooldown_sets, 1, "the live-cast swipe is set once")
near(slot_icon("steady").cooldown.cooldown_duration, 0.8, 1e-9,
    "the swipe length is the live cast's own length")
eq(slot_icon("steady").cooldown_set, true, "the swipe latch is armed")
tick()
eq(slot_icon("steady").cooldown.cooldown_sets, 1, "the swipe latch holds across ticks")
sandbox.cast = nil
tick()
eq(slot_icon("steady").cooldown.cooldown_sets, 2, "the ended cast clears the swipe")
eq(slot_icon("steady").cooldown.cooldown_duration, 0, "the clear is a zero-length cooldown")
eq(slot_icon("steady").cooldown_set, false, "the swipe latch resets on clear")
eq(ui.frame.hold.fade.target, 0, "the ended cast clears the ride")
eq(target("steady"), 1, "with the cast ended the steady prompt returns")

-- The hidden window never holds on Wrath (no auto-shot management on WotLK):
-- the filler prompt persists straight through it, with no overlay.
ST.ranged.hidden_window_start = sandbox.clock - 0.2
ST.ranged.hidden_window_duration = 0.5
tick()
eq(target("steady"), 1, "Wrath: the window never suppresses the filler prompt")
eq(ui.frame.hold.fade.target, 0, "Wrath: the window shows no hold overlay")
ST.ranged.hidden_window_start = sandbox.clock - 1.0
ST.ranged.hidden_window_duration = 0.5
tick()
eq(ui.frame.hold.fade.target, 0, "past the window there is still no hold")
eq(target("steady"), 1, "past the window the steady prompt persists")
ST.ranged.hidden_window_start = nil
ST.ranged.hidden_window_duration = nil

-- A real Steady cooldown withholds; a queue then rides it.
sandbox.cooldowns = { [49052] = { sandbox.clock, 6 } }
tick()
eq(target("steady"), 0, "a real Steady cooldown suppresses the prompt")
eq(ui.frame.hold.fade.target, 0, "a cooldown with nothing queued shows no hold")
ST.raptor_strike_queued = true
tick()
eq(target("steady"), 0, "a queued raptor with Steady on cooldown shows no action")
eq(ui.frame.hold.fade.target, 1, "the queued state shows the hold overlay")
eq(ui.frame.hold.text.text, "RIDE", "the queued state reads RIDE")
ST.raptor_strike_queued = false
sandbox.cooldowns = {}
tick()
eq(target("steady"), 1, "with Steady ready the prompt returns")
ST.steady_shot_queued = true
tick()
eq(target("steady"), 1, "rule W6 outranks the queued ride (Steady is the next press)")
eq(ui.frame.hold.fade.target, 0, "the queued ride waits behind the steady prompt")
ST.steady_shot_queued = false

-- A closing window still prompts the filler (no clip check on Wrath); a queue
-- behind a silenced filler rides.
tick(nil, 0.8)
eq(target("steady"), 1, "Wrath: a closing window still prompts the filler")
eq(ui.frame.hold.fade.target, 0, "a ready filler shows no hold")
sandbox.cooldowns = { [49052] = { sandbox.clock, 6 } }
ST.raptor_strike_queued = true
tick(nil, 0.8)
eq(target("steady"), 0, "a closing window with the filler cooling down shows no action")
eq(ui.frame.hold.fade.target, 1, "a closing window with a queue rides")
eq(ui.frame.hold.text.text, "RIDE", "the closing-window ride reads RIDE")
ST.raptor_strike_queued = false
sandbox.cooldowns = {}
tick()

-- Absent ranged state: the Wrath filler needs no cycle, so the prompt persists
-- (on Retail the family short-circuit keeps the frame empty instead - pinned in
-- the Retail section below).
ST.ranged = nil
sandbox.advance(0.1)
ST.HUNTER.on_bar_update(ST, "mainhand")
eq(target("steady"), 1, "Wrath: no ranged state still prompts the filler")
eq(ui.frame.hold.fade.target, 0, "no ranged state shows no hold")
ST.ranged = { start = 0, speed = 3.0, ends_at = 0, auto_repeat_active = true }

-- Option gates: disabled hides the frame and stops the mapping; visibility follows the
-- in-combat key; the size/position/lock diff applies live.
local before_disable = target("steady")
class_db.nextaction_enabled = false
tick()
eq(ui.frame.shown, false, "nextaction_enabled=false hides the frame")
eq(target("steady"), before_disable, "the gated tick leaves the slot targets alone")
class_db.nextaction_enabled = true
tick()
eq(ui.frame.shown, true, "re-enabling brings the frame back")
class_db.nextaction_visibility_key = "always"
ST.in_combat = false
tick()
eq(ui.frame.shown, true, "the always visibility key keeps the frame out of combat")
class_db.nextaction_visibility_key = "in_combat"
tick()
eq(ui.frame.shown, false, "the in_combat key hides the frame out of combat")
ST.in_combat = true
tick()
eq(ui.frame.shown, true, "back in combat the frame returns")

class_db.nextaction_icon_size = 60
class_db.nextaction_locked = false
tick()
near(ui.frame.scale, 60 / 45, 1e-9, "the icon-size option rescales the live frame")
eq(ST.guide_ui_icon_size, 60, "the settings diff latches the applied size")
eq(ui.frame.movable, true, "unlocking makes the frame movable")
class_db.nextaction_x = 25
class_db.nextaction_icon_size = 45
class_db.nextaction_locked = true
tick()
near(ui.frame.scale, 1, 1e-9, "the size option restores the scale")
eq(ui.frame.movable, false, "locking makes the frame immovable again")
eq(ui.frame.points and ui.frame.points[1][4], 25, "the position option moves the live frame")

-- The hand gates: even with a state change a real tick would map, the ranged tick never
-- maps (the shared ui gates on the mainhand hand) and offhand stops at the class hook's
-- own gate.
local before_ranged = target("steady")
ST.ranged = nil
sandbox.advance(1.0)
ST.HUNTER.on_bar_update(ST, "ranged")
eq(target("steady"), before_ranged,
    "the ranged tick leaves the mapping alone (the shared ui gates on the mainhand hand)")
local before_offhand = target("steady")
sandbox.advance(1.0)
ST.HUNTER.on_bar_update(ST, "offhand")
eq(target("steady"), before_offhand, "the offhand call does not tick the guide")
ST.ranged = { start = 0, speed = 3.0, ends_at = 0, auto_repeat_active = true }

--=========================================================================================
-- 4) Config/options parity, the TOC load order and the drive call sites
--=========================================================================================
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    local presets = read("config_presets.lua")
    local hunter_defaults = presets:match("ST%.HUNTER%.defaults%s*=%s*%{(.-)ST%.MAGE%.defaults")
        or ""
    local options = read("option_tables.lua")
    local hunter_opts = options:match(
        "function ST%.class_opts_funcs%.HUNTER%((.-)function ST%.class_opts_funcs%.DRUID%(")
        or ""

    local expected_defaults = {
        nextaction_enabled = "true",
        nextaction_locked = "true",
        nextaction_visibility_key = "\"in_combat\"",
        nextaction_icon_size = "45",
        nextaction_x = "0",
        nextaction_y = "-180",
    }
    for key, value in pairs(expected_defaults) do
        check(hunter_defaults:find("%f[%a_]" .. key .. "%s*=%s*" .. value, 1) ~= nil,
            "config_presets.lua: HUNTER default " .. key .. " = " .. value)
    end

    local widget_types = {
        nextaction_enabled = "toggle",
        nextaction_locked = "toggle",
        nextaction_visibility_key = "select",
        nextaction_icon_size = "range",
        nextaction_x = "input",
        nextaction_y = "input",
    }
    for key, wtype in pairs(widget_types) do
        local widget = hunter_opts:match("%f[%a_]" .. key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"" .. wtype .. "\"") ~= nil,
            "option_tables.lua: " .. key .. " has a " .. wtype .. " widget")
    end
    check(hunter_opts:find("Next Action Guide") ~= nil,
        "option_tables.lua: the hunter options carry a Next Action Guide block")
    check(hunter_opts:find("nag_header") ~= nil and hunter_opts:find("nag_desc") ~= nil,
        "option_tables.lua: the hunter block carries the header/description pair")

    -- hunter_guide.lua loads after nextaction.lua in every TOC.
    local tocs = { "SwedgeTimer.toc", "SwedgeTimer_Vanilla.toc", "SwedgeTimer_TBC.toc",
        "SwedgeTimer_Wrath.toc", "SwedgeTimer_Mainline.toc", "SwedgeTimer_Cata.toc",
        "SwedgeTimer_Mists.toc" }
    for i = 1, #tocs do
        local text = read(tocs[i])
        local after = text:find("\nnextaction.lua", 1, true)
        local guide_at = text:find("\nhunter_guide.lua", 1, true)
        check(after ~= nil and guide_at ~= nil and guide_at > after,
            tocs[i] .. ": hunter_guide.lua loads after nextaction.lua")
    end

    -- The drive call sites live in classes/hunter.lua.
    local hunter_src = read("classes/hunter.lua")
    check(hunter_src:find("st%.nextaction_ui%.init%(self%)") ~= nil,
        "classes/hunter.lua: post_init drives st.nextaction_ui.init")
    check(hunter_src:find("st%.nextaction_ui%.on_bar_update%(self, hand%)") ~= nil,
        "classes/hunter.lua: on_bar_update drives st.nextaction_ui.on_bar_update")
    check(hunter_src:find("st%.nextaction_ui%.apply_settings%(self%)") ~= nil,
        "classes/hunter.lua: the settings diff applies live")
    check(hunter_src:find("self%.HUNTER%.resolve_guide_icons%(%)") ~= nil,
        "classes/hunter.lua: post_init resolves the guide icons")
    check(hunter_src:find("aimed_shot_ids") ~= nil,
        "classes/hunter.lua: the Era Aimed Shot rank table is declared")
    check(hunter_src:find("guide_slots_era") ~= nil,
        "classes/hunter.lua: the Era slot set is declared")
    check(hunter_src:find('key%s*=%s*"aimed"') ~= nil,
        "classes/hunter.lua: the aimed slot is declared")
    check(hunter_src:find("guide_slots_wrath") ~= nil,
        "classes/hunter.lua: the Wrath slot set is declared")
    check(hunter_src:find("guide_slots_era_sod") ~= nil,
        "classes/hunter.lua: the Era-SoD slot set is declared")
    check(hunter_src:find("chimera_shot_sod_ids") ~= nil,
        "classes/hunter.lua: the SoD Chimera rune table is declared")
    check(hunter_src:find("chimera_shot_wrath_ids") ~= nil,
        "classes/hunter.lua: the Wrath Chimera rank table is declared")
    check(hunter_src:find("explosive_shot_ids") ~= nil,
        "classes/hunter.lua: the Explosive Shot rank table is declared")
    check(hunter_src:find("kill_shot_ids") ~= nil,
        "classes/hunter.lua: the Kill Shot rank table is declared")
    check(hunter_src:find("arcane_shot_ids") ~= nil,
        "classes/hunter.lua: the Arcane Shot rank table is declared")
    check(hunter_src:find("summon_hawk_ids") ~= nil,
        "classes/hunter.lua: the Summon Hawk table is declared (UNCONFIRMED)")
    check(hunter_src:find("sniper_shot_ids") ~= nil,
        "classes/hunter.lua: the Sniper Shot table is declared (UNCONFIRMED)")
    check(hunter_src:find("guide_slots_forever") ~= nil,
        "classes/hunter.lua: the Forever slot set is declared")
    check(hunter_src:find('key%s*=%s*"hawk"') ~= nil,
        "classes/hunter.lua: the hawk slot is declared")
    check(hunter_src:find('key%s*=%s*"sniper"') ~= nil,
        "classes/hunter.lua: the sniper slot is declared")
    check(hunter_src:find('key%s*=%s*"kill_shot"') ~= nil,
        "classes/hunter.lua: the kill_shot slot is declared")
    check(hunter_src:find('key%s*=%s*"chimera"') ~= nil,
        "classes/hunter.lua: the chimera slot is declared")
    check(hunter_src:find('key%s*=%s*"explosive"') ~= nil,
        "classes/hunter.lua: the explosive slot is declared")
    check(hunter_src:find('key%s*=%s*"arcane"') ~= nil,
        "classes/hunter.lua: the arcane slot is declared")
    check(hunter_src:find("is_spell_known") ~= nil,
        "classes/hunter.lua: the spec/rune detection reads spell knowledge")
    -- Rule F1 (Summon Hawk upkeep) is declared but not yet implemented: the
    -- markers must stay until a confirmed hawk-count source lands.
    check(hunter_src:find("NOT YET IMPLEMENTED (rule F1)", 1, true) ~= nil,
        "classes/hunter.lua: the hawk upkeep is marked not-yet-implemented")
    local guide_src = read("hunter_guide.lua")
    check(guide_src:find("NOT YET IMPLEMENTED", 1, true) ~= nil,
        "hunter_guide.lua: rule F1 is marked not-yet-implemented")
end

--=========================================================================================
-- Retail (12.x) inertness: the stand-in reports no ranged cycle, but live casts,
-- cooldown-shaped reads and queue flags answer on Retail - every such shape must
-- stay empty.
--=========================================================================================
do
    local saved_family = pure.family
    pure.family = "RETAIL"
    -- The full baseline (clip-safe Steady) stays silent.
    local out = evaluate({})
    eq(out.action, nil, "retail: a clip-safe Steady never prompts")
    eq(out.hold, false, "retail: a clip-safe Steady never holds")
    eq(out.hold_text, nil, "retail: a clip-safe Steady carries no hold text")
    -- A live cast never rides.
    local live = evaluate({ steady_remaining = 0.5 })
    eq(live.action, nil, "retail: a live Steady cast never prompts")
    eq(live.hold, false, "retail: a live Steady cast never rides")
    eq(live.hold_text, nil, "retail: a live Steady cast carries no RIDE text")
    -- A queued ability never rides.
    local queued = evaluate({ raptor_strike_queued = true })
    eq(queued.hold, false, "retail: a queued Raptor Strike never rides")
    -- The TBC instant shape (forged inputs) never prompts.
    eq(evaluate({ kc_known = true }).action, nil,
        "retail: Kill Command never prompts")
    -- The Forever shapes (forged inputs) never prompt either.
    eq(evaluate({ hawk_known = true, hawk_active_count = 1 }).action, nil,
        "retail: Summon Hawk never prompts")
    eq(evaluate({ sniper_known = true, sniper_remaining_cd = nil,
        sniper_cast_seconds = 4.0, latency = 0.03,
        synced_duration = 4.56 }).action, nil,
        "retail: Sniper Shot never prompts")
    eq(evaluate({ sniper_known = true, sniper_remaining = 2.0 }).hold, false,
        "retail: a live Sniper cast never rides")
    -- The Wrath/SoD shapes (forged inputs) never prompt either.
    eq(evaluate({ killshot_known = true, target_hp_frac = 0.10 }).action, nil,
        "retail: Kill Shot never prompts")
    eq(evaluate({ chimera_known = true }).action, nil,
        "retail: Chimera never prompts")
    eq(evaluate({ explosive_known = true, wrath_aimed_known = true,
        arcane_known = true }).action, nil,
        "retail: the Wrath priority never prompts")
    -- The hidden-window shape never holds.
    local windowed = evaluate({ hidden_window_start = 99.9, hidden_window_duration = 0.5 })
    eq(windowed.hold, false, "retail: the hidden window never holds")
    eq(windowed.hold_text, nil, "retail: the hidden window carries no HOLD text")
    eq(windowed.waiting_judgement, false, "retail: the judgement carry stays false")
    -- A stale out table is fully overwritten (no frozen field survives).
    local stale = { action = "steady", hold = true, hold_text = "RIDE",
        filler_slot = "steady", judge_slot = "x", rotation_key = "y",
        waiting_judgement = true, effective_weapon_speed = 9.9,
        steady_ratio = "stale" }
    local ret = hg.evaluate(inp({}), stale)
    eq(ret, stale, "retail: evaluate returns the caller's out table")
    eq(stale.action, nil, "retail: a stale action is cleared")
    eq(stale.hold, false, "retail: a stale hold is cleared")
    eq(stale.hold_text, nil, "retail: stale hold text is cleared")
    eq(stale.filler_slot, nil, "retail: a stale filler_slot is cleared")
    eq(stale.judge_slot, nil, "retail: a stale judge_slot is cleared")
    eq(stale.rotation_key, nil, "retail: a stale rotation_key is cleared")
    eq(stale.waiting_judgement, false, "retail: a stale judgement carry is cleared")
    eq(stale.effective_weapon_speed, nil, "retail: a stale eWS is cleared")
    eq(stale.steady_ratio, nil, "retail: a stale ratio is cleared")
    -- The gate is Retail-specific: any other family still prompts.
    pure.family = "TBC"
    eq(evaluate({}).action, "steady",
        "non-retail family: a clip-safe Steady still prompts")
    pure.family = saved_family
end

-- Weave band mapping (hunter_wa_map Secs 1-3, wago J3U7jOhMI Mode 3): the Dynamic
-- switch mapped onto our model. The band is carried but no rule reads it
-- (filed arm): forged values change nothing, and the 2b HOLD fires on the
-- range probe alone in every band (the unshootable leg of the switch).
do
    eq(evaluate({ weave_band = "melee" }).action, "steady",
        "band: a forged melee band prompts nothing by itself")
    eq(evaluate({ weave_band = "ranged" }).action, "steady",
        "band: a forged ranged band prompts nothing by itself")
    eq(evaluate({ weave_band = "out_of_range" }).action, "steady",
        "band: a forged far band prompts nothing by itself")
    eq(evaluate({ weave_band = "bogus" }).action, "steady",
        "band: a garbage band prompts nothing by itself")
    eq(evaluate({ weave_band = "melee" }).hold, false,
        "band: a forged melee band raises no overlay either")
    eq(evaluate({ weave_band = "melee" }).hold_text, nil,
        "band: a forged melee band writes no hold text either")
    eq(evaluate({ steady_known = false }).action, nil,
        "band: unknown band with nothing due stays silent")
    eq(evaluate({ steady_known = false, weave_band = "melee" }).action, nil,
        "band: forged melee with nothing due stays silent")
    eq(evaluate({ steady_known = false, weave_band = "melee" }).hold, false,
        "band: forged melee with nothing due raises no overlay either")
    eq(evaluate({ target_in_range = 0, weave_band = "melee" }).hold_text, "HOLD",
        "band: 2b holds in the melee band on a 0 probe")
    eq(evaluate({ target_in_range = 0, weave_band = "ranged" }).hold_text, "HOLD",
        "band: 2b holds in the ranged band on a 0 probe")
    eq(evaluate({ target_in_range = 0 }).hold_text, "HOLD",
        "band: 2b holds with unknown band on a 0 probe")
end

-- Rotation-text tiers (hunter_wa_map §1, wago eEJOoHci- TBC pack): the WA
-- speed→label readout as pure data + lookup. CLIENT-OBSERVED, SIM-UNCONFIRMED,
-- display-only (evaluate never reads them). Custom texts/colors stay filed
-- with the WA option keys (options scope); the tables carry the WA defaultText
-- labels only.
do
    local std = hg.ROTATION_TIERS_STANDARD
    local weave = hg.ROTATION_TIERS_WEAVE
    check(type(std) == "table" and type(weave) == "table",
        "tiers: both WA tables are declared")
    eq(#std, 9, "tiers: Standard carries the WA 9 tiers")
    eq(#weave, 5, "tiers: Melee Weave carries the WA 5 tiers")
    local want_std = {
        { 2.33, "5:4:1:1" }, { 1.95, "5:5:1:1" }, { 1.74, "5:6:1:1" },
        { 1.27, "1:1" }, { 1.09, "5:9:1:1" }, { 0.90, "2:3" },
        { 0.70, "1:2" }, { 0.57, "2:5" }, { 0, "1:3" },
    }
    for i = 1, #want_std do
        eq(std[i].speed_gt, want_std[i][1],
            "tiers: Standard tier " .. i .. " thresholds the WA " .. want_std[i][1])
        eq(std[i].label, want_std[i][2],
            "tiers: Standard tier " .. i .. " labels the WA " .. want_std[i][2])
    end
    local want_weave = {
        { 1.83, "5:5:1:1 3w" }, { 1.62, "2:2 1w" }, { 1.22, "6:9:1:1 3w" },
        { 0.94, "6:11:1:1 3w" }, { 0, "3:7 2w" },
    }
    for i = 1, #want_weave do
        eq(weave[i].speed_gt, want_weave[i][1],
            "tiers: Weave tier " .. i .. " thresholds the WA " .. want_weave[i][1])
        eq(weave[i].label, want_weave[i][2],
            "tiers: Weave tier " .. i .. " labels the WA " .. want_weave[i][2])
    end

    -- Lookup: first threshold the speed strictly exceeds wins (WA verbatim).
    eq(hg.rotation_tier(3.0), "5:4:1:1", "tier: a fast cycle reads the top tier")
    eq(hg.rotation_tier(2.33, 1), "5:5:1:1",
        "tier boundary: equality falls through (strict >)")
    eq(hg.rotation_tier(1.96, 1), "5:5:1:1", "tier: just above 1.95 reads 5:5:1:1")
    eq(hg.rotation_tier(1.95, 1), "5:6:1:1", "tier boundary: 1.95 falls through")
    eq(hg.rotation_tier(0.5, 1), "1:3", "tier: a slow cycle reads the bottom tier")
    eq(hg.rotation_tier(0, 1), "1:3", "tier: zero reads the bottom tier")
    eq(hg.rotation_tier(2.0, 2), "5:5:1:1 3w", "tier: mode 2 reads the weave table")
    eq(hg.rotation_tier(1.83, 2), "2:2 1w", "tier boundary: weave equality falls through")
    eq(hg.rotation_tier(0.5, 2), "3:7 2w", "tier: weave bottom tier")
    -- Mode default + the filed dynamic 3 read Standard (the WA's no-target default).
    eq(hg.rotation_tier(3.0, nil), "5:4:1:1", "tier: a nil mode reads Standard")
    eq(hg.rotation_tier(3.0, 3), "5:4:1:1", "tier: the filed mode 3 reads Standard")
    eq(hg.rotation_tier(3.0, 99), "5:4:1:1", "tier: a bogus mode reads Standard")
    -- Unknown speed never guesses.
    eq(hg.rotation_tier(nil), nil, "tier: nil speed reads nil")
    eq(hg.rotation_tier(0 / 0), nil, "tier: NaN speed reads nil")
    eq(hg.rotation_tier("2.5"), nil, "tier: a non-number reads nil")

    -- Display-only: no tier input exists and evaluate never calls the lookup.
    local f = assert(io.open(ROOT .. "hunter_guide.lua", "r"))
    local src = f:read("*a")
    f:close()
    local _, defs = src:gsub("rotation_tier%s*%(", "")
    eq(defs, 1, "tier: the lookup is defined once and never called in-engine")
    check(src:find("inputs%.rotation", 1, true) == nil,
        "tier: the frozen input set carries no tier field")
    eq(evaluate({}).action, "steady",
        "tier: the engine baseline is unchanged by the readout")
end

--=========================================================================================
-- 6) The practice contract: the rotation table, the scenario step and the class drills
--=========================================================================================
-- The shared engine looks the hunter up by player_class and reads three things
-- (the orchestrator's contract, 2026-10-19):
--   ST.HUNTER.practice_rotation       the family's shot priority in the sim's order
--   ST.HUNTER.practice_scenario_step  the expected action at one decision
--   ST.HUNTER.practice_drills         the class drills (key + label + grade)
-- The pins below prove the shape, the per-family order, the sim citations and the
-- fact that the scenario reuses the SAME engine the live guide uses.
local GUIDE_ACTIONS = {
    kill_shot = true, chimera = true, explosive = true, arcane = true, aimed = true,
    multi = true, steady = true, kill_command = true, bestial_wrath = true,
    rapid_fire = true, hawk = true, sniper = true,
    -- The APL UTILITY layer (the utility lane, 2026-10-20): the engine has an
    -- arm for each of these now, so they are engine-facing rows too.
    serpent = true, raptor_strike = true, wyvern_strike = true,
    aspect_viper = true, aspect_hawk = true, aspect_falcon = true,
    aspect_dragonhawk = true, wing_clip = true, mongoose_bite = true,
    immolation_trap = true, hunters_mark = true, silencing_shot = true,
    explosive_trap = true, black_arrow = true,
}

do
    local H = ST.HUNTER
    check(type(H.practice_rotation) == "table", "the hunter exposes practice_rotation")
    check(type(H.practice_scenario_step) == "function", "the hunter exposes practice_scenario_step")
    check(type(H.practice_drills) == "table", "the hunter exposes practice_drills")

    -- The per-family tables: the ENGINE-facing rows (the actions the frozen engine
    -- can emit) plus the APL's SPINE rows (the utility/upkeep layer the engine has
    -- no arm for - the APL gap analysis, bench/rotation_gap_vs_apl_2026-10-20.md §2).
    -- Every row carries the same shape: an action, a label, the spell id + name, the
    -- family gate, the live flag and the source.
    local rotations = H.PRACTICE_ROTATIONS
    check(type(rotations) == "table", "the per-family rotation tables exist")
    local families = { "ERA", "SOD", "TBC", "WRATH", "FOREVER" }
    for i = 1, #families do
        local family = families[i]
        local table_for = rotations[family]
        check(type(table_for) == "table" and #table_for > 0,
            "the " .. family .. " rotation table exists and is not empty")
        local engine_rows = 0
        for j = 1, #table_for do
            local entry = table_for[j]
            check(type(entry.action) == "string" and entry.action ~= "",
                "the " .. family .. " rotation entry names an action (" .. tostring(entry.action) .. ")")
            check(type(entry.label) == "string" and entry.label ~= "",
                "the " .. family .. " rotation entry carries a label")
            check(type(entry.source) == "string"
                and (entry.source:find("wowsims") ~= nil or entry.source:find("docs/research") ~= nil),
                "the " .. family .. " rotation entry cites a sim or research source")
            -- The family gate rides on the line: the table is read per family, so
            -- every row names the family whose SIM plays it.
            check(type(entry.families) == "table" and #entry.families == 1
                and entry.families[1] == family,
                "the " .. family .. " rotation entry is gated on its own family ("
                    .. tostring(entry.action) .. ")")
            -- The live flag: the read exists (true) or the row names the read it is
            -- waiting for (false).
            check(type(entry.live) == "boolean",
                "the " .. family .. " rotation entry carries the live flag ("
                    .. tostring(entry.action) .. ")")
            -- HU-13's engine flag is a STRICT BOOLEAN too: a truthiness test
            -- (entry.engine ~= false) would pass for nil, 0 and any truthy
            -- string, and a row with no arm must never look engine-facing.
            check(type(entry.engine) == "boolean",
                "the " .. family .. " rotation entry carries the engine flag ("
                    .. tostring(entry.action) .. ")")
            -- The cross-row rule (the other five classes enforce it): a row that
            -- waits for a read names that read - never an empty `needs`.
            if entry.live == false then
                check(type(entry.needs) == "string" and entry.needs ~= "",
                    "the " .. family .. " rotation row files the read it needs ("
                        .. tostring(entry.action) .. ")")
            end
            -- The id + name pair: the TBC client resolves by NAME and the Era client
            -- by ID, so a row that names a spell carries both.
            if entry.spell_id ~= nil then
                check(type(entry.spell_name) == "string" and entry.spell_name ~= "",
                    "the " .. family .. " rotation row carries the spell name ("
                        .. tostring(entry.action) .. ")")
            end
            if entry.engine == true then
                engine_rows = engine_rows + 1
                check(GUIDE_ACTIONS[entry.action] == true,
                    "the " .. family .. " engine-facing rotation names a guide action ("
                        .. tostring(entry.action) .. ")")
            end
        end
        check(engine_rows > 0, "the " .. family .. " rotation keeps its engine-facing rows")
    end

    -- The compiled order: the engine-facing rows first (the order the guide plays
    -- them), then the APL's spine rows in the APL's own priority order.
    local function order_of(family)
        local names = {}
        for i = 1, #rotations[family] do names[i] = rotations[family][i].action end
        return table.concat(names, ",")
    end
    eq(order_of("ERA"), "aimed,multi,rapid_fire,serpent",
        "the Era rotation is Aimed, Multi, then the Rapid Fire and Serpent rows")
    eq(order_of("SOD"),
        "chimera,aimed,multi,rapid_fire,kill_shot,raptor_strike,wyvern_strike,aspect_viper,arcane,aspect_falcon,wing_clip",
        "the SoD rotation is Chimera, Aimed, Multi, then the APL's spine rows")
    eq(order_of("TBC"),
        "kill_command,bestial_wrath,rapid_fire,arcane,multi,steady,aspect_viper,aspect_hawk",
        "the TBC rotation is KC, BW, RF, Arcane, Multi, Steady, then the mana-swap rows")
    eq(order_of("WRATH"),
        "kill_shot,chimera,explosive,aimed,arcane,steady,aspect_viper,aspect_dragonhawk,silencing_shot,serpent,explosive_trap,multi,black_arrow",
        "the Wrath rotation is the six-arm priority, then the APL's spine rows")
    eq(order_of("FOREVER"),
        "hawk,sniper,raptor_strike,hunters_mark,mongoose_bite,immolation_trap,wing_clip,serpent,arcane,multi,aimed",
        "the Forever rotation is the hawk upkeep, the Sniper cast and the APL's spine rows (the Steady Shot row is gone: the Forever client has no Steady Shot)")

    -- The APL's UTILITY LAYER (the operator's "a rotation that only carries the
    -- damage abilities is not the class's rotation"): the Serpent Sting upkeep, the
    -- aspect swaps and the Kill Shot execute, each with the id its family's APL
    -- casts. The Serpent Sting ranks are 13554 / 25295 / 49001 (SIM-CONFIRMED) and
    -- the read is name-first (the TBC client resolves by name).
    local function row_for(family, action)
        for i = 1, #rotations[family] do
            if rotations[family][i].action == action then
                return rotations[family][i]
            end
        end
        return nil
    end
    eq(row_for("ERA", "serpent").spell_id, 25295, "the Era Serpent row carries the APL's 25295")
    eq(row_for("FOREVER", "serpent").spell_id, 25295, "the Forever Serpent row carries the APL's 25295")
    eq(row_for("WRATH", "serpent").spell_id, 49001, "the Wrath Serpent row carries the APL's 49001")
    eq(row_for("TBC", "aspect_viper").spell_id, 34074, "the TBC Viper row carries the APL's 34074")
    eq(row_for("SOD", "aspect_viper").spell_id, 415423, "the SoD Viper row carries the APL's 415423")
    eq(row_for("WRATH", "aspect_viper").spell_id, 34074, "the Wrath Viper row carries the APL's 34074")
    eq(row_for("TBC", "aspect_hawk").spell_id, 27044, "the TBC Hawk row carries the APL's 27044")
    eq(row_for("SOD", "aspect_falcon").spell_id, 469145, "the SoD Falcon row carries the APL's 469145")
    eq(row_for("WRATH", "aspect_dragonhawk").spell_id, 61847,
        "the Wrath Dragonhawk row carries the APL's 61847")
    eq(row_for("SOD", "kill_shot").spell_id, 409593, "the SoD Kill Shot row carries the APL's 409593")
    -- The id FIXES: the WotLK APLs cast 61006 and 60053/60052, not the client's
    -- rank-1 ids the rows used to cite.
    eq(row_for("WRATH", "kill_shot").spell_id, 61006,
        "the Wrath Kill Shot row cites the APL's 61006, not the rank-1 53351")
    eq(row_for("WRATH", "explosive").spell_id, 60053,
        "the Wrath Explosive row cites the APL's 60053, not the rank-1 53301")
    eq(row_for("TBC", "steady").spell_id, 34120,
        "the TBC Steady row cites the TBC rank 34120, not the WotLK rank-1 56641")
    -- The HU-12 ruling: the rotation carries the APL's SPELL rows; the APL's
    -- PRE-PULL rows stay in the prepull table (the SoD's Serpent Sting is one).
    eq(row_for("SOD", "serpent"), nil, "the SoD serpent stays a pre-pull row (HU-12)")
    eq(ST.HUNTER.PRACTICE_PREPULLS.SOD[5].action, "serpent",
        "the SoD serpent pre-pull row is still in the prepull table")

    -- The ENGINE-FACING slice: the panel's action vocabulary and the engine's
    -- inputs. Since the APL UTILITY lane (2026-10-20) every row whose read and
    -- whose engine arm landed is engine-facing, so the slice is the family's
    -- WHOLE spine - the panel can ask for every line the engine can emit.
    local function engine_order_of(family)
        local names = {}
        local slice = H.practice_rotation_for(family)
        for i = 1, #slice do names[i] = slice[i].action end
        return table.concat(names, ",")
    end
    eq(engine_order_of("ERA"), "aimed,multi,rapid_fire,serpent",
        "the Era engine slice is the whole Era spine")
    eq(engine_order_of("SOD"),
        "chimera,aimed,multi,rapid_fire,kill_shot,raptor_strike,wyvern_strike,aspect_viper,arcane,aspect_falcon,wing_clip",
        "the SoD engine slice is the whole SoD spine")
    eq(engine_order_of("TBC"),
        "kill_command,bestial_wrath,rapid_fire,arcane,multi,steady,aspect_viper,aspect_hawk",
        "the TBC engine slice is the whole TBC spine")
    eq(engine_order_of("WRATH"),
        "kill_shot,chimera,explosive,aimed,arcane,steady,aspect_viper,aspect_dragonhawk,silencing_shot,serpent,explosive_trap,multi,black_arrow",
        "the Wrath engine slice is the whole thirteen-row spine")
    eq(engine_order_of("FOREVER"),
        "hawk,sniper,raptor_strike,hunters_mark,mongoose_bite,immolation_trap,wing_clip,serpent,arcane,multi",
        "the Forever engine slice is the whole Forever spine")
    for i = 1, #families do
        local family = families[i]
        local slice = H.practice_rotation_for(family)
        local slice_actions = {}
        for j = 1, #slice do slice_actions[slice[j].action] = true end
        for j = 1, #rotations[family] do
            local entry = rotations[family][j]
            if entry.engine == false then
                eq(slice_actions[entry.action], nil,
                    "the " .. family .. " spine row " .. tostring(entry.action)
                        .. " stays out of the engine slice")
            else
                eq(slice_actions[entry.action], true,
                    "the " .. family .. " row " .. tostring(entry.action)
                        .. " is in the engine slice")
            end
        end
    end

    -- The running client's table: the family's own list, and an empty table on a
    -- client with no sourced rotation (never a guess).
    local function rotation_for(project)
        local sb = build({ project = project })
        return sb.ST.HUNTER.practice_rotation, sb
    end
    local wrath_rotation, wrath_sb = rotation_for(11)
    eq(#wrath_rotation, 13, "the Wrath client reads the six-arm priority plus the APL's spine")
    local running_names = {}
    for i = 1, #wrath_rotation do running_names[i] = wrath_rotation[i].action end
    eq(table.concat(running_names, ","),
        "kill_shot,chimera,explosive,aimed,arcane,steady,aspect_viper,aspect_dragonhawk,silencing_shot,serpent,explosive_trap,multi,black_arrow",
        "the running client reads its own family's table")
    local retail_rotation = rotation_for(1)
    eq(#retail_rotation, 0, "a client with no sourced rotation reads an empty table")
    local cata_rotation = rotation_for(14)
    eq(#cata_rotation, 0, "Cata reads an empty rotation too (no sim in scope)")

    -- The scenario step: the shape, and the engine's own verdict.
    local step = wrath_sb.ST.HUNTER.practice_scenario_step
    local result = step(wrath_sb.ST, { now = 100 })
    check(type(result) == "table", "the scenario step returns a table")
    -- The scenario's default state has EVERY engine-facing row known and off
    -- cooldown (the shipped fixture semantics: a fresh scenario has every
    -- cooldown ready), so the family's TOP APL row leads: the Silencing Shot on
    -- the WotLK MM spine (i=3). A row the ctx puts on cooldown hands the step to
    -- the next one down the spine.
    eq(result.action, "silencing_shot",
        "the Wrath scenario wants the MM spine's top row (the Silencing Shot)")
    check(type(result.reason) == "string" and result.reason ~= "",
        "the scenario step explains itself")
    -- The execute: Kill Shot wins at or under 20% health.
    eq(step(wrath_sb.ST, { now = 100, target_hp_frac = 0.2 }).action, "kill_shot",
        "the Wrath scenario takes the execute")
    eq(step(wrath_sb.ST, { now = 100, target_hp_frac = 0.21 }).action, "silencing_shot",
        "above the execute threshold the Silencing Shot leads")
    -- The cooldown order: a Chimera on cooldown hands the shot to Explosive.
    eq(step(wrath_sb.ST, { now = 100, cooldowns = { silencing_shot = 5 } }).action, "explosive_trap",
        "the Wrath scenario follows the cooldown order (the MM APL's i=6 trap row)")
    eq(step(wrath_sb.ST, { now = 100, cooldowns = { silencing_shot = 5,
        explosive_trap = 5 } }).action, "chimera",
        "the trap on cooldown hands the step to the Chimera")
    -- The buff lines: the scenario carries the aura state from the ctx into the
    -- engine, so a line whose buff is KNOWN DOWN is asked for and one whose
    -- buff is up never is.
    eq(step(wrath_sb.ST, { now = 100, serpent_active = false,
        cooldowns = { silencing_shot = 5, explosive_trap = 5 } }).action, "serpent",
        "the Wrath scenario asks for the Serpent upkeep when the sting is known down")
    eq(step(wrath_sb.ST, { now = 100, serpent_active = true,
        cooldowns = { silencing_shot = 5, explosive_trap = 5 } }).action, "chimera",
        "the Wrath scenario NEVER asks for the Serpent while the sting is up")
    -- An unreadable clock decides nothing.
    eq(step(wrath_sb.ST, { now = "x" }), nil, "an unreadable clock decides nothing")
    eq(step(wrath_sb.ST, nil), nil, "a missing ctx decides nothing")
    eq(step(wrath_sb.ST, { now = 0 / 0 }), nil, "a NaN clock decides nothing")
    -- A client with no sourced rotation decides nothing.
    local retail_sb = build({ project = 1 })
    eq(retail_sb.ST.HUNTER.practice_scenario_step(retail_sb.ST, { now = 100 }), nil,
        "a client with no sourced rotation decides nothing")

    -- The TBC scenario: Kill Command is the first priority, the pops follow it.
    local tbc_sb = build({ project = 5 })
    local tbc_step = tbc_sb.ST.HUNTER.practice_scenario_step
    eq(tbc_step(tbc_sb.ST, { now = 100 }).action, "kill_command",
        "the TBC scenario pops Kill Command first")
    eq(tbc_step(tbc_sb.ST, { now = 100, cooldowns = { kill_command = 5 } }).action,
        "bestial_wrath", "the TBC scenario pops Bestial Wrath behind it")
    eq(tbc_step(tbc_sb.ST, { now = 100,
        cooldowns = { kill_command = 5, bestial_wrath = 5 } }).action, "rapid_fire",
        "the TBC scenario pops Rapid Fire last")

    -- The Era scenario: the weave, and the clip check decides which shot fits.
    local era_sb = build({ project = 2 })
    local era_step = era_sb.ST.HUNTER.practice_scenario_step
    eq(era_step(era_sb.ST, { now = 100 }).action, "rapid_fire",
        "the Era scenario asks for the Era spine's top row (the Rapid Fire, i=1)")
    eq(era_step(era_sb.ST, { now = 100, cooldowns = { rapid_fire = 5 } }).action, "multi",
        "the Rapid Fire on cooldown hands the Era step to the Multi weave")
    -- The cast ride: a cast shot occupies the player, so the next decision rides it.
    -- A ride is a HOLD, and a hold is a DECISION (the operator ruling HU-8): the
    -- step states it, so the engine can punish a cast during the ride.
    local ride_sb = build({ project = 11 })
    local ride_step = ride_sb.ST.HUNTER.practice_scenario_step
    eq(ride_step(ride_sb.ST, { now = 100 }).action, "silencing_shot",
        "the ride scenario starts clean")
    local riding = ride_step(ride_sb.ST, { now = 100, last_action = "steady" })
    check(type(riding) == "table" and riding.hold == true,
        "a cast in progress states an explicit hold")
    eq(riding.action, nil, "the ride hold names no action")
    check(type(riding.reason) == "string" and riding.reason ~= "",
        "the ride hold carries the guide's own caption")
    local riding_now = ride_step(ride_sb.ST, { now = 100.5, last_action = "steady" })
    check(type(riding_now) == "table" and riding_now.hold == true,
        "the ride holds while the cast runs")
    eq(ride_step(ride_sb.ST, { now = 102.0, last_action = "steady" }).action, "silencing_shot",
        "the decision returns when the cast is over")

    -- The drills: the audit's target set (bench/class_features_drills_2026-10-19.md
    -- §2.3 (C)), each with its registry key, a label and a grade function.
    local drills = wrath_sb.ST.HUNTER.practice_drills
    eq(#drills, 4, "the hunter ships the four audited drills")
    local expected_keys = { "hunter_shot_order", "hunter_weave_clip",
        "hunter_kill_command", "hunter_prepull" }
    for i = 1, #expected_keys do
        eq(drills[i].key, expected_keys[i], "drill " .. i .. " carries the audited registry key")
        check(type(drills[i].label) == "string" and drills[i].label ~= "",
            "drill " .. drills[i].key .. " carries a label")
        check(type(drills[i].grade) == "function", "drill " .. drills[i].key .. " grades")
    end

    -- D-H1: the shot priority. The right pick is an S, a wrong pick an F (a
    -- mis-order, not a late pick), and no press grades nothing.
    local order = drills[1].grade
    eq(order(wrath_sb.ST, { now = 100, pressed = "silencing_shot" }), "S",
        "shot order: the shot the rotation wants is an S")
    eq(order(wrath_sb.ST, { now = 100, pressed = "steady" }), "F",
        "shot order: a different shot is a mis-order (F)")
    eq(order(wrath_sb.ST, { now = 100 }), nil, "shot order: no press grades nothing")
    -- The run bands: the mis-pick tally grades the session instead.
    eq(order(wrath_sb.ST, { now = 100, pressed = "chimera", mispicks = 0 }), "S",
        "shot order: a clean run is an S")
    eq(order(wrath_sb.ST, { now = 100, pressed = "chimera", mispicks = 1 }), "A",
        "shot order: one mis-pick is an A")
    eq(order(wrath_sb.ST, { now = 100, pressed = "chimera", mispicks = 3 }), "C",
        "shot order: three mis-picks are a C")
    eq(order(wrath_sb.ST, { now = 100, pressed = "chimera", mispicks = 9 }), "F",
        "shot order: nine mis-picks are an F")

    -- The pick channel (the F1 fix in practice_ui.lua's drill_list_grade): the
    -- drill-list PRESS is the pick, and it is written into every alias the graders
    -- read - ctx.pick among them, which this class's reader reads FIRST. So a
    -- press grades the press, even while a shot is in flight. The class's own pick
    -- (the live cast) survives only a press-LESS press.
    eq(order(wrath_sb.ST, { now = 100, pick = "silencing_shot" }), "S",
        "shot order: a press in ctx.pick grades the press")
    eq(order(wrath_sb.ST, { now = 100, pick = "steady" }), "F",
        "shot order: a different pick in ctx.pick is a mis-order")
    eq(order(wrath_sb.ST, { now = 100, pick = "steady", pressed = "silencing_shot" }), "F",
        "shot order: ctx.pick wins over the other aliases (the drill-list press's alias)")
    eq(order(wrath_sb.ST, { now = 100, pick = "silencing_shot", action = "steady" }), "S",
        "shot order: ctx.pick wins over ctx.action too")
    -- The press-LESS drill press: this class's ctx publishes the live cast as
    -- ctx.pick, and that is the pick the drill judges.
    wrath_sb.cast = { name = "Steady Shot", start = 99, ["end"] = 101, spell_id = 49052 }
    local live_ctx = wrath_sb.ST.HUNTER.practice_context(wrath_sb.ST, 100, nil)
    eq(live_ctx.pick, "steady",
        "the class's own ctx publishes the live cast as the pick")
    eq(order(wrath_sb.ST, live_ctx), "F",
        "a press-less drill press judges the live cast")
    wrath_sb.cast = nil
    local idle_ctx = wrath_sb.ST.HUNTER.practice_context(wrath_sb.ST, 100, nil)
    eq(idle_ctx.pick, nil, "no live cast means the class publishes no pick")
    eq(order(wrath_sb.ST, idle_ctx), nil,
        "a press-less drill press with no live cast grades nothing")

    -- D-H2: the clip. The margin bands are the shipped weave bands; a clip is an F.
    -- The drill judges the MOMENT (it reads no press at all): the shot the rotation
    -- wants is the highest-priority cast shot of the rotation, and the margin is the
    -- time left before the cast would clip the Auto Shot.
    local clip = drills[2].grade
    eq(clip(wrath_sb.ST, { now = 100 }), "D",
        "clip: a wide margin is a D")
    eq(clip(wrath_sb.ST, { now = 100.4 }), "B",
        "clip: a 0.07 s margin is a B")
    eq(clip(wrath_sb.ST, { now = 100.47 }), "S",
        "clip: a tight start is an S")
    eq(clip(wrath_sb.ST, { now = 100.5 }), "F",
        "clip: a cast past the deadline clips (F)")
    eq(clip(wrath_sb.ST, { now = 100, pressed = "chimera" }), "D",
        "clip: the drill judges the moment, not the press")
    -- A client whose rotation has no cast shot (the Wrath Aimed is instant) still
    -- has the Steady filler: the drill judges that one.
    eq(clip(wrath_sb.ST, { now = 100, pressed = "steady" }), "D",
        "clip: the press does not change the moment's grade")

    -- D-H3: the cooldown pops (the TBC order: Kill Command, Bestial Wrath, Rapid
    -- Fire). The drill is a TBC rotation, so it grades nothing elsewhere.
    local tbc_drills = tbc_sb.ST.HUNTER.practice_drills
    local pop = tbc_drills[3].grade
    eq(pop(tbc_sb.ST, { now = 100, pressed = "kill_command" }), "S",
        "pop: the first pop off cooldown is an S")
    eq(pop(tbc_sb.ST, { now = 100, pressed = "kill_command",
        cooldowns = { kc = 5 } }), "F",
        "pop: the wrong pop (the order slipped) is an F")
    eq(pop(tbc_sb.ST, { now = 100, pressed = "rapid_fire" }), "F",
        "pop: the wrong pop order is an F")
    eq(pop(tbc_sb.ST, { now = 100, pressed = "kill_command", ready_at = 99 }), "A",
        "pop: a pop one GCD late is an A")
    eq(pop(tbc_sb.ST, { now = 100, pressed = "steady" }), nil,
        "pop: a shot is not this drill's business")
    -- Without a pick the moment itself is the judgement: how far down the sim's
    -- order the moment sits.
    eq(pop(tbc_sb.ST, { now = 100 }), "S",
        "pop: Kill Command up is the clean moment")
    eq(pop(tbc_sb.ST, { now = 100, cooldowns = { kc = 5 } }), "A",
        "pop: the order slipped to Bestial Wrath (A)")
    eq(pop(tbc_sb.ST, { now = 100, cooldowns = { kc = 5, bw = 5 } }), "B",
        "pop: the order slipped to Rapid Fire (B)")
    eq(pop(tbc_sb.ST, { now = 100, cooldowns = { kc = 5, bw = 5, rf = 5 } }), nil,
        "pop: nothing is up, so there is no pop to make")
    local wrath_pop = wrath_sb.ST.HUNTER.practice_drills[3].grade
    eq(wrath_pop(wrath_sb.ST, { now = 100, pressed = "kill_command" }), nil,
        "pop: the pops are a TBC rotation")

    -- D-H4: the opener. The pre-pull sequence is the sim APL's own offsets.
    local prepulls = tbc_sb.ST.HUNTER.PRACTICE_PREPULLS
    check(type(prepulls.TBC) == "table" and #prepulls.TBC == 2,
        "the TBC pre-pull sequence has the Hawk and the Steady opener")
    eq(prepulls.TBC[1].action, "aspect_hawk", "the TBC pre-pull opens with the Aspect of the Hawk")
    eq(prepulls.TBC[1].at, -20, "the Aspect of the Hawk is pre-pulled 20 s before the pull")
    eq(prepulls.TBC[2].action, "steady", "the TBC pull opener is the Steady Shot")
    eq(prepulls.TBC[2].at, 0.5, "the Steady opener lands inside the first half second")
    check(type(prepulls.SOD) == "table" and #prepulls.SOD == 5,
        "the SoD pre-pull sequence carries the five APL entries")
    eq(prepulls.SOD[1].at, -5, "the SoD pre-pull opens with the Aspect of the Falcon at -5 s")
    eq(prepulls.SOD[5].action, "serpent", "the SoD pre-pull ends with the Serpent Sting")
    check(type(prepulls.FOREVER) == "table" and #prepulls.FOREVER == 2,
        "the Forever pre-pull sequence carries the Mark and the Hawk")
    eq(prepulls.FOREVER[1].at, -22, "the Forever pre-pull opens with the Hunter's Mark at -22 s")
    local pre = tbc_drills[4].grade
    eq(pre(tbc_sb.ST, { now = 0, time_to_pull = 20, pressed = "aspect_hawk" }), "S",
        "opener: the due pre-pull on time is an S")
    eq(pre(tbc_sb.ST, { now = 0, time_to_pull = 10, pressed = "aspect_hawk" }), "D",
        "opener: a late pre-pull is a D")
    eq(pre(tbc_sb.ST, { now = 0, time_to_pull = 20, pressed = "steady" }), "D",
        "opener: the wrong opener misses the due one (D)")
    eq(pre(tbc_sb.ST, { now = 0, time_to_pull = 40, pressed = "steady" }), nil,
        "opener: nothing is due yet, so nothing grades")
    -- Without a pull clock the drill opens its OWN synthetic countdown (the audit's
    -- D-H4: "a new synthetic pull clock belongs to the drill, not to the guide").
    eq(pre(tbc_sb.ST, { now = 0, pressed = "aspect_hawk" }), "S",
        "opener: the drill's own clock opens on the first opener")

    -- The family's key: SoD shares the ERA token and the Chimera rune decides.
    eq(wrath_sb.ST.HUNTER.practice_rotation_family(), "WRATH",
        "the Wrath client reads the WRATH rotation family")
    eq(tbc_sb.ST.HUNTER.practice_rotation_family(), "TBC",
        "the TBC client reads the TBC rotation family")
    eq(era_sb.ST.HUNTER.practice_rotation_family(), "ERA",
        "the Era client reads the ERA rotation family")
    -- A ctx that names another family grades that family's rotation (the offline
    -- "simulate another client" case): the engine's family gates and the per-client
    -- cast-time fallbacks follow the named family for the call, and the running
    -- client's own family is restored afterwards.
    do
        local cross = wrath_sb.ST.HUNTER.practice_scenario_step
        eq(cross(wrath_sb.ST, { now = 100, family = "TBC" }).action, "kill_command",
            "a ctx that names TBC grades the TBC rotation")
        eq(wrath_sb.st.family, "WRATH", "the running client's family is restored after the call")
        eq(cross(wrath_sb.ST, { now = 100 }).action, "silencing_shot",
            "the running client still grades its own rotation")
    end

    -- The engine's optional accessors: the rotation slice and the family key.
    eq(#wrath_sb.ST.HUNTER.practice_rotation_for(), 13,
        "the running client's rotation slice is the whole Wrath spine")
    eq(#tbc_sb.ST.HUNTER.practice_rotation_for("TBC"), 8,
        "a named family's slice is that family's rotation")
    eq(#tbc_sb.ST.HUNTER.practice_rotation_for("ERA"), 4,
        "another family's slice is that family's rotation")
    eq(#wrath_sb.ST.HUNTER.practice_rotation_for("NOPE"), 0,
        "an unknown family answers an empty slice")
    -- The class's own ctx builder (the engine's extension point): the live state in
    -- the engine's vocabulary.
    do
        local ctx_sb = build()
        ctx_sb.ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0 }
        ctx_sb.clock = 100
        local ctx = ctx_sb.ST.HUNTER.practice_context(ctx_sb.ST, 100, nil)
        check(type(ctx) == "table", "the class publishes its own scenario ctx")
        eq(ctx.now, 100, "the ctx carries the clock")
        eq(ctx.last_action, nil, "the ctx carries the last action")
        eq(ctx.cycle_duration, 3.0, "the ctx carries the live ranged cycle")
        check(type(ctx.cooldowns) == "table", "the ctx carries the cooldown map")
        check(type(ctx.resources) == "table", "the ctx carries the resources")
        eq(ctx.resources.family, "WRATH", "the ctx carries the engine's family token")
        -- The live pull moment (BS-8 item 2 / P-17): the prepull step judges the
        -- pull window from the SAME moment the live guide reads, so the class's
        -- own ctx builder carries it.
        eq(ctx.pull_at, nil, "pull: an unarmed clock publishes no pull moment")
        eq(ctx.pull_in_seconds, nil, "pull: an unarmed clock publishes no countdown")
        local pull_sb = build()
        pull_sb.ST.pull_at = 1234
        pull_sb.ST.pull_in_seconds = function(self, now) return self.pull_at - now end
        local pull_ctx = pull_sb.ST.HUNTER.practice_context(pull_sb.ST, 1000, nil)
        eq(pull_ctx.pull_at, 1234, "pull: the ctx carries the absolute pull moment")
        eq(pull_ctx.pull_in_seconds, 234, "pull: the ctx carries the countdown to the pull")
        -- A non-numeric clock is never a guess.
        local broken = build()
        broken.ST.pull_at = "soon"
        broken.ST.pull_in_seconds = function() return "soon" end
        local broken_ctx = broken.ST.HUNTER.practice_context(broken.ST, 1000, nil)
        eq(broken_ctx.pull_at, nil, "pull: a non-numeric moment is never published")
        eq(broken_ctx.pull_in_seconds, nil, "pull: a non-numeric countdown is never published")
    end
end

--=========================================================================================
-- 6b) HU-8: the class states its hold, and the three states are the engine's own
--=========================================================================================
-- The operator ruling (hands-up HU-8, resolved 2026-10-19): a HOLD is a DECISION and
-- an unknown is not. The hunter's guide answers a HOLD (the RIDE window, the hidden
-- Auto-Shot window, out of range) and the step must SAY so: casting during the hold
-- is an illegal cast, doing nothing is correct, and a state the guide cannot read
-- stays unknown (no attempt at all).
do
    local hold_sb = build({ project = 11 })
    local pmod = assert(loadfile(ROOT .. "practice.lua"))
    setfenv(pmod, hold_sb.env)
    local okp, errp = pcall(function() pmod("SwedgeTimer", hold_sb.st) end)
    check(okp, "hold: practice.lua loads in the hunter sandbox (" .. tostring(errp) .. ")")
    local H = hold_sb.st.practice and hold_sb.st.practice.harness
    check(type(H) == "table", "hold: the shared harness is loaded")

    -- The hold statement: the accessor keeps it (the engine's contract).
    local hold_answer = H.practice_scenario_step("HUNTER", hold_sb.ST,
        { now = 100, last_action = "steady" })
    check(type(hold_answer) == "table" and hold_answer.hold == true,
        "hold: the ride state states an explicit hold")
    eq(hold_answer.action, nil, "hold: the hold statement names no action")
    check(type(hold_answer.reason) == "string" and hold_answer.reason ~= "",
        "hold: the hold statement carries the guide's reason")

    -- The three states, through the engine's own decision:
    --   hold + a cast  -> the illegal cast (an attempt, an F)
    --   hold + nothing -> a correct hold (no attempt, no points)
    --   unknown        -> unknown (no attempt)
    local run = H.new_rotation_run()
    local cast = H.rotation_run_decide(run, hold_answer.action, "chimera", hold_answer.hold)
    eq(cast.outcome, "illegal_cast", "hold: a cast during the ride is an illegal cast")
    eq(H.ROTATION_OUTCOME_GRADES[cast.outcome], "F", "hold: the illegal cast grades F")
    eq(run.mispicks, 1, "hold: the illegal cast counts against the run's band")
    local idle_run = H.new_rotation_run()
    local idle = H.rotation_run_decide(idle_run, hold_answer.action, nil, hold_answer.hold)
    eq(idle.outcome, "hold_ok", "hold: doing nothing during the ride is correct")
    eq(H.ROTATION_OUTCOME_GRADES[idle.outcome], nil,
        "hold: a correct hold records no attempt (no points)")
    eq(idle_run.mispicks, 0, "hold: a correct hold is never a mis-pick")
    -- The unknown: a state the guide cannot read stays unknown.
    local unknown_answer = H.practice_scenario_step("HUNTER", hold_sb.ST, { now = "x" })
    eq(unknown_answer, nil, "hold: an unreadable state stays unknown (no hold statement)")
    local unknown_run = H.new_rotation_run()
    local unknown = H.rotation_run_decide(unknown_run, nil, "chimera")
    eq(unknown.outcome, "unknown", "hold: an unknown step stays unknown")
    eq(H.ROTATION_OUTCOME_GRADES[unknown.outcome], nil,
        "hold: an unknown decision records no attempt")
    eq(unknown_run.mispicks, 0, "hold: an unknown decision is never a mis-pick")
end

--=========================================================================================
-- The guide's shared spell slots are FAMILY-CORRECT: every slot carries the
-- client's own rank for that family (the same owner the HUD reads, so the two
-- surfaces can never disagree about which spell the running client has -
-- bench/hunter_hud_family_2026-10-20.md §2), and the guide never declares a slot
-- for a spell the client cannot have.
--=========================================================================================
do
    local function guide_by_key(sandbox_st)
        local by_key = {}
        for i = 1, #sandbox_st.HUNTER.guide.slots do
            by_key[sandbox_st.HUNTER.guide.slots[i].key] = sandbox_st.HUNTER.guide.slots[i]
        end
        return by_key
    end
    local EXPECT = {
        { project = 2, family = "ERA",
          ids = { raptor = 14266, multi = 25294, rapid_fire = 3045, aimed = 20904 } },
        { project = 5, family = "TBC",
          ids = { steady = 34120, raptor = 27014, kill_command = 34026, multi = 27021,
            bestial_wrath = 19574, rapid_fire = 3045 } },
        { project = 11, family = "WRATH",
          ids = { steady = 49052, multi = 49048, aimed = 49050 } },
        { project = 18, family = "FOREVER",
          ids = { raptor = 14266, multi = 2643 } },
    }
    for _, case in ipairs(EXPECT) do
        local sb = build({ project = case.project })
        local by_key = guide_by_key(sb.ST)
        for key, id in pairs(case.ids) do
            check(by_key[key] ~= nil,
                case.family .. " guide: the " .. key .. " slot is declared")
            if by_key[key] then
                eq(by_key[key].spell_id, id,
                    case.family .. " guide: the " .. key .. " slot carries the client's own rank")
            end
        end
    end
    -- The dead-slot rule on the guide side: a client that cannot have a spell has
    -- no slot for it (the same rule the HUD's filter follows).
    local era = guide_by_key(build({ project = 2 }).ST)
    eq(era.steady, nil, "Era guide: no Steady slot is declared")
    eq(era.kill_command, nil, "Era guide: no Kill Command slot is declared")
    eq(era.bestial_wrath, nil, "Era guide: no Bestial Wrath slot is declared")
    local forever = guide_by_key(build({ project = 18 }).ST)
    eq(forever.steady, nil, "Forever guide: no Steady slot is declared")
    eq(forever.kill_command, nil, "Forever guide: no Kill Command slot is declared")
    -- The guide and the HUD carry the SAME id for every slot they share.
    for _, case in ipairs(EXPECT) do
        local sb = build({ project = case.project })
        local g_by_key, h_by_key = guide_by_key(sb.ST), {}
        for i = 1, #sb.ST.HUNTER.HUD_SLOTS do
            h_by_key[sb.ST.HUNTER.HUD_SLOTS[i].key] = sb.ST.HUNTER.HUD_SLOTS[i]
        end
        local shared, agree = 0, true
        for key, slot in pairs(h_by_key) do
            if slot.spell and g_by_key[key] then
                shared = shared + 1
                if g_by_key[key].spell_id ~= slot.spell then agree = false end
            end
        end
        check(shared > 0, case.family .. ": the guide and the HUD share at least one slot")
        check(agree, case.family .. ": the guide and the HUD carry the same id for every shared slot")
    end
end

if failures == 0 then
    print("PASS  hunter_guide_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  hunter_guide_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
