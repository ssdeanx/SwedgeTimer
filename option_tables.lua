------------------------------------------------------------------------------------
-- Module to contain option table defaults
--
-- The module's purpose is to dynamically generate any options tables
-- depending on player class that the addon needs. So for example,
-- a Paladin will only ever see the mainhand options, and the Paladin-specific
-- class options.
------------------------------------------------------------------------------------
local addon_name, st = ...
---@class ST: AceAddon
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
---@field set_bar_color fun(self: ST, hand: any, color_table?: any)
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
-- NOTE: no `print` alias here (was: local print = st.utils.print_msg): the only
-- references were two commented-out debug lines, and st stays reachable directly.

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
    local _, pretty_class = UnitClass("player")
    return pretty_class or "Player"
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

local hud_template_matches

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
        desc = "Enables the timer when Talent Specialization 1 is active (only one spec active at a time).",
        get = function()
            return ST:get_class_table().enable_spec1 == true
        end,
        set = function(_, value)
            local cdb = ST:get_class_table()
            cdb.enable_spec1 = value and true or false
            if value then
                cdb.enable_spec2 = false
            end
            if ST.iter_hands and ST.handle_bar_visibility then
                for h in ST:iter_hands() do
                    ST:handle_bar_visibility(h)
                end
            end
        end,
        disabled = function()
            return not ST:get_class_table().class_enabled
        end,
    }
    self.opts_table.args.enable_spec2 = {
        type = "toggle",
        order = 1.12,
        name = "Spec 2",
        desc = "Enables the timer when Talent Specialization 2 is active (only one spec active at a time).",
        get = function()
            return ST:get_class_table().enable_spec2 == true
        end,
        set = function(_, value)
            local cdb = ST:get_class_table()
            cdb.enable_spec2 = value and true or false
            if value then
                cdb.enable_spec1 = false
            end
            if ST.iter_hands and ST.handle_bar_visibility then
                for h in ST:iter_hands() do
                    ST:handle_bar_visibility(h)
                end
            end
        end,
        disabled = function()
            return not ST:get_class_table().class_enabled
        end,
    }
    self.opts_table.args.weave_range_enabled = {
        type = "toggle",
        order = 1.13,
        name = "Ranged distance bar",
        desc = "Show the standalone horizontal ranged-distance bar: it fills as the "..
            "distance to your attackable target closes to melee (full at 5 yd or "..
            "closer) and drains as the target moves away, labelling the exact distance "..
            "in yards plus MELEE / IN RANGE / OUT. It hides when there is no attackable "..
            "target or the client cannot answer a distance, so an empty bar means "..
            "unknown, never zero. ON by default for hunters (35 yd band, Auto Shot "..
            "range); every other class opts in here (30 yd band).",
        get = function()
            local class_db = ST:get_class_table()
            -- An explicit saved value wins in BOTH directions: true shows the bar,
            -- false hides it.
            if class_db.weave_range_enabled ~= nil then
                return class_db.weave_range_enabled == true
            end
            -- nil = the class's own shipped default (ON for hunters, off for everyone
            -- else), read from the defaults table so the two can never disagree.
            if type(ST.weave_range_default_enabled) ~= "function" then
                return false
            end
            return ST.weave_range_default_enabled(ST.player_class)
        end,
        set = function(_, value)
            ST:get_class_table().weave_range_enabled = value
        end,
        disabled = function()
            return not ST:get_class_table().class_enabled
        end,
    }
    self.opts_table.args.power_bar_enabled = {
        type = "toggle",
        order = 1.14,
        name = "Power bar",
        desc = "Show your primary resource under the bottom-most melee bar (offhand when "..
            "used, else mainhand): mana, rage, energy or focus as the client reports it. "..
            "The bar is the owning swing bar's width and 14 px tall by default. It hides "..
            "when no melee bar is visible or the client cannot answer the power read.",
        get = function()
            return ST:get_class_table().power_bar_enabled ~= false
        end,
        set = function(_, value)
            ST:get_class_table().power_bar_enabled = value and true or false
            if st.power_bar and type(st.power_bar.refresh) == "function" then
                st.power_bar.refresh(ST)
            end
        end,
        disabled = function()
            return not ST:get_class_table().class_enabled
        end,
    }
    self.opts_table.args.power_bar_height = {
        type = "range",
        order = 1.15,
        name = "Power bar height",
        desc = "Height of the power bar in pixels (default 14).",
        min = 10, max = 30, step = 1,
        get = function()
            return ST:get_class_table().power_bar_height or 14
        end,
        set = function(_, value)
            ST:get_class_table().power_bar_height = value
            if st.power_bar and type(st.power_bar.refresh) == "function" then
                st.power_bar.refresh(ST)
            end
        end,
        disabled = function()
            local db = ST:get_class_table()
            return not db.class_enabled or db.power_bar_enabled == false
        end,
    }
    self.opts_table.args.power_bar_text_enabled = {
        type = "toggle",
        order = 1.16,
        name = "Power bar value",
        desc = "Show the current power value in the bar.",
        get = function()
            return ST:get_class_table().power_bar_text_enabled ~= false
        end,
        set = function(_, value)
            ST:get_class_table().power_bar_text_enabled = value and true or false
            if st.power_bar and type(st.power_bar.refresh) == "function" then
                st.power_bar.refresh(ST)
            end
        end,
        disabled = function()
            local db = ST:get_class_table()
            return not db.class_enabled or db.power_bar_enabled == false
        end,
    }
    -- Class activation (main.lua: ST:activate_class). Operator order 2026-10-21:
    -- only the selected class's module executes. "Auto" (default) is the class being
    -- played; an explicit pick activates that class's module instead. The value is read
    -- at init, so a change applies at the next login/reload. Nil-safe: a stored false
    -- hides the widget, and nil reads as "Auto".
    self.opts_table.args.class_activation = {
        type = "select",
        order = 1.17,
        name = "Class module",
        desc = "Which class module SwedgeTimer activates. Auto (the default) activates the "..
            "class you are playing; picking a class activates that class's module instead. "..
            "Only the selected class is loaded - the others stay inert. Applies at the next "..
            "login or reload.",
        values = {
            Auto = "Auto (your class)",
            DRUID = "Druid",
            HUNTER = "Hunter",
            PALADIN = "Paladin",
            ROGUE = "Rogue",
            SHAMAN = "Shaman",
            WARRIOR = "Warrior",
        },
        sorting = { "Auto", "DRUID", "HUNTER", "PALADIN", "ROGUE", "SHAMAN", "WARRIOR" },
        get = function()
            local value = ST:get_class_table().class_activation
            if value == nil or value == false then
                return "Auto"
            end
            return value
        end,
        set = function(_, value)
            ST:get_class_table().class_activation = value
        end,
        hidden = function()
            return ST:get_class_table().class_activation == false
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

    -- Add behaviour panel: the scattered timer-behaviour toggles live here, not at
    -- top level (the panel shipped empty before 2026-10-19). Each moved widget keeps
    -- its live consumer - timers_locked -> main.lua lock/unlock + designmode.lua +
    -- hunter_ui.lua reads; diag_tick_counters -> diag.lua wrap_onupdate (~= true
    -- gate, config.lua false); enemy_swing_enabled -> enemy_swing.lua
    -- feature_enabled (== true gate, config.lua false). Per-hand visibility
    -- (show_behaviour/show_condition/require_in_range/dim_oor) stays in the hand
    -- panels: those keys live in the per-hand db tables and main.lua
    -- handle_bar_visibility reads them there, so a global copy would orphan.
    ST.behaviour_group = {
        name = "Behaviour",
        type = "group",
        desc = "Configure timer behaviour options.",
        order = 1.4,
        handler = ST.opts_funcs.global,
        args = {
            timers_locked = {
                type = "toggle",
                order = 1.1,
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
            },
            -- Enemy swing bar (enemy_swing.lua): the hostile-target swing bar, classic-line
            -- families only. Off by default; the driver reads the toggle live on its events.
            enemy_swing_enabled = {
                type = "toggle",
                order = 1.2,
                name = "Enemy swing bar",
                desc = "Track your hostile target's mainhand swing with a bar under the mainhand "..
                    "timer (classic-line clients only). Off by default.",
                get = "getter",
                set = "setter",
            },
            -- Diagnostics (diag.lua): per-tick budget counters. Off by default; the gate is
            -- decided at init, so the toggle applies at the next login/reload (see diag.lua's
            -- wrap_onupdate).
            diag_tick_counters = {
                type = "toggle",
                order = 1.3,
                name = "Diagnostic tick counters",
                desc = "Count the hand-bar OnUpdate ticks and measure their CPU time for /st diag. "..
                    "Applies at the next login or reload; off by default.",
                get = "getter",
                set = "setter",
            },
        },
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
                    -- Callable-guarded, not just nil-guarded: a partially loaded
                    -- designmode.lua leaves st.designmode without is_active, and a
                    -- throwing name blanks the whole Design Mode page in AceConfig.
                    if st.designmode and type(st.designmode.is_active) == "function"
                        and st.designmode.is_active() then
                        return "Stop Design Mode"
                    end
                    return "Start Design Mode"
                end,
                desc = "Toggle design mode. Also available as /st design; Esc ends it.",
                func = function()
                    if st.designmode and type(st.designmode.toggle) == "function" then
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
                    if st.designmode and type(st.designmode.refresh_grid) == "function" then
                        st.designmode.refresh_grid()
                    end
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
                    if st.designmode and type(st.designmode.refresh_grid) == "function" then
                        st.designmode.refresh_grid()
                    end
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
            design_mouse_anchor = {
                type = "toggle",
                order = 1.55,
                name = "Mouse-anchored dragging",
                desc = "Centre the dragged element on the cursor instead of preserving the grab "..
                    "offset; snapping still applies (Shift places it freely).",
                get = function()
                    return ST:get_class_table().design_mouse_anchor == true
                end,
                set = function(_, value)
                    ST:get_class_table().design_mouse_anchor = value
                end,
            },
            design_note = {
                type = "description",
                order = 1.6,
                name = "\nElements only exist while their module has built them - a class with no "..
                    "Cooldown HUD slots or a hidden practice panel will not offer one to position.",
            },
            hud_header = {
                type = "header",
                order = 2.0,
                name = "Cooldown HUD Quick Styling & Templates",
            },
            hud_desc = {
                type = "description",
                order = 2.01,
                name = "Choose a layout template or fine-tune HUD geometry and style live while positioning overlays.",
            },
            hud_template = {
                type = "select",
                order = 2.1,
                name = "HUD layout template",
                desc = "Load a curated HUD template for your class (Custom leaves current settings unchanged).",
                values = function()
                    local vals = { custom = "Custom" }
                    local class_token = ST.player_class
                    local class_tbl = class_token and ST[class_token]
                    local tmpls = class_tbl and class_tbl.HUD_TEMPLATES
                    if type(tmpls) == "table" then
                        for k, v in pairs(tmpls) do
                            vals[k] = v.label or k
                        end
                    end
                    return vals
                end,
                get = function()
                    local db = ST:get_class_table()
                    local stored = db and db.hud_template or nil
                    if type(stored) ~= "string" then
                        return "custom"
                    end
                    local class_token = ST.player_class
                    local class_tbl = class_token and ST[class_token]
                    local tmpls = class_tbl and class_tbl.HUD_TEMPLATES
                    local template = tmpls and tmpls[stored] or nil
                    if template == nil then
                        return "custom"
                    end
                    if hud_template_matches and hud_template_matches(db, template) then
                        return stored
                    end
                    return "custom"
                end,
                set = function(_, value)
                    local db = ST:get_class_table()
                    if not db then return end
                    if value == nil or value == "custom" then
                        db.hud_template = nil
                        return
                    end
                    local class_token = ST.player_class
                    local class_tbl = class_token and ST[class_token]
                    local tmpls = class_tbl and class_tbl.HUD_TEMPLATES
                    local template = tmpls and tmpls[value] or nil
                    if template == nil then
                        db.hud_template = nil
                        return
                    end
                    if type(template.slots) == "table" then
                        for slot_key, show in pairs(template.slots) do
                            db["hud_show_" .. slot_key] = show and true or false
                        end
                    end
                    if template.hud_icon_size ~= nil then
                        db.hud_icon_size = template.hud_icon_size
                    end
                    if template.hud_spacing ~= nil then
                        db.hud_spacing = template.hud_spacing
                    end
                    if template.hud_orientation ~= nil then
                        db.hud_orientation = template.hud_orientation
                    end
                    if template.hud_match_bar_width ~= nil then
                        db.hud_match_bar_width = template.hud_match_bar_width
                    end
                    db.hud_template = value
                    if st.hud and type(st.hud.apply_settings) == "function" then
                        st.hud.apply_settings(ST)
                    end
                    if st.designmode and type(st.designmode.refresh) == "function" then
                        st.designmode.refresh()
                    end
                end,
            },
            hud_orientation = {
                type = "select",
                order = 2.2,
                name = "Orientation",
                desc = "Arrange icons in a horizontal row or vertical column.",
                values = { horizontal = "Horizontal row", vertical = "Vertical column" },
                get = function()
                    local db = ST:get_class_table()
                    return (db and db.hud_orientation) or "horizontal"
                end,
                set = function(_, value)
                    local db = ST:get_class_table()
                    if db then db.hud_orientation = value end
                    if st.hud and type(st.hud.apply_settings) == "function" then
                        st.hud.apply_settings(ST)
                    end
                    if st.designmode and type(st.designmode.refresh) == "function" then
                        st.designmode.refresh()
                    end
                end,
            },
            hud_icon_size = {
                type = "range",
                order = 2.3,
                name = "Icon size",
                desc = "Size of each cooldown icon in pixels.",
                min = 16, max = 64, step = 1,
                get = function()
                    local db = ST:get_class_table()
                    return tonumber(db and db.hud_icon_size) or 36
                end,
                set = function(_, value)
                    local db = ST:get_class_table()
                    if db then db.hud_icon_size = value end
                    if st.hud and type(st.hud.apply_settings) == "function" then
                        st.hud.apply_settings(ST)
                    end
                    if st.designmode and type(st.designmode.refresh) == "function" then
                        st.designmode.refresh()
                    end
                end,
                disabled = function()
                    local db = ST:get_class_table()
                    return db and db.hud_match_bar_width and db.hud_orientation ~= "vertical"
                end,
            },
            hud_spacing = {
                type = "range",
                order = 2.4,
                name = "Icon spacing",
                desc = "Space between icons in pixels.",
                min = 0, max = 16, step = 1,
                get = function()
                    local db = ST:get_class_table()
                    return tonumber(db and db.hud_spacing) or 2
                end,
                set = function(_, value)
                    local db = ST:get_class_table()
                    if db then db.hud_spacing = value end
                    if st.hud and type(st.hud.apply_settings) == "function" then
                        st.hud.apply_settings(ST)
                    end
                    if st.designmode and type(st.designmode.refresh) == "function" then
                        st.designmode.refresh()
                    end
                end,
            },
            hud_match_bar_width = {
                type = "toggle",
                order = 2.5,
                name = "Match bar width",
                desc = "Automatically scale icon size so the horizontal row exactly spans the swing bar width.",
                get = function()
                    local db = ST:get_class_table()
                    return db and db.hud_match_bar_width == true
                end,
                set = function(_, value)
                    local db = ST:get_class_table()
                    if db then db.hud_match_bar_width = value end
                    if st.hud and type(st.hud.apply_settings) == "function" then
                        st.hud.apply_settings(ST)
                    end
                    if st.designmode and type(st.designmode.refresh) == "function" then
                        st.designmode.refresh()
                    end
                end,
                disabled = function()
                    local db = ST:get_class_table()
                    return db and db.hud_orientation == "vertical"
                end,
            },
            hud_scale = {
                type = "range",
                order = 2.6,
                name = "HUD overall scale",
                desc = "Scale multiplier applied to the entire Cooldown HUD.",
                min = 0.5, max = 2.0, step = 0.05,
                get = function()
                    local db = ST:get_class_table()
                    return tonumber(db and db.hud_scale) or 1.0
                end,
                set = function(_, value)
                    local db = ST:get_class_table()
                    if db then db.hud_scale = value end
                    if st.hud and type(st.hud.apply_settings) == "function" then
                        st.hud.apply_settings(ST)
                    end
                    if st.designmode and type(st.designmode.refresh) == "function" then
                        st.designmode.refresh()
                    end
                end,
            },
            hud_zoom = {
                type = "toggle",
                order = 2.7,
                name = "Zoomed / Borderless icons",
                desc = "Trim the 5% Blizzard outer icon border for a clean, modern edge-to-edge square look.",
                get = function()
                    local db = ST:get_class_table()
                    return db and db.hud_zoom ~= false
                end,
                set = function(_, value)
                    local db = ST:get_class_table()
                    if db then db.hud_zoom = value end
                    if st.hud and type(st.hud.apply_settings) == "function" then
                        st.hud.apply_settings(ST)
                    end
                end,
            },
        },
    }

    -- Add the Practice Mode page (practice.lua registry + practice_ui.lua session):
    -- the dedicated-page shape of the archived settings (settings_ui.lua
    -- "Guides & Practice" > "Practice Mode": Simulation / Boss fight /
    -- Rotation display / Fight timeline / Feedback). The toggle below is the
    -- same seam as the class panel's Start/Stop Practice and /st practice: one
    -- session, no new invocation. Drill rows mirror the archive Simulation /
    -- Boss-fight tabs with live consumers in practice_ui.lua; the paladin class
    -- panel keeps its own practice widgets untouched.
    ST.opts_table.args.practice = {
        name = "Practice",
        type = "group",
        desc = "Run class practice drills: simulated fights with graded attempts.",
        order = 1.46,
        args = {
            practice_desc = {
                type = "description",
                order = 1.0,
                name = "Class practice drills: fully simulated fights (no mana cost, no real "..
                    "casts) with graded attempts. Panel icons and keybinds cast simulated "..
                    "spells; the class panels drill their own technique - paladin seal-twist "..
                    "timing on the swing sim (plus the Avenging Wrath + Haste Pot / Seal of "..
                    "Blood macro window), hunter forced-move windows, shaman weave timing, "..
                    "rogue energy-pool timing (plus the Era SS-after-swing window), druid "..
                    "powershifts - while warrior grades live Execute-range entries with no "..
                    "sim of its own. Start here, from the class panel, or with /st practice.",
            },
            practice_toggle = {
                type = "execute",
                order = 1.1,
                name = function()
                    if st.practice_ui and type(st.practice_ui.is_active) == "function"
                        and st.practice_ui.is_active() then
                        return "Open Practice Panel"
                    end
                    return "Start Practice"
                end,
                desc = "Open the practice trainer (same session as /st practice and the class panel button). Closing options leaves the session running; only the practice panel's X stops it. A session can only be started out of combat.",
                func = function()
                    if st.practice_ui and type(st.practice_ui.open) == "function" then
                        st.practice_ui.open(ST)
                    elseif st.practice_ui and type(st.practice_ui.toggle) == "function" then
                        st.practice_ui.toggle(ST) -- half-loaded fallback
                    end
                end,
            },
            -- The practice mode (the shared engine lane): "class" is the shipped
            -- per-class session (the default - a fresh profile behaves exactly as
            -- before), "scenario" runs the class's rotation scenario and "drills"
            -- runs the class's focused drill list. The value is nil-safe: an
            -- unset or unknown value means the class session.
            practice_mode = {
                type = "select",
                order = 1.2,
                name = "Practice mode",
                desc = "Which practice session the Start/Stop toggle runs. "..
                    "Class session is the shipped per-class drill. "..
                    "Rotation scenario runs the class's own rotation end to end and grades the "..
                    "sequence you cast. Drill list shows the class's focused drills, one button "..
                    "each. A class that ships no scenario (or no drills) refuses that session "..
                    "with a clear message - it never falls back to another class's drill.",
                values = {
                    class = "Class session (default)",
                    scenario = "Rotation scenario",
                    drills = "Drill list",
                },
                get = function()
                    local mode = ST:get_class_table().practice_mode
                    if mode == "scenario" or mode == "drills" then
                        return mode
                    end
                    return "class"
                end,
                set = function(_, value)
                    ST:get_class_table().practice_mode = value
                end,
            },
            practice_mode_note = {
                type = "description",
                order = 1.21,
                name = function()
                    local pr = st.practice
                    local H = pr and pr.harness
                    if type(H) ~= "table" then
                        return "The practice engine is not available on this client."
                    end
                    local class_key = ST.player_class
                    local scenario = H.practice_scenario_available(class_key) and "yes" or "no"
                    local drills = H.practice_drills(class_key)
                    local count = drills and #drills or 0
                    local text = string.format(
                        "This class ships a rotation scenario: %s. Focused drills: %d.",
                        scenario, count)
                    -- The truth for the family the player is on: the rotation
                    -- scenario needs a LIVE swing engine (the rotation is timed
                    -- off the swing), and the client that keeps the inert
                    -- stand-in has none. The option must not advertise a session
                    -- the client cannot run.
                    local engine = ST.swing_engine
                    if type(engine) == "string" and engine == "inert-standin" then
                        text = text ..
                            " The rotation scenario cannot run on this client (no live swing engine)."
                    end
                    return text
                end,
            },
            practice_sim_header = {
                type = "header",
                order = 2.0,
                name = "Simulation",
            },
            practice_weapon_speed = {
                type = "range",
                order = 2.1,
                name = "Weapon speed override (s)",
                desc = "0 uses the equipped weapon speed.",
                min = 0, max = 4, step = 0.1,
                get = function()
                    return ST:get_class_table().practice_weapon_speed or 0
                end,
                set = function(_, value)
                    ST:get_class_table().practice_weapon_speed = value
                end,
            },
            practice_aw_includes_pot = {
                type = "toggle",
                order = 2.2,
                name = "AW macro: Haste Pot",
                desc = "When Avenging Wrath is cast, also activate Haste Potion automatically (no GCD). Simulates a /cast Avenging Wrath + /use Haste Potion macro. Off by default.",
                get = function()
                    return ST:get_class_table().practice_aw_includes_pot == true
                end,
                set = function(_, value)
                    ST:get_class_table().practice_aw_includes_pot = value
                end,
            },
            practice_aw_includes_sob = {
                type = "toggle",
                order = 2.3,
                name = "AW macro: Seal of Blood",
                desc = "When Avenging Wrath is cast, also cast Seal of Blood automatically if the GCD is free (arms a twist like a manual seal when Command is up). Simulates a /cast Avenging Wrath + /cast Seal of Blood macro. Off by default.",
                get = function()
                    return ST:get_class_table().practice_aw_includes_sob == true
                end,
                set = function(_, value)
                    ST:get_class_table().practice_aw_includes_sob = value
                end,
            },
            practice_dst_enabled = {
                type = "toggle",
                order = 2.4,
                name = "Dragonspine Trophy proc",
                desc = "Simulate Dragonspine Trophy: random chance on melee swing to gain haste (~1 PPM, 20 s ICD). Off by default.",
                get = function()
                    return ST:get_class_table().practice_dst_enabled == true
                end,
                set = function(_, value)
                    ST:get_class_table().practice_dst_enabled = value
                end,
            },
            practice_spell_queue_window = {
                type = "range",
                order = 2.5,
                name = "Spell queue window (ms)",
                desc = "Simulates WoW's spell queue window: a press inside this long before the GCD ends queues and fires when the GCD clears. 0 disables. Default 400 ms (WoW's SpellQueueWindow CVar).",
                min = 0, max = 400, step = 10,
                get = function()
                    return (tonumber(ST:get_class_table().practice_spell_queue_window) or 0.4) * 1000
                end,
                set = function(_, value)
                    ST:get_class_table().practice_spell_queue_window = value / 1000
                end,
            },
            practice_fight_header = {
                type = "header",
                order = 3.0,
                name = "Boss Fight",
            },
            practice_bl_delay = {
                type = "range",
                order = 3.1,
                name = "Bloodlust delay (s)",
                desc = "During a boss fight Bloodlust auto-fires after this many seconds. 0 fires on fight start.",
                min = 0, max = 120, step = 1,
                get = function()
                    return tonumber(ST:get_class_table().practice_bl_delay) or 0
                end,
                set = function(_, value)
                    ST:get_class_table().practice_bl_delay = value
                end,
            },
            practice_rotation_header = {
                type = "header",
                order = 4.0,
                name = "Rotation Display",
            },
            practice_rotation_desc = {
                type = "description",
                order = 4.1,
                name = "The rotation display shows during the session whenever the rotation "..
                    "resolves (Rotation: <name> plus step icons). Position is session-local; "..
                    "it always shows while a fight runs - no option ships for it.",
            },
            practice_timeline_header = {
                type = "header",
                order = 5.0,
                name = "Fight Timeline",
            },
            practice_timeline_desc = {
                type = "description",
                order = 5.1,
                name = "The fight timeline (WarcraftLogs-style cast log) always opens on fight "..
                    "start and persists for post-fight review. Position is session-local; it "..
                    "always shows - no option ships for it.",
            },
            practice_feedback_header = {
                type = "header",
                order = 6.0,
                name = "Feedback Text",
            },
            practice_result_duration = {
                type = "range",
                order = 6.1,
                name = "Result text duration (s)",
                desc = "How long the TWIST!/MISS popup stays on screen.",
                min = 0.3, max = 3.0, step = 0.1,
                get = function()
                    return ST:get_class_table().practice_result_duration or 0.8
                end,
                set = function(_, value)
                    ST:get_class_table().practice_result_duration = value
                end,
            },
            practice_result_text_size = {
                type = "range",
                order = 6.2,
                name = "Result text size",
                desc = "Font size of the TWIST!/MISS popup.",
                min = 12, max = 48, step = 1,
                get = function()
                    return ST:get_class_table().practice_result_text_size or 28
                end,
                set = function(_, value)
                    ST:get_class_table().practice_result_text_size = value
                    if st.practice_ui and type(st.practice_ui.update_result_font) == "function" then
                        st.practice_ui.update_result_font(ST)
                    end
                end,
            },
            practice_result_color_hit = {
                order = 6.3,
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
                order = 6.4,
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
        },
    }

    -- The Progress page (design spec §3): the practice progression read model, shown
    -- through description widgets whose name is a function, so the page always carries
    -- the live numbers. Nothing here writes progression DATA - the two exceptions are
    -- the explicit reset action at the bottom of the page and the badge visibility
    -- toggle below (a class-table setting, not progression data: it only decides
    -- whether the surface is drawn).
    --
    -- The numbers come from the pure modules' own read models
    -- (st.practice_progress.profile_snapshot + st.practice_stats.snapshot, wired by
    -- practice_progress_ui.lua), so the page can never disagree with the rules that
    -- produced the data. Every read is nil-safe: with no practice data the page shows
    -- "No practice data yet" instead of an error.
    --
    -- The helpers below are local to this function on purpose: the page owns no state
    -- of its own beyond the reset arming, which lives in practice_progress_ui.lua.
    local function progress_model(scope)
        local module = st.practice_progress_ui
        if type(module) ~= "table" then return nil end
        local reader = (scope == "account") and module.account_model or module.current_model
        if type(reader) ~= "function" then return nil end
        local ok, model = pcall(reader, ST)
        if not ok or type(model) ~= "table" then return nil end
        return model
    end
    local function progress_text(renderer, scope)
        local module = st.practice_progress_ui
        if type(module) ~= "table" then
            return "Practice progress is not available on this client."
        end
        if type(module[renderer]) ~= "function" then return "" end
        local model = progress_model(scope)
        if not model then return "Practice progress is not available on this client." end
        local ok, text = pcall(module[renderer], model)
        if not ok or type(text) ~= "string" then return "" end
        return text
    end
    -- Ask AceConfig to redraw the open page after a change the page itself made (the
    -- reset), so the description widgets pick up the new numbers straight away.
    local function ui_module_refresh()
        local module = st.practice_progress_ui
        if type(module) ~= "table" or type(module.notify_options_refresh) ~= "function" then
            return
        end
        module.notify_options_refresh()
    end

    ST.opts_table.args.progress = {
        name = "Progress",
        type = "group",
        desc = "Practice progression: level, XP, per-drill mastery, achievements and the "..
            "lifetime practice statistics.",
        order = 1.47,
        args = {
            progress_desc = {
                type = "description",
                order = 1.0,
                name = function()
                    local module = st.practice_progress_ui
                    if type(module) ~= "table" then
                        return "Practice progress is not available on this client."
                    end
                    return "Your practice progression for this class. XP, mastery and "..
                        "achievements are earned by running drills; they never gate a "..
                        "drill. The stats frame shows the full history, the accuracy "..
                        "sparkline and the per-class table."
                end,
            },
            progress_level = {
                type = "description",
                order = 1.1,
                name = function()
                    return progress_text("render_level")
                end,
            },
            progress_xp_bar = {
                type = "description",
                order = 1.2,
                name = function()
                    return progress_text("render_xp_bar")
                end,
            },
            progress_mastery_header = {
                type = "header",
                order = 2.0,
                name = "Drill mastery",
            },
            progress_mastery = {
                type = "description",
                order = 2.1,
                name = function()
                    return progress_text("render_mastery")
                end,
            },
            progress_achievements_header = {
                type = "header",
                order = 3.0,
                name = "Achievements",
            },
            progress_achievements = {
                type = "description",
                order = 3.1,
                name = function()
                    return progress_text("render_achievements")
                end,
            },
            progress_stats_header = {
                type = "header",
                order = 4.0,
                name = "Statistics",
            },
            progress_stats = {
                type = "description",
                order = 4.1,
                name = function()
                    return progress_text("render_stats")
                end,
            },
            progress_account = {
                type = "description",
                order = 4.2,
                name = function()
                    local account = progress_model("account")
                    if not account or not account.has_data then return "" end
                    local own = progress_model()
                    -- Only worth a second block when the account holds more than this
                    -- class does - other classes were played too.
                    if own and own.has_data
                        and own.stats.attempts >= account.stats.attempts then
                        return ""
                    end
                    local text = progress_text("render_stats", "account")
                    if text == "" then return "" end
                    return "All classes:\n" .. text
                end,
            },
            progress_open_stats = {
                type = "execute",
                order = 5.0,
                name = "Open the stats frame",
                desc = "Opens a separate window with the accuracy sparkline over the last "..
                    "50 sessions, the per-drill and per-class tables and the session history.",
                func = function()
                    local module = st.practice_progress_ui
                    if type(module) ~= "table" or type(module.open_frame) ~= "function" then
                        return
                    end
                    module.open_frame(ST)
                end,
            },
            -- The practice level badge (HU-9). The badge, the session XP bar and the
            -- level-up / achievement chat notices all ride ONE class-table key:
            -- practice_panel_badge (config_presets.lua ships it TRUE - the operator
            -- order of 2026-10-19, "start at lvl 1, gain xp each practice, level up",
            -- is the gate for that default-visible change).
            --
            -- Before this widget the key had NO widget anywhere, so with the surface
            -- visible by default there was no in-game way to turn it off (only a
            -- SavedVariables edit). The widget is the documented surface: the module
            -- owns the read (ui.badge_is_enabled, nil-safe == true) and the write
            -- (ui.set_badge_enabled, which writes the class table and redraws the
            -- badge), so a profile that turns the badge off KEEPS it off (the saved
            -- false wins over the default on the next load).
            --
            -- Nil-safe: with no practice_ui module loaded the getter reads false and
            -- the setter is a no-op, so a half-loaded addon never breaks the page.
            progress_badge = {
                type = "toggle",
                order = 5.1,
                name = "Show the practice level badge",
                desc = "Show the practice level badge under the practice panel, with the "..
                    "session XP bar and the level-up / achievement chat notices. Turning "..
                    "it off hides the surface and silences the notices; the progression "..
                    "data is still collected and saved.",
                get = function()
                    local module = st.practice_ui
                    if type(module) ~= "table" or type(module.badge_is_enabled) ~= "function" then
                        return false
                    end
                    local ok, on = pcall(module.badge_is_enabled, ST)
                    if not ok then return false end
                    return on == true
                end,
                set = function(_, value)
                    local module = st.practice_ui
                    if type(module) ~= "table" or type(module.set_badge_enabled) ~= "function" then
                        return
                    end
                    module.set_badge_enabled(ST, value == true)
                end,
            },
            progress_reset_header = {
                type = "header",
                order = 6.0,
                name = "Reset",
            },
            progress_reset = {
                type = "execute",
                order = 6.1,
                name = function()
                    local module = st.practice_progress_ui
                    if type(module) == "table" and type(module.reset_armed) == "function"
                        and module.reset_armed() then
                        return "Confirm: reset all practice progress"
                    end
                    return "Reset all practice progress"
                end,
                desc = "Erases every practice level, XP, drill mastery, achievement and saved "..
                    "session. Click once to arm it, then click again to confirm; the Cancel "..
                    "button disarms it. There is no undo.",
                func = function()
                    local module = st.practice_progress_ui
                    if type(module) ~= "table" or type(module.request_reset) ~= "function" then
                        return
                    end
                    module.request_reset(ST)
                    ui_module_refresh()
                end,
            },
            progress_reset_cancel = {
                type = "execute",
                order = 6.2,
                name = "Cancel the reset",
                hidden = function()
                    local module = st.practice_progress_ui
                    if type(module) ~= "table" or type(module.reset_armed) ~= "function" then
                        return true
                    end
                    return not module.reset_armed()
                end,
                func = function()
                    local module = st.practice_progress_ui
                    if type(module) ~= "table" or type(module.disarm_reset) ~= "function" then
                        return
                    end
                    module.disarm_reset()
                    ui_module_refresh()
                end,
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
    -- Melee pair height routing (operator order 2026-10-28; brief L3). While the class-level
    -- pair height (bars.lua: ST:melee_pair_height) is set, the mainhand and the offhand
    -- RENDER at it, so their per-hand Height widget must show and edit THAT value: the
    -- hand's own saved bar_height is kept untouched (it applies again once the pair clears)
    -- and a widget that still showed or wrote it would be lying. With NO pair height the
    -- OFFHAND still renders at the mainhand's height (the size invariant in bars.lua), so
    -- its widget shows and edits the MAINHAND key - the offhand's own height key never
    -- sizes the bar. The ranged hand is never part of either rule. Nil-safe: no bars.lua
    -- (a sandbox) means no routing, as shipped.
    local function pair_height()
        if type(ST.melee_pair_height) ~= "function" then
            return nil
        end
        return ST:melee_pair_height()
    end

    -- The effective height of one melee hand: the pair when set, else the mainhand's key for
    -- the offhand, else the hand's own key.
    local function effective_height(hand_token, hands)
        if hand_token == "mainhand" or hand_token == "offhand" then
            local pair = pair_height()
            if pair ~= nil then
                return pair
            end
        end
        if hand_token == nil then
            -- The multi-hand groups: follow their first melee hand, if any.
            for i = 1, #(hands or {}) do
                local h = hands[i]
                if h == "mainhand" or h == "offhand" then
                    hand_token = h
                    break
                end
            end
        end
        if hand_token == "offhand" then
            local mainhand = ST:get_hand_table("mainhand")
            if type(mainhand) == "table" and type(mainhand.bar_height) == "number" then
                return mainhand.bar_height
            end
            return nil
        end
        if hand_token == "mainhand" then
            local mainhand = ST:get_hand_table("mainhand")
            return type(mainhand) == "table" and mainhand.bar_height or nil
        end
        return nil
    end

    local function hands_include_melee(hands)
        if type(hands) ~= "table" then
            return false
        end
        for i = 1, #hands do
            if hands[i] == "mainhand" or hands[i] == "offhand" then
                return true
            end
        end
        return false
    end

    for hand, settings in pairs(ST.opts_case_dict) do
        ST.opts_funcs[hand] = {}
        local melee_group = hands_include_melee(settings.hands)

        -- A generic getter func for each hand
        if hand == "mainhand" or hand == "offhand" or hand == "ranged" then
            ST.opts_funcs[hand].getter = function(_, info)
                local key = info[#info]
                if key == "bar_height" and melee_group then
                    local effective = effective_height(hand, settings.hands)
                    if effective ~= nil then
                        return effective
                    end
                end
                local db = ST:get_hand_table(hand)
                return db[key]
            end
        else
            -- Just default to the mainhand for the all_bars func.
            ST.opts_funcs[hand].getter = function(_, info)
                local key = info[#info]
                if key == "bar_height" and melee_group then
                    local effective = effective_height(nil, settings.hands)
                    if effective ~= nil then
                        return effective
                    end
                end
                local db = ST:get_hand_table("mainhand")
                return db[key]
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

        -- A setter for the per-hand Enabled toggle: writes the value, then
        -- builds the hand's frames on enable (HU-22 lazy bars: a bar switched
        -- on mid-session appears without a reload). Never builds on disable.
        -- Nil-safe when the build seam is absent (suites that stub main.lua).
        ST.opts_funcs[hand].enabled_setter = function(_, info, value)
            for h in ST:generic_iter(settings.hands) do
                local db = ST:get_hand_table(h)
                db[info[#info]] = value
                if value and type(ST.bring_up_hand) == "function" then
                    ST:bring_up_hand(h)
                end
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
            local key = info[#info]
            local pair = melee_group and pair_height() or nil
            for h in ST:generic_iter(settings.hands) do
                -- A bar_height write is routed to whatever actually sizes that bar:
                --   * a set pair height owns BOTH melee hands (write the pair key);
                --   * with no pair, the offhand renders at the mainhand's height, so a
                --     write aimed at the offhand lands on the mainhand key (the offhand's
                --     own key never sizes it);
                --   * everything else - the ranged hand included - writes its own key.
                local to_pair = key == "bar_height" and pair ~= nil
                    and (h == "mainhand" or h == "offhand")
                local to_mainhand = key == "bar_height" and pair == nil
                    and (h == "offhand" or (hand == "offhand" and h == "mainhand"))
                if to_pair then
                    ST:get_class_table().melee_bar_height = value
                elseif to_mainhand then
                    local mainhand = ST:get_hand_table("mainhand")
                    if type(mainhand) == "table" then
                        mainhand.bar_height = value
                    end
                else
                    local db = ST:get_hand_table(h)
                    db[key] = value
                end
            end
            -- A routed write can land on another hand than the panel's, so re-apply the whole
            -- class hand set (the mainhand pass also cascades to the built offhand).
            for h in ST:generic_iter(ST:get_class_hands()) do
                ST:configure_bar_size_and_positions(h)
                ST:configure_bar_appearances(h)
                ST:configure_bar_outline(h)
                ST:configure_gcd_markers(h)
                ST:set_gcd_marker_positions(h)
                ST:configure_deadzone(h)
                ST:set_deadzone_width(h)
            end
        end

        -- A setter for theme presets (visual brainstorm item 3)
        ST.opts_funcs[hand].theme_preset_setter = function(_, info, value)
            for h in ST:generic_iter(settings.hands) do
                local db = ST:get_hand_table(h)
                if value == "custom" or value == nil then
                    db.theme_preset = nil
                else
                    local preset = ST.THEME_PRESETS and ST.THEME_PRESETS[value]
                    if preset then
                        db.theme_preset = value
                        if preset.bar_texture_key then db.bar_texture_key = preset.bar_texture_key end
                        if preset.background_color then db.background_color = {unpack(preset.background_color)} end
                        if preset.border_color then db.border_color = {unpack(preset.border_color)} end
                        if preset.border_width then db.border_width = preset.border_width end
                        if preset.show_spark ~= nil then db.show_spark = preset.show_spark end
                        if preset.spark_color then db.spark_color = {unpack(preset.spark_color)} end
                        if preset.enable_flash ~= nil then db.enable_flash = preset.enable_flash end
                        if preset.flash_color then db.flash_color = {unpack(preset.flash_color)} end
                    end
                end
                ST:configure_bar_appearances(h)
                ST:configure_bar_outline(h)
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
        if st.hud and type(st.hud.apply_settings) == "function" then
            st.hud.apply_settings(ST)
        end
    end

    ST.class_getsetters.color_getter = function(_, info)
        local db = ST:get_class_table()
        local color_table = db[info[#info]]
        return ST:convert_color(color_table)
    end

    ST.class_getsetters.color_setter = function(_, info, r, g, b, a)
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
-- per class. The HUD master hud_enabled ships true in the shared defaults
-- (owner order 2026-10-19 on-by-default package, pinned in
-- tests/options_load_state.lua §17); rotation_label_enabled still ships false,
-- so only the label waits for its toggle.
--
-- slot_toggles is an array of { key = "hud_show_<slot>", name = "...",
-- desc = "..." } mirroring the class's HUD_SLOTS keys/titles; hud_desc,
-- glow_desc and format_desc carry the class-specific copy.
local function hud_rotation_widgets(slot_toggles, hud_desc, glow_desc, format_desc, format_values)
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
            name = "Lock HUD frame",
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
            name = "Lock label frame",
            desc = "Prevent dragging the label. While unlocked the label stays visible so it can be positioned.",
            get = "getter",
            set = "setter",
        },
        rotation_label_visibility_key = {
            type = "select",
            order = 9.12,
            name = "Show label",
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
            values = format_values or { key = "2/3", labelled = "Rotation: 2/3", steps = "CS, Twist, Twist", both = "2/3  -  CS, Twist, Twist" },
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
                if st.rotation_text and type(st.rotation_text.set_align) == "function" then
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
            name = "Label color",
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

-- HUD layout templates (bench/hud_templates_2026-10-19.md §7): one select per
-- class that loads a curated slot + geometry set from ST.<CLASS>.HUD_TEMPLATES
-- (config_presets.lua) through the normal db keys. The HUD's own tick notices
-- the db change (layout_changed -> apply_settings, hud.lua:1141-1144), so the
-- setter writes keys only — no new widget API, no hud.lua call.
--
-- Nil-safe: a nil hud_template, or a stored id with no table, reads as Custom
-- (Custom leaves everything untouched — zero default-visible change). Picking
-- Custom stores nil and writes nothing else. Picking a template writes its
-- full slot set (explicit true/false per key, so switching templates never
-- leaves a stale slot on) plus its four geometry keys, then stores the id.
--
-- Dirty-detect is derived state, not a setter chain: get returns the stored id
-- only while the db still matches that template's set; any manual
-- toggle/geometry tweak reads back as Custom (reselect to re-apply).
hud_template_matches = function(db, template)
    if type(db) ~= "table" or type(template) ~= "table" then
        return false
    end
    local slots = template.slots
    if type(slots) ~= "table" then
        return false
    end
    for slot_key, show in pairs(slots) do
        local want = show and true or false
        local got = db["hud_show_" .. slot_key] and true or false
        if got ~= want then
            return false
        end
    end
    if db.hud_icon_size ~= template.hud_icon_size then
        return false
    end
    if db.hud_spacing ~= template.hud_spacing then
        return false
    end
    if db.hud_orientation ~= template.hud_orientation then
        return false
    end
    local want_match = template.hud_match_bar_width and true or false
    local got_match = db.hud_match_bar_width and true or false
    return got_match == want_match
end

local function hud_template_widget(class_token, values)
    return {
        type = "select",
        order = 8.02,
        name = "Layout template",
        desc = "Load a curated slot + size set in one click (Custom, the default, "..
            "leaves everything as-is). Picking a template writes its slots and "..
            "geometry to the normal options below and remembers the pick; any "..
            "manual tweak after that reads back as Custom — reselect to re-apply. "..
            "Drag the unlocked frame in /st design to place the row.",
        values = values,
        get = function()
            local db = ST:get_class_table()
            local stored = db and db.hud_template or nil
            if type(stored) ~= "string" then
                return "custom"
            end
            local class_tbl = ST[class_token]
            local templates = class_tbl and class_tbl.HUD_TEMPLATES or nil
            local template = templates and templates[stored] or nil
            if template == nil then
                return "custom"
            end
            if hud_template_matches(db, template) then
                return stored
            end
            return "custom"
        end,
        set = function(_, value)
            local db = ST:get_class_table()
            if not db then
                return
            end
            if value == nil or value == "custom" then
                db.hud_template = nil
                return
            end
            local class_tbl = ST[class_token]
            local templates = class_tbl and class_tbl.HUD_TEMPLATES or nil
            local template = templates and templates[value] or nil
            if template == nil then
                db.hud_template = nil
                return
            end
            if type(template.slots) == "table" then
                for slot_key, show in pairs(template.slots) do
                    db["hud_show_" .. slot_key] = show and true or false
                end
            end
            if template.hud_icon_size ~= nil then
                db.hud_icon_size = template.hud_icon_size
            end
            if template.hud_spacing ~= nil then
                db.hud_spacing = template.hud_spacing
            end
            if template.hud_orientation ~= nil then
                db.hud_orientation = template.hud_orientation
            end
            if template.hud_match_bar_width ~= nil then
                db.hud_match_bar_width = template.hud_match_bar_width
            end
            db.hud_template = value
        end,
    }
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
            name = "Enable seal colors",
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
            name = "Enable Art of War glow",
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
        aow_exo_pulse_enabled = {
            type = "toggle",
            order = 2.22,
            name = "AoW+Exo overlap pulse",
            desc = "Pulse the bar on each transition to Art of War up with Exorcism ready "..
                "(the Require Exorcism Ready gate applies).",
            get = "getter",
            set = "setter",
        },
        aow_glow_color = {
            order=2.3,
            type="color",
            name="Art of War glow color",
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
        tracker_header = {
            type = "header",
            order = 2.7,
            name = "Judgement & Cooldowns",
        },
        tracker_desc = {
            order = 2.71,
            type = "description",
            name = "Target and cooldown trackers: the target's Judgement of the Crusader "..
                "remaining time and a row of your own cooldowns beside the bar.",
        },
        jotc_bar_enabled = {
            type = "toggle",
            order = 2.72,
            name = "Judgement of the Crusader bar",
            desc = "Show a mini-bar with the target's Judgement of the Crusader remaining "..
                "time (your melee swings refresh the max rank).",
            get = "getter",
            set = "setter",
        },
        cd_icons_enabled = {
            type = "toggle",
            order = 2.73,
            name = "Cooldown icon row",
            desc = "Show your cooldowns (Avenging Wrath, Divine Shield, Hammer of Justice, "..
                "Hand of Protection, Holy Wrath, Lay on Hands, racial) beside the bar, "..
                "glowing in the final 4 seconds.",
            get = "getter",
            set = "setter",
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
            name = "Twist attempt flash",
            desc = "Flash the bar while two seals are active on the swing; the floating text has its own toggle below (Success text).",
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.twist_enabled
            end,
        },
        twist_score_enabled = {
            type = "toggle",
            order = 3.41,
            name = "Twist hit-rate badge",
            desc = "Show your twist hit rate (N% (S/A)) below the bar in combat.",
            get = "getter",
            set = "setter",
        },
        twist_score_persist = {
            type = "toggle",
            order = 3.42,
            name = "Keep hit rate across sessions",
            desc = "Restore and mirror the twist hit-rate counts in your profile instead "..
                "of resetting them each session.",
            get = "getter",
            set = "setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.twist_score_enabled
            end,
        },
        twist_lust_override_enabled = {
            type = "toggle",
            order = 3.43,
            name = "Narrow window during Bloodlust/Heroism",
            desc = "Narrow the twist window while Bloodlust or Heroism is up (TBC and later).",
            get = "getter",
            set = "setter",
        },
        reseal_marker_enabled = {
            type = "toggle",
            order = 3.44,
            name = "Reseal marker",
            desc = "Show a marker at the swing position where the global cooldown clears, "..
                "so reseal timing reads against the twist window (off by default).",
            get = "getter",
            set = "setter",
        },
        -- Mana-sustain governor (the engine plug reads db.twist_mana_threshold_pct
        -- nil-safe at classes/paladin.lua:3281-3285; nextaction.lua:556-557 keeps the
        -- reseal's mana and rides the swing below it). Nil-safe getter: a fresh profile
        -- renders 0 = off (AceConfigDialog feeds get straight into Slider:SetValue,
        -- which errors on nil), never an empty slider; 0 behaves as off because
        -- mana_pct never reads below 0. The shipped default is 0 (the documented OFF
        -- state - config_presets.lua carries the reason and the citation).
        mana_header = {
            type = "header",
            order = 3.46,
            name = "Mana Governor",
        },
        twist_mana_threshold_pct = {
            type = "range",
            order = 3.47,
            name = "Twist mana threshold (%)",
            desc = "Skip the twist reseal and ride the swing instead while mana sits below "..
                "this percentage. 0 disables the governor (archived behaviour).",
            min = 0, max = 100, step = 1,
            get = function()
                local v = ST:get_class_table().twist_mana_threshold_pct
                if type(v) == "number" and v == v then
                    return v
                end
                return 0
            end,
            set = "setter",
        },
        twist_color_twisting = {
            order=3.5,
            type="color",
            name="Twist armed color",
            desc="Color to use when a seal twist is armed or attempted.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },
        twist_color_cant = {
            order=3.6,
            type="color",
            name="Twist impossible color",
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
            disabled = function()
                local db = ST:get_class_table()
                return not db.twist_enabled
            end,
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
        seal_tracker_header = {
            type = "header",
            order = 3.984,
            name = "Seal & Judgement Trackers",
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
            name = "Impossible-twist warning",
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
                "latency. Dynamic uses the lag calibration values above; Fixed uses the offset below; None disables the padding.",
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
            name = "Lock guide frame",
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
                return tostring(ST:get_class_table().nextaction_x or 127)
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
                return tostring(ST:get_class_table().nextaction_y or -65)
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
            name = "Show frame title",
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
                "simulated spells (left click); /st practice toggles the session. Only weapon speed, result styling and panel position ship as options; rotation lock, haste buttons and keybinds are still in development.",
        },
        practice_toggle = {
            type = "execute",
            order = 7.1,
            name = function()
                if st.practice_ui and type(st.practice_ui.is_active) == "function"
                    and st.practice_ui.is_active() then
                    return "Open Practice Panel"
                end
                return "Start Practice"
            end,
            desc = "Open the practice trainer. Closing options leaves the session running; only the practice panel's X stops it. A session can only be started out of combat.",
            func = function()
                if st.practice_ui and type(st.practice_ui.open) == "function" then
                    st.practice_ui.open(ST)
                elseif st.practice_ui and type(st.practice_ui.toggle) == "function" then
                    st.practice_ui.toggle(ST) -- half-loaded fallback
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
                if st.practice_ui and type(st.practice_ui.update_result_font) == "function" then
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
                -- Re-anchor through the panel's own position applier (practice_ui.lua
                -- apply_settings re-reads the offsets above; combat-lockdown defers
                -- it internally), mirroring the update_result_font seam above.
                if st.practice_ui and type(st.practice_ui.apply_settings) == "function" then
                    st.practice_ui.apply_settings(ST)
                end
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
        -- Layout template (bench/hud_templates_2026-10-19.md §7): curated sets
        -- from ST.PALADIN.HUD_TEMPLATES, applied on explicit pick only
        -- (nil = Custom, writes nothing).
        -- Gallery shortlist 3: Core rows are the Luxthos Era-line visual-check target.
        hud_template = hud_template_widget("PALADIN", {
            custom = "Custom",
            twist_core = "P-T1 Twist Core",
            full_ret = "P-T2 Full Ret + Trinkets",
            minimal = "P-T3 Minimal",
        }),
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
            name = "Lock HUD frame",
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
        -- SoD/shockadin mirror slots (descriptors + provider in
        -- classes/paladin.lua:3396-3409/:3657-3774; defaults ship on in
        -- ST.PALADIN.defaults, templates in ST.PALADIN.HUD_TEMPLATES).
        -- Gallery bench/paladin_styles_2026-10-19.md §0: SoD-native slots
        -- extend P-T2, not P-T1.
        hud_show_soc = {
            type = "toggle",
            order = 8.48,
            name = "Seal of Command",
            desc = "Show the Seal of Command icon (active seal shows its aura).",
            get = "getter",
            set = "setter",
        },
        hud_show_sob = {
            type = "toggle",
            order = 8.49,
            name = "Seal of Blood",
            desc = "Show the Seal of Blood icon (Wrath: Divine Storm, with its cooldown swipe).",
            get = "getter",
            set = "setter",
        },
        hud_show_how = {
            type = "toggle",
            order = 8.50,
            name = "Hammer of Wrath",
            desc = "Show the Hammer of Wrath icon (glows in combat inside Execute range).",
            get = "getter",
            set = "setter",
        },
        hud_show_holy_shock = {
            type = "toggle",
            order = 8.51,
            name = "Holy Shock",
            desc = "Show the Holy Shock icon (SoD shockadin only; hidden where unknown).",
            get = "getter",
            set = "setter",
        },
        hud_show_aura_mastery = {
            type = "toggle",
            order = 8.52,
            name = "Aura Mastery",
            desc = "Show the Aura Mastery icon (SoD shockadin only; hidden where unknown).",
            get = "getter",
            set = "setter",
        },
        -- The WotLK APL's UTILITY BAND (bench/paladin_apl_utility_build_2026-10-20.md
        -- §2): the two display-only mirrors (descriptors + provider in
        -- classes/paladin.lua's HUD_SLOTS + get_hud_state). Consumers:
        -- classes/paladin.lua's provider reads hud_show_<key> == true (nil = off)
        -- - the druid Claw shape, so both ship false in ST.PALADIN.defaults and a
        -- fresh profile's HUD row is unchanged. WotLK only: the provider's family
        -- gate hides both on every other client.
        hud_show_hor = {
            type = "toggle",
            order = 8.53,
            name = "Hand of Reckoning",
            desc = "Show the Hand of Reckoning icon (with its cooldown swipe; WotLK only).",
            get = "getter",
            set = "setter",
        },
        hud_show_how_wrath = {
            type = "toggle",
            order = 8.54,
            name = "Hammer of Wrath (WotLK)",
            desc = "Show the WotLK Hammer of Wrath icon (with its cooldown swipe; greys above "
                .. "20 % target health, WotLK only).",
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
            name = "Lock label frame",
            desc = "Prevent dragging the label. While unlocked the label stays visible so it can be positioned.",
            get = "getter",
            set = "setter",
        },
        rotation_label_visibility_key = {
            type = "select",
            order = 9.12,
            name = "Show label",
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
                if st.rotation_text and type(st.rotation_text.set_align) == "function" then
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
            name = "Label color",
            desc = "Colour of the label.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
        },

        -- Sim reference (wowsims): text-only, no clickability (WoW cannot open
        -- external links, so the URLs below are display text, not buttons).
        -- The Next Action Guide practices the sim rotation in-game: twist
        -- windows, Crusader Strike timing and filler gating follow the sim
        -- numbers where sourced (see bench/paladin_rotation_audit_2026-10-19.md).
        wowsims_header = {
            type = "header",
            order = 10.0,
            name = "Sim Reference",
        },
        wowsims_desc = {
            order = 10.01,
            type = "description",
            name = "Rotation numbers follow the wowsims sims: https://github.com/wowsims/classic, "..
                "https://github.com/wowsims/sod, https://github.com/wowsims/tbc-new, "..
                "https://github.com/wowsims/forever (Wrath has no in-scope sim; "..
                "that row is Wowhead-guide-derived). Practice the sim in-game: "..
                "enable the guide above and run its prompts against the sim APL.",
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
            "activated when Improved Defensive Stance is talented). Talent detection is a heuristic; verify in-client.",
            get = "getter",
            set = "setter",
        },
        hide_in_arms_spec = {
            type = "toggle",
            order = 0.82,
            name = "Hide when Arms",
            desc = "When enabled, the timer will hide when the Warrior is in Arms spec ("..
            "activated when Bladestorm is talented). Talent detection is a heuristic; verify in-client.",
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
            name="Heroic Strike color",
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
            name="Cleave color",
            desc="Color to use when Cleave is queued.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.enable_cleave_color
            end,
        },
        rage_desc = {
            order = 1.5,
            type = "description",
            name = "If either of the above are enabled, the mainhand timer bar will turn a certain color when the player "..
                "has queued an on-next-attack ability, but has since dropped below the rage threshold necessary "..
                "to use the ability."
        },
        insufficient_rage_color = {
            order=1.6,
            type="color",
            name="Queued-but-unaffordable color",
            desc="Color while a queued Heroic Strike / Cleave sits above your current rage.",
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
            name = "Enable Bloodsurge glow",
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
            order = 3.10,
            name = "Deep Wounds bar",
            desc = "Show your own Deep Wounds bleed duration on the current target above "..
                "the mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        warrior_deep_wounds_bar_color = {
            order=3.11,
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
            order = 3.12,
            name = "Sunder Armor bar",
            desc = "Show your own Sunder Armor duration and stack count (1-5) on the "..
                "current target above the mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        warrior_sunder_armor_bar_color = {
            order=3.13,
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
            order = 3.14,
            name = "Rend bar",
            desc = "Show your own Rend duration on the current target above the mainhand "..
                "bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        warrior_rend_bar_color = {
            order=3.15,
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
            order = 3.16,
            name = "Thunder Clap bar",
            desc = "Show your own Thunder Clap duration on the current target above the "..
                "mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        warrior_thunder_clap_bar_color = {
            order=3.17,
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
            order = 3.18,
            name = "Demo Shout bar",
            desc = "Show your own Demoralizing (Demolition) Shout duration on the current "..
                "target above the mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        warrior_demo_shout_bar_color = {
            order=3.19,
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
            order = 3.20,
            name = "Shield Block bar",
            desc = "Show a 4 px Shield Block duration bar with its icon above the "..
                "mainhand bar while the buff is active.",
            get = "getter",
            set = "setter",
        },
        warrior_shield_block_bar_color = {
            order=3.21,
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
            order = 3.22,
            name = "Slam cast bar",
            desc = "Show a small Slam cast-progress bar above the mainhand bar while "..
                "casting Slam.",
            get = "getter",
            set = "setter",
        },
        show_warrior_overpower_flash = {
            type = "toggle",
            order = 3.23,
            name = "Overpower proc flash",
            desc = "Pulse a gold border and an OP marker around the mainhand bar while "..
                "an Overpower proc window is open (armed when your attack is dodged).",
            get = "getter",
            set = "setter",
        },
        show_warrior_rampage_badge = {
            type = "toggle",
            order = 3.24,
            name = "Rampage badge",
            desc = "Show the Rampage stack count and refresh window beside the mainhand "..
                "bar while the buff is live.",
            get = "getter",
            set = "setter",
        },
        show_warrior_bank_cue = {
            type = "toggle",
            order = 3.25,
            name = "Queued-ability BANK cue",
            desc = "Show an amber edge and a centred BANK label while a queued "..
                "on-next-attack ability is unaffordable in combat.",
            get = "getter",
            set = "setter",
        },
        show_warrior_battle_shout_badge = {
            type = "toggle",
            order = 3.26,
            name = "Battle Shout badge",
            desc = "Show your Battle Shout's remaining time beside the bar.",
            get = "getter",
            set = "setter",
        },
        show_warrior_desync_alert = {
            type = "toggle",
            order = 3.27,
            name = "Offhand desync spark",
            desc = "Show a spark where the offhand will land while mainhand and offhand swings are desynced (off by default).",
            get = "getter",
            set = "setter",
        },
        show_warrior_commanding_suppression = {
            type = "toggle",
            order = 3.28,
            name = "Commanding suppression",
            desc = "While Commanding Shout covers Battle Shout, hide the Battle Shout "..
                "badge and show the Commanding countdown instead (off by default).",
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
            name = "On-screen rotation prompt (on by default): the next ability to press "..
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
            name = "Lock guide frame",
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
                return tostring(ST:get_class_table().nextaction_x or 127)
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
                return tostring(ST:get_class_table().nextaction_y or -65)
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
            order = 4.131,
            name = "Execute range (%)",
            desc = "Suggest Execute while the target is below this health percentage.",
            min = 5, max = 35, step = 1,
            get = "getter",
            set = "setter",
        },
        -- Forever Rend upkeep (W-15 / bench/class_features_drills_2026-10-19.md:292:
        -- "Rend upkeep (SoD 11574 + rune 412507; Forever 11574 toggle <= 3 s)"; the
        -- Forever APL's Rend-weave group is toggle-gated). The pure rule is LIVE -
        -- warrior_guide.lua's should_maintain_rend_outside_arms with
        -- REND_REFRESH_DEFAULT = 3, wired into rule R - but the provider feeds
        -- rend_upkeep_enabled only on SoD (Blood Frenzy rune 412507 known), so the
        -- rule is dormant on the Forever client.
        --
        -- This widget owns the KEY; the provider read that carries it into the guide
        -- inputs is the FILED line (classes/warrior.lua:3049-3053 - the warrior
        -- lane's file). Nil-safe: the key is read as == true, so nil and false both
        -- leave the rule dormant. OFF by default (no default entry ships in
        -- config_presets.lua) - the rule has never run on Forever, and arming it
        -- needs a deliberate choice, not a fresh profile.
        guide_forever_rend_upkeep = {
            type = "toggle",
            order = 4.132,
            name = "Forever Rend upkeep",
            desc = "Prompt the Rend upkeep on the WoW Forever client: the Forever APL's "..
                "Rend-weave group re-applies Rend while the debuff has 3 seconds or fewer "..
                "left. Off by default - the rule stays dormant while it is off.",
            get = function()
                return ST:get_class_table().guide_forever_rend_upkeep == true
            end,
            set = function(_, value)
                ST:get_class_table().guide_forever_rend_upkeep = (value == true)
            end,
        },
        -- Practice (the archive's Guides & Practice page shape, warrior entry):
        -- the shared practice session every class shares, started both ways
        -- (this toggle or /st practice), plus the warrior Execute drill report
        -- below. The report grades live Execute entries through the practice
        -- harness: no sim session, no panel casts - fight a target and every
        -- crossing into Execute range logs the rage pooled at the entry. No new
        -- db keys: every widget reads nil-safe with the shipped paladin
        -- defaults below, and the report stays hidden until opened (nil = off).
        practice_header = {
            type = "header",
            order = 5.0,
            name = "Execute Practice",
        },
        practice_desc = {
            order = 5.05,
            type = "description",
            name = "Execute-phase drill plus the shared practice session: the toggle below (or "..
                "/st practice) starts and stops the shared session, while the Execute report "..
                "below grades live Execute-range entries with no session of its own - fight a "..
                "target and every crossing into Execute range logs the rage pooled at the entry. "..
                "Only weapon speed, result styling and panel position ship as options.",
        },
        practice_toggle = {
            type = "execute",
            order = 5.1,
            name = function()
                -- Callable-guarded, not just nil-guarded: a partially loaded
                -- practice_ui.lua leaves st.practice_ui without is_active, and a
                -- throwing name blanks the whole options page in AceConfig.
                if st.practice_ui and type(st.practice_ui.is_active) == "function"
                    and st.practice_ui.is_active() then
                    return "Open Practice Panel"
                end
                return "Start Practice"
            end,
            desc = "Open the practice trainer. Closing options leaves the session running; only the practice panel's X stops it. A session can only be started out of combat.",
            func = function()
                if st.practice_ui and type(st.practice_ui.open) == "function" then
                    st.practice_ui.open(ST)
                elseif st.practice_ui and type(st.practice_ui.toggle) == "function" then
                    st.practice_ui.toggle(ST) -- half-loaded fallback
                end
            end,
        },
        practice_weapon_speed = {
            type = "range",
            order = 5.2,
            name = "Weapon speed override (s)",
            desc = "0 uses the equipped weapon speed.",
            min = 0, max = 4, step = 0.1,
            get = function()
                return ST:get_class_table().practice_weapon_speed or 0
            end,
            set = "setter",
        },
        -- Practice result feedback and panel placement. Every widget reads the
        -- archived practice_result_* / practice_panel_* keys nil-safe (the
        -- paladin defaults stand in until set); the session UI (practice_ui.lua)
        -- owns the same fallbacks, so the options and the panel round-trip in
        -- both directions. The two result colours are stored in the 0-1 range
        -- the result popup paints with (SetTextColor), NOT the shared 0-255
        -- convention, so they use direct get/set functions.
        practice_result_duration = {
            type = "range",
            order = 5.3,
            name = "Result text duration (s)",
            desc = "How long the result popup stays on screen.",
            min = 0.3, max = 3.0, step = 0.1,
            get = function()
                return ST:get_class_table().practice_result_duration or 0.8
            end,
            set = "setter",
        },
        practice_result_text_size = {
            type = "range",
            order = 5.31,
            name = "Result text size",
            desc = "Font size of the result popup.",
            min = 12, max = 48, step = 1,
            get = function()
                return ST:get_class_table().practice_result_text_size or 28
            end,
            set = function(_, value)
                ST:get_class_table().practice_result_text_size = value
                if st.practice_ui and type(st.practice_ui.update_result_font) == "function" then
                    st.practice_ui.update_result_font(ST)
                end
            end,
        },
        practice_result_color_hit = {
            order = 5.32,
            type = "color",
            name = "Hit text color",
            desc = "Colour of the result popup on a scored attempt.",
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
            order = 5.33,
            type = "color",
            name = "Miss text color",
            desc = "Colour of the result popup on a failed attempt.",
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
            order = 5.34,
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
            order = 5.35,
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
            order = 5.36,
            name = "Reset panel position",
            desc = "Move the practice panel back to its default spot beside the swing bar.",
            func = function()
                local db = ST:get_class_table()
                db.practice_panel_x = 0
                db.practice_panel_y = 0
                -- Re-anchor through the panel's own position applier (practice_ui.lua
                -- apply_settings re-reads the offsets above; combat-lockdown defers
                -- it internally), mirroring the update_result_font seam above.
                if st.practice_ui and type(st.practice_ui.apply_settings) == "function" then
                    st.practice_ui.apply_settings(ST)
                end
            end,
        },
        execute_report_header = {
            type = "header",
            order = 5.5,
            name = "Execute Report",
        },
        execute_report_desc = {
            order = 5.51,
            type = "description",
            name = "Execute-phase drill (W6): no session - fight a target into Execute range. "..
                "Every crossing into Execute range logs the rage pooled at the entry, graded S "..
                "(full pool) to F (empty). The frame starts hidden; stop_fight re-renders it "..
                "when visible.",
        },
        warrior_execute_report = {
            type = "execute",
            order = 5.52,
            name = function()
                if st.practice_ui and st.practice_ui.warrior_execute_report_visible then
                    return "Hide Execute Report"
                end
                return "Show Execute Report"
            end,
            desc = "Toggle the post-fight Execute report frame.",
            func = function()
                if st.practice_ui and type(st.practice_ui.toggle_warrior_execute_report) == "function" then
                    st.practice_ui.toggle_warrior_execute_report(ST)
                end
            end,
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
        { key = "hud_show_rend", name = "Rend", desc = "Show the Rend icon (with its GCD swipe)." },
        { key = "hud_show_ms", name = "Mortal Strike", desc = "Show the Mortal Strike icon (with its GCD swipe)." },
        { key = "hud_show_bladestorm", name = "Bladestorm", desc = "Show the Bladestorm icon." },
        { key = "hud_show_raging_blow", name = "Raging Blow", desc = "Show the Raging Blow icon." },
        -- Hamstring weave filler (closes designer-templates G1: the default +
        -- template entries shipped without a widget, so the slot could only be
        -- toggled via template or /run). Sunder upkeep slot (Forever HUD mirror
        -- classes/warrior.lua:3013-3017; templates cover the union).
        { key = "hud_show_hamstring", name = "Hamstring", desc = "Show the Hamstring icon (with its GCD swipe)." },
        { key = "hud_show_sunder", name = "Sunder Armor", desc = "Show the Sunder Armor icon (with its GCD swipe)." },
        { key = "hud_show_trinket1", name = "Trinket 1", desc = "Show the top trinket slot (hidden while the slot is empty)." },
        { key = "hud_show_trinket2", name = "Trinket 2", desc = "Show the bottom trinket slot (hidden while the slot is empty)." },
    },
        "A row of ability icons with cooldown swipes and remaining-time text. Icons grey out "..
            "while on cooldown, tint blue without mana and red out of range. Overpower glows "..
            "while its dodge window is live and Execute glows in combat inside Execute range. "..
            "Unlock the frame to drag it into place.",
        "Overpower glows while its dodge window is live and Execute glows in combat inside "..
            "Execute range, both only while the toggle is on. No other icon glows.",
        "What the label says: the rotation alone, with a prefix, its steps, or both.",
        { key = "Execute", labelled = "Rotation: Execute", steps = "OP, Execute, Slam", both = "Execute  -  OP, Execute, Slam" })) do
        opts_group[k] = v
    end
    -- Sim reference (wowsims): text-only, no clickability (WoW cannot open
    -- external links, so the URLs below are display text, not buttons).
    -- The Next Action Guide practices the sim rotation in-game: Execute range,
    -- Heroic Strike floors and Whirlwind delay follow the sim numbers where
    -- sourced (see bench/warrior_rotation_audit_2026-10-19.md).
    opts_group.wowsims_header = {
        type = "header",
        order = 10.0,
        name = "Sim Reference",
    }
    opts_group.wowsims_desc = {
        order = 10.01,
        type = "description",
        name = "Rotation numbers follow the wowsims sims: https://github.com/wowsims/classic, "..
            "https://github.com/wowsims/sod, https://github.com/wowsims/tbc-new, "..
            "https://github.com/wowsims/forever (Wrath and Victory Rush have no "..
            "in-scope sim; those rows stay unconfirmed). Practice the sim in-game: "..
            "enable the guide above and run its prompts against the sim APL.",
    }
    -- Layout template (bench/hud_templates_2026-10-19.md §7): curated sets
    -- from ST.WARRIOR.HUD_TEMPLATES, applied on explicit pick only
    -- (nil = Custom, writes nothing). W-T3 is the provisional arms/SoD union.
    -- Gallery shortlist 5: W-T1 copy names the queue-color reads (shipped HS tint).
    opts_group.hud_template = hud_template_widget("WARRIOR", {
        custom = "Custom",
        fury_core = "W-T1 Fury Core",
        full_trinkets = "W-T2 Full + Trinkets",
        arms_sod = "W-T3 Arms / SoD (provisional)",
    })
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
            name = "Enable Raptor Strike color",
            desc = "Enables a special bar color when Raptor Strike is queued on the next attack.",
            get = "getter",
            set = "setter",
        },
        raptor_strike_color = {
            order=1.2,
            type="color",
            name="Raptor Strike color",
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
            name = "Enable Steady Shot color",
            desc = "Enables a special bar color when Steady Shot is queued.",
            get = "getter",
            set = "setter",
        },
        steady_shot_color = {
            order=2.2,
            type="color",
            name="Steady Shot color",
            desc="Color to use when Steady Shot is queued.",
            hasAlpha=true,
            get = "color_getter",
            set = "color_setter",
        },
        hunter_melee_header = {
            type = "header",
            order = 2.5,
            name = "Melee Bars",
        },
        hunter_melee_desc = {
            order = 2.501,
            type = "description",
            name = "The thin mainhand/offhand bars are pinned under the ranged bar and follow "..
                "its width (ranged, then mainhand, then offhand). Turning this off restores "..
                "each hand's own saved width and position.",
        },
        hunter_melee_stack = {
            type = "toggle",
            order = 2.51,
            name = "Stack melee bars under the ranged bar",
            desc = "Mainhand and offhand become thin bars under the ranged bar at its width. "..
                "Off: each hand keeps its own width and LibWindow position.",
            get = function()
                return ST:get_class_table().hunter_melee_stack ~= false
            end,
            set = function(_, value)
                local db = ST:get_class_table()
                db.hunter_melee_stack = value and true or false
                if value == false and st.hunter_ui
                    and type(st.hunter_ui.restore_melee_layout) == "function" then
                    st.hunter_ui.restore_melee_layout(ST)
                end
            end,
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
            name = "Enable cast bar",
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
            name = "Cast bar color",
            desc = "Color of the hunter cast bar. The Auto Shot window always uses this colour; live casts "..
                "tint green while stopping is safe and red while it is not.",
            hasAlpha = true,
            get = "hunter_cast_color_getter",
            set = "hunter_cast_color_setter",
            disabled = function()
                local db = ST:get_class_table()
                return not db.hunter_cast_bar_enabled
            end,
        },
        hunter_cast_zone_enabled = {
            type = "toggle",
            order = 3.4,
            name = "Movement-safe cast zone",
            desc = "Show a safe-to-move zone on the ranged bar while casting (green when "..
                "stopping is safe, red when it is not). Works without the cast bar.",
            get = "getter",
            set = "setter",
        },
        target_warning_header = {
            type = "header",
            order = 3.5,
            name = "Target Warning",
        },
        target_warning_desc = {
            order = 3.501,
            type = "description",
            name = "A red \"targeting you\" label above the cast bar while your target is "..
                "targeting you. Unknown hides: the label only shows on a confirmed read.",
        },
        hunter_target_warning_enabled = {
            type = "toggle",
            order = 3.51,
            name = "Enable target warning",
            desc = "Shows the target-of-target warning label (off by default).",
            get = "getter",
            set = "setter",
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
            name = "Enable range helper",
            desc = "Shows the 4-state range helper beside the ranged bar.",
            get = "getter",
            set = "setter",
        },
        hunter_weave_prog_enabled = {
            type = "toggle",
            order = 4.2,
            name = "Melee-weave progress tracking",
            desc = "Track the melee-weave distance approximation each frame (off by default). No visible change on its own: a future display reads this state.",
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
            name = "Enable Rapid Fire bar",
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
            name = "Enable aspect icon",
            desc = "Shows the active aspect's icon beside the ranged bar.",
            get = "getter",
            set = "setter",
        },
        pet_badges_header = {
            type = "header",
            order = 6.5,
            name = "Pet Badges",
        },
        pet_badges_desc = {
            order = 6.51,
            type = "description",
            name = "Aura badges for the pet fight: Bestial Wrath's duration and the "..
                "pet's Frenzy stack count.",
        },
        hunter_bw_badge_enabled = {
            type = "toggle",
            order = 6.52,
            name = "Bestial Wrath badge",
            desc = "Show the Bestial Wrath duration with a countdown, glowing in the "..
                "final 4 seconds.",
            get = "getter",
            set = "setter",
        },
        hunter_frenzy_stacks_enabled = {
            type = "toggle",
            order = 6.53,
            name = "Pet Frenzy stacks",
            desc = "Show the pet's Frenzy Effect stack count.",
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
            name = "On-screen rotation prompt (on by default): Steady Shot when the cast "..
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
        hunter_multi_target = {
            type = "toggle",
            order = 7.101,
            name = "Multi-target mode (manual, not wired yet)",
            desc = "Treat the fight as 2+ targets: the guide prefers Multi-Shot over the "..
                "single-target filler. Manual because automatic target counting is "..
                "unreliable in raids.",
            get = "getter",
            set = "setter",
        },
        nextaction_locked = {
            type = "toggle",
            order = 7.11,
            name = "Lock guide frame",
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
                return tostring(ST:get_class_table().nextaction_x or 127)
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
                return tostring(ST:get_class_table().nextaction_y or -65)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().nextaction_y = n
                end
            end,
        },
        shot_report_header = {
            type = "header",
            order = 7.5,
            name = "Shot Report",
        },
        shot_report_desc = {
            order = 7.51,
            type = "description",
            name = "Post-fight shot analytics (clip rate, latency buffer, next-cast hint) "..
                "over the rolling last-N shots. The frame starts hidden; stop_fight "..
                "re-renders it when visible.",
        },
        hunter_shot_report = {
            type = "execute",
            order = 7.52,
            name = function()
                if st.practice_ui and st.practice_ui.hunter_report_visible then
                    return "Hide Shot Report"
                end
                return "Show Shot Report"
            end,
            desc = "Toggle the post-fight shot report frame.",
            func = function()
                if st.practice_ui and type(st.practice_ui.toggle_hunter_report) == "function" then
                    st.practice_ui.toggle_hunter_report(ST)
                end
            end,
        },
        proc_badges_header = {
            type = "header",
            order = 7.4,
            name = "Proc & Readiness Badges",
        },
        proc_badges_desc = {
            order = 7.41,
            type = "description",
            name = "Badge-layer prompts (never drive the guide engine): the double "..
                "Rapid Fire window after Readiness, the Improved Steady Shot tint, "..
                "and the OOM Viper swap cue. All off by default.",
        },
        hunter_readiness_badge_enabled = {
            type = "toggle",
            order = 7.42,
            name = "Readiness double-Rapid Fire window",
            desc = "Show a 2x readout on the Rapid Fire bar while the double "..
                "Rapid Fire window after Readiness is live (off by default).",
            get = "getter",
            set = "setter",
        },
        hunter_iss_badge_enabled = {
            type = "toggle",
            order = 7.43,
            name = "Steady Shot proc tint (ISS)",
            desc = "Glow the Steady Shot and Aimed Shot HUD icons while the "..
                "Improved Steady Shot proc is banked (off by default).",
            get = "getter",
            set = "setter",
        },
        hunter_oom_viper_badge_enabled = {
            type = "toggle",
            order = 7.44,
            name = "Low-mana Viper badge (OOM)",
            desc = "Show a VIPER badge while mana sits below the swap band and "..
                "Aspect of the Viper is known but not active (off by default).",
            get = "getter",
            set = "setter",
        },
        hunter_lnl_badge_enabled = {
            type = "toggle",
            order = 7.45,
            name = "Trap-proc badge (Lock and Load)",
            desc = "Show an \"LnL\" badge while the Lock and Load trap-proc window is live "..
                "(off by default; hidden while the proc state is unknown).",
            get = "getter",
            set = "setter",
        },
        hunter_practice_header = {
            type = "header",
            order = 7.6,
            name = "Forced-Move Practice",
        },
        hunter_practice_desc = {
            order = 7.61,
            type = "description",
            name = "Forced-move drill from the practice registry (stay mobile inside the move "..
                "windows, keep casts clear of the next one). Start/stop with /st practice or "..
                "the button below; the panel's shot icons cast simulated shots (no mana, no "..
                "real casts), graded S/A/B/C/D/F into the session score.",
        },
        hunter_practice_toggle = {
            type = "execute",
            order = 7.62,
            name = function()
                if st.practice_ui and type(st.practice_ui.is_active) == "function"
                    and st.practice_ui.is_active() then
                    return "Open Practice Panel"
                end
                return "Start Practice"
            end,
            desc = "Open the practice trainer. Closing options leaves the session running; only the practice panel's X stops it. A session can only be started out of combat.",
            func = function()
                if st.practice_ui and type(st.practice_ui.open) == "function" then
                    st.practice_ui.open(ST)
                elseif st.practice_ui and type(st.practice_ui.toggle) == "function" then
                    st.practice_ui.toggle(ST) -- half-loaded fallback
                end
            end,
        },
        -- Simulation + feedback rows (paladin parity, owner order 2026-10-19): the
        -- same knobs the shared session reads from the class table (result
        -- styling, panel position), so the hunter page has the same shape as the
        -- paladin's. No weapon-speed override: the forced-move drill runs no
        -- drill swing (practice_ui.lua:4115), so that key would be an orphan here.
        practice_result_duration = {
            type = "range",
            order = 7.63,
            name = "Result text duration (s)",
            desc = "How long the grade popup stays on screen.",
            min = 0.3, max = 3.0, step = 0.1,
            get = function()
                return ST:get_class_table().practice_result_duration or 0.8
            end,
            set = "setter",
        },
        practice_result_text_size = {
            type = "range",
            order = 7.64,
            name = "Result text size",
            desc = "Font size of the grade popup.",
            min = 12, max = 48, step = 1,
            get = function()
                return ST:get_class_table().practice_result_text_size or 28
            end,
            set = function(_, value)
                ST:get_class_table().practice_result_text_size = value
                if st.practice_ui and type(st.practice_ui.update_result_font) == "function" then
                    st.practice_ui.update_result_font(ST)
                end
            end,
        },
        practice_result_color_hit = {
            order = 7.65,
            type = "color",
            name = "Pass text color",
            desc = "Colour of the grade popup on a passing grade.",
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
            order = 7.66,
            type = "color",
            name = "Fail text color",
            desc = "Colour of the grade popup on a failing grade.",
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
            order = 7.67,
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
            order = 7.68,
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
            order = 7.69,
            name = "Reset panel position",
            desc = "Move the practice panel back to its default spot beside the swing bar.",
            func = function()
                local db = ST:get_class_table()
                db.practice_panel_x = 0
                db.practice_panel_y = 0
                -- Re-anchor through the panel's own position applier (practice_ui.lua
                -- apply_settings re-reads the offsets above; combat-lockdown defers
                -- it internally), mirroring the update_result_font seam above.
                if st.practice_ui and type(st.practice_ui.apply_settings) == "function" then
                    st.practice_ui.apply_settings(ST)
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
        "What the label says: the rotation alone, with a prefix, its steps, or both.",
        { key = "Steady", labelled = "Rotation: Steady", steps = "Steady, Auto, Steady", both = "Steady  -  Steady, Auto, Steady" })) do
        opts_group[k] = v
    end
    -- Sim reference (wowsims): text-only, no clickability (WoW cannot open
    -- external links, so the URLs below are display text, not buttons).
    -- The Next Action Guide practices the sim rotation in-game: filler choice,
    -- Lock and Load arms and Serpent guards follow the sim numbers where
    -- sourced (see bench/hunter_rotation_audit_2026-10-19.md).
    opts_group.wowsims_header = {
        type = "header",
        order = 10.0,
        name = "Sim Reference",
    }
    opts_group.wowsims_desc = {
        order = 10.01,
        type = "description",
        name = "Rotation numbers follow the wowsims sims: https://github.com/wowsims/classic, "..
            "https://github.com/wowsims/sod, https://github.com/wowsims/tbc-new, "..
            "https://github.com/wowsims/wotlk, https://github.com/wowsims/forever. "..
            "Practice the sim in-game: enable the guide above and run its prompts "..
            "against the sim APL.",
    }
    -- Layout template (bench/hud_templates_2026-10-19.md §7): curated sets
    -- from ST.HUNTER.HUD_TEMPLATES, applied on explicit pick only
    -- (nil = Custom, writes nothing).
    -- Gallery shortlist 3: Core rows are the Luxthos Era-line visual-check target.
    opts_group.hud_template = hud_template_widget("HUNTER", {
        custom = "Custom",
        shot_rotation = "H-T1 Shot Rotation",
        full_bm = "H-T2 Full BM + Trinkets",
        minimal_glow = "H-T3 Minimal + Glow",
    })
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
            name = "Enable form colors",
            desc = "Enables form-dependent colors.",
            get = "getter",
            set = "setter",
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
            order = 6.0,
            name = "Maul",
        },
        queue_desc = {
            order = 6.02,
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
            order = 6.1,
            name = "Enable Maul color",
            desc = "Enables a custom color for the mainhand bar when Maul is queued.",
            get = "getter",
            set = "setter",
        },
        maul_color = {
            order=6.2,
            type="color",
            name="Maul color",
            desc="Color to use when Maul is queued.",
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
            order = 6.51,
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
            order=6.53,
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
            order = 7.0,
            name = "Druid Trackers",
        },
        trackers_desc = {
            order = 7.01,
            type = "description",
            name = "Feral/forms helper visuals: the 2-second cat-form energy cycle "..
                "beside the mainhand bar, the current shape on the bar while "..
                "shapeshifted, and your own Mangle/Rip/Rake durations above the bar.",
        },
        show_druid_energy_tick = {
            type = "toggle",
            order = 7.1,
            name = "Energy tick bar",
            desc = "Show a thin bar left of the mainhand bar tracking the 2-second "..
                "cat-form energy cycle (it fills as the next natural tick approaches).",
            get = "getter",
            set = "setter",
        },
        druid_energy_tick_color = {
            order=7.2,
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
            order = 7.3,
            name = "Form label",
            desc = "Show the current shape (Cat / Bear / Caster) on the mainhand bar "..
                "while shapeshifted; the configured bar texts are untouched in no form.",
            get = "getter",
            set = "setter",
        },
        show_druid_mangle_bar = {
            type = "toggle",
            order = 7.4,
            name = "Mangle bar",
            desc = "Show your own Mangle duration on the current target above the "..
                "mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        druid_mangle_bar_color = {
            order=7.5,
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
            order = 7.6,
            name = "Rip bar",
            desc = "Show your own Rip duration on the current target above the "..
                "mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        druid_rip_bar_color = {
            order=7.7,
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
            order = 7.8,
            name = "Rake bar",
            desc = "Show your own Rake duration on the current target above the "..
                "mainhand bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        druid_rake_bar_color = {
            order=7.9,
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
        show_druid_pips = {
            type = "toggle",
            order = 7.11,
            name = "Combo-point pips",
            desc = "Show combo points as pips under the bar in cat form (the row glows at 5).",
            get = "getter",
            set = "setter",
        },
        show_druid_shred_countdown = {
            type = "toggle",
            order = 7.12,
            name = "Shred countdown",
            desc = "Show \"Shred in Xs\" below the bar until the next energy tick can afford "..
                "a Shred (TBC/Wrath only).",
            get = "getter",
            set = "setter",
        },
        show_druid_maul_badge = {
            type = "toggle",
            order = 7.13,
            name = "Rage-cap Maul badge",
            desc = "Show the at-cap time (\"Cap Ns\") in bear form while rage is capped.",
            get = "getter",
            set = "setter",
        },
        show_druid_omen_glow = {
            type = "toggle",
            order = 7.14,
            name = "Omen glow",
            desc = "Glow the energy bar while the Omen of Clarity proc is up.",
            get = "getter",
            set = "setter",
        },
        show_druid_gcd_tick = {
            type = "toggle",
            order = 7.15,
            name = "GCD tick marker",
            desc = "Show a marker on the energy bar for the global cooldown's position "..
                "in the energy cycle.",
            get = "getter",
            set = "setter",
        },
        show_druid_ttd_readout = {
            type = "toggle",
            order = 7.16,
            name = "Target time-to-die readout",
            desc = "Show the target's time-to-die (\"TTD 8s\") below the bar. Unknown "..
                "hides: no target, unreadable or dead health shows nothing (off by default).",
            get = "getter",
            set = "setter",
        },

        -- Practice (the shared session: the toggle below starts it, the panel icons
        -- cast the simulated spells; opt-in, out-of-combat gated like the paladin's
        -- Twist Practice entry - no default-visible change).
        druid_practice_header = {
            type = "header",
            order = 7.17,
            name = "Practice",
        },
        druid_practice_desc = {
            order = 7.171,
            type = "description",
            name = "Practice minigame: simulate a boss fight's swing rotation in a "..
                "separate simulation, without attacking anything. The panel's ability icons cast "..
                "simulated spells (left click); the toggle below or /st practice toggles the "..
                "session. The druid powershift drill (druid_powershift) is registered for this "..
                "class and grades through the same scoring pipeline.",
        },
        druid_practice_toggle = {
            type = "execute",
            order = 7.172,
            name = function()
                if st.practice_ui and type(st.practice_ui.is_active) == "function"
                    and st.practice_ui.is_active() then
                    return "Open Practice Panel"
                end
                return "Start Practice"
            end,
            desc = "Open the practice trainer. Closing options leaves the session running; only the practice panel's X stops it. A session can only be started out of combat.",
            func = function()
                if st.practice_ui and type(st.practice_ui.open) == "function" then
                    st.practice_ui.open(ST)
                elseif st.practice_ui and type(st.practice_ui.toggle) == "function" then
                    st.practice_ui.toggle(ST) -- half-loaded fallback
                end
            end,
        },
        -- Simulation + feedback rows: the same knobs the shared session reads from
        -- the class table (weapon speed, result styling, panel position), mirrored
        -- from the paladin's Practice section so the page has the same shape.
        practice_weapon_speed = {
            type = "range",
            order = 7.18,
            name = "Weapon speed override (s)",
            desc = "0 uses the equipped weapon speed.",
            min = 0, max = 4, step = 0.1,
            get = "getter",
            set = "setter",
        },
        -- Practice result feedback and panel placement. Every widget edits the
        -- practice_result_* / practice_panel_* keys the session UI (practice_ui.lua)
        -- already reads, so the shipped defaults and the options round-trip in both
        -- directions. The two result colours are stored in the 0-1 range the result
        -- popup paints with (SetTextColor), NOT the shared 0-255 convention, so they
        -- use direct get/set functions instead of the class color_getter/color_setter.
        practice_result_duration = {
            type = "range",
            order = 7.19,
            name = "Result text duration (s)",
            desc = "How long the TWIST!/MISS popup stays on screen.",
            min = 0.3, max = 3.0, step = 0.1,
            get = "getter",
            set = "setter",
        },
        practice_result_text_size = {
            type = "range",
            order = 7.191,
            name = "Result text size",
            desc = "Font size of the TWIST!/MISS popup.",
            min = 12, max = 48, step = 1,
            get = "getter",
            set = function(_, value)
                ST:get_class_table().practice_result_text_size = value
                if st.practice_ui and type(st.practice_ui.update_result_font) == "function" then
                    st.practice_ui.update_result_font(ST)
                end
            end,
        },
        practice_result_color_hit = {
            order = 7.192,
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
            order = 7.193,
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
            order = 7.194,
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
            order = 7.195,
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
            order = 7.196,
            name = "Reset panel position",
            desc = "Move the practice panel back to its default spot beside the swing bar.",
            func = function()
                local db = ST:get_class_table()
                db.practice_panel_x = 0
                db.practice_panel_y = 0
                -- Re-anchor through the panel's own position applier (practice_ui.lua
                -- apply_settings re-reads the offsets above; combat-lockdown defers
                -- it internally), mirroring the update_result_font seam above.
                if st.practice_ui and type(st.practice_ui.apply_settings) == "function" then
                    st.practice_ui.apply_settings(ST)
                end
            end,
        },

        -- Next Action Guide (shared nextaction_ui frame; provider ST.DRUID.guide).
        nag_header = {
            type = "header",
            order = 7.95,
            name = "Next Action Guide",
        },
        nag_desc = {
            type = "description",
            order = 7.951,
            name = "On-screen rotation prompt (on by default): the next ability to press "..
                "in bear (Maul / Mangle) or cat form (Rip, Rake, Mangle, Ferocious Bite, "..
                "Shred) with the RIDE cue while a Maul is queued. Drag the frame while it "..
                "is unlocked to position it.",
        },
        nextaction_enabled = {
            type = "toggle",
            order = 7.952,
            name = "Enable",
            desc = "Show the next action guide.",
            get = "getter",
            set = "setter",
        },
        nextaction_locked = {
            type = "toggle",
            order = 7.953,
            name = "Lock guide frame",
            desc = "Prevent dragging the guide frame.",
            get = "getter",
            set = "setter",
        },
        nextaction_visibility_key = {
            type = "select",
            order = 7.954,
            name = "Show guide",
            desc = "When the guide is visible.",
            values = { always = "Always", in_combat = "In combat" },
            get = "getter",
            set = "setter",
        },
        nextaction_icon_size = {
            type = "range",
            order = 7.955,
            name = "Icon size",
            desc = "Guide icon size in pixels.",
            min = 20, max = 80, step = 1,
            get = "getter",
            set = "setter",
        },
        nextaction_x = {
            type = "input",
            order = 7.956,
            name = "X position",
            desc = "Horizontal screen position (dragging the frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().nextaction_x or 127)
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
            order = 7.957,
            name = "Y position",
            desc = "Vertical screen position (dragging the frame also updates this).",
            get = function()
                return tostring(ST:get_class_table().nextaction_y or -65)
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
            order = 7.958,
            name = "Rip refresh (s)",
            desc = "Suggest Rip while the target's Rip is missing or has this many "..
                "seconds or fewer remaining.",
            min = 0, max = 10, step = 0.5,
            get = "getter",
            set = "setter",
        },
        guide_rake_refresh = {
            type = "range",
            order = 7.959,
            name = "Rake refresh (s)",
            desc = "Suggest Rake while the target's Rake is missing or has this many "..
                "seconds or fewer remaining.",
            min = 0, max = 10, step = 0.5,
            get = "getter",
            set = "setter",
        },
        -- TBC Rip combo-point floor (the gather feeds db.guide_rip_min_cp raw at
        -- classes/druid.lua:1707; the engine clamps 2-5 and defaults nil to the
        -- frozen RIP_MIN_CP_TBC = 4 at druid_guide.lua:515-520). Ships 4, so a
        -- fresh profile renders the archived behaviour, never an empty slider.
        guide_rip_min_cp = {
            type = "range",
            order = 7.960,
            name = "Rip combo points",
            desc = "Suggest Rip once this many combo points are banked (TBC). "..
                "2 finishes early, 5 pools to full; 4 matches the sim default.",
            min = 2, max = 5, step = 1,
            get = "getter",
            set = "setter",
        },
    }
    -- Cooldown HUD + Rotation Text (shared hud_rotation_widgets builder: the same
    -- 8.x/9.x structure as the paladin's sections; the slot toggles mirror
    -- ST.DRUID.HUD_SLOTS). The Maul slot greys while a queued Maul is
    -- unaffordable; Tiger's Fury and Berserk glow in combat once ready.
    for k, v in pairs(hud_rotation_widgets({
        { key = "hud_show_maul", name = "Maul", desc = "Show the Maul icon (greys while a queued Maul is unaffordable)." },
        { key = "hud_show_mangle", name = "Mangle", desc = "Show the Mangle icon (with its GCD swipe)." },
        { key = "hud_show_rip", name = "Rip", desc = "Show the Rip icon (with its GCD swipe)." },
        { key = "hud_show_rake", name = "Rake", desc = "Show the Rake icon (with its GCD swipe)." },
        { key = "hud_show_bite", name = "Ferocious Bite", desc = "Show the Ferocious Bite icon (with its GCD swipe)." },
        { key = "hud_show_shred", name = "Shred", desc = "Show the Shred icon (with its GCD swipe)." },
        -- D-1 Claw mirror (bench/hud_parity_2026-10-19.md D-1): consumer
        -- classes/druid.lua:1979 HUD_SLOTS + :2217-2222 provider (== true shows,
        -- nil = off). Ship false = hidden (no default-visible change).
        { key = "hud_show_claw", name = "Claw", desc = "Show the Claw icon (with its GCD swipe)." },
        { key = "hud_show_tf", name = "Tiger's Fury", desc = "Show the Tiger's Fury icon (glows in combat once it is ready)." },
        { key = "hud_show_berserk", name = "Berserk", desc = "Show the Berserk icon (glows in combat once it is ready)." },
        { key = "hud_show_trinket1", name = "Trinket 1", desc = "Show the top trinket slot (hidden while the slot is empty)." },
        { key = "hud_show_trinket2", name = "Trinket 2", desc = "Show the bottom trinket slot (hidden while the slot is empty)." },
    },
        "A row of ability icons with cooldown swipes and remaining-time text. Icons grey out "..
            "while on cooldown (Maul also while a queued Maul is unaffordable), tint blue "..
            "without mana and red out of range. Tiger's Fury and Berserk glow in combat "..
            "once they are ready. Unlock the frame to drag it into place.",
        "Tiger's Fury and Berserk glow in combat once they are ready, both only while "..
            "the toggle is on. No other icon glows.",
        "What the label says: the rotation alone, with a prefix, its steps, or both.",
        { key = "Rip", labelled = "Rotation: Rip", steps = "Mangle, Rip, Rake", both = "Rip  -  Mangle, Rip, Rake" })) do
        opts_group[k] = v
    end
    -- Sim reference (wowsims): text-only, no clickability (WoW cannot open
    -- external links, so the URLs below are display text, not buttons).
    -- The Next Action Guide practices the sim rotation in-game: Tiger's Fury
    -- lines, Rip/Rake expiry and the Forever 50 ceiling follow the sim numbers
    -- where sourced (see bench/druid_rotation_audit_2026-10-19.md).
    opts_group.wowsims_header = {
        type = "header",
        order = 10.0,
        name = "Sim Reference",
    }
    opts_group.wowsims_desc = {
        order = 10.01,
        type = "description",
        name = "Rotation numbers follow the wowsims sims: https://github.com/wowsims/classic, "..
            "https://github.com/wowsims/sod, https://github.com/wowsims/tbc-new, "..
            "https://github.com/wowsims/wotlk, https://github.com/wowsims/forever. "..
            "Practice the sim in-game: enable the guide above and run its prompts "..
            "against the sim rotation.",
    }
    -- Layout template (bench/hud_templates_2026-10-19.md §7): curated sets
    -- from ST.DRUID.HUD_TEMPLATES, applied on explicit pick only
    -- (nil = Custom, writes nothing).
    -- Gallery shortlist 3: Core rows are the Luxthos Era-line visual-check target.
    opts_group.hud_template = hud_template_widget("DRUID", {
        custom = "Custom",
        bleed_core = "D-T1 Bleed Core",
        full_feral = "D-T2 Full Feral + Pops",
        bear_guard = "D-T3 Bear Guard",
    })
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
            name = "Enable spell weaving",
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
            desc = "Count Maelstrom Weapon stacks toward the cast time (20% per stack; 5 stacks are instant).",
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
            name = "Stormstrike + Shamanistic Rage badges",
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
        show_shaman_stormstrike_bar = {
            type = "toggle",
            order = 2.31,
            name = "Stormstrike bar",
            desc = "Show the target's Stormstrike nature-vulnerability remaining time "..
                "above the Flame Shock bar, with a glow in the last 4 seconds.",
            get = "getter",
            set = "setter",
        },
        badges_header = {
            type = "header",
            order = 2.65,
            name = "Bar Badges",
        },
        show_shaman_wf_hold_tint = {
            type = "toggle",
            order = 2.7,
            name = "Windfury hold tint",
            desc = "Wash the swing's final fraction amber while Stormstrike is held for "..
                "the Windfury internal cooldown.",
            get = "getter",
            set = "setter",
        },
        show_shaman_rockbiter_badge = {
            type = "toggle",
            order = 2.8,
            name = "Rockbiter badge",
            desc = "Show the Rockbiter Weapon remaining time beside the bar.",
            get = "getter",
            set = "setter",
        },
        show_shaman_spell_positions = {
            type = "toggle",
            order = 2.9,
            name = "Safe-cast position row",
            desc = "Show the cast-start zone, the per-spell icons at their latest safe "..
                "starts and the effective cast times above the bar.",
            get = "getter",
            set = "setter",
        },
        show_shaman_dw_sync = {
            type = "toggle",
            order = 2.91,
            name = "Dual-wield sync / Flurry readout",
            desc = "Show the dual-wield sync readout and the live Flurry proc countdown "..
                "beside the bar.",
            get = "getter",
            set = "setter",
        },
        show_shaman_lust_status = {
            type = "toggle",
            order = 2.92,
            name = "Lust status badge",
            desc = "Show the Bloodlust / Heroism remaining time beside the bar (\"BL ?\" "..
                "while the aura list may be restricted and the read is inconclusive; "..
                "hidden while no lust is up).",
            get = "getter",
            set = "setter",
        },

        -- Practice (the archive's Guides & Practice page shape, shaman entry):
        -- the same session every class shares, started both ways (this toggle or
        -- /st practice), plus the shaman weave drill. The session panel icons cast
        -- simulated spells; the drill grades simulated Lightning Bolt / Chain
        -- Lightning starts by margin before the weave marker through the practice
        -- harness. No new db keys: every widget reads nil-safe with the shipped
        -- paladin defaults below, and the drill stays hidden until opened
        -- (nil = off).
        practice_header = {
            type = "header",
            order = 5.0,
            name = "Weave Practice",
        },
        practice_desc = {
            order = 5.05,
            type = "description",
            name = "Practice drill: simulate weave-timing casts against a drill swing, "..
                "without attacking anything. The panel's Lightning Bolt / Chain Lightning icons cast "..
                "simulated spells (left click); the toggle below (or /st practice) starts and stops "..
                "the session. Only weapon speed, result styling and panel position ship as options.",
        },
        practice_toggle = {
            type = "execute",
            order = 5.1,
            name = function()
                if st.practice_ui and type(st.practice_ui.is_active) == "function"
                    and st.practice_ui.is_active() then
                    return "Open Practice Panel"
                end
                return "Start Practice"
            end,
            desc = "Open the practice trainer. Closing options leaves the session running; only the practice panel's X stops it. A session can only be started out of combat.",
            func = function()
                if st.practice_ui and type(st.practice_ui.open) == "function" then
                    st.practice_ui.open(ST)
                elseif st.practice_ui and type(st.practice_ui.toggle) == "function" then
                    st.practice_ui.toggle(ST) -- half-loaded fallback
                end
            end,
        },
        practice_weapon_speed = {
            type = "range",
            order = 5.2,
            name = "Weapon speed override (s)",
            desc = "0 uses the equipped weapon speed.",
            min = 0, max = 4, step = 0.1,
            get = function()
                return ST:get_class_table().practice_weapon_speed or 0
            end,
            set = "setter",
        },
        -- Practice result feedback and panel placement. Every widget reads the
        -- archived practice_result_* / practice_panel_* keys nil-safe (the
        -- paladin defaults stand in until set); the session UI (practice_ui.lua)
        -- owns the same fallbacks, so the options and the panel round-trip in
        -- both directions. The two result colours are stored in the 0-1 range
        -- the result popup paints with (SetTextColor), NOT the shared 0-255
        -- convention, so they use direct get/set functions.
        practice_result_duration = {
            type = "range",
            order = 5.3,
            name = "Result text duration (s)",
            desc = "How long the grade popup stays on screen.",
            min = 0.3, max = 3.0, step = 0.1,
            get = function()
                return ST:get_class_table().practice_result_duration or 0.8
            end,
            set = "setter",
        },
        practice_result_text_size = {
            type = "range",
            order = 5.31,
            name = "Result text size",
            desc = "Font size of the grade popup.",
            min = 12, max = 48, step = 1,
            get = function()
                return ST:get_class_table().practice_result_text_size or 28
            end,
            set = function(_, value)
                ST:get_class_table().practice_result_text_size = value
                if st.practice_ui and type(st.practice_ui.update_result_font) == "function" then
                    st.practice_ui.update_result_font(ST)
                end
            end,
        },
        practice_result_color_hit = {
            order = 5.32,
            type = "color",
            name = "Hit text color",
            desc = "Colour of the grade popup on a tight weave (S/A/B/C).",
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
            order = 5.33,
            type = "color",
            name = "Miss text color",
            desc = "Colour of the grade popup on a late or clipped weave (D/F).",
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
            order = 5.34,
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
            order = 5.35,
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
            order = 5.36,
            name = "Reset panel position",
            desc = "Move the practice panel back to its default spot beside the swing bar.",
            func = function()
                local db = ST:get_class_table()
                db.practice_panel_x = 0
                db.practice_panel_y = 0
                -- Re-anchor through the panel's own position applier (practice_ui.lua
                -- apply_settings re-reads the offsets above; combat-lockdown defers
                -- it internally), mirroring the update_result_font seam above.
                if st.practice_ui and type(st.practice_ui.apply_settings) == "function" then
                    st.practice_ui.apply_settings(ST)
                end
            end,
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
            name = "On-screen rotation prompt (on by default): the next ability to press "..
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
            name = "Lock guide frame",
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
                return tostring(ST:get_class_table().nextaction_x or 127)
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
                return tostring(ST:get_class_table().nextaction_y or -65)
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
            order = 3.101,
            name = "Flame Shock refresh (s)",
            desc = "Suggest Flame Shock while the target's Flame Shock is missing or has "..
                "this many seconds or fewer remaining.",
            min = 0, max = 10, step = 0.5,
            get = "getter",
            set = "setter",
        },
        -- The TBC APL's "Filler Shock" choice (the Shocks group picks ONE filler):
        -- the valueVariables default is Earth Shock (the group's row 3, 25454 r8) and
        -- the ALTERNATIVE is Frost Shock (the group's row 2, 25464 r5). The class
        -- reads this key and states the choice to the frozen engine's `filler_shock`
        -- input (classes/shaman.lua's gather), so the engine's rule 13b answers only
        -- when Frost Shock is picked; every other value - and a missing one - reads
        -- as the APL's default. Ships the APL's default (Earth Shock), so a fresh
        -- profile behaves exactly as before.
        guide_filler_shock = {
            type = "select",
            order = 3.102,
            name = "Shock filler",
            desc = "Which shock the guide suggests as the TBC filler: Earth Shock (the "..
                "APL's default) or Frost Shock. Frost Shock replaces the Earth Shock "..
                "filler entirely while it is picked.",
            values = {
                earth = "Earth Shock",
                frost = "Frost Shock",
            },
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
        -- The two maintain mirrors (bench/shaman_slots_2026-10-19.md §2): the live
        -- consumer is classes/shaman.lua - ST.SHAMAN.HUD_SLOTS declares the
        -- "lightningshield" and "searing" descriptors, and ST.SHAMAN.get_hud_state
        -- reads hud_db["hud_show_" .. slot.key] == true (nil = off; the provider-level
        -- hide is the no-default-visible gate). Both ship false = hidden, the druid
        -- Claw mirror's shape. They stay before the trinkets so the row's order
        -- mirrors ST.SHAMAN.HUD_SLOTS.
        { key = "hud_show_lightningshield", name = "Lightning Shield", desc = "Show the Lightning Shield icon (glows in combat while no shield aura is up)." },
        { key = "hud_show_searing", name = "Searing Totem", desc = "Show the Searing Totem icon (glows in combat while the fire totem slot is empty)." },
        -- The third maintain mirror (S-20 / U-10): the Call of the Elements water
        -- clock. The same live consumer - classes/shaman.lua ST.SHAMAN.HUD_SLOTS
        -- declares the "coe" descriptor and ST.SHAMAN.get_hud_state reads
        -- hud_db["hud_show_coe"] == true (nil = off; the provider-level hide is the
        -- no-default-visible gate). It ships false = hidden, like the two above,
        -- and it sits before the trinkets so the row's order mirrors
        -- ST.SHAMAN.HUD_SLOTS.
        { key = "hud_show_coe", name = "Call of the Elements", desc = "Show the Call of the Elements icon (glows in combat while the water totem has under 20 s left)." },
        { key = "hud_show_trinket1", name = "Trinket 1", desc = "Show the top trinket slot (hidden while the slot is empty)." },
        { key = "hud_show_trinket2", name = "Trinket 2", desc = "Show the bottom trinket slot (hidden while the slot is empty)." },
    },
        "A row of ability icons with cooldown swipes and remaining-time text. Icons grey out "..
            "while on cooldown, tint blue without mana and red out of range. Stormstrike glows "..
            "once it is ready in combat. Unlock the frame to drag it into place.",
        "Stormstrike glows once it is ready in combat, only while the toggle is on. The "..
            "Lightning Shield, Searing Totem and Call of the Elements mirrors glow while "..
            "their upkeep is due (no shield aura up / the fire totem slot empty / the "..
            "water totem under 20 s), each only while its own toggle is on. No other "..
            "icon glows.",
        "What the label says: the rotation alone, with a prefix, its steps, or both.",
        { key = "Stormstrike", labelled = "Rotation: Stormstrike", steps = "SS, FS, LB", both = "Stormstrike  -  SS, FS, LB" })) do
        opts_group[k] = v
    end
    -- Sim reference (wowsims): text-only, no clickability (WoW cannot open
    -- external links, so the URLs below are display text, not buttons).
    -- The Next Action Guide practices the sim rotation in-game: Stormstrike
    -- on cooldown, Flame Shock expiry-only and the Windfury ICD follow the sim
    -- numbers where sourced (see bench/shaman_rotation_audit_2026-10-19.md).
    opts_group.wowsims_header = {
        type = "header",
        order = 10.0,
        name = "Sim Reference",
    }
    opts_group.wowsims_desc = {
        order = 10.01,
        type = "description",
        name = "Rotation numbers follow the wowsims sims: https://github.com/wowsims/classic, "..
            "https://github.com/wowsims/sod, https://github.com/wowsims/tbc-new, "..
            "https://github.com/wowsims/forever (Wrath has no in-scope sim; that "..
            "row is guide-derived). Practice the sim in-game: enable the guide "..
            "above and run its prompts against the sim rotation.",
    }
    -- Layout template (bench/hud_templates_2026-10-19.md §7): curated sets
    -- from ST.SHAMAN.HUD_TEMPLATES, applied on explicit pick only
    -- (nil = Custom, writes nothing).
    -- Gallery shortlist 2/6/7: Sabimaru visual-check for S-T1/S-T2; bar-side
    -- borrows out of scope here (UNCONFIRMED); D2/D3 WOTLK items excluded.
    opts_group.hud_template = hud_template_widget("SHAMAN", {
        custom = "Custom",
        twist_core = "S-T1 Twist Core",
        full_weave = "S-T2 Full Enhance + Weave",
        minimal = "S-T3 Minimal",
    })
    return opts_group
end

-- Rogue guide thresholds: the db value wins; nil falls back to the pure engine's
-- default constant (with the shipped literal as a last resort), so a range never
-- renders empty in a profile that predates the key.
local function rogue_threshold_get(db_key, constant, fallback)
    local value = ST:get_class_table()[db_key]
    if type(value) == "number" then
        return value
    end
    local rg = st.rogue_guide
    local engine = rg and rg[constant]
    if type(engine) == "number" then
        return engine
    end
    return fallback
end

-- One inline setter per threshold (no bar reconfigure chain: guide thresholds do
-- not touch the bars).
local function rogue_threshold_set(db_key)
    return function(_, value)
        local n = tonumber(value)
        if n then
            ST:get_class_table()[db_key] = n
        end
    end
end

function ST.class_opts_funcs.ROGUE(self)
    local opts_group = {
        energy_header = {
            type = "header",
            order = 1.01,
            name = "Energy / Pooling",
        },
        energy_desc = {
            order = 1.02,
            type = "description",
            name = "Energy-tick spark and pooling tint on the mainhand bar. Pooling bands "..
                "are energy thresholds: do not pool above the pre-tick / post-tick line. "..
                "Both cues hide while the tick prediction is unknown (energy procs, missing "..
                "reads) instead of drawing a guessed tick.",
        },
        show_rogue_energy_tick = {
            type = "toggle",
            order = 1.1,
            name = "Energy tick marker",
            desc = "Show the predicted energy tick position. Hidden while the tick prediction is unknown.",
            get = "getter",
            set = "setter",
        },
        rogue_energy_tick_color = {
            order = 1.11,
            type = "color",
            name = "Tick marker color",
            desc = "Color of the energy tick marker.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                return not ST:get_class_table().show_rogue_energy_tick
            end,
        },
        show_rogue_pool_tint = {
            type = "toggle",
            order = 1.2,
            name = "Pooling tint",
            desc = "Tint the energy display while inside the pooling band. Hidden while the tick prediction is unknown.",
            get = "getter",
            set = "setter",
        },
        rogue_pool_tint_color = {
            order = 1.21,
            type = "color",
            name = "Pooling tint color",
            desc = "Color used for the pooling band tint.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                return not ST:get_class_table().show_rogue_pool_tint
            end,
        },
        rogue_pool_band_pre = {
            type = "range",
            order = 1.3,
            name = "Pool: don't spend below (pre-tick)",
            desc = "Energy threshold at or above which the next tick would cap the bar.",
            min = 0, max = 100, step = 5,
            get = "getter",
            set = "setter",
        },
        rogue_pool_band_post = {
            type = "range",
            order = 1.31,
            name = "Pool: don't spend below (post-tick)",
            desc = "Energy threshold to respect immediately after a tick.",
            min = 0, max = 100, step = 5,
            get = "getter",
            set = "setter",
        },

        duty_header = {
            type = "header",
            order = 2.01,
            name = "Upkeep Duty",
        },
        duty_desc = {
            order = 2.02,
            type = "description",
            name = "Who keeps the target's armor debuff up. The upkeep states themselves "..
                "already render in the Cooldown HUD (Slice and Dice, Rupture, Expose "..
                "Armor, Thistle Tea) and the Next Action Guide (Expose Armor, Shiv, "..
                "Thistle Tea), so no separate bar cues ship.",
        },
        rogue_ea_duty = {
            type = "toggle",
            order = 2.03,
            name = "Expose Armor duty",
            desc = "Treat keeping Expose Armor on the target as your job (Improved "..
                "Expose Armor): the guide suggests it while the debuff is missing or "..
                "inside the refresh window. Leave off when someone else handles the "..
                "armor debuff. Off by default; the guide never suggests Expose Armor while off.",
            get = "getter",
            set = "setter",
        },
        thresholds_header = {
            type = "header",
            order = 2.7,
            name = "Guide Thresholds",
        },
        thresholds_desc = {
            type = "description",
            order = 2.705,
            name = "Tuning for the upkeep and finisher suggestions. Each range shows the "..
                "effective value, including the shipped default for a profile that "..
                "predates the key.",
        },
        rogue_rupture_refresh = {
            type = "range",
            order = 2.71,
            name = "Rupture refresh (s)",
            desc = "Suggest Rupture while the target's Rupture is missing or has this "..
                "many seconds or fewer remaining.",
            min = 0, max = 10, step = 0.5,
            get = function()
                return rogue_threshold_get("rogue_rupture_refresh", "RUPTURE_REFRESH_DEFAULT", 4)
            end,
            set = rogue_threshold_set("rogue_rupture_refresh"),
        },
        rogue_rupture_min_ttd = {
            type = "range",
            order = 2.72,
            name = "Rupture skip-if-dying-within (s)",
            desc = "Dump Eviscerate instead of starting a Rupture when the target is "..
                "estimated to die inside this many seconds (the addon's own health-"..
                "velocity estimate; an unknown time-to-die never suggests a finisher "..
                "on a guess).",
            min = 0, max = 30, step = 1,
            get = function()
                return rogue_threshold_get("rogue_rupture_min_ttd", "RUPTURE_MIN_TTD_DEFAULT", 8)
            end,
            set = rogue_threshold_set("rogue_rupture_min_ttd"),
        },
        rogue_finisher_min_cp = {
            type = "range",
            order = 2.73,
            name = "Finisher min combo points",
            desc = "Only plan finishers at this many combo points or more.",
            min = 0, max = 5, step = 1,
            get = function()
                return rogue_threshold_get("rogue_finisher_min_cp", "FINISHER_MIN_CP_DEFAULT", 5)
            end,
            set = rogue_threshold_set("rogue_finisher_min_cp"),
        },
        rogue_ea_refresh = {
            type = "range",
            order = 2.74,
            name = "Expose Armor refresh (s)",
            desc = "With the duty toggle on, suggest Expose Armor while the target's "..
                "debuff is missing or has this many seconds or fewer remaining.",
            min = 0, max = 10, step = 0.5,
            get = function()
                return rogue_threshold_get("rogue_ea_refresh", "EA_REFRESH_DEFAULT", 3)
            end,
            set = rogue_threshold_set("rogue_ea_refresh"),
        },
        rogue_shiv_refresh = {
            type = "range",
            order = 2.75,
            name = "Shiv refresh (s)",
            desc = "Suggest Shiv before Deadly Poison falls off the target: refresh "..
                "while it has this many seconds or fewer remaining.",
            min = 0, max = 10, step = 0.5,
            get = function()
                return rogue_threshold_get("rogue_shiv_refresh", "SHIV_REFRESH_DEFAULT", 2)
            end,
            set = rogue_threshold_set("rogue_shiv_refresh"),
        },
        rogue_tea_energy_max = {
            type = "range",
            order = 2.76,
            name = "Thistle Tea drink-at energy",
            desc = "Suggest Thistle Tea while energy is at or below this.",
            min = 0, max = 100, step = 5,
            get = function()
                return rogue_threshold_get("rogue_tea_energy_max", "TEA_ENERGY_MAX_DEFAULT", 40)
            end,
            set = rogue_threshold_set("rogue_tea_energy_max"),
        },

        postswing_header = {
            type = "header",
            order = 3.01,
            name = "Post-swing & Weapon Cues",
        },
        postswing_desc = {
            type = "description",
            order = 3.02,
            name = "Post-swing cues on the mainhand bar. Sinister Strike window: "..
                "Classic Era only, and only with a readable sword mainhand - strike "..
                "in the 0.1-0.2 s after the swing lands. The window ships red and "..
                "visible by default (owner order 2026-10-19); turn the toggle off "..
                "to hide it. Weapon-swap band: Era, TBC "..
                "and WoW Forever (Wrath stays off pending in-client confirmation, "..
                "and Retail has no swing reset to time); its caption carries the "..
                "cost (GCD + swing reset). Poison reminder: flags a missing mainhand "..
                "or offhand poison (no charge counts). A cue hides while the swing "..
                "or weapon reads are unknown.",
        },
        show_rogue_ss_window = {
            type = "toggle",
            order = 3.1,
            name = "Sinister Strike window",
            desc = "Show the red post-swing Sinister Strike window (Classic Era, sword "..
                "mainhand only). On by default per owner order 2026-10-19; hidden "..
                "while the swing or weapon reads are unknown.",
            get = "getter",
            set = "setter",
        },
        rogue_ss_color = {
            order = 3.11,
            type = "color",
            name = "Sinister Strike window color",
            desc = "Color of the Sinister Strike window band.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                return not ST:get_class_table().show_rogue_ss_window
            end,
        },
        show_rogue_swap_cue = {
            type = "toggle",
            order = 3.2,
            name = "Weapon-swap window",
            desc = "Show the weapon-swap window band after a swing (Era, TBC and "..
                "WoW Forever; the caption carries the swap cost).",
            get = "getter",
            set = "setter",
        },
        rogue_swap_color = {
            order = 3.21,
            type = "color",
            name = "Weapon-swap color",
            desc = "Color of the weapon-swap window band.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                return not ST:get_class_table().show_rogue_swap_cue
            end,
        },
        show_rogue_poison_cue = {
            type = "toggle",
            order = 3.3,
            name = "Poison reminder",
            desc = "Show a reminder when the mainhand or offhand weapon has no "..
                "poison. Hidden while the weapon buffs cannot be read.",
            get = "getter",
            set = "setter",
        },
        rogue_poison_color = {
            order = 3.31,
            type = "color",
            name = "Poison reminder color",
            desc = "Color of the poison reminder text.",
            hasAlpha = true,
            get = "color_getter",
            set = "color_setter",
            disabled = function()
                return not ST:get_class_table().show_rogue_poison_cue
            end,
        },

        -- Next Action Guide (shared nextaction_ui frame; provider ST.ROGUE.guide).
        nag_header = {
            type = "header",
            order = 4.0,
            name = "Next Action Guide",
        },
        nag_desc = {
            type = "description",
            order = 4.05,
            name = "On-screen rotation prompt (on by default): the ability to press "..
                "next, with a POOL hold while the energy tick is close and a NOW label "..
                "once the action is rideable. When the swing, energy, combo-point or "..
                "aura reads cannot be trusted the guide shows \"…\" instead of advice - "..
                "no guessed prompt. Drag the frame while it is unlocked to position it.",
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
            name = "Lock guide frame",
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
                return tostring(ST:get_class_table().nextaction_x or 127)
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
                return tostring(ST:get_class_table().nextaction_y or -65)
            end,
            set = function(_, value)
                local n = tonumber(value)
                if n then
                    ST:get_class_table().nextaction_y = n
                end
            end,
        },
        -- Practice (shared session, rogue drills): the options Start/Stop toggle below
        -- starts the same session /st practice toggles (practice_ui.toggle) - panel
        -- icons cast simulated spells, the Start Fight button runs the fight, keybinds
        -- work as in game. Rogue drill grading (energy-pool timing, Era
        -- SS-after-swing) scores through the practice registry (classes/rogue.lua
        -- seam) and hides while its reads are unknown. Every widget below reads the
        -- same class-table keys the shared session already consumes, so no new
        -- defaults ship; each get falls back to the shipped shared timing.
        practice_header = {
            type = "header",
            order = 7.0,
            name = "Practice",
        },
        practice_desc = {
            order = 7.05,
            type = "description",
            name = "Practice session with simulated spells: the panel icons cast "..
                "simulated spells (left click), the Start Fight button runs the fight, "..
                "and keybinds work as in game. /st practice toggles the same session. "..
                "Rogue drill grading (energy-pool timing and the Era SS-after-swing "..
                "window) scores through the practice registry and hides while its "..
                "reads are unknown.",
        },
        practice_toggle = {
            type = "execute",
            order = 7.1,
            name = function()
                if st.practice_ui and type(st.practice_ui.is_active) == "function"
                    and st.practice_ui.is_active() then
                    return "Open Practice Panel"
                end
                return "Start Practice"
            end,
            desc = "Open the practice trainer. Closing options leaves the session running; only the practice panel's X stops it. A session can only be started out of combat.",
            func = function()
                if st.practice_ui and type(st.practice_ui.open) == "function" then
                    st.practice_ui.open(ST)
                elseif st.practice_ui and type(st.practice_ui.toggle) == "function" then
                    st.practice_ui.toggle(ST) -- half-loaded fallback
                end
            end,
        },
        practice_weapon_speed = {
            type = "range",
            order = 7.2,
            name = "Weapon speed override (s)",
            desc = "0 uses the equipped weapon speed.",
            min = 0, max = 4, step = 0.1,
            get = function()
                -- Consumer: resolve_base_speed (practice_ui.lua) reads this key.
                return ST:get_class_table().practice_weapon_speed or 0
            end,
            set = function(_, value)
                ST:get_class_table().practice_weapon_speed = value
            end,
        },
        -- Practice result feedback and panel placement. Every widget edits the keys
        -- the shared session UI (practice_ui.lua) already reads, so the shipped
        -- shared timing applies until the rogue profile writes its own. The two
        -- result colours are stored in the 0-1 range the result popup paints with,
        -- NOT the shared 0-255 convention. Fallbacks cite the shipped shared
        -- defaults (config_presets.lua practice_result_*).
        practice_result_duration = {
            type = "range",
            order = 7.3,
            name = "Result text duration (s)",
            desc = "How long the result popup stays on screen.",
            min = 0.3, max = 3.0, step = 0.1,
            get = function()
                return ST:get_class_table().practice_result_duration or 0.8
            end,
            set = function(_, value)
                ST:get_class_table().practice_result_duration = value
            end,
        },
        practice_result_text_size = {
            type = "range",
            order = 7.31,
            name = "Result text size",
            desc = "Font size of the result popup.",
            min = 12, max = 48, step = 1,
            get = function()
                return ST:get_class_table().practice_result_text_size or 28
            end,
            set = function(_, value)
                ST:get_class_table().practice_result_text_size = value
                if st.practice_ui and type(st.practice_ui.update_result_font) == "function" then
                    st.practice_ui.update_result_font(ST)
                end
            end,
        },
        practice_result_color_hit = {
            order = 7.32,
            type = "color",
            name = "Hit text color",
            desc = "Colour of the result popup on a scored attempt.",
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
            desc = "Colour of the result popup on a failed attempt.",
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
                -- Re-anchor through the panel's own position applier (practice_ui.lua
                -- apply_settings re-reads the offsets above).
                if st.practice_ui and type(st.practice_ui.apply_settings) == "function" then
                    st.practice_ui.apply_settings(ST)
                end
            end,
        },
    }
    -- Cooldown HUD + Rotation Text (shared hud_rotation_widgets builder: the same
    -- 8.x/9.x structure as the other class sections; the slot toggles mirror
    -- ST.ROGUE.HUD_SLOTS). Slice and Dice, Rupture and Expose Armor glow in their
    -- final 3 seconds; the rotation label reads ST.ROGUE.get_rotation_key (the
    -- guide's own decision: POOL, NOW, or the localized action name).
    for k, v in pairs(hud_rotation_widgets({
        { key = "hud_show_snd", name = "Slice and Dice", desc = "Show the Slice and Dice icon." },
        { key = "hud_show_rupture", name = "Rupture", desc = "Show the Rupture icon." },
        { key = "hud_show_ea", name = "Expose Armor", desc = "Show the Expose Armor icon." },
        { key = "hud_show_ar", name = "Adrenaline Rush", desc = "Show the Adrenaline Rush icon." },
        { key = "hud_show_bf", name = "Blade Flurry", desc = "Show the Blade Flurry icon." },
        { key = "hud_show_tea", name = "Thistle Tea", desc = "Show the Thistle Tea icon." },
        { key = "hud_show_kick", name = "Kick", desc = "Show the Kick icon." },
        -- R-M1 short-CD row (bench/settings_audit_2026-10-19.md R-M1): consumers
        -- classes/rogue.lua:442 shortcd_wanted (== true shows, nil = off) +
        -- :1047-1049 HUD_SLOTS + :1268-1332 provider. Ship false = hidden
        -- (no default-visible change; R-T3 template turns them on).
        { key = "hud_show_kidney", name = "Kidney Shot", desc = "Show the Kidney Shot icon." },
        { key = "hud_show_restealth", name = "Re-stealth", desc = "Show the Re-stealth icon." },
        { key = "hud_show_bandage", name = "Bandage", desc = "Show the Bandage icon." },
        { key = "hud_show_coldblood", name = "Cold Blood", desc = "Show the Cold Blood icon." },
        { key = "hud_show_trinket1", name = "Trinket 1", desc = "Show the top trinket slot (hidden while the slot is empty)." },
        { key = "hud_show_trinket2", name = "Trinket 2", desc = "Show the bottom trinket slot (hidden while the slot is empty)." },
    },
        "A row of ability icons with cooldown swipes and remaining-time text. Icons grey out "..
            "while on cooldown, tint blue without energy and red out of range. Slice and Dice, "..
            "Rupture and Expose Armor glow in their final seconds. Unlock the frame to drag it "..
            "into place.",
        "Slice and Dice, Rupture and Expose Armor glow in their final 3 seconds, only while "..
            "the toggle is on. No other icon glows.",
        "What the label says: the rotation alone, with a prefix, its steps, or both.",
        { key = "Rupture", labelled = "Rotation: Rupture", steps = "SS, Rupture, Eviscerate", both = "Rupture  -  SS, Rupture, Eviscerate" })) do
        opts_group[k] = v
    end
    -- Sim reference (wowsims): text-only, no clickability (WoW cannot open
    -- external links, so the URLs below are display text, not buttons).
    -- The Next Action Guide practices the sim rotation in-game: pooling bands,
    -- Expose Armor windows, Thistle Tea lines and finisher floors follow the
    -- sim numbers where sourced (see bench/rogue_rotation_audit_2026-10-19.md).
    opts_group.wowsims_header = {
        type = "header",
        order = 10.0,
        name = "Sim Reference",
    }
    opts_group.wowsims_desc = {
        order = 10.01,
        type = "description",
        name = "Rotation numbers follow the wowsims sims: https://github.com/wowsims/classic, "..
            "https://github.com/wowsims/sod, https://github.com/wowsims/tbc-new, "..
            "https://github.com/wowsims/wotlk, https://github.com/wowsims/forever "..
            "(Retail has no sim repo in scope). Practice the sim in-game: enable "..
            "the guide above and run its prompts against the sim APL.",
    }
    -- Layout template (bench/hud_templates_2026-10-19.md §7): curated sets
    -- from ST.ROGUE.HUD_TEMPLATES, applied on explicit pick only
    -- (nil = Custom, writes nothing). R-T3 is the provisional PvP set (its
    -- kidney/restealth/bandage keys now have widgets above; the pick still writes
    -- them, nil-safe via the provider gate).
    -- Gallery shortlist 1: R-T1 UxkIny-style Core is the anchor (no change).
    opts_group.hud_template = hud_template_widget("ROGUE", {
        custom = "Custom",
        core = "R-T1 UxkIny-style Core",
        full_cds = "R-T2 Full + CDs + Trinkets",
        pvp_utility = "R-T3 PvP Utility (provisional)",
    })
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
                -- Honest per-hand width (operator order 2026-10-28: "off hand should always be
                -- same width as main hand"; publish-audit E1). bars.lua's size invariant
                -- renders the OFFHAND at the MAINHAND's width on every layout pass, so the
                -- offhand's own bar_width key never sizes the bar: this widget shows the
                -- mainhand's width and is locked, and a write aimed at the offhand is routed
                -- to the mainhand key (defensive - the lock keeps the UI off that path).
                -- The hunter melee stack overrides BOTH melee hands for the pass; the
                -- description says so for every non-ranged hand. The ranged hand is never
                -- part of either rule.
                desc = function()
                    local base = "The pixel width of the swing timer."
                    if hand == "offhand" then
                        base = base .. " The offhand always renders at the mainhand's width, "
                            .. "so this field follows the mainhand."
                    end
                    if hand ~= "ranged" and ST.player_class == "HUNTER"
                        and type(ST.get_class_table) == "function"
                        and ST:get_class_table().hunter_melee_stack ~= false then
                        return base .. " While the hunter melee stack is on, this hand follows "
                            .. "the ranged bar's width; turn it off under Hunter -> Melee Bars."
                    end
                    return base
                end,
                min = 100, max = 600, step = 1,
                get = function()
                    if hand == "offhand" then
                        -- The width the offhand actually renders at: the mainhand's key.
                        local mainhand = ST:get_hand_table("mainhand")
                        if type(mainhand) == "table" and type(mainhand.bar_width) == "number" then
                            return mainhand.bar_width
                        end
                    end
                    local db = ST:get_hand_table(hand)
                    return type(db) == "table" and db.bar_width or nil
                end,
                set = function(_, value)
                    -- A write aimed at the offhand lands on the key that actually sizes it
                    -- (the mainhand's); the disabled gate below keeps the UI off this path.
                    local target = hand
                    if hand == "offhand" then
                        target = "mainhand"
                    end
                    local db = ST:get_hand_table(target)
                    if type(db) == "table" then
                        db.bar_width = value
                    end
                    -- The mainhand pass also cascades to the built offhand (bars.lua), so one
                    -- hand's reconfigure covers the rendered pair.
                    ST:configure_bar_size_and_positions(target)
                    ST:configure_bar_appearances(target)
                    ST:configure_bar_outline(target)
                    ST:configure_gcd_markers(target)
                    ST:set_gcd_marker_positions(target)
                    ST:configure_deadzone(target)
                    ST:set_deadzone_width(target)
                end,
                disabled = function()
                    -- Locked: the offhand's own width key never sizes the bar, so showing it
                    -- as editable would be the lie this widget exists to end.
                    return hand == "offhand"
                end,
            },
            [hand .. "bar_height"] = {
                type = "range",
                order = 1.02 + offset,
                name = "Height",
                -- Honest per-hand height (operator order 2026-10-28; brief L3). Two rules
                -- decide what this widget may show:
                --   * while the class-level melee pair height is set, BOTH melee hands render
                --     at it, so the widget shows it and is locked (the pair widget below owns
                --     the value);
                --   * the OFFHAND always renders at the mainhand's height (the size
                --     invariant in bars.lua), so with no pair height its widget shows the
                --     MAINHAND's height and is locked - the offhand's own saved key never
                --     sizes the bar, so showing it would be a lie.
                -- The ranged hand is never part of either rule.
                desc = function()
                    local base = "The pixel height of the swing timer."
                    if hand == "offhand" then
                        return base .. " The offhand always renders at the mainhand's height, "
                            .. "so this field follows the mainhand."
                    end
                    if hand == "mainhand" and type(ST.melee_pair_height) == "function"
                        and ST:melee_pair_height() ~= nil then
                        return base .. " Both melee bars currently follow the melee pair "
                            .. "height below; clear it there to size them separately."
                    end
                    return base
                end,
                min = 6, max = 60, step = 1,
                get = function()
                    if hand == "mainhand" or hand == "offhand" then
                        if type(ST.melee_pair_height) == "function" then
                            local pair = ST:melee_pair_height()
                            if pair ~= nil then
                                return pair
                            end
                        end
                    end
                    if hand == "offhand" then
                        local mainhand = ST:get_hand_table("mainhand")
                        if type(mainhand) == "table" and type(mainhand.bar_height) == "number" then
                            return mainhand.bar_height
                        end
                    end
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
                end,
                disabled = function()
                    if hand == "offhand" then
                        -- Locked always: the mainhand's height (or the pair's) is what the
                        -- offhand renders at; its own key is never read for sizing.
                        return true
                    end
                    if hand ~= "mainhand" then
                        return false
                    end
                    return type(ST.melee_pair_height) == "function"
                        and ST:melee_pair_height() ~= nil
                end,
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

    -- Melee pair height (operator order 2026-10-28; brief L3): ONE height for the mainhand
    -- and the offhand together. It is a CLASS-level key (documented in config_presets.lua),
    -- so it cannot live inside the per-hand loop above; order 3.5 puts it right after the
    -- last melee hand's controls and before the ranged hand's. Only a class that owns both
    -- melee hands gets it. The bounds mirror the per-hand Height widget (6..60 px).
    -- The hand set comes from iter_hands (the same authority the loop above uses), so a
    -- sandbox that stubs only iter_hands still builds the tree.
    local has_mainhand, has_offhand = false, false
    for hand in self:iter_hands() do
        if hand == "mainhand" then
            has_mainhand = true
        elseif hand == "offhand" then
            has_offhand = true
        end
    end
    if has_mainhand and has_offhand then
        opts_group.args.melee_pair_header = {
            type = "header",
            order = 3.5,
            name = "Melee pair (mainhand + offhand)",
        }
        opts_group.args.melee_pair_desc = {
            type = "description",
            order = 3.51,
            name = "One height for both melee bars. While it is set the mainhand and the "
                .. "offhand render at exactly this height (the offhand already matches the "
                .. "mainhand's width). Clear it to size the two hands separately again.",
        }
        opts_group.args.melee_pair_height = {
            type = "range",
            order = 3.52,
            name = "Melee pair height (both hands)",
            desc = "Pixel height applied to BOTH melee bars. Clear it with the button below "
                .. "to go back to each hand's own height.",
            min = 6, max = 60, step = 1,
            get = function()
                if type(ST.melee_pair_height) == "function" then
                    local pair = ST:melee_pair_height()
                    if pair ~= nil then
                        return pair
                    end
                end
                local mainhand = ST:get_hand_table("mainhand")
                return (type(mainhand) == "table" and mainhand.bar_height) or 20
            end,
            set = function(_, value)
                local height = tonumber(value)
                if height == nil or height <= 0 then
                    return
                end
                local class_db = ST:get_class_table()
                if type(class_db) ~= "table" then
                    return
                end
                class_db.melee_bar_height = height
                -- One pass sizes the mainhand and the built offhand (the size cascade).
                if type(ST.configure_bar_size_and_positions) == "function" then
                    ST:configure_bar_size_and_positions("mainhand")
                end
            end,
        }
        opts_group.args.melee_pair_height_reset = {
            type = "execute",
            order = 3.53,
            name = "Use each hand's own height",
            desc = "Clears the pair height so the mainhand and offhand use their own saved "
                .. "heights again (the offhand still follows the mainhand).",
            func = function()
                local class_db = ST:get_class_table()
                if type(class_db) ~= "table" then
                    return
                end
                -- nil = the shipped behaviour (config_presets.lua documents why there is no
                -- stored default for this key). No per-hand key is rewritten.
                class_db.melee_bar_height = nil
                if type(ST.configure_bar_size_and_positions) == "function" then
                    ST:configure_bar_size_and_positions("mainhand")
                end
                if ST.options_table_name then
                    local ok, ACR = pcall(LibStub, "AceConfigRegistry-3.0", true)
                    if ok and type(ACR) == "table" and type(ACR.NotifyChange) == "function" then
                        pcall(ACR.NotifyChange, ACR, ST.options_table_name)
                    end
                end
            end,
        }
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
    -- NOTE: no `title` local here: the group name comes from settings.panel_title
    -- below; settings.title has no other reader, so fetching it was dead.

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
            set = "enabled_setter",
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

    -- One-time appearance migration BEFORE any widget can read a colour (the getters
    -- read lazily when a panel renders): the bar backdrop default became opaque and
    -- AceDB never overwrites a saved key (config.lua owns the pure function and the
    -- versioned flag). main.lua creates AceDB and then calls set_opts()
    -- (main.lua:416-424), and bars.lua builds the backdrops later in init_libs, so this
    -- is the first settings-aware seam on the init path. Both calls are pcall'd: a bad
    -- profile or a migration fault must never abort the options build (or login).
    if type(self.migrate_appearance_defaults) == "function"
        and type(self.get_profile_table) == "function" then
        local read_ok, profile = pcall(self.get_profile_table, self)
        if read_ok then
            pcall(self.migrate_appearance_defaults, profile)
        end
    end

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