-- import_export.lua ===================================================================
-- Settings import / export for SwedgeTimer.
--
-- An export string is "SWT2:" followed by base64 of a Lua-table-literal-like text
-- ({format_version=2,settings={...}}). Both directions are self-contained: the writer
-- formats numbers locale-independently and escapes strings itself, and the reader is a
-- small hand-written parser (no loadstring), so a pasted string that picked up line
-- breaks or a client with an odd locale can't break it. Strings from 1.8.0 and older
-- ("SWT1:") use the same grammar and still import.
--
-- What travels: every key in SwedgeTimer.defaults.profile (so a new setting can never
-- be forgotten), minus a few that are per-machine (minimap button, window sizes, the
-- migration stamp) and three optional groups: positions, sounds and Practice Mode
-- keybinds. Import writes each known key after a type check (numbers given as strings
-- are converted, colours are clamped), then rebuilds every on-screen element.
--=======================================================================================
local addon_name, st = ...
local print = st.utils.print_msg
local ST = LibStub("AceAddon-3.0"):GetAddon("SwedgeTimer")

st.import_export = {}
local IE = st.import_export

-- State for the settings page
IE.export_string = ""
IE.import_string = ""
IE.include_positions = false
IE.include_sounds = false
IE.include_practice_keys = false
IE.status_message = ""

local FORMAT_VERSION = 2
local PREFIX = "SWT2:"
local LEGACY_PREFIX = "SWT1:"

--=========================================================================================
-- Which keys travel
--=========================================================================================
-- Never exported: per-machine / per-screen or bookkeeping
local excluded_settings = {
	minimap = true,               -- minimap button position
	schema_version = true,        -- migration stamp
	settings_scale = true,        -- settings window size
	design_scale = true,          -- design mode toolbar size
	design_card_scale = true,     -- design mode card size
	design_effects_x = true,      -- design mode window spot
	design_effects_y = true,
	practice_bar_mappings = true, -- which action bar slots the practice buttons took over
}

-- Optional: positions (the "Include positions" switch)
local position_settings = {
	bar_x_offset = true, bar_y_offset = true, bar_point = true, bar_rel_point = true,
	icon_x_offset = true, icon_y_offset = true, icon_point = true, icon_rel_point = true,
	rotation_offset_x = true, rotation_offset_y = true,
	nextaction_x = true, nextaction_y = true,
	successful_twist_text_x_offset = true, successful_twist_text_y_offset = true,
	successful_twist_text_point = true, successful_twist_text_rel_point = true,
	hud_x = true, hud_y = true,
	rotation_label_x = true, rotation_label_y = true,
	practice_rotation_display_x = true, practice_rotation_display_y = true,
	practice_timeline_x = true, practice_timeline_y = true,
}

-- Optional: sounds (the "Include sounds" switch)
local sound_settings = {
	sound_channel = true,
	twist_sound_enabled = true, twist_sound_choice = true,
	twist_success_sound_enabled = true, twist_success_sound_choice = true,
}

-- Optional: Practice Mode keybinds (the "Include Practice Mode keybinds" switch)
local function is_practice_key(key)
	return type(key) == "string" and key:sub(1, 13) == "practice_key_"
end

IE.excluded_settings = excluded_settings
IE.position_settings = position_settings
IE.sound_settings = sound_settings

--=========================================================================================
-- Base64
--=========================================================================================
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:sub(i, i)] = i - 1 end

local function base64_encode(data)
	local out = {}
	local n = #data
	for i = 1, n, 3 do
		local a, b, c = data:byte(i, i + 2)
		local v = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = math.floor(v / 262144) % 64
		local c2 = math.floor(v / 4096) % 64
		local c3 = math.floor(v / 64) % 64
		local c4 = v % 64
		out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
			.. (b and B64:sub(c3 + 1, c3 + 1) or "=")
			.. (c and B64:sub(c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end

-- Ignores anything that is not a base64 character (line breaks, spaces from a paste)
local function base64_decode(data)
	local clean = data:gsub("[^%w%+/]", "")
	local out = {}
	local bits, nbits = 0, 0
	for i = 1, #clean do
		bits = bits * 64 + B64_INDEX[clean:sub(i, i)]
		nbits = nbits + 6
		if nbits >= 8 then
			nbits = nbits - 8
			local byte = math.floor(bits / (2 ^ nbits)) % 256
			out[#out + 1] = string.char(byte)
			bits = bits % (2 ^ nbits)
		end
	end
	return table.concat(out)
end

IE.base64_encode = base64_encode
IE.base64_decode = base64_decode

--=========================================================================================
-- Serializer: a Lua-table-literal-like text, written by hand
--=========================================================================================
local function fmt_number(v)
	if v ~= v or v == math.huge or v == -math.huge then return "0" end
	local s
	if v == math.floor(v) and math.abs(v) < 1e15 then
		s = string.format("%d", v)
	else
		s = string.format("%.14g", v)
	end
	return (s:gsub(",", "."))   -- never a locale comma
end

local function fmt_string(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return string.format("\\%03d", c:byte())
	end) .. '"'
end

local function serialize(val, depth)
	depth = depth or 0
	local tp = type(val)
	if tp == "boolean" then return val and "true" or "false" end
	if tp == "number" then return fmt_number(val) end
	if tp == "string" then return fmt_string(val) end
	if tp == "table" then
		if depth > 8 then return "{}" end
		local keys = {}
		for k in pairs(val) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then return ta < tb end
			return a < b
		end)
		local parts = {}
		for _, k in ipairs(keys) do
			local v = val[k]
			local vt = type(v)
			if vt == "boolean" or vt == "number" or vt == "string" or vt == "table" then
				local ks
				if type(k) == "string" and k:match("^[%a_][%w_]*$") then
					ks = k
				elseif type(k) == "string" then
					ks = "[" .. fmt_string(k) .. "]"
				elseif type(k) == "number" then
					ks = "[" .. fmt_number(k) .. "]"
				end
				if ks then parts[#parts + 1] = ks .. "=" .. serialize(v, depth + 1) end
			end
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "nil"
end

--=========================================================================================
-- Parser: the same grammar (and the one 1.8.0's %q-based writer produced), no loadstring
--=========================================================================================
local Parser = {}
Parser.__index = Parser

local function new_parser(text)
	return setmetatable({ s = text, i = 1, n = #text }, Parser)
end

function Parser:skip()
	local s = self.s
	while self.i <= self.n do
		local c = s:sub(self.i, self.i)
		if c == " " or c == "\t" or c == "\n" or c == "\r" then
			self.i = self.i + 1
		else
			break
		end
	end
end

function Parser:peek()
	self:skip()
	return self.s:sub(self.i, self.i)
end

function Parser:expect(ch)
	if self:peek() ~= ch then
		error(("expected '%s' at %d"):format(ch, self.i), 0)
	end
	self.i = self.i + 1
end

function Parser:string()
	local s = self.s
	local quote = s:sub(self.i, self.i)
	self.i = self.i + 1
	local out = {}
	while self.i <= self.n do
		local c = s:sub(self.i, self.i)
		if c == quote then
			self.i = self.i + 1
			return table.concat(out)
		elseif c == "\\" then
			local nx = s:sub(self.i + 1, self.i + 1)
			if nx:match("%d") then
				local digits = s:match("^%d%d?%d?", self.i + 1)
				out[#out + 1] = string.char(tonumber(digits))
				self.i = self.i + 1 + #digits
			else
				local map = { n = "\n", t = "\t", r = "\r", a = "\a", b = "\b", f = "\f", v = "\v",
					["\\"] = "\\", ['"'] = '"', ["'"] = "'", ["\n"] = "\n" }
				out[#out + 1] = map[nx] or nx
				self.i = self.i + 2
			end
		else
			out[#out + 1] = c
			self.i = self.i + 1
		end
	end
	error("unterminated string", 0)
end

function Parser:number()
	local s = self.s
	local txt = s:match("^[%+%-]?%d*%.?%d*[eE]?[%+%-]?%d*", self.i)
	if not txt or txt == "" then error("bad number at " .. self.i, 0) end
	self.i = self.i + #txt
	local v = tonumber(txt)
	if not v then error("bad number '" .. txt .. "'", 0) end
	return v
end

function Parser:value()
	local c = self:peek()
	if c == "{" then return self:table() end
	if c == '"' or c == "'" then return self:string() end
	if c:match("[%d%-%+%.]") then return self:number() end
	local word = self.s:match("^[%a_][%w_]*", self.i)
	if word == "true" then self.i = self.i + 4; return true end
	if word == "false" then self.i = self.i + 5; return false end
	if word == "nil" then self.i = self.i + 3; return nil end
	error("unexpected '" .. tostring(c) .. "' at " .. self.i, 0)
end

function Parser:table()
	self:expect("{")
	local t = {}
	local nextindex = 1
	while true do
		local c = self:peek()
		if c == "}" then self.i = self.i + 1; return t end
		if c == "" then error("unterminated table", 0) end
		local key
		if c == "[" then
			self.i = self.i + 1
			key = self:value()
			self:expect("]")
			self:expect("=")
		else
			local word = self.s:match("^[%a_][%w_]*", self.i)
			local after = word and self.s:sub(self.i + #word, self.i + #word) or ""
			-- an identifier followed by "=" is a key; anything else is an array value
			if word and after == "=" and word ~= "true" and word ~= "false" and word ~= "nil" then
				key = word
				self.i = self.i + #word + 1
			end
		end
		local v = self:value()
		if key == nil then
			key = nextindex
			nextindex = nextindex + 1
		end
		t[key] = v
		local sep = self:peek()
		if sep == "," or sep == ";" then
			self.i = self.i + 1
		elseif sep ~= "}" then
			error("expected ',' or '}' at " .. self.i, 0)
		end
	end
end

local function deserialize(text)
	local p = new_parser(text)
	local ok, result = pcall(function()
		local v = p:value()
		p:skip()
		if p.i <= p.n then error("trailing text at " .. p.i, 0) end
		return v
	end)
	if not ok then return nil, result end
	return result
end

IE.serialize = serialize
IE.deserialize = deserialize

--=========================================================================================
-- Export
--=========================================================================================
local function deep_copy(orig)
	if type(orig) ~= "table" then return orig end
	local copy = {}
	for k, v in pairs(orig) do copy[deep_copy(k)] = deep_copy(v) end
	return copy
end
IE.deep_copy = deep_copy

-- Returns the export string and the number of settings in it (nil, err on failure).
function IE.export_settings(include_positions, include_sounds, include_practice_keys)
	if not (ST.db and ST.db.profile and ST.defaults and ST.defaults.profile) then
		return nil, "SwedgeTimer is still loading"
	end
	local db = ST.db.profile
	local defaults = ST.defaults.profile
	local version = ""
	local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	if getter then version = tostring(getter(addon_name, "Version") or ""):gsub('"', "") end

	local settings, count = {}, 0
	for key, default in pairs(defaults) do
		local skip = excluded_settings[key]
			or (position_settings[key] and not include_positions)
			or (sound_settings[key] and not include_sounds)
			or (is_practice_key(key) and not include_practice_keys)
		if not skip then
			local value = db[key]
			if value == nil then value = default end
			if type(value) == "table" then value = deep_copy(value) end
			settings[key] = value
			count = count + 1
		end
	end

	local payload = serialize({
		format_version = FORMAT_VERSION,
		addon_version = version,
		timestamp = time and time() or 0,
		settings = settings,
	})
	return PREFIX .. base64_encode(payload), count
end

--=========================================================================================
-- Import
--=========================================================================================

-- Coerces `value` to the type of `default`. Returns the usable value or nil.
local function coerce(value, default)
	local want, got = type(default), type(value)
	if want == got then
		if want == "table" then
			value = deep_copy(value)
			-- colours: arrays of 3-4 numbers, clamped to 0..1
			if #value >= 3 and #value <= 4 then
				local colour = true
				for i = 1, #value do if type(value[i]) ~= "number" then colour = false end end
				if colour then
					for i = 1, #value do value[i] = math.max(0, math.min(1, value[i])) end
				end
			end
		end
		return value
	end
	if want == "number" and got == "string" then
		return tonumber((value:gsub(",", ".")))
	elseif want == "string" and got == "number" then
		return tostring(value)
	elseif want == "boolean" and got == "number" then
		return value ~= 0
	end
	return nil
end
IE.coerce = coerce

-- Writes the known keys of `settings` into the profile. Returns counts.
function IE.apply_settings(settings)
	local db = ST.db.profile
	local defaults = ST.defaults.profile
	local applied, unknown, rejected = 0, 0, 0
	for key, value in pairs(settings) do
		if excluded_settings[key] then
			-- never imported
		elseif defaults[key] == nil then
			unknown = unknown + 1
		else
			local v = coerce(value, defaults[key])
			if v == nil then
				rejected = rejected + 1
			else
				db[key] = v
				applied = applied + 1
			end
		end
	end
	return applied, unknown, rejected
end

function IE.decode(import_string)
	if type(import_string) ~= "string" then return nil, "Import string is empty" end
	local s = import_string:gsub("%s+", "")
	if s == "" then return nil, "Import string is empty" end
	local body
	if s:sub(1, #PREFIX) == PREFIX then
		body = s:sub(#PREFIX + 1)
	elseif s:sub(1, #LEGACY_PREFIX) == LEGACY_PREFIX then
		body = s:sub(#LEGACY_PREFIX + 1)
	else
		return nil, "Not a SwedgeTimer export string (it should start with SWT2: or SWT1:)"
	end
	local ok, text = pcall(base64_decode, body)
	if not ok or not text or text == "" then return nil, "The string is damaged (could not decode it)" end
	-- 1.8.0 strings carry NUL padding from their encoder: drop it
	text = text:gsub("%z+$", "")
	local data, err = deserialize(text)
	if type(data) ~= "table" then
		return nil, "The string is damaged (" .. tostring(err or "unreadable") .. ")"
	end
	if type(data.settings) ~= "table" then return nil, "The string holds no settings" end
	local fv = tonumber(data.format_version) or 0
	if fv > FORMAT_VERSION then
		return nil, "The string comes from a newer SwedgeTimer (format " .. fv .. ") - update the addon"
	end
	return data
end

function IE.import_settings(import_string)
	if not (ST.db and ST.db.profile) then return false, "SwedgeTimer is still loading" end
	local data, err = IE.decode(import_string)
	if not data then return false, err end

	local applied, unknown, rejected = IE.apply_settings(data.settings)
	if applied == 0 then
		return false, "Nothing usable in that string"
	end

	if ST.RefreshAllUI then ST:RefreshAllUI() else IE.refresh_all_ui() end

	local msg = "Imported " .. applied .. " settings"
	local extra = {}
	if data.addon_version and data.addon_version ~= "" then extra[#extra + 1] = "from SwedgeTimer " .. tostring(data.addon_version) end
	if unknown > 0 then extra[#extra + 1] = unknown .. " unknown skipped" end
	if rejected > 0 then extra[#extra + 1] = rejected .. " invalid skipped" end
	if #extra > 0 then msg = msg .. " (" .. table.concat(extra, ", ") .. ")" end
	return true, msg
end

--=========================================================================================
-- Rebuild every on-screen element from the profile (after an import or a profile
-- switch). Each module's own "apply" is called so nothing is re-implemented here.
--=========================================================================================
function IE.refresh_all_ui()
	if not (st.bar and st.bar.frame) then return end
	local db = ST.db.profile
	local SML = LibStub("LibSharedMedia-3.0")
	local frame = st.bar.frame

	-- the bar: geometry, outline, textures, fonts, markers, colours, layering, visibility
	if st.set_bar_size then st.set_bar_size() end          -- size + fonts + markers + icons
	if st.set_bar_position then st.set_bar_position() end  -- anchors + outline
	if st.set_deadzone then st.set_deadzone() end
	if frame.bar then frame.bar:SetTexture(SML:Fetch("statusbar", db.bar_texture_key)) end
	if frame.gcd_bar then
		frame.gcd_bar:SetTexture(SML:Fetch("statusbar", db.gcd_texture_key))
		frame.gcd_bar:SetVertexColor(unpack(db.bar_color_gcd))
	end
	if frame.deadzone then
		if db.enable_deadzone then frame.deadzone:Show() else frame.deadzone:Hide() end
	end
	frame:SetFrameStrata(db.frame_strata)
	frame:SetFrameLevel(db.draw_level + 1)
	if frame.backplane then
		frame.backplane:SetFrameStrata(db.frame_strata)
		frame.backplane:SetFrameLevel(db.draw_level)
	end
	frame:SetMovable(not db.bar_locked)
	frame:EnableMouse(not db.bar_locked)
	if st.bar.set_bar_color then st.bar.set_bar_color() end
	if st.bar.set_gcd_bar_width then st.bar.set_gcd_bar_width() end
	if st.bar.update_texts then st.bar.update_texts() end
	if st.bar.show_or_hide_bar then st.bar.show_or_hide_bar() end

	-- seal icons
	if st.bar.set_seal_timer_text_properties then st.bar.set_seal_timer_text_properties() end
	if st.bar.set_icon_size then st.bar.set_icon_size() end       -- includes position
	if st.bar.icon_frame then
		st.bar.icon_frame:SetFrameStrata(db.frame_strata)
		st.bar.icon_frame:SetFrameLevel(db.draw_level + 1)
	end
	if st.bar.update_seal_icons then st.bar.update_seal_icons() end

	-- successful twist text
	if st.bar.update_success_text_properties then st.bar.update_success_text_properties() end
	if st.bar.set_success_text_position then st.bar.set_success_text_position() end

	-- the guide, the HUD, the rotation text
	if st.nextaction and st.nextaction.apply_settings then st.nextaction.apply_settings() end
	if st.hud and st.hud.apply_settings then st.hud.apply_settings() end
	if st.rotation_text and st.rotation_text.apply_settings then st.rotation_text.apply_settings() end

	-- practice mode displays (only when built)
	if st.practice then
		if st.practice.update_rotation_display then pcall(st.practice.update_rotation_display) end
		if st.practice.timeline_frame then st.practice.timeline_needs_render = true end
	end

	-- minimap button
	local icon = LibStub("LibDBIcon-1.0", true)
	if icon and icon.Refresh and db.minimap then pcall(icon.Refresh, icon, "SwedgeTimer", db.minimap) end
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed import_export.lua module correctly') end
