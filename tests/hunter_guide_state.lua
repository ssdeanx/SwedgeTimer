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
--     the world-latency basis and the rank-resolution fallback,
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

-- H2: the Bloodlust/Heroism window suppresses the weave arms only (rules 6a/6b),
-- with Steady Shot kept as the spam cue; every other rule stays live.
do
    -- A due clip-safe Aimed Shot (3 s cast + 0.03 latency vs a 3.06 ttl: swing_start
    -- 99 + 4.06 - now 100) fires without a window; inside one it falls through to the
    -- Steady spam cue.
    eq(evaluate({ aimed_known = true, aimed_cast_seconds = 3.0, latency = 0.03,
        synced_duration = 4.06 }).action, "aimed",
        "H2: a due clip-safe Aimed fires without a window")
    eq(evaluate({ aimed_known = true, aimed_cast_seconds = 3.0, latency = 0.03,
        synced_duration = 4.06, lust_remaining = 30 }).action, "steady",
        "H2: the Aimed weave suppressed, Steady Shot carries the window")
    -- A due clip-safe Multi-Shot (0.5 s cast vs a 1.06 ttl) is suppressed too, and the
    -- suppressed arm falls through to the Steady spam cue.
    eq(evaluate({ multi_known = true, latency = 0.03,
        synced_duration = 2.06 }).action, "multi",
        "H2: a due clip-safe Multi fires without a window")
    eq(evaluate({ multi_known = true, latency = 0.03,
        synced_duration = 2.06, lust_remaining = 30 }).action, "steady",
        "H2: the Multi weave suppressed, Steady Shot becomes the spam cue")
    -- Only a positive remaining suppresses: 0 and negatives read as no window.
    eq(evaluate({ multi_known = true, latency = 0.03,
        synced_duration = 1.56, lust_remaining = 0 }).action, "multi",
        "H2: a zero remaining is not a window")
    eq(evaluate({ multi_known = true, latency = 0.03,
        synced_duration = 1.56, lust_remaining = -5 }).action, "multi",
        "H2: a negative remaining is not a window")
    eq(evaluate({ multi_known = true, latency = 0.03,
        synced_duration = 1.56, lust_remaining = NONE }).action, "multi",
        "H2: an absent reading is not a window")

    -- The suppression never touches the other rules.
    eq(evaluate({ lust_remaining = 30, kc_known = true }).action, "kill_command",
        "H2: the TBC Kill Command priority stays live in the window")
    eq(evaluate({ lust_remaining = 30, hidden_window_start = 99.9,
        hidden_window_duration = 0.5 }).hold_text, "HOLD",
        "H2: the hidden-window hold stays live in the window")
    eq(evaluate({ lust_remaining = 30, steady_remaining = 0.3 }).hold_text, "RIDE",
        "H2: the live-cast ride stays live in the window")
    eq(evaluate({ lust_remaining = 30, target_in_range = 0 }).hold_text, "HOLD",
        "H2: the range gate stays live in the window")
    local saved = pure.family
    pure.family = "WRATH"
    eq(evaluate({ lust_remaining = 30 }).action, "steady",
        "H2: the Wrath filler is never suppressed")
    pure.family = saved
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

local MODULES = { "compat.lua", "utils.lua", "nextaction_ui.lua", "hunter_window.lua",
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
    -- Player auras for the H2 Bloodlust/Heroism scan (compat's scan_player_aura reads
    -- through this wrapper). nil means "no auras": every existing fixture stays on the
    -- no-window path. Non-player units answer nil (the hunter badges' pet scan lives in
    -- hunter_ui, not in this sandbox).
    env.UnitAura = function(unit, index, filter)
        sb.aura_queries = sb.aura_queries + 1
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
eq(#slots, 6, "six slots are declared (the contract's maximum)")
check(#slots <= 6, "the slot set stays at the contract's six or fewer")
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
eq(#ui.icons, 6, "the frame holds one icon per slot")
eq(sandbox.frames, 15, "frame count: group + hold + 6 icons/borders + 1 cooldown")
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
near(gathered.latency, 0.05, 1e-9, "gather: world latency only (no twist calibration)")
near(gathered.hidden_window_start, 101.45, 1e-9,
    "gather: the hidden window is recomputed from the live cycle")
near(gathered.hidden_window_duration, 0.55, 1e-9,
    "gather: the window width is the base cast window plus latency")
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

-- The cached window bounds win over a recompute (the visual half's cache is reused).
ST.ranged.hidden_window_start = 100.4
ST.ranged.hidden_window_duration = 0.5
local cached_gather = ST.HUNTER.guide.gather(ST, gathered_target)
eq(cached_gather.hidden_window_start, 100.4,
    "gather: the cached window bounds win over a recompute")
eq(cached_gather.hidden_window_duration, 0.5,
    "gather: the cached window length wins over a recompute")
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
    eq(#fslots, 6, "the fallback client declares the Wrath six (project 11)")
    eq(fslots[1].spell_id, 53351, "an unlearned Kill Shot keeps the rank-1 fallback")
    eq(fslots[2].spell_id, 53209, "an unlearned Chimera keeps the rank-1 fallback")
    eq(fslots[3].spell_id, 53301, "an unlearned Explosive keeps the rank-1 fallback")
    eq(fslots[4].spell_id, 49050, "an unlearned Wrath Aimed keeps the rank-1 fallback")
    eq(fslots[5].spell_id, 49045, "an unlearned Arcane keeps the rank-1 fallback")
    eq(fslots[6].spell_id, 56641, "an unresolved Steady rank keeps the rank-1 fallback")
    local fui = fallback.st.nextaction_ui
    eq(fui.icons[1].icon.texture.texture, nil,
        "an unresolvable icon simply stays texture-less (no error)")
    fallback.ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0 }
    fallback.ST.latency = { world_ms = 50 }
    local fgathered = fallback.ST.HUNTER.guide.gather(fallback.ST, {})
    eq(fgathered.steady_cast_seconds, 1.5, "an unreadable cast time falls back to 1.5 s")
    eq(fgathered.steady_remaining_cd, 0, "an unresolved rank reads no cooldown")
    eq(fgathered.multi_cast_seconds, 0.5, "an unreadable Multi cast time falls back to 0.5 s")
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

-- H2 gather wiring: the Bloodlust/Heroism read through compat's frozen scan contract,
-- throttled; Era never arms and spends no scan.
do
    local h2 = build({ project = 5 })  -- TBC arms the scan
    eq(h2.st.lust_supported, true, "H2: the TBC family arms the lust scan")
    local h2ST, h2st = h2.ST, h2.st
    h2ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
    h2ST.latency = { world_ms = 50 }
    h2ST.raptor_strike_queued = false
    h2ST.steady_shot_queued = false
    h2.clock = 100
    h2.player_auras = {
        { name = "Bloodlust", spell_id = 2825, duration = 40, expiration = 130 },
    }
    local g = h2ST.HUNTER.guide.gather(h2ST, {})
    near(g.lust_remaining, 30, 1e-9, "H2 gather: a live Bloodlust reads its remaining seconds")
    check(h2.aura_queries > 0, "H2 gather: the aura scan ran on TBC")
    check(h2st.lust_spell_ids ~= nil, "H2 gather: the id list comes from compat")
    -- Throttle: the aura drops, but a gather inside the window reuses the reading.
    h2.player_auras = nil
    h2.clock = 100.2
    near(h2ST.HUNTER.guide.gather(h2ST, {}).lust_remaining, 30, 1e-9,
        "H2 gather: the scan is throttled (cached reading serves the tick)")
    -- Past the throttle the scan re-polls and the dropped aura clears the field.
    h2.clock = 100.6
    eq(h2ST.HUNTER.guide.gather(h2ST, {}).lust_remaining, nil,
        "H2 gather: a dropped aura clears the window after the throttle")
    -- Heroism matches the same contract (the id list, not the name).
    h2.player_auras = {
        { name = "Heroism", spell_id = 32182, duration = 40, expiration = 140.6 },
    }
    h2.clock = 101.2
    near(h2ST.HUNTER.guide.gather(h2ST, {}).lust_remaining, 39.4, 1e-9,
        "H2 gather: Heroism matches the id list too")
    -- An unrelated aura is never the window.
    h2.player_auras = {
        { name = "Rapid Fire", spell_id = 3045, duration = 15, expiration = 120 },
    }
    h2.clock = 101.8
    eq(h2ST.HUNTER.guide.gather(h2ST, {}).lust_remaining, nil,
        "H2 gather: an unrelated aura is never the window")
    -- An expired window clamps to 0 and reads as no window (never suppressed on 0).
    h2.player_auras = {
        { name = "Bloodlust", spell_id = 2825, duration = 40, expiration = 101.9 },
    }
    h2.clock = 102.4
    eq(h2ST.HUNTER.guide.gather(h2ST, {}).lust_remaining, nil,
        "H2 gather: an expired window reads as no window")
    -- Era never arms: no scan is spent and the field stays nil.
    local era = build({ project = 2 })
    eq(era.st.lust_supported, false, "H2 gather: the Era family keeps the scan closed")
    era.ST.ranged = { start = 99.0, speed = 3.0, ends_at = 102.0, auto_repeat_active = true }
    era.ST.latency = { world_ms = 50 }
    era.clock = 50
    era.player_auras = {
        { name = "Bloodlust", spell_id = 2825, duration = 40, expiration = 90 },
    }
    eq(era.ST.HUNTER.guide.gather(era.ST, {}).lust_remaining, nil,
        "H2 gather: Era never reads a lust window")
    eq(era.aura_queries, 0, "H2 gather: Era spends no aura scan")
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
    eq(#tslots, 6, "the TBC client declares all six slots")
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
    tST.ranged.hidden_window_start = tbc.clock - 0.2
    tST.ranged.hidden_window_duration = 0.5
    ttick()
    eq(tui.frame.hold.fade.target, 1, "TBC tick: the window shows the hold overlay")
    eq(tui.frame.hold.text.text, "HOLD", "TBC tick: the window reads HOLD")
    eq(ttarget("multi"), 0, "TBC tick: the window suppresses the weave prompt")
    tST.ranged.hidden_window_start = nil
    tST.ranged.hidden_window_duration = nil
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
    eq(#eslots, 3, "the Era client declares three slots (the contract allows six)")
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
    eq(#eui.icons, 3, "the Era frame holds one icon per slot")
    eq(era.frames, 9, "Era frame count: group + hold + 3 icons/borders + 1 cooldown")
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
    eq(era.cooldown_queries, 6, "Era gather: one cooldown read per prompt (steady/kc/bw/rf/multi/aimed)")
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
    eq(#tST.HUNTER.guide.slots, 6, "TBC with Aimed data still declares six slots")
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
        eq(#mslots, 6, "Wrath MM declares six slots")
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
    eq(#sslots, 4, "SoD declares four slots (the contract allows six)")
    check(#sslots <= 6, "the SoD slot set stays at the contract's six or fewer")
    do
        local keys = {}
        for i = 1, #sslots do keys[#keys + 1] = sslots[i].key end
        eq(table.concat(keys, ","), "chimera,aimed,raptor,multi",
            "SoD slots are the Era set with Chimera first")
    end
    eq(sslots[1].spell_id, 409433, "SoD resolves the Chimera rune icon")
    eq(sslots[1].cooldown_key, nil, "the SoD Chimera slot is a swipe-less prompt")
    eq(sslots[2].spell_id, 20904, "SoD keeps the Era Aimed rank")
    local sui = sst.nextaction_ui
    eq(#sui.icons, 4, "the SoD frame holds one icon per slot")
    eq(sod.frames, 11, "SoD frame count: group + hold + 4 icons/borders + 1 cooldown")
    eq(sui.icons[1].icon.texture.texture, "icon_chimera_sod",
        "the Chimera icon shows the rune texture")

    -- The gather on a SoD tick: the rune weaves above the Era pair.
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
    eq(sod.cooldown_queries, 7, "SoD gather: the Era six plus the rune read")
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
    eq(#pslots, 3, "a pet-rune build keeps the three-slot Era set")
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
-- construction, and the filler (Steady, if known) plus the melee surface carry
-- the tick. Multi-Shot data answers but never prompts (the conservative gate).
do
    local FOREVER_SPELLS = {
        [34120] = { name = "Steady Shot", icon = "icon_steady_forever", cast_ms = 1500 },
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
    eq(#fslots, 4, "the Forever client declares four slots (the contract allows six)")
    check(#fslots <= 6, "the Forever slot set stays at the contract's six or fewer")
    do
        local keys = {}
        for i = 1, #fslots do keys[#keys + 1] = fslots[i].key end
        eq(table.concat(keys, ","), "hawk,sniper,steady,raptor",
            "Forever slots are the upkeep, the cast, the filler and the melee surface")
    end
    eq(fslots[1].spell_id, nil, "the hawk slot ships spell-less (UNCONFIRMED id)")
    eq(fslots[1].cooldown_key, nil, "the hawk slot is a swipe-less upkeep prompt")
    eq(fslots[2].spell_id, nil, "the sniper slot ships spell-less (UNCONFIRMED id)")
    eq(fslots[2].cooldown_key, "sniper", "the sniper slot carries its live-cast swipe key")
    eq(fslots[2].swipe_duration, 4.0, "the sniper slot carries the cast-length swipe fallback")
    eq(fslots[2].swipe_always, true, "the sniper swipe stays armed while the RIDE hold fades the icon")
    eq(fslots[3].spell_id, 34120, "Forever steady resolves to the known rank")
    eq(fslots[4].spell_id, 27014, "Forever raptor resolves to the known rank")
    local fui = fst.nextaction_ui
    eq(#fui.icons, 4, "the Forever frame holds one icon per slot")
    eq(fw.frames, 12, "Forever frame count: group + hold + 4 icons/borders + 2 cooldowns")
    eq(fui.icons[1].icon.texture.texture, nil,
        "a spell-less hawk icon simply stays texture-less (no error)")
    eq(fui.icons[2].icon.texture.texture, nil,
        "a spell-less sniper icon simply stays texture-less (no error)")
    eq(fui.icons[3].icon.texture.texture, "icon_steady_forever",
        "the steady icon shows the current rank's texture")
    eq(fui.icons[2].remaining_key, "sniper_remaining", "the swipe field names derive from the key")
    eq(fui.icons[2].duration_key, "sniper_duration", "the swipe length field derives from the key")
    eq(fui.icons[1].remaining_key, nil, "the hawk slot carries no swipe fields")

    -- The gather on a Forever tick: both UNCONFIRMED gates down, Steady due.
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
    eq(fgathered.steady_known, true, "Forever gather: Steady Shot is known")
    eq(fw.cooldown_queries, 5, "Forever gather: one cooldown read per old prompt (steady/kc/bw/rf/multi)")
    eq(fST.HUNTER.guide.evaluate(fgathered, {}).action, "steady",
        "Forever: Steady Shot is the prompt on a fresh tick (filler intact)")

    -- Stale fields are overwritten on the reused table.
    fgathered.hawk_known = true
    fgathered.sniper_known = true
    fgathered.sniper_remaining = 1.0
    fgathered = fST.HUNTER.guide.gather(fST, fgathered)
    eq(fgathered.hawk_known, false, "the hawk gate is overwritten, not stale")
    eq(fgathered.sniper_known, false, "the sniper gate is overwritten, not stale")
    eq(fgathered.sniper_remaining, nil, "the cleared cast removes the stale sniper remaining")
    eq(fgathered.sniper_duration, nil, "the cleared cast removes the stale sniper duration")

    -- Every action the Forever engine can return names a Forever slot.
    do
        local actions = { "hawk", "sniper", "steady" }
        local all_resolve = true
        for i = 1, #actions do
            if fui.slot_index[actions[i]] == nil then
                all_resolve = false
            end
        end
        check(all_resolve, "every Forever action names a declared Forever slot")
    end

    -- The Forever tick through the real hook lights the steady slot; the
    -- window still holds there (conservative, pinned at the pure level too).
    local function ftarget(key) return fui.icons[fui.slot_index[key]].fade.target end
    local function ftick()
        fST.mainhand = { speed = 3.0, ends_at = fw.clock + 3.0, start = fw.clock,
            is_full = false }
        fw.advance(0.1)
        fST.HUNTER.on_bar_update(fST, "mainhand")
    end
    ftick()
    eq(ftarget("steady"), 1, "Forever tick: the filler prompt lights the steady slot")
    eq(ftarget("hawk"), 0, "Forever tick: the unconfirmed hawk slot stays dark")
    eq(ftarget("sniper"), 0, "Forever tick: the unconfirmed sniper slot stays dark")
    eq(fui.frame.hold.fade.target, 0, "Forever tick: the filler prompt shows no hold")
    eq(fui.frame.shown, true, "Forever tick: the frame shows in combat")
    fST.ranged.hidden_window_start = fw.clock - 0.2
    fST.ranged.hidden_window_duration = 0.5
    ftick()
    eq(fui.frame.hold.fade.target, 1, "Forever tick: the window shows the hold overlay")
    eq(fui.frame.hold.text.text, "HOLD", "Forever tick: the window reads HOLD")
    eq(ftarget("steady"), 0, "Forever tick: the window suppresses the filler prompt")
    fST.ranged.hidden_window_start = nil
    fST.ranged.hidden_window_duration = nil
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
        nextaction_enabled = "false",
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

if failures == 0 then
    print("PASS  hunter_guide_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  hunter_guide_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
