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

-- weave.lua loads before practice.lua in every TOC (the S7 weave scenario delegates its
-- timing model to st.weave), so the sandbox mirrors that order.
local wmod = assert(loadfile(ROOT .. "weave.lua"))
setfenv(wmod, env)
local okw, errw = pcall(function() wmod("SwedgeTimer", st) end)
check(okw, "weave.lua loads under the sandbox (" .. tostring(errw) .. ")")
check(type(st.weave) == "table", "st.weave table exists")

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

-- timeline data / keybind labels / haste setters -------------------------------------

-- shorten_keybind (archive 183-225 verbatim logic)
eq(pr.shorten_keybind(nil), "", "shorten: nil -> empty")
eq(pr.shorten_keybind(""), "", "shorten: empty -> empty")
eq(pr.shorten_keybind("1"), "1", "shorten: single key passes through")
eq(pr.shorten_keybind("F12"), "F12", "shorten: F12 fits in 3 chars")
eq(pr.shorten_keybind("BUTTON4"), "M4", "shorten: mouse button 4")
eq(pr.shorten_keybind("MOUSEWHEELUP"), "MU", "shorten: wheel up")
eq(pr.shorten_keybind("MOUSEWHEELDOWN"), "MD", "shorten: wheel down")
eq(pr.shorten_keybind("CTRL-1"), "C1", "shorten: ctrl modifier prefix")
eq(pr.shorten_keybind("SHIFT-F1"), "SF1", "shorten: shift prefix + truncation to 3")
eq(pr.shorten_keybind("ALT-BUTTON5"), "AM5", "shorten: alt + mouse button, truncated")
eq(pr.shorten_keybind("NUMPAD0"), "N0", "shorten: numpad digit")
eq(pr.shorten_keybind("NUMPADPLUS"), "N+", "shorten: numpad plus mapped")
eq(pr.shorten_keybind("NUMPADMINUS"), "N-", "shorten: numpad minus mapped")
eq(pr.shorten_keybind("NUMPADMULTIPLY"), "N*", "shorten: numpad multiply mapped")
eq(pr.shorten_keybind("NUMPADDIVIDE"), "N/", "shorten: numpad divide mapped")
eq(pr.shorten_keybind("NUMPADDECIMAL"), "N.", "shorten: numpad decimal mapped")
eq(pr.shorten_keybind("NUMPADHOME"), "NHO", "shorten: unknown numpad key truncated")
eq(pr.shorten_keybind("PADLSHOULDER"), "LB", "shorten: gamepad left bumper")
eq(pr.shorten_keybind("PADDUP"), "DU", "shorten: gamepad d-pad up")
eq(pr.shorten_keybind("PADRSTICKRIGHT"), "RR", "shorten: gamepad right stick right")
eq(pr.shorten_keybind("HOME"), "HOM", "shorten: long key truncated to 3")

-- DEFAULT_KEYBINDS (archive reset defaults 3952-3956)
eq(pr.DEFAULT_KEYBINDS.soc, "1", "default keybind soc")
eq(pr.DEFAULT_KEYBINDS.sob, "2", "default keybind sob")
eq(pr.DEFAULT_KEYBINDS.cs, "3", "default keybind cs")
eq(pr.DEFAULT_KEYBINDS.judge, "4", "default keybind judge")
eq(pr.DEFAULT_KEYBINDS.sotc, "5", "default keybind sotc")
eq(pr.DEFAULT_KEYBINDS.consec, "6", "default keybind consec")
eq(pr.DEFAULT_KEYBINDS.aw, "7", "default keybind aw")
eq(pr.DEFAULT_KEYBINDS.hpot, "8", "default keybind hpot")
eq(pr.DEFAULT_KEYBINDS.abacus, "9", "default keybind abacus")
eq(pr.DEFAULT_KEYBINDS.stop, "", "default keybind stop empty")
local default_key_count = 0
for _ in pairs(pr.DEFAULT_KEYBINDS) do default_key_count = default_key_count + 1 end
eq(default_key_count, #pr.ABILITY_ORDER, "default keybinds cover every ability")

-- TIMELINE_LANES / index / seal mapping / labels
eq(#pr.TIMELINE_LANES, 6, "six timeline lanes")
eq(pr.TIMELINE_LANES[2].key, "melee", "lane 2 is melee")
eq(pr.TIMELINE_LANE_INDEX.judge, 6, "judge lane index 6")
eq(pr.TIMELINE_LANE_INDEX.cs, 3, "cs lane index 3")
eq(pr.SEAL_LABEL_TO_LANE.blood, "sob", "blood maps to the sob lane")
eq(pr.SEAL_LABEL_TO_LANE.command, "soc", "command maps to the soc lane")
eq(pr.SEAL_LABEL_TO_LANE.crusader, nil, "crusader has no lane")
check(type(pr.MELEE_TEXTURE) == "string" and pr.MELEE_TEXTURE:find("INV_Sword_04") ~= nil,
    "MELEE_TEXTURE is the sword icon")
eq(pr.SWING_ACTION_LABELS.twist, "Twist", "action label twist")
eq(pr.SWING_ACTION_LABELS.judge_command, "Judge (Seal of Command)", "action label judge_command")

-- format_fight_time (archive sim_update 3393)
eq(pr.format_fight_time(0), "Fight: 0:00", "fight clock zero")
eq(pr.format_fight_time(5.9), "Fight: 0:05", "fight clock floors seconds")
eq(pr.format_fight_time(65), "Fight: 1:05", "fight clock minutes pad seconds")
eq(pr.format_fight_time(600), "Fight: 10:00", "fight clock ten minutes")
eq(pr.format_fight_time(-3), "Fight: 0:00", "fight clock clamps negatives")
eq(pr.format_fight_time(nil), "Fight: 0:00", "fight clock nil -> zero")

-- cast_timeline_lane (archive sim_cast_seal 3087-3093 + sim_cast_ability 3165-3168)
eq(pr.cast_timeline_lane("cs"), "cs", "cast lane cs")
eq(pr.cast_timeline_lane("judge"), "judge", "cast lane judge")
eq(pr.cast_timeline_lane("consec"), "consec", "cast lane consec")
eq(pr.cast_timeline_lane("soc"), "soc", "cast lane soc via seal label")
eq(pr.cast_timeline_lane("sob"), "sob", "cast lane sob via seal label")
eq(pr.cast_timeline_lane("sotc"), nil, "cast lane sotc: crusader has no lane")
eq(pr.cast_timeline_lane("aw"), nil, "cast lane aw: buffs are not logged")
eq(pr.cast_timeline_lane("hpot"), nil, "cast lane hpot: consumables are not logged")
eq(pr.cast_timeline_lane("abacus"), nil, "cast lane abacus: trinkets are not logged")
eq(pr.cast_timeline_lane("stop"), nil, "cast lane stop: stopattack is not logged")
eq(pr.cast_timeline_lane("nope"), nil, "cast lane unknown: nothing logged")

-- push_timeline_event / timeline_max_time (archive log_timeline_event 1881-1898)
local tev = {}
local tn = 0
local fs = pr.new_sim()
tn = pr.push_timeline_event(tev, tn, fs, 10, "cs", "tex_cs")
eq(tn, 0, "push outside a fight: count unchanged")
eq(tev[1], nil, "push outside a fight: nothing stored")
pr.begin_fight(fs, 100, { bl_delay = 999 })
tn = pr.push_timeline_event(tev, tn, fs, 103.5, "cs", "tex_cs")
eq(tn, 1, "push in a fight: count advances")
eq(tev[1].time, 3.5, "push: fight-relative time")
eq(tev[1].lane, "cs", "push: lane stored")
eq(tev[1].texture, "tex_cs", "push: texture stored")
tn = pr.push_timeline_event(tev, tn, fs, 105, "melee", "tex_sw", "twist", "blood")
eq(tn, 2, "push: second event counted")
eq(tev[2].result, "twist", "push: result stored")
eq(tev[2].seal_active, "blood", "push: seal_active stored")
eq(pr.timeline_max_time(tev, tn), 5, "max time across events")
eq(pr.timeline_max_time({}, 0), 0, "max time with no events is 0")

-- bands_for_fight / track_rotation_band (archive start_fight 2866-2876 + 1557-1579)
local b0, n0 = pr.bands_for_fight(nil)
eq(n0, 0, "bands_for_fight nil rotation: no bands")
eq(#b0, 0, "bands_for_fight nil rotation: empty table")
local bd1, bn1 = pr.bands_for_fight("1/2")
eq(bn1, 1, "bands_for_fight: one opening band")
eq(bd1[1].start_time, 0, "opening band starts at 0")
eq(bd1[1].rotation, "1/2", "opening band rotation")
bn1 = pr.track_rotation_band(bd1, bn1, "1/2", 10)
eq(bn1, 1, "track: unchanged rotation appends nothing")
bn1 = pr.track_rotation_band(bd1, bn1, "2/3", 12.5)
eq(bn1, 2, "track: changed rotation appends a band")
eq(bd1[2].start_time, 12.5, "track: band starts at the change time")
eq(bd1[2].rotation, "2/3", "track: band carries the new rotation")
bn1 = pr.track_rotation_band(bd1, bn1, nil, 15)
eq(bn1, 2, "track: nil rotation appends nothing")
-- bands feed analyze() directly: a two-band fight grades per band
local band_ev = {
    { lane = "melee", result = "miss", seal_active = "blood", time = 1.0 },
    { lane = "cs", time = 2.0 },
    { lane = "melee", result = "miss", seal_active = "blood", time = 13.0 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 14.0 },
    { lane = "melee", result = "twist", seal_active = "blood", time = 15.0 },
}
local band_r = pr.analyze(band_ev, #band_ev, bd1, bn1)
expect_result(band_r, 1, "blood_auto", "blood_auto", true, "tracked bands: band 1 opener")
expect_result(band_r, 3, "blood_auto", "blood_auto", true, "tracked bands: band 2 opener slot 1")
expect_result(band_r, 5, "twist", "twist", true, "tracked bands: band 2 opener slot 3")

-- set_bloodlust / set_haste_pot (archive activate/deactivate 2592-2690 minus UI/sound)
local h1 = pr.new_sim()
eq(pr.set_bloodlust(h1, 0, true), true, "set_bloodlust on: applied")
eq(h1.has_bloodlust, true, "set_bloodlust on: flag set")
eq(h1.bl_buff_expires, 40, "set_bloodlust on: 40s duration")
eq(pr.set_bloodlust(h1, 5, true), false, "set_bloodlust on while active: no-op")
eq(h1.bl_buff_expires, 40, "set_bloodlust double activation keeps the original expiry")
eq(pr.set_bloodlust(h1, 10, false), true, "set_bloodlust off: cleared")
eq(h1.has_bloodlust, false, "set_bloodlust off: flag cleared")
eq(h1.bl_buff_expires, 0, "set_bloodlust off: expiry cleared")
local h1l = pr.new_sim()
h1l.locked_rotation = "1/2"
eq(pr.set_bloodlust(h1l, 0, true), false, "set_bloodlust while locked: refused")
eq(h1l.has_bloodlust, false, "set_bloodlust while locked: not applied")
local h2 = pr.new_sim()
eq(pr.set_haste_pot(h2, 0, true), true, "set_haste_pot on: applied")
eq(h2.haste_pot_buff_expires, 15, "set_haste_pot on: 15s duration")
eq(pr.set_haste_pot(h2, 5, true), false, "set_haste_pot on while active: no-op")
eq(h2.haste_pot_buff_expires, 15, "set_haste_pot double activation keeps the original expiry")
eq(pr.set_haste_pot(h2, 10, false), true, "set_haste_pot off: cleared")
eq(h2.has_haste_pot, false, "set_haste_pot off: flag cleared")
local h2l = pr.new_sim()
h2l.locked_rotation = "2/3"
eq(pr.set_haste_pot(h2l, 0, true), false, "set_haste_pot while locked: refused")

-- scoring: grade thresholds ------------------------------------------------------
eq(pr.GRADE_LEAD_MS_S, 100, "grade cutoff S == 100ms")
eq(pr.GRADE_LEAD_MS_A, 200, "grade cutoff A == 200ms")
eq(pr.GRADE_LEAD_MS_B, 300, "grade cutoff B == 300ms")
eq(pr.GRADE_LEAD_MS_C, 350, "grade cutoff C == 350ms")
eq(pr.GRADE_POINTS.S, 100, "S is worth 100")
eq(pr.GRADE_POINTS.A, 80, "A is worth 80")
eq(pr.GRADE_POINTS.B, 60, "B is worth 60")
eq(pr.GRADE_POINTS.C, 40, "C is worth 40")
eq(pr.GRADE_POINTS.D, 20, "D is worth 20")
eq(pr.GRADE_POINTS.F, 0, "a miss scores 0")
eq(pr.SCORE_WINDOW, 20, "the rolling window covers 20 attempts")
eq(pr.grade_twist(0), "S", "grade: zero lead is S")
eq(pr.grade_twist(100), "S", "grade: exactly 100ms is S")
eq(pr.grade_twist(101), "A", "grade: 101ms drops to A")
eq(pr.grade_twist(200), "A", "grade: exactly 200ms is A")
eq(pr.grade_twist(201), "B", "grade: 201ms drops to B")
eq(pr.grade_twist(300), "B", "grade: exactly 300ms is B")
eq(pr.grade_twist(301), "C", "grade: 301ms drops to C")
eq(pr.grade_twist(350), "C", "grade: exactly 350ms is C")
eq(pr.grade_twist(351), "D", "grade: 351ms drops to D")
eq(pr.grade_twist(399), "D", "grade: a barely-inside-window twist is D")
eq(pr.grade_twist(nil), "C", "grade: unmeasured success is the neutral C")
eq(pr.grade_twist("x"), "C", "grade: non-number lead is the neutral C")

-- on_swing: lead_ms + grade -------------------------------------------------------
local g1 = pr.new_sim()
pr.cast(g1, "soc", 0, out)
pr.cast(g1, "sob", 2, out)
clear_out()
pr.on_swing(g1, 2.2, out)
near(out.lead_ms, 200, "on_swing: 200ms swap lead is measured")
eq(out.grade, "A", "on_swing: 200ms lead grades A")
eq(out.feedback, "TWIST!", "on_swing: feedback still TWIST!")
local g1t = pr.new_sim()
pr.cast(g1t, "soc", 0, out)
pr.cast(g1t, "sob", 2, out)
clear_out()
pr.on_swing(g1t, 2.05, out)
near(out.lead_ms, 50, "on_swing: 50ms swap lead is measured")
eq(out.grade, "S", "on_swing: 50ms lead grades S")
local g1d = pr.new_sim()
pr.cast(g1d, "soc", 0, out)
pr.cast(g1d, "sob", 2, out)
clear_out()
pr.on_swing(g1d, 2.39, out)
near(out.lead_ms, 390, "on_swing: 390ms swap lead is measured")
eq(out.grade, "D", "on_swing: 390ms lead grades D")
local g2 = pr.new_sim()
pr.cast(g2, "soc", 0, out)
pr.cast(g2, "sob", 2, out)
pr.tick(g2, 2.5, 0.016, out)
clear_out()
pr.on_swing(g2, 2.5, out)
eq(out.grade, "F", "on_swing: an armed attempt past the fade grades F")
eq(out.lead_ms, nil, "on_swing: the expired fade leaves no measurable lead")
local g3 = pr.new_sim()
pr.begin_fight(g3, 0, { bl_delay = 999 })
clear_out()
pr.on_swing(g3, 3.5, out)
eq(out.grade, nil, "on_swing: no attempt means no grade")
eq(out.lead_ms, nil, "on_swing: no attempt means no lead")
local g4 = pr.new_sim()
g4.active_seals = { command = true, blood = true }
g4.n_active_seals = 2
g4.seal_1_label = "command"
g4.seal_2_label = "blood"
g4.twist_attempted = true
pr.on_swing(g4, 0, out)
eq(out.result, "twist", "on_swing: fadeless dual still twists")
eq(out.lead_ms, nil, "on_swing: fadeless dual has no measurable lead")
eq(out.grade, "C", "on_swing: fadeless dual grades the neutral C")

-- scoring: record + summary --------------------------------------------------------
local sc = pr.new_score()
eq(sc.attempts, 0, "new_score: no attempts")
eq(sc.hits, 0, "new_score: no hits")
local empty = pr.score_summary(sc)
eq(empty.score, 0, "empty summary scores 0")
eq(empty.hit_rate, 0, "empty summary hit-rate 0")
eq(empty.mean_error_ms, nil, "empty summary has no mean error")
eq(empty.best_grade, nil, "empty summary has no best grade")
pr.record_attempt(sc, nil, nil)
eq(sc.attempts, 0, "record: a nil grade records nothing")
pr.record_attempt(sc, "S", 50)
pr.record_attempt(sc, "F", nil)
eq(sc.attempts, 2, "record: two attempts counted")
eq(sc.hits, 1, "record: one hit counted")
eq(sc.total_points, 100, "record: S + F totals 100 points")
eq(sc.error_sum_ms, 50, "record: only the measured hit feeds the error sum")
eq(sc.error_count, 1, "record: the unmeasured miss feeds no error")
eq(sc.best_grade, "S", "record: best single grade tracked")
eq(sc.last_grade, "F", "record: last grade tracked")
local sum = pr.score_summary(sc)
eq(sum.score, 50, "summary: (100 + 0) / 2 rounds to 50")
near(sum.hit_rate, 0.5, "summary: 1/2 hit-rate")
near(sum.mean_points, 50, "summary: mean points 50")
near(sum.mean_error_ms, 50, "summary: mean error over measured hits only")
near(sum.rolling_hit_rate, 0.5, "summary: rolling hit-rate matches under the window")
near(sum.rolling_points, 50, "summary: rolling points match under the window")

-- scoring: rolling window eviction ---------------------------------------------------
local rw = pr.new_score()
for _ = 1, 5 do pr.record_attempt(rw, "F", nil) end
for _ = 1, 20 do pr.record_attempt(rw, "S", 100) end
eq(rw.attempts, 25, "rolling: 25 attempts recorded")
eq(#rw.recent_points, 20, "rolling: the ring caps at SCORE_WINDOW")
eq(rw.recent_hits, 20, "rolling: the five early misses aged out of the ring")
local rsum = pr.score_summary(rw)
near(rsum.hit_rate, 0.8, "rolling: overall hit-rate still sees the early misses")
near(rsum.rolling_hit_rate, 1.0, "rolling: the window hit-rate is perfect")
near(rsum.rolling_points, 100, "rolling: the window points are perfect")
eq(rsum.score, 80, "rolling: the session score still carries every attempt (2000/25)")
local rw2 = pr.new_score()
for _ = 1, 21 do pr.record_attempt(rw2, "A", 150) end
eq(#rw2.recent_points, 20, "rolling: one eviction at 21 attempts")
eq(rw2.recent_hits, 20, "rolling: evicting a hit drops the ring hit count")
local rw3 = pr.new_score()
pr.record_attempt(rw3, "F", nil)
for _ = 1, 20 do pr.record_attempt(rw3, "S", 100) end
eq(rw3.recent_hits, 20, "rolling: evicting the only miss leaves a perfect ring")

-- scoring: determinism -----------------------------------------------------------------
local da = pr.new_score()
local dbb = pr.new_score()
for _, g in ipairs({ "S", "A", "F", "B", "D", "C" }) do
    pr.record_attempt(da, g, 120)
    pr.record_attempt(dbb, g, 120)
end
local sa = pr.score_summary(da)
local sb = pr.score_summary(dbb)
eq(sa.score, sb.score, "determinism: identical sequences give identical scores")
eq(sa.mean_error_ms, sb.mean_error_ms, "determinism: identical mean errors")
eq(sa.best_grade, sb.best_grade, "determinism: identical best grades")

--=========================================================================================
-- Generic scenario harness (C1) ------------------------------------------------------------
--=========================================================================================
local H = pr.harness
check(type(H) == "table", "st.practice.harness exists")
for _, name in ipairs({
    "register_scenario", "get_scenario", "scenarios_for_class", "new_session",
    "begin_session", "tick_session", "end_session", "scenario_event", "query",
    "record_session_attempt", "session_summary", "grade_band", "build_windows",
    "window_at", "next_window", "time_to_next_window", "window_remaining",
    "overlap_seconds", "new_combo", "combo_open", "combo_record", "combo_missing",
    "combo_evaluate", "combo_window_remaining", "grade_move_cast",
    "execute_phase_update", "grade_execute_entry", "new_energy_state", "energy_update",
    "energy_spend", "grade_powershift", "powershift_cycle", "weave_marker_fraction",
    "weave_safe_start_in", "grade_weave_cast", "energy_tick_marker",
    "grade_energy_spend", "grade_ss_after_swing",
}) do
    check(type(H[name]) == "function", "harness exposes " .. name)
end

-- harness: registry ---------------------------------------------------------------
eq(#H.SCENARIO_ORDER, 8, "eight scenarios are registered")
local specs = H.scenarios_for_class(nil)
eq(#specs, 8, "scenarios_for_class(nil) returns every scenario")
eq(specs[1].key, "paladin_twist", "the paladin twist sim is consumer #1")
local paladin_specs = H.scenarios_for_class("PALADIN")
eq(#paladin_specs, 2, "two paladin scenarios")
eq(paladin_specs[1].key, "paladin_twist", "paladin order: twist first")
eq(paladin_specs[2].key, "paladin_aw_combo", "paladin order: AW combo second")
eq(#H.scenarios_for_class("HUNTER"), 1, "one hunter shell")
eq(H.scenarios_for_class("HUNTER")[1].key, "hunter_forced_move", "the hunter shell is H5")
eq(H.get_scenario("warrior_execute").kind, "execute_phase", "W6 spec kind")
eq(H.get_scenario("druid_powershift").kind, "energy_loop", "D7 spec kind")
eq(H.get_scenario("shaman_weave").kind, "weave_timing", "S7 spec kind")
eq(H.get_scenario("paladin_aw_combo").kind, "combo_windows", "P5 spec kind")
eq(H.get_scenario("paladin_twist").kind, "paladin_twist", "the paladin spec kind")
local rogue_specs = H.scenarios_for_class("ROGUE")
eq(#rogue_specs, 2, "two rogue scenarios")
eq(rogue_specs[1].key, "rogue_energy_pool", "rogue order: energy pool first")
eq(rogue_specs[2].key, "rogue_ss_window", "rogue order: SS window second")
eq(H.get_scenario("rogue_energy_pool").kind, "energy_loop", "rogue energy spec kind")
eq(H.get_scenario("rogue_ss_window").kind, "swing_window", "rogue SS spec kind")
eq(H.get_scenario("nope"), nil, "unknown scenario reads nil")
local dup, dup_err = H.register_scenario({ key = "paladin_twist", title = "dup" })
eq(dup, nil, "duplicate registration is rejected")
check(type(dup_err) == "string", "duplicate registration reports an error")
eq(H.register_scenario({ title = "no key" }), nil, "a keyless spec is rejected")
eq(H.register_scenario({ key = "x", title = "bad kind", kind = "bogus" }), nil,
    "an unknown kind is rejected")
eq(#H.SCENARIO_ORDER, 8, "rejected registrations do not enter the registry")

-- harness: windows -------------------------------------------------------------------
local win = H.build_windows({ count = 3, first_start = 10, duration = 2.5, gap = 5.5, label = "move" })
eq(#win, 3, "build_windows count")
eq(win[1].start_time, 10, "window 1 start")
eq(win[1].end_time, 12.5, "window 1 end")
eq(win[2].start_time, 18, "window 2 start follows the duration+gap cadence")
eq(win[3].start_time, 26, "window 3 start")
eq(win[1].label, "move", "window label")
eq(win[1].index, 1, "window index")
local win_b = H.build_windows({ count = 3, first_start = 10, duration = 2.5, gap = 5.5, label = "move" })
eq(win_b[3].start_time, win[3].start_time, "build_windows is deterministic")
eq(H.window_at(win, 9.99), nil, "window_at before the first window")
check(H.window_at(win, 10) ~= nil, "window_at includes the start edge")
eq(H.window_at(win, 12.5), nil, "window_at excludes the end edge")
eq(H.window_at(win, 11).index, 1, "window_at inside")
eq(H.window_at(win, nil), nil, "window_at with a non-number")
eq(H.window_at({}, 10), nil, "window_at with no windows")
eq(H.next_window(win, 5).start_time, 10, "next_window before the first")
eq(H.next_window(win, 10).start_time, 10, "next_window keeps the active window")
eq(H.next_window(win, 12.4).start_time, 10, "next_window keeps it until its end edge")
eq(H.next_window(win, 12.5).start_time, 18, "next_window moves on at the end edge")
eq(H.next_window(win, 26.1).start_time, 26, "next_window keeps the last window until its end")
eq(H.next_window(win, 28.6), nil, "next_window after the last")
eq(H.time_to_next_window(win, 5), 5, "time_to_next_window before")
eq(H.time_to_next_window(win, 11), 0, "time_to_next_window inside reads 0")
eq(H.time_to_next_window(win, 28.6), nil, "time_to_next_window after the last is nil")
eq(H.window_remaining(win, 11), 1.5, "window_remaining inside")
eq(H.window_remaining(win, 13), nil, "window_remaining between windows")
near(H.overlap_seconds(win, 0, 30), 7.5, "overlap_seconds counts the full windows")
near(H.overlap_seconds(win, 11, 19), 2.5, "overlap_seconds clamps to the span (1.5 + 1.0)")
eq(H.overlap_seconds(win, 13, 18), 0, "overlap_seconds with no overlap")
eq(H.overlap_seconds(win, 5, 5), 0, "overlap_seconds with an empty span")
near(H.overlap_seconds({ { start_time = 0, end_time = 5 }, { start_time = 3, end_time = 8 } }, 0, 10), 8,
    "overlap_seconds merges overlapping windows")

-- harness: session lifecycle ---------------------------------------------------------
local missing_session, session_err = H.new_session("nope", 0)
eq(missing_session, nil, "new_session rejects an unknown key")
check(type(session_err) == "string", "new_session reports the unknown key")
local sess = H.new_session("hunter_forced_move", 100)
eq(sess.active, false, "a new session is inactive")
eq(sess.started_at, 100, "a new session records its start time")
eq(sess.score.attempts, 0, "a new session owns an empty score")
eq(#sess.windows, 0, "windows are built at begin")
eq(H.begin_session(sess, 100), true, "begin_session activates")
eq(sess.active, true, "the session is active after begin")
eq(#sess.windows, 5, "the H5 session builds its default windows")
eq(sess.windows[1].start_time, 105, "the first forced-move window starts 5 s in")
eq(H.begin_session(sess, 101), false, "a second begin is a no-op")
local sout = {}
H.tick_session(sess, 104.9, 0.05, sout)
eq(sout.move_started, false, "no move window before the first start")
H.tick_session(sess, 105.1, 0.05, sout)
eq(sout.move_started, true, "crossing the first window start fires move_started")
H.tick_session(sess, 105.2, 0.05, sout)
eq(sout.move_started, false, "move_started does not repeat")
H.tick_session(sess, 107.6, 0.05, sout)
eq(sout.move_ended, true, "crossing the window end fires move_ended")
eq(H.end_session(sess, 108), true, "end_session ends it")
eq(sess.active, false, "the session is inactive after end")
eq(H.end_session(sess, 109), false, "a second end is a no-op")
sout.move_started = "stale"
H.tick_session(sess, 120, 0.05, sout)
eq(sout.move_started, "stale", "an inactive session's tick does not run")
local custom = H.new_session("hunter_forced_move", 0)
H.begin_session(custom, 0, { windows = { { start_time = 1, end_time = 2, label = "x" } } })
eq(#custom.windows, 1, "opts.windows overrides the spec windows")

-- harness: queries + events ----------------------------------------------------------
local esess = H.new_session("hunter_forced_move", 0)
eq(H.scenario_event(esess, "x", 1), nil, "events do not fire before begin")
H.begin_session(esess, 0)
eq(H.scenario_event(esess, "x", 1), nil, "an unknown H5 action grades nothing")
local qv, qerr = H.query(esess, "nope", 0)
eq(qv, nil, "unknown query reads nil")
check(type(qerr) == "string", "unknown query reports an error")
eq(H.query(esess, "in_move_window", 4.9), false, "H5 query before the window")
eq(H.query(esess, "in_move_window", 5.5), true, "H5 query inside the window")
eq(H.query(esess, "time_to_move", 4), 1, "H5 time_to_move before the window")
eq(H.query(esess, "time_to_move", 6), 0, "H5 time_to_move inside reads 0")
near(H.query(esess, "window_remaining", 6), 1.5, "H5 window_remaining inside")
-- H5: the exact-time cast path grades through the session windows
eq(H.scenario_event(esess, 3, 3), "S", "H5 event: a cast clear of the window is S")
eq(H.scenario_event(esess, 5.5, 5.5), "F", "H5 event: a cast inside the window is F")
eq(H.scenario_event(esess, { start = 12.6, cast_time = 0.5 }, 12.6), "C",
    "H5 event: a table key grades the cast running into the next window")
eq(H.scenario_event(esess, nil, 1), nil, "H5 event: a missing key grades nothing")
-- H5: re-begin clears the transient window flags without rebuilding the windows
esess.state.in_window = true
esess.state.current_index = 3
H.end_session(esess, 10)
H.begin_session(esess, 20)
eq(esess.state.in_window, false, "H5 re-begin clears the window flag")
eq(esess.state.current_index, nil, "H5 re-begin clears the window index")
eq(#esess.windows, 5, "H5 re-begin rebuilds the windows on the new clock")
H.end_session(esess, 30)

-- harness: scoring pipeline ----------------------------------------------------------
local ss = H.new_session("hunter_forced_move", 0)
H.begin_session(ss, 0)
H.record_session_attempt(ss, "S", 100)
H.record_session_attempt(ss, "F", nil)
local ssum = H.session_summary(ss)
eq(ssum.attempts, 2, "session summary counts attempts")
eq(ssum.hits, 1, "session summary counts hits")
eq(ssum.score, 50, "session score = (100 + 0) / 2")
eq(H.session_summary(nil), nil, "a nil session has no summary")
eq(H.record_session_attempt(nil, "S", 1), nil, "a nil session records nothing")
local hsc = H.new_score()
H.record_attempt(hsc, "A", 150)
eq(H.score_summary(hsc).score, 80, "the harness pipeline behaves like the engine's")

-- harness: grade_band ----------------------------------------------------------------
local bands = { { max = 1, grade = "S" }, { max = 2, grade = "A" }, { grade = "F" } }
eq(H.grade_band(0.5, bands), "S", "grade_band first band")
eq(H.grade_band(1, bands), "S", "grade_band includes the max edge")
eq(H.grade_band(1.5, bands), "A", "grade_band second band")
eq(H.grade_band(99, bands), "F", "grade_band fallback")
eq(H.grade_band(nil, bands), "F", "grade_band non-number reads the fallback")
eq(H.grade_band(0.5, nil), nil, "grade_band without bands is nil")
eq(H.grade_band(nil, { { max = 1, grade = "S" } }), nil, "grade_band without a fallback stays nil")

-- P5: combo windows ------------------------------------------------------------------
local combo = H.new_combo()
eq(combo.opener, "aw", "combo default opener is AW")
eq(combo.pieces[1], "hpot", "combo default piece is the haste pot")
eq(combo.window, 3, "combo default window is 3 s")
eq(combo.open, false, "a new combo is closed")
eq(H.combo_open(combo, 0, "hpot"), false, "a non-opener does not open the window")
eq(H.combo_open(combo, 10, "aw"), true, "AW opens the window")
eq(H.combo_open(combo, 10.5, "aw"), false, "a second AW does not reopen")
eq(H.combo_record(combo, 10.5, "cs"), false, "a non-piece is not recorded")
eq(H.combo_record(combo, 10.5, "hpot"), true, "the piece records inside the window")
eq(H.combo_record(combo, 10.6, "hpot"), false, "a duplicate piece is rejected")
eq(H.combo_window_remaining(combo, 11), 2, "combo window_remaining counts down")
local cdetail = H.combo_evaluate(combo)
eq(cdetail.complete, true, "the combo is complete")
eq(cdetail.grade, "A", "a 0.5 s lag grades A")
near(cdetail.lag, 0.5, "the lag is the slowest piece")
local incomplete = H.new_combo({ pieces = { "hpot", "abacus" } })
H.combo_open(incomplete, 0, "aw")
H.combo_record(incomplete, 0.1, "hpot")
local idetail = H.combo_evaluate(incomplete)
eq(idetail.complete, false, "a missing piece leaves the combo incomplete")
eq(idetail.grade, "F", "an incomplete combo grades F")
eq(idetail.missing[1], "abacus", "the missing piece is reported")
eq(H.combo_evaluate(H.new_combo()), nil, "a closed combo evaluates to nil")
local function combo_grade_for(lag)
    local c = H.new_combo()
    H.combo_open(c, 0, "aw")
    H.combo_record(c, lag, "hpot")
    return H.combo_evaluate(c).grade
end
eq(combo_grade_for(0.2), "S", "combo lag 0.2 is S")
eq(combo_grade_for(0.21), "A", "combo lag 0.21 is A")
eq(combo_grade_for(0.5), "A", "combo lag 0.5 is A")
eq(combo_grade_for(1.0), "B", "combo lag 1.0 is B")
eq(combo_grade_for(2.0), "C", "combo lag 2.0 is C")
eq(combo_grade_for(2.9), "D", "combo lag 2.9 is D")
eq(combo_grade_for(3.0), "D", "combo lag at the window edge is D")
eq(combo_grade_for(3.1), "F", "a piece past the window never records (incomplete)")

-- a later opener starts a fresh window once the previous one expired
local cyc = H.new_combo()
H.combo_open(cyc, 0, "aw")
H.combo_record(cyc, 0.1, "hpot")
eq(H.combo_open(cyc, 2, "aw"), false, "an opener inside the running window does not restart it")
eq(H.combo_open(cyc, 4, "aw"), true, "an opener after the window expired starts a fresh cycle")
eq(H.combo_missing(cyc)[1], "hpot", "the fresh cycle starts with no pieces")
eq(H.combo_evaluate(cyc).complete, false, "the fresh cycle is incomplete until the piece lands")

-- P5: the AW combo scenario through the harness --------------------------------------
local asess = H.new_session("paladin_aw_combo", 0)
H.begin_session(asess, 0, { bl_delay = 999 })
eq(asess.state.sim.fight_active, true, "the combo scenario begins its sim fight")
eq(H.scenario_event(asess, "aw", 10), "opened", "AW opens the combo window at its cast time")
eq(H.scenario_event(asess, "hpot", 10.3), "recorded", "the pot records at its cast time")
local aq = H.query(asess, "combo_grade", 10.4)
eq(aq.grade, "A", "the 0.3 s combo grades A")
eq(aq.complete, true, "the combo is complete")
eq(H.scenario_event(asess, "hpot", 10.5), nil, "a duplicate piece event is rejected")
near(H.query(asess, "combo_window_remaining", 10.5), 2.5, "the combo query counts the window down")
eq(H.query(asess, "combo_missing", 10.5)[1], nil, "no pieces are missing")
-- sim-driven path: the tick observes the AW/haste buff transitions
local asess2 = H.new_session("paladin_aw_combo", 0)
H.begin_session(asess2, 0, { bl_delay = 999 })
pr.cast(asess2.state.sim, "aw", 5, out)
local aout = {}
H.tick_session(asess2, 5.1, 0.05, aout)
eq(aout.combo_opened, true, "the tick observes AW and opens the window")
pr.cast(asess2.state.sim, "hpot", 5.2, out)
H.tick_session(asess2, 5.25, 0.05, aout)
eq(aout.combo_recorded, "hpot", "the tick observes the pot and records the piece")
local aq2 = H.query(asess2, "combo_grade", 5.4)
eq(aq2.complete, true, "the sim-driven combo completes")
eq(aq2.grade, "S", "a 0.15 s observed lag grades S")
H.end_session(asess2, 6)
eq(asess2.state.sim.fight_active, false, "finish ends the sim fight")

-- H5: cast legality around the forced-move windows -----------------------------------
local mwin = H.build_windows({ count = 2, first_start = 5, duration = 2, gap = 8 })
eq(H.grade_move_cast(mwin, 6, 0), "F", "a cast inside the window is F")
eq(H.grade_move_cast(mwin, 14.5, 0.5), "C", "a cast running into the next window is C")
eq(H.grade_move_cast(mwin, 14, 0.5), "B", "finishing 0.5 s before the window is B")
eq(H.grade_move_cast(mwin, 13, 0.5), "A", "finishing 1.5 s before the window is A")
eq(H.grade_move_cast(mwin, 10, 0.5), "S", "finishing with room is S")
eq(H.grade_move_cast(mwin, 20, 0.5), "S", "a cast after the last window is S")
eq(H.grade_move_cast(mwin, nil, 0), nil, "a missing cast time grades nothing")

-- W6: execute-phase tracker + entry grading ------------------------------------------
local ex = H.new_session("warrior_execute", 0)
eq(H.begin_session(ex, 0), true, "the execute session begins")
eq(H.execute_phase_update(ex.state, 1, 0.5), nil, "above the threshold: no crossing")
eq(H.execute_phase_update(ex.state, 2, 0.20), "entered", "crossing the threshold enters the phase")
eq(H.execute_phase_update(ex.state, 3, 0.10), nil, "staying inside fires nothing")
eq(ex.state.entries, 1, "the entry is counted")
eq(H.query(ex, "in_execute_phase", 3), true, "the query reports the phase")
near(H.query(ex, "phase_time", 3.5), 1.5, "the query reports the time in phase")
eq(H.execute_phase_update(ex.state, 4, 0.35), "exited", "re-crossing exits the phase")
eq(H.query(ex, "phase_time", 4), nil, "no phase time outside the phase")
eq(H.execute_phase_update(ex.state, 5, "x"), nil, "an unknown HP reading changes nothing")
eq(ex.state.phase_active, false, "the unknown reading leaves the phase state")
eq(H.grade_execute_entry(ex.state, 100), "S", "full rage at entry is S")
eq(H.grade_execute_entry(ex.state, 80), "A", "80% rage is A")
eq(H.grade_execute_entry(ex.state, 50), "B", "half rage is B")
eq(H.grade_execute_entry(ex.state, 30), "C", "30% rage is C")
eq(H.grade_execute_entry(ex.state, 10), "D", "10% rage is D")
eq(H.grade_execute_entry(ex.state, 0), "F", "empty rage is F")
eq(H.grade_execute_entry(ex.state, nil), nil, "a missing rage reading grades nothing")
eq(H.grade_execute_entry(ex.state, 120), "S", "over-target rage clamps to S")
local ex2 = H.new_session("warrior_execute", 0)
H.begin_session(ex2, 0)
local eout = {}
ex2.state.hp_fraction = 0.1
H.tick_session(ex2, 1, 0.05, eout)
eq(eout.execute_phase_entered, true, "the tick carries the entry flag")
H.tick_session(ex2, 1.1, 0.05, eout)
eq(eout.execute_phase_entered, false, "the entry flag does not repeat")
ex2.state.hp_fraction = 0.5
H.tick_session(ex2, 1.2, 0.05, eout)
eq(eout.execute_phase_exited, true, "the tick carries the exit flag")
-- W6: the exact-time HP path feeds the tracker synchronously
do
local ex3 = H.new_session("warrior_execute", 0)
H.begin_session(ex3, 0)
eq(H.scenario_event(ex3, 0.5, 1), nil, "W6 event: above the threshold reports no crossing")
eq(H.scenario_event(ex3, 0.20, 2), "entered", "W6 event: crossing the threshold enters")
eq(ex3.state.hp_fraction, 0.20, "W6 event: the reading is stored for the tick")
local eout3 = {}
H.tick_session(ex3, 2.1, 0.05, eout3)
eq(eout3.execute_phase_entered, false, "W6 event: the entry does not re-fire on the tick")
eq(H.scenario_event(ex3, "x", 3), nil, "W6 event: a non-number reading grades nothing")
eq(H.scenario_event(ex3, 0.5, 4), "exited", "W6 event: re-crossing exits")
-- W6: the graded unit is the entry - grade the pooled rage, record, summarise
local ex4 = H.new_session("warrior_execute", 0)
H.begin_session(ex4, 0)
eq(H.scenario_event(ex4, 0.15, 1), "entered", "W6 scoring: the entry crossing")
H.record_session_attempt(ex4, H.grade_execute_entry(ex4.state, 90), nil)
local exsum = H.session_summary(ex4)
eq(exsum.attempts, 1, "W6 scoring: one entry recorded")
eq(exsum.hits, 1, "W6 scoring: the pooled entry is a hit")
eq(exsum.score, 80, "W6 scoring: 90% rage grades A for 80 points")
-- W6: re-begin clears the phase without touching the configured threshold
H.end_session(ex4, 2)
H.begin_session(ex4, 10)
eq(ex4.state.phase_active, false, "W6 re-begin clears the phase")
eq(ex4.state.entries, 0, "W6 re-begin clears the entry count")
eq(ex4.state.hp_fraction, nil, "W6 re-begin clears the last reading")
eq(ex4.state.threshold, 0.20, "W6 re-begin keeps the configured threshold")
end

-- D7: powershift loop (fixed sim model; the D1 talent probe stays blocked) -----------
eq(H.POWERSHIFT_DEFAULTS.rule_energy, 20, "the 20-energy rule is the model rule")
eq(H.POWERSHIFT_DEFAULTS.shift_refund, 40, "the refund is a fixed sim constant")
local en = H.new_energy_state()
eq(en.energy, 0, "a fresh energy pool starts empty")
eq(en.energy_max, 100, "the pool caps at 100")
eq(H.energy_update(en, 0), 0, "the first update only sets the clock baseline")
eq(H.energy_update(en, 2), 20, "2 s of regen at 10/s reaches 20")
eq(H.energy_update(en, 20), 100, "regen caps at the pool size")
eq(H.energy_spend(en, 20, 30), 70, "spending floors at the pool value")
eq(H.energy_spend(en, 20, 999), 0, "overspending floors at 0")
eq(H.grade_powershift(en), "S", "shifting at 0 energy is S")
en.energy = 20
eq(H.grade_powershift(en), "S", "shifting at exactly the 20-energy rule is S")
en.energy = 21
eq(H.grade_powershift(en), "A", "21 energy drops to A")
en.energy = 40
eq(H.grade_powershift(en), "B", "40 energy is B")
en.energy = 60
eq(H.grade_powershift(en), "C", "60 energy is C")
en.energy = 80
eq(H.grade_powershift(en), "D", "80 energy is D")
en.energy = 81
eq(H.grade_powershift(en), "F", "above 80 energy is F")
local pgrade, pafter = H.powershift_cycle(en, 20)
eq(pgrade, "F", "the cycle grades the energy at the shift")
eq(pafter, 100, "the fixed refund lands (capped at the pool)")
eq(en.shifts, 1, "the shift is counted")
local low = H.new_energy_state({ energy = 10 })
local lgrade, lafter = H.powershift_cycle(low, 0)
eq(lgrade, "S", "a low-energy shift grades S")
eq(lafter, 50, "the refund adds to the pool")
local ds = H.new_session("druid_powershift", 0)
H.begin_session(ds, 0)
local dout = {}
H.tick_session(ds, 0, 0.05, dout)
eq(dout.energy, 0, "the first scenario tick establishes the baseline")
H.tick_session(ds, 3, 0.05, dout)
eq(dout.energy, 30, "the scenario tick advances the pool")
eq(H.query(ds, "grade_next_shift", 3), "A", "the query grades the current energy")
-- D7: the exact-time shift path grades, refunds and counts through the session
do
local ds2 = H.new_session("druid_powershift", 0)
H.begin_session(ds2, 0)
H.tick_session(ds2, 0, 0.05, {})
H.tick_session(ds2, 1, 0.05, {})
eq(H.scenario_event(ds2, "shift", 1), "S", "D7 event: shifting at 10 energy grades S")
eq(ds2.state.energy, 50, "D7 event: the fixed refund lands in the pool")
eq(ds2.state.shifts, 1, "D7 event: the shift is counted")
eq(H.scenario_event(ds2, "dance", 1), nil, "D7 event: a non-shift action is ignored")
local first_shift = H.scenario_event(ds2, "shift", 2)
eq(first_shift, "C", "D7 event: shifting at 60 energy grades C")
H.record_session_attempt(ds2, first_shift, nil)
local dssum = H.session_summary(ds2)
eq(dssum.attempts, 1, "D7 scoring: one shift recorded")
eq(dssum.score, 40, "D7 scoring: the C shift scores 40")
-- D7: re-begin re-baselines the clock without draining the pool
H.end_session(ds2, 2)
local kept = ds2.state.energy
H.begin_session(ds2, 100)
eq(ds2.state.energy, kept, "D7 re-begin keeps the pooled energy")
local reout = {}
H.tick_session(ds2, 100, 0.05, reout)
eq(reout.energy, kept, "D7 re-begin grants no phantom regen across the gap")
end

-- S7: weave-timing (weave.lua math) --------------------------------------------------
local we = H.new_session("shaman_weave", 0)
H.begin_session(we, 0)
local marker = H.query(we, "marker_fraction", 0)
near(marker, (2.6 - 1.6) / 2.6, "the marker comes from weave.lua's model")
near(H.weave_marker_fraction(2.6, 1.5, 0.1), (2.6 - 1.6) / 2.6, "the marker helper delegates")
near(H.weave_safe_start_in(we.state, 5, 10), 3.4, "safe_start_in delegates to weave.lua")
local wstate = { swing_duration = 2.6, effective_cast = 1.5, latency = 0.1 }
local wgrade, wmarker = H.grade_weave_cast(wstate, 0.38, 0)
near(wmarker, marker, "the grade helper reports the marker")
eq(wgrade, "S", "a start 0.005 before the marker is S")
eq(H.grade_weave_cast(wstate, 0.36, 0), "A", "a start 0.025 before the marker is A")
eq(H.grade_weave_cast(wstate, 0.30, 0), "B", "a start 0.085 before the marker is B")
eq(H.grade_weave_cast(wstate, 0.20, 0), "C", "a start 0.185 before the marker is C")
eq(H.grade_weave_cast(wstate, 0.0, 0), "D", "a very early start is D")
eq(H.grade_weave_cast(wstate, 0.5, 0), "F", "a start past the marker clips and is F")
eq(H.grade_weave_cast(wstate, 0.2, 0.4), "F", "a measured clip is F")
eq(H.grade_weave_cast(wstate, nil, 0), nil, "an unmeasured start grades nothing")
-- S7: the exact-time cast path grades through the session state
do
local we2 = H.new_session("shaman_weave", 0)
H.begin_session(we2, 0)
eq(H.scenario_event(we2, 0.38, 0), "S", "S7 event: a number key grades the swing fraction")
eq(H.scenario_event(we2, { start = 0.5 }, 0), "F", "S7 event: a table key past the marker clips")
eq(H.scenario_event(we2, { start = 0.30, clip = 0.4 }, 0), "F", "S7 event: a measured clip is F")
eq(H.scenario_event(we2, "x", 0), nil, "S7 event: a non-cast action grades nothing")
eq(H.scenario_event(we2, { start = "x" }, 0), nil, "S7 event: a table without a start grades nothing")
local wgrade_ev = H.scenario_event(we2, 0.36, 0)
H.record_session_attempt(we2, wgrade_ev, nil)
local wsum = H.session_summary(we2)
eq(wsum.attempts, 1, "S7 scoring: one cast recorded")
eq(wsum.score, 80, "S7 scoring: the A cast scores 80")
end

-- Rogue drills (Round 2, Slice D) ------------------------------------------------------
-- Energy pooling: the marker is one latency before the 2 s tick (0.95 with the
-- defaults) and the shared weave margin bands grade the distance to it. A start at or
-- past the marker is a tick clip (F); an unknown tick grades nil (never a guess).
do
local rog = H.new_session("rogue_energy_pool", 0)
H.begin_session(rog, 0)
near(H.query(rog, "tick_marker", 0), 0.95, "the tick marker sits one latency before the tick")
local rmarker, rgrade
rgrade, rmarker = H.grade_energy_spend(rog.state, 0.94, 0)
near(rmarker, 0.95, "the energy grade helper reports the marker")
eq(rgrade, "S", "energy: a start 0.01 before the marker is S")
eq(H.grade_energy_spend(rog.state, 0.91, 0), "A", "energy: 0.04 before the marker is A")
eq(H.grade_energy_spend(rog.state, 0.86, 0), "B", "energy: 0.09 before the marker is B")
eq(H.grade_energy_spend(rog.state, 0.76, 0), "C", "energy: 0.19 before the marker is C")
eq(H.grade_energy_spend(rog.state, 0.70, 0), "D", "energy: a very early spend is D")
eq(H.grade_energy_spend(rog.state, 0.96, 0), "F", "energy: a start past the marker caps the tick and is F")
eq(H.grade_energy_spend(rog.state, 0.90, 0.05), "F", "energy: a measured tick clip is F")
eq(H.grade_energy_spend(rog.state, nil, 0), nil, "energy: an unmeasured start grades nothing")
eq(H.energy_tick_marker({ tick_known = false }), nil, "an unknown tick has no marker")
eq(H.energy_tick_marker({ tick_interval = 0 }), nil, "a broken tick interval has no marker")
eq(H.scenario_event(rog, 0.94, 0), "S", "energy event: a number key grades the tick fraction")
eq(H.scenario_event(rog, { start = 0.96 }, 0), "F", "energy event: a table key past the marker clips")
eq(H.scenario_event(rog, { start = 0.90, clip = 0.4 }, 0), "F", "energy event: a measured clip is F")
eq(H.scenario_event(rog, "x", 0), nil, "energy event: a non-spend action grades nothing")
eq(H.scenario_event(rog, { start = "x" }, 0), nil, "energy event: a table without a start grades nothing")
local rsum_grade = H.scenario_event(rog, 0.94, 0)
H.record_session_attempt(rog, rsum_grade, nil)
local rogue_sum = H.session_summary(rog)
eq(rogue_sum.attempts, 1, "energy scoring: one spend recorded")
eq(rogue_sum.score, 100, "energy scoring: the S spend scores 100")
local rnone = H.new_session("rogue_energy_pool", 0, { tick_known = false })
H.begin_session(rnone, 0)
eq(H.query(rnone, "tick_marker", 0), nil, "an unknown tick query reads nil")
eq(H.scenario_event(rnone, 0.94, 0), nil, "an unknown tick is unscored, never a guessed tick")
end

-- Era SS-after-swing: 0.1 s after the mainhand swing is ideal, 0.2 s is average; the
-- window edge is the F mirror on both sides, and an unknown swing grades nil.
do
local ss_drill = H.new_session("rogue_ss_window", 0)
H.begin_session(ss_drill, 0)
local sswin = H.query(ss_drill, "window", 0)
near(sswin.start_time, 0.1, "SS window starts 0.1 s after the swing")
near(sswin.end_time, 0.2, "SS window ends 0.2 s after the swing")
near(sswin.ideal, 0.1, "the perfect SS offset is 0.1 s")
local sstate = ss_drill.state
eq(H.grade_ss_after_swing(sstate, 0.11), "S", "SS: 0.11 s is S")
eq(H.grade_ss_after_swing(sstate, 0.13), "A", "SS: 0.13 s is A")
eq(H.grade_ss_after_swing(sstate, 0.15), "B", "SS: 0.15 s is B")
eq(H.grade_ss_after_swing(sstate, 0.17), "C", "SS: 0.17 s is C")
eq(H.grade_ss_after_swing(sstate, 0.19), "D", "SS: 0.19 s is D")
eq(H.grade_ss_after_swing(sstate, 0.09), "F", "SS: an early cast (before 0.1 s) is F")
eq(H.grade_ss_after_swing(sstate, 0.21), "F", "SS: a late cast (after 0.2 s) is F")
eq(H.grade_ss_after_swing(sstate, nil), nil, "SS: an unmeasured offset grades nothing")
eq(H.grade_ss_after_swing({ swing_known = false }, 0.15), nil, "SS: an unknown swing grades nothing")
eq(H.scenario_event(ss_drill, 0.15, 0), "B", "SS event: a number key grades the offset")
eq(H.scenario_event(ss_drill, 0.25, 0), "F", "SS event: a missed window is F")
eq(H.scenario_event(ss_drill, "x", 0), nil, "SS event: a non-number key grades nothing")
local ssnone = H.new_session("rogue_ss_window", 0, { swing_known = false })
H.begin_session(ssnone, 0)
eq(H.scenario_event(ssnone, 0.15, 0), nil, "an unknown mainhand swing is unscored")
end

-- consumer #1: the harness-driven paladin session matches the direct engine path -----
local SIM_FIELDS = {
    "n_active_seals", "seal_1_label", "seal_2_label", "fading_seal_label",
    "fading_seal_expires", "effective_speed", "effective_gcd", "has_bloodlust",
    "bl_buff_expires", "has_haste_pot", "haste_pot_buff_expires", "has_abacus",
    "abacus_buff_expires", "abacus_cooldown_expires", "has_dst", "dst_buff_expires",
    "dst_icd_expires", "cs_cooldown_expires", "judge_cooldown_expires",
    "consec_cooldown_expires", "aw_cooldown_expires", "aw_buff_expires", "fight_active",
    "fight_start_time", "fight_bl_delay", "fight_bl_fired", "attack_paused",
    "attack_pause_pending", "swing_held", "twist_attempted", "queued_ability",
    "queue_timestamp", "swing_active", "swing_ends_at", "gcd_active", "gcd_expires",
    "queue_window", "locked_rotation",
}
local function sim_matches(a, b, label)
    for i = 1, #SIM_FIELDS do
        local field = SIM_FIELDS[i]
        eq(a[field], b[field], label .. ": " .. field)
    end
    eq(a.active_seals.blood, b.active_seals.blood, label .. ": active_seals.blood")
    eq(a.active_seals.command, b.active_seals.command, label .. ": active_seals.command")
end
local direct = pr.new_sim()
local psess = H.new_session("paladin_twist", 0)
H.begin_session(psess, 0, { bl_delay = 2 })
pr.begin_fight(direct, 0, { bl_delay = 2 })
pr.apply_haste(direct, 3.5, 0)
pr.apply_haste(psess.state, 3.5, 0)
sim_matches(direct, psess.state, "harness equivalence after begin")
local d_out, s_out = {}, {}
pr.cast(direct, "soc", 0.5, d_out)
pr.cast(psess.state, "soc", 0.5, s_out)
eq(d_out.gcd_started, s_out.gcd_started, "cast flags match: gcd_started")
eq(d_out.seal_changed, s_out.seal_changed, "cast flags match: seal_changed")
eq(d_out.twist_armed, s_out.twist_armed, "cast flags match: twist_armed (the first soc swap)")
pr.tick(direct, 1.0, 0.05, d_out)
H.tick_session(psess, 1.0, 0.05, s_out)
eq(d_out.seal_faded, s_out.seal_faded, "tick flags match: seal_faded")
eq(d_out.seal_faded, true, "the fade window expires on both paths")
pr.cast(direct, "sob", 2.5, d_out)
pr.cast(psess.state, "sob", 2.5, s_out)
eq(d_out.twist_armed, s_out.twist_armed, "cast flags match: the sob swap arms the twist")
eq(d_out.twist_armed, true, "the sob swap arms on both paths")
pr.tick(direct, 2.7, 0.05, d_out)
H.tick_session(psess, 2.7, 0.05, s_out)
eq(d_out.bl_fired, s_out.bl_fired, "tick flags match: bl_fired")
eq(d_out.buffs_changed, s_out.buffs_changed, "tick flags match: buffs_changed")
eq(d_out.swing_ready, s_out.swing_ready, "tick flags match: swing_ready")
pr.on_swing(direct, 2.7, d_out)
pr.on_swing(psess.state, 2.7, s_out)
eq(d_out.result, s_out.result, "on_swing result matches")
eq(d_out.grade, s_out.grade, "on_swing grade matches")
eq(d_out.grade, "A", "the 200 ms twist grades A on both paths")
near(d_out.lead_ms, s_out.lead_ms, "on_swing lead matches")
sim_matches(direct, psess.state, "harness equivalence after the twist")
near(H.query(psess, "time_to_swing", 3), direct.swing_ends_at - 3, "the swing query mirrors the sim")
eq(H.query(psess, "twist_window_remaining", 3), nil, "no fade window after the twist consumed it")
eq(H.query(psess, "rotation", 3), pr.determine_rotation(direct), "the rotation query mirrors the engine")
H.end_session(psess, 4)
eq(psess.state.fight_active, false, "the harness finish ends the sim fight")
eq(direct.fight_active, true, "the direct sim is untouched by the harness")

if failures == 0 then
    print("PASS  practice_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  practice_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
