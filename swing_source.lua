--=========================================================================================
-- Swing source for WoW Forever (PLAYER_SWING)
--
-- WoW Forever is a Mainline-code client: it has no classic combat log, so the vendored
-- LibClassicSwingTimerAPI is not shipped there (see the _Mainline TOC). The client does
-- expose PLAYER_SWING, documented in the forever UI source
-- (origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/
-- SwingTimerDocumentation.lua:43-52):
--   PLAYER_SWING(swingDuration:number, swingType:Enum.PlayerSwingType), SynchronousEvent
--   Enum.PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } (:71-82)
-- and Blizzard's own swing timer reads it the same way this module does
-- (origin/forever:Interface/AddOns/Blizzard_SwingTimer/Blizzard_SwingTimer.lua):
--   :141-161  the event arms (PLAYER_SWING starts a cycle, WEAPON_SLOT_CHANGED
--             restarts it at the equipped duration, combat/target/range arms only
--             touch presentation)
--   :184-192  GetEquippedSwingDuration reads all three UnitAttackSpeed returns
--   :319-330  ResetSwingTimerForEquippedWeapon restarts the live cycle on a swap
--
-- This module mirrors the surface main.lua consumes from the classic library -
-- SwingTimerInfo(hand) and the CallbackHandler Register/UnregisterCallback pair firing
-- the SWING_TIMER_* events with the library's exact argument order - so the existing
-- swing machinery (register_timer_callbacks, init_timers/SwingTimerInfo, the init
-- deadline rescue) runs unchanged on Forever. Classic-line clients keep using the
-- vendored library; this source only reports itself available on the FOREVER family
-- and stays inert everywhere else.
--
-- TOC order: compat.lua -> swing_source.lua -> main.lua (main.lua reads
-- st.swing_source.available while it loads, and st.family comes from compat.lua).
--=========================================================================================
local _, st = ...

local swing_source = {}
st.swing_source = swing_source

-- See compat.lua: a restricted (secret) attack-speed read must degrade to "no update"
-- with the in-flight cycles keeping their schedules, never to an error. Exact no-op
-- where the probe is absent (every non-Mainline client, where this module is inert).
local is_secret = issecretvalue or function()
	return false
end

-- Same callback mechanics as the library: LibClassicSwingTimerAPI embeds
-- LibStub("CallbackHandler-1.0"):New(lib), and the registry fires a function callback
-- as method(eventname, ...) - exactly the shape main.lua's callback_event_handler
-- expects. Using the same CallbackHandler keeps Register/Unregister semantics identical.
local callbacks = LibStub("CallbackHandler-1.0"):New(swing_source)

--------------------------------------------------------------------------------
-- Availability
--------------------------------------------------------------------------------

local function can_probe_events()
	return C_EventUtils ~= nil and C_EventUtils.IsEventValid ~= nil
end

-- The guarded pattern main.lua uses for PLAYER_TARGET_SET_ATTACKING: assume from the
-- family, downgrade when the event-validity probe says no. Without C_EventUtils there
-- is nothing to probe with, so the FOREVER family alone decides (WoW Forever is the
-- only family documented to have PLAYER_SWING, and on every other family the vendored
-- library - or the inert stub in main.lua - is the engine, so this one stays inert).
local function is_event_valid(event_name)
	if can_probe_events() then
		return C_EventUtils.IsEventValid(event_name) == true
	end
	return st.family == "FOREVER"
end

swing_source.available = (st.family == "FOREVER" or rawget(_G, "C_SwingTimer") ~= nil) and is_event_valid("PLAYER_SWING")

--------------------------------------------------------------------------------
-- Clock
--------------------------------------------------------------------------------

-- All timestamps must live in the GetTime() domain that main.lua/bars.lua compare
-- against. Prefer compat.lua's aligned high-precision clock when present (it folds
-- GetTimePreciseSec into the GetTime domain); raw GetTimePreciseSec is a different,
-- unaligned domain and must never be used directly here.
local function now()
	if st.api and st.api.get_time then
		return st.api.get_time()
	end
	return GetTime()
end

--------------------------------------------------------------------------------
-- Cycle state
--------------------------------------------------------------------------------

local HANDS = { "mainhand", "offhand", "ranged" }

-- Extra time after a swing's nominal end before the cycle is declared over: the next
-- PLAYER_SWING normally lands first and supersedes the scheduled stop.
local STOP_GRACE_SECONDS = 0.1

-- Sustained-reject notice threshold: combat + no valid swing for this long while the
-- feed keeps rejecting payloads means the bars are stale, so say so once (H5).
local SUSTAINED_REJECT_SECONDS = 5

-- Session counters for /st diag (H5). The reject paths keep their existing behaviour
-- (ignore the payload, keep the old cycle); these only make the failure observable.
-- A-1 (2026-11-06): speed_fallbacks counts the cycles RECOVERED from the equipped speed
-- when the payload duration was restricted/malformed, and first_reject_notice_shown
-- latches the once-per-session notice that makes a single dropped payload observable.
local stats = {
	payload_rejects = 0,
	unknown_swing_type = 0,
	malformed_duration = 0,
	speed_fallbacks = 0,
	speed_read_keeps = 0,
	valid_swings = 0,
	last_valid_swing_at = nil,
	first_reject_at = nil,
	reject_notice_shown = false,
	first_reject_notice_shown = false,
	in_combat = false,
}
swing_source.stats = stats

local function print_notice(message)
	if st.utils and type(st.utils.print_msg) == "function" then
		pcall(st.utils.print_msg, message)
	end
end

-- Record one rejected payload, and raise the one-time chat notice when the reject has
-- lasted SUSTAINED_REJECT_SECONDS in combat. The counters are always written first so
-- /st diag can explain the state even when the notice has been dismissed.
-- A-1 (2026-11-06): a SINGLE rejected payload is a real user-visible event on this
-- client ("one shot consumed") and the sustained notice cannot see it, so the first
-- reject of the session is announced immediately - once, at payload speed. The
-- sustained notice keeps its own latch for the feed-wide case.
local function note_payload_reject()
	stats.payload_rejects = stats.payload_rejects + 1
	-- The single-reject notice is clock-free and latched first: even a broken clock must
	-- not make the one user-visible signal disappear.
	if not stats.first_reject_notice_shown then
		stats.first_reject_notice_shown = true
		print_notice("The Forever swing feed rejected a PLAYER_SWING payload; one swing "
			.. "cycle could not be displayed (the next cycle recovers). /st diag reports "
			.. "the counts.")
	end
	local t = now()
	if type(t) ~= "number" then
		return
	end
	if stats.first_reject_at == nil then
		stats.first_reject_at = t
	end
	if stats.in_combat and not stats.reject_notice_shown then
		local reference = stats.last_valid_swing_at or stats.first_reject_at
		if type(reference) == "number" and t - reference >= SUSTAINED_REJECT_SECONDS then
			stats.reject_notice_shown = true
			print_notice("The Forever swing feed has rejected PLAYER_SWING payloads for "
				.. SUSTAINED_REJECT_SECONDS
				.. "+ seconds; the swing bars may be stale. /st diag reports the counts.")
		end
	end
end

-- hand -> { counter, start, speed, expiration } while a swing is in flight. Counters
-- only ever increase, so a scheduled stop fires only while its counter is still the
-- live cycle's - supersession without any timer-cancel machinery.
local active_cycles = {}
local cycle_counters = { mainhand = 0, offhand = 0, ranged = 0 }

local function begin_cycle(hand, start_time, speed)
	cycle_counters[hand] = (cycle_counters[hand] or 0) + 1
	local cycle = {
		counter = cycle_counters[hand],
		start = start_time,
		speed = speed,
		expiration = start_time + speed,
	}
	active_cycles[hand] = cycle
	return cycle
end

local function clear_cycle(hand)
	active_cycles[hand] = nil
end

local function fire_stop_if_current(hand, counter)
	local cycle = active_cycles[hand]
	if cycle and cycle.counter == counter then
		clear_cycle(hand)
		callbacks:Fire("SWING_TIMER_STOP", hand)
	end
end

--------------------------------------------------------------------------------
-- Swing type -> hand
--------------------------------------------------------------------------------

-- Enum.PlayerSwingType is the documented source; the numeric table mirrors its
-- MainHand=0 / OffHand=1 / Ranged=2 values and covers clients where Enum is missing.
local swing_type_hands = {
	[0] = "mainhand",
	[1] = "offhand",
	[2] = "ranged",
}

local function hand_for_swing_type(swing_type)
	if type(swing_type) ~= "number" then
		return nil
	end
	local swing_enum = Enum and Enum.PlayerSwingType
	if swing_enum then
		if swing_type == swing_enum.MainHand then
			return "mainhand"
		elseif swing_type == swing_enum.OffHand then
			return "offhand"
		elseif swing_type == swing_enum.Ranged then
			return "ranged"
		end
	end
	return swing_type_hands[swing_type]
end

--------------------------------------------------------------------------------
-- Event handling
--------------------------------------------------------------------------------

-- Restricted (secret) payload arguments (A-1, 2026-11-06): a secret number/boolean
-- passes every type() check and raises on the first comparison, so it must be probed
-- BEFORE any branch - otherwise the throw escapes OnEvent and one shot is lost with no
-- counter. Normalised to a plain boolean so the caller never handles an opaque value.
local function is_restricted(value)
	return is_secret(value) and true or false
end

-- One usable positive swing duration, or nil. A restricted, non-numeric, non-finite or
-- non-positive value is "cannot be timed" - and is never compared while restricted.
local function usable_duration(value)
	if is_secret(value) then
		return nil
	end
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value <= 0 then
		return nil
	end
	return value
end

-- The equipped swing speed for one hand, used to RECOVER a cycle whose PLAYER_SWING
-- duration could not be timed (A-1). The payload only repeats what the client already
-- reports about the equipped weapon, so a restricted/malformed duration does not mean
-- the swing did not happen - dropping the cycle is what made one shot look "consumed".
-- Same two documented sources the module already reads: UnitAttackSpeed's per-hand
-- returns (Forever returns all three; Blizzard_SwingTimer.lua:184-192) and, for the
-- ranged hand only, UnitRangedDamage's first return. Every read is pcall'd and
-- secret-checked; nothing is invented when neither can answer.
local function read_equipped_speed(hand)
	local speed
	if type(UnitAttackSpeed) == "function" then
		local ok, speeds = pcall(function()
		return { UnitAttackSpeed("player") }
	end)
	if ok and type(speeds) == "table" then
		local main_speed, off_speed, ranged_speed = speeds[1], speeds[2], speeds[3]
		if hand == "offhand" then
			speed = off_speed
		elseif hand == "ranged" then
			speed = ranged_speed
		else
			speed = main_speed
		end
	end
	end
	if is_restricted(speed) or not canaccessvalue(speed) or type(speed) ~= "number" or speed <= 0 then
		if hand == "ranged" and type(UnitRangedDamage) == "function" then
			local ok, damage = pcall(UnitRangedDamage, "player")
			if ok then
				speed = damage
			end
		end
	end
	return usable_duration(speed)
end

local function on_player_swing(swing_duration, swing_type)
	-- A restricted swing type cannot be mapped (comparisons and table indexing on an
	-- opaque value raise), so it is attributed as an unknown type and dropped.
	if is_restricted(swing_type) then
		stats.unknown_swing_type = stats.unknown_swing_type + 1
		note_payload_reject()
		return
	end
	local hand = hand_for_swing_type(swing_type)
	if not hand then
		stats.unknown_swing_type = stats.unknown_swing_type + 1
		note_payload_reject()
		return -- unknown swing type: ignore
	end
	local duration = usable_duration(swing_duration)
	if duration == nil then
		-- Restricted or malformed duration on a KNOWN hand: recover the cycle from the
		-- equipped speed instead of swallowing the shot (A-1). Only a payload with no
		-- readable fallback speed is a counted reject.
		duration = read_equipped_speed(hand)
		if duration == nil then
			stats.malformed_duration = stats.malformed_duration + 1
			note_payload_reject()
			return -- malformed payload with no readable fallback: nothing to time
		end
		stats.speed_fallbacks = stats.speed_fallbacks + 1
	end

	local cycle = begin_cycle(hand, now(), duration)
	stats.valid_swings = stats.valid_swings + 1
	stats.last_valid_swing_at = cycle.start
	stats.first_reject_at = nil
	callbacks:Fire("SWING_TIMER_START", duration, cycle.expiration, hand)

	-- A newer swing bumps the counter, so a superseded stop timer is a no-op.
	C_Timer.After(duration + STOP_GRACE_SECONDS, function()
		fire_stop_if_current(hand, cycle.counter)
	end)
end

local function on_unit_attack_speed(unit)
	-- Unit-filtered: only the player's own speed matters. A nil unit (direct call)
	-- still re-reads; any other unit is noise from an unfiltered registration.
	if unit ~= nil and unit ~= "player" then
		return
	end
	-- WoW Forever returns mainhand, offhand and ranged speeds from UnitAttackSpeed
	-- (Blizzard_SwingTimer.lua reads all three via GetEquippedSwingDuration). Re-read
	-- and update every in-flight cycle whose speed moved. A missing or throwing reader
	-- keeps every cycle on its scheduled speed, like a secret reading does below.
	if type(UnitAttackSpeed) ~= "function" then
		stats.speed_read_keeps = stats.speed_read_keeps + 1
		return
	end
	local results = {pcall(UnitAttackSpeed, "player")}
	local ok = results[1]
	local main_speed = results[2]
	local off_speed = results[3]
	local ranged_speed = results[4]
	if not ok then
		stats.speed_read_keeps = stats.speed_read_keeps + 1
		return
	end
	local speeds = {
		mainhand = main_speed,
		offhand = off_speed,
		ranged = ranged_speed,
	}
	for hand, cycle in pairs(active_cycles) do
		local new_speed = speeds[hand]
		-- Only usable positive readings; a nil/zero read (weapon removed) leaves the
		-- cycle to its scheduled stop.
		local usable = type(new_speed) == "number"
			and not is_secret(new_speed)
			and canaccessvalue(new_speed)
			and new_speed > 0
		if usable and new_speed ~= cycle.speed then
			-- Match the library's attack-speed rescale: the REMAINING time scales by
			-- new/old instead of moving the whole cycle to the new absolute speed.
			local t = now()
			local old_speed = cycle.speed
			local remaining = cycle.expiration - t
			if remaining < 0 then
				remaining = 0
			end
			cycle.speed = new_speed
			cycle.expiration = t + remaining * (new_speed / old_speed)
			callbacks:Fire("SWING_TIMER_UPDATE", cycle.speed, cycle.expiration, hand)
		elseif not usable then
			-- The read could not describe this hand (nil/zero/non-numeric): the cycle
			-- keeps its schedule, and the keep is counted for /st diag (H5).
			stats.speed_read_keeps = stats.speed_read_keeps + 1
		end
	end
end

local function on_weapon_slot_changed()
	-- Mirror Blizzard's own WEAPON_SLOT_CHANGED arm (origin/forever
	-- Blizzard_SwingTimer.lua:151-153 + :319-330): a swap re-reads the equipped
	-- speeds and RESTARTS each live cycle at the newly equipped duration
	-- (ResetSwingTimerForEquippedWeapon -> ResetSwingTimer(GetEquippedSwingDuration)),
	-- and a hand the swap invalidated (no usable speed: weapon removed) ends like a
	-- combat-exit clear. The classic library's equipment path restarts the same way
	-- (LibClassicSwingTimerAPI.lua:732-744, SwingStart(..., true) for all three hands),
	-- so this is also the shape main.lua's handlers already understand (an UPDATE
	-- re-anchors bar.start = expiration - speed, i.e. a full cycle from now).
	-- A swap-clear is not a reject, so the H5 reject counters are untouched.
	if type(UnitAttackSpeed) ~= "function" then
		stats.speed_read_keeps = stats.speed_read_keeps + 1
		return
	end
	local results = {pcall(UnitAttackSpeed, "player")}
	local ok = results[1]
	local main_speed = results[2]
	local off_speed = results[3]
	local ranged_speed = results[4]
	if not ok then
		stats.speed_read_keeps = stats.speed_read_keeps + 1
		return
	end
	local speeds = {
		mainhand = main_speed,
		offhand = off_speed,
		ranged = ranged_speed,
	}
	for i = 1, #HANDS do
		local hand = HANDS[i]
		local cycle = active_cycles[hand]
		if cycle then
			local new_speed = speeds[hand]
			if not is_secret(new_speed) and canaccessvalue(new_speed)
				and type(new_speed) == "number" and new_speed > 0 then
				-- Restart, not rescale: equipping a weapon resets the client's swing
				-- cycle, so the bar must show a full cycle of the equipped speed.
				local t = now()
				cycle.start = t
				cycle.speed = new_speed
				cycle.expiration = t + new_speed
				callbacks:Fire("SWING_TIMER_UPDATE", cycle.speed, cycle.expiration, hand)
			else
				-- No usable speed for this hand after the swap: the cycle is
				-- invalid, so end it like a combat-exit clear. Its scheduled stop
				-- timer then finds no matching cycle and is ignored.
				clear_cycle(hand)
				callbacks:Fire("SWING_TIMER_STOP", hand)
			end
		end
	end
end

local function on_combat_changed(in_combat)
	stats.in_combat = in_combat == true
	if in_combat ~= false then
		return
	end
	-- Leaving combat ends every in-flight cycle; its scheduled stop timer then finds
	-- no matching cycle and is ignored.
	for i = 1, #HANDS do
		local hand = HANDS[i]
		if active_cycles[hand] then
			clear_cycle(hand)
			callbacks:Fire("SWING_TIMER_STOP", hand)
		end
	end
end

local info_initialized = false

local function on_player_entering_world()
	-- A reload/zone change drops any in-flight swings; the counters keep stale stop
	-- timers from matching later cycles. A live cycle is STOPped before it is dropped:
	-- clearing it silently would leave main.lua's bar frozen on a cycle whose scheduled
	-- stop can no longer match (the same contract as the combat-exit clear above).
	for i = 1, #HANDS do
		local hand = HANDS[i]
		if active_cycles[hand] then
			clear_cycle(hand)
			callbacks:Fire("SWING_TIMER_STOP", hand)
		end
	end
	-- One report per session, on the first world entry (main.lua's registration
	-- exists by then).
	if not info_initialized then
		info_initialized = true
		callbacks:Fire("SWING_TIMER_INFO_INITIALIZED")
	end
end

--------------------------------------------------------------------------------
-- Public read API (same contract/shape as LibClassicSwingTimerAPI:SwingTimerInfo)
--------------------------------------------------------------------------------

-- Volatile diagnostic counters for /st diag verbose (H5): rejected payloads, recovered
-- cycles and speed-read keeps. The behaviour they observe is unchanged.
function swing_source:diagnostic_text()
	return string.format(
		"swing source payload_rejects=%d unknown_type=%d malformed_duration=%d"
		.. " speed_fallbacks=%d speed_read_keeps=%d valid_swings=%d notice=%s"
		.. " first_reject_notice=%s",
		stats.payload_rejects,
		stats.unknown_swing_type,
		stats.malformed_duration,
		stats.speed_fallbacks,
		stats.speed_read_keeps,
		stats.valid_swings,
		stats.reject_notice_shown and "shown" or "no",
		stats.first_reject_notice_shown and "shown" or "no")
end

function swing_source:SwingTimerInfo(hand)
	local cycle = active_cycles[hand]
	if cycle then
		return cycle.speed, cycle.expiration, cycle.start
	end
	-- Idle/unknown: mirror main.lua's make_swing_stub() nil-shape (nil, nil, nil);
	-- init_timers turns the nil-shape into the per-hand engine_dead idle path.
	return nil, nil, nil
end

--------------------------------------------------------------------------------
-- Engine frame
--------------------------------------------------------------------------------

if swing_source.available then
	local frame = CreateFrame("Frame", "SwedgeTimer_SwingSourceFrame")
	frame:Hide()

	-- PLAYER_TARGET_CHANGED and PLAYER_SWING_RANGE_UPDATE are deliberately NOT
	-- registered, verified against Blizzard's own engine (origin/forever
	-- Blizzard_SwingTimer.lua:141-161): both are display-only arms - PLAYER_TARGET_CHANGED
	-- calls UpdateRangeState (the out-of-range alpha) and PLAYER_SWING_RANGE_UPDATE calls
	-- SetOutOfRange; neither touches swingDuration/swingEndTime, so neither can start,
	-- retime or end a cycle. The addon's range state comes from main.lua's exact-yard
	-- poll (compat.api.UnitDistance), and PLAYER_SWING_RANGE_UPDATE additionally requires
	-- C_SwingTimer.EnableRangeCheck (SwingTimerDocumentation.lua:11-20), which the addon
	-- does not call. Registering either would be dead wiring.
	local engine_events = {
		"PLAYER_SWING",
		"UNIT_ATTACK_SPEED",
		"WEAPON_SLOT_CHANGED",
		"PLAYER_IN_COMBAT_CHANGED",
		"PLAYER_ENTERING_WORLD",
	}
	for i = 1, #engine_events do
		local event_name = engine_events[i]
		if is_event_valid(event_name) then
			if event_name == "UNIT_ATTACK_SPEED" and frame.RegisterUnitEvent then
				frame:RegisterUnitEvent(event_name, "player")
			else
				frame:RegisterEvent(event_name)
			end
		end
	end

	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "PLAYER_SWING" then
			on_player_swing(...)
		elseif event == "UNIT_ATTACK_SPEED" then
			on_unit_attack_speed(...)
		elseif event == "WEAPON_SLOT_CHANGED" then
			on_weapon_slot_changed()
		elseif event == "PLAYER_IN_COMBAT_CHANGED" then
			on_combat_changed(...)
		elseif event == "PLAYER_ENTERING_WORLD" then
			on_player_entering_world()
		end
	end)
end
