-- tests/engine_matrix_state.lua: the cross-branch swing-engine matrix.
--
-- One row per shipped client branch, each run against the REAL compat.lua family
-- detection, the REAL swing_source.lua (its own availability probe, event registration
-- and callback payloads) and the REAL main.lua selection ladder:
--
--   branch      WOW_PROJECT_ID / iface   toc ships lib?   engine chosen
--   classic_era 2  / 11509               yes             vendored-lib
--   anniversary 5  / 20506               yes             vendored-lib
--   titan      11  / 38002               yes             vendored-lib
--   forever    18  / 16001               no (_Mainline)  forever-source
--   retail      1  / 120100              no (_Mainline)  inert-standin
--
-- Cross-client facts cited from /home/sam/wow-ui-source (shell-read, 2026-10-25):
--   * PLAYER_SWING exists ONLY on origin/forever, documented at
--     Interface/AddOns/Blizzard_APIDocumentationGenerated/SwingTimerDocumentation.lua:43-52
--     (payload swingDuration:number, swingType:PlayerSwingType) with the enum at :71-82
--     (MainHand=0, OffHand=1, Ranged=2), and consumed by Blizzard's own bar at
--     Interface/AddOns/Blizzard_SwingTimer/Blizzard_SwingTimer.lua:141-161.
--   * `live` and the three classic branches have NO PLAYER_SWING string anywhere under
--     Interface and no Blizzard_SwingTimer addon at all (git grep / git ls-tree).
--     So the classic line must keep the vendored library and Retail must stay inert.
--
-- This suite does not duplicate the dispatcher pins (tests/main_init_state.lua owns the
-- SWING_TIMER_* handler shape, tests/real_wire_state.lua owns the real-vendored-library
-- wire): it pins WHICH engine each branch selects, WHICH events that engine registers,
-- and the payload shape it fires into main.lua.
--
-- Run from the repo root: lua5.1 tests/engine_matrix_state.lua  (any cwd works).

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

--=========================================================================================
-- The branch table
--=========================================================================================
-- event_probe: what the branch's C_EventUtils.IsEventValid answers. Forever is the only
-- branch where the engine events are valid; the others answer false for PLAYER_SWING
-- (the event does not exist there at all).
local BRANCHES = {
    {
        tag = "era", project = 2, interface = 11509, family = "ERA",
        lib_present = true, engine = "vendored-lib", mainline = false,
        event_probe = function() return false end,
    },
    {
        tag = "anniversary", project = 5, interface = 20506, family = "TBC",
        lib_present = true, engine = "vendored-lib", mainline = false,
        event_probe = function() return false end,
    },
    {
        tag = "titan", project = 11, interface = 38002, family = "WRATH",
        lib_present = true, engine = "vendored-lib", mainline = false,
        event_probe = function() return false end,
    },
    {
        tag = "forever", project = 18, interface = 16001, family = "FOREVER",
        lib_present = false, engine = "forever-source", mainline = true,
        event_probe = function(name)
            return name == "PLAYER_SWING"
                or name == "UNIT_ATTACK_SPEED"
                or name == "WEAPON_SLOT_CHANGED"
                or name == "PLAYER_IN_COMBAT_CHANGED"
                or name == "PLAYER_ENTERING_WORLD"
        end,
    },
    {
        tag = "retail", project = 1, interface = 120100, family = "RETAIL",
        lib_present = false, engine = "inert-standin", mainline = true,
        event_probe = function() return false end,
    },
}

--=========================================================================================
-- Sandbox
--=========================================================================================
-- One throwaway client per boot. Loads compat.lua -> swing_source.lua -> main.lua in
-- order (the _Mainline TOC order), exactly like smoke.lua's boot_main discipline:
-- nothing in the addon is touched.
local function boot(row)
    local b = {
        frames = {},
        events = {},        -- non-unit Registrations on the engine frame
        unit_events = {},   -- RegisterUnitEvent captures
        fired = {},         -- CallbackHandler Fire log
        registered = {},    -- event -> callback (main.lua registers in OnInitialize only)
        clock = 100,
    }

    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.WOW_PROJECT_ID = row.project
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_CAMELOT = 18
    env.GetBuildInfo = function() return "test", "00000", "today", row.interface end
    env.GetTime = function() return b.clock end
    env.GetTimePreciseSec = function() return b.clock end
    env.UnitClass = function() return "Paladin", "PALADIN" end
    env.UnitAttackSpeed = function() return 2.6, 1.8, 3.0 end
    env.UnitRangedDamage = function() return 3.0 end
    env.C_EventUtils = { IsEventValid = row.event_probe }
    env.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
    env.C_Timer = {
        After = function() end,
        NewTimer = function() return { Cancel = function() end } end,
    }

    -- The engine frame: capture registration order, never execute a client call.
    local function make_frame()
        local f = { scripts = {} }
        function f:RegisterEvent(name) b.events[#b.events + 1] = name end
        function f:RegisterUnitEvent(name, unit)
            b.events[#b.events + 1] = name
            b.unit_events[#b.unit_events + 1] = { name = name, unit = unit }
        end
        function f:UnregisterEvent(name) end
        function f:IsEventRegistered(name) return false end
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:Hide() end
        function f:Show() end
        return f
    end
    env.CreateFrame = function()
        local f = make_frame()
        b.frames[#b.frames + 1] = f
        return f
    end

    local registry = {
        New = function(_, target)
            return {
                RegisterCallback = function(_, event, cb) b.registered[event] = cb end,
                UnregisterCallback = function() end,
                Fire = function(_, event, ...)
                    b.fired[#b.fired + 1] = { event = event, args = { ... }, n = select("#", ...) }
                    local cb = b.registered[event]
                    if cb then cb(event, ...) end
                end,
            }
        end,
    }
    local stub = { RegisterCallback = function() end, UnregisterCallback = function() end }
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { NewAddon = function() return b.ST end }
        elseif major == "CallbackHandler-1.0" then
            return registry
        elseif major == "LibClassicSwingTimerAPI" then
            return row.lib_present and stub or nil
        end
        return stub
    end

    b.ST = {}
    b.st = { utils = { print_msg = function() end } }
    local modules = { "compat.lua", "swing_source.lua", "main.lua" }
    for i = 1, #modules do
        local chunk = assert(loadfile(ROOT .. modules[i]), "cannot load " .. modules[i])
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "SwedgeTimer", b.st)
        check(ok, row.tag .. ": " .. modules[i] .. " loads (" .. tostring(err) .. ")")
    end
    b.env = env
    -- The engine frame is the one swing_source creates for itself; main.lua creates none
    -- at load. Mark it by the name argument the module passes.
    b.engine_frame = b.frames[#b.frames]
    return b
end

-- Callback helpers over one boot's Fire log.
local function count_fired(b, event)
    local n = 0
    for i = 1, #b.fired do
        if b.fired[i].event == event then n = n + 1 end
    end
    return n
end
local function last_fired(b)
    return b.fired[#b.fired]
end

--=========================================================================================
-- 1) Family detection + engine selection, one row per branch
--=========================================================================================
local boots = {}
for i = 1, #BRANCHES do
    local row = BRANCHES[i]
    local b = boot(row)
    boots[row.tag] = b
    eq(b.st.family, row.family, row.tag .. ": compat family is " .. row.family)
    eq(b.st.is_mainline, row.mainline, row.tag .. ": is_mainline = " .. tostring(row.mainline))
    eq(b.ST.swing_engine, row.engine, row.tag .. ": main.lua selects " .. row.engine)
    eq(b.ST.addon_version ~= nil, true, row.tag .. ": main.lua loaded its version")
end

-- 1a) The engine's own availability gate, per branch. This is the value main.lua reads.
eq(boots.era.st.swing_source.available, false, "era: swing_source unavailable")
eq(boots.anniversary.st.swing_source.available, false, "anniversary: swing_source unavailable")
eq(boots.titan.st.swing_source.available, false, "titan: swing_source unavailable")
eq(boots.forever.st.swing_source.available, true, "forever: swing_source available")
eq(boots.retail.st.swing_source.available, false, "retail: swing_source unavailable")

-- 1b) The TOC contract the matrix depends on: only _Mainline omits the vendored library.
-- (toc_check.lua owns the full TOC pins; this keeps the matrix's premise explicit.)
do
    local function toc_has(path, needle)
        local f = assert(io.open(ROOT .. path, "r"), "cannot read " .. path)
        local text = f:read("*a")
        f:close()
        return text:find(needle, 1, true) ~= nil
    end
    local LIB = "Libs\\LibClassicSwingTimerAPI\\LibClassicSwingTimerAPI.lua"
    eq(toc_has("SwedgeTimer_Vanilla.toc", LIB), true, "toc: _Vanilla ships the classic library")
    eq(toc_has("SwedgeTimer_TBC.toc", LIB), true, "toc: _TBC ships the classic library")
    eq(toc_has("SwedgeTimer_Wrath.toc", LIB), true, "toc: _Wrath ships the classic library")
    eq(toc_has("SwedgeTimer_Mainline.toc", LIB), false, "toc: _Mainline omits the classic library")
    eq(toc_has("SwedgeTimer_Mainline.toc", "swing_source.lua"), true,
        "toc: _Mainline ships the native swing source")
end

--=========================================================================================
-- 2) Event registration, per branch
--=========================================================================================
-- The classic line and Retail have no PLAYER_SWING: their engine is the vendored library
-- (classic) or the inert stand-in (Retail), so swing_source must create no frame and
-- register no event, however the probe answers.
for _, tag in ipairs({ "era", "anniversary", "titan", "retail" }) do
    local b = boots[tag]
    eq(#b.frames, 0, tag .. ": swing_source created no engine frame")
    eq(#b.events, 0, tag .. ": swing_source registered no event")
end

do
    local b = boots.forever
    eq(#b.frames, 1, "forever: swing_source created exactly one engine frame")
    eq(table.concat(b.events, ","),
        "PLAYER_SWING,UNIT_ATTACK_SPEED,WEAPON_SLOT_CHANGED,PLAYER_IN_COMBAT_CHANGED,PLAYER_ENTERING_WORLD",
        "forever: the engine registers exactly its five cycle events, in order")
    eq(#b.unit_events, 1, "forever: exactly one event uses the unit-filtered registration")
    eq(b.unit_events[1].name, "UNIT_ATTACK_SPEED", "forever: UNIT_ATTACK_SPEED is unit-filtered")
    eq(b.unit_events[1].unit, "player", "forever: the unit filter is the player")
    -- Omission proof, verified against Blizzard's own arm set: target/range are display
    -- only (SwingTimerDocumentation.lua:54-65; Blizzard_SwingTimer.lua:149-150,156-160)
    -- and can never start, retime or end a cycle, so registering them would be dead
    -- wiring. The addon reads range from main.lua's exact-yard poll instead.
    local joined = table.concat(b.events, ",")
    eq(joined:find("PLAYER_TARGET_CHANGED", 1, true), nil,
        "forever: PLAYER_TARGET_CHANGED is not registered (display-only arm)")
    eq(joined:find("PLAYER_SWING_RANGE_UPDATE", 1, true), nil,
        "forever: PLAYER_SWING_RANGE_UPDATE is not registered (display-only arm)")
end

--=========================================================================================
-- 3) Payload shape: PLAYER_SWING -> the SWING_TIMER_* surface main.lua consumes
--=========================================================================================
-- main.lua's handlers take speed-first (main.lua:1176-1196 strips only a leading
-- "player"/"target" unit id from the classic library's legacy re-fire). The source must
-- therefore fire (speed, expiration, hand) for START/UPDATE and (hand) for STOP.
do
    local b = boots.forever
    local fire = function(...) b.engine_frame.scripts.OnEvent(b.engine_frame, ...) end

    -- PLAYER_SWING(swingDuration, swingType) per SwingTimerDocumentation.lua:43-52.
    fire("PLAYER_SWING", 2.6, 0)
    local start = last_fired(b)
    eq(start.event, "SWING_TIMER_START", "forever payload: PLAYER_SWING fires SWING_TIMER_START")
    eq(start.n, 3, "forever payload: START carries exactly three arguments")
    eq(start.args[1], 2.6, "forever payload: START arg1 is the swing duration (speed-first)")
    eq(start.args[2], b.clock + 2.6, "forever payload: START arg2 is the expiration")
    eq(start.args[3], "mainhand", "forever payload: enum MainHand=0 maps to mainhand")

    fire("PLAYER_SWING", 2.0, 1)
    eq(last_fired(b).args[3], "offhand", "forever payload: enum OffHand=1 maps to offhand")
    fire("PLAYER_SWING", 3.0, 2)
    eq(last_fired(b).args[3], "ranged", "forever payload: enum Ranged=2 maps to ranged")

    local before = #b.fired
    fire("PLAYER_SWING", 3.0, 9)
    eq(#b.fired, before, "forever payload: an unknown swing type is ignored")
    fire("PLAYER_SWING", 0, 0)
    eq(#b.fired, before, "forever payload: a zero duration is ignored")
    fire("PLAYER_SWING", "x", 0)
    eq(#b.fired, before, "forever payload: a non-numeric duration is ignored")

    -- UNIT_ATTACK_SPEED(unitTarget) per UnitDocumentation.lua:4143-4151.
    b.env.UnitAttackSpeed = function() return 1.3, 1.8, 3.0 end
    fire("UNIT_ATTACK_SPEED", "player")
    local update = last_fired(b)
    eq(update.event, "SWING_TIMER_UPDATE", "forever payload: UNIT_ATTACK_SPEED fires UPDATE")
    eq(update.args[1], 1.3, "forever payload: UPDATE arg1 is the new speed")
    eq(update.args[3], "mainhand", "forever payload: UPDATE arg3 is the hand")

    -- PLAYER_IN_COMBAT_CHANGED(inCombat) per PlayerScriptDocumentation.lua:1861-1869.
    -- Three hands are live here (mh/oh/ranged): combat exit STOPs each, hand-only.
    fire("PLAYER_IN_COMBAT_CHANGED", false)
    local stops = {}
    for i = 1, #b.fired do
        if b.fired[i].event == "SWING_TIMER_STOP" then stops[#stops + 1] = b.fired[i] end
    end
    eq(#stops, 3, "forever payload: combat exit STOPs every live hand")
    eq(stops[1].args[1], "mainhand", "forever payload: the first STOP names the mainhand")
    eq(stops[2].args[1], "offhand", "forever payload: the second STOP names the offhand")
    eq(stops[3].args[1], "ranged", "forever payload: the third STOP names the ranged hand")
    eq(stops[1].n, 1, "forever payload: STOP carries the hand only")

    -- PLAYER_ENTERING_WORLD: one INFO_INITIALIZED per session, no arguments.
    local info_before = count_fired(b, "SWING_TIMER_INFO_INITIALIZED")
    fire("PLAYER_ENTERING_WORLD")
    eq(count_fired(b, "SWING_TIMER_INFO_INITIALIZED"), info_before + (info_before == 0 and 1 or 0),
        "forever payload: world entry reports INFO_INITIALIZED once")
    eq(last_fired(b).event, "SWING_TIMER_INFO_INITIALIZED",
        "forever payload: INFO_INITIALIZED is the world-entry event")
    eq(last_fired(b).n, 0, "forever payload: INFO_INITIALIZED carries no arguments")
end

--=========================================================================================
-- 4) The probe gates, per branch (mutation anchors)
--=========================================================================================
-- 4a) A FOREVER client whose probe rejects PLAYER_SWING must not arm the engine.
do
    local row = {
        tag = "forever-probe-reject", project = 18, interface = 16001, family = "FOREVER",
        lib_present = false, engine = "inert-standin", mainline = true,
        event_probe = function() return false end,
    }
    local b = boot(row)
    eq(b.st.family, "FOREVER", "probe-reject: still the Forever family")
    eq(b.st.swing_source.available, false, "probe-reject: the engine is unavailable")
    eq(b.ST.swing_engine, "inert-standin", "probe-reject: main.lua falls back to inert")
    eq(#b.frames, 0, "probe-reject: no engine frame is created")
end

-- 4b) A classic client whose probe approves PLAYER_SWING still must not arm it: the
-- family gate dominates (HU-31 keeps the classic line on the vendored library).
do
    local row = {
        tag = "era-probe-approve", project = 2, interface = 11509, family = "ERA",
        lib_present = true, engine = "vendored-lib", mainline = false,
        event_probe = function() return true end,
    }
    local b = boot(row)
    eq(b.st.swing_source.available, false, "probe-approve: a classic client stays inert")
    eq(#b.frames, 0, "probe-approve: no engine frame is created")
    eq(b.ST.swing_engine, "vendored-lib", "probe-approve: the vendored library still wins")
end

-- 4c) The interface-only Forever mapping (no WOW_PROJECT_ID): 1.60.x must select the
-- source, not the classic library (main.lua's ladder depends on compat's family).
do
    local row = {
        tag = "forever-interface", project = nil, interface = 16001, family = "FOREVER",
        lib_present = false, engine = "forever-source", mainline = true,
        event_probe = BRANCHES[4].event_probe,
    }
    local b = boot(row)
    eq(b.st.family, "FOREVER", "interface-only 16001: compat maps to FOREVER")
    eq(b.ST.swing_engine, "forever-source", "interface-only 16001: the source is selected")
    eq(#b.frames, 1, "interface-only 16001: the engine frame exists")
end

--=========================================================================================
-- Non-vacuity floor
--=========================================================================================
check(checks >= 60, "non-vacuity floor: the matrix exercised at least 60 checks")

if failures == 0 then
    print("PASS  engine_matrix_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  engine_matrix_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
