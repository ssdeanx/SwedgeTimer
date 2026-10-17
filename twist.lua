--=========================================================================================
-- Twist: seal twisting state machine for Paladins.
--
-- Ported from the archived builds under docs/swedge/SwedgeTimer_TBC (and *_Forever):
--   * detection model: a twist attempt = two seals active at the instant a swing lands
--     (SWING_DAMAGE / SWING_MISSED), and a success = a Seal of Command proc (SPELL_DAMAGE
--     with a soc_proc_id) while an attempt is pending.
--   * impossible-twist warning = a running GCD plus calibrated lag that cannot
--     clear before the swing, warned until the twist window opens (player.lua:743-771).
--
-- This module is deliberately PURE (no WoW API calls, no tables owned by the addon) so
-- it can be unit-tested offline with the harness in tests/twist_state.lua. WoW-facing
-- code (combat log forwarding, auras, bars, options) calls into these helpers rather
-- than re-implementing the rules, so the behaviour has a single source.
--=========================================================================================
local _, st = ...

st.twist = st.twist or {}

-- Seal of Command proc ids: the damage spells that fire when Command produces proc
-- damage on the swing. Source: docs/swedge/SwedgeTimer_TBC/st_data.lua:57-67.
st.twist.SOC_PROC_IDS = {
    [20424] = true, -- Rank 1
    [20944] = true, -- Rank 2
    [20945] = true, -- Rank 3
    [20946] = true, -- Rank 4
    [20947] = true, -- Rank 5
    [29385] = true, -- Rank 6 (TBC)
}

-- Twist window constants (see docs/swedge/.../bar.lua:1917-1927).
-- TBC calibration (docs/research/tbc_minmax.md, paladin): Seal of Command
-- procs ~0.5 s after the white hit lands, so the twist (second seal) goes in
-- during the swing's last ~0.4 s (Warmane forum, Wowhead SoD guide,
-- TheRealBlayst). The 0.4 s baseline below already matches that model;
-- SOC_PROC_DELAY_SECONDS records the proc delay it sits inside (documentary:
-- not wired into get_window_seconds, whose math is unchanged).
st.twist.BASE_WINDOW_SECONDS = 0.4
st.twist.SOC_PROC_DELAY_SECONDS = 0.5

-- Pure helper: is twisting even possible right now?
-- twisting requires a Command-style seal or Righteousness-style seal up (the seal
-- whose damage actually lands with the swing). See the archived is_twist_seal_active().
function st.twist.is_twist_seal_active(has_soc, has_sor)
    return (has_soc or has_sor) and true or false
end

-- Pure: how many of the active seals count toward a twist attempt. We only count the
-- seal family, not duplicated ranks. The implementation lives outside; this helper just
-- normalises the input so the threshold test stays (count == 2).
function st.twist.normalize_seal_count(n)
    if type(n) ~= "number" then return 0 end
    if n < 0 then return 0 end
    if n ~= math.floor(n) then return math.floor(n) end
    return n
end

-- Pure: did a swing land produce a twist attempt?
-- attempt = NOT an extra attack AND seal discipline present AND n_active_seals == 2
function st.twist.detect_twist_attempt(is_extra_attack, seal_discipline_active, n_active_seals)
    if is_extra_attack then return false end
    if not seal_discipline_active then return false end
    if st.twist.normalize_seal_count(n_active_seals) ~= 2 then return false end
    return true
end

-- Pure: did a spell proc equal the success for a pending attempt?
function st.twist.detect_twist_success(attempt_pending, spell_id)
    if not attempt_pending then return false end
    if type(spell_id) ~= "number" then return false end
    return st.twist.SOC_PROC_IDS[spell_id] == true
end

-- Pure: twist window duration (seconds) given the selected padding mode.
--   mode        : "None" | "Fixed" | "Dynamic"
--   lag_ms      : calibrated world latency in milliseconds (Dynamic mode)
--   fixed_ms    : user padding in milliseconds (Fixed mode)
function st.twist.get_window_seconds(mode, lag_ms, fixed_ms)
    local window = st.twist.BASE_WINDOW_SECONDS
    local padding = 0
    if mode == "Dynamic" then
        local ms = lag_ms or 0
        if ms < 0 then ms = 0 end
        padding = ms * 0.7 * 0.001
    elseif mode == "Fixed" then
        local ms = fixed_ms or 0
        if ms < 0 then ms = 0 end
        if ms > 400 then ms = 400 end
        padding = ms * 0.001
    end
    -- never let padding shrink the 400 ms baseline, and cap absurdly large values
    local result = window + padding
    if result < window then result = window end
    if result > 0.8 then result = 0.8 end
    return result
end

-- Pure: impossible-twist heuristic, matching the archived build (player.lua:743-771):
-- "the GCD running now, plus calibrated latency, will not clear before this swing
-- lands" AND "we are still before the twist window" => the player cannot twist this
-- swing (unless they stopattack). Inside the twist window the warning clears, as in
-- the archive, because it is already go-time. All inputs are plain numbers.
function st.twist.is_twist_impossible(enabled, remaining_seconds, gcd_seconds, lag_ms,
                                       lag_multiplier, lag_offset_ms, window_seconds)
    if not enabled then return false end
    if remaining_seconds < 0 then remaining_seconds = 0 end
    local window = window_seconds or st.twist.BASE_WINDOW_SECONDS
    if window < 0 then window = 0 end
    -- Already inside (or past) the twist window: not the warning phase.
    if remaining_seconds <= window then return false end
    local ms = lag_ms or 0
    if ms < 0 then ms = 0 end
    local mult = lag_multiplier or 1.4
    if mult < 0 then mult = 0 end
    local offset = lag_offset_ms or 0
    if offset < 0 then offset = 0 end
    -- Calibrated latency, mirroring the archive's lag_calibrated_ms.
    local gcd_with_lag = (gcd_seconds or 0) + (ms * 0.001 * mult) + (offset * 0.001)
    return gcd_with_lag > remaining_seconds
end

-- Helpers above are reachable via st.twist and pure (no WoW globals).
if st.debug then st.utils.print_msg('-- Parsed twist.lua correctly') end
