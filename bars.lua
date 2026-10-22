------------------------------------------------------------------------------------
-- Module for all swing timer bar/widget code.
--
-- Contains:
--   - The function to initialise all the frames on addon load
--   - configuration functions that are used on init/setting change
--   - UIHANDLER objects to handle drag/drop etc behaviour
--   - OnUpdate scripts to handle the limited number of things that are
--      best done on a per-frame basis.
--   - functions to manipulate the widgets in predefined ways
------------------------------------------------------------------------------------
local addon_name, st = ...
-- Chat output policy: st.utils.print_msg (utils.lua) is the addon's single chat path,
-- and every message in this file names it explicitly. There is deliberately no local
-- alias for the client's raw global print here: a bare call to it would bypass the
-- addon's chat path, so the identifier is kept out of the file on purpose.
local LSM = LibStub("LibSharedMedia-3.0")
local LCG = LibStub("LibCustomGlow-1.0")
local floor = math.floor
---@class ST
---@field get_hand_table fun(self: ST, hand: string): table
---@field get_class_table fun(self: ST): table
---@field options_table_name string
---@field player_class string
---@field target_min_range any
---@field target_max_range any
---@field db table
---@field latency table
---@field gcd table
---@field is_cat_or_bear boolean
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
local LWIN = LibStub("LibWindow-1.1")

-- A statusbar texture fetch must never leave a bar textureless. LibSharedMedia's
-- Fetch legitimately returns nil (the key is not in the registry - a registration
-- that failed on this client - or the registered path is empty), and a nil texture
-- is an INVISIBLE bar. The chain degrades instead of giving up: the requested key ->
-- the shipped fallback key ("Minimalist", registered in main.lua) -> the client's own
-- white pixel. The fetch is pcall-guarded too, so a throwing media library cannot
-- abort the configuration pass and leave the bar without a texture.
local FALLBACK_STATUSBAR_KEY = "Minimalist"
local CLIENT_WHITE_PIXEL = "Interface\\Buttons\\WHITE8X8"

local function fetch_statusbar_texture(key)
    local ok, texture = pcall(LSM.Fetch, LSM, 'statusbar', key)
    if not ok or texture == nil then
        local ok_fallback, fallback = pcall(LSM.Fetch, LSM, 'statusbar', FALLBACK_STATUSBAR_KEY)
        if ok_fallback and fallback ~= nil then
            texture = fallback
        else
            texture = CLIENT_WHITE_PIXEL
        end
    end
    return texture
end

-- Initialize hand tables
ST.mainhand = {}
ST.offhand = {}
ST.ranged = {}

--=========================================================================================
-- Intialisation func (called once relevant libs are loaded once per hand)
--=========================================================================================
function ST:init_visuals_template(hand)
    -- Get the relevant db table.
    local db = self:get_hand_table(hand)

    -- Initialize GCD state table if not already present.
    if not self.gcd then
        self.gcd = {
            expires = 0,
            gcd1_phys_time_before_swing = 0,
            gcd1_spell_time_before_swing = 0,
        }
    end

    -- Initialize form tracking field if not already present.
    if self.is_cat_or_bear == nil then
        self.is_cat_or_bear = false
    end

    -- Make the anchor frame, which is the top-level parent of the bar
    -- visual frames in our addon, and set its initial size/position properties.
	local anchor_frame = CreateFrame(
		"Frame",
        addon_name .. "_" .. hand .. "_" .. "AnchorFrame",
        UIParent
	)
    self[hand].anchor_frame = anchor_frame

    -- Configure drag and drop handlers with LibWindow, adding a callback
    -- to the config menu to let the panel know the coords have changed.
    LWIN.RegisterConfig(anchor_frame, db)
    anchor_frame:RegisterForDrag("LeftButton")
    anchor_frame:SetScript("OnDragStart", function()
            LWIN.OnDragStart(anchor_frame)
        end
    )
    anchor_frame:SetScript("OnDragStop", function()
            LWIN.OnDragStop(anchor_frame)
            local ACR = LibStub("AceConfigRegistry-3.0")
            ACR:NotifyChange(self.options_table_name)
        end
    )

    -- Make a frame, also the size of the anchor, that will receive
    -- calls to show and hide the bar, so other addons like WeakAuras
    -- can anchor to this frame and respect show/hide but not our bar's
    -- dim settings.
    local hiding_anchor_frame = CreateFrame(
        "Frame",
        addon_name .. "_" .. hand .. "_" .. "HidingAnchorFrame",
        anchor_frame
    )
    anchor_frame.hiding_anchor_frame = hiding_anchor_frame

    -- Make a frame to house the bar components in full.
    -- This frame has to inherit from BackdropTemplate.
    local bar_frame = CreateFrame(
        "Frame",
        addon_name .. "_" .. hand .. "_" .. "TimerFrame",
        anchor_frame,
        "BackdropTemplate"
    )
    anchor_frame.bar_frame = bar_frame

    -- Now make a frame to house the progress bar components
    local visuals_frame = CreateFrame(
        "Frame",
        nil,
        bar_frame
    )
    bar_frame.visuals_frame = visuals_frame

    -- Create the swing timer bar texture
    visuals_frame.bar = visuals_frame:CreateTexture(nil, "ARTWORK")
    visuals_frame.bar:SetPoint("TOPLEFT", 0, 0)

    -- Create the GCD timer bar
    visuals_frame.gcd_bar = visuals_frame:CreateTexture(nil, "ARTWORK")
    visuals_frame.gcd_bar:Hide()

    -- Create the deadzone bar
    visuals_frame.deadzone = visuals_frame:CreateTexture(nil, "ARTWORK")

    -- Create the attack speed/swing timer texts and init them
    visuals_frame.left_text = visuals_frame:CreateFontString(nil, "OVERLAY")
    visuals_frame.center_text = visuals_frame:CreateFontString(nil, "OVERLAY")
    visuals_frame.right_text = visuals_frame:CreateFontString(nil, "OVERLAY")

    -- Create the line markers
    visuals_frame.gcd1a_marker = visuals_frame:CreateLine()
    visuals_frame.gcd1b_marker = visuals_frame:CreateLine()

    self:configure_frame_strata(hand)
    self:configure_draw_layers(hand)
    self:configure_bar_size_and_positions(hand)
    self:configure_bar_outline(hand)
    self:configure_bar_appearances(hand)
    self:configure_deadzone(hand)
    self:set_deadzone_width(hand)
    self:configure_texts(hand)
    self:configure_gcd_markers(hand)

end

------------------------------------------------------------------------------------
-- Bar configuration functions (called on frame inits and setting changes)
-- These all operate on a given hand.
------------------------------------------------------------------------------------
function ST:configure_draw_layers(hand)
    -- Sets the draw layers within the visuals frame for the swing timer
    -- bar sub-components.
    local f = self:get_visuals_frame(hand)
    f.gcd_bar:SetDrawLayer("ARTWORK", -2)
    f.deadzone:SetDrawLayer("ARTWORK", -1)
    f.gcd1a_marker:SetDrawLayer("OVERLAY", -1)
    f.gcd1b_marker:SetDrawLayer("OVERLAY", -1)
end

function ST:configure_bar_size_and_positions(hand)
    local db = self:get_hand_table(hand)

    -- First set the anchor frame and bar frames
    -- to the full size in the settings, and restore their
    -- positions with LibWindow
    local anchor_frame = self:get_anchor_frame(hand)
    anchor_frame:ClearAllPoints()
    anchor_frame:SetPoint("CENTER")
    anchor_frame:SetWidth(db.bar_width)
    anchor_frame:SetHeight(db.bar_height)
    LWIN.RestorePosition(anchor_frame)
    anchor_frame:Show()

    -- And also the hiding anchor frame.
    local hiding_anchor_frame = self:get_hiding_anchor_frame(hand)
    hiding_anchor_frame:ClearAllPoints()
    hiding_anchor_frame:SetPoint("CENTER")
    hiding_anchor_frame:SetWidth(db.bar_width)
    hiding_anchor_frame:SetHeight(db.bar_height)
    hiding_anchor_frame:Show()

    -- Might need to set the width/height of the bar_frame too
    local bar_frame = self:get_bar_frame(hand)
    bar_frame:ClearAllPoints()
    bar_frame:SetPoint("CENTER")
    bar_frame:SetWidth(db.bar_width)
    bar_frame:SetHeight(db.bar_height)

    -- For the visuals frame, we calculate a reduced size
    -- based on the backplane settings.
    -- Set it internally for use elsewhere
    local visuals_frame = self:get_visuals_frame(hand)
    local vf_width = db.bar_width - (db.border_width * 2)
    local vf_height = db.bar_height - (db.border_width * 2)
    self[hand].vf_width = vf_width
    self[hand].vf_height = vf_height
    visuals_frame:SetHeight(vf_height)
    visuals_frame:SetWidth(vf_width)

    -- And set the subcomponent anchors (where appropriate)
    -- and sizes.
    visuals_frame.bar:SetPoint("TOPLEFT", 0, 0)
    visuals_frame.bar:SetHeight(vf_height)
    visuals_frame.bar:SetWidth(vf_width)
    visuals_frame.gcd_bar:SetHeight(vf_height)
    visuals_frame.deadzone:SetHeight(vf_height)
    visuals_frame.deadzone:SetPoint("TOPRIGHT")
    visuals_frame:ClearAllPoints()
    visuals_frame:SetPoint("CENTER")
    self:configure_texts(hand)
    self:configure_gcd_markers(hand)
    self:configure_bar_outline(hand)
end

function ST:configure_frame_strata(hand)
    local frame = self:get_bar_frame(hand)
    -- Draw level and frame strata are profile-wide settings: config.lua ships both in
    -- ST.defaults.profile and the strata option setter writes them through
    -- get_profile_table. They are not per-hand keys (AceDB expands the hand tables from
    -- ST.bar_defaults, which carries neither), so reading them off the hand table made
    -- db.draw_level nil here - a nil-arithmetic crash in init_timers -> init_libs on
    -- every fresh profile (see tests/bars_state.lua, which reproduces it).
    local db = self:get_profile_table()
    frame:SetFrameLevel(db.draw_level+1)
    frame:SetFrameStrata(db.frame_strata)
end

function ST:configure_bar_appearances(hand)
    -- COnfigure textures/colors for bar and GCD underlay
    local frame = self:get_visuals_frame(hand)
    local db = self:get_hand_table(hand)
    frame.bar:SetTexture(fetch_statusbar_texture(db.bar_texture_key))
    frame.gcd_bar:SetTexture(fetch_statusbar_texture(db.gcd_texture_key))
    self:set_bar_color(hand)
    frame.gcd_bar:SetVertexColor(
        self:convert_color(db.bar_color_gcd)
    )
end

function ST:configure_gcd_markers(hand)
    -- Configure textures and marker widths.
    local db = self:get_hand_table(hand)
    local f = self:get_visuals_frame(hand)
    f.gcd1a_marker:SetColorTexture(
        self:convert_color(db.gcd1a_marker_color)
    )
    f.gcd1b_marker:SetColorTexture(
        self:convert_color(db.gcd1b_marker_color)
    )
    f.gcd1a_marker:SetThickness(db.gcd1a_marker_width)
    f.gcd1b_marker:SetThickness(db.gcd1b_marker_width)
end

function ST:configure_deadzone(hand)
	local db = self:get_hand_table(hand)
	local f = self:get_visuals_frame(hand).deadzone
    if not db.enable_deadzone then
        f:Hide()
    else
        f:Show()
    end
    f:SetTexture(fetch_statusbar_texture(db.deadzone_texture_key))
	f:SetVertexColor(
        self:convert_color(db.deadzone_bar_color)
    )
end

function ST:configure_texts(hand)
    local db = self:get_hand_table(hand)
	local frame = self:get_visuals_frame(hand)
	-- The shared font chain (utils.lua): the bar texts are written per frame, so every
	-- one of them carries a font from the start - a FontString with no font throws
	-- "Font not set" on its first SetText. A key that no longer resolves (the font
	-- lives in another addon's LSM registration) falls back through
	-- STANDARD_TEXT_FONT to the classic client font instead of handing SetFont a
	-- nil path, which would throw out of the bar build.
	local font_path = st.utils.fetch_font_path(db.text_font)
    local outlines = {
        none = "",
        outline = "OUTLINE",
        thickoutline = "THICKOUTLINE",
        monochrome = "MONOCHROME",
    }
	local opt_string = outlines[db.text_outline_key]
    local w, h = self:get_bar_visuals_width_and_height(hand)

    -------------------------------------
    -- Left text
    -------------------------------------
    -- The best center point for the x offset seems to be about 1% above normal.
    local left_text_x_offset = ((db.left_text_x_percent_offset + 1)/ 100) * w
    -- The best center point for the y offset seems to be about 5% below normal.
    local left_text_y_offset = ((db.left_text_y_percent_offset - 1)/ 100) * h
    frame.left_text:SetPoint(
        "LEFT",
        left_text_x_offset,
        left_text_y_offset
    )
    st.utils.apply_font(frame.left_text, font_path, db.text_size, opt_string)
    frame.left_text:SetTextColor(
        self:convert_color(db.text_color)
    )
    if db.left_text_enabled then
        frame.left_text:Show()
    else
        frame.left_text:Hide()
    end

    -------------------------------------
    -- Center text
    -------------------------------------
    local center_text_x_offset = ((db.center_text_x_percent_offset + 1)/ 100) * w
    local center_text_y_offset = ((db.center_text_y_percent_offset - 1)/ 100) * h
    frame.center_text:SetPoint(
        "CENTER",
        center_text_x_offset,
        center_text_y_offset
    )
    st.utils.apply_font(frame.center_text, font_path, db.text_size, opt_string)
    frame.center_text:SetTextColor(
        select(1, self:convert_color(db.text_color))
    )
    if db.center_text_enabled then
        frame.center_text:Show()
    else
        frame.center_text:Hide()
    end

    -------------------------------------
    -- Right text
    -------------------------------------
    local right_text_x_offset = ((db.right_text_x_percent_offset -1)/ 100) * w
    local right_text_y_offset = ((db.right_text_y_percent_offset - 1)/ 100) * h
	frame.right_text:SetPoint(
        "RIGHT",
        right_text_x_offset,
        right_text_y_offset
    )
    st.utils.apply_font(frame.right_text, font_path, db.text_size, opt_string)
	frame.right_text:SetTextColor(
        self:convert_color(db.text_color)
    )
    if db.right_text_enabled then
        frame.right_text:Show()
    else
        frame.right_text:Hide()
    end
end

function ST:configure_bar_outline(hand)
	local frame = self:get_bar_frame(hand)
    local db = self:get_hand_table(hand)
    frame.backdropInfo = {
        bgFile = fetch_statusbar_texture(db.background_texture_key),
		edgeFile = LSM:Fetch('border', db.border_texture_key),
        tile = true, tileSize = 16, edgeSize = db.border_width,
        -- insets = {
        --     left = db.border_width,
        --     right = db.border_width,
        --     top = db.border_width,
        --     bottom = db.border_width
        -- }
    }
    frame:ApplyBackdrop()
    frame:SetBackdropBorderColor(
        self:convert_color(db.border_color)
    )
	frame:SetBackdropColor(
        self:convert_color(db.background_color)
    )
end

function ST:configure_gcd_underlay(hand)
    local db = self:get_hand_table(hand)
	local frame = self:get_visuals_frame(hand)
    frame.gcd_bar:SetTexture(fetch_statusbar_texture(db.gcd_texture_key))
    frame.gcd_bar:SetVertexColor(
        self:convert_color(db.bar_color_gcd)
    )
    frame.gcd_bar:SetDrawLayer("ARTWORK", -2)
end

-- ST:convert_color is defined once, in main.lua (array input, 0-255 -> 0-1 scale, optional
-- alpha override). A second definition used to live HERE, reading {r=, g=, b=, a=} keys
-- instead; bars.lua loads after main.lua on every toc, so it won and every caller - all of
-- which pass 0-255 arrays - silently got 0, 0, 0, 0 for every bar/text/border/glow colour
-- (see tests/bars_state.lua). Do not re-add it: never call a cross-module colour converter
-- anything but main.lua's array contract.

--=========================================================================================
-- Property funcs
--=========================================================================================
function ST:get_bar_visuals_width_and_height(hand)
    return self[hand].vf_width, self[hand].vf_height
end

function ST:get_anchor_frame(hand)
    return self[hand].anchor_frame
end

function ST:get_hiding_anchor_frame(hand)
    return self[hand].anchor_frame.hiding_anchor_frame
end

function ST:get_visuals_frame(hand)
    return self[hand].anchor_frame.bar_frame.visuals_frame
end

function ST:get_bar_frame(hand)
    return self[hand].anchor_frame.bar_frame
end

--=========================================================================================
-- C3: unified swing-safe overlay service (registered zones)
--
-- A small registration seam for per-hand bar overlays (clip / slam / twist-style bands).
-- Additive by design: the existing band call sites (classes/*.lua) keep drawing exactly
-- as they do today; zones registered here are invoked once per bar tick by
-- onupdate_common, after the class hook. This is the differentiator against
-- SuperSwingTimer's hardcoded overlay consolidation (verify_bank C3 / §6.4): a
-- registered service instead of one fixed layout.
--
--   local handle = self:register_zone(zone_id, draw_fn, priority)
--     zone_id   unique non-empty string
--     draw_fn   function(ctx), called once per bar tick for every hand
--     priority  number, lower runs first (ties keep registration order; default 0)
--   handle = { zone_id, priority, unregister(), set_priority(p) }
--
-- ctx is one reused table (no per-tick allocation): hand, frame (the hand's visuals
-- frame), state (self[hand]), db (the hand table), width, height, time
-- (st.api.get_time()), progress (the bar fill fraction). Draw calls are isolated per
-- zone through the guarded dispatcher below (H2): a throwing zone cannot freeze the
-- bar, and the first throw per zone is reported once.
--=========================================================================================
function ST:register_zone(zone_id, draw_fn, priority)
    if type(zone_id) ~= "string" or zone_id == "" then
        return nil, "zone_id must be a non-empty string"
    end
    if type(draw_fn) ~= "function" then
        return nil, "draw_fn must be a function(ctx)"
    end
    local zones = self.zones
    if not zones then
        zones = { list = {}, by_id = {}, count = 0, seq = 0, ctx = {} }
        self.zones = zones
    end
    if zones.by_id[zone_id] then
        return nil, "duplicate zone id '" .. zone_id .. "'"
    end
    zones.seq = zones.seq + 1
    local entry = {
        zone_id = zone_id,
        draw_fn = draw_fn,
        priority = tonumber(priority) or 0,
        seq = zones.seq,
    }

    -- Ascending priority, stable by registration seq. Slots shift; the list stays dense.
    local function insert(e)
        local list = zones.list
        local at = zones.count
        while at > 1 do
            local prev = list[at - 1]
            if prev.priority > e.priority
                or (prev.priority == e.priority and prev.seq > e.seq) then
                list[at] = prev
                at = at - 1
            else
                break
            end
        end
        list[at] = e
    end

    local function remove()
        local list = zones.list
        for i = 1, zones.count do
            if list[i] == entry then
                for j = i, zones.count - 1 do
                    list[j] = list[j + 1]
                end
                list[zones.count] = nil
                zones.count = zones.count - 1
                return true
            end
        end
        return false
    end

    zones.count = zones.count + 1
    insert(entry)
    zones.by_id[zone_id] = entry

    local handle = { zone_id = zone_id, priority = entry.priority }
    function handle.unregister()
        if not zones.by_id[zone_id] then return false end
        remove()
        zones.by_id[zone_id] = nil
        return true
    end
    function handle.set_priority(_, p)
        if not zones.by_id[zone_id] then return false end
        local np = tonumber(p)
        if not np then return false end
        entry.priority = np
        handle.priority = np
        remove()
        zones.count = zones.count + 1
        insert(entry)
        return true
    end
    return handle
end

--=========================================================================================
-- Per-tick isolation (H2): a class hook or zone must never freeze the bar.
--
-- The contract itself lives in guard.lua (one implementation for the whole addon): the
-- bar fill/text are painted before these calls, so the visual stays correct even when a
-- hook throws. The first throw per site is reported once in chat; every throw is
-- counted (self.bar_hook_errors, printed by /st diag's runtime line). After
-- st.guard.QUARANTINE_THROWS the site is quarantined for the session, so a permanently
-- broken hook cannot burn a pcall every frame - the quarantine is announced, never a
-- silent removal.
--
-- What stays here is this module's own wording ("Bar update ...") and its own site
-- keys; the shared module owns the counting, the once-only report and the quarantine.
--=========================================================================================
st.guard.label("zone", "Bar update")
st.guard.label("class", "Bar update")
st.guard.label("ldb", "Bar update")

function ST:update_zones(hand)
    -- Dispatches the registered zones for one hand, ascending priority. No-op (and no
    -- clock read) while nothing is registered.
    local zones = self.zones
    if not zones or zones.count == 0 then
        return
    end
    local ctx = zones.ctx
    local state = self[hand]
    if not state then
        return
    end
    local w, h = self:get_bar_visuals_width_and_height(hand)
    ctx.hand = hand
    ctx.frame = self:get_visuals_frame(hand)
    ctx.state = state
    ctx.db = self:get_hand_table(hand)
    ctx.width = w
    ctx.height = h
    ctx.time = st.api.get_time()
    ctx.progress = state and state.current_progress or nil
    local list = zones.list
    for i = 1, zones.count do
        st.guard.run(self, "zone:" .. tostring(list[i].zone_id), list[i].draw_fn, ctx)
    end
end

--=========================================================================================
-- OnUpdate funcs
--=========================================================================================
function ST:onupdate_common(hand, elapsed)
    -- Template OnUpdate function for each bar.
    local frame = self:get_visuals_frame(hand)
    local d = self[hand]
    local t = GetTime()
    local db = self:get_hand_table(hand)
    if d.engine_dead then
        -- H1-render: no engine. Never impersonate a live 1 s cycle; paint a dim bar
        -- with an explicit degraded label instead. This is terminal for the session.
        frame.bar:SetWidth(1)
        frame.bar:SetTexCoord(0, 0, 0, 1)
        self:set_bar_texts(hand)
        if not frame._engine_dead_rendered then
            frame._engine_dead_rendered = true
            frame.bar:SetAlpha(0.35)
            frame.center_text:SetAlpha(0.8)
        end
        return
    end
    if type(d.speed) ~= "number" or type(d.start) ~= "number"
        or type(d.ends_at) ~= "number" or d.speed <= 0 then
        -- No cycle yet (idle engine before its first start): neutral sliver, no maths
        -- on nil - the old path divided nil and froze the tick.
        frame.bar:SetWidth(1)
        frame.bar:SetTexCoord(0, 0, 0, 1)
        self:set_bar_texts(hand)
        return
    end
    if not d.is_paused then
        d.current_progress = math.min(1, (t - d.start) /
            (d.ends_at - d.start)
        )
    end

    local progress = d.current_progress
    local w, h = self:get_bar_visuals_width_and_height(hand)
    -- Update the main bar's width
    local timer_width = w * progress
    frame.bar:SetWidth(max(1, timer_width))
	frame.bar:SetTexCoord(0, progress, 0, 1)

    -- Update the GCD underlay if necessary.
    if db.show_gcd_underlay and self.gcd.expires then
        self:set_gcd_width(hand, timer_width, progress)
    end

    -- If any gcd marker is anchored to the swing, handle
    -- that here.
    if db.gcd1a_marker_enabled and db.gcd1a_marker_anchor == "swing" then
        local gcd_d = self:get_gcd_marker_duration(hand, '1a')
        local gcd_additional_progress = gcd_d / d.speed
        local combined_progress = progress + gcd_additional_progress
        -- Hide it only if the bar is full and hide_inactive is enabled,
        -- otherwise show.
        if d.is_full and db.gcd1a_marker_hide_inactive then
            frame.gcd1a_marker:Hide()
        else
            frame.gcd1a_marker:Show()
        end
        if combined_progress > 1.0 then
            if db.gcd1a_swing_anchor_wrap then
                while combined_progress > 1.0 do
                    combined_progress = combined_progress - 1.0
                end
            else
                combined_progress = 1.0
                frame.gcd1a_marker:Hide()
            end
        end
        local offset = combined_progress * w
        local v_offset = h * db.gcd1a_marker_fractional_height * -1
        frame.gcd1a_marker:SetStartPoint("TOPLEFT", offset, 0)
        frame.gcd1a_marker:SetEndPoint("TOPLEFT", offset, v_offset)
    end
    if db.gcd1b_marker_enabled and db.gcd1b_marker_anchor == "swing" then
        local gcd_d = self:get_gcd_marker_duration(hand, '1b')
        local gcd_additional_progress = gcd_d / d.speed
        local combined_progress = progress + gcd_additional_progress
        if d.is_full and db.gcd1b_marker_hide_inactive then
            frame.gcd1b_marker:Hide()
        else
            frame.gcd1b_marker:Show()
        end
        if combined_progress > 1.0 then
            if db.gcd1b_swing_anchor_wrap then
                while combined_progress > 1.0 do
                    combined_progress = combined_progress - 1.0
                end
            else
                combined_progress = 1.0
                frame.gcd1b_marker:Hide()
            end
        end
        -- st.utils.print_msg(combined_progress)
        local offset = combined_progress * w
        local v_offset = h * db.gcd1b_marker_fractional_height
        frame.gcd1b_marker:SetStartPoint("BOTTOMLEFT", offset, 0)
        frame.gcd1b_marker:SetEndPoint("BOTTOMLEFT", offset, v_offset)
    end

    -- Set texts
    self:set_bar_texts(hand)

    -- Generic class hook for per-frame bar visuals (e.g. the paladin twist band).
    -- Isolated per tick (H2): the fill/text above already painted, so a throwing hook
    -- costs its own visuals, not the bar.
    local class = self[self.player_class]
    if class and class.on_bar_update then
        st.guard.run(self, "class:" .. tostring(self.player_class) .. ":on_bar_update",
            class.on_bar_update, self, hand)
    end

    -- C3: registered overlay zones (additive service; one table read when unused).
    if self.zones and self.zones.count > 0 then
        self:update_zones(hand)
    end

    -- LibDataBroker feed (mainhand only, see ldb.lua): the broker object is created on
    -- the first tick and throttled internally, so this stays free on the offhand/ranged
    -- bars and when no broker display is installed.
    if st.ldb and hand == "mainhand" then
        -- Isolated like the class hook and the zones above: a throwing broker feed
        -- must not escape the tick. The bar is already painted above, so an isolated
        -- feed throw costs the feed and nothing else.
        st.guard.run(self, "ldb:update", st.ldb.update, self, hand)
    end
end

ST.mainhand.onupdate = function(elapsed)
    ST:onupdate_common("mainhand", elapsed)
end

ST.offhand.onupdate = function(elapsed)
    ST:onupdate_common("offhand", elapsed)
end

ST.ranged.onupdate = function(elapsed)
    ST:onupdate_common("ranged", elapsed)
end

--=========================================================================================
-- Collections of widget altering funcs to be called on specific events/conditions
-- Some operate generally, others on a given hand.
--=========================================================================================
function ST:on_latency_update()
    -- Only the player's own hands have frames: init_timers builds iter_hands(), and the
    -- single-hand classes (PALADIN, DRUID) have no offhand/ranged anchor frame, so the
    -- old hardcoded three-hand list made post_init index a nil anchor_frame and crash on
    -- every login (see tests/bars_state.lua). Mirrors option_tables.lua's latency_setter.
    for hand in self:iter_hands() do
        self:set_deadzone_width(hand)
    end
end

function ST:on_gcd_length_change()
    -- This function fires when the *predicted length* of a GCD
    -- changes, and doesn't refer to any active GCD.
    -- Same frame set as on_latency_update: iterate the hands that exist.
    for hand in self:iter_hands() do
        self:set_gcd_marker_positions(hand)
    end
end

function ST:on_attack_speed_change(hand)
    self:set_deadzone_width(hand)
    self:set_bar_texts(hand)
    self:set_gcd_marker_positions(hand)
end

function ST:on_bar_active(hand)
    -- Called when the bar enters the active state.
    -- This is whenever the player goes from a persistently idle state
    -- to actively swinging.
    local db = self:get_hand_table(hand)
    local frame = self:get_visuals_frame(hand)
    if db.gcd1a_marker_enabled or db.gcd1b_marker_enabled then
        self:set_gcd_marker_positions(hand)
    end
    if db.enable_deadzone then
        frame.deadzone:Show()
    end
    if db.left_text_hide_inactive then
        frame.left_text:Hide()
    end
    if db.right_text_hide_inactive then
        frame.right_text:Hide()
    end
end

function ST:on_bar_inactive(hand)
    -- Called when the bar enters the inactive state.
    -- This is when the player stops swinging with a full timer for
    -- some finite and configurable period of time.
    -- st.utils.print_msg("TRIGGERING BAR INACTIVE")
    local db = self:get_hand_table(hand)
    local frame = self:get_visuals_frame(hand)
    if db.gcd1a_marker_hide_inactive then
        frame.gcd1a_marker:Hide()
    end
    if db.gcd1b_marker_hide_inactive then
        frame.gcd1b_marker:Hide()
    end
    if db.deadzone_hide_inactive then
        frame.deadzone:Hide()
    end
    if db.left_text_hide_inactive then
        frame.left_text:Hide()
    end
    if db.right_text_hide_inactive then
        frame.right_text:Hide()
    end
end

--=========================================================================================
-- Funcs to alter widgets outside of configuration changes.
-- These all operate on a given hand.
--=========================================================================================
function ST:set_gcd_width(hand, timer_width, progress)
    local frame = self:get_visuals_frame(hand)
    local tab = self[hand]
    local gcd_progress = (self.gcd.expires - tab.start) / (tab.ends_at - tab.start)
    -- if gcd would go over the end of the bar, instead use the swing timer
    -- bar progress to evalute texture coords and gcd bar width
    local w = self:get_bar_visuals_width_and_height(hand)
    if gcd_progress > 1 then
        local gcd_width = w - timer_width
        frame.gcd_bar:SetWidth(max(1, gcd_width))
        if gcd_width == 0 then
            frame.gcd_bar:Hide()
        else
            frame.gcd_bar:Show()
        end
        -- st.utils.print_msg(gcd_width)
        -- st.utils.print_msg(string.format("%f %f", progress, gcd_width))
        frame.gcd_bar:SetTexCoord(progress, 1, 0, 1)
    else
        local gcd_width = (w * gcd_progress) - timer_width
        frame.gcd_bar:Show()
        frame.gcd_bar:SetWidth(max(1, gcd_width))
        frame.gcd_bar:SetTexCoord(progress, gcd_progress, 0, 1)
    end
    frame.gcd_bar:SetPoint("TOPLEFT", timer_width, 0)
end

function ST:get_gcd_marker_duration(hand, marker)
    local db = self:get_hand_table(hand)
    if marker == '1a' then
        local t = self.gcd.gcd1_phys_time_before_swing
        if db.gcd1a_marker_mode == "spell" then
            t = self.gcd.gcd1_spell_time_before_swing
        elseif db.gcd1a_marker_mode == "form" then
            if not self.is_cat_or_bear then
                t = self.gcd.gcd1_spell_time_before_swing
            end
        end
        return t
    elseif marker == '1b' then
        local t = self.gcd.gcd1_phys_time_before_swing
        if db.gcd1b_marker_mode == "spell" then
            t = self.gcd.gcd1_spell_time_before_swing
        elseif db.gcd1b_marker_mode == "form" then
            if not self.is_cat_or_bear then
                t = self.gcd.gcd1_spell_time_before_swing
            end
        end
        return t
    end
end

function ST:set_gcd_marker_positions(hand)
    -- This function's task is to first check if any GCD markers should
    -- be shown. It then calculates the necessary offsets from the end of the bar,
    -- and sets them.
    -- st.utils.print_msg('Setting marker positions for hand: ' .. tostring(hand))
    local db_hand = self:get_hand_table(hand)
    local frame = self:get_visuals_frame(hand)
    local s = self[hand].speed
    if type(s) ~= "number" or s <= 0 then
        -- No engine cycle: no marker can be positioned. Hide both, never divide nil.
        frame.gcd1a_marker:Hide()
        frame.gcd1b_marker:Hide()
        return
    end

    local w, h = self:get_bar_visuals_width_and_height(hand)

    -- Only process if enabled
    if db_hand.gcd1a_marker_enabled then
        if db_hand.gcd1a_marker_anchor == "endofswing" then
            local t_before = self:get_gcd_marker_duration(hand, '1a')
            local progress = t_before / s
            -- If progress > 1 then the marker is pushed off the side of the bar,
            -- more than one standard swing, so *always* hide it.
            if progress >= 1 then
                frame.gcd1a_marker:Hide()
            else
                -- If the bar is full and hide_when_inactive, also hide
                if (self[hand].is_full and db_hand.gcd1a_marker_hide_inactive) then
                    frame.gcd1a_marker:Hide()
                else
                    -- If we get here, show it
                    local offset = progress * w * -1
                    local v_offset = h * db_hand.gcd1a_marker_fractional_height * -1
                    frame.gcd1a_marker:SetStartPoint("TOPRIGHT", offset, 0)
                    frame.gcd1a_marker:SetEndPoint("TOPRIGHT", offset, v_offset)
                    frame.gcd1a_marker:Show()
                end
            end
        end
    else
        frame.gcd1a_marker:Hide()
    end
    if db_hand.gcd1b_marker_enabled then
        if db_hand.gcd1b_marker_anchor == "endofswing" then
            local t_before = self:get_gcd_marker_duration(hand, '1b')
            local progress = t_before / s
            if progress >= 1 or (self[hand].is_full and db_hand.gcd1b_marker_hide_inactive) then
                frame.gcd1b_marker:Hide()
            else
                frame.gcd1b_marker:Show()
            end
            local offset = progress * w * -1
            local v_offset = h * db_hand.gcd1b_marker_fractional_height
            frame.gcd1b_marker:SetStartPoint("BOTTOMRIGHT", offset, 0)
            frame.gcd1b_marker:SetEndPoint("BOTTOMRIGHT", offset, v_offset)
        end
    else
        frame.gcd1b_marker:Hide()
    end
end

function ST:needs_range_string(hand)
    local db = self:get_hand_table(hand)
    if db.left_text_enabled and db.left_text_key == "range_finder" then
        return true
    elseif db.center_text_enabled and db.center_text_key == "range_finder" then
        return true
    elseif db.right_text_enabled and db.right_text_key == "range_finder" then
        return true
    end
    return false
end

function ST:set_bar_texts(hand)
    -- Function to set the requisite texts on the bar.
    local frame = self:get_visuals_frame(hand)
    if self[hand].engine_dead then
        -- H1-render: an explicit degraded label instead of blank/pretend values.
        frame.left_text:Hide()
        frame.right_text:Hide()
        frame.center_text:SetText("engine offline")
        frame.center_text:Show()
        return
    end
    if self[hand].is_paused then return end
    local db = self:get_hand_table(hand)
    local t = GetTime()
    local speed = self[hand].speed
    local ends_at = self[hand].ends_at
    local timer = type(ends_at) == "number" and max(0, ends_at - t) or nil
    local lookup = {
        attack_speed = type(speed) == "number"
            and format("%.1f", st.utils.simple_round(speed, 0.1)) or "",
        swing_timer = type(timer) == "number"
            and format("%.1f", st.utils.simple_round(timer, 0.1)) or "",
    }

    if self:needs_range_string(hand) then
        local min_range = self.target_min_range or ""
        min_range = tostring(min_range)
        local max_range = self.target_max_range or ""
        max_range = tostring(max_range)

        if self.target_min_range == nil and self.target_max_range == nil then
            lookup.range_finder = ""
        elseif self.target_min_range == nil then
            lookup.range_finder = format("N/A - %s", max_range)
        elseif self.target_max_range == nil then
            lookup.range_finder = format("%s - N/A", min_range)
        else
            lookup.range_finder = format("%s - %s", min_range, max_range)
        end
    end

    if db.left_text_enabled then
        if db.left_text_hide_inactive and self[hand].is_full then
            frame.left_text:Hide()
        else
            local text = lookup[db.left_text_key]
            frame.left_text:SetText(text)
            frame.left_text:Show()
        end
    else
        frame.left_text:Hide()
    end

    if db.center_text_enabled then
        if db.center_text_hide_inactive and self[hand].is_full then
            frame.center_text:Hide()
        else
            local text = lookup[db.center_text_key]
            frame.center_text:SetText(text)
            frame.center_text:Show()
        end
    else
        frame.center_text:Hide()
    end

    if db.right_text_enabled then
        if db.right_text_hide_inactive and self[hand].is_full then
            frame.right_text:Hide()
        else
            local text = lookup[db.right_text_key]
            frame.right_text:SetText(text)
            frame.right_text:Show()
        end
    else
        frame.right_text:Hide()
    end
end

function ST:set_deadzone_width(hand)
    -- st.utils.print_msg('call to set deadzone width for '..hand)
    local db = self:get_hand_table(hand)
    local frame = self:get_visuals_frame(hand).deadzone
    local speed = self[hand].speed
    if type(speed) ~= "number" or speed <= 0 then
        -- No engine cycle to scale against (the inert stand-in): hide, never divide nil.
        frame:Hide()
        return
    end
    local db_shared = self.db.profile
    local frac = (self.latency.world_ms / 1000) / speed
    frac = frac * db_shared.deadzone_scale_factor
    local w = self:get_bar_visuals_width_and_height(hand)
    frame:SetWidth(max(1, frac * w))

    -- Determine if to show or hide.
    if not db.enable_deadzone then
        frame:Hide()
        return
    end
    if db.deadzone_hide_inactive and self[hand].is_full then
        frame:Hide()
        return
    end
    frame:Show()
end

function ST:set_bar_color(hand, color_table)
    local db = self:get_hand_table(hand)
    local frame = self:get_visuals_frame(hand)

    -- If given a manual color, set that.
    if color_table then
        frame.bar:SetVertexColor(
            unpack(color_table)
        )
        return
    end

    -- If a class override exists, use it.
    local result = false
    if self[self.player_class].set_bar_color then
        result = self[self.player_class].set_bar_color(self, hand)
    end

    -- If no special behaviour was triggered, revert to the default.
    if not result then
        frame.bar:SetVertexColor(
            self:convert_color(db.bar_color_default)
        )
    end
end

--=========================================================================================
-- D3: generic combo-point pips (frozen contract for the parallel druid lane)
--
--   local pips = ST:new_pips(parent, opts)
--     -> a frame with :set(count 0-5) and :glow_full(bool)
--
-- Five-rect row (verify_bank D3 row: the Wago feral-pack standard). Filled pips take
-- opts.color (default gold), empty pips the same hue dimmed; glow_full(true) arms the
-- gold pulse (LibCustomGlow PixelGlow), shown while the count is full. All opts are
-- optional: count, size, gap, point, x, y, color, empty_color, glow_color (0-255 rgb
-- + 0-1 alpha arrays), texture, and design = false | { key, title, save, reset }.
-- set() is nil-safe: a non-number reads as 0 (empty row, never stale pips).
--=========================================================================================
local PIPS_COUNT = 5
local PIPS_SIZE = 10
local PIPS_GAP = 2
local PIPS_COLOR = { 255, 210, 64, 1 }        -- filled pip: gold (the D3 standard)
local PIPS_EMPTY_ALPHA = 0.15                 -- empty pip: the same hue, dimmed
local PIPS_GLOW_LINES = 8
local PIPS_GLOW_FREQUENCY = 0.5
local PIPS_GLOW_LENGTH = 8
local PIPS_GLOW_THICKNESS = 1

local pips_serial = 0

function ST:new_pips(parent, opts)
    if type(parent) ~= "table" or type(parent.CreateTexture) ~= "function" then
        return nil
    end
    opts = opts or {}
    local count = floor(tonumber(opts.count) or PIPS_COUNT)
    if count < 1 then count = 1 end
    local size = tonumber(opts.size) or PIPS_SIZE
    local gap = tonumber(opts.gap) or PIPS_GAP

    pips_serial = pips_serial + 1
    local frame = CreateFrame("Frame", nil, parent)
    local total_w = count * size + (count - 1) * gap
    frame:SetSize(total_w, size)
    local point = opts.point or "BOTTOM"
    local x = tonumber(opts.x) or 0
    local y = tonumber(opts.y) or 0
    frame:SetPoint(point, parent, point, x, y)

    local fill = opts.color or PIPS_COLOR
    local fill_r, fill_g, fill_b = self:convert_color(fill)
    local empty_r, empty_g, empty_b, empty_a
    if opts.empty_color then
        empty_r, empty_g, empty_b, empty_a = self:convert_color(opts.empty_color)
    else
        empty_r, empty_g, empty_b = fill_r, fill_g, fill_b
        empty_a = PIPS_EMPTY_ALPHA
    end

    local cells = {}
    for i = 1, count do
        local cell = frame:CreateTexture(nil, "ARTWORK")
        if opts.texture then
            cell:SetTexture(opts.texture)
        else
            cell:SetColorTexture(1, 1, 1, 1)
        end
        cell:SetSize(size, size)
        cell:SetPoint("LEFT", frame, "LEFT", (i - 1) * (size + gap), 0)
        cells[i] = cell
    end

    local state = { current = 0, glow = false, glowing = false }

    local function glow_update()
        local want = state.glow and state.current >= count
        if want and not state.glowing then
            state.glowing = true
            if LCG and LCG.PixelGlow_Start then
                local gr, gg, gb, ga = self:convert_color(opts.glow_color or PIPS_COLOR)
                LCG.PixelGlow_Start(frame, { gr, gg, gb, ga or 1 },
                    PIPS_GLOW_LINES, PIPS_GLOW_FREQUENCY, PIPS_GLOW_LENGTH,
                    PIPS_GLOW_THICKNESS, 0, 0, false)
            end
        elseif not want and state.glowing then
            state.glowing = false
            if LCG and LCG.PixelGlow_Stop then
                LCG.PixelGlow_Stop(frame)
            end
        end
    end

    local function pips_set(n)
        n = floor((tonumber(n) or 0) + 0.5)
        if n < 0 then n = 0 elseif n > count then n = count end
        state.current = n
        for i = 1, count do
            local cell = cells[i]
            if i <= n then
                cell:SetVertexColor(fill_r, fill_g, fill_b, fill[4] or 1)
            else
                cell:SetVertexColor(empty_r, empty_g, empty_b, empty_a or 1)
            end
        end
        glow_update()
    end

    local function pips_glow(on)
        state.glow = on == true
        glow_update()
    end

    -- The contract is called colon-style (pips:set(3) / pips:glow_full(true)), so the
    -- attached methods drop the self argument; the inner helpers stay (n) / (on).
    frame.set = function(_, n) pips_set(n) end
    frame.glow_full = function(_, on) pips_glow(on) end

    pips_set(0)

    -- Design target (C6): every new widget registers so design mode can select/move it.
    -- opts.design = false opts out; a caller table supplies key/title and (optionally)
    -- its own save/reset db seam. Without them the drop centres the row on the offsets
    -- (session-only) and reset re-anchors it to its construction point.
    local dm = st.designmode
    local design = opts.design
    if design ~= false and dm and dm.registry then
        local dcfg = type(design) == "table" and design or {}
        local key = dcfg.key or ("pips_" .. pips_serial)
        local desc = {
            key = key,
            title = dcfg.title or "Combo points",
            get_frame = function() return frame end,
            save = dcfg.save or function(sx, sy)
                local scale = frame:GetScale() or 1
                if scale <= 0 then scale = 1 end
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", sx / scale, sy / scale)
            end,
            reset = dcfg.reset or function()
                frame:ClearAllPoints()
                frame:SetPoint(point, parent, point, x, y)
            end,
        }
        local _, err = dm.registry:register(desc)
        if err then
            st.utils.print_msg("Design mode: pips element not registered - " .. tostring(err))
        end

        -- Snap-to-row template (C6): the row's own cells join the drag magnets, so a
        -- dragged element can land on the pip rhythm. The slots are reused per tick.
        if dm.register_template and st.design and st.design.row_boxes then
            -- The row's cells sit centred on the frame: the first pip's centre is half a
            -- pip in from the frame's left edge.
            local base = st.design.row_boxes(count, size, gap, (size - total_w) / 2, 0, "x")
            local slots = {}
            for i = 1, count do
                slots[i] = { l = 0, r = 0, t = 0, b = 0 }
            end
            dm.register_template({
                id = key .. "_cells",
                get_cells = function()
                    -- Degenerate geometry (size <= 0) leaves row_boxes without cells:
                    -- return nil, the template's "not readable" contract, instead of
                    -- indexing a nil table from inside the design-mode drag handler.
                    if not base then return nil end
                    local s = (frame:GetEffectiveScale() or 1)
                        / (UIParent:GetEffectiveScale() or 1)
                    local cx, cy = frame:GetCenter()
                    local ux, uy = UIParent:GetCenter()
                    if not (cx and cy and ux and uy) then return nil end
                    local ox, oy = cx * s - ux, cy * s - uy
                    for i = 1, count do
                        local b, c = base[i], slots[i]
                        c.l = ox + b.l * s
                        c.r = ox + b.r * s
                        c.t = oy + b.t * s
                        c.b = oy + b.b * s
                    end
                    return slots
                end,
            })
        end
    end

    return frame
end


if st.debug then st.utils.print_msg('-- Parsed bars.lua module correctly') end
