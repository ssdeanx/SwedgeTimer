-- tests/range_source_state.lua: the range engine on TBC Anniversary (2026-10-21) -
-- exact yards, zero protected calls, no guard cascade.
--
-- Operator in-client evidence: `ADDON_ACTION_BLOCKED ... protected function
-- 'check_interact_distance()'` through update_range_helper -> ui.update -> the hunter
-- class hook -> guard.run (25 throws = the whole hook quarantined), and the rf_update
-- dead-man disabling the range state after three poll failures. This suite models that
-- failing client: UnitDistanceSquared answers exact yards, CheckInteractDistance is a
-- THROWING global that records every call, and the vendored LibRangeCheck is loaded as
-- shipped (it must build no interact checker at all).
--
-- Covered (brief items 1-7):
--   1. init_range_finders + several rf_update runs make ZERO CheckInteractDistance calls
--      and never take the disable path.
--   2. The state follows the yards: 4 melee only; 8 ranged (hunter 35 / paladin 30);
--      20 ranged; 40 neither; nil/unchecked unknown - never a guess.
--   3. target_min_range / target_max_range are floor/ceil numbers and ST.target_distance
--      is the exact reading.
--   4. The range state works with LibRangeCheck never reporting (the init deadline path).
--   5. hunter_ui.update_range_helper shows the strip with a target and a reading, hides
--      it with none or with every probe unknown, and touches no protected function.
--   6. Cascade proof: one throwing sub-feature inside ui.update is isolated to its own
--      site; the other sub-features keep running and the CLASS hook site is never
--      quarantined.
--   7. A throwing class post_init is isolated: init_libs still completes and the guard
--      records the site once.
--
-- Run from the repo root: lua5.1 tests/range_source_state.lua  (any cwd works).


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
        interact_calls = 0, -- protected CheckInteractDistance calls (must stay 0)
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
        return sb.target_yards * sb.target_yards, sb.target_checked ~= false
    end
    -- The failing client's protected call: present as a THROWING recorder, exactly like
    -- the in-client ADDON_ACTION_BLOCKED. Any call from the addon or the vendored library
    -- both aborts the caller and fails the zero-call pins below.
    env.CheckInteractDistance = function(unit, index)
        sb.interact_calls = sb.interact_calls + 1
        error("CheckInteractDistance is protected on TBC Anniversary")
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

local function fire_lrc_checkers(b)
    local cb = b.sb.lrc_cb[b.sb.LRC.CHECKERS_CHANGED]
    assert(cb, "the LRC CHECKERS_CHANGED callback is registered")
    cb()
end

local build_ui
do
    local function new_region(kind, name, parent)
        local region = {
            kind = kind, name = name, parent = parent,
            shown = true, width = 200, height = 15, scale = 1, frame_level = 1,
            center_y = 0, bottom = 0, points = {}, restored = 0,
        }
        setmetatable(region, {
            __index = function(t, key)
                -- WoW region methods are cached no-ops; data fields stay nil when a
                -- fixture leaves them unset (so bar_frame/text/tex read back nil, not a
                -- fabricated function).
                if type(key) ~= "string" or not key:match("^[A-Z]") then
                    return nil
                end
                local fn = function() end
                rawset(t, key, fn)
                return fn
            end,
        })
        function region:CreateTexture() return new_region("Texture", nil, self) end
        function region:CreateFontString() return new_region("FontString", nil, self) end
        function region:CreateFrame() return new_region("Frame", nil, self) end
        function region:SetPoint(point, relative, relative_point, x, y)
            self.points[#self.points + 1] = { point = point, relative = relative, x = x, y = y }
            if point == "CENTER" then
                self.center_y = y or 0
            end
        end
        function region:ClearAllPoints() self.points = {} end
        function region:GetPoint(index)
            local p = self.points[index or 1]
            if not p then
                return nil
            end
            return p.point, p.relative, p.point, p.x or 0, p.y or 0
        end
        function region:SetWidth(w) self.width = w end
        function region:GetWidth() return self.width end
        function region:SetHeight(h) self.height = h end
        function region:GetHeight() return self.height end
        function region:SetSize(w, h) self.width, self.height = w, h end
        function region:SetScale(s) self.scale = s end
        function region:GetScale() return self.scale end
        function region:SetFrameLevel(l) self.frame_level = l end
        function region:GetFrameLevel() return self.frame_level end
        function region:GetBottom() return self.bottom end
        function region:GetCenter() return 0, self.center_y end
        function region:Show() self.shown = true end
        function region:Hide() self.shown = false end
        function region:IsShown() return self.shown end
        function region:IsVisible() return self.shown end
        -- SoD-faithful FontString: SetFont(nil) latches nothing (false, like the
        -- client) and SetText with no font throws ("Font not set"). Every FontString
        -- the hunter UI creates must carry a font BEFORE its first SetText.
        function region:SetFont(path, size, flags)
            if kind ~= "FontString" then
                return true
            end
            if path == nil then
                return false
            end
            self.font = { path, size, flags }
            return true
        end
        function region:GetFont() return self.font and self.font[1] or nil end
        function region:SetText(text)
            if kind == "FontString" and self.font == nil then
                error("Font not set", 2)
            end
            self.text = text
        end
        function region:SetTexture(texture) self.texture = texture end
        function region:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
        function region:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
        return region
    end

    build_ui = function(opts)
        opts = opts or {}
        local sb = {
            now = opts.now or 0,
            calls = { cast = 0, aura = 0, in_range = 0, distance = 0, restore = 0 },
            live_cast = opts.live_cast,
            auras = opts.auras,
            pet_auras = opts.pet_auras,
            in_range = opts.in_range,
            target_yards = opts.target_yards,
            in_combat = opts.in_combat == true,
            ranged_available = opts.ranged_available ~= false,
            regions = {},
        }

        local env = setmetatable({}, { __index = _G })
        env.WOW_PROJECT_ID = 11
        env.WOW_PROJECT_CLASSIC = 2
        env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
        env.WOW_PROJECT_WRATH_CLASSIC = 11
        env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
        env.WOW_PROJECT_MISTS_CLASSIC = 19
        env.WOW_PROJECT_MAINLINE = 1
        env.WOW_PROJECT_FOREVER = 18
        env.UIParent = new_region("Frame", "UIParent", nil)
        env.CreateFrame = function(kind, name, parent)
            local region = new_region(kind or "Frame", name, parent)
            sb.regions[#sb.regions + 1] = region
            return region
        end
        env.InCombatLockdown = function() return sb.in_combat end
        env.GetTime = function() return sb.now end
        env.GetTimePreciseSec = function() return sb.now end
        -- The client's own standard font. The shared chain (utils.lua) reads it as
        -- the middle step: the LSM path, then STANDARD_TEXT_FONT, then the classic
        -- client font. A distinctive value proves which step carried the label.
        env.STANDARD_TEXT_FONT = "Fonts\\STANDARD.TTF"
        if opts.no_std_font then
            env.STANDARD_TEXT_FONT = nil
        end

        -- H1 scripted unit tokens (absent by default = the client answers nothing).
        if opts.unit_exists ~= nil then
            env.UnitExists = opts.unit_exists
        end
        if opts.unit_is_unit ~= nil then
            env.UnitIsUnit = opts.unit_is_unit
        end

        -- Minimal client spell data: the hunter tokens, the reference Multi-Shot ranks and
        -- the aspect table, so the token/name matchers resolve against a real client shape.
        local spell_data = {
            [75] = "Auto Shot", [2973] = "Raptor Strike", [2974] = "Wing Clip",
            [3045] = "Rapid Fire", [2643] = "Multi-Shot", [27021] = "Multi-Shot",
            [13165] = "Aspect of the Hawk", [27044] = "Aspect of the Hawk",
            [5118] = "Aspect of the Cheetah", [13163] = "Aspect of the Monkey",
            [13159] = "Aspect of the Pack", [20190] = "Aspect of the Wild",
            [34074] = "Aspect of the Viper", [13171] = "Aspect of the Beast",
            [19574] = "Bestial Wrath", [19615] = "Frenzy Effect",
        }
        env.GetSpellInfo = function(id)
            if opts.missing_spells and opts.missing_spells[id] then
                return nil
            end
            local name = spell_data[id]
            if not name then
                return nil
            end
            return name, nil, "icon_" .. id, 0, 0, 0, id
        end
        env.UnitCastingInfo = function()
            sb.calls.cast = sb.calls.cast + 1
            local cast = sb.live_cast
            if not cast then
                return nil
            end
            return cast.name, "", "cast_icon", cast.start_ms, cast.end_ms,
                false, 1, false, cast.spell_id
        end
        env.UnitChannelInfo = function() return nil end
        env.UnitAura = function(unit, index, filter)
            sb.calls.aura = sb.calls.aura + 1
            local list = sb.auras
            if unit ~= "player" then
                list = sb.pet_auras
            end
            local aura = list and list[index]
            if not aura then
                return nil
            end
            return aura.name, "", aura.count or 0, "", aura.duration, aura.expiration,
                nil, nil, nil, aura.spell_id
        end
        env.IsSpellInRange = function(spell, unit)
            sb.calls.in_range = sb.calls.in_range + 1
            if not sb.in_range then
                return nil
            end
            return sb.in_range[spell]
        end
        -- Exact target distance: the sweet spot is a yards band now (R3, 2026-10-21).
        -- nil yards = the client cannot answer (unknown), never a guess or a zero.
        env.UnitDistanceSquared = function(unit)
            sb.calls.distance = sb.calls.distance + 1
            if sb.target_yards == nil then
                return 0, false
            end
            return sb.target_yards * sb.target_yards, true
        end
        -- The protected call the hunter UI used to make: throwing + recording, so
        -- "no protected function" is an assertion, not a code-reading habit.
        env.CheckInteractDistance = function(unit, index)
            sb.calls.interact = (sb.calls.interact or 0) + 1
            error("CheckInteractDistance is protected on TBC Anniversary")
        end

        -- Opt-in mana + spell-knowledge fixtures for the OOM Viper probe (compat
        -- reads both through _G; absent reads the unknown shape). Placed before
        -- the compat load so the probes resolve like the class build() above.
        if opts.mana ~= nil then
            env.UnitPower = function() return opts.mana.cur end
            env.UnitPowerMax = function() return opts.mana.max end
        end
        if opts.known_spells ~= nil then
            env.IsSpellKnown = function(id)
                return opts.known_spells[id] == true
            end
        end

        -- compat.lua reads several legacy globals through _G; mirror EVERY stub for the
        -- duration of its load, then restore _G exactly. Absent keys are tracked by
        -- name (same discipline as build()): a nil entry stores nothing in the mirrored
        -- table and would otherwise leak the stub into every later sandbox.
        local mirrored = {}
        local mirrored_names = {}
        for name, value in pairs(env) do
            mirrored[name] = rawget(_G, name)
            mirrored_names[#mirrored_names + 1] = name
            _G[name] = value
        end

        local st = {}
        local compat = assert(loadfile(ROOT .. "compat.lua"))
        setfenv(compat, env)
        compat("SwedgeTimer", st)

        for _, name in ipairs(mirrored_names) do
            _G[name] = mirrored[name]
        end

        local ST = { HUNTER = {} }
        local class_db = {
            class_enabled = true,
            timers_locked = true,
            hunter_cast_bar_enabled = true,
            hunter_cast_bar_height = 15,
            hunter_cast_bar_color = { 0.35, 0.65, 0.95, 1.0 },
            hunter_range_helper_enabled = true,
            hunter_rapid_fire_bar_enabled = true,
            hunter_aspect_icon_enabled = true,
            -- H1 target warning ships off (nil = off); a test opts in explicitly.
            hunter_target_warning_enabled = opts.target_warning_enabled,
        }
        local hand_db = {
            ranged = { bar_texture_key = "Minimalist", text_font = "Expressway", text_size = 14 },
            mainhand = { bar_width = 200, bar_height = 14 },
            offhand = { bar_width = 200, bar_height = 14 },
        }
        local ranged_bar_frame = new_region("Frame", "RangedBarFrame", env.UIParent)
        ranged_bar_frame.width = 275
        ranged_bar_frame.height = 20
        ranged_bar_frame.bottom = opts.ranged_bottom or -120
        -- The bar's visuals frame is where bars.lua keeps the fill textures and the
        -- paladin/hunter overlays draw (the hunter cast zone parents here).
        ranged_bar_frame.visuals_frame = new_region("Frame", "RangedVisualsFrame", ranged_bar_frame)
        ranged_bar_frame.visuals_frame.width = 273
        ranged_bar_frame.visuals_frame.height = 18
        local ranged_anchor = new_region("Frame", "RangedAnchorFrame", env.UIParent)
        if not opts.no_ranged_frame then
            ranged_anchor.bar_frame = ranged_bar_frame
        end
        local mh_anchor = new_region("Frame", "MHAnchorFrame", env.UIParent)
        mh_anchor.height = 14
        mh_anchor.center_y = -142
        mh_anchor.points[1] = { point = "CENTER", relative = env.UIParent, x = 0, y = -142 }
        local oh_anchor = new_region("Frame", "OHAnchorFrame", env.UIParent)
        oh_anchor.height = 14
        oh_anchor.center_y = -158
        oh_anchor.points[1] = { point = "CENTER", relative = env.UIParent, x = 0, y = -158 }
        ST.latency = { world_ms = opts.world_ms or 0 }
        ST.has_attackable_target = opts.has_target ~= false
        ST.ranged = {
            anchor_frame = ranged_anchor,
            start = opts.ranged_start,
            speed = opts.ranged_speed,
            synced_duration = opts.ranged_synced,
        }
        ST.mainhand = { anchor_frame = mh_anchor }
        ST.offhand = { anchor_frame = oh_anchor }
        ST.get_class_table = function() return class_db end
        ST.get_hand_table = function(_, hand) return hand_db[hand] end
        ST.bar_is_enabled = function(_, hand) return hand == "ranged" and sb.ranged_available end

        env.LibStub = function(major)
            if major == "AceAddon-3.0" then
                return { GetAddon = function() return ST end }
            end
            if major == "LibSharedMedia-3.0" then
                return {
                    Fetch = function(_, kind, key)
                        if kind == "font" then
                            -- The font chain (utils.lua) has to survive a key that no
                            -- longer resolves (the operator's font lives in another
                            -- addon's LSM registration) and a Fetch that throws.
                            if opts.lsm_throw then
                                error("LSM fetch failed", 2)
                            end
                            if opts.lsm_font_nil then
                                return nil
                            end
                            return "Fonts\\FIXEDFONT.TTF"
                        end
                        return key
                    end,
                }
            end
            if major == "LibWindow-1.1" then
                return {
                    RestorePosition = function(frame)
                        sb.calls.restore = sb.calls.restore + 1
                        frame.restored = frame.restored + 1
                    end,
                }
            end
            return {}
        end

        -- The real TOC order: hunter_window before hunter_ui before classes/hunter.
        local utils = assert(loadfile(ROOT .. "utils.lua"))
        setfenv(utils, env)
        utils("SwedgeTimer", st)

        local hw_mod = assert(loadfile(ROOT .. "hunter_window.lua"))
        setfenv(hw_mod, env)
        hw_mod("SwedgeTimer", st)

        -- hunter_ui registers its per-subfeature guard labels/sites at load (R3).
        local guard_mod = assert(loadfile(ROOT .. "guard.lua"))
        setfenv(guard_mod, env)
        guard_mod("SwedgeTimer", st)

        local ui_mod = assert(loadfile(ROOT .. "hunter_ui.lua"))
        setfenv(ui_mod, env)
        ui_mod("SwedgeTimer", st)

        local class_mod = assert(loadfile(ROOT .. "classes/hunter.lua"))
        setfenv(class_mod, env)
        class_mod("SwedgeTimer", st)
        -- Same activation as build(): classes/hunter.lua registers its body as a
        -- loader (operator order 2026-10-21), so this sandbox must run it too.
        assert(type(st.class_loaders) == "table"
            and type(st.class_loaders["HUNTER"]) == "function",
            "classes/hunter.lua registers the HUNTER loader (build_ui)")
        st.class_loaders["HUNTER"]()

        sb.st = st
        sb.ST = ST
        sb.env = env
        sb.class_db = class_db
        sb.hand_db = hand_db
        sb.mh_anchor = mh_anchor
        sb.oh_anchor = oh_anchor
        sb.ranged_bar_frame = ranged_bar_frame
        return sb
    end
end

--=========================================================================================
-- 1) Exact yards, zero protected calls: init + several polls
--=========================================================================================

--=========================================================================================
-- 0) The vendored LibRangeCheck, loaded as shipped: no interact checker exists
--=========================================================================================
local LIB_PATH = ROOT .. "Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua"
local function read_file(path)
    local f = assert(io.open(path, "r"), "cannot read " .. path)
    local text = f:read("*a")
    f:close()
    return text
end
local function count_plain(src, needle)
    local count, pos = 0, 1
    while true do
        local at = src:find(needle, pos, true)
        if not at then break end
        count = count + 1
        pos = at + #needle
    end
    return count
end

do
    local src = read_file(LIB_PATH)
    eq(count_plain(src, "CheckInteractDistance("), 0,
        "static pin: the vendored library carries zero CheckInteractDistance calls")

    -- Model the failing client: no spellbook data, no legacy range API, no item API -
    -- the shape where the retired ladder used to fall back to the interact checkers.
    local sb = { interactions = 0 }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.WOW_PROJECT_ID = 5
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.C_EventUtils = { IsEventValid = function() return false end }
    env.CreateFrame = function()
        local f = {}
        setmetatable(f, {
            __index = function(t, key)
                if type(key) ~= "string" or not key:match("^[A-Z]") then
                    return nil
                end
                local fn = function() end
                rawset(t, key, fn)
                return fn
            end,
        })
        function f:RegisterEvent() end
        function f:UnregisterEvent() end
        function f:IsEventRegistered() return false end
        function f:SetScript() end
        return f
    end
    -- The item source the library captures at load (harm item names for minRangeCheck).
    env.C_Item = {
        GetItemInfo = function() return nil end,
        IsItemInRange = function()
            error("C_Item.IsItemInRange is blocked for addon code")
        end,
    }
    env.UnitClass = function() return "Hunter", "HUNTER" end
    env.UnitRace = function() return "Orc", "Orc" end
    env.GetTime = function() return 100 end
    env.GetInventorySlotInfo = function() return 16 end
    env.GetInventoryItemLink = function() return nil end
    env.UnitExists = function() return true end
    env.UnitCanAttack = function() return true end
    env.UnitCanAssist = function() return false end
    env.UnitIsDeadOrGhost = function() return false end
    env.UnitIsVisible = function() return true end
    env.BOOKTYPE_SPELL = "spell"
    env.tinsert = table.insert
    env.tremove = table.remove
    env.wipe = function(t)
        for i = #t, 1, -1 do t[i] = nil end
        return t
    end
    env.CheckInteractDistance = function()
        sb.interactions = sb.interactions + 1
        error("CheckInteractDistance is protected on TBC Anniversary")
    end
    env.LibStub = {
        NewLibrary = function(_, major)
            sb.library = {}
            return sb.library
        end,
    }
    local chunk = assert(loadfile(LIB_PATH), "the vendored LibRangeCheck must load")
    setfenv(chunk, env)
    local ok_load, load_err = pcall(chunk)
    check(ok_load, "the vendored LibRangeCheck loads as shipped (" .. tostring(load_err) .. ")")
    local lib = sb.library
    check(type(lib) == "table", "the library registered itself")
    if type(lib) == "table" then
        local ok_init, init_err = pcall(lib.init, lib)
        check(ok_init, "init() does not throw on the empty-list client (" .. tostring(init_err) .. ")")
        eq(#lib.harmRC, 0, "the harm checker list is empty")
        eq(#lib.miscRC, 0, "the misc checker list is empty")
        local ok_range, min_range = pcall(lib.GetRange, lib, "target")
        check(ok_range, "GetRange() does not throw with no checker (" .. tostring(min_range) .. ")")
        eq(min_range, nil, "GetRange() reports no estimate")
        eq(select(2, pcall(lib.GetRange, lib, "target")), nil, "GetRange() reports no max")
        local max_checker, max_band = lib:GetHarmMaxChecker(35)
        eq(max_checker, nil, "GetHarmMaxChecker(35) answers no checker")
        eq(max_band, nil, "GetHarmMaxChecker(35) answers no band")
        local min_checker, min_band = lib:GetHarmMinChecker(2)
        eq(min_checker, nil, "GetHarmMinChecker(2) answers no checker")
        eq(min_band, nil, "GetHarmMinChecker(2) answers no band")
        eq(sb.interactions, 0, "the loaded library NEVER calls the protected function")
    end
end

--=========================================================================================
-- 1) Exact yards, zero protected calls: init + several polls
--=========================================================================================
do
    local b = boot({ class = "HUNTER" })
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)
    eq(T.interfaces_are_initialised, true, "init completed")
    eq(F.interact_calls, 0, "init made zero protected CheckInteractDistance calls")

    -- Every library checker consumer is now fatal: the poll must not consult any of them.
    F.LRC.GetHarmMaxChecker = function() error("GetHarmMaxChecker must not be consulted") end
    F.LRC.GetHarmMinChecker = function() error("GetHarmMinChecker must not be consulted") end
    F.LRC.GetRange = function() error("GetRange must not be consulted") end

    for i = 1, 5 do
        F.target_yards = 4 + i * 3 -- 7, 10, 13, 16, 19
        local ok, err = pcall(T.rf_update, T)
        check(ok, "poll " .. i .. " does not error (" .. tostring(err) .. ")")
    end
    eq(F.interact_calls, 0, "five polls made zero protected calls")
    eq(F.lrc_stats.harm_max, 0, "no harm checker was requested")
    eq(F.lrc_stats.harm_min, 0, "no min checker was requested")
    eq(F.lrc_stats.range, 0, "no LRC range read happened")
    eq(F.unit_distance_calls, 6, "one exact-yards probe per poll (init + five)")
    eq(T.rf_failure_count, 0, "no poll failure was counted")
    eq(T.rf_disabled, nil, "the dead-man never fired")
    eq(#F.notices, 0, "no disable notice was printed")
end

--=========================================================================================
-- 2) The state follows exact yards (the brief's table)
--=========================================================================================
local function state_after(b, yards, checked)
    local T, F = b.ST, b.sb
    F.target_yards = yards
    F.target_checked = checked
    local ok, err = pcall(T.update_range_state, T)
    check(ok, "update_range_state at " .. tostring(yards) .. " yd does not error ("
        .. tostring(err) .. ")")
    return {
        melee = T.in_melee_range,
        ranged = T.in_ranged_range,
        distance = T.target_distance,
        min = T.target_min_range,
        max = T.target_max_range,
    }
end

do
    local b = boot({ class = "PALADIN" })
    fire_stl_ready(b)
    fire_lrc_checkers(b)

    local s = state_after(b, 4)
    eq(s.melee, true, "4 yd is melee")
    eq(s.ranged, false, "4 yd is not also ranged")
    s = state_after(b, 5)
    eq(s.melee, true, "5 yd (the melee boundary) is melee")
    eq(s.ranged, false, "5 yd is not ranged")
    s = state_after(b, 5.5)
    eq(s.melee, false, "5.5 yd is outside melee")
    eq(s.ranged, true, "5.5 yd is ranged")
    s = state_after(b, 8)
    eq(s.melee, false, "8 yd is outside melee")
    eq(s.ranged, true, "8 yd is inside the 30 yd paladin budget")
    s = state_after(b, 20)
    eq(s.ranged, true, "20 yd is ranged")
    s = state_after(b, 30)
    eq(s.ranged, true, "30 yd (the paladin boundary) is ranged")
    s = state_after(b, 31)
    eq(s.melee, false, "31 yd is outside melee")
    eq(s.ranged, false, "31 yd is outside the 30 yd paladin budget")
    s = state_after(b, 40)
    eq(s.melee, false, "40 yd is outside melee")
    eq(s.ranged, false, "40 yd is outside ranged")

    -- Unknown: nil OR an unchecked reading is never melee and never a guess.
    s = state_after(b, nil)
    eq(s.melee, false, "nil is not melee")
    eq(s.ranged, false, "nil is not ranged")
    eq(s.distance, nil, "nil stays nil (never a zero)")
    eq(s.min, nil, "nil clears the min text")
    eq(s.max, nil, "nil clears the max text")
    s = state_after(b, 8, false)
    eq(s.melee, false, "an unchecked reading is not melee")
    eq(s.ranged, false, "an unchecked reading is not ranged")
    eq(s.distance, nil, "an unchecked reading is unknown, never 8")

    -- The hunter budget is 35 yd, not the paladin 30.
    local hb = boot({ class = "HUNTER" })
    fire_stl_ready(hb)
    fire_lrc_checkers(hb)
    s = state_after(hb, 8)
    eq(s.ranged, true, "hunter: 8 yd is ranged")
    s = state_after(hb, 34)
    eq(s.ranged, true, "hunter: 34 yd is ranged")
    s = state_after(hb, 35)
    eq(s.ranged, true, "hunter: 35 yd (boundary) is ranged")
    s = state_after(hb, 36)
    eq(s.ranged, false, "hunter: 36 yd is out of range")
end

--=========================================================================================
-- 3) The text fields + ST.target_distance are fed from the exact reading
--=========================================================================================
do
    local b = boot({ class = "PALADIN" })
    local T, F = b.ST, b.sb
    fire_stl_ready(b)
    fire_lrc_checkers(b)

    F.target_yards = 4.4
    T:update_range_state()
    near(T.target_distance, 4.4, "ST.target_distance is the exact reading")
    eq(T.target_min_range, 4, "4.4 yd floors the min text")
    eq(T.target_max_range, 5, "4.4 yd ceils the max text")

    F.target_yards = 12.2
    T:update_range_state()
    near(T.target_distance, 12.2, "ST.target_distance follows the next reading")
    eq(T.target_min_range, 12, "12.2 yd floors the min text")
    eq(T.target_max_range, 13, "12.2 yd ceils the max text")

    F.target_yards = 12
    T:update_range_state()
    eq(F.interact_calls, 0, "state updates never touch the protected function")
end

--=========================================================================================
-- 4) The range state works with LibRangeCheck never reporting (deadline path)
--=========================================================================================
do
    local b = boot({ class = "HUNTER" })
    local T, F = b.ST, b.sb
    -- Any consultation of the library is fatal: it never reports, so nothing may read it.
    F.LRC.GetHarmMaxChecker = function() error("LRC must not be consulted") end
    F.LRC.GetHarmMinChecker = function() error("LRC must not be consulted") end
    F.LRC.GetRange = function() error("LRC must not be consulted") end

    fire_stl_ready(b)
    fire_deadline(b)
    eq(T.lrc_unavailable, true, "the deadline marks LRC unavailable")
    eq(T.interfaces_are_initialised, true, "init proceeds without LRC")
    eq(#F.notices, 0, "no range-disable notice is printed")
    eq(T.target_distance, 12, "the deadline path still reads exact yards")

    F.target_yards = 8
    local ok, err = pcall(T.rf_update, T)
    check(ok, "the poll keeps working without LRC (" .. tostring(err) .. ")")
    eq(T.in_ranged_range, true, "8 yd is ranged without any library")
    eq(T.in_melee_range, false, "8 yd is not melee")
    eq(F.interact_calls, 0, "still zero protected calls")
end

--=========================================================================================
-- 5) hunter_ui.update_range_helper: shows, hides, never calls the protected function
--=========================================================================================
do
    local sb = build_ui({ has_target = true, in_range = { ["Auto Shot"] = 1 }, target_yards = 7 })
    sb.ST.HUNTER.post_init(sb.ST)
    sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
    local helper = sb.st.hunter_ui.range_helper
    eq(helper.shown, true, "the strip SHOWS with a target and an answering probe")
    near(helper.tex.color[1], 0.98, "7 yd paints the sweet-spot colour")

    sb.target_yards = 12
    sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
    eq(helper.shown, true, "12 yd still shows the strip")
    near(helper.tex.color[3], 1.00, "12 yd paints the ranged colour")

    -- Every probe unknown: hide, never guess a band.
    sb.in_range = nil
    sb.target_yards = nil
    sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
    eq(helper.shown, false, "every probe unknown hides the strip")

    -- Answering again brings it back; no target hides it.
    sb.in_range = { ["Auto Shot"] = 1 }
    sb.target_yards = 12
    sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
    eq(helper.shown, true, "an answering probe brings the strip back")
    sb.ST.has_attackable_target = false
    sb.ST.HUNTER.on_bar_update(sb.ST, "ranged")
    eq(helper.shown, false, "no attackable target hides the strip")
    eq(sb.calls.interact or 0, 0, "the helper never calls the protected function")
end

--=========================================================================================
-- 6) Cascade proof: one throwing sub-feature cannot quarantine the class hook
--=========================================================================================
do
    local sb = build_ui({ has_target = true, in_range = { ["Auto Shot"] = 1 }, target_yards = 12 })
    sb.ST.HUNTER.post_init(sb.ST)
    local ui = sb.st.hunter_ui
    local aspect_calls, cast_calls = 0, 0
    local real_aspect = ui.update_aspect_icon
    ui.update_aspect_icon = function(self, db, now)
        aspect_calls = aspect_calls + 1
        return real_aspect(self, db, now)
    end
    local real_cast = ui.update_cast_bar
    ui.update_cast_bar = function(self, db, now)
        cast_calls = cast_calls + 1
        return real_cast(self, db, now)
    end
    -- The retired probe's role: a sub-feature that throws on EVERY frame.
    ui.update_range_helper = function() error("range helper exploded") end

    local class_site = "class:HUNTER:on_bar_update"
    local class_runs = 0
    for i = 1, 30 do
        local ok, err = pcall(sb.st.guard.run, sb.ST, class_site, function()
            class_runs = class_runs + 1
            ui.update(sb.ST)
        end, sb.ST)
        check(ok, "frame " .. i .. ": the class hook does not error (" .. tostring(err) .. ")")
    end
    eq(class_runs, 30, "the class hook ran on every frame")
    eq(aspect_calls, 30, "the aspect sub-feature kept running every frame")
    eq(cast_calls, 30, "the cast-bar sub-feature kept running every frame")
    eq(sb.ST.bar_hook_errors.by_site["hunter_ui:range_helper"], 25,
        "the throwing sub-feature was quarantined at the shared threshold")
    check(sb.ST.bar_hook_errors.quarantined["hunter_ui:range_helper"] == true,
        "the throwing sub-feature is the only quarantined site")
    eq(sb.ST.bar_hook_errors.by_site[class_site], nil,
        "the class hook site NEVER saw a failure")
    eq(sb.ST.bar_hook_errors.quarantined[class_site], nil,
        "the class hook site was never quarantined")
end

--=========================================================================================
-- 7) A throwing class post_init is isolated; init_libs still completes
--=========================================================================================
do
    local b = boot({ class = "PALADIN" })
    local T, F = b.ST, b.sb
    -- The class loader normally installs the fixture's counting hook. Replace it with
    -- one that throws, exactly like a class module with a bad probe at post_init.
    b.st.class_loaders["PALADIN"] = function()
        b.ST.PALADIN = b.ST.PALADIN or {}
        b.ST.PALADIN.post_init = function() error("class post_init exploded") end
    end
    fire_stl_ready(b)
    local ok, err = pcall(fire_lrc_checkers, b)
    check(ok, "init_libs does not propagate the class post_init throw (" .. tostring(err) .. ")")
    eq(T.interfaces_are_initialised, true, "init completed despite the throwing class hook")
    local errors = T.bar_hook_errors
        or { by_site = {}, first_reported = {}, quarantined = {} }
    eq(errors.by_site["class:PALADIN:post_init"], 1,
        "the class post_init site is counted")
    check(errors.first_reported["class:PALADIN:post_init"] == true,
        "the class post_init failure is reported once")
    eq(errors.quarantined["class:PALADIN:post_init"], nil,
        "one throw does not quarantine the site")
    check((F.counts.bar_inactive or 0) >= 1, "the rest of post_init still ran its hand loop")
    eq(F.diag.calls, 1, "the readiness self-report still ran")
end

if failures == 0 then
    print("PASS  range_source_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  range_source_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
