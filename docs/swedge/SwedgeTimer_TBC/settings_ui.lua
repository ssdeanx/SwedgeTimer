-- settings_ui.lua ======================================================================
-- The "Radiance" settings window for SwedgeTimer.
--
-- This module draws a custom, frame-based settings window. It does NOT own any
-- settings logic: every row is backed by an entry in the existing AceConfig options
-- table (SwedgeTimer.options) or the AceDB profiles table, and all get/set/values/
-- disabled/hidden/confirm behaviour is delegated to those entries. The page layout
-- below only decides where each option is shown. Any option that is not referenced
-- by the layout is appended automatically to a "More settings" section, so nothing
-- can silently go missing.
--
-- Art: `Images/keyart.tga` (1024x512, painting occupies the top 0.79 of the texture), drawn at native scale pushed right by ART_X, and
-- `Images/logo.tga` (128x128). Replace those files to re-skin the window; if they are
-- missing the window falls back to a procedural glow and the Seal of Command icon.
--=======================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon("SwedgeTimer")
local SML = LibStub("LibSharedMedia-3.0")
local print = st.utils.print_msg

st.settings_ui = st.settings_ui or {}
local UI = st.settings_ui

local strupper, strlower, floor, max, min, abs = string.upper, string.lower, math.floor, math.max, math.min, math.abs
local tinsert, tremove, unpack = table.insert, table.remove, unpack

--=======================================================================================
-- Theme
--=======================================================================================
local IMG = "Interface\\AddOns\\SwedgeTimer\\Images\\"
local FONT_DIR = "Interface\\AddOns\\SwedgeTimer\\Fonts\\"
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"

local FONT = {
	regular = FONT_DIR .. "Roboto-Regular.ttf",
	medium  = FONT_DIR .. "Roboto-Medium.ttf",
	bold    = FONT_DIR .. "Roboto-Bold.ttf",
	mono    = FONT_DIR .. "RobotoMono-Regular.ttf",
}

local TEX = {
	round    = IMG .. "ui_round.tga",
	circle   = IMG .. "circle_smooth.tga",
	gradient = IMG .. "ui_gradient.tga",
	glow     = IMG .. "ui_glow.tga",
	chevron  = IMG .. "ui_chevron.tga",
	close    = IMG .. "ui_close.tga",
	search   = IMG .. "ui_search.tga",
	check    = IMG .. "ui_check.tga",
	artmask  = IMG .. "ui_artmask.tga",
}

-- Expose the fonts to LibSharedMedia so they can also be used for the bar text.
SML:Register("font", "Roboto", FONT.regular)
SML:Register("font", "Roboto Bold", FONT.bold)
SML:Register("font", "Roboto Mono", FONT.mono)

local function hex(h, a)
	local r = tonumber(h:sub(1, 2), 16) / 255
	local g = tonumber(h:sub(3, 4), 16) / 255
	local b = tonumber(h:sub(5, 6), 16) / 255
	return { r, g, b, a or 1 }
end

local C = {
	bg            = hex("0c0c0f"),
	win_border    = hex("3a3c44"),
	white         = hex("ffffff"),
	text          = hex("e9eaee"),
	text_soft     = hex("c9cbd1"),
	label         = hex("a9acb5"),
	muted         = hex("9a9da6"),
	dim           = hex("6a6d76"),
	nav_group     = hex("8a8d96"),
	accent        = hex("ff8a1f"),
	accent_hover  = hex("ffa04a"),
	accent_text   = hex("1a0d00"),
	warm          = hex("ffb54a"),
	warm_light    = hex("ffd27a"),
	warm_pale     = hex("ffc86a"),
	green         = hex("57d38c"),
	panel         = hex("141418", 0.85),
	panel_border  = hex("ffffff", 0.09),
	panel_title_line = hex("ffffff", 0.1),
	panel_head    = hex("ffffff", 0.045),
	row_line      = hex("ffffff", 0.04),
	input_bg      = hex("0c0c0f", 0.70),
	input_border  = hex("ffffff", 0.12),
	input_border_hover = hex("6a6d76"),
	track_off     = hex("3a3c44"),
	nav_active    = hex("2a2b30", 0.80),
	nav_hover     = hex("1f2025"),
	tab_bar       = hex("0c0c0f", 0.90),
	tab_bar_border = hex("ffffff", 0.10),
	tab_idle_text = hex("d3d5db"),
	tab_hover     = hex("ffffff", 0.08),
	button_bg     = hex("1d1e23", 0.65),
	button_border = hex("ffffff", 0.12),
	search_bg     = hex("1d1e23", 0.65),
	search_border = hex("ffffff", 0.06),
	sidebar_fill  = hex("0c0c0f", 0.88),
	sidebar_line  = hex("ffffff", 0.08),
	content_fill  = hex("0c0c0f", 0.32),
	footer_fill   = hex("0c0c0f", 0.72),
	footer_line   = hex("ffffff", 0.08),
	swatch_border = hex("ffffff", 0.13),
}

-- Layout (the design is 1216x800; this is the same composition at ~82%)
local WIN_W, WIN_H     = 1000, 660
local SIDEBAR_W        = 250
local HEADER_H         = 118
local FOOTER_H         = 56
local RADIUS           = 12
local PAD              = 28
local CONTROL_W        = 230
local ROW_INSET        = 18
local ROW_PAD          = 12
local ROW_MIN_H        = 48
local SECTION_TITLE_H  = 40
local SECTION_GAP      = 14
local ART_H            = 390
local SCALE_MIN, SCALE_MAX = 0.4, 1.5 -- window scale limits (also capped so the window fits the screen)
local SCALE_DEFAULT    = 0.6            -- keep in sync with settings_scale in SwedgeTimer.defaults
local ART_X            = 260   -- push the key art this far right; its left edge fades into the background
local ART_NATIVE_W     = ART_H * 1024 / (512 * 0.79) -- key art width at native scale for ART_H
local PULLOUT_ITEM_H   = 26
local PULLOUT_MAX_H    = 320

local FS = {
	brand = 18, version = 11, nav_group = 10, nav_item = 14, nav_count = 11,
	group = 11, title = 30, tab = 12, section = 13, crumb = 11,
	name = 14, desc = 12, desc_row = 13, value = 12, button = 13, footer = 13,
}

--=======================================================================================
-- Small drawing helpers
--=======================================================================================
local function norm_path(p)
	return strlower(tostring(p or ""):gsub("/", "\\"))
end

-- Sets a font and falls back to Friz Quadrata when the file cannot be loaded.
local function set_font(fs, path, size)
	fs:SetFont(path, size, "")
	local current = fs:GetFont()
	if norm_path(current) ~= norm_path(path) then
		fs:SetFont(FALLBACK_FONT, size, "")
	end
end

local function create_text(parent, font, size, color, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	set_font(fs, font, size)
	if color then fs:SetTextColor(unpack(color)) end
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	return fs
end

local function set_color(fs, color)
	fs:SetTextColor(unpack(color))
end

local function create_line(parent, color, layer, sub)
	local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
	t:SetColorTexture(unpack(color))
	return t
end

-- Nine-slice rounded rectangle drawn from ui_round.tga (64px, corner radius 16px).
local SLICES = { "tl", "t", "tr", "l", "c", "r", "bl", "b", "br" }
local ALL_CORNERS = { tl = true, tr = true, bl = true, br = true }

local function new_slices(frame, layer, sub)
	local s = {}
	for _, k in ipairs(SLICES) do
		local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
		t:SetTexture(TEX.round)
		s[k] = t
	end
	return s
end

local function layout_slices(s, frame, r, inset, corners)
	local i = inset or 0
	corners = corners or ALL_CORNERS
	local function corner(k, rounded, u1, u2, v1, v2)
		if rounded then s[k]:SetTexCoord(u1, u2, v1, v2) else s[k]:SetTexCoord(0.4, 0.6, 0.4, 0.6) end
	end
	corner("tl", corners.tl, 0, 0.25, 0, 0.25)
	corner("tr", corners.tr, 0.75, 1, 0, 0.25)
	corner("bl", corners.bl, 0, 0.25, 0.75, 1)
	corner("br", corners.br, 0.75, 1, 0.75, 1)
	s.t:SetTexCoord(0.3, 0.7, 0.02, 0.25)
	s.b:SetTexCoord(0.3, 0.7, 0.75, 0.98)
	s.l:SetTexCoord(0.02, 0.25, 0.3, 0.7)
	s.r:SetTexCoord(0.75, 0.98, 0.3, 0.7)
	s.c:SetTexCoord(0.3, 0.7, 0.3, 0.7)

	for _, t in pairs(s) do t:ClearAllPoints() end
	s.tl:SetPoint("TOPLEFT", frame, "TOPLEFT", i, -i);          s.tl:SetSize(r, r)
	s.tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -i, -i);       s.tr:SetSize(r, r)
	s.bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", i, i);     s.bl:SetSize(r, r)
	s.br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -i, i);  s.br:SetSize(r, r)
	s.t:SetPoint("TOPLEFT", s.tl, "TOPRIGHT");     s.t:SetPoint("BOTTOMRIGHT", s.tr, "BOTTOMLEFT")
	s.b:SetPoint("TOPLEFT", s.bl, "TOPRIGHT");     s.b:SetPoint("BOTTOMRIGHT", s.br, "BOTTOMLEFT")
	s.l:SetPoint("TOPLEFT", s.tl, "BOTTOMLEFT");   s.l:SetPoint("BOTTOMRIGHT", s.bl, "TOPRIGHT")
	s.r:SetPoint("TOPLEFT", s.tr, "BOTTOMLEFT");   s.r:SetPoint("BOTTOMRIGHT", s.br, "TOPRIGHT")
	s.c:SetPoint("TOPLEFT", s.tl, "BOTTOMRIGHT");  s.c:SetPoint("BOTTOMRIGHT", s.br, "TOPLEFT")
end

local function color_slices(s, r, g, b, a)
	for _, t in pairs(s) do t:SetVertexColor(r, g, b, a) end
end

-- Adds a rounded background (and optional 1px border) to an existing frame.
local function add_rounded(frame, opts)
	local r = opts.radius or RADIUS
	local skin = {}
	if opts.border then
		skin.border = new_slices(frame, opts.layer or "BACKGROUND", (opts.sub or 0) - 1)
		layout_slices(skin.border, frame, r, 0, opts.corners)
		color_slices(skin.border, unpack(opts.border))
		skin.fill = new_slices(frame, opts.layer or "BACKGROUND", opts.sub or 0)
		layout_slices(skin.fill, frame, max(r - 1, 1), 1, opts.corners)
	else
		skin.fill = new_slices(frame, opts.layer or "BACKGROUND", opts.sub or 0)
		layout_slices(skin.fill, frame, r, 0, opts.corners)
	end
	color_slices(skin.fill, unpack(opts.fill or C.panel))
	function skin:SetFill(r_, g_, b_, a_) color_slices(self.fill, r_, g_, b_, a_) end
	function skin:SetBorder(r_, g_, b_, a_) if self.border then color_slices(self.border, r_, g_, b_, a_) end end
	return skin
end

local function create_panel(parent, opts, frame_type)
	local f = CreateFrame(frame_type or "Frame", nil, parent)
	f.skin = add_rounded(f, opts)
	return f
end

-- Thin scroll indicator for a ScrollFrame: a faint track with a thumb whose size and
-- position mirror the scroll range. Purely visual (the wheel does the scrolling) and
-- hidden whenever the content fits. `x` offsets it from the scroll frame's right edge.
local function add_scroll_indicator(scroll, opts)
	opts = opts or {}
	local ind = CreateFrame("Frame", nil, scroll:GetParent())
	ind:SetWidth(opts.width or 4)
	ind:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", opts.x or 0, 0)
	ind:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", opts.x or 0, 0)
	ind.track = ind:CreateTexture(nil, "BACKGROUND")
	ind.track:SetAllPoints()
	ind.track:SetColorTexture(1, 1, 1, 0.05)
	ind.thumb = ind:CreateTexture(nil, "ARTWORK")
	ind.thumb:SetTexture(TEX.round)
	ind.thumb:SetTexCoord(0.3, 0.7, 0.3, 0.7)
	ind.thumb:SetVertexColor(1, 1, 1, 0.25)
	ind.thumb:SetPoint("TOPLEFT")
	ind.thumb:SetPoint("TOPRIGHT")
	ind.thumb:SetHeight(18)
	function ind:Update()
		local view = scroll:GetHeight() or 0
		local child = scroll:GetScrollChild()
		local total = child and child:GetHeight() or 0
		local range = total - view
		if view <= 0 or range <= 0.5 then self:Hide(); return end
		local h = max(opts.min_thumb or 18, view / total * view)
		local pos = max(0, min(1, (scroll:GetVerticalScroll() or 0) / range)) * (view - h)
		self.thumb:SetHeight(h)
		self.thumb:ClearAllPoints()
		self.thumb:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -pos)
		self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -pos)
		self:Show()
	end
	local function refresh() ind:Update() end
	scroll:SetScript("OnVerticalScroll", refresh)
	scroll:SetScript("OnScrollRangeChanged", refresh)
	scroll:SetScript("OnSizeChanged", refresh)
	ind:Hide()
	return ind
end

local function fmt_hex(r, g, b)
	return string.format("#%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local function strip_codes(s)
	if type(s) ~= "string" then return "" end
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return s
end

--=======================================================================================
-- Option table access (mirrors the AceConfig semantics the addon relies on)
--=======================================================================================
local ROOTS

local function get_roots()
	if not ROOTS then
		ROOTS = { main = { table = ST.options, appName = "SwedgeTimer_Options" } }
		if ST.db then
			local ok, profiles = pcall(function() return LibStub("AceDBOptions-3.0"):GetOptionsTable(ST.db) end)
			if ok and profiles then
				ROOTS.profiles = { table = profiles, appName = "SwedgeTimer_Profiles" }
			end
		end
	end
	return ROOTS
end

-- "group.key" resolves against SwedgeTimer.options; "profiles:key" against the profiles table.
local function resolve_path(pathstr)
	local rootname, rest = pathstr:match("^(%w+):(.+)$")
	if not rootname then rootname, rest = "main", pathstr end
	local root = get_roots()[rootname]
	if not root then return nil end
	local node = root.table
	local chain, keys = { node }, {}
	for seg in rest:gmatch("[^%.]+") do
		node = node.args and node.args[seg]
		if not node then return nil end
		chain[#chain + 1] = node
		keys[#keys + 1] = seg
	end
	return { option = node, chain = chain, keys = keys, root = root, path = pathstr }
end

local function inherited(res, prop)
	for i = #res.chain, 1, -1 do
		local v = res.chain[i][prop]
		if v ~= nil then return v end
	end
end

local function make_info(res)
	local info = {}
	for i, k in ipairs(res.keys) do info[i] = k end
	info.options = res.root.table
	info.appName = res.root.appName
	info.option = res.option
	info.arg = res.option.arg
	info.type = res.option.type
	info.handler = inherited(res, "handler")
	info.uiType = "dialog"
	info.uiName = "SwedgeTimer_Settings"
	return info
end

local function call_member(member, info, ...)
	if type(member) == "function" then return member(info, ...) end
	if type(member) == "string" then
		local h = info.handler
		if h and h[member] then return h[member](h, info, ...) end
	end
end

local function eval_name(v, info)
	if type(v) == "function" then return v(info) or "" end
	return v or ""
end

local function eval_flag(v, info)
	if v == nil or v == false then return false end
	if v == true then return true end
	local r = call_member(v, info)
	return r and true or false
end

local function eval_values(res, info)
	local v = res.option.values
	if type(v) == "table" then return v end
	return call_member(v, info) or {}
end

local function get_value(res, info)
	local g = inherited(res, "get")
	if not g then return nil end
	return call_member(g, info)
end

local silent_set = false

local function do_set(res, info, ...)
	local s = inherited(res, "set")
	if s then call_member(s, info, ...) end
	if not silent_set then UI.request_refresh() end
end

local function set_value(res, info, ...)
	local confirm = inherited(res, "confirm")
	local text
	if confirm then
		if type(confirm) == "boolean" then
			text = true
		else
			text = call_member(confirm, info, ...)
		end
	end
	if text then
		if text == true then text = res.option.confirmText or "Are you sure?" end
		local args = { ... }
		local n = select("#", ...)
		UI.confirm(text, function() do_set(res, info, unpack(args, 1, n)) end)
	else
		do_set(res, info, ...)
	end
end

local function do_exec(res, info)
	local fn = inherited(res, "func")
	if fn then call_member(fn, info) end
	UI.request_refresh()
end

local function exec_option(res, info)
	local confirm = inherited(res, "confirm")
	local text
	if confirm then
		if type(confirm) == "boolean" then text = true else text = call_member(confirm, info) end
	end
	if text then
		if text == true then text = res.option.confirmText or "Are you sure?" end
		UI.confirm(text, function() do_exec(res, info) end)
	else
		do_exec(res, info)
	end
end

StaticPopupDialogs["SWEDGETIMER_CONFIRM"] = {
	text = "%s",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data) if data and data.func then data.func() end end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function UI.confirm(text, func)
	StaticPopup_Show("SWEDGETIMER_CONFIRM", text, nil, { func = func })
end

--=======================================================================================
-- Page layout. Every string is a path into the options table.
--=======================================================================================
local PAGES = {
	{ id = "general", group = "Swing Bar", label = "General", sections = {
		{ title = "Addon", rows = { "bar_enabled", "ret_only", "spec_status", "welcome_message", "minimap_button_enabled" } },
		{ title = "Design mode", rows = { "design.design_desc", "design.open_design_mode", "design.design_grid", "design.design_scale", "design.design_card_scale" } },
		{ title = "Features", rows = { "features.bar_enabled", "features.judgement_marker_enabled",
			"features.enable_deadzone", "features.bar_twist_color_enabled" } },
		{ title = "Sound", rows = { "features.twist_sound_enabled", "features.twist_sound_choice", "features.sound_channel" } },
	}},
	{ id = "bar", group = "Swing Bar", label = "Swing Bar", tabs = {
		{ label = "Layout", sections = {
			{ title = "Size", rows = { "positioning.bar_width", "positioning.bar_height" } },
			{ title = "Position", rows = { "positioning.position_description", "positioning.position_description2",
				"positioning.bar_locked", "positioning.bar_x_offset", "positioning.bar_y_offset",
				"positioning.bar_point", "positioning.bar_rel_point" } },
			{ title = "Layering", rows = { "positioning.strata_description", "positioning.frame_strata", "positioning.draw_level" } },
		}},
		{ label = "Textures & Border", sections = {
			{ title = "Textures", rows = { "bar_appearance.bar_texture_key", "bar_appearance.gcd_texture_key",
				"bar_appearance.backplane_texture_key", "bar_appearance.backplane_alpha" } },
			{ title = "Border", rows = { "bar_appearance.bar_border_description", "bar_appearance.border_mode_key",
				"bar_appearance.backplane_outline_width", "bar_appearance.border_texture_key" } },
			{ title = "Deadzone", rows = { "bar_appearance.deadzone_desc", "bar_appearance.deadzone_texture_key",
				"bar_appearance.bar_color_deadzone" } },
		}},
		{ label = "Colors", sections = {
			{ title = "Contextual bar colors", rows = { "bar_appearance.bar_color_default", "bar_appearance.bar_color_twisting",
				"bar_appearance.bar_color_warning" } },
			{ title = "Seal colors", rows = { "bar_appearance.bar_color_command", "bar_appearance.bar_color_righteousness",
				"bar_appearance.bar_color_blood", "bar_appearance.bar_color_vengeance", "bar_appearance.bar_color_wisdom",
				"bar_appearance.bar_color_light", "bar_appearance.bar_color_justice", "bar_appearance.bar_color_crusader" } },
			{ title = "GCD underlay", rows = { "bar_appearance.bar_color_gcd" } },
			{ title = "Markers", rows = { "bar_appearance.gcd1_enabled", "bar_appearance.marker_width",
				"bar_appearance.marker_texture", "bar_appearance.gcd_marker_color", "bar_appearance.twist_marker_color",
				"bar_appearance.judgement_marker_color" } },
		}},
		{ label = "Text", sections = {
			{ title = "Font", rows = { "bar_appearance.text_font", "bar_appearance.font_size", "bar_appearance.font_color",
				"bar_appearance.font_outline_key" } },
			{ title = "Labels", rows = { "bar_appearance.left_text", "bar_appearance.center_text", "bar_appearance.right_text" } },
		}},
		{ label = "Seal Icons", sections = {
			{ title = "Seal icon display", rows = { "icon_settings.icon_enabled", "icon_settings.icon_match_bar_height",
				"icon_settings.icon_size", "icon_settings.icon_spacing" } },
			{ title = "Icon position", rows = { "icon_settings.icon_detached", "icon_settings.icon_locked",
				"icon_settings.icon_x_offset", "icon_settings.icon_y_offset", "icon_settings.icon_point",
				"icon_settings.icon_rel_point", "icon_settings.icon_centered" } },
			{ title = "Seal duration timer", rows = { "icon_settings.seal_timer_enabled",
				"icon_settings.seal_cooldown_overlay_enabled", "icon_settings.seal_timer_size", "icon_settings.seal_timer_color" } },
		}},
	}},
	{ id = "behaviour", group = "Swing Bar", label = "Behaviour", sections = {
		{ title = "Bar visibility", rows = { "bar_behaviour.autohide_desc", "bar_behaviour.visibility_key" } },
		{ title = "Deadzone scaling", rows = { "bar_behaviour.deadzone_desc", "bar_behaviour.deadzone_scale_factor" } },
		{ title = "Marker offsets", rows = { "bar_behaviour.marker_descriptions", "bar_behaviour.gcd_padding_mode",
			"bar_behaviour.gcd_static_padding_ms", "bar_behaviour.twist_window_descriptions",
			"bar_behaviour.twist_padding_mode", "bar_behaviour.twist_window_padding_ms" } },
	}},
	{ id = "lag", group = "Swing Bar", label = "Lag Compensation", sections = {
		{ title = "Lag compensation", rows = { "lag_detection_section.lag_detection_enabled",
			"lag_detection_section.bar_color_cant_twist" } },
		{ title = "What is lag compensation?", rows = { "lag_detection_section.lag_descriptions1",
			"lag_detection_section.lag_descriptions101", "lag_detection_section.lag_descriptions1001",
			"lag_detection_section.lag_descriptions102", "lag_detection_section.lag_descriptions103",
			"lag_detection_section.lag_descriptions104" } },
		{ title = "How it works", rows = { "lag_detection_section.lag_descriptions_20002",
			"lag_detection_section.lag_descriptions_2002" } },
		{ title = "Do I need to calibrate?", rows = { "lag_detection_section.lag_descriptions_3002" } },
		{ title = "Calibration settings", rows = { "lag_detection_section.lag_descriptions_2",
			"lag_detection_section.lag_descriptions_22", "lag_detection_section.lag_descriptions_23",
			"lag_detection_section.lag_multiplier", "lag_detection_section.lag_offset" } },
	}},
	{ id = "nag", group = "Guides & Practice", label = "Next Action Guide", tabs = {
		{ label = "General", sections = {
			{ title = "Guide", rows = { "nextaction_guide.nextaction_desc", "nextaction_guide.nextaction_enabled",
				"nextaction_guide.nextaction_locked", "nextaction_guide.nextaction_visibility_key" } },
			{ title = "Load in zones", rows = { "nextaction_guide.nextaction_zones_desc", "nextaction_guide.nextaction_zone_world",
				"nextaction_guide.nextaction_zone_party", "nextaction_guide.nextaction_zone_raid",
				"nextaction_guide.nextaction_zone_pvp", "nextaction_guide.nextaction_zone_arena" } },
		}},
		{ label = "Layout", sections = {
			{ title = "Size", rows = { "nextaction_guide.nextaction_icon_size" } },
			{ title = "Position", rows = { "nextaction_guide.nextaction_x", "nextaction_guide.nextaction_y" } },
		}},
		{ label = "Timing", sections = {
			{ title = "Timing", rows = { "nextaction_guide.nextaction_reaction_time_ms", "nextaction_guide.nextaction_cs_max_delay_ms" } },
		}},
		{ label = "Display", sections = {
			{ title = "Cues", rows = { "nextaction_guide.nextaction_hold_enabled", "nextaction_guide.nextaction_show_label",
				"nextaction_guide.nextaction_show_rotation_text", "nextaction_guide.nextaction_show_judgement" } },
			{ title = "Fillers", rows = { "nextaction_guide.nextaction_show_fillers",
				"nextaction_guide.nextaction_filler_mana_consecration", "nextaction_guide.nextaction_filler_mana_exorcism" } },
		}},
	}},
	{ id = "hud", group = "Guides & Practice", label = "Cooldown HUD", tabs = {
		{ label = "General", sections = {
			{ title = "HUD", rows = { "cooldown_hud.hud_desc", "cooldown_hud.hud_enabled", "cooldown_hud.hud_visibility_key" } },
			{ title = "Icons", rows = { "cooldown_hud.hud_show_cs", "cooldown_hud.hud_show_judgement",
				"cooldown_hud.hud_show_consecration", "cooldown_hud.hud_show_exorcism",
				"cooldown_hud.hud_show_trinket1", "cooldown_hud.hud_show_trinket2", "cooldown_hud.hud_show_wings" } },
		}},
		{ label = "Layout", sections = {
			{ title = "Size", rows = { "cooldown_hud.hud_icon_size", "cooldown_hud.hud_match_bar_width", "cooldown_hud.hud_spacing", "cooldown_hud.hud_orientation" } },
			{ title = "Position", rows = { "cooldown_hud.hud_x", "cooldown_hud.hud_y" } },
		}},
		{ label = "Style", sections = {
			{ title = "Remaining time", rows = { "cooldown_hud.hud_show_text", "cooldown_hud.hud_font", "cooldown_hud.hud_text_size",
				"cooldown_hud.hud_text_outline", "cooldown_hud.hud_text_color", "cooldown_hud.hud_text_warn_color" } },
			{ title = "Border", rows = { "cooldown_hud.hud_border_size", "cooldown_hud.hud_border_color" } },
			{ title = "Cues", rows = { "cooldown_hud.hud_glow_enabled", "cooldown_hud.hud_desaturate",
				"cooldown_hud.hud_mana_tint", "cooldown_hud.hud_range_tint" } },
		}},
	}},
	{ id = "rottext", group = "Guides & Practice", label = "Rotation Text", sections = {
		{ title = "Rotation text", rows = { "rotation_label.rotation_label_desc", "rotation_label.rotation_label_enabled",
			"rotation_label.rotation_label_visibility_key", "rotation_label.rotation_label_format", "rotation_label.rotation_label_align" } },
		{ title = "Position", rows = { "rotation_label.rotation_label_x", "rotation_label.rotation_label_y" } },
		{ title = "Style", rows = { "rotation_label.rotation_label_font", "rotation_label.rotation_label_size",
			"rotation_label.rotation_label_outline", "rotation_label.rotation_label_color" } },
	}},
	{ id = "practice", group = "Guides & Practice", label = "Practice Mode", tabs = {
		{ label = "Simulation", sections = {
			{ title = "Twist practice minigame", rows = { "practice_mode.practice_desc", "practice_mode.practice_toggle" } },
			{ title = "Simulation", rows = { "practice_mode.practice_weapon_speed", "practice_mode.practice_aw_includes_pot",
				"practice_mode.practice_aw_includes_sob", "practice_mode.practice_dst_enabled",
				"practice_mode.practice_spell_queue_window" } },
			{ title = "Boss fight", rows = { "practice_mode.practice_bl_delay" } },
		}},
		{ label = "Rotation & Timeline", sections = {
			{ title = "Rotation display", rows = { "practice_mode.practice_rotation_display_enabled",
				"practice_mode.practice_rotation_display_icon_size", "practice_mode.practice_rotation_display_icon_spacing" } },
			{ title = "Fight timeline", rows = { "practice_mode.practice_timeline_enabled", "practice_mode.practice_timeline_mode",
				"practice_mode.practice_timeline_width", "practice_mode.practice_timeline_pixels_per_second" } },
		}},
		{ label = "Feedback", sections = {
			{ title = "Feedback text", rows = { "practice_mode.practice_result_duration", "practice_mode.practice_result_text_size",
				"practice_mode.practice_result_color_hit", "practice_mode.practice_result_color_miss" } },
		}},
	}},
	{ id = "feedback", group = "Feedback", label = "Twist Feedback", sections = {
		{ title = "Twist feedback system", rows = { "twist_feedback.twist_feedback_intro", "twist_feedback.twist_success_desc" } },
		{ title = "Twist attempt alerts", rows = { "twist_feedback.twist_attempt_desc",
			"twist_feedback.twist_success_sound_enabled", "twist_feedback.twist_success_sound_choice",
			"twist_feedback.twist_success_glow_enabled", "twist_feedback.twist_success_glow_color",
			"twist_feedback.twist_success_glow_type", "twist_feedback.twist_success_glow_duration",
			"twist_feedback.twist_success_glow_lines", "twist_feedback.twist_success_glow_frequency",
			"twist_feedback.twist_success_glow_thickness", "twist_feedback.twist_success_glow_scale" } },
		{ title = "Successful twist text", rows = { "twist_feedback.successful_twist_text_desc",
			"twist_feedback.successful_twist_text_enabled", "twist_feedback.successful_twist_text_mode",
			"twist_feedback.successful_twist_text_font",
			"twist_feedback.successful_twist_text_size", "twist_feedback.successful_twist_text_outline",
			"twist_feedback.successful_twist_text_color", "twist_feedback.successful_twist_text_duration",
			"twist_feedback.successful_twist_text_locked" } },
	}},
	{ id = "io", group = "System", label = "Import / Export", sections = {
		{ title = "Export", rows = { "import_export.export_desc", "import_export.include_positions",
			"import_export.include_sounds", "import_export.include_practice_keys", "import_export.generate_export",
			"import_export.export_string_display" } },
		{ title = "Import", rows = { "import_export.import_desc", "import_export.import_string_input", "import_export.do_import" } },
		{ title = "Status", rows = { "import_export.status_message_display" } },
	}},
	{ id = "profiles", group = "System", label = "Profiles", sections = {
		{ title = "Profiles", rows = { "profiles:desc", "profiles:current" } },
		{ title = "Active profile", rows = { "profiles:choosedesc", "profiles:choose", "profiles:new" } },
		{ title = "Copy", rows = { "profiles:copydesc", "profiles:copyfrom" } },
		{ title = "Reset", rows = { "profiles:descreset", "profiles:reset" } },
		{ title = "Delete", rows = { "profiles:deldesc", "profiles:delete" } },
	}},
}

local GROUPS = { "Swing Bar", "Guides & Practice", "Feedback", "System" }

-- Where uncovered options from each top-level group land.
local FALLBACK_PAGE = {
	[""] = "general", practice_mode = "practice", twist_feedback = "feedback", features = "general",
	bar_behaviour = "behaviour", lag_detection_section = "lag", positioning = "bar", bar_appearance = "bar",
	icon_settings = "bar", nextaction_guide = "nag", cooldown_hud = "hud", rotation_label = "rottext", import_export = "io", design = "general",
}

local function page_by_id(id)
	for _, p in ipairs(PAGES) do if p.id == id then return p end end
	return PAGES[1]
end

local function page_section_lists(page)
	if page.tabs then
		local lists = {}
		for _, t in ipairs(page.tabs) do lists[#lists + 1] = t.sections end
		return lists
	end
	return { page.sections }
end

-- Append any option the layout does not mention, so the window can never hide a setting.
local coverage_done = false
local function ensure_coverage()
	if coverage_done then return end
	coverage_done = true
	local covered = {}
	for _, page in ipairs(PAGES) do
		for _, sections in ipairs(page_section_lists(page)) do
			for _, s in ipairs(sections) do
				for _, path in ipairs(s.rows) do covered[path] = true end
			end
		end
	end

	local extras = {}
	local function walk(node, prefix, top)
		for key, opt in pairs(node.args or {}) do
			local path = prefix == "" and key or (prefix .. "." .. key)
			if opt.type == "group" then
				walk(opt, path, top ~= "" and top or key)
			elseif opt.type ~= "header" and not covered[path]
				and not (opt.type == "description" and opt.name == "") then
				extras[#extras + 1] = { path = path, top = top, order = opt.order or 100 }
			end
		end
	end
	walk(ST.options, "", "")
	table.sort(extras, function(a, b) if a.top == b.top then return a.order < b.order end return a.top < b.top end)

	for _, e in ipairs(extras) do
		local page = page_by_id(FALLBACK_PAGE[e.top] or "general")
		local sections = page.tabs and page.tabs[1].sections or page.sections
		local last = sections[#sections]
		if not last or last.title ~= "More settings" then
			last = { title = "More settings", rows = {} }
			sections[#sections + 1] = last
		end
		last.rows[#last.rows + 1] = e.path
		if st.debug then print("Settings UI: uncovered option added to fallback section: " .. e.path) end
	end
end

--=======================================================================================
-- Row model
--=======================================================================================
local function row_kind(opt)
	local t = opt.type
	if t == "toggle" then return "toggle"
	elseif t == "range" then return "range"
	elseif t == "select" then return "select"
	elseif t == "color" then return "color"
	elseif t == "input" then return opt.multiline and "text" or "input"
	elseif t == "execute" then return "execute"
	elseif t == "description" then return "desc"
	elseif t == "header" then return "header"
	end
	return "unsupported"
end

local function build_row(path)
	local res = resolve_path(path)
	if not res then
		if st.debug then print("Settings UI: unknown option path " .. tostring(path)) end
		return nil
	end
	local info = make_info(res)
	if eval_flag(inherited(res, "hidden"), info) then return nil end
	local opt = res.option
	local row = {
		res = res, info = info, opt = opt,
		kind = row_kind(opt),
		name = eval_name(opt.name, info),
		desc = eval_name(opt.desc, info),
		disabled = eval_flag(inherited(res, "disabled"), info),
	}
	if row.kind == "desc" and strip_codes(row.name):match("^%s*$") and not opt.image then
		return nil  -- blank spacer / empty status line
	end
	return row
end

local function is_control_kind(kind)
	return kind ~= "desc" and kind ~= "header" and kind ~= "unsupported"
end

local function count_page_rows(page)
	local n = 0
	for _, sections in ipairs(page_section_lists(page)) do
		for _, s in ipairs(sections) do
			for _, path in ipairs(s.rows) do
				local res = resolve_path(path)
				if res and is_control_kind(row_kind(res.option)) then n = n + 1 end
			end
		end
	end
	return n
end

--=======================================================================================
-- Widget pools
--=======================================================================================
-- A "host" owns a set of widget pools and the rows currently laid out from them. The
-- settings window is one host; every design-mode quick card is another, so cards and
-- the window can be rebuilt independently without stealing each other's widgets.
local hosts = {}

local function new_host(on_refresh)
	local h = { pools = {}, rows = {}, on_refresh = on_refresh }
	hosts[#hosts + 1] = h
	return h
end

local function acquire(host, kind, ctor, parent)
	local pool = host.pools[kind]
	if not pool then pool = { free = {}, used = {} }; host.pools[kind] = pool end
	local w = tremove(pool.free)
	if not w then w = ctor() end
	pool.used[#pool.used + 1] = w
	w:SetParent(parent)
	w:ClearAllPoints()
	w:Show()
	return w
end

local function release_all(host)
	for _, pool in pairs(host.pools) do
		for i = #pool.used, 1, -1 do
			local w = pool.used[i]
			pool.used[i] = nil
			if w.OnRelease then w:OnRelease() end
			w:Hide()
			w:ClearAllPoints()
			pool.free[#pool.free + 1] = w
		end
	end
	wipe(host.rows)
end

--=======================================================================================
-- Controls
--=======================================================================================
local state = { page = "general", tab = 1, query = "", scroll = 0 }
local win, pullout, catcher
local WIN_HOST = new_host()
local live_rows = WIN_HOST.rows
local dirty, suppress_refresh = false, false
local preview_sound_handle

local function fmt_range(v, step)
	if type(v) ~= "number" then return tostring(v or "") end
	if step and step < 1 then
		local decimals = 0
		local s = step
		while s < 1 and decimals < 4 do s = s * 10; decimals = decimals + 1 end
		local str = string.format("%." .. decimals .. "f", v)
		str = str:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
		return str
	end
	return tostring(floor(v + 0.5))
end

local function round_step(v, lo, step)
	if not step or step <= 0 then return v end
	local n = floor((v - lo) / step + 0.5)
	v = lo + n * step
	-- kill float noise (0.30000000000000004 -> 0.3)
	return tonumber(string.format("%.6f", v))
end

---------------------------------------------------------------------------------------
-- Toggle (pill switch)
---------------------------------------------------------------------------------------
local function create_toggle(w, h)
	w, h = w or 46, h or 24
	local knob = h - 6
	local f = CreateFrame("Button", nil, UIParent)
	f:SetSize(w, h)
	f.skin = add_rounded(f, { radius = h / 2, fill = C.track_off })
	f.knob = f:CreateTexture(nil, "ARTWORK")
	f.knob:SetTexture(TEX.circle)
	f.knob:SetSize(knob, knob)
	f.knob:SetVertexColor(1, 1, 1, 1)
	f.knob:SetPoint("LEFT", f, "LEFT", 3, 0)
	f.knob_x, f.knob_on_x, f.knob_off_x = 3, w - 3 - knob, 3
	f.on = false

	local function animate(self, dt)
		local target = self.on and self.knob_on_x or self.knob_off_x
		local delta = target - self.knob_x
		if abs(delta) < 0.5 then
			self.knob_x = target
			self:SetScript("OnUpdate", nil)
		else
			self.knob_x = self.knob_x + delta * min(1, dt * 18)
		end
		self.knob:SetPoint("LEFT", self, "LEFT", self.knob_x, 0)
	end

	function f:SetOn(on, animate_it)
		self.on = on and true or false
		local c = self.on and C.accent or C.track_off
		self.skin:SetFill(unpack(c))
		if animate_it then
			self:SetScript("OnUpdate", animate)
		else
			self.knob_x = self.on and self.knob_on_x or self.knob_off_x
			self.knob:SetPoint("LEFT", self, "LEFT", self.knob_x, 0)
			self:SetScript("OnUpdate", nil)
		end
	end
	f:SetScript("OnClick", function(self)
		if self.on_click then self.on_click(self) end
	end)
	function f:OnRelease() self.on_click = nil; self.row = nil; self:SetScript("OnUpdate", nil) end
	return f
end

local function new_toggle() return create_toggle(46, 24) end

---------------------------------------------------------------------------------------
-- Range (slider + value box)
---------------------------------------------------------------------------------------
local RANGE_BOX_W, RANGE_TRACK_GAP = 64, 18
local RANGE_TRACK_W = CONTROL_W - RANGE_BOX_W - RANGE_TRACK_GAP - 8

local function new_range()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(CONTROL_W, 28)

	f.box = create_panel(f, { radius = 7, fill = C.input_bg, border = C.input_border })
	f.box:SetSize(RANGE_BOX_W, 26)
	f.box:SetPoint("RIGHT")
	f.edit = CreateFrame("EditBox", nil, f.box)
	f.edit:SetPoint("TOPLEFT", 6, 0)
	f.edit:SetPoint("BOTTOMRIGHT", -6, 0)
	set_font(f.edit, FONT.mono, FS.value)
	f.edit:SetTextColor(1, 1, 1)
	f.edit:SetJustifyH("RIGHT")
	f.edit:SetAutoFocus(false)
	f.edit:SetMaxLetters(12)

	f.track = create_panel(f, { radius = 3, fill = C.track_off })
	f.track:SetHeight(6)
	f.track:SetPoint("LEFT", 8, 0)
	f.track:SetPoint("RIGHT", f.box, "LEFT", -RANGE_TRACK_GAP, 0)
	f.fillbar = create_panel(f.track, { radius = 3, fill = C.accent })
	f.fillbar:SetPoint("TOPLEFT")
	f.fillbar:SetPoint("BOTTOMLEFT")
	f.fillbar:SetWidth(1)

	f.slider = CreateFrame("Slider", nil, f)
	f.slider:SetOrientation("HORIZONTAL")
	f.slider:SetPoint("TOPLEFT", f.track, "TOPLEFT", -8, 9)
	f.slider:SetPoint("BOTTOMRIGHT", f.track, "BOTTOMRIGHT", 8, -9)
	-- The fill bar is its own frame above the track, so lift the slider (and its thumb)
	-- above both or the orange fill draws over the knob.
	f.slider:SetFrameLevel((f.fillbar:GetFrameLevel() or ((f:GetFrameLevel() or 0) + 2)) + 1)
	f.slider:SetThumbTexture(TEX.circle)
	local thumb = f.slider:GetThumbTexture()
	thumb:SetSize(16, 16)
	thumb:SetDrawLayer("OVERLAY")
	thumb:SetVertexColor(1, 1, 1, 1)
	if f.slider.SetObeyStepOnDrag then f.slider:SetObeyStepOnDrag(true) end

	local function update_visuals(self, v)
		local lo, hi = self.lo, self.hi
		local pct = hi > lo and (v - lo) / (hi - lo) or 0
		pct = max(0, min(1, pct))
		self.fillbar:SetWidth(max(1, pct * RANGE_TRACK_W))
		if not self.edit:HasFocus() then self.edit:SetText(fmt_range(v, self.step)) end
	end
	f.update_visuals = update_visuals

	f.slider:SetScript("OnValueChanged", function(s, v, user)
		local self = s:GetParent()
		if not user or not self.row then return end
		v = round_step(v, self.lo, self.step)
		if v == self.value then return end
		self.value = v
		update_visuals(self, v)
		set_value(self.row.res, self.row.info, v)
	end)
	f.slider:SetScript("OnMouseDown", function() suppress_refresh = true end)
	f.slider:SetScript("OnMouseUp", function() suppress_refresh = false; UI.request_refresh() end)

	local function commit(self)
		local v = tonumber(self.edit:GetText())
		self.edit:ClearFocus()
		if not v or not self.row then update_visuals(self, self.value); return end
		v = max(self.min_hard, min(self.max_hard, v))
		v = round_step(v, self.min_hard, self.step)
		self.value = v
		set_value(self.row.res, self.row.info, v)
	end
	f.edit:SetScript("OnEnterPressed", function(e) commit(e:GetParent():GetParent()) end)
	f.edit:SetScript("OnEscapePressed", function(e) e:ClearFocus(); local p = e:GetParent():GetParent(); update_visuals(p, p.value) end)
	f.edit:SetScript("OnEditFocusLost", function(e) local p = e:GetParent():GetParent(); update_visuals(p, p.value) end)

	function f:Setup(row)
		self.row = row
		local opt = row.opt
		self.min_hard = opt.min or 0
		self.max_hard = opt.max or 100
		self.lo = opt.softMin or self.min_hard
		self.hi = opt.softMax or self.max_hard
		self.step = opt.step or 1
		local v = tonumber(get_value(row.res, row.info)) or self.lo
		self.value = v
		self.slider:SetMinMaxValues(self.lo, self.hi)
		self.slider:SetValueStep(self.step)
		self.slider:SetValue(max(self.lo, min(self.hi, v)))
		update_visuals(self, v)
	end
	function f:SetEnabledState(enabled)
		self.slider:EnableMouse(enabled)
		self.edit:EnableMouse(enabled)
	end
	function f:OnRelease() self.row = nil; self.edit:ClearFocus() end
	return f
end

---------------------------------------------------------------------------------------
-- Select (dropdown button + shared pullout list)
---------------------------------------------------------------------------------------
-- LibSharedMedia-backed selects (dialogControl "LSM30_<Type>") use values tables that map
-- media name -> file path. The name is the key, so that is what gets displayed and sorted.
local function lsm_type(row)
	local control = row and row.opt and row.opt.dialogControl
	local kind = type(control) == "string" and control:match("^LSM30_(%a+)$")
	return kind and strlower(kind) or nil
end

local function option_label(row, values, key)
	if key == nil then return "" end
	if lsm_type(row) then return tostring(key) end
	local text = values[key]
	if text == nil then text = key end
	return strip_codes(tostring(text))
end

-- Texture previews only make sense for fill-style media; borders and fonts are handled separately.
local function media_preview_path(media, key)
	if key and (media == "statusbar" or media == "background") then
		return SML:Fetch(media, key, true)
	end
end

local function new_select()
	local b = CreateFrame("Button", nil, UIParent)
	b:SetSize(180, 28)
	b.skin = add_rounded(b, { radius = 7, fill = C.input_bg, border = C.input_border })
	b.preview = b:CreateTexture(nil, "BORDER")
	b.preview:SetPoint("TOPLEFT", 2, -2)
	b.preview:SetPoint("BOTTOMRIGHT", -2, 2)
	b.preview:SetAlpha(0.35)
	b.preview:Hide()
	b.label = create_text(b, FONT.medium, FS.button, C.white)
	b.label:SetPoint("LEFT", 11, 0)
	b.label:SetPoint("RIGHT", -26, 0)
	b.label:SetJustifyV("MIDDLE")
	b.label:SetWordWrap(false)
	b.chev = b:CreateTexture(nil, "OVERLAY")
	b.chev:SetTexture(TEX.chevron)
	b.chev:SetSize(12, 12)
	b.chev:SetPoint("RIGHT", -9, 0)
	b.chev:SetVertexColor(unpack(C.muted))
	b:SetScript("OnEnter", function(s) s.skin:SetBorder(unpack(C.input_border_hover)) end)
	b:SetScript("OnLeave", function(s) s.skin:SetBorder(unpack(C.input_border)) end)
	b:SetScript("OnClick", function(s) UI.open_pullout(s) end)

	function b:Setup(row)
		self.row = row
		local values = eval_values(row.res, row.info)
		self.values = values
		local v = get_value(row.res, row.info)
		self.value = v
		self.preview:Hide()
		local path = media_preview_path(lsm_type(row), v)
		if path then
			self.preview:SetTexture(path)
			self.preview:SetVertexColor(1, 0.85, 0.6)
			self.preview:Show()
		end
		self.label:SetText(option_label(row, values, v))
	end
	function b:OnRelease() self.row = nil; self.values = nil end
	return b
end

local function sorted_keys(row, values)
	local keys = {}
	for k in pairs(values) do keys[#keys + 1] = k end
	local lsm = lsm_type(row) ~= nil
	local function label(k)
		return strlower(lsm and tostring(k) or strip_codes(tostring(values[k])))
	end
	local sorting = row.opt.sorting
	if type(sorting) == "function" or type(sorting) == "string" then
		sorting = call_member(sorting, row.info)
	end
	if type(sorting) == "table" then
		local order = {}
		for i, k in ipairs(sorting) do order[k] = i end
		table.sort(keys, function(a, b)
			local oa, ob = order[a] or 1e9, order[b] or 1e9
			if oa ~= ob then return oa < ob end
			return label(a) < label(b)
		end)
	else
		table.sort(keys, function(a, b) return label(a) < label(b) end)
	end
	return keys
end

local function stop_preview_sound()
	if preview_sound_handle then
		StopSound(preview_sound_handle)
		preview_sound_handle = nil
	end
end

local function create_pullout()
	catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(50)
	catcher:SetAllPoints(UIParent)
	catcher:EnableMouse(true)
	catcher:RegisterForClicks("AnyUp")
	catcher:SetScript("OnClick", function() UI.close_pullout() end)
	catcher:Hide()

	pullout = create_panel(UIParent, { radius = 9, fill = hex("15161a", 0.98), border = hex("ffffff", 0.14) })
	pullout:SetFrameStrata("FULLSCREEN_DIALOG")
	pullout:SetFrameLevel(60)
	pullout:EnableMouse(true)
	pullout:Hide()

	pullout.scroll = CreateFrame("ScrollFrame", nil, pullout)
	pullout.scroll:SetPoint("TOPLEFT", 4, -4)
	pullout.scroll:SetPoint("BOTTOMRIGHT", -4, 4)
	pullout.child = CreateFrame("Frame", nil, pullout.scroll)
	pullout.child:SetSize(200, 10)
	pullout.scroll:SetScrollChild(pullout.child)
	pullout.scroll:EnableMouseWheel(true)
	pullout.scroll:SetScript("OnMouseWheel", function(s, delta)
		local maxs = max(0, pullout.child:GetHeight() - s:GetHeight())
		s:SetVerticalScroll(max(0, min(maxs, s:GetVerticalScroll() - delta * PULLOUT_ITEM_H * 3)))
	end)
	pullout.indicator = add_scroll_indicator(pullout.scroll, { width = 3, x = 1 })
	pullout.items = {}
	pullout:SetScript("OnHide", function() stop_preview_sound(); catcher:Hide() end)
end

local function new_pullout_item()
	local b = CreateFrame("Button", nil, pullout.child)
	b:SetHeight(PULLOUT_ITEM_H)
	b.hl = b:CreateTexture(nil, "BACKGROUND", nil, 1)
	b.hl:SetColorTexture(1, 1, 1, 0.08)
	b.hl:SetPoint("TOPLEFT", 2, 0)
	b.hl:SetPoint("BOTTOMRIGHT", -2, 0)
	b.hl:Hide()
	b.preview = b:CreateTexture(nil, "BACKGROUND", nil, 0)
	b.preview:SetPoint("TOPLEFT", 2, -2)
	b.preview:SetPoint("BOTTOMRIGHT", -2, 2)
	b.preview:SetAlpha(0.45)
	b.preview:Hide()
	b.label = create_text(b, FONT.regular, FS.button, C.text)
	b.label:SetPoint("LEFT", 12, 0)
	b.label:SetPoint("RIGHT", -28, 0)
	b.label:SetJustifyV("MIDDLE")
	b.label:SetWordWrap(false)
	b.check = b:CreateTexture(nil, "OVERLAY")
	b.check:SetTexture(TEX.check)
	b.check:SetSize(14, 14)
	b.check:SetPoint("RIGHT", -8, 0)
	b.check:SetVertexColor(unpack(C.accent))
	b:SetScript("OnEnter", function(s)
		s.hl:Show()
		if s.sound_key then
			local path = st.bar and st.bar.twist_sounds and st.bar.twist_sounds[s.sound_key]
			if path then
				stop_preview_sound()
				local channel = ST.db and ST.db.profile.sound_channel or "Master"
				local ok, handle = PlaySoundFile(path, channel)
				if ok then preview_sound_handle = handle end
			end
		end
	end)
	b:SetScript("OnLeave", function(s) s.hl:Hide() end)
	b:SetScript("OnClick", function(s)
		local owner = pullout.owner
		UI.close_pullout()
		if owner and owner.row then
			set_value(owner.row.res, owner.row.info, s.key)
		end
	end)
	return b
end

function UI.close_pullout()
	if pullout then pullout:Hide() end
	if catcher then catcher:Hide() end
end

function UI.open_pullout(owner)
	if not pullout then create_pullout() end
	if pullout:IsShown() and pullout.owner == owner then UI.close_pullout(); return end
	local row = owner.row
	if not row then return end
	local values = eval_values(row.res, row.info)
	local keys = sorted_keys(row, values)
	local current = get_value(row.res, row.info)
	local control = row.opt.dialogControl
	local media = lsm_type(row)
	local width = max(owner:GetWidth(), 220)

	for _, item in ipairs(pullout.items) do item:Hide() end
	local y = 0
	for i, key in ipairs(keys) do
		local item = pullout.items[i]
		if not item then item = new_pullout_item(); pullout.items[i] = item end
		item.key = key
		item.sound_key = (control == "Dropdown-SoundPreview") and key or nil
		item:ClearAllPoints()
		item:SetPoint("TOPLEFT", pullout.child, "TOPLEFT", 0, -y)
		item:SetWidth(width - 8)
		set_font(item.label, FONT.regular, FS.button)
		item.preview:Hide()
		local path = media_preview_path(media, key)
		if path then
			item.preview:SetTexture(path)
			item.preview:SetVertexColor(1, 0.85, 0.6)
			item.preview:Show()
		elseif media == "font" then
			-- Preview each font in the list with its own face; the name stays readable.
			local fpath = SML:Fetch("font", key, true)
			if fpath then set_font(item.label, fpath, FS.button) end
		end
		item.label:SetText(option_label(row, values, key))
		if key == current then item.check:Show(); set_color(item.label, C.white) else item.check:Hide(); set_color(item.label, C.text) end
		item:Show()
		y = y + PULLOUT_ITEM_H
	end
	pullout.child:SetSize(width - 8, max(y, 1))
	local h = min(PULLOUT_MAX_H, y + 8)
	-- match whatever opened it: the window (scaled) or a design-mode card (unscaled)
	pullout:SetScale((owner:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1))
	pullout:SetSize(width, h)
	pullout:ClearAllPoints()
	local below = owner:GetBottom() and (owner:GetBottom() * owner:GetEffectiveScale() / UIParent:GetEffectiveScale() - h > 10)
	if below then
		pullout:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
	else
		pullout:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 4)
	end
	pullout.owner = owner
	pullout.scroll:SetVerticalScroll(0)
	catcher:Show()
	pullout:Show()
	pullout.indicator:Update()
end

---------------------------------------------------------------------------------------
-- Color (swatch + hex box)
---------------------------------------------------------------------------------------
local function open_color_picker(r, g, b, a, has_alpha, callback)
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, opacity = a, hasOpacity = has_alpha,
			swatchFunc = function()
				local nr, ng, nb = ColorPickerFrame:GetColorRGB()
				local na = has_alpha and ColorPickerFrame:GetColorAlpha() or a
				callback(nr, ng, nb, na)
			end,
			opacityFunc = function()
				local nr, ng, nb = ColorPickerFrame:GetColorRGB()
				local na = has_alpha and ColorPickerFrame:GetColorAlpha() or a
				callback(nr, ng, nb, na)
			end,
			cancelFunc = function() callback(r, g, b, a) end,
		})
		return
	end
	ColorPickerFrame:Hide()
	ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
	ColorPickerFrame:SetClampedToScreen(true)
	ColorPickerFrame.func = function()
		local nr, ng, nb = ColorPickerFrame:GetColorRGB()
		local na = has_alpha and (1 - OpacitySliderFrame:GetValue()) or a
		callback(nr, ng, nb, na)
	end
	ColorPickerFrame.swatchFunc = ColorPickerFrame.func
	ColorPickerFrame.hasOpacity = has_alpha
	ColorPickerFrame.opacityFunc = ColorPickerFrame.func
	if has_alpha then ColorPickerFrame.opacity = 1 - (a or 1) end
	ColorPickerFrame:SetColorRGB(r, g, b)
	ColorPickerFrame.cancelFunc = function() callback(r, g, b, a) end
	ColorPickerFrame:Show()
end

local function new_color()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(124, 26)
	f.swatch = CreateFrame("Button", nil, f)
	f.swatch:SetSize(32, 26)
	f.swatch:SetPoint("LEFT")
	f.swatch.skin = add_rounded(f.swatch, { radius = 6, fill = C.white, border = C.swatch_border })
	f.swatch.dark = f.swatch:CreateTexture(nil, "BACKGROUND", nil, -2)
	f.swatch.dark:SetColorTexture(0.05, 0.05, 0.06, 1)
	f.swatch.dark:SetPoint("TOPLEFT", 1, -1)
	f.swatch.dark:SetPoint("BOTTOMRIGHT", -1, 1)

	f.box = create_panel(f, { radius = 7, fill = C.input_bg, border = C.input_border })
	f.box:SetSize(84, 26)
	f.box:SetPoint("RIGHT")
	f.edit = CreateFrame("EditBox", nil, f.box)
	f.edit:SetPoint("TOPLEFT", 8, 0)
	f.edit:SetPoint("BOTTOMRIGHT", -6, 0)
	set_font(f.edit, FONT.mono, FS.value)
	f.edit:SetTextColor(unpack(C.text_soft))
	f.edit:SetAutoFocus(false)
	f.edit:SetMaxLetters(7)

	local function apply(self, r, g, b, a)
		self.r, self.g, self.b, self.a = r, g, b, a
		self.swatch.skin:SetFill(r, g, b, a or 1)
		if not self.edit:HasFocus() then self.edit:SetText(fmt_hex(r, g, b)) end
	end

	f.swatch:SetScript("OnClick", function(s)
		local self = s:GetParent()
		if not self.row then return end
		local r, g, b, a = self.r, self.g, self.b, self.a
		open_color_picker(r, g, b, a, self.has_alpha, function(nr, ng, nb, na)
			if not self.row then return end
			apply(self, nr, ng, nb, na)
			silent_set = true
			set_value(self.row.res, self.row.info, nr, ng, nb, na)
			silent_set = false
		end)
	end)

	local function commit(self)
		local t = self.edit:GetText():gsub("^#", "")
		self.edit:ClearFocus()
		local rr, gg, bb = t:match("^(%x%x)(%x%x)(%x%x)$")
		if not rr or not self.row then apply(self, self.r, self.g, self.b, self.a); return end
		local r, g, b = tonumber(rr, 16) / 255, tonumber(gg, 16) / 255, tonumber(bb, 16) / 255
		apply(self, r, g, b, self.a)
		set_value(self.row.res, self.row.info, r, g, b, self.a)
	end
	f.edit:SetScript("OnEnterPressed", function(e) commit(e:GetParent():GetParent()) end)
	f.edit:SetScript("OnEscapePressed", function(e) e:ClearFocus(); local p = e:GetParent():GetParent(); apply(p, p.r, p.g, p.b, p.a) end)
	f.edit:SetScript("OnEditFocusLost", function(e) local p = e:GetParent():GetParent(); apply(p, p.r, p.g, p.b, p.a) end)

	function f:Setup(row)
		self.row = row
		self.has_alpha = row.opt.hasAlpha and true or false
		local r, g, b, a = get_value(row.res, row.info)
		apply(self, tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1, tonumber(a) or 1)
	end
	function f:SetEnabledState(enabled)
		self.swatch:EnableMouse(enabled)
		self.edit:EnableMouse(enabled)
	end
	function f:OnRelease() self.row = nil; self.edit:ClearFocus() end
	return f
end

---------------------------------------------------------------------------------------
-- Input (single line)
---------------------------------------------------------------------------------------
local function new_input()
	local f = create_panel(UIParent, { radius = 7, fill = C.input_bg, border = C.input_border })
	f:SetSize(130, 28)
	f.edit = CreateFrame("EditBox", nil, f)
	f.edit:SetPoint("TOPLEFT", 10, 0)
	f.edit:SetPoint("BOTTOMRIGHT", -10, 0)
	set_font(f.edit, FONT.mono, FS.button)
	f.edit:SetTextColor(1, 1, 1)
	f.edit:SetAutoFocus(false)
	f.edit:SetMaxLetters(0)
	f:EnableMouse(true)
	f:SetScript("OnMouseDown", function(s) s.edit:SetFocus() end)

	local function commit(self, rebuild)
		if not self.row then return end
		local text = self.edit:GetText()
		if text == self.last then return end
		self.last = text
		local validate = inherited(self.row.res, "validate")
		if validate then
			local ok = call_member(validate, self.row.info, text)
			if ok ~= true and ok ~= nil then
				print(type(ok) == "string" and ok or "Invalid value.")
				self.edit:SetText(self.last or "")
				return
			end
		end
		if rebuild then
			set_value(self.row.res, self.row.info, text)
		else
			silent_set = true
			set_value(self.row.res, self.row.info, text)
			silent_set = false
			UI.refresh_states()
		end
	end
	f.edit:SetScript("OnEnterPressed", function(e) local p = e:GetParent(); commit(p, true); e:ClearFocus() end)
	f.edit:SetScript("OnEscapePressed", function(e) local p = e:GetParent(); e:SetText(p.last or ""); e:ClearFocus() end)
	f.edit:SetScript("OnEditFocusGained", function(e) e:GetParent().skin:SetBorder(unpack(C.accent)) end)
	f.edit:SetScript("OnEditFocusLost", function(e) local p = e:GetParent(); p.skin:SetBorder(unpack(C.input_border)); commit(p, false) end)

	function f:Setup(row)
		self.row = row
		local v = get_value(row.res, row.info)
		v = v == nil and "" or tostring(v)
		self.last = v
		self.edit:SetText(v)
		self.edit:SetCursorPosition(0)
	end
	function f:SetEnabledState(enabled)
		self:EnableMouse(enabled)
		self.edit:EnableMouse(enabled)
	end
	function f:OnRelease() self.row = nil; self.edit:ClearFocus() end
	return f
end

---------------------------------------------------------------------------------------
-- Text (multi-line input)
---------------------------------------------------------------------------------------
local TEXT_BOX_H = 84

local function new_textbox()
	local f = create_panel(UIParent, { radius = 8, fill = C.input_bg, border = C.input_border })
	f:SetHeight(TEXT_BOX_H)
	f:EnableMouse(true)
	f.scroll = CreateFrame("ScrollFrame", nil, f)
	f.scroll:SetPoint("TOPLEFT", 10, -8)
	f.scroll:SetPoint("BOTTOMRIGHT", -10, 8)
	f.scroll:EnableMouseWheel(true)
	f.edit = CreateFrame("EditBox", nil, f.scroll)
	f.edit:SetMultiLine(true)
	f.edit:SetAutoFocus(false)
	f.edit:SetMaxLetters(0)
	set_font(f.edit, FONT.mono, FS.value)
	f.edit:SetTextColor(unpack(C.muted))
	f.edit:SetWidth(200)
	f.scroll:SetScrollChild(f.edit)
	f.scroll:SetScript("OnMouseWheel", function(s, delta)
		local maxs = max(0, f.edit:GetHeight() - s:GetHeight())
		s:SetVerticalScroll(max(0, min(maxs, s:GetVerticalScroll() - delta * 20)))
	end)
	f.indicator = add_scroll_indicator(f.scroll, { width = 3, x = 6 })
	f:SetScript("OnMouseDown", function(s) s.edit:SetFocus() end)
	f.edit:SetScript("OnCursorChanged", function(e, x, y, w, h)
		local sf = f.scroll
		local vh = sf:GetHeight()
		local cur = sf:GetVerticalScroll()
		y = -y
		if y < cur then sf:SetVerticalScroll(y)
		elseif y + h > cur + vh then sf:SetVerticalScroll(y + h - vh) end
	end)

	local function commit(self)
		if not self.row then return end
		local text = self.edit:GetText()
		if text == self.last then return end
		self.last = text
		silent_set = true
		set_value(self.row.res, self.row.info, text)
		silent_set = false
		UI.refresh_states()
	end
	f.edit:SetScript("OnTextChanged", function(e, user) if user then commit(f) end end)
	f.edit:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
	f.edit:SetScript("OnEditFocusGained", function(e) f.skin:SetBorder(unpack(C.accent)); e:SetTextColor(1, 1, 1) end)
	f.edit:SetScript("OnEditFocusLost", function(e) f.skin:SetBorder(unpack(C.input_border)); e:SetTextColor(unpack(C.muted)); commit(f) end)

	function f:Setup(row, width)
		self.row = row
		self:SetWidth(width)
		self.edit:SetWidth(width - 20)
		local v = get_value(row.res, row.info)
		v = v == nil and "" or tostring(v)
		self.last = v
		self.edit:SetText(v)
		self.edit:SetCursorPosition(0)
		self.scroll:SetVerticalScroll(0)
	end
	function f:SetEnabledState(enabled)
		self:EnableMouse(enabled)
		self.edit:EnableMouse(enabled)
	end
	function f:OnRelease() self.row = nil; self.edit:ClearFocus() end
	return f
end

---------------------------------------------------------------------------------------
-- Execute (accent button)
---------------------------------------------------------------------------------------
local function new_execute()
	local b = CreateFrame("Button", nil, UIParent)
	b:SetHeight(30)
	b.skin = add_rounded(b, { radius = 8, fill = C.accent })
	b.label = create_text(b, FONT.bold, FS.button, C.accent_text)
	b.label:SetPoint("CENTER")
	b.label:SetJustifyV("MIDDLE")
	b:SetScript("OnEnter", function(s) s.skin:SetFill(unpack(C.accent_hover)) end)
	b:SetScript("OnLeave", function(s) s.skin:SetFill(unpack(C.accent)) end)
	b:SetScript("OnClick", function(s) if s.row then exec_option(s.row.res, s.row.info) end end)
	function b:Setup(row)
		self.row = row
		self.label:SetText(strip_codes(row.name))
		self:SetWidth(max(90, self.label:GetStringWidth() + 36))
	end
	function b:OnRelease() self.row = nil; self.skin:SetFill(unpack(C.accent)) end
	return b
end

---------------------------------------------------------------------------------------
-- Generic secondary button (footer / tabs)
---------------------------------------------------------------------------------------
local function create_button(parent, text, on_click)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(32)
	b.skin = add_rounded(b, { radius = 8, fill = C.button_bg, border = C.button_border })
	b.label = create_text(b, FONT.medium, FS.button, C.text)
	b.label:SetPoint("CENTER")
	b.label:SetJustifyV("MIDDLE")
	b:SetScript("OnEnter", function(s) s.skin:SetBorder(unpack(C.input_border_hover)); set_color(s.label, C.white) end)
	b:SetScript("OnLeave", function(s) s.skin:SetBorder(unpack(C.button_border)); set_color(s.label, C.text) end)
	b:SetScript("OnClick", on_click)
	function b:SetText(t)
		self.label:SetText(t)
		self:SetWidth(self.label:GetStringWidth() + 36)
	end
	b:SetText(text)
	return b
end

--=======================================================================================
-- Rows and sections
--=======================================================================================
local CONTROL_CTORS = {
	toggle = new_toggle, range = new_range, select = new_select, color = new_color,
	input = new_input, text = new_textbox, execute = new_execute,
}

local function new_row()
	local f = CreateFrame("Frame", nil, UIParent)
	f.line = create_line(f, C.row_line, "ARTWORK")
	f.line:SetHeight(1)
	f.line:SetPoint("TOPLEFT", 0, 0)
	f.line:SetPoint("TOPRIGHT", 0, 0)
	f.name = create_text(f, FONT.bold, FS.name, C.white)
	f.desc = create_text(f, FONT.regular, FS.desc, C.muted)
	f.desc:SetSpacing(2)
	f.text = create_text(f, FONT.regular, FS.desc_row, C.label)
	f.text:SetSpacing(4)
	f.image = f:CreateTexture(nil, "ARTWORK")
	f.image:Hide()
	function f:OnRelease()
		self.control = nil
		self.row = nil
		self.host = nil
		self:EnableMouse(false)
		self:SetScript("OnEnter", nil)
		self:SetScript("OnLeave", nil)
		self.name:SetText(""); self.desc:SetText(""); self.text:SetText("")
		self.name:Hide(); self.desc:Hide(); self.text:Hide(); self.image:Hide()
	end
	return f
end

local function new_section()
	local f = create_panel(UIParent, { radius = RADIUS, fill = C.panel, border = C.panel_border })
	f.topline = create_line(f, hex("ffd27a", 0.1), "BACKGROUND", 2)
	f.topline:SetHeight(1)
	f.topline:SetPoint("TOPLEFT", RADIUS, -1)
	f.topline:SetPoint("TOPRIGHT", -RADIUS, -1)
	-- Header band: a slightly lighter rounded strip behind the title so the card's
	-- heading reads as a heading and not as another row of text.
	f.head = CreateFrame("Frame", nil, f)
	f.head:SetPoint("TOPLEFT", 1, -1)
	f.head:SetPoint("TOPRIGHT", -1, -1)
	f.head:SetHeight(SECTION_TITLE_H - 1)
	f.head.skin = add_rounded(f.head, { radius = RADIUS - 1, fill = C.panel_head, corners = { tl = true, tr = true } })
	f.mark = f.head:CreateTexture(nil, "ARTWORK")
	f.mark:SetTexture(TEX.round)
	f.mark:SetTexCoord(0.3, 0.7, 0.3, 0.7)
	f.mark:SetSize(3, 14)
	f.mark:SetPoint("LEFT", f.head, "LEFT", 16, 0)
	f.mark:SetVertexColor(unpack(C.accent))
	f.title = create_text(f.head, FONT.bold, FS.section, C.white)
	f.title:SetPoint("LEFT", f.mark, "RIGHT", 9, 0)
	f.title:SetJustifyV("MIDDLE")
	f.crumb = create_text(f, FONT.mono, FS.crumb, C.dim)
	f.crumb:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
	f.crumb:SetJustifyV("MIDDLE")
	f.line = create_line(f, C.panel_title_line, "ARTWORK")
	f.line:SetHeight(1)
	f.line:SetPoint("TOPLEFT", 1, -SECTION_TITLE_H)
	f.line:SetPoint("TOPRIGHT", -1, -SECTION_TITLE_H)
	return f
end

-- Hover tooltip for compact rows (their description has no room on the row itself).
local function row_tooltip_enter(rowf)
	local row = rowf.row
	if not (row and row.desc and row.desc ~= "") then return end
	GameTooltip:SetOwner(rowf, "ANCHOR_RIGHT")
	GameTooltip:SetText(strip_codes(row.name), 1, 1, 1)
	GameTooltip:AddLine(row.desc, 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

-- Lays out one row inside a section. Returns the row height. `compact` stacks the
-- control under its name and moves the description into a hover tooltip: the layout
-- for the narrow design-mode quick cards.
local function layout_row(rowf, row, width, first, compact)
	rowf.row = row
	rowf:SetWidth(width)
	if first then rowf.line:Hide() else rowf.line:Show() end
	local inner_w = width - ROW_INSET * 2
	local kind = row.kind
	local height
	if compact then
		rowf:EnableMouse(true)
		rowf:SetScript("OnEnter", row_tooltip_enter)
		rowf:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	if kind == "desc" or kind == "unsupported" or kind == "header" then
		local text = row.name
		if kind == "unsupported" then text = "|cffff8a1f" .. strip_codes(row.name) .. "|r  (option type '" .. tostring(row.opt.type) .. "' is not supported by this window)" end
		local fs = rowf.text
		local size = FS.desc_row
		if row.opt.fontSize == "large" then size = 16 elseif row.opt.fontSize == "medium" then size = 14 end
		if kind == "header" then
			set_font(fs, FONT.bold, FS.section)
			set_color(fs, C.label)
			text = strupper(strip_codes(text))
		else
			set_font(fs, FONT.regular, size)
			set_color(fs, C.label)
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", ROW_INSET, -ROW_PAD)
		fs:SetWidth(inner_w)
		fs:SetText(text)
		fs:Show()
		local th = (text ~= "" and fs:GetStringHeight() or 0)
		height = th + ROW_PAD * 2
		local img = row.opt.image
		if img and kind == "desc" then
			if type(img) == "function" then img = img(row.info) end
			local iw, ih = row.opt.imageWidth or 64, row.opt.imageHeight or 64
			rowf.image:SetTexture(img)
			rowf.image:SetSize(iw, ih)
			if row.opt.imageCoords then rowf.image:SetTexCoord(unpack(row.opt.imageCoords)) else rowf.image:SetTexCoord(0, 1, 0, 1) end
			rowf.image:ClearAllPoints()
			rowf.image:SetPoint("TOPLEFT", ROW_INSET, -(ROW_PAD + th + (th > 0 and 8 or 0)))
			rowf.image:Show()
			height = height + ih + (th > 0 and 8 or 0)
		end
		rowf:SetHeight(max(height, 28))
		return rowf:GetHeight()
	end

	local ctor = CONTROL_CTORS[kind]
	local control = acquire(rowf.host or WIN_HOST, kind, ctor, rowf)
	rowf.control = control

	if compact and kind == "execute" then
		-- the button carries its own label: let it span the row
		control:Setup(row)
		control:SetPoint("TOPLEFT", ROW_INSET, -ROW_PAD)
		control:SetWidth(inner_w)
		height = ROW_PAD * 2 + control:GetHeight()
		rowf:SetHeight(height)
		return height
	end

	if kind == "text" then
		rowf.name:ClearAllPoints()
		rowf.name:SetPoint("TOPLEFT", ROW_INSET, -ROW_PAD)
		rowf.name:SetWidth(inner_w)
		rowf.name:SetText(strip_codes(row.name))
		rowf.name:Show()
		local nh = rowf.name:GetStringHeight()
		control:Setup(row, inner_w)
		control:SetPoint("TOPLEFT", ROW_INSET, -(ROW_PAD + nh + 8))
		height = ROW_PAD + nh + 8 + TEXT_BOX_H + ROW_PAD
	else
		if kind == "toggle" then
			control.row = row
			control:SetOn(get_value(row.res, row.info) and true or false, false)
			control.on_click = function(self)
				local on = not self.on
				self:SetOn(on, true)
				set_value(row.res, row.info, on)
			end
		else
			control:Setup(row)
		end
		local ctrl_w = control:GetWidth()
		local stacked = compact and kind ~= "toggle"
		local label_w = stacked and inner_w or (inner_w - ctrl_w - 20)
		rowf.name:ClearAllPoints()
		rowf.name:SetPoint("TOPLEFT", ROW_INSET, -ROW_PAD)
		rowf.name:SetWidth(label_w)
		rowf.name:SetText(strip_codes(row.name))
		rowf.name:Show()
		local nh = rowf.name:GetStringHeight()
		local dh = 0
		if stacked then
			control:SetPoint("TOPRIGHT", rowf, "TOPRIGHT", -ROW_INSET, -(ROW_PAD + nh + 6))
			height = ROW_PAD + nh + 6 + control:GetHeight() + ROW_PAD
			rowf:SetHeight(height)
			return height
		elseif compact then
			height = max(36, ROW_PAD * 2 + nh)
			control:SetPoint("RIGHT", rowf, "RIGHT", -ROW_INSET, 0)
			rowf:SetHeight(height)
			return height
		end
		if row.desc and row.desc ~= "" then
			rowf.desc:ClearAllPoints()
			rowf.desc:SetPoint("TOPLEFT", ROW_INSET, -(ROW_PAD + nh + 3))
			rowf.desc:SetWidth(label_w)
			rowf.desc:SetText(row.desc)
			rowf.desc:Show()
			dh = rowf.desc:GetStringHeight() + 3
		end
		height = max(ROW_MIN_H, ROW_PAD * 2 + nh + dh)
		control:SetPoint("RIGHT", rowf, "RIGHT", -ROW_INSET, 0)
	end
	rowf:SetHeight(height)
	return height
end

local function apply_row_state(rowf)
	local row = rowf.row
	if not row or not row.res then return end
	local disabled = eval_flag(inherited(row.res, "disabled"), row.info)
	row.disabled = disabled
	rowf:SetAlpha(disabled and 0.45 or 1)
	local c = rowf.control
	if c then
		if c.SetEnabledState then c:SetEnabledState(not disabled) else c:EnableMouse(not disabled) end
	end
end

function UI.refresh_states()
	for _, host in ipairs(hosts) do
		for _, rowf in ipairs(host.rows) do
			apply_row_state(rowf)
			local row = rowf.row
			if row and row.kind == "execute" and rowf.control then
				local name = eval_name(row.opt.name, row.info)
				if name ~= row.name then row.name = name; rowf.control:Setup(row) end
			end
		end
	end
end

--=======================================================================================
-- Window construction
--=======================================================================================
local function version_string()
	local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local v = getter and getter(addon_name, "Version") or ""
	v = tostring(v or ""):gsub('"', "")
	return v
end

local function create_nav(sidebar)
	local holder = CreateFrame("Frame", nil, sidebar)
	holder:SetPoint("TOPLEFT", 14, -132)
	holder:SetPoint("BOTTOMRIGHT", -14, 40)
	sidebar.nav_items = {}
	local y = 0
	for _, group in ipairs(GROUPS) do
		local label = create_text(holder, FONT.bold, FS.nav_group, C.nav_group)
		label:SetPoint("TOPLEFT", 12, -y - 6)
		label:SetText(strupper(group))
		y = y + 24
		for _, page in ipairs(PAGES) do
			if page.group == group then
				local b = CreateFrame("Button", nil, holder)
				b:SetPoint("TOPLEFT", 0, -y)
				b:SetPoint("RIGHT", 0, 0)
				b:SetHeight(28)
				b.skin = add_rounded(b, { radius = 8, fill = { 0, 0, 0, 0 } })
				b.label = create_text(b, FONT.regular, FS.nav_item, C.text_soft)
				b.label:SetPoint("LEFT", 12, 0)
				b.label:SetJustifyV("MIDDLE")
				b.label:SetText(page.label)
				b.count = create_text(b, FONT.regular, FS.nav_count, C.dim)
				b.count:SetPoint("RIGHT", -12, 0)
				b.count:SetJustifyV("MIDDLE")
				b.page = page
				b:SetScript("OnEnter", function(s) if state.page ~= s.page.id or state.query ~= "" then s.skin:SetFill(unpack(C.nav_hover)) end end)
				b:SetScript("OnLeave", function(s) if state.page ~= s.page.id or state.query ~= "" then s.skin:SetFill(0, 0, 0, 0) end end)
				b:SetScript("OnClick", function(s) UI.show_page(s.page.id) end)
				sidebar.nav_items[#sidebar.nav_items + 1] = b
				y = y + 28
			end
		end
		y = y + 8
	end
end

local function update_nav()
	for _, b in ipairs(win.sidebar.nav_items) do
		local active = (state.page == b.page.id) and state.query == ""
		if active then
			b.skin:SetFill(unpack(C.nav_active))
			set_font(b.label, FONT.bold, FS.nav_item)
			set_color(b.label, C.white)
		else
			b.skin:SetFill(0, 0, 0, 0)
			set_font(b.label, FONT.regular, FS.nav_item)
			set_color(b.label, C.text_soft)
		end
		b.count:SetText(tostring(count_page_rows(b.page)))
	end
end

local function create_search(sidebar)
	local box = create_panel(sidebar, { radius = 9, fill = C.search_bg, border = C.search_border })
	box:SetPoint("TOPLEFT", 14, -84)
	box:SetPoint("TOPRIGHT", -14, -84)
	box:SetHeight(36)
	box:EnableMouse(true)
	box.icon = box:CreateTexture(nil, "ARTWORK")
	box.icon:SetTexture(TEX.search)
	box.icon:SetSize(15, 15)
	box.icon:SetPoint("LEFT", 12, 0)
	box.icon:SetVertexColor(unpack(C.muted))
	box.edit = CreateFrame("EditBox", nil, box)
	box.edit:SetPoint("TOPLEFT", 34, 0)
	box.edit:SetPoint("BOTTOMRIGHT", -30, 0)
	set_font(box.edit, FONT.regular, 14)
	box.edit:SetTextColor(unpack(C.text))
	box.edit:SetAutoFocus(false)
	box.edit:SetMaxLetters(60)
	box.placeholder = create_text(box, FONT.regular, 14, C.dim)
	box.placeholder:SetPoint("LEFT", 34, 0)
	box.placeholder:SetJustifyV("MIDDLE")
	box.placeholder:SetText("Search settings")
	box.clear = CreateFrame("Button", nil, box)
	box.clear:SetSize(20, 20)
	box.clear:SetPoint("RIGHT", -8, 0)
	box.clear.icon = box.clear:CreateTexture(nil, "ARTWORK")
	box.clear.icon:SetTexture(TEX.close)
	box.clear.icon:SetSize(11, 11)
	box.clear.icon:SetPoint("CENTER")
	box.clear.icon:SetVertexColor(unpack(C.muted))
	box.clear:Hide()
	box.clear:SetScript("OnClick", function() box.edit:SetText(""); box.edit:ClearFocus(); UI.set_query("") end)
	box:SetScript("OnMouseDown", function() box.edit:SetFocus() end)
	box.edit:SetScript("OnTextChanged", function(e, user)
		local t = e:GetText()
		if t == "" then box.placeholder:Show(); box.clear:Hide() else box.placeholder:Hide(); box.clear:Show() end
		if user then UI.set_query(t) end
	end)
	box.edit:SetScript("OnEscapePressed", function(e) e:SetText(""); e:ClearFocus(); UI.set_query("") end)
	box.edit:SetScript("OnEnterPressed", function(e) e:ClearFocus() end)
	box.edit:SetScript("OnEditFocusGained", function() box.skin:SetBorder(unpack(C.accent)) end)
	box.edit:SetScript("OnEditFocusLost", function() box.skin:SetBorder(unpack(C.search_border)) end)
	sidebar.search = box
end

local function create_sidebar()
	local sb = CreateFrame("Frame", nil, win)
	sb:SetPoint("TOPLEFT", 1, -1)
	sb:SetPoint("BOTTOMLEFT", 1, FOOTER_H)
	sb:SetWidth(SIDEBAR_W - 1)
	sb.skin = add_rounded(sb, { radius = RADIUS, fill = C.sidebar_fill, corners = { tl = true } })
	sb.edge = create_line(sb, C.sidebar_line, "ARTWORK")
	sb.edge:SetWidth(1)
	sb.edge:SetPoint("TOPRIGHT", 0, 0)
	sb.edge:SetPoint("BOTTOMRIGHT", 0, 0)

	-- Brand
	local logo = CreateFrame("Frame", nil, sb)
	logo:SetSize(46, 46)
	logo:SetPoint("TOPLEFT", 18, -18)
	logo.glow = logo:CreateTexture(nil, "BACKGROUND")
	logo.glow:SetTexture(TEX.glow)
	logo.glow:SetSize(110, 110)
	logo.glow:SetPoint("CENTER")
	logo.glow:SetBlendMode("ADD")
	logo.glow:SetVertexColor(1, 0.71, 0.29, 0.18)
	logo.tex = logo:CreateTexture(nil, "ARTWORK")
	logo.tex:SetAllPoints()
	if not logo.tex:SetTexture(IMG .. "logo.tga") and not logo.tex:SetTexture(IMG .. "logo.png") then
		logo.tex:SetTexture(GetSpellTexture(20375))  -- Seal of Command
		logo.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
	if logo.CreateMaskTexture and logo.tex.AddMaskTexture then
		local mask = logo:CreateMaskTexture()
		mask:SetTexture(TEX.round, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(logo.tex)
		logo.tex:AddMaskTexture(mask)
	end
	sb.brand = create_text(sb, FONT.bold, FS.brand, C.white)
	sb.brand:SetPoint("TOPLEFT", logo, "TOPRIGHT", 14, -4)
	sb.brand:SetText("SwedgeTimer")
	sb.version = create_text(sb, FONT.mono, FS.version, C.muted)
	sb.version:SetPoint("TOPLEFT", sb.brand, "BOTTOMLEFT", 0, -3)
	sb.version:SetText("v" .. version_string())

	create_search(sb)
	create_nav(sb)

	sb.credit = create_text(sb, FONT.medium, 12, C.white)
	sb.credit:SetPoint("BOTTOMLEFT", 20, 14)
	sb.credit:SetText("Made by Folktale")
	return sb
end

local function create_header()
	local h = CreateFrame("Frame", nil, win)
	h:SetPoint("TOPLEFT", SIDEBAR_W, 0)
	h:SetPoint("TOPRIGHT", 0, 0)
	h:SetHeight(HEADER_H)
	h:EnableMouse(true)
	h:RegisterForDrag("LeftButton")
	h:SetScript("OnDragStart", function() win:StartMoving() end)
	h:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)

	h.group = create_text(h, FONT.bold, FS.group, C.accent)
	h.group:SetPoint("BOTTOMLEFT", PAD, 50)
	h.group:SetShadowColor(0, 0, 0, 0.9)
	h.group:SetShadowOffset(1, -1)
	h.title = create_text(h, FONT.bold, FS.title, C.white)
	h.title:SetPoint("BOTTOMLEFT", PAD, 16)
	h.title:SetShadowColor(0, 0, 0, 0.9)
	h.title:SetShadowOffset(1, -2)

	h.close = CreateFrame("Button", nil, h)
	h.close:SetSize(30, 30)
	h.close:SetPoint("TOPRIGHT", -20, -18)
	h.close.skin = add_rounded(h.close, { radius = 8, fill = hex("1d1e23", 0.8), border = hex("ffffff", 0.1) })
	h.close.icon = h.close:CreateTexture(nil, "ARTWORK")
	h.close.icon:SetTexture(TEX.close)
	h.close.icon:SetSize(13, 13)
	h.close.icon:SetPoint("CENTER")
	h.close.icon:SetVertexColor(unpack(C.text_soft))
	h.close:SetScript("OnEnter", function(s) s.icon:SetVertexColor(1, 1, 1); s.skin:SetBorder(unpack(C.input_border_hover)) end)
	h.close:SetScript("OnLeave", function(s) s.icon:SetVertexColor(unpack(C.text_soft)); s.skin:SetBorder(1, 1, 1, 0.1) end)
	h.close:SetScript("OnClick", function() UI.close() end)
	return h
end

local function create_content()
	local c = CreateFrame("Frame", nil, win)
	c:SetPoint("TOPLEFT", SIDEBAR_W, -HEADER_H)
	c:SetPoint("BOTTOMRIGHT", -1, FOOTER_H)
	c.skin = add_rounded(c, { radius = RADIUS, fill = C.content_fill, corners = { tl = true } })
	c.topline = create_line(c, hex("ffd27a", 0.2), "BACKGROUND", 2)
	c.topline:SetHeight(1)
	c.topline:SetPoint("TOPLEFT", RADIUS, 0)
	c.topline:SetPoint("TOPRIGHT", 0, 0)

	-- Tab bar
	c.tabbar = create_panel(c, { radius = 10, fill = C.tab_bar, border = C.tab_bar_border })
	c.tabbar:SetPoint("TOPLEFT", PAD, -14)
	c.tabbar:SetHeight(36)
	c.tabbar.buttons = {}
	c.tabbar:Hide()

	-- Scrolling body
	c.scroll = CreateFrame("ScrollFrame", nil, c)
	c.scroll:SetPoint("TOPLEFT", PAD, -16)
	c.scroll:SetPoint("BOTTOMRIGHT", -PAD + 8, 18)
	c.child = CreateFrame("Frame", nil, c.scroll)
	c.child:SetSize(100, 100)
	c.scroll:SetScrollChild(c.child)
	c.scroll:EnableMouseWheel(true)

	c.bar = CreateFrame("Slider", nil, c)
	c.bar:SetOrientation("VERTICAL")
	c.bar:SetWidth(4)
	c.bar:SetPoint("TOPRIGHT", -10, -18)
	c.bar:SetPoint("BOTTOMRIGHT", -10, 20)
	c.bar.track = c.bar:CreateTexture(nil, "BACKGROUND")
	c.bar.track:SetAllPoints()
	c.bar.track:SetColorTexture(1, 1, 1, 0.05)
	c.bar:SetThumbTexture(TEX.round)
	local thumb = c.bar:GetThumbTexture()
	thumb:SetSize(4, 40)
	thumb:SetTexCoord(0.3, 0.7, 0.3, 0.7)
	thumb:SetVertexColor(1, 1, 1, 0.25)
	c.bar:SetMinMaxValues(0, 0)
	c.bar:SetValue(0)
	c.bar:SetScript("OnValueChanged", function(s, v)
		c.scroll:SetVerticalScroll(v)
		state.scroll = v
	end)
	c.scroll:SetScript("OnMouseWheel", function(s, delta)
		local lo, hi = c.bar:GetMinMaxValues()
		c.bar:SetValue(max(lo, min(hi, c.bar:GetValue() - delta * 48)))
	end)
	c:EnableMouseWheel(true)
	c:SetScript("OnMouseWheel", function(s, delta) c.scroll:GetScript("OnMouseWheel")(c.scroll, delta) end)
	return c
end

local function create_footer()
	local f = CreateFrame("Frame", nil, win)
	f:SetPoint("BOTTOMLEFT", 1, 1)
	f:SetPoint("BOTTOMRIGHT", -1, 1)
	f:SetHeight(FOOTER_H - 1)
	f.skin = add_rounded(f, { radius = RADIUS, fill = C.footer_fill, corners = { bl = true, br = true } })
	f.topline = create_line(f, C.footer_line, "ARTWORK")
	f.topline:SetHeight(1)
	f.topline:SetPoint("TOPLEFT", 0, 0)
	f.topline:SetPoint("TOPRIGHT", 0, 0)
	f.divider = create_line(f, hex("ffffff", 0.06), "ARTWORK")
	f.divider:SetWidth(1)
	f.divider:SetPoint("TOPLEFT", SIDEBAR_W - 1, -1)
	f.divider:SetPoint("BOTTOMLEFT", SIDEBAR_W - 1, 1)

	-- Master switch
	f.master = create_toggle(38, 20)
	f.master:SetParent(f)
	f.master:SetPoint("LEFT", 18, 0)
	f.master.on_click = function(self)
		local res = resolve_path("bar_enabled")
		if not res then return end
		local info = make_info(res)
		self:SetOn(not self.on, true)
		set_value(res, info, self.on)
	end
	f.dot = f:CreateTexture(nil, "ARTWORK")
	f.dot:SetTexture(TEX.circle)
	f.dot:SetSize(8, 8)
	f.dot:SetPoint("LEFT", f.master, "RIGHT", 9, 0)
	f.dot_glow = f:CreateTexture(nil, "BACKGROUND", nil, 2)
	f.dot_glow:SetTexture(TEX.glow)
	f.dot_glow:SetSize(26, 26)
	f.dot_glow:SetPoint("CENTER", f.dot, "CENTER")
	f.dot_glow:SetBlendMode("ADD")
	f.status = create_text(f, FONT.medium, FS.footer, C.text)
	f.status:SetPoint("LEFT", f.dot, "RIGHT", 6, 0)
	f.status:SetJustifyV("MIDDLE")

	-- Ret only
	f.ret = create_toggle(38, 20)
	f.ret:SetParent(f)
	f.ret:SetPoint("RIGHT", f, "LEFT", SIDEBAR_W - 68, 0)
	f.ret.on_click = function(self)
		local res = resolve_path("ret_only")
		if not res then return end
		local info = make_info(res)
		self:SetOn(not self.on, true)
		set_value(res, info, self.on)
	end
	f.ret_label = create_text(f, FONT.medium, FS.footer, C.text_soft)
	f.ret_label:SetPoint("LEFT", f.ret, "RIGHT", 8, 0)
	f.ret_label:SetJustifyV("MIDDLE")
	f.ret_label:SetText("Ret only")

	f.hint = create_text(f, FONT.regular, FS.footer, C.muted)
	f.hint:SetPoint("LEFT", SIDEBAR_W + PAD, 0)
	f.hint:SetJustifyV("MIDDLE")
	f.hint:SetText("Changes apply instantly")

	f.unlock = create_button(f, "Design mode", function()
		if st.editmode and st.editmode.toggle then st.editmode.toggle() end
	end)
	f.unlock:SetPoint("RIGHT", -30, 0)
	f.reset = create_button(f, "Reset page", function() UI.reset_current_page() end)
	f.reset:SetPoint("RIGHT", f.unlock, "LEFT", -10, 0)
	return f
end

local function update_footer()
	local f = win.footer
	local db = ST.db and ST.db.profile
	if not db then return end
	local enabled = db.bar_enabled and true or false
	f.master:SetOn(enabled, false)
	f.status:SetText(enabled and "Enabled" or "Disabled")
	if enabled then
		f.dot:SetVertexColor(unpack(C.green))
		f.dot_glow:SetVertexColor(C.green[1], C.green[2], C.green[3], 0.5)
		f.dot_glow:Show()
	else
		f.dot:SetVertexColor(unpack(C.dim))
		f.dot_glow:Hide()
	end
	f.ret:SetOn(db.ret_only and true or false, false)
	local designing = st.editmode and st.editmode.active and st.editmode.active()
	f.unlock:SetText(designing and "Exit design mode" or "Design mode")
	if st.spec and st.spec.describe then
		local label, points = st.spec.describe()
		f.hint:SetText("Detected spec: |cFFFFD27A" .. label .. "|r  " .. points)
	end
end

---------------------------------------------------------------------------------------
-- Window scale: the whole window (and everything in it) scales via SetScale, driven by a
-- drag grip in the bottom-right corner. The top-left corner stays put while dragging.
---------------------------------------------------------------------------------------
local function clamp_scale(scale)
	local uw, uh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
	local fit = (uw > 0 and uh > 0) and min(uw / WIN_W, uh / WIN_H) or SCALE_MAX
	return max(SCALE_MIN, min(SCALE_MAX, fit, tonumber(scale) or SCALE_DEFAULT))
end

-- Apply a scale. If left/top (in UIParent units) are given, pin the top-left corner there.
local function apply_scale(scale, left, top)
	scale = clamp_scale(scale)
	win:SetScale(scale)
	if left and top then
		win:ClearAllPoints()
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
	end
	return scale
end

local function create_resize_grip()
	local g = CreateFrame("Button", nil, win)
	g:SetSize(22, 22)
	g:SetPoint("BOTTOMRIGHT", -4, 4)
	g:SetFrameLevel((win.footer:GetFrameLevel() or 0) + 5)
	g:RegisterForClicks("LeftButtonUp")
	-- Six dots in a diagonal triangle, the classic resize-grip glyph.
	g.dots = {}
	for _, d in ipairs({ { 4, 4 }, { 9, 4 }, { 14, 4 }, { 4, 9 }, { 9, 9 }, { 4, 14 } }) do
		local t = g:CreateTexture(nil, "OVERLAY")
		t:SetTexture(TEX.circle)
		t:SetSize(3, 3)
		t:SetPoint("BOTTOMRIGHT", -d[1], d[2])
		t:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 0.9)
		g.dots[#g.dots + 1] = t
	end
	local function tint(color, a)
		for _, t in ipairs(g.dots) do t:SetVertexColor(color[1], color[2], color[3], a) end
	end
	g:SetScript("OnEnter", function()
		tint(C.white, 1)
		GameTooltip:SetOwner(g, "ANCHOR_TOPLEFT")
		GameTooltip:SetText("Drag to resize", 1, 1, 1)
		GameTooltip:AddLine("Double-click to reset to the default size.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	g:SetScript("OnLeave", function() if not g.resizing then tint(C.muted, 0.9) end; GameTooltip:Hide() end)

	g:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		local s, ue = win:GetScale(), UIParent:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		cx, cy = cx / ue, cy / ue
		-- Frame edges in UIParent units, plus where the cursor grabbed the corner.
		g.left, g.top = win:GetLeft() * s, win:GetTop() * s
		g.grab_dx, g.grab_dy = win:GetRight() * s - cx, cy - win:GetBottom() * s
		g.resizing = true
		tint(C.accent, 1)
		g:SetScript("OnUpdate", function()
			local ue2 = UIParent:GetEffectiveScale()
			local x, y = GetCursorPosition()
			x, y = x / ue2 + g.grab_dx, y / ue2 - g.grab_dy
			local wanted = max((x - g.left) / WIN_W, (g.top - y) / WIN_H)
			apply_scale(wanted, g.left, g.top)
		end)
	end)
	local function stop()
		if not g.resizing then return end
		g.resizing = false
		g:SetScript("OnUpdate", nil)
		tint(g:IsMouseOver() and C.white or C.muted, g:IsMouseOver() and 1 or 0.9)
		local db = ST.db and ST.db.profile
		if db then db.settings_scale = win:GetScale() end
	end
	g.stop = stop
	g:SetScript("OnMouseUp", stop)
	g:SetScript("OnHide", stop)
	g:SetScript("OnDoubleClick", function()
		local s = win:GetScale()
		apply_scale(SCALE_DEFAULT, win:GetLeft() * s, win:GetTop() * s)
		local db = ST.db and ST.db.profile
		if db then db.settings_scale = SCALE_DEFAULT end
	end)
	return g
end

local function create_window()
	win = CreateFrame("Frame", "SwedgeTimerSettingsFrame", UIParent)
	win:SetSize(WIN_W, WIN_H)
	win:SetPoint("CENTER")
	win:SetFrameStrata("HIGH")
	win:SetToplevel(true)
	win:SetMovable(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:Hide()

	win.skin = add_rounded(win, { radius = RADIUS, fill = C.bg, border = C.win_border, sub = -7 })

	-- Key art (optional) with a fade mask, then the radiance glow.
	local art = win:CreateTexture(nil, "BACKGROUND", nil, -5)
	art:SetPoint("TOPLEFT", ART_X, -1)
	art:SetPoint("TOPRIGHT", -1, -1)
	art:SetHeight(ART_H)
	local found = false
	for _, path in ipairs({ IMG .. "keyart.tga", IMG .. "keyart.png", IMG .. "keyart.blp" }) do
		if art:SetTexture(path) then found = true; break end
	end
	if found then
		-- Native scale from the art's left edge: pushing it right crops the right-hand side rather than squashing it.
		art:SetTexCoord(0, math.min(1, (WIN_W - ART_X - 1) / ART_NATIVE_W), 0, 0.79)
		art:SetVertexColor(0.92, 0.92, 0.92)
		if win.CreateMaskTexture and art.AddMaskTexture then
			local mask = win:CreateMaskTexture()
			mask:SetTexture(TEX.artmask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(art)
			art:AddMaskTexture(mask)
		else
			local fade = win:CreateTexture(nil, "BACKGROUND", nil, -4)
			fade:SetTexture(TEX.gradient)
			fade:SetTexCoord(0, 1, 1, 0)
			fade:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 1)
			fade:SetPoint("TOPLEFT", art, "TOPLEFT", 0, -130)
			fade:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", 0, 0)
			local lfade = win:CreateTexture(nil, "BACKGROUND", nil, -4)
			lfade:SetTexture(TEX.gradient)
			lfade:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1) -- rotated: opaque on the left, clear on the right
			lfade:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 1)
			lfade:SetPoint("TOPLEFT", art, "TOPLEFT", 0, 0)
			lfade:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", 0, 0)
			lfade:SetWidth(160)
		end
	else
		art:Hide()
	end
	win.art = art

	-- The radiance glows are centred on the top edge, so only their lower part falls inside
	-- the window. Anchor that part to the top edge and crop the texture to match, so nothing
	-- draws past the window border.
	local function top_glow(w, h, cx, cy, r, g, b, a)
		local t = win:CreateTexture(nil, "BACKGROUND", nil, -3)
		t:SetTexture(TEX.glow)
		local above = h / 2 - cy          -- how much of the glow would sit above the top edge
		local visible = h - above
		t:SetSize(w, visible)
		t:SetPoint("TOP", win, "TOP", cx, -1)
		t:SetTexCoord(0, 1, above / h, 1)
		t:SetBlendMode("ADD")
		t:SetVertexColor(r, g, b, a)
		return t
	end
	top_glow(720, 300, 130, 10, 1, 0.82, 0.48, found and 0.14 or 0.2)
	top_glow(420, 200, 90, 0, 1, 0.6, 0.2, found and 0.08 or 0.12)

	win.sidebar = create_sidebar()
	win.header = create_header()
	win.content = create_content()
	win.footer = create_footer()
	win.grip = create_resize_grip()

	win:SetScript("OnShow", function()
		local db = ST.db and ST.db.profile
		apply_scale(db and db.settings_scale or SCALE_DEFAULT)
		dirty = true
	end)
	win:SetScript("OnHide", function()
		if win.grip then win.grip.stop() end
		UI.close_pullout()
		if ST.OnSettingsClosed then ST:OnSettingsClosed() end
	end)
	win:SetScript("OnUpdate", function()
		if dirty and not suppress_refresh then
			dirty = false
			UI.rebuild()
		end
	end)

	tinsert(UISpecialFrames, "SwedgeTimerSettingsFrame")
end

--=======================================================================================
-- Building the current view
--=======================================================================================
local function current_view()
	local page = page_by_id(state.page)
	local q = strlower(state.query or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if q ~= "" then
		local sections = {}
		for _, p in ipairs(PAGES) do
			local lists = p.tabs and p.tabs or { { label = nil, sections = p.sections } }
			for _, t in ipairs(lists) do
				for _, s in ipairs(t.sections) do
					local rows = {}
					for _, path in ipairs(s.rows) do
						local row = build_row(path)
						if row and is_control_kind(row.kind) then
							local hay = strlower(strip_codes(row.name) .. " " .. strip_codes(row.desc or "") .. " " .. s.title)
							if hay:find(q, 1, true) then rows[#rows + 1] = row end
						end
					end
					if #rows > 0 then
						sections[#sections + 1] = { title = s.title, crumb = t.label and (p.label .. " > " .. t.label) or p.label, rows = rows }
					end
				end
			end
		end
		if #sections == 0 then
			sections[1] = { title = "No matches", crumb = "", rows = {
				{ kind = "desc", name = "Nothing matches \"" .. state.query .. "\". Search covers setting names and descriptions on every page.", opt = {} },
			} }
		end
		return { group = "Results", title = "Search: \"" .. state.query .. "\"", sections = sections, tabs = nil }
	end

	local sections_spec
	if page.tabs then
		state.tab = max(1, min(#page.tabs, state.tab or 1))
		sections_spec = page.tabs[state.tab].sections
	else
		sections_spec = page.sections
	end
	local sections = {}
	for _, s in ipairs(sections_spec) do
		local rows = {}
		for _, path in ipairs(s.rows) do
			local row = build_row(path)
			if row then rows[#rows + 1] = row end
		end
		if #rows > 0 then sections[#sections + 1] = { title = s.title, crumb = "", rows = rows } end
	end
	return { group = page.group, title = page.label, sections = sections, tabs = page.tabs, page = page }
end

local function layout_tabs(view)
	local bar = win.content.tabbar
	if not view.tabs then bar:Hide(); return 0 end
	bar:Show()
	for _, b in ipairs(bar.buttons) do b:Hide() end
	local x = 4
	for i, t in ipairs(view.tabs) do
		local b = bar.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, bar)
			b:SetHeight(28)
			b.skin = add_rounded(b, { radius = 7, fill = { 0, 0, 0, 0 } })
			b.label = create_text(b, FONT.bold, FS.tab, C.tab_idle_text)
			b.label:SetPoint("CENTER")
			b.label:SetJustifyV("MIDDLE")
			b:SetScript("OnEnter", function(s) if not s.active then s.skin:SetFill(unpack(C.tab_hover)) end end)
			b:SetScript("OnLeave", function(s) if not s.active then s.skin:SetFill(0, 0, 0, 0) end end)
			b:SetScript("OnClick", function(s) state.tab = s.index; state.scroll = 0; UI.request_refresh() end)
			bar.buttons[i] = b
		end
		b.index = i
		b.active = (i == state.tab)
		b.label:SetText(t.label)
		b:SetWidth(b.label:GetStringWidth() + 30)
		b:ClearAllPoints()
		b:SetPoint("LEFT", bar, "LEFT", x, 0)
		if b.active then
			b.skin:SetFill(unpack(C.accent))
			set_color(b.label, C.accent_text)
		else
			b.skin:SetFill(0, 0, 0, 0)
			set_color(b.label, C.tab_idle_text)
		end
		b:Show()
		x = x + b:GetWidth() + 4
	end
	bar:SetWidth(x)
	return 36 + 10
end

function UI.rebuild()
	if not win or not ST.db then return end
	ensure_coverage()
	release_all(WIN_HOST)

	local view = current_view()
	win.header.group:SetText(strupper(view.group or ""))
	win.header.title:SetText(view.title or "")

	local content = win.content
	local tabs_h = layout_tabs(view)
	content.scroll:ClearAllPoints()
	content.scroll:SetPoint("TOPLEFT", PAD, -(16 + tabs_h))
	content.scroll:SetPoint("BOTTOMRIGHT", -PAD + 8, 18)
	content.bar:ClearAllPoints()
	content.bar:SetPoint("TOPRIGHT", -10, -(18 + tabs_h))
	content.bar:SetPoint("BOTTOMRIGHT", -10, 20)

	local width = (WIN_W - SIDEBAR_W) - PAD * 2
	content.child:SetWidth(width)
	local y = 0
	for _, s in ipairs(view.sections) do
		local sec = acquire(WIN_HOST, "section", new_section, content.child)
		sec:SetPoint("TOPLEFT", content.child, "TOPLEFT", 0, -y)
		sec:SetWidth(width)
		sec.title:SetText(strupper(s.title))
		sec.crumb:SetText(s.crumb or "")
		local sy = SECTION_TITLE_H + 1
		for i, row in ipairs(s.rows) do
			local rowf = acquire(WIN_HOST, "row", new_row, sec)
			rowf.host = WIN_HOST
			rowf:SetPoint("TOPLEFT", sec, "TOPLEFT", 1, -sy)
			local h = layout_row(rowf, row, width - 2, i == 1)
			apply_row_state(rowf)
			live_rows[#live_rows + 1] = rowf
			sy = sy + h
		end
		sec:SetHeight(sy + 6)
		y = y + sy + 6 + SECTION_GAP
	end
	local total = max(1, y - SECTION_GAP)
	content.child:SetHeight(total)

	local view_h = content.scroll:GetHeight()
	if view_h <= 0 then view_h = WIN_H - HEADER_H - FOOTER_H - 34 - tabs_h end
	local max_scroll = max(0, total - view_h)
	content.bar:SetMinMaxValues(0, max_scroll)
	local thumb = content.bar:GetThumbTexture()
	if max_scroll > 0 then
		content.bar:Show()
		thumb:SetHeight(max(24, (view_h / total) * (view_h - 4)))
	else
		content.bar:Hide()
	end
	local sv = max(0, min(max_scroll, state.scroll or 0))
	content.bar:SetValue(sv)
	content.scroll:SetVerticalScroll(sv)

	update_nav()
	update_footer()
end

function UI.request_refresh()
	dirty = true
	for _, host in ipairs(hosts) do
		if host.on_refresh then host.on_refresh(host) end
	end
end

function UI.refresh_suppressed()
	return suppress_refresh
end

function UI.set_query(q)
	state.query = q or ""
	state.scroll = 0
	UI.request_refresh()
end

function UI.show_page(id, tab)
	if state.page ~= id or state.query ~= "" or (tab and tab ~= state.tab) then state.scroll = 0 end
	state.page = id
	state.tab = tab or 1
	if state.query ~= "" then
		state.query = ""
		if win then win.sidebar.search.edit:SetText("") end
	end
	UI.request_refresh()
end

function UI.toggle_bar_lock()
	local res = resolve_path("positioning.bar_locked")
	if not res then return end
	local info = make_info(res)
	local locked = get_value(res, info)
	set_value(res, info, not locked)
end

--=======================================================================================
-- Shared pieces for other SwedgeTimer windows (design mode): the theme, the chrome
-- widgets, direct option access, and a row builder that renders AceConfig option paths
-- into any frame with the compact layout.
--=======================================================================================
UI.theme = { C = C, FONT = FONT, TEX = TEX, FS = FS, hex = hex, RADIUS = RADIUS }
UI.create_panel = create_panel
UI.create_button = create_button
UI.create_text = create_text
UI.create_toggle = create_toggle
UI.add_rounded = add_rounded
UI.set_font = set_font
UI.set_color = set_color
UI.new_host = new_host
UI.release_host = release_all

function UI.option_get(path)
	local res = resolve_path(path)
	if not res then return nil end
	return get_value(res, make_info(res))
end

function UI.option_set(path, ...)
	local res = resolve_path(path)
	if not res then return end
	set_value(res, make_info(res), ...)
end

function UI.option_name(path)
	local res = resolve_path(path)
	if not res then return path end
	return strip_codes(eval_name(res.option.name, make_info(res)))
end

-- Renders the given option paths as compact rows into `parent`, top-down from (0,0).
-- Returns the total height. Hidden options are skipped; unknown paths are ignored.
function UI.build_rows(host, parent, paths, width)
	release_all(host)
	local y = 0
	local n = 0
	for _, path in ipairs(paths) do
		local row = build_row(path)
		if row then
			n = n + 1
			local rowf = acquire(host, "row", new_row, parent)
			rowf.host = host
			rowf:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
			local h = layout_row(rowf, row, width, n == 1, true)
			apply_row_state(rowf)
			host.rows[#host.rows + 1] = rowf
			y = y + h
		end
	end
	return y
end

-- Restore every option on the current page/tab that has an entry in the defaults table.
function UI.reset_current_page()
	if state.query ~= "" then print("Clear the search to reset a page."); return end
	local page = page_by_id(state.page)
	local sections = page.tabs and page.tabs[state.tab or 1].sections or page.sections
	local defaults = ST.defaults and ST.defaults.profile or {}
	local title = page.tabs and (page.label .. " / " .. page.tabs[state.tab or 1].label) or page.label
	local function copy(v)
		if type(v) ~= "table" then return v end
		local t = {}
		for k, x in pairs(v) do t[k] = copy(x) end
		return t
	end
	UI.confirm("Reset all settings on \"" .. title .. "\" to their defaults?", function()
		silent_set = true
		for _, s in ipairs(sections) do
			for _, path in ipairs(s.rows) do
				local res = resolve_path(path)
				local t = res and res.option.type
				if res and res.root == get_roots().main
					and (t == "toggle" or t == "range" or t == "select" or t == "input" or t == "color") then
					local key = res.keys[#res.keys]
					local d = defaults[key]
					if d ~= nil then
						-- Restore the stored value, then run the option's own setter with what its
						-- getter reports so unit conversions and visual side effects stay correct.
						ST.db.profile[key] = copy(d)
						local info = make_info(res)
						if t == "color" then
							local r, g, b, a = get_value(res, info)
							do_set(res, info, r, g, b, a)
						else
							do_set(res, info, get_value(res, info))
						end
					end
				end
			end
		end
		silent_set = false
		UI.request_refresh()
	end)
end

--=======================================================================================
-- Public API
--=======================================================================================
function UI.open()
	if not ST.db then print("SwedgeTimer is still loading."); return end
	if not win then create_window() end
	if not win:IsShown() then
		win:Show()
	end
	dirty = true
end

function UI.close()
	if win then win:Hide() end
end

function UI.toggle()
	if win and win:IsShown() then UI.close() else UI.open() end
end

function UI.is_open()
	return win and win:IsShown() or false
end

-- Refresh when other code (e.g. the practice toggle) notifies AceConfig of a change.
do
	local registry = LibStub("AceConfigRegistry-3.0", true)
	if registry and registry.RegisterCallback then
		registry.RegisterCallback(UI, "ConfigTableChange", function(_, appName)
			if UI.is_open() then UI.request_refresh() end
		end)
	end
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed settings_ui.lua module correctly') end
