--=========================================================================================
-- Druid energy: pure maths for the druid port - the cat-form energy tick cycle, the
-- form-label mapping and the target debuff bar display rules.
--
-- WoW-free by design (the twist.lua / weave.lua / hunter_window.lua discipline): no WoW
-- globals, no clock reads; every timestamp and reading arrives as an argument. The
-- WoW-facing code lives in classes/druid.lua, the offline tests in
-- tests/druid_energy_state.lua.
--
-- Ported from the read-only reference SuperSwingTimer-WoW/SuperSwingTimer_ClassMods.lua
-- (druid block 4514-5524); the reference line for each helper is named on it.
--=========================================================================================
local _, st = ...

st.druid_energy = st.druid_energy or {}

-- One natural energy tick every 2.0 s (reference DRUID_ENERGY_TICK_DURATION,
-- SuperSwingTimer_ClassMods.lua:4516).
st.druid_energy.ENERGY_TICK_SECONDS = 2.0

-- One natural tick grants 20 energy. The reference's [19, 22] window below is the
-- gain-detection bracket; the grant itself is the flat 20 every feral source states.
st.druid_energy.ENERGY_TICK_GAIN = 20

-- Natural-gain classifier window: a power gain inside [19, 22] is the game's own energy
-- tick and re-anchors the cycle (reference IsLikelyNaturalDruidEnergyGain,
-- SuperSwingTimer_ClassMods.lua:4544-4546).
st.druid_energy.ENERGY_GAIN_MIN = 19
st.druid_energy.ENERGY_GAIN_MAX = 22

-- D4 time-to-die EMA (bench/verify_bank.md §4.1 correction - BINDING): the velocity
-- feeding the estimator is an exponential moving average of HP/s (TimeToDie-style),
-- never a raw sample - raw samples spike on crits and DoT ticks and would swing the
-- estimate wildly. The EMA weight of the newest sample: 0.25 keeps a ~4-sample
-- horizon (own choice; the competitor's exact constant is not published).
st.druid_energy.TTD_EMA_ALPHA = 0.25
-- Minimum seconds between HP samples: the live read is per-frame, and dividing by a
-- near-zero dt would manufacture velocity noise; the throttle gives the EMA a stable
-- dt.
st.druid_energy.TTD_SAMPLE_SECONDS = 0.25

-- Debuff bars glow while the remaining time is inside the final seconds (reference
-- MANGLE/RIP/RAKE_GLOW_WINDOW, SuperSwingTimer_ClassMods.lua:4794, 4926, 5071).
st.druid_energy.DEBUFF_GLOW_SECONDS = 4

-- Pure: fraction of the way through the current energy cycle, in [0, 1). Mirrors the
-- reference's tickProgress: the time elapsed since the anchor, modulo the cycle length
-- (SuperSwingTimer_ClassMods.lua:4672-4677). A negative elapsed time (anchor in the
-- future - a reload or a clock-domain mismatch) reads 0; a missing/non-number anchor or
-- now reads 0; a missing/non-positive/non-number cycle falls back to the shipped tick
-- length so a caller bug degrades to a sane phase instead of a division by zero.
function st.druid_energy.get_energy_tick_fraction(anchor_time, now, cycle)
    if type(anchor_time) ~= "number" or type(now) ~= "number" then
        return 0
    end
    local duration = cycle
    if type(duration) ~= "number" or duration <= 0 then
        duration = st.druid_energy.ENERGY_TICK_SECONDS
    end
    local elapsed = now - anchor_time
    if elapsed < 0 then
        elapsed = 0
    end
    return (elapsed % duration) / duration
end

-- Pure: is a power delta the game's own energy tick? The reference accepts the 19-22
-- window (SuperSwingTimer_ClassMods.lua:4544-4546). Only numbers can qualify, so a
-- secret/non-numeric reading can never be mistaken for a tick.
function st.druid_energy.is_natural_gain(delta)
    return type(delta) == "number"
        and delta >= st.druid_energy.ENERGY_GAIN_MIN
        and delta <= st.druid_energy.ENERGY_GAIN_MAX
end

-- Pure: the proc-adjusted power delta for the D2 proc-aware tick clock
-- (bench/competitor_gaps_2026-10-19.md §Druid D2: Combat-Potency-style grants must
-- not re-anchor). A known proc grant observed since the last sample (SoD
-- King-of-the-Jungle Tiger's Fury +60, docs/research/rotations_sod.md - SoD-only)
-- is removed before the tick classifier runs, so a tick landing in the proc frame
-- still re-anchors (delta 80 - 60 = 20) and a capped proc partial (delta 20 with
-- no tick) never forges one. Anything unreadable reads nil; a missing, zero or
-- non-number proc grant degrades to the raw delta (the legacy path, unchanged).
function st.druid_energy.adjust_gain_for_procs(delta, proc_gain)
    if type(delta) ~= "number" or delta ~= delta then
        return nil
    end
    if type(proc_gain) ~= "number" or proc_gain ~= proc_gain or proc_gain == 0 then
        return delta
    end
    return delta - proc_gain
end

-- Pure: proc-aware natural-tick classifier. A nil/zero/unreadable proc grant runs
-- the legacy 19-22 window verbatim (is_natural_gain above); otherwise the adjusted
-- delta decides. Only numbers can qualify, so a secret reading is never a tick.
function st.druid_energy.is_tick_gain(delta, proc_gain)
    return st.druid_energy.is_natural_gain(
        st.druid_energy.adjust_gain_for_procs(delta, proc_gain))
end

-- Pure: the bar label for a UnitPowerType reading: 3 (energy) -> Cat, 1 (rage) -> Bear,
-- anything else (mana) -> Caster (reference GetDruidFormLabel,
-- SuperSwingTimer_ClassMods.lua:4530-4538).
function st.druid_energy.get_form_label(power_type)
    if power_type == 3 then
        return "Cat"
    end
    if power_type == 1 then
        return "Bear"
    end
    return "Caster"
end

-- Pure: remaining seconds of a tracked target debuff for display, floored at 0, plus the
-- bar's total span. A missing/non-positive expiration stamp falls back to the full
-- duration, and a missing/non-positive duration to the bar's own fallback (reference
-- Mangle handling, SuperSwingTimer_ClassMods.lua:4890-4900; Rip/Rake share the shape).
function st.druid_energy.get_debuff_remaining(duration, expiration_time, now, fallback_duration)
    local total = duration
    if type(total) ~= "number" or total <= 0 then
        total = fallback_duration
    end
    if type(total) ~= "number" or total <= 0 then
        total = 0
    end
    if type(expiration_time) == "number" and expiration_time > 0 and type(now) == "number" then
        local remaining = expiration_time - now
        if remaining < 0 then
            remaining = 0
        end
        return remaining, total
    end
    return total, total
end

-- Pure: should a debuff bar glow? Only while the debuff is up and inside the final
-- seconds (reference SetMangleGlow family, e.g. SuperSwingTimer_ClassMods.lua:4800).
function st.druid_energy.should_debuff_glow(remaining)
    return type(remaining) == "number"
        and remaining > 0
        and remaining <= st.druid_energy.DEBUFF_GLOW_SECONDS
end

-- Pure: one EMA step of HP/s (the D4 estimator's smoothing step). hp / prev_hp are
-- hit points, dt the seconds between the samples, alpha the weight of the newest
-- sample. A heal (hp > prev_hp) contributes zero velocity: healing does not resurrect
-- a time-to-die, and a negative velocity would flip the division below into nonsense.
-- The first sample (a non-number ema) seeds from the raw velocity; every later sample
-- smooths. Anything unreadable (missing/non-number/NaN hp, a non-positive dt) returns
-- nil, which the caller reads as "drop the baseline and re-seed" - a poisoned sample
-- must never linger in the EMA.
function st.druid_energy.update_hp_velocity(ema, hp, prev_hp, dt, alpha)
    if type(hp) ~= "number" or type(prev_hp) ~= "number"
        or hp ~= hp or prev_hp ~= prev_hp
        or type(dt) ~= "number" or dt <= 0 or dt ~= dt then
        return nil
    end
    local weight = alpha
    if type(weight) ~= "number" or weight <= 0 or weight > 1 or weight ~= weight then
        weight = st.druid_energy.TTD_EMA_ALPHA
    end
    local velocity = (prev_hp - hp) / dt
    if velocity < 0 then
        velocity = 0
    end
    if type(ema) ~= "number" or ema ~= ema then
        return velocity
    end
    return weight * velocity + (1 - weight) * ema
end

-- Pure: the time-to-die estimate from a smoothed HP/s and the live HP: hp / velocity
-- while the velocity is a positive number (a zero/negative velocity has no finite
-- crossing). Unreadable or NaN inputs read nil - the caller treats that as unknown,
-- never as an estimate.
function st.druid_energy.get_time_to_die(hp, hp_velocity)
    if type(hp) ~= "number" or type(hp_velocity) ~= "number"
        or hp ~= hp or hp_velocity ~= hp_velocity or hp_velocity <= 0 then
        return nil
    end
    return hp / hp_velocity
end

-- Pure: the D1 time-to-die readout text ("TTD 8s"), or nil when the estimate is
-- unknown - the caller hides the readout then, never guessing a number. Rounds to
-- the nearest whole second (the badge/countdown quantise idiom); a zero estimate
-- (already dead) reads "TTD 0s", never nil.
function st.druid_energy.format_time_to_die(ttd_seconds)
    if type(ttd_seconds) ~= "number" or ttd_seconds ~= ttd_seconds or ttd_seconds < 0 then
        return nil
    end
    return "TTD " .. tostring(math.floor(ttd_seconds + 0.5)) .. "s"
end

-- Pure: seconds until the energy cycle has paid `cost` from `energy`, given the same
-- cycle anchor the tick bar maintains (the D5 "Shred in Xs" countdown). ticks =
-- ceil(deficit / gain); the wait is the time to the next tick boundary plus the
-- remaining full cycles. 0 when the cost is already affordable; nil when the inputs
-- cannot answer (unreadable or NaN energy/cost/anchor/clock) - the caller hides then,
-- never guessing a countdown.
function st.druid_energy.get_time_to_energy_cost(anchor_time, now, energy, cost, cycle, gain)
    if type(energy) ~= "number" or type(cost) ~= "number"
        or energy ~= energy or cost ~= cost then
        return nil
    end
    local deficit = cost - energy
    if deficit <= 0 then
        return 0
    end
    if type(anchor_time) ~= "number" or type(now) ~= "number"
        or anchor_time ~= anchor_time or now ~= now then
        return nil
    end
    local duration = cycle
    if type(duration) ~= "number" or duration <= 0 or duration ~= duration then
        duration = st.druid_energy.ENERGY_TICK_SECONDS
    end
    local per_tick = gain
    if type(per_tick) ~= "number" or per_tick <= 0 or per_tick ~= per_tick then
        per_tick = st.druid_energy.ENERGY_TICK_GAIN
    end
    local ticks = math.ceil(deficit / per_tick)
    local elapsed = now - anchor_time
    if elapsed < 0 then
        elapsed = 0
    end
    local since_tick = elapsed % duration
    return (duration - since_tick) + (ticks - 1) * duration
end

-- Pure: the height fraction (0-1) on the energy tick column where the fill will stand
-- when the running GCD ends - the "GCD tick overlay" the feral packs put on the energy
-- bar (discover #4). The cycle fraction now plus the GCD's remaining share of the
-- cycle, clamped to the column. nil when the inputs cannot answer (no GCD running, an
-- unreadable/NaN anchor or clock) - the caller hides the marker then.
function st.druid_energy.get_gcd_tick_fraction(anchor_time, now, gcd_remaining, cycle)
    if type(gcd_remaining) ~= "number" or gcd_remaining <= 0 or gcd_remaining ~= gcd_remaining then
        return nil
    end
    if type(anchor_time) ~= "number" or type(now) ~= "number"
        or anchor_time ~= anchor_time or now ~= now then
        return nil
    end
    local duration = cycle
    if type(duration) ~= "number" or duration <= 0 or duration ~= duration then
        duration = st.druid_energy.ENERGY_TICK_SECONDS
    end
    local fraction = st.druid_energy.get_energy_tick_fraction(anchor_time, now, duration)
        + gcd_remaining / duration
    if fraction < 0 then
        return 0
    end
    if fraction > 1 then
        return 1
    end
    return fraction
end

-- Pure: seconds to the next energy tick from the same anchor the tick bar
-- maintains (the trick/pooling groundwork: the sims' ShredTrick/RipTrick windows,
-- the TBC MangleTrick/RakeTrick/BiteTrick windows and the Forever 2 s/1 s pooling
-- horizons all read time-to-next-tick). Duration fallback mirrors
-- get_energy_tick_fraction above. Unreadable anchor/clock reads nil (the caller
-- treats that as unknown, never a guessed window); a future anchor (reload or a
-- clock-domain mismatch) reads the full duration.
function st.druid_energy.get_tick_remaining(anchor_time, now, cycle)
    if type(anchor_time) ~= "number" or type(now) ~= "number"
        or anchor_time ~= anchor_time or now ~= now then
        return nil
    end
    local duration = cycle
    if type(duration) ~= "number" or duration <= 0 or duration ~= duration then
        duration = st.druid_energy.ENERGY_TICK_SECONDS
    end
    local elapsed = now - anchor_time
    if elapsed < 0 then
        elapsed = 0
    end
    local since_tick = elapsed % duration
    return duration - since_tick
end

-- Pure: is an energy reading inside a trick window [low, high] (both ends
-- inclusive; the sims' [biteCost,39] and [biteCost,mangleCost) bands)? Only
-- numbers can qualify, so an unreadable energy or bound never opens a window.
-- NaN-safe: every comparison is false for NaN.
function st.druid_energy.is_energy_in_window(energy, low, high)
    if type(energy) ~= "number" or type(low) ~= "number" or type(high) ~= "number" then
        return false
    end
    return energy >= low and energy <= high
end

-- Helpers above are reachable via st.druid_energy and pure (no WoW globals).
if st.debug then st.utils.print_msg('-- Parsed druid_energy.lua correctly') end
