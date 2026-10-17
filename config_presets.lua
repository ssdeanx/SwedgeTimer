------------------------------------------------------------------------------------
-- Module to contain config default settings for the addon, per class and global
------------------------------------------------------------------------------------
local addon_name, st = ...
local LSM = LibStub("LibSharedMedia-3.0")
---@type AceAddon
---@class AceAddon
---@field class_defaults table
---@field bar_defaults table
---@field DEATHKNIGHT table
---@field DRUID table
---@field HUNTER table
---@field MAGE table
---@field PALADIN table
---@field PRIEST table
---@field ROGUE table
---@field SHAMAN table
---@field WARLOCK table
---@field WARRIOR table
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)



-- This table is used for any per-class settings that should apply globally.
ST.class_defaults = {
    class_enabled = true,
    timers_locked = true,
    bar_movement_mode = "all",
    enable_spec1 = true,
    enable_spec2 = true,

    -- Cooldown HUD (hud.lua): shared defaults for every class. The per-slot toggles
    -- (hud_show_<key>) and any class-specific descriptors live in the class's own
    -- defaults - ST.PALADIN.defaults below for the paladin slot set. Off by default
    -- so nothing new appears until it is enabled.
    hud_enabled = false,
    hud_visibility_key = "always",
    hud_locked = true,
    hud_x = 0,
    hud_y = -236,
    hud_scale = 1,
    hud_icon_size = 36,
    hud_match_bar_width = false,
    hud_spacing = 2,
    hud_orientation = "horizontal",
    hud_show_text = true,
    hud_font = "Expressway",
    hud_text_size = 16,
    hud_text_outline = "outline",
    -- Text/border colours follow the addon's 0-255 storage convention (so the standard
    -- color_getter/color_setter option widgets apply); hud.lua converts through
    -- convert_color. Defaults are the archive's (hud.lua:567-570) converted up.
    hud_text_color = {250, 255, 0, 1},
    hud_text_warn_color = {255, 102, 107, 1},
    hud_border_size = 2,
    hud_border_color = {0, 0, 0, 1},
    hud_glow_enabled = true,
    hud_desaturate = true,
    hud_mana_tint = true,
    hud_range_tint = true,

    -- Rotation label (rotationtext.lua): shared defaults for every class - the module
    -- stays inert for classes that do not provide get_rotation_key, so the keys are
    -- harmless there. Off by default; the paladin's options section edits them.
    -- rotation_label_x/y are the offsets of the label's anchor point (its left, centre
    -- or right edge, per rotation_label_align) from the screen centre, in screen pixels.
    rotation_label_enabled = false,
    rotation_label_visibility_key = "always",
    rotation_label_format = "key",
    rotation_label_align = "center",
    rotation_label_x = 0,
    rotation_label_y = -150,
    rotation_label_scale = 1,
    rotation_label_locked = true,
    rotation_label_font = "Expressway",
    rotation_label_size = 16,
    rotation_label_outline = "outline",
    -- 0-255 RGB + 0-1 alpha (the addon's storage convention, so the standard
    -- color_getter/color_setter widgets apply); the archive's {1.0, 0.82, 0.0, 1.0}
    -- converted up.
    rotation_label_color = {255, 209, 0, 1},

    -- Design mode (designmode.lua): the persisted grid / snap settings, shared for every
    -- class. The enabled state is a session state and is deliberately NOT stored. The
    -- grid step treats anything below 8 px as off (design.MIN_GRID - the archive rule);
    -- snap_threshold is the alignment magnet in pixels (the archive's CENTER_MAGNET).
    design_grid_enabled = true,
    design_grid = 24,
    design_snap = true,
    design_snap_threshold = 8,

    -- Melee-weave proximity bar (weave_range.lua): shared default for every class, off
    -- by default. The top-level options toggle edits it; the module hides its frame
    -- whenever it is off.
    weave_range_enabled = false,
}

-- This table is used by AceDB's smart defaults feature
-- so we only have to override behaviour in class-specific tables.
ST.bar_defaults = {

    -- Visibility behaviour
    enabled = true,
    show_behaviour = "conditional",  -- can be conditional or always
    show_condition = "either",
    require_in_range = false,

    -- Out of range behaviour
    dim_oor = true,
    dim_alpha = 0.6,

    -- Bar dimensions
    bar_height = 20,
    bar_width = 275,

    -- Bar positions (handled by LibWindow-1.1)
    x = 0,
    y = -120,
    point = "CENTER",
    scale = 1,

    -- Timer bar appearance
    bar_texture_key = "Minimalist",
    bar_color_default = {93, 58, 207, 0.6},

    -- Background and border appearance
    background_color = {0.0, 0.0, 0.0, 0.85},
    background_texture_key = "Solid",

    border_color = {40, 40, 40, 0.95},
    border_texture_key = "Square Full White",
    border_width = 2,

    -- Bar Texts
    text_size = 14,
    text_color = {255, 255, 255, 1.0},
    text_font = "Expressway",
    text_outline_key = "outline",

    left_text_key  = "attack_speed",
    left_text_enabled = true,
    left_text_hide_inactive = false,
    left_text_x_percent_offset = 0,
    left_text_y_percent_offset = 0,

    center_text_key = "range_finder",
    center_text_enabled = false,
    center_text_hide_inactive = false,
    center_text_x_percent_offset = 0,
    center_text_y_percent_offset = 0,

    right_text_key = "swing_timer",
    right_text_enabled = true,
    right_text_hide_inactive = true,
    right_text_x_percent_offset = 0,
    right_text_y_percent_offset = 0,

    -- GCD underlay
    show_gcd_underlay = true,
    bar_color_gcd = {140, 140, 140, 0.85},
    gcd_texture_key = "Minimalist",

    -- GCD markers
    gcd1a_marker_enabled = true,
    gcd1a_marker_anchor = "endofswing",
    gcd1a_marker_hide_inactive = true,
    gcd1a_marker_mode = "phys",
    gcd1a_marker_color = {230, 230, 230, 1.0},
    gcd1a_marker_width = 2,
    gcd1a_marker_fractional_height = 0.25,
    gcd1a_swing_anchor_wrap = true,

    gcd1b_marker_enabled = true,
    gcd1b_marker_anchor = "endofswing",
    gcd1b_marker_hide_inactive = true,
    gcd1b_marker_mode = "phys",
    gcd1b_marker_color = {230, 230, 230, 1.0},
    gcd1b_marker_width = 2,
    gcd1b_marker_fractional_height = 0.25,
    gcd1b_swing_anchor_wrap = true,

    -- Deadzone settings
    enable_deadzone = false,
    deadzone_texture_key = "Solid",
    deadzone_bar_color = {141, 59, 81, 0.82},
    deadzone_hide_inactive = true,

    -- Show range
    show_range_finder = false,

}

------------------------------------------------------------------------------------
-- DEATHKNIGHT
------------------------------------------------------------------------------------
ST.DEATHKNIGHT.defaults = {
    -- Bar options
    ['**'] = ST.bar_defaults,
	mainhand = {
        enable_deadzone = true,
        gcd1a_marker_mode = "phys",
        gcd1b_marker_mode = "spell",
    },
	offhand = {
        y = -142,
		bar_color_default = {13, 79, 115, 0.8},
        show_gcd_underlay = false,
        gcd1a_marker_enabled = false,
        gcd1b_marker_enabled = false,
	},
}

------------------------------------------------------------------------------------
-- DRUID
------------------------------------------------------------------------------------
ST.DRUID.defaults = {
    -- Class-level options
    enable_maul_color = true,
    maul_color = {112, 19, 189, 1.0},
    insufficient_rage_color = {140, 140, 140, 1.0},

    -- Druid trackers (reference SuperSwingTimer_ClassMods.lua druid block 4514-5524):
    -- the cat-form energy tick bar, the mainhand form label and the Mangle/Rip/Rake
    -- target debuff bars. All default on. Colours are 0-255 RGB + 0-1 alpha like the
    -- other class colours (converted through the same convert_color path); the tree
    -- defaults mirror the reference's fills (ClassMods.lua:4814, 4946, 5091 and the
    -- druidEnergyTick colour, Constants.lua:982).
    show_druid_energy_tick = true,
    druid_energy_tick_color = {255, 209, 46, 1.0},
    show_druid_form_label = true,
    show_druid_mangle_bar = true,
    druid_mangle_bar_color = {230, 153, 26, 0.90},
    show_druid_rip_bar = true,
    druid_rip_bar_color = {51, 191, 51, 0.90},
    show_druid_rake_bar = true,
    druid_rake_bar_color = {217, 102, 26, 0.90},

    -- Next Action Guide (the shared nextaction_ui frame driven by ST.DRUID.guide in
    -- classes/druid.lua; the decision model is the pure druid_guide.lua). Default OFF:
    -- a wrong prompt is worse than none, so the owner enables it after in-client
    -- verification. Key names match the paladin's/warrior's so the shared frame reads
    -- them unchanged; guide_rip_refresh/guide_rake_refresh are the druid-only debuff
    -- refresh thresholds (seconds).
    nextaction_enabled = false,
    nextaction_locked = true,
    nextaction_visibility_key = "in_combat",
    nextaction_icon_size = 45,
    nextaction_x = 0,
    nextaction_y = -180,
    guide_rip_refresh = 4,
    guide_rake_refresh = 4,

    -- Cooldown HUD: the druid slot toggles (the shared hud_* keys live in
    -- ST.class_defaults; the descriptors they gate are ST.DRUID.HUD_SLOTS in
    -- classes/druid.lua). Slot toggles ship on: the HUD master hud_enabled
    -- ships off in the shared defaults, so nothing surfaces until enabled.
    hud_show_maul = true,
    hud_show_mangle = true,
    hud_show_rip = true,
    hud_show_rake = true,
    hud_show_bite = true,
    hud_show_shred = true,
    hud_show_trinket1 = true,
    hud_show_trinket2 = true,

    -- Form-dependent visibility defaults
    form_vis_normal = true,
    form_vis_bear = true,
    form_vis_cat = true,
    form_vis_moonkin = true,
    form_vis_tree = true,
    form_vis_travel = true,
    form_vis_flight = true,

    use_form_colors = true,
    form_color_bear = {159, 4, 44, 1.0},
    form_color_cat = {189, 126, 9, 1.0},
    form_color_moonkin = {4, 148, 214, 1.0},
    form_color_tree = {4, 204, 124, 1.0},
    form_color_travel = {18, 85, 201, 1.0},
    form_color_flight = {18, 85, 201, 1.0},

    -- Bar options
    ['**'] = ST.bar_defaults,
    mainhand = {
        enable_deadzone = true,
        bar_color_default = {18, 85, 201, 1.0},
        gcd1a_marker_mode = "form",
        gcd1b_marker_mode = "form",
    },
    offhand = {
        enabled = false,
    },
    ranged = {
        enabled = false,
    },
}

------------------------------------------------------------------------------------
-- HUNTER
------------------------------------------------------------------------------------
ST.HUNTER.defaults = {

    enable_raptor_strike_color = true,
    raptor_strike_color = {207, 58, 83, 1.0},

    -- Steady Shot queueing colour. Off by default: the detection is opt-in until
    -- the Steady Shot rank ids have been confirmed in-client.
    enable_steady_shot_color = false,
    steady_shot_color = {211, 145, 12, 1.0},

    -- Hunter visual set (hunter_ui.lua): the cast bar above the ranged bar, the 4-state
    -- range helper strip, the Rapid Fire aura bar and the aspect icon. All enabled by
    -- default; the widgets only appear while the ranged bar is usable (never on clients
    -- without a ranged swing, e.g. Retail). The cast-bar colour is stored as 0-1 floats
    -- (it feeds SetVertexColor directly, unlike the 0-255 class colours).
    hunter_cast_bar_enabled = true,
    hunter_cast_bar_height = 15,
    hunter_cast_bar_color = {0.35, 0.65, 0.95, 1.0},
    hunter_range_helper_enabled = true,
    hunter_rapid_fire_bar_enabled = true,
    hunter_aspect_icon_enabled = true,

    -- Next Action Guide (the shared nextaction_ui frame driven by ST.HUNTER.guide in
    -- classes/hunter.lua; the decision model is the pure hunter_guide.lua). Default OFF:
    -- a wrong prompt is worse than none, so the owner enables it after in-client
    -- verification. Key names match the paladin's so the shared frame reads them
    -- unchanged; the hunter guide carries no class-specific thresholds.
    nextaction_enabled = false,
    nextaction_locked = true,
    nextaction_visibility_key = "in_combat",
    nextaction_icon_size = 45,
    nextaction_x = 0,
    nextaction_y = -180,

    -- Cooldown HUD: the hunter slot toggles (the shared hud_* keys live in
    -- ST.class_defaults; the descriptors they gate are ST.HUNTER.HUD_SLOTS in
    -- classes/hunter.lua). Slot toggles ship on: the HUD master hud_enabled
    -- ships off in the shared defaults, so nothing surfaces until enabled.
    hud_show_steady = true,
    hud_show_raptor = true,
    hud_show_kill_command = true,
    hud_show_multi = true,
    hud_show_bestial_wrath = true,
    hud_show_rapid_fire = true,
    hud_show_aimed = true,
    hud_show_trinket1 = true,
    hud_show_trinket2 = true,

    -- Bar options
    ['**'] = ST.bar_defaults,
    mainhand = {
        require_in_range = true,
        show_condition = "both",
        bar_height = 14,
		bar_width = 200,
        show_gcd_underlay = false,
        gcd1a_marker_enabled = false,
        gcd1b_marker_enabled = false,
        border_width = 1,
        text_size = 10,
        y = -142,
    },
    offhand = {
        require_in_range = true,
        show_condition = "both",
		bar_color_default = {13, 79, 115, 0.8},
        show_gcd_underlay = false,
        gcd1a_marker_enabled = false,
        gcd1b_marker_enabled = false,
        bar_height = 14,
		bar_width = 200,
        text_size = 10,
        border_width = 1,
        y = -158,
	},
	ranged = {
        enable_deadzone = true,
        require_in_range = false,
        force_show_in_combat = false,
		bar_color_default = {6, 143, 47, 0.8},
        gcd1a_marker_enabled = false,
        gcd1b_marker_enabled = false,
        show_gcd_underlay = true,
        center_text_enabled = true,
	},
}

------------------------------------------------------------------------------------
-- MAGE
------------------------------------------------------------------------------------
ST.MAGE.defaults = {
    class_enabled = false,
    -- Bar options
    ['**'] = ST.bar_defaults,
    mainhand = {
        enabled = false,
        y = -142,
        gcd1a_marker_mode = "spell",
        gcd1b_marker_mode = "spell",

    },
    ranged = {
        bar_x_offset = 0,
		bar_y_offset = -102,
        bar_color_default = {125, 10, 201, 1.0},
        gcd1a_marker_mode = "spell",
        gcd1b_marker_mode = "spell",
    }
}

------------------------------------------------------------------------------------
-- PALADIN
------------------------------------------------------------------------------------
ST.PALADIN.defaults = {
    tag = "PALADIN",
    has_class_options = true,

    use_seal_colors = true,
    soc_color = {47, 128, 10, 1.0},
    sov_color = {192, 60, 38, 1.0},
    sol_color = {6, 140, 104, 1.0},
    sow_color = {22, 100, 117, 1.0},
    sor_color = {207, 58, 165, 1.0},
    soj_color = {204, 185, 18, 1.0},
    sob_color = {219, 97, 28, 1.0},
    sotc_color = {230, 191, 107, 1.0},

    -- Seal twisting (per the archived build's feature set).
    twist_enabled = true,
    twist_feedback_enabled = true,
    twist_marker_enabled = true,
    twist_padding_mode = "None",
    twist_window_padding_ms = 0,
    lag_detection_enabled = true,
    lag_multiplier = 1.4,
    lag_offset = 15,

    -- Twist helper visuals (window band, state colors, success text).
    twist_marker_color = {255, 255, 255, 0.35},
    twist_color_twisting = {179, 26, 153, 1.0},
    twist_color_cant = {212, 212, 3, 1.0},
    twist_success_text_enabled = true,
    twist_success_text_color = {90, 255, 90, 1.0},
    twist_success_text_size = 24,
    twist_success_text_duration = 1.5,

    -- Judgement marker line + standalone seal icons (archived TBC bar visuals,
    -- docs/swedge/SwedgeTimer_TBC/bar.lua:270-272/1750-1786 and 826-910). Core
    -- rotation feedback, so all default on; the colours/sizes are constants in
    -- classes/paladin.lua (only the enables are options).
    judgement_marker_enabled = true,
    seal_icons_enabled = true,

    -- Twist-success glow (archived bar.lua:551-616, Pixel at minimum). Fires on
    -- the twist attempt like the archive; the lines/frequency/thickness are
    -- constants in classes/paladin.lua (the HUD's Pixel parameters).
    twist_success_glow_enabled = true,
    twist_success_glow_color = {0, 255, 0, 0.8},
    twist_success_glow_duration = 0.4,

    -- Twist feedback sounds (ported from the archived build; all off by default).
    twist_sound_enabled = false,
    twist_sound_choice = "pop",
    twist_success_sound_enabled = false,
    twist_success_sound_choice = "TadaFanfare",
    sound_channel = "Master",

    -- Next Action Guide (archived rotation prompt ported to the live addon).
    nextaction_enabled = true,
    nextaction_locked = true,
    nextaction_visibility_key = "in_combat",
    nextaction_icon_size = 45,
    nextaction_x = 0,
    nextaction_y = -180,
    nextaction_reaction_time_ms = 100,
    -- TBC: researched CS delay is under 1 s (was 1700). CONFLICT: Wrath wants
    -- ~0 (no twist to protect); revisit with a family branch if needed. The
    -- option range is unchanged.
    nextaction_cs_max_delay_ms = 900,
    nextaction_hold_enabled = true,
    nextaction_show_rotation_text = true,
    nextaction_show_label = true,
    nextaction_show_judgement = true,
    nextaction_show_fillers = true,
    nextaction_filler_mana_consecration = 35,
    nextaction_filler_mana_exorcism = 30,

    use_aow_glow = true,
    require_exo_ready = true,
    aow_glow_color = {209, 198, 115, 1.0},
    aow_glow_nlines = 12,
    aow_glow_freq = 0.1,
    aow_glow_line_length = 12,

    -- Twist Practice (phase 2 UI; the key names stay archive-compatible for the later
    -- phases). practice_weapon_speed is the practice swing base speed: 0 uses the
    -- equipped weapon speed. practice_panel_x/y are offsets from the panel's anchor,
    -- added to the archive's 8 px gap right of the mainhand bar.
    practice_result_duration = 0.8,
    practice_result_text_size = 28,
    practice_result_color_hit = {0, 1, 0, 1},
    practice_result_color_miss = {1, 0.2, 0.2, 1},
    practice_weapon_speed = 0,
    practice_panel_x = 0,
    practice_panel_y = 0,

    -- Cooldown HUD: the paladin slot toggles (the shared hud_* keys live in
    -- ST.class_defaults above; the descriptors they gate are ST.PALADIN.HUD_SLOTS in
    -- classes/paladin.lua). Other classes add their own hud_show_<key> keys here in
    -- their own defaults when they declare slots.
    hud_show_cs = true,
    hud_show_judgement = true,
    hud_show_consecration = true,
    hud_show_exorcism = true,
    hud_show_trinket1 = true,
    hud_show_trinket2 = true,
    hud_show_wings = true,

    -- Bar options
    ['**'] = ST.bar_defaults,
	mainhand = {

        -- bar_color_default = {150, 18, 97, 0.9},

        enable_deadzone = true,
        gcd1a_marker_mode = "phys",
        gcd1b_marker_mode = "spell",
        -- gcd1a_marker_anchor = "swing",
        -- gcd1b_marker_anchor = "swing",
        gcd1a_swing_anchor_wrap = false,
        gcd1b_swing_anchor_wrap = false,
    },
}

------------------------------------------------------------------------------------
-- PRIEST
------------------------------------------------------------------------------------
ST.PRIEST.defaults = {
    class_enabled = false,
    -- Bar options
    ['**'] = ST.bar_defaults,
    mainhand = {
        enabled = false,
        y = -142,
        gcd1a_marker_mode = "spell",
        gcd1b_marker_mode = "spell",

    },
    ranged = {
        bar_x_offset = 0,
		bar_y_offset = -102,
        bar_color_default = {125, 10, 201, 1.0},
        gcd1a_marker_mode = "spell",
        gcd1b_marker_mode = "spell",
    }
}

------------------------------------------------------------------------------------
-- ROGUE
------------------------------------------------------------------------------------
ST.ROGUE.defaults = {
    -- Bar options
    ['**'] = ST.bar_defaults,
	mainhand = {
        enable_deadzone = true,
    },
	offhand = {
        y = -142,
		bar_color_default = {13, 79, 115, 0.8},
        show_gcd_underlay = false,
        gcd1a_marker_enabled = false,
        gcd1b_marker_enabled = false,
	},
	ranged = {
        enabled = false,
        show_behaviour = "conditional",
        show_condition = "either",
        require_in_range = true,
		bar_height = 15,
		bar_width = 200,
        y = -166,
		bar_color_default = {112, 8, 11, 0.8},
		font_size = 10,
        show_gcd_underlay = false,
        show_gcd_markers = false,
        show_range_finder = true,
        gcd1a_marker_enabled = false,
        gcd1b_marker_enabled = false,
	},
}

------------------------------------------------------------------------------------
-- SHAMAN
------------------------------------------------------------------------------------
ST.SHAMAN.defaults = {
    -- Spell weaving assist (Enhancement shaman LB weaving; math lives in weave.lua).
    weave_enabled = true,
    weave_mw_enabled = true,
    weave_marker_size = 6,
    weave_marker_alpha = 1,
    weave_spark_width = 3,
    weave_spark_height = 15,
    weave_spark_alpha = 0.95,
    weave_families = {
        LB = true,
        CL = true,
        HW = true,
        LHW = true,
        CH = true,
    },

    -- Enhancement trackers (ported from the reference's shaman block): the reference
    -- breakpoint markers + offhand spark mirror, the Windfury Weapon ICD strip, the
    -- Flame Shock target bar, the Stormstrike / Shamanistic Rage badges and the shield
    -- charge row. All default on.
    show_shaman_breakpoint_markers = true,
    show_shaman_windfury_icd = true,
    show_shaman_flame_shock_bar = true,
    show_shaman_cooldown_badges = true,
    show_shaman_shield_charges = true,

    -- Next Action Guide (the shared nextaction_ui frame driven by ST.SHAMAN.guide in
    -- classes/shaman.lua; the decision model is the pure shaman_guide.lua). Default
    -- OFF: a wrong prompt is worse than none, so the owner enables it after in-client
    -- verification. Key names match the paladin's/warrior's so the shared frame reads
    -- them unchanged; guide_flameshock_refresh is the shaman-only refresh threshold.
    nextaction_enabled = false,
    nextaction_locked = true,
    nextaction_visibility_key = "in_combat",
    nextaction_icon_size = 45,
    nextaction_x = 0,
    nextaction_y = -180,
    guide_flameshock_refresh = 3,

    -- Cooldown HUD: the shaman slot toggles (the shared hud_* keys live in
    -- ST.class_defaults; the descriptors they gate are ST.SHAMAN.HUD_SLOTS in
    -- classes/shaman.lua). Slot toggles ship on: the HUD master hud_enabled
    -- ships off in the shared defaults, so nothing surfaces until enabled.
    hud_show_stormstrike = true,
    hud_show_flameshock = true,
    hud_show_weave = true,
    hud_show_firenova = true,
    hud_show_earthshock = true,
    hud_show_twist = true,
    hud_show_trinket1 = true,
    hud_show_trinket2 = true,

    -- Bar options
    ['**'] = ST.bar_defaults,
	mainhand = {
        enable_deadzone = true,
        gcd1a_marker_mode = "phys",
        gcd1b_marker_mode = "spell",
    },
	offhand = {
        y = -142,
		bar_color_default = {13, 79, 115, 0.8},
        show_gcd_underlay = false,
        gcd1a_marker_enabled = false,
        gcd1b_marker_enabled = false,
	},
}

------------------------------------------------------------------------------------
-- WARLOCK
------------------------------------------------------------------------------------
ST.WARLOCK.defaults = {
    class_enabled = false,
    -- Bar options
    ['**'] = ST.bar_defaults,
    mainhand = {
        y = -142,
        enabled = false,
        gcd1a_marker_mode = "spell",
        gcd1b_marker_mode = "spell",

    },
    ranged = {
        bar_x_offset = 0,
		bar_y_offset = -102,
        bar_color_default = {125, 10, 201, 1.0},
        gcd1a_marker_mode = "spell",
        gcd1b_marker_mode = "spell",
    }
}

------------------------------------------------------------------------------------
-- WARRIOR
------------------------------------------------------------------------------------
ST.WARRIOR.defaults = {
    -- Class-level options
    enable_hs_color = true,
    hs_color = {130, 7, 9, 1.0},
    enable_cleave_color = true,
    cleave_color = {64, 130, 7, 1.0},
    insufficient_rage_color = {140, 140, 140, 1.0},

    use_bloodsurge_glow = true,
    bloodsurge_glow_color = {227, 57, 74, 1.0},
    bloodsurge_glow_nlines = 12,
    bloodsurge_glow_freq = 0.1,
    bloodsurge_glow_line_length = 12,

    -- Warrior trackers (reference SuperSwingTimer_ClassMods.lua warrior block 1689-3333):
    -- the Shield Block bar, the Slam cast bar, the Overpower proc flash and the Deep
    -- Wounds / Sunder Armor / Rend / Thunder Clap / Demo Shout target debuff bars. All
    -- default on. Colours are 0-255 RGB + 0-1 alpha like the other class colours
    -- (converted through the same convert_color path); the fills mirror the reference's
    -- (ClassMods.lua:2273, 2413, 2565, 2705, 2844 and the shieldBlockBar colour,
    -- Constants.lua:1006).
    show_warrior_deep_wounds_bar = true,
    warrior_deep_wounds_bar_color = {179, 38, 38, 0.90},
    show_warrior_sunder_armor_bar = true,
    warrior_sunder_armor_bar_color = {140, 89, 38, 0.90},
    show_warrior_rend_bar = true,
    warrior_rend_bar_color = {217, 38, 26, 0.90},
    show_warrior_thunder_clap_bar = true,
    warrior_thunder_clap_bar_color = {89, 140, 191, 0.90},
    show_warrior_demo_shout_bar = true,
    warrior_demo_shout_bar_color = {166, 128, 77, 0.90},
    show_warrior_shield_block_bar = true,
    warrior_shield_block_bar_color = {51, 140, 255, 0.90},
    show_warrior_slam_cast_bar = true,
    show_warrior_overpower_flash = true,
    show_warrior_rampage_badge = true,

    -- Next Action Guide (the shared nextaction_ui frame driven by ST.WARRIOR.guide in
    -- classes/warrior.lua; the decision model is the pure warrior_guide.lua). Default
    -- OFF: a wrong prompt is worse than none, so the owner enables it after in-client
    -- verification. Key names match the paladin's so the shared frame reads them
    -- unchanged; guide_execute_pct is the warrior-only Execute-range threshold.
    nextaction_enabled = false,
    nextaction_locked = true,
    nextaction_visibility_key = "in_combat",
    nextaction_icon_size = 45,
    nextaction_x = 0,
    nextaction_y = -180,
    guide_execute_pct = 20,

    hide_in_tank_spec = false,
    hide_in_arms_spec = false,

    -- Cooldown HUD: the warrior slot toggles (the shared hud_* keys live in
    -- ST.class_defaults; the descriptors they gate are ST.WARRIOR.HUD_SLOTS in
    -- classes/warrior.lua). The union of both family sets ships on (cleave is
    -- the non-TBC slot, bt/ww the TBC ones): the HUD master hud_enabled ships
    -- off in the shared defaults, so nothing surfaces until enabled.
    hud_show_op = true,
    hud_show_execute = true,
    hud_show_slam = true,
    hud_show_hs = true,
    hud_show_cleave = true,
    hud_show_bt = true,
    hud_show_ww = true,
    hud_show_trinket1 = true,
    hud_show_trinket2 = true,

    -- Bar options
    ['**'] = ST.bar_defaults,
	mainhand = {
        enable_deadzone = true,
    },
	offhand = {
        y = -142,
		bar_color_default = {13, 79, 115, 0.8},
        show_gcd_underlay = false,
        gcd1a_marker_enabled = false,
        gcd1b_marker_enabled = false,
	},
	ranged = {
        enabled = false,
        show_behaviour = "conditional",
        show_condition = "either",
        require_in_range = true,
		bar_height = 15,
		bar_width = 200,
        y = -166,
		bar_color_default = {112, 8, 11, 0.8},
		font_size = 10,
        show_gcd_underlay = false,
        show_gcd_markers = false,
        show_range_finder = true,
        gcd1a_marker_enabled = false,
        gcd1b_marker_enabled = false,
	},
}

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed config_presets.lua module correctly') end