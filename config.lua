------------------------------------------------------------------------------------
-- Module to contain config default
------------------------------------------------------------------------------------
local addon_name, st = ...
-- No LSM/LWIN fetch here: defaults are plain media-key strings and positions; the
-- only LSM/LWIN handles live in option_table_presets.lua / option_tables.lua and
-- bars.lua, which resolve them at runtime.
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
-- local print = st.utils.print_msg

---@class AceAddon
---@field defaults? table
local _ST = ST
---@type AceAddon
ST = _ST

------------------------------------------------------------------------------------
-- Default settings for the addon.
ST.defaults = {

	profile = {

		-- Top level
		welcome_message = true,
		enabled = true, -- top level control

		-- Per-tick budget counters (diag.lua). Off by default; true enables the counting
		-- wrappers for /st diag at the next login or reload (the off path installs the
		-- original OnUpdate handlers untouched).
		diag_tick_counters = false,

		-- Enemy swing bar (enemy_swing.lua). Off by default; the top-level toggle arms
		-- the hostile-target swing bar on the classic-line families (inert elsewhere).
		enemy_swing_enabled = false,

		-- Practice progression + stats (practice_progress.lua / practice_stats.lua).
		-- The default shape of the saved blob: a fresh profile starts from a valid,
		-- fully-shaped practice state instead of an absent one. The table is the
		-- AceDB DEFAULT - it is never mutated: the hook (practice_ui.lua) REPLACES
		-- the profile key with the repaired blob
		-- (db.profile.practice = st.practice_progress.migrate(db.profile.practice)).
		practice = ST.PRACTICE_DEFAULTS,

		-- Frame strata/draw level
		frame_strata = "MEDIUM",
		draw_level = 10,

		-- Bar visual behaviour
		bar_full_delay = 0.05,

		-- Latency scale factors.
		latency_linear_offset = 0.0,
		latency_scale_factor = 1.0,

		-- GCD marker offsets
		gcd_marker_offset_mode = "None",
		gcd_marker_offset_scale_factor = 1.0,
		gcd_marker_fixed_offset = 50,

		-- Deadzone
		deadzone_scale_factor = 1.1,

		-- Class-specific defaults
		['**'] = ST.class_defaults,
		DEATHKNIGHT = ST.DEATHKNIGHT.defaults,
		DRUID = ST.DRUID.defaults,
		HUNTER = ST.HUNTER.defaults,
		MAGE = ST.MAGE.defaults,
		PALADIN = ST.PALADIN.defaults,
		PRIEST = ST.PRIEST.defaults,
		ROGUE = ST.ROGUE.defaults,
		SHAMAN = ST.SHAMAN.defaults,
		WARLOCK = ST.WARLOCK.defaults,
		WARRIOR = ST.WARRIOR.defaults,
	},

}

--=========================================================================================
-- One-time appearance migration: opaque bar backdrop
--=========================================================================================
-- Operator order 2026-10-25: "make the background alpha high so its not fully see
-- through" - the BACKDROP only. The coloured progress fill (bar_color_default), the
-- border (border_color) and the HUD background are not touched by this migration.
--
-- ST.bar_defaults.background_color moved from {0,0,0,0.85} to {0,0,0,1.0}
-- (config_presets.lua). AceDB only fills keys that are ABSENT, so every profile that
-- logged in before this build keeps its saved 0.85 forever unless it is migrated.
--
-- WHAT MAY BE RAISED: only the exact old default {0, 0, 0, 0.85}. Any other value is a
-- user pick or a theme preset (ST.THEME_PRESETS ships 0.90 / 0.65 / 0.95 / 0.85 alpha
-- with non-black RGB) and is left exactly as saved. A hand whose ACTIVE theme preset
-- owns the stored colour is skipped too: "Classic Retro" ships exactly
-- {0,0,0,0.85} (config_presets.lua), and applying it stores that colour plus
-- theme_preset = "classic" (option_tables.lua:1326-1329) - that is a preset choice, not
-- an untouched default.
--
-- STORED SHAPE (verified, not assumed): AceDB's copyDefaults
-- (Libs/AceDB-3.0/AceDB-3.0.lua:88-131) rawsets a NEW table for every default table and
-- copies the leaves in, so an untouched profile holds a plain 4-element array
-- {0, 0, 0, 0.85} and the defaults table is never aliased into the profile (:117-124).
-- Black reads the same in both storage conventions: this key ships 0-1 floats, while the
-- colour setter stores 0-255 (option_tables.lua:1364-1368), and 0 == 0.0. That is what
-- makes the exact-match test safe; it also bounds it.
--
-- RESIDUAL (accepted, stated on bench/appearance_options_2026-10-25.md): a user who
-- deliberately picked pure black at 0.85 alpha through the colour picker is
-- byte-identical to an untouched default, and a "Classic Retro" preset the user then
-- switched to Custom leaves {0,0,0,0.85} with theme_preset = nil. Both take the opaque
-- default. There is no saved signal that distinguishes them (no per-key
-- touched-tracking exists), so the alternative would be to migrate nothing.
--
-- WHEN: ST:set_opts() (option_tables.lua) calls this once, before any widget can read a
-- colour (the getters read lazily at panel render). main.lua creates AceDB and then calls
-- set_opts() (main.lua:416-424), and the bars are built later in init_libs, so that is the
-- first settings-aware seam on the init path. Idempotent: the profile flag makes a second
-- call a no-op - and the flag is READ WITH rawget (see the function), because a plain read
-- of an absent profile key is a WRITE on a real AceDB profile.
ST.APPEARANCE_DEFAULTS_MIGRATION_FLAG = "appearance_defaults_213"

-- The exact old default this migration may raise. A future default move adds its own
-- step (and its own flag) next to this one rather than editing this value.
ST.APPEARANCE_OLD_BACKGROUND_COLOR = { 0.0, 0.0, 0.0, 0.85 }

-- The class rows a profile can carry: the same ten tokens ST.defaults.profile lists
-- above. Literal on purpose - a class row is only descended into when the token is a
-- class the addon ships.
local APPEARANCE_CLASS_TOKENS = {
	"DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN",
	"PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

-- Exact 4-element colour equality. Non-tables never match, so a corrupt saved colour is
-- skipped instead of indexed.
local function colors_equal(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

-- Is the stored backdrop owned by the hand's ACTIVE theme preset? Only then is it a
-- preset choice rather than the old default (the one collision is "Classic Retro").
local function preset_owns_background_color(hand)
	local presets = ST.THEME_PRESETS
	local key = hand.theme_preset
	if type(presets) ~= "table" or type(key) ~= "string" then
		return false
	end
	local preset = presets[key]
	return type(preset) == "table"
		and colors_equal(hand.background_color, preset.background_color)
end

-- Raises ONLY the untouched old default on every hand of every class row, then marks the
-- profile. Returns the number of hand colours it changed (0 on a second run). Nil-safe
-- by construction: a nil profile, a corrupt class row, a non-table hand or a non-table
-- colour is skipped, never thrown on - this runs on the login path.
--
-- THE FLAG IS READ WITH rawget, NOT A PLAIN INDEX. The live profile root is an AceDB table
-- carrying the '**' defaults metatable (ST.defaults.profile['**'] = ST.class_defaults;
-- Libs/AceDB-3.0/AceDB-3.0.lua:88-107): its __index CREATES a defaults-filled table, rawsets
-- it on the profile and returns it. A plain read is therefore truthy on the very FIRST
-- login and rawsets junk - which is exactly how the 2026-10-25 order (0.85 -> 1.0 backdrop)
-- silently never reached a single saved profile: this function returned 0 forever. rawget
-- reads only what was actually saved.
--
-- ONLY THE PLAIN BOOLEAN THIS FUNCTION WRITES COUNTS AS DONE. A table at the key is not a
-- run marker: it is what the defective read created, and the defective code returned 0
-- before it could ever reach its own write. Accepting any truthy value would leave every
-- profile that logged in with that build at 0.85 forever - the same silent failure in a new
-- shape - so a table (or any non-true value) runs the migration, then is replaced by `true`.
function ST.migrate_appearance_defaults(profile)
	if type(profile) ~= "table" then
		return 0
	end
	if rawget(profile, ST.APPEARANCE_DEFAULTS_MIGRATION_FLAG) == true then
		return 0
	end
	local old = ST.APPEARANCE_OLD_BACKGROUND_COLOR
	local raised = 0
	for _, token in ipairs(APPEARANCE_CLASS_TOKENS) do
		-- rawget for the same reason: a class row the profile does not carry must stay
		-- absent (AceDB fills the shipped rows itself); a plain read would create one.
		local class_db = rawget(profile, token)
		if type(class_db) == "table" then
			for _, hand in pairs(class_db) do
				-- A hand table carries no '**' metatable of its own (bar_defaults has no
				-- '*'/'**' entry, so AceDB only copies leaves into it), which is why the
				-- leaf reads here stay plain - they cannot create anything.
				if type(hand) == "table"
					and colors_equal(hand.background_color, old)
					and not preset_owns_background_color(hand) then
					hand.background_color = { 0.0, 0.0, 0.0, 1.0 }
					raised = raised + 1
				end
			end
		end
	end
	-- rawset: the marker is this function's own plain value, never a metatable write path.
	rawset(profile, ST.APPEARANCE_DEFAULTS_MIGRATION_FLAG, true)
	return raised
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then st.utils.print_msg('-- Parsed config.lua module correctly') end
