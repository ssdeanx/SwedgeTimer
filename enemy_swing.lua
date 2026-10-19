--=========================================================================================
-- Enemy swing bar: the current hostile target's mainhand swing timer.
--
-- WHAT IT IS: a small bar under the mainhand swing bar that fills from the tracked
-- enemy's observed mainhand swing toward its next expected one, with the remaining
-- seconds as text. Ported from the read-only SuperSwingTimer reference
-- (SuperSwingTimer-WoW; read-only, never shipped):
--   * target identity/refresh   SuperSwingTimer_State.lua:494-564 (HasAttackableTarget,
--     GetEnemySwingSpeed, RefreshEnemyTarget)
--   * swing start + speed       SuperSwingTimer_State.lua:765-830 (StartSwing's enemy
--     branch and StartEnemySwing: live UnitAttackSpeed("target") > cached speed > 2.0)
--   * combat-log attribution    SuperSwingTimer_State.lua:1272-1302 (SWING_DAMAGE's
--     isOffHand is payload arg 21, SWING_MISSED's is arg 13; off-hand hits are ignored)
--     and :1373-1379 (UNIT_DIED / UNIT_DESTROYED clears the tracked target)
--   * mid-cycle speed rescale   SuperSwingTimer_State.lua:1225-1239 (RescaleTimer)
--   * visibility + combat exit  SuperSwingTimer_UI.lua:2378 (visible only in combat with
--     a tracked hostile target) and SuperSwingTimer.lua:1689-1717 (regen-enabled clears
--     the cycle)
--
-- FAMILY GATE: the bar is driven by the classic combat log (CLEU SWING_DAMAGE /
-- SWING_MISSED), so it arms only on the classic-line families (ERA, TBC, WRATH, CATA,
-- MISTS). WoW Forever is Mainline-code with no classic combat log and Retail runs the
-- inert stand-in engine, so both must stay inert there: no frame, no event, no read -
-- the feature degrades to hidden cleanly. The gate is a pure function of st.family from
-- compat.lua plus the C_EventUtils validity probe where the client exposes one; it never
-- leans on a Mainline-code boolean alone (the Forever lesson: that client is
-- Mainline-code but must behave like classic-line where swing features are concerned).
--
-- DEFAULT OFF: the feature reads ST.db.profile.enemy_swing_enabled and only an explicit
-- true arms it; nil (missing addon/db/profile/key) reads as off. The options pass adds
-- the widget and the shipped default (documented in bench/buildout_enemy-swing_2026-10-17.md).
--
-- SELF-WIRING: no lane in this round may edit main.lua, so unlike the class-driven UI
-- modules (hunter_ui / nextaction_ui are initialised from classes/*.lua's post_init)
-- this module owns its own driver frame and registers its own events. The addon object
-- is fetched lazily through LibStub at event time, so the module is load-order
-- independent: its toc line sits right after swing_source.lua, before utils.lua/main.lua.
--
-- OFFLINE-VERIFIED: the pure helpers and the event-driven state machine are unit-tested
-- by tests/enemy_swing_state.lua (sandboxed frames, stubbed api). IN-CLIENT CONFIRMATION
-- NEEDED for: the bar's placement/size/colours under a real bar stack, the label text,
-- and UnitAttackSpeed("target") fidelity on each classic family.
--=========================================================================================
local addon_name, st = ...

st.enemy_swing = st.enemy_swing or {}
local enemy_swing = st.enemy_swing

--------------------------------------------------------------------------------
-- Pure helpers (WoW-free by design, like twist.lua / weave.lua / hunter_window.lua):
-- no WoW globals, no clock reads, every timestamp arrives as an argument in the
-- api.get_time() (seconds) domain. Unit-tested by tests/enemy_swing_state.lua.
--------------------------------------------------------------------------------

-- The families whose clients carry the classic combat log. FOREVER and RETAIL are
-- Mainline-code (no classic combat log at all); UNKNOWN has no evidence either way.
local CLEU_FAMILIES = { ERA = true, TBC = true, WRATH = true, CATA = true, MISTS = true }

-- Whether the enemy swing bar may arm on a client family: classic-line families only.
-- Never keyed off a version string or a Mainline-code boolean.
function enemy_swing.family_supported(family)
    return CLEU_FAMILIES[family] == true
end

-- Combat-log payload positions (1-based) inside CombatLogGetCurrentEventInfo()'s return
-- tuple, matching the reference's unpack at SuperSwingTimer_State.lua:1281:
--   1 timestamp, 2 subevent, 3 hideCaster, 4 sourceGUID, ..., 8 targetGUID,
--   21 SWING_DAMAGE isOffHand, 13 SWING_MISSED isOffHand.
-- Named constants so the runtime extraction and the offline suite share one source.
enemy_swing.CLEU_SUBEVENT_INDEX = 2
enemy_swing.CLEU_SOURCE_GUID_INDEX = 4
enemy_swing.CLEU_TARGET_GUID_INDEX = 8
enemy_swing.SWING_DAMAGE_OFFHAND_INDEX = 21
enemy_swing.SWING_MISSED_OFFHAND_INDEX = 13

-- Which hand a swing subevent reports, from its off-hand flag: only an explicit true
-- reads as off-hand (the reference's `if not isOffHandAttack` treats nil and false
-- alike), and any other subevent reports nil so the caller ignores it in one compare.
function enemy_swing.swing_hand(subevent, is_offhand)
    if subevent ~= "SWING_DAMAGE" and subevent ~= "SWING_MISSED" then
        return nil
    end
    if is_offhand == true then
        return "offhand"
    end
    return "mainhand"
end

-- Whether a combat-log source is the tracked enemy: both GUIDs must be non-empty strings
-- and equal. The reference compares `sourceGUID == currentEnemyGUID` behind a non-nil
-- gate (SuperSwingTimer_State.lua:1288-1290); a nil, empty or non-string reading must
-- never match.
function enemy_swing.source_is_tracked(source_guid, tracked_guid)
    return type(source_guid) == "string" and source_guid ~= ""
        and type(tracked_guid) == "string" and tracked_guid ~= ""
        and source_guid == tracked_guid
end

-- Whether the current target should be tracked: it exists, the player can attack it, and
-- its GUID is a known string (reference HasAttackableTarget,
-- SuperSwingTimer_State.lua:494-502, plus a string guard so a restricted or missing GUID
-- reads as unknown).
function enemy_swing.should_track_target(exists, can_attack, guid)
    if exists ~= true then
        return false
    end
    if can_attack ~= true then
        return false
    end
    return type(guid) == "string" and guid ~= ""
end

-- The fallback cycle length when neither a live reading nor a cached speed exists: the
-- reference's 2.0 (SuperSwingTimer_State.lua:790).
enemy_swing.FALLBACK_SPEED = 2.0

-- Where a cycle's speed came from. Rendered differently (M7): a fallback cycle is an
-- estimate, so the bar dims it and shows the target name instead of a fake countdown.
enemy_swing.SPEED_SOURCE_LIVE = "live"
enemy_swing.SPEED_SOURCE_CACHED = "cached"
enemy_swing.SPEED_SOURCE_FALLBACK = "fallback"

-- Resolve the cycle length and its provenance: a usable positive live reading wins,
-- else the last cycle's speed, else the 2.0 fallback (same precedence as the
-- reference's enemy branch, SuperSwingTimer_State.lua:788-790).
function enemy_swing.resolve_speed_with_source(reading, previous_speed)
    if type(reading) == "number" and reading > 0 then
        return reading, enemy_swing.SPEED_SOURCE_LIVE
    end
    if type(previous_speed) == "number" and previous_speed > 0 then
        return previous_speed, enemy_swing.SPEED_SOURCE_CACHED
    end
    return enemy_swing.FALLBACK_SPEED, enemy_swing.SPEED_SOURCE_FALLBACK
end

-- Speed-only form kept for callers/tests that do not care about provenance.
function enemy_swing.resolve_speed(reading, previous_speed)
    local speed = enemy_swing.resolve_speed_with_source(reading, previous_speed)
    return speed
end

-- A cycle is { start = <seconds in the api.get_time() domain>, speed = <cycle length>,
-- source = "live" | "cached" | "fallback" }. New cycle from a swing landing at `start`
-- with `speed` seconds; nil when either value is unusable, so a caller can never arm a
-- cycle on a bad read.
function enemy_swing.new_cycle(start, speed, source)
    if type(start) ~= "number" or type(speed) ~= "number" or speed <= 0 then
        return nil
    end
    return { start = start, speed = speed, source = source }
end

-- Progress fraction in [0, 1] at `now`: 0 at the observed swing, 1 at the next expected
-- one. Clamped at both edges (clock skew and a stalled cycle both read the nearer edge);
-- nil for an unusable cycle or clock so the caller can fall back instead of guessing.
function enemy_swing.cycle_progress(cycle, now)
    if type(cycle) ~= "table" or type(cycle.start) ~= "number"
        or type(cycle.speed) ~= "number" or cycle.speed <= 0 or type(now) ~= "number" then
        return nil
    end
    local elapsed = now - cycle.start
    if elapsed < 0 then
        elapsed = 0
    end
    local progress = elapsed / cycle.speed
    if progress > 1 then
        progress = 1
    end
    return progress
end

-- Remaining seconds until the next expected swing, clamped at 0; nil for an unusable
-- cycle or clock.
function enemy_swing.cycle_remaining(cycle, now)
    if type(cycle) ~= "table" or type(cycle.start) ~= "number"
        or type(cycle.speed) ~= "number" or cycle.speed <= 0 or type(now) ~= "number" then
        return nil
    end
    local remaining = cycle.start + cycle.speed - now
    if remaining < 0 then
        remaining = 0
    end
    return remaining
end

-- Rescale a live cycle to a new speed, keeping the remaining time proportional
-- (reference RescaleTimer, SuperSwingTimer_State.lua:1225-1239): a change under 0.01 s
-- returns the same cycle table (no-op), anything else returns a fresh cycle. nil when
-- the inputs are unusable, so the caller keeps its current cycle.
function enemy_swing.rescale_cycle(cycle, new_speed, now)
    if type(cycle) ~= "table" or type(cycle.start) ~= "number"
        or type(cycle.speed) ~= "number" or cycle.speed <= 0 then
        return nil
    end
    if type(new_speed) ~= "number" or new_speed <= 0 or type(now) ~= "number" then
        return nil
    end
    if math.abs(cycle.speed - new_speed) < 0.01 then
        return cycle
    end
    local remaining = cycle.start + cycle.speed - now
    if remaining < 0 then
        remaining = 0
    end
    local new_remaining = remaining * (new_speed / cycle.speed)
    return { start = now + new_remaining - new_speed, speed = new_speed }
end

-- Whether the bar should be visible right now: the toggle is on, a hostile target is
-- tracked, and the player is in combat (reference ApplyVisibility,
-- SuperSwingTimer_UI.lua:2378). A pure function so the matrix is unit-tested directly.
function enemy_swing.should_show(enabled, tracked_guid, in_combat)
    return enabled == true
        and type(tracked_guid) == "string" and tracked_guid ~= ""
        and in_combat == true
end

--------------------------------------------------------------------------------
-- Frame geometry and colours (px, 0-1 texture colours). Fixed defaults for this round;
-- the options pass adds live width/position settings and the design-mode pass may make
-- the bar draggable. IN-CLIENT CONFIRMATION NEEDED for the exact placement under a
-- real bar stack.
--------------------------------------------------------------------------------

enemy_swing.BAR_WIDTH = 200
enemy_swing.BAR_HEIGHT = 10
enemy_swing.BAR_GAP = 2
enemy_swing.BAR_PADDING = 1
enemy_swing.BAR_COLOR = { 1.0, 0.0, 0.0, 1.0 }   -- reference enemy colour (Constants.lua:979)
enemy_swing.BG_COLOR = { 0.0, 0.0, 0.0, 0.6 }
enemy_swing.TEXT_COLOR = { 1.0, 1.0, 1.0, 1.0 }

--------------------------------------------------------------------------------
-- Runtime state (single instance; the offline suite drives it through the event
-- handlers below). `frame` is built lazily once the addon's bar stack exists.
--------------------------------------------------------------------------------

local runtime = {
    tracked_guid = nil,   -- the hostile target's GUID, or nil when untracked
    tracked_name = nil,
    cycle = nil,          -- live swing cycle, or nil before the first observed swing
    in_combat = false,    -- player combat state (PLAYER_REGEN_* + the world-entry probe)
    frame = nil,          -- the bar frame, or nil before it is built
    driver = nil,         -- the always-on event frame
}
enemy_swing.runtime = runtime

-- Pack a multi-return tuple (Lua 5.1 has no table.pack on every client; main.lua defines
-- one only for its own scope). Only used for the combat-log payload, never per frame.
local function pack(...)
    return { n = select("#", ...), ... }
end

-- The feature toggle: only an explicit true arms the bar (nil = off; a missing addon
-- object, db, profile table or key all read as off). Options-pass key:
-- ST.db.profile.enemy_swing_enabled.
function enemy_swing.feature_enabled(ST)
    if type(ST) ~= "table" or type(ST.db) ~= "table" or type(ST.db.profile) ~= "table" then
        return false
    end
    return ST.db.profile.enemy_swing_enabled == true
end

-- The addon object, fetched lazily: this module loads before main.lua creates it (toc
-- order), so nothing may be cached at file scope. nil on any client where the AceAddon
-- registry is not up yet - every caller then degrades to "off" instead of erroring.
local function get_addon()
    local ace_addon = LibStub and LibStub("AceAddon-3.0", true)
    if type(ace_addon) ~= "table" or type(ace_addon.GetAddon) ~= "function" then
        return nil
    end
    return ace_addon:GetAddon(addon_name, true)
end

-- All timestamps live in the api.get_time() domain (the aligned GetTime domain that
-- main.lua/bars.lua compare in). Raw clocks never appear in this module - the clock rule
-- in tests/wiring_check.lua bans them outside compat.lua.
local function now()
    if type(st.api) == "table" and type(st.api.get_time) == "function" then
        return st.api.get_time()
    end
    return nil
end

-- The tracked enemy's live mainhand attack speed through compat's wrapper: a usable
-- positive first return, else nil (reference GetEnemySwingSpeed,
-- SuperSwingTimer_State.lua:504-519). A nil reading (absent client / restricted value)
-- and a non-positive one degrade alike; callers fall back to the cached speed.
local function read_target_speed()
    if type(st.api) ~= "table" or type(st.api.UnitAttackSpeed) ~= "function" then
        return nil
    end
    local speed = st.api.UnitAttackSpeed("target")
    if type(speed) == "number" and speed > 0 then
        return speed
    end
    return nil
end

-- The live target: GUID + name when it is hostile and tracked-eligible, else nil, nil.
-- UnitExists/UnitCanAttack/UnitGUID/UnitName are read directly (the same guarded
-- classic-client reads weave_range.lua and the class modules use); this module never
-- runs on a Mainline-code family, so the secret-value regime does not apply here.
local function read_target()
    local exists = type(UnitExists) == "function" and UnitExists("target") == true
    local can_attack = type(UnitCanAttack) == "function"
        and UnitCanAttack("player", "target") == true
    local guid
    if type(UnitGUID) == "function" then
        guid = UnitGUID("target")
    end
    if not enemy_swing.should_track_target(exists, can_attack, guid) then
        return nil, nil
    end
    local name
    if type(UnitName) == "function" then
        name = UnitName("target")
    end
    if type(name) ~= "string" or name == "" then
        name = nil
    end
    return guid, name
end

-- Re-read the current target. Returns true when the tracked GUID changed (a new target
-- or the target clearing), after dropping the cycle; a same-GUID refresh only updates
-- the name (reference RefreshEnemyTarget, SuperSwingTimer_State.lua:521-564).
function enemy_swing.refresh_target()
    local guid, name = read_target()
    if guid == runtime.tracked_guid then
        if name ~= nil then
            runtime.tracked_name = name
        end
        return false
    end
    runtime.tracked_guid = guid
    runtime.tracked_name = name
    runtime.cycle = nil
    return true
end

-- Start (or restart) the cycle from an observed mainhand swing: the cycle length is the
-- live reading, else the previous cycle's speed, else the 2.0 fallback (reference
-- StartSwing's enemy branch, SuperSwingTimer_State.lua:788-791). `now_seconds` is
-- optional; without it the api clock is read.
function enemy_swing.start_cycle(now_seconds)
    local t = now_seconds
    if type(t) ~= "number" then
        t = now()
    end
    if type(t) ~= "number" then
        return nil
    end
    local previous_speed = runtime.cycle and runtime.cycle.speed or nil
    local speed, source = enemy_swing.resolve_speed_with_source(
        read_target_speed(), previous_speed)
    runtime.cycle = enemy_swing.new_cycle(t, speed, source)
    return runtime.cycle
end

--------------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------------

-- Build the bar frame lazily. It parents to the mainhand bar frame - the existing layout
-- hook the hunter cast bar (hunter_ui.lua:131-145) and the paladin sidebars
-- (classes/paladin.lua:1085-1088) use - so it follows the swing stack's position and
-- scale, and hides whenever that bar hides. No frame is ever built while the addon's
-- bars are not up (pcall around the getter), and none is ever built off-family (the
-- driver only exists there, and nothing else calls this).
function enemy_swing.ensure_frame(ST)
    if runtime.frame then
        return runtime.frame
    end
    if type(CreateFrame) ~= "function" then
        return nil
    end
    if type(ST) ~= "table" or type(ST.get_bar_frame) ~= "function" then
        return nil
    end
    local ok, bar_frame = pcall(ST.get_bar_frame, ST, "mainhand")
    if not ok or bar_frame == nil then
        return nil
    end

    local frame = CreateFrame("Frame", addon_name .. "EnemySwingBar", bar_frame)
    frame:SetSize(enemy_swing.BAR_WIDTH, enemy_swing.BAR_HEIGHT)
    frame:SetPoint("TOP", bar_frame, "BOTTOM", 0, -enemy_swing.BAR_GAP)
    frame:SetFrameLevel(bar_frame:GetFrameLevel() + 2)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    frame.bg:SetColorTexture(unpack(enemy_swing.BG_COLOR))

    frame.bar = frame:CreateTexture(nil, "ARTWORK")
    frame.bar:SetPoint("TOPLEFT", frame, "TOPLEFT",
        enemy_swing.BAR_PADDING, -enemy_swing.BAR_PADDING)
    frame.bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",
        enemy_swing.BAR_PADDING, enemy_swing.BAR_PADDING)
    frame.bar:SetColorTexture(unpack(enemy_swing.BAR_COLOR))

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.text:SetJustifyH("CENTER")
    frame.text:SetTextColor(unpack(enemy_swing.TEXT_COLOR))
    frame.text:SetShadowColor(0, 0, 0, 1)
    frame.text:SetShadowOffset(1, -1)

    frame:SetScript("OnUpdate", enemy_swing.on_update)
    frame:Hide()

    runtime.frame = frame
    return frame
end

--------------------------------------------------------------------------------
-- Show/hide gate and painting
--------------------------------------------------------------------------------

-- Apply the visibility rule to the frame (build it first if the toggle is on). Reads
-- the toggle itself so a disabled feature also hides a bar that was shown before the
-- toggle flipped off, on the next event.
function enemy_swing.apply_visibility()
    local ST = get_addon()
    if not enemy_swing.feature_enabled(ST) then
        local frame = runtime.frame
        if frame and frame:IsShown() then
            frame:Hide()
        end
        return
    end
    local frame = enemy_swing.ensure_frame(ST)
    if not frame then
        return
    end
    if enemy_swing.should_show(true, runtime.tracked_guid, runtime.in_combat) then
        if not frame:IsShown() then
            frame:Show()
        end
    elseif frame:IsShown() then
        frame:Hide()
    end
end

-- One paint: the fill width tracks the cycle progress and the text shows the remaining
-- seconds while a measured cycle is live, else the target name ("Enemy" when unknown).
-- A fallback-speed cycle (M7) is dimmed and shows the target name instead of a fake
-- countdown. When the clock is unavailable the bar hides rather than freezing on stale
-- paint. The text latches its quantised tenth so an unchanged frame costs no string
-- churn; the fill is cheap enough to repaint every tick (bars.lua repaints its fill per
-- frame the same way).
function enemy_swing.on_update()
    local frame = runtime.frame
    if not frame then
        return
    end
    local t = now()
    if t == nil then
        -- A dead clock cannot advance the fill: hide instead of leaving the last frame
        -- painted forever. The next event re-applies visibility when the clock is back.
        frame:Hide()
        return
    end
    local cycle = runtime.cycle
    local progress = enemy_swing.cycle_progress(cycle, t)
    if progress == nil then
        progress = 0
    end
    local fallback = cycle ~= nil and cycle.source == enemy_swing.SPEED_SOURCE_FALLBACK
    if frame._fallback_render ~= fallback then
        frame._fallback_render = fallback
        if fallback then
            local color = enemy_swing.BAR_COLOR
            frame.bar:SetColorTexture(color[1], color[2], color[3], 0.35)
        else
            frame.bar:SetColorTexture(unpack(enemy_swing.BAR_COLOR))
        end
    end
    local inner_width = enemy_swing.BAR_WIDTH - (enemy_swing.BAR_PADDING * 2)
    frame.bar:SetWidth(math.max(1, inner_width * progress))
    frame.bar:SetTexCoord(0, progress, 0, 1)

    local remaining = enemy_swing.cycle_remaining(cycle, t)
    if remaining ~= nil and not fallback then
        local tenth = math.floor(remaining * 10 + 0.5)
        if frame._text_tenth ~= tenth then
            frame._text_tenth = tenth
            frame._name_value = nil
            frame.text:SetText(string.format("%.1f", remaining))
        end
    else
        local name = runtime.tracked_name or "Enemy"
        if frame._name_value ~= name then
            frame._name_value = name
            frame._text_tenth = nil
            frame.text:SetText(name)
        end
    end
end

--------------------------------------------------------------------------------
-- Event handlers (driven by the driver frame below; the offline suite calls them
-- directly). Every handler is nil-safe and cheap when the feature is off.
--------------------------------------------------------------------------------

function enemy_swing.on_player_entering_world()
    if not enemy_swing.active then
        return
    end
    -- A reload/zone change drops any in-flight cycle and the previous target.
    runtime.cycle = nil
    runtime.tracked_guid = nil
    runtime.tracked_name = nil
    runtime.in_combat = false
    if type(UnitAffectingCombat) == "function" then
        runtime.in_combat = UnitAffectingCombat("player") == true
    end
    if enemy_swing.feature_enabled(get_addon()) then
        enemy_swing.refresh_target()
    end
    enemy_swing.apply_visibility()
end

function enemy_swing.on_target_changed()
    if not enemy_swing.active then
        return
    end
    if enemy_swing.feature_enabled(get_addon()) then
        enemy_swing.refresh_target()
    end
    enemy_swing.apply_visibility()
end

function enemy_swing.on_combat_state(in_combat)
    if not enemy_swing.active then
        return
    end
    runtime.in_combat = in_combat == true
    if not runtime.in_combat then
        -- Combat exit ends the cycle (reference ResetTimer("enemy") on
        -- PLAYER_REGEN_ENABLED, SuperSwingTimer.lua:1689-1717).
        runtime.cycle = nil
    end
    enemy_swing.apply_visibility()
end

-- UNIT_ATTACK_SPEED: re-read the tracked target's speed and rescale an in-flight cycle
-- proportionally (reference SyncMeleeTimerSpeed + RescaleTimer,
-- SuperSwingTimer_State.lua:666-684, :1225-1239). The event can carry any unit token;
-- the re-read is target-specific and an unchanged reading is a no-op, so no unit filter
-- is needed.
function enemy_swing.on_unit_attack_speed()
    if not enemy_swing.active then
        return
    end
    if not enemy_swing.feature_enabled(get_addon()) then
        return
    end
    if runtime.tracked_guid == nil or runtime.cycle == nil then
        return
    end
    local speed = read_target_speed()
    if speed == nil then
        return
    end
    local t = now()
    if t == nil then
        return
    end
    local rescaled = enemy_swing.rescale_cycle(runtime.cycle, speed, t)
    if rescaled ~= nil then
        -- A usable live reading upgrades the cycle's provenance even when the value
        -- matches the previous estimate (M7: measured vs fallback rendering).
        rescaled.source = enemy_swing.SPEED_SOURCE_LIVE
        runtime.cycle = rescaled
    end
end

-- COMBAT_LOG_EVENT_UNFILTERED: only the tracked enemy's mainhand SWING_DAMAGE /
-- SWING_MISSED start a cycle (reference HandleCLEU, SuperSwingTimer_State.lua:1272-1302);
-- a UNIT_DIED / UNIT_DESTROYED of the tracked target clears it (State.lua:1373-1379).
-- The payload arrives through compat's wrapper, which reports nil on clients without the
-- classic combat log - a nil/absent payload is ignored, never an error. The toggle is
-- checked before the payload is read: CLEU is the hot path (hundreds of events a second
-- in a raid) and a disabled feature must cost one db read, not a parse.
function enemy_swing.on_combat_log_event()
    if not enemy_swing.active then
        return
    end
    if not enemy_swing.feature_enabled(get_addon()) then
        return
    end
    if type(st.api) ~= "table"
        or type(st.api.CombatLogGetCurrentEventInfo) ~= "function" then
        return
    end
    local payload = pack(st.api.CombatLogGetCurrentEventInfo())
    local subevent = payload[enemy_swing.CLEU_SUBEVENT_INDEX]
    if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
        if enemy_swing.source_is_tracked(payload[enemy_swing.CLEU_TARGET_GUID_INDEX],
            runtime.tracked_guid) then
            runtime.tracked_guid = nil
            runtime.tracked_name = nil
            runtime.cycle = nil
            enemy_swing.apply_visibility()
        end
        return
    end
    if not enemy_swing.source_is_tracked(payload[enemy_swing.CLEU_SOURCE_GUID_INDEX],
        runtime.tracked_guid) then
        return
    end
    local is_offhand
    if subevent == "SWING_DAMAGE" then
        is_offhand = payload[enemy_swing.SWING_DAMAGE_OFFHAND_INDEX]
    elseif subevent == "SWING_MISSED" then
        is_offhand = payload[enemy_swing.SWING_MISSED_OFFHAND_INDEX]
    else
        return
    end
    if enemy_swing.swing_hand(subevent, is_offhand) ~= "mainhand" then
        return
    end
    enemy_swing.start_cycle(now())
end

--------------------------------------------------------------------------------
-- Driver frame: created once at load, only on a classic-line family. Off-family the
-- module stays completely inert: no frame, no event registration, no reads.
--------------------------------------------------------------------------------

enemy_swing.active = false

-- Event-validity probe: where the client exposes C_EventUtils, the probe has the final
-- say (mirrors swing_source.lua's is_event_valid discipline); without it the family
-- gate above already decided.
local function is_event_valid(event_name)
    if C_EventUtils ~= nil and C_EventUtils.IsEventValid ~= nil then
        return C_EventUtils.IsEventValid(event_name) == true
    end
    return true
end

if enemy_swing.family_supported(st.family)
    and is_event_valid("COMBAT_LOG_EVENT_UNFILTERED")
    and type(CreateFrame) == "function" then
    local driver = CreateFrame("Frame", addon_name .. "EnemySwingDriver")
    runtime.driver = driver
    local driver_events = {
        "PLAYER_ENTERING_WORLD",
        "PLAYER_TARGET_CHANGED",
        "UNIT_ATTACK_SPEED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "COMBAT_LOG_EVENT_UNFILTERED",
    }
    for i = 1, #driver_events do
        driver:RegisterEvent(driver_events[i])
    end
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            enemy_swing.on_player_entering_world()
        elseif event == "PLAYER_TARGET_CHANGED" then
            enemy_swing.on_target_changed()
        elseif event == "UNIT_ATTACK_SPEED" then
            enemy_swing.on_unit_attack_speed()
        elseif event == "PLAYER_REGEN_DISABLED" then
            enemy_swing.on_combat_state(true)
        elseif event == "PLAYER_REGEN_ENABLED" then
            enemy_swing.on_combat_state(false)
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            enemy_swing.on_combat_log_event()
        end
    end)
    enemy_swing.active = true
end
