-- main.lua ============================================================================
local addon_name, st = ...
-- local L = st.localization_table
local version = "1.9.0"
local load_message = "version |cFF00FF00" .. version .. "|r loaded! New: |cFF00FF00/st design|r arranges everything on screen. Settings via |cFF00FF00/st|r."
local ST = LibStub("AceAddon-3.0"):GetAddon("SwedgeTimer")
local SML = LibStub("LibSharedMedia-3.0")
local print = st.utils.print_msg

st.core = {}
st.core.in_combat = false

--=========================================================================================
-- A frame to detect if the player is in combat or not.
st.core.in_combat_frame = CreateFrame("Frame", addon_name .. "CombatFrame", UIParent)
local function in_combat_frame_event_handler(self, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        st.core.in_combat = false
        -- Reset extra attacks counter when leaving combat (safety cleanup)
        st.player.extra_attacks_pending = 0
    elseif event == "PLAYER_REGEN_DISABLED" then
        st.core.in_combat = true
    end
    st.bar.update_bar_on_combat()
end

--=========================================================================================
-- Now, a frame to load the addon upon intercepting the ADDON_LOADED event trigger
--=========================================================================================
-- This function is called once when the addon is loaded, and 
-- sets up the various frames and elements.
local function init_addon(self)

    -- Load visuals
    if st.debug then print('Initialising visuals...') end
    st.bar.init_bar_visuals()

    -- Register SharedMedia callback for late-loaded textures (fixes texture reset on /reload)
    -- Other addons like SharedMedia_MyMedia may register textures after SwedgeTimer loads
    SML.RegisterCallback(ST, "LibSharedMedia_Registered", function(event, mediatype, key)
        if mediatype == "statusbar" and st.bar.frame then
            local db = ST.db.profile
            if key == db.bar_texture_key then
                st.bar.frame.bar:SetTexture(SML:Fetch('statusbar', key))
            end
            if key == db.gcd_texture_key then
                st.bar.frame.gcd_bar:SetTexture(SML:Fetch('statusbar', key))
            end
            if key == db.deadzone_texture_key then
                st.set_deadzone()
            end
            if key == db.backplane_texture_key or key == db.border_texture_key then
                st.configure_bar_outline()
            end
            if key == db.marker_texture then
                st.set_marker_colors()
            end
        elseif mediatype == "font" and st.bar.frame then
            local db = ST.db.profile
            if key == db.text_font then
                st.set_fonts()
            end
        end
    end)

    -- Initialize rotation helper (after bar visuals)
    if st.debug then print('Initialising rotation helper...') end
    st.bar.init_rotation_helper()

    -- Initialize practice mode
    if st.debug then print('Initialising practice mode...') end
    if st.practice and st.practice.init then
        st.practice.init()
    end

    -- Initialize the next action guide
    if st.debug then print('Initialising next action guide...') end
    if st.nextaction and st.nextaction.init then
        st.nextaction.init()
    end

    -- Initialize the cooldown HUD
    if st.debug then print('Initialising cooldown HUD...') end
    if st.hud and st.hud.init then
        st.hud.init()
    end

    -- Initialize the rotation text
    if st.rotation_text and st.rotation_text.init then
        st.rotation_text.init()
    end

    if st.debug then print('Registering events and widget handlers...') end
    -- Register the in-combat events and widget handlers
    st.core.in_combat_frame:SetScript("OnEvent", in_combat_frame_event_handler)
    st.core.in_combat_frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    st.core.in_combat_frame:RegisterEvent("PLAYER_REGEN_DISABLED")

    -- Attach the events and widget handlers for the player stats frame
    st.player_frame:SetScript("OnEvent", st.player.frame_on_event)
    st.player_frame:SetScript("OnUpdate", st.player.frame_on_update)
    st.player_frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    st.player_frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    st.player_frame:RegisterUnitEvent("UNIT_AURA", "player")
    st.player_frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    st.player_frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")

    -- TBC Classic: These events don't exist in TBC, commenting out
    -- st.player_frame:RegisterEvent("EXECUTE_CHAT_LINE")
    -- st.player_frame:RegisterEvent("PLAYER_TARGET_SET_ATTACKING")

    st.player_frame:RegisterEvent("CHARACTER_POINTS_CHANGED")
    st.player_frame:RegisterEvent("PLAYER_TALENT_UPDATE")
    st.player_frame:RegisterEvent("UNIT_SPELLCAST_SENT")
    st.player_frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    st.player_frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    st.player_frame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")

    -- Any operations to initialise the player state
    st.player.swing_timer = 0.00001
    st.player.update_weapon_speed()
    st.player.calculate_spell_GCD_duration()
    st.player.on_player_aura_change()
    st.player.update_lag()

    -- Initialize ret spec state (before first show_or_hide_bar call)
    st.utils.update_ret_spec()

    -- Some settings that have to be set after the bar is initialised
    st.bar.update_visuals_on_update()
    st.bar.set_bar_color()
    st.bar.set_gcd_bar_width()
    st.bar.set_bar_color()
    st.bar.show_or_hide_bar()
    st.bar.update_seal_icons()

    -- Initialize minimap button
    if st.minimap and st.minimap.init then
        st.minimap.init()
    end

    -- Design mode (combat auto-lock)
    if st.editmode and st.editmode.init then
        st.editmode.init()
    end

    -- If appropriate show welcome message
    if st.debug then print('... complete!') end
    if ST.db.profile.welcome_message then print(load_message) end

    -- one-time note for profiles upgraded from an older version (see migrate_saved_variables)
    local current = ST.db.GetCurrentProfile and ST.db:GetCurrentProfile()
    for _, name in ipairs(ST.migrated_profiles or {}) do
        if name == current then
            print("Updated to " .. version .. ": your layout is untouched. New optional elements (Cooldown HUD, "
                .. "Rotation text) are off by default - turn them on with |cFF00FF00/st design|r.")
            break
        end
    end
end

-- The frame responsible for loading the addon at the appropriate time
st.core.init_frame = CreateFrame("Frame", addon_name .. "InitFrame", UIParent)
local function init_frame_event_handler(self, event, ...)
    local args = {...}
    if event == "ADDON_LOADED" then
        if args[1] == "SwedgeTimer" then

            -- Only load the addon if the player is a paladin
            if not st.utils.player_is_paladin() then
                st.core.init_frame:SetScript("OnEvent", nil)
                return
            end
        
            -- else, load it
            init_addon()

            -- Now we've loaded, remove the handler from the frame to stop it 
            -- processing events
            st.core.init_frame:SetScript("OnEvent", nil)
        end
    end
end

st.core.init_frame:SetScript("OnEvent", init_frame_event_handler)
st.core.init_frame:RegisterEvent("ADDON_LOADED")

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed main.lua module correctly') end
