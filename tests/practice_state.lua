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

do -- the moving timeline's pure maths (a block: the suite chunk is at the local ceiling)
-- The MOVING timeline's pure maths (the cue strip; the frames live in practice_ui.lua)
-- -------------------------------------------------------------------------------------
-- Playhead / scale: a fixed fraction of the visible strip, and a scale that makes the
-- horizon fill the part to its right.
eq(pr.TL_PLAYHEAD_FRACTION, 0.25, "the playhead fraction is a quarter")
eq(pr.TL_HORIZON_SECONDS, 10, "the visible horizon is ten seconds (the reference strip)")
eq(pr.timeline_playhead_x(600, 0.25), 150, "playhead_x: 25% of 600")
eq(pr.timeline_playhead_x(600), 150, "playhead_x: the shipped fraction by default")
eq(pr.timeline_playhead_x(0), 0, "playhead_x: no width, no playhead")
eq(pr.timeline_playhead_x(600, -3), 0, "playhead_x: clamps below 0")
eq(pr.timeline_playhead_x(600, 3), 600, "playhead_x: clamps above 1")
eq(pr.timeline_pps(600, 0.25, 6), 75, "pps: six seconds fill the right 450 px")
eq(pr.timeline_pps(600, 0.25, 0), 0, "pps: no horizon, no scale")
eq(pr.timeline_pps(0, 0.25, 6), 0, "pps: no width, no scale")
eq(pr.timeline_pps(600, 1, 6), 0, "pps: a playhead at the right edge leaves no horizon")

-- event_x: now on the playhead, future to its right, past to its left.
eq(pr.timeline_event_x(150, 10, 10, 75), 150, "event_x: now sits on the playhead")
eq(pr.timeline_event_x(150, 11.5, 10, 75), 262.5, "event_x: 1.5 s ahead = 112.5 px right")
eq(pr.timeline_event_x(150, 8.5, 10, 75), 37.5, "event_x: 1.5 s late = 112.5 px left")
eq(pr.timeline_event_x(150, nil, 10, 75), nil, "event_x: no clock, no position")
eq(pr.timeline_event_x(150, 10, nil, 75), nil, "event_x: no now, no position")

-- window: the absolute clock range on screen.
local w_from, w_to = pr.timeline_window(10, 600, 75, 0.25)
eq(w_from, 8, "window: 2 s of history on the left")
eq(w_to, 16, "window: 6 s of horizon on the right")
local d_from, d_to = pr.timeline_window(10, 600, 0, 0.25)
eq(d_from, 10, "window: a dead scale collapses on now (from)")
eq(d_to, 10, "window: a dead scale collapses on now (to)")

-- slice: the indices inside a window, both edges inclusive.
local sev = { { at = 7.9 }, { at = 8 }, { at = 10 }, { at = 13 }, { at = 16 }, { at = 16.1 } }
local sf, sl = pr.timeline_slice(sev, 6, 8, 16)
eq(sf, 2, "slice: the first covered index")
eq(sl, 5, "slice: the last covered index")
eq(select(1, pr.timeline_slice(sev, 6, 8.5, 12)), 3, "slice: a narrow window starts at its first cover")
eq(select(2, pr.timeline_slice(sev, 6, 8.5, 12)), 3, "slice: a narrow window ends at its last cover")
eq(select(1, pr.timeline_slice(sev, 6, 20, 30)), nil, "slice: an empty window has no first")
eq(select(1, pr.timeline_slice(sev, 0, 8, 16)), nil, "slice: a zero count covers nothing")
eq(select(1, pr.timeline_slice(nil, 6, 8, 16)), nil, "slice: no array covers nothing")
eq(select(1, pr.timeline_slice(sev, 6, nil, 16)), nil, "slice: an unreadable bound covers nothing")

-- row filter: a cue is a row the tree can read AND the engine can ask for.
eq(pr.timeline_row_is_cue({ live = true, engine = true }), true, "row_is_cue: live+engine")
eq(pr.timeline_row_is_cue({ live = false, engine = true }), false, "row_is_cue: not live")
eq(pr.timeline_row_is_cue({ live = true, engine = false }), false, "row_is_cue: no engine arm")
eq(pr.timeline_row_is_cue({ live = true }), false, "row_is_cue: a missing engine flag is no")
eq(pr.timeline_row_is_cue(nil), false, "row_is_cue: nil row")

-- cadence: the neutral preview, anchored (so it MOVES), one cue per cycle step.
local cad_rotation = {
    { action = "a", label = "A", spell_id = 11, live = true, engine = true },
    { action = "skip", live = false, engine = true },
    { action = "b", label = "B", spell_id = 22, live = true, engine = true },
}
local cad, cad_n = pr.timeline_cadence({}, cad_rotation, 0, 0, 6, 1.5, 3.5)
eq(cad_n, 4, "cadence: four cues fill a 6 s horizon at 2 per 3.5 s cycle")
eq(cad[1].at, 0, "cadence: the first cue is at the anchor")
eq(cad[1].key, "a", "cadence: the first live+engine row")
eq(cad[1].spell_id, 11, "cadence: the row's spell id rides the cue")
eq(cad[2].at, 1.75, "cadence: the cycle's two cues sit evenly (3.5 / 2)")
eq(cad[2].key, "b", "cadence: the dead row is skipped")
eq(cad[3].at, 3.5, "cadence: the next cycle opens on the cycle length")
eq(cad[4].at, 5.25, "cadence: and its second cue follows")
local cad2, cad2_n = pr.timeline_cadence({}, cad_rotation, 0, 5.2, 6, 1.5, 3.5)
eq(cad2_n, 4, "cadence: a later rebuild still fills the horizon")
eq(cad2[1].at, 5.25, "cadence: past cues are dropped, the anchor keeps the rest stable")
eq(select(2, pr.timeline_cadence({}, nil, 0, 0, 6, 1.5, 3.5)), 0,
    "cadence: no rotation table, no cues")
eq(select(2, pr.timeline_cadence({}, {}, 0, 0, 6, 1.5, 3.5)), 0,
    "cadence: an empty rotation table, no cues")
eq(select(2, pr.timeline_cadence({}, { { action = "x", live = false, engine = false } },
    0, 0, 6, 1.5, 3.5)), 0, "cadence: no live+engine row, no cues")
local cad_slots = {}
pr.timeline_cadence(cad_slots, cad_rotation, 0, 0, 6, 1.5, 3.5)
local cad_first_slot = cad_slots[1]
pr.timeline_cadence(cad_slots, cad_rotation, 0, 0, 6, 1.5, 3.5)
eq(cad_slots[1], cad_first_slot, "cadence: the out table's slots are reused, never re-allocated")
-- A future anchor leads the strip (the fight has not started yet).
local cad3, cad3_n = pr.timeline_cadence({}, cad_rotation, 100, 99, 4, 1.5, 3.5)
eq(cad3_n, 2, "cadence: cues run from the anchor when the anchor is still ahead")
eq(cad3[1].at, 100, "cadence: the first cue sits on the anchor")
end

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
    -- The shared rotation-scenario + drill engine (the per-class lanes plug into it).
    "practice_class_module", "practice_scenario_available", "practice_scenario_step",
    "practice_drills", "practice_drill_by_key", "practice_drill_grade",
    "practice_neutral_actions",
    "new_rotation_run", "rotation_run_decide", "rotation_run_summary",
}) do
    check(type(H[name]) == "function", "harness exposes " .. name)
end

-- harness: registry ---------------------------------------------------------------
-- All EIGHT built-in drills stay registered: the class's session wrappers and their
-- offline pins still resolve the old keys (backward compatibility, operator order
-- 2026-10-19). What the ruling changed is the TRUTH and the routing:
--   * three built-ins are SUPERSEDED by a class's own drill list (H.SUPERSEDED_DRILLS):
--     druid_powershift -> druid_powershift_rework (the sim's trigger, not the
--     addon's 20-energy rule), shaman_weave -> shaman_mw_weave (the same weave.lua
--     maths, re-sourced) and warrior_execute -> warrior_execute_burn (the execute
--     phase). One skill, one truth: the class list wins.
--   * a superseded built-in's grading is DELEGATED to the class's drill, so the old
--     truth never grades a player attempt.
eq(#H.SCENARIO_ORDER, 8, "eight built-in drills are registered")
local specs = H.scenarios_for_class(nil)
eq(#specs, 8, "scenarios_for_class(nil) returns every scenario")
eq(specs[1].key, "paladin_twist", "the paladin twist sim is consumer #1")
local paladin_specs = H.scenarios_for_class("PALADIN")
eq(#paladin_specs, 2, "two paladin scenarios")
eq(paladin_specs[1].key, "paladin_twist", "paladin order: twist first")
eq(paladin_specs[2].key, "paladin_aw_combo", "paladin order: AW combo second")
eq(#H.scenarios_for_class("HUNTER"), 1, "one hunter shell")
eq(H.scenarios_for_class("HUNTER")[1].key, "hunter_forced_move", "the hunter shell is H5")
eq(H.get_scenario("hunter_forced_move").kind, "forced_move", "the hunter spec kind")
eq(H.get_scenario("warrior_execute").kind, "execute_phase", "W6 spec kind")
eq(H.get_scenario("druid_powershift").kind, "energy_loop", "D7 spec kind")
eq(H.get_scenario("shaman_weave").kind, "weave_timing", "S7 spec kind")
local rogue_specs = H.scenarios_for_class("ROGUE")
eq(#rogue_specs, 2, "two rogue scenarios")
eq(rogue_specs[1].key, "rogue_energy_pool", "rogue order: energy pool first")
eq(rogue_specs[2].key, "rogue_ss_window", "rogue order: SS window second")
eq(H.get_scenario("rogue_energy_pool").kind, "energy_loop", "rogue energy spec kind")
eq(H.get_scenario("rogue_ss_window").kind, "swing_window", "rogue SS spec kind")
eq(H.get_scenario("paladin_aw_combo").kind, "combo_windows", "P5 spec kind")
eq(H.get_scenario("paladin_twist").kind, "paladin_twist", "the paladin spec kind")
-- The superseded built-ins still resolve (the class wrappers and their pins), and
-- each names the class drill that owns the skill.
eq(H.get_scenario("druid_powershift").class, "DRUID", "the superseded powershift drill still resolves")
eq(H.get_scenario("shaman_weave").class, "SHAMAN", "the superseded weave drill still resolves")
eq(H.get_scenario("warrior_execute").class, "WARRIOR", "the superseded execute drill still resolves")
eq(H.SUPERSEDED_DRILLS.druid_powershift, "druid_powershift_rework",
    "the powershift drill is superseded by the class's own shift rule")
eq(H.SUPERSEDED_DRILLS.shaman_weave, "shaman_mw_weave",
    "the weave drill is superseded by the class's own weave decision")
eq(H.SUPERSEDED_DRILLS.warrior_execute, "warrior_execute_burn",
    "the execute drill is superseded by the class's own execute phase")
eq(H.SUPERSEDED_DRILLS.paladin_twist, nil, "the paladin twist drill is not superseded")
eq(H.SUPERSEDED_DRILLS.hunter_forced_move, nil, "the hunter forced move is not superseded")
eq(H.SUPERSEDED_DRILLS.rogue_energy_pool, nil, "the rogue energy pool is not superseded")
eq(H.get_scenario("nope"), nil, "unknown scenario reads nil")
local dup, dup_err = H.register_scenario({ key = "paladin_twist", title = "dup" })
eq(dup, nil, "duplicate registration is rejected")
check(type(dup_err) == "string", "duplicate registration reports an error")
eq(H.register_scenario({ title = "no key" }), nil, "a keyless spec is rejected")
eq(H.register_scenario({ key = "x", title = "bad kind", kind = "bogus" }), nil,
    "an unknown kind is rejected")
eq(#H.SCENARIO_ORDER, 8, "rejected registrations do not enter the registry")

-- harness: the scenario kinds ------------------------------------------------------
-- The seven shipped kinds keep their meaning and the eight registered entries keep
-- their kinds; the audit's taxonomy adds the rotation scenario kind and the four
-- drill kinds (bench/class_features_drills_2026-10-19.md §4.1).
for _, kind in ipairs({
    "paladin_twist", "combo_windows", "forced_move", "execute_phase",
    "energy_loop", "weave_timing", "swing_window",
    "rotation_run", "rotation_order", "rotation_window", "transition", "situational",
}) do
    eq(H.SCENARIO_KINDS[kind], true, "the scenario kind is accepted: " .. kind)
end
local kind_count = 0
for _ in pairs(H.SCENARIO_KINDS) do kind_count = kind_count + 1 end
eq(kind_count, 12, "twelve scenario kinds are accepted")
-- A new-kind spec registers; the eight shipped entries are untouched.
local run_spec = H.register_scenario({
    key = "test_rotation_run",
    title = "Test rotation run",
    class = "PALADIN",
    kind = "rotation_run",
})
eq(type(run_spec), "table", "a rotation_run spec registers")
eq(H.get_scenario("test_rotation_run").kind, "rotation_run", "the new spec keeps its kind")
eq(#H.SCENARIO_ORDER, 9, "the new spec enters the registry")
eq(H.scenarios_for_class("PALADIN")[3].key, "test_rotation_run", "paladin order: the new spec third")
eq(#H.scenarios_for_class("HUNTER"), 1, "the new spec does not leak into another class")
-- The registry is a live list: the test spec is removed again so the shipped
-- counts stay exact for the rest of the suite.
H.SCENARIOS["test_rotation_run"] = nil
for i = #H.SCENARIO_ORDER, 1, -1 do
    if H.SCENARIO_ORDER[i] == "test_rotation_run" then
        table.remove(H.SCENARIO_ORDER, i)
    end
end
eq(#H.SCENARIO_ORDER, 8, "the registry is back to the eight built-in drills")
eq(H.get_scenario("test_rotation_run"), nil, "the removed spec is gone")

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
-- W6: the tick path carries the transition flags
do
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
end
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
eq(H.grade_energy_spend({ tick_marker = 0 / 0 }, 0.5, 0), nil, "energy: a NaN tick marker grades nothing (never a guessed D)")
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
eq(H.grade_ss_after_swing({ window_start = 0 / 0 }, 0.05), nil, "SS: a NaN window grades nothing (never a guessed B)")
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

--=========================================================================================
-- H2: hunter post-fight shot analytics (pure stats over the shot log)
--=========================================================================================
do
    -- An empty or missing log summarizes empty and hints the empty line.
    do
        local no_shots = pr.summarize_shots({}, nil)
        eq(no_shots.total, 0, "H2: an empty log totals zero")
        eq(no_shots.clipped, 0, "H2: an empty log clips zero")
        eq(no_shots.clip_rate, 0, "H2: an empty log rates zero")
        eq(no_shots.mean_latency, nil, "H2: an empty log has no mean latency")
        local missing = pr.summarize_shots(nil, nil)
        eq(missing.total, 0, "H2: a non-table log summarizes empty")
        eq(pr.shot_hint(missing, nil), "No shots logged yet.", "H2: the empty hint")
        eq(pr.shot_hint(nil, 0.5), "No shots logged yet.", "H2: a non-table summary hints empty")
    end

    -- Mixed samples: totals, clip rate and the mean over numeric latencies only.
    do
        local log = {
            { clipped = false, latency = 0.1, at = 1 },
            { clipped = true, latency = 0.2, at = 2 },
            { clipped = true, latency = nil, at = 3 },
            "not-a-sample",
            { clipped = false, latency = 0.3, at = 4 },
        }
        local s = pr.summarize_shots(log, nil)
        eq(s.total, 4, "H2: non-table entries are skipped")
        eq(s.clipped, 2, "H2: clips count")
        near(s.clip_rate, 0.5, "H2: the clip rate")
        near(s.mean_latency, 0.2, "H2: the mean skips non-numeric latencies")
        eq(pr.shot_buffer_fraction(0.2, 0.6), 0.2 / 0.6, "H2: the buffer fraction")
        -- count caps the samples read.
        local capped = pr.summarize_shots(log, 2)
        eq(capped.total, 2, "H2: count caps the samples read")
        eq(capped.clipped, 1, "H2: the capped clip count")
    end

    -- Buffer fraction nil-cases: never a fraction on a guess.
    do
        eq(pr.shot_buffer_fraction(nil, 0.6), nil, "H2: no mean means no fraction")
        eq(pr.shot_buffer_fraction(0.1, nil), nil, "H2: no window means no fraction")
        eq(pr.shot_buffer_fraction(0.1, 0), nil, "H2: a non-positive window means no fraction")
        eq(pr.shot_buffer_fraction(-0.1, 0.6), nil, "H2: a negative mean means no fraction")
        eq(pr.shot_buffer_fraction("x", 0.6), nil, "H2: a non-number mean means no fraction")
    end

    -- Hint branches: clean (singular/plural), advisory at the warn rate, tighten
    -- below it, and the buffer clause only with both numbers.
    do
        eq(pr.SHOT_CLIP_WARN_RATE, 0.2, "H2: the warn rate is 20%")
        local clean = pr.summarize_shots({ { clipped = false, latency = 0.1 } }, nil)
        eq(pr.shot_hint(clean, nil), "Clean: no clips in 1 shot.",
            "H2: the clean hint (singular, no buffer clause)")
        local clean2 = pr.summarize_shots({
            { clipped = false, latency = 0.1 }, { clipped = false, latency = 0.3 },
        }, nil)
        eq(pr.shot_hint(clean2, 0.6),
            "Clean: no clips in 2 shots. Latency 200ms of a 600ms window (33% buffer used).",
            "H2: the clean hint carries the buffer clause")
        local warn = pr.summarize_shots({
            { clipped = true }, { clipped = false }, { clipped = false },
            { clipped = false }, { clipped = false },
        }, nil)
        near(warn.clip_rate, 0.2, "H2: 1 of 5 rates the warn threshold")
        eq(pr.shot_hint(warn, nil),
            "1 of 5 shots clipped (20%). Start each cast earlier or widen the cast window.",
            "H2: the warn-rate hint advises the window")
        local note = pr.summarize_shots({
            { clipped = true, latency = 0.1 },
            { clipped = false, latency = 0.1 }, { clipped = false, latency = 0.1 },
            { clipped = false, latency = 0.1 }, { clipped = false, latency = 0.1 },
            { clipped = false, latency = 0.1 }, { clipped = false, latency = 0.1 },
            { clipped = false, latency = 0.1 }, { clipped = false, latency = 0.1 },
            { clipped = false, latency = 0.1 },
        }, nil)
        eq(pr.shot_hint(note, 0.6),
            "1 of 10 shots clipped (10%). Tighten the next cast start."
            .. " Latency 100ms of a 600ms window (17% buffer used).",
            "H2: below the warn rate the hint tightens the start")
    end
end

--=========================================================================================
-- Hunter prepull checklist (pure data + missing/readout helpers)
--=========================================================================================
do
    local steps = pr.HUNTER_PREPULL_STEPS
    check(type(steps) == "table", "prepull: the step table is defined")
    eq(#steps, 3, "prepull: three generic steps")
    eq(steps[1].key, "mark", "prepull: mark first")
    eq(steps[2].key, "aspect", "prepull: aspect second")
    eq(steps[3].key, "potion", "prepull: potion third")
    local all = pr.hunter_prepull_missing({ mark = true, aspect = true, potion = true })
    eq(#all, 0, "prepull: nothing missing when all done")
    eq(pr.hunter_prepull_hint(all), "Ready.", "prepull: the ready readout")
    local some = pr.hunter_prepull_missing({ mark = true })
    eq(#some, 2, "prepull: two steps missing")
    eq(some[1], "Hawk aspect", "prepull: order follows the checklist")
    eq(some[2], "Haste potion", "prepull: order follows the checklist")
    eq(pr.hunter_prepull_hint(some), "Prepull: Hawk aspect, Haste potion.",
        "prepull: the missing readout")
    local none = pr.hunter_prepull_missing(nil)
    eq(#none, 3, "prepull: a missing map misses everything")
    eq(pr.hunter_prepull_hint(nil), "Ready.", "prepull: a nil list reads ready")
    local partial = pr.hunter_prepull_missing({ mark = false, aspect = true, potion = true })
    eq(#partial, 1, "prepull: false never counts as done")
    eq(partial[1], "Hunter's Mark", "prepull: the false entry is listed")
end

--=========================================================================================
-- Hunter weave/move-cue checklist (pure data + missing/readout helpers)
--=========================================================================================
do
    local steps = pr.HUNTER_WEAVE_STEPS
    check(type(steps) == "table", "weave: the step table is defined")
    eq(#steps, 3, "weave: three generic steps")
    eq(steps[1].key, "trap", "weave: trap first")
    eq(steps[2].key, "melee", "weave: melee second")
    eq(steps[3].key, "move", "weave: move third")
    local all = pr.hunter_weave_missing({ trap = true, melee = true, move = true })
    eq(#all, 0, "weave: nothing missing when all done")
    eq(pr.hunter_weave_hint(all), "Weave set.", "weave: the ready readout")
    local some = pr.hunter_weave_missing({ trap = true })
    eq(#some, 2, "weave: two steps missing")
    eq(some[1], "Melee weave inside 5 yd", "weave: order follows the checklist")
    eq(some[2], "Move on the swing gap", "weave: order follows the checklist")
    eq(pr.hunter_weave_hint(some), "Weave: Melee weave inside 5 yd, Move on the swing gap.",
        "weave: the missing readout")
    local none = pr.hunter_weave_missing(nil)
    eq(#none, 3, "weave: a missing map misses everything")
    eq(pr.hunter_weave_hint(nil), "Weave set.", "weave: a nil list reads ready")
    local partial = pr.hunter_weave_missing({ trap = false, melee = true, move = true })
    eq(#partial, 1, "weave: false never counts as done")
    eq(partial[1], "Trap down before the pull", "weave: the false entry is listed")
end

--=========================================================================================
-- Combat resource pools (sim-resources lane)
--=========================================================================================
-- Two locals only (s, c): the 5.1 chunk caps at 200 locals and the suites
-- above already spend most of them.
do
    local s, c
    -- Rage constants (wowsims/classic sim/core/rage.go + bloodthirst.go).
    eq(pr.RAGE_MAX, 100, "rage: max 100")
    eq(pr.RAGE_DEALT_MULT, 7.5, "rage: dealt mult 7.5")
    eq(pr.RAGE_TAKEN_MULT, 2.5, "rage: taken mult 2.5")
    eq(pr.RAGE_BT_REFUND, 0.8, "rage: BT miss refund 0.8")
    eq(pr.WARRIOR_RAGE_COSTS.bt, 30, "rage: BT costs 30")
    eq(pr.WARRIOR_RAGE_COSTS.ww, 25, "rage: WW costs 25")
    eq(pr.WARRIOR_RAGE_COSTS.slam, 15, "rage: Slam costs 15")
    eq(pr.WARRIOR_RAGE_COSTS.op, 5, "rage: OP costs 5")

    -- Conversion (sim GetRageConversion: 25 -> 82.25, 40 -> 140.5 tested).
    eq(pr.rage_conversion(25), 82.25, "rage: conversion at 25")
    eq(pr.rage_conversion(40), 140.5, "rage: conversion at 40")
    c = pr.rage_conversion(60)
    check(type(c) == "number" and c > 230.5 and c < 230.7, "rage: conversion at 60 near 230.6")
    c = pr.rage_conversion(70)
    check(type(c) == "number" and c > 274.6 and c < 274.8, "rage: conversion at 70 near 274.7")
    eq(pr.rage_conversion(0), nil, "rage: conversion at 0 is nil")
    eq(pr.rage_conversion(-5), nil, "rage: conversion at negative is nil")
    eq(pr.rage_conversion(nil), nil, "rage: conversion of nil is nil")
    eq(pr.rage_conversion("60"), nil, "rage: conversion of a string is nil")
    eq(pr.rage_conversion(0 / 0), nil, "rage: conversion of NaN is nil")

    -- White/taken gains (sim OnSpellHitDealt/Taken).
    eq(pr.rage_white_gain(100, 50), 15, "rage: white 100dmg/50conv is 15")
    eq(pr.rage_white_gain(100, 50, 2.5), 5, "rage: white honors an explicit mult")
    eq(pr.rage_white_gain(100, 50, nil), 15, "rage: white nil mult reads the dealt default")
    eq(pr.rage_white_gain(100, 50, 0), 15, "rage: white bad mult reads the dealt default")
    eq(pr.rage_white_gain(nil, 50), nil, "rage: white nil damage is nil (miss)")
    eq(pr.rage_white_gain(100, nil), nil, "rage: white nil conversion is nil")
    eq(pr.rage_white_gain(100, 0), nil, "rage: white zero conversion is nil")
    eq(pr.rage_white_gain(-5, 50), nil, "rage: white negative damage is nil")
    eq(pr.rage_white_gain(0 / 0, 50), nil, "rage: white NaN damage is nil")
    eq(pr.rage_taken_gain(100, 50), 5, "rage: taken 100dmg/50conv is 5")
    eq(pr.rage_taken_gain(100, 50, 7.5), 15, "rage: taken honors an explicit mult")
    eq(pr.rage_taken_gain(nil, 50), nil, "rage: taken nil damage is nil")
    eq(pr.rage_taken_gain(100, nil), nil, "rage: taken nil conversion is nil")

    -- Pool lifecycle.
    s = pr.new_rage_state()
    eq(s.rage, 0, "rage: a fresh pool starts empty")
    eq(s.max, 100, "rage: a fresh pool caps at 100")
    s = pr.new_rage_state({ rage = 50 })
    eq(s.rage, 50, "rage: starting value kept")
    eq(pr.new_rage_state({ rage = 150 }).rage, 100, "rage: starting value clamps at max")
    eq(pr.new_rage_state({ rage = -5 }).rage, 0, "rage: negative start floors at 0")
    eq(pr.new_rage_state({ rage = 0 / 0 }).rage, 0, "rage: NaN start reads empty")
    s = pr.new_rage_state({ max = 200, rage = 30 })
    eq(s.max, 200, "rage: explicit max kept")
    eq(s.rage, 30, "rage: value under an explicit max kept")
    eq(pr.new_rage_state({ max = -1 }).max, 100, "rage: bad max falls back to 100")

    -- Gains cap; bad amounts bank nothing.
    s = pr.new_rage_state({ rage = 50 })
    eq(pr.rage_gain(s, 20), 70, "rage: gain banks")
    eq(s.rage, 70, "rage: gain lands in the pool")
    eq(pr.rage_gain(s, 999), 100, "rage: gain caps at max")
    eq(pr.rage_gain(s, nil), nil, "rage: nil gain banks nothing")
    eq(s.rage, 100, "rage: nil gain leaves the pool")
    eq(pr.rage_gain(s, 0), nil, "rage: zero gain banks nothing")
    eq(pr.rage_gain(s, -5), nil, "rage: negative gain banks nothing")
    eq(pr.rage_gain(s, 0 / 0), nil, "rage: NaN gain banks nothing")
    eq(pr.rage_gain(nil, 10), nil, "rage: gain on no pool is nil")
    eq(pr.rage_gain(s, 30 * pr.RAGE_BT_REFUND), 100, "rage: the BT-miss refund banks through gain")

    -- Spends fail closed.
    s = pr.new_rage_state({ rage = 100 })
    eq(pr.rage_spend(s, 30), true, "rage: BT spend fires")
    eq(s.rage, 70, "rage: BT spend deducts")
    eq(pr.rage_spend(s, 999), false, "rage: uncovered spend refuses")
    eq(s.rage, 70, "rage: refused spend leaves the pool")
    eq(pr.rage_spend(s, 0 / 0), false, "rage: NaN cost never spends")
    eq(pr.rage_spend(s, -5), false, "rage: negative cost never spends")
    eq(pr.rage_spend(s, 0), true, "rage: zero cost is a free no-op")
    eq(s.rage, 70, "rage: zero cost deducts nothing")
    eq(pr.rage_spend(nil, 30), false, "rage: spend on no pool is false")
    eq(pr.rage_spend(s, nil), false, "rage: nil cost never spends")

    -- Execute drains all.
    eq(pr.rage_drain_all(s), 70, "rage: drain returns the pooled rage")
    eq(s.rage, 0, "rage: drain zeroes the pool")
    eq(pr.rage_drain_all(s), 0, "rage: drain on empty is 0")
    eq(pr.rage_drain_all(nil), nil, "rage: drain on no pool is nil")

    -- Affordability gate (pool twin of the live composite_rage_gate).
    s = pr.new_rage_state({ rage = 70 })
    eq(pr.rage_can_spend(s, 30, 20), true, "rage: 70 covers 30 + 20 reserve")
    eq(pr.rage_can_spend(s, 30, 40), true, "rage: 70 covers exactly 30 + 40")
    eq(pr.rage_can_spend(s, 30, 41), false, "rage: 70 cannot cover 30 + 41")
    eq(pr.rage_can_spend(s, 30, nil), true, "rage: nil reserve counts as 0")
    eq(pr.rage_can_spend(s, 30, 0 / 0), true, "rage: NaN reserve counts as 0")
    eq(pr.rage_can_spend(s, 30, -5), true, "rage: negative reserve counts as 0")
    eq(pr.rage_can_spend(s, nil, 0), false, "rage: unknown cost fails closed")
    eq(pr.rage_can_spend(s, 0 / 0, 0), false, "rage: NaN cost fails closed")
    eq(pr.rage_can_spend(nil, 30, 0), false, "rage: no pool fails closed")
    eq(pr.rage_can_spend({}, 30, 0), false, "rage: unreadable pool fails closed")

    -- Spend grades for the shared score pipeline.
    eq(pr.rage_spend_grade(s, 30, 20), "S", "rage: covered spend grades S")
    eq(pr.rage_spend_grade(s, 30, 41), "F", "rage: starving spend grades F")
    eq(pr.rage_spend_grade(s, nil, 0), nil, "rage: unknown cost grades nothing")
    eq(pr.rage_spend_grade(nil, 30, 0), nil, "rage: no pool grades nothing")
    eq(pr.rage_spend_grade({}, 30, 0), nil, "rage: unreadable pool grades nothing")

    -- Mana pool (mechanics only; costs/regen filed - see the header).
    s = pr.new_mana_state()
    eq(s.mana, 0, "mana: a fresh pool starts empty")
    eq(s.max, nil, "mana: max is caller-fed (nil default)")
    eq(pr.new_mana_state({ max = 5000 }).max, 5000, "mana: explicit max kept")
    eq(pr.new_mana_state({ max = 100, mana = 150 }).mana, 100, "mana: start clamps at max")
    eq(pr.mana_gain(s, 40), 40, "mana: uncapped gain banks")
    s = pr.new_mana_state({ max = 100, mana = 90 })
    eq(pr.mana_gain(s, 20), 100, "mana: gain caps when the max is known")
    eq(pr.mana_gain(s, nil), nil, "mana: nil gain banks nothing")
    eq(pr.mana_spend(s, 30), true, "mana: covered spend fires")
    eq(s.mana, 70, "mana: spend deducts")
    eq(pr.mana_spend(s, 999), false, "mana: uncovered spend refuses")
    eq(s.mana, 70, "mana: refused spend leaves the pool")
    eq(pr.mana_spend(s, nil), false, "mana: nil cost never spends")
    eq(pr.mana_can_spend(s, 70), true, "mana: exact cover is affordable")
    eq(pr.mana_can_spend(s, 71), false, "mana: one short is not")
    eq(pr.mana_can_spend(nil, 10), false, "mana: no pool fails closed")

    -- Focus pool (mechanics only; costs/regen filed - see the header).
    s = pr.new_focus_state()
    eq(s.focus, 0, "focus: a fresh pool starts empty")
    eq(s.max, nil, "focus: max is caller-fed (nil default)")
    eq(pr.new_focus_state({ max = 100, focus = 120 }).focus, 100, "focus: start clamps at max")
    eq(pr.focus_gain(s, 25), 25, "focus: uncapped gain banks")
    s = pr.new_focus_state({ max = 100, focus = 90 })
    eq(pr.focus_gain(s, 20), 100, "focus: gain caps when the max is known")
    eq(pr.focus_spend(s, 40), true, "focus: covered spend fires")
    eq(s.focus, 60, "focus: spend deducts")
    eq(pr.focus_spend(s, 999), false, "focus: uncovered spend refuses")
    eq(pr.focus_spend(s, nil), false, "focus: nil cost never spends")
    eq(pr.focus_can_spend(s, 60), true, "focus: exact cover is affordable")
    eq(pr.focus_can_spend(s, 61), false, "focus: one short is not")
end

--=========================================================================================
-- The shared rotation-scenario + drill engine (the per-class lanes plug into it)
--=========================================================================================
-- The contract the six class lanes code against (fixed by the orchestrator):
--   ST.<CLASS>.practice_scenario_step(self, ctx)
--       -> { action = "<spell key>", reason = "<text>" } | nil
--   ST.<CLASS>.practice_drills
--       = { { key = "<registry key>", label = "<label>",
--            grade = function(self, ctx) -> "S".."F" | nil end }, ... }
-- The engine looks them up by player_class; a class that provides neither degrades
-- loudly (the UI prints the refusal) - never a silent paladin sim.
--
-- The block runs in its own function: the suite's chunk is already at Lua 5.1's
-- 200-local limit, and a nested frame has its own budget.
local function engine_tests()
-- A fake class module: the engine only ever reads the two contract members.
local fake = {}
fake.practice_scenario_step = function(self, ctx)
    fake.last_self = self
    fake.last_ctx = ctx
    if ctx and ctx.now and ctx.now >= 100 then
        return nil
    end
    return { action = "cs", reason = "the seal is up" }
end
fake.practice_drills = {
    { key = "fake_timing", label = "Fake timing", grade = function() return "A" end },
    { key = "fake_window", label = "Fake window", grade = function() return nil end },
    { key = "fake_broken", label = "Fake broken", grade = function() error("boom") end },
}
st.FAKE = fake

eq(H.practice_class_module("FAKE"), fake, "the class module is found by its class key")
eq(H.practice_class_module("NOPE"), nil, "an unknown class has no module")
eq(H.practice_class_module(nil), nil, "a nil class key has no module")
eq(H.practice_class_module(""), nil, "an empty class key has no module")

eq(H.practice_scenario_available("FAKE"), true, "a class with a step function has a scenario")
eq(H.practice_scenario_available("NOPE"), false, "a class without one has no scenario")
eq(H.practice_scenario_available(nil), false, "a nil class has no scenario")
-- A class module WITHOUT the step function has no scenario (the module is there,
-- the contract member is not).
st.NOSTEP = { practice_drills = {} }
eq(H.practice_scenario_available("NOSTEP"), false,
    "a class module without a step function has no scenario")
st.NOSTEP = nil

local answer = H.practice_scenario_step("FAKE", st, { now = 1 })
eq(type(answer), "table", "the class's answer comes back")
eq(answer.action, "cs", "the answer carries the action")
eq(answer.reason, "the seal is up", "the answer carries the reason")
eq(fake.last_self, st, "the step is called with the addon as self")
eq(fake.last_ctx.now, 1, "the step receives the injected clock")
eq(H.practice_scenario_step("FAKE", st, { now = 100 }), nil,
    "a class that cannot decide answers nil (never a wrong action)")
eq(H.practice_scenario_step("NOPE", st, { now = 1 }), nil,
    "a class without a step function answers nil")
eq(H.practice_scenario_step(nil, st, { now = 1 }), nil, "a nil class answers nil")

-- A class whose step throws answers nil (the engine never propagates the throw).
st.THROWER = {
    practice_scenario_step = function() error("boom") end,
}
eq(H.practice_scenario_step("THROWER", st, { now = 1 }), nil, "a throwing step answers nil")
-- A class whose step answers garbage answers nil.
st.GARBAGE = {
    practice_scenario_step = function() return { action = "" } end,
}
eq(H.practice_scenario_step("GARBAGE", st, { now = 1 }), nil, "an empty action answers nil")
st.GARBAGE.practice_scenario_step = function() return "cs" end
eq(H.practice_scenario_step("GARBAGE", st, { now = 1 }), nil, "a non-table answer answers nil")
st.GARBAGE = nil
st.THROWER = nil

-- The drill list: only the entries that carry a key and a grader survive.
local drills = H.practice_drills("FAKE")
eq(type(drills), "table", "the class's drill list comes back")
eq(#drills, 3, "every well-formed drill survives")
eq(drills[1].key, "fake_timing", "the drill order is kept")
eq(drills[1].label, "Fake timing", "the drill label is kept")
eq(H.practice_drills("NOPE"), nil, "a class without drills has none")
eq(H.practice_drills(nil), nil, "a nil class has no drills")
st.NODRILLS = { practice_drills = { { label = "no key" }, { key = "no grade" } } }
eq(H.practice_drills("NODRILLS"), nil, "a class with no gradeable drill has no drills")
st.NODRILLS.practice_drills = {}
eq(H.practice_drills("NODRILLS"), nil, "an empty drill list has no drills")
st.NODRILLS = nil

eq(H.practice_drill_by_key("FAKE", "fake_timing").key, "fake_timing", "a drill is found by key")
eq(H.practice_drill_by_key("FAKE", "nope"), nil, "an unknown drill key reads nil")
eq(H.practice_drill_by_key("FAKE", nil), nil, "a nil drill key reads nil")
eq(H.practice_drill_grade("FAKE", "fake_timing", st, { now = 1 }), "A",
    "the class's grader answers the grade")
eq(H.practice_drill_grade("FAKE", "fake_window", st, { now = 1 }), nil,
    "a grader that cannot judge answers nil (never a guessed grade)")
eq(H.practice_drill_grade("FAKE", "fake_broken", st, { now = 1 }), nil,
    "a throwing grader answers nil")
eq(H.practice_drill_grade("FAKE", "nope", st, { now = 1 }), nil,
    "an unknown drill answers nil")
-- A grader that answers a letter outside the grade set is rejected.
st.BADGRADE = {
    practice_drills = { { key = "bad", label = "Bad", grade = function() return "Z" end } },
}
eq(H.practice_drill_grade("BADGRADE", "bad", st, { now = 1 }), nil,
    "a grade outside the grade set is rejected")
st.BADGRADE = nil

-- The rotation run: the pure state machine.
eq(H.ROTATION_RUN_STEPS, 10, "the run is ten decisions long")
local run = H.new_rotation_run()
eq(run.steps, 0, "a fresh run has no decisions")
eq(run.max_steps, 10, "a fresh run has the default length")
eq(run.finished, false, "a fresh run is not finished")
eq(H.new_rotation_run({ max_steps = 3 }).max_steps, 3, "the length is caller-fed")
eq(H.new_rotation_run({ max_steps = 0 }).max_steps, 10, "a zero length falls back")
eq(H.new_rotation_run({ max_steps = "x" }).max_steps, 10, "a non-number length falls back")

local rd1 = H.rotation_run_decide(run, "cs", "cs")
eq(rd1.outcome, "correct", "a matching cast is correct")
eq(rd1.expected, "cs", "the decision records the expectation")
eq(rd1.actual, "cs", "the decision records the cast")
eq(run.correct, 1, "the run counts the correct decision")
local rd2 = H.rotation_run_decide(run, "cs", "judge")
eq(rd2.outcome, "out_of_order", "a different cast is out of order")
eq(run.mispicks, 1, "the run counts the mis-pick")
local rd3 = H.rotation_run_decide(run, "cs", nil)
eq(rd3.outcome, "miss", "no cast is a miss")
eq(run.misses, 1, "the run counts the miss")
local rd4 = H.rotation_run_decide(run, nil, "cs")
eq(rd4.outcome, "unknown", "no expectation is unknown")
eq(rd4.expected, nil, "an unknown decision records no expectation")
eq(run.unknown, 1, "the run counts the unknown decision")
eq(run.steps, 4, "every decision counts as a step")
eq(run.finished, false, "the run is not finished yet")

-- The outcome grades: a correct decision is a hit, a wrong or missing one a miss.
eq(H.ROTATION_OUTCOME_GRADES.correct, "S", "a correct decision grades S")
eq(H.ROTATION_OUTCOME_GRADES.out_of_order, "F", "an out-of-order decision grades F")
eq(H.ROTATION_OUTCOME_GRADES.miss, "F", "a miss grades F")
eq(H.ROTATION_OUTCOME_GRADES.unknown, nil, "an unknown decision grades nothing")
for _, outcome in ipairs({ "correct", "out_of_order", "miss", "unknown" }) do
    eq(H.ROTATION_OUTCOMES[outcome], true, "the outcome class exists: " .. outcome)
end

-- The summary and the run bands.
local summary = H.rotation_run_summary(run)
eq(summary.steps, 4, "the summary counts the steps")
eq(summary.correct, 1, "the summary counts the correct decisions")
eq(summary.mispicks, 1, "the summary counts the mis-picks")
eq(summary.misses, 1, "the summary counts the misses")
eq(summary.unknown, 1, "the summary counts the unknown decisions")
eq(summary.grade, "B", "two mis-picks (one out of order, one miss) grade B")
eq(summary.finished, false, "the summary reports the unfinished run")

-- The band edges: 0 mis-picks S, 1 A, 2 B, 3 C, 4-5 D, 6+ F.
eq(H.grade_band(0, H.ROTATION_RUN_BANDS), "S", "0 mis-picks grades S")
eq(H.grade_band(1, H.ROTATION_RUN_BANDS), "A", "1 mis-pick grades A")
eq(H.grade_band(2, H.ROTATION_RUN_BANDS), "B", "2 mis-picks grade B")
eq(H.grade_band(3, H.ROTATION_RUN_BANDS), "C", "3 mis-picks grade C")
eq(H.grade_band(4, H.ROTATION_RUN_BANDS), "D", "4 mis-picks grade D")
eq(H.grade_band(5, H.ROTATION_RUN_BANDS), "D", "5 mis-picks grade D")
eq(H.grade_band(6, H.ROTATION_RUN_BANDS), "F", "6 mis-picks grade F")

-- A run with nothing gradeable reads UNKNOWN, never a perfect S.
local blind = H.new_rotation_run()
H.rotation_run_decide(blind, nil, "cs")
H.rotation_run_decide(blind, nil, nil)
local blind_summary = H.rotation_run_summary(blind)
eq(blind_summary.grade, nil, "a run with no gradeable decision has no grade")
eq(blind_summary.unknown, 2, "the blind run counts its unknown decisions")

-- The run ends after its length; a further decision is refused.
local short = H.new_rotation_run({ max_steps = 2 })
H.rotation_run_decide(short, "cs", "cs")
H.rotation_run_decide(short, "cs", "cs")
eq(short.finished, true, "the run finishes after its last decision")
eq(H.rotation_run_decide(short, "cs", "cs"), nil, "a finished run takes no further decision")
eq(H.rotation_run_summary(short).finished, true, "the summary reports the finished run")
eq(H.rotation_run_decide(nil, "cs", "cs"), nil, "a nil run takes no decision")
eq(H.rotation_run_summary(nil), nil, "a nil run has no summary")

-- Determinism: the same answers give the same run.
local det_a = H.new_rotation_run()
local det_b = H.new_rotation_run()
for i = 1, 4 do
    H.rotation_run_decide(det_a, "cs", i == 2 and "judge" or "cs")
    H.rotation_run_decide(det_b, "cs", i == 2 and "judge" or "cs")
end
eq(H.rotation_run_summary(det_a).grade, H.rotation_run_summary(det_b).grade,
    "determinism: identical answer sequences give identical grades")
eq(H.rotation_run_summary(det_a).correct, H.rotation_run_summary(det_b).correct,
    "determinism: identical answer sequences give identical counts")

st.FAKE = nil
end

--=========================================================================================
-- The superseded built-in drill: the class's own drill is the single source of truth
--=========================================================================================
-- A built-in drill that a class's drill list supersedes grades THROUGH that class
-- drill: the old truth (the addon's 20-energy rule, the plain weave fit) never
-- grades a player attempt. The delegation is best effort - without the class drill
-- the built-in model stands in (a flavour that ships no class drill at all).
do
local fake_addon = {}
fake_addon.DRUID = {
    practice_drills = {
        { key = "druid_powershift_rework", label = "The shift rule",
          grade = function(self, ctx)
              fake_addon.graded = ctx
              return "S"
          end },
    },
}
env.LibStub = function()
    return { GetAddon = function() return fake_addon end }
end
local ds_delegate = H.new_session("druid_powershift", 0)
H.begin_session(ds_delegate, 0)
H.tick_session(ds_delegate, 0, 0.05, {})
H.tick_session(ds_delegate, 1, 0.05, {})
eq(H.scenario_event(ds_delegate, "shift", 1), "S",
    "the superseded drill grades through the class's own drill")
check(type(fake_addon.graded) == "table", "the class's drill received a context")
eq(fake_addon.graded.now, 1, "the context carries the injected clock")
eq(fake_addon.graded.last_action, "shift", "the context carries the action")
eq(fake_addon.graded.energy, 10, "the context carries the shell's own state")
-- A flavour without the class drill: the built-in model stands in (never a throw).
env.LibStub = function()
    return { GetAddon = function() return {} end }
end
local ds_fallback = H.new_session("druid_powershift", 0)
H.begin_session(ds_fallback, 0)
H.tick_session(ds_fallback, 0, 0.05, {})
H.tick_session(ds_fallback, 1, 0.05, {})
eq(H.scenario_event(ds_fallback, "shift", 1), "S",
    "without the class drill the built-in model grades the shift")
env.LibStub = nil
end

engine_tests()

--=========================================================================================
-- HU-8: a hold is a DECISION, unknown is not
--=========================================================================================
-- The operator ruling (hands-up HU-8, resolved 2026-10-19): a class that decides to
-- hold says so explicitly. The engine then grades the step as a hold:
--   * casting any action during it is an ILLEGAL CAST (F - an attempt that costs
--     the streak), and
--   * doing nothing during it is CORRECT - recorded, but worth nothing: no
--     attempt, so a player cannot farm points by idling through a hold.
-- A nil step with NO hold statement stays UNKNOWN: no attempt, never a wrong
-- grade. The class-side statements are a separate lane; the ENGINE half is here.
--
-- The block runs in its own function: the suite's chunk is already at Lua 5.1's
-- 200-local limit, and a nested frame has its own budget.
local function hold_tests()
-- The class answers a hold: { action = nil, hold = true, reason = "..." }.
st.HOLDER = {
    practice_scenario_step = function()
        return { action = nil, hold = true, reason = "pool the resource first" }
    end,
}
local hold_answer = H.practice_scenario_step("HOLDER", st, { now = 1 })
eq(type(hold_answer), "table", "a hold statement comes back as an answer")
eq(hold_answer.hold, true, "the answer carries the hold flag")
eq(hold_answer.action, nil, "a hold statement names no action")
eq(hold_answer.reason, "pool the resource first", "the hold carries the class's reason")

-- A step that names NEITHER an action nor a hold is the "cannot decide" case: it
-- stays UNKNOWN (nil), exactly as before the ruling.
st.NOHOLD = {
    practice_scenario_step = function() return { reason = "no idea" } end,
}
eq(H.practice_scenario_step("NOHOLD", st, { now = 1 }), nil,
    "a step with neither an action nor a hold stays unknown")
-- A hold flag that is not exactly true is not a hold statement.
st.FALSEHOLD = {
    practice_scenario_step = function() return { action = nil, hold = "yes" } end,
}
eq(H.practice_scenario_step("FALSEHOLD", st, { now = 1 }), nil,
    "a non-boolean hold flag is not a hold statement")
-- A step that names an action is an ACTION: the hold flag is ignored (a class
-- that means to hold must not name an action).
st.BOTH = {
    practice_scenario_step = function() return { action = "cs", hold = true } end,
}
local both_answer = H.practice_scenario_step("BOTH", st, { now = 1 })
eq(both_answer.action, "cs", "a named action wins over the hold flag")
eq(both_answer.hold, nil, "an action is not a hold")

-- The outcome classes and the grade map.
eq(H.ROTATION_OUTCOMES.hold_ok, true, "the correct-hold outcome exists")
eq(H.ROTATION_OUTCOMES.illegal_cast, true, "the illegal-cast outcome exists")
eq(H.ROTATION_OUTCOME_GRADES.illegal_cast, "F", "an illegal cast grades F")
eq(H.ROTATION_OUTCOME_GRADES.hold_ok, nil,
    "a correct hold grades nothing (no attempt, no points)")
eq(H.ROTATION_OUTCOME_GRADES.unknown, nil, "an unknown decision grades nothing")

-- The run: a hold step.
local run = H.new_rotation_run()
local held = H.rotation_run_decide(run, nil, nil, true)
eq(held.outcome, "hold_ok", "nothing cast during a hold is a correct hold")
eq(held.hold, true, "the decision records that the step was a hold")
eq(run.holds, 1, "the run counts the correct hold")
eq(run.correct, 1, "the correct hold counts as a correct decision")
eq(run.mispicks, 0, "the correct hold is not a mis-pick")
eq(run.unknown, 0, "the correct hold is not an unknown")
-- A cast during the hold is the illegal cast: an attempt, and it counts against
-- the run's band.
local cast = H.rotation_run_decide(run, nil, "cs", true)
eq(cast.outcome, "illegal_cast", "a cast during a hold is an illegal cast")
eq(cast.actual, "cs", "the illegal cast records the cast")
eq(run.illegal_casts, 1, "the run counts the illegal cast")
eq(run.mispicks, 1, "the illegal cast counts against the run's band")
eq(run.holds, 1, "the correct hold is still counted")
-- A hold step with an expectation is still a hold (the class stated it).
local both_hold = H.rotation_run_decide(run, "cs", nil, true)
eq(both_hold.outcome, "hold_ok", "a hold wins over the expectation")

-- A nil step with NO hold statement is still UNKNOWN: no attempt, never wrong.
local unknown_run = H.new_rotation_run()
local unknown = H.rotation_run_decide(unknown_run, nil, "cs")
eq(unknown.outcome, "unknown", "a nil step with no hold statement stays unknown")
eq(unknown_run.unknown, 1, "the run counts the unknown decision")
eq(unknown_run.mispicks, 0, "an unknown decision is never a mis-pick")
eq(H.ROTATION_OUTCOME_GRADES[unknown.outcome], nil,
    "an unknown decision records no attempt")

-- The summary carries the hold counters.
local summary = H.rotation_run_summary(run)
eq(summary.holds, 2, "the summary counts the correct holds")
eq(summary.illegal_casts, 1, "the summary counts the illegal casts")
eq(summary.mispicks, 1, "the summary counts the mis-picks")
eq(summary.grade, "A", "one mis-pick grades A (the illegal cast counts)")

-- Determinism: the same answers give the same run (the engine reads no clock
-- and invents no randomness).
local det_a, det_b = H.new_rotation_run(), H.new_rotation_run()
for _ = 1, 4 do
    H.rotation_run_decide(det_a, nil, nil, true)
    H.rotation_run_decide(det_b, nil, nil, true)
end
eq(H.rotation_run_summary(det_a).grade, H.rotation_run_summary(det_b).grade,
    "determinism: identical hold sequences give identical grades")
eq(H.rotation_run_summary(det_a).holds, H.rotation_run_summary(det_b).holds,
    "determinism: identical hold sequences give identical counts")

st.HOLDER = nil
st.NOHOLD = nil
st.FALSEHOLD = nil
st.BOTH = nil
end

hold_tests()

--=========================================================================================
-- The NEUTRAL action: a legitimate action the rotation did not ask for
--=========================================================================================
-- The operator order (2026-10-20): the practice panel offers the class's whole
-- ability list, so a player can press a common spell (a heal, a shield, food, a
-- potion, a movement ability) that the rotation never asks for. Grading that
-- press as a mis-pick (F) cost the streak and decayed the band for something the
-- player did RIGHT. So the engine grows a NEUTRAL outcome: no attempt, no points,
-- no mis-pick - the run counts it and the summary shows it.
--
-- The class seam (the accessor's contract, for the class lane):
--   ST.<CLASS>.practice_neutral_actions = { heal = true, ... }        (flat)
--   ST.<CLASS>.practice_neutral_actions = { ERA = { ... }, TBC = { ... } }  (per family)
-- A class that publishes NOTHING keeps today's behaviour: every non-rotation press
-- is a mis-pick.
--
-- The block runs in its own function: the suite's chunk is already at Lua 5.1's
-- 200-local limit, and a nested frame has its own budget.
local function neutral_tests()
-- The class publishes a flat set: the accessor answers that set.
st.NEUTRAL = {
    practice_neutral_actions = { heal = true, shield = true },
}
local flat = H.practice_neutral_actions("NEUTRAL")
eq(type(flat), "table", "a published neutral set comes back as a table")
eq(type(flat) == "table" and flat.heal, true, "the published heal key is in the set")
eq(type(flat) == "table" and flat.shield, true, "the published shield key is in the set")
eq(type(flat) == "table" and flat.food, nil, "an unpublished key is not in the set")
eq(type(H.practice_neutral_actions(st.NEUTRAL)) == "table"
    and H.practice_neutral_actions(st.NEUTRAL).heal, true,
    "the accessor takes the class module as well as the class key")
flat = flat or {}
flat.food = true
eq(st.NEUTRAL.practice_neutral_actions.food, nil,
    "the accessor hands out a copy, never the published table")

-- A class that publishes NOTHING: the accessor answers nil (unknown-hides).
st.NEUTRALNONE = {}
eq(H.practice_neutral_actions("NEUTRALNONE"), nil,
    "a class with no published set answers nil")
-- A malformed publish: not a table, empty, or no true value - all nil.
st.NEUTRALBAD = { practice_neutral_actions = "heal" }
eq(H.practice_neutral_actions("NEUTRALBAD"), nil, "a non-table publish answers nil")
st.NEUTRALEMPTY = { practice_neutral_actions = {} }
eq(H.practice_neutral_actions("NEUTRALEMPTY"), nil, "an empty publish answers nil")
st.NEUTRALFALSE = { practice_neutral_actions = { heal = "yes" } }
eq(H.practice_neutral_actions("NEUTRALFALSE"), nil,
    "a publish with no true value answers nil")
eq(H.practice_neutral_actions("NOCLASSATALL"), nil, "an unknown class answers nil")

-- A family-scoped publish: the set of the CURRENT family, and nil for a family
-- the class published no bucket for (the engine never guesses a set).
st.NEUTRALFAMILY = {
    practice_neutral_actions = {
        ERA = { heal = true },
        TBC = { heal = true, food = true },
    },
}
st.family = "TBC"
local family_set = H.practice_neutral_actions("NEUTRALFAMILY")
eq(type(family_set), "table", "a family-scoped publish resolves for the current family")
eq(type(family_set) == "table" and family_set.food, true,
    "the current family's key is in the set")
eq(type(family_set) == "table" and family_set.shield, nil,
    "another family's key is not in the set")
st.family = "WRATH"
eq(H.practice_neutral_actions("NEUTRALFAMILY"), nil,
    "a family with no published bucket answers nil")
st.family = nil
eq(H.practice_neutral_actions("NEUTRALFAMILY"), nil,
    "a family-scoped publish with no family answers nil")

-- The engine: a neutral press is a NEUTRAL step - no attempt, no points, and NOT
-- a mis-pick.
local neutral = H.practice_neutral_actions("NEUTRAL")
local run = H.new_rotation_run()
local n1 = H.rotation_run_decide(run, "cs", "heal", false, neutral)
eq(n1.outcome, "neutral", "a neutral action is a neutral step")
eq(n1.actual, "heal", "the decision records the cast")
eq(n1.expected, "cs", "the decision records the expectation")
eq(n1.neutral, true, "the decision records that the step was neutral")
eq(H.ROTATION_OUTCOMES.neutral, true, "the neutral outcome class exists")
eq(H.ROTATION_OUTCOME_GRADES.neutral, nil,
    "a neutral step grades nothing (no attempt, no points)")
eq(run.neutral, 1, "the run counts the neutral step")
eq(run.mispicks, 0, "a neutral step is not a mis-pick")
eq(run.correct, 0, "a neutral step is not a correct decision")
eq(run.unknown, 0, "a neutral step is not an unknown")
eq(run.misses, 0, "a neutral step is not a miss")
eq(run.steps, 1, "a neutral step is still a step of the run")
eq(run.finished, false, "the run is not finished by a neutral step")

-- The rotation action is unaffected: the same set published, the wanted action
-- still grades correct.
local n2 = H.rotation_run_decide(run, "cs", "cs", false, neutral)
eq(n2.outcome, "correct", "the rotation action still grades correct")
eq(run.correct, 1, "the run counts the correct decision")
eq(run.neutral, 1, "the neutral tally is untouched by the correct step")
eq(run.mispicks, 0, "the correct step is not a mis-pick")

-- An action that is neither the rotation action nor neutral: a mis-pick (F).
local n3 = H.rotation_run_decide(run, "cs", "food", false, neutral)
eq(n3.outcome, "out_of_order", "an action that is neither rotation nor neutral is a mis-pick")
eq(H.ROTATION_OUTCOME_GRADES.out_of_order, "F", "a mis-pick grades F")
eq(run.mispicks, 1, "the run counts the mis-pick")
eq(run.neutral, 1, "the mis-pick is not a neutral step")

-- A class that publishes no set: every non-rotation press stays a mis-pick.
local plain = H.new_rotation_run()
local plain_decision = H.rotation_run_decide(plain, "cs", "heal", false,
    H.practice_neutral_actions("NOCLASSATALL"))
eq(plain_decision.outcome, "out_of_order",
    "without a published set a neutral action is still a mis-pick")
eq(H.ROTATION_OUTCOME_GRADES[plain_decision.outcome], "F", "and it grades F")
eq(plain.mispicks, 1, "the run counts the mis-pick")
eq(plain.neutral, 0, "the run counts no neutral step")

-- A hold wins over the neutral set (HU-8): the class stated "cast nothing" and
-- the prompt says so - a neutral press must not make the illegal cast free.
local hold_run = H.new_rotation_run()
local hold_decision = H.rotation_run_decide(hold_run, nil, "heal", true, neutral)
eq(hold_decision.outcome, "illegal_cast",
    "a cast during a hold is an illegal cast, neutral or not")
eq(hold_run.mispicks, 1, "the illegal cast counts against the band")
eq(hold_run.neutral, 0, "the illegal cast is not a neutral step")
eq(H.ROTATION_OUTCOME_GRADES.illegal_cast, "F", "the illegal cast grades F")

-- The summary carries the neutral count.
local summary = H.rotation_run_summary(run)
eq(summary.neutral, 1, "the summary counts the neutral steps")
eq(summary.mispicks, 1, "the summary counts the mis-picks")
eq(summary.correct, 1, "the summary counts the correct steps")
eq(summary.grade, "A", "one mis-pick grades A (the neutral step is not one)")

-- A run of nothing but neutral steps has nothing gradeable: it reads UNKNOWN,
-- never a perfect S.
local only_neutral = H.new_rotation_run()
for _ = 1, 3 do
    H.rotation_run_decide(only_neutral, "cs", "heal", false, neutral)
end
local neutral_summary = H.rotation_run_summary(only_neutral)
eq(neutral_summary.grade, nil, "a run with no gradeable step has no grade")
eq(neutral_summary.neutral, 3, "the summary counts the three neutral steps")
eq(neutral_summary.correct, 0, "a neutral step is never a correct decision")

-- Determinism: the same answers give the same run (the engine reads no clock
-- and invents no randomness).
local det_a, det_b = H.new_rotation_run(), H.new_rotation_run()
for _ = 1, 4 do
    H.rotation_run_decide(det_a, "cs", "heal", false, neutral)
    H.rotation_run_decide(det_b, "cs", "heal", false, neutral)
end
eq(H.rotation_run_summary(det_a).neutral, H.rotation_run_summary(det_b).neutral,
    "determinism: identical neutral sequences give identical counts")
eq(H.rotation_run_summary(det_a).grade, H.rotation_run_summary(det_b).grade,
    "determinism: identical neutral sequences give identical grades")

st.NEUTRAL = nil
st.NEUTRALNONE = nil
st.NEUTRALBAD = nil
st.NEUTRALEMPTY = nil
st.NEUTRALFALSE = nil
st.NEUTRALFAMILY = nil
end

neutral_tests()

if failures == 0 then
    print("PASS  practice_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  practice_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
