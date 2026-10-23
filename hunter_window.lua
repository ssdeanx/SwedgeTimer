--=========================================================================================
-- Hunter window: pure ranged-window maths for the SuperSwingTimer hunter port, phase 1.
--
-- WoW-free by design (the twist.lua / weave.lua / nextaction.lua discipline): no WoW
-- globals, no clock reads, every timestamp arrives as an argument in the api.get_time()
-- (seconds) domain. The client probes that feed these helpers live in compat.lua,
-- main.lua and classes/hunter.lua; the offline tests live in tests/hunter_window_state.lua.
--
-- Ported from the read-only reference SuperSwingTimer-WoW:
--   cast_window              SuperSwingTimer_UI.lua:16-23
--   hidden_window            SuperSwingTimer_UI.lua:418-428
--   is_cast_safe             SuperSwingTimer_UI.lua:870-877
--   is_stopped_position_safe SuperSwingTimer_UI.lua:204-225
--   time_until_next_shot     SuperSwingTimer_State.lua:452-472
--   sync_duration            SuperSwingTimer_State.lua:697-710
--   should_restart           SuperSwingTimer_State.lua:832-853
--   cast_bar_display         SuperSwingTimer_UI.lua:459-491, 943-1095 (mode priority)
--   latency_slice_fraction   SuperSwingTimer_UI.lua:890-941
--   clip_tint                SuperSwingTimer_UI.lua:858-886
--   range_state              SuperSwingTimer_ClassMods.lua:5585-5610
--   hold_seconds             SwedgeTimer display kernel (H1 shot clock), not a reference port
-- Constants: SuperSwingTimer_Constants.lua:168 (cast window), :180 (steady-shot grace),
-- SuperSwingTimer_UI.lua:872-876 (multi-shot grace), SuperSwingTimer_State.lua:25 (dedupe),
-- SuperSwingTimer_Constants.lua:975-976 (clip tint colours).
--=========================================================================================
local _, st = ...

st.hunter_window = st.hunter_window or {}

local hunter_window = st.hunter_window

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- The shared hidden hunter/ranged cast window (SuperSwingTimer_Constants.lua:168).
hunter_window.BASE_CAST_WINDOW = 0.5

-- Auto Shot fires during the last 0.5 s of a Steady Shot cast without clipping
-- (SuperSwingTimer_Constants.lua:180).
hunter_window.STEADY_SHOT_GRACE = 0.5

-- Multi-Shot has 0 grace: its hidden window delays Auto Shot on overlap
-- (SuperSwingTimer_UI.lua:872-876).
hunter_window.MULTI_SHOT_GRACE = 0

--------------------------------------------------------------------------------
-- TBC micro-details (docs/research/tbc_minmax.md)
--------------------------------------------------------------------------------

-- Quiver haste (15%) and the max-rank Serpent's Swiftness bonus (20%): the two
-- are multiplicative, so a BM hunter runs at 1.15 * 1.20 = 1.38 total while an
-- untalented quiver alone is 1.15 (the SV shape). Callers compose the product
-- themselves so stacked-haste procs (Rapid Fire, Bloodlust, DST...) can join it.
hunter_window.QUIVER_HASTE = 0.15
hunter_window.SERPENT_SWIFTNESS_HASTE = 0.20

-- Steady-shot ratio bands over the effective weapon speed (rotationtools via
-- tbc_minmax.md): 1:1 while eWS sits in [1.3, 1.6] s, the standard French
-- 5:5:1:1 macro above it (the 1.5 s Steady cast no longer sustains 1:1 there),
-- and the high-haste 1:2/1:3 shape below it (stacked haste drives eWS towards
-- ~0.62 s for ~10 s). Bounds are inclusive at both edges.
hunter_window.EWS_RATIO_LO = 1.3
hunter_window.EWS_RATIO_HI = 1.6

-- Hit-rating caps vs boss specials (tbc_minmax.md): 142 base (9%), 126 with a
-- Draenei in party (Heroic Presence, 8%), 95 with Improved Faerie Fire (6%),
-- 79 with both (5%). Hit changes land chance, never shot timing, so this feeds
-- future HUD/badge display only - never the prompt matrix (documented choice:
-- the engine is intentionally hit-blind).
hunter_window.HIT_CAP_BASE = 142
hunter_window.HIT_CAP_DRAENEI = 126
hunter_window.HIT_CAP_IFF = 95
hunter_window.HIT_CAP_BOTH = 79

-- Effective weapon speed from a base weapon speed and a total haste multiplier:
-- eWS = WS / mult, so a 3.0 weapon under quiver x Serpent's Swiftness reads
-- 3.0 / 1.38, under a bare quiver 3.0 / 1.15, and a 2.9 weapon under the full
-- stacked 4.64 mult reads ~0.625 (the ~0.62 s figure). A nil/non-positive base
-- or multiplier reports nil rather than guessing.
function hunter_window.effective_weapon_speed(base_speed, haste_mult)
    if type(base_speed) ~= "number" or base_speed <= 0 then
        return nil
    end
    if type(haste_mult) ~= "number" or haste_mult <= 0 then
        return nil
    end
    return base_speed / haste_mult
end

-- Which Steady-shot ratio the current effective weapon speed selects (bands
-- above): "one_to_one", "french" or "one_to_two". A non-number eWS reports nil
-- (unknown cycle, no ratio) rather than guessing.
function hunter_window.steady_ratio_band(effective_speed)
    if type(effective_speed) ~= "number" then
        return nil
    end
    if effective_speed < hunter_window.EWS_RATIO_LO then
        return "one_to_two"
    end
    if effective_speed > hunter_window.EWS_RATIO_HI then
        return "french"
    end
    return "one_to_one"
end

-- The applicable hit-rating cap for the two raid buffs that move it. Only an
-- explicit true/1 reads as present (the range_state probe discipline: a 0 is
-- "absent", never truthy); both absent (nil included) reads as the 142 base.
function hunter_window.hit_cap_rating(has_draenei, has_iff)
    local draenei = has_draenei == true or has_draenei == 1
    local iff = has_iff == true or has_iff == 1
    if draenei and iff then
        return hunter_window.HIT_CAP_BOTH
    end
    if iff then
        return hunter_window.HIT_CAP_IFF
    end
    if draenei then
        return hunter_window.HIT_CAP_DRAENEI
    end
    return hunter_window.HIT_CAP_BASE
end

-- Ranged start dedupe floor; the live window is max(0.25, latency + 0.05)
-- (SuperSwingTimer_State.lua:25, :839).
hunter_window.RANGED_START_DEDUPE_WINDOW = 0.25

--------------------------------------------------------------------------------
-- Cast window
--------------------------------------------------------------------------------

-- Width of the hidden cast window: the client's fixed 0.5 s Auto Shot cast window, at
-- the END of the ranged cycle. Latency is deliberately NOT added to the width (operator
-- ruling 2026-10-22): the red zone is the cast window itself, never wider. Latency is
-- why a Steady Shot cast may land INSIDE that window without clipping, so it affects
-- the cast-safety verdict (is_cast_safe), never the zone geometry. The `latency`
-- argument is kept for call-site compatibility and ignored.
function hunter_window.cast_window(_)
    return hunter_window.BASE_CAST_WINDOW
end

-- The hidden cast window of a ranged cycle: the last `cast_window` seconds before the
-- cycle ends at last_swing + duration (reference
-- GetHunterHiddenCastWindowFromRangedTimer tail, SuperSwingTimer_UI.lua:418-426).
-- Returns window_start, window_end (the reference computes the same bounds and hands
-- back the start plus the width; this helper returns the start/end pair the callers need).
-- The reference floors the window at 0.01 s and defaults a nil window to the base 0.5 s
-- (`math.max(GetRangedCastWindow() or 0.5, 0.01)`); callers normally pass
-- cast_window(latency). An invalid timer (no anchor, no positive duration) reports
-- nil, nil, the reference's "not swinging / no duration" early return (UI.lua:394-397).
function hunter_window.hidden_window(last_swing, duration, cast_window)
    if type(last_swing) ~= "number" or type(duration) ~= "number" or duration <= 0 then
        return nil, nil
    end
    if type(cast_window) ~= "number" then
        cast_window = hunter_window.BASE_CAST_WINDOW
    end
    cast_window = math.max(cast_window, 0.01)
    local window_end = last_swing + duration
    local window_start = window_end - cast_window
    return window_start, window_end
end

--------------------------------------------------------------------------------
-- Cast-bar display
--------------------------------------------------------------------------------

-- Which face the hunter cast bar shows right now, from the reference's priority chain
-- (a live player cast wins, then the hidden window of the ongoing ranged cycle, then
-- nothing; SuperSwingTimer_UI.lua:459-491, :943-1095):
--   "cast"   - a live player cast is in progress (has_live_cast == true)
--   "window" - the hidden Auto Shot window covers `now`: a valid window_start,
--              window_duration > 0 and window_start <= now <= window_start + duration
--              (inclusive bounds, matching the reference's
--              `now < windowStart or now > windowEnd` outside test)
--   "hidden" - neither. A missing/zero/negative window or an unknown `now` all land
--              here rather than guessing; only an explicit true counts as a live cast.
function hunter_window.cast_bar_display(has_live_cast, window_start, window_duration, now)
    if has_live_cast == true then
        return "cast"
    end
    if type(window_start) == "number" and type(window_duration) == "number" and window_duration > 0
        and type(now) == "number"
        and now >= window_start and now <= window_start + window_duration then
        return "window"
    end
    return "hidden"
end

-- The H1 shot clock: seconds of HOLD left while `now` sits in the hidden Auto-Shot
-- window (window_start + window_duration - now, i.e. the moment the window closes and
-- the next Auto Shot fires). The same inclusive-bounds test as cast_bar_display above:
-- a `now` at either edge is inside (0 at the closing edge), anything outside reads nil,
-- as does a missing/zero/negative duration or a non-number argument - the shot clock
-- derives from the same bounds the HOLD ride keys on, never from a clock read (this is
-- a display kernel for the SwedgeTimer face label, not a verbatim SuperSwingTimer port).
function hunter_window.hold_seconds(window_start, window_duration, now)
    if type(window_start) ~= "number" or type(window_duration) ~= "number"
        or window_duration <= 0 or type(now) ~= "number" then
        return nil
    end
    local window_end = window_start + window_duration
    if now < window_start or now > window_end then
        return nil
    end
    return window_end - now
end

-- Width fraction of the red latency end-slice drawn at the right edge of the cast bar:
-- latency_window / duration clamped into [0, 1] (the reference multiplies the fraction
-- by the bar width and clamps the result to it, SuperSwingTimer_UI.lua:890-941). A
-- non-number or non-positive latency or duration reports 0 (no slice), and a slice wider
-- than the whole bar reports 1.
function hunter_window.latency_slice_fraction(latency_window, duration)
    if type(latency_window) ~= "number" or latency_window <= 0 then
        return 0
    end
    if type(duration) ~= "number" or duration <= 0 then
        return 0
    end
    local fraction = latency_window / duration
    if fraction > 1 then
        return 1
    end
    return fraction
end

-- Colour key for the no-clip tint of a live cast, from hunter_window.is_cast_safe's
-- verdict: "clipSafe" (green) when the cast fits before the next shot, "clipZone" (red)
-- otherwise (reference Constants.lua:975-976; the tint is only ever applied to real
-- casts, never to the Auto Shot window label). Only an explicit true is safe: an
-- unknown/absent verdict tints red, mirroring the reference's non-nil clipSafe path.
function hunter_window.clip_tint(safe)
    if safe == true then
        return "clipSafe"
    end
    return "clipZone"
end

--------------------------------------------------------------------------------
-- Cast safety
--------------------------------------------------------------------------------

-- Whether a cast with `remaining_cast` seconds left is safe (reference clipSafe,
-- SuperSwingTimer_UI.lua:870-877):
--   remaining_cast <= max(time_until_next_shot + grace - max(latency, 0.03), 0)
-- `grace` is STEADY_SHOT_GRACE (0.5) for Steady Shot - Auto Shot may fire in the last
-- 0.5 s of the cast without clipping (SuperSwingTimer_Constants.lua:180) - and
-- MULTI_SHOT_GRACE (0) for Multi-Shot, whose hidden window delays Auto Shot on overlap
-- (SuperSwingTimer_UI.lua:872-876). A nil/non-number grace reads as the steady-shot
-- grace, matching the reference's `ns.STEADY_SHOT_GRACE or 0.5`. Latency is floored at
-- 0.03 s so even a zero-latency reading leaves a buffer.
function hunter_window.is_cast_safe(remaining_cast, time_until_next_shot, grace, latency)
    if type(remaining_cast) ~= "number" or type(time_until_next_shot) ~= "number" then
        return false
    end
    if type(latency) ~= "number" then
        latency = 0
    end
    local safety_buffer = math.max(latency, 0.03)
    if type(grace) ~= "number" then
        grace = hunter_window.STEADY_SHOT_GRACE
    end
    return remaining_cast <= math.max(time_until_next_shot + grace - safety_buffer, 0)
end

-- Whether standing still right now is safe for the ranged cast window: safe when the
-- player stopped at or before the window opened, unsafe when still moving or when the
-- stop landed after it (reference IsRangedCastWindowSafe, SuperSwingTimer_UI.lua:204-225).
-- The window opens at `last_swing + duration - cast_window`; the exact inequality is
--   stopped_at <= window_open
-- so a stop exactly at the boundary is safe and anything strictly later is too late. A
-- nil (or non-number) last_stopped_at means "never stopped this session" and is safe
-- while not moving; still moving is never safe. An invalid timer or window reports
-- false (same guards).
function hunter_window.is_stopped_position_safe(is_moving, last_stopped_at, last_swing, duration, cast_window)
    if type(last_swing) ~= "number" or type(duration) ~= "number" or duration <= 0 then
        return false
    end
    if type(cast_window) ~= "number" or cast_window <= 0 then
        return false
    end
    if is_moving == true then
        return false
    end
    local window_open = last_swing + duration - cast_window
    if type(last_stopped_at) == "number" and last_stopped_at > window_open then
        return false
    end
    return true
end

--------------------------------------------------------------------------------
-- Range helper
--------------------------------------------------------------------------------

-- Whether a raw range probe reads as in-band: the classic clients answer 1/0 and the
-- modern ones true/false, so both spellings count. Everything else - false, 0, nil,
-- non-numbers - is out of band.
local function probe_is_true(value)
    return value == true or value == 1
end

-- The hunter range helper's state from the three probes, in reference priority order
-- (reference GetHunterRangeState, SuperSwingTimer_ClassMods.lua:5585-5610):
--   melee > sweet_spot > ranged > out_of_range
-- An unknown probe (nil) reads as out of band, so all-unknown reports "out_of_range";
-- the caller decides whether that is a real reading or whether every probe was unknown
-- and the strip should stay hidden (the reference returns nil there).
function hunter_window.range_state(melee, sweet, ranged)
    if probe_is_true(melee) then
        return "melee"
    end
    if probe_is_true(sweet) then
        return "sweet_spot"
    end
    if probe_is_true(ranged) then
        return "ranged"
    end
    return "out_of_range"
end

--------------------------------------------------------------------------------
-- Next-shot timing
--------------------------------------------------------------------------------

-- Seconds until the next ranged shot. A live swing wins: last_swing + duration while
-- the duration is positive, clamped at 0 (reference
-- GetTimeUntilNextHunterRangedShot, SuperSwingTimer_State.lua:460-462). Otherwise an
-- absolute `cooldown_end` the caller computed from GetSpellCooldown(75) (start +
-- duration) is the fallback, clamped the same way (State.lua:464-469). nil when neither
-- source reports a cycle (State.lua:471); a non-number `now` reports nil instead of
-- guessing.
function hunter_window.time_until_next_shot(now, last_swing, duration, cooldown_end)
    if type(now) ~= "number" then
        return nil
    end
    if type(last_swing) == "number" and type(duration) == "number" and duration > 0 then
        return math.max((last_swing + duration) - now, 0)
    end
    if type(cooldown_end) == "number" then
        return math.max(cooldown_end - now, 0)
    end
    return nil
end

--------------------------------------------------------------------------------
-- Ranged duration sync
--------------------------------------------------------------------------------

-- Apply a live Auto Shot cooldown reading to the ranged cycle (reference
-- SyncRangedTimerSpeed, SuperSwingTimer_State.lua:697-710). Returns
--   duration, speed, reanchor
-- where duration and speed are both the cooldown duration (the reference assigns
-- autoShotDuration to t.duration and t.speed alike, State.lua:702-703) and `reanchor`
-- says whether the swing anchor should move to `auto_shot_start` under the drift rule
--   abs(last_swing - auto_shot_start) > 0.01
-- with a strict comparison, so a drift of exactly 0.01 s does NOT re-anchor
-- (State.lua:701, :708). A nil/non-number previous anchor reads as the cooldown start
-- (the source's `t.lastSwing or autoShotStart`), i.e. no drift. A missing/zero cooldown
-- start cannot anchor anything (reanchor = false); a missing/non-positive cooldown
-- duration reads as "no cooldown" and returns nil so the caller can skip.
function hunter_window.sync_duration(previous_last_swing, auto_shot_start, auto_shot_duration)
    if type(auto_shot_duration) ~= "number" or auto_shot_duration <= 0 then
        return nil
    end
    local reanchor = false
    if type(auto_shot_start) == "number" and auto_shot_start > 0 then
        local anchor = previous_last_swing
        if type(anchor) ~= "number" then
            anchor = auto_shot_start
        end
        reanchor = math.abs(anchor - auto_shot_start) > 0.01
    end
    return auto_shot_duration, auto_shot_duration, reanchor
end

--------------------------------------------------------------------------------
-- Ranged start dedupe
--------------------------------------------------------------------------------

-- Whether a ranged (re)start may run now (reference StartRangedSwing,
-- SuperSwingTimer_State.lua:839-845): false while the previous start is inside
--   dedupe = max(0.25, latency + 0.05)
-- i.e. blocked for 0 <= now - last_restart_at < dedupe. A negative elapsed (clock skew)
-- and an elapsed at or past the window allow the restart, and a nil/zero
-- last_restart_at means "no start yet" and allows it too (the source guards with
-- `t.lastRangedStartTime and t.lastRangedStartTime > 0`). A non-number `now` reports
-- false rather than guessing.
function hunter_window.should_restart(now, last_restart_at, latency)
    if type(now) ~= "number" then
        return false
    end
    local dedupe_window = hunter_window.RANGED_START_DEDUPE_WINDOW
    if type(latency) == "number" and latency + 0.05 > dedupe_window then
        dedupe_window = latency + 0.05
    end
    if type(last_restart_at) == "number" and last_restart_at > 0 then
        local elapsed = now - last_restart_at
        if elapsed >= 0 and elapsed < dedupe_window then
            return false
        end
    end
    return true
end

if st.debug then st.utils.print_msg('-- Parsed hunter_window.lua correctly') end
