------------------------------------------------------------------------------------
-- Module to contain config default settings for the addon, per class and global
------------------------------------------------------------------------------------
local addon_name, st = ...
-- No LSM fetch here: this file only declares default values (plain media-key
-- strings); this file's only LSM handle lives in option_table_presets.lua
-- (values = LSM:HashTable), which resolves them when the widgets are built.
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
    enable_spec2 = false,

    -- Cooldown HUD (hud.lua): shared defaults for every class. The per-slot toggles
    -- (hud_show_<key>) and any class-specific descriptors live in the class's own
    -- defaults - ST.PALADIN.defaults below for the paladin slot set. On by default
    -- (owner order 2026-10-19 on-by-default package: a fresh profile shows
    -- bars+HUD+guide). Nil-safe: hud.lua should_show hides on == false and
    -- apply_settings enables on ~= false, so nil reads as on, matching true.
    hud_enabled = true,
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
    hud_zoom = true,

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

    -- Class activation (main.lua: ST:activate_class). Operator order 2026-10-21: only
    -- the SELECTED class's module executes. "Auto" is the default: it activates the
    -- class being played, so a rogue session is unchanged. An explicit class token
    -- (DRUID/HUNTER/PALADIN/ROGUE/SHAMAN/WARRIOR) activates that class's module
    -- instead. Read at init, so a change applies at the next login/reload. Nil-safe:
    -- a stored false hides the options widget, and nil reads as "Auto".
    class_activation = "Auto",

    -- Practice progression visibility (practice_ui.lua): the panel's level badge and
    -- the session XP bar, plus the level-up and achievement chat notices, all ride
    -- THIS ONE db key on the class table (practice_panel_badge). The read is
    -- nil-safe (practice_ui.lua: ui.badge_is_enabled compares == true), so nil and
    -- false both hide the badge and silence the notices.
    --
    -- ON by default. GATE: the operator order of 2026-10-19 ("start at lvl 1, gain
    -- xp each practice, level up") is the explicit gate for this default-visible
    -- change - the request IS the gate, so a fresh profile shows the level badge,
    -- the session XP bar and the notices. The default only reaches a FRESH profile:
    -- a profile that saved false keeps false (the saved value wins over the
    -- default), and an old profile with no key at all still hides the surface
    -- (nil reads as off).
    practice_panel_badge = true,
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
    -- The swing bar and the GCD underlay are the addon's PROGRESS bars, so they take
    -- the operator's texture as their default (operator order, 2026-10-20 - that order
    -- IS the gate for the default-visible change). "Wglass" is registered as a
    -- statusbar medium in main.lua, so it is selectable in the texture dropdown.
    bar_texture_key = "Wglass",
    bar_color_default = {93, 58, 207, 0.85},

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
    -- The GCD underlay is a progress bar (it fills with the GCD), so it shares the
    -- swing bar's default texture - the operator's, per the order above.
    gcd_texture_key = "Wglass",

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
    -- The deadzone is a MARKER (a shaded latency region), not a progress bar, so it
    -- deliberately keeps the plain "Solid" fill and does not follow the progress
    -- bars' texture default.
    deadzone_texture_key = "Solid",
    deadzone_bar_color = {141, 59, 81, 0.82},
    deadzone_hide_inactive = true,

    -- Show range
    show_range_finder = false,

    -- Leading edge spark & completion flash (visual brainstorm items 1 & 2)
    show_spark = true,
    spark_width = 4,
    spark_color = {255, 255, 255, 1.0},

    enable_flash = true,
    flash_duration = 0.15,
    flash_color = {255, 255, 255, 0.6},
    theme_preset = nil,

}

-- Ready-made visual theme presets (visual brainstorm item 3)
ST.THEME_PRESETS = {
    midnight = {
        name = "Midnight Velvet",
        desc = "Deep navy/velvet dark background, crisp slate borders, bright white leading edge spark.",
        bar_texture_key = "Wglass",
        background_color = {15, 18, 25, 0.90},
        border_color = {45, 55, 72, 1.0},
        border_width = 2,
        show_spark = true,
        spark_color = {255, 255, 255, 1.0},
        enable_flash = true,
        flash_color = {200, 220, 255, 0.6},
    },
    glass = {
        name = "Clean Glassmorphic",
        desc = "Modern frosted translucent look with clean light borders and responsive pulse.",
        bar_texture_key = "Wglass",
        background_color = {20, 25, 35, 0.65},
        border_color = {160, 175, 200, 0.8},
        border_width = 1,
        show_spark = true,
        spark_color = {230, 245, 255, 0.95},
        enable_flash = true,
        flash_color = {255, 255, 255, 0.5},
    },
    elvui = {
        name = "Minimalist / Flat",
        desc = "Flat statusbar with sharp 1px black outline and razor-sharp feedback.",
        bar_texture_key = "Flat",
        background_color = {10, 10, 10, 0.95},
        border_color = {0, 0, 0, 1.0},
        border_width = 1,
        show_spark = true,
        spark_color = {255, 255, 255, 1.0},
        enable_flash = true,
        flash_color = {255, 255, 255, 0.7},
    },
    classic = {
        name = "Classic Retro",
        desc = "Traditional Blizzard styling with classic solid textures and gray borders.",
        bar_texture_key = "Blizzard",
        background_color = {0, 0, 0, 0.85},
        border_color = {128, 128, 128, 1.0},
        border_width = 2,
        show_spark = false,
        enable_flash = false,
    },
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
    -- classes/druid.lua; the decision model is the pure druid_guide.lua). Default ON
    -- (owner order 2026-10-19 on-by-default package: a fresh profile shows
    -- bars+HUD+guide). Nil-safe: nextaction_ui.should_show hides on == false,
    -- so nil reads as on, matching true. Key names match the paladin's/warrior's so the shared frame reads
    -- them unchanged; guide_rip_refresh/guide_rake_refresh are the druid-only debuff
    -- refresh thresholds (seconds). Sim standing
    -- (bench/druid_rotation_audit_2026-10-19.md): TBC ripNow/rakeNow,
    -- Wrath ripNow/rakeNow, Forever F3/F4 and SoD canRip are all expiry-only
    -- (recast-when-missing, window 0) — the TBC/SoD/WRATH/FOREVER chains in
    -- druid_guide.lua already refresh on expiry and never read these windows.
    -- The shipped 4s windows only run on the legacy fallback chain (unknown
    -- families such as Cata/Mists, which have no sim among the in-scope repos),
    -- so they are kept as the legacy fallback, not a sim value.
    nextaction_enabled = true,
    nextaction_locked = true,
    nextaction_visibility_key = "in_combat",
    nextaction_icon_size = 45,
    nextaction_x = 0,
    nextaction_y = -180,
    guide_rip_refresh = 4,
    guide_rake_refresh = 4,
    -- TBC Rip combo-point floor (T1 override: nil falls back to the frozen
    -- RIP_MIN_CP_TBC = 4 at druid_guide.lua:515-520). Ships 4 = archived.
    guide_rip_min_cp = 4,

    -- Practice knobs (paladin parity, owner order 2026-10-19): the shared session
    -- (practice_ui.lua) reads these unprefixed keys from the class table
    -- (practice_weapon_speed at fight start, practice_result_* for the grade
    -- popup, practice_panel_x/y for the shared panel), so the druid panel edits
    -- them directly. Nil-safe: the session falls back to these same values when
    -- nil (0 speed = equipped, 0.8 s / 28 / green-red / 0,0), so shipping them
    -- changes no fresh-profile behaviour.
    practice_result_duration = 0.8,
    practice_result_text_size = 28,
    practice_result_color_hit = {0, 1, 0, 1},
    practice_result_color_miss = {1, 0.2, 0.2, 1},
    practice_weapon_speed = 0,
    practice_panel_x = 0,
    practice_panel_y = 0,

    -- Cooldown HUD: the druid slot toggles (the shared hud_* keys live in
    -- ST.class_defaults; the descriptors they gate are ST.DRUID.HUD_SLOTS in
    -- classes/druid.lua). Slot toggles ship on: the HUD master hud_enabled
    -- ships on in the shared defaults (owner order 2026-10-19 on-by-default
    -- package), so a fresh profile shows bars+HUD+guide together.
    hud_show_maul = true,
    hud_show_mangle = true,
    hud_show_rip = true,
    hud_show_rake = true,
    hud_show_bite = true,
    hud_show_shred = true,
    -- D-1 Claw mirror (bench/hud_parity_2026-10-19.md D-1): provider
    -- classes/druid.lua:2217-2222 reads == true (nil = off). Ship false = hidden
    -- (no default-visible change).
    hud_show_claw = false,
    -- D2: Tiger's Fury / Berserk join the row. Hide-on-false shape like every other
    -- slot toggle (nil behaves identically); shipping true only makes the options
    -- checkbox match the effective default.
    hud_show_tf = true,
    hud_show_berserk = true,
    hud_show_trinket1 = true,
    hud_show_trinket2 = true,
    -- Layout template selection (bench/hud_templates_2026-10-19.md §7): nil =
    -- Custom (current behavior, zero default-visible change). The curated sets
    -- live in ST.DRUID.HUD_TEMPLATES below; the options select applies one on
    -- explicit user pick only.
    hud_template = nil,

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

-- Ready-made Cooldown HUD layout templates (bench/hud_templates_2026-10-19.md
-- §§4/7-8: D-T1 Bleed Core, D-T2 Full Feral + Pops, D-T3 Bear Guard). Curated
-- visible-slot subsets + geometry over the existing hud_* db keys only (the HUD
-- renders in HUD_SLOTS declaration order; templates never reorder). Applied by
-- the hud_template options select on explicit user pick only; nil (Custom)
-- leaves every key untouched. D-T3 bear fit is UNCONFIRMED in-client (design
-- §4: no bear-tank source in corpus). Gallery shortlist 3/4
-- (bench/weakaura_templates_2026-10-19.md): Core rows are the Luxthos Era-line
-- visual-check target, Minimal cites the minimalist-bars precedent (in-client only).
-- Claw (bench/druid_styles_2026-10-19.md shortlist #3, Meatslab D3 density):
-- D-T1 stays the 4-icon minimal core (no new slots), D-T2 takes the builder,
-- D-T3 (bear) leaves it off.
ST.DRUID.HUD_TEMPLATES = {
    bleed_core = {
        label = "D-T1 Bleed Core",
        slots = {
            maul = false, mangle = true, rip = true, rake = true, bite = false,
            shred = true, claw = false, tf = false, berserk = false,
            trinket1 = false, trinket2 = false,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = false,
    },
    full_feral = {
        label = "D-T2 Full Feral + Pops",
        slots = {
            maul = true, mangle = true, rip = true, rake = true, bite = true,
            shred = true, claw = true, tf = true, berserk = true,
            trinket1 = true, trinket2 = true,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = true,
    },
    bear_guard = {
        label = "D-T3 Bear Guard",
        slots = {
            maul = true, mangle = true, rip = false, rake = false, bite = false,
            shred = false, claw = false, tf = false, berserk = true,
            trinket1 = true, trinket2 = true,
        },
        hud_icon_size = 32, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = false,
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
    -- The red Auto Shot cast window at the END of the ranged bar: a fixed 0.5 s band,
    -- never widened by latency (operator ruling 2026-10-22). Ships on: the zone is the
    -- stop-and-cast reference the hunter rotation is read against.
    hunter_cast_zone_enabled = true,
    hunter_range_helper_enabled = true,
    hunter_rapid_fire_bar_enabled = true,
    hunter_aspect_icon_enabled = true,

    -- Next Action Guide (the shared nextaction_ui frame driven by ST.HUNTER.guide in
    -- classes/hunter.lua; the decision model is the pure hunter_guide.lua). Default ON
    -- (owner order 2026-10-19 on-by-default package: a fresh profile shows
    -- bars+HUD+guide). Nil-safe: nextaction_ui.should_show hides on == false,
    -- so nil reads as on, matching true. Key names match the paladin's so the shared frame reads them
    -- unchanged; the hunter guide carries no class-specific thresholds (all
    -- hunter sim gaps are slots/inputs, not tunables:
    -- bench/hunter_rotation_audit_2026-10-19.md ranks LnL/Serpent/Arcane/Sniper
    -- as missing inputs/slots, with no threshold number to ship — filed
    -- follow-ups, not defaults).
    nextaction_enabled = true,
    nextaction_locked = true,
    nextaction_visibility_key = "in_combat",
    nextaction_icon_size = 45,
    nextaction_x = 0,
    nextaction_y = -180,

    -- Cooldown HUD: the hunter slot toggles (the shared hud_* keys live in
    -- ST.class_defaults; the descriptors they gate are ST.HUNTER.HUD_SLOTS in
    -- classes/hunter.lua). Slot toggles ship on: the HUD master hud_enabled
    -- ships on in the shared defaults (owner order 2026-10-19 on-by-default
    -- package), so a fresh profile shows bars+HUD+guide together.
    hud_show_steady = true,
    hud_show_raptor = true,
    hud_show_kill_command = true,
    hud_show_multi = true,
    hud_show_bestial_wrath = true,
    hud_show_rapid_fire = true,
    hud_show_aimed = true,
    hud_show_trinket1 = true,
    hud_show_trinket2 = true,
    -- Layout template selection (bench/hud_templates_2026-10-19.md §7): nil =
    -- Custom (current behavior, zero default-visible change). The curated sets
    -- live in ST.HUNTER.HUD_TEMPLATES below; the options select applies one on
    -- explicit user pick only.
    hud_template = nil,

    -- Practice knobs (paladin parity, owner order 2026-10-19): the shared session
    -- (practice_ui.lua) reads these unprefixed keys from the class table
    -- (practice_result_* for the grade popup, practice_panel_x/y for the shared
    -- panel), so the hunter panel edits them directly. No practice_weapon_speed:
    -- the forced-move drill runs no drill swing (practice_ui.lua:4115), so the
    -- key would be an orphan here. Nil-safe: the session falls back to these
    -- same values when nil (0.8 s / 28 / green-red / 0,0), so shipping them
    -- changes no fresh-profile behaviour.
    practice_result_duration = 0.8,
    practice_result_text_size = 28,
    practice_result_color_hit = {0, 1, 0, 1},
    practice_result_color_miss = {1, 0.2, 0.2, 1},
    practice_panel_x = 0,
    practice_panel_y = 0,

    -- Nil-off keys (no entry ships: nil stays off, read with == true in
    -- classes/hunter.lua and hunter_ui.lua): hunter_target_warning_enabled, hunter_bw_badge_enabled,
    -- hunter_frenzy_stacks_enabled, hunter_multi_target,
    -- hunter_readiness_badge_enabled (Readiness 2x window),
    -- hunter_iss_badge_enabled (ISS tint), hunter_oom_viper_badge_enabled
    -- (OOM Viper badge), hunter_lnl_badge_enabled (Lock and Load badge) and
    -- hunter_weave_prog_enabled (melee-weave progress tracking state).

    -- Bar options
    ['**'] = ST.bar_defaults,
    mainhand = {
        require_in_range = false,
        show_condition = "either",
        bar_color_default = {93, 58, 207, 0.9},
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
        require_in_range = false,
        show_condition = "either",
		bar_color_default = {13, 79, 115, 0.9},
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
		bar_color_default = {6, 143, 47, 0.9},
        gcd1a_marker_enabled = false,
        gcd1b_marker_enabled = false,
        show_gcd_underlay = true,
        center_text_enabled = true,
	},
}

-- Ready-made Cooldown HUD layout templates (bench/hud_templates_2026-10-19.md
-- §§3/7-8: H-T1 Shot Rotation, H-T2 Full BM + Trinkets, H-T3 Minimal + Glow).
-- Curated visible-slot subsets + geometry over the existing hud_* db keys only
-- (the HUD renders in HUD_SLOTS declaration order; templates never reorder).
-- Applied by the hud_template options select on explicit user pick only; nil
-- (Custom) leaves every key untouched. Gallery shortlist 3/4
-- (bench/weakaura_templates_2026-10-19.md): Core rows are the Luxthos Era-line
-- visual-check target, Minimal cites the minimalist-bars precedent (in-client only).
ST.HUNTER.HUD_TEMPLATES = {
    shot_rotation = {
        label = "H-T1 Shot Rotation",
        slots = {
            steady = true, raptor = false, kill_command = true, multi = true,
            bestial_wrath = false, rapid_fire = false, aimed = true,
            trinket1 = false, trinket2 = false,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = false,
    },
    full_bm = {
        label = "H-T2 Full BM + Trinkets",
        slots = {
            steady = true, raptor = true, kill_command = true, multi = true,
            bestial_wrath = true, rapid_fire = true, aimed = true,
            trinket1 = true, trinket2 = true,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = true,
    },
    minimal_glow = {
        label = "H-T3 Minimal + Glow",
        slots = {
            steady = true, raptor = false, kill_command = true, multi = false,
            bestial_wrath = false, rapid_fire = false, aimed = false,
            trinket1 = false, trinket2 = false,
        },
        hud_icon_size = 28, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = false,
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
    -- option range is unchanged. Sim standing
    -- (bench/paladin_rotation_audit_2026-10-19.md TBC CONFLICT): the TBC sim
    -- holds CS via the 11 s "Delay Major CDs" variable (no explicit CS entry),
    -- so 900 is the researched pull-phase compromise, not a sim value — kept
    -- with reason; the TBC pull-hold latch lives engine-side
    -- (classes/paladin.lua TBC pull-hold + nextaction.lua cs_hold_remaining).
    nextaction_cs_max_delay_ms = 900,
    nextaction_hold_enabled = true,
    nextaction_show_rotation_text = true,
    nextaction_show_label = true,
    nextaction_show_judgement = true,
    nextaction_show_fillers = true,
    -- Filler mana thresholds: no single sim value exists, so both are kept
    -- with reason (bench/paladin_rotation_audit_2026-10-19.md TBC + Forever
    -- GAPs). TBC sim defaults Use Exorcism/Consecrate to false (opt-in); the
    -- engine matches that whenever the target count is known (withholds) and
    -- only suggests into the unknown-target default. Forever sim gates fillers
    -- on mana >= 10% + autoTimeToNext > 1.5s; the shipped 35/30 are the
    -- conservative TBC-era sustain lines, not the Forever 10% line — lowering
    -- to 10 would over-prompt on TBC without the sim's consumes support.
    nextaction_filler_mana_consecration = 35,
    nextaction_filler_mana_exorcism = 30,
    -- Twist mana-sustain governor (P-22). The widget is the 0-100 percent range on
    -- the paladin panel (option_tables.lua); the provider forwards this key
    -- (classes/paladin.lua:3281-3285) into inputs.twist_mana_threshold and the
    -- engine plug keeps the reseal's mana and rides the swing below it
    -- (nextaction.lua:556-557). DEFAULT 0 = OFF = the archived behaviour.
    --
    -- Why off: the cited source (docs/research/tbc_minmax.md:27 - "twisting at
    -- 100% uptime ooms in 1-2 min without mana support", Reddit r/classicwowtbc
    -- + Warmane) establishes the risk but names NO percentage, and the TBC sim
    -- APLs manage mana through their disabled-by-default fillers + consumes
    -- (bench/paladin_rotation_audit_2026-10-19.md TBC GAP) rather than through a
    -- twist pause. A non-zero default would change the live TBC guide's prompts
    -- with no operator gate, so the shipped value is the documented off state and
    -- the player sets the percent deliberately. 0 and nil behave identically
    -- (mana_pct never reads below 0, so the governor never fires at 0).
    twist_mana_threshold_pct = 0,

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
    -- SoD/shockadin mirror slots (the guide->HUD mirror bench/hud_parity_2026-10-19.md
    -- P-1; descriptors + provider in classes/paladin.lua:3396-3409/:3657-3774).
    -- Gallery bench/paladin_styles_2026-10-19.md §0: SoD-native slots extend P-T2,
    -- not P-T1. All ship on: the HUD master hud_enabled ships on in the shared
    -- defaults (owner order 2026-10-19 on-by-default package); unknown clients hide
    -- provider-side (how/holy_shock/aura_mastery).
    hud_show_soc = true,
    hud_show_sob = true,
    hud_show_how = true,
    hud_show_holy_shock = true,
    hud_show_aura_mastery = true,
    -- The WotLK APL's UTILITY BAND (bench/paladin_apl_utility_build_2026-10-20.md
    -- §2): Hand of Reckoning (67485) + the WotLK Hammer of Wrath (48806).
    -- Consumers: classes/paladin.lua's HUD_SLOTS descriptors + the provider gate
    -- in get_hud_state, which reads hud_show_<key> == true (nil = off). The
    -- druid Claw shape: the display-only mirror ships FALSE (hidden, no
    -- default-visible change) and the player turns it on in the panel.
    hud_show_hor = false,
    hud_show_how_wrath = false,
    -- Layout template selection (bench/hud_templates_2026-10-19.md §7): nil =
    -- Custom (current behavior, zero default-visible change). The curated sets
    -- live in ST.PALADIN.HUD_TEMPLATES below; the options select applies one on
    -- explicit user pick only.
    hud_template = nil,

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

-- Ready-made Cooldown HUD layout templates (bench/hud_templates_2026-10-19.md
-- §§1/7-8: P-T1 Twist Core, P-T2 Full Ret + Trinkets, P-T3 Minimal). Curated
-- visible-slot subsets + geometry over the existing hud_* db keys only (the HUD
-- renders in HUD_SLOTS declaration order; templates never reorder). Applied by
-- the hud_template options select on explicit user pick only; nil (Custom)
-- leaves every key untouched. SoD-native slots (soc/sob/how/holy_shock/
-- aura_mastery) extend P-T2, not P-T1 (bench/paladin_styles_2026-10-19.md §0;
-- S2 Faelor density + S8 Sealor pack + S10 Malamo minimal row). The WotLK APL's
-- UTILITY BAND (hor / how_wrath - bench/paladin_apl_utility_build_2026-10-20.md
-- §2) follows the same rule: the family-specific slots extend P-T2 ("all
-- visible", bench/hud_templates_2026-10-19.md §1) and stay off in P-T1/P-T3 -
-- the druid's Claw shape (a display-only mirror, false in the defaults, on in
-- the "full" template). Gallery shortlist 3/4
-- (bench/weakaura_templates_2026-10-19.md): Core rows are the Luxthos Era-line
-- visual-check target, Minimal cites the minimalist-bars precedent (in-client only).
ST.PALADIN.HUD_TEMPLATES = {
    twist_core = {
        label = "P-T1 Twist Core",
        slots = {
            cs = true, judgement = true, consecration = false, exorcism = true,
            trinket1 = false, trinket2 = false, wings = true,
            soc = false, sob = false, how = false,
            holy_shock = false, aura_mastery = false,
            hor = false, how_wrath = false,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = false,
    },
    full_ret = {
        label = "P-T2 Full Ret + Trinkets",
        slots = {
            cs = true, judgement = true, consecration = true, exorcism = true,
            trinket1 = true, trinket2 = true, wings = true,
            soc = true, sob = true, how = true,
            holy_shock = true, aura_mastery = true,
            hor = true, how_wrath = true,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = true,
    },
    minimal = {
        label = "P-T3 Minimal",
        slots = {
            cs = true, judgement = true, consecration = false, exorcism = false,
            trinket1 = false, trinket2 = false, wings = false,
            soc = false, sob = false, how = false,
            holy_shock = false, aura_mastery = false,
            hor = false, how_wrath = false,
        },
        hud_icon_size = 28, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = false,
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
    -- Energy/pooling presentation. Nil-safe per the standing rule: == false hides,
    -- nil = off, so every behaviour toggle below ships false and nothing is visible
    -- by default.
    -- The 65/85 bands are the sourced never-pool-above thresholds (rogue_research
    -- §1.3): 65 pre-tick on Era/TBC, 85 post-tick. Sim comparison
    -- (bench/rogue_rotation_audit_2026-10-19.md T-M1/V-G6/W-M1): TBC sim pools
    -- at a single 71, Forever caps at 75 post-tick, Wrath caps at 85 — those
    -- per-client numbers live in rogue_guide.lua POOL_BANDS (TBC 71/71,
    -- FOREVER 65/75, ERA/WRATH 65/85) and win whenever the db override below
    -- is nil. The shipped 65/85 is the unknown-family fallback (ERA/WRATH
    -- shape); it is kept so a profile that predates the family tables keeps
    -- its choice. Tuning is options-driven; the data lives here so a profile
    -- keeps its choice.
    show_rogue_energy_tick = false,
    rogue_energy_tick_color = {255, 209, 64, 0.90},
    show_rogue_pool_tint = false,
    rogue_pool_tint_color = {255, 128, 0, 0.85},
    rogue_pool_band_pre = 65,
    rogue_pool_band_post = 85,

    -- Upkeep cues REMOVED (rogue-parity 2026-10-19): the HUD slots
    -- (snd/rupture/ea/tea, with the final-seconds glow and the greyed-missing
    -- render) and the guide actions (expose/shiv/tea) already cover every
    -- upkeep state these keys promised, so a second bar presentation would
    -- duplicate live state without new signal. The duty toggle below is the
    -- only upkeep key the guide consumes.

    -- Expose Armor duty opt-in (TBC Improved Expose Armor): when on, the guide treats
    -- EA upkeep as the rogue's job. nil-safe: nil = off.
    rogue_ea_duty = false,

    -- Post-swing window cues. Family/loadout gating lives in classes/rogue.lua: the
    -- Sinister Strike window is Classic Era only and needs a readable sword mainhand;
    -- the weapon-swap band runs Era/TBC/Forever and its caption carries the cost
    -- (GCD + swing reset); the poison line reports MH/OH poison presence only (no
    -- charge counts). Colours are 0-255 RGB + 0-1 alpha via convert_color.
    -- OWNER ORDER 2026-10-19 (rogue-redzone): the SS window ships RED and VISIBLE
    -- by default on Era - the explicit gate for this default-visible exception to
    -- the standing off-by-default rule. Nil-safe reads hold: == true shows, so
    -- nil/false/off-family/unknown-weapon still hide.
    show_rogue_ss_window = true,
    rogue_ss_color = {255, 64, 48, 0.85},
    show_rogue_swap_cue = false,
    rogue_swap_color = {89, 140, 191, 0.85},
    show_rogue_poison_cue = false,
    rogue_poison_color = {214, 64, 54, 0.95},

    -- Guide thresholds (the pure rogue_guide defaults; the options ranges tune them).
    -- Each ships the engine's documented default so a profile round-trips its value;
    -- a nil read still falls back to the engine default (profiles that predate the
    -- keys), and the ranges render that effective value instead of an empty field.
    -- Sim standing per bench/rogue_rotation_audit_2026-10-19.md (engine-side
    -- per-family tables in rogue_guide.lua already carry the sim numbers, so
    -- these shipped values are the unknown-family fallback only):
    -- rupture_refresh 4 = ERA/WRATH shape (no sim refresh row there,
    -- UNCONFIRMED); TBC/FOREVER sims recast-when-missing (window 0 in
    -- RUPTURE_REFRESH_BY_FAMILY, audit T-G3/H9). rupture_min_ttd 8 = the
    -- sourced 1CP Rupture duration (rogue_research §5.2, audit W-M2 MATCH at
    -- 1CP); TBC 5 / WRATH 4 / FOREVER 6 live in RUPTURE_MIN_TTD_BY_FAMILY
    -- (audit T-C1/W-M2/V-G3). finisher_min_cp 5 = ERA/TBC shape (audit E-M1
    -- MATCH); WRATH 4 / FOREVER 3 live in FINISHER_MIN_CP_BY_FAMILY (audit
    -- V-G3/W-G2). ea_refresh 3 = ERA IEA shape (audit E-G4 MATCH at 3s);
    -- TBC 6 / FOREVER 16 live in EA_REFRESH_BY_FAMILY (audit H4/T-G2/V-G2).
    -- shiv_refresh 2 = the §4 watch-list window (no sim window row; Mutilate+
    -- EA context filed, audit T-G4/H7). tea_energy_max 40 = WRATH shape (the
    -- sim's 50 line is potion, not Tea); ERA 29 / TBC 30 / FOREVER 15 live in
    -- TEA_ENERGY_MAX_BY_FAMILY (audit H10/E-G3/T-G5/V-G4).
    rogue_rupture_refresh = 4,
    rogue_rupture_min_ttd = 8,
    rogue_finisher_min_cp = 5,
    rogue_ea_refresh = 3,
    rogue_shiv_refresh = 2,
    rogue_tea_energy_max = 40,

    -- Next Action Guide (the shared nextaction_ui frame driven by ST.ROGUE.guide in
    -- classes/rogue.lua; the decision model is the pure rogue_guide.lua). Default
    -- ON (owner order 2026-10-19 on-by-default package: a fresh profile shows
    -- bars+HUD+guide). Nil-safe: nextaction_ui.should_show hides on == false,
    -- so nil reads as on, matching true. Key names match the paladin's/shaman's so the shared frame reads
    -- them unchanged. The provider reports inputs_unknown when the swing/energy/CP
    -- reads cannot be trusted, so the frame shows "…" instead of a guessed prompt.
    nextaction_enabled = true,
    nextaction_locked = true,
    nextaction_visibility_key = "in_combat",
    nextaction_icon_size = 45,
    nextaction_x = 0,
    nextaction_y = -180,

    -- Cooldown HUD: the rogue slot toggles (the shared hud_* keys live in
    -- ST.class_defaults; the descriptors they gate are ST.ROGUE.HUD_SLOTS in
    -- classes/rogue.lua). Slot toggles ship on: the HUD master hud_enabled ships
    -- on in the shared defaults (owner order 2026-10-19 on-by-default package),
    -- so a fresh profile shows bars+HUD+guide together.
    hud_show_snd = true,
    hud_show_rupture = true,
    hud_show_ea = true,
    hud_show_ar = true,
    hud_show_bf = true,
    hud_show_tea = true,
    hud_show_kick = true,
    -- R-M1 short-CD row (bench/settings_audit_2026-10-19.md R-M1): provider
    -- classes/rogue.lua:442 shortcd_wanted reads == true (nil = off). Ship false
    -- = hidden (no default-visible change; R-T3 template turns them on).
    hud_show_kidney = false,
    hud_show_restealth = false,
    hud_show_bandage = false,
    hud_show_coldblood = true,
    hud_show_trinket1 = true,
    hud_show_trinket2 = true,
    -- Layout template selection (bench/hud_templates_2026-10-19.md §7): nil =
    -- Custom (current behavior, zero default-visible change). The curated sets
    -- live in ST.ROGUE.HUD_TEMPLATES below; the options select applies one on
    -- explicit user pick only.
    hud_template = nil,

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
        require_in_range = false,
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

-- Ready-made Cooldown HUD layout templates (bench/hud_templates_2026-10-19.md
-- §§6/7-8: R-T1 UxkIny-style Core, R-T2 Full + CDs + Trinkets, R-T3 PvP
-- Utility). Curated visible-slot subsets + geometry over the existing hud_* db
-- keys only (the HUD renders in HUD_SLOTS declaration order; templates never
-- reorder). Applied by the hud_template options select on explicit user pick
-- only; nil (Custom) leaves every key untouched. R-T3 is PROVISIONAL (design
-- §6): kidney/restealth/bandage now have widgets (option_tables.lua R-M1 row)
-- and shipped false defaults (nil-safe: the provider hides them unless exactly
-- true). The template still writes their hud_show_<key> db keys on explicit
-- pick; the suite pins this exemption list, not the keys.
-- Gallery shortlist 1/4 (bench/weakaura_templates_2026-10-19.md): R-T1
-- UxkIny-style Core is the anchor (A3, TBC 2.4.3 — no change); Minimal cites
-- the minimalist-bars precedent.
ST.ROGUE.HUD_TEMPLATES = {
    core = {
        label = "R-T1 UxkIny-style Core",
        slots = {
            snd = true, rupture = true, ea = true, ar = false, bf = false,
            tea = true, kick = true, kidney = false, restealth = false,
            bandage = false, coldblood = false, trinket1 = false, trinket2 = false,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = false,
    },
    full_cds = {
        label = "R-T2 Full + CDs + Trinkets",
        slots = {
            snd = true, rupture = true, ea = true, ar = true, bf = true,
            tea = true, kick = true, kidney = false, restealth = false,
            bandage = false, coldblood = true, trinket1 = true, trinket2 = true,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = true,
    },
    pvp_utility = {
        label = "R-T3 PvP Utility (provisional)",
        slots = {
            snd = false, rupture = false, ea = true, ar = false, bf = false,
            tea = false, kick = true, kidney = true, restealth = true,
            bandage = true, coldblood = false, trinket1 = false, trinket2 = false,
        },
        hud_icon_size = 32, hud_spacing = 4,
        hud_orientation = "vertical", hud_match_bar_width = false,
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
    -- ON (owner order 2026-10-19 on-by-default package: a fresh profile shows
    -- bars+HUD+guide). Nil-safe: nextaction_ui.should_show hides on == false,
    -- so nil reads as on, matching true. Key names match the paladin's/warrior's so the shared frame reads
    -- them unchanged; guide_flameshock_refresh is the shaman-only refresh threshold.
    -- Sim standing (bench/shaman_rotation_audit_2026-10-19.md cross-sim
    -- finding 3): every sim re-applies Flame Shock only when the dot is
    -- INACTIVE (SoD P6/P4, Era default, TBC default, Forever testing.build
    -- all use `not dotIsActive`; none refresh early), so the SIM-EXACT value
    -- is 0 (expiry-only; the engine honors explicit 0 as recast-when-missing,
    -- shaman_guide.lua rule 6). The shipped 3 was kept only because the
    -- tests/shaman_guide_state.lua pin could not move with it; that pin moves
    -- with this edit (BS-4c, one writer per file), so the value is now the
    -- sim-exact 0. The prior 3 clipped ~3 s of dot every cycle.
    nextaction_enabled = true,
    nextaction_locked = true,
    nextaction_visibility_key = "in_combat",
    nextaction_icon_size = 45,
    nextaction_x = 0,
    nextaction_y = -180,
    guide_flameshock_refresh = 0,
    -- The TBC APL's "Filler Shock" choice (the Shocks group picks ONE filler: the
    -- valueVariables default is Earth Shock 25454 r8, the ALTERNATIVE is Frost Shock
    -- 25464 r5 - wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json
    -- i=6 group Shocks rows 2-3). The class reads this key and states the choice to
    -- the frozen engine's `filler_shock` input (classes/shaman.lua's gather).
    -- DEFAULT: "earth" - the APL's own default, so a fresh profile behaves exactly
    -- as before (the Earth Shock filler, no Frost Shock prompt). NIL-SAFE: a missing
    -- or unknown value reads as the same default (the engine treats anything but the
    -- Frost Shock token as "the APL's default"), so the choice never arms the Frost
    -- Shock arm by accident.
    guide_filler_shock = "earth",

    -- Cooldown HUD: the shaman slot toggles (the shared hud_* keys live in
    -- ST.class_defaults; the descriptors they gate are ST.SHAMAN.HUD_SLOTS in
    -- classes/shaman.lua). Slot toggles ship on: the HUD master hud_enabled
    -- ships on in the shared defaults (owner order 2026-10-19 on-by-default
    -- package), so a fresh profile shows bars+HUD+guide together.
    hud_show_stormstrike = true,
    hud_show_flameshock = true,
    hud_show_weave = true,
    hud_show_firenova = true,
    hud_show_earthshock = true,
    hud_show_twist = true,
    -- The three maintain mirrors (bench/shaman_slots_2026-10-19.md §2, plus the
    -- Call of the Elements mirror - S-20 / U-10): the provider
    -- classes/shaman.lua ST.SHAMAN.get_hud_state reads == true (nil = off, so a nil
    -- toggle hides too). Ship false = hidden (no default-visible change), the druid
    -- Claw mirror's shape.
    hud_show_lightningshield = false,
    hud_show_searing = false,
    hud_show_coe = false,
    hud_show_trinket1 = true,
    hud_show_trinket2 = true,
    -- Layout template selection (bench/hud_templates_2026-10-19.md §7): nil =
    -- Custom (current behavior, zero default-visible change). The curated sets
    -- live in ST.SHAMAN.HUD_TEMPLATES below; the options select applies one on
    -- explicit user pick only.
    hud_template = nil,

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

-- Ready-made Cooldown HUD layout templates (bench/hud_templates_2026-10-19.md
-- §§5/7-8: S-T1 Twist Core, S-T2 Full Enhance + Weave, S-T3 Minimal). Curated
-- visible-slot subsets + geometry over the existing hud_* db keys only (the HUD
-- renders in HUD_SLOTS declaration order; templates never reorder). Applied by
-- the hud_template options select on explicit user pick only; nil (Custom)
-- leaves every key untouched. Gallery shortlist 2
-- (bench/weakaura_templates_2026-10-19.md): the Sabimaru SoD+Era suite (A2) is
-- the S-T1/S-T2 visual-check target; the Dora TBC suite (§D4) covers the same
-- kit. Shortlist 6/7 bar-side borrows (hand colors, Delta readout, WF shading,
-- cast-zone bracket) are out of template scope — UNCONFIRMED until in-client;
-- per-spell weave toggles already ship as weave_families. WOTLK-flagged D2/D3
-- are NOT gallery inputs.
ST.SHAMAN.HUD_TEMPLATES = {
    -- The three maintain mirrors (lightningshield/searing/coe, ship-false
    -- defaults above) ride every template explicitly OFF: the full-set promise
    -- (no stale slot on switch, exact dirty-detect) holds for all 11 slots,
    -- and no template pick surfaces upkeep icons unasked.
    twist_core = {
        label = "S-T1 Twist Core",
        slots = {
            stormstrike = true, flameshock = true, weave = false,
            firenova = false, earthshock = true, twist = true,
            lightningshield = false, searing = false, coe = false,
            trinket1 = false, trinket2 = false,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = false,
    },
    full_weave = {
        label = "S-T2 Full Enhance + Weave",
        slots = {
            stormstrike = true, flameshock = true, weave = true,
            firenova = true, earthshock = true, twist = true,
            lightningshield = false, searing = false, coe = false,
            trinket1 = true, trinket2 = true,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = true,
    },
    minimal = {
        label = "S-T3 Minimal",
        slots = {
            stormstrike = true, flameshock = true, weave = false,
            firenova = false, earthshock = false, twist = false,
            lightningshield = false, searing = false, coe = false,
            trinket1 = false, trinket2 = false,
        },
        hud_icon_size = 28, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = false,
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

    -- Nil-off keys (no entry ships: nil stays off, read with ~= true in
    -- classes/warrior.lua like the bank cue): show_warrior_bank_cue,
    -- show_warrior_battle_shout_badge, show_warrior_desync_alert (W1 desync
    -- spark) and show_warrior_commanding_suppression (W2 Commanding coverage -
    -- suppresses the Battle Shout badge while covered).

    -- Next Action Guide (the shared nextaction_ui frame driven by ST.WARRIOR.guide in
    -- classes/warrior.lua; the decision model is the pure warrior_guide.lua). Default
    -- ON (owner order 2026-10-19 on-by-default package: a fresh profile shows
    -- bars+HUD+guide). Nil-safe: nextaction_ui.should_show hides on == false,
    -- so nil reads as on, matching true. Key names match the paladin's so the shared frame reads them
    -- unchanged; guide_execute_pct is the warrior-only Execute-range threshold.
    -- Sim-exact 20 (bench/warrior_rotation_audit_2026-10-19.md §2 M4: Era
    -- isExecutePhase E20 on both APLs; TBC execute.go E20-only; SoD E20 or
    -- Sudden-Death aura; Forever Victory Rush is Victorious-gated, not a
    -- threshold — the shipped 20 is the sim value on every client with an
    -- Execute phase). HS floors (Era 40 / TBC 40, Forever 40-gated) already
    -- live engine-side (classes/warrior.lua hs_rage_floor feeds + the TBC HS
    -- ranks 29707/30324 in hs_ids); no floor default ships here by design.
    nextaction_enabled = true,
    nextaction_locked = true,
    nextaction_visibility_key = "in_combat",
    nextaction_icon_size = 45,
    nextaction_x = 0,
    nextaction_y = -180,
    guide_execute_pct = 20,

    -- Nil-off key: guide_forever_rend_upkeep (no entry ships - nil stays off).
    -- The Forever Rend upkeep toggle (W-15; bench/class_features_drills_2026-10-19.md:292
    -- "Rend upkeep (SoD 11574 + rune 412507; Forever 11574 toggle <= 3 s)"; the
    -- Forever APL's Rend-weave group is toggle-gated). The PURE rule is live
    -- (warrior_guide.lua's should_maintain_rend_outside_arms with
    -- REND_REFRESH_DEFAULT = 3, wired into rule R), but the provider feeds
    -- rend_upkeep_enabled only on SoD with the Blood Frenzy rune known, so the
    -- rule is dormant on the Forever client.
    -- The widget lives on the warrior panel (option_tables.lua); the read that
    -- carries the key into the guide inputs is the FILED line
    -- (classes/warrior.lua:3049-3053 - the warrior lane's file). OFF by default:
    -- the rule has never run on Forever, so arming it is the player's deliberate
    -- choice, not a fresh profile's default (and no operator order gates a new
    -- prompt on that family). The key is read as == true, so nil and false both
    -- leave the rule dormant.

    hide_in_tank_spec = false,
    hide_in_arms_spec = false,

    -- Cooldown HUD: the warrior slot toggles (the shared hud_* keys live in
    -- ST.class_defaults; the descriptors they gate are ST.WARRIOR.HUD_SLOTS in
    -- classes/warrior.lua). The union of the family sets ships on (cleave is
    -- the non-TBC slot, bt/ww the TBC ones, rend/ms/bladestorm the arms set,
    -- raging_blow the SoD set, hamstring the base/Forever slot and sunder the
    -- Forever upkeep slot): the HUD
    -- master hud_enabled ships
    -- on in the shared defaults (owner order 2026-10-19 on-by-default package),
    -- so a fresh profile shows bars+HUD+guide together.
    hud_show_op = true,
    hud_show_execute = true,
    hud_show_slam = true,
    hud_show_hs = true,
    hud_show_cleave = true,
    hud_show_bt = true,
    hud_show_ww = true,
    hud_show_rend = true,
    hud_show_ms = true,
    hud_show_bladestorm = true,
    hud_show_raging_blow = true,
    hud_show_hamstring = true,
    -- Sunder upkeep slot (the HUD mirror: the TBC row classes/warrior.lua:3291-3293
    -- and the Forever row :3280-3282). Ships OFF - the druid-Claw shape (the
    -- provider hides the mirror unless hud_show_sunder reads exactly true, so
    -- false and nil both hide): the mirror ships (one click to enable) and a
    -- fresh profile's HUD row is unchanged. The W-T2 template still turns it on
    -- on an explicit pick.
    hud_show_sunder = false,
    hud_show_trinket1 = true,
    hud_show_trinket2 = true,
    -- Layout template selection (bench/hud_templates_2026-10-19.md §7): nil =
    -- Custom (current behavior, zero default-visible change). The curated sets
    -- live in ST.WARRIOR.HUD_TEMPLATES below; the options select applies one on
    -- explicit user pick only.
    hud_template = nil,

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
        require_in_range = false,
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

-- Ready-made Cooldown HUD layout templates (bench/hud_templates_2026-10-19.md
-- §§2/7-8: W-T1 Fury Core, W-T2 Full + Trinkets, W-T3 Arms / SoD). Curated
-- visible-slot subsets + geometry over the existing hud_* db keys only (the HUD
-- renders in HUD_SLOTS declaration order; templates never reorder). Applied by
-- the hud_template options select on explicit user pick only; nil (Custom)
-- leaves every key untouched. W-T3 is PROVISIONAL (design §2): the arms set
-- (op/execute/rend/ms/bladestorm/hs) and the SoD set
-- (execute/slam/hs/ww/raging_blow) are family-conditional in
-- classes/warrior.lua resolve_guide_slots, which a static template cannot
-- branch on — so W-T3 ships their union + trinkets until the in-flight
-- warrior-followups lane wires the arms/SoD toggles. Sunder rides the union
-- (bench/warrior_styles_2026-10-19.md shortlist #2: W-T2 is family-full):
-- on in Full, off in the Fury/Arms cores (not their kits). Gallery shortlist 4/5
-- (bench/weakaura_templates_2026-10-19.md): W-T1 copy names the yellow/green
-- queue-color reads (B1 — already shipped as the HS tint); Minimal cites the
-- minimalist-bars precedent (in-client only).
ST.WARRIOR.HUD_TEMPLATES = {
    fury_core = {
        label = "W-T1 Fury Core",
        slots = {
            op = true, execute = true, slam = false, hs = true, cleave = false,
            bt = true, ww = true, rend = false, ms = false, bladestorm = false,
            raging_blow = false, hamstring = false, sunder = false,
            trinket1 = false, trinket2 = false,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = false,
    },
    full_trinkets = {
        label = "W-T2 Full + Trinkets",
        slots = {
            op = true, execute = true, slam = true, hs = true, cleave = true,
            bt = true, ww = true, rend = true, ms = true, bladestorm = true,
            raging_blow = true, hamstring = true, sunder = true,
            trinket1 = true, trinket2 = true,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = true,
    },
    arms_sod = {
        label = "W-T3 Arms / SoD (provisional)",
        slots = {
            op = true, execute = true, slam = true, hs = true, cleave = false,
            bt = false, ww = true, rend = true, ms = true, bladestorm = true,
            raging_blow = true, hamstring = false, sunder = false,
            trinket1 = true, trinket2 = true,
        },
        hud_icon_size = 36, hud_spacing = 2,
        hud_orientation = "horizontal", hud_match_bar_width = false,
    },
}

--=========================================================================================
-- Practice progression + stats (practice_progress.lua / practice_stats.lua)
--=========================================================================================
-- The saved shape of SwedgeTimerDB.profile.practice (spec §6 "Persistence": the
-- progress/stat state of the practice minigame). The two pure modules own the value
-- semantics and the load-time validation/repair path
-- (st.practice_progress.migrate / .validate); this table is the AceDB DEFAULT for
-- the key, so a fresh profile starts from a valid, fully-shaped practice state
-- instead of an absent one.
--
-- Nil-safe by construction: every leaf is a concrete value, never nil, so a reader
-- never has to guess a missing field. The table is READ-ONLY in practice - the hook
-- lane (design spec §7 step 2) REPLACES the profile key with the repaired blob
-- (db.profile.practice = st.practice_progress.migrate(db.profile.practice)), so the
-- default is never mutated in place.
--
-- The per-class scopes are created on demand by the pure modules (a class only gets
-- a scope once it is played), so the defaults carry empty maps rather than one
-- entry per class.
--
-- NOTE: adding this to the AceDB defaults is the hook lane's step - config.lua owns
-- ST.defaults and is outside the foundation lane's scope.
ST.PRACTICE_DEFAULTS = {
    schema_version = 1,
    progress = {
        version = 1,
        classes = {},
        global = {
            daily_streak = 0,
            unlocks = {},
        },
    },
    stats = {
        version = 1,
        classes = {},
        global = {
            runs = 0,
            attempts = 0,
            hits = 0,
            misses = 0,
            points = 0,
            best_session_score = 0,
            best_s_streak = 0,
            s_run = 0,
            time_active_seconds = 0,
            drills = {},
            recent = {},
            history = {},
        },
    },
}

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then st.utils.print_msg('-- Parsed config_presets.lua module correctly') end