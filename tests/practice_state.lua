-- tests/practice_state.lua: unit tests for the pure Twist Practice simulation engine in
-- practice.lua (port phase 1). Sandbox-loads nextaction.lua first (practice.lua delegates
-- its rotation thresholds to st.nextaction.calculate_rotation) and then practice.lua with
-- a setmetatable environment (__index = _G); neither module needs LibStub or WoW globals.
-- The expected values pin the archived engine (docs/swedge/SwedgeTimer_Forever/practice.lua
-- lines referenced in the practice.lua header).
-- Run from the repo root: lua5.1 tests/practice_state.lua

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

local pmod = assert(loadfile(ROOT .. "practice.lua"))
setfenv(pmod, env)
local ok2, err2 = pcall(function() pmod("SwedgeTimer", st) end)
check(ok2, "practice.lua loads under the sandbox (" .. tostring(err2) .. ")")
local pr = st.practice
check(type(pr) == "table", "st.practice table exists")

local out = {}
local function clear_out()
    for k in pairs(out) do out[k] = nil end
    return out
end

-- constants ----------------------------------------------------------------
eq(pr.SEAL_FADE_SECONDS, 0.4, "SEAL_FADE_SECONDS == 0.4")
check(type(pr.ABILITIES) == "table", "ABILITIES table exists")
eq(pr.ABILITIES.soc.seal_label, "command", "soc seal_label command")
eq(pr.ABILITIES.sob.seal_label, "blood", "sob seal_label blood")
eq(pr.ABILITIES.sotc.seal_label, "crusader", "sotc seal_label crusader")
eq(pr.ABILITIES.soc.spell_id, 20375, "soc spell id")
eq(pr.ABILITIES.sob.spell_id, 31892, "sob spell id")
eq(pr.ABILITIES.sotc.spell_id, 21082, "sotc spell id")
eq(pr.ABILITIES.cs.spell_id, 35395, "cs spell id")
eq(pr.ABILITIES.cs.cooldown, 6, "cs cooldown 6")
eq(pr.ABILITIES.judge.spell_id, 20271, "judge spell id")
eq(pr.ABILITIES.judge.cooldown, 8, "judge cooldown 8")
eq(pr.ABILITIES.consec.cooldown, 8, "consec cooldown 8")
eq(pr.ABILITIES.aw.type, "buff", "aw is a buff")
eq(pr.ABILITIES.aw.cooldown, 180, "aw cooldown 180")
eq(pr.ABILITIES.aw.duration, 20, "aw duration 20")
eq(pr.ABILITIES.hpot.type, "haste_consumable", "hpot type")
eq(pr.ABILITIES.hpot.duration, 15, "hpot duration 15")
eq(pr.ABILITIES.abacus.type, "haste_trinket", "abacus type")
eq(pr.ABILITIES.abacus.cooldown, 120, "abacus cooldown 120")
eq(pr.ABILITIES.abacus.duration, 10, "abacus duration 10")
eq(pr.ABILITIES.stop.type, "stopattack", "stop type")
eq(pr.ABILITY_ORDER[1], "soc", "ABILITY_ORDER starts with soc")
eq(pr.ABILITY_ORDER[2], "sob", "ABILITY_ORDER soc/sob")
eq(pr.ABILITY_ORDER[6], "consec", "ABILITY_ORDER consec position")
eq(pr.ABILITY_ORDER[10], "stop", "ABILITY_ORDER ends with stop")
eq(#pr.ABILITY_ORDER, 10, "ABILITY_ORDER has 10 keys")
eq(pr.PRESETS["1/2"].speed, 3.5, "preset 1/2 speed")
eq(pr.PRESETS["1/2"].gcd, 1.5, "preset 1/2 gcd")
eq(pr.PRESETS["2/3"].speed, 2.3, "preset 2/3 speed")
eq(pr.PRESETS["2/3"].gcd, 1.15, "preset 2/3 gcd")
eq(pr.PRESETS["2/4"].speed, 1.8, "preset 2/4 speed")
eq(pr.PRESETS["2/4"].gcd, 1.15, "preset 2/4 gcd")

-- new_sim --------------------------------------------------------------------
local sim = pr.new_sim()
check(type(sim.active_seals) == "table", "new_sim active_seals table")
eq(sim.n_active_seals, 0, "new_sim n_active_seals 0")
eq(sim.seal_1_label, nil, "new_sim seal_1_label nil")
eq(sim.seal_2_label, nil, "new_sim seal_2_label nil")
eq(sim.fading_seal_label, nil, "new_sim fading_seal_label nil")
eq(sim.fading_seal_expires, 0, "new_sim fading_seal_expires 0")
eq(sim.effective_speed, 3.5, "new_sim effective_speed 3.5")
eq(sim.effective_gcd, 1.5, "new_sim effective_gcd 1.5")
eq(sim.has_bloodlust, false, "new_sim has_bloodlust false")
eq(sim.has_haste_pot, false, "new_sim has_haste_pot false")
eq(sim.has_abacus, false, "new_sim has_abacus false")
eq(sim.has_dst, false, "new_sim has_dst false")
eq(sim.bl_buff_expires, 0, "new_sim bl_buff_expires 0")
eq(sim.haste_pot_buff_expires, 0, "new_sim haste_pot_buff_expires 0")
eq(sim.abacus_buff_expires, 0, "new_sim abacus_buff_expires 0")
eq(sim.abacus_cooldown_expires, 0, "new_sim abacus_cooldown_expires 0")
eq(sim.dst_buff_expires, 0, "new_sim dst_buff_expires 0")
eq(sim.dst_icd_expires, 0, "new_sim dst_icd_expires 0")
eq(sim.cs_cooldown_expires, 0, "new_sim cs_cooldown_expires 0")
eq(sim.judge_cooldown_expires, 0, "new_sim judge_cooldown_expires 0")
eq(sim.consec_cooldown_expires, 0, "new_sim consec_cooldown_expires 0")
eq(sim.aw_cooldown_expires, 0, "new_sim aw_cooldown_expires 0")
eq(sim.aw_buff_expires, 0, "new_sim aw_buff_expires 0")
eq(sim.fight_active, false, "new_sim fight_active false")
eq(sim.fight_start_time, 0, "new_sim fight_start_time 0")
eq(sim.fight_bl_delay, 0, "new_sim fight_bl_delay 0")
eq(sim.fight_bl_fired, false, "new_sim fight_bl_fired false")
eq(sim.attack_paused, false, "new_sim attack_paused false")
eq(sim.attack_pause_pending, false, "new_sim attack_pause_pending false")
eq(sim.swing_held, false, "new_sim swing_held false")
eq(sim.twist_attempted, false, "new_sim twist_attempted false")
eq(sim.queued_ability, nil, "new_sim queued_ability nil")
eq(sim.queue_timestamp, 0, "new_sim queue_timestamp 0")
eq(sim.swing_active, false, "new_sim swing_active false")
eq(sim.swing_ends_at, 0, "new_sim swing_ends_at 0")
eq(sim.gcd_active, false, "new_sim gcd_active false")
eq(sim.gcd_expires, 0, "new_sim gcd_expires 0")
eq(sim.queue_window, 0.4, "new_sim queue_window 0.4")
eq(sim.locked_rotation, nil, "new_sim locked_rotation nil")
local sim_b = pr.new_sim()
sim.active_seals.blood = true
check(sim_b.active_seals.blood == nil, "new_sim tables are not shared between instances")

-- apply_haste ------------------------------------------------------------------
local function hasted(base, pot, dst, abacus, bl)
    local s = pr.new_sim()
    s.has_haste_pot = pot or false
    s.has_dst = dst or false
    s.has_abacus = abacus or false
    s.has_bloodlust = bl or false
    pr.apply_haste(s, base, 0)
    return s.effective_speed, s.effective_gcd
end

local sp, gc = hasted(3.5)
eq(sp, 3.5, "haste: no buffs keeps 3.5")
eq(gc, 1.5, "haste: no buffs keeps 1.5 gcd")
sp, gc = hasted(3.5, true)
eq(sp, 2.792, "haste: pot 400 rating -> 2.792")
eq(gc, 1.197, "haste: pot 400 rating -> 1.197 gcd")
sp, gc = hasted(3.5, false, true)
eq(sp, 2.902, "haste: dst 325 rating -> 2.902")
eq(gc, 1.244, "haste: dst 325 rating -> 1.244 gcd")
sp, gc = hasted(3.5, false, false, true)
eq(sp, 3.005, "haste: abacus 260 rating -> 3.005")
eq(gc, 1.288, "haste: abacus 260 rating -> 1.288 gcd")
sp, gc = hasted(3.5, true, true)
eq(sp, 2.398, "haste: pot+dst 725 rating -> 2.398")
eq(gc, 1.028, "haste: pot+dst 725 rating -> 1.028 gcd")
sp, gc = hasted(3.5, true, true, true)
eq(sp, 2.154, "haste: all ratings 985 -> 2.154")
eq(gc, 1.0, "haste: all ratings 985 -> gcd floors at 1.0")
sp, gc = hasted(3.5, false, false, false, true)
eq(sp, 2.692, "haste: bloodlust only -> 2.692")
eq(gc, 1.154, "haste: bloodlust only -> 1.154 gcd")
sp, gc = hasted(3.5, true, false, false, true)
eq(sp, 2.148, "haste: bloodlust+pot -> 2.148")
eq(gc, 1.0, "haste: bloodlust+pot -> gcd floors at 1.0")
sp = hasted(3.5, false, true, false, true)
eq(sp, 2.232, "haste: bloodlust+dst -> 2.232")
sp = hasted(3.5, false, false, true, true)
eq(sp, 2.311, "haste: bloodlust+abacus -> 2.311")
sp = hasted(3.5, true, true, false, true)
eq(sp, 1.844, "haste: rating + bloodlust multiply separately -> 1.844")
sp, gc = hasted(3.5, true, true, true, true)
eq(sp, 1.657, "haste: all ratings + bloodlust -> 1.657")
eq(gc, 1.0, "haste: all ratings + bloodlust gcd floor")
sp = hasted(nil)
eq(sp, 3.5, "haste: nil base_speed falls back to 3.5")
sp = hasted(0)
eq(sp, 3.5, "haste: base_speed <= 0 falls back to 3.5")
sp, gc = hasted(2.6)
eq(sp, 2.6, "haste: base speed passes through")
eq(gc, 1.5, "haste: gcd stays 1.5 with no buffs")

-- locked presets bypass all haste
local ls = pr.new_sim()
ls.has_haste_pot = true
ls.has_bloodlust = true
ls.locked_rotation = "1/2"
pr.apply_haste(ls, 2.6, 0)
eq(ls.effective_speed, 3.5, "locked 1/2 overrides haste sources")
eq(ls.effective_gcd, 1.5, "locked 1/2 gcd from preset")
ls.locked_rotation = "2/3"
pr.apply_haste(ls, 3.5, 0)
eq(ls.effective_speed, 2.3, "locked 2/3 speed")
eq(ls.effective_gcd, 1.15, "locked 2/3 gcd")
ls.locked_rotation = "2/4"
pr.apply_haste(ls, 3.5, 0)
eq(ls.effective_speed, 1.8, "locked 2/4 speed")
eq(ls.effective_gcd, 1.15, "locked 2/4 gcd")
ls.locked_rotation = "bogus"
ls.has_bloodlust = false
pr.apply_haste(ls, 3.5, 0)
eq(ls.effective_speed, 2.792, "unknown locked key falls through to normal haste")

-- swing rescale mirrors the archive's remaining-time cap
local rs = pr.new_sim()
pr.begin_fight(rs, 1.0, { bl_delay = 0 })
near(rs.swing_ends_at, 4.5, "begin_fight starts the swing at the current effective speed")
pr.apply_haste(rs, 3.5, 1.4)
eq(rs.effective_speed, 2.692, "rescale case: bloodlust speed")
near(rs.swing_ends_at, 1.4 + 2.692, "apply_haste caps a longer remaining swing to the new speed")
pr.apply_haste(rs, 3.5, 2.0)
near(rs.swing_ends_at, 1.4 + 2.692, "apply_haste leaves a shorter remaining swing alone")
local lr = pr.new_sim()
pr.begin_fight(lr, 0, { locked_rotation = "2/4", bl_delay = 999 })
pr.apply_haste(lr, 3.5, 0)
eq(lr.effective_speed, 1.8, "locked rescale: preset speed")
near(lr.swing_ends_at, 1.8, "locked preset caps the swing remaining time")
local lr2 = pr.new_sim()
pr.begin_fight(lr2, 0, { locked_rotation = "1/2", bl_delay = 999 })
near(lr2.swing_ends_at, 3.5, "locked 1/2 swing starts at the default 3.5")
pr.apply_haste(lr2, 3.5, 0)
near(lr2.swing_ends_at, 3.5, "locked 1/2 does not rescale an equal remaining time")
local ns = pr.new_sim()
ns.swing_ends_at = 99
pr.apply_haste(ns, 2.0, 0)
near(ns.swing_ends_at, 99, "apply_haste ignores swing_ends_at when no swing is active")

-- determine_rotation -----------------------------------------------------------
local dr = pr.new_sim()
pr.apply_haste(dr, 3.5, 0)
eq(pr.determine_rotation(dr), "1/2", "rotation: default 3.5/1.5 -> 1/2")
eq(pr.determine_rotation(dr, "2/3"), "2/3", "rotation: explicit locked key wins")
dr.locked_rotation = "2/4"
eq(pr.determine_rotation(dr), "2/4", "rotation: sim.locked_rotation is honoured")
eq(pr.determine_rotation(dr, "1/2"), "1/2", "rotation: explicit key beats sim.locked_rotation")
dr.locked_rotation = nil
dr.effective_speed = 2.45
dr.effective_gcd = 1.5
eq(pr.determine_rotation(dr), "2/2/5", "rotation: 2.45/1.5 -> 2/2/5")
dr.effective_speed = 2.25
dr.effective_gcd = 1.3
eq(pr.determine_rotation(dr), "2/3", "rotation: 2.25/1.3 -> 2/3")
dr.effective_speed = 2.0
dr.effective_gcd = 1.3
eq(pr.determine_rotation(dr), "2/4", "rotation: 2.0/1.3 -> 2/4")
dr.effective_gcd = 1.5
eq(pr.determine_rotation(dr), "1/3", "rotation: 2.0/1.5 -> 1/3")
dr.effective_speed = 1.6
eq(pr.determine_rotation(dr), "2/5_blood", "rotation: 1.6/1.5 -> 2/5_blood")
dr.effective_speed = 1.2
eq(pr.determine_rotation(dr), "2/5_command", "rotation: 1.2/1.5 -> 2/5_command")
dr.effective_speed = 0.9
eq(pr.determine_rotation(dr), "2007", "rotation: 0.9/1.5 -> 2007")
dr.effective_speed = 0.005
eq(pr.determine_rotation(dr), nil, "rotation: below 0.01 -> nil")
local parity_mismatch = 0
local parity_speeds = { 3.5, 3.0, 2.7, 2.61, 2.6, 2.5, 2.45, 2.3, 2.25, 2.2, 2.0, 1.95, 1.9, 1.85, 1.7, 1.6, 1.5, 1.2, 1.05, 1.0, 0.9, 0.5, 0.01, 0.005 }
local parity_gcds = { 1.5, 1.4, 1.3, 1.2, 1.15, 1.1, 1.05, 1.0 }
local psim = pr.new_sim()
for _, s in ipairs(parity_speeds) do
    for _, g in ipairs(parity_gcds) do
        psim.effective_speed = s
        psim.effective_gcd = g
        local got = pr.determine_rotation(psim)
        local want = na.calculate_rotation(s, g)
        if got ~= want then
            parity_mismatch = parity_mismatch + 1
            if parity_mismatch == 1 then
                print("      first parity mismatch at speed " .. s .. " gcd " .. g)
            end
        end
    end
end
eq(parity_mismatch, 0, "rotation parity with st.nextaction.calculate_rotation across " .. (#parity_speeds * #parity_gcds) .. " speed/gcd combos")

-- cast: seals -------------------------------------------------------------------
local s1 = pr.new_sim()
pr.cast(s1, "soc", 0, out)
eq(out.seal_changed, true, "cast soc: seal_changed")
eq(out.twist_armed, false, "cast soc: no twist armed")
eq(out.gcd_started, true, "cast soc: gcd started")
eq(out.ignored, false, "cast soc: not ignored")
eq(out.gcd_blocked, false, "cast soc: not gcd blocked")
eq(s1.active_seals.command, true, "cast soc: command seal active")
eq(s1.n_active_seals, 1, "cast soc: one active seal")
eq(s1.seal_1_label, "command", "cast soc: seal_1 command")
eq(s1.seal_2_label, nil, "cast soc: no seal_2")
eq(s1.gcd_active, true, "cast soc: gcd_active true")
eq(s1.gcd_expires, 1.5, "cast soc: gcd expires at effective_gcd")

pr.cast(s1, "sob", 2, out)
eq(out.twist_armed, true, "seal swap: twist_armed")
eq(out.seal_changed, true, "seal swap: seal_changed")
eq(s1.n_active_seals, 2, "seal swap: dual seals")
eq(s1.seal_1_label, "command", "seal swap: command is the older seal")
eq(s1.seal_2_label, "blood", "seal swap: blood is the newer seal")
eq(s1.fading_seal_label, "command", "seal swap: command fades")
eq(s1.fading_seal_expires, 2.4, "seal swap: fade expires after SEAL_FADE_SECONDS")
eq(s1.twist_attempted, true, "seal swap: twist_attempted set")
eq(s1.active_seals.command, true, "seal swap: both seals active (command)")
eq(s1.active_seals.blood, true, "seal swap: both seals active (blood)")

pr.cast(s1, "sob", 4, out)
eq(out.twist_armed, true, "recast newer seal during dual: re-arms twist")
eq(s1.n_active_seals, 2, "recast newer seal during dual: still dual")
eq(s1.fading_seal_expires, 4.4, "recast newer seal during dual: fade timer restarts")

pr.cast(s1, "soc", 6, out)
eq(out.twist_armed, false, "recast older seal during dual: collapses (archive quirk)")
eq(s1.n_active_seals, 1, "recast older seal during dual: single seal")
eq(s1.seal_1_label, "command", "recast older seal during dual: command stays")
eq(s1.seal_2_label, nil, "recast older seal during dual: no seal_2")
eq(s1.fading_seal_label, nil, "recast older seal during dual: fade cleared")

local s2 = pr.new_sim()
pr.cast(s2, "soc", 0, out)
pr.cast(s2, "soc", 2, out)
eq(s2.n_active_seals, 1, "same-seal recast: single seal kept")
eq(s2.seal_1_label, "command", "same-seal recast: label kept")
eq(s2.fading_seal_label, nil, "same-seal recast: no fading seal")
eq(s2.twist_attempted, false, "same-seal recast: no twist attempt")

local s3 = pr.new_sim()
pr.cast(s3, "sotc", 0, out)
eq(s3.seal_1_label, "crusader", "sotc applies the crusader seal")

-- tick: fading seal --------------------------------------------------------------
local t1 = pr.new_sim()
pr.cast(t1, "soc", 0, out)
pr.cast(t1, "sob", 2, out)
clear_out()
pr.tick(t1, 2.3, 0.016, out)
eq(out.seal_faded, false, "tick before fade: no seal_faded")
eq(t1.n_active_seals, 2, "tick before fade: dual seals kept")
pr.tick(t1, 2.4, 0.016, out)
eq(out.seal_faded, true, "tick at fade expiry: seal_faded")
eq(t1.fading_seal_label, nil, "tick at fade expiry: fading label cleared")
eq(t1.n_active_seals, 1, "tick at fade expiry: one seal remains")
eq(t1.seal_1_label, "blood", "tick at fade expiry: newer seal (blood) remains")
eq(t1.seal_2_label, nil, "tick at fade expiry: no seal_2")
eq(t1.active_seals.command, nil, "tick at fade expiry: command removed")

-- judge --------------------------------------------------------------------------
local j1 = pr.new_sim()
pr.cast(j1, "judge", 0, out)
eq(out.ignored, true, "judge without a seal: ignored")
eq(out.cooldown_set, false, "judge without a seal: no cooldown")
eq(j1.judge_cooldown_expires, 0, "judge without a seal: cooldown untouched")

pr.cast(j1, "soc", 0, out)
pr.cast(j1, "judge", 2, out)
eq(out.ignored, false, "judge with a seal: fires")
eq(out.judged_seal, "command", "judge: command wins the snapshot")
eq(out.cooldown_set, true, "judge: cooldown set")
eq(out.gcd_started, false, "judge: no GCD")
eq(out.seal_changed, true, "judge: seal state changed (consumed)")
eq(j1.judge_cooldown_expires, 10, "judge: 8s cooldown")
eq(j1.n_active_seals, 0, "judge consumes all seals")
eq(j1.seal_1_label, nil, "judge: seal_1 cleared")
eq(j1.active_seals.command, nil, "judge: command consumed")

pr.cast(j1, "soc", 3, out)
pr.cast(j1, "judge", 4, out)
eq(out.ignored, true, "judge on cooldown: ignored")
eq(j1.n_active_seals, 1, "judge on cooldown: seals untouched")

local j2 = pr.new_sim()
pr.cast(j2, "sob", 0, out)
pr.cast(j2, "soc", 2, out)
pr.cast(j2, "judge", 4, out)
eq(out.judged_seal, "command", "judge with dual seals: command wins")
eq(j2.n_active_seals, 0, "judge with dual seals: both consumed")

local j3 = pr.new_sim()
pr.cast(j3, "sotc", 0, out)
pr.cast(j3, "sob", 2, out)
pr.cast(j3, "judge", 4, out)
eq(out.judged_seal, "blood", "judge with crusader+blood: blood wins")
eq(j3.n_active_seals, 0, "judge consumes crusader+blood")

-- cs / consec cooldowns ----------------------------------------------------------
local c1 = pr.new_sim()
pr.cast(c1, "cs", 0, out)
eq(out.cooldown_set, true, "cs: cooldown set")
eq(out.gcd_started, true, "cs: GCD started")
eq(c1.cs_cooldown_expires, 6, "cs: 6s cooldown")
pr.cast(c1, "cs", 2, out)
eq(out.ignored, true, "cs on cooldown: ignored")
eq(c1.cs_cooldown_expires, 6, "cs on cooldown: cooldown unchanged")
pr.cast(c1, "cs", 7, out)
eq(out.ignored, false, "cs after cooldown: fires")
eq(c1.cs_cooldown_expires, 13, "cs after cooldown: new expiry")
pr.cast(c1, "consec", 14, out)
eq(out.ignored, false, "consec fires")
eq(c1.consec_cooldown_expires, 22, "consec: 8s cooldown")

-- GCD block / queue ---------------------------------------------------------------
local q1 = pr.new_sim()
pr.cast(q1, "soc", 0, out)
pr.cast(q1, "cs", 0.9, out)
eq(out.gcd_blocked, true, "gcd 0.6 remaining: blocked")
eq(out.queued, false, "gcd 0.6 remaining: not queued")
eq(q1.queued_ability, nil, "gcd 0.6 remaining: nothing queued")
pr.cast(q1, "cs", 1.2, out)
eq(out.gcd_blocked, true, "gcd 0.3 remaining: blocked")
eq(out.queued, true, "gcd 0.3 remaining: queued")
eq(q1.queued_ability, "cs", "queued ability recorded")
eq(q1.queue_timestamp, 1.2, "queue timestamp recorded")
pr.cast(q1, "cs", 1.3, out)
eq(q1.queued_ability, "cs", "a later in-window press replaces the queue entry")
local q1s = pr.new_sim()
q1s.queue_window = 0
pr.cast(q1s, "soc", 0, out)
pr.cast(q1s, "cs", 1.2, out)
eq(out.queued, false, "queue_window 0: press dropped")
eq(q1s.queued_ability, nil, "queue_window 0: nothing queued")
local q1n = pr.new_sim()
q1n.queue_window = nil
pr.cast(q1n, "soc", 0, out)
pr.cast(q1n, "cs", 1.2, out)
eq(out.queued, true, "nil queue_window falls back to the 0.4s default")
local qw = pr.new_sim()
qw.queue_window = 1.0
pr.cast(qw, "soc", 0, out)
pr.cast(qw, "cs", 0.6, out)
eq(out.queued, true, "widened queue window accepts a farther press")

-- off-GCD casts ignore the GCD
local og = pr.new_sim()
pr.cast(og, "soc", 0, out)
pr.cast(og, "judge", 0.5, out)
eq(out.ignored, false, "judge casts during the GCD")
eq(out.judged_seal, "command", "judge during GCD consumed the seal")
eq(og.judge_cooldown_expires, 8.5, "judge during GCD: cooldown set")
pr.cast(og, "aw", 0.6, out)
eq(out.ignored, false, "aw casts during the GCD")
eq(out.buff_changed, true, "aw during GCD: buff applied")
pr.cast(og, "sob", 0.7, out)
pr.cast(og, "abacus", 0.8, out)
eq(out.ignored, false, "abacus casts during the GCD")
eq(out.buff_changed, true, "abacus during GCD: buff applied")

-- queue processing on GCD end -----------------------------------------------------
local q2 = pr.new_sim()
pr.begin_fight(q2, 0, { bl_delay = 999 })
pr.cast(q2, "soc", 0, out)
pr.cast(q2, "cs", 1.2, out)
eq(out.queued, true, "fight: cs queued inside the window")
clear_out()
pr.tick(q2, 1.5, 0.016, out)
eq(out.queue_ready, true, "tick at GCD end: queued ability fired")
eq(out.gcd_started, true, "queue-fired cs started a new GCD")
eq(out.cooldown_set, true, "queue-fired cs set its cooldown")
eq(q2.cs_cooldown_expires, 7.5, "queue-fired cs cooldown from fire time")
eq(q2.queued_ability, nil, "queue cleared after firing")
eq(q2.gcd_active, true, "GCD restarted by the queued cast")
eq(q2.gcd_expires, 3.0, "new GCD expiry from the queued cast")
clear_out()
pr.tick(q2, 3.0, 0.016, out)
eq(out.queue_ready, false, "nothing queued: no queue_ready")

-- queue re-validates cooldowns at fire time
local q3 = pr.new_sim()
pr.begin_fight(q3, 0, { bl_delay = 999 })
pr.cast(q3, "cs", 0, out)
pr.cast(q3, "cs", 1.2, out)
eq(q3.queued_ability, "cs", "cs on cooldown still queues (GCD gate runs first)")
clear_out()
pr.tick(q3, 1.5, 0.016, out)
eq(out.queue_ready, false, "queued cs dropped by cooldown re-validation")
eq(q3.queued_ability, nil, "queue consumed on the failed re-validation")
eq(q3.cs_cooldown_expires, 6, "re-validation does not extend the cooldown")

-- queue dropped outside a fight / while paused
local q4 = pr.new_sim()
pr.cast(q4, "soc", 0, out)
pr.cast(q4, "cs", 1.2, out)
pr.tick(q4, 1.5, 0.016, out)
eq(out.queue_ready, false, "queue outside a fight: no fire")
eq(q4.cs_cooldown_expires, 0, "queue outside a fight: cs not fired")
eq(q4.queued_ability, nil, "queue outside a fight: consumed")
local q5 = pr.new_sim()
pr.begin_fight(q5, 0, { bl_delay = 999 })
q5.attack_paused = true
pr.cast(q5, "soc", 0, out)
pr.cast(q5, "cs", 1.2, out)
pr.tick(q5, 1.5, 0.016, out)
eq(out.queue_ready, false, "queue while paused: no fire")
eq(q5.queued_ability, nil, "queue while paused: consumed")
pr.pause_attack(q5, 2.0)
q5.attack_paused = false
pr.cast(q5, "soc", 3.0, out)
pr.cast(q5, "cs", 4.2, out)
pr.pause_attack(q5, 4.3)
eq(q5.queued_ability, nil, "pause_attack clears the queue")
eq(q5.attack_pause_pending, true, "pause_attack mid-swing sets the pending flag")

-- buffs: AW -----------------------------------------------------------------------
local b1 = pr.new_sim()
pr.cast(b1, "aw", 0, out)
eq(out.buff_changed, true, "aw: buff_changed")
eq(out.cooldown_set, true, "aw: cooldown_set")
eq(out.gcd_started, false, "aw: no GCD")
eq(b1.aw_cooldown_expires, 180, "aw: 180s cooldown")
eq(b1.aw_buff_expires, 20, "aw: 20s buff")
pr.cast(b1, "aw", 10, out)
eq(out.ignored, true, "aw on cooldown: ignored")
clear_out()
pr.tick(b1, 20, 0.016, out)
eq(b1.aw_buff_expires, 0, "aw buff expires on tick")
eq(out.buffs_changed, true, "aw expiry: buffs_changed")

-- buffs: haste pot ----------------------------------------------------------------
local b2 = pr.new_sim()
pr.cast(b2, "hpot", 0, out)
eq(out.buff_changed, true, "hpot: buff_changed")
eq(out.gcd_started, true, "hpot: GCD started")
eq(b2.has_haste_pot, true, "hpot: active")
eq(b2.haste_pot_buff_expires, 15, "hpot: 15s duration")
pr.cast(b2, "hpot", 2, out)
eq(out.buff_changed, false, "hpot recast while up: no refresh")
eq(out.gcd_started, true, "hpot recast while up still starts a GCD (archive quirk)")
eq(b2.haste_pot_buff_expires, 15, "hpot recast while up: expiry unchanged")
local b2l = pr.new_sim()
b2l.locked_rotation = "1/2"
pr.cast(b2l, "hpot", 0, out)
eq(out.ignored, true, "hpot while locked: ignored")
eq(b2l.has_haste_pot, false, "hpot while locked: not applied")
local b2q = pr.new_sim()
pr.begin_fight(b2q, 0, { bl_delay = 999 })
b2q.locked_rotation = "1/2"
pr.cast(b2q, "cs", 0, out)
pr.cast(b2q, "hpot", 1.2, out)
eq(out.queued, true, "hpot while locked: GCD gate queues before the locked check")
clear_out()
pr.tick(b2q, 1.5, 0.016, out)
eq(out.ignored, true, "queued hpot while locked: ignored at fire time")
eq(b2q.has_haste_pot, false, "queued hpot while locked: never applied")

-- buffs: abacus -------------------------------------------------------------------
local b3 = pr.new_sim()
pr.cast(b3, "abacus", 0, out)
eq(out.buff_changed, true, "abacus: buff_changed")
eq(out.cooldown_set, true, "abacus: cooldown_set")
eq(out.gcd_started, false, "abacus: no GCD")
eq(b3.has_abacus, true, "abacus: active")
eq(b3.abacus_buff_expires, 10, "abacus: 10s buff")
eq(b3.abacus_cooldown_expires, 120, "abacus: 120s cooldown")
pr.cast(b3, "abacus", 5, out)
eq(out.ignored, true, "abacus on cooldown: ignored")
clear_out()
pr.tick(b3, 10, 0.016, out)
eq(b3.has_abacus, false, "abacus buff expires on tick")
eq(out.buffs_changed, true, "abacus expiry: buffs_changed")
eq(b3.abacus_cooldown_expires, 120, "abacus cooldown survives the buff expiry")
pr.cast(b3, "abacus", 121, out)
eq(out.ignored, false, "abacus after cooldown: fires")
eq(b3.abacus_cooldown_expires, 241, "abacus second activation cooldown")
local b3b = pr.new_sim()
b3b.has_abacus = true
pr.cast(b3b, "abacus", 0, out)
eq(out.ignored, true, "abacus while buff active (cd free): ignored, no refresh")
eq(b3b.abacus_buff_expires, 0, "abacus while buff active: expiry untouched")
local b3l = pr.new_sim()
b3l.locked_rotation = "2/3"
pr.cast(b3l, "abacus", 0, out)
eq(out.ignored, true, "abacus while locked: ignored")

-- begin_fight / end_fight ----------------------------------------------------------
local f1 = pr.new_sim()
pr.begin_fight(f1, 100, { bl_delay = 0 })
eq(f1.fight_active, true, "begin_fight: active")
eq(f1.fight_start_time, 100, "begin_fight: start time")
eq(f1.fight_bl_delay, 0, "begin_fight: delay recorded")
eq(f1.fight_bl_fired, true, "begin_fight: zero delay fires immediately")
eq(f1.has_bloodlust, true, "begin_fight: Bloodlust active")
eq(f1.bl_buff_expires, 140, "begin_fight: Bloodlust 40s")
eq(f1.seal_1_label, "blood", "begin_fight: starts on Seal of Blood")
eq(f1.n_active_seals, 1, "begin_fight: one seal")
eq(f1.swing_active, true, "begin_fight: swing started")
near(f1.swing_ends_at, 103.5, "begin_fight: swing ends after effective_speed")
pr.begin_fight(f1, 200, { bl_delay = 0 })
eq(f1.fight_start_time, 100, "begin_fight while fighting: no-op")

local f2 = pr.new_sim()
pr.begin_fight(f2, 0, { bl_delay = 5 })
eq(f2.fight_bl_fired, false, "begin_fight: delayed BL not fired")
eq(f2.has_bloodlust, false, "begin_fight: delayed BL not active")
clear_out()
pr.tick(f2, 4.9, 0.016, out)
eq(out.bl_fired, false, "delayed BL: tick before delay does not fire")
eq(out.fight_elapsed, true, "fight clock reports elapsed while active")
clear_out()
pr.tick(f2, 5.0, 0.016, out)
eq(out.bl_fired, true, "delayed BL fires at the delay")
eq(out.buffs_changed, true, "delayed BL marks buffs_changed")
eq(f2.has_bloodlust, true, "delayed BL active")
eq(f2.bl_buff_expires, 45, "delayed BL runs 40s from the fire time")
clear_out()
pr.tick(f2, 45.0, 0.016, out)
eq(f2.has_bloodlust, false, "Bloodlust expires on tick")
eq(out.buffs_changed, true, "Bloodlust expiry marks buffs_changed")
eq(out.bl_fired, false, "Bloodlust expiry does not re-fire the delay")

local f3 = pr.new_sim()
pr.begin_fight(f3, 0, { bl_delay = 0, locked_rotation = "1/2" })
eq(f3.fight_bl_fired, true, "locked fight: BL marked fired")
eq(f3.has_bloodlust, false, "locked fight: BL never fires")
clear_out()
pr.tick(f3, 50, 0.016, out)
eq(out.bl_fired, false, "locked fight: no BL after the delay either")
local f4 = pr.new_sim()
pr.begin_fight(f4, 0, { bl_delay = 5, locked_rotation = "2/3" })
clear_out()
pr.tick(f4, 10, 0.016, out)
eq(out.bl_fired, false, "locked fight with delay: still no BL")

local f5 = pr.new_sim()
pr.begin_fight(f5, 0, { bl_delay = 0 })
pr.cast(f5, "hpot", 1.6, out)
pr.cast(f5, "abacus", 2.0, out)
pr.cast(f5, "aw", 3.0, out)
pr.cast(f5, "cs", 3.5, out)
pr.cast(f5, "soc", 4.0, out)
pr.cast(f5, "judge", 5.5, out)
eq(pr.maybe_dst_proc(f5, 6.0, 0), true, "end_fight setup: DST proc")
eq(f5.has_dst, true, "end_fight setup: dst active")
pr.end_fight(f5)
eq(f5.fight_active, false, "end_fight: inactive")
eq(f5.fight_start_time, 0, "end_fight: start time cleared")
eq(f5.fight_bl_delay, 0, "end_fight: delay cleared")
eq(f5.fight_bl_fired, false, "end_fight: fired flag cleared")
eq(f5.has_bloodlust, false, "end_fight: Bloodlust cleared")
eq(f5.has_haste_pot, false, "end_fight: pot cleared")
eq(f5.has_abacus, false, "end_fight: abacus cleared")
eq(f5.has_dst, false, "end_fight: dst cleared")
eq(f5.cs_cooldown_expires, 0, "end_fight: cs cooldown cleared")
eq(f5.judge_cooldown_expires, 0, "end_fight: judge cooldown cleared")
eq(f5.consec_cooldown_expires, 0, "end_fight: consec cooldown cleared")
eq(f5.aw_cooldown_expires, 0, "end_fight: aw cooldown cleared")
eq(f5.aw_buff_expires, 0, "end_fight: aw buff cleared")
eq(f5.abacus_cooldown_expires, 0, "end_fight: abacus cooldown cleared")
eq(f5.dst_icd_expires, 0, "end_fight: dst ICD cleared")
eq(f5.swing_active, false, "end_fight: swing stopped")
eq(f5.attack_paused, false, "end_fight: attack not paused")
eq(f5.queued_ability, nil, "end_fight: queue cleared")
eq(f5.locked_rotation, nil, "end_fight: keeps the (nil) lock")
pr.end_fight(f5)
eq(f5.fight_active, false, "end_fight while inactive: no-op")
clear_out()
pr.tick(f5, 100, 0.016, out)
eq(out.fight_elapsed, false, "tick after end_fight: no fight clock")

-- reset (archive reset_sim_state + phase-1 fields) ---------------------------------
local r1 = pr.new_sim()
pr.begin_fight(r1, 0, { bl_delay = 0 })
pr.cast(r1, "soc", 1.0, out)
pr.cast(r1, "sob", 2.0, out)
r1.has_abacus = true
r1.has_dst = true
r1.effective_speed = 2.0
r1.locked_rotation = "2/3"
r1.twist_attempted = true
r1.queued_ability = "cs"
pr.reset(r1)
eq(r1.fight_active, false, "reset: fight inactive")
eq(r1.n_active_seals, 0, "reset: seals cleared")
eq(r1.seal_1_label, nil, "reset: seal_1 cleared")
eq(r1.fading_seal_label, nil, "reset: fading cleared")
eq(r1.has_bloodlust, false, "reset: bloodlust cleared")
eq(r1.has_haste_pot, false, "reset: pot cleared")
eq(r1.cs_cooldown_expires, 0, "reset: cs cooldown cleared")
eq(r1.judge_cooldown_expires, 0, "reset: judge cooldown cleared")
eq(r1.aw_cooldown_expires, 0, "reset: aw cooldown cleared")
eq(r1.aw_buff_expires, 0, "reset: aw buff cleared")
eq(r1.twist_attempted, false, "reset: twist_attempted cleared")
eq(r1.queued_ability, nil, "reset: queue cleared")
eq(r1.swing_held, false, "reset: held swing cleared")
eq(r1.swing_active, false, "reset: swing cleared")
eq(r1.gcd_active, false, "reset: GCD cleared")
eq(r1.has_abacus, true, "reset: abacus quirk - not reset (archive parity)")
eq(r1.has_dst, true, "reset: dst quirk - not reset (archive parity)")
eq(r1.effective_speed, 2.0, "reset: effective_speed kept (archive parity)")
eq(r1.locked_rotation, "2/3", "reset: locked rotation kept (archive parity)")

-- swing completion / on_swing ------------------------------------------------------
local w1 = pr.new_sim()
pr.begin_fight(w1, 0, { bl_delay = 999 })
clear_out()
pr.tick(w1, 3.4, 0.016, out)
eq(out.swing_ready, false, "swing not ready before the end time")
clear_out()
pr.tick(w1, 3.5, 0.016, out)
eq(out.swing_ready, true, "swing ready at the end time")
eq(w1.swing_active, false, "swing completion clears swing_active")
eq(w1.swing_ends_at, 3.5, "swing completion leaves swing_ends_at for the caller")
clear_out()
pr.on_swing(w1, 3.5, out)
eq(out.result, "miss", "on_swing with one seal: miss")
eq(out.twist_attempted, false, "on_swing: no twist attempted")
eq(out.feedback, nil, "on_swing: no feedback without a twist attempt")
eq(out.seal_consumed, nil, "on_swing: nothing consumed on a miss")
eq(out.timeline_event.lane, "melee", "on_swing payload lane melee")
eq(out.timeline_event.result, "miss", "on_swing payload result")
eq(out.timeline_event.seal, "blood", "on_swing payload seal")
eq(out.timeline_event.seal_active, "blood", "on_swing payload seal_active alias")
check(type(out.timeline_event.texture) == "string" and out.timeline_event.texture:find("INV_Sword_04") ~= nil,
    "on_swing payload texture")
eq(w1.swing_active, false, "on_swing does not restart the swing (caller's job)")
pr.start_swing(w1, 3.5)
eq(w1.swing_active, true, "start_swing starts a swing")
near(w1.swing_ends_at, 7.0, "start_swing uses effective_speed")

-- on_swing: successful twist consumes the fading (older) seal
local w2 = pr.new_sim()
pr.cast(w2, "soc", 0, out)
pr.cast(w2, "sob", 2, out)
clear_out()
pr.on_swing(w2, 2.2, out)
eq(out.result, "twist", "twist: result")
eq(out.twist_attempted, true, "twist: attempted flag reported")
eq(out.feedback, "TWIST!", "twist: feedback")
eq(out.seal_consumed, "command", "twist: older (fading) seal consumed")
eq(out.timeline_event.seal, "blood", "twist payload seal before consume (blood wins)")
eq(w2.n_active_seals, 1, "twist: one seal remains")
eq(w2.seal_1_label, "blood", "twist: newer seal stays")
eq(w2.fading_seal_label, nil, "twist: fading state cleared")
eq(w2.twist_attempted, false, "twist: attempted flag cleared on the sim")

-- on_swing: attempted twist that faded before the swing -> MISS
local w3 = pr.new_sim()
pr.cast(w3, "soc", 0, out)
pr.cast(w3, "sob", 2, out)
pr.tick(w3, 2.5, 0.016, out)
clear_out()
pr.on_swing(w3, 2.5, out)
eq(out.result, "miss", "missed twist: result miss")
eq(out.twist_attempted, true, "missed twist: attempted flag reported")
eq(out.feedback, "MISS", "missed twist: feedback MISS")
eq(out.seal_consumed, nil, "missed twist: nothing consumed")
eq(w3.twist_attempted, false, "missed twist: flag cleared")

-- on_swing: dual seals with no fading label consume seal_1
local w4 = pr.new_sim()
w4.active_seals = { command = true, blood = true }
w4.n_active_seals = 2
w4.seal_1_label = "command"
w4.seal_2_label = "blood"
pr.on_swing(w4, 0, out)
eq(out.seal_consumed, "command", "dual without fading: seal_1 consumed")
eq(w4.seal_1_label, "blood", "dual without fading: seal_2 remains")

-- pause / resume -------------------------------------------------------------------
local p1 = pr.new_sim()
pr.begin_fight(p1, 0, { bl_delay = 999 })
pr.pause_attack(p1, 1.0)
eq(p1.attack_pause_pending, true, "pause mid-swing: pending")
eq(p1.attack_paused, false, "pause mid-swing: not paused yet")
pr.pause_attack(p1, 1.1)
eq(p1.attack_pause_pending, true, "second pause while pending: no-op")
clear_out()
pr.tick(p1, 3.5, 0.016, out)
eq(out.attack_paused, true, "pending pause holds the completed swing")
eq(out.swing_ready, false, "held swing is not reported as swing_ready")
eq(p1.attack_paused, true, "pause flags set")
eq(p1.swing_held, true, "held swing flag set")
eq(p1.swing_active, false, "held swing completed")
pr.pause_attack(p1, 3.6)
eq(p1.swing_held, true, "pause while paused: no-op")
clear_out()
pr.resume_attack(p1, 4.0, out)
eq(out.resumed_attack, true, "resume: resumed_attack flag")
eq(out.held_swing, true, "resume: held_swing flag")
eq(p1.attack_paused, false, "resume clears the pause")
eq(p1.swing_held, false, "resume consumes the held flag")
eq(p1.swing_active, true, "held resume re-arms the swing")
eq(p1.swing_ends_at, 4.0, "held resume swing is immediately due")
clear_out()
pr.tick(p1, 4.0, 0.016, out)
eq(out.swing_ready, true, "held swing resolves through the normal tick path")

local p2 = pr.new_sim()
pr.begin_fight(p2, 0, { bl_delay = 999 })
pr.tick(p2, 3.5, 0.016, out)
pr.pause_attack(p2, 3.6)
eq(p2.attack_paused, true, "pause after completion: immediate")
eq(p2.swing_held, false, "immediate pause holds nothing")
clear_out()
pr.resume_attack(p2, 4.0, out)
eq(out.held_swing, false, "resume without a held swing")
eq(p2.swing_active, true, "resume starts a fresh swing")
near(p2.swing_ends_at, 7.5, "fresh resume swing uses effective_speed")
local p3 = pr.new_sim()
pr.pause_attack(p3, 0)
eq(p3.attack_paused, false, "pause outside a fight: no-op")

-- cast("stop") and cast-driven resume ----------------------------------------------
local p4 = pr.new_sim()
pr.begin_fight(p4, 0, { bl_delay = 999 })
clear_out()
pr.cast(p4, "stop", 1.0, out)
eq(out.gcd_started, false, "cast stop: no flags")
eq(out.ignored, false, "cast stop: not ignored")
eq(p4.attack_pause_pending, true, "cast stop pauses")
clear_out()
pr.tick(p4, 3.5, 0.016, out)
eq(p4.attack_paused, true, "cast stop: swing held after completion")
clear_out()
pr.cast(p4, "cs", 4.0, out)
eq(out.resumed_attack, true, "resume ability: resumed_attack flag")
eq(out.held_swing, true, "resume ability: held swing released")
eq(out.cooldown_set, true, "resume ability still fires the ability")
eq(p4.swing_ends_at, 4.0, "resume ability leaves the held swing immediately due")

local p5 = pr.new_sim()
pr.begin_fight(p5, 0, { bl_delay = 999 })
pr.pause_attack(p5, 1.0)
pr.tick(p5, 3.5, 0.016, out)
clear_out()
pr.cast(p5, "sob", 4.0, out)
eq(out.resumed_attack, true, "same-seal resume: resumed")
eq(out.twist_armed, true, "same-seal resume swaps to the opposite seal and arms a twist")
eq(p5.n_active_seals, 2, "same-seal resume: dual seals")
eq(p5.seal_1_label, "command", "same-seal resume: swapped seal is the older one")
eq(p5.seal_2_label, "blood", "same-seal resume: pressed seal is the newer one")

-- unknown / misc casts -------------------------------------------------------------
local u1 = pr.new_sim()
pr.cast(u1, "nope", 0, out)
eq(out.ignored, true, "unknown ability: ignored")
eq(u1.gcd_active, false, "unknown ability: no GCD")
pr.cast(u1, "stop", 0, out)
eq(u1.attack_paused, false, "stop outside a fight: no-op")

-- BL + swing reset interplay -------------------------------------------------------
local z1 = pr.new_sim()
pr.begin_fight(z1, 0, { bl_delay = 0 })
pr.apply_haste(z1, 3.5, 0)
eq(z1.effective_speed, 2.692, "begin_fight + apply_haste: BL speed")
pr.start_swing(z1, 0)
near(z1.swing_ends_at, 2.692, "start_swing after haste uses the hasted speed")

-- DST proc --------------------------------------------------------------------------
local d1 = pr.new_sim()
eq(pr.maybe_dst_proc(d1, 0, 0.1), true, "dst: roll under chance procs")
eq(d1.has_dst, true, "dst: active after proc")
eq(d1.dst_buff_expires, 10, "dst: 10s buff")
eq(d1.dst_icd_expires, 20, "dst: 20s ICD")
eq(pr.maybe_dst_proc(d1, 1, 0), false, "dst: no second proc while the buff is up")
local d2 = pr.new_sim()
eq(pr.maybe_dst_proc(d2, 0, 1.0), false, "dst: failed roll")
eq(d2.dst_icd_expires, 0, "dst: failed roll does not start the ICD")
eq(d2.has_dst, false, "dst: failed roll leaves the buff inactive")
local d3 = pr.new_sim()
eq(pr.maybe_dst_proc(d3, 0, 0.0), true, "dst: zero roll procs")
pr.tick(d3, 10, 0.016, out)
eq(d3.has_dst, false, "dst: buff expires on tick")
eq(pr.maybe_dst_proc(d3, 15, 0.0), false, "dst: ICD blocks a proc at 15s")
eq(pr.maybe_dst_proc(d3, 21, 0.0), true, "dst: ICD allows a proc after 20s")
local d4 = pr.new_sim()
local chance = 4.0 * d4.effective_speed / 60
eq(pr.maybe_dst_proc(d4, 0, chance), false, "dst: roll exactly at the chance does not proc")
eq(pr.maybe_dst_proc(d4, 0, chance - 0.0001), true, "dst: roll just under the chance procs")
local d5 = pr.new_sim()
d5.effective_speed = 1.8
eq(pr.maybe_dst_proc(d5, 0, 0.11), true, "dst: chance scales with effective_speed (1.8 -> 0.12)")
eq(pr.maybe_dst_proc(pr.new_sim(), 0, nil), false, "dst: nil roll never procs")

-- CLASSIFY / pattern tables ---------------------------------------------------------
eq(pr.CLASSIFY({ result = "twist", seal_active = "blood" }), "twist", "classify: twist wins")
eq(pr.CLASSIFY({ result = "miss", seal_active = "blood" }), "blood_auto", "classify: blood auto")
eq(pr.CLASSIFY({ result = "miss", seal_active = "command" }), "cmd_auto", "classify: command auto")
eq(pr.CLASSIFY({ result = "miss", seal_active = nil }), "no_seal", "classify: no seal")
local rotation_keys = { "1/2", "2/3", "2/2/5", "2/4", "1/3", "2/5_blood", "2/5_command", "2007" }
for _, key in ipairs(rotation_keys) do
    check(type(pr.CS_SEGMENT_PATTERNS[key]) == "table", "CS_SEGMENT_PATTERNS[" .. key .. "] present")
    check(type(pr.IMPLICIT_AUTO[key]) == "string", "IMPLICIT_AUTO[" .. key .. "] present")
end
eq(pr.CS_SEGMENT_PATTERNS["1/2"][1], "blood_auto", "pattern 1/2 starts with blood_auto")
eq(pr.CS_SEGMENT_PATTERNS["1/2"][2], "twist", "pattern 1/2 ends with twist")
eq(pr.CS_SEGMENT_PATTERNS["2/2/5"][1][1], "blood_auto", "pattern 2/2/5 sub 1")
eq(pr.CS_SEGMENT_PATTERNS["2/2/5"][2][3], "twist", "pattern 2/2/5 sub 2")
eq(pr.IMPLICIT_AUTO["2/5_command"], "cmd_auto", "implicit auto: cmd for 2/5_command")
eq(pr.IMPLICIT_AUTO["1/2"], "blood_auto", "implicit auto: blood otherwise")
eq(pr.IMPLICIT_AUTO["2007"], "blood_auto", "implicit auto: 2007 is blood")

-- analyze: helpers -------------------------------------------------------------------
local function expect_result(r, i, expected, actual, correct, label)
    local item = r[i]
    if not item then
        check(false, label .. " (no result)")
        return
    end
    eq(item.expected, expected, label .. " expected")
    eq(item.actual, actual, label .. " actual")
    eq(item.correct, correct, label .. " correct")
end

local band_1_2 = { { start_time = 0, rotation = "1/2" } }
local ev = {
    { lane = "melee", result = "miss", seal_active = "blood", time = 0.5 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 1.0 },
    { lane = "cs", time = 1.5 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 2.0 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 3.0 },
}
local r = pr.analyze(ev, #ev, band_1_2, 1)
expect_result(r, 1, "blood_auto", "blood_auto", true, "1/2 opener swing 1")
expect_result(r, 2, "twist", "twist", true, "1/2 opener swing 2")
eq(r[3], nil, "cs events get no grading entry")
expect_result(r, 4, "blood_auto", "blood_auto", true, "1/2 scored segment swing 1")
expect_result(r, 5, "twist", "twist", true, "1/2 scored segment swing 2")

-- opener leniency allows any order within the pattern length
local ev_order = {
    { lane = "melee", result = "twist", seal_active = "blood", time = 0.5 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 1.0 },
    { lane = "cs", time = 1.5 },
}
r = pr.analyze(ev_order, #ev_order, band_1_2, 1)
expect_result(r, 1, "twist", "twist", true, "opener leniency: twist first is fine")
expect_result(r, 2, "blood_auto", "blood_auto", true, "opener leniency: auto after a twist is fine")

-- the same order inside a scored segment is wrong
local ev_scored = {
    { lane = "cs", time = 0.1 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 0.5 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 1.0 },
}
r = pr.analyze(ev_scored, #ev_scored, band_1_2, 1)
expect_result(r, 2, "blood_auto", "twist", false, "scored segment: twist in slot 1 wrong")
expect_result(r, 3, "twist", "blood_auto", false, "scored segment: auto in slot 2 wrong")

-- opener beyond the pattern length should have been CS
local ev_long_opener = {
    { lane = "melee", result = "miss", seal_active = "blood", time = 0.5 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 1.0 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 1.5 },
}
r = pr.analyze(ev_long_opener, #ev_long_opener, band_1_2, 1)
expect_result(r, 3, "cs", "blood_auto", false, "opener beyond pattern: expected cs")

-- scored segment beyond the pattern length should have been CS
local ev_long_segment = {
    { lane = "cs", time = 0.1 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 0.5 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 1.0 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 1.5 },
}
r = pr.analyze(ev_long_segment, #ev_long_segment, band_1_2, 1)
expect_result(r, 4, "cs", "blood_auto", false, "scored segment beyond pattern: expected cs")

-- no_seal in the opener
local ev_noseal = { { lane = "melee", result = "miss", seal_active = nil, time = 0.5 } }
r = pr.analyze(ev_noseal, #ev_noseal, band_1_2, 1)
expect_result(r, 1, "blood_auto", "no_seal", false, "opener without a seal is wrong")

-- mistakes do not cascade across segments
local ev_iso = {
    { lane = "cs", time = 0.1 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 0.5 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 1.0 },
    { lane = "cs", time = 1.5 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 2.0 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 2.5 },
}
r = pr.analyze(ev_iso, #ev_iso, band_1_2, 1)
expect_result(r, 3, "twist", "blood_auto", false, "isolated segment: wrong slot 2")
expect_result(r, 5, "blood_auto", "blood_auto", true, "isolated segment: next segment ok 1")
expect_result(r, 6, "twist", "twist", true, "isolated segment: next segment ok 2")

-- 2/2/5 alternation
local band_225 = { { start_time = 0, rotation = "2/2/5" } }
local ev_225 = {
    { lane = "melee", result = "miss", seal_active = "blood", time = 0.5 },
    { lane = "cs", time = 1.0 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 1.5 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 2.0 },
    { lane = "cs", time = 2.5 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 3.0 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 3.5 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 4.0 },
    { lane = "cs", time = 4.5 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 5.0 },
}
r = pr.analyze(ev_225, #ev_225, band_225, 1)
expect_result(r, 1, "blood_auto", "blood_auto", true, "2/2/5 opener")
expect_result(r, 3, "blood_auto", "blood_auto", true, "2/2/5 sub-pattern 1 slot 1")
expect_result(r, 4, "twist", "twist", true, "2/2/5 sub-pattern 1 slot 2")
expect_result(r, 6, "blood_auto", "blood_auto", true, "2/2/5 sub-pattern 2 slot 1")
expect_result(r, 7, "blood_auto", "blood_auto", true, "2/2/5 sub-pattern 2 slot 2")
expect_result(r, 8, "twist", "twist", true, "2/2/5 sub-pattern 2 slot 3")
expect_result(r, 10, "blood_auto", "twist", false, "2/2/5 alternates back to sub-pattern 1")

-- band crossing flushes against the old rotation and reopens leniency
local bands_two = {
    { start_time = 0, rotation = "1/2" },
    { start_time = 2.0, rotation = "2/3" },
}
local ev_cross = {
    { lane = "melee", result = "miss", seal_active = "blood", time = 0.5 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 1.0 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 2.5 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 3.0 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 3.5 },
}
r = pr.analyze(ev_cross, #ev_cross, bands_two, 2)
expect_result(r, 1, "blood_auto", "blood_auto", true, "band 1 opener swing")
expect_result(r, 2, "twist", "twist", true, "band 1 opener twist")
expect_result(r, 3, "blood_auto", "blood_auto", true, "band 2 reopens as a lenient opener (2/3 allows 3)")
expect_result(r, 4, "twist", "twist", true, "band 2 opener twist 1")
expect_result(r, 5, "twist", "twist", true, "band 2 opener twist 2")

-- judging with SoC is always wrong; other judge seals produce no entry
local ev_judge = {
    { lane = "judge", seal_active = "command", time = 1.0 },
    { lane = "judge", seal_active = "blood", time = 2.0 },
    { lane = "judge", seal_active = nil, time = 3.0 },
}
r = pr.analyze(ev_judge, #ev_judge, band_1_2, 1)
expect_result(r, 1, "judge_blood", "judge_command", false, "judge_command flagged wrong")
eq(r[2], nil, "judge with blood gets no entry")
eq(r[3], nil, "judge without a seal gets no entry")

-- judge events do not break a melee segment
local ev_judge_mid = {
    { lane = "melee", result = "miss", seal_active = "blood", time = 0.5 },
    { lane = "judge", seal_active = "command", time = 0.7 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 1.0 },
    { lane = "cs", time = 1.5 },
}
r = pr.analyze(ev_judge_mid, #ev_judge_mid, band_1_2, 1)
expect_result(r, 1, "blood_auto", "blood_auto", true, "judge mid-segment: swing 1 kept")
expect_result(r, 2, "judge_blood", "judge_command", false, "judge mid-segment: judge flagged")
expect_result(r, 3, "twist", "twist", true, "judge mid-segment: swing 2 kept in the same opener")

-- unknown rotation -> every swing skipped
local band_bogus = { { start_time = 0, rotation = "bogus" } }
local ev_bogus = {
    { lane = "melee", result = "miss", seal_active = "blood", time = 0.5 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 1.0 },
}
r = pr.analyze(ev_bogus, #ev_bogus, band_bogus, 1)
eq(r[1] and r[1].skipped, true, "unknown rotation: swing 1 skipped")
eq(r[2] and r[2].skipped, true, "unknown rotation: swing 2 skipped")

-- zero bands -> empty results; count limits processing
r = pr.analyze(ev_judge, #ev_judge, {}, 0)
local n_entries = 0
for _ in pairs(r) do n_entries = n_entries + 1 end
eq(n_entries, 0, "zero bands: empty results")
local ev_count = {
    { lane = "melee", result = "miss", seal_active = "blood", time = 0.5 },
    { lane = "cs", time = 1.0 },
    { lane = "melee", result = "miss", seal_active = nil, time = 1.5 },
}
r = pr.analyze(ev_count, 2, band_1_2, 1)
expect_result(r, 1, "blood_auto", "blood_auto", true, "count limits to the first events")
eq(r[3], nil, "count excludes later events")

if failures == 0 then
    print("PASS  practice_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  practice_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
