-- tests/forever_guide_state.lua: unit tests for forever_guide.lua
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

local st = {}
local env = setmetatable({}, {
    __index = function(_, key)
        error("forever_guide.lua touched the global '" .. tostring(key) .. "'", 2)
    end,
})
env.math = math
env.type = type
env.tostring = tostring
env.pairs = pairs
env.pcall = pcall
env.string = string
env.select = select
env.setmetatable = setmetatable

local chunk, err = loadfile(ROOT .. "forever_guide.lua")
if not chunk then error("could not load forever_guide.lua: " .. tostring(err)) end
setfenv(chunk, env)
chunk("SwedgeTimer", st)

local FG = st.forever_guide
check(type(FG) == "table", "forever_guide module loaded")
check(type(FG.SPELLS) == "table", "SPELLS table exists")
check(type(FG.SPELLS_BY_CLASS) == "table", "SPELLS_BY_CLASS table exists")

-- 1. WARRIOR
-- Prot
local out = FG.evaluate("WARRIOR", "prot", { ["Shield Slam"] = true, rage = 30 })
eq(out.action, "shield_slam", "warrior prot: shield slam ready by name")
eq(out.spell_name, "Shield Slam", "warrior prot: spell name is Shield Slam")

out = FG.evaluate("WARRIOR", "prot", { ["Shield Wall"] = true, player_health_pct = 30, rage = 10 })
eq(out.action, "shield_wall", "warrior prot: shield wall defensive")

out = FG.evaluate("WARRIOR", "prot", { ["Last Stand"] = true, player_health_pct = 38, rage = 10 })
eq(out.action, "last_stand", "warrior prot: last stand defensive")

out = FG.evaluate("WARRIOR", "prot", { ["Shield Block"] = true, shield_block_active = false, rage = 15 })
eq(out.action, "shield_block", "warrior prot: shield block active")

out = FG.evaluate("WARRIOR", "prot", { ["Revenge"] = true, revenge_usable = true, rage = 10, shield_slam_remaining = 5 })
eq(out.action, "revenge", "warrior prot: revenge proc ready")
eq(out.spell_name, "Revenge", "warrior prot: spell name is Revenge")

out = FG.evaluate("WARRIOR", "prot", { ["Bloodthirst"] = true, shield_slam_remaining = 5, revenge_usable = false, rage = 35 })
eq(out.action, "bt", "warrior prot: fury-prot bloodthirst fallback")

-- Arms
out = FG.evaluate("WARRIOR", "arms", { ["Mortal Strike"] = true, rage = 35 })
eq(out.action, "ms", "warrior arms: mortal strike ready by name")
eq(out.spell_name, "Mortal Strike", "warrior arms: spell name is Mortal Strike")

out = FG.evaluate("WARRIOR", "arms", { ["Overpower"] = true, bloodthrill_active = true, rage = 10, ms_remaining = 4 })
eq(out.action, "op", "warrior arms: overpower on bloodthrill proc")

out = FG.evaluate("WARRIOR", "arms", { ["Execute"] = true, target_health_pct = 15, ms_remaining = 4, op_remaining = 4, rage = 20 })
eq(out.action, "execute", "warrior arms: execute in execute phase")

-- Fury
out = FG.evaluate("WARRIOR", "fury", { ["Bloodthirst"] = true, rage = 35 })
eq(out.action, "bt", "warrior fury: bloodthirst ready by name")
eq(out.spell_name, "Bloodthirst", "warrior fury: spell name is Bloodthirst")

out = FG.evaluate("WARRIOR", "fury", { ["Whirlwind"] = true, bt_remaining = 4, rage = 30 })
eq(out.action, "ww", "warrior fury: whirlwind when bt on cd")

out = FG.evaluate("WARRIOR", "fury", { ["Cleave"] = true, bt_remaining = 4, ww_remaining = 4, target_count = 2, rage = 30 })
eq(out.action, "cleave", "warrior fury: cleave multi-target")

-- General Leveling Warrior (No MS, No BT)
out = FG.evaluate("WARRIOR", nil, { ["Heroic Strike"] = true, ["Rend"] = true, rend_active = false, rage = 15 })
eq(out.rotation_key, "general", "warrior leveling: spec resolves to general")
eq(out.action, "rend", "warrior leveling: rend upkeep prioritized")
eq(out.spell_name, "Rend", "warrior leveling: spell name is Rend")

out = FG.evaluate("WARRIOR", nil, { ["Heroic Strike"] = true, ["Rend"] = true, rend_active = true, rage = 35 })
eq(out.action, "hs", "warrior leveling: dumps rage with heroic strike")
eq(out.spell_name, "Heroic Strike", "warrior leveling: spell name is Heroic Strike")

-- 2. PALADIN
-- Prot
out = FG.evaluate("PALADIN", "prot", { has_rf = false, ["Righteous Fury"] = true })
eq(out.action, "rf", "paladin prot: missing rf prompts rf by name")
eq(out.spell_name, "Righteous Fury", "paladin prot: spell name is Righteous Fury")

out = FG.evaluate("PALADIN", "prot", { has_rf = true, seal_active = true, ["Judgement"] = true })
eq(out.action, "judge", "paladin prot: judge ready")
eq(out.spell_name, "Judgement", "paladin prot: spell name is Judgement")

out = FG.evaluate("PALADIN", "prot", { has_rf = true, seal_inactive = true, ["Seal of Fury"] = true, judge_remaining = 5 })
eq(out.action, "sof", "paladin prot: seal of fury upkeep")
eq(out.spell_name, "Seal of Fury", "paladin prot: spell name is Seal of Fury")

out = FG.evaluate("PALADIN", "prot", { has_rf = true, seal_active = true, ["Consecration"] = true, judge_remaining = 5, mana_pct = 50 })
eq(out.action, "consecration", "paladin prot: consecration ready")
eq(out.spell_name, "Consecration", "paladin prot: spell name is Consecration")

out = FG.evaluate("PALADIN", "prot", { has_rf = true, seal_active = true, ["Holy Shield"] = true, judge_remaining = 5, cons_remaining = 5, mana_pct = 50 })
eq(out.action, "holy_shield", "paladin prot: holy shield ready")
eq(out.spell_name, "Holy Shield", "paladin prot: spell name is Holy Shield")

out = FG.evaluate("PALADIN", "prot", { has_rf = true, seal_active = true, ["Holy Strike"] = true, judge_remaining = 5, cons_remaining = 5, holy_shield_remaining = 5 })
eq(out.action, "holy_strike", "paladin prot: holy strike ready")
eq(out.spell_name, "Holy Strike", "paladin prot: spell name is Holy Strike")

-- Ret
out = FG.evaluate("PALADIN", "ret", { ["Judgement"] = true })
eq(out.action, "judge", "paladin ret: judge prioritized first")
eq(out.spell_name, "Judgement", "paladin ret: spell name is Judgement")

out = FG.evaluate("PALADIN", "ret", { ["Hammer of Wrath"] = true, judge_remaining = 5, target_health_pct = 15 })
eq(out.action, "how", "paladin ret: how in execute by name")
eq(out.spell_name, "Hammer of Wrath", "paladin ret: spell name is Hammer of Wrath")

out = FG.evaluate("PALADIN", "ret", { ["Holy Strike"] = true, judge_remaining = 4 })
eq(out.action, "holy_strike", "paladin ret: holy strike ready by name")
eq(out.spell_name, "Holy Strike", "paladin ret: spell name is Holy Strike")

out = FG.evaluate("PALADIN", "ret", { ["Seal of Command"] = true, judge_remaining = 4, holy_strike_remaining = 4, seal_inactive = true })
eq(out.action, "soc", "paladin ret: seal of command refresh")
eq(out.spell_name, "Seal of Command", "paladin ret: spell name is Seal of Command")

out = FG.evaluate("PALADIN", "ret", { ["Consecration"] = true, judge_remaining = 4, holy_strike_remaining = 4, seal_active = true, mana_pct = 40 })
eq(out.action, "consecration", "paladin ret: consecration weave")
eq(out.spell_name, "Consecration", "paladin ret: spell name is Consecration")

-- General Leveling Paladin (No SoC, No Shock)
out = FG.evaluate("PALADIN", nil, { ["Seal of Righteousness"] = true, seal_inactive = true })
eq(out.rotation_key, "general", "paladin leveling: spec resolves to general")
eq(out.action, "sor", "paladin leveling: seal upkeep")
eq(out.spell_name, "Seal of Righteousness", "paladin leveling: spell name is Seal of Righteousness")

out = FG.evaluate("PALADIN", nil, { ["Holy Strike"] = true, ["Judgement"] = true, judge_remaining = 5, seal_active = true })
eq(out.rotation_key, "general", "paladin leveling: spec resolves to general")
eq(out.action, "holy_strike", "paladin leveling: holy strike on cd")
eq(out.spell_name, "Holy Strike", "paladin leveling: spell name is Holy Strike")

-- Shockadin
out = FG.evaluate("PALADIN", "shockadin", { ["Judgement"] = true })
eq(out.action, "judge", "paladin shockadin: judge first")

out = FG.evaluate("PALADIN", "shockadin", { ["Consecration"] = true, judge_remaining = 4, mana_pct = 50 })
eq(out.action, "consecration", "paladin shockadin: consecration second")

out = FG.evaluate("PALADIN", "shockadin", { ["Holy Strike"] = true, judge_remaining = 4, cons_remaining = 4, seal_active = true })
eq(out.action, "holy_strike", "paladin shockadin: holy strike weave")

out = FG.evaluate("PALADIN", "shockadin", { ["Holy Shock"] = true, judge_remaining = 4, cons_remaining = 4, holy_strike_remaining = 4, seal_active = true })
eq(out.action, "holy_shock", "paladin shockadin: holy shock ready by name")
eq(out.spell_name, "Holy Shock", "paladin shockadin: spell name is Holy Shock")

-- 3. HUNTER
-- Melee Spec (Survival / Strider Kick)
out = FG.evaluate("HUNTER", "melee", { ["Raptor Strike"] = true })
eq(out.action, "raptor_strike", "hunter melee: raptor strike ready by name")
eq(out.spell_name, "Raptor Strike", "hunter melee: spell name is Raptor Strike")

out = FG.evaluate("HUNTER", "melee", { raptor_strike_remaining_cd = 4, ["Strider Kick"] = true })
eq(out.action, "strider_kick", "hunter melee: strider kick ready by name")
eq(out.spell_name, "Strider Kick", "hunter melee: spell name is Strider Kick")

out = FG.evaluate("HUNTER", nil, { ["Strider Kick"] = true, raptor_strike_remaining_cd = 4 })
eq(out.rotation_key, "melee", "hunter spec resolves to melee when strider kick known")

-- Ranged / Weave Leveling Hunter
out = FG.evaluate("HUNTER", nil, { ["Hunter's Mark"] = true, hunters_mark_active = false })
eq(out.rotation_key, "ranged", "hunter leveling: spec resolves to ranged")
eq(out.action, "hunters_mark", "hunter ranged: hunter's mark down by name")
eq(out.spell_name, "Hunter's Mark", "hunter ranged: spell name is Hunter's Mark")

out = FG.evaluate("HUNTER", "ranged", { hunters_mark_active = true, ["Serpent Sting"] = true, serpent_active = false })
eq(out.action, "serpent", "hunter ranged: serpent sting down by name")
eq(out.spell_name, "Serpent Sting", "hunter ranged: spell name is Serpent Sting")

out = FG.evaluate("HUNTER", "ranged", { hunters_mark_active = true, serpent_active = true, ["Arcane Shot"] = true })
eq(out.action, "arcane", "hunter ranged: arcane shot ready by name")
eq(out.spell_name, "Arcane Shot", "hunter ranged: spell name is Arcane Shot")

out = FG.evaluate("HUNTER", "ranged", { hunters_mark_active = true, serpent_active = true, ["Multi-Shot"] = true, arcane_remaining_cd = 4 })
eq(out.action, "multi", "hunter ranged: multi-shot ready")
eq(out.spell_name, "Multi-Shot", "hunter ranged: spell name is Multi-Shot")

out = FG.evaluate("HUNTER", "ranged", { hunters_mark_active = true, serpent_active = true, ["Aimed Shot"] = true, arcane_remaining_cd = 4, multi_remaining_cd = 4 })
eq(out.action, "aimed", "hunter ranged: aimed shot ready")
eq(out.spell_name, "Aimed Shot", "hunter ranged: spell name is Aimed Shot")

out = FG.evaluate("HUNTER", "ranged", { hunters_mark_active = true, serpent_active = true, ["Sniper Shot"] = true, arcane_remaining_cd = 4, multi_remaining_cd = 4, aimed_remaining_cd = 4 })
eq(out.action, "sniper", "hunter ranged: sniper shot ready")
eq(out.spell_name, "Sniper Shot", "hunter ranged: spell name is Sniper Shot")

-- Weave in melee range
out = FG.evaluate("HUNTER", "ranged", { unit_distance = 4, ["Raptor Strike"] = true })
eq(out.action, "raptor_strike", "hunter weave in melee: raptor strike")

out = FG.evaluate("HUNTER", "ranged", { unit_distance = 4, ["Strider Kick"] = true, raptor_strike_remaining_cd = 4 })
eq(out.action, "strider_kick", "hunter weave in melee: strider kick")

-- 4. ROGUE
out = FG.evaluate("ROGUE", "mutilate", { ["Mutilate"] = true, combo_points = 2, energy = 65, snd_remaining = 10 })
eq(out.action, "mutilate", "rogue mutilate: mutilate builder by name")
eq(out.spell_name, "Mutilate", "rogue mutilate: spell name is Mutilate")

out = FG.evaluate("ROGUE", "combat_bs", { ["Backstab"] = true, combo_points = 2, energy = 65, snd_remaining = 10 })
eq(out.action, "backstab", "rogue combat_bs: backstab builder by name")
eq(out.spell_name, "Backstab", "rogue combat_bs: spell name is Backstab")

out = FG.evaluate("ROGUE", "hemo", { ["Hemorrhage"] = true, combo_points = 2, energy = 40, snd_remaining = 10 })
eq(out.action, "hemo", "rogue hemo: hemorrhage builder by name")
eq(out.spell_name, "Hemorrhage", "rogue hemo: spell name is Hemorrhage")

out = FG.evaluate("ROGUE", nil, { ["Sinister Strike"] = true, combo_points = 1, energy = 50, snd_remaining = 10 })
eq(out.rotation_key, "combat_ss", "rogue leveling: spec resolves to combat_ss")
eq(out.action, "ss", "rogue ss: sinister strike builder by name")
eq(out.spell_name, "Sinister Strike", "rogue ss: spell name is Sinister Strike")

out = FG.evaluate("ROGUE", "combat_ss", { combo_points = 2, ["Slice and Dice"] = true, snd_remaining = 0, energy = 30 })
eq(out.action, "snd", "rogue: slice and dice down at low cp")
eq(out.spell_name, "Slice and Dice", "rogue: spell name is Slice and Dice")

out = FG.evaluate("ROGUE", "combat_ss", { combo_points = 5, ["Rupture"] = true, energy = 40, snd_remaining = 10 })
eq(out.action, "rupture", "rogue: rupture finisher at 5 cp by name")
eq(out.spell_name, "Rupture", "rogue: spell name is Rupture")

out = FG.evaluate("ROGUE", "combat_ss", { combo_points = 5, ["Eviscerate"] = true, rupture_active = true, energy = 40, snd_remaining = 10 })
eq(out.action, "eviscerate", "rogue: eviscerate finisher at 5 cp")
eq(out.spell_name, "Eviscerate", "rogue: spell name is Eviscerate")

out = FG.evaluate("ROGUE", "mutilate", { combo_points = 4, ["Venom"] = true, envenom_usable = true, energy = 40, snd_remaining = 10 })
eq(out.action, "envenom", "rogue: envenom finisher by name")
eq(out.spell_name, "Venom", "rogue: spell name is Venom (the Forever client name)")

-- Forever producer mapping (classes/rogue.lua:1241,1245): the class gather sets
-- venom_ready and venom_buff_active and NEVER sets envenom_usable. The cited APL row
-- (classes/rogue.lua:2754) is "the buff is down AND cp >= 3"; the ALIAS must map the
-- class fields onto the engine key so the row is reachable at all.
local venom_inputs = {
    cp = 4, energy_now = 40,
    ["Venom"] = true,          -- known, by the client name
    venom_ready = true,        -- known + usable + off cooldown (utility_ready)
    venom_buff_active = false, -- the aura walk completed without the Venom buff
}
out = FG.evaluate("ROGUE", "mutilate", venom_inputs, {})
eq(out.action, "envenom", "forever venom: ready + buff down + cp >= 3 fires the finisher")
eq(out.spell_name, "Venom", "forever venom: the mapped producer carries the client name")

-- The cp >= 3 boundary: at exactly 3 cp the engine's finisher entry gate is open only
-- through its SnD-expiry arm (cp >= 3 and snd_rem <= 2); with SnD not tracked the
-- SnD-refresh branch cannot outrank Venom, so this pins the alias's own cp >= 3.
local venom_cp3 = {
    cp = 3, energy_now = 40,
    ["Venom"] = true, venom_ready = true, venom_buff_active = false,
    snd_remains = 2,
}
out = FG.evaluate("ROGUE", "mutilate", venom_cp3, {})
eq(out.action, "envenom", "forever venom: the APL's cp >= 3 arm fires at exactly 3 cp")

-- The buff is up: the APL condition is false, so the row must stay quiet.
local venom_buff_up = {
    cp = 4, energy_now = 40, ["Venom"] = true,
    venom_ready = true, venom_buff_active = true,
}
out = FG.evaluate("ROGUE", "mutilate", venom_buff_up, {})
check(out.action ~= "envenom", "forever venom: an active Venom buff suppresses the finisher")
check(out.spell_name ~= "Venom", "forever venom: no Venom name while the buff is up")

-- Not ready (the class's utility_ready returned nil): no row.
local venom_not_ready = {
    cp = 4, energy_now = 40, ["Venom"] = true,
    venom_ready = nil, venom_buff_active = false,
}
out = FG.evaluate("ROGUE", "mutilate", venom_not_ready, {})
check(out.action ~= "envenom", "forever venom: a not-ready spell suppresses the finisher")

-- Unreadable buff state (the class read nil: no aura scan at all): nil is NOT "down",
-- so the row stays quiet instead of claiming a buff state it never read.
local venom_unreadable = {
    cp = 4, energy_now = 40, ["Venom"] = true,
    venom_ready = true, venom_buff_active = nil,
}
out = FG.evaluate("ROGUE", "mutilate", venom_unreadable, {})
check(out.action ~= "envenom", "forever venom: an unreadable buff stays unknown (nil is not down)")

out = FG.evaluate("ROGUE", "combat_ss", { ["Riposte"] = true, riposte_usable = true, energy = 20 })
eq(out.action, "riposte", "rogue: riposte proc prompts by name")
eq(out.spell_name, "Riposte", "rogue: spell name is Riposte")

-- 5. DRUID
out = FG.evaluate("DRUID", "bear", { ["Barkskin"] = true, player_health_pct = 35 })
eq(out.action, "barkskin", "druid bear: barkskin defensive")
eq(out.spell_name, "Barkskin", "druid bear: spell name is Barkskin")

out = FG.evaluate("DRUID", "bear", { ["Frenzied Regeneration"] = true, player_health_pct = 30, rage = 15 })
eq(out.action, "frenzied_regen", "druid bear: frenzied regen defensive")
eq(out.spell_name, "Frenzied Regeneration", "druid bear: spell name is Frenzied Regeneration")

out = FG.evaluate("DRUID", "bear", { ["Enrage"] = true, rage = 5 })
eq(out.action, "enrage", "druid bear: enrage ready by name")
eq(out.spell_name, "Enrage", "druid bear: spell name is Enrage")

out = FG.evaluate("DRUID", "bear", { enrage_remaining = 30, ["Faerie Fire (Feral)"] = true, faerie_fire_active = false })
eq(out.action, "faerie_fire", "druid bear: faerie fire upkeep")

out = FG.evaluate("DRUID", "bear", { enrage_remaining = 30, faerie_fire_active = true, ["Primal Bite"] = true, rage = 30 })
eq(out.action, "primal_bite", "druid bear: primal bite ready")
eq(out.spell_name, "Primal Bite", "druid bear: spell name is Primal Bite")

out = FG.evaluate("DRUID", "bear", { enrage_remaining = 30, faerie_fire_active = true, ["Lacerate"] = true, lacerate_stacks = 2, rage = 20 })
eq(out.action, "lacerate", "druid bear: lacerate build")
eq(out.spell_name, "Lacerate", "druid bear: spell name is Lacerate")

out = FG.evaluate("DRUID", "bear", { enrage_remaining = 30, faerie_fire_active = true, lacerate_stacks = 5, lacerate_remaining = 10, ["Maul"] = true, rage = 20 })
eq(out.action, "maul", "druid bear: maul ready by name")
eq(out.spell_name, "Maul", "druid bear: spell name is Maul")

out = FG.evaluate("DRUID", "cat", { prowl_active = true, ["Ravage"] = true, energy = 65 })
eq(out.action, "ravage", "druid cat: ravage in prowl")
eq(out.spell_name, "Ravage", "druid cat: spell name is Ravage")

out = FG.evaluate("DRUID", "cat", { ["Faerie Fire (Feral)"] = true, faerie_fire_active = false })
eq(out.action, "faerie_fire", "druid cat: faerie fire down by name")
eq(out.spell_name, "Faerie Fire (Feral)", "druid cat: spell name is Faerie Fire (Feral)")

out = FG.evaluate("DRUID", "cat", { faerie_fire_active = true, combo_points = 5, ["Rip"] = true, energy = 40 })
eq(out.action, "rip", "druid cat: rip finisher at 5 cp by name")
eq(out.spell_name, "Rip", "druid cat: spell name is Rip")

out = FG.evaluate("DRUID", "cat", { faerie_fire_active = true, combo_points = 5, rip_active = true, ["Ferocious Bite"] = true, energy = 40 })
eq(out.action, "ferocious_bite", "druid cat: ferocious bite finisher at 5 cp")
eq(out.spell_name, "Ferocious Bite", "druid cat: spell name is Ferocious Bite")

out = FG.evaluate("DRUID", "cat", { faerie_fire_active = true, combo_points = 2, ["Rake"] = true, rake_active = false, energy = 40 })
eq(out.action, "rake", "druid cat: rake upkeep")
eq(out.spell_name, "Rake", "druid cat: spell name is Rake")

-- 6. SHAMAN
out = FG.evaluate("SHAMAN", "enhancement", { ["Flame Shock"] = true, flameshock_active = false })
eq(out.action, "flameshock", "shaman: flame shock down by name")
eq(out.spell_name, "Flame Shock", "shaman: spell name is Flame Shock")

out = FG.evaluate("SHAMAN", "enhancement", { flameshock_active = true, ["Stormstrike"] = true })
eq(out.action, "stormstrike", "shaman: stormstrike ready by name")
eq(out.spell_name, "Stormstrike", "shaman: spell name is Stormstrike")

out = FG.evaluate("SHAMAN", "enhancement", { flameshock_active = true, stormstrike_remaining = 6, mw_stacks = 5, ["Lightning Bolt"] = true })
eq(out.action, "weave", "shaman: instant lightning bolt at 5 mw stacks")
eq(out.spell_name, "Lightning Bolt", "shaman: spell name is Lightning Bolt")

out = FG.evaluate("SHAMAN", "enhancement", { flameshock_active = true, stormstrike_remaining = 6, mw_stacks = 2, ["Earth Shock"] = true })
eq(out.action, "earthshock", "shaman: earth shock ready")
eq(out.spell_name, "Earth Shock", "shaman: spell name is Earth Shock")

out = FG.evaluate("SHAMAN", "enhancement", { flameshock_active = true, stormstrike_remaining = 6, shock_remaining = 4, ["Fire Nova"] = true, mana_fraction = 0.5 })
eq(out.action, "firenova", "shaman: fire nova ready")
eq(out.spell_name, "Fire Nova", "shaman: spell name is Fire Nova")

out = FG.evaluate("SHAMAN", nil, { ["Lightning Shield"] = true, lightningshield_active = false, shock_remaining = 5 })
eq(out.rotation_key, "general", "shaman leveling: spec resolves to general")
eq(out.action, "lightningshield", "shaman leveling: lightning shield upkeep")
eq(out.spell_name, "Lightning Shield", "shaman leveling: spell name is Lightning Shield")


-- 7. LIVE GATHER BRIDGE: the class gather_guide_inputs key names (what the game
-- actually feeds), not the evaluator's own names.
check(FG.SPELLS.FLAME_SHOCK.id == 8050, "flame shock uses its own rank-1 id (8050)")
check(FG.SPELLS.FLAME_SHOCK.id ~= FG.SPELLS.EARTH_SHOCK.id, "flame shock id is not earth shock's id")

-- Venom: the Forever client names the rogue poison "Venom" (id 1310703). The Lua key
-- stays ENVENOM and the action / slot key stays "envenom" so nothing ripples into the
-- class modules; only the client-facing name changes.
eq(FG.SPELLS.ENVENOM.name, "Venom", "envenom definition carries the client name Venom")
eq(FG.SPELLS.ENVENOM.id, 1310703, "envenom keeps id 1310703")
eq(FG.SPELLS_BY_NAME["Venom"], FG.SPELLS.ENVENOM, "SPELLS_BY_NAME maps Venom to the envenom definition")
check(FG.SPELLS_BY_NAME["Envenom"] == nil, "the stale Envenom name is gone from SPELLS_BY_NAME")

local function has_key(class, key)
    local slots = FG.get_guide_slots(class)
    for i = 1, #slots do
        if slots[i].key == key then return true end
    end
    return false
end
local function has_hud_key(class, key)
    local slots = FG.get_hud_slots(class)
    for i = 1, #slots do
        if slots[i].key == key then return true end
    end
    return false
end
check(has_key("HUNTER", "raptor_strike"), "guide slot key matches action: raptor_strike")
check(has_key("HUNTER", "aspect_hawk"), "guide slot key matches action: aspect_hawk")
check(has_key("DRUID", "ferocious_bite") and has_key("DRUID", "demoralizing_roar"), "guide slot keys match druid actions")
check(has_key("ROGUE", "ea"), "guide slot key matches rogue action: ea")
check(has_key("ROGUE", "envenom"), "venom keeps the guide slot key envenom")
check(has_hud_key("ROGUE", "envenom"), "venom keeps the hud slot key envenom (no class-module ripple)")

-- Warrior: Bloodthirst on cooldown by the client (no bt_remaining fed, as on Forever).
local cd_state = { Bloodthirst = { 100, 6 } }
st.api = {
    get_time = function() return 102 end,
    GetSpellCooldown = function(name)
        local c = cd_state[name]
        if c then return c[1], c[2] end
        return 0, 0
    end,
}
out = FG.evaluate("WARRIOR", "fury", { ["Bloodthirst"] = true, ["Whirlwind"] = true, rage = 40 })
eq(out.action, "ww", "live: bloodthirst on client cooldown is not prompted (lazy cooldown read)")
cd_state = {}
out = FG.evaluate("WARRIOR", "fury", { ["Bloodthirst"] = true, ["Whirlwind"] = true, rage = 40 })
eq(out.action, "bt", "live: bloodthirst ready by client cooldown is prompted")
st.api = nil

-- Paladin ret: live seal state (seal = "soc", seal_inactive reports only Righteousness).
out = FG.evaluate("PALADIN", "ret", { ["Seal of Command"] = true, ["Consecration"] = true,
    seal = "soc", seal_inactive = true, judge_remaining = 5, holy_strike_remaining = 5,
    cons_remaining = 0, exo_remaining = 5, mana_pct = 50 })
eq(out.action, "consecration", "live: seal up by engine seal state does not re-prompt the seal")

-- Rogue: energy_now / cp / snd_remains / rupture_remains.
out = FG.evaluate("ROGUE", "combat_ss", { ["Eviscerate"] = true, ["Rupture"] = true,
    energy_now = 80, cp = 5, snd_remains = 10, rupture_known = true, rupture_remains = 12 })
eq(out.action, "eviscerate", "live: rogue reads cp/energy_now and an up Rupture")

-- Druid: form_index + rage + the Faerie Fire debuff clock.
out = FG.evaluate("DRUID", nil, { ["Maul"] = true, ["Faerie Fire (Feral)"] = true,
    form_index = 1, rage = 30, ff_debuff_remaining = 10 })
eq(out.rotation_key, "bear", "live: druid bear form from form_index")
eq(out.action, "maul", "live: bear rotation runs with Faerie Fire debuff up")

-- Shaman: Flame Shock dot clock.
out = FG.evaluate("SHAMAN", "enhancement", { ["Flame Shock"] = true, ["Stormstrike"] = true,
    flameshock_allowed = true, flameshock_remaining = 8, stormstrike_remaining = 0, shock_remaining = 0 })
eq(out.action, "stormstrike", "live: flame shock up (tracker remaining) moves on to stormstrike")

-- Hunter: Aspect of the Hawk is its own action key.
out = FG.evaluate("HUNTER", "ranged", { ["Aspect of the Hawk"] = true, hawk_remaining_cd = 0 })
eq(out.action, "aspect_hawk", "aspect of the hawk emits aspect_hawk (not Summon Hawk's key)")

out = FG.evaluate("HUNTER", "melee", { ["Aspect of the Hawk"] = true, hawk_remaining_cd = 0 })
eq(out.action, "aspect_hawk", "melee: aspect of the hawk emits aspect_hawk")
out = FG.evaluate("ROGUE", "combat_ss", { ["Sinister Strike"] = true, energy_now = 60, cp = 2, snd_remains = 10 })
eq(out.action, "ss", "live: rogue builder fires on energy_now (not pooled at 0)")

-- 8. OUTPUT-TABLE REUSE: every field the model can write is cleared before the
-- branch runs. nextaction_ui and the class providers hand the same table back on
-- every tick, so a HOLD / POOL / WAIT branch must not re-display the last action,
-- and judge_call must not latch the Judgement icon on later ticks.
local reuse = {}
eq(FG.evaluate("PALADIN", "ret", { ["Judgement"] = true }, reuse), reuse,
    "reuse: evaluate returns the caller's reused table")
eq(reuse.action, "judge", "reuse: first tick cues Judgement")
eq(reuse.judge_call, true, "reuse: first tick sets judge_call")
eq(FG.evaluate("PALADIN", "prot", { has_rf = true, seal_active = true }, reuse), reuse,
    "reuse: the second tick writes into the same table")
eq(reuse.hold, true, "reuse: second tick takes a HOLD/WAIT branch")
eq(reuse.hold_text, "WAIT", "reuse: second tick carries the WAIT text")
eq(reuse.action, nil, "reuse: a no-action branch clears the previous action")
eq(reuse.spell_name, nil, "reuse: a no-action branch clears the previous spell name")
eq(reuse.judge_call, nil, "reuse: judge_call does not latch across ticks")
eq(reuse.judge_slot, nil, "reuse: judge_slot does not latch across ticks")
eq(reuse.rotation_key, "prot", "reuse: the current tick's rotation_key still lands")
eq(FG.evaluate("NOPE", nil, {}, reuse), reuse, "reuse: an unknown class still returns the caller's table")
eq(reuse.action, nil, "reuse: an unknown class clears the action")
eq(reuse.rotation_key, nil, "reuse: an unknown class clears the rotation_key")

-- 9. RESTRICTED COOLDOWN READS (secret timing): compat's fifth return is true only
-- when the client handed back secret timing and no readable fallback answered. That
-- is unknown, never "ready": the tick is flagged inputs_unknown so the display
-- suppresses the advice (M6). An absent/nil fifth return is the classic shape and
-- must behave exactly as before.
st.api = {
    get_time = function() return 100 end,
    GetSpellCooldown = function() return 0, 0, 0, 0, true end,
}
out = FG.evaluate("PALADIN", "ret", { ["Judgement"] = true })
eq(out.inputs_unknown, true, "restricted: a restricted cooldown read marks the tick unknown")
st.api = {
    get_time = function() return 100 end,
    GetSpellCooldown = function() return 0, 0, 0, 0 end,
}
out = FG.evaluate("PALADIN", "ret", { ["Judgement"] = true })
eq(out.inputs_unknown, false, "restricted: an absent fifth return leaves the tick known")
eq(out.action, "judge", "restricted: the nil-flag path still cues Judgement")
out = FG.evaluate("PALADIN", "ret", { ["Judgement"] = true, inputs_unknown = true })
eq(out.inputs_unknown, true, "restricted: the caller's unknown bit is preserved")
st.api = nil

-- 10. VERIFIED FOREVER SPELL IDS (Wowhead Forever DB): the full ladder every tracked
-- spell must carry. A bare name lookup is the primary path; these tables are the
-- fallback ladder is_known and the HUD/guide gates walk, so a wrong or missing id
-- silently hides a slot. Pinning the whole ladder makes any drift land here.
local VERIFIED_IDS = {
    -- Hunter
    SERPENT_STING = { id = 1978, ids = { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295, 425728, 425729, 425730, 425732, 425733, 425734, 425735, 425736, 425737 } },
    RAPTOR_STRIKE = { id = 2973, ids = { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 } },
    STRIDER_KICK = { id = 1317257, ids = { 1317257 } },
    MONGOOSE_BITE = { id = 1495, ids = { 1495, 14269, 14270, 14271 } },
    HUNTERS_MARK = { id = 1130, ids = { 1130, 14323, 14324, 14325 } },
    ARCANE_SHOT = { id = 3044, ids = { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287 } },
    MULTI_SHOT = { id = 2643, ids = { 2643 } },
    WING_CLIP = { id = 2974, ids = { 2974, 14267, 14268 } },
    IMMOLATION_TRAP = { id = 13795, ids = { 13795, 14302, 14303, 14304, 14305 } },
    AIMED_SHOT = { id = 19434, ids = { 19434, 20900, 20901, 20902, 20903, 20904 } },
    SNIPER_SHOT = { id = 1310687, ids = { 1310687, 1310786 } },
    SUMMON_HAWK = { id = 1293241, ids = { 1293241 } },
    ASPECT_HAWK = { id = 13165, ids = { 13165, 14318, 14319, 14320, 14321, 14322, 25296 } },
    -- Warrior
    HEROIC_STRIKE = { id = 78, ids = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 } },
    REND = { id = 772, ids = { 772, 6546, 6547, 6548, 11572, 11573, 11574 } },
    OVERPOWER = { id = 7384, ids = { 7384, 7887, 11584, 11585 } },
    BLOODTHRILL = { id = 1289682, ids = { 1289681, 1289682 } },
    MORTAL_STRIKE = { id = 12294, ids = { 12294, 21551, 21552, 21553 } },
    BLOODTHIRST = { id = 23881, ids = { 23881, 23892, 23893, 23894 } },
    WHIRLWIND = { id = 1680, ids = { 1680 } },
    EXECUTE = { id = 5308, ids = { 5308, 20658, 20660, 20661, 20662 } },
    SLAM = { id = 1240193, ids = { 1240193, 1464, 8820, 11604, 11605 } },
    SUNDER_ARMOR = { id = 7386, ids = { 7386, 7405, 8380, 11596, 11597 } },
    THUNDER_CLAP = { id = 6343, ids = { 6343, 8198, 8204, 8205, 11580, 11581 } },
    DEMO_SHOUT = { id = 1160, ids = { 1160, 6190, 11554, 11555, 11556 } },
    REVENGE = { id = 6572, ids = { 6572, 6574, 7379, 11600, 11601, 25288 } },
    SHIELD_SLAM = { id = 23922, ids = { 23922, 23923, 23924, 23925 } },
    SHIELD_BLOCK = { id = 2565, ids = { 2565 } },
    SHIELD_WALL = { id = 871, ids = { 871 } },
    LAST_STAND = { id = 12975, ids = { 12975 } },
    HAMSTRING = { id = 1715, ids = { 1715, 7372, 7373 } },
    CLEAVE = { id = 845, ids = { 845, 7369, 11608, 11609, 20569 } },
    BATTLE_SHOUT = { id = 6673, ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 } },
    -- Paladin
    HOLY_STRIKE = { id = 679, ids = { 679, 678, 1866, 680, 2495, 5569, 10332, 10333 } },
    JUDGEMENT = { id = 20271, ids = { 20271 } },
    SEAL_RIGHTEOUSNESS = { id = 21084, ids = { 21084, 20154, 20287, 20288, 20289, 20290, 20291, 20292, 20293 } },
    SEAL_COMMAND = { id = 20375, ids = { 20375, 20915, 20918, 20919, 20920 } },
    SEAL_CRUSADER = { id = 21082, ids = { 21082, 20162, 20305, 20306, 20307, 20308 } },
    CONSECRATION = { id = 26573, ids = { 26573, 20116, 20922, 20923, 20924 } },
    EXORCISM = { id = 879, ids = { 879, 5614, 5615, 10312, 10313, 10314, 415068, 415069, 415070, 415071, 415072, 415073 } },
    HAMMER_OF_WRATH = { id = 24275, ids = { 24275, 24274, 24239 } },
    HOLY_SHOCK = { id = 20473, ids = { 20473, 20929, 20930 } },
    DIVINE_FAVOR = { id = 20216, ids = { 20216 } },
    HOLY_SHIELD = { id = 20925, ids = { 20925 } },
    RIGHTEOUS_FURY = { id = 25780, ids = { 25780, 407627 } },
    SEAL_FURY = { id = 20423, ids = { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 } },
    -- Rogue
    SINISTER_STRIKE = { id = 1752, ids = { 1752, 1757, 1758, 1759, 1760, 8621, 11293, 11294 } },
    EVISCERATE = { id = 2098, ids = { 2098, 6760, 6761, 6762, 8623, 8624, 11299, 11300, 31016 } },
    SLICE_AND_DICE = { id = 5171, ids = { 5171, 6774 } },
    RUPTURE = { id = 1943, ids = { 1943, 8639, 8640, 11273, 11274, 11275 } },
    MUTILATE = { id = 1241584, ids = { 399960, 399961, 1241582, 1241584, 1241585, 1241586, 1241588, 1241590 } },
    HEMORRHAGE = { id = 16511, ids = { 16511 } },
    BACKSTAB = { id = 53, ids = { 53, 2589, 2590, 2591, 8721, 11279, 11280, 11281, 25300 } },
    RIPOSTE = { id = 14251, ids = { 14251 } },
    ENVENOM = { id = 1310703, ids = { 1310703 } },
    EXPOSE_ARMOR = { id = 8647, ids = { 8647, 8649, 8650, 11197, 11198 } },
    -- Druid
    MAUL = { id = 6807, ids = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 } },
    SWIPE = { id = 779, ids = { 779, 780, 769, 9754, 9908, 1264494, 1264497, 1264498, 1264501, 1264502 } },
    DEMO_ROAR = { id = 99, ids = { 99, 1735, 9490, 9747, 9898 } },
    ENRAGE = { id = 5229, ids = { 5229 } },
    FAERIE_FIRE_FERAL = { id = 16857, ids = { 16857, 17390, 17391, 17392, 784, 1070, 13424, 13752 } },
    CLAW = { id = 1082, ids = { 1082, 3029, 5201, 9849, 9850 } },
    SHRED = { id = 5221, ids = { 5221, 6800, 8992, 9829, 9830 } },
    RIP = { id = 1079, ids = { 1079, 9492, 9493, 9752, 9894, 9896 } },
    FEROCIOUS_BITE = { id = 22568, ids = { 1328618, 22568, 22827, 22828, 22829, 31018 } },
    LACERATE = { id = 1235827, ids = { 1328617, 1328616, 414644, 1235826, 1235827, 1299332 } },
    PRIMAL_BITE = { id = 1238070, ids = { 407995, 1238069, 1238070, 1238073 } },
    BARKSKIN = { id = 22812, ids = { 22812 } },
    FRENZIED_REGEN = { id = 22842, ids = { 22842 } },
    RAKE = { id = 1822, ids = { 1822, 1823, 1824, 9904 } },
    RAVAGE = { id = 6785, ids = { 6785, 6787, 9866, 9867 } },
    TIGERS_FURY = { id = 5217, ids = { 5217 } },
    -- Shaman
    FLAME_SHOCK = { id = 8050, ids = { 8050, 8052, 8053, 10447, 10448, 29228 } },
    STORMSTRIKE = { id = 17364, ids = { 17364 } },
    EARTH_SHOCK = { id = 8042, ids = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 } },
    FIRE_NOVA = { id = 408345, ids = { 408341, 408342, 408343, 408344, 408345 } },
    LIGHTNING_BOLT = { id = 403, ids = { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208, 408439, 408440, 408441, 408442, 408443, 408472, 408473, 408474, 408475, 408477 } },
    LIGHTNING_SHIELD = { id = 324, ids = { 324, 325, 905, 945, 8134, 10431, 10432 } },
    WATER_SHIELD = { id = 408510, ids = { 408510 } },
    SEARING_TOTEM = { id = 3599, ids = { 3599, 6363, 6364, 6365, 10437, 10438 } },
    STRENGTH_OF_EARTH = { id = 8075, ids = { 8075, 8160, 8161, 10442, 25361 } },
}

local function contains_id(sp, id)
    if not (type(sp) == "table" and type(sp.ids) == "table") then return false end
    for i = 1, #sp.ids do
        if sp.ids[i] == id then return true end
    end
    return false
end

local verified_keys = 0
for key, want in pairs(VERIFIED_IDS) do
    local sp = FG.SPELLS[key]
    check(type(sp) == "table", key .. " is declared in FG.SPELLS")
    if type(sp) == "table" then
        verified_keys = verified_keys + 1
        eq(sp.id, want.id, key .. " keeps the verified primary id")
        eq(type(sp.ids) == "table" and #sp.ids or 0, #want.ids,
            key .. " carries the verified number of rank ids")
        for i = 1, #want.ids do
            eq(sp.ids and sp.ids[i], want.ids[i],
                key .. " rank " .. i .. " is the verified id")
        end
    end
end
eq(verified_keys, 81, "the verified table pins every tracked spell")

-- The operator order (2026-11-05): the Feral Faerie Fire ladder carries ALL candidate
-- ids for now - the classic fallback (16857/17390-17392) plus the unverified Forever
-- candidates (784/1070/13424/13752), in that exact order. A silent drift in either
-- half lands here even if the VERIFIED_IDS mirror is edited to match.
do
    local ff = FG.SPELLS.FAERIE_FIRE_FERAL
    local want = { 16857, 17390, 17391, 17392, 784, 1070, 13424, 13752 }
    eq(ff.id, 16857, "feral faerie fire keeps the classic primary id")
    eq(#ff.ids, #want, "feral faerie fire carries the full operator union")
    for i = 1, #want do
        eq(ff.ids[i], want[i],
            "feral faerie fire id " .. i .. " is the operator union member")
    end
end

-- Every definition (declared or not in the verified table) must carry a ladder and a
-- primary id inside it; a spell added later without a pin fails here.
local declared_count = 0
for key in pairs(FG.SPELLS) do
    declared_count = declared_count + 1
    check(VERIFIED_IDS[key] ~= nil, key .. " is pinned by the verified ladder table")
end
eq(declared_count, 81, "FG.SPELLS still declares eighty-one tracked spells")

-- Structural invariants: non-empty ids, primary id inside ids, no repeated rank inside
-- one spell, and no id claimed by two different spell names. The documented alternates
-- (SoR 20154/21084, the 415xxx Exorcism, 425xxx Serpent Sting, 408xxx Lightning Bolt,
-- 1289681/1289682 Bloodthrill) all live under ONE name, so they never trip the rule.
do
    local owner = {}
    local cross_owner = nil
    for key, sp in pairs(FG.SPELLS) do
        check(type(sp.ids) == "table" and #sp.ids > 0, key .. " has a non-empty ids table")
        check(contains_id(sp, sp.id), key .. " keeps its primary id inside ids")
        local local_seen = {}
        for i = 1, #sp.ids do
            local id = sp.ids[i]
            check(local_seen[id] == nil, key .. " never lists id " .. tostring(id) .. " twice")
            local_seen[id] = true
            if owner[id] and owner[id] ~= sp.name then
                cross_owner = tostring(id) .. " (" .. owner[id] .. " / " .. sp.name .. ")"
            end
            owner[id] = sp.name
        end
    end
    check(cross_owner == nil, "no spell id is claimed by two names (" .. tostring(cross_owner) .. ")")
end

-- Proven-wrong ids from the older tables must stay out of the spell they were mis-filed
-- under (each one belongs to a different spell or to no Forever spell at all).
check(not contains_id(FG.SPELLS.SNIPER_SHOT, 14266),
    "Sniper Shot never claims Raptor Strike's 14266")
for i = 1, 3 do
    check(not contains_id(FG.SPELLS.DEMO_SHOUT, ({ 11549, 11550, 11551 })[i]),
        "Demoralizing Shout never claims Battle Shout's 11549/11550/11551")
end
check(not contains_id(FG.SPELLS.SEARING_TOTEM, 10587),
    "Searing Totem never claims the unrelated 10587")
check(not contains_id(FG.SPELLS.CLAW, 9823) and not contains_id(FG.SPELLS.CLAW, 9827),
    "Claw never claims Pounce's 9823/9827")
check(not contains_id(FG.SPELLS.SEAL_CRUSADER, 21183),
    "Seal of the Crusader never claims the Judgement debuff 21183")
check(not contains_id(FG.SPELLS.CONSECRATION, 20142),
    "Consecration never claims the retired 20142 (rank 2 is 20116)")
check(not contains_id(FG.SPELLS.BLOODTHRILL, 1282733),
    "Bloodthrill never claims the retired 1282733")
check(not contains_id(FG.SPELLS.TIGERS_FURY, 417045),
    "Tiger's Fury never claims the unverified 417045 variant")
check(not contains_id(FG.SPELLS.RAPTOR_STRIKE, 409433)
    and not contains_id(FG.SPELLS.RAPTOR_STRIKE, 415068),
    "Raptor Strike stays on the classic ladder (no 409xxx/415xxx family)")

-- The documented alternates stay present under their one spell name.
check(contains_id(FG.SPELLS.SEAL_RIGHTEOUSNESS, 20154)
    and contains_id(FG.SPELLS.SEAL_RIGHTEOUSNESS, 21084),
    "Seal of Righteousness keeps both verified bases (20154/21084)")
check(contains_id(FG.SPELLS.EXORCISM, 415068)
    and contains_id(FG.SPELLS.EXORCISM, 415073),
    "Exorcism keeps the verified 415xxx cast ladder")
check(contains_id(FG.SPELLS.SERPENT_STING, 425728)
    and contains_id(FG.SPELLS.SERPENT_STING, 425737),
    "Serpent Sting keeps the verified 425xxx cast ladder")
check(contains_id(FG.SPELLS.LIGHTNING_BOLT, 408439)
    and contains_id(FG.SPELLS.LIGHTNING_BOLT, 408477),
    "Lightning Bolt keeps the verified 408xxx cast ladder")
check(contains_id(FG.SPELLS.BLOODTHRILL, 1289681)
    and contains_id(FG.SPELLS.BLOODTHRILL, 1289682),
    "Bloodthrill keeps both verified ids (1289681/1289682)")
check(contains_id(FG.SPELLS.LACERATE, 1299332),
    "Lacerate keeps the alternate rank 4 (1299332)")

-- 11. FINAL FUNCTIONAL AUDIT (2026-11-05): proven Forever-only defects D1-D5, D7.
-- Each pin below fails on the pre-fix code (mutation-proofed on /tmp/opencode)
-- and passes after. Era/TBC/Titanforge behaviour is untouched (this module is
-- Forever-only). D6 (hunter cast-safety) is deferred - in-game timing needed.
-- D4 keeps the target_count arms with filed-skeleton comments (removal would
-- break the pinned evaluator contract below); D8 is comment-only.

-- D1: a level 1-3 paladin knows no Seal - hold, never prompt an unlearned one.
out = FG.evaluate("PALADIN", "general", {})
eq(out.action, nil, "D1: L1 general paladin with nothing known prompts no action")
eq(out.hold, true, "D1: L1 general paladin holds")
eq(out.hold_text, "WAIT", "D1: L1 general paladin hold text is WAIT")
out = FG.evaluate("PALADIN", "ret", {})
eq(out.action, nil, "D1: L1 ret paladin with nothing known prompts no action")
eq(out.hold, true, "D1: L1 ret paladin holds")
eq(out.hold_text, "WAIT", "D1: L1 ret paladin hold text is WAIT")
-- Level 4+ with Seal of Righteousness known still gets the seal upkeep.
out = FG.evaluate("PALADIN", "general", { ["Seal of Righteousness"] = true, seal_inactive = true })
eq(out.action, "sor", "D1: SoR known still prompts the seal upkeep")
out = FG.evaluate("PALADIN", "ret", { ["Seal of Righteousness"] = true, seal_active = false, judge_remaining = 4, holy_strike_remaining = 4 })
eq(out.action, "sor", "D1: ret with SoR known (no SoC) still prompts sor")

-- D2: a level 1 hunter knows nothing - hold instead of a blank guide.
out = FG.evaluate("HUNTER", "ranged", {})
eq(out.action, nil, "D2: L1 hunter with nothing known prompts no action")
eq(out.hold, true, "D2: L1 hunter holds")
eq(out.hold_text, "WAIT", "D2: L1 hunter hold text is WAIT")
eq(out.rotation_key, "ranged", "D2: L1 hunter still resolves the ranged rotation")

-- D3: caster druid is unmodeled - hold instead of returning an empty out.
out = FG.evaluate("DRUID", "caster", {})
eq(out.action, nil, "D3: caster druid prompts no action")
eq(out.hold, true, "D3: caster druid holds")
eq(out.hold_text, "WAIT", "D3: caster druid hold text is WAIT")

-- D4 (filed, kept): the target_count arms stay pinned for direct callers until
-- the enemy-count sensor lands; the gather never feeds target_count on Forever.
out = FG.evaluate("WARRIOR", "prot", { ["Thunder Clap"] = true, rage = 25, target_count = 2 })
eq(out.action, "thunder_clap", "D4: filed prot TC arm still fires for direct callers")
out = FG.evaluate("WARRIOR", "arms", { ["Cleave"] = true, rage = 45, target_count = 2 })
eq(out.action, "cleave", "D4: filed arms cleave arm still fires for direct callers")

-- D5: every guide slot whose spell has a cooldown input carries the swipe key;
-- slots without one (dots, seals, rage dumps, rogue energy) stay keyless.
-- Structural only: the frame paints the swipe, never asserted here.
local function d5_slot(class, key)
    local slots = FG.get_guide_slots(class)
    for i = 1, #slots do
        if slots[i].key == key then return slots[i] end
    end
    return nil
end
local d5_ms = d5_slot("WARRIOR", "ms")
check(d5_ms ~= nil, "D5: warrior ms slot exists")
eq(d5_ms.cooldown_key, "ms", "D5: warrior ms slot carries cooldown_key ms")
check(d5_ms.swipe_duration ~= nil, "D5: warrior ms slot carries a swipe fallback")
local d5_tc = d5_slot("WARRIOR", "thunder_clap")
eq(d5_tc.cooldown_key, "tc", "D5: thunder_clap slot names the tc input base")
local d5_judge = d5_slot("PALADIN", "judge")
eq(d5_judge.cooldown_key, "judge", "D5: paladin judge slot carries cooldown_key judge")
eq(d5_judge.swipe_duration, 8, "D5: judge swipe fallback is the class slot's own 8 s")
local d5_ss = d5_slot("SHAMAN", "stormstrike")
eq(d5_ss.cooldown_key, "stormstrike", "D5: shaman stormstrike slot carries its cooldown key")
eq(d5_ss.swipe_duration, 10, "D5: stormstrike swipe fallback is the shipped 10 s")
local d5_fs = d5_slot("SHAMAN", "flameshock")
eq(d5_fs.cooldown_key, "flameshock", "D5: flameshock slot follows the debuff-window input")
local d5_arc = d5_slot("HUNTER", "arcane")
eq(d5_arc.cooldown_key, "arcane", "D5: hunter arcane slot carries its structural key")
local d5_fr = d5_slot("DRUID", "frenzied_regen")
eq(d5_fr.cooldown_key, "frenzied_regen", "D5: frenzied_regen slot carries its cooldown key")
eq(d5_fr.swipe_duration, 180, "D5: frenzied_regen swipe fallback is the class slot's own 180 s")
local d5_rogue_ss = d5_slot("ROGUE", "ss")
check(d5_rogue_ss ~= nil, "D5: rogue ss slot exists")
eq(d5_rogue_ss.cooldown_key, nil, "D5: rogue ss stays keyless (energy, no cooldown input)")
local d5_sor = d5_slot("PALADIN", "sor")
eq(d5_sor.cooldown_key, nil, "D5: seal slots stay keyless (no cooldown)")
local d5_serpent = d5_slot("HUNTER", "serpent")
eq(d5_serpent.cooldown_key, nil, "D5: serpent stays keyless (dot, no cooldown input)")

-- D7: the watershield alias reads the dedicated producer, not Lightningshield.
out = FG.evaluate("SHAMAN", "enhancement", { ["Water Shield"] = true, watershield_due = true, flameshock_active = true, stormstrike_remaining = 5, shock_remaining = 5 })
eq(out.action, "watershield", "D7: watershield_due=true prompts Water Shield")
eq(out.spell_name, "Water Shield", "D7: Water Shield prompt carries the name")
out = FG.evaluate("SHAMAN", "enhancement", { ["Water Shield"] = true, watershield_due = false, lightningshield_due = true, flameshock_active = true, stormstrike_remaining = 5, shock_remaining = 5 })
check(out.action ~= "watershield", "D7: watershield_due=false suppresses even when LS is due")
-- The alias bug this replaces: with LS unknown the old alias read nil and the
-- engine prompted Water Shield even while it was already up. The dedicated
-- producer suppresses on its own reading.
out = FG.evaluate("SHAMAN", "enhancement", { ["Water Shield"] = true, watershield_due = false, flameshock_active = true, stormstrike_remaining = 5, shock_remaining = 5 })
check(out.action ~= "watershield", "D7: an active Water Shield suppresses its own prompt")

if failures == 0 then
    print(string.format("PASS  forever_guide_state.lua (%d checks)", checks))
else
    print(string.format("FAIL  forever_guide_state.lua (%d failures / %d checks)", failures, checks))
    os.exit(1)
end
