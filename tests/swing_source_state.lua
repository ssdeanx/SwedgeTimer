-- tests/swing_source_state.lua: offline tests for the WoW Forever swing engine
-- (swing_source.lua). Sandbox-loads the module with fake CallbackHandler / frame /
-- timer / Enum / UnitAttackSpeed stubs and drives the exact event shapes main.lua
-- consumes, so the callback contract, supersession and attack-speed rescale are
-- pinned without a client.
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
local function make_frame()
    local f = {}
    function f:RegisterEvent(name) frame_events[#frame_events + 1] = name end
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
check(frame_events[1] ~= nil, "engine registers its events")

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

if failures == 0 then
    print("PASS  swing_source_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  swing_source_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
