local addon_name, st = ...

-- Register a left-aligned dropdown widget for AceGUI
-- This is used by AceConfig dialogControl to display dropdown text left-aligned

local AceGUI = LibStub("AceGUI-3.0")

do
    local widgetType = "Dropdown-Left"
    local widgetVersion = 1

    local function Constructor()
        -- Create a standard dropdown widget
        local widget = AceGUI:Create("Dropdown")

        -- Left-align the selected text
        if widget.text then
            widget.text:SetJustifyH("LEFT")
        end

        widget.type = widgetType
        return widget
    end

    AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion)
end

-- A dropdown for the addon's sound settings that previews a sound when its list
-- entry is hovered. List keys must be keys of st.bar.twist_sounds.
do
    local widgetType = "Dropdown-SoundPreview"
    local widgetVersion = 1

    local preview_handle = nil

    local function item_on_enter(item)
        local key = item.userdata and item.userdata.value
        local sound_path = key and st.bar and st.bar.twist_sounds and st.bar.twist_sounds[key]
        if not sound_path then return end

        -- Stop the previous preview so sweeping across the list doesn't stack sounds
        if preview_handle then
            StopSound(preview_handle)
            preview_handle = nil
        end

        local ST = LibStub("AceAddon-3.0"):GetAddon("SwedgeTimer", true)
        local channel = ST and ST.db and ST.db.profile.sound_channel or "Master"
        local will_play, handle = PlaySoundFile(sound_path, channel)
        if will_play then
            preview_handle = handle
        end
    end

    local function Constructor()
        local widget = AceGUI:Create("Dropdown")

        -- Hook every list item's hover after the list is (re)built
        local orig_SetList = widget.SetList
        widget.SetList = function(self, list, order, itemType)
            orig_SetList(self, list, order, itemType)
            if self.pullout and self.pullout.items then
                for _, item in ipairs(self.pullout.items) do
                    item:SetCallback("OnEnter", item_on_enter)
                end
            end
        end

        widget.type = widgetType
        return widget
    end

    AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion)
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed widgets.lua module correctly') end
