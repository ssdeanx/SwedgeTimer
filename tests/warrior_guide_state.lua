-- tests/warrior_guide_state.lua: offline tests for the warrior next-action guide: the
-- pure rule engine (warrior_guide.lua) and the provider glue + drive (classes/warrior.lua)
-- over the real compat.lua + utils.lua + nextaction_ui.lua in a sandbox.
--
-- Pins:
--   * warrior_guide.lua loads with NO WoW API at all (a strict sandbox errors on any
--     global read) and the frozen rule matrix: all eight branches and their boundaries
--     (OP window exactly 0, execute at 19.9/20.1 %, bloodsurge while slamming, the
--     HS cost boundary at rage == cost, the swing-window margin, unknown rage/health,
--     the TBC Bloodthirst/Whirlwind ready boundaries, the Execute reservation and the
--     HS floor/reservation withholds),
--   * the frozen output fields are overwritten on every call (stale fields can never
--     survive into a reused out table) and nil inputs never error,
--   * the gather into the caller-owned reused table: every frozen input, the GCD-echo
--     filter (duration <= 1.51 s ignored), the rank-resolved icons/costs, stale-field
--     overwrites, cached rank resolution and unknown health/rage degrading to nil,
--   * the provider contract shape (slot keys, <= 6 slots, cooldown keys resolving into
--     the gathered inputs, possible actions naming declared slots),
--   * the Wrath default (fury) set: six slots op/execute/slam/hs/bt/ww with the
--     BT/WW readers, the 50-rage floor and the wrath_fury flag through the real
--     hooks; the legacy (non-core) contrast rides a Cata sandbox instead,
--   * the Wrath arms set (Mortal Strike known): six slots op/execute/rend/ms/
--     bladestorm/hs with the upkeep/cooldown readers and the wrath_arms flag,
--   * the SoD set (ERA + runes): six slots execute/slam/hs/bt/ww/raging_blow
--     with floor 60, the spam flag and the sod flag,
--   * the TBC family set (six slots with bt/ww replacing cleave, BT/WW cooldown+cost
--     reads, the 40-rage HS floor, the gated display through the real hooks),
--   * the display mapping through the real frame sandbox (action -> slot -> fade targets,
--     the HOLD/RIDE texts, real-cooldown swipes and their latch, the option gates),
--   * the compat UnitHealth/UnitHealthMax guards (nil = unknown),
--   * the config/options parity for every new warrior key and the TOC load order,
--   * the drive wiring (post_init -> ui.init, on_bar_update -> the settings diff +
--     ui.on_bar_update) exercised through the real hooks.
-- Run from the repo root: lua5.1 tests/warrior_guide_state.lua  (any cwd works).

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
            error("warrior_guide.lua touched a global: " .. tostring(key))
        end,
    })
    local chunk = assert(loadfile(ROOT .. "warrior_guide.lua"))
    setfenv(chunk, strict)
    local ok, err = pcall(chunk, "SwedgeTimer", pure)
    check(ok, "warrior_guide.lua loads with no WoW API and no globals (" .. tostring(err) .. ")")
end

local wg = pure.warrior_guide
check(type(wg) == "table", "warrior_guide.lua defines st.warrior_guide")
check(type(wg.evaluate) == "function", "the pure engine is exported")
eq(wg.EXECUTE_PCT_DEFAULT, 20, "the execute threshold default is 20")
eq(wg.REACTION_DEFAULT, 0.1, "the reaction default mirrors the paladin engine (0.1)")

-- The practice-facing pure helpers (the rotation scenario + the drills).
do
    eq(wg.WW_DELAY, 1.5, "the Delay Check window is exposed as 1.5 s")
    eq(wg.CORE_RESERVE_WINDOW, 1.5, "the reserve window is exposed as 1.5 s")
    check(type(wg.core_reserves_rage) == "function",
        "the core reservation is exported for the drill")
    eq(wg.core_reserves_rage({ bt_remaining = 0, rage = 10 }, 15), true,
        "the exported reservation: a ready core claims the next GCD")
    eq(wg.core_reserves_rage({ bt_remaining = 30, rage = 100 }, 15), false,
        "the exported reservation: a core far outside the window claims nothing")
    eq(wg.core_reserves_rage({ bt_remaining = 1, rage = 20, bt_cost = 30 }, 15), true,
        "the exported reservation: a core inside the window with too little rage left claims it")
    eq(wg.core_reserves_rage({}, 15), false,
        "the exported reservation: no reader means no claim")

    -- The Execute drain (the sims spend the whole pool).
    eq(wg.rage_after_execute(100, 15, true), 0,
        "the Execute drain: the draining families end empty")
    eq(wg.rage_after_execute(0, 15, true), 0,
        "the Execute drain: an empty pool stays empty")
    eq(wg.rage_after_execute(50, 15, false), 35,
        "the Execute drain: a non-draining family keeps the change")
    eq(wg.rage_after_execute(10, 15, false), 0,
        "the Execute drain: the change never goes below zero")
    eq(wg.rage_after_execute("x", 15, true), nil,
        "the Execute drain: an unreadable pool answers nil")
    eq(wg.rage_after_execute(0 / 0, 15, true), nil,
        "the Execute drain: a NaN pool answers nil")

    -- The action reasons.
    eq(wg.action_reason("bt"), "Bloodthirst", "the reason for Bloodthirst")
    eq(wg.action_reason("op"), "Overpower window (dodge proc)", "the reason for Overpower")
    check(type(wg.action_reason("nope")) == "nil",
        "an unknown action has no reason")
    eq(wg.action_reason(nil), nil, "a nil action has no reason")
    -- The unset sentinel (an input the caller removes): the file-level NONE
    -- sentinel is declared further down, so this block carries its own.
    local UNSET = {}
    -- The utility spine's reasons (the APL's own rows).
    eq(wg.action_reason("bloodrage"), "Bloodrage (the rage cooldown)",
        "the reason for Bloodrage")
    eq(wg.action_reason("battle_shout"), "Battle Shout (the attack-power buff)",
        "the reason for Battle Shout")
    eq(wg.action_reason("battle_stance"), "Battle Stance (the Overpower stance)",
        "the reason for Battle Stance")
    eq(wg.action_reason("berserker_stance"), "Berserker Stance (the damage stance)",
        "the reason for Berserker Stance")

    --=====================================================================================
    -- The utility spine: the per-line verdict, the order walk and the stance arms
    --=====================================================================================
    do
        local lines = wg.UTILITY_LINES
        check(type(lines) == "table", "the engine publishes the utility spine's line table")
        local line = lines.bloodrage
        check(type(line) == "table", "the Bloodrage row carries its input names")
        eq(line.remaining, "bloodrage_remaining", "the Bloodrage row names its cooldown read")
        eq(line.duration, "bloodrage_duration", "the Bloodrage row names its duration read")
        eq(line.buff, "bloodrage_buff", "the Bloodrage row names its buff read")
        eq(line.known, "bloodrage_known", "the Bloodrage row names its knowledge read")
        eq(line.rage_max, "bloodrage_rage_max", "the Bloodrage row names its rage ceiling read")
        eq(lines.battle_shout.rage_max, nil,
            "a row without a rage ceiling carries no rage read")
        -- The verdict: a row is due only when every gate is a known gate.
        local function due(overrides)
            local inputs = {
                bloodrage_known = true, bloodrage_remaining = 0, bloodrage_buff = false,
                bloodrage_rage_max = 90, rage = 10,
            }
            for k, v in pairs(overrides or {}) do
                if v == UNSET then
                    inputs[k] = nil
                else
                    inputs[k] = v
                end
            end
            return wg.utility_line_due(line, inputs)
        end
        eq(due({}), true,
            "the utility verdict: a known, ready, buff-free row is due")
        eq(due({ bloodrage_buff = true }), false,
            "the utility verdict: a row whose buff is up is never due")
        eq(due({ bloodrage_remaining = 12 }), false,
            "the utility verdict: a row on cooldown is never due")
        eq(due({ bloodrage_known = false }), false,
            "the utility verdict: a spell the client lacks is never due")
        eq(due({ bloodrage_known = UNSET }), false,
            "the utility verdict: an unreadable knowledge probe never prompts")
        eq(due({ bloodrage_buff = UNSET }), false,
            "the utility verdict: an unreadable buff never prompts")
        eq(due({ bloodrage_remaining = UNSET }), false,
            "the utility verdict: an unreadable cooldown never prompts")
        eq(due({ rage = 95 }), false,
            "the utility verdict: the APL's rage ceiling withholds the row")
        eq(due({ rage = UNSET }), false,
            "the utility verdict: an unreadable rage pool never prompts")
        eq(wg.utility_line_due(nil, {}), false,
            "the utility verdict: no line is never due")
        -- The order walk: the APL's own priority order decides.
        local order = { "death_wish", "bloodrage" }
        local inputs = {
            death_wish_known = true, death_wish_remaining = 0, death_wish_buff = false,
            bloodrage_known = true, bloodrage_remaining = 0, bloodrage_buff = false,
            bloodrage_rage_max = 90, rage = 10,
        }
        eq(wg.utility_spine_pick(order, inputs), "death_wish",
            "the spine picks the APL's first due row")
        inputs.death_wish_remaining = 30
        eq(wg.utility_spine_pick(order, inputs), "bloodrage",
            "the spine falls through to the next due row")
        eq(wg.utility_spine_pick({}, inputs), nil,
            "the spine answers nil when nothing is due")
        eq(wg.utility_spine_pick(nil, inputs), nil,
            "the spine answers nil without an order")
        -- The stance upkeep arm.
        eq(wg.utility_stance_action("battle", "berserker"), "berserker_stance",
            "the stance upkeep asks for the wanted stance")
        eq(wg.utility_stance_action("berserker", "berserker"), nil,
            "the stance upkeep never asks for the stance the player is in")
        eq(wg.utility_stance_action(nil, "berserker"), nil,
            "the stance upkeep never asks on an unknown stance")
        eq(wg.utility_stance_action("battle", nil), nil,
            "the stance upkeep never asks when the family carries no stance row")
        -- The weave arm.
        eq(wg.utility_weave_stance("berserker", true, true), "battle_stance",
            "the weave asks for Battle Stance while the Overpower window is live")
        eq(wg.utility_weave_stance("berserker", true, false), nil,
            "the weave never asks outside the Overpower window")
        eq(wg.utility_weave_stance("berserker", false, true), nil,
            "the weave never asks on a family whose APL does not carry it")
        eq(wg.utility_weave_stance("battle", true, true), nil,
            "the weave never asks for the stance the player is in")
        eq(wg.utility_weave_stance(nil, true, true), nil,
            "the weave never asks on an unknown stance")
        -- The stance keys the engine names.
        eq(wg.STANCE_ACTIONS.battle, "battle_stance", "the battle stance's action key")
        eq(wg.STANCE_ACTIONS.berserker, "berserker_stance",
            "the berserker stance's action key")
        eq(wg.STANCE_ACTIONS.gladiator, "gladiator_stance",
            "the gladiator stance's action key")
        eq(wg.STANCE_GLADIATOR, "gladiator", "the SoD rune stance's key")
    end

    --=====================================================================================
    -- The utility spine in the engine: the row's read decides the pick
    --=====================================================================================
    do
        local function pick(overrides)
            local inputs = { swing_remaining = 2.0, rage = 50, hs_cost = 15,
                target_health_pct = 100, execute_pct = 20,
                utility_order = { "bloodrage" },
                bloodrage_known = true, bloodrage_remaining = 0, bloodrage_buff = false,
                bloodrage_rage_max = 90 }
            for k, v in pairs(overrides or {}) do
                if v == UNSET then
                    inputs[k] = nil
                else
                    inputs[k] = v
                end
            end
            local out = {}
            wg.evaluate(inputs, out)
            return out.action
        end
        eq(pick({}), "bloodrage",
            "the engine asks for the utility row whose read says so")
        eq(pick({ bloodrage_buff = true }), "hs",
            "the engine never asks for a utility row whose buff is up")
        eq(pick({ bloodrage_remaining = 12 }), "hs",
            "the engine never asks for a utility row on cooldown")
        eq(pick({ bloodrage_known = false }), "hs",
            "the engine never asks for a utility row the client lacks")
        eq(pick({ bloodrage_buff = UNSET }), "hs",
            "the engine never asks for a utility row with an unreadable buff")
        eq(pick({ rage = 95 }), "hs",
            "the engine withholds a utility row over the APL's rage ceiling")
        eq(pick({ bloodrage_rage_max = nil }), "bloodrage",
            "a row without a rage ceiling asks regardless of the pool")
        -- The LOW rows sit below the core rotation, the HIGH rows above it.
        local function pick_low(overrides)
            local inputs = { swing_remaining = 2.0, rage = 50, hs_cost = 15,
                target_health_pct = 100, execute_pct = 20,
                bt_remaining = 0, ww_remaining = 5,
                utility_order_low = { "battle_shout" },
                battle_shout_known = true, battle_shout_remaining = 0,
                battle_shout_buff = false }
            for k, v in pairs(overrides or {}) do
                if v == UNSET then
                    inputs[k] = nil
                else
                    inputs[k] = v
                end
            end
            local out = {}
            wg.evaluate(inputs, out)
            return out.action
        end
        eq(pick_low({}), "bt",
            "the core rotation wins over a LOW utility row")
        eq(pick_low({ bt_remaining = 30, ww_remaining = 30 }), "battle_shout",
            "the LOW utility row fires when the core is cooling")
        -- The stance upkeep arm, in the engine.
        local out = {}
        wg.evaluate({ swing_remaining = 2.0, rage = 50, hs_cost = 15,
            target_health_pct = 100, execute_pct = 20, bt_remaining = 30, ww_remaining = 30,
            utility_stance = "battle", utility_wanted_stance = "berserker" }, out)
        eq(out.action, "berserker_stance",
            "the engine asks for the stance the APL's upkeep row wants")
        local out2 = {}
        wg.evaluate({ swing_remaining = 2.0, rage = 50, hs_cost = 15,
            target_health_pct = 100, execute_pct = 20, bt_remaining = 30, ww_remaining = 30,
            utility_stance = "berserker", utility_wanted_stance = "berserker" }, out2)
        eq(out2.action, "hs",
            "the engine never asks for the stance the player is already in")
        -- The weave arm, in the engine.
        local out3 = {}
        wg.evaluate({ swing_remaining = 2.0, rage = 50, hs_cost = 15,
            target_health_pct = 100, execute_pct = 20,
            utility_stance = "berserker", utility_weave = true, overpower_remaining = 3 },
            out3)
        eq(out3.action, "battle_stance",
            "the engine asks for the weave's first step while the Overpower window is live")
    end

    -- The audited drill bands.
    eq(wg.ww_delay_band(2.5), "S", "D-W2: a 2.5 s clearance is an S")
    eq(wg.ww_delay_band(1.0), "S", "D-W2: a 1.0 s clearance is an S")
    eq(wg.ww_delay_band(0.9), "A", "D-W2: a 0.9 s clearance is an A")
    eq(wg.ww_delay_band(0.5), "A", "D-W2: a 0.5 s clearance is an A")
    eq(wg.ww_delay_band(0.49), "B", "D-W2: below half a second is a B")
    eq(wg.ww_delay_band(0.2), "B", "D-W2: a 0.2 s clearance is a B")
    eq(wg.ww_delay_band(0.19), "C", "D-W2: below a fifth is a C")
    eq(wg.ww_delay_band(0), "C", "D-W2: the window's edge is a C")
    eq(wg.ww_delay_band(-0.1), "D", "D-W2: inside the window is a D")
    eq(wg.ww_delay_band("x"), nil, "D-W2: an unreadable margin answers nil")

    eq(wg.sunder_upkeep_band(5), "S", "D-W3: five stacks is an S")
    eq(wg.sunder_upkeep_band(4), "A", "D-W3: four stacks is an A")
    eq(wg.sunder_upkeep_band(3), "B", "D-W3: three stacks is a B")
    eq(wg.sunder_upkeep_band(2), "C", "D-W3: two stacks is a C")
    eq(wg.sunder_upkeep_band(1), "D", "D-W3: one stack is a D")
    eq(wg.sunder_upkeep_band(0), "F", "D-W3: an expired debuff is an F")
    eq(wg.sunder_upkeep_band(nil), nil, "D-W3: an unreadable stack count answers nil")

    eq(wg.execute_burn_band(true, nil), "S", "D-W4: a full pool with no lateness reading is an S")
    eq(wg.execute_burn_band(true, 1), "S", "D-W4: a full pool one GCD late is an S")
    eq(wg.execute_burn_band(true, 2), "A", "D-W4: a full pool two GCDs late is an A")
    eq(wg.execute_burn_band(true, 3), "B", "D-W4: a full pool three GCDs late is a B")
    eq(wg.execute_burn_band(true, 4), "D", "D-W4: a full pool four GCDs late is a D")
    eq(wg.execute_burn_band(false, nil), "C", "D-W4: a short pool with a clean burn is a C")
    eq(wg.execute_burn_band(false, 1), "C", "D-W4: a short pool one GCD late is a C")
    eq(wg.execute_burn_band(false, 2), "D", "D-W4: a short pool two GCDs late is a D")

    eq(wg.core_order_band(0, 0), "S", "D-W1: no mis-pick is an S")
    eq(wg.core_order_band(1, 0), "A", "D-W1: one mis-pick is an A")
    eq(wg.core_order_band(2, 0), "B", "D-W1: two mis-picks are a B")
    eq(wg.core_order_band(3, 0), "C", "D-W1: three mis-picks are a C")
    eq(wg.core_order_band(5, 0), "D", "D-W1: five mis-picks are a D")
    eq(wg.core_order_band(6, 0), "F", "D-W1: six mis-picks are an F")
    eq(wg.core_order_band(0, 1), "F", "D-W1: a reserve violation is an F")
    eq(wg.core_order_band(-1, 0), nil, "D-W1: an unreadable count answers nil")
    eq(wg.core_order_band("x", 0), nil, "D-W1: a non-numeric count answers nil")

    -- D-W5 (the Heroic Strike / Cleave queue window): the margin bands and the
    -- pure verdict. The cited numbers are the sim's own (the +19 % dual-wield
    -- penalty it lifts and the 5 % white base chance it falls back to - 24 %
    -- together); the queue delay is the sim's 250 ms reaction-time model.
    eq(wg.HS_QUEUE_DRILL, "warrior_hs_queue", "D-W5: the drill's key is the class's own")
    eq(wg.DW_MISS_PENALTY, 0.19, "D-W5: the dual-wield penalty the queue lifts is +19 %")
    eq(wg.WHITE_MISS_BASE, 0.05, "D-W5: the white base miss chance is 5 %")
    eq(wg.HS_QUEUE_DELAY_SECONDS, 0.25, "D-W5: the sim's queue delay is 250 ms")
    eq(wg.hs_queue_band(0.30), "S", "D-W5: a 300 ms margin is an S")
    eq(wg.hs_queue_band(0.25), "S", "D-W5: a 250 ms margin is an S")
    eq(wg.hs_queue_band(0.20), "A", "D-W5: a 200 ms margin is an A")
    eq(wg.hs_queue_band(0.10), "B", "D-W5: a 100 ms margin is a B")
    eq(wg.hs_queue_band(0.05), "C", "D-W5: a 50 ms margin is a C")
    eq(wg.hs_queue_band(0.005), "D", "D-W5: a hair-thin margin is a D")
    eq(wg.hs_queue_band(nil), nil, "D-W5: an unreadable margin answers nil")
    eq(wg.hs_queue_band("x"), nil, "D-W5: a non-numeric margin answers nil")
    -- The verdict: the offhand's next landing has to land before the mainhand
    -- swing that fires the queued ability, and the margin is the room on the
    -- tighter side of the press window.
    eq(wg.hs_queue_grade({ dual_wielding = true, speed = 2.6, swing_remaining = 2.1,
        offhand_swing_remaining = 0.8 }), "S",
        "D-W5: a press with room on both sides is an S")
    eq(wg.hs_queue_grade({ dual_wielding = true, speed = 2.6, swing_remaining = 2.1,
        offhand_swing_remaining = 2.5 }), "F",
        "D-W5: the offhand landing after the ability fires is an F")
    eq(wg.hs_queue_grade({ dual_wielding = true, speed = 2.6, swing_remaining = 2.1,
        offhand_swing_remaining = 2.1 }), "F",
        "D-W5: a coincident offhand landing is an F (the window is empty)")
    eq(wg.hs_queue_grade({ dual_wielding = true, speed = 2.6, swing_remaining = 2.595,
        offhand_swing_remaining = 0.5 }), "D",
        "D-W5: the margin is the tighter of the two sides")
    eq(wg.hs_queue_grade({ dual_wielding = false, speed = 2.6, swing_remaining = 2.1,
        offhand_swing_remaining = 0.8 }), nil,
        "D-W5: a one-armed warrior has no offhand swing to catch")
    eq(wg.hs_queue_grade({ dual_wielding = true, speed = 2.6, swing_remaining = 2.1 }),
        nil, "D-W5: an unknown offhand landing answers nil")
    eq(wg.hs_queue_grade({ dual_wielding = true, speed = 0, swing_remaining = 2.1,
        offhand_swing_remaining = 0.8 }), nil,
        "D-W5: an unknown weapon speed answers nil")
    eq(wg.hs_queue_grade(nil), nil, "D-W5: no inputs answer nil")
end

-- Rule-matrix inputs: everything the frozen input set names, with a baseline that lands
-- on rule 7 (rage 50 >= cost 15, window open). NONE clears a key (a nil literal in an
-- override table is simply absent in Lua).
local NONE = {}
local function inp(overrides)
    local t = {
        speed = 3.0, swing_remaining = 2.0, gcd_remaining = 0,
        rage = 50, hs_cost = 15, cleave_cost = 20,
        hs_queued = false, cleave_queued = false, insufficient_rage = false,
        has_bloodsurge = false, slam_casting = false,
        target_health_pct = 100, execute_pct = 20,
        op_remaining = 0, execute_remaining = 0, slam_remaining = 0,
        hs_remaining = 0, cleave_remaining = 0,
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
    local ret = wg.evaluate(inp(overrides), out)
    eq(ret, out, "evaluate returns the caller's out table")
    return out
end

-- Baseline (rule 7): nothing better to do -> Heroic Strike.
do
    local out = evaluate({})
    eq(out.action, "hs", "baseline: rage covers the HS cost -> Heroic Strike")
    eq(out.hold, false, "baseline: no hold")
    eq(out.hold_text, nil, "baseline: no hold text")
    eq(out.filler_slot, nil, "baseline: filler_slot stays nil")
    eq(out.judge_slot, nil, "baseline: judge_slot stays nil")
    eq(out.rotation_key, nil, "baseline: rotation_key stays nil")
    eq(out.waiting_judgement, false, "baseline: waiting_judgement stays false")
end

-- Rule 1: the Overpower dodge window.
do
    eq(evaluate({ overpower_remaining = 5 }).action, "op",
        "rule 1: an active OP window with the ability ready -> Overpower")
    eq(evaluate({ overpower_remaining = 0.001 }).action, "op",
        "rule 1: a window just off zero is still active")
    eq(evaluate({ overpower_remaining = 0 }).action, "hs",
        "rule 1 boundary: a window of exactly 0 is already over")
    eq(evaluate({ overpower_remaining = -1 }).action, "hs",
        "rule 1 boundary: a negative window is over")
    eq(evaluate({ overpower_remaining = 5, op_remaining = 2 }).action, "hs",
        "rule 1: a real Overpower cooldown withholds the prompt")
    eq(evaluate({ overpower_remaining = 5, op_remaining = NONE }).action, "op",
        "rule 1: an unknown cooldown reads as ready")
    eq(evaluate({ overpower_remaining = 5, target_health_pct = 10,
        has_bloodsurge = true }).action, "op",
        "rule 1 outranks the Execute range and the Bloodsurge proc")
    local out = evaluate({ overpower_remaining = 5 })
    eq(out.hold, false, "rule 1: the OP prompt carries no hold")
    eq(out.hold_text, nil, "rule 1: the OP prompt carries no hold text")
end

-- Rule 2: the Execute range.
do
    eq(evaluate({ target_health_pct = 19.9 }).action, "execute",
        "rule 2: 19.9 % health -> Execute")
    eq(evaluate({ target_health_pct = 20.1 }).action, "hs",
        "rule 2 boundary: 20.1 % health falls through to the HS fallback")
    eq(evaluate({ target_health_pct = 20 }).action, "hs",
        "rule 2 boundary: exactly the threshold is not below it")
    eq(evaluate({ target_health_pct = 24, execute_pct = 25 }).action, "execute",
        "rule 2: a custom threshold applies")
    eq(evaluate({ target_health_pct = 10, execute_pct = NONE }).action, "execute",
        "rule 2: a missing threshold falls back to 20")
    eq(evaluate({ target_health_pct = NONE }).action, "hs",
        "rule 2: unknown health skips the Execute branch")
    eq(evaluate({ target_health_pct = 10, execute_remaining = 2 }).action, "hs",
        "rule 2: a real Execute cooldown withholds the prompt")
    eq(evaluate({ target_health_pct = 10, has_bloodsurge = true }).action, "execute",
        "rule 2 outranks the Bloodsurge proc")
end

-- The stance gates (rules 1 and 2): the sims register Overpower with a
-- Battle-stance requirement and Execute with Battle|Berserker, so a known
-- stance outside that set withholds the prompt. An unknown stance withholds
-- nothing (the legacy behaviour stays byte-identical).
do
    eq(evaluate({ overpower_remaining = 5, stance = "battle" }).action, "op",
        "stance gate: Overpower in Battle stance still prompts")
    eq(evaluate({ overpower_remaining = 5, stance = "berserker" }).action, "hs",
        "stance gate: Overpower in Berserker stance is withheld (the sim's Battle-only rule)")
    eq(evaluate({ overpower_remaining = 5, stance = "defensive" }).action, "hs",
        "stance gate: Overpower in Defensive stance is withheld")
    eq(evaluate({ overpower_remaining = 5, stance = NONE }).action, "op",
        "stance gate: an unknown stance withholds nothing")
    eq(evaluate({ target_health_pct = 10, stance = "battle" }).action, "execute",
        "stance gate: Execute in Battle stance still prompts")
    eq(evaluate({ target_health_pct = 10, stance = "berserker" }).action, "execute",
        "stance gate: Execute in Berserker stance still prompts (the sim allows both)")
    eq(evaluate({ target_health_pct = 10, stance = "defensive" }).action, "hs",
        "stance gate: Execute in Defensive stance is withheld")
    eq(evaluate({ target_health_pct = 10, stance = NONE }).action, "execute",
        "stance gate: an unknown stance withholds nothing")
    -- The gates themselves, as pure verdicts.
    eq(wg.stance_allows_op(nil), true, "stance gate: an unknown stance allows Overpower")
    eq(wg.stance_allows_op("battle"), true, "stance gate: Battle allows Overpower")
    eq(wg.stance_allows_op("berserker"), false, "stance gate: Berserker blocks Overpower")
    eq(wg.stance_allows_op("defensive"), false, "stance gate: Defensive blocks Overpower")
    eq(wg.stance_allows_execute(nil), true, "stance gate: an unknown stance allows Execute")
    eq(wg.stance_allows_execute("battle"), true, "stance gate: Battle allows Execute")
    eq(wg.stance_allows_execute("berserker"), true, "stance gate: Berserker allows Execute")
    eq(wg.stance_allows_execute("defensive"), false, "stance gate: Defensive blocks Execute")
    eq(wg.stance_allows_execute("nonsense"), false,
        "stance gate: an unknown stance key is not Battle or Berserker")
    eq(wg.STANCE_BATTLE, "battle", "the stance key for Battle is battle")
    eq(wg.STANCE_BERSERKER, "berserker", "the stance key for Berserker is berserker")
    eq(wg.STANCE_DEFENSIVE, "defensive", "the stance key for Defensive is defensive")
end

-- Rule 3: the Bloodsurge proc.
do
    eq(evaluate({ has_bloodsurge = true }).action, "slam",
        "rule 3: a Bloodsurge proc -> Slam")
    eq(evaluate({ has_bloodsurge = true, hs_queued = true }).action, "slam",
        "rule 3 outranks the queued on-next-attack ride")
    eq(evaluate({ has_bloodsurge = true, rage = NONE }).action, "slam",
        "rule 3 outranks the rage rules")
    eq(evaluate({ has_bloodsurge = true, slam_casting = true }).action, "hs",
        "rule 3: a Slam already in flight falls through to the HS fallback")
    eq(evaluate({ has_bloodsurge = false, slam_casting = true }).action, "hs",
        "rule 3: slam_casting alone changes nothing")
end

-- Rule 4: the queued ride.
do
    eq(evaluate({ hs_queued = true }).action, nil, "rule 4: a queued HS is not re-suggested")
    eq(evaluate({ hs_queued = true }).hold, true, "rule 4: a queued HS holds")
    eq(evaluate({ hs_queued = true }).hold_text, "RIDE", "rule 4: the queued HS reads RIDE")
    eq(evaluate({ cleave_queued = true }).hold, true, "rule 4: a queued Cleave holds too")
    eq(evaluate({ cleave_queued = true }).hold_text, "RIDE", "rule 4: the queued Cleave reads RIDE")
    eq(evaluate({ hs_queued = true, overpower_remaining = 5 }).action, "op",
        "rule 1 outranks the queued ride")
end

-- Rule 7: Heroic Strike, the insufficient-rage hold and the window boundary.
do
    eq(evaluate({ rage = 15, hs_cost = 15 }).action, "hs",
        "rule 7 boundary: rage exactly equal to the cost is sufficient")
    eq(evaluate({ rage = 14.99, hs_cost = 15 }).action, nil,
        "rule 7 boundary: rage just below the cost is not")
    eq(evaluate({ rage = 14.99, hs_cost = 15 }).hold_text, "HOLD",
        "rule 7: the known shortfall reads HOLD")
    eq(evaluate({ rage = 10 }).hold, true, "rule 7: insufficient rage holds")
    eq(evaluate({ rage = 10 }).action, nil, "rule 7: insufficient rage shows no action")
    eq(evaluate({ rage = 50, hs_cost = NONE, insufficient_rage = true }).hold_text, "HOLD",
        "rule 7: with no cost data the module's shortfall flag still reads HOLD")
    eq(evaluate({ rage = 50, hs_cost = NONE, insufficient_rage = false }).action, nil,
        "rule 7: an unprovable sufficiency withholds the prompt")
    eq(evaluate({ rage = NONE }).action, nil, "rule 7: unknown rage shows no prompt")
    eq(evaluate({ rage = NONE, insufficient_rage = true }).hold, false,
        "rule 7: the flag alone (rage unknown) cannot hold")
    eq(evaluate({ swing_remaining = 0.05 }).action, nil,
        "rule 7 boundary: inside the reaction half-step the prompt is withheld")
    eq(evaluate({ swing_remaining = 0.06 }).action, "hs",
        "rule 7 boundary: just outside it the prompt returns")
    eq(evaluate({ swing_remaining = 0 }).action, nil,
        "rule 7: a landed swing withholds the prompt")
    eq(evaluate({ swing_remaining = NONE }).action, nil,
        "rule 7: an unknown swing withholds the prompt")
    eq(evaluate({ reaction = 1.0, swing_remaining = 0.4 }).action, nil,
        "rule 7: a custom reaction widens the withheld margin")
    eq(evaluate({ reaction = 1.0, swing_remaining = 0.6 }).action, "hs",
        "rule 7: and the prompt returns just outside it")
    eq(evaluate({ gcd_remaining = 1.5 }).action, "hs",
        "rule 7: HS is off the GCD, so a running GCD never closes the window")
end

-- Rules 5/6: the TBC Bloodthirst / Whirlwind core (a known reading is required).
do
    eq(evaluate({ bt_remaining = 0 }).action, "bt",
        "rule 5: a ready Bloodthirst with a reader -> BT")
    eq(evaluate({ bt_remaining = -0.5 }).action, "bt",
        "rule 5: a just-expired BT reads as ready")
    eq(evaluate({ bt_remaining = 0.001 }).action, "hs",
        "rule 5 boundary: BT still on cooldown falls through to HS")
    eq(evaluate({ bt_remaining = NONE }).action, "hs",
        "rule 5: no BT reader (non-TBC) keeps the legacy path")
    eq(evaluate({ ww_remaining = 0 }).action, "ww",
        "rule 6: a ready Whirlwind with a reader -> WW")
    eq(evaluate({ ww_remaining = 2 }).action, "hs",
        "rule 6 boundary: WW still on cooldown falls through to HS")
    eq(evaluate({ ww_remaining = NONE }).action, "hs",
        "rule 6: no WW reader (non-TBC) keeps the legacy path")
    eq(evaluate({ bt_remaining = 0, ww_remaining = 0 }).action, "bt",
        "rule 5 outranks rule 6: BT before WW")
    eq(evaluate({ bt_remaining = 3, ww_remaining = 0 }).action, "ww",
        "rule 6 fires while BT cools down")
    eq(evaluate({ bt_remaining = 1.0, ww_remaining = 0 }).action, nil,
        "rule 6: the WW delay withholds while BT lands inside 1.5 s")
    eq(evaluate({ bt_remaining = 1.0, ww_remaining = 0 }).hold, false,
        "rule 6: the delay withhold waits silently (the HS reservation agrees)")
    eq(evaluate({ bt_remaining = 1.5, ww_remaining = 0 }).action, "ww",
        "rule 6 boundary: BT exactly 1.5 s out still fires (the sim Delay Check)")
    eq(evaluate({ bt_remaining = 1.6, ww_remaining = 0 }).action, "ww",
        "rule 6: BT outside the delay window fires WW")
    eq(evaluate({ bt_remaining = 0 / 0, ww_remaining = 0 }).action, "ww",
        "rule 6: a NaN BT reads as unknown and never withholds")
    eq(evaluate({ bt_remaining = 0, overpower_remaining = 5 }).action, "op",
        "rule 1 outranks the TBC core")
    eq(evaluate({ bt_remaining = 0, has_bloodsurge = true }).action, "slam",
        "rule 3 outranks the TBC core")
    eq(evaluate({ bt_remaining = 0, hs_queued = true }).action, nil,
        "rule 4 outranks the TBC core: a queued HS is not re-suggested")
    eq(evaluate({ bt_remaining = 0, hs_queued = true }).hold_text, "RIDE",
        "rule 4 outranks the TBC core: the queued HS still reads RIDE")
    eq(evaluate({ bt_remaining = 0 / 0 }).action, "hs",
        "a NaN BT reading never prompts")
end

-- Rule 2 reservation: Execute never at the core's expense.
do
    eq(evaluate({ target_health_pct = 10, bt_remaining = 0, rage = 100 }).action, "bt",
        "rule 2: a ready BT claims the GCD over Execute")
    eq(evaluate({ target_health_pct = 10, ww_remaining = 0, rage = 100 }).action, "ww",
        "rule 2: a ready WW claims the GCD over Execute")
    eq(evaluate({ target_health_pct = 10, bt_remaining = 1.0, bt_cost = 30,
        rage = 100 }).action, "execute",
        "rule 2: a soon BT with rage to cover both still allows Execute")
    eq(evaluate({ target_health_pct = 10, bt_remaining = 1.0, bt_cost = 30,
        rage = 40 }).action, nil,
        "rule 2: a soon BT without rage for both withholds Execute (and HS too)")
    eq(evaluate({ target_health_pct = 10, bt_remaining = 1.0, bt_cost = NONE,
        rage = 40 }).action, nil,
        "rule 2: an unknown BT cost falls back to the 30-rage default")
    eq(evaluate({ target_health_pct = 10, bt_remaining = 5, bt_cost = 30,
        rage = 40 }).action, "execute",
        "rule 2: a BT outside the reserve window does not gate Execute")
    eq(evaluate({ target_health_pct = 10, bt_remaining = NONE,
        ww_remaining = NONE }).action, "execute",
        "rule 2: no readers (non-TBC) keeps the legacy Execute")
end

-- Rule 7 guard: the HS floor and the core reservation withhold silently.
do
    eq(evaluate({ rage = 49, hs_cost = 15, hs_rage_floor = 50 }).action, nil,
        "rule 7: a 50 floor withholds HS below 50 rage")
    eq(evaluate({ rage = 49, hs_cost = 15, hs_rage_floor = 50 }).hold, false,
        "rule 7: the floor withhold is silent (pooled, not missing)")
    eq(evaluate({ rage = 50, hs_cost = 15, hs_rage_floor = 50 }).action, "hs",
        "rule 7 boundary: rage exactly at the floor still dumps")
    eq(evaluate({ rage = 60, hs_cost = 15, bt_remaining = 1.0,
        bt_cost = 30 }).action, "hs",
        "rule 7: a soon BT with rage to cover both still allows HS")
    eq(evaluate({ rage = 40, hs_cost = 15, bt_remaining = 1.0,
        bt_cost = 30 }).action, nil,
        "rule 7: a soon BT without rage for both withholds HS")
    eq(evaluate({ rage = 40, hs_cost = 15, bt_remaining = 1.0,
        bt_cost = 30 }).hold, false,
        "rule 7: the reservation withhold is silent too")
    eq(evaluate({ rage = 39, hs_cost = 15, ww_remaining = 1.0,
        ww_cost = 25 }).action, nil,
        "rule 7: a soon WW without rage for both withholds HS (39 - 15 < 25)")
    eq(evaluate({ rage = 40, hs_cost = 15, bt_remaining = 5,
        ww_remaining = 6 }).action, "hs",
        "rule 7: core cooldowns outside the window do not guard HS")
    eq(evaluate({ rage = 10, hs_cost = 15, hs_rage_floor = 50 }).hold_text, "HOLD",
        "rule 7: a real shortfall still reads HOLD under the floor")
end

-- Rule 7 guard: the APL's execute-phase clause on the dump. The TBC and Forever
-- APLs gate their Heroic Strike row on NOT being inside the execute phase
-- (tbc-new fury.apl.json [18]; forever arms.apl.json [27]); the Era APL's row
-- explicitly allows the dump inside the phase, and the SoD / WotLK APLs carry
-- no such clause, so the provider arms the gate only on those two families.
do
    check(type(wg.dump_blocked_in_execute) == "function",
        "execute-phase gate: the pure helper is exported")
    eq(wg.dump_blocked_in_execute({ execute_phase_dump_gate = true,
        target_health_pct = 10 }, 20), true,
        "execute-phase gate: an armed gate and a sub-threshold target block the dump")
    eq(wg.dump_blocked_in_execute({ execute_phase_dump_gate = true,
        target_health_pct = 20 }, 20), false,
        "execute-phase gate: exactly the threshold is not inside the phase")
    eq(wg.dump_blocked_in_execute({ execute_phase_dump_gate = true,
        target_health_pct = 100 }, 20), false,
        "execute-phase gate: a healthy target is not inside the phase")
    eq(wg.dump_blocked_in_execute({ target_health_pct = 10 }, 20), false,
        "execute-phase gate: an unarmed gate (every other family) never blocks")
    eq(wg.dump_blocked_in_execute({ execute_phase_dump_gate = true,
        target_health_pct = NONE }, 20), false,
        "execute-phase gate: an unknown target health is not a phase")
    eq(wg.dump_blocked_in_execute({ execute_phase_dump_gate = true,
        target_health_pct = 0 / 0 }, 20), false,
        "execute-phase gate: a NaN health is not a phase")
    eq(wg.dump_blocked_in_execute(nil, 20), false,
        "execute-phase gate: no inputs never block")
    eq(wg.dump_blocked_in_execute({ execute_phase_dump_gate = true,
        target_health_pct = 10 }, NONE), false,
        "execute-phase gate: an unknown threshold is not a phase")
    -- The rule-7 integration: inside the phase the dump is not asked for. The
    -- Execute row is put on cooldown so the dump would be the fallback.
    eq(evaluate({ target_health_pct = 10, execute_remaining = 5 }).action, "hs",
        "execute-phase gate: without the gate the dump still fires in the phase")
    eq(evaluate({ execute_phase_dump_gate = true, target_health_pct = 10,
        execute_remaining = 5 }).action, nil,
        "execute-phase gate: with the gate the dump is withheld in the phase")
    eq(evaluate({ execute_phase_dump_gate = true, target_health_pct = 10,
        execute_remaining = 5 }).hold, false,
        "execute-phase gate: the phase withhold is silent (the phase is the APL's move)")
    eq(evaluate({ execute_phase_dump_gate = true, target_health_pct = 10,
        execute_remaining = 0, bt_remaining = 30 }).action, "execute",
        "execute-phase gate: the Execute row still owns the phase")
    eq(evaluate({ execute_phase_dump_gate = true, target_health_pct = 100,
        execute_remaining = 5 }).action, "hs",
        "execute-phase gate: outside the phase the dump keeps its legacy shape")
    eq(evaluate({ execute_phase_dump_gate = true, target_health_pct = NONE,
        execute_remaining = 5 }).action, "hs",
        "execute-phase gate: an unknown health is not a phase, so the dump stands")
end

-- Era rules (1.15.9 fury): BT/WW readers, the 40-rage floor (classic
-- dps_no_reck.apl.json gates HS/Cleave on currentRage >= 40), the 2.5 s window
-- (midpoint of the 2-3 s ground truth) and Execute spam with no reservation.
do
    local function era_evaluate(overrides)
        local base = {
            hs_rage_floor = 40, core_reserve_window = 2.5, execute_spam = true,
        }
        for k, v in pairs(overrides or {}) do
            if v == NONE then
                base[k] = nil
            else
                base[k] = v
            end
        end
        return evaluate(base)
    end
    eq(era_evaluate({ bt_remaining = 0 }).action, "bt",
        "era: a ready Bloodthirst with a reader -> BT")
    eq(era_evaluate({ bt_remaining = 3, ww_remaining = 0 }).action, "ww",
        "era: WW fires while BT cools down")
    eq(era_evaluate({ bt_remaining = 0, ww_remaining = 0 }).action, "bt",
        "era: BT outranks WW")
    eq(era_evaluate({ bt_remaining = NONE, ww_remaining = NONE }).action, "hs",
        "era: no readers keeps the legacy HS fallback")
    eq(era_evaluate({ rage = 39, hs_cost = 15 }).action, nil,
        "era: the 40-rage floor withholds HS at 39")
    eq(era_evaluate({ rage = 39, hs_cost = 15 }).hold, false,
        "era: the floor withhold is silent")
    eq(era_evaluate({ rage = 40, hs_cost = 15 }).action, "hs",
        "era boundary: rage exactly at 40 still dumps")
    eq(era_evaluate({ rage = 45, hs_cost = 15 }).action, "hs",
        "era: rage above the floor dumps")
    eq(era_evaluate({ rage = 40, hs_cost = 15, bt_remaining = 2.0,
        bt_cost = 30 }).action, nil,
        "era: a BT in 2.0 s without rage for both withholds HS (40 - 15 < 30)")
    eq(era_evaluate({ rage = 60, hs_cost = 15, bt_remaining = 2.0,
        bt_cost = 30 }).action, "hs",
        "era: a BT in 2.0 s with rage to cover both still allows HS")
    eq(era_evaluate({ rage = 40, hs_cost = 15, bt_remaining = 2.6,
        bt_cost = 30, ww_remaining = 6 }).action, "hs",
        "era: a BT at 2.6 s (outside the 2.5 s window) does not guard HS")
    eq(era_evaluate({ rage = 40, hs_cost = 15, bt_remaining = 2.5,
        bt_cost = 30 }).action, nil,
        "era boundary: a BT at exactly 2.5 s still guards HS")
    eq(era_evaluate({ target_health_pct = 10, bt_remaining = 0,
        rage = 100 }).action, "execute",
        "era: Execute spams even with BT ready (no TBC reservation)")
    eq(era_evaluate({ target_health_pct = 10, bt_remaining = 1.0, bt_cost = 30,
        rage = 40 }).action, "execute",
        "era: Execute spams even when BT lands soon with rage short")
    eq(era_evaluate({ target_health_pct = 10, ww_remaining = 0,
        rage = 100 }).action, "execute",
        "era: Execute spams even with WW ready")
    eq(era_evaluate({ overpower_remaining = 5, bt_remaining = 0 }).action, "op",
        "era: an active OP window outranks BT")
end

-- Branch helper with its own defaults (NOT the shared inp() above: a NONE
-- override must stick as nil instead of being re-defaulted). Shared by the
-- fury / arms / SoD blocks below.
local function branch_evaluate(extra, overrides)
    local t = {
        speed = 3.0, swing_remaining = 2.0, gcd_remaining = 0,
        rage = 50, hs_cost = 15, cleave_cost = 20,
        hs_queued = false, cleave_queued = false, insufficient_rage = false,
        has_bloodsurge = false, slam_casting = false,
        target_health_pct = 100, execute_pct = 20,
        op_remaining = 0, execute_remaining = 0, slam_remaining = 0,
        hs_remaining = 0, cleave_remaining = 0,
    }
    for k, v in pairs(extra or {}) do t[k] = v end
    for k, v in pairs(overrides or {}) do
        if v == NONE then
            t[k] = nil
        else
            t[k] = v
        end
    end
    local out = {}
    local ret = wg.evaluate(t, out)
    eq(ret, out, "branch evaluate returns the caller's out table")
    return out
end

-- Wrath fury rules (3.3.5 fury: BT > WW > Slam-proc (delay-gated) > demoted
-- Execute > HS dump; floor 50, 1.5 s default window).
do
    local function fury_evaluate(overrides)
        return branch_evaluate({ hs_rage_floor = 50, wrath_fury = true },
            overrides)
    end
    eq(fury_evaluate({ bt_remaining = 0, ww_remaining = 5 }).action, "bt",
        "fury: a ready Bloodthirst with a reader -> BT")
    eq(fury_evaluate({ bt_remaining = 3, ww_remaining = 0 }).action, "ww",
        "fury: WW fires while BT cools down")
    eq(fury_evaluate({ bt_remaining = 0, ww_remaining = 0 }).action, "bt",
        "fury: BT outranks WW")
    eq(fury_evaluate({ bt_remaining = NONE, ww_remaining = NONE }).action, "hs",
        "fury: no readers keeps the legacy HS fallback")
    eq(fury_evaluate({ has_bloodsurge = true, bt_remaining = 3,
        ww_remaining = 5 }).action, "slam",
        "fury: a Bloodsurge proc fires with the core cooling")
    eq(fury_evaluate({ has_bloodsurge = true, bt_remaining = 0,
        ww_remaining = 5 }).action, "bt",
        "fury: the delay gate withholds Slam while BT is ready")
    eq(fury_evaluate({ has_bloodsurge = true, bt_remaining = 5,
        ww_remaining = 0 }).action, "ww",
        "fury: the delay gate withholds Slam while WW is ready")
    eq(fury_evaluate({ has_bloodsurge = true, hs_queued = true,
        bt_remaining = 3, ww_remaining = 5 }).action, "slam",
        "fury: Slam outranks the queued ride (like the base rule)")
    eq(fury_evaluate({ target_health_pct = 10, bt_remaining = 0,
        rage = 100 }).action, "bt",
        "fury: BT claims the GCD in Execute range (demoted Execute)")
    eq(fury_evaluate({ target_health_pct = 10, bt_remaining = 3,
        ww_remaining = 5, rage = 100 }).action, "execute",
        "fury: the demoted Execute fires with the core cooling and rage to spare")
    eq(fury_evaluate({ target_health_pct = 10, bt_remaining = 3,
        ww_remaining = 5, rage = 40 }).action, nil,
        "fury: the demoted Execute withholds below the 50 floor (and HS too)")
    eq(fury_evaluate({ target_health_pct = 10, bt_remaining = 1.0, bt_cost = 30,
        rage = 40 }).action, nil,
        "fury: the demoted Execute withholds when BT lands with rage short")
    eq(fury_evaluate({ target_health_pct = 10, bt_remaining = 5, bt_cost = 30,
        rage = 60 }).action, "execute",
        "fury: a BT outside the reserve window does not gate the demoted Execute")
    eq(fury_evaluate({ target_health_pct = 10, bt_remaining = NONE,
        ww_remaining = NONE, rage = 100 }).action, "execute",
        "fury: no readers still demotes (never at the legacy rule-2 spot)")
    eq(fury_evaluate({ rage = 49, hs_cost = 15 }).action, nil,
        "fury: the 50-rage floor withholds HS at 49")
    eq(fury_evaluate({ rage = 50, hs_cost = 15 }).action, "hs",
        "fury boundary: rage exactly at 50 still dumps")
    eq(fury_evaluate({ overpower_remaining = 5, bt_remaining = 0 }).action, "op",
        "fury: an active OP window outranks BT")
end

-- Wrath arms rules (Rend upkeep > SD/health Execute > OP-on-TfB > Bladestorm >
-- MS > HS dump; no BT/WW/Slam prompts).
do
    local function arms_evaluate(overrides)
        return branch_evaluate({ wrath_arms = true }, overrides)
    end
    eq(arms_evaluate({ rend_remaining = NONE }).action, "rend",
        "arms: a missing Rend prompts Rend")
    eq(arms_evaluate({ rend_remaining = 3 }).action, "rend",
        "arms boundary: Rend at exactly the 3 s refresh prompts")
    eq(arms_evaluate({ rend_remaining = 3.1, target_health_pct = 100,
        ms_remaining = 5 }).action, "hs",
        "arms: a healthy Rend falls through past MS to HS")
    eq(arms_evaluate({ rend_remaining = 0 / 0 }).action, "hs",
        "arms: a NaN Rend falls through to the HS dump")
    eq(arms_evaluate({ rend_remaining = 10, sudden_death = true,
        overpower_remaining = 5 }).action, "execute",
        "arms: SD-Execute outranks the OP window")
    eq(arms_evaluate({ rend_remaining = 10, sudden_death = true,
        target_health_pct = 100 }).action, "execute",
        "arms: SD-Execute bypasses the health gate")
    eq(arms_evaluate({ rend_remaining = 10, target_health_pct = 10,
        overpower_remaining = 5 }).action, "execute",
        "arms: sub-20 % Execute outranks the OP window")
    eq(arms_evaluate({ rend_remaining = 10, tfb = true }).action, "op",
        "arms: TfB prompts OP with no dodge window")
    eq(arms_evaluate({ rend_remaining = 10,
        overpower_remaining = 5 }).action, "op",
        "arms: the dodge window still prompts OP")
    eq(arms_evaluate({ rend_remaining = 10, ms_remaining = 5,
        bladestorm_remaining = 5, bladestorm_known = true,
        rage = NONE }).action, nil,
        "arms: no proc, MS cooling and unknown rage shows no prompt")
    eq(arms_evaluate({ rend_remaining = 10, ms_remaining = 0,
        bladestorm_remaining = 5, bladestorm_known = true }).action, "ms",
        "arms: a ready Mortal Strike prompts MS")
    eq(arms_evaluate({ rend_remaining = 10, ms_remaining = 0,
        bladestorm_remaining = 0, bladestorm_known = true }).action,
        "bladestorm", "arms: Bladestorm outranks MS")
    eq(arms_evaluate({ rend_remaining = 10, ms_remaining = 0,
        bladestorm_remaining = 0 }).action, "ms",
        "arms: an untalented Bladestorm never prompts")
    eq(arms_evaluate({ rend_remaining = 10, ms_remaining = NONE,
        bladestorm_remaining = NONE }).action, "hs",
        "arms: unknown cooldowns fall through to the HS dump (known-reading rule)")
    eq(arms_evaluate({ rend_remaining = 10, bt_remaining = 0,
        ww_remaining = 0 }).action, nil,
        "arms: ready BT/WW readers never prompt on arms")
    eq(arms_evaluate({ rend_remaining = 10, has_bloodsurge = true }).action,
        "hs", "arms: a Bloodsurge proc never prompts Slam on arms (HS covers it)")
    eq(arms_evaluate({ rend_remaining = 10, hs_queued = true }).hold_text,
        "RIDE", "arms: a queued HS still reads RIDE")
end

-- SoD rules (pool >60; SD dump at any health; Slam on Blood Surge; BT > WW >
-- Raging Blow > HS dump; no OP prompts).
do
    local function sod_evaluate(overrides)
        return branch_evaluate(
            { sod = true, execute_spam = true, hs_rage_floor = 60 }, overrides)
    end
    eq(sod_evaluate({ sudden_death = true, target_health_pct = 100,
        overpower_remaining = 5 }).action, "execute",
        "sod: SD-Execute dumps at any health and never prompts OP")
    eq(sod_evaluate({ sudden_death = true, target_health_pct = 100,
        bt_remaining = 0, ww_remaining = 0, rage = 100 }).action, "execute",
        "sod: SD-Execute outranks the ready core")
    eq(sod_evaluate({ target_health_pct = 10, bt_remaining = 0,
        rage = 100 }).action, "execute",
        "sod: sub-20 % Execute spams over a ready BT")
    eq(sod_evaluate({ has_bloodsurge = true, bt_remaining = 3,
        ww_remaining = 4 }).action, "slam",
        "sod: Slam fires on Blood Surge with the core cooling")
    eq(sod_evaluate({ bt_remaining = 0 }).action, "bt",
        "sod: a ready Bloodthirst -> BT")
    eq(sod_evaluate({ bt_remaining = 3, ww_remaining = 0 }).action, "ww",
        "sod: WW fires while BT cools down")
    eq(sod_evaluate({ bt_remaining = 3, ww_remaining = 4,
        raging_blow_remaining = 0 }).action, "raging_blow",
        "sod: Raging Blow fills after WW")
    eq(sod_evaluate({ bt_remaining = 3, ww_remaining = 4,
        raging_blow_remaining = 2 }).action, nil,
        "sod: a cooling Raging Blow withholds (HS floor next)")
    eq(sod_evaluate({ rage = 59, hs_cost = 15, bt_remaining = 3,
        ww_remaining = 4, raging_blow_remaining = 2 }).action, nil,
        "sod: the 60-rage pool floor withholds HS at 59")
    eq(sod_evaluate({ rage = 59, hs_cost = 15, bt_remaining = 3,
        ww_remaining = 4, raging_blow_remaining = 2 }).hold, false,
        "sod: the pool withhold is silent")
    eq(sod_evaluate({ rage = 60, hs_cost = 15, bt_remaining = 3,
        ww_remaining = 4, raging_blow_remaining = 2 }).action, "hs",
        "sod boundary: rage exactly at 60 still dumps")
end

-- Victory Rush (Forever execute-phase cue, UNCONFIRMED id): Execute at any
-- health, still behind the OP window and before Slam/BT/WW; nil (every other
-- family) keeps the legacy health gate byte-identically.
do
    eq(evaluate({ victory_rush = true, target_health_pct = 100 }).action, "execute",
        "victory rush: ready at full health -> Execute")
    eq(evaluate({ victory_rush = true, target_health_pct = NONE }).action, "execute",
        "victory rush: bypasses the unknown-health gate too")
    eq(evaluate({ victory_rush = true, target_health_pct = 100,
        overpower_remaining = 5 }).action, "op",
        "victory rush: the live OP window still outranks it")
    eq(evaluate({ victory_rush = true, target_health_pct = 100,
        has_bloodsurge = true }).action, "execute",
        "victory rush: Execute still outranks the Bloodsurge proc")
    eq(evaluate({ victory_rush = true, target_health_pct = 100,
        execute_remaining = 2 }).action, "hs",
        "victory rush: a real Execute cooldown withholds the prompt")
    eq(evaluate({ victory_rush = true, target_health_pct = 100,
        hs_queued = true }).action, "execute",
        "victory rush: a queued HS does not steal the Execute prompt")
    eq(evaluate({ victory_rush = true, target_health_pct = 100,
        hs_queued = true }).hold, false,
        "victory rush: no cue flag means no CANCEL overlay")
    eq(evaluate({ victory_rush = false, target_health_pct = 100 }).action, "hs",
        "victory rush: false keeps the legacy health gate")
end

-- HS-cancel cue (TBC micro): rule-2 Execute with HS/Cleave queued reads
-- CANCEL instead of riding; without the provider flag the legacy shape holds.
do
    local out = evaluate({ target_health_pct = 10, hs_queued = true,
        hs_cancel_cue = true })
    eq(out.action, "execute", "hs-cancel: Execute range with HS queued -> Execute")
    eq(out.hold, true, "hs-cancel: the queued spend reads as a hold")
    eq(out.hold_text, "CANCEL", "hs-cancel: the overlay reads CANCEL")
    out = evaluate({ target_health_pct = 10, cleave_queued = true,
        hs_cancel_cue = true })
    eq(out.action, "execute", "hs-cancel: a queued Cleave cancels the same way")
    eq(out.hold_text, "CANCEL", "hs-cancel: the Cleave overlay reads CANCEL too")
    out = evaluate({ target_health_pct = 10, hs_queued = true })
    eq(out.action, "execute", "no flag: Execute range with HS queued still -> Execute")
    eq(out.hold, false, "no flag: no hold (legacy shape)")
    eq(out.hold_text, nil, "no flag: no hold text (legacy shape)")
    out = evaluate({ target_health_pct = 10, hs_cancel_cue = true })
    eq(out.action, "execute", "hs-cancel: nothing queued -> Execute with no overlay")
    eq(out.hold, false, "hs-cancel: nothing queued -> no hold")
    eq(out.hold_text, nil, "hs-cancel: nothing queued -> no hold text")
    out = evaluate({ target_health_pct = 100, hs_queued = true, hs_cancel_cue = true })
    eq(out.action, nil, "hs-cancel: outside Execute range the queued HS still rides")
    eq(out.hold_text, "RIDE", "hs-cancel: outside Execute range the overlay reads RIDE")
    out = evaluate({ target_health_pct = 10, hs_queued = true, hs_cancel_cue = true,
        bt_remaining = 0, rage = 100 })
    eq(out.action, nil, "hs-cancel: a ready BT still claims the GCD over Execute")
    eq(out.hold_text, "RIDE", "hs-cancel: the withheld Execute keeps the queued RIDE")
end

-- Tactical Mastery stance-swap cap (TBC micro, pure): a swap keeps at most 25
-- rage with the talent, nothing without it. No rule consumes this yet (the
-- stance-event wiring is deferred); it pins the 25-cap maths for that wiring.
do
    eq(wg.TACTICAL_MASTERY_RAGE_CAP, 25, "the TM cap is 25")
    eq(wg.rage_after_stance_swap(100, true), 25, "TM: 100 rage swaps down to 25")
    eq(wg.rage_after_stance_swap(25, true), 25, "TM boundary: exactly 25 keeps all")
    eq(wg.rage_after_stance_swap(10, true), 10, "TM: 10 rage keeps all")
    eq(wg.rage_after_stance_swap(0, true), 0, "TM: 0 rage keeps 0")
    eq(wg.rage_after_stance_swap(100, false), 0, "no TM: the swap dumps all rage")
    eq(wg.rage_after_stance_swap(100, nil), 0, "unknown talent reads as no TM")
    eq(wg.rage_after_stance_swap(-5, true), 0, "negative rage floors at 0")
    eq(wg.rage_after_stance_swap(nil, true), nil, "unknown rage answers nil")
    eq(wg.rage_after_stance_swap(0 / 0, true), nil, "NaN rage answers nil")
end

-- Follow-up engine groundwork (warrior-rotfix journal 2026-10-19): Sunder
-- upkeep, Rend upkeep outside arms, the SoD OP stance-dance gate and the
-- Hamstring weave verdict are pure helpers with no engine rule yet (no slot
-- names them - six-slot contract full). The pins below plus the
-- no-visible-change pins after them; the rule + slot + options wiring is filed.
do
    eq(wg.SUNDER_STACKS_MAX, 5, "the Sunder stack cap is 5")
    eq(wg.SUNDER_REFRESH_DEFAULT, 10, "the Sunder refresh window is 10 s")
    eq(wg.should_refresh_sunder(4, 25), true, "sunder: below cap re-stacks (window ignored)")
    eq(wg.should_refresh_sunder(0, 25), true, "sunder: zero stacks re-stacks")
    eq(wg.should_refresh_sunder(5, 25), false, "sunder: capped + fresh never refreshes")
    eq(wg.should_refresh_sunder(5, 10), true, "sunder boundary: at cap inside the window refreshes")
    eq(wg.should_refresh_sunder(5, 10.1), false, "sunder boundary: just outside it does not")
    eq(wg.should_refresh_sunder(nil, 4), true, "sunder: unknown stacks with a short window refreshes")
    eq(wg.should_refresh_sunder(nil, 25), false, "sunder: unknown stacks with a fresh window does not")
    eq(wg.should_refresh_sunder(nil, nil), false, "sunder: unknown hides (both halves unknown)")
    eq(wg.should_refresh_sunder(5, 0 / 0), false, "sunder: NaN remaining hides")
    eq(wg.should_refresh_sunder(0 / 0, nil), false, "sunder: NaN stacks with no window hides")
    eq(wg.should_refresh_sunder(5, 12, 15), true, "sunder: a custom window applies")
    eq(wg.should_refresh_sunder(5, 9, "wide"), true, "sunder: a bad window falls back to 10")

    eq(wg.SOD_OP_STANCE_AURA_ID, 426969, "the SoD gate aura id (UNCONFIRMED)")
    eq(wg.should_stance_dance_op(true, 1, true), true, "stance-dance: aura + stance + OP ready")
    eq(wg.should_stance_dance_op(true, 3, true), true, "stance-dance: any non-zero form (map UNCONFIRMED)")
    eq(wg.should_stance_dance_op(false, 1, true), false, "stance-dance: no aura never dances")
    eq(wg.should_stance_dance_op(nil, 1, true), false, "stance-dance: unknown aura never dances")
    eq(wg.should_stance_dance_op(true, 0, true), false, "stance-dance: form 0 is no stance")
    eq(wg.should_stance_dance_op(true, nil, true), false, "stance-dance: unknown form hides")
    eq(wg.should_stance_dance_op(true, 0 / 0, true), false, "stance-dance: NaN form hides")
    eq(wg.should_stance_dance_op(true, 1, false), false, "stance-dance: OP not ready never dances")
    eq(wg.should_stance_dance_op(true, 1, nil), false, "stance-dance: unknown readiness never dances")

    eq(wg.HAMSTRING_RAGE_THRESHOLD_ERA, 80, "the Era weave threshold is 80 (sim-cited)")
    eq(wg.should_weave_hamstring(81, true, 80), true, "hamstring: rage above the threshold weaves")
    eq(wg.should_weave_hamstring(80, true, 80), false, "hamstring boundary: exactly at it does not")
    eq(wg.should_weave_hamstring(81, true, nil), false, "hamstring: no threshold never weaves")
    eq(wg.should_weave_hamstring(81, true, 0 / 0), false, "hamstring: NaN threshold never weaves")
    eq(wg.should_weave_hamstring(81, false, 80), false, "hamstring: unlearned never weaves")
    eq(wg.should_weave_hamstring(81, nil, 80), false, "hamstring: unknown knowledge never weaves")
    eq(wg.should_weave_hamstring(nil, true, 80), false, "hamstring: unknown rage never weaves")
    eq(wg.should_weave_hamstring(0 / 0, true, 80), false, "hamstring: NaN rage never weaves")

    eq(wg.should_maintain_rend_outside_arms(1, nil), false, "rend: disabled never prompts")
    eq(wg.should_maintain_rend_outside_arms(1, false), false, "rend: false never prompts")
    eq(wg.should_maintain_rend_outside_arms(nil, true), true, "rend: missing applies once enabled")
    eq(wg.should_maintain_rend_outside_arms(3, true), true, "rend boundary: at exactly 3 s applies")
    eq(wg.should_maintain_rend_outside_arms(3.1, true), false, "rend boundary: just past it does not")
    eq(wg.should_maintain_rend_outside_arms(0 / 0, true), false, "rend: NaN hides (missing reads nil, not NaN)")
    eq(wg.should_maintain_rend_outside_arms(2, true, 5), true, "rend: a custom window applies")
    eq(wg.should_maintain_rend_outside_arms(4, true, "wide"), false, "rend: a bad window falls back to 3")
end

-- Filed rules, now live (S/R/D/W): Sunder upkeep (rule S), Rend upkeep
-- outside arms (rule R, enabled-gated), the SoD stance-dance OP source (rule
-- D, aura + stance gated) and the Hamstring weave (rule W, threshold-gated)
-- prompt through the same engine. Dormant shapes (nil/unknown inputs - the
-- family gating lives in the gather) decide exactly like before; the HELD
-- floors + Victory Rush pins below hold.
do
    -- Rule S: Sunder upkeep fires with a live window, yields to procs,
    -- Execute range and a queued ride, outranks the core + HS dump.
    eq(evaluate({ sunder_stacks = 4, sunder_remaining = 25 }).action, "sunder",
        "S: below cap re-stacks (window ignored)")
    eq(evaluate({ sunder_stacks = 5, sunder_remaining = 9 }).action, "sunder",
        "S: at cap inside the window refreshes")
    eq(evaluate({ sunder_stacks = 5, sunder_remaining = 25 }).action, "hs",
        "S: capped + fresh falls through to the HS dump")
    eq(evaluate({ sunder_stacks = 2, sunder_remaining = 4,
        bt_remaining = 0 }).action, "sunder",
        "S: maintenance outranks a ready Bloodthirst")
    eq(evaluate({ sunder_stacks = 2, sunder_remaining = 4,
        bt_remaining = 0, ww_remaining = 0 }).action, "sunder",
        "S: maintenance outranks the ready core")
    eq(evaluate({ sunder_stacks = 2, sunder_remaining = 4,
        target_health_pct = 10 }).action, "execute",
        "S: Execute range still outranks maintenance")
    eq(evaluate({ sunder_stacks = 2, sunder_remaining = 4,
        overpower_remaining = 5 }).action, "op",
        "S: the OP window outranks maintenance")
    eq(evaluate({ sunder_stacks = 2, sunder_remaining = 4,
        has_bloodsurge = true }).action, "slam",
        "S: the Bloodsurge proc outranks maintenance")
    eq(evaluate({ sunder_stacks = 2, sunder_remaining = 4,
        hs_queued = true }).action, nil,
        "S: a queued HS rides instead of maintenance")
    eq(evaluate({ sunder_stacks = 2, sunder_remaining = 4,
        hs_queued = true }).hold_text, "RIDE",
        "S: the queued ride keeps its text over maintenance")
    eq(evaluate({ sunder_stacks = nil, sunder_remaining = nil,
        bt_remaining = 0 }).action, "bt",
        "S: unknown upkeep hides (the core fires)")

    -- Rule R: Rend upkeep outside arms fires once enabled, yields like S.
    eq(evaluate({ rend_remaining = nil,
        rend_upkeep_enabled = true }).action, "rend",
        "R: missing Rend applies once enabled")
    eq(evaluate({ rend_remaining = 2,
        rend_upkeep_enabled = true }).action, "rend",
        "R: inside the window applies")
    eq(evaluate({ rend_remaining = 10,
        rend_upkeep_enabled = true }).action, "hs",
        "R: a fresh Rend falls through to the HS dump")
    eq(evaluate({ rend_remaining = nil }).action, "hs",
        "R: no enable flag never prompts (Forever toggle filed)")
    eq(evaluate({ rend_remaining = nil,
        rend_upkeep_enabled = false }).action, "hs",
        "R: a false flag never prompts")
    eq(evaluate({ rend_remaining = 1, rend_upkeep_enabled = true,
        overpower_remaining = 5 }).action, "op",
        "R: the OP window outranks maintenance")
    eq(evaluate({ sunder_stacks = 2, sunder_remaining = 4, rend_remaining = 1,
        rend_upkeep_enabled = true }).action, "sunder",
        "S outranks R: armor first, then Rend")

    -- Rule D: the SoD stance-dance arm fires OP with aura + stance + ready.
    eq(branch_evaluate({ sod = true },
        { sod_stance_aura = true, stance_form = 1 }).action, "op",
        "D: aura + stance prompts OP on SoD")
    eq(branch_evaluate({ sod = true },
        { sod_stance_aura = true, stance_form = 3 }).action, "op",
        "D: any non-zero form reads as a stance (map UNCONFIRMED)")
    eq(branch_evaluate({ sod = true },
        { sod_stance_aura = true, stance_form = 1,
            op_remaining = 2, raging_blow_remaining = 2, bt_remaining = 3,
            ww_remaining = 4 }).action, "hs",
        "D: an OP cooldown withholds the dance (falls to HS)")
    eq(branch_evaluate({ sod = true },
        { stance_form = 1, raging_blow_remaining = 2, bt_remaining = 3,
            ww_remaining = 4 }).action, "hs",
        "D: unknown aura never dances")
    eq(branch_evaluate({ sod = true },
        { sod_stance_aura = true, raging_blow_remaining = 2,
            bt_remaining = 3, ww_remaining = 4 }).action, "hs",
        "D: unknown stance never dances")
    eq(branch_evaluate({ sod = true },
        { sod_stance_aura = true, stance_form = 0,
            raging_blow_remaining = 2, bt_remaining = 3,
            ww_remaining = 4 }).action, "hs",
        "D: form 0 is no stance")
    eq(branch_evaluate({ sod = true },
        { overpower_remaining = 5, raging_blow_remaining = 2,
            bt_remaining = 3, ww_remaining = 4 }).action, "hs",
        "D: the dodge window stays suppressed on SoD (no dodge source)")
    eq(branch_evaluate({ sod = true },
        { target_health_pct = 10,
            overpower_remaining = 5 }).action, "execute",
        "D: Execute range still prompts on SoD (suppressed OP never steals it)")

    -- Rule W: the Hamstring weave fires above the threshold with the filler
    -- known; below the core, above the HS dump.
    eq(branch_evaluate({}, { rage = 81, hamstring_known = true,
        hamstring_rage_threshold = 80 }).action, "hamstring",
        "W: rage above the threshold weaves")
    eq(branch_evaluate({}, { rage = 80, hamstring_known = true,
        hamstring_rage_threshold = 80 }).action, "hs",
        "W boundary: exactly at the threshold dumps HS instead")
    eq(branch_evaluate({}, { rage = 81, hamstring_known = true }).action, "hs",
        "W: no threshold never weaves")
    eq(branch_evaluate({}, { rage = 81,
        hamstring_rage_threshold = 80 }).action, "hs",
        "W: unknown knowledge never weaves")
    eq(branch_evaluate({}, { rage = 81, hamstring_known = true,
        hamstring_rage_threshold = 80, bt_remaining = 0 }).action, "bt",
        "W: the ready core outranks the weave")
    eq(branch_evaluate({}, { rage = 81, hamstring_known = true,
        hamstring_rage_threshold = 80, target_health_pct = 10,
        execute_spam = true }).action, "execute",
        "W: Execute spam outranks the weave")

    -- Dormant shapes decide exactly like before (the family gating lives in
    -- the gather: nil inputs never prompt, on any branch).
    eq(evaluate({}).action, "hs",
        "dormant: the bare baseline still dumps HS")
    eq(branch_evaluate({ wrath_arms = true, rend_remaining = 10 },
        {}).action, "hs",
        "dormant: arms with a healthy Rend still dumps HS")
    eq(branch_evaluate({ wrath_fury = true, hs_rage_floor = 50 },
        {}).action, "hs",
        "dormant: fury with no upkeep still dumps HS")
    eq(branch_evaluate({ sod = true, execute_spam = true, hs_rage_floor = 60 },
        { bt_remaining = 3, ww_remaining = 4,
            raging_blow_remaining = 2 }).action, nil,
        "dormant: SoD with no upkeep still withholds under the pool floor")

    -- HELD floors (warrior-rotfix journal 2026-10-19): Wrath 50 (no Wrath sim
    -- source) and SoD 60 (a design decision is owed, not a copy) stay put.
    eq(branch_evaluate({ wrath_fury = true, hs_rage_floor = 50 },
        { rage = 49, hs_cost = 15 }).action, nil,
        "HELD: the Wrath 50 floor withholds HS at 49")
    eq(branch_evaluate({ sod = true, execute_spam = true, hs_rage_floor = 60 },
        { rage = 59, hs_cost = 15, bt_remaining = 3,
            ww_remaining = 4, raging_blow_remaining = 2 }).action, nil,
        "HELD: the SoD 60 pool floor withholds HS at 59")
end

-- Slam safe-window verdict (brainstorm W4 band): clean when the cast lands
-- before the next swing, clash when the swing lands mid-cast, nil on unknown
-- clocks; Forever (no swing reset) always reads clean.
do
    eq(wg.slam_cast_safety(1.0, 2.0, true), "clean", "cast lands first -> clean")
    eq(wg.slam_cast_safety(1.5, 1.5, true), "clean", "boundary: together still lands clean")
    eq(wg.slam_cast_safety(0, 2.0, true), "clean", "a finished cast reads clean")
    eq(wg.slam_cast_safety(1.6, 1.5, true), "clash", "swing lands mid-cast -> clash")
    eq(wg.slam_cast_safety(1.6, 1.5, false), "clean", "Forever: no swing reset -> always clean")
    eq(wg.slam_cast_safety(9.9, 0.1, false), "clean", "Forever: clean even deep in the deadzone")
    eq(wg.slam_cast_safety(1.6, 1.5, nil), "clash", "nil resets keeps the classic assumption")
    eq(wg.slam_cast_safety(nil, 1.5, true), nil, "unknown cast answers nil")
    eq(wg.slam_cast_safety(1.0, nil, true), nil, "unknown swing answers nil")
    eq(wg.slam_cast_safety(0 / 0, 1.5, true), nil, "NaN cast answers nil")
    eq(wg.slam_cast_safety(1.0, 0 / 0, true), nil, "NaN swing answers nil")
end

-- Dual-wield desync verdict (competitor-gaps W1): pure next-landing
-- coincidence math. "clash" within the window (boundary inclusive),
-- "clean" outside it, nil on any unknown clock; the spark fraction places
-- the OH landing on the current MH swing, nil when unplaceable.
do
    eq(wg.DESYNC_ALERT_GAP, 0.3, "the desync window is the provisional 0.3 s")
    eq(wg.swing_sync_gap(2.0, 2.0), 0, "coincident landings: zero gap")
    eq(wg.swing_sync_gap(2.0, 2.25), 0.25, "the gap is the absolute landing distance")
    eq(wg.swing_sync_gap(2.25, 2.0), 0.25, "the gap is directionless")
    eq(wg.swing_sync_gap(nil, 2.0), nil, "an unknown MH clock answers nil")
    eq(wg.swing_sync_gap(2.0, nil), nil, "an unknown OH clock answers nil")
    eq(wg.swing_sync_gap(0 / 0, 2.0), nil, "a NaN MH clock answers nil")
    eq(wg.swing_sync_gap(2.0, 0 / 0), nil, "a NaN OH clock answers nil")
    eq(wg.swing_sync_gap("2", 2.0), nil, "a non-numeric clock answers nil")
    eq(wg.swing_sync_status(2.0, 2.0), "clash", "coincident landings read clash")
    eq(wg.swing_sync_status(2.0, 2.25), "clash", "a 0.25 s gap reads clash")
    eq(wg.swing_sync_status(2.0, 2.5), "clean", "a 0.5 s gap reads clean")
    eq(wg.swing_sync_status(1.0, 1.25, 0.25), "clash",
        "an explicit window boundary reads clash (inclusive)")
    eq(wg.swing_sync_status(1.0, 1.5, 0.25), "clean",
        "past an explicit window reads clean")
    eq(wg.swing_sync_status(2.0, 2.0, nil), "clash",
        "a missing window falls back to the module constant")
    eq(wg.swing_sync_status(2.0, 2.5, "wide"), "clean",
        "a non-numeric window falls back instead of erroring")
    eq(wg.swing_sync_status(2.0, 2.0, 0 / 0), "clash",
        "a NaN window falls back to the module constant")
    eq(wg.swing_sync_status(nil, 2.0), nil, "an unknown MH clock answers nil")
    eq(wg.swing_sync_status(2.0, nil), nil, "an unknown OH clock answers nil")
    eq(wg.swing_sync_status(0 / 0, 0 / 0), nil, "NaN clocks answer nil")
    eq(wg.swing_sync_fraction(2.0, 2.0, 2.5), 1.0,
        "an OH landing with the MH sits at the right edge")
    eq(wg.swing_sync_fraction(2.0, 1.0, 2.0), 0.5,
        "an OH landing mid-swing sits mid-bar")
    eq(wg.swing_sync_fraction(2.0, 0.0, 2.0), 0.0,
        "an OH landing at the MH start sits at the left edge (inclusive)")
    eq(wg.swing_sync_fraction(1.0, 2.0, 2.0), nil,
        "an OH landing past the MH landing is unplaceable")
    eq(wg.swing_sync_fraction(2.0, -0.5, 2.0), nil,
        "an OH landing before the MH start is unplaceable")
    eq(wg.swing_sync_fraction(nil, 1.0, 2.0), nil, "an unknown MH clock is unplaceable")
    eq(wg.swing_sync_fraction(2.0, nil, 2.0), nil, "an unknown OH clock is unplaceable")
    eq(wg.swing_sync_fraction(2.0, 1.0, nil), nil, "an unknown MH speed is unplaceable")
    eq(wg.swing_sync_fraction(2.0, 1.0, 0), nil, "a zero MH speed is unplaceable")
    eq(wg.swing_sync_fraction(2.0, 1.0, -2.0), nil, "a negative MH speed is unplaceable")
    eq(wg.swing_sync_fraction(0 / 0, 1.0, 2.0), nil, "a NaN MH clock is unplaceable")
    eq(wg.swing_sync_fraction(2.0, 0 / 0, 2.0), nil, "a NaN OH clock is unplaceable")
    eq(wg.swing_sync_fraction(2.0, 1.0, 0 / 0), nil, "a NaN MH speed is unplaceable")
end

-- Rule 8 / frozen fields / nil-safety.
do
    eq(evaluate({ rage = NONE }).hold, false, "rule 8: no action, no hold")
    eq(evaluate({ rage = NONE }).hold_text, nil, "rule 8: no hold text")

    local out = {
        action = "stale", hold = "stale", hold_text = "STALE", filler_slot = "stale",
        judge_slot = "stale", rotation_key = "stale", waiting_judgement = true,
    }
    wg.evaluate(inp({ rage = NONE }), out)
    eq(out.action, nil, "a reused out table has action overwritten")
    eq(out.hold, false, "a reused out table has hold overwritten")
    eq(out.hold_text, nil, "a reused out table has hold_text overwritten")
    eq(out.filler_slot, nil, "a reused out table has filler_slot overwritten")
    eq(out.judge_slot, nil, "a reused out table has judge_slot overwritten")
    eq(out.rotation_key, nil, "a reused out table has rotation_key overwritten")
    eq(out.waiting_judgement, false, "a reused out table has waiting_judgement overwritten")

    local ok, err = pcall(wg.evaluate)
    check(ok, "evaluate with no arguments does not error (" .. tostring(err) .. ")")
    ok, err = pcall(wg.evaluate, nil, nil)
    check(ok, "evaluate(nil, nil) does not error (" .. tostring(err) .. ")")
    local fallback = wg.evaluate(inp({ overpower_remaining = 3 }))
    eq(fallback.action, "op", "evaluate can allocate its own out table")

    local frozen = inp({})
    local before_rage = frozen.rage
    wg.evaluate(frozen, {})
    eq(frozen.rage, before_rage, "evaluate never writes back into its inputs")

    local NaN = 0 / 0
    eq(evaluate({ overpower_remaining = NaN, target_health_pct = NaN,
        swing_remaining = NaN }).action, nil,
        "a NaN-shaped input cannot match any rule")
end

--=========================================================================================
-- 1) Sandbox: compat + utils + nextaction_ui + warrior_guide + classes/warrior.lua
--=========================================================================================
local SPELL_INFOS = {
    [7384] = { name = "Overpower", icon = "icon_op" },
    -- The utility spine's spells: present in a real client's spell data (learned
    -- or not), so the Wrath name resolution caches them instead of retrying the
    -- GetSpellInfo name leg on every gather.
    [2458] = { name = "Berserker Stance", icon = "icon_zerk" },
    [2687] = { name = "Battle Shout", icon = "icon_shout" },
    [64382] = { name = "Shattering Throw", icon = "icon_throw" },
    [57755] = { name = "Heroic Throw", icon = "icon_throw2" },
    [5308] = { name = "Execute", icon = "icon_execute" },
    [1464] = { name = "Slam", icon = "icon_slam_r1" },
    [47475] = { name = "Slam", icon = "icon_slam" },
    [78] = { name = "Heroic Strike", icon = "icon_hs_r1" },
    [47450] = { name = "Heroic Strike", icon = "icon_hs" },
    [845] = { name = "Cleave", icon = "icon_cleave_r1" },
    [47520] = { name = "Cleave", icon = "icon_cleave" },
}

-- The TBC client's spell book: the same abilities capped at their 2.5.6 max ranks
-- (Slam 25242, HS 25286, Cleave 25231, Bloodthirst 23894; Whirlwind resolves
-- through the base 1680 on every family), so the rank resolution in a TBC
-- sandbox lands where it would in game.
local TBC_SPELL_INFOS = {
    [7384] = { name = "Overpower", icon = "icon_op" },
    [5308] = { name = "Execute", icon = "icon_execute" },
    [1464] = { name = "Slam", icon = "icon_slam_r1" },
    [25242] = { name = "Slam", icon = "icon_slam" },
    [78] = { name = "Heroic Strike", icon = "icon_hs_r1" },
    [25286] = { name = "Heroic Strike", icon = "icon_hs" },
    [845] = { name = "Cleave", icon = "icon_cleave_r1" },
    [25231] = { name = "Cleave", icon = "icon_cleave" },
    [23881] = { name = "Bloodthirst", icon = "icon_bt_r1" },
    [23894] = { name = "Bloodthirst", icon = "icon_bt" },
    [1680] = { name = "Whirlwind", icon = "icon_ww_r1" },
}

-- The Era client's spell book (1.15.9): HS 25286 and Cleave 25231 are shared
-- with TBC (the smoke fixture models Era as knowing them), while Slam/BT
-- resolve at their vanilla ranks (Slam 11605, BT 23884 - NEEDS IN-CLIENT
-- CONFIRMATION on 1.15.9), Whirlwind through the base 1680 and Hamstring
-- through 18499 once learned (sim-cited TBC weave rank; 7373 rank-1
-- fallback). Rank resolution in an Era sandbox lands on these through the
-- same tables the addon ships.
local ERA_SPELL_INFOS = {
    [7384] = { name = "Overpower", icon = "icon_op" },
    [5308] = { name = "Execute", icon = "icon_execute" },
    [1464] = { name = "Slam", icon = "icon_slam_r1" },
    [11605] = { name = "Slam", icon = "icon_slam_era" },
    [78] = { name = "Heroic Strike", icon = "icon_hs_r1" },
    [25286] = { name = "Heroic Strike", icon = "icon_hs" },
    [845] = { name = "Cleave", icon = "icon_cleave_r1" },
    [25231] = { name = "Cleave", icon = "icon_cleave" },
    [7373] = { name = "Hamstring", icon = "icon_hamstring_r1" },
    [18499] = { name = "Hamstring", icon = "icon_hamstring" },
    [23881] = { name = "Bloodthirst", icon = "icon_bt_r1" },
    [23884] = { name = "Bloodthirst", icon = "icon_bt_era" },
    [1680] = { name = "Whirlwind", icon = "icon_ww_r1" },
}
-- The Forever client's spell book (1.60.x): the rank-1 classic set plus Victory
-- Rush 34428 (the WotLK id, UNCONFIRMED on Forever - the provider requires
-- family + knowledge + usable, so a wrong id fails safe to nil).
local FOREVER_SPELL_INFOS = {
    [7384] = { name = "Overpower", icon = "icon_op" },
    [5308] = { name = "Execute", icon = "icon_execute" },
    [1464] = { name = "Slam", icon = "icon_slam_r1" },
    [78] = { name = "Heroic Strike", icon = "icon_hs_r1" },
    [845] = { name = "Cleave", icon = "icon_cleave_r1" },
    [34428] = { name = "Victory Rush", icon = "icon_vr" },
}
-- Wrath extras for the base (fury) book: Bloodthirst 30335 (the wotlk-current
-- rank, wowhead.com/wotlk/spell=30335); Whirlwind resolves through the base
-- 1680 (the shipped ww_ids carries only the sim-cited base id), so the fury
-- sandbox resolves the core like a 3.3.5 client. Arms sandboxes add MS 47486
-- / Bladestorm 63784 below; SoD sandboxes add Raging Blow 402911.
local WRATH_CORE_INFOS = {
    [23881] = { name = "Bloodthirst", icon = "icon_bt_r1" },
    [30335] = { name = "Bloodthirst", icon = "icon_bt" },
    [1680] = { name = "Whirlwind", icon = "icon_ww_r1" },
}
local ARMS_EXTRA_INFOS = {
    [12294] = { name = "Mortal Strike", icon = "icon_ms_r1" },
    [47486] = { name = "Mortal Strike", icon = "icon_ms" },
    [772] = { name = "Rend", icon = "icon_rend_r1" },
    [47465] = { name = "Rend", icon = "icon_rend" },
    [63784] = { name = "Bladestorm", icon = "icon_bladestorm" },
}
local SOD_EXTRA_INFOS = {
    [402911] = { name = "Raging Blow", icon = "icon_raging" },
}

local MODULES = { "compat.lua", "utils.lua", "guard.lua", "nextaction_ui.lua", "warrior_guide.lua",
    "classes/warrior.lua" }

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
    function t:SetAllPoints() end
    function t:SetTexCoord(l, r, top, bottom) t.texcoord = { l, r, top, bottom } end
    function t:SetTexture(tex) t.texture = tex end
    function t:SetColorTexture() end
    function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
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
    -- opts.tbc selects the TBC client profile (2.5.6 spell book), opts.era the
    -- Era profile (1.15.9 spell book); opts.project and opts.interface select
    -- the family detection inputs (defaults: Wrath). The Wrath default book is
    -- the base book plus the fury core (BT 30335 / WW base 1680); opts.arms adds
    -- the arms ranks (MS / Rend / Bladestorm) on top, opts.sod_runes adds
    -- Raging Blow on top of whatever family book is selected.
    -- opts.known_spells lists the ids api.is_spell_known answers true for
    -- (spec/rune/talent probes; everything else answers false).
    -- opts.forever selects the Forever client profile (1.60.x spell book);
    -- opts.spell_usable injects the IsSpellUsable probe (Victory Rush), absent
    -- by default so the probe-missing path is exercised too.
    local book
    if opts.forever then
        book = FOREVER_SPELL_INFOS
    elseif opts.tbc then
        book = TBC_SPELL_INFOS
    elseif opts.era then
        book = ERA_SPELL_INFOS
    else
        book = {}
        for id, info in pairs(SPELL_INFOS) do book[id] = info end
        for id, info in pairs(WRATH_CORE_INFOS) do book[id] = info end
    end
    if opts.arms then
        local merged = {}
        for id, info in pairs(book) do merged[id] = info end
        for id, info in pairs(ARMS_EXTRA_INFOS) do merged[id] = info end
        book = merged
    end
    if opts.sod_runes then
        local merged = {}
        for id, info in pairs(book) do merged[id] = info end
        for id, info in pairs(SOD_EXTRA_INFOS) do merged[id] = info end
        book = merged
    end
    -- opts.drop_ids prunes ids from the book (a client whose spell data lacks
    -- the shipped UNCONFIRMED id: the id probe must fail safe to the name).
    if opts.drop_ids then
        local pruned = {}
        for id, info in pairs(book) do
            if not opts.drop_ids[id] then pruned[id] = info end
        end
        book = pruned
    end
    local known_spells = opts.known_spells or {}
    local sb = {
        clock = 0,
        frames = 0,
        power = 50,
        rage_cost = { { cost = 15 } },
        target_health = { 100, 100 },
        cooldowns = {},
        hide_spells = false,
        get_spell_info_calls = 0,
        cost_queries = 0,
        last_cost_id = nil,
        cooldown_query_log = {},
        cost_query_log = {},
        known_query_log = {},
    }

    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.WOW_PROJECT_ID = opts.project or 11
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.GetTimePreciseSec = function() return sb.clock end
    env.GetTime = function() return sb.clock end
    -- Name back-map for the book below (name-family queries read the same
    -- id-keyed fixtures). Several ranks share one name, so a name query returns
    -- EVERY id that carries it - a real client answers a name regardless of rank.
    -- Every query shape is logged for the name-vs-id pins.
    local function ids_for_book_name(name)
        local ids = {}
        if type(name) ~= "string" then
            return ids
        end
        for id, info in pairs(book) do
            if info.name == name then
                ids[#ids + 1] = id
            end
        end
        return ids
    end
    env.IsSpellKnown = function(spell)
        sb.known_query_log[#sb.known_query_log + 1] = spell
        if known_spells[spell] == true then
            return true
        end
        if type(spell) == "string" then
            -- A name-capable client answers a name query by the spell NAME; the
            -- fixture's book carries several ranks under one name, so any known
            -- rank of that name answers true (a real client does not care which
            -- rank id the name maps to).
            local ids = ids_for_book_name(spell)
            for i = 1, #ids do
                if known_spells[ids[i]] == true then
                    return true
                end
            end
            return false
        end
        return false
    end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.GetLocale = function() return "enUS" end
    env.GetBuildInfo = function()
        return "0.0.0", "00000", "today", opts.interface or 30300
    end
    env.UIParent = make_frame("UIParent")
    env.UIParent.GetCenter = function() return 0, 0 end
    env.CreateFrame = function(...)
        sb.frames = sb.frames + 1
        return make_frame(select(2, ...))
    end
    env.GetSpellInfo = function(spell)
        sb.get_spell_info_calls = sb.get_spell_info_calls + 1
        if sb.hide_spells then
            return nil
        end
        local info = book[spell]
        if info then
            return info.name, nil, info.icon, 0, 0, 0, spell
        end
        -- Name-known spells (a client that knows the spell under a different
        -- id than the shipped UNCONFIRMED one): opts.known_names maps the
        -- English name to its client-local id.
        if type(spell) == "string" and opts.known_names then
            local name_id = opts.known_names[spell]
            if name_id then
                return spell, nil, "icon_name_" .. spell, 0, 0, 0, name_id
            end
        end
        return nil
    end
    env.GetSpellCooldown = function(spell)
        sb.cooldown_query_log[#sb.cooldown_query_log + 1] = spell
        local cd = sb.cooldowns[spell]
        if cd == nil and type(spell) == "string" then
            local ids = ids_for_book_name(spell)
            for i = 1, #ids do
                cd = sb.cooldowns[ids[i]]
                if cd ~= nil then
                    break
                end
            end
        end
        if cd then
            return cd[1], cd[2], 1, 1
        end
        return 0, 0, 0, 0
    end
    env.GetSpellBaseCooldown = function() return 0 end
    env.GetSpellPowerCost = function(id)
        sb.cost_queries = sb.cost_queries + 1
        sb.last_cost_id = id
        sb.cost_query_log[#sb.cost_query_log + 1] = id
        local keys = { id }
        if type(id) == "string" then
            keys = ids_for_book_name(id)
        end
        if sb.cost_by_id then
            for i = 1, #keys do
                local c = sb.cost_by_id[keys[i]]
                if c ~= nil then
                    return { { cost = c } }
                end
            end
        end
        return sb.rage_cost
    end
    env.IsCurrentSpell = function() return false end
    -- Victory Rush usability probe (Forever only): injected per sandbox; absent
    -- means the client cannot answer (compat degrades to unknown, never usable).
    if opts.spell_usable ~= nil then
        env.IsSpellUsable = opts.spell_usable
    end
    env.UnitPower = function() return sb.power end
    env.UnitPowerMax = function() return 100 end
    env.UnitHealthMax = function()
        if sb.target_health then return sb.target_health[2] end
        return nil
    end
    env.UnitHealth = function()
        if sb.target_health then return sb.target_health[1] end
        return nil
    end
    env.UnitExists = function() return true end
    env.UnitAura = function() return nil end
    env.UnitCastingInfo = function() return nil end
    env.UnitChannelInfo = function() return nil end
    env.InCombatLockdown = function() return false end

    local ST = {
        WARRIOR = {},
        player_class = "WARRIOR",
        interfaces_are_initialised = true,
        in_combat = false,
        player_guid = "Player-1",
        db = { profile = { enabled = true } },
    }
    local class_db = {
        -- The real WARRIOR defaults (config_presets.lua), so a wrong colour is a module
        -- bug and not a fixture bug. The guide keys are the new ones; enabled=true here
        -- so the display half can be exercised (the shipped default false is pinned by
        -- the text parity section below).
        enable_hs_color = true,
        hs_color = { 130, 7, 9, 1.0 },
        enable_cleave_color = true,
        cleave_color = { 64, 130, 7, 1.0 },
        insufficient_rage_color = { 140, 140, 140, 1.0 },
        use_bloodsurge_glow = true,
        bloodsurge_glow_color = { 227, 57, 74, 1.0 },
        bloodsurge_glow_nlines = 12,
        bloodsurge_glow_freq = 0.1,
        bloodsurge_glow_line_length = 12,
        show_warrior_deep_wounds_bar = true,
        warrior_deep_wounds_bar_color = { 179, 38, 38, 0.90 },
        show_warrior_sunder_armor_bar = true,
        warrior_sunder_armor_bar_color = { 140, 89, 38, 0.90 },
        show_warrior_rend_bar = true,
        warrior_rend_bar_color = { 217, 38, 26, 0.90 },
        show_warrior_thunder_clap_bar = true,
        warrior_thunder_clap_bar_color = { 89, 140, 191, 0.90 },
        show_warrior_demo_shout_bar = true,
        warrior_demo_shout_bar_color = { 166, 128, 77, 0.90 },
        show_warrior_shield_block_bar = true,
        warrior_shield_block_bar_color = { 51, 140, 255, 0.90 },
        show_warrior_slam_cast_bar = true,
        show_warrior_overpower_flash = true,
        mainhand = { border_width = 2 },
        nextaction_enabled = true,
        nextaction_locked = true,
        nextaction_visibility_key = "in_combat",
        nextaction_icon_size = 45,
        nextaction_x = 0,
        nextaction_y = -180,
        guide_execute_pct = 20,
    }
    function ST.get_class_table() return class_db end
    function ST.get_hand_table() return class_db.mainhand end
    function ST.get_visuals_frame() return nil end
    function ST.get_bar_visuals_width_and_height() return 100, 20 end
    function ST.get_bar_frame() return nil end
    function ST.convert_color(_, t, new_alpha)
        local r, g, b, a = unpack(t)
        a = new_alpha or a
        return r / 255, g / 255, b / 255, a
    end
    function ST.set_bar_color() return true end

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

check(type(st.warrior_guide) == "table", "the provider sandbox loads the pure engine")
check(type(ST.WARRIOR.guide) == "table", "classes/warrior.lua defines ST.WARRIOR.guide")
check(type(ST.WARRIOR.guide.gather) == "function", "the warrior guide has gather")
check(type(ST.WARRIOR.guide.evaluate) == "function", "the warrior guide has evaluate")

-- post_init resolves the rank icons and builds the frame through the real hook.
ST.in_combat = true
ST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
ST.gcd = { expires = 0 }
ST.WARRIOR.post_init(ST)
local ui = st.nextaction_ui
check(ui.frame ~= nil, "post_init builds the guide frame through the real hook")
check(ui.inert ~= true, "the warrior provider is live")
eq(ui.get_provider(ST), ST.WARRIOR.guide, "the warrior guide resolves as the frame's provider")

local slots = ST.WARRIOR.guide.slots
eq(#slots, 10, "the Wrath default (fury) declares the six core slots plus the utility spine's four rows")
eq(#slots, 10, "the slot set is the six core slots plus the utility spine's four rows")
local expected_keys = { "op", "execute", "slam", "hs", "bt", "ww" }
for i = 1, #expected_keys do
    eq(slots[i].key, expected_keys[i], "slot " .. i .. " is " .. expected_keys[i])
    eq(slots[i].cooldown_key, expected_keys[i],
        "slot " .. expected_keys[i] .. " carries its cooldown_key")
    eq(slots[i].swipe_duration, 1.5,
        "slot " .. expected_keys[i] .. " carries the GCD-length swipe fallback")
end
eq(slots[1].spell_id, 7384, "op keeps the Overpower rank-1 id")
eq(slots[2].spell_id, 5308, "execute keeps the Execute rank-1 id")
eq(slots[3].spell_id, 47475, "post_init resolved slam to the client's current rank")
eq(slots[4].spell_id, 47450, "post_init resolved hs to the client's current rank")
eq(slots[5].spell_id, 30335, "post_init resolved bt to the wotlk-current rank")
eq(slots[6].spell_id, 1680, "post_init resolved ww to the sim-cited base id")
eq(ST.WARRIOR.guide.labels.next_action, "Next action:", "labels.next_action is the default")
eq(ST.WARRIOR.guide.labels.hold, "HOLD", "labels.hold is the default")
eq(ST.WARRIOR.guide.labels.ride, "RIDE", "labels.ride is the default")
eq(ST.WARRIOR.guide.rotation_key, nil, "no rotation text source is declared")
eq(ST.WARRIOR.guide.rotation_names, nil, "no rotation name map is declared")

-- The frame: one icon per slot, in order, showing the resolved rank textures.
eq(#ui.icons, 10, "the frame holds one icon per slot")
eq(sandbox.frames, 31, "frame count: group + the slots' icons/borders/cooldowns + hold")
for i = 1, #slots do
    eq(ui.icons[i].slot, slots[i], "icon " .. i .. " follows the slot declaration order")
end
eq(ui.icons[1].icon.texture.texture, "icon_op", "the op icon shows the Overpower texture")
eq(ui.icons[2].icon.texture.texture, "icon_execute", "the execute icon shows the Execute texture")
eq(ui.icons[3].icon.texture.texture, "icon_slam", "the slam icon shows the current rank's texture")
eq(ui.icons[4].icon.texture.texture, "icon_hs", "the hs icon shows the current rank's texture")
eq(ui.icons[5].icon.texture.texture, "icon_bt", "the bt icon shows the Bloodthirst texture")
eq(ui.icons[6].icon.texture.texture, "icon_ww_r1", "the ww icon shows the rank-1 art (rank-invariant)")
eq(ui.frame.label.text, "Next action:", "the label carries the default caption")
eq(ui.icons[1].remaining_key, "op_remaining", "the swipe field names are derived from the key")
eq(ui.icons[5].expires_key, "bt_expires", "the expiry field name is derived from the key")
eq(ui.icons[3].glow_key, nil, "the warrior slots carry no glow")

-- Every possible action output names a declared slot (through the real provider).
do
    local provider = ST.WARRIOR.guide
    local function action_of(overrides)
        local inputs = { swing_remaining = 2.0, rage = 50, hs_cost = 15,
            target_health_pct = 100, execute_pct = 20 }
        for k, v in pairs(overrides or {}) do
            if v == NONE then
                inputs[k] = nil
            else
                inputs[k] = v
            end
        end
        local out = {}
        provider.evaluate(inputs, out)
        return out.action
    end
    local actions = {
        action_of({ overpower_remaining = 3 }),
        action_of({ target_health_pct = 10 }),
        action_of({ has_bloodsurge = true }),
        action_of({}),
        action_of({ rage = NONE }),
    }
    eq(actions[1], "op", "the provider delegates to the pure engine (op)")
    eq(actions[2], "execute", "the provider delegates to the pure engine (execute)")
    eq(actions[3], "slam", "the provider delegates to the pure engine (slam)")
    eq(actions[4], "hs", "the provider delegates to the pure engine (hs)")
    eq(actions[5], nil, "the provider delegates to the pure engine (none)")
    -- The fury reader path (BT/WW present, floor 50, wrath_fury): every action
    -- the engine can return on this branch names a declared slot.
    local function fury_action_of(overrides)
        local inputs = { swing_remaining = 2.0, rage = 60, hs_cost = 15,
            target_health_pct = 100, execute_pct = 20, hs_rage_floor = 50,
            wrath_fury = true }
        for k, v in pairs(overrides or {}) do
            if v == NONE then
                inputs[k] = nil
            else
                inputs[k] = v
            end
        end
        local out = {}
        provider.evaluate(inputs, out)
        return out.action
    end
    eq(fury_action_of({ bt_remaining = 0, ww_remaining = 5 }), "bt",
        "the fury provider delegates to the pure engine (bt)")
    eq(fury_action_of({ bt_remaining = 3, ww_remaining = 0 }), "ww",
        "the fury provider delegates to the pure engine (ww)")
    eq(fury_action_of({ bt_remaining = 3, ww_remaining = 5,
        has_bloodsurge = true }), "slam",
        "the fury provider delegates to the pure engine (slam, core cooling)")
    eq(fury_action_of({ bt_remaining = 0, ww_remaining = 5,
        has_bloodsurge = true }), "bt",
        "the fury delay gate withholds Slam while BT is ready")
    eq(fury_action_of({ bt_remaining = 3, ww_remaining = 5,
        target_health_pct = 10 }), "execute",
        "the fury provider delegates to the pure engine (demoted execute)")
    eq(fury_action_of({ bt_remaining = 0, ww_remaining = 0,
        target_health_pct = 10 }), "bt",
        "the demoted execute never spends at the core's expense")
    local fury_actions = { "bt", "ww", "slam", "execute", "hs", "op" }
    local all_resolve = true
    for i = 1, #actions do
        if actions[i] ~= nil and ui.slot_index[actions[i]] == nil then
            all_resolve = false
        end
    end
    check(all_resolve, "every action the engine can return names a declared slot")
    local fall_resolve = true
    for i = 1, #fury_actions do
        if ui.slot_index[fury_actions[i]] == nil then
            fall_resolve = false
        end
    end
    check(fall_resolve, "every action the fury branch can return names a declared slot")
    local slots_have_keys = true
    for i = 1, #slots do
        if ui.slot_index[slots[i].key] == nil then
            slots_have_keys = false
        end
    end
    check(slots_have_keys, "every declared slot key is frame-addressable")
end

-- The gather into the caller-owned reused table.
sandbox.clock = 100
ST.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
ST.gcd = { expires = 100.5 }
ST.hs_queued = true
ST.cleave_queued = false
ST.insufficient_rage = false
ST.has_bloodsurge = true
ST.warrior_slam_casting = true
ST.warrior_overpower_proc_until = 103.5
sandbox.power = 40
sandbox.target_health = { 350, 1000 }
sandbox.cooldowns = { [7384] = { 100, 6 }, [5308] = { 100, 1.5 },
    [30335] = { 98, 4 } }
sandbox.rage_cost = { { cost = 15 } }
sandbox.cost_by_id = { [47450] = 15, [47520] = 15, [30335] = 30, [1680] = 25 }
sandbox.cost_queries = 0

local gathered_target = {}
local gathered = ST.WARRIOR.guide.gather(ST, gathered_target)
eq(gathered, gathered_target, "gather writes into and returns the caller's table")
eq(gathered.speed, 3.0, "gather: speed")
near(gathered.swing_remaining, 2.0, 1e-9, "gather: swing_remaining")
near(gathered.gcd_remaining, 0.5, 1e-9, "gather: gcd_remaining")
eq(gathered.rage, 40, "gather: rage from UnitPower")
eq(gathered.hs_queued, true, "gather: hs_queued")
eq(gathered.cleave_queued, false, "gather: cleave_queued")
eq(gathered.insufficient_rage, false, "gather: insufficient_rage")
eq(gathered.has_bloodsurge, true, "gather: has_bloodsurge")
eq(gathered.slam_casting, true, "gather: slam_casting from the Slam cast tracking")
near(gathered.overpower_remaining, 3.5, 1e-9, "gather: the OP window countdown")
near(gathered.target_health_pct, 35, 1e-9, "gather: target health percentage")
eq(gathered.hs_cost, 15, "gather: the HS rage cost")
eq(gathered.cleave_cost, 15, "gather: the Cleave rage cost")
near(gathered.op_remaining, 6.0, 1e-9, "gather: op_remaining from a real cooldown")
eq(gathered.op_duration, 6, "gather: the real cooldown length is latched")
eq(gathered.execute_remaining, 0, "gather: the ~1.5 s GCD echo is filtered (remaining 0)")
eq(gathered.execute_duration, nil, "gather: the GCD echo latches no duration")
eq(gathered.slam_remaining, 0, "gather: no Slam cooldown reads as 0")
eq(gathered.hs_remaining, 0, "gather: no HS cooldown reads as 0")
eq(gathered.cleave_remaining, 0, "gather: no Cleave cooldown reads as 0")
eq(gathered.execute_pct, 20, "gather: the Execute threshold default")
eq(gathered.bt_remaining, 2.0, "gather: bt_remaining from a real cooldown (98 + 4 s Wrath BT)")
eq(gathered.bt_duration, 4, "gather: the real BT length is latched")
eq(gathered.ww_remaining, 0, "gather: no WW cooldown reads as ready")
eq(gathered.ww_duration, nil, "gather: no WW cooldown latches no duration")
eq(gathered.bt_cost, 30, "gather: the BT rage cost")
eq(gathered.ww_cost, 25, "gather: the WW rage cost")
eq(gathered.hs_rage_floor, 50, "gather: the 50-rage fury floor")
eq(gathered.core_reserve_window, nil, "gather: the reserve window stays the 1.5 s default")
eq(gathered.execute_spam, nil, "gather: no Execute spam on fury (rule F demotes instead)")
eq(gathered.hs_cancel_cue, nil, "gather: no HS-cancel cue outside TBC")
eq(gathered.victory_rush, nil, "gather: no Victory Rush outside Forever")
eq(gathered.wrath_fury, true, "gather: the frozen fury flag")
eq(gathered.wrath_arms, nil, "gather: no arms flag on fury")
eq(gathered.sod, nil, "gather: no SoD flag on Wrath")
eq(gathered.sudden_death, nil, "gather: no SD proc without the aura")
eq(gathered.tfb, nil, "gather: no TfB proc without the aura")
eq(gathered.hamstring_known, nil, "gather: no Hamstring flag without the spellbook")
eq(gathered.hamstring_rage_threshold, nil, "gather: no weave threshold on fury")
eq(gathered.rend_upkeep_enabled, nil, "gather: no Rend enable on fury")
eq(gathered.sunder_stacks, nil, "gather: no Sunder upkeep reader on fury")
eq(gathered.sunder_remaining, nil, "gather: no Sunder countdown reader on fury")
eq(gathered.rend_remaining, nil, "gather: no Rend reader on fury")
eq(gathered.ms_remaining, nil, "gather: no MS reader on fury")
eq(gathered.bladestorm_remaining, nil, "gather: no Bladestorm reader on fury")
eq(gathered.bladestorm_known, nil, "gather: no Bladestorm probe on fury")
eq(gathered.raging_blow_remaining, nil, "gather: no Raging Blow reader on Wrath")
eq(sandbox.cost_queries, 4, "gather: all four rage costs are queried once")
eq(sandbox.last_cost_id, "Whirlwind", "gather: the WW cost is read by NAME on Wrath")

-- Every slot's cooldown key resolves into the gathered inputs.
local cooldowns_resolve = true
for i = 1, #slots do
    local cd_key = slots[i].cooldown_key
    if cd_key ~= nil then
        local remaining = gathered[cd_key .. "_remaining"]
        local known = gathered[cd_key .. "_known"]
        -- The core rows always carry their reader; a utility row the client does
        -- not know is dark on purpose (known = false).
        if remaining == nil and known ~= false then
            cooldowns_resolve = false
        end
    end
end
check(cooldowns_resolve, "every slot cooldown_key resolves into the gathered inputs")

-- Stale fields are overwritten on the reused table, and the rank caches stop per-tick
-- spell-data walks.
ST.hs_queued = false
ST.has_bloodsurge = false
ST.warrior_slam_casting = false
ST.warrior_overpower_proc_until = nil
ST.gcd = { expires = 0 }
sandbox.power = nil
sandbox.target_health = nil
sandbox.cooldowns = {}
sandbox.rage_cost = nil
sandbox.cost_by_id = nil
sandbox.get_spell_info_calls = 0
sandbox.cost_queries = 0
local gathered2 = ST.WARRIOR.guide.gather(ST, gathered_target)
sandbox.get_spell_info_calls = 0
sandbox.cost_queries = 0
ST.WARRIOR.guide.gather(ST, gathered_target)
eq(gathered2, gathered_target, "the reused table is the same table")
eq(gathered2.overpower_remaining, nil, "the cleared OP window overwrites the stale value")
eq(gathered2.target_health_pct, nil, "a cleared target clears target_health_pct")
eq(gathered2.rage, nil, "an unreadable rage reads as nil")
eq(gathered2.hs_cost, nil, "an unreadable cost reads as nil")
eq(gathered2.cleave_cost, nil, "an unreadable Cleave cost reads as nil")
eq(gathered2.op_remaining, 0, "the dropped cooldown reads as 0")
eq(gathered2.op_duration, nil, "the dropped cooldown clears the duration")
eq(gathered2.hs_queued, false, "the queue flag is overwritten, not stale")
eq(gathered2.slam_casting, false, "the cast flag is overwritten, not stale")
eq(gathered2.gcd_remaining, 0, "the cleared GCD reads as 0")
eq(gathered2.bt_remaining, 0, "the dropped BT cooldown reads ready")
eq(gathered2.bt_duration, nil, "the dropped BT cooldown clears the duration")
eq(gathered2.wrath_fury, true, "the frozen fury flag survives a cooldown drop")
eq(gathered2.hs_rage_floor, 50, "the fury floor survives a cooldown drop")
eq(gathered2.sudden_death, nil, "no SD aura reads as nil")
eq(gathered2.tfb, nil, "no TfB aura reads as nil")
eq(sandbox.get_spell_info_calls, 0, "the resolved ranks are cached (no per-tick walks)")
eq(sandbox.cost_queries, 4, "the cost read still happens; an unreadable cost stays nil")
class_db.guide_execute_pct = 25
eq(ST.WARRIOR.guide.gather(ST, gathered_target).execute_pct, 25,
    "the Execute threshold rides the options")
class_db.guide_execute_pct = nil
eq(ST.WARRIOR.guide.gather(ST, gathered_target).execute_pct, 20,
    "a missing option falls back to the 20 % default")
class_db.guide_execute_pct = 20

-- Direct calls without an out table use the module's own reused table.
local own = ST.WARRIOR.gather_guide_inputs(ST)
eq(own, ST.WARRIOR.guide_inputs, "gather without an out table uses the module's reused table")

-- The rank-1 fallback when nothing resolves on the client.
do
    local fallback = build()
    fallback.hide_spells = true
    fallback.ST.WARRIOR.post_init(fallback.ST)
    local fslots = fallback.ST.WARRIOR.guide.slots
    eq(fslots[3].spell_id, 1464, "an unresolved Slam keeps the rank-1 fallback")
    eq(fslots[4].spell_id, 78, "an unresolved HS keeps the rank-1 fallback")
    eq(fslots[5].spell_id, 23881, "an unresolved BT keeps the rank-1 fallback")
    eq(fslots[6].spell_id, 1680, "an unresolved WW keeps the rank-1 fallback")
    local fui = fallback.st.nextaction_ui
    eq(fui.icons[4].icon.texture.texture, nil,
        "an unresolvable icon simply stays texture-less (no error)")
    fallback.cost_queries = 0
    local fgathered = fallback.ST.WARRIOR.guide.gather(fallback.ST, {})
    eq(fgathered.hs_cost, nil, "an unresolved HS rank yields no cost")
    eq(fgathered.bt_remaining, 0, "an unresolved BT rank reads ready, never stale")
    eq(fgathered.bt_cost, nil, "an unresolved BT rank yields no cost")
    eq(fgathered.wrath_fury, true, "the frozen fury flag needs no spell data")
    eq(fallback.cost_queries, 0, "an unresolved rank skips the cost query entirely")
end

--=========================================================================================
-- 3) The display mapping through the real frame and the real hooks
--=========================================================================================
ST.in_combat = true
ST.mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false }
ST.gcd = { expires = 0 }
ST.warrior_overpower_proc_until = nil
ST.has_bloodsurge = false
ST.hs_queued = false
ST.cleave_queued = false
ST.insufficient_rage = false
ST.warrior_slam_casting = false
sandbox.power = 50
sandbox.rage_cost = { { cost = 15 } }
sandbox.target_health = { 100, 100 }
sandbox.cooldowns = {}
sandbox.clock = 200

local function tick(advance)
    ST.mainhand.ends_at = sandbox.clock + 3.0
    sandbox.advance(advance or 0.1)
    ST.WARRIOR.on_bar_update(ST, "mainhand")
end
local function target(key)
    return ui.icons[ui.slot_index[key]].fade.target
end
local function slot_icon(key)
    return ui.icons[ui.slot_index[key]].icon
end

-- The OP window.
ST.warrior_overpower_proc_until = sandbox.clock + 5
tick()
eq(target("op"), 1, "the OP window lights the Overpower slot through the real hook")
eq(target("hs"), 0, "the HS slot stays dark on the OP tick")
eq(ui.frame.hold.fade.target, 0, "the OP tick shows no hold overlay")
eq(ui.frame.shown, true, "the in-combat tick shows the frame")

-- The OP window (outranks the fury core).
ST.warrior_overpower_proc_until = sandbox.clock + 5
tick()
eq(target("op"), 1, "the OP window lights the Overpower slot through the real hook")
eq(target("hs"), 0, "the HS slot stays dark on the OP tick")
eq(target("bt"), 0, "the BT slot stays dark on the OP tick")
eq(ui.frame.hold.fade.target, 0, "the OP tick shows no hold overlay")
eq(ui.frame.shown, true, "the in-combat tick shows the frame")

-- Execute range with BT ready: still BT (the fury demotion).
ST.warrior_overpower_proc_until = nil
sandbox.target_health = { 199, 1000 }
tick()
eq(target("bt"), 1, "19.9 % target health with BT ready still lights BT (demoted Execute)")
eq(target("execute"), 0, "the demoted Execute stays dark while BT is ready")
eq(target("op"), 0, "the Overpower slot fades out")

-- BT cooling, WW ready -> WW (outside Execute range so WW is visible).
sandbox.target_health = { 100, 100 }
sandbox.cooldowns = { [30335] = { sandbox.clock, 4 } }
tick()
eq(target("ww"), 1, "WW lights while BT cools down")
eq(target("bt"), 0, "BT fades while cooling")
eq(target("execute"), 0, "Execute stays dark outside its range")

-- Both core abilities cooling, rage to spare -> HS.
sandbox.cooldowns = { [30335] = { sandbox.clock, 4 }, [1680] = { sandbox.clock, 10 } }
tick()
eq(target("hs"), 1, "HS dumps with the core cooling and rage to spare")

-- Same, rage below the 50 floor -> nothing, and no hold overlay.
sandbox.power = 40
tick()
eq(target("hs"), 0, "HS withholds below the 50-rage floor")
eq(ui.frame.hold.fade.target, 0, "the floor withhold shows no hold overlay")
sandbox.power = 50

-- Execute range, core cooling, rage to spare -> demoted Execute.
sandbox.target_health = { 199, 1000 }
tick()
eq(target("execute"), 1, "Execute lights in range with the core cooling and rage to spare")
eq(target("bt"), 0, "BT stays dark while cooling")
sandbox.target_health = { 100, 100 }

-- The Bloodsurge proc with the core cooling, then with BT ready (delay gate).
ST.has_bloodsurge = true
tick()
eq(target("slam"), 1, "the Bloodsurge proc lights the Slam slot with the core cooling")
eq(target("hs"), 0, "Slam outranks the HS fallback")
eq(target("bt"), 0, "Slam outranks a cooling BT")
sandbox.cooldowns = {}
tick()
eq(target("bt"), 1, "a ready BT claims the GCD over the Slam proc (delay gate)")
eq(target("slam"), 0, "the gated Slam stays dark while BT is ready")
sandbox.cooldowns = { [30335] = { sandbox.clock, 4 }, [1680] = { sandbox.clock, 10 } }
ST.warrior_slam_casting = true
tick()
eq(target("slam"), 0, "a Slam already in flight suppresses the Slam prompt")
eq(target("hs"), 1, "while slamming the guide falls back to HS")
ST.warrior_slam_casting = false
ST.has_bloodsurge = false
sandbox.cooldowns = {}

-- The queued ride, the BT prompt and the insufficient-rage hold (core cooling).
ST.hs_queued = true
sandbox.cooldowns = { [30335] = { sandbox.clock, 4 }, [1680] = { sandbox.clock, 10 } }
tick()
eq(target("hs"), 0, "a queued HS is not re-suggested")
eq(ui.frame.hold.fade.target, 1, "the queued state shows the hold overlay")
eq(ui.frame.hold.text.text, "RIDE", "the queued state reads RIDE")
ST.hs_queued = false
tick()
eq(target("hs"), 1, "with nothing queued the guide suggests HS")
eq(ui.frame.hold.fade.target, 0, "the hold overlay clears")
sandbox.power = 5
tick()
eq(target("hs"), 0, "insufficient rage withholds the HS prompt")
eq(ui.frame.hold.fade.target, 1, "insufficient rage shows the hold overlay")
eq(ui.frame.hold.text.text, "HOLD", "the shortfall reads HOLD")
sandbox.power = nil
tick()
eq(target("hs"), 0, "unknown rage shows no prompt")
eq(ui.frame.hold.fade.target, 0, "unknown rage shows no hold")
sandbox.power = 50
sandbox.cooldowns = {}

-- A real client cooldown drives the swipe; the latch holds; the clear drops it.
ST.has_bloodsurge = true
sandbox.cooldowns = { [30335] = { sandbox.clock, 4 }, [1680] = { sandbox.clock, 10 },
    [47475] = { sandbox.clock, 6 } }
tick()
eq(target("slam"), 1, "the proc tick shows the Slam slot")
eq(slot_icon("slam").cooldown.cooldown_duration, 6,
    "the client-reported cooldown length drives the swipe")
eq(slot_icon("slam").cooldown.cooldown_sets, 1, "the swipe is set once")
eq(slot_icon("slam").cooldown_set, true, "the swipe latch is armed")
tick()
eq(slot_icon("slam").cooldown.cooldown_sets, 1, "the swipe latch holds across ticks")
ST.has_bloodsurge = false
sandbox.cooldowns = {}
tick()
eq(slot_icon("slam").cooldown.cooldown_sets, 2, "the dropped cooldown clears the swipe")
eq(slot_icon("slam").cooldown.cooldown_duration, 0, "the clear is a zero-length cooldown")
eq(slot_icon("slam").cooldown_set, false, "the swipe latch resets on clear")

-- Option gates: disabled hides the frame and stops the mapping; visibility follows the
-- in-combat key; the size/position/lock diff applies live.
local before_disable = target("hs")
class_db.nextaction_enabled = false
tick()
eq(ui.frame.shown, false, "nextaction_enabled=false hides the frame")
eq(target("hs"), before_disable, "the gated tick leaves the slot targets alone")
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

-- The hand gate: an offhand call never ticks the guide.
local before_offhand = target("hs")
sandbox.advance(1.0)
ST.WARRIOR.on_bar_update(ST, "offhand")
eq(target("hs"), before_offhand, "the offhand call does not tick the guide")

--=========================================================================================
-- 4) The TBC family: six slots, BT/WW reads, the floor, the gated display
--=========================================================================================
local tbc = build({ project = 5, interface = 20506, tbc = true })
eq(tbc.st.family, "TBC", "the TBC project id maps to TBC")
local TST, tst = tbc.ST, tbc.st
check(type(tst.warrior_guide) == "table", "the TBC sandbox loads the pure engine")

TST.in_combat = true
TST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
TST.gcd = { expires = 0 }
TST.WARRIOR.post_init(TST)
local tui = tst.nextaction_ui
check(tui.frame ~= nil, "TBC post_init builds the guide frame through the real hook")
eq(tui.get_provider(TST), TST.WARRIOR.guide, "the TBC guide resolves as the frame's provider")

local tslots = TST.WARRIOR.guide.slots
eq(#tslots, 15, "TBC declares the seven core slots plus the utility spine's eight rows")
eq(#tslots, 15, "the TBC slot set is the seven core slots plus the utility spine's eight rows")
local texpected_keys = { "op", "execute", "slam", "hs", "bt", "ww", "sunder" }
for i = 1, #texpected_keys do
    eq(tslots[i].key, texpected_keys[i], "TBC slot " .. i .. " is " .. texpected_keys[i])
    eq(tslots[i].cooldown_key, texpected_keys[i],
        "TBC slot " .. texpected_keys[i] .. " carries its cooldown_key")
    eq(tslots[i].swipe_duration, 1.5,
        "TBC slot " .. texpected_keys[i] .. " carries the GCD-length swipe fallback")
end
eq(tslots[1].spell_id, 7384, "TBC op keeps the Overpower rank-1 id")
eq(tslots[2].spell_id, 5308, "TBC execute keeps the Execute rank-1 id")
eq(tslots[3].spell_id, 25242, "TBC post_init resolved slam to the 2.5.6 rank")
eq(tslots[4].spell_id, 25286, "TBC post_init resolved hs to the 2.5.6 rank")
eq(tslots[5].spell_id, 23894, "TBC post_init resolved bt to the 2.5.6 rank")
eq(tslots[6].spell_id, 1680, "TBC post_init resolved ww to the sim-cited base id")
eq(tslots[7].spell_id, 7386, "TBC sunder keeps the rank-1 fallback (no Sunder book entry)")

-- The frame: one icon per slot, in order, showing the resolved rank textures.
eq(#tui.icons, 15, "the TBC frame holds one icon per slot")
eq(tbc.frames, 45, "TBC frame count: group + the slots' icons/borders/cooldowns + hold")
for i = 1, #tslots do
    eq(tui.icons[i].slot, tslots[i], "TBC icon " .. i .. " follows the slot declaration order")
end
eq(tui.icons[5].icon.texture.texture, "icon_bt",
    "the bt icon shows the Bloodthirst texture")
eq(tui.icons[6].icon.texture.texture, "icon_ww_r1",
    "the ww icon shows the rank-1 art (rank-invariant)")
eq(tui.icons[5].remaining_key, "bt_remaining", "the BT swipe field names are derived")
eq(tui.icons[6].expires_key, "ww_expires", "the WW expiry field name is derived")

-- The TBC HUD row mirrors the TBC guide row (W-21): the six core abilities plus
-- the Sunder upkeep slot, which the guide already shipped. The mirror is
-- display-only (no cooldown of its own to ride) and hides unless its
-- hud_show_sunder toggle reads exactly true (nil = off, the druid Claw shape).
do
    local thud = TST.WARRIOR.HUD_SLOTS
    eq(#thud, 9, "TBC HUD: seven ability slots plus the two trinkets (sunder mirrored)")
    local tkeys = { "op", "execute", "slam", "hs", "bt", "ww", "sunder",
        "trinket1", "trinket2" }
    for i = 1, #tkeys do
        eq(thud[i].key, tkeys[i], "TBC HUD slot " .. i .. " is " .. tkeys[i])
    end
    local sunder_mirrored = false
    for i = 1, #thud do
        if thud[i].key == "sunder" then sunder_mirrored = true end
    end
    check(sunder_mirrored, "TBC HUD: the sunder slot is mirrored (W-21)")
    eq(thud[7].spell, 7386, "the sunder mirror keeps the rank-1 Sunder id")
    eq(thud[7].kind, "spell", "the sunder mirror is a spell slot")
end

-- The legacy (non-core) contrast rides a Cata sandbox: no readers, no floor,
-- cleave kept. Wrath and its branches always feed the core readers above.
do
    local legacy_env = build({ project = 14, interface = 40400 })
    eq(legacy_env.st.family, "CATA", "the Cata project id maps to CATA")
    local legacy = legacy_env.ST.WARRIOR.guide.gather(legacy_env.ST, {})
    eq(legacy.bt_remaining, nil, "non-core gather feeds no BT reader")
    eq(legacy.bt_duration, nil, "non-core gather feeds no BT duration")
    eq(legacy.ww_remaining, nil, "non-core gather feeds no WW reader")
    eq(legacy.ww_duration, nil, "non-core gather feeds no WW duration")
    eq(legacy.bt_cost, nil, "non-core gather feeds no BT cost")
    eq(legacy.ww_cost, nil, "non-core gather feeds no WW cost")
    eq(legacy.hs_rage_floor, nil, "non-core gather sets no HS floor")
    eq(legacy.wrath_fury, nil, "non-core gather sets no fury flag")
    eq(legacy.wrath_arms, nil, "non-core gather sets no arms flag")
    eq(legacy.sod, nil, "non-core gather sets no SoD flag")
    eq(legacy_env.ST.WARRIOR.guide.slots[5].key, "cleave", "non-core keeps the cleave slot")
    eq(legacy_env.ST.WARRIOR.guide.slots[6].key, "hamstring", "non-core carries the Hamstring filler sixth")
    eq(#legacy_env.ST.WARRIOR.guide.slots, 6, "non-core keeps the six-slot base set")
    eq(legacy.hamstring_known, nil, "non-core gather: no Hamstring flag without the spellbook")
    eq(legacy.hamstring_remaining, 0, "non-core gather: the unlearned Hamstring reads ready")
    eq(legacy.hamstring_duration, nil, "non-core gather: the unlearned Hamstring latches no duration")
end

-- Hamstring slot (base set, sixth): descriptor, swipe wiring, icon fallback and
-- the known/unknown gather cases on a fresh Cata sandbox (the block above
-- owns its locals). No rule names "hamstring" yet, so the same tick with and
-- without the flag decides identically (pinned with the other follow-up
-- inputs above).
do
    local benv = build({ project = 14, interface = 40400 })
    benv.ST.WARRIOR.post_init(benv.ST)
    local bslots = benv.ST.WARRIOR.guide.slots
    local hslot = bslots[6]
    eq(hslot.key, "hamstring", "the base sixth slot names hamstring")
    eq(hslot.cooldown_key, "hamstring", "the Hamstring slot carries its cooldown_key")
    eq(hslot.swipe_duration, 1.5, "the Hamstring slot carries the GCD-length swipe fallback")
    eq(hslot.spell_id, 7373, "the Hamstring slot keeps the rank-1 fallback without spell data")
    local bhslots = benv.ST.WARRIOR.HUD_SLOTS
    eq(#bhslots, 8, "base HUD: six ability slots plus the two trinkets")
    local hkeys = { "op", "execute", "slam", "hs", "cleave", "hamstring", "trinket1", "trinket2" }
    for i = 1, #hkeys do
        eq(bhslots[i].key, hkeys[i], "base HUD slot " .. i .. " is " .. hkeys[i])
    end
    eq(bhslots[6].spell, 7373, "base HUD: Hamstring keeps the rank-1 fallback")
    -- The slot's swipe fields resolve into the gathered inputs.
    local bgathered = benv.ST.WARRIOR.guide.gather(benv.ST, {})
    check(bgathered.hamstring_remaining ~= nil, "the Hamstring cooldown_key resolves into the gathered inputs")
    eq(bgathered.hamstring_known, nil, "base gather: unknown Hamstring feeds nil")
end

-- Every TBC action output names a declared slot (through the real provider).
do
    local provider = TST.WARRIOR.guide
    local function taction_of(overrides)
        local inputs = { swing_remaining = 2.0, rage = 60, hs_cost = 15,
            target_health_pct = 100, execute_pct = 20, hs_rage_floor = 50 }
        for k, v in pairs(overrides or {}) do
            if v == NONE then
                inputs[k] = nil
            else
                inputs[k] = v
            end
        end
        local out = {}
        provider.evaluate(inputs, out)
        return out.action
    end
    eq(taction_of({ bt_remaining = 0, ww_remaining = 0 }), "bt",
        "the TBC provider delegates to the pure engine (bt)")
    eq(taction_of({ bt_remaining = 4, ww_remaining = 0 }), "ww",
        "the TBC provider delegates to the pure engine (ww)")
    eq(taction_of({ bt_remaining = 4, ww_remaining = 6 }), "hs",
        "the TBC provider delegates to the pure engine (hs)")
    eq(taction_of({ bt_remaining = 4, ww_remaining = 6, rage = 40 }), nil,
        "the TBC provider delegates to the pure engine (floor withhold)")
    eq(taction_of({ target_health_pct = 10, bt_remaining = 4, ww_remaining = 6,
        rage = 60 }), "execute",
        "the TBC provider delegates to the pure engine (execute)")
    local tactions = { "bt", "ww", "hs", "execute", "op", "slam", "sunder" }
    local tall_resolve = true
    for i = 1, #tactions do
        if tui.slot_index[tactions[i]] == nil then
            tall_resolve = false
        end
    end
    check(tall_resolve, "every action the TBC engine can return names a declared slot")
end

-- The TBC gather into the caller-owned reused table.
tbc.clock = 100
TST.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
TST.gcd = { expires = 100.5 }
TST.hs_queued = false
TST.cleave_queued = false
TST.insufficient_rage = false
TST.has_bloodsurge = false
TST.warrior_slam_casting = false
TST.warrior_overpower_proc_until = nil
tbc.power = 60
tbc.target_health = { 150, 1000 }
tbc.cooldowns = { [23894] = { 98, 6 } }
tbc.rage_cost = { { cost = 15 } }
-- Per-spell costs like the live client answers them (HS 15, BT 30, WW 25).
tbc.cost_by_id = { [25286] = 15, [25231] = 15, [23894] = 30, [1680] = 25 }

local tgathered_target = {}
local tgathered = TST.WARRIOR.guide.gather(TST, tgathered_target)
eq(tgathered, tgathered_target, "TBC gather writes into and returns the caller's table")
near(tgathered.bt_remaining, 4.0, 1e-9, "TBC gather: bt_remaining from a real cooldown")
eq(tgathered.bt_duration, 6, "TBC gather: the real BT length is latched")
eq(tgathered.ww_remaining, 0, "TBC gather: no WW cooldown reads as ready")
eq(tgathered.ww_duration, nil, "TBC gather: no WW cooldown latches no duration")
eq(tgathered.bt_cost, 30, "TBC gather: the BT rage cost")
eq(tgathered.ww_cost, 25, "TBC gather: the WW rage cost")
eq(tgathered.hs_cost, 15, "TBC gather: the HS rage cost")
eq(tgathered.hs_rage_floor, 40, "TBC gather: the 40-rage HS floor")
eq(tgathered.hs_cancel_cue, true, "TBC gather: the HS-cancel cue is armed")
eq(tgathered.hamstring_rage_threshold, nil, "TBC gather: no weave threshold (number filed)")
eq(tgathered.rend_upkeep_enabled, nil, "TBC gather: no Rend enable (Forever + SoD only)")
eq(tgathered.sunder_stacks, nil, "TBC gather: no Sunder aura reads nil")
eq(tgathered.sunder_remaining, nil, "TBC gather: no Sunder countdown reads nil")
eq(tgathered.victory_rush, nil, "TBC gather: no Victory Rush outside Forever")
near(tgathered.target_health_pct, 15, 1e-9, "TBC gather: target health percentage")

-- The GCD echo is filtered on the new readers too, and stale fields clear.
tbc.cooldowns = { [23894] = { 100, 1.5 }, [1680] = { 100, 1.5 } }
TST.WARRIOR.guide.gather(TST, tgathered_target)
eq(tgathered_target.bt_remaining, 0, "TBC gather: the BT GCD echo is filtered")
eq(tgathered_target.bt_duration, nil, "TBC gather: the BT echo latches no duration")
eq(tgathered_target.ww_remaining, 0, "TBC gather: the WW GCD echo is filtered")
tbc.cooldowns = { [23894] = { 98, 6 } }
TST.WARRIOR.guide.gather(TST, tgathered_target)
tbc.cooldowns = {}
TST.WARRIOR.guide.gather(TST, tgathered_target)
eq(tgathered_target.bt_remaining, 0, "TBC gather: the dropped BT cooldown reads ready")
eq(tgathered_target.bt_duration, nil, "TBC gather: the dropped BT cooldown clears")

-- The rank-1 fallback when nothing resolves on the client.
do
    local fallback = build({ project = 5, interface = 20506, tbc = true })
    fallback.hide_spells = true
    fallback.ST.WARRIOR.post_init(fallback.ST)
    local fslots = fallback.ST.WARRIOR.guide.slots
    eq(#fslots, 15, "an unresolved TBC client still declares the same slot set")
    eq(fslots[5].spell_id, 23881, "an unresolved BT keeps the rank-1 fallback")
    eq(fslots[6].spell_id, 1680, "an unresolved WW keeps the rank-1 fallback")
    local fgathered = fallback.ST.WARRIOR.guide.gather(fallback.ST, {})
    eq(fgathered.bt_remaining, 0, "an unresolved BT rank reads ready, never stale")
    eq(fgathered.bt_cost, nil, "an unresolved BT rank yields no cost")
end

-- The TBC display mapping through the real frame and the real hooks.
TST.mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false }
TST.gcd = { expires = 0 }
TST.warrior_overpower_proc_until = nil
TST.has_bloodsurge = false
TST.hs_queued = false
TST.cleave_queued = false
TST.insufficient_rage = false
TST.warrior_slam_casting = false
tbc.power = 60
tbc.rage_cost = { { cost = 15 } }
tbc.target_health = { 100, 100 }
tbc.cooldowns = {}
tbc.clock = 200

local function ttick(advance)
    TST.mainhand.ends_at = tbc.clock + 3.0
    tbc.advance(advance or 0.1)
    TST.WARRIOR.on_bar_update(TST, "mainhand")
end
local function ttarget(key)
    return tui.icons[tui.slot_index[key]].fade.target
end
local function tslot_icon(key)
    return tui.icons[tui.slot_index[key]].icon
end

-- BT ready (no cooldown) lights the BT slot.
ttick()
eq(ttarget("bt"), 1, "TBC: a ready Bloodthirst lights the BT slot through the real hook")
eq(ttarget("hs"), 0, "TBC: HS stays dark while BT is ready")
eq(ttarget("ww"), 0, "TBC: WW stays dark while BT is ready")

-- Execute range with BT ready: still BT (the reservation).
tbc.target_health = { 150, 1000 }
ttick()
eq(ttarget("bt"), 1, "TBC: BT claims the GCD in Execute range")
eq(ttarget("execute"), 0, "TBC: Execute stays dark while BT is ready")

-- BT cooling, WW ready -> WW.
tbc.target_health = { 100, 100 }
tbc.cooldowns = { [23894] = { tbc.clock, 6 } }
ttick()
eq(ttarget("ww"), 1, "TBC: WW lights while BT cools down")
eq(ttarget("bt"), 0, "TBC: BT fades while cooling")
eq(tslot_icon("bt").cooldown.cooldown_sets, nil,
    "TBC: the cooling BT sets no phantom swipe (it prompts only when ready)")

-- Both core abilities cooling, rage to spare -> HS.
tbc.cooldowns = { [23894] = { tbc.clock, 6 }, [1680] = { tbc.clock, 10 } }
ttick()
eq(ttarget("hs"), 1, "TBC: HS dumps with the core cooling and rage to spare")

-- Same, rage below the floor -> nothing, and no hold overlay.
tbc.power = 30
ttick()
eq(ttarget("hs"), 0, "TBC: HS withholds below the 40-rage floor")
eq(tui.frame.hold.fade.target, 0, "TBC: the floor withhold shows no hold overlay")
tbc.power = 60

-- Execute range, core cooling, rage to spare -> Execute.
tbc.target_health = { 150, 1000 }
ttick()
eq(ttarget("execute"), 1, "TBC: Execute lights in range with rage to cover BT")

-- Execute range, rage short, BT landing inside the window -> withheld.
tbc.power = 40
tbc.cooldowns = { [23894] = { tbc.clock - 5, 6 }, [1680] = { tbc.clock, 10 } }
ttick()
eq(ttarget("execute"), 0, "TBC: Execute withholds when BT lands with rage short")
eq(ttarget("bt"), 0, "TBC: BT itself is still cooling")
tbc.power = 60
tbc.cooldowns = {}

-- Execute range with HS queued and the core cooling: the HS-cancel cue reads
-- CANCEL through the real hook (cancel the queued spend, don't ride it).
tbc.target_health = { 150, 1000 }
tbc.cooldowns = { [23894] = { tbc.clock, 6 }, [1680] = { tbc.clock, 10 } }
TST.hs_queued = true
ttick()
eq(ttarget("execute"), 1, "TBC: Execute lights in range with HS queued")
eq(tui.frame.hold.fade.target, 1, "TBC: the queued spend shows the hold overlay")
eq(tui.frame.hold.text.text, "CANCEL", "TBC: the overlay reads CANCEL, not RIDE")
TST.hs_queued = false
tbc.cooldowns = {}
tbc.target_health = { 100, 100 }

--=========================================================================================
-- 4b) The Era family (1.15.9 fury): six slots, BT/WW reads, the 30 floor, the
-- 2.5 s window, Execute spam, the gated display
--=========================================================================================
local era = build({ project = 2, interface = 11509, era = true,
    known_spells = { [18499] = true } })
eq(era.st.family, "ERA", "the Classic project id maps to ERA")
local EST, est = era.ST, era.st
check(type(est.warrior_guide) == "table", "the Era sandbox loads the pure engine")

EST.in_combat = true
EST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
EST.gcd = { expires = 0 }
EST.WARRIOR.post_init(EST)
local eui = est.nextaction_ui
check(eui.frame ~= nil, "Era post_init builds the guide frame through the real hook")
eq(eui.get_provider(EST), EST.WARRIOR.guide, "the Era guide resolves as the frame's provider")

local eslots = EST.WARRIOR.guide.slots
eq(#eslots, 13, "Era declares the seven core slots plus the utility spine's six rows")
eq(#eslots, 13, "the Era slot set is the seven core slots plus the utility spine's six rows")
local eexpected_keys = { "op", "execute", "slam", "hs", "bt", "ww", "hamstring" }
for i = 1, #eexpected_keys do
    eq(eslots[i].key, eexpected_keys[i], "Era slot " .. i .. " is " .. eexpected_keys[i])
    eq(eslots[i].cooldown_key, eexpected_keys[i],
        "Era slot " .. eexpected_keys[i] .. " carries its cooldown_key")
    eq(eslots[i].swipe_duration, 1.5,
        "Era slot " .. eexpected_keys[i] .. " carries the GCD-length swipe fallback")
end
eq(eslots[1].spell_id, 7384, "Era op keeps the Overpower rank-1 id")
eq(eslots[2].spell_id, 5308, "Era execute keeps the Execute rank-1 id")
eq(eslots[3].spell_id, 11605, "Era post_init resolved slam to the vanilla rank")
eq(eslots[4].spell_id, 25286, "Era post_init resolved hs to the shared rank")
eq(eslots[5].spell_id, 23884, "Era post_init resolved bt to the vanilla rank")
eq(eslots[6].spell_id, 1680, "Era post_init resolved ww to the sim-cited base id")
eq(eslots[7].spell_id, 18499, "Era post_init resolved hamstring to the known TBC rank")

eq(#eui.icons, 13, "the Era frame holds one icon per slot")
eq(era.frames, 40, "Era frame count: group + the slots' icons/borders/cooldowns + hold")
for i = 1, #eslots do
    eq(eui.icons[i].slot, eslots[i], "Era icon " .. i .. " follows the slot declaration order")
end
eq(eui.icons[5].icon.texture.texture, "icon_bt_era",
    "the bt icon shows the Era rank's texture")
eq(eui.icons[6].icon.texture.texture, "icon_ww_r1",
    "the ww icon shows the rank-1 art (rank-invariant)")
eq(eui.icons[5].remaining_key, "bt_remaining", "the Era BT swipe field names are derived")
eq(eui.icons[6].expires_key, "ww_expires", "the Era WW expiry field name is derived")

-- The Era HUD mirrors the guide (seven abilities plus the two trinkets).
do
    local hslots = EST.WARRIOR.HUD_SLOTS
    eq(#hslots, 9, "Era HUD: seven ability slots plus the two trinkets")
    local hkeys = { "op", "execute", "slam", "hs", "bt", "ww", "hamstring",
        "trinket1", "trinket2" }
    for i = 1, #hkeys do
        eq(hslots[i].key, hkeys[i], "Era HUD slot " .. i .. " is " .. hkeys[i])
    end
end

-- The legacy (non-core) contrast gains the new inputs: still nil there.
do
    local legacy = ST.WARRIOR.guide.gather(ST, {})
    eq(legacy.core_reserve_window, nil, "non-core gather feeds no reserve window")
    eq(legacy.execute_spam, nil, "non-core gather feeds no spam flag")
    eq(legacy.hamstring_rage_threshold, nil, "non-core gather feeds no weave threshold")
    eq(legacy.rend_upkeep_enabled, nil, "non-core gather feeds no Rend enable")
    eq(legacy.sunder_stacks, nil, "non-core gather feeds no Sunder upkeep")
end

-- Every Era action output names a declared slot (through the real provider).
do
    local provider = EST.WARRIOR.guide
    local function eaction_of(overrides)
        local inputs = { swing_remaining = 2.0, rage = 60, hs_cost = 15,
            target_health_pct = 100, execute_pct = 20, hs_rage_floor = 40,
            core_reserve_window = 2.5, execute_spam = true }
        for k, v in pairs(overrides or {}) do
            if v == NONE then
                inputs[k] = nil
            else
                inputs[k] = v
            end
        end
        local out = {}
        provider.evaluate(inputs, out)
        return out.action
    end
    eq(eaction_of({ bt_remaining = 0, ww_remaining = 0 }), "bt",
        "the Era provider delegates to the pure engine (bt)")
    eq(eaction_of({ bt_remaining = 4, ww_remaining = 0 }), "ww",
        "the Era provider delegates to the pure engine (ww)")
    eq(eaction_of({ bt_remaining = 4, ww_remaining = 6 }), "hs",
        "the Era provider delegates to the pure engine (hs)")
    eq(eaction_of({ bt_remaining = 4, ww_remaining = 6, rage = 20 }), nil,
        "the Era provider delegates to the pure engine (floor withhold)")
    eq(eaction_of({ target_health_pct = 10, bt_remaining = 0, ww_remaining = 0,
        rage = 60 }), "execute",
        "the Era provider delegates to the pure engine (spam over BT)")
    local eactions = { "bt", "ww", "hs", "execute", "op", "slam", "hamstring" }
    local eall_resolve = true
    for i = 1, #eactions do
        if eui.slot_index[eactions[i]] == nil then
            eall_resolve = false
        end
    end
    check(eall_resolve, "every action the Era engine can return names a declared slot")
end

-- The Era gather into the caller-owned reused table.
era.clock = 100
EST.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
EST.gcd = { expires = 100.5 }
EST.hs_queued = false
EST.cleave_queued = false
EST.insufficient_rage = false
EST.has_bloodsurge = false
EST.warrior_slam_casting = false
EST.warrior_overpower_proc_until = nil
era.power = 60
era.target_health = { 150, 1000 }
era.cooldowns = { [23884] = { 98, 6 } }
era.rage_cost = { { cost = 15 } }
era.cost_by_id = { [25286] = 15, [25231] = 15, [23884] = 30, [1680] = 25 }

local egathered_target = {}
local egathered = EST.WARRIOR.guide.gather(EST, egathered_target)
eq(egathered, egathered_target, "Era gather writes into and returns the caller's table")
near(egathered.bt_remaining, 4.0, 1e-9, "Era gather: bt_remaining from a real cooldown")
eq(egathered.bt_duration, 6, "Era gather: the real BT length is latched")
eq(egathered.ww_remaining, 0, "Era gather: no WW cooldown reads as ready")
eq(egathered.ww_duration, nil, "Era gather: no WW cooldown latches no duration")
eq(egathered.bt_cost, 30, "Era gather: the BT rage cost")
eq(egathered.ww_cost, 25, "Era gather: the WW rage cost")
eq(egathered.hs_cost, 15, "Era gather: the HS rage cost")
eq(egathered.hs_rage_floor, 40, "Era gather: the 40-rage HS floor")
eq(egathered.core_reserve_window, 2.5, "Era gather: the 2.5 s reserve window")
eq(egathered.execute_spam, true, "Era gather: the spam flag")
eq(egathered.hamstring_known, true, "Era gather: the Hamstring weave flag")
eq(egathered.hamstring_remaining, 0, "Era gather: the known Hamstring reads ready (no cooldown of its own)")
eq(egathered.hamstring_duration, nil, "Era gather: the known Hamstring latches no duration")
eq(egathered.hamstring_rage_threshold, 80, "Era gather: the 80-rage weave threshold")
eq(egathered.rend_upkeep_enabled, nil, "Era gather: no Rend enable outside SoD")
near(egathered.target_health_pct, 15, 1e-9, "Era gather: target health percentage")

-- The GCD echo is filtered on the new readers too, and stale fields clear.
era.cooldowns = { [23884] = { 100, 1.5 }, [1680] = { 100, 1.5 } }
EST.WARRIOR.guide.gather(EST, egathered_target)
eq(egathered_target.bt_remaining, 0, "Era gather: the BT GCD echo is filtered")
eq(egathered_target.bt_duration, nil, "Era gather: the BT echo latches no duration")
eq(egathered_target.ww_remaining, 0, "Era gather: the WW GCD echo is filtered")
era.cooldowns = { [23884] = { 98, 6 } }
EST.WARRIOR.guide.gather(EST, egathered_target)
era.cooldowns = {}
EST.WARRIOR.guide.gather(EST, egathered_target)
eq(egathered_target.bt_remaining, 0, "Era gather: the dropped BT cooldown reads ready")
eq(egathered_target.bt_duration, nil, "Era gather: the dropped BT cooldown clears")
eq(egathered_target.core_reserve_window, 2.5, "Era gather: the window survives a cooldown drop")
eq(egathered_target.execute_spam, true, "Era gather: the spam flag survives a cooldown drop")
eq(egathered_target.hs_rage_floor, 40, "Era gather: the floor survives a cooldown drop")

-- The Era display mapping through the real frame and the real hooks.
EST.mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false }
EST.gcd = { expires = 0 }
EST.warrior_overpower_proc_until = nil
EST.has_bloodsurge = false
EST.hs_queued = false
EST.cleave_queued = false
EST.insufficient_rage = false
EST.warrior_slam_casting = false
era.power = 60
era.rage_cost = { { cost = 15 } }
era.target_health = { 100, 100 }
era.cooldowns = {}
era.clock = 200

local function etick(advance)
    EST.mainhand.ends_at = era.clock + 3.0
    era.advance(advance or 0.1)
    EST.WARRIOR.on_bar_update(EST, "mainhand")
end
local function etarget(key)
    return eui.icons[eui.slot_index[key]].fade.target
end

-- BT ready (no cooldown) lights the BT slot.
etick()
eq(etarget("bt"), 1, "Era: a ready Bloodthirst lights the BT slot through the real hook")
eq(etarget("hs"), 0, "Era: HS stays dark while BT is ready")
eq(etarget("ww"), 0, "Era: WW stays dark while BT is ready")

-- Execute range with BT ready: still Execute (spam, unlike the TBC reservation).
era.target_health = { 150, 1000 }
etick()
eq(etarget("execute"), 1, "Era: Execute spams in range even with BT ready")
eq(etarget("bt"), 0, "Era: BT fades while Execute spams")

-- BT cooling, WW ready -> WW (outside Execute range).
era.target_health = { 100, 100 }
era.cooldowns = { [23884] = { era.clock, 6 } }
etick()
eq(etarget("ww"), 1, "Era: WW lights while BT cools down")
eq(etarget("bt"), 0, "Era: BT fades while cooling")

-- Both core abilities cooling, rage to spare -> HS.
era.cooldowns = { [23884] = { era.clock, 6 }, [1680] = { era.clock, 10 } }
etick()
eq(etarget("hs"), 1, "Era: HS dumps with the core cooling and rage to spare")

-- Same, rage below the 40 floor -> nothing, and no hold overlay.
era.power = 20
etick()
eq(etarget("hs"), 0, "Era: HS withholds below the 40-rage floor")
eq(eui.frame.hold.fade.target, 0, "Era: the floor withhold shows no hold overlay")
era.power = 60

-- Execute range, rage short, BT landing inside the window -> still Execute (spam).
era.target_health = { 150, 1000 }
era.power = 40
era.cooldowns = { [23884] = { era.clock - 5, 6 }, [11585] = { era.clock, 10 } }
etick()
eq(etarget("execute"), 1, "Era: Execute spams even when BT lands with rage short")
era.power = 60
era.cooldowns = {}
era.target_health = { 100, 100 }

-- OP window outranks the Era core.
EST.warrior_overpower_proc_until = era.clock + 5
etick()
eq(etarget("op"), 1, "Era: the OP window lights Overpower over BT")
EST.warrior_overpower_proc_until = nil
etick()
eq(etarget("bt"), 1, "Era: clearing the OP window returns to BT")

-- Hamstring weave: rage above the 80 threshold with the core cooling.
era.power = 90
era.cooldowns = { [23884] = { era.clock, 6 }, [1680] = { era.clock, 10 } }
etick()
eq(etarget("hamstring"), 1, "Era: rage above 80 weaves Hamstring with the core cooling")
eq(etarget("hs"), 0, "Era: HS stays dark while the weave fires")
era.power = 60
era.cooldowns = {}
etick()
eq(etarget("bt"), 1, "Era: rage back below 80 returns to BT")

--=========================================================================================
-- 4c) The Wrath arms branch (Mortal Strike known): six slots op/execute/rend/ms/
-- bladestorm/hs, the upkeep/cooldown readers, the wrath_arms flag, the gated
-- display. BT/WW/Slam readers stay nil (no arms rule names them).
--=========================================================================================
local arms_sb = build({ known_spells = { [47486] = true, [63784] = true } ,
    arms = true })
eq(arms_sb.st.family, "WRATH", "the arms sandbox runs the Wrath family")
local AST, ast = arms_sb.ST, arms_sb.st
check(type(ast.warrior_guide) == "table", "the arms sandbox loads the pure engine")

AST.in_combat = true
AST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
AST.gcd = { expires = 0 }
AST.WARRIOR.post_init(AST)
local aui = ast.nextaction_ui
check(aui.frame ~= nil, "arms post_init builds the guide frame through the real hook")
eq(aui.get_provider(AST), AST.WARRIOR.guide, "the arms guide resolves as the frame's provider")
eq(AST.warrior_is_arms, true, "Mortal Strike known freezes the arms branch")
eq(AST.warrior_is_sod, false, "no runes freezes no SoD flag on Wrath")

local aslots = AST.WARRIOR.guide.slots
eq(#aslots, 8, "arms declares the six core slots plus the utility spine's two rows")
local aexpected_keys = { "op", "execute", "rend", "ms", "bladestorm", "hs" }
for i = 1, #aexpected_keys do
    eq(aslots[i].key, aexpected_keys[i], "arms slot " .. i .. " is " .. aexpected_keys[i])
    eq(aslots[i].cooldown_key, aexpected_keys[i],
        "arms slot " .. aexpected_keys[i] .. " carries its cooldown_key")
end
eq(aslots[3].spell_id, 47465, "arms post_init resolved rend to the WotLK rank")
eq(aslots[4].spell_id, 47486, "arms post_init resolved ms to the WotLK rank")
eq(aslots[5].spell_id, 63784, "arms bladestorm keeps its single id")
eq(aslots[5].swipe_duration, 90, "arms bladestorm carries the 90 s swipe fallback")
eq(#aui.icons, 8, "the arms frame holds one icon per slot")
eq(arms_sb.frames, 26, "arms frame count: group + the slots' icons/borders/cooldowns + hold")
eq(aui.icons[3].icon.texture.texture, "icon_rend",
    "the rend icon shows the WotLK rank's texture")
eq(aui.icons[4].icon.texture.texture, "icon_ms",
    "the ms icon shows the WotLK rank's texture")

-- The fury contrast: no Mortal Strike known stays fury (proved by the default
-- sandbox above: six fury slots, wrath_fury true).
eq(ST.warrior_is_arms, false, "no Mortal Strike known freezes the fury branch")
eq(ST.WARRIOR.guide.slots[5].key, "bt", "fury keeps the BT slot")

-- The arms HUD mirrors the arms guide (six abilities plus the two trinkets).
do
    local hslots = AST.WARRIOR.HUD_SLOTS
    eq(#hslots, 8, "arms HUD: six ability slots plus the two trinkets")
    local hkeys = { "op", "execute", "rend", "ms", "bladestorm", "hs",
        "trinket1", "trinket2" }
    for i = 1, #hkeys do
        eq(hslots[i].key, hkeys[i], "arms HUD slot " .. i .. " is " .. hkeys[i])
    end
end

-- Every arms action output names a declared slot (through the real provider).
do
    local provider = AST.WARRIOR.guide
    local function aaction_of(overrides)
        local inputs = { swing_remaining = 2.0, rage = 60, hs_cost = 15,
            target_health_pct = 100, execute_pct = 20, wrath_arms = true }
        for k, v in pairs(overrides or {}) do
            if v == NONE then
                inputs[k] = nil
            else
                inputs[k] = v
            end
        end
        local out = {}
        provider.evaluate(inputs, out)
        return out.action
    end
    eq(aaction_of({ rend_remaining = nil }), "rend",
        "the arms provider delegates to the pure engine (rend)")
    eq(aaction_of({ rend_remaining = 10, sudden_death = true }), "execute",
        "the arms provider delegates to the pure engine (SD execute)")
    eq(aaction_of({ rend_remaining = 10, tfb = true }), "op",
        "the arms provider delegates to the pure engine (TfB op)")
    eq(aaction_of({ rend_remaining = 10, ms_remaining = 0,
        bladestorm_remaining = 5, bladestorm_known = true }), "ms",
        "the arms provider delegates to the pure engine (ms)")
    eq(aaction_of({ rend_remaining = 10, ms_remaining = 5,
        bladestorm_remaining = 0, bladestorm_known = true }), "bladestorm",
        "the arms provider delegates to the pure engine (bladestorm)")
    local aactions = { "rend", "execute", "op", "bladestorm", "ms", "hs" }
    local aall_resolve = true
    for i = 1, #aactions do
        if aui.slot_index[aactions[i]] == nil then
            aall_resolve = false
        end
    end
    check(aall_resolve, "every action the arms engine can return names a declared slot")
end

-- The arms gather into the caller-owned reused table.
arms_sb.clock = 100
AST.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
AST.gcd = { expires = 100.5 }
AST.hs_queued = false
AST.cleave_queued = false
AST.insufficient_rage = false
AST.has_bloodsurge = false
AST.warrior_slam_casting = false
AST.warrior_overpower_proc_until = nil
AST.has_sudden_death = false
AST.has_tfb = false
arms_sb.power = 60
arms_sb.target_health = { 100, 100 }
arms_sb.cooldowns = {}
arms_sb.rage_cost = { { cost = 15 } }
arms_sb.cost_by_id = { [47450] = 15, [47520] = 15 }

local agathered_target = {}
local agathered = AST.WARRIOR.guide.gather(AST, agathered_target)
eq(agathered, agathered_target, "arms gather writes into and returns the caller's table")
eq(agathered.wrath_arms, true, "arms gather: the frozen arms flag")
eq(agathered.wrath_fury, nil, "arms gather: no fury flag")
eq(agathered.sod, nil, "arms gather: no SoD flag")
eq(agathered.bt_remaining, nil, "arms gather: no BT reader (no arms rule names it)")
eq(agathered.ww_remaining, nil, "arms gather: no WW reader")
eq(agathered.slam_remaining, 0, "arms gather: the Slam swipe reader stays (no rule names it)")
eq(agathered.hs_rage_floor, 50, "arms gather: the 50-rage dump floor")
eq(agathered.execute_spam, nil, "arms gather: no spam flag (rule B needs none)")
eq(agathered.rend_remaining, nil, "arms gather: no Rend aura reads as nil (missing)")
eq(agathered.ms_remaining, 0, "arms gather: no MS cooldown reads as ready")
eq(agathered.bladestorm_known, true, "arms gather: the Bladestorm talent probe answers")
eq(agathered.hamstring_rage_threshold, nil, "arms gather: no weave threshold on arms")
eq(agathered.rend_upkeep_enabled, nil, "arms gather: no Rend enable outside SoD")
eq(agathered.raging_blow_remaining, nil, "arms gather: no Raging Blow reader")
eq(agathered.sudden_death, nil, "arms gather: no SD aura reads as nil")
eq(agathered.tfb, nil, "arms gather: no TfB aura reads as nil")

-- The GCD echo is filtered on the new readers too.
arms_sb.cooldowns = { [47486] = { 100, 1.5 }, [63784] = { 100, 1.5 } }
AST.WARRIOR.guide.gather(AST, agathered_target)
eq(agathered_target.ms_remaining, 0, "arms gather: the MS GCD echo is filtered")
eq(agathered_target.bladestorm_remaining, 0, "arms gather: the Bladestorm GCD echo is filtered")

-- The arms display mapping through the real frame and the real hooks.
AST.mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false }
AST.gcd = { expires = 0 }
AST.warrior_overpower_proc_until = nil
AST.has_bloodsurge = false
AST.has_sudden_death = false
AST.has_tfb = false
AST.hs_queued = false
AST.cleave_queued = false
AST.insufficient_rage = false
AST.warrior_slam_casting = false
arms_sb.power = 60
arms_sb.rage_cost = { { cost = 15 } }
arms_sb.cost_by_id = nil
arms_sb.target_health = { 100, 100 }
arms_sb.cooldowns = {}
arms_sb.clock = 200

local function atick(advance)
    AST.mainhand.ends_at = arms_sb.clock + 3.0
    arms_sb.advance(advance or 0.1)
    AST.WARRIOR.on_bar_update(AST, "mainhand")
end
local function atarget(key)
    return aui.icons[aui.slot_index[key]].fade.target
end

-- No Rend aura (UnitAura stub answers nil): Rend upkeep lights first.
atick()
eq(atarget("rend"), 1, "arms: a missing Rend lights the Rend slot through the real hook")
eq(atarget("ms"), 0, "arms: MS stays dark while Rend is missing")

-- MS ready with no cooldowns: Rend still missing, so still Rend (upkeep first).
arms_sb.cooldowns = { [47486] = { arms_sb.clock, 6 } }
atick()
eq(atarget("rend"), 1, "arms: Rend upkeep outranks a cooling MS")

--=========================================================================================
-- 4d) The SoD branch (ERA + Raging Blow known): six slots
-- execute/slam/hs/bt/ww/raging_blow, floor 60, the spam flag, the sod flag.
--=========================================================================================
local sod_sb = build({ project = 2, interface = 11509, era = true,
    known_spells = { [402911] = true }, sod_runes = true })
eq(sod_sb.st.family, "ERA", "the SoD sandbox runs the ERA family")
local SST, sst = sod_sb.ST, sod_sb.st

SST.in_combat = true
SST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
SST.gcd = { expires = 0 }
SST.WARRIOR.post_init(SST)
local sui = sst.nextaction_ui
check(sui.frame ~= nil, "SoD post_init builds the guide frame through the real hook")
eq(SST.warrior_is_sod, true, "Raging Blow known freezes the SoD branch")
eq(SST.warrior_is_arms, false, "no Mortal Strike known freezes no arms flag on SoD")

local sslots = SST.WARRIOR.guide.slots
eq(#sslots, 12, "SoD declares the eight core slots plus the utility spine's four rows")
local sexpected_keys = { "execute", "slam", "hs", "bt", "ww", "raging_blow",
    "rend", "op" }
for i = 1, #sexpected_keys do
    eq(sslots[i].key, sexpected_keys[i], "SoD slot " .. i .. " is " .. sexpected_keys[i])
    eq(sslots[i].cooldown_key, sexpected_keys[i],
        "SoD slot " .. sexpected_keys[i] .. " carries its cooldown_key")
end
eq(sslots[6].spell_id, 402911, "SoD raging_blow keeps the rune id")
eq(sslots[6].swipe_duration, 8, "SoD raging_blow carries the 8 s swipe fallback")
eq(sslots[7].spell_id, 772, "SoD rend keeps the rank-1 fallback (no Rend book entry)")
eq(sslots[7].swipe_duration, 1.5, "SoD rend carries the GCD-length swipe fallback")
eq(sslots[8].spell_id, 7384, "SoD op keeps the Overpower rank-1 id")
eq(#sui.icons, 12, "the SoD frame holds one icon per slot")
eq(sod_sb.frames, 36, "SoD frame count: group + the slots' icons/borders/cooldowns + hold")
eq(sui.icons[6].icon.texture.texture, "icon_raging",
    "the raging icon shows the rune texture")

-- The Era-base contrast (no runes) keeps the op slot and floor 30.
eq(EST.warrior_is_sod, false, "no runes freezes Era-base (no SoD flag)")
eq(EST.WARRIOR.guide.slots[1].key, "op", "Era-base keeps the op slot")

-- The SoD HUD mirrors the SoD guide (eight abilities plus the two trinkets).
do
    local hslots = SST.WARRIOR.HUD_SLOTS
    eq(#hslots, 10, "SoD HUD: eight ability slots plus the two trinkets")
    local hkeys = { "execute", "slam", "hs", "bt", "ww", "raging_blow",
        "rend", "op", "trinket1", "trinket2" }
    for i = 1, #hkeys do
        eq(hslots[i].key, hkeys[i], "SoD HUD slot " .. i .. " is " .. hkeys[i])
    end
end

-- Every SoD action output names a declared slot (through the real provider).
do
    local provider = SST.WARRIOR.guide
    local function saction_of(overrides)
        local inputs = { swing_remaining = 2.0, rage = 70, hs_cost = 15,
            target_health_pct = 100, execute_pct = 20, hs_rage_floor = 60,
            execute_spam = true, sod = true }
        for k, v in pairs(overrides or {}) do
            if v == NONE then
                inputs[k] = nil
            else
                inputs[k] = v
            end
        end
        local out = {}
        provider.evaluate(inputs, out)
        return out.action
    end
    eq(saction_of({ sudden_death = true }), "execute",
        "the SoD provider delegates to the pure engine (SD execute)")
    eq(saction_of({ has_bloodsurge = true, bt_remaining = 3,
        ww_remaining = 4 }), "slam",
        "the SoD provider delegates to the pure engine (slam)")
    eq(saction_of({ bt_remaining = 0 }), "bt",
        "the SoD provider delegates to the pure engine (bt)")
    eq(saction_of({ bt_remaining = 3, ww_remaining = 0 }), "ww",
        "the SoD provider delegates to the pure engine (ww)")
    eq(saction_of({ bt_remaining = 3, ww_remaining = 4,
        raging_blow_remaining = 0 }), "raging_blow",
        "the SoD provider delegates to the pure engine (raging)")
    local sactions = { "execute", "slam", "bt", "ww", "raging_blow", "hs",
        "rend", "op" }
    local sall_resolve = true
    for i = 1, #sactions do
        if sui.slot_index[sactions[i]] == nil then
            sall_resolve = false
        end
    end
    check(sall_resolve, "every action the SoD engine can return names a declared slot")
end

-- The SoD Rend enable (rune 412507 known): the gather feeds true, the
-- missing Rend prompts through the real provider, the frame lights the rend
-- slot. Without the rune the same tick stays dormant (pinned above).
do
    local rune_sb = build({ project = 2, interface = 11509, era = true,
        known_spells = { [402911] = true, [412507] = true }, sod_runes = true })
    local RST = rune_sb.ST
    RST.in_combat = true
    RST.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
    RST.gcd = { expires = 0 }
    RST.WARRIOR.post_init(RST)
    eq(RST.warrior_has_sod_rend_rune, true, "SoD+rune: the Rend rune freezes on")
    rune_sb.clock = 100
    rune_sb.power = 70
    rune_sb.target_health = { 100, 100 }
    rune_sb.rage_cost = { { cost = 15 } }
    local rgathered = RST.WARRIOR.guide.gather(RST, {})
    eq(rgathered.rend_upkeep_enabled, true, "SoD+rune gather: the Rend enable rides")
    eq(rgathered.rend_remaining, nil, "SoD+rune gather: no target Rend reads as missing")
    eq(RST.WARRIOR.guide.evaluate(rgathered, {}).action, "rend",
        "SoD+rune provider: a missing Rend prompts Rend")
    -- The gated display through the real hook: Rend lights, no hold overlay.
    RST.mainhand.ends_at = rune_sb.clock + 3.0
    rune_sb.advance(0.1)
    RST.WARRIOR.on_bar_update(RST, "mainhand")
    local rui = rune_sb.st.nextaction_ui
    eq(rui.icons[rui.slot_index["rend"]].fade.target, 1,
        "SoD+rune: a missing Rend lights the Rend slot through the real hook")
    eq(rui.frame.hold.fade.target, 0, "SoD+rune: the Rend upkeep shows no hold overlay")
    -- The rune alone never widens SoD detection (pinned in warrior_state.lua
    -- too): ERA + 412507 without a SoD rune stays Era-base.
    local alone_sb = build({ project = 2, interface = 11509, era = true,
        known_spells = { [412507] = true } })
    local AST2 = alone_sb.ST
    AST2.WARRIOR.post_init(AST2)
    eq(AST2.warrior_is_sod, false, "rune-alone: no SoD branch without a SoD rune")
    eq(AST2.WARRIOR.guide.gather(AST2, {}).rend_upkeep_enabled, nil,
        "rune-alone gather: no Rend enable outside SoD")
end

-- The SoD gather into the caller-owned reused table.
sod_sb.clock = 100
SST.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
SST.gcd = { expires = 100.5 }
SST.hs_queued = false
SST.cleave_queued = false
SST.insufficient_rage = false
SST.has_bloodsurge = false
SST.warrior_slam_casting = false
SST.warrior_overpower_proc_until = nil
sod_sb.power = 70
sod_sb.target_health = { 150, 1000 }
sod_sb.cooldowns = {}
sod_sb.rage_cost = { { cost = 15 } }
sod_sb.cost_by_id = { [25286] = 15, [25231] = 15, [23884] = 30, [1680] = 25 }

local sgathered_target = {}
local sgathered = SST.WARRIOR.guide.gather(SST, sgathered_target)
eq(sgathered, sgathered_target, "SoD gather writes into and returns the caller's table")
eq(sgathered.sod, true, "SoD gather: the frozen SoD flag")
eq(sgathered.wrath_fury, nil, "SoD gather: no fury flag")
eq(sgathered.wrath_arms, nil, "SoD gather: no arms flag")
eq(sgathered.hs_rage_floor, 60, "SoD gather: the 60-rage pool floor")
eq(sgathered.core_reserve_window, 2.5, "SoD gather: the Era-carried window")
eq(sgathered.execute_spam, true, "SoD gather: the spam flag")
eq(sgathered.bt_remaining, 0, "SoD gather: no BT cooldown reads as ready")
eq(sgathered.bt_cost, 30, "SoD gather: the BT rage cost")
eq(sgathered.ww_cost, 25, "SoD gather: the WW rage cost")
eq(sgathered.raging_blow_remaining, 0, "SoD gather: no Raging Blow cooldown reads as ready")
eq(sgathered.rend_remaining, nil, "SoD gather: no Rend reader")
eq(sgathered.rend_upkeep_enabled, nil, "SoD gather: no Rend enable without the rune")
eq(sgathered.hamstring_rage_threshold, nil, "SoD gather: no weave threshold on SoD")
eq(sgathered.ms_remaining, nil, "SoD gather: no MS reader")
near(sgathered.target_health_pct, 15, 1e-9, "SoD gather: target health percentage")

-- The SoD display mapping: floor withhold, then the pool clearing it.
SST.mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false }
SST.gcd = { expires = 0 }
SST.warrior_overpower_proc_until = nil
SST.has_bloodsurge = false
SST.hs_queued = false
SST.cleave_queued = false
SST.insufficient_rage = false
SST.warrior_slam_casting = false
sod_sb.power = 50
sod_sb.rage_cost = { { cost = 15 } }
sod_sb.cost_by_id = nil
sod_sb.target_health = { 100, 100 }
sod_sb.cooldowns = { [23884] = { sod_sb.clock, 6 }, [1680] = { sod_sb.clock, 10 },
    [402911] = { sod_sb.clock, 8 } }
sod_sb.clock = 200

local function stick(advance)
    SST.mainhand.ends_at = sod_sb.clock + 3.0
    sod_sb.advance(advance or 0.1)
    SST.WARRIOR.on_bar_update(SST, "mainhand")
end
local function starget(key)
    return sui.icons[sui.slot_index[key]].fade.target
end

-- Core cooling, rage 50 below the 60 pool floor: nothing, no hold.
stick()
eq(starget("hs"), 0, "SoD: HS withholds below the 60-rage pool floor")
eq(starget("raging_blow"), 0, "SoD: Raging Blow withholds while cooling")
eq(sui.frame.hold.fade.target, 0, "SoD: the pool withhold shows no hold overlay")
sod_sb.power = 70
sod_sb.cooldowns = {}
stick()
eq(starget("bt"), 1, "SoD: a ready Bloodthirst lights the BT slot through the real hook")

--=========================================================================================
-- 4e) The Forever family (1.60.x): the base five-slot set, Victory Rush known +
-- usable -> the engine's Execute bypass at any health, inert otherwise
--=========================================================================================
do
    local function ready_usable() return true end
    local function spent_usable() return false end
    local fkeys = { [34428] = true }
    local forever_sb = build({ project = 18, interface = 16001, forever = true,
        known_spells = fkeys, spell_usable = ready_usable })
    eq(forever_sb.st.family, "FOREVER", "the Forever project id maps to FOREVER")
    local FST = forever_sb.ST
    FST.in_combat = true
    FST.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
    FST.gcd = { expires = 0 }
    FST.hs_queued = false
    FST.cleave_queued = false
    FST.insufficient_rage = false
    FST.has_bloodsurge = false
    FST.warrior_slam_casting = false
    FST.warrior_overpower_proc_until = nil
    forever_sb.clock = 100
    forever_sb.power = 60
    forever_sb.target_health = { 100, 100 }
    forever_sb.rage_cost = { { cost = 15 } }
    FST.WARRIOR.post_init(FST)
    local fui = forever_sb.st.nextaction_ui
    check(fui.frame ~= nil, "Forever post_init builds the guide frame through the real hook")

    -- Victory Rush reuses the execute slot; Hamstring rides the base set's
    -- sixth slot (room existed there); Sunder upkeep takes the seventh.
    local fslots = FST.WARRIOR.guide.slots
    eq(#fslots, 13, "Forever declares the seven core slots plus the utility spine's six rows")
    local fexpected = { "op", "execute", "slam", "hs", "cleave", "hamstring",
        "sunder" }
    for i = 1, #fexpected do
        eq(fslots[i].key, fexpected[i], "Forever slot " .. i .. " is " .. fexpected[i])
    end
    eq(#fui.icons, 13, "the Forever frame holds one icon per slot")
    eq(fslots[6].spell_id, 7373, "Forever: the Hamstring slot keeps the rank-1 fallback")
    eq(fslots[7].spell_id, 7386, "Forever: the Sunder slot keeps the rank-1 fallback")
    eq(fslots[7].cooldown_key, "sunder", "Forever: the Sunder slot carries its cooldown_key")
    -- The Forever HUD mirrors the Forever guide (seven plus the two trinkets).
    do
        local fhud = FST.WARRIOR.HUD_SLOTS
        eq(#fhud, 9, "Forever HUD: seven ability slots plus the two trinkets")
        local fhkeys = { "op", "execute", "slam", "hs", "cleave", "hamstring",
            "sunder", "trinket1", "trinket2" }
        for i = 1, #fhkeys do
            eq(fhud[i].key, fhkeys[i], "Forever HUD slot " .. i .. " is " .. fhkeys[i])
        end
    end

    -- Known + usable: the gather feeds victory_rush, and the provider prompts
    -- Execute at full health through the real engine.
    local freused = {}
    local fgathered = FST.WARRIOR.guide.gather(FST, freused)
    eq(fgathered, freused, "Forever gather writes into the caller's table")
    eq(fgathered.victory_rush, true, "Forever gather: known + usable Victory Rush reads ready")
    eq(fgathered.hs_cancel_cue, nil, "Forever gather: no TBC HS-cancel cue")
    eq(fgathered.bt_remaining, nil, "Forever gather: no BT reader")
    eq(fgathered.hs_rage_floor, nil, "Forever gather: no HS floor")
    eq(fgathered.execute_spam, nil, "Forever gather: no Execute spam")
    eq(fgathered.hamstring_known, nil, "Forever gather: no Hamstring flag without the spellbook")
    eq(fgathered.hamstring_remaining, 0, "Forever gather: the unlearned Hamstring reads ready")
    eq(fgathered.hamstring_duration, nil, "Forever gather: the unlearned Hamstring latches no duration")
    eq(fgathered.hamstring_rage_threshold, nil, "Forever gather: no weave threshold (toggle filed)")
    eq(fgathered.rend_upkeep_enabled, nil, "Forever gather: no Rend enable (toggle filed)")
    eq(fgathered.sunder_stacks, nil, "Forever gather: no Sunder aura reads nil")
    eq(fgathered.sunder_remaining, nil, "Forever gather: no Sunder countdown reads nil")
    local fout = FST.WARRIOR.guide.evaluate(fgathered, {})
    eq(fout.action, "execute", "Forever provider: Victory Rush prompts Execute at 100 % health")
    eq(fout.hold, false, "Forever provider: the VR prompt carries no overlay")

    -- The gated display through the real hook: Execute lights, no hold overlay.
    FST.mainhand.ends_at = forever_sb.clock + 3.0
    forever_sb.advance(0.1)
    FST.WARRIOR.on_bar_update(FST, "mainhand")
    eq(fui.icons[fui.slot_index["execute"]].fade.target, 1,
        "Forever: Execute lights with Victory Rush ready")
    eq(fui.frame.hold.fade.target, 0, "Forever: the VR prompt shows no hold overlay")

    -- A VR-negative client overwrites the stale flag on the same table.
    local neg_sb = build({ project = 18, interface = 16001, forever = true,
        known_spells = fkeys, spell_usable = spent_usable })
    local NST = neg_sb.ST
    NST.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
    NST.gcd = { expires = 0 }
    neg_sb.clock = 100
    neg_sb.power = 60
    neg_sb.target_health = { 100, 100 }
    neg_sb.rage_cost = { { cost = 15 } }
    local neg_gathered = NST.WARRIOR.guide.gather(NST, freused)
    eq(neg_gathered, freused, "the reused table is the same table")
    eq(neg_gathered.victory_rush, nil, "an unusable Victory Rush overwrites the stale flag")
    eq(NST.WARRIOR.guide.evaluate(neg_gathered, {}).action, "hs",
        "an unusable Victory Rush falls through to the HS fallback")

    -- Unknown to the client: the id probe fails safe to nil (never prompts).
    local unknown_sb = build({ project = 18, interface = 16001, forever = true,
        spell_usable = ready_usable })
    local UST = unknown_sb.ST
    UST.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
    UST.gcd = { expires = 0 }
    unknown_sb.clock = 100
    unknown_sb.power = 60
    unknown_sb.target_health = { 100, 100 }
    unknown_sb.rage_cost = { { cost = 15 } }
    local unknown_gathered = UST.WARRIOR.guide.gather(UST, {})
    eq(unknown_gathered.victory_rush, nil, "an unknown Victory Rush id reads nil")
    eq(UST.WARRIOR.guide.evaluate(unknown_gathered, {}).action, "hs",
        "an unknown Victory Rush id falls through to the HS fallback")

    -- No usability probe at all: unknown degrades to nil, never to usable.
    local noprobe_sb = build({ project = 18, interface = 16001, forever = true,
        known_spells = fkeys })
    local PST = noprobe_sb.ST
    PST.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
    PST.gcd = { expires = 0 }
    noprobe_sb.clock = 100
    noprobe_sb.power = 60
    noprobe_sb.target_health = { 100, 100 }
    noprobe_sb.rage_cost = { { cost = 15 } }
    local noprobe_gathered = PST.WARRIOR.guide.gather(PST, {})
    eq(noprobe_gathered.victory_rush, nil, "no usability probe reads as unknown, never usable")

    -- Wrong shipped id, spell known by name: the name fallback degrades to
    -- the name read instead of disabling the cue (the shipped 34428 is absent
    -- from this client's spell data AND unknown, but the client knows
    -- "Victory Rush" under its own id and reports it usable).
    local fallback_sb = build({ project = 18, interface = 16001, forever = true,
        drop_ids = { [34428] = true },
        known_names = { ["Victory Rush"] = 99999 },
        spell_usable = ready_usable })
    local FST2 = fallback_sb.ST
    FST2.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
    FST2.gcd = { expires = 0 }
    fallback_sb.clock = 100
    fallback_sb.power = 60
    fallback_sb.target_health = { 100, 100 }
    fallback_sb.rage_cost = { { cost = 15 } }
    local fallback_gathered = FST2.WARRIOR.guide.gather(FST2, {})
    eq(fallback_gathered.victory_rush, true,
        "a wrong Victory Rush id degrades to the name read (still prompts)")
    eq(FST2.WARRIOR.guide.evaluate(fallback_gathered, {}).action, "execute",
        "the name-read Victory Rush prompts Execute at 100 % health")
end

--=========================================================================================
-- 5) The compat health wrappers (nil = unknown)
--=========================================================================================
do
    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.WOW_PROJECT_ID = 11
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", 30300 end
    env.UnitPower = function() return 0 end
    env.UnitPowerMax = function() return 0 end
    local chunk = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(chunk, env)
    local bare_st = {}
    chunk("SwedgeTimer", bare_st)
    check(type(bare_st.api.UnitHealth) == "function", "compat exports api.UnitHealth")
    check(type(bare_st.api.UnitHealthMax) == "function", "compat exports api.UnitHealthMax")
    eq(bare_st.api.UnitHealth("player"), nil, "a client without UnitHealth answers nil (unknown)")
    eq(bare_st.api.UnitHealthMax("target"), nil, "a client without UnitHealthMax answers nil (unknown)")
end

--=========================================================================================
-- 6) Config/options parity, the TOC load order and the drive call sites
--=========================================================================================
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    local presets = read("config_presets.lua")
    local warrior_defaults = presets:match("ST%.WARRIOR%.defaults%s*=%s*%{(.-)$") or ""
    local options = read("option_tables.lua")
    local warrior_opts = options:match("function ST%.class_opts_funcs%.WARRIOR%((.*)$") or ""

    local expected_defaults = {
        nextaction_enabled = "true",
        nextaction_locked = "true",
        nextaction_visibility_key = "\"in_combat\"",
        nextaction_icon_size = "45",
        nextaction_x = "0",
        nextaction_y = "-180",
        guide_execute_pct = "20",
    }
    for key, value in pairs(expected_defaults) do
        check(warrior_defaults:find("%f[%a_]" .. key .. "%s*=%s*" .. value, 1) ~= nil,
            "config_presets.lua: WARRIOR default " .. key .. " = " .. value)
    end

    local widget_types = {
        nextaction_enabled = "toggle",
        nextaction_locked = "toggle",
        nextaction_visibility_key = "select",
        nextaction_icon_size = "range",
        nextaction_x = "input",
        nextaction_y = "input",
        guide_execute_pct = "range",
        -- Warrior Practice page (the archive's Guides & Practice shape, warrior
        -- entry): the session toggle + the shipped simulation/feedback subset
        -- plus the W6 drill report, all nil-safe without new defaults.
        practice_header = "header",
        practice_desc = "description",
        practice_toggle = "execute",
        practice_weapon_speed = "range",
        practice_result_duration = "range",
        practice_result_text_size = "range",
        practice_result_color_hit = "color",
        practice_result_color_miss = "color",
        practice_panel_x = "input",
        practice_panel_y = "input",
        practice_reset_position = "execute",
        execute_report_header = "header",
        execute_report_desc = "description",
        warrior_execute_report = "execute",
    }
    for key, wtype in pairs(widget_types) do
        local widget = warrior_opts:match("%f[%a_]" .. key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"" .. wtype .. "\"") ~= nil,
            "option_tables.lua: " .. key .. " has a " .. wtype .. " widget")
    end
    check(warrior_opts:find("Next Action Guide") ~= nil,
        "option_tables.lua: the warrior options carry a Next Action Guide block")
    check(warrior_opts:find("Twist Practice") ~= nil,
        "option_tables.lua: the warrior options carry the Practice page entry")
    local toggle_widget = warrior_opts:match("practice_toggle%s*=%s*{(.-)\n%s*}") or ""
    check(toggle_widget:find("practice_ui.toggle", 1, true) ~= nil,
        "option_tables.lua: practice_toggle routes into st.practice_ui.toggle")
    local report_widget = warrior_opts:match("warrior_execute_report%s*=%s*{(.-)\n%s*}") or ""
    check(report_widget:find("toggle_warrior_execute_report", 1, true) ~= nil,
        "option_tables.lua: warrior_execute_report routes into the report toggle")
    local pct_widget = warrior_opts:match("guide_execute_pct%s*=%s*{(.-)\n%s*}") or ""
    check(pct_widget:find("min%s*=%s*5[^%d]") ~= nil and pct_widget:find("max%s*=%s*35") ~= nil,
        "option_tables.lua: guide_execute_pct is a 5-35 range")

    -- warrior_guide.lua loads after nextaction.lua in every TOC.
    local tocs = { "SwedgeTimer.toc", "SwedgeTimer_Vanilla.toc", "SwedgeTimer_TBC.toc",
        "SwedgeTimer_Wrath.toc", "SwedgeTimer_Mainline.toc", "SwedgeTimer_Cata.toc",
        "SwedgeTimer_Mists.toc" }
    for i = 1, #tocs do
        local text = read(tocs[i])
        local after = text:find("\nnextaction.lua", 1, true)
        local guide_at = text:find("\nwarrior_guide.lua", 1, true)
        check(after ~= nil and guide_at ~= nil and guide_at > after,
            tocs[i] .. ": warrior_guide.lua loads after nextaction.lua")
    end

    -- The drive call sites live in classes/warrior.lua.
    local warrior_src = read("classes/warrior.lua")
    check(warrior_src:find("st%.nextaction_ui%.init%(self%)") ~= nil,
        "classes/warrior.lua: post_init drives st.nextaction_ui.init")
    check(warrior_src:find("st%.nextaction_ui%.on_bar_update%(self, hand%)") ~= nil,
        "classes/warrior.lua: on_bar_update drives st.nextaction_ui.on_bar_update")
    check(warrior_src:find("st%.nextaction_ui%.apply_settings%(self%)") ~= nil,
        "classes/warrior.lua: the settings diff applies live")
end

--=========================================================================================
-- Retail (12.x) inertness: the stand-in never swings, but health/rage/queue reads
-- answer on Retail - every previously-prompting shape must stay empty.
--=========================================================================================
do
    local saved_family = pure.family
    pure.family = "RETAIL"
    -- The known leak: Execute range with a working UnitHealth read and no swing.
    local out = evaluate({ target_health_pct = 10 })
    eq(out.action, nil, "retail: Execute range never prompts")
    eq(out.hold, false, "retail: Execute range never holds")
    eq(out.hold_text, nil, "retail: Execute range carries no hold text")
    -- The rest of the non-swing rules: the OP window, Bloodsurge, the queued RIDE,
    -- the HS prompt itself and the HOLD shortfall.
    eq(evaluate({ overpower_remaining = 2 }).action, nil,
        "retail: the Overpower window never prompts")
    eq(evaluate({ has_bloodsurge = true }).action, nil,
        "retail: Bloodsurge never prompts")
    local ride = evaluate({ hs_queued = true })
    eq(ride.action, nil, "retail: a queued HS never prompts")
    eq(ride.hold, false, "retail: a queued HS never rides")
    eq(ride.hold_text, nil, "retail: a queued HS carries no RIDE text")
    eq(evaluate({}).action, nil, "retail: the HS dump never prompts")
    eq(evaluate({ sunder_stacks = 2, sunder_remaining = 4 }).action, nil,
        "retail: live Sunder upkeep never prompts")
    eq(evaluate({ rend_remaining = nil,
        rend_upkeep_enabled = true }).action, nil,
        "retail: live Rend upkeep never prompts")
    eq(branch_evaluate({ sod = true },
        { sod_stance_aura = true, stance_form = 1 }).action, nil,
        "retail: the stance-dance never prompts")
    eq(branch_evaluate({}, { rage = 90, hamstring_known = true,
        hamstring_rage_threshold = 80 }).action, nil,
        "retail: the weave never prompts")
    local short = evaluate({ rage = 5 })
    eq(short.action, nil, "retail: a rage shortfall never prompts")
    eq(short.hold, false, "retail: a rage shortfall never holds")
    eq(short.hold_text, nil, "retail: a rage shortfall carries no HOLD text")
    eq(short.waiting_judgement, false, "retail: the judgement carry stays false")
    -- A stale out table is fully overwritten (no frozen field survives).
    local stale = { action = "hs", hold = true, hold_text = "HOLD",
        filler_slot = "hs", judge_slot = "execute", rotation_key = "x",
        waiting_judgement = true }
    local ret = wg.evaluate(inp({ target_health_pct = 10 }), stale)
    eq(ret, stale, "retail: evaluate returns the caller's out table")
    eq(stale.action, nil, "retail: a stale action is cleared")
    eq(stale.hold, false, "retail: a stale hold is cleared")
    eq(stale.hold_text, nil, "retail: stale hold text is cleared")
    eq(stale.filler_slot, nil, "retail: a stale filler_slot is cleared")
    eq(stale.judge_slot, nil, "retail: a stale judge_slot is cleared")
    eq(stale.rotation_key, nil, "retail: a stale rotation_key is cleared")
    eq(stale.waiting_judgement, false, "retail: a stale judgement carry is cleared")
    -- The gate is Retail-specific: any other family still prompts.
    pure.family = "TBC"
    eq(evaluate({ target_health_pct = 10 }).action, "execute",
        "non-retail family: Execute still prompts")
    pure.family = saved_family
end

--=========================================================================================
-- W2: Commanding suppression verdict + commanding readout (pure, family-agnostic)
--=========================================================================================
do
    local suppress = pure.warrior_guide.should_suppress_battle_shout
    check(type(suppress) == "function", "W2: the suppression verdict is defined")
    eq(suppress(200, 100, true), true, "W2: a live window with the toggle on suppresses")
    eq(suppress(100, 100, true), false, "W2: an exactly-elapsed window never suppresses")
    eq(suppress(50, 100, true), false, "W2: an elapsed window never suppresses")
    eq(suppress(200, 100, false), false, "W2: the toggle off never suppresses")
    eq(suppress(200, 100, nil), false, "W2: a nil toggle never suppresses")
    eq(suppress(nil, 100, true), false, "W2: an unknown expiry never suppresses")
    eq(suppress(200, nil, true), false, "W2: an unknown clock never suppresses")
    eq(suppress("x", 100, true), false, "W2: a non-number expiry never suppresses")
    eq(suppress(200, "x", true), false, "W2: a non-number clock never suppresses")
    eq(suppress(0 / 0, 100, true), false, "W2: a NaN expiry never suppresses")
    eq(suppress(200, 0 / 0, true), false, "W2: a NaN clock never suppresses")

    local display = pure.warrior_guide.get_commanding_display
    check(type(display) == "function", "W2: the commanding readout is defined")
    eq(display(160, 100), "CMD 60s", "W2: the readout counts the reported expiry")
    eq(display(100, 100), nil, "W2: an exactly-elapsed window hides the readout")
    eq(display(50, 100), nil, "W2: an elapsed window hides the readout")
    eq(display(nil, 100), nil, "W2: no capture hides the readout")
    eq(display(160, nil), nil, "W2: an unknown clock hides the readout")
    eq(display(0 / 0, 100), nil, "W2: a NaN expiry hides the readout")
end

--=========================================================================================
-- W6: Execute-entry report (pure, family-agnostic) + warrior Practice page parity
--=========================================================================================
do
    local summarize = pure.warrior_guide.summarize_execute
    local hint = pure.warrior_guide.execute_hint
    check(type(summarize) == "function", "W6 report: summarize_execute is defined")
    check(type(hint) == "function", "W6 report: execute_hint is defined")

    -- Empty shapes summarize empty, never a guess.
    local empty = summarize(nil, nil)
    eq(empty.total, 0, "W6 report: a non-table log totals zero")
    eq(empty.graded, 0, "W6 report: a non-table log grades zero")
    eq(empty.mean_rage, nil, "W6 report: a non-table log means nil")
    eq(hint(nil), "No Execute entries logged yet.",
        "W6 report: a missing summary hints the empty log")
    eq(hint({}), "No Execute entries logged yet.",
        "W6 report: a table without a total hints the empty log")
    eq(hint({ total = 0 }), "No Execute entries logged yet.",
        "W6 report: a zero total hints the empty log")

    -- Counting, grading histogram, rage mean; non-tables skipped, NaN unknown.
    local log = {
        { hp_fraction = 0.15, rage = 100, grade = "S", at = 1 },
        { hp_fraction = 0.10, rage = 80, grade = "A", at = 2 },
        { hp_fraction = 0.12, rage = nil, grade = nil, at = 3 },
        "junk",
        { hp_fraction = 0.18, rage = 0 / 0, grade = nil, at = 4 },
        { hp_fraction = 0.19, rage = 10, grade = "X", at = 5 },
    }
    local s = summarize(log, nil)
    eq(s.total, 5, "W6 report: table samples count, junk does not")
    eq(s.graded, 2, "W6 report: only known grade letters count as graded")
    eq(s.grades.S, 1, "W6 report: the S histogram counts")
    eq(s.grades.A, 1, "W6 report: the A histogram counts")
    eq(s.grades.F, 0, "W6 report: the F histogram starts at zero")
    near(s.mean_rage, (100 + 80 + 10) / 3, 1e-9,
        "W6 report: the mean covers numeric rage only (NaN excluded)")
    -- The count cap reads the newest-first head like the hunter report shape.
    local capped = summarize(log, 2)
    eq(capped.total, 2, "W6 report: the count cap limits the samples read")
    near(capped.mean_rage, (100 + 80) / 2, 1e-9,
        "W6 report: the capped mean covers the capped head")
    local neg = summarize(log, -1)
    eq(neg.total, 5, "W6 report: a negative count reads the whole log")

    -- Hint branches: singular/plural, loaded/pool, the 50 % boundary.
    eq(hint({ total = 1, grades = { S = 1, A = 0 } }),
        "Loaded: 1 of 1 entry crossed with S/A rage. Hold the BANK.",
        "W6 report: a single loaded entry names the singular")
    eq(hint({ total = 2, grades = { S = 1, A = 0 } }),
        "Loaded: 1 of 2 entries crossed with S/A rage. Hold the BANK.",
        "W6 report: exactly half loaded still holds (boundary inclusive)")
    eq(hint({ total = 3, grades = { S = 1, A = 0 } }),
        "Pool rage before 20%: only 1 of 3 entries crossed with S/A rage.",
        "W6 report: below half loaded pools")
    eq(hint({ total = 2, grades = {} }),
        "Pool rage before 20%: only 0 of 2 entries crossed with S/A rage.",
        "W6 report: a missing histogram grades zero good")
    eq(hint(s),
        "Pool rage before 20%: only 2 of 5 entries crossed with S/A rage.",
        "W6 report: the live summary hints the pool")
end

--=========================================================================================
-- Name-vs-id rule (operator 2026-10-19; bench/lessons.md): TBC queries carry
-- the localized name with the id fallback; Era queries carry ids only.
-- The value pins above prove the reads still land; these pins prove the keys.
--=========================================================================================
do
    -- TBC: every cooldown and cost query is a name (all queried ids resolve
    -- in the 2.5.6 book); knowledge probes fall back to ids (nothing probed
    -- on TBC is in the book — the cold-book discipline).
    for i = 1, #tbc.cooldown_query_log do
        check(type(tbc.cooldown_query_log[i]) == "string",
            "name-vs-id TBC: cooldown query " .. tostring(tbc.cooldown_query_log[i]) .. " is a name")
    end
    for i = 1, #tbc.cost_query_log do
        check(type(tbc.cost_query_log[i]) == "string",
            "name-vs-id TBC: cost query " .. tostring(tbc.cost_query_log[i]) .. " is a name")
    end
    check(#tbc.cooldown_query_log > 0, "name-vs-id TBC: cooldown queries were logged")
    check(#tbc.cost_query_log > 0, "name-vs-id TBC: cost queries were logged")
    for i = 1, #tbc.known_query_log do
        check(type(tbc.known_query_log[i]) == "number",
            "name-vs-id TBC: an unresolvable probe falls back to an id")
    end

    -- Era: every query shape is numeric (ids only).
    for i = 1, #era.cooldown_query_log do
        check(type(era.cooldown_query_log[i]) == "number",
            "name-vs-id Era: every cooldown query is an id")
    end
    for i = 1, #era.cost_query_log do
        check(type(era.cost_query_log[i]) == "number",
            "name-vs-id Era: every cost query is an id")
    end
    for i = 1, #era.known_query_log do
        check(type(era.known_query_log[i]) == "number",
            "name-vs-id Era: every knowledge probe is an id")
    end
    check(#era.cooldown_query_log > 0, "name-vs-id Era: cooldown queries were logged")

    -- Slots stay numeric ids on both families (icon descriptors resolved via
    -- GetSpellInfo, which takes ids on every family).
    eq(type(tslots[5].spell_id), "number", "name-vs-id TBC: guide slots keep numeric ids")
    eq(TST.WARRIOR.HUD_SLOTS[5].spell, 23881, "name-vs-id TBC: HUD slots keep numeric ids")

    -- Static wiring pins (the defects this suite must keep closed).
    local f = assert(io.open(ROOT .. "classes/warrior.lua", "r"))
    local source = f:read("*a")
    f:close()
    check(source:find("api.get_spell_query", 1, true) ~= nil,
        "name-vs-id wiring: queries go through compat's family helper")
    check(source:find('st.family == "TBC"', 1, true) ~= nil,
        "name-vs-id wiring: the family branch is st.family, never a version string")
    check(source:find("resolve_spell_name", 1, true) ~= nil,
        "name-vs-id wiring: names resolve through the client's own GetSpellInfo")
    check(source:find("aura_matches", 1, true) ~= nil,
        "name-vs-id wiring: the Blood Surge scan matches through the shared matcher")
    check(source:find("is_spell_known_query", 1, true) ~= nil,
        "name-vs-id wiring: knowledge probes go through the family query")
end

if failures == 0 then
    print("PASS  warrior_guide_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  warrior_guide_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
