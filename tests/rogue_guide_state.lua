-- tests/rogue_guide_state.lua: offline tests for the rogue next-action guide: the
-- pure decision engine (rogue_guide.lua) in a strict sandbox.
--
-- Pins:
--   * rogue_guide.lua loads with NO WoW API at all (a strict sandbox errors on any
--     global read) and the per-client DATA tables: pooling bands per family
--     (ERA/WRATH 65/85, TBC single 71, FOREVER 65/75), the finisher spine + CP
--     floors + dump floors per family (ERA Eviscerate-first, TBC/WRATH/FOREVER
--     rupture-first), Rupture/EA refresh windows per family, the Wrath Rupture
--     per-CP DATA (1CP 8 s / 5CP 16 s sourced, 2-4CP UNCONFIRMED) + accessor,
--     SnD upkeep rows +
--     per-CP durations, Tea/AR energy lines per family, the sweaty override and
--     the Shiv/BF gates — and the Envenom rule per family (ERA/TBC dying_only,
--     WRATH let_expire, FOREVER never, RETAIL chain, SOD primary via the
--     ERA + sod_envenom latch — each its own table, never a shared reference),
--   * the builder family gate (BS-6): Hemorrhage is a TBC/Forever/Era builder and
--     never a SoD one (the ERA token behind the sod_envenom latch, and the SOD
--     token, are vetoed; an unknown family answers false) - the pure half of the
--     rogue's Hemorrhage builder, plus the exported predicate,
--   * the pooling-band predicate and its boundaries (pre/post/cap lines, unknown
--     energy/tick/band, NaN),
--   * the Rupture-vs-Eviscerate decider on numeric TTD (TTD boundary, rupture
--     missing/refresh/healthy, unknown TTD/CP, NaN rupture) and the per-CP
--     duration lookup (sourced rows only, 2-4CP/out-of-range/nil/NaN hide;
--     the flat floors still govern every verdict),
--   * the per-client Envenom verdicts (dying-only boundary + unknown TTD, Wrath
--     let-expire + cap exception, Forever never, retail chain + proven-empty
--     stacks, SoD primary + fight-end wired through the ERA + sod_envenom
--     latch, unknown family),
--   * the SnD upkeep verdict (usable/CP/window/missing/NaN/unknown-family +
--     TBC min-CP), the AR verdict (family lines + ERA tick gate + FOREVER SnD
--     ride) and the BF verdict (SnD ride + EA-healthy-on-duty),
--   * the EA-duty / Shiv / Thistle-Tea verdicts and their boundaries,
--   * the TBC Shiv Mutilate/CP gates, the Cold Blood verdict (TBC w/ SnD,
--     Forever 5CP), the SOD SnD rows (4CP/1s) and the SOD Tea fight-end
--     (40 while ttd <= 15 s, unknown TTD stays on 10),
--   * the EA-duty wait/release (H6 rule 1a: TBC 15 s minimum, SnD-cover and
--     pool-line boundaries, unknown-hides) and the Forever finisher lockout
--     (duty + low EA suppresses snd/dump/planned, keeps expose/builders/Tea/AR),
--   * the evaluate rule order (unknown > expose > 1a release > snd > shiv(ERA+TBC,
--     TBC Mutilate/CP-gated) > envenom (SOD via the latch) > dying dump
--     (family CP floor) > finisher (family mode/floor) > AR > BF > Cold Blood
--     (1a-hold/lockout-yielding) > tea (SOD fight-end) > pool/spend (the 1a
--     hold first, then the ERA sweaty override)), the unknown-input
--     contract (nil/unusable -> caller-visible unknown, never a guessed
--     verdict), the frozen output fields overwritten on every call, and
--     nil-safety.
-- Run from the repo root: lua5.1 tests/rogue_guide_state.lua  (any cwd works).

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
            error("rogue_guide.lua touched a global: " .. tostring(key))
        end,
    })
    local chunk = assert(loadfile(ROOT .. "rogue_guide.lua"))
    setfenv(chunk, strict)
    local ok, err = pcall(chunk, "SwedgeTimer", pure)
    check(ok, "rogue_guide.lua loads with no WoW API and no globals (" .. tostring(err) .. ")")
end

local rg = pure.rogue_guide
check(type(rg) == "table", "rogue_guide.lua defines st.rogue_guide")
check(type(rg.evaluate) == "function", "the pure engine is exported")
check(type(rg.pool_verdict) == "function", "the pooling-band predicate is exported")
check(type(rg.finisher_for_ttd) == "function", "the Rupture-vs-Eviscerate decider is exported")
check(type(rg.rupture_duration_for_cp) == "function", "the per-CP Rupture duration lookup is exported")
check(type(rg.envenom_verdict) == "function", "the per-client Envenom verdict is exported")
check(type(rg.snd_verdict) == "function", "the SnD upkeep verdict is exported")
check(type(rg.ar_verdict) == "function", "the Adrenaline Rush verdict is exported")
check(type(rg.bf_verdict) == "function", "the Blade Flurry verdict is exported")
check(type(rg.shiv_verdict) == "function", "the Shiv verdict is exported")
check(type(rg.ea_verdict) == "function", "the EA-duty verdict is exported")
check(type(rg.ea_wait_verdict) == "function", "the EA-duty wait verdict is exported")
check(type(rg.ea_lockout_active) == "function", "the EA-duty lockout predicate is exported")
check(type(rg.tea_verdict) == "function", "the Thistle-Tea verdict is exported")
check(type(rg.stacked_glow) == "function", "the stacked multi-CD glow predicate is exported")
check(type(rg.is_unknown) == "function", "the unknown-input predicate is exported")
check(type(rg.band_for) == "function", "the band lookup is exported")
eq(rg.TICK_ENERGY_DEFAULT, 20, "the tick gain is 20 (Era+TBC CONFIRMED)")
eq(rg.MAX_ENERGY_DEFAULT, 100, "the energy cap default is 100")
eq(rg.RUPTURE_MIN_TTD_DEFAULT, 8, "the TTD default is 8 (sourced 1CP Rupture 8 s)")
eq(rg.FINISHER_MIN_CP_DEFAULT, 5, "the planned-finisher line is 5 CP")
eq(rg.SHIV_REFRESH_DEFAULT, 2, "the Shiv window is 2 (research §4 watch-list)")

-- Pooling bands: per-client DATA (audit T-M1/V-G6/F2). TBC is the sim-validated
-- single 71 line (pre == post: at/above always spends); FOREVER caps at the
-- sim's 75 cap-danger line; ERA/WRATH keep the tick-gated 65/85 (classic
-- MATCH). RETAIL absent (phase-based).
do
    eq(rg.POOL_BANDS.TBC.pre, 71, "TBC pre-tick band is 71 (sim single line)")
    eq(rg.POOL_BANDS.TBC.post, 71, "TBC post-tick band is 71 (no post line)")
    eq(rg.POOL_BANDS.ERA.pre, 65, "ERA carries the pre-tick band as data")
    eq(rg.POOL_BANDS.ERA.post, 85, "ERA carries the post-tick band as data")
    eq(rg.POOL_BANDS.WRATH.pre, 65, "WRATH carries the pre-tick band as data")
    eq(rg.POOL_BANDS.WRATH.post, 85, "WRATH carries the post-tick band as data")
    eq(rg.POOL_BANDS.FOREVER.pre, 65, "FOREVER carries the pre-tick band as data")
    eq(rg.POOL_BANDS.FOREVER.post, 75, "FOREVER post-tick band is 75 (cap-danger)")
    eq(rg.POOL_BANDS.RETAIL, nil, "RETAIL has no tick band (phase-based)")
    eq(rg.band_for("TBC"), rg.POOL_BANDS.TBC, "band_for returns the TBC table")
    eq(rg.band_for("BOGUS"), nil, "band_for answers nil for an unknown family")
    eq(rg.band_for(nil), nil, "band_for answers nil for a nil family")
end

-- The builder family gate (BS-6, bench/filed_closure_sweep_2026-10-19.md §7):
-- the pure half of the rogue's Hemorrhage builder. Hemorrhage is a
-- TBC/Forever/Era builder; the SoD client (the ERA token behind the
-- sod_envenom latch) builds with a rune, never with Hemorrhage.
do
    check(type(rg.builder_candidate_allowed) == "function",
        "the builder family gate is exported")
    local gated = rg.BUILDER_GATED_FAMILIES["Hemorrhage"]
    check(type(gated) == "table", "Hemorrhage carries a family gate")
    eq(gated.TBC, true, "TBC has the Hemorrhage builder")
    eq(gated.ERA, true, "ERA has the Hemorrhage builder")
    eq(gated.FOREVER, true, "FOREVER has the Hemorrhage builder")
    eq(gated.WRATH, nil, "WRATH has no Hemorrhage builder")
    eq(gated.RETAIL, nil, "RETAIL has no Hemorrhage builder")
    eq(rg.builder_candidate_allowed("Hemorrhage", "TBC", nil), true,
        "TBC: Hemorrhage is a builder")
    eq(rg.builder_candidate_allowed("Hemorrhage", "FOREVER", nil), true,
        "FOREVER: Hemorrhage is a builder")
    eq(rg.builder_candidate_allowed("Hemorrhage", "ERA", nil), true,
        "ERA: Hemorrhage is a builder")
    eq(rg.builder_candidate_allowed("Hemorrhage", "ERA", true), false,
        "SoD (the ERA token behind the latch): Hemorrhage is never a builder")
    eq(rg.builder_candidate_allowed("Hemorrhage", "SOD", true), false,
        "the SOD token never builds with Hemorrhage")
    eq(rg.builder_candidate_allowed("Hemorrhage", "WRATH", nil), false,
        "WRATH never builds with Hemorrhage")
    eq(rg.builder_candidate_allowed("Hemorrhage", "RETAIL", nil), false,
        "RETAIL never builds with Hemorrhage")
    eq(rg.builder_candidate_allowed("Hemorrhage", nil, nil), false,
        "an unknown family never builds with Hemorrhage")
    eq(rg.builder_candidate_allowed("Hemorrhage", "BOGUS", nil), false,
        "an unknown family token never builds with Hemorrhage")
    eq(rg.builder_candidate_allowed("Saber Slash", "TBC", nil), true,
        "an ungated candidate (the SoD rune) is a builder on every client")
    eq(rg.builder_candidate_allowed("Mutilate", "ERA", true), true,
        "an ungated candidate (Mutilate) is a builder on every client")
    eq(rg.builder_candidate_allowed(nil, "TBC", nil), false,
        "a nameless candidate is never a builder")
    -- The engine's builder action is the slot key the class fills with the
    -- winner of the chain (the guide's builder slot).
    check(rg.opener_rank("builder") ~= nil,
        "the engine's builder action is the guide's builder slot key")
end

-- Rotation-audit DATA tables: finisher spine/m floors, refresh windows, upkeep
-- lines and gates (each family owns its row; never shared, never guessed).
do
    eq(rg.FINISHER_MODES.ERA, "eviscerate", "ERA plans Eviscerate (E-C1)")
    eq(rg.FINISHER_MODES.TBC, "rupture", "TBC plans Rupture-first")
    eq(rg.FINISHER_MODES.WRATH, "rupture", "WRATH plans Rupture-first")
    eq(rg.FINISHER_MODES.FOREVER, "rupture", "FOREVER plans Rupture-first")
    eq(rg.FINISHER_MODES.RETAIL, nil, "RETAIL has no finisher mode row (filed)")
    eq(rg.FINISHER_MIN_CP_BY_FAMILY.ERA, 5, "ERA planned line is 5 CP")
    eq(rg.FINISHER_MIN_CP_BY_FAMILY.TBC, 5, "TBC planned line is 5 CP")
    eq(rg.FINISHER_MIN_CP_BY_FAMILY.WRATH, 4, "WRATH planned line is 4 CP (W-G2)")
    eq(rg.FINISHER_MIN_CP_BY_FAMILY.FOREVER, 3, "FOREVER planned line is 3 CP (V-G3)")
    eq(rg.RUPTURE_REFRESH_BY_FAMILY.ERA, 4, "ERA Rupture refresh is 4")
    eq(rg.RUPTURE_REFRESH_BY_FAMILY.TBC, 0, "TBC recasts Rupture when missing (T-G3)")
    eq(rg.RUPTURE_REFRESH_BY_FAMILY.WRATH, 4, "WRATH Rupture refresh is 4")
    eq(rg.RUPTURE_REFRESH_BY_FAMILY.FOREVER, 0, "FOREVER recasts when missing")
    eq(rg.RUPTURE_MIN_TTD_BY_FAMILY.ERA, 8, "ERA floor is 8 (sourced 1CP row)")
    eq(rg.RUPTURE_MIN_TTD_BY_FAMILY.TBC, 5, "TBC floor is 5 (T-C1 5CP/5s)")
    eq(rg.RUPTURE_MIN_TTD_BY_FAMILY.WRATH, 4, "WRATH floor is 4 (fight<=4s)")
    eq(rg.RUPTURE_MIN_TTD_BY_FAMILY.FOREVER, 6, "FOREVER floor is 6 (3CP fight-end)")
    eq(rg.RUPTURE_DURATION_BY_CP[1], 8, "Wrath 1CP Rupture lasts 8 s (W-M2 sourced)")
    eq(rg.RUPTURE_DURATION_BY_CP[5], 16, "Wrath 5CP Rupture lasts 16 s (W-M2 sourced)")
    eq(rg.RUPTURE_DURATION_BY_CP[2], nil, "2CP duration is UNCONFIRMED (never interpolated)")
    eq(rg.RUPTURE_DURATION_BY_CP[3], nil, "3CP duration is UNCONFIRMED (never interpolated)")
    eq(rg.RUPTURE_DURATION_BY_CP[4], nil, "4CP duration is UNCONFIRMED (never interpolated)")
    eq(rg.RUPTURE_DURATION_BY_CP[0], nil, "0CP carries no duration row")
    eq(rg.RUPTURE_DURATION_BY_CP[6], nil, "6CP carries no duration row")
    eq(rg.DUMP_MIN_CP_BY_FAMILY.ERA, 1, "ERA dumps at any CP (Era rule)")
    eq(rg.DUMP_MIN_CP_BY_FAMILY.TBC, 5, "TBC dumps at 5 CP only (T-C1)")
    eq(rg.DUMP_MIN_CP_BY_FAMILY.WRATH, 4, "WRATH dumps at 4 CP")
    eq(rg.DUMP_MIN_CP_BY_FAMILY.FOREVER, 3, "FOREVER dumps at 3 CP")
    eq(rg.SND_REFRESH_BY_FAMILY.ERA, 3, "ERA SnD window is 3")
    eq(rg.SND_REFRESH_BY_FAMILY.TBC, 0, "TBC SnD recasts when missing")
    eq(rg.SND_REFRESH_BY_FAMILY.WRATH, 1, "WotLK SnD window is 1")
    eq(rg.SND_REFRESH_BY_FAMILY.FOREVER, 0, "FOREVER SnD recasts when missing")
    eq(rg.SND_MIN_CP_BY_FAMILY.ERA, 1, "ERA SnD needs 1 CP")
    eq(rg.SND_MIN_CP_BY_FAMILY.TBC, 2, "TBC SnD needs 2 CP (10 s minimum)")
    eq(rg.SND_MIN_CP_BY_FAMILY.WRATH, 1, "WRATH SnD needs 1 CP")
    eq(rg.SND_MIN_CP_BY_FAMILY.FOREVER, 1, "FOREVER SnD needs 1 CP")
    eq(rg.SND_MIN_CP_DEFAULT, 1, "the SnD CP fallback is 1")
    eq(rg.SND_DURATION_BY_CP[1], 9, "1CP SnD lasts 9 s")
    eq(rg.SND_DURATION_BY_CP[2], 12, "2CP SnD lasts 12 s")
    eq(rg.SND_DURATION_BY_CP[3], 15, "3CP SnD lasts 15 s")
    eq(rg.SND_DURATION_BY_CP[4], 18, "4CP SnD lasts 18 s")
    eq(rg.SND_DURATION_BY_CP[5], 21, "5CP SnD lasts 21 s")
    eq(rg.EA_REFRESH_BY_FAMILY.ERA, 3, "ERA EA window is 3 (E-G4 MATCH)")
    eq(rg.EA_REFRESH_BY_FAMILY.TBC, 6, "TBC EA imminent is 6 (T-G2)")
    eq(rg.EA_REFRESH_BY_FAMILY.WRATH, 3, "WRATH EA window is 3")
    eq(rg.EA_REFRESH_BY_FAMILY.FOREVER, 16, "FOREVER EA lockout is 16 (V-G2)")
    eq(rg.EA_MINIMUM_BY_FAMILY.TBC, 15, "TBC EA minimum is 15 (H6 sim-literal)")
    eq(rg.EA_MINIMUM_BY_FAMILY.ERA, nil, "ERA has no EA minimum row (no wait)")
    eq(rg.EA_MINIMUM_BY_FAMILY.FOREVER, nil, "FOREVER has no EA minimum row")
    eq(rg.EA_MINIMUM_BY_FAMILY.WRATH, nil, "WRATH has no EA minimum row")
    eq(rg.EA_WAIT_SND_MINIMUM, 10, "the TBC wait needs 10 s of SnD cover")
    check(rg.EA_LOCKOUT_FAMILIES.FOREVER == true, "FOREVER locks out spenders on EA duty")
    check(rg.EA_LOCKOUT_FAMILIES.TBC ~= true, "TBC never locks out (wait instead)")
    check(rg.EA_LOCKOUT_FAMILIES.ERA ~= true, "ERA never locks out")
    eq(rg.TEA_ENERGY_MAX_BY_FAMILY.ERA, 29, "ERA Tea line is 29 (E-G3)")
    eq(rg.TEA_ENERGY_MAX_BY_FAMILY.TBC, 30, "TBC Tea line is 30 (T-G5)")
    eq(rg.TEA_ENERGY_MAX_BY_FAMILY.WRATH, 40, "WRATH Tea line is 40")
    eq(rg.TEA_ENERGY_MAX_BY_FAMILY.FOREVER, 15, "FOREVER Tea line is 15 (V-G4)")
    eq(rg.AR_ENERGY_MAX_BY_FAMILY.ERA, 59, "ERA AR line is 59 (tick-gated)")
    eq(rg.AR_ENERGY_MAX_BY_FAMILY.TBC, 40, "TBC AR line is 40")
    eq(rg.AR_ENERGY_MAX_BY_FAMILY.WRATH, 50, "WotLK AR line is 50")
    eq(rg.AR_ENERGY_MAX_BY_FAMILY.FOREVER, 50, "FOREVER AR line is 50")
    eq(rg.AR_ENERGY_MAX_BY_FAMILY.RETAIL, nil, "RETAIL has no AR line (filed)")
    eq(rg.SWEATY_SPEND_BY_FAMILY.ERA, 79, "ERA sweaty override is 79 (E-G1)")
    eq(rg.SWEATY_SPEND_BY_FAMILY.TBC, nil, "TBC has no sweaty override")
    check(rg.SHIV_FAMILIES.ERA == true, "ERA keeps Shiv")
    check(rg.SHIV_FAMILIES.TBC == true, "TBC keeps Shiv")
    check(rg.SHIV_FAMILIES.WRATH ~= true, "WotLK never Shivs (H7)")
    check(rg.SHIV_FAMILIES.FOREVER ~= true, "FOREVER never Shivs (H7)")
    check(rg.BF_FAMILIES.ERA == true, "ERA keeps Blade Flurry")
    check(rg.BF_FAMILIES.TBC == true, "TBC keeps Blade Flurry")
    check(rg.BF_FAMILIES.WRATH == true, "WRATH keeps Blade Flurry")
    check(rg.BF_FAMILIES.FOREVER == true, "FOREVER keeps Blade Flurry")
    check(rg.BF_FAMILIES.RETAIL ~= true, "RETAIL never prompts BF (filed)")
    eq(rg.SND_MIN_CP_BY_FAMILY.SOD, 4, "SOD SnD needs 4 CP (S-G1)")
    eq(rg.SND_REFRESH_BY_FAMILY.SOD, 1, "SOD SnD window is 1 (S-G1)")
    eq(rg.TEA_ENERGY_MAX_BY_FAMILY.SOD, 10, "SOD Tea line is 10 (S-M1)")
    eq(rg.SOD_TEA_FIGHT_END_TTD, 15, "SOD Tea fight-end TTD is 15 (S-M1)")
    eq(rg.SOD_TEA_FIGHT_END_MAX, 40, "SOD Tea fight-end line is 40 (S-M1)")
    check(rg.SHIV_MUTILATE_GATE_FAMILIES.TBC == true,
        "TBC Shivs only when Mutilate is unknown (T-G4)")
    check(rg.SHIV_MUTILATE_GATE_FAMILIES.ERA ~= true, "ERA keeps Shiv ungated")
    eq(rg.SHIV_CP_MAX_BY_FAMILY.TBC, 4, "TBC Shivs below 5CP (T-G4)")
    eq(rg.SHIV_CP_MAX_BY_FAMILY.ERA, nil, "ERA carries no Shiv CP row")
    check(rg.CB_FAMILIES.TBC == true, "TBC presses Cold Blood")
    check(rg.CB_FAMILIES.FOREVER == true, "FOREVER presses Cold Blood at 5CP")
    check(rg.CB_FAMILIES.ERA ~= true, "ERA never prompts Cold Blood (no sim row)")
    check(rg.CB_FAMILIES.WRATH ~= true, "WRATH never prompts Cold Blood (filed)")
    check(rg.CB_FAMILIES.RETAIL ~= true, "RETAIL never prompts Cold Blood (filed)")
    eq(rg.CB_MIN_CP_BY_FAMILY.FOREVER, 5, "FOREVER Cold Blood needs 5CP (V-G5)")
    eq(rg.CB_MIN_CP_BY_FAMILY.TBC, nil, "TBC carries no Cold Blood CP row")
end

-- Envenom rules: each family owns its table (never a shared reference).
do
    eq(rg.ENVENOM_RULES.TBC.mode, "dying_only", "TBC Envenom is dying-only")
    eq(rg.ENVENOM_RULES.ERA.mode, "dying_only", "ERA Envenom is dying-only")
    eq(rg.ENVENOM_RULES.WRATH.mode, "let_expire", "WRATH Envenom lets the buff expire")
    eq(rg.ENVENOM_RULES.FOREVER.mode, "never", "FOREVER never prompts Envenom")
    eq(rg.ENVENOM_RULES.RETAIL.mode, "chain", "RETAIL Envenom chains")
    check(rg.ENVENOM_RULES.ERA ~= rg.ENVENOM_RULES.TBC,
        "ERA and TBC own distinct Envenom tables (never shared)")
    check(rg.POOL_BANDS.ERA ~= rg.POOL_BANDS.TBC,
        "ERA and TBC own distinct band tables (never shared)")
end

--=========================================================================================
-- 0b) Rogue-owned TTD EMA (F1: vendored from the druid D4 precedent - same
--     smoothing, same inputs/outputs; no cross-class runtime read)
--=========================================================================================
do
    eq(rg.TTD_EMA_ALPHA, 0.25, "the rogue EMA weights the newest sample 0.25")
    eq(rg.TTD_SAMPLE_SECONDS, 0.25, "the rogue sampler throttles to 0.25 s")
    check(type(rg.update_hp_velocity) == "function", "the EMA step is exported")
    check(type(rg.get_time_to_die) == "function", "the TTD divide is exported")
    near(rg.update_hp_velocity(nil, 900, 1000, 1, 0.25), 100, 1e-9,
        "a first sample seeds the raw velocity")
    near(rg.update_hp_velocity(100, 800, 1000, 1, 0.25), 125, 1e-9,
        "a later sample smooths with weight 0.25")
    near(rg.update_hp_velocity(100, 900, 900, 1, 0.25), 75, 1e-9,
        "zero damage decays the EMA without crossing zero")
    near(rg.update_hp_velocity(50, 1000, 900, 1, 0.25), 37.5, 1e-9,
        "a heal contributes zero velocity")
    near(rg.update_hp_velocity(100, 800, 900, 1, nil), 0.25 * 100 + 0.75 * 100, 1e-9,
        "a missing alpha falls back to the shipped weight")
    near(rg.update_hp_velocity(100, 800, 900, 1, 0), 100, 1e-9,
        "a zero alpha falls back to the shipped weight")
    near(rg.update_hp_velocity(100, 800, 900, 1, 2), 100, 1e-9,
        "an out-of-range alpha falls back to the shipped weight")
    eq(rg.update_hp_velocity(100, nil, 900, 1, 0.25), nil, "a missing hp reads nil")
    eq(rg.update_hp_velocity(100, 800, nil, 1, 0.25), nil, "a missing prev_hp reads nil")
    eq(rg.update_hp_velocity(100, 800, 900, 0, 0.25), nil, "a zero dt reads nil")
    eq(rg.update_hp_velocity(100, 800, 900, -1, 0.25), nil, "a negative dt reads nil")
    eq(rg.update_hp_velocity(100, 800, 900, nil, 0.25), nil, "a missing dt reads nil")
    eq(rg.update_hp_velocity(100, 0 / 0, 900, 1, 0.25), nil, "a NaN hp reads nil")
    eq(rg.update_hp_velocity(100, 800, 0 / 0, 1, 0.25), nil, "a NaN prev_hp reads nil")
    near(rg.update_hp_velocity(0 / 0, 800, 900, 1, 0.25), 100, 1e-9,
        "a NaN ema re-seeds from the raw velocity")
    near(rg.get_time_to_die(1000, 100), 10, 1e-9, "1000 hp at 100 HP/s dies in 10 s")
    near(rg.get_time_to_die(50, 25), 2, 1e-9, "the estimate scales with the hp")
    near(rg.get_time_to_die(0, 100), 0, 1e-9, "zero hp reads zero seconds")
    eq(rg.get_time_to_die(1000, 0), nil, "a zero velocity has no crossing")
    eq(rg.get_time_to_die(1000, -5), nil, "a negative velocity has no crossing")
    eq(rg.get_time_to_die(nil, 100), nil, "a missing hp reads nil")
    eq(rg.get_time_to_die(1000, nil), nil, "a missing velocity reads nil")
    eq(rg.get_time_to_die(0 / 0, 100), nil, "a NaN hp reads nil")
    eq(rg.get_time_to_die(1000, 0 / 0), nil, "a NaN velocity reads nil")
end

--=========================================================================================
-- 1) The pooling-band predicate (per-family bands now: ERA 65/85, TBC single
-- 71, WRATH 65/85, FOREVER 65/75)
--=========================================================================================
do
    local era = rg.POOL_BANDS.ERA
    eq(rg.pool_verdict(50, 1.0, era), "pool", "ERA 50 energy pools")
    eq(rg.pool_verdict(64.9, 1.0, era), "pool", "ERA pre boundary: 64.9 pools")
    eq(rg.pool_verdict(65, 1.0, era), "spend", "ERA pre: 65 with a live tick spends")
    eq(rg.pool_verdict(65, nil, era), "pool", "ERA pre with unknown tick pools")
    eq(rg.pool_verdict(84.9, 1.0, era), "spend", "ERA 84.9 with a tick spends")
    eq(rg.pool_verdict(85, 9.9, era), "spend", "ERA post: 85 spends whatever the clock says")
    eq(rg.pool_verdict(100, 1.0, era), "spend", "ERA capped bar spends")
    eq(rg.pool_verdict(81, 1.0, era), "spend", "ERA 81 + 20 ticks past 100: spends")
    local tbc = rg.POOL_BANDS.TBC
    eq(rg.pool_verdict(50, 1.0, tbc), "pool", "TBC 50 energy pools")
    eq(rg.pool_verdict(70.9, 1.0, tbc), "pool", "TBC boundary: 70.9 pools")
    eq(rg.pool_verdict(71, nil, tbc), "spend", "TBC single line: 71 spends with no tick (T-M1)")
    eq(rg.pool_verdict(80, nil, tbc), "spend", "TBC 80 with unknown tick spends (no post line)")
    local forever = rg.POOL_BANDS.FOREVER
    eq(rg.pool_verdict(74.9, 1.0, forever), "spend", "FOREVER 74.9 with a tick spends")
    eq(rg.pool_verdict(75, 9.9, forever), "spend", "FOREVER post: 75 spends (V-G6)")
    eq(rg.pool_verdict(74.9, nil, forever), "pool", "FOREVER 74.9 unknown tick pools")
    eq(rg.pool_verdict(50, 1.0, nil), nil, "no band (RETAIL/unknown family) stays silent")
    eq(rg.pool_verdict(50, 1.0, {}), nil, "a band without numbers stays silent")
    eq(rg.pool_verdict(nil, 1.0, era), nil, "unknown energy answers nil (never guessed)")
    eq(rg.pool_verdict(0 / 0, 1.0, era), nil, "NaN energy answers nil")
    eq(rg.pool_verdict(50, 1.0, era, 110), "pool", "Vigor 110 cap pools at 50")
    eq(rg.pool_verdict(95, 1.0, era, 110), "spend", "95 + 20 ticks past 110: spends")
end

--=========================================================================================
-- 2) Rupture-vs-Eviscerate on numeric TTD
--=========================================================================================
do
    local opts = { min_cp = 5, rupture_refresh = 4, rupture_min_ttd = 8 }
    eq(rg.finisher_for_ttd(5, 30, nil, opts), "rupture",
        "Rupture missing with time to live -> Rupture")
    eq(rg.finisher_for_ttd(5, 30, 0, opts), "rupture",
        "Rupture expired with time to live -> Rupture")
    eq(rg.finisher_for_ttd(5, 30, 4, opts), "rupture",
        "boundary: Rupture at exactly the refresh window refreshes")
    eq(rg.finisher_for_ttd(5, 30, 4.1, opts), "eviscerate",
        "a healthy Rupture falls through to Eviscerate")
    eq(rg.finisher_for_ttd(5, 8, nil, opts), "eviscerate",
        "boundary: TTD at exactly 8 dies before Rupture pays -> Eviscerate")
    eq(rg.finisher_for_ttd(5, 7.9, 20, opts), "eviscerate",
        "short TTD Eviscerates even with Rupture up")
    eq(rg.finisher_for_ttd(5, 8.1, nil, opts), "rupture",
        "TTD just above 8 with Rupture missing -> Rupture")
    eq(rg.finisher_for_ttd(4, 30, nil, opts), nil,
        "4 CP is below the planned-finisher line -> nil")
    eq(rg.finisher_for_ttd(5, nil, nil, opts), nil,
        "unknown TTD answers nil (H4: never a guessed finisher)")
    eq(rg.finisher_for_ttd(nil, 30, nil, opts), nil, "unknown CP answers nil")
    eq(rg.finisher_for_ttd(5, 30, 0 / 0, opts), nil, "NaN Rupture answers nil")
    eq(rg.finisher_for_ttd(5, 0 / 0, nil, opts), nil, "NaN TTD answers nil")
    eq(rg.finisher_for_ttd(5, 30, nil, nil), "rupture",
        "nil opts fall back to the frozen defaults")
end

--=========================================================================================
-- 2b) Per-CP Rupture durations (audit W-M2 — sim-sourced rows only, DATA-only)
--=========================================================================================
do
    -- Sourced endpoint rows answer; everything else hides (never interpolated).
    eq(rg.rupture_duration_for_cp(1), 8, "1CP Rupture lasts 8 s (W-M2 sourced)")
    eq(rg.rupture_duration_for_cp(5), 16, "5CP Rupture lasts 16 s (W-M2 sourced)")
    eq(rg.rupture_duration_for_cp(2), nil, "2CP hides (UNCONFIRMED, never guessed)")
    eq(rg.rupture_duration_for_cp(3), nil, "3CP hides (UNCONFIRMED, never guessed)")
    eq(rg.rupture_duration_for_cp(4), nil, "4CP hides (UNCONFIRMED, never guessed)")
    eq(rg.rupture_duration_for_cp(0), nil, "0CP hides (no row)")
    eq(rg.rupture_duration_for_cp(6), nil, "6CP hides (no row)")
    eq(rg.rupture_duration_for_cp(nil), nil, "nil CP hides (never a guessed duration)")
    eq(rg.rupture_duration_for_cp(0 / 0), nil, "NaN CP hides")
    eq(rg.rupture_duration_for_cp("5"), nil, "a non-number CP hides")

    -- DATA-only: no sim rule consumes the table, so the flat floors still
    -- govern every verdict (no default-visible change). A 5CP TTD that the
    -- 16 s row would Eviscerate still Ruptures on the flat floors.
    local flat5 = { min_cp = 5, rupture_refresh = 0, rupture_min_ttd = 5 }
    eq(rg.finisher_for_ttd(5, 10, nil, flat5), "rupture",
        "DATA-only: TBC 5CP TTD 10 still Ruptures on the flat 5 s floor (not the 16 s row)")
    local flat4 = { min_cp = 4, rupture_refresh = 4, rupture_min_ttd = 4 }
    eq(rg.finisher_for_ttd(5, 10, nil, flat4), "rupture",
        "DATA-only: WRATH 5CP TTD 10 still Ruptures on the flat 4 s floor (not the 16 s row)")
end

--=========================================================================================
-- 3) Per-client Envenom verdicts
--=========================================================================================
do
    local tbc_band = rg.POOL_BANDS.TBC
    -- TBC dying_only: 5 CP + a stack + a dying target.
    eq(rg.envenom_verdict("TBC", { cp = 5, deadly_stacks = 3, ttd = 5 }, tbc_band), "envenom",
        "TBC: dying target with CP and stacks -> Envenom")
    eq(rg.envenom_verdict("TBC", { cp = 5, deadly_stacks = 3, ttd = 8 }, tbc_band), "envenom",
        "TBC boundary: TTD at exactly ttd_max still dumps")
    eq(rg.envenom_verdict("TBC", { cp = 5, deadly_stacks = 3, ttd = 8.1 }, tbc_band), nil,
        "TBC: a living target never Envenoms mid-fight")
    eq(rg.envenom_verdict("TBC", { cp = 5, deadly_stacks = 3, ttd = nil }, tbc_band), nil,
        "TBC: unknown TTD never Envenoms")
    eq(rg.envenom_verdict("TBC", { cp = 4, deadly_stacks = 5, ttd = 5 }, tbc_band), nil,
        "TBC: 4 CP is below the Envenom line")
    eq(rg.envenom_verdict("TBC", { cp = 5, deadly_stacks = 0, ttd = 5 }, tbc_band), nil,
        "TBC: no stacks to consume -> nil")
    eq(rg.envenom_verdict("TBC", { cp = 5, deadly_stacks = nil, ttd = 5 }, tbc_band), nil,
        "TBC: unknown stacks never Envenoms (consumption must be proven)")
    eq(rg.envenom_verdict("ERA", { cp = 5, deadly_stacks = 2, ttd = 4 }, tbc_band), "envenom",
        "ERA: same dying-only shape through its own table")
    -- WRATH let_expire: CP + 5 stacks prove it; an active buff withholds.
    eq(rg.envenom_verdict("WRATH", { cp = 4, deadly_stacks = 5 }, tbc_band), "envenom",
        "WRATH: 4 CP + 5 stacks with no buff -> Envenom")
    eq(rg.envenom_verdict("WRATH", { cp = 5, deadly_stacks = 5, envenom_buff_remains = nil }, tbc_band),
        "envenom", "WRATH: nil buff reads as missing (druid nil-rule precedent)")
    eq(rg.envenom_verdict("WRATH", { cp = 5, deadly_stacks = 5, envenom_buff_remains = 0 }, tbc_band),
        "envenom", "WRATH: an expired buff re-applies")
    eq(rg.envenom_verdict("WRATH",
        { cp = 5, deadly_stacks = 5, envenom_buff_remains = 6, energy_now = 50 }, tbc_band), nil,
        "WRATH: an active buff withholds re-apply (let it expire)")
    eq(rg.envenom_verdict("WRATH",
        { cp = 5, deadly_stacks = 5, envenom_buff_remains = 6, energy_now = 90 }, tbc_band), "envenom",
        "WRATH: active buff + capping energy chains early")
    eq(rg.envenom_verdict("WRATH",
        { cp = 5, deadly_stacks = 5, envenom_buff_remains = 6, energy_now = nil }, tbc_band), nil,
        "WRATH: active buff + unknown energy withholds (cap must be proven)")
    eq(rg.envenom_verdict("WRATH", { cp = 3, deadly_stacks = 5 }, tbc_band), nil,
        "WRATH: 3 CP is below the sin line")
    eq(rg.envenom_verdict("WRATH", { cp = 5, deadly_stacks = 4 }, tbc_band), nil,
        "WRATH: 4 stacks is below the 5-stack line")
    eq(rg.envenom_verdict("WRATH", { cp = 5, deadly_stacks = nil }, tbc_band), nil,
        "WRATH: unknown stacks never Envenoms")
    -- FOREVER never: even the perfect dump stays silent.
    eq(rg.envenom_verdict("FOREVER", { cp = 5, deadly_stacks = 5, ttd = 3 }, tbc_band), nil,
        "FOREVER: beta dumps Eviscerate, never Envenom")
    -- RETAIL chain: 5 CP chains unless stacks are proven empty.
    eq(rg.envenom_verdict("RETAIL", { cp = 5, envenom_buff_remains = 6 }, tbc_band), "envenom",
        "RETAIL: 5 CP chains while the buff rides")
    eq(rg.envenom_verdict("RETAIL", { cp = 5, envenom_buff_remains = nil }, tbc_band), "envenom",
        "RETAIL: 5 CP chains with an unknown buff")
    eq(rg.envenom_verdict("RETAIL", { cp = 5, deadly_stacks = 0 }, tbc_band), nil,
        "RETAIL: proven-empty stacks withhold the chain")
    eq(rg.envenom_verdict("RETAIL", { cp = 4 }, tbc_band), nil,
        "RETAIL: 4 CP is below the chain line")
    -- Unknown family: never a guessed Envenom.
    eq(rg.envenom_verdict("BOGUS", { cp = 5, deadly_stacks = 5, ttd = 3 }, tbc_band), nil,
        "unknown family never Envenoms")
    eq(rg.envenom_verdict(nil, { cp = 5, deadly_stacks = 5, ttd = 3 }, tbc_band), nil,
        "nil family never Envenoms")
    -- SOD primary, wired through the ERA + sod_envenom latch (evaluate maps
    -- the family; direct callers pass "SOD" themselves): 4+CP primary dump
    -- behind stacks, 2+CP fight-end.
    eq(rg.ENVENOM_RULES.SOD.mode, "sod_primary", "SOD owns its primary table")
    eq(rg.envenom_verdict("SOD", { cp = 4, deadly_stacks = 1, ttd = 30 }, tbc_band), "envenom",
        "SOD: 4 CP + stacks primary-dumps (S-C1)")
    eq(rg.envenom_verdict("SOD", { cp = 2, deadly_stacks = 1, ttd = 3 }, tbc_band), "envenom",
        "SOD: 2 CP on a dying target dumps")
    eq(rg.envenom_verdict("SOD", { cp = 2, deadly_stacks = 1, ttd = 30 }, tbc_band), nil,
        "SOD: 2 CP on a living target builds")
    eq(rg.envenom_verdict("SOD", { cp = 4, deadly_stacks = nil, ttd = 30 }, tbc_band), nil,
        "SOD: unknown stacks never Envenoms")
    eq(rg.envenom_verdict("SOD", { cp = 3, deadly_stacks = 1, ttd = 30 }, tbc_band), nil,
        "SOD: 3 CP on a living target is below the primary line")
end

--=========================================================================================
-- 4) EA duty, Shiv upkeep, Thistle Tea
--=========================================================================================
do
    eq(rg.ea_verdict(true, nil, 3), "expose", "EA duty with no clock prompts (missing upkeep)")
    eq(rg.ea_verdict(true, 3, 3), "expose", "boundary: EA at exactly the window refreshes")
    eq(rg.ea_verdict(true, 3.1, 3), nil, "a healthy EA stays silent")
    eq(rg.ea_verdict(true, 0, 3), "expose", "a fallen EA re-applies")
    eq(rg.ea_verdict(false, nil, 3), nil, "off duty never Exposes")
    eq(rg.ea_verdict(nil, nil, 3), nil, "nil duty never Exposes")
    eq(rg.ea_verdict(true, 0 / 0, 3), nil, "NaN EA clock answers nil")

    eq(rg.shiv_verdict(5, 1.5, true, 2), "shiv", "Deadly falling off with Shiv ready -> Shiv")
    eq(rg.shiv_verdict(5, 2, true, 2), "shiv", "boundary: falloff at exactly the window Shivs")
    eq(rg.shiv_verdict(5, 2.1, true, 2), nil, "a healthy Deadly clock stays silent")
    eq(rg.shiv_verdict(5, nil, true, 2), nil, "nil Deadly clock never Shivs (H4)")
    eq(rg.shiv_verdict(5, 0 / 0, true, 2), nil, "NaN Deadly clock never Shivs")
    eq(rg.shiv_verdict(5, 1.0, false, 2), nil, "Shiv on cooldown never prompts")
    eq(rg.shiv_verdict(5, 1.0, nil, 2), nil, "unknown Shiv usability never prompts")
    eq(rg.shiv_verdict(5, 1.0, true, nil), "shiv", "nil window falls back to the 2 s default")

    eq(rg.tea_verdict(true, 30, 40), "tea", "low energy with Tea ready -> Tea")
    eq(rg.tea_verdict(true, 40, 40), "tea", "boundary: energy at exactly the line Teas")
    eq(rg.tea_verdict(true, 41, 40), nil, "energy above the line stays silent")
    eq(rg.tea_verdict(false, 10, 40), nil, "Tea on cooldown never prompts")
    eq(rg.tea_verdict(true, nil, 40), nil, "unknown energy never Teas")
    eq(rg.tea_verdict(true, 10, nil), "tea", "nil line falls back to the 40 default")

    -- R3 stacked multi-CD glow (rogue_deep §2.7; competitor_gaps R3): two or more
    -- active offensive CDs glow; anything else stays silent (never a guess).
    eq(rg.stacked_glow(2), true, "two stacked CDs glow")
    eq(rg.stacked_glow(3), true, "three stacked CDs glow")
    eq(rg.stacked_glow(1), nil, "a lone CD never glows")
    eq(rg.stacked_glow(0), nil, "no active CD never glows")
    eq(rg.stacked_glow(nil), nil, "an unknown count never glows")
    eq(rg.stacked_glow(0 / 0), nil, "NaN never glows")
end

--=========================================================================================
-- 4c) H6: the TBC EA-duty wait/release + the Forever finisher lockout
--=========================================================================================
do
    local tbc_band = rg.POOL_BANDS.TBC
    local function wait(args, band, window)
        return rg.ea_wait_verdict("TBC", args, band or tbc_band, window)
    end
    local healthy = { ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }

    -- Duty / family / minimum gates.
    eq(rg.ea_wait_verdict("TBC", healthy, tbc_band, 6), "wait",
        "H6: 5CP + duty + EA below minimum + healthy SnD + low energy holds")
    eq(wait({ ea_duty = false, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }), nil,
        "H6: off duty never waits (inert by default)")
    eq(wait({ ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }), nil,
        "H6: nil duty never waits")
    eq(rg.ea_wait_verdict("ERA", healthy, rg.POOL_BANDS.ERA, 3), nil,
        "H6: ERA has no minimum row (no wait)")
    eq(rg.ea_wait_verdict("FOREVER", healthy, rg.POOL_BANDS.FOREVER, 16), nil,
        "H6: FOREVER has no minimum row (lockout instead)")
    eq(rg.ea_wait_verdict("BOGUS", healthy, tbc_band, 6), nil,
        "H6: unknown family never waits")
    eq(wait(nil, tbc_band, 6), nil, "H6: nil args never wait")

    -- EA clock: missing belongs to rule 1, above-minimum is normal priority,
    -- imminent belongs to rule 1, NaN hides.
    eq(wait({ ea_duty = true, ea_remains = nil, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }), nil,
        "H6: missing EA belongs to rule 1 (no wait)")
    eq(wait({ ea_duty = true, ea_remains = 15, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }), nil,
        "H6 boundary: EA at exactly the 15 s minimum is above-minimum")
    eq(wait({ ea_duty = true, ea_remains = 15.1, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }), nil,
        "H6: a healthy EA runs the normal priority")
    eq(wait({ ea_duty = true, ea_remains = 6, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }), nil,
        "H6 boundary: EA at exactly the 6 s window belongs to rule 1")
    eq(wait({ ea_duty = true, ea_remains = 6.1, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }), "wait",
        "H6: EA just above imminent holds")
    eq(wait({ ea_duty = true, ea_remains = 14.9, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }), "wait",
        "H6: EA just below the minimum holds")
    eq(wait({ ea_duty = true, ea_remains = 0 / 0, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }), nil,
        "H6: NaN EA hides (unknown-hides)")

    -- CP: the sim group enters at exactly 5CP (CP caps at 5).
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 4,
        snd_usable = true, snd_remains = 20, energy_now = 50 }), nil,
        "H6: 4 CP never waits (the group needs 5)")
    eq(wait({ ea_duty = true, ea_remains = 10, cp = nil,
        snd_usable = true, snd_remains = 20, energy_now = 50 }), nil,
        "H6: unknown CP never waits")

    -- SnD cover: genuinely missing or short releases now; unreadable hides;
    -- NaN hides.
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = nil, energy_now = 50 }), "expose",
        "H6: missing SnD cannot cover the wait - cast now")
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 9.9, energy_now = 50 }), "expose",
        "H6: SnD short of 10 releases now")
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 10, energy_now = 50 }), "wait",
        "H6 boundary: SnD at exactly 10 covers the wait")
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = nil, snd_remains = nil, energy_now = 50 }), nil,
        "H6: unreadable SnD hides (no wait machinery)")
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 0 / 0, energy_now = 50 }), nil,
        "H6: NaN SnD hides")

    -- Energy: the pool line releases, below holds, unknown hides.
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 71 }), "expose",
        "H6 boundary: energy at exactly 71 releases into Expose")
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 70.9 }), "wait",
        "H6: energy just below 71 holds")
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = nil }), nil,
        "H6: unknown energy hides")
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 0 / 0 }), nil,
        "H6: NaN energy hides")
    eq(rg.ea_wait_verdict("TBC", { ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }, nil, 6), nil,
        "H6: no band line hides")
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }, {}), nil,
        "H6: a band without numbers hides")

    -- Explicit window wins over the family row.
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }, tbc_band, 12), nil,
        "H6: EA at 10 inside an explicit 12 window belongs to rule 1")
    eq(wait({ ea_duty = true, ea_remains = 13, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }, tbc_band, 12), "wait",
        "H6: EA at 13 above an explicit 12 window holds")
    eq(wait({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50 }, tbc_band, nil), "wait",
        "H6: nil window falls back to the family 6")

    -- Forever lockout: duty + low EA suppresses, everything else stays live.
    eq(rg.ea_lockout_active("FOREVER", true, nil, 16), true,
        "H6 lockout: missing EA on duty locks out")
    eq(rg.ea_lockout_active("FOREVER", true, 16, 16), true,
        "H6 lockout boundary: EA at exactly 16 locks out")
    eq(rg.ea_lockout_active("FOREVER", true, 16.1, 16), false,
        "H6 lockout: EA at 16.1 runs the normal priority")
    eq(rg.ea_lockout_active("FOREVER", true, 10, 16), true,
        "H6 lockout: EA at 10 locks out")
    eq(rg.ea_lockout_active("FOREVER", false, nil, 16), false,
        "H6 lockout: off duty never locks out (inert by default)")
    eq(rg.ea_lockout_active("FOREVER", nil, nil, 16), false,
        "H6 lockout: nil duty never locks out")
    eq(rg.ea_lockout_active("FOREVER", true, 0 / 0, 16), false,
        "H6 lockout: NaN EA hides")
    eq(rg.ea_lockout_active("TBC", true, nil, 6), false,
        "H6 lockout: TBC never locks out (waits instead)")
    eq(rg.ea_lockout_active("ERA", true, nil, 3), false,
        "H6 lockout: ERA never locks out")
    eq(rg.ea_lockout_active("BOGUS", true, nil, 16), false,
        "H6 lockout: unknown family never locks out")
    eq(rg.ea_lockout_active("FOREVER", true, 10, nil), true,
        "H6 lockout: nil window falls back to the family 16")
end

--=========================================================================================
-- 4b) SnD upkeep, AR and Blade Flurry (audit F0/H1 + F3/H11)
--=========================================================================================
do
    -- SnD: usable spell + family CP floor + missing-or-inside-window.
    eq(rg.snd_verdict("TBC", { snd_usable = true, cp = 2, snd_remains = nil }), "snd",
        "TBC: missing SnD at 2 CP prompts (upkeep gap)")
    eq(rg.snd_verdict("TBC", { snd_usable = true, cp = 2, snd_remains = 0 }), "snd",
        "TBC boundary: SnD at exactly the 0 window refreshes")
    eq(rg.snd_verdict("TBC", { snd_usable = true, cp = 1, snd_remains = nil }), nil,
        "TBC: 1 CP never SnDs (10 s minimum)")
    eq(rg.snd_verdict("ERA", { snd_usable = true, cp = 1, snd_remains = nil }), "snd",
        "ERA: 1 CP SnDs (classic early SnD)")
    eq(rg.snd_verdict("ERA", { snd_usable = true, cp = 1, snd_remains = 3 }), "snd",
        "ERA boundary: SnD at exactly 3 refreshes")
    eq(rg.snd_verdict("ERA", { snd_usable = true, cp = 1, snd_remains = 3.1 }), nil,
        "ERA: a healthy SnD stays silent")
    eq(rg.snd_verdict("WRATH", { snd_usable = true, cp = 5, snd_remains = 1 }), "snd",
        "WotLK boundary: SnD at exactly 1 refreshes")
    eq(rg.snd_verdict("FOREVER", { snd_usable = true, cp = 1, snd_remains = nil }), "snd",
        "FOREVER: 1 CP SnDs (clip model)")
    eq(rg.snd_verdict("TBC", { snd_usable = true, cp = 2, snd_remains = 0 / 0 }), nil,
        "NaN SnD clock never prompts (H4)")
    eq(rg.snd_verdict("TBC", { snd_usable = nil, cp = 5, snd_remains = nil }), nil,
        "an unresolved SnD spell never prompts")
    eq(rg.snd_verdict("TBC", { snd_usable = true, cp = nil, snd_remains = nil }), nil,
        "unknown CP never SnDs")
    eq(rg.snd_verdict("BOGUS", { snd_usable = true, cp = 5, snd_remains = nil }), nil,
        "unknown family never SnDs (no refresh row)")
    eq(rg.snd_verdict(nil, { snd_usable = true, cp = 5, snd_remains = nil }), nil,
        "nil family never SnDs")
    eq(rg.snd_verdict("TBC",
        { snd_usable = true, cp = 5, snd_remains = nil, snd_refresh = 2 }), "snd",
        "an explicit refresh override wins over the family row")
    eq(rg.snd_verdict("TBC",
        { snd_usable = true, cp = 1, snd_remains = nil, snd_min_cp = 1 }), "snd",
        "an explicit min-CP override wins over the family row")

    -- AR: ready + family energy line (+ERA tick gate, +FOREVER SnD ride).
    eq(rg.ar_verdict("TBC", { ar_ready = true, energy_now = 40 }), "ar",
        "TBC boundary: AR at exactly 40 fires")
    eq(rg.ar_verdict("TBC", { ar_ready = true, energy_now = 41 }), nil,
        "TBC: 41 energy withholds AR")
    eq(rg.ar_verdict("ERA", { ar_ready = true, energy_now = 58, energy_tick_in = 0.5 }), "ar",
        "ERA: AR below 59 with a tick inside 1 s fires")
    eq(rg.ar_verdict("ERA", { ar_ready = true, energy_now = 59, energy_tick_in = 0.5 }), nil,
        "ERA: AR at exactly 59 never fires")
    eq(rg.ar_verdict("ERA", { ar_ready = true, energy_now = 58, energy_tick_in = nil }), nil,
        "ERA: AR with an unknown tick withholds (never a timed guess)")
    eq(rg.ar_verdict("ERA", { ar_ready = true, energy_now = 58, energy_tick_in = 1.0 }), nil,
        "ERA boundary: AR at exactly tick 1.0 withholds")
    eq(rg.ar_verdict("FOREVER", { ar_ready = true, energy_now = 50, snd_remains = 10 }), "ar",
        "FOREVER: AR at 50 with SnD riding fires")
    eq(rg.ar_verdict("FOREVER", { ar_ready = true, energy_now = 50, snd_remains = nil }), nil,
        "FOREVER: AR without SnD withholds")
    eq(rg.ar_verdict("WRATH", { ar_ready = true, energy_now = 50 }), "ar",
        "WotLK: AR at 50 fires")
    eq(rg.ar_verdict("WRATH", { ar_ready = true, energy_now = 51 }), nil,
        "WotLK: 51 withholds AR")
    eq(rg.ar_verdict("TBC", { ar_ready = nil, energy_now = 10 }), nil,
        "an unready AR never prompts")
    eq(rg.ar_verdict("TBC", { ar_ready = true, energy_now = nil }), nil,
        "unknown energy never prompts AR")
    eq(rg.ar_verdict("BOGUS", { ar_ready = true, energy_now = 10 }), nil,
        "unknown family never prompts AR")
    eq(rg.ar_verdict("RETAIL", { ar_ready = true, energy_now = 10 }), nil,
        "RETAIL never prompts AR (no sim line — filed)")

    -- BF: ready + SnD riding (+EA healthy while on duty).
    eq(rg.bf_verdict("TBC",
        { bf_ready = true, snd_remains = 10, ea_duty = true, ea_remains = 20 }), "bf",
        "TBC: BF with SnD + healthy EA fires")
    eq(rg.bf_verdict("TBC",
        { bf_ready = true, snd_remains = 10, ea_duty = true, ea_remains = nil }), nil,
        "TBC: BF withholds while EA is due (EA rule fires first)")
    eq(rg.bf_verdict("TBC",
        { bf_ready = true, snd_remains = 10, ea_duty = false }), "bf",
        "off duty, BF needs SnD only")
    eq(rg.bf_verdict("TBC", { bf_ready = true, snd_remains = nil }), nil,
        "BF without SnD never prompts")
    eq(rg.bf_verdict("TBC", { bf_ready = true, snd_remains = 0 }), nil,
        "BF with a fallen SnD never prompts")
    eq(rg.bf_verdict("TBC", { bf_ready = nil, snd_remains = 10 }), nil,
        "an unready BF never prompts")
    eq(rg.bf_verdict("BOGUS", { bf_ready = true, snd_remains = 10 }), nil,
        "unknown family never prompts BF")
    eq(rg.bf_verdict("RETAIL", { bf_ready = true, snd_remains = 10 }), nil,
        "RETAIL never prompts BF (filed)")
end

--=========================================================================================
-- 4d) TBC Shiv gates, Cold Blood, SOD SnD/Tea rows (rogue-leftovers 2026-10-19)
--=========================================================================================
do
    -- shiv_family_ok: the TBC Mutilate/CP gates; ERA ungated; elsewhere nil.
    eq(rg.shiv_family_ok("TBC", { cp = 4 }), true,
        "TBC below 5CP with unknown Mutilate Shivs")
    eq(rg.shiv_family_ok("TBC", { cp = 4, mutilate_known = nil }), true,
        "TBC nil Mutilate never withholds (unknown keeps the upkeep)")
    eq(rg.shiv_family_ok("TBC", { cp = 4, mutilate_known = false }), true,
        "TBC false Mutilate never withholds (only strict true gates)")
    eq(rg.shiv_family_ok("TBC", { cp = 4, mutilate_known = true }), nil,
        "TBC Mutilate-known withholds Shiv (T-G4)")
    eq(rg.shiv_family_ok("TBC", { cp = 5 }), nil,
        "TBC at 5CP never Shivs (T-G4)")
    eq(rg.shiv_family_ok("TBC", { cp = nil }), nil,
        "TBC unknown CP hides (never a guessed Shiv)")
    eq(rg.shiv_family_ok("TBC", { cp = 0 / 0 }), nil, "TBC NaN CP hides")
    eq(rg.shiv_family_ok("ERA", { cp = 5, mutilate_known = true }), true,
        "ERA ignores both gates (H7)")
    eq(rg.shiv_family_ok("WRATH", { cp = 0 }), nil, "WotLK never Shivs (H7)")
    eq(rg.shiv_family_ok("FOREVER", { cp = 0 }), nil, "FOREVER never Shivs (H7)")
    eq(rg.shiv_family_ok("BOGUS", { cp = 0 }), nil, "unknown family never Shivs")
    eq(rg.shiv_family_ok("TBC", nil), nil, "nil args never Shiv")

    -- cb_verdict: TBC w/ SnD, Forever at 5CP w/ SnD; elsewhere nil.
    eq(rg.cb_verdict("TBC", { coldblood_ready = true, snd_remains = 20 }), "coldblood",
        "TBC: Cold Blood with SnD riding fires")
    eq(rg.cb_verdict("TBC", { coldblood_ready = true, snd_remains = nil }), nil,
        "TBC: Cold Blood without SnD withholds")
    eq(rg.cb_verdict("TBC", { coldblood_ready = true, snd_remains = 0 }), nil,
        "TBC: Cold Blood with a fallen SnD withholds")
    eq(rg.cb_verdict("TBC", { coldblood_ready = nil, snd_remains = 20 }), nil,
        "an unready Cold Blood never prompts")
    eq(rg.cb_verdict("TBC", { coldblood_ready = true, snd_remains = 0 / 0 }), nil,
        "NaN SnD never prompts Cold Blood")
    eq(rg.cb_verdict("FOREVER",
        { coldblood_ready = true, snd_remains = 20, cp = 5 }), "coldblood",
        "FOREVER: Cold Blood at 5CP with SnD fires (V-G5)")
    eq(rg.cb_verdict("FOREVER",
        { coldblood_ready = true, snd_remains = 20, cp = 4 }), nil,
        "FOREVER: 4CP withholds Cold Blood")
    eq(rg.cb_verdict("FOREVER",
        { coldblood_ready = true, snd_remains = 20, cp = nil }), nil,
        "FOREVER: unknown CP withholds Cold Blood")
    eq(rg.cb_verdict("ERA",
        { coldblood_ready = true, snd_remains = 20, cp = 5 }), nil,
        "ERA never prompts Cold Blood (no sim row)")
    eq(rg.cb_verdict("WRATH",
        { coldblood_ready = true, snd_remains = 20, cp = 5 }), nil,
        "WRATH never prompts Cold Blood (filed)")
    eq(rg.cb_verdict("RETAIL",
        { coldblood_ready = true, snd_remains = 20, cp = 5 }), nil,
        "RETAIL never prompts Cold Blood (filed)")
    eq(rg.cb_verdict("BOGUS",
        { coldblood_ready = true, snd_remains = 20, cp = 5 }), nil,
        "unknown family never prompts Cold Blood")
    eq(rg.cb_verdict("TBC", nil), nil, "nil args never prompt Cold Blood")

    -- SOD SnD rows through the direct family (evaluate maps the ERA latch).
    eq(rg.snd_verdict("SOD", { snd_usable = true, cp = 4, snd_remains = nil }), "snd",
        "SOD: missing SnD at 4 CP prompts (S-G1)")
    eq(rg.snd_verdict("SOD", { snd_usable = true, cp = 4, snd_remains = 1 }), "snd",
        "SOD boundary: SnD at exactly 1 refreshes")
    eq(rg.snd_verdict("SOD", { snd_usable = true, cp = 4, snd_remains = 1.1 }), nil,
        "SOD: a healthy SnD stays silent")
    eq(rg.snd_verdict("SOD", { snd_usable = true, cp = 3, snd_remains = nil }), nil,
        "SOD: 3 CP never SnDs (S-G1 4CP line)")
end

--=========================================================================================
-- 5) evaluate: rule order, the unknown contract, frozen fields, nil-safety
--=========================================================================================
local NONE = {}
local function inp(overrides)
    local t = {
        family = "TBC",
        energy_now = 50, energy_tick_in = 1.0, max_energy = 100,
        cp = 0, ttd = 30,
        rupture_remains = 20,
        deadly_stacks = 0, deadly_remaining = nil,
        envenom_buff_remains = nil,
        ea_duty = false, ea_remains = nil,
        shiv_ready = false,
        tea_ready = false,
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
    local ret = rg.evaluate(inp(overrides), out)
    eq(ret, out, "evaluate returns the caller's out table")
    return out
end

-- Baseline (rule 7): low energy, no CP, nothing due -> POOL.
do
    local out = evaluate({})
    eq(out.action, nil, "baseline: pooling shows no action")
    eq(out.hold, true, "baseline: pooling holds")
    eq(out.hold_text, "POOL", "baseline: the hold reads POOL")
    eq(out.unknown, false, "baseline: readable inputs are not unknown")
    eq(out.filler_slot, nil, "baseline: filler_slot stays nil")
    eq(out.judge_slot, nil, "baseline: judge_slot stays nil")
    eq(out.rotation_key, nil, "baseline: rotation_key stays nil")
    eq(out.waiting_judgement, false, "baseline: waiting_judgement stays false")
end

-- Rule 0: the unknown contract outranks everything.
do
    local out = evaluate({ energy_now = NONE })
    eq(out.unknown, true, "unreadable energy is caller-visible unknown")
    eq(out.action, nil, "unknown energy shows no action (never guessed)")
    eq(out.hold, false, "unknown energy shows no hold")
    eq(out.hold_text, nil, "unknown energy shows no hold text")
    out = evaluate({ cp = NONE })
    eq(out.unknown, true, "unreadable CP is caller-visible unknown")
    eq(out.action, nil, "unknown CP shows no action")
    out = evaluate({ energy_now = NONE, ea_duty = true, ea_remains = nil })
    eq(out.action, nil, "unknown outranks even a due EA refresh")
    eq(out.unknown, true, "EA cannot rescue unknown core reads")
    out = evaluate({ energy_now = 0 / 0, cp = 5 })
    eq(out.unknown, true, "NaN energy is unknown")
    check(rg.is_unknown(nil) == true, "is_unknown(nil) is true")
    check(rg.is_unknown({}) == true, "is_unknown({}) is true")
    check(rg.is_unknown({ energy_now = 50, cp = 0 }) == false, "is_unknown is false on usable reads")
end

-- Rule 0b: the explicit provider-owned M6 bit outranks even readable core reads.
do
    local out = evaluate({ inputs_unknown = true })
    eq(out.unknown, true, "an explicit inputs_unknown bit is caller-visible unknown")
    eq(out.action, nil, "the explicit bit suppresses every action")
    eq(out.hold, false, "the explicit bit suppresses the hold")
    out = evaluate({ inputs_unknown = true, ea_duty = true, ea_remains = nil, cp = 5 })
    eq(out.action, nil, "the explicit bit outranks even a due EA refresh")
    out = evaluate({ inputs_unknown = true, cp = 5, deadly_stacks = 5, ttd = 3 })
    eq(out.unknown, true, "the bit owns the verdict regardless of the payload")
    out = evaluate({ inputs_unknown = false })
    eq(out.unknown, false, "an explicit false bit leaves readable reads alone")
    check(rg.is_unknown({ energy_now = 50, cp = 0, inputs_unknown = true }) == true,
        "is_unknown honours the explicit bit")
    check(rg.is_unknown({ energy_now = 50, cp = 0, inputs_unknown = false }) == false,
        "is_unknown is false on an explicit false bit with usable reads")
end

-- Rule 1: EA duty outranks every spender.
do
    eq(evaluate({ ea_duty = true, ea_remains = nil, cp = 5 }).action, "expose",
        "rule 1: a missing EA on duty outranks a 5-CP finisher")
    eq(evaluate({ ea_duty = true, ea_remains = 2, cp = 5, deadly_stacks = 5,
        deadly_remaining = 1, shiv_ready = true }).action, "expose",
        "rule 1 outranks a due Shiv")
    eq(evaluate({ ea_duty = true, ea_remains = 10, cp = 5,
        rupture_remains = NONE }).action, "rupture",
        "a healthy EA falls through to the finisher")
    eq(evaluate({ ea_duty = true, ea_remains = nil, cp = 5, ttd = 5,
        deadly_stacks = 3 }).action, "expose",
        "rule 1 outranks a due TBC Envenom (EA-due + envenom-due -> expose)")
end

-- Rule 2: Shiv upkeep before the Deadly clock falls off (TBC below 5CP).
do
    eq(evaluate({ shiv_ready = true, deadly_remaining = 1, deadly_stacks = 5,
        cp = 4 }).action, "shiv",
        "rule 2: an imminent Deadly falloff Shivs before the finisher")
    eq(evaluate({ shiv_ready = true, deadly_remaining = 1, deadly_stacks = 5,
        cp = 5 }).action, "eviscerate",
        "TBC CP gate: at 5CP the finisher wins over a due Shiv (T-G4)")
    eq(evaluate({ shiv_ready = true, deadly_remaining = 1, deadly_stacks = 5,
        cp = 5, mutilate_known = true }).action, "eviscerate",
        "TBC Mutilate gate: Mutilate-known withholds Shiv (T-G4)")
    eq(evaluate({ family = "ERA", shiv_ready = true, deadly_remaining = 1,
        deadly_stacks = 5, cp = 5, mutilate_known = true }).action, "shiv",
        "ERA keeps Shiv ungated (no sim either way — H7)")
    eq(evaluate({ shiv_ready = true, deadly_remaining = 10, deadly_stacks = 5,
        cp = 5, rupture_remains = NONE }).action, "rupture",
        "a healthy Deadly clock falls through to the finisher")
    eq(evaluate({ shiv_ready = true, deadly_remaining = 1, deadly_stacks = 5,
        cp = 4, ttd = 5 }).action, "shiv",
        "rule 2 outranks a due TBC Envenom (shiv-due + envenom-due -> shiv)")
    eq(evaluate({ shiv_ready = true, deadly_remaining = 1, deadly_stacks = 5,
        cp = 5, ttd = 5 }).action, "envenom",
        "at 5CP the CP gate yields Shiv to the due Envenom (T-G4)")
    eq(evaluate({ shiv_ready = true, deadly_remaining = 1, deadly_stacks = 5,
        cp = 1, ttd = 5 }).action, "shiv",
        "rule 2 outranks the dying dump (shiv-due + dying -> shiv)")
end

-- Rule 3: per-client Envenom sits between Shiv and the TTD decider.
do
    eq(evaluate({ family = "TBC", cp = 5, deadly_stacks = 3, ttd = 5 }).action, "envenom",
        "rule 3: the TBC dying-target Envenom fires")
    eq(evaluate({ family = "FOREVER", cp = 5, deadly_stacks = 5, ttd = 3,
        rupture_remains = NONE }).action, "eviscerate",
        "FOREVER never Envenoms: the dying dump fires instead")
    eq(evaluate({ family = "WRATH", cp = 5, deadly_stacks = 5,
        envenom_buff_remains = nil, ttd = 60, rupture_remains = 20 }).action, "envenom",
        "rule 3: the Wrath Envenom outranks a healthy Rupture")
end

-- Rules 4-5: the dying dump (per-family CP floor) and the planned finisher
-- (ERA Eviscerate-first, rupture-first elsewhere).
do
    eq(evaluate({ family = "ERA", cp = 1, ttd = 5 }).action, "eviscerate",
        "rule 4: ERA 1 CP on a dying target Eviscerates (Era any-CP rule)")
    eq(evaluate({ family = "ERA", cp = 1, ttd = 8 }).action, "eviscerate",
        "rule 4 boundary: ERA ttd at exactly 8 still dumps")
    eq(evaluate({ family = "ERA", cp = 0, ttd = 5 }).action, nil,
        "rule 4 needs at least 1 CP on ERA: 0 CP with no Tea ready pools")
    eq(evaluate({ family = "TBC", cp = 1, ttd = 5 }).action, nil,
        "rule 4: TBC 1 CP on a dying target builds (T-C1 — no any-CP leak)")
    eq(evaluate({ family = "TBC", cp = 1, ttd = 5 }).hold, true,
        "rule 4: TBC 1 CP pools toward the 5CP finisher")
    eq(evaluate({ family = "TBC", cp = 5, ttd = 5, rupture_remains = NONE }).action, "eviscerate",
        "rule 4 boundary: TBC 5CP at exactly 5 dumps")
    eq(evaluate({ family = "TBC", cp = 5, ttd = 5.1, rupture_remains = NONE }).action, "rupture",
        "rule 5: TBC 5CP just above 5 with Rupture missing -> Rupture")
    eq(evaluate({ family = "WRATH", cp = 3, ttd = 3 }).action, nil,
        "rule 4: WRATH 3 CP builds (dump needs 4)")
    eq(evaluate({ family = "WRATH", cp = 4, ttd = 4 }).action, "eviscerate",
        "rule 4 boundary: WRATH 4CP at exactly 4 dumps")
    eq(evaluate({ family = "WRATH", cp = 4, ttd = 30, rupture_remains = NONE }).action, "rupture",
        "rule 5: WRATH 4CP with time and no Rupture -> Rupture")
    eq(evaluate({ family = "FOREVER", cp = 2, ttd = 5 }).action, nil,
        "rule 4: FOREVER 2 CP builds (dump needs 3)")
    eq(evaluate({ family = "FOREVER", cp = 3, ttd = 6 }).action, "eviscerate",
        "rule 4 boundary: FOREVER 3CP at exactly 6 dumps")
    eq(evaluate({ family = "FOREVER", cp = 3, ttd = 30,
        rupture_remains = NONE }).action, "rupture",
        "rule 5: FOREVER 3CP with time and no Rupture -> Rupture (V-G3)")
    eq(evaluate({ family = "FOREVER", cp = 2, ttd = 30,
        rupture_remains = NONE }).action, nil,
        "2 CP is below the FOREVER line (falls to Tea/pool)")
    eq(evaluate({ family = "ERA", cp = 5, ttd = 60, rupture_remains = NONE }).action, "eviscerate",
        "rule 5: ERA 5CP with time and no Rupture -> Eviscerate (E-C1)")
    eq(evaluate({ family = "ERA", cp = 5, ttd = 60, rupture_remains = 20 }).action, "eviscerate",
        "rule 5: ERA never Ruptures, even healthy (E-C1)")
    eq(evaluate({ family = "TBC", cp = 5, ttd = 60, rupture_remains = NONE }).action, "rupture",
        "rule 5: TBC 5 CP with time and no Rupture -> Rupture")
    eq(evaluate({ family = "TBC", cp = 5, ttd = 60, rupture_remains = 20 }).action, "eviscerate",
        "rule 5: TBC 5CP with Rupture healthy -> Eviscerate")
    eq(evaluate({ family = "TBC", cp = 5, ttd = NONE, rupture_remains = NONE }).action, nil,
        "rule 5 with unknown TTD guesses no finisher (falls to Tea/pool)")
    eq(evaluate({ family = "TBC", cp = 4, ttd = 60, rupture_remains = NONE }).action, nil,
        "4 CP is below the TBC line (falls to Tea/pool)")
    eq(evaluate({ family = "BOGUS", cp = 5 }).action, "eviscerate",
        "unknown family still plans the finisher (every rogue client has Rupture/Eviscerate)")
end

-- Rules 6-7: Tea on a proven deficit, then pool-vs-spend.
do
    eq(evaluate({ cp = 0, tea_ready = true, energy_now = 20 }).action, "tea",
        "rule 6: low energy with Tea ready -> Tea")
    eq(evaluate({ cp = 5, ttd = NONE, rupture_remains = NONE,
        tea_ready = true, energy_now = 20 }).action, "tea",
        "rule 6 catches the unknown-TTD fallthrough on a deficit")
    eq(evaluate({ cp = 0, tea_ready = true, energy_now = 50 }).hold_text, "POOL",
        "a healthy bar with Tea ready still pools")
    eq(evaluate({ cp = 0, energy_now = 90, energy_tick_in = 0.5 }).action, "builder",
        "rule 7: 90 energy spends (the builder)")
    eq(evaluate({ cp = 0, energy_now = 90, energy_tick_in = 0.5 }).hold, false,
        "the builder prompt carries no hold")
    eq(evaluate({ family = "RETAIL", cp = 0, energy_now = 10 }).action, nil,
        "RETAIL has no tick band: low energy stays silent (phase pooling)")
    eq(evaluate({ family = "RETAIL", cp = 0, energy_now = 10 }).hold, false,
        "RETAIL silence carries no hold")
    eq(evaluate({ family = "BOGUS", cp = 0, energy_now = 10 }).action, nil,
        "unknown family stays silent too")
end

-- Per-family evaluate: SnD upkeep order, EA windows, Tea defaults, the sweaty
-- override, the Shiv gate and the AR/BF placement.
do
    -- 1b: SnD outranks spenders, yields to EA and to the dying dump.
    eq(evaluate({ snd_usable = true, snd_remains = nil, cp = 2, ttd = 30 }).action, "snd",
        "rule 1b: missing SnD with CP prompts before the finisher")
    eq(evaluate({ snd_usable = true, snd_remains = 20, cp = 5, ttd = 60,
        rupture_remains = NONE }).action, "rupture",
        "a healthy SnD falls through to the TBC finisher")
    eq(evaluate({ ea_duty = true, ea_remains = nil, cp = 5,
        snd_usable = true, snd_remains = nil }).action, "expose",
        "rule 1 outranks 1b (EA-due + SnD-missing -> expose)")
    eq(evaluate({ family = "ERA", snd_usable = true, snd_remains = nil,
        cp = 5, ttd = 5 }).action, "eviscerate",
        "the dying dump owns dying targets even with SnD missing")
    eq(evaluate({ shiv_ready = true, deadly_remaining = 1, deadly_stacks = 5,
        cp = 5, snd_usable = true, snd_remains = nil, ttd = 30 }).action, "snd",
        "rule 1b outranks a due Shiv (upkeep order: SnD first)")

    -- EA windows per family through evaluate (explicit input still wins).
    eq(evaluate({ family = "TBC", ea_duty = true, ea_remains = 5,
        cp = 0 }).action, "expose",
        "TBC: EA at 5 (inside 6) refreshes")
    eq(evaluate({ family = "TBC", ea_duty = true, ea_remains = 7,
        cp = 0 }).action, nil,
        "TBC: EA at 7 (outside 6) stays silent")
    eq(evaluate({ family = "FOREVER", ea_duty = true, ea_remains = 10,
        cp = 5 }).action, "expose",
        "FOREVER: EA at 10 (inside 16) refreshes at 5CP")
    eq(evaluate({ family = "FOREVER", ea_duty = true, ea_remains = 10,
        cp = 0 }).action, nil,
        "FOREVER: below 5CP the low bar runs the lockout (no any-CP expose)")
    eq(evaluate({ family = "FOREVER", ea_duty = true, ea_remains = 17,
        cp = 0 }).action, nil,
        "FOREVER: EA at 17 (outside 16) stays silent")
    eq(evaluate({ family = "ERA", ea_duty = true, ea_remains = 5,
        cp = 0 }).action, nil,
        "ERA: EA at 5 (outside 3) stays silent")

    -- Tea defaults per family (explicit input still wins).
    eq(evaluate({ family = "FOREVER", cp = 0, tea_ready = true,
        energy_now = 15 }).action, "tea",
        "FOREVER boundary: Tea at exactly 15 fires")
    eq(evaluate({ family = "FOREVER", cp = 0, tea_ready = true,
        energy_now = 16 }).hold_text, "POOL",
        "FOREVER: 16 with Tea ready still pools")
    eq(evaluate({ family = "ERA", cp = 0, tea_ready = true,
        energy_now = 29 }).action, "tea",
        "ERA boundary: Tea at exactly 29 fires")

    -- Sweaty override: ERA spends at 79+ with no tick; TBC pools below 71.
    eq(evaluate({ family = "ERA", cp = 0, energy_now = 79,
        energy_tick_in = NONE }).action, "builder",
        "ERA sweaty override: 79 with an unknown tick spends (E-G1)")
    eq(evaluate({ family = "ERA", cp = 0, energy_now = 78,
        energy_tick_in = NONE }).hold_text, "POOL",
        "ERA: 78 with an unknown tick still pools")
    eq(evaluate({ family = "TBC", cp = 0, energy_now = 78,
        energy_tick_in = NONE }).action, "builder",
        "TBC single line: 78 spends with no tick")

    -- Shiv gate: WRATH/FOREVER never Shiv, even Deadly-imminent.
    eq(evaluate({ family = "WRATH", shiv_ready = true, deadly_remaining = 1,
        deadly_stacks = 5, cp = 0, energy_now = 10 }).hold, true,
        "WRATH never Shivs (H7): a Deadly-imminent bar pools")
    eq(evaluate({ family = "FOREVER", shiv_ready = true, deadly_remaining = 1,
        deadly_stacks = 5, cp = 3, ttd = 30,
        rupture_remains = NONE }).action, "rupture",
        "FOREVER never Shivs (H7): the finisher fires instead")

    -- 5b/5c: AR/BF sit between the finisher and Tea, slot-less.
    eq(evaluate({ family = "TBC", cp = 0, energy_now = 40, ar_ready = true,
        ttd = 30 }).action, "ar",
        "rule 5b: TBC AR at 40 fires ahead of Tea/pool")
    eq(evaluate({ family = "TBC", cp = 0, energy_now = 40, ar_ready = true,
        tea_ready = true, ttd = 30 }).action, "ar",
        "rule 5b outranks Tea on the same deficit")
    eq(evaluate({ family = "TBC", cp = 5, ttd = 60, rupture_remains = NONE,
        energy_now = 40, ar_ready = true }).action, "rupture",
        "the planned finisher outranks AR")
    eq(evaluate({ family = "TBC", cp = 0, energy_now = 50, bf_ready = true,
        snd_remains = 10, ttd = 30 }).action, "bf",
        "rule 5c: BF behind SnD fires ahead of Tea/pool")
    eq(evaluate({ family = "TBC", cp = 0, energy_now = 10, bf_ready = true,
        snd_remains = 10, tea_ready = true, ttd = 30 }).action, "bf",
        "rule 5c outranks Tea")

    -- 5d: Cold Blood sits between BF and Tea, yields to the hold/lockout.
    eq(evaluate({ family = "TBC", cp = 4, energy_now = 50, ttd = 30,
        coldblood_ready = true, snd_usable = true, snd_remains = 20 }).action,
        "coldblood",
        "rule 5d: TBC Cold Blood with SnD fires ahead of Tea/pool")
    eq(evaluate({ family = "TBC", cp = 4, energy_now = 50, ttd = 30,
        coldblood_ready = true, bf_ready = true,
        snd_usable = true, snd_remains = 20 }).action, "bf",
        "rule 5c outranks Cold Blood")
    eq(evaluate({ family = "TBC", cp = 4, energy_now = 40, ttd = 30,
        coldblood_ready = true, ar_ready = true,
        snd_usable = true, snd_remains = 20 }).action, "ar",
        "rule 5b outranks Cold Blood")
    eq(evaluate({ family = "TBC", cp = 4, energy_now = 10, ttd = 30,
        coldblood_ready = true, tea_ready = true,
        snd_usable = true, snd_remains = 20 }).action, "coldblood",
        "rule 5d outranks Tea on the same deficit")
    eq(evaluate({ family = "TBC", cp = 5, energy_now = 50, ttd = 30,
        rupture_remains = NONE, coldblood_ready = true,
        snd_usable = true, snd_remains = 20 }).action, "rupture",
        "the planned finisher outranks Cold Blood")
    eq(evaluate({ family = "TBC", cp = 0, energy_now = 50,
        coldblood_ready = true, snd_remains = nil }).action, nil,
        "Cold Blood without SnD stays silent (falls to pool)")
end

-- H6 rule 1a + Forever lockout + the SOD latch through evaluate.
do
    -- 1a hold: 5CP + duty + EA in (6, 15) + SnD cover + low energy holds
    -- instead of the finisher (the sim's waitUntil).
    local held = evaluate({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50, ttd = 30 })
    eq(held.action, nil, "rule 1a: the wait holds instead of the Rupture finisher")
    eq(held.hold, true, "rule 1a: the wait holds")
    eq(held.hold_text, "POOL", "rule 1a: the wait reads POOL")
    -- The hold owns dying targets too (the sim waits at 5CP, never dumps).
    held = evaluate({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50, ttd = 5 })
    eq(held.action, nil, "rule 1a: the wait holds on a dying target (no dump)")
    eq(held.hold_text, "POOL", "rule 1a: the dying-target wait reads POOL")
    -- Pool-release: energy at the line casts Expose now.
    eq(evaluate({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 71, ttd = 30 }).action,
        "expose", "rule 1a: energy at 71 releases into Expose")
    -- SnD-short release beats the SnD rule (the sim group outranks SnD).
    eq(evaluate({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = nil, energy_now = 50, ttd = 30 }).action,
        "expose", "rule 1a: missing SnD releases into Expose (not snd)")
    eq(evaluate({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 5, energy_now = 50, ttd = 30 }).action,
        "expose", "rule 1a: short SnD releases into Expose")
    -- Unreadable SnD runs the old priority (no wait machinery).
    eq(evaluate({ ea_duty = true, ea_remains = 10, cp = 5,
        rupture_remains = NONE }).action, "rupture",
        "rule 1a: unreadable SnD falls through to the finisher")
    -- Off duty the window is inert (no default-visible change).
    eq(evaluate({ ea_duty = false, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50,
        ttd = 30 }).action, "eviscerate",
        "rule 1a: off duty the same bar Eviscerates (no wait)")
    -- Cooldown/consumable lines stay live during the wait (the sim ranks
    -- AR/Tea above the EA group).
    eq(evaluate({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 40, ar_ready = true,
        ttd = 30 }).action, "ar",
        "rule 1a: AR fires through the wait")
    eq(evaluate({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 20, tea_ready = true,
        ttd = 30 }).action, "tea",
        "rule 1a: Tea fires through the wait")

    -- Forever lockout: duty + low EA withholds snd/dump/planned below 5CP
    -- (the sim exposes at 5CP only and suppresses every other finisher);
    -- builders, AR, Tea and BF stay live exactly like the sim.
    local locked = evaluate({ family = "FOREVER", cp = 3, ea_duty = true,
        ea_remains = 10, snd_usable = true, snd_remains = nil, energy_now = 50,
        ttd = 30, rupture_remains = NONE })
    eq(locked.action, nil, "lockout: SnD + finisher yield below 5CP (no action)")
    eq(locked.hold_text, "POOL", "lockout: the bar pools behind the duty")
    locked = evaluate({ family = "FOREVER", cp = 3, ttd = 5, ea_duty = true,
        ea_remains = 10, energy_now = 50 })
    eq(locked.action, nil, "lockout: the 3CP fight-end dump is withheld")
    eq(locked.hold_text, "POOL", "lockout: the dying bar pools behind the duty")
    eq(evaluate({ family = "FOREVER", cp = 5, ea_duty = true, ea_remains = 10,
        energy_now = 50 }).action, "expose",
        "lockout: at 5CP rule 1 still exposes through the lockout")
    eq(evaluate({ family = "FOREVER", cp = 5, ea_duty = true, ea_remains = 17,
        snd_usable = true, snd_remains = nil, energy_now = 50, ttd = 30,
        rupture_remains = NONE }).action, "snd",
        "lockout: EA at 17 resumes the normal priority (snd)")
    eq(evaluate({ family = "FOREVER", cp = 3, ea_duty = false, ea_remains = 10,
        snd_usable = true, snd_remains = nil, energy_now = 50, ttd = 30,
        rupture_remains = NONE }).action, "snd",
        "lockout: off duty the same bar SnDs (no lockout)")

    -- SOD latch through evaluate: ERA + sod_envenom runs the primary table.
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 4, deadly_stacks = 1,
        ttd = 30, energy_now = 50 }).action, "envenom",
        "SOD latch: ERA + latch Envenoms at 4CP on a living target")
    eq(evaluate({ family = "ERA", cp = 4, deadly_stacks = 1,
        ttd = 30, energy_now = 50 }).action, nil,
        "SOD latch: ERA without the latch never Envenoms mid-fight")
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 2, deadly_stacks = 1,
        ttd = 3 }).action, "envenom",
        "SOD latch: 2CP on a dying target dumps Envenom")
    eq(evaluate({ family = "ERA", cp = 2, deadly_stacks = 1, ttd = 3 }).action,
        "eviscerate",
        "SOD latch: ERA without the latch Eviscerates the same dump")
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 3, deadly_stacks = 1,
        ttd = 30, energy_now = 50 }).action, nil,
        "SOD latch: 3CP on a living target is below the primary line")
    eq(evaluate({ family = "TBC", sod_envenom = true, cp = 4, deadly_stacks = 5,
        ttd = 30, energy_now = 50 }).action, nil,
        "SOD latch: off ERA the latch is ignored (TBC dying-only needs ttd)")

    -- SOD SnD rows through the latch (S-G1: 4+CP, <=1 s).
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 1,
        snd_usable = true, snd_remains = NONE,
        energy_now = 50, ttd = 30 }).action, nil,
        "SOD latch: 1CP never SnDs (the 4CP line)")
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 1,
        snd_usable = true, snd_remains = NONE,
        energy_now = 50, ttd = 30 }).hold_text, "POOL",
        "SOD latch: 1CP pools toward the 4CP SnD")
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 4,
        snd_usable = true, snd_remains = NONE,
        energy_now = 50, ttd = 30 }).action, "snd",
        "SOD latch: 4CP prompts SnD (S-G1)")
    eq(evaluate({ family = "ERA", cp = 1,
        snd_usable = true, snd_remains = NONE,
        energy_now = 50, ttd = 30 }).action, "snd",
        "SOD latch: Era-base keeps the 1CP SnD")

    -- SOD Tea through the latch (S-M1: 10, or 40 while ttd <= 15 s).
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 0,
        tea_ready = true, energy_now = 10, ttd = 30 }).action, "tea",
        "SOD latch: Tea at exactly 10 fires")
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 0,
        tea_ready = true, energy_now = 11, ttd = 30 }).hold_text, "POOL",
        "SOD latch: 11 on a living target pools")
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 0,
        tea_ready = true, energy_now = 30, ttd = 10 }).action, "tea",
        "SOD latch: 30 on a dying target Teas (fight-end 40)")
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 0,
        tea_ready = true, energy_now = 30, ttd = NONE }).hold_text, "POOL",
        "SOD latch: unknown TTD never guesses the fight-end (stays on 10)")
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 0,
        tea_ready = true, energy_now = 30, ttd = 10,
        tea_energy_max = 5 }).hold_text, "POOL",
        "SOD latch: an explicit line wins over the fight-end 40")
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 0,
        tea_ready = true, energy_now = 35, ttd = 30,
        tea_energy_max = 40 }).action, "tea",
        "SOD latch: an explicit 40 fires on its own line")

    -- Cold Blood through the frame: Forever lockout shadows it, the TBC
    -- wait holds it.
    eq(evaluate({ family = "FOREVER", cp = 5, ttd = NONE,
        rupture_remains = NONE, coldblood_ready = true,
        snd_usable = true, snd_remains = 20, energy_now = 50 }).action,
        "coldblood",
        "FOREVER: Cold Blood at 5CP fires (V-G5)")
    eq(evaluate({ family = "FOREVER", cp = 5, ea_duty = true, ea_remains = 10,
        coldblood_ready = true, snd_usable = true, snd_remains = 20,
        energy_now = 50 }).action, "expose",
        "lockout: rule 1 exposes through a ready Cold Blood (V-G5)")
    eq(evaluate({ ea_duty = true, ea_remains = 10, cp = 5,
        snd_usable = true, snd_remains = 20, energy_now = 50,
        coldblood_ready = true, ttd = 30 }).hold_text, "POOL",
        "rule 1a: the wait holds behind a ready Cold Blood")
end

-- Band overrides and the Wrath cap exception through evaluate.
do
    eq(evaluate({ pool_pre = 65, pool_post = 85, energy_now = 70,
        energy_tick_in = 1.0, cp = 0 }).action, "builder",
        "explicit band overrides drive the spend")
    eq(evaluate({ family = "WRATH", cp = 5, deadly_stacks = 5,
        envenom_buff_remains = 6, energy_now = 90, energy_tick_in = 1.0,
        ttd = 60, rupture_remains = 20 }).action, "envenom",
        "Wrath cap exception: capping energy chains Envenom through the buff")
end

-- Frozen fields, input immutability, nil-safety.
do
    local out = {
        action = "stale", hold = "stale", hold_text = "STALE", filler_slot = "stale",
        judge_slot = "stale", rotation_key = "stale", waiting_judgement = true,
        unknown = "stale",
    }
    rg.evaluate(inp({ cp = NONE }), out)
    eq(out.action, nil, "a reused out table has action overwritten")
    eq(out.hold, false, "a reused out table has hold overwritten")
    eq(out.hold_text, nil, "a reused out table has hold_text overwritten")
    eq(out.filler_slot, nil, "a reused out table has filler_slot overwritten")
    eq(out.judge_slot, nil, "a reused out table has judge_slot overwritten")
    eq(out.rotation_key, nil, "a reused out table has rotation_key overwritten")
    eq(out.waiting_judgement, false, "a reused out table has waiting_judgement overwritten")
    eq(out.unknown, true, "a reused out table has unknown overwritten")

    local ok, err = pcall(rg.evaluate)
    check(ok, "evaluate with no arguments does not error (" .. tostring(err) .. ")")
    ok, err = pcall(rg.evaluate, nil, nil)
    check(ok, "evaluate(nil, nil) does not error (" .. tostring(err) .. ")")
    local fallback = rg.evaluate(inp({ family = "ERA", cp = 1, ttd = 5 }))
    eq(fallback.action, "eviscerate", "evaluate can allocate its own out table")

    local frozen = inp({})
    local before_energy = frozen.energy_now
    rg.evaluate(frozen, {})
    eq(frozen.energy_now, before_energy, "evaluate never writes back into its inputs")
end

--=========================================================================================
-- 6) The Wrath sin upkeep (Hunger for Blood) and the practice-surface helpers
--=========================================================================================
-- The wowsims wotlk APL refreshes Hunger for Blood when its aura has <= 1 s
-- left (ui/rogue/apls/mutilate.apl.json: auraRemainingTime(51662) <= 1s ->
-- cast 51662 - fetched 2026-10-19). The rule sits right after the Slice and
-- Dice upkeep (the APL's own order), is WRATH-only, and follows the SnD nil
-- convention: a missing buff is an upkeep gap, an unreadable clock hides.
do
    check(type(rg.hfb_verdict) == "function", "the Hunger for Blood verdict is exported")
    eq(rg.HFB_REFRESH_BY_FAMILY.WRATH, 1, "the Hunger for Blood window is 1 s (the sim's line)")
    eq(rg.HFB_FAMILIES.WRATH, true, "Wrath plays the sin upkeep")
    eq(rg.HFB_FAMILIES.ERA, nil, "Era does not play the sin upkeep")
    eq(rg.HFB_FAMILIES.TBC, nil, "TBC does not play the sin upkeep")

    local args = { hfb_usable = true, hfb_remains = 0.5 }
    eq(rg.hfb_verdict("WRATH", args), "hfb", "a buff inside the window prompts the refresh")
    args = { hfb_usable = true, hfb_remains = 15 }
    eq(rg.hfb_verdict("WRATH", args), nil, "a healthy buff does not prompt")
    args = { hfb_usable = true, hfb_remains = 1 }
    eq(rg.hfb_verdict("WRATH", args), "hfb", "the tail boundary (<= 1 s) prompts")
    args = { hfb_usable = true, hfb_remains = nil }
    eq(rg.hfb_verdict("WRATH", args), "hfb", "a missing buff prompts (the SnD convention)")
    args = { hfb_usable = true, hfb_remains = 0 / 0 }
    eq(rg.hfb_verdict("WRATH", args), nil, "a NaN clock hides (H4)")
    args = { hfb_usable = nil, hfb_remains = 0 }
    eq(rg.hfb_verdict("WRATH", args), nil, "an unresolved spell never prompts")
    eq(rg.hfb_verdict("ERA", { hfb_usable = true, hfb_remains = 0 }), nil,
        "a family without the row never prompts")
    eq(rg.hfb_verdict(nil, { hfb_usable = true, hfb_remains = 0 }), nil,
        "an unknown family never prompts")
    local ok, err = pcall(rg.hfb_verdict, "WRATH", nil)
    check(ok, "the Hunger for Blood verdict is nil-safe (" .. tostring(err) .. ")")

    -- The rule order: SnD (1b) outranks Hunger for Blood (1c), and the upkeep
    -- outranks every spender.
    local out = evaluate({ family = "WRATH", cp = 2, snd_usable = true,
        snd_remains = nil, hfb_usable = true, hfb_remains = nil })
    eq(out.action, "snd", "rule 1b: Slice and Dice outranks the Hunger for Blood upkeep")
    out = evaluate({ family = "WRATH", cp = 2, snd_usable = true,
        snd_remains = 30, hfb_usable = true, hfb_remains = nil })
    eq(out.action, "hfb", "rule 1c: the Hunger for Blood upkeep fires when SnD rides")
    out = evaluate({ family = "WRATH", cp = 2, snd_usable = true,
        snd_remains = 30, hfb_usable = true, hfb_remains = 20 })
    eq(out.action, nil, "a healthy Hunger for Blood leaves the rotation alone")
    out = evaluate({ family = "ERA", cp = 2, snd_usable = true,
        snd_remains = 30, hfb_usable = true, hfb_remains = nil })
    eq(out.action, nil, "Era never plays the sin upkeep")
end

-- The practice-surface helpers: the per-CP SnD duration, the family floors and
-- the opener order. The values come from the engine's own tables, so a tuning
-- pass moves the drills and the guide together.
do
    check(type(rg.snd_duration_for_cp) == "function",
        "the per-CP Slice and Dice duration lookup is exported")
    eq(rg.snd_duration_for_cp(1), 9, "1 CP SnD lasts 9 s (the sourced row)")
    eq(rg.snd_duration_for_cp(5), 21, "5 CP SnD lasts 21 s (the sourced row)")
    eq(rg.snd_duration_for_cp(0), nil, "0 CP has no sourced row (never interpolated)")
    eq(rg.snd_duration_for_cp(6), nil, "6 CP has no sourced row (never interpolated)")
    eq(rg.snd_duration_for_cp(nil), nil, "a nil CP reads nil")
    eq(rg.snd_duration_for_cp(0 / 0), nil, "a NaN CP reads nil")

    check(type(rg.family_floors) == "function", "the family-floor accessor is exported")
    local floors = rg.family_floors("ERA")
    eq(floors.finisher_min_cp, 5, "the Era planned-finisher floor is 5 CP")
    eq(floors.dump_min_cp, 1, "the Era dump floor is any CP")
    eq(floors.min_ttd, 8, "the Era finisher TTD floor is 8 s")
    floors = rg.family_floors("WRATH")
    eq(floors.finisher_min_cp, 4, "the Wrath planned-finisher floor is 4 CP")
    eq(floors.dump_min_cp, 4, "the Wrath dump floor is 4 CP")
    eq(floors.min_ttd, 4, "the Wrath finisher TTD floor is 4 s")
    floors = rg.family_floors("FOREVER")
    eq(floors.finisher_min_cp, 3, "the Forever planned-finisher floor is 3 CP")
    floors = rg.family_floors("BOGUS")
    eq(floors.finisher_min_cp, nil, "an unknown family has no floor (never guessed)")

    check(type(rg.opener_rank) == "function", "the opener-rank lookup is exported")
    eq(rg.opener_rank("snd"), 3, "the Slice and Dice upkeep sits third in the opener order")
    eq(rg.opener_rank("eviscerate"), rg.opener_rank("rupture"),
        "the two finishers share the finisher rank")
    check(rg.opener_rank("snd") < rg.opener_rank("builder"),
        "the upkeep outranks the builder in the opener order")
    eq(rg.opener_rank("tea"), nil, "an action outside the opener order has no rank")
    eq(rg.opener_rank(nil), nil, "a nil action has no rank")
    eq(rg.PREPULL_FAMILIES.TBC, true, "the TBC sim carries the prepull cooldown")
    eq(rg.PREPULL_FAMILIES.ERA, nil, "the Era sim has no prepull cooldown row")
    eq(rg.PREPULL_LEAD_SECONDS, 1, "the prepull lead is 1 s (the sim's -1s)")
    eq(rg.GCD_SECONDS, 1.5, "the GCD is the addon's 1.5 s client floor")
end

-- The practice surface: the ctx contract and the pure graders.
-- The class module owns the rotation TABLE; the decisions live here, so the whole
-- path is testable in the strict sandbox (no WoW API, no clock).
do
    check(type(rg.build_practice_inputs) == "function",
        "the practice input builder is exported")
    check(type(rg.practice_expected) == "function", "the practice verdict is exported")
    check(type(rg.practice_step) == "function", "the practice step is exported")
    check(type(rg.practice_reason) == "function", "the practice reason is exported")
    check(type(rg.get_practice_pick) == "function", "the practice pick reader is exported")
    check(type(rg.grade_finisher_order) == "function", "the finisher-order grader is exported")
    check(type(rg.grade_cp_finish) == "function", "the combo-point grader is exported")
    check(type(rg.grade_snd_upkeep) == "function", "the debuff-upkeep grader is exported")
    check(type(rg.grade_opener) == "function", "the opener grader is exported")

    -- The ctx contract: the resources carry the engine's own input names, the
    -- cooldowns prove a readiness, and a missing read stays nil.
    local ctx = {
        now = 100,
        last_action = "builder",
        resources = { energy_now = 50, cp = 5, ttd = 30, family = "ERA" },
        cooldowns = { ar = 0, bf = 12 },
    }
    local inputs = rg.build_practice_inputs(ctx, {})
    eq(inputs.energy_now, 50, "the input builder reads the energy")
    eq(inputs.cp, 5, "the input builder reads the combo points")
    eq(inputs.ttd, 30, "the input builder reads the time to die")
    eq(inputs.family, "ERA", "the input builder reads the family")
    eq(inputs.ar_ready, true, "a cooldown row at 0 proves the readiness")
    eq(inputs.bf_ready, nil, "a running cooldown never proves the readiness")
    eq(inputs.snd_usable, nil, "a missing upkeep read stays nil (unknown-hides)")
    -- A readiness the state bag already proves is never cleared by the cooldown
    -- pass (the bag is the richer read).
    local bag_ready = rg.build_practice_inputs({
        resources = { ar_ready = true, cp = 1, family = "ERA" },
    }, {})
    eq(bag_ready.ar_ready, true, "the state bag's readiness survives the cooldown pass")
    local bag_ready_cd = rg.build_practice_inputs({
        resources = { ar_ready = true, cp = 1, family = "ERA" },
        cooldowns = { ar = 12 },
    }, {})
    eq(bag_ready_cd.ar_ready, true,
        "a running cooldown never clears a readiness the state bag proves")
    -- A reused table never keeps a stale value.
    local reused = { ar_ready = true, snd_remains = 12 }
    rg.build_practice_inputs(ctx, reused)
    eq(reused.snd_remains, nil, "the input builder clears the fields it owns")
    eq(reused.ar_ready, true, "the input builder rewrites the readiness it owns")

    -- The pick reader accepts the contract's name and its aliases.
    eq(rg.get_practice_pick({ last_action = "snd" }), "snd", "the pick reads last_action")
    eq(rg.get_practice_pick({ action = "snd" }), "snd", "the pick reads the action alias")
    eq(rg.get_practice_pick({ pick = "snd" }), "snd", "the pick reads the pick alias")
    eq(rg.get_practice_pick({ pressed = "snd" }), "snd", "the pick reads the pressed alias")
    eq(rg.get_practice_pick({ choice = "snd" }), "snd", "the pick reads the choice alias")
    eq(rg.get_practice_pick({}), nil, "no pick reads nil")
    eq(rg.get_practice_pick(nil), nil, "no ctx reads nil")

    -- The step: the engine's decision, and nil for everything undecidable.
    local step = rg.practice_step(ctx)
    check(type(step) == "table", "the step answers a known state")
    eq(step and step.action, "eviscerate", "the Era step wants Eviscerate")
    check(type(step and step.reason) == "string" and step.reason ~= "",
        "the step carries a short reason")
    eq(rg.practice_step({ resources = { energy_now = 40, cp = 0, family = "ERA" } }), nil,
        "a POOL step is a hold, so the step is unknown")
    eq(rg.practice_step({ resources = { cp = 5, family = "ERA" } }), nil,
        "an unreadable energy read makes the step unknown")
    eq(rg.practice_step(nil), nil, "a missing ctx makes the step unknown")
end

-- The drill graders (the practice audit's section C).
do
    local function ctx_for(overrides)
        local t = {
            now = 100,
            last_action = "eviscerate",
            resources = { energy_now = 50, cp = 5, ttd = 30, family = "ERA" },
        }
        for k, v in pairs(overrides or {}) do
            if k == "resources" then
                for rk, rv in pairs(v) do
                    if rv == NONE then
                        t.resources[rk] = nil
                    else
                        t.resources[rk] = rv
                    end
                end
            elseif v == NONE then
                t[k] = nil
            else
                t[k] = v
            end
        end
        return t
    end

    -- D-R1: the priority order.
    eq(rg.grade_finisher_order(ctx_for()), "S", "the right pick grades S")
    eq(rg.grade_finisher_order(ctx_for({ last_action = "rupture" })), "F",
        "the wrong Era finisher is a mis-pick (F)")
    eq(rg.grade_finisher_order(ctx_for({ resources = { cp = 0 } })), nil,
        "a state with nothing due grades nothing")
    eq(rg.grade_finisher_order(ctx_for({ resources = { energy_now = 40, cp = 0 } })), nil,
        "a POOL state grades nothing (the engine grades a hold unknown)")
    eq(rg.grade_finisher_order(ctx_for({ last_action = NONE })), nil,
        "no cast grades nothing")

    -- D-R2: the combo-point decision.
    eq(rg.grade_cp_finish(ctx_for()), "S", "the finisher at the floor with the right finisher is S")
    eq(rg.grade_cp_finish(ctx_for({ resources = { cp = 4 } })), "A", "one CP short is A")
    eq(rg.grade_cp_finish(ctx_for({ resources = { cp = 3 } })), "B", "two CP short is B")
    eq(rg.grade_cp_finish(ctx_for({ resources = { cp = 2 } })), "F",
        "below the floor on a healthy target wastes the CP (F)")
    eq(rg.grade_cp_finish(ctx_for({ last_action = "rupture" })), "C",
        "the right CP with the wrong finisher is C")
    eq(rg.grade_cp_finish(ctx_for({ resources = { cp = 0, ttd = 5 } })), "D",
        "below the floor on a dying target is forgiven (D)")
    eq(rg.grade_cp_finish(ctx_for({ last_action = "builder" })), nil,
        "a builder cast is not a combo-point decision")
    eq(rg.grade_cp_finish(ctx_for({ resources = { cp = NONE } })), nil,
        "an unreadable combo-point read grades nothing")
    eq(rg.grade_cp_finish(ctx_for({ resources = { energy_now = NONE } })), nil,
        "an unreadable energy read grades nothing (the state is unknown)")

    -- D-R3: the debuff upkeep.
    eq(rg.grade_snd_upkeep(ctx_for({ last_action = "snd",
        resources = { cp = 3, snd_remains = 12 } })), "S",
        "a refresh while the debuff is up is S")
    eq(rg.grade_snd_upkeep(ctx_for({ last_action = "snd",
        resources = { cp = 3, snd_remains = 0 } })), "C",
        "a refresh at the expiry grades the expired debuff (C)")
    eq(rg.grade_snd_upkeep(ctx_for({ last_action = "snd",
        resources = { cp = 3, snd_late_by = 1.5 } })), "A",
        "a refresh one tick late is A")
    eq(rg.grade_snd_upkeep(ctx_for({ last_action = "snd",
        resources = { cp = 3, snd_late_by = 3 } })), "B",
        "a refresh two ticks late is B")
    eq(rg.grade_snd_upkeep(ctx_for({ last_action = "snd",
        resources = { cp = 3, snd_late_by = 30 } })), "F",
        "a refresh after the debuff's own length is never maintained (F)")
    eq(rg.grade_snd_upkeep(ctx_for({ last_action = "builder",
        resources = { cp = 3, snd_late_by = 1 } })), "D",
        "the builder pressed over the window is D")
    eq(rg.grade_snd_upkeep(ctx_for({ last_action = "snd",
        resources = { cp = 3 } })), nil, "no clock grades the upkeep nothing")
    eq(rg.grade_snd_upkeep(ctx_for({ last_action = "builder",
        resources = { cp = 3, snd_remains = 12 } })), nil,
        "a builder cast with a healthy debuff is not an upkeep event")

    -- D-R4: the opener.
    local function opener_ctx(now, pick)
        local c = ctx_for({ last_action = pick })
        c.now = now
        c.resources.pull_at = 100
        return c
    end
    eq(rg.grade_opener(opener_ctx(101.5, "eviscerate")), "S", "the opener step on time is S")
    eq(rg.grade_opener(opener_ctx(103.0, "eviscerate")), "A", "one GCD late is A")
    eq(rg.grade_opener(opener_ctx(104.5, "eviscerate")), "B", "two GCDs late is B")
    eq(rg.grade_opener(opener_ctx(106.0, "eviscerate")), "C", "three GCDs late is C")
    eq(rg.grade_opener(opener_ctx(110.0, "eviscerate")), "D",
        "a badly late opener step is D (the opener was missed)")
    eq(rg.grade_opener(opener_ctx(101.5, "builder")), "D",
        "skipping the due step is D")
    eq(rg.grade_opener(opener_ctx(101.5, "tea")), "F",
        "an action outside the opener order is F")
    local no_clock = ctx_for({ last_action = "eviscerate" })
    eq(rg.grade_opener(no_clock), nil, "no pull clock grades the opener nothing")

    -- The prepull step: the sim's TBC Adrenaline Rush at -1 s (the state bag
    -- proves the cooldown is ready).
    local prepull = ctx_for({ last_action = "ar" })
    prepull.now = 99
    prepull.resources.family = "TBC"
    prepull.resources.ar_ready = true
    prepull.resources.pull_at = 100
    eq(rg.grade_opener(prepull), "S",
        "the prepull cooldown on the sim's -1 s mark grades S")
    local prepull_late = ctx_for({ last_action = "ar" })
    prepull_late.now = 99.5
    prepull_late.resources.family = "TBC"
    prepull_late.resources.ar_ready = true
    prepull_late.resources.pull_at = 100
    eq(rg.grade_opener(prepull_late), "A", "a late prepull is A")
    local no_prepull = ctx_for({ last_action = "ar" })
    no_prepull.now = 99
    no_prepull.resources.family = "TBC"
    no_prepull.resources.pull_at = 100
    eq(rg.grade_opener(no_prepull), "F",
        "without the proven cooldown the prepull is not the expected step (wrong order)")
end

--=========================================================================================
-- The APL utility layer: the arms for the rotation table's utility rows
--=========================================================================================
-- bench/rotation_gap_vs_apl_2026-10-20.md §3 (the rogue) is the INPUT; every
-- condition below was re-read from the APL files themselves on 2026-10-20
-- (wowsims/{sod,forever,wotlk}/master) and the ids named against the sims' own
-- spell data.
do
    check(type(rg.vanish_verdict) == "function", "the Vanish verdict is exported")
    check(type(rg.forever_opener_verdict) == "function",
        "the Forever opener cluster verdict is exported")
    check(type(rg.premeditation_verdict) == "function",
        "the Premeditation verdict is exported")
    check(type(rg.venom_verdict) == "function", "the Venom verdict is exported")
    check(type(rg.poisoned_knife_verdict) == "function",
        "the Poisoned Knife verdict is exported")
    check(type(rg.tricks_verdict) == "function",
        "the Tricks of the Trade verdict is exported")
    check(type(rg.killing_spree_verdict) == "function",
        "the Killing Spree verdict is exported")
    check(type(rg.forever_paired_pop_verdict) == "function",
        "the Forever paired-pop verdict is exported")

    -- The family gates: the Era and TBC APLs carry no Vanish row at all.
    eq(rg.VANISH_FAMILIES.SOD, true, "the SoD carries the Vanish row")
    eq(rg.VANISH_FAMILIES.WRATH, true, "the WotLK carries the Vanish row")
    eq(rg.VANISH_FAMILIES.FOREVER, true, "the Forever client carries the Vanish row")
    eq(rg.VANISH_FAMILIES.ERA, nil, "the Era APL carries no Vanish row")
    eq(rg.VANISH_FAMILIES.TBC, nil, "the TBC APL carries no Vanish row")
    eq(rg.POISONED_KNIFE_FAMILIES.SOD, true, "the SoD carries the Poisoned Knife row")
    eq(rg.POISONED_KNIFE_FAMILIES.ERA, nil, "the Era APL carries no Poisoned Knife row")
    eq(rg.PREMEDITATION_FAMILIES.FOREVER, true, "the Forever client carries the Premeditation row")
    eq(rg.PREMEDITATION_FAMILIES.ERA, nil, "the Era APL carries no Premeditation row")
    eq(rg.VENOM_FAMILIES.FOREVER, true, "the Forever client carries the Venom row")
    eq(rg.VENOM_FAMILIES.ERA, nil, "the Era APL carries no Venom row")
    eq(rg.TRICKS_FAMILIES.WRATH, true, "the WotLK carries the Tricks row")
    eq(rg.TRICKS_FAMILIES.FOREVER, nil, "the Forever APL carries no Tricks row")
    eq(rg.KILLING_SPREE_FAMILIES.WRATH, true, "the WotLK carries the Killing Spree row")
    eq(rg.GNOME_EUREKA_FAMILIES.FOREVER, true, "the Forever client carries the Eureka! row")
    eq(rg.GNOME_EUREKA_FAMILIES.ERA, nil, "the Eureka! row is Forever-only")
    -- The Hypersharp row has NO arm: its spell (54758) is the Engineering belt
    -- enchant's effect, not a spell the rogue casts (classes/rogue.lua's
    -- rotation table keeps the row as its citation).
    eq(rg.hypersharp_verdict, nil, "the Hypersharp row has no arm (nothing to ask for)")
    eq(rg.HYPERSHARP_FAMILIES, nil, "the Hypersharp row has no family gate")
    eq(rg.FOREVER_OPENER_FAMILIES.FOREVER, true, "the Forever client carries the opener cluster")
    eq(rg.FOREVER_OPENER_FAMILIES.ERA, nil, "the opener cluster is Forever-only")

    -- The Vanish verdict (the SoD's Vanish -> Envenom opener and the WotLK's
    -- Vanish pop).
    eq(rg.vanish_verdict("SOD", { vanish_ready = true, cp = 5,
        master_of_subtlety_active = false, envenom_ready = true }), "vanish",
        "SoD: 5CP with Envenom castable and the rune aura down fires")
    eq(rg.vanish_verdict("SOD", { vanish_ready = true, cp = 5,
        master_of_subtlety_active = true, envenom_ready = true }), nil,
        "SoD: the Master of Subtlety aura withholds the Vanish")
    eq(rg.vanish_verdict("SOD", { vanish_ready = true, cp = 4,
        master_of_subtlety_active = false, envenom_ready = true }), nil,
        "SoD: only 5CP opens")
    eq(rg.vanish_verdict("SOD", { vanish_ready = true, cp = 5,
        master_of_subtlety_active = false }), nil,
        "SoD: an unreadable Envenom readiness never opens")
    eq(rg.vanish_verdict("SOD", { cp = 5, master_of_subtlety_active = false,
        envenom_ready = true }), nil,
        "SoD: an unproven Vanish readiness never opens")
    eq(rg.vanish_verdict("WRATH", { vanish_ready = true, vanished_active = false }),
        "vanish", "WotLK: a ready Vanish fires while the 58426 aura is down")
    eq(rg.vanish_verdict("WRATH", { vanish_ready = true, vanished_active = true }),
        nil, "WotLK: the 58426 aura withholds the Vanish")
    eq(rg.vanish_verdict("WRATH", { vanish_ready = true }), "vanish",
        "WotLK: an absent 58426 aura reads as down")
    eq(rg.vanish_verdict("ERA", { vanish_ready = true }), nil,
        "the Era APL has no Vanish row")
    eq(rg.vanish_verdict("TBC", { vanish_ready = true }), nil,
        "the TBC APL has no Vanish row")
    eq(rg.vanish_verdict("FOREVER", { vanish_ready = true }), nil,
        "the Forever Vanish row rides the opener cluster, not this arm")

    -- The Forever opener cluster (the APL's i=1 / i=2 / i=5 rows).
    eq(rg.forever_opener_verdict("FOREVER", { cp = 3, ambush_ready = true,
        ambush_cue_active = true }), "ambush",
        "FOREVER: the Ambush cue with cp < 5 fires")
    eq(rg.forever_opener_verdict("FOREVER", { cp = 5, ambush_ready = true,
        ambush_cue_active = true }), nil,
        "FOREVER: the Ambush cue needs cp < 5")
    eq(rg.forever_opener_verdict("FOREVER", { cp = 3, ambush_ready = true,
        ambush_cue_active = false, garrote_ready = true,
        garrote_dot_active = false }), "garrote",
        "FOREVER: the Garrote row fires while its dot is down")
    eq(rg.forever_opener_verdict("FOREVER", { cp = 3, ambush_ready = true,
        ambush_cue_active = false, garrote_ready = true,
        garrote_dot_active = true }), nil,
        "FOREVER: the Garrote dot withholds the Garrote row")
    eq(rg.forever_opener_verdict("FOREVER", { cp = 3, preparation_ready = true,
        vanish_cd_remaining = 60 }), "preparation",
        "FOREVER: Preparation fires while Vanish is on cooldown")
    eq(rg.forever_opener_verdict("FOREVER", { cp = 3, preparation_ready = true }),
        nil, "FOREVER: an unreadable Vanish cooldown never preps")
    eq(rg.forever_opener_verdict("FOREVER", { cp = 3, preparation_ready = true,
        vanish_cd_remaining = 0 }), nil,
        "FOREVER: a ready Vanish never preps")
    -- The Vanish row (i=3): the Garrote dot down, the energy at/above the
    -- Garrote's CURRENT cost, cp < 5 and the Slice and Dice not about to fall.
    local forever_vanish = {
        cp = 3, vanish_ready = true, garrote_dot_active = false,
        garrote_energy_cost = 45, energy_now = 60, snd_remains = 20,
    }
    eq(rg.forever_opener_verdict("FOREVER", forever_vanish), "vanish",
        "FOREVER: the Vanish row fires with the energy covering the Garrote")
    eq(rg.forever_opener_verdict("FOREVER", { cp = 3, vanish_ready = true,
        garrote_dot_active = false, garrote_energy_cost = 45, energy_now = 44,
        snd_remains = 20 }), nil,
        "FOREVER: the energy must cover the Garrote's cost")
    eq(rg.forever_opener_verdict("FOREVER", { cp = 3, vanish_ready = true,
        garrote_dot_active = false, energy_now = 60, snd_remains = 20 }), nil,
        "FOREVER: an unreadable Garrote cost never fires the Vanish row")
    eq(rg.forever_opener_verdict("FOREVER", { cp = 3, vanish_ready = true,
        garrote_dot_active = false, garrote_energy_cost = 45, energy_now = 60,
        snd_remains = 2 }), nil,
        "FOREVER: the Slice and Dice about to fall withholds the Vanish row")
    eq(rg.forever_opener_verdict("FOREVER", { cp = 3, vanish_ready = true,
        garrote_dot_active = false, garrote_energy_cost = 45, energy_now = 60 }),
        nil,
        "FOREVER: an unreadable Slice and Dice clock never fires the Vanish row")
    eq(rg.forever_opener_verdict("FOREVER", { cp = 5, vanish_ready = true,
        garrote_dot_active = false, garrote_energy_cost = 45, energy_now = 60,
        snd_remains = 20 }), nil,
        "FOREVER: the Vanish row needs cp < 5")
    eq(rg.forever_opener_verdict("FOREVER", { cp = 3, vanish_ready = true,
        garrote_dot_active = true, garrote_energy_cost = 45, energy_now = 60,
        snd_remains = 20 }), nil,
        "FOREVER: the Garrote dot withholds the Vanish row")
    eq(rg.forever_opener_verdict("ERA", { cp = 3, vanish_ready = true,
        garrote_dot_active = false, garrote_energy_cost = 45, energy_now = 60,
        snd_remains = 20 }), nil,
        "the opener cluster is Forever-only")
    eq(rg.forever_opener_verdict("ERA", { cp = 3, ambush_ready = true,
        ambush_cue_active = true }), nil,
        "the opener cluster is Forever-only")

    -- The Premeditation and Venom verdicts.
    eq(rg.premeditation_verdict("FOREVER", { premeditation_ready = true, cp = 3 }),
        "premeditation", "FOREVER: Premeditation fires at cp <= 3")
    eq(rg.premeditation_verdict("FOREVER", { premeditation_ready = true, cp = 4 }),
        nil, "FOREVER: Premeditation waits above 3CP")
    eq(rg.premeditation_verdict("FOREVER", { cp = 1 }), nil,
        "FOREVER: an unproven Premeditation readiness never fires")
    eq(rg.venom_verdict("FOREVER", { venom_ready = true, venom_buff_active = false,
        cp = 3 }), "venom", "FOREVER: the Venom row fires at 3CP with the buff down")
    eq(rg.venom_verdict("FOREVER", { venom_ready = true, venom_buff_active = true,
        cp = 3 }), nil, "FOREVER: the Venom buff withholds the Venom row")
    eq(rg.venom_verdict("FOREVER", { venom_ready = true, venom_buff_active = false,
        cp = 2 }), nil, "FOREVER: the Venom row needs 3CP")

    -- The Poisoned Knife verdict (the SoD's 4-stack Deadly Poison window).
    eq(rg.poisoned_knife_verdict("SOD", { poisoned_knife_ready = true,
        deadly_stacks = 4, cp = 4, energy_now = 80 }), "poisoned_knife",
        "SoD: 4 stacks under 5CP and energy <= 80 fires")
    eq(rg.poisoned_knife_verdict("SOD", { poisoned_knife_ready = true,
        deadly_stacks = 3, cp = 4, energy_now = 80 }), nil,
        "SoD: fewer than 4 stacks never fires")
    eq(rg.poisoned_knife_verdict("SOD", { poisoned_knife_ready = true,
        deadly_stacks = 4, cp = 5, energy_now = 80 }), nil,
        "SoD: 5CP never fires the window")
    eq(rg.poisoned_knife_verdict("SOD", { poisoned_knife_ready = true,
        deadly_stacks = 4, cp = 4, energy_now = 81 }), nil,
        "SoD: above 80 energy never fires the window")
    eq(rg.poisoned_knife_verdict("ERA", { poisoned_knife_ready = true,
        deadly_stacks = 4, cp = 4, energy_now = 80 }), nil,
        "the Poisoned Knife row is SoD-only")

    -- The WotLK pops.
    eq(rg.tricks_verdict("WRATH", { tricks_ready = true, energy_now = 50 }),
        "tricks_of_the_trade", "WotLK: Tricks fires at energy <= 50")
    eq(rg.tricks_verdict("WRATH", { tricks_ready = true, energy_now = 51 }), nil,
        "WotLK: Tricks waits above 50 energy")
    eq(rg.tricks_verdict("WRATH", { energy_now = 10 }), nil,
        "WotLK: an unproven Tricks readiness never fires")
    eq(rg.killing_spree_verdict("WRATH", { killing_spree_ready = true,
        energy_now = 50 }), "killing_spree", "WotLK: Killing Spree fires at energy <= 50")
    eq(rg.killing_spree_verdict("WRATH", { killing_spree_ready = true,
        energy_now = 51 }), nil, "WotLK: Killing Spree waits above 50 energy")

    -- The Eureka! verdict (the Forever APL's i=13): the racial is known and off
    -- cooldown AND one of the three readable disjuncts holds.
    eq(rg.gnome_eureka_verdict("FOREVER", { gnome_eureka_ready = true,
        ar_known = false }), "gnome_eureka",
        "FOREVER: an unknown Adrenaline Rush fires the racial")
    eq(rg.gnome_eureka_verdict("FOREVER", { gnome_eureka_ready = true,
        ar_known = true, ar_buff_active = true }), "gnome_eureka",
        "FOREVER: the Adrenaline Rush's buff riding fires the racial")
    eq(rg.gnome_eureka_verdict("FOREVER", { gnome_eureka_ready = true,
        ar_known = true, ar_buff_active = false, ar_cd_remaining = 200,
        gnome_eureka_full_cd = 120 }), "gnome_eureka",
        "FOREVER: the Adrenaline Rush outlasting the racial fires it")
    eq(rg.gnome_eureka_verdict("FOREVER", { gnome_eureka_ready = true,
        ar_known = true, ar_buff_active = false, ar_cd_remaining = 120,
        gnome_eureka_full_cd = 120 }), nil,
        "FOREVER: an equal Adrenaline Rush cooldown never fires the racial")
    eq(rg.gnome_eureka_verdict("FOREVER", { gnome_eureka_ready = true,
        ar_known = true, ar_buff_active = false, ar_cd_remaining = 200 }), nil,
        "FOREVER: an unreadable racial cooldown never fires it")
    eq(rg.gnome_eureka_verdict("FOREVER", { ar_known = false }), nil,
        "FOREVER: an unproven racial readiness never fires")
    eq(rg.gnome_eureka_verdict("ERA", { gnome_eureka_ready = true,
        ar_known = false }), nil,
        "the Eureka! row is Forever-only")

    -- The Forever paired pops (the APL's 1.9 m Adrenaline Rush gate).
    eq(rg.FOREVER_PAIRED_POP_AR_CD, 114, "the paired-pop gate is 1.9 m")
    eq(rg.forever_paired_pop_verdict("FOREVER", { blood_fury_ready = true,
        ar_cd_remaining = 114 }, "blood_fury_ready", "blood_fury"), "blood_fury",
        "FOREVER: Blood Fury fires with the Adrenaline Rush 1.9 m out")
    eq(rg.forever_paired_pop_verdict("FOREVER", { blood_fury_ready = true,
        ar_cd_remaining = 113 }, "blood_fury_ready", "blood_fury"), nil,
        "FOREVER: Blood Fury waits while the Adrenaline Rush is nearly ready")
    eq(rg.forever_paired_pop_verdict("FOREVER", { blood_fury_ready = true },
        "blood_fury_ready", "blood_fury"), nil,
        "FOREVER: an unreadable Adrenaline Rush cooldown never pops")
    eq(rg.forever_paired_pop_verdict("FOREVER", { elunes_light_ready = true,
        ar_cd_remaining = 120 }, "elunes_light_ready", "elunes_light"), "elunes_light",
        "FOREVER: Elune's Light fires with the same gate")
    eq(rg.forever_paired_pop_verdict("ERA", { blood_fury_ready = true,
        ar_cd_remaining = 120 }, "blood_fury_ready", "blood_fury"), nil,
        "the paired pops are Forever-only")
end

-- The utility arms inside the rule order (the engine's own evaluate): the
-- cluster rides above the Slice and Dice upkeep, the stealth opener behind it.
do
    eq(evaluate({ family = "FOREVER", cp = 3, ambush_ready = true,
        ambush_cue_active = true, snd_usable = true, snd_remains = NONE,
        energy_now = 50, ttd = 30 }).action, "ambush",
        "FOREVER: the opener cluster rides above the SnD upkeep")
    eq(evaluate({ family = "FOREVER", cp = 5, ambush_ready = true,
        ambush_cue_active = true, snd_usable = true, snd_remains = NONE,
        energy_now = 50, ttd = 30 }).action, "snd",
        "FOREVER: at 5CP the SnD upkeep owns the step")
    eq(evaluate({ family = "FOREVER", cp = 3, preparation_ready = true,
        vanish_cd_remaining = 60, snd_usable = true, snd_remains = NONE,
        energy_now = 50, ttd = 30 }).action, "preparation",
        "FOREVER: the Preparation row rides in the opener cluster")
    eq(evaluate({ family = "ERA", sod_envenom = true, cp = 5, vanish_ready = true,
        master_of_subtlety_active = false, envenom_ready = true,
        snd_usable = true, snd_remains = 20, energy_now = 50, ttd = 30 }).action,
        "vanish",
        "SoD: the Vanish opener rides behind the SnD upkeep")
    local mos = evaluate({ family = "ERA", sod_envenom = true, cp = 5,
        vanish_ready = true, master_of_subtlety_active = true, envenom_ready = true,
        snd_usable = true, snd_remains = 20, energy_now = 50, ttd = 30 })
    check(mos.action ~= "vanish",
        "SoD: the Master of Subtlety aura withholds the Vanish")
    eq(evaluate({ family = "WRATH", cp = 0, tricks_ready = true,
        energy_now = 40, ttd = 30 }).action, "tricks_of_the_trade",
        "WotLK: the Tricks pop rides with the cooldown cluster")
    eq(evaluate({ family = "WRATH", cp = 0, tricks_ready = true,
        energy_now = 60, ttd = 30 }).action, nil,
        "WotLK: above 50 energy the Tricks pop stays quiet")
    eq(evaluate({ family = "FOREVER", cp = 0, blood_fury_ready = true,
        ar_cd_remaining = 120, energy_now = 50, ttd = 30 }).action, "blood_fury",
        "FOREVER: the paired pop rides with the cooldown cluster")
    eq(evaluate({ family = "FOREVER", cp = 3, venom_ready = true,
        venom_buff_active = false, energy_now = 50, ttd = 30 }).action, "venom",
        "FOREVER: the Venom row rides above the planned finisher")
    eq(evaluate({ family = "FOREVER", cp = 3, vanish_ready = true,
        garrote_dot_active = false, garrote_energy_cost = 45, energy_now = 60,
        snd_remains = 20, snd_usable = true, ttd = 30 }).action, "vanish",
        "FOREVER: the Vanish opener rides in the opener cluster")
    eq(evaluate({ family = "FOREVER", cp = 0, gnome_eureka_ready = true,
        ar_known = true, ar_buff_active = true, energy_now = 50,
        ttd = 30 }).action, "gnome_eureka",
        "FOREVER: the Eureka! racial rides with the cooldown cluster")
end

-- The practice surface carries the utility layer's input names (the ctx feeds
-- the arms the same way it feeds the shipped rows).
do
    local fields = {}
    for i = 1, #rg.PRACTICE_RESOURCE_FIELDS do
        fields[rg.PRACTICE_RESOURCE_FIELDS[i]] = true
    end
    for _, name in ipairs({ "vanish_ready", "master_of_subtlety_active",
        "vanished_active", "vanish_cd_remaining", "ambush_ready",
        "ambush_cue_active", "garrote_ready", "garrote_dot_active",
        "garrote_energy_cost", "preparation_ready", "premeditation_ready",
        "venom_ready", "venom_buff_active", "blood_fury_ready",
        "elunes_light_ready", "ar_cd_remaining", "ar_known", "ar_buff_active",
        "gnome_eureka_ready", "gnome_eureka_full_cd", "poisoned_knife_ready",
        "tricks_ready", "killing_spree_ready", "envenom_ready" }) do
        check(fields[name] == true, "the practice ctx carries the " .. name .. " input")
    end
    local flags = {}
    for i = 1, #rg.PRACTICE_COOLDOWN_FIELDS do
        flags[rg.PRACTICE_COOLDOWN_FIELDS[i][2]] = true
    end
    for _, name in ipairs({ "vanish_ready", "ambush_ready", "garrote_ready",
        "preparation_ready", "premeditation_ready", "venom_ready",
        "blood_fury_ready", "elunes_light_ready", "gnome_eureka_ready",
        "poisoned_knife_ready", "tricks_ready", "killing_spree_ready",
        "envenom_ready" }) do
        check(flags[name] == true, "the practice ctx proves the " .. name .. " readiness")
    end
    -- The opener drill's pre-pull row (the class publishes the APL's
    -- prepullActions table; the ctx names the family's first ready cast row).
    local function drill_ctx(overrides)
        local t = {
            now = 100,
            last_action = "eviscerate",
            resources = { energy_now = 50, cp = 5, ttd = 30, family = "ERA" },
        }
        for k, v in pairs(overrides or {}) do
            if k == "resources" then
                for rk, rv in pairs(v) do
                    t.resources[rk] = rv
                end
            else
                t[k] = v
            end
        end
        return t
    end
    local prepull_ctx = drill_ctx({ last_action = "blood_fury", now = 98,
        resources = { family = "FOREVER", blood_fury_ready = true, pull_at = 100 },
        prepull_action = "blood_fury", prepull_at = -2 })
    eq(rg.grade_opener(prepull_ctx), "S",
        "the ctx's pre-pull row grades on the APL's own mark")
    local prepull_missing = drill_ctx({ last_action = "blood_fury", now = 98,
        resources = { family = "FOREVER", pull_at = 100 },
        prepull_action = "blood_fury", prepull_at = -2 })
    check(rg.grade_opener(prepull_missing) ~= "S",
        "without the proven readiness the pre-pull row is not the expected step")
end

print("rogue_guide_state: " .. checks .. " checks, " .. failures .. " failures")
os.exit(failures == 0 and 0 or 1)
