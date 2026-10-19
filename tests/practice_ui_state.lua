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
    function f:SetFont(path, size, flags) f.font = { path, size, flags }; return true end
    function f:SetText(text) f.text = text end
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
-- opts.no_practice: a flavor without the pure engine (practice.lua not loaded).
-- opts.no_bar:      st.practice_ui's anchor fallback (no mainhand bar frame).
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
    local ST = {
        PALADIN = {},
        player_class = "PALADIN",
        interfaces_are_initialised = true,
        in_combat = false,
        gcd = { duration = 1.5, spell_length = 1.5 },
        mainhand = { speed = 2.6 },
    }
    function ST.PALADIN.practice_sync() sb.practice_sync = sb.practice_sync + 1 end
    function ST.PALADIN.on_aura_change() sb.aura_change = sb.aura_change + 1 end
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

    local LSM = {
        -- Records the media key the module asks for, so the hand-font option path is
        -- pinned, and returns the scripted font (nil exercises the fallback).
        Fetch = function(_, mediatype, key)
            sb.font_requests[#sb.font_requests + 1] = { mediatype = mediatype, key = key }
            return sb.lsm_font
        end,
    }

    local env = setmetatable({}, { __index = _G })
    env.WOW_PROJECT_ID = 11
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_MAINLINE = 1
    env.GetTimePreciseSec = function() return sb.clock end
    env.GetTime = function() return sb.clock end
    env.GetBuildInfo = function() return "3.3.5", "12340", "today", 38002 end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
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
    env.GetSpellInfo = function(spell_id)
        local icon = SPELL_ICONS[spell_id]
        if not icon then
            return nil
        end
        return "Spell " .. spell_id, nil, icon, 0, 0, 0, spell_id
    end
    env.GetSpellTexture = function(spell_id)
        return SPELL_ICONS[spell_id]
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
            return LSM
        end
        return {}
    end

    -- compat.lua reads several legacy globals through rawget(_G, ...); mirror every
    -- stub into _G for the duration of its load, then restore _G exactly.
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

    -- design.lua (pure) backs the descriptor normaliser the C6 handoff must satisfy.
    local design = assert(loadfile(ROOT .. "design.lua"))
    setfenv(design, env)
    design("SwedgeTimer", st)

    -- nextaction.lua owns the rotation thresholds practice.lua delegates to (the TOCs
    -- load it before practice.lua; practice_state.lua does the same).
    local nextaction = assert(loadfile(ROOT .. "nextaction.lua"))
    setfenv(nextaction, env)
    nextaction("SwedgeTimer", st)

    if not opts.no_practice then
        local practice = assert(loadfile(ROOT .. "practice.lua"))
        setfenv(practice, env)
        practice("SwedgeTimer", st)
    end

    local pui = assert(loadfile(ROOT .. "practice_ui.lua"))
    setfenv(pui, env)
    local ok, err = pcall(pui, "SwedgeTimer", st)
    if not ok then
        print("FAIL  practice_ui.lua does not load under the sandbox: " .. tostring(err))
        os.exit(1)
    end

    sb.env, sb.st, sb.ST, sb.class_db, sb.hand_db, sb.bar_frame = env, st, ST, class_db, hand_db, bar_frame
    return { env = env, st = st, ST = ST, sb = sb }
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
    "save_timeline_position",
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
    eq(F.created_frames, 69, "init creates exactly the documented 69 frames " ..
        "(35 panel/result/driver + 10 key buttons + 6 rotation display + " ..
        "6 timeline shell + 4 proc icons + 8 panel buttons)")
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
--=========================================================================================
do
    local b = build()
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    T.interfaces_are_initialised = false
    local HOOKS = {
        { "tick", { 0.1 } },
        { "start", {} },
        { "stop", {} },
        { "toggle", {} },
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
    eq(F.created_frames, 69, "the score line adds no frames (a FontString, not a frame)")
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
    eq(#u.design_targets, 3, "three practice elements are exposed")
    local by_key = {}
    for i = 1, #u.design_targets do
        by_key[u.design_targets[i].key] = u.design_targets[i]
    end
    check(by_key.practice_panel ~= nil, "the panel target is registered")
    check(by_key.practice_rotation ~= nil, "the rotation display target is registered")
    check(by_key.practice_timeline ~= nil, "the timeline target is registered")
    for _, key in ipairs({ "practice_panel", "practice_rotation", "practice_timeline" }) do
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
    u.start(T)
    for _, key in ipairs({ "practice_panel", "practice_rotation", "practice_timeline" }) do
        eq(by_key[key].available(), true, key .. ": available during a session")
    end

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

if failures == 0 then
    print("PASS  practice_ui_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  practice_ui_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
