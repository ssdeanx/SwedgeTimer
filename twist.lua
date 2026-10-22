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

-- SoD twist window (all SoD twist APLs: p4-twist, p8-twist): the sim twists
-- inside 200 ms after the swing (autoTimeToNext <= 200ms + strictSequence
-- wait), not the 0.4 s classic/TBC baseline above. narrow_window_for_sod
-- swaps the baseline while preserving the user's configured padding.
st.twist.SOD_WINDOW_SECONDS = 0.2

-- Pure: SoD-narrow a caller-computed window (padding already applied).
-- Non-SoD (nil/false) passes through untouched; a nil/non-number window
-- passes through for the caller to handle, never a guessed number.
function st.twist.narrow_window_for_sod(window_seconds, sod_active)
    if sod_active ~= true then
        return window_seconds
    end
    if type(window_seconds) ~= "number" or window_seconds ~= window_seconds then
        return window_seconds
    end
    local narrowed = window_seconds
        - (st.twist.BASE_WINDOW_SECONDS - st.twist.SOD_WINDOW_SECONDS)
    if narrowed < st.twist.SOD_WINDOW_SECONDS then
        narrowed = st.twist.SOD_WINDOW_SECONDS
    end
    return narrowed
end

-- Seal of Command proc model (both sims: classic soc.go, forever
-- seal_of_command.go): ~7 PPM on white hits only with a 1 s ICD. A swing
-- landing inside the ICD after a proc cannot proc, so it must arm no
-- attempt and score nothing. is_proc_icd_clear is the pure gate: true when
-- a swing may proc (no proc yet, or the ICD has cleared), false inside the
-- window. Unusable inputs degrade to true (the archived attempt behaviour),
-- never to a suppressed attempt.
st.twist.SOC_PROC_ICD_SECONDS = 1

-- Pure: may a swing landing now produce a Command proc?
function st.twist.is_proc_icd_clear(now_seconds, last_proc_at_seconds)
    if type(now_seconds) ~= "number" or now_seconds ~= now_seconds then
        return true
    end
    if type(last_proc_at_seconds) ~= "number"
        or last_proc_at_seconds ~= last_proc_at_seconds then
        return true
    end
    return (now_seconds - last_proc_at_seconds) >= st.twist.SOC_PROC_ICD_SECONDS
end

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

-- Seal of Command proc names (R1): clients that report the spell name where
-- classic reports the numeric id (Anniversary, UNCONFIRMED) still need the
-- success to land. The literal English proc name is the fallback; the
-- client's own localized names (resolved through GetSpellInfo by the caller,
-- same discipline as the warrior's localized-name scans) are authoritative.
st.twist.SOC_PROC_NAME_FALLBACK = "Seal of Command"

-- Pure: did a spell-NAME payload equal the success for a pending attempt?
-- The numeric path above is untouched and stays byte-identical.
function st.twist.detect_twist_success_name(attempt_pending, name, localized_names)
    if not attempt_pending then return false end
    if type(name) ~= "string" then return false end
    if localized_names ~= nil and localized_names[name] == true then return true end
    return name == st.twist.SOC_PROC_NAME_FALLBACK
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

-- Pure: GCD-aware reseal marker fraction (SST 3.1.0 "reseal marker for twist
-- seals", bench/competitor_gaps_2026-10-19.md sec Paladin P1 - SST in-client
-- behavior UNCONFIRMED). The marker sits where the running GCD clears inside the
-- current swing, so the player sees when a reseal press becomes possible relative
-- to the twist window the band already draws (left of the band = clears early,
-- inside it = clears in-window): fraction = 1 - (swing_remaining - gcd_remaining)
-- / swing_duration. nil (hidden) when the inputs cannot time it: no running GCD
-- (nothing to wait for), an unreadable/degenerate swing, or a GCD that clears
-- outside this swing. The twist window itself stays on the band; this helper only
-- times the GCD clear, so it takes no window input.
function st.twist.get_reseal_marker_fraction(swing_duration, swing_remaining, gcd_remaining)
    if type(swing_duration) ~= "number" or swing_duration ~= swing_duration
        or swing_duration <= 0 then
        return nil
    end
    if type(swing_remaining) ~= "number" or swing_remaining ~= swing_remaining then
        return nil
    end
    if type(gcd_remaining) ~= "number" or gcd_remaining ~= gcd_remaining
        or gcd_remaining <= 0 then
        return nil
    end
    if swing_remaining < 0 then swing_remaining = 0 end
    local fraction = 1 - (swing_remaining - gcd_remaining) / swing_duration
    if fraction < 0 or fraction > 1 then
        return nil
    end
    return fraction
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
