-- minimap.lua
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon("SwedgeTimer")
local print = st.utils.print_msg

st.minimap = {}

-- Create LibDataBroker launcher object
local ldb = LibStub("LibDataBroker-1.1"):NewDataObject("SwedgeTimer", {
    type = "data source",
    text = "SwedgeTimer",
    icon = GetSpellTexture(20375),  -- Seal of Command

    OnClick = function(self, button)
        if button == "LeftButton" then
            ST.db.profile.bar_enabled = not ST.db.profile.bar_enabled
            st.bar.show_or_hide_bar()
        elseif button == "RightButton" then
            if ST.OpenSettings then
                ST:OpenSettings()
            end
        end
    end,

    OnTooltipShow = function(tooltip)
        tooltip:SetText("SwedgeTimer")
        tooltip:AddLine("|cffeda55fLeft-Click:|r Toggle swing timer", 1, 1, 1)
        tooltip:AddLine("|cffeda55fRight-Click:|r Open settings", 1, 1, 1)
    end,
})

local icon = LibStub("LibDBIcon-1.0")

st.minimap.init = function()
    icon:Register("SwedgeTimer", ldb, ST.db.profile.minimap)
end

st.minimap.show = function()
    ST.db.profile.minimap.hide = false
    icon:Show("SwedgeTimer")
end

st.minimap.hide = function()
    ST.db.profile.minimap.hide = true
    icon:Hide("SwedgeTimer")
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed minimap.lua module correctly') end
