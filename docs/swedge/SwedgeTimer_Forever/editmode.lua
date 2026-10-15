-- editmode.lua ========================================================================
-- Design mode: the global unlock. `/st design` (or the "Design mode" footer button)
-- unlocks EVERY on-screen element at once - the swing bar, the seal icons, the
-- successful twist text, the Next Action Guide and, while practicing, the Practice
-- Mode displays. A snap grid drops over the screen, every element is force-shown with
-- sample content (disabled ones as ghosts) and gets a labelled overlay that:
--   - drags anywhere on its body (positions snap to the grid; hold Shift to place freely)
--   - Ctrl-click marks it; "Select all" on the toolbar marks everything. Dragging any
--     marked element moves the whole selection together (the dragged one snaps, the
--     rest keep their offsets to it)
--   - carries no label of its own (the hover tooltip and the toolbar chip name it)
--   - opens a quick card on click with that element's key dials, rendered from the
--     same AceConfig options the settings window uses (st.settings_ui.build_rows), plus
--     "Reset position" and "All settings".
-- The toolbar at the top carries one chip per element with its on/off switch (elements
-- often sit close together, so switches on the elements themselves got in the way);
-- clicking a chip's name opens that element's card. "Effects & sounds" is a chip without
-- a frame: its card holds the twist feedback family. The "Simulate twists" button runs
-- the 1/2 rotation on the preview - a Command swing that twists to Blood, then a Blood
-- swing - firing the real sounds, glow and success text so they can be tested live.
-- The toolbar and cards scale with `design_scale` (a grip on each card drags it).
-- Esc, Done, `/st lock` or entering combat ends it. Ported from ClassicRaidTools'
-- EditMode.lua and reshaped around SwedgeTimer's module layout.
--
-- Elements are described by descriptors in ELEMENTS below (st.editmode.register adds
-- more). Each has:
--   key, title         identity + toolbar/card label
--   frame()            -> the live frame (nil while the module hasn't built it);
--                      absent for a "virtual" element that only has a chip and a card
--   available()        optional; false hides the element from design mode (practice)
--   enable_path        AceConfig path of the element's on/off toggle (tag switch)
--   card               list of AceConfig paths for the quick card
--   settings           { page =, tab = } for the "All settings" button
--   fixed()            optional; true = can't be dragged (icons attached to the bar)
--   fixed_hint         hover hint while fixed
--   save(x, y)         write a new CENTER/CENTER offset and re-anchor
--   reset()            put the element back at its default position
--   box()              optional; the frame whose rect the overlay hugs and aligns by
--                      (the bar's backplane) when it differs from the moved frame
--   pad                { l, r, t, b } (or a function returning it) extra overlay pixels
--                      beyond the box; negative values shrink the box (the bar)
--   border()           optional; the drawn border thickness on the box edge in px.
--                      Two abutting borders overlap by the thinner one when snapping
--
-- Overlays are children of their targets, so they ride every move, scale and show/hide.
-- The grid lives on its own BACKGROUND-strata layer behind everything.
--=======================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon("SwedgeTimer")
local print = st.utils.print_msg

st.editmode = st.editmode or {}
local EM = st.editmode

local max, min, floor, abs = math.max, math.min, math.floor, math.abs

local GRID_STEPS = { 0, 16, 24, 32, 48 }
local PANEL_W = 300
local PANEL_PAD = 16
local PANEL_TITLE_H = 40
local TICK = 0.3                         -- overlay refresh cadence while unlocked
local TOOLBAR_H = 94
local TOOLBAR_MIN_W = 700
local CHIP_H = 26
local CENTER_MAGNET = 8                  -- px: within this of the screen centre = centred
local ALIGN_REACH = 120                  -- px: only elements this close (on the other axis) offer their lines
local SCALE_MIN, SCALE_MAX = 0.4, 1.5
local TOOLBAR_TOP = 26                   -- gap from the screen top, in UIParent px
local IMG = "Interface\\AddOns\\SwedgeTimer\\Images\\"
local ART_V0, ART_V1 = 0.20, 0.50        -- the band of the key art shown on the toolbar
local ART_MAX_W = 620

local active = false
local layer, toolbar, panel, effects_panel, guides
local overlays = {}                      -- pooled element overlays
local grid_lines = {}                    -- pooled 1px line textures on the layer
local registry = {}                      -- element descriptors in order
local panel_host                         -- settings_ui row host for the quick card
local panel_overlay                      -- the overlay whose card is open
local panel_dirty = false
local combat_frame
local simulating = false
local selected = {}                      -- element key -> true: the marked elements

local function UI() return st.settings_ui end
local function theme() return st.settings_ui.theme end
local function db() return ST.db.profile end

--=========================================================================================
-- Public state
--=========================================================================================
function EM.active() return active end

--=========================================================================================
-- Selection: marked elements move together
--=========================================================================================
function EM.is_selected(desc)
	return desc ~= nil and selected[desc.key] == true
end

function EM.selection_count()
	local n = 0
	for _ in pairs(selected) do n = n + 1 end
	return n
end

local overlay_paint_ref, refresh_toolbar_selection   -- forward declarations

function EM.set_selected(desc, on)
	if not desc then return end
	if on then selected[desc.key] = true else selected[desc.key] = nil end
	if refresh_toolbar_selection then refresh_toolbar_selection() end
end

function EM.clear_selection()
	for k in pairs(selected) do selected[k] = nil end
	if refresh_toolbar_selection then refresh_toolbar_selection() end
end
function EM.simulating() return active and simulating end

function EM.scale()
	local s = tonumber(db().design_scale) or 0.7
	return max(SCALE_MIN, min(SCALE_MAX, s))
end

function EM.card_scale()
	local s = tonumber(db().design_card_scale) or 0.7
	return max(SCALE_MIN, min(SCALE_MAX, s))
end

function EM.register(desc)
	registry[#registry + 1] = desc
end

function EM.grid_step()
	local g = tonumber(db().design_grid) or 0
	return g >= 8 and g or 0
end

--=========================================================================================
-- Geometry helpers
--=========================================================================================

-- A frame's centre as an offset from the screen centre in UIParent units (frames can
-- carry their own scale, e.g. the next action guide).
local function center_offsets(frame)
	local s = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	local cx, cy = frame:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not (cx and cy and ux and uy) then return 0, 0 end
	return cx * s - ux, cy * s - uy
end

-- A frame's size in UIParent units (frames can carry their own scale).
local function screen_size(frame)
	local s = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	return (frame:GetWidth() or 0) * s, (frame:GetHeight() or 0) * s
end

-- A frame's edges as offsets from the screen centre in UIParent units:
-- left, right, top, bottom (nil when it has no rect yet).
local function screen_rect(frame)
	local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
	if not (l and r and t and b) then return nil end
	local s = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	local ux, uy = UIParent:GetCenter()
	if not (ux and uy) then return nil end
	return l * s - ux, r * s - ux, t * s - uy, b * s - uy
end

-- An overlay's visible box (its box frame plus pads) as screen-centre offsets.
local function box_rect(o)
	local f = o.box or o.target
	if not f then return nil end
	local l, r, t, b = screen_rect(f)
	if not l then return nil end
	local pad = o.pad or {}
	local es = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	return l - (pad.l or 0) * es, r + (pad.r or 0) * es, t + (pad.t or 0) * es, b - (pad.b or 0) * es
end

-- Alignment: the edges and centre lines of every OTHER element on screen, plus the
-- screen centre. `xs` are vertical lines (x offsets), `ys` horizontal ones.
local alignment_overlays   -- set by refresh(): the live overlay list
-- `exclude` is one overlay or a set { [overlay] = true } (a group being dragged)
-- Each line is { v = offset, kind = "lo" | "hi" | "mid", border = px }: "lo" is the
-- left / bottom edge, "hi" the right / top edge, "mid" the centre. The border is the
-- element's own drawn border on that edge, so abutting borders can be stacked.
-- ml/mr/mt/mb is the dragged box: an element only offers its vertical lines when it is
-- within ALIGN_REACH of that box vertically (and its horizontal lines when it is within
-- reach horizontally) - something on the far side of the screen never grabs a drop.
local function alignment_lines(exclude, ml, mr, mt, mb)
	local xs, ys = { { v = 0, kind = "mid", border = 0 } }, { { v = 0, kind = "mid", border = 0 } }
	local ex = exclude
	if exclude and exclude.desc then ex = { [exclude] = true } end
	ex = ex or {}
	for _, o in ipairs(alignment_overlays or {}) do
		if not ex[o] and o:IsShown() and o.desc then
			local l, r, t, b = box_rect(o)
			if l then
				local bd = o.edge_border or 0
				local xgap = max(0, l - (mr or l), (ml or r) - r)
				local ygap = max(0, b - (mt or b), (mb or t) - t)
				if ygap <= ALIGN_REACH then
					xs[#xs + 1] = { v = l, kind = "lo", border = bd }
					xs[#xs + 1] = { v = r, kind = "hi", border = bd }
					xs[#xs + 1] = { v = (l + r) / 2, kind = "mid", border = 0 }
				end
				if xgap <= ALIGN_REACH then
					ys[#ys + 1] = { v = b, kind = "lo", border = bd }
					ys[#ys + 1] = { v = t, kind = "hi", border = bd }
					ys[#ys + 1] = { v = (t + b) / 2, kind = "mid", border = 0 }
				end
			end
		end
	end
	return xs, ys
end

-- Where one of my lines should land against a candidate. Two elements that ABUT
-- (my low edge against their high edge, or the reverse) overlap by the thinner of the
-- two borders, so 2 px + 2 px reads as one 2 px line instead of a 4 px band. Lines of
-- the same kind (tops level, lefts level) and centres align exactly.
local function target_for(mine, cand)
	local overlap = min(mine.border or 0, cand.border or 0)
	if overlap > 0 then
		if mine.kind == "lo" and cand.kind == "hi" then return cand.v - overlap end   -- I sit right of / below them
		if mine.kind == "hi" and cand.kind == "lo" then return cand.v + overlap end   -- I sit left of / above them
	end
	return cand.v
end

-- The closest alignment within the magnet for one axis: `mine` are the dragged
-- box's own lines (edges + centre), `lines` the candidates. Returns the delta to
-- apply and the line hit (nil when nothing is close enough).
local function nearest(mine, lines)
	local best_d, best_line
	for _, m in ipairs(mine) do
		for _, ln in ipairs(lines) do
			local target = target_for(m, ln)
			local d = target - m.v
			if abs(d) <= CENTER_MAGNET and (not best_d or abs(d) < abs(best_d)) then
				best_d, best_line = d, target
			end
		end
	end
	return best_d, best_line
end

-- Alignment for a dragged element whose BOX (the visible rect) is at l/r/t/b. The
-- screen centre only attracts the element's centre; other elements attract every
-- edge and the centre. Returns dx, dy (nil = free on that axis) and the lines hit.
function EM.align(l, r, t, b, exclude, border)
	local xs, ys = alignment_lines(exclude, l, r, t, b)
	border = border or 0
	local cx, cy = (l + r) / 2, (t + b) / 2
	local mx = { { v = l, kind = "lo", border = border }, { v = r, kind = "hi", border = border }, { v = cx, kind = "mid", border = 0 } }
	local my = { { v = b, kind = "lo", border = border }, { v = t, kind = "hi", border = border }, { v = cy, kind = "mid", border = 0 } }
	-- screen centre (index 1) vs the centre only; element lines vs everything
	local dx, gx = nearest({ mx[3] }, { xs[1] })
	local dx2, gx2 = nearest(mx, { unpack(xs, 2) })
	if dx2 and (not dx or abs(dx2) < abs(dx)) then dx, gx = dx2, gx2 end
	local dy, gy = nearest({ my[3] }, { ys[1] })
	local dy2, gy2 = nearest(my, { unpack(ys, 2) })
	if dy2 and (not dy or abs(dy2) < abs(dy)) then dy, gy = dy2, gy2 end
	return dx, dy, gx, gy
end

-- Snap a dropped element. Priority per axis: an edge / centre lined up with another
-- element or the screen centre (within the magnet) wins outright; otherwise the box's
-- top-left corner lands on the grid (edges are what the eye aligns, not centres).
-- Shift while dropping skips both. x/y = the frame's centre offsets, l/r/t/b = the
-- visible box's edges. Returns the new centre offsets.
function EM.snap(x, y, l, r, t, b, exclude, border)
	local g = EM.grid_step()
	local function half(v) return floor(v * 2 + 0.5) / 2 end
	if IsShiftKeyDown and IsShiftKeyDown() then
		return half(x), half(y)
	end
	local dx, dy = EM.align(l, r, t, b, exclude, border)
	local sx, sy
	if dx then
		sx = x + dx
	elseif g == 0 then
		sx = half(x)
	else
		sx = half(x + (floor(l / g + 0.5) * g - l))
	end
	if dy then
		sy = y + dy
	elseif g == 0 then
		sy = half(y)
	else
		sy = half(y + (floor(t / g + 0.5) * g - t))
	end
	return sx, sy
end

-- Whether centre offsets count as horizontally / vertically centred on the screen.
function EM.centred(x, y)
	return abs(x) <= CENTER_MAGNET, abs(y) <= CENTER_MAGNET
end

local function defaults()
	return ST.defaults and ST.defaults.profile or {}
end

--=========================================================================================
-- Element descriptors
--=========================================================================================
local ELEMENTS = {
	{
		key = "bar", title = "Swing bar",
		frame = function() return st.bar and st.bar.frame end,
		enable_path = "features.bar_enabled",
		card = {
			"features.bar_enabled", "positioning.bar_width", "positioning.bar_height",
			"bar_behaviour.visibility_key", "bar_appearance.bar_texture_key", "bar_appearance.backplane_alpha",
			"features.enable_deadzone", "bar_appearance.gcd1_enabled", "features.judgement_marker_enabled",
		},
		settings = { page = "bar", tab = 1 },
		-- the visible edge is the backplane's outline: the backplane frame itself
		-- reaches one backdrop inset (6 px) further out on every side, so shrink by it
		box = function() return st.bar and st.bar.frame and st.bar.frame.backplane end,
		border = function() return st.bar and st.bar.visible_outline and st.bar.visible_outline() or 0 end,
		pad = function()
			local bp = st.bar and st.bar.frame and st.bar.frame.backplane
			local ins = bp and bp.backdropInfo and bp.backdropInfo.insets or nil
			local i = ins and (ins.left or 6) or 6
			return { l = -i, r = -i, t = -i, b = -i }
		end,
		save = function(x, y)
			local p = db()
			p.bar_point, p.bar_rel_point = "CENTER", "CENTER"
			p.bar_x_offset, p.bar_y_offset = x, y
			st.set_bar_position()
		end,
		reset = function()
			local p, d = db(), defaults()
			p.bar_point, p.bar_rel_point = d.bar_point, d.bar_rel_point
			p.bar_x_offset, p.bar_y_offset = d.bar_x_offset, d.bar_y_offset
			st.set_bar_position()
		end,
	},
	{
		key = "icons", title = "Seal icons",
		frame = function() return st.bar and st.bar.icon_frame end,
		enable_path = "icon_settings.icon_enabled",
		card = {
			"icon_settings.icon_enabled", "icon_settings.icon_detached", "icon_settings.icon_match_bar_height",
			"icon_settings.icon_size", "icon_settings.icon_spacing", "icon_settings.icon_centered",
			"icon_settings.seal_timer_enabled", "icon_settings.seal_cooldown_overlay_enabled",
		},
		settings = { page = "bar", tab = 5 },
		fixed = function() return not db().icon_detached end,
		fixed_hint = "attached to the bar - click, then turn on Detach to move it",
		save = function(x, y)
			local p = db()
			p.icon_point, p.icon_rel_point = "CENTER", "CENTER"
			p.icon_x_offset, p.icon_y_offset = x, y
			st.bar.set_icon_position()
		end,
		reset = function()
			local p, d = db(), defaults()
			p.icon_point, p.icon_rel_point = d.icon_point, d.icon_rel_point
			p.icon_x_offset, p.icon_y_offset = d.icon_x_offset, d.icon_y_offset
			st.bar.set_icon_position()
		end,
	},
	{
		key = "success", title = "Successful twist text",
		frame = function() return st.bar and st.bar.success_text_frame end,
		enable_path = "twist_feedback.successful_twist_text_enabled",
		card = {
			"twist_feedback.successful_twist_text_enabled", "twist_feedback.successful_twist_text_mode",
			"twist_feedback.successful_twist_text_font", "twist_feedback.successful_twist_text_size",
			"twist_feedback.successful_twist_text_outline", "twist_feedback.successful_twist_text_color",
			"twist_feedback.successful_twist_text_duration",
		},
		settings = { page = "feedback" },
		save = function(x, y)
			local p = db()
			p.successful_twist_text_point, p.successful_twist_text_rel_point = "CENTER", "CENTER"
			p.successful_twist_text_x_offset, p.successful_twist_text_y_offset = x, y
			st.bar.set_success_text_position()
		end,
		reset = function()
			local p, d = db(), defaults()
			p.successful_twist_text_point, p.successful_twist_text_rel_point =
				d.successful_twist_text_point, d.successful_twist_text_rel_point
			p.successful_twist_text_x_offset, p.successful_twist_text_y_offset =
				d.successful_twist_text_x_offset, d.successful_twist_text_y_offset
			st.bar.set_success_text_position()
		end,
	},
	{
		key = "nag", title = "Next Action Guide",
		frame = function() return st.nextaction and st.nextaction.frame end,
		border = function() return 2 end,   -- the icons' 2 px "Blizzard Dialog" edge
		enable_path = "nextaction_guide.nextaction_enabled",
		card = {
			"nextaction_guide.nextaction_enabled", "nextaction_guide.nextaction_icon_size",
			"nextaction_guide.nextaction_visibility_key", "nextaction_guide.nextaction_hold_enabled",
			"nextaction_guide.nextaction_show_label", "nextaction_guide.nextaction_show_rotation_text",
			"nextaction_guide.nextaction_show_judgement", "nextaction_guide.nextaction_show_fillers",
		},
		settings = { page = "nag" },
		save = function(x, y)
			local p = db()
			p.nextaction_x, p.nextaction_y = x, y
			st.nextaction.apply_settings()
		end,
		reset = function()
			local p, d = db(), defaults()
			p.nextaction_x, p.nextaction_y = d.nextaction_x, d.nextaction_y
			st.nextaction.apply_settings()
		end,
	},
	{
		key = "hud", title = "Cooldown HUD",
		frame = function() return st.hud and st.hud.frame end,
		border = function() return db().hud_border_size or 0 end,
		enable_path = "cooldown_hud.hud_enabled",
		card = {
			"cooldown_hud.hud_enabled", "cooldown_hud.hud_visibility_key", "cooldown_hud.hud_icon_size",
			"cooldown_hud.hud_match_bar_width", "cooldown_hud.hud_spacing", "cooldown_hud.hud_orientation",
			"cooldown_hud.hud_show_cs", "cooldown_hud.hud_show_judgement", "cooldown_hud.hud_show_consecration",
			"cooldown_hud.hud_show_exorcism", "cooldown_hud.hud_show_trinket1", "cooldown_hud.hud_show_trinket2", "cooldown_hud.hud_show_wings",
			"cooldown_hud.hud_show_text", "cooldown_hud.hud_glow_enabled",
		},
		settings = { page = "hud" },
		save = function(x, y)
			local p = db()
			p.hud_x, p.hud_y = x, y
			st.hud.apply_settings()
		end,
		reset = function()
			local p, d = db(), defaults()
			p.hud_x, p.hud_y = d.hud_x, d.hud_y
			st.hud.apply_settings()
		end,
	},
	{
		key = "rottext", title = "Rotation text",
		frame = function() return st.rotation_text and st.rotation_text.frame end,
		enable_path = "rotation_label.rotation_label_enabled",
		card = {
			"rotation_label.rotation_label_enabled", "rotation_label.rotation_label_visibility_key",
			"rotation_label.rotation_label_format", "rotation_label.rotation_label_align", "rotation_label.rotation_label_font",
			"rotation_label.rotation_label_size", "rotation_label.rotation_label_outline", "rotation_label.rotation_label_color",
		},
		settings = { page = "rottext" },
		save = function(x, y)
			-- x/y are centre offsets; the label stores the offset of its anchor edge
			local p = db()
			local f = st.rotation_text.frame
			local s = f and (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1) or 1
			local w = f and (f:GetWidth() or 0) * s or 0
			local point = st.rotation_text.anchor_point()
			if point == "LEFT" then x = x - w / 2 elseif point == "RIGHT" then x = x + w / 2 end
			p.rotation_label_x, p.rotation_label_y = x, y
			st.rotation_text.apply_settings()
		end,
		reset = function()
			local p, d = db(), defaults()
			p.rotation_label_x, p.rotation_label_y = d.rotation_label_x, d.rotation_label_y
			st.rotation_text.apply_settings()
		end,
	},
	{
		key = "effects", title = "Effects & sounds",
		virtual = true,
		card = {
			"features.twist_sound_enabled", "features.twist_sound_choice",
			"twist_feedback.twist_success_sound_enabled", "twist_feedback.twist_success_sound_choice",
			"twist_feedback.twist_success_glow_enabled", "twist_feedback.twist_success_glow_type",
			"twist_feedback.twist_success_glow_color", "twist_feedback.twist_success_glow_duration",
			"twist_feedback.successful_twist_text_enabled", "features.sound_channel",
		},
		settings = { page = "feedback" },
	},
	{
		key = "practice_rotation", title = "Practice rotation display",
		frame = function() return st.practice and st.practice.rotation_display end,
		available = function() return st.practice and st.practice.active end,
		enable_path = "practice_mode.practice_rotation_display_enabled",
		card = {
			"practice_mode.practice_rotation_display_enabled", "practice_mode.practice_rotation_display_icon_size",
			"practice_mode.practice_rotation_display_icon_spacing",
		},
		settings = { page = "practice", tab = 2 },
		save = function(x, y)
			local p = db()
			p.practice_rotation_display_x, p.practice_rotation_display_y = x, y
			local f = st.practice.rotation_display
			f:ClearAllPoints()
			f:SetPoint("CENTER", UIParent, "CENTER", x, y)
		end,
		reset = function()
			local p, d = db(), defaults()
			p.practice_rotation_display_x, p.practice_rotation_display_y =
				d.practice_rotation_display_x, d.practice_rotation_display_y
			local f = st.practice.rotation_display
			if f then
				f:ClearAllPoints()
				f:SetPoint("CENTER", UIParent, "CENTER", p.practice_rotation_display_x, p.practice_rotation_display_y)
			end
		end,
	},
	{
		key = "practice_timeline", title = "Practice fight timeline",
		frame = function() return st.practice and st.practice.timeline_frame end,
		available = function() return st.practice and st.practice.active end,
		enable_path = "practice_mode.practice_timeline_enabled",
		card = {
			"practice_mode.practice_timeline_enabled", "practice_mode.practice_timeline_mode",
			"practice_mode.practice_timeline_width", "practice_mode.practice_timeline_pixels_per_second",
		},
		settings = { page = "practice", tab = 2 },
		save = function(x, y)
			local p = db()
			p.practice_timeline_x, p.practice_timeline_y = x, y
			local f = st.practice.timeline_frame
			f:ClearAllPoints()
			f:SetPoint("CENTER", UIParent, "CENTER", x, y)
		end,
		reset = function()
			local p, d = db(), defaults()
			p.practice_timeline_x, p.practice_timeline_y = d.practice_timeline_x, d.practice_timeline_y
			local f = st.practice.timeline_frame
			if f then
				f:ClearAllPoints()
				f:SetPoint("CENTER", UIParent, "CENTER", p.practice_timeline_x, p.practice_timeline_y)
			end
		end,
	},
}

for _, desc in ipairs(ELEMENTS) do EM.register(desc) end

local function element_enabled(desc)
	if not desc.enable_path then return true end
	return UI().option_get(desc.enable_path) and true or false
end

--=========================================================================================
-- Chrome helpers (the settings window's theme, so every design surface matches)
--=========================================================================================
local function accent_button(parent, text, on_click)
	local T = theme()
	local b = UI().create_button(parent, text, on_click)
	b.skin:SetFill(unpack(T.C.accent))
	b.skin:SetBorder(0, 0, 0, 0)
	UI().set_font(b.label, T.FONT.bold, T.FS.button)
	UI().set_color(b.label, T.C.accent_text)
	b:SetScript("OnEnter", function(s) s.skin:SetFill(unpack(T.C.accent_hover)) end)
	b:SetScript("OnLeave", function(s) s.skin:SetFill(unpack(T.C.accent)) end)
	return b
end

local function grid_label()
	local g = EM.grid_step()
	return g == 0 and "Grid: off" or ("Grid: " .. g .. " px")
end

-- Scale the toolbar to design_scale and the cards to design_card_scale. Anchor
-- offsets are in the frame's own units, so they are divided by the scale to stay put.
function EM.apply_scale()
	local s = EM.scale()
	if toolbar then
		toolbar:SetScale(s)
		toolbar:ClearAllPoints()
		toolbar:SetPoint("TOP", UIParent, "TOP", 0, -TOOLBAR_TOP / s)
	end
	local cs = EM.card_scale()
	if panel then
		panel:SetScale(cs)
		if panel:IsShown() then EM.position_panel(panel_overlay) end
	end
	if effects_panel then
		effects_panel:SetScale(cs)
		if effects_panel:IsShown() then EM.position_effects() end
	end
end

--=========================================================================================
-- The layer: a dim veil + pooled 1px grid lines out from the screen centre.
-- BACKGROUND strata, so every element floats above its own alignment guides.
--=========================================================================================
local function grid_line(i)
	local t = grid_lines[i]
	if not t then
		t = layer:CreateTexture(nil, "ARTWORK")
		grid_lines[i] = t
	end
	return t
end

local function draw_grid()
	if not layer then return end
	local C = theme().C
	local g = EM.grid_step()
	local w = UIParent:GetWidth() or 1024
	local h = UIParent:GetHeight() or 768
	local cx, cy = w / 2, h / 2
	local n = 0
	local function put(vertical, offset, major, axis)
		n = n + 1
		local t = grid_line(n)
		t:ClearAllPoints()
		if axis then
			t:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.28)
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
		-- no grid: just the centre cross as a reference
		put(true, 0, false, true)
		put(false, 0, false, true)
	end
	for i = n + 1, #grid_lines do grid_lines[i]:Hide() end
end

function EM.refresh_grid()
	if not active then return end
	draw_grid()
	if toolbar and toolbar.grid then toolbar.grid:SetText(grid_label()) end
end

local function ensure_layer()
	if layer then return end
	layer = CreateFrame("Frame", "SwedgeTimerDesignMode", UIParent)
	layer:SetAllPoints(UIParent)
	layer:SetFrameStrata("BACKGROUND")
	layer.dim = layer:CreateTexture(nil, "BACKGROUND")
	layer.dim:SetAllPoints()
	layer.dim:SetColorTexture(0, 0, 0, 0.35)
	-- Esc locks: the layer is a "special frame", so Esc hides it and OnHide finishes
	-- the job (idempotent - lock() on an already hidden layer is harmless)
	tinsert(UISpecialFrames, "SwedgeTimerDesignMode")
	layer:SetScript("OnHide", function()
		if active then EM.lock() end
	end)
	local acc = 0
	layer:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc < TICK then return end
		acc = 0
		EM.refresh()
	end)
	layer:Hide()
end

--=========================================================================================
-- Centre guides: bright lines through the screen centre that light up while a dragged
-- element is centred horizontally / vertically. Above every element, mouse-transparent.
--=========================================================================================
local function ensure_guides()
	if guides then return end
	local C = theme().C
	guides = CreateFrame("Frame", nil, UIParent)
	guides:SetAllPoints(UIParent)
	guides:SetFrameStrata("DIALOG")
	guides:EnableMouse(false)
	guides.v = guides:CreateTexture(nil, "OVERLAY")
	guides.v:SetColorTexture(C.warm_light[1], C.warm_light[2], C.warm_light[3], 0.9)
	guides.v:SetWidth(2)
	guides.v:SetPoint("TOP", guides, "TOP", 0, 0)
	guides.v:SetPoint("BOTTOM", guides, "BOTTOM", 0, 0)
	guides.h = guides:CreateTexture(nil, "OVERLAY")
	guides.h:SetColorTexture(C.warm_light[1], C.warm_light[2], C.warm_light[3], 0.9)
	guides.h:SetHeight(2)
	guides.h:SetPoint("LEFT", guides, "LEFT", 0, 0)
	guides.h:SetPoint("RIGHT", guides, "RIGHT", 0, 0)
	guides.v:Hide()
	guides.h:Hide()
	guides:Hide()
end

-- gx / gy: the vertical / horizontal line to light (offsets from the screen centre),
-- nil to hide that line.
local function show_guides(gx, gy)
	ensure_guides()
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
-- The toolbar: pinned top-centre with the grid dial and Done.
--=========================================================================================
local function ensure_toolbar()
	if toolbar then return end
	local T = theme()
	local C = T.C
	-- opaque fill: the key art's own blacks must be the same black as the panel, or
	-- the seam where the picture starts shows as an edge
	toolbar = UI().create_panel(UIParent, { radius = T.RADIUS, fill = C.bg, border = C.win_border })
	toolbar:SetSize(TOOLBAR_MIN_W, TOOLBAR_H)
	toolbar:SetPoint("TOP", UIParent, "TOP", 0, -TOOLBAR_TOP)
	toolbar:SetFrameStrata("FULLSCREEN_DIALOG")
	toolbar:EnableMouse(true)

	-- the settings window's key art along the right of the header, fading into the
	-- dark on its left edge and towards the chips row; a warm glow if the art is missing
	local art = toolbar:CreateTexture(nil, "BACKGROUND", nil, 1)
	art:SetPoint("TOPRIGHT", -1, -1)
	art:SetPoint("BOTTOMRIGHT", -1, 1)
	local found = false
	for _, path in ipairs({ IMG .. "keyart.tga", IMG .. "keyart.png", IMG .. "keyart.blp" }) do
		if art:SetTexture(path) then found = true; break end
	end
	if found then
		art:SetVertexColor(0.85, 0.85, 0.85, 1)
		-- the picture dissolves into the panel over its whole left half (sized in
		-- layout_toolbar_art): no seam, and the title block never fights it
		local lfade = toolbar:CreateTexture(nil, "BACKGROUND", nil, 2)
		lfade:SetTexture(T.TEX.gradient)
		lfade:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1) -- opaque on the left, clear on the right
		lfade:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 1)
		lfade:SetPoint("TOPLEFT", art, "TOPLEFT", 0, 0)
		lfade:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", 0, 0)
		lfade:SetWidth(300)
		toolbar.lfade = lfade
		-- the chips row stays readable: darken the lower part of the art
		local bfade = toolbar:CreateTexture(nil, "BACKGROUND", nil, 3)
		bfade:SetTexture(T.TEX.gradient)
		bfade:SetTexCoord(0, 1, 1, 0)
		bfade:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 0.85)
		bfade:SetPoint("TOPLEFT", art, "TOPLEFT", 0, -(TOOLBAR_H * 0.35))
		bfade:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", 0, 0)
		toolbar.art_found = true
	else
		art:Hide()
	end
	toolbar.art = art
	toolbar.glow = toolbar:CreateTexture(nil, "BACKGROUND", nil, 2)
	toolbar.glow:SetTexture(T.TEX.glow)
	toolbar.glow:SetBlendMode("ADD")
	toolbar.glow:SetVertexColor(C.warm[1], C.warm[2], C.warm[3], 1)
	toolbar.glow:SetAlpha(found and 0.10 or 0.16)
	toolbar.glow:SetSize(280, 110)
	toolbar.glow:SetPoint("LEFT", -40, 0)

	toolbar.title = UI().create_text(toolbar, T.FONT.bold, 16, C.accent)
	toolbar.title:SetPoint("TOPLEFT", 18, -12)
	toolbar.title:SetShadowColor(0, 0, 0, 1)
	toolbar.title:SetShadowOffset(1, -1)
	toolbar.title:SetText("Design mode")
	toolbar.hint = UI().create_text(toolbar, T.FONT.regular, 11, C.text_soft)
	toolbar.hint:SetPoint("TOPLEFT", 18, -34)
	toolbar.hint:SetShadowColor(0, 0, 0, 1)
	toolbar.hint:SetShadowOffset(1, -1)
	toolbar.hint:SetWordWrap(false)
	toolbar.hint:SetText("Drag to move  -  click for dials  -  Ctrl-click to mark, drag a marked one to move them all  -  Shift: no snap")

	-- row 2: one chip per element - its on/off switch and, on the name, its card
	toolbar.rowline = toolbar:CreateTexture(nil, "ARTWORK")
	toolbar.rowline:SetColorTexture(1, 1, 1, 0.07)
	toolbar.rowline:SetHeight(1)
	toolbar.rowline:SetPoint("TOPLEFT", 12, -(TOOLBAR_H - CHIP_H - 24))
	toolbar.rowline:SetPoint("TOPRIGHT", -12, -(TOOLBAR_H - CHIP_H - 24))
	toolbar.chips = {}

	toolbar.done = accent_button(toolbar, "Done", function() EM.lock() end)
	toolbar.done:SetPoint("TOPRIGHT", -14, -13)

	toolbar.grid = UI().create_button(toolbar, grid_label(), function(btn)
		-- cycle through the grid steps
		local cur = EM.grid_step()
		local next_step = GRID_STEPS[1]
		for i, g in ipairs(GRID_STEPS) do
			if g == cur then next_step = GRID_STEPS[i + 1] or GRID_STEPS[1]; break end
		end
		UI().option_set("design.design_grid", next_step)
		EM.refresh_grid()
	end)
	toolbar.grid:SetPoint("RIGHT", toolbar.done, "LEFT", -10, 0)
	toolbar.grid:SetHeight(28)
	toolbar.done:SetHeight(28)

	-- mark every movable element (or clear the marks) for a group move
	toolbar.select = UI().create_button(toolbar, "Select all", function()
		if EM.selection_count() > 0 then
			EM.clear_selection()
		else
			EM.select_all()
		end
		EM.refresh()
	end)
	toolbar.select:SetPoint("RIGHT", toolbar.grid, "LEFT", -10, 0)
	toolbar.select:SetHeight(28)

	toolbar:Hide()
end

--=========================================================================================
-- Element overlays: one labelled, draggable, clickable veil per element frame.
--=========================================================================================
local open_panel   -- forward declaration

local function overlay_paint(o, hot, centred)
	local C = theme().C
	local on = o.enabled ~= false
	local marked = EM.is_selected(o.desc)
	local a_fill = hot and 0.12 or (on and 0.05 or 0.03)
	if marked then a_fill = a_fill + 0.06 end
	if o.dragging then a_fill = 0 end   -- see the element itself while placing it
	local a_line = (hot or marked) and 1 or (on and 0.6 or 0.35)
	local line = (centred or marked) and C.warm_light or C.accent
	o.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], a_fill)
	for _, t in pairs(o.border) do
		t:SetColorTexture(line[1], line[2], line[3], a_line)
	end
end

local function overlay_tooltip(o)
	local d = o.desc
	if not d then return end
	GameTooltip:SetOwner(o, "ANCHOR_TOP")
	GameTooltip:SetText(d.title .. (o.enabled == false and "  (off)" or ""), 1, 1, 1)
	if d.fixed and d.fixed() then
		GameTooltip:AddLine(d.fixed_hint or "Can't be moved", 1, 0.82, 0.48, true)
	else
		GameTooltip:AddLine("Drag to move (Shift: no snap)", 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine("Click for its dials", 0.8, 0.8, 0.8)
	if EM.is_selected(d) then
		GameTooltip:AddLine("Marked - drag to move the whole selection (Ctrl-click to unmark)", 1, 0.82, 0.48, true)
	else
		GameTooltip:AddLine("Ctrl-click to mark it for a group move", 0.8, 0.8, 0.8)
	end
	if d.enable_path then
		GameTooltip:AddLine("On/off: the switch on the toolbar", 0.8, 0.8, 0.8)
	end
	GameTooltip:Show()
end

local function make_overlay(i)
	local T = theme()
	local C = T.C
	local o = CreateFrame("Button", nil, UIParent)
	o:EnableMouse(true)
	o.fill = o:CreateTexture(nil, "BACKGROUND")
	o.fill:SetAllPoints()
	o.border = {}
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do
		local t = o:CreateTexture(nil, "BORDER")
		o.border[side] = t
	end
	-- 1px lines INSIDE the box, so the outline sits exactly on the element's edge
	o.border.top:SetPoint("TOPLEFT", 0, 0);       o.border.top:SetPoint("TOPRIGHT", 0, 0);       o.border.top:SetHeight(1)
	o.border.bottom:SetPoint("BOTTOMLEFT", 0, 0); o.border.bottom:SetPoint("BOTTOMRIGHT", 0, 0); o.border.bottom:SetHeight(1)
	o.border.left:SetPoint("TOPLEFT", 0, 0);      o.border.left:SetPoint("BOTTOMLEFT", 0, 0);    o.border.left:SetWidth(1)
	o.border.right:SetPoint("TOPRIGHT", 0, 0);    o.border.right:SetPoint("BOTTOMRIGHT", 0, 0);  o.border.right:SetWidth(1)

	o.is_overlay = true

	o:RegisterForDrag("LeftButton")
	o:RegisterForClicks("LeftButtonUp")
	o:SetScript("OnEnter", function(self)
		overlay_paint(self, true)
		overlay_tooltip(self)
	end)
	o:SetScript("OnLeave", function(self)
		if panel_overlay ~= self then overlay_paint(self, false) end
		GameTooltip:Hide()
	end)
	-- The other marked elements ride along with the dragged one: each is re-saved
	-- at its start position plus the leader's travel (live, then once more snapped)
	local function move_followers(self, dx, dy)
		for _, m in ipairs(self.group or {}) do
			if m ~= self and m.desc and m.desc.save then
				m.desc.save(m.group_start[1] + dx, m.group_start[2] + dy)
			end
		end
	end
	-- while dragging: light a guide line (and the border) whenever an edge or the
	-- centre lines up with another element or the screen centre
	local function drag_tick(self)
		local f = self.target
		if not (self.dragging and f) then return end
		if self.group then
			local cx, cy = center_offsets(f)
			move_followers(self, cx - self.group_start[1], cy - self.group_start[2])
		end
		local l, r, t, b = box_rect(self)
		if not l then return end
		local dx, dy, gx, gy = EM.align(l, r, t, b, self.group_set or self, self.edge_border)
		show_guides(dx and gx or nil, dy and gy or nil)
		overlay_paint(self, true, (dx or dy) and true or false)
	end
	o:SetScript("OnDragStart", function(self)
		local d, f = self.desc, self.target
		if not (d and f) then return end
		if d.fixed and d.fixed() then return end
		self.dragging = true
		GameTooltip:Hide()
		-- a marked element drags the whole selection: remember where everyone starts
		self.group, self.group_set = nil, nil
		if EM.is_selected(d) then
			self.group, self.group_set = {}, {}
			for _, m in ipairs(overlays) do
				if m:IsShown() and m.desc and m.target and EM.is_selected(m.desc)
					and not (m.desc.fixed and m.desc.fixed()) then
					m.group_start = { center_offsets(m.target) }
					self.group[#self.group + 1] = m
					self.group_set[m] = true
				end
			end
		end
		self.group_start = { center_offsets(f) }
		-- clear the view: no fill, just the outline on the edge
		f:SetMovable(true)
		f:StartMoving()
		self:SetScript("OnUpdate", drag_tick)
		drag_tick(self)
	end)
	o:SetScript("OnDragStop", function(self)
		if not self.dragging then return end
		self.dragging = nil
		self:SetScript("OnUpdate", nil)
		show_guides(nil, nil)
		local d, f = self.desc, self.target
		if not (d and f) then return end
		f:StopMovingOrSizing()
		local x, y = center_offsets(f)
		local l, r, t, b = box_rect(self)
		if not l then
			local w, h = screen_size(f)
			l, r, t, b = x - w / 2, x + w / 2, y + h / 2, y - h / 2
		end
		x, y = EM.snap(x, y, l, r, t, b, self.group_set or self, self.edge_border)
		if d.save then d.save(x, y) end
		if self.group then
			move_followers(self, x - self.group_start[1], y - self.group_start[2])
			self.group, self.group_set = nil, nil
		end
		EM.refresh()
		-- the element landed somewhere new: bring its open card along
		if panel_overlay == self then EM.position_panel(self) end
	end)
	o:SetScript("OnClick", function(self)
		if IsControlKeyDown and IsControlKeyDown() then
			EM.set_selected(self.desc, not EM.is_selected(self.desc))
			overlay_paint(self, true)
			return
		end
		open_panel(self)
	end)
	overlays[i] = o
	return o
end

-- Match the element frames to the overlay pool; called on unlock, from the ticker and
-- after every dial change (elements appear, resize, attach/detach while unlocked).
function EM.refresh()
	if not active then return end
	local n = 0
	for _, desc in ipairs(registry) do
		local ok, f = pcall(desc.frame)
		if not ok then f = nil end
		local avail = true
		if desc.available then
			local ok2, a = pcall(desc.available)
			avail = ok2 and a and true or false
		end
		if f and avail and f:IsShown() then
			n = n + 1
			local o = overlays[n] or make_overlay(n)
			if not o.dragging then
				o.desc, o.target = desc, f
				o.enabled = element_enabled(desc)
				o:SetParent(f)
				o:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
				local box
				if desc.box then
					local okb, bf = pcall(desc.box)
					if okb then box = bf end
				end
				o.box = box   -- nil = the target frame itself
				local hug = box or f
				local pad = desc.pad
				if type(pad) == "function" then
					local okp, pv = pcall(pad)
					pad = okp and pv or nil
				end
				pad = pad or {}
				o.pad = pad
				-- the element's drawn border on its box edge (for stacking abutting borders)
				local bd = desc.border
				if type(bd) == "function" then
					local okb2, bv = pcall(bd)
					bd = okb2 and bv or 0
				end
				o.edge_border = tonumber(bd) or 0
				o:ClearAllPoints()
				o:SetPoint("TOPLEFT", hug, "TOPLEFT", -(pad.l or 0), (pad.t or 0))
				o:SetPoint("BOTTOMRIGHT", hug, "BOTTOMRIGHT", (pad.r or 0), -(pad.b or 0))
				if panel_overlay ~= o then overlay_paint(o, false) end
				o:Show()
			end
		end
	end
	for i = n + 1, #overlays do
		overlays[i]:Hide()
		overlays[i].desc, overlays[i].target, overlays[i].box = nil, nil, nil
	end
	alignment_overlays = overlays
	-- the pool reshuffles when elements appear/vanish: a card left open for a
	-- reassigned overlay would show the wrong element's dials
	if panel_overlay and panel and panel:IsShown() and panel_overlay.desc ~= panel.desc then
		EM.close_panel()
	end
	EM.refresh_chips()
	EM.update_sim_button()
end

--=========================================================================================
-- Toolbar chips: one per element on screen, with its on/off switch; the name opens
-- the element's card. Pooled and re-laid out on every refresh.
--=========================================================================================
local function overlay_for(desc)
	for _, o in ipairs(overlays) do
		if o.desc == desc and o:IsShown() then return o end
	end
end

local function make_chip(i)
	local T = theme()
	local C = T.C
	local chip = UI().create_panel(toolbar, { radius = CHIP_H / 2, fill = T.hex("1d1e23", 0.7), border = T.hex("ffffff", 0.1) }, "Button")
	chip:SetHeight(CHIP_H)
	chip.toggle = UI().create_toggle(30, 16)
	chip.toggle:SetParent(chip)
	chip.toggle:SetPoint("LEFT", chip, "LEFT", 5, 0)
	chip.toggle:SetFrameLevel(chip:GetFrameLevel() + 2)
	chip.toggle.on_click = function(self)
		local desc = chip.desc
		if not (desc and desc.enable_path) then return end
		local on = not self.on
		self:SetOn(on, true)
		UI().option_set(desc.enable_path, on)
		local o = overlay_for(desc)
		if o then o.enabled = on; overlay_paint(o, panel_overlay == o) end
	end
	chip.label = UI().create_text(chip, T.FONT.medium, 12, C.text)
	chip.label:SetPoint("LEFT", chip.toggle, "RIGHT", 7, 0)
	chip.label:SetJustifyV("MIDDLE")
	chip:SetScript("OnEnter", function(self)
		self.skin:SetBorder(unpack(C.input_border_hover))
		local o = overlay_for(self.desc)
		if o then overlay_paint(o, true) end
	end)
	chip:SetScript("OnLeave", function(self)
		self.skin:SetBorder(1, 1, 1, 0.1)
		local o = overlay_for(self.desc)
		if o and panel_overlay ~= o then overlay_paint(o, false) end
	end)
	chip:SetScript("OnClick", function(self)
		local d = self.desc
		if not d then return end
		if d.virtual then
			open_panel(nil, d)
		else
			local o = overlay_for(d)
			if o then open_panel(o) end
		end
	end)
	toolbar.chips[i] = chip
	return chip
end

function EM.refresh_chips()
	if not (active and toolbar) then return end
	local n = 0
	local x = 18
	for _, desc in ipairs(registry) do
		local avail = true
		if desc.available then
			local ok, a = pcall(desc.available)
			avail = ok and a and true or false
		end
		if avail and (desc.virtual or overlay_for(desc)) then
			n = n + 1
			local chip = toolbar.chips[n] or make_chip(n)
			chip.desc = desc
			chip.label:SetText(desc.title)
			if desc.enable_path then
				chip.toggle:Show()
				chip.toggle:SetOn(element_enabled(desc), false)
				chip.label:ClearAllPoints()
				chip.label:SetPoint("LEFT", chip.toggle, "RIGHT", 7, 0)
			else
				chip.toggle:Hide()
				chip.label:ClearAllPoints()
				chip.label:SetPoint("LEFT", chip, "LEFT", 10, 0)
			end
			local w = (desc.enable_path and (5 + 30 + 7) or 10) + (chip.label:GetStringWidth() or 40) + 12
			chip:SetWidth(w)
			chip:ClearAllPoints()
			chip:SetPoint("BOTTOMLEFT", toolbar, "BOTTOMLEFT", x, 12)
			chip:Show()
			x = x + w + 8
		end
	end
	for i = n + 1, #toolbar.chips do
		toolbar.chips[i]:Hide()
		toolbar.chips[i].desc = nil
	end
	-- wide enough for the chips row AND the title row (hint text + the two buttons)
	local row1 = 18 + (toolbar.hint:GetStringWidth() or 0) + 24
		+ (toolbar.select:GetWidth() or 0) + 10
		+ (toolbar.grid:GetWidth() or 0) + 10 + (toolbar.done:GetWidth() or 0) + 14
	toolbar:SetWidth(max(TOOLBAR_MIN_W, x - 8 + 18, row1))
	EM.layout_toolbar_art()
end

-- Mark every movable element on screen (attached icons follow the bar anyway)
function EM.select_all()
	for _, o in ipairs(overlays) do
		if o:IsShown() and o.desc and o.target and not (o.desc.fixed and o.desc.fixed()) then
			selected[o.desc.key] = true
		end
	end
	if refresh_toolbar_selection then refresh_toolbar_selection() end
end

refresh_toolbar_selection = function()
	if not (toolbar and toolbar.select) then return end
	local C = theme().C
	local n = EM.selection_count()
	toolbar.select:SetText(n > 0 and ("Clear selection (" .. n .. ")") or "Select all")
	if n > 0 then
		toolbar.select.skin:SetBorder(unpack(C.accent))
		UI().set_color(toolbar.select.label, C.warm_light)
	else
		toolbar.select.skin:SetBorder(1, 1, 1, 0.12)
		UI().set_color(toolbar.select.label, C.text)
	end
	for _, o in ipairs(overlays) do
		if o:IsShown() and o.desc and panel_overlay ~= o and not o.dragging then overlay_paint(o, false) end
	end
end

-- Size the key art to the toolbar: as wide as fits right of the title block, cropped
-- from the right of the art band at its native aspect so nothing is squashed.
function EM.layout_toolbar_art()
	if not (toolbar and toolbar.art_found) then return end
	-- starts right of the title block (hint text + a margin), never over it
	local title_block = 18 + (toolbar.hint:GetStringWidth() or 380) + 70
	local w = min(ART_MAX_W, (toolbar:GetWidth() or TOOLBAR_MIN_W) - title_block)
	if w < 120 then toolbar.art:Hide(); return end
	toolbar.art:Show()
	toolbar.art:SetWidth(w)
	local band_px = (ART_V1 - ART_V0) * 512          -- art pixels in the band
	local scale = (TOOLBAR_H - 2) / band_px          -- drawn px per art px
	local u_span = min(1, w / (1024 * scale))
	toolbar.art:SetTexCoord(1 - u_span, 1, ART_V0, ART_V1)
	if toolbar.lfade then toolbar.lfade:SetWidth(max(120, w * 0.55)) end
end

--=========================================================================================
-- Cards. Two of them share one look and one row engine:
--   panel          the element card: the clicked element's dials, pinned beside it
--   effects_panel  the "Effects & sounds" window: free-floating (drag its title bar,
--                  position remembered), opens on the left when design mode starts,
--                  carries the twist simulation button above its dials
-- Both scale with design_card_scale; the grip on either drags that value.
--=========================================================================================
local function card_drag_stop(card)
	card:StopMovingOrSizing()
	local x, y = center_offsets(card)
	local p = db()
	p.design_effects_x, p.design_effects_y = floor(x + 0.5), floor(y + 0.5)
end

local function make_card(kind)
	local T = theme()
	local C = T.C
	local card = UI().create_panel(UIParent, { radius = T.RADIUS, fill = T.hex("0c0c0f", 0.96), border = C.win_border })
	card.kind = kind
	card:SetSize(PANEL_W, 120)
	card:SetFrameStrata("FULLSCREEN_DIALOG")
	card:SetClampedToScreen(true)
	card:EnableMouse(true)
	card.topline = card:CreateTexture(nil, "ARTWORK")
	card.topline:SetColorTexture(1, 0.82, 0.48, 0.18)
	card.topline:SetHeight(1)
	card.topline:SetPoint("TOPLEFT", T.RADIUS, -1)
	card.topline:SetPoint("TOPRIGHT", -T.RADIUS, -1)
	card.mark = card:CreateTexture(nil, "ARTWORK")
	card.mark:SetTexture(T.TEX.round)
	card.mark:SetTexCoord(0.3, 0.7, 0.3, 0.7)
	card.mark:SetSize(3, 14)
	card.mark:SetPoint("TOPLEFT", PANEL_PAD, -13)
	card.mark:SetVertexColor(unpack(C.accent))
	card.title = UI().create_text(card, T.FONT.bold, T.FS.section, C.white)
	card.title:SetPoint("LEFT", card.mark, "RIGHT", 9, 0)
	card.title:SetJustifyV("MIDDLE")
	card.line = card:CreateTexture(nil, "ARTWORK")
	card.line:SetColorTexture(1, 1, 1, 0.1)
	card.line:SetHeight(1)
	card.line:SetPoint("TOPLEFT", 1, -PANEL_TITLE_H)
	card.line:SetPoint("TOPRIGHT", -1, -PANEL_TITLE_H)

	card.close = CreateFrame("Button", nil, card)
	card.close:SetSize(22, 22)
	card.close:SetPoint("TOPRIGHT", -9, -9)
	card.close.icon = card.close:CreateTexture(nil, "ARTWORK")
	card.close.icon:SetTexture(T.TEX.close)
	card.close.icon:SetSize(11, 11)
	card.close.icon:SetPoint("CENTER")
	card.close.icon:SetVertexColor(unpack(C.muted))
	card.close:SetScript("OnEnter", function(s) s.icon:SetVertexColor(1, 1, 1) end)
	card.close:SetScript("OnLeave", function(s) s.icon:SetVertexColor(unpack(C.muted)) end)
	card.close:SetScript("OnClick", function()
		if kind == "effects" then EM.close_effects() else EM.close_panel() end
	end)

	card.content = CreateFrame("Frame", nil, card)
	card.content:SetPoint("TOPLEFT", 1, -(PANEL_TITLE_H + 1))
	card.content:SetWidth(PANEL_W - 2)

	if kind == "element" then
		card.reset = UI().create_button(card, "Reset position", function()
			local d = card.desc
			if d and d.reset then d.reset(); EM.refresh() end
		end)
	end
	card.all = UI().create_button(card, "All settings", function()
		local d = card.desc
		if kind == "effects" then EM.close_effects() else EM.close_panel() end
		if d and d.settings and UI().open then
			UI().open()
			UI().show_page(d.settings.page, d.settings.tab)
		end
	end)

	if kind == "effects" then
		-- free-floating: the title bar drags it, the spot is remembered
		card:SetMovable(true)
		card.drag = CreateFrame("Frame", nil, card)
		card.drag:SetPoint("TOPLEFT", 0, 0)
		card.drag:SetPoint("TOPRIGHT", -34, 0)
		card.drag:SetHeight(PANEL_TITLE_H)
		card.drag:EnableMouse(true)
		card.drag:RegisterForDrag("LeftButton")
		card.drag:SetScript("OnDragStart", function() card:StartMoving() end)
		card.drag:SetScript("OnDragStop", function() card_drag_stop(card) end)
		-- the twist simulation lives here, above the dials
		card.sim = UI().create_button(card, "Simulate 1/2 twists", function() EM.set_simulating(not simulating) end)
		card.sim:SetHeight(30)
		card.simhint = UI().create_text(card, T.FONT.regular, 11, C.muted)
		card.simhint:SetWordWrap(true)
		card.simhint:SetText("Runs a Command swing that twists to Blood, then a Blood swing, on repeat. "
			.. "Every twist fires the sounds, glow and text below for real.")
	end

	-- resize grip: drags design_card_scale (every card); double-click resets
	local g = CreateFrame("Button", nil, card)
	g:SetSize(18, 18)
	g:SetPoint("BOTTOMRIGHT", -3, 3)
	g:SetFrameLevel((card:GetFrameLevel() or 1) + 5)
	g.dots = {}
	for _, d in ipairs({ { 3, 3 }, { 8, 3 }, { 13, 3 }, { 3, 8 }, { 8, 8 }, { 3, 13 } }) do
		local t = g:CreateTexture(nil, "OVERLAY")
		t:SetTexture(T.TEX.circle)
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
		GameTooltip:AddLine("Resizes the design mode cards. Double-click to reset.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	g:SetScript("OnLeave", function() if not g.resizing then tint(C.muted, 0.9) end; GameTooltip:Hide() end)
	g:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		local s, ue = card:GetScale(), UIParent:GetEffectiveScale()
		-- pin the top-left corner where it is, so the card grows right / down
		local left, top = card:GetLeft() * s, card:GetTop() * s
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / s, top / s)
		local cx, cy = GetCursorPosition()
		cx, cy = cx / ue, cy / ue
		g.left, g.top = left, top
		g.grab_dx, g.grab_dy = card:GetRight() * s - cx, cy - card:GetBottom() * s
		g.resizing = true
		tint(C.accent, 1)
		g:SetScript("OnUpdate", function()
			local ue2 = UIParent:GetEffectiveScale()
			local x, y = GetCursorPosition()
			x, y = x / ue2 + g.grab_dx, y / ue2 - g.grab_dy
			local wanted = max((x - g.left) / PANEL_W, (g.top - y) / (card:GetHeight() or 1))
			wanted = max(SCALE_MIN, min(SCALE_MAX, wanted))
			card:SetScale(wanted)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.left / wanted, g.top / wanted)
		end)
	end)
	local function stop()
		if not g.resizing then return end
		g.resizing = false
		g:SetScript("OnUpdate", nil)
		tint(g:IsMouseOver() and C.white or C.muted, g:IsMouseOver() and 1 or 0.9)
		db().design_card_scale = card:GetScale()
		if kind == "effects" then card_drag_stop(card) end   -- the corner moved its centre
		EM.apply_scale()
		if UI().request_refresh then UI().request_refresh() end
	end
	g.stop = stop
	g:SetScript("OnMouseUp", stop)
	g:SetScript("OnHide", stop)
	g:SetScript("OnDoubleClick", function()
		db().design_card_scale = ST.defaults.profile.design_card_scale or 0.7
		EM.apply_scale()
		if UI().request_refresh then UI().request_refresh() end
	end)
	card.grip = g

	card.host = UI().new_host(function() card.dirty = true end)
	card:SetScript("OnUpdate", function()
		if card.dirty and not UI().refresh_suppressed() then
			card.dirty = false
			EM.rebuild_card(card)
		end
	end)
	card:SetScript("OnHide", function()
		if card.host then UI().release_host(card.host) end
	end)
	card:Hide()
	return card
end

local function ensure_panel()
	if panel then return end
	panel = make_card("element")
end

local function ensure_effects()
	if effects_panel then return end
	effects_panel = make_card("effects")
	for _, desc in ipairs(registry) do
		if desc.virtual then effects_panel.desc = desc; break end
	end
	effects_panel.title:SetText(effects_panel.desc and effects_panel.desc.title or "Effects & sounds")
end

function EM.update_sim_button()
	if not (effects_panel and effects_panel.sim) then return end
	local C = theme().C
	effects_panel.sim:SetText(simulating and "Stop simulating" or "Simulate 1/2 twists")
	if simulating then
		effects_panel.sim.skin:SetFill(unpack(C.accent))
		effects_panel.sim.skin:SetBorder(0, 0, 0, 0)
		UI().set_color(effects_panel.sim.label, C.accent_text)
	else
		effects_panel.sim.skin:SetFill(unpack(C.button_bg))
		effects_panel.sim.skin:SetBorder(unpack(C.button_border))
		UI().set_color(effects_panel.sim.label, C.text)
	end
end

function EM.set_simulating(on)
	simulating = on and true or false
	EM.update_sim_button()
	if st.bar and st.bar.set_success_text_position then st.bar.set_success_text_position() end
end

function EM.close_panel()
	if panel then panel:Hide() end
	if panel_overlay then overlay_paint(panel_overlay, false) end
	panel_overlay = nil
	if panel then panel.desc = nil end
end

-- Pin the element card to the SCREEN beside the element on whichever side has the
-- room - never to the overlay itself: a size dial resizes the element live and a card
-- anchored to it would slide out from under the cursor.
function EM.position_panel(o)
	if not (panel and panel:IsShown()) then return end
	panel:ClearAllPoints()
	local s = panel:GetScale() or 1
	local es = o and (o:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	local left, right, top = o and o:GetLeft(), o and o:GetRight(), o and o:GetTop()
	if not (left and right and top) then
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		return
	end
	local w = UIParent:GetWidth() or 1024
	if (left + right) / 2 * es > w / 2 then
		panel:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", (left * es - 14) / s, (top * es + 6) / s)
	else
		panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (right * es + 14) / s, (top * es + 6) / s)
	end
end

-- The effects window: its remembered spot, or the left edge of the screen.
function EM.position_effects()
	if not effects_panel then return end
	local s = effects_panel:GetScale() or 1
	local p = db()
	effects_panel:ClearAllPoints()
	if p.design_effects_x and p.design_effects_y then
		effects_panel:SetPoint("CENTER", UIParent, "CENTER", p.design_effects_x / s, p.design_effects_y / s)
	else
		effects_panel:SetPoint("LEFT", UIParent, "LEFT", 24 / s, 0)
	end
end

-- (Re)renders a card's rows from its element's option paths.
function EM.rebuild_card(card)
	if not (card and card:IsShown() and card.desc) then return end
	local d = card.desc
	local top = PANEL_TITLE_H + 1
	if card.sim then
		-- simulation button + its hint above the dials
		card.sim:ClearAllPoints()
		card.sim:SetPoint("TOPLEFT", card, "TOPLEFT", PANEL_PAD, -(top + 10))
		card.sim:SetWidth(PANEL_W - 2 * PANEL_PAD)
		card.simhint:ClearAllPoints()
		card.simhint:SetPoint("TOPLEFT", card, "TOPLEFT", PANEL_PAD, -(top + 10 + 30 + 6))
		card.simhint:SetWidth(PANEL_W - 2 * PANEL_PAD)
		top = top + 10 + 30 + 6 + (card.simhint:GetStringHeight() or 24) + 10
		card.content:ClearAllPoints()
		card.content:SetPoint("TOPLEFT", 1, -top)
		EM.update_sim_button()
	end
	local h = UI().build_rows(card.host, card.content, d.card or {}, PANEL_W - 2)
	card.content:SetHeight(max(h, 1))
	local y = top + h + 10
	card.all:ClearAllPoints()
	if card.reset then
		card.reset:ClearAllPoints()
		if d.reset then
			card.reset:Show()
			card.reset:SetPoint("TOPLEFT", card, "TOPLEFT", PANEL_PAD, -y)
			card.all:SetPoint("LEFT", card.reset, "RIGHT", 8, 0)
		else
			card.reset:Hide()
			card.all:SetPoint("TOPLEFT", card, "TOPLEFT", PANEL_PAD, -y)
		end
	else
		card.all:SetPoint("TOPLEFT", card, "TOPLEFT", PANEL_PAD, -y)
	end
	if d.settings then card.all:Show() else card.all:Hide() end
	card:SetHeight(y + 32 + PANEL_PAD)
	if card == panel then EM.refresh() end
end

function EM.rebuild_panel() EM.rebuild_card(panel) end

function EM.open_effects()
	ensure_effects()
	if not effects_panel.desc then return end
	effects_panel:SetScale(EM.card_scale())
	effects_panel:Show()
	EM.rebuild_card(effects_panel)
	EM.position_effects()
end

function EM.close_effects()
	if effects_panel then effects_panel:Hide() end
end

function EM.toggle_effects()
	if effects_panel and effects_panel:IsShown() then EM.close_effects() else EM.open_effects() end
end

function EM.effects_shown()
	return effects_panel ~= nil and effects_panel:IsShown()
end

-- o = the element's overlay, or nil with `desc` for a virtual element
open_panel = function(o, desc)
	desc = desc or (o and o.desc)
	if not desc then return end
	if desc.virtual then
		EM.toggle_effects()
		return
	end
	-- clicking the element (or its chip) again puts its card away
	if panel and panel:IsShown() and panel.desc == desc then
		EM.close_panel()
		return
	end
	ensure_panel()
	EM.close_panel()
	panel_overlay = o
	if o then overlay_paint(o, true) end
	panel.desc = desc
	panel.title:SetText(desc.title)
	panel:SetScale(EM.card_scale())
	panel:Show()
	EM.rebuild_card(panel)
	EM.position_panel(o)
end

--=========================================================================================
-- Unlock / lock
--=========================================================================================
local function apply_module_locks()
	local p = db()
	if st.bar and st.bar.frame then
		st.bar.frame:SetMovable(not p.bar_locked)
		st.bar.frame:EnableMouse(not p.bar_locked)
	end
	if st.bar and st.bar.set_icon_position then st.bar.set_icon_position() end
	if st.nextaction and st.nextaction.apply_settings then st.nextaction.apply_settings() end
	if st.hud and st.hud.apply_settings then st.hud.apply_settings() end
	if st.rotation_text and st.rotation_text.apply_settings then st.rotation_text.apply_settings() end
end

function EM.unlock()
	if active then return end
	if InCombatLockdown and InCombatLockdown() then
		print("Design mode can't start in combat - try again after the fight.")
		return
	end
	if not (st.bar and st.bar.frame and st.settings_ui and st.settings_ui.build_rows) then
		print("SwedgeTimer is still loading - try again in a moment.")
		return
	end
	-- build the chrome BEFORE flipping active: a fresh layer starts hidden, and its
	-- OnHide would otherwise lock the mode it is about to open
	ensure_layer()
	ensure_toolbar()
	active = true
	if st.bar.begin_preview then st.bar.begin_preview() end
	if st.nextaction and st.nextaction.apply_settings then st.nextaction.apply_settings() end
	if st.hud and st.hud.apply_settings then st.hud.apply_settings() end
	if st.rotation_text and st.rotation_text.apply_settings then st.rotation_text.apply_settings() end
	draw_grid()
	if toolbar.grid then toolbar.grid:SetText(grid_label()) end
	EM.apply_scale()
	-- the settings window would sit over the elements: close it, the cards take over
	if st.settings_ui.close then st.settings_ui.close() end
	layer:Show()
	toolbar:Show()
	EM.open_effects()
	EM.refresh()
	if st.settings_ui.request_refresh then st.settings_ui.request_refresh() end
	print("Design mode: drag any element into place, click one for its dials, and use the switches on "
		.. "the toolbar to turn elements on or off. Esc, Done or |cFF00FF00/st lock|r when you're happy.")
end

function EM.lock(quiet)
	if not active then
		if not quiet then print("Nothing is unlocked. |cFF00FF00/st design|r opens design mode.") end
		return
	end
	active = false
	simulating = false
	EM.clear_selection()
	EM.close_panel()
	EM.close_effects()
	for i = 1, #overlays do
		local o = overlays[i]
		o:Hide()
		o:SetScript("OnUpdate", nil)
		o.desc, o.target, o.dragging, o.group, o.group_set = nil, nil, nil, nil, nil
		-- back to a neutral parent: a target frame may get hidden/rebuilt while locked
		o:SetParent(UIParent)
		o:ClearAllPoints()
	end
	if toolbar then
		toolbar:Hide()
		for _, chip in ipairs(toolbar.chips) do chip.desc = nil end
	end
	if layer then layer:Hide() end
	if guides then guides:Hide() end
	if st.bar and st.bar.end_preview then st.bar.end_preview() end
	apply_module_locks()
	if st.settings_ui and st.settings_ui.request_refresh then st.settings_ui.request_refresh() end
	if not quiet then print("Design mode off - everything locked in place.") end
end

function EM.toggle()
	if active then EM.lock() else EM.unlock() end
end

--=========================================================================================
function EM.init()
	if combat_frame then return end
	combat_frame = CreateFrame("Frame")
	combat_frame:SetScript("OnEvent", function()
		if active then
			EM.lock(true)
			print("Design mode closed - combat started.")
		end
	end)
	combat_frame:RegisterEvent("PLAYER_REGEN_DISABLED")
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed editmode.lua module correctly') end
