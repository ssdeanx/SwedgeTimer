------------------------------------------------------------------------------------
-- Module to contain option table defaults
--
-- The module's purpose is to dynamically generate any options tables
-- depending on player class that the addon needs. So for example,
-- a Paladin will only ever see the mainhand options, and the Paladin-specific 
-- class options.
------------------------------------------------------------------------------------
local addon_name, st = ...
---@class ST
---@field opts_table table
---@field opts_funcs table
---@field set_adjusted_latencies fun(self: ST)
---@field set_gcd_times_before_swing_seconds fun(self: ST)
---@field iter_hands fun(self: ST):any
---@field generic_iter fun(self: ST, hands: any):any
---@field set_deadzone_width fun(self: ST, hand: any)
---@field set_gcd_marker_positions fun(self: ST, hand: any)
---@field configure_texts fun(self: ST, hand: any)
---@field configure_bar_size_and_positions fun(self: ST, hand: any)
---@field configure_bar_appearances fun(self: ST, hand: any)
---@field configure_bar_outline fun(self: ST, hand: any)
---@field configure_gcd_markers fun(self: ST, hand: any)
---@field configure_deadzone fun(self: ST, hand: any)
---@field set_bar_color fun(self: ST, hand: any)
---@field configure_frame_strata fun(self: ST, hand: any)
---@field lock_frames fun(self: ST)
---@field unlock_frames fun(self: ST)
---@field get_profile_table fun(self: ST):table
---@field get_class_table fun(self: ST):table
---@field get_hand_table fun(self: ST, hand: any):table
---@field convert_color fun(self: ST, color_table: any):any
---@field convert_color_up fun(self: ST, color_table: any):any
---@field determine_form_visibility_flag fun(self: ST)
---@field handle_bar_visibility fun(self: ST, hand: any)
---@field get_anchor_frame fun(self: ST, hand: any):any
---@field valid_anchor_points table
---@field bar_appearance_preset table
---@field fonts_table_preset table
---@field deadzone_settings_table table
---@field gcd_underlay_preset table
---@field gcd_markers_preset table
---@field gcd_marker_modes table
---@field show_bar_opts table
---@field show_bar_conditions table
---@field show_bar_conditions_sorting table
---@field build_preset_options_tables fun(self: ST)
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
local LSM = LibStub("LibSharedMedia-3.0")
local LWIN = LibStub("LibWindow-1.1")
local print = st.utils.print_msg

-- This object will eventually be passed to AceConfig as the options
-- table for the addon. We'll build it dynamically upon addon init.
ST.opts_table = {
    name = "SwedgeTimer",
    type = "group",
    args = {
        -- global_header = {
        --     order = 0.01,
        --     type = "header",
        --     name = "Global and Class Configuration",
        -- },
        -- This title breaks the bar submenus from the global one.
        bar_header = {
            order = 10,
            type = "header",
            name = "Timer Configuration",
        },
    },
}

-- We're going to add helper funcs to a table that the hand opts
-- tables can reference for setters and getters.
ST.opts_funcs = {}

-- Initialize player class information
local _, english_class = UnitClass("player")
ST.player_class_pretty = english_class or "Player"
ST.player_class = string.lower(ST.player_class_pretty)

-- Available hands per class live in main.lua, keyed by the uppercase class token.
-- This file used to redefine the table with lowercase keys, clobbering it and crashing
-- ST:iter_hands() during OnInitialize. Do not reintroduce a definition here; use
-- ST:get_class_hands() instead.

-- Initialize info panels
ST.info_panel = {}
ST.class_info_panel = {}

-- Setter and getter for global funcs
ST.opts_funcs.global = {}
-- Retrieve the localized class name of the player (e.g., "Paladin"),
-- used for class-specific labels in the options table.
ST.opts_funcs.global.get_player_class_pretty = function()
    local _, english_class = UnitClass("player")
    return english_class or "Player"
end
ST.opts_funcs.global.getter = function(_, info)
    local db = ST:get_profile_table()
    return db[info[#info]]
end
ST.opts_funcs.global.setter = function(_, info, value)
    local db = ST:get_profile_table()
    db[info[#info]] = value
end
-- Setter for latency options.
ST.opts_funcs.global.latency_setter = function(_, info, value)
    local db = ST:get_profile_table()
    db[info[#info]] = value
    ST:set_adjusted_latencies()
    ST:set_gcd_times_before_swing_seconds()
    for hand in ST:iter_hands() do
        ST:set_deadzone_width(hand)
        ST:set_gcd_marker_positions(hand)
    end
end
-- Setter for strata options.
ST.opts_funcs.global.strata_setter = function(_, info, value)
    local db = ST:get_profile_table()
    db[info[#info]] = value
    for hand in ST:iter_hands() do
        ST:configure_frame_strata(hand)
    end
end

function ST:generate_top_level_options_table()
    -- Set the top-level options that are displayed above the settings menu.
    self.opts_table.handler = self.opts_funcs.global
    self.opts_table.args.class_enabled = {
        type = "toggle",
        order = 1.1,
        name = string.format("%s Enable/Disable", self.opts_funcs.global.get_player_class_pretty()),
        desc = "Enables or disables SwedgeTimer for this class.",
        get = function()
            local db = ST:get_class_table()
            return db.class_enabled
        end,
        set = function(_, value)
            local db = ST:get_class_table()
            db.class_enabled = value
        end,
    }
    self.opts_table.args.enable_spec1 = {
        type = "toggle",
        order = 1.11,
        name = "Spec 1",
        desc = "Enables the timer when Talent Specialization 1 is active.",
        get = function()
            return ST:get_class_table().enable_spec1
        end,
        set = function(_, value)
            ST:get_class_table().enable_spec1 = value
        end,
        disabled = function()
            return not ST:get_class_table().class_enabled
        end,
    }
    self.opts_table.args.enable_spec2 = {
        type = "toggle",
        order = 1.12,
        name = "Spec 2",
        desc = "Enables the timer when Talent Specialization 2 is active.",
        get = function()
            return ST:get_class_table().enable_spec2
        end,
        set = function(_, value)
            ST:get_class_table().enable_spec2 = value
        end,
        disabled = function()
            return not ST:get_class_table().class_enabled
        end,
    }
    self.opts_table.args.weave_range_enabled = {
        type = "toggle",
        order = 1.13,
        name = "Melee-weave proximity bar",
        desc = "Show a vertical bar next to the player frame that fills as the distance to "..
            "your attackable target closes (melee to 30 yd) and drains as it grows; the "..
            "label prints the current range band in yards. Off by default.",
        get = function()
            return ST:get_class_table().weave_range_enabled == true
        end,
        set = function(_, value)
            ST:get_class_table().weave_range_enabled = value
        end,
        disabled = function()
            return not ST:get_class_table().class_enabled
        end,
    }
    self.opts_table.args.timers_locked = {
        type = "toggle",
        order = 1.2,
        name = "Timers locked",
        desc = "Prevents all swing timers from being dragged or scaled with the mouse.",
        get = function()
            local db = ST:get_class_table()
            return db.timers_locked
        end,
        set = function(_, input)
            local db = ST:get_class_table()
            db.timers_locked = input
            if db.timers_locked then
                ST:lock_frames()
            else
                ST:unlock_frames()
            end
        end,
    }
    self.opts_table.args.welcome_message = {
        type = "toggle",
        order = 1.3,
        name = "Welcome message",
        desc = "Displays a login message showing the addon version on player login or reload.",
        get = "getter",
        set = "setter",
    }

    -- Add behaviour panel
    ST.behaviour_group = {
        name = "Behaviour",
        type = "group",
        desc = "Configure timer behaviour options.",
        order = 1.4,
        args = {},
    }
    ST.opts_table.args.behaviour = ST.behaviour_group

    -- Add the Design Mode panel (designmode.lua): the global unlock. Its persisted keys
    -- (design_grid_enabled / design_grid / design_snap / design_snap_threshold) live in
    -- the shared class defaults; the enabled state is a session state (no db key).
    ST.opts_table.args.design_mode = {
        name = "Design Mode",
        type = "group",
        desc = "Position every element this build shows: a snap grid over the screen and a "..
            "draggable overlay on each frame.",
        order = 1.45,
        args = {
            design_desc = {
                type = "description",
                order = 1.0,
                name = "Design mode unlocks every element this class actually has - the swing "..
                    "bars, the Cooldown HUD, the rotation label, the Next Action Guide and the "..
                    "practice panel while a session runs. Elements that are not created on this "..
                    "class (or not visible) are skipped. Drag an overlay to move its element; "..
                    "hold Shift to place it freely and Alt to force the exact screen centre. "..
                    "Double-click an overlay to reset it; Esc or /st design ends the session. "..
                    "A session can only start out of combat.",
            },
            design_toggle = {
                type = "execute",
                order = 1.1,
                name = function()
                    if st.designmode and st.designmode.is_active() then
                        return "Stop Design Mode"
                    end
                    return "Start Design Mode"
                end,
                desc = "Toggle design mode. Also available as /st design; Esc ends it.",
                func = function()
                    if st.designmode then
                        st.designmode.toggle(ST)
                    end
                end,
            },
            design_grid_enabled = {
                type = "toggle",
                order = 1.2,
                name = "Show grid",
                desc = "Draw the snap grid over the screen while design mode runs.",
                get = function()
                    return ST:get_class_table().design_grid_enabled ~= false
                end,
                set = function(_, value)
                    ST:get_class_table().design_grid_enabled = value
                    if st.designmode then st.designmode.refresh_grid() end
                end,
            },
            design_grid = {
                type = "range",
                order = 1.3,
                name = "Grid step (px)",
                desc = "Grid step dragged elements quantise to when nothing aligns. Steps below 8 count as off.",
                min = 8, max = 64, step = 8,
                get = function()
                    return tonumber(ST:get_class_table().design_grid) or 24
                end,
                set = function(_, value)
                    ST:get_class_table().design_grid = value
                    if st.designmode then st.designmode.refresh_grid() end
                end,
                disabled = function()
                    return ST:get_class_table().design_grid_enabled == false
                end,
            },
            design_snap = {
                type = "toggle",
                order = 1.4,
                name = "Snap to elements and screen centre",
                desc = "Snap a dragged element to the other elements' edges and centres (and the "..
                    "screen centre) within the threshold.",
                get = function()
                    return ST:get_class_table().design_snap ~= false
                end,
                set = function(_, value)
                    ST:get_class_table().design_snap = value
                end,
            },
            design_snap_threshold = {
                type = "range",
                order = 1.5,
                name = "Snap threshold (px)",
                desc = "How close a line must be before it snaps, in pixels.",
                min = 2, max = 32, step = 1,
                get = function()
                    return tonumber(ST:get_class_table().design_snap_threshold) or 8
                end,
                set = function(_, value)
                    ST:get_class_table().design_snap_threshold = value
                end,
                disabled = function()
                    return ST:get_class_table().design_snap == false
                end,
            },
            design_note = {
                type = "description",
                order = 1.6,
                name = "\nElements only exist while their module has built them - a class with no "..
                    "Cooldown HUD slots or a hidden practice panel will not offer one to position.",
            },
        },
    }

end

function ST:generate_info_panel()
    self.opts_table.args.info = {
        type = "group",
        order = 0.1,
        name = "Info",
        args = ST.info_panel,
    }
    self.opts_table.args.class_info = {
        type = "group",
        order = 0.2,
        name = string.format("%s Info", self.player_class_pretty),
        args = ST.class_info_panel,
    }
end

--=========================================================================================
-- This section sets the widget set/get functions using handlers.
--=========================================================================================
function ST:set_opts_case_dict()
    -- This function sets a case dict for setting the bar sub-menus.
    self.opts_case_dict = {
        mainhand = {
            pretty_name = "Mainhand",
            title = "Mainhand Controls",
            panel_title = string.format("Mainhand", self.player_class_pretty),
            desc = "This panel and its subpanels configure the settings for the mainhand timer.\n",
            hands = {"mainhand"},
            order_offset = 1,
        },
        offhand = {
            pretty_name = "Offhand",
            title = "Offhand Controls",
            panel_title = string.format("Offhand", self.player_class_pretty),
            desc = "This panel and its subpanels configure the settings for the offhand timer.\n",
            hands = {"offhand"},
            order_offset = 2,
        },
        ranged = {
            pretty_name = "Ranged",
            title = "Ranged Controls",
            panel_title = string.format("Ranged", self.player_class_pretty),
            desc = "This panel and its subpanels configure the settings for the ranged timer.\n",
            hands = {"ranged"},
            order_offset = 3,
        },
        all_hands = {
            title = "All Bar Controls",
            panel_title = string.format("All %s hands", self.player_class_pretty),
            desc = "This panel and its subpanels configure the settings for all timers. It is only visible "..
            "to classes that can use multiple types of weapons (mainhand/offhand/ranged)."..
            "\n\nAny changes made here will apply to *all timers*, use caution!\n",
            hands = self:get_class_hands(),
            order_offset = 4,
        },
        melee_hands = {
            title = "Melee Bar Controls",
            panel_title = string.format("%s Melee hands", self.player_class_pretty),
            desc = "This panel and its subpanels configure the settings for both melee timers. It is only visible "..
            "to classes that can use mainhand, offhand, and ranged weapons."..
            "\n\nAny changes made here will apply to *both the mainhand and offhand timers*, use caution!\n",
            hands = {"mainhand", "offhand"},
            order_offset = 5,
        },
    }
end

-- This function will be run when the addon initialises to generate
-- the getter and setter funcs for the hands. These will be a little specialised
-- to ensure the appropriate config functions in the addon are run when the user
-- changes the settings.
function ST:set_opts_funcs()
    for hand, settings in pairs(ST.opts_case_dict) do
        ST.opts_funcs[hand] = {}

        -- A generic getter func for each hand
        if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
            ST.opts_funcs[hand].getter = function(_, info)
                local db = ST:get_hand_table(hand)
                return db[info[#info]]
            end
        else
            -- Just default to the mainhand for the all_bars func.
            ST.opts_funcs[hand].getter = function(_, info)
                local db = ST:get_hand_table("mainhand")
                return db[info[#info]]
            end
        end

        -- A generic setter func for this hand, to be used when
        -- no further state change has to happen
        ST.opts_funcs[hand].setter = function(_, info, value)
            for h in ST:generic_iter(settings.hands) do
                local db = ST:get_hand_table(h)
                db[info[#info]] = value
            end
        end

        -- A setter for bar texts
        ST.opts_funcs[hand].text_setter = function(_, info, value)
            for h in ST:generic_iter(settings.hands) do
                local db = ST:get_hand_table(h)
                db[info[#info]] = value
                ST:configure_texts(h)
            end
        end

        -- A setter for bar appearances
        ST.opts_funcs[hand].bar_setter = function(_, info, value)
            for h in ST:generic_iter(settings.hands) do
                local db = ST:get_hand_table(h)
                db[info[#info]] = value
                ST:configure_bar_size_and_positions(h)
                ST:configure_bar_appearances(h)
                ST:configure_bar_outline(h)
                ST:configure_gcd_markers(h)
                ST:set_gcd_marker_positions(h)
                ST:configure_deadzone(h)
                ST:set_deadzone_width(h)
            end
        end

        -- A getter for colors. Colors are stored in SwedgeTimer's 
        -- db as 0-255 ranges, and need converted to the expected
        -- 0-1 ranges for the client.
        if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
            ST.opts_funcs[hand].color_getter = function(_, info)
                local db = ST:get_hand_table(hand)
                local color_table = db[info[#info]]
                -- print(color_table)
                return ST:convert_color(color_table)
            end
        else
            ST.opts_funcs[hand].color_getter = function(_, info)
                local db = ST:get_hand_table("mainhand")
                local color_table = db[info[#info]]
                return ST:convert_color(color_table)
            end
        end

        -- A setter for colors, which trigger text and bar color configs
        -- We scale up the 0-1 ranges the client uses to the 0-255 ranges
        -- that the SwedgeTimer db uses.
        ST.opts_funcs[hand].color_setter = function(_, info, r, g, b, a)
            for h in ST:generic_iter(settings.hands) do
                local db = ST:get_hand_table(h)
                local color_table = {ST:convert_color_up({r, g, b, a})}
                db[info[#info]] = color_table
                ST:configure_texts(h)
                ST:configure_bar_appearances(h)
                ST:configure_gcd_markers(h)
                ST:configure_deadzone(h)
                ST:configure_bar_outline(h)
                ST:set_bar_color(h)
                ST:set_deadzone_width(h)
            end
        end

        -------------------------------------------------------------------------
        -- Disabler funcs
        -------------------------------------------------------------------------
        -- Left text disabler
        ST.opts_funcs[hand].left_text_disable = function()
            if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
                return not ST:get_hand_table(hand).left_text_enabled
            else
                return not ST:get_hand_table("mainhand").left_text_enabled
            end
        end

        -- Center text disabler
        ST.opts_funcs[hand].center_text_disable = function()
            if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
                return not ST:get_hand_table(hand).center_text_enabled
            else
                return not ST:get_hand_table("mainhand").center_text_enabled
            end
        end

        -- Right text disabler
        ST.opts_funcs[hand].right_text_disable = function()
            if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
                return not ST:get_hand_table(hand).right_text_enabled
            else
                return not ST:get_hand_table("mainhand").right_text_enabled
            end
        end

        -- Solid Border disabler
        ST.opts_funcs[hand].solid_border_disable = function()
            if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
                return ST:get_hand_table(hand).border_mode_key ~= "Solid"
            else
                return ST:get_hand_table("mainhand").border_mode_key ~= "Solid"
            end
        end

        -- Texture Border disabler
        ST.opts_funcs[hand].texture_border_disable = function()
            if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
                return ST:get_hand_table(hand).border_mode_key ~= "Texture"
            else
                return ST:get_hand_table("mainhand").border_mode_key ~= "Texture"
            end
        end

        -- GCD1a anchor disabler
        ST.opts_funcs[hand].gcd1a_anchor_disable = function()
            if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
                return not ST:get_hand_table(hand).gcd1a_marker_enabled
            else
                return not ST:get_hand_table("mainhand").gcd1a_marker_enabled
            end
        end
        -- GCD1a wrap disabler
        ST.opts_funcs[hand].gcd1a_wrap_disable = function()
            if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
                local marker_enabled = ST:get_hand_table(hand).gcd1a_marker_enabled
                local is_anchored_swing = ST:get_hand_table(hand).gcd1a_marker_anchor == "swing"
                return (not marker_enabled) or (not is_anchored_swing)
            else
                local marker_enabled = ST:get_hand_table("mainhand").gcd1a_marker_enabled
                local is_anchored_swing = ST:get_hand_table("mainhand").gcd1a_marker_anchor == "swing"
                return (not marker_enabled) or (not is_anchored_swing)
            end
        end
        -- GCD1b anchor disabler
        ST.opts_funcs[hand].gcd1b_anchor_disable = function()
            if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
                return not ST:get_hand_table(hand).gcd1b_marker_enabled
            else
                return not ST:get_hand_table("mainhand").gcd1b_marker_enabled
            end
        end
        -- GCD1b wrap disabler
        ST.opts_funcs[hand].gcd1b_wrap_disable = function()
            if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
                local marker_enabled = ST:get_hand_table(hand).gcd1b_marker_enabled
                local is_anchored_swing = ST:get_hand_table(hand).gcd1b_marker_anchor == "swing"
                return (not marker_enabled) or (not is_anchored_swing)
            else
                local marker_enabled = ST:get_hand_table("mainhand").gcd1b_marker_enabled
                local is_anchored_swing = ST:get_hand_table("mainhand").gcd1b_marker_anchor == "swing"
                return (not marker_enabled) or (not is_anchored_swing)
            end
        end

        -- Bar vis disablers
        ST.opts_funcs[hand].not_always_shown_disabler = function()
            local db = ST:get_hand_table("mainhand")
            if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
                db = ST:get_hand_table(hand)
            end
            return db.show_behaviour == "always"
        end
        ST.opts_funcs[hand].require_in_range_disabler = function()
            local db = ST:get_hand_table("mainhand")
            if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
                db = ST:get_hand_table(hand)
            end
            if db.show_behaviour == "always" then
                return true
            end
            if db.show_condition == "in_combat" then
                return true
            end
            return false
        end

        -- Range disablers
        ST.opts_funcs[hand].oor_dim_alpha_disabler = function()
            local db = ST:get_hand_table("mainhand")
            if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
                db = ST:get_hand_table(hand)
            end
            return not db.dim_oor
        end
    end
end

--=========================================================================================
-- Class settings/opts tables/getters and setters
--=========================================================================================
-- Generate getter and setters
function ST:generate_class_getters_setters()
    self.class_getsetters = {}

    -- A generic getter func
    ST.class_getsetters.getter = function(_, info)
        local db = ST:get_class_table()
        return db[info[#info]]
    end

    -- A generic setter func
    ST.class_getsetters.setter = function(_, info, value)
        local db = ST:get_class_table()
        db[info[#info]] = value
        ST:determine_form_visibility_flag()
        for h in ST:iter_hands() do
            ST:configure_texts(h)
            ST:configure_bar_size_and_positions(h)
            ST:configure_bar_appearances(h)
            ST:configure_bar_outline(h)
            ST:configure_gcd_markers(h)
            ST:set_gcd_marker_positions(h)
            ST:handle_bar_visibility(h)
        end
    end

    ST.class_getsetters.color_getter = function(self, info)
        local db = ST:get_class_table()
        local color_table = db[info[#info]]
        return ST:convert_color(color_table)
    end

    ST.class_getsetters.color_setter = function(self, info, r, g, b, a)
        local db = ST:get_class_table()
        local color_table = {ST:convert_color_up({r, g, b, a})}
        db[info[#info]] = color_table
        for h in ST:iter_hands() do
            ST:configure_texts(h)
            ST:configure_gcd_markers(h)
            ST:configure_deadzone(h)
            ST:configure_bar_outline(h)
            ST:set_bar_color(h)
        end
    end
end

ST.class_opts_funcs = {}
function ST:generate_class_options_table()
    self:generate_class_getters_setters()
    -- Function to generate the per-class settings.
    if ST.class_opts_funcs[self.player_class] then
        local args = self.class_opts_funcs[self.player_class](self)
        ST.opts_table.args.class = {
            name = string.format("%s Configuration", self.player_class_pretty),
            type = "group",
            desc = string.format("This panel contains settings specific to the %s class.",
                self.player_class_pretty),
            order = 0.5,
            args = args,
            handler = self.class_getsetters,
        }
    end
end

-- Sound choices for the Paladin twist feedback options (section 6.x). Labels ported
-- from the archived build's core.lua; the keys are the saved option values and must
-- stay in sync with the sound file map in classes/paladin.lua.
local twist_sound_options = {
    -- Original sounds
    ["pop"] = "Pop",
    ["bubble-pop"] = "Bubble Pop",
    ["swoosh"] = "Swoosh",
    ["whoopee"] = "Whoopee",
    -- Instruments
    ["AcousticGuitar"] = "Acoustic Guitar",
    ["Brass"] = "Brass",
    ["Drums"] = "Drums",
    ["Glass"] = "Glass",
    ["SynthChord"] = "Synth Chord",
    ["TempleBellHuge"] = "Temple Bell",
    ["Xylophone"] = "Xylophone",
    -- Alerts & UI
    ["AirHorn"] = "Air Horn",
    ["BikeHorn"] = "Bike Horn",
    ["ErrorBeep"] = "Error Beep",
    ["RingingPhone"] = "Ringing Phone",
    ["RobotBlip"] = "Robot Blip",
    ["WarningSiren"] = "Warning Siren",
    ["WaterDrop"] = "Water Drop",
    -- Animals
    ["Bleat"] = "Bleat",
    ["CatMeow2"] = "Cat Meow",
    ["ChickenAlarm"] = "Chicken Alarm",
    ["CowMooing"] = "Cow Moo",
    ["GoatBleating"] = "Goat Bleat",
    ["KittenMeow"] = "Kitten Meow",
    ["RoaringLion"] = "Roaring Lion",
    ["RoosterChickenCalls"] = "Rooster Call",
    ["SheepBleat"] = "Sheep Bleat",
    -- Combat & Action
    ["Bloodlust"] = "Bloodlust",
    ["BatmanPunch"] = "Batman Punch",
    ["Blast"] = "Blast",
    ["BoxingArenaSound"] = "Boxing Arena",
    ["DoubleWhoosh"] = "Double Whoosh",
    ["SharpPunch"] = "Sharp Punch",
    ["Shotgun"] = "Shotgun",
    -- Cartoon & Fun
    ["Applause"] = "Applause",
    ["BananaPeelSlip"] = "Banana Peel Slip",
    ["CartoonVoiceBaritone"] = "Cartoon Voice",
    ["CartoonWalking"] = "Cartoon Walking",
    ["HeartbeatSingle"] = "Heartbeat",
    ["SqueakyToyShort"] = "Squeaky Toy",
    ["SquishFart"] = "Squish Fart",
    ["TadaFanfare"] = "Tada Fanfare",
    -- Voice Callouts
    ["Adds"] = "Adds",
    ["Boss"] = "Boss",
    ["DontRelease"] = "Don't Release",
    ["Empowered"] = "Empowered",
    ["Focus"] = "Focus",
    ["Idiot"] = "Idiot",
    ["OhNo"] = "Oh No",
    ["Protected"] = "Protected",
    ["Release"] = "Release",
    ["RunAway"] = "Run Away",
    ["Spread"] = "Spread",
    ["Stack"] = "Stack",
    ["Taunt"] = "Taunt",
    -- Shapes (Markers)
    ["Circle"] = "Circle",
    ["Cross"] = "Cross",
    ["Diamond"] = "Diamond",
    ["Left"] = "Left",
    ["Moon"] = "Moon",
    ["Right"] = "Right",
    ["Skull"] = "Skull",
    ["Square"] = "Square",
    ["Star"] = "Star",
    ["Triangle"] = "Triangle",
    -- Misc
    ["Next"] = "Next",
    ["Portal"] = "Portal",
    ["Switch"] = "Switch",
    ["Torch"] = "Torch",
}

-- Shared Cooldown HUD + Rotation Text widgets for the non-paladin HUD classes
-- (hunter/warrior/druid/shaman). Structure mirrors the PALADIN sections above
-- (orders 8.x HUD, 9.x rotation): the same shared hud_*/rotation_label_* keys
-- from ST.class_defaults, the same widget types, ranges, selects and disablers.
-- Only the description copy, the glow-cue text and the per-slot toggles differ
-- per class. hud_enabled / rotation_label_enabled ship false in the shared
-- defaults, so nothing surfaces until enabled.
--
-- slot_toggles is an array of { key = "hud_show_<slot>", name = "...",
-- desc = "..." } mirroring the class's HUD_SLOTS keys/titles; hud_desc,
-- glow_desc and format_desc carry the class-specific copy.
local function hud_rotation_widgets(slot_toggles, hud_desc, glow_desc, format_desc)
    local widgets = {
        hud_header = {
            type = "header",
            order = 8.0,
            name = "Cooldown HUD",
        },
        hud_desc = {
            order = 8.01,
            type = "description",
            name = hud_desc,
        },
        hud_enabled = {
            type = "toggle",
            order = 8.1,
            name = "Enable Cooldown HUD",
            desc = "Show the cooldown HUD.",
            get = "getter",
            set = "setter",
        },
        hud_locked = {
            type = "toggle",
            order = 8.11,
            name = "Lock frame",
            desc = "Prevent dragging the HUD frame. While unlocked the HUD stays visible so it can be "..
                "positioned, with sample cooldowns running.",
            get = "getter",
            set = "setter",
        },
        hud_visibility_key = {
            type = "select",
            order = 8.12,
            name = "Show HUD",
            desc = "When the HUD is visible (Practice Mode always shows it).",
            values = { always = "Always", in_combat = "In combat", in_combat_or_target = "In combat or with an attackable target" },
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hud_enabled
            end,
        },
        hud_icon_size = {
            type = "range",
            order = 8.13,
            name = "Icon size",
            desc = "Size of each icon in pixels.",
            min = 16, max = 96, step = 1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.hud_match_bar_width and db.hud_orientation ~= "vertical"
            end,
        },
        hud_match_bar_width = {
            type = "toggle",
            order = 8.14,
            name = "Match bar width",
            desc = "Size the row to exactly the swing bar's width (outline included) and the icons to "..
                "fill it. Rows only.",
            get = "getter",
            set = "setter",
            disabled = function()
                return ST:get_class_table().hud_orientation == "vertical"
            end,
        },
        hud_spacing = {
            type = "range",
            order = 8.15,
            name = "Spacing",
            desc = "Gap between icons in pixels.",
            min = -10, max = 30, step = 1,
            get = "getter",
            set = "setter",
        },
        hud_orientation = {
            type = "select",
            order = 8.16,
            name = "Orientation",
            desc = "Lay the icons out in a row or a column.",
            values = { horizontal = "Row", vertical = "Column" },
            get = "getter",
            set = "setter",
        },
        hud_scale = {
            type = "range",
            order = 8.17,
            name = "Scale",
            desc = "Scale of the whole HUD row.",
            min = 0.5, max = 2.0, step = 0.05,
            get = "getter",
            set = "setter",
        },
        hud_x = {
            type = "input",
            order = 8.18,
            name = "X position",
            desc = "Horizontal screen position (dragging the unlocked frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().hud_x or 0)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().hud_x = n
                end
            end,
        },
        hud_y = {
            type = "input",
            order = 8.19,
            name = "Y position",
            desc = "Vertical screen position (dragging the unlocked frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().hud_y or -236)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().hud_y = n
                end
            end,
        },
        hud_style_header = {
            type = "header",
            order = 8.2,
            name = "Style",
        },
        hud_show_text = {
            type = "toggle",
            order = 8.21,
            name = "Remaining time text",
            desc = "Show the remaining time on each icon (one decimal under 3 seconds, turning red; the "..
                "global cooldown never carries text).",
            get = "getter",
            set = "setter",
        },
        hud_font = {
            type = "select",
            order = 8.22,
            name = "Text font",
            desc = "Font for the remaining time.",
            dialogControl = "LSM30_Font",
            values = LSM:HashTable("font"),
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hud_show_text
            end,
        },
        hud_text_size = {
            type = "range",
            order = 8.23,
            name = "Text size",
            desc = "Font size of the remaining time.",
            min = 8, max = 40, step = 1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hud_show_text
            end,
        },
        hud_text_outline = {
            type = "select",
            order = 8.24,
            name = "Text outline",
            desc = "Outline style of the remaining time.",
            values = ST.outlines,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hud_show_text
            end,
        },
        hud_text_color = {
            order = 8.25,
            type = "color",
            name = "Text color",
            desc = "Colour of the remaining time.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hud_show_text
            end,
        },
        hud_text_warn_color = {
            order = 8.26,
            type = "color",
            name = "Text color under 3 s",
            desc = "Colour of the remaining time in its last 3 seconds.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hud_show_text
            end,
        },
        hud_border_size = {
            type = "range",
            order = 8.27,
            name = "Border size",
            desc = "Border thickness around each icon (0 = none).",
            min = 0, max = 8, step = 1,
            get = "getter",
            set = "setter",
        },
        hud_border_color = {
            order = 8.28,
            type = "color",
            name = "Border color",
            desc = "Colour of the icon borders.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
        },
        hud_cues_header = {
            type = "header",
            order = 8.3,
            name = "Cues",
        },
        hud_glow_enabled = {
            type = "toggle",
            order = 8.31,
            name = "Glow when it's the right call",
            desc = glow_desc,
            get = "getter",
            set = "setter",
        },
        hud_desaturate = {
            type = "toggle",
            order = 8.32,
            name = "Grey out on cooldown",
            desc = "Desaturate icons while on cooldown.",
            get = "getter",
            set = "setter",
        },
        hud_mana_tint = {
            type = "toggle",
            order = 8.33,
            name = "Blue without mana",
            desc = "Tint an icon blue when you can't afford the ability.",
            get = "getter",
            set = "setter",
        },
        hud_range_tint = {
            type = "toggle",
            order = 8.34,
            name = "Red out of range",
            desc = "Tint an icon red when the target is out of the ability's range.",
            get = "getter",
            set = "setter",
        },
        hud_icons_header = {
            type = "header",
            order = 8.4,
            name = "Icons",
        },
        rotation_label_header = {
            type = "header",
            order = 9.0,
            name = "Rotation Text",
        },
        rotation_label_desc = {
            order = 9.01,
            type = "description",
            name = "A free-standing label with the rotation pattern recommended for the current weapon "..
                "speed and haste - the same rotation the Next Action Guide uses. Unlock the frame to drag "..
                "it into place; classes without a rotation source never show it.",
        },
        rotation_label_enabled = {
            type = "toggle",
            order = 9.1,
            name = "Show rotation text",
            desc = "Show the rotation label.",
            get = "getter",
            set = "setter",
        },
        rotation_label_locked = {
            type = "toggle",
            order = 9.11,
            name = "Lock frame",
            desc = "Prevent dragging the label. While unlocked the label stays visible so it can be positioned.",
            get = "getter",
            set = "setter",
        },
        rotation_label_visibility_key = {
            type = "select",
            order = 9.12,
            name = "Show text",
            desc = "When to show the label (Practice Mode always shows it).",
            values = { always = "Always show", in_combat = "In combat" },
            get = "getter",
            set = "setter",
            disabled = function()
                return not ST:get_class_table().rotation_label_enabled
            end,
        },
        rotation_label_format = {
            type = "select",
            order = 9.13,
            name = "Format",
            desc = format_desc,
            values = { key = "2/3", labelled = "Rotation: 2/3", steps = "CS, Twist, Twist", both = "2/3  -  CS, Twist, Twist" },
            get = "getter",
            set = "setter",
            disabled = function()
                return not ST:get_class_table().rotation_label_enabled
            end,
        },
        rotation_label_align = {
            type = "select",
            order = 9.14,
            name = "Alignment",
            desc = "Which edge of the label stays put when the text changes length. Left and right sit "..
                "flush against that edge of the label's box.",
            values = { left = "Left", center = "Center", right = "Right" },
            get = "getter",
            set = function(_, value)
                if st.rotation_text then
                    st.rotation_text.set_align(value)
                end
            end,
            disabled = function()
                return not ST:get_class_table().rotation_label_enabled
            end,
        },
        rotation_label_x = {
            type = "input",
            order = 9.15,
            name = "X position",
            desc = "Horizontal screen position of the label's anchor point (its left, centre or right "..
                "edge per Alignment). Dragging the unlocked label also updates this.",
            get = function()
                return tostring(ST:get_class_table().rotation_label_x or 0)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().rotation_label_x = n
                end
            end,
        },
        rotation_label_y = {
            type = "input",
            order = 9.16,
            name = "Y position",
            desc = "Vertical screen position (dragging the unlocked label also updates this).",
            get = function()
                return tostring(ST:get_class_table().rotation_label_y or -150)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().rotation_label_y = n
                end
            end,
        },
        rotation_label_scale = {
            type = "range",
            order = 9.17,
            name = "Scale",
            desc = "Scale of the whole label.",
            min = 0.5, max = 2.0, step = 0.05,
            get = "getter",
            set = "setter",
        },
        rotation_label_font = {
            type = "select",
            order = 9.21,
            name = "Font",
            desc = "Font of the label.",
            dialogControl = "LSM30_Font",
            values = LSM:HashTable("font"),
            get = "getter",
            set = "setter",
        },
        rotation_label_size = {
            type = "range",
            order = 9.22,
            name = "Text size",
            desc = "Font size of the label.",
            min = 8, max = 48, step = 1,
            get = "getter",
            set = "setter",
        },
        rotation_label_outline = {
            type = "select",
            order = 9.23,
            name = "Outline",
            desc = "Outline style of the label.",
            values = ST.outlines,
            get = "getter",
            set = "setter",
        },
        rotation_label_color = {
            order = 9.24,
            type = "color",
            name = "Color",
            desc = "Colour of the label.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
        },
    }
    for i = 1, #slot_toggles do
        local slot = slot_toggles[i]
        widgets[slot.key] = {
            type = "toggle",
            order = 8.41 + (i - 1) * 0.01,
            name = slot.name,
            desc = slot.desc,
            get = "getter",
            set = "setter",
        }
    end
    return widgets
end

function ST.class_opts_funcs.PALADIN(self)
    local opts_group = {
        -- class_header = {
        --     type = "header",
        --     order = 1.0,
        --     name = "Paladin Configuration",
        -- },
        seal_header = {
            type = "header",
            order = 1.01,
            name = "Seal Context Colors",
        },
        seal_desc = {
            type = "description",
            order = 1.1,
            name = "The timer bar can be configured to turn a custom color depending on the paladin's active seal.",
        },
        use_seal_colors = {
            type = "toggle",
            order = 1.11,
            name = "Enable",
            desc = "Enables custom colors for the mainhand bar based on active seal.",
            get = "getter",
            set = "setter",
        },
        soc_color = {
            order=1.12,
            type="color",
            name="Seal of Command",
            desc="Color to use when Seal of Command is active.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_seal_colors
            end,
        },
        sov_color = {
            order=1.13,
            type="color",
            name="Seal of Corruption/Vengeance",
            desc="Color to use when Seal of Corruption/Vengeance is active.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_seal_colors
            end,
        },
        sor_color = {
            order=1.14,
            type="color",
            name="Seal of Righteousness",
            desc="Color to use when Seal of Righteousness is active.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_seal_colors
            end,
        },
        sol_color = {
            order=1.15,
            type="color",
            name="Seal of Light",
            desc="Color to use when Seal of Light is active.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_seal_colors
            end,
        },
        sow_color = {
            order=1.16,
            type="color",
            name="Seal of Wisdom",
            desc="Color to use when Seal of Wisdom is active.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_seal_colors
            end,
        },
        soj_color = {
            order=1.17,
            type="color",
            name="Seal of Justice",
            desc="Color to use when Seal of Justice is active.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_seal_colors
            end,
        },
        sob_color = {
            order=1.18,
            type="color",
            name="Seal of Blood/Martyr",
            desc="Color to use when Seal of Blood/Martyr is active.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_seal_colors
            end,
        },
        sotc_color = {
            order=1.19,
            type="color",
            name="Seal of the Crusader",
            desc="Color to use when Seal of the Crusader is active.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_seal_colors
            end,
        },
        aow_header = {
            type = "header",
            order = 2.0,
            name = "Art of War Procs",
        },
        aow_desc = {
            type = "description",
            order = 2.1,
            name = "The timer bar can be configured to glow when the Paladin has Art of War.",
        },
        use_aow_glow = {
            type = "toggle",
            order = 2.2,
            name = "Enable",
            desc = "Enables a glow color when the Paladin has Art of War",
            get = "getter",
            set = "setter",
        },
        require_exo_ready = {
            type = "toggle",
            order = 2.21,
            name = "Require Exorcism Ready",
            desc = "If set, the glow effect will only happen when Exorcism is off cooldown.",
            get = "getter",
            set = "setter",
        },
        aow_glow_color = {
            order=2.3,
            type="color",
            name="Color",
            desc="Glow color to use when the Paladin has an Art of War proc.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_aow_glow
            end,
        },
        aow_glow_nlines = {
            type = "range",
            order = 2.4,
            name = "Number of glow lines",
            desc = "The number of lines to use in the glow effect.",
            min = 1, max = 200,
            step = 1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_aow_glow
            end,
        },
        aow_glow_freq = {
            type = "range",
            order = 2.5,
            name = "Glow frequency",
            desc = "The rotation frequency of the glow effect.",
            min = 0.01, max = 1.0, step = 0.01,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_aow_glow
            end,
        },
        aow_glow_line_length = {
            type = "range",
            order = 2.6,
            name = "Glow line length",
            desc = "The glow line length.",
            min = 1, max = 30, step = 1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_aow_glow
            end,
        },
        twist_header = {
            type = "header",
            order = 3.0,
            name = "Seal Twisting",
        },
        twist_desc = {
            order = 3.05,
            type = "description",
            name = "The twist window band marks the final ~0.4 s of each swing. The band's color shows when a "..
                "twist is armed or impossible, and feedback appears when a twist attempt lands.",
        },
        twist_enabled = {
            type = "toggle",
            order = 3.1,
            name = "Enable twist helpers",
            desc = "Master toggle for the twist window band and twist attempt feedback.",
            get = "getter",
            set = "setter",
        },
        twist_marker_enabled = {
            type = "toggle",
            order = 3.2,
            name = "Twist window band",
            desc = "Shows a band over the final part of each swing where a seal twist can land.",
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.twist_enabled
            end,
        },
        twist_marker_color = {
            order=3.3,
            type="color",
            name="Band color",
            desc="Color to use for the twist window band while a twist can still land.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not (db.twist_enabled and db.twist_marker_enabled)
            end,
        },
        twist_feedback_enabled = {
            type = "toggle",
            order = 3.4,
            name = "Twist attempt feedback",
            desc = "Shows attempt feedback on the timer bar, and the success text when that is enabled.",
            get = "getter",
            set = "setter",
        },
        twist_color_twisting = {
            order=3.5,
            type="color",
            name="Armed / attempted color",
            desc="Color to use when a seal twist is armed or attempted.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },
        twist_color_cant = {
            order=3.6,
            type="color",
            name="'Can't twist' warning color",
            desc="Color to use when a twist cannot land within the current swing.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },
        twist_success_text_enabled = {
            type = "toggle",
            order = 3.7,
            name = "Success text",
            desc = "Shows floating text when a seal twist lands successfully.",
            get = "getter",
            set = "setter",
        },
        twist_success_text_color = {
            order=3.8,
            type="color",
            name="Success text color",
            desc="Color to use for the twist success text.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.twist_success_text_enabled
            end,
        },
        twist_success_text_size = {
            type = "range",
            order = 3.9,
            name = "Success text size",
            desc = "The font size of the twist success text.",
            min = 12, max = 48, step = 1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.twist_success_text_enabled
            end,
        },
        twist_success_text_duration = {
            type = "range",
            order = 3.95,
            name = "Success text duration (s)",
            desc = "How long the twist success text stays on screen, in seconds.",
            min = 0.5, max = 5, step = 0.1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.twist_success_text_enabled
            end,
        },
        twist_success_glow_enabled = {
            type = "toggle",
            order = 3.96,
            name = "Twist success glow",
            desc = "Shows a LibCustomGlow Pixel glow on the bar when a twist attempt lands.",
            get = "getter",
            set = "setter",
        },
        twist_success_glow_color = {
            order = 3.97,
            type = "color",
            name = "Success glow color",
            desc = "Color of the twist attempt glow.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.twist_success_glow_enabled
            end,
        },
        twist_success_glow_duration = {
            type = "range",
            order = 3.98,
            name = "Success glow duration (s)",
            desc = "How long the twist attempt glow stays on screen, in seconds.",
            min = 0.2, max = 2, step = 0.1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.twist_success_glow_enabled
            end,
        },
        judgement_marker_enabled = {
            type = "toggle",
            order = 3.985,
            name = "Judgement marker",
            desc = "Shows a line on the swing bar where Judgement comes off cooldown (only with a seal worth judging).",
            get = "getter",
            set = "setter",
        },
        seal_icons_enabled = {
            type = "toggle",
            order = 3.99,
            name = "Seal icons",
            desc = "Shows standalone Seal of Command / Seal of Blood icons with cooldown swipe and timer text.",
            get = "getter",
            set = "setter",
        },
        lag_header = {
            type = "header",
            order = 4.0,
            name = "Lag Compensation",
        },
        lag_desc = {
            order = 4.05,
            type = "description",
            name = "The global cooldown and latency can make a correct twist fail. Raising these values makes "..
                "the 'can't twist' warning fire earlier.",
        },
        lag_detection_enabled = {
            type = "toggle",
            order = 4.1,
            name = "Warn on impossible twists",
            desc = "Enables the warning color when a twist cannot land within the current swing.",
            get = "getter",
            set = "setter",
        },
        lag_multiplier = {
            type = "range",
            order = 4.2,
            name = "Latency multiplier",
            desc = "The player's world latency is multiplied by this value in the lag detection calibration.",
            min = 1.0, max = 3.0, step = 0.1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.lag_detection_enabled
            end,
        },
        lag_offset = {
            type = "range",
            order = 4.3,
            name = "Latency offset (ms)",
            desc = "Added to the player's world latency in the lag detection calibration.",
            min = 0, max = 200, step = 1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.lag_detection_enabled
            end,
        },
        twist_padding_mode = {
            type = "select",
            order = 4.4,
            name = "Window padding mode",
            desc = "Whether to push the twist window back from the end of the swing to account for input and "..
                "latency. Dynamic uses the lag calibration values above; Fixed uses the offset below.",
            values = {None="None", Fixed="Fixed", Dynamic="Dynamic"},
            get = "getter",
            set = "setter",
        },
        twist_window_padding_ms = {
            type = "range",
            order = 4.5,
            name = "Fixed padding (ms)",
            desc = "The twist window is pushed this far back from the end of the swing.",
            min = 0, max = 400, step = 1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.twist_padding_mode ~= "Fixed"
            end,
        },
        nag_header = {
            type = "header",
            order = 5.0,
            name = "Next Action Guide",
        },
        nag_desc = {
            type = "description",
            order = 5.05,
            name = "On-screen rotation prompt: the next ability to press (Crusader Strike, Command, "..
                "Blood, twist) with HOLD/RIDE and Judgement cues. Drag the frame while it is unlocked to position it.",
        },
        nextaction_enabled = {
            type = "toggle",
            order = 5.1,
            name = "Enable",
            desc = "Show the next action guide.",
            get = "getter",
            set = "setter",
        },
        nextaction_locked = {
            type = "toggle",
            order = 5.11,
            name = "Lock frame",
            desc = "Prevent dragging the guide frame.",
            get = "getter",
            set = "setter",
        },
        nextaction_visibility_key = {
            type = "select",
            order = 5.12,
            name = "Show guide",
            desc = "When the guide is visible.",
            values = { always = "Always", in_combat = "In combat" },
            get = "getter",
            set = "setter",
        },
        nextaction_icon_size = {
            type = "range",
            order = 5.13,
            name = "Icon size",
            desc = "Guide icon size in pixels.",
            min = 20, max = 80, step = 1,
            get = "getter",
            set = "setter",
        },
        nextaction_x = {
            type = "input",
            order = 5.14,
            name = "X position",
            desc = "Horizontal screen position (dragging the frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().nextaction_x or 0)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().nextaction_x = n
                end
            end,
        },
        nextaction_y = {
            type = "input",
            order = 5.15,
            name = "Y position",
            desc = "Vertical screen position (dragging the frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().nextaction_y or -180)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().nextaction_y = n
                end
            end,
        },
        nextaction_reaction_time_ms = {
            type = "range",
            order = 5.2,
            name = "Reaction time (ms)",
            desc = "Assumed player reaction time used by the guide's timing model.",
            min = 0, max = 350, step = 10,
            get = "getter",
            set = "setter",
        },
        nextaction_cs_max_delay_ms = {
            type = "range",
            order = 5.21,
            name = "Crusader Strike max delay (ms)",
            desc = "How late Crusader Strike may be suggested over a twist.",
            min = 0, max = 3000, step = 50,
            get = "getter",
            set = "setter",
        },
        nextaction_hold_enabled = {
            type = "toggle",
            order = 5.22,
            name = "Show HOLD/RIDE overlay",
            desc = "Show the HOLD/RIDE circle on the guide.",
            get = "getter",
            set = "setter",
        },
        nextaction_show_rotation_text = {
            type = "toggle",
            order = 5.23,
            name = "Show rotation text",
            desc = "Show the recommended rotation pattern under the guide.",
            get = "getter",
            set = "setter",
        },
        nextaction_show_label = {
            type = "toggle",
            order = 5.24,
            name = "Show \"Next action:\" label",
            desc = "Show the small frame label.",
            get = "getter",
            set = "setter",
        },
        nextaction_show_judgement = {
            type = "toggle",
            order = 5.25,
            name = "Show Judgement cue",
            desc = "Show the Judgement cue icon when it is time to judge.",
            get = "getter",
            set = "setter",
        },
        nextaction_show_fillers = {
            type = "toggle",
            order = 5.26,
            name = "Show filler suggestions",
            desc = "Show Consecration/Exorcism filler suggestions.",
            get = "getter",
            set = "setter",
        },
        nextaction_filler_mana_consecration = {
            type = "range",
            order = 5.3,
            name = "Consecration mana threshold (%)",
            desc = "Suggest Consecration only above this mana percentage.",
            min = 0, max = 100, step = 1,
            get = "getter",
            set = "setter",
        },
        nextaction_filler_mana_exorcism = {
            type = "range",
            order = 5.31,
            name = "Exorcism mana threshold (%)",
            desc = "Suggest Exorcism only above this mana percentage.",
            min = 0, max = 100, step = 1,
            get = "getter",
            set = "setter",
        },
        twist_sounds_header = {
            type = "header",
            order = 6.0,
            name = "Twist Sounds",
        },
        twist_sounds_desc = {
            order = 6.05,
            type = "description",
            name = "Optional sound cues for seal twisting: one when the twist window opens, and one when a "..
                "twist attempt lands. All sounds are off by default.",
        },
        twist_sound_enabled = {
            type = "toggle",
            order = 6.1,
            name = "Window sound",
            desc = "Play a sound when the swing enters the twist window.",
            get = "getter",
            set = "setter",
        },
        twist_sound_choice = {
            type = "select",
            order = 6.2,
            name = "Window sound effect",
            desc = "Which sound to play when the twist window opens. Hover a sound in the list to preview it.",
            dialogControl = "Dropdown-SoundPreview",
            values = twist_sound_options,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.twist_sound_enabled
            end,
        },
        twist_success_sound_enabled = {
            type = "toggle",
            order = 6.3,
            name = "Twist attempt sound",
            desc = "Play a sound when a twist attempt lands (two seals active on the swing).",
            get = "getter",
            set = "setter",
        },
        twist_success_sound_choice = {
            type = "select",
            order = 6.4,
            name = "Twist attempt sound effect",
            desc = "Which sound to play when a twist attempt lands. Hover a sound in the list to preview it.",
            dialogControl = "Dropdown-SoundPreview",
            values = twist_sound_options,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.twist_success_sound_enabled
            end,
        },
        sound_channel = {
            type = "select",
            order = 6.5,
            name = "Sound channel",
            desc = "Audio channel for the twist sounds. Master bypasses SFX mute.",
            values = {Master="Master", SFX="SFX", Music="Music", Ambience="Ambience"},
            get = "getter",
            set = "setter",
        },
        practice_header = {
            type = "header",
            order = 7.0,
            name = "Twist Practice",
        },
        practice_desc = {
            order = 7.05,
            type = "description",
            name = "Practice minigame: simulate a boss fight's swing rotation and seal twisting in a "..
                "separate simulation, without attacking anything. The panel's ability icons cast "..
                "simulated spells (left click); /st practice toggles the session. The full practice "..
                "options (rotation lock, haste buttons, keybinds) are still in development.",
        },
        practice_toggle = {
            type = "execute",
            order = 7.1,
            name = function()
                if st.practice_ui and st.practice_ui.is_active() then
                    return "Stop Practice"
                end
                return "Start Practice"
            end,
            desc = "Toggle the practice session. A session can only be started out of combat.",
            func = function()
                if st.practice_ui then
                    st.practice_ui.toggle(ST)
                end
            end,
        },
        practice_weapon_speed = {
            type = "range",
            order = 7.2,
            name = "Weapon speed override (s)",
            desc = "0 uses the equipped weapon speed.",
            min = 0, max = 4, step = 0.1,
            get = "getter",
            set = "setter",
        },
        -- Practice result feedback and panel placement. Every widget edits the archived
        -- practice_result_* / practice_panel_* keys above the session UI (practice_ui.lua)
        -- already reads, so the shipped defaults and the options round-trip in both
        -- directions. The two result colours are stored in the 0-1 range the result popup
        -- paints with (SetTextColor), NOT the shared 0-255 convention, so they use direct
        -- get/set functions instead of the class color_getter/color_setter.
        practice_result_duration = {
            type = "range",
            order = 7.3,
            name = "Result text duration (s)",
            desc = "How long the TWIST!/MISS popup stays on screen.",
            min = 0.3, max = 3.0, step = 0.1,
            get = "getter",
            set = "setter",
        },
        practice_result_text_size = {
            type = "range",
            order = 7.31,
            name = "Result text size",
            desc = "Font size of the TWIST!/MISS popup.",
            min = 12, max = 48, step = 1,
            get = "getter",
            set = function(_, value)
                ST:get_class_table().practice_result_text_size = value
                if st.practice_ui then
                    st.practice_ui.update_result_font(ST)
                end
            end,
        },
        practice_result_color_hit = {
            order = 7.32,
            type = "color",
            name = "Twist text color",
            desc = "Colour of the TWIST! popup on a successful twist.",
            hasAlpha = false,
            get = function()
                local c = ST:get_class_table().practice_result_color_hit or {0, 1, 0, 1}
                return c[1], c[2], c[3], c[4] or 1
            end,
            set = function(_, r, g, b, a)
                ST:get_class_table().practice_result_color_hit = {r, g, b, a}
            end,
        },
        practice_result_color_miss = {
            order = 7.33,
            type = "color",
            name = "Miss text color",
            desc = "Colour of the MISS popup on a failed twist.",
            hasAlpha = false,
            get = function()
                local c = ST:get_class_table().practice_result_color_miss or {1, 0.2, 0.2, 1}
                return c[1], c[2], c[3], c[4] or 1
            end,
            set = function(_, r, g, b, a)
                ST:get_class_table().practice_result_color_miss = {r, g, b, a}
            end,
        },
        practice_panel_x = {
            type = "input",
            order = 7.34,
            name = "Panel X position",
            desc = "Horizontal offset of the practice panel from its anchor (dragging the panel also updates this).",
            get = function()
                return tostring(ST:get_class_table().practice_panel_x or 0)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().practice_panel_x = n
                end
            end,
        },
        practice_panel_y = {
            type = "input",
            order = 7.35,
            name = "Panel Y position",
            desc = "Vertical offset of the practice panel from its anchor (dragging the panel also updates this).",
            get = function()
                return tostring(ST:get_class_table().practice_panel_y or 0)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().practice_panel_y = n
                end
            end,
        },
        practice_reset_position = {
            type = "execute",
            order = 7.36,
            name = "Reset panel position",
            desc = "Move the practice panel back to its default spot beside the swing bar.",
            func = function()
                local db = ST:get_class_table()
                db.practice_panel_x = 0
                db.practice_panel_y = 0
            end,
        },

        -- Cooldown HUD (hud.lua). The shared hud_* keys live in ST.class_defaults and
        -- the paladin slot toggles in ST.PALADIN.defaults; this section edits them
        -- through the class getter/setter, and hud.lua picks changes up on its next
        -- tick. Other classes plug in by adding the same shared-looking widgets plus
        -- their own hud_show_<slot key> toggles to their own options section (their
        -- descriptors and provider live in their own class module).
        hud_header = {
            type = "header",
            order = 8.0,
            name = "Cooldown HUD",
        },
        hud_desc = {
            order = 8.01,
            type = "description",
            name = "A row of ability icons with cooldown swipes and remaining-time text. Icons grey out "..
                "while on cooldown (Judgement also without a seal, Exorcism without an Undead or Demon "..
                "target), tint blue without mana and red out of range, and Exorcism and Avenging Wrath "..
                "glow when they are the right call. Unlock the frame to drag it into place.",
        },
        hud_enabled = {
            type = "toggle",
            order = 8.1,
            name = "Enable Cooldown HUD",
            desc = "Show the cooldown HUD.",
            get = "getter",
            set = "setter",
        },
        hud_locked = {
            type = "toggle",
            order = 8.11,
            name = "Lock frame",
            desc = "Prevent dragging the HUD frame. While unlocked the HUD stays visible so it can be "..
                "positioned, with sample cooldowns running.",
            get = "getter",
            set = "setter",
        },
        hud_visibility_key = {
            type = "select",
            order = 8.12,
            name = "Show HUD",
            desc = "When the HUD is visible (Practice Mode always shows it).",
            values = { always = "Always", in_combat = "In combat", in_combat_or_target = "In combat or with an attackable target" },
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hud_enabled
            end,
        },
        hud_icon_size = {
            type = "range",
            order = 8.13,
            name = "Icon size",
            desc = "Size of each icon in pixels.",
            min = 16, max = 96, step = 1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.hud_match_bar_width and db.hud_orientation ~= "vertical"
            end,
        },
        hud_match_bar_width = {
            type = "toggle",
            order = 8.14,
            name = "Match bar width",
            desc = "Size the row to exactly the swing bar's width (outline included) and the icons to "..
                "fill it. Rows only.",
            get = "getter",
            set = "setter",
            disabled = function()
                return ST:get_class_table().hud_orientation == "vertical"
            end,
        },
        hud_spacing = {
            type = "range",
            order = 8.15,
            name = "Spacing",
            desc = "Gap between icons in pixels.",
            min = -10, max = 30, step = 1,
            get = "getter",
            set = "setter",
        },
        hud_orientation = {
            type = "select",
            order = 8.16,
            name = "Orientation",
            desc = "Lay the icons out in a row or a column.",
            values = { horizontal = "Row", vertical = "Column" },
            get = "getter",
            set = "setter",
        },
        hud_scale = {
            type = "range",
            order = 8.17,
            name = "Scale",
            desc = "Scale of the whole HUD row.",
            min = 0.5, max = 2.0, step = 0.05,
            get = "getter",
            set = "setter",
        },
        hud_x = {
            type = "input",
            order = 8.18,
            name = "X position",
            desc = "Horizontal screen position (dragging the unlocked frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().hud_x or 0)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().hud_x = n
                end
            end,
        },
        hud_y = {
            type = "input",
            order = 8.19,
            name = "Y position",
            desc = "Vertical screen position (dragging the unlocked frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().hud_y or -236)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().hud_y = n
                end
            end,
        },
        hud_style_header = {
            type = "header",
            order = 8.2,
            name = "Style",
        },
        hud_show_text = {
            type = "toggle",
            order = 8.21,
            name = "Remaining time text",
            desc = "Show the remaining time on each icon (one decimal under 3 seconds, turning red; the "..
                "global cooldown never carries text).",
            get = "getter",
            set = "setter",
        },
        hud_font = {
            type = "select",
            order = 8.22,
            name = "Text font",
            desc = "Font for the remaining time.",
            dialogControl = "LSM30_Font",
            values = LSM:HashTable("font"),
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hud_show_text
            end,
        },
        hud_text_size = {
            type = "range",
            order = 8.23,
            name = "Text size",
            desc = "Font size of the remaining time.",
            min = 8, max = 40, step = 1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hud_show_text
            end,
        },
        hud_text_outline = {
            type = "select",
            order = 8.24,
            name = "Text outline",
            desc = "Outline style of the remaining time.",
            values = ST.outlines,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hud_show_text
            end,
        },
        hud_text_color = {
            order = 8.25,
            type = "color",
            name = "Text color",
            desc = "Colour of the remaining time.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hud_show_text
            end,
        },
        hud_text_warn_color = {
            order = 8.26,
            type = "color",
            name = "Text color under 3 s",
            desc = "Colour of the remaining time in its last 3 seconds.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hud_show_text
            end,
        },
        hud_border_size = {
            type = "range",
            order = 8.27,
            name = "Border size",
            desc = "Border thickness around each icon (0 = none).",
            min = 0, max = 8, step = 1,
            get = "getter",
            set = "setter",
        },
        hud_border_color = {
            order = 8.28,
            type = "color",
            name = "Border color",
            desc = "Colour of the icon borders.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
        },
        hud_cues_header = {
            type = "header",
            order = 8.3,
            name = "Cues",
        },
        hud_glow_enabled = {
            type = "toggle",
            order = 8.31,
            name = "Glow when it's the right call",
            desc = "Exorcism glows against an Undead or Demon target and Avenging Wrath once it is ready, "..
                "both in combat and off cooldown. No other icon glows.",
            get = "getter",
            set = "setter",
        },
        hud_desaturate = {
            type = "toggle",
            order = 8.32,
            name = "Grey out on cooldown",
            desc = "Desaturate icons while on cooldown (Judgement also without a seal, Exorcism without "..
                "a valid target).",
            get = "getter",
            set = "setter",
        },
        hud_mana_tint = {
            type = "toggle",
            order = 8.33,
            name = "Blue without mana",
            desc = "Tint an icon blue when you can't afford the ability.",
            get = "getter",
            set = "setter",
        },
        hud_range_tint = {
            type = "toggle",
            order = 8.34,
            name = "Red out of range",
            desc = "Tint an icon red when the target is out of the ability's range.",
            get = "getter",
            set = "setter",
        },
        hud_icons_header = {
            type = "header",
            order = 8.4,
            name = "Icons",
        },
        hud_show_cs = {
            type = "toggle",
            order = 8.41,
            name = "Crusader Strike",
            desc = "Show the Crusader Strike icon (with its GCD swipe).",
            get = "getter",
            set = "setter",
        },
        hud_show_judgement = {
            type = "toggle",
            order = 8.42,
            name = "Judgement",
            desc = "Show the Judgement icon.",
            get = "getter",
            set = "setter",
        },
        hud_show_consecration = {
            type = "toggle",
            order = 8.43,
            name = "Consecration",
            desc = "Show the Consecration icon (with its GCD swipe).",
            get = "getter",
            set = "setter",
        },
        hud_show_exorcism = {
            type = "toggle",
            order = 8.44,
            name = "Exorcism",
            desc = "Show the Exorcism icon (with its GCD swipe).",
            get = "getter",
            set = "setter",
        },
        hud_show_trinket1 = {
            type = "toggle",
            order = 8.45,
            name = "Trinket 1",
            desc = "Show the top trinket slot (hidden while the slot is empty).",
            get = "getter",
            set = "setter",
        },
        hud_show_trinket2 = {
            type = "toggle",
            order = 8.46,
            name = "Trinket 2",
            desc = "Show the bottom trinket slot (hidden while the slot is empty).",
            get = "getter",
            set = "setter",
        },
        hud_show_wings = {
            type = "toggle",
            order = 8.47,
            name = "Avenging Wrath",
            desc = "Show the Avenging Wrath icon (glows in combat once it is ready).",
            get = "getter",
            set = "setter",
        },

        -- Rotation label (rotationtext.lua). The shared rotation_label_* keys live in
        -- ST.class_defaults; the label reads them through the class getter/setter and
        -- picks every change up on its own tick (a HUD-style layout poll). Only classes
        -- whose module provides get_rotation_key show the label; a class without one
        -- never creates it. Alignment goes through the label's own set_align, which
        -- moves the stored offset so the label does not jump when the anchor changes.
        rotation_label_header = {
            type = "header",
            order = 9.0,
            name = "Rotation Text",
        },
        rotation_label_desc = {
            order = 9.01,
            type = "description",
            name = "A free-standing label with the rotation pattern recommended for the current weapon "..
                "speed and haste - the same rotation the Next Action Guide uses. Unlock the frame to drag "..
                "it into place; classes without a rotation source never show it.",
        },
        rotation_label_enabled = {
            type = "toggle",
            order = 9.1,
            name = "Show rotation text",
            desc = "Show the rotation label.",
            get = "getter",
            set = "setter",
        },
        rotation_label_locked = {
            type = "toggle",
            order = 9.11,
            name = "Lock frame",
            desc = "Prevent dragging the label. While unlocked the label stays visible so it can be positioned.",
            get = "getter",
            set = "setter",
        },
        rotation_label_visibility_key = {
            type = "select",
            order = 9.12,
            name = "Show text",
            desc = "When to show the label (Practice Mode always shows it).",
            values = { always = "Always show", in_combat = "In combat" },
            get = "getter",
            set = "setter",
            disabled = function()
                return not ST:get_class_table().rotation_label_enabled
            end,
        },
        rotation_label_format = {
            type = "select",
            order = 9.13,
            name = "Format",
            desc = "What the label says: the rotation alone (2/3), with a prefix (Rotation: 2/3), "..
                "its steps (CS, Twist, Twist), or both.",
            values = { key = "2/3", labelled = "Rotation: 2/3", steps = "CS, Twist, Twist", both = "2/3  -  CS, Twist, Twist" },
            get = "getter",
            set = "setter",
            disabled = function()
                return not ST:get_class_table().rotation_label_enabled
            end,
        },
        rotation_label_align = {
            type = "select",
            order = 9.14,
            name = "Alignment",
            desc = "Which edge of the label stays put when the text changes length. Left and right sit "..
                "flush against that edge of the label's box.",
            values = { left = "Left", center = "Center", right = "Right" },
            get = "getter",
            set = function(_, value)
                if st.rotation_text then
                    st.rotation_text.set_align(value)
                end
            end,
            disabled = function()
                return not ST:get_class_table().rotation_label_enabled
            end,
        },
        rotation_label_x = {
            type = "input",
            order = 9.15,
            name = "X position",
            desc = "Horizontal screen position of the label's anchor point (its left, centre or right "..
                "edge per Alignment). Dragging the unlocked label also updates this.",
            get = function()
                return tostring(ST:get_class_table().rotation_label_x or 0)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().rotation_label_x = n
                end
            end,
        },
        rotation_label_y = {
            type = "input",
            order = 9.16,
            name = "Y position",
            desc = "Vertical screen position (dragging the unlocked label also updates this).",
            get = function()
                return tostring(ST:get_class_table().rotation_label_y or -150)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().rotation_label_y = n
                end
            end,
        },
        rotation_label_scale = {
            type = "range",
            order = 9.17,
            name = "Scale",
            desc = "Scale of the whole label.",
            min = 0.5, max = 2.0, step = 0.05,
            get = "getter",
            set = "setter",
        },
        rotation_label_font = {
            type = "select",
            order = 9.21,
            name = "Font",
            desc = "Font of the label.",
            dialogControl = "LSM30_Font",
            values = LSM:HashTable("font"),
            get = "getter",
            set = "setter",
        },
        rotation_label_size = {
            type = "range",
            order = 9.22,
            name = "Text size",
            desc = "Font size of the label.",
            min = 8, max = 48, step = 1,
            get = "getter",
            set = "setter",
        },
        rotation_label_outline = {
            type = "select",
            order = 9.23,
            name = "Outline",
            desc = "Outline style of the label.",
            values = ST.outlines,
            get = "getter",
            set = "setter",
        },
        rotation_label_color = {
            order = 9.24,
            type = "color",
            name = "Color",
            desc = "Colour of the label.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
        },
    }
    return opts_group
end

function ST.class_opts_funcs.WARRIOR(self)
    local opts_group = {
        tank_vid_header = {
            type = "header",
            order = 0.8,
            name = "Spec-dependent enable/disable"
        },
        hide_in_tank_spec = {
            type = "toggle",
            order = 0.81,
            name = "Hide when Protection",
            desc = "When enabled, the timer will hide when the Warrior is in Protection spec ("..
            "activated when Improved Defensive Stance is talented).",
            get = "getter",
            set = "setter",
        },
        hide_in_arms_spec = {
            type = "toggle",
            order = 0.82,
            name = "Hide when Arms",
            desc = "When enabled, the timer will hide when the Warrior is in Arms spec ("..
            "activated when Bladestorm is talented).",
            get = "getter",
            set = "setter",
        },
        class_header = {
            type = "header",
            order = 1.0,
            name = "On-next-attack Configuration",
        },
        queue_desc = {
            order = 1.02,
            type = "description",
            name = "The mainhand timer bar can be configured to turn a custom color when an on-next-attack ability is queued."
        },
        lb0 = {
            type = "header",
            order = 1.03,
            name = "",
        },
        enable_hs_color = {
            type = "toggle",
            order = 1.1,
            name = "Enable Heroic Strike",
            desc = "Enables a custom color for the mainhand bar when Heroic Strike is queued.",
            get = "getter",
            set = "setter",
        },
        hs_color = {
            order=1.2,
            type="color",
            name="Color",
            desc="Color to use when Heroic Strike is queued.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.enable_hs_color
            end,
        },
        enable_cleave_color = {
            type = "toggle",
            order = 1.3,
            name = "Enable Cleave",
            desc = "Enables a custom color for the mainhand bar when Cleave is queued.",
            get = "getter",
            set = "setter",
        },
        cleave_color = {
            order=1.4,
            type="color",
            name="Color",
            desc="Color to use when Cleave is queued.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.enable_cleave_color
            end,
        },
        lb1 = {
            type = "header",
            order = 1.45,
            name = "",
        },
        rage_desc = {
            order = 1.5,
            type = "description",
            name = "If either of the above are enabled, the mainhand timer bar will turn a certain color when the player "..
                "has queued an on-next-attack ability, but has since dropped below the rage threshold necessary "..
                "to use the ability."
        },
        lb2 = {
            type = "header",
            order = 1.55,
            name = "",
        },
        insufficient_rage_color = {
            order=1.6,
            type="color",
            name="Insufficient Rage color",
            desc="Color to use when the player drops below the rage threshold for the queued ability.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },
        header3 = {
            order = 2.0,
            type = "header",
            name = "Bloodsurge Glow"
        },
        desc3 = {
            order = 2.1,
            type = "description",
            name = "The mainhand timer can be configured to have a glow effect when the"..
            " player gets a Bloodsurge instant slam proc."
        },
        use_bloodsurge_glow = {
            type = "toggle",
            order = 2.2,
            name = "Enable",
            desc = "Enables a glow color when the Warrior has Bloodsurge",
            get = "getter",
            set = "setter",
        },
        bloodsurge_glow_color = {
            order=2.3,
            type="color",
            name="Color",
            desc="Glow color to use.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_bloodsurge_glow
            end,
        },
        bloodsurge_glow_nlines = {
            type = "range",
            order = 2.4,
            name = "Number of glow lines",
            desc = "The number of lines to use in the glow effect.",
            min = 1, max = 200,
            step = 1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_bloodsurge_glow
            end,
        },
        bloodsurge_glow_freq = {
            type = "range",
            order = 2.5,
            name = "Glow frequency",
            desc = "The rotation frequency of the glow effect.",
            min = 0.01, max = 1.0, step = 0.01,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_bloodsurge_glow
            end,
        },
        bloodsurge_glow_line_length = {
            type = "range",
            order = 2.6,
            name = "Glow line length",
            desc = "The glow line length.",
            min = 1, max = 30, step = 1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.use_bloodsurge_glow
            end,
        },
        -- Warrior trackers (reference SuperSwingTimer_ClassMods.lua warrior block
        -- 1689-3333): the Shield Block bar, the Slam cast bar, the Overpower proc flash
        -- and the Deep Wounds / Sunder Armor / Rend / Thunder Clap / Demo Shout target
        -- debuff bars.
        trackers_header = {
            type = "header",
            order = 3.0,
            name = "Warrior Trackers",
        },
        trackers_desc = {
            order = 3.01,
            type = "description",
            name = "Timing helpers above the mainhand bar: your Shield Block duration, the "..
                "Slam cast in progress, a pulsing Overpower proc cue, and your own Deep "..
                "Wounds / Sunder Armor / Rend / Thunder Clap / Demo Shout debuffs on the "..
                "current target.",
        },
        show_warrior_deep_wounds_bar = {
            type = "toggle",
            order = 3.1,
            name = "Deep Wounds bar",
            desc = "Show your own Deep Wounds bleed duration on the current target above "..
                "the mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        warrior_deep_wounds_bar_color = {
            order=3.2,
            type="color",
            name="Deep Wounds color",
            desc="Color of the Deep Wounds duration bar.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.show_warrior_deep_wounds_bar == false
            end,
        },
        show_warrior_sunder_armor_bar = {
            type = "toggle",
            order = 3.3,
            name = "Sunder Armor bar",
            desc = "Show your own Sunder Armor duration and stack count (1-5) on the "..
                "current target above the mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        warrior_sunder_armor_bar_color = {
            order=3.4,
            type="color",
            name="Sunder Armor color",
            desc="Color of the Sunder Armor duration bar.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.show_warrior_sunder_armor_bar == false
            end,
        },
        show_warrior_rend_bar = {
            type = "toggle",
            order = 3.5,
            name = "Rend bar",
            desc = "Show your own Rend duration on the current target above the mainhand "..
                "bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        warrior_rend_bar_color = {
            order=3.6,
            type="color",
            name="Rend color",
            desc="Color of the Rend duration bar.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.show_warrior_rend_bar == false
            end,
        },
        show_warrior_thunder_clap_bar = {
            type = "toggle",
            order = 3.7,
            name = "Thunder Clap bar",
            desc = "Show your own Thunder Clap duration on the current target above the "..
                "mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        warrior_thunder_clap_bar_color = {
            order=3.8,
            type="color",
            name="Thunder Clap color",
            desc="Color of the Thunder Clap duration bar.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.show_warrior_thunder_clap_bar == false
            end,
        },
        show_warrior_demo_shout_bar = {
            type = "toggle",
            order = 3.9,
            name = "Demo Shout bar",
            desc = "Show your own Demoralizing (Demolition) Shout duration on the current "..
                "target above the mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        warrior_demo_shout_bar_color = {
            order=3.10,
            type="color",
            name="Demo Shout color",
            desc="Color of the Demoralizing Shout duration bar.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.show_warrior_demo_shout_bar == false
            end,
        },
        show_warrior_shield_block_bar = {
            type = "toggle",
            order = 3.11,
            name = "Shield Block bar",
            desc = "Show a 4 px Shield Block duration bar with its icon above the "..
                "mainhand bar while the buff is active.",
            get = "getter",
            set = "setter",
        },
        warrior_shield_block_bar_color = {
            order=3.12,
            type="color",
            name="Shield Block color",
            desc="Color of the Shield Block duration bar.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.show_warrior_shield_block_bar == false
            end,
        },
        show_warrior_slam_cast_bar = {
            type = "toggle",
            order = 3.13,
            name = "Slam cast bar",
            desc = "Show a small Slam cast-progress bar above the mainhand bar while "..
                "casting Slam.",
            get = "getter",
            set = "setter",
        },
        show_warrior_overpower_flash = {
            type = "toggle",
            order = 3.14,
            name = "Overpower proc flash",
            desc = "Pulse a gold border and an OP marker around the mainhand bar while "..
                "an Overpower proc window is open (armed when your attack is dodged).",
            get = "getter",
            set = "setter",
        },
        show_warrior_rampage_badge = {
            type = "toggle",
            order = 3.15,
            name = "Rampage badge",
            desc = "Show the Rampage stack count and refresh window beside the mainhand "..
                "bar while the buff is live.",
            get = "getter",
            set = "setter",
        },
        nag_header = {
            type = "header",
            order = 4.0,
            name = "Next Action Guide",
        },
        nag_desc = {
            type = "description",
            order = 4.05,
            name = "On-screen rotation prompt (off by default): the next ability to press "..
                "(Overpower, Execute, Slam, Heroic Strike, Cleave) with the HOLD/RIDE cue "..
                "when an on-next-attack ability is queued or rage is short. Drag the frame "..
                "while it is unlocked to position it.",
        },
        nextaction_enabled = {
            type = "toggle",
            order = 4.1,
            name = "Enable",
            desc = "Show the next action guide.",
            get = "getter",
            set = "setter",
        },
        nextaction_locked = {
            type = "toggle",
            order = 4.11,
            name = "Lock frame",
            desc = "Prevent dragging the guide frame.",
            get = "getter",
            set = "setter",
        },
        nextaction_visibility_key = {
            type = "select",
            order = 4.12,
            name = "Show guide",
            desc = "When the guide is visible.",
            values = { always = "Always", in_combat = "In combat" },
            get = "getter",
            set = "setter",
        },
        nextaction_icon_size = {
            type = "range",
            order = 4.13,
            name = "Icon size",
            desc = "Guide icon size in pixels.",
            min = 20, max = 80, step = 1,
            get = "getter",
            set = "setter",
        },
        nextaction_x = {
            type = "input",
            order = 4.14,
            name = "X position",
            desc = "Horizontal screen position (dragging the frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().nextaction_x or 0)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().nextaction_x = n
                end
            end,
        },
        nextaction_y = {
            type = "input",
            order = 4.15,
            name = "Y position",
            desc = "Vertical screen position (dragging the frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().nextaction_y or -180)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().nextaction_y = n
                end
            end,
        },
        guide_execute_pct = {
            type = "range",
            order = 4.16,
            name = "Execute range (%)",
            desc = "Suggest Execute while the target is below this health percentage.",
            min = 5, max = 35, step = 1,
            get = "getter",
            set = "setter",
        },
    }
    -- Cooldown HUD + Rotation Text (shared hud_rotation_widgets builder: the same
    -- 8.x/9.x structure as the paladin's sections; the slot toggles mirror
    -- ST.WARRIOR.HUD_SLOTS, both family sets). Overpower glows while its dodge
    -- window is live and Execute glows in combat inside Execute range.
    for k, v in pairs(hud_rotation_widgets({
        { key = "hud_show_op", name = "Overpower", desc = "Show the Overpower icon (glows while the dodge window is live)." },
        { key = "hud_show_execute", name = "Execute", desc = "Show the Execute icon (glows in combat inside Execute range)." },
        { key = "hud_show_slam", name = "Slam", desc = "Show the Slam icon (with its GCD swipe)." },
        { key = "hud_show_hs", name = "Heroic Strike", desc = "Show the Heroic Strike icon (with its GCD swipe)." },
        { key = "hud_show_cleave", name = "Cleave", desc = "Show the Cleave icon (with its GCD swipe)." },
        { key = "hud_show_bt", name = "Bloodthirst", desc = "Show the Bloodthirst icon." },
        { key = "hud_show_ww", name = "Whirlwind", desc = "Show the Whirlwind icon." },
        { key = "hud_show_trinket1", name = "Trinket 1", desc = "Show the top trinket slot (hidden while the slot is empty)." },
        { key = "hud_show_trinket2", name = "Trinket 2", desc = "Show the bottom trinket slot (hidden while the slot is empty)." },
    },
        "A row of ability icons with cooldown swipes and remaining-time text. Icons grey out "..
            "while on cooldown, tint blue without mana and red out of range. Overpower glows "..
            "while its dodge window is live and Execute glows in combat inside Execute range. "..
            "Unlock the frame to drag it into place.",
        "Overpower glows while its dodge window is live and Execute glows in combat inside "..
            "Execute range, both only while the toggle is on. No other icon glows.",
        "What the label says: the rotation alone, with a prefix, its steps, or both.")) do
        opts_group[k] = v
    end
    return opts_group
end

function ST.class_opts_funcs.HUNTER(self)
    -- The hunter cast-bar colour is stored as 0-1 floats (hunter_ui.lua feeds it to
    -- SetVertexColor directly), while the shared class colour pair assumes the 0-255
    -- storage. This widget therefore carries its own get/set pair.
    ST.class_getsetters.hunter_cast_color_getter = function(_, info)
        local db = ST:get_class_table()
        local color = db[info[#info]] or {}
        return color[1] or color.r or 0.35, color[2] or color.g or 0.65,
            color[3] or color.b or 0.95, color[4] or color.a or 1
    end
    ST.class_getsetters.hunter_cast_color_setter = function(_, info, r, g, b, a)
        local db = ST:get_class_table()
        db[info[#info]] = {r, g, b, a}
    end

    local opts_group = {
        form_color_header = {
            type = "header",
            order = 1.0,
            name = "Raptor Strike Queueing",
        },
        rs_desc = {
            order = 1.001,
            type = "description",
            name = "The mainhand progress bar can be configured to turn a custom color when Raptor Strike is queued."
        },
        enable_raptor_strike_color = {
            type = "toggle",
            order = 1.1,
            name = "Enable",
            desc = "Enables a special bar color when Raptor Strike is queued on the next attack.",
            get = "getter",
            set = "setter",
        },
        raptor_strike_color = {
            order=1.2,
            type="color",
            name="Color",
            desc="Color to use when Raptor Strike is queued.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },
        steady_shot_header = {
            type = "header",
            order = 2.0,
            name = "Steady Shot Queueing",
        },
        ss_desc = {
            order = 2.001,
            type = "description",
            name = "The mainhand progress bar can be configured to turn a custom color when Steady Shot is queued."
        },
        enable_steady_shot_color = {
            type = "toggle",
            order = 2.1,
            name = "Enable",
            desc = "Enables a special bar color when Steady Shot is queued.",
            get = "getter",
            set = "setter",
        },
        steady_shot_color = {
            order=2.2,
            type="color",
            name="Color",
            desc="Color to use when Steady Shot is queued.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },
        hunter_cast_bar_header = {
            type = "header",
            order = 3.0,
            name = "Hunter Cast Bar",
        },
        hcb_desc = {
            order = 3.001,
            type = "description",
            name = "A cast bar above the ranged bar. A live cast (Steady Shot, Multi-Shot, ...) shows its "..
                "name and progress with a red latency end-slice and a green/red no-clip tint; otherwise the "..
                "hidden Auto Shot window of the ranged cycle shows as \"Auto Shot\".",
        },
        hunter_cast_bar_enabled = {
            type = "toggle",
            order = 3.1,
            name = "Enable",
            desc = "Shows the hunter cast bar above the ranged bar.",
            get = "getter",
            set = "setter",
        },
        hunter_cast_bar_height = {
            type = "range",
            order = 3.2,
            name = "Height",
            desc = "Height of the hunter cast bar.",
            min = 6, max = 40, step = 1,
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hunter_cast_bar_enabled
            end,
        },
        hunter_cast_bar_color = {
            order = 3.3,
            type = "color",
            name = "Color",
            desc = "Color of the hunter cast bar. The Auto Shot window always uses this colour; live casts "..
                "overlay it in green when the cast is clip-safe and red when it is not.",
            hasAlpha = true,
            get = "hunter_cast_color_getter",
            set = "hunter_cast_color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hunter_cast_bar_enabled
            end,
        },
        hunter_range_helper_header = {
            type = "header",
            order = 4.0,
            name = "Range Helper",
        },
        hrh_desc = {
            order = 4.001,
            type = "description",
            name = "A vertical strip on the left edge of the ranged bar. Its colour reports the target's "..
                "state: melee range, the hunter sweet spot, ranged range, or out of range.",
        },
        hunter_range_helper_enabled = {
            type = "toggle",
            order = 4.1,
            name = "Enable",
            desc = "Shows the 4-state range helper beside the ranged bar.",
            get = "getter",
            set = "setter",
        },
        hunter_rapid_fire_header = {
            type = "header",
            order = 5.0,
            name = "Rapid Fire",
        },
        hrf_desc = {
            order = 5.001,
            type = "description",
            name = "A small aura-duration bar above the ranged bar with a whole-seconds countdown, shown "..
                "only while the Rapid Fire buff is active.",
        },
        hunter_rapid_fire_bar_enabled = {
            type = "toggle",
            order = 5.1,
            name = "Enable",
            desc = "Shows the Rapid Fire duration bar while the buff is active.",
            get = "getter",
            set = "setter",
        },
        hunter_aspect_header = {
            type = "header",
            order = 6.0,
            name = "Aspect Icon",
        },
        hai_desc = {
            order = 6.001,
            type = "description",
            name = "An icon showing the active aspect (Hawk, Cheetah, Monkey, Pack, Wild, Viper, Beast), "..
                "left of the range helper.",
        },
        hunter_aspect_icon_enabled = {
            type = "toggle",
            order = 6.1,
            name = "Enable",
            desc = "Shows the active aspect's icon beside the ranged bar.",
            get = "getter",
            set = "setter",
        },

        -- Next Action Guide (shared nextaction_ui frame; provider ST.HUNTER.guide).
        nag_header = {
            type = "header",
            order = 7.0,
            name = "Next Action Guide",
        },
        nag_desc = {
            type = "description",
            order = 7.05,
            name = "On-screen rotation prompt (off by default): Steady Shot when the cast "..
                "fits before the next Auto Shot, with the HOLD cue inside the hidden Auto "..
                "Shot window and the RIDE cue while a Steady Shot cast or a queued on-next-"..
                "swing ability is riding. Drag the frame while it is unlocked to position it.",
        },
        nextaction_enabled = {
            type = "toggle",
            order = 7.1,
            name = "Enable",
            desc = "Show the next action guide.",
            get = "getter",
            set = "setter",
        },
        nextaction_locked = {
            type = "toggle",
            order = 7.11,
            name = "Lock frame",
            desc = "Prevent dragging the guide frame.",
            get = "getter",
            set = "setter",
        },
        nextaction_visibility_key = {
            type = "select",
            order = 7.12,
            name = "Show guide",
            desc = "When the guide is visible.",
            values = { always = "Always", in_combat = "In combat" },
            get = "getter",
            set = "setter",
        },
        nextaction_icon_size = {
            type = "range",
            order = 7.13,
            name = "Icon size",
            desc = "Guide icon size in pixels.",
            min = 20, max = 80, step = 1,
            get = "getter",
            set = "setter",
        },
        nextaction_x = {
            type = "input",
            order = 7.14,
            name = "X position",
            desc = "Horizontal screen position (dragging the frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().nextaction_x or 0)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().nextaction_x = n
                end
            end,
        },
        nextaction_y = {
            type = "input",
            order = 7.15,
            name = "Y position",
            desc = "Vertical screen position (dragging the frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().nextaction_y or -180)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().nextaction_y = n
                end
            end,
        },
    }
    -- Cooldown HUD + Rotation Text (shared hud_rotation_widgets builder: the same
    -- 8.x/9.x structure as the paladin's sections; the slot toggles mirror
    -- ST.HUNTER.HUD_SLOTS). Kill Command glows once it is ready in combat.
    for k, v in pairs(hud_rotation_widgets({
        { key = "hud_show_steady", name = "Steady Shot", desc = "Show the Steady Shot icon (with its GCD swipe)." },
        { key = "hud_show_raptor", name = "Raptor Strike", desc = "Show the Raptor Strike icon (with its GCD swipe)." },
        { key = "hud_show_kill_command", name = "Kill Command", desc = "Show the Kill Command icon (glows once it is ready in combat)." },
        { key = "hud_show_multi", name = "Multi-Shot", desc = "Show the Multi-Shot icon (with its GCD swipe)." },
        { key = "hud_show_bestial_wrath", name = "Bestial Wrath", desc = "Show the Bestial Wrath icon." },
        { key = "hud_show_rapid_fire", name = "Rapid Fire", desc = "Show the Rapid Fire icon." },
        { key = "hud_show_aimed", name = "Aimed Shot", desc = "Show the Aimed Shot icon (with its GCD swipe)." },
        { key = "hud_show_trinket1", name = "Trinket 1", desc = "Show the top trinket slot (hidden while the slot is empty)." },
        { key = "hud_show_trinket2", name = "Trinket 2", desc = "Show the bottom trinket slot (hidden while the slot is empty)." },
    },
        "A row of ability icons with cooldown swipes and remaining-time text. Icons grey out "..
            "while on cooldown, tint blue without mana and red out of range. Kill Command glows "..
            "once it is ready in combat. Unlock the frame to drag it into place.",
        "Kill Command glows once it is ready in combat, only while the toggle is on. No other "..
            "icon glows.",
        "What the label says: the rotation alone, with a prefix, its steps, or both.")) do
        opts_group[k] = v
    end
    return opts_group
end

function ST.class_opts_funcs.DRUID(self)
    local opts_group = {

        -- Form-dependent visibility
        form_vis_header = {
            type = "header",
            order = 3.0,
            name = "Form-dependent Visibility"
        },
        form_vis_desc = {
            type = "description",
            order = 3.1,
            name = "The timer bar can be configured to be only visible in certain forms.",
        },
        form_vis_normal = {
            type = "toggle",
            order = 3.2,
            name = "No Form",
            desc = "Show the bar when in default form.",
            get = "getter",
            set = "setter",
        },
        form_vis_bear = {
            type = "toggle",
            order = 3.3,
            name = "Bear/Dire Bear",
            desc = "Show the bar when in Bear or Dire Bear form.",
            get = "getter",
            set = "setter",
        },
        form_vis_cat = {
            type = "toggle",
            order = 3.4,
            name = "Cat",
            desc = "Show the bar when in Cat form.",
            get = "getter",
            set = "setter",
        },
        form_vis_moonkin = {
            type = "toggle",
            order = 3.5,
            name = "Moonkin",
            desc = "Show the bar when in Moonkin form.",
            get = "getter",
            set = "setter",
        },
        form_vis_tree = {
            type = "toggle",
            order = 3.6,
            name = "Tree of Life",
            desc = "Show the bar when in Tree of Life form.",
            get = "getter",
            set = "setter",
        },
        form_vis_travel = {
            type = "toggle",
            order = 3.7,
            name = "Travel Form",
            desc = "Show the bar when in Travel form.",
            get = "getter",
            set = "setter",
        },
        form_vis_flight = {
            type = "toggle",
            order = 3.8,
            name = "Flight Form",
            desc = "Show the bar when in Flight form.",
            get = "getter",
            set = "setter",
        },

        -- Form-dependent colors
        form_color_header = {
            type = "header",
            order = 4,
            name = "Form-dependent Colors",
        },
        form_color_desc = {
            order = 4.1,
            type = "description",
            name = "Enables the timer bar color changing depending on the druid's form."
        },
        use_form_colors = {
            type = "toggle",
            order = 4.3,
            name = "Enable",
            desc = "Enables form-dependent colors.",
            get = "getter",
            set = "setter",
        },
        lb02 = {
            type = "description",
            order = 4.4,
            name = "",
        },
        form_color_bear = {
            order=5.0,
            type="color",
            name="Bear/Dire Bear",
            desc="Color to use when in Bear/Dire Bear form.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },
        form_color_cat = {
            order=5.1,
            type="color",
            name="Cat",
            desc="Color to use when in Cat form.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },
        form_color_moonkin = {
            order=5.2,
            type="color",
            name="Moonkin",
            desc="Color to use when in Moonkin form.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },
        form_color_tree = {
            order=5.3,
            type="color",
            name="Tree of Life",
            desc="Color to use when in Tree of Life form.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },
        form_color_travel = {
            order=5.4,
            type="color",
            name="Travel Form",
            desc="Color to use when in Travel form.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },
        form_color_flight = {
            order=5.5,
            type="color",
            name="Flight Form",
            desc="Color to use when in Flight form.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },

        -- Maul color
        class_header = {
            type = "header",
            order = 11.0,
            name = "Maul",
        },
        queue_desc = {
            order = 11.02,
            type = "description",
            name = "The timer bar can be configured to turn a custom color when maul is queued."
        },
        -- lb0 = {
        --     type = "header",
        --     order = 11.03,
        --     name = "",
        -- },
        enable_maul_color = {
            type = "toggle",
            order = 11.1,
            name = "Enable Maul Color",
            desc = "Enables a custom color for the mainhand bar when Maul is queued.",
            get = "getter",
            set = "setter",
        },
        maul_color = {
            order=11.2,
            type="color",
            name="Color",
            desc="Color to use when Heroic Strike is queued.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.enable_maul_color
            end,
        },
        -- Insufficient rage
        -- lb1 = {
        --     type = "header",
        --     order = 12,
        --     name = "",
        -- },
        rage_desc = {
            order = 12.1,
            type = "description",
            name = "If the above is enabled, the mainhand timer bar will turn a certain color when the player "..
                "has queued Maul, but has since dropped below the rage threshold necessary "..
                "to use the ability."
        },
        -- lb2 = {
        --     type = "header",
        --     order = 12.2,
        --     name = "",
        -- },
        insufficient_rage_color = {
            order=12.3,
            type="color",
            name="Insufficient Rage color",
            desc="Color to use for the timer bar when the player drops below the rage threshold for the queued ability.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },

        -- Druid trackers (reference SuperSwingTimer_ClassMods.lua druid block
        -- 4514-5524): the cat-form energy tick bar, the mainhand form label and the
        -- Mangle/Rip/Rake target debuff bars.
        trackers_header = {
            type = "header",
            order = 13.0,
            name = "Druid Trackers",
        },
        trackers_desc = {
            order = 13.01,
            type = "description",
            name = "Feral/forms helper visuals: the 2-second cat-form energy cycle "..
                "beside the mainhand bar, the current shape on the bar while "..
                "shapeshifted, and your own Mangle/Rip/Rake durations above the bar.",
        },
        show_druid_energy_tick = {
            type = "toggle",
            order = 13.1,
            name = "Energy tick bar",
            desc = "Show a thin bar left of the mainhand bar tracking the 2-second "..
                "cat-form energy cycle (it fills as the next natural tick approaches).",
            get = "getter",
            set = "setter",
        },
        druid_energy_tick_color = {
            order=13.2,
            type="color",
            name="Energy tick color",
            desc="Color of the energy tick bar.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.show_druid_energy_tick == false
            end,
        },
        show_druid_form_label = {
            type = "toggle",
            order = 13.3,
            name = "Form label",
            desc = "Show the current shape (Cat / Bear / Caster) on the mainhand bar "..
                "while shapeshifted; the configured bar texts are untouched in no form.",
            get = "getter",
            set = "setter",
        },
        show_druid_mangle_bar = {
            type = "toggle",
            order = 13.4,
            name = "Mangle bar",
            desc = "Show your own Mangle duration on the current target above the "..
                "mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        druid_mangle_bar_color = {
            order=13.5,
            type="color",
            name="Mangle bar color",
            desc="Color of the Mangle duration bar.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.show_druid_mangle_bar == false
            end,
        },
        show_druid_rip_bar = {
            type = "toggle",
            order = 13.6,
            name = "Rip bar",
            desc = "Show your own Rip duration on the current target above the "..
                "mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        druid_rip_bar_color = {
            order=13.7,
            type="color",
            name="Rip bar color",
            desc="Color of the Rip duration bar.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.show_druid_rip_bar == false
            end,
        },
        show_druid_rake_bar = {
            type = "toggle",
            order = 13.8,
            name = "Rake bar",
            desc = "Show your own Rake duration on the current target above the "..
                "mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        druid_rake_bar_color = {
            order=13.9,
            type="color",
            name="Rake bar color",
            desc="Color of the Rake duration bar.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return db.show_druid_rake_bar == false
            end,
        },

        -- Next Action Guide (shared nextaction_ui frame; provider ST.DRUID.guide).
        nag_header = {
            type = "header",
            order = 14.0,
            name = "Next Action Guide",
        },
        nag_desc = {
            type = "description",
            order = 14.05,
            name = "On-screen rotation prompt (off by default): the next ability to press "..
                "in bear (Maul / Mangle) or cat form (Rip, Rake, Mangle, Ferocious Bite, "..
                "Shred) with the RIDE cue while a Maul is queued. Drag the frame while it "..
                "is unlocked to position it.",
        },
        nextaction_enabled = {
            type = "toggle",
            order = 14.1,
            name = "Enable",
            desc = "Show the next action guide.",
            get = "getter",
            set = "setter",
        },
        nextaction_locked = {
            type = "toggle",
            order = 14.11,
            name = "Lock frame",
            desc = "Prevent dragging the guide frame.",
            get = "getter",
            set = "setter",
        },
        nextaction_visibility_key = {
            type = "select",
            order = 14.12,
            name = "Show guide",
            desc = "When the guide is visible.",
            values = { always = "Always", in_combat = "In combat" },
            get = "getter",
            set = "setter",
        },
        nextaction_icon_size = {
            type = "range",
            order = 14.13,
            name = "Icon size",
            desc = "Guide icon size in pixels.",
            min = 20, max = 80, step = 1,
            get = "getter",
            set = "setter",
        },
        nextaction_x = {
            type = "input",
            order = 14.14,
            name = "X position",
            desc = "Horizontal screen position (dragging the frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().nextaction_x or 0)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().nextaction_x = n
                end
            end,
        },
        nextaction_y = {
            type = "input",
            order = 14.15,
            name = "Y position",
            desc = "Vertical screen position (dragging the frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().nextaction_y or -180)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().nextaction_y = n
                end
            end,
        },
        guide_rip_refresh = {
            type = "range",
            order = 14.16,
            name = "Rip refresh (s)",
            desc = "Suggest Rip while the target's Rip is missing or has this many "..
                "seconds or fewer remaining.",
            min = 0, max = 10, step = 0.5,
            get = "getter",
            set = "setter",
        },
        guide_rake_refresh = {
            type = "range",
            order = 14.17,
            name = "Rake refresh (s)",
            desc = "Suggest Rake while the target's Rake is missing or has this many "..
                "seconds or fewer remaining.",
            min = 0, max = 10, step = 0.5,
            get = "getter",
            set = "setter",
        },
    }
    -- Cooldown HUD + Rotation Text (shared hud_rotation_widgets builder: the same
    -- 8.x/9.x structure as the paladin's sections; the slot toggles mirror
    -- ST.DRUID.HUD_SLOTS). The Maul slot greys while a queued Maul is
    -- unaffordable; no druid icon glows, so the glow toggle below has no effect.
    for k, v in pairs(hud_rotation_widgets({
        { key = "hud_show_maul", name = "Maul", desc = "Show the Maul icon (greys while a queued Maul is unaffordable)." },
        { key = "hud_show_mangle", name = "Mangle", desc = "Show the Mangle icon (with its GCD swipe)." },
        { key = "hud_show_rip", name = "Rip", desc = "Show the Rip icon (with its GCD swipe)." },
        { key = "hud_show_rake", name = "Rake", desc = "Show the Rake icon (with its GCD swipe)." },
        { key = "hud_show_bite", name = "Ferocious Bite", desc = "Show the Ferocious Bite icon (with its GCD swipe)." },
        { key = "hud_show_shred", name = "Shred", desc = "Show the Shred icon (with its GCD swipe)." },
        { key = "hud_show_trinket1", name = "Trinket 1", desc = "Show the top trinket slot (hidden while the slot is empty)." },
        { key = "hud_show_trinket2", name = "Trinket 2", desc = "Show the bottom trinket slot (hidden while the slot is empty)." },
    },
        "A row of ability icons with cooldown swipes and remaining-time text. Icons grey out "..
            "while on cooldown (Maul also while a queued Maul is unaffordable), tint blue "..
            "without mana and red out of range. No druid icon glows. Unlock the frame to drag "..
            "it into place.",
        "No druid icon ever glows, so this toggle has no effect on this class.",
        "What the label says: the rotation alone, with a prefix, its steps, or both.")) do
        opts_group[k] = v
    end
    return opts_group

end

--=========================================================================================
-- Bar Positioning group
--=========================================================================================
-- Spell weaving family toggles live in the nested weave_families table, so they need
-- key-specific accessors rather than the generic class getter/setter pair.
local function weave_family_getter(family)
    return function()
        local db = ST:get_class_table()
        return not db.weave_families or db.weave_families[family] ~= false
    end
end

local function weave_family_setter(family)
    return function(_, value)
        local db = ST:get_class_table()
        db.weave_families = db.weave_families or {}
        db.weave_families[family] = value and true or false
    end
end

function ST.class_opts_funcs.SHAMAN(self)
    local opts_group = {
        weave_header = {
            type = "header",
            order = 1.01,
            name = "Spell Weaving",
        },
        weave_desc = {
            type = "description",
            order = 1.05,
            name = "Enhancement weave assist: the marker shows the latest swing position a "..
                "tracked cast may start at and still land before the next swing; the spark "..
                "shows the active cast (red when it would clip the swing).",
        },
        weave_enabled = {
            type = "toggle",
            order = 1.1,
            name = "Enable",
            desc = "Show the spell weaving breakpoint marker and cast spark on the mainhand bar.",
            get = "getter",
            set = "setter",
        },
        weave_family_LB = {
            type = "toggle",
            order = 1.2,
            name = "Lightning Bolt",
            desc = "Track Lightning Bolt breakpoints.",
            get = weave_family_getter("LB"),
            set = weave_family_setter("LB"),
            disabled = function() return ST:get_class_table().weave_enabled == false end,
        },
        weave_family_CL = {
            type = "toggle",
            order = 1.21,
            name = "Chain Lightning",
            desc = "Track Chain Lightning breakpoints.",
            get = weave_family_getter("CL"),
            set = weave_family_setter("CL"),
            disabled = function() return ST:get_class_table().weave_enabled == false end,
        },
        weave_family_HW = {
            type = "toggle",
            order = 1.22,
            name = "Healing Wave",
            desc = "Track Healing Wave breakpoints.",
            get = weave_family_getter("HW"),
            set = weave_family_setter("HW"),
            disabled = function() return ST:get_class_table().weave_enabled == false end,
        },
        weave_family_LHW = {
            type = "toggle",
            order = 1.23,
            name = "Lesser Healing Wave",
            desc = "Track Lesser Healing Wave breakpoints.",
            get = weave_family_getter("LHW"),
            set = weave_family_setter("LHW"),
            disabled = function() return ST:get_class_table().weave_enabled == false end,
        },
        weave_family_CH = {
            type = "toggle",
            order = 1.24,
            name = "Chain Heal",
            desc = "Track Chain Heal breakpoints.",
            get = weave_family_getter("CH"),
            set = weave_family_setter("CH"),
            disabled = function() return ST:get_class_table().weave_enabled == false end,
        },
        weave_mw_enabled = {
            type = "toggle",
            order = 1.3,
            name = "Maelstrom Weapon",
            desc = "Reduce the effective cast time by 20% per Maelstrom Weapon stack; 5 stacks are instant.",
            get = "getter",
            set = "setter",
            disabled = function() return ST:get_class_table().weave_enabled == false end,
        },
        weave_marker_size = {
            type = "range",
            order = 1.4,
            name = "Marker size",
            desc = "Size of the breakpoint spell icon.",
            min = 6, max = 24, step = 1,
            get = "getter",
            set = "setter",
            disabled = function() return ST:get_class_table().weave_enabled == false end,
        },
        weave_marker_alpha = {
            type = "range",
            order = 1.41,
            name = "Marker alpha",
            desc = "Opacity of the breakpoint spell icon (dimmed while the cast would clip).",
            min = 0, max = 1, step = 0.05,
            get = "getter",
            set = "setter",
            disabled = function() return ST:get_class_table().weave_enabled == false end,
        },
        weave_spark_width = {
            type = "range",
            order = 1.5,
            name = "Spark width",
            desc = "Width of the moving cast spark.",
            min = 2, max = 60, step = 1,
            get = "getter",
            set = "setter",
            disabled = function() return ST:get_class_table().weave_enabled == false end,
        },
        weave_spark_height = {
            type = "range",
            order = 1.51,
            name = "Spark height",
            desc = "Height of the moving cast spark (clamped to the bar height).",
            min = 2, max = 100, step = 1,
            get = "getter",
            set = "setter",
            disabled = function() return ST:get_class_table().weave_enabled == false end,
        },
        weave_spark_alpha = {
            type = "range",
            order = 1.52,
            name = "Spark alpha",
            desc = "Opacity of the moving cast spark.",
            min = 0, max = 1, step = 0.05,
            get = "getter",
            set = "setter",
            disabled = function() return ST:get_class_table().weave_enabled == false end,
        },
        trackers_header = {
            type = "header",
            order = 2.01,
            name = "Shaman Trackers",
        },
        show_shaman_breakpoint_markers = {
            type = "toggle",
            order = 2.1,
            name = "Breakpoint markers",
            desc = "Show the reference breakpoint icons above and below the bar, and mirror "..
                "the cast spark on the offhand bar while dual-wielding.",
            get = "getter",
            set = "setter",
        },
        show_shaman_windfury_icd = {
            type = "toggle",
            order = 2.2,
            name = "Windfury ICD bar",
            desc = "Show a thin Windfury Weapon internal-cooldown strip beside the mainhand "..
                "bar (red above 2s, orange above 0.5s, green when ready).",
            get = "getter",
            set = "setter",
        },
        show_shaman_flame_shock_bar = {
            type = "toggle",
            order = 2.3,
            name = "Flame Shock bar",
            desc = "Show the target's Flame Shock remaining time above the mainhand bar, "..
                "with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        show_shaman_cooldown_badges = {
            type = "toggle",
            order = 2.4,
            name = "Stormstrike / Shamanistic Rage badges",
            desc = "Show the Stormstrike cooldown (SS) and the Shamanistic Rage timer (SR) "..
                "beside the mainhand bar.",
            get = "getter",
            set = "setter",
        },
        show_shaman_shield_charges = {
            type = "toggle",
            order = 2.5,
            name = "Shield charges",
            desc = "Show Lightning Shield / Water Shield charges as small rectangles left "..
                "of the mainhand bar; empty charges are dimmed.",
            get = "getter",
            set = "setter",
        },

        -- Next Action Guide (shared nextaction_ui frame; provider ST.SHAMAN.guide).
        nag_header = {
            type = "header",
            order = 3.0,
            name = "Next Action Guide",
        },
        nag_desc = {
            type = "description",
            order = 3.05,
            name = "On-screen rotation prompt (off by default): the next ability to press "..
                "(Stormstrike, Flame Shock, or the weave cast once Maelstrom Weapon has "..
                "stacked) with the RIDE cue while a cast is in flight. Drag the frame "..
                "while it is unlocked to position it.",
        },
        nextaction_enabled = {
            type = "toggle",
            order = 3.1,
            name = "Enable",
            desc = "Show the next action guide.",
            get = "getter",
            set = "setter",
        },
        nextaction_locked = {
            type = "toggle",
            order = 3.11,
            name = "Lock frame",
            desc = "Prevent dragging the guide frame.",
            get = "getter",
            set = "setter",
        },
        nextaction_visibility_key = {
            type = "select",
            order = 3.12,
            name = "Show guide",
            desc = "When the guide is visible.",
            values = { always = "Always", in_combat = "In combat" },
            get = "getter",
            set = "setter",
        },
        nextaction_icon_size = {
            type = "range",
            order = 3.13,
            name = "Icon size",
            desc = "Guide icon size in pixels.",
            min = 20, max = 80, step = 1,
            get = "getter",
            set = "setter",
        },
        nextaction_x = {
            type = "input",
            order = 3.14,
            name = "X position",
            desc = "Horizontal screen position (dragging the frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().nextaction_x or 0)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().nextaction_x = n
                end
            end,
        },
        nextaction_y = {
            type = "input",
            order = 3.15,
            name = "Y position",
            desc = "Vertical screen position (dragging the frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().nextaction_y or -180)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().nextaction_y = n
                end
            end,
        },
        guide_flameshock_refresh = {
            type = "range",
            order = 3.16,
            name = "Flame Shock refresh (s)",
            desc = "Suggest Flame Shock while the target's Flame Shock is missing or has "..
                "this many seconds or fewer remaining.",
            min = 0, max = 10, step = 0.5,
            get = "getter",
            set = "setter",
        },
    }
    -- Cooldown HUD + Rotation Text (shared hud_rotation_widgets builder: the same
    -- 8.x/9.x structure as the paladin's sections; the slot toggles mirror
    -- ST.SHAMAN.HUD_SLOTS). Stormstrike glows once it is ready in combat.
    for k, v in pairs(hud_rotation_widgets({
        { key = "hud_show_stormstrike", name = "Stormstrike", desc = "Show the Stormstrike icon (glows once it is ready in combat)." },
        { key = "hud_show_flameshock", name = "Flame Shock", desc = "Show the Flame Shock icon (with its GCD swipe)." },
        { key = "hud_show_weave", name = "Lightning Bolt", desc = "Show the Lightning Bolt weave icon (with its GCD swipe)." },
        { key = "hud_show_firenova", name = "Fire Nova Totem", desc = "Show the Fire Nova Totem icon." },
        { key = "hud_show_earthshock", name = "Earth Shock", desc = "Show the Earth Shock icon (with its GCD swipe)." },
        { key = "hud_show_twist", name = "Windfury Totem", desc = "Show the Windfury Totem icon (with its GCD swipe)." },
        { key = "hud_show_trinket1", name = "Trinket 1", desc = "Show the top trinket slot (hidden while the slot is empty)." },
        { key = "hud_show_trinket2", name = "Trinket 2", desc = "Show the bottom trinket slot (hidden while the slot is empty)." },
    },
        "A row of ability icons with cooldown swipes and remaining-time text. Icons grey out "..
            "while on cooldown, tint blue without mana and red out of range. Stormstrike glows "..
            "once it is ready in combat. Unlock the frame to drag it into place.",
        "Stormstrike glows once it is ready in combat, only while the toggle is on. No other "..
            "icon glows.",
        "What the label says: the rotation alone, with a prefix, its steps, or both.")) do
        opts_group[k] = v
    end
    return opts_group
end

function ST:generate_bar_position_options_table()

    local opts_group = {
		name = "Size/Positioning/Scale",
		type = "group",
        desc = "This panel controls the positioning and scales of the bars in SwedgeTimer.",
        order = 0.6,
        args = {
            section_desc = {
                order = 0.1,
                type = "description",
                name = "This panel allows the user to control each timer's position. It is recommended "..
                    "to move the timers into position with the mouse with the timers unlocked in the global "..
                    "settings, and carry out any fine tuning here.",
            }
        },
    }

    local hand_offsets = {
        mainhand = 1.0,
        offhand = 2.0,
        ranged = 3.0,
    }

    for hand in self:iter_hands() do
        local offset = hand_offsets[hand]
        local name_pretty = self.opts_case_dict[hand].pretty_name
        local g = {
            [hand .. "_header"] = {
                type = "header",
                order = 1.0 + offset,
                name = name_pretty,
            },
            [hand .. "bar_width"] = {
                type = "range",
                order = 1.01 + offset,
                name = "Width",
                desc = "The pixel width of the swing timer.",
                min = 100, max = 600, step = 1,
                get = function()
                    return ST:get_hand_table(hand).bar_width
                end,
                set = function(_, value)
                    ST:get_hand_table(hand).bar_width = value
                    ST:configure_bar_size_and_positions(hand)
                    ST:configure_bar_appearances(hand)
                    ST:configure_bar_outline(hand)
                    ST:configure_gcd_markers(hand)
                    ST:set_gcd_marker_positions(hand)
                    ST:configure_deadzone(hand)
                    ST:set_deadzone_width(hand)
                end
            },
            [hand .. "bar_height"] = {
                type = "range",
                order = 1.02 + offset,
                name = "Height",
                desc = "The pixel height of the swing timer.",
                min = 6, max = 60, step = 1,
                get = function()
                    return ST:get_hand_table(hand).bar_height
                end,
                set = function(_, value)
                    ST:get_hand_table(hand).bar_height = value
                    ST:configure_bar_size_and_positions(hand)
                    ST:configure_bar_appearances(hand)
                    ST:configure_bar_outline(hand)
                    ST:configure_gcd_markers(hand)
                    ST:set_gcd_marker_positions(hand)
                    ST:configure_deadzone(hand)
                    ST:set_deadzone_width(hand)
                end
            },
            [hand .. "_x"] = {
                type = "range",
                order = 1.1 + offset,
                name = "x coord",
                min = -2000, max = 2000, step = 1,
                softMin = -1000, softMax = 1000,
                get = function()
                    return ST:get_hand_table(hand).x
                end,
                set = function(_, value)
                    ST:get_hand_table(hand).x = value
                    LWIN.RestorePosition(ST:get_anchor_frame(hand))
                end,
            },
            [hand .. "_y"] = {
                type = "range",
                order = 1.2 + offset,
                name = "y coord",
                min = -2000, max = 2000, step = 1,
                softMin = -800, softMax = 800,
                get = function()
                    return ST:get_hand_table(hand).y
                end,
                set = function(_, value)
                    ST:get_hand_table(hand).y = value
                    LWIN.RestorePosition(ST:get_anchor_frame(hand))
                end,
            },
            [hand .. "_point"] = {
                type = "select",
                order = 1.3 + offset,
                name = "Anchor Point",
                desc = "The anchor point to the Parent UI.",
                values = ST.valid_anchor_points,
                get = function()
                    return ST:get_hand_table(hand).point
                end,
                set = function(_, value)
                    ST:get_hand_table(hand).point = value
                    LWIN.RestorePosition(ST:get_anchor_frame(hand))
                end,
            },
            [hand .. "_scale"] = {
                type = "range",
                order = 1.4 + offset,
                name = "Scale",
                min = 0.1, max = 2.0, step = 0.01,
                get = function()
                    return ST:get_hand_table(hand).scale
                end,
                set = function(_, value)
                    ST:get_hand_table(hand).scale = value
                    LWIN.RestorePosition(ST:get_anchor_frame(hand))
                end,
            },
        }
        for k, v in pairs(g) do
            opts_group.args[k] = v
        end
    end
    self.opts_table.args.positions = opts_group
end


--=========================================================================================
-- Per-hand opts table entries.
--=========================================================================================
function ST:generate_hand_options_table(hand)
    -- Function to generate an options table for a hand object.
    local settings = ST.opts_case_dict[hand]
    local offset = settings.order_offset
    local title = settings.title

    -- print(hand_title)
    local opts_group = {
        handler = ST.opts_funcs[hand],
		name = settings.panel_title,
		type = "group",
        desc = settings.desc,
        order = offset,
	}

    -- This will be the options table for the hand.
    -- All standard widgets are configured here.
    local opts = {

        enabled_header = {
            order = 0.001,
            name = "Timer Enabled",
            type = "header",
        },
        enabled = {
            type = "toggle",
            order = 0.01,
            name = "Enabled",
            desc = "Enables or disables the swing timer.",
            get = "getter",
            set = "setter",
        },

        -- -- Bar size options
        -- size_header = {
        --     order = 1.1,
        --     name = "Bar Size",
        --     type = "header",
        -- },
        -- bar_width = {
        --     type = "range",
        --     order = 2,
        --     name = "Width",
        --     desc = "The width of the swing timer.",
        --     min = 100, max = 600, step = 1,
        --     get = "getter",
        --     set = "bar_setter",
        -- },
        -- bar_height = {
        --     type = "range",
        --     order = 3,
        --     name = "Height",
        --     desc = "The height of the swing timer.",
        --     min = 6, max = 60, step = 1,
        --     get = "getter",
        --     set = "bar_setter",
        -- },

        bar_appearance_group = {
            type = "group",
            order = 1.5,
            name = "Appearance",
            args = ST.bar_appearance_preset,
        },

        -- -- Border options go here.
        -- bar_borders_group = {
        --     type = "group",
        --     order = 1.7,
        --     name = "Border",
        --     args = ST.borders_preset,
        -- },

        -- Font options all go here.
        texts_group = {
            type = "group",
            order = 2.00,
            name = "Texts",
            args = ST.fonts_table_preset,
        },

        -- Deadzone group
        deadzone_group = {
            type = "group",
            order = 2.1,
            name = "Deadzone",
            args = ST.deadzone_settings_table,
        },

        -- GCD underlay group
        underlay_group = {
            type = "group",
            order = 2.2,
            name = "GCD Underlay",
            args = ST.gcd_underlay_preset,
        },

        -- GCD marker group
        gcd_markers_group = {
            type = "group",
            order = 3.0,
            name = "GCD Markers",
            args = ST.gcd_markers_preset
        }
    }

    opts_group.args = opts

    -- Any optional groups should go here.
    if hand == "mainhand" or hand == "ranged" then
        -- opts_group.args.gcd_markers_group = {
        --     type = "group",
        --     order = 3.0,
        --     name = "GCD Markers",
        --     args = ST.gcd_markers_preset
        -- }
        -- Add in the GCD mode options, which are class-dependent.
        if self.player_class == "DRUID" then
            opts_group.args.gcd_markers_group.args.gcd1a_marker_mode = {
                order = 2.2,
                type = "select",
                name = "GCD type to show",
                desc = "The GCD type to show (physical/spell). If set to Form Dependent, will show the physical "..
                    "GCD duration in cat/bear form, and the spell GCD duration in all other forms.",
                values = ST.gcd_marker_modes.DRUID,
                get = "getter",
                set = "bar_setter",
                disabled = "gcd1a_anchor_disable"
            }
            opts_group.args.gcd_markers_group.args.gcd1b_marker_mode = {
                order = 2.7,
                type = "select",
                name = "GCD type to show",
                desc = "The GCD type to show (physical/spell). If set to Form Dependent, will show the physical "..
                    "GCD duration in cat/bear form, and the spell GCD duration in all other forms.",
                values = ST.gcd_marker_modes.DRUID,
                get = "getter",
                set = "bar_setter",
                disabled = "gcd1b_anchor_disable"
            }
        else
            opts_group.args.gcd_markers_group.args.gcd1a_marker_mode = {
                order = 2.2,
                type = "select",
                name = "GCD type to show",
                desc = "The GCD type to show (physical/spell).",
                values = ST.gcd_marker_modes.NONDRUID,
                get = "getter",
                set = "bar_setter",
                disabled = "gcd1a_anchor_disable"
            }
            opts_group.args.gcd_markers_group.args.gcd1b_marker_mode = {
                order = 2.7,
                type = "select",
                name = "GCD type to show",
                desc = "The GCD type to show (physical/spell).",
                values = ST.gcd_marker_modes.NONDRUID,
                get = "getter",
                set = "bar_setter",
                disabled = "gcd1b_anchor_disable"
            }
        end
    end

    -- Only basic hands and melee hands get visibility behaviour.
    if true then --hand == "mainhand" or hand == "offhand" or hand == "ranged" or hand == "melee_hands" then
        local vis_opts = {
            vis_header = {
                type = "header",
                order = 0.1,
                name = "Bar Visibility",
            },
            show_behaviour = {
                type = "select",
                order = 0.2,
                name = "Show...",
                values = ST.show_bar_opts,
                desc = "Choose to always show the bar, or to require some conditions.",
                get = "getter",
                set = "setter",
            },
            show_condition = {
                type = "select",
                order = 0.3,
                name = "Conditions to show",
                values = ST.show_bar_conditions,
                desc = "Choose to always show the bar, or to require some conditions.",
                get = "getter",
                set = "setter",
                sorting = ST.show_bar_conditions_sorting,
                disabled = "not_always_shown_disabler",
            },
            require_in_range = {
                type = "toggle",
                order = 0.4,
                name = "Require target in-range",
                desc = "If requiring a valid target, will only show the bar when the player is in range with this hand.",
                get = "getter",
                set = "setter",
                disabled = "require_in_range_disabler",
            },
            range_header = {
                type = "header",
                order = 21.0,
                name = "Out-of-range Behaviour",
            },
            dim_oor = {
                type = "toggle",
                order = 21.1,
                name = "Dim out of range",
                desc = "Dims the bar when the player is out of range with this hand, or has no target.",
                get = "getter",
                set = "setter",
            },
            dim_alpha = {
                type = "range",
                order = 21.2,
                name = "Alpha",
                desc = "The bar alpha when out of range.",
                min = 0, max = 1, step = 0.01,
                get = "getter",
                set = "setter",
                disabled = "oor_dim_alpha_disabler",
            }
        }
        for k, v in pairs(vis_opts) do
            opts_group.args[k] = v
        end
    end

    -- Assign it to the opts table.
    if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
        self.opts_table.args[hand] = opts_group
    else
        -- If we need to, construct the multi-bar control panel and group.
        if not self.opts_table.args.multi_control then
            local mp_desc = "This panel allows the user to control multiple groups of bars at once for this class."
            self.opts_table.args.multi_control = {
                name = "Multi-timer Controls",
                type = "group",
                desc = mp_desc,
                args = {},
                order = 8.0,
            }
            self.opts_table.args.multi_control.args.multi_header = {
                name = "Control Multiple Timers at Once",
                order = 0.1,
                type = "header",
            }
            self.opts_table.args.multi_control.args.multi_desc = {
                name = mp_desc,
                order = 0.2,
                type = "description",
            }
        end
        self.opts_table.args.multi_control.args[hand] = opts_group
    end
end

function ST:set_opts()
    -- Finally, a function to be run on init that will dynamically generate
    -- all the requested panel tables on a per-hand/per-class basis.

    -- Sets a dict for hand/collection-based case switching. 
    self:set_opts_case_dict()

    -- Generate the preset options tables that don't require special case switching.
    self:build_preset_options_tables()

    -- Generates some handler setters/getters/disablers for hands/collections.
	self:set_opts_funcs()

    -- Generate the top level, position, and class opts if they exist.
	self:generate_info_panel()
    self:generate_top_level_options_table()
	self:generate_bar_position_options_table()
	self:generate_class_options_table()

    -- Generate all basic hand panels
	for hand in self:iter_hands() do
		self:generate_hand_options_table(hand)
	end

    -- Generate an "All hands" collection control panel if multiple hands exist
	local hands = self:get_class_hands()
	if #hands ~= 1 then
		self:generate_hand_options_table("all_hands")
	end

	-- Only generate "melee hands" collection control panel if class can use all three
    -- basic hands.
	if #hands == 3 then
		self:generate_hand_options_table("melee_hands")
	end
end