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
-- Reads a repo file as text (the static pins read main.lua itself).
local function read(path)
    local f = assert(io.open(ROOT .. path, "r"))
    local text = f:read("*a")
    f:close()
    return text
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
--   class        the class token the client plays (default PALADIN). F2: a class
--                whose class_hands list holds "offhand" (WARRIOR, ROGUE, HUNTER,
--                SHAMAN) is needed to exercise the offhand bar paths - a paladin
--                or a druid has an offhand weapon but no offhand bar.
--   use_offhand  true makes UnitAttackSpeed report an offhand speed, i.e. the
--                player has an offhand weapon (the probe check_weapons reads).
local function build(opts)
    opts = opts or {}
    local engine_mode = opts.engine or "vendored"
    local class_token = opts.class or "PALADIN"
    local class_pretty = class_token:sub(1, 1):upper() .. class_token:sub(2):lower()

    local sb = {
        clock = 100,
        notices = {},        -- self:Print captures (the init_libs notices)
        chatter = {},        -- DEFAULT_CHAT_FRAME:AddMessage captures
        -- Every call that reaches the CLIENT's global print (not the addon's chat path)
        -- lands here. The sandbox has no global print of its own, so this spy is what
        -- turns "the module printed through the global" into an assertion instead of
        -- stray console output - see section 18.
        raw_prints = {},
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
        hook_order = {},     -- activation vs class post_init, in call order
        class_loaded = 0,    -- the class loader's call count
        counts = {},         -- fixture-level counters
        lrc_stats = { harm_max = 0, harm_min = 0, range = 0 },
        checker_calls = 0,
        in_melee = true,     -- what the LRC checker stub answers
        target_yards = 12,   -- exact yards api.UnitDistance reports (nil = unknown)
        unit_distance_calls = 0,
        use_offhand = opts.use_offhand == true,
        diag = { calls = 0, verbose_calls = 0, installs = 0, uninstalls = 0 },
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
    }
    profile[class_token] = class_db
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
    -- Exact target distance (compat.api.UnitDistance's source; R1). The flag is the
    -- client's "the reading was actually checked" bit: false (or nil yards) = unknown.
    env.UnitDistanceSquared = function(unit)
        sb.unit_distance_calls = sb.unit_distance_calls + 1
        if sb.target_yards == nil then
            return 0, false
        end
        return sb.target_yards * sb.target_yards, true
    end
    -- The live pull clock's source (BS-8 item 2): the player's target casting (the
    -- pre-pull projection reads the cast's end), and the two guards a pull needs -
    -- a group and an instance. opts.target_casting / cast_end_ms script the cast;
    -- opts.in_group / opts.in_instance script the guards.
    env.UnitCastingInfo = function(unit)
        if unit ~= "target" or not opts.target_casting then
            return nil
        end
        return "Some Boss Spell", nil, nil, 0, opts.cast_end_ms or 0, false, nil, false, 1234
    end
    env.IsInGroup = function() return opts.in_group ~= false end
    env.IsInInstance = function() return opts.in_instance ~= false end
    env.GetBuildInfo = function() return "3.3.5", "12340", "today", opts.interface or 38002 end
    env.floor = math.floor
    env.UnitClass = function() return class_pretty, class_token end
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
    -- The client's global print, spied. The addon's chat path is st.utils.print_msg
    -- (utils.lua -> DEFAULT_CHAT_FRAME:AddMessage), so a module that reaches the global
    -- instead shows up here - and never as stray console output.
    env.print = function(...)
        local first = select(1, ...)
        sb.raw_prints[#sb.raw_prints + 1] = tostring(first)
    end
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

    -- The house error contract (guard.lua) loads BEFORE main.lua in every TOC, so
    -- the sandbox mirrors that order: main.lua's logout flush runs under the real
    -- guard, and a failure lands in the counter /st diag reads.
    local guard = assert(loadfile(ROOT .. "guard.lua"))
    setfenv(guard, env)
    local ok_guard, err_guard = pcall(guard, "SwedgeTimer", st)
    check(ok_guard, "guard.lua loads under the sandbox (" .. tostring(err_guard) .. ")")
    check(type(st.guard) == "table" and type(st.guard.run) == "function",
        "the house error contract is available to main.lua")

    -- The module-parse trailers are st.debug-gated, and utils.lua sets that switch to
    -- false as it loads. opts.debug flips it back on AFTER utils.lua has loaded (so
    -- utils.lua's own trailer stays silent) but BEFORE main.lua loads, so main.lua's
    -- trailer is reachable and its output path is observable. Section 18 uses it.
    if opts.debug then
        st.debug = true
    end

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
        -- F1: the chained error handler's install/uninstall calls are observable.
        install_error_handler = function()
            sb.diag.installs = sb.diag.installs + 1
            return true
        end,
        uninstall_error_handler = function()
            sb.diag.uninstalls = sb.diag.uninstalls + 1
            return true
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

    -- The class loader the real classes/<class>.lua registers (operator order
    -- 2026-10-21: only the SELECTED class's module executes). main.lua activates the
    -- selected loader during init, so the hooks live INSIDE this loader: their absence
    -- before activation is the order proof, exactly as the real class body installs its
    -- hooks only when its loader runs.
    st.class_loaders = st.class_loaders or {}
    st.class_loaders[class_token] = function()
        sb.class_loaded = sb.class_loaded + 1
        sb.hook_order[#sb.hook_order + 1] = "activate"
        ST[class_token] = ST[class_token] or {}
        for i = 1, #HOOK_NAMES do
            local name = HOOK_NAMES[i]
            sb.hooks[name] = sb.hooks[name] or 0
            ST[class_token][name] = function(...)
                if name == "post_init" then
                    sb.hook_order[#sb.hook_order + 1] = "post_init"
                end
                sb.hooks[name] = sb.hooks[name] + 1
                sb.hook_args[name] = capture_args(...)
            end
        end
    end

    -- The hand containers exist on ST (main.lua built them); the anchor frames are
    -- normally created by bars.lua - one per hand of the class (the class hands
    -- list is the authority, the same one main.lua's iter_hands() walks).
    local hands = ST.class_hands[class_token] or { "mainhand" }
    for i = 1, #hands do
        local hand = hands[i]
        ST[hand].anchor_frame = make_frame(hand .. ".anchor")
        local anchor = ST[hand].anchor_frame
        anchor.hiding_anchor_frame = make_frame(hand .. ".hiding")
        anchor.bar_frame = make_frame(hand .. ".bar")
        anchor.bar_frame.visuals_frame = make_frame(hand .. ".visuals")
        anchor.bar_frame.visuals_frame.gcd_bar = make_frame(hand .. ".gcd_bar")
        ST[hand].onupdate = function() end
    end

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
    eq(T.lrc_ready, true, "the deadline treats LRC as settled")
    eq(T.interfaces_are_initialised, true, "initialisation proceeds after the deadline")

    -- No notice: range state no longer depends on LibRangeCheck (R1, 2026-10-21), so a
    -- missing library is a /st diag fact, not a disabled feature.
    eq(#F.notices, 0, "the deadline rescue prints no range-disable notice")

    -- Range finders start anyway and read exact yards; the library is untouched.
    eq(F.lrc_stats.harm_max, 0, "no harm checker is requested without LRC")
    eq(F.lrc_stats.range, 0, "no LRC range read without LRC")
    eq(T.rangefinder_interval, 0.05, "init_range_finders starts without LRC")
    eq(T.target_distance, 12, "the exact-yards probe answers")
    eq(T.in_melee_range, false, "12 yd is outside the 5 yd melee band")
    eq(T.in_ranged_range, true, "12 yd is inside the 30 yd ranged band")
    eq(T.target_min_range, 12, "the text min is the floor of the exact reading")
    eq(T.target_max_range, 12, "the text max is the ceil of the exact reading")

    --  and init ran exactly once.
    eq(F.counts.init_visuals, 1, "the visual template is initialised once")
    eq(F.counts.set_texts, 1, "the bar texts are initialised once")
    eq(F.hooks.post_init, 1, "the class post_init hook ran once")
    eq(F.diag.calls, 1, "the diagnostic self-report ran once")
    near(T.mainhand.speed, 2.6, "the vendored engine's swing speed was used")

    -- The deadline callback is idempotent once init has run.
    fire_deadline(b)
    eq(F.hooks.post_init, 1, "re-firing the deadline does not re-run init")
    eq(#F.notices, 0, "re-firing the deadline does not re-print a notice")
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
    eq(#F.notices, 1, "the rescue prints only the engine notice (range no longer depends on LRC)")
    eq(F.notices[1], "Swing timer bars are unavailable on this client; range and GCD features remain active.",
        "the engine loss is the only notice")
    eq(T.mainhand.speed, nil, "init_timers reads the replacement stub's unknown shape (no fake cycle)")
    eq(T.mainhand.ends_at, nil, "the stand-in has no invented expiration")
    eq(T.mainhand.engine_dead, true, "the stand-in marks the hand engine_dead for the bar render")

    -- A late report from the engine that never made it changes nothing now.
    fire_stl_ready(b)
    eq(F.hooks.post_init, 1, "a late engine report does not re-run init")
    eq(#F.notices, 1, "a late engine report does not re-print the notices")
end

--=========================================================================================
-- 2) Late-library recovery: LRC reports after the deadline
--=========================================================================================
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_deadline(b)
    local notices_after_deadline = #F.notices
    local post_init_calls = F.hooks.post_init
    local diag_calls = F.diag.calls

    -- The callback lifts the fallback flag so /st diag stops reporting lrc=fallback.
    -- It must not look like a second initialisation: range state already runs from
    -- exact yards and never consulted the library (R1, 2026-10-21).
    fire_lrc_checkers(b)
    eq(T.lrc_ready, true, "a late CHECKERS_CHANGED marks LRC ready")
    eq(T.lrc_unavailable, false, "a late CHECKERS_CHANGED lifts the lrc=fallback flag")
    eq(T.rangefinder_interval, 0.05, "the range finder interval is unchanged by recovery")
    eq(T.target_distance, 12, "the exact-yards reading survives the late report")
    eq(T.in_ranged_range, true, "the range state survives the late report")
    eq(F.lrc_stats.harm_max, 0, "recovery requests no LRC checker")
    eq(F.checker_calls, 0, "recovery runs no checker")
    eq(F.lrc_stats.range, 0, "recovery reads no LRC range")

    -- The poll loop is alive: the first poll re-armed a fresh interval timer, and firing
    -- it reads the exact distance again and arms the next interval.
    local poll = find_timer(b, 0.05)
    check(poll ~= nil, "the range poll re-arms itself")
    local polls_before = F.unit_distance_calls
    local timers_before = #F.after
    if poll then
        poll.cb()
    end
    eq(#F.after, timers_before + 1, "the followed-up poll arms the next interval")
    eq(F.unit_distance_calls, polls_before + 1, "the followed-up poll probes the distance once")

    -- Recovery must not look like a second initialisation.
    eq(F.hooks.post_init, post_init_calls, "recovery does not re-run post_init")
    eq(#F.notices, notices_after_deadline, "recovery does not re-print the notice")
    eq(F.diag.calls, diag_calls, "recovery does not re-report diag")
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
    eq(F.lrc_stats.harm_max, 0, "no LRC checker was requested (exact-yards source)")
    eq(F.checker_calls, 0, "no checker ran")
    eq(T.target_distance, 12, "the exact-yards probe answered")
    eq(T.in_ranged_range, true, "12 yd is inside the ranged band")
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
    -- F2: the suite no longer hand-sets has_oh to defeat the offhand guard - the
    -- flag is derived by check_weapons (see section 15). Here the init guard alone
    -- has to stop the handler.
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

    -- F2: a paladin has an offhand weapon but no offhand bar, so the offhand
    -- re-sync must leave the offhand alone (the positive path lives in section 15,
    -- on a class that has an offhand bar).
    T.offhand.speed = 3.6
    T.offhand.start = 0
    T:PLAYER_TARGET_SET_ATTACKING("PLAYER_TARGET_SET_ATTACKING")
    eq(T.offhand.start, 0, "a class without an offhand bar leaves the offhand timer alone")
    eq(F.counts.bar_color, nil, "a class without an offhand bar does not recolour")
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
    eq(#F.notices, 1, "the rescued init prints only the engine notice (range is exact-yards)")
    eq(F.notices[1], "Swing timer bars are unavailable on this client; range and GCD features remain active.",
        "range is never reported as unavailable for a missing library")
end

--=========================================================================================
-- 10) rf_update dead-man: a throwing distance probe disables range checking, never errors
--=========================================================================================
-- The exact-yards probe itself is pcall-wrapped in compat, but the state writes around
-- it are not allowed to kill the poll loop either. A transient throw retries with
-- bounded backoff; three consecutive throws disable the session through ONE one-time
-- notice; a nil reading is the honest "unknown" answer, never a failure.
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)

    -- Healthy baseline: the init poll wrote the exact-yards state and re-armed.
    eq(T.target_distance, 12, "the healthy init poll read exact yards")
    eq(T.in_melee_range, false, "12 yd is outside melee")
    eq(T.in_ranged_range, true, "12 yd is inside ranged")
    eq(T.target_min_range, 12, "the min text is the floor")
    eq(T.target_max_range, 12, "the max text is the ceil")
    check(find_timer(b, 0.05) ~= nil, "the healthy poll armed the next interval")
    eq(#F.notices, 0, "the healthy poll printed nothing")

    -- The probe explodes: bounded retry with backoff (M1), then session-disable.
    local healthy_probe = b.st.api.UnitDistance
    local touches_before = #F.touches
    local timers_before = #F.after
    b.st.api.UnitDistance = function() error("distance probe exploded") end

    local ok, err = pcall(T.rf_update, T)
    check(ok, "a throwing probe does not error (" .. tostring(err) .. ")")
    eq(T.rf_disabled, nil, "the first throw retries instead of disabling")
    eq(T.rf_failure_count, 1, "the first throw is counted")
    eq(#F.notices, 0, "the retry path prints nothing yet")
    eq(#F.after, timers_before + 1, "the first throw arms a backoff retry")
    eq(F.after[#F.after].delay, 0.05, "the first retry uses the base interval")

    -- Second consecutive throw: longer backoff, still no disable.
    F.after[#F.after].cb()
    eq(T.rf_disabled, nil, "the second throw still retries")
    eq(T.rf_failure_count, 2, "the second throw is counted")
    eq(F.after[#F.after].delay, 0.1, "the retry backs off exponentially (0.1 s)")

    -- Third consecutive throw: the bounded retry exhausts and disables the session.
    F.after[#F.after].cb()
    eq(T.rf_disabled, true, "the third consecutive throw disables range checking")
    eq(T.rf_failure_count, 3, "the exhausted retry keeps its count")
    eq(T.rf_disabled_after_failures, true, "the failure path records its terminal state")
    eq(#F.notices, 1, "the exhausted retry prints exactly one notice")
    eq(F.notices[1], "Range checking is unavailable on this client; the range display is disabled.",
        "the retry-exhaustion notice is the range-checking disable")
    eq(#F.after, timers_before + 2, "the terminal failure does not arm another retry")
    eq(#F.touches, touches_before, "the retry path touches no frames")

    -- Every later poll stops immediately: no probe, no second notice.
    local probes = F.unit_distance_calls
    ok = pcall(T.rf_update, T)
    check(ok, "a poll after the disable still does not error")
    eq(F.unit_distance_calls, probes, "a disabled poll never probes")
    eq(#F.after, timers_before + 2, "a disabled poll never reschedules")
    eq(#F.notices, 1, "the notice stays one-time")
    b.st.api.UnitDistance = healthy_probe
end
do
    -- A successful poll between throws resets the consecutive counter.
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    local healthy_probe = b.st.api.UnitDistance
    b.st.api.UnitDistance = function() error("transient") end
    T.rf_update(T)
    eq(T.rf_failure_count, 1, "the transient throw starts the streak")
    b.st.api.UnitDistance = healthy_probe
    F.after[#F.after].cb() -- retry succeeds
    eq(T.rf_failure_count, 0, "a successful retry resets the consecutive counter")
    eq(T.rf_disabled, nil, "range checking stays alive after a recovered poll")
    eq(T.in_ranged_range, true, "the recovered poll rewrote the state")
end
do
    -- Unknown is NOT a failure: the client not answering must not burn the retry budget
    -- or the session, and must clear both text fields (never a guess).
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    F.target_yards = nil
    local timers_before = #F.after
    local ok, err = pcall(T.rf_update, T)
    check(ok, "an unknown reading does not error (" .. tostring(err) .. ")")
    eq(T.rf_failure_count, 0, "a nil reading is not counted as a failure")
    eq(T.rf_disabled, nil, "a nil reading never disables range checking")
    eq(T.target_distance, nil, "the unknown distance is published as nil")
    eq(T.in_melee_range, false, "unknown is not melee")
    eq(T.in_ranged_range, false, "unknown is not ranged")
    eq(T.target_min_range, nil, "unknown clears the min text")
    eq(T.target_max_range, nil, "unknown clears the max text")
    eq(#F.after, timers_before + 1, "the loop keeps polling after an unknown")
    eq(F.after[#F.after].delay, 0.05, "the next poll keeps the base interval")
end
do
    -- The same failure inside the init poll: init still completes, the disable lands
    -- before post_init, and the notice is printed exactly once through the shared path.
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    b.st.api.UnitDistance = function() error("init poll exploded") end
    fire_lrc_checkers(b)
    check(T.interfaces_are_initialised, "init completes despite the throwing first poll")
    eq(T.rf_disabled, nil, "the init poll retries first")
    eq(T.rf_failure_count, 1, "the init poll counts its first throw")
    check(find_timer(b, 0.05) ~= nil, "the failing init poll arms its retry")
    F.after[#F.after].cb()
    F.after[#F.after].cb()
    eq(T.rf_disabled, true, "the sustained init-poll failure disables range checking")
    eq(#F.notices, 1, "the init poll failure prints the notice exactly once")
    eq(F.notices[1], "Range checking is unavailable on this client; the range display is disabled.",
        "the init poll notice is the range-checking disable")
    eq(F.hooks.post_init, 1, "post_init still runs after the disable")
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
do
    -- 12) Combat-enter resets the hunter shot log (H2 fight-scoping): entering combat
    -- on a hunter clears the rolling log so the post-fight report covers the new
    -- fight only; any other class (or a missing HUNTER module) leaves it alone.
    local b = boot()
    local T = b.ST
    local resets = 0
    T.player_class = "HUNTER"
    T.HUNTER = {
        reset_shot_log = function(self)
            resets = resets + 1
        end,
    }
    local ok, err = pcall(T.PLAYER_REGEN_DISABLED, T)
    check(ok, "combat-enter does not error on a hunter (" .. tostring(err) .. ")")
    eq(T.in_combat, true, "combat-enter marks in_combat")
    eq(resets, 1, "combat-enter resets the hunter shot log once")

    -- A second fight-start resets again (no one-shot latch).
    local ok2, err2 = pcall(T.PLAYER_REGEN_DISABLED, T)
    check(ok2, "a second combat-enter does not error (" .. tostring(err2) .. ")")
    eq(resets, 2, "each combat-enter resets the hunter shot log")

    -- Non-hunters never touch the log: the seeded HUNTER table carries no hook.
    local c = boot()
    local U = c.ST
    eq(U.player_class, "PALADIN", "the guard fixture runs a paladin")
    eq(U.HUNTER.reset_shot_log, nil, "the guard fixture wires no hunter reset hook")
    local ok3, err3 = pcall(U.PLAYER_REGEN_DISABLED, U)
    check(ok3, "combat-enter does not error on a non-hunter (" .. tostring(err3) .. ")")
    eq(U.in_combat, true, "combat-enter marks in_combat on a non-hunter too")
    eq(U.HUNTER.reset_shot_log, nil, "combat-enter adds no reset hook on a non-hunter")
end

--=========================================================================================
-- 13) Retail stub classes: MONK / DEMONHUNTER / EVOKER never nil-index a dispatch
--=========================================================================================
-- Hunter resweep ses_eaaf2f3b7ffeuygfA6RMet8AyF (HIGH, CONFIRMED): a Retail login for a
-- class with no class module used to nil-index at the unguarded dispatch sites (the
-- post_init guard, the rage/spellcast forwarders, the class_on_* wrappers, and the
-- bars set_bar_color guard). main.lua now ships inert ST.MONK / ST.DEMONHUNTER /
-- ST.EVOKER stub tables in token order, so every site resolves to a table and skips
-- its absent hook. In-game the AceDB ['**'] wildcard (config.lua) seeds the per-class
-- profile table and get_class_hands falls back to {}, so no class_hands or db change
-- is needed; this section seeds the same shape explicitly, then drives the login,
-- aura, cast, rage and swing dispatches for all 13 classes. CLEU registration is
-- class-independent on the classic line (G2: every classic-line class registers for
-- the neutral extra-attack/parry pre-pass; the class dispatch still forwards only to
-- the paladin/warrior readers), so no CLEU leg is needed here - the matrix lives in
-- bars_state §6 and the functional legs in real_wire_state.
do
    local ALL_CLASSES = {
        "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE",
        "MONK", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
    }
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)

    -- Stub presence: every class token resolves to a table (the three new stubs are
    -- the pin; the rest guards against a future stub going missing the same way).
    for i = 1, #ALL_CLASSES do
        eq(type(T[ALL_CLASSES[i]]), "table", "ST." .. ALL_CLASSES[i] .. " exists for the dispatch sites")
    end

    -- Mirror the in-game shape the login path expects: the AceDB ['**'] seed for the
    -- profile table, and the anchor frames bars.lua builds for every hand.
    for i = 1, #ALL_CLASSES do
        if F.profile[ALL_CLASSES[i]] == nil then
            F.profile[ALL_CLASSES[i]] = F.class_db
        end
    end
    for _, hand in ipairs({ "mainhand", "offhand", "ranged" }) do
        local anchor = F.make_frame(hand .. ".anchor")
        anchor.hiding_anchor_frame = F.make_frame(hand .. ".hiding")
        anchor.bar_frame = F.make_frame(hand .. ".bar")
        anchor.bar_frame.visuals_frame = F.make_frame(hand .. ".visuals")
        anchor.bar_frame.visuals_frame.gcd_bar = F.make_frame(hand .. ".gcd_bar")
        T[hand].anchor_frame = anchor
        T[hand].onupdate = function() end
    end

    local before = hook_snapshot(b)
    for i = 1, #ALL_CLASSES do
        local cls = ALL_CLASSES[i]
        T.player_class = cls
        local function trial(name, fn, ...)
            local ok, err = pcall(fn, ...)
            check(ok, cls .. " " .. name .. " does not error (" .. tostring(err) .. ")")
        end
        trial("login (post_init)", T.post_init, T)
        trial("aura", T.UNIT_AURA, T, "UNIT_AURA", "player")
        trial("cast succeeded", T.UNIT_SPELLCAST_SUCCEEDED, T, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 403)
        trial("cast failed-quiet", T.UNIT_SPELLCAST_FAILED_QUIET, T, "UNIT_SPELLCAST_FAILED_QUIET", "player", "cast-1", 403)
        trial("lifecycle START", T.UNIT_SPELLCAST_START, T, "UNIT_SPELLCAST_START", "player", "cast-1", 403)
        trial("lifecycle DELAYED", T.UNIT_SPELLCAST_DELAYED, T, "UNIT_SPELLCAST_DELAYED", "player", "cast-1", 403)
        trial("lifecycle STOP", T.UNIT_SPELLCAST_STOP, T, "UNIT_SPELLCAST_STOP", "player", "cast-1", nil)
        trial("lifecycle INTERRUPTED", T.UNIT_SPELLCAST_INTERRUPTED, T, "UNIT_SPELLCAST_INTERRUPTED", "player", "cast-1", 403)
        trial("lifecycle FAILED", T.UNIT_SPELLCAST_FAILED, T, "UNIT_SPELLCAST_FAILED", "player", "cast-1", 403)
        trial("lifecycle CHANNEL_START", T.UNIT_SPELLCAST_CHANNEL_START, T, "UNIT_SPELLCAST_CHANNEL_START", "player", "cast-1", 403)
        trial("lifecycle CHANNEL_STOP", T.UNIT_SPELLCAST_CHANNEL_STOP, T, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-1", nil)
        trial("cast-queue change", T.CURRENT_SPELL_CAST_CHANGED, T, "CURRENT_SPELL_CAST_CHANGED", false)
        trial("rage update", T.UNIT_POWER_FREQUENT, T, "UNIT_POWER_FREQUENT", "player", "RAGE")
        trial("non-rage power", T.UNIT_POWER_FREQUENT, T, "UNIT_POWER_FREQUENT", "player", "MANA")
        trial("equipment change", T.PLAYER_EQUIPMENT_CHANGED, T, "PLAYER_EQUIPMENT_CHANGED", 16, true)
        trial("cooldown update", T.SPELL_UPDATE_COOLDOWN, T)
        trial("autorepeat start", T.START_AUTOREPEAT_SPELL, T)
        trial("autorepeat stop", T.STOP_AUTOREPEAT_SPELL, T)
        trial("talent group", T.ACTIVE_TALENT_GROUP_CHANGED, T, "ACTIVE_TALENT_GROUP_CHANGED", 1)
        trial("talent points", T.CHARACTER_POINTS_CHANGED, T, "CHARACTER_POINTS_CHANGED")
        trial("swing start", T.SWING_TIMER_START, T, "SWING_TIMER_START", 2.6, F.clock + 2.6, "mainhand")
        trial("swing update", T.SWING_TIMER_UPDATE, T, "SWING_TIMER_UPDATE", 2.6, F.clock + 2.6, "mainhand")
        trial("swing stop", T.SWING_TIMER_STOP, T, "SWING_TIMER_STOP", "mainhand")
        trial("combat exit", T.PLAYER_REGEN_ENABLED, T)
        trial("combat enter", T.PLAYER_REGEN_DISABLED, T)
    end

    -- The wired class reached its hooks exactly once per dispatch; every other class
    -- (stubs included) stayed silent, so the stubs are inert.
    eq(F.hooks.post_init, before.post_init + 1, "the login dispatch reached the wired post_init once")
    eq(F.hooks.on_aura_change, before.on_aura_change + 1, "the aura dispatch reached the wired hook once")
    eq(F.hooks.on_spellcast_succeeded, before.on_spellcast_succeeded + 1, "the succeeded dispatch reached the wired hook once")
    eq(F.hooks.on_spellcast_failed_quiet, before.on_spellcast_failed_quiet + 1, "the failed-quiet dispatch reached the wired hook once")
    eq(F.hooks.on_spellcast_event, before.on_spellcast_event + 7, "the seven lifecycle dispatches reached the wired hook")
    eq(F.hooks.on_current_spell_cast_changed, before.on_current_spell_cast_changed + 1, "the cast-queue dispatch reached the wired hook once")
    eq(F.hooks.on_rage_update, before.on_rage_update + 1, "the rage dispatch reached the wired hook once")
    eq(F.hooks.on_cooldown_update, before.on_cooldown_update + 1, "the cooldown dispatch reached the wired hook once")
    eq(F.hooks.on_autorrepeat_event, before.on_autorrepeat_event + 2, "both autorepeat dispatches reached the wired hook")
    eq(F.hooks.on_talents_changed, before.on_talents_changed + 2, "both talent dispatches reached the wired hook")
    eq(F.hooks.on_combat_exit, before.on_combat_exit + 1, "the combat-exit dispatch reached the wired hook once")
end

--=========================================================================================
-- 14) SWING_TIMER_* nil-bar guards: an unknown hand never errors, notices once
--=========================================================================================
-- Live errors (operator screenshot): SWING_TIMER_START indexed a nil self[hand] and the
-- SWING_TIMER_STOP deferred callback touched a bar that was gone. Every guarded handler
-- takes the same shape -- local bar, one-time notice, return -- and the STOP callback
-- re-checks the bar at fire time.
do
    -- Each guarded handler prints the one-time notice on its own first unknown
    -- hand: a fresh boot per handler, so stripping any single notice fails.
    local cases = {
        { "START", "SWING_TIMER_START", function(T, clock)
            return pcall(T.SWING_TIMER_START, T, "SWING_TIMER_START", 2.6, clock + 2.6, "bogus")
        end },
        { "STOP", "SWING_TIMER_STOP", function(T)
            return pcall(T.SWING_TIMER_STOP, T, "SWING_TIMER_STOP", "bogus")
        end },
        { "UPDATE", "SWING_TIMER_UPDATE", function(T, clock)
            return pcall(T.SWING_TIMER_UPDATE, T, "SWING_TIMER_UPDATE", 2.6, clock + 2.6, "bogus")
        end },
        { "PAUSED", "SWING_TIMER_PAUSED", function(T)
            return pcall(T.SWING_TIMER_PAUSED, T, "SWING_TIMER_PAUSED", "bogus")
        end },
    }
    for i = 1, #cases do
        local b = boot()
        local T, F = b.ST, b.sb
        fire_stl_ready(b)
        fire_lrc_checkers(b)
        local notices_before = #F.notices
        local ok, err = cases[i][3](T, F.clock)
        check(ok, "unknown-hand " .. cases[i][1] .. " does not error (" .. tostring(err) .. ")")
        eq(#F.notices, notices_before + 1, "the first unknown hand prints exactly one notice (" .. cases[i][2] .. ")")
        contains(F.notices[#F.notices], "bogus", "the unknown-hand notice names the hand (" .. cases[i][2] .. ")")
    end
end
do
    local b = boot()
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    local notices_before = #F.notices

    -- Unknown hands on all four guarded handlers: no error, no state.
    local ok_start, err_start = pcall(T.SWING_TIMER_START, T, "SWING_TIMER_START", 2.6, F.clock + 2.6, "bogus")
    check(ok_start, "unknown-hand START does not error (" .. tostring(err_start) .. ")")
    local ok_stop, err_stop = pcall(T.SWING_TIMER_STOP, T, "SWING_TIMER_STOP", "bogus")
    check(ok_stop, "unknown-hand STOP does not error (" .. tostring(err_stop) .. ")")
    local ok_update, err_update = pcall(T.SWING_TIMER_UPDATE, T, "SWING_TIMER_UPDATE", 2.6, F.clock + 2.6, "bogus")
    check(ok_update, "unknown-hand UPDATE does not error (" .. tostring(err_update) .. ")")
    local ok_paused, err_paused = pcall(T.SWING_TIMER_PAUSED, T, "SWING_TIMER_PAUSED", "bogus")
    check(ok_paused, "unknown-hand PAUSED does not error (" .. tostring(err_paused) .. ")")
    eq(#F.notices, notices_before + 1, "four unknown hands still print exactly one notice")
    eq(#F.new_timers, 0, "an unknown-hand STOP arms no deferred timer")
    near(T.mainhand.speed, 2.6, "an unknown-hand START leaves the real bar alone")

    -- A second unknown hand (different name): still no error, still one notice.
    local ok_again, err_again = pcall(T.SWING_TIMER_START, T, "SWING_TIMER_START", 2.6, F.clock + 2.6, "nope")
    check(ok_again, "a second unknown hand still does not error (" .. tostring(err_again) .. ")")
    eq(#F.notices, notices_before + 1, "later unknown hands do not re-print the notice")

    -- Valid hands still work after the guards tripped.
    local ok_valid, err_valid = pcall(T.SWING_TIMER_START, T, "SWING_TIMER_START", 3.0, F.clock + 3.0, "mainhand")
    check(ok_valid, "a valid START still runs (" .. tostring(err_valid) .. ")")
    near(T.mainhand.speed, 3.0, "a valid START writes the bar speed")
    near(T.mainhand.ends_at, F.clock + 3.0, "a valid START writes the bar expiry")
    T:SWING_TIMER_PAUSED("SWING_TIMER_PAUSED", "mainhand")
    eq(T.mainhand.is_paused, true, "a valid PAUSED pauses the bar")
    T:SWING_TIMER_UPDATE("SWING_TIMER_UPDATE", 3.0, F.clock + 3.0, "mainhand")
    eq(T.mainhand.is_paused, false, "a valid UPDATE unpauses the bar")
    near(T.mainhand.speed, 3.0, "a valid UPDATE writes the bar speed")
    local timers_before = #F.new_timers
    T:SWING_TIMER_STOP("SWING_TIMER_STOP", "mainhand")
    eq(#F.new_timers, timers_before + 1, "a valid STOP arms the deferred timer")
    F.new_timers[#F.new_timers].cb()
    eq(T.mainhand.is_full, true, "the fired STOP timer marks the bar full")

    -- The bar vanishes between arm and fire: the deferred callback stays silent.
    T:SWING_TIMER_STOP("SWING_TIMER_STOP", "mainhand")
    local deferred = F.new_timers[#F.new_timers].cb
    local saved = T.mainhand
    T.mainhand = nil
    local ok_gone, err_gone = pcall(deferred)
    check(ok_gone, "a STOP timer firing after the bar is gone does not error (" .. tostring(err_gone) .. ")")
    eq(#F.notices, notices_before + 1, "the vanished-bar fire adds no second notice")
    T.mainhand = saved
    T:SWING_TIMER_START("SWING_TIMER_START", 2.6, F.clock + 2.6, "mainhand")
    near(T.mainhand.speed, 2.6, "the restored bar takes swings again")
end

--=========================================================================================
-- 14b) Swing-engine wire shapes: the dispatcher drops the classic unit-id lead
--=========================================================================================
-- TBC hunter ranged bar, 2026-10-21: the vendored classic library re-fires its
-- UNIT_SWING_TIMER_* events as SWING_TIMER_* WITH the unit id leading
-- (Fire(legacy, unitId, speed, ...)), while swing_source fires speed-first; the
-- app's handlers take speed-first. Without the dispatcher's normalisation the
-- classic payloads misalign by one argument (bar.speed becomes "player", a STOP
-- names a hand that is really an expiry timestamp) and the bars render their
-- init seed once, then freeze - with no error, because nothing throws. These
-- pins drive T.callback_event_handler with both engines' exact wire shapes.
do
    local b = boot({ class = "HUNTER", engine = "vendored", interface = 20506, project = 5 })
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    check(T.interfaces_are_initialised, "wire: the TBC hunter fixture reached a full init")

    -- Classic wire (vendored lib): the unit id leads. The dispatcher strips it,
    -- so the ranged bar takes the cycle and the wire counters record receipt.
    T.callback_event_handler("SWING_TIMER_START", "player", 3.1, F.clock + 3.1, "ranged")
    eq(type(T.ranged.speed), "number", "wire: a classic START writes a numeric speed")
    near(T.ranged.speed, 3.1, "wire: a classic START writes the bar speed")
    near(T.ranged.ends_at, F.clock + 3.1, "wire: a classic START writes the bar expiry")
    eq(T.swing_wire_counts.ranged.start, 1, "wire: a classic START is counted")

    T.callback_event_handler("SWING_TIMER_UPDATE", "player", 3.1, F.clock + 3.1, "ranged")
    near(T.ranged.speed, 3.1, "wire: a classic UPDATE writes the bar speed")
    eq(T.swing_wire_counts.ranged.update, 1, "wire: a classic UPDATE is counted")

    local timers_before = #F.new_timers
    T.callback_event_handler("SWING_TIMER_STOP", "player", "ranged")
    eq(#F.new_timers, timers_before + 1, "wire: a classic STOP arms the deferred timer")
    eq(T.swing_wire_counts.ranged.stop, 1, "wire: a classic STOP is counted")

    -- Forever wire (swing_source): speed leads, no unit id. The dispatcher leaves
    -- it untouched - stripping here would eat the speed itself.
    T.callback_event_handler("SWING_TIMER_START", 2.4, F.clock + 2.4, "ranged")
    near(T.ranged.speed, 2.4, "wire: a Forever START writes the bar speed")
    eq(T.swing_wire_counts.ranged.start, 2, "wire: a Forever START is counted")

    -- A non-swing callback keeps its exact args through the same dispatcher.
    T.callback_event_handler("GCD_STARTED", 1.2, 101.2)
    near(T.gcd.duration, 1.2, "wire: a plain GCD_STARTED keeps its args")
    eq(T.swing_wire_counts.ranged.start, 2, "wire: a GCD callback touches no wire count")

    -- A Forever STOP (hand only, no unit id) must survive the strip: the hand
    -- itself is a string, so the normalisation keys on the unit-id tokens,
    -- never on "any leading string".
    local timers_before_2 = #F.new_timers
    T.callback_event_handler("SWING_TIMER_STOP", "ranged")
    eq(#F.new_timers, timers_before_2 + 1, "wire: a Forever STOP arms the deferred timer")
    eq(T.swing_wire_counts.ranged.stop, 2, "wire: a Forever STOP is counted")

    -- The diag runtime line exposes the wire.
    local notices_before = #F.notices
    b.env.LE_EXPANSION_LEVEL_CURRENT = 1
    T:print_runtime_diag()
    eq(#F.notices, notices_before + 1, "wire: the diag line prints")
    contains(F.notices[#F.notices], "swing_ranged=2/1/2", "wire: the diag line carries the ranged counts")
    contains(F.notices[#F.notices], "swing_last=STOP:ranged", "wire: the diag line carries the last cycle event")
    contains(F.notices[#F.notices], "proj=5", "wire: the diag line carries the project id")
    contains(F.notices[#F.notices], "exp=1", "wire: the diag line carries the expansion level")
    contains(F.notices[#F.notices], "bcc=5", "wire: the diag line carries the BCC project constant")
end

--=========================================================================================
-- 15) F2: the PLAYER_TARGET_SET_ATTACKING guard has a real production path
--=========================================================================================
-- Deep audit (bench/deep_audit_2026-10-19.md, F2): the event was registered on every
-- classic-line client, but self.has_oh was initialised false and never set again, so
-- the handler body always returned at its guard - a registered dead event. The suite
-- used to defeat the guard by hand (T.has_oh = true), which is exactly what hid the
-- defect. These pins drive the production path instead: check_weapons derives has_oh
-- from the offhand-presence probe (api.UnitAttackSpeed's offhand speed), and the
-- guard opens on its own.
do
    -- A warrior with an offhand weapon: the class has an offhand bar and the probe
    -- reports an offhand speed.
    local b = boot({ class = "WARRIOR", use_offhand = true })
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    check(T.interfaces_are_initialised, "F2: the fixture reached a full init")
    eq(T.player_class, "WARRIOR", "F2: the fixture plays a warrior")
    eq(T.offhand.has_weapon, true, "F2: check_weapons detects the offhand weapon")
    eq(T.has_oh, true, "F2: has_oh is derived from the offhand probe, not hand-set")
    eq(T:has_hand("offhand"), true, "F2: a warrior has an offhand bar")

    -- The guard opens on its own: an overdue offhand cycle is re-synced.
    T.offhand.speed = 3.6
    T.offhand.start = 0
    T:PLAYER_TARGET_SET_ATTACKING("PLAYER_TARGET_SET_ATTACKING")
    eq(F.counts.bar_color, 1, "F2: the offhand recolour runs on the production path")
    near(T.offhand.start, F.clock - 3.6, "F2: the offhand timer is snapped to now minus speed")
    near(T.offhand.ends_at, F.clock, "F2: the offhand cycle end moves with the start")

    -- A cycle that is not overdue is left alone (no false re-sync).
    T.offhand.start = F.clock
    T.offhand.ends_at = F.clock + 3.6
    T:PLAYER_TARGET_SET_ATTACKING("PLAYER_TARGET_SET_ATTACKING")
    eq(F.counts.bar_color, 1, "F2: a live offhand cycle is not re-synced")
    near(T.offhand.start, F.clock, "F2: a live offhand cycle keeps its start")

    -- Before the first swing (and on the inert stand-in) the cycle fields are nil:
    -- there is nothing to re-sync, and the handler must not error.
    T.offhand.speed = nil
    T.offhand.start = nil
    local ok_nil, err_nil = pcall(T.PLAYER_TARGET_SET_ATTACKING, T, "PLAYER_TARGET_SET_ATTACKING")
    check(ok_nil, "F2: a nil offhand cycle does not error (" .. tostring(err_nil) .. ")")
    eq(F.counts.bar_color, 1, "F2: a nil offhand cycle triggers no recolour")

    -- A zero-length cycle would divide by zero in the bar's progress maths.
    T.offhand.speed = 0
    T.offhand.start = 0
    local ok_zero, err_zero = pcall(T.PLAYER_TARGET_SET_ATTACKING, T, "PLAYER_TARGET_SET_ATTACKING")
    check(ok_zero, "F2: a zero-length offhand cycle does not error (" .. tostring(err_zero) .. ")")
    eq(T.offhand.start, 0, "F2: a zero-length offhand cycle is left alone")
end

do
    -- No offhand weapon: the guard stays shut, and the handler does nothing.
    local b = boot({ class = "WARRIOR" })
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(T.offhand.has_weapon, false, "F2: a two-hander has no offhand weapon")
    eq(T.has_oh, false, "F2: without an offhand weapon the guard stays shut")
    T.offhand.speed = 3.6
    T.offhand.start = 0
    T:PLAYER_TARGET_SET_ATTACKING("PLAYER_TARGET_SET_ATTACKING")
    eq(T.offhand.start, 0, "F2: without an offhand weapon the offhand timer is untouched")
    eq(F.counts.bar_color, nil, "F2: without an offhand weapon nothing is recoloured")

    -- Equipping and unequipping an offhand weapon opens and closes the guard
    -- through the same production path (PLAYER_EQUIPMENT_CHANGED -> check_weapons).
    F.use_offhand = true
    T:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", 17, true)
    eq(T.has_oh, true, "F2: equipping an offhand weapon opens the guard")
    eq(T.offhand.has_weapon, true, "F2: the offhand weapon state follows the equip")
    F.use_offhand = false
    T:PLAYER_EQUIPMENT_CHANGED("PLAYER_EQUIPMENT_CHANGED", 17, true)
    eq(T.has_oh, false, "F2: unequipping the offhand weapon closes the guard again")
end

do
    -- A paladin has an offhand weapon but no offhand bar: the recolour would touch
    -- frames that were never created, so the handler must leave the offhand alone.
    local b = boot({ class = "PALADIN", use_offhand = true })
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(T.has_oh, true, "F2: the paladin fixture detects the offhand weapon")
    eq(T:has_hand("offhand"), false, "F2: a paladin has no offhand bar")
    T.offhand.speed = 3.6
    T.offhand.start = 0
    local ok, err = pcall(T.PLAYER_TARGET_SET_ATTACKING, T, "PLAYER_TARGET_SET_ATTACKING")
    check(ok, "F2: a class without an offhand bar does not error (" .. tostring(err) .. ")")
    eq(T.offhand.start, 0, "F2: a class without an offhand bar leaves the offhand timer alone")
    eq(F.counts.bar_color, nil, "F2: a class without an offhand bar does not recolour")
end

--=========================================================================================
-- 16) F1: the chained error handler is installed at init and removed at logout
--=========================================================================================
-- Deep audit (bench/deep_audit_2026-10-19.md, F1): install_error_handler had no
-- caller in the whole tree, so the ring was never written and /st diag printed
-- "errors none" as a fact when nothing could have been observed.
do
    local b = boot()
    local T, F = b.ST, b.sb
    eq(F.diag.installs, 0, "F1: the chain is not installed before the init")
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(F.diag.installs, 1, "F1: init installs the chained error handler once")
    check(F.events["PLAYER_LOGOUT"] ~= nil, "F1: PLAYER_LOGOUT is registered")

    -- Idempotence: a late library report must not install a second chain.
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(F.diag.installs, 1, "F1: a repeated init report does not install the chain twice")

    -- The session's end removes the chain again.
    T:PLAYER_LOGOUT()
    eq(F.diag.uninstalls, 1, "F1: PLAYER_LOGOUT removes the chained error handler")
    T:PLAYER_LOGOUT()
    eq(F.diag.uninstalls, 2, "F1: the removal is unconditional (a second logout repeats it)")
end

--=========================================================================================
-- 16b) H2: the logout flushes the practice progression session
--=========================================================================================
-- Deep audit (2026-10-20, H2): the progression session's completion bonus, its daily
-- streak, its run, its time active and its bounded history row were written by ONE
-- caller - the practice session's stop. A player who practised and then logged out
-- (or reloaded) kept the per-attempt XP and lost everything else, with no error and
-- no notice. The logout handler must call the flush, and the flush must be reached
-- even when the practice module is not loaded at all.
do
    local b = boot()
    local T, F = b.ST, b.sb
    local calls, seen_self = 0, nil
    F.st.practice_ui = {
        flush_progress_session = function(self)
            calls = calls + 1
            seen_self = self
            return true
        end,
    }
    T:PLAYER_LOGOUT()
    eq(calls, 1, "H2: the logout handler flushes the practice progression session")
    eq(seen_self, T, "H2: the flush receives the addon object")

    -- A second logout (the client can fire it twice) flushes again - the flush
    -- itself is idempotent, the handler is unconditional.
    T:PLAYER_LOGOUT()
    eq(calls, 2, "H2: the logout handler flushes unconditionally")

    -- Without the practice module the handler still runs cleanly.
    F.st.practice_ui = nil
    local ok, err = pcall(function() T:PLAYER_LOGOUT() end)
    check(ok, "H2: the logout handler survives a missing practice UI module (" .. tostring(err) .. ")")
end

--=========================================================================================
-- 16c) M1: the logout flush's failure is COUNTED, not swallowed (re-audit 2026-10-20)
--=========================================================================================
-- The flush used to run under a bare pcall and the error was thrown away - the very
-- data class H2 was filed for (the completion bonus, the daily streak, the run, the
-- time active and the history row) went silent again, with no counter and no notice.
-- The house contract (st.guard.run) counts the failure, reports the FIRST one once
-- (never a chat flood) and shows the count in /st diag's bar_hook_errors line.
do
    local b = boot()
    local T, F = b.ST, b.sb
    local thrown = 0
    F.st.practice_ui = {
        flush_progress_session = function()
            thrown = thrown + 1
            error("flush boom")
        end,
    }
    local ok, err = pcall(function() T:PLAYER_LOGOUT() end)
    check(ok, "M1: the logout handler survives a throwing flush (" .. tostring(err) .. ")")
    eq(thrown, 1, "M1: the throwing flush is called once")
    check(type(T.bar_hook_errors) == "table", "M1: the failure leaves a counter behind")
    eq(type(T.bar_hook_errors) == "table" and T.bar_hook_errors.by_site["practice:logout"] or nil, 1,
        "M1: the counter names the logout flush site")
    eq(type(T.bar_hook_errors) == "table" and T.bar_hook_errors.count or nil, 1,
        "M1: the failure is counted once")
    -- The first failure of the site is announced once, through the addon's own chat path.
    local function announcements()
        local n = 0
        for _, notice in ipairs(F.notices) do
            if notice:find("practice:logout", 1, true) then n = n + 1 end
        end
        return n
    end
    eq(announcements(), 1, "M1: the first failure is announced once")
    -- A second logout counts again and does NOT announce again.
    pcall(function() T:PLAYER_LOGOUT() end)
    eq(T.bar_hook_errors.by_site["practice:logout"], 2, "M1: every failure keeps counting")
    eq(announcements(), 1, "M1: the site is announced once, not per failure")
    -- The /st diag runtime line is the reader of that counter.
    run_cmd(b, "st", "diag")
    contains(F.notices[#F.notices], "bar_hook_errors=2",
        "M1: the diag runtime line shows the counted failure")
end

--=========================================================================================
-- 17) F5 / F7 / F11: the runtime diag line, the dead helper, the tautology asserts
--=========================================================================================
do
    -- F5: the HUD's combat-log registration counter was write-only - hud.lua's
    -- comment named a /st diag reader that did not exist. The runtime line is it.
    local b = boot()
    local F = b.sb
    F.st.hud = { cleu_register_errors = 3 }
    run_cmd(b, "st", "diag")
    contains(F.notices[#F.notices], "hud_cleu_register_errors=3",
        "F5: the runtime diag line reads the HUD's combat-log registration counter")
    F.st.hud = nil
    run_cmd(b, "st", "diag")
    contains(F.notices[#F.notices], "hud_cleu_register_errors=0",
        "F5: without the HUD module the counter renders zero")
end

do
    -- F7: needs_gcd had no callers, and its per-hand table reads auto-created
    -- synthetic AceDB tables - a future caller would have read a plausible
    -- non-real table. The helper is gone.
    local main_src = read("main.lua")
    check(main_src:find("needs_gcd", 1, true) == nil,
        "F7: the dead needs_gcd helper is gone from main.lua")

    -- F11: the "assert(event == event)" tautologies were runtime asserts doing a
    -- linter's job. The handlers name their unused arguments instead.
    local code_only = {}
    for line in main_src:gmatch("[^\r\n]+") do
        if not line:match("^%s*%-%-") then
            code_only[#code_only + 1] = line
        end
    end
    local main_code = table.concat(code_only, "\n")
    check(main_code:find("assert(event", 1, true) == nil,
        "F11: main.lua has no unused-argument tautology asserts")
    local handlers = {
        "ST:CURRENT_SPELL_CAST_CHANGED(_event, is_cancelled)",
        "ST:PLAYER_ENTERING_WORLD(_event, _is_initial_login, _is_reloading_ui)",
        "ST:PLAYER_EQUIPMENT_CHANGED(_event, slot, _has_current)",
        "ST:UNIT_AURA(_event, unit_id, _is_full_update, _updated_auras)",
        "ST:UNIT_POWER_FREQUENT(_event, unit_id, powerType)",
        "ST:UNIT_SPELLCAST_FAILED_QUIET(_event, unit_id, cast_guid, spell_id)",
        "ST:UNIT_SPELLCAST_SUCCEEDED(_event, unit_id, cast_guid, spell_id)",
    }
    for i = 1, #handlers do
        check(main_src:find("function " .. handlers[i], 1, true) ~= nil,
            "F11: " .. handlers[i] .. " names its unused arguments")
    end
end

--=========================================================================================
-- 18) Output policy: main.lua reaches the chat path, never the client's global print
--=========================================================================================
-- The bars lane (bench/bars_print_policy_2026-10-19.md) removed the
-- `local print = st.utils.print_msg` alias from bars.lua and routed its module-parse
-- trailer through st.utils.print_msg explicitly. main.lua carried the same alias shape
-- and the same bare global print in its trailer; the policy that replaced it is pinned
-- here:
--   - no bare print call survives anywhere in main.lua (source scan, comments included),
--   - main.lua defines no print alias (the ambiguous identifier is gone),
--   - the module-parse trailer reaches the chat frame when the debug switch is on,
--   - the client's global print is never called.
do
    -- The source scan: "st.utils.print_msg(" never contains "print(", so every hit here
    -- is a bare call to the client's global print - live code or a commented-out debug
    -- line alike.
    local src_file = io.open(ROOT .. "main.lua", "r")
    local src = src_file and src_file:read("*a") or nil
    if src_file then src_file:close() end
    check(src ~= nil, "output policy: main.lua is readable")
    local bare = 0
    if src then
        for line in src:gmatch("[^\n]+") do
            if line:find("print%(") then
                bare = bare + 1
            end
        end
    end
    eq(bare, 0, "output policy: main.lua calls no bare print (chat output is st.utils.print_msg)")
    check(src ~= nil and src:find("\nlocal print =", 1, true) == nil,
        "output policy: main.lua defines no print alias")

    -- The trailer itself: with st.debug on, main.lua's module-parse line must arrive
    -- through the chat frame and never through the client's global print.
    local b = build({ debug = true })
    local F = b.sb
    eq(#F.raw_prints, 0,
        "output policy: the client's global print is never called by main.lua")
    local reported = false
    for i = 1, #F.chatter do
        if F.chatter[i]:find("Parsed main1.lua module correctly", 1, true) then
            reported = true
        end
    end
    check(reported, "output policy: main.lua's module trailer reaches the chat frame")
end

--=========================================================================================
-- 19) BS-8 item 1: the paladin's LCD.Register degrade is visible on the runtime line
--=========================================================================================
-- JE-1 (deep audit 2026-10-19): the class counted every failed LibClassicDurations
-- registration (ST.PALADIN.lcd_register_errors) and NOTHING read it, so a degraded
-- guide frame showed no diagnostic at all. The runtime diag line is that reader, in
-- the same shape as the HUD's counter.
do
    local b = boot()
    local F = b.sb
    b.ST.PALADIN.lcd_register_errors = 2
    run_cmd(b, "st", "diag")
    contains(F.notices[#F.notices], "paladin_lcd_register_errors=2",
        "JE-1: the runtime diag line reads the paladin's LCD registration counter")
    b.ST.PALADIN.lcd_register_errors = nil
    run_cmd(b, "st", "diag")
    contains(F.notices[#F.notices], "paladin_lcd_register_errors=0",
        "JE-1: without a counter the line renders zero")
end

--=========================================================================================
-- 20) BS-8 item 2: the live pull clock
--=========================================================================================
-- The prepull rule needs a pull countdown (nextaction.lua's
-- PREPULL_SEAL_LEAD_SECONDS / out.prepull_ready read inputs.time_to_pull_seconds).
-- The shipped clients have no pull-timer API, so main.lua publishes the addon's own
-- clock: a TIMESTAMP the guide can read, armed by the pull moments the client
-- reports.
do
    local b = boot()
    local T, F = b.ST, b.sb
    -- Unknown by default: the clock is never a guess.
    eq(T.pull_at, nil, "the pull clock starts unknown")
    eq(T:pull_in_seconds(F.clock), nil, "an unknown pull reads no countdown")
    -- Arming it: the absolute moment and the relative one.
    T:set_pull_at(120)
    eq(T.pull_at, 120, "the clock keeps the absolute pull moment")
    eq(T:pull_in_seconds(100), 20, "the countdown is the distance to the pull")
    eq(T:pull_in_seconds(130), -10, "the countdown is negative after the pull")
    T:set_pull_in(5)
    eq(T.pull_at, F.clock + 5, "the relative arming counts from now")
    T:set_pull_at(nil)
    eq(T.pull_at, nil, "the clock disarms")
    eq(T:pull_in_seconds(F.clock), nil, "a disarmed clock reads no countdown")
    -- A non-number is ignored (the clock is never a guess).
    T:set_pull_at("soon")
    eq(T.pull_at, nil, "a non-numeric pull moment is ignored")
    -- The fight's own pull: combat enter stamps it, combat exit clears it.
    T:PLAYER_REGEN_DISABLED()
    eq(T.pull_at, F.clock, "combat enter stamps the pull")
    eq(T:pull_in_seconds(F.clock), 0, "the pull reads zero once it happened")
    T:PLAYER_REGEN_ENABLED()
    eq(T.pull_at, nil, "combat exit clears the clock (the next pull is unknown)")
end

do
    -- The pre-pull projection: the player's target starts a cast out of combat, so
    -- the pull is that cast's end. The cast's own times come from the client.
    local b = boot({ target_casting = true, cast_end_ms = 102000 })
    local T = b.ST
    T:update_pull_clock("target")
    eq(T.pull_at, 102, "the target's cast end is the projected pull")
    eq(T:pull_in_seconds(100), 2, "the countdown shrinks towards the pull")
    -- A cast by anybody else never arms the clock (a pull is the boss's cast).
    T:set_pull_at(nil)
    T:update_pull_clock("player")
    eq(T.pull_at, nil, "the player's own cast never arms the pull clock")
    -- In combat the projection is refused (the pull already happened).
    T.in_combat = true
    T:update_pull_clock("target")
    eq(T.pull_at, nil, "in combat the pull clock is not armed")
end

do
    -- The source's guards: a pull is a group event inside an instance, so neither a
    -- solo player nor a player in the open world arms the clock.
    local solo = boot({ in_group = false })
    solo.ST:update_pull_clock("target")
    eq(solo.ST.pull_at, nil, "a solo player never arms the pull clock")
    local open_world = boot({ in_instance = false })
    open_world.ST:update_pull_clock("target")
    eq(open_world.ST.pull_at, nil, "outside an instance the pull clock stays unknown")
end

--=========================================================================================
-- 7c) Class activation (operator order 2026-10-21): only the selected module runs
--=========================================================================================
-- The class files register their body as a loader at load; main.lua activates the
-- SELECTED loader in init_libs. The order is the contract: activation must precede the
-- class post_init hook (which is what brings up the practice panel and the HUD), and
-- the fail-closed paths must never abort init or leave a half-populated class table.
do
    -- Auto (the default): the PLAYING class's loader runs, once, before post_init.
    local b = boot()
    local T, F = b.ST, b.sb
    eq(F.class_loaded, 0, "the class loader is not run at load - the SavedVariables are not readable yet")
    eq(#F.hook_order, 0, "no class hook exists before activation")
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(F.class_loaded, 1, "Auto activates the playing class's loader exactly once")
    eq(F.hooks.post_init, 1, "the class post_init hook ran once")
    eq(#F.hook_order, 2, "activation then post_init - nothing else in the order")
    eq(F.hook_order[1], "activate", "activation comes FIRST")
    eq(F.hook_order[2], "post_init", "the class post_init hook comes after activation")
    eq(T.interfaces_are_initialised, true, "a healthy activation lets init complete")
    eq(#F.notices, 0, "Auto prints no activation notice")
    eq(T.active_class, T.player_class,
        "Auto records the playing class as the ACTIVE class (the shared layer's fact)")

    -- Idempotence: a late library report cannot re-run the loader.
    fire_lrc_checkers(b)
    eq(F.class_loaded, 1, "a late report does not re-activate the class")
    eq(F.hooks.post_init, 1, "a late report does not re-run post_init")
end

do
    -- An explicit pick activates THAT class's loader instead of the playing class's.
    local b = build({ report_login = false })
    b.sb.class_db.class_activation = "ROGUE"
    b.st.class_loaders["ROGUE"] = function()
        b.ST.ROGUE.test_marker = true
    end
    b.ST:OnInitialize()
    report_login(b)
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(b.sb.class_loaded, 0, "the playing class's loader did NOT run when another class is selected")
    eq(b.ST.ROGUE.test_marker, true, "the selected class's loader ran")
    eq(b.sb.hooks.post_init, nil, "the unselected playing class has no post_init hook to run")
    eq(b.ST.interfaces_are_initialised, true, "init still completes under an explicit selection")
    eq(#b.sb.notices, 0, "a resolvable explicit selection prints no notice")
    eq(b.ST.active_class, "ROGUE",
        "an explicit pick records THAT class as the ACTIVE class")
end

do
    -- Fail closed: an explicit class with no module -> one clear line, no crash, no
    -- half-state. Init (and the shared layer) still completes.
    local b = build({ report_login = false })
    b.sb.class_db.class_activation = "WARRIOR"
    b.ST:OnInitialize()
    report_login(b)
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(b.ST.interfaces_are_initialised, true, "a missing module does not abort init")
    eq(b.sb.class_loaded, 0, "the playing class's loader did not run")
    eq(b.sb.hooks.post_init, nil, "no class post_init hook ran for the missing class")
    eq(#b.sb.notices, 1, "the missing module prints exactly one notice")
    contains(b.sb.notices[1], "no class module is available for WARRIOR",
        "the notice names the missing class")
    check(next(b.ST.WARRIOR) == nil, "the missing class table stays empty (no half-state)")
    eq(b.ST.active_class, nil, "no loader -> no ACTIVE class (the shared layer degrades)")
    eq(b.sb.diag.calls, 1, "init's own self-report still ran")
end

do
    -- Fail closed: a loader that throws -> one clear line, no crash, and the class
    -- table is reset so a half-populated module cannot survive.
    local b = build({ report_login = false })
    b.st.class_loaders["PALADIN"] = function()
        b.ST.PALADIN.partial = true
        error("loader exploded")
    end
    b.ST:OnInitialize()
    report_login(b)
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(b.ST.interfaces_are_initialised, true, "a throwing loader does not abort init")
    eq(#b.sb.notices, 1, "the throwing loader prints exactly one notice")
    contains(b.sb.notices[1], "PALADIN class module failed to load",
        "the notice names the failing class")
    contains(b.sb.notices[1], "loader exploded", "the notice carries the error")
    check(next(b.ST.PALADIN) == nil, "the half-populated class table was rolled back")
    eq(b.ST.active_class, nil, "a throwing loader -> no ACTIVE class (fail closed)")
    eq(b.sb.hooks.post_init, nil, "the throwing loader never reached the post_init hook")
    eq(b.sb.diag.calls, 1, "init's own self-report still ran")
end

do
    -- Auto on a class with no module (an unsupported class, or a pre-loader class
    -- file in the A1/A2 transition) stays silent: that is today's unsupported-class
    -- path, and a notice there would be a user-visible change unrelated to the order.
    local b = build({ report_login = false })
    b.st.class_loaders["PALADIN"] = nil
    b.ST:OnInitialize()
    report_login(b)
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(b.ST.interfaces_are_initialised, true, "init completes without any class module")
    eq(#b.sb.notices, 0, "Auto without a module prints no notice")
    eq(b.sb.hooks.post_init, nil, "no class post_init hook ran")
end

if failures == 0 then
    print("PASS  main_init_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  main_init_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
