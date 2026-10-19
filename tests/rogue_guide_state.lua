-- tests/rogue_guide_state.lua: offline tests for the rogue next-action guide: the
-- pure decision engine (rogue_guide.lua) in a strict sandbox.
--
-- Pins:
--   * rogue_guide.lua loads with NO WoW API at all (a strict sandbox errors on any
--     global read) and the per-client DATA tables: pooling bands per family
--     (TBC 65/85 CONFIRMED, ERA/WRATH/FOREVER carried, RETAIL absent) and the
--     Envenom rule per family (ERA/TBC dying_only, WRATH let_expire, FOREVER
--     never, RETAIL chain - each its own table, never a shared reference),
--   * the pooling-band predicate and its boundaries (pre/post/cap lines, unknown
--     energy/tick/band, NaN),
--   * the Rupture-vs-Eviscerate decider on numeric TTD (TTD boundary, rupture
--     missing/refresh/healthy, unknown TTD/CP, NaN rupture),
--   * the per-client Envenom verdicts (dying-only boundary + unknown TTD, Wrath
--     let-expire + cap exception, Forever never, retail chain + proven-empty
--     stacks, unknown family),
--   * the EA-duty / Shiv / Thistle-Tea verdicts and their boundaries,
--   * the evaluate rule order (unknown > expose > shiv > envenom > dying dump >
--     finisher > tea > pool/spend), the unknown-input contract (nil/unusable ->
--     caller-visible unknown, never a guessed verdict), the frozen output fields
--     overwritten on every call, and nil-safety.
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
check(type(rg.envenom_verdict) == "function", "the per-client Envenom verdict is exported")
check(type(rg.shiv_verdict) == "function", "the Shiv verdict is exported")
check(type(rg.ea_verdict) == "function", "the EA-duty verdict is exported")
check(type(rg.tea_verdict) == "function", "the Thistle-Tea verdict is exported")
check(type(rg.is_unknown) == "function", "the unknown-input predicate is exported")
check(type(rg.band_for) == "function", "the band lookup is exported")
eq(rg.TICK_ENERGY_DEFAULT, 20, "the tick gain is 20 (Era+TBC CONFIRMED)")
eq(rg.MAX_ENERGY_DEFAULT, 100, "the energy cap default is 100")
eq(rg.RUPTURE_MIN_TTD_DEFAULT, 8, "the TTD default is 8 (sourced 1CP Rupture 8 s)")
eq(rg.FINISHER_MIN_CP_DEFAULT, 5, "the planned-finisher line is 5 CP")
eq(rg.SHIV_REFRESH_DEFAULT, 2, "the Shiv window is 2 (research §4 watch-list)")

-- Pooling bands: per-client DATA, TBC 65/85 CONFIRMED, RETAIL absent (phase-based).
do
    eq(rg.POOL_BANDS.TBC.pre, 65, "TBC pre-tick band is 65")
    eq(rg.POOL_BANDS.TBC.post, 85, "TBC post-tick band is 85")
    eq(rg.POOL_BANDS.ERA.pre, 65, "ERA carries the pre-tick band as data")
    eq(rg.POOL_BANDS.ERA.post, 85, "ERA carries the post-tick band as data")
    eq(rg.POOL_BANDS.WRATH.pre, 65, "WRATH carries the pre-tick band as data")
    eq(rg.POOL_BANDS.FOREVER.post, 85, "FOREVER carries the post-tick band as data")
    eq(rg.POOL_BANDS.RETAIL, nil, "RETAIL has no tick band (phase-based)")
    eq(rg.band_for("TBC"), rg.POOL_BANDS.TBC, "band_for returns the TBC table")
    eq(rg.band_for("BOGUS"), nil, "band_for answers nil for an unknown family")
    eq(rg.band_for(nil), nil, "band_for answers nil for a nil family")
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
-- 1) The pooling-band predicate
--=========================================================================================
do
    local tbc = rg.POOL_BANDS.TBC
    eq(rg.pool_verdict(50, 1.0, tbc), "pool", "50 energy pools")
    eq(rg.pool_verdict(64.9, 1.0, tbc), "pool", "pre boundary: 64.9 pools")
    eq(rg.pool_verdict(65, 1.0, tbc), "spend", "pre boundary: 65 with a live tick spends")
    eq(rg.pool_verdict(65, nil, tbc), "pool", "pre line with an unknown tick pools (never a timed guess)")
    eq(rg.pool_verdict(84.9, 1.0, tbc), "spend", "84.9 with a tick spends (pre line)")
    eq(rg.pool_verdict(85, 9.9, tbc), "spend", "post boundary: 85 spends whatever the clock says")
    eq(rg.pool_verdict(100, 1.0, tbc), "spend", "a capped bar spends")
    eq(rg.pool_verdict(81, 1.0, tbc), "spend", "81 + 20 ticks past 100: the coming tick caps you")
    eq(rg.pool_verdict(80, 1.0, tbc), "spend", "boundary: 80 + 20 = 100 still spends (>= cap)")
    eq(rg.pool_verdict(79, 1.0, tbc), "spend", "79 + 20 = 99: pre line already spends")
    eq(rg.pool_verdict(50, 1.0, nil), nil, "no band (RETAIL/unknown family) stays silent")
    eq(rg.pool_verdict(50, 1.0, {}), nil, "a band without numbers stays silent")
    eq(rg.pool_verdict(nil, 1.0, tbc), nil, "unknown energy answers nil (never guessed)")
    eq(rg.pool_verdict(0 / 0, 1.0, tbc), nil, "NaN energy answers nil")
    eq(rg.pool_verdict(50, 1.0, tbc, 110), "pool", "Vigor 110 cap pools at 50")
    eq(rg.pool_verdict(95, 1.0, tbc, 110), "spend", "95 + 20 ticks past 110: spends")
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
end

-- Rule 2: Shiv upkeep before the Deadly clock falls off.
do
    eq(evaluate({ shiv_ready = true, deadly_remaining = 1, deadly_stacks = 5,
        cp = 5 }).action, "shiv",
        "rule 2: an imminent Deadly falloff Shivs before the finisher")
    eq(evaluate({ shiv_ready = true, deadly_remaining = 10, deadly_stacks = 5,
        cp = 5, rupture_remains = NONE }).action, "rupture",
        "a healthy Deadly clock falls through to the finisher")
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

-- Rules 4-5: the dying dump at any CP, then the planned finisher on TTD.
do
    eq(evaluate({ cp = 1, ttd = 5 }).action, "eviscerate",
        "rule 4: 1 CP on a dying target Eviscerates (Era any-CP rule)")
    eq(evaluate({ cp = 0, ttd = 5 }).action, nil,
        "rule 4 needs at least 1 CP: 0 CP with no Tea ready pools")
    eq(evaluate({ cp = 5, ttd = 5, rupture_remains = NONE }).action, "eviscerate",
        "rule 4 fires before rule 5 even with Rupture missing")
    eq(evaluate({ cp = 5, ttd = 60, rupture_remains = NONE }).action, "rupture",
        "rule 5: 5 CP with time and no Rupture -> Rupture")
    eq(evaluate({ cp = 5, ttd = 60, rupture_remains = 20 }).action, "eviscerate",
        "rule 5: 5 CP with Rupture healthy -> Eviscerate")
    eq(evaluate({ cp = 5, ttd = NONE, rupture_remains = NONE }).action, nil,
        "rule 5 with unknown TTD guesses no finisher (falls to Tea/pool)")
    eq(evaluate({ cp = 4, ttd = 60, rupture_remains = NONE }).action, nil,
        "4 CP is below the planned line (falls to Tea/pool)")
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
    local fallback = rg.evaluate(inp({ cp = 1, ttd = 5 }))
    eq(fallback.action, "eviscerate", "evaluate can allocate its own out table")

    local frozen = inp({})
    local before_energy = frozen.energy_now
    rg.evaluate(frozen, {})
    eq(frozen.energy_now, before_energy, "evaluate never writes back into its inputs")
end

print("rogue_guide_state: " .. checks .. " checks, " .. failures .. " failures")
os.exit(failures == 0 and 0 or 1)
