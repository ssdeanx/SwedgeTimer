-- tests/nextaction_state.lua: unit tests for the pure next-action guide engine in
-- nextaction.lua. Sandbox-loads the module with a setmetatable environment
-- (__index = _G); the module needs no LibStub and no WoW globals. The expected
-- values pin the archived decision table (docs/swedge/SwedgeTimer_TBC/nextaction.lua,
-- compute() lines 186-465) and the rotation thresholds (rotation.lua lines 140-172).
-- Run from the repo root: lua5.1 tests/nextaction_state.lua

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

local mod = assert(loadfile(ROOT .. "nextaction.lua"))
setfenv(mod, env)
local ok, err = pcall(function() mod("SwedgeTimer", st) end)
check(ok, "nextaction.lua loads under the sandbox (" .. tostring(err) .. ")")
local na = st.nextaction
check(type(na) == "table", "st.nextaction table exists")

-- constants ----------------------------------------------------------------
eq(na.CS_SPELL_ID, 35395, "CS_SPELL_ID == 35395")
eq(na.JUDGEMENT_SPELL_ID, 20271, "JUDGEMENT_SPELL_ID == 20271")
eq(na.CONSECRATION_SPELL_ID, 26573, "CONSECRATION_SPELL_ID == 26573")
eq(na.EXORCISM_SPELL_ID, 879, "EXORCISM_SPELL_ID == 879")
eq(na.SOC_ID, 20375, "SOC_ID == 20375")
eq(na.SOB_ID, 31892, "SOB_ID == 31892")
check(type(na.exorcism_target_types) == "table", "exorcism_target_types table exists")

-- rotation tables: all eight keys, each with a sequence / description / display name
local rotation_keys = { "1/2", "2/3", "2/2/5", "2/4", "1/3", "2/5_blood", "2/5_command", "2007" }
for _, key in ipairs(rotation_keys) do
    check(type(na.sequences[key]) == "table", "sequences[" .. key .. "] table")
    check(type(na.descriptions[key]) == "string", "descriptions[" .. key .. "] string")
    check(type(na.display_names[key]) == "string", "display_names[" .. key .. "] string")
end
eq(#na.sequences["1/2"], 2, "sequences 1/2 has 2 steps")
eq(#na.sequences["2/2/5"], 5, "sequences 2/2/5 has 5 steps")
eq(na.sequences["2/2/5"][3], "cs_late", "2/2/5 third step is cs_late")
eq(na.sequences["2007"][1], "blood_auto", "2007 starts on a blood auto")
eq(na.descriptions["2007"], "Ride Blood & CS", "2007 description")
eq(na.display_names["2/5_blood"], "2/5 Blood", "2/5_blood display name")
eq(na.display_names["2/5_command"], "2/5 Command", "2/5_command display name")
eq(na.display_names["2/3"], "2/3", "2/3 display name")

-- get_gcd_duration: nil -> 1.5; clamped into [1.0, 1.5] ---------------------
eq(na.get_gcd_duration(nil), 1.5, "gcd: nil -> 1.5")
eq(na.get_gcd_duration(2.0), 1.5, "gcd: 2.0 clamps down to 1.5")
eq(na.get_gcd_duration(1.5), 1.5, "gcd: 1.5 stays")
near(na.get_gcd_duration(1.3), 1.3, "gcd: 1.3 stays")
eq(na.get_gcd_duration(1.0), 1.0, "gcd: 1.0 stays")
eq(na.get_gcd_duration(0.9), 1.0, "gcd: 0.9 clamps up to 1.0")
eq(na.get_gcd_duration(0), 1.0, "gcd: 0 clamps up to 1.0")

-- get_haste_amount: 1.5 - gcd, floored at 0 --------------------------------
eq(na.get_haste_amount(1.5), 0, "haste: gcd 1.5 -> 0")
near(na.get_haste_amount(1.3), 0.2, "haste: gcd 1.3 -> 0.2")
near(na.get_haste_amount(1.0), 0.5, "haste: gcd 1.0 -> 0.5")
eq(na.get_haste_amount(nil), 0, "haste: nil -> 0")
eq(na.get_haste_amount(2.0), 0, "haste: over-base gcd floors at 0")

-- calculate_rotation: all eight threshold outcomes, in priority order ---------
eq(na.calculate_rotation(2.7, 1.5), "1/2", "rotation: > 2.6 -> 1/2")
eq(na.calculate_rotation(3.0, 1.5), "1/2", "rotation: 3.0 -> 1/2")
eq(na.calculate_rotation(2.3, 1.3), "2/3", "rotation: 2.3 @ haste 0.2 -> 2/3")
eq(na.calculate_rotation(2.251, 1.3), "2/3", "rotation: just above max(1.9, 2*gcd-0.35) -> 2/3")
eq(na.calculate_rotation(2.249, 1.3), "2/4", "rotation: just below the 2/3 gate -> 2/4")
eq(na.calculate_rotation(2.45, 1.5), "2/2/5", "rotation: >= 2.4 -> 2/2/5")
eq(na.calculate_rotation(2.35, 1.4), "2/2/5", "rotation: >= 2.3 with haste > 0.05 -> 2/2/5")
eq(na.calculate_rotation(2.0, 1.3), "2/4", "rotation: max(1.5, 1.5*gcd+0.05) with haste > 0.1 -> 2/4")
eq(na.calculate_rotation(2.0, 1.5), "1/3", "rotation: >= 1.9 without haste -> 1/3")
eq(na.calculate_rotation(1.6, 1.5), "2/5_blood", "rotation: >= gcd+0.07 -> 2/5_blood")
eq(na.calculate_rotation(1.2, 1.5), "2/5_command", "rotation: > 1.0 -> 2/5_command")
eq(na.calculate_rotation(0.9, 1.5), "2007", "rotation: >= 0.01 -> 2007")
eq(na.calculate_rotation(nil, 1.5), "1/2", "rotation: nil attack speed defaults to 3.0 -> 1/2")
eq(na.calculate_rotation(3.0, nil), "1/2", "rotation: nil gcd defaults to 1.5")
eq(na.calculate_rotation(0.005, 1.5), nil, "rotation: below 0.01 -> nil")

-- get_seal_state: blood wins; Command needs > 1 s remaining -------------------
eq(na.get_seal_state(false, true, nil), "sob", "seal: blood up -> sob")
eq(na.get_seal_state(true, true, 0.5), "sob", "seal: blood wins in the dual-seal window")
eq(na.get_seal_state(true, false, 5), "soc", "seal: command fresh (> 1 s) -> soc")
eq(na.get_seal_state(true, false, 1.01), "soc", "seal: command just above 1 s -> soc")
eq(na.get_seal_state(true, false, 1.0), "none", "seal: command at exactly 1 s is stale")
eq(na.get_seal_state(true, false, 0.5), "none", "seal: command inside 1 s -> none")
eq(na.get_seal_state(true, false, nil), "soc", "seal: command without expiry data counts as fresh")
eq(na.get_seal_state(false, false, 5), "none", "seal: nothing up -> none")

-- evaluate() harness: caller-owned out table, reused across calls -------------
local out = {}
local function fresh(inputs)
    for k in pairs(out) do out[k] = nil end
    return na.evaluate(inputs, out)
end
local function inp(overrides)
    local t = {
        speed = 3.0, swing_remaining = 3.0, G = 1.5, gcd_remaining = 0,
        twist_window = 0.4, reaction = 0.1, cs_remaining = 6, judge_remaining = 6,
        seal = "none", cs_delay_max = 1.7, waiting_judgement = false,
        melee_count = 0, mana_pct = 50, creature_type = nil, filler_remaining = 0,
    }
    for k, v in pairs(overrides or {}) do t[k] = v end
    return t
end
local function ev(overrides)
    return fresh(inp(overrides))
end

-- out-table contract ----------------------------------------------------------
check(fresh(inp({})) == out, "evaluate returns the caller's out table (no per-call allocation)")
check(type(out.action) == "string" and type(out.hold) == "boolean"
    and type(out.riding) == "boolean" and type(out.judge_call) == "boolean"
    and (out.filler_kind == nil or type(out.filler_kind) == "string")
    and type(out.prediction_hold) == "number" and type(out.waiting_judgement) == "boolean",
    "evaluate writes the seven result fields with the right types")

-- GCD ready, before div (swing 3.0, gcd 0): rel_div = 1.05 --------------------
local r = ev({ seal = "soc" })
eq(r.action, "twist", "before div + soc: twist")
eq(r.hold, true, "before div + soc: hold")
eq(r.riding, false, "before div + soc: not riding")
eq(r.judge_call, false, "before div + soc: no judgement cue without blood")
eq(r.filler_kind, nil, "before div + soc: no filler with zero melees")
near(r.prediction_hold, 2.675, "before div + soc: prediction_hold = reaction + rel_gap")
eq(r.waiting_judgement, false, "before div + soc: judgement latch clear")

r = ev({})
eq(r.action, "soc", "before div + no seal: reseal Command")
eq(r.hold, false, "before div + no seal: no hold")
near(r.prediction_hold, 2.675, "before div + no seal: prediction_hold = reaction + rel_gap")
eq(r.filler_kind, nil, "before div + no seal: filler only lives in the soc branch")
eq(r.waiting_judgement, false, "before div + no seal: latch clear")

r = ev({ waiting_judgement = true })
eq(r.waiting_judgement, false, "non-blood state clears a stale judgement latch")

-- CS override ----------------------------------------------------------------
r = ev({ cs_remaining = 2.0 })
eq(r.action, "cs", "CS override flips soc to cs when the delay budget is gone")
eq(r.hold, true, "CS override holds while CS remaining > 0.1")
near(r.prediction_hold, 2.675, "CS override keeps the pre-override prediction_hold")
eq(r.judge_call, false, "CS override suppresses the judgement cue")

r = ev({ cs_remaining = 0 })
eq(r.action, "cs", "CS override still fires with CS already up")
eq(r.hold, false, "no hold once CS remaining <= 0.1")

r = ev({ cs_remaining = 0.1 })
eq(r.action, "cs", "CS override at cs_remaining == 0.1")
eq(r.hold, false, "0.1 is not > 0.1: no hold")

-- the +0.1 cs delay budget bump only applies to twist actions -----------------
r = ev({ seal = "soc", cs_remaining = 2.5 })
eq(r.action, "twist", "same CS timing keeps twist action due to the +0.1 twist bump")
near(r.prediction_hold, 2.675, "twist bump case keeps prediction_hold")
r = ev({ cs_remaining = 2.5 })
eq(r.action, "cs", "without the twist bump the same CS timing flips to cs")
eq(r.hold, true, "flipped cs keeps hold while CS remaining > 0.1")

-- GCD ready, swing ready (swing 0.0): prediction_hold floor -------------------
r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 0, melee_count = 3 })
eq(r.action, "twist", "swing ready + soc: twist")
eq(r.hold, true, "swing ready + soc: hold")
near(r.prediction_hold, 0, "negative prediction_hold floors to 0")
eq(r.filler_kind, nil, "filler suppressed when CS is back before the GCD would finish")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 3.0, melee_count = 3 })
eq(r.action, "twist", "swing ready + soc + room: twist")
eq(r.filler_kind, "consecration", "filler ready + mana > 35 + 3 melees: consecration")
near(r.prediction_hold, 0, "swing-ready prediction_hold stays floored at 0")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 3.0, melee_count = 2 })
eq(r.filler_kind, nil, "filler needs more than 2 melee swings")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 3.0, melee_count = 3, speed = 2.0 })
eq(r.action, "twist", "slow weapon still twists")
eq(r.filler_kind, nil, "filler needs weapon speed above 2.2")

-- GCD ready, in twist (swing 0.3) ---------------------------------------------
r = ev({ seal = "soc", swing_remaining = 0.3, cs_remaining = 1.0 })
eq(r.action, "twist", "in twist + soc: twist now")
eq(r.hold, false, "in twist + soc: no hold")
near(r.prediction_hold, 0, "in twist + soc: prediction_hold floors from -1")
eq(r.filler_kind, nil, "in twist + soc: no filler")

r = ev({ swing_remaining = 0.3, cs_remaining = 1.0 })
eq(r.action, "soc", "in twist + no seal: CS back inside the GCD -> soc")
near(r.prediction_hold, 0, "in twist + no seal: prediction_hold 0")

r = ev({ swing_remaining = 0.3, cs_remaining = 6 })
eq(r.action, "sob", "in twist + no seal: CS far -> sob")
near(r.prediction_hold, 0, "in twist + sob: prediction_hold 0")

-- GCD ready, after div (swing 1.0): rel_gap = 0.575 ---------------------------
r = ev({ seal = "soc", swing_remaining = 1.0, cs_remaining = 1.0 })
eq(r.action, "twist", "after div + soc: twist")
eq(r.hold, true, "after div + soc: hold")
near(r.prediction_hold, 0.675, "after div + soc: prediction_hold = reaction + rel_gap")

r = ev({ seal = "soc", swing_remaining = 1.0, cs_remaining = 0.3 })
eq(r.action, "cs", "CS override flips an after-div twist")
eq(r.hold, true, "override keeps hold while CS remaining > 0.1")
near(r.prediction_hold, 0.675, "after-div override keeps prediction_hold")

-- GCD busy, branch B1: rel_div >= check (swing 3.0, gcd 1.0) ------------------
r = ev({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3 })
eq(r.action, "twist", "B1 + soc: GCD frees before div -> twist")
eq(r.hold, true, "B1 + soc: hold")
eq(r.filler_kind, "consecration", "B1 + soc: consecration evaluated against the busy GCD")
near(r.prediction_hold, 2.675, "B1 + soc: prediction_hold = reaction + rel_gap")

r = ev({ gcd_remaining = 1.0, cs_remaining = 6 })
eq(r.action, "soc", "B1 + no seal: soc")
eq(r.hold, false, "B1 + no seal: no hold")
eq(r.filler_kind, nil, "B1 + no seal: no filler outside the soc branch")
near(r.prediction_hold, 2.675, "B1 + no seal: prediction_hold = reaction + rel_gap")

-- filler kind selection on the B1 twist branch --------------------------------
r = ev({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3, mana_pct = 40, creature_type = "Undead" })
eq(r.action, "twist", "B1 + exo target: still a twist")
eq(r.filler_kind, "exorcism", "undead target + mana > 30: exorcism")

r = ev({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3, mana_pct = 31, creature_type = "Demon" })
eq(r.filler_kind, "exorcism", "demon target + mana > 30: exorcism")

r = ev({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3, mana_pct = 40, creature_type = "Untoter" })
eq(r.filler_kind, "exorcism", "localized Undead name also maps to exorcism")

r = ev({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3, mana_pct = 30, creature_type = "Undead" })
eq(r.filler_kind, nil, "undead at/below the exorcism mana threshold: no filler")

r = ev({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3, mana_pct = 35, creature_type = "Beast" })
eq(r.filler_kind, nil, "mana 35 is not above the consecration threshold")

r = ev({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3, mana_pct = 36, creature_type = "Beast" })
eq(r.filler_kind, "consecration", "non-undead above the consecration threshold: consecration")

r = ev({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3, mana_pct = 40, creature_type = "Undead", filler_remaining = 2.0 })
eq(r.filler_kind, nil, "filler gated by its own cooldown not being back by the GCD end")

r = ev({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3, mana_pct = 40, creature_type = "Undead", filler_remaining = 999 })
eq(r.filler_kind, nil, "filler_remaining 999 means the spell is unavailable")

local nodata = inp({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3, mana_pct = 40, creature_type = "Undead" })
nodata.filler_remaining = nil
r = fresh(nodata)
eq(r.filler_kind, nil, "nil filler_remaining means the spell is unavailable")

local nomanaless = inp({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3, creature_type = "Undead" })
nomanaless.mana_pct = nil
r = fresh(nomanaless)
eq(r.filler_kind, nil, "missing mana reading counts as 0%: no filler")

-- GCD busy, branch B2: check > rel_gap and check < rel_swing (swing 1.0, gcd 0.7)
r = ev({ seal = "soc", swing_remaining = 1.0, gcd_remaining = 0.7, cs_remaining = 0 })
eq(r.action, "twist", "B2 + soc: GCD frees inside the twist gap -> twist")
eq(r.hold, false, "B2 + soc: no hold")
near(r.prediction_hold, 0, "B2 + soc: prediction_hold floors from -1")
eq(r.filler_kind, nil, "B2 + soc: no filler")

r = ev({ swing_remaining = 1.0, gcd_remaining = 0.7, cs_remaining = 1.0 })
eq(r.action, "soc", "B2 + no seal: CS back within check + G -> soc")
eq(r.hold, false, "B2 + soc fallback: no hold")
near(r.prediction_hold, 0.8, "B2 fallback: prediction_hold = reaction + gcd_remaining")

r = ev({ swing_remaining = 1.0, gcd_remaining = 0.7, cs_remaining = 6 })
eq(r.action, "sob", "B2 + no seal: CS far -> sob")
near(r.prediction_hold, 0.8, "B2 sob: prediction_hold = reaction + gcd_remaining")

-- GCD busy, branch B3: check < rel_gap (swing 1.0, gcd 0.5) -------------------
r = ev({ seal = "soc", swing_remaining = 1.0, gcd_remaining = 0.5, cs_remaining = 1.0 })
eq(r.action, "twist", "B3 + soc: GCD frees between div and the gap -> twist")
eq(r.hold, true, "B3 + soc: hold")
eq(r.filler_kind, nil, "B3 + soc: this branch never suggests a filler")
near(r.prediction_hold, 0.675, "B3 + soc: prediction_hold = reaction + rel_gap")

r = ev({ swing_remaining = 1.0, gcd_remaining = 0.5, cs_remaining = 1.0 })
eq(r.action, "soc", "B3 + no seal: CS back within check + G -> soc")
near(r.prediction_hold, 0.6, "B3 fallback: prediction_hold = reaction + gcd_remaining")

-- GCD busy, branch B4: rel_div2 >= check (swing 1.0, gcd 1.2) -----------------
r = ev({ seal = "soc", swing_remaining = 1.0, gcd_remaining = 1.2, cs_remaining = 6, melee_count = 3 })
eq(r.action, "twist", "B4 + soc: GCD frees before the next div -> twist")
eq(r.hold, true, "B4 + soc: hold")
eq(r.filler_kind, "consecration", "B4 + soc: filler evaluated against the next-swing prediction")
near(r.prediction_hold, 3.7, "B4 + soc: max(prediction_land, rel_gap2) + reaction")

r = ev({ seal = "soc", swing_remaining = 1.0, gcd_remaining = 0.95, cs_remaining = 6 })
eq(r.action, "twist", "B4 boundary: check == rel_swing falls past B2 into B4")
near(r.prediction_hold, 3.7, "B4 boundary keeps the B4 prediction_hold")

r = ev({ swing_remaining = 1.0, gcd_remaining = 1.2, cs_remaining = 6 })
eq(r.action, "soc", "B4 + no seal: soc")
near(r.prediction_hold, 3.7, "B4 + no seal: max(prediction_land, rel_gap2) + reaction")

-- GCD busy, branch B5: GCD frees after the next div (swing 1.0, gcd 2.5) ------
r = ev({ seal = "soc", swing_remaining = 1.0, gcd_remaining = 2.5, cs_remaining = 6 })
eq(r.action, "twist", "B5 + soc: GCD frees after the next div -> twist")
eq(r.hold, true, "B5 + soc: hold")
near(r.prediction_hold, 4.1, "B5 + soc: max(prediction_land, rel_gap2) + reaction")

r = ev({ swing_remaining = 1.0, gcd_remaining = 2.5, cs_remaining = 6 })
eq(r.action, "soc", "B5 + no seal: soc")
near(r.prediction_hold, 2.6, "B5 + no seal: reaction + gcd_remaining")

r = ev({ seal = "soc", swing_remaining = 1.0, gcd_remaining = 2.5, cs_remaining = 2.5 })
eq(r.action, "cs", "CS override fires with a long busy GCD")
eq(r.hold, true, "busy-GCD override holds while CS remaining + 0.1 > gcd_remaining")
near(r.prediction_hold, 4.1, "busy-GCD override keeps prediction_hold")

r = ev({ seal = "soc", swing_remaining = 1.0, gcd_remaining = 2.5, cs_remaining = 0 })
eq(r.action, "cs", "busy-GCD override with CS ready")
eq(r.hold, false, "busy-GCD override drops hold when CS is nearly ready")

-- seal of blood: ride branch (swing 1.0, gcd 0.5) -----------------------------
r = ev({ seal = "sob", swing_remaining = 1.0, gcd_remaining = 0.5, cs_remaining = 6, melee_count = 3 })
eq(r.action, "soc", "blood ride: reseal Command")
eq(r.hold, true, "blood ride: hold")
eq(r.riding, true, "blood ride: riding overlay")
eq(r.filler_kind, "consecration", "blood ride allows a filler")
eq(r.judge_call, false, "no judgement cue while riding")
near(r.prediction_hold, 3.7, "blood ride: reaction + max(prediction_land, rel_gap2)")
eq(r.waiting_judgement, false, "blood ride clears the judgement latch")

r = ev({ seal = "sob", swing_remaining = 1.0, gcd_remaining = 0.5, cs_remaining = 1.0, melee_count = 3 })
eq(r.action, "cs", "CS override preempts the blood ride")
eq(r.hold, true, "preempted ride keeps a CS hold while the GCD is busy")
eq(r.riding, false, "CS override clears riding")
eq(r.filler_kind, nil, "filler suppressed when CS is back within the GCD")

-- seal of blood: reseal-now branch (swing 3.0, gcd 0) -------------------------
r = ev({ seal = "sob", swing_remaining = 3.0, gcd_remaining = 0, cs_remaining = 6 })
eq(r.action, "soc", "blood reseal-now: action soc")
eq(r.hold, false, "blood reseal-now: no hold")
eq(r.riding, false, "blood reseal-now: not riding")
eq(r.judge_call, false, "judgement far from the reseal point: no cue")
near(r.prediction_hold, 2.675, "blood reseal-now: reaction + max(rel_gap, 0)")
eq(r.filler_kind, nil, "blood reseal-now: no filler")

-- seal of blood: judgement cue ------------------------------------------------
r = ev({ seal = "sob", swing_remaining = 3.0, gcd_remaining = 0, cs_remaining = 6, judge_remaining = 0.5 })
eq(r.action, "soc", "judge cue: still resealing Command")
eq(r.judge_call, true, "judgement cue fires before the reseal div")
eq(r.hold, true, "judgement cue holds the reseal")
eq(r.waiting_judgement, true, "judgement latch set")

r = ev({ seal = "sob", swing_remaining = 3.0, gcd_remaining = 0, cs_remaining = 6, judge_remaining = 0, waiting_judgement = true })
eq(r.judge_call, true, "judgement cue still true once judgement is ready")
eq(r.waiting_judgement, false, "judgement latch cleared once judgement is ready")
eq(r.hold, false, "hold released when the judgement latch clears")

r = ev({ seal = "sob", swing_remaining = 3.0, gcd_remaining = 0, cs_remaining = 6, judge_remaining = 0.5, speed = 2.0, waiting_judgement = true })
eq(r.judge_call, true, "cue still fires on a slow weapon")
eq(r.waiting_judgement, false, "slow weapon does not hold for judgement")
eq(r.hold, false, "slow-weapon cue releases the hold")

r = ev({ seal = "sob", swing_remaining = 3.0, gcd_remaining = 0, cs_remaining = 6, judge_remaining = 2.0, waiting_judgement = true })
eq(r.judge_call, false, "no cue while judgement is far from the reseal point")
eq(r.waiting_judgement, true, "latch retained while the cue condition is unmet")

r = ev({ seal = "sob", swing_remaining = 0.3, gcd_remaining = 0, cs_remaining = 6, judge_remaining = 1.0 })
eq(r.action, "soc", "blood window open: reseal preserves the blood swing")
eq(r.hold, true, "window-open cue holds via the judgement path")
eq(r.riding, false, "window open: no riding")
eq(r.judge_call, true, "cue measured against the next swing's div when not before div")
eq(r.waiting_judgement, true, "window-open cue sets the latch")
near(r.prediction_hold, 3.0, "window open: reaction + rel_gap2")

-- seal of blood: padded GCD marker (gcd_before_swing) -------------------------
r = ev({ seal = "sob", swing_remaining = 2.2, gcd_remaining = 0.5, gcd_before_swing = 1.75, cs_remaining = 6 })
eq(r.action, "soc", "padded marker case: reseal Command")
eq(r.hold, true, "padded marker keeps this swing a ride")
eq(r.riding, true, "padded marker: riding")
near(r.prediction_hold, 4.9, "padded marker ride: reaction + max(prediction_land, rel_gap2)")

r = ev({ seal = "sob", swing_remaining = 2.2, gcd_remaining = 0.5, cs_remaining = 6 })
eq(r.action, "soc", "unpadded marker case: reseal Command")
eq(r.hold, false, "without the padding the reseal branch triggers")
eq(r.riding, false, "unpadded marker: no ride")
near(r.prediction_hold, 1.875, "unpadded reseal: reaction + max(rel_gap, 0)")

-- option defaults and input normalisation -------------------------------------
r = fresh({ speed = 3.0, swing_remaining = 3.0, seal = "soc", cs_remaining = 6 })
eq(r.action, "twist", "missing G/twist_window/reaction fall back to the archive defaults")
near(r.prediction_hold, 2.675, "default-value call matches the pinned landmarks")

r = ev({ seal = "soc", gcd_remaining = -1, cs_remaining = 6 })
eq(r.action, "twist", "negative gcd_remaining reads as an idle GCD")
eq(r.hold, true, "negative gcd_remaining keeps the twist hold")

r = ev({ seal = nil })
eq(r.action, "soc", "nil seal behaves like no seal")

if failures == 0 then
    print("PASS  nextaction_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  nextaction_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
