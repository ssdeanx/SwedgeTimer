-- tests/real_wire_state.lua: end-to-end swing-wire proofs over the REAL stack.
--
-- Assembly, all REAL and unmodified (HU-25 route, desks/swing-wire-hunt2 spec 3):
-- Lua 5.1 sandbox, scripted WoW API (event bus + manual C_Timer clock), the REAL
-- LibStub (Libs/LibStub/LibStub.lua, per-sandbox instance), the SHIPPED v7
-- CallbackHandler-1.0, the REAL vendored LibClassicSwingTimerAPI.lua, the REAL
-- main.lua init/reg/dispatcher/handler path (via compat.lua + utils.lua + guard.lua,
-- the same load order as the TOC), with stubbed FRAMES and stubbed non-swing
-- libraries (Ace*, LibRangeCheck-2.0, LibLatencyMonitor, LibGlobalCooldown).
-- No fixture answers in the lib's shape: every swing number the app seeds from or
-- reacts to comes out of the real lib's tables and timers.
--
-- Legs per profile (HU-31 scope: classic_era, classic_anniversary, titanforge
-- (WotLK-line, interface 38002 - Titanforge-shaped, not generic Wrath);
-- Anniversary =5 with LE_EXPANSION_LEVEL_CURRENT=1 AND a nil variant - the
-- runtime value is binary-provided and unknowable offline; Titanforge =11/2/
-- 38002; Forever =18/interface 16001, which loads the REAL swing_source.lua
-- instead of the vendored lib and drives the REAL shipped v7 registry into
-- the REAL main.lua dispatcher; Retail =1/interface 120100, which loads NO
-- swing engine at all - the inert stand-in must stay silent):
--   Era happy:        ADDON_LOADED builds lib units; PEW fires INFO_INITIALIZED
--                     (app-observed, stl_ready) while init still waits for LRC;
--                     LRC completes init; the six regs land IN THE LIB's v7
--                     registry object (identity, not a counter); CLEU
--                     SWING_DAMAGE advances mh (engine_dead=false); SUCCEEDED(75)
--                     + autorepeat advances ranged.
--   Anniversary(1):   same drive, melee + ranged advance (the conditional wire).
--   Titanforge:       same drive on the Wrath tables (SUCCEEDED(75) also resets
--                     melee there - asserted only where pinned); melee + ranged
--                     advance.
--   TBC/Wrath drivers: lone SUCCEEDED(75) advances ranged identically on Era,
--                     anniv(1) and titan (agreement: the SUCCEEDED path has no
--                     family gate, lib:600-606); CAST_START drives an Era ranged
--                     UPDATE but leaves anniv(1)/titan untouched (isClassic
--                     gate, lib:456); FAILED_QUIET sets the Era 0.5s window
--                     (UPDATE) but leaves anniv(1)/titan untouched (isClassic
--                     gate, lib:772).
--   Lifecycle (Era/Anniversary/Titanforge, in that priority order):
--                     mainhand START -> clock past expiry -> hand-only STOP
--                     (is_full follows); offhand START -> UNIT_ATTACK_SPEED
--                     UPDATE -> hand-only STOP -> is_full, on a two-speed
--                     UnitAttackSpeed fixture (the default fixture returns no
--                     offhand weapon, so the offhand was never driven before).
--                     The STOP legs are the first real-registry STOP coverage:
--                     a dispatcher regression eating hand-only STOPs used to
--                     stay green.
--   Reset (Era/Anniversary/Titanforge): after STOP -> full, the next swing
--                     re-STARTs the hand (start re-anchors, is_full clears,
--                     fresh expiry) - a stale freeze breaks these legs.
--                     Cross-hand isolation rides along (a START on one hand
--                     never moves the other two anchors).
--   Fallback driver (app-side UNIT_SPELLCAST_SUCCEEDED -> the engine lane's
--                     maybe_drive_ranged_fallback): silent-engine drive + full
--                     STOP -> full -> re-START (anniv-nil, where the lib is
--                     silent); suppression on a live engine (era); convergence
--                     into exactly one STOP; inert on retail/forever (HU-31);
--                     auto-repeat + spell-id gates.
--   MISSED routing (Era/Anniversary/Titanforge): SWING_MISSED lands on
--                     mainhand vs offhand by its offhand slot (lib:397-401);
--                     all pinned as PASS.
--   PARRY / EXTRA_ATTACKS: EXPECTED-FAIL xfail (same mechanism as D2), pending
--                     HU-29 - the parry-haste arm (lib:415) is unreachable
--                     behind the generic SWING_MISSED catch (lib:397), and the
--                     lib has no SPELL_EXTRA_ATTACKS handler at all. Never pinned
--                     as PASS. Era-only (the dead arms are family-independent).
--   Forever joint (own-API path - no classic-lib behavior pinned here):
--                     REAL swing_source.lua Fire(speed, expiry, hand) through
--                     the REAL shipped v7 into the REAL dispatcher into bar
--                     state: idle nil-shape seed, mh START -> UPDATE -> hand-only
--                     STOP -> is_full, oh START -> hand-only STOP -> is_full; the
--                     six regs land in the source's v7 registry object (identity).
--   Retail silent (own-API path - no classic-lib behavior pinned here):
--                     no engine loads; the inert stand-in reports ready, init
--                     completes on LRC with exactly the unavailable notice, all
--                     hands seed engine_dead, and no wire traffic ever flows.
--   D8 negative:      hold INFO past 5 s, run the deadline, deliver the lib late.
--                     Pre-fix this leg is RED (D8: the stub substitution is
--                     permanent); post-fix it is green (late-INFO rewire).
--   D2 Anniversary-nil (expected-fail, pending HU-29 - Libs/ is HU-29-ruled, not
--                     this lane): melee advances, ranged does not. Recorded as
--                     EXPECTED-FAIL, never green, never a failure.
--
-- Run from the repo root: lua5.1 tests/real_wire_state.lua  (any cwd works; a
-- /tmp/opencode copy tests itself the same way - ROOT follows arg[0]).

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures, expected_failures = 0, 0, 0
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
local function near(got, want, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > 1e-9 then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end
-- D2 leg only: the HU-29-blocked shape. Loud, counted apart, never a failure,
-- never green.
local function xfail(label)
    checks = checks + 1
    expected_failures = expected_failures + 1
    print("EXPECTED-FAIL  " .. label)
end

local function read_text(path)
    local f = assert(io.open(path, "r"), "cannot read " .. path)
    local text = f:read("*a")
    f:close()
    return text
end

-- Static identity pins: the swing engine under test is the shipped file, not a
-- re-typed fixture. These hold on the pre-fix and the post-fix tree alike.
do
    local lib_src = read_text(ROOT .. "Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua")
    check(lib_src:find('MINOR = "LibClassicSwingTimerAPI", 32', 1, true) ~= nil,
        "real-lib identity: the shipped LibClassicSwingTimerAPI minor 32 is loaded")
    local cbh_src = read_text(ROOT .. "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
    check(cbh_src:find('MINOR = "CallbackHandler-1.0", 7', 1, true) ~= nil,
        "shipped-v7 identity: CallbackHandler-1.0 minor 7 hosts the registry")
end

local SIX = {
    "SWING_TIMER_CLIPPED", "SWING_TIMER_DELTA", "SWING_TIMER_PAUSED",
    "SWING_TIMER_START", "SWING_TIMER_STOP", "SWING_TIMER_UPDATE",
}

--=========================================================================================
-- Sandbox builder: one throwaway client per call.
-- opts.profile  "era" | "anniv" | "anniv-nil" | "titan" | "forever" | "retail"
--               (class is always HUNTER: the only profile whose bar set covers
--               melee and ranged; HU-31 scope: era, anniv, titan run the real
--               lib; forever and retail assert their own-API paths only).
-- opts.off_speed  offhand UnitAttackSpeed return (default 0 = no offhand
--               weapon, the shipped shape; set to a positive speed to drive
--               the offhand through the real lib).
-- Forever loads the REAL swing_source.lua (the engine the _Mainline TOC
-- ships) instead of the vendored lib, through the REAL shipped v7.
-- Retail loads NO swing engine (the _Mainline TOC ships none there either):
-- main.lua falls back to its inert stand-in, which must stay silent.
--=========================================================================================
local function build(opts)
    opts = opts or {}
    local profile = opts.profile or "era"
    local project_map = { era = 2, anniv = 5, ["anniv-nil"] = 5,
        titan = 11, forever = 18, retail = 1 }
    local interface_map = { era = 11509, anniv = 20506, ["anniv-nil"] = 20506,
        titan = 38002, forever = 16001, retail = 120100 }
    local project = project_map[profile]
    local interface = interface_map[profile]
    local is_forever = (profile == "forever")
    local is_retail = (profile == "retail")
    check(project ~= nil, "profile '" .. tostring(profile) .. "' is a known client shape")
    if project == nil then return nil end
    local expansion_current
    if profile == "era" then
        expansion_current = 0 -- lib-irrelevant (isClassic ignores it); runtime value unknowable offline
    elseif profile == "anniv" then
        expansion_current = 1
    elseif profile == "titan" then
        expansion_current = 2 -- Titanforge is WotLK-line: the lib's isWrath gate reads this
    else
        expansion_current = nil -- the D2 shape (anniv-nil) and the Mainline-code
                                -- profiles (forever/retail): binary-provided or N/A
    end

    local sb = {
        clock = 1000,
        notices = {},     -- ST:Print captures (init_libs notices)
        chatter = {},     -- DEFAULT_CHAT_FRAME:AddMessage captures
        raw_prints = {},  -- the client's global print, spied
        timers = {},      -- manual C_Timer clock: After + NewTimer share one queue
        events = {},      -- app-side AceEvent RegisterEvent captures
        commands = {},    -- RegisterChatCommand captures
        lrc_cb = {},
        lgc_cb = {},
        llm_cb = {},
        cleu = {},        -- scripted CombatLogGetCurrentEventInfo payload
        counts = {},
        cb_errors = {},   -- errors swallowed by the callback bus (geterrorhandler records)
        diag = { calls = 0 },
    }
    local function bump(key)
        sb.counts[key] = (sb.counts[key] or 0) + 1
    end

    -- Frame stub: the lib's event-bus frame, the tooltip, and the addon bar frames.
    local lib_frame = nil
    local function make_frame(label)
        local f = { label = label, scripts = {}, shown = false }
        function f:RegisterEvent(name) bump("frame:RegisterEvent:" .. tostring(name)) end
        function f:RegisterUnitEvent(name, unit)
            bump("frame:RegisterUnitEvent:" .. tostring(name) .. "@" .. tostring(unit))
        end
        function f:UnregisterEvent(name) bump("frame:UnregisterEvent") end
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:GetScript(script) return self.scripts[script] end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:IsShown() return self.shown end
        function f:SetMovable(v) bump("frame:SetMovable") end
        function f:EnableMouse(v) bump("frame:EnableMouse") end
        function f:SetAlpha(v) bump("frame:SetAlpha") end
        function f:SetPoint(a, b, c, d, e) bump("frame:SetPoint") end
        function f:ClearAllPoints() bump("frame:ClearAllPoints") end
        function f:SetWidth(w) bump("frame:SetWidth") end
        function f:SetHeight(h) bump("frame:SetHeight") end
        function f:RegisterForDrag(a, b) bump("frame:RegisterForDrag") end
        function f:SetOwner(a, b) bump("frame:SetOwner") end
        function f:ClearLines() end
        function f:SetItemByID(id) end
        function f:NumLines() return 0 end
        return f
    end

    -- The addon object the Ace stub hands main.lua.
    local ST = {}
    function ST:RegisterEvent(event) sb.events[event] = (sb.events[event] or 0) + 1 end
    function ST:RegisterUnitEvent(event) sb.events[event] = (sb.events[event] or 0) + 1 end
    function ST:RegisterChatCommand(command, method) sb.commands[command] = method end
    function ST:Print(msg) sb.notices[#sb.notices + 1] = tostring(msg) end

    local env = setmetatable({}, { __index = _G })
    env._G = env -- this client's globals table: LibStub instances stay per-sandbox
    env.strmatch = string.match -- WoW client global LibStub.lua needs
    -- The WoW client forwards xpcall's trailing arguments to the called function;
    -- stock Lua 5.1 drops them (verified nargs=0). The shipped AceAddon-3.0,
    -- AceGUI-3.0, AceConfigDialog-3.0 and CallbackHandler-1.0 Dispatch all call
    -- xpcall(func, err, ...) with payload args, so a stock xpcall delivers every
    -- library callback argless. This shim is scripted client behaviour, not a
    -- fixture in the lib's shape.
    local real_xpcall = xpcall
    env.xpcall = function(f, errfunc, ...)
        local args = { n = select("#", ...), ... }
        return real_xpcall(function() return f(unpack(args, 1, args.n)) end, errfunc)
    end
    env.geterrorhandler = function()
        return function(err)
            sb.cb_errors[#sb.cb_errors + 1] = tostring(err)
            return err
        end
    end
    env.table = setmetatable({}, { __index = _G.table }) -- main.lua defines table.pack at load
    env.WOW_PROJECT_ID = project
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_FOREVER = 18
    env.WOW_PROJECT_CAMELOT = 18 -- compat.lua reads this name (falls back to 18)
    env.Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
    env.LE_EXPANSION_LEVEL_CURRENT = expansion_current
    env.LE_EXPANSION_BURNING_CRUSADE = 1
    env.LE_EXPANSION_WRATH_OF_THE_LICH_KING = 2
    env.LE_EXPANSION_CATACLYSM = 3
    env.LE_EXPANSION_MISTS_OF_PANDARIA = 4
    env.GetTime = function() return sb.clock end
    env.GetTimePreciseSec = function() return sb.clock end
    env.UnitDistanceSquared = function(unit) return 144, true end -- 12 yd, checked
    env.UnitCastingInfo = function(unit) return nil end
    env.IsInGroup = function() return true end
    env.IsInInstance = function() return true end
    env.GetBuildInfo = function()
        if profile == "era" then return "1.15.9", "00000", "today", interface end
        if profile == "forever" then return "1.60.1", "00000", "today", interface end
        if profile == "titan" then return "3.80.2", "00000", "today", interface end
        if profile == "retail" then return "12.1.0", "00000", "today", interface end
        return "2.5.6", "00000", "today", interface
    end
    env.UnitClass = function() return "Hunter", "HUNTER" end
    env.UnitGUID = function(unit)
        if unit == "player" then return "Player-0001" end
        if unit == "target" then return "Target-0001" end
        return nil
    end
    env.GetPlayerInfoByGUID = function(guid) return "Hunter", "HUNTER" end
    env.UnitExists = function() return false end
    env.UnitCanAttack = function() return false end
    env.GetActiveTalentGroup = function() return 1 end
    env.GetShapeshiftForm = function() return 0 end
    env.IsCurrentSpell = function() return false end
    env.UnitAttackSpeed = function(unit) return sb.attack_speed[1], sb.attack_speed[2] end
    sb.attack_speed = { 2.6, opts.off_speed or 0 } -- default: no offhand weapon
    env.UnitRangedDamage = function(unit) return 3.0 end
    -- unpack must name the length explicitly: CLEU shapes carry positional
    -- nils (the offhand SWING_DAMAGE flag sits at index 22), and a bare
    -- unpack stops at the first hole.
    env.CombatLogGetCurrentEventInfo = function() return unpack(sb.cleu, 1, table.maxn(sb.cleu)) end
    env.GetInventoryItemID = function(unit, slot) return nil end -- no tooltip parse: base speed 1
    env.INVSLOT_RANGED = 18
    env.SPEED = "Speed"
    env.UnitAura = function() return nil end
    env.GetSpellCooldown = function(spell) return 0, 0, 0 end
    env.WorldFrame = {}
    env.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, msg) sb.chatter[#sb.chatter + 1] = tostring(msg) end,
    }
    env.print = function(...)
        sb.raw_prints[#sb.raw_prints + 1] = tostring(select(1, ...))
    end
    env.C_Timer = {
        After = function(delay, fn)
            sb.timer_seq = (sb.timer_seq or 0) + 1
            sb.timers[sb.timer_seq] = { delay = delay, due = sb.clock + delay, cb = fn, cancelled = false }
        end,
        NewTimer = function(delay, fn)
            sb.timer_seq = (sb.timer_seq or 0) + 1
            local timer = { delay = delay, due = sb.clock + delay, cb = fn, cancelled = false }
            function timer:Cancel() self.cancelled = true end
            function timer:IsCancelled() return self.cancelled end
            sb.timers[sb.timer_seq] = timer
            return timer
        end,
        NewTicker = function(delay, fn)
            local ticker = { cancelled = false }
            function ticker:Cancel() self.cancelled = true end
            return ticker
        end,
    }
    env.CreateFrame = function(kind, name, parent, template)
        if kind == "GameTooltip" then return make_frame("tooltip") end
        if kind == "Frame" and lib_frame == nil then
            lib_frame = make_frame("lib")
            return lib_frame
        end
        return make_frame(tostring(name or kind or "frame"))
    end

    -- The REAL LibStub, instanced per sandbox (env._G=env keeps its registry here).
    local libstub_chunk = assert(loadfile(ROOT .. "Libs/LibStub/LibStub.lua"))
    setfenv(libstub_chunk, env)
    libstub_chunk()
    local LibStub = env.LibStub
    assert(type(LibStub) == "table" and type(LibStub.NewLibrary) == "function",
        "the real LibStub loads in the sandbox")

    -- Stub libraries, registered INTO the real LibStub (fixtures for the
    -- non-swing surface only; none of them answers in the lib's shape).
    local LRC = {
        CHECKERS_CHANGED = "CHECKERS_CHANGED",
        MeleeRange = -1,
        RegisterCallback = function(_, event, fn) sb.lrc_cb[event] = fn end,
        GetHarmMaxChecker = function(_, range) return function(unit) return true end end,
        GetHarmMinChecker = function(_, range) return function(unit) return true end end,
        GetRange = function(_, unit) return 0, 8 end,
    }
    local LLM = {
        LATENCY_CHANGED = "LATENCY_CHANGED",
        RegisterCallback = function(_, event, fn) sb.llm_cb[event] = fn end,
    }
    local LGC = {
        GCD_STARTED = "GCD_STARTED",
        GCD_OVER = "GCD_OVER",
        GCD_DURATIONS_UPDATED = "GCD_DURATIONS_UPDATED",
        RegisterCallback = function(_, event, fn) sb.lgc_cb[event] = fn end,
    }
    local LSM = {
        Register = function(_, mediatype, key, path) bump("lsm:Register") end,
        Fetch = function() return nil end,
    }
    local LWIN = {}
    local function stub_library(major, minor, obj)
        local lib = LibStub:NewLibrary(major, minor)
        assert(lib ~= nil, "stub library registers: " .. major)
        for k, v in pairs(obj) do lib[k] = v end
        return lib
    end
    stub_library("AceAddon-3.0", 1, {
        NewAddon = function(_, name) return ST end,
        GetAddon = function(_, name) return ST end,
    })
    stub_library("AceDB-3.0", 1, { New = function(_, name, defaults) return sb.db end })
    stub_library("AceConfig-3.0", 1, { RegisterOptionsTable = function() bump("ac_register") end })
    stub_library("AceConfigDialog-3.0", 1, { AddToBlizOptions = function() bump("acd_bliz") end })
    stub_library("AceDBOptions-3.0", 1, { GetOptionsTable = function() return {} end })
    stub_library("LibSharedMedia-3.0", 1, LSM)
    stub_library("LibWindow-1.1", 1, LWIN)
    stub_library("LibRangeCheck-2.0", 1, LRC)
    stub_library("LibLatencyMonitor", 1, LLM)
    stub_library("LibGlobalCooldown", 1, LGC)
    sb.LRC, sb.LLM, sb.LGC = LRC, LLM, LGC

    -- The addon database (only the keys main.lua's own path reads).
    local class_db = {
        class_enabled = true,
        timers_locked = false,
        enable_spec1 = true,
        enable_spec2 = true,
        form_vis_normal = true,
    }
    local function make_hand_db()
        return { enabled = true, dim_oor = false, dim_alpha = 0.5 }
    end
    class_db.mainhand = make_hand_db()
    class_db.offhand = make_hand_db()
    class_db.ranged = make_hand_db()
    local profile_db = {
        welcome_message = false,
        latency_scale_factor = 1,
        latency_linear_offset = 0,
        gcd_marker_offset_mode = "Off",
    }
    profile_db.HUNTER = class_db
    sb.db = { profile = profile_db, profilename = "Default" }

    -- The SHIPPED v7 CallbackHandler, then the REAL swing engine for the
    -- profile: the vendored lib on the classic line (era/anniv/anniv-nil/
    -- titan), the REAL swing_source.lua (the engine the _Mainline TOC ships)
    -- on Forever, and nothing on Retail (the _Mainline TOC ships no engine
    -- there either - main.lua falls back to its inert stand-in, which must
    -- stay silent).
    local cbh_chunk = assert(loadfile(ROOT .. "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"))
    setfenv(cbh_chunk, env)
    cbh_chunk()
    if is_forever then
        -- Capture the exact v7 registry object swing_source.lua creates, so the
        -- reg-identity assertion below names the real object (not a counter).
        local CBH = LibStub("CallbackHandler-1.0")
        local real_new = CBH.New
        CBH.New = function(self, target, ...)
            local reg = real_new(self, target, ...)
            sb.source_registry = reg
            return reg
        end
    end
    local swing_lib, registry
    if not is_forever and not is_retail then
        local lib_chunk = assert(loadfile(ROOT .. "Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua"))
        setfenv(lib_chunk, env)
        local ok_lib, err_lib = pcall(lib_chunk, "SwedgeTimer")
        check(ok_lib, "the real vendored lib loads in the sandbox (" .. tostring(err_lib) .. ")")
        if not ok_lib then return nil end
        swing_lib = LibStub("LibClassicSwingTimerAPI")
        check(type(swing_lib) == "table", "LibStub serves the real LibClassicSwingTimerAPI")
        if type(swing_lib) ~= "table" then return nil end
        check(type(swing_lib.callbacks) == "table" and type(swing_lib.callbacks.Fire) == "function",
            "the lib's v7 registry object exists (lib.callbacks)")
        registry = swing_lib.callbacks
    end

    -- compat.lua reads several legacy globals through rawget(_G, ...); env._G IS
    -- env here, so those reads resolve into this sandbox with no mirroring.
    local st = {}
    st.utils = {
        convert_lookup_table = function(list)
            local tab = {}
            for i = 1, #list do tab[list[i]] = true end
            return tab
        end,
    }
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    compat("SwedgeTimer", st)
    if is_forever then
        -- TOC order (compat -> swing_source -> main): main.lua reads
        -- st.swing_source.available while it loads, so the REAL source must be
        -- in place first. Not loaded on any other profile (main.lua falls back
        -- to the vendored lib / inert stand-in there).
        local source_chunk = assert(loadfile(ROOT .. "swing_source.lua"))
        setfenv(source_chunk, env)
        local ok_src, err_src = pcall(source_chunk, "SwedgeTimer", st)
        check(ok_src, "the real swing_source.lua loads in the sandbox (" .. tostring(err_src) .. ")")
        if not ok_src then return nil end
        check(st.swing_source ~= nil, "st.swing_source exists")
        check(st.swing_source.available == true, "the Forever source reports itself available")
        check(type(sb.source_registry) == "table" and type(sb.source_registry.Fire) == "function",
            "the source's v7 registry object is captured (source_registry)")
        registry = sb.source_registry
    end
    local utils = assert(loadfile(ROOT .. "utils.lua"))
    setfenv(utils, env)
    utils("SwedgeTimer", st)
    local guard = assert(loadfile(ROOT .. "guard.lua"))
    setfenv(guard, env)
    local ok_guard, err_guard = pcall(guard, "SwedgeTimer", st)
    check(ok_guard, "guard.lua loads under the sandbox (" .. tostring(err_guard) .. ")")
    st.diag = {
        report = function(self, verbose)
            sb.diag.calls = sb.diag.calls + 1
        end,
        install_error_handler = function()
            sb.diag.installs = (sb.diag.installs or 0) + 1
            return true
        end,
        uninstall_error_handler = function()
            sb.diag.uninstalls = (sb.diag.uninstalls or 0) + 1
            return true
        end,
    }

    local main_chunk = assert(loadfile(ROOT .. "main.lua"))
    setfenv(main_chunk, env)
    local ok_main, err_main = pcall(main_chunk, "SwedgeTimer", st)
    if not ok_main then
        print("FAIL  main.lua does not load under the sandbox: " .. tostring(err_main))
        return nil
    end

    -- The TOC surface the rest of the addon provides (bars.lua visuals entry
    -- points stay stubs; the wire under test ends at ST[hand] state and the
    -- installed OnUpdate, both asserted below).
    ST.defaults = {}
    ST.set_opts = function(self) bump("set_opts"); self.opts_table = {} end
    ST.init_visuals_template = function() bump("init_visuals") end
    ST.set_bar_texts = function() bump("set_texts") end
    ST.on_latency_update = function() bump("latency_update") end
    ST.set_gcd_marker_positions = function() bump("gcd_marker") end
    ST.on_bar_inactive = function() bump("bar_inactive") end
    ST.on_bar_active = function() bump("bar_active") end
    ST.on_attack_speed_change = function() bump("attack_speed_change") end
    ST.on_gcd_length_change = function() bump("gcd_length_change") end
    ST.set_bar_color = function() bump("bar_color") end

    -- Stubbed bar frames, one set per hand of the class (the seed/render state
    -- lives on ST[hand]; the frames only carry the OnUpdate the seed installs).
    for _, hand in ipairs({ "mainhand", "offhand", "ranged" }) do
        ST[hand].anchor_frame = make_frame(hand .. ".anchor")
        local anchor = ST[hand].anchor_frame
        anchor.hiding_anchor_frame = make_frame(hand .. ".hiding")
        anchor.bar_frame = make_frame(hand .. ".bar")
        anchor.bar_frame.visuals_frame = make_frame(hand .. ".visuals")
        anchor.bar_frame.visuals_frame.gcd_bar = make_frame(hand .. ".gcd_bar")
        ST[hand].onupdate = function() end
    end

    return { env = env, st = st, ST = ST, sb = sb, lib = swing_lib,
        registry = registry, lib_frame = lib_frame, profile = profile }
end

--=========================================================================================
-- Drive helpers: the scripted client.
--=========================================================================================
-- Manual clock: run every due, uncancelled timer (After + NewTimer share one
-- queue). Iterates to the append high-water mark, never #timers: consumed
-- timers leave nil holes and Lua 5.1 # is undefined on holed tables, so a
-- #-bounded sweep can strand a due timer forever (Titanforge's re-fired
-- ranged timer proved it).
local function advance(b, sec)
    b.sb.clock = b.sb.clock + sec
    local ran = true
    while ran do
        ran = false
        for i = 1, (b.sb.timer_seq or 0) do
            local t = b.sb.timers[i]
            if t and not t.cancelled and t.due <= b.sb.clock then
                b.sb.timers[i] = nil
                ran = true
                t.cb()
            end
        end
    end
end

-- The lib's whole event bus: its frame OnEvent script.
local function lib_event(b, event, ...)
    local script = b.lib_frame.scripts.OnEvent
    assert(script ~= nil, "the lib registered its frame OnEvent script")
    script(b.lib_frame, event, ...)
end

local function report_login(b)
    local cb = b.sb.lgc_cb["GCD_DURATIONS_UPDATED"]
    assert(cb, "OnInitialize registered the GCD_DURATIONS_UPDATED callback")
    cb("GCD_DURATIONS_UPDATED", 1.5, 1.5)
end

local function fire_lrc(b)
    local cb = b.sb.lrc_cb[b.sb.LRC.CHECKERS_CHANGED]
    assert(cb, "OnInitialize registered the LRC CHECKERS_CHANGED callback")
    cb()
end

local function addon_loaded(b)
    lib_event(b, "ADDON_LOADED", "SwedgeTimer")
end

local function pew(b)
    lib_event(b, "PLAYER_ENTERING_WORLD")
end

-- CLEU mainhand swing: (ts, subEvent, hide, sourceGUID, ...) in the lib's shape.
local function cleu_mh_swing(b)
    b.sb.cleu = { b.sb.clock, "SWING_DAMAGE", nil, "Player-0001", "Me", 0,
        0, "Creature-09", "Target", 0, 0, 100, nil, nil, nil }
    lib_event(b, "COMBAT_LOG_EVENT_UNFILTERED")
end

-- CLEU offhand swing: the lib reads the offhand flag from the trailing
-- isOffHand slot (CLEU return 21); everything else mirrors the mainhand shape.
local function cleu_oh_swing(b)
    b.sb.cleu = { b.sb.clock, "SWING_DAMAGE", nil, "Player-0001", "Me", 0,
        0, "Creature-09", "Target", 0, 0, 100, nil, nil, nil,
        nil, nil, nil, nil, nil, true }
    lib_event(b, "COMBAT_LOG_EVENT_UNFILTERED")
end

-- CLEU misses: the lib re-reads the offhand flag from the overkill slot
-- (cleu index 13) on SWING_MISSED (lib:399-401).
local function cleu_miss(b, offhand)
    b.sb.cleu = { b.sb.clock, "SWING_MISSED", nil, "Player-0001", "Me", 0,
        0, "Creature-09", "Target", 0, 0, "DODGE", offhand and true or false, nil, nil }
    lib_event(b, "COMBAT_LOG_EVENT_UNFILTERED")
end

-- CLEU parry: a SWING_MISSED whose miss type is PARRY (lib:415, unreachable
-- behind the generic SWING_MISSED catch at lib:397 while HU-29 is open).
local function cleu_parry(b)
    b.sb.cleu = { b.sb.clock, "SWING_MISSED", nil, "Player-0001", "Me", 0,
        0, "Creature-09", "Target", 0, 0, "PARRY", false, nil, nil }
    lib_event(b, "COMBAT_LOG_EVENT_UNFILTERED")
end

-- CLEU SPELL_EXTRA_ATTACKS (Windfury/sword-spec shape): the lib has no
-- handler for it at all (HU-29 D5), so today this fires nothing.
local function cleu_extra_attacks(b)
    b.sb.cleu = { b.sb.clock, "SPELL_EXTRA_ATTACKS", nil, "Player-0001", "Me", 0,
        0, "Creature-09", "Target", 0, 0, 75, "Auto Shot", 1 }
    lib_event(b, "COMBAT_LOG_EVENT_UNFILTERED")
end

-- CLEU SPELL_CAST_START with a ranged-spell id in the spell slot (lib:454-456).
local function cleu_cast_start(b, spell)
    b.sb.cleu = { b.sb.clock, "SPELL_CAST_START", nil, "Player-0001", "Me", 0,
        0, "Creature-09", "Target", 0, 0, spell, nil, nil, nil }
    lib_event(b, "COMBAT_LOG_EVENT_UNFILTERED")
end

-- Unit events straight at the lib's frame (the app never sees these; the lib
-- translates them into the UNIT_SWING_TIMER_* re-fire the registry carries).
local function failed_quiet(b, spell)
    lib_event(b, "UNIT_SPELLCAST_FAILED_QUIET", "player", "cast-1", spell)
end

local function attack_speed(b, unit)
    lib_event(b, "UNIT_ATTACK_SPEED", unit or "player")
end

local function autorepeat_start(b)
    lib_event(b, "START_AUTOREPEAT_SPELL")
end

local function succeeded(b, spell)
    lib_event(b, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", spell)
end

local function wire_starts(b, hand)
    local counts = b.ST.swing_wire_counts
    if type(counts) ~= "table" then return 0 end
    local h = counts[hand]
    if type(h) ~= "table" then return 0 end
    return h.start or 0
end

local function wire_updates(b, hand)
    local counts = b.ST.swing_wire_counts
    if type(counts) ~= "table" then return 0 end
    local h = counts[hand]
    if type(h) ~= "table" then return 0 end
    return h.update or 0
end

local function wire_stops(b, hand)
    local counts = b.ST.swing_wire_counts
    if type(counts) ~= "table" then return 0 end
    local h = counts[hand]
    if type(h) ~= "table" then return 0 end
    return h.stop or 0
end

local function wire_total(b)
    local counts = b.ST.swing_wire_counts
    if type(counts) ~= "table" then return 0 end
    local n = 0
    for _, h in pairs(counts) do
        if type(h) == "table" then
            n = n + (h.start or 0) + (h.update or 0) + (h.stop or 0)
        end
    end
    return n
end

-- The six app regs land IN THE ENGINE's v7 registry object (identity, not a
-- counter). skip_unit is for engines without the lib's legacy UNIT_ re-fire
-- (swing_source fires SWING_TIMER_* directly, main.lua:964+ strips nothing
-- from a speed-first payload).
local function assert_six_in_lib_registry(b, tag, skip_unit)
    for i = 1, #SIX do
        local event = SIX[i]
        local bucket = b.registry.events and b.registry.events[event]
        check(type(bucket) == "table" and type(bucket[b.ST]) == "function",
            tag .. ": '" .. event .. "' is registered in the engine's registry by the app")
    end
    if not skip_unit then
        local unit_bucket = b.registry.events and b.registry.events["UNIT_SWING_TIMER_START"]
        check(type(unit_bucket) == "table" and type(unit_bucket[b.lib]) == "function",
            tag .. ": the lib's own UNIT_ re-fire entry shares the same registry object")
    end
end

print("")
print("-- real-wire legs: Era / Anniversary(1) / Titanforge / TBC+Wrath drivers / lifecycle x3 / MISSED x3 / PARRY+EXTRA(xfail) / Forever joint / Retail silent / D8-negative / Anniversary-nil(D2) --")
print("")

--=========================================================================================
-- Era happy leg (green on the pre-fix tree: the strip + wire shape with the real lib).
--=========================================================================================
do
    local b = build({ profile = "era" })
    assert(b ~= nil, "era: the sandbox builds")
    local T, F = b.ST, b.sb

    T:OnInitialize()
    check(F.events["PLAYER_ENTERING_WORLD"] ~= nil, "era: the app registers its world-enter event")
    check(F.events["START_AUTOREPEAT_SPELL"] ~= nil, "era: autorepeat events stay registered (classic line)")
    check(F.events["UNIT_SPELLCAST_SUCCEEDED"] ~= nil, "era: the app registers its spellcast-success event")
    check(b.lib_frame ~= nil and b.lib_frame.scripts.OnEvent ~= nil,
        "era: the real lib registered its frame OnEvent script")
    report_login(b)
    eq(T.interfaces_are_initialised, false, "era: init waits before the libraries report")

    addon_loaded(b)
    eq(b.lib.player.id, "player", "era: ADDON_LOADED builds the lib player unit")
    eq(b.lib.target.id, "target", "era: ADDON_LOADED builds the lib target unit")

    pew(b) -- lib first: INFO fires while LRC is still pending
    eq(T.stl_ready, true, "era: PEW is app-observed as INFO_INITIALIZED (stl_ready)")
    eq(T.interfaces_are_initialised, false, "era: init still waits for LRC after INFO")

    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "era: LRC completes init")
    eq(T.swing_engine, "vendored-lib", "era: the engine line reads vendored-lib")
    eq(#F.notices, 0, "era: the lib-first happy path prints no notice")
    assert_six_in_lib_registry(b, "era")

    -- Seed: init_timers read the live lib (never a fixture number).
    near(T.mainhand.speed, 2.6, "era: mh seed speed comes from the live lib")
    eq(T.mainhand.engine_dead, false, "era: mh seed is not engine_dead")
    check(T.mainhand.start ~= nil and T.mainhand.ends_at ~= nil, "era: mh seed has a live cycle")
    near(T.ranged.speed, 3.0, "era: ranged seed speed comes from the live lib")
    check(T:get_bar_frame("mainhand"):GetScript("OnUpdate") ~= nil,
        "era: the mh OnUpdate is installed on the stubbed frame")

    -- CLEU mainhand swing advances the bar.
    local pre_start = T.mainhand.start
    advance(b, 1.5)
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, "era: CLEU SWING_DAMAGE advances mh to the swing time")
    check(T.mainhand.start ~= pre_start, "era: mh actually moved")
    near(T.mainhand.speed, 2.6, "era: mh speed survives the swing")
    eq(T.mainhand.engine_dead, false, "era: mh stays live after the swing")
    check(wire_starts(b, "mainhand") >= 1, "era: the START wire counter saw the mh swing")

    -- Auto Shot: autorepeat + SUCCEEDED(75) advances ranged.
    local pre_ranged = T.ranged.start
    autorepeat_start(b)
    advance(b, 1.0)
    succeeded(b, 75)
    eq(T.ranged.start, F.clock, "era: SUCCEEDED(75)+autorepeat advances ranged")
    near(T.ranged.speed, 3.0, "era: ranged speed survives the shot")
    eq(T.ranged.engine_dead, false, "era: ranged stays live after the shot")
    check(T.ranged.start ~= pre_ranged, "era: ranged actually moved")
    check(wire_starts(b, "ranged") >= 1, "era: the START wire counter saw the ranged shot")
    check(#F.notices == 0, "era: still no notice after live fire")
    eq(#F.raw_prints, 0, "era: nothing reached the client's global print")
    eq(#F.cb_errors, 0, "era: no callback-bus error was swallowed")
end

--=========================================================================================
-- Anniversary(level=1) happy leg: the conditional wire, green with the real lib.
--=========================================================================================
do
    local b = build({ profile = "anniv" })
    assert(b ~= nil, "anniv: the sandbox builds")
    local T, F = b.ST, b.sb

    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    eq(b.lib.player.id, "player", "anniv: ADDON_LOADED builds the lib player unit")
    pew(b)
    eq(T.stl_ready, true, "anniv: PEW is app-observed as INFO_INITIALIZED (stl_ready)")
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "anniv: LRC completes init")
    eq(T.swing_engine, "vendored-lib", "anniv: the engine line reads vendored-lib")
    eq(#F.notices, 0, "anniv: the happy path prints no notice")
    assert_six_in_lib_registry(b, "anniv")

    local pre_start = T.mainhand.start
    advance(b, 1.5)
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, "anniv: CLEU SWING_DAMAGE advances mh")
    check(T.mainhand.start ~= pre_start, "anniv: mh actually moved")
    eq(T.mainhand.engine_dead, false, "anniv: mh stays live after the swing")

    local pre_ranged = T.ranged.start
    autorepeat_start(b)
    advance(b, 1.0)
    succeeded(b, 75)
    eq(T.ranged.start, F.clock, "anniv(1): SUCCEEDED(75)+autorepeat advances ranged")
    eq(T.ranged.engine_dead, false, "anniv(1): ranged stays live after the shot")
    check(T.ranged.start ~= pre_ranged, "anniv(1): ranged actually moved")
    eq(#F.cb_errors, 0, "anniv: no callback-bus error was swallowed")
end

--=========================================================================================
-- Titanforge happy leg: the same drive on the Wrath tables (HU-31: Titanforge
-- is WotLK-line, interface 38002 - this unblocks the old U-W1 wait, which had
-- kept every Wrath leg out of the harness). SUCCEEDED(75) also resets melee
-- on Wrath (reset_swing_spells, lib:1087) - pinned only as "mh advances".
--=========================================================================================
do
    local b = build({ profile = "titan" })
    assert(b ~= nil, "titan: the sandbox builds")
    local T, F = b.ST, b.sb

    T:OnInitialize()
    check(F.events["PLAYER_ENTERING_WORLD"] ~= nil, "titan: the app registers its world-enter event")
    report_login(b)
    addon_loaded(b)
    eq(b.lib.player.id, "player", "titan: ADDON_LOADED builds the lib player unit")
    pew(b)
    eq(T.stl_ready, true, "titan: PEW is app-observed as INFO_INITIALIZED (stl_ready)")
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "titan: LRC completes init")
    eq(T.swing_engine, "vendored-lib", "titan: the engine line reads vendored-lib")
    eq(#F.notices, 0, "titan: the happy path prints no notice")
    assert_six_in_lib_registry(b, "titan")

    local pre_start = T.mainhand.start
    advance(b, 1.5)
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, "titan: CLEU SWING_DAMAGE advances mh")
    check(T.mainhand.start ~= pre_start, "titan: mh actually moved")
    eq(T.mainhand.engine_dead, false, "titan: mh stays live after the swing")

    local pre_ranged = T.ranged.start
    autorepeat_start(b)
    advance(b, 1.0)
    succeeded(b, 75)
    eq(T.ranged.start, F.clock, "titan: SUCCEEDED(75)+autorepeat advances ranged")
    eq(T.ranged.engine_dead, false, "titan: ranged stays live after the shot")
    check(T.ranged.start ~= pre_ranged, "titan: ranged actually moved")
    eq(#F.cb_errors, 0, "titan: no callback-bus error was swallowed")
end

--=========================================================================================
-- TBC/Wrath driver table legs: the family-divergent ranged drivers through
-- the real lib + real v7 (Pin 1, HU-31 order: Era/Anniversary/Titanforge).
-- The SUCCEEDED path has no family gate (lib:600-606), so a lone SUCCEEDED(75)
-- advances ranged identically on all three families; the CAST_START (lib:456)
-- and FAILED_QUIET (lib:772) paths are isClassic-gated, so they drive an Era
-- UPDATE and leave TBC/Wrath untouched. A gate swap on any of the three paths
-- breaks exactly one leg below.
--=========================================================================================
do
    local tags = { era = "era", anniv = "tbc", titan = "titan" }
    for _, profile in ipairs({ "era", "anniv", "titan" }) do
        local tag = tags[profile]
        local b = build({ profile = profile })
        assert(b ~= nil, tag .. "-driver: the sandbox builds")
        local T, F = b.ST, b.sb
        T:OnInitialize()
        report_login(b)
        addon_loaded(b)
        pew(b)
        fire_lrc(b)
        eq(T.interfaces_are_initialised, true, tag .. "-driver: init completes")
        assert_six_in_lib_registry(b, tag .. "-driver")

        -- Lone SUCCEEDED(75) with no prior START_AUTOREPEAT_SPELL: advances
        -- ranged on BOTH families (agreement leg - the lib checks neither
        -- isShooting nor family here; verified against the real lib 2026-10-22).
        local pre_ranged = T.ranged.start
        advance(b, 1.0)
        succeeded(b, 75)
        eq(T.ranged.start, F.clock, tag .. "-driver: lone SUCCEEDED(75) advances ranged")
        check(T.ranged.start ~= pre_ranged, tag .. "-driver: ranged actually moved")
        check(wire_starts(b, "ranged") >= 1, tag .. "-driver: the START wire counter saw it")
        eq(#F.cb_errors, 0, tag .. "-driver: no callback-bus error was swallowed")
    end
end

-- CAST_START: Era drives a ranged UPDATE (autoShotCastTime rescale), TBC and
-- Titanforge do not move at all.
do
    local tags = { era = "era-cast", anniv = "tbc-cast", titan = "titan-cast" }
    for _, profile in ipairs({ "era", "anniv", "titan" }) do
        local tag = tags[profile]
        local b = build({ profile = profile })
        assert(b ~= nil, tag .. ": the sandbox builds")
        local T, F = b.ST, b.sb
        T:OnInitialize()
        report_login(b)
        addon_loaded(b)
        pew(b)
        fire_lrc(b)
        -- Past the cast window (condition: now > rangedExpiration - autoShotCastTime).
        advance(b, 2.6)
        local pre_exp = T.ranged.ends_at
        local pre_updates = wire_updates(b, "ranged")
        cleu_cast_start(b, 75)
        if profile == "era" then
            eq(wire_updates(b, "ranged"), pre_updates + 1, "era-cast: CAST_START drives a ranged UPDATE")
            check(T.ranged.ends_at ~= pre_exp, "era-cast: the ranged expiration moved")
            near(T.ranged.ends_at, F.clock + b.lib.player.autoShotCastTime,
                "era-cast: the UPDATE carries now + autoShotCastTime (live lib state)")
        else
            eq(wire_updates(b, "ranged"), pre_updates, tag .. ": CAST_START fires no ranged UPDATE")
            eq(T.ranged.ends_at, pre_exp, tag .. ": the ranged expiration is untouched")
        end
        eq(#F.cb_errors, 0, tag .. ": no callback-bus error was swallowed")
    end
end

-- FAILED_QUIET: Era sets the 0.5s hidden-cast window (UPDATE with
-- now + 0.5 + autoShotCastTime), TBC and Titanforge do not touch ranged.
do
    local tags = { era = "era-fq", anniv = "tbc-fq", titan = "titan-fq" }
    for _, profile in ipairs({ "era", "anniv", "titan" }) do
        local tag = tags[profile]
        local b = build({ profile = profile })
        assert(b ~= nil, tag .. ": the sandbox builds")
        local T, F = b.ST, b.sb
        T:OnInitialize()
        report_login(b)
        addon_loaded(b)
        pew(b)
        fire_lrc(b)
        autorepeat_start(b) -- FAILED_QUIET needs isShooting on every family here
        advance(b, 1.0)
        local pre_exp = T.ranged.ends_at
        local pre_updates = wire_updates(b, "ranged")
        failed_quiet(b, 75)
        if profile == "era" then
            eq(wire_updates(b, "ranged"), pre_updates + 1, "era-fq: FAILED_QUIET drives a ranged UPDATE")
            near(T.ranged.ends_at, F.clock + 0.5 + b.lib.player.autoShotCastTime,
                "era-fq: the UPDATE carries the 0.5s window (live lib state)")
        else
            eq(wire_updates(b, "ranged"), pre_updates, tag .. ": FAILED_QUIET fires no ranged UPDATE")
            eq(T.ranged.ends_at, pre_exp, tag .. ": the ranged expiration is untouched")
        end
        eq(#F.cb_errors, 0, tag .. ": no callback-bus error was swallowed")
    end
end

--=========================================================================================
-- Full swing lifecycle per hand through the real v7 registry (Pin 2, HU-31
-- Era/Anniversary legs; Titanforge has its own leg below - Wrath re-fires
-- ranged on every melee swing, so Era-shaped wire-last asserts do not hold
-- there): mainhand START -> clock past expiry -> hand-only STOP (is_full
-- follows), and offhand START -> UNIT_ATTACK_SPEED UPDATE -> hand-only STOP
-- -> is_full, on a two-speed UnitAttackSpeed fixture (the default fixture
-- returns no offhand weapon, so the offhand was never driven before). The
-- STOP legs are the first real-registry STOP coverage: a dispatcher regression
-- eating hand-only STOPs used to stay green.
--=========================================================================================
do
    local tags = { era = "life", anniv = "life-ab" }
    for _, profile in ipairs({ "era", "anniv" }) do
    local tag = tags[profile]
    local b = build({ profile = profile, off_speed = 1.8 })
    assert(b ~= nil, tag .. ": the sandbox builds")
    local T, F = b.ST, b.sb
    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    pew(b)
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, tag .. ": init completes")
    eq(T.swing_engine, "vendored-lib", tag .. ": the engine line reads vendored-lib")
    assert_six_in_lib_registry(b, "life")
    near(T.offhand.speed, 1.8, tag .. ": the offhand seed speed comes from the live lib")
    eq(T.offhand.engine_dead, false, tag .. ": the offhand seed is not engine_dead")

    -- Mainhand: START -> past expiry -> hand-only STOP -> is_full.
    local mh_updates_before = wire_updates(b, "mainhand")
    advance(b, 1.5)
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, tag .. ": CLEU SWING_DAMAGE advances mh")
    eq(wire_updates(b, "mainhand"), mh_updates_before, tag .. ": the mh swing fires no UPDATE")
    local mh_exp = T.mainhand.ends_at
    advance(b, mh_exp - F.clock + 0.15) -- past the lib's own SwingEnd timer
    eq(wire_stops(b, "mainhand") >= 1, true, tag .. ": the hand-only STOP reaches the app")
    eq(T.mainhand.engine_dead, false, tag .. ": mh stays live after the STOP")
    advance(b, 0.6) -- the app's bar_full_delay (0.5) elapses
    eq(T.mainhand.is_full, true, tag .. ": the mh bar marks full after the STOP")
    eq(T.swing_wire_last.hand, "mainhand", tag .. ": the wire-last diag names the hand")
    eq(T.swing_wire_last.kind, "STOP", tag .. ": the wire-last diag names the STOP")

    -- Offhand: START -> attack-speed UPDATE -> hand-only STOP -> is_full.
    local oh_updates_before = wire_updates(b, "offhand")
    cleu_oh_swing(b)
    eq(T.offhand.start, F.clock, tag .. ": CLEU offhand SWING_DAMAGE advances oh")
    near(T.offhand.speed, 1.8, tag .. ": the oh cycle runs at the fixture speed")
    b.sb.attack_speed = { 2.6, 0.9 }
    attack_speed(b, "player")
    eq(wire_updates(b, "offhand"), oh_updates_before + 1, tag .. ": UNIT_ATTACK_SPEED drives an oh UPDATE")
    near(T.offhand.speed, 0.9, tag .. ": the oh cycle runs at the new speed")
    local oh_exp = T.offhand.ends_at
    advance(b, oh_exp - F.clock + 0.15)
    eq(wire_stops(b, "offhand") >= 1, true, tag .. ": the hand-only oh STOP reaches the app")
    eq(T.offhand.engine_dead, false, tag .. ": oh stays live after the STOP")
    advance(b, 0.6)
    eq(T.offhand.is_full, true, tag .. ": the oh bar marks full after the STOP")
    eq(T.swing_wire_last.hand, "offhand", tag .. ": the wire-last diag names the oh hand")
    eq(T.swing_wire_last.kind, "STOP", tag .. ": the wire-last diag names the oh STOP")
    eq(#F.cb_errors, 0, tag .. ": no callback-bus error was swallowed")
    end
end

--=========================================================================================
-- Titanforge lifecycle (Pin 2, HU-31 Wrath leg): Wrath re-fires a ranged
-- START on every melee swing (lib:405-413, reset), so this leg pins the true
-- Titanforge traffic - mh START (+ranged START quirk) -> mh STOP -> ranged
-- STOP -> fulls; oh START (+ranged re-START) -> UPDATE -> oh STOP -> full -
-- draining one hand at a time with the wire-last diag asserted at each drain.
--=========================================================================================
do
    local tag = "life-tf"
    local b = build({ profile = "titan", off_speed = 1.8 })
    assert(b ~= nil, tag .. ": the sandbox builds")
    local T, F = b.ST, b.sb
    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    pew(b)
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, tag .. ": init completes")
    eq(T.swing_engine, "vendored-lib", tag .. ": the engine line reads vendored-lib")
    assert_six_in_lib_registry(b, tag)
    near(T.offhand.speed, 1.8, tag .. ": the offhand seed speed comes from the live lib")

    -- Mainhand: START (+ranged START quirk) -> mh STOP -> ranged STOP -> fulls.
    advance(b, 1.5)
    local ranged_starts_before = wire_starts(b, "ranged")
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, tag .. ": CLEU SWING_DAMAGE advances mh")
    eq(wire_starts(b, "ranged"), ranged_starts_before + 1,
        tag .. ": the Wrath melee swing re-fires a ranged START (lib:405-413)")
    eq(T.ranged.start, F.clock, tag .. ": the re-fired ranged cycle starts at the swing")
    local tf_mh_exp, tf_ranged_exp = T.mainhand.ends_at, T.ranged.ends_at
    advance(b, tf_mh_exp - F.clock + 0.15) -- mainhand SwingEnd; ranged still pending
    eq(wire_stops(b, "mainhand") >= 1, true, tag .. ": the hand-only mh STOP reaches the app")
    eq(wire_stops(b, "ranged"), 0, tag .. ": the ranged STOP has not fired yet")
    eq(T.swing_wire_last.hand, "mainhand", tag .. ": the wire-last diag names mh")
    eq(T.swing_wire_last.kind, "STOP", tag .. ": the wire-last diag names the mh STOP")
    advance(b, tf_ranged_exp - F.clock + 0.15) -- ranged SwingEnd
    eq(wire_stops(b, "ranged") >= 1, true, tag .. ": the re-fired ranged STOP reaches the app")
    eq(T.swing_wire_last.hand, "ranged", tag .. ": the wire-last diag names ranged")
    advance(b, 0.6) -- both bar_full_delay timers elapse
    eq(T.mainhand.is_full, true, tag .. ": the mh bar marks full")
    eq(T.ranged.is_full, true, tag .. ": the ranged bar marks full")

    -- Offhand: START (+ranged re-START) -> UPDATE -> oh STOP -> full.
    local tf_ranged_starts = wire_starts(b, "ranged")
    cleu_oh_swing(b)
    eq(T.offhand.start, F.clock, tag .. ": CLEU offhand SWING_DAMAGE advances oh")
    eq(wire_starts(b, "ranged"), tf_ranged_starts + 1,
        tag .. ": the Wrath offhand swing re-fires ranged (lib:405-407)")
    b.sb.attack_speed = { 2.6, 0.9 }
    attack_speed(b, "player")
    eq(wire_updates(b, "offhand") >= 1, true, tag .. ": UNIT_ATTACK_SPEED drives an oh UPDATE")
    near(T.offhand.speed, 0.9, tag .. ": the oh cycle runs at the new speed")
    local tf_oh_exp = T.offhand.ends_at
    advance(b, tf_oh_exp - F.clock + 0.15)
    eq(wire_stops(b, "offhand") >= 1, true, tag .. ": the hand-only oh STOP reaches the app")
    eq(T.offhand.engine_dead, false, tag .. ": oh stays live after the STOP")
    eq(T.swing_wire_last.hand, "offhand", tag .. ": the wire-last diag names oh")
    eq(T.swing_wire_last.kind, "STOP", tag .. ": the wire-last diag names the oh STOP")
    advance(b, 0.6)
    eq(T.offhand.is_full, true, tag .. ": the oh bar marks full")
    eq(#F.cb_errors, 0, tag .. ": no callback-bus error was swallowed")
end

--=========================================================================================
-- SWING_MISSED routing (Pin 3, PASS pins, HU-31 Era/Anniversary/Titanforge):
-- main-slot vs offhand-slot misses land on the correct hand through the real
-- lib (lib:397-401). A regression routing every miss to mainhand breaks the
-- offhand third (on Titanforge the miss also re-fires ranged - unasserted).
--=========================================================================================
do
    local tags = { era = "miss", anniv = "miss-ab", titan = "miss-tf" }
    for _, profile in ipairs({ "era", "anniv", "titan" }) do
    local tag = tags[profile]
    local b = build({ profile = profile, off_speed = 1.8 })
    assert(b ~= nil, tag .. ": the sandbox builds")
    local T, F = b.ST, b.sb
    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    pew(b)
    fire_lrc(b)
    assert_six_in_lib_registry(b, "miss")

    local pre_mh, pre_oh = T.mainhand.start, T.offhand.start
    advance(b, 1.0)
    cleu_miss(b, false)
    eq(T.mainhand.start, F.clock, tag .. ": a main-slot miss advances mh")
    check(T.mainhand.start ~= pre_mh, tag .. ": mh actually moved")
    eq(T.offhand.start, pre_oh, tag .. ": a main-slot miss leaves oh alone")

    advance(b, 1.0)
    cleu_miss(b, true)
    eq(T.offhand.start, F.clock, tag .. ": an offhand-slot miss advances oh")
    check(T.offhand.start ~= pre_oh, tag .. ": oh actually moved")
    eq(T.mainhand.engine_dead, false, tag .. ": mh stays live")
    eq(T.offhand.engine_dead, false, tag .. ": oh stays live")
    eq(#F.cb_errors, 0, tag .. ": no callback-bus error was swallowed")
    end
end

--=========================================================================================
-- PARRY + EXTRA_ATTACKS (Pin 3, EXPECTED-FAIL pending HU-29 - Libs/ is
-- HU-29-ruled, not this lane): the parry-haste arm (lib:415) is unreachable
-- behind the generic SWING_MISSED catch (lib:397), and the lib has no
-- SPELL_EXTRA_ATTACKS handler at all. Recorded as EXPECTED-FAIL, never green,
-- never a failure - and never pinned as PASS. Era-only (the dead arms are
-- family-independent, so one profile carries the xfail).
--=========================================================================================
do
    local b = build({ profile = "era", off_speed = 1.8 })
    assert(b ~= nil, "px: the sandbox builds")
    local T, F = b.ST, b.sb
    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    pew(b)
    fire_lrc(b)
    assert_six_in_lib_registry(b, "px")

    -- PARRY: a correct parry-haste shortens (UPDATEs) the mainhand cycle
    -- without starting a new one. Today the generic catch STARTs instead.
    advance(b, 1.0)
    cleu_mh_swing(b) -- live mainhand cycle to shorten
    local starts_before = wire_starts(b, "mainhand")
    local updates_before = wire_updates(b, "mainhand")
    local exp_before = T.mainhand.ends_at
    advance(b, 0.5)
    cleu_parry(b)
    if wire_starts(b, "mainhand") == starts_before
        and wire_updates(b, "mainhand") == updates_before + 1
        and T.mainhand.ends_at < exp_before then
        eq(T.mainhand.ends_at < exp_before, true, "px: HU-29 landed - parry shortens the cycle")
    else
        xfail("px: parry-haste unreachable (HU-29: lib:415 behind lib:397)")
    end

    -- EXTRA_ATTACKS: the event is unhandled today (no lib handler). Any future
    -- suppression shape (HU-29) must flip this leg to a real pin.
    local total_before = wire_total(b)
    advance(b, 0.5)
    cleu_extra_attacks(b)
    if wire_total(b) ~= total_before then
        eq(false, "px: EXTRA_ATTACKS now drives wire traffic - pin the HU-29 shape here")
    else
        xfail("px: SPELL_EXTRA_ATTACKS unhandled (HU-29: no lib handler)")
    end
    eq(#F.cb_errors, 0, "px: no callback-bus error was swallowed")
end

--=========================================================================================
-- Forever joint leg (issue 1): REAL swing_source.lua Fire(speed, expiry, hand)
-- through the REAL shipped v7 registry into the REAL main.lua dispatcher into
-- bar state. Idle nil-shape seed, mh START -> UNIT_ATTACK_SPEED UPDATE ->
-- hand-only STOP -> is_full, oh START -> hand-only STOP -> is_full.
--=========================================================================================
do
    local b = build({ profile = "forever" })
    assert(b ~= nil, "forev: the sandbox builds")
    local T, F = b.ST, b.sb
    check(T ~= nil and F ~= nil, "forev: the app and sandbox handles exist")

    T:OnInitialize()
    check(F.events["PLAYER_ENTERING_WORLD"] ~= nil, "forev: the app registers its world-enter event")
    check(F.events["START_AUTOREPEAT_SPELL"] == nil,
        "forev: no autorepeat registration on a Mainline-code client")
    check(b.lib_frame ~= nil and b.lib_frame.scripts.OnEvent ~= nil,
        "forev: the real source registered its frame OnEvent script")

    pew(b) -- PLAYER_ENTERING_WORLD -> the source fires INFO_INITIALIZED once
    eq(T.stl_ready, true, "forev: PEW is app-observed as INFO_INITIALIZED (stl_ready)")
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "forev: LRC completes init")
    eq(T.swing_engine, "forever-source", "forev: the engine line reads forever-source")
    eq(#F.notices, 0, "forev: the happy path prints no notice")
    assert_six_in_lib_registry(b, "forev", true)
    -- Idle nil-shape seed (B1 through the real dispatcher path, not a stub).
    eq(T.mainhand.speed, nil, "forev: idle mh seed speed is nil")
    eq(T.mainhand.ends_at, nil, "forev: idle mh seed expiration is nil")
    eq(T.mainhand.engine_dead, false, "forev: idle mh seed is not engine_dead")
    eq(T.offhand.speed, nil, "forev: idle oh seed speed is nil")

    -- Mainhand joint: PLAYER_SWING -> START -> UPDATE -> STOP -> full.
    -- The source arms its scheduled stop once per swing (payload duration +
    -- grace; an UPDATE rescales the displayed expiration but does not re-arm
    -- the timer), so the STOP advance is measured from the swing start.
    lib_event(b, "PLAYER_SWING", 2.6, 0)
    local f_t0 = F.clock
    eq(T.mainhand.start, F.clock, "forev: PLAYER_SWING advances mh through the real joint")
    near(T.mainhand.speed, 2.6, "forev: the mh cycle runs at the payload speed")
    near(T.mainhand.ends_at, F.clock + 2.6, "forev: the mh expiration is start + speed")
    eq(T.mainhand.engine_dead, false, "forev: mh stays live after the swing")
    check(wire_starts(b, "mainhand") >= 1, "forev: the START wire counter saw the swing")

    local f_updates_before = wire_updates(b, "mainhand")
    local f_exp_before = T.mainhand.ends_at
    b.sb.attack_speed = { 1.3, 0 }
    attack_speed(b, "player")
    eq(wire_updates(b, "mainhand"), f_updates_before + 1, "forev: UNIT_ATTACK_SPEED drives an mh UPDATE")
    near(T.mainhand.speed, 1.3, "forev: the mh cycle runs at the new speed")
    near(T.mainhand.ends_at, F.clock + (f_exp_before - F.clock) * (1.3 / 2.6),
        "forev: the UPDATE rescales the remaining time (live source state)")

    local f_exp = f_t0 + 2.6 + 0.1 -- the source's scheduled stop, not the rescaled expiry
    advance(b, f_exp - F.clock + 0.05) -- past the source's scheduled stop
    eq(wire_stops(b, "mainhand") >= 1, true, "forev: the hand-only STOP reaches the app")
    eq(T.mainhand.engine_dead, false, "forev: mh stays live after the STOP")
    advance(b, 0.6)
    eq(T.mainhand.is_full, true, "forev: the mh bar marks full after the STOP")
    eq(T.swing_wire_last.hand, "mainhand", "forev: the wire-last diag names the hand")
    eq(T.swing_wire_last.kind, "STOP", "forev: the wire-last diag names the STOP")

    -- Offhand joint: PLAYER_SWING(1) -> START -> STOP -> full.
    lib_event(b, "PLAYER_SWING", 2.0, 1)
    eq(T.offhand.start, F.clock, "forev: PLAYER_SWING(1) advances oh through the real joint")
    near(T.offhand.speed, 2.0, "forev: the oh cycle runs at the payload speed")
    check(wire_starts(b, "offhand") >= 1, "forev: the START wire counter saw the oh swing")
    local fo_exp = T.offhand.ends_at
    advance(b, fo_exp - F.clock + 0.15)
    eq(wire_stops(b, "offhand") >= 1, true, "forev: the hand-only oh STOP reaches the app")
    advance(b, 0.6)
    eq(T.offhand.is_full, true, "forev: the oh bar marks full after the STOP")
    eq(T.swing_wire_last.hand, "offhand", "forev: the wire-last diag names the oh hand")
    eq(#F.cb_errors, 0, "forev: no callback-bus error was swallowed")
end

--=========================================================================================
-- Retail silent leg (own-API path - no classic-lib behavior pinned here, HU-31):
-- Retail ships no swing engine, so main.lua falls back to its inert stand-in:
-- the stand-in reports ready, init completes on LRC with exactly the
-- unavailable notice, every hand seeds engine_dead, and no wire traffic ever
-- flows - including across the 5s init deadline.
--=========================================================================================
do
    local b = build({ profile = "retail" })
    assert(b ~= nil, "ret: the sandbox builds")
    local T, F = b.ST, b.sb

    T:OnInitialize()
    check(F.events["PLAYER_ENTERING_WORLD"] ~= nil, "ret: the app registers its world-enter event")
    check(F.events["START_AUTOREPEAT_SPELL"] == nil,
        "ret: no autorepeat registration on a Mainline-code client")
    eq(T.stl_ready, true, "ret: the inert stand-in counts as ready from the start")
    eq(T.swing_engine, "inert-standin", "ret: the engine line reads inert-standin")
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "ret: LRC completes init")
    eq(#F.notices, 1, "ret: init prints exactly the unavailable notice")
    check(F.notices[1] ~= nil and F.notices[1]:find("unavailable", 1, true) ~= nil,
        "ret: the notice names the unavailable engine")
    for _, hand in ipairs({ "mainhand", "offhand", "ranged" }) do
        eq(T[hand].speed, nil, "ret: idle " .. hand .. " seed speed is nil")
        eq(T[hand].engine_dead, true, "ret: idle " .. hand .. " seed is engine_dead")
    end
    advance(b, 6) -- past the 5s init deadline: nothing re-substitutes, nothing fires
    eq(T.interfaces_are_initialised, true, "ret: init stays completed past the deadline")
    eq(T.init_deadline_fired, nil, "ret: the deadline found init done and stood down")
    eq(#F.notices, 1, "ret: still exactly one notice past the deadline")
    eq(wire_total(b), 0, "ret: the stand-in carries no wire traffic")
    eq(#F.cb_errors, 0, "ret: no callback-bus error was swallowed")
end

--=========================================================================================
-- D8 negative leg: hold INFO past 5 s, run the deadline, deliver the lib late.
-- RED on the pre-fix tree (the stub substitution is permanent); green after the
-- late-INFO rewire. The happy legs above must not move between the two runs.
--=========================================================================================
do
    local b = build({ profile = "era" })
    assert(b ~= nil, "d8: the sandbox builds")
    local T, F = b.ST, b.sb

    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    fire_lrc(b) -- LRC reports; the swing engine never does
    eq(T.interfaces_are_initialised, false, "d8: init still waits while INFO is held")

    advance(b, 5.1) -- the deadline runs with INFO still held
    eq(T.init_deadline_fired, true, "d8: the deadline records that it fired")
    eq(T.interfaces_are_initialised, true, "d8: init proceeds on the deadline")
    eq(T.swing_engine, "inert-standin", "d8: the deadline substitutes the stand-in")
    eq(#F.notices, 1, "d8: the substitution prints exactly the unavailable notice")
    eq(T.mainhand.speed, nil, "d8: the stub seeds no fake mh cycle")
    eq(T.mainhand.engine_dead, true, "d8: the stub marks mh engine_dead")

    pew(b) -- the lib reports late
    eq(T.stl_ready, true, "d8: the late INFO still lands on the app callback")
    eq(T.swing_engine, "vendored-lib", "d8: the late INFO re-points STL at the reporting engine")
    eq(#F.notices, 1, "d8: the rewire adds no chat line (the engine/diag lines carry it)")
    assert_six_in_lib_registry(b, "d8")
    near(T.mainhand.speed, 2.6, "d8: the re-seed reads the live lib (mh speed)")
    eq(T.mainhand.engine_dead, false, "d8: the re-seed leaves engine_dead")
    near(T.ranged.speed, 3.0, "d8: the re-seed reads the live lib (ranged speed)")

    -- Bars advance on the rewired engine.
    local pre_start = T.mainhand.start
    advance(b, 1.5)
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, "d8: CLEU SWING_DAMAGE advances mh after the rewire")
    check(T.mainhand.start ~= pre_start, "d8: mh actually moved after the rewire")
    local pre_ranged = T.ranged.start
    autorepeat_start(b)
    advance(b, 1.0)
    succeeded(b, 75)
    eq(T.ranged.start, F.clock, "d8: SUCCEEDED(75)+autorepeat advances ranged after the rewire")
    check(T.ranged.start ~= pre_ranged, "d8: ranged actually moved after the rewire")

    -- A second late INFO is a no-op (double-reg guard): no duplicate work.
    local notices_before = #F.notices
    pew(b)
    eq(#F.notices, notices_before, "d8: a repeated late INFO prints nothing again")
    eq(T.init_deadline_fired, true, "d8: the deadline line stays fired (truthful)")
    eq(#F.cb_errors, 0, "d8: no callback-bus error was swallowed")
end

--=========================================================================================
-- D2 Anniversary-nil leg: EXPECTED-FAIL pending HU-29 (Libs/ is HU-29-ruled).
-- Melee (table-free CLEU path) advances; ranged (empty spell tables) does not.
--=========================================================================================
do
    local b = build({ profile = "anniv-nil" })
    assert(b ~= nil, "d2: the sandbox builds")
    local T, F = b.ST, b.sb

    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    pew(b)
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "d2: init completes on the nil-expansion profile")
    assert_six_in_lib_registry(b, "d2")

    advance(b, 1.5)
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, "d2: melee still advances on the nil-expansion profile")
    eq(T.mainhand.engine_dead, false, "d2: mh stays live on the nil-expansion profile")

    local pre_ranged = T.ranged.start
    autorepeat_start(b)
    advance(b, 1.0)
    succeeded(b, 75)
    if T.ranged.start == pre_ranged then
        xfail("d2: Anniversary-nil ranged did not advance on SUCCEEDED(75) (HU-29: lib isBCC gate)")
    else
        eq(T.ranged.start, F.clock, "d2: Anniversary-nil ranged advanced (HU-29 has landed)")
    end
end

--=========================================================================================
-- Reset legs (Era, real lib + real v7): after STOP -> full, the next swing
-- re-STARTs every hand (start re-anchors, is_full clears, fresh expiry). A
-- stale freeze (start stuck, bar full forever) breaks exactly these legs.
-- Cross-hand isolation rides along: a START on one hand never moves the
-- other two hands' anchors (the steady/auto cross-talk shape at bar-state
-- level; the shared-state provenance itself is pinned in hunter_state /
-- hunter_guide_state by the display lane).
--=========================================================================================
do
    local b = build({ profile = "era", off_speed = 1.8 })
    assert(b ~= nil, "era-reset: the sandbox builds")
    local T, F = b.ST, b.sb
    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    pew(b)
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "era-reset: init completes")
    assert_six_in_lib_registry(b, "era-reset")

    -- Mainhand: sweep -> stop -> full -> reset.
    advance(b, 1.5)
    local era_oh0, era_rg0 = T.offhand.start, T.ranged.start
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, "era-reset: CLEU SWING_DAMAGE advances mh")
    eq(T.offhand.start, era_oh0, "era-reset: an mh swing leaves oh anchored")
    eq(T.ranged.start, era_rg0, "era-reset: an mh swing leaves ranged anchored")
    local era_mh_starts = wire_starts(b, "mainhand")
    local era_mh_exp = T.mainhand.ends_at
    advance(b, era_mh_exp - F.clock + 0.15)
    eq(wire_stops(b, "mainhand") >= 1, true, "era-reset: the hand-only mh STOP reaches the app")
    advance(b, 0.6)
    eq(T.mainhand.is_full, true, "era-reset: the mh bar marks full after the STOP")
    advance(b, 0.5)
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, "era-reset: the next mh swing re-STARTs after full")
    eq(T.mainhand.is_full, false, "era-reset: the mh re-START clears is_full")
    eq(wire_starts(b, "mainhand"), era_mh_starts + 1, "era-reset: the mh re-START is wired")
    check(T.mainhand.ends_at > F.clock, "era-reset: the mh re-START arms a fresh expiry")

    -- Offhand: sweep -> stop -> full -> reset (mh stays anchored throughout).
    local era_mh0 = T.mainhand.start
    cleu_oh_swing(b)
    eq(T.offhand.start, F.clock, "era-reset: CLEU offhand SWING_DAMAGE advances oh")
    eq(T.mainhand.start, era_mh0, "era-reset: an oh swing leaves mh anchored")
    near(T.offhand.speed, 1.8, "era-reset: the oh cycle runs at the fixture speed")
    local era_oh_starts = wire_starts(b, "offhand")
    local era_oh_exp = T.offhand.ends_at
    advance(b, era_oh_exp - F.clock + 0.15)
    eq(wire_stops(b, "offhand") >= 1, true, "era-reset: the hand-only oh STOP reaches the app")
    advance(b, 0.6)
    eq(T.offhand.is_full, true, "era-reset: the oh bar marks full after the STOP")
    advance(b, 0.5)
    cleu_oh_swing(b)
    eq(T.offhand.start, F.clock, "era-reset: the next oh swing re-STARTs after full")
    eq(T.offhand.is_full, false, "era-reset: the oh re-START clears is_full")
    eq(wire_starts(b, "offhand"), era_oh_starts + 1, "era-reset: the oh re-START is wired")

    -- Ranged (lib path): sweep -> stop -> full -> reset (melee stays anchored).
    local era_mh1, era_oh1 = T.mainhand.start, T.offhand.start
    autorepeat_start(b)
    advance(b, 1.0)
    succeeded(b, 75)
    eq(T.ranged.start, F.clock, "era-reset: SUCCEEDED(75)+autorepeat advances ranged")
    eq(T.mainhand.start, era_mh1, "era-reset: a ranged swing leaves mh anchored")
    eq(T.offhand.start, era_oh1, "era-reset: a ranged swing leaves oh anchored")
    local era_rg_starts = wire_starts(b, "ranged")
    local era_rg_exp = T.ranged.ends_at
    check(era_rg_exp > F.clock, "era-reset: the ranged cycle arms a full-cycle expiry")
    advance(b, era_rg_exp - F.clock + 0.15)
    eq(wire_stops(b, "ranged") >= 1, true, "era-reset: the hand-only ranged STOP reaches the app")
    advance(b, 0.6)
    eq(T.ranged.is_full, true, "era-reset: the ranged bar marks full after the STOP")
    advance(b, 0.5)
    autorepeat_start(b)
    advance(b, 1.0)
    succeeded(b, 75)
    eq(T.ranged.start, F.clock, "era-reset: the next ranged cycle re-STARTs after full")
    eq(T.ranged.is_full, false, "era-reset: the ranged re-START clears is_full")
    eq(wire_starts(b, "ranged"), era_rg_starts + 1, "era-reset: the ranged re-START is wired")
    eq(#F.cb_errors, 0, "era-reset: no callback-bus error was swallowed")
end

--=========================================================================================
-- Anniversary reset legs: the conditional wire carries the same sweep -> stop ->
-- full -> reset contract (mainhand + ranged; offhand rides the Era leg above -
-- the slot routing is family-independent and pinned in the MISSED block).
--=========================================================================================
do
    local b = build({ profile = "anniv", off_speed = 1.8 })
    assert(b ~= nil, "ab-reset: the sandbox builds")
    local T, F = b.ST, b.sb
    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    pew(b)
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "ab-reset: init completes")
    assert_six_in_lib_registry(b, "ab-reset")

    advance(b, 1.5)
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, "ab-reset: CLEU SWING_DAMAGE advances mh")
    local ab_mh_starts = wire_starts(b, "mainhand")
    advance(b, T.mainhand.ends_at - F.clock + 0.15)
    eq(wire_stops(b, "mainhand") >= 1, true, "ab-reset: the hand-only mh STOP reaches the app")
    advance(b, 0.6)
    eq(T.mainhand.is_full, true, "ab-reset: the mh bar marks full after the STOP")
    advance(b, 0.5)
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, "ab-reset: the next mh swing re-STARTs after full")
    eq(T.mainhand.is_full, false, "ab-reset: the mh re-START clears is_full")
    eq(wire_starts(b, "mainhand"), ab_mh_starts + 1, "ab-reset: the mh re-START is wired")

    autorepeat_start(b)
    advance(b, 1.0)
    succeeded(b, 75)
    eq(T.ranged.start, F.clock, "ab-reset: SUCCEEDED(75)+autorepeat advances ranged")
    local ab_rg_starts = wire_starts(b, "ranged")
    advance(b, T.ranged.ends_at - F.clock + 0.15)
    eq(wire_stops(b, "ranged") >= 1, true, "ab-reset: the hand-only ranged STOP reaches the app")
    advance(b, 0.6)
    eq(T.ranged.is_full, true, "ab-reset: the ranged bar marks full after the STOP")
    advance(b, 0.5)
    autorepeat_start(b)
    advance(b, 1.0)
    succeeded(b, 75)
    eq(T.ranged.start, F.clock, "ab-reset: the next ranged cycle re-STARTs after full")
    eq(T.ranged.is_full, false, "ab-reset: the ranged re-START clears is_full")
    eq(wire_starts(b, "ranged"), ab_rg_starts + 1, "ab-reset: the ranged re-START is wired")
    eq(#F.cb_errors, 0, "ab-reset: no callback-bus error was swallowed")
end

--=========================================================================================
-- Titanforge reset leg: the Wrath melee swing re-fires a ranged START alongside
-- the mainhand one (lib:405-413), so only the mainhand reset is pinned here -
-- the ranged quirk traffic is pinned in the lifecycle leg above.
--=========================================================================================
do
    local b = build({ profile = "titan", off_speed = 1.8 })
    assert(b ~= nil, "tf-reset: the sandbox builds")
    local T, F = b.ST, b.sb
    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    pew(b)
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "tf-reset: init completes")
    assert_six_in_lib_registry(b, "tf-reset")

    advance(b, 1.5)
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, "tf-reset: CLEU SWING_DAMAGE advances mh")
    local tf_mh_starts = wire_starts(b, "mainhand")
    advance(b, T.mainhand.ends_at - F.clock + 0.15)
    eq(wire_stops(b, "mainhand") >= 1, true, "tf-reset: the hand-only mh STOP reaches the app")
    advance(b, 0.6)
    eq(T.mainhand.is_full, true, "tf-reset: the mh bar marks full after the STOP")
    advance(b, 0.5)
    cleu_mh_swing(b)
    eq(T.mainhand.start, F.clock, "tf-reset: the next mh swing re-STARTs after full")
    eq(T.mainhand.is_full, false, "tf-reset: the mh re-START clears is_full")
    eq(wire_starts(b, "mainhand"), tf_mh_starts + 1, "tf-reset: the mh re-START is wired")
    eq(#F.cb_errors, 0, "tf-reset: no callback-bus error was swallowed")
end

--=========================================================================================
-- Fallback-driver legs (the engine lane's maybe_drive_ranged_fallback, driven
-- through the REAL app-side UNIT_SPELLCAST_SUCCEEDED handler - the exact shape
-- the client dispatches. The lib-event helper above never reaches that handler:
-- AceEvent delivery is outside the lib's frame bus, so these legs call the
-- handler directly. The hunter class module is absent in this sandbox (ST.HUNTER
-- is main.lua's empty table), which is exactly the fallback's contract: it reads
-- the cached auto_repeat_active flag and the client probes, never class code).
--=========================================================================================
do
    -- Silence: on the nil-expansion profile the lib never drives ranged (D2),
    -- so the fallback IS the driver - full START -> STOP -> full -> re-START.
    local b = build({ profile = "anniv-nil", off_speed = 1.8 })
    assert(b ~= nil, "fb-silence: the sandbox builds")
    local T, F = b.ST, b.sb
    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    pew(b)
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "fb-silence: init completes")
    eq(T.swing_engine, "vendored-lib", "fb-silence: the engine line reads vendored-lib")
    assert_six_in_lib_registry(b, "fb-silence")
    -- The cached hunter auto-repeat reading (class sync absent here, set directly).
    T.ranged.auto_repeat_active = true

    local fb_mh0, fb_oh0 = T.mainhand.start, T.offhand.start
    T:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 75)
    eq(wire_starts(b, "ranged"), 1, "fb-silence: the fallback drives a ranged START on a silent engine")
    eq(T.ranged.start, F.clock, "fb-silence: the fallback START anchors at now")
    near(T.ranged.speed, 3.0, "fb-silence: the fallback cycle runs at the UnitRangedDamage speed")
    near(T.ranged.ends_at, F.clock + 3.0, "fb-silence: the fallback expiry spans the full cycle")
    check(T.ranged.fallback_timer ~= nil, "fb-silence: the fallback arms its stop timer")
    eq(T.mainhand.start, fb_mh0, "fb-silence: the fallback leaves mh anchored")
    eq(T.offhand.start, fb_oh0, "fb-silence: the fallback leaves oh anchored")
    advance(b, 3.0 + 0.05)
    eq(wire_stops(b, "ranged"), 1, "fb-silence: exactly one fallback STOP fires (the lib is silent)")
    eq(T.swing_wire_last.hand, "ranged", "fb-silence: the wire-last diag names ranged")
    eq(T.swing_wire_last.kind, "STOP", "fb-silence: the wire-last diag names the STOP")
    advance(b, 0.6)
    eq(T.ranged.is_full, true, "fb-silence: the ranged bar marks full after the fallback STOP")
    T:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 75)
    eq(wire_starts(b, "ranged"), 2, "fb-silence: the next shot re-STARTs after full")
    eq(T.ranged.is_full, false, "fb-silence: the fallback re-START clears is_full")
    eq(#F.cb_errors, 0, "fb-silence: no callback-bus error was swallowed")
end

do
    -- Suppression: with a live engine the fallback never double-drives.
    local b = build({ profile = "era", off_speed = 1.8 })
    assert(b ~= nil, "fb-suppress: the sandbox builds")
    local T, F = b.ST, b.sb
    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    pew(b)
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "fb-suppress: init completes")
    autorepeat_start(b)
    advance(b, 1.0)
    succeeded(b, 75) -- the engine's own ranged START (stamps liveness)
    local live_starts = wire_starts(b, "ranged")
    check(live_starts >= 1, "fb-suppress: the engine drives ranged first")
    T.ranged.auto_repeat_active = true
    T:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 75)
    eq(wire_starts(b, "ranged"), live_starts, "fb-suppress: the fallback adds no START on a live engine")
    eq(T.ranged.fallback_timer, nil, "fb-suppress: the fallback arms no stop timer on a live engine")
    eq(#F.cb_errors, 0, "fb-suppress: no callback-bus error was swallowed")
end

do
    -- Convergence: a fallback START followed by the engine's own START on the
    -- same shot settles into one cycle (the engine cancels the fallback timer),
    -- so the full advance yields exactly one STOP, never two.
    local b = build({ profile = "era", off_speed = 1.8 })
    assert(b ~= nil, "fb-converge: the sandbox builds")
    local T, F = b.ST, b.sb
    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    pew(b)
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "fb-converge: init completes")
    T.ranged.auto_repeat_active = true
    T:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 75)
    eq(wire_starts(b, "ranged"), 1, "fb-converge: the fallback STARTs first")
    check(T.ranged.fallback_timer ~= nil, "fb-converge: the fallback timer is armed")
    succeeded(b, 75) -- the engine's own START lands on the same shot
    eq(wire_starts(b, "ranged"), 2, "fb-converge: the engine START lands second")
    eq(T.ranged.fallback_timer, nil, "fb-converge: the engine START cancels the fallback timer")
    advance(b, T.ranged.ends_at - F.clock + 0.15)
    eq(wire_stops(b, "ranged"), 1, "fb-converge: exactly one STOP fires for the converged cycle")
    advance(b, 0.6)
    eq(T.ranged.is_full, true, "fb-converge: the converged cycle marks full")
    eq(#F.cb_errors, 0, "fb-converge: no callback-bus error was swallowed")
end

do
    -- Forever reset (own-API path): after STOP -> full, the next PLAYER_SWING
    -- re-STARTs the hand - the same stale-freeze contract as the classic line,
    -- through the REAL source engine + real v7 + real dispatcher joint.
    local b = build({ profile = "forever" })
    assert(b ~= nil, "forev-reset: the sandbox builds")
    local T, F = b.ST, b.sb
    T:OnInitialize()
    check(F.events["PLAYER_ENTERING_WORLD"] ~= nil, "forev-reset: the app registers its world-enter event")
    pew(b)
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "forev-reset: LRC completes init")
    eq(T.swing_engine, "forever-source", "forev-reset: the engine line reads forever-source")

    lib_event(b, "PLAYER_SWING", 2.6, 0)
    eq(T.mainhand.start, F.clock, "forev-reset: PLAYER_SWING advances mh")
    local fr_mh_starts = wire_starts(b, "mainhand")
    advance(b, T.mainhand.ends_at - F.clock + 0.15)
    eq(wire_stops(b, "mainhand") >= 1, true, "forev-reset: the hand-only mh STOP reaches the app")
    advance(b, 0.6)
    eq(T.mainhand.is_full, true, "forev-reset: the mh bar marks full after the STOP")
    advance(b, 0.5)
    lib_event(b, "PLAYER_SWING", 2.6, 0)
    eq(T.mainhand.start, F.clock, "forev-reset: the next swing re-STARTs mh after full")
    eq(T.mainhand.is_full, false, "forev-reset: the mh re-START clears is_full")
    eq(wire_starts(b, "mainhand"), fr_mh_starts + 1, "forev-reset: the mh re-START is wired")

    lib_event(b, "PLAYER_SWING", 2.0, 1)
    eq(T.offhand.start, F.clock, "forev-reset: PLAYER_SWING(1) advances oh")
    local fr_oh_starts = wire_starts(b, "offhand")
    advance(b, T.offhand.ends_at - F.clock + 0.15)
    eq(wire_stops(b, "offhand") >= 1, true, "forev-reset: the hand-only oh STOP reaches the app")
    advance(b, 0.6)
    eq(T.offhand.is_full, true, "forev-reset: the oh bar marks full after the STOP")
    advance(b, 0.5)
    lib_event(b, "PLAYER_SWING", 2.0, 1)
    eq(T.offhand.start, F.clock, "forev-reset: the next swing re-STARTs oh after full")
    eq(T.offhand.is_full, false, "forev-reset: the oh re-START clears is_full")
    eq(wire_starts(b, "offhand"), fr_oh_starts + 1, "forev-reset: the oh re-START is wired")
    eq(#F.cb_errors, 0, "forev-reset: no callback-bus error was swallowed")
end

do
    -- Inert: Retail and Forever never take the classic-lib fallback (HU-31).
    for _, profile in ipairs({ "retail", "forever" }) do
        local b = build({ profile = profile })
        assert(b ~= nil, "fb-inert-" .. profile .. ": the sandbox builds")
        local T, F = b.ST, b.sb
        T:OnInitialize()
        if profile == "forever" then
            report_login(b)
            addon_loaded(b)
            pew(b)
        end
        fire_lrc(b)
        eq(T.interfaces_are_initialised, true, "fb-inert-" .. profile .. ": init completes")
        T.ranged.auto_repeat_active = true
        local pre_start = T.ranged.start
        T:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 75)
        eq(wire_total(b), 0, "fb-inert-" .. profile .. ": the fallback drives nothing off the classic line")
        eq(T.ranged.start, pre_start, "fb-inert-" .. profile .. ": ranged stays anchored")
        eq(T.ranged.fallback_timer, nil, "fb-inert-" .. profile .. ": no fallback timer is armed")
        eq(#F.cb_errors, 0, "fb-inert-" .. profile .. ": no callback-bus error was swallowed")
    end
end

do
    -- Gates: without auto-repeat, or for a non-Auto-Shot spell, the fallback
    -- stays silent (never invents a cycle: no source means no drive).
    local b = build({ profile = "era", off_speed = 1.8 })
    assert(b ~= nil, "fb-gates: the sandbox builds")
    local T, F = b.ST, b.sb
    T:OnInitialize()
    report_login(b)
    addon_loaded(b)
    pew(b)
    fire_lrc(b)
    eq(T.interfaces_are_initialised, true, "fb-gates: init completes")
    local pre_start = T.ranged.start
    -- auto_repeat_active unset and the sandbox probe answers false: no drive.
    T:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 75)
    eq(wire_starts(b, "ranged"), 0, "fb-gates: no auto-repeat means no fallback START")
    eq(T.ranged.start, pre_start, "fb-gates: ranged stays anchored without auto-repeat")
    -- Auto-repeat on, but a non-Auto-Shot spell id: no drive.
    T.ranged.auto_repeat_active = true
    T:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 999)
    eq(wire_starts(b, "ranged"), 0, "fb-gates: a non-Auto-Shot id drives nothing")
    eq(T.ranged.start, pre_start, "fb-gates: ranged stays anchored on a non-Auto-Shot id")
    eq(T.ranged.fallback_timer, nil, "fb-gates: no fallback timer is armed by a gated shot")
    eq(#F.cb_errors, 0, "fb-gates: no callback-bus error was swallowed")
end

print("")
print(string.format("%d checks, %d failures (%d expected-fail pending HU-29)",
    checks, failures, expected_failures))
if failures > 0 then
    os.exit(1)
end
os.exit(0)
