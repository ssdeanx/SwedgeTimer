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
	diff = math.abs(n1 - n2)
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
-- Spec analyzer (ported from ClassicRaidTools' Inspect.lua, own-player half only).
-- Sums the ranks of every talent per tab and calls the dominant tab the spec, so it is
-- locale independent and works for any build. Fewer than 5 points total, or an exact
-- tie between tabs, is "unknown" (a fresh leveling paladin).
--=======================================================================================
st.spec = {}
st.spec.tabs = {
	{ key = "holy", name = "Holy" },
	{ key = "protection", name = "Protection" },
	{ key = "retribution", name = "Retribution" },
}
st.spec.MIN_POINTS = 5
st.spec.current = { key = nil, name = "Unknown", points = { 0, 0, 0 }, total = 0 }

-- Points spent in a talent tab. Primary method sums each talent's rank (the 5th return
-- of GetTalentInfo on classic-era clients); GetTalentTabInfo's pointsSpent sits at a
-- different position on the hybrid Anniversary client and misread the tree.
local function tab_points_via_talents(index)
	if not (GetNumTalents and GetTalentInfo) then return nil end
	local n = GetNumTalents(index)
	if not n or n == 0 then return nil end
	local total = 0
	for t = 1, n do
		local _, _, _, _, rank = GetTalentInfo(index, t)
		total = total + (tonumber(rank) or 0)
	end
	return total
end

local function tab_points_via_tabinfo(index)
	if not GetTalentTabInfo then return 0 end
	local r1, _, r3, _, r5 = GetTalentTabInfo(index)
	if type(r1) == "string" then return tonumber(r3) or 0 end
	return tonumber(r5) or tonumber(r3) or 0
end

-- Re-reads the player's talents. Returns the spec table (also stored in st.spec.current).
st.spec.read = function()
	local tabs = st.spec.tabs
	local n_tabs = math.min((GetNumTalentTabs and GetNumTalentTabs()) or #tabs, #tabs)
	local pts, total = {}, 0
	for i = 1, n_tabs do
		pts[i] = tab_points_via_talents(i)
		total = total + (pts[i] or 0)
	end
	if total == 0 then
		total = 0
		for i = 1, n_tabs do
			pts[i] = tab_points_via_tabinfo(i)
			total = total + (pts[i] or 0)
		end
	end
	for i = 1, #tabs do pts[i] = pts[i] or 0 end
	local best
	for i = 1, #tabs do
		if not best or pts[i] > pts[best] then best = i end
	end
	local key, name = nil, "Unknown"
	if best and pts[best] >= st.spec.MIN_POINTS then
		local tie = false
		for i = 1, #tabs do
			if i ~= best and pts[i] == pts[best] then tie = true end
		end
		if not tie then key, name = tabs[best].key, tabs[best].name end
	end
	st.spec.current = { key = key, name = name, points = pts, total = total }
	return st.spec.current
end

-- "Retribution (0 / 0 / 41)" style summary for the settings window and /st spec.
st.spec.describe = function()
	local c = st.spec.current or st.spec.read()
	local p = c.points or { 0, 0, 0 }
	local label = c.name or "Unknown"
	if not c.key then
		label = (c.total or 0) < st.spec.MIN_POINTS and "Leveling (no spec yet)" or "Unknown"
	end
	return label, string.format("%d / %d / %d", p[1] or 0, p[2] or 0, p[3] or 0)
end

-- /st spec : print the per-tab points the addon reads and the spec it picks.
st.spec.print = function()
	local c = st.spec.read()
	local parts = {}
	for i, tab in ipairs(st.spec.tabs) do
		parts[#parts + 1] = tab.name .. "=" .. tostring(c.points[i] or 0)
	end
	local label = c.key and c.name or "|cFFFF6060unknown|r"
	if not c.key and c.total < st.spec.MIN_POINTS then label = "leveling (fewer than " .. st.spec.MIN_POINTS .. " points)" end
	st.utils.print_msg("Spec: " .. table.concat(parts, "  ") .. "  => " .. label
		.. (st.utils.is_ret_spec and "  (bar shown with Ret only)" or "  (bar hidden with Ret only)"))
end

-- Kept for compatibility: true when the dominant tree is Retribution.
st.utils.player_has_2h_spec = function()
	return st.spec.read().key == "retribution"
end

-- Cached ret spec state. True for Retribution AND for a paladin with no spec yet
-- (leveling): "Ret only" should never hide the bar from someone we cannot classify.
st.utils.is_ret_spec = false

local function ret_or_unknown()
	local c = st.spec.read()
	return c.key == "retribution" or c.key == nil
end

local function refresh_dependents()
	if st.bar and st.bar.frame and st.bar.show_or_hide_bar then
		st.bar.show_or_hide_bar()
	end
	if st.nextaction and st.nextaction.frame and st.nextaction.apply_settings then
		st.nextaction.apply_settings()
	end
	if st.settings_ui and st.settings_ui.request_refresh then
		st.settings_ui.request_refresh()
	end
end

-- Update cached ret spec state and trigger bar visibility refresh
-- Uses a delayed re-check because talent API may not be updated yet when
-- CHARACTER_POINTS_CHANGED fires (common TBC Classic issue)
st.utils.update_ret_spec = function()
    st.utils.is_ret_spec = ret_or_unknown()
    refresh_dependents()

    -- Schedule a delayed re-check after 0.5s in case the talent API wasn't ready
    if not st.utils.ret_spec_timer_frame then
        st.utils.ret_spec_timer_frame = CreateFrame("Frame")
    end
    st.utils.ret_spec_pending = 0.5
    st.utils.ret_spec_timer_frame:SetScript("OnUpdate", function(self, elapsed)
        st.utils.ret_spec_pending = st.utils.ret_spec_pending - elapsed
        if st.utils.ret_spec_pending <= 0 then
            self:SetScript("OnUpdate", nil)
            st.utils.is_ret_spec = ret_or_unknown()
            refresh_dependents()
        end
    end)
end

--=======================================================================================
-- a switch to control debug statements in module parsing
-- NOTE: this does not incur any additional CPU usage in the addon's
--       typical operation, just in parsing the code.
st.debug = false

if st.debug then st.utils.print_msg('-- Parsed util.lua module correctly') end
