local addon_name, st = ...
st.debug_counter = 0
st.utils = {}

-- Sends the given message to the chat frame with the addon name in front.
st.utils.print_msg = function(msg)
	-- print(type(msg))
	st.debug_counter = st.debug_counter + 1
	if type(msg) == "table" then
		-- print('found a table')
		st.utils.table_printer(msg)
		return
	end
	-- elseif type(msg) == "boolean" then
	msg = tostring(msg)
	-- end
	local chat_msg = "|cFFF58CBA" .. addon_name .. ": [" .. st.debug_counter .. "] |r" .. msg
	DEFAULT_CHAT_FRAME:AddMessage(chat_msg)
end

-- Rounds down, e.g. if step=0.1 will round down to 1dp.
st.utils.simple_round = function(num, step)
    return floor(num / step) * step
end

st.utils.table_printer = function(table)
	for key, value in pairs(table) do
        st.utils.print_msg('key ' .. key)
        st.utils.print_msg(value)
    end
end

-- Converts a list to a lookup table.
st.utils.convert_lookup_table = function(list)
	local my_table = {}
	for _, id in ipairs(list) do my_table[id] = true end
	return my_table
end


-- Detect if two numbers are within a given tolerance of each other
st.utils.test_tolerance = function(n1, n2, tolerance)
	local diff = math.abs(n1 - n2)
	if diff < tolerance then
		return true
	else
		return false
	end
end

-- Detect if the player is a paladin
st.utils.player_is_paladin = function()
	local english_class = select(2, UnitClass("player")) -- same in all locales
	if english_class == "PALADIN" then
		 return true
	end
	return false
end


--=======================================================================================
-- The shared font chain (one implementation for the whole addon)
--
-- A FontString that carries no font throws on SetText ("Font not set") on a real
-- client, so every FontString must be fonted BEFORE its first SetText. The chain
-- is
--     the caller's path -> STANDARD_TEXT_FONT -> the classic client font
-- and every step is pcall-guarded: a missing LSM, a throwing Fetch, a missing
-- STANDARD_TEXT_FONT or a FontString that refuses the font degrades to the next
-- step instead of throwing out of a frame build. Nothing here ever throws.
--=======================================================================================
local FONT_FALLBACK_PATH = "Fonts\\FRIZQT__.TTF"

-- Resolves an LSM font key to a font path. Never throws; nil when the key cannot
-- be resolved (the caller then walks the fallback chain). The key may live in
-- another addon's LSM registration - the resolved path is that addon's file, and
-- the FontString still has to receive it.
st.utils.fetch_font_path = function(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    local ok_lib, lsm = pcall(LibStub, "LibSharedMedia-3.0", true)
    if not ok_lib or type(lsm) ~= "table" or type(lsm.Fetch) ~= "function" then
        return nil
    end
    local ok_fetch, path = pcall(lsm.Fetch, lsm, "font", key)
    if not ok_fetch or type(path) ~= "string" or path == "" then
        return nil
    end
    return path
end

-- Applies a font to a FontString. Never throws. The chain is the given path, then
-- STANDARD_TEXT_FONT, then the classic client font; the first candidate the
-- FontString accepts wins. Returns true when a font was applied (a FontString
-- without GetFont cannot be checked, so an applied font is taken at face value).
st.utils.apply_font = function(text, path, size, outline)
    if type(text) ~= "table" or type(text.SetFont) ~= "function" then
        return false
    end
    if type(size) ~= "number" then
        size = 12
    end
    if type(outline) ~= "string" then
        outline = ""
    end
    local candidates = {}
    if type(path) == "string" and path ~= "" then
        candidates[#candidates + 1] = path
    end
    local standard = STANDARD_TEXT_FONT
    if type(standard) == "string" and standard ~= "" then
        candidates[#candidates + 1] = standard
    end
    candidates[#candidates + 1] = FONT_FALLBACK_PATH
    for i = 1, #candidates do
        local ok, res = pcall(text.SetFont, text, candidates[i], size, outline)
        if ok and res ~= false then
            if type(text.GetFont) ~= "function" then
                return true
            end
            local ok_get, got = pcall(text.GetFont, text)
            if not ok_get or got ~= nil then
                return true
            end
        end
    end
    return false
end

--=======================================================================================
-- a switch to control debug statements in module parsing
-- NOTE: this does not incur any additional CPU usage in the addon's
--       typical operation, just in parsing the code.
st.debug = false

if st.debug then st.utils.print_msg('-- Parsed util.lua module correctly') end
