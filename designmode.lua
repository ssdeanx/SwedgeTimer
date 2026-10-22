--=========================================================================================
-- Design mode: the global unlock. `/st design` (or the Design Mode options button) drops
-- a snap grid over the screen and one draggable overlay on every element this build
-- actually has:
--   * the swing bars this class uses (mainhand/offhand/ranged),
--   * the Cooldown HUD (hud.lua),
--   * the Rotation label (rotationtext.lua),
--   * the Next Action Guide (nextaction_ui.lua),
--   * the Practice panel (practice_ui.lua) while a practice session runs,
--   * the Hunter shot report and Warrior Execute report while shown.
-- Each overlay carries the element's title, drags the real frame live through the
-- element's own save path (its db keys stay the single source of truth), draws the
-- guide lines the pure design.lua maths reports while a snap is active, and resets the
-- position on double-click. Hold Shift while dragging to place freely, Alt to force the
-- exact screen centre. Esc or the same command exits; entering combat closes it.
--
-- Snap templates (C6): stacked-layout providers (DM.register_template) offer their cell
-- lines to the drag magnets, so an element can snap onto a row's rhythm. Mouse anchoring
-- (discover #17, Gnosis-style): the class key design_mouse_anchor (nil = off) centres the
-- dragged element on the cursor instead of preserving the grab offset.
--
-- Options-panel coexistence (2026-10-21 UX pass): the AceConfig options panel is the
-- AceGUI "Frame" container at FULLSCREEN_DIALOG / level 100 (Libs/AceGUI-3.0/widgets/
-- AceGUIContainer-Frame.lua, Constructor). The full-screen design chrome - the veil +
-- grid layer, the snap guides - and the per-element overlay VISUALS draw ABOVE that
-- panel and every one of them is mouse-transparent; the overlay INPUT buttons live at
-- the FULLSCREEN strata, strictly below FULLSCREEN_DIALOG, so no design surface can
-- ever swallow the panel's mouse (the panel keeps its title drag). While an options
-- window is open the layer leaves UISpecialFrames, so Esc closes the options window
-- instead of ending the design session; it returns the moment the options are gone.
-- A small movable control panel (title + Lock frames/Unlock + Exit) rides along while
-- a session runs; the lock is a session state like design mode itself - no db key,
-- nil = off, reset on enter and stop.
--
-- Ported (lean) from the archived build's editmode.lua (docs/swedge/SwedgeTimer_Forever/
-- editmode.lua). What is deliberately NOT ported, because this build has no live
-- consumers for it: the toolbar and its per-element chips with on/off switches,
-- multi-select (Ctrl mark, group drag, Select all), the quick settings cards (AceConfig
-- rows rendered beside the element, Design-mode "All settings" jump), the twist
-- simulation (Effects & sounds) panel, card/toolbar scale grips, the element preview
-- ghosts/force-show of disabled elements, and the archive's design_grid select with
-- additional design_scale/design_card_scale/design_effects_x/y keys. The archive's
-- element registry grew more elements (seal icons, twist text, practice timeline);
-- only this build's real frames are registered here.
--
-- Constraints honoured: never a protected/secure call; no frame creation in combat
-- (enter refuses under lockdown and the refresh tick bails out), every cross-element
-- position write goes through the owning module's own save/apply seam, and the drag
-- tick allocates nothing in steady state (design.lua line-list slots are reused).
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
local LWIN = LibStub("LibWindow-1.1")
local D = st.design

st.designmode = st.designmode or {}
local DM = st.designmode

local floor = math.floor

local LAYER_NAME = addon_name .. "DesignMode"
local TICK = 0.5                              -- overlay refresh cadence while unlocked
local WARM = { 1, 0.82, 0.48 }                -- the overlay/guide colour (archive warm_light)
local DIM_ALPHA = 0.35                        -- the veil over the screen while designing

-- Layering against the AceConfig options panel (the AceGUI "Frame" container:
-- FULLSCREEN_DIALOG / level 100, AceGUIContainer-Frame.lua Constructor). The chrome
-- draws above the panel and stays mouse-transparent; the per-element INPUT buttons sit
-- at the FULLSCREEN strata - below FULLSCREEN_DIALOG - so the panel's mouse (its
-- title-bar drag included) can never be swallowed by design mode. Levels are the z-order
-- inside their strata: panel (100) < veil+grid (110) < overlay visuals (130) <
-- guides (140) < control panel (150); the AceConfig validation popup stays on top at
-- TOOLTIP / 100.
local CHROME = {
    strata = "FULLSCREEN_DIALOG",             -- above the options panel
    layer = 110,                              -- veil + grid
    visual = 130,                             -- the per-element overlay visuals
    guides = 140,                             -- snap guides (over everything design)
    control = 150,                            -- the control panel
    input_strata = "FULLSCREEN",              -- below FULLSCREEN_DIALOG: input can never rise over the panel
    input_level = 1,
}

local active = false
local layer, guides
local control                                 -- the control panel (built on first enter)
local drag_locked = false                      -- session lock: overlays shown but frozen (no db key)
local overlays = {}                           -- pooled element overlays
local grid_lines = {}                         -- pooled 1px line textures on the layer
local locks_saved = {}                        -- element key -> true when design mode overrode it

-- Reusable candidate-line lists and box-line scratch for the drag tick (design.lua
-- reuses the slot tables; the lists never allocate after the first drag).
DM.lines_x, DM.lines_y = {}, {}
DM.mine_x, DM.mine_y = {}, {}

--=========================================================================================
-- Settings (the persisted keys live in the shared class defaults; enabled state does not
-- exist in the db - design mode is a session state)
--=========================================================================================
local function db()
    return ST:get_class_table()
end

local function grid_step()
    if db().design_grid_enabled == false then
        return 0
    end
    local g = tonumber(db().design_grid)
    if g and g >= D.MIN_GRID then
        return g
    end
    return 0
end

local function snap_enabled()
    return db().design_snap ~= false
end

local function snap_magnet()
    local m = tonumber(db().design_snap_threshold)
    if m and m > 0 then
        return m
    end
    return D.DEFAULT_MAGNET
end

-- Defaults for the reset paths: the current class's defaults, then the shared class
-- defaults (the `**` chain config.lua assembles).
local function class_default(key)
    local cls = ST.defaults and ST.defaults.profile and ST.defaults.profile[ST.player_class]
    if cls then
        if cls[key] ~= nil then
            return cls[key]
        end
        local shared = cls["**"]
        if shared and shared[key] ~= nil then
            return shared[key]
        end
    end
    return ST.class_defaults and ST.class_defaults[key]
end

-- Hand-level defaults: the class's hand table, then its `**` (ST.bar_defaults).
local function hand_default(hand, key)
    local cls = ST.defaults and ST.defaults.profile and ST.defaults.profile[ST.player_class]
    if cls then
        local hand_db = cls[hand]
        if hand_db and hand_db[key] ~= nil then
            return hand_db[key]
        end
        local shared = cls["**"]
        if shared and shared[key] ~= nil then
            return shared[key]
        end
    end
    return ST.bar_defaults and ST.bar_defaults[key]
end

--=========================================================================================
-- Geometry helpers (archive editmode.lua 142-180): every rect/offset in this file is an
-- offset from UIParent's centre in UIParent units - the domain the elements' own db keys
-- and apply functions already use.
--=========================================================================================
local function centre_offsets(frame)
    local s = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then
        return 0, 0
    end
    return cx * s - ux, cy * s - uy
end

local function screen_size(frame)
    local s = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return (frame:GetWidth() or 0) * s, (frame:GetHeight() or 0) * s
end

local function screen_rect(frame)
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then
        return nil
    end
    local s = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local ux, uy = UIParent:GetCenter()
    if not (ux and uy) then
        return nil
    end
    return l * s - ux, r * s - ux, t * s - uy, b * s - uy
end

local function cursor_ui()
    local s = UIParent:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    if not (x and y) then
        return nil
    end
    return x / s, y / s
end

-- Move a target frame's centre to the given offsets through the same SetPoint pattern
-- its own apply path uses (offset divided by the frame's scale).
local function move_centre(frame, x, y)
    local s = frame:GetScale() or 1
    if s <= 0 then
        s = 1
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x / s, y / s)
end

--=========================================================================================
-- Chrome: the layer (veil + grid), the centre guides, the overlays
--=========================================================================================
local function grid_line(i)
    local t = grid_lines[i]
    if not t then
        t = layer:CreateTexture(nil, "ARTWORK")
        grid_lines[i] = t
    end
    return t
end

-- The archived grid (editmode.lua 599-646): 1 px lines out from the screen centre, every
-- fourth brighter, plus an accent cross through the centre.
local function draw_grid()
    if not layer then return end
    local g = grid_step()
    local w = UIParent:GetWidth() or 1024
    local h = UIParent:GetHeight() or 768
    local cx, cy = w / 2, h / 2
    local n = 0
    local function put(vertical, offset, major, axis)
        n = n + 1
        local t = grid_line(n)
        t:ClearAllPoints()
        if axis then
            t:SetColorTexture(WARM[1], WARM[2], WARM[3], 0.28)
        else
            t:SetColorTexture(1, 1, 1, major and 0.09 or 0.045)
        end
        if vertical then
            t:SetSize(1, h)
            t:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", cx + offset, 0)
        else
            t:SetSize(w, 1)
            t:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", 0, cy + offset)
        end
        t:Show()
    end
    if g > 0 then
        put(true, 0, false, true)
        put(false, 0, false, true)
        local k = 1
        while k * g <= cx do
            put(true, k * g, k % 4 == 0)
            put(true, -k * g, k % 4 == 0)
            k = k + 1
        end
        k = 1
        while k * g <= cy do
            put(false, k * g, k % 4 == 0)
            put(false, -k * g, k % 4 == 0)
            k = k + 1
        end
    else
        -- no grid: the centre cross is the only reference
        put(true, 0, false, true)
        put(false, 0, false, true)
    end
    for i = n + 1, #grid_lines do
        grid_lines[i]:Hide()
    end
end

-- An options window counts as open while this addon's AceConfig floating dialog is
-- shown, or while the Classic Interface Options window (which hosts the AddToBlizOptions
-- embed) is shown. Every read is nil-safe: a missing global or library reports "closed".
local function options_window_open()
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
        return true
    end
    local ACD = LibStub("AceConfigDialog-3.0", true)
    local f = ACD and ACD.OpenFrames and ST.options_table_name
        and ACD.OpenFrames[ST.options_table_name]
    return (f and f:IsShown()) and true or false
end

-- Esc runs FrameXML's CloseSpecialWindows, which hides EVERY shown UISpecialFrames
-- entry (classic_era UIParentPanelManager.lua:1041-1050), and the design layer's OnHide
-- stops design mode. While an options window is open the layer therefore leaves the
-- list, so Esc closes the options window instead of killing the design session; it goes
-- back in the moment the options window is gone. Idempotent - the layer's OnUpdate
-- re-runs it every frame, so the swap happens within a frame of the panel opening or
-- closing. Only while ACTIVE does an open options window claim the entry: a stopped
-- session keeps the historic permanent registration (a hidden layer is a no-op there).
local function sync_esc_registration()
    if not layer then return end
    local idx
    for k, v in pairs(UISpecialFrames) do
        if v == LAYER_NAME then idx = k end
    end
    local want = not (active and options_window_open())
    if want and not idx then
        tinsert(UISpecialFrames, LAYER_NAME)
    elseif not want and idx then
        tremove(UISpecialFrames, idx)
    end
end

local function ensure_layer()
    if layer then return end
    layer = CreateFrame("Frame", LAYER_NAME, UIParent)
    layer:SetAllPoints(UIParent)
    -- Above the options panel, but explicitly mouse-transparent: the veil and the grid
    -- may cover the panel's pixels, never its mouse.
    layer:SetFrameStrata(CHROME.strata)
    layer:SetFrameLevel(CHROME.layer)
    layer:EnableMouse(false)
    layer.dim = layer:CreateTexture(nil, "BACKGROUND")
    layer.dim:SetAllPoints()
    layer.dim:SetColorTexture(0, 0, 0, DIM_ALPHA)
    -- Esc locks: a "special frame" is hidden by the client's Escape handler, and OnHide
    -- finishes the job (idempotent - it only runs while active). Registered through
    -- sync_esc_registration, not here, so an options window open at enter is honoured.
    layer:SetScript("OnHide", function()
        if active and options_window_open() then
            -- Esc (or anything else running CloseWindows) while an options window is
            -- open must not end the design session: the layer goes straight back up
            -- and the registration is re-synced without stopping. This is the backstop
            -- for the frame-wide gap between an options window opening and the next
            -- OnUpdate sync.
            layer:Show()
            sync_esc_registration()
            return
        end
        if active then
            DM.stop(true)
            ST:Print("Design mode off - everything locked in place.")
        end
    end)
    local acc = 0
    layer:SetScript("OnUpdate", function(_, elapsed)
        sync_esc_registration()
        acc = acc + (elapsed or 0)
        if acc < TICK then return end
        acc = 0
        DM.refresh()
    end)
    layer:Hide()
end

local function ensure_guides()
    if guides then return end
    guides = CreateFrame("Frame", nil, UIParent)
    guides:SetAllPoints(UIParent)
    guides:SetFrameStrata(CHROME.strata)
    guides:SetFrameLevel(CHROME.guides)       -- over the veil, the panel and the overlay visuals
    guides:EnableMouse(false)
    guides.v = guides:CreateTexture(nil, "OVERLAY")
    guides.v:SetColorTexture(WARM[1], WARM[2], WARM[3], 0.9)
    guides.v:SetWidth(2)
    guides.v:SetPoint("TOP", guides, "TOP", 0, 0)
    guides.v:SetPoint("BOTTOM", guides, "BOTTOM", 0, 0)
    guides.h = guides:CreateTexture(nil, "OVERLAY")
    guides.h:SetColorTexture(WARM[1], WARM[2], WARM[3], 0.9)
    guides.h:SetHeight(2)
    guides.h:SetPoint("LEFT", guides, "LEFT", 0, 0)
    guides.h:SetPoint("RIGHT", guides, "RIGHT", 0, 0)
    guides.v:Hide()
    guides.h:Hide()
    guides:Hide()
end

-- gx / gy: the vertical / horizontal guide line offsets to light (nil hides that line).
local function show_guides(gx, gy)
    if not guides then
        if not (gx or gy) then return end
        ensure_guides()
    end
    if gx then
        guides.v:ClearAllPoints()
        guides.v:SetPoint("TOP", guides, "TOP", gx, 0)
        guides.v:SetPoint("BOTTOM", guides, "BOTTOM", gx, 0)
    end
    if gy then
        guides.h:ClearAllPoints()
        guides.h:SetPoint("LEFT", guides, "LEFT", 0, gy)
        guides.h:SetPoint("RIGHT", guides, "RIGHT", 0, gy)
    end
    guides.v:SetShown(gx and true or false)
    guides.h:SetShown(gy and true or false)
    guides:SetShown((gx or gy) and true or false)
end

--=========================================================================================
-- Overlays: one labelled, draggable veil per element. All drag maths is cursor-based
-- (grab offset captured on drag start), so moving the target never feeds back into the
-- cursor position and the overlays are free to ride their targets.
--=========================================================================================
local function overlay_paint(o, hot)
    local a_fill = hot and 0.14 or 0.06
    if o.dragging then a_fill = 0 end        -- see the element itself while placing it
    local a_line = hot and 1 or 0.75
    o.fill:SetColorTexture(WARM[1], WARM[2], WARM[3], a_fill)
    local sides = o.border
    for i = 1, #sides do
        sides[i]:SetColorTexture(WARM[1], WARM[2], WARM[3], a_line)
    end
end

-- Candidate guide lines: every OTHER shown element's box lines within reach, filled into
-- the module's reusable lists (design.lua reuses the slot tables, so the tick does not
-- allocate once the slots exist). Registered snap templates offer their cells' lines too.
local function collect_lines(o, l, r, t, b)
    local lines_x, lines_y = DM.lines_x, DM.lines_y
    local nx, ny = 0, 0
    for i = 1, #overlays do
        local other = overlays[i]
        if other ~= o and other:IsShown() and other.desc and other.box then
            local or_l, or_r, or_t, or_b = screen_rect(other.box)
            if or_l then
                nx, ny = D.offer_lines(lines_x, nx, lines_y, ny,
                    or_l, or_r, or_t, or_b, other.edge_border or 0,
                    l, r, t, b, D.DEFAULT_REACH)
            end
        end
    end
    local tpls = DM.templates
    for i = 1, tpls.count do
        local tpl = tpls.list[i]
        local okc, cells = pcall(tpl.get_cells)
        if okc and type(cells) == "table" then
            local bd = tpl.border
            if type(bd) == "function" then
                local okb, bv = pcall(bd)
                bd = okb and bv or 0
            end
            local border = tonumber(bd) or 0
            for c = 1, #cells do
                local cell = cells[c]
                if type(cell) == "table" then
                    nx, ny = D.offer_lines(lines_x, nx, lines_y, ny,
                        cell.l, cell.r, cell.t, cell.b, border,
                        l, r, t, b, D.DEFAULT_REACH)
                end
            end
        end
    end
    return nx, ny
end

local drag_tick   -- forward declaration

local function make_overlay(i)
    -- Split in two frames: the INPUT button (drag/click/tooltip) lives at the
    -- FULLSCREEN strata, below the options panel, so it can never swallow the panel's
    -- mouse; the VISUAL frame (fill/border/label) rides above the panel and is
    -- mouse-transparent, so the element stays visible wherever the panel sits. Both
    -- are anchored to the same box in attach (parent stays UIParent: the strata are
    -- pinned, never inherited from the target frame).
    local o = CreateFrame("Button", nil, UIParent)
    o.is_overlay = true
    o:EnableMouse(true)
    o.visual = CreateFrame("Frame", nil, UIParent)
    o.visual:EnableMouse(false)
    o.fill = o.visual:CreateTexture(nil, "BACKGROUND")
    o.fill:SetAllPoints()
    o.border = {}
    local sides = { "top", "bottom", "left", "right" }
    for s = 1, #sides do
        local t = o.visual:CreateTexture(nil, "BORDER")
        o.border[s] = t
    end
    -- 1 px lines INSIDE the box, so the outline sits exactly on the element's edge
    local top, bottom, left, right = o.border[1], o.border[2], o.border[3], o.border[4]
    top:SetPoint("TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", 0, 0); top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", 0, 0); bottom:SetPoint("BOTTOMRIGHT", 0, 0); bottom:SetHeight(1)
    left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMLEFT", 0, 0); left:SetWidth(1)
    right:SetPoint("TOPRIGHT", 0, 0); right:SetPoint("BOTTOMRIGHT", 0, 0); right:SetWidth(1)
    o.title = o.visual:CreateFontString(nil, "OVERLAY")
    st.utils.apply_font(o.title, STANDARD_TEXT_FONT, 10, "OUTLINE")
    o.title:SetTextColor(WARM[1], WARM[2], WARM[3], 1)
    o.title:SetPoint("BOTTOMLEFT", o.visual, "TOPLEFT", 0, 1)
    o.title:SetShadowColor(0, 0, 0, 1)
    o.title:SetShadowOffset(1, -1)
    o:RegisterForDrag("LeftButton")
    o:RegisterForClicks("LeftButtonUp")
    o:SetScript("OnEnter", function(self)
        overlay_paint(self, true)
        local d = self.desc
        if d then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(d.title, 1, 1, 1)
            GameTooltip:AddLine("Drag to move  -  Shift: no snap  -  Alt: exact centre", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Double-click to reset the position", 0.8, 0.8, 0.8)
            if db().design_mouse_anchor == true then
                GameTooltip:AddLine("Mouse anchoring: the element centres on the cursor", 0.8, 0.8, 0.8)
            end
            if DM.is_locked() then
                GameTooltip:AddLine("Design is locked - use Unlock frames in the control panel to move anything",
                    1, 0.82, 0.48)
            end
            GameTooltip:Show()
        end
    end)
    o:SetScript("OnLeave", function(self)
        overlay_paint(self, false)
        GameTooltip:Hide()
    end)
    o:SetScript("OnDragStart", function(self)
        if DM.is_locked() then return end        -- frozen: visible, but not draggable
        local d, f = self.desc, self.target
        if not (d and f) then return end
        if InCombatLockdown and InCombatLockdown() then return end
        local mx, my = cursor_ui()
        if not mx then return end
        self.dragging = true
        GameTooltip:Hide()
        local cx, cy = centre_offsets(f)
        self.start_x, self.start_y = cx, cy
        self.cursor_x, self.cursor_y = mx, my
        local hug = self.box or f
        local w, h = screen_size(hug)
        self.half_w, self.half_h = w / 2, h / 2
        self:SetScript("OnUpdate", drag_tick)
        drag_tick(self)
    end)
    o:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
        show_guides(nil, nil)
        local d, f = self.desc, self.target
        if d and f and d.save and self.live_x then
            -- The element's own save path: db keys first, then its apply function.
            d.save(self.live_x, self.live_y)
        end
        DM.refresh()
    end)
    o:SetScript("OnDoubleClick", function(self)
        if DM.is_locked() then return end        -- frozen: no reset either
        local d = self.desc
        if not (d and d.reset) then return end
        if InCombatLockdown and InCombatLockdown() then return end
        d.reset()
        DM.refresh()
    end)
    overlays[i] = o
    return o
end

-- While dragging: the desired centre is the grab offset plus the cursor travel; align /
-- grid / centre-force come from design.lua. The snapped result moves the real frame
-- live and the active guide lines are drawn.
drag_tick = function(self)
    if not self.dragging then return end
    local f = self.target
    if not f then return end
    local mx, my = cursor_ui()
    if not mx then return end
    local rawx, rawy
    if db().design_mouse_anchor == true then
        -- Mouse anchoring (discover #17, Gnosis-style; nil = off): the element's centre
        -- follows the cursor, so the drop anchors the frame to the mouse.
        rawx, rawy = mx, my
    else
        rawx = self.start_x + (mx - self.cursor_x)
        rawy = self.start_y + (my - self.cursor_y)
    end
    local sx, sy, gx, gy
    if IsShiftKeyDown and IsShiftKeyDown() then
        sx, sy = D.round_half(rawx), D.round_half(rawy)
    elseif IsAltKeyDown and IsAltKeyDown() then
        sx, sy = D.centre_force(rawx, rawy, true)
        gx, gy = 0, 0
    else
        local l = rawx - self.half_w
        local r = rawx + self.half_w
        local t = rawy + self.half_h
        local b = rawy - self.half_h
        local nx, ny = collect_lines(self, l, r, t, b)
        local magnet = 0
        if snap_enabled() then
            magnet = snap_magnet()
        end
        sx, sy, gx, gy = D.snap(rawx, rawy, l, r, t, b, DM.lines_x, nx, DM.lines_y, ny,
            magnet, grid_step(), self.edge_border or 0, DM.mine_x, DM.mine_y)
        if magnet == 0 then
            gx, gy = nil, nil
        end
    end
    show_guides(gx, gy)
    move_centre(f, sx, sy)
    self.live_x, self.live_y = sx, sy
end

local function attach(o, desc, frame)
    o.desc, o.target = desc, frame
    local box = frame
    if desc.box then
        local okb, b = pcall(desc.box)
        if okb and b then
            box = b
        end
    end
    o.box = box
    local bd = desc.border
    if type(bd) == "function" then
        local okb, bv = pcall(bd)
        bd = okb and bv or 0
    end
    o.edge_border = tonumber(bd) or 0
    -- Pinned strata instead of the target's: input below the options panel (FULLSCREEN),
    -- visual above it (CHROME.strata), both on UIParent and both anchored to the element's
    -- box - so the overlay rides the target through the drag tick and the centre maths
    -- (centre_offsets / move_centre / screen_rect) never changes, while the owning
    -- module's own save path (desc.save) stays the single source of truth.
    o:SetParent(UIParent)
    o:SetFrameStrata(CHROME.input_strata)
    o:SetFrameLevel(CHROME.input_level)
    o:ClearAllPoints()
    o:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    o:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    local v = o.visual
    v:SetParent(UIParent)
    v:SetFrameStrata(CHROME.strata)
    v:SetFrameLevel(CHROME.visual)
    v:ClearAllPoints()
    v:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    v:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    o.title:SetText(desc.title)
    overlay_paint(o, false)
end

local function element_frame(desc)
    local okc, frame = pcall(desc.get_frame)
    if not okc then
        return nil
    end
    return frame
end

local function element_available(desc)
    if type(desc.available) ~= "function" then
        return true
    end
    local okc, avail = pcall(desc.available)
    return (okc and avail) and true or false
end

-- Match the overlay pool to the elements that exist: nil frames and unavailable
-- elements are skipped silently (no stub frames).
function DM.refresh()
    if not active then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local n = 0
    for i = 1, DM.registry.count do
        local desc = DM.registry.list[i]
        local frame = element_frame(desc)
        if frame and element_available(desc) and frame:IsShown() then
            n = n + 1
            local o = overlays[n] or make_overlay(n)
            if not o.dragging then
                attach(o, desc, frame)
                o:Show()
            end
            o.visual:Show()
        end
    end
    for i = n + 1, #overlays do
        local o = overlays[i]
        o:Hide()
        o.visual:Hide()
        o.desc, o.target, o.box = nil, nil, nil
    end
end

--=========================================================================================
-- Element registry: the descriptors. get_frame returns nil while a module has not built
-- its frame, so classes without the element never see an overlay.
--=========================================================================================
DM.registry = DM.registry or D.new_registry()

local function register(desc)
    local norm, err = DM.registry:register(desc)
    if not norm then
        st.utils.print_msg("Design mode: element not registered - " .. tostring(err))
    end
    return norm
end

-- The generic element-registration seam (class-isolation 2026-10-21): a class
-- module registers its OWN design elements through this entry, exactly like the
-- shared descriptors below. The shared registry therefore never names a class;
-- an inactive class simply has no elements in it. Returns the normalised
-- descriptor, or nil (with the module's own one-line notice) when it is invalid.
function DM.register_element(desc)
    return register(desc)
end

-- The swing bars: the anchor frame is the full bar rect; positions go through LibWindow
-- (the module's own save/restore path), so its x/y/point/scale keys stay authoritative.
local HAND_TITLES = { mainhand = "Mainhand bar", offhand = "Offhand bar", ranged = "Ranged bar" }

local function bar_descriptor(hand)
    return {
        key = "bar_" .. hand,
        title = HAND_TITLES[hand] or (hand .. " bar"),
        get_frame = function()
            if not ST.interfaces_are_initialised then return nil end
            return ST:get_anchor_frame(hand)
        end,
        save = function(x, y)
            local frame = ST[hand] and ST[hand].anchor_frame
            if not frame then return end
            local scale = frame:GetScale() or 1
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
            LWIN.SavePosition(frame)
        end,
        reset = function()
            local frame = ST[hand] and ST[hand].anchor_frame
            if not frame then return end
            local hand_db = ST:get_hand_table(hand)
            hand_db.x = hand_default(hand, "x")
            hand_db.y = hand_default(hand, "y")
            hand_db.point = hand_default(hand, "point") or "CENTER"
            LWIN.RestorePosition(frame)
        end,
        lock = {
            get = function() return ST:get_class_table().timers_locked ~= false end,
            set = function(locked)
                ST:get_class_table().timers_locked = locked
                if locked then
                    ST:lock_frames()
                else
                    ST:unlock_frames()
                end
            end,
        },
    }
end

register(bar_descriptor("mainhand"))
register(bar_descriptor("offhand"))
register(bar_descriptor("ranged"))

-- Class-owned design elements (seal icons, twist success text) are registered by
-- the class module itself through DM.register_element at activation
-- (class-isolation 2026-10-21 C6): this shared registry never names a class, and
-- a client on which that class is not active simply has no such elements.

-- The Cooldown HUD (hud.lua): hud_x/hud_y are UIParent-unit centre offsets; the module's
-- apply_settings owns the SetPoint/layout maths, its layout poll picks the change up.
register({
    key = "hud",
    title = "Cooldown HUD",
    get_frame = function() return st.hud and st.hud.frame end,
    save = function(x, y)
        local hdb = db()
        hdb.hud_x = floor(x + 0.5)
        hdb.hud_y = floor(y + 0.5)
        if st.hud then st.hud.apply_settings(ST) end
    end,
    reset = function()
        local hdb = db()
        hdb.hud_x = class_default("hud_x") or 0
        hdb.hud_y = class_default("hud_y") or -236
        if st.hud then st.hud.apply_settings(ST) end
    end,
    lock = {
        get = function() return db().hud_locked ~= false end,
        set = function(locked)
            db().hud_locked = locked
            if st.hud then st.hud.apply_settings(ST) end
        end,
    },
})

-- The Rotation label (rotationtext.lua): rotation_label_x/y store the offset of the
-- label's anchor edge, so the drop converts the dragged centre first (the module's own
-- save_position maths, without moving the frame twice).
register({
    key = "rottext",
    title = "Rotation label",
    get_frame = function() return st.rotation_text and st.rotation_text.frame end,
    save = function(x, y)
        local frame = st.rotation_text and st.rotation_text.frame
        if not frame then return end
        local rdb = db()
        local scale = frame:GetScale() or 1
        local w = (frame:GetWidth() or 0) * scale
        local point = st.rotation_text.anchor_point_for(rdb.rotation_label_align)
        if point == "LEFT" then
            x = x - w / 2
        elseif point == "RIGHT" then
            x = x + w / 2
        end
        rdb.rotation_label_x = floor(x + 0.5)
        rdb.rotation_label_y = floor(y + 0.5)
        st.rotation_text.apply_settings(ST)
    end,
    reset = function()
        local rdb = db()
        rdb.rotation_label_x = class_default("rotation_label_x") or 0
        rdb.rotation_label_y = class_default("rotation_label_y") or -150
        if st.rotation_text then st.rotation_text.apply_settings(ST) end
    end,
    lock = {
        get = function() return db().rotation_label_locked ~= false end,
        set = function(locked)
            db().rotation_label_locked = locked
            if st.rotation_text then st.rotation_text.apply_settings(ST) end
        end,
    },
})

-- The Next Action Guide (nextaction_ui.lua): nextaction_x/y are centre offsets and its
-- apply_settings owns the anchor maths.
register({
    key = "nag",
    title = "Next action guide",
    get_frame = function() return st.nextaction_ui and st.nextaction_ui.frame end,
    save = function(x, y)
        local ndb = db()
        ndb.nextaction_x = floor(x + 0.5)
        ndb.nextaction_y = floor(y + 0.5)
        if st.nextaction_ui then st.nextaction_ui.apply_settings(ST) end
    end,
    reset = function()
        local ndb = db()
        ndb.nextaction_x = class_default("nextaction_x") or 0
        ndb.nextaction_y = class_default("nextaction_y") or -180
        if st.nextaction_ui then st.nextaction_ui.apply_settings(ST) end
    end,
    lock = {
        get = function() return db().nextaction_locked ~= false end,
        set = function(locked)
            db().nextaction_locked = locked
            if st.nextaction_ui then st.nextaction_ui.apply_settings(ST) end
        end,
    },
})

-- The practice control panel (practice_ui.lua): shown only while a session runs; its own
-- save_position stores offsets from the bar's top-right corner and re-anchors it.
register({
    key = "practice_panel",
    title = "Practice panel",
    available = function() return st.practice_ui ~= nil and st.practice_ui.is_active() == true end,
    get_frame = function() return st.practice_ui and st.practice_ui.panel end,
    save = function(x, y)
        local panel = st.practice_ui and st.practice_ui.panel
        if not panel then return end
        panel:ClearAllPoints()
        panel:SetPoint("CENTER", UIParent, "CENTER", x, y)
        st.practice_ui.save_position(ST)
    end,
    reset = function()
        local pdb = db()
        pdb.practice_panel_x = class_default("practice_panel_x") or 0
        pdb.practice_panel_y = class_default("practice_panel_y") or 0
        if st.practice_ui then st.practice_ui.apply_settings(ST) end
    end,
})

-- The practice rotation display + timeline (practice_ui.lua ui.design_targets):
-- screen-positioned frames with session-local positions, available only while a
-- session runs. The descriptors delegate to the practice module's own table
-- (single source; the C6 handoff) and degrade silently when it is absent, so the
-- registry count stays stable in every sandbox. Bar-relative sidebars (the
-- paladin JotC mini-bar, the CD icon group, the enemy swing bar) are
-- deliberately NOT separate targets: they are children of the bar frame and
-- move with the bar overlay.
local function practice_delegate(key)
    local pui = st.practice_ui
    local targets = pui and pui.design_targets
    if type(targets) ~= "table" then
        return nil
    end
    for i = 1, #targets do
        local t = targets[i]
        if type(t) == "table" and t.key == key then
            return t
        end
    end
    return nil
end

local function practice_descriptor(key, title)
    return {
        key = key,
        title = title,
        get_frame = function()
            local d = practice_delegate(key)
            if d then
                local ok, frame = pcall(d.get_frame)
                if ok then
                    return frame
                end
            end
            return nil
        end,
        available = function()
            local d = practice_delegate(key)
            if d and d.available then
                local ok, open = pcall(d.available)
                if ok then
                    return open and true or false
                end
            end
            return false
        end,
        save = function(x, y)
            local d = practice_delegate(key)
            if d and d.save then
                d.save(x, y)
            end
        end,
        reset = function()
            local d = practice_delegate(key)
            if d and d.reset then
                d.reset()
            end
        end,
    }
end

register(practice_descriptor("practice_rotation", "Practice rotation display"))
register(practice_descriptor("practice_timeline", "Practice timeline"))
-- The post-fight reports (practice_ui.lua HunterShotReport / WarriorExecuteReport
-- frames): session-independent, available only while shown. Registered through
-- the same delegation so the count stays stable in every sandbox.
register(practice_descriptor("practice_hunter_report", "Hunter shot report"))
register(practice_descriptor("practice_warrior_report", "Warrior Execute report"))

--=========================================================================================
-- Snap templates (C6): stacked-layout providers. A template is { id, get_cells } (see
-- design.lua's normalise_template); its cell lines join the drag magnets, so an element
-- being dragged can land on a registered row's rhythm. Registered by the widgets that
-- own the layout (e.g. the pips row) and removed by id.
--=========================================================================================
DM.templates = DM.templates or { list = {}, by_id = {}, count = 0 }

function DM.register_template(t)
    local norm, err = D.normalise_template(t)
    if not norm then
        st.utils.print_msg("Design mode: template not registered - " .. tostring(err))
        return nil
    end
    local tpls = DM.templates
    if tpls.by_id[norm.id] then
        st.utils.print_msg("Design mode: template not registered - duplicate template id '"
            .. norm.id .. "'")
        return nil
    end
    tpls.count = tpls.count + 1
    tpls.list[tpls.count] = norm
    tpls.by_id[norm.id] = norm
    return norm
end

function DM.unregister_template(id)
    local tpls = DM.templates
    local tpl = tpls.by_id[id]
    if not tpl then return false end
    tpls.by_id[id] = nil
    for i = 1, tpls.count do
        if tpls.list[i] == tpl then
            for j = i, tpls.count - 1 do
                tpls.list[j] = tpls.list[j + 1]
            end
            tpls.list[tpls.count] = nil
            tpls.count = tpls.count - 1
            return true
        end
    end
    return false
end

--=========================================================================================
-- Lock overrides: while design mode runs the elements' own `locked` keys are forced off
-- so every module keeps its frame visible and positionable (their positioning rule), and
-- restored to exactly what they were on exit.
--=========================================================================================
local function unlock_elements()
    for i = 1, DM.registry.count do
        local desc = DM.registry.list[i]
        if desc.lock then
            local prev = desc.lock.get() and true or false
            if prev then
                locks_saved[desc.key] = true
                desc.lock.set(false)
            end
        end
    end
end

local function restore_locks()
    for i = 1, DM.registry.count do
        local desc = DM.registry.list[i]
        local prev = locks_saved[desc.key]
        locks_saved[desc.key] = nil
        if prev and desc.lock then
            desc.lock.set(true)
        end
    end
end

-- The bars have no per-frame "designing" preview in this build, so design mode shows the
-- class's bars directly and hands them back to the normal visibility logic on exit.
local function set_bars_designing(on)
    if not ST.interfaces_are_initialised then return end
    for hand in ST:iter_hands() do
        if ST[hand] and ST[hand].anchor_frame then
            if on then
                ST:get_bar_frame(hand):Show()
                ST:get_hiding_anchor_frame(hand):Show()
            else
                ST:handle_bar_visibility(hand)
            end
        end
    end
end

local function notify_options()
    if not ST.options_table_name then return end
    local ACR = LibStub("AceConfigRegistry-3.0", true)
    if ACR then
        ACR:NotifyChange(ST.options_table_name)
    end
end

--=========================================================================================
-- The control panel (small, movable): title + Lock/Unlock + Exit, shown while a session
-- runs. Built on the first enter - never at load, never in combat (enter refuses there)
-- - and hidden on stop. It is the only design-owned mouse surface allowed above the
-- options panel, and only over its own small rect (R1 keeps every FULL-SCREEN design
-- frame mouse-transparent). The lock is a session state like design mode itself: no db
-- key, nil = off, reset on enter and on stop.
--=========================================================================================
local function ensure_control()
    if control then return end
    control = CreateFrame("Frame", LAYER_NAME .. "Control", UIParent)
    control:SetFrameStrata(CHROME.strata)
    control:SetFrameLevel(CHROME.control)     -- over the veil, the guides and the overlays
    control:SetSize(220, 72)
    control:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -96)
    control:EnableMouse(true)
    control:SetMovable(true)
    control:RegisterForDrag("LeftButton")
    control:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        self:StartMoving()
    end)
    control:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    control.bg = control:CreateTexture(nil, "BACKGROUND")
    control.bg:SetAllPoints()
    control.bg:SetColorTexture(0, 0, 0, 0.85)
    control.border = {}
    local sides = { "top", "bottom", "left", "right" }
    for s = 1, #sides do
        local t = control:CreateTexture(nil, "BORDER")
        t:SetColorTexture(WARM[1], WARM[2], WARM[3], 0.9)
        control.border[s] = t
    end
    local top, bottom, left, right = control.border[1], control.border[2], control.border[3], control.border[4]
    top:SetPoint("TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", 0, 0); top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", 0, 0); bottom:SetPoint("BOTTOMRIGHT", 0, 0); bottom:SetHeight(1)
    left:SetPoint("TOPLEFT", 0, 0); left:SetPoint("BOTTOMLEFT", 0, 0); left:SetWidth(1)
    right:SetPoint("TOPRIGHT", 0, 0); right:SetPoint("BOTTOMRIGHT", 0, 0); right:SetWidth(1)
    control.title = control:CreateFontString(nil, "OVERLAY")
    st.utils.apply_font(control.title, STANDARD_TEXT_FONT, 11, "OUTLINE")
    control.title:SetTextColor(WARM[1], WARM[2], WARM[3], 1)
    control.title:SetPoint("TOPLEFT", control, "TOPLEFT", 10, -8)
    control.title:SetText("SwedgeTimer design mode")
    control.lock_btn = CreateFrame("Button", nil, control, "UIPanelButtonTemplate")
    control.lock_btn:EnableMouse(true)
    control.lock_btn:SetSize(120, 22)
    control.lock_btn:SetPoint("BOTTOMLEFT", control, "BOTTOMLEFT", 10, 8)
    control.lock_btn:SetScript("OnClick", function()
        DM.set_locked(not drag_locked)
    end)
    control.lock_btn:SetText("Lock frames")
    control.exit_btn = CreateFrame("Button", nil, control, "UIPanelButtonTemplate")
    control.exit_btn:EnableMouse(true)
    control.exit_btn:SetSize(76, 22)
    control.exit_btn:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT", -10, 8)
    control.exit_btn:SetScript("OnClick", function()
        DM.exit()
    end)
    control.exit_btn:SetText("Exit")
    control:Hide()
end

--=========================================================================================
-- Enter / exit
--=========================================================================================
function DM.is_active()
    return active
end

-- Session lock (control panel): while locked the overlays stay VISIBLE but refuse
-- drags and double-click resets - the frames are frozen in place. Session state only:
-- no db key is written, and a fresh session always starts unlocked.
function DM.is_locked()
    return drag_locked
end

function DM.set_locked(v)
    drag_locked = v and true or false
    if control and control.lock_btn then
        control.lock_btn:SetText(drag_locked and "Unlock frames" or "Lock frames")
    end
end

function DM.enter()
    if active then return end
    if InCombatLockdown and InCombatLockdown() then
        ST:Print("Design mode can't start in combat - try again after the fight.")
        return
    end
    if not ST.interfaces_are_initialised then
        ST:Print("SwedgeTimer is still loading - try again in a moment.")
        return
    end
    ensure_layer()
    ensure_guides()
    ensure_control()
    active = true
    DM.set_locked(false)
    sync_esc_registration()                   -- Esc ends design mode only while no options window is open
    unlock_elements()
    set_bars_designing(true)
    draw_grid()
    DM.refresh()
    layer:Show()
    control:Show()
    notify_options()
    ST:Print("Design mode on: drag an element, Shift = no snap, Alt = exact centre, double-click = reset. Esc or /st design ends it.")
end

-- The teardown is decorative + db lock flags only (no protected calls), which is what
-- lets the combat path close design mode while the client is in lockdown.
function DM.stop(quiet)
    if not active then return false end
    active = false
    DM.set_locked(false)                      -- the session lock dies with the session
    for i = 1, #overlays do
        local o = overlays[i]
        o:Hide()
        o.visual:Hide()
        o:SetScript("OnUpdate", nil)
        o.dragging = nil
        o.live_x, o.live_y = nil, nil
        o.desc, o.target, o.box = nil, nil, nil
        -- back to a neutral parent: a target frame may be hidden or rebuilt while locked
        o:SetParent(UIParent)
        o:ClearAllPoints()
    end
    show_guides(nil, nil)
    restore_locks()
    set_bars_designing(false)
    if layer then layer:Hide() end
    if control then control:Hide() end
    notify_options()
    if not quiet then
        ST:Print("Design mode off - everything locked in place.")
    end
    return true
end

function DM.exit(quiet)
    if not active then
        if not quiet then ST:Print("Design mode is already off.") end
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        if not quiet then ST:Print("Design mode can't be toggled in combat - try again after the fight.") end
        return
    end
    DM.stop(quiet)
end

function DM.toggle()
    if active then
        DM.exit()
    else
        DM.enter()
    end
end

-- Called from main.lua's PLAYER_REGEN_DISABLED handler (no extra event registration):
-- design mode closes when a fight starts, cosmetic teardown only.
function DM.on_combat_start()
    if not active then return end
    DM.stop(true)
    ST:Print("Design mode closed - combat started.")
end

-- Redraw the grid when the options change it while unlocked.
function DM.refresh_grid()
    if active then
        draw_grid()
    end
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then st.utils.print_msg('-- Parsed designmode.lua module correctly') end
