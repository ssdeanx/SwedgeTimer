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
eq(weave.get_effective_cast_time(0, 1, 1, false), nil, "cast: base 0 is UNKNOWN -> nil (H4, was 0)")
eq(weave.get_effective_cast_time(-2, 1, 1, false), nil, "cast: negative base -> nil (H4)")
eq(weave.get_effective_cast_time(nil, 1, 1, false), nil, "cast: nil base -> nil (H4)")
eq(weave.get_effective_cast_time(0/0, 1, 1, false), nil, "cast: NaN base -> nil (H4)")
near(weave.get_effective_cast_time(2.5, 1, nil, false), 2.5, "cast: nil MW multiplier treated as 1")
near(weave.get_effective_cast_time(2.5, nil, 1, false), 2.5, "cast: nil haste treated as 1")
near(weave.get_effective_cast_time(2.5, 1, 1, nil), 2.5, "cast: nil instant flag -> not instant")
-- H4 signal separation: the two legitimate instant signals still read 0 even when
-- the base cast is unknown - only an unresolvable base becomes nil.
eq(weave.get_effective_cast_time(nil, 1, 1, true), 0, "cast: the instant flag still wins over an unknown base")
eq(weave.get_effective_cast_time(nil, 1, 0, false), 0, "cast: five MW stacks still read instant on an unknown base")

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
near(weave.get_marker_fraction(4, 0, 0), 1, "marker: zero cast (a legitimate instant) pins the marker at 1")
-- H4: an unresolvable cast is UNKNOWN, not instant - the caller must hide the marker
-- instead of drawing a whole-swing-safe breakpoint at fraction 1.
eq(weave.get_marker_fraction(4, nil, 0), nil, "marker: nil cast -> nil (UNKNOWN, H4; was 1)")
eq(weave.get_marker_fraction(4, -1, 0), nil, "marker: negative cast -> nil (H4)")
eq(weave.get_marker_fraction(4, 0/0, 0), nil, "marker: NaN cast -> nil (H4)")
eq(weave.get_marker_fraction(4, nil, 0.1), nil, "marker: unknown cast stays unknown with latency")

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
-- H4: an unknown (nil) marker never asserts a clip, and never errors on the compare.
eq(weave.is_clipped(0, 0.9, nil), false, "clipped: an unknown marker never clips (H4)")
eq(weave.is_clipped(0.001, 0.9, nil), true, "clipped: a real clip amount still flags with an unknown marker")

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

-- ICD registry / get_icd_remaining / Flurry + DW sync (round 2) ------------------
-- One generic ICD read serves every entry in the registry; the windfury read
-- above delegates to it (same results), Flurry's 0.5 s proc ICD is the second
-- entry, and the DW sync threshold IS the Flurry ICD (the model where the ICD
-- affects timing).
eq(weave.ICD_SECONDS.windfury, 3, "ICD registry: windfury window is 3 s")
eq(weave.ICD_SECONDS.flurry, 0.5, "ICD registry: flurry window is 0.5 s")
near(weave.get_icd_remaining(100, 3, 100.5), 2.5, "ICD: 0.5 s into a 3 s window")
near(weave.get_icd_remaining(100, 0.5, 100.2), 0.3, "ICD: sub-second windows count down")
eq(weave.get_icd_remaining(100, 3, 103), 0, "ICD: elapsed -> 0")
eq(weave.get_icd_remaining(100, 3, 99.5), 3, "ICD: a future stamp floors the elapsed at 0")
eq(weave.get_icd_remaining(nil, 3, 5), nil, "ICD: no stamp -> nil")
eq(weave.get_icd_remaining(0, 3, 5), nil, "ICD: zero stamp -> nil")
eq(weave.get_icd_remaining(-5, 3, 5), nil, "ICD: negative stamp -> nil")
eq(weave.get_icd_remaining("100", 3, 5), nil, "ICD: non-number stamp -> nil")
eq(weave.get_icd_remaining(100, nil, 5), nil, "ICD: no window -> nil")
eq(weave.get_icd_remaining(100, 0, 5), nil, "ICD: zero window -> nil")
eq(weave.get_icd_remaining(100, -1, 5), nil, "ICD: negative window -> nil")
near(weave.get_icd_remaining(100, 3, nil), 3, "ICD: nil now reads as the full window")
near(weave.get_flurry_icd_remaining(100, 100.2), 0.3, "flurry ICD: 0.2 s after the proc -> 0.3 s left")
near(weave.get_flurry_icd_remaining(100, 100.5), 0, "flurry ICD: elapsed -> 0")
eq(weave.get_flurry_icd_remaining(nil, 100), nil, "flurry ICD: no proc stamp -> nil")
eq(weave.DW_SYNC_THRESHOLD_SECONDS, 0.5, "DW sync: the threshold is the Flurry ICD")
near(weave.get_dw_sync_offset(10.0, 10.1), 0.1, "DW sync: offset is the absolute gap")
near(weave.get_dw_sync_offset(10.1, 10.0), 0.1, "DW sync: offset is order-independent")
eq(weave.get_dw_sync_offset(10.0, 10.0), 0, "DW sync: identical landings -> zero offset")
eq(weave.get_dw_sync_offset(nil, 10.0), nil, "DW sync: missing MH landing -> nil")
eq(weave.get_dw_sync_offset(10.0, nil), nil, "DW sync: missing OH landing -> nil")
eq(weave.get_dw_sync_offset("10", 10.0), nil, "DW sync: non-number landing -> nil")
eq(weave.is_dw_desynced(0.5), false, "DW sync: exactly the threshold is still synced (strict >)")
eq(weave.is_dw_desynced(0.51), true, "DW sync: above the threshold warns")
eq(weave.is_dw_desynced(0), false, "DW sync: a perfect pair never warns")
eq(weave.is_dw_desynced(nil), false, "DW sync: an unknown offset never warns")
eq(weave.is_dw_desynced("0.9"), false, "DW sync: a non-number offset never warns")

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

-- should_hold_stormstrike (S3) -------------------------------------------------
-- Stormstrike ready + the WF ICD clearing inside this swing -> hold. Strictly
-- numeric: nil/NaN/strings never hold; the ICD must be live (> 0) and the swing
-- still running (> 0); the boundary wf == swing holds (<=).
eq(weave.should_hold_stormstrike(1.0, 2.0), true, "hold: ICD clears inside the swing -> hold")
eq(weave.should_hold_stormstrike(2.0, 2.0), true, "hold: ICD clears exactly at the swing end -> hold (<=)")
eq(weave.should_hold_stormstrike(2.1, 2.0), false, "hold: ICD clears after the swing -> no hold")
eq(weave.should_hold_stormstrike(0, 2.0), false, "hold: elapsed ICD -> no hold")
eq(weave.should_hold_stormstrike(-1, 2.0), false, "hold: negative ICD -> no hold")
eq(weave.should_hold_stormstrike(nil, 2.0), false, "hold: unknown ICD -> no hold")
eq(weave.should_hold_stormstrike(1.0, 0), false, "hold: swing landing now -> no hold")
eq(weave.should_hold_stormstrike(1.0, nil), false, "hold: unknown swing -> no hold")
eq(weave.should_hold_stormstrike("1", 2.0), false, "hold: non-number ICD -> no hold")
eq(weave.should_hold_stormstrike(1.0, "2"), false, "hold: non-number swing -> no hold")
eq(weave.should_hold_stormstrike(0/0, 2.0), false, "hold: NaN ICD never holds")
eq(weave.should_hold_stormstrike(1.0, 0/0), false, "hold: NaN swing never holds")

-- get_wf_hold_wash_fraction (S3) ------------------------------------------------
-- Start fraction of the amber wash: from the WF-ICD clear point to the swing end.
near(weave.get_wf_hold_wash_fraction(0, 4, 3), 0.75, "wash: 3 s of ICD left on a 4 s swing -> starts at 0.75")
near(weave.get_wf_hold_wash_fraction(2, 4, 1), 0.75, "wash: elapsed + ICD over the swing duration")
near(weave.get_wf_hold_wash_fraction(3.5, 4, 1), 1, "wash: past the swing end clamps to 1")
eq(weave.get_wf_hold_wash_fraction(0, 0, 3), nil, "wash: zero swing duration -> nil")
eq(weave.get_wf_hold_wash_fraction(0, -1, 3), nil, "wash: negative swing duration -> nil")
eq(weave.get_wf_hold_wash_fraction(nil, 4, 3), nil, "wash: missing elapsed -> nil")
eq(weave.get_wf_hold_wash_fraction(0, nil, 3), nil, "wash: missing duration -> nil")
eq(weave.get_wf_hold_wash_fraction(0, 4, nil), nil, "wash: missing ICD -> nil")
eq(weave.get_wf_hold_wash_fraction(0, 4, -1), nil, "wash: negative ICD -> nil")
eq(weave.get_wf_hold_wash_fraction("0", 4, 3), nil, "wash: non-number elapsed -> nil")

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

-- get_stormstrike_remaining / should_stormstrike_glow (S2) ----------------------
-- Same shape as the Flame Shock pair: a missing expiration counts down from the
-- stamp, a missing duration falls back to the 12 s default, the glow window is the
-- final 4 s.
local ss_remaining, ss_total = weave.get_stormstrike_remaining(12, 108, 100)
near(ss_remaining, 8, "stormstrike: 8 s left on a 12 s debuff")
near(ss_total, 12, "stormstrike: total span is the reported duration")
near(weave.get_stormstrike_remaining(12, 100, 100), 0, "stormstrike: elapsed -> 0 (floored)")
near(weave.get_stormstrike_remaining(12, 90, 100), 0, "stormstrike: expired -> 0")
local ss_r2, ss_t2 = weave.get_stormstrike_remaining(nil, 106, 100)
near(ss_r2, 6, "stormstrike: missing duration still counts down from the stamp")
near(ss_t2, 12, "stormstrike: missing duration -> 12 s fallback total")
local ss_r3, ss_t3 = weave.get_stormstrike_remaining(nil, nil, 100)
near(ss_r3, 12, "stormstrike: no payload at all -> fallback duration")
near(ss_t3, 12, "stormstrike: no payload at all -> fallback total")
local ss_r4, ss_t4 = weave.get_stormstrike_remaining(0, 106, 100)
near(ss_r4, 6, "stormstrike: non-positive duration -> fallback total, stamp counted")
near(ss_t4, 12, "stormstrike: non-positive duration -> fallback total")
eq(weave.STORMSTRIKE_FALLBACK_DURATION, 12, "STORMSTRIKE_FALLBACK_DURATION == 12")
eq(weave.STORMSTRIKE_GLOW_SECONDS, 4, "STORMSTRIKE_GLOW_SECONDS == 4")
eq(weave.should_stormstrike_glow(4), true, "stormstrike glow: at 4 s -> glow")
eq(weave.should_stormstrike_glow(0.1), true, "stormstrike glow: just above 0 -> glow")
eq(weave.should_stormstrike_glow(4.01), false, "stormstrike glow: above 4 s -> no glow")
eq(weave.should_stormstrike_glow(0), false, "stormstrike glow: elapsed -> no glow")
eq(weave.should_stormstrike_glow(-1), false, "stormstrike glow: expired -> no glow")
eq(weave.should_stormstrike_glow(nil), false, "stormstrike glow: missing -> no glow")
eq(weave.should_stormstrike_glow("4"), false, "stormstrike glow: non-number -> no glow")

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
-- The unreadable-count fallback is the 3-charge standard (reference
-- SuperSwingTimer_ClassMods.lua:4141-4144), never the optimistic full row.
eq(weave.SHIELD_FALLBACK_CHARGES, 3, "SHIELD_FALLBACK_CHARGES == 3")
local ls_slots, ls_filled = weave.get_shield_tracker_state("lightning", 2)
eq(ls_slots, 4, "shields: Lightning Shield row has 4 slots")
eq(ls_filled, 2, "shields: Lightning Shield fills the aura count")
local ls_s2, ls_f2 = weave.get_shield_tracker_state("lightning", nil)
eq(ls_s2, 4, "shields: missing Lightning count -> 4 slots")
eq(ls_f2, 3, "shields: missing count reads as the 3-charge standard")
local ls_s3, ls_f3 = weave.get_shield_tracker_state("lightning", 9)
eq(ls_s3, 4, "shields: Lightning count above the cap clamps")
eq(ls_f3, 4, "shields: Lightning count above the cap reads full")
local ls_s4, ls_f4 = weave.get_shield_tracker_state("lightning", 2.6)
eq(ls_s4, 4, "shields: Lightning rounding keeps 4 slots")
eq(ls_f4, 3, "shields: fractional counts round to the nearest charge")
local ls_s5, ls_f5 = weave.get_shield_tracker_state("lightning", 0)
eq(ls_s5, 4, "shields: zero count still shows the 4 Lightning slots")
eq(ls_f5, 3, "shields: zero count reads as the 3-charge standard")
local ws_slots, ws_filled = weave.get_shield_tracker_state("water", 1)
eq(ws_slots, 3, "shields: Water Shield row has 3 slots")
eq(ws_filled, 1, "shields: Water Shield fills the aura count")
local ws_s2, ws_f2 = weave.get_shield_tracker_state("water", nil)
eq(ws_s2, 3, "shields: missing Water count -> 3 slots")
eq(ws_f2, 3, "shields: missing Water count reads as the 3-charge standard (full row)")
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
eq(str_filled, 3, "shields: non-number count reads as the 3-charge standard")

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

-- get_mw5_spender / should_hold_mw5 (S4) ----------------------------------------
-- The spender choice: Lava Burst ONLY on a strict boolean-true known reading
-- (the SoD rune / talent gate); every other reading demotes to Lightning Bolt.
-- The FS-collision guard: FS inside its final 2 s AND a strictly-ready shock
-- hold the five-stack weave; the boundary at exactly 2.0 s does NOT hold.
eq(weave.MW5_FS_GUARD_SECONDS, 2, "MW5_FS_GUARD_SECONDS == 2")
eq(weave.get_mw5_spender(true), "lavaburst", "MW5 spender: known rune -> Lava Burst")
eq(weave.get_mw5_spender(false), "lightning", "MW5 spender: unknown rune -> Lightning Bolt")
eq(weave.get_mw5_spender(nil), "lightning", "MW5 spender: nil rune -> Lightning Bolt")
eq(weave.get_mw5_spender(1), "lightning", "MW5 spender: only boolean true enables (no truthy gate)")
eq(weave.get_mw5_spender("true"), "lightning", "MW5 spender: a string never enables")
eq(weave.should_hold_mw5(1.9, true), true, "MW5 guard: FS under 2 s + ready shock -> hold")
eq(weave.should_hold_mw5(2.0, true), false, "MW5 guard: exactly 2.0 s -> no hold (strict <)")
eq(weave.should_hold_mw5(2.01, true), false, "MW5 guard: above 2 s -> no hold")
eq(weave.should_hold_mw5(0, true), true, "MW5 guard: FS about to expire -> hold")
eq(weave.should_hold_mw5(1.9, false), false, "MW5 guard: shock not ready -> no hold")
eq(weave.should_hold_mw5(1.9, nil), false, "MW5 guard: unknown shock -> no hold (no guess)")
eq(weave.should_hold_mw5(nil, true), false, "MW5 guard: no FS reading -> no hold")
eq(weave.should_hold_mw5("1", true), false, "MW5 guard: non-number FS -> no hold")
eq(weave.should_hold_mw5(0/0, true), false, "MW5 guard: NaN FS never holds")
check(type(weave.LAVA_BURST_COLOR) == "table" and #weave.LAVA_BURST_COLOR == 4,
    "LAVA_BURST_COLOR is an rgba table")
near(weave.LAVA_BURST_COLOR[4], 1, "LAVA_BURST_COLOR alpha is 1")

-- get_spell_position_state / can_prompt_weave (round 2) --------------------------
-- The 2-3 stack weave gate: below MW_MIN_WEAVE_STACKS the spell reads "wait"
-- (dim); from there on a start at or before the latest safe start reads "ready"
-- and a passed window reads "clip" (never prompted). Five stacks short-circuit
-- (the instant cast has no window). Unreadable readings never read ready.
eq(weave.MW_MIN_WEAVE_STACKS, 2, "MW_MIN_WEAVE_STACKS == 2")
eq(weave.get_spell_position_state(2, 0.3, 0.6), "ready", "positions: 2 stacks inside the window -> ready")
eq(weave.get_spell_position_state(3, 0.6, 0.6), "ready", "positions: at the safe start -> ready (strict > for clip)")
eq(weave.get_spell_position_state(3, 0.61, 0.6), "clip", "positions: past the safe start -> clip")
eq(weave.get_spell_position_state(1, 0.1, 0.9), "wait", "positions: one stack -> wait")
eq(weave.get_spell_position_state(0, 0.1, 0.9), "wait", "positions: zero stacks -> wait")
eq(weave.get_spell_position_state(nil, 0.1, 0.9), "wait", "positions: unknown stacks -> wait")
eq(weave.get_spell_position_state("2", 0.1, 0.9), "wait", "positions: non-number stacks -> wait")
eq(weave.get_spell_position_state(5, nil, nil), "ready", "positions: five stacks short-circuit to ready")
eq(weave.get_spell_position_state(4, nil, 0.5), "wait", "positions: unknown current fraction -> wait")
eq(weave.get_spell_position_state(4, 0.2, nil), "wait", "positions: unknown safe start -> wait")
eq(weave.get_spell_position_state(4, 0/0, 0.5), "wait", "positions: NaN current fraction never reads ready")
eq(weave.get_spell_position_state(4, 0.2, 0/0), "wait", "positions: NaN safe start never reads ready")
eq(weave.can_prompt_weave(2, 0.3, 0.6), true, "prompt: ready spells prompt")
eq(weave.can_prompt_weave(2, 0.7, 0.6), false, "prompt: a clip never prompts")
eq(weave.can_prompt_weave(1, 0.3, 0.6), false, "prompt: below the stack gate never prompts")
eq(weave.can_prompt_weave(5, nil, nil), true, "prompt: the instant fallback always prompts")

-- G5 composition: the cross-term walk a live shaman actually runs, end to end
-- (effective cast -> marker fraction -> position state/prompt). Three realistic
-- cases pin argument order, the ms/s units and the haste-vs-MW interaction that
-- every single-function case above would preserve even if one were wrong.
-- Case 1: 0 stacks, no haste, 100 ms latency, 3.0 s swing (the LB baseline).
local comp_eff = weave.get_effective_cast_time(2.5, 1, 1, false)
near(comp_eff, 2.5, "G5 baseline: 0 stacks, no haste -> the base cast time")
local comp_marker = weave.get_marker_fraction(3.0, comp_eff, 0.1)
near(comp_marker, (3.0 - 2.6) / 3.0, "G5 baseline: marker = (swing - cast - latency) / swing")
eq(weave.get_spell_position_state(0, 0.2, comp_marker), "wait", "G5 baseline: 0 stacks never read ready")
eq(weave.can_prompt_weave(0, 0.2, comp_marker), false, "G5 baseline: no prompt below the stack gate")
-- Case 2: 3 stacks + 30% spell haste + 100 ms latency on a 2.6 s swing -> ready.
local comp_eff2 = weave.get_effective_cast_time(2.5, weave.get_haste_multiplier(30), weave.get_maelstrom_multiplier(3), false)
near(comp_eff2, (2.5 / 1.3) * 0.4, "G5 hasted 3 stacks: base / haste * MW multiplier")
local comp_marker2 = weave.get_marker_fraction(2.6, comp_eff2, 0.1)
near(comp_marker2, (2.6 - (comp_eff2 + 0.1)) / 2.6, "G5 hasted 3 stacks: latency shifts the marker left")
eq(weave.get_spell_position_state(3, comp_marker2 - 0.01, comp_marker2), "ready", "G5 hasted 3 stacks: just before the marker reads ready")
eq(weave.get_spell_position_state(3, comp_marker2 + 0.01, comp_marker2), "clip", "G5 hasted 3 stacks: past the marker reads clip")
eq(weave.can_prompt_weave(3, comp_marker2 - 0.01, comp_marker2), true, "G5 hasted 3 stacks: the prompt fires inside the window")
local comp_safe = weave.get_safe_start_in(2.6, 0, 0.1, comp_eff2)
near(comp_safe, 2.6 - 0.1 - comp_eff2, "G5 hasted 3 stacks: safe_start_in counts down to the marker")
check(comp_safe > 0, "G5 hasted 3 stacks: the window is still open at the swing start")
-- Case 3: 5 stacks short-circuit the whole model (instant, no window).
local comp_eff3 = weave.get_effective_cast_time(2.5, 1, weave.get_maelstrom_multiplier(5), false)
eq(comp_eff3, 0, "G5 5 stacks: the spender is instant")
local comp_marker3 = weave.get_marker_fraction(2.6, comp_eff3, 0)
eq(comp_marker3, 1, "G5 5 stacks: the instant cast's marker sits at the swing end")
eq(weave.get_spell_position_state(5, 0.99, comp_marker3), "ready", "G5 5 stacks: ready anywhere in the swing")
eq(weave.can_prompt_weave(5, 0.99, comp_marker3), true, "G5 5 stacks: the instant fallback always prompts")

-- get_cast_zone_bounds (round 2) -------------------------------------------------
-- The "spells start cast range zone" spans the numeric latest-safe starts.
local z_min, z_max, z_n = weave.get_cast_zone_bounds({ 0.625, 0.7 })
near(z_min, 0.625, "zone: min is the earliest safe start")
near(z_max, 0.7, "zone: max is the latest safe start")
eq(z_n, 2, "zone: both entries counted")
local z2_min, z2_max, z2_n = weave.get_cast_zone_bounds({ 0.7, nil, 0.625, "x" })
near(z2_min, 0.625, "zone: non-number entries are skipped (min)")
near(z2_max, 0.7, "zone: non-number entries are skipped (max)")
eq(z2_n, 2, "zone: only numeric entries count")
local z3_min, z3_max, z3_n = weave.get_cast_zone_bounds({})
eq(z3_min, nil, "zone: an empty list has no min")
eq(z3_max, nil, "zone: an empty list has no max")
eq(z3_n, 0, "zone: an empty list counts zero")
local z4_min, z4_max, z4_n = weave.get_cast_zone_bounds(nil)
eq(z4_min, nil, "zone: a missing list has no min")
eq(z4_max, nil, "zone: a missing list has no max")
eq(z4_n, 0, "zone: a missing list counts zero")
local z5_min, z5_max = weave.get_cast_zone_bounds({ 0.5, 0.5 })
near(z5_min, 0.5, "zone: a single distinct start is both bounds (min)")
near(z5_max, 0.5, "zone: a single distinct start is both bounds (max)")
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
