--=========================================================================================
-- Twist Practice: the playable UI for the pure st.practice simulation engine (port phase 2).
--
-- Ported from the archived build's practice UI (docs/swedge/SwedgeTimer_Forever/practice.lua):
--   * control panel        558-914    (panel rows: title, speed/GCD + rotation lines,
--                                      two icon rows, hint, fight timer, fight button,
--                                      Bloodlust/Haste-pot/DST buttons, rotation selector,
--                                      timeline toggle - archive 558-914)
--   * haste buttons        761-796    (Bloodlust/Haste-pot countdown buttons, minus the
--                                      archived sound hook; DST rides a session-local
--                                      toggle since its db option is out of scope)
--   * rotation selector    807-871 + set_locked_rotation 1258-1304 (session-local lock on
--                                      sim.locked_rotation; haste is cleared on lock)
--   * result popup         524-541    + fade 3284-3301 + show_result 3655-3665
--   * result font update   3667-3672
--   * session start/stop   927-1165   (minus the archived hooks into bar/player functions;
--                                      this port mirrors the simulation onto the addon's own
--                                      bar state instead - see sync_to_addon)
--   * start_fight          2807-2889  (reduced to the engine's fight lifecycle + the
--                                      timeline/band reset and the always-show timeline)
--   * icon state updates   3535-3610  (cooldown swipes kept on the addon's set-once
--                                      pattern per nextaction_ui.lua, plus the archived
--                                      buff/active-seal border highlights)
--   * rotation display     1461-1662  (center-screen name/desc/icons driven by
--                                      st.nextaction.sequences; position is session-local)
--   * rotation tracking    1554-1579  (band logging into the ui-owned band array; the
--                                      engine helper track_rotation_band is pure)
--   * timeline data        1881-1898  (event/band collection on the ui-owned arrays;
--                                      rendering below is a trimmed port of 1900-2510)
--   * keybind capture      261-332 + 4142-4196 (fullscreen capture overlay; bindings live
--                                      in the session-local ui.keybinds table and are
--                                      applied with SetOverrideBindingClick)
--   * proc icons           2715-2802  (Bloodlust + DST icons with swipe + countdown)
--   * sync_state_to_player 2542-2587  (mapped onto ST.PALADIN.practice_sync)
--
-- The engine (practice.lua) is pure and owns no clock: this module owns the clock, the
-- frames and the mirroring onto the live addon state:
--   * Session: /st practice (or the options button) toggles a practice session; start()
--     resets the sim and immediately begins a fight (begin_fight + apply_haste). The
--     panel's Start/Stop Fight button restarts/ends fights within the session; its X
--     button (or /st practice again) stops the session (stop()).
--   * Driver: this module's own OnUpdate frame, NOT the paladin class hook. The class
--     hook only fires while the swing bar is shown, but the driver must keep running
--     while the bar is hidden (and while a real-combat pause is waiting to end); the
--     0.05 s compute throttle mirrors nextaction_ui's UPDATE_INTERVAL, and the result
--     popup fades on every frame for a smooth step between compute ticks.
--   * Real-combat pause (archive sim_on_swing 3434-3441, stricter here): while ST.in_combat
--     the sim is frozen entirely - no casts, no swing progression, no grading - and the
--     panel shows a paused hint. On resume every future sim deadline is shifted by the
--     pause duration (shift_sim_times) so nothing lands retroactively.
--   * Bridge: ST.mainhand/ST.gcd carry the simulated swing and GCD (sync_to_addon), the
--     seal state is mirrored by ST.PALADIN.practice_sync, and main.lua's hide_bar guard
--     keeps the mainhand bar visible for the session (the range-finder loop re-runs bar
--     visibility every 0.05 s).
--   * Icon swipes use the set-once latch pattern (nextaction_ui's set_icon_cooldown):
--     a swipe is started only when a cooldown appears or restarts, never re-set per frame.
--
-- Deviations / deferrals (documented for the later phases):
--   * Keybinds and bar mappings are session-local (ui.keybinds, from
--     st.practice.DEFAULT_KEYBINDS): the archived practice_key_* / practice_bar_mappings
--     persistence needs new options, which this lane may not add. Right-clicking a panel
--     icon assigns a key via the capture overlay; action-bar button discovery, manual
--     linking (click-catchers) and bar overlays plug in through ui.attach_overlay
--     (see the "Bar overlays (deferred)" section).
--   * The archive's calculate_spell_GCD_duration hook is emulated only through
--     gcd.spell_length here; the guide's cooldown inputs still come from the live
--     spell cooldowns until the phase-4 haste/rotation/guide integration.
--   * The AW macro options (practice_aw_includes_pot/sob, archive 3198-3208)
--     apply through cast_key below: pot sets the buff directly (no GCD,
--     dup- and lock-guarded like the archive), SoB casts the full seal when
--     the GCD is free. Both ride the Practice page toggles (nil = off).
--   * practice_weapon_speed is read at session/fight start; changing it mid-session
--     takes effect at the next start_fight.
--   * The timeline has no db options here: it always shows on fight start (the archive's
--     "always" default), pixels-per-second and width are constants below, and the
--     position is session-local.
--   * The rotation display has no enable option: it shows during the session whenever
--     the rotation resolves. Its position is session-local (default CENTER + 0, +100).
--   * The DST proc rides the session-local ui.dst_enabled toggle, seeded from
--     the Practice page option (nil = off, the archived practice_dst_enabled
--     default); the panel toggle still flips it live within the session.
--   * Archive quirk: the panel's gcd_dim texture was created but never shown
--     (update_icon_states only fired the gcd_cooldown swipe). Phase 2 shows the dim on
--     GCD-gated icons during the simulated GCD, which is what the panel description says.
--
-- Per-class fidelity (what each drill mirrors, and what the sim cannot model):
--   * Paladin: the twist sim runs the engine's own rotation (determine_rotation),
--     real swing (equipped speed or the weapon-speed override) and the live GCD
--     model. Panel order is the engine's ABILITY_ORDER key-for-key.
--   * Hunter: forced-move windows with Steady (1.5 s) / Multi (0.5 s) /
--     Aimed (3.0 s) starts graded against the window. Times are the class's
--     PRACTICE_SHOTS constants, not live reads: Wrath's instant Aimed and the
--     Arcane/Chimera/Explosive vehicles are not modelled (class-side backlog:
--     practice_cast_time should resolve live per client like the icon ids do).
--     Casts carry no latency compensation (reaction drill; equal shift for all
--     shots, class-side backlog if the shell ever needs it).
--   * Shaman: weave starts graded against the drill swing by the weave model.
--     Swing is real (equipped speed or override), cast seconds ride the live
--     weave catalogue (harness defaults when the catalogue is silent) and
--     latency rides the live world-latency read. Only LB/CL casts exist as
--     vehicles (HW/CH/LvB families are a class-side table addition; the panel
--     already follows PRACTICE_CAST_ORDER dynamically).
--   * Rogue: pool spends graded against the real 2 s energy cadence, SS strikes
--     against the drill swing (Era sword timing only, per sim research that
--     refuted it on TBC+). Latency rides the harness default, not a live read
--     (class-side backlog: a practice_latency_seconds reader like the shaman's).
--   * Druid: powershifts graded against the harness energy model
--     (POWERSHIFT_DEFAULTS: 100 pool, 10/s regen, 40 shift refund, 20-energy
--     rule). Rates are harness defaults, not live reads (no class-side live
--     reader exists; in-client numbers owed before the model can claim them).
--   * Warrior: no drill shell exists, so the toggle runs the shared twist sim
--     session (the options page documents it as the shared session) while the
--     Execute report grades LIVE Execute-range entries (real rage, real target
--     HP, no sim). A warrior-native sim would need a class-side shell plus a
--     harness scenario plus a branch here; until then the shared session is
--     the documented behaviour, not a silent fallback.
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
local LSM = LibStub("LibSharedMedia-3.0")
-- Cross-client API wrappers (see compat.lua).
local api = st.api

st.practice_ui = st.practice_ui or {}
local ui = st.practice_ui

--=========================================================================================
-- Display constants
--=========================================================================================
local UPDATE_INTERVAL = 0.05    -- simulation tick cadence (guide/WA poll parity)
local ICON_SIZE = 30            -- archive geometry
local ICON_SPACING = 4
local ICONS_PER_ROW = 5
local PANEL_WIDTH = 210
local PANEL_ANCHOR_GAP = 8      -- archive: panel TOPLEFT 8 px right of the bar TOPRIGHT
local RESULT_WIDTH = 200
local RESULT_HEIGHT = 50
local RESULT_FADE_SECONDS = 0.3 -- archive: the popup fades over its final 0.3 s
local RESULT_FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local RESULT_COLOR_HIT = {0, 1, 0, 1}
local RESULT_COLOR_MISS = {1, 0.2, 0.2, 1}
local HINT_ACTIVE = "Click an icon to cast. /st practice or the X button stops."
local HINT_STOPPED = "Press Start Fight, or cast seals with the icon grid."
local HINT_PAUSED = "Paused: in combat. Practice resumes when combat ends."
-- Drill hints are the ACTIVE class's own wording: each class's practice_panel
-- carries hint_active / hint_stopped (class-isolation 2026-10-21), so the shared
-- module keeps no per-class strings.
-- Rotation scenario hints (the shared engine): the panel asks the class what it
-- wants cast and grades the player's cast against it.
local HINT_SCENARIO_ACTIVE = "Cast what the rotation wants. /st practice or the X button stops."
local HINT_SCENARIO_STOPPED = "The run is over. /st practice or the X button stops the session."
-- Drill-list hints (the shared engine): one button per drill, pressed to grade.
-- There is no separate "stopped" wording: the drill list has no pre-run state
-- (no fight to start), so the drills are always pressable.
local HINT_DRILLS_ACTIVE = "Press a drill to grade it. /st practice or the X button stops."

-- The practice mode the session runs in (the Practice page select):
--   "class"    the shipped per-class session (the default; today's behaviour)
--   "scenario" the class's rotation SCENARIO (ST.<CLASS>.practice_scenario_step)
--   "drills"   the class's focused DRILL list (ST.<CLASS>.practice_drills)
local PRACTICE_MODE_CLASS = "class"
local PRACTICE_MODE_SCENARIO = "scenario"
local PRACTICE_MODE_DRILLS = "drills"

-- The rotation scenario's decision window: how long the player has to cast the
-- action the class asked for before the step closes as a miss. [DESIGN]
local SCENARIO_STEP_SECONDS = 3.0

-- The practice row geometry (the companion strip under the panel's content that
-- carries the scenario's action buttons, the drill list's buttons, the prompt and
-- the status line).
--
-- The strip GROWS with the button lines (practice_row_set_height): 74 px is the
-- TWO-line minimum (the prompt line, two button lines and the status line), and
-- a class whose rotation spine needs more lines gets a taller strip - the
-- hunter's thirteen-row Wrath spine is four button lines, so the strip carries
-- it and the panel's height follows. Nothing here caps the row: a rotation row
-- is never cut off by the panel.
local PRACTICE_ROW_HEIGHT = 74
local PRACTICE_ROW_BUTTON_H = 20
local PRACTICE_ROW_BUTTON_GAP = 2
local PRACTICE_ROW_ACTION_W = 46
local PRACTICE_ROW_ACTION_PER_ROW = 4
local PRACTICE_ROW_DRILL_W = 96
local PRACTICE_ROW_DRILL_PER_ROW = 2

-- The twist drill is the PALADIN's own: the inherited twist session belongs to
-- the class that owns it and to nobody else.
local TWIST_DRILL_KEY = "paladin_twist"

-- Rotation display (archive 1501-1552, session-local position).
local ROT_ICON_SIZE = 40
local ROT_ICON_SPACING = 6
local ROT_DISPLAY_MAX_ICONS = 5
local ROT_DISPLAY_DEFAULT_X = 0
local ROT_DISPLAY_DEFAULT_Y = 100

-- Timeline (archive 162-166 + 2369+, trimmed; no db options in this lane).
local TIMELINE_WIDTH = 600
local TIMELINE_PPS = 80
local TIMELINE_LANE_HEIGHT = 24
local TIMELINE_ICON_SIZE = 20
local TIMELINE_LABEL_WIDTH = 60
local TIMELINE_RULER_HEIGHT = 46
local TIMELINE_DEFAULT_X = 0      -- session-local default centre offset (archive layout)
local TIMELINE_DEFAULT_Y = -200
local ROTATION_BAND_ICON_SIZE = 14
local ROTATION_BAND_ICON_SPACING = 2
local ROTATION_BAND_MAX_ICONS = 5

-- Timeline lane -> spell id for lane icons and split-seal textures.
local LANE_SPELL_IDS = {
    sob = 31892, cs = 35395, consec = 26573, soc = 20375, judge = 20271,
}

-- Rotation step -> spell id for the rotation display icons (twist is split halves).
local STEP_SPELL_IDS = { cs = 35395, cs_late = 35395, blood_auto = 31892, cmd_auto = 20375 }
local BLOOD_SPELL_ID = 31892
local COMMAND_SPELL_ID = 20375
local BLOODLUST_SPELL_ID = 2825
local BLOODLUST_FALLBACK = "Interface\\Icons\\Spell_Nature_Bloodlust"
local DST_ITEM_ID = 28830
local DST_FALLBACK = "Interface\\Icons\\INV_Misc_Bone_06"

-- Per-rotation band colours (archive 2148-2158).
local ROTATION_BAND_COLORS = {
    ["1/2"] = { 0.12, 0.25, 0.50 },
    ["2/3"] = { 0.40, 0.15, 0.50 },
    ["1/3"] = { 0.15, 0.40, 0.25 },
    ["2/4"] = { 0.50, 0.30, 0.10 },
    ["2/5_blood"] = { 0.50, 0.12, 0.12 },
    ["2/5_command"] = { 0.45, 0.45, 0.12 },
    ["2/2/5"] = { 0.15, 0.35, 0.50 },
    ["2007"] = { 0.35, 0.20, 0.40 },
}
local ROTATION_BAND_FALLBACK = { 0.30, 0.30, 0.30 }

-- Rotation selector grid (archive 816-822).
local ROT_GRID = { { "auto", "1/2" }, { "2/3", "2/4" } }
local ROT_LABELS = { auto = "Raid Pull", ["1/2"] = "1/2", ["2/3"] = "2/3", ["2/4"] = "2/4" }

-- Bare modifier keys the capture overlay ignores (archive 237-242).
local IGNORE_KEYS = {
    LSHIFT = true, RSHIFT = true,
    LCTRL = true, RCTRL = true,
    LALT = true, RALT = true,
    UNKNOWN = true,
}

-- Buff border highlights (archive update_icon_states 3564-3592).
local BORDER_IDLE = { 0.3, 0.3, 0.3, 0.8 }
local BORDER_SEAL = { 0.0, 0.8, 0.0, 0.9 }
local BORDER_AW = { 1.0, 0.8, 0.0, 0.9 }
local BORDER_HPOT = { 1.0, 0.55, 0.0, 0.9 }
local BORDER_ABACUS = { 0.6, 0.2, 0.8, 0.9 }

-- Future sim deadlines that the real-combat pause must carry over the pause (see
-- shift_sim_times). Cooldowns of abilities the sim tracks, buff windows, the seal fade,
-- the swing, the GCD and the queue timestamp all live on the same clock domain.
local SHIFTED_SIM_TIMES = {
    "swing_ends_at",
    "gcd_expires",
    "fading_seal_expires",
    "bl_buff_expires",
    "haste_pot_buff_expires",
    "abacus_buff_expires",
    "abacus_cooldown_expires",
    "dst_buff_expires",
    "dst_icd_expires",
    "cs_cooldown_expires",
    "judge_cooldown_expires",
    "consec_cooldown_expires",
    "aw_cooldown_expires",
    "aw_buff_expires",
    "queue_timestamp",
}

--=========================================================================================
-- Small helpers
--=========================================================================================
-- Anchors a practice frame to the mainhand bar (the archive's geometry), falling back
-- to UIParent's centre when the bar frame does not exist. The frames are built in
-- post_init, after init_timers, so the fallback is only a guard.
local function anchor_to_mainhand_bar(self, frame, point, bar_point, x, y)
    frame:ClearAllPoints()
    local bar = self:get_bar_frame("mainhand")
    if bar then
        frame:SetPoint(point, bar, bar_point, x, y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- The equipped mainhand swing speed (the archive's UnitAttackSpeed source), or nil.
local function get_equipped_speed()
    local speed = api.UnitAttackSpeed("player")
    if type(speed) == "number" and speed > 0 then
        return speed
    end
    return nil
end

-- Base swing speed for a session: the configured override when set (a positive
-- practice_weapon_speed), else the equipped weapon, else the engine's 3.5 s fallback.
local function resolve_base_speed(db)
    local override = type(db) == "table" and db.practice_weapon_speed or nil
    if type(override) == "number" and override > 0 then
        return override
    end
    return get_equipped_speed() or 3.5
end

-- Icon texture for a spell id through the cross-client wrappers (nil when unknown).
local function spell_texture(spell_id)
    if not spell_id then
        return nil
    end
    if api.GetSpellInfo then
        local _, _, icon = api.GetSpellInfo(spell_id)
        if icon then
            return icon
        end
    end
    if GetSpellTexture then
        local icon = GetSpellTexture(spell_id)
        if icon then
            return icon
        end
    end
    return nil
end

-- The four per-class drill routes (hunter / shaman / rogue / druid) live in the
-- class modules' OWN `practice_panel` providers (class-isolation 2026-10-21
-- C1-C4). The shared layer asks the ACTIVE class through ui.practice_panel()
-- only: it never names a class and never compares a hardcoded drill key.

-- The pure harness (the shared engine), or nil when the flavor ships no engine.
local function practice_harness()
    local pr = st.practice
    if not pr then
        return nil
    end
    return pr.harness
end

-- The class module that owns the practice contract (the addon object owns the
-- class modules; this module's own table is the fallback for a half-loaded
-- addon). Nil when the class module is absent.
--
-- C7 (class-isolation 2026-10-21): the class is the one main.lua ACTIVATED
-- (ST.active_class), never the class being played (ST.player_class). An explicit
-- non-playing pick owns its practice; with no active class the shared layer has
-- no class features and never guesses.
local function practice_class_module()
    local class_key = ST.active_class
    if type(class_key) ~= "string" or class_key == "" then
        return nil
    end
    local module = type(ST) == "table" and ST[class_key] or nil
    if type(module) ~= "table" then
        module = type(st) == "table" and st[class_key] or nil
    end
    if type(module) ~= "table" then
        return nil
    end
    return module
end

-- The class's CANONICAL key for an action key: the class's own alias table maps
-- every spelling the engine, the practice sim or the guide may report onto the
-- canonical key (the paladin's "consecration" -> "cons"; the sim's own
-- "consec" -> "cons"). A class with a single key space publishes no table, and
-- the normaliser is then the identity.
--
-- The ENGINE owns the class contract (practice.lua's H.practice_canonical_key)
-- and this is the UI's seam over it. It is a ui-table member and NOT a
-- file-scope local on purpose: this module sits at the Lua 5.1 local ceiling
-- (199 of 200), so a 200th file-scope local would be a LOAD FAILURE.
function ui.canonical_key(key)
    local H = practice_harness()
    if not H or type(H.practice_canonical_key) ~= "function" then
        return key
    end
    return H.practice_canonical_key(practice_class_module(), key)
end

-- The drill ids that belong to THIS class: the class module's published drill
-- list (the new drills) and the harness registry's entries for the class (the
-- shipped drills). A class's own drills win over any inherited or shared key.
local function practice_own_drill_keys(class_key)
    local out = {}
    local seen = {}
    local H = practice_harness()
    if not H then
        return out
    end
    local function push(key)
        if type(key) ~= "string" or key == "" or seen[key] then
            return
        end
        seen[key] = true
        out[#out + 1] = key
    end
    local drills = H.practice_drills(practice_class_module())
    if drills then
        for i = 1, #drills do
            push(drills[i].key)
        end
    end
    local specs = H.scenarios_for_class(class_key)
    for i = 1, #specs do
        push(specs[i].key)
    end
    return out
end

-- Is the drill key one of the class's own?
local function practice_owns_drill(own_keys, key)
    if type(own_keys) ~= "table" or type(key) ~= "string" then
        return false
    end
    for i = 1, #own_keys do
        if own_keys[i] == key then
            return true
        end
    end
    return false
end

-- Does the class publish its own drills (the contract member)? A class that does
-- never falls back to the inherited twist session.
local function practice_publishes_drills()
    local H = practice_harness()
    if not H then
        return false
    end
    local drills = H.practice_drills(practice_class_module())
    return drills ~= nil and #drills > 0
end

-- The built-in drill the class's shipped session grades (its drill key), or nil.
-- The class module names it: ST.<CLASS>.practice_scenario_key() (the hunter's
-- accessor carries the older get_ prefix - both spellings are read).
local function practice_class_scenario_key()
    local module = practice_class_module()
    if type(module) ~= "table" then
        return nil
    end
    local fn = module.practice_scenario_key
    if type(fn) ~= "function" then
        fn = module.get_practice_scenario_key
    end
    if type(fn) ~= "function" then
        return nil
    end
    -- pcall-guarded: a throwing accessor never stops the session.
    local ok, key = pcall(function() return fn(module) end)
    if not ok or type(key) ~= "string" or key == "" then
        return nil
    end
    return key
end

-- Does the class's own drill list supersede the built-in drill its shipped
-- session would run? (one skill, one truth - the class list wins)
local function practice_own_drill_supersedes_route()
    local H = practice_harness()
    if not H then
        return false
    end
    local session_drill = practice_class_scenario_key()
    if type(session_drill) ~= "string" then
        return false
    end
    local superseding = H.SUPERSEDED_DRILLS[session_drill]
    if type(superseding) ~= "string" then
        return false
    end
    local drills = H.practice_drills(practice_class_module())
    if not drills then
        return false
    end
    for i = 1, #drills do
        if drills[i].key == superseding then
            return true
        end
    end
    return false
end

-- Does the class own the twist drill (the paladin's own)? The twist session
-- belongs to the class that owns it and to nobody else.
local function practice_owns_twist_drill()
    return practice_owns_drill(practice_own_drill_keys(ST.active_class), TWIST_DRILL_KEY)
end

-- Does the class's OWN drill list win over the session the class would otherwise
-- run? Two cases:
--   * the class's list supersedes a built-in drill that no shipped session of
--     its own grades (one skill, one truth - the operator's ruling), or
--   * the class has no shipped session of its own and does not own the twist
--     drill (the twist session is the paladin's, never an inherited session).
--
-- A class WITH a shipped session of its own (the hunter, the shaman, the rogue,
-- the druid) keeps that session: its session grades through the class's own drill
-- (H.delegate_drill_grade), so the skill stays one truth - but the session itself
-- must stay REACHABLE.
local function practice_class_list_wins()
    if not practice_publishes_drills() then
        return false
    end
    -- (b) A class with a SHIPPED session of its own (the hunter, the shaman, the
    --     rogue, the druid) keeps it: its session grades through the class's own
    --     drill (H.delegate_drill_grade), so the skill is still one truth - and
    --     the session itself stays REACHABLE. Routing it to the drill list
    --     instead left the class with no session at all: its panel icons then
    --     hit a drill cast with no session (a silent no-op) and the class's own
    --     session was unreachable.
    if ui.practice_class_drill() then
        return false
    end
    -- (a) The class's list supersedes the built-in drill its shipped session
    --     grades: the class trains its own list instead.
    if practice_own_drill_supersedes_route() then
        return true
    end
    -- (c) No shipped session of its own: the class would inherit the twist
    --     session, and it never does when it has drills of its own.
    return not practice_owns_twist_drill()
end

-- Does this class run a SIM session (the twist sim or one of the class drill
-- sessions)? A class whose own drill list wins runs its own drill list instead -
-- it never falls back to the twist session.
local function practice_class_runs_sim_session()
    if ui.practice_class_drill() then
        if not practice_class_list_wins() then
            return true
        end
    end
    -- The twist sim is the PALADIN's drill, never an inherited session: a class
    -- that does not own the twist drill runs no sim session at all (the operator
    -- ruling - no class is offered another class's drill). A class with no
    -- practice of its own is refused loudly by ui.start.
    return practice_owns_twist_drill()
end

-- Is the swing engine LIVE on this client? The engine reports its mode on the
-- addon object (main.lua): "vendored-lib" (the classic line), "forever-source"
-- (the Forever PLAYER_SWING engine) or "inert-standin" (the retail client, which
-- has no classic combat log and keeps a stand-in that never reports a swing).
--
-- The rotation SCENARIO needs a live swing engine: the rotation the class asks
-- for is timed off the swing, so on the inert client every step would answer
-- UNKNOWN (ten unknown steps instead of a session). The scenario is gated on the
-- engine and the refusal is loud.
--
-- Only the EXPLICIT stand-in counts as dead: a client that has not reported its
-- engine yet (or a flavour that does not set the field at all) is unknown, and
-- an unknown engine never blocks a session.
local function practice_swing_engine_dead()
    local engine = ST.swing_engine
    if type(engine) ~= "string" or engine == "" then
        return false
    end
    return engine == "inert-standin"
end

-- The class's scenario id (optional): the class lane owns the name its rotation
-- scenario is registered under. It may publish a string or a function that
-- returns one; the engine's own table is the fallback.
local function practice_scenario_id()
    local module = practice_class_module()
    if type(module) ~= "table" then
        return nil
    end
    local key = module.practice_scenario_key
    if type(key) == "string" then
        return (key ~= "") and key or nil
    end
    if type(key) ~= "function" then
        return nil
    end
    -- pcall-guarded: a throwing accessor never stops the session (the engine's
    -- own id stands in).
    local ok, resolved = pcall(function() return module.practice_scenario_key() end)
    if not ok or type(resolved) ~= "string" or resolved == "" then
        return nil
    end
    return resolved
end

-- The rotation the class publishes (optional): the class lane may expose the
-- rotation slice it mirrors (ST.<CLASS>.practice_rotation_for). The engine uses
-- the actions it names - in the rotation's own priority order, with the class's
-- own labels - for the scenario panel's buttons. A class that publishes none
-- keeps the guide slot vocabulary.
local function practice_rotation_entries()
    local module = practice_class_module()
    if type(module) ~= "table" or type(module.practice_rotation_for) ~= "function" then
        return nil
    end
    -- The call is argument-free on purpose: the class picks its own slice (the
    -- running family / order). pcall-guarded: a class that needs an argument
    -- answers nil and the guide slot vocabulary stands in.
    local ok, entries = pcall(function() return module.practice_rotation_for() end)
    if not ok or type(entries) ~= "table" then
        return nil
    end
    local out = {}
    for i = 1, #entries do
        local entry = entries[i]
        if type(entry) == "table" and type(entry.action) == "string" and entry.action ~= "" then
            out[#out + 1] = {
                action = entry.action,
                label = (type(entry.label) == "string" and entry.label ~= "") and entry.label
                    or entry.action,
            }
        end
    end
    if #out == 0 then
        return nil
    end
    return out
end

-- The rotation family the running client uses (optional): the class lane may
-- publish it (ST.<CLASS>.practice_rotation_family). It is the panel's readout -
-- which rotation the scenario is grading against.
local function practice_rotation_family()
    local module = practice_class_module()
    if type(module) ~= "table" or type(module.practice_rotation_family) ~= "function" then
        return nil
    end
    local ok, family = pcall(function() return module.practice_rotation_family() end)
    if not ok or type(family) ~= "string" or family == "" then
        return nil
    end
    return family
end


-- Start-block accounting (the start-path analogue of the tick's note_practice_error
-- below): every refused start counts in self.bar_hook_errors (read by /st diag) and
-- prints its reason, so no start path ever dies silent. Unlike the tick site
-- (20/s), starts are user-invoked, so every refusal prints (no once-per-session
-- throttle); the counter still lets /st diag show the volume.
--
-- The contract itself lives in guard.lua (one implementation for the whole addon):
-- this is the refusal flavour of it (count + print every time).
local START_BLOCK_SITE = "practice:start"
local function note_start_block(self, msg)
    st.guard.refusal(self or ST, START_BLOCK_SITE, msg)
end

-- A drill cast that reaches a class drill with NO session is a LOUD refusal,
-- never a silent no-op: the player clicked a drill icon and nothing happened.
-- The refusal is counted (the /st diag report reads the count) and printed with
-- its reason.
local CAST_BLOCK_SITE = "practice:cast"
local function note_cast_block(self, msg)
    st.guard.refusal(self or ST, CAST_BLOCK_SITE, msg)
end

--=========================================================================================
-- The active class's practice provider (class-isolation 2026-10-21)
--=========================================================================================
-- ONE uniform contract between the shared practice UI and whichever class module
-- main.lua activated (R2 shape (a): the class publishes a provider table). The
-- shared layer reads this table generically: it never names a class, never
-- compares a hardcoded drill key, and never indexes a missing function without a
-- guard. A class with no provider simply has no drill panel; every caller then
-- degrades to the paladin sim / the drill list / "no practice for this class".
--
-- These are ui-table members rather than file-scope locals on purpose: this
-- module sits at the Lua 5.1 local ceiling (199 of 200), so one more file-scope
-- local would be a LOAD FAILURE.
function ui.practice_panel()
    local module = practice_class_module()
    if type(module) ~= "table" then
        return nil, nil
    end
    local panel = module.practice_panel
    if type(panel) ~= "table" then
        return nil, module
    end
    return panel, module
end

-- The active class's drill scenario key (throw-guarded; nil on drift).
function ui.practice_drill_scenario_key()
    local panel = ui.practice_panel()
    if not panel or type(panel.scenario_key) ~= "function" then
        return nil
    end
    local ok, key = pcall(panel.scenario_key)
    if not ok or type(key) ~= "string" or key == "" then
        return nil
    end
    return key
end

-- Does the ACTIVE class's own drill scenario run? The class declares its drill
-- key and its live scenario key; the route matches only when they agree.
function ui.practice_class_drill()
    local panel = ui.practice_panel()
    if not panel or type(panel.drill_key) ~= "string" or panel.drill_key == "" then
        return false
    end
    return ui.practice_drill_scenario_key() == panel.drill_key
end

-- The active class's drill order, or nil for a class without a drill panel.
function ui.practice_class_order()
    if not ui.practice_class_drill() then
        return nil
    end
    local panel = ui.practice_panel()
    if type(panel.order) ~= "function" then
        return nil
    end
    local ok, order = pcall(panel.order)
    if not ok or type(order) ~= "table" then
        return nil
    end
    return order
end

-- The active class's drill definition for one key (the class's own label and
-- spell-id/name art rule), or nil when the class cannot map the key.
function ui.practice_class_def(key)
    local panel = ui.practice_panel()
    if not panel or type(panel.label) ~= "function" then
        return nil
    end
    local ok, label = pcall(panel.label, key)
    if not ok or label == nil then
        return nil
    end
    local spell_id = nil
    if type(panel.spell_id) == "function" then
        local ok_sid, sid = pcall(panel.spell_id, key)
        if ok_sid then
            spell_id = sid
        end
    end
    local def = {
        name = label,
        spell_id = spell_id,
        cooldown = 0,
        type = panel.def_type or "ability",
    }
    if panel.icon == "name" and api.GetSpellInfo then
        local name = label
        if name then
            local _, _, icon = api.GetSpellInfo(name)
            if icon then
                def.texture = icon
            end
        end
    end
    return def
end

-- The order the panel/keybind surfaces use: the active class's own drill order
-- when its route runs, else the shared sim's ability order.
function ui.practice_order()
    local order = ui.practice_class_order()
    if order then
        return order
    end
    local pr = st.practice
    return (pr and pr.ABILITY_ORDER) or {}
end

-- A drill class whose module is present but whose scenario key no longer matches
-- (renamed harness key, half-loaded module) never silently runs the paladin sim:
-- the route is broken and start fails it closed with the class's own message.
function ui.practice_drill_broken()
    local panel = ui.practice_panel()
    if not panel or type(panel.drill_key) ~= "string" or panel.drill_key == "" then
        return false
    end
    return not ui.practice_class_drill()
end

-- Is one of the active class's drill sessions running?
function ui.practice_drill_running()
    local panel = ui.practice_panel()
    if not panel or type(panel.session) ~= "table"
        or type(panel.session.running) ~= "function" then
        return false
    end
    local ok, running = pcall(panel.session.running, ui)
    return ok and running == true
end

-- Start the active class's own drill session through its provider, then run the
-- shared session trailer (fresh score, progression, panel). Returns false when
-- the class has no runnable shell.
function ui.practice_start_drill(self, now)
    local panel = ui.practice_panel()
    if not panel or type(panel.session) ~= "table"
        or type(panel.session.start) ~= "function" then
        return false
    end
    -- The panel order must resolve key-for-key (unknown-hide in build): a drill
    -- whose icons cannot resolve refuses to start (fail-loud) rather than
    -- running a session whose casts never score.
    local order = ui.practice_class_order()
    if type(order) ~= "table" or #order == 0 then
        return false
    end
    for i = 1, #order do
        if ui.practice_class_def(order[i]) == nil then
            return false
        end
    end
    local db = self:get_class_table()
    local duration = resolve_base_speed(db)
    if type(duration) ~= "number" or duration <= 0 then
        duration = 3.5
    end
    local ok, started = pcall(panel.session.start, self, now, ui,
        { base_speed = duration })
    if not ok or not started then
        return false
    end
    return ui.begin_drill_session(self, now)
end

-- The shared drill-session trailer: everything every class's own drill start
-- does after it has built its session state.
function ui.begin_drill_session(self, now)
    local pr = st.practice
    if not pr then
        return false
    end
    ui.active = true
    ui.combat_paused = false
    ui.last_compute = 0
    ui.result_remaining = 0
    -- Drill casts start unbound (the keybind capture flow assigns them); the
    -- paladin defaults do not apply to drill keys.
    ui.keybinds = {}
    ui.score = pr.new_score()
    -- The progression hook: a fresh pure session, the live clock stamp and the
    -- drill key (the session's graded attempts feed it from here on).
    ui.begin_progress_session(self, now)
    ui.load_bests(self)
    ui.last_score_text = nil
    ui.last_seal_sig = nil
    ui.last_rotation_line = nil
    ui.last_fight_text = nil
    ui.last_info_text = nil
    ui.last_button_active = nil
    ui.last_hint_text = nil
    ui.current_display_rotation = nil
    ui.build_bar_mappings(self)
    ui.update_result_font(self)
    ui.refresh_icons(self)
    ui.update_info(self)
    ui.update_score(self)
    ui.update_button(self)
    ui.update_hint(self)
    ui.update_keybind_labels(self)
    ui.rebind_keys(self)
    ui.apply_settings(self)
    ui.panel:Show()
    ui.driver:Show()
    ui.sync_to_addon(self)
    self:Print("Practice mode started. Type /st practice to stop.")
    return true
end

-- The running drill session's fight state (nil when no class drill session
-- exists or the provider has no state seam).
function ui.practice_drill_active()
    local panel = ui.practice_panel()
    if not panel or type(panel.session) ~= "table"
        or type(panel.session.active) ~= "function" then
        return nil
    end
    local ok, active = pcall(panel.session.active, ui)
    if not ok then
        return nil
    end
    return active
end

-- Begin (or re-begin) the active class's drill run - the Start/Stop Fight button.
function ui.practice_begin_fight(self, now)
    local panel = ui.practice_panel()
    if not panel or type(panel.session) ~= "table"
        or type(panel.session.begin) ~= "function" then
        return false
    end
    local ok = pcall(panel.session.begin, self, now, ui)
    if not ok then
        note_start_block(self, "Practice drill fight cannot begin (shell error).")
        return false
    end
    return true
end

-- End the active class's drill run (the session object survives for a re-begin).
function ui.practice_end_fight(self)
    local panel = ui.practice_panel()
    if not panel or type(panel.session) ~= "table"
        or type(panel.session.end_session) ~= "function" then
        return false
    end
    pcall(panel.session.end_session, self, ui)
    return true
end

-- Stop the active class's drill session (nil-safe: a half-loaded shell still
-- tears the session down). Returns true when the provider owned the teardown.
function ui.practice_stop_drill(self)
    local panel = ui.practice_panel()
    if not panel or type(panel.session) ~= "table"
        or type(panel.session.running) ~= "function" then
        return false
    end
    local ok_run, running = pcall(panel.session.running, ui)
    if not ok_run or not running then
        return false
    end
    if type(panel.session.stop) ~= "function" then
        note_start_block(self, "Practice drill session end skipped (shell missing).")
        return true
    end
    local ok_end = pcall(panel.session.stop, self, ui)
    if not ok_end then
        note_start_block(self, "Practice drill session end skipped (shell error).")
    end
    return true
end

--=========================================================================================
-- Practice progression hook (the gamification spec's step 2)
--
-- The pure modules own every rule: practice_progress.lua (XP, the level curve, the
-- per-drill mastery, the streaks, the daily XP cap, the unlock registry) and
-- practice_stats.lua (the lifetime aggregates, the per-drill table, the bounded
-- session history). This layer only feeds them from a live session and reads the
-- result back:
--   * every graded attempt feeds the progress side (XP under the daily per-drill cap,
--     the session streak, the per-drill mastery window) and the stats side (the
--     lifetime counters, the per-drill table, the best grade, the best S-run);
--   * the session's live window - measured on the injected monotonic clock
--     (st.api.get_time()), never a wall clock - is the "time active": only the time
--     between the session's start and its end counts, never the time the panel sits
--     idle with no session running;
--   * the achievement predicates are evaluated on the merged snapshot at session end;
--   * the saved blob is REPLACED, never mutated in place: db.profile.practice is a
--     NEW table on every write, and the AceDB default (ST.PRACTICE_DEFAULTS) is
--     never touched.
--
-- Write discipline (spec §6): the profile KEY is replaced at session end, at a
-- level-up, and at most once every PROGRESS_SAVE_INTERVAL seconds while a session
-- runs - never once per attempt.
--
-- L5 (progression audit 2026-10-20): the old wording read like a DURABILITY
-- guarantee and it is not one. The throttled write replaces the profile key with a
-- wrapper table that holds REFERENCES to the live progress and stats tables, so the
-- profile ALWAYS mirrors the live state: the throttle decides how often the key is
-- swapped, never how current the data is. What makes the state durable is the
-- CLIENT: the SavedVariables are serialised at logout (a /reload writes no
-- SavedVariables at all - the client fires no logout event and serialises nothing),
-- so nothing an addon does at reload time can reach the disk. The write shape stays
-- exactly as it is - it is what makes the logout flush land.
--
-- The panel's level badge ships ON (opt-out): the db key practice_panel_badge
-- DEFAULTS to true (config_presets.lua), so a fresh profile sees the badge, the
-- session XP bar and the chat notices - the operator order of 2026-10-19
-- ("start at lvl 1, gain xp each practice, level up") is the gate for that
-- default-visible change. The read is still nil-safe and exact (== true), so a
-- profile that saved false (or an old profile with no key at all) hides the
-- surface. The chat notices ride the same key: the unlock lane (spec §7 step 4)
-- owns the toast.
--=========================================================================================

-- The practice ids each class owns now live in the class module's OWN
-- practice_panel.progress table (class-isolation 2026-10-21 R3): mode (the drill
-- its session grades), scenario (the rotation scope id) and the drill list. The
-- shared layer reads the ACTIVE class's provider; it keeps no class-keyed map.

-- The live-session write throttle (spec §6): at most one profile-key swap every
-- five minutes while a session runs. It is NOT a durability guarantee - the profile
-- always mirrors the live state (the swapped key holds the live tables), and the
-- client serialises the SavedVariables at logout.
local PROGRESS_SAVE_INTERVAL = 300

-- The panel badge geometry. The badge is a small companion frame UNDER the panel's
-- bottom-left corner: the panel's own rows are full (the title, the icon grid and
-- the rotation grid span its whole width), so the badge hangs below it instead of
-- overlapping anything.
local BADGE_WIDTH = 84
local BADGE_HEIGHT = 30
local BADGE_BAR_INSET = 6
local BADGE_BAR_WIDTH = BADGE_WIDTH - (2 * BADGE_BAR_INSET) - 2
local BADGE_BAR_HEIGHT = 6

-- The calendar day the pure layer uses for the daily streak and the daily XP cap.
-- The client exposes `date` as a global on EVERY shipped family - Blizzard's own
-- code calls it on all five branches the addon supports (the citation is in
-- bench/progression_fixes_2026-10-20.md §6) - but the call is guarded, so a
-- client that ever lost the global cannot throw.
--
-- L6 (progression audit 2026-10-20): there is ONE day numbering. The "YYYY-MM-DD"
-- form below is the CIVIL calendar, which is the numbering the pure layer's day
-- ordinal is built from (the count of civil days since 1970-01-01). The numeric
-- fallback that used to live here was a UTC day count - a DIFFERENT numbering,
-- which rolls the day over at a different hour - so mixing the two rolled the
-- day over at the wrong hour. It is gone: a client with no calendar has NO day,
-- which is the pure layer's own no-day path, and it is REPORTED to the player
-- (the cap notice in record_progress_attempt), never hidden.
local function current_day()
    local ok, day = pcall(date, "%Y-%m-%d")
    if ok and type(day) == "string" and day ~= "" then
        return day
    end
    return nil
end

-- The addon's profile table (nil-safe: a half-loaded addon has no db yet).
local function profile_table(self)
    if type(self) ~= "table" then
        return nil
    end
    if type(self.get_profile_table) == "function" then
        local ok, tbl = pcall(self.get_profile_table, self)
        if ok and type(tbl) == "table" then
            return tbl
        end
    end
    if type(self.db) == "table" and type(self.db.profile) == "table" then
        return self.db.profile
    end
    return nil
end

-- The class scope key the session's progression belongs to (the player's class).
local function progress_class_key()
    local class = ST.active_class
    if type(class) ~= "string" or class == "" then
        return nil
    end
    return class
end

-- The reserved drill bucket: an attempt with no usable drill id lands here, so its
-- XP is still tracked and still capped (a caller cannot dodge the anti-grind cap by
-- dropping the drill id). The pure progression module owns the rule - this is the
-- SAME key it files the attempt under (practice_progress.lua's record_attempt), and
-- the stats side uses it too, so the merged row is one coherent row (L2).
ui.UNKNOWN_DRILL_KEY = "_unknown"

-- The drill key the session grades (the progression scope's drill id).
-- The RUNNING mode wins: a scenario run grades under the scenario's id, a drill
-- under that drill's id. Then the class's OWN drills win over any inherited or
-- shared key: the shipped key stands only when the class owns it, so a class
-- that owns its own drills never grades under somebody else's key.
local function progress_drill_key(class_key)
    if type(class_key) ~= "string" then
        return nil
    end
    if type(ui.progress_mode_key) == "string" and ui.progress_mode_key ~= "" then
        return ui.progress_mode_key
    end
    -- The ACTIVE class's own progression facts (its provider).
    local panel = ui.practice_panel()
    local progress = panel and panel.progress
    local mode = type(progress) == "table" and progress.mode or nil
    local own = practice_own_drill_keys(class_key)
    if #own > 0 then
        if type(mode) == "string" and practice_owns_drill(own, mode) then
            return mode
        end
        return own[1]
    end
    if type(mode) == "string" then
        return mode
    end
    return nil
end

-- The refusal notice (M1): this session's XP is not being saved.
--
-- It is printed through self:Print and NOT through the badge-gated announce():
-- a progression dead end must be reported even when the badge is off. Once per
-- session - the latch is cleared with the session (begin_progress_session).
function ui.announce_not_persistable(self)
    if ui.progress_persist_notice then
        return false
    end
    ui.progress_persist_notice = true
    if type(self) == "table" and type(self.Print) == "function" then
        self:Print("Practice progress: this session's XP is not being saved - the saved "
            .. "profile was written by a newer build, and that build's data is left untouched.")
    end
    return true
end

-- The live practice blob: migrated and validated ONCE, then replaced into the
-- profile. A blob a NEWER build wrote is never overwritten (we do not understand
-- it): the hook runs in memory only until that build comes back.
--
-- M1 (progression audit 2026-10-20): the version check was an inline comparison
-- HERE, a second copy of the pure module's rule. The pure module owns it:
-- P.migrate returns a NEWER build's blob UNCHANGED (we never wipe data we do not
-- understand) and P.is_current says whether a blob is one this build understands.
-- The hook asks the shared helper instead of comparing schema versions itself, so
-- ONE source of truth owns the rule.
function ui.ensure_progress_profile(self)
    if ui.progress_profile then
        return ui.progress_profile
    end
    local P = st.practice_progress
    local S = st.practice_stats
    if not P or not S then
        return nil
    end
    local profile = profile_table(self)
    if not profile then
        return nil
    end
    local blob = profile.practice
    local ok, migrated = pcall(P.migrate, blob or {})
    if not ok or type(migrated) ~= "table" then
        migrated = P.new_profile()
    end
    -- A migrated blob this build does NOT understand is a NEWER build's blob: the
    -- pure module left it exactly as it was. It is protected (never overwritten)
    -- and the refusal is REPORTED (M1): the player keeps practising, the badge
    -- keeps climbing and NOTHING is saved - that is a dead end, not a silent
    -- no-op, and the guard saw no error to report.
    if not P.is_current(migrated) then
        ui.progress_persistable = false
        ui.progress_profile = {
            schema_version = P.SCHEMA_VERSION,
            progress = P.new_state(),
            stats = S.new_state(),
        }
        ui.announce_not_persistable(self)
        return ui.progress_profile
    end
    if type(migrated.progress) ~= "table" then
        migrated.progress = P.new_state()
    end
    if type(migrated.stats) ~= "table" then
        migrated.stats = S.new_state()
    end
    -- REPLACE the profile key with the repaired blob: the AceDB default table is
    -- never mutated and the saved blob is never edited in place.
    profile.practice = migrated
    ui.progress_persistable = true
    ui.progress_profile = migrated
    return migrated
end

-- Writes the live progression state into the profile. The profile KEY is replaced
-- with a new table every time (never edited in place), and the write is skipped
-- entirely when a newer build owns the saved blob.
function ui.persist_progress(self, now)
    local profile = profile_table(self)
    local P = st.practice_progress
    if not profile or not P or not ui.progress_profile then
        return false
    end
    if ui.progress_persistable == false then
        -- M1 (progression audit 2026-10-20): the refusal was SILENT. The session
        -- kept scoring, the badge kept climbing and NOTHING was written - with no
        -- error and no notice, so /st diag stayed clean. The refusal is reported
        -- (once per session).
        ui.announce_not_persistable(self)
        return false
    end
    profile.practice = {
        schema_version = P.SCHEMA_VERSION,
        progress = ui.progress_profile.progress,
        stats = ui.progress_profile.stats,
    }
    ui.progress_last_save = now or api.get_time()
    return true
end

-- The throttled write: at most one profile-key swap every PROGRESS_SAVE_INTERVAL
-- seconds while a session runs (never one per attempt). The swap is NOT what makes
-- the state durable - the profile already mirrors the live tables, and the client
-- serialises the SavedVariables at logout.
function ui.maybe_persist_progress(self, now)
    local stamp = now or api.get_time()
    if type(ui.progress_last_save) ~= "number" then
        ui.progress_last_save = stamp
        return false
    end
    if stamp - ui.progress_last_save < PROGRESS_SAVE_INTERVAL then
        return false
    end
    return ui.persist_progress(self, stamp)
end

-- Is the panel's level badge enabled? The db key must be exactly true (the
-- standing rule: nil = off, == false hides), so a fresh profile shows nothing.
function ui.badge_is_enabled(self)
    if type(self) ~= "table" or type(self.get_class_table) ~= "function" then
        return false
    end
    local ok, db = pcall(self.get_class_table, self)
    if not ok or type(db) ~= "table" then
        return false
    end
    return db.practice_panel_badge == true
end

-- Turns the badge on or off. The options page owns the widget (spec §7 step 3);
-- this entry point is what it calls. The toggle is written to the class table so
-- it survives a reload.
function ui.set_badge_enabled(self, enabled)
    self = self or ST
    local on = (enabled == true)
    ui.badge_enabled = on
    if type(self) == "table" and type(self.get_class_table) == "function" then
        local ok, db = pcall(self.get_class_table, self)
        if ok and type(db) == "table" then
            db.practice_panel_badge = on
        end
    end
    ui.update_badge(self)
    return on
end

-- A chat notice. The notices ride the badge's opt-in: with the toggle off the
-- progression runs silently (the data is still collected and saved), so nothing
-- changes for an existing user until the operator-gated toggle is turned on.
local function announce(self, text)
    local owner = self or ST
    if not ui.badge_enabled then
        return
    end
    if type(owner) ~= "table" or type(owner.Print) ~= "function" then
        return
    end
    owner:Print(text)
end

-- The level-up notice.
local function announce_level_up(self, info)
    if type(info) ~= "table" then
        return
    end
    if (info.renown or 0) > 0 then
        announce(self, string.format("Practice level up: renown %d (level %d).",
            info.renown, info.level))
    else
        announce(self, string.format("Practice level up: level %d.", info.level))
    end
end

-- The achievement notices (the ids the predicates unlocked in this session).
local function announce_unlocks(self, ids)
    if type(ids) ~= "table" then
        return
    end
    local P = st.practice_progress
    if not P then
        return
    end
    for _, id in ipairs(ids) do
        local definition = P.UNLOCKS and P.UNLOCKS[id]
        local label = (type(definition) == "table" and definition.label) or id
        announce(self, "Practice achievement unlocked: " .. tostring(label))
    end
end

-- A session begins: a fresh pure session, the live clock stamp and the drill key.
function ui.begin_progress_session(self, now)
    local P = st.practice_progress
    -- The badge's opt-in is read per session, so a toggle flipped in the options
    -- takes effect on the next session without a reload.
    ui.badge_enabled = ui.badge_is_enabled(self)
    if not P then
        return
    end
    -- The refusal notice (M1) is per session too: the latch is cleared with the
    -- session, so a session whose XP cannot be saved says so ONCE - and a NEW
    -- session says it again (the refusal is still in force).
    ui.progress_persist_notice = nil
    local profile = ui.ensure_progress_profile(self)
    if not profile then
        return
    end
    ui.progress_session = P.new_session()
    ui.progress_class_key = progress_class_key()
    ui.progress_drill_key = progress_drill_key(ui.progress_class_key)
    ui.progress_started_at = now or api.get_time()
    ui.progress_last_save = ui.progress_started_at
    ui.progress_new_unlocks = {}
    -- The cap notice (M4) is per session: a client with no calendar day is told
    -- once per session, not once per attempt.
    ui.progress_cap_notice = nil
    ui.update_badge(self)
end

-- One graded attempt into the progression state: XP (under the daily per-drill cap),
-- the session streak, the per-drill mastery window and the lifetime stats counters.
-- A level-up persists immediately (the only write an attempt can cause); every
-- other attempt only touches memory.
function ui.record_progress_attempt(self, grade)
    local P = st.practice_progress
    local S = st.practice_stats
    if not P or not S then
        return
    end
    -- M1 (deep audit 2026-10-20): the profile is ensured HERE, not only by the badge.
    -- The Progress page's reset drops the hook lane's live cache; the attempt then
    -- returned early and the session kept SCORING with no XP, no mastery, no streak,
    -- no stats and no badge - a success that looked real and recorded nothing.
    local profile = ui.ensure_progress_profile(self)
    local session = ui.progress_session
    local class_key = ui.progress_class_key
    if not profile or not session or not class_key then
        return
    end
    local progress = profile.progress
    local stats = profile.stats
    if type(progress) ~= "table" or type(stats) ~= "table" then
        return
    end
    local drill_key = ui.progress_drill_key
    local day = current_day()
    local before = P.level_info(P.scope_xp(progress, class_key))
    -- The session's XP before and after the attempt: a grade that earns points but
    -- moves nothing means the daily cap swallowed the whole award.
    local xp_before = session.xp
    if type(xp_before) ~= "number" then xp_before = 0 end
    P.record_attempt(progress, session, class_key, drill_key, grade, day)
    -- L2 (progression audit 2026-10-20): the reserved bucket must be the SAME key
    -- on both sides. The progress module files an attempt with no usable drill id
    -- under "_unknown"; the stats module dropped it, so the merged row showed the
    -- progress side's attempts next to a 0.0% accuracy - a self-contradictory row.
    local bucket = (type(drill_key) == "string" and drill_key ~= "") and drill_key
        or ui.UNKNOWN_DRILL_KEY
    S.record_attempt(stats, class_key, grade, bucket)
    local xp_after = session.xp
    if type(xp_after) ~= "number" then xp_after = 0 end
    local after = P.level_info(P.scope_xp(progress, class_key))
    -- The grade's own points: what the attempt WOULD have earned without the cap.
    -- nil (not 0) is the seed: a 0 would be a number and the pure module's own copy
    -- of the table - the fallback for a grade the live table does not know - would
    -- never be consulted.
    local points = nil
    local live_points = st.practice and st.practice.GRADE_POINTS
    if type(live_points) == "table" then
        points = live_points[grade]
    end
    if type(points) ~= "number" and type(P.GRADE_POINTS) == "table" then
        points = P.GRADE_POINTS[grade]
    end
    if type(points) ~= "number" then points = 0 end
    -- The award was swallowed: the grade earned points but nothing moved - neither
    -- the session's XP nor the scope's. That is the daily per-drill cap.
    local swallowed = (xp_after <= xp_before) and (after.xp <= before.xp)
    -- M4: the daily cap must never freeze SILENTLY. With no calendar day the cap's
    -- counter cannot reset, so the drill's XP is swallowed for good - the player is
    -- told (once per session) instead of watching the numbers quietly stop.
    if day == nil and swallowed and points > 0 and not ui.progress_cap_notice then
        ui.progress_cap_notice = true
        if type(self) == "table" and type(self.Print) == "function" then
            self:Print("Practice XP: this client reports no calendar date, so the daily XP "
                .. "cap cannot reset - this drill earns XP only up to its cap until the "
                .. "client provides a date.")
        end
    end
    -- H2 (progression audit 2026-10-20): with a VALID day the swallow was
    -- COMPLETELY silent - the notice above is gated on "no calendar day". The badge
    -- showed no "+N XP", the XP bar stopped, the level stopped and the score kept
    -- counting, and the player was told NOTHING. That happens to every player,
    -- every day, after ~3 attempts on a drill. The notice is now per DRILL per DAY:
    -- the drill's bucket carries the day it was told for, so the next calendar day
    -- tells it again. It is printed through self:Print and NOT through the
    -- badge-gated announce(): a progression dead end must be reported even when
    -- the badge is off.
    if day ~= nil and swallowed and points > 0 then
        local notices = ui.progress_cap_notice_days
        if type(notices) ~= "table" then
            notices = {}
            ui.progress_cap_notice_days = notices
        end
        if notices[bucket] ~= day then
            notices[bucket] = day
            if type(self) == "table" and type(self.Print) == "function" then
                self:Print("Practice XP: this drill has reached today's XP cap (3x its median "
                    .. "hit XP); it earns again after the next day.")
            end
        end
    end
    if after.raw_level > before.raw_level then
        announce_level_up(self, after)
        ui.persist_progress(self)
    end
    ui.update_badge(self)
end

-- Records one graded attempt in BOTH the live session score and the progression
-- state: the scoring model owns the score, the pure progression/stats modules own
-- the XP, the mastery, the streaks and the lifetime counters. This is the single
-- entry point every graded attempt goes through (the engine's grading path calls
-- it), so the score and the progression can never drift apart.
function ui.record_graded_attempt(self, grade, lead_ms)
    local pr = st.practice
    if not pr or not grade then
        return
    end
    -- L4 (progression audit 2026-10-20): the live score model counts ANY grade it
    -- is handed, while the pure modules drop a grade outside the scoring model's
    -- set. Validate first, so the score and the progression can never drift apart.
    local P = st.practice_progress
    if P and type(P.known_grade) == "function" and not P.known_grade(grade) then
        return
    end
    if ui.score then
        pr.record_attempt(ui.score, grade, lead_ms)
    end
    ui.record_progress_attempt(self, grade)
end

-- The session ends: the completion bonus, the daily streak, the time active, the
-- bounded history and the achievement evaluation. The write happens once, here.
function ui.end_progress_session(self, now)
    local P = st.practice_progress
    local S = st.practice_stats
    local pr = st.practice
    if not P or not S then
        return
    end
    local profile = ui.progress_profile
    local session = ui.progress_session
    local class_key = ui.progress_class_key
    if not profile or not session or not class_key then
        return
    end
    local progress = profile.progress
    local stats = profile.stats
    if type(progress) ~= "table" or type(stats) ~= "table" then
        return
    end
    local stamp = now or api.get_time()
    local duration = 0
    if type(ui.progress_started_at) == "number" then
        duration = stamp - ui.progress_started_at
    end
    if type(duration) ~= "number" or duration < 0 then
        duration = 0
    end
    local summary = {}
    if pr and ui.score then
        summary = pr.score_summary(ui.score)
    end
    local day = current_day()
    -- The stats side: the run, the time active, the best session score and the
    -- bounded history ring (a session with no attempts is not a completed session).
    S.record_session(stats, class_key, summary, duration, day)
    -- The progression side: the completion bonus and the daily streak.
    local result = P.end_session(progress, session, class_key, day, {})
    -- The achievements: the merged snapshot feeds the predicates (spec §4).
    local stats_snapshot = S.snapshot(stats)
    local snapshot = P.profile_snapshot(progress, stats_snapshot, class_key)
    -- M2 (progression audit 2026-10-20): the ACCOUNT scope is a scope of its own -
    -- its unlock flags live in progress.global.unlocks - so it needs its own
    -- evaluation, or every account-scoped achievement stays locked for good.
    local account = P.profile_snapshot(progress, stats_snapshot, P.GLOBAL_SCOPE)
    local unlocked = P.evaluate_unlocks_both(progress, class_key, snapshot, account)
    ui.progress_new_unlocks = unlocked.newly
    announce_unlocks(self, unlocked.newly)
    if result and result.leveled_up then
        announce_level_up(self, { level = result.level, renown = result.renown })
    end
    -- M1 (progression audit 2026-10-20): the write's outcome rides the result, so
    -- the caller can tell "the session closed" from "the session was SAVED". The
    -- old flush reported only the close.
    local written = ui.persist_progress(self, stamp)
    if type(result) == "table" then
        result.persisted = (written == true)
    end
    ui.progress_session = nil
    ui.progress_started_at = nil
    ui.progress_class_key = nil
    ui.progress_drill_key = nil
    ui.update_badge(self)
    return result
end

-- The progression flush: the session's completion bonus, its daily streak, its run,
-- its time active and its bounded history row are written - WITHOUT the frame
-- teardown ui.stop performs.
--
-- H2 (deep audit 2026-10-20): end_progress_session had exactly ONE caller - the
-- session stop - so a player who practised and then logged out kept the
-- per-attempt XP but lost the run, the time, the history row and - for good -
-- the daily streak. The flush is now the one writer: the session stop, the logout
-- path (main.lua's PLAYER_LOGOUT) and the practice panel's hide.
--
-- (A UI /reload is NOT covered, and cannot be: the client fires no logout event
-- on a reload and writes no SavedVariables there - it serialises them at logout
-- only. Nothing an addon does at reload time can reach the disk.)
--
-- A logout is NOT a session end: the frames are left alone (tearing them down
-- there is a separate risk), and the flush is idempotent - a session that is
-- already closed flushes nothing.
function ui.flush_progress_session(self, now)
    self = self or ST
    if type(ui.progress_session) ~= "table" then
        return false
    end
    -- The session end returns its result (nil when it could not close the session).
    local result = ui.end_progress_session(self, now)
    if type(result) ~= "table" then
        return false
    end
    -- M1 (progression audit 2026-10-20): the flush reported "I closed the session",
    -- not "I wrote it" - so a session whose saved blob a NEWER build owns closed
    -- cleanly and reported SUCCESS while nothing was written. The guard saw no
    -- error, so /st diag stayed clean and the player was told nothing. The flush
    -- now reports the WRITE, so the logout boundary sees the refusal.
    return result.persisted == true
end

-- The reset hook (M1): the Progress page's reset erases the saved progress, so the
-- LIVE session's own counters go with it. The session keeps running - the score,
-- the simulation and the panel are untouched - but its progression bookkeeping
-- restarts from zero: a session that kept its pre-reset attempts would award a
-- completion bonus for attempts the player just erased, and the badge's "+N XP"
-- would count XP that no longer exists.
--
-- The pure module owns the session's shape, so the fresh session comes from it.
function ui.reset_progress_session(self)
    self = self or ST
    local P = st.practice_progress
    if type(ui.progress_session) ~= "table" then
        return false
    end
    if not P or type(P.new_session) ~= "function" then
        ui.progress_session = nil
        ui.update_badge(self)
        return false
    end
    local ok, fresh = pcall(P.new_session)
    if not ok or type(fresh) ~= "table" then
        ui.progress_session = nil
        ui.update_badge(self)
        return false
    end
    ui.progress_session = fresh
    -- L5 (re-audit 2026-10-20): the M4 cap notice is per session, and the reset
    -- starts a NEW session - so the notice is cleared with it. Without this the
    -- notice (the client reports no calendar date, so the daily cap cannot
    -- reset) could fire only once per login and the rest of the session was
    -- silent again.
    ui.progress_cap_notice = nil
    -- H2 (progression audit 2026-10-20): the per-drill-per-day cap latch goes with
    -- the session too - the reset wipes the drill's daily XP, so the cap bites
    -- again from zero and the player must be told again.
    ui.progress_cap_notice_days = nil
    -- The badge repaints: the erased XP must not stay on it.
    ui.update_badge(self)
    return true
end

-- Repaints the badge: the class level, the XP into the level, the level bar and the
-- XP the live session earned. Hidden unless the opt-in toggle is on.
function ui.update_badge(self)
    local badge = ui.badge_frame
    if not badge then
        return
    end
    if not ui.badge_enabled then
        badge:Hide()
        return
    end
    local P = st.practice_progress
    if not P then
        badge:Hide()
        return
    end
    -- The profile is ensured here too, so the badge can be turned on before the
    -- first session (it then reads the saved level, not a blank one).
    local profile = ui.ensure_progress_profile(self)
    if not profile then
        badge:Hide()
        return
    end
    local progress = profile.progress
    local class_key = ui.progress_class_key or progress_class_key()
    if type(progress) ~= "table" or not class_key then
        badge:Hide()
        return
    end
    local info = P.level_info(P.scope_xp(progress, class_key))
    local level_text = string.format("Lv %d", info.level)
    if (info.renown or 0) > 0 then
        level_text = string.format("Lv %d +%d", info.level, info.renown)
    end
    badge.level:SetText(level_text)
    local into = info.xp_into_level or 0
    local need = info.xp_for_next_level or 0
    badge.xp:SetText(string.format("%d/%d", into, need))
    local frac = 0
    if need > 0 then
        frac = into / need
        if frac < 0 then frac = 0 end
        if frac > 1 then frac = 1 end
    end
    badge.bar_fill:SetWidth(math.floor(BADGE_BAR_WIDTH * frac + 0.5))
    local session_xp = 0
    if type(ui.progress_session) == "table" then
        session_xp = ui.progress_session.xp or 0
    end
    if type(session_xp) ~= "number" or session_xp <= 0 then
        badge.session:SetText("")
    else
        badge.session:SetText(string.format("+%d XP", math.floor(session_xp)))
    end
    badge:Show()
end

-- Display name for a panel icon key (keybind capture prompt + finish message):
-- the paladin engine name, else the ACTIVE class's own drill label, else the raw
-- key. The class owns its labels (class-isolation 2026-10-21): the shared layer
-- asks the provider, never a named module.
local function ability_display_name(key)
    local pr = st.practice
    local ab = pr and pr.ABILITIES[key]
    if ab and ab.name then
        return ab.name
    end
    local panel = ui.practice_panel()
    if panel and type(panel.label) == "function" then
        local ok, label = pcall(panel.label, key)
        if ok and label then
            return label
        end
    end
    return key
end

-- Icon texture for an ability key (panel icons, timeline cast events).
local function ability_texture(key)
    local pr = st.practice
    local ab = pr and pr.ABILITIES[key]
    if not ab then
        return nil
    end
    if ab.texture then
        return ab.texture
    end
    return spell_texture(ab.spell_id)
end

-- Applies a started-or-updated cooldown swipe once per cooldown, following the
-- codebase's set-once latch pattern (nextaction_ui.lua set_icon_cooldown). `state` is
-- the per-swipe bookkeeping table ({swipe_set, swipe_prev}); an upward jump in
-- remaining means a new cooldown started without an observed gap.
local function set_swipe(state, cooldown, remaining, full_duration)
    remaining = remaining or 0
    if remaining > (state.swipe_prev or 0) + 0.1 then
        state.swipe_set = false
    end
    state.swipe_prev = remaining
    if remaining > 0 then
        if not state.swipe_set then
            cooldown:SetCooldown(api.get_time() - (full_duration - remaining), full_duration)
            state.swipe_set = true
        end
    elseif state.swipe_set then
        cooldown:SetCooldown(0, 0)
        state.swipe_set = false
    end
end

-- The archive's button widget (create_toggle_button 735-759), minus the toggle state
-- colours the practice UI sets through update_button.
local function create_button(parent, label)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(90, 22)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    btn.label = btn:CreateFontString(nil, "OVERLAY")
    btn.label:SetPoint("CENTER", 0, 0)
    btn.label:SetFontObject(GameFontHighlightSmall)
    btn.label:SetText(label)
    return btn
end

-- One clickable ability icon (archive create_ability_row body 634-691, minus the
-- action-bar linking: right-click assigns a session-local key through the capture
-- overlay, left-click casts): icon texture, border, ability-cooldown swipe,
-- GCD swipe + GCD dim overlays, keybind label, left-click cast.
local function create_ability_icon(parent, key, ab)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon.key = key

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    local texture = ab.texture
    if not texture and ab.spell_id and api.GetSpellInfo then
        texture = select(3, api.GetSpellInfo(ab.spell_id))
    end
    if texture then
        icon.texture:SetTexture(texture)
    end
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    icon.border = icon:CreateTexture(nil, "OVERLAY", nil, 1)
    icon.border:SetPoint("TOPLEFT", -1, 1)
    icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
    icon.border:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    icon.border:SetDrawLayer("OVERLAY", -1)

    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetDrawEdge(false)
    if icon.cooldown.SetHideCountdownNumbers then
        icon.cooldown:SetHideCountdownNumbers(true)
    end

    icon.gcd_cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.gcd_cooldown:SetAllPoints()
    icon.gcd_cooldown:SetDrawEdge(false)
    if icon.gcd_cooldown.SetHideCountdownNumbers then
        icon.gcd_cooldown:SetHideCountdownNumbers(true)
    end

    icon.gcd_dim = icon:CreateTexture(nil, "OVERLAY")
    icon.gcd_dim:SetAllPoints()
    icon.gcd_dim:SetColorTexture(0, 0, 0, 0.5)
    icon.gcd_dim:Hide()

    -- Keybind label (archive 666-670; text comes from update_keybind_labels).
    icon.keybind_text = icon:CreateFontString(nil, "OVERLAY")
    icon.keybind_text:SetPoint("BOTTOM", icon, "BOTTOM", 0, 2)
    icon.keybind_text:SetFontObject(NumberFontNormalSmallGray or GameFontHighlightSmall)
    icon.keybind_text:SetText("")

    icon:EnableMouse(true)
    icon:SetScript("OnMouseDown", function(_, button)
        if not ui.active then
            return
        end
        if button == "RightButton" then
            ui.start_key_capture(ST, key)
        elseif button == "LeftButton" then
            ui.cast_key(ST, key)
        end
    end)

    -- Icon mapping for refresh_icons: the sim cooldown field where the engine keeps one
    -- (cs/judge/consec/aw/abacus - every ability with a cooldown), and whether the sim's
    -- GCD gates the cast (everything except Judgement, AW, the trinket and stopattack;
    -- see practice.lua cast()'s gate). Both swipe bookkeeping tables use the set-once
    -- latch above.
    icon.cooldown_field = (ab.cooldown and ab.cooldown > 0) and (key .. "_cooldown_expires") or nil
    icon.cooldown_full = ab.cooldown
    icon.gcd_gated = not (key == "judge" or ab.type == "buff" or ab.type == "haste_trinket"
        or ab.type == "stopattack")
    icon.ability_swipe = {}
    icon.gcd_swipe = {}
    return icon
end

--=========================================================================================
-- Frame construction (called once from ST.PALADIN.post_init, out of combat)
--=========================================================================================
function ui.init(self)
    if ui.panel then
        return
    end
    local pr = st.practice
    if not pr then
        -- The pure engine module is not loaded on this flavor: nothing to run.
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        -- Frames are only ever created out of combat. The init deadline in main.lua can
        -- land while the player is already in combat (reload mid-fight): retry shortly
        -- instead of leaving practice unavailable for the rest of the session.
        if not ui.init_retry_armed then
            ui.init_retry_armed = true
            C_Timer.After(1, function()
                ui.init_retry_armed = false
                ui.init(self)
            end)
        end
        return
    end
    ui.sim = pr.new_sim()
    ui.bar_mappings = {}
    -- Reused output tables: no per-frame allocations (the engine fills them).
    ui.out = {}
    ui.grade_out = {}
    ui.cast_out = {}
    ui.combat_paused = false
    ui.result_remaining = 0
    ui.dst_enabled = false
    ui.keybinds = {}
    ui.timeline_events = {}
    ui.timeline_event_count = 0
    ui.timeline_bands = {}
    ui.timeline_band_count = 0
    ui.timeline_visible = false
    ui.timeline_needs_render = false
    ui.score = nil
    ui.bests = nil
    ui.last_score_text = nil
    ui.rot_x = ROT_DISPLAY_DEFAULT_X
    ui.rot_y = ROT_DISPLAY_DEFAULT_Y
    ui.current_display_rotation = nil
    ui.build_result_frame(self)
    ui.build_panel(self)
    ui.build_key_buttons(self)
    ui.build_rotation_display(self)
    ui.build_timeline(self)
    ui.build_proc_icons(self)
    ui.apply_settings(self)
end

-- SoD-safe result font (mirrors hud.lua apply_font): a FontString with no font
-- throws on SetText ("Font not set"). Set the real font BEFORE the first SetText;
-- update_result_font re-applies through the same helper (the single restyle path).
-- Fallback chain is LSM font -> STANDARD_TEXT_FONT -> the classic client font,
-- all pcall-guarded and nil-safe so a missing LSM / throwing Fetch / missing
-- STANDARD / missing db never throws out of the result build.
local function apply_result_font(text, self)
    if type(text) ~= "table" or type(text.SetFont) ~= "function" then
        return
    end
    local size = 28
    local font_key = "Expressway"
    if self and type(self.get_class_table) == "function" and type(self.get_hand_table) == "function" then
        local ok_db, db = pcall(self.get_class_table, self)
        if ok_db and type(db) == "table" and type(db.practice_result_text_size) == "number" then
            size = db.practice_result_text_size
        end
        local ok_hand, hand_db = pcall(self.get_hand_table, self, "mainhand")
        if ok_hand and type(hand_db) == "table" and type(hand_db.text_font) == "string" then
            font_key = hand_db.text_font
        end
    end
    local std = rawget(_G, "STANDARD_TEXT_FONT") or RESULT_FALLBACK_FONT
    local path
    if type(LSM) == "table" and type(LSM.Fetch) == "function" then
        local ok_fetch, fetched = pcall(LSM.Fetch, LSM, "font", font_key)
        if ok_fetch then
            path = fetched
        end
    end
    local ok
    local has_font = false
    if path then
        local ok_set, res = pcall(text.SetFont, text, path, size, "OUTLINE")
        if ok_set then
            ok = res
        end
        if type(text.GetFont) == "function" then
            local ok_get, got = pcall(text.GetFont, text)
            if ok_get then
                has_font = got ~= nil
            end
        end
    end
    if ok == false or not has_font then
        pcall(text.SetFont, text, std, size, "OUTLINE")
    end
end

function ui.build_result_frame(self)
    local result = CreateFrame("Frame", addon_name .. "PracticeResultFrame", UIParent)
    ui.result_frame = result
    result:SetSize(RESULT_WIDTH, RESULT_HEIGHT)
    anchor_to_mainhand_bar(self, result, "BOTTOM", "TOP", 0, 8)
    result:SetFrameStrata("HIGH")
    result.text = result:CreateFontString(nil, "OVERLAY")
    -- SoD crash fix: font BEFORE the first SetText (mirrors hud.lua create_icon).
    apply_result_font(result.text, self)
    result.text:SetPoint("CENTER", 0, 0)
    result.text:SetShadowColor(0, 0, 0, 1)
    result.text:SetShadowOffset(2, -2)
    result.text:SetText("")
    ui.update_result_font(self)
    result:SetAlpha(0)
end

function ui.build_panel(self)
    local panel = CreateFrame("Frame", addon_name .. "PracticeControlFrame", UIParent,
        "BackdropTemplate")
    ui.panel = panel
    panel:SetSize(PANEL_WIDTH, 160) -- resized to the content below
    anchor_to_mainhand_bar(self, panel, "TOPLEFT", "TOPRIGHT", PANEL_ANCHOR_GAP, 0)
    panel:SetFrameStrata("HIGH")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetClampedToScreen(true)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    panel:SetScript("OnDragStart", function(f)
        -- Repositioning is only ever user-driven and never during lockdown.
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        f:StartMoving()
    end)
    panel:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        ui.save_position(self)
    end)
    -- H2 (deep audit 2026-10-20): the panel's hide is a flush point. The
    -- progression session's completion bonus, its daily streak, its run, its time
    -- active and its history row are written when the panel goes away, so a
    -- session that ends WITHOUT the panel's stop still lands in the saved
    -- profile. The flush never tears the frames down - it only ends the
    -- progression session - and it is idempotent.
    --
    -- L1 (re-audit 2026-10-20): the flush applies only when the run is actually
    -- OVER. A hide while the run is alive used to end the progression session
    -- while the simulation kept running: the score kept moving while the XP, the
    -- mastery, the streak and the stats stopped recording - with no notice. A
    -- live run keeps its progression session here (re-opened if it was closed),
    -- so the score and the recording can never diverge.
    panel:SetScript("OnHide", function()
        if ui.active == true then
            if type(ui.progress_session) ~= "table" then
                ui.begin_progress_session(ST, api.get_time())
            end
            return
        end
        ui.flush_progress_session(ST)
    end)

    local y = -8

    -- Title (archive: "|cFFFF8800Twist Practice|r", GameFontNormal).
    panel.title = panel:CreateFontString(nil, "OVERLAY")
    panel.title:SetPoint("TOP", panel, "TOP", 0, y)
    panel.title:SetFontObject(GameFontNormal)
    panel.title:SetText("|cFFFF8800Twist Practice|r")
    -- A class with its own drill panel names it (the class's own title).
    local panel_provider = ui.practice_panel()
    if ui.practice_class_drill() and panel_provider
        and type(panel_provider.title) == "string" then
        panel.title:SetText(panel_provider.title)
    end
    y = y - 16

    -- Close button = stop the session (archive close_btn 590-597).
    local close_btn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close_btn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
    close_btn:SetSize(20, 20)
    close_btn:SetScript("OnClick", function()
        ui.stop(ST)
    end)

    -- Speed / GCD info line.
    panel.info_text = panel:CreateFontString(nil, "OVERLAY")
    panel.info_text:SetPoint("TOP", panel, "TOP", 0, y)
    panel.info_text:SetFontObject(GameFontHighlightSmall)
    panel.info_text:SetText("Speed: --  GCD: --")
    y = y - 16

    -- Rotation line (archive update_info_display 3677-3687, second half; paladin
    -- sim only - the hunter, shaman, rogue and druid drills have no rotation to show).
    if not ui.practice_class_drill() then
    panel.rotation_text = panel:CreateFontString(nil, "OVERLAY")
    panel.rotation_text:SetPoint("TOP", panel, "TOP", 0, y)
    panel.rotation_text:SetFontObject(GameFontHighlightSmall)
    panel.rotation_text:SetText("Rotation: --")
    y = y - 16
    end

    -- Ability grid: the engine's own order, two rows of five (archive row layout).
    -- The hunter drill shows its own shot order here (same widget, same
    -- casts-are-simulated flow; icon textures resolve through the class tables).
    -- A class that runs no sim session (its own drills are its session) gets NO
    -- icon grid: the twist sim's seal icons are not its actions.
    local pr = st.practice
    -- The active class's own drill order (its own facts) or the sim's order.
    local order = ui.practice_order()
    local class_drill = ui.practice_class_drill()
    local rows = math.ceil(#order / ICONS_PER_ROW)
    if practice_class_runs_sim_session() then
    for row = 1, rows do
        local first = (row - 1) * ICONS_PER_ROW + 1
        local last = math.min(row * ICONS_PER_ROW, #order)
        local count = last - first + 1
        local total_width = count * ICON_SIZE + (count - 1) * ICON_SPACING
        local start_x = -total_width / 2 + ICON_SIZE / 2
        for i = first, last do
            local key = order[i]
            local ab = pr.ABILITIES[key]
            if ab == nil and class_drill then
                ab = ui.practice_class_def(key)
            end
            if ab then
                local icon = create_ability_icon(panel, key, ab)
                icon:SetPoint("TOP", panel, "TOP",
                    start_x + (i - first) * (ICON_SIZE + ICON_SPACING), y)
                panel.ability_icons = panel.ability_icons or {}
                panel.ability_icons[key] = icon
            end
        end
        y = y - ICON_SIZE - 4
    end
    end
    y = y - 2

    -- Hint line: doubles as the real-combat pause notice.
    panel.hint_text = panel:CreateFontString(nil, "OVERLAY")
    panel.hint_text:SetPoint("TOP", panel, "TOP", 0, y)
    panel.hint_text:SetWidth(PANEL_WIDTH - 16)
    panel.hint_text:SetWordWrap(true)
    panel.hint_text:SetJustifyH("CENTER")
    st.utils.apply_font(panel.hint_text, STANDARD_TEXT_FONT, 9, "")
    panel.hint_text:SetTextColor(0.5, 0.5, 0.5, 0.8)
    panel.hint_text:SetText(HINT_STOPPED)
    y = y - 26

    -- Start/Stop Fight button.
    panel.fight_btn = create_button(panel, "Start Fight")
    panel.fight_btn:SetPoint("TOP", panel, "TOP", 0, y)
    panel.fight_btn:SetScript("OnClick", function()
        ui.toggle_fight(ST)
    end)
    y = y - 22

    -- Fight timer text (archive 875-879; empty outside fights).
    panel.fight_timer_text = panel:CreateFontString(nil, "OVERLAY")
    panel.fight_timer_text:SetPoint("TOP", panel, "TOP", 0, y)
    panel.fight_timer_text:SetFontObject(GameFontHighlightSmall)
    panel.fight_timer_text:SetText("")
    y = y - 14

    -- Session score line (scoring section below; empty until the first attempt).
    panel.score_text = panel:CreateFontString(nil, "OVERLAY")
    panel.score_text:SetPoint("TOP", panel, "TOP", 0, y)
    panel.score_text:SetFontObject(GameFontHighlightSmall)
    panel.score_text:SetText("")
    y = y - 14

    -- Session resource line (sim-resources lane): empty unless a drill owns a
    -- resource pool (set explicitly through the setters below; no pool runs
    -- the panel exactly as before - no default-visible change).
    panel.resource_text = panel:CreateFontString(nil, "OVERLAY")
    panel.resource_text:SetPoint("TOP", panel, "TOP", 0, y)
    panel.resource_text:SetFontObject(GameFontHighlightSmall)
    panel.resource_text:SetText("")
    panel.resource_text:Hide()
    y = y - 14

    -- Paladin sim widgets below (haste, DST, rotation presets, timeline): the hunter
    -- drill panel skips them - same panel frame and session flow, drill contents.
    -- The shaman drill skips them too (no twist sim, no locked rotations, the drill
    -- swing is the only clock and the score line is the only readout).
    -- The rogue drill skips them too (no twist sim, no locked rotations, the drill
    -- tick and swing are the only clocks and the score line is the only readout).
    -- The druid drill skips them too (no twist sim, no locked rotations, the drill
    -- energy pool is the only clock and the score line is the only readout).
    -- A class that runs no sim session at all (its own drills are its session)
    -- skips them too: the twist sim's widgets are not its practice.
    if practice_class_runs_sim_session() and not ui.practice_class_drill() then
    -- Haste buttons (archive 761-796): Bloodlust left, Haste Pot right, each with a
    -- countdown label. Bloodlust is silent during a fight (auto-controlled there).
    panel.bl_btn = create_button(panel, "Bloodlust")
    panel.bl_btn:ClearAllPoints()
    panel.bl_btn:SetPoint("TOPRIGHT", panel, "TOP", -2, y)
    panel.bl_btn:SetScript("OnClick", function()
        ui.click_haste(ST, "bl")
    end)
    panel.bl_btn.countdown = panel.bl_btn:CreateFontString(nil, "OVERLAY")
    panel.bl_btn.countdown:SetPoint("RIGHT", panel.bl_btn, "RIGHT", -4, 0)
    panel.bl_btn.countdown:SetFontObject(GameFontHighlightSmall)
    panel.bl_btn.countdown:SetText("")

    panel.hp_btn = create_button(panel, "Haste Pot")
    panel.hp_btn:ClearAllPoints()
    panel.hp_btn:SetPoint("TOPLEFT", panel, "TOP", 2, y)
    panel.hp_btn:SetScript("OnClick", function()
        ui.click_haste(ST, "hpot")
    end)
    panel.hp_btn.countdown = panel.hp_btn:CreateFontString(nil, "OVERLAY")
    panel.hp_btn.countdown:SetPoint("RIGHT", panel.hp_btn, "RIGHT", -4, 0)
    panel.hp_btn.countdown:SetFontObject(GameFontHighlightSmall)
    panel.hp_btn.countdown:SetText("")
    y = y - 28

    -- DST proc toggle (session-local; the archived practice_dst_enabled option is out
    -- of scope, so the toggle lives on the panel instead of in the options).
    panel.dst_btn = create_button(panel, "DST: Off")
    panel.dst_btn:SetPoint("TOP", panel, "TOP", 0, y)
    panel.dst_btn:SetScript("OnClick", function()
        ui.click_haste(ST, "dst")
    end)
    y = y - 28

    -- Rotation selector (archive 807-862): Raid Pull (auto) plus the three locked
    -- presets. Clicking the active preset reverts to auto (engine toggle semantics
    -- live in set_locked_rotation).
    local rot_label = panel:CreateFontString(nil, "OVERLAY")
    rot_label:SetPoint("TOP", panel, "TOP", 0, y)
    rot_label:SetFontObject(GameFontHighlightSmall)
    rot_label:SetText("Practice Rotation")
    y = y - 14

    panel.rot_buttons = {}
    local rot_btn_w, rot_btn_h = 88, 20
    local rot_btn_spacing = 2
    local rot_total_w = 2 * rot_btn_w + 1 * rot_btn_spacing
    for row_i, row in ipairs(ROT_GRID) do
        for col_i, rot_key in ipairs(row) do
            local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
            btn:SetSize(rot_btn_w, rot_btn_h)
            local bx = -rot_total_w / 2 + (col_i - 1) * (rot_btn_w + rot_btn_spacing)
                + rot_btn_w / 2
            local by = y - (row_i - 1) * (rot_btn_h + rot_btn_spacing)
            btn:SetPoint("TOP", panel, "TOP", bx, by)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 8, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
            btn.label = btn:CreateFontString(nil, "OVERLAY")
            btn.label:SetPoint("CENTER", 0, 0)
            btn.label:SetFontObject(GameFontHighlightSmall)
            btn.label:SetText(ROT_LABELS[rot_key] or rot_key)
            btn.rot_key = rot_key
            btn:SetScript("OnClick", function(self_btn)
                if self_btn.rot_key == "auto" then
                    ui.set_locked_rotation(ST, nil)
                else
                    ui.set_locked_rotation(ST, self_btn.rot_key)
                end
            end)
            panel.rot_buttons[rot_key] = btn
        end
    end
    y = y - (#ROT_GRID * (rot_btn_h + rot_btn_spacing) + 4)

    -- Timeline toggle button (archive 895-899).
    panel.timeline_btn = create_button(panel, "Timeline")
    panel.timeline_btn:ClearAllPoints()
    panel.timeline_btn:SetPoint("TOP", panel, "TOP", 0, y)
    panel.timeline_btn:SetScript("OnClick", function()
        ui.toggle_timeline(ST)
    end)
    y = y - 28
    end

    panel:SetHeight(math.abs(y) + 8)
    -- The panel's shipped height: the practice row (the scenario / drill strip)
    -- grows the panel while it is up and restores this height when it goes away.
    ui.panel_base_height = math.abs(y) + 8
    panel:Hide()

    -- The practice level badge (the gamification hook): a small companion frame
    -- UNDER the panel's bottom-left corner. The panel's own rows are full (the
    -- title, the icon grid and the rotation grid span its whole width), so the
    -- badge hangs below the panel instead of overlapping any of them, and the
    -- panel's height is untouched - the badge is an overlay, not a new row.
    -- It stays HIDDEN unless the opt-in toggle (practice_panel_badge) is on, so
    -- a fresh profile sees exactly the panel it saw before.
    local badge = CreateFrame("Frame", addon_name .. "PracticeBadge", panel, "BackdropTemplate")
    ui.badge_frame = badge
    badge:SetSize(BADGE_WIDTH, BADGE_HEIGHT)
    badge:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -4)
    badge:SetFrameStrata("HIGH")
    badge:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    badge:SetBackdropColor(0, 0, 0, 0.75)
    badge:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    badge.level = badge:CreateFontString(nil, "OVERLAY")
    badge.level:SetPoint("TOPLEFT", badge, "TOPLEFT", BADGE_BAR_INSET, -5)
    badge.level:SetFontObject(GameFontHighlightSmall)
    badge.level:SetText("")
    badge.xp = badge:CreateFontString(nil, "OVERLAY")
    badge.xp:SetPoint("TOPRIGHT", badge, "TOPRIGHT", -BADGE_BAR_INSET, -5)
    badge.xp:SetFontObject(GameFontHighlightSmall)
    badge.xp:SetText("")
    badge.bar_bg = badge:CreateTexture(nil, "BACKGROUND")
    badge.bar_bg:SetPoint("TOPLEFT", badge, "TOPLEFT", BADGE_BAR_INSET, -18)
    badge.bar_bg:SetSize(BADGE_BAR_WIDTH, BADGE_BAR_HEIGHT)
    badge.bar_bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    badge.bar_fill = badge:CreateTexture(nil, "ARTWORK")
    badge.bar_fill:SetPoint("TOPLEFT", badge.bar_bg, "TOPLEFT", 0, 0)
    badge.bar_fill:SetHeight(BADGE_BAR_HEIGHT)
    badge.bar_fill:SetWidth(0)
    badge.bar_fill:SetColorTexture(0.85, 0.70, 0.20, 1)
    badge.session = badge:CreateFontString(nil, "OVERLAY")
    badge.session:SetPoint("BOTTOMLEFT", badge, "BOTTOMLEFT", BADGE_BAR_INSET, 4)
    badge.session:SetFontObject(GameFontHighlightSmall)
    badge.session:SetText("")
    badge:Hide()

    -- Driver: the module's own OnUpdate frame (see the header); hidden outside sessions.
    local driver = CreateFrame("Frame", addon_name .. "PracticeDriverFrame", UIParent)
    ui.driver = driver
    driver:SetScript("OnUpdate", function(_, elapsed)
        ui.tick(ST, elapsed)
    end)
    driver:Hide()

    ui.build_bar_mappings(self)
end

--=========================================================================================
-- Bar mappings (phase 2: the panel icon bar itself; action-bar overlays land in phase 3)
--=========================================================================================
function ui.build_bar_mappings(self)
    local panel = ui.panel
    if not panel or not panel.ability_icons then
        return
    end
    ui.bar_mappings = ui.bar_mappings or {}
    for key, icon in pairs(panel.ability_icons) do
        ui.bar_mappings[key] = icon
    end
end

--=========================================================================================
-- Keybinds: session-local capture + override bindings
--=========================================================================================

-- Invisible click targets for SetOverrideBindingClick (archive init 506-522). The
-- buttons live on the panel so they die with it; bindings are applied by
-- rebind_keys() and cleared on stop().
function ui.build_key_buttons(self)
    local panel = ui.panel
    if not panel then
        return
    end
    local pr = st.practice
    if not pr then
        return
    end
    -- The hunter drill binds its own shot order (same capture flow, drill keys).
    local order = ui.practice_order()
    ui.buttons = ui.buttons or {}
    for _, key in ipairs(order) do
        if not ui.buttons[key] then
            local btn = CreateFrame("Button", addon_name .. "PracticeKey" .. key, panel)
            btn:SetSize(1, 1)
            btn:SetPoint("CENTER", panel, "CENTER", 0, 0)
            btn:EnableMouse(false)
            if btn.RegisterForClicks then
                btn:RegisterForClicks("AnyUp")
            end
            btn.key_name = addon_name .. "PracticeKey" .. key
            local capture = key
            btn:SetScript("OnClick", function()
                ui.cast_key(ST, capture)
            end)
            ui.buttons[key] = btn
        end
    end
end

-- Applies the session-local keybinds as override bindings (archive rebind_keys
-- 1309-1326, minus persistence). Safe to call under lockdown: it simply skips the
-- apply and leaves the labels alone.
function ui.rebind_keys(self)
    local panel = ui.panel
    if not panel or not ui.buttons then
        return
    end
    if not (ui.active and SetOverrideBindingClick and ClearOverrideBindings) then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    ClearOverrideBindings(panel)
    local pr = st.practice
    if not pr then
        return
    end
    local order = ui.practice_order()
    for _, key in ipairs(order) do
        local bind = ui.keybinds and ui.keybinds[key]
        local btn = ui.buttons[key]
        if bind and bind ~= "" and btn then
            local name = (btn.GetName and btn:GetName()) or btn.key_name
            SetOverrideBindingClick(panel, false, bind, name)
        end
    end
    ui.update_keybind_labels(self)
end

-- Refreshes the keybind labels on the panel icons from ui.keybinds.
function ui.update_keybind_labels(self)
    local panel = ui.panel
    if not panel or not panel.ability_icons then
        return
    end
    local pr = st.practice
    if not pr then
        return
    end
    local order = ui.practice_order()
    for _, key in ipairs(order) do
        local icon = panel.ability_icons[key]
        if icon and icon.keybind_text then
            local bind = ui.keybinds and ui.keybinds[key] or ""
            icon.keybind_text:SetText(pr.shorten_keybind(bind))
        end
    end
end

-- Modifier prefix from the current key state (archive get_modifier_prefix 228-234).
local function capture_modifier_prefix()
    local prefix = ""
    if IsControlKeyDown and IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsAltKeyDown and IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsShiftKeyDown and IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    return prefix
end

-- Lazily creates the fullscreen key-capture overlay (archive 261-332, trimmed: no
-- gamepad-emulator CVar probe beyond the guarded EnableGamePadButton hook).
local function get_or_create_key_capture_frame()
    if ui.key_capture_frame then
        return ui.key_capture_frame
    end
    local f = CreateFrame("Frame", addon_name .. "PracticeKeyCapture", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:EnableMouse(true)
    if f.EnableMouseWheel then
        f:EnableMouseWheel(true)
    end
    if f.EnableKeyboard then
        f:EnableKeyboard(false)
    end

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 0, 0, 0.5)

    f.prompt = f:CreateFontString(nil, "OVERLAY")
    st.utils.apply_font(f.prompt, STANDARD_TEXT_FONT, 16, "OUTLINE")
    f.prompt:SetPoint("CENTER", 0, 20)
    f.prompt:SetTextColor(1, 1, 1, 1)

    f.hint = f:CreateFontString(nil, "OVERLAY")
    st.utils.apply_font(f.hint, STANDARD_TEXT_FONT, 11, "OUTLINE")
    f.hint:SetPoint("CENTER", 0, -10)
    f.hint:SetTextColor(0.7, 0.7, 0.7, 1)
    f.hint:SetText("ESC or right-click to cancel")

    f:SetScript("OnKeyDown", function(_, key)
        if IGNORE_KEYS[key] then
            return
        end
        if key == "ESCAPE" then
            ui.cancel_key_capture(ST)
            return
        end
        ui.finish_key_capture(ST, capture_modifier_prefix() .. key)
    end)

    f:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            return
        end
        if button == "RightButton" then
            ui.cancel_key_capture(ST)
            return
        end
        local mouse_map = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
        local mapped = mouse_map[button] or button
        ui.finish_key_capture(ST, capture_modifier_prefix() .. mapped)
    end)

    f:SetScript("OnMouseWheel", function(_, delta)
        local key = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
        ui.finish_key_capture(ST, capture_modifier_prefix() .. key)
    end)

    if f.EnableGamePadButton then
        f:SetScript("OnGamePadButtonDown", function(_, button)
            ui.finish_key_capture(ST, capture_modifier_prefix() .. button)
        end)
    end

    f:Hide()
    ui.key_capture_frame = f
    return f
end

-- Starts capturing a key for an ability (right-click a panel icon). Pre-init safe.
function ui.start_key_capture(self, ability_key)
    self = self or ST
    if not ui.active or not ability_key then
        return
    end
    ui.key_capture_ability = ability_key
    local name = ability_display_name(ability_key)
    local f = get_or_create_key_capture_frame()
    f.prompt:SetText("Press the key for |cFF00FFFF" .. name .. "|r")
    if f.EnableKeyboard then
        f:EnableKeyboard(true)
    end
    if f.EnableGamePadButton then
        f:EnableGamePadButton(true)
    end
    if f.SetPropagateKeyboardInput then
        f:SetPropagateKeyboardInput(false)
    end
    f:Show()
    self:Print(string.format("Press the key for %s (ESC to cancel).", name))
end

-- Stores a captured key (archive finish_key_capture 4157-4186, minus persistence).
function ui.finish_key_capture(self, bind)
    self = self or ST
    local ability_key = ui.key_capture_ability
    if not ability_key then
        return
    end
    ui.cancel_key_capture(self)
    ui.keybinds = ui.keybinds or {}
    ui.keybinds[ability_key] = bind
    if ui.active then
        ui.rebind_keys(self)
    end
    ui.update_keybind_labels(self)
    local name = ability_display_name(ability_key)
    self:Print(string.format("Practice key for %s set to %s.", name, bind))
end

function ui.cancel_key_capture(self)
    ui.key_capture_ability = nil
    local f = ui.key_capture_frame
    if f then
        if f.EnableKeyboard then
            f:EnableKeyboard(false)
        end
        if f.EnableGamePadButton then
            f:EnableGamePadButton(false)
        end
        f:Hide()
    end
end

-- Restores the default keybinds and detaches every overlay (archive
-- reset_all_mappings 3944-3964, minus persistence).
function ui.reset_keybinds(self)
    self = self or ST
    ui.detach_all_overlays(self)
    ui.keybinds = {}
    local pr = st.practice
    if pr then
        for key, bind in pairs(pr.DEFAULT_KEYBINDS) do
            ui.keybinds[key] = bind
        end
    end
    if ui.active then
        ui.rebind_keys(self)
    end
    ui.update_keybind_labels(self)
    self:Print("Practice keybinds have been reset.")
end

--=========================================================================================
-- Haste buttons + rotation selector
--=========================================================================================

-- Haste button clicks (archive bl/hp button bodies 762-789): Bloodlust refuses while
-- a fight runs (auto-controlled there) or the rotation is locked; the haste pot goes
-- through the direct setter so no GCD starts, like the archive's button path.
function ui.click_haste(self, which)
    self = self or ST
    if not ui.active then
        return
    end
    local pr = st.practice
    local sim = ui.sim
    if not pr or not sim then
        return
    end
    local now = api.get_time()
    if which == "bl" then
        if sim.fight_active or sim.locked_rotation or sim.has_bloodlust then
            return
        end
        if pr.set_bloodlust(sim, now, true) then
            pr.apply_haste(sim, ui.base_speed, now)
            ui.update_haste_buttons(self)
            ui.update_info(self)
            ui.sync_to_addon(self)
        end
    elseif which == "hpot" then
        if sim.has_haste_pot then
            return
        end
        if pr.set_haste_pot(sim, now, true) then
            pr.apply_haste(sim, ui.base_speed, now)
            ui.update_haste_buttons(self)
            ui.update_info(self)
            ui.sync_to_addon(self)
        end
    elseif which == "dst" then
        ui.dst_enabled = not ui.dst_enabled
        if not ui.dst_enabled then
            sim.has_dst = false
            sim.dst_buff_expires = 0
            pr.apply_haste(sim, ui.base_speed, now)
        end
        ui.update_haste_buttons(self)
        ui.update_proc_icons(self)
    end
end

-- Countdown + active/disabled visuals for the three haste buttons (archive
-- sim_update 3336-3364 countdown halves + set_haste_buttons_enabled 1234-1256).
function ui.update_haste_buttons(self)
    local panel = ui.panel
    if not panel then
        return
    end
    local sim = ui.sim
    local now = api.get_time()
    local locked = sim and sim.locked_rotation or nil
    if panel.bl_btn then
        local remaining = (sim and sim.has_bloodlust and sim.bl_buff_expires > now)
            and math.ceil(sim.bl_buff_expires - now) or 0
        if panel.bl_btn.countdown then
            panel.bl_btn.countdown:SetText(remaining > 0 and tostring(remaining) or "")
        end
        if sim and sim.has_bloodlust then
            panel.bl_btn:SetBackdropColor(0.1, 0.3, 0.6, 0.9)
            panel.bl_btn.label:SetText("|cFF00FFFFBloodlust|r")
        else
            panel.bl_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            panel.bl_btn.label:SetText("Bloodlust")
        end
    end
    if panel.hp_btn then
        local remaining = (sim and sim.has_haste_pot and sim.haste_pot_buff_expires > now)
            and math.ceil(sim.haste_pot_buff_expires - now) or 0
        if panel.hp_btn.countdown then
            panel.hp_btn.countdown:SetText(remaining > 0 and tostring(remaining) or "")
        end
        if sim and sim.has_haste_pot then
            panel.hp_btn:SetBackdropColor(0.5, 0.3, 0.1, 0.9)
            panel.hp_btn.label:SetText("|cFFFF8800Haste Pot|r")
        else
            panel.hp_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            panel.hp_btn.label:SetText("Haste Pot")
        end
    end
    if panel.dst_btn then
        if ui.dst_enabled then
            panel.dst_btn:SetBackdropColor(0.1, 0.4, 0.1, 0.9)
            panel.dst_btn.label:SetText("|cFF00FF00DST: On|r")
        else
            panel.dst_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            panel.dst_btn.label:SetText("DST: Off")
        end
    end
    ui.set_haste_buttons_enabled(not locked)
end

-- Dims the Bloodlust/Haste-pot buttons while a rotation is locked (archive
-- set_haste_buttons_enabled 1234-1256).
function ui.set_haste_buttons_enabled(enabled)
    local panel = ui.panel
    if not panel then
        return
    end
    for _, btn in ipairs({ panel.bl_btn, panel.hp_btn }) do
        if btn then
            if enabled then
                btn:SetAlpha(1.0)
                btn:EnableMouse(true)
            else
                btn:SetAlpha(0.4)
                btn:EnableMouse(false)
            end
        end
    end
end

-- Locks (or unlocks, on a repeat click) a practice rotation (archive
-- set_locked_rotation 1258-1304): locking clears every haste effect and disables
-- the haste buttons; either way the speed/GCD are re-derived immediately.
function ui.set_locked_rotation(self, rot_key)
    self = self or ST
    local pr = st.practice
    local sim = ui.sim
    if not pr or not sim then
        return
    end
    if rot_key and rot_key == sim.locked_rotation then
        rot_key = nil
    end
    sim.locked_rotation = rot_key
    local now = api.get_time()
    if rot_key then
        pr.set_bloodlust(sim, now, false)
        pr.set_haste_pot(sim, now, false)
        sim.has_abacus = false
        sim.abacus_buff_expires = 0
        sim.has_dst = false
        sim.dst_buff_expires = 0
        ui.set_haste_buttons_enabled(false)
    else
        ui.set_haste_buttons_enabled(true)
    end
    pr.apply_haste(sim, ui.base_speed, now)
    local panel = ui.panel
    if panel and panel.rot_buttons then
        for key, btn in pairs(panel.rot_buttons) do
            local is_active = (key == "auto" and rot_key == nil) or (key == rot_key)
            if is_active then
                btn:SetBackdropColor(0.1, 0.4, 0.1, 0.9)
                btn.label:SetText("|cFF00FF00" .. (ROT_LABELS[key] or key) .. "|r")
            else
                btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
                btn.label:SetText(ROT_LABELS[key] or key)
            end
        end
    end
    ui.current_display_rotation = nil
    ui.update_rotation_display(self)
    ui.update_haste_buttons(self)
    ui.update_info(self)
    ui.refresh_icons(self)
    ui.sync_to_addon(self)
end

--=========================================================================================
-- Center-screen rotation display (archive 1461-1662)
--=========================================================================================

-- One rotation step icon (archive create_rotation_display_icon 1465-1498): a full
-- texture plus split halves for twist steps.
local function create_rotation_icon(parent, size)
    local icon_frame = CreateFrame("Frame", nil, parent)
    icon_frame:SetSize(size, size)

    icon_frame.border = icon_frame:CreateTexture(nil, "BACKGROUND")
    icon_frame.border:SetPoint("TOPLEFT", -1, 1)
    icon_frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    icon_frame.border:SetColorTexture(0, 0, 0, 0.8)

    icon_frame.texture = icon_frame:CreateTexture(nil, "ARTWORK")
    icon_frame.texture:SetAllPoints()
    icon_frame.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    icon_frame.twist_left = icon_frame:CreateTexture(nil, "ARTWORK")
    icon_frame.twist_left:SetPoint("TOPLEFT", 0, 0)
    icon_frame.twist_left:SetPoint("BOTTOMLEFT", 0, 0)
    icon_frame.twist_left:SetWidth(size / 2)
    icon_frame.twist_left:SetTexCoord(0.07, 0.5, 0.07, 0.93)
    icon_frame.twist_left:Hide()

    icon_frame.twist_right = icon_frame:CreateTexture(nil, "ARTWORK")
    icon_frame.twist_right:SetPoint("TOPRIGHT", 0, 0)
    icon_frame.twist_right:SetPoint("BOTTOMRIGHT", 0, 0)
    icon_frame.twist_right:SetWidth(size / 2)
    icon_frame.twist_right:SetTexCoord(0.5, 0.93, 0.07, 0.93)
    icon_frame.twist_right:Hide()

    icon_frame:Hide()
    return icon_frame
end

-- Paints one rotation step onto an icon frame (the archived
-- st.bar.set_rotation_icon_texture was never ported, so the mapping lives here):
-- twist is split Command/Blood halves, everything else a single spell texture.
local function set_step_texture(icon_frame, step)
    local left_hide, right_hide = true, true
    if step == "twist" then
        local cmd = spell_texture(COMMAND_SPELL_ID)
        local blood = spell_texture(BLOOD_SPELL_ID)
        if cmd then
            icon_frame.twist_left:SetTexture(cmd)
            left_hide = false
        end
        if blood then
            icon_frame.twist_right:SetTexture(blood)
            right_hide = false
        end
        if icon_frame.texture then
            icon_frame.texture:SetTexture(nil)
        end
    else
        local spell_id = STEP_SPELL_IDS[step]
        local tex = spell_texture(spell_id)
        if tex and icon_frame.texture then
            icon_frame.texture:SetTexture(tex)
        end
    end
    if left_hide then
        icon_frame.twist_left:Hide()
    else
        icon_frame.twist_left:Show()
    end
    if right_hide then
        icon_frame.twist_right:Hide()
    else
        icon_frame.twist_right:Show()
    end
end

-- Exposed for the timeline band icons (same step mapping).
function ui.set_step_texture(icon_frame, step)
    set_step_texture(icon_frame, step)
end

-- Builds the free-floating rotation display (archive create_rotation_display
-- 1501-1552, session-local position).
function ui.build_rotation_display(self)
    if not ui.panel then
        return
    end
    local frame = CreateFrame("Frame", addon_name .. "PracticeRotationDisplay", UIParent)
    ui.rotation_display = frame
    frame:SetSize(300, 100)
    frame:SetPoint("CENTER", UIParent, "CENTER", ui.rot_x or 0, ui.rot_y or 100)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(f)
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        f:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        ui.save_rotation_position(self)
    end)

    frame.rotation_name = frame:CreateFontString(nil, "OVERLAY")
    st.utils.apply_font(frame.rotation_name, STANDARD_TEXT_FONT, 15, "OUTLINE")
    frame.rotation_name:SetPoint("BOTTOM", frame, "CENTER", 0, ROT_ICON_SIZE / 2 + 4)
    frame.rotation_name:SetTextColor(1, 0.82, 0, 1)
    frame.rotation_name:SetShadowColor(0, 0, 0, 1)
    frame.rotation_name:SetShadowOffset(1, -1)
    frame.rotation_name:SetText("")

    frame.desc_text = frame:CreateFontString(nil, "OVERLAY")
    st.utils.apply_font(frame.desc_text, STANDARD_TEXT_FONT, 11, "OUTLINE")
    frame.desc_text:SetPoint("TOP", frame, "CENTER", 0, -(ROT_ICON_SIZE / 2 + 4))
    frame.desc_text:SetTextColor(0.65, 0.65, 0.65, 1)
    frame.desc_text:SetShadowColor(0, 0, 0, 1)
    frame.desc_text:SetShadowOffset(1, -1)
    frame.desc_text:SetText("")

    ui.rotation_icons = {}
    for i = 1, ROT_DISPLAY_MAX_ICONS do
        ui.rotation_icons[i] = create_rotation_icon(frame, ROT_ICON_SIZE)
    end
    frame:Hide()
end

-- Stores the dragged display position as a center offset (session-local).
function ui.save_rotation_position(self)
    local frame = ui.rotation_display
    if not frame or not UIParent then
        return
    end
    if not (frame.GetCenter and UIParent.GetCenter) then
        return
    end
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then
        return
    end
    ui.rot_x = math.floor(cx - ux + 0.5)
    ui.rot_y = math.floor(cy - uy + 0.5)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", ui.rot_x, ui.rot_y)
end

-- Updates the rotation display: texts + icons, static reference, no step tracking
-- (archive update_rotation_display 1582-1662). `rotation` may be passed by the tick
-- to avoid a second determine_rotation call.
function ui.update_rotation_display(self, rotation)
    local frame = ui.rotation_display
    if not frame then
        return
    end
    local pr = st.practice
    local sim = ui.sim
    if not pr or not sim then
        return
    end
    rotation = rotation or pr.determine_rotation(sim)
    if not ui.active or not rotation then
        ui.current_display_rotation = rotation
        frame:Hide()
        return
    end
    local na = st.nextaction
    local sequence = (na and na.sequences and na.sequences[rotation]) or {}
    if #sequence == 0 then
        ui.current_display_rotation = rotation
        frame:Hide()
        return
    end
    ui.current_display_rotation = rotation
    frame:Show()

    local display_name = (na and na.display_names and na.display_names[rotation]) or rotation
    local desc = (na and na.descriptions and na.descriptions[rotation]) or ""
    frame.rotation_name:SetText(display_name)
    frame.desc_text:SetText(desc)

    local size = ROT_ICON_SIZE
    local spacing = ROT_ICON_SPACING
    local num_icons = #sequence
    local total_width = (size * num_icons) + (spacing * (num_icons - 1))
    local start_x = -total_width / 2 + size / 2

    frame.rotation_name:ClearAllPoints()
    frame.rotation_name:SetPoint("BOTTOM", frame, "CENTER", 0, size / 2 + 4)
    frame.desc_text:ClearAllPoints()
    frame.desc_text:SetPoint("TOP", frame, "CENTER", 0, -(size / 2 + 4))
    frame:SetSize(math.max(total_width + 20, 100), size + 50)

    for i = 1, ROT_DISPLAY_MAX_ICONS do
        local icon_frame = ui.rotation_icons[i]
        if icon_frame then
            if i <= num_icons then
                icon_frame:SetSize(size, size)
                icon_frame.twist_left:SetWidth(size / 2)
                icon_frame.twist_right:SetWidth(size / 2)
                icon_frame:ClearAllPoints()
                local x_pos = start_x + (i - 1) * (size + spacing)
                icon_frame:SetPoint("CENTER", frame, "CENTER", x_pos, 0)
                set_step_texture(icon_frame, sequence[i])
                icon_frame:Show()
            else
                icon_frame:Hide()
            end
        end
    end
end

--=========================================================================================
-- Fight timeline (archive 1900-2510, trimmed)
--=========================================================================================

-- Timeline icon pool entry (archive get_timeline_icon 1901-1991, minus the
-- twist-overlay badge sub-frame: twists reuse the error-border-free split look).
local function get_timeline_icon(parent)
    ui.timeline_icon_pool = ui.timeline_icon_pool or {}
    ui.timeline_icon_pool_used = (ui.timeline_icon_pool_used or 0) + 1
    local idx = ui.timeline_icon_pool_used
    local pool = ui.timeline_icon_pool

    if pool[idx] then
        pool[idx]:Show()
        pool[idx].error_border:Hide()
        pool[idx].analysis_data = nil
        return pool[idx]
    end

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(TIMELINE_ICON_SIZE, TIMELINE_ICON_SIZE)

    f.texture = f:CreateTexture(nil, "ARTWORK")
    f.texture:SetAllPoints()
    f.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.split_left = f:CreateTexture(nil, "ARTWORK")
    f.split_left:SetPoint("TOPLEFT", 0, 0)
    f.split_left:SetPoint("BOTTOMLEFT", 0, 0)
    f.split_left:SetWidth(TIMELINE_ICON_SIZE / 2)
    f.split_left:SetTexCoord(0.07, 0.5, 0.07, 0.93)
    f.split_left:Hide()

    f.split_right = f:CreateTexture(nil, "ARTWORK")
    f.split_right:SetPoint("TOPRIGHT", 0, 0)
    f.split_right:SetPoint("BOTTOMRIGHT", 0, 0)
    f.split_right:SetWidth(TIMELINE_ICON_SIZE / 2)
    f.split_right:SetTexCoord(0.5, 0.93, 0.07, 0.93)
    f.split_right:Hide()

    f.result_label = f:CreateFontString(nil, "OVERLAY")
    st.utils.apply_font(f.result_label, STANDARD_TEXT_FONT, 9, "OUTLINE")
    f.result_label:SetPoint("BOTTOM", f, "TOP", 0, 0)
    f.result_label:SetText("")

    f.error_border = f:CreateTexture(nil, "BACKGROUND")
    f.error_border:SetPoint("TOPLEFT", -2, 2)
    f.error_border:SetPoint("BOTTOMRIGHT", 2, -2)
    f.error_border:SetColorTexture(0.8, 0.1, 0.1, 0.7)
    f.error_border:Hide()

    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self_icon)
        if self_icon.analysis_data and not self_icon.analysis_data.correct and GameTooltip then
            local pr = st.practice
            local labels = (pr and pr.SWING_ACTION_LABELS) or {}
            local expected = labels[self_icon.analysis_data.expected]
                or self_icon.analysis_data.expected
            local actual = labels[self_icon.analysis_data.actual]
                or self_icon.analysis_data.actual
            GameTooltip:SetOwner(self_icon, "ANCHOR_TOP")
            GameTooltip:AddLine("Incorrect action", 1, 0.2, 0.2)
            GameTooltip:AddLine("You did: " .. actual, 1, 1, 1)
            GameTooltip:AddLine("Expected: " .. expected, 0, 1, 0)
            if self_icon.analysis_data.actual == "judge_command" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Judging Rank 1 SoC is a large DPS loss.", 1, 0.5, 0.5)
            end
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    pool[idx] = f
    return f
end

local function reset_timeline_icon_pool()
    if not ui.timeline_icon_pool then
        return
    end
    for i = 1, (ui.timeline_icon_pool_used or 0) do
        if ui.timeline_icon_pool[i] then
            ui.timeline_icon_pool[i]:Hide()
        end
    end
    ui.timeline_icon_pool_used = 0
end

-- Divider pool (archive 2001-2022).
local function get_timeline_divider(parent)
    ui.timeline_divider_pool = ui.timeline_divider_pool or {}
    ui.timeline_divider_pool_used = (ui.timeline_divider_pool_used or 0) + 1
    local idx = ui.timeline_divider_pool_used
    local pool = ui.timeline_divider_pool

    if pool[idx] then
        pool[idx]:Show()
        return pool[idx]
    end

    local t = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
    t:SetColorTexture(0.4, 0.4, 0.4, 0.3)
    pool[idx] = t
    return t
end

local function reset_timeline_divider_pool()
    if not ui.timeline_divider_pool then
        return
    end
    for i = 1, (ui.timeline_divider_pool_used or 0) do
        if ui.timeline_divider_pool[i] then
            ui.timeline_divider_pool[i]:Hide()
        end
    end
    ui.timeline_divider_pool_used = 0
end

-- Ruler tick pool (archive 2025-2057).
local function get_ruler_tick(parent)
    ui.timeline_ruler_pool = ui.timeline_ruler_pool or {}
    ui.timeline_ruler_pool_used = (ui.timeline_ruler_pool_used or 0) + 1
    local idx = ui.timeline_ruler_pool_used
    local pool = ui.timeline_ruler_pool

    if pool[idx] then
        pool[idx].tick:Show()
        pool[idx].label:Show()
        return pool[idx]
    end

    local tick = parent:CreateTexture(nil, "ARTWORK")
    tick:SetColorTexture(0.6, 0.6, 0.6, 0.5)

    local label = parent:CreateFontString(nil, "OVERLAY")
    st.utils.apply_font(label, STANDARD_TEXT_FONT, 9, "OUTLINE")
    label:SetTextColor(0.7, 0.7, 0.7, 1)

    local entry = { tick = tick, label = label }
    pool[idx] = entry
    return entry
end

local function reset_timeline_ruler_pool()
    if not ui.timeline_ruler_pool then
        return
    end
    for i = 1, (ui.timeline_ruler_pool_used or 0) do
        local entry = ui.timeline_ruler_pool[i]
        if entry then
            entry.tick:Hide()
            entry.label:Hide()
        end
    end
    ui.timeline_ruler_pool_used = 0
end

-- Rotation band pool (archive 2065-2119): header bg + lane tint + label + icons.
local function get_rotation_band(parent)
    ui.timeline_rotation_band_pool = ui.timeline_rotation_band_pool or {}
    ui.timeline_rotation_band_pool_used = (ui.timeline_rotation_band_pool_used or 0) + 1
    local idx = ui.timeline_rotation_band_pool_used
    local pool = ui.timeline_rotation_band_pool

    if pool[idx] then
        pool[idx].bg:Show()
        pool[idx].lane_tint:Show()
        pool[idx].label:Show()
        return pool[idx]
    end

    local bg = parent:CreateTexture(nil, "ARTWORK", nil, -1)
    local lane_tint = parent:CreateTexture(nil, "BORDER")
    local label = parent:CreateFontString(nil, "OVERLAY")
    st.utils.apply_font(label, STANDARD_TEXT_FONT, 9, "OUTLINE")

    local icons = {}
    for i = 1, ROTATION_BAND_MAX_ICONS do
        icons[i] = create_rotation_icon(parent, ROTATION_BAND_ICON_SIZE)
    end

    local entry = { bg = bg, lane_tint = lane_tint, label = label, icons = icons }
    pool[idx] = entry
    return entry
end

local function reset_rotation_band_pool()
    if not ui.timeline_rotation_band_pool then
        return
    end
    for i = 1, (ui.timeline_rotation_band_pool_used or 0) do
        local entry = ui.timeline_rotation_band_pool[i]
        if entry then
            entry.bg:Hide()
            entry.lane_tint:Hide()
            entry.label:Hide()
            for j = 1, ROTATION_BAND_MAX_ICONS do
                if entry.icons[j] then
                    entry.icons[j]:Hide()
                end
            end
        end
    end
    ui.timeline_rotation_band_pool_used = 0
end

function ui.reset_timeline_pools()
    reset_timeline_icon_pool()
    reset_timeline_divider_pool()
    reset_timeline_ruler_pool()
    reset_rotation_band_pool()
end

-- Renders the rotation bands over the ruler + lane area (archive 2137-2218).
local function render_timeline_bands(scroll_child, total_width)
    reset_rotation_band_pool()
    local pr = st.practice
    local band_count = ui.timeline_band_count or 0
    if band_count == 0 or not pr then
        return
    end
    local content_time = math.max(pr.timeline_max_time(
        ui.timeline_events, ui.timeline_event_count) + 2, 10)
    local num_lanes = #(pr.TIMELINE_LANES or {})
    local lane_area_height = num_lanes * TIMELINE_LANE_HEIGHT
    local na = st.nextaction

    for i = 1, band_count do
        local band_data = ui.timeline_bands[i]
        if band_data then
            local start_x = band_data.start_time * TIMELINE_PPS
            local end_time = (i < band_count and ui.timeline_bands[i + 1])
                and ui.timeline_bands[i + 1].start_time or content_time
            local end_x = end_time * TIMELINE_PPS
            local width = math.max(end_x - start_x, 1)

            local entry = get_rotation_band(scroll_child)
            local color = ROTATION_BAND_COLORS[band_data.rotation] or ROTATION_BAND_FALLBACK

            entry.bg:ClearAllPoints()
            entry.bg:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", start_x, 0)
            entry.bg:SetSize(width, TIMELINE_RULER_HEIGHT)
            entry.bg:SetColorTexture(color[1], color[2], color[3], 0.55)

            entry.lane_tint:ClearAllPoints()
            entry.lane_tint:SetPoint("TOPLEFT", scroll_child, "TOPLEFT",
                start_x, -TIMELINE_RULER_HEIGHT)
            entry.lane_tint:SetSize(width, lane_area_height)
            entry.lane_tint:SetColorTexture(color[1], color[2], color[3], 0.08)

            local display_name = (na and na.display_names and na.display_names[band_data.rotation])
                or band_data.rotation
            entry.label:ClearAllPoints()
            entry.label:SetPoint("TOP", entry.bg, "TOP", 0, -1)
            entry.label:SetText(display_name)
            entry.label:SetTextColor(0.9, 0.9, 0.9, 1)

            local sequence = (na and na.sequences and na.sequences[band_data.rotation]) or {}
            local num_icons = #sequence
            local icons_total_width = (ROTATION_BAND_ICON_SIZE * num_icons)
                + (ROTATION_BAND_ICON_SPACING * math.max(num_icons - 1, 0))
            local band_center_x = start_x + width / 2
            local icons_start_x = band_center_x - icons_total_width / 2
            for j = 1, ROTATION_BAND_MAX_ICONS do
                local icon_frame = entry.icons[j]
                if j <= num_icons then
                    icon_frame:ClearAllPoints()
                    local ix = icons_start_x
                        + (j - 1) * (ROTATION_BAND_ICON_SIZE + ROTATION_BAND_ICON_SPACING)
                    icon_frame:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", ix, -14)
                    set_step_texture(icon_frame, sequence[j])
                    icon_frame:Show()
                else
                    icon_frame:Hide()
                end
            end
        end
    end
end

-- Renders the ruler ticks (archive 2221-2243).
local function render_timeline_ruler(scroll_child, total_width)
    reset_timeline_ruler_pool()
    local pr = st.practice
    if not pr then
        return
    end
    local max_time = pr.timeline_max_time(ui.timeline_events, ui.timeline_event_count)
    for sec = 0, math.ceil(max_time) do
        local x = sec * TIMELINE_PPS
        if x <= total_width then
            local entry = get_ruler_tick(scroll_child)
            entry.tick:SetSize(1, 8)
            entry.tick:ClearAllPoints()
            entry.tick:SetPoint("BOTTOMLEFT", scroll_child, "TOPLEFT", x, -TIMELINE_RULER_HEIGHT)
            local mins = math.floor(sec / 60)
            local secs = sec % 60
            entry.label:ClearAllPoints()
            entry.label:SetPoint("BOTTOM", entry.tick, "TOP", 0, 0)
            entry.label:SetText(string.format("%d:%02d", mins, secs))
            entry.label:Show()
        end
    end
end

-- Full re-render from the event data (archive render_timeline 2246-2366, trimmed).
function ui.render_timeline()
    ui.timeline_needs_render = false
    local frame = ui.timeline_frame
    if not frame or not frame.scroll_child then
        return
    end
    local pr = st.practice
    if not pr then
        return
    end
    local content_time = math.max(pr.timeline_max_time(
        ui.timeline_events, ui.timeline_event_count) + 2, 10)
    local total_width = content_time * TIMELINE_PPS
    local scroll_child = frame.scroll_child
    scroll_child:SetWidth(total_width)

    ui.reset_timeline_pools()
    render_timeline_bands(scroll_child, total_width)
    render_timeline_ruler(scroll_child, total_width)

    if frame.lane_bgs then
        for _, bg in ipairs(frame.lane_bgs) do
            bg:SetWidth(total_width)
        end
    end

    local analysis = pr.analyze(ui.timeline_events, ui.timeline_event_count,
        ui.timeline_bands, ui.timeline_band_count)
    local num_lanes = #(pr.TIMELINE_LANES or {})
    for i = 1, (ui.timeline_event_count or 0) do
        local event = ui.timeline_events[i]
        local lane_idx = event and pr.TIMELINE_LANE_INDEX[event.lane]
        if lane_idx then
            local x = event.time * TIMELINE_PPS
            local y = -(TIMELINE_RULER_HEIGHT + (lane_idx - 1) * TIMELINE_LANE_HEIGHT
                + (TIMELINE_LANE_HEIGHT - TIMELINE_ICON_SIZE) / 2)
            local icon = get_timeline_icon(scroll_child)
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", x - TIMELINE_ICON_SIZE / 2, y)

            -- Melee with an active (non-twist) seal: split sword/seal icon.
            if event.lane == "melee" and event.seal_active and event.result ~= "twist" then
                icon.texture:Hide()
                icon.split_left:SetTexture(event.texture)
                local seal_spell = (event.seal_active == "blood")
                    and BLOOD_SPELL_ID or COMMAND_SPELL_ID
                local seal_tex = spell_texture(seal_spell)
                if seal_tex then
                    icon.split_right:SetTexture(seal_tex)
                end
                icon.split_left:Show()
                icon.split_right:Show()
            else
                if event.texture then
                    icon.texture:SetTexture(event.texture)
                end
                icon.texture:Show()
                icon.split_left:Hide()
                icon.split_right:Hide()
            end

            -- Grading mark for melee/judge swings (archive 2329-2344).
            if event.lane == "melee" or event.lane == "judge" then
                local verdict = analysis[i]
                icon.analysis_data = verdict
                if verdict and not verdict.skipped and not verdict.correct then
                    icon.error_border:Show()
                    icon.result_label:SetText("|cFFFF3333X|r")
                    icon.result_label:Show()
                else
                    icon.error_border:Hide()
                    icon.result_label:SetText("")
                    icon.result_label:Hide()
                end
            else
                icon.error_border:Hide()
                icon.analysis_data = nil
            end

            if event.lane == "melee" then
                local div = get_timeline_divider(scroll_child)
                div:SetSize(1, num_lanes * TIMELINE_LANE_HEIGHT)
                div:ClearAllPoints()
                div:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", x, -TIMELINE_RULER_HEIGHT)
            end
        end
    end

    if frame.scrollbar and frame.scroll_frame then
        local visible_width = frame.scroll_frame.GetWidth
            and frame.scroll_frame:GetWidth() or TIMELINE_WIDTH
        local max_scroll = math.max(total_width - visible_width, 0)
        frame.scrollbar:SetMinMaxValues(0, max_scroll)
        if ui.timeline_auto_scroll then
            frame.scrollbar:SetValue(max_scroll)
            if frame.scroll_frame.SetHorizontalScroll then
                frame.scroll_frame:SetHorizontalScroll(max_scroll)
            end
        end
    end
end

-- Builds the timeline frame hierarchy (archive create_timeline 2369-2510, trimmed).
function ui.build_timeline(self)
    if not ui.panel then
        return
    end
    local pr = st.practice
    if not pr then
        return
    end
    local lanes = pr.TIMELINE_LANES or {}
    local num_lanes = #lanes
    local content_height = TIMELINE_RULER_HEIGHT + num_lanes * TIMELINE_LANE_HEIGHT
    local frame_height = content_height + 30

    local frame = CreateFrame("Frame", addon_name .. "PracticeTimeline", UIParent,
        "BackdropTemplate")
    ui.timeline_frame = frame
    frame:SetSize(TIMELINE_WIDTH + TIMELINE_LABEL_WIDTH + 16, frame_height)
    ui.timeline_x = ui.timeline_x or TIMELINE_DEFAULT_X
    ui.timeline_y = ui.timeline_y or TIMELINE_DEFAULT_Y
    frame:SetPoint("CENTER", UIParent, "CENTER", ui.timeline_x, ui.timeline_y)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    frame:SetScript("OnDragStart", function(f)
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        f:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        ui.save_timeline_position(self)
    end)

    local close_btn = CreateFrame("Button", nil, frame)
    close_btn:SetSize(16, 16)
    close_btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close_btn.label = close_btn:CreateFontString(nil, "OVERLAY")
    close_btn.label:SetPoint("CENTER", 0, 0)
    close_btn.label:SetFontObject(GameFontHighlightSmall)
    close_btn.label:SetText("X")
    close_btn:SetScript("OnClick", function()
        ui.toggle_timeline(ST)
    end)

    local label_area = CreateFrame("Frame", nil, frame)
    label_area:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -(4 + TIMELINE_RULER_HEIGHT))
    label_area:SetSize(TIMELINE_LABEL_WIDTH, num_lanes * TIMELINE_LANE_HEIGHT)
    for i, lane in ipairs(lanes) do
        local y = -((i - 1) * TIMELINE_LANE_HEIGHT)
        local lane_icon = label_area:CreateTexture(nil, "ARTWORK")
        lane_icon:SetSize(16, 16)
        lane_icon:SetPoint("LEFT", label_area, "TOPLEFT", 2, y - TIMELINE_LANE_HEIGHT / 2)
        lane_icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local spell_id = LANE_SPELL_IDS[lane.key]
        if spell_id then
            local tex = spell_texture(spell_id)
            if tex then
                lane_icon:SetTexture(tex)
            end
        elseif lane.key == "melee" then
            lane_icon:SetTexture(pr.MELEE_TEXTURE)
        end
        local lane_label = label_area:CreateFontString(nil, "OVERLAY")
        st.utils.apply_font(lane_label, STANDARD_TEXT_FONT, 9, "OUTLINE")
        lane_label:SetPoint("LEFT", lane_icon, "RIGHT", 3, 0)
        lane_label:SetTextColor(0.8, 0.8, 0.8, 1)
        lane_label:SetText(lane.name)
    end

    local scroll_frame = CreateFrame("ScrollFrame", addon_name .. "PracticeTimelineSF", frame)
    scroll_frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 6 + TIMELINE_LABEL_WIDTH, -4)
    scroll_frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 18)
    frame.scroll_frame = scroll_frame

    local scroll_child = CreateFrame("Frame", nil, scroll_frame)
    scroll_child:SetHeight(content_height)
    scroll_child:SetWidth(TIMELINE_WIDTH)
    if scroll_frame.SetScrollChild then
        scroll_frame:SetScrollChild(scroll_child)
    end
    frame.scroll_child = scroll_child

    frame.lane_bgs = {}
    for i = 1, num_lanes do
        local bg = scroll_child:CreateTexture(nil, "BACKGROUND")
        local shade = (i % 2 == 0) and 0.08 or 0.04
        bg:SetColorTexture(shade, shade, shade, 1)
        bg:SetHeight(TIMELINE_LANE_HEIGHT)
        bg:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", 0,
            -(TIMELINE_RULER_HEIGHT + (i - 1) * TIMELINE_LANE_HEIGHT))
        bg:SetWidth(TIMELINE_WIDTH)
        frame.lane_bgs[i] = bg
    end

    local scrollbar = CreateFrame("Slider", nil, frame, "BackdropTemplate")
    scrollbar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6 + TIMELINE_LABEL_WIDTH, 4)
    scrollbar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 4)
    scrollbar:SetHeight(12)
    if scrollbar.SetMinMaxValues then
        scrollbar:SetMinMaxValues(0, 1)
    end
    if scrollbar.SetValue then
        scrollbar:SetValue(0)
    end
    if scrollbar.SetValueStep then
        scrollbar:SetValueStep(1)
    end
    if scrollbar.SetObeyStepOnDrag then
        scrollbar:SetObeyStepOnDrag(true)
    end
    if scrollbar.SetOrientation then
        scrollbar:SetOrientation("HORIZONTAL")
    end
    scrollbar:SetScript("OnValueChanged", function(_, value)
        if scroll_frame.SetHorizontalScroll then
            scroll_frame:SetHorizontalScroll(value)
        end
    end)
    frame.scrollbar = scrollbar

    if scroll_frame.EnableMouseWheel then
        scroll_frame:EnableMouseWheel(true)
    end
    scroll_frame:SetScript("OnMouseWheel", function(_, delta)
        local min_val, max_val = 0, 1
        if scrollbar.GetMinMaxValues then
            min_val, max_val = scrollbar:GetMinMaxValues()
        end
        local cur = (scrollbar.GetValue and scrollbar:GetValue()) or 0
        local step = TIMELINE_PPS * 2
        local new_val = math.max(min_val, math.min(max_val, cur - delta * step))
        if scrollbar.SetValue then
            scrollbar:SetValue(new_val)
        end
        if delta > 0 then
            ui.timeline_auto_scroll = false
        elseif new_val >= max_val then
            ui.timeline_auto_scroll = true
        end
    end)

    frame:Hide()
end

-- Stores the dragged timeline position as a center offset (session-local, like the
-- rotation display).
function ui.save_timeline_position(self)
    local frame = ui.timeline_frame
    if not frame or not UIParent then
        return
    end
    if not (frame.GetCenter and UIParent.GetCenter) then
        return
    end
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then
        return
    end
    ui.timeline_x = math.floor(cx - ux + 0.5)
    ui.timeline_y = math.floor(cy - uy + 0.5)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", ui.timeline_x, ui.timeline_y)
end

-- Toggles the timeline frame (archive toggle_timeline 2513-2537).
function ui.toggle_timeline()
    local frame = ui.timeline_frame
    if not frame then
        return
    end
    if ui.timeline_visible then
        frame:Hide()
        ui.timeline_visible = false
    else
        frame:Show()
        ui.timeline_visible = true
        ui.timeline_needs_render = true
    end
    ui.update_timeline_button()
end

-- Refreshes just the timeline toggle button (fight start reuses it).
function ui.update_timeline_button()
    local panel = ui.panel
    if not panel or not panel.timeline_btn then
        return
    end
    if ui.timeline_visible then
        panel.timeline_btn:SetBackdropColor(0.1, 0.3, 0.1, 0.9)
        panel.timeline_btn.label:SetText("|cFF00FF00Timeline|r")
    else
        panel.timeline_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        panel.timeline_btn.label:SetText("Timeline")
    end
end

--=========================================================================================
-- Proc icons: Bloodlust + DST (archive 2715-2802)
--=========================================================================================

-- One proc icon: border, texture, cooldown swipe (set-once latch), countdown text.
local function create_proc_icon(key, texture)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(48, 48)
    local x = (key == "dst") and -30 or 30
    frame:SetPoint("CENTER", UIParent, "CENTER", x, 150)
    frame:SetFrameStrata("HIGH")

    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetPoint("TOPLEFT", -1, 1)
    frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.border:SetColorTexture(0, 0, 0, 0.8)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexture(texture)

    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints()
    frame.cooldown:SetDrawEdge(false)
    if frame.cooldown.SetHideCountdownNumbers then
        frame.cooldown:SetHideCountdownNumbers(true)
    end

    frame.countdown = frame:CreateFontString(nil, "OVERLAY")
    frame.countdown:SetPoint("BOTTOM", frame, "BOTTOM", 0, -14)
    st.utils.apply_font(frame.countdown, STANDARD_TEXT_FONT, 14, "OUTLINE")
    frame.countdown:SetTextColor(1, 1, 1, 1)
    frame.countdown:SetText("")

    frame.proc_swipe = {}
    frame:Hide()
    return frame
end

-- Builds both proc icons, dimmed until their buffs run (archive start 1018-1033).
function ui.build_proc_icons(self)
    if not ui.panel then
        return
    end
    local bl_tex = spell_texture(BLOODLUST_SPELL_ID) or BLOODLUST_FALLBACK
    local dst_tex = DST_FALLBACK
    if GetItemIcon then
        dst_tex = GetItemIcon(DST_ITEM_ID) or DST_FALLBACK
    end
    ui.proc_icons = {
        bl = create_proc_icon("bl", bl_tex),
        dst = create_proc_icon("dst", dst_tex),
    }
end

-- Drives the proc icons from the sim buffs (archive sim_update 3346-3384 halves):
-- full alpha + swipe + countdown while the buff runs, dimmed/desaturated else.
function ui.update_proc_icons(self)
    local icons = ui.proc_icons
    if not icons then
        return
    end
    local sim = ui.sim
    local now = api.get_time()
    local function update_one(frame, active, expires, full_duration)
        if not frame then
            return
        end
        local remaining = (active and expires > now) and (expires - now) or 0
        set_swipe(frame.proc_swipe, frame.cooldown, remaining, full_duration)
        if remaining > 0 then
            frame:SetAlpha(1)
            if frame.icon.SetDesaturated then
                frame.icon:SetDesaturated(false)
            end
            frame.countdown:SetText(string.format("%d", math.ceil(remaining)))
        else
            frame:SetAlpha(0.4)
            if frame.icon.SetDesaturated then
                frame.icon:SetDesaturated(true)
            end
            frame.countdown:SetText("")
        end
    end
    if sim then
        update_one(icons.bl, sim.has_bloodlust, sim.bl_buff_expires, 40)
        update_one(icons.dst, sim.has_dst, sim.dst_buff_expires, 10)
    else
        update_one(icons.bl, false, 0, 40)
        update_one(icons.dst, false, 0, 10)
    end
end

--=========================================================================================
-- Bar overlays (action-bar mirrors): mechanism ships, discovery is deferred
--=========================================================================================
-- The overlay object model (archive create_bar_overlay 3799-3901, minus the hotkey
-- mirror) is fully implemented below and driven every tick by update_overlays(),
-- with press flashes fired from cast_key(). What is NOT here: finding the parent
-- action-bar button automatically. That needs the archived discover_action_buttons
-- (BT4/Dominos/ElvUI/Blizzard _G scan) plus the manual linking click-catchers and
-- persisted mappings (new options), all deferred. Plug-in: call
--   st.practice_ui.attach_overlay(ST, ability_key, parent_frame)
-- once the parent is known (e.g. from a future linking pass); detach_overlay and
-- detach_all_overlays undo it. Until then overlays stay empty and cost nothing.
function ui.attach_overlay(self, ability_key, parent_frame)
    self = self or ST
    local pr = st.practice
    local ab = pr and pr.ABILITIES[ability_key]
    if not ab or not parent_frame then
        return
    end
    ui.detach_overlay(self, ability_key)
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local container = CreateFrame("Frame", nil, parent_frame)
    container:SetAllPoints()
    if parent_frame.GetFrameStrata and container.SetFrameStrata then
        container:SetFrameStrata(parent_frame:GetFrameStrata())
    end
    if parent_frame.GetFrameLevel and container.SetFrameLevel then
        container:SetFrameLevel(parent_frame:GetFrameLevel() + 5)
    end

    local icon_tex = container:CreateTexture(nil, "ARTWORK")
    icon_tex:SetAllPoints()
    local tex = ability_texture(ability_key)
    if tex then
        icon_tex:SetTexture(tex)
        icon_tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local cd = CreateFrame("Cooldown", nil, container, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    if cd.SetHideCountdownNumbers then
        cd:SetHideCountdownNumbers(true)
    end

    local dim = container:CreateTexture(nil, "OVERLAY")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.5)
    dim:Hide()

    local gcd_cd = CreateFrame("Cooldown", nil, container, "CooldownFrameTemplate")
    gcd_cd:SetAllPoints()
    gcd_cd:SetDrawEdge(false)
    if gcd_cd.SetHideCountdownNumbers then
        gcd_cd:SetHideCountdownNumbers(true)
    end

    local flash = container:CreateTexture(nil, "OVERLAY")
    flash:SetAllPoints()
    flash:SetColorTexture(1, 1, 1, 0)
    flash:Hide()

    local cd_text_frame = CreateFrame("Frame", nil, container)
    cd_text_frame:SetAllPoints()
    local cd_text = cd_text_frame:CreateFontString(nil, "OVERLAY")
    cd_text:SetPoint("CENTER", container, "CENTER", 0, 0)
    st.utils.apply_font(cd_text, STANDARD_TEXT_FONT, 14, "OUTLINE")
    cd_text:SetTextColor(1, 1, 1, 1)
    cd_text:Hide()

    ui.overlays = ui.overlays or {}
    ui.overlays[ability_key] = {
        container = container,
        cooldown = cd,
        cooldown_set = false,
        cooldown_state = {},
        gcd_dim = dim,
        gcd_cooldown = gcd_cd,
        gcd_state = {},
        flash = flash,
        flash_timer = 0,
        cd_text = cd_text,
    }
end

function ui.detach_overlay(self, ability_key)
    if not ui.overlays then
        return
    end
    local overlay = ui.overlays[ability_key]
    if not overlay then
        return
    end
    if overlay.container then
        overlay.container:Hide()
    end
    ui.overlays[ability_key] = nil
end

function ui.detach_all_overlays(self)
    if not ui.overlays then
        return
    end
    local keys = {}
    for key in pairs(ui.overlays) do
        keys[#keys + 1] = key
    end
    for _, key in ipairs(keys) do
        ui.detach_overlay(self, key)
    end
    ui.overlays = {}
end

-- Press flash (archive flash_bar_button 3973-3980).
function ui.flash_overlay(self, ability_key)
    if not ui.overlays then
        return
    end
    local overlay = ui.overlays[ability_key]
    if not overlay or not overlay.flash then
        return
    end
    if overlay.flash.SetVertexColor then
        overlay.flash:SetVertexColor(1, 1, 1, 0.6)
    end
    overlay.flash:Show()
    overlay.flash_timer = 0.15
end

-- Per-tick overlay drive (archive update_icon_states 3594-3647, set-once variant):
-- cooldown swipes latch like the panel icons, plus countdown text + flash fade.
function ui.update_overlays(self, now)
    if not ui.overlays then
        return
    end
    local sim = ui.sim
    if not sim then
        return
    end
    now = now or api.get_time()
    local pr = st.practice
    local gcd_remaining = 0
    if sim.gcd_active and sim.gcd_expires > now then
        gcd_remaining = sim.gcd_expires - now
    end
    for key, overlay in pairs(ui.overlays) do
        local ab = pr.ABILITIES[key]
        if ab and (ab.type == "ability" or ab.type == "buff" or ab.type == "haste_trinket") then
            local expires = sim[key .. "_cooldown_expires"] or 0
            local remaining = (expires > now) and (expires - now) or 0
            if not overlay.cooldown_set and remaining > 0 then
                overlay.cooldown:SetCooldown(expires - ab.cooldown, ab.cooldown)
                overlay.cooldown_set = true
            elseif overlay.cooldown_set and remaining <= 0 then
                overlay.cooldown:SetCooldown(0, 0)
                overlay.cooldown_set = false
            end
            if overlay.cd_text then
                if remaining > 0 then
                    overlay.cd_text:SetText(string.format("%d", math.ceil(remaining)))
                    overlay.cd_text:Show()
                else
                    overlay.cd_text:Hide()
                end
            end
        elseif overlay.cooldown then
            overlay.cooldown:SetCooldown(0, 0)
            overlay.cooldown_set = false
            if overlay.cd_text then
                overlay.cd_text:Hide()
            end
        end
        if overlay.gcd_dim then
            local gated = not (key == "judge" or ab.type == "buff"
                or ab.type == "haste_trinket" or ab.type == "stopattack")
            if gated then
                set_swipe(overlay.gcd_state, overlay.gcd_cooldown, gcd_remaining,
                    sim.effective_gcd)
                if gcd_remaining > 0 then
                    overlay.gcd_dim:Show()
                else
                    overlay.gcd_dim:Hide()
                end
            end
        end
        if overlay.flash_timer > 0 then
            overlay.flash_timer = overlay.flash_timer - 0.016
            if overlay.flash_timer <= 0 then
                overlay.flash_timer = 0
                overlay.flash:Hide()
                if overlay.flash.SetVertexColor then
                    overlay.flash:SetVertexColor(1, 1, 1, 0)
                end
            elseif overlay.flash.SetVertexColor then
                overlay.flash:SetVertexColor(1, 1, 1, 0.6 * (overlay.flash_timer / 0.15))
            end
        end
    end
end
--=========================================================================================
-- Session lifecycle
--=========================================================================================
function ui.is_active()
    -- True while a practice session runs (the paladin module's gates read this).
    return ui.active == true
end

function ui.toggle(self)
    self = self or ST
    if ui.active then
        ui.stop(self)
    else
        ui.start(self)
    end
end

--=========================================================================================
-- Rotation scenario + generic drill sessions (the shared engine)
--=========================================================================================
-- Two new session modes ride the same panel, the same score accumulator and the
-- same progression hook as the shipped per-class sessions:
--
--   SCENARIO  the class's rotation, run end to end. The engine asks the class what
--             it wants cast (ST.<CLASS>.practice_scenario_step), the player casts,
--             and the engine compares and grades the decision: correct / out of
--             order / miss / unknown. Every graded decision feeds
--             ui.record_graded_attempt, so XP and mastery work unchanged.
--
--   DRILLS    the class's focused drill list (ST.<CLASS>.practice_drills). One
--             panel button per drill; pressing it grades that drill.
--
-- The mode comes from the Practice page's select (nil = the shipped class session,
-- so a fresh profile sees exactly the panel it saw before). A class that provides
-- neither a scenario nor drills fails LOUDLY in these modes - never a silent
-- paladin sim on the wrong class.
--
-- The pure half lives in practice.lua (st.practice.harness): the contract lookups,
-- the comparison and the grade bands are offline-testable there. This half is the
-- frame-and-clock wiring only.
--=========================================================================================

-- The practice mode the Practice page selects. An unknown or missing value means
-- the shipped class session (the default - no default-visible change).
local function practice_mode(self)
    -- A session-local override: the twist drill press (the paladin's own drill in
    -- the drill list) hands the panel over to the class session. The override is
    -- consumed by the start that reads it, so the Practice page's select is never
    -- changed.
    local override = ui.practice_mode_override
    ui.practice_mode_override = nil
    if override == PRACTICE_MODE_CLASS or override == PRACTICE_MODE_SCENARIO
        or override == PRACTICE_MODE_DRILLS then
        return override
    end
    local db = nil
    if self and type(self.get_class_table) == "function" then
        local ok, class_db = pcall(self.get_class_table, self)
        if ok then
            db = class_db
        end
    end
    local mode = type(db) == "table" and db.practice_mode or nil
    if mode == PRACTICE_MODE_SCENARIO or mode == PRACTICE_MODE_DRILLS then
        return mode
    end
    return PRACTICE_MODE_CLASS
end

-- The resource fields the default ctx lifts from the class's gathered guide inputs.
--
-- Verified field by field against the six classes' gather_guide_inputs - every class
-- names its own pool, there is no shared name:
--   druid    rage (bear), energy (cat), combo_points (cat)
--   hunter   mana (the hunter publishes its own ctx; the fraction is its pool)
--   paladin  mana_pct
--   rogue    energy_now, max_energy, cp
--   shaman   mana_fraction
--   warrior  rage
-- "focus" is deliberately absent: no gather produces it (the focus pool lives in the
-- engine's own sim state, never in the gathered inputs). A name the class did not
-- produce is skipped, never guessed.
--
-- The list is the pool contract; the pass below it also lifts the class's own state
-- beside the pool (the rogue's own ctx copies every gathered value), so a class that
-- adds a field needs no change here, a field nobody listed still reaches the class's
-- grader, and no class can crash this path.
local SCENARIO_RESOURCE_KEYS = {
    "mana",           -- hunter (its own ctx publishes the mana fraction)
    "mana_pct",       -- paladin
    "mana_fraction",  -- shaman
    "rage",           -- druid (bear) and warrior
    "energy",         -- druid (cat)
    "energy_now",     -- rogue
    "max_energy",     -- rogue
    "combo_points",   -- druid (cat)
    "cp",             -- rogue
}

-- The live pull clock in the context (BS-8 item 2): the prepull rule and the
-- prepull drills read the SAME moment the live guide reads.
--   ctx.pull_at           the absolute pull timestamp (api.get_time() domain)
--   ctx.pull_in_seconds   the countdown to the pull, in seconds
-- Both stay nil when the pull is unknown (the clock is never a guess), and a
-- context that already carries its own pull clock (a drill's synthetic one)
-- wins - the live clock never overwrites a caller that knows better.
local function apply_pull_clock(ctx, now)
    if type(ctx) ~= "table" then
        return ctx
    end
    if ctx.pull_at ~= nil or ctx.pull_in_seconds ~= nil then
        return ctx
    end
    if type(ST) ~= "table" then
        return ctx
    end
    local pull_at = ST.pull_at
    if type(pull_at) == "number" and pull_at == pull_at then
        ctx.pull_at = pull_at
    end
    if type(ST.pull_in_seconds) == "function" then
        local ok, value = pcall(ST.pull_in_seconds, ST, now)
        if ok and type(value) == "number" and value == value then
            ctx.pull_in_seconds = value
        end
    end
    return ctx
end

-- The context the class's decision and its graders read:
--   now         the injected clock (the caller's domain - never read here)
--   last_action the action the player cast last (nil at the start of a run)
--   resources   the resource values the class's gathered inputs expose, or nil
--   cooldowns   the remaining cooldowns the class's gathered inputs expose, or nil
-- A class that publishes its own context builder (ST.<CLASS>.practice_context)
-- owns the whole ctx; the engine's builder below is the fallback (it fills what
-- it can see from the class's gathered guide inputs).
local function scenario_context(now, last_action)
    local module = practice_class_module()
    if type(module) == "table" and type(module.practice_context) == "function" then
        local ok, ctx = pcall(function() return module.practice_context(ST, now, last_action) end)
        if ok and type(ctx) == "table" then
            -- The clock and the last action are the engine's to inject: the
            -- contract's four fields always hold, whatever the class fills in.
            ctx.now = now
            ctx.last_action = last_action
            if type(ctx.resources) ~= "table" then
                ctx.resources = nil
            end
            if type(ctx.cooldowns) ~= "table" then
                ctx.cooldowns = nil
            end
            return apply_pull_clock(ctx, now)
        end
    end
    local ctx = {
        now = now,
        last_action = last_action,
        resources = nil,
        cooldowns = nil,
    }
    if type(module) ~= "table" or type(module.gather_guide_inputs) ~= "function" then
        return apply_pull_clock(ctx, now)
    end
    ui.scenario_inputs = ui.scenario_inputs or {}
    local gathered = nil
    -- pcall-guarded: a half-loaded class module never throws out of the step.
    local ok, result = pcall(module.gather_guide_inputs, ST, ui.scenario_inputs)
    if ok and type(result) == "table" then
        gathered = result
    end
    if not gathered then
        return apply_pull_clock(ctx, now)
    end
    local resources = {}
    -- The pool readings (the contract above): a name the class did not produce is
    -- skipped, never guessed.
    for i = 1, #SCENARIO_RESOURCE_KEYS do
        local name = SCENARIO_RESOURCE_KEYS[i]
        local value = gathered[name]
        if type(value) == "number" then
            resources[name] = value
        end
    end
    -- The class's own state beside the pool: every other value its gather produced
    -- (numbers, flags and tokens), the same rule the rogue's own ctx uses. This is
    -- the safety net - a field nobody listed still reaches the class's grader, so no
    -- class degrades to "unknown" over a missing entry, and no class can crash this
    -- path.
    for key, value in pairs(gathered) do
        if type(key) == "string" and resources[key] == nil then
            local kind = type(value)
            if kind == "number" or kind == "boolean" or kind == "string" then
                resources[key] = value
            end
        end
    end
    if next(resources) ~= nil then
        ctx.resources = resources
    end
    local cooldowns = {}
    for key, value in pairs(gathered) do
        if type(key) == "string" and type(value) == "number" then
            local base = key:match("^(.-)_remaining_cd$") or key:match("^(.-)_remaining$")
            if base and base ~= "" then
                cooldowns[base] = value
            end
        end
    end
    if next(cooldowns) ~= nil then
        ctx.cooldowns = cooldowns
    end
    return apply_pull_clock(ctx, now)
end

-- The class's action vocabulary for the scenario panel: the guide slot keys (the
-- same key space the guide engine emits) plus every key the class has asked for.
-- Ordered, so the panel's buttons never shuffle between frames.
local function scenario_guide_slots()
    local module = practice_class_module()
    local guide = type(module) == "table" and module.guide or nil
    local slots = type(guide) == "table" and guide.slots or nil
    if type(slots) ~= "table" then
        return nil
    end
    return slots
end

-- Remember an action key the class asked for (the panel's button set grows with it).
local function scenario_note_action(key)
    if type(key) ~= "string" or key == "" then
        return
    end
    ui.scenario_action_set = ui.scenario_action_set or {}
    if ui.scenario_action_set[key] then
        return
    end
    ui.scenario_action_set[key] = true
    ui.scenario_actions = ui.scenario_actions or {}
    ui.scenario_actions[#ui.scenario_actions + 1] = key
end

-- The ordered action vocabulary: the class's published rotation first (its own
-- priority order and labels), then the guide slot keys, then the keys the class
-- asked for that neither names.
--
-- ONE SPELLING PER SPELL: every key is canonicalised through the class's own
-- alias table and the CANONICAL key is the button's key. The paladin has two
-- key spaces - the rotation and the guide engine say "cons" / "exo" / "hs" /
-- "am", the guide SLOTS say "consecration" / "exorcism" / "holy_shock" /
-- "aura_mastery" - and the row used to push BOTH, so the player got TWO
-- Consecration buttons for one spell (a bare text "cons" and an icon
-- "consecration"). The grader compares canonical keys, so a second spelling was
-- a second button that could only ever be a mis-pick.
local function scenario_action_order()
    local out = {}
    local seen = {}
    local labels = {}
    local function push(key, label)
        if type(key) ~= "string" or key == "" then
            return
        end
        local canonical = ui.canonical_key(key)
        if type(canonical) ~= "string" or canonical == "" then
            canonical = key
        end
        if seen[canonical] then
            return
        end
        seen[canonical] = true
        labels[canonical] = (type(label) == "string" and label ~= "") and label or canonical
        out[#out + 1] = canonical
    end
    local rotation = practice_rotation_entries()
    if rotation then
        for i = 1, #rotation do
            push(rotation[i].action, rotation[i].label)
        end
    end
    local slots = scenario_guide_slots()
    if slots then
        for i = 1, #slots do
            local slot = slots[i]
            if type(slot) == "table" then
                -- The slot's own key is the label when the rotation names no row
                -- for it: the button reads as it always did, only its KEY is
                -- canonical now.
                push(slot.key, slot.key)
            end
        end
    end
    for i = 1, #(ui.scenario_actions or {}) do
        push(ui.scenario_actions[i])
    end
    return out, labels
end

-- The label the panel's button carries for an action key (the class's own label
-- when it publishes one, the key otherwise).
local function scenario_action_label(key, labels)
    if labels and labels[key] then
        return labels[key]
    end
    return key
end

-- The spell id the class's guide publishes for an action key (nil when unknown).
--
-- The lookup goes through the class's alias table: the CANONICAL key ("cons")
-- finds the guide slot that spells it ("consecration"), so the ONE button the
-- panel offers for a spell carries that spell's icon - and the button that used
-- to carry it (the alias) is no longer a second button for the same spell.
local function scenario_action_spell_id(key)
    local slots = scenario_guide_slots()
    if not slots then
        return nil
    end
    local canonical = ui.canonical_key(key)
    for i = 1, #slots do
        local slot = slots[i]
        if type(slot) == "table" and type(slot.key) == "string" then
            if slot.key == key or ui.canonical_key(slot.key) == canonical then
                return slot.spell_id
            end
        end
    end
    return nil
end

--=========================================================================================
-- The practice row (the companion strip under the panel's content)
--=========================================================================================
-- Created lazily on the first scenario / drill session, so the shipped panel (and
-- its size) is untouched until a session asks for it. It carries the buttons, the
-- prompt line and the status line.
local function build_practice_row(self)
    local panel = ui.panel
    if not panel then
        return nil
    end
    if ui.practice_row then
        return ui.practice_row
    end
    local row = CreateFrame("Frame", nil, panel)
    row:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 6)
    row:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
    row:SetHeight(PRACTICE_ROW_HEIGHT)
    row:Hide()
    ui.practice_row = row

    ui.practice_row_prompt = row:CreateFontString(nil, "OVERLAY")
    ui.practice_row_prompt:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    ui.practice_row_prompt:SetFontObject(GameFontHighlightSmall)
    ui.practice_row_prompt:SetText("")

    ui.practice_row_buttons = CreateFrame("Frame", nil, row)
    ui.practice_row_buttons:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    ui.practice_row_buttons:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 12)

    ui.practice_row_status = row:CreateFontString(nil, "OVERLAY")
    ui.practice_row_status:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    ui.practice_row_status:SetFontObject(GameFontHighlightSmall)
    ui.practice_row_status:SetText("")
    return row
end

-- Show or hide the practice row. The panel grows by the row's height while the row
-- is up and shrinks back when it goes away (the shipped panel's size is restored).
local function practice_row_show(self, visible)
    local row = ui.practice_row
    if not row then
        return
    end
    if visible then
        row:Show()
        if ui.panel and type(ui.panel_base_height) == "number" then
            ui.panel:SetHeight(ui.panel_base_height + (ui.practice_row_height or PRACTICE_ROW_HEIGHT) + 10)
        end
    else
        row:Hide()
        if ui.panel and type(ui.panel_base_height) == "number" then
            ui.panel:SetHeight(ui.panel_base_height)
        end
    end
end

-- The row's height: the prompt line, the button lines and the status line. The
-- row grows with the button lines (the drill-list row carries two groups: the
-- class's actions - the pick - and the class's drills). The height follows the
-- row's button lines; the panel's height follows the row's.
local function practice_row_set_height(self, lines)
    local row = ui.practice_row
    if not row then
        return
    end
    local count = type(lines) == "number" and lines or 0
    if count < 2 then
        count = 2
    end
    local height = 30 + count * (PRACTICE_ROW_BUTTON_H + PRACTICE_ROW_BUTTON_GAP)
    ui.practice_row_height = height
    row:SetHeight(height)
    if ui.panel and type(ui.panel_base_height) == "number" then
        local shown = (type(row.IsShown) == "function") and row:IsShown() or false
        ui.panel:SetHeight(ui.panel_base_height + (shown and (height + 10) or 0))
    end
end

-- The row's buttons: one per entry ({ key, label, spell_id }). The button's
-- OnClick hands its key back to the caller.
--
-- The buttons are REUSED from the row's own pool (keyed by the group and the
-- entry key): the row is rebuilt on every scenario step (open and close), and a
-- row that created a fresh button per rebuild leaked hundreds of hidden frames
-- per run. The pool only ever grows to the largest set the row showed, and the
-- label and the icon are updated IN PLACE.
--
-- A rebuild is a PASS: practice_row_begin opens it, the groups claim their
-- buttons, practice_row_finish hides every pooled button no group claimed.
local function practice_row_begin(self)
    local container = ui.practice_row_buttons
    if not container then
        return nil
    end
    container.pool = container.pool or {}
    container.index = container.index or {}
    container.buttons = container.buttons or {}
    container.claimed = {}
    return container
end

-- Place one group's buttons. The first_line argument puts a group on its own
-- lines (the drill-list row carries the class's actions and the class's
-- drills). Returns the number of lines the row now uses.
--
-- The pool lookup is inlined on purpose: the row's helpers are file-scope
-- locals and the module sits at Lua 5.1's local limit.
local function practice_row_set_buttons(self, container, group, entries, width, per_row, on_click, first_line)
    if not container then
        return first_line
    end
    local lines = first_line
    for i = 1, #entries do
        local entry = entries[i]
        if type(entry) == "table" and type(entry.key) == "string" and entry.key ~= "" then
            local pool_key = group .. "\001" .. entry.key
            local btn = container.index[pool_key]
            if not btn then
                btn = create_button(container, entry.label)
                container.index[pool_key] = btn
                container.pool[#container.pool + 1] = btn
            end
            btn:SetSize(width, PRACTICE_ROW_BUTTON_H)
            local column = (i - 1) % per_row
            local line = math.floor((i - 1) / per_row)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", container, "TOPLEFT",
                column * (width + PRACTICE_ROW_BUTTON_GAP),
                -(first_line + line) * (PRACTICE_ROW_BUTTON_H + PRACTICE_ROW_BUTTON_GAP))
            btn.key = entry.key
            -- The label: the drill's or the class's own label.
            if btn.label then
                btn.label:SetText(entry.label or entry.key)
                btn.label:ClearAllPoints()
                btn.label:SetPoint("CENTER", 0, 0)
            end
            -- The icon (when the class publishes a spell id) sits left of the
            -- label. The texture is created ONCE per button (the row is rebuilt
            -- on every step) and its art is swapped in place.
            local texture = nil
            if entry.spell_id then
                texture = spell_texture(entry.spell_id)
            end
            if texture then
                if not btn.row_icon then
                    btn.row_icon = btn:CreateTexture(nil, "ARTWORK")
                    btn.row_icon:SetPoint("LEFT", btn, "LEFT", 2, 0)
                    btn.row_icon:SetSize(PRACTICE_ROW_BUTTON_H - 4, PRACTICE_ROW_BUTTON_H - 4)
                end
                btn.row_icon:SetTexture(texture)
                btn.row_icon:Show()
                if btn.label then
                    btn.label:ClearAllPoints()
                    btn.label:SetPoint("LEFT", btn, "LEFT", PRACTICE_ROW_BUTTON_H + 2, 0)
                end
            elseif btn.row_icon then
                btn.row_icon:Hide()
            end
            btn:SetScript("OnClick", function()
                on_click(entry.key)
            end)
            container.claimed[btn] = true
            container.buttons[entry.key] = btn
            btn:Show()
            lines = math.max(lines, first_line + line + 1)
        end
    end
    return lines
end

-- The pass ends: every pooled button no group claimed is hidden. The frame stays
-- in the pool (that is the point - the next pass reuses it).
local function practice_row_finish(self, container)
    if not container then
        return
    end
    for i = 1, #container.pool do
        local btn = container.pool[i]
        if not container.claimed[btn] then
            btn:Hide()
        end
    end
    container.claimed = {}
end

-- The row's prompt line (what the rotation wants, or the drill list's header).
local function practice_row_prompt(self, text)
    if ui.practice_row_prompt then
        ui.practice_row_prompt:SetText(text or "")
    end
end

-- The row's status line (the last outcome, the run summary).
local function practice_row_status(self, text)
    if ui.practice_row_status then
        ui.practice_row_status:SetText(text or "")
    end
end

--=========================================================================================
-- The rotation scenario session
--=========================================================================================
-- The row syncers are declared here and defined below: the scenario's step opener
-- and the drill list's button handler call each other.
local scenario_row_sync
local drill_list_press
local drill_list_pick_press
local scenario_finish

-- Open the next scenario step: ask the class what it wants cast. A class that
-- cannot decide answers nil - the step is UNKNOWN, never a wrong action. A class
-- that states an explicit HOLD answers { action = nil, hold = true } - the step is
-- a hold (HU-8): casting during it is an illegal cast, doing nothing is correct.
local function scenario_open_step(self, now)
    local H = practice_harness()
    local run = ui.scenario_run
    if not H or type(run) ~= "table" or run.finished == true then
        return nil
    end
    local ctx = scenario_context(now, ui.scenario_last_action)
    local answer = H.practice_scenario_step(ui.scenario_class, ST, ctx)
    local step = {
        expected = nil,
        hold = false,
        reason = nil,
        opened_at = now,
        deadline = now + SCENARIO_STEP_SECONDS,
    }
    if answer then
        step.expected = answer.action
        step.hold = answer.hold == true
        step.reason = answer.reason
        if answer.action then
            scenario_note_action(answer.action)
        end
    end
    ui.scenario_step = step
    scenario_row_sync(self)
    return step
end

-- Close the open step with the player's cast (nil = nothing was cast) and grade
-- the decision. An unknown decision records NO attempt: the engine never invents a
-- grade and never calls the player's action wrong.
--
-- A hold step (HU-8) is graded by the engine: nothing cast during it is CORRECT
-- (and worth nothing - no attempt, so idle time cannot be farmed for points), and
-- any cast during it is an ILLEGAL CAST (F, an attempt that costs the streak).
--
-- A NEUTRAL action (the class's published set: a heal, a shield, food - an action
-- that is legitimate but that the rotation did not ask for) is not a mis-pick
-- either: the step records NO attempt (no points, no streak, no XP) and the run
-- counts it in its neutral tally.
local function scenario_close_step(self, expected, actual, hold, reason)
    local H = practice_harness()
    if not H or type(ui.scenario_run) ~= "table" then
        return nil
    end
    -- THE GRADER'S NORMALISATION (the seam, not the engine): the press and the
    -- class's answer are compared as CANONICAL keys, so a press is graded by the
    -- SPELL it represents and not by the spelling that reached the engine. The
    -- engine (H.rotation_run_decide) stays pure - it compares the two strings it
    -- is handed and knows nothing of the class's alias table.
    --
    -- A press the class published as NEUTRAL keeps its own spelling: the neutral
    -- set is keyed on the class's own vocabulary, and a neutral key is never an
    -- alias of a rotation action (the closed-list suite holds that).
    local neutral = ui.scenario_neutral
    if type(actual) == "string" and actual ~= "" then
        if type(neutral) ~= "table" or neutral[actual] ~= true then
            actual = ui.canonical_key(actual)
        end
    end
    if type(expected) == "string" and expected ~= "" then
        expected = ui.canonical_key(expected)
    end
    local decision = H.rotation_run_decide(ui.scenario_run, expected, actual, hold == true,
        neutral)
    ui.scenario_step = nil
    if not decision then
        return nil
    end
    if decision.outcome == "unknown" then
        practice_row_status(self, "unknown - the rotation could not decide")
        scenario_row_sync(self)
        return decision
    end
    if decision.actual then
        ui.scenario_last_action = decision.actual
    end
    local grade = H.ROTATION_OUTCOME_GRADES[decision.outcome]
    if grade then
        ui.record_graded_attempt(self, grade, nil)
    end
    ui.update_score(self)
    if decision.outcome == "correct" then
        ui.show_result(self, "CORRECT")
        practice_row_status(self, "correct: " .. tostring(decision.actual))
    elseif decision.outcome == "neutral" then
        -- A legitimate action the rotation did not ask for: the player did
        -- nothing wrong. No attempt is recorded (the grade map has no entry for
        -- a neutral step), so the score, the streak and the XP do not move.
        ui.show_result(self, "NEUTRAL")
        practice_row_status(self, string.format("NEUTRAL: %s - not a rotation action",
            tostring(decision.actual)))
    elseif decision.outcome == "out_of_order" then
        ui.show_result(self, "OUT OF ORDER")
        practice_row_status(self, string.format("out of order: wanted %s, cast %s",
            tostring(decision.expected), tostring(decision.actual)))
    elseif decision.outcome == "illegal_cast" then
        -- A cast during a hold: the wrong thing to do, and the engine says so
        -- plainly (the class's own hold reason rides the message).
        ui.show_result(self, "ILLEGAL CAST")
        local message = "illegal cast: the rotation is holding"
        if type(reason) == "string" and reason ~= "" then
            message = message .. " - " .. reason
        end
        practice_row_status(self, message)
    elseif decision.outcome == "hold_ok" then
        -- Correct, but worth nothing: no attempt is recorded (the grade map has
        -- no entry for a correct hold), so idling through a hold cannot farm
        -- points.
        ui.show_result(self, "HOLD OK")
        local message = "hold: correct - nothing cast"
        if type(reason) == "string" and reason ~= "" then
            message = message .. " - " .. reason
        end
        practice_row_status(self, message)
    else
        ui.show_result(self, "MISS")
        practice_row_status(self, string.format("miss: wanted %s", tostring(decision.expected)))
    end
    scenario_row_sync(self)
    return decision
end

-- The player cast an action in the scenario session: compare it with the action
-- the class asked for. A cast with no open step is not graded (it never counts as
-- a wrong action). A cast during an explicit HOLD is the illegal cast (HU-8).
local function scenario_cast(self, key)
    local step = ui.scenario_step
    if not step then
        return
    end
    scenario_close_step(self, step.expected, key, step.hold, step.reason)
end

-- One scenario tick: close an expired decision window, open the next step and
-- finish the run when the decisions are spent.
local function scenario_tick_session(self, now, elapsed)
    local H = practice_harness()
    local run = ui.scenario_run
    if not H or type(run) ~= "table" then
        return
    end
    local step = ui.scenario_step
    if step and type(step.deadline) == "number" and now >= step.deadline then
        -- The decision window closed with no cast: a MISS (the rotation wanted an
        -- action and the player did not cast it) - or a correct HOLD, when the
        -- class stated one (the engine decides, the UI only passes the flag).
        scenario_close_step(self, step.expected, nil, step.hold, step.reason)
    end
    if run.finished == true then
        scenario_finish(self, now)
        return
    end
    if ui.scenario_step == nil then
        scenario_open_step(self, now)
    end
end

-- The run is over: write the summary into the row. A run with nothing gradeable
-- (every step unknown) reads UNKNOWN - never a perfect S.
function scenario_finish(self, now)
    local H = practice_harness()
    local summary = H and H.rotation_run_summary(ui.scenario_run) or nil
    ui.scenario_summary = summary
    ui.scenario_step = nil
    if summary then
        -- The neutral counter rides along only when it matters: a run without a
        -- neutral action reads exactly as before (no default-visible change).
        local neutral = summary.neutral or 0
        if summary.grade then
            local text = string.format("run %s: %d/%d correct, %d mis-pick%s, %d unknown, %d hold%s",
                summary.grade, summary.correct, summary.steps, summary.mispicks,
                summary.mispicks == 1 and "" or "s", summary.unknown,
                summary.holds or 0, (summary.holds or 0) == 1 and "" or "s")
            if neutral > 0 then
                text = text .. string.format(", %d neutral%s", neutral, neutral == 1 and "" or "s")
            end
            practice_row_status(self, text)
        else
            local text = string.format("run unknown: %d step%s, %d unknown",
                summary.steps, summary.steps == 1 and "" or "s", summary.unknown)
            if neutral > 0 then
                text = text .. string.format(", %d neutral%s", neutral, neutral == 1 and "" or "s")
            end
            practice_row_status(self, text)
        end
    end
    scenario_row_sync(self)
    ui.update_info(self)
end

-- The scenario row's content: one button per action the class can ask for, and
-- the prompt line with the wanted action and the class's reason.
function scenario_row_sync(self)
    if not ui.practice_row then
        return
    end
    local order, labels = scenario_action_order()
    local entries = {}
    for i = 1, #order do
        entries[i] = {
            key = order[i],
            label = scenario_action_label(order[i], labels),
            spell_id = scenario_action_spell_id(order[i]),
        }
    end
    local container = practice_row_begin(self)
    local lines = practice_row_set_buttons(self, container, "action", entries,
        PRACTICE_ROW_ACTION_W, PRACTICE_ROW_ACTION_PER_ROW, function(key)
            scenario_cast(ST, key)
        end, 0)
    practice_row_finish(self, container)
    practice_row_set_height(self, lines)
    local step = ui.scenario_step
    if step and step.hold then
        -- An explicit hold (HU-8): the prompt says so, with the class's own
        -- reason, so the player knows the cast would be wrong.
        local text = "next: HOLD"
        if step.reason then
            text = text .. " - " .. step.reason
        end
        practice_row_prompt(self, text)
    elseif step and step.expected then
        local text = "next: " .. tostring(step.expected)
        if step.reason then
            text = text .. " - " .. step.reason
        end
        practice_row_prompt(self, text)
    elseif step then
        practice_row_prompt(self, "next: unknown (the rotation cannot decide)")
    else
        practice_row_prompt(self, "next: -")
    end
end

-- Start the rotation scenario session. Returns false when the class publishes no
-- scenario (the caller prints the loud "not available" notice - never a silent
-- paladin sim on the wrong class).
local function scenario_start_session(self, now)
    local H = practice_harness()
    local pr = st.practice
    if not (H and pr) then
        return false
    end
    -- The rotation scenario needs a LIVE swing engine (the rotation is timed off
    -- the swing). On the client that keeps the inert stand-in the scenario would
    -- produce nothing but unknown steps, so it refuses here and the caller
    -- prints the loud "not available on this client" notice.
    if practice_swing_engine_dead() then
        return false
    end
    local module = practice_class_module()
    if not H.practice_scenario_available(module) then
        return false
    end
    ui.scenario_class = module
    ui.scenario_run = H.new_rotation_run()
    ui.scenario_step = nil
    ui.scenario_last_action = nil
    ui.scenario_actions = {}
    ui.scenario_action_set = {}
    ui.scenario_inputs = {}
    ui.scenario_summary = nil
    -- The class's NEUTRAL action set (the legitimate actions the rotation does
    -- not ask for: a heal, a shield, food...). Nil when the class publishes
    -- none - then every non-rotation press stays a mis-pick, exactly as before.
    ui.scenario_neutral = nil
    if type(H.practice_neutral_actions) == "function" then
        ui.scenario_neutral = H.practice_neutral_actions(module)
    end
    ui.active = true
    ui.combat_paused = false
    ui.last_compute = 0
    ui.result_remaining = 0
    -- The scenario has no keybinds of its own (the class lane owns the key space).
    ui.keybinds = {}
    ui.score = pr.new_score()
    -- The progression scope follows the running mode: a scenario run grades under
    -- the scenario's id. The class owns the name (its own practice_scenario_key);
    -- the provider's progress facts are the fallback.
    ui.progress_mode_key = practice_scenario_id()
    if not ui.progress_mode_key then
        local provider = ui.practice_panel()
        local progress = provider and provider.progress
        ui.progress_mode_key = type(progress) == "table" and progress.scenario or nil
    end
    ui.begin_progress_session(self, now)
    ui.load_bests(self)
    ui.last_score_text = nil
    ui.last_info_text = nil
    ui.last_hint_text = nil
    ui.last_button_active = nil
    ui.last_fight_text = nil
    ui.current_display_rotation = nil
    build_practice_row(self)
    practice_row_show(self, true)
    -- The new modes have no fight of their own: the paladin sim's fight button
    -- stays out of their way (the scenario and the drill list own the session).
    if ui.panel and ui.panel.fight_btn then
        ui.panel.fight_btn:Hide()
    end
    scenario_open_step(self, now)
    ui.update_result_font(self)
    ui.refresh_icons(self)
    ui.update_info(self)
    ui.update_score(self)
    ui.update_button(self)
    ui.update_hint(self)
    ui.apply_settings(self)
    ui.panel:Show()
    ui.driver:Show()
    self:Print("Practice scenario started. Type /st practice to stop.")
    return true
end

--=========================================================================================
-- The generic drill-list session
--=========================================================================================

-- The drill row's content: the class's ACTIONS (the pick) and the class's DRILLS
-- (the skill to train).
--
-- The action group is the PICK channel: a drill that needs the player's choice
-- (the priority-order drills) compares the pick with the rotation's answer, so
-- the panel has to be able to supply one. A drill press with no pick grades the
-- moment only - the pick-based drills answer nil (UNKNOWN) and record nothing.
--
-- The twist drill is the PALADIN's own: it is listed first in the paladin's drill
-- list (the flagship practice stays reachable from the paladin's panel) and its
-- press hands the panel over to the twist session. It is a session, not a
-- moment-grader, so it never goes through the drill grader.
local function drill_row_sync(self)
    if not ui.practice_row then
        return
    end
    local container = practice_row_begin(self)
    if not container then
        return
    end
    -- The class's actions: the pick.
    local order, labels = scenario_action_order()
    local action_entries = {}
    for i = 1, #order do
        action_entries[i] = {
            key = order[i],
            label = scenario_action_label(order[i], labels),
            spell_id = scenario_action_spell_id(order[i]),
        }
    end
    local lines = practice_row_set_buttons(self, container, "action", action_entries,
        PRACTICE_ROW_ACTION_W, PRACTICE_ROW_ACTION_PER_ROW, function(key)
            drill_list_pick_press(ST, key)
        end, 0)
    -- The class's drills: the skill to train. The twist drill (the paladin's
    -- own) leads the list.
    local drill_entries = {}
    if practice_owns_twist_drill() then
        drill_entries[#drill_entries + 1] = { key = TWIST_DRILL_KEY, label = "Twist timing" }
    end
    for i = 1, #(ui.drill_list or {}) do
        local drill = ui.drill_list[i]
        if type(drill) == "table" and type(drill.key) == "string" and drill.key ~= ""
            and drill.key ~= TWIST_DRILL_KEY then
            drill_entries[#drill_entries + 1] = { key = drill.key, label = drill.label }
        end
    end
    lines = practice_row_set_buttons(self, container, "drill", drill_entries,
        PRACTICE_ROW_DRILL_W, PRACTICE_ROW_DRILL_PER_ROW, function(key)
            drill_list_press(ST, key)
        end, lines)
    practice_row_finish(self, container)
    practice_row_set_height(self, lines)
    practice_row_prompt(self, string.format(
        "drills: %d - press one to grade it (the actions above are your pick)",
        #drill_entries))
end

-- Grade one drill through the class's own grader, with the pick the panel
-- supplied. A grader that cannot judge (nil) reads UNKNOWN and records no
-- attempt - a grade is never invented.
--
-- The ctx is the class's own context (the engine's fallback when the class
-- publishes none) plus the pick and the session's own state.
--
-- The pick rides in every alias the class graders read (ctx.pick / ctx.pressed /
-- ctx.action / ctx.last_action). A class that publishes its own pick (the hunter's
-- live cast) does NOT shadow the press: the press wins, and the class's own pick
-- survives only when the player pressed nothing.
--
-- The session identity and the session state are the drill-list session's OWN:
-- the counters a class's grader keeps (the mis-pick window behind the S/A/B/C/D/F
-- band) hang off them. Keyed on the addon object they outlived the session - a
-- band's mis-picks survived into the next session and the drill decayed S -> F
-- for the life of the profile.
local function drill_list_grade(self, drill_key, pick)
    local H = practice_harness()
    if not H or type(ui.drill_list) ~= "table" then
        return
    end
    local now = api.get_time()
    -- THE PICK'S NORMALISATION (the same alias space as the scenario's grader):
    -- the pick is the panel's own button key and the class's grader compares it
    -- with the rotation's answer in the canonical key space, so the pick is
    -- normalised here - before the ctx is built, so every alias the class reads
    -- (ctx.last_action included) carries the canonical key.
    if type(pick) == "string" and pick ~= "" then
        pick = ui.canonical_key(pick)
    end
    local ctx = scenario_context(now, pick)
    if type(ctx) ~= "table" then
        ctx = { now = now, last_action = pick, resources = nil, cooldowns = nil }
    end
    -- F1 (drill-pick contract 2026-10-20): the drill-list PRESS is the pick. The
    -- block used to fill only an EMPTY alias, so a class that published its own
    -- pick alias kept it - and the class's own reader, which reads that alias
    -- FIRST, graded the class's value instead of the player's press. The hunter
    -- publishes ctx.pick (the live cast) and reads ctx.pick first, so a drill-list
    -- press made while a Steady Shot was casting was graded against the live cast
    -- instead of the press; the rogue and the shaman read ctx.action first, so the
    -- same hole opened for them.
    --
    -- The press wins in every alias. A class's own pick still SURVIVES when the
    -- player pressed nothing (the pick is empty below): the hunter's shot drills
    -- judge the shot that is actually in flight, and the SCENARIO path - a
    -- different call site - keeps the live cast as the pick, untouched.
    if type(pick) == "string" and pick ~= "" then
        ctx.pick = pick
        ctx.pressed = pick
        ctx.action = pick
    end
    ctx.session = ui.drill_list_session
    ctx.session_id = ui.drill_list_session
    ctx.state = ui.drill_list_state
    local grade = H.practice_drill_grade(ui.drill_list_class, drill_key, ST, ctx)
    -- The progression scope follows the drill: the mastery row is per drill.
    ui.progress_drill_key = drill_key
    ui.drill_list_current = drill_key
    if not grade then
        practice_row_status(self, "unknown: " .. tostring(drill_key))
        return
    end
    ui.record_graded_attempt(self, grade, nil)
    ui.update_score(self)
    ui.show_result(self, grade)
    practice_row_status(self, tostring(drill_key) .. ": " .. grade)
end

-- The player pressed an ACTION in the drill-list row: that action is the pick.
-- The drill the panel currently has selected is graded with it (the pick-based
-- drills need it), and the pick stays for the next drill press.
function drill_list_pick_press(self, action_key)
    if type(ui.drill_list) ~= "table" then
        return
    end
    if type(action_key) ~= "string" or action_key == "" then
        return
    end
    ui.drill_list_pick = ui.canonical_key(action_key)
    local drill_key = ui.drill_list_current
    if type(drill_key) ~= "string" or drill_key == "" then
        -- No drill selected yet: the class's first published drill is the one the
        -- pick grades (the panel's default scope).
        local first = ui.drill_list[1]
        drill_key = (type(first) == "table") and first.key or nil
    end
    if type(drill_key) ~= "string" or drill_key == "" then
        practice_row_status(self, "no drill to grade")
        return
    end
    drill_list_grade(self, drill_key, action_key)
end

-- Press one drill: grade it through the class's own grader, with the pick the
-- panel supplied. A grader that cannot judge (nil) reads UNKNOWN and records no
-- attempt - a grade is never invented.
function drill_list_press(self, drill_key)
    if type(ui.drill_list) ~= "table" then
        return
    end
    if type(drill_key) ~= "string" or drill_key == "" then
        return
    end
    if drill_key == TWIST_DRILL_KEY and practice_owns_twist_drill() then
        -- The twist drill is the paladin's own session, not a moment-grader: the
        -- drill-list session ends and the twist session (the flagship practice)
        -- starts. The session-local mode override keeps the Practice page's
        -- select untouched - the override is consumed by the start that reads it.
        ui.stop(self)
        ui.practice_mode_override = PRACTICE_MODE_CLASS
        ui.start(self)
        return
    end
    drill_list_grade(self, drill_key, ui.drill_list_pick)
end

-- Start the drill-list session. Returns false when the class publishes no drills
-- (the caller prints the loud "not available" notice).
local function drill_list_start_session(self, now)
    local H = practice_harness()
    local pr = st.practice
    if not (H and pr) then
        return false
    end
    local module = practice_class_module()
    local drills = H.practice_drills(module)
    if not drills then
        return false
    end
    ui.drill_list_class = module
    ui.drill_list = drills
    ui.drill_list_current = nil
    -- The session's own identity and state: the drill counters hang off them, so
    -- a band's mis-picks never outlive the session.
    ui.drill_list_session = {}
    ui.drill_list_state = {}
    ui.drill_list_pick = nil
    ui.active = true
    ui.combat_paused = false
    ui.last_compute = 0
    ui.result_remaining = 0
    ui.keybinds = {}
    ui.score = pr.new_score()
    -- The progression scope follows the drill that runs; until one is pressed the
    -- class's own default drill stands: the panel map's key when the class owns
    -- it (a class's own drills win over an inherited or shared key), else the
    -- class's first published drill.
    ui.progress_mode_key = nil
    ui.begin_progress_session(self, now)
    local default = nil
    local provider = ui.practice_panel()
    local progress = provider and provider.progress
    if type(progress) == "table" and type(progress.mode) == "string"
        and practice_owns_drill(practice_own_drill_keys(ST.active_class), progress.mode) then
        default = progress.mode
    end
    if not default and drills[1] then
        default = drills[1].key
    end
    if default then
        ui.progress_drill_key = default
    end
    ui.load_bests(self)
    ui.last_score_text = nil
    ui.last_info_text = nil
    ui.last_hint_text = nil
    ui.last_button_active = nil
    ui.last_fight_text = nil
    ui.current_display_rotation = nil
    build_practice_row(self)
    practice_row_show(self, true)
    -- The drill list has no fight of its own (same reason as the scenario mode).
    if ui.panel and ui.panel.fight_btn then
        ui.panel.fight_btn:Hide()
    end
    drill_row_sync(self)
    ui.update_result_font(self)
    ui.refresh_icons(self)
    ui.update_info(self)
    ui.update_score(self)
    ui.update_button(self)
    ui.update_hint(self)
    ui.apply_settings(self)
    ui.panel:Show()
    ui.driver:Show()
    self:Print("Practice drills started. Type /st practice to stop.")
    return true
end

function ui.start(self)
    self = self or ST
    if ui.active then
        return
    end
    local pr = st.practice
    if not pr then
        -- Genuinely unavailable: the flavor ships no practice engine.
        note_start_block(self, "Practice mode is not available.")
        return
    end
    if self.in_combat or (InCombatLockdown and InCombatLockdown()) then
        note_start_block(self, "Practice mode cannot be started in combat.")
        return
    end
    if not ui.panel then
        -- The init deadline can land in combat (reload mid-fight): init defers
        -- and retries in 1 s. A toggle inside that window finds no panel yet;
        -- build now instead of failing closed on a transient.
        pcall(ui.init, self)
        if not ui.panel then
            note_start_block(self, "Practice mode is not available (panel not built).")
            return
        end
    end

    -- The practice mode the Practice page selects. "class" (the default) runs the
    -- shipped per-class session unchanged; the two new modes run the shared
    -- rotation scenario or the class's drill list. A class that provides neither
    -- fails LOUDLY here - never a silent paladin sim on the wrong class.
    local mode = practice_mode(self)
    if mode == PRACTICE_MODE_SCENARIO then
        if not scenario_start_session(self, api.get_time()) then
            if practice_swing_engine_dead() then
                -- The client keeps the inert swing stand-in: the rotation the
                -- scenario runs needs a live swing engine, so the session is
                -- refused here (loud, never ten unknown steps).
                note_start_block(self,
                    "Practice scenario is not available on this client (no live swing engine).")
            else
                note_start_block(self, "Practice scenario is not available for this class.")
            end
        end
        return
    end
    if mode == PRACTICE_MODE_DRILLS then
        if not drill_list_start_session(self, api.get_time()) then
            note_start_block(self, "Practice drills are not available for this class.")
        end
        return
    end

    -- The class's OWN drill list wins: a class whose list supersedes the built-in
    -- drill its shipped session would run trains its own list instead (one skill,
    -- one truth - the operator's ruling), and a class with its own drills that
    -- does not own the twist drill never runs the inherited twist session. The
    -- check comes BEFORE the class routes: a superseded route steps aside.
    if practice_class_list_wins() then
        if not drill_list_start_session(self, api.get_time()) then
            note_start_block(self, "Practice drills are not available for this class.")
        end
        return
    end

    -- The ACTIVE class's own drill starts through the identical entry (options
    -- toggle or /st practice): same panel, same session flow, the class's own
    -- engine. The starter is internally fail-closed (shell validation + guarded
    -- shell calls), so the dispatch stays a direct call.
    if ui.practice_class_drill() then
        if not ui.practice_start_drill(self, api.get_time()) then
            note_start_block(self, "Practice drill is not available (session rejected).")
        end
        return
    end

    -- A drill class whose scenario key drifted (or half-loaded) fails closed
    -- here: never a silent paladin sim on the wrong class. The class supplies
    -- its own drift wording (its own fact).
    if ui.practice_drill_broken() then
        local panel = ui.practice_panel()
        note_start_block(self,
            (panel and type(panel.drift_message) == "string" and panel.drift_message)
            or "Practice mode is not available.")
        return
    end

    -- No practice of its own: the twist minigame is the PALADIN's drill, never an
    -- inherited session. A class that publishes no drills of its own and owns no
    -- drill (MAGE, PRIEST, WARLOCK, MONK, DEMONHUNTER, EVOKER) is refused LOUDLY
    -- here - never a silent paladin minigame on the wrong class.
    if not practice_publishes_drills() and not practice_owns_twist_drill() then
        note_start_block(self, "No practice for this class.")
        return
    end

    local db = self:get_class_table()
    local sim = ui.sim
    local now = api.get_time()

    ui.base_speed = resolve_base_speed(db)
    -- Stash the live GCD values for stop() to restore (the client's lib repopulates
    -- them on the next real cast; expires is nil-ed like GCD_OVER does).
    -- Nil-safe: a session stashes what exists, never throws on a half-built bar.
    if type(self.gcd) == "table" then
        ui.saved_gcd_duration = self.gcd.duration
        ui.saved_gcd_spell_length = self.gcd.spell_length
    else
        ui.saved_gcd_duration = nil
        ui.saved_gcd_spell_length = nil
    end
    if type(self.mainhand) == "table" then
        ui.saved_hand_speed = self.mainhand.speed
    else
        ui.saved_hand_speed = nil
    end

    -- Fresh state, fresh speed, then the fight: apply_haste before begin_fight so a
    -- previous session's haste cannot leave a too-fast first swing in place, and again
    -- after it so the immediate Bloodlust (bl_delay 0) rescales the swing.
    pr.reset(sim)
    -- Session tuning from the Practice page (archive db rows): nil reads keep
    -- the shipped sim defaults, so a fresh profile behaves byte-identically.
    -- Nil-safe: a session with no class profile row still starts on defaults.
    local queue_window = tonumber(db and db.practice_spell_queue_window) or 0.4
    if queue_window < 0 then
        queue_window = 0
    end
    if queue_window > 0.4 then
        queue_window = 0.4
    end
    sim.queue_window = queue_window
    pr.apply_haste(sim, ui.base_speed, now)
    local bl_delay = tonumber(db and db.practice_bl_delay) or 0
    if bl_delay < 0 then
        bl_delay = 0
    end
    pr.begin_fight(sim, now, { bl_delay = bl_delay })
    pr.apply_haste(sim, ui.base_speed, now)

    ui.active = true
    ui.combat_paused = false
    ui.last_compute = 0
    ui.result_remaining = 0
    -- Session-local keybinds (archived defaults; capture edits this table).
    ui.keybinds = {}
    for key, bind in pairs(pr.DEFAULT_KEYBINDS) do
        ui.keybinds[key] = bind
    end
    ui.dst_enabled = (type(db) == "table" and db.practice_dst_enabled == true)
    -- Fresh session score; bests load from the addon's own class profile table
    -- (nil-safe on a fresh profile) and the score line repaints from empty.
    ui.score = pr.new_score()
    -- The progression hook: a fresh pure session, the live clock stamp and the
    -- drill key (the session's graded attempts feed it from here on). The twist
    -- session grades the twist drill - the scope names the drill that is
    -- actually graded.
    ui.progress_mode_key = TWIST_DRILL_KEY
    ui.begin_progress_session(self, now)
    ui.load_bests(self)
    ui.last_score_text = nil
    -- Fresh timeline data; the opening band tracks the current rotation.
    ui.timeline_events = {}
    ui.timeline_event_count = 0
    ui.timeline_bands, ui.timeline_band_count =
        pr.bands_for_fight(pr.determine_rotation(sim))
    ui.timeline_auto_scroll = true
    ui.timeline_needs_render = true
    -- Force the seal-colour latch so the new session re-applies the bar colour even if
    -- it opens with the same seals the previous session ended on.
    ui.last_seal_sig = nil
    ui.last_rotation_line = nil
    ui.last_fight_text = nil
    ui.current_display_rotation = nil
    ui.build_bar_mappings(self)
    ui.update_result_font(self)
    ui.refresh_icons(self)
    ui.update_info(self)
    ui.update_score(self)
    ui.update_button(self)
    ui.update_hint(self)
    ui.update_haste_buttons(self)
    ui.update_keybind_labels(self)
    ui.rebind_keys(self)
    ui.update_rotation_display(self)
    ui.update_proc_icons(self)
    if ui.proc_icons then
        if ui.proc_icons.bl then
            ui.proc_icons.bl:Show()
        end
        if ui.proc_icons.dst then
            ui.proc_icons.dst:Show()
        end
    end
    if ui.timeline_frame then
        ui.timeline_frame:Show()
        ui.timeline_visible = true
        ui.render_timeline()
    end
    ui.apply_settings(self)
    ui.panel:Show()
    ui.driver:Show()
    ui.sync_to_addon(self)

    self:Print("Practice mode started. Type /st practice to stop.")
end

function ui.stop(self)
    self = self or ST
    if not ui.active then
        return
    end
    ui.active = false
    ui.combat_paused = false

    -- End the ACTIVE class's own drill run (nil for a class without one); the
    -- provider owns the teardown, and the shared body below persists bests,
    -- clears bindings and hides the frames. Fail-loud and counted on a
    -- half-loaded shell (the provider's stop is pcall-guarded).
    ui.practice_stop_drill(self)

    -- End the rotation scenario run and the drill-list session (both nil for the
    -- shipped per-class sessions). The pure run state dies with the session; the
    -- progression scope returns to the class's own fallback id.
    ui.scenario_run = nil
    ui.scenario_step = nil
    ui.scenario_class = nil
    ui.scenario_actions = nil
    ui.scenario_action_set = nil
    ui.scenario_inputs = nil
    ui.scenario_last_action = nil
    ui.scenario_summary = nil
    ui.scenario_neutral = nil
    ui.drill_list = nil
    ui.drill_list_class = nil
    ui.drill_list_current = nil
    ui.drill_list_session = nil
    ui.drill_list_state = nil
    ui.drill_list_pick = nil
    ui.progress_mode_key = nil
    practice_row_show(self, false)

    -- Session resource pools end with the session (sessions begin pool-less;
    -- the setters above re-arm them explicitly).
    ui.clear_session_pools(self)

    local pr = st.practice
    local sim = ui.sim
    if pr and sim then
        if sim.fight_active then
            pr.end_fight(sim)
        end
        pr.reset(sim)
    end
    -- The progression hook: the session's graded attempts, its live duration and
    -- its summary feed the progression + stats modules, the achievements are
    -- evaluated and the state is written once (the session-end write).
    --
    -- H2: the flush (not the bare session end) is the one writer - the logout path
    -- and the panel's hide use the same call, so a session that ends without the
    -- panel's stop still lands in the saved profile.
    ui.flush_progress_session(self, api.get_time())
    -- A session can end mid-fight, so bests save here as well as at fight end.
    ui.maybe_save_bests(self)

    ui.cancel_key_capture(self)
    if ClearOverrideBindings and ui.panel and not (InCombatLockdown and InCombatLockdown()) then
        ClearOverrideBindings(ui.panel)
    end
    ui.detach_all_overlays(self)

    ui.result_remaining = 0
    if ui.result_frame then
        ui.result_frame:SetAlpha(0)
    end
    if ui.panel then
        ui.panel:Hide()
    end
    if ui.driver then
        ui.driver:Hide()
    end
    if ui.rotation_display then
        ui.rotation_display:Hide()
    end
    ui.current_display_rotation = nil
    if ui.timeline_frame then
        ui.timeline_frame:Hide()
    end
    ui.timeline_visible = false
    ui.timeline_needs_render = false
    ui.timeline_events = {}
    ui.timeline_event_count = 0
    ui.timeline_bands = {}
    ui.timeline_band_count = 0
    if ui.proc_icons then
        if ui.proc_icons.bl then
            ui.proc_icons.bl:Hide()
        end
        if ui.proc_icons.dst then
            ui.proc_icons.dst:Hide()
        end
    end
    ui.clear_addon_state(self)

    self:Print("Practice mode stopped.")
end

-- Start/Stop Fight: toggle a fight inside an already running session (the archive split
-- start()/start_fight(); phase 2 starts the first fight with the session).
function ui.toggle_fight(self)
    self = self or ST
    if not ui.active then
        return
    end
    -- The rotation scenario and the drill list have no fight of their own: the
    -- paladin sim's fight button stays out of their way (their button is hidden).
    if ui.scenario_run or ui.drill_list then
        return
    end
    local fighting = ui.sim and ui.sim.fight_active
    if ui.hunter_session then
        fighting = ui.hunter_session.active
    end
    if ui.shaman_session then
        fighting = ui.shaman_session.active
    end
    if ui.rogue_session then
        fighting = ui.rogue_session.active
    end
    if ui.druid_session then
        fighting = ui.druid_session.active
    end
    if fighting then
        ui.stop_fight(self)
    else
        ui.start_fight(self)
    end
end

function ui.start_fight(self)
    self = self or ST
    if not ui.active or (ui.sim and ui.sim.fight_active)
        or ui.scenario_run or ui.drill_list
        or ui.practice_drill_active() == true then
        return
    end
    if self.in_combat or (InCombatLockdown and InCombatLockdown()) then
        self:Print("Practice fights cannot be started in combat.")
        return
    end
    -- The ACTIVE class's drill re-begins through its own provider (same
    -- Start/Stop Fight button); a half-loaded shell refuses loudly.
    if ui.practice_drill_running() then
        ui.practice_begin_fight(self, api.get_time())
        ui.update_button(self)
        ui.update_hint(self)
        ui.update_score(self)
        ui.sync_to_addon(self)
        return
    end

    local pr = st.practice
    local sim = ui.sim
    local now = api.get_time()
    pr.apply_haste(sim, ui.base_speed, now)
    pr.begin_fight(sim, now, {})
    pr.apply_haste(sim, ui.base_speed, now)
    -- Fresh timeline data with the opening band; the timeline shows on every fight
    -- (the archive's "always" default; there is no mode option in this lane).
    ui.timeline_events = {}
    ui.timeline_event_count = 0
    ui.timeline_bands, ui.timeline_band_count =
        pr.bands_for_fight(pr.determine_rotation(sim))
    ui.timeline_auto_scroll = true
    ui.timeline_needs_render = true
    ui.last_fight_text = nil
    if ui.timeline_frame then
        ui.timeline_frame:Show()
        ui.timeline_visible = true
        ui.update_timeline_button()
        ui.render_timeline()
    end
    ui.update_button(self)
    ui.update_hint(self)
    ui.update_haste_buttons(self)
    ui.update_score(self)
    ui.sync_to_addon(self)
end

function ui.stop_fight(self)
    self = self or ST
    local pr = st.practice
    local sim = ui.sim
    if ui.practice_drill_running() then
        if ui.practice_drill_active() ~= true then
            return
        end
    elseif not pr or not sim or not sim.fight_active then
        return
    end
    if ui.practice_drill_running() then
        ui.practice_end_fight(self)
    else
        pr.end_fight(sim)
        pr.apply_haste(sim, ui.base_speed, api.get_time())
    end
    ui.result_remaining = 0
    if ui.result_frame then
        ui.result_frame:SetAlpha(0)
    end
    -- Final render for post-fight review; the data and the frame stay up.
    ui.timeline_needs_render = true
    if ui.timeline_visible then
        ui.render_timeline()
    end
    -- The hunter shot report (H2): re-render when visible so the post-fight numbers
    -- are final. Visibility is user-driven; this never shows the frame by itself.
    if ui.hunter_report_visible then
        ui.render_hunter_report(self)
    end
    -- The warrior Execute report (W6): re-render when visible so the post-fight
    -- numbers are final. Visibility is user-driven; this never shows the frame
    -- by itself.
    if ui.warrior_execute_report_visible then
        ui.render_warrior_execute_report(self)
    end
    if ui.panel and ui.panel.fight_timer_text then
        ui.panel.fight_timer_text:SetText("")
    end
    ui.last_fight_text = nil
    ui.update_button(self)
    ui.update_hint(self)
    -- The fight's attempts are final: persist personal bests and repaint the line.
    ui.maybe_save_bests(self)
    ui.update_score(self)
    ui.sync_to_addon(self)
end

--=========================================================================================
-- Driver: per-frame simulation tick
--=========================================================================================
-- N4: compute isolation. The session driver owns the sim clock; a throwing engine
-- must freeze the tick's scoring, never corrupt the session. The contract lives in
-- guard.lua (one implementation for the whole addon): first throw prints once, every
-- throw counts in self.bar_hook_errors (read by /st diag), the site quarantines after
-- st.guard.QUARANTINE_THROWS. Degrade freezes scoring for the tick (no
-- record_attempt/update_score/show_result on a failed compute).
--
-- What stays here is this module's own wording ("Practice ...") and its own site key.
-- The drill paths keep their own pcall (each one grades through its own shell and
-- reads its own result), so they report the failure to the shared contract.
st.guard.label("practice", "Practice")
local PRACTICE_ERROR_SITE = "practice:tick"

local function note_practice_error(self, err)
    st.guard.note(self or ST, PRACTICE_ERROR_SITE, err)
end

local function practice_quarantined(self)
    return st.guard.quarantined(self or ST, PRACTICE_ERROR_SITE)
end

function ui.tick(self, elapsed)
    if not ui.active then
        return
    end
    local pr = st.practice
    if not pr then
        return
    end

    -- The result popup fades on every frame for a smooth step between compute ticks.
    ui.update_result_fade(elapsed)

    local now = api.get_time()
    if now - (ui.last_compute or 0) < UPDATE_INTERVAL then
        return
    end
    ui.last_compute = now

    -- The throttled progression write: at most one save every five minutes while
    -- the session runs (never one per attempt - spec §6).
    ui.maybe_persist_progress(self, now)

    if ui.pending_apply and not (InCombatLockdown and InCombatLockdown()) then
        ui.apply_settings(self)
    end

    -- Real combat pauses the simulation entirely: no casts, no swing progression, no
    -- grading (the archive only paused grading; phase 2 freezes the whole sim so a real
    -- fight cannot be double-counted or raced).
    if self.in_combat then
        if not ui.combat_paused then
            ui.combat_paused = true
            ui.combat_pause_start = now
            ui.update_hint(self)
        end
        ui.sync_to_addon(self)
        ui.update_button(self)
        return
    end
    if ui.combat_paused then
        ui.combat_paused = false
        local shift = now - (ui.combat_pause_start or now)
        -- The ACTIVE class's drill provider shifts its own clocks; the sim shift
        -- stays the shared fallback (paladin sim / no drill session).
        local panel = ui.practice_panel()
        if panel and type(panel.session) == "table"
            and type(panel.session.pause) == "function" then
            pcall(panel.session.pause, self, ui, shift)
        else
            ui.shift_sim_times(ui.sim, shift)
        end
        ui.update_hint(self)
    end

    -- Quarantine gates every compute path below (paladin sim and all four drill
    -- shells): a poisoned tick stops computing for the session, never corrupting
    -- it.
    if practice_quarantined(self) then
        return
    end
    local sim = ui.sim
    local out = ui.out
    if ui.scenario_run then
        local ok, tick_err = pcall(scenario_tick_session, self, now, elapsed)
        if not ok then
            note_practice_error(self, tick_err)
            return
        end
    elseif ui.drill_list then
        -- The drill list has no clock of its own: its buttons grade on the press.
        -- The tick only keeps the panel's readout live.
        ui.update_info(self)
    elseif ui.practice_drill_running() then
        local panel = ui.practice_panel()
        local session_api = panel and panel.session
        if not session_api or type(session_api.tick) ~= "function" then
            note_practice_error(self, "the class drill session has no tick seam")
            return
        end
        local ok, tick_err = pcall(session_api.tick, self, now, elapsed, ui)
        if not ok then
            note_practice_error(self, tick_err)
            return
        end
    else
    local ok, tick_err = pcall(pr.tick, sim, now, elapsed, out)
    if not ok then
        note_practice_error(self, tick_err)
        return
    end
    if out.buffs_changed or out.bl_fired or out.buff_changed then
        -- A haste source started or expired (the tick's own buffs_changed / bl_fired,
        -- or buff_changed merged from a queue-fired cast): re-derive speed and GCD.
        pr.apply_haste(sim, ui.base_speed, now)
    end
    if out.swing_ready then
        -- A swing landed: restart the next swing (the engine's contract keeps the
        -- restart with the caller), then grade the landing. A real-combat pause skips
        -- this whole tick, which is how grading is suspended there. Guarded (N4):
        -- a throwing grade freezes scoring for the tick, never corrupts the session.
        local grade = ui.grade_out
        local swing_ok, swing_err = pcall(function()
            pr.start_swing(sim, now)
            pr.on_swing(sim, now, grade)
        end)
        if not swing_ok then
            note_practice_error(self, swing_err)
            return
        end
        if grade.feedback then
            ui.show_result(self, grade.feedback)
        end
        -- Scoring: a graded attempt (grade is nil for swings with no attempt) feeds
        -- the running session score, the progression state and repaints the panel
        -- score line.
        if grade.grade and ui.score then
            ui.record_graded_attempt(self, grade.grade, grade.lead_ms)
            ui.update_score(self)
        end
        -- Timeline: mirror the swing event with its fight-relative time.
        ui.timeline_event_count = pr.push_timeline_event(ui.timeline_events,
            ui.timeline_event_count, sim, now, "melee", pr.MELEE_TEXTURE,
            grade.result, grade.timeline_event and grade.timeline_event.seal)
        ui.timeline_needs_render = true
        -- DST proc roll (archive sim_on_swing 3515-3525): session toggle + unlocked.
        if ui.dst_enabled and not sim.locked_rotation then
            local roll = (ui.random or math.random)()
            if pr.maybe_dst_proc(sim, now, roll) then
                pr.apply_haste(sim, ui.base_speed, now)
            end
        end
        -- Drill rage generation (sim-resources lane): the landed white swing
        -- banks rage through the sim formula when the drill owns a pool AND a
        -- drill damage + level. Both default nil (unknown-hides): no pool or
        -- no damage runs the tick exactly as before.
        if ui.rage_pool and type(ui.drill_white_damage) == "number" then
            local conv = pr.rage_conversion and pr.rage_conversion(ui.drill_level) or nil
            local gain = conv and pr.rage_white_gain
                and pr.rage_white_gain(ui.drill_white_damage, conv) or nil
            if gain then
                pr.rage_gain(ui.rage_pool, gain)
            end
        end
    end
    end
    if sim.fight_active then
        -- Fight clock, rotation bands, rotation display.
        ui.update_fight_timer(self, now)
        local rotation
        local rot_ok, rot_res = pcall(pr.determine_rotation, sim)
        if rot_ok then
            rotation = rot_res
        else
            note_practice_error(self, rot_res)
            rotation = nil
        end
        if rotation then
            local before = ui.timeline_band_count
            ui.timeline_band_count = pr.track_rotation_band(ui.timeline_bands,
                ui.timeline_band_count, rotation, now - sim.fight_start_time)
            if ui.timeline_band_count ~= before then
                ui.timeline_needs_render = true
            end
        end
        ui.update_rotation_display(self, rotation)
    end
    if ui.timeline_needs_render and ui.timeline_visible then
        ui.render_timeline()
    end
    -- The tick's merged cast flags (queue_ready from a queued ability, seal_faded,
    -- cooldown_set, ...) all land in the same mirror + icon refresh below.
    ui.sync_to_addon(self)
    ui.refresh_icons(self)
    ui.update_info(self)
    ui.update_resource_display(self)
    ui.update_button(self)
    ui.update_haste_buttons(self)
    ui.update_proc_icons(self)
    ui.update_overlays(self, now)
end

--=========================================================================================
-- Bridge: mirror the simulation onto the addon's live state
--=========================================================================================
function ui.sync_to_addon(self)
    self = self or ST
    -- A running class drill owns the bridge through its provider: the hunter
    -- and the druid mirror nothing (their sessions own bar visibility via
    -- main.lua's guard); the shaman and the rogue mirror their own drill swing.
    if ui.practice_drill_running() then
        local panel = ui.practice_panel()
        if panel and type(panel.session) == "table"
            and type(panel.session.sync) == "function" then
            pcall(panel.session.sync, self, ui)
        end
        return
    end
    local sim = ui.sim
    if not sim then
        return
    end
    local now = api.get_time()

    -- Swing mirror (main.lua's bars read these fields and compare to GetTime()).
    local d = self.mainhand
    d.speed = sim.effective_speed
    if sim.swing_active then
        d.start = sim.swing_ends_at - sim.effective_speed
        d.ends_at = sim.swing_ends_at
        d.is_paused = false
    else
        -- No swing in flight (attack hold, or a fight that has not started): hold an
        -- empty bar instead of animating a swing that is not happening.
        d.start = now
        d.ends_at = now + sim.effective_speed
        d.current_progress = 0
        d.is_paused = true
    end
    d.is_full = false
    if sim.attack_paused or sim.attack_pause_pending or ui.combat_paused then
        d.is_paused = true
    end

    -- GCD mirror. duration/expires feed the bar's GCD underlay and markers;
    -- spell_length feeds the guide's G input through main.lua's
    -- get_spell_gcd_duration / set_gcd_times_before_swing_seconds.
    local g = self.gcd
    local gcd_changed = (g.duration ~= sim.effective_gcd) or (g.spell_length ~= sim.effective_gcd)
    g.duration = sim.effective_gcd
    g.spell_length = sim.effective_gcd
    g.expires = (sim.gcd_active and math.max(sim.gcd_expires, now)) or nil
    if gcd_changed then
        if g.phys_length then
            self:set_gcd_times_before_swing_seconds()
        end
        self:on_gcd_length_change()
    end

    -- Seal mirror: the twist visuals, bar colours and the guide read the sim state.
    -- The bar's seal colour is re-applied whenever the mirrored seal set changes (the
    -- archive did the same through update_bar_on_aura_change in start_fight/sim_cast);
    -- without it the simulation's seal swaps would be invisible on the bar itself.
    local seal_sig = (sim.seal_1_label or "-") .. "/" .. (sim.seal_2_label or "-")
    -- The shared bridge never stamps paladin seal fields onto a class that
    -- mirrors none: the class's own sync seam decides (a class without one
    -- simply mirrors nothing here).
    -- The active class's sim-path mirror seam (the paladin's seal state), if it
    -- has one. A class without the seam simply mirrors nothing here.
    local sim_panel = ui.practice_panel()
    if sim_panel and type(sim_panel.session) == "table"
        and type(sim_panel.session.sync_sim) == "function" then
        pcall(sim_panel.session.sync_sim, self)
    end
    if seal_sig ~= ui.last_seal_sig then
        ui.last_seal_sig = seal_sig
        self:set_bar_color("mainhand")
    end
    -- Practice owns the mainhand bar while the session runs (main.lua's hide_bar guard
    -- covers the range-finder loop, which re-runs bar visibility every 0.05 s).
    self:show_bar("mainhand")
end

-- Shifts every still-future simulation deadline by `shift` seconds - the real-combat
-- pause of the sim. Deadlines that already passed before the pause stay expired, so an
-- expiring buff cannot be kept alive by combat.
function ui.shift_sim_times(sim, shift)
    if not sim or not shift or shift <= 0 then
        return
    end
    local now = api.get_time()
    for i = 1, #SHIFTED_SIM_TIMES do
        local field = SHIFTED_SIM_TIMES[i]
        local value = sim[field]
        if type(value) == "number" and value > now then
            sim[field] = value + shift
        end
    end
end

-- Restores the addon's live state after the session ends: the swing bar goes to its
-- idle (full) look, the real GCD values come back, and the real auras take over.
function ui.clear_addon_state(self)
    -- A drill session restores its own live state through its provider: the
    -- hunter/druid only recompute bar visibility; the shaman/rogue return the
    -- swing bar to idle (the live GCD and auras were never touched). The route
    -- (not the session object) decides: ui.stop clears the session BEFORE this
    -- teardown runs.
    if ui.practice_class_drill() then
        local panel = ui.practice_panel()
        if panel and type(panel.session) == "table"
            and type(panel.session.clear) == "function" then
            pcall(panel.session.clear, self, ui)
        end
        return
    end
    local now = api.get_time()
    local d = self.mainhand
    d.speed = ui.saved_hand_speed or d.speed
    local speed = d.speed or 3.5
    -- The idle look of a timer whose swing just ended (progress clamps to 1).
    d.start = now - speed
    d.ends_at = now
    d.current_progress = 1
    d.is_full = true
    d.is_paused = false
    self:on_bar_inactive("mainhand")

    local g = self.gcd
    g.duration = ui.saved_gcd_duration
    g.spell_length = ui.saved_gcd_spell_length
    g.expires = nil
    if g.phys_length then
        self:set_gcd_times_before_swing_seconds()
    end
    self:on_gcd_length_change()

    -- Real auras take over again (also restores the bar's seal colour). The
    -- active class's sim-path restore seam (the paladin's on_aura_change) is
    -- callable-guarded: a class without the seam fails closed instead of
    -- throwing on teardown.
    local panel = ui.practice_panel()
    if panel and type(panel.session) == "table"
        and type(panel.session.clear_sim) == "function" then
        pcall(panel.session.clear_sim, self)
    end
    self:handle_bar_visibility("mainhand")
end

--=========================================================================================
-- Simulated casts
--=========================================================================================
function ui.cast_key(self, key)
    self = self or ST
    if not ui.active then
        return
    end
    local pr = st.practice
    if not pr then
        return
    end
    if self.in_combat then
        -- The grid is silent while the real-combat pause freezes the simulation.
        return
    end

    -- The rotation scenario grades the cast against the action the class asked
    -- for (same grid, same scoring flow, the shared engine). Quarantine-gated and
    -- pcall-isolated like the tick path.
    if ui.scenario_run then
        if not practice_quarantined(self) then
            local ok, cast_err = pcall(scenario_cast, self, key)
            if not ok then
                note_practice_error(self, cast_err)
            end
        end
        return
    end

    -- The drill-list session: the panel's icon press is the PLAYER'S PICK (the
    -- action under test). It grades the drill the panel currently has selected,
    -- through the class's own grader. Quarantine-gated and pcall-isolated like
    -- the tick path.
    if ui.drill_list then
        if not practice_quarantined(self) then
            local ok, cast_err = pcall(drill_list_pick_press, self, key)
            if not ok then
                note_practice_error(self, cast_err)
            end
        end
        return
    end

    -- The ACTIVE class's drill grades the simulated cast through its provider
    -- (same grid, same scoring flow, the class's own engine). Quarantine-gated
    -- and pcall-isolated like the tick path: a throwing cast freezes scoring,
    -- never the session.
    if ui.practice_class_drill() then
        if not ui.practice_drill_running() then
            -- A drill cast with no session is a LOUD refusal (the player clicked
            -- a drill icon and nothing happened), never a fall-through to the
            -- paladin sim.
            note_cast_block(self, "Drill cast ignored (no drill session is running).")
            return
        end
        if not practice_quarantined(self) then
            local panel = ui.practice_panel()
            local session_api = panel and panel.session
            if not session_api or type(session_api.cast) ~= "function" then
                note_practice_error(self, "the class drill session has no cast seam")
                return
            end
            local ok, grade, margin = pcall(session_api.cast, self, key, ui)
            if not ok then
                note_practice_error(self, grade)
                return
            end
            if grade == nil then
                return
            end
            ui.record_graded_attempt(self, grade, margin)
            ui.update_score(self)
            ui.show_result(self, grade)
            ui.flash_overlay(self, key)
        end
        return
    end

    local sim = ui.sim
    local now = api.get_time()
    local out = ui.cast_out
    -- Drill mana consumption (sim-resources lane): a session mana pool spends
    -- the caller-fed cost for the cast key. Costs default unknown
    -- (rank-dependent; the class-side GetSpellPowerCost feed is owed): no pool
    -- or no cost runs the cast exactly as before.
    local mana_cost = nil
    if ui.mana_pool and type(ui.mana_costs) == "table" then
        local c = ui.mana_costs[key]
        if type(c) == "number" and c == c and c >= 0 then
            mana_cost = c
        end
    end
    if mana_cost and not pr.mana_can_spend(ui.mana_pool, mana_cost) then
        out.gcd_started = false
        out.gcd_blocked = false
        out.queued = false
        out.seal_changed = false
        out.twist_armed = false
        out.buff_changed = false
        out.cooldown_set = false
        out.resumed_attack = false
        out.ignored = true
        out.judged_seal = nil
        out.held_swing = nil
        ui.show_result(self, "OOM")
        ui.update_resource_display(self)
        return
    end
    pr.cast(sim, key, now, out)
    -- A fired cast (not ignored, not GCD-blocked, not queued for later) spends
    -- its cost now. Queue-fired casts spend nothing (filed follow-up: the
    -- internal queue path bypasses this cast site).
    if mana_cost and not out.ignored and not out.gcd_blocked and not out.queued then
        pr.mana_spend(ui.mana_pool, mana_cost)
    end
    if key == "aw" and out.buff_changed then
        -- AW macro (archive sim_cast_buff 3198-3208: practice_aw_includes_pot /
        -- sob): the pieces apply the way the archive applies them, not through
        -- the GCD-gated cast path. Pot sets the buff directly (no GCD, dup- and
        -- lock-guarded like activate_haste_pot); SoB casts the full seal when
        -- the GCD is free (like sim_cast_seal, twist-arming included). Both ride
        -- the Practice page toggles (nil = off).
        local db = self:get_class_table()
        if db.practice_aw_includes_pot == true
            and not sim.has_haste_pot and not sim.locked_rotation then
            sim.has_haste_pot = true
            sim.haste_pot_buff_expires = now + (pr.ABILITIES.hpot.duration or 15)
            out.buff_changed = true
        end
        if db.practice_aw_includes_sob == true
            and not (sim.gcd_active and sim.gcd_expires > now) then
            local mout = {}
            pr.cast(sim, "sob", now, mout)
            out.gcd_started = out.gcd_started or mout.gcd_started
            out.seal_changed = out.seal_changed or mout.seal_changed
            out.twist_armed = out.twist_armed or mout.twist_armed
            out.buff_changed = out.buff_changed or mout.buff_changed
            out.cooldown_set = out.cooldown_set or mout.cooldown_set
            local ab = pr.ABILITIES["sob"]
            local lane = ab and pr.cast_timeline_lane("sob")
            if lane and sim.fight_active then
                ui.timeline_event_count = pr.push_timeline_event(ui.timeline_events,
                    ui.timeline_event_count, sim, now, lane, ability_texture("sob"), nil,
                    ab.seal_label)
                ui.timeline_needs_render = true
            end
        end
    end
    if out.buff_changed then
        -- Haste pot / Abacus change the effective speed and GCD.
        pr.apply_haste(sim, ui.base_speed, now)
    end
    -- Timeline: seals log on their seal lane, cs/judge/consec on their own lane
    -- (archive sim_cast_seal 3087-3093 + sim_cast_ability 3165-3168).
    local lane = pr.cast_timeline_lane(key)
    if lane and sim.fight_active then
        local ab = pr.ABILITIES[key]
        local seal_active = nil
        if ab.type == "seal" then
            seal_active = ab.seal_label
        elseif key == "judge" then
            seal_active = out.judged_seal
        end
        ui.timeline_event_count = pr.push_timeline_event(ui.timeline_events,
            ui.timeline_event_count, sim, now, lane, ability_texture(key), nil,
            seal_active)
        ui.timeline_needs_render = true
    end
    ui.flash_overlay(self, key)
    -- The out flags nest inside the bridge: gcd_started -> the GCD mirror,
    -- seal_changed/twist_armed -> practice_sync, buff_changed/cooldown_set -> the icon
    -- swipes; sync + refresh handle every branch and are cheap.
    ui.sync_to_addon(self)
    ui.refresh_icons(self)
    ui.update_info(self)
    ui.update_resource_display(self)
    ui.update_button(self)
    if out.buff_changed then
        ui.update_haste_buttons(self)
        ui.update_proc_icons(self)
    end
    ui.update_overlays(self, now)
end

--=========================================================================================
-- Icon states (set-once swipes, per nextaction_ui.lua)
--=========================================================================================
function ui.refresh_icons(self)
    local sim = ui.sim
    if not sim then
        return
    end
    local now = api.get_time()
    local gcd_remaining = 0
    if sim.gcd_active and sim.gcd_expires > now then
        gcd_remaining = sim.gcd_expires - now
    end
    for _, icon in pairs(ui.bar_mappings) do
        if icon.cooldown_field then
            local expires = sim[icon.cooldown_field] or 0
            local remaining = (expires > now) and (expires - now) or 0
            set_swipe(icon.ability_swipe, icon.cooldown, remaining, icon.cooldown_full)
        end
        if icon.gcd_gated then
            set_swipe(icon.gcd_swipe, icon.gcd_cooldown, gcd_remaining, sim.effective_gcd)
            if gcd_remaining > 0 then
                icon.gcd_dim:Show()
            else
                icon.gcd_dim:Hide()
            end
        end
        -- Buff / active-seal border highlights (archive update_icon_states 3564-3592).
        if icon.border and icon.border.SetColorTexture and icon.key then
            local key = icon.key
            local border = BORDER_IDLE
            if key == "aw" and sim.aw_buff_expires > now then
                border = BORDER_AW
            elseif key == "hpot" and sim.has_haste_pot then
                border = BORDER_HPOT
            elseif key == "abacus" and sim.has_abacus then
                border = BORDER_ABACUS
            else
                local pr = st.practice
                local ab = pr and pr.ABILITIES[key]
                if ab and ab.type == "seal" and sim.active_seals[ab.seal_label] then
                    border = BORDER_SEAL
                end
            end
            icon.border:SetColorTexture(border[1], border[2], border[3], border[4])
        end
    end
end

--=========================================================================================
-- Panel display updates
--=========================================================================================
function ui.update_info(self)
    local panel = ui.panel
    if not panel or not panel.info_text then
        return
    end
    local sim = ui.sim
    if not sim then
        return
    end
    -- The rotation scenario reports its run progress here (same line, drill readout).
    if ui.scenario_run then
        local H = practice_harness()
        local summary = H and H.rotation_run_summary(ui.scenario_run) or nil
        local text = "Scenario idle"
        if summary then
            local family = practice_rotation_family()
            text = string.format("%sStep %d/%d  correct %d  mis-picks %d  unknown %d",
                family and ("Rotation " .. family .. "  ") or "",
                summary.steps, summary.max_steps, summary.correct, summary.mispicks,
                summary.unknown)
            -- The hold counters ride along only when they matter: a run without a
            -- hold reads exactly as before (no default-visible change).
            if (summary.holds or 0) > 0 or (summary.illegal_casts or 0) > 0 then
                text = text .. string.format("  holds %d  illegal %d",
                    summary.holds or 0, summary.illegal_casts or 0)
            end
            -- The neutral counter rides along only when it matters (same rule).
            if (summary.neutral or 0) > 0 then
                text = text .. string.format("  neutral %d", summary.neutral or 0)
            end
        end
        if text ~= ui.last_info_text then
            ui.last_info_text = text
            panel.info_text:SetText(text)
        end
        return
    end
    -- The drill list reports its attempt count here (same line, drill readout).
    if ui.drill_list then
        local attempts = (ui.score and ui.score.attempts) or 0
        local text = string.format("Drills %d  attempts %d", #ui.drill_list, attempts)
        if text ~= ui.last_info_text then
            ui.last_info_text = text
            panel.info_text:SetText(text)
        end
        return
    end
    -- The active class's drill reports its own live status here (same line,
    -- drill readout); a class without a status seam reads its own idle line.
    if ui.practice_class_drill() then
        local provider = ui.practice_panel()
        local text
        if provider and type(provider.status) == "function" then
            local ok_status, status = pcall(provider.status, ui, api.get_time())
            if ok_status and type(status) == "string" then
                text = status
            end
        end
        if not text then
            text = (provider and provider.idle_status) or "Drill idle"
        end
        if text ~= ui.last_info_text then
            ui.last_info_text = text
            panel.info_text:SetText(text)
        end
        return
    end
    local text = string.format("Speed: %.1fs  GCD: %.2fs", sim.effective_speed or 0,
        sim.effective_gcd or 0)
    if text ~= ui.last_info_text then
        ui.last_info_text = text
        panel.info_text:SetText(text)
    end
    -- Rotation line (archive update_info_display 3684-3686, via st.nextaction names).
    if panel.rotation_text then
        local pr = st.practice
        local rotation = pr and pr.determine_rotation(sim)
        local na = st.nextaction
        local name = rotation
            and ((na and na.display_names and na.display_names[rotation]) or rotation)
            or "--"
        local line = "Rotation: " .. name
        if line ~= ui.last_rotation_line then
            ui.last_rotation_line = line
            panel.rotation_text:SetText(line)
        end
    end
end

-- Fight clock line (archive sim_update 3387-3394, text half).
function ui.update_fight_timer(self, now)
    local panel = ui.panel
    if not panel or not panel.fight_timer_text then
        return
    end
    local sim = ui.sim
    local pr = st.practice
    local text = ""
    if ui.practice_class_drill() then
        local provider = ui.practice_panel()
        local elapsed
        if provider and type(provider.fight_elapsed) == "function" then
            local ok_el, el = pcall(provider.fight_elapsed, ui, now or api.get_time())
            if ok_el then
                elapsed = el
            end
        end
        if pr and elapsed then
            text = pr.format_fight_time(elapsed)
        end
    elseif sim and sim.fight_active and pr then
        now = now or api.get_time()
        text = pr.format_fight_time(now - sim.fight_start_time)
    end
    if text ~= ui.last_fight_text then
        ui.last_fight_text = text
        panel.fight_timer_text:SetText(text)
    end
end

function ui.update_button(self)
    local panel = ui.panel
    if not panel or not panel.fight_btn then
        return
    end
    local active = ui.sim and ui.sim.fight_active
    -- The active class's drill reads its own run state (same button, drill fight).
    local drill_active = ui.practice_drill_active()
    if drill_active ~= nil then
        active = drill_active
    end
    if active == ui.last_button_active then
        return
    end
    ui.last_button_active = active
    if active then
        panel.fight_btn.label:SetText("|cFFFF0000Stop Fight|r")
        panel.fight_btn:SetBackdropColor(0.4, 0.1, 0.1, 0.9)
    else
        panel.fight_btn.label:SetText("Start Fight")
        panel.fight_btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    end
end

function ui.update_hint(self)
    local panel = ui.panel
    if not panel or not panel.hint_text then
        return
    end
    local text
    if ui.combat_paused then
        text = HINT_PAUSED
    elseif ui.scenario_run then
        local run = ui.scenario_run
        text = (type(run) == "table" and run.finished == true)
            and HINT_SCENARIO_STOPPED or HINT_SCENARIO_ACTIVE
    elseif ui.drill_list then
        text = HINT_DRILLS_ACTIVE
    elseif ui.practice_class_drill() then
        local provider = ui.practice_panel()
        if ui.practice_drill_active() == true then
            text = (provider and provider.hint_active) or HINT_ACTIVE
        else
            text = (provider and provider.hint_stopped) or HINT_STOPPED
        end
    elseif ui.sim and not ui.sim.fight_active then
        text = HINT_STOPPED
    else
        text = HINT_ACTIVE
    end
    if text ~= ui.last_hint_text then
        ui.last_hint_text = text
        panel.hint_text:SetText(text)
    end
end

--=========================================================================================
-- Result popup ("TWIST!" / "MISS")
--=========================================================================================
function ui.show_result(self, feedback)
    local result = ui.result_frame
    if not result then
        return
    end
    local db = self:get_class_table()
    -- Nil-safe: a session with no class profile row still grades (the shipped
    -- colours/duration stand in, like the Practice page nil-reads).
    if type(db) ~= "table" then
        db = {}
    end
    local color
    if ui.scenario_run or ui.drill_list then
        -- The shared engine's modes: a grade letter other than F is a hit; the
        -- decision outcomes follow the same rule (CORRECT hits, MISS, OUT OF
        -- ORDER and ILLEGAL CAST - a cast during an explicit hold - miss).
        -- NEUTRAL is NOT a miss either: a legitimate action the rotation did
        -- not ask for is no mistake, so it reads like HOLD OK.
        if feedback == "F" or feedback == "MISS" or feedback == "OUT OF ORDER"
            or feedback == "ILLEGAL CAST" then
            color = db.practice_result_color_miss or RESULT_COLOR_MISS
        else
            color = db.practice_result_color_hit or RESULT_COLOR_HIT
        end
    elseif ui.practice_class_drill() then
        -- Drill grades: anything but F is a hit; the MOVE! cue rides the miss colour.
        if feedback == "F" or feedback == "MOVE!" then
            color = db.practice_result_color_miss or RESULT_COLOR_MISS
        else
            color = db.practice_result_color_hit or RESULT_COLOR_HIT
        end
    elseif feedback == "TWIST!" then
        color = db.practice_result_color_hit or RESULT_COLOR_HIT
    else
        color = db.practice_result_color_miss or RESULT_COLOR_MISS
    end
    result.text:SetText(feedback)
    result.text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    ui.result_duration = db.practice_result_duration or 0.8
    ui.result_remaining = ui.result_duration
    result:SetAlpha(1)
end

-- Archive fade (sim_update 3290-3301): full alpha until the last 0.3 s of the timer,
-- then a linear fade over that window.
function ui.update_result_fade(elapsed)
    if not ui.result_remaining or ui.result_remaining <= 0 then
        return
    end
    ui.result_remaining = ui.result_remaining - (elapsed or 0)
    local result = ui.result_frame
    if not result then
        return
    end
    if ui.result_remaining <= 0 then
        ui.result_remaining = 0
        result:SetAlpha(0)
    elseif ui.result_remaining < RESULT_FADE_SECONDS then
        result:SetAlpha(ui.result_remaining / RESULT_FADE_SECONDS)
    else
        result:SetAlpha(1)
    end
end

function ui.update_result_font(self)
    local result = ui.result_frame
    if not result then
        return
    end
    if type(result.text) ~= "table" then
        return
    end
    apply_result_font(result.text, self)
end

--=========================================================================================
-- Practice scoring: running session score + persistent personal bests
--=========================================================================================
-- Bests live in the addon's own class profile table (db.practice_bests, next to the
-- other practice_* keys this module already reads): AceDB persists the profile table
-- to SavedVariables, so no new options and no defaults entries are needed. Reads are
-- nil-safe (a fresh profile has no bests yet); writes never touch tables outside the
-- addon's own db. Practice stays paladin-only: the score accumulates twist attempts,
-- and only the paladin twist sim produces those.
function ui.load_bests(self)
    self = self or ST
    ui.bests = nil
    if not self.get_class_table then
        return
    end
    local db = self:get_class_table()
    local saved = db and db.practice_bests
    if type(saved) ~= "table" then
        return
    end
    ui.bests = {
        score = (type(saved.score) == "number") and saved.score or 0,
        hit_rate = (type(saved.hit_rate) == "number") and saved.hit_rate or 0,
        mean_error_ms = (type(saved.mean_error_ms) == "number")
            and saved.mean_error_ms or nil,
        grade = (type(saved.grade) == "string") and saved.grade or nil,
        attempts = (type(saved.attempts) == "number") and saved.attempts or 0,
    }
end

-- Persists personal bests when the session improved them: a higher session score
-- wins outright, an equal score with a tighter mean error wins the tiebreak, and the
-- best single-attempt grade rides along (rank-ordered, never downgrades). Fights with
-- no attempts save nothing. Only the addon's own class table is written.
function ui.maybe_save_bests(self)
    self = self or ST
    local pr = st.practice
    if not pr or not ui.score or not self.get_class_table then
        return
    end
    local summary = pr.score_summary(ui.score)
    if (summary.attempts or 0) == 0 then
        return
    end
    local db = self:get_class_table()
    if type(db) ~= "table" then
        return
    end
    local best = ui.bests
    local improved_score = false
    if not best then
        improved_score = true
    elseif summary.score > (best.score or 0) then
        improved_score = true
    elseif summary.score == (best.score or 0)
        and summary.mean_error_ms and best.mean_error_ms
        and summary.mean_error_ms < best.mean_error_ms then
        improved_score = true
    end
    local rank = pr.GRADE_RANK or {}
    local grade = best and best.grade or nil
    if summary.best_grade
        and (not grade or (rank[summary.best_grade] or 0) > (rank[grade] or 0)) then
        grade = summary.best_grade
    end
    local improved_grade = grade ~= (best and best.grade)
    if not improved_score and not improved_grade then
        return
    end
    local next_best = {
        score = improved_score and summary.score or (best and best.score or 0),
        hit_rate = improved_score and summary.hit_rate or (best and best.hit_rate or 0),
        mean_error_ms = improved_score and summary.mean_error_ms
            or (best and best.mean_error_ms),
        attempts = improved_score and summary.attempts or (best and best.attempts or 0),
        grade = grade,
    }
    ui.bests = next_best
    db.practice_bests = {
        score = next_best.score,
        hit_rate = next_best.hit_rate,
        mean_error_ms = next_best.mean_error_ms,
        attempts = next_best.attempts,
        grade = next_best.grade,
    }
end

-- "Best: 91 (S)" for the score line; "--" when no best is stored yet.
function ui.best_score_text()
    local best = ui.bests
    if not best or type(best.score) ~= "number" then
        return "--"
    end
    if best.grade then
        return string.format("%d (%s)", best.score, best.grade)
    end
    return tostring(best.score)
end

-- Repaints the panel score line: running score, hits/attempts, mean timing error,
-- last grade and the persistent best. Reuses the panel frame; no new frames.
function ui.update_score(self)
    local panel = ui.panel
    if not panel or not panel.score_text then
        return
    end
    local pr = st.practice
    local text
    if pr and ui.score and (ui.score.attempts or 0) > 0 then
        local summary = pr.score_summary(ui.score)
        local err = (summary.mean_error_ms ~= nil)
            and string.format("%dms", math.floor(summary.mean_error_ms + 0.5)) or "--"
        text = string.format("Score %d %d/%d %s %s Best %s",
            summary.score, summary.hits, summary.attempts, err,
            summary.last_grade or "-", ui.best_score_text())
    else
        local best = ui.best_score_text()
        text = (best ~= "--") and ("Score -- Best " .. best) or "Score --"
    end
    if text ~= ui.last_score_text then
        ui.last_score_text = text
        panel.score_text:SetText(text)
    end
end

--=========================================================================================
-- Session resource pools (sim-resources lane)
--=========================================================================================
-- Explicit, test-driven, dormant by default. Nothing in start() creates a pool
-- (activation with live damage/cost feeds belongs to the class-shell lane);
-- a nil pool runs every path below exactly as before (unknown-hides). The
-- display shows the first active pool in rage > mana > focus order and hides
-- otherwise, so sessions without a pool see no change.
function ui.set_session_rage_pool(self, opts)
    local pr = st.practice
    if not pr or type(pr.new_rage_state) ~= "function" then
        return nil
    end
    opts = opts or {}
    ui.rage_pool = pr.new_rage_state(opts)
    ui.drill_white_damage = opts.white_damage
    ui.drill_level = opts.level
    ui.update_resource_display(self)
    return ui.rage_pool
end

function ui.set_session_mana_pool(self, max, costs)
    local pr = st.practice
    if not pr or type(pr.new_mana_state) ~= "function" then
        return nil
    end
    ui.mana_pool = pr.new_mana_state({ max = max })
    ui.mana_costs = costs
    ui.update_resource_display(self)
    return ui.mana_pool
end

function ui.set_session_focus_pool(self, max)
    local pr = st.practice
    if not pr or type(pr.new_focus_state) ~= "function" then
        return nil
    end
    ui.focus_pool = pr.new_focus_state({ max = max })
    ui.update_resource_display(self)
    return ui.focus_pool
end

-- Clear every session pool (stop() runs this; sessions begin pool-less).
function ui.clear_session_pools(self)
    ui.rage_pool = nil
    ui.mana_pool = nil
    ui.focus_pool = nil
    ui.drill_white_damage = nil
    ui.drill_level = nil
    ui.mana_costs = nil
    ui.last_resource_text = nil
    ui.update_resource_display(self)
end

-- Paint the resource line for the active pool, or hide it when no pool is
-- active or readable. Nil-safe: no panel or no pool reads as empty.
function ui.update_resource_display(self)
    local panel = ui.panel
    if not panel or not panel.resource_text then
        return
    end
    local text = ""
    local kind, amount, max
    if type(ui.rage_pool) == "table" then
        kind, amount, max = "Rage", ui.rage_pool.rage, ui.rage_pool.max
    elseif type(ui.mana_pool) == "table" then
        kind, amount, max = "Mana", ui.mana_pool.mana, ui.mana_pool.max
    elseif type(ui.focus_pool) == "table" then
        kind, amount, max = "Focus", ui.focus_pool.focus, ui.focus_pool.max
    end
    if kind and type(amount) == "number" and amount == amount then
        if type(max) == "number" and max == max then
            text = string.format("%s: %d/%d", kind, math.floor(amount), math.floor(max))
        else
            text = string.format("%s: %d", kind, math.floor(amount))
        end
    end
    if text ~= ui.last_resource_text then
        ui.last_resource_text = text
        panel.resource_text:SetText(text)
        if text == "" then
            panel.resource_text:Hide()
        else
            panel.resource_text:Show()
        end
    end
end

--=========================================================================================
-- Panel position
--=========================================================================================
-- Re-anchors the panel (and the result popup) from the saved offsets; the offsets are
-- added to the archive's 8 px default gap so the defaults (0, 0) reproduce the archive
-- layout exactly. Never runs during combat lockdown: a deferred apply waits for the
-- driver tick.
function ui.apply_settings(self)
    self = self or ST
    local panel = ui.panel
    if not panel then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        ui.pending_apply = true
        return
    end
    ui.pending_apply = false
    local db = self:get_class_table()
    -- Nil-safe: a session with no class profile row anchors at the archive
    -- default instead of throwing out of start.
    if type(db) ~= "table" then
        db = {}
    end
    anchor_to_mainhand_bar(self, panel, "TOPLEFT", "TOPRIGHT",
        (db.practice_panel_x or 0) + PANEL_ANCHOR_GAP, db.practice_panel_y or 0)
    if ui.result_frame then
        anchor_to_mainhand_bar(self, ui.result_frame, "BOTTOM", "TOP", 0, 8)
    end
end

-- Stores the dragged position as offsets from the bar's top-right corner (the panel is
-- a UIParent child with scale 1 and the bar defaults to scale 1; a rescaled bar only
-- affects where a stored offset lands, never the frame maths).
function ui.save_position(self)
    local panel = ui.panel
    local bar = self:get_bar_frame("mainhand")
    if not panel or not bar then
        return
    end
    local left, top = panel:GetLeft(), panel:GetTop()
    local bar_right, bar_top = bar:GetRight(), bar:GetTop()
    if not (left and top and bar_right and bar_top) then
        return
    end
    local db = self:get_class_table()
    db.practice_panel_x = math.floor(left - bar_right - PANEL_ANCHOR_GAP + 0.5)
    db.practice_panel_y = math.floor(top - bar_top + 0.5)
    ui.apply_settings(self)
end

--=========================================================================================
-- Design-mode targets (C6 handoff)
--=========================================================================================
-- The practice UI's placeable elements, exposed in the designmode.lua registry descriptor
-- shape ({ key, title, get_frame, available, save(x, y), reset }) so the design-mode lane
-- can register them without reaching into this module's internals:
--   * practice_panel    - the control panel; its offsets persist through the existing
--                         practice_panel_x/practice_panel_y keys (save_position owns the
--                         maths), reset restores the 0/0 archive layout.
--   * practice_rotation - the centre-screen rotation display; position is session-local
--                         (ui.rot_x/rot_y, no db keys in this lane), so save/reset only
--                         move the live frame for the session.
--   * practice_timeline - the fight timeline; position is session-local too
--                         (ui.timeline_x/timeline_y), defaults CENTER + 0, -200.
--   * practice_hunter_report - the hunter post-fight shot report; position is
--                         session-local (no db keys in this lane), so save/reset
--                         only move the live frame. Available while the report is
--                         shown (the report is session-independent).
--   * practice_warrior_report - the warrior Execute report; same session-local
--                         shape, available while shown.
-- get_frame returns nil before init / before the frame exists, and available() is true
-- only while a session runs - the design-mode refresh skips both silently.
ui.design_targets = {
    {
        key = "practice_panel",
        title = "Practice panel",
        get_frame = function() return ui.panel end,
        available = function() return ui.is_active() end,
        save = function(x, y)
            local panel = ui.panel
            if not panel then
                return
            end
            panel:ClearAllPoints()
            panel:SetPoint("CENTER", UIParent, "CENTER", x, y)
            ui.save_position(ST)
        end,
        reset = function()
            local db = ST:get_class_table()
            if type(db) == "table" then
                db.practice_panel_x = 0
                db.practice_panel_y = 0
            end
            ui.apply_settings(ST)
        end,
    },
    {
        key = "practice_rotation",
        title = "Practice rotation display",
        get_frame = function() return ui.rotation_display end,
        available = function() return ui.is_active() end,
        save = function(x, y)
            local frame = ui.rotation_display
            if not frame then
                return
            end
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
            ui.save_rotation_position(ST)
        end,
        reset = function()
            ui.rot_x = ROT_DISPLAY_DEFAULT_X
            ui.rot_y = ROT_DISPLAY_DEFAULT_Y
            local frame = ui.rotation_display
            if frame then
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", ui.rot_x, ui.rot_y)
            end
        end,
    },
    {
        key = "practice_timeline",
        title = "Practice timeline",
        get_frame = function() return ui.timeline_frame end,
        available = function() return ui.is_active() end,
        save = function(x, y)
            local frame = ui.timeline_frame
            if not frame then
                return
            end
            ui.timeline_x = math.floor(x + 0.5)
            ui.timeline_y = math.floor(y + 0.5)
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", ui.timeline_x, ui.timeline_y)
        end,
        reset = function()
            ui.timeline_x = TIMELINE_DEFAULT_X
            ui.timeline_y = TIMELINE_DEFAULT_Y
            local frame = ui.timeline_frame
            if frame then
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", ui.timeline_x, ui.timeline_y)
            end
        end,
    },
    {
        key = "practice_hunter_report",
        title = "Hunter shot report",
        get_frame = function() return ui.hunter_report_frame end,
        available = function() return ui.hunter_report_visible == true end,
        save = function(x, y)
            local frame = ui.hunter_report_frame
            if not frame then
                return
            end
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end,
        reset = function()
            local frame = ui.hunter_report_frame
            if frame then
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            end
        end,
    },
    {
        key = "practice_warrior_report",
        title = "Warrior Execute report",
        get_frame = function() return ui.warrior_execute_report_frame end,
        available = function() return ui.warrior_execute_report_visible == true end,
        save = function(x, y)
            local frame = ui.warrior_execute_report_frame
            if not frame then
                return
            end
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end,
        reset = function()
            local frame = ui.warrior_execute_report_frame
            if frame then
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            end
        end,
    },
}

--=========================================================================================
-- Hunter post-fight shot report (H2, competitor_gaps)
--=========================================================================================
-- The practice-report screen for the hunter shot log (classes/hunter.lua gathers, the
-- practice.lua summarize/shot_hint math above scores). Standalone by design: it reads
-- the live hunter log, not the paladin sim, so it needs no session and no panel -
-- toggle it after a fight and it renders the rolling last-N shots. Hidden by default
-- (no default-visible change); stop_fight re-renders it when visible so the numbers
-- are final. Nil-safe throughout: no frame, no engine or no hunter log renders
-- nothing (an explicit empty-log hint when the user opened the screen).
local HUNTER_REPORT_WIDTH = 260
local HUNTER_REPORT_TEXT_WIDTH = 236

-- Builds the report frame on first use (UIParent only; never the panel, so hunters
-- without a practice session still get the screen). The owner is unused: the frame
-- needs no addon state, and the session-independent toggle passes ST through.
function ui.build_hunter_report(self)
    if ui.hunter_report_frame then
        return
    end
    -- Frames are only ever created out of combat (CreateFrame under lockdown
    -- risks taint): the toggle below reports the refusal instead.
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local frame = CreateFrame("Frame", addon_name .. "HunterShotReport", UIParent,
        "BackdropTemplate")
    frame:SetSize(HUNTER_REPORT_WIDTH, 110)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -6)
    frame.title:SetFontObject(GameFontNormal)
    frame.title:SetText("Shot Report")

    frame.summary_text = frame:CreateFontString(nil, "OVERLAY")
    frame.summary_text:SetPoint("TOP", frame, "TOP", 0, -24)
    frame.summary_text:SetWidth(HUNTER_REPORT_TEXT_WIDTH)
    frame.summary_text:SetFontObject(GameFontHighlightSmall)
    frame.summary_text:SetText("")

    frame.hint_text = frame:CreateFontString(nil, "OVERLAY")
    frame.hint_text:SetPoint("TOP", frame, "TOP", 0, -42)
    frame.hint_text:SetWidth(HUNTER_REPORT_TEXT_WIDTH)
    frame.hint_text:SetWordWrap(true)
    st.utils.apply_font(frame.hint_text, STANDARD_TEXT_FONT, 10, "")
    frame.hint_text:SetTextColor(0.8, 0.8, 0.8, 1)
    frame.hint_text:SetText("")

    frame:Hide()
    ui.hunter_report_frame = frame
    ui.hunter_report_visible = false
end

-- Renders the rolling last-N shots into the report frame. The live cast window for
-- the buffer clause is base + observed mean through the hunter_window kernel when it
-- is loaded; nil omits the clause.
function ui.render_hunter_report(self)
    self = self or ST
    local frame = ui.hunter_report_frame
    local pr = st.practice
    if not frame or not pr then
        return
    end
    local log
    if self.HUNTER and type(self.HUNTER.hunter_shot_log) == "table" then
        log = self.HUNTER.hunter_shot_log
    end
    local summary = pr.summarize_shots(log or {}, nil)
    local window
    local hw = st.hunter_window
    if hw and hw.cast_window and type(summary.mean_latency) == "number" then
        window = hw.cast_window(summary.mean_latency)
    end
    local head = string.format("Shots: %d (%d clipped, %d%%)", summary.total,
        summary.clipped, math.floor(summary.clip_rate * 100 + 0.5))
    if frame.summary_text then
        frame.summary_text:SetText(head)
    end
    if frame.hint_text then
        frame.hint_text:SetText(pr.shot_hint(summary, window))
    end
end

-- Shows (building and rendering first) or hides the report. Session-independent: safe
-- before init and without a running fight. Building under combat lockdown is
-- refused (no frame to show); hiding still works.
function ui.toggle_hunter_report(self)
    self = self or ST
    ui.build_hunter_report(self)
    if not ui.hunter_report_frame then
        if InCombatLockdown and InCombatLockdown() then
            self:Print("The shot report cannot be opened in combat.")
        end
        return
    end
    if ui.hunter_report_visible then
        ui.hunter_report_frame:Hide()
        ui.hunter_report_visible = false
    else
        ui.hunter_report_visible = true
        ui.render_hunter_report(self)
        ui.hunter_report_frame:Show()
    end
end

--=========================================================================================
-- Warrior Execute report (W6, competitor_gaps)
--=========================================================================================
-- The practice-report screen for the warrior Execute log (classes/warrior.lua
-- gathers, warrior_guide.lua summarize/execute_hint score it). Standalone by
-- design, mirroring the hunter shot report above: it reads the live warrior
-- log, not the twist sim, so it needs no session and no panel - toggle it after
-- a fight and it renders the rolling last-N entries. Hidden by default (no
-- default-visible change); stop_fight re-renders it when visible so the numbers
-- are final. Nil-safe throughout: no frame, no guide module or no warrior log
-- renders nothing (an explicit empty-log hint when the owner opened the screen).
local WARRIOR_EXECUTE_REPORT_WIDTH = 260
local WARRIOR_EXECUTE_REPORT_TEXT_WIDTH = 236

-- Builds the report frame on first use (UIParent only; never the panel, so
-- warriors without a practice session still get the screen). The owner is
-- unused: the frame needs no addon state, and the session-independent toggle
-- passes ST through.
function ui.build_warrior_execute_report(self)
    if ui.warrior_execute_report_frame then
        return
    end
    -- Frames are only ever created out of combat (CreateFrame under lockdown
    -- risks taint): the toggle below reports the refusal instead.
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local frame = CreateFrame("Frame", addon_name .. "WarriorExecuteReport", UIParent,
        "BackdropTemplate")
    frame:SetSize(WARRIOR_EXECUTE_REPORT_WIDTH, 110)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -6)
    frame.title:SetFontObject(GameFontNormal)
    frame.title:SetText("Execute Report")

    frame.summary_text = frame:CreateFontString(nil, "OVERLAY")
    frame.summary_text:SetPoint("TOP", frame, "TOP", 0, -24)
    frame.summary_text:SetWidth(WARRIOR_EXECUTE_REPORT_TEXT_WIDTH)
    frame.summary_text:SetFontObject(GameFontHighlightSmall)
    frame.summary_text:SetText("")

    frame.hint_text = frame:CreateFontString(nil, "OVERLAY")
    frame.hint_text:SetPoint("TOP", frame, "TOP", 0, -42)
    frame.hint_text:SetWidth(WARRIOR_EXECUTE_REPORT_TEXT_WIDTH)
    frame.hint_text:SetWordWrap(true)
    st.utils.apply_font(frame.hint_text, STANDARD_TEXT_FONT, 10, "")
    frame.hint_text:SetTextColor(0.8, 0.8, 0.8, 1)
    frame.hint_text:SetText("")

    frame:Hide()
    ui.warrior_execute_report_frame = frame
    ui.warrior_execute_report_visible = false
end

-- Renders the rolling last-N entries into the report frame.
function ui.render_warrior_execute_report(self)
    self = self or ST
    local frame = ui.warrior_execute_report_frame
    if not frame then
        return
    end
    local guide = st.warrior_guide
    if not guide or not guide.summarize_execute then
        return
    end
    local log
    if self.WARRIOR and type(self.WARRIOR.warrior_execute_log) == "table" then
        log = self.WARRIOR.warrior_execute_log
    end
    local summary = guide.summarize_execute(log or {}, nil)
    local head
    if type(summary.mean_rage) == "number" then
        head = string.format("Entries: %d (mean rage %d)", summary.total,
            math.floor(summary.mean_rage + 0.5))
    else
        head = string.format("Entries: %d (mean rage --)", summary.total)
    end
    if frame.summary_text then
        frame.summary_text:SetText(head)
    end
    if frame.hint_text and guide.execute_hint then
        frame.hint_text:SetText(guide.execute_hint(summary))
    end
end

-- Shows (building and rendering first) or hides the report. Session-independent:
-- safe before init and without a running fight. Building under combat lockdown
-- is refused (no frame to show); hiding still works.
function ui.toggle_warrior_execute_report(self)
    self = self or ST
    ui.build_warrior_execute_report(self)
    if not ui.warrior_execute_report_frame then
        if InCombatLockdown and InCombatLockdown() then
            self:Print("The Execute report cannot be opened in combat.")
        end
        return
    end
    if ui.warrior_execute_report_visible then
        ui.warrior_execute_report_frame:Hide()
        ui.warrior_execute_report_visible = false
    else
        ui.warrior_execute_report_visible = true
        ui.render_warrior_execute_report(self)
        ui.warrior_execute_report_frame:Show()
    end
end

if st.debug then st.utils.print_msg('-- Parsed practice_ui.lua module correctly') end
