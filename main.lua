--=========================================================================================
-- Main module for SwedgeTimer
--=========================================================================================
local addon_name, st = ...
local version = "2.1.1"
-- local version = "2.0"
local ST = LibStub("AceAddon-3.0"):NewAddon(addon_name, "AceConsole-3.0", "AceEvent-3.0")
-- Exposed for the diagnostic report (diag.lua); keep in sync with the ## Version
-- header in every toc.
ST.addon_version = version
local LSM = LibStub("LibSharedMedia-3.0")
local STL = LibStub("LibClassicSwingTimerAPI", true)
-- The swing library is only shipped on clients with a classic combat log (see the
-- flavor TOCs). WoW Forever has no classic combat log but exposes PLAYER_SWING, so
-- swing_source.lua provides a compatible engine there; Retail keeps the whole
-- initialisation flow intact with an inert stand-in, and the user is told in
-- init_libs. The same stand-in replaces an engine that loads but never reports
-- itself ready (see the init deadline in OnInitialize).
local function make_swing_stub()
	return {
		RegisterCallback = function(...) end,
		UnregisterCallback = function(...) end,
		-- Unknown (no engine), never a plausible 1 s cycle: the old fake shape made a
		-- dead engine indistinguishable from a live idle swing. init_timers turns the
		-- nil shape into the per-hand engine_dead state the bars render (H1).
		SwingTimerInfo = function(...)
			return nil, nil, nil
		end,
	}
end
-- The vendored library always wins when it is present (the classic client line);
-- st.swing_source only reports itself available on the FOREVER family.
-- ST.swing_engine records which of the three modes is live, for the diagnostic report.
local SWING_ENGINE_AVAILABLE = STL ~= nil
if SWING_ENGINE_AVAILABLE then
	ST.swing_engine = "vendored-lib"
elseif st.swing_source and st.swing_source.available then
	STL = st.swing_source
	SWING_ENGINE_AVAILABLE = true
	ST.swing_engine = "forever-source"
else
	STL = make_swing_stub()
	ST.swing_engine = "inert-standin"
end
local LRC = LibStub("LibRangeCheck-2.0")
local LLM = LibStub("LibLatencyMonitor")
local LGC = LibStub("LibGlobalCooldown")
local LWIN = LibStub("LibWindow-1.1")

-- Chat output policy: st.utils.print_msg (utils.lua) is the addon's single chat path
-- for module messages, and ST:Print (AceConsole) is its second, established one - both
-- are named explicitly below. There is deliberately no local alias for the client's raw
-- global print here: a bare call to it would bypass both, so the identifier is kept
-- out of the file on purpose.
-- Cross-client API wrappers (see compat.lua).
local api = st.api

ST.DEATHKNIGHT = {}
ST.DEMONHUNTER = {}
ST.DRUID = {}
ST.EVOKER = {}
ST.HUNTER = {}
ST.MAGE = {}
ST.MONK = {}
ST.PALADIN = {}
ST.PRIEST = {}
ST.ROGUE = {}
ST.SHAMAN = {}
ST.WARLOCK = {}
ST.WARRIOR = {}

--=========================================================================================
-- Funcs/iterables to automate common tasks
--=========================================================================================
local SwingTimerInfo = function(hand)
    return STL:SwingTimerInfo(hand)
end

-- Lua 5.1 has no table.pack (pinned by tests/main_init_state.lua and the
-- enemy_swing.lua header note): this shim provides it for 5.1 clients.
function table.pack(...)
	return { n = select("#", ...), ... }
end

ST.interfaces_are_initialised = false

-- keyword-accessible tables to handle case-switching
ST.mainhand = {}
ST.offhand = {}
ST.ranged = {}

ST.class_hands = {
	DEATHKNIGHT = {"mainhand", "offhand"},
	DRUID = {"mainhand"},
	HUNTER = {"mainhand", "offhand", "ranged"},
	MAGE = {"mainhand", "ranged"},
	PALADIN = {"mainhand"},
	PRIEST = {"mainhand", "ranged"},
	ROGUE = {"mainhand", "offhand", "ranged"},
	SHAMAN = {"mainhand", "offhand"},
	WARLOCK = {"mainhand", "ranged"},
	WARRIOR = {"mainhand", "offhand", "ranged"},
}

-- Hands for the player's class. `class_hands` is keyed by the uppercase class token
-- (UnitClass's second return); a lowercase spelling is tolerated defensively, because a
-- legacy option-table definition used to clobber this table with lowercase keys - which
-- made iter_hands() index nil during OnInitialize and aborted the rest of init at login.
function ST:get_class_hands()
	local hands = self.class_hands[self.player_class]
	if hands == nil and type(self.player_class) == "string" then
		hands = self.class_hands[string.upper(self.player_class)]
	end
	return hands or {}
end

function ST:iter_hands()
	-- Iterates over melee/ranged/offhand
	local i = 0
	local hands = self:get_class_hands()
	local n = #hands
	return function ()
		i = i + 1
		if i <= n then
			return hands[i]
		end
		return nil
	end
end

-- True when the player's class has a bar for that hand. The class hands list is the
-- same authority iter_hands() uses (init_timers builds exactly one bar per entry),
-- so a class without that hand never reaches a hand-specific frame call. F2: a
-- paladin or a druid has an offhand weapon but no offhand bar, so a hand-specific
-- call for them would touch frames that were never created.
function ST:has_hand(hand)
	local hands = self:get_class_hands()
	for i = 1, #hands do
		if hands[i] == hand then
			return true
		end
	end
	return false
end

function ST:generic_iter(array)
	local i = 0
	local n = #array
	return function()
		i = i + 1
		if i <= n then
			return array[i]
		end
	end
end

function ST:is_value_in_array(value, array)
	for _, v in pairs(array) do
		if v == value then
			return true
		end
	end
	return false
end

function ST:convert_color(t, new_alpha)
	-- Convert standard 0-255 colors down to WoW 0-1 ranges.
	local r,g,b,a = unpack(t)
	a = new_alpha or a
	r = r/255
	g = g/255
	b = b/255
	return r, g, b, a
end

function ST:convert_color_up(t, new_alpha)
	-- Convert WoW 0-1 ranges up to standard 0-255 ranges.
	local r,g,b,a = unpack(t)
	a = new_alpha or a
	r = r * 255
	g = g * 255
	b = b * 255
	return r, g, b, a
end

function ST:get_anchor_frame(hand)
	-- Gets the main anchor frame for the hand.
	return self[hand].anchor_frame
end

function ST:get_hiding_anchor_frame(hand)
	-- Get the hiding anchor frame, which also gets calls to show/hide.
	return self:get_anchor_frame(hand).hiding_anchor_frame
end

function ST:get_bar_frame(hand)
	-- Gets the bar frame for the hand.
	-- This is the frame with the backdrop, but *not* the frame
	-- with the bar visuals - that's a child of this one.
	return self:get_anchor_frame(hand).bar_frame
end

function ST:get_visuals_frame(hand)
	return self:get_bar_frame(hand).visuals_frame
end

function ST:get_profile_table()
	return self.db.profile
end

function ST:get_class_table()
	return self.db.profile[self.player_class]
end

function ST:get_hand_table(hand)
	return self.db.profile[self.player_class][hand]
end

function ST:get_in_range(hand)
	if hand == "ranged" then return self.in_ranged_range else return self.in_melee_range end
end

function ST:hide_bar(hand)
	-- Twist Practice owns the mainhand bar while its session runs: the simulated swing
	-- must stay visible even though the range-finder loop (set_bar_visibilities every
	-- 0.05 s) re-applies the user's show conditions. Every other hand keeps them.
	if hand == "mainhand" and st.practice_ui and st.practice_ui.is_active() then
		return
	end
	self:get_bar_frame(hand):Hide()
	self:get_hiding_anchor_frame(hand):Hide()
end

function ST:check_bar_enable_settings(db_class, hand)
	-- Function to check if the settings indicate the bar should be shown or hidden.
	-- Twist Practice owns the mainhand bar while its session runs (archive parity: the
	-- archived build's should_show_bar hook forced it visible): the simulated swing
	-- must show regardless of the user's enable/spec gating.
	if hand == "mainhand" and st.practice_ui and st.practice_ui.is_active() then
		return true
	end
	if not db_class.class_enabled then 	-- Global enable/disable
		return false
	end
	if not self:bar_is_enabled(hand) then 	-- Hand enabled
		return false
	end
	if self.current_talent_group == 1 then  -- Spec 1 enabled
		if not db_class.enable_spec1 then
			return false
		end
	end
	if self.current_talent_group == 2 then  -- Spec 1 enabled
		if not db_class.enable_spec2 then
			return false
		end
	end
	return true 	-- If we get to the end the bar should be shown.
end

function ST:show_bar(hand)
	local db_class = self:get_class_table()
	if self:check_bar_enable_settings(db_class, hand) then
		if self.player_class == "DRUID" then
			if self.should_show_bar_this_form then
				self:get_bar_frame(hand):Show()
				self:get_hiding_anchor_frame(hand):Show()
			else
				self:hide_bar(hand)
			end
		elseif self.player_class == "WARRIOR" then
			if db_class.hide_in_tank_spec and self.has_imp_def_stance then
				self:hide_bar(hand)
			elseif db_class.hide_in_arms_spec and self.has_bladestorm then
				self:hide_bar(hand)
			else
				self:get_bar_frame(hand):Show()
				self:get_hiding_anchor_frame(hand):Show()
			end
		else
			self:get_bar_frame(hand):Show()
			self:get_hiding_anchor_frame(hand):Show()
		end
	else
		self:hide_bar(hand)
	end
end

function ST:lock_frames()
	for hand in self:iter_hands() do
		local f = self:get_anchor_frame(hand)
		f:SetMovable(false)
		f:EnableMouse(false)
		f:SetScript("OnMouseWheel", nil)
	end
end

function ST:unlock_frames()
	for hand in self:iter_hands() do
		local f = self:get_anchor_frame(hand)
		f:SetMovable(true)
		f:EnableMouse(true)
		f:SetScript("OnMouseWheel", function(_, dir)
				LWIN.OnMouseWheel(f, dir)
				local ACR = LibStub("AceConfigRegistry-3.0")
				ACR:NotifyChange(ST.options_table_name)
			end
		)
	end
end


--=========================================================================================
-- Funcs to initialise the addon
--=========================================================================================
function ST:OnInitialize()

	-- Get player class first
	self.player_class_pretty, self.player_class = UnitClass("player")

	-- Register our media
	LSM:Register(
		"border", "Square Full White", [[Interface\BUTTONS\WHITE8X8]]
	)
	LSM:Register(
		"font", "Expressway", [[Interface\Addons\SwedgeTimer\Media\Fonts\Expressway.ttf]]
	)
	LSM:Register(
		"statusbar", "Minimalist", [[Interface\Addons\SwedgeTimer\Media\Textures\Minimalist.tga]]
	)
	-- The operator's texture, shipped as the DEFAULT status-bar texture for the
	-- addon's progress bars (operator order, 2026-10-20 - that order IS the gate
	-- for the default-visible change). It is registered in the "statusbar"
	-- registry, so it appears in the EXISTING texture dropdowns
	-- (option_table_presets.lua, values = LSM:HashTable("statusbar")) with no new
	-- widget. "Minimalist" stays registered as the shipped fallback key bars.lua
	-- degrades to when a texture fetch comes back nil.
	LSM:Register(
		"statusbar", "Wglass", [[Interface\Addons\SwedgeTimer\Media\StatusBar\Wglass.tga]]
	)

	-- Addon database
	local SwedgeTimerDB = LibStub("AceDB-3.0"):New(addon_name.."DB", self.defaults, true)
	self.db = SwedgeTimerDB

	-----------------------------------------------------------
	-- Dynamically construct the options tables
	-----------------------------------------------------------
	local AC = LibStub("AceConfig-3.0")
	local ACD = LibStub("AceConfigDialog-3.0")
	self:set_opts()

	self.options_table_name = addon_name.."_Options"
	AC:RegisterOptionsTable(self.options_table_name, self.opts_table)
	self.optionsFrame = ACD:AddToBlizOptions(self.options_table_name, addon_name)

	-- Profile options
	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	AC:RegisterOptionsTable(addon_name.."_Profiles", profiles)
	ACD:AddToBlizOptions(addon_name.."_Profiles", "Profiles", addon_name)

	-----------------------------------------------------------
	-- Callbackhandlers for letting the addon know that dependent
	-- libraries have their interfaces enabled.
	-----------------------------------------------------------
	-- Init our lib interfaces only once the range and swing timer
	-- libs are both loaded, as they are interdependent
	-- init_libs has a check to ensure this only happens once per reload
	self.lrc_ready = false
	self.lrc_unavailable = false -- set by the init deadline if LRC never reports ready
	self.stl_ready = not SWING_ENGINE_AVAILABLE -- inert stand-in counts as ready
	self.llm_ready = false
	LRC.RegisterCallback(self, LRC.CHECKERS_CHANGED, function()
			self.lrc_ready = true
			-- A late report means the init deadline was wrong about LibRangeCheck:
			-- clear the fallback flag so /st diag stops reporting lrc=fallback.
			-- Range state does not depend on it (exact yards, api.UnitDistance).
			self.lrc_unavailable = false
			self:init_libs()
		end
	)
	STL.RegisterCallback(self, "SWING_TIMER_INFO_INITIALIZED", function()
			self.stl_ready = true
			self:init_libs()
		end
	)

	-- A library that never reports ready (an incompatible client, or an error
	-- inside its own initialisation) must not stall init_libs forever: after a
	-- grace period, initialise anyway, with the missing library disabled for
	-- this session. Range state does not depend on LibRangeCheck any more; the flag
	-- only feeds /st diag's lrc= line, and a late report clears it (callback above).
	C_Timer.After(5, function()
			if self.interfaces_are_initialised then
				return
			end
			-- Recorded for the diagnostic report: a library never reported ready in
			-- time, so this deadline had to finish the initialisation.
			self.init_deadline_fired = true
			if not self.lrc_ready then
				self.lrc_unavailable = true
				self.lrc_ready = true
			end
			if not self.stl_ready then
				STL = make_swing_stub()
				SWING_ENGINE_AVAILABLE = false
				ST.swing_engine = "inert-standin"
				self.stl_ready = true
			end
			self:init_libs()
		end
	)

	-----------------------------------------------------------
	-- Callbackhandlers that are less sensitive to load orders.
	-----------------------------------------------------------
	-- LibLatencyMonitor
	LLM.RegisterCallback(self, LLM.LATENCY_CHANGED, self.callback_event_handler)

	-- LibGlobalCooldown
	LGC.RegisterCallback(self, LGC.GCD_STARTED, self.callback_event_handler)
	LGC.RegisterCallback(self, LGC.GCD_OVER, self.callback_event_handler)
	LGC.RegisterCallback(self, LGC.GCD_DURATIONS_UPDATED, self.callback_event_handler)

	-----------------------------------------------------------
	-- The set of containers and frames used in the addon.
	-- Even though many are nilled, this collates them so
	-- we have a reference to each container visually
	-- in the code.
	-----------------------------------------------------------
	-- Character info containers
	self.player_guid = UnitGUID("player")
	-- F2: the pre-probe default only. check_weapons derives the real value from the
	-- offhand-presence probe - the PLAYER_TARGET_SET_ATTACKING guard reads it, so it
	-- must never stay at this initial value.
	self.has_oh = false
	self.has_ranged = false
	self.mh_timer = 0
	self.oh_timer = 0
	self.ranged_timer = 0

	-- Character state containers
	self.in_combat = false
	-- Fight clock for totem-maintain gates (shaman Searing): api.get_time() of
	-- the last combat-enter; nil outside combat or when the clock did not
	-- answer (readers stay nil-safe and never prompt on a guess).
	self.fight_start_at = nil
	-- The live pull clock (BS-8 item 2 / P-17): the absolute timestamp of the
	-- expected pull, in the api.get_time() domain. nil = unknown (never a
	-- guess). See the pull-clock section below.
	self.pull_at = nil
	self.is_melee_attacking = false
	self.has_target = false
	self.has_attackable_target = false
	-- Movement state for the hunter ranged cast-window safety check (phase 1):
	-- PLAYER_STARTED_MOVING / PLAYER_STOPPED_MOVING keep api.get_time()-domain stamps,
	-- and classes/hunter.lua consumes them through
	-- hunter_window.is_stopped_position_safe.
	self.is_moving = false
	self.last_stopped_moving_at = nil

	-- Next-action guide (paladin): landed melee swings this fight; incremented on
	-- swing start in combat, reset by the guide display when guidance stops.
	self.guide_melee_count = 0

	self.current_talent_group = api.GetActiveTalentGroup()

	self.form_index = api.GetShapeshiftForm()
	self.is_cat_or_bear = false
	if self.player_class == "DRUID" then
		if self.form_index == 1 or self.form_index == 3 then
			self.is_cat_or_bear = true
		end
	end
	self.should_show_bar_this_form = true

	-- MH timer containers
	self.mainhand.start = nil
	self.mainhand.speed = nil
	self.mainhand.ends_at = nil
	self.mainhand.inactive_timer = nil
	self.mainhand.has_weapon = true  -- always true
	self.mainhand.is_full = true  -- deliberately true
	self.mainhand.is_full_timer = nil
	self.mainhand.is_paused = false
	self.mainhand.current_progress = false

	-- OH containers
	self.offhand.start = nil
	self.offhand.speed = nil
	self.offhand.ends_at = nil
	self.offhand.inactive_timer = nil
	self.offhand.has_weapon = false
	self.offhand.is_full = false
	self.offhand.is_full_timer = nil
	self.offhand.is_paused = false

	-- ranged containers
	self.ranged.start = nil
	self.ranged.speed = nil
	self.ranged.ends_at = nil
	self.ranged.inactive_timer = nil
	self.ranged.has_weapon = false
	self.ranged.is_full = false
	-- Auto Shot sync state (hunter phase 1; the maths live in hunter_window.lua):
	--   synced_duration     - the auto-shot cycle length last read from
	--                         GetSpellCooldown(75), api.get_time()-domain seconds
	--   hidden_window_start / hidden_window_duration
	--                       - cached hidden cast-window bounds (phase 2 render consumes
	--                         them); nil means "recompute"
	--   auto_repeat_active  - last IsAutoRepeatSpell(75) reading (mounted hunters
	--                         always read false)
	--   last_restart_at     - clock stamp of the last deduped ranged start
	self.ranged.synced_duration = nil
	self.ranged.hidden_window_start = nil
	self.ranged.hidden_window_duration = nil
	self.ranged.auto_repeat_active = false
	self.ranged.last_restart_at = nil

	-- GCD info containers
	self.gcd = {}
    self.gcd.duration = nil
	self.gcd.started = nil
	self.gcd.expires = nil
	self.gcd.phys_length = nil
	self.gcd.spell_length = nil

	self.gcd1_phys_time_before_swing = nil
	self.gcd1_spell_time_before_swing = nil
	self.gcd1_marker_position = nil

	-- self.gcd2_phys_time_before_swing = nil
	-- self.gcd2_spell_time_before_swing = nil
	-- self.gcd2_marker_position = nil

	-- Latency info containers
	self.latency = {}
	self.latency.update_interval_s = 1
	self.latency.home_ms = 0
	self.latency.calibrated_home_ms = 0
	self.latency.world_ms = 0
	self.latency.calibrated_world_ms = 0

	-----------------------------------------------------------
	-- Register WoW API events
	-----------------------------------------------------------
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
	self:RegisterEvent("CHARACTER_POINTS_CHANGED")
	self:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	-- F1: the session's end. The chained error handler (installed in init_libs) is
	-- removed again here, so the next session never chains onto this session's.
	self:RegisterEvent("PLAYER_LOGOUT")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	-- Movement state and Auto Shot sync signals for the hunter ranged feature (phase 1).
	-- The movement events and SPELL_UPDATE_COOLDOWN are valid on every supported
	-- family; START_AUTOREPEAT_SPELL / STOP_AUTOREPEAT_SPELL are registered only where
	-- the client's event-validity probe accepts them (the same pattern as
	-- PLAYER_TARGET_SET_ATTACKING just below) - registering an unknown event throws.
	-- Without a probe, the family decides: the classic client line keeps them (the
	-- live clients expose them too; the probe governs wherever it exists).
	self:RegisterEvent("PLAYER_STARTED_MOVING")
	self:RegisterEvent("PLAYER_STOPPED_MOVING")
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	local autorepeat_events_valid = true
	if C_EventUtils and C_EventUtils.IsEventValid then
		autorepeat_events_valid = C_EventUtils.IsEventValid("START_AUTOREPEAT_SPELL")
			and C_EventUtils.IsEventValid("STOP_AUTOREPEAT_SPELL")
	elseif st.is_mainline then
		autorepeat_events_valid = false
	end
	if autorepeat_events_valid then
		self:RegisterEvent("START_AUTOREPEAT_SPELL")
		self:RegisterEvent("STOP_AUTOREPEAT_SPELL")
	end
	-- PLAYER_TARGET_SET_ATTACKING exists on the classic client line only, and
	-- registering an unknown event throws, so gate it by family and probe where
	-- the event-validity API is available.
	local target_attacking_valid = not st.is_mainline
	if target_attacking_valid and C_EventUtils and C_EventUtils.IsEventValid then
		target_attacking_valid = C_EventUtils.IsEventValid("PLAYER_TARGET_SET_ATTACKING")
	end
	if target_attacking_valid then
		self:RegisterEvent("PLAYER_TARGET_SET_ATTACKING")
	end
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_ENTER_COMBAT")
	self:RegisterEvent("PLAYER_LEAVE_COMBAT")
	self:RegisterEvent("UNIT_AURA")
	-- Resource tracking for the warrior/druid rage-vs-queued-cost colouring. The
	-- handler (ST:UNIT_POWER_FREQUENT) already exists; without this registration the
	-- entire rage feature was unreachable.
	self:RegisterEvent("UNIT_POWER_FREQUENT")
	-- The classic combat log feeds the paladin twist state machine and the warrior
	-- Overpower dodge-proc window (reference State.lua:1315-1321/1340-1349). Only the
	-- classic client line has it; Mainline-code clients (Retail, Forever) have no
	-- classic combat log, so no window can ever arm there.
	if (self.player_class == "PALADIN" or self.player_class == "WARRIOR") and not st.is_mainline then
		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
	self:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	-- Player spellcast lifecycle for the class modules (weave assist and friends).
	-- Unlike PLAYER_TARGET_SET_ATTACKING these events exist on every supported
	-- client, so they need no family/validity gate.
	self:RegisterEvent("UNIT_SPELLCAST_START")
	self:RegisterEvent("UNIT_SPELLCAST_DELAYED")
	self:RegisterEvent("UNIT_SPELLCAST_STOP")
	self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
	self:RegisterEvent("UNIT_SPELLCAST_FAILED")
	self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
	self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
	self:RegisterEvent("UNIT_TARGET")
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

	-----------------------------------------------------------
	-- Register Slashcommands
	-----------------------------------------------------------
	self:register_slashcommands()

end

--=========================================================================================
-- Class activation (operator order 2026-10-21)
--=========================================================================================
-- The class files register their body as a loader in st.class_loaders at load; the
-- SELECTED class is activated here, during init, because the SavedVariables are not
-- readable while the files execute. Activation runs before post_init, whose class hook
-- is what brings up the practice panel and the HUD (tests/main_init_state.lua pins that
-- order). With the default "Auto" the active class is the one being played, so a rogue
-- session behaves exactly as it did when every class file ran at load.
-- Fail closed: a missing loader or a loader that throws never aborts init. On a throw
-- the class table is reset to a fresh empty table (no half-state) and the user sees one
-- clear line. A class file that still runs its body at load (the pre-loader shape) is
-- already populated and is never reported as missing.
function ST:activate_class()
	if self.class_activated then
		return self.class_activated
	end
	self.class_activated = true
	-- The shared layer's one fact about class features (C7): the class whose
	-- loader ran. nil until a loader succeeds, so a shared module always reads
	-- ST.active_class and never guesses from player_class.
	self.active_class = nil

	local selection = self:get_class_table().class_activation
	local explicit = type(selection) == "string" and string.lower(selection) ~= "auto"
	if not explicit then
		selection = self.player_class
	end
	local class = type(selection) == "string" and string.upper(selection) or nil
	local loaders = st.class_loaders
	local loader = class and loaders and loaders[class] or nil
	if type(loader) ~= "function" then
		local already_loaded = class ~= nil and type(self[class]) == "table"
			and next(self[class]) ~= nil
		-- Auto on a class this addon has no module for is today's unsupported-class
		-- path and stays silent; an explicit pick is intent, so it gets the notice.
		if explicit and not already_loaded then
			self:Print("SwedgeTimer: no class module is available for "
				.. tostring(class or selection) .. "; its class features stay disabled.")
		end
		return false, "no-loader"
	end
	local ok, err = pcall(loader)
	if not ok then
		if class then
			self[class] = {}
		end
		self:Print("SwedgeTimer: the " .. tostring(class) .. " class module failed to load ("
			.. tostring(err) .. "); its class features stay disabled for this session.")
		return false, err
	end
	-- R0 (class-isolation 2026-10-21): record the class that actually owns the
	-- populated module table. The shared layer keys every class feature on this
	-- field, so an explicit non-playing pick behaves as the selected class.
	self.active_class = class
	return true
end

function ST:init_libs()
	-- This function inits our interfaces to the libraries we use,
	-- but only once those libraries are fully ready and have
	-- all of the information necessary.
	if self.interfaces_are_initialised then
		return
	end
	if not (self.lrc_ready and self.stl_ready) then
		return
	end
	-- Operator order 2026-10-21: only the SELECTED class's module executes. This is
	-- the first point where the SavedVariables (AceDB) are readable, and it is before
	-- the class post_init hook and the practice/HUD init that hook performs.
	self:activate_class()
	self.interfaces_are_initialised = true
	-- F1 (deep audit 2026-10-19): the chained error handler was never installed, so
	-- the diagnostic report's "errors none" line was a false negative - with no
	-- handler there was nothing that could ever have been observed. Install the
	-- chain now (the interfaces are up, so the rest of the session is covered) and
	-- remove it again on PLAYER_LOGOUT. The handler itself lives in diag.lua; this
	-- is the only caller.
	if st.diag and type(st.diag.install_error_handler) == "function" then
		st.diag.install_error_handler()
	end
	self:init_timers()
	self:init_range_finders()
	self:post_init()

	-- If requested, print a welcome message once everything is
	-- initialised properly.
	local db = self:get_profile_table()
	if db.welcome_message then
		self:Print("Version " .. version .. " loaded!")
	end

	-- No swing engine at all (Retail, or a Forever engine that never reported
	-- ready - see the init deadline): say so once, instead of leaving the user
	-- wondering why the swing bars never move.
	if not SWING_ENGINE_AVAILABLE then
		self:Print("Swing timer bars are unavailable on this client; range and GCD features remain active.")
	end

	-- Range state no longer depends on LibRangeCheck (exact yards, api.UnitDistance):
	-- a library that missed the deadline needs no disable notice here. The lrc_ready /
	-- lrc_unavailable flags stay for /st diag's lrc= line only.

	-- One-line readiness self-report for the owner's test session; /st diag prints
	-- the verbose form. Print-only, pcall-guarded end to end (see diag.lua).
	if st.diag then
		st.diag.report(self)
	end
end

function ST:init_timers()
	self:register_timer_callbacks()
	self:check_weapons()
	for hand in self:iter_hands() do
		local t = {SwingTimerInfo(hand)}
		if type(t[1]) ~= "number" then
			-- Unknown engine shape (the inert stand-in returns nil): never invent a
			-- cycle. The per-hand flag is what bars.lua renders as "engine offline".
			self[hand].speed = nil
			self[hand].ends_at = nil
			self[hand].start = nil
			self[hand].engine_dead = (SWING_ENGINE_AVAILABLE == false)
		else
			-- If the player has a shield, the below check prevents zero
			-- division errors in the offhand timer bar initialisation.
			if t[1] == 0 then
				t[1] = 0.1
			end
			self[hand].engine_dead = false
			self[hand].speed = t[1]
			self[hand].ends_at = t[2]
			self[hand].start = t[3]
		end
		ST:init_visuals_template(hand)
		ST:set_bar_texts(hand)
		-- hook the onupdate (st.diag may install a per-tick counter wrapper; default OFF
		-- installs the original untouched - see diag.lua's wrap_onupdate)
		local onupdate = self[hand].onupdate
		if st.diag and st.diag.wrap_onupdate then
			onupdate = st.diag.wrap_onupdate(self, hand, onupdate)
		end
		self:get_bar_frame(hand):SetScript("OnUpdate", onupdate)
	end
end

function ST:register_timer_callbacks()
	STL.RegisterCallback(self, "SWING_TIMER_CLIPPED", self.callback_event_handler)
	STL.RegisterCallback(self, "SWING_TIMER_DELTA", self.callback_event_handler)
	STL.RegisterCallback(self, "SWING_TIMER_PAUSED", self.callback_event_handler)
	STL.RegisterCallback(self, "SWING_TIMER_START", self.callback_event_handler)
	STL.RegisterCallback(self, "SWING_TIMER_STOP", self.callback_event_handler)
	STL.RegisterCallback(self, "SWING_TIMER_UPDATE", self.callback_event_handler)
end

function ST:check_weapons()
	-- Detect what weapon types are equipped.
	-- Before we used the LibClassicSwinngTimer function to get the attack speeds.
	-- This lib used the same events that this function is triggered on internally,
	-- which led to inconsistencies depending on callback order. Using the basic
	-- WoW API to make these checks fixes the issue.
	local _, speed_offhand = api.UnitAttackSpeed("player")
	speed_offhand = speed_offhand or 0
	local speed_ranged = api.UnitRangedDamage("player") or 0
	if speed_offhand == 0 then
		self.offhand.has_weapon = false
	else
		self.offhand.has_weapon = true
	end
	if speed_ranged == 0 then
		self.ranged.has_weapon = false
	else
		self.ranged.has_weapon = true
	end
	-- F2 (deep audit 2026-10-19): has_oh is the offhand-presence guard of
	-- ST:PLAYER_TARGET_SET_ATTACKING. It was initialised false and never set again,
	-- so that handler always returned at its guard and the offhand re-sync never ran
	-- in production. It is derived here from the very same probe that fills
	-- offhand.has_weapon, so the two can never disagree, and it follows every weapon
	-- change (PLAYER_EQUIPMENT_CHANGED calls this function for the weapon slots).
	self.has_oh = self.offhand.has_weapon
end

function ST:post_init()
	-- Takes care of any miscellaneous widget/state manipulation that needs to run
	-- once the libraries and addon are initialised.
	self:set_gcd_times_before_swing_seconds()
	self:on_latency_update()
	-- self:get_druid_talent_info()
	self:get_talent_information()
	self:determine_form_visibility_flag()
	for hand in self:iter_hands() do
		self:set_gcd_marker_positions(hand)
		-- self:set_bar_full_state(hand)
		self:on_bar_inactive(hand)
		self[hand].is_full = true
	end

	if self[self.player_class].post_init then
		-- R4 (class post_init isolation, 2026-10-21): a throwing class post_init used to
		-- abort ST:post_init before the shared widgets below (frame lock state, bar
		-- visibility, the TBC aura poll), and the error escaped into init_libs. One
		-- guarded site per class: the first throw is announced, every throw is counted
		-- and the site is quarantined after st.guard.QUARANTINE_THROWS (25), exactly
		-- like the other hook sites.
		st.guard.run(self, "class:" .. tostring(self.player_class) .. ":post_init",
			function(addon)
				local class_module = addon[addon.player_class]
				class_module.post_init(addon)
			end, self)
	end

	-- Melee-weave proximity bar (weave_range.lua): creates its hidden frame and driver
	-- here; the bar itself stays invisible until the class's weave_range_enabled toggle
	-- is on (off by default). Absent module (harness sandboxes) stays a no-op.
	if st.weave_range then
		st.weave_range.init(self)
	end

	-- Set frames to locked or unlocked based on settings.
	local db_class = self:get_class_table()
	if db_class.timers_locked then
		self:lock_frames()
	else
		self:unlock_frames()
	end
	for hand in self:iter_hands() do
		self:show_bar(hand)
	end

	-- TBC Anniversary: UNIT_AURA does not fire reliably there, so start the 0.05 s
	-- aura re-parse loop (TBC family only; a no-op everywhere else).
	self:start_aura_poll()
end

--=========================================================================================
-- TBC player-aura poll (UNIT_AURA does not fire reliably on TBC)
--=========================================================================================
-- Archive docs/swedge/SwedgeTimer_TBC/player.lua:913-918 re-runs
-- st.player.on_player_aura_change() every 0.05 s from the OnUpdate accumulator, so
-- seal changes are never missed. This is the same path through the rf_update-style
-- C_Timer loop: the tick re-runs the UNIT_AURA handler's exact parse path
-- (ST:class_on_aura_change, with its interfaces_are_initialised guard) on the same
-- 0.05 s cadence, on TBC-family clients only. Every other family returns before
-- arming anything, so those clients are byte-identical.
-- Archive parity: the archive poll is unconditional -- no combat gate and no
-- out-of-combat state-change skip -- so this loop is unconditional too; the only
-- throttle besides the cadence is the shared init guard. Deviation: the archive
-- accumulates frame elapsed time while this loop re-arms a C_Timer (the pattern
-- rf_update already uses), because main.lua has no per-frame OnUpdate.
local AURA_POLL_INTERVAL = 0.05

function ST:start_aura_poll()
	if st.family ~= "TBC" then
		return
	end
	if self.aura_poll_running then
		return
	end
	self.aura_poll_running = true
	self.aura_poll_interval = AURA_POLL_INTERVAL
	C_Timer.After(AURA_POLL_INTERVAL, function() self:aura_poll_tick() end)
end

function ST:aura_poll_tick()
	if st.family ~= "TBC" then
		return
	end
	-- The loop is armed once from post_init and must outlive the init window: gate
	-- only the work, exactly like ST:UNIT_AURA does, and always re-arm so a tick
	-- that fires before the libraries report never kills the loop.
	if self.interfaces_are_initialised then
		self:class_on_aura_change()
	end
	C_Timer.After(AURA_POLL_INTERVAL, function() self:aura_poll_tick() end)
end

--=========================================================================================
-- CallbackHandlers
--=========================================================================================
function ST:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
	-- AceEvent dispatches handlers as (event, ...): keep the event name in the
	-- forwarded arguments so each class module's signature lines up (the paladin
	-- twist chain and the warrior Overpower proc both read it).
	if not self.interfaces_are_initialised then
		return
	end
	if self.player_class == "PALADIN" then
		self.PALADIN.on_combat_log_unfiltered(self, event, ...)
	elseif self.player_class == "WARRIOR" then
		self.WARRIOR.on_combat_log_unfiltered(self, event, ...)
	end
end

function ST.callback_event_handler(event, ...)
	-- Func to pass all callbacks to their relevant handler. A throwing handler must
	-- not break the library's own dispatch (H3): isolate it, count it per event, and
	-- say so once per event - never silently resume without the counter.
	-- if string.find(event, "GCD") then
	-- 	st.utils.print_msg('<===============')
	-- 	st.utils.print_msg(event)
	-- 	local args = table.pack(...)
	-- 	for i=1, args.n do
	-- 		st.utils.print_msg(tostring(args[i]))
	-- 	end
	-- 	st.utils.print_msg('--------------->')
	-- end
	local handler = ST[event]
	if type(handler) ~= "function" then
		return
	end
	-- Swing-engine wire normalisation (TBC hunter ranged bar, 2026-10-21): the two
	-- engines disagree on the first payload argument. The vendored classic library
	-- re-fires its UNIT_SWING_TIMER_* events as SWING_TIMER_* WITH the unit id
	-- leading (Fire(legacy, unitId, speed, ...)), while swing_source fires
	-- speed-first; the app's handlers take speed-first. Drop a leading unit-id
	-- token here so both engines land on the same handler shape. Only the
	-- SWING_TIMER_* family is touched: GCD/latency callbacks keep their exact
	-- args, and a Forever payload (speed first, a number) passes through intact.
	local ok, err
	if type(event) == "string" and event:sub(1, 12) == "SWING_TIMER_"
		and (select(1, ...) == "player" or select(1, ...) == "target") then
		local n = select("#", ...)
		local args = { ... }
		ok, err = pcall(handler, ST, event, unpack(args, 2, n))
	else
		ok, err = pcall(handler, ST, event, ...)
	end
	if not ok then
		local counts = ST.callback_errors
		if not counts then
			counts = {}
			ST.callback_errors = counts
		end
		local n = (counts[event] or 0) + 1
		counts[event] = n
		if n == 1 then
			ST:Print("Swing timer callback '" .. tostring(event)
				.. "' failed and was isolated: " .. tostring(err))
		end
	end
end

-----------------------------------------------------------
-- GCD lib funcs
-----------------------------------------------------------
function ST:GCD_STARTED(_, duration, expires)
	self.gcd.duration = duration
	self.gcd.expires = expires
end

function ST:GCD_OVER()
	-- Registered in OnInitialize, so this can fire inside the ~5s init window; the
	-- visuals frames do not exist yet and indexing them used to crash.
	if not self.interfaces_are_initialised then
		return
	end
	self.gcd.expires = nil
	for hand in self:iter_hands() do
		self:get_visuals_frame(hand).gcd_bar:Hide()
	end
end

function ST:GCD_DURATIONS_UPDATED(_, phys_length, spell_length)
	self.gcd.spell_length = spell_length
	self.gcd.phys_length = phys_length
	self:set_gcd_times_before_swing_seconds()
	if self.interfaces_are_initialised then
		self:on_gcd_length_change()
	end
end

function ST:get_spell_gcd_duration()
	-- Base spell-GCD length in seconds (the lib's reported spell length; 1.5 before
	-- it has reported). The next-action guide consumes this as the engine's G input.
	return self.gcd.spell_length or 1.5
end

function ST:get_gcd_time_before_swing_seconds(hand)
	-- Precomputed spell-GCD "time before swing" (the spell GCD plus the configured
	-- marker offset) - the next-action guide's reseal deadline basis. Only the first
	-- marker is precomputed and its value is hand-independent today; the hand
	-- argument keeps this accessor symmetric with the other bar accessors.
	if hand ~= nil then
		local key = "gcd1_spell_time_before_swing_" .. tostring(hand)
		if self.gcd[key] ~= nil then
			return self.gcd[key]
		end
	end
	return self.gcd.gcd1_spell_time_before_swing or self:get_spell_gcd_duration()
end

-----------------------------------------------------------
-- Latency tracking
-----------------------------------------------------------
function ST:LATENCY_CHANGED(_, home, world)
	self.latency.home_ms = home
	self.latency.world_ms = world
	-- The latency monitor has produced a real measurement. `llm_ready` gates nothing;
	-- /st diag reports it so a dead monitor is visible instead of assumed working.
	if type(world) == "number" then
		self.llm_ready = true
	end
	self:set_adjusted_latencies()
	if self.interfaces_are_initialised then
		self:set_gcd_times_before_swing_seconds()
		self:on_latency_update()
	end
end

-----------------------------------------------------------
-- Swing Timer Lib
-----------------------------------------------------------
-- Swing-wire receipt counters (TBC hunter ranged bar, 2026-10-21): the silent
-- failure was callbacks arriving but misaligned, so the fix ships its own
-- reader. /st diag prints the per-hand START/UPDATE/STOP counts plus the last
-- cycle event - a quiet engine (or a misaligned wire) is one command away
-- instead of invisible.
function ST:note_swing_wire(hand, kind)
	local counts = self.swing_wire_counts
	if type(counts) ~= "table" then
		counts = {}
		self.swing_wire_counts = counts
	end
	local h = counts[hand]
	if type(h) ~= "table" then
		h = { start = 0, update = 0, stop = 0 }
		counts[hand] = h
	end
	if kind == "START" then
		h.start = h.start + 1
	elseif kind == "UPDATE" then
		h.update = h.update + 1
	elseif kind == "STOP" then
		h.stop = h.stop + 1
	end
	self.swing_wire_last = { hand = hand, kind = kind, t = GetTime() }
end

function ST:SWING_TIMER_CLIPPED(_, hand)
	if self[hand] then
		self[hand].is_paused = false
	end
end

function ST:SWING_TIMER_DELTA(_, delta)
	self.last_swing_delta = delta
end

function ST:SWING_TIMER_PAUSED(_, hand)
	local bar = self[hand]
	if not bar then
		if not self.swing_unknown_hand_notice_shown then
			self.swing_unknown_hand_notice_shown = true
			self:Print("Swing timer received unknown hand '" .. tostring(hand) .. "'; ignoring.")
		end
		return
	end
	-- st.utils.print_msg(hand)
	bar.is_paused = true
end

function ST:SWING_TIMER_START(_, speed, expiration_time, hand)
	self:note_swing_wire(hand, "START")
	local bar = self[hand]
	if not bar then
		if not self.swing_unknown_hand_notice_shown then
			self.swing_unknown_hand_notice_shown = true
			self:Print("Swing timer received unknown hand '" .. tostring(hand) .. "'; ignoring.")
		end
		return
	end
	-- if not ST.interfaces_are_initialised then return end
	if bar.is_full_timer then
		bar.is_full_timer:Cancel()
		bar.is_full = false
		self:on_bar_active(hand)
	elseif bar.is_full then
		bar.is_full = false
		self:on_bar_active(hand)
	end
	bar.is_full = false
	bar.is_paused = false
	bar.engine_dead = false
	bar.start = GetTime()
	bar.speed = speed
	bar.ends_at = expiration_time
	self:set_bar_color(hand)
	-- Next-action guide: count melee swings started while in combat (the guide's
	-- filler suggestion waits for more than two swings; paladins only have a
	-- mainhand, so one count per swing).
	if self.player_class == "PALADIN" and self.in_combat then
		self.guide_melee_count = (self.guide_melee_count or 0) + 1
	end
	if self.recent_form_change then
		self:on_gcd_length_change()
		self.recent_form_change = false
	end
end

function ST:SWING_TIMER_STOP(_, hand)
	self:note_swing_wire(hand, "STOP")
	local bar = self[hand]
	if not bar then
		if not self.swing_unknown_hand_notice_shown then
			self.swing_unknown_hand_notice_shown = true
			self:Print("Swing timer received unknown hand '" .. tostring(hand) .. "'; ignoring.")
		end
		return
	end
	local db_shared = self.db and self.db.profile
	local bar_full_delay = db_shared and db_shared.bar_full_delay
	if bar_full_delay == nil then
		bar_full_delay = 0.5
	end
	bar.is_full_timer = C_Timer.NewTimer(bar_full_delay, function()
		-- self:set_bar_full_state(hand)
		-- st.utils.print_msg("C_Timer expired")
		local live = self[hand]
		if not live then
			return
		end
		live.is_full = true
		self:on_bar_inactive(hand)
	end)
	if self.player_class == "DRUID" then
		self:on_attack_speed_change(hand)
	end
end

function ST:SWING_TIMER_UPDATE(_, speed, expiration_time, hand)
	self:note_swing_wire(hand, "UPDATE")
	local bar = self[hand]
	if not bar then
		if not self.swing_unknown_hand_notice_shown then
			self.swing_unknown_hand_notice_shown = true
			self:Print("Swing timer received unknown hand '" .. tostring(hand) .. "'; ignoring.")
		end
		return
	end
	local t = GetTime()
	if expiration_time < t then
		expiration_time = t
	end
	bar.is_paused = false
	bar.engine_dead = false
	bar.speed = speed
	bar.start = expiration_time - speed
	bar.ends_at = expiration_time
	-- st.utils.print_msg(string.format("%f : %f", t, expiration_time))
	if t >= expiration_time then
		bar.is_full = true
		self:on_bar_inactive(hand)
	else
		bar.is_full = false
	end
	-- st.utils.print_msg('New speed = ' .. tostring(speed))
	self:on_attack_speed_change(hand)
end

------------------------------------------------------------------------------------
-- Wow API event callbacks
--
-- AceEvent dispatches every handler as (event, ...). An argument a handler does not
-- use is named with a leading underscore (_event). F11: the old unused-argument
-- tautologies were runtime asserts doing a linter's job (the luacheck config
-- already ignores unused arguments, code 212) - the parameter name says it instead.
------------------------------------------------------------------------------------
function ST:CURRENT_SPELL_CAST_CHANGED(_event, is_cancelled)
	-- Same init guard as the spellcast handlers: queue detection recolours the bar.
	if not self.interfaces_are_initialised then
		return
	end
	self:class_on_current_spell_cast_changed(is_cancelled)
end

function ST:PLAYER_ENTERING_WORLD(_event, _is_initial_login, _is_reloading_ui)
	-- No work of its own: the init arc is driven by the library callbacks
	-- (init_libs), and the modules that need the world-enter signal (hud.lua,
	-- enemy_swing.lua, swing_source.lua) register it on their own frames.
end

function ST:PLAYER_EQUIPMENT_CHANGED(_event, slot, _has_current)
	-- Registered in OnInitialize; on_attack_speed_change reaches the visuals frames
	-- (deadzone width), which do not exist inside the init window.
	if not self.interfaces_are_initialised then
		return
	end
	if slot == 16 or slot == 17 or slot == 18 then
		self:check_weapons()
		for hand in self:iter_hands() do
			self:on_attack_speed_change(hand)
		end
	end

end

function ST:PLAYER_LOGOUT()
	-- F1 (deep audit 2026-10-19): the chained error handler is a session-wide chain
	-- on the client's error handler. It is installed in init_libs and must be removed
	-- here, or the next session chains onto this session's handler (and this
	-- session's ring keeps collecting into a module that is no longer loaded).
	if st.diag and type(st.diag.uninstall_error_handler) == "function" then
		st.diag.uninstall_error_handler()
	end
	-- H2 (deep audit 2026-10-20): the practice progression session's completion
	-- bonus, its daily streak, its run, its time active and its bounded history
	-- row were written by ONE caller - the practice session's stop. A player who
	-- practised and then logged out (or reloaded) kept the per-attempt XP and lost
	-- everything else, with no error and no notice.
	--
	-- The flush runs here, before the client writes the SavedVariables (the client
	-- serialises them after PLAYER_LOGOUT is dispatched). AceDB's own logout
	-- handler is registered at library load - before this one - so it has already
	-- stripped the defaults when this handler writes the fresh blob into
	-- profile.practice, and the write still lands inside sv.profiles[key].
	--
	-- The flush does NOT tear the frames down: a logout is not a session end, and
	-- the teardown is a separate risk. It only ends the progression session and
	-- persists it.
	local pui = st.practice_ui
	if type(pui) == "table" and type(pui.flush_progress_session) == "function" then
		-- M1 (re-audit 2026-10-20): the flush used to run under a bare pcall and
		-- the error was thrown away - the very data class H2 was filed for (the
		-- completion bonus, the daily streak, the run, the time active and the
		-- history row) went silent again, with no counter and no notice. The house
		-- contract counts the failure, reports the FIRST one once (never a chat
		-- flood) and shows the count in /st diag's bar_hook_errors line.
		--
		-- M1 (progression audit 2026-10-20): the flush reports the WRITE, not the
		-- close. A false result means the session closed but NOTHING was saved -
		-- the saved blob belongs to a NEWER build and is protected. The boundary
		-- sees that here and the player is told, once per session, that this
		-- session's XP is not being saved (the notice is the hook lane's, and it
		-- is already printed when the refusal was first detected).
		local flushed, wrote = st.guard.run(self, "practice:logout", pui.flush_progress_session, self)
		if flushed and wrote == false and type(pui.announce_not_persistable) == "function" then
			pui.announce_not_persistable(self)
		end
	end
end

--=========================================================================================
-- The live pull clock (BS-8 item 2 / P-17)
--=========================================================================================
-- The prepull rule needs a pull countdown (nextaction.lua's PREPULL_SEAL_LEAD_SECONDS
-- and out.prepull_ready read inputs.time_to_pull_seconds). The practice session has
-- its own synthetic clock (the drill's countdown); the LIVE guide needs a real one.
--
-- The shipped clients carry NO pull-timer API: the FrameXML of classic_era (1.15.9),
-- classic_anniversary (2.5.6), classic_titan (3.80.2) and origin/forever (1.60.1)
-- has no pull timer, no GetPullTime and no SetPullTimer (checked 2026-10-19 against
-- the client sources). So the live clock is the addon's own, and it publishes a
-- TIMESTAMP - the same shape the practice clock uses (ctx.pull_at /
-- ctx.pull_in_seconds) and the same shape the guide engine reads.
--
--   ST.pull_at              the absolute pull timestamp (api.get_time() domain);
--                            nil = unknown (never a guess).
--   ST:set_pull_at(at)      arm the clock at an absolute timestamp; nil disarms.
--   ST:set_pull_in(seconds) arm the clock `seconds` from now.
--   ST:pull_in_seconds(now) the countdown in seconds; nil when unknown.
--
-- The read is ONE timestamp (the stored pull moment against the injected clock) -
-- there is no per-frame scan and no client call in the reader.
--
-- The live source: the pull moment the client reports.
--   * the fight's own pull: PLAYER_REGEN_DISABLED stamps the clock (the pull
--     happened) and PLAYER_REGEN_ENABLED clears it (the NEXT pull is unknown).
--   * the pre-pull: while the player is out of combat and their own target
--     starts a cast, the pull is projected to that cast's END - the real "the
--     boss is casting, pull now" cue. The cast's start and end come from the
--     client (api.UnitCastingSpell), so no number is invented here.
--
-- The projection is deliberately narrow, because a wrong prepull prompt is worse
-- than no prepull prompt: it is taken from the player's TARGET (a pull is the
-- boss's opening cast, not the player's own), only while the player is OUT of
-- combat, and only when the player is in a GROUP inside an INSTANCE (a pull is a
-- group event, so an open-world mob casting can never arm the clock).

-- Arm the pull clock at an absolute timestamp (api.get_time() domain). nil
-- disarms it. A non-number is ignored: the clock is never a guess.
function ST:set_pull_at(at)
	if at == nil then
		self.pull_at = nil
		return nil
	end
	if type(at) ~= "number" or at ~= at then
		return self.pull_at
	end
	self.pull_at = at
	return self.pull_at
end

-- Arm the pull clock `seconds` from now (the clock domain is the api.get_time()
-- domain; a clock that does not answer leaves the clock unknown).
function ST:set_pull_in(seconds)
	if type(seconds) ~= "number" or seconds ~= seconds then
		return self.pull_at
	end
	local get_time = api and api.get_time
	local now = (type(get_time) == "function") and get_time() or nil
	if type(now) ~= "number" then
		return self.pull_at
	end
	return self:set_pull_at(now + seconds)
end

-- The seconds until the pull (negative after it), or nil when the pull is
-- unknown. One timestamp, no client call: the reader is the countdown against
-- the stored pull moment.
function ST:pull_in_seconds(now)
	if type(self.pull_at) ~= "number" then
		return nil
	end
	local get_time = api and api.get_time
	local clock = now
	if type(clock) ~= "number" then
		clock = (type(get_time) == "function") and get_time() or nil
	end
	if type(clock) ~= "number" or clock ~= clock then
		return nil
	end
	return self.pull_at - clock
end

-- Can the live client offer a pull moment at all? A pull is a group event inside
-- an instance, so the clock only ever arms there. Every probe is nil-safe: a
-- client that does not answer leaves the clock unknown.
function ST:pull_clock_source_available()
	if self.in_combat then
		return false
	end
	if type(IsInGroup) == "function" and not IsInGroup() then
		return false
	end
	if type(IsInInstance) == "function" and not IsInInstance() then
		return false
	end
	return true
end

-- The pre-pull projection: the player's target starts a cast out of combat, so
-- the pull is that cast's end. The cast's own times come from the client.
function ST:update_pull_clock(unit_id)
	if unit_id ~= "target" then
		return self.pull_at
	end
	if not self:pull_clock_source_available() then
		return self.pull_at
	end
	if type(api) ~= "table" or type(api.UnitCastingSpell) ~= "function" then
		return self.pull_at
	end
	local ok, _, _, _, end_seconds = pcall(api.UnitCastingSpell, "target")
	if not ok or type(end_seconds) ~= "number" or end_seconds ~= end_seconds then
		return self.pull_at
	end
	return self:set_pull_at(end_seconds)
end

function ST:PLAYER_REGEN_ENABLED()
	self.in_combat = false
	self.fight_start_at = nil
	-- The pull is over and the next one is unknown: the clock is disarmed,
	-- so no reader can mistake the last fight's pull for an upcoming one.
	self:set_pull_at(nil)
	-- Reset combat-scoped class state (e.g. the paladin extra-attack counter):
	-- orphaned procs must not suppress the next fight's first twists.
	local class = self[self.player_class]
	if class and class.on_combat_exit then
		class.on_combat_exit(self)
	end
end

function ST:PLAYER_REGEN_DISABLED()
	self.in_combat = true
	-- Fight clock: stamp combat-enter in the api.get_time() domain (nil-safe:
	-- a clock that does not answer leaves the stamp unknown). Re-stamps on
	-- every enter, like the hunter shot-log reset below.
	local get_time = api and api.get_time
	local now = (type(get_time) == "function") and get_time() or nil
	if type(now) == "number" then
		self.fight_start_at = now
		-- The live pull clock: the fight's own pull happened, so the clock
		-- reads zero (the prepull window is behind us, never ahead of the
		-- pull). A clock that did not answer leaves the pull unknown.
		self:set_pull_at(now)
	end
	-- Design mode is cosmetic only (no protected calls anywhere in its teardown): drop
	-- its chrome when a fight starts. Routed through this already-registered handler so
	-- no new event is needed.
	if st.designmode and st.designmode.on_combat_start then
		st.designmode.on_combat_start()
	end
	-- Fight-scoped hunter shot log (H2, competitor_gaps): a fight starts with an empty
	-- log so the post-fight report covers this fight only; between fights the log keeps
	-- rolling the last-N shots. Hunter-only: no other class fills the log (the sampler
	-- runs on the hunter ranged tick), so no other class resets it. Guarded like the
	-- on_combat_exit dispatch below (a missing module never errors).
	if self.player_class == "HUNTER" and self.HUNTER
		and self.HUNTER.reset_shot_log then
		self.HUNTER.reset_shot_log(self)
	end
end

function ST:PLAYER_ENTER_COMBAT()
	self.is_melee_attacking = true
end

function ST:PLAYER_LEAVE_COMBAT()
	self.is_melee_attacking = false
end

function ST:PLAYER_STARTED_MOVING()
	-- Hunter ranged cast-window safety input: whether the player is moving right now
	-- (one component of hunter_window.is_stopped_position_safe).
	self.is_moving = true
end

function ST:PLAYER_STOPPED_MOVING()
	self.is_moving = false
	self.last_stopped_moving_at = api.get_time()
end

function ST:PLAYER_TARGET_SET_ATTACKING()
	-- Required to set the offhand timer delay when startattack or when
	-- target is changed (both fire this event).
	--
	-- F2 (deep audit 2026-10-19): this handler used to be a silent no-op in
	-- production - has_oh was never set true, so the body always returned at the
	-- guard and the registered event did nothing. The guards below now describe the
	-- real state: the player has an offhand weapon (derived in check_weapons), the
	-- class has an offhand bar at all (a paladin or a druid has an offhand weapon
	-- but no offhand bar, and the recolour below would touch frames that do not
	-- exist), and there is a live offhand cycle to re-sync (before the first swing -
	-- and on the inert stand-in - the cycle fields are nil).
	if not self.interfaces_are_initialised then return end
	if not self.has_oh then return end
	if not self:has_hand("offhand") then return end
	local speed = self.offhand.speed
	local old_start = self.offhand.start
	if type(speed) ~= "number" or type(old_start) ~= "number" then return end
	if speed <= 0 then return end
	-- The aligned clock (compat's api.get_time): the same domain the swing engine's
	-- GetTime() stamps live in, so the comparison below is apples to apples.
	local get_time = api and api.get_time
	local t = (type(get_time) == "function") and get_time() or nil
	if type(t) ~= "number" then return end
	if old_start + speed < t then
		-- The offhand cycle is overdue: re-sync it to a fresh, full swing. Both ends
		-- move together - the bar divides the elapsed time by (ends_at - start), so
		-- moving one end alone could leave a negative span and a negative bar width.
		self:set_bar_color('offhand')
		self.offhand.start = t - speed
		self.offhand.ends_at = t
	end
end

function ST:UNIT_AURA(_event, unit_id, _is_full_update, _updated_auras)
	if unit_id ~= "player" or (not self.interfaces_are_initialised) then
		return
	end
	self:class_on_aura_change()
end

function ST:UNIT_POWER_FREQUENT(_event, unit_id, powerType)
	-- Used to track if a warrior or druid has enough rage to cast
	-- any currently queued on-next-cast ability
	if unit_id ~= "player" or (not self.interfaces_are_initialised) then
		return
	end
	if powerType == "RAGE" then
		if self[self.player_class].on_rage_update then
			self[self.player_class].on_rage_update(self)
		end
	end
end

function ST:UNIT_SPELLCAST_FAILED_QUIET(_event, unit_id, cast_guid, spell_id)
	if unit_id ~= "player" or (not self.interfaces_are_initialised) then
		return
	end
	-- Trigger any class-specific behaviour
	if self[self.player_class].on_spellcast_failed_quiet then
		self[self.player_class].on_spellcast_failed_quiet(self, unit_id, cast_guid, spell_id)
	end
end

function ST:UNIT_SPELLCAST_SUCCEEDED(_event, unit_id, cast_guid, spell_id)
	-- Class hooks recolour the bar, which needs the visuals frame. Casting within the
	-- init window (up to the 5s deadline) used to index a nil anchor_frame here.
	if unit_id ~= "player" or (not self.interfaces_are_initialised) then
		return
	end
	-- Trigger any class-specific behaviour
	if self[self.player_class].on_spellcast_succeeded then
		self[self.player_class].on_spellcast_succeeded(self, unit_id, cast_guid, spell_id)
	end
end

-- Player spellcast lifecycle events: one thin handler per event, each forwarded to
-- the class module's on_spellcast_event hook when it has one. cast_guid/spell_id
-- can be nil on some clients (e.g. UNIT_SPELLCAST_STOP may omit the spell id) and
-- are passed through as received. The early return matches the two sibling handlers
-- above (H6): ST:class_on_spellcast_event (below) has no callee-side init guard,
-- and a cast inside the ~5 s init window can reach visuals that do not exist yet.
function ST:UNIT_SPELLCAST_START(event, unit_id, cast_guid, spell_id)
	if not self.interfaces_are_initialised then
		return
	end
	-- The live pull clock: a target that starts casting out of combat is
	-- the pre-pull (the pull is the cast's end). Cheap: one cast read per
	-- cast start, and it arms the clock only when the source allows it.
	self:update_pull_clock(unit_id)
	self:class_on_spellcast_event(event, unit_id, cast_guid, spell_id)
end

function ST:UNIT_SPELLCAST_DELAYED(event, unit_id, cast_guid, spell_id)
	if not self.interfaces_are_initialised then
		return
	end
	self:class_on_spellcast_event(event, unit_id, cast_guid, spell_id)
end

function ST:UNIT_SPELLCAST_STOP(event, unit_id, cast_guid, spell_id)
	if not self.interfaces_are_initialised then
		return
	end
	self:class_on_spellcast_event(event, unit_id, cast_guid, spell_id)
end

function ST:UNIT_SPELLCAST_INTERRUPTED(event, unit_id, cast_guid, spell_id)
	if not self.interfaces_are_initialised then
		return
	end
	self:class_on_spellcast_event(event, unit_id, cast_guid, spell_id)
end

function ST:UNIT_SPELLCAST_FAILED(event, unit_id, cast_guid, spell_id)
	if not self.interfaces_are_initialised then
		return
	end
	self:class_on_spellcast_event(event, unit_id, cast_guid, spell_id)
end

function ST:UNIT_SPELLCAST_CHANNEL_START(event, unit_id, cast_guid, spell_id)
	if not self.interfaces_are_initialised then
		return
	end
	self:class_on_spellcast_event(event, unit_id, cast_guid, spell_id)
end

function ST:UNIT_SPELLCAST_CHANNEL_STOP(event, unit_id, cast_guid, spell_id)
	if not self.interfaces_are_initialised then
		return
	end
	self:class_on_spellcast_event(event, unit_id, cast_guid, spell_id)
end

function ST:UNIT_TARGET(event, unit_id)
	if event ~= "UNIT_TARGET" then
		return
	end
	if unit_id ~= "player" then
		return
	end
	if UnitExists("target") then self.has_target = true else self.has_target = false end
	if UnitCanAttack("player", "target") == true then
		self.has_attackable_target = true
	else
		self.has_attackable_target = false
	end
end

function ST:UPDATE_SHAPESHIFT_FORM()
	-- At present, only druids care about shapeshifting, so the code
	-- to handle their forms goes here.
	if self.player_class ~= "DRUID" then
        return
    end
	local i = api.GetShapeshiftForm()

	-- If form hasn't changed, do nothing.
	if i == self.form_index then
		return
	end
    self.form_index = i
	self:determine_form_visibility_flag()
	if i == 1 or i ==3 then
        self.is_cat_or_bear = true
    else
        self.is_cat_or_bear = false
    end

	-- Set a flag to ensure a recalculation of bar elements at the next swing
	-- in case of any snapshotting
	self.recent_form_change = true
	if self.interfaces_are_initialised then
		self:on_attack_speed_change("mainhand")
		self:set_bar_color("mainhand")
	end
	if self.interfaces_are_initialised then
		self:handle_bar_visibility("mainhand")
	end
end

function ST:SPELL_UPDATE_COOLDOWN()
	-- Auto Shot cooldown refresh for the hunter ranged sync. State-only in phase 1:
	-- the hook updates self.ranged and never touches a frame.
	local class = self[self.player_class]
	if class and class.on_cooldown_update then
		class.on_cooldown_update(self)
	end
end

function ST:START_AUTOREPEAT_SPELL()
	-- Auto Shot auto-repeat started (hunter): refresh the cached auto-repeat state
	-- and seed a deduped ranged cycle anchor. State-only in phase 1.
	local class = self[self.player_class]
	if class and class.on_autorrepeat_event then
		class.on_autorrepeat_event(self, true)
	end
end

function ST:STOP_AUTOREPEAT_SPELL()
	-- Auto Shot auto-repeat stopped (hunter): refresh the cached auto-repeat state.
	local class = self[self.player_class]
	if class and class.on_autorrepeat_event then
		class.on_autorrepeat_event(self, false)
	end
end

function ST:determine_form_visibility_flag()
	-- function called on form or settings change to
	-- set the form visibility flag
	local i = api.GetShapeshiftForm()
	local db = self:get_class_table()
	self.should_show_bar_this_form = false
	if i == 0 and db.form_vis_normal then
		self.should_show_bar_this_form = true
	elseif i == 1 and db.form_vis_bear then
		self.should_show_bar_this_form = true
	elseif i == 4 and db.form_vis_travel then
		self.should_show_bar_this_form = true
	elseif i == 3 and db.form_vis_cat then
		self.should_show_bar_this_form = true
	elseif i == 5 and db.form_vis_moonkin and self.has_moonkin then
		self.should_show_bar_this_form = true
	elseif i == 5 and db.form_vis_tree and self.has_tree_of_life then
		self.should_show_bar_this_form = true
	elseif i == 5 and (not self.has_moonkin and not self.has_tree_of_life) and db.form_vis_flight then
		self.should_show_bar_this_form = true
	elseif i == 6 and db.form_vis_flight then
		self.should_show_bar_this_form = true
	end
end

------------------------------------------------------------------------------------
-- Talent information.
------------------------------------------------------------------------------------
function ST:ACTIVE_TALENT_GROUP_CHANGED(event, group)
	self.last_talent_event = event
	self.current_talent_group = group
	if self.player_class == "DRUID" then
		self:get_druid_talent_info()
		self:determine_form_visibility_flag()
	elseif self.player_class == "WARRIOR" then
		self:get_warrior_talent_info()
	end
	local class = self[self.player_class]
	-- Class modules may cache client-specific data that a respec invalidates (the
	-- shaman weave catalogue caches rank cast times resolved at post_init).
	if class and class.on_talents_changed then
		class.on_talents_changed(self)
	end
end

function ST:CHARACTER_POINTS_CHANGED(event)
	self.last_talent_event = event
	if self.player_class == "DRUID" then
		self:get_druid_talent_info()
		self:determine_form_visibility_flag()
	elseif self.player_class == "WARRIOR" then
		self:get_warrior_talent_info()
	end
	local class = self[self.player_class]
	-- Class modules may cache client-specific data that a respec invalidates (the
	-- shaman weave catalogue caches rank cast times resolved at post_init).
	if class and class.on_talents_changed then
		class.on_talents_changed(self)
	end
end

function ST:get_talent_information()
	self:get_druid_talent_info()
	self:get_warrior_talent_info()
end

-- Talent-tree positions are only verified on the Wrath of the Lich King client.
-- Every other family lays its talent trees out differently (or replaced the tree
-- system entirely), so these checks stay off there until per-family positions are
-- verified; the flags then simply stay false.
local talent_positions = {
	WRATH = {
		moonkin = {1, 11},
		tree_of_life = {3, 19},
		devastate = {3, 20},
		imp_def_stance = {3, 16},
		bladestorm = {1, 27},
	},
}

function ST:get_druid_talent_info()
	-- function to get the druid talent info and determine
	-- if the player has moonkin or tree
	local positions = talent_positions[st.family]
	if not positions then
		self.has_moonkin = false
		self.has_tree_of_life = false
		return
	end
	self.has_moonkin = select(5, api.GetTalentInfo(positions.moonkin[1], positions.moonkin[2])) == 1
	self.has_tree_of_life = select(5, api.GetTalentInfo(positions.tree_of_life[1], positions.tree_of_life[2])) == 1
end

function ST:get_warrior_talent_info()
	-- Functions to get talents for specs that the user may want to hide
	-- the swing timer in.
	local positions = talent_positions[st.family]
	if not positions then
		self.has_devastate = false
		self.has_imp_def_stance = false
		self.has_bladestorm = false
		return
	end
	self.has_devastate = select(5, api.GetTalentInfo(positions.devastate[1], positions.devastate[2])) == 1
	self.has_imp_def_stance = select(5, api.GetTalentInfo(positions.imp_def_stance[1], positions.imp_def_stance[2])) ~= 0
	self.has_bladestorm = select(5, api.GetTalentInfo(positions.bladestorm[1], positions.bladestorm[2])) == 1
end

------------------------------------------------------------------------------------
-- Latency and GCD markers
------------------------------------------------------------------------------------
function ST:set_adjusted_latencies()
	-- Set the calibrated latencies
	local db = self:get_profile_table()
	local home = (self.latency.home_ms * db.latency_scale_factor) + db.latency_linear_offset
	self.latency.calibrated_home_ms = home
	local world = (self.latency.world_ms * db.latency_scale_factor) + db.latency_linear_offset
	self.latency.calibrated_world_ms = world
end

function ST:get_gcd_marker_time_offset_seconds()
	-- Gets the time offset in seconds according to the settings.
	local db = self:get_profile_table()
	local offset = 0
	if db.gcd_marker_offset_mode == "Dynamic" then
		offset = self.latency.world_ms
	elseif db.gcd_marker_offset_mode == "Calibrated" then
		offset = self.latency.calibrated_world_ms
	elseif db.gcd_marker_offset_mode == "Fixed" then
		offset = db.latency_linear_offset
	end
	offset = offset / 1000
	return offset
end

function ST:set_gcd_times_before_swing_seconds()
	-- Set all of the calculated times before our next swing. The bases fall back to
	-- the documented 1.5 s pre-report default (the same one get_spell_gcd_duration
	-- applies): init_libs can complete without LibGlobalCooldown ever reporting (a
	-- broken library, or the init deadline), and nil arithmetic here used to crash
	-- post_init after interfaces_are_initialised was already set.
	local base_phys = self.gcd.phys_length or 1.5
	local base_spell = self.gcd.spell_length or 1.5
	local offset = self:get_gcd_marker_time_offset_seconds()
	self.gcd.gcd1_phys_time_before_swing = base_phys + offset
	self.gcd.gcd1_spell_time_before_swing = base_spell + offset
	self.gcd.gcd2_phys_time_before_swing = (2 * base_phys) + offset
	self.gcd.gcd2_spell_time_before_swing = (2 * base_spell) + offset
end

------------------------------------------------------------------------------------
-- Range finding
------------------------------------------------------------------------------------
-- Exact-yard range state (R1, 2026-10-21). Source: compat's api.UnitDistance, one
-- UnitDistanceSquared probe per poll. nil means the client cannot answer (unknown),
-- and unknown is never turned into a guess or a 0. LibRangeCheck is NOT consulted for
-- range state any more: its interaction ladder called CheckInteractDistance, a
-- PROTECTED function on TBC Anniversary (see the vendored header block), so the addon
-- reads exact yards and the library keeps only its non-interact checkers.
-- UnitDistanceSquared is addon-callable: Blizzard's own CompactUnitFrame.lua:1069
-- (classic_anniversary) calls it from insecure unit-frame Lua and trusts the reading
-- only when checkedDistance is true; compat normalises exactly that. Blizzard calls
-- CheckInteractDistance only from secure popup code (UnitPopupSharedUtils.lua:194,
-- classic_anniversary); the addon block is the 2026-10-21 in-client
-- ADDON_ACTION_BLOCKED log, not a documented API restriction.
--
-- RF_MELEE_RANGE = 5: the vendored library's retired interaction ladder treated 5 yd
-- as the melee band (HarmItems[5], item 8149 "Voodoo Charm"). The library's own
-- `local MeleeRange = 2` is its SPELL-range floor - a different quantity - so it is
-- not this constant's source.
-- RF_RANGED_RANGE = 30 / hunter 35: carried over unchanged from the pre-change
-- implementation (classic 30 yd spell range; the hunter dead zone starts at 5 yd and
-- their shots reach 35 yd).
local RF_MELEE_RANGE = 5
local RF_RANGED_RANGE = 30
local RF_HUNTER_RANGED_RANGE = 35

function ST:ranged_range_yards()
	if self.player_class == "HUNTER" then
		return RF_HUNTER_RANGED_RANGE
	end
	return RF_RANGED_RANGE
end

function ST:disable_range_checking()
	-- Runtime dead-man for the poll loop only (three consecutive poll failures). It
	-- deliberately does NOT set lrc_unavailable: that field means "LibRangeCheck missed
	-- the init deadline" and is what /st diag reports as lrc=fallback - range state does
	-- not depend on the library, so a poll failure must not rewrite that line.
	self.rf_disabled = true
	if not self.range_disabled_notice_shown then
		self.range_disabled_notice_shown = true
		self:Print("Range checking is unavailable on this client; the range display is disabled.")
	end
end

function ST:update_range_state()
	-- One exact-yards probe per poll. nil is "unknown": both flags false (never nil,
	-- never true) and both text fields cleared, so the bars render a blank range and
	-- the out-of-range dim treats the target as not confirmed in range.
	local yards = api.UnitDistance("target")
	self.target_distance = yards
	if yards == nil then
		self.in_melee_range = false
		self.in_ranged_range = false
		self.target_min_range = nil
		self.target_max_range = nil
		return
	end
	local in_melee = yards <= RF_MELEE_RANGE
	self.in_melee_range = in_melee
	self.in_ranged_range = (yards <= self:ranged_range_yards()) and not in_melee
	-- Text fields stay integers around the exact reading: floor/ceil never claim a
	-- tighter band than the probe supports.
	self.target_min_range = math.floor(yards)
	self.target_max_range = math.ceil(yards)
end

function ST:init_range_finders()
	self.rangefinder_interval = 0.05
	self.target_distance = nil
	self.in_melee_range = false
	self.in_ranged_range = false
	self.target_min_range = nil
	self.target_max_range = nil
	self:rf_update()
end

-- Range-poll resilience (M1). A transient throw retries a bounded number of times with
-- exponential backoff before the session-disable. A nil reading is NOT a failure: it is
-- the honest "unknown" answer and the loop keeps polling. Only the failure terminal
-- sets rf_disabled; its counters stay in /st diag's runtime line.
local RF_MAX_POLL_FAILURES = 3
local RF_MAX_RETRY_DELAY = 0.4

function ST:rf_update()
	if self.rf_disabled then
		-- Range checking was disabled by the poll dead-man: stop the retry loop.
		return
	end
	-- api.UnitDistance already pcalls the client call; this outer pcall also covers
	-- the state writes, so a future edit here cannot kill the polling loop silently.
	local ok, err = pcall(function()
		self:update_range_state()
	end)
	if not ok then
		self.rf_failure_count = (self.rf_failure_count or 0) + 1
		self.rf_last_error = tostring(err)
		if self.rf_failure_count >= RF_MAX_POLL_FAILURES then
			self.rf_disabled_after_failures = true
			self:disable_range_checking()
			return
		end
		local delay = self.rangefinder_interval * (2 ^ (self.rf_failure_count - 1))
		if delay > RF_MAX_RETRY_DELAY then
			delay = RF_MAX_RETRY_DELAY
		end
		self.rf_retry_delay = delay
		C_Timer.After(delay, function() self:rf_update() end)
		return
	end
	self.rf_failure_count = 0
	self.rf_retry_delay = nil
	self:set_bar_visibilities()
	self:handle_oor()
	C_Timer.After(self.rangefinder_interval, function() self:rf_update() end)
end

------------------------------------------------------------------------------------
-- Bar out-of-range behaviour
------------------------------------------------------------------------------------
function ST:handle_oor()
	for hand in self:iter_hands() do
		if self:bar_is_enabled(hand) then
			self:handle_oor_hand(hand)
		end
	end
end

function ST:handle_oor_hand(hand)
	local db = self:get_hand_table(hand)
	local frame = self:get_bar_frame(hand)
	-- self:Print(db.dim_oor)
	if db.dim_oor then
		-- if hand == "offhand" then
		-- 	-- self:Print(self:get_in_range(hand))
		-- end
		if not self:get_in_range(hand) then
			frame:SetAlpha(db.dim_alpha)
		else
			frame:SetAlpha(1.0)
		end
	else
		frame:SetAlpha(1.0)
	end
end

------------------------------------------------------------------------------------
-- Bar visibility
------------------------------------------------------------------------------------
function ST:bar_is_enabled(hand)
	local db = self:get_hand_table(hand)
	if hand == "mainhand" then -- always has weapon
		if db.enabled then
			return true
		else
			return false
		end
	end
	if db.enabled and self[hand].has_weapon then
		return true
	else
		return false
	end
end

function ST:handle_bar_visibility(hand)
	-- Determines if the bar should be shown or not.
	local db = self:get_hand_table(hand)
	if db.show_behaviour == "always" then
		self:show_bar(hand)
		return
	end
	if db.show_condition == "in_combat" then
		if self.in_combat then
			self:show_bar(hand)
		else
			self:hide_bar(hand)
		end
	elseif db.show_condition == "has_target" then
		if not self.has_attackable_target then
			self:hide_bar(hand)
			return
		end
		if db.require_in_range then
			if not self:get_in_range(hand) then
				self:hide_bar(hand)
				return
			end
		end
		self:show_bar(hand)
	elseif db.show_condition == "both" then
		if not self.in_combat then
			self:hide_bar(hand)
			return
		end
		if not self.has_attackable_target then
			self:hide_bar(hand)
			return
		end
		if db.require_in_range then
			if not self:get_in_range(hand) then
				self:hide_bar(hand)
				return
			end
		end
		self:show_bar(hand)
	elseif db.show_condition == "either" then
		if self.in_combat then
			self:show_bar(hand)
			return
		end
		if not self.has_attackable_target then
			self:hide_bar(hand)
			return
		end
		if db.require_in_range then
			if not self:get_in_range(hand) then
				self:hide_bar(hand)
				return
			end
		end
		self:show_bar(hand)
	end
end

function ST:set_bar_visibilities()
	-- Function hooked onto the rangefinder C_Timer to determine bar states
	local db_class = self:get_class_table()
	if not db_class.class_enabled then
		for hand in self:iter_hands() do
			self:hide_bar(hand)
		end
		return
	end

	for hand in self:iter_hands() do
		-- st.utils.print_msg(string.format("%s in range: %s", hand, tostring(in_range)))
		if not self:bar_is_enabled(hand) then
			self:hide_bar(hand)
		else
			self:handle_bar_visibility(hand)
		end
	end
end

------------------------------------------------------------------------------------
-- Slashcommands
------------------------------------------------------------------------------------
-- Runtime half of /st diag verbose: the counters the guarded call sites write. One
-- line on every client, plus the Forever engine's payload/speed-read counters when
-- that engine is the live one (H5). print-only, like diag.lua.
function ST:print_runtime_diag()
	local parts = {}
	local bar = self.bar_hook_errors
	if type(bar) == "table" then
		parts[#parts + 1] = "bar_hook_errors=" .. tostring(bar.count or 0)
	else
		parts[#parts + 1] = "bar_hook_errors=0"
	end
	local callback_total = 0
	if type(self.callback_errors) == "table" then
		for _, count in pairs(self.callback_errors) do
			if type(count) == "number" then
				callback_total = callback_total + count
			end
		end
	end
	parts[#parts + 1] = "callback_errors=" .. tostring(callback_total)
	-- F5 (deep audit 2026-10-19): the HUD's combat-log registration counter was
	-- write-only - hud.lua's comment named a /st diag reader that did not exist.
	-- This runtime line IS that reader: hud.lua counts every failed
	-- COMBAT_LOG_EVENT_UNFILTERED registration, and the volume is visible here.
	local hud = st.hud
	local cleu_errors = 0
	if type(hud) == "table" and type(hud.cleu_register_errors) == "number" then
		cleu_errors = hud.cleu_register_errors
	end
	parts[#parts + 1] = "hud_cleu_register_errors=" .. tostring(cleu_errors)
	-- JE-1 (deep audit 2026-10-19): the paladin's LibClassicDurations
	-- registration failure was invisible - the class counts every failed
	-- LCD.Register (ST.PALADIN.lcd_register_errors) and nothing read it, so a
	-- degraded guide frame showed no diagnostic at all. This runtime line
	-- IS that reader, in the same shape as the HUD counter above. The class
	-- table lives on the addon object, so the read is self.PALADIN.
	local paladin = self.PALADIN
	local lcd_errors = 0
	if type(paladin) == "table" and type(paladin.lcd_register_errors) == "number" then
		lcd_errors = paladin.lcd_register_errors
	end
	parts[#parts + 1] = "paladin_lcd_register_errors=" .. tostring(lcd_errors)
	parts[#parts + 1] = "rf_failures=" .. tostring(self.rf_failure_count or 0)
	parts[#parts + 1] = "rf_disabled=" .. tostring(self.rf_disabled == true)
	parts[#parts + 1] = "rf_disabled_after_failures=" .. tostring(self.rf_disabled_after_failures == true)
	-- Client identity the swing lib's version branches read (Era vs Anniversary,
	-- 2026-10-21): the vendored engine picks its isClassic/isBCC tables off
	-- WOW_PROJECT_ID and LE_EXPANSION_LEVEL_CURRENT, compared against the
	-- WOW_PROJECT_* constants. A nil constant or an unexpected expansion level
	-- leaves every table empty with no error (melee survives, ranged does not).
	-- Read-only, nil-tolerant: unknown prints as nil.
	parts[#parts + 1] = "proj=" .. tostring(WOW_PROJECT_ID)
	parts[#parts + 1] = "exp=" .. tostring(LE_EXPANSION_LEVEL_CURRENT)
	parts[#parts + 1] = "bcc=" .. tostring(WOW_PROJECT_BURNING_CRUSADE_CLASSIC)
	-- Swing-wire receipt (TBC hunter ranged bar, 2026-10-21): per-hand
	-- START/UPDATE/STOP counts plus the last cycle event, in the same shape as
	-- the counters above. Zeros print as zeros, never as blanks.
	local wire = self.swing_wire_counts
	if type(wire) ~= "table" then
		wire = {}
	end
	for _, hand in ipairs({ "mainhand", "offhand", "ranged" }) do
		local h = wire[hand]
		if type(h) ~= "table" then
			h = { start = 0, update = 0, stop = 0 }
		end
		parts[#parts + 1] = "swing_" .. hand .. "="
			.. tostring(h.start or 0) .. "/"
			.. tostring(h.update or 0) .. "/"
			.. tostring(h.stop or 0)
	end
	local last = self.swing_wire_last
	if type(last) == "table" then
		local age = "?"
		local now = GetTime()
		if type(now) == "number" and type(last.t) == "number" then
			age = string.format("%.1f", now - last.t)
		end
		parts[#parts + 1] = "swing_last=" .. tostring(last.kind) .. ":" .. tostring(last.hand) .. ":" .. age .. "s"
	else
		parts[#parts + 1] = "swing_last=none"
	end
	self:Print("diag runtime " .. table.concat(parts, " "))
	if st.swing_source and st.swing_source.available
		and type(st.swing_source.diagnostic_text) == "function" then
		local ok, text = pcall(st.swing_source.diagnostic_text)
		if ok and type(text) == "string" then
			self:Print(text)
		end
	end
end

function ST:register_slashcommands()
	local register_func_string = "open_menu"
	self:RegisterChatCommand("st", register_func_string)
	self:RegisterChatCommand("swedgetimer", register_func_string)
	self:RegisterChatCommand("test1", "test1")
end

function ST:test1()
end

function ST:open_menu(input)
	-- AceConsole passes the raw input: no argument opens the options menu,
	-- "practice" toggles the Twist Practice session, "design" toggles design mode,
	-- "diag" prints the verbose diagnostic report, anything else prints usage.
	local arg = input and input:match("^%s*(.-)%s*$") or ""
	arg = arg:lower()
	if arg == "" then
		local ACD = LibStub("AceConfigDialog-3.0")
		ACD:Open(addon_name.."_Options")
	elseif arg == "practice" then
		if st.practice_ui then
			st.practice_ui.toggle(self)
		else
			self:Print("Practice mode is not available on this client.")
		end
	elseif arg == "design" then
		if st.designmode then
			-- Never in combat: design mode refuses under lockdown itself (no protected
			-- calls anywhere in its path).
			st.designmode.toggle(self)
		else
			self:Print("Design mode is not available on this client.")
		end
	elseif arg == "diag" then
		if st.diag then
			st.diag.report(self, true)
			self:print_runtime_diag()
		else
			self:Print("Diagnostics are not available on this client.")
		end
	else
		self:Print("Unknown argument '" .. arg .. "'. Usage: /st practice to toggle practice mode, /st design to toggle design mode, /st diag for a diagnostic report, /st to open options.")
	end
end

--=========================================================================================
-- Funcs to apply per-class settings
--=========================================================================================
function ST:class_on_aura_change()
	local c = self.player_class
	if self[c].on_aura_change then
		self[c].on_aura_change(self)
	end
end

function ST:class_on_current_spell_cast_changed(is_cancelled)
	local c = self.player_class
	if self[c].on_current_spell_cast_changed then
		self[c].on_current_spell_cast_changed(self, is_cancelled)
	end
end

function ST:class_on_spellcast_event(event, unit_id, cast_guid, spell_id)
	-- Player spellcast lifecycle dispatch for the class modules (weave assist and
	-- friends). Nilable cast_guid/spell_id are passed through untouched.
	if unit_id ~= "player" then
		return
	end
	local c = self.player_class
	if self[c].on_spellcast_event then
		self[c].on_spellcast_event(self, event, unit_id, cast_guid, spell_id)
	end
end

--=========================================================================================
-- For debug and lua syntax errors
--=========================================================================================
if st.debug then st.utils.print_msg('-- Parsed main1.lua module correctly') end
