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

-- Natural-gain classifier window: a power gain inside [19, 22] is the game's own energy
-- tick and re-anchors the cycle (reference IsLikelyNaturalDruidEnergyGain,
-- SuperSwingTimer_ClassMods.lua:4544-4546).
st.druid_energy.ENERGY_GAIN_MIN = 19
st.druid_energy.ENERGY_GAIN_MAX = 22

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

-- Helpers above are reachable via st.druid_energy and pure (no WoW globals).
if st.debug then st.utils.print_msg('-- Parsed druid_energy.lua correctly') end
