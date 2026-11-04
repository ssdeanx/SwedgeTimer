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

out = FG.evaluate("ROGUE", "mutilate", { combo_points = 4, ["Envenom"] = true, envenom_usable = true, energy = 40, snd_remaining = 10 })
eq(out.action, "envenom", "rogue: envenom finisher by name")
eq(out.spell_name, "Envenom", "rogue: spell name is Envenom")

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

local function has_key(class, key)
    local slots = FG.get_guide_slots(class)
    for i = 1, #slots do
        if slots[i].key == key then return true end
    end
    return false
end
check(has_key("HUNTER", "raptor_strike"), "guide slot key matches action: raptor_strike")
check(has_key("HUNTER", "aspect_hawk"), "guide slot key matches action: aspect_hawk")
check(has_key("DRUID", "ferocious_bite") and has_key("DRUID", "demoralizing_roar"), "guide slot keys match druid actions")
check(has_key("ROGUE", "ea"), "guide slot key matches rogue action: ea")

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

if failures == 0 then
    print(string.format("PASS  forever_guide_state.lua (%d checks)", checks))
else
    print(string.format("FAIL  forever_guide_state.lua (%d failures / %d checks)", failures, checks))
    os.exit(1)
end
