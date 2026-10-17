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

-- TBC CS-delay default: the fallback is 0.9, not the archived 1.7 ------------
-- (cs_remaining 3.0 flips to cs under 0.9 but keeps twisting under 1.7).
local nodefault = {
    speed = 3.0, swing_remaining = 3.0, G = 1.5, gcd_remaining = 0,
    twist_window = 0.4, reaction = 0.1, cs_remaining = 3.0, judge_remaining = 6,
    seal = "soc", waiting_judgement = false,
    melee_count = 0, mana_pct = 50, creature_type = nil, filler_remaining = 0,
}
r = fresh(nodefault)
eq(r.action, "cs", "omitted cs_delay_max falls back to the TBC 0.9 s budget")
eq(r.hold, true, "fallback-budget cs holds while CS remaining > 0.1")
nodefault.cs_delay_max = 1.7
r = fresh(nodefault)
eq(r.action, "twist", "explicit 1.7 keeps the archived delay budget")

-- TBC judge-feasibility gate (judge_require_fit) ------------------------------
-- Absent flag keeps the archived cue (pinned above); the live provider sets it.
r = ev({ seal = "sob", swing_remaining = 3.0, gcd_remaining = 0, cs_remaining = 6,
    judge_remaining = 0.5, judge_require_fit = true })
eq(r.judge_call, true, "fit gate: slow weapon still cues (judge + reseal fits)")
eq(r.hold, true, "fit gate: the fitting cue holds the reseal")
eq(r.waiting_judgement, true, "fit gate: the fitting cue sets the latch")

r = ev({ seal = "sob", swing_remaining = 2.2, speed = 2.0, gcd_remaining = 0,
    cs_remaining = 6, judge_remaining = 0.2, judge_require_fit = true })
eq(r.judge_call, false, "fit gate: fast weapon keeps twisting (reseal misses)")
eq(r.action, "soc", "fit gate: the reseal action stands without the cue")
eq(r.riding, false, "fit gate: no ride on the reseal-now branch")
eq(r.waiting_judgement, false, "fit gate: no latch without a cue")

r = ev({ seal = "sob", swing_remaining = 2.2, speed = 2.0, gcd_remaining = 0,
    cs_remaining = 6, judge_remaining = 0.2 })
eq(r.judge_call, true, "no fit flag: the same tick keeps the archived cue")
eq(r.hold, false, "no fit flag: fast weapons never held for judgement")

r = ev({ seal = "sob", swing_remaining = 0.3, gcd_remaining = 0, cs_remaining = 6,
    judge_remaining = 1.0, judge_require_fit = true })
eq(r.judge_call, false, "fit gate: window-open judge that misses the next gap stays quiet")

-- Crusader priority (jotc_remaining): an expiring JotC outranks Blood --------
r = ev({ seal = "sob", swing_remaining = 3.0, gcd_remaining = 0, cs_remaining = 6,
    judge_remaining = 2.0, jotc_remaining = 1.0 })
eq(r.judge_call, true, "crusader: expiring JotC cues where Blood would not")
eq(r.hold, true, "crusader: the cue holds the reseal")
eq(r.waiting_judgement, true, "crusader: the cue sets the latch")

r = ev({ seal = "sob", swing_remaining = 3.0, gcd_remaining = 0, cs_remaining = 6,
    judge_remaining = 2.0, jotc_remaining = 9.0 })
eq(r.judge_call, false, "crusader: a fresh JotC leaves the Blood rule alone")

r = ev({ seal = "sob", swing_remaining = 3.0, gcd_remaining = 0, cs_remaining = 6,
    judge_remaining = 2.0 })
eq(r.judge_call, false, "crusader: untracked JotC keeps the archived Blood-only cue")

r = ev({ seal = "sob", swing_remaining = 1.0, gcd_remaining = 0.5, cs_remaining = 6,
    melee_count = 3, jotc_remaining = 1.0 })
eq(r.judge_call, false, "crusader: never cues mid-ride")
eq(r.riding, true, "crusader: the ride stands through an expiring JotC")

r = ev({ seal = "sob", swing_remaining = 2.2, speed = 2.0, gcd_remaining = 0,
    cs_remaining = 6, judge_remaining = 0.2, judge_require_fit = true,
    jotc_remaining = 1.0 })
eq(r.judge_call, true, "crusader: debuff uptime bypasses the fit gate")

r = ev({ seal = "sob", swing_remaining = 3.0, gcd_remaining = 0, cs_remaining = 0,
    jotc_remaining = 1.0 })
eq(r.action, "cs", "crusader: CS still wins over an expiring JotC")
eq(r.judge_call, false, "crusader: no cue once CS takes the action")

-- Consecration is AoE-only (target_count); Exorcism is untouched -------------
r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 3.0, melee_count = 3,
    target_count = 1 })
eq(r.action, "twist", "single-target keeps the twist action")
eq(r.filler_kind, nil, "single-target withholds Consecration")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 3.0, melee_count = 3,
    target_count = 0 })
eq(r.filler_kind, nil, "no target withholds Consecration")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 3.0, melee_count = 3,
    target_count = 2 })
eq(r.filler_kind, "consecration", "two targets keep the Consecration suggestion")

r = ev({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 40, creature_type = "Undead", target_count = 1 })
eq(r.filler_kind, "exorcism", "single-target Exorcism vs Undead still fires")

-- Era branch (Era 1.15.9 ret): no Crusader Strike, SoC/SoR twist on the same
-- landmarks, single-target Consecration, HoW execute -------------------------
-- cs_known=false disables the CS override; every no-seal reseal tiebreak falls
-- back to Command (there is no CS timing to wait for).
r = ev({ cs_remaining = 2.0, cs_known = false })
eq(r.action, "soc", "era: unknown CS never overrides the reseal")
eq(r.hold, false, "era: the reseal carries no CS hold")
eq(r.judge_call, false, "era: no judgement cue without the twist seal")

r = ev({ cs_remaining = 2.0, cs_known = true })
eq(r.action, "cs", "cs_known=true keeps the archived override")

r = ev({ cs_remaining = 2.0, era = true, cs_known = true })
eq(r.action, "cs", "era: a client that knows CS still prompts it")

-- No-seal reseal choices with unknown CS (the archive picks "sob" in all four
-- spots; without CS the main seal is re-established instead).
r = ev({ swing_remaining = 0.3, cs_remaining = 6, cs_known = false })
eq(r.action, "soc", "era: in-twist with no seal reseals Command")

r = ev({ swing_remaining = 1.0, cs_remaining = 6, cs_known = false })
eq(r.action, "soc", "era: after-div with no seal reseals Command")

r = ev({ swing_remaining = 1.0, gcd_remaining = 0.7, cs_remaining = 6, cs_known = false })
eq(r.action, "soc", "era: B2 with no seal reseals Command")

r = ev({ swing_remaining = 1.0, gcd_remaining = 0.5, cs_remaining = 6, cs_known = false })
eq(r.action, "soc", "era: B3 with no seal reseals Command")

-- The twist landmarks are reused untouched: SoC up still twists on time.
r = ev({ seal = "soc", swing_remaining = 0.3, cs_remaining = 6, cs_known = false, era = true })
eq(r.action, "twist", "era: in-twist + soc still twists now")
eq(r.hold, false, "era: in-twist keeps no hold")
near(r.prediction_hold, 0, "era: in-twist prediction_hold still floors from -1")

r = ev({ seal = "sob", swing_remaining = 1.0, gcd_remaining = 0.5, cs_remaining = 6,
    melee_count = 3, cs_known = false, era = true })
eq(r.action, "soc", "era: the twist-seal ride still reseals Command")
eq(r.riding, true, "era: the ride overlay survives without CS")
eq(r.filler_kind, "consecration", "era: the ride still allows a filler")

-- Consecration is a mana-permitting single-target filler on Era.
r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    target_count = 1, era = true, cs_known = false })
eq(r.action, "twist", "era: single-target keeps the twist action")
eq(r.filler_kind, "consecration", "era: single-target keeps the Consecration suggestion")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 35, target_count = 1, era = true, cs_known = false })
eq(r.filler_kind, nil, "era: Consecration stays mana-gated (35 is not above 35)")

-- Exorcism vs Undead/Demon is unchanged on Era.
r = ev({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 40, creature_type = "Undead", era = true, cs_known = false })
eq(r.filler_kind, "exorcism", "era: Exorcism vs Undead still fires")

-- Hammer of Wrath execute: below 20% target health with HoW ready.
r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 50, era = true, cs_known = false,
    target_health_pct = 19, how_remaining = 0 })
eq(r.action, "twist", "era: the execute keeps the twist action")
eq(r.filler_kind, "how", "era: HoW below 20% with HoW ready")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 50, era = true, cs_known = false,
    target_health_pct = 20, how_remaining = 0 })
eq(r.filler_kind, "consecration", "era: 20% is not below the execute window")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 50, era = true, cs_known = false, how_remaining = 0 })
eq(r.filler_kind, "consecration", "era: unknown target health never cues HoW")

local nohow = inp({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 50, era = true, cs_known = false, target_health_pct = 19 })
nohow.how_remaining = nil
r = fresh(nohow)
eq(r.filler_kind, "consecration", "era: unknown HoW cooldown never cues HoW")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 50, era = true, cs_known = false,
    target_health_pct = 19, how_remaining = 999 })
eq(r.filler_kind, "consecration", "era: HoW 999 means the spell is unavailable")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 50, era = true, cs_known = false,
    target_health_pct = 19, how_remaining = 2.0 })
eq(r.filler_kind, "consecration", "era: HoW back after the GCD end never cues HoW")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 50, target_health_pct = 19, how_remaining = 0 })
eq(r.filler_kind, "consecration", "non-era ignores the execute inputs (archived suggestion)")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 40, creature_type = "Undead", era = true, cs_known = false,
    target_health_pct = 19, how_remaining = 0 })
eq(r.filler_kind, "how", "era: the execute outranks Exorcism")

-- Era judge-feasibility costs a single reseal (Judgement + SoR->SoC): the fast
-- weapon below misses under the TBC double-reseal cost but fits on Era.
r = ev({ seal = "sob", swing_remaining = 2.2, speed = 2.0, gcd_remaining = 0,
    cs_remaining = 6, judge_remaining = 0.2, judge_require_fit = true,
    era = true, cs_known = false })
eq(r.judge_call, true, "era: single-reseal fit cues where TBC keeps twisting")
eq(r.hold, false, "era: fast weapons never held for judgement")
eq(r.waiting_judgement, false, "era: no hold means no latch")

r = ev({ seal = "sob", swing_remaining = 1.0, gcd_remaining = 0.5, cs_remaining = 6,
    melee_count = 3, jotc_remaining = 1.0, era = true, cs_known = false })
eq(r.judge_call, false, "era: never cues mid-ride")
eq(r.riding, true, "era: the ride stands through an expiring JotC")

-- Retail (12.x) inertness: the stand-in never swings, but seals, cooldowns, mana
-- and creature type all answer on Retail - every such shape must stay empty. --
local saved_family_retail = st.family
st.family = "RETAIL"
-- The reseal tick (no seal, full swing) prompts nothing.
r = ev({})
eq(r.action, nil, "retail: the reseal tick never prompts")
eq(r.hold, false, "retail: the reseal tick never holds")
-- Blood up prompts nothing (no reseal, no ride, no judgement cue).
r = ev({ seal = "sob", swing_remaining = 3.0, gcd_remaining = 0, cs_remaining = 6,
    judge_remaining = 0.5 })
eq(r.action, nil, "retail: blood up never prompts")
eq(r.riding, false, "retail: blood up never rides")
eq(r.judge_call, false, "retail: blood up never cues judgement")
-- The CS override never fires.
r = ev({ cs_remaining = 0 })
eq(r.action, nil, "retail: the CS override never fires")
eq(r.hold, false, "retail: the CS override never holds")
-- No filler is ever suggested, even with melees + mana + an exorcisable target.
r = ev({ seal = "soc", gcd_remaining = 1.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 40, creature_type = "Undead" })
eq(r.action, nil, "retail: a filler setup never prompts")
eq(r.filler_kind, nil, "retail: no filler is ever suggested")
eq(r.prediction_hold, 0, "retail: the prediction hold is neutral")
eq(r.waiting_judgement, false, "retail: the judgement latch stays clear")
-- A stale out table is fully overwritten (no result field survives).
local stale_na = { action = "soc", hold = true, riding = true, judge_call = true,
    filler_kind = "exorcism", prediction_hold = 2.5, waiting_judgement = true }
check(na.evaluate(inp({ seal = "sob" }), stale_na) == stale_na,
    "retail: evaluate returns the caller's out table")
eq(stale_na.action, nil, "retail: a stale action is cleared")
eq(stale_na.hold, false, "retail: a stale hold is cleared")
eq(stale_na.riding, false, "retail: a stale ride is cleared")
eq(stale_na.judge_call, false, "retail: a stale judgement cue is cleared")
eq(stale_na.filler_kind, nil, "retail: a stale filler is cleared")
eq(stale_na.prediction_hold, 0, "retail: a stale prediction hold is neutralised")
eq(stale_na.waiting_judgement, false, "retail: a stale judgement latch is cleared")
-- The gate is Retail-specific: any other family still prompts.
st.family = "TBC"
r = ev({})
eq(r.action, "soc", "non-retail family: the reseal tick still prompts")
st.family = saved_family_retail

-- Wrath FCFS + SoD Exodin (evaluate_fcfs) ---------------------------------------
-- Pure priority-winner branches; the archived tree above is untouched. finputs
-- defaults to everything ready (mana 100, Undead, AoW up) so each case isolates
-- by putting higher-priority abilities on cooldown.
local function finputs(overrides)
    local t = {
        fcfs_mode = "wrath", G = 1.5, gcd_remaining = 0,
        cs_known = true, cs_remaining = 0, judge_remaining = 0,
        ds_remaining = 0, cons_remaining = 0, exo_remaining = 0,
        hw_remaining = 0, how_remaining = 0,
        mana_pct = 100, creature_type = "Undead",
        target_count = nil, target_health_pct = 100, has_aow = true,
    }
    for k, v in pairs(overrides or {}) do t[k] = v end
    return t
end
local function fev(overrides)
    for k in pairs(out) do out[k] = nil end
    return na.evaluate_fcfs(finputs(overrides), out)
end
-- finputs defaults fcfs_mode to "wrath" (a nil constructor value is a no-op in
-- Lua), so mode-less cases strip it explicitly after construction.
local function fev_nomode(overrides)
    local t = finputs(overrides)
    t.fcfs_mode = nil
    for k in pairs(out) do out[k] = nil end
    return na.evaluate_fcfs(t, out)
end

-- Unknown / non-FCFS modes yield the empty display shape.
r = fev_nomode({})
eq(r.action, nil, "fcfs: no mode prompts nothing")
eq(r.hold, false, "fcfs: no mode holds nothing")
eq(r.riding, false, "fcfs: no mode never rides")
eq(r.judge_call, false, "fcfs: no mode never cues judgement")
eq(r.filler_kind, nil, "fcfs: no mode suggests no filler")
eq(r.waiting_judgement, false, "fcfs: no mode keeps the latch clear")

r = fev({ fcfs_mode = "bogus" })
eq(r.action, nil, "fcfs: an unknown mode prompts nothing")
eq(r.filler_kind, nil, "fcfs: an unknown mode suggests no filler")

local saved_family_fcfs = st.family
st.family = "RETAIL"
r = fev({})
eq(r.action, nil, "fcfs: Retail stays inert even in wrath mode")
eq(r.filler_kind, nil, "fcfs: Retail suggests no filler even in wrath mode")
eq(r.judge_call, false, "fcfs: Retail never cues judgement even in wrath mode")
st.family = "SOD-PLACEHOLDER"
r = fev({ fcfs_mode = "sod" })
eq(r.filler_kind, "exorcism", "fcfs: a non-Retail family runs the sod table")
st.family = saved_family_fcfs

-- Wrath order: CS > Judge > DS > Cons > AoW-Exo > HW --------------------------
r = fev({})
eq(r.action, "cs", "wrath: all ready -> Crusader Strike")
eq(r.hold, false, "wrath: the winner needs no hold")
eq(r.riding, false, "wrath: FCFS never rides")
eq(r.judge_call, false, "wrath: CS wins without a judgement cue")
eq(r.filler_kind, nil, "wrath: CS wins without a filler")
eq(r.prediction_hold, 0, "wrath: the prediction hold is neutral")
eq(r.waiting_judgement, false, "wrath: no judgement latch in FCFS")

r = fev({ cs_remaining = 6 })
eq(r.action, nil, "wrath: Judge wins through the cue, not the action icon")
eq(r.judge_call, true, "wrath: CS on CD -> Judgement cue")

r = fev({ cs_remaining = 6, judge_remaining = 6 })
eq(r.action, "sob", "wrath: CS + Judge on CD -> Divine Storm on the sob channel")

r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 8 })
eq(r.filler_kind, "consecration", "wrath: next -> Consecration")

r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 8, cons_remaining = 8 })
eq(r.filler_kind, "exorcism", "wrath: next -> Exorcism under Art of War")

-- AoW gate: Exorcism without the proc is skipped, Holy Wrath takes the tick.
r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 8,
    cons_remaining = 8, has_aow = false })
eq(r.filler_kind, "how", "wrath: Exorcism without AoW is skipped (Holy Wrath wins)")

-- Holy Wrath eligibility: Undead/Demon only; ineligible falls to the wait.
r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 8,
    cons_remaining = 8, exo_remaining = 8, creature_type = "Beast" })
eq(r.filler_kind, nil, "wrath: Holy Wrath vs Beast is withheld")
eq(r.action, "cs", "wrath: nothing castable waits on Crusader Strike")
eq(r.hold, true, "wrath: the wait holds")

-- Never-wait: a ready Exorcism beats waiting 0.5 s on Crusader Strike.
r = fev({ cs_remaining = 0.5, judge_remaining = 6, ds_remaining = 8, cons_remaining = 8 })
eq(r.filler_kind, "exorcism", "wrath: never wait on CS while Exorcism is ready")

-- Priority still respected when the top spell IS ready.
r = fev({ cs_remaining = 0 })
eq(r.action, "cs", "wrath: a ready CS beats a ready Exorcism")

-- Mana gates: 35/30 are not above their thresholds.
r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 8,
    mana_pct = 35 })
eq(r.filler_kind, "exorcism", "wrath: Consecration at 35 is mana-withheld")

r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 8,
    mana_pct = 36 })
eq(r.filler_kind, "consecration", "wrath: Consecration at 36 fires")

r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 8,
    cons_remaining = 8, mana_pct = 30 })
eq(r.filler_kind, "how", "wrath: Exorcism at 30 is mana-withheld (HW wins)")

r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 8,
    cons_remaining = 8, mana_pct = 30, creature_type = "Beast" })
eq(r.action, "cs", "wrath: mana-starved with no eligible target waits on CS")
eq(r.hold, true, "wrath: the mana-starved wait holds")

-- Readiness is measured against the GCD end (castable when the GCD frees).
r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 0.01,
    gcd_remaining = 0 })
eq(r.filler_kind, "consecration", "wrath: DS 0.01 s out with a free GCD is not ready")

r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 0.01,
    gcd_remaining = 0.5 })
eq(r.action, "sob", "wrath: DS 0.01 s out with 0.5 s of GCD left is ready")

r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 0.5,
    gcd_remaining = 0.5 })
eq(r.action, "sob", "wrath: remaining == GCD reads as ready")

-- Unknown spells (nil / 999) are withheld, never prompted.
r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 999 })
eq(r.filler_kind, "consecration", "wrath: DS 999 means unknown (withheld)")

local nonil = finputs({ cs_remaining = 6, judge_remaining = 6 })
nonil.ds_remaining = nil
for k in pairs(out) do out[k] = nil end
r = na.evaluate_fcfs(nonil, out)
eq(r.filler_kind, "consecration", "wrath: nil DS remaining means unknown (withheld)")

-- Nothing ready: wait on the top priority; nothing known at all: stay empty.
r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 8,
    cons_remaining = 8, exo_remaining = 8, hw_remaining = 8 })
eq(r.action, "cs", "wrath: all on CD waits on Crusader Strike")
eq(r.hold, true, "wrath: the all-on-CD wait holds")
eq(r.filler_kind, nil, "wrath: the all-on-CD wait suggests no filler")

local noinfo = finputs({})
noinfo.cs_remaining, noinfo.judge_remaining, noinfo.ds_remaining = nil, nil, nil
noinfo.cons_remaining, noinfo.exo_remaining, noinfo.hw_remaining = nil, nil, nil
for k in pairs(out) do out[k] = nil end
r = na.evaluate_fcfs(noinfo, out)
eq(r.action, nil, "wrath: no known ability prompts nothing")
eq(r.hold, false, "wrath: no known ability holds nothing")

-- An unknown Crusader Strike is never prompted (SoD rune missing / low level).
r = fev({ cs_remaining = 0, ds_remaining = 0, judge_remaining = 6,
    cons_remaining = 8, exo_remaining = 8, hw_remaining = 8, cs_known = false })
eq(r.action, "sob", "wrath: unknown CS is skipped (DS wins)")

r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 8,
    cons_remaining = 8, exo_remaining = 8, hw_remaining = 8, cs_known = false })
eq(r.action, nil, "wrath: the wait skips unknown CS for soonest-known Judge")
eq(r.judge_call, true, "wrath: the wait cues Judge")
eq(r.hold, true, "wrath: the wait on Judge holds")

-- 2pc-T10: the order is stable with and without it (resets surface as live
-- readiness, which the walk already elevates); explicit set detection deferred.
r = fev({ cs_remaining = 6, judge_remaining = 6, ds_2pc = true })
eq(r.action, "sob", "wrath: 2pc-T10 keeps DS above Cons/Exorcism")
r = fev({ cs_remaining = 6, judge_remaining = 6, ds_2pc = false })
eq(r.action, "sob", "wrath: base order matches the 2pc order")

-- Latch hygiene: a stale carry never survives an FCFS tick.
r = fev({ waiting_judgement = true })
eq(r.waiting_judgement, false, "wrath: FCFS clears a stale judgement latch")

-- Holy Wrath carries no mana gate (documented choice: eligibility is the gate).
r = fev({ cs_remaining = 6, judge_remaining = 6, ds_remaining = 8,
    cons_remaining = 8, exo_remaining = 8, mana_pct = 5 })
eq(r.filler_kind, "how", "wrath: eligible Holy Wrath fires even nearly oom")

-- Out-table contract: the caller's table is reused and fully overwritten.
local stale_fcfs = { action = "cs", hold = true, riding = true, judge_call = true,
    filler_kind = "exorcism", prediction_hold = 2.5, waiting_judgement = true }
local stale_inputs = finputs({})
stale_inputs.fcfs_mode = nil
check(na.evaluate_fcfs(stale_inputs, stale_fcfs) == stale_fcfs,
    "fcfs: evaluate returns the caller's out table")
eq(stale_fcfs.action, nil, "fcfs: a stale action is cleared")
eq(stale_fcfs.hold, false, "fcfs: a stale hold is cleared")
eq(stale_fcfs.riding, false, "fcfs: a stale ride is cleared")
eq(stale_fcfs.judge_call, false, "fcfs: a stale judgement cue is cleared")
eq(stale_fcfs.filler_kind, nil, "fcfs: a stale filler is cleared")
eq(stale_fcfs.prediction_hold, 0, "fcfs: a stale prediction hold is neutralised")
eq(stale_fcfs.waiting_judgement, false, "fcfs: a stale judgement latch is cleared")

-- SoD Exodin: Exo (core) > CS > DS > Judge > Cons > HoW ----------------------
r = fev({ fcfs_mode = "sod" })
eq(r.filler_kind, "exorcism", "sod: all ready -> Exorcism first (core button)")
eq(r.action, nil, "sod: the Exorcism winner needs no action icon")

r = fev({ fcfs_mode = "sod", exo_remaining = 6 })
eq(r.action, "cs", "sod: Exorcism on CD -> Crusader Strike")

r = fev({ fcfs_mode = "sod", exo_remaining = 6, cs_remaining = 6 })
eq(r.action, "sob", "sod: next -> Divine Storm on the sob channel")

r = fev({ fcfs_mode = "sod", exo_remaining = 6, cs_remaining = 6, ds_remaining = 8 })
eq(r.judge_call, true, "sod: next -> Judgement cue")

r = fev({ fcfs_mode = "sod", exo_remaining = 6, cs_remaining = 6,
    ds_remaining = 8, judge_remaining = 6 })
eq(r.filler_kind, "consecration", "sod: next -> Consecration (target unknown)")

-- Consecration is cleave-gated: single-target withholds, 3+ keeps.
r = fev({ fcfs_mode = "sod", exo_remaining = 6, cs_remaining = 6,
    ds_remaining = 8, judge_remaining = 6, target_count = 1,
    target_health_pct = 100 })
eq(r.filler_kind, "exorcism", "sod: single-target withholds Consecration")
eq(r.hold, true, "sod: the withheld tick waits on Exorcism (soonest known)")

r = fev({ fcfs_mode = "sod", exo_remaining = 6, cs_remaining = 6,
    ds_remaining = 8, judge_remaining = 6, target_count = 3 })
eq(r.filler_kind, "consecration", "sod: three targets keep Consecration")

r = fev({ fcfs_mode = "sod", exo_remaining = 6, cs_remaining = 6,
    ds_remaining = 8, judge_remaining = 6, mana_pct = 35 })
eq(r.hold, true, "sod: Consecration at 35 is mana-withheld (waits on Exorcism)")

-- Exodin Exorcism is the core vs EVERY target with no AoW gate (unlike Wrath).
r = fev({ fcfs_mode = "sod", creature_type = "Beast" })
eq(r.filler_kind, "exorcism", "sod: Exorcism fires vs Beast (no creature gate)")

r = fev({ fcfs_mode = "sod", has_aow = false })
eq(r.filler_kind, "exorcism", "sod: Exorcism fires without Art of War")

r = fev({ fcfs_mode = "sod", mana_pct = 30, cs_remaining = 0 })
eq(r.action, "cs", "sod: Exorcism at 30 is mana-withheld (CS wins)")

-- Hammer of Wrath below 20%, own cooldown; 20%+ / unknown never cues.
r = fev({ fcfs_mode = "sod", exo_remaining = 6, cs_remaining = 6,
    ds_remaining = 8, judge_remaining = 6, cons_remaining = 8,
    target_health_pct = 19, how_remaining = 0 })
eq(r.filler_kind, "how", "sod: HoW below 20% with HoW ready")

r = fev({ fcfs_mode = "sod", exo_remaining = 6, cs_remaining = 6,
    ds_remaining = 8, judge_remaining = 6, cons_remaining = 8,
    target_health_pct = 20, how_remaining = 0 })
eq(r.hold, true, "sod: 20% is not below the execute window (waits on Exorcism)")

local nohow_sod = finputs({ fcfs_mode = "sod", exo_remaining = 6, cs_remaining = 6,
    ds_remaining = 8, judge_remaining = 6, cons_remaining = 8,
    target_health_pct = 19 })
nohow_sod.how_remaining = nil
for k in pairs(out) do out[k] = nil end
r = na.evaluate_fcfs(nohow_sod, out)
eq(r.hold, true, "sod: unknown HoW cooldown never cues HoW")

r = fev({ fcfs_mode = "sod", exo_remaining = 6, cs_remaining = 6,
    ds_remaining = 8, judge_remaining = 6, cons_remaining = 8,
    target_health_pct = 19, how_remaining = 999 })
eq(r.hold, true, "sod: HoW 999 means unavailable (waits on Exorcism)")

-- A DS-only rune set (CS unknown) never prompts Crusader Strike.
r = fev({ fcfs_mode = "sod", cs_remaining = 0, ds_remaining = 0,
    judge_remaining = 6, cons_remaining = 8, exo_remaining = 8,
    how_remaining = 8, cs_known = false })
eq(r.action, "sob", "sod: unknown CS is skipped (DS wins)")

-- FCFS ignores the twist-only inputs (fit gate, JotC, seals, swing landmarks,
-- the mirrored filler reading): the branch stands on its own inputs.
r = fev({ fcfs_mode = "sod", exo_remaining = 6, cs_remaining = 6,
    ds_remaining = 8, judge_require_fit = true, jotc_remaining = 1.0,
    seal = "sob", swing_remaining = 0.3, cs_delay_max = 1.7,
    filler_remaining = 999, melee_count = 5 })
eq(r.judge_call, true, "sod: twist-only inputs do not disturb the order")

-- TBC micro: twist-weapon suitability labels ----------------------------------
-- (sourced TBC 2.5.6 ret; docs/research/tbc_minmax.md: slow >= 3.0 twists,
-- 3.8 the best-proc-rate speed, 3.6 the common raid speed).
eq(na.TBC_TWIST_MIN_SPEED, 3.0, "tbc: twist floor is the 3.0 slow-weapon minimum")
eq(na.TBC_TWIST_BEST_SPEED, 3.8, "tbc: best speed is the 3.8 SoC optimum")
eq(na.TBC_SOC_PROC_DELAY, 0.5, "tbc: SoC proc delay documents the 0.5 s model")
eq(na.classify_twist_weapon(3.8), "optimal", "tbc: 3.8 -> optimal")
eq(na.classify_twist_weapon(4.0), "optimal", "tbc: above 3.8 stays optimal")
eq(na.classify_twist_weapon(3.6), "slow", "tbc: 3.6 common raid speed -> slow")
eq(na.classify_twist_weapon(3.0), "slow", "tbc: 3.0 floor -> slow")
eq(na.classify_twist_weapon(2.9), "fast", "tbc: below 3.0 -> fast")
eq(na.classify_twist_weapon(2.0), "fast", "tbc: fast weapon -> fast")
eq(na.classify_twist_weapon(nil), "slow", "tbc: unknown speed defaults to 3.0 -> slow")
-- The labels never move the rotation thresholds above.
eq(na.calculate_rotation(3.8, 1.5), "1/2", "tbc: 3.8 still cadences 1/2")
eq(na.calculate_rotation(3.6, 1.5), "1/2", "tbc: 3.6 still cadences 1/2")

-- Forever adaptation (UNCONFIRMED beta; docs/research/forever_beta.md) --------
-- An absent/false flag keeps the archived behaviour (pinned by every check
-- above); the landmarks below reuse the 0.4 s window (optimal window unknown).
r = ev({ seal = "sob", swing_remaining = 2.2, speed = 2.0, gcd_remaining = 0,
    cs_remaining = 6, judge_remaining = 0.2, judge_require_fit = true,
    forever = true })
eq(r.judge_call, true, "forever: no-reseal fit cues where TBC keeps twisting")
eq(r.action, "soc", "forever: the reseal action stands with the cue")
eq(r.hold, false, "forever: judging costs no hold without a reseal")
eq(r.waiting_judgement, false, "forever: no hold means no latch")

r = ev({ seal = "sob", swing_remaining = 2.2, speed = 2.0, gcd_remaining = 0,
    cs_remaining = 6, judge_remaining = 0.2, judge_require_fit = true,
    forever = false })
eq(r.judge_call, false, "forever=false keeps the archived fit gate")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    target_count = 1, forever = true })
eq(r.action, "twist", "forever: single-target keeps the twist action")
eq(r.filler_kind, "consecration", "forever: single-target keeps Consecration (beta Ret ST)")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 50, forever = true, target_health_pct = 19, how_remaining = 0 })
eq(r.action, "twist", "forever: the execute keeps the twist action")
eq(r.filler_kind, "how", "forever: HoW below 20% with HoW ready (beta Ret ST)")

r = ev({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 50, forever = true, target_health_pct = 20, how_remaining = 0 })
eq(r.filler_kind, "consecration", "forever: 20% is not below the execute window")

local nohow_fw = inp({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6, melee_count = 3,
    mana_pct = 50, forever = true, target_health_pct = 19 })
nohow_fw.how_remaining = nil
r = fresh(nohow_fw)
eq(r.filler_kind, "consecration", "forever: unknown HoW cooldown never cues HoW")

r = ev({ seal = "soc", swing_remaining = 0.3, cs_remaining = 6, forever = true })
eq(r.action, "twist", "forever: in-twist + soc still twists now")
near(r.prediction_hold, 0, "forever: the 0.4 s landmarks stand (window UNCONFIRMED)")

r = ev({ seal = "sob", swing_remaining = 1.0, gcd_remaining = 0.5, cs_remaining = 6,
    melee_count = 3, forever = true })
eq(r.action, "soc", "forever: the twist-seal ride still reseals Command")
eq(r.riding, true, "forever: the ride overlay survives (SoR in the twist position)")

if failures == 0 then
    print("PASS  nextaction_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  nextaction_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
