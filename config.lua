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
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then st.utils.print_msg('-- Parsed config.lua module correctly') end
