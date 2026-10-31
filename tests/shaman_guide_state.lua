-- tests/shaman_guide_state.lua: offline tests for the shaman next-action guide: the
-- pure rule engine (shaman_guide.lua) and the provider glue + drive (classes/shaman.lua)
-- over the real compat.lua + utils.lua + nextaction_ui.lua + weave.lua in a sandbox.
--
-- Pins:
--   * shaman_guide.lua loads with NO WoW API at all (a strict sandbox errors on any
--     global read) and the frozen rule matrix: the casting RIDE hold winning over
--     everything, the Wrath cooldown slots (Fire Elemental / Feral Spirit ready,
--     known-gated) above the MW5-only instant (sub-5 hardcasts live in the
--     fit-verified rules 5b/5c/12b below; without a fit verdict 3-4 stacks
--     still never weave) AND their mw_available gate (nil reads
--     as available, so older callers keep Wrath behaviour), Flame Shock missing /
--     exactly 3.0 s / out of its window / the SoD+TBC 12 s opener gate (Wrath,
--     Forever and unknown families ignore it), the twist skeleton's due/unknown shape, the
--     Era static totems (Windfury first, Grace of Air fallback while Windfury is
--     unknown - G2), the Stormstrike fishing hold (WAIT) and its numeric boundaries, Stormstrike on/off
--     cooldown and the availability gate, the Magma maintain window (due/refresh
--     boundary/unknown/custom refresh), Fire Nova ready/down, Lava Lash ready/down
--     and the Earth Shock filler,
--   * the APL UTILITY layer (bench/rotation_gap_vs_apl_2026-10-20.md §5): the
--     Bloodlust party cooldown (rule 3b), the Strength of Earth Totem upkeep
--     (rule 8a) and the Mana Spring Totem upkeep (rule 8d) - family-gated,
--     threshold-exact and unknown-hides - and the TBC Frost Shock filler
--     (rule 13b), which answers ONLY when the player states the APL's
--     alternative "Filler Shock" choice and keeps the Earth Shock filler
--     silent in that case; Frost Shock is never named on any other family,
--   * Wrath never twists (the live feed stays nil there); a fed target_count
--     changes nothing (no Chain Lightning split - deferred for lack of a countable
--     input),
----   * the frozen output fields are overwritten on every call (stale fields can never
--     survive into a reused out table) and nil inputs never error,
--   * the gather into the caller-owned reused table: every frozen input (including
--     mw_available, the Windfury ICD feed, Fire Nova and the nil twist stub), the
--     GCD-echo filter on the Stormstrike AND Fire Nova cooldowns, the tracker-fed
--     Flame Shock window, the catalogue readiness, stale-field overwrites and the
--     option threshold,
--   * the throttled target scan keeps running while the guide is enabled even with the
--     Flame Shock bar switched off (and stays idle with the guide off too),
--   * the provider contract shape (slot keys, fifteen slots, cooldown keys resolving into
--     the gathered inputs, possible actions naming declared slots),
--   * the display mapping through the real frame sandbox (action -> slot -> fade
--     targets, the RIDE/WAIT holds, debuff-fed swipes and their latch, the option
--     gates),
--   * the TBC behaviour through the sandbox (a TBC client: no weave prompt ever, the
--     WAIT hold, Nova and the shock filler; the Wrath slots stay dark there) and
--     the Wrath block (the exact MW5 prompt survives behind a family override, the
--     MW>=3 LB fit lights the weave slot high when 300 ms + cast fits (M1), the
--     cooldown slots light in research order),
--   * the SoD block (the MW latch re-enables the MW5 rule; the weave slot
--     re-points at Lava Burst when the rune is known and keeps the catalogue
--     without it),
--   * the config/options parity for every new shaman key and the TOC load order,
--   * the drive wiring (post_init -> ui.init, on_bar_update -> the settings diff +
--     ui.on_bar_update) exercised through the real hooks.
-- Run from the repo root: lua5.1 tests/shaman_guide_state.lua  (any cwd works).

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
            error("shaman_guide.lua touched a global: " .. tostring(key))
        end,
    })
    local chunk = assert(loadfile(ROOT .. "shaman_guide.lua"))
    setfenv(chunk, strict)
    local ok, err = pcall(chunk, "SwedgeTimer", pure)
    check(ok, "shaman_guide.lua loads with no WoW API and no globals (" .. tostring(err) .. ")")
end

local sg = pure.shaman_guide
check(type(sg) == "table", "shaman_guide.lua defines st.shaman_guide")
check(type(sg.evaluate) == "function", "the pure engine is exported")
eq(sg.FLAMESHOCK_REFRESH_DEFAULT, 3, "the Flame Shock refresh default is 3")
eq(sg.FS_FIGHT_GATE_SECONDS, 12, "the Flame Shock opener gate is 12 s")
eq(sg.SR_MANA_THRESHOLD_TBC, 0.10, "the TBC Shamanistic Rage mana gate is 10%")
eq(sg.SR_MANA_THRESHOLD_SOD, 0.65, "the SoD Shamanistic Rage mana gate is 65%")
eq(sg.ES_MANA_FLOOR_ERA, 0.5, "the Era Earth Shock mana floor is 50%")
eq(sg.FN_MANA_FLOOR_FOREVER, 0.10, "the Forever Fire Nova mana floor is 10%")
eq(sg.WEAVE_SUB5_MIN_STACKS, 0, "the SoD sub-5 weave floor is 0 stacks (ANY incl 0-1)")
eq(sg.WEAVE_SUB5_FIT_BUFFER_SECONDS, 0.10, "the SoD sub-5 fit buffer is 100 ms")
eq(sg.WEAVE_SUB5_MIN_STACKS_WRATH, 3, "the Wrath sub-5 weave floor is 3 stacks (WF-build MW>=3)")
eq(sg.WEAVE_SUB5_FIT_BUFFER_WRATH_SECONDS, 0.30, "the Wrath sub-5 fit buffer is 300 ms")

-- Rule-matrix inputs: everything the frozen input set names, with a baseline that lands
-- on Stormstrike (no cast, Maelstrom available, no stacks, a healthy Flame Shock, SS
-- off cooldown, Fire Nova ready but outranked).
local NONE = {}
local function inp(overrides)
    local t = {
        speed = 3.0, swing_remaining = 2.0, gcd_remaining = 0,
        casting = false, mw_available = true, mw_stacks = 0, weave_available = true,
        weave_sub5_ready = nil, weave_sub5_cast_seconds = nil, weave_sub5_is_lavaburst = nil,
        flameshock_remaining = 10, flameshock_refresh = 0, flameshock_allowed = nil,
        stormstrike_remaining = 0, stormstrike_hold_enabled = nil,
        windfury_icd_remaining = nil,
        firenova_remaining = 0, fireele_active = nil, twist_remaining = nil,
        twist_mana_threshold = nil, fireele_remaining = nil, feralspirit_remaining = nil,
        wftotem_remaining = nil, goatotem_remaining = nil,
        sr_remaining = nil, sr_mana_threshold = nil, mana_fraction = nil,
        shock_remaining = nil,
        magma_remaining = nil, magma_refresh = 3,
        lavalash_remaining = nil,
        target_count = nil, moltenblast_remaining = nil, clearcasting_active = nil,
        searing_down = nil, mw_observed = nil, lightningshield_due = nil,
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
    local ret = sg.evaluate(inp(overrides), out)
    eq(ret, out, "evaluate returns the caller's out table")
    return out
end

-- Baseline: nothing to re-apply, SS ready -> Stormstrike.
do
    local out = evaluate({})
    eq(out.action, "stormstrike", "baseline: a healthy Flame Shock and a ready SS -> Stormstrike")
    eq(out.hold, false, "baseline: no hold")
    eq(out.hold_text, nil, "baseline: no hold text")
    eq(out.filler_slot, nil, "baseline: filler_slot stays nil")
    eq(out.judge_slot, nil, "baseline: judge_slot stays nil")
    eq(out.rotation_key, nil, "baseline: rotation_key stays nil")
    eq(out.waiting_judgement, false, "baseline: waiting_judgement stays false")
end

-- Rule 1: the casting hold wins over everything.
do
    local out = evaluate({ casting = true })
    eq(out.action, nil, "rule 1: a cast in flight shows no action")
    eq(out.hold, true, "rule 1: a cast in flight holds")
    eq(out.hold_text, "RIDE", "rule 1: the casting hold reads RIDE")
    eq(evaluate({ casting = true, mw_stacks = 5 }).action, nil,
        "rule 1 outranks the 5-stack weave")
    eq(evaluate({ casting = true, mw_stacks = 5, flameshock_remaining = NONE }).hold_text, "RIDE",
        "rule 1 outranks the Flame Shock refresh")
    eq(evaluate({ casting = true, stormstrike_remaining = 0 }).action, nil,
        "rule 1 outranks a ready Stormstrike")
end

-- Rules 2-3: Fire Elemental / Feral Spirit ready, known-gated (nil = unknown).
do
    eq(evaluate({ fireele_remaining = 0 }).action, "fireele",
        "rule 2: a ready Fire Elemental -> fireele")
    eq(evaluate({ fireele_remaining = 0, mw_stacks = 5 }).action, "fireele",
        "rule 2 outranks the 5-stack weave")
    eq(evaluate({ fireele_remaining = 0, flameshock_remaining = NONE }).action, "fireele",
        "rule 2 outranks the Flame Shock refresh")
    eq(evaluate({ fireele_remaining = 0, stormstrike_remaining = 0 }).action, "fireele",
        "rule 2 outranks a ready Stormstrike")
    eq(evaluate({ fireele_remaining = 5, stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 2 boundary: a running cooldown falls through")
    eq(evaluate({ fireele_remaining = NONE }).action, "stormstrike",
        "rule 2: an unknown Fire Elemental never prompts")
    eq(evaluate({ feralspirit_remaining = 0 }).action, "feralspirit",
        "rule 3: a ready Feral Spirit -> feralspirit")
    eq(evaluate({ feralspirit_remaining = 0, mw_stacks = 5 }).action, "feralspirit",
        "rule 3 outranks the 5-stack weave")
    eq(evaluate({ feralspirit_remaining = 0, flameshock_remaining = NONE }).action, "feralspirit",
        "rule 3 outranks the Flame Shock refresh")
    eq(evaluate({ feralspirit_remaining = 5, stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 3 boundary: a running cooldown falls through")
    eq(evaluate({ feralspirit_remaining = NONE }).action, "stormstrike",
        "rule 3: an unknown Feral Spirit never prompts")
    eq(evaluate({ fireele_remaining = 0, feralspirit_remaining = 0 }).action, "fireele",
        "rule 2 outranks rule 3 when both are ready")
end

-- Rule 4: Shamanistic Rage ready inside its family mana gate (SoD <= 65%,
-- TBC < 10%; Wrath prompts on cooldown with a nil threshold).
do
    eq(evaluate({ sr_remaining = 0 }).action, "shamanisticrage",
        "rule 4: a ready Shamanistic Rage with no gate -> shamanisticrage")
    eq(evaluate({ sr_remaining = 0, feralspirit_remaining = 0 }).action, "feralspirit",
        "rule 3 outranks a ready Shamanistic Rage")
    eq(evaluate({ sr_remaining = 0, mw_stacks = 5 }).action, "shamanisticrage",
        "rule 4 outranks the 5-stack weave")
    eq(evaluate({ sr_remaining = 0, flameshock_remaining = NONE }).action, "shamanisticrage",
        "rule 4 outranks the Flame Shock refresh")
    eq(evaluate({ sr_remaining = 5, stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 4 boundary: a running cooldown falls through")
    eq(evaluate({ sr_remaining = NONE }).action, "stormstrike",
        "rule 4: an unknown Shamanistic Rage never prompts")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = 0.10, mana_fraction = 0.05 }).action,
        "shamanisticrage", "rule 4: TBC mana below 10% prompts")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = 0.10, mana_fraction = 0.10 }).action,
        "shamanisticrage", "rule 4 boundary: exactly the threshold prompts")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = 0.10, mana_fraction = 0.11 }).action,
        "stormstrike", "rule 4: TBC mana above 10% falls through")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = 0.65, mana_fraction = 0.65 }).action,
        "shamanisticrage", "rule 4: SoD mana at 65% prompts")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = 0.65, mana_fraction = 0.66 }).action,
        "stormstrike", "rule 4: SoD mana above 65% falls through")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = 0.10, mana_fraction = NONE }).action,
        "stormstrike", "rule 4: a gated threshold never prompts on unknown mana")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = 0.10, mana_fraction = "low" }).action,
        "stormstrike", "rule 4: a gated threshold never prompts on a non-number mana")
end

-- Rule 4 family defaults: the engine constants cover direct callers that omit
-- the threshold (the live gather always feeds it explicitly). No live-visible
-- change; a gated default never prompts on unknown mana.
do
    local saved_family = pure.family
    pure.family = "TBC"
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = NONE, mana_fraction = 0.05 }).action,
        "shamanisticrage", "rule 4 default: TBC with no threshold prompts at low mana")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = NONE, mana_fraction = 0.10 }).action,
        "shamanisticrage", "rule 4 default: TBC boundary exactly 10% prompts")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = NONE, mana_fraction = 0.11 }).action,
        "stormstrike", "rule 4 default: TBC with no threshold falls through above 10%")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = NONE, mana_fraction = NONE }).action,
        "stormstrike", "rule 4 default: TBC never prompts on unknown mana")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = 0.65, mana_fraction = 0.5 }).action,
        "shamanisticrage", "rule 4 default: an explicit threshold still wins over the family")
    pure.family = "ERA"
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = NONE, mana_fraction = 0.65 }).action,
        "shamanisticrage", "rule 4 default: ERA with no threshold prompts at 65%")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = NONE, mana_fraction = 0.66 }).action,
        "stormstrike", "rule 4 default: ERA with no threshold falls through above 65%")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = NONE, mana_fraction = NONE }).action,
        "stormstrike", "rule 4 default: ERA never prompts on unknown mana")
    pure.family = "WRATH"
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = NONE, mana_fraction = 0.99 }).action,
        "shamanisticrage", "rule 4 default: Wrath with no threshold prompts on cooldown")
    eq(evaluate({ sr_remaining = 0, sr_mana_threshold = NONE, mana_fraction = NONE }).action,
        "shamanisticrage", "rule 4 default: Wrath prompts on unknown mana (ungated)")
    pure.family = saved_family
end

-- Rule 5: the five-stack instant, gated on Maelstrom availability. MW5-ONLY for
-- the instant; the sub-5 hardcast lives in rules 5b (LvB, high) + 12b (LB,
-- low), both fit-verified (G1) - without a fit verdict 3-4 stacks still fall
-- through below.
do
    eq(evaluate({ mw_stacks = 5 }).action, "weave",
        "rule 5: five stacks -> weave")
    eq(evaluate({ mw_stacks = 5, flameshock_remaining = NONE }).action, "weave",
        "rule 5 outranks the Flame Shock refresh")
    eq(evaluate({ mw_stacks = 5, stormstrike_remaining = 0 }).action, "weave",
        "rule 5 outranks a ready Stormstrike")
    eq(evaluate({ mw_stacks = 5, weave_available = false }).action, "weave",
        "rule 5 boundary: five stacks are instant regardless of the catalogue state")
    eq(evaluate({ mw_stacks = 4.99, stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 5 boundary: just below five stacks falls through without a fit verdict")
    eq(evaluate({ mw_stacks = NONE }).action, "stormstrike",
        "rule 5: an unreadable stack count cannot match")
    eq(evaluate({ mw_stacks = 5, mw_available = NONE }).action, "weave",
        "rule 5: a missing mw_available reads as available (older callers keep Wrath behaviour)")
    eq(evaluate({ mw_stacks = 5, mw_available = false }).action, "stormstrike",
        "rule 5 gate: five stacks without Maelstrom fall through to Stormstrike")
    eq(evaluate({ mw_stacks = 5, mw_available = false, stormstrike_remaining = 8,
        firenova_remaining = 8 }).action, "earthshock",
        "rule 5 gate: with SS and Nova down the fallthrough reaches the shock filler")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 3 }).action, "firenova",
        "rule 5: 3 stacks with SS down and no fit verdict reach Fire Nova, never the weave")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 4, weave_available = true }).action,
        "firenova", "rule 5: 4 stacks with no fit verdict never weave even with the catalogue ready")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 3, firenova_remaining = 5 }).action,
        "earthshock", "rule 5: 3 stacks with SS and Nova down and no fit verdict reach the shock filler")
    eq(evaluate({ mw_stacks = 5, target_count = 3 }).action, "weave",
        "no target-count split on the instant: extra targets do not change the MW5 prompt")
    eq(evaluate({ mw_stacks = 5, weave_sub5_ready = true, weave_sub5_is_lavaburst = true }).action,
        "weave", "rule 5 outranks the sub-5 fit (same action, instant first)")
end

-- Rules 5b + 5c + 12b: the ANY-stack weave fit (G1 SoD + M1 Wrath). Strict
-- booleans: ready must be true AND is_lavaburst a boolean; nil/false/NaN
-- never prompt, so older callers keep the MW5-only behaviour.
do
    local NaN = 0 / 0
    -- 5b HIGH (LvB fit, above Stormstrike): the SoD sim weaves Lava Burst at
    -- ANY stacks when the cast fits, above SS.
    eq(evaluate({ mw_stacks = 3, weave_sub5_ready = true, weave_sub5_is_lavaburst = true }).action,
        "weave", "rule 5b: a fit LvB hardcast -> weave")
    -- 0-1 hardcast (G1 remainder): the SoD sim weaves at ANY stacks incl 0-1,
    -- so a fit verdict at 1 (and 0) stacks prompts the same way.
    eq(evaluate({ mw_stacks = 1, weave_sub5_ready = true, weave_sub5_is_lavaburst = true }).action,
        "weave", "rule 5b: a fit LvB hardcast at 1 stack -> weave")
    eq(evaluate({ mw_stacks = 1, weave_sub5_ready = true, weave_sub5_is_lavaburst = false,
        stormstrike_remaining = 8, firenova_remaining = 8,
        lavalash_remaining = 8, shock_remaining = 0 }).action, "weave",
        "rule 12b: a fit LB hardcast at 1 stack below LL -> weave")
    eq(evaluate({ mw_stacks = 0, weave_sub5_ready = true, weave_sub5_is_lavaburst = true }).action,
        "weave", "rule 5b: a fit LvB hardcast at 0 stacks -> weave")
    eq(evaluate({ mw_stacks = 3, weave_sub5_ready = true, weave_sub5_is_lavaburst = true,
        flameshock_remaining = NONE }).action, "weave",
        "rule 5b outranks the Flame Shock refresh")
    eq(evaluate({ mw_stacks = 2, weave_sub5_ready = true, weave_sub5_is_lavaburst = true,
        stormstrike_remaining = 0 }).action, "weave",
        "rule 5b outranks a ready Stormstrike")
    eq(evaluate({ mw_stacks = 4, weave_sub5_ready = true, weave_sub5_is_lavaburst = true,
        stormstrike_remaining = 8, firenova_remaining = 0 }).action, "weave",
        "rule 5b outranks Fire Nova while SS is down")
    eq(evaluate({ mw_stacks = 3, weave_sub5_ready = true, weave_sub5_is_lavaburst = true,
        sr_remaining = 0 }).action, "shamanisticrage",
        "rule 4 outranks the LvB fit (SR > LvB, the sim order)")
    eq(evaluate({ mw_stacks = 5, weave_sub5_ready = true, weave_sub5_is_lavaburst = true }).action,
        "weave", "rule 5 outranks 5b when both are ready (same action)")
    eq(evaluate({ casting = true, mw_stacks = 3, weave_sub5_ready = true,
        weave_sub5_is_lavaburst = true }).action, nil,
        "rule 1 outranks the LvB fit (RIDE holds mid-cast)")
    eq(evaluate({ fireele_remaining = 0, mw_stacks = 3, weave_sub5_ready = true,
        weave_sub5_is_lavaburst = true }).action, "fireele",
        "rule 2 outranks the LvB fit")
    eq(evaluate({ feralspirit_remaining = 0, mw_stacks = 3, weave_sub5_ready = true,
        weave_sub5_is_lavaburst = true }).action, "feralspirit",
        "rule 3 outranks the LvB fit")
    -- 5b unknown-hides: nil/false/NaN ready never prompts; nil is_lavaburst
    -- never prompts; non-boolean is_lavaburst never prompts.
    eq(evaluate({ mw_stacks = 3, weave_sub5_ready = NONE, weave_sub5_is_lavaburst = true,
        stormstrike_remaining = 8, firenova_remaining = 8, lavalash_remaining = 8,
        shock_remaining = 8 }).action, "earthshock",
        "rule 5b: an unknown fit never prompts (older callers keep MW5-only)")
    eq(evaluate({ mw_stacks = 3, weave_sub5_ready = false, weave_sub5_is_lavaburst = true,
        stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 5b: a known-not-fit never prompts")
    eq(evaluate({ mw_stacks = 3, weave_sub5_ready = NaN, weave_sub5_is_lavaburst = true,
        stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 5b: a NaN ready never prompts")
    eq(evaluate({ mw_stacks = 3, weave_sub5_ready = true, weave_sub5_is_lavaburst = NONE,
        stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 5b: an unknown spell never prompts")
    eq(evaluate({ mw_stacks = 3, weave_sub5_ready = true, weave_sub5_is_lavaburst = "yes",
        stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 5b: a non-boolean spell never prompts")
    -- 12b LOW (LB fit, below Lava Lash): the SoD sim weaves Lightning Bolt at
    -- ANY stacks when the cast fits, below LL and above CL.
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 3, firenova_remaining = 8,
        lavalash_remaining = 8, weave_sub5_ready = true, weave_sub5_is_lavaburst = false,
        shock_remaining = 0 }).action, "weave",
        "rule 12b: a fit LB hardcast below LL -> weave")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 3, firenova_remaining = 8,
        lavalash_remaining = 0, weave_sub5_ready = true, weave_sub5_is_lavaburst = false }).action,
        "lavalash", "rule 12 outranks the LB fit (LL > LB fit, the sim order)")
    eq(evaluate({ stormstrike_remaining = 0, mw_stacks = 3, weave_sub5_ready = true,
        weave_sub5_is_lavaburst = false }).action, "stormstrike",
        "a ready Stormstrike outranks the LB fit (SS > LB fit, the sim order)")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 3, firenova_remaining = 8,
        lavalash_remaining = 8, weave_sub5_ready = true, weave_sub5_is_lavaburst = false,
        target_count = 3, shock_remaining = 0 }).action, "weave",
        "rule 12b outranks the multi-target Chain Lightning")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 3, firenova_remaining = 8,
        lavalash_remaining = 8, weave_sub5_ready = false, weave_sub5_is_lavaburst = false,
        shock_remaining = 0 }).action, "earthshock",
        "rule 12b: a known-not-fit LB never prompts")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 3, firenova_remaining = 8,
        lavalash_remaining = 8, weave_sub5_ready = true, weave_sub5_is_lavaburst = NONE,
        shock_remaining = 0 }).action, "earthshock",
        "rule 12b: an unknown spell never prompts")
    -- 5c HIGH (Wrath LB fit, between MW5 and Flame Shock): the default_wf sim
    -- weaves Lightning Bolt at MW >= 3 when 300 ms + cast fits, above SS.
    -- Family-gated: the same feed on a non-Wrath family is not 5c (SoD LB
    -- falls through to 12b below).
    do
        local saved_family = pure.family
        pure.family = "WRATH"
        eq(evaluate({ mw_stacks = 3, weave_sub5_ready = true, weave_sub5_is_lavaburst = false }).action,
            "weave", "rule 5c: a fit Wrath LB hardcast -> weave")
        eq(evaluate({ mw_stacks = 3, weave_sub5_ready = true, weave_sub5_is_lavaburst = false,
            flameshock_remaining = NONE }).action, "weave",
            "rule 5c outranks the Flame Shock refresh")
        eq(evaluate({ mw_stacks = 4, weave_sub5_ready = true, weave_sub5_is_lavaburst = false,
            stormstrike_remaining = 0 }).action, "weave",
            "rule 5c outranks a ready Stormstrike (SS > LB fit is the SoD order, not Wrath)")
        eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 3, firenova_remaining = 8,
            lavalash_remaining = 0, weave_sub5_ready = true, weave_sub5_is_lavaburst = false }).action,
            "weave", "rule 5c outranks Lava Lash while the LOW fit sits below it")
        eq(evaluate({ mw_stacks = 3, weave_sub5_ready = true, weave_sub5_is_lavaburst = false,
            sr_remaining = 0 }).action, "shamanisticrage",
            "rule 4 outranks the Wrath LB fit (SR > LB fit, the sim order)")
        eq(evaluate({ mw_stacks = 5, weave_sub5_ready = true, weave_sub5_is_lavaburst = false }).action,
            "weave", "rule 5 outranks 5c when both are ready (same action)")
        eq(evaluate({ casting = true, mw_stacks = 3, weave_sub5_ready = true,
            weave_sub5_is_lavaburst = false }).action, nil,
            "rule 1 outranks the Wrath LB fit (RIDE holds mid-cast)")
        -- 5c unknown-hides: nil/false/NaN ready never prompts; nil/non-boolean
        -- spell never prompts.
        eq(evaluate({ mw_stacks = 3, weave_sub5_ready = NONE, weave_sub5_is_lavaburst = false,
            stormstrike_remaining = 8, firenova_remaining = 8, lavalash_remaining = 8,
            shock_remaining = 8 }).action, "earthshock",
            "rule 5c: an unknown fit never prompts (older callers keep MW5-only)")
        eq(evaluate({ mw_stacks = 3, weave_sub5_ready = false, weave_sub5_is_lavaburst = false,
            stormstrike_remaining = 0 }).action, "stormstrike",
            "rule 5c: a known-not-fit never prompts")
        eq(evaluate({ mw_stacks = 3, weave_sub5_ready = NaN, weave_sub5_is_lavaburst = false,
            stormstrike_remaining = 0 }).action, "stormstrike",
            "rule 5c: a NaN ready never prompts")
        eq(evaluate({ mw_stacks = 3, weave_sub5_ready = true, weave_sub5_is_lavaburst = NONE,
            stormstrike_remaining = 0 }).action, "stormstrike",
            "rule 5c: an unknown spell never prompts")
        eq(evaluate({ mw_stacks = 3, weave_sub5_ready = true, weave_sub5_is_lavaburst = "yes",
            stormstrike_remaining = 0 }).action, "stormstrike",
            "rule 5c: a non-boolean spell never prompts")
        -- Family gate: the same feed off Wrath never takes the HIGH rank (a
        -- ready Stormstrike answers instead; the LOW fit sits below SS).
        pure.family = "ERA"
        eq(evaluate({ mw_stacks = 3, weave_sub5_ready = true, weave_sub5_is_lavaburst = false,
            stormstrike_remaining = 0 }).action, "stormstrike",
            "rule 5c gate: the same feed off Wrath falls through to Stormstrike, not 5c")
        pure.family = saved_family
    end
    -- Cross-tier: the HIGH fit outranks everything the LOW fit sits below.
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 3, firenova_remaining = 8,
        lavalash_remaining = 0, weave_sub5_ready = true, weave_sub5_is_lavaburst = true,
        shock_remaining = 0 }).action, "weave",
        "rule 5b outranks Lava Lash while the LOW fit sits below it")
end

-- Rule 6: the Flame Shock refresh window (vetoed on Era-base, where the sim
-- never casts Flame Shock).
do
    eq(evaluate({ flameshock_remaining = NONE }).action, "flameshock",
        "rule 6: an untracked Flame Shock -> Flame Shock")
    eq(evaluate({ flameshock_remaining = 3 }).action, "stormstrike",
        "rule 6 boundary: a live dot is not re-applied (the shipped threshold is 0 - expiry only)")
    eq(evaluate({ flameshock_remaining = 0.001 }).action, "stormstrike",
        "rule 6 boundary: a hair of life left is still not re-applied")
    eq(evaluate({ flameshock_remaining = 0 }).action, "flameshock",
        "rule 6: a remaining of exactly 0 refreshes")
    eq(evaluate({ flameshock_remaining = NONE, stormstrike_remaining = 0 }).action, "flameshock",
        "rule 6 outranks a ready Stormstrike")
    eq(evaluate({ flameshock_remaining = 4.5, flameshock_refresh = 5 }).action, "flameshock",
        "rule 6: a custom refresh widens the window")
    eq(evaluate({ flameshock_remaining = 5.5, flameshock_refresh = 5 }).action, "stormstrike",
        "rule 6: just outside it the chain moves on")
    eq(evaluate({ flameshock_remaining = 3.5, flameshock_refresh = NONE }).action, "stormstrike",
        "rule 6: a missing threshold falls back to 3")
    eq(evaluate({ flameshock_remaining = 3, flameshock_refresh = NONE }).action, "flameshock",
        "rule 6: the engine's own 3 s fallback still refreshes at exactly 3.0 s")
    eq(evaluate({ flameshock_remaining = 3.5, flameshock_refresh = 0 }).action, "stormstrike",
        "rule 6: a zero threshold only refreshes an absent-or-expired debuff")
    eq(evaluate({ flameshock_remaining = NONE, flameshock_allowed = false }).action,
        "stormstrike", "rule 6 veto: Era-base never refreshes, even untracked")
    eq(evaluate({ flameshock_remaining = 0, flameshock_allowed = false }).action,
        "stormstrike", "rule 6 veto: Era-base never refreshes, even expired")
    eq(evaluate({ flameshock_remaining = NONE, flameshock_allowed = true }).action,
        "flameshock", "rule 6: an explicit allow keeps the untracked refresh")
end

-- Rule 6 opener gate: no Flame Shock in the first 12 s on SoD/TBC (SoD P6 +
-- TBC default APL: FS only once the fight is older than 12 s). Unknown age
-- prompts as before; Wrath, Forever and every other family ignore the gate.
do
    local NaN = 0 / 0
    local saved_family = pure.family
    -- SoD shape: the ERA token with the maintain allowed (the MW-rune signal).
    pure.family = "ERA"
    eq(evaluate({ flameshock_remaining = NONE, flameshock_allowed = true, fight_elapsed = 0 }).action,
        "stormstrike", "rule 6 gate: a SoD pull falls through to Stormstrike")
    eq(evaluate({ flameshock_remaining = NONE, flameshock_allowed = true, fight_elapsed = 11.999 }).action,
        "stormstrike", "rule 6 gate: SoD just under 12 s still falls through")
    eq(evaluate({ flameshock_remaining = NONE, flameshock_allowed = true, fight_elapsed = 12 }).action,
        "flameshock", "rule 6 gate: SoD at exactly 12 s prompts")
    eq(evaluate({ flameshock_remaining = NONE, flameshock_allowed = true, fight_elapsed = NONE }).action,
        "flameshock", "rule 6 gate: SoD unknown age prompts as before")
    eq(evaluate({ flameshock_remaining = NONE, flameshock_allowed = true, fight_elapsed = NaN }).action,
        "flameshock", "rule 6 gate: SoD NaN age prompts as before")
    eq(evaluate({ flameshock_remaining = NONE, flameshock_allowed = false, fight_elapsed = 30 }).action,
        "stormstrike", "rule 6 gate: the Era-base veto stands past the gate")
    pure.family = "TBC"
    eq(evaluate({ flameshock_remaining = NONE, fight_elapsed = 0 }).action,
        "stormstrike", "rule 6 gate: a TBC pull falls through to Stormstrike")
    eq(evaluate({ flameshock_remaining = NONE, fight_elapsed = 12 }).action,
        "flameshock", "rule 6 gate: TBC at 12 s prompts")
    pure.family = "WRATH"
    eq(evaluate({ flameshock_remaining = NONE, fight_elapsed = 0 }).action,
        "flameshock", "rule 6 gate: Wrath ignores the gate (filed M5 fight-remaining)")
    pure.family = "FOREVER"
    eq(evaluate({ flameshock_remaining = NONE, fight_elapsed = 0 }).action,
        "flameshock", "rule 6 gate: Forever ignores the gate (no sim fight gate)")
    pure.family = nil
    eq(evaluate({ flameshock_remaining = NONE, fight_elapsed = 0 }).action,
        "flameshock", "rule 6 gate: a nil family keeps the old behaviour")
    pure.family = saved_family
end

-- Rules 7-9: the twist skeleton, the opt-in fishing hold and Stormstrike off
-- cooldown. (Wrath has no twisting: live twist_remaining is nil there, so rule 7
-- is dead.)
do
    eq(evaluate({ twist_remaining = 0 }).action, "twist",
        "rule 7: a due twist prompts the twist")
    eq(evaluate({ twist_remaining = 0, flameshock_remaining = NONE }).action, "flameshock",
        "rule 6 outranks a due twist")
    eq(evaluate({ twist_remaining = 0, stormstrike_remaining = 0,
        windfury_icd_remaining = 0.5, stormstrike_hold_enabled = true }).action, "twist",
        "rule 7 outranks the fishing hold")
    eq(evaluate({ twist_remaining = 5 }).action, "stormstrike",
        "rule 7 boundary: a twist that is not due falls through")
    eq(evaluate({ twist_remaining = NONE }).action, "stormstrike",
        "rule 7: an unknown twist never prompts (the live skeleton shape)")

    -- Rule 8: delay-if-fishing-WF, opt-in only (audit 2026-10-19 §1: every sim
    -- casts Stormstrike on cooldown, so the default presses it).
    local held = evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 0.5,
        swing_remaining = 2.0, stormstrike_hold_enabled = true })
    eq(held.action, nil, "rule 8: an opted-in ICD inside the swing holds Stormstrike")
    eq(held.hold, true, "rule 8: the hold overlay shows")
    eq(held.hold_text, "WAIT", "rule 8: the fishing hold reads WAIT")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 0.5,
        swing_remaining = 2.0 }).action, "stormstrike",
        "rule 8 default: without the opt-in a live ICD presses Stormstrike")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 0.5,
        swing_remaining = 2.0, stormstrike_hold_enabled = false }).action, "stormstrike",
        "rule 8 default: an explicit false presses Stormstrike too")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 0,
        stormstrike_hold_enabled = true }).action,
        "stormstrike", "rule 8 boundary: an elapsed ICD presses Stormstrike")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 2.5,
        swing_remaining = 2.0, stormstrike_hold_enabled = true }).action, "stormstrike",
        "rule 8 boundary: an ICD past the swing presses Stormstrike")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 2.0,
        swing_remaining = 2.0, stormstrike_hold_enabled = true }).action, nil,
        "rule 8 boundary: an ICD exactly at the swing still holds")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = NONE,
        stormstrike_hold_enabled = true }).action,
        "stormstrike", "rule 8: an unknown ICD never holds")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 0.5,
        swing_remaining = NONE, stormstrike_hold_enabled = true }).action, "stormstrike",
        "rule 8: an unknown swing never holds")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 0.5,
        swing_remaining = 0, stormstrike_hold_enabled = true }).action, "stormstrike",
        "rule 8: a landing swing presses (the next tick re-evaluates)")
    local NaN = 0 / 0
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = NaN,
        stormstrike_hold_enabled = true }).action,
        "stormstrike", "rule 8: a NaN ICD never holds")

    -- Rule 9: Stormstrike off cooldown.
    eq(evaluate({ stormstrike_remaining = NONE }).action, "stormstrike",
        "rule 9: an unreadable cooldown reads as ready")
    eq(evaluate({ stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 9 boundary: exactly 0 is off cooldown")
    eq(evaluate({ stormstrike_remaining = -1 }).action, "stormstrike",
        "rule 9: a negative remaining is off cooldown")
    eq(evaluate({ stormstrike_remaining = 0.001, mw_stacks = 0,
        firenova_remaining = 8 }).action, "earthshock",
        "rule 9 boundary: a real SS cooldown with Nova down falls to the shock filler")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0,
        weave_available = false }).action, "firenova",
        "rule 9: a real cooldown falls to Fire Nova")
end

-- Rule 7 mana pause (audit 2026-10-19 TBC §: the sim pauses the twist
-- alternation at low mana instead of downranking). Input-driven: a nil
-- threshold keeps the old prompt; the live feed is filed, so every path
-- below is dormant until the gather feeds the threshold.
do
    local due = { twist_remaining = 0, flameshock_remaining = 5,
        stormstrike_remaining = 0 }
    eq(evaluate(due).action, "twist",
        "rule 7 pause: no threshold twists as before")
    due.twist_mana_threshold = 0.10
    due.mana_fraction = 0.11
    eq(evaluate(due).action, "twist",
        "rule 7 pause: mana above the threshold twists on")
    due.mana_fraction = 0.10
    eq(evaluate(due).action, "stormstrike",
        "rule 7 pause boundary: exactly the threshold falls through")
    due.mana_fraction = 0.05
    eq(evaluate(due).action, "stormstrike",
        "rule 7 pause: mana below the threshold falls through")
    eq(evaluate(due).hold, false,
        "rule 7 pause: the fallthrough carries no hold")
    due.mana_fraction = nil
    eq(evaluate(due).action, "twist",
        "rule 7 pause: unknown mana never pauses")
    due.mana_fraction = "low"
    eq(evaluate(due).action, "twist",
        "rule 7 pause: non-number mana never pauses")
    due.mana_fraction = 0.05
    due.twist_mana_threshold = nil
    eq(evaluate(due).action, "twist",
        "rule 7 pause: unknown threshold never pauses")
    due.twist_mana_threshold = "0.10"
    eq(evaluate(due).action, "twist",
        "rule 7 pause: non-number threshold never pauses")
    local NaN = 0 / 0
    due.twist_mana_threshold = 0.10
    due.mana_fraction = NaN
    eq(evaluate(due).action, "twist",
        "rule 7 pause: NaN mana never pauses")
    due.mana_fraction = 0.05
    due.twist_mana_threshold = NaN
    eq(evaluate(due).action, "twist",
        "rule 7 pause: NaN threshold never pauses")
    -- Higher rules still outrank a paused twist; the chain below still moves.
    due.twist_mana_threshold = 0.10
    due.mana_fraction = 0.05
    due.mw_stacks = 5
    eq(evaluate(due).action, "weave",
        "rule 7 pause: five stacks still outrank a paused twist")
    due.mw_stacks = 0
    due.flameshock_remaining = 0
    eq(evaluate(due).action, "flameshock",
        "rule 7 pause: the Flame Shock refresh still outranks a paused twist")
end

-- Rules 8b-8c: Era static totems (G2, audit 2026-10-19 Era §: WF refresh
-- first, GoA when inactive, both above Stormstrike). The engine is ungated -
-- the gather feeds due only on Era-base - so these pins prove rank and
-- unknown-hides, not family (family gating is pinned through the gather
-- below).
do
    eq(evaluate({ stormstrike_remaining = 0, wftotem_remaining = 0 }).action, "wftotem",
        "rule 8b: a due Windfury Totem prompts the wftotem slot")
    eq(evaluate({ stormstrike_remaining = 0, wftotem_remaining = 0,
        goatotem_remaining = 0 }).action, "wftotem",
        "rule 8b outranks 8c when both are due (the sim's priority)")
    eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 0,
        wftotem_remaining = 0 }).action, "wftotem",
        "rule 8b outranks Fire Nova while Stormstrike is down")
    eq(evaluate({ wftotem_remaining = 0, stormstrike_remaining = 0,
        windfury_icd_remaining = 0.5, swing_remaining = 2.0,
        stormstrike_hold_enabled = true }).action, nil,
        "rule 8 outranks 8b: the fishing hold still waits")
    eq(evaluate({ stormstrike_remaining = 0, wftotem_remaining = NONE }).action,
        "stormstrike", "rule 8b: an unknown Windfury Totem never prompts")
    eq(evaluate({ stormstrike_remaining = 0, goatotem_remaining = 0 }).action, "goa",
        "rule 8c: a due Grace of Air prompts the goa slot")
    eq(evaluate({ stormstrike_remaining = 0, goatotem_remaining = NONE }).action,
        "stormstrike", "rule 8c: an unknown Grace of Air never prompts")
    eq(evaluate({ goatotem_remaining = 0, stormstrike_remaining = 8,
        firenova_remaining = 0 }).action, "goa",
        "rule 8c outranks Fire Nova while Stormstrike is down")
    eq(evaluate({ wftotem_remaining = 5 }).action, "stormstrike",
        "rule 8b boundary: a non-due feed falls through")
    eq(evaluate({ goatotem_remaining = 5 }).action, "stormstrike",
        "rule 8c boundary: a non-due feed falls through")
    -- Higher rules still outrank both totems.
    eq(evaluate({ wftotem_remaining = 0, mw_stacks = 5 }).action, "weave",
        "rule 5 outranks a due Windfury Totem")
    eq(evaluate({ goatotem_remaining = 0, mw_stacks = 5 }).action, "weave",
        "rule 5 outranks a due Grace of Air")
    eq(evaluate({ wftotem_remaining = 0, twist_remaining = 0 }).action, "twist",
        "rule 7 outranks a due Windfury Totem")
end

-- Rules 3b / 8a / 8d / 13b: the APL UTILITY layer
-- (bench/rotation_gap_vs_apl_2026-10-20.md §5) - the Wrath Bloodlust party
-- cooldown, the Strength of Earth and Mana Spring totem upkeeps and the TBC
-- Frost Shock filler. Every arm is family-gated, threshold-exact and
-- unknown-hides: an unreadable totem slot or an unknown cooldown never
-- prompts.
do
    -- The helpers' own contracts (the APL's conditions per family).
    eq(sg.SOE_REFRESH_TBC, 5, "the TBC Strength of Earth refresh window is 5 s")
    eq(sg.SOE_REFRESH_DEFAULT, 0, "the default Strength of Earth window is 0 s (the empty slot)")
    eq(sg.MANA_SPRING_REFRESH_TBC, 5, "the TBC Mana Spring refresh window is 5 s")
    eq(sg.FILLER_SHOCK_FROST, "FROST", "the Frost Shock filler choice token")
    eq(sg.get_strength_of_earth_due("ERA", 0, false), true,
        "the Strength of Earth helper: an empty earth slot is due on Era-base")
    eq(sg.get_strength_of_earth_due("ERA", 5, false), false,
        "the Strength of Earth helper: a live totem is not due on Era-base")
    eq(sg.get_strength_of_earth_due("ERA", 0, true), false,
        "the Strength of Earth helper: the SoD build runs no Strength of Earth row")
    eq(sg.get_strength_of_earth_due("ERA", nil, false), false,
        "the Strength of Earth helper: an unreadable slot is never due")
    eq(sg.get_strength_of_earth_due("TBC", 0, false), true,
        "the Strength of Earth helper: TBC reads the empty slot as due")
    eq(sg.get_strength_of_earth_due("TBC", 5, false), true,
        "the Strength of Earth helper: the TBC 5 s refresh boundary is inclusive")
    eq(sg.get_strength_of_earth_due("TBC", 6, false), false,
        "the Strength of Earth helper: TBC waits for the 5 s refresh window")
    eq(sg.get_strength_of_earth_due("TBC", nil, false), false,
        "the Strength of Earth helper: an unknown TBC slot is never due")
    eq(sg.get_strength_of_earth_due("FOREVER", 0, false), true,
        "the Strength of Earth helper: Forever reads the empty slot as due")
    eq(sg.get_strength_of_earth_due("FOREVER", 3, false), false,
        "the Strength of Earth helper: a live Forever totem is not due")
    eq(sg.get_strength_of_earth_due("WRATH", 0, false), false,
        "the Strength of Earth helper: Wrath runs no Strength of Earth row")
    eq(sg.get_mana_spring_due("TBC", 0, false), true,
        "the Mana Spring helper: TBC reads the empty water slot as due")
    eq(sg.get_mana_spring_due("TBC", 5, false), true,
        "the Mana Spring helper: the TBC 5 s refresh boundary is inclusive")
    eq(sg.get_mana_spring_due("TBC", 6, false), false,
        "the Mana Spring helper: TBC waits for the 5 s refresh window")
    eq(sg.get_mana_spring_due("TBC", nil, false), false,
        "the Mana Spring helper: an unknown slot is never due")
    eq(sg.get_mana_spring_due("ERA", 0, false), false,
        "the Mana Spring helper: Era runs no Mana Spring row")
    eq(sg.get_mana_spring_due("WRATH", 0, false), false,
        "the Mana Spring helper: Wrath runs no Mana Spring row")
    eq(sg.get_mana_spring_due("FOREVER", 0, false), false,
        "the Mana Spring helper: the Forever Mana Spring row is a PRE-PULL row")

    -- Rule 3b: the Bloodlust party cooldown (the Wrath enhancement APL's
    -- i=1/i=2 row). Wrath-only; nil (an unknown spell) never prompts. The
    -- fall-through baseline is { stormstrike_remaining = 8, firenova_remaining
    -- = 5 }: nothing above the shock filler fires, so an unarmed answer is the
    -- shock filler ("earthshock").
    do
        local saved_family = pure.family
        pure.family = "WRATH"
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            bloodlust_remaining = 0 }).action,
            "bloodlust", "rule 3b: a ready Bloodlust prompts its slot")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            bloodlust_remaining = 30 }).action,
            "earthshock", "rule 3b: a Bloodlust on cooldown falls through")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            bloodlust_remaining = NONE }).action,
            "earthshock", "rule 3b: an unknown Bloodlust never prompts")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            bloodlust_remaining = 0, feralspirit_remaining = 0 }).action,
            "feralspirit", "rule 3 outranks the Bloodlust row")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            bloodlust_remaining = 0, sr_remaining = 0 }).action,
            "bloodlust", "rule 3b outranks Shamanistic Rage")
        pure.family = "ERA"
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            bloodlust_remaining = 0 }).action,
            "earthshock", "rule 3b: the Era token runs no Bloodlust row")
        pure.family = saved_family
    end

    -- Rule 8a: the Strength of Earth Totem upkeep (Era i=0, TBC Totems group
    -- row 3, Forever i=4). It sits with the other totem upkeeps, above the Era
    -- air totems (the Era APL ranks Strength of Earth first) and below the
    -- twist.
    do
        local saved_family = pure.family
        pure.family = "ERA"
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            strength_of_earth_remaining = 0 }).action,
            "strength_of_earth", "rule 8a: an empty earth slot prompts the upkeep")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            strength_of_earth_remaining = 5 }).action,
            "earthshock", "rule 8a: a live totem falls through on Era-base")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            strength_of_earth_remaining = NONE }).action,
            "earthshock", "rule 8a: an unknown earth slot never prompts")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            strength_of_earth_remaining = 0, wftotem_remaining = 0 }).action,
            "strength_of_earth", "rule 8a outranks the Era air totems")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            strength_of_earth_remaining = 0, goatotem_remaining = 0 }).action,
            "strength_of_earth", "rule 8a outranks the Grace of Air fallback")
        eq(evaluate({ twist_remaining = 0, strength_of_earth_remaining = 0 }).action,
            "twist", "rule 7 outranks the Strength of Earth upkeep")
        eq(evaluate({ stormstrike_remaining = 0, strength_of_earth_remaining = 0 }).action,
            "strength_of_earth", "rule 8a outranks Stormstrike")
        pure.family = "TBC"
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            strength_of_earth_remaining = 5 }).action,
            "strength_of_earth", "rule 8a: TBC refreshes at 5 s left")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            strength_of_earth_remaining = 6 }).action,
            "earthshock", "rule 8a boundary: TBC waits for the 5 s refresh window")
        pure.family = "WRATH"
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            strength_of_earth_remaining = 0 }).action,
            "earthshock", "rule 8a: Wrath runs no Strength of Earth row")
        pure.family = "FOREVER"
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            strength_of_earth_remaining = 0 }).action,
            "strength_of_earth", "rule 8a: Forever reads the empty earth slot")
        pure.family = saved_family
    end

    -- Rule 8d: the Mana Spring Totem upkeep (the TBC Totems group row 4).
    -- TBC-only; the SoD and Forever Mana Spring rows are PRE-PULL rows.
    do
        local saved_family = pure.family
        pure.family = "TBC"
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            mana_spring_remaining = 0 }).action,
            "mana_spring", "rule 8d: an empty water slot prompts the upkeep")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            mana_spring_remaining = 5 }).action,
            "mana_spring", "rule 8d: the TBC 5 s refresh boundary is inclusive")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            mana_spring_remaining = 6 }).action,
            "earthshock", "rule 8d boundary: TBC waits for the 5 s refresh window")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            mana_spring_remaining = NONE }).action,
            "earthshock", "rule 8d: an unknown water slot never prompts")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            strength_of_earth_remaining = 0, mana_spring_remaining = 0 }).action,
            "strength_of_earth", "rule 8a outranks the Mana Spring upkeep")
        pure.family = "ERA"
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            mana_spring_remaining = 0 }).action,
            "earthshock", "rule 8d: the Era token runs no Mana Spring row")
        pure.family = saved_family
    end

    -- Rule 13b: the TBC Frost Shock filler. It answers ONLY when the player
    -- states the APL's alternative "Filler Shock" choice, and then the Earth
    -- Shock filler (rules 14 and 17) stays silent - the APL's Shocks group
    -- picks ONE filler.
    do
        local saved_family = pure.family
        pure.family = "TBC"
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            shock_remaining = 0, filler_shock = "FROST", frostshock_remaining = 0 }).action,
            "frostshock", "rule 13b: the stated Frost Shock choice prompts Frost Shock")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            shock_remaining = 0 }).action,
            "earthshock", "rule 13b: without the choice the APL default (Earth Shock) stands")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            shock_remaining = 0, filler_shock = "FROST", frostshock_remaining = 30 }).action,
            nil, "rule 13b: Frost Shock on cooldown leaves the shock slot empty")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            shock_remaining = 0, filler_shock = "FROST", frostshock_remaining = NONE }).action,
            nil, "rule 13b: an unknown Frost Shock never prompts")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            shock_remaining = 0, filler_shock = "EARTH" }).action,
            "earthshock", "rule 13b: only the FROST token flips the filler")
        pure.family = "WRATH"
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            shock_remaining = 0, filler_shock = "FROST", frostshock_remaining = 0 }).action,
            "earthshock", "rule 13b: the choice is TBC-only (Wrath keeps Earth Shock)")
        pure.family = saved_family
    end
end

-- Rule 9b: the Searing Totem maintain (audit 2026-10-19 §2.6 S-17). The classic
-- default APL keeps Searing down once the fight is older than 20 s, the SoD
-- phase_6 APL past 30 s; the feed is the fire-slot reader (due) plus the fight
-- clock, and the SoD latch picks the gate on the shared ERA token. The rule is
-- ERA-only - the helper returns false on every other family, so no number is
-- invented for the TBC low-mana fallback or the Forever static maintain.
do
    eq(sg.SEARING_UPKEEP_FIGHT_GATE_ERA, 20, "the Era Searing fight gate is 20 s")
    eq(sg.SEARING_UPKEEP_FIGHT_GATE_SOD, 30, "the SoD Searing fight gate is 30 s")
    eq(sg.get_searing_upkeep_due("ERA", 25, true, false), true,
        "the Searing helper: Era-base past 20 s with the slot empty is due")
    eq(sg.get_searing_upkeep_due("ERA", 20, true, false), false,
        "the Searing helper: exactly 20 s is not yet due (the gate is exclusive)")
    eq(sg.get_searing_upkeep_due("ERA", 35, true, true), true,
        "the Searing helper: SoD past 30 s with the slot empty is due")
    eq(sg.get_searing_upkeep_due("ERA", 25, true, true), false,
        "the Searing helper: SoD waits for its 30 s gate")
    eq(sg.get_searing_upkeep_due("ERA", 25, false, false), false,
        "the Searing helper: a live Searing is never due")
    eq(sg.get_searing_upkeep_due("ERA", 25, nil, false), false,
        "the Searing helper: an unknown slot is never due")
    eq(sg.get_searing_upkeep_due("ERA", nil, true, false), false,
        "the Searing helper: an unknown fight age is never due")
    eq(sg.get_searing_upkeep_due("TBC", 25, true, false), false,
        "the Searing helper: TBC never fires (no sim threshold is quoted)")
    eq(sg.get_searing_upkeep_due("WRATH", 25, true, false), false,
        "the Searing helper: Wrath ranks Magma instead")
    eq(sg.get_searing_upkeep_due("FOREVER", 25, true, false), false,
        "the Searing helper: the Forever static maintain stays filed")
    -- The rule itself (ERA family).
    do
        local saved_family = pure.family
        pure.family = "ERA"
        eq(evaluate({ stormstrike_remaining = 8, searing_down = true,
            fight_elapsed = 25 }).action, "searing",
            "rule 9b: a due Searing Totem prompts the searing slot")
        eq(evaluate({ stormstrike_remaining = 8, searing_down = true,
            fight_elapsed = 10 }).action, "earthshock",
            "rule 9b boundary: a young fight never prompts the Searing")
        eq(evaluate({ stormstrike_remaining = 8, searing_down = false,
            fight_elapsed = 25 }).action, "earthshock",
            "rule 9b: a live Searing is never due")
        eq(evaluate({ stormstrike_remaining = 8, searing_down = nil,
            fight_elapsed = 25 }).action, "earthshock",
            "rule 9b: an unknown fire slot never prompts")
        eq(evaluate({ stormstrike_remaining = 8, searing_down = true,
            fight_elapsed = nil }).action, "earthshock",
            "rule 9b: an unknown fight age never prompts")
        eq(evaluate({ stormstrike_remaining = 0, searing_down = true,
            fight_elapsed = 25 }).action, "stormstrike",
            "rule 9 outranks the Searing maintain")
        pure.family = saved_family
    end
    eq(evaluate({ stormstrike_remaining = 8, searing_down = true,
        fight_elapsed = 25 }).action, "firenova",
        "rule 9b: outside the ERA token the Searing never fires")
end

-- Rule 11b: the Lightning Shield maintain (audit 2026-10-19 §2.6 S-19). The three
-- wowsims/wotlk enhancement APLs maintain it iff inactive, above Lava Lash and
-- below Fire Nova; the SoD phase_6 APL's i=8 row and the Forever APL's i=6 row
-- cast 10432 the same way. The family gate is the pure helper: WRATH, FOREVER
-- and the SoD build on the ERA token (the MW-rune latch) - the Era-base and TBC
-- sims run no Lightning Shield.
do
    eq(sg.get_lightningshield_family_gate("WRATH", false), true,
        "the Lightning Shield gate: Wrath runs the maintain")
    eq(sg.get_lightningshield_family_gate("FOREVER", false), true,
        "the Lightning Shield gate: Forever runs the maintain")
    eq(sg.get_lightningshield_family_gate("ERA", true), true,
        "the Lightning Shield gate: the SoD build on the Era token runs the maintain")
    eq(sg.get_lightningshield_family_gate("ERA", false), false,
        "the Lightning Shield gate: the Era-base build never runs the maintain")
    eq(sg.get_lightningshield_family_gate("ERA", nil), false,
        "the Lightning Shield gate: an unknown latch reads as Era-base")
    eq(sg.get_lightningshield_family_gate("TBC", false), false,
        "the Lightning Shield gate: TBC never runs the maintain")
    eq(sg.get_lightningshield_family_gate("TBC", true), false,
        "the Lightning Shield gate: TBC stays silent even with the latch")
    do
        local saved_family = pure.family
        pure.family = "WRATH"
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            lightningshield_due = true }).action,
            "lightningshield", "rule 11b: a due Lightning Shield prompts its slot")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            lightningshield_due = false }).action,
            "earthshock", "rule 11b: an up-to-date shield never prompts")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            lightningshield_due = nil }).action,
            "earthshock", "rule 11b: an unknown shield read never prompts")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 0,
            lightningshield_due = true }).action, "firenova",
            "rule 11 outranks the Lightning Shield (the sim's order)")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            lightningshield_due = true, lavalash_remaining = 0 }).action, "lightningshield",
            "rule 11b outranks a ready Lava Lash (the sim's order)")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            lightningshield_due = true, lavalash_remaining = 5 }).action, "lightningshield",
            "rule 11b outranks a ready Lava Lash and the shock filler")
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            lightningshield_due = false, lavalash_remaining = 5 }).action, "earthshock",
            "rule 11b falls to the shock filler when the shield is up")
        -- The SoD build on the Era token: the latch opens the maintain.
        pure.family = "ERA"
        eq(evaluate({ stormstrike_remaining = 8, mw_observed = true,
            lightningshield_due = true }).action,
            "lightningshield", "rule 11b: the SoD build prompts the maintain")
        eq(evaluate({ stormstrike_remaining = 8, mw_observed = false,
            lightningshield_due = true }).action,
            "earthshock", "rule 11b: the Era-base build never prompts the maintain")
        eq(evaluate({ stormstrike_remaining = 8, mw_observed = nil,
            lightningshield_due = true }).action,
            "earthshock", "rule 11b: an unknown latch never prompts the maintain")
        -- Forever (the Forever APL's i=6 row).
        pure.family = "FOREVER"
        eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
            lightningshield_due = true }).action,
            "lightningshield", "rule 11b: Forever prompts the maintain")
        pure.family = saved_family
    end
    eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
        lightningshield_due = true }).action,
        "earthshock", "rule 11b: outside the gated families the shield never fires")
end

-- Rules 10-17: Magma maintain, Fire Nova (Era/Forever/Fire-Ele-gated), Lava Lash,
-- Chain Lightning (skeleton), the shock-capped Earth Shock, Molten Blast, the
-- Forever Nova and the Era-aware shock filler.
do
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = 0 }).action, "magma",
        "rule 10: a due Magma Totem -> magma")
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = 3 }).action, "magma",
        "rule 10 boundary: exactly the refresh window prompts")
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = 3.001 }).action, "firenova",
        "rule 10 boundary: just above the refresh window falls to Fire Nova")
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = NONE }).action, "firenova",
        "rule 10: an unknown Magma never prompts")
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = 2, magma_refresh = 1 }).action,
        "firenova", "rule 10: a custom refresh narrows the window")
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = 2, magma_refresh = NONE }).action,
        "magma", "rule 10: a missing refresh falls back to 3")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0 }).action, "firenova",
        "rule 11: Nova ready with SS down -> firenova")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = NONE }).action,
        "firenova", "rule 11: an unreadable Nova cooldown reads as ready")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 0,
        lavalash_remaining = 0 }).action, "firenova",
        "rule 11 outranks a ready Lava Lash")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 0,
        lavalash_remaining = 0, magma_remaining = 0 }).action, "magma",
        "rule 10 outranks a ready Fire Nova")
    -- Era runs no Fire Nova (Searing holds the fire slot there).
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 0 }).action,
        "firenova", "rule 11: Nova fires outside Era and Forever")
    do
        local saved_family = pure.family
        pure.family = "ERA"
        eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 0 }).action,
            "earthshock", "rule 11: Era never fires Nova (falls to the filler)")
        pure.family = "FOREVER"
        eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 0 }).action,
            "earthshock", "rule 11: Forever ranks Nova below Earth Shock")
        pure.family = saved_family
    end
    -- A live Fire Elemental is never replaced by Nova.
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 0,
        fireele_active = true, lavalash_remaining = 5 }).action, "earthshock",
        "rule 11: a live Fire Elemental suppresses Nova")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 0,
        fireele_active = false, lavalash_remaining = 5 }).action, "firenova",
        "rule 11: a downed Elemental releases Nova")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
        lavalash_remaining = 0 }).action, "lavalash",
        "rule 12: a ready Lava Lash answers with SS and Nova down")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
        lavalash_remaining = 5 }).action, "earthshock",
        "rule 12 boundary: Lava Lash on cooldown falls to the shock filler")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
        lavalash_remaining = NONE }).action, "earthshock",
        "rule 12: an unknown Lava Lash never prompts")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5 }).action,
        "earthshock", "rule 17: the shock filler answers with everything else down")
    local out = evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5 })
    eq(out.hold, false, "rule 17: the filler carries no hold")
    eq(out.hold_text, nil, "rule 17: the filler carries no hold text")
end

-- Rule 13: multi-target Chain Lightning (SoD MW >= 4 with 2+ targets). SKELETON:
-- without the enemy-count sensor the feed is nil and the rule stays dead.
do
    local chain = { stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
        lavalash_remaining = 5, shock_remaining = 5 }
    eq(evaluate(chain).action, "earthshock",
        "rule 13: an unknown target count never chains (falls to the filler)")
    chain.target_count = 1
    chain.mw_stacks = 5
    eq(evaluate(chain).action, "weave",
        "rule 5 outranks the chain at five stacks even with targets")
    chain.mw_stacks = 4
    chain.target_count = 1
    eq(evaluate(chain).action, "earthshock",
        "rule 13 boundary: one target never chains")
    chain.target_count = 2
    eq(evaluate(chain).action, "chainlightning",
        "rule 13: four stacks with two targets chains")
    chain.mw_stacks = 3
    eq(evaluate(chain).action, "earthshock",
        "rule 13 boundary: three stacks never chain")
    chain.mw_stacks = 4
    chain.mw_available = false
    eq(evaluate(chain).action, "earthshock",
        "rule 13 gate: no Maelstrom never chains")
end

-- Rules 14-15: the shock-capped Earth Shock and Molten Blast (SoD: ES and Molten
-- alternate on the shock global).
do
    local shock_down = { stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
        lavalash_remaining = 5, shock_remaining = 8 }
    eq(evaluate(shock_down).action, "earthshock",
        "rule 14 boundary: the fallback answers on a running shock cooldown")
    local shock_ready = { stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
        lavalash_remaining = 5, shock_remaining = 0 }
    eq(evaluate(shock_ready).action, "earthshock",
        "rule 14: a ready shock answers Earth Shock")
    shock_ready.moltenblast_remaining = 0
    eq(evaluate(shock_ready).action, "earthshock",
        "rule 14 outranks a ready Molten Blast")
    shock_down.moltenblast_remaining = 0
    eq(evaluate(shock_down).action, "moltenblast",
        "rule 15: Molten Blast answers below a running shock cooldown")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
        lavalash_remaining = 5, shock_remaining = 8, moltenblast_remaining = NONE }).action,
        "earthshock", "rule 15: an unknown Molten Blast never prompts")
end

-- Rule 16: Forever Fire Nova (free on Clearcasting, else a mana dump above 10%).
do
    local saved_family = pure.family
    pure.family = "FOREVER"
    local base = { stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 0,
        lavalash_remaining = 5, shock_remaining = 8 }
    eq(evaluate(base).action, "earthshock",
        "rule 16: Forever with no proc and low mana holds Nova for the filler")
    base.clearcasting_active = true
    eq(evaluate(base).action, "firenova",
        "rule 16: Forever Clearcasting fires Nova")
    base.clearcasting_active = nil
    base.mana_fraction = 0.05
    eq(evaluate(base).action, "earthshock",
        "rule 16: Forever mana at 5% holds Nova")
    base.mana_fraction = 0.11
    eq(evaluate(base).action, "firenova",
        "rule 16: Forever mana above 10% dumps Nova")
    base.mana_fraction = nil
    eq(evaluate(base).action, "earthshock",
        "rule 16: Forever never dumps Nova on unknown mana")
    pure.family = saved_family
end

-- Rule 17: the Era-aware shock filler (Era-base at mana < 50% stays silent - the
-- Era sim casts no filler there).
do
    local saved_family = pure.family
    pure.family = "ERA"
    local low = { stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
        lavalash_remaining = 5, shock_remaining = 0, mana_fraction = 0.2,
        flameshock_allowed = false }
    local low_out = evaluate(low)
    eq(low_out.action, nil, "rule 17: Era-base at low mana prompts nothing")
    eq(low_out.hold, false, "rule 17: the silence carries no hold")
    low.mana_fraction = 0.6
    eq(evaluate(low).action, "earthshock",
        "rule 17: Era-base at healthy mana fills Earth Shock")
    low.mana_fraction = nil
    eq(evaluate(low).action, "earthshock",
        "rule 17: Era-base with unknown mana keeps the old filler")
    low.flameshock_allowed = true
    low.mana_fraction = 0.2
    eq(evaluate(low).action, "earthshock",
        "rule 17: SoD (allowed) fills at low mana")
    pure.family = saved_family
end

-- Frost Shock is never prompted: no slot, no rule, no output.
do
    local battery = {
        {}, { mw_stacks = 5 }, { flameshock_remaining = NONE },
        { twist_remaining = 0 }, { stormstrike_remaining = 8, mw_stacks = 3 },
        { stormstrike_remaining = 8, mw_stacks = 0 },
        { stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5 },
        { fireele_remaining = 0 }, { feralspirit_remaining = 0 },
        { stormstrike_remaining = 8, magma_remaining = 0 },
        { stormstrike_remaining = 8, firenova_remaining = 5, lavalash_remaining = 0 },
        { sr_remaining = 0 },
        { stormstrike_remaining = 8, mw_stacks = 4, firenova_remaining = 5,
            lavalash_remaining = 5, shock_remaining = 5, target_count = 2 },
        { stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
            lavalash_remaining = 5, shock_remaining = 8, moltenblast_remaining = 0 },
    }
    local frost_seen = false
    for i = 1, #battery do
        local action = evaluate(battery[i]).action
        if type(action) == "string" and action:find("frost") then
            frost_seen = true
        end
    end
    check(not frost_seen, "no engine output ever names Frost Shock")
end

-- Frozen fields / nil-safety.
do
    local out = {
        action = "stale", hold = "stale", hold_text = "STALE", filler_slot = "stale",
        judge_slot = "stale", rotation_key = "stale", waiting_judgement = true,
    }
    sg.evaluate(inp({ casting = true }), out)
    eq(out.action, nil, "a reused out table has action overwritten")
    eq(out.hold, true, "a reused out table has hold overwritten")
    eq(out.hold_text, "RIDE", "a reused out table has hold_text overwritten")
    eq(out.filler_slot, nil, "a reused out table has filler_slot overwritten")
    eq(out.judge_slot, nil, "a reused out table has judge_slot overwritten")
    eq(out.rotation_key, nil, "a reused out table has rotation_key overwritten")
    eq(out.waiting_judgement, false, "a reused out table has waiting_judgement overwritten")

    local ok, err = pcall(sg.evaluate)
    check(ok, "evaluate with no arguments does not error (" .. tostring(err) .. ")")
    ok, err = pcall(sg.evaluate, nil, nil)
    check(ok, "evaluate(nil, nil) does not error (" .. tostring(err) .. ")")
    local fallback = sg.evaluate(inp({ mw_stacks = 5 }))
    eq(fallback.action, "weave", "evaluate can allocate its own out table")

    local frozen = inp({})
    local before_ss = frozen.stormstrike_remaining
    sg.evaluate(frozen, {})
    eq(frozen.stormstrike_remaining, before_ss, "evaluate never writes back into its inputs")

    local NaN = 0 / 0
    eq(evaluate({ mw_stacks = NaN, flameshock_remaining = NaN, stormstrike_remaining = NaN }).action,
        "stormstrike", "NaN inputs cannot match a rule and fall to the off-cooldown read")
    eq(evaluate({ mw_stacks = NaN, flameshock_remaining = 5, stormstrike_remaining = 8 }).action,
        "firenova", "a NaN stack count cannot reach the weave rule and falls to Fire Nova")
end

--=========================================================================================
-- 1) Sandbox: compat + utils + nextaction_ui + shaman_guide + weave + classes/shaman
--=========================================================================================
local SPELL_INFOS = {
    [403] = { name = "Lightning Bolt", icon = "icon_lb_r1", cast_ms = 3000 },
    [25449] = { name = "Lightning Bolt", icon = "icon_lb", cast_ms = 2500 },
    [25448] = { name = "Lightning Bolt", icon = "icon_lb9", cast_ms = 2000 },
    -- Wrath Lightning Bolt max rank for the M1 sub-5 hardcast (sim source:
    -- wowsims/wotlk sim/shaman/lightning_bolt.go 49238, base cast 2500 ms).
    [49238] = { name = "Lightning Bolt", icon = "icon_lb_wrath", cast_ms = 2500 },
    [25442] = { name = "Chain Lightning", icon = "icon_cl", cast_ms = 2000 },
    [17364] = { name = "Stormstrike", icon = "icon_ss" },
    [8050] = { name = "Flame Shock", icon = "icon_fs" },
    [1535] = { name = "Fire Nova Totem", icon = "icon_nova" },
    [8042] = { name = "Earth Shock", icon = "icon_es" },
    [8512] = { name = "Windfury Totem", icon = "icon_wf" },
    -- Wrath slots: Feral Spirit is repo-verified; Fire Elemental / Magma / Lava
    -- Lash ship best-recall ids marked UNCONFIRMED in the module (the known gate
    -- is what the tests exercise, so the fixture marks them known explicitly).
    [51533] = { name = "Feral Spirit", icon = "icon_feral" },
    [2894] = { name = "Fire Elemental Totem", icon = "icon_fireele" },
    [8190] = { name = "Magma Totem", icon = "icon_magma" },
    [60103] = { name = "Lava Lash", icon = "icon_lavalash" },
    -- Fixture-only Lava Burst (the SoD rune choice is name-probed, so the id only
    -- needs to be numeric here).
    [51505] = { name = "Lava Burst", icon = "icon_lava", cast_ms = 2000 },
    -- Fixture-only stand-in for an unconfirmed higher Windfury Totem rank: not in
    -- the addon's twist id table, so only the live-name resolution path stamps it.
    [10613] = { name = "Windfury Totem", icon = "icon_wf" },
    -- The APL utility layer (bench/rotation_gap_vs_apl_2026-10-20.md §5): the
    -- Bloodlust party cooldown, the Strength of Earth and Mana Spring totems and
    -- the TBC Frost Shock - the ids are the sims' own (the fixture marks them
    -- known where the test needs the known gate to open).
    [2825] = { name = "Bloodlust", icon = "icon_bloodlust" },
    [10442] = { name = "Strength of Earth Totem", icon = "icon_soe" },
    [25570] = { name = "Mana Spring Totem", icon = "icon_mana_spring" },
    [25464] = { name = "Frost Shock", icon = "icon_frostshock" },
    -- Fixture-only SoD rune names (the addon's name feeds resolve these the way a
    -- SoD client resolves its runes).
    [51600] = { name = "Feral Spirit", icon = "icon_feral_sod" },
    [51601] = { name = "Lava Lash", icon = "icon_lavalash_sod" },
    [51602] = { name = "Molten Blast", icon = "icon_molten", cast_ms = 0 },
    [51603] = { name = "Shamanistic Rage", icon = "icon_sr_sod" },
    -- Shamanistic Rage (TBC id) + Chain Lightning multi-target rank for the new
    -- slots' icons.
    [30823] = { name = "Shamanistic Rage", icon = "icon_sr" },
    [10605] = { name = "Chain Lightning", icon = "icon_cl_multi" },
    [425339] = { name = "Molten Blast", icon = "icon_molten" },
    -- Era static totems (G2): sim-sourced rank-1 ids, both UNCONFIRMED in the
    -- module (known-gated, so the fixture marks them explicitly per test).
    [10614] = { name = "Windfury Totem", icon = "icon_wf_era" },
    [10627] = { name = "Grace of Air Totem", icon = "icon_goa" },
    -- The two maintain slots (S-19 / S-17): the shipped ids are UNCONFIRMED, so
    -- the client's own spell data answers by NAME and re-points the slot icon.
    -- The fixture ids are test-owned (never shipped): they stand for "whatever
    -- the client answers", so the resolution is provable.
    [9201] = { name = "Lightning Shield", icon = "icon_ls" },
    [9202] = { name = "Searing Totem", icon = "icon_searing" },
    -- The Call of the Elements (S-20 / U-10): the shipped id 66842 is
    -- CLIENT-SOURCED (the clients' own Constants.lua totem-multi-cast list), so
    -- the fixture carries it as the shipped id.
    [66842] = { name = "Call of the Elements", icon = "icon_coe" },
}

local MODULES = { "compat.lua", "utils.lua", "guard.lua", "nextaction_ui.lua", "shaman_guide.lua",
    "weave.lua", "classes/shaman.lua" }

local function make_fontstring()
    local f = { hidden = false }
    function f:SetPoint() end
    function f:SetJustifyH() end
    function f:SetShadowColor() end
    function f:SetShadowOffset() end
    function f:SetFont(path, size, flags) f.font = { path, size, flags }; return true end
    function f:SetText(text) f.text = text end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:Hide() f.hidden = true end
    function f:Show() f.hidden = false end
    function f:IsShown() return not f.hidden end
    return f
end

local function make_texture()
    local t = { hidden = true }
    function t:SetDrawLayer() end
    function t:SetAllPoints() end
    function t:SetTexCoord(l, r, top, bottom) t.texcoord = { l, r, top, bottom } end
    function t:SetTexture(tex) t.texture = tex end
    function t:SetColorTexture() end
    function t:SetWidth(w) t.width = w end
    function t:SetHeight(h) t.height = h end
    function t:SetPoint() end
    function t:ClearAllPoints() end
    function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
    function t:IsShown() return not t.hidden end
    return t
end

local function make_frame(name)
    local f = { name = name, shown = false }
    function f:SetSize(w, h) f.width, f.height = w, h end
    function f:SetPoint(point, anchor, rel_point, x, y)
        f.points = f.points or {}
        f.points[#f.points + 1] = { point, anchor, rel_point, x, y }
    end
    function f:ClearAllPoints() f.points = nil end
    function f:SetFrameStrata() end
    function f:SetClampedToScreen() end
    function f:RegisterForDrag() end
    function f:SetScript(event, fn)
        f.scripts = f.scripts or {}
        f.scripts[event] = fn
    end
    function f:GetScript(event) return f.scripts and f.scripts[event] or nil end
    function f:Show() f.shown = true end
    function f:Hide() f.shown = false end
    function f:IsShown() return f.shown end
    function f:SetAlpha(a) f.alpha = a end
    function f:SetScale(s) f.scale = s end
    function f:GetScale() return f.scale or 1 end
    function f:SetMovable(m) f.movable = m end
    function f:EnableMouse(m) f.mouse = m end
    function f:GetFrameLevel() return 5 end
    function f:SetFrameLevel(l) f.level = l end
    function f:GetName() return f.name end
    function f:GetCenter() return 50, 60 end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:CreateTexture() return make_texture() end
    function f:CreateFontString() return make_fontstring() end
    function f:SetBackdrop(backdrop) f.backdrop = backdrop end
    function f:SetBackdropBorderColor(r, g, b, a) f.border_color = { r, g, b, a } end
    function f:SetCooldown(start, duration)
        f.cooldown_sets = (f.cooldown_sets or 0) + 1
        f.cooldown_start, f.cooldown_duration = start, duration
    end
    function f:SetReverse(reverse) f.reverse = reverse end
    function f:SetHideCountdownNumbers(flag) f.hide_numbers = flag end
    function f:SetAllPoints() end
    return f
end

local function build(opts)
    opts = opts or {}
    local sb = {
        clock = 0,
        frames = 0,
        known = opts.known or { [25449] = true, [25442] = true },
        auras = opts.auras or {},
        target_auras = opts.target_auras or {},
        cooldowns = {},
        hide_spells = false,
        aura_calls = 0,
        target_aura_calls = 0,
    }

    local env = setmetatable({}, { __index = _G })
    env.WOW_PROJECT_ID = 5
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.GetTimePreciseSec = function() return sb.clock end
    env.GetTime = function() return sb.clock end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.GetLocale = function() return "enUS" end
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", 30300 end
    env.UIParent = make_frame("UIParent")
    env.UIParent.GetCenter = function() return 0, 0 end
    env.CreateFrame = function(...)
        sb.frames = sb.frames + 1
        return make_frame(select(2, ...))
    end
    env.GetSpellInfo = function(spell)
        if sb.hide_spells then
            return nil
        end
        local info = SPELL_INFOS[spell]
        local id = spell
        if info == nil and type(spell) == "string" then
            -- Name-vs-id: TBC queries by NAME. The fixture answers the highest
            -- KNOWN rank carrying that name (nil when none is known), so the
            -- TBC catalogue resolves the same current rank the Era id walk
            -- finds. The SoD Lava Burst probe (unique name) rides the same
            -- path with its numeric id.
            local best_id, best_info = nil, nil
            for candidate_id, candidate in pairs(SPELL_INFOS) do
                if candidate.name == spell and sb.known[candidate_id] == true then
                    if best_id == nil or candidate_id > best_id then
                        best_id, best_info = candidate_id, candidate
                    end
                end
            end
            -- Unranked names (Stormstrike, totems, SoD runes): answer when any
            -- rank is known OR when the name is not rank-gated (the fixture
            -- marks them known explicitly where the test needs them).
            if best_info == nil then
                for candidate_id, candidate in pairs(SPELL_INFOS) do
                    if candidate.name == spell then
                        -- Prefer an explicitly-known id; otherwise the first
                        -- (unranked spells have a single id, so this is exact).
                        if sb.known[candidate_id] == true then
                            best_id, best_info = candidate_id, candidate
                            break
                        end
                        if best_id == nil then
                            best_id, best_info = candidate_id, candidate
                        end
                    end
                end
                -- Ranked families (LB/CL) with no known rank stay unknown.
                if spell == "Lightning Bolt" or spell == "Chain Lightning" then
                    if best_id ~= nil and sb.known[best_id] ~= true then
                        best_id, best_info = nil, nil
                    end
                end
            end
            info, id = best_info, best_id
        end
        if info then
            return info.name, nil, info.icon, info.cast_ms or 0, 0, 0, id
        end
        return nil
    end
    env.IsSpellKnown = function(id)
        if sb.known[id] == true then
            return true
        end
        -- TBC name leg (bench/lessons.md): the same known ranks answer by NAME.
        if type(id) == "string" then
            for candidate_id, candidate in pairs(SPELL_INFOS) do
                if candidate.name == id and sb.known[candidate_id] == true then
                    return true
                end
            end
        end
        return nil
    end
    env.UnitAura = function(unit, index, filter)
        local entry
        if unit == "target" then
            sb.target_aura_calls = sb.target_aura_calls + 1
            entry = sb.target_auras[index]
        else
            sb.aura_calls = sb.aura_calls + 1
            entry = sb.auras[index]
        end
        if not entry then return nil end
        return entry.name, nil, entry.count, nil, entry.duration, entry.expiration,
            entry.source, nil, nil, entry.spell_id
    end
    env.GetSpellCooldown = function(id)
        -- Name-vs-id: TBC queries by NAME, Era by id; the fixture answers both
        -- through the same SPELL_INFOS names so both resolutions pin identically.
        local key = id
        if type(id) == "string" then
            for candidate_id, candidate in pairs(SPELL_INFOS) do
                if candidate.name == id and sb.cooldowns[candidate_id] then
                    key = candidate_id
                    break
                end
            end
            -- Direct name-keyed cooldowns (SoD name feeds) also answer.
            if sb.cooldowns[id] and not sb.cooldowns[key] then
                key = id
            end
        end
        local cd = sb.cooldowns[key]
        if cd then return cd.start, cd.duration, 1, 1 end
        return 0, 0, 1, 1
    end
    env.UnitCastingInfo = function() return nil end
    env.UnitChannelInfo = function() return nil end
    env.UnitSpellHaste = function() return 0 end
    -- Air-slot totem fixture for the twist reconciliation: nil serves
    -- MayReturnNothing (no totem / no client read), otherwise the client's
    -- haveTotem, totemName, startTime, duration, icon, modRate, spellID shape.
    -- fire_totem serves the same shape for the fire slot (Magma maintain);
    -- earth_totem (slot 2) and water_totem (slot 3) serve the APL utility
    -- layer's Strength of Earth and Mana Spring clocks.
    env.GetTotemInfo = function(slot)
        if slot == 1 then
            local t = sb.fire_totem
            if t == nil then return nil end
            return t.have, t.name, t.start, t.duration, t.icon, t.modrate, t.spell
        end
        if slot == 2 then
            local t = sb.earth_totem
            if t == nil then return nil end
            return t.have, t.name, t.start, t.duration, t.icon, t.modrate, t.spell
        end
        if slot == 3 then
            local t = sb.water_totem
            if t == nil then return nil end
            return t.have, t.name, t.start, t.duration, t.icon, t.modrate, t.spell
        end
        local t = sb.totem
        if slot ~= 4 or t == nil then return nil end
        return t.have, t.name, t.start, t.duration, t.icon, t.modrate, t.spell
    end
    env.RAID_CLASS_COLORS = { SHAMAN = { r = 0.0, g = 0.44, b = 0.87 } }

    local ST = {
        SHAMAN = {},
        player_class = "SHAMAN",
        interfaces_are_initialised = true,
        in_combat = false,
        mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false },
        offhand = { has_weapon = false },
        gcd = { expires = 0 },
        latency = { world_ms = 0 },
    }
    local class_db = {
        -- The real SHAMAN defaults (config_presets.lua) plus the guide keys; enabled
        -- here so the display half can be exercised (the shipped default false is
        -- pinned by the text parity section below).
        weave_enabled = true,
        weave_mw_enabled = true,
        weave_marker_size = 6,
        weave_marker_alpha = 1,
        weave_spark_width = 3,
        weave_spark_height = 15,
        weave_spark_alpha = 0.95,
        show_shaman_breakpoint_markers = true,
        show_shaman_windfury_icd = true,
        show_shaman_flame_shock_bar = true,
        show_shaman_cooldown_badges = true,
        show_shaman_shield_charges = true,
        nextaction_enabled = true,
        nextaction_locked = true,
        nextaction_visibility_key = "in_combat",
        nextaction_icon_size = 45,
        nextaction_x = 0,
        nextaction_y = -180,
        guide_flameshock_refresh = 0,
    }
    function ST.get_class_table() return class_db end
    function ST.get_visuals_frame(_, hand)
        if hand == "offhand" then return sb.offhand_visuals end
        return sb.visuals
    end
    function ST.get_bar_visuals_width_and_height() return 100, 15 end
    function ST.get_hand_table()
        return { text_font = "font" }
    end

    local visuals = {}
    function visuals:CreateTexture() return make_texture() end
    function visuals:CreateFontString() return make_fontstring() end
    sb.visuals = visuals
    local offhand_visuals = {}
    function offhand_visuals:CreateTexture() return make_texture() end
    function offhand_visuals:CreateFontString() return make_fontstring() end
    sb.offhand_visuals = offhand_visuals

    local LCG = {}
    function LCG.PixelGlow_Start() end
    function LCG.PixelGlow_Stop() end
    local LSM = {}
    function LSM.Fetch(_, mediatype)
        if mediatype == "border" then return "border_tex" end
        if mediatype == "font" then return "Fonts\\FRIZQT__.TTF" end
        return nil
    end
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        elseif major == "LibCustomGlow-1.0" then
            return LCG
        elseif major == "LibSharedMedia-3.0" then
            return LSM
        end
        return {}
    end

    -- compat.lua reads several legacy globals through _G (annotation-safe on
    -- Mainline-code clients); mirror every sandbox stub for the duration of the loads,
    -- then restore _G exactly.
    local mirrored = {}
    for name, value in pairs(env) do
        mirrored[name] = { present = rawget(_G, name) ~= nil, value = rawget(_G, name) }
        _G[name] = value
    end

    local st = {}
    local modules = opts.modules or MODULES
    for i = 1, #modules do
        local chunk = assert(loadfile(ROOT .. modules[i]))
        setfenv(chunk, env)
        chunk("SwedgeTimer", st)
        -- Class files register their body as a loader (operator order 2026-10-21:
        -- only the selected class executes). This sandbox activates the class it
        -- loads, exactly as main.lua does at init.
        local class = modules[i]:match("classes/(%a+)%.lua")
        if class and type(st.class_loaders) == "table"
            and type(st.class_loaders[class:upper()]) == "function" then
            st.class_loaders[class:upper()]()
        end
    end

    for name, previous in pairs(mirrored) do
        _G[name] = previous.value
        if not previous.present then _G[name] = nil end
    end

    sb.env, sb.st, sb.ST, sb.class_db = env, st, ST, class_db
    function sb.advance(dt) sb.clock = sb.clock + dt end
    return sb
end

--=========================================================================================
-- 2) The provider through the real modules: contract shape, post_init, gather
--=========================================================================================
local sandbox = build()
local ST, st = sandbox.ST, sandbox.st
local class_db = sandbox.class_db

check(type(st.shaman_guide) == "table", "the provider sandbox loads the pure engine")
check(type(ST.SHAMAN.guide) == "table", "classes/shaman.lua defines ST.SHAMAN.guide")
check(type(ST.SHAMAN.guide.gather) == "function", "the shaman guide has gather")
check(type(ST.SHAMAN.guide.evaluate) == "function", "the shaman guide has evaluate")
check(type(ST.SHAMAN.resolve_guide_icons) == "function", "the weave-icon resolver is exported")

-- post_init resolves the catalogue + weave icon and builds the frame through the hook.
ST.in_combat = true
ST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
ST.gcd = { expires = 0 }
ST.SHAMAN.post_init(ST)
local ui = st.nextaction_ui
check(ui.frame ~= nil, "post_init builds the guide frame through the real hook")
check(ui.inert ~= true, "the shaman provider is live")
eq(ui.get_provider(ST), ST.SHAMAN.guide, "the shaman guide resolves as the frame's provider")

local slots = ST.SHAMAN.guide.slots
eq(#slots, 22, "twenty-two slots are declared")
local expected_keys = { "stormstrike", "flameshock", "weave", "firenova", "earthshock", "twist",
    "feralspirit", "fireele", "magma", "lavalash",
    "shamanisticrage", "chainlightning", "moltenblast", "wftotem", "goa",
    "lightningshield", "searing", "coe",
    "bloodlust", "strength_of_earth", "mana_spring", "frostshock" }
local expected_icons = { "icon_ss", "icon_fs", "icon_lb", "icon_nova", "icon_es", "icon_wf",
    "icon_feral", "icon_fireele", "icon_magma", "icon_lavalash",
    "icon_sr", "icon_cl_multi", "icon_molten", "icon_wf_era", "icon_goa",
    "icon_ls", "icon_searing", "icon_coe",
    "icon_bloodlust", "icon_soe", "icon_mana_spring", "icon_frostshock" }
for i = 1, #expected_keys do
    eq(slots[i].key, expected_keys[i], "slot " .. i .. " is " .. expected_keys[i])
end
-- The APL utility layer's four slots carry no swipe: a persistent totem has no
-- window to ride, and the two cooldowns ride the client-reported length.
for i = 19, #slots do
    eq(slots[i].cooldown_key, nil, "slot " .. i .. " carries no cooldown key")
    eq(slots[i].swipe_duration, nil, "slot " .. i .. " carries no swipe fallback")
end
eq(slots[1].cooldown_key, "stormstrike", "stormstrike's swipe is its client cooldown")
eq(slots[1].swipe_duration, 10, "stormstrike carries the base-cooldown swipe fallback")
eq(slots[2].cooldown_key, "flameshock", "flameshock's swipe is the tracker's debuff window")
eq(slots[2].swipe_duration, 12, "flameshock carries the Flame Shock swipe fallback")
eq(slots[3].cooldown_key, nil, "the weave slot carries no cooldown key")
eq(slots[4].cooldown_key, "firenova", "firenova's swipe is its client cooldown")
eq(slots[4].swipe_duration, 15, "firenova carries the 15 s totem swipe fallback")
eq(slots[5].cooldown_key, nil, "the earthshock slot carries no cooldown key")
eq(slots[6].cooldown_key, nil, "the twist skeleton carries no cooldown key")
eq(slots[7].cooldown_key, "feralspirit", "feralspirit's swipe is its client cooldown")
eq(slots[7].swipe_duration, 180, "feralspirit carries the Feral Spirit swipe fallback")
eq(slots[8].cooldown_key, "fireele", "fireele's swipe is its client cooldown")
eq(slots[8].swipe_duration, 600, "fireele carries the Fire Elemental swipe fallback")
eq(slots[9].cooldown_key, "magma", "magma's swipe is the fire-slot totem window")
eq(slots[9].swipe_duration, 20, "magma carries the totem-window swipe fallback")
eq(slots[10].cooldown_key, "lavalash", "lavalash names its client cooldown")
eq(slots[10].swipe_duration, nil, "lavalash carries no fallback (cooldown unconfirmed)")
eq(slots[11].spell_id, 30823, "shamanisticrage keeps the Shamanistic Rage id")
eq(slots[11].cooldown_key, "shamanisticrage", "shamanisticrage names its client cooldown")
eq(slots[11].swipe_duration, nil, "shamanisticrage carries no fallback (client length rides)")
eq(slots[12].spell_id, 10605, "chainlightning keeps the multi-target rank id")
eq(slots[12].cooldown_key, nil, "the chainlightning skeleton carries no cooldown key")
eq(slots[12].swipe_duration, nil, "the chainlightning skeleton carries no swipe fallback")
eq(slots[13].spell_id, 425339, "moltenblast shows the unconfirmed Molten Blast id")
eq(slots[13].cooldown_key, nil, "the moltenblast slot carries no cooldown key")
eq(slots[13].swipe_duration, nil, "the moltenblast slot carries no swipe fallback")
eq(slots[14].key, "wftotem", "the fourteenth slot is the Era Windfury Totem maintain")
eq(slots[14].spell_id, 10614, "wftotem shows the unconfirmed Windfury Totem id")
eq(slots[14].cooldown_key, nil, "the wftotem slot carries no cooldown key")
eq(slots[14].swipe_duration, nil, "the wftotem slot carries no swipe fallback")
eq(slots[15].key, "goa", "the fifteenth slot is the Era Grace of Air fallback")
eq(slots[15].spell_id, 10627, "goa shows the unconfirmed Grace of Air id")
eq(slots[15].cooldown_key, nil, "the goa slot carries no cooldown key")
eq(slots[15].swipe_duration, nil, "the goa slot carries no swipe fallback")
eq(slots[16].key, "lightningshield", "the sixteenth slot is the Wrath Lightning Shield maintain")
eq(slots[16].spell_id, 9201, "lightningshield shows the client's own Lightning Shield id")
eq(slots[16].cooldown_key, nil, "the lightningshield slot carries no cooldown key")
eq(slots[16].swipe_duration, nil, "the lightningshield slot carries no swipe fallback")
eq(slots[17].key, "searing", "the seventeenth slot is the Era Searing Totem maintain")
eq(slots[17].spell_id, 9202, "searing shows the client's own Searing Totem id")
eq(slots[17].cooldown_key, nil, "the searing slot carries no cooldown key")
eq(slots[17].swipe_duration, nil, "the searing slot carries no swipe fallback")
eq(slots[1].spell_id, 17364, "stormstrike keeps the spec's id")
eq(slots[2].spell_id, 8050, "flameshock keeps the spec's id")
eq(slots[3].spell_id, 25449, "post_init resolved the weave icon from the catalogue")
eq(slots[4].spell_id, 1535, "firenova keeps the Fire Nova Totem rank-1 id")
eq(slots[5].spell_id, 8042, "earthshock keeps the Earth Shock rank-1 id")
eq(slots[6].spell_id, 8512, "the twist skeleton shows the Windfury Totem id")
eq(slots[7].spell_id, 51533, "feralspirit keeps the Feral Spirit id")
eq(slots[8].spell_id, 2894, "fireele shows the unconfirmed Fire Elemental id")
eq(slots[9].spell_id, 8190, "magma shows the unconfirmed Magma Totem id")
eq(slots[10].spell_id, 60103, "lavalash shows the unconfirmed Lava Lash id")
eq(ST.SHAMAN.guide.labels.next_action, "Next action:", "labels.next_action is the default")
eq(ST.SHAMAN.guide.labels.hold, "HOLD", "labels.hold is the default")
eq(ST.SHAMAN.guide.labels.ride, "RIDE", "labels.ride is the default")
eq(ST.SHAMAN.guide.rotation_key, nil, "no rotation text source is declared")
eq(ST.SHAMAN.guide.rotation_names, nil, "no rotation name map is declared")

-- The frame: one icon per slot, in order.
eq(#ui.icons, 22, "the frame holds one icon per slot")
eq(sandbox.frames, 54, "frame count: group + hold + 22 icons/borders + 8 cooldowns")
for i = 1, #slots do
    eq(ui.icons[i].slot, slots[i], "icon " .. i .. " follows the slot declaration order")
    eq(ui.icons[i].icon.texture.texture, expected_icons[i],
        "icon " .. i .. " shows " .. expected_icons[i])
end
eq(ui.frame.label.text, "Next action:", "the label carries the default caption")
eq(ui.icons[1].remaining_key, "stormstrike_remaining", "the swipe fields derive from the key")
eq(ui.icons[2].duration_key, "flameshock_duration", "the duration field derives from the key")
eq(ui.icons[3].remaining_key, nil, "the weave slot carries no swipe fields")
eq(ui.icons[4].remaining_key, "firenova_remaining", "the firenova swipe fields derive from the key")
eq(ui.icons[5].remaining_key, nil, "the earthshock slot carries no swipe fields")
eq(ui.icons[6].remaining_key, nil, "the twist skeleton carries no swipe fields")
eq(ui.icons[7].remaining_key, "feralspirit_remaining", "the feralspirit swipe fields derive from the key")
eq(ui.icons[8].remaining_key, "fireele_remaining", "the fireele swipe fields derive from the key")
eq(ui.icons[9].remaining_key, "magma_remaining", "the magma swipe fields derive from the key")
eq(ui.icons[10].remaining_key, "lavalash_remaining", "the lavalash swipe fields derive from the key")
eq(ui.icons[10].duration_key, "lavalash_duration", "the lavalash duration field derives from the key")
eq(ui.icons[11].remaining_key, "shamanisticrage_remaining", "the shamanisticrage swipe fields derive from the key")
eq(ui.icons[11].duration_key, "shamanisticrage_duration", "the shamanisticrage duration field derives from the key")
eq(ui.icons[12].remaining_key, nil, "the chainlightning skeleton carries no swipe fields")
eq(ui.icons[12].duration_key, nil, "the chainlightning skeleton carries no duration field")
eq(ui.icons[13].remaining_key, nil, "the moltenblast slot carries no swipe fields")
eq(ui.icons[13].duration_key, nil, "the moltenblast slot carries no duration field")
eq(ui.icons[14].remaining_key, nil, "the wftotem slot carries no swipe fields")
eq(ui.icons[14].duration_key, nil, "the wftotem slot carries no duration field")
eq(ui.icons[15].remaining_key, nil, "the goa slot carries no swipe fields")
eq(ui.icons[15].duration_key, nil, "the goa slot carries no duration field")
eq(ui.icons[16].remaining_key, nil, "the lightningshield slot carries no swipe fields")
eq(ui.icons[16].duration_key, nil, "the lightningshield slot carries no duration field")
eq(ui.icons[17].remaining_key, nil, "the searing slot carries no swipe fields")
eq(ui.icons[17].duration_key, nil, "the searing slot carries no duration field")

-- No HUD mirror (deferred, the 13-vs-8 precedent): the Era totems are
-- guide-only until the HUD lane mirrors them, like the Wrath additions. The two
-- maintain mirrors (S-19 / S-17) ARE mirrored: they have a live read, so the row
-- carries them (nil = off - the options pass owns the default + the widget).
do
    local hud_keys = {}
    for i = 1, #ST.SHAMAN.HUD_SLOTS do
        hud_keys[ST.SHAMAN.HUD_SLOTS[i].key] = true
    end
    check(hud_keys.wftotem == nil, "deferred: the HUD declares no wftotem slot")
    check(hud_keys.goa == nil, "deferred: the HUD declares no goa slot")
    check(hud_keys.lightningshield == true, "mirrored: the HUD declares the lightningshield slot")
    check(hud_keys.searing == true, "mirrored: the HUD declares the searing slot")
    check(hud_keys.coe ~= nil, "mirrored: the HUD declares the Call of the Elements slot")
end
eq(ui.icons[10].duration_key, "lavalash_duration", "the lavalash duration field derives from the key")
eq(ui.icons[1].glow_key, nil, "the shaman slots carry no glow")

-- Every possible action output names a declared slot (through the real provider).
-- The sandbox is a TBC client, so the weave actions never appear here (the Wrath
-- block below pins them through the frame instead); the new cooldown/magma feeds
-- default to nil (unknown spells, no WRATH feed), so they fall through exactly
-- like the old chain.
do
    local provider = ST.SHAMAN.guide
    local function action_of(overrides)
        local inputs = inp(overrides)
        -- The provider sandbox is TBC: Maelstrom is unavailable, like the gather feeds.
        inputs.mw_available = false
        -- The provider battery predates the opt-in hold and the Era/Forever gates:
        -- enable the old hold and keep the neutral families for the delegation pins.
        inputs.stormstrike_hold_enabled = true
        local out = {}
        provider.evaluate(inputs, out)
        return out.action
    end
    local actions = {
        action_of({}),
        action_of({ mw_stacks = 5 }),
        action_of({ flameshock_remaining = NONE }),
        action_of({ stormstrike_remaining = 8, mw_stacks = 3 }),
        action_of({ stormstrike_remaining = 8, mw_stacks = 0 }),
        action_of({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5 }),
        action_of({ stormstrike_remaining = 0, windfury_icd_remaining = 0.5 }),
        action_of({ twist_remaining = 0 }),
        action_of({ fireele_remaining = 0 }),
        action_of({ feralspirit_remaining = 0 }),
        action_of({ fireele_remaining = 0, feralspirit_remaining = 0 }),
        action_of({ stormstrike_remaining = 8, magma_remaining = 0 }),
        action_of({ stormstrike_remaining = 8, firenova_remaining = 5, lavalash_remaining = 0 }),
        -- The battery feeds mana the way the live gather does (the TBC family
        -- default gates the threshold-less prompt on known mana).
        action_of({ sr_remaining = 0, mana_fraction = 0.05 }),
        action_of({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
            lavalash_remaining = 5, shock_remaining = 8, moltenblast_remaining = 0 }),
        -- The Era totems route through the same provider (the engine is
        -- feed-gated: the TBC sandbox would never feed these, so the battery
        -- feeds them directly to pin the action->slot wiring).
        action_of({ wftotem_remaining = 0 }),
        action_of({ goatotem_remaining = 0 }),
        action_of({ wftotem_remaining = 0, goatotem_remaining = 0 }),
    }
    eq(actions[1], "stormstrike", "the provider delegates to the pure engine (stormstrike)")
    eq(actions[2], "stormstrike", "TBC: five stacks fall through to Stormstrike, not the weave")
    eq(actions[3], "flameshock", "the provider delegates to the pure engine (flameshock)")
    eq(actions[4], "firenova", "MW5-only: stacked Maelstrom without MW falls to Fire Nova, never the weave")
    eq(actions[5], "firenova", "the provider delegates to the pure engine (firenova)")
    eq(actions[6], "earthshock", "the provider delegates to the pure engine (earthshock)")
    eq(actions[7], nil, "the fishing hold prompts no slot (WAIT overlay only)")
    eq(actions[8], "twist", "the provider delegates to the pure engine (twist skeleton)")
    eq(actions[9], "fireele", "the provider delegates to the pure engine (fireele)")
    eq(actions[10], "feralspirit", "the provider delegates to the pure engine (feralspirit)")
    eq(actions[11], "fireele", "Fire Elemental outranks Feral Spirit when both are ready")
    eq(actions[12], "magma", "the provider delegates to the pure engine (magma)")
    eq(actions[13], "lavalash", "the provider delegates to the pure engine (lavalash)")
    eq(actions[14], "shamanisticrage", "the provider delegates to the pure engine (shamanisticrage)")
    eq(actions[15], "moltenblast", "the provider delegates to the pure engine (moltenblast)")
    eq(actions[16], "wftotem", "the provider delegates to the pure engine (wftotem)")
    eq(actions[17], "goa", "the provider delegates to the pure engine (goa)")
    eq(actions[18], "wftotem", "Windfury outranks Grace of Air when both are due")
    local all_resolve = true
    for i = 1, #actions do
        if actions[i] ~= nil and ui.slot_index[actions[i]] == nil then
            all_resolve = false
        end
    end
    check(all_resolve, "every action the engine can return names a declared slot")
    local slots_have_keys = true
    for i = 1, #slots do
        if ui.slot_index[slots[i].key] == nil then
            slots_have_keys = false
        end
    end
    check(slots_have_keys, "every declared slot key is frame-addressable")
end

-- The FAMILY SCOPE (the release-gate blocker B1): the practice strip offers the
-- running CLIENT's slot set, so the class publishes one set per family and the
-- running build's own token (SOD on the ERA token) rides on top of it.
--
-- The engine side of that contract: an action the engine answers must name a
-- slot in that client's set - the panel adds the engine's own answers to the
-- strip, so an action outside the set would put a foreign button back. The
-- check runs through the REAL gather (the family gates live there, not in the
-- rules), so it is the answer the client would actually show.
do
    local saved_family = sandbox.st.family
    for _, client_family in ipairs({ "ERA", "TBC", "WRATH", "FOREVER" }) do
        sandbox.st.family = client_family
        local slot_keys = {}
        local family_slots = ST.SHAMAN.family_guide_slots(client_family)
        for i = 1, #family_slots do slot_keys[family_slots[i].key] = true end
        check(#family_slots > 0,
            "family scope: the " .. client_family .. " client carries a slot set")
        local live_inputs = ST.SHAMAN.guide.gather(ST, {})
        local live_out = {}
        ST.SHAMAN.guide.evaluate(live_inputs, live_out)
        if live_out.action ~= nil then
            check(slot_keys[live_out.action] == true,
                "family scope: the " .. client_family .. " answer (" .. tostring(live_out.action)
                    .. ") names a slot in its own set")
        end
    end
    -- The engine's own family gates and the family's slot set agree: a family
    -- whose gate admits a row carries that row (one direction: a gate that
    -- keeps a row silent on a build never removes the row from the set).
    local guide = sandbox.st.shaman_guide
    local gate_cases = {
        { gate = guide.get_lightningshield_family_gate, args = { "WRATH", false },
            key = "lightningshield" },
        { gate = guide.get_lightningshield_family_gate, args = { "FOREVER", false },
            key = "lightningshield" },
        { gate = guide.get_lightningshield_family_gate, args = { "ERA", true },
            key = "lightningshield", extra = "SOD" },
        { gate = guide.get_strength_of_earth_due, args = { "TBC", 0, false },
            key = "strength_of_earth" },
        { gate = guide.get_strength_of_earth_due, args = { "ERA", 0, false },
            key = "strength_of_earth" },
        { gate = guide.get_strength_of_earth_due, args = { "FOREVER", 0, false },
            key = "strength_of_earth" },
        { gate = guide.get_mana_spring_due, args = { "TBC", 0 },
            key = "mana_spring" },
        { gate = guide.get_searing_upkeep_due, args = { "ERA", 100, true, false },
            key = "searing" },
    }
    for _, case in ipairs(gate_cases) do
        local admitted = case.gate(unpack(case.args))
        if admitted == true then
            local family = case.args[1]
            local set_keys = {}
            local set_slots = ST.SHAMAN.family_guide_slots(family, case.extra)
            for i = 1, #set_slots do set_keys[set_slots[i].key] = true end
            check(set_keys[case.key] == true,
                "family scope: the " .. family .. " set carries the " .. case.key
                    .. " row its engine gate admits")
        end
    end
    -- The SoD build: the ERA token plus the rune basis. The build's own row
    -- (the Lightning Shield maintain) rides on the ERA set, and the shared
    -- rows stay.
    local era_set = {}
    for _, slot in ipairs(ST.SHAMAN.family_guide_slots("ERA")) do era_set[slot.key] = true end
    local sod_set = {}
    for _, slot in ipairs(ST.SHAMAN.family_guide_slots("ERA", "SOD")) do sod_set[slot.key] = true end
    check(era_set.lightningshield == nil,
        "family scope: the Era-base set carries no Lightning Shield row")
    check(sod_set.lightningshield == true,
        "family scope: the SoD build's set carries the Lightning Shield row")
    check(sod_set.stormstrike == true,
        "family scope: the SoD build's set keeps the shared rows")
    sandbox.st.family = saved_family
end

-- The gather into the caller-owned reused table.
sandbox.clock = 100
ST.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
ST.gcd = { expires = 100.5 }
ST.weave_is_casting = false
ST.weave_mw_stacks = 2
ST.weave_fs_duration = 12
ST.weave_fs_expires = 110
sandbox.cooldowns = { [17364] = { start = 100, duration = 8 } }

local gathered_target = {}
local gathered = ST.SHAMAN.guide.gather(ST, gathered_target)
eq(gathered, gathered_target, "gather writes into and returns the caller's table")
eq(gathered.speed, 3.0, "gather: speed")
near(gathered.swing_remaining, 2.0, 1e-9, "gather: swing_remaining")
near(gathered.gcd_remaining, 0.5, 1e-9, "gather: gcd_remaining")
eq(gathered.casting, false, "gather: the cast state")
eq(gathered.mw_stacks, 2, "gather: the Maelstrom stack count")
eq(gathered.weave_available, true, "gather: the resolved catalogue is available")
near(gathered.flameshock_remaining, 10, 1e-9, "gather: the tracker's Flame Shock window")
eq(gathered.flameshock_duration, 12, "gather: the Flame Shock swipe length")
near(gathered.stormstrike_remaining, 8, 1e-9, "gather: the real Stormstrike cooldown")
eq(gathered.stormstrike_duration, 8, "gather: the client-reported cooldown length")
eq(gathered.flameshock_refresh, 0, "gather: the refresh threshold default")

-- The TBC sandbox has no Maelstrom, no Windfury imbue and no air-totem read: the
-- gate is off, the ICD feed is unknown and the twist stub is nil, while Fire Nova
-- (no cooldown running) reads as ready. TBC keeps the Flame Shock maintain and
-- the Magma feed (audit 2026-10-19: TBC runs Magma as its default filler); the
-- hold opt-in reads off, mana is unknown (no UnitPower in the sandbox), and the
-- SoD/Forever feeds stay nil, so the chain runs unchanged apart from Magma.
eq(gathered.mw_available, false, "gather: TBC has no Maelstrom Weapon")
eq(gathered.flameshock_allowed, true, "gather: TBC keeps the Flame Shock maintain")
eq(gathered.stormstrike_hold_enabled, false, "gather: the hold opt-in reads off without the tint")
eq(gathered.mana_fraction, nil, "gather: an unreadable mana pool reads unknown")
eq(gathered.shock_remaining, 0, "gather: the shared shock cooldown reads ready")
eq(gathered.windfury_icd_remaining, nil, "gather: no ICD without the imbue")
eq(gathered.firenova_remaining, 0, "gather: Fire Nova reads as ready")
eq(gathered.firenova_duration, nil, "gather: a ready Nova latches no duration")
eq(gathered.fireele_active, nil, "gather: no Fire Elemental drop reads unknown")
eq(gathered.twist_remaining, nil, "gather: the twist stub stays nil")
eq(gathered.sr_remaining, nil, "gather: TBC with no SR cooldown running reads nil")
eq(gathered.sr_mana_threshold, 0.10, "gather: TBC carries the 10% SR gate")
eq(gathered.moltenblast_remaining, nil, "gather: TBC never feeds Molten Blast")
eq(gathered.target_count, nil, "gather: no enemy-count sensor feeds nil")
eq(gathered.clearcasting_active, false, "gather: no Clearcasting aura reads down")
eq(gathered.fireele_remaining, nil, "gather: TBC never feeds Fire Elemental")
eq(gathered.fireele_duration, nil, "gather: and latches no duration")
eq(gathered.feralspirit_remaining, nil, "gather: TBC never feeds Feral Spirit")
eq(gathered.feralspirit_duration, nil, "gather: and latches no duration")
eq(gathered.lavalash_remaining, nil, "gather: TBC never feeds Lava Lash")
eq(gathered.lavalash_duration, nil, "gather: and latches no duration")
eq(gathered.moltenblast_duration, nil, "gather: and latches no duration")
eq(gathered.magma_refresh, 3, "gather: the magma refresh reads the constant")
eq(gathered.mw_observed, false, "gather: the SoD MW-rune latch reads off without the rune")
eq(gathered.lightningshield_due, nil, "gather: TBC never feeds the Lightning Shield maintain")
eq(gathered.searing_down, nil, "gather: an unreadable fire slot never feeds the Searing due flag")

-- The TBC Magma feed is live (audit 2026-10-19: TBC default filler): a due stamp
-- counts down and an affirmatively empty fire slot reads due.
ST.weave_magma_last_drop = sandbox.clock - 20
near(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, 0, 1e-9,
    "gather: TBC feeds a due Magma drop")
ST.weave_magma_last_drop = nil
sandbox.fire_totem = { have = false }
eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, 0,
    "gather: TBC reads an empty fire slot as due")
eq(ST.weave_magma_last_drop, nil, "gather: the empty slot clears the stale stamp")
sandbox.fire_totem = nil

-- Every slot's always-fed cooldown_key resolves into the gathered inputs (the
-- known-gated Wrath/SoD keys and the skeleton Chain Lightning feed stay nil on
-- TBC).
local always_fed = { stormstrike = true, flameshock = true, firenova = true }
local cooldowns_resolve = true
for i = 1, #slots do
    local key = slots[i].cooldown_key
    if key and always_fed[key] and gathered[key .. "_remaining"] == nil then
        cooldowns_resolve = false
    end
end
check(cooldowns_resolve, "every always-fed slot cooldown_key resolves into the gathered inputs")

-- The Fire Nova read carries the same GCD-echo filter as Stormstrike.
sandbox.cooldowns = { [1535] = { start = 100, duration = 15 } }
local g4 = ST.SHAMAN.guide.gather(ST, gathered_target)
near(g4.firenova_remaining, 15, 1e-9, "gather: the real Fire Nova cooldown")
eq(g4.firenova_duration, 15, "gather: the client-reported Nova length")
sandbox.cooldowns = { [1535] = { start = 100, duration = 1.5 } }
local g5 = ST.SHAMAN.guide.gather(ST, gathered_target)
eq(g5.firenova_remaining, 0, "a ~1.5 s GCD echo is filtered on Nova too")
eq(g5.firenova_duration, nil, "the Nova GCD echo latches no duration")
sandbox.cooldowns = {}

-- The Windfury ICD feed: seconds from the last swing while the imbue is up.
ST.weave_windfury_active = true
local g6 = ST.SHAMAN.guide.gather(ST, gathered_target)
near(g6.windfury_icd_remaining, 2.0, 1e-9, "gather: the Windfury ICD from the last swing")
ST.weave_windfury_active = false
local g7 = ST.SHAMAN.guide.gather(ST, gathered_target)
eq(g7.windfury_icd_remaining, nil, "gather: a dropped imbue clears the ICD feed")

-- The GCD-echo filter on the Stormstrike read.
sandbox.cooldowns = { [17364] = { start = 100, duration = 1.5 } }
local g2 = ST.SHAMAN.guide.gather(ST, gathered_target)
eq(g2.stormstrike_remaining, 0, "a ~1.5 s GCD echo is filtered (remaining 0)")
eq(g2.stormstrike_duration, nil, "the GCD echo latches no duration")
sandbox.cooldowns = { [17364] = { start = 80, duration = 12 } }
local g3 = ST.SHAMAN.guide.gather(ST, gathered_target)
eq(g3.stormstrike_remaining, 0, "an expired cooldown reads as ready")
eq(g3.stormstrike_duration, nil, "an expired cooldown latches no duration")

-- Stale fields are overwritten on the reused table.
ST.weave_is_casting = true
ST.weave_mw_stacks = nil
ST.weave_fs_duration = nil
ST.weave_fs_expires = nil
sandbox.cooldowns = {}
local gathered2 = ST.SHAMAN.guide.gather(ST, gathered_target)
eq(gathered2, gathered_target, "the reused table is the same table")
eq(gathered2.casting, true, "the cast flag is overwritten, not stale")
eq(gathered2.mw_stacks, 0, "an unreadable stack count reads as 0")
eq(gathered2.weave_available, false, "casting withholds the weave availability")
eq(gathered2.flameshock_remaining, nil, "the cleared tracker clears the Flame Shock input")
eq(gathered2.flameshock_duration, nil, "and the stale swipe length")
eq(gathered2.stormstrike_remaining, 0, "the dropped cooldown reads as 0")
eq(gathered2.mw_available, false, "the Maelstrom gate is re-fed, not stale")
eq(gathered2.windfury_icd_remaining, nil, "the ICD feed is re-fed, not stale")
eq(gathered2.firenova_remaining, 0, "the dropped Nova cooldown reads as 0")
eq(gathered2.firenova_duration, nil, "and latches no duration")
eq(gathered2.twist_remaining, nil, "the twist stub is re-fed, not stale")
eq(gathered2.fireele_remaining, nil, "the Fire Elemental feed is re-fed, not stale")
eq(gathered2.fireele_duration, nil, "and latches no duration")
eq(gathered2.feralspirit_remaining, nil, "the Feral Spirit feed is re-fed, not stale")
eq(gathered2.feralspirit_duration, nil, "and latches no duration")
eq(gathered2.lavalash_remaining, nil, "the Lava Lash feed is re-fed, not stale")
eq(gathered2.lavalash_duration, nil, "and latches no duration")
eq(gathered2.magma_remaining, nil, "the Magma feed is re-fed, not stale")
eq(gathered2.magma_duration, nil, "and latches no duration")
eq(gathered2.magma_refresh, 3, "the magma refresh is re-fed, not stale")
eq(gathered2.sr_remaining, nil, "the Shamanistic Rage feed is re-fed, not stale")
eq(gathered2.sr_mana_threshold, 0.10, "the TBC SR gate is re-fed, not stale")
eq(gathered2.mana_fraction, nil, "the mana feed is re-fed, not stale")
eq(gathered2.shock_remaining, 0, "the shock feed is re-fed, not stale")
eq(gathered2.flameshock_allowed, true, "the Era veto is re-fed, not stale")
eq(gathered2.stormstrike_hold_enabled, false, "the hold opt-in is re-fed, not stale")
eq(gathered2.fireele_active, nil, "the Fire Elemental guard is re-fed, not stale")
eq(gathered2.moltenblast_remaining, nil, "the Molten Blast feed is re-fed, not stale")
eq(gathered2.target_count, nil, "the target-count skeleton is re-fed, not stale")
eq(gathered2.clearcasting_active, false, "the Clearcasting feed is re-fed, not stale")

-- The refresh threshold rides the options.
class_db.guide_flameshock_refresh = 6
eq(ST.SHAMAN.guide.gather(ST, gathered_target).flameshock_refresh, 6,
    "the refresh threshold rides the options")
class_db.guide_flameshock_refresh = nil
eq(ST.SHAMAN.guide.gather(ST, gathered_target).flameshock_refresh, 0,
    "a missing option falls back to the gather's own 0 s fallback (classes/shaman.lua's "..
    "gather), which is the shipped default (every sim re-applies Flame Shock only on expiry)")
class_db.guide_flameshock_refresh = 0

-- Direct calls without an out table use the module's own reused table.
local own = ST.SHAMAN.gather_guide_inputs(ST)
eq(own, ST.SHAMAN.guide_inputs, "gather without an out table uses the module's reused table")

-- The merged aura walk feeds the Maelstrom stacks the rules read.
do
    sandbox.auras = {
        { name = "Maelstrom Weapon", count = 3, duration = 30, expiration = 0,
            source = "player", spell_id = 53817 },
    }
    ST.SHAMAN.on_aura_change(ST)
    eq(ST.weave_mw_stacks, 3, "the aura walk refreshes the Maelstrom stacks")
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).mw_stacks, 3,
        "the refreshed stacks reach the frozen input")
    sandbox.auras = {}
    ST.SHAMAN.on_aura_change(ST)
    eq(ST.weave_mw_stacks, 0, "a dropped aura clears the stacks")
end

-- The tracker feeds the guide's frozen Flame Shock input (and the throttled target
-- scan keeps running while the guide is enabled even with the bar off).
do
    ST.weave_is_casting = false
    sandbox.target_auras = {
        { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 10,
            source = "player", spell_id = 8050 },
    }
    class_db.show_shaman_flame_shock_bar = false
    sandbox.target_aura_calls = 0
    local function tick(advance)
        ST.mainhand.ends_at = sandbox.clock + 3.0
        sandbox.advance(advance or 0.1)
        ST.SHAMAN.on_bar_update(ST, "mainhand")
    end
    tick()
    tick()
    check(sandbox.target_aura_calls > 0,
        "the guide keeps the target scan alive with the Flame Shock bar off")
    near(ST.SHAMAN.guide.gather(ST, gathered_target).flameshock_remaining, 10, 0.2,
        "the tracker feeds flameshock_remaining")
    -- With the guide off too, the bar-off configuration reads no target auras.
    class_db.nextaction_enabled = false
    sandbox.target_aura_calls = 0
    tick()
    eq(sandbox.target_aura_calls, 0,
        "with the guide off too, the bar-off configuration reads no target auras")
    class_db.nextaction_enabled = true
    class_db.show_shaman_flame_shock_bar = true
    -- A cleared target clears the frozen input on the very next gather.
    sandbox.target_auras = {}
    tick()
    tick()
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).flameshock_remaining, nil,
        "a cleared target clears the stale Flame Shock input")
end

-- The totem-twist live feed (TBC): SUCCEEDED commits and the air-slot clock flow
-- into twist_remaining; every other family stays nil (byte-identical).
do
    ST.weave_is_casting = false
    ST.weave_mw_stacks = 0
    ST.weave_windfury_active = false
    ST.weave_twist_last_drop = nil
    sandbox.cooldowns = {}
    sandbox.totem = nil

    -- A Windfury commit stamps now: the full period is left.
    ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-tw-live", 8512)
    near(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, 10, 1e-9,
        "gather: a fresh twist commit reads the full period")
    -- An unconfirmed rank stamps through its live spell name, not the id table.
    ST.weave_twist_last_drop = nil
    ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-tw-rank", 10613)
    near(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, 10, 1e-9,
        "gather: an unconfirmed twist rank stamps by spell name")
    -- Grace of Air stamps through the name token.
    ST.weave_twist_last_drop = nil
    ST.SHAMAN.on_spellcast_succeeded(ST, "player", "Grace of Air Totem", 99999)
    near(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, 10, 1e-9,
        "gather: Grace of Air stamps by name token")

    -- Due (a full period elapsed): the engine answers twist with a healthy Flame
    -- Shock and a ready Stormstrike (rules 6 and 7 both pass it by).
    ST.weave_twist_last_drop = sandbox.clock - 10
    ST.weave_fs_duration = 12
    ST.weave_fs_expires = sandbox.clock + 10
    local due = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(due.twist_remaining, 0, "gather: a period-old drop reads due")
    local due_out = {}
    ST.SHAMAN.guide.evaluate(due, due_out)
    eq(due_out.action, "twist", "rule 7: a due twist prompts the twist slot")

    -- Not due (3 s elapsed): the chain falls past the twist to Stormstrike.
    ST.weave_twist_last_drop = sandbox.clock - 3
    local fresh = ST.SHAMAN.guide.gather(ST, gathered_target)
    near(fresh.twist_remaining, 7, 1e-9, "gather: a fresh drop counts down")
    local fresh_out = {}
    ST.SHAMAN.guide.evaluate(fresh, fresh_out)
    eq(fresh_out.action, "stormstrike", "a twist that is not due falls to Stormstrike")

    -- The air-slot clock backfills an unknown stamp (mid-twist load): 4 s of a
    -- 10 s period elapsed. A non-twist totem and an absent read stay unknown.
    ST.weave_twist_last_drop = nil
    sandbox.totem = { have = true, name = "Grace of Air Totem", start = sandbox.clock - 4 }
    near(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, 6, 1e-9,
        "gather: the air-slot clock backfills an unknown stamp")
    ST.weave_twist_last_drop = nil
    sandbox.totem = { have = true, name = "Searing Totem", start = sandbox.clock - 4 }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: a non-twist air totem never feeds the twist")
    sandbox.totem = nil

    -- Non-TBC families stay nil even with a due drop (byte-identical).
    ST.weave_twist_last_drop = sandbox.clock - 10
    sandbox.st.family = "WRATH"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: Wrath never feeds the twist despite a due drop")
    sandbox.st.family = "ERA"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: Era never feeds the twist despite a due drop")
    sandbox.st.family = "TBC"

-- The Wrath cooldown feeds: known-gated (unknown ids stay nil on every family),
-- the Magma stamp model through SUCCEEDED + the fire-slot clock, and the no-twist
-- pin (a due twist drop never feeds outside TBC).
do
    sandbox.st.family = "WRATH"
    ST.weave_is_casting = false
    ST.weave_mw_stacks = 0
    ST.weave_magma_last_drop = nil
    sandbox.cooldowns = {}
    sandbox.fire_totem = nil

    -- Unknown spells feed nil (the UNCONFIRMED-id shape on a client without them).
    sandbox.known = { [25449] = true, [25442] = true }
    local unknown = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(unknown.fireele_remaining, nil, "gather: an unknown Fire Elemental feeds nil")
    eq(unknown.feralspirit_remaining, nil, "gather: an unknown Feral Spirit feeds nil")
    eq(unknown.lavalash_remaining, nil, "gather: an unknown Lava Lash feeds nil")

    -- Known and ready: remaining 0, no duration latched.
    sandbox.known[51533] = true
    sandbox.known[2894] = true
    sandbox.known[60103] = true
    local ready = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(ready.feralspirit_remaining, 0, "gather: a ready Feral Spirit reads 0")
    eq(ready.feralspirit_duration, nil, "gather: a ready Feral Spirit latches no duration")
    eq(ready.fireele_remaining, 0, "gather: a ready Fire Elemental reads 0")
    eq(ready.lavalash_remaining, 0, "gather: a ready Lava Lash reads 0")

    -- Known and on cooldown: the real remaining + client length ride.
    sandbox.cooldowns = { [51533] = { start = sandbox.clock, duration = 180 } }
    local cooling = ST.SHAMAN.guide.gather(ST, gathered_target)
    near(cooling.feralspirit_remaining, 180, 1e-9, "gather: the real Feral Spirit cooldown")
    eq(cooling.feralspirit_duration, 180, "gather: the client-reported Feral length")

    -- The GCD echo is filtered on the known gate too.
    sandbox.cooldowns = { [51533] = { start = sandbox.clock, duration = 1.5 } }
    local echo = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(echo.feralspirit_remaining, 0, "a ~1.5 s GCD echo is filtered on Feral Spirit too")
    eq(echo.feralspirit_duration, nil, "the Feral GCD echo latches no duration")
    sandbox.cooldowns = {}
    -- Back to unknown for the Magma leg below (a ready cooldown slot would
    -- outrank Magma and shadow the assertions).
    sandbox.known[51533] = nil
    sandbox.known[2894] = nil
    sandbox.known[60103] = nil

    -- Magma: unknown stamp + unreadable slot feeds nil (never prompts on a guess).
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, nil,
        "gather: an unknown Magma drop with no totem read feeds nil")

    -- The Lightning Shield maintain (S-19): the player's own shield aura drives
    -- the feed - no aura up means the cast is due, an aura up means it is not,
    -- and an unrun walk means unknown (never prompts on a guess). The maintain is
    -- known-gated (the Lightning Shield is a talent), so the fixture marks it
    -- known here; an unknown spell never feeds the due flag.
    ST.weave_shield_scanned = false
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).lightningshield_due, nil,
        "gather: an unrun aura walk never feeds the Lightning Shield maintain")
    ST.weave_shield_scanned = true
    ST.weave_shield_type = nil
    sandbox.known[9201] = true
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).lightningshield_due, true,
        "gather: no shield aura up feeds the Lightning Shield maintain due")
    ST.weave_shield_type = "lightning"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).lightningshield_due, false,
        "gather: an up-to-date Lightning Shield never feeds due")
    ST.weave_shield_type = "water"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).lightningshield_due, false,
        "gather: a Water Shield build never feeds the Lightning Shield due")
    ST.weave_shield_type = nil
    sandbox.known[9201] = nil
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).lightningshield_due, nil,
        "gather: an unknown Lightning Shield never feeds the maintain")
    sandbox.known[9201] = true

    -- The Searing maintain (S-17): the fire-slot reader feeds due only on an
    -- affirmatively empty slot; a live Searing (or another totem) never does.
    -- The maintain is known-gated (the Searing Totem is a talent on Era/SoD), so
    -- the fixture marks it known here.
    sandbox.known[9202] = true
    sandbox.fire_totem = { have = false }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).searing_down, true,
        "gather: an affirmatively empty fire slot feeds the Searing due flag")
    sandbox.fire_totem = { have = true, name = "Searing Totem", start = sandbox.clock }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).searing_down, false,
        "gather: a live Searing Totem never feeds due")
    sandbox.known[9202] = nil
    sandbox.fire_totem = { have = false }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).searing_down, nil,
        "gather: an unknown Searing Totem never feeds the due flag")
    sandbox.known[9202] = true
    sandbox.fire_totem = nil

    -- A Magma SUCCEEDED commit stamps now: the full window is left.
    ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-magma-live", 8190)
    near(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, 20, 1e-9,
        "gather: a fresh Magma commit reads the full window")
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_duration, 20,
        "gather: the Magma window rides as the swipe length")

    -- Due (a full window elapsed): the engine answers magma with SS down.
    ST.weave_magma_last_drop = sandbox.clock - 20
    ST.weave_fs_duration = 12
    ST.weave_fs_expires = sandbox.clock + 10
    sandbox.cooldowns = { [17364] = { start = sandbox.clock, duration = 8 } }
    local magma_due = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(magma_due.magma_remaining, 0, "gather: a window-old Magma drop reads due")
    local magma_due_out = {}
    ST.SHAMAN.guide.evaluate(magma_due, magma_due_out)
    eq(magma_due_out.action, "magma", "rule 10: a due Magma prompts the magma slot")

    -- Inside the refresh window: still magma; past it: Nova.
    ST.weave_magma_last_drop = sandbox.clock - 18
    local refresh_in = ST.SHAMAN.guide.gather(ST, gathered_target)
    near(refresh_in.magma_remaining, 2, 1e-9, "gather: a drop 18 s ago reads 2 s left")
    local refresh_out = {}
    ST.SHAMAN.guide.evaluate(refresh_in, refresh_out)
    eq(refresh_out.action, "magma", "a Magma inside the refresh window still prompts")

    -- The fire-slot clock backfills an unknown stamp (mid-fight load): 4 s of a
    -- 20 s window elapsed. A non-Magma fire totem and an absent read stay unknown.
    ST.weave_magma_last_drop = nil
    sandbox.fire_totem = { have = true, name = "Magma Totem", start = sandbox.clock - 4 }
    near(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, 16, 1e-9,
        "gather: the fire-slot clock backfills an unknown stamp")
    ST.weave_magma_last_drop = nil
    sandbox.fire_totem = { have = true, name = "Searing Totem", start = sandbox.clock - 4 }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, nil,
        "gather: a non-Magma fire totem never feeds Magma")
    sandbox.fire_totem = nil

    -- An affirmatively empty fire slot feeds due (the initial drop prompt).
    sandbox.fire_totem = { have = false }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, 0,
        "gather: an affirmatively empty fire slot reads due")
    eq(ST.weave_magma_last_drop, nil, "the empty slot clears the stale stamp")
    sandbox.fire_totem = nil

    -- Non-Magma families stay nil even with a due drop (byte-identical): ERA and
    -- FOREVER never feed (Era runs Searing, Forever its own totems); TBC and Wrath
    -- both feed (audit 2026-10-19: TBC default filler).
    ST.weave_magma_last_drop = sandbox.clock - 20
    sandbox.st.family = "ERA"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, nil,
        "gather: Era never feeds Magma despite a due drop")
    sandbox.st.family = "FOREVER"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, nil,
        "gather: Forever never feeds Magma despite a due drop")
    sandbox.st.family = "TBC"
    near(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, 0, 1e-9,
        "gather: TBC feeds the due drop too")
    sandbox.st.family = "WRATH"
    near(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, 0, 1e-9,
        "gather: Wrath feeds the due drop again")

    -- No-twist on Wrath: a due twist drop still feeds nil (Wrath never twists).
    ST.weave_twist_last_drop = sandbox.clock - 10
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: Wrath never feeds the twist despite a due drop")
    local no_twist = ST.SHAMAN.guide.gather(ST, gathered_target)
    local no_twist_out = {}
    ST.SHAMAN.guide.evaluate(no_twist, no_twist_out)
    check(no_twist_out.action ~= "twist", "Wrath: a due twist drop never prompts the twist slot")

    -- Fixture restored: TBC client, no live aura, stamps cleared.
    ST.weave_twist_last_drop = nil
    ST.weave_magma_last_drop = nil
    ST.weave_fs_duration = nil
    ST.weave_fs_expires = nil
    sandbox.totem = nil
    sandbox.fire_totem = nil
    sandbox.cooldowns = {}
    sandbox.known = { [25449] = true, [25442] = true }
    sandbox.st.family = "TBC"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: the restored fixture reads unknown again")
end
end

-- The Era static totem feeds (G2): Windfury first, Grace of Air as the
-- fallback while Windfury is unknown. Era-base only (family ERA without the
-- SoD MW-rune latch); every other family stays nil (byte-identical), and an
-- unreadable air slot never feeds due. Both ids are UNCONFIRMED, so the
-- known gate is what the tests drive.
do
    sandbox.st.family = "ERA"
    ST.weave_mw_observed = false
    ST.weave_is_casting = false
    ST.weave_mw_stacks = 0
    ST.weave_fs_duration = nil
    ST.weave_fs_expires = nil
    sandbox.cooldowns = {}
    sandbox.known = { [25449] = true, [25442] = true }

    -- Unknown spells feed nil even on an empty slot (the UNCONFIRMED-id shape
    -- on a client without them).
    sandbox.totem = { have = false }
    local unknown = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(unknown.wftotem_remaining, nil, "gather: an unknown Windfury Totem feeds nil")
    eq(unknown.goatotem_remaining, nil, "gather: an unknown Grace of Air feeds nil")

    -- Empty slot with Windfury known: WF due (the sim's priority), GoA silent.
    sandbox.known[10614] = true
    local empty = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(empty.wftotem_remaining, 0, "gather: an empty air slot feeds Windfury due")
    eq(empty.goatotem_remaining, nil, "gather: Windfury known gates Grace of Air")
    local empty_out = {}
    ST.SHAMAN.guide.evaluate(empty, empty_out)
    eq(empty_out.action, "wftotem", "rule 8b: the Era tick prompts the wftotem slot")

    -- The slot holding Windfury reads not-due, by name and by id alike.
    sandbox.totem = { have = true, name = "Windfury Totem", start = sandbox.clock - 4 }
    local wf_up = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(wf_up.wftotem_remaining, nil, "gather: a live Windfury Totem never feeds due")
    eq(wf_up.goatotem_remaining, nil, "gather: a live Windfury Totem gates Grace of Air")
    sandbox.totem = { have = true, name = "Other", spell = 10614, start = sandbox.clock - 4 }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).wftotem_remaining, nil,
        "gather: the Windfury id reads up whatever the totem name says")

    -- The slot holding Grace of Air with Windfury known: WF takes it back.
    sandbox.totem = { have = true, name = "Grace of Air Totem", start = sandbox.clock - 4 }
    local goa_up = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(goa_up.wftotem_remaining, 0, "gather: Windfury takes the slot back from Grace of Air")
    eq(goa_up.goatotem_remaining, nil, "gather: a live Grace of Air never feeds due itself")

    -- Windfury unknown: Grace of Air is the fallback air totem on an empty slot.
    sandbox.known[10614] = nil
    sandbox.known[10627] = true
    sandbox.totem = { have = false }
    local fallback = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(fallback.wftotem_remaining, nil, "gather: an unknown Windfury never feeds")
    eq(fallback.goatotem_remaining, 0, "gather: the empty slot feeds Grace of Air due")
    local fallback_out = {}
    ST.SHAMAN.guide.evaluate(fallback, fallback_out)
    eq(fallback_out.action, "goa", "rule 8c: the fallback tick prompts the goa slot")

    -- Grace of Air up with Windfury unknown: both silent (no thrash).
    sandbox.totem = { have = true, name = "Grace of Air Totem", start = sandbox.clock - 4 }
    local goa_holds = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(goa_holds.wftotem_remaining, nil, "gather: unknown Windfury never takes the slot")
    eq(goa_holds.goatotem_remaining, nil, "gather: a live Grace of Air never feeds due")

    -- A third air totem (Nature Resistance and friends) is unmodeled: both
    -- silent, never fight the player's drop.
    sandbox.known[10614] = true
    sandbox.totem = { have = true, name = "Nature Resistance Totem", start = sandbox.clock - 4 }
    local other = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(other.wftotem_remaining, nil, "gather: an unmodeled air totem never feeds Windfury")
    eq(other.goatotem_remaining, nil, "gather: an unmodeled air totem never feeds Grace of Air")

    -- An unreadable air slot never feeds due (never prompts on a guess).
    sandbox.totem = nil
    local unreadable = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(unreadable.wftotem_remaining, nil, "gather: an unreadable air slot feeds no Windfury")
    eq(unreadable.goatotem_remaining, nil, "gather: an unreadable air slot feeds no Grace of Air")

    -- Every other family stays nil even on an empty slot (byte-identical):
    -- SoD runs no totem maintain, TBC twists, Wrath/Forever run none.
    sandbox.totem = { have = false }
    sandbox.known[10614] = true
    ST.weave_mw_observed = true
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).wftotem_remaining, nil,
        "gather: SoD never feeds Windfury despite an empty slot")
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).goatotem_remaining, nil,
        "gather: SoD never feeds Grace of Air despite an empty slot")
    ST.weave_mw_observed = false
    sandbox.st.family = "TBC"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).wftotem_remaining, nil,
        "gather: TBC never feeds Windfury despite an empty slot")
    sandbox.st.family = "WRATH"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).wftotem_remaining, nil,
        "gather: Wrath never feeds Windfury despite an empty slot")
    sandbox.st.family = "FOREVER"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).wftotem_remaining, nil,
        "gather: Forever never feeds Windfury despite an empty slot")
    sandbox.st.family = nil
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).wftotem_remaining, nil,
        "gather: an unknown family never feeds Windfury on a guess")
    -- The live frame reuses its table: leaving Era clears the feed in place.
    local reused_era = ST.SHAMAN.guide.gather(ST, gathered_target)
    sandbox.st.family = "ERA"
    reused_era = ST.SHAMAN.guide.gather(ST, reused_era)
    eq(reused_era.wftotem_remaining, 0, "back on Era-base: the Windfury feed returns")
    sandbox.st.family = "TBC"
    reused_era = ST.SHAMAN.guide.gather(ST, reused_era)
    eq(reused_era.wftotem_remaining, nil, "leaving Era clears the Windfury feed (no stale value)")

    -- Fixture restored: TBC client, no live aura, stamps cleared.
    ST.weave_mw_stacks = 0
    ST.weave_mw_observed = false
    sandbox.cooldowns = {}
    sandbox.known = { [25449] = true, [25442] = true }
    sandbox.totem = nil
    sandbox.st.family = "TBC"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).wftotem_remaining, nil,
        "gather: the restored fixture reads unknown again")
end

-- The Forever adaptation (docs/research/forever_beta.md, all UNCONFIRMED): no
-- twisting (party-buff totem model - totems coexist with imbues, so there is no
-- weapon-enchant twist to prompt).
do
    ST.weave_is_casting = false
    ST.weave_mw_stacks = 0
    ST.weave_mw_observed = false
    ST.weave_windfury_active = false
    ST.weave_twist_last_drop = nil
    ST.weave_fs_duration = 12
    ST.weave_fs_expires = sandbox.clock + 10
    sandbox.cooldowns = {}
    sandbox.totem = nil
    sandbox.st.family = "FOREVER"

    -- A due drop still feeds nil (nothing to alternate on Forever).
    ST.weave_twist_last_drop = sandbox.clock - 10
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: Forever never feeds the twist despite a due drop")
    -- The air-slot clock cannot backfill it either.
    ST.weave_twist_last_drop = nil
    sandbox.totem = { have = true, name = "Windfury Totem", start = sandbox.clock - 4 }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: the air-slot clock never feeds the twist on Forever")
    sandbox.totem = nil

    -- The tick answers Stormstrike behind the nil feed, never the twist slot.
    local no_twist = ST.SHAMAN.guide.gather(ST, gathered_target)
    local no_twist_out = {}
    ST.SHAMAN.guide.evaluate(no_twist, no_twist_out)
    eq(no_twist_out.action, "stormstrike",
        "Forever: the tick answers Stormstrike, never the twist slot")

    -- Fixture restored: TBC client, no live aura, stamps cleared.
    ST.weave_mw_stacks = 0
    ST.weave_mw_observed = false
    ST.weave_twist_last_drop = nil
    ST.weave_fs_duration = nil
    ST.weave_fs_expires = nil
    sandbox.cooldowns = {}
    sandbox.totem = nil
    sandbox.st.family = "TBC"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: the restored fixture reads unknown again")
end

-- The Lightning Bolt fallback when the catalogue resolves nothing.
do
    local fallback = build({ known = {} })
    -- A pre-init gather never errors (the weave catalogue does not exist yet).
    local pre = fallback.ST.SHAMAN.gather_guide_inputs(fallback.ST, {})
    eq(pre.weave_available, false, "a pre-init gather answers weave_available=false")
    fallback.ST.SHAMAN.post_init(fallback.ST)
    local fslots = fallback.ST.SHAMAN.guide.slots
    eq(fslots[3].spell_id, 403, "an unresolved catalogue keeps the Lightning Bolt fallback")
    local fui = fallback.st.nextaction_ui
    eq(fui.icons[3].icon.texture.texture, "icon_lb_r1",
        "the fallback icon resolves through GetSpellInfo")
    local fgathered = fallback.ST.SHAMAN.guide.gather(fallback.ST, {})
    eq(fgathered.weave_available, false, "an unresolved catalogue is not weave-available")
end

--=========================================================================================
-- 3) The display mapping through the real frame and the real hooks
--=========================================================================================
sandbox.clock = 201
ST.mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false }
ST.gcd = { expires = 0 }
ST.weave_is_casting = false
ST.weave_mw_stacks = 0
ST.weave_fs_duration = nil
ST.weave_fs_expires = nil
sandbox.cooldowns = {}

local function tick(advance)
    ST.mainhand.ends_at = sandbox.clock + 3.0
    sandbox.advance(advance or 0.1)
    ST.SHAMAN.on_bar_update(ST, "mainhand")
end
local function target(key)
    return ui.icons[ui.slot_index[key]].fade.target
end
local function slot_icon(key)
    return ui.icons[ui.slot_index[key]].icon
end

-- The casting hold wins over everything.
ST.weave_is_casting = true
ST.weave_mw_stacks = 5
sandbox.cooldowns = {}
tick()
eq(target("weave"), 0, "a cast in flight suppresses the weave prompt")
eq(target("stormstrike"), 0, "a cast in flight suppresses Stormstrike")
eq(ui.frame.hold.fade.target, 1, "the cast in flight shows the hold overlay")
eq(ui.frame.hold.text.text, "RIDE", "the casting hold reads RIDE")
eq(ui.frame.shown, true, "the in-combat tick shows the frame")
eq(ST.weave_mw_stacks, 5, "the stacks survive the cast")

-- Five stacks buy no prompt on TBC: with Maelstrom unavailable the fallthrough lands
-- on the untracked Flame Shock instead of the weave slot.
ST.weave_is_casting = false
tick()
eq(target("weave"), 0, "TBC: five stacks never light the weave slot")
eq(target("flameshock"), 1, "TBC: the fallthrough lights the Flame Shock slot")
eq(ui.frame.hold.fade.target, 0, "the hold overlay clears")

-- An untracked Flame Shock, then an expired one.
-- The shipped refresh threshold is 0 - expiry only (every sim re-applies Flame Shock
-- only when the dot is INACTIVE), so a LIVE dot is never re-applied and an expired
-- one has no countdown left to ride: the frame's slot lights, its swipe stays idle.
ST.weave_mw_stacks = 0
sandbox.cooldowns = { [17364] = { start = sandbox.clock, duration = 8 } }
tick()
eq(target("flameshock"), 1, "an untracked Flame Shock lights the Flame Shock slot")
eq(target("weave"), 0, "and the weave slot clears")
eq(slot_icon("flameshock").cooldown.cooldown_sets or 0, 0,
    "an untracked Flame Shock has no countdown to ride")
sandbox.target_auras = {
    { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock - 1,
        source = "player", spell_id = 8050 },
}
tick()
tick()
eq(target("flameshock"), 1, "an expired Flame Shock stays suggested")
eq(slot_icon("flameshock").cooldown.cooldown_sets or 0, 0,
    "an expired debuff has no countdown left to ride (the shipped threshold is 0)")
eq(slot_icon("flameshock").cooldown_set, false,
    "the Flame Shock swipe latch stays unarmed on an expired debuff")
sandbox.target_auras = {
    { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 10,
        source = "player", spell_id = 8050 },
}
tick()
tick()
eq(target("flameshock"), 0, "a live Flame Shock is not re-applied (the shipped threshold is 0)")
eq(slot_icon("flameshock").cooldown.cooldown_sets or 0, 0,
    "a live debuff rides no swipe while its slot is dark")
eq(slot_icon("flameshock").cooldown_set, false,
    "the swipe latch stays reset while the slot is dark")

-- An explicit override still rides the whole path: a live dot inside the window is
-- suggested again, and only then does the slot have a countdown to ride - the
-- tracker's debuff length.
class_db.guide_flameshock_refresh = 3
sandbox.target_auras = {
    { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 2,
        source = "player", spell_id = 8050 },
}
tick()
tick()
eq(target("flameshock"), 1, "the explicit refresh window suggests a live Flame Shock")
eq(slot_icon("flameshock").cooldown.cooldown_duration, 12,
    "the tracker's debuff length drives the Flame Shock swipe")
eq(slot_icon("flameshock").cooldown.cooldown_sets, 1, "the Flame Shock swipe is set once")
eq(slot_icon("flameshock").cooldown_set, true, "the Flame Shock swipe latch is armed")
tick()
eq(slot_icon("flameshock").cooldown.cooldown_sets, 1, "the swipe latch holds across ticks")
-- Restore the SHIPPED default (0 - the gather's own `or 3` fallback only answers a
-- missing key, so the fixture must carry the shipped value, not nil).
class_db.guide_flameshock_refresh = 0

-- A healthy Flame Shock with SS ready -> Stormstrike (and no swipe while ready).
sandbox.cooldowns = {}
tick()
eq(target("flameshock"), 0, "a healthy Flame Shock clears its slot")
eq(target("stormstrike"), 1, "with SS ready the guide suggests Stormstrike")

-- SS down + three stacks: no weave without Maelstrom; Fire Nova answers instead.
-- (The Flame Shock cache above is healthy again, so Nova - not the refresh - wins.)
sandbox.cooldowns = { [17364] = { start = sandbox.clock, duration = 8 } }
ST.weave_mw_stacks = 3
tick()
eq(target("stormstrike"), 0, "a running SS cooldown clears the Stormstrike slot")
eq(target("weave"), 0, "TBC: 3 stacks with SS down do not light the weave slot")
eq(target("firenova"), 1, "TBC: Fire Nova answers while Stormstrike is down")
ST.weave_mw_stacks = 2
tick()
eq(target("firenova"), 1, "2 stacks still answer Fire Nova (no stacks needed)")
eq(target("earthshock"), 0, "and the shock filler stays dark behind Nova")

-- Five stacks still buy nothing with SS down either.
ST.weave_mw_stacks = 5
tick()
eq(target("weave"), 0, "TBC: 5 stacks do not outrank a running SS cooldown")
eq(target("firenova"), 1, "Fire Nova still answers")
ST.weave_mw_stacks = 0

-- Fire Nova on cooldown: the Earth Shock filler answers.
sandbox.cooldowns[1535] = { start = sandbox.clock, duration = 15 }
tick()
eq(target("firenova"), 0, "a running Fire Nova cooldown clears its slot")
eq(target("earthshock"), 1, "the shock filler answers with everything else down")
eq(ui.frame.hold.fade.target, 0, "the filler carries no hold")
sandbox.cooldowns[1535] = nil
tick()
eq(target("firenova"), 1, "a ready Nova prompts again")
eq(target("earthshock"), 0, "and the filler yields to it")

-- Delay-if-fishing-WF, now opt-in (audit 2026-10-19 §1): Stormstrike ready, Flame
-- Shock healthy and the Windfury ICD inside this swing presses Stormstrike by
-- default (every sim does); the hold only arms behind the wf-hold-tint opt-in.
sandbox.cooldowns = {}
sandbox.target_auras = {
    { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 10,
        source = "player", spell_id = 8050 },
}
ST.weave_windfury_active = true
ST.mainhand = { speed = 3.0, ends_at = sandbox.clock + 3.0, start = sandbox.clock - 2.5,
    is_full = false }
tick()
tick()
eq(ui.frame.hold.fade.target, 0, "the default presses Stormstrike, no hold overlay")
eq(target("stormstrike"), 1, "the default prompts Stormstrike with the ICD inside the swing")
eq(target("flameshock"), 0, "a healthy Flame Shock stays dark behind it")
eq(target("firenova"), 0, "and Fire Nova stays dark behind it")
class_db.show_shaman_wf_hold_tint = true
tick()
tick()
eq(ui.frame.hold.fade.target, 1, "the opt-in fishing hold shows the overlay")
eq(ui.frame.hold.text.text, "WAIT", "the opt-in fishing hold reads WAIT")
eq(target("stormstrike"), 0, "the held Stormstrike stays dark")
eq(target("flameshock"), 0, "a healthy Flame Shock stays dark behind the hold")
eq(target("firenova"), 0, "and Fire Nova stays dark behind the hold")
class_db.show_shaman_wf_hold_tint = nil

-- With the ICD elapsed the same tick prompts Stormstrike instead.
ST.mainhand = { speed = 3.0, ends_at = sandbox.clock + 3.0, start = sandbox.clock - 3.0,
    is_full = false }
tick()
eq(target("stormstrike"), 1, "with the ICD elapsed the guide prompts Stormstrike")
eq(ui.frame.hold.fade.target, 0, "the hold overlay clears")
ST.weave_windfury_active = false

-- The twist slot stays dark with no drop known: neither a commit nor the air-slot
-- clock has fed twist_remaining (the live feed is pinned above).
eq(target("twist"), 0, "the twist slot stays dark with no known drop")

-- Wrath through the real frame: the MW5 prompt survives, the MW3 hardcast is
-- gone (MW5-only), the cooldown slots light in research order, and Wrath never
-- twists (then back to TBC for the option gates below).
sandbox.st.family = "WRATH"
ST.weave_is_casting = false
ST.weave_mw_stacks = 5
sandbox.cooldowns = {}
sandbox.target_auras = {}
tick()
tick()
eq(target("weave"), 1, "Wrath: five stacks light the weave slot")
eq(target("flameshock"), 0, "Wrath: the instant weave outranks the Flame Shock refresh")
ST.weave_mw_stacks = 3
sandbox.cooldowns = { [17364] = { start = sandbox.clock, duration = 8 } }
sandbox.target_auras = {
    { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 10,
        source = "player", spell_id = 8050 },
}
tick()
tick()
eq(target("weave"), 0, "Wrath: 3 stacks with SS down no longer light the weave slot")
eq(target("firenova"), 1, "Wrath: 3 stacks with SS down fall to Fire Nova")
-- The cooldown slots light in research order (Fire Ele > Feral > MW5).
sandbox.known[51533] = true
sandbox.known[2894] = true
ST.weave_mw_stacks = 5
sandbox.cooldowns = {}
tick()
tick()
eq(target("fireele"), 1, "Wrath: a ready Fire Elemental lights its slot")
eq(target("feralspirit"), 0, "Wrath: Feral Spirit stays dark behind Fire Elemental")
eq(target("weave"), 0, "Wrath: Fire Elemental outranks the 5-stack weave")
sandbox.known[2894] = nil
tick()
tick()
eq(target("feralspirit"), 1, "Wrath: a ready Feral Spirit lights its slot")
eq(target("fireele"), 0, "Wrath: an unknown Fire Elemental stays dark")
eq(target("weave"), 0, "Wrath: Feral Spirit outranks the 5-stack weave")
-- Shamanistic Rage lights on cooldown with no mana gate (Wrath has no sim-backed
-- threshold); Feral Spirit outranks it in research order.
sandbox.known[30823] = true
tick()
tick()
eq(target("feralspirit"), 1, "Wrath: Feral Spirit outranks a ready Shamanistic Rage")
eq(target("shamanisticrage"), 0, "Wrath: Shamanistic Rage stays dark behind Feral Spirit")
sandbox.known[51533] = nil
tick()
tick()
eq(target("shamanisticrage"), 1, "Wrath: a ready Shamanistic Rage lights its slot")
eq(target("weave"), 0, "Wrath: Shamanistic Rage outranks the 5-stack weave")
sandbox.known[30823] = nil
-- Magma due lights its slot with SS down (an affirmatively empty fire slot).
sandbox.known[51533] = nil
ST.weave_mw_stacks = 0
sandbox.cooldowns = { [17364] = { start = sandbox.clock, duration = 8 } }
ST.weave_magma_last_drop = nil
sandbox.fire_totem = { have = false }
tick()
tick()
eq(target("magma"), 1, "Wrath: an empty fire slot lights the magma slot")
eq(target("firenova"), 0, "Wrath: Magma outranks Fire Nova")
-- Lava Lash answers with SS and Nova down and a fresh Magma. The Wrath Lightning
-- Shield maintain (rule 11b, S-19) sits above Lava Lash, so a player with no
-- shield aura up is prompted the shield first.
sandbox.fire_totem = nil
ST.weave_magma_last_drop = sandbox.clock
sandbox.cooldowns = {
    [17364] = { start = sandbox.clock, duration = 8 },
    [1535] = { start = sandbox.clock, duration = 15 },
}
sandbox.known[60103] = true
-- The Lightning Shield maintain is known-gated (the Lightning Shield is a
-- talent), so the fixture marks it known on this build.
sandbox.known[9201] = true
tick()
tick()
eq(target("lightningshield"), 1, "Wrath: no shield aura up lights the Lightning Shield slot")
eq(target("lavalash"), 0, "Wrath: the Lightning Shield outranks a ready Lava Lash")
-- The shield is up: the maintain is satisfied and the Lava Lash answers again.
sandbox.auras = { { name = "Lightning Shield", count = 4, spell_id = 9201 } }
ST.SHAMAN.on_aura_change(ST)
tick()
tick()
eq(target("lightningshield"), 0, "Wrath: an up-to-date Lightning Shield stays dark")
eq(target("lavalash"), 1, "Wrath: a ready Lava Lash answers with SS and Nova down")
eq(target("earthshock"), 0, "Wrath: the shock filler stays dark behind Lava Lash")
-- No-twist on Wrath through the frame: a due drop lights nothing.
ST.weave_twist_last_drop = sandbox.clock - 10
tick()
eq(target("twist"), 0, "Wrath: a due twist drop never lights the twist slot")
eq(target("lavalash"), 1, "Wrath: the tick still answers Lava Lash behind it")
sandbox.st.family = "TBC"
ST.weave_mw_stacks = 0
ST.weave_twist_last_drop = nil
ST.weave_magma_last_drop = nil
sandbox.fire_totem = nil
sandbox.known = { [25449] = true, [25442] = true }
sandbox.cooldowns = {}
sandbox.target_auras = {}
sandbox.auras = {}

-- SoD through the real frame: ERA shares the token but HAS the MW rune, so
-- the aura-observed latch re-enables the MW rules; Era-base (never observed)
-- vetoes the Flame Shock maintain (the Era sim never casts it) and falls to
-- Stormstrike; the option stays the kill-switch.
sandbox.st.family = "ERA"
ST.weave_mw_observed = false
ST.weave_is_casting = false
ST.weave_mw_stacks = 5
sandbox.cooldowns = {}
sandbox.target_auras = {}
tick()
tick()
eq(target("weave"), 0, "Era-base: five stacks never light the weave slot")
eq(target("flameshock"), 0, "Era-base: the vetoed maintain never lights Flame Shock")
eq(target("stormstrike"), 1, "Era-base: the fallthrough prompts Stormstrike")
eq(ST.SHAMAN.guide.gather(ST, gathered_target).mw_available, false,
    "Era-base: the gather reports MW unavailable")
eq(ST.SHAMAN.guide.gather(ST, gathered_target).flameshock_allowed, false,
    "Era-base: the gather vetoes the Flame Shock maintain")

-- The rune aura latches through the real hook and re-enables the MW rules.
sandbox.auras = {
    { name = "Maelstrom Weapon", count = 5, spell_id = 408505 },
}
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_mw_stacks, 5, "SoD: the rune aura refreshes the stacks")
eq(ST.weave_mw_observed, true, "SoD: the rune aura latches observed")
eq(ST.SHAMAN.guide.gather(ST, gathered_target).mw_available, true,
    "SoD: the gather reports MW available")
eq(ST.SHAMAN.guide.gather(ST, gathered_target).flameshock_allowed, true,
    "SoD: the gather keeps the Flame Shock maintain")
-- Feral Spirit feeds by name on SoD (the Wrath id never resolves there) and tops
-- the sim priority, so it outranks the weave.
eq(ST.SHAMAN.guide.gather(ST, gathered_target).feralspirit_remaining, 0,
    "SoD: Feral Spirit feeds ready by name")
eq(ST.SHAMAN.guide.gather(ST, gathered_target).lavalash_remaining, 0,
    "SoD: Lava Lash feeds ready by name")
tick()
tick()
eq(target("feralspirit"), 1, "SoD: a ready Feral Spirit lights its slot")
eq(target("weave"), 0, "SoD: Feral Spirit outranks the 5-stack weave")
sandbox.cooldowns = { ["Feral Spirit"] = { start = sandbox.clock, duration = 180 } }
tick()
tick()
eq(target("weave"), 1, "SoD: five stacks light the weave slot with Feral Spirit down")
eq(target("feralspirit"), 0, "SoD: a cooling Feral Spirit stays dark")
sandbox.cooldowns = {}

-- Lava Lash answers with SS down (sim order), ahead of the shock filler.
ST.weave_mw_stacks = 3
sandbox.auras = {
    { name = "Maelstrom Weapon", count = 3, spell_id = 408505 },
}
ST.SHAMAN.on_aura_change(ST)
sandbox.cooldowns = {
    [17364] = { start = sandbox.clock, duration = 8 },
    ["Feral Spirit"] = { start = sandbox.clock, duration = 180 },
}
sandbox.target_auras = {
    { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 10,
        source = "player", spell_id = 8050 },
}
tick()
tick()
eq(target("weave"), 0, "SoD: 3 stacks with SS down never light the weave slot")
eq(target("lavalash"), 1, "SoD: 3 stacks with SS down answer Lava Lash")
sandbox.cooldowns["Lava Lash"] = { start = sandbox.clock, duration = 6 }
tick()
tick()
eq(target("lavalash"), 0, "SoD: a cooling Lava Lash stays dark")
eq(target("earthshock"), 1, "SoD: the shock filler answers with Lava Lash down")

-- The option stays the kill-switch even when observed.
class_db.weave_mw_enabled = false
eq(ST.SHAMAN.guide.gather(ST, gathered_target).mw_available, false,
    "SoD: option-off reports MW unavailable despite the latch")
tick()
eq(target("weave"), 0, "SoD: option-off suppresses the weave slot despite the latch")
class_db.weave_mw_enabled = true

-- Fixture restored: TBC client, no live aura, latch cleared.
sandbox.auras = {}
ST.SHAMAN.on_aura_change(ST)
ST.weave_mw_observed = false
sandbox.st.family = "TBC"
ST.weave_mw_stacks = 0
sandbox.cooldowns = {}
sandbox.target_auras = {}

-- G1 SoD ANY-stack weave fit (live-gate G1): the gather verifies a sub-5
-- LB/LvB hardcast fits the live swing on a WF-imbue SoD build at ANY stacks
-- incl 0-1; every other shape feeds nil (never prompts, old behaviour).
do
    sandbox.st.family = "ERA"
    ST.weave_mw_observed = true
    class_db.weave_mw_enabled = true
    ST.weave_is_casting = false
    ST.weave_windfury_active = true
    ST.weave_rockbiter_active = false
    ST.weave_mw_stacks = 3
    ST.latency = { world_ms = 0 }
    ST.weave_haste_mult = 1
    ST.mainhand = { speed = 3.0, ends_at = sandbox.clock + 2.0, start = sandbox.clock - 1.0, is_full = false }
    ST.weave_lava_burst = nil
    ST.weave_lava_burst_retry_at = nil
    sandbox.known[51505] = nil
    if not ST.weave_catalog or not ST.weave_catalog.LB then
        ST.weave_catalog = ST.weave_catalog or {}
        ST.weave_catalog.LB = { spell_id = 25449, name = "Lightning Bolt", icon = "icon_lb", cast_seconds = 2.5 }
    end
    local fit = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(fit.weave_sub5_ready, true, "G1 gather: a fitting LB hardcast feeds ready on a WF-imbue SoD build")
    eq(fit.weave_sub5_is_lavaburst, false, "G1 gather: without the rune the fit spell is Lightning Bolt")
    check(type(fit.weave_sub5_cast_seconds) == "number",
        "G1 gather: the effective sub-5 cast time is numeric in the window")
    -- The fit verdict reaches the engine: LB fit below Lava Lash lights the
    -- weave slot once LL cools.
    ST.weave_mw_stacks = 3
    sandbox.cooldowns = {
        [17364] = { start = sandbox.clock, duration = 8 },
        ["Feral Spirit"] = { start = sandbox.clock, duration = 180 },
        ["Lava Lash"] = { start = sandbox.clock, duration = 6 },
        [1535] = { start = sandbox.clock, duration = 15 },
    }
    sandbox.target_auras = {
        { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 10,
            source = "player", spell_id = 8050 },
    }
    tick()
    tick()
    eq(target("weave"), 1, "G1: a fit LB hardcast lights the weave slot below Lava Lash")
    sandbox.cooldowns = {}
    sandbox.target_auras = {}
    -- Lava Burst rune known: the fit spell is LvB (HIGH, above Stormstrike).
    sandbox.known[51505] = true
    ST.weave_lava_burst = nil
    ST.weave_lava_burst_retry_at = nil
    local lava_fit = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(lava_fit.weave_sub5_ready, true, "G1 gather: a fitting LvB hardcast feeds ready with the rune")
    eq(lava_fit.weave_sub5_is_lavaburst, true, "G1 gather: with the rune the fit spell is Lava Burst")
    sandbox.known[51505] = nil
    ST.weave_lava_burst = nil
    ST.weave_lava_burst_retry_at = nil
    -- A short swing withholds the fit (known-not-fit, still no prompt).
    ST.mainhand = { speed = 3.0, ends_at = sandbox.clock + 0.5, start = sandbox.clock - 2.5, is_full = false }
    local short = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(short.weave_sub5_ready, false, "G1 gather: a clipping cast feeds known-not-fit")
    eq(short.weave_sub5_is_lavaburst, false, "G1 gather: the spell stays Lightning Bolt when the cast clips")
    ST.mainhand = { speed = 3.0, ends_at = sandbox.clock + 2.0, start = sandbox.clock - 1.0, is_full = false }
    -- Imbue-build gate: no WF imbue never feeds ready (WF-build only weaves).
    ST.weave_windfury_active = false
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "G1 gather: a dropped WF imbue clears the fit feed")
    ST.weave_windfury_active = true
    -- A Rockbiter build never feeds ready (SoD sim runs WF/WF).
    ST.weave_rockbiter_active = true
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "G1 gather: a Rockbiter build never feeds the fit")
    ST.weave_rockbiter_active = false
    -- ANY stacks incl 0-1 feed (the SoD sim weaves at ANY stacks when the
    -- cast fits); 5 stays on rule 5 (the instant). The 0-1 casts are nearly
    -- full-length, so these pins widen the swing to one that fits them.
    ST.mainhand = { speed = 3.0, ends_at = sandbox.clock + 3.0, start = sandbox.clock, is_full = false }
    ST.weave_mw_stacks = 1
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, true,
        "G1 gather: 1 stack feeds ready when the cast fits (0-1 hardcast)")
    ST.weave_mw_stacks = 0
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, true,
        "G1 gather: 0 stacks feed ready when the cast fits (0-1 hardcast)")
    ST.mainhand = { speed = 3.0, ends_at = sandbox.clock + 2.0, start = sandbox.clock - 1.0, is_full = false }
    ST.weave_mw_stacks = 5
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "G1 gather: 5 stacks never feed the fit (rule 5 owns the instant)")
    ST.weave_mw_stacks = 3
    -- Casting withholds the fit (rule 1 RIDE holds anyway).
    ST.weave_is_casting = true
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "G1 gather: casting never feeds the fit")
    ST.weave_is_casting = false
    -- Non-SoD families: TBC/Era-base never feed (no MW there).
    sandbox.st.family = "TBC"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "G1 gather: TBC never feeds the fit")
    -- M1 Wrath sub-5 (default_wf APL: MW>=3 + 300 ms + cast fits): the Wrath
    -- branch feeds ready under the same WF-imbue gate with a 3-4 stack window
    -- and the 300 ms buffer; the spell is always Lightning Bolt (LvB is
    -- Elemental-only there, the lava resolver answers nil off ERA).
    sandbox.st.family = "WRATH"
    sandbox.known[49238] = true
    ST.weave_mw_stacks = 3
    local m1 = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(m1.weave_sub5_ready, true, "M1 gather: a fitting Wrath LB hardcast feeds ready at 3 stacks")
    eq(m1.weave_sub5_is_lavaburst, false, "M1 gather: the Wrath fit spell is always Lightning Bolt")
    check(type(m1.weave_sub5_cast_seconds) == "number",
        "M1 gather: the Wrath effective cast time is numeric in the window")
    -- The fit verdict reaches the engine HIGH: the weave slot lights with SS
    -- ready (rule 5c outranks Stormstrike, unlike the SoD LOW fit).
    sandbox.cooldowns = {}
    sandbox.target_auras = {
        { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 10,
            source = "player", spell_id = 8050 },
    }
    tick()
    tick()
    eq(target("weave"), 1, "M1: a fit Wrath LB hardcast lights the weave slot above Stormstrike")
    sandbox.cooldowns = {}
    sandbox.target_auras = {}
    -- Effective at 3 stacks is 2.5 * 0.4 = 1.0 s: the 300 ms buffer (not the
    -- SoD 100 ms) decides the boundary - 1.25 s remaining withholds where the
    -- SoD buffer would still fit.
    ST.mainhand = { speed = 3.0, ends_at = sandbox.clock + 1.35, start = sandbox.clock - 1.65, is_full = false }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, true,
        "M1 gather: effective + latency + 300 ms fits on Wrath")
    ST.mainhand = { speed = 3.0, ends_at = sandbox.clock + 1.25, start = sandbox.clock - 1.75, is_full = false }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, false,
        "M1 gather: just inside 300 ms withholds on Wrath (SoD 100 ms would fit)")
    ST.mainhand = { speed = 3.0, ends_at = sandbox.clock + 2.0, start = sandbox.clock - 1.0, is_full = false }
    -- MIN boundary: 0-2 stacks never feed on Wrath (M1 is MW>=3); 5 stays on
    -- rule 5.
    ST.weave_mw_stacks = 2
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "M1 gather: 2 stacks never feed the fit on Wrath (MW>=3)")
    ST.weave_mw_stacks = 4
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, true,
        "M1 gather: 4 stacks feed ready when the cast fits on Wrath")
    ST.weave_mw_stacks = 5
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "M1 gather: 5 stacks never feed the fit on Wrath (rule 5 owns the instant)")
    ST.weave_mw_stacks = 1
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "M1 gather: 1 stack never feeds the fit on Wrath (SoD ANY does not apply)")
    ST.weave_mw_stacks = 0
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "M1 gather: 0 stacks never feed the fit on Wrath")
    ST.weave_mw_stacks = 3
    -- Known gate: RE-CUT (2026-10-25, operator ruling - Wrath state queries carry the
    -- localized NAME), so "unknown LB" means the client knows NO Lightning Bolt rank;
    -- the cited 49238 id is not the query form. Clear both rank ids the name leg reads,
    -- even with the SoD catalogue rank present.
    sandbox.known[49238] = nil
    sandbox.known[25449] = nil
    sandbox.known[25448] = nil
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "M1 gather: an unknown Wrath LB never feeds the fit")
    sandbox.known[25449] = true
    sandbox.known[49238] = true
    -- The Wrath branch needs no MW latch (Wrath has the talent, not the SoD
    -- rune): unobserved still feeds.
    ST.weave_mw_observed = false
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, true,
        "M1 gather: Wrath feeds without the MW latch")
    ST.weave_mw_observed = true
    -- Imbue-build gate: no WF imbue / a Rockbiter build never feed on Wrath.
    ST.weave_windfury_active = false
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "M1 gather: a dropped WF imbue clears the Wrath fit feed")
    ST.weave_windfury_active = true
    ST.weave_rockbiter_active = true
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "M1 gather: a Rockbiter build never feeds the Wrath fit")
    ST.weave_rockbiter_active = false
    -- Casting withholds the fit on Wrath too.
    ST.weave_is_casting = true
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "M1 gather: casting never feeds the Wrath fit")
    ST.weave_is_casting = false
    -- The option kill-switch withholds the Wrath fit.
    class_db.weave_mw_enabled = false
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "M1 gather: option-off never feeds the Wrath fit")
    class_db.weave_mw_enabled = true
    -- LvB never resolves off ERA: with the rune fixture marked known the
    -- Wrath spell stays Lightning Bolt.
    sandbox.known[51505] = true
    local m1_lava = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(m1_lava.weave_sub5_ready, true, "M1 gather: the fit survives a known SoD rune off ERA")
    eq(m1_lava.weave_sub5_is_lavaburst, false, "M1 gather: LvB never resolves on Wrath")
    sandbox.known[51505] = nil
    sandbox.known[49238] = nil
    ST.weave_mw_observed = false
    sandbox.st.family = "ERA"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "G1 gather: Era-base never feeds the fit")
    ST.weave_mw_observed = true
    -- The option kill-switch withholds the fit with MW.
    class_db.weave_mw_enabled = false
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).weave_sub5_ready, nil,
        "G1 gather: option-off never feeds the fit")
    class_db.weave_mw_enabled = true
    -- Stale fields are overwritten on the reused table.
    sandbox.st.family = "TBC"
    local stale_fit = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(stale_fit.weave_sub5_ready, nil, "G1 gather: the fit feed is re-fed, not stale")
    eq(stale_fit.weave_sub5_cast_seconds, nil, "G1 gather: the cast feed is re-fed, not stale")
    eq(stale_fit.weave_sub5_is_lavaburst, nil, "G1 gather: the spell feed is re-fed, not stale")
    -- Fixture restored for the blocks below: TBC client, no live aura.
    sandbox.st.family = "TBC"
    ST.weave_mw_observed = false
    ST.weave_mw_stacks = 0
    ST.weave_windfury_active = false
    ST.weave_rockbiter_active = false
    sandbox.cooldowns = {}
    sandbox.target_auras = {}
end

-- SoD Lava Burst choice: on ERA the weave slot re-points at the rune when the
-- client knows it, and keeps the catalogue without it (Era-base byte-identical).
do
    local lava = build()
    lava.st.family = "ERA"
    lava.ST.SHAMAN.post_init(lava.ST)
    eq(lava.ST.SHAMAN.guide.slots[3].spell_id, 51505,
        "SoD: the weave slot re-points at Lava Burst when the rune is known")
    eq(lava.ST.SHAMAN.guide.slots[3].key, "weave",
        "SoD: the re-point keeps the weave slot identity")
    local saved_lava = SPELL_INFOS[51505]
    SPELL_INFOS[51505] = nil
    local base = build()
    base.st.family = "ERA"
    base.ST.SHAMAN.post_init(base.ST)
    eq(base.ST.SHAMAN.guide.slots[3].spell_id, 25449,
        "Era-base: without the rune the weave slot keeps the catalogue")
    SPELL_INFOS[51505] = saved_lava
end

-- Option gates: disabled hides the frame and stops the mapping; visibility follows the
-- in-combat key; the size/position/lock diff applies live.
sandbox.cooldowns = {}
tick()
local before_disable = target("stormstrike")
class_db.nextaction_enabled = false
tick()
eq(ui.frame.shown, false, "nextaction_enabled=false hides the frame")
eq(target("stormstrike"), before_disable, "the gated tick leaves the slot targets alone")
class_db.nextaction_enabled = true
tick()
eq(ui.frame.shown, true, "re-enabling brings the frame back")
class_db.nextaction_visibility_key = "always"
ST.in_combat = false
tick()
eq(ui.frame.shown, true, "the always visibility key keeps the frame out of combat")
class_db.nextaction_visibility_key = "in_combat"
tick()
eq(ui.frame.shown, false, "the in_combat key hides the frame out of combat")
ST.in_combat = true
tick()
eq(ui.frame.shown, true, "back in combat the frame returns")

class_db.nextaction_icon_size = 60
class_db.nextaction_locked = false
tick()
near(ui.frame.scale, 60 / 45, 1e-9, "the icon-size option rescales the live frame")
eq(ST.guide_ui_icon_size, 60, "the settings diff latches the applied size")
eq(ui.frame.movable, true, "unlocking makes the frame movable")
class_db.nextaction_x = 25
class_db.nextaction_icon_size = 45
class_db.nextaction_locked = true
tick()
near(ui.frame.scale, 1, 1e-9, "the size option restores the scale")
eq(ui.frame.movable, false, "locking makes the frame immovable again")
eq(ui.frame.points and ui.frame.points[1][4], 25, "the position option moves the live frame")

-- The hand gates: an offhand call only mirrors the spark, never ticks the guide.
local before_offhand = target("stormstrike")
sandbox.advance(1.0)
ST.SHAMAN.on_bar_update(ST, "offhand")
eq(target("stormstrike"), before_offhand, "the offhand call does not tick the guide")

--=========================================================================================
-- 4) Config/options parity, the TOC load order and the drive call sites
--=========================================================================================
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    local presets = read("config_presets.lua")
    local shaman_defaults = presets:match("ST%.SHAMAN%.defaults%s*=%s*%{(.-)ST%.WARLOCK%.defaults") or ""
    local options = read("option_tables.lua")
    local shaman_opts = options:match("function ST%.class_opts_funcs%.SHAMAN%((.-)function ST:generate_bar_position_options_table") or ""

    local expected_defaults = {
        nextaction_enabled = "true",
        nextaction_locked = "true",
        nextaction_visibility_key = "\"in_combat\"",
        nextaction_icon_size = "45",
        nextaction_x = "127",
        nextaction_y = "-65",
        guide_flameshock_refresh = "0",
    }
    for key, value in pairs(expected_defaults) do
        check(shaman_defaults:find("%f[%a_]" .. key .. "%s*=%s*" .. value, 1) ~= nil,
            "config_presets.lua: SHAMAN default " .. key .. " = " .. value)
    end

    local widget_types = {
        nextaction_enabled = "toggle",
        nextaction_locked = "toggle",
        nextaction_visibility_key = "select",
        nextaction_icon_size = "range",
        nextaction_x = "input",
        nextaction_y = "input",
        guide_flameshock_refresh = "range",
    }
    for key, wtype in pairs(widget_types) do
        local widget = shaman_opts:match("%f[%a_]" .. key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"" .. wtype .. "\"") ~= nil,
            "option_tables.lua: " .. key .. " has a " .. wtype .. " widget")
    end
    check(shaman_opts:find("Next Action Guide") ~= nil,
        "option_tables.lua: the shaman options carry a Next Action Guide block")
    local fs_widget = shaman_opts:match("guide_flameshock_refresh%s*=%s*{(.-)\n%s*}") or ""
    check(fs_widget:find("min%s*=%s*0[^%d]") ~= nil and fs_widget:find("max%s*=%s*10") ~= nil,
        "option_tables.lua: guide_flameshock_refresh is a 0-10 range")

    -- shaman_guide.lua loads after nextaction.lua in every TOC.
    local tocs = { "SwedgeTimer.toc", "SwedgeTimer_Vanilla.toc", "SwedgeTimer_TBC.toc",
        "SwedgeTimer_Wrath.toc", "SwedgeTimer_Mainline.toc", "SwedgeTimer_Cata.toc",
        "SwedgeTimer_Mists.toc" }
    for i = 1, #tocs do
        local text = read(tocs[i])
        local after = text:find("\nnextaction.lua", 1, true)
        local guide_at = text:find("\nshaman_guide.lua", 1, true)
        check(after ~= nil and guide_at ~= nil and guide_at > after,
            tocs[i] .. ": shaman_guide.lua loads after nextaction.lua")
    end

    -- The drive call sites live in classes/shaman.lua.
    local shaman_src = read("classes/shaman.lua")
    check(shaman_src:find("st%.nextaction_ui%.init%(self%)") ~= nil,
        "classes/shaman.lua: post_init drives st.nextaction_ui.init")
    check(shaman_src:find("st%.nextaction_ui%.on_bar_update%(self, hand%)") ~= nil,
        "classes/shaman.lua: on_bar_update drives st.nextaction_ui.on_bar_update")
    check(shaman_src:find("st%.nextaction_ui%.apply_settings%(self%)") ~= nil,
        "classes/shaman.lua: the settings diff applies live")
    check(shaman_src:find("self%.SHAMAN%.resolve_guide_icons%(self%)") ~= nil,
        "classes/shaman.lua: post_init drives the weave-icon resolver")
    check(shaman_src:find("ST%.SHAMAN%.gather_guide_inputs%(self, out%)") ~= nil,
        "classes/shaman.lua: the provider delegates to the gather")
    check(shaman_src:find("st%.weave%.has_maelstrom_weapon%(st%.family,") ~= nil,
        "classes/shaman.lua: the MW gate feeds the family plus the observed latch")
    check(shaman_src:find("weave_mw_observed%s*=%s*true") ~= nil,
        "classes/shaman.lua: the aura scan latches the observed MW signal")
    check(shaman_src:find("weave_mw_observed%s*=%s*false") ~= nil,
        "classes/shaman.lua: post_init clears the observed MW latch")
    check(shaman_src:find("get_windfury_icd_remaining%(d%.start, now,") ~= nil,
        "classes/shaman.lua: the gather feeds the Windfury ICD with the family window")
    check(shaman_src:find("inputs%.twist_remaining = nil") ~= nil,
        "classes/shaman.lua: the gather re-feeds the twist input every tick")
    check(shaman_src:find("WEAVE_FERAL_SPIRIT_SPELL_ID") ~= nil,
        "classes/shaman.lua: the Feral Spirit slot id is declared")
    check(shaman_src:find("WEAVE_FIRE_ELEMENTAL_SPELL_ID") ~= nil,
        "classes/shaman.lua: the Fire Elemental slot id is declared")
    check(shaman_src:find("WEAVE_MAGMA_TOTEM_SPELL_ID") ~= nil,
        "classes/shaman.lua: the Magma Totem slot id is declared")
    check(shaman_src:find("WEAVE_LAVA_LASH_SPELL_ID") ~= nil,
        "classes/shaman.lua: the Lava Lash slot id is declared")
    check(shaman_src:find("get_guide_cooldown_known") ~= nil,
        "classes/shaman.lua: the cooldown slots are known-gated")
    check(shaman_src:find("refresh_magma_from_totems") ~= nil,
        "classes/shaman.lua: the Magma fire-slot reconciliation is wired")
    check(shaman_src:find("weave_magma_last_drop%s*=%s*nil") ~= nil,
        "classes/shaman.lua: post_init clears the Magma stamp")
    check(shaman_src:find("Lava Burst") ~= nil,
        "classes/shaman.lua: the SoD Lava Burst re-point is wired")
    check(shaman_src:find("inputs%.magma_refresh") ~= nil,
        "classes/shaman.lua: the gather re-feeds the magma refresh every tick")

    -- The engine's frozen shape: fifteen actions, no MW>=3 hardcast, no frost.
    local guide_src = read("shaman_guide.lua")
    check(guide_src:find("mw_stacks >= 3", 1, true) == nil,
        "shaman_guide.lua: no MW>=3 hardcast rule survives (MW5-only)")
    check(guide_src:find("\"magma\"", 1, true) ~= nil,
        "shaman_guide.lua: the magma action is declared")
    check(guide_src:find("\"lavalash\"", 1, true) ~= nil,
        "shaman_guide.lua: the lavalash action is declared")
    check(guide_src:find("\"shamanisticrage\"", 1, true) ~= nil,
        "shaman_guide.lua: the shamanisticrage action is declared")
    check(guide_src:find("\"chainlightning\"", 1, true) ~= nil,
        "shaman_guide.lua: the chainlightning action is declared")
    check(guide_src:find("\"moltenblast\"", 1, true) ~= nil,
        "shaman_guide.lua: the moltenblast action is declared")
    check(guide_src:find("\"wftotem\"", 1, true) ~= nil,
        "shaman_guide.lua: the wftotem action is declared")
    check(guide_src:find("\"goa\"", 1, true) ~= nil,
        "shaman_guide.lua: the goa action is declared")
    check(guide_src:find("stormstrike_hold_enabled", 1, true) ~= nil,
        "shaman_guide.lua: the hold opt-in is declared")
    check(guide_src:find("flameshock_allowed", 1, true) ~= nil,
        "shaman_guide.lua: the Era maintain veto is declared")
    check(guide_src:find("SR_MANA_THRESHOLD", 1, true) ~= nil,
        "shaman_guide.lua: the SR family gates are declared")
    check(guide_src:find("fireele_active", 1, true) ~= nil,
        "shaman_guide.lua: the Fire Elemental guard is declared")
    check(guide_src:find("\"fireele\"", 1, true) ~= nil,
        "shaman_guide.lua: the fireele action is declared")
    check(guide_src:find("\"feralspirit\"", 1, true) ~= nil,
        "shaman_guide.lua: the feralspirit action is declared")
    check(guide_src:find("MAGMA_REFRESH_DEFAULT", 1, true) ~= nil,
        "shaman_guide.lua: the magma refresh constant is declared")
    local weave_src = read("weave.lua")
    check(weave_src:find("get_magma_remaining", 1, true) ~= nil,
        "weave.lua: the Magma remaining helper is declared")
    check(weave_src:find("get_windfury_icd_seconds", 1, true) ~= nil,
        "weave.lua: the family ICD window is declared")
    check(weave_src:find("get_fireele_remaining", 1, true) ~= nil,
        "weave.lua: the Fire Elemental remaining helper is declared")
    check(weave_src:find("FIRE_ELEMENTAL_DURATION_SECONDS", 1, true) ~= nil,
        "weave.lua: the Fire Elemental duration constant is declared")
    check(weave_src:find("MAGMA_TOTEM_DURATION_SECONDS", 1, true) ~= nil,
        "weave.lua: the Magma duration constant is declared")
    check(weave_src:find("WINDFURY_MAX_PROCS_PER_MINUTE", 1, true) ~= nil,
        "weave.lua: the Windfury proc-ceiling constant is declared")
    check(weave_src:find("is_windfury_proc_capped", 1, true) ~= nil,
        "weave.lua: the proc-ceiling helper is declared")
    check(weave_src:find("TOTEM_TWIST_PULSE_SECONDS", 1, true) ~= nil,
        "weave.lua: the twist-pulse constant is declared")
    check(weave_src:find("is_totem_twist_family", 1, true) ~= nil,
        "weave.lua: the twist-family gate is declared")
    check(shaman_src:find("is_totem_twist_family", 1, true) ~= nil,
        "classes/shaman.lua: the twist feed is gated through the pure helper")
    check(shaman_src:find("resolve_named_spell", 1, true) ~= nil,
        "classes/shaman.lua: the SoD name feeds are wired")
    check(shaman_src:find("windfury_window", 1, true) ~= nil,
        "classes/shaman.lua: the strip/guide share one ICD window")
    check(shaman_src:find("weave_fireele_last_drop", 1, true) ~= nil,
        "classes/shaman.lua: the Fire Elemental stamp is wired")
    check(shaman_src:find("weave_clearcasting", 1, true) ~= nil,
        "classes/shaman.lua: the Clearcasting feed is wired")
    check(shaman_src:find("Rage of the Farseer", 1, true) ~= nil,
        "classes/shaman.lua: the Farseer lust leg is wired")
end

--=========================================================================================
-- Retail (12.x) inertness: the stand-in never swings, but the cast flag, the
-- absent-debuff default and the idle-cooldown defaults answer on Retail - every
-- such shape must stay empty.
--=========================================================================================
do
    local saved_family = pure.family
    pure.family = "RETAIL"
    -- The baseline (ready Stormstrike) stays silent.
    local out = evaluate({})
    eq(out.action, nil, "retail: a ready Stormstrike never prompts")
    eq(out.hold, false, "retail: a ready Stormstrike never holds")
    -- The Flame Shock refresh (nil always refreshes) stays silent.
    eq(evaluate({ flameshock_remaining = NONE }).action, nil,
        "retail: a missing Flame Shock never prompts")
    -- A cast in flight never rides.
    local casting = evaluate({ casting = true })
    eq(casting.action, nil, "retail: a cast in flight never prompts")
    eq(casting.hold, false, "retail: a cast in flight never rides")
    eq(casting.hold_text, nil, "retail: a cast in flight carries no RIDE text")
    -- Five Maelstrom stacks never weave, even with availability forged on.
    eq(evaluate({ mw_stacks = 5, mw_available = true }).action, nil,
        "retail: five Maelstrom stacks never prompt")
    -- The shock filler (Fire Nova on cooldown, Stormstrike down) never prompts.
    eq(evaluate({ stormstrike_remaining = 5, firenova_remaining = 0 }).action, nil,
        "retail: Fire Nova never prompts")
    -- The Wrath slots never prompt either, ready or not.
    eq(evaluate({ fireele_remaining = 0 }).action, nil,
        "retail: a ready Fire Elemental never prompts")
    eq(evaluate({ feralspirit_remaining = 0 }).action, nil,
        "retail: a ready Feral Spirit never prompts")
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = 0 }).action, nil,
        "retail: a due Magma never prompts")
    eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
        lavalash_remaining = 0 }).action, nil,
        "retail: a ready Lava Lash never prompts")
    eq(evaluate({ sr_remaining = 0 }).action, nil,
        "retail: a ready Shamanistic Rage never prompts")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 4, firenova_remaining = 5,
        lavalash_remaining = 5, shock_remaining = 5, target_count = 2 }).action, nil,
        "retail: multi-target Chain Lightning never prompts")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
        lavalash_remaining = 5, shock_remaining = 8, moltenblast_remaining = 0 }).action,
        nil, "retail: a ready Molten Blast never prompts")
    eq(out.waiting_judgement, false, "retail: the judgement carry stays false")
    -- A stale out table is fully overwritten (no frozen field survives).
    local stale = { action = "stormstrike", hold = true, hold_text = "WAIT",
        filler_slot = "stormstrike", judge_slot = "x", rotation_key = "y",
        waiting_judgement = true }
    local ret = sg.evaluate(inp({}), stale)
    eq(ret, stale, "retail: evaluate returns the caller's out table")
    eq(stale.action, nil, "retail: a stale action is cleared")
    eq(stale.hold, false, "retail: a stale hold is cleared")
    eq(stale.hold_text, nil, "retail: stale hold text is cleared")
    eq(stale.filler_slot, nil, "retail: a stale filler_slot is cleared")
    eq(stale.judge_slot, nil, "retail: a stale judge_slot is cleared")
    eq(stale.rotation_key, nil, "retail: a stale rotation_key is cleared")
    eq(stale.waiting_judgement, false, "retail: a stale judgement carry is cleared")
    -- The gate is Retail-specific: any other family still prompts.
    pure.family = "WRATH"
    eq(evaluate({}).action, "stormstrike",
        "non-retail family: a ready Stormstrike still prompts")
    pure.family = saved_family
end

-- Name-vs-id classification (bench/lessons.md): the pure engine has NO
-- spell-id uses in scope (no GetSpellInfo / GetSpellCooldown / is_spell_known /
-- spell_id reads) — all TBC-name vs Era-id resolution lives in the gather
-- (classes/shaman.lua, pinned by tests/shaman_state.lua §31). Pinned here
-- statically so a future id probe cannot slip into the pure module.
do
    local path = ROOT .. "shaman_guide.lua"
    local fh = io.open(path, "r")
    local src = fh and fh:read("*a")
    if fh then fh:close() end
    check(src ~= nil, "name-vs-id: shaman_guide.lua is readable")
    if src then
        check(not src:find("api.GetSpellInfo(", 1, true), "name-vs-id: pure engine never calls GetSpellInfo")
        check(not src:find("api.GetSpellCooldown(", 1, true), "name-vs-id: pure engine never calls GetSpellCooldown")
        check(not src:find("api.is_spell_known(", 1, true), "name-vs-id: pure engine never probes known spells")
        check(not src:find("api.GetSpellPowerCost(", 1, true), "name-vs-id: pure engine never reads power costs")
    end
end

--=========================================================================================
-- 5) The practice surface (bench/class_features_drills_2026-10-19.md §2.6 C + D)
--=========================================================================================
-- The pure half of the practice contract: the ctx -> frozen input writer, the
-- scenario step and the four target drills. The strict sandbox has no weave.lua
-- (the weave drill must stay unscored without it - unknown-hides) and no WoW API.
do
    -- The frozen input set, written out by hand from the module header. The
    -- practice writer must cover every one of them (the ctx can drive the whole
    -- engine) and may not invent a name that is not a frozen input.
    local FROZEN_INPUTS = {
        speed = true, swing_remaining = true, gcd_remaining = true, casting = true,
        mw_available = true, mw_stacks = true, weave_available = true,
        weave_sub5_ready = true, weave_sub5_cast_seconds = true,
        weave_sub5_is_lavaburst = true, flameshock_remaining = true,
        flameshock_refresh = true, flameshock_allowed = true, fight_elapsed = true,
        stormstrike_remaining = true, stormstrike_hold_enabled = true,
        windfury_icd_remaining = true, firenova_remaining = true, fireele_active = true,
        twist_remaining = true, twist_mana_threshold = true, fireele_remaining = true,
        feralspirit_remaining = true, magma_remaining = true, magma_refresh = true,
        lavalash_remaining = true, sr_remaining = true, sr_mana_threshold = true,
        mana_fraction = true, shock_remaining = true, target_count = true,
        moltenblast_remaining = true, wftotem_remaining = true,
        goatotem_remaining = true, clearcasting_active = true,
        searing_down = true, mw_observed = true, lightningshield_due = true,
        water_remaining = true, water_duration = true,
        strength_of_earth_remaining = true, mana_spring_remaining = true,
        bloodlust_remaining = true, frostshock_remaining = true, filler_shock = true,
    }
    check(type(sg.PRACTICE_COOLDOWN_FIELDS) == "table", "the practice cooldown map exists")
    check(type(sg.PRACTICE_RESOURCE_FIELDS) == "table", "the practice resource map exists")
    local covered = {}
    local frozen_ok, invented = true, nil
    for i = 1, #sg.PRACTICE_COOLDOWN_FIELDS do
        local entry = sg.PRACTICE_COOLDOWN_FIELDS[i]
        if type(entry) ~= "table" or type(entry[1]) ~= "string" or type(entry[2]) ~= "string" then
            frozen_ok = false
        elseif not FROZEN_INPUTS[entry[2]] then
            frozen_ok = false
            invented = entry[2]
        else
            covered[entry[2]] = true
        end
    end
    for i = 1, #sg.PRACTICE_RESOURCE_FIELDS do
        local name = sg.PRACTICE_RESOURCE_FIELDS[i]
        if type(name) ~= "string" or not FROZEN_INPUTS[name] then
            frozen_ok = false
            invented = name
        else
            covered[name] = true
        end
    end
    check(frozen_ok, "every practice field is a frozen engine input (bad: " .. tostring(invented) .. ")")
    local missing = nil
    for name in pairs(FROZEN_INPUTS) do
        if not covered[name] then missing = name end
    end
    eq(missing, nil, "the practice writer covers every frozen input (missing: " .. tostring(missing) .. ")")

    -- The reasons: one short line per action the engine can return (the guide
    -- slot keys - the same list the class suite pins against the slot table).
    check(type(sg.PRACTICE_REASONS) == "table", "the practice reason table exists")
    local REASON_ACTIONS = { "fireele", "feralspirit", "shamanisticrage", "weave",
        "flameshock", "twist", "wftotem", "goa", "stormstrike", "searing", "magma",
        "firenova", "lightningshield", "lavalash", "chainlightning", "earthshock",
        "moltenblast", "coe", "bloodlust", "strength_of_earth", "mana_spring",
        "frostshock" }
    for i = 1, #REASON_ACTIONS do
        local action = REASON_ACTIONS[i]
        check(type(sg.PRACTICE_REASONS[action]) == "string"
            and sg.PRACTICE_REASONS[action] ~= "",
            "the reason table answers " .. action)
    end

    -- The input writer: the ctx -> frozen input mapping.
    local written = sg.build_practice_inputs({
        now = 100,
        cooldowns = { stormstrike = 0, flameshock = 10, firenova = 5, shock = 2 },
        resources = { mana_fraction = 0.4, mw_stacks = 3, target_count = 2,
            stormstrike_hold_enabled = true, fight_elapsed = 25, swing_remaining = 1.5 },
    }, {})
    eq(written.stormstrike_remaining, 0, "the writer maps ctx.cooldowns.stormstrike")
    eq(written.flameshock_remaining, 10, "the writer maps ctx.cooldowns.flameshock")
    eq(written.firenova_remaining, 5, "the writer maps ctx.cooldowns.firenova")
    eq(written.shock_remaining, 2, "the writer maps ctx.cooldowns.shock")
    eq(written.mana_fraction, 0.4, "the writer maps ctx.resources.mana_fraction")
    eq(written.mw_stacks, 3, "the writer maps ctx.resources.mw_stacks")
    eq(written.target_count, 2, "the writer maps ctx.resources.target_count")
    eq(written.stormstrike_hold_enabled, true, "the writer maps the hold opt-in")
    eq(written.fight_elapsed, 25, "the writer maps ctx.resources.fight_elapsed")
    eq(written.swing_remaining, 1.5, "the writer maps ctx.resources.swing_remaining")
    -- The "_remaining" spelling is an accepted alias.
    local aliased = sg.build_practice_inputs({ cooldowns = { stormstrike_remaining = 7 } }, {})
    eq(aliased.stormstrike_remaining, 7, "the writer accepts the _remaining alias")
    -- The action keys the rotation table uses are accepted too, including the two
    -- where the action key and the frozen input name differ.
    local keyed = sg.build_practice_inputs({ cooldowns = { goa = 0, earthshock = 2,
        shamanisticrage = 3 } }, {})
    eq(keyed.goatotem_remaining, 0, "the writer accepts the Grace of Air action key")
    eq(keyed.shock_remaining, 2, "the writer accepts the Earth Shock action key")
    eq(keyed.sr_remaining, 3, "the writer accepts the Shamanistic Rage action key")
    -- The two maintain slots ride their due flags (the action key, then the
    -- frozen input name).
    local maintains = sg.build_practice_inputs({ cooldowns = { searing = true,
        lightningshield = true } }, {})
    eq(maintains.searing_down, true, "the writer accepts the Searing action key")
    eq(maintains.lightningshield_due, true, "the writer accepts the Lightning Shield action key")
    local maintains_named = sg.build_practice_inputs({ resources = {
        searing_down = true, lightningshield_due = true, mw_observed = true } }, {})
    eq(maintains_named.searing_down, true, "the writer accepts the Searing due flag by name")
    eq(maintains_named.lightningshield_due, true,
        "the writer accepts the Lightning Shield due flag by name")
    eq(maintains_named.mw_observed, true, "the writer maps the SoD latch")
    -- A nil ctx writes nothing (never a guess).
    local empty = sg.build_practice_inputs(nil, {})
    local empty_fields = 0
    for _ in pairs(empty) do empty_fields = empty_fields + 1 end
    eq(empty_fields, 0, "a nil ctx writes no input")
    -- A reused table never keeps a stale value.
    local reused = sg.build_practice_inputs({ cooldowns = { stormstrike = 4 },
        resources = { mw_stacks = 5 } }, reused)
    reused = sg.build_practice_inputs({ cooldowns = { firenova = 1 } }, reused)
    eq(reused.stormstrike_remaining, nil, "the reused table drops the stale Stormstrike")
    eq(reused.mw_stacks, nil, "the reused table drops the stale stacks")
    eq(reused.firenova_remaining, 1, "the reused table carries the new read")

    -- The scenario step: the rotation's next action, or nil when undecidable.
    local step = sg.practice_step({ now = 100,
        cooldowns = { stormstrike = 0, flameshock = 10 } })
    check(type(step) == "table", "the step answers a table")
    eq(step.action, "stormstrike", "the step answers the engine's action")
    eq(step.reason, "Stormstrike off cooldown", "the step carries the reason line")
    eq(sg.practice_step({ now = 100, resources = { casting = true } }), nil,
        "a cast in flight leaves the step undecidable")
    -- An empty ctx is not undecidable: the engine's own nil-Flame-Shock rule
    -- always refreshes (the frozen rule 6), so the step answers that verdict.
    -- The step is the engine's verdict, never a second opinion.
    eq(sg.practice_step(nil).action, "flameshock",
        "an empty ctx answers the engine's own verdict (the nil Flame Shock refreshes)")
    -- The reason line for the weave reads the stack count.
    local weave_step = sg.practice_step({ now = 100, cooldowns = { stormstrike = 8,
        flameshock = 10 }, resources = { mw_available = true, mw_stacks = 5 } })
    eq(weave_step.action, "weave", "five stacks answer the weave")
    eq(weave_step.reason, "Five Maelstrom stacks - instant weave", "the weave reason names the stacks")
    local sub5_step = sg.practice_step({ now = 100, cooldowns = { stormstrike = 8,
        flameshock = 10 }, resources = { mw_available = true, mw_stacks = 2,
        weave_sub5_ready = true, weave_sub5_is_lavaburst = true } })
    eq(sub5_step.action, "weave", "a verified sub-5 fit answers the weave")
    eq(sub5_step.reason, "Sub-5 weave fits the swing", "the sub-5 reason names the fit")
    -- The two maintain slots are teachable: the scenario step answers them when
    -- the engine does (S-19 / S-17). The pure surface reads st.family (the
    -- class-side step swaps it for the ctx's family), so the pins set it.
    do
        local saved_family = pure.family
        pure.family = "ERA"
        local searing_step = sg.practice_step({ now = 100, resources = {
            stormstrike_remaining = 8, flameshock_remaining = 10, fight_elapsed = 25,
            searing_down = true } })
        eq(searing_step.action, "searing", "a due Searing answers the searing slot")
        eq(searing_step.reason, "Searing Totem due", "the Searing reason names the maintain")
        pure.family = "WRATH"
        local shield_step = sg.practice_step({ now = 100, resources = {
            stormstrike_remaining = 8, flameshock_remaining = 10, firenova_remaining = 5,
            lightningshield_due = true } })
        eq(shield_step.action, "lightningshield", "a due Lightning Shield answers its slot")
        eq(shield_step.reason, "Lightning Shield due",
            "the Lightning Shield reason names the maintain")
        local coe_step = sg.practice_step({ now = 100, resources = {
            stormstrike_remaining = 8, flameshock_remaining = 10, firenova_remaining = 5 } })
        check(coe_step.action ~= "coe",
            "the Call of the Elements is never answered (filed, no slot)")
        pure.family = saved_family
    end

    -- Drill D-S1: the enhancement priority.
    eq(sg.grade_enh_priority({ now = 100, cooldowns = { stormstrike = 0, flameshock = 10 },
        last_action = "stormstrike" }), "S", "D-S1: the expected action grades S")
    eq(sg.grade_enh_priority({ now = 100, cooldowns = { stormstrike = 0, flameshock = 10 },
        last_action = "flameshock" }), "F", "D-S1: a different action grades F")
    eq(sg.grade_enh_priority({ now = 100, cooldowns = { stormstrike = 0, flameshock = 10 } }),
        nil, "D-S1: nothing cast grades nothing")
    eq(sg.grade_enh_priority({ now = 100, resources = { casting = true },
        last_action = "stormstrike" }), nil, "D-S1: a hold grades nothing")
    eq(sg.grade_enh_priority(nil), nil, "D-S1: a nil ctx grades nothing")

    -- Drill D-S2: the stack decision. Without weave.lua there is no marker, so
    -- the drill never grades (unknown-hides).
    eq(sg.grade_mw_weave({ now = 100, last_action = "weave",
        resources = { mw_stacks = 5, swing_remaining = 1.0 } }), nil,
        "D-S2: without weave.lua the weave drill never grades")
    eq(sg.grade_mw_weave({ now = 100, last_action = "stormstrike",
        resources = { mw_stacks = 5, swing_remaining = 1.0 } }), nil,
        "D-S2: a non-weave press is not scored")

    -- Drill D-S3: the Stormstrike decision.
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "stormstrike",
        resources = { ss_ready_at = 100 } }), "S", "D-S3: pressing on cooldown grades S")
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "stormstrike",
        resources = { ss_ready_at = 99 } }), "A", "D-S3: one GCD late grades A")
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "stormstrike",
        resources = { ss_ready_at = 97 } }), "B", "D-S3: two GCDs late grades B")
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "stormstrike",
        resources = { ss_ready_at = 96 } }), "C", "D-S3: three GCDs late grades C")
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "stormstrike",
        resources = { ss_ready_at = 90 } }), "D", "D-S3: later than three GCDs grades D")
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "flameshock",
        resources = { ss_ready_at = 100 } }), "F",
        "D-S3: holding Stormstrike with the opt-in off is a dead GCD")
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "flameshock",
        resources = { ss_ready_at = 100, stormstrike_hold_enabled = true } }), nil,
        "D-S3: holding Stormstrike with the opt-in on grades nothing")
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "flameshock",
        resources = { ss_ready_at = 100, gcd = 2.0 } }), "F",
        "D-S3: the opt-in is read, the GCD length is the default")
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "stormstrike",
        resources = { ss_ready_at = 99, gcd = 2.0 } }), "A",
        "D-S3: a stated GCD length drives the band")
    -- No ready stamp: the Stormstrike's own cooldown decides.
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "stormstrike",
        cooldowns = { stormstrike = 0 } }), "S",
        "D-S3: a ready Stormstrike pressed grades S")
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "flameshock",
        cooldowns = { stormstrike = 0 } }), "F",
        "D-S3: a held Stormstrike with the opt-in off is a dead GCD")
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "flameshock",
        cooldowns = { stormstrike = 0 }, resources = { stormstrike_hold_enabled = true } }),
        nil, "D-S3: a held Stormstrike with the opt-in on grades nothing")
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "stormstrike",
        cooldowns = { stormstrike = 8 } }), nil,
        "D-S3: a Stormstrike still on cooldown grades nothing")
    eq(sg.grade_stormstrike_hold({ now = 100, last_action = "stormstrike" }), nil,
        "D-S3: an unknown Stormstrike cooldown grades nothing")
    eq(sg.grade_stormstrike_hold({ now = 100, cooldowns = { stormstrike = 0 } }), nil,
        "D-S3: nothing cast grades nothing")

    -- Drill D-S4: the totem upkeep.
    eq(sg.grade_totem_upkeep({ now = 100, last_action = "wftotem",
        cooldowns = { wftotem = 0 } }), "S", "D-S4: the due slot re-dropped grades S")
    eq(sg.grade_totem_upkeep({ now = 100, last_action = "goa",
        cooldowns = { wftotem = 0 } }), "D", "D-S4: the due slot left empty grades D")
    eq(sg.grade_totem_upkeep({ now = 100, last_action = "magma",
        cooldowns = { wftotem = 0 }, resources = { fireele_active = true } }), "F",
        "D-S4: replacing a live Fire Elemental grades F")
    eq(sg.grade_totem_upkeep({ now = 100, last_action = "wftotem" }), nil,
        "D-S4: nothing due grades nothing")
    eq(sg.grade_totem_upkeep({ now = 100, last_action = "wftotem",
        cooldowns = { wftotem = 0 }, resources = { totem_due_at = 99.5 } }), "A",
        "D-S4: one second late grades A")
    eq(sg.grade_totem_upkeep({ now = 100, last_action = "wftotem",
        cooldowns = { wftotem = 0 }, resources = { totem_due_at = 95 } }), "D",
        "D-S4: more than three seconds late grades D")
    eq(sg.grade_totem_upkeep({ now = 100, last_action = "goa",
        cooldowns = { goatotem = 0 } }), "S", "D-S4: the Grace of Air fallback grades S")
    eq(sg.grade_totem_upkeep({ now = 100, last_action = "magma",
        cooldowns = { magma = 0 } }), "S", "D-S4: a due Magma grades S")

    -- The Searing upkeep gate (the groundwork the audit lists unwired, S-17).
    eq(sg.SEARING_UPKEEP_FIGHT_GATE_ERA, 20, "the Era Searing gate is 20 s")
    eq(sg.SEARING_UPKEEP_FIGHT_GATE_SOD, 30, "the SoD Searing gate is 30 s")
    eq(sg.get_searing_upkeep_due("ERA", 21, true, false), true,
        "the Era Searing is due past 20 s")
    eq(sg.get_searing_upkeep_due("ERA", 20, true, false), false,
        "the Era Searing gate is strict (20 s is not past it)")
    eq(sg.get_searing_upkeep_due("ERA", 31, true, true), true,
        "the SoD Searing is due past 30 s")
    eq(sg.get_searing_upkeep_due("ERA", 30, true, true), false,
        "the SoD Searing gate is strict (30 s is not past it)")
    eq(sg.get_searing_upkeep_due("ERA", 40, false, false), false,
        "a Searing that is not down is never due")
    eq(sg.get_searing_upkeep_due("ERA", nil, true, false), false,
        "an unknown fight age never prompts the Searing")
    eq(sg.get_searing_upkeep_due("TBC", 60, true, false), false,
        "TBC never grades the Searing (no sim threshold quoted)")
    eq(sg.get_searing_upkeep_due("WRATH", 60, true, false), false,
        "Wrath never grades the Searing (the APL ranks Magma)")
    eq(sg.get_searing_upkeep_due("FOREVER", 60, true, false), false,
        "Forever never grades the Searing (the static totem maintain is filed)")

    -- The Maelstrom stack floor per family.
    eq(sg.get_mw_stack_floor("ERA", true), 0, "the SoD floor is any stack")
    eq(sg.get_mw_stack_floor("ERA", false), 5, "the Era-base floor is the MW5 instant")
    eq(sg.get_mw_stack_floor("WRATH", false), 3, "the Wrath floor is three stacks")
    eq(sg.get_mw_stack_floor("TBC", false), 5, "the TBC floor is the MW5 instant")

    -- The band helper (the same shape the shared engine's H.grade_band uses).
    eq(sg.band_grade(0, sg.WEAVE_MARGIN_BANDS), "S", "the band helper: 0 s is an S")
    eq(sg.band_grade(0.03, sg.WEAVE_MARGIN_BANDS), "A", "the band helper: 30 ms is an A")
    eq(sg.band_grade(0.4, sg.WEAVE_MARGIN_BANDS), "D", "the band helper: beyond the last band is a D")
    eq(sg.band_grade(1, nil), nil, "the band helper: no bands grade nothing")
    eq(sg.WEAVE_DRILL_DEFAULTS.swing_duration, 2.6, "the weave drill's default swing is 2.6 s")
    eq(sg.WEAVE_DRILL_DEFAULTS.effective_cast, 1.5, "the weave drill's default cast is 1.5 s")
    eq(sg.WEAVE_DRILL_DEFAULTS.latency, 0.1, "the weave drill's default latency is 0.1 s")
    eq(sg.GCD_SECONDS_DEFAULT, 1.5, "the GCD default is 1.5 s")

    -- The pick reader: the contract's ctx names the action last_action, and the
    -- aliases are accepted so the shared engine can name it either way.
    eq(sg.get_practice_pick({ last_action = "stormstrike" }), "stormstrike",
        "the pick reader reads last_action")
    eq(sg.get_practice_pick({ action = "weave" }), "weave", "the pick reader reads action")
    eq(sg.get_practice_pick({ pick = "weave" }), "weave", "the pick reader reads pick")
    eq(sg.get_practice_pick({ pressed = "weave" }), "weave", "the pick reader reads pressed")
    eq(sg.get_practice_pick({}), nil, "the pick reader reads nothing from an empty ctx")
    eq(sg.get_practice_pick(nil), nil, "the pick reader reads nothing from a nil ctx")
    eq(sg.get_practice_pick({ last_action = 42 }), nil, "a non-string pick reads nothing")
end

--=========================================================================================
-- 6) The class practice contract (bench/class_features_drills_2026-10-19.md §2.6)
--=========================================================================================
-- The class hooks the shared engine drives: the rotation table, the scenario step
-- and the four target drills. The provider sandbox carries the real modules
-- (shaman_guide.lua + classes/shaman.lua + weave.lua), so this is the end-to-end
-- view: the class, the engine it reuses and the practice surface that drives them.
do
    local rot = ST.SHAMAN.practice_rotation
    check(type(rot) == "table", "the class ships a rotation table")
    eq(#rot, 22, "the rotation table carries twenty-two lines")
    -- The order is the engine's rule order (the compiled sim priority).
    local ORDER = { "fireele", "feralspirit", "bloodlust", "shamanisticrage", "weave",
        "flameshock", "twist", "strength_of_earth", "wftotem", "goa", "mana_spring",
        "stormstrike", "searing", "magma", "firenova",
        "lightningshield", "lavalash", "chainlightning", "frostshock", "earthshock",
        "moltenblast", "coe" }
    for i = 1, #ORDER do
        eq(rot[i].action, ORDER[i], "rotation line " .. i .. " is " .. ORDER[i])
    end
    -- Every line carries its shape and its citation.
    local UNCONFIRMED = { fireele = true, twist = true, wftotem = true, goa = true,
        searing = true, magma = true, lightningshield = true, lavalash = true,
        moltenblast = true, coe = true }
    local shape_ok, citation_ok, unconfirmed_ok, unique_ok = true, true, true, true
    local seen = {}
    local families_ok = true
    local flags_ok, needs_ok = true, true
    for i = 1, #rot do
        local line = rot[i]
        if type(line.action) ~= "string" or line.action == "" then shape_ok = false end
        if type(line.label) ~= "string" or line.label == "" then shape_ok = false end
        if type(line.spell_id) ~= "number" then shape_ok = false end
        if type(line.spell_name) ~= "string" or line.spell_name == "" then shape_ok = false end
        if type(line.families) ~= "table" or #line.families == 0 then shape_ok = false end
        if type(line.live) ~= "boolean" then shape_ok = false end
        -- The HU-13 flag convention: BOTH flags are declared on every line -
        -- `live` (the line's read exists and the line can be evaluated) and
        -- `engine` (the frozen engine has an arm that can ask for it).
        if type(line.engine) ~= "boolean" then flags_ok = false end
        if line.live == false and (type(line.needs) ~= "string" or line.needs == "") then
            needs_ok = false
        end
        -- Every line cites a dated bench source: the 2026-10-19 audit (the shipped
        -- lines) or the 2026-10-20 APL gap analysis (the APL utility layer).
        if type(line.source) ~= "string"
            or not (line.source:find("audit 2026-10-19", 1, true)
                or line.source:find("rotation_gap_vs_apl_2026-10-20", 1, true)) then
            citation_ok = false
        end
        if UNCONFIRMED[line.action] and not line.source:find("UNCONFIRMED", 1, true) then
            unconfirmed_ok = false
        end
        if seen[line.action] then unique_ok = false end
        seen[line.action] = true
        for f = 1, #line.families do
            local fam = line.families[f]
            -- SOD is the SoD build's own token (the hunter's rotation table uses it
            -- the same way): it rides the ERA client token and is separated from
            -- the Era-base build at runtime by the MW-rune latch.
            if fam ~= "ERA" and fam ~= "SOD" and fam ~= "TBC" and fam ~= "WRATH"
                and fam ~= "FOREVER" then
                families_ok = false
            end
        end
    end
    check(shape_ok, "every rotation line carries action/label/id/name/families/live/source")
    check(flags_ok, "every rotation line declares both flags (live and engine)")
    check(needs_ok, "every line without a read names the read it needs")
    check(citation_ok, "every rotation line cites a dated bench source")
    check(unconfirmed_ok, "every unconfirmed id says so in its own citation")
    check(unique_ok, "the rotation action keys are unique")
    check(families_ok, "the rotation lines name only known family tokens")
    -- The two flags answer different questions (HU-13): `live` is the line's READ
    -- and `engine` is an arm the frozen engine can PLAY with the inputs the
    -- shipped tree produces - a live read without an arm is a spine row, and a
    -- rule whose input no producer feeds claims no arm at all (the Chain
    -- Lightning sensor).
    local slot_keys = {}
    for i = 1, #slots do slot_keys[slots[i].key] = true end
    local live_ok, engine_ok = true, true
    for i = 1, #rot do
        local line = rot[i]
        if line.live and not slot_keys[line.action] then live_ok = false end
        if line.engine and not slot_keys[line.action] then engine_ok = false end
    end
    check(live_ok, "every live rotation line names a declared guide slot")
    check(engine_ok, "every rotation line the engine can play names a declared guide slot")
    -- The lines the audit lists unwired: S-19 and S-17 landed with their slots and
    -- rules, so they are live now; S-20 (Call of the Elements) landed with its
    -- slot, its rule 9c and the water clock, so it is live too.
    eq(rot[13].action, "searing", "the Searing line sits at the fire-slot maintain")
    eq(rot[13].live, true, "the Searing line is live (guide slot 17 + rule 9b)")
    eq(rot[16].action, "lightningshield", "the Lightning Shield line is in the spine")
    eq(rot[16].live, true, "the Lightning Shield line is live (guide slot 16 + rule 11b)")
    eq(rot[22].action, "coe", "the Call of the Elements line closes the spine")
    eq(rot[22].live, true, "the Call of the Elements line is live (guide slot 18 + rule 9c)")
    -- The CoE line cites the water clock it reads and the client-sourced slot map.
    check(rot[22].source:find("water", 1, true) ~= nil,
        "the Call of the Elements citation names the water clock it reads")
    check(rot[22].source:find("GetTotemInfo", 1, true) ~= nil,
        "the Call of the Elements citation names the reader it uses")
    -- The APL utility layer (bench/rotation_gap_vs_apl_2026-10-20.md §5): the four
    -- new lines, their per-family ids and their flags.
    eq(rot[3].action, "bloodlust", "the Bloodlust party cooldown sits at rule 3b")
    eq(rot[8].action, "strength_of_earth", "the Strength of Earth upkeep sits at rule 8a")
    eq(rot[11].action, "mana_spring", "the Mana Spring upkeep sits at rule 8d")
    eq(rot[19].action, "frostshock", "the TBC Frost Shock filler sits at rule 13b")
    for i = 1, #rot do
        local line = rot[i]
        if line.action == "bloodlust" or line.action == "strength_of_earth"
            or line.action == "mana_spring" or line.action == "frostshock" then
            eq(line.live, true, "the " .. line.action .. " line has a live read")
            eq(line.engine, true, "the " .. line.action .. " line has an engine arm")
            check(type(line.spell_ids) == "table",
                "the " .. line.action .. " line carries its per-family ids")
        end
    end
    -- The Chain Lightning line is the honest case: the enemy-count READ does not
    -- exist (no client API counts enemies), so NO producer ever feeds target_count
    -- and rule 13 has no producer either - the line is not live AND claims no
    -- engine arm. It names the read it waits for.
    eq(rot[18].action, "chainlightning", "the Chain Lightning line keeps its place")
    eq(rot[18].live, false, "the Chain Lightning line is not live (no enemy-count read)")
    eq(rot[18].engine, false,
        "the Chain Lightning line claims no engine arm (nothing feeds target_count)")
    check(type(rot[18].needs) == "string" and rot[18].needs:find("target_count", 1, true) ~= nil,
        "the Chain Lightning line names the read it waits for")
    -- Name-vs-id (bench/lessons.md): TBC resolves by NAME and Era by ID, and both
    -- are pinned here against the module's own constants.
    local IDS = {
        fireele = 2894, feralspirit = 51533, shamanisticrage = 30823, weave = 403,
        flameshock = 8050, twist = 8512, wftotem = 10614, goa = 10627,
        stormstrike = 17364, searing = 10438, magma = 8190, firenova = 1535,
        lightningshield = 49281, lavalash = 60103, chainlightning = 10605,
        earthshock = 8042, moltenblast = 425339, coe = 66842,
        bloodlust = 2825, strength_of_earth = 10442, mana_spring = 25570,
        frostshock = 25464,
    }
    local NAMES = {
        fireele = "Fire Elemental Totem", feralspirit = "Feral Spirit",
        shamanisticrage = "Shamanistic Rage", weave = "Lightning Bolt",
        flameshock = "Flame Shock", twist = "Windfury Totem", wftotem = "Windfury Totem",
        goa = "Grace of Air Totem", stormstrike = "Stormstrike",
        searing = "Searing Totem", magma = "Magma Totem", firenova = "Fire Nova Totem",
        lightningshield = "Lightning Shield", lavalash = "Lava Lash",
        chainlightning = "Chain Lightning", earthshock = "Earth Shock",
        moltenblast = "Molten Blast", coe = "Call of the Elements",
        bloodlust = "Bloodlust", strength_of_earth = "Strength of Earth Totem",
        mana_spring = "Mana Spring Totem", frostshock = "Frost Shock",
    }
    for i = 1, #rot do
        local line = rot[i]
        eq(line.spell_id, IDS[line.action], "the Era id of " .. line.action)
        eq(line.spell_name, NAMES[line.action], "the TBC name of " .. line.action)
    end
    -- The per-family id maps: the family-split ids the bench called out.
    eq(rot[8].spell_ids.ERA, 10442, "the Strength of Earth Era id is 10442")
    eq(rot[8].spell_ids.TBC, 25528, "the Strength of Earth TBC id is 25528")
    eq(rot[8].spell_ids.FOREVER, 25361, "the Strength of Earth Forever id is 25361")
    eq(rot[11].spell_ids.TBC, 25570, "the Mana Spring TBC id is 25570")
    eq(rot[11].spell_ids.SOD, 10497, "the Mana Spring SoD pre-pull id is 10497")
    eq(rot[3].spell_ids.WRATH, 2825, "the Bloodlust Wrath id is 2825")
    eq(rot[19].spell_ids.TBC, 25464, "the Frost Shock TBC id is 25464")
    -- The TBC name of a line is the name the module itself queries by.
    eq(rot[12].spell_name, "Stormstrike", "the Stormstrike line names the TBC spell")
    eq(rot[15].spell_name, "Fire Nova Totem", "the Fire Nova line names the TBC spell")

    -- The scenario step: the engine's verdict, or nil when undecidable.
    local step = ST.SHAMAN.practice_scenario_step(ST, {
        now = 100, cooldowns = { stormstrike = 0, flameshock = 10 } })
    check(type(step) == "table", "the scenario step answers a table")
    eq(step.action, "stormstrike", "the scenario step answers the engine's action")
    eq(step.reason, "Stormstrike off cooldown", "the scenario step carries the reason")
    -- The APL utility layer: the practice ctx can ask for each new line, and the
    -- engine's own arm answers it (the ctx carries the line's read).
    local soe_step = ST.SHAMAN.practice_scenario_step(ST, { now = 100,
        cooldowns = { stormstrike = 8, flameshock = 10, firenova = 5,
            strength_of_earth = 0 } })
    eq(soe_step.action, "strength_of_earth",
        "the scenario asks for a due Strength of Earth upkeep")
    local ms_step = ST.SHAMAN.practice_scenario_step(ST, { now = 100,
        cooldowns = { stormstrike = 8, flameshock = 10, firenova = 5,
            mana_spring = 0 } })
    eq(ms_step.action, "mana_spring",
        "the scenario asks for a due Mana Spring upkeep")
    local bl_step = ST.SHAMAN.practice_scenario_step(ST, { now = 100,
        cooldowns = { stormstrike = 8, flameshock = 10, firenova = 5, bloodlust = 0 },
        resources = { family = "WRATH" } })
    eq(bl_step.action, "bloodlust", "the scenario asks for a ready Bloodlust")
    local fs_step = ST.SHAMAN.practice_scenario_step(ST, { now = 100,
        cooldowns = { stormstrike = 8, flameshock = 10, firenova = 5, shock = 0,
            frostshock = 0 },
        resources = { filler_shock = "FROST" } })
    eq(fs_step.action, "frostshock", "the scenario asks for the Frost Shock filler")
    local fs_default = ST.SHAMAN.practice_scenario_step(ST, { now = 100,
        cooldowns = { stormstrike = 8, flameshock = 10, firenova = 5, shock = 0,
            frostshock = 0 } })
    eq(fs_default.action, "earthshock",
        "the scenario keeps the APL's Earth Shock default when no choice is stated")
    -- A cast in flight is a RIDE hold, and a hold is a DECISION (the operator
    -- ruling HU-8): the step states it explicitly, so the engine can punish a
    -- cast during the ride instead of reading the step as an unknown.
    local ride_step = ST.SHAMAN.practice_scenario_step(ST,
        { now = 100, resources = { casting = true } })
    check(type(ride_step) == "table" and ride_step.hold == true,
        "a cast in flight states an explicit hold")
    eq(ride_step.action, nil, "the ride hold names no action")
    check(type(ride_step.reason) == "string" and ride_step.reason ~= "",
        "the ride hold carries the guide's own caption")
    -- An empty ctx is not undecidable: the engine's own nil-Flame-Shock rule
    -- always refreshes, so the step answers that verdict (the step is the
    -- engine's verdict, never a second opinion).
    eq(ST.SHAMAN.practice_scenario_step(ST, nil).action, "flameshock",
        "an empty ctx answers the engine's own verdict")
    eq(ST.SHAMAN.practice_scenario_step(nil, { now = 100 }).action, "flameshock",
        "the addon argument is not read: the step is pure")
    -- The ctx family drives the engine's family gates and is restored afterwards
    -- (the provider sandbox is a TBC client).
    eq(st.family, "TBC", "the provider sandbox is a TBC client")
    local nova_ctx = { now = 100, cooldowns = { stormstrike = 8, flameshock = 10,
        firenova = 0 } }
    eq(ST.SHAMAN.practice_scenario_step(ST, nova_ctx).action, "firenova",
        "TBC: a ready Fire Nova answers the Nova line")
    local era_step = ST.SHAMAN.practice_scenario_step(ST, { now = 100,
        cooldowns = { stormstrike = 8, flameshock = 10, firenova = 0 },
        resources = { family = "ERA" } })
    eq(era_step.action, "earthshock", "the ctx family drives the engine's family gates")
    eq(st.family, "TBC", "the ctx family is restored after the call")
    -- The step never throws, whatever the ctx carries.
    local ok_step = pcall(ST.SHAMAN.practice_scenario_step, ST, { now = "soon",
        cooldowns = 5, resources = "nope" })
    check(ok_step, "the scenario step never throws on a malformed ctx")
    eq(st.family, "TBC", "a malformed ctx leaves the family alone")

    -- The class drills: the audit's four target drills (D-S1..D-S4).
    check(type(ST.SHAMAN.practice_drills) == "table", "the class ships its drills")
    eq(#ST.SHAMAN.practice_drills, 4, "four target drills")
    local DRILL_KEYS = { "shaman_enh_priority", "shaman_mw_weave",
        "shaman_stormstrike_hold", "shaman_totem_upkeep" }
    for i = 1, #DRILL_KEYS do
        local drill = ST.SHAMAN.practice_drills[i]
        eq(drill.key, DRILL_KEYS[i], "drill " .. i .. " is " .. DRILL_KEYS[i])
        check(type(drill.label) == "string" and drill.label ~= "",
            "drill " .. DRILL_KEYS[i] .. " carries a label")
        check(type(drill.grade) == "function",
            "drill " .. DRILL_KEYS[i] .. " carries a grader")
    end
    -- A malformed ctx never throws and never grades.
    for i = 1, #DRILL_KEYS do
        local drill = ST.SHAMAN.practice_drills[i]
        local ok_grade = pcall(drill.grade, ST, nil)
        check(ok_grade, "drill " .. DRILL_KEYS[i] .. " never throws on a nil ctx")
        eq(drill.grade(ST, nil), nil, "drill " .. DRILL_KEYS[i] .. " grades nothing without a ctx")
        eq(drill.grade(ST, "junk"), nil, "drill " .. DRILL_KEYS[i] .. " grades nothing on junk")
    end
    -- D-S1 through the class hook: the engine's verdict decides the grade.
    local prio = ST.SHAMAN.practice_drills[1]
    eq(prio.grade(ST, { now = 100, cooldowns = { stormstrike = 0, flameshock = 10 },
        last_action = "stormstrike" }), "S", "D-S1: the expected action grades S")
    eq(prio.grade(ST, { now = 100, cooldowns = { stormstrike = 0, flameshock = 10 },
        last_action = "flameshock" }), "F", "D-S1: a different action grades F")
    -- D-S2 through the class hook: the weave maths is the real one (weave.lua is
    -- loaded in this sandbox), so the marker and the clip are the shipped ones.
    local mw = ST.SHAMAN.practice_drills[2]
    -- A 1.5 s cast in a 2.6 s swing: the marker sits at (2.6 - 1.6) / 2.6 =
    -- 0.3846; a start at 0.38 leaves a 0.0046 margin -> S.
    eq(mw.grade(ST, { now = 100, last_action = "weave", resources = {
        mw_stacks = 5, swing_duration = 2.6, swing_remaining = 2.6 - 0.38 * 2.6,
        weave_cast_seconds = 1.5, latency = 0.1, family = "WRATH" } }), "S",
        "D-S2: a tight weave start grades S on the shipped marker")
    -- A start past the marker clips the swing -> F.
    eq(mw.grade(ST, { now = 100, last_action = "weave", resources = {
        mw_stacks = 5, swing_duration = 2.6, swing_remaining = 2.6 - 0.9 * 2.6,
        weave_cast_seconds = 1.5, latency = 0.1, family = "WRATH" } }), "F",
        "D-S2: a clipping weave start grades F")
    -- Below the family's stack floor (Wrath: MW >= 3) the weave is a wrong pick.
    eq(mw.grade(ST, { now = 100, last_action = "weave", resources = {
        mw_stacks = 2, swing_duration = 2.6, swing_remaining = 2.6 - 0.38 * 2.6,
        weave_cast_seconds = 1.5, latency = 0.1, family = "WRATH" } }), "F",
        "D-S2: a weave below the family's stack floor grades F")
    -- SoD weaves at any stack, so the same start grades there.
    eq(mw.grade(ST, { now = 100, last_action = "weave", resources = {
        mw_stacks = 1, swing_duration = 2.6, swing_remaining = 2.6 - 0.38 * 2.6,
        weave_cast_seconds = 1.5, latency = 0.1, family = "ERA", mw_observed = true } }), "S",
        "D-S2: SoD weaves at any stack")
    -- D-S3 through the class hook.
    local ss = ST.SHAMAN.practice_drills[3]
    eq(ss.grade(ST, { now = 100, last_action = "stormstrike",
        resources = { ss_ready_at = 100 } }), "S", "D-S3: pressing on cooldown grades S")
    eq(ss.grade(ST, { now = 100, last_action = "flameshock",
        resources = { ss_ready_at = 100 } }), "F",
        "D-S3: holding Stormstrike with the opt-in off is a dead GCD")
    -- D-S4 through the class hook: the Searing groundwork the audit lists unwired
    -- is consumed here (the fight clock + the fire-slot reader).
    local totem = ST.SHAMAN.practice_drills[4]
    eq(totem.grade(ST, { now = 100, last_action = "searing",
        resources = { family = "ERA", fight_elapsed = 25, searing_down = true } }), "S",
        "D-S4: the Era Searing past 20 s grades the Searing drop")
    eq(totem.grade(ST, { now = 100, last_action = "searing",
        resources = { family = "ERA", fight_elapsed = 10, searing_down = true } }), nil,
        "D-S4: the Era Searing before the fight gate grades nothing")
    eq(totem.grade(ST, { now = 100, last_action = "searing",
        resources = { family = "ERA", fight_elapsed = 35, searing_down = true,
            mw_observed = true } }), "S", "D-S4: the SoD Searing past 30 s grades the drop")
    eq(totem.grade(ST, { now = 100, last_action = "magma",
        resources = { family = "TBC", fireele_active = true } }), "F",
        "D-S4: replacing a live Fire Elemental grades F")

    -- The shared engine (practice.lua:3223-3477) drives the class hooks: the drill
    -- list, the scenario step and the per-attempt grade all come through it.
    do
        -- The engine resolves the class module from the AceAddon table FIRST (the
        -- class tables live there; the namespace is only the fallback), so no
        -- per-class alias is needed - and the class module carries none
        -- (hands-up.md HU-7, bench/practice_scenario_engine_2026-10-19.md section 6).
        eq(st.SHAMAN, nil, "the class module carries no namespace alias")
        local pmod = assert(loadfile(ROOT .. "practice.lua"))
        setfenv(pmod, sandbox.env)
        local okp, errp = pcall(function() pmod("SwedgeTimer", st) end)
        check(okp, "practice.lua loads in the provider sandbox (" .. tostring(errp) .. ")")
        local H = st.practice and st.practice.harness
        check(type(H) == "table", "the shared engine is loaded")
        if type(H) == "table" then
            eq(H.practice_scenario_available("SHAMAN"), true,
                "the engine finds the shaman scenario step")
            local drills = H.practice_drills("SHAMAN")
            check(type(drills) == "table", "the engine reads the shaman drill list")
            eq(drills and #drills or 0, 4, "the engine sees the four shaman drills")
            if type(drills) == "table" and #drills == 4 then
                for i = 1, #DRILL_KEYS do
                    eq(drills[i].key, DRILL_KEYS[i], "the engine registers " .. DRILL_KEYS[i])
                end
            end
            local engine_step = H.practice_scenario_step("SHAMAN", ST, {
                now = 100, cooldowns = { stormstrike = 0, flameshock = 10 } })
            eq(engine_step and engine_step.action, "stormstrike",
                "the engine drives the shaman scenario step")
            eq(H.practice_drill_grade("SHAMAN", "shaman_enh_priority", ST, {
                now = 100, cooldowns = { stormstrike = 0, flameshock = 10 },
                last_action = "stormstrike" }), "S",
                "the engine grades a shaman drill attempt")
            eq(H.practice_drill_grade("SHAMAN", "shaman_enh_priority", ST, {
                now = 100, cooldowns = { stormstrike = 0, flameshock = 10 },
                last_action = "flameshock" }), "F",
                "the engine grades a wrong shaman drill attempt")
            eq(H.practice_drill_grade("SHAMAN", "shaman_enh_priority", ST, nil), nil,
                "the engine grades nothing without a ctx")
            eq(H.practice_drill_grade("SHAMAN", "no_such_drill", ST, {}), nil,
                "the engine grades an unknown drill nothing")

            -- HU-8: the class states its hold, and the three states are the
            -- engine's own: a cast during a hold is the illegal cast, doing
            -- nothing is correct (no attempt), and an unknown stays unknown.
            local hold_answer = H.practice_scenario_step("SHAMAN", ST,
                { now = 100, resources = { casting = true } })
            check(type(hold_answer) == "table" and hold_answer.hold == true,
                "hold: the ride state states an explicit hold")
            eq(hold_answer.action, nil, "hold: the hold statement names no action")
            check(type(hold_answer.reason) == "string" and hold_answer.reason ~= "",
                "hold: the hold statement carries the guide's reason")
            local run = H.new_rotation_run()
            local cast = H.rotation_run_decide(run, hold_answer.action, "stormstrike",
                hold_answer.hold)
            eq(cast.outcome, "illegal_cast",
                "hold: a cast during the ride is an illegal cast")
            eq(H.ROTATION_OUTCOME_GRADES[cast.outcome], "F",
                "hold: the illegal cast grades F")
            eq(run.mispicks, 1, "hold: the illegal cast counts against the run's band")
            local idle_run = H.new_rotation_run()
            local idle = H.rotation_run_decide(idle_run, hold_answer.action, nil,
                hold_answer.hold)
            eq(idle.outcome, "hold_ok", "hold: doing nothing during the ride is correct")
            eq(H.ROTATION_OUTCOME_GRADES[idle.outcome], nil,
                "hold: a correct hold records no attempt (no points)")
            eq(idle_run.mispicks, 0, "hold: a correct hold is never a mis-pick")
            -- The unknown: a ctx the guide cannot read stays unknown.
            local unknown_run = H.new_rotation_run()
            local unknown = H.rotation_run_decide(unknown_run, nil, "stormstrike")
            eq(unknown.outcome, "unknown", "hold: an unknown step stays unknown")
            eq(H.ROTATION_OUTCOME_GRADES[unknown.outcome], nil,
                "hold: an unknown decision records no attempt")
            eq(unknown_run.mispicks, 0, "hold: an unknown decision is never a mis-pick")
        end
    end
end

if failures == 0 then
    print("PASS  shaman_guide_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  shaman_guide_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
