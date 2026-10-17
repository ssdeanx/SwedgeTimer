-- tests/weave_state.lua: unit tests for the pure weave math helpers in weave.lua.
-- Sandbox-loads weave.lua with a setmetatable environment (__index = _G); the module
-- needs no LibStub and no WoW globals. Plain Lua 5.1, no WoW client needed.
-- Run from the repo root: lua5.1 tests/weave_state.lua

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL  " .. label) end
end
local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then failures = failures + 1; print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")") end
end
local function near(got, want, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > 1e-9 then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

local st = {}
local env = setmetatable({}, { __index = _G })
env.ST = st

local mod = assert(loadfile(ROOT .. "weave.lua"))
setfenv(mod, env)
local ok, err = pcall(function() mod("SwedgeTimer", st) end)
check(ok, "weave.lua loads under the sandbox (" .. tostring(err) .. ")")
local weave = st.weave
check(type(weave) == "table", "st.weave table exists")

-- constants ----------------------------------------------------------------
eq(weave.MW_MAX_STACKS, 5, "MW_MAX_STACKS == 5")
near(weave.MW_PER_STACK, 0.20, "MW_PER_STACK == 0.20")

-- clamp_fraction -----------------------------------------------------------
eq(weave.clamp_fraction(0.5), 0.5, "clamp: 0.5 stays 0.5")
eq(weave.clamp_fraction(0), 0, "clamp: 0 stays 0")
eq(weave.clamp_fraction(1), 1, "clamp: 1 stays 1")
eq(weave.clamp_fraction(-0.2), 0, "clamp: negative floors to 0")
eq(weave.clamp_fraction(2), 1, "clamp: > 1 ceilings to 1")
eq(weave.clamp_fraction(nil), 0, "clamp: nil -> 0")
eq(weave.clamp_fraction("0.5"), 0, "clamp: non-number string -> 0")
eq(weave.clamp_fraction(true), 0, "clamp: non-number boolean -> 0")

-- get_haste_multiplier -----------------------------------------------------
eq(weave.get_haste_multiplier(0), 1, "haste: 0% -> 1")
near(weave.get_haste_multiplier(20), 1.2, "haste: 20% -> 1.2")
near(weave.get_haste_multiplier(100), 2, "haste: 100% -> 2")
eq(weave.get_haste_multiplier(nil), 1, "haste: nil -> 1")
eq(weave.get_haste_multiplier(-5), 1, "haste: negative -> 1")

-- get_max_haste_multiplier -------------------------------------------------
near(weave.get_max_haste_multiplier(20, 1.30), 1.30, "max haste: 1.30 buff beats 1.2 haste")
near(weave.get_max_haste_multiplier(20, 1.10), 1.2, "max haste: 1.2 haste beats 1.10 buff")
near(weave.get_max_haste_multiplier(50, 1.30), 1.5, "max haste: 1.5 haste beats 1.30 buff")
near(weave.get_max_haste_multiplier(100, 1.30), 2, "max haste: maxed, not multiplied (2, not 2.6)")
eq(weave.get_max_haste_multiplier(nil, nil), 1, "max haste: both nil -> 1")
eq(weave.get_max_haste_multiplier(0, 1), 1, "max haste: no haste, no buff -> 1")
near(weave.get_max_haste_multiplier(-5, 1.30), 1.30, "max haste: negative haste, buff wins")

-- get_maelstrom_multiplier -------------------------------------------------
eq(weave.get_maelstrom_multiplier(0), 1, "MW: 0 stacks -> 1")
near(weave.get_maelstrom_multiplier(1), 0.8, "MW: 1 stack -> 0.8")
near(weave.get_maelstrom_multiplier(3), 0.4, "MW: 3 stacks -> 0.4")
eq(weave.get_maelstrom_multiplier(5), 0, "MW: 5 stacks -> 0 (instant)")
eq(weave.get_maelstrom_multiplier(7), 0, "MW: 7 stacks clamped to 5 -> 0")
eq(weave.get_maelstrom_multiplier(-2), 1, "MW: negative stacks -> 0 stacks -> 1")
eq(weave.get_maelstrom_multiplier(nil), 1, "MW: nil -> 0 stacks -> 1")

-- get_effective_cast_time --------------------------------------------------
eq(weave.get_effective_cast_time(2.5, 1, 1, true), 0, "cast: instant flag -> 0")
eq(weave.get_effective_cast_time(2.5, 1, 0, false), 0, "cast: MW multiplier 0 -> 0")
eq(weave.get_effective_cast_time(2.5, 1, -0.5, false), 0, "cast: MW multiplier negative -> 0")
near(weave.get_effective_cast_time(2.5, 1, 1, false), 2.5, "cast: base only")
near(weave.get_effective_cast_time(2.5, 1.2, 1, false), 2.5 / 1.2, "cast: base / haste")
near(weave.get_effective_cast_time(2.5, 1, 0.4, false), 1.0, "cast: base * MW multiplier")
near(weave.get_effective_cast_time(2.5, 1.2, 0.4, false), (2.5 / 1.2) * 0.4, "cast: base / haste * MW")
near(weave.get_effective_cast_time(2.5, 0, 1, false), 2.5, "cast: zero haste treated as 1")
near(weave.get_effective_cast_time(2.5, -3, 1, false), 2.5, "cast: negative haste treated as 1")
eq(weave.get_effective_cast_time(0, 1, 1, false), 0, "cast: base 0 -> 0")
eq(weave.get_effective_cast_time(-2, 1, 1, false), 0, "cast: negative base -> 0")
eq(weave.get_effective_cast_time(nil, 1, 1, false), 0, "cast: nil base -> 0")
near(weave.get_effective_cast_time(2.5, 1, nil, false), 2.5, "cast: nil MW multiplier treated as 1")
near(weave.get_effective_cast_time(2.5, nil, 1, false), 2.5, "cast: nil haste treated as 1")
near(weave.get_effective_cast_time(2.5, 1, 1, nil), 2.5, "cast: nil instant flag -> not instant")

-- get_marker_fraction ------------------------------------------------------
near(weave.get_marker_fraction(4, 2.5, 0), 0.375, "marker: 4s swing, 2.5s cast, 0 latency -> 0.375")
near(weave.get_marker_fraction(4, 2.5, 0.1), 0.35, "marker: latency shifts the marker left")
near(weave.get_marker_fraction(4, 2, 0), 0.5, "marker: 2s cast -> 0.5")
near(weave.get_marker_fraction(4, 3.2, 0.2), 0.15, "marker: 3.4s cast+latency -> 0.15")
eq(weave.get_marker_fraction(4, 4, 0), 0, "marker: cast == duration -> 0 boundary")
eq(weave.get_marker_fraction(4, 3.5, 1), 0, "marker: cast+latency > duration clamps to 0")
eq(weave.get_marker_fraction(0, 2.5, 0), 0, "marker: zero duration -> 0")
eq(weave.get_marker_fraction(-1, 0, 0), 0, "marker: negative duration -> 0")
near(weave.get_marker_fraction(4, 2.5, nil), 0.375, "marker: nil latency treated as 0")
near(weave.get_marker_fraction(4, nil, 0), 1, "marker: nil cast treated as 0 -> 1")

-- get_safe_start_in --------------------------------------------------------
near(weave.get_safe_start_in(5, 1, 0.1, 2.5), 1.4, "safe start: window still open")
check(weave.get_safe_start_in(5, 1, 0.1, 2.5) > 0, "safe start: positive when open")
near(weave.get_safe_start_in(2, 1, 0.1, 2.5), -1.6, "safe start: negative when passed")
check(weave.get_safe_start_in(2, 1, 0.1, 2.5) < 0, "safe start: negative not clamped")
eq(weave.get_safe_start_in(3, 1, 0, 2), 0, "safe start: exact boundary -> 0")
near(weave.get_safe_start_in(3.5, 1, 0.25, 0.75), 1.5, "safe start: latency and cast both subtract")

-- get_clip_amount ----------------------------------------------------------
eq(weave.get_clip_amount(1, 0.1, 2.5, 5), 0, "clip: cast ends before the swing -> 0")
near(weave.get_clip_amount(3.9, 0.1, 2.5, 5), 1.5, "clip: overrun measured in seconds")
eq(weave.get_clip_amount(2.4, 0.1, 2.5, 5), 0, "clip: exactly at the swing -> 0 (strict >)")
near(weave.get_clip_amount(2.4001, 0.1, 2.5, 5), 0.0001, "clip: just past the swing -> small positive")
eq(weave.get_clip_amount(10, 0, 0, 5), 5, "clip: no cast, no latency")
near(weave.get_clip_amount(1, 0.1, 2.5, 3), 0.6, "clip: latency and remaining cast counted")

-- is_clipped ---------------------------------------------------------------
eq(weave.is_clipped(1, nil, 0.5), true, "clipped: positive clip amount")
eq(weave.is_clipped(0.001, nil, 0.5), true, "clipped: tiny positive clip amount")
eq(weave.is_clipped(0, 0.6, 0.5), true, "clipped: cast started after the marker")
eq(weave.is_clipped(0, 0.5, 0.5), false, "clipped: at the marker is not clipped (strict >)")
eq(weave.is_clipped(0, 0.4, 0.5), false, "clipped: started before the marker")
eq(weave.is_clipped(0, nil, 0.5), false, "clipped: no clip amount, no cast-start fraction")
eq(weave.is_clipped(nil, nil, nil), false, "clipped: all missing -> false")
eq(weave.is_clipped(0, 0.9, 0), true, "clipped: marker 0, started later")

-- get_projected_impact_fraction --------------------------------------------
near(weave.get_projected_impact_fraction(1, 1, 0.1, 0, 4), 0.525, "projected: (1+1+0.1)/4")
near(weave.get_projected_impact_fraction(2, 0, 0, 0, 4), 0.5, "projected: half the swing")
near(weave.get_projected_impact_fraction(1, 1, 0, 1, 4), 0.25, "projected: swing_start offsets")
eq(weave.get_projected_impact_fraction(3, 5, 1, 0, 4), 1, "projected: over the swing clamps to 1")
eq(weave.get_projected_impact_fraction(0, 0, 0, 4, 4), 0, "projected: before the swing clamps to 0")
eq(weave.get_projected_impact_fraction(1, 0.5, 0.25, 3, 4), 0, "projected: negative impact -> 0")
eq(weave.get_projected_impact_fraction(4, 0, 0, 4, 4), 0, "projected: exactly at swing end -> 0")

-- get_cast_start_fraction --------------------------------------------------
near(weave.get_cast_start_fraction(1, 0, 4), 0.25, "cast start: 1s into a 4s swing")
near(weave.get_cast_start_fraction(3, 0, 4), 0.75, "cast start: 3s into a 4s swing")
near(weave.get_cast_start_fraction(2, 1, 4), 0.25, "cast start: swing_start offsets")
eq(weave.get_cast_start_fraction(-1, 0, 4), 0, "cast start: before the swing clamps to 0")
eq(weave.get_cast_start_fraction(5, 0, 4), 1, "cast start: past the swing clamps to 1")
eq(weave.get_cast_start_fraction(nil, 0, 4), 0, "cast start: nil start -> 0")

-- get_spark_fraction -------------------------------------------------------
near(weave.get_spark_fraction(0.25, 0.75, 0.5), 0.5, "spark: halfway between start and landing")
near(weave.get_spark_fraction(0.25, 0.75, 0), 0.25, "spark: at progress 0 sits at the start")
near(weave.get_spark_fraction(0.25, 0.75, 1), 0.75, "spark: at progress 1 sits at the landing")
near(weave.get_spark_fraction(0.25, 0.75, nil), 0.25, "spark: nil progress treated as 0")
near(weave.get_spark_fraction(2, 0.75, 0.5), 0.875, "spark: start clamped to 1 before interpolating")
near(weave.get_spark_fraction(-1, 0.75, 0.5), 0.375, "spark: start clamped to 0 before interpolating")
near(weave.get_spark_fraction(0.25, 2, 0.5), 0.625, "spark: landing clamped to 1 before interpolating")
near(weave.get_spark_fraction(0.25, 0.75, 2), 0.75, "spark: progress > 1 clamped to 1")
near(weave.get_spark_fraction(0.25, 0.75, -1), 0.25, "spark: progress < 0 clamped to 0")
eq(weave.get_spark_fraction(nil, nil, nil), 0, "spark: all missing -> 0")

-- tracker constants ---------------------------------------------------------
eq(weave.WINDFURY_ICD_SECONDS, 3, "WINDFURY_ICD_SECONDS == 3")
near(weave.WINDFURY_TINT_RED_ABOVE, 2.0, "WINDFURY_TINT_RED_ABOVE == 2.0")
near(weave.WINDFURY_TINT_ORANGE_ABOVE, 0.5, "WINDFURY_TINT_ORANGE_ABOVE == 0.5")
eq(weave.FLAME_SHOCK_FALLBACK_DURATION, 12, "FLAME_SHOCK_FALLBACK_DURATION == 12")
eq(weave.FLAME_SHOCK_GLOW_SECONDS, 4, "FLAME_SHOCK_GLOW_SECONDS == 4")
eq(weave.SHIELD_MAX_CHARGES.lightning, 4, "Lightning Shield max charges == 4")
eq(weave.SHIELD_MAX_CHARGES.water, 3, "Water Shield max charges == 3")

-- get_windfury_icd_remaining -----------------------------------------------
near(weave.get_windfury_icd_remaining(100, 100.5), 2.5, "windfury: 0.5s after the swing -> 2.5s left")
near(weave.get_windfury_icd_remaining(100, 102.5), 0.5, "windfury: mid-cooldown remainder")
eq(weave.get_windfury_icd_remaining(100, 103), 0, "windfury: cooldown elapsed -> 0")
eq(weave.get_windfury_icd_remaining(100, 200), 0, "windfury: long past the swing -> 0 (floored)")
eq(weave.get_windfury_icd_remaining(100, 99.5), 3, "windfury: future swing stamp floors the elapsed at 0")
eq(weave.get_windfury_icd_remaining(nil, 5), nil, "windfury: no swing stamp -> nil")
eq(weave.get_windfury_icd_remaining(0, 5), nil, "windfury: zero swing stamp -> nil")
eq(weave.get_windfury_icd_remaining(-5, 5), nil, "windfury: negative swing stamp -> nil")
eq(weave.get_windfury_icd_remaining("100", 5), nil, "windfury: non-number swing stamp -> nil")
near(weave.get_windfury_icd_remaining(100, nil), 3, "windfury: nil now reads as the full window")

-- get_windfury_tint_bucket --------------------------------------------------
eq(weave.get_windfury_tint_bucket(3), "red", "windfury tint: full window -> red")
eq(weave.get_windfury_tint_bucket(2.01), "red", "windfury tint: just above 2s -> red")
eq(weave.get_windfury_tint_bucket(2), "orange", "windfury tint: exactly 2s -> orange (strict >)")
eq(weave.get_windfury_tint_bucket(0.51), "orange", "windfury tint: just above 0.5s -> orange")
eq(weave.get_windfury_tint_bucket(0.5), "green", "windfury tint: exactly 0.5s -> green (strict >)")
eq(weave.get_windfury_tint_bucket(0), "green", "windfury tint: ready -> green")
eq(weave.get_windfury_tint_bucket(-2), "green", "windfury tint: negative -> green")
eq(weave.get_windfury_tint_bucket(nil), "green", "windfury tint: missing reading -> green")
eq(weave.get_windfury_tint_bucket("2"), "green", "windfury tint: non-number -> green")

-- get_flame_shock_remaining -------------------------------------------------
local fs_remaining, fs_total = weave.get_flame_shock_remaining(12, 108, 100)
near(fs_remaining, 8, "flame shock: 8s left on a 12s debuff")
near(fs_total, 12, "flame shock: total span is the reported duration")
near(weave.get_flame_shock_remaining(12, 100, 100), 0, "flame shock: elapsed -> 0 (floored)")
near(weave.get_flame_shock_remaining(12, 90, 100), 0, "flame shock: expired -> 0")
local fs_r2, fs_t2 = weave.get_flame_shock_remaining(5, nil, 100)
near(fs_r2, 5, "flame shock: no expiration -> full duration")
near(fs_t2, 5, "flame shock: no expiration -> duration total")
local fs_r3, fs_t3 = weave.get_flame_shock_remaining(nil, 106, 100)
near(fs_r3, 6, "flame shock: missing duration still counts down from the stamp")
near(fs_t3, 12, "flame shock: missing duration -> fallback total")
local fs_r4, fs_t4 = weave.get_flame_shock_remaining(nil, nil, 100)
near(fs_r4, 12, "flame shock: no payload at all -> fallback duration")
near(fs_t4, 12, "flame shock: no payload at all -> fallback total")
local fs_r5, fs_t5 = weave.get_flame_shock_remaining(0, 106, 100)
near(fs_r5, 6, "flame shock: non-positive duration -> fallback total, stamp counted")
near(fs_t5, 12, "flame shock: non-positive duration -> fallback total")
local fs_r6, fs_t6 = weave.get_flame_shock_remaining(-3, -3, 100)
near(fs_r6, 12, "flame shock: non-positive duration and stamp -> fallback duration")
near(fs_t6, 12, "flame shock: non-positive duration and stamp -> fallback total")

-- should_flame_shock_glow ---------------------------------------------------
eq(weave.should_flame_shock_glow(4), true, "flame shock glow: at 4s -> glow")
eq(weave.should_flame_shock_glow(0.1), true, "flame shock glow: just above 0 -> glow")
eq(weave.should_flame_shock_glow(4.01), false, "flame shock glow: above 4s -> no glow")
eq(weave.should_flame_shock_glow(0), false, "flame shock glow: elapsed -> no glow")
eq(weave.should_flame_shock_glow(-1), false, "flame shock glow: expired -> no glow")
eq(weave.should_flame_shock_glow(nil), false, "flame shock glow: missing -> no glow")
eq(weave.should_flame_shock_glow("4"), false, "flame shock glow: non-number -> no glow")

-- get_cooldown_remaining ----------------------------------------------------
near(weave.get_cooldown_remaining(100, 8, 103), 5, "cooldown: 5s left of the 8s window")
near(weave.get_cooldown_remaining(100, 8, 100), 8, "cooldown: at the start -> full duration")
eq(weave.get_cooldown_remaining(100, 8, 108), nil, "cooldown: elapsed -> nil")
eq(weave.get_cooldown_remaining(100, 8, 120), nil, "cooldown: long elapsed -> nil")
eq(weave.get_cooldown_remaining(0, 0, 5), nil, "cooldown: zero duration -> nil")
eq(weave.get_cooldown_remaining(0, -4, 5), nil, "cooldown: negative duration -> nil")
eq(weave.get_cooldown_remaining(nil, 8, 5), nil, "cooldown: no start stamp -> nil")
eq(weave.get_cooldown_remaining(0, "8", 5), nil, "cooldown: non-number duration -> nil")
near(weave.get_cooldown_remaining(100, 8, nil), 108, "cooldown: nil now reads as time 0")

-- get_shield_tracker_state --------------------------------------------------
local ls_slots, ls_filled = weave.get_shield_tracker_state("lightning", 2)
eq(ls_slots, 4, "shields: Lightning Shield row has 4 slots")
eq(ls_filled, 2, "shields: Lightning Shield fills the aura count")
local ls_s2, ls_f2 = weave.get_shield_tracker_state("lightning", nil)
eq(ls_s2, 4, "shields: missing Lightning count -> 4 slots")
eq(ls_f2, 4, "shields: missing count reads as full")
local ls_s3, ls_f3 = weave.get_shield_tracker_state("lightning", 9)
eq(ls_s3, 4, "shields: Lightning count above the cap clamps")
eq(ls_f3, 4, "shields: Lightning count above the cap reads full")
local ls_s4, ls_f4 = weave.get_shield_tracker_state("lightning", 2.6)
eq(ls_s4, 4, "shields: Lightning rounding keeps 4 slots")
eq(ls_f4, 3, "shields: fractional counts round to the nearest charge")
local ls_s5, ls_f5 = weave.get_shield_tracker_state("lightning", 0)
eq(ls_s5, 4, "shields: zero count still shows the 4 Lightning slots")
eq(ls_f5, 4, "shields: zero count reads as the full-row fallback")
local ws_slots, ws_filled = weave.get_shield_tracker_state("water", 1)
eq(ws_slots, 3, "shields: Water Shield row has 3 slots")
eq(ws_filled, 1, "shields: Water Shield fills the aura count")
local ws_s2, ws_f2 = weave.get_shield_tracker_state("water", nil)
eq(ws_s2, 3, "shields: missing Water count -> 3 slots")
eq(ws_f2, 3, "shields: missing Water count reads as full")
local ws_s3, ws_f3 = weave.get_shield_tracker_state("water", 5)
eq(ws_s3, 3, "shields: Water count above the cap clamps")
eq(ws_f3, 3, "shields: Water count above the cap reads full")
local no_slots, no_filled = weave.get_shield_tracker_state(nil, 2)
eq(no_slots, 0, "shields: no shield type -> no slots")
eq(no_filled, 0, "shields: no shield type -> no filled slots")
local bad_slots, bad_filled = weave.get_shield_tracker_state("bogus", 2)
eq(bad_slots, 0, "shields: unknown shield type -> no slots")
eq(bad_filled, 0, "shields: unknown shield type -> no filled slots")
local str_slots, str_filled = weave.get_shield_tracker_state("lightning", "2")
eq(str_slots, 4, "shields: non-number count keeps the Lightning slots")
eq(str_filled, 4, "shields: non-number count reads as full")

-- has_maelstrom_weapon ----------------------------------------------------
-- TBC never has Maelstrom Weapon; ERA needs the aura-observed latch (SoD HAS the
-- 408505 rune, Era-base never observes it); every other (and every unknown) family
-- keeps the current behaviour regardless of the latch (Wrath byte-identical).
eq(weave.has_maelstrom_weapon("TBC"), false, "MW gate: TBC has no Maelstrom Weapon")
eq(weave.has_maelstrom_weapon("TBC", true), false, "MW gate: TBC stays off even when observed")
eq(weave.has_maelstrom_weapon("ERA"), false, "MW gate: Era-base (never observed) has no Maelstrom Weapon")
eq(weave.has_maelstrom_weapon("ERA", nil), false, "MW gate: ERA + nil latch stays off")
eq(weave.has_maelstrom_weapon("ERA", false), false, "MW gate: ERA + false latch stays off")
eq(weave.has_maelstrom_weapon("ERA", true), true, "MW gate: ERA + observed (SoD rune) enables Maelstrom Weapon")
eq(weave.has_maelstrom_weapon("ERA", 1), false, "MW gate: only boolean true enables (no truthy latch)")
eq(weave.has_maelstrom_weapon("WRATH"), true, "MW gate: Wrath keeps Maelstrom Weapon")
eq(weave.has_maelstrom_weapon("WRATH", nil), true, "MW gate: Wrath ignores a nil latch")
eq(weave.has_maelstrom_weapon("WRATH", false), true, "MW gate: Wrath ignores a false latch")
eq(weave.has_maelstrom_weapon("WRATH", true), true, "MW gate: Wrath ignores a true latch (byte-identical)")
eq(weave.has_maelstrom_weapon("CATA"), true, "MW gate: Cata keeps Maelstrom Weapon")
eq(weave.has_maelstrom_weapon("CATA", true), true, "MW gate: Cata ignores the latch")
eq(weave.has_maelstrom_weapon("MISTS"), true, "MW gate: Mists keeps Maelstrom Weapon")
eq(weave.has_maelstrom_weapon("RETAIL"), true, "MW gate: Retail keeps Maelstrom Weapon")
eq(weave.has_maelstrom_weapon("FOREVER"), true, "MW gate: Forever keeps Maelstrom Weapon (bars_state pins the marker)")
eq(weave.has_maelstrom_weapon("UNKNOWN"), true, "MW gate: unknown families keep current behaviour")
eq(weave.has_maelstrom_weapon(nil), true, "MW gate: a missing family keeps current behaviour")
eq(weave.has_maelstrom_weapon(nil, true), true, "MW gate: a missing family ignores the latch")
eq(weave.has_maelstrom_weapon("tbc"), true, "MW gate: the match is case-sensitive (no silent miss)")
eq(weave.TOTEM_TWIST_PERIOD_SECONDS, 10, "TOTEM_TWIST_PERIOD_SECONDS == 10")
eq(weave.TOTEM_TWIST_PULSE_SECONDS, 9, "TOTEM_TWIST_PULSE_SECONDS == 9")

-- is_totem_twist_family ------------------------------------------------------
-- TBC only: Wrath never twists, Forever runs the party-buff totem model
-- (totems coexist with imbues - nothing to alternate), unknown families never
-- prompt on a guess.
eq(weave.is_totem_twist_family("TBC"), true, "twist family: TBC twists")
eq(weave.is_totem_twist_family("FOREVER"), false, "twist family: Forever never twists (party-buff totems)")
eq(weave.is_totem_twist_family("WRATH"), false, "twist family: Wrath never twists")
eq(weave.is_totem_twist_family("ERA"), false, "twist family: Era never twists")
eq(weave.is_totem_twist_family("RETAIL"), false, "twist family: Retail never twists")
eq(weave.is_totem_twist_family("CATA"), false, "twist family: Cata never twists")
eq(weave.is_totem_twist_family(nil), false, "twist family: a missing family never twists")
eq(weave.is_totem_twist_family("tbc"), false, "twist family: the match is case-sensitive (no silent miss)")

-- WINDFURY_MAX_PROCS_PER_MINUTE / is_windfury_proc_capped ---------------------
-- The 3 s ICD caps Windfury Weapon at 20 procs/min, shared across hands.
eq(weave.WINDFURY_MAX_PROCS_PER_MINUTE, 20, "WINDFURY_MAX_PROCS_PER_MINUTE == 20")
eq(weave.is_windfury_proc_capped(20), true, "proc ceiling: 20 procs read capped")
eq(weave.is_windfury_proc_capped(21), true, "proc ceiling: above 20 reads capped")
eq(weave.is_windfury_proc_capped(19), false, "proc ceiling: 19 procs read uncapped")
eq(weave.is_windfury_proc_capped(0), false, "proc ceiling: 0 procs read uncapped")
eq(weave.is_windfury_proc_capped(nil), false, "proc ceiling: an unknown count never caps")
eq(weave.is_windfury_proc_capped("20"), false, "proc ceiling: a non-number count never caps")

-- get_totem_twist_remaining ------------------------------------------------
near(weave.get_totem_twist_remaining(100, 100), 10, "twist: just dropped -> full period left")
near(weave.get_totem_twist_remaining(100, 105), 5, "twist: mid-period remainder")
near(weave.get_totem_twist_remaining(100, 110), 0, "twist: period elapsed -> due (0)")
eq(weave.get_totem_twist_remaining(100, 200), 0, "twist: long past the drop -> 0 (floored)")
eq(weave.get_totem_twist_remaining(100, 99.5), 10, "twist: clock before the drop reads the full period")
eq(weave.get_totem_twist_remaining(nil, 105), nil, "twist: no last drop -> nil (no prompt on a guess)")
eq(weave.get_totem_twist_remaining(0, 105), nil, "twist: zero last drop -> nil")
eq(weave.get_totem_twist_remaining(-5, 105), nil, "twist: negative last drop -> nil")
eq(weave.get_totem_twist_remaining("100", 105), nil, "twist: non-number last drop -> nil")
near(weave.get_totem_twist_remaining(100, nil), 10, "twist: nil now reads as the full period")

-- MAGMA_TOTEM_DURATION_SECONDS / get_magma_remaining ---------------------------
eq(weave.MAGMA_TOTEM_DURATION_SECONDS, 20, "MAGMA_TOTEM_DURATION_SECONDS == 20")
near(weave.get_magma_remaining(100, 100), 20, "magma: just dropped -> full duration left")
near(weave.get_magma_remaining(100, 110), 10, "magma: mid-duration remainder")
near(weave.get_magma_remaining(100, 120), 0, "magma: duration elapsed -> due (0)")
eq(weave.get_magma_remaining(100, 200), 0, "magma: long past the drop -> 0 (floored)")
eq(weave.get_magma_remaining(100, 99.5), 20, "magma: clock before the drop reads the full duration")
eq(weave.get_magma_remaining(nil, 105), nil, "magma: no last drop -> nil (no prompt on a guess)")
eq(weave.get_magma_remaining(0, 105), nil, "magma: zero last drop -> nil")
eq(weave.get_magma_remaining(-5, 105), nil, "magma: negative last drop -> nil")
eq(weave.get_magma_remaining("100", 105), nil, "magma: non-number last drop -> nil")
near(weave.get_magma_remaining(100, nil), 20, "magma: nil now reads as the full duration")

-- FAMILIES / SPELL_GROUPS / FAMILY_COLORS shape ----------------------------
eq(#weave.FAMILIES, 5, "FAMILIES has 5 entries")
eq(table.concat(weave.FAMILIES, ","), "LB,CL,HW,LHW,CH", "FAMILIES order is LB,CL,HW,LHW,CH")
eq(#weave.SPELL_GROUPS, 5, "SPELL_GROUPS has 5 groups")
eq(#weave.SPELL_GROUPS[1].ids, 12, "LB group lists 12 ranks")
eq(weave.SPELL_GROUPS[1].ids[1], 403, "LB lowest rank is 403")
eq(weave.SPELL_GROUPS[1].ids[12], 25449, "LB highest rank is 25449")
eq(weave.SPELL_GROUPS[2].ids[1], 421, "CL lowest rank is 421")
eq(weave.SPELL_GROUPS[5].ids[#weave.SPELL_GROUPS[5].ids], 25423, "CH highest rank is 25423")
for i = 1, #weave.SPELL_GROUPS do
    local group = weave.SPELL_GROUPS[i]
    local family = weave.FAMILIES[i] or ("?" .. tostring(i))
    eq(group.abbrev, family, "group " .. i .. " abbrev matches FAMILIES")
    check(type(group.label) == "string" and group.label ~= "", "group " .. i .. " has a label")
    check(type(group.ids) == "table" and #group.ids > 0, "group " .. i .. " has ids")
    local ascending, all_numbers = true, true
    for j = 1, #group.ids do
        if type(group.ids[j]) ~= "number" then all_numbers = false end
        if j > 1 and group.ids[j] <= group.ids[j - 1] then ascending = false end
    end
    check(ascending, "group " .. i .. " ids ascend (low -> high rank)")
    check(all_numbers, "group " .. i .. " ids are numbers")
end
for i = 1, #weave.FAMILIES do
    local family = weave.FAMILIES[i]
    local color = weave.FAMILY_COLORS[family] or {}
    check(weave.FAMILY_COLORS[family] ~= nil, "FAMILY_COLORS has " .. family)
    for k = 1, 4 do
        check(type(color[k]) == "number" and color[k] >= 0 and color[k] <= 1,
            "FAMILY_COLORS." .. family .. "[" .. k .. "] in [0, 1]")
    end
    eq(color[4], 1, "FAMILY_COLORS." .. family .. " alpha is 1")
end

if failures == 0 then
    print("PASS  weave_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  weave_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
