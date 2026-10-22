-- tests/practice_ui_state.lua: offline execution tests for the Twist Practice UI
-- (practice_ui.lua, the addon's largest module) over the real compat.lua + utils.lua +
-- practice.lua in a sandbox.
--
-- Sandbox discipline: like tests/hunter_state.lua, the real compat.lua is loaded with
-- every stub mirrored into _G for the duration of its load (compat reads several legacy
-- globals through rawget(_G, ...), which a setfenv environment cannot shadow), then
-- utils.lua, the pure practice.lua engine and practice_ui.lua load under setfenv.
-- C_Timer.After callbacks are captured so the combat-lockdown init retry can be fired by
-- hand, InCombatLockdown is controllable, and the clock behind st.api.get_time() is
-- scripted.
--
-- Covered here: init frame construction and the lockdown retry; session start/stop/
-- toggle and both panel buttons; the real-combat pause with every shifted simulation
-- deadline; the driver tick (swing grading, swing restart, mainhand mirror, result
-- popup); the gcd mirror's change latch; cast_key's pause guard and flag routing; the
-- result popup's text/colour/fade/font; the set-once cooldown swipes; pre-init hook
-- safety; and the option gates (practice_weapon_speed, the result keys, panel offsets).
-- Run from the repo root: lua5.1 tests/practice_ui_state.lua  (any cwd works).

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
local function read(path)
    local f = assert(io.open(ROOT .. path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end
local function count_keys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
-- Cooldown swipe bookkeeping: the frame stub records every SetCooldown(start, duration);
-- activations carry the full duration, clears are the (0, 0) calls.
local function swipe_activations(calls, duration)
    local n = 0
    for i = 1, #calls do
        if calls[i].duration == duration then n = n + 1 end
    end
    return n
end
local function swipe_clears(calls)
    local n = 0
    for i = 1, #calls do
        if calls[i].duration == 0 then n = n + 1 end
    end
    return n
end

--=========================================================================================
-- Frame stubs (record what the practice UI draws and what it swipes)
--=========================================================================================
local function make_texture()
    local t = { hidden = false }
    function t:SetAllPoints() end
    function t:SetPoint() end
    function t:SetSize(w, h) t.width, t.height = w, h end
    function t:SetWidth(w) t.width = w end
    function t:SetHeight(h) t.height = h end
    function t:SetTexCoord() end
    function t:SetTexture(texture) t.texture = texture end
    function t:SetColorTexture(r, g, b, a) t.color = { r, g, b, a } end
    function t:SetVertexColor(r, g, b, a) t.vertex_color = { r, g, b, a } end
    function t:SetDesaturated(flag) t.desaturated = flag end
    function t:ClearAllPoints() t.cleared = true end
    function t:SetDrawLayer() end
    function t:SetAlpha(alpha) t.alpha = alpha end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
    function t:IsShown() return not t.hidden end
    return t
end

local function make_fontstring()
    local f = { hidden = false }
    function f:SetPoint() end
    function f:ClearAllPoints() f.point_cleared = true end
    function f:SetFontObject(obj) f.font_object = obj end
    -- SoD-faithful: SetFont with a nil path latches nothing (false, like the
    -- client); SetText with no font (neither SetFont nor SetFontObject latched)
    -- throws ("Font not set"). The result frame must carry a font before its
    -- first SetText.
    function f:SetFont(path, size, flags)
        if path == nil then
            return false
        end
        f.font = { path, size, flags }
        return true
    end
    function f:GetFont()
        -- A font object carries a font of its own (the client reports its path),
        -- so a FontString set with SetFontObject is not fontless.
        if f.font then return f.font[1] end
        if f.font_object then return f.font_object end
        return nil
    end
    function f:SetText(text)
        if f.font == nil and f.font_object == nil then
            error("Font not set", 2)
        end
        f.text = text
    end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:SetShadowColor(r, g, b, a) f.shadow_color = { r, g, b, a } end
    function f:SetShadowOffset(x, y) f.shadow_offset = { x, y } end
    function f:SetWidth(w) f.width = w end
    function f:SetWordWrap(wrap) f.word_wrap = wrap end
    function f:SetJustifyH(justify) f.justify = justify end
    function f:Hide() f.hidden = true end
    function f:Show() f.hidden = false end
    function f:IsShown() return not f.hidden end
    return f
end

local function make_frame()
    local f = { shown = true }
    function f:SetSize(w, h) f.width, f.height = w, h end
    function f:SetWidth(w) f.width = w end
    function f:SetHeight(h) f.height = h end
    function f:GetWidth() return f.width or 0 end
    function f:GetCenter() return f.center_x or 0, f.center_y or 0 end
    function f:SetPoint(point, anchor, relative_point, x, y)
        f.point = { point, anchor, relative_point, x, y }
    end
    function f:ClearAllPoints() f.point = nil end
    function f:SetFrameStrata(strata) f.strata = strata end
    function f:GetFrameStrata() return f.strata end
    function f:SetFrameLevel(level) f.frame_level = level end
    function f:GetFrameLevel() return f.frame_level or 0 end
    function f:SetClampedToScreen(clamped) f.clamped = clamped end
    function f:SetMovable(movable) f.movable = movable end
    function f:EnableMouse(enabled) f.mouse = enabled end
    function f:EnableMouseWheel(enabled) f.mouse_wheel = enabled end
    function f:EnableKeyboard(enabled) f.keyboard = enabled end
    function f:SetPropagateKeyboardInput(propagate) f.propagate_keyboard = propagate end
    function f:EnableGamePadButton(enabled) f.gamepad = enabled end
    function f:RegisterForDrag(button) f.drag_buttons = button end
    function f:RegisterForClicks(...) f.clicks = { ... } end
    function f:GetName() return f.key_name end
    function f:SetParent(parent) f.parent = parent end
    function f:SetScript(event, fn)
        f.scripts = f.scripts or {}
        f.scripts[event] = fn
    end
    function f:GetScript(event) return f.scripts and f.scripts[event] or nil end
    function f:Show() f.shown = true end
    function f:Hide() f.shown = false end
    function f:IsShown() return f.shown end
    function f:SetAlpha(alpha) f.alpha = alpha end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:GetLeft() return f.left end
    function f:GetTop() return f.top end
    function f:GetRight() return f.right end
    function f:CreateTexture() return make_texture() end
    function f:CreateFontString() return make_fontstring() end
    function f:SetBackdrop(backdrop) f.backdrop = backdrop end
    function f:SetBackdropColor(r, g, b, a) f.backdrop_color = { r, g, b, a } end
    function f:SetBackdropBorderColor(r, g, b, a) f.backdrop_border_color = { r, g, b, a } end
    -- Region / cooldown surface (also present on plain frames: unreachable there).
    function f:SetAllPoints() end
    function f:SetDrawEdge(edge) f.draw_edge = edge end
    function f:SetHideCountdownNumbers(flag) f.hide_numbers = flag end
    function f:SetCooldown(start, duration)
        f.cooldown_calls = f.cooldown_calls or {}
        f.cooldown_calls[#f.cooldown_calls + 1] = { start = start, duration = duration }
    end
    function f:Clear() f.cleared = (f.cleared or 0) + 1 end
    -- Slider surface (the timeline scrollbar).
    function f:SetMinMaxValues(lo, hi) f.min_max = { lo, hi } end
    function f:GetMinMaxValues()
        if f.min_max then
            return f.min_max[1], f.min_max[2]
        end
        return 0, 1
    end
    function f:SetValue(value) f.slider_value = value end
    function f:GetValue() return f.slider_value or 0 end
    function f:SetValueStep(step) f.value_step = step end
    function f:SetObeyStepOnDrag(flag) f.obey_step = flag end
    function f:SetOrientation(orientation) f.orientation = orientation end
    function f:SetThumbTexture(texture) f.thumb = texture end
    -- ScrollFrame surface (the timeline scroller).
    function f:SetScrollChild(child) f.scroll_child_set = child end
    function f:SetHorizontalScroll(offset) f.h_scroll = offset end
    return f
end

-- Fires the module's driver OnUpdate script with a scripted elapsed; the callers own the
-- clock (the module reads st.api.get_time(), not the frame delta).
local function drive(b, elapsed)
    local fn = b.st.practice_ui.driver:GetScript("OnUpdate")
    assert(fn, "the driver OnUpdate script is registered")
    fn(b.st.practice_ui.driver, elapsed or 0.05)
end

local SPELL_ICONS = {
    [20375] = "icon_soc",
    [31892] = "icon_sob",
    [21082] = "icon_sotc",
    [35395] = "icon_cs",
    [20271] = "icon_judge",
    [26573] = "icon_consec",
    [31884] = "icon_aw",
    [28507] = "icon_hpot",
    [33807] = "icon_abacus",
    [2825] = "icon_bl",
}

--=========================================================================================
-- Sandbox builder
--=========================================================================================
-- A fresh practice blob: the shape the AceDB default (ST.PRACTICE_DEFAULTS) carries.
local function fresh_practice_blob()
    return {
        schema_version = 1,
        progress = {
            version = 1,
            classes = {},
            global = { daily_streak = 0, unlocks = {} },
        },
        stats = {
            version = 1,
            classes = {},
            global = {
                runs = 0, attempts = 0, hits = 0, misses = 0, points = 0,
                best_session_score = 0, best_s_streak = 0, s_run = 0,
                time_active_seconds = 0, drills = {}, recent = {}, history = {},
            },
        },
    }
end

-- The drive helper for the progression section: the paladin twist that lands an A.
-- (Soc at 1.9 swaps blood->command and fades blood till 2.3; the 2.0 swing lands at
-- the 2.01 drive with a 110ms lead -> grade A.)
local function twist_attempt(b, clock)
    local F = b.sb
    F.clock = 1.9
    b.st.practice_ui.cast_key(b.ST, "soc")
    F.clock = clock or 2.01
    drive(b, 0.01)
end

-- opts.no_practice: a flavor without the pure engine (practice.lua not loaded).
-- opts.no_bar:      st.practice_ui's anchor fallback (no mainhand bar frame).
-- opts.with_db:     the addon's saved profile (the progression hook's surface).
-- opts.practice_blob: a pre-seeded db.profile.practice blob (the migration path).
-- opts.day:         the scripted calendar day the hook injects (mutable at runtime
--                    through sb.day).
-- opts.no_date:     the client exposes NO `date` global (the M4 path).
-- opts.clock_epoch: the client's clock in epoch seconds (nil = no clock at all).
-- opts.with_progress_ui: load practice_progress_ui.lua too (the shipped reset).
-- opts.project_id:  the client family the sandbox pretends to be (the compat
--                    layer's own WOW_PROJECT_ID probe; nil = WotLK Classic).
-- opts.client_spells: the spell ids the sandbox's client knows (on top of the
--                    fixed base set) - the client's own spell data.
local function build(opts)
    opts = opts or {}

    local sb = {
        clock = 0,
        lockdown = false,
        attack_speed = 2.6,
        timers = {},
        prints = {},
        frames = {},
        created_frames = 0,
        override_bindings = {},
        cleared_bindings = 0,
        tooltips = {},
        modifiers = { ctrl = false, alt = false, shift = false },
        practice_sync = 0,
        aura_change = 0,
        gcd_changes = 0,
        gcd_times = 0,
        bar_colors = 0,
        shows = 0,
        inactives = 0,
        visibilities = 0,
        last_bar_color_hand = nil,
        last_show_hand = nil,
        last_inactive_hand = nil,
        last_visibility_hand = nil,
        lsm_font = "Fonts\\LSM.ttf",
        font_requests = {},
        day = opts.day or "2026-10-19",
        practice_writes = 0,
    }

    -- The real PALADIN practice defaults (config_presets.lua): a wrong fixture value
    -- would be a fixture bug, not a module bug.
    local class_db = {
        practice_weapon_speed = 0,
        practice_result_duration = 0.8,
        practice_result_text_size = 28,
        practice_result_color_hit = { 0, 1, 0, 1 },
        practice_result_color_miss = { 1, 0.2, 0.2, 1 },
        practice_panel_x = 0,
        practice_panel_y = 0,
    }
    local hand_db = { text_font = "Expressway" }

    local bar_frame = make_frame()
    bar_frame.right, bar_frame.top = 60, 60

    -- The addon object: only the surface practice_ui touches.
    -- The six class tables live here (main.lua creates them; every class module
    -- reaches them through LibStub), so a test that drives a REAL class grader
    -- finds the class's own module.
    local ST = {
        PALADIN = {},
        ROGUE = {},
        WARRIOR = {},
        DRUID = {},
        SHAMAN = {},
        HUNTER = {},
        player_class = "PALADIN",
        active_class = "PALADIN",
        interfaces_are_initialised = true,
        in_combat = false,
        gcd = { duration = 1.5, spell_length = 1.5 },
        mainhand = { speed = 2.6 },
    }
    function ST.PALADIN.practice_sync() sb.practice_sync = sb.practice_sync + 1 end
    function ST.PALADIN.on_aura_change() sb.aura_change = sb.aura_change + 1 end
    -- The paladin's sim-path provider seams (class-isolation 2026-10-21): the
    -- shared bridge asks the ACTIVE class's provider for them.
    ST.PALADIN.practice_panel = {
        progress = {
            mode = "paladin_twist",
            scenario = "paladin_rotation",
            drills = { "paladin_twist", "paladin_aw_combo" },
        },
        session = {
            sync_sim = function(self) ST.PALADIN.practice_sync(self) end,
            clear_sim = function(self) ST.PALADIN.on_aura_change(self) end,
        },
    }
    function ST:Print(msg) sb.prints[#sb.prints + 1] = tostring(msg) end
    function ST:get_class_table() return class_db end
    function ST:get_hand_table() return hand_db end
    function ST:get_bar_frame()
        if opts.no_bar then
            return nil
        end
        return bar_frame
    end
    function ST:set_bar_color(hand)
        sb.bar_colors = sb.bar_colors + 1
        sb.last_bar_color_hand = hand
    end
    function ST:show_bar(hand)
        sb.shows = sb.shows + 1
        sb.last_show_hand = hand
    end
    function ST:on_bar_inactive(hand)
        sb.inactives = sb.inactives + 1
        sb.last_inactive_hand = hand
    end
    function ST:handle_bar_visibility(hand)
        sb.visibilities = sb.visibilities + 1
        sb.last_visibility_hand = hand
    end
    function ST:set_gcd_times_before_swing_seconds() sb.gcd_times = sb.gcd_times + 1 end
    function ST:on_gcd_length_change() sb.gcd_changes = sb.gcd_changes + 1 end

    -- The saved profile (the progression hook's surface). The real AceDB profile is
    -- a plain table; this thin proxy counts how often the practice key is REPLACED
    -- (a write), so the throttle can be pinned.
    local profile_store = {}
    local profile = setmetatable({}, {
        __index = function(_, key) return profile_store[key] end,
        __newindex = function(_, key, value)
            profile_store[key] = value
            if key == "practice" then
                sb.practice_writes = sb.practice_writes + 1
            end
        end,
    })
    sb.profile = profile
    sb.profile_store = profile_store
    if opts.with_db then
        ST.db = { profile = profile }
        function ST:get_profile_table() return self.db and self.db.profile or nil end
        -- AceDB copies the defaults into the profile, so the practice key starts as
        -- its own copy of the default blob (the default table itself stays untouched).
        profile_store.practice = opts.practice_blob or fresh_practice_blob()
    end

    local LSM = {
        -- Records the media key the module asks for, so the hand-font option path is
        -- pinned, and returns the scripted font (nil exercises the fallback).
        Fetch = function(_, mediatype, key)
            sb.font_requests[#sb.font_requests + 1] = { mediatype = mediatype, key = key }
            if opts.lsm_throw then
                error("LSM probe throw")
            end
            return sb.lsm_font
        end,
    }

    local env = setmetatable({}, { __index = _G })
    -- opts.project_id: the client family this sandbox pretends to be (the compat
    -- layer's own WOW_PROJECT_ID probe). nil = the default (WotLK Classic). The guide
    -- vocabulary is family-scoped, so a pin that reads one family's own slot set
    -- asks for that family here (2 = Classic Era, 5 = TBC, 11 = WotLK,
    -- 18 = WoW Forever).
    env.WOW_PROJECT_ID = opts.project_id or 11
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_MAINLINE = 1
    env.GetTimePreciseSec = function() return sb.clock end
    env.GetTime = function() return sb.clock end
    -- The calendar day the progression hook injects into the pure layer. Scripted
    -- so the daily streak and the daily XP cap are deterministic.
    --
    -- opts.no_date: the client exposes NO `date` global at all (the M4 path).
    -- opts.clock_epoch: the client's clock (the `time` global) in epoch seconds;
    --   nil = the client has no clock either.
    env.date = function(fmt)
        if fmt == "%Y-%m-%d" then
            return sb.day
        end
        return ""
    end
    -- The mirror below cannot restore an ABSENT global (a nil previous value drops
    -- the key from the restore table), so a global a previous build leaked into _G
    -- stays there for the rest of the run. The M4 builds need the calendar and the
    -- clock to be TRULY absent - a client that has neither - so they clear the
    -- leak themselves.
    if opts.no_date then
        env.date = nil
        _G.date = nil
    end
    if opts.clock_epoch ~= nil then
        env.time = function() return sb.epoch or opts.clock_epoch end
    else
        _G.time = nil
    end
    env.GetBuildInfo = function() return "3.3.5", "12340", "today", 38002 end
    -- The client's own standard font (the shared chain's middle step). A distinctive
    -- value proves which step carried a label; opts.std_font = false (or the older
    -- opts.no_std_font) removes it so the chain's classic-client fallback has to
    -- carry the label.
    local std_font = opts.std_font
    if std_font == nil and not opts.no_std_font then
        std_font = "Fonts\\FRIZQT__.TTF"
    end
    if std_font == false then
        std_font = nil
    end
    env.STANDARD_TEXT_FONT = std_font
    env.GameFontNormal = "GameFontNormal"
    env.GameFontHighlightSmall = "GameFontHighlightSmall"
    env.UIParent = make_frame()
    env.CreateFrame = function(kind, name, parent, template)
        sb.created_frames = sb.created_frames + 1
        local f = make_frame()
        f.kind, f.name, f.parent, f.template = kind, name, parent, template
        sb.frames[#sb.frames + 1] = f
        return f
    end
    env.InCombatLockdown = function() return sb.lockdown end
    env.C_Timer = {
        After = function(delay, callback)
            sb.timers[#sb.timers + 1] = { delay = delay, cb = callback }
        end,
    }
    -- The client's own spell data (opts.client_spells): the spell ids this sandbox's
    -- client knows, on top of the fixed base set. The common abilities resolve
    -- against the client (the class's own resolver asks the client first, the cited
    -- id ladder second), so a pin can seed the client with the rank it owns and
    -- read the resolved id back - and a client that knows NONE of the common
    -- spells resolves none of them (unknown-hides).
    local client_spells = {}
    for id, icon in pairs(SPELL_ICONS) do client_spells[id] = icon end
    for _, id in ipairs(opts.client_spells or {}) do
        client_spells[id] = "icon_spell_" .. tostring(id)
    end
    env.GetSpellInfo = function(spell_id)
        local icon = client_spells[spell_id]
        if not icon then
            return nil
        end
        return "Spell " .. spell_id, nil, icon, 0, 0, 0, spell_id
    end
    env.GetSpellTexture = function(spell_id)
        return client_spells[spell_id]
    end
    env.GetItemIcon = function(item_id)
        return "icon_item_" .. tostring(item_id)
    end
    env.IsControlKeyDown = function() return sb.modifiers.ctrl end
    env.IsAltKeyDown = function() return sb.modifiers.alt end
    env.IsShiftKeyDown = function() return sb.modifiers.shift end
    env.SetOverrideBindingClick = function(owner, _, bind, btn_name)
        sb.override_bindings[#sb.override_bindings + 1] =
            { owner = owner, bind = bind, btn = btn_name }
    end
    env.ClearOverrideBindings = function(owner)
        sb.cleared_bindings = sb.cleared_bindings + 1
        sb.override_bindings = {}
    end
    env.GameTooltip = {
        lines = {},
        shown = false,
        SetOwner = function(self, owner, anchor)
            self.owner, self.anchor = owner, anchor
        end,
        AddLine = function(self, text, r, g, b)
            self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b }
        end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    }
    env.NumberFontNormalSmallGray = "NumberFontNormalSmallGray"
    env.UnitAttackSpeed = function() return sb.attack_speed end
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        elseif major == "LibSharedMedia-3.0" then
            if opts.no_lsm then
                return nil
            end
            return LSM
        end
        return {}
    end

    -- compat.lua reads several legacy globals through rawget(_G, ...); mirror every
    -- stub into _G for the duration of its load, then restore _G exactly. The
    -- names are kept in a list as well: a name whose previous value was nil must
    -- still be restored (assigning nil removes the key), or the mirror leaks the
    -- sandbox value into every later build (the next build would then see a
    -- STANDARD_TEXT_FONT the sandbox never set).
    local mirrored, mirrored_names = {}, {}
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

    local utils = assert(loadfile(ROOT .. "utils.lua"))
    setfenv(utils, env)
    utils("SwedgeTimer", st)

    -- guard.lua owns the shared error-isolation contract (the TOCs load it right
    -- after utils.lua and before every consumer).
    local guard = assert(loadfile(ROOT .. "guard.lua"))
    setfenv(guard, env)
    guard("SwedgeTimer", st)

    -- design.lua (pure) backs the descriptor normaliser the C6 handoff must satisfy.
    local design = assert(loadfile(ROOT .. "design.lua"))
    setfenv(design, env)
    design("SwedgeTimer", st)

    -- nextaction.lua owns the rotation thresholds practice.lua delegates to (the TOCs
    -- load it before practice.lua; practice_state.lua does the same).
    local nextaction = assert(loadfile(ROOT .. "nextaction.lua"))
    setfenv(nextaction, env)
    nextaction("SwedgeTimer", st)

    -- weave.lua is the pure marker/clip math the shaman drill grades through
    -- (all TOCs load it before practice.lua; the starter refuses a session the
    -- marker cannot resolve).
    local weave = assert(loadfile(ROOT .. "weave.lua"))
    setfenv(weave, env)
    weave("SwedgeTimer", st)

    if not opts.no_practice then
        local practice = assert(loadfile(ROOT .. "practice.lua"))
        setfenv(practice, env)
        practice("SwedgeTimer", st)
    end

    -- opts.class_modules: the REAL class modules a test drives (the drill-list pick
    -- contract, section 27). The list is opt-in and ordered: the class's own pure
    -- guide first, then the class module itself. A module that fails to load fails
    -- the suite (a half-loaded class would grade nothing, and the pin would pass
    -- for the wrong reason).
    for i = 1, #(opts.class_modules or {}) do
        local path = opts.class_modules[i]
        local chunk = assert(loadfile(ROOT .. path))
        setfenv(chunk, env)
        local ok_m, err_m = pcall(chunk, "SwedgeTimer", st)
        if not ok_m then
            print("FAIL  " .. path .. " does not load under the sandbox: " .. tostring(err_m))
            os.exit(1)
        end
        -- Operator order 2026-10-21: a wrapped class file registers its body as a
        -- loader; the sandbox activates it exactly as main.lua does at init.
        local class = path:match("classes/(%a+)%.lua")
        if class and type(st.class_loaders) == "table"
            and type(st.class_loaders[class:upper()]) == "function" then
            st.class_loaders[class:upper()]()
        end
    end

    -- The pure progression + stats modules (the TOCs load them between practice.lua
    -- and practice_ui.lua; they are WoW-free, so they load in any sandbox).
    local pstats = assert(loadfile(ROOT .. "practice_stats.lua"))
    setfenv(pstats, env)
    pstats("SwedgeTimer", st)

    local pprogress = assert(loadfile(ROOT .. "practice_progress.lua"))
    setfenv(pprogress, env)
    pprogress("SwedgeTimer", st)

    local pui = assert(loadfile(ROOT .. "practice_ui.lua"))
    setfenv(pui, env)
    local ok, err = pcall(pui, "SwedgeTimer", st)
    if not ok then
        print("FAIL  practice_ui.lua does not load under the sandbox: " .. tostring(err))
        os.exit(1)
    end

    -- The Progress page's read model + reset (the real module): the M1 pin drives
    -- the SHIPPED reset path instead of a copy of it. The module creates no frame
    -- at load, so the frame census is untouched.
    if opts.with_progress_ui then
        local ppui = assert(loadfile(ROOT .. "practice_progress_ui.lua"))
        setfenv(ppui, env)
        local ok_p, err_p = pcall(ppui, "SwedgeTimer", st)
        if not ok_p then
            print("FAIL  practice_progress_ui.lua does not load under the sandbox: " .. tostring(err_p))
            os.exit(1)
        end
    end

    sb.env, sb.st, sb.ST, sb.class_db, sb.hand_db, sb.bar_frame = env, st, ST, class_db, hand_db, bar_frame
    return { env = env, st = st, ST = ST, sb = sb }
end

--=========================================================================================
-- Fixture: the class modules' practice-panel provider
--
-- The real class modules publish `practice_panel` (class-isolation 2026-10-21): the
-- shared practice UI reads that ONE contract and never names a class. This suite's
-- hand-built class tables are the sandbox's class modules, so they publish the same
-- contract here. The closures read T.<CLASS>.<fn> dynamically, so a test that stubs
-- a class function keeps driving the shared layer exactly as before the contract.
--=========================================================================================
local function fixture_panel(b, T, cls)
    local M = T[cls]
    local practice = b.st.practice
    local panel = { session = {} }
    local session = panel.session
    local function now_() return b.st.api.get_time() end

    if cls == "HUNTER" then
        panel.drill_key = "hunter_forced_move"
        panel.def_type = "shot"
        panel.title = "|cFFFF8800Forced-Move Practice|r"
        panel.idle_status = "Drill idle"
        panel.hint_active = "Click a shot to cast. /st practice or the X button stops."
        panel.hint_stopped = "Press Start Fight, or cast shots with the icon grid."
        panel.drift_message = "Practice mode is not available (hunter drill key drifted)."
        panel.progress = {
            mode = "hunter_forced_move",
            scenario = "hunter_rotation",
            drills = { "hunter_forced_move" },
        }
        panel.scenario_key = function()
            if type(M.get_practice_scenario_key) ~= "function" then return nil end
            return M.get_practice_scenario_key()
        end
        panel.order = function() return M.PRACTICE_SHOT_ORDER end
        panel.label = function(key) return M.practice_shot_label(key) end
        panel.spell_id = function(key) return M.practice_shot_spell_id(key) end
        panel.status = function(ui, now)
            if type(M.practice_status) ~= "function" then return nil end
            return M.practice_status(ui.hunter_session, now)
        end
        panel.fight_elapsed = function(ui, now)
            if type(M.practice_fight_elapsed) ~= "function" then return nil end
            return M.practice_fight_elapsed(ui.hunter_session, now)
        end
        session.running = function(ui) return ui.hunter_session ~= nil end
        session.active = function(ui)
            return ui.hunter_session and ui.hunter_session.active
        end
        session.start = function(self, now, ui)
            if type(M.practice_new_session) ~= "function"
                or type(M.practice_begin_session) ~= "function"
                or type(M.practice_tick) ~= "function"
                or type(M.practice_cast) ~= "function" then
                return false
            end
            local ok, s = pcall(M.practice_new_session, now)
            if not ok or s == nil then return false end
            local ok_begin, begun = pcall(M.practice_begin_session, s, now)
            if not ok_begin or begun == false then return false end
            ui.hunter_session = s
            ui.hunter_out = {}
            return true
        end
        session.tick = function(self, now, elapsed, ui)
            local s = ui.hunter_session
            if s == nil then return end
            ui.hunter_out = M.practice_tick(s, now, elapsed, ui.hunter_out)
            if ui.hunter_out and ui.hunter_out.move_started then
                ui.show_result(self, "MOVE!")
            end
            ui.update_fight_timer(self, now)
        end
        session.cast = function(self, key, ui)
            if ui.hunter_session == nil then return nil end
            return M.practice_cast(ui.hunter_session, now_(), key)
        end
        session.stop = function(self, ui)
            local s = ui.hunter_session
            if s == nil then return end
            if type(M.practice_end_session) == "function" then
                M.practice_end_session(s, now_())
            end
            ui.hunter_session = nil
        end
        session.begin = function(self, now, ui)
            if ui.hunter_session and type(M.practice_begin_session) == "function" then
                M.practice_begin_session(ui.hunter_session, now)
            end
        end
        session.end_session = function(self, ui)
            if ui.hunter_session and type(M.practice_end_session) == "function" then
                M.practice_end_session(ui.hunter_session, now_())
            end
        end
        session.pause = function(self, ui, shift)
            if ui.hunter_session and type(M.practice_shift_pause) == "function" then
                M.practice_shift_pause(ui.hunter_session, shift)
            end
        end
        session.sync = function() end
        session.clear = function(self) self:handle_bar_visibility("mainhand") end
        return panel
    end

    if cls == "SHAMAN" then
        panel.drill_key = "shaman_weave"
        panel.def_type = "ability"
        panel.icon = "name"
        panel.title = "|cFFFF8800Weave Practice|r"
        panel.idle_status = "Drill idle - press Start Fight"
        panel.hint_active = "Click a cast to weave. /st practice or the X button stops."
        panel.hint_stopped = "Press Start Fight, or cast weaves with the icon grid."
        panel.drift_message = "Practice mode is not available (shaman drill key drifted)."
        panel.progress = {
            mode = "shaman_mw_weave",
            scenario = "shaman_rotation",
            drills = { "shaman_enh_priority" },
        }
        panel.scenario_key = function()
            if type(M.practice_scenario_key) ~= "function" then return nil end
            return M.practice_scenario_key()
        end
        panel.order = function() return M.PRACTICE_CAST_ORDER end
        panel.label = function(key) return M.practice_cast_label(key) end
        panel.spell_id = function(key) return M.practice_cast_spell_id(key) end
        panel.status = function(ui, now)
            if type(M.practice_status) ~= "function" then return nil end
            return M.practice_status(ui.shaman_swing, now)
        end
        panel.fight_elapsed = function(ui, now)
            if type(M.practice_fight_elapsed) ~= "function" then return nil end
            return M.practice_fight_elapsed(ui.shaman_session, now)
        end
        session.running = function(ui) return ui.shaman_session ~= nil end
        session.active = function(ui)
            return ui.shaman_session and ui.shaman_session.active
        end
        session.start = function(self, now, ui, ctx)
            if type(M.practice_latency_seconds) ~= "function"
                or type(M.practice_cast_seconds) ~= "function"
                or type(M.new_practice_session) ~= "function"
                or type(M.tick_practice_session) ~= "function"
                or type(M.practice_cast) ~= "function" then
                return false
            end
            local duration = ctx and ctx.base_speed
            if type(duration) ~= "number" or duration <= 0 then duration = 3.5 end
            if type(self.mainhand) == "table" then
                ui.saved_hand_speed = self.mainhand.speed
            else
                ui.saved_hand_speed = nil
            end
            local ok_lat, latency = pcall(M.practice_latency_seconds)
            if not ok_lat or type(latency) ~= "number" then latency = 0 end
            local ok_cast, cast = pcall(M.practice_cast_seconds, "weave_lb")
            if not ok_cast or type(cast) ~= "number" then
                local defaults = practice and practice.harness
                    and practice.harness.WEAVE_DEFAULTS
                cast = (defaults and defaults.effective_cast) or 1.5
            end
            local harness = practice and practice.harness
            local ok_marker, marker = false, nil
            if type(harness) == "table"
                and type(harness.weave_marker_fraction) == "function" then
                ok_marker, marker = pcall(harness.weave_marker_fraction,
                    duration, cast, latency)
            end
            if not ok_marker or type(marker) ~= "number" then return false end
            local ok, s = pcall(M.new_practice_session, now, {
                swing_duration = duration,
                effective_cast = cast,
                latency = latency,
            })
            if not ok or s == nil then return false end
            ui.shaman_session = s
            ui.shaman_swing = {
                swing_duration = duration,
                swing_start = now,
                swing_ends_at = now + duration,
            }
            ui.shaman_out = {}
            ui.base_speed = duration
            return true
        end
        session.tick = function(self, now, elapsed, ui)
            local s = ui.shaman_session
            local swing = ui.shaman_swing
            if s == nil or swing == nil then return end
            local duration = swing.swing_duration
            if type(duration) ~= "number" or duration <= 0 then return end
            if s.active then
                local guard = 0
                while now >= swing.swing_ends_at and guard < 8 do
                    swing.swing_start = swing.swing_ends_at
                    swing.swing_ends_at = swing.swing_ends_at + duration
                    guard = guard + 1
                end
            end
            ui.shaman_out = M.tick_practice_session(s, now, elapsed, ui.shaman_out)
            ui.update_fight_timer(self, now)
            ui.sync_to_addon(self)
        end
        session.cast = function(self, key, ui)
            local s = ui.shaman_session
            local swing = ui.shaman_swing
            if s == nil or swing == nil then return nil end
            return M.practice_cast(s, swing, now_(), key)
        end
        session.stop = function(self, ui)
            local s = ui.shaman_session
            if s == nil then return end
            if type(M.end_practice_session) == "function" then
                M.end_practice_session(s, now_())
            end
            ui.shaman_session = nil
            ui.shaman_swing = nil
        end
        session.begin = function(self, now, ui)
            if ui.shaman_session and type(M.practice_begin_session) == "function" then
                M.practice_begin_session(ui.shaman_session, now)
            end
        end
        session.end_session = function(self, ui)
            if ui.shaman_session and type(M.end_practice_session) == "function" then
                M.end_practice_session(ui.shaman_session, now_())
            end
        end
        session.pause = function(self, ui, shift)
            local swing = ui.shaman_swing
            if swing then
                swing.swing_start = swing.swing_start + shift
                swing.swing_ends_at = swing.swing_ends_at + shift
            end
        end
        session.sync = function(self, ui)
            local swing = ui.shaman_swing
            local s = ui.shaman_session
            local now = now_()
            local d = self.mainhand
            if swing and type(swing.swing_duration) == "number" and swing.swing_duration > 0
                and type(swing.swing_start) == "number"
                and type(swing.swing_ends_at) == "number" then
                d.speed = swing.swing_duration
                d.start = swing.swing_start
                d.ends_at = swing.swing_ends_at
                d.is_paused = not (s and s.active)
            else
                d.speed = ui.base_speed or d.speed or 3.5
                d.start = now
                d.ends_at = now + (d.speed or 3.5)
                d.is_paused = true
            end
            d.is_full = false
            if ui.combat_paused then d.is_paused = true end
            if type(M.practice_sync) == "function" then M.practice_sync(self) end
            self:show_bar("mainhand")
        end
        session.clear = function(self, ui)
            local now = now_()
            local d = self.mainhand
            d.speed = ui.saved_hand_speed or d.speed
            local speed = d.speed or 3.5
            d.start = now - speed
            d.ends_at = now
            d.current_progress = 1
            d.is_full = true
            d.is_paused = false
            self:on_bar_inactive("mainhand")
            self:handle_bar_visibility("mainhand")
        end
        return panel
    end

    if cls == "ROGUE" then
        panel.drill_key = "rogue_energy_pool"
        panel.def_type = "drill"
        panel.title = "|cFFFF8800Pool Practice|r"
        panel.idle_status = "Drill idle - press Start Fight"
        panel.hint_active = "Click a cast to drill. /st practice or the X button stops."
        panel.hint_stopped = "Press Start Fight, or cast drills with the icon grid."
        panel.drift_message = "Practice mode is not available (rogue drill key drifted)."
        panel.progress = {
            mode = "rogue_energy_pool",
            scenario = "rogue_rotation",
            drills = { "rogue_energy_pool", "rogue_ss_window" },
        }
        panel.scenario_key = function()
            if type(M.practice_scenario_key) ~= "function" then return nil end
            return M.practice_scenario_key()
        end
        panel.order = function()
            if type(M.practice_cast_order) == "function" then
                return M.practice_cast_order()
            end
            return M.PRACTICE_CAST_ORDER
        end
        panel.label = function(key) return M.practice_cast_label(key) end
        panel.spell_id = function(key) return M.practice_cast_spell_id(key) end
        panel.status = function(ui, now)
            if type(M.practice_status) ~= "function" then return nil end
            return M.practice_status({ tick = ui.rogue_tick, swing = ui.rogue_swing }, now)
        end
        panel.fight_elapsed = function(ui, now)
            if type(M.practice_fight_elapsed) ~= "function" then return nil end
            return M.practice_fight_elapsed(ui.rogue_session, now)
        end
        session.running = function(ui) return ui.rogue_session ~= nil end
        session.active = function(ui)
            return ui.rogue_session and ui.rogue_session.active
        end
        session.start = function(self, now, ui, ctx)
            if type(M.new_practice_session) ~= "function"
                or type(M.new_ss_session) ~= "function"
                or type(M.practice_begin_session) ~= "function"
                or type(M.tick_practice_session) ~= "function"
                or type(M.practice_cast) ~= "function" then
                return false
            end
            local duration = ctx and ctx.base_speed
            if type(duration) ~= "number" or duration <= 0 then duration = 3.5 end
            if type(self.mainhand) == "table" then
                ui.saved_hand_speed = self.mainhand.speed
            else
                ui.saved_hand_speed = nil
            end
            local ok, s = pcall(M.new_practice_session, now, {})
            if not ok or s == nil then return false end
            local ok_ss, ss = pcall(M.new_ss_session, now, {})
            if not ok_ss then ss = nil end
            local ok_begin, begun = pcall(M.practice_begin_session, s, now)
            if not ok_begin or begun == false then return false end
            if ss then pcall(M.practice_begin_session, ss, now) end
            ui.rogue_session = s
            ui.rogue_ss_session = ss
            ui.rogue_tick = { start = now, interval = 2 }
            ui.rogue_swing = {
                swing_duration = duration,
                swing_start = now,
                swing_ends_at = now + duration,
            }
            ui.rogue_out = {}
            ui.base_speed = duration
            return true
        end
        session.tick = function(self, now, elapsed, ui)
            local s = ui.rogue_session
            if s == nil then return end
            local swing = ui.rogue_swing
            if swing and s.active then
                local duration = swing.swing_duration
                if type(duration) == "number" and duration > 0 then
                    local guard = 0
                    while now >= swing.swing_ends_at and guard < 8 do
                        swing.swing_start = swing.swing_ends_at
                        swing.swing_ends_at = swing.swing_ends_at + duration
                        guard = guard + 1
                    end
                end
            end
            ui.rogue_out = M.tick_practice_session(s, now, elapsed, ui.rogue_out)
            if ui.rogue_ss_session then
                M.tick_practice_session(ui.rogue_ss_session, now, elapsed, ui.rogue_out)
            end
            ui.update_fight_timer(self, now)
            ui.sync_to_addon(self)
        end
        session.cast = function(self, key, ui)
            if ui.rogue_session == nil then return nil end
            local drill = {
                energy = ui.rogue_session,
                ss = ui.rogue_ss_session,
                tick = ui.rogue_tick,
                swing = ui.rogue_swing,
            }
            return M.practice_cast(drill, now_(), key)
        end
        session.stop = function(self, ui)
            local now = now_()
            if ui.rogue_session and type(M.end_practice_session) == "function" then
                M.end_practice_session(ui.rogue_session, now)
            end
            ui.rogue_session = nil
            if ui.rogue_ss_session and type(M.end_practice_session) == "function" then
                M.end_practice_session(ui.rogue_ss_session, now)
            end
            ui.rogue_ss_session = nil
            ui.rogue_tick = nil
            ui.rogue_swing = nil
        end
        session.begin = function(self, now, ui)
            if ui.rogue_session and type(M.practice_begin_session) == "function" then
                M.practice_begin_session(ui.rogue_session, now)
            end
        end
        session.end_session = function(self, ui)
            local now = now_()
            if ui.rogue_session and type(M.end_practice_session) == "function" then
                M.end_practice_session(ui.rogue_session, now)
            end
        end
        session.pause = function(self, ui, shift)
            if type(M.practice_shift_pause) == "function" then
                M.practice_shift_pause({
                    tick = ui.rogue_tick,
                    swing = ui.rogue_swing,
                }, shift)
            end
        end
        session.sync = function(self, ui)
            local swing = ui.rogue_swing
            local s = ui.rogue_session
            local now = now_()
            local d = self.mainhand
            if swing and type(swing.swing_duration) == "number" and swing.swing_duration > 0
                and type(swing.swing_start) == "number"
                and type(swing.swing_ends_at) == "number" then
                d.speed = swing.swing_duration
                d.start = swing.swing_start
                d.ends_at = swing.swing_ends_at
                d.is_paused = not (s and s.active)
            else
                d.speed = ui.base_speed or d.speed or 3.5
                d.start = now
                d.ends_at = now + (d.speed or 3.5)
                d.is_paused = true
            end
            d.is_full = false
            if ui.combat_paused then d.is_paused = true end
            if type(M.practice_sync) == "function" then M.practice_sync(self) end
            self:show_bar("mainhand")
        end
        session.clear = function(self, ui)
            local now = now_()
            local d = self.mainhand
            d.speed = ui.saved_hand_speed or d.speed
            local speed = d.speed or 3.5
            d.start = now - speed
            d.ends_at = now
            d.current_progress = 1
            d.is_full = true
            d.is_paused = false
            self:on_bar_inactive("mainhand")
            self:handle_bar_visibility("mainhand")
        end
        return panel
    end

    if cls == "DRUID" then
        panel.drill_key = "druid_powershift"
        panel.def_type = "shift"
        panel.title = "|cFFFF8800Powershift Practice|r"
        panel.idle_status = "Drill idle - press Start Fight"
        panel.hint_active = "Click to powershift. /st practice or the X button stops."
        panel.hint_stopped = "Press Start Fight, or cast to powershift."
        panel.drift_message = "Practice mode is not available (druid drill key drifted)."
        panel.progress = {
            mode = "druid_powershift_rework",
            scenario = "druid_rotation",
            drills = { "druid_finisher_order" },
        }
        panel.scenario_key = function()
            if type(M.practice_scenario_key) ~= "function" then return nil end
            return M.practice_scenario_key()
        end
        panel.order = function() return { "shift" } end
        panel.label = function(key)
            if key ~= "shift" then return nil end
            return "Powershift"
        end
        panel.spell_id = function() return nil end
        panel.status = function(ui, now)
            local summary
            if type(M.practice_summary) == "function" then
                local ok, sum = pcall(M.practice_summary, ui.druid_session)
                if ok then summary = sum end
            end
            if summary and type(summary.attempts) == "number" and summary.attempts > 0 then
                return string.format("Shifts: %d  Score: %d", summary.attempts,
                    summary.score or 0)
            end
            return nil
        end
        panel.fight_elapsed = function(ui, now)
            local s = ui.druid_session
            if s and s.active and type(s.started_at) == "number" and type(now) == "number" then
                local elapsed = now - s.started_at
                if elapsed == elapsed and elapsed >= 0 then return elapsed end
            end
            return nil
        end
        session.running = function(ui) return ui.druid_session ~= nil end
        session.active = function(ui)
            return ui.druid_session and ui.druid_session.active
        end
        session.start = function(self, now, ui)
            if type(M.new_practice_session) ~= "function"
                or type(M.tick_practice_session) ~= "function"
                or type(M.practice_shift) ~= "function" then
                return false
            end
            local ok, s = pcall(M.new_practice_session, now, {})
            if not ok or s == nil then return false end
            ui.druid_session = s
            ui.druid_out = {}
            return true
        end
        session.tick = function(self, now, elapsed, ui)
            local s = ui.druid_session
            if s == nil then return end
            ui.druid_out = M.tick_practice_session(s, now, elapsed, ui.druid_out)
            ui.update_fight_timer(self, now)
        end
        session.cast = function(self, key, ui)
            local s = ui.druid_session
            if s == nil then return nil end
            return M.practice_shift(s, now_())
        end
        session.stop = function(self, ui)
            local s = ui.druid_session
            if s == nil then return end
            if type(M.end_practice_session) == "function" then
                M.end_practice_session(s, now_())
            end
            ui.druid_session = nil
            ui.druid_out = nil
        end
        session.begin = function(self, now, ui)
            if type(M.new_practice_session) == "function" then
                local ok, s = pcall(M.new_practice_session, now, {})
                if ok and s then
                    ui.druid_session = s
                    ui.druid_out = {}
                end
            end
        end
        session.end_session = function(self, ui)
            if ui.druid_session and type(M.end_practice_session) == "function" then
                M.end_practice_session(ui.druid_session, now_())
            end
        end
        session.pause = function(self, ui, shift)
            local s = ui.druid_session
            if s and type(s.started_at) == "number" then
                s.started_at = s.started_at + shift
            end
        end
        session.sync = function() end
        session.clear = function(self) self:handle_bar_visibility("mainhand") end
        return panel
    end

    return nil
end

--=========================================================================================
-- 1) Load surface: the module loads and exposes every documented entry point
--=========================================================================================
local base = build()
local bst, bsb, bui = base.st, base.sb, base.st.practice_ui
check(type(bst.practice) == "table", "the pure engine (st.practice) is loaded first")
check(type(bui) == "table", "practice_ui.lua defines st.practice_ui")
eq(bsb.created_frames, 0, "no frames are created at file load")
eq(bui.panel, nil, "the panel is not created at file load")
eq(bui.result_frame, nil, "the result frame is not created at file load")
eq(bui.driver, nil, "the driver is not created at file load")
eq(bui.active, nil, "no session runs at load")
local ENTRY_POINTS = {
    "init", "build_result_frame", "build_panel", "build_bar_mappings", "is_active", "toggle",
    "start", "stop", "toggle_fight", "start_fight", "stop_fight", "tick", "sync_to_addon",
    "shift_sim_times", "clear_addon_state", "cast_key", "refresh_icons", "update_info",
    "update_button", "update_hint", "show_result", "update_result_fade", "update_result_font",
    "apply_settings", "save_position", "build_key_buttons", "rebind_keys",
    "update_keybind_labels", "start_key_capture", "finish_key_capture", "cancel_key_capture",
    "reset_keybinds", "click_haste", "update_haste_buttons", "set_haste_buttons_enabled",
    "set_locked_rotation", "build_rotation_display", "save_rotation_position",
    "update_rotation_display", "set_step_texture", "build_timeline", "render_timeline",
    "reset_timeline_pools", "toggle_timeline", "update_timeline_button", "build_proc_icons",
    "update_proc_icons", "attach_overlay", "detach_overlay", "detach_all_overlays",
    "flash_overlay", "update_overlays", "update_fight_timer",
    "load_bests", "maybe_save_bests", "best_score_text", "update_score",
    "save_timeline_position", "build_hunter_report", "render_hunter_report",
    "toggle_hunter_report",
    -- The progression hook (the gamification step 2).
    "ensure_progress_profile", "persist_progress", "maybe_persist_progress",
    "begin_progress_session", "record_progress_attempt", "record_graded_attempt",
    "end_progress_session", "update_badge", "badge_is_enabled", "set_badge_enabled",
}
for i = 1, #ENTRY_POINTS do
    check(type(bui[ENTRY_POINTS[i]]) == "function", "practice_ui.lua exposes " .. ENTRY_POINTS[i])
end

--=========================================================================================
-- 2) init: frames out of combat, nothing plus an armed retry under lockdown
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb

    -- Lockdown: nothing is created, exactly one retry is armed (and only one).
    F.lockdown = true
    local ok, err = pcall(u.init, T)
    check(ok, "init under combat lockdown does not error (" .. tostring(err) .. ")")
    eq(F.created_frames, 0, "no frames are created under lockdown")
    eq(u.init_retry_armed, true, "the retry is armed")
    eq(u.sim, nil, "no simulation state is created under lockdown")
    eq(u.panel, nil, "the panel is not created under lockdown")
    eq(#F.timers, 1, "exactly one retry timer is armed")
    eq(F.timers[1].delay, 1, "the retry waits 1 s")
    u.init(T)
    eq(#F.timers, 1, "a second init while the retry is pending does not stack timers")

    -- Lockdown lifted: firing the captured C_Timer callback creates everything.
    F.lockdown = false
    F.timers[1].cb()
    eq(u.init_retry_armed, false, "firing the retry clears the flag")
    eq(u.panel ~= nil, true, "the retry creates the panel")
    eq(F.created_frames, 70, "init creates exactly the documented 70 frames " ..
        "(35 panel/result/driver + 10 key buttons + 6 rotation display + " ..
        "6 timeline shell + 4 proc icons + 8 panel buttons + 1 level badge)")
    eq(u.sim ~= nil, true, "the retry creates the simulation")
    local frames_after = F.created_frames
    u.init(T)
    eq(F.created_frames, frames_after, "a further init is a no-op")

    -- The created surface.
    check(type(u.out) == "table" and type(u.cast_out) == "table" and type(u.grade_out) == "table",
        "the reused out tables exist")
    eq(u.combat_paused, false, "the pause flag starts clear")
    eq(u.result_remaining, 0, "the popup timer starts clear")
    eq(count_keys(u.bar_mappings), 10, "all ten ability icons are mapped")
    eq(count_keys(u.panel.ability_icons), 10, "the panel owns every ability icon")
    eq(u.bar_mappings.cs, u.panel.ability_icons.cs, "the bar mapping points at the icon frame")
    eq(u.panel.shown, false, "the panel starts hidden")
    eq(u.driver.shown, false, "the driver starts hidden")
    eq(u.result_frame.alpha, 0, "the result popup starts transparent")
    eq(u.result_frame.text.text, "", "the result text starts empty")
    eq(u.panel.title.text, "|cFFFF8800Twist Practice|r", "the archive title")
    eq(u.panel.info_text.text, "Speed: --  GCD: --", "the info line starts at placeholder values")
    eq(u.panel.hint_text.text, "Press Start Fight, or cast seals with the icon grid.", "the stopped hint ships")
    eq(u.panel.fight_btn.label.text, "Start Fight", "the fight button starts idle")
    eq(u.panel.movable, true, "the panel is movable")
    eq(u.panel.clamped, true, "the panel is clamped to screen")
    eq(u.panel.drag_buttons, "LeftButton", "the panel drags with the left button")
    eq(u.panel.strata, "HIGH", "the panel sits at the HIGH strata")
    eq(u.result_frame.strata, "HIGH", "the result popup sits at the HIGH strata")
    check(type(u.driver:GetScript("OnUpdate")) == "function", "the driver OnUpdate is wired")
    check(u.panel.fight_btn:GetScript("OnClick") ~= nil, "the fight button is wired")
    check(u.panel.hint_text.word_wrap == true, "the hint text wraps")

    -- Icon descriptors (cooldown field / length / gcd gate matrix).
    local icons = u.panel.ability_icons
    eq(icons.cs.cooldown_field, "cs_cooldown_expires", "cs swipes from its simulated cooldown")
    eq(icons.judge.cooldown_field, "judge_cooldown_expires", "judge swipes from its simulated cooldown")
    eq(icons.aw.cooldown_field, "aw_cooldown_expires", "aw swipes from its simulated cooldown")
    eq(icons.abacus.cooldown_field, "abacus_cooldown_expires", "abacus swipes from its simulated cooldown")
    eq(icons.soc.cooldown_field, nil, "a seal has no cooldown swipe")
    eq(icons.stop.cooldown_field, nil, "stopattack has no cooldown swipe")
    eq(icons.cs.cooldown_full, 6, "cs carries its 6 s length")
    eq(icons.judge.cooldown_full, 8, "judge carries its 8 s length")
    eq(icons.aw.cooldown_full, 180, "aw carries its 180 s length")
    eq(icons.abacus.cooldown_full, 120, "abacus carries its 120 s length")
    eq(icons.cs.gcd_gated, true, "cs is gcd-gated")
    eq(icons.hpot.gcd_gated, true, "the haste pot is gcd-gated")
    eq(icons.judge.gcd_gated, false, "judge is off the gcd")
    eq(icons.aw.gcd_gated, false, "aw is off the gcd")
    eq(icons.abacus.gcd_gated, false, "the trinket is off the gcd")
    eq(icons.stop.gcd_gated, false, "stopattack is off the gcd")
    eq(icons.cs.texture.texture, "icon_cs", "the icon texture resolves through the spell data")
    eq(icons.stop.texture.texture, "Interface\\Icons\\Ability_DualWield", "stopattack uses its own texture")
    eq(icons.cs.gcd_dim.hidden, true, "the gcd dim starts hidden")
    eq(icons.cs.cooldown.hide_numbers, true, "the swipe hides countdown numbers")

    -- Anchoring: 8 px right of the bar, the result popup above it.
    eq(u.panel.point[1], "TOPLEFT", "the panel anchors to the bar's top-right")
    eq(u.panel.point[2], F.bar_frame, "the panel anchors to the mainhand bar frame")
    eq(u.panel.point[3], "TOPRIGHT", "the panel uses the bar's top-right point")
    eq(u.panel.point[4], 8, "the panel sits at the archive's 8 px gap")
    eq(u.result_frame.point[1], "BOTTOM", "the result popup anchors above the bar")
    eq(u.result_frame.point[5], 8, "the result popup sits 8 px above the bar")

    -- New panel rows (rotation line, fight timer, haste buttons, selector, timeline).
    eq(u.panel.rotation_text.text, "Rotation: --", "the rotation line starts empty")
    eq(u.panel.fight_timer_text.text, "", "the fight timer starts empty")
    eq(u.panel.bl_btn.label.text, "Bloodlust", "the Bloodlust button starts idle")
    eq(u.panel.bl_btn.countdown.text, "", "the Bloodlust countdown starts empty")
    eq(u.panel.hp_btn.label.text, "Haste Pot", "the haste pot button starts idle")
    eq(u.panel.hp_btn.countdown.text, "", "the haste pot countdown starts empty")
    eq(u.panel.dst_btn.label.text, "DST: Off", "the DST toggle starts off")
    eq(count_keys(u.panel.rot_buttons), 4, "the rotation selector has four buttons")
    eq(u.panel.rot_buttons.auto.label.text, "Raid Pull", "the auto button reads Raid Pull")
    eq(u.panel.rot_buttons["1/2"].label.text, "1/2", "the 1/2 button reads 1/2")
    eq(u.panel.timeline_btn.label.text, "Timeline", "the timeline button starts idle")
    eq(u.panel.ability_icons.cs.keybind_text.text, "", "keybind labels start empty")
    eq(count_keys(u.buttons), 10, "all ten invisible key buttons exist")
    eq(u.buttons.cs.key_name, "SwedgeTimerPracticeKeycs", "the key button name")
    eq(u.dst_enabled, false, "the DST toggle defaults off")
    eq(u.timeline_visible, false, "the timeline starts hidden")
    eq(u.timeline_event_count, 0, "no timeline events at init")
    eq(u.timeline_band_count, 0, "no rotation bands at init")
    eq(u.rotation_display.shown, false, "the rotation display starts hidden")
    eq(#u.rotation_icons, 5, "the rotation display has five icon slots")
    eq(u.timeline_frame.shown, false, "the timeline frame starts hidden")
    eq(u.timeline_frame.scroll_child ~= nil, true, "the timeline has a scroll child")
    eq(u.timeline_frame.scrollbar ~= nil, true, "the timeline has a scrollbar")
    eq(#u.timeline_frame.lane_bgs, 6, "the timeline has six lane backgrounds")
    eq(u.proc_icons.bl ~= nil, true, "the Bloodlust proc icon exists")
    eq(u.proc_icons.dst ~= nil, true, "the DST proc icon exists")
    eq(u.proc_icons.bl.shown, false, "proc icons start hidden")

    -- A flavor without an engine creates nothing and says so.
    local np = build({ no_practice = true })
    local nu, nT, nF = np.st.practice_ui, np.ST, np.sb
    nu.init(nT)
    eq(nF.created_frames, 0, "without the engine init creates nothing")
    nu.start(nT)
    eq(nF.prints[#nF.prints], "Practice mode is not available.",
        "without the engine start reports unavailability")

    -- A flavor without a bar frame falls back to UIParent's centre (no error).
    local nb = build({ no_bar = true })
    local qu, qT = nb.st.practice_ui, nb.ST
    local ok2, err2 = pcall(qu.init, qT)
    check(ok2, "init without a bar frame does not error (" .. tostring(err2) .. ")")
    eq(qu.panel.point[1], "CENTER", "without a bar frame the panel falls back to the centre")
    local ok3, err3 = pcall(qu.save_position, qT)
    check(ok3, "save_position without a bar frame does not error (" .. tostring(err3) .. ")")
end

--=========================================================================================
-- 3) Session lifecycle: start / stop / toggle, both buttons, state restoration
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)

    -- In combat: the addon flag refuses the session.
    T.in_combat = true
    u.start(T)
    eq(u.active, nil, "start in combat leaves the session inactive")
    eq(u.panel.shown, false, "the panel stays hidden after a refused start")
    eq(u.driver.shown, false, "the driver stays hidden after a refused start")
    eq(F.prints[#F.prints], "Practice mode cannot be started in combat.", "the combat refusal prints the reason")
    -- Combat lockdown refuses too (the client-side gate).
    T.in_combat = false
    F.lockdown = true
    u.start(T)
    eq(u.active, nil, "start under combat lockdown leaves the session inactive")
    eq(F.prints[#F.prints], "Practice mode cannot be started in combat.", "the lockdown refusal prints the same reason")
    F.lockdown = false

    -- A real session at t = 0.
    u.start(T)
    eq(u.active, true, "start activates the session")
    eq(u.is_active(), true, "is_active reports the session")
    eq(u.sim.fight_active, true, "start begins the fight")
    eq(u.sim.swing_active, true, "the first swing is in flight")
    near(u.sim.swing_ends_at, 2.0, "2.6/1.3 -> the first swing lands 2.0 s in")
    near(u.sim.effective_speed, 2.0, "the immediate Bloodlust rescales the swing speed")
    near(u.sim.effective_gcd, 1.154, "the GCD is hasted to 1.154 s")
    near(u.sim.bl_buff_expires, 40, "the immediate Bloodlust runs its 40 s")
    eq(u.base_speed, 2.6, "the equipped weapon speed is the base speed")
    eq(u.panel.shown, true, "the panel shows")
    eq(u.driver.shown, true, "the driver is live")
    eq(F.prints[#F.prints], "Practice mode started. Type /st practice to stop.", "start prints the session notice")

    -- The addon-state mirror (sync_to_addon).
    near(T.mainhand.speed, 2.0, "the mirrored bar speed is the simulated one")
    near(T.mainhand.start, 0.0, "the mirrored swing starts at the landing minus speed")
    near(T.mainhand.ends_at, 2.0, "the mirrored swing ends at the simulated swing end")
    eq(T.mainhand.is_paused, false, "the mirrored swing runs")
    eq(T.mainhand.is_full, false, "the mirrored bar is not idle-full during a session")
    near(T.gcd.duration, 1.154, "the effective GCD mirrors onto the real container")
    near(T.gcd.spell_length, 1.154, "the spell length mirrors too")
    eq(T.gcd.expires, nil, "the real GCD expiry is cleared while the sim owns it")
    check(F.practice_sync >= 1, "the seal mirror (PALADIN.practice_sync) runs")
    eq(F.bar_colors, 1, "the seal colour is applied on the session's first mirror")
    eq(F.last_bar_color_hand, "mainhand", "the colour lands on the mainhand bar")
    check(F.shows >= 1 and F.last_show_hand == "mainhand", "the session shows the bar")

    -- Panel text driven by the session.
    eq(u.panel.fight_btn.label.text, "|cFFFF0000Stop Fight|r", "the active fight label ships red")
    eq(u.panel.hint_text.text, "Click an icon to cast. /st practice or the X button stops.", "the active hint ships")
    eq(u.panel.info_text.text, "Speed: 2.0s  GCD: 1.15s", "the info line reports the simulated speed/GCD")
    local prints_before = #F.prints
    u.start(T)
    eq(#F.prints, prints_before, "a second start while active is a silent no-op")

    -- toggle -> stop: the session ends and the addon state comes back.
    u.toggle(T)
    eq(u.active, false, "toggle stops the session")
    eq(u.sim.fight_active, false, "stop ends the fight")
    eq(u.panel.shown, false, "the panel hides")
    eq(u.driver.shown, false, "the driver hides")
    near(u.result_frame.alpha, 0, "the result popup is cleared")
    eq(T.gcd.duration, 1.5, "the saved real gcd duration comes back")
    eq(T.gcd.spell_length, 1.5, "the saved spell length comes back")
    eq(T.gcd.expires, nil, "no real GCD expiry is invented")
    eq(T.mainhand.speed, 2.6, "the saved real weapon speed comes back")
    eq(T.mainhand.is_full, true, "the bar goes to its idle full look")
    eq(T.mainhand.is_paused, false, "the idle bar is not paused")
    eq(T.mainhand.current_progress, 1, "the idle bar runs full")
    near(T.mainhand.ends_at, 0, "the idle bar ends at the stop time")
    eq(F.last_inactive_hand, "mainhand", "the bar is marked inactive")
    check(F.aura_change >= 1, "the real auras take over again")
    eq(F.last_visibility_hand, "mainhand", "the real bar-visibility rule runs")
    eq(F.prints[#F.prints], "Practice mode stopped.", "stop prints the session notice")
    local stop_prints = #F.prints
    u.stop(T)
    eq(#F.prints, stop_prints, "a second stop is a silent no-op")

    -- toggle -> start again, then the X button stops the session.
    u.toggle(T)
    eq(u.active, true, "toggle starts a new session")
    eq(u.sim.fight_active, true, "the new session starts a fight")
    local close
    for i = 1, #F.frames do
        if F.frames[i].template == "UIPanelCloseButton" then
            close = F.frames[i]
        end
    end
    check(close ~= nil, "the close button exists")
    close:GetScript("OnClick")()
    eq(u.active, false, "the X button stops the session")

    -- The Start/Stop Fight button toggles fights inside the session.
    u.start(T)
    local fight_btn = u.panel.fight_btn
    eq(fight_btn.label.text, "|cFFFF0000Stop Fight|r", "an active fight labels the button Stop Fight")
    fight_btn:GetScript("OnClick")()
    eq(u.sim.fight_active, false, "the fight button stops the fight")
    eq(fight_btn.label.text, "Start Fight", "the idle label comes back")
    eq(u.panel.hint_text.text, "Press Start Fight, or cast seals with the icon grid.", "the stopped hint returns")
    fight_btn:GetScript("OnClick")()
    eq(u.sim.fight_active, true, "the fight button restarts the fight")
    eq(fight_btn.label.text, "|cFFFF0000Stop Fight|r", "the button flips back")
    u.stop(T)
end

--=========================================================================================
-- 4) Real-combat pause: the sim freezes and every shifted deadline moves by the pause
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)                  -- t = 0; the first swing lands at 2.0
    local sim = u.sim
    u.cast_key(T, "soc")        -- arms a twist for the swing that lands at resume
    eq(sim.n_active_seals, 2, "the seal swap armed a two-seal window")
    eq(sim.twist_attempted, true, "the twist is pending for the next swing")

    -- The list practice_ui promises to shift, in source order. Pinned against both the
    -- hardcoded names below and the source table itself.
    local SHIFT_FIELDS = {
        "swing_ends_at", "gcd_expires", "fading_seal_expires", "bl_buff_expires",
        "haste_pot_buff_expires", "abacus_buff_expires", "abacus_cooldown_expires",
        "dst_buff_expires", "dst_icd_expires", "cs_cooldown_expires",
        "judge_cooldown_expires", "consec_cooldown_expires", "aw_cooldown_expires",
        "aw_buff_expires", "queue_timestamp",
    }
    local src = read("practice_ui.lua")
    local shift_block = src:match("local SHIFTED_SIM_TIMES = {(.-)}")
    check(type(shift_block) == "string", "the SHIFTED_SIM_TIMES table is found in the source")
    local declared = {}
    for name in (shift_block or ""):gmatch('"([%w_]+)"') do
        declared[#declared + 1] = name
    end
    eq(#declared, #SHIFT_FIELDS, "the source list keeps all 15 shifted fields")
    for i = 1, #SHIFT_FIELDS do
        eq(declared[i], SHIFT_FIELDS[i], "SHIFTED_SIM_TIMES[" .. i .. "] is " .. SHIFT_FIELDS[i])
    end

    -- A distinguishable deadline per field: 104..116 stay future across the pause,
    -- 8.0 already passed before it, 12.0 passes during it (the swing).
    sim.swing_ends_at = 12.0
    sim.gcd_expires = 104
    sim.fading_seal_expires = 105
    sim.bl_buff_expires = 106
    sim.haste_pot_buff_expires = 107
    sim.abacus_buff_expires = 108
    sim.abacus_cooldown_expires = 109
    sim.dst_buff_expires = 110
    sim.dst_icd_expires = 111
    sim.cs_cooldown_expires = 112
    sim.judge_cooldown_expires = 8.0
    sim.consec_cooldown_expires = 113
    sim.aw_cooldown_expires = 114
    sim.aw_buff_expires = 115
    sim.queue_timestamp = 116

    -- Enter real combat at 10.0: the driver pauses and the panel says so.
    T.in_combat = true
    F.clock = 10.0
    drive(b)
    eq(u.combat_paused, true, "the first in-combat compute pauses the sim")
    near(u.combat_pause_start, 10.0, "the pause start is the tick time")
    eq(u.panel.hint_text.text, "Paused: in combat. Practice resumes when combat ends.", "the paused hint shows")

    -- Still in combat at 14.0: the swing deadline (12.0) passed, nothing may run.
    local frozen_swing = sim.swing_ends_at
    F.clock = 14.0
    drive(b)
    eq(u.combat_paused, true, "the sim stays paused while combat runs")
    near(u.combat_pause_start, 10.0, "the pause start is not restarted")
    eq(sim.swing_ends_at, frozen_swing, "the swing does not land while paused")
    eq(sim.swing_ends_at, 12.0, "the swing deadline is untouched by the pause")
    eq(sim.gcd_expires, 104, "the cast window is untouched while paused")
    eq(sim.cs_cooldown_expires, 112, "the tracked cooldown is untouched while paused")
    eq(sim.n_active_seals, 2, "the seal window is frozen")
    eq(sim.twist_attempted, true, "no grading ran while paused")
    eq(u.result_remaining, 0, "no result popup while paused")

    -- Leave combat at 15.0: resume shifts every still-future deadline by the 5.0 s pause.
    local before = {}
    for i = 1, #SHIFT_FIELDS do
        before[SHIFT_FIELDS[i]] = sim[SHIFT_FIELDS[i]]
    end
    T.in_combat = false
    F.clock = 15.0
    drive(b)
    eq(u.combat_paused, false, "leaving combat resumes the sim")
    eq(u.panel.hint_text.text, "Click an icon to cast. /st practice or the X button stops.", "the paused hint clears")
    -- swing_ends_at passes during the pause (it lands at resume, then restarts) and
    -- fading_seal_expires is consumed by the resumed twist grading; both are pinned by
    -- their own assertions below and in the second cycle. judge_cooldown_expires is the
    -- pre-pause negative control.
    local SPECIAL = { swing_ends_at = true, fading_seal_expires = true, judge_cooldown_expires = true }
    for i = 1, #SHIFT_FIELDS do
        local field = SHIFT_FIELDS[i]
        if not SPECIAL[field] then
            eq(sim[field], before[field] + 5.0, field .. " shifted by the pause length")
        end
    end
    eq(sim.judge_cooldown_expires, 8.0, "a deadline that passed before the pause stays expired")
    eq(sim.fading_seal_expires, 0, "the resumed twist grading consumed the fading seal window")
    near(sim.swing_ends_at, 17.0, "the swing that passed during the pause lands on resume, then restarts")
    eq(sim.swing_active, true, "the next swing is in flight")
    eq(sim.n_active_seals, 1, "the resumed grading consumed the older seal")
    eq(sim.seal_1_label, "command", "the newer seal stays")
    eq(sim.twist_attempted, false, "the resumed grading cleared the twist attempt")
    eq(u.result_frame.text.text, "TWIST!", "the resumed swing grades through the driver's on_swing path")
    near(u.result_remaining, 0.8, "the popup runs its configured duration")
    near(T.mainhand.ends_at, 17.0, "the restarted swing mirrors onto the bar")

    -- A second pause cycle pins fading_seal_expires on its own: with no swing in flight
    -- nothing lands after the resume, so nothing can consume the shifted window.
    local b2 = build()
    local u2, T2, F2 = b2.st.practice_ui, b2.ST, b2.sb
    u2.init(T2)
    u2.start(T2)
    u2.sim.swing_active = false
    u2.sim.fading_seal_label = "blood"
    u2.sim.fading_seal_expires = 500
    T2.in_combat = true
    F2.clock = 10.0
    drive(b2)
    eq(u2.combat_paused, true, "the second cycle pauses")
    T2.in_combat = false
    F2.clock = 15.0
    drive(b2)
    eq(u2.combat_paused, false, "the second cycle resumes")
    eq(u2.sim.fading_seal_expires, 505, "fading_seal_expires shifts by the pause length")
end

--=========================================================================================
-- 5) Driver tick: swing grading, swing restart, mainhand mirror, result popup
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    F.class_db.practice_result_duration = 1.25
    F.class_db.practice_result_text_size = 36
    F.class_db.practice_result_color_hit = { 0.2, 0.9, 0.1, 0.8 }
    F.class_db.practice_result_color_miss = { 0.9, 0.1, 0.2, 0.8 }
    u.init(T)
    F.clock = 100.0
    u.start(T)
    eq(u.result_frame.text.font[1], "Fonts\\LSM.ttf", "start applies the media font")
    eq(u.result_frame.text.font[2], 36, "start applies the configured result font size")
    eq(F.font_requests[#F.font_requests].key, "Expressway", "the hand's text_font key is fetched")

    -- A twist armed inside the 0.4 s fade window grades TWIST! when the swing lands.
    F.clock = 101.9
    u.cast_key(T, "soc")
    eq(u.sim.fading_seal_label, "blood", "the older seal starts fading")
    F.clock = 102.01
    drive(b, 0.01)
    eq(u.result_frame.text.text, "TWIST!", "the graded swing shows TWIST!")
    eq(u.result_frame.text.color[1], 0.2, "the hit colour is the configured one (r)")
    eq(u.result_frame.text.color[4], 0.8, "the hit colour is the configured one (a)")
    eq(u.result_frame.alpha, 1, "a fresh popup is fully opaque")
    eq(u.result_duration, 1.25, "the configured popup duration is read")
    near(u.result_remaining, 1.25, "the popup timer starts at the configured duration")
    eq(u.sim.swing_active, true, "the landed swing restarts the next swing")
    near(u.sim.swing_ends_at, 104.01, "the restarted swing ends one effective speed later")
    near(T.mainhand.ends_at, 104.01, "the simulated swing end mirrors onto the bar")
    near(T.mainhand.start, 102.01, "the mirrored start is end minus speed")
    near(T.mainhand.speed, 2.0, "the simulated speed mirrors onto the bar")
    eq(T.mainhand.is_paused, false, "the restarted swing is not paused")
    eq(u.sim.n_active_seals, 1, "the successful twist consumed the older seal")
    eq(u.sim.seal_1_label, "command", "the newer seal stays")

    -- A twist whose fade window closed before the swing grades MISS.
    F.clock = 103.1
    u.cast_key(T, "sob")
    eq(u.sim.twist_attempted, true, "the second swap arms a twist too")
    F.clock = 104.02
    drive(b, 0.01)
    eq(u.result_frame.text.text, "MISS", "a fade-window miss grades MISS")
    eq(u.result_frame.text.color[1], 0.9, "the miss colour is the configured one (r)")
    eq(u.result_frame.text.color[4], 0.8, "the miss colour is the configured one (a)")
    near(u.sim.swing_ends_at, 106.02, "the missed swing lands and restarts")
    near(T.mainhand.ends_at, 106.02, "the miss also mirrors the restarted swing")
    eq(u.sim.n_active_seals, 1, "the fade left a single seal for the miss")
    eq(u.sim.seal_1_label, "blood", "the surviving seal is the newer one")

    -- The driver tick fades the popup (same elapsed the frame loop supplies).
    drive(b, 1.3)
    eq(u.result_frame.alpha, 0, "the driver tick fades the popup to alpha 0")
    eq(u.result_remaining, 0, "the faded popup timer lands on zero")
end

--=========================================================================================
-- 6) sync_to_addon: the gcd mirror reports a length change exactly once
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.gcd.phys_length = true
    u.init(T)
    u.start(T)
    eq(F.gcd_changes, 1, "start's first mirror reports nil -> 1.154 once")
    eq(F.gcd_times, 1, "set_gcd_times_before_swing_seconds runs with phys_length present")
    F.clock = 0.1
    drive(b)
    eq(F.gcd_changes, 1, "an unchanged gcd reports nothing")
    eq(F.gcd_times, 1, "an unchanged gcd does not rebuilt the gcd times")

    -- A real gcd-length change reports exactly once, then goes quiet again.
    u.sim.effective_gcd = 1.3
    F.clock = 0.2
    drive(b)
    eq(F.gcd_changes, 2, "a changed gcd reports once")
    eq(T.gcd.duration, 1.3, "the changed duration mirrors")
    eq(T.gcd.spell_length, 1.3, "the changed spell length mirrors")
    F.clock = 0.3
    drive(b)
    eq(F.gcd_changes, 2, "the new gcd does not report again")
    eq(F.gcd_times, 2, "the gcd times rebuild with the change")

    -- Without phys_length only the change callback runs.
    T.gcd.phys_length = nil
    u.sim.effective_gcd = 1.4
    F.clock = 0.4
    drive(b)
    eq(F.gcd_changes, 3, "changing the gcd again reports once")
    eq(F.gcd_times, 2, "no phys_length -> no gcd-times rebuild")

    -- The active gcd window mirrors its expiry; an inactive gcd mirrors nil.
    u.sim.gcd_active = true
    u.sim.gcd_expires = 25.0
    u.sync_to_addon(T)
    eq(T.gcd.expires, 25.0, "an active simulated gcd mirrors its expiry")
    u.sim.gcd_active = false
    u.sync_to_addon(T)
    eq(T.gcd.expires, nil, "an inactive simulated gcd clears the expiry")

    -- Mainhand mirror: a simulated attack pause pauses the bar.
    u.sim.attack_paused = true
    u.sync_to_addon(T)
    eq(T.mainhand.is_paused, true, "a simulated attack pause pauses the mirrored bar")
    u.sim.attack_paused = false
    u.combat_paused = true
    u.sync_to_addon(T)
    eq(T.mainhand.is_paused, true, "the real-combat pause also pauses the mirrored bar")
    u.combat_paused = false

    -- No swing in flight: the bar holds an empty, unpaused full-speed span.
    u.sim.swing_active = false
    F.clock = 1.0
    u.sync_to_addon(T)
    near(T.mainhand.start, 1.0, "no swing -> the bar holds at now")
    near(T.mainhand.ends_at, 3.0, "no swing -> now + effective speed")
    eq(T.mainhand.current_progress, 0, "no swing -> progress 0")
    eq(T.mainhand.is_full, false, "no swing -> not the idle-full state")
end

--=========================================================================================
-- 7) cast_key: the pause guard and the flag routing into the bridge
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)
    local sim = u.sim

    -- While the real-combat pause is armed the grid is silent.
    T.in_combat = true
    local sync_before = F.practice_sync
    u.cast_key(T, "soc")
    eq(sim.n_active_seals, 1, "cast_key changes nothing while in combat")
    eq(sim.cs_cooldown_expires, 0, "no cooldown is started while in combat")
    eq(F.practice_sync, sync_before, "no bridge sync runs while in combat")
    T.in_combat = false

    -- cs: a gcd_started cast mirrors the gcd window.
    local sync0 = F.practice_sync
    F.clock = 0.5
    u.cast_key(T, "cs")
    near(sim.cs_cooldown_expires, 6.5, "cs starts its 6 s cooldown")
    eq(sim.gcd_active, true, "cs starts the simulated gcd")
    near(sim.gcd_expires, 1.654, "the gcd window uses the effective gcd")
    near(T.gcd.expires, 1.654, "gcd_started mirrors the expiry")
    near(T.gcd.spell_length, 1.154, "the gcd length mirrors")
    eq(F.practice_sync, sync0 + 1, "the cast runs one bridge sync")
    local cs_icon = u.panel.ability_icons.cs
    eq(swipe_activations(cs_icon.cooldown.cooldown_calls, 6), 1, "the cs swipe is set once")

    -- judge: seal_changed without a gcd; the seal is consumed for the judged_seal flag.
    sync0 = F.practice_sync
    u.cast_key(T, "judge")
    eq(sim.n_active_seals, 0, "judgement consumes the seal")
    near(sim.judge_cooldown_expires, 8.5, "judgement starts its 8 s cooldown")
    near(sim.gcd_expires, 1.654, "judgement does not restart the gcd")
    eq(F.practice_sync, sync0 + 1, "seal_changed folds into the same sync")
    eq(swipe_activations(u.panel.ability_icons.judge.cooldown.cooldown_calls, 8), 1,
        "the judge swipe is set once")

    -- A seal cast after the gcd expired applies and re-arms the twist machinery.
    sync0 = F.practice_sync
    F.clock = 1.7
    u.cast_key(T, "soc")
    eq(sim.n_active_seals, 1, "the seal applies")
    eq(sim.seal_1_label, "command", "the command seal is tracked")
    eq(sim.twist_attempted, false, "a first seal is not a twist attempt")
    near(sim.gcd_expires, 2.854, "the seal cast restarts the gcd")
    eq(F.practice_sync, sync0 + 1, "the seal cast syncs once")

    -- stop: the simulated attack pauses and the mirror reports it.
    F.clock = 3.0
    u.cast_key(T, "stop")
    check(sim.attack_paused or sim.attack_pause_pending, "stop arms the simulated attack pause")
    eq(T.mainhand.is_paused, true, "the mirrored bar reports the pause")

    -- A resume ability releases the pause and starts a fresh swing.
    F.clock = 3.2
    sim.cs_cooldown_expires = 0
    u.cast_key(T, "cs")
    eq(sim.attack_paused, false, "cs resumes the simulated attack")
    eq(sim.attack_pause_pending, false, "the pending pause flag clears")
    near(sim.swing_ends_at, 5.2, "the resumed swing starts at the current effective speed")

    -- The icon wiring: left-click casts; right-click starts key capture.
    F.clock = 4.0
    sim.gcd_active = false
    sim.cs_cooldown_expires = 0
    sync0 = F.practice_sync
    local icon = u.panel.ability_icons.cs
    icon:GetScript("OnMouseDown")(icon, "RightButton")
    eq(sim.cs_cooldown_expires, 0, "a right-click does not cast")
    eq(F.practice_sync, sync0, "a right-click does not sync")
    eq(u.key_capture_ability, "cs", "a right-click starts key capture for the icon")
    eq(u.key_capture_frame.shown, true, "the capture overlay shows")
    check(u.key_capture_frame.prompt.text:find("Crusader Strike") ~= nil,
        "the capture prompt names the ability")
    u.cancel_key_capture(T)
    eq(u.key_capture_ability, nil, "the capture can be cancelled")
    eq(u.key_capture_frame.shown, false, "cancelling hides the overlay")
    icon:GetScript("OnMouseDown")(icon, "LeftButton")
    near(sim.cs_cooldown_expires, 10.0, "a left-click casts through cast_key (4.0 + 6)")
    eq(F.practice_sync, sync0 + 1, "the left-click syncs once")
end

--=========================================================================================
-- 8) Result popup: configured text/colour/duration, font fallback, linear fade
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)

    -- The configured font size and the hand's media font flow through LSM.
    F.lsm_font = "Fonts\\Custom.ttf"
    F.class_db.practice_result_text_size = 30
    F.hand_db.text_font = "MyFont"
    u.update_result_font(T)
    eq(F.font_requests[#F.font_requests].mediatype, "font", "the media type is the font category")
    eq(F.font_requests[#F.font_requests].key, "MyFont", "the hand's text_font key is fetched")
    eq(u.result_frame.text.font[1], "Fonts\\Custom.ttf", "the fetched font is applied")
    eq(u.result_frame.text.font[2], 30, "the configured size is applied")
    eq(u.result_frame.text.font[3], "OUTLINE", "the result text keeps its outline")
    F.lsm_font = nil
    u.update_result_font(T)
    eq(u.result_frame.text.font[1], "Fonts\\FRIZQT__.TTF", "a missing media font falls back")
    F.lsm_font = "Fonts\\Custom.ttf"
    F.hand_db.text_font = nil
    u.update_result_font(T)
    eq(F.font_requests[#F.font_requests].key, "Expressway", "no hand font -> the Expressway default is fetched")

    -- show_result reads the configured keys at show time.
    F.class_db.practice_result_duration = 1.0
    F.class_db.practice_result_color_hit = { 0.1, 0.2, 0.3, 0.4 }
    u.show_result(T, "TWIST!")
    eq(u.result_frame.text.text, "TWIST!", "the popup shows the feedback text")
    eq(u.result_frame.text.color[1], 0.1, "the configured hit colour applies (r)")
    eq(u.result_frame.text.color[4], 0.4, "the configured hit colour applies (a)")
    eq(u.result_duration, 1.0, "the configured duration is read")
    eq(u.result_remaining, 1.0, "the popup timer starts at the configured duration")
    eq(u.result_frame.alpha, 1, "the popup shows fully opaque")
    F.class_db.practice_result_duration = 2.0
    u.show_result(T, "TWIST!")
    eq(u.result_remaining, 2.0, "a changed duration is read at the next show")

    -- The fade: full alpha above the final 0.3 s, then linear to 0.
    u.update_result_fade(1.5)
    eq(u.result_frame.alpha, 1, "above the fade window the popup holds full alpha")
    u.update_result_fade(0.25)
    check(math.abs(u.result_frame.alpha - (0.25 / 0.3)) < 1e-9, "the fade is linear over the final 0.3 s")
    u.update_result_fade(0.25)
    eq(u.result_frame.alpha, 0, "the popup reaches alpha 0 at the end of the duration")
    eq(u.result_remaining, 0, "the faded timer lands on zero")
    u.update_result_fade(1.0)
    eq(u.result_frame.alpha, 0, "fading an expired popup is a no-op")

    -- Defaults: the shipped colours and duration apply when the config is absent.
    F.class_db.practice_result_duration = nil
    F.class_db.practice_result_color_hit = nil
    u.show_result(T, "TWIST!")
    eq(u.result_frame.text.color[2], 1, "the default hit colour applies without config")
    eq(u.result_duration, 0.8, "the default popup duration is 0.8")
    F.class_db.practice_result_color_miss = nil
    u.show_result(T, "MISS")
    eq(u.result_frame.text.color[1], 1, "the default miss colour applies without config")
    near(u.result_frame.text.color[2], 0.2, "the default miss colour carries its red-green mix")
end

--=========================================================================================
-- 9) Set-once swipes: one SetCooldown per activation, re-set on a restart, cleared once
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)
    local sim = u.sim
    F.clock = 0.5
    u.cast_key(T, "cs")
    local icon = u.panel.ability_icons.cs
    local calls = icon.cooldown.cooldown_calls
    eq(swipe_activations(calls, 6), 1, "the cs swipe is set once per activation")

    -- Ticks while the cooldown drains never re-set the swipe.
    F.clock = 0.56
    drive(b)
    F.clock = 1.0
    drive(b)
    F.clock = 2.0
    drive(b)
    eq(swipe_activations(calls, 6), 1, "ticks do not re-set the same swipe")
    eq(#calls, 1, "the running cooldown records nothing else")

    -- A restart without an observed gap jumps the remaining time; the swipe re-sets once.
    F.clock = 3.0
    sim.cs_cooldown_expires = 9.0
    drive(b)
    eq(swipe_activations(calls, 6), 2, "a restarted cooldown re-sets the swipe")
    eq(calls[2].duration, 6, "the re-set swipe carries the full duration")
    near(calls[2].start, 3.0, "the re-set swipe derives its start from remaining/duration")
    F.clock = 3.5
    drive(b)
    F.clock = 4.0
    drive(b)
    eq(swipe_activations(calls, 6), 2, "after the restart the swipe is set once, not per tick")

    -- Expiry clears the swipe exactly once, and idle ticks do not re-clear it.
    sim.cs_cooldown_expires = 0
    F.clock = 4.06
    drive(b)
    eq(swipe_clears(calls), 1, "the expired cooldown clears the swipe exactly once")
    eq(#calls, 3, "the clear is the only additional call")
    F.clock = 4.12
    drive(b)
    F.clock = 4.18
    drive(b)
    eq(#calls, 3, "an idle cooldown does not re-clear the swipe")

    -- The gcd swipe follows the same latch on the icon's second bar.
    local gcd_calls = icon.gcd_cooldown.cooldown_calls
    eq(swipe_activations(gcd_calls, 1.154), 1, "the gcd swipe is set once for the cast")
    eq(swipe_clears(gcd_calls), 1, "the gcd swipe clears once at expiry")

    -- A fresh cast after expiry sets the swipe again.
    F.clock = 4.2
    u.cast_key(T, "cs")
    eq(swipe_activations(calls, 6), 3, "a fresh activation after expiry sets the swipe again")
    eq(swipe_activations(gcd_calls, 1.154), 2, "the new cast restarts the gcd swipe")
end

--=========================================================================================
-- 10) Pre-init safety: every hook is inert before the frames exist
-- (start/toggle are excluded by design: start lazily builds the panel when it
-- is missing out of combat - see section 10b - and toggle delegates to start)
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.interfaces_are_initialised = false
    local HOOKS = {
        { "tick", { 0.1 } },
        { "stop", {} },
        { "toggle_fight", {} },
        { "start_fight", {} },
        { "stop_fight", {} },
        { "cast_key", { "cs" } },
        { "refresh_icons", {} },
        { "sync_to_addon", {} },
        { "update_info", {} },
        { "update_button", {} },
        { "update_hint", {} },
        { "show_result", { "TWIST!" } },
        { "update_result_font", {} },
        { "apply_settings", {} },
        { "save_position", {} },
        { "build_bar_mappings", {} },
        { "build_key_buttons", {} },
        { "rebind_keys", {} },
        { "update_keybind_labels", {} },
        { "start_key_capture", { "cs" } },
        { "finish_key_capture", { "F" } },
        { "cancel_key_capture", {} },
        { "reset_keybinds", {} },
        { "click_haste", { "bl" } },
        { "update_haste_buttons", {} },
        { "set_haste_buttons_enabled", { true } },
        { "set_locked_rotation", { "2/3" } },
        { "build_rotation_display", {} },
        { "save_rotation_position", {} },
        { "update_rotation_display", {} },
        { "build_timeline", {} },
        { "render_timeline", {} },
        { "reset_timeline_pools", {} },
        { "toggle_timeline", {} },
        { "update_timeline_button", {} },
        { "build_proc_icons", {} },
        { "update_proc_icons", {} },
        { "attach_overlay", { "cs", nil } },
        { "detach_overlay", { "cs" } },
        { "detach_all_overlays", {} },
        { "flash_overlay", { "cs" } },
        { "update_overlays", { 0 } },
        { "update_fight_timer", { 0 } },
        { "save_timeline_position", {} },
        { "load_bests", {} },
        { "maybe_save_bests", {} },
        { "update_score", {} },
    }
    for i = 1, #HOOKS do
        local fn = u[HOOKS[i][1]]
        for pass = 1, 2 do
            local ok, err = pcall(fn, T, unpack(HOOKS[i][2]))
            check(ok, "pre-init " .. HOOKS[i][1] .. " (pass " .. pass .. ") does not error ("
                .. tostring(err) .. ")")
        end
    end
    local ok1, err1 = pcall(u.update_result_fade, 0.1)
    check(ok1, "pre-init update_result_fade does not error (" .. tostring(err1) .. ")")
    local ok2, err2 = pcall(u.shift_sim_times, nil, 5)
    check(ok2, "shift_sim_times with no sim does not error (" .. tostring(err2) .. ")")
    local ok3, err3 = pcall(u.shift_sim_times, {}, nil)
    check(ok3, "shift_sim_times with no shift does not error (" .. tostring(err3) .. ")")
    eq(u.is_active(), false, "is_active is false before init")
    eq(u.active, nil, "no pre-init hook activated the session")
    eq(u.panel, nil, "no pre-init hook created the panel")
    eq(u.sim, nil, "no pre-init hook created the sim")
    eq(u.result_frame, nil, "no pre-init hook created the result frame")
    eq(F.created_frames, 0, "no pre-init hook created any frame")
    eq(T.mainhand.speed, 2.6, "no pre-init hook touched the addon state")
end

--=========================================================================================
-- 10b) Start blocks: every no-start path speaks once + counts in the diag
-- (practice:start), never dies silent. Lazy init heals the combat-defer race.
--=========================================================================================
do
    -- A toggle before init builds the panel out of combat and starts (the
    -- reload-mid-fight retry window no longer fails closed on a transient).
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    local ok, err = pcall(u.start, T)
    check(ok, "pre-init start does not error (" .. tostring(err) .. ")")
    eq(u.panel ~= nil, true, "lazy init builds the panel on a panel-less start")
    eq(u.active, true, "lazy init starts the session")
    eq(F.prints[#F.prints], "Practice mode started. Type /st practice to stop.",
        "lazy init prints the session notice")
    u.stop(T)

    -- A toggle before init while in combat refuses with the combat reason and
    -- builds nothing (the deferred retry still owns the build).
    local c = build()
    local cu, cT, cF = c.st.practice_ui, c.ST, c.sb
    cT.in_combat = true
    local okc, errc = pcall(cu.start, cT)
    check(okc, "pre-init start in combat does not error (" .. tostring(errc) .. ")")
    eq(cu.active, nil, "combat still refuses the session")
    eq(cu.panel, nil, "combat creates no panel")
    eq(cF.created_frames, 0, "combat creates no frame")
    eq(cF.prints[#cF.prints], "Practice mode cannot be started in combat.",
        "combat prints the combat reason")
    eq(cT.bar_hook_errors.by_site["practice:start"], 1, "the combat refusal counts in the diag")

    -- A missing engine keeps the legacy message (genuinely unavailable).
    local n = build({ no_practice = true })
    local nu, nT, nF = n.st.practice_ui, n.ST, n.sb
    nu.start(nT)
    eq(nF.prints[#nF.prints], "Practice mode is not available.",
        "without the engine start keeps the legacy message")
    eq(nT.bar_hook_errors.by_site["practice:start"], 1, "the no-engine refusal counts in the diag")

    -- A drill whose shell rejects the session speaks per-drill (shaman shown;
    -- hunter/rogue/druid ride the identical branch shape).
    local s = build()
    local su, sT, sF = s.st.practice_ui, s.ST, s.sb
    sT.player_class = "SHAMAN"
sT.active_class = "SHAMAN"
    sT.SHAMAN = {
        practice_scenario_key = function() return "shaman_weave" end,
        PRACTICE_CAST_ORDER = { "weave_lb" },
        practice_cast_label = function() return "Lightning Bolt" end,
        practice_cast_spell_id = function() return 1001 end,
        practice_cast_seconds = function() return 1.5 end,
        practice_latency_seconds = function() return 0 end,
        new_practice_session = function(now, opts) return nil end,
        tick_practice_session = function(session, now, elapsed, out) return out or {} end,
        practice_cast = function(session, swing, now, key) return nil end,
        practice_status = function() return "Marker: --" end,
        practice_fight_elapsed = function() return 0 end,
        end_practice_session = function() return false end,
        practice_sync = function() return 0 end,
    }
    sT.SHAMAN.practice_panel = fixture_panel(s, sT, "SHAMAN")
    su.init(sT)
    local oks, errs = pcall(su.start, sT)
    check(oks, "rejected shaman drill does not error (" .. tostring(errs) .. ")")
    check(su.active ~= true, "rejected shaman drill starts no session")
    eq(sF.prints[#sF.prints], "Practice drill is not available (session rejected).",
        "rejected shaman drill prints its own reason")
    eq(sT.bar_hook_errors.by_site["practice:start"], 1, "the rejection counts in the diag")

    -- A half-loaded shell (tick entry missing) fails the start closed instead
    -- of running a session whose ticks never advance.
    sT.SHAMAN.tick_practice_session = nil
    su.start(sT)
    check(su.active ~= true, "half-loaded shaman shell starts no session")
    eq(sF.prints[#sF.prints], "Practice drill is not available (session rejected).",
        "half-loaded shaman shell prints the rejection")
    sT.SHAMAN.tick_practice_session = function(session, now, elapsed, out) return out or {} end

    -- A throwing shell accessor fails the route closed (drift message, no throw).
    sT.SHAMAN.practice_scenario_key = function() error("shell probe") end
    local okt, errt = pcall(su.start, sT)
    check(okt, "throwing shaman accessor does not error out of start (" .. tostring(errt) .. ")")
    check(su.active ~= true, "throwing accessor starts no session")
    eq(sF.prints[#sF.prints], "Practice mode is not available (shaman drill key drifted).",
        "throwing accessor prints the drift reason")
    sT.SHAMAN.practice_scenario_key = function() return "shaman_weave" end

    -- A throwing begin fails the run closed with the session cleaned up.
    sT.SHAMAN.new_practice_session = function(now, opts) error("begin probe") end
    local okb, errb = pcall(su.start, sT)
    check(okb, "throwing shaman begin does not error out of start (" .. tostring(errb) .. ")")
    check(su.active ~= true, "throwing begin leaves no active session")
    eq(su.shaman_session, nil, "throwing begin leaves no drill session")
    eq(sF.prints[#sF.prints], "Practice drill is not available (session rejected).",
        "throwing begin prints the rejection")
end

--=========================================================================================
-- 10c) Cross-class sweep: a shaman session never calls through another class's
-- module, and nil profile/bar reads degrade instead of throwing.
--=========================================================================================
do
    -- Nil class profile: the paladin path still starts on shipped defaults.
    local b = build()
    local u, T = b.st.practice_ui, b.ST
    u.init(T)
    T.get_class_table = function() return nil end
    local ok, err = pcall(u.start, T)
    check(ok, "start with a nil class profile does not error (" .. tostring(err) .. ")")
    eq(u.active, true, "nil profile still starts the session")
    eq(u.base_speed, 2.6, "nil profile falls back to the equipped speed")
    u.stop(T)
    eq(u.active, false, "the session stops with a nil profile")

    -- Missing readout entries read idle instead of throwing the tick.
    local s = build()
    local su, sT, sF = s.st.practice_ui, s.ST, s.sb
    sT.player_class = "SHAMAN"
sT.active_class = "SHAMAN"
    sT.SHAMAN = {
        practice_scenario_key = function() return "shaman_weave" end,
        PRACTICE_CAST_ORDER = { "weave_lb" },
        practice_cast_label = function() return "Lightning Bolt" end,
        practice_cast_spell_id = function() return 1001 end,
        practice_cast_seconds = function() return 1.5 end,
        practice_latency_seconds = function() return 0 end,
        new_practice_session = function(now, opts) return { active = true } end,
        tick_practice_session = function(session, now, elapsed, out) return out or {} end,
        practice_cast = function(session, swing, now, key) return nil end,
        practice_fight_elapsed = function() return 0 end,
        end_practice_session = function(session, now) session.active = false end,
        practice_sync = function() return 0 end,
    }
    sT.SHAMAN.practice_panel = fixture_panel(s, sT, "SHAMAN")
    su.init(sT)
    su.start(sT)
    eq(su.active, true, "shaman drill starts without the readout entries")
    sT.SHAMAN.practice_status = nil
    sT.SHAMAN.practice_fight_elapsed = nil
    sF.clock = 1.0
    local okt, errt = pcall(drive, s, 0.1)
    check(okt, "missing readout entries do not error the tick (" .. tostring(errt) .. ")")
    eq(su.panel.info_text.text, "Drill idle - press Start Fight", "missing status reads idle")
    su.stop(sT)

    -- Missing teardown entry still stops (fail-loud + cleaned up).
    su.start(sT)
    sT.SHAMAN.end_practice_session = nil
    local prints_before = #sF.prints
    local oko, erro = pcall(su.stop, sT)
    check(oko, "missing teardown entry does not error stop (" .. tostring(erro) .. ")")
    eq(su.active, false, "stop ends the session without the shell")
    eq(su.shaman_session, nil, "stop clears the drill session without the shell")
    -- The class's provider owns the teardown now (class-isolation 2026-10-21):
    -- a missing class entry is the provider's business, never a shared notice.
    local shared_notice = false
    for i = prints_before + 1, #sF.prints do
        if sF.prints[i] == "Practice drill session end skipped (shell missing)." then
            shared_notice = true
        end
    end
    eq(shared_notice, false, "the provider owns teardown (no shared-layer shell notice)")
    eq(sF.prints[#sF.prints], "Practice mode stopped.", "stop still prints the session notice")

    -- A missing class re-begin entry is the provider's business: the shared
    -- begin seam exists, so the shared layer neither throws nor invents a notice.
    sT.SHAMAN.end_practice_session = function(session, now) session.active = false end
    su.start(sT)
    sT.SHAMAN.practice_begin_session = nil
    su.stop_fight(sT)
    local okf, errf = pcall(su.start_fight, sT)
    check(okf, "missing re-begin entry does not error start_fight (" .. tostring(errf) .. ")")
    eq(sF.prints[#sF.prints], "Practice mode started. Type /st practice to stop.",
        "missing re-begin entry is a silent no-op (the provider owns the seam)")
    su.stop(sT)
end

--=========================================================================================
-- 10d) Per-class fidelity: each drill mirrors the shell it grades (order and
-- real timings proven at the panel), and the warrior routing stays the
-- documented shared session.
--=========================================================================================
do
    -- Paladin: the panel binds the engine order key-for-key, in sequence.
    local b = build()
    local u, T = b.st.practice_ui, b.ST
    local pr = b.st.practice
    u.init(T)
    local seen = {}
    for i = 1, #pr.ABILITY_ORDER do
        local key = pr.ABILITY_ORDER[i]
        check(u.panel.ability_icons[key] ~= nil, "paladin: the panel binds " .. key)
        seen[#seen + 1] = key
    end
    eq(#seen, count_keys(u.panel.ability_icons), "paladin: the panel binds exactly the engine order")
    u.start(T)
    eq(u.base_speed, 2.6, "paladin: the session runs the equipped speed")
    u.stop(T)

    -- Hunter: the panel binds the shell shot order in sequence.
    local h = build()
    local hu, hT = h.st.practice_ui, h.ST
    hT.player_class = "HUNTER"
hT.active_class = "HUNTER"
    local horder = { "steady", "multi", "aimed" }
    hT.HUNTER = {
        get_practice_scenario_key = function() return "hunter_forced_move" end,
        PRACTICE_SHOT_ORDER = horder,
        practice_shot_label = function(key) return key end,
        practice_shot_spell_id = function(key) return 1001 end,
        practice_new_session = function(now, opts) return { active = false } end,
        practice_begin_session = function(session, now) session.active = true return true end,
        practice_tick = function(session, now, elapsed, out) return out or {} end,
        practice_cast = function(session, now, key) return "A" end,
        practice_status = function() return "Windows clear - cast freely" end,
        practice_fight_elapsed = function() return 0 end,
        practice_end_session = function(session, now) session.active = false end,
    }
    hT.HUNTER.practice_panel = fixture_panel(h, hT, "HUNTER")
    hu.init(hT)
    for i = 1, #horder do
        check(hu.panel.ability_icons[horder[i]] ~= nil,
            "hunter: the panel binds " .. horder[i] .. " in shell order")
    end
    eq(count_keys(hu.panel.ability_icons), #horder, "hunter: the panel binds exactly the shell order")
    hu.start(hT)
    eq(hu.active, true, "hunter: the drill session starts")
    hu.stop(hT)

    -- Shaman: the panel binds the shell cast order and the drill swing mirrors
    -- the equipped weapon speed (the real beat the drill grades).
    local s = build()
    local su, sT, sF = s.st.practice_ui, s.ST, s.sb
    sT.player_class = "SHAMAN"
sT.active_class = "SHAMAN"
    sT.SHAMAN = {
        practice_scenario_key = function() return "shaman_weave" end,
        PRACTICE_CAST_ORDER = { "weave_lb", "weave_cl" },
        practice_cast_label = function(key) return key end,
        practice_cast_spell_id = function(key) return 1001 end,
        practice_cast_seconds = function(key) return 1.5 end,
        practice_latency_seconds = function() return 0 end,
        new_practice_session = function(now, opts) return { active = true } end,
        tick_practice_session = function(session, now, elapsed, out) return out or {} end,
        practice_cast = function(session, swing, now, key) return nil end,
        practice_begin_session = function(session, now, opts) session.active = true return true end,
        practice_status = function() return "Marker: --" end,
        practice_fight_elapsed = function() return 0 end,
        end_practice_session = function(session, now) session.active = false end,
        practice_sync = function() return 0 end,
    }
    sT.SHAMAN.practice_panel = fixture_panel(s, sT, "SHAMAN")
    su.init(sT)
    check(su.panel.ability_icons.weave_lb ~= nil, "shaman: the panel binds weave_lb")
    check(su.panel.ability_icons.weave_cl ~= nil, "shaman: the panel binds weave_cl")
    su.start(sT)
    eq(su.shaman_swing.swing_duration, 2.6, "shaman: the drill swing is the equipped speed")
    eq(su.base_speed, 2.6, "shaman: the session base speed is the equipped speed")
    su.stop(sT)

    -- An order key the class cannot define refuses the start instead of running
    -- a session whose icon has no cast behind it.
    sT.SHAMAN.PRACTICE_CAST_ORDER = { "weave_lb", "bogus_key" }
    sT.SHAMAN.practice_cast_label = function(key)
        if key == "weave_lb" or key == "weave_cl" then return key end
        return nil
    end
    su.start(sT)
    check(su.active ~= true, "unresolvable drill order starts no session")
    eq(sF.prints[#sF.prints], "Practice drill is not available (session rejected).",
        "unresolvable drill order prints the rejection")

    -- A weave model that cannot resolve the marker refuses the start: in-fight
    -- casts would never score, so no session runs.
    sT.SHAMAN.PRACTICE_CAST_ORDER = { "weave_lb", "weave_cl" }
    sT.SHAMAN.practice_cast_label = function(key) return key end
    local saved_weave = s.st.weave
    s.st.weave = nil
    su.start(sT)
    check(su.active ~= true, "unresolvable weave marker starts no session")
    eq(sF.prints[#sF.prints], "Practice drill is not available (session rejected).",
        "unresolvable weave marker prints the rejection")
    s.st.weave = saved_weave

    -- Rogue: the drill swing mirrors the equipped speed and the energy clock
    -- runs the real 2 s cadence.
    local r = build()
    local ru, rT = r.st.practice_ui, r.ST
    rT.player_class = "ROGUE"
rT.active_class = "ROGUE"
    rT.ROGUE = {
        practice_scenario_key = function() return "rogue_energy_pool" end,
        PRACTICE_CAST_ORDER = { "evisc" },
        practice_cast_label = function(key) return "Pool Spend" end,
        practice_cast_spell_id = function(key) return "Eviscerate" end,
        practice_cast_order = function() return { "evisc" } end,
        new_practice_session = function(now, opts) return { active = false } end,
        new_ss_session = function(now, opts) return nil end,
        practice_begin_session = function(session, now) session.active = true return true end,
        tick_practice_session = function(session, now, elapsed, out) return out or {} end,
        practice_cast = function(drill, now, key) return "S" end,
        practice_status = function() return "Pool: --" end,
        practice_fight_elapsed = function() return 0 end,
        end_practice_session = function(session, now) session.active = false end,
        practice_sync = function() return 0 end,
    }
    rT.ROGUE.practice_panel = fixture_panel(r, rT, "ROGUE")
    ru.init(rT)
    ru.start(rT)
    eq(ru.rogue_swing.swing_duration, 2.6, "rogue: the drill swing is the equipped speed")
    eq(ru.rogue_tick.interval, 2, "rogue: the energy clock runs the 2 s cadence")
    ru.stop(rT)

    -- Druid: the single-shift panel binds the drill def.
    local d = build()
    local du, dT = d.st.practice_ui, d.ST
    dT.player_class = "DRUID"
dT.active_class = "DRUID"
    dT.DRUID = {
        practice_scenario_key = function() return "druid_powershift" end,
        new_practice_session = function(now, opts) return { active = true, started_at = now } end,
        tick_practice_session = function(session, now, elapsed, out) return out or {} end,
        practice_shift = function(session, now) return "S" end,
        practice_summary = function(session) return { attempts = 0, score = 0 } end,
        end_practice_session = function(session, now) session.active = false return true end,
    }
    dT.DRUID.practice_panel = fixture_panel(d, dT, "DRUID")
    du.init(dT)
    check(du.panel.ability_icons.shift ~= nil, "druid: the panel binds the single shift cast")
    du.start(dT)
    eq(du.active, true, "druid: the powershift session starts")
    du.stop(dT)

    -- Warrior (no drills of its own in this sandbox): the twist minigame is the
    -- PALADIN's drill, never an inherited session, so a class with no practice
    -- of its own is refused LOUDLY - never a silent paladin sim.
    local w = build()
    local wu, wT, wF = w.st.practice_ui, w.ST, w.sb
    wT.player_class = "WARRIOR"
wT.active_class = "WARRIOR"
    wu.init(wT)
    wu.start(wT)
    eq(wu.active, nil, "warrior: a class with no practice of its own starts no session")
    eq(wF.prints[#wF.prints], "No practice for this class.",
        "warrior: the refusal is loud and names the reason")
    eq(count_keys(wu.panel.ability_icons or {}), 0,
        "warrior: the panel carries no twist sim icon grid")
    wu.stop(wT)
end

--=========================================================================================
-- 11) Option gates: weapon speed, result keys, panel offsets and the drag round-trip
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    F.class_db.practice_weapon_speed = 1.6
    u.init(T)
    u.start(T)
    eq(u.base_speed, 1.6, "practice_weapon_speed overrides the equipped speed")
    near(u.sim.effective_speed, 1.231, "1.6/1.3 with the immediate Bloodlust")
    near(u.sim.swing_ends_at, 1.231, "the first swing is clamped to the hasted speed")
    u.stop(T)

    -- 0 (the shipped default) uses the equipped weapon speed.
    F.class_db.practice_weapon_speed = 0
    u.start(T)
    eq(u.base_speed, 2.6, "weapon speed option 0 reads the equipped weapon")
    near(u.sim.effective_speed, 2.0, "2.6/1.3 -> 2.0")
    u.stop(T)

    -- No usable equipment reading falls back to the engine's 3.5 s.
    F.attack_speed = 0
    u.start(T)
    eq(u.base_speed, 3.5, "an unusable weapon speed falls back to 3.5")
    near(u.sim.effective_speed, 2.692, "3.5/1.3 -> 2.692")
    u.stop(T)

    -- A changed result duration is read at show time.
    F.class_db.practice_result_duration = 2.5
    u.show_result(T, "MISS")
    eq(u.result_remaining, 2.5, "a changed result duration is read at show time")

    -- The panel offsets add to the archive's 8 px gap.
    F.class_db.practice_panel_x = 12
    F.class_db.practice_panel_y = -4
    u.apply_settings(T)
    eq(u.panel.point[4], 20, "practice_panel_x adds to the 8 px gap")
    eq(u.panel.point[5], -4, "practice_panel_y is the vertical offset")

    -- A deferred option apply waits for the driver tick while lockdown is up.
    u.start(T)
    F.class_db.practice_panel_x = 5
    F.lockdown = true
    u.apply_settings(T)
    eq(u.pending_apply, true, "apply_settings under lockdown defers the re-anchor")
    eq(u.panel.point[4], 20, "the deferred apply leaves the anchor alone")
    F.lockdown = false
    F.clock = F.clock + 0.1
    drive(b)
    eq(u.pending_apply, false, "the driver tick applies the deferred re-anchor")
    eq(u.panel.point[4], 13, "the deferred offset lands (5 + 8)")
    u.stop(T)

    -- A drag stores offsets from the bar's top-right corner and re-anchors.
    u.panel.left, u.panel.top = 100, 60
    F.bar_frame.right, F.bar_frame.top = 60, 60
    u.save_position(T)
    eq(F.class_db.practice_panel_x, 32, "a drag stores x from the bar's right edge minus the gap")
    eq(F.class_db.practice_panel_y, 0, "a drag stores y from the bar's top edge")
    eq(u.panel.point[4], 40, "the stored offset re-anchors through apply_settings")
end

--=========================================================================================
-- 12) Keybinds: session defaults, capture overlay, override rebind, reset
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)

    -- Session defaults mirror the archived reset defaults, shortened onto labels.
    eq(u.keybinds.cs, "3", "the session keybinds default to the archived set")
    eq(u.keybinds.stop, "", "stopattack defaults to unbound")
    eq(u.panel.ability_icons.cs.keybind_text.text, "3", "the cs label shows its key")
    eq(u.panel.ability_icons.stop.keybind_text.text, "", "an unbound icon labels nothing")
    eq(#F.override_bindings, 9, "nine override bindings are applied (stop is unbound)")
    eq(F.cleared_bindings, 1, "rebind clears stale bindings first")

    -- Capture flow through the overlay scripts.
    u.start_key_capture(T, "cs")
    local cap = u.key_capture_frame
    eq(u.key_capture_ability, "cs", "capture arms the ability")
    eq(cap.shown, true, "the capture overlay shows")
    check(cap.prompt.text:find("Crusader Strike") ~= nil, "the prompt names the ability")
    cap:GetScript("OnKeyDown")(cap, "LSHIFT")
    eq(u.key_capture_ability, "cs", "a bare modifier is ignored")
    cap:GetScript("OnKeyDown")(cap, "ESCAPE")
    eq(u.key_capture_ability, nil, "ESC cancels the capture")
    eq(cap.shown, false, "cancelling hides the overlay")

    -- Modifier prefixes compose the stored bind; labels shorten it.
    u.start_key_capture(T, "cs")
    F.modifiers.ctrl = true
    cap:GetScript("OnKeyDown")(cap, "1")
    F.modifiers.ctrl = false
    eq(u.keybinds.cs, "CTRL-1", "capture records the modifier prefix")
    eq(u.panel.ability_icons.cs.keybind_text.text, "C1", "the label shortens the bind")
    local rebound = false
    for i = 1, #F.override_bindings do
        if F.override_bindings[i].bind == "CTRL-1" then
            rebound = true
        end
    end
    check(rebound, "finishing a capture re-applies the override bindings")

    -- Wheel and middle-mouse capture paths.
    u.start_key_capture(T, "judge")
    cap:GetScript("OnMouseWheel")(cap, 1)
    eq(u.keybinds.judge, "MOUSEWHEELUP", "wheel-up captures MOUSEWHEELUP")
    eq(u.panel.ability_icons.judge.keybind_text.text, "MU", "wheel-up shortens to MU")
    u.start_key_capture(T, "aw")
    cap:GetScript("OnMouseDown")(cap, "MiddleButton")
    eq(u.keybinds.aw, "BUTTON3", "middle-click captures BUTTON3")
    u.start_key_capture(T, "aw")
    cap:GetScript("OnMouseDown")(cap, "LeftButton")
    eq(u.key_capture_ability, "aw", "left-click is not a capture key")
    cap:GetScript("OnMouseDown")(cap, "RightButton")
    eq(u.key_capture_ability, nil, "right-click cancels the capture")

    -- Lockdown skips the apply but keeps the labels.
    F.lockdown = true
    local before = #F.override_bindings
    u.rebind_keys(T)
    eq(#F.override_bindings, before, "rebind under lockdown applies nothing")
    F.lockdown = false

    -- Reset restores the defaults; stop clears the bindings.
    u.keybinds.cs = "X"
    u.reset_keybinds(T)
    eq(u.keybinds.cs, "3", "reset restores the default keybinds")
    eq(u.panel.ability_icons.cs.keybind_text.text, "3", "reset restores the labels")
    local cleared_before = F.cleared_bindings
    u.stop(T)
    eq(F.cleared_bindings, cleared_before + 1, "stop clears the override bindings")
end

--=========================================================================================
-- 13) Haste buttons: Bloodlust / haste pot / DST toggle with countdowns
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)                  -- t = 0, fight running, Bloodlust already on
    local sim = u.sim

    -- The immediate Bloodlust lights the button with its countdown.
    eq(u.panel.bl_btn.label.text, "|cFF00FFFFBloodlust|r", "an active Bloodlust highlights")
    eq(u.panel.bl_btn.countdown.text, "40", "the Bloodlust countdown reads 40 s")
    u.click_haste(T, "bl")
    eq(sim.has_bloodlust, true, "clicking Bloodlust mid-fight is a silent no-op")
    sim.has_bloodlust = false
    sim.bl_buff_expires = 0
    u.click_haste(T, "bl")
    eq(sim.has_bloodlust, false, "Bloodlust cannot be switched on mid-fight either")
    sim.has_bloodlust = true
    sim.bl_buff_expires = 40

    -- Outside a fight the button activates Bloodlust directly (no GCD, archive path).
    u.stop_fight(T)
    eq(sim.has_bloodlust, false, "stop_fight clears Bloodlust")
    F.clock = 50.0
    u.click_haste(T, "bl")
    eq(sim.has_bloodlust, true, "the button activates Bloodlust outside a fight")
    eq(sim.bl_buff_expires, 90, "Bloodlust runs 40 s from the click")
    eq(sim.gcd_active, false, "the button path starts no GCD")
    near(sim.effective_speed, 2.0, "the hasted speed applies")
    eq(u.panel.bl_btn.countdown.text, "40", "the countdown restarts")
    u.click_haste(T, "bl")
    eq(sim.bl_buff_expires, 90, "a redundant Bloodlust click changes nothing")

    -- The haste pot goes through the same direct setter (no GCD either).
    u.click_haste(T, "hpot")
    eq(sim.has_haste_pot, true, "the button activates the haste pot")
    eq(sim.gcd_active, false, "the pot button starts no GCD either")
    eq(u.panel.hp_btn.label.text, "|cFFFF8800Haste Pot|r", "an active pot highlights")
    eq(u.panel.hp_btn.countdown.text, "15", "the pot countdown reads 15 s")

    -- Expiry clears the visuals through the driver tick.
    F.clock = 65.5
    drive(b)
    eq(sim.has_haste_pot, false, "the pot expires on tick")
    eq(u.panel.hp_btn.countdown.text, "", "the expired pot clears its countdown")
    eq(u.panel.hp_btn.label.text, "Haste Pot", "the expired pot label resets")
    F.clock = 90.5
    drive(b)
    eq(sim.has_bloodlust, false, "Bloodlust expires on tick")
    eq(u.panel.bl_btn.countdown.text, "", "the expired Bloodlust clears its countdown")

    -- The DST toggle flips the session flag and clears the buff when turned off.
    eq(u.dst_enabled, false, "DST defaults off")
    u.click_haste(T, "dst")
    eq(u.dst_enabled, true, "the DST button enables procs")
    eq(u.panel.dst_btn.label.text, "|cFF00FF00DST: On|r", "the DST button highlights")
    sim.has_dst = true
    sim.dst_buff_expires = 999
    u.update_proc_icons(T)
    u.click_haste(T, "dst")
    eq(u.dst_enabled, false, "the DST button toggles back off")
    eq(sim.has_dst, false, "disabling DST clears the buff")
    eq(u.panel.dst_btn.label.text, "DST: Off", "the DST button resets")
    u.stop(T)
end

--=========================================================================================
-- 14) Rotation selector: lock/unlock, haste clearing, button visuals, bands
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)                  -- 2.0/1.154 -> 2/3, fight running, Bloodlust on
    local sim = u.sim

    eq(u.panel.rotation_text.text, "Rotation: 2/3", "the rotation line names 2/3")
    eq(u.timeline_band_count, 1, "the fight opens with one band")
    eq(u.timeline_bands[1].rotation, "2/3", "the opening band is 2/3")

    -- Lock 2/4 through its button: haste clears, speed snaps, buttons dim.
    u.panel.rot_buttons["2/4"]:GetScript("OnClick")(u.panel.rot_buttons["2/4"])
    eq(sim.locked_rotation, "2/4", "the selector locks the rotation")
    eq(sim.has_bloodlust, false, "locking clears Bloodlust")
    near(sim.effective_speed, 1.8, "the preset speed applies")
    near(sim.effective_gcd, 1.15, "the preset GCD applies")
    eq(u.panel.rot_buttons["2/4"].label.text, "|cFF00FF002/4|r", "the locked button highlights")
    eq(u.panel.rot_buttons.auto.label.text, "Raid Pull", "the auto button goes idle")
    eq(u.panel.bl_btn.alpha, 0.4, "locking dims the Bloodlust button")
    eq(u.panel.bl_btn.mouse, false, "locking disables the Bloodlust button")
    eq(u.panel.rotation_text.text, "Rotation: 2/4", "the rotation line follows the lock")
    u.click_haste(T, "bl")
    eq(sim.has_bloodlust, false, "Bloodlust stays refused while locked")
    u.click_haste(T, "hpot")
    eq(sim.has_haste_pot, false, "the pot stays refused while locked")

    -- The next driver tick logs the rotation change as a second band.
    F.clock = 1.0
    drive(b)
    eq(u.timeline_band_count, 2, "the rotation change appends a band")
    eq(u.timeline_bands[2].rotation, "2/4", "the new band carries 2/4")
    near(u.timeline_bands[2].start_time, 1.0, "the band starts at the change time")

    -- Clicking the locked preset again reverts to auto (toggle semantics).
    u.panel.rot_buttons["2/4"]:GetScript("OnClick")(u.panel.rot_buttons["2/4"])
    eq(sim.locked_rotation, nil, "a repeat click unlocks back to auto")
    near(sim.effective_speed, 2.6, "unlocking re-derives the unhasted speed")
    eq(u.panel.bl_btn.alpha, 1.0, "unlocking re-enables the haste buttons")
    eq(u.panel.rot_buttons.auto.label.text, "|cFF00FF00Raid Pull|r", "auto highlights again")

    -- The auto button unlocks explicitly too.
    u.set_locked_rotation(T, "1/2")
    eq(sim.locked_rotation, "1/2", "set_locked_rotation locks directly")
    u.panel.rot_buttons.auto:GetScript("OnClick")(u.panel.rot_buttons.auto)
    eq(sim.locked_rotation, nil, "the auto button unlocks")
    u.stop(T)
end

--=========================================================================================
-- 15) Rotation display: sequence icons, twist halves, hide rules, drag offsets
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)                  -- 2/3 -> {"cs", "twist", "twist"}
    local na = b.st.nextaction

    eq(u.rotation_display.shown, true, "the display shows while the rotation resolves")
    eq(u.current_display_rotation, "2/3", "the tracked rotation is 2/3")
    eq(u.rotation_display.rotation_name.text, na.display_names["2/3"],
        "the display names the rotation")
    eq(u.rotation_display.desc_text.text, na.descriptions["2/3"],
        "the display describes the rotation")
    local shown_icons = 0
    for i = 1, 5 do
        if u.rotation_icons[i].shown then
            shown_icons = shown_icons + 1
        end
    end
    eq(shown_icons, 3, "three icons for the 2/3 sequence")
    eq(u.rotation_icons[1].texture.texture, "icon_cs", "the cs step shows the cs icon")
    eq(u.rotation_icons[2].twist_left.hidden, false, "the twist step shows its left half")
    eq(u.rotation_icons[2].twist_right.hidden, false, "the twist step shows its right half")
    eq(u.rotation_icons[2].twist_left.texture, "icon_soc",
        "the twist left half is Seal of Command")
    eq(u.rotation_icons[2].twist_right.texture, "icon_sob",
        "the twist right half is Seal of Blood")
    eq(u.rotation_icons[4].shown, false, "unused slots stay hidden")

    -- An unresolvable rotation hides the display but keeps tracking it.
    u.sim.effective_speed = 0.005
    F.clock = 1.0
    drive(b)
    eq(u.rotation_display.shown, false, "no rotation -> the display hides")
    eq(u.current_display_rotation, nil, "the tracked rotation clears")

    -- Dragging stores session-local center offsets and re-anchors.
    u.sim.effective_speed = 2.0
    F.clock = 2.0
    drive(b)
    eq(u.rotation_display.shown, true, "the display returns with the rotation")
    u.rotation_display.center_x, u.rotation_display.center_y = 30, -40
    F.env.UIParent.center_x, F.env.UIParent.center_y = 0, 0
    u.save_rotation_position(T)
    eq(u.rot_x, 30, "a drag stores the x center offset")
    eq(u.rot_y, -40, "a drag stores the y center offset")
    eq(u.rotation_display.point[4], 30, "the stored offset re-anchors")
    u.stop(T)
    eq(u.rotation_display.shown, false, "stop hides the display")
    eq(u.current_display_rotation, nil, "stop clears the tracked rotation")
end

--=========================================================================================
-- 16) Timeline: event collection, band tracking, render pools, grading marks
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)                  -- t = 0, fight running, Seal of Blood up
    local sim = u.sim

    -- Casts log on their lanes with fight-relative times.
    F.clock = 0.5
    u.cast_key(T, "cs")
    eq(u.timeline_event_count, 1, "the cs cast logs one event")
    eq(u.timeline_events[1].lane, "cs", "the cs event lane")
    eq(u.timeline_events[1].texture, "icon_cs", "the cs event texture")
    near(u.timeline_events[1].time, 0.5, "the cs event carries the fight time")
    F.clock = 0.6
    u.cast_key(T, "judge")      -- off-GCD: judges the blood seal
    eq(u.timeline_event_count, 2, "the judge cast logs a second event")
    eq(u.timeline_events[2].lane, "judge", "the judge event lane")
    eq(u.timeline_events[2].seal_active, "blood", "judge records the judged seal")
    eq(sim.n_active_seals, 0, "judgement consumed the seals")

    -- The landed swing logs a melee event; the timeline renders on the tick.
    F.clock = 2.01
    drive(b)
    eq(u.timeline_event_count, 3, "the swing logs the melee event")
    eq(u.timeline_events[3].lane, "melee", "the swing event lane")
    eq(u.timeline_events[3].result, "miss", "the seal-less swing is a miss")
    eq(u.timeline_needs_render, false, "the visible timeline renders on the tick")
    eq(u.timeline_icon_pool_used, 3, "one pooled icon per event")
    eq(u.timeline_divider_pool_used, 1, "one divider per melee event")
    eq(u.timeline_ruler_pool_used, 4, "ruler ticks for seconds 0..3")
    eq(u.timeline_rotation_band_pool_used, 1, "one band entry for the opening band")
    local max_lo, max_hi = u.timeline_frame.scrollbar:GetMinMaxValues()
    eq(max_lo, 0, "the scrollbar starts at 0")
    eq(max_hi, 800, "10 s of content at 80 pps fills the scrollbar")
    eq(u.timeline_frame.scrollbar:GetValue(), 800, "auto-scroll rides the end")
    eq(u.timeline_frame.scroll_frame.h_scroll, 800, "the scroller follows")

    -- The seal-less opener swing is wrong: error border + X + tooltip data.
    local marked = 0
    for i = 1, u.timeline_icon_pool_used do
        local icon = u.timeline_icon_pool[i]
        if icon.analysis_data and not icon.analysis_data.correct then
            marked = marked + 1
            check(icon.error_border.hidden == false, "a wrong swing shows its error border")
            eq(icon.result_label.text, "|cFFFF3333X|r", "a wrong swing is marked X")
            icon:GetScript("OnEnter")(icon)
            check(F.env.GameTooltip.shown, "hovering a wrong swing shows the tooltip")
            local tip = F.env.GameTooltip.lines
            check(#tip >= 3, "the tooltip explains the mistake")
            icon:GetScript("OnLeave")(icon)
            eq(F.env.GameTooltip.shown, false, "leaving hides the tooltip")
        end
    end
    check(marked >= 1, "at least one swing is marked wrong")

    -- Toggle hides/shows; stop_fight keeps the data; start_fight resets it.
    u.toggle_timeline(T)
    eq(u.timeline_visible, false, "toggle hides the timeline")
    eq(u.timeline_frame.shown, false, "the frame hides")
    eq(u.panel.timeline_btn.label.text, "Timeline", "the toggle button resets")
    u.toggle_timeline(T)
    eq(u.timeline_visible, true, "toggle shows the timeline again")
    eq(u.panel.timeline_btn.label.text, "|cFF00FF00Timeline|r", "the toggle highlights")
    u.stop_fight(T)
    eq(u.timeline_event_count, 3, "stop_fight keeps the events for review")
    eq(u.timeline_visible, true, "stop_fight keeps the frame up")
    u.start_fight(T)
    eq(u.timeline_event_count, 0, "start_fight clears the events")
    eq(u.timeline_band_count, 1, "start_fight re-opens the band")
    u.stop(T)
    eq(u.timeline_frame.shown, false, "stop hides the timeline")
    eq(u.timeline_event_count, 0, "stop clears the events")
    eq(u.timeline_band_count, 0, "stop clears the bands")
end

--=========================================================================================
-- 17) Proc icons: Bloodlust/DST states plus the gated DST proc roll
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)                  -- immediate Bloodlust: the BL icon lights up
    local sim = u.sim
    local bl, dst = u.proc_icons.bl, u.proc_icons.dst

    eq(bl.shown, true, "the BL icon shows during the session")
    eq(bl.alpha, 1, "an active Bloodlust runs the icon full alpha")
    eq(bl.countdown.text, "40", "the BL icon counts its 40 s down")
    eq(swipe_activations(bl.cooldown.cooldown_calls, 40), 1, "the BL swipe is set once")
    eq(dst.alpha, 0.4, "the inactive DST icon sits dimmed")
    eq(dst.countdown.text, "", "the inactive DST icon counts nothing")

    -- DST stays unrunnable while the toggle is off, even with a friendly roll.
    u.random = function() return 0 end
    F.clock = 2.01
    drive(b)
    eq(sim.has_dst, false, "no DST proc while the toggle is off")

    -- Enabled and unlocked, the roll procs through the driver's swing path.
    u.click_haste(T, "dst")
    F.clock = 4.02
    drive(b)
    eq(sim.has_dst, true, "the toggle on + a 0 roll procs DST")
    eq(dst.alpha, 1, "the DST icon lights up")
    eq(dst.countdown.text, "10", "the DST icon counts its 10 s down")
    near(sim.effective_speed, 1.658, "the proc re-derives the hasted speed")

    -- A locked rotation suppresses the roll even with the toggle on.
    sim.has_dst = false
    sim.dst_buff_expires = 0
    sim.dst_icd_expires = 0
    u.set_locked_rotation(T, "2/3")
    F.clock = 6.5
    drive(b)
    eq(sim.has_dst, false, "no DST proc while the rotation is locked")
    u.set_locked_rotation(T, nil)
    u.random = nil
    u.stop(T)
    eq(bl.shown, false, "stop hides the proc icons")
end

--=========================================================================================
-- 18) Bar overlays: attach/detach, press flash, set-once cooldown, GCD dim
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)

    -- Attaching builds the overlay on the caller-supplied parent frame.
    local parent = F.env.CreateFrame("Frame", nil, F.env.UIParent)
    u.attach_overlay(T, "cs", parent)
    local ov = u.overlays.cs
    check(ov ~= nil, "attach_overlay creates the overlay")
    eq(ov.container.shown, true, "the overlay container shows")
    eq(ov.cooldown_set, false, "no cooldown is latched yet")
    eq(ov.cd_text.hidden, true, "the countdown starts hidden")
    eq(ov.flash.hidden, true, "the flash starts hidden")

    -- Casting flashes the button; the tick latches the cooldown exactly once.
    F.clock = 0.5
    u.cast_key(T, "cs")
    near(ov.flash_timer, 0.134, "a cast fires the press flash (one fade step consumed)")
    eq(ov.flash.hidden, false, "the flash shows")
    F.clock = 0.56
    drive(b)
    eq(swipe_activations(ov.cooldown.cooldown_calls, 6), 1, "the overlay swipe latches once")
    eq(ov.cooldown_set, true, "the overlay records the latch")
    eq(ov.cd_text.hidden, false, "the countdown shows while cooling down")
    check(ov.cd_text.text ~= nil and ov.cd_text.text ~= "", "the countdown carries seconds")
    F.clock = 1.0
    drive(b)
    eq(swipe_activations(ov.cooldown.cooldown_calls, 6), 1, "ticks do not re-latch the swipe")
    eq(ov.gcd_dim.hidden, false, "the GCD dim shows during the simulated GCD")

    -- Expiry clears the swipe and the countdown; the flash fades on its own.
    F.clock = 7.0
    drive(b)
    eq(swipe_clears(ov.cooldown.cooldown_calls), 1, "expiry clears the swipe once")
    eq(ov.cd_text.hidden, true, "the countdown hides at expiry")
    eq(ov.gcd_dim.hidden, true, "the GCD dim hides after the GCD")
    for i = 1, 12 do
        F.clock = 7.0 + i * 0.06
        drive(b)
    end
    eq(ov.flash_timer, 0, "the flash timer bottoms out")
    eq(ov.flash.hidden, true, "the flash fades out")
    eq(ov.flash.hidden, true, "the flash fades out")

    -- Detach removes the overlay; lockdown refuses new ones.
    u.detach_overlay(T, "cs")
    eq(u.overlays.cs, nil, "detach removes the overlay")
    u.attach_overlay(T, "cs", parent)
    u.attach_overlay(T, "judge", parent)
    u.detach_all_overlays(T)
    eq(u.overlays.cs, nil, "detach-all removes every overlay")
    eq(u.overlays.judge, nil, "detach-all removes every overlay (judge)")
    F.lockdown = true
    u.attach_overlay(T, "cs", parent)
    eq(u.overlays.cs, nil, "attach under lockdown creates nothing")
    F.lockdown = false
    u.stop(T)
end

--=========================================================================================
-- 19) Fight timer, info latches, buff/seal border highlights
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)

    -- The fight clock runs while the fight does and clears when it stops.
    F.clock = 65.0
    drive(b)
    eq(u.panel.fight_timer_text.text, "Fight: 1:05", "the fight clock formats m:ss")
    u.stop_fight(T)
    eq(u.panel.fight_timer_text.text, "", "stop_fight clears the fight clock")

    -- Buff and active-seal border highlights ride refresh_icons.
    F.clock = 66.0
    u.start_fight(T)
    u.cast_key(T, "aw")
    F.clock = 66.5
    drive(b)
    local aw_border = u.panel.ability_icons.aw.border.color
    eq(aw_border[1], 1.0, "an active AW gilds its border (r)")
    eq(aw_border[2], 0.8, "an active AW gilds its border (g)")
    u.cast_key(T, "soc")
    F.clock = 67.0
    drive(b)
    local soc_border = u.panel.ability_icons.soc.border.color
    eq(soc_border[2], 0.8, "an active seal greens its border")
    local sob_border = u.panel.ability_icons.sob.border.color
    eq(sob_border[1], 0.3, "an inactive seal keeps the idle border")
    F.clock = 87.0
    drive(b)
    eq(u.panel.ability_icons.aw.border.color[1], 0.3, "an expired AW drops its border")
    u.stop(T)
end

--=========================================================================================
-- 20) Scoring: running session score, per-attempt grades, persistent personal bests
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    eq(u.panel.score_text ~= nil, true, "the panel owns a score line")
    eq(u.panel.score_text.text, "", "the score line starts empty")
    eq(F.created_frames, 70, "the score line adds no frames (a FontString, not a frame)")
    u.start(T)                  -- t = 0, fight running, Seal of Blood up

    -- No attempts yet, no stored bests: the placeholder line.
    eq(u.score ~= nil, true, "start opens a fresh session score")
    eq(u.score.attempts, 0, "the fresh score counts nothing")
    eq(u.bests, nil, "a fresh profile loads no bests")
    eq(u.panel.score_text.text, "Score --", "the empty score line")

    -- Arm a twist inside the fade window: the landed swing records an A (110ms).
    -- (Soc at 1.9 swaps blood->command and fades blood till 2.3; the 2.0 swing
    -- lands at the 2.01 drive with a 110ms lead.)
    F.clock = 1.9
    u.cast_key(T, "soc")
    F.clock = 2.01
    drive(b, 0.01)
    eq(u.result_frame.text.text, "TWIST!", "the popup text is unchanged by scoring")
    eq(u.score.attempts, 1, "the graded swing records one attempt")
    eq(u.score.hits, 1, "the twist records one hit")
    eq(u.score.best_grade, "A", "the 110ms lead tracks best grade A")
    eq(u.score.last_grade, "A", "the last grade tracks the attempt")
    eq(u.panel.score_text.text, "Score 80 1/1 110ms A Best --",
        "the line shows score, hits, mean error, last grade and no best yet")

    -- A second twist past the fade window records an F and drags the score.
    -- (Sob at 3.1 swaps back with the fade till 3.5; the 4.01 swing lands at the
    -- 4.02 drive after the fade expired. 3.1 clears the 1.9 + 1.154 GCD.)
    F.clock = 3.1
    u.cast_key(T, "sob")
    F.clock = 4.02
    drive(b, 0.01)
    eq(u.result_frame.text.text, "MISS", "the expired window still grades MISS")
    eq(u.score.attempts, 2, "the miss records a second attempt")
    eq(u.score.hits, 1, "the miss records no hit")
    eq(u.score.last_grade, "F", "the last grade tracks the miss")
    eq(u.score.best_grade, "A", "the best grade survives a miss")
    eq(u.panel.score_text.text, "Score 40 1/2 110ms F Best --",
        "the miss halves the score; the mean error still covers the one hit")

    -- Fight end persists the best into the addon's own class table only.
    local hand_keys_before = count_keys(F.hand_db)
    u.stop_fight(T)
    check(type(F.class_db.practice_bests) == "table", "stop_fight writes db.practice_bests")
    eq(F.class_db.practice_bests.score, 40, "the stored best score")
    eq(F.class_db.practice_bests.grade, "A", "the stored best grade")
    eq(F.class_db.practice_bests.attempts, 2, "the stored attempt count")
    near(F.class_db.practice_bests.hit_rate, 0.5, "the stored hit-rate")
    eq(count_keys(F.hand_db), hand_keys_before, "nothing is written outside the class table")
    eq(u.panel.score_text.text, "Score 40 1/2 110ms F Best 40 (A)",
        "the line picks up the persisted best")

    -- A new session loads the stored best; empty fights never overwrite it.
    u.stop(T)
    u.start(T)
    eq(u.score.attempts, 0, "a new session restarts the running score")
    eq(u.bests.score, 40, "the new session loads the stored best")
    eq(u.bests.grade, "A", "the new session loads the stored best grade")
    eq(u.panel.score_text.text, "Score -- Best 40 (A)", "the empty line keeps the best")
    u.stop_fight(T)
    eq(F.class_db.practice_bests.score, 40, "a fight with no attempts saves nothing")
    u.start_fight(T)
    F.clock = F.clock + 0.06
    drive(b, 0.06)
    u.stop_fight(T)
    eq(F.class_db.practice_bests.score, 40, "a scoreless fight never overwrites the best")

    -- A tighter twist in the next fight beats the best; stop() mid-fight saves too.
    -- (start_fight re-Bloodlusts to a 2.0 swing ending at fight start + 2.0; the soc
    -- 60ms before it lands grades S.)
    u.start_fight(T)
    local landing = u.sim.swing_ends_at
    F.clock = landing - 0.06
    u.cast_key(T, "soc")
    F.clock = landing
    drive(b, 0.06)
    eq(u.result_frame.text.text, "TWIST!", "the tight twist lands")
    eq(u.score.best_grade, "S", "the 60ms lead tracks best grade S")
    eq(u.panel.score_text.text,
        "Score 100 1/1 60ms S Best 40 (A)", "the running line leads the stored best")
    u.stop(T)
    eq(F.class_db.practice_bests.score, 100, "stop() mid-fight persists the better score")
    eq(F.class_db.practice_bests.grade, "S", "the better grade persists with it")
    eq(count_keys(F.hand_db), hand_keys_before, "the better save stays in the class table")
end

--=========================================================================================
-- 21) Design-mode targets: descriptor shape, save/reset per element, session gating
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb

    -- Before init: the descriptors exist, frames read nil, nothing is available.
    eq(type(u.design_targets), "table", "the design targets table exists at load")
    eq(#u.design_targets, 5, "five practice elements are exposed")
    local by_key = {}
    for i = 1, #u.design_targets do
        by_key[u.design_targets[i].key] = u.design_targets[i]
    end
    check(by_key.practice_panel ~= nil, "the panel target is registered")
    check(by_key.practice_rotation ~= nil, "the rotation display target is registered")
    check(by_key.practice_timeline ~= nil, "the timeline target is registered")
    check(by_key.practice_hunter_report ~= nil, "the hunter report target is registered")
    check(by_key.practice_warrior_report ~= nil, "the warrior report target is registered")
    for _, key in ipairs({ "practice_panel", "practice_rotation", "practice_timeline",
        "practice_hunter_report", "practice_warrior_report" }) do
        local d = by_key[key]
        eq(type(d.title), "string", key .. " has a title")
        eq(type(d.get_frame), "function", key .. " has get_frame")
        eq(type(d.available), "function", key .. " has available")
        eq(type(d.save), "function", key .. " has save")
        eq(type(d.reset), "function", key .. " has reset")
        eq(d.get_frame(), nil, key .. ": no frame before init")
        eq(d.available(), false, key .. ": unavailable before a session")
    end

    u.init(T)
    for _, key in ipairs({ "practice_panel", "practice_rotation", "practice_timeline" }) do
        check(by_key[key].get_frame() ~= nil, key .. ": the frame exists after init")
    end
    -- Reports build on toggle, not on init (session-independent screens).
    eq(by_key.practice_hunter_report.get_frame(), nil, "the shot report builds on toggle")
    eq(by_key.practice_warrior_report.get_frame(), nil, "the Execute report builds on toggle")
    u.start(T)
    for _, key in ipairs({ "practice_panel", "practice_rotation", "practice_timeline" }) do
        eq(by_key[key].available(), true, key .. ": available during a session")
    end
    eq(by_key.practice_hunter_report.available(), false, "the shot report hides until shown")
    eq(by_key.practice_warrior_report.available(), false, "the Execute report hides until shown")

    -- Shot report: toggle shows it, save/reset move it, toggle hides it again.
    u.toggle_hunter_report(T)
    eq(by_key.practice_hunter_report.available(), true, "the shot report is available while shown")
    local hr = by_key.practice_hunter_report
    hr.save(120, 60)
    eq(u.hunter_report_frame.point[1], "CENTER", "the shot report save re-anchors")
    eq(u.hunter_report_frame.point[4], 120, "the shot report save stores x")
    eq(u.hunter_report_frame.point[5], 60, "the shot report save stores y")
    hr.reset()
    eq(u.hunter_report_frame.point[4], 0, "the shot report reset restores x")
    eq(u.hunter_report_frame.point[5], 60, "the shot report reset restores y")

    -- Execute report: same shape, same defaults.
    u.toggle_warrior_execute_report(T)
    eq(by_key.practice_warrior_report.available(), true, "the Execute report is available while shown")
    local er = by_key.practice_warrior_report
    er.save(-40, 90)
    eq(u.warrior_execute_report_frame.point[1], "CENTER", "the Execute report save re-anchors")
    eq(u.warrior_execute_report_frame.point[4], -40, "the Execute report save stores x")
    eq(u.warrior_execute_report_frame.point[5], 90, "the Execute report save stores y")
    er.reset()
    eq(u.warrior_execute_report_frame.point[4], 0, "the Execute report reset restores x")
    eq(u.warrior_execute_report_frame.point[5], 60, "the Execute report reset restores y")
    u.toggle_hunter_report(T)
    eq(by_key.practice_hunter_report.available(), false, "the shot report hides on toggle-off")
    u.toggle_warrior_execute_report(T)
    eq(by_key.practice_warrior_report.available(), false, "the Execute report hides on toggle-off")

    -- Lockdown: a fresh toggle refuses with a message instead of creating frames.
    local lb = build()
    local lu, lT, lF = lb.st.practice_ui, lb.ST, lb.sb
    lu.init(lT)
    lF.lockdown = true
    local frames_before = lF.created_frames
    lu.toggle_hunter_report(lT)
    eq(lF.created_frames, frames_before, "lockdown: no shot report frame is created")
    check((lF.prints[#lF.prints] or ""):find("cannot be opened in combat", 1, true) ~= nil,
        "lockdown: the shot report refusal names the combat gate")
    lu.toggle_warrior_execute_report(lT)
    eq(lF.created_frames, frames_before, "lockdown: no Execute frame is created either")
    check((lF.prints[#lF.prints] or ""):find("cannot be opened in combat", 1, true) ~= nil,
        "lockdown: the Execute refusal names the combat gate")

    -- Panel: save re-anchors through the panel's own path and persists its offsets.
    local panel = by_key.practice_panel
    u.panel.left, u.panel.top = 148, 20
    F.bar_frame.right, F.bar_frame.top = 60, 60
    panel.save(120, -80)
    eq(F.class_db.practice_panel_x, 80, "save_position persists the x offset")
    eq(F.class_db.practice_panel_y, -40, "save_position persists the y offset")
    eq(u.panel.point[1], "TOPLEFT", "the panel save re-anchors through the bar path")
    eq(u.panel.point[4], 88, "the stored x offset plus the default gap")
    eq(u.panel.point[5], -40, "the stored y offset")
    panel.reset()
    eq(F.class_db.practice_panel_x, 0, "the panel reset restores the default x")
    eq(F.class_db.practice_panel_y, 0, "the panel reset restores the default y")
    eq(u.panel.point[1], "TOPLEFT", "the reset re-anchors to the bar")
    eq(u.panel.point[4], 8, "the default gap lands at 8 px")

    -- Rotation display: save stores the session-local centre offsets.
    local rot = by_key.practice_rotation
    u.rotation_display.center_x, u.rotation_display.center_y = 120, -80
    rot.save(120, -80)
    eq(u.rot_x, 120, "the rotation save stores x")
    eq(u.rot_y, -80, "the rotation save stores y")
    eq(u.rotation_display.point[1], "CENTER", "the rotation save re-anchors")
    rot.reset()
    eq(u.rot_x, 0, "the rotation reset restores the default x")
    eq(u.rot_y, 100, "the rotation reset restores the default y")
    eq(u.rotation_display.point[4], 0, "the reset re-anchors at the default x")
    eq(u.rotation_display.point[5], 100, "the reset re-anchors at the default y")

    -- Timeline: save stores the session-local centre offsets.
    local tl = by_key.practice_timeline
    tl.save(50, -300)
    eq(u.timeline_x, 50, "the timeline save stores x")
    eq(u.timeline_y, -300, "the timeline save stores y")
    eq(u.timeline_frame.point[1], "CENTER", "the timeline save re-anchors")
    tl.reset()
    eq(u.timeline_x, 0, "the timeline reset restores the default x")
    eq(u.timeline_y, -200, "the timeline reset restores the default y")
    eq(u.timeline_frame.point[5], -200, "the reset re-anchors at the default y")

    u.stop(T)
    eq(by_key.practice_panel.available(), false, "the targets gate on the session again")

    -- The descriptors pass the real design.lua registry normaliser (the C6 contract).
    for i = 1, #u.design_targets do
        local norm, nerr = b.st.design.normalise_descriptor(u.design_targets[i])
        check(norm ~= nil, "target " .. u.design_targets[i].key .. " normalises (" .. tostring(nerr) .. ")")
        if norm then
            eq(norm.key, u.design_targets[i].key, "the normalised key survives for " .. norm.key)
        end
    end
end

--=========================================================================================
-- 22) Grade review: timeline close button, drag persistence, key buttons, wheel, bests
--=========================================================================================
do
    -- The timeline close button is labelled and toggles the frame.
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)
    local tclose = nil
    for i = 1, #F.frames do
        local fr = F.frames[i]
        if fr.parent == u.timeline_frame and fr.width == 16 and fr:GetScript("OnClick") then
            tclose = fr
        end
    end
    check(tclose ~= nil, "the timeline close button exists")
    eq(tclose.label.text, "X", "the timeline close button reads X")
    eq(u.timeline_visible, true, "the timeline shows after start")
    tclose:GetScript("OnClick")()
    eq(u.timeline_visible, false, "the timeline close button hides the timeline")
    eq(u.timeline_frame.shown, false, "the frame hides")
    tclose:GetScript("OnClick")()
    eq(u.timeline_visible, true, "the close button shows the timeline again")
    u.stop(T)
end

do
    -- A timeline drag stores session-local center offsets and re-anchors.
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)
    u.timeline_frame.center_x, u.timeline_frame.center_y = 50, -300
    F.env.UIParent.center_x, F.env.UIParent.center_y = 0, 0
    u.save_timeline_position(T)
    eq(u.timeline_x, 50, "a drag stores the timeline x center offset")
    eq(u.timeline_y, -300, "a drag stores the timeline y center offset")
    eq(u.timeline_frame.point[4], 50, "the stored offset re-anchors")
    eq(u.timeline_frame.point[5], -300, "the stored y offset re-anchors")
    -- The frame's own drag-stop script persists (it previously snapped back).
    u.timeline_x, u.timeline_y = 0, -200
    u.timeline_frame:GetScript("OnDragStop")(u.timeline_frame)
    eq(u.timeline_x, 50, "the drag-stop script persists the position")
    u.stop(T)
end

do
    -- The invisible key buttons cast through cast_key.
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)
    local sim = u.sim
    F.clock = 4.0
    sim.gcd_active = false
    sim.cs_cooldown_expires = 0
    local sync0 = F.practice_sync
    u.buttons.cs:GetScript("OnClick")()
    near(sim.cs_cooldown_expires, 10.0, "the key button casts (4.0 + 6)")
    eq(F.practice_sync, sync0 + 1, "the key button syncs once")
    u.stop(T)
end

do
    -- The timeline mousewheel drives the scrollbar and the auto-scroll latch.
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)
    F.clock = 0.5
    u.cast_key(T, "cs")
    F.clock = 2.01
    drive(b)
    eq(u.timeline_auto_scroll, true, "auto-scroll rides the end after render")
    local sf = u.timeline_frame.scroll_frame
    local _, max_hi = u.timeline_frame.scrollbar:GetMinMaxValues()
    check(max_hi > 0, "the scrollbar spans the content")
    sf:GetScript("OnMouseWheel")(sf, 1)
    eq(u.timeline_auto_scroll, false, "wheeling up leaves the end")
    check(u.timeline_frame.scrollbar:GetValue() < max_hi, "wheeling up scrolls back")
    sf:GetScript("OnMouseWheel")(sf, -1)
    eq(u.timeline_auto_scroll, true, "wheeling down to the end resumes auto-scroll")
    u.stop(T)
end

do
    -- A better grade with a worse score still persists the grade (never downgrades).
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    local pr = b.st.practice
    F.class_db.practice_bests = { score = 100, hit_rate = 1.0, mean_error_ms = 50,
        attempts = 5, grade = "A" }
    u.init(T)
    u.start(T)
    eq(u.bests.grade, "A", "the seeded best grade loads")
    pr.record_attempt(u.score, "S", 60)
    for _ = 1, 4 do pr.record_attempt(u.score, "F", nil) end
    u.stop_fight(T)
    eq(F.class_db.practice_bests.score, 100, "a worse score never overwrites the best score")
    eq(F.class_db.practice_bests.grade, "S", "the better grade still persists")
    eq(F.class_db.practice_bests.attempts, 5, "the attempt count rides with the kept score")
    u.stop(T)
end

do
    -- Equal score with a tighter mean error wins the tiebreak.
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    local pr = b.st.practice
    F.class_db.practice_bests = { score = 40, hit_rate = 0.5, mean_error_ms = 110,
        attempts = 2, grade = "A" }
    u.init(T)
    u.start(T)
    pr.record_attempt(u.score, "A", 50)
    pr.record_attempt(u.score, "F", nil)
    u.stop_fight(T)
    eq(F.class_db.practice_bests.score, 40, "the tie score persists")
    near(F.class_db.practice_bests.mean_error_ms, 50, "the tighter mean error wins the tiebreak")
    u.stop(T)
end

do
    -- Corrupted stored bests read as empty and are repaired by the next save.
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    local pr = b.st.practice
    F.class_db.practice_bests = "junk"
    u.init(T)
    u.start(T)
    eq(u.bests, nil, "a non-table best reads as no best")
    eq(u.panel.score_text.text, "Score --", "the line shows no best")
    pr.record_attempt(u.score, "S", 60)
    u.stop_fight(T)
    check(type(F.class_db.practice_bests) == "table", "the next save repairs the stored best")
    eq(F.class_db.practice_bests.score, 100, "the repaired best carries the session score")
    u.stop(T)
end

do
    -- Wrong-typed fields inside the stored table fall back to empty values.
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    F.class_db.practice_bests = { score = "x", hit_rate = "y", grade = 7, attempts = "z" }
    u.init(T)
    u.start(T)
    eq(u.bests.score, 0, "a non-number score falls back to 0")
    eq(u.bests.grade, nil, "a non-string grade falls back to nil")
    eq(u.bests.attempts, 0, "a non-number attempt count falls back to 0")
    eq(u.best_score_text(), "0", "a zero score with no grade reads as 0")
    u.stop(T)
end

do
    -- Reload semantics: dropping the live bests re-reads them from the class table.
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    local pr = b.st.practice
    u.init(T)
    u.start(T)
    pr.record_attempt(u.score, "S", 60)
    u.stop_fight(T)
    eq(F.class_db.practice_bests.score, 100, "the session persists its score")
    u.bests = nil
    u.load_bests(T)
    eq(u.bests.score, 100, "a reload re-reads the stored score")
    eq(u.bests.grade, "S", "a reload re-reads the stored grade")
    u.stop(T)
end

--=========================================================================================
-- Hunter post-fight shot report (H2): standalone screen over the live hunter log
--=========================================================================================
do
    -- Toggle before init builds the hidden frame, shows it, and renders the empty
    -- hint: no session and no hunter log needed.
    local b = build()
    local u, T = b.st.practice_ui, b.ST
    eq(u.hunter_report_frame, nil, "H2: no report frame at load")
    local ok, err = pcall(u.toggle_hunter_report, T)
    check(ok, "H2: toggle before init does not error (" .. tostring(err) .. ")")
    check(u.hunter_report_frame ~= nil, "H2: toggle builds the report frame")
    eq(u.hunter_report_visible, true, "H2: toggle shows the report")
    eq(u.hunter_report_frame.shown, true, "H2: the frame is shown")
    eq(u.hunter_report_frame.summary_text.text, "Shots: 0 (0 clipped, 0%)",
        "H2: the empty log summarizes zero")
    eq(u.hunter_report_frame.hint_text.text, "No shots logged yet.",
        "H2: the empty log hints the empty line")
    u.toggle_hunter_report(T)
    eq(u.hunter_report_visible, false, "H2: toggle hides the report")
    eq(u.hunter_report_frame.shown, false, "H2: the frame is hidden")
    -- Re-toggle reuses the frame (no duplicate build).
    local frames_before = b.sb.created_frames
    u.toggle_hunter_report(T)
    eq(b.sb.created_frames, frames_before, "H2: re-toggle builds no new frame")
    eq(u.hunter_report_visible, true, "H2: re-toggle shows again")
    u.toggle_hunter_report(T)
end

-- Render over a hunter log: counts, rate and the advisory hint. A second render with
-- the hunter_window kernel injected carries the buffer clause.
do
    local b = build()
    local u, T = b.st.practice_ui, b.ST
    T.HUNTER = { hunter_shot_log = {
        { clipped = false, latency = 0.1, at = 1 },
        { clipped = true, latency = 0.2, at = 2 },
        { clipped = false, latency = 0.3, at = 3 },
    } }
    u.toggle_hunter_report(T)
    eq(u.hunter_report_frame.summary_text.text, "Shots: 3 (1 clipped, 33%)",
        "H2: the report summarizes the log")
    check(u.hunter_report_frame.hint_text.text:find("1 of 3 shots clipped %(33%%%)") ~= nil,
        "H2: the hint reports the clip count")
    check(u.hunter_report_frame.hint_text.text:find("buffer used") == nil,
        "H2: no hunter_window means no buffer clause")
    b.st.hunter_window = { cast_window = function(lat) return 0.5 + (lat or 0) end }
    u.render_hunter_report(T)
    check(u.hunter_report_frame.hint_text.text:find("buffer used") ~= nil,
        "H2: the kernel injects the buffer clause")
    u.toggle_hunter_report(T)
end

-- stop_fight re-renders a visible report so the post-fight numbers are final; a
-- hidden report stays untouched. No practice engine: render is a safe no-op.
do
    local b = build()
    local u, T = b.st.practice_ui, b.ST
    u.init(T)
    u.start(T)
    u.toggle_hunter_report(T)
    T.HUNTER = { hunter_shot_log = { { clipped = true, latency = 0.1, at = 1 } } }
    u.stop_fight(T)
    eq(u.hunter_report_frame.summary_text.text, "Shots: 1 (1 clipped, 100%)",
        "H2: stop_fight refreshes the visible report")
    u.toggle_hunter_report(T)
    T.HUNTER.hunter_shot_log = {}
    u.stop_fight(T)
    eq(u.hunter_report_frame.summary_text.text, "Shots: 1 (1 clipped, 100%)",
        "H2: stop_fight never touches a hidden report")
    u.stop(T)

    local nb = build({ no_practice = true })
    local nu = nb.st.practice_ui
    local ok, err = pcall(nu.render_hunter_report, nb.ST)
    check(ok, "H2: render without the engine does not error (" .. tostring(err) .. ")")
end

--=========================================================================================
-- N4: compute isolation - a throwing sim tick freezes scoring, never the session.
-- First throw prints once, every throw counts in ST.bar_hook_errors (the /st diag
-- counter), the site quarantines after 25. No attempt is recorded on a failed tick.
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 100.0
    u.start(T)
    local pr = b.st.practice
    local real_tick = pr.tick
    pr.tick = function() error("N4 probe throw") end
    local prints_before = #F.prints
    F.clock = 100.1
    local ok, err = pcall(drive, b, 0.1)
    check(ok, "N4: a throwing sim tick does not break the driver (" .. tostring(err) .. ")")
    eq(u.score.attempts, 0, "N4: a failed compute records no attempt (scoring frozen)")
    eq(u.result_remaining, 0, "N4: a failed compute shows no result popup")
    eq(T.bar_hook_errors.count, 1, "N4: the throw is counted")
    eq(T.bar_hook_errors.by_site["practice:tick"], 1, "N4: the counter names the session tick")
    eq(#F.prints, prints_before + 1, "N4: the first throw prints exactly one chat line")
    check((F.prints[#F.prints] or ""):find("practice:tick", 1, true) ~= nil,
        "N4: the notice names the failed tick")
    for _ = 1, 3 do
        F.clock = F.clock + 0.1
        drive(b, 0.1)
    end
    eq(T.bar_hook_errors.by_site["practice:tick"], 4, "N4: every throw keeps counting")
    eq(#F.prints, prints_before + 1, "N4: repeated throws do not spam chat")
    for _ = 5, 25 do
        F.clock = F.clock + 0.1
        drive(b, 0.1)
    end
    eq(T.bar_hook_errors.by_site["practice:tick"], 25, "N4: the site reaches the quarantine threshold")
    eq(T.bar_hook_errors.quarantined["practice:tick"], true, "N4: the site is quarantined for the session")
    local counted = T.bar_hook_errors.count
    local calls = 0
    pr.tick = function() calls = calls + 1 end
    F.clock = F.clock + 0.1
    drive(b, 0.1)
    eq(calls, 0, "N4: a quarantined tick is not computed again")
    eq(T.bar_hook_errors.count, counted, "N4: a quarantined tick does not keep counting")
    eq(u.score.attempts, 0, "N4: the quarantined tick still records nothing")
    pr.tick = real_tick
    u.stop(T)
end

--=========================================================================================
-- 23) Drill UI sessions: rogue template first, then hunter / shaman / druid
--=========================================================================================
-- Each drill runs the identical shell lifecycle (start -> tick -> cast -> stop)
-- through practice_ui: H1 pcall+quarantine on every drill tick/cast, H2 live
-- GCD/aura restoration on stop, H4 key-drift refusal instead of a paladin sim.
do
    -- Rogue drill UI session (the template the other three drills mirror).
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.player_class = "ROGUE"
T.active_class = "ROGUE"
    local tick_calls, cast_calls, sync_calls, end_calls = 0, 0, 0, 0
    T.ROGUE = {
        practice_scenario_key = function() return "rogue_energy_pool" end,
        PRACTICE_CAST_ORDER = { "evisc" },
        practice_cast_label = function(key)
            if key == "evisc" then return "Pool Spend" end
            return nil
        end,
        practice_cast_spell_id = function(key)
            if key == "evisc" then return "Eviscerate" end
            return nil
        end,
        new_practice_session = function(now, opts) return { active = false } end,
        new_ss_session = function(now, opts) return nil end,
        practice_begin_session = function(session, now) session.active = true return true end,
        practice_cast_order = function() return { "evisc" } end,
        tick_practice_session = function(session, now, elapsed, out)
            tick_calls = tick_calls + 1
            return out or {}
        end,
        practice_cast = function(drill, now, key)
            cast_calls = cast_calls + 1
            return "S"
        end,
        practice_status = function(state, now) return "Pool: --" end,
        practice_fight_elapsed = function(session, now) return 0 end,
        end_practice_session = function(session, now)
            end_calls = end_calls + 1
            session.active = false
            return true
        end,
        practice_sync = function() sync_calls = sync_calls + 1; return 0 end,
    }
    T.ROGUE.practice_panel = fixture_panel(b, T, "ROGUE")
    u.init(T)
    eq(count_keys(u.panel.ability_icons), 1, "rogue: the panel shows the drill order")
    check(u.panel.ability_icons.evisc ~= nil, "rogue: the pool spend icon exists")
    eq(u.panel.title.text, "|cFFFF8800Pool Practice|r", "rogue: the drill title ships")
    u.start(T)
    eq(u.active, true, "rogue: start activates the session")
    eq(u.rogue_session ~= nil, true, "rogue: the drill session exists")
    eq(u.rogue_session.active, true, "rogue: the run begins immediately")
    eq(F.prints[#F.prints], "Practice mode started. Type /st practice to stop.",
        "rogue: start prints the session notice")
    F.clock = 1.0
    local ok, err = pcall(drive, b, 0.1)
    check(ok, "rogue: the drill tick drives without error (" .. tostring(err) .. ")")
    eq(tick_calls, 1, "rogue: the tick reaches the class shell")
    check(sync_calls >= 1, "rogue: the swing mirror runs on the tick")
    eq(u.score.attempts, 0, "rogue: the tick alone records no attempt")
    u.cast_key(T, "evisc")
    eq(cast_calls, 1, "rogue: the cast reaches the class shell")
    eq(u.score.attempts, 1, "rogue: the graded cast scores")
    u.stop(T)
    eq(u.active, false, "rogue: stop ends the session")
    eq(end_calls, 1, "rogue: the class run ends")
    eq(T.gcd.duration, 1.5, "rogue H2: the live GCD is untouched by the drill")
    eq(T.gcd.spell_length, 1.5, "rogue H2: the spell length is untouched too")
    eq(F.gcd_changes, 0, "rogue H2: no GCD length change fires")
    eq(F.aura_change, 0, "rogue H2: no aura restore runs for the drill")
    eq(T.mainhand.is_full, true, "rogue H2: the bar goes to its idle full look")
    eq(F.last_visibility_hand, "mainhand", "rogue H2: the bar-visibility rule runs")

    -- H1: a throwing rogue tick is isolated (counted once per throw, session
    -- alive, scoring frozen) and quarantines after 25. The tick side is pinned
    -- first so its first-throw notice is exact; the cast side follows on the
    -- same site (no second chat line).
    u.start(T)
    local real_tick = T.ROGUE.tick_practice_session
    T.ROGUE.tick_practice_session = function() error("rogue tick probe") end
    local prints_before = #F.prints
    F.clock = 2.0
    local ok2, err2 = pcall(drive, b, 0.1)
    check(ok2, "rogue H1: a throwing tick does not break the driver (" .. tostring(err2) .. ")")
    eq(T.bar_hook_errors.by_site["practice:tick"], 1, "rogue H1: the throw is counted")
    eq(#F.prints, prints_before + 1, "rogue H1: the first throw prints once")
    eq(u.active, true, "rogue H1: the session survives the throw")
    eq(u.score.attempts, 0, "rogue H1: the failed tick records nothing")
    local real_cast = T.ROGUE.practice_cast
    T.ROGUE.practice_cast = function() error("rogue cast probe") end
    local casts_before = cast_calls
    u.cast_key(T, "evisc")
    eq(T.bar_hook_errors.by_site["practice:tick"], 2, "rogue H1: the throwing cast is counted")
    eq(cast_calls, casts_before, "rogue H1: the failed cast records nothing more")
    eq(#F.prints, prints_before + 1, "rogue H1: repeated throws do not spam chat")
    T.ROGUE.practice_cast = real_cast
    for _ = 3, 25 do
        F.clock = F.clock + 0.1
        drive(b, 0.1)
    end
    eq(T.bar_hook_errors.by_site["practice:tick"], 25, "rogue H1: the site reaches the quarantine threshold")
    eq(T.bar_hook_errors.quarantined["practice:tick"], true, "rogue H1: the site quarantines")
    local frozen = tick_calls
    F.clock = F.clock + 0.1
    drive(b, 0.1)
    eq(tick_calls, frozen, "rogue H1: a quarantined tick is not computed again")
    T.ROGUE.tick_practice_session = real_tick
    u.stop(T)

    -- H4: a drifted rogue key fails closed (no paladin sim on the wrong class).
    T.ROGUE.practice_scenario_key = function() return "renamed_key" end
    local prints_drift = #F.prints
    u.start(T)
    check(u.active ~= true, "rogue H4: a drifted key starts no session")
    eq(F.prints[#F.prints], "Practice mode is not available (rogue drill key drifted).", "rogue H4: the drift prints unavailability")
    eq(#F.prints, prints_drift + 1, "rogue H4: the drift prints exactly once")
    T.ROGUE.practice_scenario_key = function() return "rogue_energy_pool" end
end

do
    -- Hunter drill UI session (mirrors the rogue template above).
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.player_class = "HUNTER"
T.active_class = "HUNTER"
    local tick_calls, cast_calls, end_calls = 0, 0, 0
    T.HUNTER = {
        get_practice_scenario_key = function() return "hunter_forced_move" end,
        PRACTICE_SHOT_ORDER = { "steady" },
        practice_shot_label = function(key)
            if key == "steady" then return "Steady Shot" end
            return nil
        end,
        practice_shot_spell_id = function(key)
            if key == "steady" then return 49001 end
            return nil
        end,
        practice_new_session = function(now, opts) return { active = false } end,
        practice_begin_session = function(session, now) session.active = true return true end,
        practice_tick = function(session, now, elapsed, out)
            tick_calls = tick_calls + 1
            return out or {}
        end,
        practice_cast = function(session, now, key)
            cast_calls = cast_calls + 1
            return "A"
        end,
        practice_status = function(session, now) return "Windows clear - cast freely" end,
        practice_fight_elapsed = function(session, now) return 0 end,
        practice_shift_pause = function(session, shift) end,
        practice_end_session = function(session, now)
            end_calls = end_calls + 1
            session.active = false
        end,
    }
    T.HUNTER.practice_panel = fixture_panel(b, T, "HUNTER")
    u.init(T)
    eq(count_keys(u.panel.ability_icons), 1, "hunter: the panel shows the shot order")
    eq(u.panel.title.text, "|cFFFF8800Forced-Move Practice|r", "hunter: the drill title ships")
    u.start(T)
    eq(u.active, true, "hunter: start activates the session")
    F.clock = 1.0
    local ok, err = pcall(drive, b, 0.1)
    check(ok, "hunter: the drill tick drives without error (" .. tostring(err) .. ")")
    eq(tick_calls, 1, "hunter: the tick reaches the class shell")
    u.cast_key(T, "steady")
    eq(cast_calls, 1, "hunter: the cast reaches the class shell")
    eq(u.score.attempts, 1, "hunter: the graded shot scores")
    -- H1: a throwing hunter cast is isolated (counted, session alive).
    local real_cast = T.HUNTER.practice_cast
    T.HUNTER.practice_cast = function() error("hunter cast probe") end
    local counted = T.bar_hook_errors and T.bar_hook_errors.count or 0
    u.cast_key(T, "steady")
    eq(T.bar_hook_errors.count, counted + 1, "hunter H1: the throwing cast is counted")
    eq(u.score.attempts, 1, "hunter H1: the failed cast records nothing more")
    T.HUNTER.practice_cast = real_cast
    u.stop(T)
    eq(end_calls, 1, "hunter: the class run ends")
    eq(T.gcd.duration, 1.5, "hunter H2: the live GCD is untouched by the drill")

    -- H4: drift fails closed.
    T.HUNTER.get_practice_scenario_key = function() return "renamed_key" end
    u.start(T)
    check(u.active ~= true, "hunter H4: a drifted key starts no session")
    T.HUNTER.get_practice_scenario_key = function() return "hunter_forced_move" end
end

do
    -- Shaman drill UI session (mirrors the rogue template; covers M2/G6).
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.player_class = "SHAMAN"
T.active_class = "SHAMAN"
    local tick_calls, cast_calls, sync_calls = 0, 0, 0
    T.SHAMAN = {
        practice_scenario_key = function() return "shaman_weave" end,
        PRACTICE_CAST_ORDER = { "weave_lb", "weave_cl" },
        practice_cast_label = function(key)
            if key == "weave_lb" then return "Lightning Bolt" end
            if key == "weave_cl" then return "Chain Lightning" end
            return nil
        end,
        practice_cast_spell_id = function(key) return 1001 end,
        practice_cast_seconds = function(key) return 1.5 end,
        practice_latency_seconds = function() return 0 end,
        new_practice_session = function(now, opts) return { active = true } end,
        tick_practice_session = function(session, now, elapsed, out)
            tick_calls = tick_calls + 1
            return out or {}
        end,
        practice_cast = function(session, swing, now, key)
            cast_calls = cast_calls + 1
            return "B"
        end,
        practice_begin_session = function(session, now, opts) session.active = true end,
        practice_status = function(swing, now) return "Marker: --" end,
        practice_fight_elapsed = function(session, now) return 0 end,
        end_practice_session = function(session, now) session.active = false end,
        practice_sync = function() sync_calls = sync_calls + 1; return 0 end,
    }
    T.SHAMAN.practice_panel = fixture_panel(b, T, "SHAMAN")
    u.init(T)
    eq(count_keys(u.panel.ability_icons), 2, "shaman: the panel shows the weave casts")
    eq(u.panel.title.text, "|cFFFF8800Weave Practice|r", "shaman: the drill title ships")
    u.start(T)
    eq(u.active, true, "shaman: start activates the session")
    -- M2/G6: the fight button follows the drill run (not the paladin sim).
    eq(u.panel.fight_btn.label.text, "|cFFFF0000Stop Fight|r", "shaman M2: the live fight labels the button Stop Fight")
    F.clock = 1.0
    local ok, err = pcall(drive, b, 0.1)
    check(ok, "shaman: the drill tick drives without error (" .. tostring(err) .. ")")
    eq(tick_calls, 1, "shaman: the tick reaches the class shell")
    check(sync_calls >= 1, "shaman: the swing mirror runs on the tick")
    u.cast_key(T, "weave_lb")
    eq(cast_calls, 1, "shaman: the cast reaches the class shell")
    eq(u.score.attempts, 1, "shaman: the graded weave scores")
    -- H1: a throwing shaman tick is isolated.
    local real_tick = T.SHAMAN.tick_practice_session
    T.SHAMAN.tick_practice_session = function() error("shaman tick probe") end
    local counted = T.bar_hook_errors and T.bar_hook_errors.count or 0
    F.clock = 2.0
    local ok2, err2 = pcall(drive, b, 0.1)
    check(ok2, "shaman H1: a throwing tick does not break the driver (" .. tostring(err2) .. ")")
    eq(T.bar_hook_errors.count, counted + 1, "shaman H1: the throw is counted")
    T.SHAMAN.tick_practice_session = real_tick
    u.stop(T)
    eq(T.gcd.duration, 1.5, "shaman H2: the live GCD is untouched by the drill")
    eq(F.gcd_changes, 0, "shaman H2: no GCD length change fires")

    -- H4: drift fails closed.
    T.SHAMAN.practice_scenario_key = function() return "renamed_key" end
    u.start(T)
    check(u.active ~= true, "shaman H4: a drifted key starts no session")
    T.SHAMAN.practice_scenario_key = function() return "shaman_weave" end
end

do
    -- Druid drill UI session (mirrors the rogue template; covers H5/M3).
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.player_class = "DRUID"
T.active_class = "DRUID"
    local tick_calls, shift_calls, summary_calls, end_calls, sync_calls = 0, 0, 0, 0, 0
    T.DRUID = {
        practice_scenario_key = function() return "druid_powershift" end,
        new_practice_session = function(now, opts) return { active = true, started_at = now } end,
        tick_practice_session = function(session, now, elapsed, out)
            tick_calls = tick_calls + 1
            return out or {}
        end,
        practice_shift = function(session, now)
            shift_calls = shift_calls + 1
            return "S"
        end,
        practice_summary = function(session)
            summary_calls = summary_calls + 1
            return { attempts = 0, score = 0 }
        end,
        end_practice_session = function(session, now)
            end_calls = end_calls + 1
            session.active = false
            return true
        end,
        practice_sync = function() sync_calls = sync_calls + 1; return 0 end,
    }
    T.DRUID.practice_panel = fixture_panel(b, T, "DRUID")
    u.init(T)
    -- H5: the panel shows the single powershift cast (label from the drill def,
    -- never the paladin seal engine).
    eq(count_keys(u.panel.ability_icons), 1, "druid H5: the panel shows one drill cast")
    check(u.panel.ability_icons.shift ~= nil, "druid H5: the shift cast exists")
    eq(u.panel.title.text, "|cFFFF8800Powershift Practice|r", "druid: the drill title ships")
    u.start(T)
    eq(u.active, true, "druid: start activates the session")
    eq(u.druid_session ~= nil, true, "druid: the drill session exists")
    F.clock = 1.0
    local ok, err = pcall(drive, b, 0.1)
    check(ok, "druid: the drill tick drives without error (" .. tostring(err) .. ")")
    eq(tick_calls, 1, "druid: the tick reaches the class shell")
    check(summary_calls >= 1, "druid: the info line reads the class summary")
    u.cast_key(T, "shift")
    eq(shift_calls, 1, "druid: the cast reaches the class shell")
    eq(u.score.attempts, 1, "druid: the graded shift scores")
    -- M3: the keybind capture prompt names the drill cast, not the raw key.
    u.start_key_capture(T, "shift")
    check((u.key_capture_frame.prompt.text or ""):find("Powershift", 1, true) ~= nil,
        "druid M3: the capture prompt labels the shift cast")
    u.cancel_key_capture(T)
    -- H1: a throwing druid tick is isolated.
    local real_tick = T.DRUID.tick_practice_session
    T.DRUID.tick_practice_session = function() error("druid tick probe") end
    local counted = T.bar_hook_errors and T.bar_hook_errors.count or 0
    F.clock = 2.0
    local ok2, err2 = pcall(drive, b, 0.1)
    check(ok2, "druid H1: a throwing tick does not break the driver (" .. tostring(err2) .. ")")
    eq(T.bar_hook_errors.count, counted + 1, "druid H1: the throw is counted")
    T.DRUID.tick_practice_session = real_tick
    u.stop(T)
    eq(end_calls, 1, "druid: the class run ends")
    eq(T.gcd.duration, 1.5, "druid H2: the live GCD is untouched by the drill")
    eq(F.gcd_changes, 0, "druid H2: no GCD length change fires")
    eq(F.aura_change, 0, "druid H2: no aura restore runs for the drill")

    -- H4: drift fails closed.
    T.DRUID.practice_scenario_key = function() return "renamed_key" end
    u.start(T)
    check(u.active ~= true, "druid H4: a drifted key starts no session")
    T.DRUID.practice_scenario_key = function() return "druid_powershift" end
end

do
    -- H3: a paladin sim session with a hollow PALADIN module never throws and
    -- never stamps seal fields (fail-closed bridge).
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.PALADIN = nil
    u.init(T)
    u.start(T)
    eq(u.active, true, "H3: the sim starts without the class module")
    F.clock = 1.0
    local ok, err = pcall(drive, b, 0.1)
    check(ok, "H3: the sim tick mirrors nothing without the module (" .. tostring(err) .. ")")
    u.stop(T)
    eq(u.active, false, "H3: the sim stops without the class module")
end

--=========================================================================================
-- SoD live crash: FontString:SetText(): Font not set (practice_ui.lua
-- build_result_frame). The SoD client throws when SetText runs before any SetFont;
-- the stub above is SoD-faithful (SetText without a font errors, SetFont(nil)
-- latches nothing). The fix sets a real font BEFORE the first SetText at creation,
-- then update_result_font re-applies through the same helper (the single restyle
-- path). The fallback chain is LSM font -> STANDARD_TEXT_FONT -> the classic
-- client font, pcall-guarded so a missing LSM / throwing Fetch / missing STANDARD
-- never throws out of the result build.
--=========================================================================================
do
    -- Strict creation: the fixed build carries a font, so the SoD-faithful SetText
    -- never throws. A font-stripped build_result_frame mutant (no font before
    -- SetText) dies here on init.
    local b = build()
    local ok_init, err_init = pcall(b.st.practice_ui.init, b.ST)
    check(ok_init, "SoD font: init never throws (" .. tostring(err_init) .. ")")
    check(b.st.practice_ui.result_frame ~= nil, "SoD font: the result frame still builds")
    local got = b.st.practice_ui.result_frame and b.st.practice_ui.result_frame.text
        and b.st.practice_ui.result_frame.text:GetFont() or nil
    check(got ~= nil, "SoD font: the result text carries a font after creation")
    local ok_show, err_show = pcall(b.st.practice_ui.show_result, b.ST, "TWIST!")
    check(ok_show, "SoD font: the first paint never throws (" .. tostring(err_show) .. ")")

    -- LSM Fetch nil: the STANDARD fallback carries the row, never throws.
    local n = build()
    n.sb.lsm_font = nil
    local ok_n, err_n = pcall(n.st.practice_ui.init, n.ST)
    check(ok_n, "SoD font: a nil LSM font never throws (" .. tostring(err_n) .. ")")
    local got_n = n.st.practice_ui.result_frame and n.st.practice_ui.result_frame.text
        and n.st.practice_ui.result_frame.text:GetFont() or nil
    eq(got_n, "Fonts\\FRIZQT__.TTF",
        "SoD font: a nil LSM font falls back to STANDARD_TEXT_FONT")

    -- STANDARD missing on the result path: the LSM font still carries the row,
    -- never throws. (Scoped to update_result_font: a full init with a missing
    -- STANDARD trips the panel's direct SetFont(STANDARD_TEXT_FONT) sites, which
    -- are out of scope here -- STANDARD exists on every live client. A client
    -- without the global: hide the leaked real _G value for the update, then
    -- restore it, so the missing-STANDARD path of the result helper is genuinely
    -- exercised.)
    local m = build()
    local ok_mi, err_mi = pcall(m.st.practice_ui.init, m.ST)
    check(ok_mi, "SoD font: init with STANDARD visible never throws (" .. tostring(err_mi) .. ")")
    local saved_std_m = rawget(_G, "STANDARD_TEXT_FONT")
    _G["STANDARD_TEXT_FONT"] = nil
    local ok_m, err_m = pcall(m.st.practice_ui.update_result_font, m.ST)
    _G["STANDARD_TEXT_FONT"] = saved_std_m
    check(ok_m, "SoD font: a missing STANDARD_TEXT_FONT never throws on the result path (" .. tostring(err_m) .. ")")
    local got_m = m.st.practice_ui.result_frame and m.st.practice_ui.result_frame.text
        and m.st.practice_ui.result_frame.text:GetFont() or nil
    check(got_m ~= nil,
        "SoD font: a missing STANDARD still leaves a font latched")
    eq(got_m, "Fonts\\LSM.ttf",
        "SoD font: a missing STANDARD keeps the LSM font")

    -- Both missing on the result path: the literal still carries the row, never
    -- throws.
    local b2 = build()
    local ok_b2i, err_b2i = pcall(b2.st.practice_ui.init, b2.ST)
    check(ok_b2i, "SoD font: init with LSM valid never throws (" .. tostring(err_b2i) .. ")")
    b2.sb.lsm_font = nil
    local saved_std_b2 = rawget(_G, "STANDARD_TEXT_FONT")
    _G["STANDARD_TEXT_FONT"] = nil
    local ok_b2, err_b2 = pcall(b2.st.practice_ui.update_result_font, b2.ST)
    _G["STANDARD_TEXT_FONT"] = saved_std_b2
    check(ok_b2, "SoD font: nil LSM + nil STANDARD never throws on the result path (" .. tostring(err_b2) .. ")")
    local got_b2 = b2.st.practice_ui.result_frame and b2.st.practice_ui.result_frame.text
        and b2.st.practice_ui.result_frame.text:GetFont() or nil
    eq(got_b2, "Fonts\\FRIZQT__.TTF",
        "SoD font: nil LSM + nil STANDARD still latches the literal")

    -- Throwing Fetch: pcall-guarded, falls back, never throws.
    local t = build({ lsm_throw = true })
    local ok_t, err_t = pcall(t.st.practice_ui.init, t.ST)
    check(ok_t, "SoD font: a throwing LSM Fetch never throws (" .. tostring(err_t) .. ")")
    local got_t = t.st.practice_ui.result_frame and t.st.practice_ui.result_frame.text
        and t.st.practice_ui.result_frame.text:GetFont() or nil
    check(got_t ~= nil,
        "SoD font: a throwing Fetch still leaves a font latched")

    -- Missing LSM lib: type-guarded, falls back, never throws.
    local l = build({ no_lsm = true })
    local ok_l, err_l = pcall(l.st.practice_ui.init, l.ST)
    check(ok_l, "SoD font: a missing LSM lib never throws (" .. tostring(err_l) .. ")")
    local got_l = l.st.practice_ui.result_frame and l.st.practice_ui.result_frame.text
        and l.st.practice_ui.result_frame.text:GetFont() or nil
    check(got_l ~= nil,
        "SoD font: a missing LSM lib still leaves a font latched")

    -- Single restyle path: creation fonts through apply_result_font before the first
    -- SetText, and update_result_font re-applies through the same helper.
    local src = read("practice_ui.lua")
    local apos = src:find("apply_result_font(result.text", 1, true)
    local tpos = src:find('result.text:SetText("")', 1, true)
    check(apos ~= nil and tpos ~= nil and apos < tpos,
        "SoD font: creation fonts through apply_result_font before the first SetText")
    check(src:find("apply_result_font(result.text, self)", 1, true) ~= nil,
        "SoD font: update_result_font re-applies through the same helper")
    local setfont_uses = 0
    local from = 1
    while true do
        local at = src:find("pcall(text.SetFont", from, true)
        if not at then break end
        setfont_uses = setfont_uses + 1
        from = at + 1
    end
    eq(setfont_uses, 2, "SoD font: exactly two guarded SetFont sites, both inside apply_result_font")
    check(src:find("result.text:SetFont(", 1, true) == nil,
        "SoD font: no unguarded result SetFont call survives outside pcall")
end

--=========================================================================================
-- SoD font (2): the practice UI's own FontStrings
--
-- The sweep left the panel's own captions with a bare SetFont(STANDARD_TEXT_FONT,
-- ...). Every one of them now goes through the shared chain (utils.lua
-- apply_font: the caller's path -> STANDARD_TEXT_FONT -> the classic client font,
-- every step pcall-guarded, never throwing), so a client without the global still
-- gets a font that exists.
--
-- The sandbox FontString above is SoD-faithful (SetText with no font throws
-- "Font not set"), so a fontless site dies in this suite instead of the client's
-- chat box. The source scan below checks EVERY site the practice UI creates: the
-- font must be applied before the first SetText, matched on the variable
-- expression so a same-named variable in another function cannot satisfy a site.
--=========================================================================================
do
    -- The standard font is the chain's middle step: a distinctive value proves it
    -- carried the captions (and not the classic-client fallback).
    local b = build({ std_font = "Fonts\\STANDARD_TEST.TTF" })
    local u = b.st.practice_ui
    local ok_init, err_init = pcall(u.init, b.ST)
    check(ok_init, "SoD font (2): the practice UI init never throws (" .. tostring(err_init) .. ")")

    -- The panel's own lines: the chain-fonted hint and the font-object lines.
    local hint = u.panel.hint_text
    check(hint ~= nil, "SoD font (2): the panel owns a hint line")
    if hint then
        eq(hint:GetFont(), "Fonts\\STANDARD_TEST.TTF",
            "SoD font (2): the hint line carries the standard font")
    end
    local font_object_lines = {
        { name = "title", fs = u.panel.title },
        { name = "info line", fs = u.panel.info_text },
        { name = "rotation line", fs = u.panel.rotation_text },
        { name = "fight timer", fs = u.panel.fight_timer_text },
        { name = "score line", fs = u.panel.score_text },
        { name = "resource line", fs = u.panel.resource_text },
    }
    for _, line in ipairs(font_object_lines) do
        check(line.fs ~= nil, "SoD font (2): the panel owns a " .. line.name)
        if line.fs then
            check(line.fs:GetFont() ~= nil,
                "SoD font (2): the " .. line.name .. " carries a font")
        end
    end

    -- No STANDARD_TEXT_FONT on the client: the chain's classic-client fallback still
    -- carries the line (the call never throws).
    local f = build({ std_font = false })
    local ok_f, err_f = pcall(f.st.practice_ui.init, f.ST)
    check(ok_f, "SoD font (2): the init without STANDARD_TEXT_FONT never throws (" .. tostring(err_f) .. ")")
    local fallback = f.st.practice_ui.panel.hint_text
    eq(fallback and fallback:GetFont(), "Fonts\\FRIZQT__.TTF",
        "SoD font (2): a missing STANDARD_TEXT_FONT falls back to the classic client font")

    -- The shared chain's own contract (the panel rides on it): the caller's path,
    -- then STANDARD_TEXT_FONT, then the classic client font. A FontString that
    -- refuses a font degrades to the next candidate and never throws.
    local chain = b.st.utils
    check(type(chain) == "table" and type(chain.apply_font) == "function",
        "SoD font (2): the shared font chain is loaded")
    if type(chain) == "table" and type(chain.apply_font) == "function" then
        local refused = { font = nil, calls = {} }
        function refused:SetFont(path, size, flags)
            self.calls[#self.calls + 1] = path
            if path == "Fonts\\REFUSED.TTF" then
                return false
            end
            self.font = { path, size, flags }
            return true
        end
        function refused:GetFont() return self.font and self.font[1] or nil end
        local ok_c, err_c = pcall(chain.apply_font, refused, "Fonts\\REFUSED.TTF", 12, "")
        check(ok_c, "SoD font (2): a refused font never throws out of the chain (" .. tostring(err_c) .. ")")
        eq(refused:GetFont(), "Fonts\\STANDARD_TEST.TTF",
            "SoD font (2): a refused font degrades to STANDARD_TEXT_FONT")

        local bare = { font = nil }
        function bare:SetFont(path, size, flags) self.font = { path, size, flags }; return true end
        function bare:GetFont() return self.font and self.font[1] or nil end
        chain.apply_font(bare, nil, 12, "")
        eq(bare:GetFont(), "Fonts\\STANDARD_TEST.TTF",
            "SoD font (2): a caller without a path gets STANDARD_TEXT_FONT")
    end

    -- The chain without STANDARD_TEXT_FONT still lands the classic client font.
    local g = build({ std_font = false })
    -- The sandbox must be faithful: a build without a standard font really has
    -- none, and the stub does not leak into the process global (a leaked value
    -- would make every "missing STANDARD_TEXT_FONT" check vacuous).
    eq(rawget(g.env, "STANDARD_TEXT_FONT"), nil,
        "SoD font (2): a build without a standard font really has none")
    eq(rawget(_G, "STANDARD_TEXT_FONT"), nil,
        "SoD font (2): the sandbox leaves no STANDARD_TEXT_FONT behind")
    local bare2 = { font = nil }
    function bare2:SetFont(path, size, flags) self.font = { path, size, flags }; return true end
    function bare2:GetFont() return self.font and self.font[1] or nil end
    local ok_g, err_g = pcall(g.st.utils.apply_font, bare2, nil, 12, "")
    check(ok_g, "SoD font (2): the chain without STANDARD_TEXT_FONT never throws (" .. tostring(err_g) .. ")")
    eq(bare2:GetFont(), "Fonts\\FRIZQT__.TTF",
        "SoD font (2): the chain without STANDARD_TEXT_FONT lands the classic client font")

    -- Source: every FontString the practice UI creates is fonted before its first
    -- SetText. The scan is per site and expression-matched.
    local src = read("practice_ui.lua")
    local lines = {}
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end

    -- find_call: the first line in [from, to] where <expr><suffix> appears as a
    -- whole token (a longer path may not end with the same name).
    local function find_call(from, to, expr, suffix)
        for j = from, to do
            local s = 1
            while true do
                local at = lines[j]:find(expr, s, true)
                if not at then break end
                local before = at > 1 and lines[j]:sub(at - 1, at - 1) or " "
                if not before:match("[%w_.]") then
                    if lines[j]:sub(at + #expr, at + #expr + #suffix - 1) == suffix then
                        return j
                    end
                end
                s = at + 1
            end
        end
        return nil
    end

    -- find_helper: the first line in [from, to] where the shared chain takes the
    -- expression as its FontString argument.
    local function find_helper(from, to, expr)
        local names = { "apply_font(", "apply_result_font(" }
        for j = from, to do
            for _, name in ipairs(names) do
                local s = 1
                while true do
                    local at = lines[j]:find(name, s, true)
                    if not at then break end
                    local arg = at + #name
                    if lines[j]:sub(arg, arg + #expr - 1) == expr then
                        local after = lines[j]:sub(arg + #expr, arg + #expr)
                        if after:match("[%s,)]") then
                            return j
                        end
                    end
                    s = at + 1
                end
            end
        end
        return nil
    end

    local sites, fontless, late = 0, 0, 0
    for i = 1, #lines do
        local expr = lines[i]:match("local%s+([%w_]+)%s*=%s*[%w_%.]+:CreateFontString%(")
        if not expr then
            expr = lines[i]:match("([%w_%.]+)%s*=%s*[%w_%.]+:CreateFontString%(")
        end
        if expr then
            sites = sites + 1
            local last = math.min(i + 80, #lines)
            local font_at = find_call(i + 1, last, expr, ":SetFont(")
            local font_obj_at = find_call(i + 1, last, expr, ":SetFontObject(")
            local helper_at = find_helper(i + 1, last, expr)
            if font_obj_at and (not font_at or font_obj_at < font_at) then font_at = font_obj_at end
            if helper_at and (not font_at or helper_at < font_at) then font_at = helper_at end
            local text_at = find_call(i + 1, last, expr, ":SetText(")
            if not font_at then
                fontless = fontless + 1
                check(false, "SoD font (2): " .. expr .. " (line " .. i .. ") is never fonted")
            elseif text_at and font_at > text_at then
                late = late + 1
                check(false, "SoD font (2): " .. expr .. " (line " .. i .. ") is fonted after its first SetText")
            end
        end
    end
    check(sites >= 30, "SoD font (2): the scan found the practice UI's FontString sites (" .. sites .. ")")
    eq(fontless, 0, "SoD font (2): every FontString site carries a font")
    eq(late, 0, "SoD font (2): every FontString is fonted before its first SetText")

    -- No direct SetFont survives: every font goes through the shared chain (or a
    -- font object, which carries a font of its own).
    check(src:find(":SetFont(", 1, true) == nil,
        "SoD font (2): no direct SetFont call survives in practice_ui.lua")
end

--=========================================================================================
-- 12e) Session resource pools: display, rage generation on the drill swing, mana
-- spend/refuse on drill casts, stop lifecycle (sim-resources lane)
--=========================================================================================
do
    -- A fresh session owns no pools and shows no resource line.
    local b = build()
    local u, T = b.st.practice_ui, b.ST
    local pr = b.st.practice
    u.init(T)
    eq(u.rage_pool, nil, "pools: no rage pool after init")
    eq(u.mana_pool, nil, "pools: no mana pool after init")
    eq(u.focus_pool, nil, "pools: no focus pool after init")
    eq(u.panel.resource_text.text, "", "pools: the resource line starts empty")
    eq(u.panel.resource_text.hidden, true, "pools: the resource line starts hidden")
    u.start(T)
    eq(u.panel.resource_text.text, "", "pools: no pool means no resource readout")
    eq(u.panel.resource_text.hidden, true, "pools: no pool keeps the line hidden")
    u.stop(T)

    -- Setters arm pools and paint the line; rage wins the display order.
    local b2 = build()
    local u2, T2 = b2.st.practice_ui, b2.ST
    local pr2 = b2.st.practice
    u2.init(T2)
    u2.start(T2)
    local rp = u2.set_session_rage_pool(T2, {})
    eq(type(rp), "table", "pools: the rage setter returns the pool")
    eq(rp.rage, 0, "pools: the rage pool starts empty")
    eq(rp.max, 100, "pools: the rage pool caps at 100")
    eq(u2.panel.resource_text.text, "Rage: 0/100", "pools: the rage line reads 0/100")
    eq(u2.panel.resource_text.hidden, false, "pools: the rage line shows")
    u2.set_session_mana_pool(T2, 5000)
    eq(u2.panel.resource_text.text, "Rage: 0/100", "pools: rage outranks mana")
    pr2.mana_gain(u2.mana_pool, 2500)
    u2.update_resource_display(T2)
    eq(u2.panel.resource_text.text, "Rage: 0/100", "pools: mana gain does not steal the line")
    u2.set_session_focus_pool(T2, 100)
    eq(u2.panel.resource_text.text, "Rage: 0/100", "pools: rage outranks focus too")
    u2.clear_session_pools(T2)
    eq(u2.rage_pool, nil, "pools: clear drops the rage pool")
    eq(u2.mana_pool, nil, "pools: clear drops the mana pool")
    eq(u2.focus_pool, nil, "pools: clear drops the focus pool")
    eq(u2.panel.resource_text.text, "", "pools: clear empties the line")
    eq(u2.panel.resource_text.hidden, true, "pools: clear hides the line")
    u2.set_session_mana_pool(T2, 5000)
    pr2.mana_gain(u2.mana_pool, 2500)
    u2.update_resource_display(T2)
    eq(u2.panel.resource_text.text, "Mana: 2500/5000", "pools: the mana line shows amount/max")
    u2.clear_session_pools(T2)
    u2.set_session_focus_pool(T2, 100)
    pr2.focus_gain(u2.focus_pool, 60)
    u2.update_resource_display(T2)
    eq(u2.panel.resource_text.text, "Focus: 60/100", "pools: the focus line shows amount/max")
    -- stop() ends the pools with the session.
    u2.stop(T2)
    eq(u2.rage_pool, nil, "pools: stop drops the rage pool")
    eq(u2.mana_pool, nil, "pools: stop drops the mana pool")
    eq(u2.focus_pool, nil, "pools: stop drops the focus pool")
    eq(u2.panel.resource_text.text, "", "pools: stop empties the line")

    -- A twist session (the paladin's own drill - the class that owns it): the
    -- landed drill swing banks rage through the sim formula (white damage +
    -- level are scripted drill inputs here; the class-shell lane owns the live
    -- feed). The pool mechanics are session-level, so the session that runs the
    -- fight is the twist one.
    local w = build()
    local wu, wT, wF = w.st.practice_ui, w.ST, w.sb
    wu.init(wT)
    wu.start(wT)
    eq(wu.active, true, "pools: the twist session starts")
    wu.set_session_rage_pool(wT, { white_damage = 1153, level = 60 })
    eq(wu.rage_pool.rage, 0, "pools: no swing yet, no rage")
    wF.clock = 2.0
    drive(w)
    local banked = wu.rage_pool.rage
    check(type(banked) == "number" and banked > 37 and banked < 38,
        "pools: the landed swing banks ~37.5 rage (1153 * 7.5 / ~230.6)")
    eq(wu.panel.resource_text.text, "Rage: 37/100", "pools: the banked rage paints floored")
    wu.stop(wT)

    -- No drill damage means no generation (unknown-hides): the swing lands
    -- and the pool stays empty.
    local w2 = build()
    local wu2, wT2, wF2 = w2.st.practice_ui, w2.ST, w2.sb
    wu2.init(wT2)
    wu2.start(wT2)
    wu2.set_session_rage_pool(wT2, {})
    wF2.clock = 2.0
    drive(w2)
    eq(wu2.rage_pool.rage, 0, "pools: no drill damage banks nothing")
    eq(wu2.panel.resource_text.text, "Rage: 0/100", "pools: the line still reads the empty pool")
    wu2.stop(wT2)

    -- A huge drill swing caps at the pool max.
    local w3 = build()
    local wu3, wT3, wF3 = w3.st.practice_ui, w3.ST, w3.sb
    wu3.init(wT3)
    wu3.start(wT3)
    wu3.set_session_rage_pool(wT3, { white_damage = 4612, level = 60 })
    wF3.clock = 2.0
    drive(w3)
    eq(wu3.rage_pool.rage, 100, "pools: the banked rage caps at 100")
    eq(wu3.panel.resource_text.text, "Rage: 100/100", "pools: the capped pool paints full")
    wu3.stop(wT3)

    -- Mana spend/refuse on drill casts (paladin shared session, scripted costs).
    local m = build()
    local mu, mT, mF = m.st.practice_ui, m.ST, m.sb
    mu.init(mT)
    mu.start(mT)
    mu.set_session_mana_pool(mT, 100, { soc = 40, sob = 40 })
    pr.mana_gain(mu.mana_pool, 90)
    mu.update_resource_display(mT)
    eq(mu.panel.resource_text.text, "Mana: 90/100", "pools: the funded mana line reads 90")
    mF.clock = 0
    mu.cast_key(mT, "soc")
    eq(mu.mana_pool.mana, 50, "pools: a fired seal spends its cost")
    eq(mu.panel.resource_text.text, "Mana: 50/100", "pools: the spent line repaints")
    mF.clock = 1.2
    mu.cast_key(mT, "sob")
    eq(mu.mana_pool.mana, 10, "pools: the second seal spends again")
    eq(mu.sim.n_active_seals, 1, "pools: recasting the older seal collapses (archive quirk)")
    -- Ten mana cannot cover a 40 seal: the cast refuses, the sim is untouched.
    mF.clock = 2.4
    mu.cast_key(mT, "soc")
    eq(mu.mana_pool.mana, 10, "pools: a refused cast spends nothing")
    eq(mu.sim.n_active_seals, 1, "pools: a refused cast leaves the seals alone")
    eq(mu.result_frame.text.text, "OOM", "pools: a refused cast flashes OOM")
    -- A key with no scripted cost fires free (unknown costs never spend).
    mF.clock = 3.6
    mu.cast_key(mT, "cs")
    eq(mu.mana_pool.mana, 10, "pools: an uncosted cast spends nothing")
    near(mu.sim.cs_cooldown_expires, 9.6, "pools: the uncosted cast still fires")
    mu.stop(mT)
end

--=========================================================================================
-- 21) The progression hook (the gamification spec's step 2): the live session feeds
-- the pure progress/stats modules, the achievements are evaluated, the writes are
-- throttled and the panel's level badge is opt-in.
--=========================================================================================

-- Does any of the collected chat lines contain the given text?
local function printed(sb, text)
    for i = 1, #sb.prints do
        if sb.prints[i]:find(text, 1, true) then
            return true
        end
    end
    return false
end

-- 21a) Without a saved profile the hook is inert: the session still runs and
-- nothing throws.
do
    local b = build()
    local u, T = b.st.practice_ui, b.ST
    u.init(T)
    u.start(T)
    eq(u.progress_profile, nil, "no profile: the hook keeps no state")
    eq(u.progress_session, nil, "no profile: no pure session is opened")
    local ok = pcall(function() u.stop(T) end)
    check(ok, "no profile: the session stops cleanly")
end

-- 21b) The saved blob: the profile key is REPLACED with the migrated blob, and the
-- migrated blob carries both halves.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)
    local blob = F.profile_store.practice
    check(type(blob) == "table", "the profile carries a practice blob")
    eq(blob.schema_version, 1, "the migrated blob is at schema version 1")
    check(type(blob.progress) == "table", "the migrated blob carries the progress half")
    check(type(blob.stats) == "table", "the migrated blob carries the stats half")
    check(type(blob.progress.classes) == "table", "the progress half carries the class scopes")
    check(type(blob.stats.classes) == "table", "the stats half carries the class scopes")
    u.stop(T)
end

-- 21c) A corrupt blob is repaired at load, never thrown, and never wipes a
-- sibling profile key.
do
    local corrupt = fresh_practice_blob()
    corrupt.progress = "junk"
    corrupt.stats = 42
    local b = build({ with_db = true, practice_blob = corrupt })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    F.profile_store.other_key = "keep me"
    u.init(T)
    u.start(T)
    local blob = F.profile_store.practice
    check(type(blob) == "table", "a corrupt blob is repaired into a table")
    check(type(blob.progress) == "table", "the corrupt progress half is repaired")
    check(type(blob.stats) == "table", "the corrupt stats half is repaired")
    eq(F.profile_store.other_key, "keep me", "a sibling profile key is untouched")
    u.stop(T)
end

-- 21d) A blob a NEWER build wrote is never overwritten.
do
    local future = { schema_version = 99, progress = { classes = {} } }
    local b = build({ with_db = true, practice_blob = future })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    u.start(T)
    eq(F.profile_store.practice, future, "a newer blob is left exactly as it was")
    eq(F.practice_writes, 0, "a newer blob is never written over")
    u.stop(T)
    eq(F.practice_writes, 0, "a newer blob is still never written over at session end")
end

-- 21e) A live session feeds the progression: XP, the streak, the mastery window and
-- the lifetime counters. The write count never grows per attempt.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    local writes_after_start = F.practice_writes
    check(writes_after_start >= 1, "the load-time migration replaces the profile key")

    -- One graded twist (an A) through the real engine path.
    twist_attempt(b)
    eq(u.score.attempts, 1, "the engine recorded the attempt")
    local blob = F.profile_store.practice
    local scope = blob.progress.classes.PALADIN
    check(type(scope) == "table", "the class scope exists after the first attempt")
    eq(scope.xp, 80, "an A earns its grade points as XP")
    eq(scope.best_streak, 1, "the streak counts the hit")
    eq(blob.stats.classes.PALADIN.attempts, 1, "the stats side counts the attempt")
    eq(blob.stats.classes.PALADIN.hits, 1, "the stats side counts the hit")
    eq(blob.stats.classes.PALADIN.drills.paladin_twist.attempts, 1,
        "the per-drill table counts the attempt")
    eq(F.practice_writes, writes_after_start, "an attempt that does not level up writes nothing")

    -- A miss breaks the streak and earns nothing.
    F.clock = 3.1
    u.cast_key(T, "sob")
    F.clock = 4.02
    drive(b, 0.01)
    eq(u.score.attempts, 2, "the second attempt is recorded")
    eq(scope.xp, 80, "a miss earns nothing")
    eq(scope.best_streak, 1, "the lifetime best streak survives the miss")
    eq(F.practice_writes, writes_after_start, "a miss writes nothing")

    -- The session end: the run, the time active, the history entry and the streak.
    local blob_before_stop = F.profile_store.practice
    F.clock = 12.5
    u.stop(T)
    blob = F.profile_store.practice
    check(blob ~= blob_before_stop,
        "the session end replaces the profile key instead of editing it in place")
    local stats = blob.stats.classes.PALADIN
    eq(stats.runs, 1, "the session is one completed run")
    eq(stats.time_active_seconds, 12, "the time active is the live session window")
    eq(#stats.history, 1, "the session lands in the bounded history")
    -- The history entry is read defensively: a session that never wrote one must
    -- report a failed check, not abort the suite.
    local entry = stats.history and stats.history[1]
    eq(type(entry) == "table" and entry.attempts or nil, 2, "the history entry carries the attempt count")
    eq(type(entry) == "table" and entry.score or nil, 40, "the history entry carries the session score")
    eq(blob.progress.classes.PALADIN.daily_streak, 1, "the daily streak counts the day")
    eq(blob.progress.global.daily_streak, 1, "the account daily streak counts the day")
    check(F.practice_writes > writes_after_start, "the session end writes the state")
end

-- 21f) The time active counts the live session only: the idle time between two
-- sessions never lands in the total.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    u.record_graded_attempt(T, "A")
    F.clock = 5
    u.stop(T)
    local blob = F.profile_store.practice
    eq(blob.stats.classes.PALADIN.time_active_seconds, 5, "the first session counts five seconds")
    -- The panel idles for an hour; a second session counts only its own window.
    F.clock = 3600
    u.start(T)
    u.record_graded_attempt(T, "A")
    F.clock = 3610
    u.stop(T)
    blob = F.profile_store.practice
    eq(blob.stats.classes.PALADIN.time_active_seconds, 15,
        "the idle hour between the sessions is not counted")
    eq(blob.stats.classes.PALADIN.runs, 2, "both sessions are runs")
end

-- 21g) The daily streak: a missed day freezes it, it never resets.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    u.record_graded_attempt(T, "S")
    F.clock = 1
    u.stop(T)
    eq(F.profile_store.practice.progress.classes.PALADIN.daily_streak, 1, "day one")

    -- A session two days later: the streak freezes (no reset, no increment).
    F.day = "2026-10-21"
    F.clock = 10
    u.start(T)
    u.record_graded_attempt(T, "S")
    F.clock = 11
    u.stop(T)
    eq(F.profile_store.practice.progress.classes.PALADIN.daily_streak, 1,
        "a missed day freezes the streak")

    -- The next consecutive day counts again.
    F.day = "2026-10-22"
    F.clock = 20
    u.start(T)
    u.record_graded_attempt(T, "S")
    F.clock = 21
    u.stop(T)
    eq(F.profile_store.practice.progress.classes.PALADIN.daily_streak, 2,
        "the next consecutive day counts again")
end

-- 21h) The achievements are evaluated at the session end: first_s fires on the first
-- S, and the unlock flag is persisted.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    u.record_graded_attempt(T, "S")
    F.clock = 1
    u.stop(T)
    local scope = F.profile_store.practice.progress.classes.PALADIN
    eq(scope.unlocks.first_s, true, "the first S unlocks first_s")
    eq(scope.unlocks.hundred_attempts, nil, "a single attempt is not a hundred attempts")
    -- The unlock is persisted in the saved blob, not only in memory.
    check(scope.unlocks ~= nil, "the unlock flags are part of the saved blob")
end

-- 21i) The daily per-drill XP cap stops the farming: three A attempts fill the cap
-- (3x the drill's median attempt XP) and the rest earn nothing.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    for _ = 1, 6 do
        u.record_graded_attempt(T, "A")
    end
    local scope = F.profile_store.practice.progress.classes.PALADIN
    eq(scope.xp, 240, "the drill's daily XP is capped at 3x its median attempt XP")
    -- A new calendar day resets the cap.
    F.day = "2026-10-20"
    u.record_graded_attempt(T, "A")
    eq(scope.xp, 320, "a new day resets the daily cap")
    u.stop(T)
end

-- 21j) The writes are throttled: the live session saves at most once every five
-- minutes, and a level-up saves immediately.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    local writes = F.practice_writes
    -- Below the interval: no write.
    F.clock = 299
    u.maybe_persist_progress(T, 299)
    eq(F.practice_writes, writes, "a save before the interval writes nothing")
    -- At the interval: one write.
    F.clock = 300
    u.maybe_persist_progress(T, 300)
    eq(F.practice_writes, writes + 1, "the throttled save fires at the interval")
    -- A level-up saves right away.
    u.record_graded_attempt(T, "A")
    u.record_graded_attempt(T, "A")
    check(F.practice_writes > writes + 1, "a level-up writes immediately")
    u.stop(T)
end

-- 21k) The panel's level badge is opt-in: hidden by default, and it never changes
-- the panel's own layout.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    check(u.badge_frame ~= nil, "the badge frame is built with the panel")
    eq(u.badge_frame.parent, u.panel, "the badge is a child of the panel")
    eq(u.badge_frame.shown, false, "the badge is hidden by default")
    eq(u.panel.height, 370, "the badge adds no height to the panel (it is an overlay)")
    F.clock = 0
    u.start(T)
    eq(u.badge_frame.shown, false, "the badge stays hidden with the toggle off")
    eq(u.badge_enabled, false, "the toggle reads off with no db key")
    -- With the toggle off the progression runs SILENTLY: the data is still
    -- collected and saved, but nothing is printed (no default-visible change).
    u.record_graded_attempt(T, "A", nil)
    u.record_graded_attempt(T, "A", nil)
    check(not printed(F, "Practice level up"),
        "no chat notice fires while the opt-in is off")
    u.stop(T)
end

-- 21l) The badge shows the level, the XP and the session XP once the toggle is on.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_panel_badge = true
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.badge_enabled, true, "the toggle reads on with the db key")
    eq(u.badge_frame.shown, true, "the badge shows when the toggle is on")
    eq(u.badge_frame.level.text, "Lv 1", "the badge starts at level 1")
    eq(u.badge_frame.xp.text, "0/100", "the badge starts with no XP into the level")
    twist_attempt(b)
    eq(u.badge_frame.level.text, "Lv 1", "one A does not level up")
    eq(u.badge_frame.xp.text, "80/100", "the badge shows the XP into the level")
    eq(u.badge_frame.session.text, "+80 XP", "the badge shows the session XP")
    eq(u.badge_frame.bar_fill.width, 56, "the XP bar fills with the XP (80 of 100)")
    -- The second A crosses the level line: the badge follows and the notice fires.
    u.record_graded_attempt(T, "A", nil)
    eq(u.badge_frame.level.text, "Lv 2", "the badge follows the level up")
    check(printed(F, "Practice level up"), "the level-up notice fires")
    u.stop(T)
    eq(u.badge_frame.shown, true, "the badge stays built when the session ends")
end

-- 21m) The toggle is nil-safe: only an explicit true turns the badge on, and the
-- toggle can be flipped live.
do
    local b = build({ with_db = true })
    local u, T = b.st.practice_ui, b.ST
    u.init(T)
    eq(u.badge_is_enabled(T), false, "a missing db key reads off")
    b.sb.class_db.practice_panel_badge = false
    eq(u.badge_is_enabled(T), false, "an explicit false reads off")
    b.sb.class_db.practice_panel_badge = true
    eq(u.badge_is_enabled(T), true, "an explicit true reads on")
    -- The live toggle writes the class table and repaints.
    u.set_badge_enabled(T, false)
    eq(b.sb.class_db.practice_panel_badge, false, "the toggle writes the class table")
    eq(u.badge_frame.shown, false, "the badge hides again")
    u.set_badge_enabled(T, true)
    eq(u.badge_frame.shown, true, "the badge shows again")
end

--=========================================================================================
-- 22) The shared engine: the rotation scenario session and the generic drill list
--=========================================================================================
-- The two new practice modes ride the shipped panel, score and progression hook.
-- The mode comes from the Practice page's select (nil = the shipped class session,
-- so a fresh profile sees exactly the panel it saw before). The class contract is
-- fixed: ST.<CLASS>.practice_scenario_step(self, ctx) and
-- ST.<CLASS>.practice_drills = { { key, label, grade } }.

-- 22a) The default mode is the shipped class session: no scenario, no drill list,
-- no practice row - the panel is byte-identical to the one that shipped.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.active, true, "the default mode starts the shipped class session")
    eq(u.sim.fight_active, true, "the default mode still runs the paladin sim")
    eq(u.scenario_run, nil, "the default mode starts no scenario")
    eq(u.drill_list, nil, "the default mode starts no drill list")
    eq(u.practice_row, nil, "the default mode builds no practice row")
    eq(u.progress_drill_key, "paladin_twist", "the default scope is the class's own drill")
    u.stop(T)
end

-- 22b) The rotation scenario: the class is asked, the cast is compared, the
-- decision is graded, and the graded decision feeds the shared score.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    local asked = {}
    T.PALADIN.practice_scenario_step = function(self, ctx)
        asked[#asked + 1] = ctx
        return { action = "cs", reason = "the seal is up" }
    end
    -- The class owns the name its rotation scenario is graded under (22b2 pins
    -- the resolution; here it is the shipped name).
    T.PALADIN.practice_scenario_key = "paladin_rotation"
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.active, true, "the scenario session starts")
    check(u.scenario_run ~= nil, "the scenario run exists")
    eq(u.scenario_step.expected, "cs", "the class's answer is the open step's expectation")
    eq(u.scenario_step.reason, "the seal is up", "the class's reason rides along")
    eq(#asked, 1, "the class was asked once")
    eq(asked[1].now, 0, "the class receives the injected clock")
    eq(asked[1].last_action, nil, "the first step has no last action")
    check(type(asked[1].resources) == "table" or asked[1].resources == nil,
        "the context carries the resource view (or none)")
    eq(u.practice_row.shown, true, "the practice row shows")
    eq(u.progress_drill_key, "paladin_rotation", "the scenario's id is the progression scope")
    eq(u.practice_row_prompt.text, "next: cs - the seal is up", "the prompt shows the wanted action")
    -- The matching cast is a correct decision.
    u.cast_key(T, "cs")
    eq(u.score.attempts, 1, "the correct decision is one attempt")
    eq(u.score.hits, 1, "the correct decision is a hit")
    eq(u.scenario_run.correct, 1, "the run counts the correct decision")
    eq(u.result_frame.text.text, "CORRECT", "the popup reads CORRECT")
    -- The next step opens on the tick; a different cast is out of order.
    F.clock = 1
    drive(b, 0.05)
    eq(u.scenario_step.expected, "cs", "the next step is open")
    u.cast_key(T, "judge")
    eq(u.score.attempts, 2, "the out-of-order decision is one attempt")
    eq(u.score.hits, 1, "the out-of-order decision is a miss")
    eq(u.scenario_run.mispicks, 1, "the run counts the mis-pick")
    eq(u.result_frame.text.text, "OUT OF ORDER", "the popup reads OUT OF ORDER")
    -- The deadline closes an unacted step as a miss.
    F.clock = 2
    drive(b, 0.05)
    check(u.scenario_step ~= nil, "the third step is open")
    F.clock = 20
    drive(b, 0.05)
    eq(u.scenario_run.misses, 1, "the expired step is a miss")
    eq(u.score.attempts, 3, "the miss is one attempt")
    eq(u.result_frame.text.text, "MISS", "the popup reads MISS")
    u.stop(T)
    eq(u.scenario_run, nil, "stop clears the scenario run")
    eq(u.scenario_step, nil, "stop clears the open step")
    eq(u.practice_row.shown, false, "stop hides the practice row")
end

-- 22c) A class that cannot decide answers nil: the step is UNKNOWN, no attempt is
-- recorded and the action is never called wrong.
-- 22b2) The class owns its scenario id: its own key wins over the engine's
-- fallback table, and the fallback stands when the class names none.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    T.PALADIN.practice_scenario_step = function() return { action = "cs" } end
    T.PALADIN.practice_scenario_key = "custom_rotation_key"
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.progress_drill_key, "custom_rotation_key", "the class's own scenario id is the scope")
    u.stop(T)
end

-- 22b3) The class owns its context and its rotation table: the engine asks the
-- class for both instead of guessing.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    local asked = {}
    T.PALADIN.practice_scenario_step = function(self, ctx)
        asked[#asked + 1] = ctx
        return { action = "cs" }
    end
    T.PALADIN.practice_context = function(self, now, last_action)
        return { now = now, last_action = last_action, resources = { mana = 42 },
                 cooldowns = { cs = 3 }, class_field = "from the class" }
    end
    T.PALADIN.practice_rotation_for = function()
        return { { action = "cs", label = "Crusader Strike" } }
    end
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(asked[1].class_field, "from the class", "the class's own context reaches the step")
    eq(asked[1].resources.mana, 42, "the class's resource view rides along")
    eq(asked[1].cooldowns.cs, 3, "the class's cooldown view rides along")
    eq(asked[1].now, 0, "the engine still injects the clock")
    -- The published rotation names the panel's buttons (with the class's labels).
    local button = u.practice_row_buttons.buttons["cs"]
    check(button ~= nil, "the published rotation's action has a button")
    if button then
        eq(button.label.text, "Crusader Strike", "the button carries the class's own label")
    end
    u.stop(T)
end

do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    T.PALADIN.practice_scenario_step = function() return { action = "cs" } end
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.progress_drill_key, "paladin_rotation",
        "the engine's fallback id stands when the class names none")
    u.stop(T)
end

do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    T.PALADIN.practice_scenario_step = function() return nil end
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.scenario_step.expected, nil, "the unknown step has no expectation")
    u.cast_key(T, "cs")
    eq(u.score.attempts, 0, "the unknown decision records no attempt")
    eq(u.scenario_run.unknown, 1, "the run counts the unknown decision")
    eq(u.scenario_run.mispicks, 0, "the unknown decision is not a mis-pick")
    eq(u.practice_row_status.text, "unknown - the rotation could not decide",
        "the row says the rotation could not decide")
    u.stop(T)
end

-- 22d) The run ends after its decisions and the summary lands in the row.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    T.PALADIN.practice_scenario_step = function() return { action = "cs" } end
    u.init(T)
    F.clock = 0
    u.start(T)
    for i = 1, 10 do
        u.cast_key(T, "cs")
        F.clock = F.clock + 1
        drive(b, 0.05)
        eq(u.scenario_run.steps, i, "the run took its decision " .. i)
    end
    eq(u.scenario_run.steps, 10, "the run took its ten decisions")
    eq(u.scenario_run.finished, true, "the run is finished")
    eq(u.scenario_run.correct, 10, "every decision was correct")
    check(u.practice_row_status.text:find("run S", 1, true) ~= nil,
        "the summary reads the run band")
    u.stop(T)
end

-- 22e) A class that ships no scenario refuses the session LOUDLY - never a silent
-- paladin sim on the wrong class.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.active, nil, "the session does not start")
    eq(u.sim.fight_active, false, "the refusal never falls back to the paladin sim")
    eq(u.scenario_run, nil, "no scenario run exists")
    eq(F.prints[#F.prints], "Practice scenario is not available for this class.",
        "the refusal prints the reason")
    -- The same class with the drill mode selected and no drills: also loud.
    b.sb.class_db.practice_mode = "drills"
    u.start(T)
    eq(u.active, nil, "the drill-list session does not start either")
    eq(F.prints[#F.prints], "Practice drills are not available for this class.",
        "the drill refusal prints the reason")
    -- The shipped class mode still works for the very same class.
    b.sb.class_db.practice_mode = nil
    u.start(T)
    eq(u.active, true, "the shipped class session still starts")
    u.stop(T)
end

-- 22f) The generic drill list: one button per drill, the press grades it, and the
-- progression scope follows the drill.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "drills"
    local seen = {}
    T.PALADIN.practice_drills = {
        { key = "test_timing", label = "Test timing",
          grade = function(self, ctx) seen[#seen + 1] = ctx; return "A" end },
        { key = "test_unknown", label = "Test unknown", grade = function() return nil end },
    }
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.active, true, "the drill-list session starts")
    eq(#u.drill_list, 2, "both drills are listed")
    eq(u.practice_row.shown, true, "the practice row shows")
    local buttons = u.practice_row_buttons.buttons
    check(buttons["test_timing"] ~= nil, "the first drill has a button")
    check(buttons["test_unknown"] ~= nil, "the second drill has a button")
    eq(buttons["test_timing"].label.text, "Test timing", "the button carries the drill's label")
    -- Pressing the gradeable drill grades it.
    buttons["test_timing"]:GetScript("OnClick")()
    eq(u.score.attempts, 1, "the graded drill is one attempt")
    eq(u.score.hits, 1, "the graded drill is a hit")
    eq(u.progress_drill_key, "test_timing", "the progression scope follows the drill")
    eq(seen[1].now, 0, "the grader receives the injected clock")
    -- The ungradeable drill records no attempt (a grade is never invented).
    buttons["test_unknown"]:GetScript("OnClick")()
    eq(u.score.attempts, 1, "the ungradeable drill records no attempt")
    eq(u.progress_drill_key, "test_unknown", "the scope follows the pressed drill")
    u.stop(T)
    eq(u.drill_list, nil, "stop clears the drill list")
    eq(u.practice_row.shown, false, "stop hides the practice row")
end

-- 22g) A class that publishes its own drills never runs the inherited twist
-- session: the warrior's own drill list is its session, its scope is its own
-- drill key (never the shared twist one) and its panel carries no twist sim
-- widgets at all.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.player_class = "WARRIOR"
T.active_class = "WARRIOR"
    T.WARRIOR = {
        practice_drills = {
            { key = "warrior_core_order", label = "Core order", grade = function() return "A" end },
            { key = "warrior_ww_delay", label = "WW delay", grade = function() return "B" end },
        },
    }
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.active, true, "the warrior's own drill session starts")
    check(u.drill_list ~= nil, "the warrior runs its own drill list")
    eq(#u.drill_list, 2, "both of the warrior's drills are listed")
    eq(u.sim.fight_active, false, "the warrior never runs the twist sim")
    eq(u.progress_drill_key, "warrior_core_order", "the scope is the warrior's own drill")
    eq(count_keys(u.panel.ability_icons or {}), 0, "the panel has no twist sim icon grid")
    eq(u.panel.bl_btn, nil, "the panel has no haste buttons")
    eq(u.panel.dst_btn, nil, "the panel has no DST toggle")
    -- The drill presses grade and the scope follows the pressed drill.
    local buttons = u.practice_row_buttons.buttons
    buttons["warrior_ww_delay"]:GetScript("OnClick")()
    eq(u.score.attempts, 1, "the pressed drill is graded")
    eq(u.progress_drill_key, "warrior_ww_delay", "the scope follows the pressed drill")
    u.stop(T)
end

-- 22h) A class with a SHIPPED session of its own keeps that session: the class's
-- own session grades through the class's own drill (one skill, one truth), and
-- the session itself stays reachable. The drill list is the mode="drills" option
-- on top of it, and the built-in key still resolves for the class's own
-- wrappers.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.player_class = "DRUID"
T.active_class = "DRUID"
    T.DRUID = {
        practice_scenario_key = function() return "druid_powershift" end,
        practice_drills = {
            { key = "druid_powershift_rework", label = "The shift rule",
              grade = function() return "A" end },
        },
        new_practice_session = function(now, opts) return { active = true, started_at = now } end,
        tick_practice_session = function(session, now, elapsed, out) return out or {} end,
        practice_shift = function(session, now) return "S" end,
        practice_summary = function(session) return { attempts = 0, score = 0 } end,
        end_practice_session = function(session, now) session.active = false return true end,
    }
    T.DRUID.practice_panel = fixture_panel(b, T, "DRUID")
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.active, true, "the druid's own drill session starts")
    check(u.druid_session ~= nil, "the druid keeps its own session (not the drill list)")
    eq(u.drill_list, nil, "the class session is the drill list's job, not its own")
    eq(u.sim.fight_active, false, "the druid never runs the twist sim")
    -- The drill list is still reachable (the mode="drills" option).
    b.sb.class_db.practice_mode = "drills"
    u.stop(T)
    u.start(T)
    check(u.drill_list ~= nil, "the druid trains its own drill list on demand")
    eq(u.drill_list[1].key, "druid_powershift_rework", "the class list owns the shift rule")
    eq(u.progress_drill_key, "druid_powershift_rework",
        "the scope is the class's own drill, not the built-in one")
    -- The built-in key still resolves (the class's own wrappers keep working).
    local H = b.st.practice.harness
    check(H.get_scenario("druid_powershift") ~= nil, "the built-in key still resolves")
    eq(H.SUPERSEDED_DRILLS.druid_powershift, "druid_powershift_rework",
        "the built-in drill names the class drill that owns the skill")
    u.stop(T)
end

-- 22i) The panel map itself: the warrior names its OWN drill, never the shared
-- twist drill (the operator's correction - the map is a file-local table, so the
-- pin is a source read).
--
-- The three classes whose class wrappers were re-pointed (druid / shaman /
-- warrior) name the drill their session actually runs, so the mastery row, the
-- session and the panel's offered drill are ONE drill (the filed drill-key
-- routing fix - bench/superseded_wrappers_2026-10-19.md §6 item 1).
do
    local ui_src = read("practice_ui.lua")
    local warrior_src = read("classes/warrior.lua")
    local shaman_src = read("classes/shaman.lua")
    local druid_src = read("classes/druid.lua")
    local paladin_src = read("classes/paladin.lua")
    check(warrior_src:find('mode = "warrior_execute_burn"', 1, true) ~= nil,
        "the warrior's own panel facts name the drill its session runs")
    check(shaman_src:find('mode = "shaman_mw_weave"', 1, true) ~= nil,
        "the shaman's own panel facts name the drill its session runs")
    check(druid_src:find('mode = "druid_powershift_rework"', 1, true) ~= nil,
        "the druid's own panel facts name the drill its session runs")
    check(warrior_src:find('mode = "warrior_core_order"', 1, true) == nil,
        "the warrior's own panel facts never name the list's first drill")
    check(shaman_src:find('mode = "shaman_enh_priority"', 1, true) == nil,
        "the shaman's own panel facts never name the list's first drill")
    check(druid_src:find('mode = "druid_finisher_order"', 1, true) == nil,
        "the druid's own panel facts never name the list's first drill")
    check(paladin_src:find('mode = "paladin_twist"', 1, true) ~= nil,
        "the paladin's own panel facts name the twist drill")
    check(ui_src:find('mode = "paladin_twist"', 1, true) == nil,
        "the shared practice module keeps no class-keyed progression map")
    check(ui_src:find('mode = "warrior_execute_burn"', 1, true) == nil,
        "the shared practice module keeps no class drill literal")
end

-- 22i-bis) C7 (class-isolation 2026-10-21): the shared layer keys on the ACTIVE
-- class, never on the class being PLAYED. An explicit non-playing pick (the
-- operator's class_activation option) must drive its own panel and session.
do
    local b = build()
    local u, T = b.st.practice_ui, b.ST
    T.player_class = "WARRIOR"
    T.active_class = "ROGUE"
    T.ROGUE = {
        practice_scenario_key = function() return "rogue_energy_pool" end,
        PRACTICE_CAST_ORDER = { "evisc" },
        practice_cast_label = function(key)
            if key == "evisc" then return "Pool Spend" end
            return nil
        end,
        practice_cast_spell_id = function() return "Eviscerate" end,
        practice_cast_order = function() return { "evisc" } end,
        new_practice_session = function() return { active = false } end,
        new_ss_session = function() return nil end,
        practice_begin_session = function(session) session.active = true return true end,
        tick_practice_session = function(session, now, elapsed, out) return out or {} end,
        practice_cast = function() return "S" end,
        end_practice_session = function(session) session.active = false return true end,
        practice_sync = function() return 0 end,
    }
    T.ROGUE.practice_panel = fixture_panel(b, T, "ROGUE")
    u.init(T)
    eq(u.panel.title.text, "|cFFFF8800Pool Practice|r",
        "C7: the ACTIVATED class's panel ships, not the playing class's")
    check(u.panel.ability_icons.evisc ~= nil, "C7: the ACTIVATED class's icons build")
    u.start(T)
    eq(u.active, true, "C7: the ACTIVATED class's drill session starts")
    check(u.rogue_session ~= nil, "C7: the rogue session owns the run")
    u.stop(T)
    -- The reverse: the same sandbox with the warrior ACTIVE has no rogue drill.
    T.active_class = "WARRIOR"
    u.start(T)
    check(u.active ~= true, "C7: with WARRIOR active the rogue drill does not run")
    check(u.rogue_session == nil, "C7: no rogue session leaks across the switch")
end

-- 22j) The routing fix in behaviour: the class session's progression scope (the
-- mastery row) is the drill the class's own session grades - not the list's
-- first entry.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.player_class = "DRUID"
T.active_class = "DRUID"
    T.DRUID = {
        practice_scenario_key = function() return "druid_powershift" end,
        practice_drills = {
            { key = "druid_finisher_order", label = "Finisher order", grade = function() return "A" end },
            { key = "druid_powershift_rework", label = "The shift rule", grade = function() return "A" end },
        },
        new_practice_session = function(now, opts) return { active = true, started_at = now } end,
        tick_practice_session = function(session, now, elapsed, out) return out or {} end,
        practice_shift = function(session, now) return "S" end,
        practice_summary = function(session) return { attempts = 0, score = 0 } end,
        end_practice_session = function(session, now) session.active = false return true end,
    }
    T.DRUID.practice_panel = fixture_panel(b, T, "DRUID")
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.active, true, "the druid's own drill session starts")
    eq(u.progress_drill_key, "druid_powershift_rework",
        "the mastery row is the drill the class's session runs")
    u.stop(T)
end

-- 22k) HU-8: a hold is a DECISION. The class states it, the prompt shows it, a
-- cast during it is the illegal cast (an attempt, an F) and doing nothing during
-- it is correct - and worth nothing (no attempt, so idling cannot farm points).
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    T.PALADIN.practice_scenario_step = function()
        return { action = nil, hold = true, reason = "pool the resource first" }
    end
    T.PALADIN.practice_scenario_key = "paladin_rotation"
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.scenario_step.hold, true, "the open step is a hold")
    eq(u.scenario_step.expected, nil, "a hold step expects no action")
    eq(u.practice_row_prompt.text, "next: HOLD - pool the resource first",
        "the prompt shows the hold and the class's own reason")
    -- A cast during the hold is the illegal cast: an attempt, a miss, and a clear
    -- message that names the class's reason.
    u.cast_key(T, "cs")
    eq(u.score.attempts, 1, "the illegal cast is one attempt")
    eq(u.score.hits, 0, "the illegal cast is a miss")
    eq(u.scenario_run.illegal_casts, 1, "the run counts the illegal cast")
    eq(u.scenario_run.mispicks, 1, "the illegal cast counts against the run's band")
    eq(u.result_frame.text.text, "ILLEGAL CAST", "the popup reads ILLEGAL CAST")
    check(u.practice_row_status.text:find("pool the resource first", 1, true) ~= nil,
        "the status line carries the class's hold reason")
    check(u.practice_row_status.text:find("illegal cast", 1, true) ~= nil,
        "the status line says the cast was illegal")
    -- The next step is a hold again; letting the window expire is the CORRECT
    -- hold - recorded, but never an attempt (so it awards nothing).
    F.clock = 1
    drive(b, 0.05)
    eq(u.scenario_step.hold, true, "the next step is a hold too")
    F.clock = 20
    drive(b, 0.05)
    eq(u.scenario_run.holds, 1, "the run counts the correct hold")
    eq(u.score.attempts, 1, "the correct hold records no attempt")
    eq(u.score.hits, 0, "the correct hold awards no hit")
    eq(u.result_frame.text.text, "HOLD OK", "the popup reads HOLD OK")
    check(u.practice_row_status.text:find("nothing cast", 1, true) ~= nil,
        "the status line says nothing was cast")
    u.stop(T)
end

-- 22m) The NEUTRAL action: a legitimate action the rotation did not ask for (a
-- heal, a shield, food) is NOT a mis-pick. The popup says NEUTRAL, the run counts
-- it, and it records no attempt (no score, no streak, no XP).
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    T.PALADIN.practice_scenario_step = function()
        return { action = "cs", reason = "strike now" }
    end
    T.PALADIN.practice_scenario_key = "paladin_rotation"
    -- The class publishes its neutral set (the class lane owns the sets).
    T.PALADIN.practice_neutral_actions = { heal = true }
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.scenario_step.expected, "cs", "the open step wants the rotation action")
    eq(type(u.scenario_neutral) == "table" and u.scenario_neutral.heal, true,
        "the session carries the class's neutral set")
    -- The neutral press: a heal the rotation never asks for.
    u.cast_key(T, "heal")
    eq(u.result_frame.text.text, "NEUTRAL", "the popup reads NEUTRAL")
    check(u.practice_row_status.text:find("NEUTRAL", 1, true) ~= nil,
        "the status line says NEUTRAL")
    check(u.practice_row_status.text:find("heal", 1, true) ~= nil,
        "the status line names the neutral action")
    eq(u.score.attempts, 0, "the neutral press records no attempt")
    eq(u.score.hits, 0, "the neutral press awards no hit")
    eq(u.progress_session.attempts, 0, "the neutral press records no progression attempt")
    eq(u.progress_session.xp, 0, "the neutral press awards no XP")
    eq(u.progress_session.streak, 0, "the neutral press does not move the streak")
    eq(u.scenario_run.neutral, 1, "the run counts the neutral press")
    eq(u.scenario_run.mispicks, 0, "the neutral press is not a mis-pick")
    eq(u.scenario_run.correct, 0, "the neutral press is not a correct decision")
    -- The popup is not the miss colour: a neutral action is no mistake.
    eq(u.result_frame.text.color[1], b.sb.class_db.practice_result_color_hit[1],
        "the neutral popup is not the miss colour")
    u.stop(T)
end

-- 22n) A class that publishes NO neutral set keeps today's behaviour: the same
-- press is a mis-pick (an attempt, an F) and the run counts no neutral step.
--
-- The NO DEFAULT-VISIBLE CHANGE half: the neutral counter rides along only when it
-- matters, so a run of a class with no published set reads exactly as before - the
-- run summary and the panel readout name NO neutral at all (not "0 neutrals"). The
-- positive half lives in 22o (a class WITH a published set reports its count).
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    T.PALADIN.practice_scenario_step = function()
        return { action = "cs", reason = "strike now" }
    end
    T.PALADIN.practice_scenario_key = "paladin_rotation"
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.scenario_neutral, nil, "a class with no published set has no neutral set")
    -- One step only: the run ends on the mis-pick, so the summary is written.
    u.scenario_run.max_steps = 1
    u.cast_key(T, "heal")
    eq(u.result_frame.text.text, "OUT OF ORDER",
        "without a published set the press is a mis-pick")
    eq(u.score.attempts, 1, "the mis-pick is one attempt")
    eq(u.score.hits, 0, "the mis-pick is a miss")
    eq(u.progress_session.attempts, 1, "the mis-pick records a progression attempt")
    eq(u.scenario_run.mispicks, 1, "the run counts the mis-pick")
    eq(u.scenario_run.neutral, 0, "the run counts no neutral press")
    F.clock = 0.5
    drive(b, 0.05)
    check(u.scenario_summary ~= nil, "the run summary was written")
    check(u.practice_row_status.text:find("neutral", 1, true) == nil,
        "the run summary of a class with no published set names no neutral")
    check(u.panel.info_text.text:find("neutral", 1, true) == nil,
        "the panel readout of a class with no published set names no neutral")
    u.stop(T)
end

-- 22o) The rotation action is unaffected and the run summary reports the neutral
-- count (the row's summary line and the panel's readout).
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    T.PALADIN.practice_scenario_step = function()
        return { action = "cs", reason = "strike now" }
    end
    T.PALADIN.practice_scenario_key = "paladin_rotation"
    T.PALADIN.practice_neutral_actions = { heal = true }
    u.init(T)
    F.clock = 0
    u.start(T)
    -- The rotation action itself still grades normally.
    u.cast_key(T, "cs")
    eq(u.result_frame.text.text, "CORRECT", "the rotation action still reads CORRECT")
    eq(u.score.attempts, 1, "the rotation action is one attempt")
    eq(u.score.hits, 1, "the rotation action is a hit")
    eq(u.progress_session.streak, 1, "the rotation action moves the streak")
    eq(u.scenario_run.correct, 1, "the run counts the correct decision")
    -- The next step: a neutral press, then the run ends and the summary reports.
    F.clock = 0.5
    drive(b, 0.05)
    eq(u.scenario_step.expected, "cs", "the next step is open")
    u.scenario_run.max_steps = 2
    u.cast_key(T, "heal")
    eq(u.scenario_run.neutral, 1, "the run counts the neutral press")
    eq(u.score.attempts, 1, "the neutral press adds no attempt")
    F.clock = 1
    drive(b, 0.05)
    check(u.practice_row_status.text:find("neutral", 1, true) ~= nil,
        "the run summary reports the neutral count")
    check(u.panel.info_text.text:find("neutral 1", 1, true) ~= nil,
        "the panel readout reports the neutral count")
    u.stop(T)
end

-- 22l) The live pull clock rides the context: the prepull rule and the prepull
-- drills read the same moment the live guide reads (BS-8 item 2). A context that
-- already carries its own pull clock keeps it.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    local asked = {}
    T.PALADIN.practice_scenario_step = function(self, ctx)
        asked[#asked + 1] = ctx
        return { action = "cs" }
    end
    T.PALADIN.practice_scenario_key = "paladin_rotation"
    -- The live clock on the addon object (main.lua's ST.pull_at).
    T.pull_at = 30
    function T:pull_in_seconds(now) return self.pull_at - (now or 0) end
    u.init(T)
    F.clock = 10
    u.start(T)
    eq(asked[1].pull_at, 30, "the context carries the pull timestamp")
    eq(asked[1].pull_in_seconds, 20, "the context carries the countdown")
    u.stop(T)
    -- A context that already knows its pull keeps it (the live clock never
    -- overwrites a caller that knows better).
    local b2 = build({ with_db = true })
    local u2, T2 = b2.st.practice_ui, b2.ST
    b2.sb.class_db.practice_mode = "scenario"
    local asked2 = {}
    T2.PALADIN.practice_scenario_step = function(self, ctx)
        asked2[#asked2 + 1] = ctx
        return { action = "cs" }
    end
    T2.PALADIN.practice_context = function(self, now, last_action)
        return { now = now, last_action = last_action, pull_at = 99, pull_in_seconds = 5 }
    end
    T2.pull_at = 30
    function T2:pull_in_seconds(now) return self.pull_at - (now or 0) end
    u2.init(T2)
    b2.sb.clock = 0
    u2.start(T2)
    eq(asked2[1].pull_at, 99, "the class's own pull clock wins")
    eq(asked2[1].pull_in_seconds, 5, "the class's own countdown wins")
    u2.stop(T2)
    -- A class that owns its context but carries no pull clock still gets the live
    -- one (the engine's own context path publishes it too).
    local b3 = build({ with_db = true })
    local u3, T3 = b3.st.practice_ui, b3.ST
    b3.sb.class_db.practice_mode = "scenario"
    local asked3 = {}
    T3.PALADIN.practice_scenario_step = function(self, ctx)
        asked3[#asked3 + 1] = ctx
        return { action = "cs" }
    end
    T3.PALADIN.practice_context = function(self, now, last_action)
        return { now = now, last_action = last_action, resources = {}, cooldowns = {} }
    end
    T3.pull_at = 30
    function T3:pull_in_seconds(now) return self.pull_at - (now or 0) end
    u3.init(T3)
    b3.sb.clock = 10
    u3.start(T3)
    eq(asked3[1].pull_at, 30, "the class's own context carries the live pull clock")
    eq(asked3[1].pull_in_seconds, 20, "the class's own context carries the countdown")
    u3.stop(T3)
end

--=========================================================================================
-- 23) The default scenario ctx: a class with NO own practice_context
--
-- The engine's fallback ctx builder lifts the class's gathered guide inputs into
-- ctx.resources / ctx.cooldowns. It used to read SCENARIO_RESOURCE_KEYS - a constant
-- that was defined NOWHERE in the tree - so the first scenario step of every class
-- that does not publish its own practice_context (druid, warrior, shaman) raised and
-- the session never opened. The pool contract is now verified against the six
-- classes' gather_guide_inputs, and the path cannot raise again.
--=========================================================================================
do
    local b = build({ with_db = true })
    local u, T = b.st.practice_ui, b.ST
    b.sb.class_db.practice_mode = "scenario"
    T.player_class = "WARRIOR"
T.active_class = "WARRIOR"
    local asked = {}
    T.WARRIOR = {
        -- The warrior's own gather shape (classes/warrior.lua): the pool reading plus
        -- the state beside it. No practice_context: the engine's fallback owns the
        -- ctx, exactly like the druid, the warrior and the shaman in production.
        gather_guide_inputs = function(_self, out)
            out.speed = 2.6
            out.rage = 42
            out.hs_queued = true
            out.hs_remaining = 3.5
            out.target_health_pct = 55
            return out
        end,
        practice_scenario_step = function(_self, ctx)
            asked[#asked + 1] = ctx
            return { action = "hs", reason = "the pool is banked" }
        end,
        practice_scenario_key = "warrior_rotation",
    }
    u.init(T)
    b.sb.clock = 0
    local ok, err = pcall(u.start, T)
    check(ok, "the default ctx path does not raise (" .. tostring(err) .. ")")
    eq(#asked, 1, "the class without its own ctx is asked (the fallback ran)")
    local ctx = asked[1]
    check(type(ctx) == "table", "the fallback built a context")
    eq(ctx.now, 0, "the fallback ctx carries the injected clock")
    eq(ctx.last_action, nil, "the first step has no last action")
    check(type(ctx.resources) == "table", "the fallback ctx carries the resource view")
    eq(ctx.resources.rage, 42, "the class's pool reading reaches the ctx")
    eq(ctx.resources.hs_queued, true, "the class's state flag reaches the ctx")
    eq(ctx.resources.target_health_pct, 55, "the class's state reading reaches the ctx")
    check(type(ctx.cooldowns) == "table", "the fallback ctx carries the cooldown view")
    eq(ctx.cooldowns.hs, 3.5, "the remaining cooldown lands in the cooldown table")
    u.stop(T)
end

-- 23b) The undefined-constant crash cannot come back: the resource-field list is a
-- LOCAL definition in the module (never a global read), and it is defined before the
-- code that reads it. A mutant that drops the definition breaks the module load (a
-- failed check), never a silent global read.
do
    local src = read("practice_ui.lua")
    local def = src:find("local SCENARIO_RESOURCE_KEYS = {", 1, true)
    local use = src:find("#SCENARIO_RESOURCE_KEYS", 1, true)
    check(def ~= nil, "the resource-field list is defined in the module")
    check(use ~= nil, "the resource-field list is read")
    check(def ~= nil and use ~= nil and def < use,
        "the resource-field list is defined before the code that reads it")
end

-- 23c) F10: the practice tick's isolation is the shared guard (one implementation).
-- The start path's refusal flavour is the same contract (count + print every time);
-- the tick path's flavour is count + report once + quarantine.
do
    local src = read("practice_ui.lua")
    check(src:find("st.guard.note", 1, true) ~= nil,
        "the practice tick reports its failure to the shared guard")
    check(src:find("st.guard.refusal", 1, true) ~= nil,
        "the practice start refusal reports to the shared guard")
    check(src:find("st.guard.quarantined", 1, true) ~= nil,
        "the practice quarantine gate reads the shared guard")
    check(src:find("QUARANTINE_THROWS = ", 1, true) == nil,
        "the practice module keeps no second quarantine threshold")
    check(src:find("errors.by_site", 1, true) == nil,
        "the practice module keeps no second counter bookkeeping")
    check(src:find('st.guard.label("practice", "Practice")', 1, true) ~= nil,
        "the practice wording stays at the call site")
end

-- 24) F2: the drill-list panel supplies a PICK. A drill press grades through the
-- class's own grader with the action the player pressed; without a pick the
-- pick-based graders answer nil (UNKNOWN) and the press records nothing.
--
-- The grader below has the REAL class graders' shape (the paladin, the warrior
-- and the druid all read the pick from ctx.last_action and compare it with the
-- rotation's answer): no pick -> nil, so a press that drops the pick is visible
-- here (the suite's old stub graders returned a letter whatever the ctx said,
-- which is why the defect was invisible).
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "drills"
    local seen = {}
    T.PALADIN.practice_rotation_for = function()
        return { { action = "judge", label = "Judgement" } }
    end
    T.PALADIN.practice_drills = {
        { key = "paladin_fcfs_priority", label = "FCFS priority order",
          grade = function(self, ctx)
              seen[#seen + 1] = ctx
              local pick = type(ctx) == "table" and ctx.last_action or nil
              if type(pick) ~= "string" or pick == "" then
                  return nil
              end
              return pick == "judge" and "S" or "F"
          end },
    }
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.active, true, "the drill-list session starts")
    local buttons = u.practice_row_buttons.buttons
    check(buttons["paladin_fcfs_priority"] ~= nil, "the drill has a button")
    check(buttons["judge"] ~= nil, "the class's action has a button (the pick)")
    -- The drill press with no pick in hand: the grader cannot judge -> UNKNOWN,
    -- no attempt (a grade is never invented).
    buttons["paladin_fcfs_priority"]:GetScript("OnClick")()
    eq(#seen, 1, "the drill press reached the grader")
    eq(seen[1].last_action, nil, "no pick yet: the drill press carries none")
    eq(u.score.attempts, 0, "the unknown drill records no attempt")
    -- The action press IS the pick: it grades the selected drill with the
    -- pressed action, and the class's own grader judges it.
    buttons["judge"]:GetScript("OnClick")()
    eq(#seen, 2, "the action press reached the grader")
    eq(seen[2].last_action, "judge", "the grader received the pressed action as the pick")
    eq(u.score.attempts, 1, "the graded drill is one attempt")
    eq(u.score.hits, 1, "the graded drill is a hit")
    eq(u.progress_drill_key, "paladin_fcfs_priority", "the scope follows the drill")
    -- The pick stays for the next drill press.
    buttons["paladin_fcfs_priority"]:GetScript("OnClick")()
    eq(#seen, 3, "the drill press reached the grader again")
    eq(seen[3].last_action, "judge", "the drill press carries the pick in hand")
    eq(u.score.attempts, 2, "the drill press with a pick grades the drill")
    u.stop(T)
end

-- 24b) F9: the drill counters hang off the drill-list SESSION (the ctx's session
-- identity and session state), never on the addon object: a band's mis-picks
-- cannot survive into the next session.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "drills"
    local seen = {}
    T.PALADIN.practice_drills = {
        { key = "paladin_fcfs_priority", label = "FCFS priority order",
          grade = function(self, ctx) seen[#seen + 1] = ctx return "A" end },
    }
    u.init(T)
    F.clock = 0
    u.start(T)
    local buttons = u.practice_row_buttons.buttons
    buttons["paladin_fcfs_priority"]:GetScript("OnClick")()
    eq(seen[1].session ~= nil, true, "the drill press carries a session identity")
    eq(seen[1].session, u.drill_list_session, "the identity is the drill-list session's own")
    eq(type(seen[1].state), "table", "the drill press carries the session state")
    eq(seen[1].state, u.drill_list_state, "the state is the drill-list session's own")
    local first_session = seen[1].session
    local first_state = seen[1].state
    -- A new session gets a new identity: the mis-pick window starts over.
    u.stop(T)
    u.start(T)
    local buttons2 = u.practice_row_buttons.buttons
    buttons2["paladin_fcfs_priority"]:GetScript("OnClick")()
    check(seen[2].session ~= first_session, "a new session gets a new drill-counter identity")
    check(seen[2].state ~= first_state, "a new session gets a new drill-counter window")
    u.stop(T)
end

-- 24c) F5: the practice row leaks no frames. The row is rebuilt on every
-- scenario step (open and close) and the buttons are REUSED from the row's own
-- pool, so a long run creates no new frames.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    T.PALADIN.practice_scenario_step = function() return { action = "cs" } end
    T.PALADIN.practice_scenario_key = "paladin_rotation"
    u.init(T)
    F.clock = 0
    u.start(T)
    local frames_after_start = F.created_frames
    -- Twenty steps open and close: the row is rebuilt every time.
    for _ = 1, 20 do
        u.cast_key(T, "cs")
        F.clock = F.clock + 1
        drive(b, 0.05)
    end
    eq(F.created_frames, frames_after_start,
        "twenty scenario steps create no new frame (the row reuses its buttons)")
    check(#u.practice_row_buttons.pool > 0, "the row keeps a button pool")
    u.stop(T)
end

-- 24d) F4: a class with a SHIPPED session of its own keeps that session - the
-- shaman's own weave session, not the drill list (the session grades through the
-- class's own drill, so the skill stays one truth).
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.player_class = "SHAMAN"
T.active_class = "SHAMAN"
    T.SHAMAN = {
        practice_scenario_key = function() return "shaman_weave" end,
        practice_drills = {
            { key = "shaman_mw_weave", label = "The stack decision", grade = function() return "A" end },
        },
        PRACTICE_CAST_ORDER = { "weave_lb" },
        practice_cast_label = function() return "Lightning Bolt" end,
        practice_cast_spell_id = function() return 1001 end,
        practice_cast_seconds = function() return 1.5 end,
        practice_latency_seconds = function() return 0 end,
        new_practice_session = function(now, opts) return { active = true, started_at = now } end,
        tick_practice_session = function(session, now, elapsed, out) return out or {} end,
        practice_cast = function(session, swing, now, key) return "S" end,
        practice_summary = function(session) return { attempts = 0, score = 0 } end,
        end_practice_session = function(session, now) session.active = false return true end,
    }
    T.SHAMAN.practice_panel = fixture_panel(b, T, "SHAMAN")
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.active, true, "the shaman's own session starts")
    check(u.shaman_session ~= nil, "the shaman keeps its own session (not the drill list)")
    eq(u.drill_list, nil, "the class session is the drill list's job, not its own")
    u.stop(T)
end

-- 24e) F4 (the second half): a cast with NO session is LOUD - it prints and it
-- counts. Never a silent no-op (the player clicked a drill icon and nothing
-- happened).
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.player_class = "SHAMAN"
T.active_class = "SHAMAN"
    T.SHAMAN = {
        practice_scenario_key = function() return "shaman_weave" end,
        PRACTICE_CAST_ORDER = { "weave_lb" },
        practice_cast_label = function() return "Lightning Bolt" end,
        practice_cast_spell_id = function() return 1001 end,
        practice_cast_seconds = function() return 1.5 end,
        practice_latency_seconds = function() return 0 end,
        new_practice_session = function(now, opts) return { active = true, started_at = now } end,
        tick_practice_session = function(session, now, elapsed, out) return out or {} end,
        practice_cast = function(session, swing, now, key) return "S" end,
        practice_summary = function(session) return { attempts = 0, score = 0 } end,
        end_practice_session = function(session, now) session.active = false return true end,
    }
    T.SHAMAN.practice_panel = fixture_panel(b, T, "SHAMAN")
    u.init(T)
    F.clock = 0
    u.start(T)
    -- The session is gone (it ended, or it never existed): the cast must say so.
    u.shaman_session = nil
    u.shaman_swing = nil
    local before = #F.prints
    u.cast_key(T, "lb")
    check(#F.prints > before, "the cast with no session prints the refusal")
    local last = F.prints[#F.prints]
    check(tostring(last):find("no drill session", 1, true) ~= nil,
        "the refusal names the reason (got " .. tostring(last) .. ")")
    check(type(T.bar_hook_errors) == "table" and T.bar_hook_errors.count ~= nil
        and T.bar_hook_errors.count > 0, "the refusal is counted")
    u.stop(T)
end

-- 24f) F7: the rotation scenario is gated on a LIVE swing engine. The client
-- that keeps the inert stand-in refuses the session loudly (never ten unknown
-- steps), and the reason names the client.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    T.PALADIN.practice_scenario_step = function() return { action = "cs" } end
    T.PALADIN.practice_scenario_key = "paladin_rotation"
    T.swing_engine = "inert-standin"
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(u.active, nil, "the scenario does not start on a client with no live swing engine")
    eq(u.scenario_run, nil, "no scenario run exists")
    local last = F.prints[#F.prints]
    check(tostring(last):find("not available on this client", 1, true) ~= nil,
        "the refusal says the client cannot run it (got " .. tostring(last) .. ")")
    -- A live engine runs the scenario as before.
    local b2 = build({ with_db = true })
    local u2, T2, F2 = b2.st.practice_ui, b2.ST, b2.sb
    b2.sb.class_db.practice_mode = "scenario"
    T2.PALADIN.practice_scenario_step = function() return { action = "cs" } end
    T2.PALADIN.practice_scenario_key = "paladin_rotation"
    T2.swing_engine = "vendored-lib"
    u2.init(T2)
    F2.clock = 0
    u2.start(T2)
    eq(u2.active, true, "a live swing engine runs the scenario")
    u2.stop(T2)
end

-- 24g) F10: the twist drill is the PALADIN's own. The paladin's drill list leads
-- with it (the flagship practice stays reachable from the paladin's panel) and
-- no other class is offered it.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "drills"
    T.PALADIN.practice_drills = {
        { key = "paladin_fcfs_priority", label = "FCFS priority order", grade = function() return "A" end },
    }
    u.init(T)
    F.clock = 0
    u.start(T)
    local buttons = u.practice_row_buttons.buttons
    check(buttons["paladin_twist"] ~= nil, "the paladin's drill list leads with the twist drill")
    check(buttons["paladin_fcfs_priority"] ~= nil, "the paladin's own drills are listed too")
    -- The twist press starts the twist session (the flagship practice).
    buttons["paladin_twist"]:GetScript("OnClick")()
    eq(u.drill_list, nil, "the twist press leaves the drill-list session")
    eq(u.active, true, "the twist session started")
    eq(u.progress_mode_key, "paladin_twist", "the twist session grades the twist drill")
    u.stop(T)
    -- Another class is never offered the twist drill.
    local b2 = build({ with_db = true })
    local u2, T2 = b2.st.practice_ui, b2.ST
    b2.sb.class_db.practice_mode = "drills"
    T2.player_class = "WARRIOR"
T2.active_class = "WARRIOR"
    T2.WARRIOR = {
        practice_drills = {
            { key = "warrior_core_order", label = "The core rotation", grade = function() return "A" end },
        },
    }
    u2.init(T2)
    b2.sb.clock = 0
    u2.start(T2)
    local buttons2 = u2.practice_row_buttons.buttons
    check(buttons2["paladin_twist"] == nil, "the warrior is never offered the twist drill")
    check(buttons2["warrior_core_order"] ~= nil, "the warrior's own drills are listed")
    u2.stop(T2)
end

-- 25) The practice strip's GEOMETRY (the hunter's full APL spine, 2026-10-20).
-- The strip is the panel's companion row: the prompt line, the button lines and
-- the status line. Four buttons per row, so the hunter's thirteen-row Wrath
-- spine needs FOUR button lines - and the strip has to GROW to carry them
-- (the shipped strip is 74 px, two lines). The panel's height follows the
-- strip's, so a rotation row can never fall out of the panel.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    b.sb.class_db.practice_mode = "scenario"
    -- A thirteen-row spine (the hunter's Wrath spine): every row must be
    -- reachable, so the strip has to carry four button lines.
    local spine = {}
    for i = 1, 13 do
        spine[i] = { action = "a" .. i, label = "Row " .. i }
    end
    T.PALADIN.practice_rotation_for = function() return spine end
    T.PALADIN.practice_scenario_step = function() return { action = "a1" } end
    T.PALADIN.practice_scenario_key = "paladin_rotation"
    u.init(T)
    F.clock = 0
    u.start(T)
    local buttons = u.practice_row_buttons.buttons
    local missing = 0
    for i = 1, 13 do
        if buttons["a" .. i] == nil then missing = missing + 1 end
    end
    eq(missing, 0, "every rotation row gets a button in the strip")
    -- The geometry: the strip's height follows the button lines (the prompt
    -- line, the lines and the status line), so four lines need a taller strip
    -- than the shipped two-line strip.
    local height = u.practice_row_height
    check(type(height) == "number" and height > 74,
        "the strip grows past the shipped 74 px when the spine needs four lines (got "
            .. tostring(height) .. ")")
    check(type(height) == "number" and height >= 30 + 4 * 22,
        "the strip carries four button lines (got " .. tostring(height) .. ")")
    -- The panel follows the strip: the row is never cut off by the panel.
    local panel_height = u.panel.height
    check(type(panel_height) == "number" and panel_height > u.panel_base_height,
        "the panel grows with the strip (got " .. tostring(panel_height) .. ")")
    -- The strip's own geometry constants: four buttons per row.
    local source = read("practice_ui.lua")
    check(source:find("PRACTICE_ROW_ACTION_PER_ROW = 4", 1, true) ~= nil,
        "the strip keeps four action buttons per row")
    u.stop(T)
end

--=========================================================================================
-- 26) The deep audit's practice-persistence findings (H2 / M1 / M4, 2026-10-20)
--=========================================================================================
-- H2: a completed session is silently lost on logout / /reload. The progression
-- session's completion bonus, its daily streak, its run, its time active and its
-- bounded history row were written by ONE caller - the session's stop.
-- M1: a Progress-page reset during a live session dropped every later attempt (the
-- score still moved, but no XP, no mastery, no streak, no stats and no badge).
-- M4: a client without the `date` global froze the daily XP cap forever - the drill
-- awarded 0 XP, silently.

-- 26a) H2: the flush writes the session a logout would otherwise lose, and it does
-- NOT tear the frames down (a logout is not a session end).
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    -- Ten attempts: the completion bonus needs ten (SESSION_BONUS_MIN_ATTEMPTS).
    for _ = 1, 10 do
        u.record_graded_attempt(T, "A")
    end
    local scope = F.profile_store.practice.progress.classes.PALADIN
    eq(scope.xp, 240, "H2: the attempts earn their capped XP before the flush")
    F.clock = 12
    eq(u.flush_progress_session(T), true, "H2: the flush reports that it closed the session")
    local blob = F.profile_store.practice
    scope = blob.progress.classes.PALADIN
    local stats_scope = blob.stats.classes.PALADIN
    check(type(scope) == "table", "H2: the flushed session keeps its class scope")
    check(type(stats_scope) == "table", "H2: the flushed session keeps its stats scope")
    eq(type(scope) == "table" and scope.xp or nil, 265, "H2: the flushed session pays its completion bonus")
    eq(type(scope) == "table" and scope.daily_streak or nil, 1, "H2: the flushed session counts the day (the class streak)")
    eq(type(blob.progress.global) == "table" and blob.progress.global.daily_streak or nil, 1,
        "H2: the flushed session counts the account streak")
    eq(type(stats_scope) == "table" and stats_scope.runs or nil, 1, "H2: the flushed session is a completed run")
    eq(type(stats_scope) == "table" and stats_scope.time_active_seconds or nil, 12,
        "H2: the flushed session counts its time")
    eq(type(stats_scope) == "table" and #stats_scope.history or nil, 1,
        "H2: the flushed session lands in the bounded history")
    -- The frames are NOT torn down: the logout path must not hide anything.
    eq(u.panel.shown, true, "H2: the flush leaves the practice panel alone")
    eq(u.driver.shown, true, "H2: the flush leaves the driver frame alone")
    eq(u.active, true, "H2: the flush does not stop the live session")
    eq(u.progress_session, nil, "H2: the flush closes the progression session")
    -- A second flush (the logout can fire twice) closes nothing.
    eq(u.flush_progress_session(T), false, "H2: a second flush closes nothing")
end

-- 26b) L1 (re-audit 2026-10-20): the panel's hide does NOT end a LIVE run. The
-- flush applies only when the run is actually over; a live run keeps its
-- progression session, so the score and the recording can never diverge.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    u.record_graded_attempt(T, "A")
    F.clock = 5
    local on_hide = u.panel:GetScript("OnHide")
    check(type(on_hide) == "function", "L1: the practice panel carries a hide script")
    local session_before = u.progress_session
    -- The frame stub does not fire OnHide by itself, so the script is called the
    -- way the client calls it.
    if type(on_hide) == "function" then
        on_hide(u.panel)
    end
    local blob = F.profile_store.practice
    local stats_scope = blob.stats.classes.PALADIN
    local scope = blob.progress.classes.PALADIN
    eq(type(stats_scope) == "table" and stats_scope.runs or nil, 0,
        "L1: hiding the panel during a live run writes no run")
    eq(type(scope) == "table" and scope.daily_streak or nil, 0,
        "L1: hiding the panel during a live run moves no streak")
    eq(type(stats_scope) == "table" and stats_scope.time_active_seconds or nil, 0,
        "L1: hiding the panel during a live run records no time")
    check(type(u.progress_session) == "table",
        "L1: the live run keeps its progression session")
    eq(u.progress_session, session_before, "L1: the live session is the same one")
    -- The recording continues: the next graded attempt is still recorded.
    u.record_graded_attempt(T, "A")
    eq(type(u.progress_session) == "table" and u.progress_session.attempts or nil, 2,
        "L1: the recording continues after the hide")
    -- The run's OWN end still writes everything: the flush is the one writer.
    F.clock = 9
    u.stop(T)
    local blob2 = F.profile_store.practice
    local stats_scope2 = blob2.stats.classes.PALADIN
    local scope2 = blob2.progress.classes.PALADIN
    eq(type(stats_scope2) == "table" and stats_scope2.runs or nil, 1,
        "L1: the run's end writes the run")
    eq(type(scope2) == "table" and scope2.daily_streak or nil, 1,
        "L1: the run's end writes the streak")
    eq(type(stats_scope2) == "table" and stats_scope2.time_active_seconds or nil, 9,
        "L1: the run's end writes the time")
end

-- 26c) M1: a reset during a live session does not drop the later attempts. The
-- shipped reset path (practice_progress_ui.lua's perform_reset) drives the hook.
--
-- The badge is OFF here: with the badge off, update_badge returns before it
-- re-creates the profile, so the hook lane's OWN ensure (record_progress_attempt
-- ensures the profile itself) is what keeps the recording alive. With the badge on,
-- the badge's repaint would re-create the profile and hide the defect.
do
    local b = build({ with_db = true, with_progress_ui = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    local pui = b.st.practice_progress_ui
    u.init(T)
    F.clock = 0
    u.start(T)
    u.record_graded_attempt(T, "A")
    eq(F.profile_store.practice.progress.classes.PALADIN.xp, 80, "M1: the first attempt earns its XP")

    -- The Progress page's reset, mid-session.
    eq(pui.perform_reset(T), true, "M1: the shipped reset runs against the live profile")
    -- The live session keeps running, but its progression bookkeeping starts over.
    eq(u.progress_session.xp, 0, "M1: the reset clears the in-flight session's XP")
    eq(u.progress_session.attempts, 0, "M1: the reset clears the in-flight session's attempts")

    -- The next attempt records into the FRESH profile: no silent drop.
    u.record_graded_attempt(T, "A")
    local blob = F.profile_store.practice
    local scope = blob.progress.classes.PALADIN
    local stats_scope = blob.stats.classes.PALADIN
    check(type(scope) == "table", "M1: the attempt after the reset creates the class scope")
    check(type(stats_scope) == "table", "M1: the attempt after the reset creates the stats scope")
    eq(type(scope) == "table" and scope.xp or nil, 80, "M1: the attempt after the reset earns its XP again")
    eq(type(scope) == "table" and scope.best_streak or nil, 1,
        "M1: the attempt after the reset counts the streak")
    eq(type(stats_scope) == "table" and stats_scope.attempts or nil, 1,
        "M1: the attempt after the reset counts the stats")
    u.stop(T)
end

-- 26c-bis) M1: with the badge ON, the badge's "+N XP" must not keep counting the XP
-- the reset just erased.
do
    local b = build({ with_db = true, with_progress_ui = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    local pui = b.st.practice_progress_ui
    -- The badge on, so the "+N XP" line is observable.
    F.class_db.practice_panel_badge = true
    u.init(T)
    F.clock = 0
    u.start(T)
    u.record_graded_attempt(T, "A")
    eq(u.badge_frame.session.text, "+80 XP", "M1: the badge shows the session's XP")
    eq(pui.perform_reset(T), true, "M1: the shipped reset runs against the live profile")
    eq(u.badge_frame.session.text, "", "M1: the reset takes the erased XP off the badge")
    u.record_graded_attempt(T, "A")
    eq(u.badge_frame.session.text, "+80 XP", "M1: the badge shows the post-reset XP only")
    u.stop(T)
end

-- 26d) M4/L6 (progression audit 2026-10-20): a client with NO `date` global has NO
-- day. The numeric clock fallback is gone: it was a UTC day count, a DIFFERENT
-- numbering from the civil "YYYY-MM-DD" form the pure layer's day ordinal is built
-- from, so mixing the two rolled the day over at the wrong hour. One numbering, one
-- source - the calendar, which exists on every shipped client family.
--
-- The consequence is stated, not hidden: with no day the daily cap cannot reset, so
-- the drill earns XP only up to its cap (the notice in 26e names the cause).
do
    local b = build({ with_db = true, no_date = true, clock_epoch = 1790000000 })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    for _ = 1, 6 do
        u.record_graded_attempt(T, "A")
    end
    local scope = F.profile_store.practice.progress.classes.PALADIN
    eq(scope.xp, 240, "M4: a client with no calendar day earns up to its cap")
    -- The clock moves past the day boundary: the day is STILL not there, so the cap
    -- does NOT reset. A UTC day count would have rolled it over at the wrong hour.
    F.epoch = 1790000000 + 86400
    u.record_graded_attempt(T, "A")
    eq(scope.xp, 240, "M4: a client with no calendar has no day, so the cap cannot reset")
    u.stop(T)
end

-- 26e) M4: a client with NEITHER a calendar nor a clock can still freeze the cap -
-- but never SILENTLY. The notice names the cause, and it is printed once.
do
    local b = build({ with_db = true, no_date = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    local prints_before = #F.prints
    for _ = 1, 8 do
        u.record_graded_attempt(T, "A")
    end
    local scope = F.profile_store.practice.progress.classes.PALADIN
    eq(scope.xp, 240, "M4: the cap still bites on a client with no day at all")
    check(#F.prints > prints_before, "M4: the frozen cap prints a notice")
    check((F.prints[#F.prints] or ""):find("no calendar date", 1, true) ~= nil,
        "M4: the notice names the cause")
    local prints_after = #F.prints
    u.record_graded_attempt(T, "A")
    eq(#F.prints, prints_after, "M4: the notice is printed once, not once per attempt")
    u.stop(T)
end

-- 26f) M4: the day is still read the client's way when the client HAS a calendar -
-- the clock fallback never overrides a real date.
do
    local b = build({ with_db = true, clock_epoch = 1790000000 })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    for _ = 1, 6 do
        u.record_graded_attempt(T, "A")
    end
    local scope = F.profile_store.practice.progress.classes.PALADIN
    eq(scope.xp, 240, "M4: the capped drill earns its capped XP")
    -- The scripted calendar day moves, the clock does not: the CALENDAR wins.
    F.day = "2026-10-20"
    u.record_graded_attempt(T, "A")
    eq(scope.xp, 320, "M4: the client's own calendar day resets the cap")
    u.stop(T)
end

-- 26g) L5 (re-audit 2026-10-20): the M4 cap notice can fire AGAIN after a
-- mid-session reset. The notice is per session, and the reset starts a NEW
-- session - without the clear it could fire only once per login and the rest of
-- the session was silent again.
do
    local b = build({ with_db = true, no_date = true, with_progress_ui = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    local pui = b.st.practice_progress_ui
    u.init(T)
    F.clock = 0
    u.start(T)
    for _ = 1, 8 do
        u.record_graded_attempt(T, "A")
    end
    local prints_after_first = #F.prints
    check(prints_after_first > 0, "L5: the frozen cap prints the notice")
    -- The notice is once per session: another attempt prints nothing.
    u.record_graded_attempt(T, "A")
    eq(#F.prints, prints_after_first, "L5: the notice is printed once per session")
    -- The reset starts a NEW session, so the notice can fire again.
    eq(pui.perform_reset(T), true, "L5: the shipped reset runs against the live profile")
    for _ = 1, 8 do
        u.record_graded_attempt(T, "A")
    end
    check(#F.prints > prints_after_first, "L5: the notice fires again after the reset")
    check((F.prints[#F.prints] or ""):find("no calendar date", 1, true) ~= nil,
        "L5: the second notice names the cause")
    u.stop(T)
end

-- 26h) M3 (re-audit 2026-10-20): the completion bonus is a share of what the
-- session EARNED, not of how many attempts it made. A session of misses (ten F
-- grades, zero attempt XP) earns no bonus at all - the old flat +25 for ten
-- attempts was a grind hole, and it sat outside the daily cap.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    for _ = 1, 10 do
        u.record_graded_attempt(T, "F")
    end
    F.clock = 12
    eq(u.flush_progress_session(T), true, "M3: the flush closes the session")
    local blob = F.profile_store.practice
    local scope = blob.progress.classes.PALADIN
    eq(type(scope) == "table" and scope.xp or nil, 0,
        "M3: a session of misses earns no bonus (and no attempt XP)")
    local stats_scope = blob.stats.classes.PALADIN
    eq(type(stats_scope) == "table" and stats_scope.runs or nil, 1,
        "M3: the miss session still counts as a completed run")
end

--=========================================================================================
-- 26i) H2 (progression audit 2026-10-20): the daily cap's swallow is REPORTED.
--
-- The detection was already in record_progress_attempt (a grade that earns points but
-- moves nothing means the cap swallowed the whole award), but the only consumer was
-- the M4 notice, gated on "no calendar day". With a VALID day the swallow was
-- COMPLETELY silent: the badge showed no "+N XP", the XP bar stopped, the level
-- stopped, the score kept counting and the player was told NOTHING - for every
-- player, every day, after ~3 attempts on a drill. The notice is now per DRILL per
-- DAY.
do
    local function cap_notices(prints)
        local n = 0
        for _, line in ipairs(prints) do
            if line:find("XP cap", 1, true) ~= nil then n = n + 1 end
        end
        return n
    end

    local b = build({ with_db = true, clock_epoch = 1790000000 })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(cap_notices(F.prints), 0, "H2: nothing is printed before the cap bites")
    -- Three A grades fill the drill's daily cap (3 x its median attempt XP = 240);
    -- the fourth award is swallowed whole.
    for _ = 1, 6 do
        u.record_graded_attempt(T, "A")
    end
    local scope = F.profile_store.practice.progress.classes.PALADIN
    eq(scope.xp, 240, "H2: the capped drill earns its capped XP")
    eq(cap_notices(F.prints), 1, "H2: the capped drill prints the notice once")
    -- Once per drill per day: another attempt on the same day prints nothing.
    u.record_graded_attempt(T, "A")
    eq(cap_notices(F.prints), 1, "H2: the notice is printed once per drill per day")
    -- The next calendar day resets the cap, and the cap bites again (and the player
    -- is told again).
    F.day = "2026-10-21"
    for _ = 1, 4 do
        u.record_graded_attempt(T, "A")
    end
    eq(cap_notices(F.prints), 2, "H2: the notice fires again on the next day")
    u.stop(T)
end

--=========================================================================================
-- 26j) M1 (progression audit 2026-10-20): a saved blob a NEWER build wrote is
-- protected, but the refusal was SILENT and the logout flush reported success while
-- nothing was written.
--
-- The player keeps practising - the badge climbs, the level moves, the XP accrues -
-- and at the session end nothing is saved and nothing is said. The guard sees no
-- error, so /st diag stays clean. The refusal now prints a notice (once per
-- session) and the flush reports the WRITE, not the close.
do
    local newer = { schema_version = 99, progress = { classes = {} }, stats = {} }
    local b = build({ with_db = true, practice_blob = newer, clock_epoch = 1790000000 })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    check(#F.prints > 0, "M1: the newer blob prints a refusal notice")
    local refused = false
    for _, line in ipairs(F.prints) do
        if line:find("not being saved", 1, true) ~= nil then refused = true end
    end
    check(refused, "M1: the refusal notice names the dead end")
    local prints_after = #F.prints
    u.record_graded_attempt(T, "A")
    eq(#F.prints, prints_after, "M1: the refusal notice is printed once per session")
    eq(F.practice_writes, 0, "M1: the newer blob is never written over")
    -- The flush reports the WRITE: a session whose blob a newer build owns closed
    -- cleanly and reported success while NOTHING was written.
    eq(u.flush_progress_session(T), false, "M1: the flush reports that nothing was written")
    eq(F.practice_writes, 0, "M1: the flush wrote nothing")
    u.stop(T)
end

--=========================================================================================
-- 26k) L2 (progression audit 2026-10-20): the reserved "_unknown" drill bucket is
-- recorded on BOTH sides, so the merged row is coherent (the progress side's
-- attempts next to a real accuracy, not a fabricated 0.0%).
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    -- An attempt with no usable drill id lands in the reserved bucket.
    u.progress_drill_key = nil
    u.record_graded_attempt(T, "A")
    local blob = F.profile_store.practice
    local stats_drills = blob.stats.classes.PALADIN.drills
    local progress_drills = blob.progress.classes.PALADIN.drills
    check(type(stats_drills) == "table" and type(stats_drills._unknown) == "table",
        "L2: the stats side records the reserved bucket")
    eq(type(stats_drills) == "table" and type(stats_drills._unknown) == "table"
        and stats_drills._unknown.attempts or nil, 1,
        "L2: the reserved bucket counts the attempt")
    check(type(progress_drills) == "table" and type(progress_drills._unknown) == "table",
        "L2: the progress side records the reserved bucket")
    u.stop(T)
end

-- The six classes' drill-list pick contract. Each entry names:
--   modules  - the sandbox modules the class needs (its pure guide first, then
--              the class module itself);
--   setup    - the class's live STATE fixture (the paladin's ctx reads the
--              session state for its timing and its cooldowns);
--   gather   - the class's live GATHER fixture (the sandbox has no client);
--   action   - the action key the drill-list row offers AND the rotation's
--              own answer at this fixture (the pick the press carries). A
--              rotation change moves this key - this table is the one place
--              to update, exactly like the other rotation pins in the tree;
--   aliases  - the ctx fields the class's own reader reads, in the class's own
--              order (the "only this alias" case).
--
-- Section 27b reads four more fields off the same table (the guide-vocabulary
-- leg of the action strip):
--   family_id - the client family the 27b pin runs the class on (the compat
--               layer's WOW_PROJECT_ID: 2 = Era, 5 = TBC, 11 = WotLK,
--               18 = Forever). The guide vocabulary is family-scoped, so the
--               pin asks for the family the class's own slot set needs.
--   guide_key - a key of the class's OWN guide slot list that the running
--               family's rotation does NOT rank: the class's own vocabulary,
--               as opposed to the rotation leg.
--   common    - the class's common ability the pin follows (the neutral set's
--               own key: a heal, a potion, food).
--   client_id - the spell id the sandbox's client knows (the client's own rank
--               of that ability - NOT the ladder's first id, so the pin reads
--               the client's answer back).
local PRACTICE_CLASS_SPECS = {
    {
        key = "PALADIN",
        family_id = 2,
        guide_key = "sob",
        common = "food",
        client_id = 10256,
        modules = { "classes/paladin.lua" },
        setup = function(T)
            T.state = {
                swing_ends_at = 2.0,
                gcd_expires = 0.0,
                effective_speed = 2.6,
                effective_gcd = 1.5,
                active_seals = { command = true },
                cs_cooldown_expires = 0,
                judge_cooldown_expires = 0,
                fcfs_mode = T.PALADIN.practice_default_mode(nil, nil),
            }
        end,
        action = "judge",
        aliases = { "last_action" },
    },
    {
        key = "WARRIOR",
        family_id = 18,
        guide_key = "cleave",
        common = "food",
        client_id = 10256,
        modules = { "warrior_guide.lua", "classes/warrior.lua" },
        gather = function(out)
            out.speed = 3.0
            out.swing_remaining = 2.0
            out.gcd_remaining = 0
            out.rage = 50
            out.hs_cost = 15
            out.cleave_cost = 20
            out.target_health_pct = 100
            out.execute_pct = 20
            out.op_remaining = 0
            out.execute_remaining = 0
            out.slam_remaining = 0
            out.hs_remaining = 0
            out.cleave_remaining = 0
            return out
        end,
        action = "hs",
        aliases = { "last_action" },
    },
    {
        key = "DRUID",
        family_id = 2,
        guide_key = "maul",
        common = "healing_touch",
        client_id = 25297,
        modules = { "druid_energy.lua", "druid_guide.lua", "classes/druid.lua" },
        gather = function(out)
            out.speed = 3.0
            out.swing_remaining = 2.0
            out.gcd_remaining = 0
            out.form_index = 3
            out.energy = 60
            out.combo_points = 5
            out.maul_queued = false
            out.maul_cost = 15
            out.insufficient_rage = false
            out.rip_remaining = 8
            out.rake_remaining = 7
            out.mangle_remaining = 6
            out.rip_refresh = 4
            out.rake_refresh = 4
            out.family = "ERA"
            return out
        end,
        action = "shred",
        aliases = { "last_action" },
    },
    {
        key = "ROGUE",
        family_id = 2,
        guide_key = "rupture",
        common = "food",
        client_id = 10256,
        modules = { "rogue_guide.lua", "classes/rogue.lua" },
        gather = function(out)
            out.energy_now = 50
            out.cp = 5
            out.ttd = 30
            out.family = "ERA"
            return out
        end,
        action = "eviscerate",
        aliases = { "action", "pick", "pressed", "last_action" },
    },
    {
        key = "SHAMAN",
        family_id = 2,
        guide_key = "twist",
        common = "healing_potion",
        client_id = 17534,
        modules = { "shaman_guide.lua", "classes/shaman.lua" },
        gather = function(out)
            return out
        end,
        action = "flameshock",
        aliases = { "action", "pick", "pressed", "last_action" },
    },
    {
        key = "HUNTER",
        family_id = 2,
        guide_key = "raptor",
        common = "food",
        client_id = 10256,
        modules = { "hunter_guide.lua", "classes/hunter.lua" },
        gather = function(out)
            out.speed = 3.0
            out.swing_remaining = 2.0
            out.gcd_remaining = 0
            out.target_hp_frac = 1.0
            out.synced_duration = 3.0
            return out
        end,
        action = "silencing_shot",
        aliases = { "pick", "pressed", "action", "last_action" },
    },
}

--=========================================================================================
-- 27) The drill-list pick channel: the CONTRACT, pinned against the REAL graders
--
-- Section 24 pins the plumbing with a HAND-WRITTEN paladin-shaped grader, so the
-- alias block the F2 fix added (ctx.pick / ctx.pressed / ctx.action / ctx.last_action)
-- was never exercised against a reader that reads a DIFFERENT alias: the rogue reads
-- ctx.action FIRST, the shaman accepts action -> pick -> pressed -> choice ->
-- last_action and the hunter reads pick -> pressed -> action -> last_action. The
-- moment a class published its own ctx.action the drill-list pick would have been
-- silently ignored and the press would have graded the wrong thing - with a green
-- suite.
--
-- The pins below drive the CLASS'S OWN grader (the real class module, the real
-- guide, the real alias reader) through the drill-list path. The sandbox has no
-- client, so the class's LIVE GATHER (its data source) is stubbed - the grader
-- under test stays the class's own.
--
-- The class-side contract the graders read is
-- { now, last_action, pick, pressed, action, resources, cooldowns, session,
--   session_id, state }: the drill-list press must deliver the pick in EVERY
--   alias, and each class's own reader must resolve the pick from the ctx shape
--   it actually reads.
--=========================================================================================
do
    -- The pick aliases the ctx can carry: the alias block's four plus the rogue's
    -- and the shaman's "choice" (a reader alias the drill-list press never sets).
    local PICK_ALIASES = { "last_action", "pick", "pressed", "action", "choice" }
    -- A copy of the ctx with every pick alias cleared: the reader under test then
    -- sees only the one alias the case names (or none at all).
    local function without_pick(ctx, keep)
        local out = {}
        for k, v in pairs(ctx) do
            out[k] = v
        end
        for i = 1, #PICK_ALIASES do
            out[PICK_ALIASES[i]] = nil
        end
        if keep ~= nil then
            out[keep] = ctx[keep]
        end
        return out
    end

    for _, spec in ipairs(PRACTICE_CLASS_SPECS) do
        local cls = spec.key
        local b = build({ with_db = true, class_modules = spec.modules })
        local u, T, F = b.st.practice_ui, b.ST, b.sb
        local module = T[cls]
        local ready = type(module) == "table" and type(module.practice_drills) == "table"
            and #module.practice_drills > 0
        check(ready, cls .. ": the real class module loaded (its own drill list is there)")
        if ready then
            T.player_class = cls
T.active_class = cls
            F.class_db.practice_mode = "drills"
            if type(spec.setup) == "function" then
                spec.setup(T)
            end
            if type(spec.gather) == "function" then
                module.gather_guide_inputs = function(_self, out)
                    return spec.gather(out)
                end
            end
            -- The class's REAL grader, wrapped so the ctx it receives is observable.
            -- The wrapper only delegates: the letter is the class's own.
            local real = module.practice_drills[1].grade
            local seen, graded, calls = nil, nil, 0
            module.practice_drills[1].grade = function(self, ctx)
                calls = calls + 1
                seen = ctx
                graded = real(self, ctx)
                return graded
            end
            u.init(T)
            F.clock = 0
            u.start(T)
            check(u.drill_list ~= nil, cls .. ": the drill-list session is the live one")
            local buttons = u.practice_row_buttons and u.practice_row_buttons.buttons or {}
            check(buttons[spec.action] ~= nil,
                cls .. ": the drill-list row offers the class's action (" .. spec.action .. ")")
            -- The press: the action button IS the pick, and the class's own grader
            -- judges it through the drill-list path.
            local before = calls
            local attempts = u.score.attempts
            buttons[spec.action]:GetScript("OnClick")()
            local reached = calls > before
            local ctx = reached and seen or nil
            local grade = reached and graded or nil
            check(reached, cls .. ": the drill-list press reached the class's own grader")
            check(type(grade) == "string" and grade ~= "",
                cls .. ": the class's own grader answered a letter (not UNKNOWN)")
            eq(grade, "S", cls .. ": the pressed action is the rotation's own answer")
            eq(u.score.attempts, attempts + 1,
                cls .. ": the drill-list press recorded a graded attempt")
            if ctx then
                -- The alias-delivery contract: the pick rides in EVERY alias the
                -- class graders read (this is the alias block's own job).
                eq(ctx.last_action, spec.action, cls .. ": the pick rides in ctx.last_action")
                eq(ctx.pick, spec.action, cls .. ": the pick rides in ctx.pick")
                eq(ctx.pressed, spec.action, cls .. ": the pick rides in ctx.pressed")
                eq(ctx.action, spec.action, cls .. ": the pick rides in ctx.action")
                -- Each real alias reader, exercised with the ctx shape it reads: a
                -- ctx that carries ONLY that alias still resolves the pick.
                for i = 1, #spec.aliases do
                    local alias = spec.aliases[i]
                    local only = without_pick(ctx)
                    only[alias] = spec.action
                    local ok_g, g = pcall(real, T, only)
                    check(ok_g, cls .. ": the real grader survives a ctx carrying only "
                        .. alias)
                    check(ok_g and type(g) == "string" and g ~= "",
                        cls .. ": the real grader resolves the pick from a ctx carrying only "
                            .. alias .. " (got " .. tostring(g) .. ")")
                end
                -- Without a pick the same grader cannot judge: the pick is what it
                -- graded (UNKNOWN, never a guess).
                local ok_n, n = pcall(real, T, without_pick(ctx))
                check(ok_n, cls .. ": the real grader survives a ctx with no pick")
                eq(ok_n and n or nil, nil,
                    cls .. ": the real grader answers nil without a pick (UNKNOWN)")
            end
            -- The DRILL press: the pick stays in hand and the class's own grader
            -- judges the drill with it (the panel's own two-step flow).
            local before_drill = calls
            local drill_key = u.drill_list_current
            check(type(drill_key) == "string" and drill_key ~= "",
                cls .. ": the action press selected a drill")
            check(buttons[drill_key] ~= nil,
                cls .. ": the drill-list row offers the class's drill (" .. tostring(drill_key) .. ")")
            buttons[drill_key]:GetScript("OnClick")()
            local drill_reached = calls > before_drill
            local drill_ctx = drill_reached and seen or nil
            local drill_grade = drill_reached and graded or nil
            check(drill_reached, cls .. ": the drill press reached the class's own grader")
            check(type(drill_grade) == "string" and drill_grade ~= "",
                cls .. ": the drill press answered a letter (not UNKNOWN)")
            eq(drill_grade, "S", cls .. ": the drill press graded the pick in hand")
            eq(u.score.attempts, attempts + 2,
                cls .. ": the drill press recorded a graded attempt")
            if drill_ctx then
                eq(drill_ctx.last_action, spec.action,
                    cls .. ": the drill press carries the pick in ctx.last_action")
                eq(drill_ctx.pick, spec.action,
                    cls .. ": the drill press carries the pick in ctx.pick")
                eq(drill_ctx.pressed, spec.action,
                    cls .. ": the drill press carries the pick in ctx.pressed")
                eq(drill_ctx.action, spec.action,
                    cls .. ": the drill press carries the pick in ctx.action")
            end
        end
        u.stop(T)
    end
end

--=========================================================================================
-- 27b) The scenario strip's GUIDE leg: the class's own guide vocabulary and the
-- common abilities the client actually has
--
-- WHY: the action strip has THREE legs (practice_ui.lua's scenario_action_order):
-- the class's published rotation, the class's own GUIDE SLOT list, and the keys the
-- class asked for. The middle leg is where the common abilities live: the class
-- seam (apply_practice_panel_actions) appends them to guide.slots, and the panel
-- reads guide.slots LIVE. Drop that one leg and every neutral/common ability
-- vanishes from the panel - and the suite stays GREEN, because every button key any
-- suite asserted was also a rotation action.
--
-- The pins below drive the REAL class modules (the same sandbox as section 27) and
-- read the panel's own action group:
--
--   (a) the strip carries a guide-slot key the running family's rotation does NOT
--       rank - the class's OWN vocabulary reaches the panel (the guide leg);
--   (b) the strip carries the class's common ability, with the CLIENT'S OWN
--       resolved spell id (the client's own rank, not the ladder's first id);
--   (c) the NEGATIVE half: the same class on a client that knows NONE of the
--       common spells offers NO common button (unknown-hides) - so (b) is not
--       vacuous, and the strip itself is not empty.
--
-- The family is per class (the guide vocabulary is family-scoped): the pin needs a
-- family on which the class's own slot set carries a key its rotation does not rank
-- - the warrior's own vocabulary IS its rotation vocabulary on Era and TBC, so its
-- pin runs on the Forever family, where its slot set carries the Cleave.
--=========================================================================================
do
    for _, spec in ipairs(PRACTICE_CLASS_SPECS) do
        local cls = spec.key
        -- One sandbox, one session: the class's own guide vocabulary BEFORE the
        -- seam widens it, the seam's own result, and the panel's action group.
        local function panel_strip(client_spells)
            local b = build({
                with_db = true,
                class_modules = spec.modules,
                project_id = spec.family_id,
                client_spells = client_spells,
            })
            local u, T, F = b.st.practice_ui, b.ST, b.sb
            local module = T[cls]
            T.player_class = cls
T.active_class = cls
            F.class_db.practice_mode = "scenario"
            if type(spec.setup) == "function" then
                spec.setup(T)
            end
            if type(spec.gather) == "function" then
                module.gather_guide_inputs = function(_self, out)
                    return spec.gather(out)
                end
            end
            -- The class's OWN guide vocabulary, captured before the seam widens it.
            local own = {}
            local guide = module.guide
            if type(guide) == "table" and type(guide.slots) == "table" then
                for i = 1, #guide.slots do
                    local slot = guide.slots[i]
                    if type(slot) == "table" and type(slot.key) == "string" then
                        own[slot.key] = true
                    end
                end
            end
            -- The class seam: the common abilities are appended to guide.slots.
            local seam = false
            if type(module.apply_practice_panel_actions) == "function" then
                seam = module.apply_practice_panel_actions() == true
            end
            -- The id the seam resolved for the common ability (nil when the client
            -- does not have the spell - unknown-hides).
            local resolved = nil
            if type(guide) == "table" and type(guide.slots) == "table" then
                for i = 1, #guide.slots do
                    local slot = guide.slots[i]
                    if type(slot) == "table" and slot.key == spec.common then
                        resolved = slot.spell_id
                    end
                end
            end
            u.init(T)
            F.clock = 0
            u.start(T)
            local buttons = u.practice_row_buttons and u.practice_row_buttons.buttons or {}
            return {
                b = b, u = u, module = module, own = own, seam = seam,
                resolved = resolved, buttons = buttons,
            }
        end

        -- The client knows the common ability's own rank.
        local pos = panel_strip({ spec.client_id })
        -- The client knows NONE of the common spells (the negative half).
        local neg = panel_strip({})

        -- (a) the guide leg: the class's own vocabulary reaches the panel.
        check(pos.own[spec.guide_key] == true,
            cls .. ": the class's own guide vocabulary carries " .. spec.guide_key)
        local rotation = {}
        if type(pos.module.practice_rotation_action_set) == "function" then
            local ok_r, set = pcall(pos.module.practice_rotation_action_set)
            if ok_r and type(set) == "table" then
                rotation = set
            end
        end
        check(rotation[spec.guide_key] ~= true,
            cls .. ": " .. spec.guide_key .. " is not a rotation action (the pin's own premise)")
        check(pos.buttons[spec.guide_key] ~= nil,
            cls .. ": the action strip offers the class's own guide key (" .. spec.guide_key .. ")")
        check(neg.buttons[spec.guide_key] ~= nil,
            cls .. ": the class's own guide key reaches the strip without the client's common spells")

        -- (b) the common ability, with the CLIENT's own resolved id.
        check(pos.seam == true,
            cls .. ": the class seam widened the guide slot list with the common abilities")
        check(pos.buttons[spec.common] ~= nil,
            cls .. ": the action strip offers the common ability (" .. spec.common .. ")")
        eq(pos.resolved, spec.client_id,
            cls .. ": the common ability resolved to the CLIENT's own spell id")
        local button = pos.buttons[spec.common]
        local icon = pos.b.env.GetSpellTexture(spec.client_id)
        check(button ~= nil and button.row_icon ~= nil and button.row_icon.texture == icon,
            cls .. ": the common button carries the client's own icon")

        -- (c) the negative half: a client that knows none of the common spells
        -- offers none of them (unknown-hides).
        check(neg.buttons[spec.common] == nil,
            cls .. ": a client that knows none of the common spells offers no common button")
        local common_keys, leaked = {}, {}
        for i = 1, #(neg.module.practice_common_actions or {}) do
            local action = neg.module.practice_common_actions[i]
            if type(action) == "table" and type(action.key) == "string" then
                common_keys[action.key] = true
            end
        end
        for key in pairs(neg.buttons) do
            if common_keys[key] and not neg.own[key] then
                leaked[#leaked + 1] = key
            end
        end
        table.sort(leaked)
        check(#leaked == 0,
            cls .. ": no common ability reaches the strip on a client that knows none of them" ..
            (#leaked > 0 and (" (leaked: " .. table.concat(leaked, ", ") .. ")") or ""))

        pos.u.stop(pos.b.ST)
        neg.u.stop(neg.b.ST)
    end
end

--=========================================================================================
-- 28) The progression lane's FILED call sites (progression audit 2026-10-20).
--
-- The pure lane fixed the pure modules; the call sites in practice_ui.lua and
-- practice_progress_ui.lua were FILED with the exact diff (bench/progression_fixes_
-- 2026-10-20.md §7.1-§7.5). These are the pins for the five of them:
--   7.1  the ACCOUNT scope is evaluated at the session end (its unlock flags live
--        in progress.global.unlocks, so the class scope alone left every
--        account-scoped achievement locked for good);
--   7.2  the history day is read SIGNED (the NO_DAY sentinel must reach the
--        renderer - see tests/practice_progress_ui_state.lua for the UI half);
--   7.3  ONE day numbering (the civil calendar; the UTC clock fallback is gone);
--   7.4  the grade is validated against the scoring model's set BEFORE the live
--        score counts it (so the score and the progression can never diverge);
--   7.5  the two cap notices describe the SHIPPED cap.
--=========================================================================================

-- 28a) M2: the ACCOUNT scope's achievements evaluate at the session end.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    u.record_graded_attempt(T, "S")
    F.clock = 1
    u.stop(T)
    local blob = F.profile_store.practice
    local class_scope = blob.progress.classes.PALADIN
    local account = blob.progress.global
    eq(type(class_scope) == "table" and class_scope.unlocks
        and class_scope.unlocks.first_s or nil, true,
        "M2: the class scope holds its own flag")
    eq(type(account) == "table" and account.unlocks
        and account.unlocks.first_s or nil, true,
        "M2: the account scope holds its own flag too")
    check(account ~= class_scope, "M2: the account scope is a scope of its own")
    -- The class-scoped flag does not leak into the account scope's map and the
    -- account's does not leak into the class's: the two scopes are separate.
    eq(type(account) == "table" and account.unlocks
        and account.unlocks.hundred_attempts or nil, nil,
        "M2: one attempt is not a hundred attempts (in either scope)")
end

-- 28b) L4: an unknown grade cannot move the live score. The live scoring model
-- counts ANY grade it is handed (points 0, but an attempt and a hit), while the
-- pure modules drop a grade outside the scoring model's set - so the score and
-- the progression used to diverge.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    local attempts = u.score.attempts
    local hits = u.score.hits
    local last_grade = u.score.last_grade
    u.record_graded_attempt(T, "Z")
    eq(u.score.attempts, attempts, "L4: an unknown grade is not an attempt on the live score")
    eq(u.score.hits, hits, "L4: an unknown grade is not a hit on the live score")
    eq(u.score.last_grade, last_grade, "L4: an unknown grade never becomes the last grade")
    -- The two sides count the same attempts.
    u.record_graded_attempt(T, "A")
    local stats = F.profile_store.practice.stats.classes.PALADIN
    eq(u.score.attempts, type(stats) == "table" and stats.attempts or nil,
        "L4: the live score and the progression count the same attempts")
    u.stop(T)
end

-- 28c) L6: ONE day numbering. The day the UI feeds the pure layer is the CIVIL
-- ordinal - the same numbering the pure module builds from the "YYYY-MM-DD" form.
-- The numeric clock fallback (a UTC day count) is a DIFFERENT numbering and is
-- gone: a client with no calendar has NO day.
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    local P = b.st.practice_progress
    u.init(T)
    F.clock = 0
    u.start(T)
    u.record_graded_attempt(T, "A")
    local blob = F.profile_store.practice
    local drill = blob.progress.classes.PALADIN.drills[u.progress_drill_key]
    eq(type(drill) == "table" and drill.daily_day or nil, P.day_ordinal("2026-10-19"),
        "L6: the stored day is the civil ordinal of the calendar day")
    -- A client with no calendar has NO day: the clock is not a second numbering.
    local b2 = build({ with_db = true, no_date = true, clock_epoch = 1790000000 })
    local u2, T2, F2 = b2.st.practice_ui, b2.ST, b2.sb
    u2.init(T2)
    F2.clock = 0
    u2.start(T2)
    u2.record_graded_attempt(T2, "A")
    local drill2 = F2.profile_store.practice.progress.classes.PALADIN.drills[u2.progress_drill_key]
    eq(type(drill2) == "table" and drill2.daily_day or nil, nil,
        "L6: a client with no calendar stores no day at all")
    u2.stop(T2)
end

-- 28d) The two cap notices describe the SHIPPED cap: 3x the drill's median HIT XP
-- (floored by the best hit), not 3x its median attempt XP - and a client with no
-- calendar earns UP TO its cap, not nothing.
do
    local b = build({ with_db = true, clock_epoch = 1790000000 })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    for _ = 1, 6 do
        u.record_graded_attempt(T, "A")
    end
    local cap_line = nil
    for _, line in ipairs(F.prints) do
        if line:find("XP cap", 1, true) ~= nil then cap_line = line end
    end
    check(cap_line ~= nil, "the cap notice: the capped drill prints the notice")
    check(cap_line and cap_line:find("median hit XP", 1, true) ~= nil,
        "the cap notice: it names the cap's own rule (the median HIT XP)")
    check(cap_line and cap_line:find("median attempt XP", 1, true) == nil,
        "the cap notice: it no longer describes the old cap")
    u.stop(T)
end

do
    local b = build({ with_db = true, no_date = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    for _ = 1, 8 do
        u.record_graded_attempt(T, "A")
    end
    local line = F.prints[#F.prints] or ""
    check(line:find("no calendar date", 1, true) ~= nil,
        "the no-calendar notice: it names the cause")
    check(line:find("earns XP only up to its cap", 1, true) ~= nil,
        "the no-calendar notice: it says the drill earns up to its cap")
    check(line:find("earns no XP", 1, true) == nil,
        "the no-calendar notice: it no longer claims the drill earns nothing")
    u.stop(T)
end

--=========================================================================================
-- 29) F1 (drill-pick contract 2026-10-20): the drill-list PRESS is the pick.
--
-- The alias block only filled an EMPTY alias, so a class that published its own
-- pick alias kept it - and the class's own reader, which reads that alias FIRST,
-- graded the class's value instead of the player's press.
--
-- Case A - the HUNTER, reachable today: the class's own ctx publishes ctx.pick =
-- the live cast (the shot that is casting right now) and the hunter's reader reads
-- ctx.pick FIRST. A drill-list press made while a Steady Shot was casting was
-- graded against the live cast, not the player's press (measured: F for a press
-- of the rotation's own answer).
--
-- Case B - the ROGUE/SHAMAN shape (latent today): a class ctx that publishes
-- ctx.action, which the rogue and the shaman read FIRST. The sandbox wraps the
-- class's own ctx builder to publish it; the class file is untouched.
--
-- What must NOT change: the SCENARIO path (the hunter's live cast stays the pick
-- there - a different call site) and the hunter's own drill behaviour (a drill
-- press with NO pick still judges the shot that is in flight).
--=========================================================================================
do
    -- The hunter's fixture: the rotation's own answer at this state is
    -- "silencing_shot" (the fixture section 27 uses) and a Steady Shot is in
    -- flight, so the class's own ctx publishes ctx.pick = "steady".
    local function hunter_fixture(b)
        local u, T, F = b.st.practice_ui, b.ST, b.sb
        local module = T.HUNTER
        T.player_class = "HUNTER"
T.active_class = "HUNTER"
        F.class_db.practice_mode = "drills"
        module.gather_guide_inputs = function(_self, out)
            out.speed = 3.0
            out.swing_remaining = 2.0
            out.gcd_remaining = 0
            out.target_hp_frac = 1.0
            out.synced_duration = 3.0
            out.steady_remaining = 1.0
            return out
        end
        local seen, graded, calls = nil, nil, 0
        local real = module.practice_drills[1].grade
        module.practice_drills[1].grade = function(self, ctx)
            calls = calls + 1
            seen = ctx
            graded = real(self, ctx)
            return graded
        end
        u.init(T)
        F.clock = 0
        u.start(T)
        return {
            ui = u,
            ST = T,
            module = module,
            watch = function()
                return seen, graded, calls
            end,
        }
    end

    -- Case A: the class publishes ctx.pick (the live cast).
    local b = build({ with_db = true, class_modules = { "hunter_guide.lua", "classes/hunter.lua" } })
    local a = hunter_fixture(b)
    local u, T = a.ui, a.ST
    local buttons = u.practice_row_buttons and u.practice_row_buttons.buttons or {}
    check(buttons["silencing_shot"] ~= nil,
        "F1: the drill-list row offers the hunter's action")
    buttons["silencing_shot"]:GetScript("OnClick")()
    local seen, graded, calls = a.watch()
    check(calls > 0, "F1: the drill-list press reached the hunter's own grader")
    eq(type(seen) == "table" and seen.pick or nil, "silencing_shot",
        "F1: the press wins over the class's published pick (ctx.pick)")
    eq(type(seen) == "table" and seen.pressed or nil, "silencing_shot",
        "F1: the press rides in ctx.pressed")
    eq(type(seen) == "table" and seen.action or nil, "silencing_shot",
        "F1: the press rides in ctx.action")
    eq(graded, "S", "F1: the PRESS is graded, not the live cast")
    u.stop(T)

    -- Case B: the class publishes ctx.action (the rogue's and the shaman's
    -- first-read alias) and no ctx.pick.
    local b2 = build({ with_db = true, class_modules = { "hunter_guide.lua", "classes/hunter.lua" } })
    local bb = hunter_fixture(b2)
    local u2, T2, module2 = bb.ui, bb.ST, bb.module
    local own_context = module2.practice_context
    module2.practice_context = function(self, now, last_action)
        local ctx = own_context(self, now, last_action)
        if type(ctx) == "table" then
            ctx.pick = nil
            ctx.action = "steady"
        end
        return ctx
    end
    local buttons2 = u2.practice_row_buttons and u2.practice_row_buttons.buttons or {}
    buttons2["silencing_shot"]:GetScript("OnClick")()
    local seen2, _, calls2 = bb.watch()
    check(calls2 > 0, "F1: the drill-list press reached the class's own grader")
    eq(type(seen2) == "table" and seen2.action or nil, "silencing_shot",
        "F1: the press wins over the class's published ctx.action")
    eq(type(seen2) == "table" and seen2.pick or nil, "silencing_shot",
        "F1: the press rides in ctx.pick as well")
    u2.stop(T2)

    -- Case C: the hunter's own drill behaviour is UNCHANGED - a drill press with NO
    -- pick still judges the shot that is actually in flight.
    local b3 = build({ with_db = true, class_modules = { "hunter_guide.lua", "classes/hunter.lua" } })
    local c = hunter_fixture(b3)
    local u3, T3, module3 = c.ui, c.ST, c.module
    local buttons3 = u3.practice_row_buttons and u3.practice_row_buttons.buttons or {}
    local drill_key = module3.practice_drills[1].key
    check(buttons3[drill_key] ~= nil,
        "F1: the drill-list row offers the hunter's drill (" .. tostring(drill_key) .. ")")
    buttons3[drill_key]:GetScript("OnClick")()
    local seen3, graded3, calls3 = c.watch()
    check(calls3 > 0, "F1: the drill press reached the hunter's own grader")
    eq(type(seen3) == "table" and seen3.pick or nil, "steady",
        "F1: with no press the class's own pick (the live cast) still reaches the grader")
    check(type(graded3) == "string" and graded3 ~= "",
        "F1: a drill press with no pick still judges the live cast (not UNKNOWN)")
    u3.stop(T3)
end

--=========================================================================================
-- 29) The scenario strip's GRADER SEAM: ONE spelling per spell, and a press graded by
-- the spell it represents
--
-- WHY (the deep audit's Issue 1, HIGH): the paladin has TWO key spaces. The rotation
-- and the guide engine say "cons" / "exo" / "hs" / "am" (classes/paladin.lua's
-- PRACTICE_ORDER_TWIST and the FCFS orders); the guide SLOTS say "consecration" /
-- "exorcism" / "holy_shock" / "aura_mastery" (the same file's guide.slots). The
-- action row pushed BOTH vocabularies, so the player got TWO buttons for
-- Consecration - a bare text "cons" and an icon "consecration" - and the grader
-- compared the RAW press with the RAW expectation: pressing the icon button graded
-- OUT OF ORDER (an F, a broken streak and no XP) for the spell the prompt named, on
-- TBC, on Forever, on Wrath and on the four SoD orders.
--
-- The pins below drive the REAL class modules (the same sandbox as section 27) and
-- the panel's own buttons:
--
--   (a) the panel offers ONE button per spell - no two spellings of one spell;
--   (b) the button that carries a spell's icon is the CANONICAL one;
--   (c) the press of the panel's own button for the action the prompt names grades
--       CORRECT (never out_of_order) - for every class and every slice the table
--       names;
--   (d) a press in ANY spelling the class knows grades CORRECT too: the grader
--       compares canonical keys, so the sim's own "consec" and the guide slot's
--       "consecration" are the spell the rotation calls "cons";
--   (e) the drill-list path normalises the pick the same way.
--
-- The class's own ANSWER is driven by the pin (the `want` variable): what is under
-- test is the panel <-> grader seam, not the class's decision (the rotation pins
-- hold that).
--=========================================================================================
do
    local by_key = {}
    for _, spec in ipairs(PRACTICE_CLASS_SPECS) do
        by_key[spec.key] = spec
    end

    -- The GRADER-SEAM walk: the class and the client family its panel is walked on.
    -- The paladin carries TWO key spaces, so it is walked on the classic line (TBC:
    -- the twist order names cons/exo) and on the Forever client (the twist order
    -- there names cons/exo/how) - the families the deep audit named. The other five
    -- classes carry ONE key space, so their own slice family is enough.
    --
    -- filler_actions: the class's own filler rows - the spells the guide slots name
    -- under the guide's spelling and the rotation asks for under its own (the
    -- paladin's cons / exo / hs / am: the case the audit found).
    local GRADER_SPECS = {
        { key = "PALADIN", family_id = 5,
            filler_actions = { "cons", "exo", "hs", "am" } },
        { key = "PALADIN", family_id = 18,
            filler_actions = { "cons", "exo", "hs", "am" } },
        { key = "WARRIOR", family_id = 18 },
        { key = "DRUID", family_id = 2 },
        { key = "ROGUE", family_id = 2 },
        { key = "SHAMAN", family_id = 2 },
        { key = "HUNTER", family_id = 2 },
    }

    for _, gs in ipairs(GRADER_SPECS) do
        local spec = by_key[gs.key]
        local cls = gs.key
        local tag = cls .. "@" .. tostring(gs.family_id)
        local b = build({
            with_db = true,
            class_modules = spec.modules,
            project_id = gs.family_id,
            -- The client knows the filler spells, so their buttons carry an icon.
            client_spells = { 879, 20930, 407624 },
        })
        local u, T, F = b.st.practice_ui, b.ST, b.sb
        local module = T[cls]
        T.player_class = cls
T.active_class = cls
        F.class_db.practice_mode = "scenario"
        if type(spec.setup) == "function" then
            spec.setup(T)
        end
        if type(spec.gather) == "function" then
            module.gather_guide_inputs = function(_self, out)
                return spec.gather(out)
            end
        end
        -- The class's own answer is driven by the pin: the seam is under test, not
        -- the class's decision.
        local want = nil
        module.practice_scenario_step = function()
            return { action = want }
        end
        u.init(T)
        F.clock = 0
        u.start(T)
        local buttons = u.practice_row_buttons and u.practice_row_buttons.buttons or {}

        -- (a) ONE button per spell: the panel never offers two spellings of one
        -- spell (the paladin's "cons" and "consecration" are one Consecration).
        local per_spell, dupes = {}, {}
        for key in pairs(buttons) do
            local canonical = module.practice_canonical_key(key)
            per_spell[canonical] = (per_spell[canonical] or 0) + 1
        end
        for canonical, count in pairs(per_spell) do
            if count > 1 then
                dupes[#dupes + 1] = canonical
            end
        end
        table.sort(dupes)
        check(#dupes == 0, tag .. ": the panel offers ONE button per spell"
            .. (#dupes > 0 and (" (twice: " .. table.concat(dupes, ", ") .. ")") or ""))

        -- (b) the button that carries a spell's icon is the CANONICAL one: the
        -- spell id is looked up through the class's alias table, so the one
        -- Consecration button carries the Consecration icon.
        local slots = (type(module.guide) == "table" and type(module.guide.slots) == "table")
            and module.guide.slots or {}
        for i = 1, #slots do
            local slot = slots[i]
            if type(slot) == "table" and type(slot.key) == "string"
                and type(slot.spell_id) == "number" then
                local canonical = module.practice_canonical_key(slot.key)
                local btn = buttons[canonical]
                local icon = b.env.GetSpellTexture(slot.spell_id)
                if btn and icon then
                    check(btn.row_icon ~= nil and btn.row_icon.texture == icon,
                        tag .. ": the " .. canonical .. " button carries the " .. slot.key
                            .. " icon")
                end
            end
        end

        -- The actions the panel is walked with: the class's own published rotation
        -- for the running family, plus the class's filler rows.
        local actions, seen_action = {}, {}
        local function add(action)
            if type(action) == "string" and action ~= "" and not seen_action[action] then
                seen_action[action] = true
                actions[#actions + 1] = action
            end
        end
        local slice = nil
        if type(module.practice_rotation_for) == "function" then
            local ok, entries = pcall(function() return module.practice_rotation_for() end)
            if ok and type(entries) == "table" then
                slice = entries
            end
        end
        for i = 1, #(slice or {}) do
            local entry = slice[i]
            if type(entry) == "table" then
                add(entry.action)
            end
        end
        for _, action in ipairs(gs.filler_actions or {}) do
            add(action)
        end

        -- One press, one session: the run's own budget is ten decisions and the
        -- walk asks for more than ten (the slice, the filler rows and every
        -- spelling the class knows).
        local function press(expected, press_key, label, via_button)
            u.stop(T)
            want = expected
            F.clock = F.clock + 1
            u.start(T)
            local step = u.scenario_step
            check(step ~= nil and step.expected == expected,
                label .. ": the prompt names " .. tostring(expected))
            check(u.scenario_run ~= nil, label .. ": the scenario run is alive")
            if via_button then
                local btn = buttons[press_key]
                check(btn ~= nil, label .. ": the panel offers the button ("
                    .. tostring(press_key) .. ")")
                if btn then
                    btn:GetScript("OnClick")()
                end
            else
                u.cast_key(T, press_key)
            end
            local run = u.scenario_run
            eq(run and run.correct or nil, 1, label .. ": the press grades CORRECT")
            eq(run and run.mispicks or nil, 0, label .. ": the press is not a mis-pick")
            eq(u.result_frame.text.text, "CORRECT", label .. ": the popup reads CORRECT")
            eq(u.score.attempts, 1, label .. ": the press is one graded attempt")
        end

        -- (c) the press of the panel's OWN button for the action the prompt names.
        for i = 1, #actions do
            local action = actions[i]
            press(action, action, tag .. ": the panel's button for " .. action, true)
        end

        -- (d) a press in ANY spelling the class knows grades CORRECT too.
        local aliases = module.practice_action_aliases
        if type(aliases) == "table" then
            local spellings = {}
            for alias, canonical in pairs(aliases) do
                if type(alias) == "string" and type(canonical) == "string"
                    and buttons[canonical] ~= nil and canonical ~= alias then
                    spellings[#spellings + 1] = { alias = alias, canonical = canonical }
                end
            end
            table.sort(spellings, function(a, c) return a.alias < c.alias end)
            for i = 1, #spellings do
                local spelling = spellings[i]
                press(spelling.canonical, spelling.alias,
                    tag .. ": the spelling " .. spelling.alias, false)
            end
        end

        u.stop(T)
    end
end

--=========================================================================================
-- 29e) The drill-list path normalises the pick the same way: the pick rides into the
-- class's own grader in the CANONICAL key space, whatever spelling the press
-- carried.
--
-- The drill-list press is the player's PICK (the action under test) and it is the
-- same alias space as the scenario's grader, so it is normalised at the same seam
-- (practice_ui.lua's drill_list_grade). Without it the pick would reach the class's
-- grader in the press's own spelling - and the class's grader would have to know
-- every spelling of every action to make sense of it.
--=========================================================================================
do
    local spec = nil
    for _, entry in ipairs(PRACTICE_CLASS_SPECS) do
        if entry.key == "PALADIN" then
            spec = entry
        end
    end
    local b = build({
        with_db = true,
        class_modules = spec.modules,
        project_id = 5,
        client_spells = { 879, 20930, 407624 },
    })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    local module = T.PALADIN
    T.player_class = "PALADIN"
T.active_class = "PALADIN"
    F.class_db.practice_mode = "drills"
    if type(spec.setup) == "function" then
        spec.setup(T)
    end
    if type(spec.gather) == "function" then
        module.gather_guide_inputs = function(_self, out)
            return spec.gather(out)
        end
    end
    -- The class's own grader, wrapped so the ctx it receives is observable. The
    -- wrapper only delegates: the letter is the class's own.
    local seen, graded, calls = nil, nil, 0
    local real = module.practice_drills[1].grade
    module.practice_drills[1].grade = function(self, ctx)
        calls = calls + 1
        seen = ctx
        graded = real(self, ctx)
        return graded
    end
    u.init(T)
    F.clock = 0
    u.start(T)
    check(u.drill_list ~= nil, "29e: the drill-list session is the live one")
    -- The press carries its own spelling (the guide slot's "consecration"), and
    -- the pick must reach the class's grader in the canonical key space.
    u.cast_key(T, "consecration")
    check(calls > 0, "29e: the drill-list press reached the class's own grader")
    eq(type(seen) == "table" and seen.pick or nil, "cons",
        "29e: the pick rides in ctx.pick as the canonical key")
    eq(type(seen) == "table" and seen.last_action or nil, "cons",
        "29e: the pick rides in ctx.last_action as the canonical key")
    eq(type(seen) == "table" and seen.action or nil, "cons",
        "29e: the pick rides in ctx.action as the canonical key")
    eq(type(seen) == "table" and seen.pressed or nil, "cons",
        "29e: the pick rides in ctx.pressed as the canonical key")
    eq(u.drill_list_pick, "cons", "29e: the session's pick is the canonical key")
    check(type(graded) == "string" and graded ~= "",
        "29e: the class's own grader answered a letter (not UNKNOWN)")
    u.stop(T)
end

--=========================================================================================
-- 29f) THE CANONICALISATION SEAM: two DIFFERENT spells must never collapse onto one
-- canonical key
--
-- THE HAZARD (the final publish-gate re-audit's F-1): the panel DEDUPES on the
-- canonical key (practice_ui.lua's scenario_action_order pushes the canonical key
-- and skips a key it has already pushed) and the ICON lookup takes the FIRST
-- matching slot (scenario_action_spell_id walks the guide slots and returns the
-- first slot whose key canonicalises to the wanted key). So two keys of DIFFERENT
-- spells that canonicalise onto one key cost the player three things at once: one
-- button silently vanishes, the survivor carries the OTHER spell's icon, and a
-- press of the dropped ability grades as the other spell.
--
-- No such case exists in the shipped tree - the paladin's "sob" is ONE key whose
-- label names both the Blood and the Martyrdom seal, and it never surfaces as two
-- buttons - but nothing would have caught a future one. THIS is that guard.
--
-- WHAT IS WALKED, per class, on the class's OWN published panel vocabulary:
--
--   (1) the class's own GUIDE SLOTS - the key and the slot's spell id (the icon
--       id, which the class keeps rank-invariant, so two slots of one spell
--       carry one id);
--   (2) the class's ROTATION rows for the running family - the key and the row's
--       LABEL (the spell's name, and the label the panel's button carries);
--   (3) the COMMON ABILITIES the class publishes for this family (the key, the
--       label and the published id ladder's first id). The per-ability family
--       gate decides, and the offer gate's other two clauses are deliberately not
--       applied: a merge is exactly what would make the offer gate hide a common
--       ability, and the pin has to see the collision the merge would cause.
--
-- THE RULE: two DIFFERENT keys that canonicalise onto the same key must denote the
-- SAME spell. The evidence is checked per id space (the guide slots' icon ids
-- among themselves, the common abilities' ladder heads among themselves) and across
-- the name publishers (the rotation rows' labels and the common abilities' labels
-- must agree - a rotation row's label IS the spell's name). A rotation row's id is
-- NOT compared with a guide slot's id: the two live in different id spaces (the
-- APL's cited rank against the class's rank-invariant icon id), so a same-spell
-- pair would read as two ids. A guide slot and a common ability are never compared
-- across their id spaces either - the class's own offer gate keeps a rotation
-- ability out of the common list, so the two never meet in one panel.
--
-- THE NORMALISER'S SHAPE is pinned too, so the pin is not vacuous on either side:
-- the five classes whose key space is one publish an IDENTITY normaliser (every
-- vocabulary key canonicalises to itself) and the paladin - the only class with an
-- alias table - publishes a normaliser that really merges (at least one vocabulary
-- key canonicalises onto a different key).
--=========================================================================================
do
    local by_key = {}
    for _, spec in ipairs(PRACTICE_CLASS_SPECS) do
        by_key[spec.key] = spec
    end

    -- The same walks the grader-seam block above uses: the paladin carries TWO key
    -- spaces (the rotation's and the guide slots'), so it is walked on two
    -- families; the other five carry one key space each.
    local COLLISION_SPECS = {
        { key = "PALADIN", family_id = 5 },
        { key = "PALADIN", family_id = 11 },
        { key = "PALADIN", family_id = 18 },
        { key = "WARRIOR", family_id = 18 },
        { key = "DRUID", family_id = 2 },
        { key = "ROGUE", family_id = 2 },
        { key = "SHAMAN", family_id = 2 },
        { key = "HUNTER", family_id = 2 },
    }

    for _, cs in ipairs(COLLISION_SPECS) do
        local spec = by_key[cs.key]
        local cls = cs.key
        local tag = cls .. "@" .. tostring(cs.family_id)
        local b = build({
            with_db = true,
            class_modules = spec.modules,
            project_id = cs.family_id,
            client_spells = { 879, 20930, 407624 },
        })
        local T, F = b.ST, b.sb
        local module = T[cls]
        T.player_class = cls
T.active_class = cls
        F.class_db.practice_mode = "scenario"
        if type(spec.setup) == "function" then
            spec.setup(T)
        end
        if type(spec.gather) == "function" then
            module.gather_guide_inputs = function(_self, out)
                return spec.gather(out)
            end
        end

        -- The vocabulary, one entry per published source.
        local guide, rotation = {}, {}

        -- (1) the class's OWN guide slots (the class seam widens the slot list
        -- with the common abilities on start; the class's own slots are the
        -- other half of the vocabulary).
        if type(module.guide) == "table" and type(module.guide.slots) == "table" then
            for i = 1, #module.guide.slots do
                local slot = module.guide.slots[i]
                if type(slot) == "table" and type(slot.key) == "string" and slot.key ~= "" then
                    guide[#guide + 1] = { key = slot.key, spell_id = slot.spell_id }
                end
            end
        end

        -- (2) the class's ROTATION rows for the running family.
        local ok, entries = pcall(function() return module.practice_rotation_for() end)
        if ok and type(entries) == "table" then
            for i = 1, #entries do
                local entry = entries[i]
                if type(entry) == "table" and type(entry.action) == "string"
                    and entry.action ~= "" then
                    rotation[#rotation + 1] = { key = entry.action, label = entry.label }
                end
            end
        end

        -- (3) the COMMON ABILITIES the class publishes for this family (the
        -- per-ability family gate decides). The offer gate's OTHER two clauses
        -- (the neutral publish and the rotation rank) are deliberately NOT
        -- applied here: a canonicalisation merge is exactly what would make the
        -- offer gate hide a common ability, and the pin has to see the collision
        -- the merge would cause.
        local common = {}
        if type(module.practice_common_actions) == "table" then
            for i = 1, #module.practice_common_actions do
                local action = module.practice_common_actions[i]
                local families = type(action) == "table" and action.families or nil
                local published = true
                if type(families) == "table" then
                    published = false
                    for j = 1, #families do
                        if families[j] == b.st.family then
                            published = true
                            break
                        end
                    end
                end
                if published and type(action.key) == "string" and action.key ~= "" then
                    local ids = type(action.ids) == "table" and action.ids or nil
                    common[#common + 1] = {
                        key = action.key,
                        label = action.label,
                        spell_id = ids and ids[1] or nil,
                    }
                end
            end
        end

        -- The canonical groups: every vocabulary key, canonicalised through the
        -- class's OWN normaliser (the same seam the panel reads).
        local groups, order = {}, {}
        local merged = 0
        local function add(entry, kind)
            local canonical = module.practice_canonical_key(entry.key)
            if type(canonical) ~= "string" or canonical == "" then
                canonical = entry.key
            end
            if canonical ~= entry.key then
                merged = merged + 1
            end
            local group = groups[canonical]
            if not group then
                group = { members = {} }
                groups[canonical] = group
                order[#order + 1] = canonical
            end
            local member = group.members[entry.key]
            if not member then
                member = { key = entry.key, guide_ids = {}, common_ids = {}, labels = {} }
                group.members[entry.key] = member
            end
            if kind == "guide" then
                -- the guide slot's own id: the icon id, which the class keeps
                -- rank-invariant, so two slots of one spell carry one id.
                if type(entry.spell_id) == "number" then
                    member.guide_ids[entry.spell_id] = true
                end
            else
                -- the name publishers: a rotation row's label and a common
                -- ability's label are both the spell's name.
                if type(entry.label) == "string" and entry.label ~= "" then
                    member.labels[entry.label] = true
                end
                if kind == "common" and type(entry.spell_id) == "number" then
                    -- the common ability's own ladder head (the rank-1 id).
                    member.common_ids[entry.spell_id] = true
                end
            end
        end
        for _, entry in ipairs(guide) do
            add(entry, "guide")
        end
        for _, entry in ipairs(rotation) do
            add(entry, "rotation")
        end
        for _, entry in ipairs(common) do
            add(entry, "common")
        end

        check(#order > 0, tag .. ": the class publishes a panel vocabulary")
        for _, canonical in ipairs(order) do
            local group = groups[canonical]
            local distinct = 0
            for _ in pairs(group.members) do
                distinct = distinct + 1
            end
            if distinct > 1 then
                -- The keys that collapse onto this one.
                local keys = {}
                for key in pairs(group.members) do
                    keys[#keys + 1] = key
                end
                table.sort(keys)
                -- (a) the id spaces: every guide slot of the group must carry the
                -- SAME spell id (the icon lookup takes the first one, so a
                -- different id is a different spell), and so must every common
                -- ability (the ladder head).
                local ids = {}
                for _, member in pairs(group.members) do
                    for id in pairs(member.guide_ids) do
                        ids[#ids + 1] = tostring(id)
                    end
                end
                table.sort(ids)
                check(#ids <= 1,
                    tag .. ": the canonical key '" .. canonical .. "' is one spell ("
                        .. table.concat(keys, ", ") .. ") - the guide slots' spell ids agree"
                        .. (#ids > 1 and (" (they differ: " .. table.concat(ids, ", ") .. ")")
                            or ""))
                local common_ids = {}
                for _, member in pairs(group.members) do
                    for id in pairs(member.common_ids) do
                        common_ids[#common_ids + 1] = tostring(id)
                    end
                end
                table.sort(common_ids)
                check(#common_ids <= 1,
                    tag .. ": the canonical key '" .. canonical .. "' is one spell ("
                        .. table.concat(keys, ", ") .. ") - the common abilities' spell ids agree"
                        .. (#common_ids > 1 and (" (they differ: "
                            .. table.concat(common_ids, ", ") .. ")") or ""))
                -- (b) the name publishers: the spell's name must agree.
                local names = {}
                for _, member in pairs(group.members) do
                    for name in pairs(member.labels) do
                        names[#names + 1] = name
                    end
                end
                table.sort(names)
                check(#names <= 1,
                    tag .. ": the canonical key '" .. canonical .. "' is one spell ("
                        .. table.concat(keys, ", ") .. ") - the names agree"
                        .. (#names > 1 and (" (they differ: " .. table.concat(names, ", ") .. ")")
                            or ""))
            end
        end

        -- The normaliser's shape: the pin is not vacuous on either side.
        if cls == "PALADIN" then
            check(merged > 0,
                tag .. ": the paladin's normaliser really merges a vocabulary key")
        else
            check(merged == 0,
                tag .. ": the " .. cls .. " normaliser is the identity (its key space is one)")
        end
    end
end

-- ---- the shipped comments match the code (the final-gate claim) --------------
-- The two drill-icon notes claimed "Era, TBC and Forever each answer their own
-- rank art" (the shaman site) and leaned on "the shaman drill's name-art rule"
-- (the rogue site): the classic-line name leg is UNCONFIRMED in-client (the
-- audit's §6 C1), so a client that answers the name shows its own rank art, and
-- an unanswered name leaves the icon blank. The pins keep the stale claim OUT
-- and the corrected statement IN (source-shape pins, so a correct rewording
-- still passes).
--
-- THE MATCH IS ON PROSE, NOT ON SOURCE LINES: the claim is wrapped across
-- source lines, so the file is flattened (the line-leading comment marker
-- dropped, the lines joined with one space) and the sentence is matched whole.
-- BOTH drill sites must carry the corrected statement (the count is the check):
-- a note that drops back to the old wording loses its own copy of it.
do
    local function prose(path)
        local fh = io.open(path, "r")
        local src = fh and fh:read("*a") or ""
        if fh then fh:close() end
        local parts = {}
        for line in (src:gsub("\r\n", "\n")):gmatch("[^\n]*") do
            parts[#parts + 1] = (line:gsub("^%s*%-%-%s*", ""))
        end
        return (table.concat(parts, " "):gsub("%s+", " "))
    end
    local p = prose(ROOT .. "practice_ui.lua")
        .. " " .. prose(ROOT .. "classes/shaman.lua")
        .. " " .. prose(ROOT .. "classes/rogue.lua")
    check(p:find("every client family answers its own rank art", 1, true) == nil,
        "comment: the stale 'every client family answers its own rank art' claim is gone")
    check(p:find("each answer their own rank art", 1, true) == nil,
        "comment: the stale 'each answer their own rank art' claim is gone")
    local _, marked = p:gsub("a client that answers the name shows its own rank art", "")
    check(marked >= 2,
        "comment: both drill-icon notes carry the corrected name-art statement (found "
            .. tostring(marked) .. ")")
    local _, unconfirmed = p:gsub("UNCONFIRMED in%-client", "")
    check(unconfirmed >= 2,
        "comment: both drill-icon notes mark the name leg UNCONFIRMED in-client (found "
            .. tostring(unconfirmed) .. ")")
end

if failures == 0 then
    print("PASS  practice_ui_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  practice_ui_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
