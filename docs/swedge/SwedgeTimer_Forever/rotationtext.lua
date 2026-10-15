-- rotationtext.lua =====================================================================
-- Rotation text: a free-standing label with the twist rotation SwedgeTimer currently
-- recommends ("2/3", "2/2/5", ...), the same rotation the Next Action Guide and
-- Practice Mode work from. Off by default; switch it on in design mode or the settings
-- and drop it anywhere. Formats: the key alone, "Rotation: 2/3", the step list
-- ("CS, Twist, Twist"), or both.
--=======================================================================================
local addon_name, st = ...
local print = st.utils.print_msg
local ST = LibStub("AceAddon-3.0"):GetAddon("SwedgeTimer")
local SML = LibStub("LibSharedMedia-3.0")

st.rotation_text = {}
local RT = st.rotation_text

local TICK = 0.1
local outline_map = { _none = "", outline = "OUTLINE", thick_outline = "THICKOUTLINE" }

RT.frame = nil
RT.update_counter = 0
RT.current_key = nil

local function db() return ST.db.profile end

local function previewing()
	return st.editmode ~= nil and st.editmode.active ~= nil and st.editmode.active()
end

--=========================================================================================
-- Rotation source (practice-aware) and formatting
--=========================================================================================
function RT.current_rotation()
	if st.practice and st.practice.active and st.practice.determine_rotation then
		return st.practice.determine_rotation()
	end
	if st.rotation and st.rotation.calculate_rotation then
		return st.rotation.calculate_rotation()
	end
	return nil
end

function RT.format(key)
	if not key then return "" end
	local p = db()
	local names = st.rotation and st.rotation.display_names or {}
	local descs = st.rotation and st.rotation.descriptions or {}
	local name = names[key] or key
	local desc = descs[key] or ""
	local fmt = p.rotation_label_format or "key"
	if fmt == "labelled" then
		return "Rotation: " .. name
	elseif fmt == "steps" then
		return desc ~= "" and desc or name
	elseif fmt == "both" then
		return desc ~= "" and (name .. "  -  " .. desc) or name
	end
	return name
end

--=========================================================================================
-- Frame
--=========================================================================================
local function apply_font(fs)
	local p = db()
	local path = SML:Fetch("font", p.rotation_label_font)
	local outline = outline_map[p.rotation_label_outline] or "OUTLINE"
	local ok = path and fs:SetFont(path, p.rotation_label_size or 16, outline)
	if ok == false or not fs:GetFont() then
		fs:SetFont(STANDARD_TEXT_FONT, p.rotation_label_size or 16, outline)
	end
	local c = p.rotation_label_color or { 1, 0.82, 0, 1 }
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

function RT.init()
	local p = db()
	local frame = CreateFrame("Frame", addon_name .. "RotationTextFrame", UIParent)
	RT.frame = frame
	frame:SetSize(80, 24)
	frame:SetPoint("CENTER", UIParent, "CENTER", p.rotation_label_x or 0, p.rotation_label_y or -150)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame.text = frame:CreateFontString(nil, "OVERLAY")
	frame.text:SetPoint("CENTER", 0, 0)
	frame.text:SetJustifyH("CENTER")
	frame.text:SetShadowColor(0, 0, 0, 1)
	frame.text:SetShadowOffset(1, -1)
	frame:Hide()
	RT.apply_settings()
end

function RT.should_show()
	local p = db()
	if previewing() then return true end
	if not p.bar_enabled then return false end   -- the addon's master switch
	if not p.rotation_label_enabled then return false end
	if st.practice and st.practice.active then return true end
	if p.ret_only and not st.utils.is_ret_spec then return false end
	if p.rotation_label_visibility_key == "in_combat" then
		return st.core.in_combat
	end
	return true
end

-- Alignment: the label's anchor point. rotation_label_x/y are the offsets of THAT
-- point from the screen centre, so a left-aligned label keeps its left edge where it
-- was when the text gets longer (and a right-aligned one its right edge).
function RT.anchor_point()
	local a = db().rotation_label_align
	if a == "left" then return "LEFT" elseif a == "right" then return "RIGHT" end
	return "CENTER"
end

-- Writes the text and fits the frame around it exactly (no side padding, so design
-- mode's box edge IS the text edge and left/right alignment sits flush against it)
function RT.set_text(text)
	local frame = RT.frame
	if not frame then return end
	frame.text:SetText(text or "")
	local w = frame.text:GetStringWidth() or 40
	local h = (frame.text:GetStringHeight() or 16) + 4
	frame:SetSize(math.max(w, 10), math.max(h, 12))
end

-- Change the alignment without the label jumping: the stored offset is moved from
-- the old anchor point to the new one.
function RT.set_align(align)
	local p = db()
	local frame = RT.frame
	local old_point = RT.anchor_point()
	p.rotation_label_align = align
	local new_point = RT.anchor_point()
	if frame and old_point ~= new_point then
		local w = frame:GetWidth() or 0
		local function edge_offset(point, x)   -- x = centre offset -> offset of the anchor edge
			if point == "LEFT" then return x - w / 2 elseif point == "RIGHT" then return x + w / 2 end
			return x
		end
		local function centre_from(point, x)   -- offset of the anchor edge -> centre offset
			if point == "LEFT" then return x + w / 2 elseif point == "RIGHT" then return x - w / 2 end
			return x
		end
		p.rotation_label_x = edge_offset(new_point, centre_from(old_point, p.rotation_label_x or 0))
	end
	RT.dirty = true
	RT.apply_settings()
end

function RT.apply_settings()
	local frame = RT.frame
	if not frame then return end
	local p = db()
	local point = RT.anchor_point()
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, "CENTER", p.rotation_label_x or 0, p.rotation_label_y or -150)
	frame.text:ClearAllPoints()
	frame.text:SetPoint(point, frame, point, 0, 0)
	frame.text:SetJustifyH(point)
	apply_font(frame.text)
	RT.set_text(RT.format(RT.current_key))
	if RT.should_show() then
		RT.update_display()
	else
		frame:Hide()
	end
end

function RT.update_display()
	local frame = RT.frame
	if not frame then return end
	if not frame:IsShown() then frame:Show() end
	local p = db()
	local key = RT.current_rotation()
	if previewing() then
		frame:SetAlpha(p.rotation_label_enabled and 1 or 0.35)
		-- the simulation runs the 1/2 rotation; otherwise the live one, or a sample
		if st.editmode.simulating and st.editmode.simulating() then
			key = "1/2"
		elseif not key then
			key = "2/3"
		end
	else
		frame:SetAlpha(1)
	end
	if key ~= RT.current_key or RT.dirty then
		RT.current_key = key
		RT.dirty = false
		RT.set_text(RT.format(key))
	end
end

function RT.on_update(elapsed)
	local frame = RT.frame
	if not frame then return end
	RT.update_counter = RT.update_counter + (elapsed or 0.016)
	if RT.update_counter < TICK then return end
	RT.update_counter = 0
	if not RT.should_show() then
		if frame:IsShown() then frame:Hide() end
		return
	end
	RT.update_display()
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed rotationtext.lua module correctly') end
