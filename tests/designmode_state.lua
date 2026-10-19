-- tests/designmode_state.lua: offline execution tests for design mode (designmode.lua)
-- over the real compat.lua + utils.lua + design.lua in a sandbox.
--
-- What is executed here: the real designmode.lua chunk loads in a setfenv sandbox with
-- frame stubs (CreateFrame / textures / fontstrings), a controllable InCombatLockdown,
-- a captured C_Timer, and stubbed element modules (st.hud, st.rotation_text,
-- st.nextaction_ui, st.practice_ui) plus the bar tables (ST.mainhand.anchor_frame, ...)
-- the registry attach reads. enter/exit, the registry refresh (overlay pool), the lock
-- override/restore pass, the grid draw, the drag maths wiring and the reset path all run
-- for real against descriptors designmode.lua itself registers.
--
-- Covered:
--   * load surface: module loads, st.designmode exposed, 7 real elements registered,
--     nothing created at load, LibWindow save/restore seams and AceConfigRegistry notify
--     still just stubs;
--   * enter: layer + guides + grid lines + one overlay per AVAILABLE element (absent
--     frames and an inactive practice panel are skipped - no overlay is created for
--     them), each overlay attached to its element frame (parent/level/box points/label);
--   * the grid: on/off from design_grid_enabled, step changes from design_grid (below
--     design.MIN_GRID counts as off), pooled lines hidden on redraw, refresh_grid gating;
--   * locks: the unlocked value each element's own seam reports before enter is exactly
--     what it reports after exit - locked elements are forced off and set back once, an
--     element already unlocked is never touched, and a lock key whose value is nil stays
--     nil (the seam's set is never called); locks_saved is cleared, so a second
--     enter/exit performs the same calls again;
--   * enter/exit refused in combat (and pre-init) with a message and no frames; a fight
--     starting closes an active session; the refresh tick and the per-overlay drag /
--     double-click handlers bail under lockdown;
--   * drag maths wiring: OnDragStart captures the grab offset, the tick snaps (alignment
--     to a nearby element's lines with guides, grid quantisation otherwise, Shift =
--     half-pixel, Alt = exact centre) and moves the real frame, OnDragStop hands the
--     snapped coordinates to the element's own save seam (LibWindow.SavePosition for the
--     bars, hud_x/hud_y + st.hud.apply_settings for the HUD);
--   * double-click reset calls each element's reset (bar x/y/point + LibWindow.Restore,
--     hud/rotation/guide/practice db keys through their class defaults) and is refused
--     under lockdown;
--   * exit/stop teardown: overlays hidden + re-parented to UIParent + points cleared,
--     drag OnUpdate unhooked, guides hidden, layer hidden, Ctrl-locks restored; the Esc
--     path (the layer's OnHide script) runs the same teardown; toggle round-trips;
--   * the practice element appearing/disappearing with a session (availability gated by
--     st.practice_ui.is_active()), pooled overlay reuse (no new frame on re-appear).
--
-- NOT executed here (main.lua owns them, pinned by tests/main_init_state.lua): the
-- /st design chat command and the design-mode options button; and main.lua's
-- PLAYER_REGEN_DISABLED wiring into DM.on_combat_start (the module side is driven here).
-- The element modules themselves (hud.lua etc.) are stubbed - their real save paths are
-- pinned by their own state tests; this file pins that designmode calls the right one
-- with the right values.
-- Run from the repo root: lua5.1 tests/designmode_state.lua  (any cwd works).

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
local function near(got, want, tol, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > (tol or 1e-9) then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

--=========================================================================================
-- Frame / region stubs (record what design mode draws and moves)
--=========================================================================================
local function make_texture()
    local t = { hidden = false }
    function t:SetAllPoints() t.all_points = true end
    function t:SetPoint(point, rel, relpoint, x, y)
        t.points = t.points or {}
        t.points[#t.points + 1] = { point, rel, relpoint, x, y }
    end
    function t:ClearAllPoints() t.points = {} end
    function t:SetColorTexture(r, g, b, a) t.color = { r, g, b, a } end
    function t:SetTexture(texture) t.texture = texture end
    function t:SetVertexColor(r, g, b, a) t.vertex = { r, g, b, a } end
    function t:SetSize(w, h) t.w, t.h = w, h end
    function t:SetWidth(w) t.w = w end
    function t:SetHeight(h) t.h = h end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
    function t:SetShown(shown) t.hidden = not shown end
    function t:IsShown() return not t.hidden end
    return t
end

local function make_fontstring()
    local f = { hidden = false, text = "" }
    function f:SetPoint() end
    function f:SetFont(path, size, flags) f.font = { path, size, flags }; return true end
    function f:SetText(text) f.text = text end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:SetShadowColor(r, g, b, a) f.shadow_color = { r, g, b, a } end
    function f:SetShadowOffset(x, y) f.shadow_offset = { x, y } end
    function f:Hide() f.hidden = true end
    function f:Show() f.hidden = false end
    return f
end

-- A frame stub. Geometry is scripted: GetCenter returns (cx, cy), GetWidth/GetHeight
-- (w, h); the screen edges are either derived from the centre + size (derive_rect -
-- follows move_centre, like a real client frame) or nil (an element with no readable
-- rect: screen_rect returns nil and the element offers no snap lines).
local function make_frame(name, kind)
    local f = { name = name, kind = kind, shown = true, level = 1, scale = 1, eff_scale = 1,
        cx = 0, cy = 0, w = 0, h = 0, textures = {}, fontstrings = {}, scripts = {} }
    function f:SetSize(w, h) f.w, f.h = w, h end
    function f:SetWidth(w) f.w = w end
    function f:SetHeight(h) f.h = h end
    function f:SetAllPoints() f.all_points = true end
    function f:SetPoint(point, rel, relpoint, x, y)
        f.points = f.points or {}
        f.points[#f.points + 1] = { point, rel, relpoint, x, y }
        if point == "CENTER" and relpoint == "CENTER" and type(x) == "number" then
            f.cx, f.cy = x, y
        end
    end
    function f:ClearAllPoints() f.points = {} end
    function f:SetFrameStrata(strata) f.strata = strata end
    function f:SetFrameLevel(level) f.level = level end
    function f:GetFrameLevel() return f.level end
    function f:SetParent(parent) f.parent = parent end
    function f:EnableMouse(enabled) f.mouse = enabled end
    function f:RegisterForDrag(button) f.drag_button = button end
    function f:RegisterForClicks(buttons) f.click_buttons = buttons end
    function f:SetScript(event, fn)
        f.scripts[event] = fn
    end
    function f:GetScript(event) return f.scripts[event] end
    function f:Show() f.shown = true end
    function f:Hide() f.shown = false end
    function f:SetShown(shown) f.shown = shown end
    function f:IsShown() return f.shown end
    function f:GetScale() return f.scale end
    function f:GetEffectiveScale() return f.eff_scale end
    function f:GetCenter() return f.cx, f.cy end
    function f:GetWidth() return f.w end
    function f:GetHeight() return f.h end
    function f:GetLeft() return f.derive_rect and (f.cx - f.w / 2) or f.left end
    function f:GetRight() return f.derive_rect and (f.cx + f.w / 2) or f.right end
    function f:GetTop() return f.derive_rect and (f.cy + f.h / 2) or f.top end
    function f:GetBottom() return f.derive_rect and (f.cy - f.h / 2) or f.bottom end
    function f:CreateTexture()
        local t = make_texture()
        f.textures[#f.textures + 1] = t
        return t
    end
    function f:CreateFontString()
        local fs = make_fontstring()
        f.fontstrings[#f.fontstrings + 1] = fs
        return fs
    end
    return f
end

--=========================================================================================
-- Sandbox builder
--=========================================================================================
-- opts.hands:      the class's hand list (default {"mainhand", "offhand"})
-- opts.practice:   st.practice_ui present and is_active() (default true)
-- opts.hud / opts.rottext / opts.nag: element frames present (default true)
-- opts.interfaces: ST.interfaces_are_initialised (default true)
-- opts.class_db:   overrides merged into the class db fixture
-- opts.extra_locks: extra registry descriptors carrying lock probes
local function build(opts)
    opts = opts or {}
    local sb = {
        frames = {}, created_frames = 0, prints = {}, notify = {}, timers = {},
        lockdown = false, cursor_x = 0, cursor_y = 0, shift = false, alt = false,
        lwin_saved = {}, lwin_restored = {},
        visibilities = 0, lock_frames = 0, unlock_frames = 0,
        hud_apply = 0, rottext_apply = 0, nag_apply = 0, practice_apply = 0, practice_saves = 0,
        glow_starts = 0, glow_stops = 0,
        practice_active = opts.practice_active,
    }
    if sb.practice_active == nil then sb.practice_active = opts.practice ~= false end

    local class_db = {
        timers_locked = true,
        hud_locked = nil,             -- nil means "never written": the seam reads it as locked
        rotation_label_locked = false,
        nextaction_locked = true,
        design_grid_enabled = true,
        design_grid = 24,
        design_snap = true,
        design_snap_threshold = 8,
    }
    for k, v in pairs(opts.class_db or {}) do class_db[k] = v end
    sb.class_db = class_db

    local hand_dbs = { mainhand = {}, offhand = {}, ranged = {} }

    local UIParent = make_frame("UIParent")
    UIParent.w, UIParent.h = 1024, 768

    local element = {}
    for _, hand in ipairs(opts.hands or { "mainhand", "offhand" }) do
        local f = make_frame(hand .. "Anchor", "bar")
        f.derive_rect = true
        element["bar_" .. hand] = f
    end
    if opts.hud ~= false then element.hud = make_frame("Hud", "hud") end
    if opts.rottext ~= false then element.rottext = make_frame("RotationLabel", "rottext") end
    if opts.nag ~= false then element.nag = make_frame("NextActionGuide", "nag") end
    if opts.practice ~= false then element.practice = make_frame("PracticePanel", "practice") end
    sb.element = element

    -- The frames set_bars_designing shows while designing / hands back on exit. The
    -- real bars.lua accessors (loaded below) walk anchor -> bar_frame -> visuals_frame,
    -- so the fixture wires that chain and the hand's measured visuals size.
    local bar_frames, hiding_frames = {}, {}
    for _, hand in ipairs(opts.hands or { "mainhand", "offhand" }) do
        bar_frames[hand] = make_frame(hand .. "Bar", "bar_visual")
        hiding_frames[hand] = make_frame(hand .. "Hiding", "bar_hiding")
        local vf = make_frame(hand .. "Visuals", "bar_visuals")
        vf.derive_rect = true
        vf.w, vf.h = 200, 20
        bar_frames[hand].visuals_frame = vf
        element["bar_" .. hand].bar_frame = bar_frames[hand]
        element["bar_" .. hand].hiding_anchor_frame = hiding_frames[hand]
    end

    local ST = {
        player_class = "PALADIN",
        interfaces_are_initialised = opts.interfaces ~= false,
        options_table_name = "SwedgeTimer_Options",
        defaults = { profile = { PALADIN = {
            mainhand = { x = 11, y = -22, point = "TOPRIGHT" },
            ["**"] = { x = 5, y = -5 },
            hud_x = 33, hud_y = -333,
        } } },
        class_defaults = { hud_x = 0, hud_y = -236,
            rotation_label_x = -9, rotation_label_y = -150,
            nextaction_x = 7, nextaction_y = -180 },
        bar_defaults = { x = 0, y = -120 },
    }
    function ST:Print(msg) sb.prints[#sb.prints + 1] = tostring(msg) end
    function ST:get_class_table() return class_db end
    -- main.lua's converter, mirrored (0-255 rgb, alpha passthrough; new_alpha overrides).
    function ST:convert_color(t, new_alpha)
        local r, g, b, a = unpack(t)
        a = new_alpha or a
        return r / 255, g / 255, b / 255, a
    end
    function ST:get_hand_table(hand)
        hand_dbs[hand] = hand_dbs[hand] or {}
        return hand_dbs[hand]
    end
    function ST:iter_hands()
        local hands = opts.hands or { "mainhand", "offhand" }
        local i, n = 0, #hands
        return function()
            i = i + 1
            if i <= n then return hands[i] end
        end
    end
    function ST:get_anchor_frame(hand)
        if not ST.interfaces_are_initialised then return nil end
        return ST[hand] and ST[hand].anchor_frame
    end
    function ST:get_bar_frame(hand) return bar_frames[hand] end
    function ST:get_hiding_anchor_frame(hand) return hiding_frames[hand] end
    function ST:handle_bar_visibility() sb.visibilities = sb.visibilities + 1 end
    function ST:lock_frames() sb.lock_frames = sb.lock_frames + 1 end
    function ST:unlock_frames() sb.unlock_frames = sb.unlock_frames + 1 end
    sb.ST, sb.hand_dbs, sb.bar_frames, sb.hiding_frames, sb.UIParent = ST, hand_dbs, bar_frames, hiding_frames, UIParent

    local LWIN = {
        SavePosition = function(frame)
            sb.lwin_saved[#sb.lwin_saved + 1] = { frame = frame, point = frame.points and frame.points[#frame.points] }
        end,
        RestorePosition = function(frame) sb.lwin_restored[#sb.lwin_restored + 1] = frame end,
    }
    local ACR = { NotifyChange = function(_, name) sb.notify[#sb.notify + 1] = name end }
    sb.LWIN, sb.ACR = LWIN, ACR

    local LCG = {
        PixelGlow_Start = function(frame, color, n, freq, length, th, x, y, border, key)
            sb.glow_starts = sb.glow_starts + 1
            sb.glow_last = { frame = frame, color = color, n = n, freq = freq,
                length = length, th = th, key = key }
        end,
        PixelGlow_Stop = function(frame, key)
            sb.glow_stops = sb.glow_stops + 1
            sb.glow_stop = { frame = frame, key = key }
        end,
    }
    sb.LCG = LCG

    local env = setmetatable({}, { __index = _G })
    env.WOW_PROJECT_ID = 11
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_MAINLINE = 1
    env.GetTimePreciseSec = function() return 0 end
    env.GetTime = function() return 0 end
    env.GetBuildInfo = function() return "3.3.5", "12340", "today", 38002 end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.UIParent = UIParent
    env.UISpecialFrames = {}
    env.tinsert = table.insert
    env.InCombatLockdown = function() return sb.lockdown end
    env.GetCursorPosition = function() return sb.cursor_x, sb.cursor_y end
    env.IsShiftKeyDown = function() return sb.shift end
    env.IsAltKeyDown = function() return sb.alt end
    env.GameTooltip = {
        SetOwner = function() end, SetText = function() end,
        AddLine = function(_, line)
            sb.tooltip_lines = sb.tooltip_lines or {}
            sb.tooltip_lines[#sb.tooltip_lines + 1] = line
        end,
        Show = function() end, Hide = function() sb.tooltip_hidden = true end,
    }
    env.C_Timer = {
        After = function(delay, callback)
            sb.timers[#sb.timers + 1] = { delay = delay, cb = callback }
        end,
    }
    env.CreateFrame = function(kind, name, parent)
        local f = make_frame(name, kind or "Frame")
        f.parent = parent
        sb.created_frames = sb.created_frames + 1
        sb.frames[#sb.frames + 1] = f
        return f
    end
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then return { GetAddon = function() return ST end } end
        if major == "LibWindow-1.1" then return LWIN end
        if major == "AceConfigRegistry-3.0" then return ACR end
        if major == "LibCustomGlow-1.0" then return LCG end
        return {}
    end

    local st = {}
    for _, path in ipairs({ "compat.lua", "utils.lua", "design.lua", "bars.lua", "designmode.lua" }) do
        local chunk = assert(loadfile(ROOT .. path))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "SwedgeTimer", st)
        if not ok then
            print("FAIL  " .. path .. " does not load under the sandbox: " .. tostring(err))
            os.exit(1)
        end
    end

    -- bars.lua wipes the hand tables at load (ST.mainhand = {} etc.), so the fixture's
    -- hand state is installed after the modules load - exactly as main.lua does in-game.
    for _, hand in ipairs(opts.hands or { "mainhand", "offhand" }) do
        ST[hand] = { anchor_frame = element["bar_" .. hand], vf_width = 200, vf_height = 20 }
    end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) sb.prints[#sb.prints + 1] = tostring(msg) end }

    st.hud = opts.hud ~= false and {
        frame = element.hud,
        apply_settings = function() sb.hud_apply = sb.hud_apply + 1 end,
    } or nil
    st.rotation_text = opts.rottext ~= false and {
        frame = element.rottext,
        apply_settings = function() sb.rottext_apply = sb.rottext_apply + 1 end,
        anchor_point_for = function() return "CENTER" end,
    } or nil
    st.nextaction_ui = opts.nag ~= false and {
        frame = element.nag,
        apply_settings = function() sb.nag_apply = sb.nag_apply + 1 end,
    } or nil
    st.practice_ui = opts.practice ~= false and {
        panel = element.practice,
        is_active = function() return sb.practice_active end,
        apply_settings = function() sb.practice_apply = sb.practice_apply + 1 end,
        save_position = function() sb.practice_saves = sb.practice_saves + 1 end,
    } or nil

    -- Practice rotation/timeline frames (opt-in): mirrors practice_ui.lua's own
    -- ui.design_targets table so the suite drives designmode's real delegation
    -- path (single source) instead of a parallel stub. Only the new section 16
    -- sets practice_extras; every other section keeps the panel-only fixture.
    if opts.practice_extras and st.practice_ui then
        local pui = st.practice_ui
        local rot = make_frame("PracticeRotation")
        rot.derive_rect = true
        rot.w, rot.h = 200, 40
        local tl = make_frame("PracticeTimeline")
        tl.derive_rect = true
        tl.w, tl.h = 400, 60
        pui.rotation_display = rot
        pui.timeline_frame = tl
        sb.rot_saves, sb.tl_saves, sb.rot_resets, sb.tl_resets = 0, 0, 0, 0
        pui.design_targets = {
            {
                key = "practice_rotation",
                title = "Practice rotation display",
                get_frame = function() return pui.rotation_display end,
                available = function() return pui.is_active() end,
                save = function(x, y)
                    sb.rot_saves = sb.rot_saves + 1
                    sb.rot_saved = { x, y }
                    rot:ClearAllPoints()
                    rot:SetPoint("CENTER", UIParent, "CENTER", x, y)
                end,
                reset = function()
                    sb.rot_resets = sb.rot_resets + 1
                    rot:ClearAllPoints()
                    rot:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                end,
            },
            {
                key = "practice_timeline",
                title = "Practice timeline",
                get_frame = function() return pui.timeline_frame end,
                available = function() return pui.is_active() end,
                save = function(x, y)
                    sb.tl_saves = sb.tl_saves + 1
                    sb.tl_saved = { x, y }
                    tl:ClearAllPoints()
                    tl:SetPoint("CENTER", UIParent, "CENTER", x, y)
                end,
                reset = function()
                    sb.tl_resets = sb.tl_resets + 1
                    tl:ClearAllPoints()
                    tl:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
                end,
            },
        }
    end

    sb.env, sb.st, sb.DM, sb.D = env, st, st.designmode, st.design

    -- Lock probes registered into the module's own registry: a nil-valued lock key must
    -- never be written (the seam's set is not called), a false one must stay false.
    sb.probes = {}
    for _, spec in ipairs(opts.extra_locks or {}) do
        local calls = {}
        sb.probes[spec.name] = calls
        local _, err = sb.DM.registry:register({
            key = "test_" .. spec.name,
            title = "lock probe " .. spec.name,
            get_frame = function() return nil end,
            lock = {
                get = function() return spec.get end,
                set = function(v) calls[#calls + 1] = v end,
            },
        })
        if err then
            print("FAIL  lock probe " .. spec.name .. " does not register: " .. tostring(err))
            os.exit(1)
        end
    end
    return { env = env, st = st, ST = ST, sb = sb }
end

--=========================================================================================
-- Helpers over the sandbox
--=========================================================================================
local function overlays(sb)
    local out = {}
    for _, f in ipairs(sb.frames) do
        if f.kind == "Button" then out[#out + 1] = f end
    end
    return out
end

local function overlay_titles(sb)
    local out = {}
    for _, o in ipairs(overlays(sb)) do
        out[#out + 1] = o.fontstrings[1] and o.fontstrings[1].text or nil
    end
    return out
end

local function shown_overlay_titles(sb)
    local out = {}
    for _, o in ipairs(overlays(sb)) do
        if o.shown then out[#out + 1] = o.fontstrings[1] and o.fontstrings[1].text or nil end
    end
    return out
end

local function overlay_for(sb, title)
    for _, o in ipairs(overlays(sb)) do
        if o.fontstrings[1] and o.fontstrings[1].text == title then return o end
    end
end

local function layer_of(sb)
    for _, f in ipairs(sb.frames) do
        if f.name == "SwedgeTimerDesignMode" then return f end
    end
end

-- Shown grid lines = the layer's textures after the dim veil; the centre cross always
-- gets two, and with a grid step each axis adds a +/- line per step up to the half
-- screen (every fourth line brighter - the brightness is not asserted here).
local function grid_line_count(step, w, h)
    if not (step and step >= 8) then return 2 end
    local n = 2
    local k = 1
    while k * step <= w / 2 do n = n + 2; k = k + 1 end
    k = 1
    while k * step <= h / 2 do n = n + 2; k = k + 1 end
    return n
end

local function shown_grid_lines(layer)
    local n = 0
    for i = 2, #layer.textures do
        if not layer.textures[i].hidden then n = n + 1 end
    end
    return n
end

local function last_point(f)
    return f.points and f.points[#f.points] or nil
end

--=========================================================================================
-- 1) Load surface
--=========================================================================================
local base = build()
local st, DM, sb = base.st, base.st.designmode, base.sb
check(type(st.api) == "table", "compat.lua loaded (st.api)")
check(type(st.utils) == "table", "utils.lua loaded (st.utils)")
check(type(st.design) == "table", "design.lua loaded (st.design)")
check(type(DM) == "table", "designmode.lua defines st.designmode")
for _, name in ipairs({ "enter", "exit", "stop", "toggle", "refresh", "refresh_grid",
    "is_active", "on_combat_start", "registry", "register_template",
    "unregister_template" }) do
    check(DM[name] ~= nil, "designmode.lua exposes " .. name)
end
check(type(DM.templates) == "table" and DM.templates.count == 0,
    "the snap-template registry starts empty")
check(type(base.ST.register_zone) == "function", "bars.lua loaded (ST:register_zone)")
check(type(base.ST.new_pips) == "function", "bars.lua loaded (ST:new_pips)")
eq(sb.created_frames, 0, "no frames are created at file load")
eq(DM.is_active(), false, "design mode starts inactive")
eq(DM.registry.count, 9, "the registry holds the nine real elements")
local keys = { "bar_mainhand", "bar_offhand", "bar_ranged", "hud", "rottext", "nag", "practice_panel",
    "practice_rotation", "practice_timeline" }
for i = 1, #keys do
    check(DM.registry.by_key[keys[i]] ~= nil, "registry element: " .. keys[i])
end
eq(DM.registry.by_key.bar_mainhand.title, "Mainhand bar", "bar element title")
eq(DM.registry.by_key.hud.title, "Cooldown HUD", "hud element title")
eq(DM.registry.by_key.rottext.title, "Rotation label", "rotation element title")
eq(DM.registry.by_key.nag.title, "Next action guide", "guide element title")
eq(DM.registry.by_key.practice_panel.title, "Practice panel", "practice element title")
eq(DM.registry.by_key.practice_rotation.title, "Practice rotation display", "rotation element title")
eq(DM.registry.by_key.practice_timeline.title, "Practice timeline", "timeline element title")
eq(DM.registry.by_key.practice_panel.lock, nil, "the practice element has no lock seam")
eq(DM.registry.by_key.practice_rotation.lock, nil, "the rotation element has no lock seam either")
-- Without the practice module's own design_targets table the two delegated
-- targets degrade silently: no frame, unavailable, stable count.
eq(DM.registry.by_key.practice_rotation.get_frame(), nil, "rotation: no delegate -> no frame")
eq(DM.registry.by_key.practice_rotation.available(), false, "rotation: no delegate -> unavailable")
eq(DM.registry.by_key.practice_timeline.get_frame(), nil, "timeline: no delegate -> no frame")
eq(DM.registry.by_key.practice_timeline.available(), false, "timeline: no delegate -> unavailable")
eq(DM.stop(true), false, "stop while inactive is a no-op returning false")

--=========================================================================================
-- 2) enter: layer + guides + grid + one overlay per AVAILABLE element
--=========================================================================================
do
    local b = build()
    local d, F = b.st.designmode, b.sb
    d.enter()

    eq(d.is_active(), true, "enter activates design mode")
    eq(#F.prints, 1, "enter prints one message")
    check(F.prints[1]:find("Design mode on", 1, true) ~= nil, "the enter notice names design mode")
    check(F.prints[1]:find("Shift = no snap", 1, true) ~= nil, "the enter notice documents the modifiers")

    -- Layer + guides + one overlay per element: 2 bars + hud + rottext + nag + practice.
    local layer = layer_of(F)
    check(layer ~= nil, "enter creates the design layer")
    eq(layer.shown, true, "the layer is shown")
    eq(layer.strata, "BACKGROUND", "the layer sits at the BACKGROUND strata")
    eq(layer.name, "SwedgeTimerDesignMode", "the layer carries the addon's name")
    eq(F.env.UISpecialFrames[1], "SwedgeTimerDesignMode", "the layer is an Esc special frame")
    check(type(layer:GetScript("OnHide")) == "function", "the layer has an OnHide (Esc) handler")
    check(type(layer:GetScript("OnUpdate")) == "function", "the layer has the refresh tick")

    local titles = overlay_titles(F)
    eq(#titles, 6, "enter creates one overlay per available element")
    eq(F.created_frames, 2 + 6, "enter creates only the layer, guides and the 6 overlays")
    eq(titles[1], "Mainhand bar", "overlay 1 is the mainhand bar")
    eq(titles[2], "Offhand bar", "overlay 2 is the offhand bar")
    eq(titles[3], "Cooldown HUD", "overlay 3 is the Cooldown HUD")
    eq(titles[4], "Rotation label", "overlay 4 is the rotation label")
    eq(titles[5], "Next action guide", "overlay 5 is the next action guide")
    eq(titles[6], "Practice panel", "overlay 6 is the practice panel")
    for i, o in ipairs(overlays(F)) do
        eq(o.shown, true, "overlay " .. i .. " is shown")
    end

    -- Overlay 1 is attached to the mainhand anchor frame: parented, above it, hugging
    -- its box, with a warm label.
    local o1 = overlays(F)[1]
    local bar = F.element.bar_mainhand
    eq(o1.parent, bar, "the bar overlay is parented to the element frame")
    eq(o1.level, (bar.level or 1) + 20, "the overlay sits above the element")
    local p1, p2 = o1.points[1], o1.points[2]
    eq(p1[1], "TOPLEFT", "the overlay anchors top-left")
    eq(p1[2], bar, "the overlay hugs the element's top-left")
    eq(p2[1], "BOTTOMRIGHT", "the overlay anchors bottom-right")
    eq(p2[2], bar, "the overlay hugs the element's bottom-right")
    eq(o1.mouse, true, "the overlay takes mouse")
    eq(o1.drag_button, "LeftButton", "the overlay drags with the left button")
    check(type(o1:GetScript("OnDragStart")) == "function", "the overlay has an OnDragStart")
    check(type(o1:GetScript("OnDragStop")) == "function", "the overlay has an OnDragStop")
    check(type(o1:GetScript("OnDoubleClick")) == "function", "the overlay has an OnDoubleClick")
    eq(o1.fontstrings[1].color[1], 1, "the label uses the warm colour (r)")
    eq(o1.fontstrings[1].font[3], "OUTLINE", "the label is outlined")

    -- The guides frame exists but starts hidden (no drag yet).
    local guides
    for _, f in ipairs(F.frames) do
        if f.kind == "Frame" and f.name == nil and f ~= layer then guides = guides or f end
    end
    check(guides ~= nil, "enter creates the guide frame")
    eq(guides.shown, false, "the guides start hidden")
    eq(guides.strata, "DIALOG", "the guides sit above the layer")
    eq(guides.mouse, false, "the guides never take mouse")

    -- The grid is drawn: 2 centre lines + one pair per step out to the half screen.
    eq(shown_grid_lines(layer), grid_line_count(24, 1024, 768), "the 24 px grid is drawn")
    eq(#layer.textures, 1 + grid_line_count(24, 1024, 768), "the grid reuses the layer's pooled textures")
    eq(layer.textures[1].color[4], 0.35, "the dim veil covers the screen")

    -- The bars were force-shown through their own seam; locks forced off.
    eq(F.bar_frames.mainhand.shown, true, "the mainhand bar frame is shown while designing")
    eq(F.hiding_frames.mainhand.shown, true, "the hiding anchor is shown while designing")
    eq(F.unlock_frames, 1, "the bars' lock seam unlocks once")
    eq(F.class_db.timers_locked, false, "the bar lock key is forced off while designing")
    eq(F.notify[1], "SwedgeTimer_Options", "enter notifies the options registry")

    -- A second enter while active is a no-op.
    local frames_before = F.created_frames
    d.enter()
    eq(F.created_frames, frames_before, "a second enter creates nothing")
    eq(#F.prints, 1, "a second enter prints nothing")
end

--=========================================================================================
-- 3) unavailable elements are skipped (no overlay, no stub frame)
--=========================================================================================
do
    local b = build({ nag = false, practice = false })
    local d, F = b.st.designmode, b.sb
    d.enter()
    local titles = overlay_titles(F)
    eq(#titles, 4, "an element without a frame and an inactive practice panel are skipped")
    eq(F.created_frames, 2 + 4, "no frames are created for the skipped elements")
    eq(titles[1], "Mainhand bar", "the available bars still get overlays (1)")
    eq(titles[2], "Offhand bar", "the available bars still get overlays (2)")
    eq(titles[3], "Cooldown HUD", "the HUD still gets an overlay")
    eq(titles[4], "Rotation label", "the rotation label still gets an overlay")
    eq(overlay_for(F, "Next action guide"), nil, "no overlay for the absent guide module")
    eq(overlay_for(F, "Practice panel"), nil, "no overlay for the inactive practice panel")

    -- A hands list without offhand (paladin-like) skips the offhand bar too.
    local p = build({ hands = { "mainhand" } })
    p.st.designmode.enter()
    eq(#overlay_titles(p.sb), 5, "a one-hand class shows one bar overlay")
    eq(overlay_for(p.sb, "Offhand bar"), nil, "no offhand overlay without the hand")
end

--=========================================================================================
-- 4) the grid: on/off + step from the db
--=========================================================================================
do
    local b = build()
    local d, F = b.st.designmode, b.sb
    d.enter()
    local layer = layer_of(F)
    eq(shown_grid_lines(layer), grid_line_count(24, 1024, 768), "grid: the default 24 px step is drawn")

    -- A step change redraws and hides the pooled lines it no longer needs.
    F.class_db.design_grid = 32
    d.refresh_grid()
    eq(shown_grid_lines(layer), grid_line_count(32, 1024, 768), "grid: a 32 px step redraws (fewer lines)")
    eq(#layer.textures, 1 + grid_line_count(24, 1024, 768), "grid: redraw reuses the pooled textures")

    -- Off: the centre cross is the only reference.
    F.class_db.design_grid_enabled = false
    d.refresh_grid()
    eq(shown_grid_lines(layer), 2, "grid: design_grid_enabled = false leaves the centre cross")
    F.class_db.design_grid_enabled = true
    F.class_db.design_grid = 4
    d.refresh_grid()
    eq(shown_grid_lines(layer), 2, "grid: a step below design.MIN_GRID counts as off")

    -- A nil/absent grid key falls back to off as well (the option getter ships 24).
    F.class_db.design_grid = nil
    d.refresh_grid()
    eq(shown_grid_lines(layer), 2, "grid: a nil step draws no grid")

    -- refresh_grid while inactive is a no-op (draw_grid is gated on active).
    local idle = build()
    idle.st.designmode.refresh_grid()
    eq(#idle.sb.frames, 0, "refresh_grid while inactive creates nothing")
end

--=========================================================================================
-- 5) locks: forced off on enter, restored exactly on exit
--=========================================================================================
do
    local b = build({ extra_locks = {
        { name = "nilval", get = nil },
        { name = "falseval", get = false },
        { name = "trueval", get = true },
    } })
    local d, F = b.st.designmode, b.sb
    local db = F.class_db
    -- What each real element's seam reports before enter.
    local before = {
        bars = db.timers_locked ~= false,
        hud = db.hud_locked ~= false,
        rottext = db.rotation_label_locked ~= false,
        nag = db.nextaction_locked ~= false,
    }

    d.enter()
    -- Locked elements are forced off through their own seam...
    eq(db.timers_locked, false, "lock: the bars are unlocked while designing")
    eq(F.unlock_frames, 1, "lock: unlock_frames runs once")
    eq(db.hud_locked, false, "lock: the HUD lock key (nil before) is forced off")
    eq(F.hud_apply, 1, "lock: the HUD seam re-applies once")
    eq(db.nextaction_locked, false, "lock: the guide lock key is forced off")
    eq(F.nag_apply, 1, "lock: the guide seam re-applies once")
    -- ...an element that reports false is never touched...
    eq(db.rotation_label_locked, false, "lock: an already-unlocked element stays false")
    eq(F.rottext_apply, 0, "lock: the already-unlocked element's seam is not called")
    -- ...and locks whose value is nil / false never call set at all.
    eq(#F.probes.nilval, 0, "lock: a nil lock value is never written (set not called)")
    eq(#F.probes.falseval, 0, "lock: a false lock value is never written")
    eq(#F.probes.trueval, 1, "lock: a true lock value is forced off once")
    eq(F.probes.trueval[1], false, "lock: ...to false")

    d.exit()
    eq(d.is_active(), false, "exit deactivates design mode")
    eq(#F.prints, 2, "exit prints one message")
    check(F.prints[2]:find("Design mode off", 1, true) ~= nil, "the exit notice confirms the lock-in")
    -- Every real element reports exactly the lock value it reported before enter...
    eq(db.timers_locked ~= false, before.bars, "lock: the bar lock value is restored exactly")
    eq(db.hud_locked ~= false, before.hud, "lock: the HUD lock value (nil before) is restored exactly")
    eq(db.rotation_label_locked ~= false, before.rottext, "lock: the false lock value is untouched")
    eq(db.nextaction_locked ~= false, before.nag, "lock: the guide lock value is restored exactly")
    eq(F.lock_frames, 1, "lock: lock_frames runs once on exit")
    eq(db.timers_locked, true, "lock: the bar key is set back to true")
    eq(db.hud_locked, true, "lock: the HUD key is set back to true")
    -- ...and the true/false/nil probes were never coerced.
    eq(#F.probes.nilval, 0, "lock: nil stays nil (no set on exit either)")
    eq(#F.probes.falseval, 0, "lock: false stays false")
    eq(#F.probes.trueval, 2, "lock: the true lock is set back once")
    eq(F.probes.trueval[2], true, "lock: ...to true")

    -- locks_saved is cleared: a second round performs the same calls exactly once more.
    d.enter()
    d.exit()
    eq(F.unlock_frames, 2, "lock: the second enter unlocks the bars again")
    eq(F.lock_frames, 2, "lock: the second exit re-locks the bars again")
    eq(F.hud_apply, 4, "lock: the HUD seam re-applies once per direction per round")
    eq(#F.probes.trueval, 4, "lock: the true probe is never double-toggled")
end

--=========================================================================================
-- 6) drag maths wiring: OnDragStart -> tick -> OnDragStop -> the element's save seam
--=========================================================================================
do
    -- Scenario A: no neighbours within reach -> grid quantisation, then save.
    local b = build({ hands = { "mainhand" }, practice = false })
    local d, F = b.st.designmode, b.sb
    d.enter()
    local bar = F.element.bar_mainhand
    bar.cx, bar.cy = 50, 60
    bar.w, bar.h = 200, 20
    local o = overlay_for(F, "Mainhand bar")

    F.cursor_x, F.cursor_y = 200, 100
    o:GetScript("OnDragStart")(o)
    eq(o.dragging, true, "drag: OnDragStart latches the drag")
    eq(o.start_x, 50, "drag: the grab offset records the element centre (x)")
    eq(o.start_y, 60, "drag: the grab offset records the element centre (y)")
    eq(o.cursor_x, 200, "drag: the grab cursor is remembered (x)")
    eq(o.half_w, 100, "drag: half the element's width is measured")
    eq(o.half_h, 10, "drag: half the element's height is measured")
    check(type(o:GetScript("OnUpdate")) == "function", "drag: the drag tick is hooked")
    -- 50,60 with a 200x20 box: the low edge -50 quantises to -48, so x -> 52; the top
    -- edge 70 quantises to 72, so y -> 62. No neighbour lines -> no guides.
    eq(last_point(bar)[4], 52, "drag: the box's low edge lands on the 24 px grid (x = 52)")
    eq(last_point(bar)[5], 62, "drag: the top edge lands on the 24 px grid (y = 62)")
    eq(#F.lwin_saved, 0, "drag: the tick alone does not save")

    -- Move the cursor 60 right and 40 up: l=10 -> 0, t=110 -> 120.
    F.cursor_x, F.cursor_y = 260, 140
    o:GetScript("OnUpdate")(o)
    eq(last_point(bar)[4], 100, "drag: the second tick re-snaps x to the grid (100)")
    eq(last_point(bar)[5], 110, "drag: the second tick re-snaps y to the grid (110)")

    o:GetScript("OnDragStop")(o)
    eq(o.dragging, nil, "drag: OnDragStop clears the latch")
    eq(o:GetScript("OnUpdate"), nil, "drag: OnDragStop unhooks the tick")
    eq(o.live_x, 100, "drag: the snapped x is kept for the save")
    eq(o.live_y, 110, "drag: the snapped y is kept for the save")
    eq(#F.lwin_saved, 1, "drag: the drop calls the bar's own save (LibWindow.SavePosition)")
    eq(F.lwin_saved[1].frame, bar, "drag: ...on the dragged bar frame")
    eq(F.lwin_saved[1].point[1], "CENTER", "drag: ...persisting a centre anchor")
    eq(F.lwin_saved[1].point[4], 100, "drag: ...with the snapped x")
    eq(F.lwin_saved[1].point[5], 110, "drag: ...with the snapped y")
    local guides
    for _, f in ipairs(F.frames) do
        if f.kind == "Frame" and f.name == nil and f.all_points and f.mouse == false then guides = f end
    end
    eq(guides.shown, false, "drag: the guides are hidden again on drop")

    -- Shift: free placement at the half-pixel, no snapping, no guides.
    F.shift = true
    F.cursor_x, F.cursor_y = 100, 100
    o:GetScript("OnDragStart")(o)
    F.cursor_x, F.cursor_y = 100.3, 100
    o:GetScript("OnUpdate")(o)
    eq(last_point(bar)[4], 100.5, "drag (Shift): the centre half-rounds instead of snapping")
    eq(guides.shown, false, "drag (Shift): no guides are drawn")
    o:GetScript("OnDragStop")(o)
    eq(F.lwin_saved[2].point[4], 100.5, "drag (Shift): the half-pixel position is saved")
    F.shift = false

    -- Alt: exact screen centre, guides down the middle.
    F.alt = true
    F.cursor_x, F.cursor_y = 500, 500
    o:GetScript("OnDragStart")(o)
    F.cursor_x, F.cursor_y = 900, 700
    o:GetScript("OnUpdate")(o)
    eq(last_point(bar)[4], 0, "drag (Alt): the centre force lands x on the screen centre")
    eq(last_point(bar)[5], 0, "drag (Alt): the centre force lands y on the screen centre")
    eq(guides.shown, true, "drag (Alt): the centre guides are shown")
    o:GetScript("OnDragStop")(o)
    eq(F.lwin_saved[3].point[4], 0, "drag (Alt): the centre is saved (x)")
    eq(F.lwin_saved[3].point[5], 0, "drag (Alt): the centre is saved (y)")
    F.alt = false

    -- Scenario B: a neighbour's box within reach -> alignment beats the grid and the
    -- guide lines are drawn for the hit edges/centres.
    local hud = F.element.hud
    hud.cx, hud.cy = 208, 60
    hud.derive_rect = false
    hud.left, hud.right = 158, 258
    hud.top, hud.bottom = 75, 45
    bar.cx, bar.cy = 100, 110      -- the bar where scenario A left it
    F.cursor_x, F.cursor_y = 500, 500
    o:GetScript("OnDragStart")(o)
    -- raw centre (100, 110) -> box (0..200, 100..120): the right edge 200 snaps to the
    -- HUD's centre line 208 (+8, inside the 8 px magnet); y stays on the grid at 110.
    eq(last_point(bar)[4], 108, "drag (align): the bar's edge snaps to the HUD's centre line")
    eq(guides.shown, true, "drag (align): the guide line is shown")
    eq(guides.textures[1].hidden, false, "drag (align): the vertical guide is visible")
    eq(guides.textures[2].hidden, true, "drag (align): the horizontal guide stays hidden")
    eq(guides.textures[1].points[1][4], 208, "drag (align): the vertical guide sits on the hit line")
    -- Move up-left: left edge 158 snaps to the HUD's left edge 158, top edge 75 snaps
    -- to the HUD's top edge 75.
    F.cursor_x, F.cursor_y = 458, 455
    o:GetScript("OnUpdate")(o)
    eq(last_point(bar)[4], 58, "drag (align): the second tick snaps x to the abutting edge")
    eq(last_point(bar)[5], 65, "drag (align): ...and y to the abutting edge")
    eq(guides.textures[1].hidden, false, "drag (align): the vertical guide follows")
    eq(guides.textures[2].hidden, false, "drag (align): the horizontal guide appears")
    eq(guides.textures[1].points[1][4], 158, "drag (align): the vertical guide sits on 158")
    eq(guides.textures[2].points[1][5], 75, "drag (align): the horizontal guide sits on 75")
    o:GetScript("OnDragStop")(o)
    eq(F.lwin_saved[4].point[4], 58, "drag (align): the aligned x is saved")
    eq(F.lwin_saved[4].point[5], 65, "drag (align): the aligned y is saved")
    eq(guides.shown, false, "drag (align): the guides hide on drop")
end

--=========================================================================================
-- 7) the HUD's own save seam (hud_x/hud_y + apply_settings)
--=========================================================================================
do
    local b = build({ hands = { "mainhand" }, practice = false })
    local d, F = b.st.designmode, b.sb
    d.enter()
    local hud = F.element.hud
    hud.cx, hud.cy = 300, 0
    hud.derive_rect = true
    hud.w, hud.h = 100, 20
    local o = overlay_for(F, "Cooldown HUD")
    F.cursor_x, F.cursor_y = 0, 0
    o:GetScript("OnDragStart")(o)
    -- raw centre (300, 0): the mid line 0 magnetises y exactly to the screen centre;
    -- x has no line in reach and its low edge 250 quantises to 240 -> centre 290.
    eq(last_point(hud)[4], 290, "HUD drag: the low edge lands on the grid")
    eq(last_point(hud)[5], 0, "HUD drag: the centre line magnetises to the screen centre")
    o:GetScript("OnDragStop")(o)
    eq(F.class_db.hud_x, 290, "HUD drag: the save seam stores the snapped x")
    eq(F.class_db.hud_y, 0, "HUD drag: the save seam stores the snapped y")
    eq(F.hud_apply, 2, "HUD drag: the module re-applies after the save (enter + save)")

    -- The practice panel's own save path.
    local p = build({ hands = { "mainhand" } })
    p.st.designmode.enter()
    local po = overlay_for(p.sb, "Practice panel")
    po:GetScript("OnDoubleClick")(po)   -- exercises the reset path first
    local saves = p.sb.practice_saves
    po.target.cx, po.target.cy = 12, 34
    p.sb.cursor_x, p.sb.cursor_y = 12, 34
    po:GetScript("OnDragStart")(po)
    po:GetScript("OnDragStop")(po)
    eq(p.sb.practice_saves, saves + 1, "practice drag: the panel's own save_position runs")
end

--=========================================================================================
-- 8) double-click reset calls each element's reset
--=========================================================================================
do
    local b = build()
    local d, F = b.st.designmode, b.sb
    d.enter()
    local hand_db = F.hand_dbs.mainhand
    hand_db.x, hand_db.y, hand_db.point = 99, -99, "TOPLEFT"
    local o = overlay_for(F, "Mainhand bar")
    o:GetScript("OnDoubleClick")(o)
    eq(hand_db.x, 11, "reset (bar): the class hand default is restored (x)")
    eq(hand_db.y, -22, "reset (bar): the class hand default is restored (y)")
    eq(hand_db.point, "TOPRIGHT", "reset (bar): the anchor point default is restored")
    eq(#F.lwin_restored, 1, "reset (bar): LibWindow.RestorePosition runs on the frame")
    eq(F.lwin_restored[1], F.element.bar_mainhand, "reset (bar): ...on the element's anchor frame")

    -- The offhand falls back to the `**` shared defaults (no offhand override).
    local off_db = F.hand_dbs.offhand
    off_db.x, off_db.y, off_db.point = 1, 2, "TOP"
    local oo = overlay_for(F, "Offhand bar")
    oo:GetScript("OnDoubleClick")(oo)
    eq(off_db.x, 5, "reset (offhand): the `**` shared default is restored (x)")
    eq(off_db.y, -5, "reset (offhand): the `**` shared default is restored (y)")
    eq(off_db.point, "CENTER", "reset (offhand): a missing point falls back to CENTER")

    -- The HUD reset reads the class-level default and re-applies.
    local hud_apply = F.hud_apply
    local ho = overlay_for(F, "Cooldown HUD")
    ho:GetScript("OnDoubleClick")(ho)
    eq(F.class_db.hud_x, 33, "reset (hud): the class default is restored (x)")
    eq(F.class_db.hud_y, -333, "reset (hud): the class default is restored (y)")
    eq(F.hud_apply, hud_apply + 1, "reset (hud): the module re-applies")

    -- The rotation label uses the shared class defaults.
    local ro = overlay_for(F, "Rotation label")
    ro:GetScript("OnDoubleClick")(ro)
    eq(F.class_db.rotation_label_x, -9, "reset (rotation): the shared class default is restored (x)")
    eq(F.class_db.rotation_label_y, -150, "reset (rotation): the shared class default is restored (y)")
    eq(F.rottext_apply, 1, "reset (rotation): the module re-applies")

    -- The guide has no class override: 7/-180 from the shared defaults.
    local nag_apply = F.nag_apply
    local no = overlay_for(F, "Next action guide")
    no:GetScript("OnDoubleClick")(no)
    eq(F.class_db.nextaction_x, 7, "reset (guide): the shared default is restored (x)")
    eq(F.class_db.nextaction_y, -180, "reset (guide): the shared default is restored (y)")
    eq(F.nag_apply, nag_apply + 1, "reset (guide): the module re-applies")

    -- The practice panel resets to 0,0 with its module re-applying.
    local po = overlay_for(F, "Practice panel")
    po:GetScript("OnDoubleClick")(po)
    eq(F.class_db.practice_panel_x, 0, "reset (practice): the fallback x is 0")
    eq(F.class_db.practice_panel_y, 0, "reset (practice): the fallback y is 0")
    eq(F.practice_apply, 1, "reset (practice): the module re-applies")
end

--=========================================================================================
-- 9) exit teardown, the Esc path and toggle
--=========================================================================================
do
    local b = build()
    local d, F = b.st.designmode, b.sb
    d.enter()
    local layer = layer_of(F)
    local ovs = overlays(F)
    eq(#ovs, 6, "teardown setup: six overlays")

    d.exit()
    eq(d.is_active(), false, "exit deactivates the session")
    eq(layer.shown, false, "exit hides the layer")
    for i, o in ipairs(ovs) do
        eq(o.shown, false, "exit hides overlay " .. i)
        eq(o:GetScript("OnUpdate"), nil, "exit unhooks overlay " .. i .. "'s tick")
        eq(o.parent, F.UIParent, "exit re-parents overlay " .. i .. " to UIParent")
        eq(o.desc, nil, "exit clears overlay " .. i .. "'s element")
        eq(#o.points, 0, "exit clears overlay " .. i .. "'s points")
    end
    eq(F.visibilities, 2, "exit hands both bars back to the visibility rule")
    eq(F.notify[#F.notify], "SwedgeTimer_Options", "exit notifies the options registry")
    eq(#F.prints, 2, "exit printed the off notice")

    d.exit()
    eq(#F.prints, 3, "a second exit prints the already-off notice")
    check(F.prints[3]:find("already off", 1, true) ~= nil, "...naming the state")

    -- Esc: the layer's OnHide script tears down and prints (idempotent with exit).
    d.enter()
    eq(d.is_active(), true, "re-enter for the Esc path")
    layer:GetScript("OnHide")(layer)
    eq(d.is_active(), false, "the Esc handler stops design mode")
    eq(layer.shown, false, "the Esc handler hides the layer")
    eq(#overlays(F), 6, "the overlay pool survives the Esc teardown")
    for i, o in ipairs(overlays(F)) do
        eq(o.shown, false, "the Esc handler hides overlay " .. i)
    end
    local prints = #F.prints
    layer:GetScript("OnHide")(layer)
    eq(#F.prints, prints, "a second OnHide while inactive prints nothing")

    -- Toggle round-trips.
    d.toggle()
    eq(d.is_active(), true, "toggle enters")
    d.toggle()
    eq(d.is_active(), false, "toggle exits")
end

--=========================================================================================
-- 10) combat: refusals, the fight-start close, the lockdown guards
--=========================================================================================
do
    -- Enter refuses under lockdown with no frames and no lock writes.
    local b = build()
    b.sb.lockdown = true
    b.st.designmode.enter()
    eq(b.st.designmode.is_active(), false, "enter in combat stays inactive")
    eq(b.sb.created_frames, 0, "enter in combat creates no frames")
    eq(#b.sb.prints, 1, "enter in combat prints the reason")
    check(b.sb.prints[1]:find("can't start in combat", 1, true) ~= nil, "...naming combat")
    eq(b.sb.class_db.timers_locked, true, "enter in combat writes no lock keys")
    eq(b.sb.unlock_frames, 0, "enter in combat does not unlock")

    -- Enter before init refuses too.
    local p = build({ interfaces = false })
    p.st.designmode.enter()
    eq(p.st.designmode.is_active(), false, "enter before init stays inactive")
    eq(p.sb.created_frames, 0, "enter before init creates no frames")
    check(p.sb.prints[1]:find("still loading", 1, true) ~= nil, "...naming the loading state")

    -- Exit refuses under lockdown; the session survives until the fight-start close.
    local c = build()
    local d, F = c.st.designmode, c.sb
    d.enter()
    F.lockdown = true
    d.exit()
    eq(d.is_active(), true, "exit in combat is refused")
    check(F.prints[#F.prints]:find("can't be toggled in combat", 1, true) ~= nil, "...with the reason")
    -- Per-overlay handlers bail under lockdown too (no drag, no reset).
    local o = overlay_for(F, "Mainhand bar")
    local before_x = F.hand_dbs.mainhand.x
    o:GetScript("OnDragStart")(o)
    eq(o.dragging, nil, "drag start under lockdown is refused")
    o:GetScript("OnDoubleClick")(o)
    eq(F.hand_dbs.mainhand.x, before_x, "double-click reset under lockdown is refused")
    -- A fight starting closes the session (quiet stop + one notice).
    local prints = #F.prints
    d.on_combat_start()
    eq(d.is_active(), false, "combat start closes the session")
    eq(layer_of(F).shown, false, "combat start hides the layer")
    eq(#F.prints, prints + 1, "combat start prints one notice")
    check(F.prints[#F.prints]:find("combat started", 1, true) ~= nil, "...naming combat")
    eq(F.class_db.timers_locked, true, "combat start restores the locks")

    -- The refresh tick bails under lockdown and runs after it ends.
    local r = build({ practice_active = false })
    local rd, RF = r.st.designmode, r.sb
    rd.enter()
    local layer = layer_of(RF)
    RF.practice_active = true
    RF.lockdown = true
    layer:GetScript("OnUpdate")(layer, 10)
    eq(#overlays(RF), 5, "the refresh tick bails under lockdown")
    RF.lockdown = false
    layer:GetScript("OnUpdate")(layer, 10)
    eq(#overlays(RF), 6, "the tick refreshes once lockdown ends")
end

--=========================================================================================
-- 11) the refresh pool: elements appearing / disappearing
--=========================================================================================
do
    local b = build({ practice_active = false })
    local d, F = b.st.designmode, b.sb
    d.enter()
    eq(#shown_overlay_titles(F), 5, "practice session off: no practice overlay")

    -- A session starts: the panel becomes available and refresh adds its overlay.
    F.practice_active = true
    local frames = F.created_frames
    d.refresh()
    eq(#shown_overlay_titles(F), 6, "the running practice panel gains an overlay on refresh")
    eq(shown_overlay_titles(F)[6], "Practice panel", "...labelled as the practice panel")
    eq(F.created_frames, frames + 1, "one overlay frame is created for it")

    -- The panel hides: its overlay goes away without touching the pool.
    F.element.practice.shown = false
    d.refresh()
    eq(#shown_overlay_titles(F), 5, "a hidden element loses its overlay")
    eq(F.created_frames, frames + 1, "hiding reuses the pool (no new frame)")

    -- It comes back: the pooled overlay is reused, no new frame.
    F.element.practice.shown = true
    d.refresh()
    eq(#shown_overlay_titles(F), 6, "the element reappears on refresh")
    eq(F.created_frames, frames + 1, "reappearing reuses the pooled overlay")

    -- The session ends: availability hides it even while the panel frame is shown.
    F.practice_active = false
    d.refresh()
    eq(#shown_overlay_titles(F), 5, "an unavailable element is skipped even while its frame is shown")
    local practice_overlay = overlays(F)[6]
    eq(practice_overlay.shown, false, "the dropped overlay is hidden")
    eq(practice_overlay.desc, nil, "the dropped overlay lets go of its element")
    eq(practice_overlay.fontstrings[1].text, "Practice panel", "the pooled overlay keeps its label")

    -- refresh while inactive is a no-op.
    local idle = build()
    idle.st.designmode.refresh()
    eq(#idle.sb.frames, 0, "refresh while inactive creates nothing")
end

--=========================================================================================
-- 12) the C3 zone service: registration, priority order, dispatch, removal
--=========================================================================================
do
    -- Nothing registered: dispatch reads no frame and raises nothing.
    local idle = build()
    idle.ST:update_zones("mainhand")
    check(true, "update_zones with no zones is a no-op")

    local b = build()
    local F, ST = b.sb, b.ST

    local calls = {}
    local h_late = ST:register_zone("late",
        function(ctx) calls[#calls + 1] = "late:" .. ctx.hand end, 20)
    ST:register_zone("early", function() calls[#calls + 1] = "early" end, -5)
    local h_mid = ST:register_zone("mid", function() calls[#calls + 1] = "mid" end, 0)
    check(type(h_late) == "table" and h_late.zone_id == "late", "register_zone returns a handle")
    eq(h_late.priority, 20, "the handle carries the priority")
    eq(ST.zones.count, 3, "the zone count tracks registrations")
    check(h_late.unregister ~= nil and h_late.set_priority ~= nil, "the handle exposes its seams")

    -- Invalid registrations are rejected without touching the registry.
    local bad, err = ST:register_zone("", function() end)
    eq(bad, nil, "an empty zone id is rejected")
    check(type(err) == "string" and err:find("zone_id") ~= nil, "...naming zone_id")
    eq(ST:register_zone("x", nil), nil, "a non-function draw_fn is rejected")
    local dup, duperr = ST:register_zone("mid", function() end, 5)
    eq(dup, nil, "a duplicate zone id is rejected")
    check(type(duperr) == "string" and duperr:find("duplicate") ~= nil, "...naming the duplicate")
    eq(ST.zones.count, 3, "a rejected registration changes nothing")

    -- Dispatch: ascending priority, ctx filled from the hand state (one reused table).
    ST.mainhand.current_progress = 0.25
    ST:update_zones("mainhand")
    eq(#calls, 3, "dispatch calls every zone once")
    eq(calls[1], "early", "the lowest priority runs first")
    eq(calls[2], "mid", "the default priority runs in the middle")
    eq(calls[3], "late:mainhand", "the highest priority runs last and sees the hand")

    local seen
    ST:register_zone("probe", function(ctx) seen = ctx; calls[#calls + 1] = "probe" end, 1)
    ST:update_zones("mainhand")
    eq(seen.hand, "mainhand", "ctx.hand is the dispatched hand")
    eq(seen.frame, F.bar_frames.mainhand.visuals_frame, "ctx.frame is the hand's visuals frame")
    eq(seen.state, ST.mainhand, "ctx.state is the hand state")
    eq(seen.db, F.hand_dbs.mainhand, "ctx.db is the hand table")
    eq(seen.width, 200, "ctx.width is the measured visuals width")
    eq(seen.height, 20, "ctx.height is the measured visuals height")
    eq(seen.progress, 0.25, "ctx.progress is the bar fill fraction")
    check(type(seen.time) == "number", "ctx.time comes from the aligned clock")

    -- Reprioritising re-sorts; a junk priority is refused.
    h_mid:set_priority(99)
    calls = {}
    ST:update_zones("mainhand")
    eq(calls[1], "early", "after set_priority the order re-sorts (early)")
    eq(calls[2], "probe", "...then the probe")
    eq(calls[3], "late:mainhand", "...then late")
    eq(calls[4], "mid", "the reprioritised zone runs last")
    eq(h_mid:set_priority("junk"), false, "a junk priority is refused")
    eq(h_mid.priority, 99, "the refused priority leaves the handle unchanged")

    -- Unregistration removes the zone from list and map; a second call is a no-op.
    eq(h_late:unregister(), true, "unregister removes the zone")
    eq(h_late:unregister(), false, "a second unregister is a no-op")
    eq(ST.zones.by_id["late"], nil, "the removed zone leaves the id map")
    eq(ST.zones.count, 3, "the count drops")
    calls = {}
    ST:update_zones("mainhand")
    eq(#calls, 3, "the removed zone is not dispatched")
    eq(h_late:set_priority(0), false, "a removed handle cannot reprioritise itself back in")
    check(ST:register_zone("late", function() end, 0) ~= nil, "a freed zone id can register again")
end

--=========================================================================================
-- 13) the D3 pips widget: the frozen contract (set 0-5, glow_full) and geometry
--=========================================================================================
do
    local b = build()
    local ST, F = b.ST, b.sb

    eq(ST:new_pips(nil, {}), nil, "new_pips without a parent -> nil")
    eq(ST:new_pips({}, {}), nil, "new_pips with a non-frame parent -> nil")

    local pips = ST:new_pips(F.element.hud, { design = false })
    check(type(pips) == "table", "new_pips returns a frame")
    eq(type(pips.set), "function", "the pips frame exposes set")
    eq(type(pips.glow_full), "function", "the pips frame exposes glow_full")
    eq(#pips.textures, 5, "five pip textures are created")
    eq(pips.w, 58, "the default row is five 10 px pips with 2 px gaps")
    eq(pips.h, 10, "the row is one pip tall")
    eq(pips.points[1][1], "BOTTOM", "the row anchors to the parent's bottom by default")
    eq(pips.points[1][4], 0, "the default x offset is 0")
    for i = 1, 5 do
        eq(pips.textures[i].w, 10, "pip " .. i .. " takes the default size")
        eq(pips.textures[i].points[1][4], (i - 1) * 12, "pip " .. i .. " steps by size + gap")
        eq(pips.textures[i].color[1], 1, "pip " .. i .. " is a white base texture")
    end

    -- set(0..5): filled pips take the fill colour, the rest the dimmed hue.
    local function cell(i) return pips.textures[i].vertex end
    pips:set(3)
    near(cell(1)[1], 1, 1e-9, "set(3): pip 1 fill red")
    near(cell(1)[2], 210 / 255, 1e-9, "set(3): pip 1 fill green")
    near(cell(1)[3], 64 / 255, 1e-9, "set(3): pip 1 fill blue")
    near(cell(1)[4], 1, 1e-9, "set(3): pip 1 is opaque")
    near(cell(3)[4], 1, 1e-9, "set(3): pip 3 is filled")
    near(cell(4)[4], 0.15, 1e-9, "set(3): pip 4 is empty (dimmed)")
    near(cell(5)[4], 0.15, 1e-9, "set(3): pip 5 is empty (dimmed)")

    pips:set(5)
    near(cell(5)[4], 1, 1e-9, "set(5): every pip is filled")
    pips:set(9)
    near(cell(5)[4], 1, 1e-9, "set(9): clamps to the pip count")
    pips:set(-3)
    near(cell(1)[4], 0.15, 1e-9, "set(-3): clamps to 0")
    pips:set(nil)
    near(cell(1)[4], 0.15, 1e-9, "set(nil): reads as 0 (never stale pips)")
    pips:set("junk")
    near(cell(1)[4], 0.15, 1e-9, "set('junk'): reads as 0")
    pips:set(2.6)
    near(cell(3)[4], 1, 1e-9, "set(2.6): rounds to the nearest pip")

    -- glow_full(bool): the gold pulse shows only while the count is full.
    local starts = b.sb.glow_starts
    pips:set(5)
    pips:glow_full(true)
    eq(b.sb.glow_starts, starts + 1, "glow_full(true) at full starts the pulse")
    eq(b.sb.glow_last.frame, pips, "the pulse targets the pips frame")
    near(b.sb.glow_last.color[1], 1, 1e-9, "the pulse is gold (red)")
    pips:set(4)
    eq(b.sb.glow_stops, 1, "dropping below full stops the pulse")
    pips:set(5)
    eq(b.sb.glow_starts, starts + 2, "returning to full restarts the pulse")
    pips:glow_full(false)
    eq(b.sb.glow_stops, 2, "glow_full(false) stops it")
    pips:set(5)
    eq(b.sb.glow_starts, starts + 2, "a disarmed pulse never restarts")

    -- Custom geometry and colours.
    local custom = ST:new_pips(F.element.hud, { design = false, count = 3, size = 8, gap = 1,
        point = "TOP", x = 5, y = -3, color = { 255, 0, 0, 0.5 } })
    eq(#custom.textures, 3, "opts.count builds a shorter row")
    eq(custom.w, 26, "opts.size/gap size the row (3 * 8 + 2 * 1)")
    eq(custom.points[1][1], "TOP", "opts.point anchors the row")
    eq(custom.points[1][4], 5, "opts.x offsets the row")
    custom:set(3)
    near(custom.textures[1].vertex[1], 1, 1e-9, "opts.color: red")
    near(custom.textures[1].vertex[2], 0, 1e-9, "opts.color: no green")
    near(custom.textures[1].vertex[4], 0.5, 1e-9, "opts.color: alpha")
    custom:glow_full(true)
    eq(b.sb.glow_starts, starts + 3, "a full 3-pip row glows at its own count")
end

--=========================================================================================
-- 14) the pips as a design target and a snap-to-row template (C6)
--=========================================================================================
do
    local b = build()
    local ST, dm, F = b.ST, b.st.designmode, b.sb
    local pips = ST:new_pips(F.element.hud,
        { design = { key = "test_pips", title = "Test pips" } })
    check(dm.registry.by_key.test_pips ~= nil, "the pips registers as a design target")
    eq(dm.registry.by_key.test_pips.title, "Test pips", "the design target carries the title")
    eq(dm.registry.count, 10, "the registry grew by the pips element")
    local desc = dm.registry.by_key.test_pips
    eq(desc.get_frame(), pips, "the design target resolves the pips frame")

    -- The generic save centres the row on the dropped offsets; reset re-anchors it.
    desc.save(120, 60)
    eq(last_point(pips)[1], "CENTER", "pips save: a centre anchor")
    eq(last_point(pips)[4], 120, "pips save: the snapped x")
    eq(last_point(pips)[5], 60, "pips save: the snapped y")
    desc.reset()
    eq(last_point(pips)[1], "BOTTOM", "pips reset: the construction anchor point")
    eq(last_point(pips)[2], F.element.hud, "pips reset: re-anchored to the parent")

    -- A caller's own save/reset seams win.
    local saved, reset = 0, 0
    ST:new_pips(F.element.hud, { design = { key = "custom_pips",
        save = function() saved = saved + 1 end,
        reset = function() reset = reset + 1 end } })
    local d2 = dm.registry.by_key.custom_pips
    d2.save(1, 2)
    eq(saved, 1, "a caller save seam replaces the generic one")
    d2.reset()
    eq(reset, 1, "a caller reset seam replaces the generic one")

    -- design = false opts out; an unnamed pips takes an auto key.
    ST:new_pips(F.element.hud, { design = false })
    eq(dm.registry.by_key.pips_3, nil, "design = false opts out of registration")
    check(ST:new_pips(F.element.hud) ~= nil, "an unnamed pips still builds")
    check(dm.registry.by_key.pips_4 ~= nil, "an unnamed pips takes an auto design key")

    -- The row also registers a snap template of its own cells.
    local tpl = dm.templates.by_id.test_pips_cells
    check(tpl ~= nil, "the pips row registers a snap template")
    eq(dm.templates.count, 3, "every registered pips row contributes a template")
    local pf = desc.get_frame()
    pf.cx, pf.cy = 300, 100
    local cells = tpl.get_cells()
    eq(#cells, 5, "the template exposes the row's five cells")
    eq(cells[1].l, 271, "cell 1: left edge")
    eq(cells[1].r, 281, "cell 1: right edge")
    eq(cells[1].t, 105, "cell 1: top")
    eq(cells[1].b, 95, "cell 1: bottom")
    eq(cells[3].l, 295, "cell 3: left edge")
    eq(cells[5].r, 329, "cell 5: right edge")
    check(tpl.get_cells() == cells, "the template reuses its cell slots")
    pf.cx, pf.cy = nil, nil
    eq(tpl.get_cells(), nil, "an unreadable frame -> no cells")

    -- Template registration validation and removal.
    eq(dm.register_template(nil), nil, "register_template: nil is refused")
    eq(dm.register_template({ id = "x" }), nil, "register_template: a missing get_cells is refused")
    local dup = dm.register_template({ id = "test_pips_cells", get_cells = function() return {} end })
    eq(dup, nil, "register_template: a duplicate id is refused")
    eq(dm.unregister_template("test_pips_cells"), true, "unregister_template removes by id")
    eq(dm.unregister_template("test_pips_cells"), false, "a second removal is a no-op")
    eq(dm.templates.count, 2, "the template count drops")
end

--=========================================================================================
-- 15) snap-to-row template integration and mouse anchoring
--=========================================================================================
do
    local b = build({ hands = { "mainhand" }, practice = false })
    local d, F = b.st.designmode, b.sb
    local bar = F.element.bar_mainhand
    bar.cx, bar.cy = 50, 60
    bar.w, bar.h = 200, 20
    local vf = F.bar_frames.mainhand.visuals_frame
    local pips = b.ST:new_pips(vf, { design = { key = "drag_pips" } })
    pips.cx, pips.cy = 300, 100
    pips.derive_rect = true

    d.enter()
    local o = overlay_for(F, "Mainhand bar")
    check(o ~= nil, "the bar overlay exists")
    local guides
    for _, f in ipairs(F.frames) do
        if f.kind == "Frame" and f.name == nil and f.all_points and f.mouse == false then guides = f end
    end
    check(guides ~= nil, "the guide frame exists")

    -- Raw centre (207, 100): the right edge 307 is exactly the fourth pip cell's left
    -- edge, which only the template offers (the row frame's own lines are 271/300/329).
    F.cursor_x, F.cursor_y = 200, 100
    o:GetScript("OnDragStart")(o)
    F.cursor_x, F.cursor_y = 357, 140
    o:GetScript("OnUpdate")(o)
    eq(last_point(bar)[4], 207, "template snap: the bar's edge lands on a pip cell edge (x)")
    eq(last_point(bar)[5], 100, "template snap: the row's centre line holds y")
    eq(guides.shown, true, "template snap: the guide lines are shown")
    eq(guides.textures[1].points[1][4], 307, "template snap: the vertical guide sits on the cell edge")
    eq(guides.textures[2].points[1][5], 100, "template snap: the horizontal guide sits on the row centre")
    o:GetScript("OnDragStop")(o)
    eq(F.lwin_saved[1].point[4], 207, "template snap: the snapped x is saved")

    -- Control: without the template the same drag can only reach the row frame's mid
    -- line (300), so the drop differs and no cell-edge guide appears.
    eq(d.unregister_template("drag_pips_cells"), true, "the snap template is removed")
    bar.cx, bar.cy = 50, 60
    F.cursor_x, F.cursor_y = 200, 100
    o:GetScript("OnDragStart")(o)
    F.cursor_x, F.cursor_y = 357, 140
    o:GetScript("OnUpdate")(o)
    eq(last_point(bar)[4], 200, "control: without the template the row frame's mid line wins")
    eq(guides.textures[1].points[1][4], 300, "control: the guide sits on the frame mid line")
    o:GetScript("OnDragStop")(o)
end

do
    local b = build({ hands = { "mainhand" }, practice = false })
    local d, F = b.st.designmode, b.sb
    d.enter()
    local bar = F.element.bar_mainhand
    bar.cx, bar.cy = 50, 60
    bar.w, bar.h = 200, 20
    local o = overlay_for(F, "Mainhand bar")

    -- Default OFF: the grab offset is preserved (raw 170,100 -> grid 172,110).
    F.class_db.design_mouse_anchor = nil
    F.cursor_x, F.cursor_y = 200, 100
    o:GetScript("OnDragStart")(o)
    F.cursor_x, F.cursor_y = 320, 140
    o:GetScript("OnUpdate")(o)
    eq(last_point(bar)[4], 172, "mouse anchor off: the grab offset is preserved (x)")
    eq(last_point(bar)[5], 110, "mouse anchor off: the grab offset is preserved (y)")

    -- ON: the element's centre follows the cursor (raw 320,140 -> grid 316,134).
    F.class_db.design_mouse_anchor = true
    bar.cx, bar.cy = 50, 60
    F.cursor_x, F.cursor_y = 200, 100
    o:GetScript("OnDragStart")(o)
    F.cursor_x, F.cursor_y = 320, 140
    o:GetScript("OnUpdate")(o)
    eq(last_point(bar)[4], 316, "mouse anchor on: the centre follows the cursor (x)")
    eq(last_point(bar)[5], 134, "mouse anchor on: the centre follows the cursor (y)")

    -- Shift keeps the free placement: the centre sits exactly on the cursor.
    F.shift = true
    bar.cx, bar.cy = 50, 60
    F.cursor_x, F.cursor_y = 200, 100
    o:GetScript("OnDragStart")(o)
    F.cursor_x, F.cursor_y = 320.3, 140.3
    o:GetScript("OnUpdate")(o)
    eq(last_point(bar)[4], 320.5, "mouse anchor + Shift: the centre half-rounds at the cursor (x)")
    eq(last_point(bar)[5], 140.5, "mouse anchor + Shift: the centre half-rounds at the cursor (y)")
    F.shift = false
    o:GetScript("OnDragStop")(o)

    -- The tooltip announces the mode while it is on.
    F.tooltip_lines = nil
    o:GetScript("OnEnter")(o)
    local found = false
    for i = 1, #(F.tooltip_lines or {}) do
        if F.tooltip_lines[i]:find("Mouse anchoring", 1, true) then found = true end
    end
    eq(found, true, "the tooltip announces mouse anchoring while on")
    F.class_db.design_mouse_anchor = nil
    F.tooltip_lines = nil
    o:GetScript("OnEnter")(o)
    found = false
    for i = 1, #(F.tooltip_lines or {}) do
        if F.tooltip_lines[i]:find("Mouse anchoring", 1, true) then found = true end
    end
    eq(found, false, "the tooltip stays quiet while off")
end

--=========================================================================================
-- 16) practice rotation + timeline as design targets (C6 handoff completion)
--=========================================================================================
do
    -- Delegation: the registry descriptors resolve through the practice
    -- module's own design_targets table (single source, never a parallel copy).
    local b = build({ practice_extras = true })
    local d, F = b.st.designmode, b.sb
    local rot_desc = d.registry.by_key.practice_rotation
    local tl_desc = d.registry.by_key.practice_timeline
    check(rot_desc ~= nil and tl_desc ~= nil, "rotation + timeline descriptors are registered")
    check(rot_desc.get_frame() ~= nil, "rotation resolves its frame through the delegate")
    check(tl_desc.get_frame() ~= nil, "timeline resolves its frame through the delegate")
    eq(rot_desc.available(), true, "rotation is available while the session runs")
    eq(tl_desc.available(), true, "timeline is available while the session runs")
    F.practice_active = false
    eq(rot_desc.available(), false, "rotation hides when the session ends")
    eq(tl_desc.available(), false, "timeline hides when the session ends")
    F.practice_active = true

    d.enter()
    local titles = shown_overlay_titles(F)
    eq(#titles, 8, "enter with a running session shows all eight overlays")
    eq(titles[6], "Practice panel", "overlay 6 is the practice panel")
    eq(titles[7], "Practice rotation display", "overlay 7 is the rotation display")
    eq(titles[8], "Practice timeline", "overlay 8 is the timeline")
    eq(F.created_frames, 2 + 8, "enter creates only the layer, guides and the 8 overlays")

    -- The session ends: availability hides both without touching the pool.
    F.practice_active = false
    d.refresh()
    eq(#shown_overlay_titles(F), 5, "a stopped session loses panel + rotation + timeline overlays")
    eq(F.created_frames, 2 + 8, "hiding reuses the pool (no new frame)")
    F.practice_active = true
    d.refresh()
    eq(#shown_overlay_titles(F), 8, "a new session brings both overlays back")
    eq(F.created_frames, 2 + 8, "reappearing reuses the pooled overlays")

    -- Drag save runs the practice module's own save seam with snapped coords:
    -- raw (-40, -200) on a 400x60 frame grids to (-40, -198); raw (100, 50)
    -- on a 200x40 frame grids to (100, 52). Timeline first: at the origin the
    -- rotation frame is too far vertically to offer lines, and once the
    -- timeline sits at (-40, -198) it is too far to disturb the rotation drag.
    local to = overlay_for(F, "Practice timeline")
    F.cursor_x, F.cursor_y = 0, 0
    to:GetScript("OnDragStart")(to)
    F.cursor_x, F.cursor_y = -40, -200
    to:GetScript("OnUpdate")(to)
    to:GetScript("OnDragStop")(to)
    eq(F.tl_saves, 1, "timeline drag runs the delegate save once")
    eq(F.tl_saved[1], -40, "timeline drag saves the snapped x")
    eq(F.tl_saved[2], -198, "timeline drag saves the grid-snapped y")
    to:GetScript("OnDoubleClick")(to)
    eq(F.tl_resets, 1, "timeline reset runs the delegate reset once")

    local ro = overlay_for(F, "Practice rotation display")
    F.cursor_x, F.cursor_y = 0, 0
    ro:GetScript("OnDragStart")(ro)
    F.cursor_x, F.cursor_y = 100, 50
    ro:GetScript("OnUpdate")(ro)
    ro:GetScript("OnDragStop")(ro)
    eq(F.rot_saves, 1, "rotation drag runs the delegate save once")
    eq(F.rot_saved[1], 100, "rotation drag saves the snapped x")
    eq(F.rot_saved[2], 52, "rotation drag saves the grid-snapped y")

    -- Double-click reset runs the module's own reset seam.
    ro:GetScript("OnDoubleClick")(ro)
    eq(F.rot_resets, 1, "rotation reset runs the delegate reset once")
end

--=========================================================================================
-- Summary
--=========================================================================================
print(string.format("%d checks, %d failed", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)
