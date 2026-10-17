-- tests/swing_source_state.lua: offline tests for the WoW Forever swing engine
-- (swing_source.lua). Sandbox-loads the module with fake CallbackHandler / frame /
-- timer / Enum / UnitAttackSpeed stubs and drives the exact event shapes main.lua
-- consumes, so the callback contract, supersession and attack-speed rescale are
-- pinned without a client.
--
-- Sections 8-11 extend the Forever-path hardening for the 1.60.1 release:
--   8. UnitAttackSpeed shapes on a live cycle (nil / zero / throwing / missing
--      reader keep the schedule, never throw).
--   9. Classic families (ERA, WRATH, RETAIL) stay inert even with an approving
--      event probe: the FOREVER family gate dominates the probe.
--  10. Family mapping (project 18, interface 16001 -> FOREVER) plus the C_Spell
--      unknown-id fallback behind the real compat.lua (highest known wins,
--      all-unknown resolves nil so callers keep their rank-1 fallback).
--  11. Enum-absent numeric fallback for the swing-type mapping.
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

-- Fake clock and timer queue -------------------------------------------------------------
local clock = 0
local timers = {}
local function advance(seconds)
    clock = clock + seconds
    local ran = true
    while ran do
        ran = false
        for i = 1, #timers do
            local t = timers[i]
            if t and t.due <= clock then
                timers[i] = nil
                ran = true
                t.fn()
            end
        end
    end
end

-- Fake CallbackHandler registry: Fire records every call and forwards function
-- callbacks as (eventname, ...) like the real CallbackHandler does.
local fired = {}
local registered = {}
local registry = {}
function registry:RegisterCallback(event, cb)
    registered[event] = cb
end
function registry:Fire(event, ...)
    fired[#fired + 1] = { event = event, a = { ... } }
    local cb = registered[event]
    if cb then cb(event, ...) end
end

-- Fake engine frame ----------------------------------------------------------------------
local frame = nil
local frame_events = {}
local function make_frame(events)
    events = events or frame_events
    local f = {}
    function f:RegisterEvent(name) events[#events + 1] = name end
    function f:UnregisterEvent() end
    function f:SetScript(script, fn) self.scripts = self.scripts or {}; self.scripts[script] = fn end
    function f:Hide() end
    return f
end

-- Sandbox -------------------------------------------------------------------------------
local env = {}
for k, v in pairs(_G) do env[k] = v end
env.LibStub = function(major)
    if major == "CallbackHandler-1.0" then
        return { New = function(_, target) return registry end }
    end
    return {}
end
env.CreateFrame = function() frame = make_frame(); return frame end
env.C_Timer = {
    After = function(delay, fn)
        timers[#timers + 1] = { due = clock + delay, fn = fn }
    end,
}
env.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
env.UnitAttackSpeed = function() return 2.6, nil, nil end
env.GetTime = function() return clock end

local st = {
    family = "FOREVER",
    api = { get_time = function() return clock end },
}

local mod = assert(loadfile(ROOT .. "swing_source.lua"))
setfenv(mod, env)
local ok, err = pcall(function() mod("SwedgeTimer", st) end)
check(ok, "swing_source.lua loads under the sandbox (" .. tostring(err) .. ")")

local src = st.swing_source
check(type(src) == "table", "st.swing_source exists")
eq(src.available, true, "available on FOREVER when the event probe is missing")
check(type(frame) == "table", "engine frame created")
check(frame.scripts ~= nil and frame.scripts.OnEvent ~= nil, "engine frame has an OnEvent script")
eq(#frame_events, 4, "engine registers exactly four events")
eq(table.concat(frame_events, ","),
    "PLAYER_SWING,UNIT_ATTACK_SPEED,PLAYER_IN_COMBAT_CHANGED,PLAYER_ENTERING_WORLD",
    "engine registers exactly the four engine events, in order")

local function fire(event, ...)
    frame.scripts.OnEvent(frame, event, ...)
end
local function count_event(name)
    local n = 0
    for i = 1, #fired do
        if fired[i].event == name then n = n + 1 end
    end
    return n
end
local function last_event()
    return fired[#fired]
end

-- 1) PLAYER_SWING => SWING_TIMER_START(speed, expiration, hand) -------------------------
fire("PLAYER_SWING", 2.6, 0)
eq(last_event().event, "SWING_TIMER_START", "PLAYER_SWING fires SWING_TIMER_START")
eq(last_event().a[1], 2.6, "START arg1 is the swing duration")
eq(last_event().a[2], clock + 2.6, "START arg2 is the expiration")
eq(last_event().a[3], "mainhand", "START arg3 is the hand")

local speed, expiration, start_time = src:SwingTimerInfo("mainhand")
eq(speed, 2.6, "SwingTimerInfo speed while swinging")
eq(expiration, 0 + 2.6, "SwingTimerInfo expiration while swinging")
eq(start_time, 0, "SwingTimerInfo start while swinging")

-- 2) A newer swing supersedes the scheduled stop ----------------------------------------
advance(2.0) -- t=2.0
fire("PLAYER_SWING", 2.6, 0) -- second cycle: expiration 4.6, stop due 4.7
eq(count_event("SWING_TIMER_START"), 2, "second swing fires a second START")
advance(0.8) -- t=2.8: first stop timer (due 2.7) runs, must be a no-op
eq(count_event("SWING_TIMER_STOP"), 0, "superseded stop timer does not fire STOP")
advance(2.0) -- t=4.8: second stop timer (due 4.7) runs for the live cycle
eq(count_event("SWING_TIMER_STOP"), 1, "current stop timer fires STOP once")

speed, expiration, start_time = src:SwingTimerInfo("mainhand")
eq(speed, 1, "idle SwingTimerInfo uses the stub shape (speed 1)")
eq(expiration, clock + 1, "idle SwingTimerInfo expiration is now + 1")
eq(start_time, clock, "idle SwingTimerInfo start is now")

-- 3) UNIT_ATTACK_SPEED rescales the REMAINING time proportionally -----------------------
fire("PLAYER_SWING", 2.6, 0) -- t=4.8: expiration 7.4
advance(1.2) -- t=6.0
env.UnitAttackSpeed = function() return 1.3 end
fire("UNIT_ATTACK_SPEED")
eq(last_event().event, "SWING_TIMER_UPDATE", "UNIT_ATTACK_SPEED fires SWING_TIMER_UPDATE")
eq(last_event().a[1], 1.3, "UPDATE arg1 is the new speed")
eq(last_event().a[2], 6.0 + (7.4 - 6.0) * (1.3 / 2.6), "UPDATE arg2 scales the remaining time")
eq(last_event().a[3], "mainhand", "UPDATE arg3 is the hand")

-- 4) Leaving combat ends the cycle exactly once -----------------------------------------
fire("PLAYER_IN_COMBAT_CHANGED", false)
eq(last_event().event, "SWING_TIMER_STOP", "combat exit fires STOP")
eq(last_event().a[1], "mainhand", "combat-exit STOP carries the hand")
eq(count_event("SWING_TIMER_STOP"), 2, "combat-exit STOP is the second STOP overall")
advance(2.0) -- t=8.0: the cycle's old stop timer fires against a cleared cycle
eq(count_event("SWING_TIMER_STOP"), 2, "cleared cycle does not produce a second STOP")

-- 5) SWING_TIMER_INFO_INITIALIZED fires once per session --------------------------------
fire("PLAYER_ENTERING_WORLD")
fire("PLAYER_ENTERING_WORLD")
eq(count_event("SWING_TIMER_INFO_INITIALIZED"), 1, "INFO_INITIALIZED fires exactly once")

-- 6) Swing type mapping and malformed payloads ------------------------------------------
fire("PLAYER_SWING", 2.0, 1)
eq(last_event().a[3], "offhand", "swing type 1 maps to offhand")
fire("PLAYER_SWING", 2.0, 2)
eq(last_event().a[3], "ranged", "swing type 2 maps to ranged")
local before = #fired
fire("PLAYER_SWING", 2.0, 9)
eq(#fired, before, "unknown swing type is ignored")
fire("PLAYER_SWING", 0, 0)
eq(#fired, before, "zero duration is ignored")
fire("PLAYER_SWING", "x", 0)
eq(#fired, before, "non-numeric duration is ignored")

-- 7) Event probe gating ------------------------------------------------------------------
-- swing_source.lua gates itself on C_EventUtils.IsEventValid (falling back to the FOREVER
-- family when the probe is absent). Two extra sandbox loads pin both probe directions:
-- rejected events must leave the engine inert, and a selective probe must register only
-- the approved event.
local function load_with_probe(probe)
    local probe_frames, probe_events = 0, {}
    local env2 = {}
    for k, v in pairs(_G) do env2[k] = v end
    env2.LibStub = function(major)
        if major == "CallbackHandler-1.0" then
            return { New = function()
                return { RegisterCallback = function() end,
                         UnregisterCallback = function() end,
                         Fire = function() end }
            end }
        end
        return {}
    end
    env2.CreateFrame = function()
        probe_frames = probe_frames + 1
        return make_frame(probe_events)
    end
    env2.C_Timer = { After = function() end }
    env2.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
    env2.UnitAttackSpeed = function() return 2.6 end
    env2.GetTime = function() return 0 end
    env2.C_EventUtils = { IsEventValid = probe }
    local st2 = { family = "FOREVER", api = { get_time = function() return 0 end } }
    local mod2 = assert(loadfile(ROOT .. "swing_source.lua"))
    setfenv(mod2, env2)
    local loaded, err2 = pcall(function() mod2("SwedgeTimer", st2) end)
    return st2, probe_frames, probe_events, loaded, err2
end

local st_reject, reject_frames, reject_events, reject_ok, reject_err =
    load_with_probe(function() return false end)
check(reject_ok, "probe-reject sandbox: swing_source.lua loads (" .. tostring(reject_err) .. ")")
eq(st_reject.swing_source.available, false, "probe rejecting PLAYER_SWING: engine unavailable")
eq(reject_frames, 0, "probe-reject: no engine frame created")
eq(#reject_events, 0, "probe-reject: no event registered")

local st_sel, sel_frames, sel_events = load_with_probe(function(name)
    return name == "PLAYER_SWING"
end)
eq(st_sel.swing_source.available, true, "probe approving PLAYER_SWING: engine available")
eq(sel_frames, 1, "selective probe: engine frame created")
eq(table.concat(sel_events, ","), "PLAYER_SWING",
    "selective probe: only the approved event is registered")

-- 8) UnitAttackSpeed shapes on a live cycle -------------------------------------------
-- main.lua:654 check_weapons reads through the compat wrapper (nil-safe via or 0),
-- but this engine reads the raw global. Every non-usable shape - all-nil (weapon
-- removed), all-zero, a throwing reader, a missing reader - must keep the in-flight
-- cycle on its scheduled speed instead of throwing or rescaling.
fire("PLAYER_SWING", 2.6, 0) -- fresh mainhand cycle, expiration clock + 2.6
local shape_speed, shape_expiration = src:SwingTimerInfo("mainhand")
eq(shape_speed, 2.6, "attack-speed shapes: the cycle starts at the payload speed")
local updates_before_shapes = count_event("SWING_TIMER_UPDATE")
local function check_shape_keeps_schedule(label)
    local s, e = src:SwingTimerInfo("mainhand")
    eq(s, 2.6, "attack-speed shapes: " .. label .. " keeps the scheduled speed")
    eq(e, shape_expiration, "attack-speed shapes: " .. label .. " keeps the scheduled expiration")
    eq(count_event("SWING_TIMER_UPDATE"), updates_before_shapes,
        "attack-speed shapes: " .. label .. " fires no update")
end

env.UnitAttackSpeed = function() return nil end
check(pcall(fire, "UNIT_ATTACK_SPEED"), "attack-speed shapes: an all-nil read does not throw")
check_shape_keeps_schedule("an all-nil read")

env.UnitAttackSpeed = function() return 0, 0, 0 end
check(pcall(fire, "UNIT_ATTACK_SPEED"), "attack-speed shapes: an all-zero read does not throw")
check_shape_keeps_schedule("an all-zero read")

env.UnitAttackSpeed = function() error("attack-speed reader threw") end
check(pcall(fire, "UNIT_ATTACK_SPEED"), "attack-speed shapes: a throwing reader does not throw")
check_shape_keeps_schedule("a throwing reader")

env.UnitAttackSpeed = nil
check(pcall(fire, "UNIT_ATTACK_SPEED"), "attack-speed shapes: a missing reader does not throw")
check_shape_keeps_schedule("a missing reader")

env.UnitAttackSpeed = function() return 2.6, nil, nil end -- restore the honest partial shape

-- 9) Classic families stay inert ------------------------------------------------------
-- The engine must report itself unavailable on every non-FOREVER family however the
-- event probe answers: the family gate dominates, so a classic client never arms a
-- second engine next to the vendored library (or the inert stand-in on Retail).
local function load_with_family(family, probe)
    local inert_frames, inert_events = 0, {}
    local envF = {}
    for k, v in pairs(_G) do envF[k] = v end
    envF.LibStub = function(major)
        if major == "CallbackHandler-1.0" then
            return { New = function()
                return { RegisterCallback = function() end,
                         UnregisterCallback = function() end,
                         Fire = function() end }
            end }
        end
        return {}
    end
    envF.CreateFrame = function()
        inert_frames = inert_frames + 1
        return make_frame(inert_events)
    end
    envF.C_Timer = { After = function() end }
    envF.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
    envF.UnitAttackSpeed = function() return 2.6 end
    envF.GetTime = function() return 0 end
    if probe then
        envF.C_EventUtils = { IsEventValid = probe }
    end
    local stF = { family = family, api = { get_time = function() return 0 end } }
    local modF = assert(loadfile(ROOT .. "swing_source.lua"))
    setfenv(modF, envF)
    local loaded, errF = pcall(function() modF("SwedgeTimer", stF) end)
    return stF, inert_frames, inert_events, loaded, errF
end

for _, family in ipairs({ "WRATH", "ERA", "RETAIL" }) do
    local stF, framesF, eventsF, loadedF, errF = load_with_family(family, nil)
    check(loadedF, family .. " sandbox: swing_source.lua loads (" .. tostring(errF) .. ")")
    eq(stF.swing_source.available, false, family .. ": engine unavailable without a probe")
    eq(framesF, 0, family .. ": no engine frame created")
    eq(#eventsF, 0, family .. ": no event registered")
end
do
    -- An approving probe must not arm the engine off-family either.
    local stW, framesW, eventsW, loadedW, errW = load_with_family("WRATH", function() return true end)
    check(loadedW, "wrath probe-approving sandbox: swing_source.lua loads (" .. tostring(errW) .. ")")
    eq(stW.swing_source.available, false, "wrath: an approving probe still leaves the engine unavailable")
    eq(framesW, 0, "wrath: an approving probe still creates no engine frame")
    eq(#eventsW, 0, "wrath: an approving probe still registers no event")
end

-- 10) Family mapping and the C_Spell unknown-id fallback ------------------------------
-- swing_source.lua trusts st.family from compat.lua, so the 16001 -> FOREVER mapping
-- (interface fallback and project 18) is pinned here against the real compat.lua,
-- together with the rank-resolution fallback the Forever spell DB must satisfy: the
-- highest known id wins, and an all-unknown table resolves nil so every caller keeps
-- its rank-1 fallback instead of prompting an unknown spell.
local function load_compat(envC)
    local stC = {}
    local modC = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(modC, envC)
    local loaded, errC = pcall(function() modC("SwedgeTimer", stC) end)
    return stC, loaded, errC
end
local function compat_env(opts)
    opts = opts or {}
    local e = {}
    for k, v in pairs(_G) do e[k] = v end
    e._G = e -- compat.lua reads several legacy globals through _G
    e.WOW_PROJECT_CLASSIC = 2
    e.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    e.WOW_PROJECT_WRATH_CLASSIC = 11
    e.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    e.WOW_PROJECT_MISTS_CLASSIC = 19
    e.WOW_PROJECT_MAINLINE = 1
    e.WOW_PROJECT_CAMELOT = 18
    e.WOW_PROJECT_ID = opts.project
    if opts.interface then
        e.GetBuildInfo = function() return "1.60.1", "00000", "today", opts.interface end
    end
    if opts.spell_db then
        local db = opts.spell_db
        e.C_Spell = {
            GetSpellInfo = function(id)
                if db[id] then
                    return { name = "Spell " .. tostring(id), originalIconID = 1,
                             castTime = 0, minRange = 0, maxRange = 0, spellID = id }
                end
                return nil
            end,
        }
    end
    return e
end

do
    local stF, loadedF, errF = load_compat(compat_env({ project = 18,
        spell_db = { [25286] = true, [9881] = true } }))
    check(loadedF, "forever compat sandbox: compat.lua loads (" .. tostring(errF) .. ")")
    eq(stF.family, "FOREVER", "forever: project 18 maps to FOREVER")
    eq(stF.is_mainline, true, "forever: a Mainline-code client")
    eq(stF.gcd_probe_spell_id, 61304, "forever: gcd probe is 61304")
    eq(stF.api.get_family_spell_id({ 47450, 30324, 29707, 25286, 78 }), 25286,
        "forever C_Spell DB: HS resolves to the highest known id")
    eq(stF.api.get_family_spell_id({ [25286] = true, [47450] = true }), 25286,
        "forever C_Spell DB: lookup-table form resolves to the highest known id")
    eq(stF.api.get_family_spell_id({ 47450, 26996 }), nil,
        "forever C_Spell DB: all-unknown ids resolve nil (callers keep rank-1)")
end
do
    local stF, loadedF, errF = load_compat(compat_env({ interface = 16001 }))
    check(loadedF, "16001 compat sandbox: compat.lua loads (" .. tostring(errF) .. ")")
    eq(stF.family, "FOREVER", "legacy 16001: interface fallback maps to FOREVER, not ERA")
    eq(stF.interface_number, 16001, "legacy 16001: interface number recorded")
    eq(stF.is_mainline, true, "legacy 16001: mainline-code client")
    eq(stF.gcd_probe_spell_id, 61304, "legacy 16001: gcd probe is 61304")
end
do
    local stE, loadedE, errE = load_compat(compat_env({ interface = 11509 }))
    check(loadedE, "era compat sandbox: compat.lua loads (" .. tostring(errE) .. ")")
    eq(stE.family, "ERA", "era 11509: interface fallback still maps to ERA")
end
do
    local stW, loadedW, errW = load_compat(compat_env({ project = 11 }))
    check(loadedW, "wrath compat sandbox: compat.lua loads (" .. tostring(errW) .. ")")
    eq(stW.family, "WRATH", "wrath: project 11 still maps to WRATH")
end

-- 11) Enum-absent numeric fallback -----------------------------------------------------
-- hand_for_swing_type prefers Enum.PlayerSwingType but mirrors its MainHand = 0 /
-- OffHand = 1 / Ranged = 2 values numerically, so clients without the Enum table
-- still time every hand.
do
    local enum_keep = env.Enum
    env.Enum = nil
    fire("PLAYER_SWING", 2.0, 0)
    eq(last_event().a[3], "mainhand", "no Enum: swing type 0 still maps to mainhand")
    fire("PLAYER_SWING", 2.0, 1)
    eq(last_event().a[3], "offhand", "no Enum: swing type 1 still maps to offhand")
    fire("PLAYER_SWING", 2.0, 2)
    eq(last_event().a[3], "ranged", "no Enum: swing type 2 still maps to ranged")
    local before_fallback = #fired
    fire("PLAYER_SWING", 2.0, 9)
    eq(#fired, before_fallback, "no Enum: unknown swing type is still ignored")
    fire("PLAYER_SWING", 2.0, "0")
    eq(#fired, before_fallback, "no Enum: non-numeric swing type is still ignored")
    env.Enum = enum_keep
end

if failures == 0 then
    print("PASS  swing_source_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  swing_source_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
