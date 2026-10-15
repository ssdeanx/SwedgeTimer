local addon_name, st = ...
local SwedgeTimer = LibStub("AceAddon-3.0"):NewAddon(addon_name, "AceConsole-3.0")
local SML = LibStub("LibSharedMedia-3.0")
local print = st.utils.print_msg
-- print(type(SML.DefaultMedia.statusbar))
-- print(SML.DefaultMedia.statusbar)

--=========================================================================================
-- Saved-variable migration. Runs on the RAW saved table before AceDB attaches its
-- defaults, so a profile written by an older version can be told apart from a fresh one.
--
-- 1.9.0 (schema 2): every new on-screen element (Cooldown HUD, Rotation text) is off by
-- default, so no profile grows a new element in a spot nobody chose. The migration
-- still stamps existing profiles and pins the HUD off on customised ones explicitly
-- (belt and braces should a later version flip the default), and a one-time login
-- note tells upgraders where the new things are.
--
-- Returns the names of the profiles that were migrated (for the login note).
--=========================================================================================
SwedgeTimer.SCHEMA_VERSION = 2
SwedgeTimer.migrated_profiles = {}

function SwedgeTimer.migrate_saved_variables(sv)
	local migrated = {}
	if type(sv) ~= "table" or type(sv.profiles) ~= "table" then return migrated end
	for name, raw in pairs(sv.profiles) do
		if type(raw) == "table" and raw.schema_version == nil then
			local customised = false
			for k in pairs(raw) do
				if k ~= "schema_version" then customised = true; break end
			end
			if customised then
				if raw.hud_enabled == nil then raw.hud_enabled = false end
				migrated[#migrated + 1] = name
			end
			raw.schema_version = SwedgeTimer.SCHEMA_VERSION
		end
	end
	return migrated
end

-- A profile that was just created (nothing saved yet) gets stamped so a later login
-- never mistakes it for a legacy one and switches its HUD off.
function SwedgeTimer:StampProfile()
	if self.db and self.db.profile and self.db.profile.schema_version == nil then
		self.db.profile.schema_version = SwedgeTimer.SCHEMA_VERSION
	end
end

-- Every on-screen element re-reads the profile: after a profile switch / copy / reset
-- (AceDB callbacks) and after an import.
function SwedgeTimer:RefreshAllUI()
	if not (st.bar and st.bar.frame) then return end
	if st.editmode and st.editmode.active and st.editmode.active() then
		st.editmode.lock(true)   -- never carry an open design session across a profile change
	end
	if st.import_export and st.import_export.refresh_all_ui then
		st.import_export.refresh_all_ui()
	end
	if st.utils and st.utils.update_ret_spec then st.utils.update_ret_spec() end
	if st.settings_ui and st.settings_ui.request_refresh then st.settings_ui.request_refresh() end
end

function SwedgeTimer:OnInitialize()
	-- uses the "Default" profile instead of character-specific profiles
	-- https://www.wowace.com/projects/ace3/pages/api/ace-db-3-0

	-- upgrade older saved profiles BEFORE AceDB wraps them in defaults
	SwedgeTimer.migrated_profiles = SwedgeTimer.migrate_saved_variables(_G.SwedgeTimerDB)

	local AC = LibStub("AceConfig-3.0")
	local ACD = LibStub("AceConfigDialog-3.0")

	local SwedgeTimerDB = LibStub("AceDB-3.0"):New("SwedgeTimerDB", self.defaults, true)
	self.db = SwedgeTimerDB
	self:StampProfile()

	-- profile switch / copy / reset: rebuild every element from the new profile
	self.db.RegisterCallback(self, "OnProfileChanged", function() self:StampProfile(); self:RefreshAllUI() end)
	self.db.RegisterCallback(self, "OnProfileCopied", function() self:StampProfile(); self:RefreshAllUI() end)
	self.db.RegisterCallback(self, "OnProfileReset", function() self:StampProfile(); self:RefreshAllUI() end)

	-- registers an options table and adds it to the Blizzard options window
	-- https://www.wowace.com/projects/ace3/pages/api/ace-config-3-0
	AC:RegisterOptionsTable("SwedgeTimer_Options", self.options)
	self.optionsFrame = ACD:AddToBlizOptions("SwedgeTimer_Options", "SwedgeTimer")

	-- adds a child options table, in this case our profiles panel
	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	AC:RegisterOptionsTable("SwedgeTimer_Profiles", profiles)
	ACD:AddToBlizOptions("SwedgeTimer_Profiles", "Profiles", "SwedgeTimer")

	
	-- if the player is not a paladin, replace the command to open the menu with a dummy printout
	local register_func_string = "SlashCommand"
	if not st.utils.player_is_paladin() then
		register_func_string = "NotPaladinSlashCommand"
	end
	self:RegisterChatCommand("st", register_func_string)
	self:RegisterChatCommand("swedgetimer", register_func_string)

end

function SwedgeTimer:OnEnable()

	-- only load if player is a paladin
	if not st.utils.player_is_paladin() then return end

	-- Sort out character information
	st.player.guid = UnitGUID("player")
	st.player.weapon_id = GetInventoryItemID("player", 16)
	st.player.reset_swing_timer()
end

function SwedgeTimer:NotPaladinSlashCommand(input, editbox)
	print('SwedgeTimer is disabled when the player character is not a Paladin.')
end

-- Auto-locks draggable frames whenever a settings window closes. Shared by the
-- SwedgeTimer settings window (settings_ui.lua) and the legacy AceConfig dialog.
function SwedgeTimer:OnSettingsClosed()
	if not self.db then return end
	-- Auto-lock success text position when closing settings
	if not self.db.profile.successful_twist_text_locked then
		self.db.profile.successful_twist_text_locked = true
		if st.bar and st.bar.set_success_text_position then
			st.bar.set_success_text_position()
		end
	end
	-- Auto-lock the next action guide when closing settings
	if not self.db.profile.nextaction_locked then
		self.db.profile.nextaction_locked = true
		if st.nextaction and st.nextaction.apply_settings then
			st.nextaction.apply_settings()
		end
	end
end

-- Hooks the legacy AceConfig dialog's OnHide to auto-lock draggable frames on close.
-- Must be called after ACD:Open from every code path that opens that dialog.
function SwedgeTimer:HookOptionsAutoLock()
	local ACD = LibStub("AceConfigDialog-3.0")

	-- Hook the underlying frame's OnHide (not the AceGUI callback)
	-- HookScript ADDS a handler without replacing AceConfigDialog's cleanup
	local frame = ACD.OpenFrames["SwedgeTimer_Options"]
	if frame and frame.frame and not frame.swedgeTimerOnHideHooked then
		frame.swedgeTimerOnHideHooked = true  -- Prevent duplicate hooks
		frame.frame:HookScript("OnHide", function()
			SwedgeTimer:OnSettingsClosed()
		end)
	end
end

-- Opens the legacy AceConfig dialog (also reachable via /st classic).
function SwedgeTimer:OpenClassicOptions()
	local ACD = LibStub("AceConfigDialog-3.0")
	ACD:Open("SwedgeTimer_Options")
	SwedgeTimer:HookOptionsAutoLock()
end

-- Opens the SwedgeTimer settings window.
function SwedgeTimer:OpenSettings()
	if st.settings_ui and st.settings_ui.open then
		st.settings_ui.open()
	else
		SwedgeTimer:OpenClassicOptions()
	end
end

function SwedgeTimer:SlashCommand(input, editbox)
	local cmd = input and input:trim():lower() or ""
	if cmd == "practice" then
		if st.practice and st.practice.toggle then
			st.practice.toggle()
		end
		return
	elseif cmd == "classic" or cmd == "old" then
		SwedgeTimer:OpenClassicOptions()
		return
	elseif cmd == "design" or cmd == "edit" or cmd == "unlock" then
		if st.editmode and st.editmode.toggle then
			st.editmode.toggle()
		end
		return
	elseif cmd == "lock" or cmd == "done" then
		if st.editmode and st.editmode.lock then
			st.editmode.lock()
		end
		return
	elseif cmd == "spec" then
		if st.spec and st.spec.print then
			st.spec.print()
		end
		return
	elseif cmd == "help" then
		print("Commands: |cFF00FF00/st|r settings, |cFF00FF00/st design|r arrange everything on screen "
			.. "(|cFF00FF00/st lock|r ends it), |cFF00FF00/st practice|r twist minigame, "
			.. "|cFF00FF00/st spec|r show the detected spec, |cFF00FF00/st classic|r legacy options.")
		return
	end

	SwedgeTimer:OpenSettings()
end

local bar_visibility_values = {
	always = "Always show",
	in_combat = "In combat",
	active_seal = "Seal active",
	in_combat_or_active_seal = "In combat or seal active",
}

local bar_vis_ordering = {
	"always", "in_combat", "active_seal", "in_combat_or_active_seal",
}

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

------------------------------------------------------------------------------------
-- Default settings for the addon.
SwedgeTimer.defaults = {
    profile = {

		-- Top level
		welcome_message = true,
		bar_enabled = true,
		ret_only = false,

		-- Behaviour toggles
		lag_detection_enabled = true,
		judgement_marker_enabled = true,
        bar_twist_color_enabled = false,
		enable_deadzone = true,
		twist_sound_enabled = false,
		twist_sound_choice = "pop",

		-- Auto-hide setting
		visibility_key = "always",

		-- Lag calibration
		lag_multiplier = 1.4,
		lag_offset = 15,

		-- Marker position settings
		gcd_padding_mode = "Dynamic",
		gcd_static_padding_ms = 100,
		twist_padding_mode = "None",
		twist_window_padding_ms = 0,

		-- Bar dimensions
		bar_height = 32,
		bar_width = 345,

		-- Settings window scale (dragged from its bottom-right corner)
		settings_scale = 0.6,

		-- Design mode: snap grid step in pixels (0 = no snapping) and the size of its
		-- toolbar / cards (dragged from a card's bottom-right corner)
		design_grid = 24,
		design_scale = 0.7,
		design_card_scale = 0.7,
		-- Effects & sounds window position in design mode (nil = left edge of the screen)
		design_effects_x = nil,
		design_effects_y = nil,

		-- Bar positioning
		bar_locked = true,
		bar_x_offset = 0,
		bar_y_offset = -180,
		bar_point = "CENTER",
		bar_rel_point = "CENTER",

		-- Frame strata/draw level
		frame_strata = "MEDIUM",
		draw_level = 10,

		-- Bar textures
		bar_texture_key = "Solid",
        gcd_texture_key = "Solid",
        backplane_texture_key = "Solid",
        border_texture_key = "None",
		deadzone_texture_key = "Solid",
		backplane_alpha = 0.85,

		-- Deadzone scaling
		deadzone_scale_factor = 1.0,

		-- Border settings
		border_mode_key = "Solid",
		backplane_outline_width = 2,

		-- Font settings
		font_size = 16,
		font_color = {1.0, 1.0, 1.0, 1.0},
		text_font = SML.DefaultMedia.font,
		font_outline_key = "outline",
        left_text = "attack_speed",
        right_text = "swing_timer",
        center_text = "_none",

		-- Marker settings
		marker_width = 3,
		gcd1_enabled = true,
		gcd_marker_color = {1.0, 0.0, 0.0, 1.0},
		twist_marker_color = {0.9,0.9,0.9,1.0},
		judgement_marker_color = {0.9,0.9,0.01,1.0},

		-- Seal color settings

		bar_color_command = {0.14, 0.66, 0.14, 1.0},
		bar_color_righteousness = {0.14, 0.66, 0.14, 1.0},
        bar_color_blood = {0.86, 0.38, 0.11, 1.0},
		bar_color_vengeance = {0.8, 0.5, 0.4, 1.0},
		bar_color_wisdom = {0., 0.4, 0.7, 1.0},
		bar_color_light = {0.67, 0.92, 0.859, 1.0},
		bar_color_justice = {0.77, 0.31, 0.48, 1.0},
		bar_color_crusader = {0.9, 0.75, 0.42, 1.0},


		-- Special bar colors
        bar_color_cant_twist = {0.83, 0.83, 0.01, 1.0},
        bar_color_warning = {1.0, 0.0, 0.0, 1.0}, -- when if you cast SoC, you can't twist out of it that swing
        bar_color_twisting = {0.7,0.1,0.6,1.0},
		bar_color_default = {0.53, 0.43, 0.53, 1.0},

		-- GCD underlay bar colors
		bar_color_gcd = {0.48, 0.48, 0.48, 1.0},

		-- Deadzone bar colors
		bar_color_deadzone = {0.72, 0.05, 0.05, 0.72},

		-- Seal icon settings
		icon_enabled = true,
		icon_size = 32,
		icon_spacing = 5,
		icon_match_bar_height = true,
		icon_detached = false,
		icon_locked = true,
		icon_x_offset = 0,
		icon_y_offset = 0,
		icon_point = "CENTER",
		icon_rel_point = "CENTER",
		icon_centered = false,

		-- Seal timer settings
		seal_timer_enabled = true,
		seal_timer_size = 16,
		seal_timer_color = {1, 1, 1, 1},
		seal_cooldown_overlay_enabled = true,

		-- Marker texture setting
		marker_texture = "Blizzard",

		-- Rotation Helper settings
		rotation_helper_enabled = true,
		rotation_icon_size = 32,
		rotation_icon_spacing = 4,
		rotation_show_all_steps = true,
		rotation_glow_enabled = true,
		rotation_position = "above",
		rotation_offset_x = 0,
		rotation_offset_y = 8,
		rotation_text_enabled = true,
		rotation_training_text = false,
		rotation_cs_glow_enabled = true,

		-- Minimap button settings (LibDBIcon format)
		minimap = {
			hide = false,
		},

		-- Sound settings
		sound_channel = "Master",

		-- Twist success feedback (learning mode)
		twist_success_sound_enabled = false,
		twist_success_sound_choice = "TadaFanfare",
		twist_success_glow_enabled = false,
		twist_success_glow_color = {0.0, 1.0, 0.0, 0.8},
		twist_success_glow_duration = 0.4,
		twist_success_glow_type = "Pixel",
		twist_success_glow_lines = 8,
		twist_success_glow_frequency = 0.25,
		twist_success_glow_thickness = 2,
		twist_success_glow_scale = 1.0,

		-- Successful twist text settings (true twist = Command proc)
		successful_twist_text_enabled = false,
		successful_twist_text_mode = "frame",
		successful_twist_text_font = SML.DefaultMedia.font,
		successful_twist_text_size = 24,
		successful_twist_text_outline = "outline",
		successful_twist_text_color = {0.0, 1.0, 0.0, 1.0},
		successful_twist_text_duration = 1.5,
		successful_twist_text_locked = true,
		successful_twist_text_x_offset = 0,
		successful_twist_text_y_offset = 200,
		successful_twist_text_point = "CENTER",
		successful_twist_text_rel_point = "CENTER",

		-- Practice Mode
		practice_weapon_speed = 0,              -- 0 = use real weapon speed
		practice_result_duration = 0.8,
		practice_result_text_size = 28,
		practice_result_color_hit = {0.0, 1.0, 0.0, 1.0},
		practice_result_color_miss = {1.0, 0.2, 0.2, 1.0},
		-- Practice keybinds (configurable keys)
		practice_key_soc = "1",
		practice_key_sob = "2",
		practice_key_cs = "3",
		practice_key_judge = "4",
		practice_key_sotc = "5",
		practice_key_consec = "6",
		practice_key_aw = "7",
		practice_key_hpot = "8",
		practice_key_abacus = "9",
		practice_key_stopattack = "",

		-- Practice Mode combo/fight settings
		practice_aw_includes_pot = false,
		practice_aw_includes_sob = false,
		practice_dst_enabled = false,
		practice_bl_delay = 0,
		practice_spell_queue_window = 0.4,  -- seconds (matches WoW's 400ms default)

		-- Practice Mode rotation display
		practice_rotation_display_enabled = true,
		practice_rotation_display_icon_size = 40,
		practice_rotation_display_icon_spacing = 6,
		practice_rotation_display_x = 0,
		practice_rotation_display_y = 100,

		-- Practice Mode fight timeline
		practice_timeline_enabled = true,
		practice_timeline_mode = "always",
		practice_timeline_x = 0,
		practice_timeline_y = -200,
		practice_timeline_width = 600,
		practice_timeline_pixels_per_second = 80,

		-- Practice Mode bar mappings (persisted across /reload)
		practice_bar_mappings = {},

		-- Next Action Guide (port of the "Ret Next Action Guide" WeakAura)
		nextaction_enabled = true,
		nextaction_locked = true,
		nextaction_x = 0,
		nextaction_y = -180,
		nextaction_icon_size = 45,
		nextaction_visibility_key = "in_combat",
		nextaction_reaction_time_ms = 100,
		nextaction_cs_max_delay_ms = 1700,
		nextaction_hold_enabled = true,
		nextaction_show_rotation_text = true,
		nextaction_show_label = true,
		-- Zone types the guide may load in (Practice Mode and unlocking always show it)
		nextaction_zone_world = true,
		nextaction_zone_party = true,
		nextaction_zone_raid = true,
		nextaction_zone_pvp = true,
		nextaction_zone_arena = true,
		nextaction_show_judgement = true,
		nextaction_show_fillers = true,
		nextaction_filler_mana_consecration = 35,
		nextaction_filler_mana_exorcism = 30,

		-- Cooldown HUD (port of the "[Retr] Spells" row of Nullgodx's Paladin WeakAura).
		-- Off by default: nothing new appears on anyone's screen until they turn it on.
		hud_enabled = false,
		hud_visibility_key = "always",
		hud_x = 0,
		hud_y = -236,
		hud_icon_size = 36,
		hud_match_bar_width = false,
		hud_spacing = 2,
		hud_orientation = "horizontal",
		hud_show_cs = true,
		hud_show_judgement = true,
		hud_show_consecration = true,
		hud_show_exorcism = true,
		hud_show_wings = true,
		hud_show_trinket1 = true,
		hud_show_trinket2 = true,
		hud_show_text = true,
		hud_font = SML.DefaultMedia.font,
		hud_text_size = 16,
		hud_text_outline = "outline",
		hud_text_color = {0.98, 1.0, 0.0, 1.0},
		hud_text_warn_color = {1.0, 0.4, 0.42, 1.0},
		hud_border_size = 2,
		hud_border_color = {0.0, 0.0, 0.0, 1.0},
		hud_glow_enabled = true,
		hud_desaturate = true,
		hud_mana_tint = true,
		hud_range_tint = true,

		-- Rotation text: a free-standing label with the recommended twist rotation
		rotation_label_enabled = false,
		rotation_label_visibility_key = "always",
		rotation_label_format = "key",
		rotation_label_align = "center",
		rotation_label_x = 0,
		rotation_label_y = -150,
		rotation_label_font = SML.DefaultMedia.font,
		rotation_label_size = 16,
		rotation_label_outline = "outline",
		rotation_label_color = {1.0, 0.82, 0.0, 1.0},

    },

}

local outline_map = {
	_none="",
	outline="OUTLINE",
	thick_outline="THICKOUTLINE",
}

local bar_border_modes = {
	Solid="Solid",
	Texture="Texture",
	None="None",
}

local outlines = {
	_none="None",
	outline="Outline",
	thick_outline="Thick Outline",
}

local texts = {
	_none="Not shown",
	attack_speed="Attack speed",
	swing_timer="Swing timer",
}

local gcd_padding_modes = {
	Dynamic="Dynamic",
	Fixed="Fixed",
	None="None",
}

local valid_anchor_points = {
	TOPLEFT="TOPLEFT",
    TOPRIGHT="TOPRIGHT",
    BOTTOMLEFT="BOTTOMLEFT",
    BOTTOMRIGHT="BOTTOMRIGHT",
    TOP="TOP",
    BOTTOM="BOTTOM",
    LEFT="LEFT",
    RIGHT="RIGHT",
    CENTER="CENTER",
}

------------------------------------------------------------------------------------
-- Functions to apply settings to the UI elements.
local set_bar_position = function()
	local db = SwedgeTimer.db.profile
	local frame = st.bar.frame
	frame:ClearAllPoints()
	frame:SetPoint(db.bar_point, UIParent, db.bar_rel_point, db.bar_x_offset, db.bar_y_offset)
	frame.bar:SetPoint("TOPLEFT", 0, 0)
	frame.bar:SetPoint("TOPLEFT", 0, 0)
	frame.gcd_bar:SetPoint("TOPLEFT", 0, 0)
	frame.deadzone:SetPoint("TOPRIGHT", 0, 0)
	frame.left_text:SetPoint("TOPLEFT", 3, -(db.bar_height / 2) + (db.font_size / 2))
	frame.right_text:SetPoint("TOPRIGHT", -3, -(db.bar_height / 2) + (db.font_size / 2))
	frame.center_text:SetPoint("TOP", 0, -(db.bar_height / 2) + (db.font_size / 2))
	st.configure_bar_outline()
end
st.set_bar_position = set_bar_position

local set_fonts = function()
	local db = SwedgeTimer.db.profile
	local frame = st.bar.frame
	local font_path = SML:Fetch('font', db.text_font)

	local opt_string = outline_map[db.font_outline_key]
	frame.left_text:SetFont(font_path, db.font_size, opt_string)
	frame.right_text:SetFont(font_path, db.font_size, opt_string)
	frame.center_text:SetFont(font_path, db.font_size, opt_string)
	frame.left_text:SetPoint("TOPLEFT", 3, -(db.bar_height / 2) + (db.font_size / 2))
	frame.right_text:SetPoint("TOPRIGHT", -3, -(db.bar_height / 2) + (db.font_size / 2))
	frame.center_text:SetPoint("TOP", 0, -(db.bar_height / 2) + (db.font_size / 2))
	frame.left_text:SetTextColor(unpack(db.font_color))
	frame.right_text:SetTextColor(unpack(db.font_color))
	frame.center_text:SetTextColor(unpack(db.font_color))
end
st.set_fonts = set_fonts

-- Refreshes the bar labels right away after a text setting changes; the bar's per-frame
-- update keeps them current afterwards.
local set_texts = function()
	if st.bar and st.bar.update_texts then st.bar.update_texts() end
end
st.set_texts = set_texts

local set_bar_size = function()
	local db = SwedgeTimer.db.profile
	local frame = st.bar.frame
	frame:SetWidth(db.bar_width)
	frame:SetHeight(db.bar_height)
	frame.bar:SetWidth(db.bar_width)
	frame.bar:SetHeight(db.bar_height)
	-- frame.gcd_bar:SetWidth(db.bar_width)
	frame.gcd_bar:SetHeight(db.bar_height)
	frame.deadzone:SetHeight(db.bar_height)
	set_fonts()
	st.set_markers()
	st.bar.set_icon_size()
	if st.hud and st.hud.apply_settings then st.hud.apply_settings() end   -- "match bar width"
end
st.set_bar_size = set_bar_size

local set_marker_widths = function()
	local frame = st.bar.frame
	local db = SwedgeTimer.db.profile
	frame.twist_line:SetWidth(db.marker_width)
	frame.gcd1_line:SetWidth(db.marker_width)
	frame.judgement_line:SetWidth(db.marker_width)
end
st.set_marker_widths = set_marker_widths

local set_marker_colors = function()
	local frame = st.bar.frame
	if not frame then return end  -- Safety check
	local db = SwedgeTimer.db.profile

	-- Set texture file and apply vertex color
	-- Note: We set the texture each time to ensure it's properly initialized
	local texture = SML:Fetch('statusbar', db.marker_texture or 'Blizzard')

	frame.twist_line:SetTexture(texture)
	frame.twist_line:SetVertexColor(unpack(db.twist_marker_color))

	frame.gcd1_line:SetTexture(texture)
	frame.gcd1_line:SetVertexColor(unpack(db.gcd_marker_color))

	frame.judgement_line:SetTexture(texture)
	frame.judgement_line:SetVertexColor(unpack(db.judgement_marker_color))
end
st.set_marker_colors = set_marker_colors

st.set_markers = function()
	st.set_marker_colors()
	st.set_marker_widths()
	st.bar.set_marker_offsets()
end

-- Function to be called whenever the state of the backdrop or texture
-- outline are changed.
st.configure_bar_outline = function()
	local db = SwedgeTimer.db.profile
	local mode = db.border_mode_key
	local frame = st.bar.frame
	local texture_key = db.border_texture_key
    local tv = db.backplane_outline_width
	-- 8 corresponds to no border
	tv = tv + 8

	-- Switch settings based on mode
	if mode == "None" then
		texture_key = "None"
		tv = 8
	elseif mode == "Texture" then
		tv = 8
	elseif mode == "Solid" then
		texture_key = "None"
	end

    frame.backplane.backdropInfo = {
        bgFile = SML:Fetch('statusbar', db.backplane_texture_key),
		edgeFile = SML:Fetch('border', texture_key),
        tile = true, tileSize = 16, edgeSize = 16, 
        insets = { left = 6, right = 6, top = 6, bottom = 6}
    }
    frame.backplane:ApplyBackdrop()

	tv = tv - 2
    frame.backplane:SetPoint('TOPLEFT', -1*tv, tv)
    frame.backplane:SetPoint('BOTTOMRIGHT', tv, -1*tv)
	frame.backplane:SetBackdropColor(0,0,0, db.backplane_alpha)

	-- the icons (and a width-matched HUD) match the bar as drawn: re-fit them when the outline changes
	if st.bar.set_icon_size then st.bar.set_icon_size() end
	if st.hud and st.hud.apply_settings then st.hud.apply_settings() end

end

st.set_deadzone = function()
	local db = SwedgeTimer.db.profile
	local f = st.bar.frame.deadzone
    f:SetTexture(SML:Fetch('statusbar', db.deadzone_texture_key))
	f:SetVertexColor(unpack(db.bar_color_deadzone))
end

------------------------------------------------------------------------------------
-- Now configure the option table for our settings interface.
SwedgeTimer.options = {
	type = "group",
	name = "SwedgeTimer (Updated by Folktale)",
	handler = SwedgeTimer,
	args = {

		------------------------------------------------------------------------------------
		-- top-level settings
		welcome_message = {
			type = "toggle",
			order = 1.1,
			name = "Welcome message",
			desc = "Displays a login message showing the addon version on player login or reload.",
			get = "GetValue",
			set = "SetValue",
		},
		bar_enabled = {
			type = "toggle",
			order = 1,
			name = "Enabled",
			desc = "Enables or disables SwedgeTimer.",
			get = "GetValue",
			set = "SetValue",
		},
		ret_only = {
			type = "toggle",
			order = 1.05,
			name = "Ret spec only",
			desc = "Only show SwedgeTimer while your dominant talent tree is Retribution. Disables all features "
				.. "including sounds in Holy or Protection. A paladin with fewer than 5 talent points (leveling) "
				.. "is treated as Retribution so the bar is never hidden from someone still choosing a spec.",
			get = "GetValue",
			set = function(self, key)
				SwedgeTimer.db.profile.ret_only = key
				st.utils.update_ret_spec()
			end,
		},
		spec_status = {
			type = "description",
			order = 1.06,
			fontSize = "medium",
			name = function()
				if not (st.spec and st.spec.describe) then return "" end
				local label, points = st.spec.describe()
				return "Detected spec: |cFFFFD27A" .. label .. "|r  (Holy / Protection / Retribution points: " .. points
					.. "). Type |cFF00FF00/st spec|r to re-read your talents."
			end,
		},

		------------------------------------------------------------------------------------
		-- Design mode (the global unlock; see editmode.lua)
		design = {
			type = "group",
			name = "Design mode",
			handler = SwedgeTimer,
			order = 0.9,
			args = {
				design_desc = {
					type = "description",
					order = 1,
					width = "full",
					name = "One switch to arrange everything SwedgeTimer draws: the swing bar, the seal icons, "
						.. "the successful twist text and the Next Action Guide (plus the Practice Mode "
						.. "displays while practicing). Drag any element into place - it snaps to a grid, hold "
						.. "Shift for free placement - click it for its size and style dials right there, and use the "
						.. "switches on the toolbar to turn elements on or off.",
				},
				open_design_mode = {
					type = "execute",
					order = 2,
					name = function()
						if st.editmode and st.editmode.active and st.editmode.active() then
							return "Exit design mode"
						end
						return "Enter design mode"
					end,
					desc = "Also available as /st design; Esc, Done or /st lock ends it.",
					func = function()
						if st.editmode and st.editmode.toggle then st.editmode.toggle() end
					end,
				},
				design_grid = {
					type = "select",
					order = 3,
					name = "Snap grid",
					desc = "Grid step that dragged elements snap to in design mode. Hold Shift while dropping an "
						.. "element to place it freely.",
					values = {
						[0] = "No snapping",
						[16] = "16 px (fine)",
						[24] = "24 px",
						[32] = "32 px",
						[48] = "48 px (wide)",
					},
					sorting = { 0, 16, 24, 32, 48 },
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.design_grid = key
						if st.editmode and st.editmode.refresh_grid then st.editmode.refresh_grid() end
					end,
				},
				design_scale = {
					type = "range",
					order = 4,
					name = "Toolbar size",
					desc = "Scale of the design mode toolbar.",
					min = 0.4, max = 1.5, step = 0.05,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.design_scale = key
						if st.editmode and st.editmode.apply_scale then st.editmode.apply_scale() end
					end,
				},
				design_card_scale = {
					type = "range",
					order = 5,
					name = "Card size",
					desc = "Scale of the design mode cards (element dials and the Effects & sounds window). "
						.. "A card can also be resized by dragging its bottom-right corner; double-click there resets it.",
					min = 0.4, max = 1.5, step = 0.05,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.design_card_scale = key
						if st.editmode and st.editmode.apply_scale then st.editmode.apply_scale() end
					end,
				},
			},
		},
		minimap_button_enabled = {
			order = 1.2,
			type = "toggle",
			name = "Minimap button",
			desc = "Display a button on the minimap to toggle the swing timer and access settings. Left-click to toggle bar, right-click to open settings, drag to reposition.",
			get = function()
				return not SwedgeTimer.db.profile.minimap.hide
			end,
			set = function(self, key)
				if key then
					st.minimap.show()
				else
					st.minimap.hide()
				end
			end
		},

		------------------------------------------------------------------------------------
		-- Practice Mode tab
		practice_mode = {
			type = "group",
			name = "|cFFFF8800Practice Mode|r",
			handler = SwedgeTimer,
			order = 0.05,
			args = {
				practice_header = {
					type = "header",
					order = 1,
					name = "Twist Practice Minigame",
				},
				practice_desc = {
					type = "description",
					order = 1.1,
					width = "full",
					name = "A fully simulated twist practice minigame. All spells are simulated " ..
						   "(no mana cost, no real casts). Practice openers, rotations, and " ..
						   "twisting at different haste levels.\n\n" ..
						   "Start/stop with: |cFF00FF00/st practice|r\n\n" ..
						   "Use the control panel to activate Bloodlust/Haste Potion (timed), " ..
						   "start a Boss Fight scenario, and see your current rotation. " ..
						   "Keybinds are configurable below or auto-detected from your action bars.\n",
				},
				practice_toggle = {
					type = "execute",
					order = 1.2,
					name = function()
						if st.practice and st.practice.active then
							return "Stop Practice"
						else
							return "Start Practice"
						end
					end,
					func = function()
						if st.practice and st.practice.toggle then
							st.practice.toggle()
							LibStub("AceConfigRegistry-3.0"):NotifyChange("SwedgeTimer_Options")
						end
					end,
				},

				-- Simulation settings (core gameplay)
				practice_sim_header = {
					type = "header",
					order = 2,
					name = "Simulation",
				},
				practice_weapon_speed = {
					type = "range",
					order = 2.1,
					name = "Weapon Speed",
					desc = "Override weapon speed for practice. Set to 0 to use your currently equipped weapon's speed.",
					min = 0, max = 5.0, step = 0.1,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.practice_weapon_speed = key
						if st.practice and st.practice.active then
							st.practice.recalc_speed()
						end
					end,
				},
				practice_aw_includes_pot = {
					type = "toggle",
					order = 2.2,
					name = "AW Macro: Haste Pot",
					desc = "When Avenging Wrath is cast, also activate Haste Potion automatically. Simulates a common /cast Avenging Wrath + /use Haste Potion macro.",
					get = "GetValue",
					set = "SetValue",
				},
				practice_aw_includes_sob = {
					type = "toggle",
					order = 2.3,
					name = "AW Macro: Seal of Blood",
					desc = "When Avenging Wrath is cast, also cast Seal of Blood automatically. Simulates a common /cast Avenging Wrath + /cast Seal of Blood macro.",
					get = "GetValue",
					set = "SetValue",
				},
				practice_dst_enabled = {
					type = "toggle",
					order = 2.4,
					name = "Dragonspine Trophy Proc",
					desc = "Simulate Dragonspine Trophy: random chance on melee swing to gain 325 haste rating for 10 seconds (~1 PPM, 20s ICD).",
					get = "GetValue",
					set = "SetValue",
				},

				practice_spell_queue_window = {
					type = "range",
					order = 2.5,
					name = "Spell Queue Window (ms)",
					desc = "Simulates WoW's spell queue window. When you press an ability within this time before your GCD expires, it will be queued and cast automatically when the GCD finishes. Set to 0 to disable. Default is 400ms, matching WoW's default SpellQueueWindow CVar.",
					min = 0, max = 400, step = 10,
					get = function() return SwedgeTimer.db.profile.practice_spell_queue_window * 1000 end,
					set = function(self, key) SwedgeTimer.db.profile.practice_spell_queue_window = key / 1000 end,
				},

				-- Boss Fight settings
				practice_fight_header = {
					type = "header",
					order = 3,
					name = "Boss Fight",
				},
				practice_bl_delay = {
					type = "range",
					order = 3.1,
					name = "Bloodlust Delay (seconds)",
					desc = "During a boss fight, Bloodlust will auto-fire after this many seconds. Set to 0 for immediate BL on fight start.",
					min = 0, max = 120, step = 1,
					get = "GetValue",
					set = "SetValue",
				},

				-- Rotation Display
				practice_rotation_display_header = {
					type = "header",
					order = 4,
					name = "Rotation Display",
				},
				practice_rotation_display_enabled = {
					type = "toggle",
					order = 4.1,
					name = "Enable Rotation Display",
					desc = "Show a center-screen rotation reference display during practice showing the current rotation sequence.",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.practice_rotation_display_enabled = key
						if st.practice and st.practice.rotation_display then
							if key and st.practice.active then
								st.practice.rotation_display:Show()
								if st.practice.update_rotation_display then
									st.practice.update_rotation_display()
								end
							else
								st.practice.rotation_display:Hide()
							end
						end
					end,
				},
				practice_rotation_display_icon_size = {
					type = "range",
					order = 4.2,
					name = "Icon Size",
					desc = "Size of the rotation step icons in the center display.",
					min = 24, max = 64, step = 2,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.practice_rotation_display_icon_size = key
						if st.practice and st.practice.update_rotation_display then
							st.practice.update_rotation_display()
						end
					end,
				},
				practice_rotation_display_icon_spacing = {
					type = "range",
					order = 4.3,
					name = "Icon Spacing",
					desc = "Space between rotation step icons in the center display.",
					min = 0, max = 20, step = 1,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.practice_rotation_display_icon_spacing = key
						if st.practice and st.practice.update_rotation_display then
							st.practice.update_rotation_display()
						end
					end,
				},

				-- Fight Timeline
				practice_timeline_header = {
					type = "header",
					order = 5,
					name = "Fight Timeline",
				},
				practice_timeline_enabled = {
					type = "toggle",
					order = 5.1,
					name = "Enable Fight Timeline",
					desc = "Show a WarcraftLogs-style cast timeline during boss fights. The timeline auto-opens on fight start and persists for post-fight review.",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.practice_timeline_enabled = key
						if st.practice and st.practice.timeline_frame then
							if not key then
								st.practice.timeline_frame:Hide()
								st.practice.timeline_visible = false
							end
						end
					end,
				},
				practice_timeline_mode = {
					type = "select",
					order = 5.15,
					name = "Timeline Display",
					desc = "Always: timeline opens when the fight starts. After twist: timeline only appears after your first successful twist.",
					values = {
						always = "Always show",
						after_twist = "Show after twist",
					},
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.practice_timeline_mode = key
					end,
				},
				practice_timeline_width = {
					type = "range",
					order = 5.2,
					name = "Timeline Width",
					desc = "Width of the timeline panel in pixels.",
					min = 300, max = 1200, step = 10,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.practice_timeline_width = key
						if st.practice and st.practice.timeline_frame then
							local frame = st.practice.timeline_frame
							frame:SetWidth(key + 60 + 16)  -- TIMELINE_LABEL_WIDTH + padding
							frame.scroll_frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -4)
							st.practice.timeline_needs_render = true
						end
					end,
				},
				practice_timeline_pixels_per_second = {
					type = "range",
					order = 5.3,
					name = "Timeline Zoom (px/sec)",
					desc = "How many pixels represent one second of fight time. Higher values zoom in for more detail.",
					min = 20, max = 200, step = 5,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.practice_timeline_pixels_per_second = key
						if st.practice and st.practice.timeline_visible then
							st.practice.timeline_needs_render = true
						end
					end,
				},

				-- Feedback Text (cosmetic)
				practice_feedback_header = {
					type = "header",
					order = 6,
					name = "Feedback Text",
				},
				practice_result_duration = {
					type = "range",
					order = 6.2,
					name = "Result Text Duration",
					desc = "How long the TWIST!/MISS text shows after each swing.",
					min = 0.3, max = 3.0, step = 0.1,
					get = "GetValue",
					set = "SetValue",
				},
				practice_result_text_size = {
					type = "range",
					order = 6.3,
					name = "Result Text Size",
					desc = "Font size for the TWIST!/MISS popup text.",
					min = 12, max = 48, step = 1,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.practice_result_text_size = key
						if st.practice and st.practice.update_result_text_font then
							st.practice.update_result_text_font()
						end
					end,
				},
				practice_result_color_hit = {
					type = "color",
					order = 6.4,
					name = "Twist Color",
					desc = "Color for the TWIST! text on successful timing.",
					hasAlpha = false,
					get = function()
						local c = SwedgeTimer.db.profile.practice_result_color_hit
						return c[1], c[2], c[3], c[4] or 1
					end,
					set = function(self, r, g, b, a)
						SwedgeTimer.db.profile.practice_result_color_hit = {r, g, b, a}
					end,
				},
				practice_result_color_miss = {
					type = "color",
					order = 6.5,
					name = "Miss Color",
					desc = "Color for the MISS text on failed timing.",
					hasAlpha = false,
					get = function()
						local c = SwedgeTimer.db.profile.practice_result_color_miss
						return c[1], c[2], c[3], c[4] or 1
					end,
					set = function(self, r, g, b, a)
						SwedgeTimer.db.profile.practice_result_color_miss = {r, g, b, a}
					end,
				},

			},
		},

		------------------------------------------------------------------------------------
		-- Twist Feedback tab (top of settings list) - NEW in 1.5.1
		twist_feedback = {
			type = "group",
			name = "|cFF00FF00Twist Feedback|r",
			handler = SwedgeTimer,
			order = 0.1,
			args = {
				twist_feedback_header = {
					type = "header",
					name = "Twist Feedback System",
					order = 0,
				},
				twist_feedback_intro = {
					type = "description",
					order = 0.1,
					width = "full",
					name = "|cFFFFD100NEW in 1.5.1!|r Get real-time audio and visual feedback on your seal twisting performance.\n",
				},
				twist_success_desc = {
					type = "description",
					order = 0.2,
					width = "full",
					name = "|cFF888888Missed twist:|r No twist performed (single seal or no seal)\n" ..
					       "|cFFFFFF00Attempted twist:|r Both seals active, but Command didn't proc\n" ..
					       "|cFF00FF00Successful twist:|r Both seals active AND Command procced|r\n",
				},

				------------------------------------------------------------------------------------
				-- Twist attempt feedback (learning mode)
				twist_attempt_header = {
					type = "header",
					order = 1,
					name = "Twist Attempt Alerts",
				},
				twist_attempt_desc = {
					type = "description",
					order = 1.1,
					width = "full",
					name = "These alerts trigger when you correctly time a twist (both seals active on your swing), regardless of whether Command procs.",
				},
				twist_success_sound_enabled = {
					type = "toggle",
					order = 1.2,
					width = "normal",
					name = "Sound alert",
					desc = "Play a sound when a twist is attempted (both seals active on swing).",
					get = "GetValue",
					set = "SetValue",
				},
				twist_success_sound_choice = {
					type = "select",
					order = 1.3,
					width = "normal",
					name = "Sound effect",
					desc = "Choose which sound to play on twist attempt. Hover over a sound in the list to preview it.",
					dialogControl = "Dropdown-SoundPreview",
					values = twist_sound_options,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.twist_success_sound_choice = key
						-- Play preview
						local sound_path = st.bar.twist_sounds and st.bar.twist_sounds[key]
						if sound_path then
							PlaySoundFile(sound_path, SwedgeTimer.db.profile.sound_channel or "Master")
						end
					end,
					disabled = function() return not SwedgeTimer.db.profile.twist_success_sound_enabled end,
				},
				twist_success_spacer1 = {
					type = "description",
					order = 1.35,
					width = "full",
					name = "",
				},
				twist_success_glow_enabled = {
					type = "toggle",
					order = 1.4,
					width = "normal",
					name = "Bar glow effect",
					desc = "Show a glowing pulse around the bar when a twist is attempted.",
					get = "GetValue",
					set = "SetValue",
				},
				twist_success_glow_color = {
					order = 1.5,
					type = "color",
					width = "half",
					name = "Color",
					desc = "The color of the success glow effect.",
					hasAlpha = true,
					get = function()
						local tab = SwedgeTimer.db.profile.twist_success_glow_color
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self, r, g, b, a)
						SwedgeTimer.db.profile.twist_success_glow_color = {r, g, b, a}
					end,
					disabled = function() return not SwedgeTimer.db.profile.twist_success_glow_enabled end,
				},
				twist_success_glow_spacer = {
					type = "description",
					order = 1.55,
					width = "full",
					name = "",
				},
				twist_success_glow_type = {
					type = "select",
					order = 1.56,
					width = "full",
					name = "Glow style",
					desc = "The type of animated glow effect to use.",
					dialogControl = "Dropdown-Left",
					values = {
						Pixel = "Pixel Glow (rotating lines)",
						AutoCast = "AutoCast Shine (particles)",
						Button = "Button Glow (spell proc)",
						HolyNova = "Holy Nova (expanding ring)",
						SealSpiral = "Seal Spiral (swirling energy)",
					},
					get = "GetValue",
					set = "SetValue",
					disabled = function() return not SwedgeTimer.db.profile.twist_success_glow_enabled end,
				},
				twist_success_glow_duration = {
					type = "range",
					order = 1.57,
					width = "normal",
					name = "Duration (sec)",
					desc = "How long the glow effect lasts in seconds.",
					min = 0.1, max = 4.0,
					step = 0.1,
					get = "GetValue",
					set = "SetValue",
					disabled = function() return not SwedgeTimer.db.profile.twist_success_glow_enabled end,
				},
				twist_success_glow_lines = {
					type = "range",
					order = 1.58,
					width = "normal",
					name = "Lines/Particles",
					desc = "Number of animated elements (8 default for Pixel, 4 for AutoCast).",
					min = 2, max = 16, step = 1,
					get = "GetValue",
					set = "SetValue",
					disabled = function() return not SwedgeTimer.db.profile.twist_success_glow_enabled end,
				},
				twist_success_glow_frequency = {
					type = "range",
					order = 1.59,
					width = "normal",
					name = "Speed",
					desc = "Animation speed. Negative values reverse direction.",
					min = -2.0, max = 2.0, step = 0.05,
					get = "GetValue",
					set = "SetValue",
					disabled = function() return not SwedgeTimer.db.profile.twist_success_glow_enabled end,
				},
				twist_success_glow_thickness = {
					type = "range",
					order = 1.60,
					width = "normal",
					name = "Thickness",
					desc = "Line thickness for Pixel glow style.",
					min = 1, max = 5, step = 1,
					get = "GetValue",
					set = "SetValue",
					disabled = function()
						local glowType = SwedgeTimer.db.profile.twist_success_glow_type
						return not SwedgeTimer.db.profile.twist_success_glow_enabled or glowType ~= "Pixel"
					end,
				},
				twist_success_glow_scale = {
					type = "range",
					order = 1.61,
					width = "normal",
					name = "Particle Scale",
					desc = "Scale factor for AutoCast particles. Higher values make particles larger and more visible.",
					min = 0.5, max = 3.0, step = 0.1,
					get = "GetValue",
					set = "SetValue",
					disabled = function()
						local glowType = SwedgeTimer.db.profile.twist_success_glow_type
						return not SwedgeTimer.db.profile.twist_success_glow_enabled or glowType ~= "AutoCast"
					end,
				},

				------------------------------------------------------------------------------------
				-- Successful Twist Text (Command proc feedback)
				successful_twist_text_header = {
					type = "header",
					order = 2,
					name = "Successful Twist Text",
				},
				successful_twist_text_desc = {
					type = "description",
					order = 2.1,
					width = "full",
					name = "Display customizable text when Command procs during a twist (true successful twist).",
				},
				successful_twist_text_enabled = {
					type = "toggle",
					order = 2.2,
					width = "normal",
					name = "Enable",
					desc = "Show the \"Successful TWIST!\" text on screen when Command procs during a twist.",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.successful_twist_text_enabled = key
						st.bar.set_success_text_position()
					end,
				},
				successful_twist_text_mode = {
					type = "select",
					order = 2.25,
					width = "normal",
					name = "Display via",
					desc = "Where the text appears. \"Own frame\" is SwedgeTimer's movable text. "
						.. "\"Scrolling combat text\" sends it to Mik's Scrolling Battle Text (notification area) "
						.. "when that addon is loaded, otherwise to Blizzard's floating combat text.",
					values = { frame = "Own frame", sct = "Scrolling combat text" },
					sorting = { "frame", "sct" },
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.successful_twist_text_mode = key
						st.bar.set_success_text_position()
					end,
					disabled = function() return not SwedgeTimer.db.profile.successful_twist_text_enabled end,
				},
				successful_twist_text_font = {
					type = "select",
					order = 2.3,
					width = "normal",
					name = "Font",
					desc = "The font to use for the success text.",
					dialogControl = "LSM30_Font",
					values = SML:HashTable("font"),
					get = function(info) return SwedgeTimer.db.profile.successful_twist_text_font or SML.DefaultMedia.font end,
					set = function(self, key)
						SwedgeTimer.db.profile.successful_twist_text_font = key
						st.bar.update_success_text_properties()
					end,
					disabled = function() return not SwedgeTimer.db.profile.successful_twist_text_enabled end,
				},
				successful_twist_text_size = {
					type = "range",
					order = 2.4,
					width = "normal",
					name = "Font size",
					desc = "The size of the success text.",
					min = 12, max = 48, step = 1,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.successful_twist_text_size = key
						st.bar.update_success_text_properties()
					end,
					disabled = function() return not SwedgeTimer.db.profile.successful_twist_text_enabled end,
				},
				successful_twist_text_outline = {
					type = "select",
					order = 2.5,
					width = "normal",
					name = "Font outline",
					desc = "The outline style for the success text.",
					values = outlines,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.successful_twist_text_outline = key
						st.bar.update_success_text_properties()
					end,
					disabled = function() return not SwedgeTimer.db.profile.successful_twist_text_enabled end,
				},
				successful_twist_text_color = {
					type = "color",
					order = 2.6,
					width = "normal",
					name = "Color",
					desc = "The color of the success text.",
					hasAlpha = true,
					get = function()
						local tab = SwedgeTimer.db.profile.successful_twist_text_color
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self, r, g, b, a)
						SwedgeTimer.db.profile.successful_twist_text_color = {r, g, b, a}
						st.bar.update_success_text_properties()
					end,
					disabled = function() return not SwedgeTimer.db.profile.successful_twist_text_enabled end,
				},
				successful_twist_text_duration = {
					type = "range",
					order = 2.7,
					width = "normal",
					name = "Duration (sec)",
					desc = "How long the text stays visible before fading out.",
					min = 0.5, max = 5.0, step = 0.1,
					get = "GetValue",
					set = "SetValue",
					disabled = function() return not SwedgeTimer.db.profile.successful_twist_text_enabled end,
				},
				successful_twist_text_locked = {
					type = "toggle",
					order = 2.8,
					width = "normal",
					name = "Lock position",
					desc = "When unlocked, you can drag the text to reposition it anywhere on screen.",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.successful_twist_text_locked = key
						st.bar.set_success_text_position()
					end,
					disabled = function() return not SwedgeTimer.db.profile.successful_twist_text_enabled end,
				},
			},
		},

		------------------------------------------------------------------------------------
		-- Features tab
		features = {
			type = "group",
			name = "Features",
			handler = SwedgeTimer,
			order = 1,
			args = {
				features_header = {
					type = "header",
					name = "Feature Toggles",
					order = 0.1,
				},
				bar_enabled = {
					type = "toggle",
					order = 1,
					name = "Show bar",
					desc = "Show or hide the swing timer bar.",
					get = "GetValue",
					set = "SetValue",
				},
				judgement_marker_enabled = {
					type = "toggle",
					order = 2,
					name = "Judgement marker",
					desc = "When enabled, indicates where on the swing timer judgement will come off cooldown (if in "..
					"a high value spell to judge like Seal of Blood).",
					get = "GetValue",
					set = "SetValue",
				},
				enable_deadzone = {
					type = "toggle",
					order = 3,
					name = "Enable deadzone",
					desc = "When enabled, will display a shaded region at the end of the bar corresponding to the \"Deadzone\", where "..
					"the player is locked into their current seal for this swing due to latency.",
					get = "GetValue",
					set = function(self, value)
						SwedgeTimer.db.profile.enable_deadzone = value
						if value then
							st.bar.frame.deadzone:Show()
						else
							st.bar.frame.deadzone:Hide()
						end
					end,
				},
				bar_twist_color_enabled = {
					type="toggle",
					order=4,
					name="Twist color",
					desc="When the player is actively twisting, and two seals are active, the bar will turn a special color "..
					"dictated in the Appearance settings.",
					get = "GetValue",
					set = "SetValue",
				},

				------------------------------------------------------------------------------------
				-- Sound settings
				sound_header = {
					type = "header",
					name = "Sound Settings",
					order = 5,
				},
				twist_sound_enabled = {
					type = "toggle",
					order = 5.1,
					name = "Twist window sound",
					desc = "Plays a subtle sound when the swing timer enters the twist window. Only plays when Seal of Command or Seal of Righteousness is active.",
					get = "GetValue",
					set = "SetValue",
				},
				twist_sound_choice = {
					type = "select",
					order = 5.2,
					name = "Sound effect",
					desc = "Choose which sound to play when entering the twist window. Hover over a sound in the list to preview it.",
					dialogControl = "Dropdown-SoundPreview",
					values = twist_sound_options,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.twist_sound_choice = key
						-- Play preview of selected sound
						local sound_path = st.bar.twist_sounds and st.bar.twist_sounds[key]
						if sound_path then
							PlaySoundFile(sound_path, SwedgeTimer.db.profile.sound_channel or "Master")
						end
					end,
					disabled = function() return not SwedgeTimer.db.profile.twist_sound_enabled end,
				},
				sound_channel = {
					type = "select",
					order = 5.3,
					name = "Sound channel",
					desc = "Which audio channel to play sounds on. Master bypasses SFX mute.",
					values = {
						Master = "Master",
						SFX = "Sound Effects",
						Music = "Music",
						Ambience = "Ambience",
						Dialog = "Dialog",
					},
					get = "GetValue",
					set = "SetValue",
				},
			},
		},

		------------------------------------------------------------------------------------
		-- addon feature behaviour
		bar_behaviour = {
			type = "group",
			name = "Behaviour",
			handler = SwedgeTimer,
			order = 2,
			args = {
				------------------------------------------------------------------------------------
				-- Visibility options, when to show the bar.
				autohide_header = {
					type="header",
					order=5.0,
					name="Bar visibility",
				},
				autohide_desc = {
					type="description",
					order=5.01,
					name="Determines under what conditions the bar should be shown.",
				},
				visibility_key = {
					type="select",
					order=5.1,
					name="Visibility",
					desc="The visibility setting to use.",
					values=bar_visibility_values,
					sorting=bar_vis_ordering,
					get = "GetValue",
					set = "SetValue",
				},

				------------------------------------------------------------------------------------
				-- Deadzone scaling.
				deadzone_header = {
					type="header",
					order = 5.5,
					name = "Deadzone scaling"					,
				},
				deadzone_desc = {
					type="description",
					order = 5.51,
					name="The deadzone can be adjusted by a scale factor to better suit the unique"..
					" properties of a player's connection to the game world. Decrease this value if you are able "..
					"to twist inside your deadzone, or increase this value if you cannot twist when just "..
					"outside the deadzone.",
				},
				deadzone_scale_factor = {
					type = "range",
					order = 5.52,
					name="Deadzone scale factor",
					desc="This multiplier will be applied to the player's latency to the game world"..
					" to determine the size of the deadzone.",
					min=0.1, max=2.0,
					step=0.05,
					get="GetValue",
					set="SetValue",
					disabled = function()
						return SwedgeTimer.db.profile.enable_deadzone == false
					end,
				},

				------------------------------------------------------------------------------------
				-- marker options
				marker_settings = {
					order=6,
					type="header",
					name="Marker settings",
				},
				marker_descriptions = {
					order=7,
					type="description",
					name="When GCD offset mode is Dynamic or Fixed, the GCD marker is pushed back "..
					"from the end of the swing to account for player input/lag. When the mode is set to Dynamic, this uses the calibrated lag "..
					"described in Lag Compensation."
				},
				gcd_padding_mode = {
					order=8,
					type="select",
					values=gcd_padding_modes,
					style="dropdown",
					desc="The type of GCD offset, if any, to use.",
					name="GCD offset mode",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.gcd_padding_mode=key
						st.bar.set_gcd_marker_offsets()
					end,
				},
				gcd_static_padding_ms = {
					type = "range",
					order = 9,
					name = "Fixed GCD offset (ms)",
					desc = "The GCD marker is set at one standard GCD before the swing ends, plus this offset.",
					min = 0, max = 400,
					step = 1,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.gcd_static_padding_ms = key
						st.bar.set_gcd_marker_offsets()
					end,
					disabled = function()
						return SwedgeTimer.db.profile.gcd_padding_mode ~= "Fixed"
					end,
				},

				twist_window_descriptions = {
					order=10.1,
					type="description",
					name="When Twist window offset mode is Dynamic or Fixed, the twist window marker is pushed back "..
					"from the end of the swing to account for player input/lag. When the mode is set to Dynamic, this uses the calibrated lag "..
					"described in Lag Compensation."
				},
				twist_padding_mode = {
					order=10.2,
					type="select",
					values=gcd_padding_modes,
					style="dropdown",
					desc="The type of twist window offset, if any, to use.",
					name="Twist window offset mode",
					get = "GetValue",
					-- set = "SetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.twist_padding_mode = key
						st.bar.set_twist_tick_offset()
					end,

				},
				twist_window_padding_ms = {
					type = "range",
					order = 10.3,
					name = "Fixed twist offset (ms)",
					desc = "The twist window indicator is placed (400ms plus the offset value) before the end of the swing. Players with high "..
					"latency may wish to increase this value.",
					min = 0, max=400,
					step=1,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.twist_window_padding_ms = key
						st.bar.set_twist_tick_offset()
					end
					,
					disabled = function()
						return SwedgeTimer.db.profile.twist_padding_mode ~= "Fixed"
					end,
				},
			},
		},

		------------------------------------------------------------------------------------
		-- Lag detection
		lag_detection_section= {
			type = "group",
			name = "Lag Compensation",
			handler = SwedgeTimer,
			order = 5,			
			args = {
				lag_settings = {
					order=5.01,
					type="header",
					name="What is lag compensation?",
				},
				lag_descriptions1 = {
					order=5.02,
					type="description",
					name="Many Ret players are familiar with attempting a close twist after a GCD, only to swing in command.",
				},
				lag_descriptions101 = {
					order=5.03,
					type="description",
					image="Interface/AddOns/SwedgeTimer/Images/close_twist4.blp",
					imageWidth=350,
					imageHeight=350*0.2,
					imageCoords={0.00,1.0,0.4,0.6},
					name="",
				},
				lag_descriptions1001 = {
					order=5.031,
					type="description",
					name="In the above image, the player is in SoC, and has a small amount of time after their GCD ends to cast SoB."..
					" Even with spell queueing, if the player's lag is high enough, the SoB cast can be pushed into the next swing.",
				},
				lag_descriptions102 = {
					order=5.04,
					type="description",
					name="SwedgeTimer includes a lag compensation suite, that detects instances where the player will not be "..
					"able to twist before their swing goes off due to latency.",
				},
				lag_descriptions103 = {
					order=5.05,
					type="description",
					name="",
					image="Interface/AddOns/SwedgeTimer/Images/dont_twist1.blp",
					imageWidth=350,
					imageHeight=350*0.2,
					imageCoords={0.00,1.0,0.4,0.6},
				},
				lag_descriptions104 = {
					order=5.06,
					type="description",
					name="If you see the bar turn the color specified above, don't try to twist; either ride the command swing and cast "..
					"a filler spell like Consecration, or momentarily stopattack before SoB/startattacking.",
				},

				lag_detection_enabled = {
					type = "toggle",
					order = 4.1,
					name = "Lag compensation",
					desc = "Enables the lag compensation suite.",
					get = "GetValue",
					set = "SetValue",
					},
				bar_color_cant_twist = {
					order=4.2,
					type="color",
					name="Bar color",
					desc="The color the bar turns when the player is in a good seal to twist from, but "..
					"their GCD combined with their lag will mean they cannot twist this swing unless they stopattack.",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_cant_twist
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_cant_twist = {r,g,b,a}
					end
				},
				lag_descriptions2001 = {
					order=5.20,
					type="header",
					name="How it works",
				},
				lag_descriptions_20002 = {
					order=5.201,
					type="description",
					name="To detect impossible twists, we compare the time left on the player's swing after the GCD expires to some value representing "..
					"the lag. If the time left after GCD is lower than this lag value, the lag compensation is triggered.",
				},
				lag_descriptions_2002 = {
					order=5.21,
					type="description",
					name="The player's raw latency is often not the most accurate predictor of impossible twists. Instead of using the raw latency, we "..
					"adjust the lag according to the settings below for the best result. SwedgeTimer is pre-calibrated, but everyone's connection is different, "..
					"and optimal settings may vary among players."
				},

				lag_descriptions3001 = {
					order=6.0,
					type="header",
					name="Do I need to calibrate?",
				},
				lag_descriptions_3002 = {
					order=6.22,
					type="description",
					name="To see if you require calibration, simply try some close twists on a target. Cast any spell when the bar is approaching the middle GCD marker, and try to twist your swing."..
					" if the special bar color triggers only when you get command swings, and you are able to twist all swings where the bar color does not trigger, you are calibrated correctly."..
					" If not, you may need to change the settings below.",
				},
				lag_descriptions4001 = {
					order=7.0,
					type="header",
					name="Calibration settings",
				},
				lag_descriptions_2 = {
					order=7.22,
					type="description",
					name="The figure compared to the swing time remaining after GCD is equal to (ax + b), where x is the raw latency, a is the multipler, and b is the offset.",
				},
				lag_descriptions_22 = {
					order=7.23,
					type="description",
					name="If the special bar color is not triggering when you're forced into command swings, increase the multiplier or the threshold a small amount and try again.",
				},
				lag_descriptions_23 = {
					order=7.24,
					type="description",
					name="If the special bar color is triggering when you are able to twist, reduce the multipler or the threshold by a small amount and try again.",
				},
				-- lag_descriptions_2 = {
				-- 	order=7.23,
				-- 	type="description",
				-- 	name=""
				-- },
				lag_multiplier = {
					type = "range",
					order = 7.3,
					name = "Lag multiplier",
					desc = "The player's world trip latency is multiplied by this value in the lag detection calibration.",
					min = 0, max = 2.0,
					step = 0.05,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.lag_multiplier = key
						st.bar.set_gcd_marker_offsets()
						st.bar.set_twist_tick_offset()
					end,
				},
				lag_offset = {
					type = "range",
					order = 7.3,
					name = "Lag offset (ms)",
					desc = "The player's world trip latency has this value added to it in the lag detection calibration.",
					min = 0, max = 200,
					step = 1,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.lag_offset = key
						st.bar.set_gcd_marker_offsets()
						st.bar.set_twist_tick_offset()
					end,
				},
			},
		},

		------------------------------------------------------------------------------------
		-- Size/position options
		positioning = {
			type = "group",
			name = "Size and Position",
			handler = SwedgeTimer,
			order = 3,
			args = {

				------------------------------------------------------------------------------------
				-- size options
				size_header = {
					type='header',
					name='Size',
					order=1,
				},

				bar_width = {
					type = "range",
					order = 2,
					name = "Width",
					desc = "The width of the swing timer bar.",
					min = 100, max = 600,
					step = 1,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.bar_width = key
						set_bar_size()
					end,
				},

				bar_height = {
					type = "range",
					order = 3,
					name = "Height",
					desc = "The height of the swing timer bar.",
					min = 6, max = 60,
					step = 1,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.bar_height = key
						set_bar_size()
					end,
				},

				------------------------------------------------------------------------------------
				-- position options
				position_header = {
					type = 'header',
					name = 'Position',
					order = 4,
				},
				position_description = {
					order=4.1,
					type="description",
					name="When the bar is not locked, it can be clicked and dragged with the mouse.",
				},
				position_description2 = {
					order=4.2,
					type="description",
					name="If you don't understand how UI frames anchor, then either keep both anchors on "..
					"CENTER and enter offsets manually, or position the bar with the mouse.",
				},
				bar_x_offset = {
					type = "input",
					order = 5,
					name = "Bar x offset",
					desc = "The x position of the bar.",
					get = function()
						return tostring(SwedgeTimer.db.profile.bar_x_offset)
					end,
					set = function(self, input)
						SwedgeTimer.db.profile.bar_x_offset = input
						set_bar_position()
					end			
				},
				bar_y_offset = {
					type = "input",
					order = 6,
					name = "Bar y offset",
					desc = "The y position of the bar.",
					get = function()
						return tostring(SwedgeTimer.db.profile.bar_y_offset)
					end,
					set = function(self, input)
						SwedgeTimer.db.profile.bar_y_offset = input
						set_bar_position()
					end			
				},

				bar_point = {
					order = 6.1,
					type="select",
					name = "Anchor",
					desc = "One of the region's anchors.",
					values = valid_anchor_points,
					get = "GetValue",
					set = function(self, input)
						SwedgeTimer.db.profile.bar_point = input
						set_bar_position()
					end,
				},
				bar_rel_point = {
					order = 6.2,
					type="select",
					name = "Relative anchor",
					desc = "Anchor point on region to align against.",
					values = valid_anchor_points,
					get = "GetValue",
					set = function(self, input)
						SwedgeTimer.db.profile.bar_rel_point = input
						set_bar_position()
					end,
				},
				bar_locked = {
					type = "toggle",
					order = 4.15,
					name = "Bar locked",
					desc = "Prevents the swing bar from being dragged with the mouse.",
					get = "GetValue",
					set = function(self, input)
						SwedgeTimer.db.profile.bar_locked = input
						st.bar.frame:SetMovable(not input)
						st.bar.frame:EnableMouse(not input)
					end,
				},

				------------------------------------------------------------------------------------
				-- strata/draw level options
				strata_header = {
					type = 'header',
					name = 'Frame Strata',
					order = 7.0,
				},
				strata_description = {
					type = 'description',
					name = 'The frame strata the addon should be drawn at. Anything higher than MEDIUM will be drawn over some in-game menus, so this is the highest strata allowed.',
					order = 7.1,
				},
				frame_strata = {
					order = 7.2,
					type="select",
					name = "Frame strata",
					desc = "The frame strata the addon should be drawn at.",
					values = {
						BACKGROUND = "BACKGROUND",
						LOW = "LOW",
						MEDIUM = "MEDIUM",
					},
					get = "GetValue",
					set = function(self, input)
						SwedgeTimer.db.profile.frame_strata = input
						st.bar.frame:SetFrameStrata(input)
						st.bar.frame.backplane:SetFrameStrata(input)
					end,
				},
				draw_level = {
					type = "range",
					order = 7.3,
					name = "Draw level",
					desc = "The bar's draw level within the frame strata.",
					min = 1, max=100,
					step=1,
					get = "GetValue",
					set = function(self, input)
						SwedgeTimer.db.profile.draw_level = input
						st.bar.frame:SetFrameLevel(input+1)
						st.bar.frame.backplane:SetFrameLevel(input)
					end
				},

			},
		},

		------------------------------------------------------------------------------------
		-- All appearance options
		bar_appearance = {
			type = "group",
			name = "Appearance",
			handler = SwedgeTimer,
			order = 4,
			args = {

				------------------------------------------------------------------------------------
				-- texture options
				texture_header = {
					order=1,
					type="header",
					name="Textures",
				},
				bar_texture_key = {
					order = 2,
					type = "select",
					name = "Bar",
					desc = "The texture of the swing bar.",
					dialogControl = "LSM30_Statusbar",
					values = SML:HashTable("statusbar"),
					get = function(info) return SwedgeTimer.db.profile.bar_texture_key or SML.DefaultMedia.statusbar end,
					set = function(self, key)
						SwedgeTimer.db.profile.bar_texture_key = key
						st.bar.frame.bar:SetTexture(SML:Fetch('statusbar', key))
					end
				},
				
				gcd_texture_key = {
					order = 2.1,
					type = "select",
					name = "GCD underlay",
					desc = "The texture of the GCD underlay bar.",
					dialogControl = "LSM30_Statusbar",
					values = SML:HashTable("statusbar"),
					get = function(info) return SwedgeTimer.db.profile.gcd_texture_key or SML.DefaultMedia.statusbar end,
					set = function(self, key)
						SwedgeTimer.db.profile.gcd_texture_key = key
						st.bar.frame.gcd_bar:SetTexture(SML:Fetch('statusbar', key))
						st.bar.set_gcd_bar_width()
					end
				},

				backplane_texture_key = {
					order = 2.2,
					type = "select",
					name = "Backplane",
					desc = "The texture of the bar's backplane.",
					dialogControl = "LSM30_Statusbar",
					values = SML:HashTable("statusbar"),
					get = function(info) return SwedgeTimer.db.profile.backplane_texture_key or SML.DefaultMedia.statusbar end,
					set = function(self, key)
						SwedgeTimer.db.profile.backplane_texture_key = key
						st.bar.frame.backplane.backdropInfo.bgFile = SML:Fetch('statusbar', key)
						st.bar.frame.backplane:ApplyBackdrop()
						st.bar.frame.backplane:SetBackdropColor(0,0,0, SwedgeTimer.db.profile.backplane_alpha)
					end
				},

				backplane_alpha = {
					type = "range",
					order = 2.3,
					name = "Backplane alpha",
					desc = "The opacity of the swing bar's backplane.",
					min = 0.0, max = 1.0,
					step = 0.05,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.backplane_alpha = key
						st.bar.frame.backplane:SetBackdropColor(0, 0, 0, key)
					end,
				},


				------------------------------------------------------------------------------------
				-- Border options
				bar_border_header = {
					order=3.5,
					type="header",
					name="Bar border",
				},
				bar_border_description = {
					order=3.51,
					type="description",
					name="The bar border can either be set to a solid color, a texture, or disabled.",
				},

				border_mode_key = {
					order=3.6,
					type="select",
					values=bar_border_modes,
					style="dropdown",
					desc="The outline mode to use for the bar border, if any.",
					name="Border mode",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.border_mode_key = key
						st.configure_bar_outline()
				
					end,
				},

				placeholder_1 = {
					type="description",
					order = 3.8,
					name = "",
				},

				backplane_outline_width = {
					type = "range",
					order = 5.1,
					name = "Solid outline thickness",
					desc = "The thickness of the outline around the swing timer bar, if in Solid border mode.",
					min = 0, max = 5,
					step = 0.2,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.backplane_outline_width = key
						st.configure_bar_outline()
					end,
					disabled = function()
						return SwedgeTimer.db.profile.border_mode_key ~= "Solid"
					end,
				},

				border_texture_key = {
					order = 6,
					type = "select",
					name = "Border",
					desc = "The border texture of the swing bar.",
					dialogControl = "LSM30_Border",
					values = SML:HashTable("border"),
					get = function(info) return SwedgeTimer.db.profile.border_texture_key or SML.DefaultMedia.border end,
					set = function(self, key)
						SwedgeTimer.db.profile.border_texture_key = key
						st.configure_bar_outline()
					end,
					disabled = function()
						return SwedgeTimer.db.profile.border_mode_key ~= "Texture"
					end,
				},

				------------------------------------------------------------------------------------
				-- deadzone settings
				deadzone_header = {
					order = 7.0,
					type = "header",
					name = "Deadzone",
				},
				deadzone_desc = {
					order = 7.01,
					type = "description",
					name = "The deadzone is the shaded region at the end of the bar indicating where the player cannot "..
					"change seals before their swing due to latency. "..
					"The deadzone must be enabled to be adjusted."
				},
				deadzone_texture_key = {
					order = 7.1,
					type = "select",
					name = "Deadzone texture",
					desc = "The texture of the deadzone bar.",
					dialogControl = "LSM30_Statusbar",
					values = SML:HashTable("statusbar"),
					get = function(info) return SwedgeTimer.db.profile.deadzone_texture_key or SML.DefaultMedia.statusbar end,
					set = function(self, key)
						SwedgeTimer.db.profile.deadzone_texture_key = key
						st.set_deadzone()
					end,
					disabled = function()
						return SwedgeTimer.db.profile.enable_deadzone ~= true
					end,
				},

				bar_color_deadzone = {
					order=7.2,
					type="color",
					name="Bar color",
					desc="The color of the deadzone bar",
					hasAlpha=true,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_deadzone
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_deadzone = {r,g,b,a}
						st.set_deadzone()
					end,
					disabled = function()
						return SwedgeTimer.db.profile.enable_deadzone ~= true
					end,
				},

				------------------------------------------------------------------------------------
				-- font settings
				fonts_header = {
					order=9,
					type="header",
					name="Fonts",
				},
				font_size = {
					type = "range",
					order = 9.03,
					name = "Font size",
					desc = "The size of the swing timer and attack speed fonts.",
					min = 10, max = 40, softMin = 8, softMax = 24,
					step = 1,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.font_size = key
						set_fonts()
					end,
				},
				font_color = {
					order=9.04,
					type="color",
					name="Font color",
					desc="The color of the addon texts.",
					hasAlpha=false,
					get = function()
						return unpack(SwedgeTimer.db.profile.font_color)
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.font_color = {r,g,b,a}
						set_fonts()
					end
				},
				text_font = {
					order = 9.01,
					type = "select",
					name = "Font",
					desc = "The font to use in the swing timer and attack speed text.",
					dialogControl = "LSM30_Font",
					values = SML:HashTable("font"),
					get = function(info) return SwedgeTimer.db.profile.text_font or SML.DefaultMedia.font end,
					set = function(self, key)
						SwedgeTimer.db.profile.text_font = key
						set_fonts()
					end
				},
				font_outline_key = {
					order=9.02,
					type="select",
					values=outlines,
					style="dropdown",
					desc="The outline type to use with the font.",
					name="Font outline",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.font_outline_key = key
						set_fonts()
					end,
				},
				left_text = {
					type="select",
					order = 9.1,
					values=texts,
					style="dropdown",
					name = "Left text",
					desc = "What to shows on the left of the swing timer bar.",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.left_text = key
						set_texts()
					end
				},
				right_text = {
					type="select",
					order = 9.1,
					values=texts,
					style="dropdown",
					name = "Right text",
					desc = "What to shows on the right of the swing timer bar.",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.right_text = key
						set_texts()
					end,
				},
				center_text = {
					type="select",
					order = 9.2,
					values=texts,
					style="dropdown",
					name = "Center text",
					desc = "What to show in the center of the swing timer bar.",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.center_text = key
						set_texts()
					end,
				},
				
				------------------------------------------------------------------------------------
				-- Contextual color settings
				context_colors_header = {
					type="header",
					order = 10,
					name = "Contextual bar colors",
				},
				bar_color_default = {
					order=11,
					type="color",
					name="No seal",
					desc="No seal active on the player.",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_default
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_default = {r,g,b,a}
						st.bar.set_bar_color()
					end
				},
				bar_color_twisting = {
					order=12,
					type="color",
					name="Active twist",
					desc="The player is mid-twist and has multiple seals active. Only is used if the relevant option is checked in the Behaviour settings.",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_twisting
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_twisting = {r,g,b,a}
						st.bar.set_bar_color()
					end
				},
				bar_color_warning = {
					order=13,
					type="color",
					name="Don't cast",
					desc="The color the bar turns when the player is in a good seal to twist from, but "..
					"does not have time to incur a GCD before their swing completes.",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_warning
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_warning = {r,g,b,a}
					end
				},

				------------------------------------------------------------------------------------
				-- Seal color settings
				seal_colors_header = {
					order=20,
					type="header",
					name="Seal colors",
				},



				bar_color_command = {
					order=21,
					type="color",
					name="Command",
					desc="Seal of Command (will turn the \"Don\'t Cast\" color when the player should not cast and wait to twist).",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_command
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_command = {r,g,b,a}
						st.bar.set_bar_color()
					end
				},
				bar_color_righteousness = {
					order=22,
					type="color",
					name="Righteousness",
					desc="Seal of Righteousness (will turn the \"Don\'t Cast\" color when the player should not cast and wait to twist)",
					hasAlpha=true,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_righteousness
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_righteousness = {r,g,b,a or 1}
						st.bar.set_bar_color()
					end
				},				
				bar_color_blood = {
					order=23,
					type="color",
					name="Blood",
					desc="Seal of Blood/Seal of the Martyr",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_blood
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_blood = {r,g,b,a}
						st.bar.set_bar_color()
					end
				},
				bar_color_wisdom = {
					order=25,
					type="color",
					name="Wisdom",
					desc="Seal of Wisdom",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_wisdom
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_wisdom = {r,g,b,a}
						st.bar.set_bar_color()
					end
				},

				bar_color_light = {
					order=26,
					type="color",
					name="Light",
					desc="Seal of Light",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_light
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_light = {r,g,b,a}
						st.bar.set_bar_color()
					end
				},

				bar_color_justice = {
					order=27,
					type="color",
					name="Justice",
					desc="Seal of Justice",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_justice
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_justice = {r,g,b,a}
						st.bar.set_bar_color()
					end
				},
				bar_color_crusader = {
					order=27.1,
					type="color",
					name="Crusader",
					desc="Seal of the Crusader",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_crusader
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_crusader = {r,g,b,a}
						st.bar.set_bar_color()
					end
				},
				bar_color_vengeance = {
					order=24,
					type="color",
					name="Vengeance",
					desc="Seal of Vengeance/Seal of Corruption",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_vengeance
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_vengeance = {r,g,b,a}
						st.bar.set_bar_color()
					end
				},

				------------------------------------------------------------------------------------
				-- GCD settings
				gcd_header = {
					order=30,
					type="header",
					name="GCD underlay",
				},
				bar_color_gcd = {
					order=31,
					type="color",
					name="Underlay color",
					desc="The color of the GCD underlay.",
					hasAlpha=true,
					get = function()
						local tab = SwedgeTimer.db.profile.bar_color_gcd
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.bar_color_gcd = {r,g,b,a}
						st.bar.frame.gcd_bar:SetVertexColor(unpack(SwedgeTimer.db.profile.bar_color_gcd))
					end
				},

				------------------------------------------------------------------------------------
				-- Marker appearance settings
				markers_header = {
					order=50,
					type="header",
					name="Markers",
				},
				gcd1_enabled = {
					type = "toggle",
					order = 50.1,
					name = "Enable GCD marker",
					desc = "Toggles drawing the GCD marker on the bar.",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.gcd1_enabled = key
						st.bar.show_or_hide_ticks()
					end,
				},
				-- marker_colors_header = {
				-- 	order=50.5,
				-- 	type="description",
				-- 	name="The GCD and twist window colors can be changed below.",
				-- },
				marker_width = {
					type = "range",
					order = 55,
					name = "Marker width",
					desc = "The width of the twist window GCD, and judgement markers.",
					min = 1, max = 6,
					step = 1,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.marker_width = key
						set_marker_widths()
					end,
				},
				marker_texture = {
					order = 51,
					type = "select",
					name = "Marker texture",
					desc = "The texture used for all marker lines (twist window, GCD, judgement).",
					dialogControl = "LSM30_Statusbar",
					values = SML:HashTable("statusbar"),
					get = function(info) return SwedgeTimer.db.profile.marker_texture or "Blizzard" end,
					set = function(self, key)
						SwedgeTimer.db.profile.marker_texture = key
						set_marker_colors()
					end
				},
				gcd_marker_color = {
					order=53,
					type="color",
					name="GCD color",
					desc="The color of the GCD markers.",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.gcd_marker_color
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.gcd_marker_color = {r,g,b,a}
						set_marker_colors()
					end
				},
				twist_marker_color = {
					order=52,
					type="color",
					name="Twist window color",
					desc="The color of the twist window marker.",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.twist_marker_color
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.twist_marker_color = {r,g,b,a}
						set_marker_colors()
					end
				},
				judgement_marker_color = {
					order=54,
					type="color",
					name="Judgement indicator",
					desc="The color of the judgement indicator marker, which shows when judgement will come off cooldown"..
					" on the player's swing timer. This marker only shows when the player is in a high-value spell to judge, "..
					"e.g. Blood, Vengeance, Justice.",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.judgement_marker_color
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.judgement_marker_color = {r,g,b,a}
						set_marker_colors()
					end
				},
			}
		},
		icon_settings = {
			order=6,
			type="group",
			name="Seal Icon",
			args = {
				icon_header = {
					type="header",
					order=1,
					name="Seal Icon Display",
				},
				icon_enabled = {
					order=2,
					type="toggle",
					name="Enable seal icon",
					desc="Display the currently active seal icon(s) to the right of the bar.",
					get = function()
						return SwedgeTimer.db.profile.icon_enabled
					end,
					set = function(self, key)
						SwedgeTimer.db.profile.icon_enabled = key
						if st.bar.icon_frame then
							st.bar.update_seal_icons()
						end
					end
				},
				icon_match_bar_height = {
					order=3,
					type="toggle",
					name="Match bar height",
					desc="When enabled, icon size automatically matches bar height.",
					get = function()
						return SwedgeTimer.db.profile.icon_match_bar_height
					end,
					set = function(self, key)
						SwedgeTimer.db.profile.icon_match_bar_height = key
						if st.bar.set_icon_size then
							st.bar.set_icon_size()
						end
					end
				},
				icon_size = {
					order=4,
					type="range",
					name="Icon size",
					desc="Size of the seal icon in pixels (only when not matching bar height).",
					min=16,
					max=64,
					step=1,
					get = function()
						return SwedgeTimer.db.profile.icon_size
					end,
					set = function(self, key)
						SwedgeTimer.db.profile.icon_size = key
						if st.bar.set_icon_size then
							st.bar.set_icon_size()
						end
					end,
					disabled = function()
						return SwedgeTimer.db.profile.icon_match_bar_height
					end
				},
				icon_spacing = {
					order=5,
					type="range",
					name="Icon spacing",
					desc="Gap between the bar and icon in pixels.",
					min=0,
					max=20,
					step=1,
					get = function()
						return SwedgeTimer.db.profile.icon_spacing
					end,
					set = function(self, key)
						SwedgeTimer.db.profile.icon_spacing = key
						if st.bar.set_icon_position then
							st.bar.set_icon_position()
						end
					end,
					disabled = function()
						return SwedgeTimer.db.profile.icon_detached
					end
				},
				icon_position_header = {
					order=6,
					type="header",
					name="Icon Position",
				},
				icon_detached = {
					order=7,
					type="toggle",
					name="Detach from bar",
					desc="When enabled, the seal icon can be positioned anywhere on the screen independently from the swing timer bar.",
					get = function()
						return SwedgeTimer.db.profile.icon_detached
					end,
					set = function(self, key)
						SwedgeTimer.db.profile.icon_detached = key
						if st.bar.set_icon_position then
							st.bar.set_icon_position()
						end
					end
				},
				icon_locked = {
					order=8,
					type="toggle",
					name="Icon locked",
					desc="When unlocked, the seal icon can be dragged with the mouse.",
					get = function()
						return SwedgeTimer.db.profile.icon_locked
					end,
					set = function(self, key)
						SwedgeTimer.db.profile.icon_locked = key
						if st.bar.set_icon_position then
							st.bar.set_icon_position()
						end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.icon_detached
					end
				},
				icon_x_offset = {
					order=9,
					type="input",
					name="Icon X offset",
					desc="The X position of the seal icon when detached.",
					get = function()
						return tostring(SwedgeTimer.db.profile.icon_x_offset)
					end,
					set = function(self, input)
						SwedgeTimer.db.profile.icon_x_offset = tonumber(input) or 0
						if st.bar.set_icon_position then
							st.bar.set_icon_position()
						end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.icon_detached
					end
				},
				icon_y_offset = {
					order=10,
					type="input",
					name="Icon Y offset",
					desc="The Y position of the seal icon when detached.",
					get = function()
						return tostring(SwedgeTimer.db.profile.icon_y_offset)
					end,
					set = function(self, input)
						SwedgeTimer.db.profile.icon_y_offset = tonumber(input) or 0
						if st.bar.set_icon_position then
							st.bar.set_icon_position()
						end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.icon_detached
					end
				},
				icon_point = {
					order=11,
					type="select",
					name="Anchor",
					desc="The anchor point of the seal icon.",
					values = valid_anchor_points,
					get = function()
						return SwedgeTimer.db.profile.icon_point
					end,
					set = function(self, input)
						SwedgeTimer.db.profile.icon_point = input
						if st.bar.set_icon_position then
							st.bar.set_icon_position()
						end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.icon_detached
					end
				},
				icon_rel_point = {
					order=12,
					type="select",
					name="Relative anchor",
					desc="The anchor point on the screen to align the seal icon against.",
					values = valid_anchor_points,
					get = function()
						return SwedgeTimer.db.profile.icon_rel_point
					end,
					set = function(self, input)
						SwedgeTimer.db.profile.icon_rel_point = input
						if st.bar.set_icon_position then
							st.bar.set_icon_position()
						end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.icon_detached
					end
				},
				icon_centered = {
					order=13,
					type="toggle",
					name="Center icons",
					desc="When enabled, keeps the icon display centered at the anchor point regardless of whether 1 or 2 seals are active. Prevents the display from shifting during twists.",
					get = function()
						return SwedgeTimer.db.profile.icon_centered
					end,
					set = function(self, key)
						SwedgeTimer.db.profile.icon_centered = key
						if st.bar.update_seal_icons then
							st.bar.update_seal_icons()
						end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.icon_detached
					end
				},
				seal_timer_header = {
					order=20,
					type="header",
					name="Seal Duration Timer",
				},
				seal_timer_enabled = {
					order=21,
					type="toggle",
					name="Show countdown text",
					desc="Display remaining seal duration as countdown text in the center of the icon.",
					get = function()
						return SwedgeTimer.db.profile.seal_timer_enabled
					end,
					set = function(self, key)
						SwedgeTimer.db.profile.seal_timer_enabled = key
					end
				},
				seal_cooldown_overlay_enabled = {
					order=22,
					type="toggle",
					name="Show cooldown overlay",
					desc="Display the radial cooldown swipe animation on the seal icon.",
					get = function()
						return SwedgeTimer.db.profile.seal_cooldown_overlay_enabled
					end,
					set = function(self, key)
						SwedgeTimer.db.profile.seal_cooldown_overlay_enabled = key
						if st.bar.icon_frame then
							st.bar.update_seal_icons()
						end
					end
				},
				seal_timer_size = {
					order=23,
					type="range",
					name="Timer text size",
					desc="Font size of the countdown text.",
					min=10,
					max=32,
					step=1,
					get = function()
						return SwedgeTimer.db.profile.seal_timer_size
					end,
					set = function(self, key)
						SwedgeTimer.db.profile.seal_timer_size = key
						if st.bar.set_seal_timer_text_properties then
							st.bar.set_seal_timer_text_properties()
						end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.seal_timer_enabled
					end
				},
				seal_timer_color = {
					order=24,
					type="color",
					name="Timer text color",
					desc="Color of the countdown text.",
					hasAlpha=false,
					get = function()
						local tab = SwedgeTimer.db.profile.seal_timer_color
						return tab[1], tab[2], tab[3], tab[4]
					end,
					set = function(self,r,g,b,a)
						SwedgeTimer.db.profile.seal_timer_color = {r,g,b,a or 1}
						if st.bar.set_seal_timer_text_properties then
							st.bar.set_seal_timer_text_properties()
						end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.seal_timer_enabled
					end
				},
			}
		},
		cooldown_hud = {
			order = 0.25,
			type = "group",
			name = "|cFF00FFFFCooldown HUD|r",
			handler = SwedgeTimer,
			args = {
				hud_desc = {
					order = 1,
					type = "description",
					width = "full",
					name = "A row of ability icons: Crusader Strike, Judgement, Consecration, Exorcism, "
						.. "your two trinkets and Avenging Wrath. Each shows its cooldown and remaining time, greys "
						.. "out while on cooldown (Judgement without a seal, Exorcism without an Undead or Demon "
						.. "target), and tints blue without mana and red when the target is out of range. Exorcism "
						.. "and Avenging Wrath glow when they are the right call. Trinkets show their proc, on-use "
						.. "cooldown and internal cooldown. Ported from Nullgodx's Paladin WeakAura (wago.io/CI7I0QRGO).\n",
				},
				hud_enabled = {
					order = 2, type = "toggle", name = "Enable Cooldown HUD",
					desc = "Show the cooldown HUD.",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.hud_enabled = key
						if st.hud and st.hud.apply_settings then st.hud.apply_settings() end
					end,
				},
				hud_visibility_key = {
					order = 3, type = "select", name = "Show HUD",
					desc = "When to show the HUD (Practice Mode always shows it).",
					values = { always = "Always show", in_combat = "In combat", in_combat_or_target = "In combat or with an enemy target" },
					sorting = { "always", "in_combat", "in_combat_or_target" },
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.hud_visibility_key = key
						if st.hud and st.hud.apply_settings then st.hud.apply_settings() end
					end,
					disabled = function() return not SwedgeTimer.db.profile.hud_enabled end,
				},
				hud_icons_header = { order = 10, type = "header", name = "Icons" },
				hud_show_cs = { order = 11, type = "toggle", name = "Crusader Strike", desc = "Show the Crusader Strike icon.", get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_show_cs = key; st.hud.apply_settings() end },
				hud_show_judgement = { order = 12, type = "toggle", name = "Judgement", desc = "Show the Judgement icon.", get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_show_judgement = key; st.hud.apply_settings() end },
				hud_show_consecration = { order = 13, type = "toggle", name = "Consecration", desc = "Show the Consecration icon.", get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_show_consecration = key; st.hud.apply_settings() end },
				hud_show_exorcism = { order = 14, type = "toggle", name = "Exorcism", desc = "Show the Exorcism icon.", get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_show_exorcism = key; st.hud.apply_settings() end },
				hud_show_wings = { order = 17, type = "toggle", name = "Avenging Wrath", desc = "Show the Avenging Wrath icon (glows in combat once it is ready).", get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_show_wings = key; st.hud.apply_settings() end },
				hud_show_trinket1 = { order = 15, type = "toggle", name = "Trinket 1", desc = "Show the top trinket slot (hidden while the slot is empty).", get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_show_trinket1 = key; st.hud.apply_settings() end },
				hud_show_trinket2 = { order = 16, type = "toggle", name = "Trinket 2", desc = "Show the bottom trinket slot (hidden while the slot is empty).", get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_show_trinket2 = key; st.hud.apply_settings() end },
				hud_layout_header = { order = 20, type = "header", name = "Layout" },
				hud_icon_size = { order = 21, type = "range", name = "Icon size", desc = "Size of each icon in pixels.", min = 16, max = 96, step = 1, get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_icon_size = key; st.hud.apply_settings() end,
					disabled = function() local p = SwedgeTimer.db.profile; return p.hud_match_bar_width and p.hud_orientation ~= "vertical" end },
				hud_match_bar_width = { order = 21.5, type = "toggle", name = "Match bar width",
					desc = "Make the row exactly as wide as the swing bar (outline included) and size the icons to fill it. Follows the bar's width and outline settings. Rows only.",
					get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_match_bar_width = key; st.hud.apply_settings() end,
					disabled = function() return SwedgeTimer.db.profile.hud_orientation == "vertical" end },
				hud_spacing = { order = 22, type = "range", name = "Spacing", desc = "Gap between icons in pixels.", min = 0, max = 30, step = 1, get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_spacing = key; st.hud.apply_settings() end },
				hud_orientation = { order = 23, type = "select", name = "Orientation", desc = "Lay the icons out in a row or a column.",
					values = { horizontal = "Row", vertical = "Column" }, sorting = { "horizontal", "vertical" }, get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_orientation = key; st.hud.apply_settings() end },
				hud_x = { order = 24, type = "range", name = "X offset", desc = "Horizontal offset from the screen centre. Design mode (/st design) drags it.", min = -2000, max = 2000, softMin = -800, softMax = 800, step = 1, get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_x = key; st.hud.apply_settings() end },
				hud_y = { order = 25, type = "range", name = "Y offset", desc = "Vertical offset from the screen centre. Design mode (/st design) drags it.", min = -2000, max = 2000, softMin = -600, softMax = 600, step = 1, get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_y = key; st.hud.apply_settings() end },
				hud_style_header = { order = 30, type = "header", name = "Style" },
				hud_show_text = { order = 31, type = "toggle", name = "Remaining time text", desc = "Show the remaining time on each icon (one decimal under 3 seconds, red under 3 seconds; hidden for the global cooldown).", get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_show_text = key; st.hud.apply_settings() end },
				hud_font = { order = 32, type = "select", name = "Text font", desc = "Font for the remaining time.", dialogControl = "LSM30_Font", values = SML:HashTable("font"),
					get = function() return SwedgeTimer.db.profile.hud_font or SML.DefaultMedia.font end,
					set = function(self, key) SwedgeTimer.db.profile.hud_font = key; st.hud.apply_settings() end,
					disabled = function() return not SwedgeTimer.db.profile.hud_show_text end },
				hud_text_size = { order = 33, type = "range", name = "Text size", desc = "Font size of the remaining time.", min = 8, max = 40, step = 1, get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_text_size = key; st.hud.apply_settings() end,
					disabled = function() return not SwedgeTimer.db.profile.hud_show_text end },
				hud_text_outline = { order = 34, type = "select", name = "Text outline", desc = "Outline style of the remaining time.", values = outlines, get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_text_outline = key; st.hud.apply_settings() end,
					disabled = function() return not SwedgeTimer.db.profile.hud_show_text end },
				hud_text_color = { order = 35, type = "color", name = "Text color", desc = "Colour of the remaining time.", hasAlpha = false,
					get = function() local t = SwedgeTimer.db.profile.hud_text_color; return t[1], t[2], t[3], t[4] end,
					set = function(self, r, g, b, a) SwedgeTimer.db.profile.hud_text_color = { r, g, b, a or 1 }; st.hud.apply_settings() end,
					disabled = function() return not SwedgeTimer.db.profile.hud_show_text end },
				hud_text_warn_color = { order = 36, type = "color", name = "Text color under 3 s", desc = "Colour of the remaining time in its last 3 seconds.", hasAlpha = false,
					get = function() local t = SwedgeTimer.db.profile.hud_text_warn_color; return t[1], t[2], t[3], t[4] end,
					set = function(self, r, g, b, a) SwedgeTimer.db.profile.hud_text_warn_color = { r, g, b, a or 1 }; st.hud.apply_settings() end,
					disabled = function() return not SwedgeTimer.db.profile.hud_show_text end },
				hud_border_size = { order = 37, type = "range", name = "Border size", desc = "Border thickness around each icon (0 = none).", min = 0, max = 6, step = 1, get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_border_size = key; st.hud.apply_settings() end },
				hud_border_color = { order = 38, type = "color", name = "Border color", desc = "Colour of the icon borders.", hasAlpha = true,
					get = function() local t = SwedgeTimer.db.profile.hud_border_color; return t[1], t[2], t[3], t[4] end,
					set = function(self, r, g, b, a) SwedgeTimer.db.profile.hud_border_color = { r, g, b, a or 1 }; st.hud.apply_settings() end },
				hud_cues_header = { order = 40, type = "header", name = "Cues" },
				hud_glow_enabled = { order = 41, type = "toggle", name = "Glow when it's the right call", desc = "Exorcism glows against an Undead or Demon target and Avenging Wrath once it is ready, both in combat and off cooldown. No other icon glows.", get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_glow_enabled = key; st.hud.apply_settings() end },
				hud_desaturate = { order = 42, type = "toggle", name = "Grey out on cooldown", desc = "Desaturate icons while on cooldown (Judgement also without a seal, Exorcism without a valid target).", get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_desaturate = key; st.hud.apply_settings() end },
				hud_mana_tint = { order = 43, type = "toggle", name = "Blue without mana", desc = "Tint an icon blue when you can't afford the ability.", get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_mana_tint = key; st.hud.apply_settings() end },
				hud_range_tint = { order = 44, type = "toggle", name = "Red out of range", desc = "Tint an icon red when the target is out of the ability's range.", get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.hud_range_tint = key; st.hud.apply_settings() end },
			},
		},
		rotation_label = {
			order = 0.26,
			type = "group",
			name = "|cFF00FFFFRotation Text|r",
			handler = SwedgeTimer,
			args = {
				rotation_label_desc = {
					order = 1, type = "description", width = "full",
					name = "A free-standing label with the twist rotation SwedgeTimer recommends for your "
						.. "current weapon speed and haste (\"2/3\", \"2/2/5\"...) - the same rotation the Next "
						.. "Action Guide and Practice Mode use. Place it anywhere with design mode (/st design).\n",
				},
				rotation_label_enabled = {
					order = 2, type = "toggle", name = "Show rotation text", desc = "Show the rotation label.",
					get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.rotation_label_enabled = key; st.rotation_text.apply_settings() end,
				},
				rotation_label_visibility_key = {
					order = 3, type = "select", name = "Show text",
					desc = "When to show the label (Practice Mode always shows it).",
					values = { always = "Always show", in_combat = "In combat" }, sorting = { "always", "in_combat" },
					get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.rotation_label_visibility_key = key; st.rotation_text.apply_settings() end,
					disabled = function() return not SwedgeTimer.db.profile.rotation_label_enabled end,
				},
				rotation_label_format = {
					order = 4, type = "select", name = "Format",
					desc = "What the label says: the rotation alone (2/3), with a prefix (Rotation: 2/3), its steps (CS, Twist, Twist), or both.",
					values = { key = "2/3", labelled = "Rotation: 2/3", steps = "CS, Twist, Twist", both = "2/3  -  CS, Twist, Twist" },
					sorting = { "key", "labelled", "steps", "both" },
					get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.rotation_label_format = key; st.rotation_text.dirty = true; st.rotation_text.apply_settings() end,
					disabled = function() return not SwedgeTimer.db.profile.rotation_label_enabled end,
				},
				rotation_label_align = {
					order = 5, type = "select", name = "Alignment",
					desc = "Which edge of the label stays put when the text changes length. Left and right sit flush against that edge of the label's box.",
					values = { left = "Left", center = "Center", right = "Right" }, sorting = { "left", "center", "right" },
					get = "GetValue",
					set = function(self, key) st.rotation_text.set_align(key) end,
					disabled = function() return not SwedgeTimer.db.profile.rotation_label_enabled end,
				},
				rotation_label_position_header = { order = 10, type = "header", name = "Position" },
				rotation_label_x = { order = 11, type = "range", name = "X offset", desc = "Horizontal offset of the label's anchor (its left, centre or right edge, per Alignment) from the screen centre. Design mode drags it.", min = -2000, max = 2000, softMin = -800, softMax = 800, step = 1, get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.rotation_label_x = key; st.rotation_text.apply_settings() end },
				rotation_label_y = { order = 12, type = "range", name = "Y offset", desc = "Vertical offset from the screen centre. Design mode drags it.", min = -2000, max = 2000, softMin = -600, softMax = 600, step = 1, get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.rotation_label_y = key; st.rotation_text.apply_settings() end },
				rotation_label_style_header = { order = 20, type = "header", name = "Style" },
				rotation_label_font = { order = 21, type = "select", name = "Font", desc = "Font of the label.", dialogControl = "LSM30_Font", values = SML:HashTable("font"),
					get = function() return SwedgeTimer.db.profile.rotation_label_font or SML.DefaultMedia.font end,
					set = function(self, key) SwedgeTimer.db.profile.rotation_label_font = key; st.rotation_text.dirty = true; st.rotation_text.apply_settings() end },
				rotation_label_size = { order = 22, type = "range", name = "Text size", desc = "Font size of the label.", min = 8, max = 48, step = 1, get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.rotation_label_size = key; st.rotation_text.dirty = true; st.rotation_text.apply_settings() end },
				rotation_label_outline = { order = 23, type = "select", name = "Outline", desc = "Outline style of the label.", values = outlines, get = "GetValue",
					set = function(self, key) SwedgeTimer.db.profile.rotation_label_outline = key; st.rotation_text.dirty = true; st.rotation_text.apply_settings() end },
				rotation_label_color = { order = 24, type = "color", name = "Color", desc = "Colour of the label.", hasAlpha = true,
					get = function() local t = SwedgeTimer.db.profile.rotation_label_color; return t[1], t[2], t[3], t[4] end,
					set = function(self, r, g, b, a) SwedgeTimer.db.profile.rotation_label_color = { r, g, b, a or 1 }; st.rotation_text.apply_settings() end },
			},
		},
		nextaction_guide = {
			order = 0.2,
			type = "group",
			name = "|cFF00FFFFNext Action Guide|r",
			handler = SwedgeTimer,
			args = {
				nextaction_header = {
					order = 1,
					type = "header",
					name = "Next Action Guide",
				},
				nextaction_desc = {
					order = 1.1,
					type = "description",
					width = "full",
					name = "Real-time recommendations for your next twist action: cast Seal of Command, "
						.. "cast Seal of Blood, twist now, or Crusader Strike — with HOLD, Judgement, and "
						.. "filler cues. Works in combat and in Practice Mode.\n"
						.. "Based on the \"Ret Next Action Guide\" WeakAura by Fonsas & Surveillant.\n",
				},
				nextaction_enabled = {
					order = 2,
					type = "toggle",
					name = "Enable Next Action Guide",
					desc = "Show the next action guide frame.",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.nextaction_enabled = key
						if st.nextaction and st.nextaction.apply_settings then
							st.nextaction.apply_settings()
						end
					end,
				},
				nextaction_locked = {
					order = 3,
					type = "toggle",
					name = "Lock frame",
					desc = "Lock the guide frame in place. While unlocked, the frame is always shown "
						.. "and can be dragged to reposition it.",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.nextaction_locked = key
						if st.nextaction and st.nextaction.apply_settings then
							st.nextaction.apply_settings()
						end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.nextaction_enabled
					end,
				},
				nextaction_visibility_key = {
					order = 4,
					type = "select",
					name = "Show guide",
					desc = "When to show the guide (Practice Mode always shows it).",
					values = {
						always = "Always show",
						in_combat = "In combat",
					},
					sorting = {"always", "in_combat"},
					get = "GetValue",
					set = "SetValue",
					disabled = function()
						return not SwedgeTimer.db.profile.nextaction_enabled
					end,
				},
				nextaction_zones_desc = {
					order = 4.05,
					type = "description",
					width = "full",
					name = "Only load the guide in the zone types ticked below (for example raids only, or "
						.. "everywhere except battlegrounds and arenas). Practice Mode and unlocking the "
						.. "guide for positioning always show it.",
				},
				nextaction_zone_world = {
					order = 4.1,
					type = "toggle",
					name = "Open world",
					desc = "Show the guide outside instances.",
					get = "GetValue",
					set = "SetValue",
					disabled = function() return not SwedgeTimer.db.profile.nextaction_enabled end,
				},
				nextaction_zone_party = {
					order = 4.2,
					type = "toggle",
					name = "Dungeons",
					desc = "Show the guide in 5-man dungeons.",
					get = "GetValue",
					set = "SetValue",
					disabled = function() return not SwedgeTimer.db.profile.nextaction_enabled end,
				},
				nextaction_zone_raid = {
					order = 4.3,
					type = "toggle",
					name = "Raids",
					desc = "Show the guide in raid instances.",
					get = "GetValue",
					set = "SetValue",
					disabled = function() return not SwedgeTimer.db.profile.nextaction_enabled end,
				},
				nextaction_zone_pvp = {
					order = 4.4,
					type = "toggle",
					name = "Battlegrounds",
					desc = "Show the guide in battlegrounds.",
					get = "GetValue",
					set = "SetValue",
					disabled = function() return not SwedgeTimer.db.profile.nextaction_enabled end,
				},
				nextaction_zone_arena = {
					order = 4.5,
					type = "toggle",
					name = "Arenas",
					desc = "Show the guide in arenas.",
					get = "GetValue",
					set = "SetValue",
					disabled = function() return not SwedgeTimer.db.profile.nextaction_enabled end,
				},
				nextaction_icon_size = {
					order = 5,
					type = "range",
					name = "Icon size",
					desc = "Size of the action icon in pixels.",
					min = 20, max = 80, step = 1,
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.nextaction_icon_size = key
						if st.nextaction and st.nextaction.apply_settings then
							st.nextaction.apply_settings()
						end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.nextaction_enabled
					end,
				},
				nextaction_position_header = {
					order = 10,
					type = "header",
					name = "Position",
				},
				nextaction_x = {
					order = 11,
					type = "input",
					name = "X position",
					desc = "Horizontal offset from the center of the screen.",
					get = function()
						return tostring(SwedgeTimer.db.profile.nextaction_x)
					end,
					set = function(self, input)
						SwedgeTimer.db.profile.nextaction_x = tonumber(input) or 0
						if st.nextaction and st.nextaction.apply_settings then
							st.nextaction.apply_settings()
						end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.nextaction_enabled
					end,
				},
				nextaction_y = {
					order = 12,
					type = "input",
					name = "Y position",
					desc = "Vertical offset from the center of the screen.",
					get = function()
						return tostring(SwedgeTimer.db.profile.nextaction_y)
					end,
					set = function(self, input)
						SwedgeTimer.db.profile.nextaction_y = tonumber(input) or 0
						if st.nextaction and st.nextaction.apply_settings then
							st.nextaction.apply_settings()
						end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.nextaction_enabled
					end,
				},
				nextaction_timing_header = {
					order = 20,
					type = "header",
					name = "Timing",
				},
				nextaction_reaction_time_ms = {
					order = 21,
					type = "range",
					name = "Reaction time (ms)",
					desc = "Your reaction time (NOT ping). Recommendations are shifted earlier to "
						.. "compensate for it.",
					min = 0, max = 350, step = 10,
					get = "GetValue",
					set = "SetValue",
					disabled = function()
						return not SwedgeTimer.db.profile.nextaction_enabled
					end,
				},
				nextaction_cs_max_delay_ms = {
					order = 22,
					type = "range",
					name = "Crusader Strike max delay (ms)",
					desc = "Maximum time Crusader Strike may be delayed for seal twisting before the "
						.. "guide prioritises casting it.",
					min = 0, max = 3000, step = 50,
					get = "GetValue",
					set = "SetValue",
					disabled = function()
						return not SwedgeTimer.db.profile.nextaction_enabled
					end,
				},
				nextaction_display_header = {
					order = 30,
					type = "header",
					name = "Display",
				},
				nextaction_hold_enabled = {
					order = 31,
					type = "toggle",
					name = "Show HOLD overlay",
					desc = "Cover the action icon with the dark HOLD circle when you should wait before "
						.. "pressing anything.",
					get = "GetValue",
					set = "SetValue",
					disabled = function()
						return not SwedgeTimer.db.profile.nextaction_enabled
					end,
				},
				nextaction_show_rotation_text = {
					order = 32,
					type = "toggle",
					name = "Show rotation text",
					desc = "Show the recommended twist rotation (e.g. 2/3) below the action icon.",
					get = "GetValue",
					set = "SetValue",
					disabled = function()
						return not SwedgeTimer.db.profile.nextaction_enabled
					end,
				},
				nextaction_show_label = {
					order = 32.5,
					type = "toggle",
					name = "Show \"Next action:\" label",
					desc = "Show the small \"Next action:\" text above the action icon.",
					get = "GetValue",
					set = function(self, key)
						SwedgeTimer.db.profile.nextaction_show_label = key
						if st.nextaction and st.nextaction.apply_settings then st.nextaction.apply_settings() end
					end,
					disabled = function()
						return not SwedgeTimer.db.profile.nextaction_enabled
					end,
				},
				nextaction_show_judgement = {
					order = 33,
					type = "toggle",
					name = "Show Judgement cue",
					desc = "Show a small Judgement icon when you should judge your Seal of Blood before "
						.. "twisting back to Command.",
					get = "GetValue",
					set = "SetValue",
					disabled = function()
						return not SwedgeTimer.db.profile.nextaction_enabled
					end,
				},
				nextaction_show_fillers = {
					order = 34,
					type = "toggle",
					name = "Show filler suggestions",
					desc = "Suggest Consecration (or Exorcism against Undead/Demons) when there is room "
						.. "in the rotation and you have mana to spare.",
					get = "GetValue",
					set = "SetValue",
					disabled = function()
						return not SwedgeTimer.db.profile.nextaction_enabled
					end,
				},
				nextaction_filler_mana_consecration = {
					order = 35,
					type = "range",
					name = "Consecration mana threshold (%)",
					desc = "Only suggest Consecration when your mana is above this percentage.",
					min = 0, max = 100, step = 1,
					get = "GetValue",
					set = "SetValue",
					disabled = function()
						return not (SwedgeTimer.db.profile.nextaction_enabled
							and SwedgeTimer.db.profile.nextaction_show_fillers)
					end,
				},
				nextaction_filler_mana_exorcism = {
					order = 36,
					type = "range",
					name = "Exorcism mana threshold (%)",
					desc = "Only suggest Exorcism when your mana is above this percentage.",
					min = 0, max = 100, step = 1,
					get = "GetValue",
					set = "SetValue",
					disabled = function()
						return not (SwedgeTimer.db.profile.nextaction_enabled
							and SwedgeTimer.db.profile.nextaction_show_fillers)
					end,
				},
			}
		},
		import_export = {
			order = 100,
			type = "group",
			name = "Import/Export",
			args = {
				-- EXPORT SECTION
				export_header = {
					order = 1,
					type = "header",
					name = "Export Settings",
				},
				export_desc = {
					order = 2,
					type = "description",
					name = "Generate a string that holds every setting on every page - bar, icons, guide, HUD, "
						.. "effects, text, practice - to share with other players or move between characters. "
						.. "Positions, sounds and Practice Mode keybinds only travel when their switch is on.\n",
				},
				include_positions = {
					order = 3,
					type = "toggle",
					name = "Include position settings",
					desc = "Include bar/icon X, Y offsets and anchor points in export.",
					get = function() return st.import_export.include_positions end,
					set = function(_, val) st.import_export.include_positions = val end,
				},
				include_sounds = {
					order = 3.5,
					type = "toggle",
					name = "Include sound settings",
					desc = "Include twist window sound and success feedback sound settings in export.",
					get = function() return st.import_export.include_sounds end,
					set = function(_, val) st.import_export.include_sounds = val end,
				},
				include_practice_keys = {
					order = 3.6,
					type = "toggle",
					name = "Include Practice Mode keybinds",
					desc = "Include the keys Practice Mode listens for. Off by default so a shared layout never changes someone's keys.",
					get = function() return st.import_export.include_practice_keys end,
					set = function(_, val) st.import_export.include_practice_keys = val end,
				},
				generate_export = {
					order = 4,
					type = "execute",
					name = "Generate Export String",
					func = function()
						local str, err = st.import_export.export_settings(st.import_export.include_positions,
							st.import_export.include_sounds, st.import_export.include_practice_keys)
						local msg
						if str then
							st.import_export.export_string = str
							msg = "Export string generated (" .. tostring(err) .. " settings). Select it all and copy."
						else
							st.import_export.export_string = ""
							msg = "Error: " .. (err or "Unknown")
						end
						st.import_export.status_message = msg
						-- Show in dialog status bar (bottom of settings window)
						local ACD = LibStub("AceConfigDialog-3.0")
						local frame = ACD.OpenFrames["SwedgeTimer_Options"]
						if frame and frame.SetStatusText then
							frame:SetStatusText(msg)
						end
					end,
				},
				export_string_display = {
					order = 5,
					type = "input",
					name = "Export String (select all and Ctrl+C to copy)",
					desc = "Select all text (Ctrl+A) and copy (Ctrl+C) to share your settings.",
					multiline = 4,
					width = "full",
					get = function() return st.import_export.export_string or "" end,
					set = function() end,  -- Read-only
				},

				-- IMPORT SECTION
				import_header = {
					order = 10,
					type = "header",
					name = "Import Settings",
				},
				import_desc = {
					order = 11,
					type = "description",
					name = "Paste an export string here and press Import. Strings from older SwedgeTimer versions "
						.. "still work. Everything the string holds replaces your current profile's values; settings "
						.. "it does not mention are left alone.\n",
				},
				import_string_input = {
					order = 12,
					type = "input",
					name = "Import String",
					desc = "Paste the export string here.",
					multiline = 4,
					width = "full",
					get = function() return st.import_export.import_string or "" end,
					set = function(_, val) st.import_export.import_string = val end,
				},
				do_import = {
					order = 13,
					type = "execute",
					name = "Import Settings",
					func = function()
						local success, msg = st.import_export.import_settings(st.import_export.import_string)
						st.import_export.status_message = msg
						-- Print to chat for user feedback
						st.utils.print_msg(msg)
						-- Show in dialog status bar (bottom of settings window)
						local ACD = LibStub("AceConfigDialog-3.0")
						local frame = ACD.OpenFrames["SwedgeTimer_Options"]
						if frame and frame.SetStatusText then
							frame:SetStatusText(msg)
						end
						if success then
							st.import_export.import_string = ""  -- Clear on success
						end
						-- Force panel refresh to show status message after UI refresh
						LibStub("AceConfigRegistry-3.0"):NotifyChange("SwedgeTimer")
					end,
					disabled = function() return not st.import_export.import_string or st.import_export.import_string == "" end,
				},

				-- STATUS
				status_header = {
					order = 20,
					type = "header",
					name = "",
				},
				status_message_display = {
					order = 21,
					type = "description",
					name = function() return st.import_export.status_message or "" end,
				},
			},
		},
	}
}

-- -- https://www.wowace.com/projects/ace3/pages/ace-config-3-0-options-tables#title-4-1
function SwedgeTimer:GetValue(info)
    -- print(info)
	return self.db.profile[info[#info]]
end

function SwedgeTimer:SetValue(info, value)
	self.db.profile[info[#info]] = value
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed core.lua module correctly') end
