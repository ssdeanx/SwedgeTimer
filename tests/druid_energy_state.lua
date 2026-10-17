-- tests/druid_energy_state.lua: offline tests for the pure druid maths module
-- (druid_energy.lua): the energy tick cycle fraction and its modulo/negative-clamp
-- behaviour, the 19-22 natural-gain classifier, the form-label power-type mapping and
-- the debuff bar display helpers (remaining/total, fallback durations, glow window).
-- The module is loaded in a bare sandbox - no WoW globals at all - so a stray global
-- read inside it raises instead of silently passing.
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
local function near(got, want, tol, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > tol then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

-- Bare sandbox: the Lua 5.1 standard globals only (whitelisted one by one) plus the
-- addon namespace table. Every WoW global is absent, so a chunk that read one - e.g. a
-- clock or a Unit* function - would raise here instead of silently passing.
local env = {
    type = type, tostring = tostring, tonumber = tonumber, pairs = pairs,
    ipairs = ipairs, next = next, select = select, unpack = unpack,
    math = math, string = string, table = table, os = os,
}
local st = {}
local chunk = assert(loadfile(ROOT .. "druid_energy.lua"))
setfenv(chunk, env)
chunk("SwedgeTimer", st)

local de = st.druid_energy
check(type(de) == "table", "druid_energy.lua loads and defines st.druid_energy")

--=========================================================================================
-- 1) Constants
--=========================================================================================
eq(de.ENERGY_TICK_SECONDS, 2.0, "the energy tick cycle is the reference's 2.0 s")
eq(de.ENERGY_GAIN_MIN, 19, "the natural-gain window starts at 19")
eq(de.ENERGY_GAIN_MAX, 22, "the natural-gain window ends at 22")
eq(de.DEBUFF_GLOW_SECONDS, 4, "the debuff glow window is the reference's final 4 s")

--=========================================================================================
-- 2) get_energy_tick_fraction: the reference's elapsed-modulo-cycle maths
--=========================================================================================
near(de.get_energy_tick_fraction(0, 0, 2), 0, 1e-9, "a fresh anchor starts at 0")
near(de.get_energy_tick_fraction(0, 0.5, 2), 0.25, 1e-9, "half a second is a quarter cycle")
near(de.get_energy_tick_fraction(0, 1, 2), 0.5, 1e-9, "one second is half the cycle")
near(de.get_energy_tick_fraction(0, 1.5, 2), 0.75, 1e-9, "1.5 s is three quarters")
near(de.get_energy_tick_fraction(0, 1.999, 2), 0.9995, 1e-9, "the fraction approaches 1 at the tick")
near(de.get_energy_tick_fraction(0, 2, 2), 0, 1e-9, "the fraction wraps at the cycle length")
near(de.get_energy_tick_fraction(0, 3, 2), 0.5, 1e-9, "a missed reset keeps cycling")
near(de.get_energy_tick_fraction(100, 101, 2), 0.5, 1e-9, "the fraction is anchor-relative")
near(de.get_energy_tick_fraction(100, 99, 2), 0, 1e-9, "an anchor in the future clamps to 0")
near(de.get_energy_tick_fraction(100, 100.001, 2), 0.0005, 1e-9, "a tiny elapsed time is a tiny fraction")
near(de.get_energy_tick_fraction(0, 2001, 2), 0.5, 1e-9, "a large elapsed time still wraps")
near(de.get_energy_tick_fraction(nil, 5, 2), 0, 1e-9, "a missing anchor reads 0")
near(de.get_energy_tick_fraction(5, nil, 2), 0, 1e-9, "a missing now reads 0")
near(de.get_energy_tick_fraction("5", 5, 2), 0, 1e-9, "a non-number anchor reads 0")
near(de.get_energy_tick_fraction(0, 1, 4), 0.25, 1e-9, "a wider cycle scales the fraction")
near(de.get_energy_tick_fraction(0, 1, 0), 0.5, 1e-9, "a zero cycle falls back to the shipped 2.0 s")
near(de.get_energy_tick_fraction(0, 1, nil), 0.5, 1e-9, "a missing cycle falls back to the shipped length")
near(de.get_energy_tick_fraction(0, 1, -2), 0.5, 1e-9, "a negative cycle falls back to the shipped length")
near(de.get_energy_tick_fraction(0, 1, "2"), 0.5, 1e-9, "a non-number cycle falls back to the shipped length")

--=========================================================================================
-- 3) is_natural_gain: the reference's inclusive 19-22 window
--=========================================================================================
eq(de.is_natural_gain(19), true, "the lower bound of the window qualifies")
eq(de.is_natural_gain(20), true, "the common +20 tick qualifies")
eq(de.is_natural_gain(22), true, "the upper bound of the window qualifies")
eq(de.is_natural_gain(20.5), true, "a fractional reading inside the window qualifies")
eq(de.is_natural_gain(18.999), false, "just below the window does not qualify")
eq(de.is_natural_gain(22.001), false, "just above the window does not qualify")
eq(de.is_natural_gain(0), false, "no gain does not qualify")
eq(de.is_natural_gain(-20), false, "an energy spend does not qualify")
eq(de.is_natural_gain(nil), false, "a missing delta does not qualify")
eq(de.is_natural_gain("20"), false, "a non-number delta does not qualify")
eq(de.is_natural_gain(false), false, "a boolean does not qualify")

--=========================================================================================
-- 4) get_form_label: the power-type mapping
--=========================================================================================
eq(de.get_form_label(3), "Cat", "energy power type labels Cat")
eq(de.get_form_label(1), "Bear", "rage power type labels Bear")
eq(de.get_form_label(0), "Caster", "mana power type labels Caster")
eq(de.get_form_label(4), "Caster", "other power types label Caster")
eq(de.get_form_label(nil), "Caster", "a missing power type labels Caster")
eq(de.get_form_label("3"), "Caster", "a non-number power type labels Caster")

--=========================================================================================
-- 5) get_debuff_remaining: remaining/total with the reference fallbacks
--=========================================================================================
do
    local remaining, total = de.get_debuff_remaining(12, 108, 100, 12)
    near(remaining, 8, 1e-9, "remaining counts down from the expiration stamp")
    near(total, 12, 1e-9, "total is the aura's own duration")

    remaining, total = de.get_debuff_remaining(12, 100, 100, 12)
    near(remaining, 0, 1e-9, "an expiring debuff floors at 0")
    near(total, 12, 1e-9, "an expiring debuff keeps its total")

    remaining, total = de.get_debuff_remaining(12, 90, 100, 12)
    near(remaining, 0, 1e-9, "an expired debuff floors at 0 (never negative)")
    near(total, 12, 1e-9, "an expired debuff keeps its total")

    remaining, total = de.get_debuff_remaining(nil, 105, 100, 12)
    near(remaining, 5, 1e-9, "a missing duration still counts down from the expiration")
    near(total, 12, 1e-9, "a missing duration falls back to the bar's default (12)")

    remaining, total = de.get_debuff_remaining(0, 104, 100, 9)
    near(remaining, 4, 1e-9, "a zero duration still counts down")
    near(total, 9, 1e-9, "a zero duration falls back to the bar's default (9)")

    remaining, total = de.get_debuff_remaining(-5, 107, 100, 9)
    near(remaining, 7, 1e-9, "a negative duration still counts down")
    near(total, 9, 1e-9, "a negative duration falls back to the bar's default")

    remaining, total = de.get_debuff_remaining(12, nil, 100, 12)
    near(remaining, 12, 1e-9, "a missing expiration reads as the full duration")
    near(total, 12, 1e-9, "a missing expiration keeps the total")

    remaining, total = de.get_debuff_remaining(12, 0, 100, 12)
    near(remaining, 12, 1e-9, "a zero expiration reads as the full duration")
    near(total, 12, 1e-9, "a zero expiration keeps the total")

    remaining, total = de.get_debuff_remaining(12, 108, nil, 12)
    near(remaining, 12, 1e-9, "a missing clock reads as the full duration")
    near(total, 12, 1e-9, "a missing clock keeps the total")

    remaining, total = de.get_debuff_remaining(nil, nil, 100, nil)
    near(remaining, 0, 1e-9, "no duration and no fallback reads 0 remaining")
    near(total, 0, 1e-9, "no duration and no fallback reads 0 total")
end

--=========================================================================================
-- 6) should_debuff_glow: the final-4-seconds boundary
--=========================================================================================
eq(de.should_debuff_glow(4), true, "exactly 4 s left still glows (inclusive window)")
eq(de.should_debuff_glow(3.99), true, "just inside the window glows")
eq(de.should_debuff_glow(0.001), true, "just above expiry glows")
eq(de.should_debuff_glow(4.001), false, "just outside the window does not glow")
eq(de.should_debuff_glow(5), false, "above the window does not glow")
eq(de.should_debuff_glow(0), false, "an expired debuff does not glow")
eq(de.should_debuff_glow(-1), false, "a negative remainder does not glow")
eq(de.should_debuff_glow(nil), false, "a missing remainder does not glow")
eq(de.should_debuff_glow("4"), false, "a non-number remainder does not glow")

if failures == 0 then
    print("PASS  druid_energy_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  druid_energy_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
