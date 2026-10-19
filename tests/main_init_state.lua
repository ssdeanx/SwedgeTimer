-- tests/main_init_state.lua: offline execution tests for main.lua's runtime
-- initialisation and event dispatch over the real compat.lua + utils.lua in a sandbox.
--
-- main.lua's init arc was previously only checked as TEXT by tests/wiring_check.lua:
-- nothing executed the 5 s init deadline, the late-library recovery path, or the AceEvent
-- dispatch that once shifted every argument when the event name was dropped. This suite
-- loads the real main.lua under setfenv with the same mirroring discipline as
-- tests/hunter_state.lua / tests/practice_ui_state.lua (compat.lua reads several legacy
-- globals through rawget(_G)), and stubs the addon's external surface (Ace mixins, the
-- dependent libraries, bars.lua / config.lua / classes) so main.lua's calls into them
-- are observable.
--
-- Covered here:
--   1. The init deadline: LibRangeCheck never reports -> the captured C_Timer.After(5)
--      callback flips lrc_unavailable, prints exactly one notice, and init proceeds
--      exactly once. The both-never-ready variant swaps the engine for the stand-in.
--   2. The late-library recovery: a CHECKERS_CHANGED after the deadline lifts the
--      disable and brings the range finders up without a second initialisation.
--   3. Normal init in both callback orders: no notice, init once, and a later deadline
--      firing is a no-op.
--   4. Dispatch arg convention: the class hooks receive the EVENT NAME first, for the
--      spellcast chain and CLEU (the historical arg-shift bug class), plus the library
--      callbacks that were registered with callback_event_handler.
--   5. Init-order guards: the pre-init handlers do nothing and never touch frames or
--      class hooks, while the same dispatch works after init (the guards are the gate).
--   6. Swing-engine selection: vendored library / Forever source / inert stand-in, and
--      st.swing_engine's value for each (the diag line depends on it).
--   7. /st chat-command routing through the captured RegisterChatCommand handler.
--   8. Idempotence: late reports, repeated deadline firings, and double callbacks never
--      re-run init.
--   9. Defect pin (FOUND BY THIS SUITE, fixed in main.lua): init used to crash with
--      "attempt to perform arithmetic on a nil value" when LibGlobalCooldown had never
--      reported its gcd lengths - the exact situation the deadline rescue documents
--      ("a library that never reports ready"). The gcd bases now fall back to the
--      documented 1.5 s pre-report default.
--  10. rf_update's bounded dead-man (M1/M2): a throwing LRC poll (checker call or
--      GetRange) retries with backoff up to RF_MAX_POLL_FAILURES consecutive throws,
--      then disables range checking through the shared one-time notice and stops the
--      retry loop without erroring; a successful poll resets the streak; a checker that
--      never resolves is capped instead of re-arming forever. Also covers the init-poll
--      failure, where the disable must not double-print the deadline notice.
--  4c. Callback fan-out isolation (H3): a throwing lib callback is contained, counted
--      and reported once, and the handlers keep working after it.
-- Run from the repo root: lua5.1 tests/main_init_state.lua  (any cwd works).

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
local function near(got, want, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > 1e-9 then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end
local function contains(text, needle, label)
    check(type(text) == "string" and text:find(needle, 1, true) ~= nil,
        label .. "  (expected '" .. tostring(needle) .. "' in '" .. tostring(text) .. "')")
end
-- Positional argument capture (Lua 5.1 has no table.pack; main.lua defines its own).
local function capture_args(...)
    return { n = select("#", ...), ... }
end

-- The class hooks main.lua dispatches into. classes/<class>.lua attaches these to
-- ST.PALADIN (created empty by main.lua at load); the fixture replaces every one with a
-- counter so the dispatch arg lists are observable.
local HOOK_NAMES = {
    "post_init", "on_spellcast_event", "on_combat_log_unfiltered",
    "on_spellcast_succeeded", "on_spellcast_failed_quiet",
    "on_current_spell_cast_changed", "on_aura_change", "on_combat_exit",
    "on_talents_changed", "on_rage_update", "on_cooldown_update",
    "on_autorrepeat_event",
}

--=========================================================================================
-- Sandbox builder
--=========================================================================================
-- One throwaway client per call. opts:
--   engine       "vendored" (default) | "forever" | "forever-inert" | "absent"
--   project      WOW_PROJECT_ID (default 11 = Wrath)
--   interface    GetBuildInfo's toc (default 38002)
--   report_login false skips the LibGlobalCooldown PLAYER_LOGIN report in boot()
local function build(opts)
    opts = opts or {}
    local engine_mode = opts.engine or "vendored"

    local sb = {
        clock = 100,
        notices = {},        -- self:Print captures (the init_libs notices)
        chatter = {},        -- DEFAULT_CHAT_FRAME:AddMessage captures
        after = {},          -- captured C_Timer.After timers
        new_timers = {},     -- captured C_Timer.NewTimer timers
        events = {},         -- RegisterEvent captures
        unit_events = {},    -- RegisterUnitEvent captures
        commands = {},       -- RegisterChatCommand captures
        lrc_cb = {},
        lgc_cb = {},
        llm_cb = {},
        stl_cb = {},         -- callbacks on the vendored engine
        source_cb = {},      -- callbacks on the Forever source
        lsm = {},
        acedb_new = {},
        acd_opened = {},
        touches = {},        -- every frame-method call, in order
        hooks = {},          -- class hook call counts
        hook_args = {},      -- class hook argument captures
        counts = {},         -- fixture-level counters
        lrc_stats = { harm_max = 0, harm_min = 0, range = 0 },
        checker_calls = 0,
        in_melee = true,     -- what the LRC checker stub answers
        use_offhand = false,
        diag = { calls = 0, verbose_calls = 0 },
        engine_mode = engine_mode,
    }
    local function bump(key)
        sb.counts[key] = (sb.counts[key] or 0) + 1
    end

    -- The live range checker the LRC stub hands out (melee and ranged both).
    sb.checker = function(unit)
        sb.checker_calls = sb.checker_calls + 1
        return sb.in_melee
    end

    -- Frame stub: every call is recorded so the init-order guards can assert that a
    -- pre-init handler never touched a frame. Only the members main.lua's own code
    -- paths call are real; data fields stay plain values.
    local function make_frame(label)
        local f = { label = label, scripts = {}, shown = false }
        local function touch(op)
            sb.touches[#sb.touches + 1] = label .. ":" .. op
        end
        function f:SetScript(event, fn)
            touch("SetScript(" .. tostring(event) .. ")")
            self.scripts[event] = fn
        end
        function f:GetScript(event) return self.scripts[event] end
        function f:Show() self.shown = true; touch("Show") end
        function f:Hide() self.shown = false; touch("Hide") end
        function f:IsShown() return self.shown end
        function f:SetMovable(v) touch("SetMovable(" .. tostring(v) .. ")") end
        function f:EnableMouse(v) touch("EnableMouse") end
        function f:SetAlpha(v) touch("SetAlpha") end
        function f:SetPoint(...) touch("SetPoint") end
        function f:ClearAllPoints() touch("ClearAllPoints") end
        function f:SetWidth(w) touch("SetWidth") end
        function f:SetHeight(h) touch("SetHeight") end
        function f:RegisterForDrag(...) touch("RegisterForDrag") end
        return f
    end
    sb.make_frame = make_frame

    -- The addon object LibStub("AceAddon-3.0"):NewAddon returns: the Ace mixin surface
    -- main.lua calls (AceConsole Print, AceEvent RegisterEvent, AceConsole commands).
    -- main.lua itself then attaches every handler it defines.
    local ST = {}
    function ST:RegisterEvent(event) sb.events[event] = (sb.events[event] or 0) + 1 end
    function ST:RegisterUnitEvent(event) sb.unit_events[event] = (sb.unit_events[event] or 0) + 1 end
    function ST:RegisterChatCommand(command, method) sb.commands[command] = method end
    function ST:Print(msg) sb.notices[#sb.notices + 1] = tostring(msg) end

    -- Library fixtures ------------------------------------------------------------------
    local LRC = {
        CHECKERS_CHANGED = "CHECKERS_CHANGED",
        MeleeRange = -1,
        RegisterCallback = function(_, event, fn) sb.lrc_cb[event] = fn end,
        GetHarmMaxChecker = function(_, range)
            sb.lrc_stats.harm_max = sb.lrc_stats.harm_max + 1
            return sb.checker
        end,
        GetHarmMinChecker = function(_, range)
            sb.lrc_stats.harm_min = sb.lrc_stats.harm_min + 1
            return sb.checker
        end,
        GetRange = function(_, unit)
            sb.lrc_stats.range = sb.lrc_stats.range + 1
            return 0, 8
        end,
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
    sb.LRC, sb.LLM, sb.LGC = LRC, LLM, LGC

    local LSM = {
        Register = function(_, mediatype, key, path)
            sb.lsm[#sb.lsm + 1] = { media = mediatype, key = key, path = path }
        end,
        Fetch = function() return nil end,
    }
    local LWIN = { OnMouseWheel = function() end }

    local vendored_engine = {
        RegisterCallback = function(_, event, fn) sb.stl_cb[event] = fn end,
        UnregisterCallback = function() end,
        SwingTimerInfo = function(_, hand)
            bump("stl_info")
            return 2.6, sb.clock + 2.6, sb.clock
        end,
    }
    local source_engine = {
        available = engine_mode == "forever",
        RegisterCallback = function(_, event, fn) sb.source_cb[event] = fn end,
        UnregisterCallback = function() end,
        SwingTimerInfo = function(_, hand)
            bump("source_info")
            return 3.4, sb.clock + 3.4, sb.clock
        end,
    }

    -- The addon database AceDB would have built (config.lua's defaults are irrelevant
    -- here; only the keys main.lua's own code reads appear).
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
    local profile = {
        welcome_message = false,
        latency_scale_factor = 1,
        latency_linear_offset = 0,
        gcd_marker_offset_mode = "Off",
        PALADIN = class_db,
    }
    sb.db = { profile = profile, profilename = "Default" }
    sb.profile = profile
    sb.class_db = class_db

    local AC = { RegisterOptionsTable = function() bump("ac_register") end }
    local ACD = {
        AddToBlizOptions = function() bump("acd_bliz") end,
        Open = function(_, name) sb.acd_opened[#sb.acd_opened + 1] = name end,
    }
    local ACDO = { GetOptionsTable = function() return {} end }
    local ACE_DB = {
        New = function(_, name, defaults)
            sb.acedb_new[#sb.acedb_new + 1] = { name = name, defaults = defaults }
            return sb.db
        end,
    }

    local env = setmetatable({}, { __index = _G })
    env.WOW_PROJECT_ID = opts.project or 11
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_FOREVER = 18
    -- main.lua defines table.pack at load: give the sandbox its own facade so the
    -- shared _G.table is not written to.
    env.table = setmetatable({}, { __index = _G.table })
    env.GetTime = function() return sb.clock end
    env.GetTimePreciseSec = function() return sb.clock end
    env.GetBuildInfo = function() return "3.3.5", "12340", "today", opts.interface or 38002 end
    env.floor = math.floor
    env.UnitClass = function() return "Paladin", "PALADIN" end
    env.UnitGUID = function() return "Player-0000-0001" end
    env.UnitExists = function() return false end
    env.UnitCanAttack = function() return false end
    env.GetActiveTalentGroup = function() return 1 end
    env.GetShapeshiftForm = function() return 0 end
    env.IsCurrentSpell = function() return false end
    env.UnitAttackSpeed = function(unit)
        bump("attack_speed")
        return 3.6, sb.use_offhand and 1.5 or 0
    end
    env.UnitRangedDamage = function() return 0 end
    env.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, msg) sb.chatter[#sb.chatter + 1] = tostring(msg) end,
    }
    env.C_Timer = {
        After = function(delay, fn) sb.after[#sb.after + 1] = { delay = delay, cb = fn } end,
        NewTimer = function(delay, fn)
            local timer = { delay = delay, cb = fn, cancelled = false }
            function timer:Cancel() self.cancelled = true end
            sb.new_timers[#sb.new_timers + 1] = timer
            return timer
        end,
    }
    env.CreateFrame = function(kind, name)
        bump("create_frame")
        return make_frame(tostring(name or kind or "frame"))
    end
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { NewAddon = function() return ST end, GetAddon = function() return ST end }
        elseif major == "LibSharedMedia-3.0" then
            return LSM
        elseif major == "LibClassicSwingTimerAPI" then
            if engine_mode == "vendored" then
                return vendored_engine
            end
            return nil
        elseif major == "LibRangeCheck-2.0" then
            return LRC
        elseif major == "LibLatencyMonitor" then
            return LLM
        elseif major == "LibGlobalCooldown" then
            return LGC
        elseif major == "LibWindow-1.1" then
            return LWIN
        elseif major == "AceDB-3.0" then
            return ACE_DB
        elseif major == "AceConfig-3.0" then
            return AC
        elseif major == "AceConfigDialog-3.0" then
            return ACD
        elseif major == "AceDBOptions-3.0" then
            return ACDO
        end
        return nil
    end

    -- compat.lua reads several legacy globals through rawget(_G, ...); mirror every stub
    -- into _G for the duration of its load, then restore _G exactly.
    local mirrored = {}
    for name, value in pairs(env) do
        mirrored[name] = rawget(_G, name)
        _G[name] = value
    end
    local st = {}
    local compat = assert(loadfile(ROOT .. "compat.lua"))
    setfenv(compat, env)
    compat("SwedgeTimer", st)
    for name, previous in pairs(mirrored) do
        _G[name] = previous
    end

    local utils = assert(loadfile(ROOT .. "utils.lua"))
    setfenv(utils, env)
    utils("SwedgeTimer", st)

    -- The namespace contents main.lua's load reads beyond compat/utils. The Forever
    -- swing source only exists where the real swing_source.lua would have set it; the
    -- diagnostic module is stubbed (diag.lua loads earlier in the real TOC; here only
    -- the call has to be observable).
    if engine_mode == "forever" or engine_mode == "forever-inert" then
        st.swing_source = source_engine
    end
    st.diag = {
        report = function(self, verbose)
            sb.diag.calls = sb.diag.calls + 1
            if verbose then sb.diag.verbose_calls = sb.diag.verbose_calls + 1 end
            sb.diag.last_self = self
        end,
    }

    local main_chunk = assert(loadfile(ROOT .. "main.lua"))
    setfenv(main_chunk, env)
    local ok, err = pcall(main_chunk, "SwedgeTimer", st)
    if not ok then
        print("FAIL  main.lua does not load under the sandbox: " .. tostring(err))
        os.exit(1)
    end

    -- main.lua has run: ST now owns every handler it defines. Attach the external
    -- surface the rest of the TOC provides (config.lua sets the defaults, bars.lua adds
    -- the visual update entry points, classes/* attach their hooks).
    ST.defaults = {}
    ST.set_opts = function(self)
        bump("set_opts")
        self.opts_table = {}
    end
    ST.init_visuals_template = function() bump("init_visuals") end
    ST.set_bar_texts = function() bump("set_texts") end
    ST.on_latency_update = function() bump("latency_update") end
    ST.set_gcd_marker_positions = function() bump("gcd_marker") end
    ST.on_bar_inactive = function() bump("bar_inactive") end
    ST.on_bar_active = function() bump("bar_active") end
    ST.on_attack_speed_change = function() bump("attack_speed_change") end
    ST.on_gcd_length_change = function() bump("gcd_length_change") end
    ST.set_bar_color = function() bump("bar_color") end

    ST.PALADIN = ST.PALADIN or {}
    for i = 1, #HOOK_NAMES do
        local name = HOOK_NAMES[i]
        sb.hooks[name] = 0
        ST.PALADIN[name] = function(...)
            sb.hooks[name] = sb.hooks[name] + 1
            sb.hook_args[name] = capture_args(...)
        end
    end

    -- The hand containers exist on ST (main.lua built them); the anchor frames are
    -- normally created by bars.lua. Only the hands a paladin iterates need one.
    ST.mainhand.anchor_frame = make_frame("mainhand.anchor")
    local anchor = ST.mainhand.anchor_frame
    anchor.hiding_anchor_frame = make_frame("mainhand.hiding")
    anchor.bar_frame = make_frame("mainhand.bar")
    anchor.bar_frame.visuals_frame = make_frame("mainhand.visuals")
    anchor.bar_frame.visuals_frame.gcd_bar = make_frame("mainhand.gcd_bar")
    ST.mainhand.onupdate = function() end

    sb.ST = ST
    sb.st = st
    return { env = env, st = st, ST = ST, sb = sb }
end

--=========================================================================================
-- Boot helpers
--=========================================================================================
-- Models PLAYER_LOGIN: LibGlobalCooldown's first GCD_DURATIONS_UPDATED report, which the
-- real library fires from its PLAYER_LOGIN handler (LibGlobalCooldown.lua:152-175).
local function report_login(b)
    local cb = b.sb.lgc_cb["GCD_DURATIONS_UPDATED"]
    assert(cb, "OnInitialize registered the GCD_DURATIONS_UPDATED callback")
    cb("GCD_DURATIONS_UPDATED", 1.5, 1.5)
end

local function boot(opts)
    local b = build(opts)
    b.ST:OnInitialize()
    if not (opts and opts.report_login == false) then
        report_login(b)
    end
    return b
end

local function find_timer(b, delay)
    for i = 1, #b.sb.after do
        if b.sb.after[i].delay == delay then
            return b.sb.after[i]
        end
    end
    return nil
end

local function fire_deadline(b)
    local timer = find_timer(b, 5)
    assert(timer, "the 5 s init deadline is armed")
    timer.cb()
end

local function fire_stl_ready(b)
    local cb = b.sb.stl_cb["SWING_TIMER_INFO_INITIALIZED"]
    assert(cb, "the vendored engine's SWING_TIMER_INFO_INITIALIZED callback is registered")
    cb()
end

local function fire_source_ready(b)
    local cb = b.sb.source_cb["SWING_TIMER_INFO_INITIALIZED"]
    assert(cb, "the Forever source's SWING_TIMER_INFO_INITIALIZED callback is registered")
    cb()
end

local function fire_lrc_checkers(b)
    local cb = b.sb.lrc_cb[b.sb.LRC.CHECKERS_CHANGED]
    assert(cb, "the LRC CHECKERS_CHANGED callback is registered")
    cb()
end

-- Resolves and runs a captured chat command exactly like AceConsole does for a string
-- method name: self[method](self, input).
local function run_cmd(b, command, input)
    local method = b.sb.commands[command]
    assert(method, "the /" .. tostring(command) .. " chat command is registered")
    local fn = b.ST[method]
    assert(type(fn) == "function", "the registered method " .. tostring(method) .. " exists on ST")
    return fn(b.ST, input)
end

local function hook_snapshot(b)
    local out = {}
    for k, v in pairs(b.sb.hooks) do
        out[k] = v
    end
    return out
end

local function hooks_unchanged(b, before, label)
    local changed = {}
    for k, v in pairs(b.sb.hooks) do
        if before[k] ~= v then
            changed[#changed + 1] = k
        end
    end
    eq(#changed, 0, label .. "  (changed: " .. table.concat(changed, ",") .. ")")
end

local function touched_since(b, mark, needle)
    for i = mark + 1, #b.sb.touches do
        if b.sb.touches[i]:find(needle, 1, true) then
            return true
        end
    end
    return false
end

--=========================================================================================
-- 1) The init deadline: LibRangeCheck never reports
--=========================================================================================
do
    local b = boot()
    local T, F = b.ST, b.sb

    eq(T.interfaces_are_initialised, false, "init has not run before the libraries report")
    eq(T.lrc_ready, false, "LRC is not ready before its callback")
    eq(T.stl_ready, false, "a vendored engine is not ready before its callback")
    eq(T.init_deadline_fired, nil, "the deadline flag is not set before the deadline")
    check(find_timer(b, 5) ~= nil, "the 5 s init deadline is armed by OnInitialize")

    -- The engine reports ready in time; LRC never does.
    fire_stl_ready(b)
    eq(T.stl_ready, true, "the engine callback marks the engine ready")
    eq(T.interfaces_are_initialised, false, "init still waits for LRC")

    fire_deadline(b)
    eq(T.init_deadline_fired, true, "the deadline records that it fired")
    eq(T.lrc_unavailable, true, "the deadline flips lrc_unavailable")
    eq(T.lrc_ready, true, "the deadline treats LRC as settled (disabled for the session)")
    eq(T.interfaces_are_initialised, true, "initialisation proceeds after the deadline")

    -- Exactly one notice: the range-checking disable (no welcome, engine available).
    eq(#F.notices, 1, "the deadline rescue prints exactly one notice")
    eq(F.notices[1], "Range checking is unavailable on this client; the range display is disabled.",
        "the notice is the range-checking disable")

    -- Range finders skipped entirely: nothing was requested from the library, and the
    -- retry loop did not start.
    eq(F.lrc_stats.harm_max, 0, "no harm checker was requested while LRC is disabled")
    eq(F.lrc_stats.range, 0, "no range read while LRC is disabled")
    eq(T.rangefinder_interval, nil, "init_range_finders did not start")

    --  and init ran exactly once.
    eq(F.counts.init_visuals, 1, "the visual template is initialised once")
    eq(F.counts.set_texts, 1, "the bar texts are initialised once")
    eq(F.hooks.post_init, 1, "the class post_init hook ran once")
    eq(F.diag.calls, 1, "the diagnostic self-report ran once")
    near(T.mainhand.speed, 2.6, "the vendored engine's swing speed was used")

    -- The deadline callback is idempotent once init has run.
    fire_deadline(b)
    eq(F.hooks.post_init, 1, "re-firing the deadline does not re-run init")
    eq(#F.notices, 1, "re-firing the deadline does not re-print the notice")
    eq(F.diag.calls, 1, "re-firing the deadline does not re-report diag")
end

--=========================================================================================
-- 1b) The init deadline: neither library ever reports
--=========================================================================================
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_deadline(b)
    eq(T.lrc_unavailable, true, "LRC is disabled by the deadline")
    eq(T.stl_ready, true, "the deadline settles the engine flag")
    eq(T.swing_engine, "inert-standin", "a never-ready engine is replaced by the inert stand-in")
    eq(T.interfaces_are_initialised, true, "init proceeds once the deadline settles both sides")
    eq(#F.notices, 2, "the rescue prints both unavailability notices")
    eq(F.notices[1], "Swing timer bars are unavailable on this client; range and GCD features remain active.",
        "the engine loss is reported first")
    eq(F.notices[2], "Range checking is unavailable on this client; the range display is disabled.",
        "the range loss is reported second")
    eq(T.mainhand.speed, nil, "init_timers reads the replacement stub's unknown shape (no fake cycle)")
    eq(T.mainhand.ends_at, nil, "the stand-in has no invented expiration")
    eq(T.mainhand.engine_dead, true, "the stand-in marks the hand engine_dead for the bar render")

    -- A late report from the engine that never made it changes nothing now.
    fire_stl_ready(b)
    eq(F.hooks.post_init, 1, "a late engine report does not re-run init")
    eq(#F.notices, 2, "a late engine report does not re-print the notices")
end

--=========================================================================================
-- 2) Late-library recovery: checkers arrive after the deadline
--=========================================================================================
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_deadline(b)
    local notices_after_deadline = #F.notices
    local post_init_calls = F.hooks.post_init

    -- The callback lifts the disable and brings range checking up through
    -- init_range_finders, without a second initialisation.
    fire_lrc_checkers(b)
    eq(T.lrc_unavailable, false, "a late CHECKERS_CHANGED lifts the disable")
    eq(T.rangefinder_interval, 0.05, "the range finder interval is set on recovery")
    check(type(T.melee_range_checker_func) == "function", "the melee checker is resolved on recovery")
    check(type(T.ranged_range_checker_func) == "function", "the ranged checker is resolved on recovery")
    eq(F.lrc_stats.harm_max, 2, "recovery requests both checkers (melee + ranged)")
    eq(F.checker_calls, 2, "the first range poll ran both checkers once")
    eq(T.in_melee_range, true, "the first poll stores the checker's melee reading")
    eq(T.in_ranged_range, false, "an in-melee target is not also ranged")
    eq(F.lrc_stats.range, 1, "the first poll reads the target range once")

    -- The poll loop is alive: the first poll re-armed a fresh interval timer, and firing
    -- it reads the checkers again and arms the next interval.
    local poll = find_timer(b, 0.05)
    check(poll ~= nil, "the range poll re-arms itself")
    local timers_before = #F.after
    if poll then
        poll.cb()
    end
    eq(#F.after, timers_before + 1, "the followed-up poll arms the next interval")
    eq(F.checker_calls, 4, "the followed-up poll reads both checkers again")

    -- Recovery must not look like a second initialisation.
    eq(F.hooks.post_init, post_init_calls, "recovery does not re-run post_init")
    eq(#F.notices, notices_after_deadline, "recovery does not re-print the notice")
    eq(F.diag.calls, 1, "recovery does not re-report diag")
end

--=========================================================================================
-- 3) Normal init in both callback orders; the deadline stays silent
--=========================================================================================
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(T.interfaces_are_initialised, true, "both libraries ready -> init runs")
    eq(T.lrc_unavailable, false, "no disable without the deadline")
    eq(T.init_deadline_fired, nil, "the deadline did not fire")
    eq(#F.notices, 0, "a healthy init prints no notices")
    eq(F.hooks.post_init, 1, "post_init ran once")
    eq(F.diag.calls, 1, "diag ran once")
    eq(F.lrc_stats.harm_max, 2, "both checkers were requested")
    near(T.mainhand.speed, 2.6, "the vendored engine's speed was read")
    eq(F.counts.stl_info, 1, "SwingTimerInfo was read once (one hand)")

    -- Firing the deadline after a successful init is a no-op.
    fire_deadline(b)
    eq(T.init_deadline_fired, nil, "the deadline may not fire after init")
    eq(F.hooks.post_init, 1, "no second init after the deadline")
    eq(#F.notices, 0, "no notice after the deadline")
end
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_lrc_checkers(b)
    eq(T.interfaces_are_initialised, false, "LRC alone does not initialise")
    fire_stl_ready(b)
    eq(T.interfaces_are_initialised, true, "the engine's late report completes init")
    eq(F.hooks.post_init, 1, "init still ran exactly once")
    eq(#F.notices, 0, "no notice")
end

--=========================================================================================
-- 4) Dispatch arg convention: the EVENT NAME is the first forwarded argument
--=========================================================================================
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)

    -- Spellcast lifecycle through the real AceEvent dispatch entry.
    T.callback_event_handler("UNIT_SPELLCAST_START", "player", "cast-guid-1", 12345)
    local a = F.hook_args.on_spellcast_event
    check(a ~= nil, "the class spellcast hook received the dispatch")
    if a then
        eq(a.n, 5, "the class hook is called with self + event + three payload args")
        eq(a[1], T, "the class hook receives the addon object first")
        eq(a[2], "UNIT_SPELLCAST_START", "the EVENT NAME is the first forwarded argument")
        eq(a[3], "player", "the unit follows the event name")
        eq(a[4], "cast-guid-1", "the cast guid follows the unit")
        eq(a[5], 12345, "the spell id follows the cast guid")
    end
    eq(F.hooks.on_spellcast_event, 1, "the hook ran once")

    -- Nilable trailing args are passed through untouched (UNIT_SPELLCAST_STOP may omit
    -- the spell id) and a direct handler call dispatches identically.
    T:UNIT_SPELLCAST_STOP("UNIT_SPELLCAST_STOP", "player", "cast-guid-2", nil)
    a = F.hook_args.on_spellcast_event
    eq(a.n, 5, "the nil spell id keeps the argument count")
    eq(a[2], "UNIT_SPELLCAST_STOP", "the event name is preserved for STOP")
    eq(a[5], nil, "the nil spell id stays nil")
    eq(F.hooks.on_spellcast_event, 2, "the direct handler call dispatches too")

    -- Non-player units never reach the class hook.
    T.callback_event_handler("UNIT_SPELLCAST_START", "target", "cast-guid-3", 999)
    eq(F.hooks.on_spellcast_event, 2, "a non-player unit is filtered before the class hook")

    -- CLEU forwards the event name into the paladin twist chain.
    T.callback_event_handler("COMBAT_LOG_EVENT_UNFILTERED", "SPELL_DAMAGE",
        "Player-1", "Caster", 111, 222, 333, 0)
    local c = F.hook_args.on_combat_log_unfiltered
    check(c ~= nil, "the CLEU chain reached the class hook")
    if c then
        eq(c[1], T, "the CLEU hook receives the addon object first")
        eq(c[2], "COMBAT_LOG_EVENT_UNFILTERED", "the CLEU hook receives the EVENT NAME first")
        eq(c[3], "SPELL_DAMAGE", "the CLEU hook receives the payload after the event name")
    end
end

--=========================================================================================
-- 4b) Library callbacks registered with callback_event_handler keep the convention
--=========================================================================================
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)

    -- LibGlobalCooldown.
    F.lgc_cb["GCD_STARTED"]("GCD_STARTED", 1.2, 101.2)
    eq(T.gcd.duration, 1.2, "GCD_STARTED stores the duration")
    eq(T.gcd.expires, 101.2, "GCD_STARTED stores the expiry")
    F.lgc_cb["GCD_DURATIONS_UPDATED"]("GCD_DURATIONS_UPDATED", 1.6, 1.4)
    eq(T.gcd.phys_length, 1.6, "GCD_DURATIONS_UPDATED stores the physical length")
    eq(T.gcd.spell_length, 1.4, "GCD_DURATIONS_UPDATED stores the spell length")
    near(T.gcd.gcd1_phys_time_before_swing, 1.6, "the marker time is rebuilt from the new length")
    eq(F.counts.gcd_length_change, 1, "the post-init length change reaches its handler")
    local touches = #F.touches
    F.lgc_cb["GCD_OVER"]("GCD_OVER")
    eq(T.gcd.expires, nil, "GCD_OVER clears the expiry")
    check(touched_since(b, touches, "gcd_bar:Hide"), "GCD_OVER hides the gcd bar through the visuals frame")

    -- LibLatencyMonitor: the calibrated latencies and the marker rebuild.
    local latency_before = F.counts.latency_update
    F.llm_cb[F.LLM.LATENCY_CHANGED]("LATENCY_CHANGED", 60, 150)
    eq(T.latency.home_ms, 60, "LATENCY_CHANGED stores the home latency")
    eq(T.latency.world_ms, 150, "LATENCY_CHANGED stores the world latency")
    eq(T.latency.calibrated_world_ms, 150, "the calibrated latency applies the profile scale")
    eq(F.counts.latency_update, latency_before + 1, "the post-init latency change runs on_latency_update")
end

--=========================================================================================
-- 4c) Callback fan-out isolation (H3): one throwing handler is contained and counted
--=========================================================================================
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    local notices_before = #F.notices

    local original = T.GCD_STARTED
    T.GCD_STARTED = function() error("handler exploded") end
    local ok, err = pcall(T.callback_event_handler, "GCD_STARTED", 1.2, 101.2)
    check(ok, "a throwing lib callback does not escape the fan-out (" .. tostring(err) .. ")")
    eq(type(T.callback_errors), "table", "the fan-out keeps a per-event error counter")
    eq(T.callback_errors.GCD_STARTED, 1, "the first throw is counted")
    eq(#F.notices, notices_before + 1, "the first throw prints one chat notice")
    contains(F.notices[#F.notices], "GCD_STARTED", "the notice names the failing callback")
    check(T.gcd.duration == nil, "the throwing handler's own state change did not happen")

    T.callback_event_handler("GCD_STARTED", 1.2, 101.2)
    eq(T.callback_errors.GCD_STARTED, 2, "the second throw increments the same counter")
    eq(#F.notices, notices_before + 1, "repeated throws do not spam the chat")

    -- A missing handler is ignored (a stale registration must not throw into the
    -- library's Fire), and the healthy handlers keep working afterwards.
    local ok_missing = pcall(T.callback_event_handler, "NOT_A_HANDLER")
    check(ok_missing, "a callback with no handler does not throw")
    T.GCD_STARTED = original
    T.callback_event_handler("GCD_STARTED", 1.5, 102.5)
    eq(T.gcd.duration, 1.5, "the restored handler runs normally after the isolated throws")
end

--=========================================================================================
-- 5) Init-order guards: pre-init handlers do nothing and touch nothing
--=========================================================================================
-- Phase A: before OnInitialize even ran (the worst case).
do
    local b = build({ report_login = false })
    local T, F = b.ST, b.sb
    T.has_oh = true -- defeat PLAYER_TARGET_SET_ATTACKING's secondary has_oh guard
    local PRE = {
        { "UNIT_POWER_FREQUENT", { "UNIT_POWER_FREQUENT", "player", "RAGE" } },
        { "UNIT_SPELLCAST_SUCCEEDED", { "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 48996 } },
        { "UNIT_SPELLCAST_START", { "UNIT_SPELLCAST_START", "player", "cast-2", 403 } },
        { "UNIT_SPELLCAST_DELAYED", { "UNIT_SPELLCAST_DELAYED", "player", "cast-2", 403 } },
        { "UNIT_SPELLCAST_STOP", { "UNIT_SPELLCAST_STOP", "player", "cast-2", 403 } },
        { "UNIT_SPELLCAST_INTERRUPTED", { "UNIT_SPELLCAST_INTERRUPTED", "player", "cast-2", 403 } },
        { "UNIT_SPELLCAST_FAILED", { "UNIT_SPELLCAST_FAILED", "player", "cast-2", 403 } },
        { "UNIT_SPELLCAST_CHANNEL_START", { "UNIT_SPELLCAST_CHANNEL_START", "player", "cast-2", 403 } },
        { "UNIT_SPELLCAST_CHANNEL_STOP", { "UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-2", 403 } },
        { "CURRENT_SPELL_CAST_CHANGED", { "CURRENT_SPELL_CAST_CHANGED", false } },
        { "PLAYER_EQUIPMENT_CHANGED", { "PLAYER_EQUIPMENT_CHANGED", 16, true } },
        { "PLAYER_TARGET_SET_ATTACKING", { "PLAYER_TARGET_SET_ATTACKING" } },
    }
    local before = hook_snapshot(b)
    for i = 1, #PRE do
        local ok, err = pcall(T[PRE[i][1]], T, unpack(PRE[i][2]))
        check(ok, "pre-OnInitialize " .. PRE[i][1] .. " does not error (" .. tostring(err) .. ")")
    end
    local ok_gcd, err_gcd = pcall(T.GCD_OVER, T)
    check(ok_gcd, "pre-OnInitialize GCD_OVER does not error (" .. tostring(err_gcd) .. ")")

    eq(#F.touches, 0, "no pre-OnInitialize handler touched a frame")
    hooks_unchanged(b, before, "no pre-OnInitialize handler reached a class hook")
    eq(T.interfaces_are_initialised, false, "init still has not run")
    eq(T.gcd, nil, "GCD_OVER did not create the gcd container before OnInitialize")
    eq(T.offhand.start, nil, "PLAYER_TARGET_SET_ATTACKING left the offhand timer alone")
    eq(F.counts.attack_speed or 0, 0, "PLAYER_EQUIPMENT_CHANGED did not re-check the weapons")
    eq(F.counts.bar_color or 0, 0, "no pre-init recolour")
end

-- Phase B: inside the real init window (OnInitialize ran, libraries have not reported).
do
    local b = boot()
    local T, F = b.ST, b.sb
    T.has_oh = true
    T.gcd.expires = 123
    local PRE = {
        { "UNIT_POWER_FREQUENT", { "UNIT_POWER_FREQUENT", "player", "RAGE" } },
        { "UNIT_SPELLCAST_SUCCEEDED", { "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 48996 } },
        { "UNIT_SPELLCAST_START", { "UNIT_SPELLCAST_START", "player", "cast-2", 403 } },
        { "UNIT_SPELLCAST_DELAYED", { "UNIT_SPELLCAST_DELAYED", "player", "cast-2", 403 } },
        { "UNIT_SPELLCAST_STOP", { "UNIT_SPELLCAST_STOP", "player", "cast-2", 403 } },
        { "UNIT_SPELLCAST_INTERRUPTED", { "UNIT_SPELLCAST_INTERRUPTED", "player", "cast-2", 403 } },
        { "UNIT_SPELLCAST_FAILED", { "UNIT_SPELLCAST_FAILED", "player", "cast-2", 403 } },
        { "UNIT_SPELLCAST_CHANNEL_START", { "UNIT_SPELLCAST_CHANNEL_START", "player", "cast-2", 403 } },
        { "UNIT_SPELLCAST_CHANNEL_STOP", { "UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-2", 403 } },
        { "CURRENT_SPELL_CAST_CHANGED", { "CURRENT_SPELL_CAST_CHANGED", false } },
        { "PLAYER_EQUIPMENT_CHANGED", { "PLAYER_EQUIPMENT_CHANGED", 16, true } },
        { "PLAYER_TARGET_SET_ATTACKING", { "PLAYER_TARGET_SET_ATTACKING" } },
    }
    local touches = #F.touches
    local before = hook_snapshot(b)
    for i = 1, #PRE do
        local ok, err = pcall(T[PRE[i][1]], T, unpack(PRE[i][2]))
        check(ok, "init-window " .. PRE[i][1] .. " does not error (" .. tostring(err) .. ")")
    end
    local ok_gcd, err_gcd = pcall(F.lgc_cb["GCD_OVER"], "GCD_OVER")
    check(ok_gcd, "init-window GCD_OVER does not error (" .. tostring(err_gcd) .. ")")

    eq(#F.touches, touches, "no init-window handler touched a frame")
    hooks_unchanged(b, before, "no init-window handler reached a class hook")
    eq(T.interfaces_are_initialised, false, "init still has not run")
    eq(T.gcd.expires, 123, "GCD_OVER left the init-window expiry alone")
    eq(T.offhand.start, nil, "PLAYER_TARGET_SET_ATTACKING left the offhand timer alone")
    eq(F.counts.attack_speed or 0, 0, "PLAYER_EQUIPMENT_CHANGED did not re-check the weapons")
    eq(F.counts.bar_color or 0, 0, "no init-window recolour")

    -- The events really are registered dispatch targets: the guards are the gate.
    check(F.events["UNIT_POWER_FREQUENT"] ~= nil, "UNIT_POWER_FREQUENT is registered by OnInitialize")
    check(F.events["UNIT_SPELLCAST_SUCCEEDED"] ~= nil, "UNIT_SPELLCAST_SUCCEEDED is registered")
    check(F.events["CURRENT_SPELL_CAST_CHANGED"] ~= nil, "CURRENT_SPELL_CAST_CHANGED is registered")
    check(F.events["PLAYER_EQUIPMENT_CHANGED"] ~= nil, "PLAYER_EQUIPMENT_CHANGED is registered")
    check(F.events["PLAYER_TARGET_SET_ATTACKING"] ~= nil, "PLAYER_TARGET_SET_ATTACKING is registered")
    check(F.lgc_cb["GCD_OVER"] ~= nil, "GCD_OVER is registered on LibGlobalCooldown")
end

-- Phase C: the same dispatches work after init - the guard was the only blocker.
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)

    T:UNIT_POWER_FREQUENT("UNIT_POWER_FREQUENT", "player", "RAGE")
    eq(F.hooks.on_rage_update, 1, "post-init rage events reach the class hook")
    T:UNIT_POWER_FREQUENT("UNIT_POWER_FREQUENT", "player", "MANA")
    eq(F.hooks.on_rage_update, 1, "a non-rage power type is filtered")

    local speed_before = F.counts.attack_speed
    T:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", 16, true)
    eq(F.counts.attack_speed, speed_before + 1, "equipping a weapon re-checks the weapons post-init")
    eq(F.counts.attack_speed_change, 1, "the re-check repaints the hand")
    T:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", 1, true)
    eq(F.counts.attack_speed, speed_before + 1, "an unrelated slot is ignored")

    T:CURRENT_SPELL_CAST_CHANGED("CURRENT_SPELL_CAST_CHANGED", true)
    eq(F.hooks.on_current_spell_cast_changed, 1, "post-init cast-queue changes reach the class hook")
    eq(F.hook_args.on_current_spell_cast_changed[2], true, "the is_cancelled flag is forwarded")

    T:UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-9", 48996)
    eq(F.hooks.on_spellcast_succeeded, 1, "post-init cast successes reach the class hook")
    local s = F.hook_args.on_spellcast_succeeded
    eq(s[2], "player", "the unit is the first payload argument")
    eq(s[3], "cast-9", "the cast guid follows")
    eq(s[4], 48996, "the spell id follows")

    -- The seven lifecycle handlers reach the same class hook once init is done: the
    -- early return is the only gate (H6).
    T:UNIT_SPELLCAST_START("UNIT_SPELLCAST_START", "player", "cast-10", 403)
    eq(F.hooks.on_spellcast_event, 1, "post-init START reaches the lifecycle class hook")
    eq(F.hook_args.on_spellcast_event[2], "UNIT_SPELLCAST_START",
        "the lifecycle hook still receives the event name first")
    T:UNIT_SPELLCAST_CHANNEL_STOP("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-10", nil)
    eq(F.hooks.on_spellcast_event, 2, "post-init CHANNEL_STOP reaches the lifecycle class hook")

    T.has_oh = true
    T.offhand.speed = 3.6
    T.offhand.start = 0
    T:PLAYER_TARGET_SET_ATTACKING("PLAYER_TARGET_SET_ATTACKING")
    eq(F.counts.bar_color, 1, "the offhand recolour runs post-init")
    near(T.offhand.start, F.clock - 3.6, "the offhand timer is snapped to now minus speed")
end

--=========================================================================================
-- 6) Swing-engine selection (the diag line's engine field)
--=========================================================================================
do
    local b = boot()
    local T, F = b.ST, b.sb
    eq(T.swing_engine, "vendored-lib", "the vendored library wins when present")
    eq(T.stl_ready, false, "a vendored engine waits for SWING_TIMER_INFO_INITIALIZED")
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(F.counts.stl_info, 1, "SwingTimerInfo was served by the vendored library")
    check(F.stl_cb["SWING_TIMER_UPDATE"] ~= nil, "the timer callbacks register on the vendored library")
end
do
    local b = boot({ engine = "forever", project = 18, interface = 16001 })
    local T, F = b.ST, b.sb
    eq(F.st.family, "FOREVER", "the fixture runs the Forever family")
    eq(T.swing_engine, "forever-source", "the Forever source is selected when the library is absent")
    eq(T.stl_ready, false, "the source engine waits for SWING_TIMER_INFO_INITIALIZED")
    check(F.source_cb["SWING_TIMER_INFO_INITIALIZED"] ~= nil,
        "the init-ready callback is registered on the source")
    fire_source_ready(b)
    eq(T.interfaces_are_initialised, false, "the source alone does not initialise")
    fire_lrc_checkers(b)
    eq(T.interfaces_are_initialised, true, "the source engine completes init")
    near(T.mainhand.speed, 3.4, "SwingTimerInfo comes from the source engine")
    eq(F.counts.source_info, 1, "the source engine served the one hand")
    check(F.source_cb["SWING_TIMER_UPDATE"] ~= nil, "the timer callbacks register on the source engine")
    eq(#F.notices, 0, "a working source engine prints no engine notice")
    check(not F.events["COMBAT_LOG_EVENT_UNFILTERED"], "no classic combat log on Mainline-code clients")
    check(not F.events["PLAYER_TARGET_SET_ATTACKING"], "no PLAYER_TARGET_SET_ATTACKING on Mainline-code clients")
    check(not F.events["START_AUTOREPEAT_SPELL"], "no auto-repeat events on Mainline-code clients")
end
do
    local b = boot({ engine = "forever-inert", project = 18, interface = 16001 })
    local T, F = b.ST, b.sb
    eq(T.swing_engine, "inert-standin", "an unavailable source falls back to the stand-in")
    eq(T.stl_ready, true, "the stand-in counts as ready")
    fire_lrc_checkers(b)
    eq(T.interfaces_are_initialised, true, "the stand-in client inits on LRC alone")
    eq(#F.notices, 1, "the stand-in prints the engine notice once")
    eq(F.notices[1], "Swing timer bars are unavailable on this client; range and GCD features remain active.",
        "the engine notice explains the stand-in")
    eq(T.mainhand.speed, nil, "the stand-in reports unknown, never a plausible 1 s cycle")
    eq(T.mainhand.engine_dead, true, "the stand-in marks the hand engine_dead")
end
do
    local b = boot({ engine = "absent", project = 1, interface = 120100 })
    local T, F = b.ST, b.sb
    eq(F.st.family, "RETAIL", "the fixture runs the Retail family")
    eq(T.swing_engine, "inert-standin", "no engine at all -> the inert stand-in")
    eq(T.stl_ready, true, "the stand-in counts as ready")
    check(F.events["PLAYER_EQUIPMENT_CHANGED"] ~= nil, "the Retail client still registers its events")
    check(not F.events["COMBAT_LOG_EVENT_UNFILTERED"], "Retail registers no classic combat log")
    fire_lrc_checkers(b)
    eq(T.interfaces_are_initialised, true, "init completes without any swing engine")
    eq(#F.notices, 1, "the Retail stand-in prints the engine notice once")
end

--=========================================================================================
-- 7) /st chat-command routing through the captured registration
--=========================================================================================
do
    local b = boot()
    local T, F = b.ST, b.sb

    eq(F.commands["st"], "open_menu", "the /st command routes to open_menu")
    eq(F.commands["swedgetimer"], "open_menu", "the /swedgetimer alias routes to open_menu")
    eq(F.commands["test1"], "test1", "the /test1 probe command is registered")

    -- No argument (and whitespace-only input) opens the options.
    run_cmd(b, "st", "")
    eq(F.acd_opened[1], "SwedgeTimer_Options", "an empty input opens the options window")
    run_cmd(b, "st", "   ")
    eq(F.acd_opened[2], "SwedgeTimer_Options", "whitespace-only input opens the options window")
    run_cmd(b, "swedgetimer", nil)
    eq(F.acd_opened[3], "SwedgeTimer_Options", "a nil input opens the options window through the alias")

    -- practice toggles st.practice_ui, else a notice.
    local practice = { toggles = 0, last_self = nil }
    F.st.practice_ui = {
        toggle = function(self)
            practice.toggles = practice.toggles + 1
            practice.last_self = self
        end,
    }
    run_cmd(b, "st", "practice")
    eq(practice.toggles, 1, "practice routes into st.practice_ui.toggle")
    eq(practice.last_self, T, "the toggle receives the addon object")
    run_cmd(b, "st", "  PRACTICE  ")
    eq(practice.toggles, 2, "the argument is trimmed and case-folded")
    F.st.practice_ui = nil
    run_cmd(b, "st", "practice")
    eq(F.notices[#F.notices], "Practice mode is not available on this client.",
        "without the module the practice route reports unavailability")

    -- design toggles st.designmode, else a notice.
    local design = { toggles = 0 }
    F.st.designmode = { toggle = function() design.toggles = design.toggles + 1 end }
    run_cmd(b, "st", "design")
    eq(design.toggles, 1, "design routes into st.designmode.toggle")
    F.st.designmode = nil
    run_cmd(b, "st", "design")
    eq(F.notices[#F.notices], "Design mode is not available on this client.",
        "without the module the design route reports unavailability")

    -- diag calls the verbose report, else a notice.
    local diag_before = F.diag.calls
    run_cmd(b, "st", "diag")
    eq(F.diag.calls, diag_before + 1, "diag routes into st.diag.report")
    eq(F.diag.verbose_calls, 1, "the diag route asks for the verbose report")
    eq(F.diag.last_self, T, "the report receives the addon object")
    contains(F.notices[#F.notices], "diag runtime",
        "the verbose diag route prints the runtime error counters")
    local diag_stub = F.st.diag
    F.st.diag = nil
    run_cmd(b, "st", "diag")
    eq(F.notices[#F.notices], "Diagnostics are not available on this client.",
        "without the module the diag route reports unavailability")
    F.st.diag = diag_stub

    -- Unknown arguments print the usage line.
    run_cmd(b, "st", "bogus")
    local usage = F.notices[#F.notices]
    contains(usage, "Unknown argument 'bogus'.", "the unknown argument is echoed")
    contains(usage, "Usage: /st practice", "the usage line lists the routes")
    run_cmd(b, "st", "DiAg ")
    eq(F.diag.calls, diag_before + 2, "the diag route is case-insensitive too")

    -- The test probe resolves and runs.
    check(type(T.test1) == "function", "ST:test1 exists for the registered probe command")
    local ok_test, err_test = pcall(run_cmd, b, "test1", "")
    check(ok_test, "the test1 probe command runs (" .. tostring(err_test) .. ")")
end

--=========================================================================================
-- 8) Idempotence: late reports and repeated callbacks never re-run init
--=========================================================================================
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    fire_deadline(b)
    eq(T.interfaces_are_initialised, true, "init stays initialised")
    eq(F.hooks.post_init, 1, "repeated reports never re-run post_init")
    eq(F.counts.init_visuals, 1, "repeated reports never re-init the visuals")
    eq(F.diag.calls, 1, "repeated reports never re-report diag")
    eq(#F.notices, 0, "repeated reports never print")
end

--=========================================================================================
-- 9) Defect pin: init completes even when LibGlobalCooldown never reported
--=========================================================================================
-- FOUND BY THIS SUITE: init_libs -> post_init -> set_gcd_times_before_swing_seconds
-- used to do `nil + offset` on the gcd bases, crashing the WHOLE init after
-- interfaces_are_initialised was already set. The rescue path exists precisely for a
-- library that never reports ready, and LibGlobalCooldown has no readiness gate, so a
-- broken LGC + healthy range/swing libraries produced a hard error instead of the
-- graceful degradation the init comments promise. main.lua now defaults both bases to
-- the documented 1.5 s pre-report value (the same fallback get_spell_gcd_duration
-- already applies to the spell gcd).
do
    -- 9a: the normal reports arrive (STL + LRC) while LGC stays silent.
    local b = boot({ report_login = false })
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    local ok, err = pcall(fire_lrc_checkers, b)
    check(ok, "init must not crash when LibGlobalCooldown never reported (" .. tostring(err) .. ")")
    check(T.interfaces_are_initialised, "init completed without a LibGlobalCooldown report")
    eq(F.hooks.post_init, 1, "post_init ran through the nil-safe gcd default")
    near(T.gcd.gcd1_phys_time_before_swing, 1.5, "the physical marker uses the 1.5 default")
    near(T.gcd.gcd1_spell_time_before_swing, 1.5, "the spell marker uses the 1.5 default")
    near(T.gcd.gcd2_phys_time_before_swing, 3.0, "the doubled physical marker uses the default")
    near(T.gcd.gcd2_spell_time_before_swing, 3.0, "the doubled spell marker uses the default")
    eq(T.gcd.phys_length, nil, "the container still waits for the library's own report")

    -- The late report still corrects every value.
    F.lgc_cb["GCD_DURATIONS_UPDATED"]("GCD_DURATIONS_UPDATED", 2.0, 1.2)
    eq(T.gcd.phys_length, 2.0, "the late report overwrites the physical length")
    near(T.gcd.gcd2_phys_time_before_swing, 4.0, "the markers recompute from the reported value")
end
do
    -- 9b: the deadline rescue runs with LGC silent (and no engine report either).
    local b = boot({ report_login = false })
    local T, F = b.ST, b.sb
    local ok, err = pcall(fire_deadline, b)
    check(ok, "the deadline rescue must not crash without a LibGlobalCooldown report ("
        .. tostring(err) .. ")")
    check(T.interfaces_are_initialised, "the deadline rescue completed")
    eq(F.hooks.post_init, 1, "the rescued init ran post_init once")
    near(T.gcd.gcd1_phys_time_before_swing, 1.5, "the rescued init keeps the 1.5 default")
    eq(#F.notices, 2, "the rescued init still prints its two unavailability notices")
end

--=========================================================================================
-- 10) rf_update dead-man: a throwing LRC poll disables range checking, never errors
--=========================================================================================
-- The vendored LibRangeCheck-2.0 is maintained for classic-line clients; the
-- IsEventValid event guards let its internals run on Retail/WoW Forever for the first
-- time, where a classic-only global can still make a poll throw. rf_update must catch
-- that, disable range checking through the same state + one-time notice as the init
-- deadline, and stop the retry loop - while a healthy poll stays byte-identical.
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)

    -- Healthy baseline: the init poll wrote the same state and re-armed the interval.
    eq(F.lrc_stats.range, 1, "the healthy init poll read the range once")
    eq(F.checker_calls, 2, "the healthy init poll called both checkers once")
    eq(T.in_melee_range, true, "the healthy poll stored the melee reading")
    eq(T.in_ranged_range, false, "the healthy poll derived ranged from melee")
    eq(T.target_min_range, 0, "the healthy poll stored the min range")
    eq(T.target_max_range, 8, "the healthy poll stored the max range")
    check(find_timer(b, 0.05) ~= nil, "the healthy poll armed the next interval")
    eq(#F.notices, 0, "the healthy poll printed nothing")

    -- The checker call explodes: bounded retry with backoff (M1), then session-disable.
    local range_before = F.lrc_stats.range
    local timers_before = #F.after
    local touches_before = #F.touches
    T.melee_range_checker_func = function() error("LRC checker exploded") end
    local ok, err = pcall(T.rf_update, T)
    check(ok, "a throwing checker poll does not error (" .. tostring(err) .. ")")
    eq(T.lrc_unavailable, false, "the first throw retries instead of disabling")
    eq(T.rf_failure_count, 1, "the first throw is counted")
    eq(#F.notices, 0, "the retry path prints nothing yet")
    eq(F.lrc_stats.range, range_before, "the throwing poll never reached the range read")
    eq(#F.after, timers_before + 1, "the first throw arms a backoff retry")
    eq(F.after[#F.after].delay, 0.05, "the first retry uses the base interval")

    -- Second consecutive throw: longer backoff, still no disable.
    F.after[#F.after].cb()
    eq(T.lrc_unavailable, false, "the second throw still retries")
    eq(T.rf_failure_count, 2, "the second throw is counted")
    eq(#F.after, timers_before + 2, "the second throw arms another retry")
    eq(F.after[#F.after].delay, 0.1, "the retry backs off exponentially (0.1 s)")

    -- Third consecutive throw: the bounded retry exhausts and disables the session.
    F.after[#F.after].cb()
    eq(T.lrc_unavailable, true, "the third consecutive throw disables range checking")
    eq(T.rf_failure_count, 3, "the exhausted retry keeps its count")
    eq(T.rf_disabled_after_failures, true, "the failure path records its terminal state")
    eq(#F.notices, 1, "the exhausted retry prints exactly one notice")
    eq(F.notices[1], "Range checking is unavailable on this client; the range display is disabled.",
        "the retry-exhaustion notice is the range-checking disable")
    eq(#F.after, timers_before + 2, "the terminal failure does not arm another retry")
    eq(#F.touches, touches_before, "the retry path touches no frames")

    -- Every later poll stops immediately: no library reads, no second notice.
    local calls_after_failure = F.checker_calls
    ok = pcall(T.rf_update, T)
    check(ok, "a poll after the disable still does not error")
    eq(F.checker_calls, calls_after_failure, "a disabled poll never calls a checker")
    eq(#F.after, timers_before + 2, "a disabled poll never reschedules")
    eq(#F.notices, 1, "the notice stays one-time")
end
do
    -- A successful poll between throws resets the consecutive counter.
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    local checker = T.melee_range_checker_func
    T.melee_range_checker_func = function() error("transient") end
    T.rf_update(T)
    eq(T.rf_failure_count, 1, "the transient throw starts the streak")
    T.melee_range_checker_func = checker
    F.after[#F.after].cb() -- retry succeeds
    eq(T.rf_failure_count, 0, "a successful retry resets the consecutive counter")
    eq(T.lrc_unavailable, false, "range checking stays alive after a recovered poll")
end
do
    -- The range read itself throws (the lib's GetRange internals).
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    F.LRC.GetRange = function() error("LRC GetRange exploded") end
    local timers_before = #F.after
    local ok, err = pcall(T.rf_update, T)
    check(ok, "a throwing GetRange poll does not error (" .. tostring(err) .. ")")
    eq(T.lrc_unavailable, false, "a GetRange throw retries first")
    F.after[#F.after].cb()
    F.after[#F.after].cb()
    eq(T.lrc_unavailable, true, "a sustained GetRange throw disables range checking")
    eq(#F.notices, 1, "a sustained GetRange throw prints the one-time notice")
    eq(#F.after, timers_before + 2, "the terminal failure stops the retry loop")
end
do
    -- The same failure inside the init poll: the disable lands before post_init, so the
    -- notice must be printed exactly once through the shared path (never twice).
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    F.LRC.GetHarmMaxChecker = function() return function() error("init poll exploded") end end
    fire_lrc_checkers(b)
    check(T.interfaces_are_initialised, "init completes despite the throwing first poll")
    eq(T.lrc_unavailable, false, "the init poll retries first")
    check(find_timer(b, 0.05) ~= nil, "the failing init poll arms its retry")
    F.after[#F.after].cb()
    F.after[#F.after].cb()
    eq(T.lrc_unavailable, true, "the sustained init-poll failure disables range checking")
    eq(#F.notices, 1, "the init poll failure prints the notice exactly once")
    eq(F.notices[1], "Range checking is unavailable on this client; the range display is disabled.",
        "the init poll notice is the range-checking disable")
    eq(F.hooks.post_init, 1, "post_init still runs after the disable")
end
do
    -- M2: a checker that never resolves is capped instead of re-arming forever.
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    T.melee_range_checker_func = nil
    T.rf_checker_laps = 99
    local timers_before = #F.after
    local ok, err = pcall(T.rf_update, T)
    check(ok, "the capped checker loop does not error (" .. tostring(err) .. ")")
    eq(T.rf_checker_laps, 100, "the checker loop counts its laps")
    eq(T.rf_checker_exhausted, true, "reaching the cap records the terminal state")
    eq(T.lrc_unavailable, true, "the cap folds into the range-disable state")
    eq(#F.notices, 1, "the cap prints the shared one-time notice")
    eq(#F.after, timers_before, "the cap arms no further checker lap")
end

--=========================================================================================
-- 11) TBC aura poll: 0.05 s re-parse of the player aura path (UNIT_AURA is unreliable there)
--=========================================================================================
-- Archive docs/swedge/SwedgeTimer_TBC/player.lua:913-918 polls
-- st.player.on_player_aura_change() every 0.05 s unconditionally (no combat gate, no
-- state-change skip). The live driver (ST:start_aura_poll / ST:aura_poll_tick in
-- main.lua) re-runs the UNIT_AURA handler's exact path (ST:class_on_aura_change,
-- with its interfaces_are_initialised guard) on the same cadence through the
-- rf_update-style C_Timer.After loop, TBC family only.
local function count_timers(b, delay)
    local n = 0
    for i = 1, #b.sb.after do
        if b.sb.after[i].delay == delay then
            n = n + 1
        end
    end
    return n
end
local function timers_at(b, delay)
    local out = {}
    for i = 1, #b.sb.after do
        if b.sb.after[i].delay == delay then
            out[#out + 1] = b.sb.after[i]
        end
    end
    return out
end
do
    -- 11a: TBC arms the loop at init; exactly one of the two 0.05 loops re-parses
    -- auras, and both loops persist.
    local b = boot({ project = 5, interface = 20506 })
    local T, F = b.ST, b.sb
    eq(F.st.family, "TBC", "the fixture runs the TBC family")
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    check(T.interfaces_are_initialised, "TBC init completed")
    eq(T.aura_poll_running, true, "TBC starts the aura poll at init")
    near(T.aura_poll_interval, 0.05, "the aura poll cadence is 0.05 s")
    local armed = timers_at(b, 0.05)
    eq(#armed, 2, "TBC arms both the range poll and the aura poll")
    local timers_before = #F.after
    local hooks_before = F.hooks.on_aura_change
    armed[1].cb()
    armed[2].cb()
    eq(F.hooks.on_aura_change, hooks_before + 1, "exactly one of the two 0.05 loops re-parses the player auras")
    eq(#F.after, timers_before + 2, "both 0.05 loops re-arm after firing")
    -- The re-armed pair keeps parsing: the aura loop persists across intervals.
    local rearmed = {}
    for i = timers_before + 1, #F.after do
        rearmed[#rearmed + 1] = F.after[i]
    end
    eq(#rearmed, 2, "both loops re-armed exactly one timer each")
    local hooks_mid = F.hooks.on_aura_change
    rearmed[1].cb()
    rearmed[2].cb()
    eq(F.hooks.on_aura_change, hooks_mid + 1, "the aura loop persists across intervals")
    -- The event path is unchanged on TBC.
    local hooks_event = F.hooks.on_aura_change
    T:UNIT_AURA("UNIT_AURA", "player")
    eq(F.hooks.on_aura_change, hooks_event + 1, "UNIT_AURA for the player still parses on TBC")
    T:UNIT_AURA("UNIT_AURA", "target")
    eq(F.hooks.on_aura_change, hooks_event + 1, "a non-player UNIT_AURA is still filtered on TBC")
    -- Starting twice never builds a second loop.
    local armed_before = #F.after
    T:start_aura_poll()
    eq(#F.after, armed_before, "a second start_aura_poll arms nothing")
end
do
    -- 11b: off TBC the driver is byte-identical -- no state, only the range poll is
    -- armed, and no 0.05 timer ever reaches the aura hook (Wrath is the regression
    -- baseline; Era/Retail/Forever spot-check the family gate).
    local b = boot()
    local T, F = b.ST, b.sb
    eq(F.st.family, "WRATH", "the fixture runs the Wrath family")
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(T.aura_poll_running, nil, "Wrath never starts the aura poll")
    eq(T.aura_poll_interval, nil, "Wrath sets no aura cadence")
    eq(count_timers(b, 0.05), 1, "only the range poll is armed off TBC")
    local hooks_before = F.hooks.on_aura_change
    for _ = 1, 3 do
        local pending = timers_at(b, 0.05)
        pending[#pending].cb()
    end
    eq(F.hooks.on_aura_change, hooks_before, "no 0.05 loop reaches the aura hook off TBC")
    eq(count_timers(b, 0.05), 4, "the off-TBC 0.05 loop re-arms exactly once per firing")
    -- The event path still works off TBC (it is the only aura trigger there).
    T:UNIT_AURA("UNIT_AURA", "player")
    eq(F.hooks.on_aura_change, hooks_before + 1, "UNIT_AURA still parses off TBC")
end
do
    -- Family-gate spot checks: Era, Retail (stand-in engine) and Forever arm nothing.
    local gates = {
        { name = "era", opts = { project = 2, interface = 11509 }, ready = "stl" },
        { name = "retail", opts = { engine = "absent", project = 1, interface = 120100 }, ready = "none" },
        { name = "forever", opts = { engine = "forever", project = 18, interface = 16001 }, ready = "source" },
    }
    for i = 1, #gates do
        local g = gates[i]
        local b = boot(g.opts)
        local T = b.ST
        if g.ready == "stl" then
            fire_stl_ready(b)
        elseif g.ready == "source" then
            fire_source_ready(b)
        end
        fire_lrc_checkers(b)
        check(T.interfaces_are_initialised, "the " .. g.name .. " client initialised")
        eq(T.aura_poll_running, nil, "the " .. g.name .. " client never starts the aura poll")
        eq(T.aura_poll_interval, nil, "the " .. g.name .. " client sets no aura cadence")
        eq(count_timers(b, 0.05), 1, "the " .. g.name .. " client arms only the range poll")
    end
end
do
    -- 11c: a TBC tick inside the init window parses nothing (the guard is the gate)
    -- but keeps the loop alive, exactly like the UNIT_AURA handler.
    local b = build({ project = 5, interface = 20506 })
    local T, F = b.ST, b.sb
    T:OnInitialize()
    eq(F.st.family, "TBC", "the guard fixture runs the TBC family")
    local before = hook_snapshot(b)
    local timers_before = #F.after
    local ok, err = pcall(T.aura_poll_tick, T)
    check(ok, "an init-window aura tick does not error (" .. tostring(err) .. ")")
    hooks_unchanged(b, before, "an init-window tick never reaches the class hook")
    eq(#F.after, timers_before + 1, "an init-window tick still re-arms the loop")
    local ok_aura, err_aura = pcall(T.UNIT_AURA, T, "UNIT_AURA", "player")
    check(ok_aura, "an init-window UNIT_AURA does not error (" .. tostring(err_aura) .. ")")
    hooks_unchanged(b, before, "an init-window UNIT_AURA never reaches the class hook either")
end

if failures == 0 then
    print("PASS  main_init_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  main_init_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
