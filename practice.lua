--=========================================================================================
-- Twist Practice minigame: pure simulation engine (port phase 1 - no WoW API, no frames).
--
-- Ported from the archived builds under docs/swedge/SwedgeTimer_Forever/practice.lua
-- (byte-identical to the *_TBC copy); reference lines:
--   * 72-127     sim state fields + rotation presets
--   * 132-146    ability definitions / order (stop included)
--   * 1342-1426  recalc_speed: rating + Bloodlust haste math, locked presets, swing rescale
--   * 1431-1458  determine_rotation thresholds (delegated to nextaction.lua)
--   * 3026-3094  sim_cast_seal (apply / dual-seal twist window / same-seal collapse)
--   * 3096-3174  sim_cast_ability (cooldowns; judgement requires and consumes all seals)
--   * 3176-3213  sim_cast_buff (Avenging Wrath only; the AW combos are deferred)
--   * 3218-3247  start_sim_gcd
--   * 3252-3279  process_spell_queue (a queued ability fires when the GCD ends)
--   * 3284-3425  sim_update (tick: seal fade, buff expiries, BL auto-fire, swing completion)
--   * 3430-3531  sim_on_swing (twist grading, older-seal consume)
--   * 4201-4227  sim_stopattack / sim_startattack (pause / resume)
--   * 1669-1878  swing grading: classify / CS segment patterns / evaluate / analyze
--
-- The module is deliberately PURE (no WoW API, no addon-owned live state) so the whole
-- simulation can be unit-tested offline with tests/practice_state.lua. Every entry point
-- takes `now` explicitly; the caller owns the clock (in game: st.api.get_time()).
--
-- Caller contract (phase 2 builds against this):
--   * sim = st.practice.new_sim(). Call apply_haste(sim, base_speed, now) at fight start,
--     after begin_fight/end_fight, and whenever tick reports out.buffs_changed or
--     out.bl_fired (the engine cannot re-derive speed without the base weapon speed).
--   * begin_fight(sim, now, { bl_delay = d, locked_rotation = key }) starts the fight and
--     the first swing at the CURRENT effective_speed (like the archive's start_fight);
--     call apply_haste after it so an immediate Bloodlust rescales the swing. A delay of
--     0 Bloodlusts immediately (unless locked); a positive delay fires from tick().
--   * per-frame: tick(sim, now, elapsed, out). On out.swing_ready the caller evaluates
--     on_swing(sim, now, out2), then calls start_swing(sim, now) to begin the next swing;
--     restarting the swing after a swing is deliberately the caller's job in phase 1.
--   * stopattack: cast(sim, "stop", now, out) or pause_attack(sim, now). Resume happens
--     either through cast() of a resume ability (cs/judge/sob/aw; out.resumed_attack) or
--     through resume_attack(sim, now, out). A held swing (out.held_swing) is immediately
--     due and resolves through the normal tick swing_ready path.
--   * the DST proc is caller-driven: gate it on your own enable setting and the rotation
--     lock, then call maybe_dst_proc(sim, now, math.random()) after on_swing.
--   * timeline: mirror out.timeline_event from on_swing into the caller's event array
--     (add the fight-relative time), then feed the whole array to analyze(events, count,
--     bands, band_count) at fight end. analyze() consumes events with key `seal_active`;
--     the on_swing payload carries both `seal` and `seal_active` so it can be passed
--     through directly once `time` has been added.
--   * moving cue strip (NEW, not an archive port): timeline_playhead_x / timeline_pps /
--     timeline_event_x / timeline_window / timeline_slice / timeline_cadence are the
--     pure geometry + schedule for the practice UI's playhead strip (fixed playhead,
--     upcoming actions approaching it). They are additive: the LOG path above is
--     unchanged and still feeds analyze().
--
-- Phase-1 sim additions beyond the archive's st.practice.sim fields (needed because the
-- archive kept this state in st.player / st.practice):
--   * swing_active / swing_ends_at   - the current swing (absolute end time in the
--     caller's clock domain); archive st.player.swing_timer.
--   * gcd_active / gcd_expires       - the simulated GCD window; archive st.player.
--     gcd_lockout + active_gcd_remaining.
--   * queue_window                   - spell-queue window seconds (archive db default 0.4).
--   * locked_rotation                - locked preset key set by begin_fight, read by
--     apply_haste (locked presets bypass all haste) and by cast() (locked blocks hpot and
--     abacus). NOT cleared by reset(): the archive keeps the lock as a practice setting.
--
-- Deferred to later phases (deliberately NOT simulated here):
--   * the AW combos practice_aw_includes_pot / practice_aw_includes_sob (archive 3198-3208;
--     needs new options, out of the practice lane's scope)
--   * UI side effects (sounds, glow, result text, timeline frame rendering, bar overlays)
--   * the in-real-combat scoring pause (archive sim_on_swing 3434-3441): the caller decides
--     whether to call on_swing while in real combat.
--
-- cast() out flags, all reset on every call: gcd_started, gcd_blocked (true whenever a
-- GCD rejected the cast, including when it was queued), queued, seal_changed (seal
-- applied, or seals consumed by judgement), twist_armed (twist_attempted set),
-- buff_changed, cooldown_set, resumed_attack, ignored (no-op cast), plus the phase-1
-- additions out.judged_seal ("command"|"blood"|nil; command wins) and out.held_swing.
--
-- tick() out flags: seal_faded, buffs_changed, bl_fired, swing_ready, attack_paused,
-- attack_resumed, fight_elapsed (fight clock running this tick), queue_ready (a queued
-- ability fired); when a queued ability fires, its cast() flags are merged into the same
-- out table.
--=========================================================================================
local addon_name, st = ...

st.practice = st.practice or {}

-- Seconds the older seal keeps twisting after a new seal is cast (archive sim_cast_seal).
st.practice.SEAL_FADE_SECONDS = 0.4

-- Ability definitions (archive 132-143, verbatim). "stop" is the stopattack action;
-- cast("stop") routes to pause_attack(). Seals have no cooldown; hpot/abacus have their
-- own activation rules; aw carries its buff duration.
st.practice.ABILITIES = {
    soc    = { name = "Seal of Command", spell_id = 20375, type = "seal", cooldown = 0, seal_label = "command" },
    sob    = { name = "Seal of Blood", spell_id = 31892, type = "seal", cooldown = 0, seal_label = "blood" },
    sotc   = { name = "Seal of the Crusader", spell_id = 21082, type = "seal", cooldown = 0, seal_label = "crusader" },
    cs     = { name = "Crusader Strike", spell_id = 35395, type = "ability", cooldown = 6 },
    judge  = { name = "Judgement", spell_id = 20271, type = "ability", cooldown = 8 },
    consec = { name = "Consecration", spell_id = 26573, type = "ability", cooldown = 8 },
    aw     = { name = "Avenging Wrath", spell_id = 31884, type = "buff", cooldown = 180, duration = 20 },
    hpot   = { name = "Haste Potion", spell_id = 28507, type = "haste_consumable", cooldown = 0, duration = 15 },
    abacus = { name = "Abacus of Violent Odds", spell_id = 33807, type = "haste_trinket", cooldown = 120, duration = 10 },
    stop   = { name = "Stop Attack", texture = "Interface\\Icons\\Ability_DualWield", type = "stopattack", cooldown = 0 },
}

-- UI/keybind order (archive 146).
st.practice.ABILITY_ORDER = { "soc", "sob", "cs", "judge", "sotc", "consec", "aw", "hpot", "abacus", "stop" }

-- Locked-rotation presets (archive 122-127): speed/gcd pairs that force a rotation via
-- determine_rotation(). While locked, apply_haste() uses these and ignores all haste.
st.practice.PRESETS = {
    ["1/2"] = { speed = 3.5, gcd = 1.5 },
    ["2/3"] = { speed = 2.3, gcd = 1.15 },
    ["2/4"] = { speed = 1.8, gcd = 1.15 },
}

-- Session-local default keybinds (archive reset_all_mappings 3952-3956): the practice
-- UI copies this into its own table at session start. Persistence (the archived
-- practice_key_* db keys) needs new options and is deliberately not wired here.
st.practice.DEFAULT_KEYBINDS = {
    soc = "1",
    sob = "2",
    cs = "3",
    judge = "4",
    sotc = "5",
    consec = "6",
    aw = "7",
    hpot = "8",
    abacus = "9",
    stop = "",
}

-- Timeline lane definitions (archive 148-160, minus the spell-id/texture lookups the
-- caller resolves: the pure engine only maps ability keys to lane keys).
st.practice.TIMELINE_LANES = {
    { key = "sob",    name = "SoB" },
    { key = "melee",  name = "Melee" },
    { key = "cs",     name = "CS" },
    { key = "consec", name = "Consec" },
    { key = "soc",    name = "SoC" },
    { key = "judge",  name = "Judge" },
}

st.practice.TIMELINE_LANE_INDEX = {
    sob = 1, melee = 2, cs = 3, consec = 4, soc = 5, judge = 6,
}

-- Seal label -> timeline lane (archive 160); crusader has no lane (never logged).
st.practice.SEAL_LABEL_TO_LANE = { blood = "sob", command = "soc" }

-- Melee swing icon (archive sim_on_swing 3457).
st.practice.MELEE_TEXTURE = "Interface\\Icons\\INV_Sword_04"

-- Human-readable labels for grading tooltips (archive 1682-1690).
st.practice.SWING_ACTION_LABELS = {
    blood_auto = "Seal of Blood auto",
    cmd_auto = "Seal of Command auto",
    twist = "Twist",
    no_seal = "Auto (no seal)",
    cs = "Crusader Strike + SoB auto",
    judge_blood = "Judge (Seal of Blood)",
    judge_command = "Judge (Seal of Command)",
}

-- Abbreviate a keybind string to max 3 characters for icon labels (archive
-- shorten_keybind 183-225, verbatim logic). Pure: no WoW API.
function st.practice.shorten_keybind(key)
    if not key or key == "" then return "" end

    local mods = ""
    local base = key
    if base:find("^CTRL%-") then
        mods = "C"; base = base:sub(6)
    end
    if base:find("^SHIFT%-") then
        mods = "S"; base = base:sub(7)
    end
    if base:find("^ALT%-") then
        mods = "A"; base = base:sub(5)
    end

    local np = base:match("^NUMPAD(.+)")
    if np then
        local np_map = {
            DECIMAL = ".", PLUS = "+", MINUS = "-", MULTIPLY = "*", DIVIDE = "/",
        }
        base = "N" .. (np_map[np] or np)
    end

    if base == "MOUSEWHEELUP" then
        base = "MU"
    elseif base == "MOUSEWHEELDOWN" then
        base = "MD"
    elseif base:match("^BUTTON(%d)") then
        base = "M" .. base:match("^BUTTON(%d)")
    end

    local pad_map = {
        PAD1 = "P1",
        PAD2 = "P2",
        PAD3 = "P3",
        PAD4 = "P4",
        PADLSHOULDER = "LB",
        PADRSHOULDER = "RB",
        PADLTRIGGER = "LT",
        PADRTRIGGER = "RT",
        PADLSTICK = "LS",
        PADRSTICK = "RS",
        PADDUP = "DU",
        PADDDOWN = "DD",
        PADDLEFT = "DL",
        PADDRIGHT = "DR",
        PADFORWARD = "FW",
        PADBACK = "BK",
        PADLSTICKUP = "LU",
        PADLSTICKDOWN = "LD",
        PADLSTICKLEFT = "LL",
        PADLSTICKRIGHT = "LR",
        PADRSTICKUP = "RU",
        PADRSTICKDOWN = "RD",
        PADRSTICKLEFT = "RL",
        PADRSTICKRIGHT = "RR",
    }
    if pad_map[base] then base = pad_map[base] end

    local result = mods .. base
    return result:sub(1, 3)
end

-- Fight clock label for the panel (archive sim_update 3393: "Fight: m:ss").
-- Negative inputs clamp to 0.
function st.practice.format_fight_time(elapsed)
    if type(elapsed) ~= "number" or elapsed < 0 then
        elapsed = 0
    end
    local mins = math.floor(elapsed / 60)
    local secs = math.floor(elapsed % 60)
    return string.format("Fight: %d:%02d", mins, secs)
end

-- Timeline lane for a cast ability (archive sim_cast_seal 3087-3093 +
-- sim_cast_ability 3165-3168): seals log on their seal lane, cs/judge/consec on
-- their own lane, everything else (aw/hpot/abacus/stop/sotc) logs nothing.
function st.practice.cast_timeline_lane(ability_key)
    if ability_key == "cs" or ability_key == "judge" or ability_key == "consec" then
        return ability_key
    end
    local ab = st.practice.ABILITIES[ability_key]
    if ab and ab.type == "seal" and st.practice.SEAL_LABEL_TO_LANE[ab.seal_label] then
        return st.practice.SEAL_LABEL_TO_LANE[ab.seal_label]
    end
    return nil
end

--=========================================================================================
-- Sim state
--=========================================================================================

-- Fresh simulation state (archive 72-117 field-for-field, plus the phase-1 additions
-- documented in the header). All times are in the caller's clock domain.
function st.practice.new_sim()
    return {
        active_seals = {},       -- [seal_label] = true
        n_active_seals = 0,
        seal_1_label = nil,      -- oldest seal (or only seal)
        seal_2_label = nil,      -- newest seal (during the twist window)
        fading_seal_label = nil, -- seal fading after a new seal was cast
        fading_seal_expires = 0,

        effective_speed = 3.5, -- weapon speed after haste
        effective_gcd = 1.5,   -- GCD after haste

        has_bloodlust = false,
        has_haste_pot = false,
        has_abacus = false,
        has_dst = false,
        bl_buff_expires = 0,
        haste_pot_buff_expires = 0,
        abacus_buff_expires = 0,
        abacus_cooldown_expires = 0,
        dst_buff_expires = 0,
        dst_icd_expires = 0,

        cs_cooldown_expires = 0,
        judge_cooldown_expires = 0,
        consec_cooldown_expires = 0,
        aw_cooldown_expires = 0,
        aw_buff_expires = 0,

        fight_active = false,
        fight_start_time = 0,
        fight_bl_delay = 0,
        fight_bl_fired = false,

        attack_paused = false,
        attack_pause_pending = false,
        swing_held = false,      -- swing completed during stopattack, held until resume

        twist_attempted = false, -- a seal swap armed a twist this swing cycle

        queued_ability = nil,
        queue_timestamp = 0,

        -- Phase-1 additions (see header).
        swing_active = false,
        swing_ends_at = 0,
        gcd_active = false,
        gcd_expires = 0,
        queue_window = 0.4,
        locked_rotation = nil,
    }
end

-- Reset the sim for a new practice session (archive reset_sim_state 1170-1229, which is
-- called when practice mode starts). Deliberate archive quirks preserved:
--   * effective_speed/effective_gcd and locked_rotation are NOT reset (practice-level
--     state; the caller re-runs apply_haste() / begin_fight()).
--   * has_abacus/abacus_* and has_dst/dst_* are NOT reset either (the archive clears them
--     through stop_fight -> deactivate_* instead; end_fight() mirrors that here).
function st.practice.reset(sim)
    sim.active_seals = {}
    sim.n_active_seals = 0
    sim.seal_1_label = nil
    sim.seal_2_label = nil
    sim.fading_seal_label = nil
    sim.fading_seal_expires = 0

    sim.has_bloodlust = false
    sim.has_haste_pot = false
    sim.bl_buff_expires = 0
    sim.haste_pot_buff_expires = 0

    sim.cs_cooldown_expires = 0
    sim.judge_cooldown_expires = 0
    sim.consec_cooldown_expires = 0
    sim.aw_cooldown_expires = 0
    sim.aw_buff_expires = 0

    sim.fight_active = false
    sim.fight_start_time = 0
    sim.fight_bl_delay = 0
    sim.fight_bl_fired = false

    sim.attack_paused = false
    sim.attack_pause_pending = false
    sim.swing_held = false
    sim.twist_attempted = false

    sim.queued_ability = nil
    sim.queue_timestamp = 0

    sim.swing_active = false
    sim.swing_ends_at = 0
    sim.gcd_active = false
    sim.gcd_expires = 0
end

--=========================================================================================
-- Haste / rotation
--=========================================================================================

-- Recalculate effective_speed / effective_gcd (archive recalc_speed 1342-1426).
--   * Locked rotation: the preset's speed/gcd win and every haste source is ignored.
--   * Otherwise: haste rating is additive (pot 400 + DST 325 + Abacus 260; 15.77 rating
--     per 1% at level 70); Bloodlust is a separate multiplicative category (/1.3); the
--     GCD floors at 1.0; both values round to 3 dp.
--   * A swing already in flight is capped to the new speed (remaining time may only
--     shrink), mirroring the archive's "swing_timer > speed -> swing_timer = speed".
-- base_speed nil or <= 0 falls back to 3.5 (the archive's UnitAttackSpeed fallback).
function st.practice.apply_haste(sim, base_speed, now)
    if sim.locked_rotation then
        local preset = st.practice.PRESETS[sim.locked_rotation]
        if preset then
            sim.effective_speed = preset.speed
            sim.effective_gcd = preset.gcd
            if sim.swing_active and (sim.swing_ends_at - now) > preset.speed then
                sim.swing_ends_at = now + preset.speed
            end
            return
        end
    end

    if type(base_speed) ~= "number" or base_speed <= 0 then
        base_speed = 3.5
    end

    local speed = base_speed
    local gcd = 1.5

    local total_haste_rating = 0
    if sim.has_haste_pot then total_haste_rating = total_haste_rating + 400 end
    if sim.has_dst then total_haste_rating = total_haste_rating + 325 end
    if sim.has_abacus then total_haste_rating = total_haste_rating + 260 end

    local haste_from_rating = total_haste_rating / 15.77 / 100
    speed = speed / (1 + haste_from_rating)
    gcd = gcd / (1 + haste_from_rating)

    if sim.has_bloodlust then
        speed = speed / 1.3
        gcd = gcd / 1.3
    end
    gcd = math.max(1.0, gcd)

    speed = math.floor(speed * 1000 + 0.5) / 1000
    gcd = math.floor(gcd * 1000 + 0.5) / 1000

    sim.effective_speed = speed
    sim.effective_gcd = gcd

    if sim.swing_active and (sim.swing_ends_at - now) > speed then
        sim.swing_ends_at = now + speed
    end
end

-- Rotation key for the current speed/GCD (archive determine_rotation 1431-1458).
-- The locked key wins; otherwise the thresholds live in nextaction.lua
-- (st.nextaction.calculate_rotation, the archived rotation.lua:140-172) so they are not
-- duplicated here. TOCs load nextaction.lua before practice.lua; the guard returns nil
-- only if the module is loaded without it.
function st.practice.determine_rotation(sim, locked_rotation)
    local locked = locked_rotation or sim.locked_rotation
    if locked then
        return locked
    end
    local na = st.nextaction
    if na and na.calculate_rotation then
        return na.calculate_rotation(sim.effective_speed, sim.effective_gcd)
    end
    return nil
end

-- Direct haste setters for the panel toggle buttons (archive activate/deactivate
-- 2592-2690, minus UI/sound). Unlike cast("hpot") these start no GCD, matching the
-- archive's button paths. Guarded against redundant activation (the original expiry
-- is kept); clearing is unconditional. The caller re-runs apply_haste() afterwards.
function st.practice.set_bloodlust(sim, now, on)
    if on then
        if sim.has_bloodlust then return false end
        if sim.locked_rotation then return false end
        sim.has_bloodlust = true
        sim.bl_buff_expires = now + 40
        return true
    end
    sim.has_bloodlust = false
    sim.bl_buff_expires = 0
    return true
end

function st.practice.set_haste_pot(sim, now, on)
    if on then
        if sim.has_haste_pot then return false end
        if sim.locked_rotation then return false end
        sim.has_haste_pot = true
        sim.haste_pot_buff_expires = now + 15
        return true
    end
    sim.has_haste_pot = false
    sim.haste_pot_buff_expires = 0
    return true
end

--=========================================================================================
-- Fight timeline data (pure; the frame rendering lives in practice_ui.lua)
--=========================================================================================

-- Append a timeline event (archive log_timeline_event 1881-1898): no-op while no
-- fight runs. `time` is fight-relative. Returns the new count.
function st.practice.push_timeline_event(events, count, sim, now, lane, texture, result, seal_active)
    if not sim.fight_active then
        return count
    end
    local next_count = (count or 0) + 1
    events[next_count] = {
        time = now - sim.fight_start_time,
        lane = lane,
        texture = texture,
        result = result,
        seal_active = seal_active,
    }
    return next_count
end

-- Latest event time (archive timeline_max_time, computed on demand).
function st.practice.timeline_max_time(events, count)
    local max_time = 0
    for i = 1, (count or 0) do
        local event = events[i]
        if event and event.time and event.time > max_time then
            max_time = event.time
        end
    end
    return max_time
end

--=========================================================================================
-- Moving practice timeline (pure geometry + schedule; the frames live in practice_ui.lua)
--=========================================================================================
-- The cue strip the operator asked for: a FIXED vertical playhead a quarter of the way
-- into the visible strip, and the upcoming actions scrolling right-to-left toward it.
-- An action's icon crosses the playhead at its `at` clock, which is the second the
-- drill wants it pressed. Everything here is arithmetic - no frames, no WoW API - so
-- the suites pin the maths without a client.

-- Where the playhead sits: a fraction of the strip's VISIBLE width.
st.practice.TL_PLAYHEAD_FRACTION = 0.25
-- How far ahead the strip looks, in seconds. Ten, not six: the operator's
-- reference strip shows ~13 s of clock with the playhead a quarter in (10 s to the
-- right), and the pixels-per-second follows the strip's screen width, so ten keeps
-- the cue speed of the reference at any width.
st.practice.TL_HORIZON_SECONDS = 10
-- The neutral cadence's fallback spacing: a class that publishes none of its own
-- PRACTICE_GCD_SECONDS / PRACTICE_CYCLE_SECONDS previews at these.
st.practice.TL_CADENCE_GCD = 1.5
st.practice.TL_CADENCE_CYCLE = 3.5

-- A fraction clamped to [0, 1]; a non-number reads the shipped default.
local function tl_fraction(value)
    value = tonumber(value) or st.practice.TL_PLAYHEAD_FRACTION
    if value < 0 then
        return 0
    elseif value > 1 then
        return 1
    end
    return value
end

-- The playhead's x inside the strip: `fraction` of the VISIBLE width. A zero/absent
-- width answers 0 (nothing to place against), never a guess.
function st.practice.timeline_playhead_x(width, fraction)
    width = tonumber(width) or 0
    if width < 0 then
        width = 0
    end
    return width * tl_fraction(fraction)
end

-- Pixels per second for a strip that shows `horizon` seconds to the RIGHT of the
-- playhead: the playhead is fixed, so the right part of the strip IS the horizon.
function st.practice.timeline_pps(width, fraction, horizon)
    width = tonumber(width) or 0
    horizon = tonumber(horizon) or st.practice.TL_HORIZON_SECONDS
    if width <= 0 or horizon <= 0 then
        return 0
    end
    local span = width * (1 - tl_fraction(fraction))
    if span <= 0 then
        return 0
    end
    return span / horizon
end

-- x of an event at the absolute clock `at`, seen at `now`: ahead of now sits to the
-- RIGHT of the playhead, a past event to the LEFT. Nil when either clock is unknown.
function st.practice.timeline_event_x(playhead_x, at, now, pps)
    at = tonumber(at)
    now = tonumber(now)
    if not at or not now then
        return nil
    end
    return (tonumber(playhead_x) or 0) + (at - now) * (tonumber(pps) or 0)
end

-- The absolute-clock window on screen, left edge .. right edge: `fraction` of the
-- width behind the playhead, the rest of the horizon ahead. A dead clock (pps <= 0)
-- collapses the window onto `now` (nothing can be placed).
function st.practice.timeline_window(now, width, pps, fraction)
    now = tonumber(now) or 0
    width = tonumber(width) or 0
    pps = tonumber(pps) or 0
    if pps <= 0 or width <= 0 then
        return now, now
    end
    fraction = tl_fraction(fraction)
    return now - (width * fraction) / pps, now + (width * (1 - fraction)) / pps
end

-- Index range of the ascending `events` that fall inside [from_at, to_at]; nil when
-- the window is empty. A pure read: no allocation, no re-order.
function st.practice.timeline_slice(events, count, from_at, to_at)
    if type(events) ~= "table" or type(from_at) ~= "number" or type(to_at) ~= "number" then
        return nil
    end
    local first, last
    for i = 1, (count or 0) do
        local event = events[i]
        local at = type(event) == "table" and event.at or nil
        if type(at) == "number" and at == at and at >= from_at and at <= to_at then
            first = first or i
            last = i
        end
    end
    return first, last
end

-- Is this rotation row a cue the preview may show? The class's OWN published fact:
-- a row the tree cannot read today (`live == false`) or the engine cannot ask for
-- (`engine == false`) is not a cue.
function st.practice.timeline_row_is_cue(row)
    return type(row) == "table" and row.live == true and row.engine == true
end

-- The neutral "rotation cadence (preview)" schedule: the class's own live+engine
-- rotation rows, one cue every `gcd`-ish second, walking the published list one
-- action per cue. `cycle` is the repeat length: a cycle carries round(cycle/gcd)
-- cues spread EVENLY over it (1.5 s GCD inside a 3.5 s cycle = two cues 1.75 s
-- apart), so the preview never bursts two cues half a GCD apart at a cycle
-- boundary and the cycle itself stays exact. Absolute times are anchored to
-- `anchor` (the fight/session start), so the cues MOVE as the clock advances
-- instead of being re-based on `now` every rebuild. `out` is reused slot-for-slot
-- (no per-tick allocation); the returned count is the truth, slots past it are
-- stale and must be ignored.
function st.practice.timeline_cadence(out, rotation, anchor, now, horizon, gcd, cycle)
    out = type(out) == "table" and out or {}
    local rows = type(rotation) == "table" and #rotation or 0
    if rows == 0 then
        return out, 0
    end
    now = tonumber(now) or 0
    horizon = tonumber(horizon) or st.practice.TL_HORIZON_SECONDS
    if horizon < 0 then
        horizon = 0
    end
    gcd = tonumber(gcd) or st.practice.TL_CADENCE_GCD
    if gcd <= 0 then
        gcd = st.practice.TL_CADENCE_GCD
    end
    cycle = tonumber(cycle) or st.practice.TL_CADENCE_CYCLE
    if cycle <= 0 then
        cycle = st.practice.TL_CADENCE_CYCLE
    end

    local limit = now + horizon
    local origin
    anchor = tonumber(anchor)
    if anchor and anchor == anchor then
        if anchor >= now then
            origin = anchor
        else
            -- the cycle containing `now`, so a long fight never walks every cycle
            origin = anchor + math.floor((now - anchor) / cycle) * cycle
        end
    else
        origin = now
    end

    local count = 0
    local index = 0
    local steps = math.floor(cycle / gcd + 0.5)
    if steps < 1 then
        steps = 1
    elseif steps > 64 then
        -- A pathological GCD/cycle pair (a class passing 0.01 s) cannot flood the
        -- schedule: at most 64 cues per cycle, which is already denser than the
        -- strip can draw.
        steps = 64
    end
    local step_gap = cycle / steps
    local cycle_start = origin
    local guard = 0
    while cycle_start <= limit and guard < 256 do
        guard = guard + 1
        for k = 0, steps - 1 do
            local at = cycle_start + k * step_gap
            if at > limit then
                break
            end
            -- advance to the next cue row (skipping rows the class does not offer)
            local row
            for step = 1, rows do
                local i = (index + step - 1) % rows + 1
                local candidate = rotation[i]
                if st.practice.timeline_row_is_cue(candidate) then
                    row = candidate
                    index = i
                    break
                end
            end
            if not row then
                break
            end
            if at >= now then
                count = count + 1
                local slot = out[count]
                if type(slot) ~= "table" then
                    slot = {}
                    out[count] = slot
                end
                slot.at = at
                slot.key = row.action
                slot.label = row.label or row.action
                slot.spell_id = row.spell_id
                -- A row may name its own lane; otherwise the lane is the one the
                -- sim's own event log uses for that action (cast_timeline_lane),
                -- so the preview lands on the same rail as the recorded fight.
                slot.lane = row.lane or st.practice.cast_timeline_lane(row.action)
                slot.texture = nil
            end
        end
        cycle_start = cycle_start + cycle
    end
    return out, count
end

-- Opening rotation band for a fight (archive start_fight 2866-2876): one band at
-- time 0 when the rotation resolves, none when it does not.
function st.practice.bands_for_fight(rotation)
    if not rotation then
        return {}, 0
    end
    return { { start_time = 0, rotation = rotation } }, 1
end

-- Record a rotation change as a timeline band (archive update_rotation_tracking
-- 1557-1579, minus the display/HUD half which lives in practice_ui.lua). Appends
-- only when the rotation differs from the last band. Returns the new band count.
function st.practice.track_rotation_band(bands, band_count, rotation, fight_time)
    if not rotation then
        return band_count
    end
    band_count = band_count or 0
    local last = bands[band_count]
    if last and last.rotation == rotation then
        return band_count
    end
    local next_count = band_count + 1
    bands[next_count] = { start_time = fight_time, rotation = rotation }
    return next_count
end

--=========================================================================================
-- Fight lifecycle
--=========================================================================================

-- Start a fresh swing: it completes after the current effective_speed (the archive's
-- st.player.reset_swing_timer is called by start_fight and sim_startattack).
function st.practice.start_swing(sim, now)
    sim.swing_active = true
    sim.swing_ends_at = now + sim.effective_speed
end

-- Begin a boss fight (archive start_fight 2807-2889). Starts with Seal of Blood, starts
-- the swing, and fires Bloodlust immediately when bl_delay is 0 and the rotation is not
-- locked. The caller should apply_haste() afterwards (Bloodlust changes the speed), and
-- must call end_fight() before starting another fight.
function st.practice.begin_fight(sim, now, opts)
    if sim.fight_active then return end
    opts = opts or {}

    sim.fight_active = true
    sim.fight_start_time = now
    sim.fight_bl_delay = opts.bl_delay or 0
    -- A stop-and-restart inside a swap fade window must not leak the pending twist into
    -- the next fight (the first swing would grade a spurious MISS).
    sim.twist_attempted = false
    -- A locked rotation survives across fights (archive keeps the lock): only an explicit
    -- non-nil argument changes it, so an empty opts table cannot silently clear it.
    if opts.locked_rotation ~= nil then
        sim.locked_rotation = opts.locked_rotation
    end

    if sim.locked_rotation then
        sim.fight_bl_fired = true -- locked rotations never auto-Bloodlust
    else
        sim.fight_bl_fired = false
    end

    sim.attack_paused = false
    sim.attack_pause_pending = false
    sim.queued_ability = nil
    sim.queue_timestamp = 0

    sim.active_seals = {}
    sim.active_seals["blood"] = true
    sim.n_active_seals = 1
    sim.seal_1_label = "blood"
    sim.seal_2_label = nil
    sim.fading_seal_label = nil
    sim.fading_seal_expires = 0

    st.practice.start_swing(sim, now)

    if not sim.locked_rotation and sim.fight_bl_delay == 0 then
        sim.fight_bl_fired = true
        sim.has_bloodlust = true
        sim.bl_buff_expires = now + 40
    end
end

-- End the fight (archive stop_fight 2891-2953): clears the queue, attack/pause state,
-- timed buffs (Bloodlust/pot/Abacus/DST) and all cooldowns. locked_rotation persists.
-- The caller must apply_haste() afterwards to re-derive speed/GCD.
function st.practice.end_fight(sim)
    if not sim.fight_active then return end

    sim.queued_ability = nil
    sim.queue_timestamp = 0
    sim.fight_active = false
    sim.fight_start_time = 0
    sim.fight_bl_delay = 0
    sim.fight_bl_fired = false
    sim.attack_paused = false
    sim.attack_pause_pending = false
    sim.swing_held = false
    sim.swing_active = false
    sim.swing_ends_at = 0

    sim.has_bloodlust = false
    sim.bl_buff_expires = 0
    sim.has_haste_pot = false
    sim.haste_pot_buff_expires = 0
    sim.has_abacus = false
    sim.abacus_buff_expires = 0
    sim.has_dst = false
    sim.dst_buff_expires = 0

    sim.cs_cooldown_expires = 0
    sim.judge_cooldown_expires = 0
    sim.consec_cooldown_expires = 0
    sim.aw_cooldown_expires = 0
    sim.aw_buff_expires = 0
    sim.abacus_cooldown_expires = 0
    sim.dst_icd_expires = 0
end

--=========================================================================================
-- Simulated cast
--=========================================================================================

-- Abilities that resume the attack out of a stopattack pause (archive 335).
local RESUME_ABILITIES = { cs = true, judge = true, sob = true, aw = true }

-- Cast a simulated ability (archive sim_cast 2958-3024 + the per-type bodies below).
-- See the header for the full out-flag contract. "stop" routes to pause_attack().
function st.practice.cast(sim, ability_key, now, out)
    out.gcd_started = false
    out.gcd_blocked = false
    out.queued = false
    out.seal_changed = false
    out.twist_armed = false
    out.buff_changed = false
    out.cooldown_set = false
    out.resumed_attack = false
    out.ignored = false
    out.judged_seal = nil
    out.held_swing = nil

    local ab = st.practice.ABILITIES[ability_key]
    if not ab then
        out.ignored = true
        return out
    end

    if ability_key == "stop" then
        st.practice.pause_attack(sim, now)
        return out
    end

    -- GCD gate (archive 2972-2983): Judgement, AW and the trinket are off-GCD.
    if ability_key ~= "judge" and ab.type ~= "buff" and ab.type ~= "haste_trinket" then
        local remaining = sim.gcd_expires - now
        if sim.gcd_active and remaining > 0 then
            local queue_window = sim.queue_window or 0.4
            if queue_window > 0 and remaining <= queue_window then
                sim.queued_ability = ability_key
                sim.queue_timestamp = now
                out.queued = true
            end
            out.gcd_blocked = true
            return out
        end
    end

    -- Resume from stopattack (archive 2985-2996). A same-seal press swaps to the opposite
    -- seal first so the cast below arms a twist.
    if (sim.attack_paused or sim.attack_pause_pending) and RESUME_ABILITIES[ability_key] then
        if ab.type == "seal" and sim.n_active_seals == 1 and sim.seal_1_label == ab.seal_label then
            local opposite = ab.seal_label == "blood" and "command" or "blood"
            sim.active_seals = {}
            sim.active_seals[opposite] = true
            sim.seal_1_label = opposite
        end
        st.practice.resume_attack(sim, now, out)
    end

    if ab.type == "seal" then
        -- Seal apply / swap (archive sim_cast_seal 3026-3094).
        local seal_label = ab.seal_label
        if sim.n_active_seals > 0 then
            local old_label = sim.seal_1_label
            if old_label and old_label ~= seal_label then
                -- Dual-seal twist window: the older seal fades after SEAL_FADE_SECONDS.
                sim.fading_seal_label = old_label
                sim.fading_seal_expires = now + st.practice.SEAL_FADE_SECONDS
                sim.twist_attempted = true
                sim.active_seals = {}
                sim.active_seals[old_label] = true
                sim.active_seals[seal_label] = true
                sim.n_active_seals = 2
                sim.seal_1_label = old_label
                sim.seal_2_label = seal_label
                out.twist_armed = true
            else
                -- Same seal recast: collapse to the single seal.
                sim.active_seals = {}
                sim.active_seals[seal_label] = true
                sim.n_active_seals = 1
                sim.seal_1_label = seal_label
                sim.seal_2_label = nil
                sim.fading_seal_label = nil
                sim.fading_seal_expires = 0
            end
        else
            sim.active_seals = {}
            sim.active_seals[seal_label] = true
            sim.n_active_seals = 1
            sim.seal_1_label = seal_label
            sim.seal_2_label = nil
        end
        out.seal_changed = true
        sim.gcd_active = true
        sim.gcd_expires = now + sim.effective_gcd
        out.gcd_started = true
        return out
    end

    if ab.type == "ability" then
        -- Cooldown-gated abilities (archive sim_cast_ability 3096-3174).
        local cd_key = ability_key .. "_cooldown_expires"
        if sim[cd_key] and sim[cd_key] > now then
            out.ignored = true
            return out
        end

        if ability_key == "judge" then
            if sim.n_active_seals == 0 then
                out.ignored = true
                return out
            end
            -- Capture the judged seal before consuming (command wins), then consume all.
            if sim.active_seals["command"] then
                out.judged_seal = "command"
            elseif sim.active_seals["blood"] then
                out.judged_seal = "blood"
            end
            sim.active_seals = {}
            sim.n_active_seals = 0
            sim.seal_1_label = nil
            sim.seal_2_label = nil
            sim.fading_seal_label = nil
            sim.fading_seal_expires = 0
            out.seal_changed = true
        end

        if ab.cooldown > 0 then
            sim[cd_key] = now + ab.cooldown
            out.cooldown_set = true
        end

        -- Judgement does not trigger the GCD; cs/consec do.
        if ability_key ~= "judge" then
            sim.gcd_active = true
            sim.gcd_expires = now + sim.effective_gcd
            out.gcd_started = true
        end
        return out
    end

    if ab.type == "buff" then
        -- Off-GCD buffs (archive sim_cast_buff 3176-3213); only AW exists.
        local cd_key = ability_key .. "_cooldown_expires"
        if sim[cd_key] and sim[cd_key] > now then
            out.ignored = true
            return out
        end
        if ab.cooldown > 0 then
            sim[cd_key] = now + ab.cooldown
            out.cooldown_set = true
        end
        if ab.duration then
            sim.aw_buff_expires = now + ab.duration
            out.buff_changed = true
        end
        -- Deferred (archive 3198-3208): practice_aw_includes_pot and
        -- practice_aw_includes_sob combos are not simulated in phase 1.
        return out
    end

    if ab.type == "haste_consumable" then
        -- Haste potion: blocked while the rotation is locked; always starts a GCD, even
        -- on a redundant press while the buff is already up (archive 3004-3009 + 2654).
        if sim.locked_rotation then
            out.ignored = true
            return out
        end
        if not sim.has_haste_pot then
            sim.has_haste_pot = true
            sim.haste_pot_buff_expires = now + ab.duration
            out.buff_changed = true
        end
        sim.gcd_active = true
        sim.gcd_expires = now + sim.effective_gcd
        out.gcd_started = true
        return out
    end

    if ab.type == "haste_trinket" then
        -- Abacus: off-GCD, blocked while locked, 120 s cooldown, no refresh while up
        -- (archive 3010-3019 + 2692-2705).
        if sim.locked_rotation then
            out.ignored = true
            return out
        end
        local cd_key = ability_key .. "_cooldown_expires"
        if sim[cd_key] and sim[cd_key] > now then
            out.ignored = true
            return out
        end
        if not sim.has_abacus then
            sim.has_abacus = true
            sim.abacus_buff_expires = now + ab.duration
            sim.abacus_cooldown_expires = now + ab.cooldown
            out.buff_changed = true
            out.cooldown_set = true
        else
            out.ignored = true
        end
        return out
    end

    return out
end

--=========================================================================================
-- Stopattack pause / resume
--=========================================================================================

-- Stop attacking (archive sim_stopattack 4201-4213): clears the queue; pauses immediately
-- when no swing is in flight, otherwise lets the current swing finish and holds it.
function st.practice.pause_attack(sim, now)
    if not sim.fight_active or sim.attack_paused or sim.attack_pause_pending then return end
    sim.queued_ability = nil
    sim.queue_timestamp = 0
    if not sim.swing_active then
        -- Swing already completed and pending: pause immediately (no held swing).
        sim.attack_paused = true
        return
    end
    sim.attack_pause_pending = true
end

-- Shared resume body (archive sim_startattack 4215-4227): clears the pause flags; a held
-- swing becomes immediately due (tick reports swing_ready for it), otherwise a fresh
-- swing starts at the current effective_speed.
local function resume_attack_internal(sim, now, out)
    local held = sim.swing_held
    sim.attack_paused = false
    sim.attack_pause_pending = false
    sim.swing_held = false
    out.held_swing = held and true or false
    if held then
        sim.swing_active = true
        sim.swing_ends_at = now
    else
        st.practice.start_swing(sim, now)
    end
end

-- Resume the attack (always resumes + starts/releases a swing, like sim_startattack).
-- out.resumed_attack is always true; out.held_swing is true when a held swing was
-- released (immediately due) and false otherwise.
function st.practice.resume_attack(sim, now, out)
    resume_attack_internal(sim, now, out)
    out.resumed_attack = true
    return out
end

--=========================================================================================
-- Per-frame tick
--=========================================================================================

-- Advance the simulation (archive sim_update 3284-3425 + process_spell_queue 3252-3279).
-- `elapsed` is accepted for call-site parity with the archive's frame delta but the
-- simulation is driven by absolute `now` values. See the header for the out contract.
function st.practice.tick(sim, now, elapsed, out)
    out.seal_faded = false
    out.buffs_changed = false
    out.bl_fired = false
    out.swing_ready = false
    out.attack_paused = false
    out.attack_resumed = false
    out.fight_elapsed = false
    out.queue_ready = false
    -- cast() flags merged in when a queued ability fires this tick.
    out.gcd_started = false
    out.gcd_blocked = false
    out.queued = false
    out.seal_changed = false
    out.twist_armed = false
    out.cooldown_set = false
    out.ignored = false
    out.judged_seal = nil
    out.held_swing = nil

    -- Fading seal expiry (archive 3303-3329): the old seal drops out of the twist window.
    if sim.fading_seal_label and sim.fading_seal_expires > 0 and now >= sim.fading_seal_expires then
        sim.active_seals[sim.fading_seal_label] = nil
        sim.fading_seal_label = nil
        sim.fading_seal_expires = 0
        sim.n_active_seals = 0
        sim.seal_1_label = nil
        sim.seal_2_label = nil
        for label in pairs(sim.active_seals) do
            sim.n_active_seals = sim.n_active_seals + 1
            if not sim.seal_1_label then
                sim.seal_1_label = label
            else
                sim.seal_2_label = label
            end
        end
        out.seal_faded = true
    end

    -- Avenging Wrath buff expiry (archive 3331-3334): no haste, no recalc.
    if sim.aw_buff_expires > 0 and now >= sim.aw_buff_expires then
        sim.aw_buff_expires = 0
        out.buffs_changed = true
    end

    -- Bloodlust expiry (archive 3336-3352).
    if sim.has_bloodlust and sim.bl_buff_expires > 0 and now >= sim.bl_buff_expires then
        sim.has_bloodlust = false
        sim.bl_buff_expires = 0
        out.buffs_changed = true
    end

    -- Haste pot expiry (archive 3354-3364).
    if sim.has_haste_pot and sim.haste_pot_buff_expires > 0 and now >= sim.haste_pot_buff_expires then
        sim.has_haste_pot = false
        sim.haste_pot_buff_expires = 0
        out.buffs_changed = true
    end

    -- Abacus buff expiry (archive 3366-3371; the cooldown is left running).
    if sim.has_abacus and sim.abacus_buff_expires > 0 and now >= sim.abacus_buff_expires then
        sim.has_abacus = false
        sim.abacus_buff_expires = 0
        out.buffs_changed = true
    end

    -- DST buff expiry (archive 3373-3384; the ICD is left running).
    if sim.has_dst and sim.dst_buff_expires > 0 and now >= sim.dst_buff_expires then
        sim.has_dst = false
        sim.dst_buff_expires = 0
        out.buffs_changed = true
    end

    -- Fight clock + auto-Bloodlust (archive 3386-3400). A zero delay was already fired
    -- by begin_fight; only a positive delay fires here, and never while locked.
    if sim.fight_active then
        out.fight_elapsed = true
        if not sim.locked_rotation and not sim.fight_bl_fired and sim.fight_bl_delay > 0
            and (now - sim.fight_start_time) >= sim.fight_bl_delay then
            sim.fight_bl_fired = true
            sim.has_bloodlust = true
            sim.bl_buff_expires = now + 40
            out.bl_fired = true
            out.buffs_changed = true
        end
    end

    -- GCD end -> spell queue (archive process_gcd_end hook + process_spell_queue
    -- 3252-3279). The queue is consumed on GCD end; firing is re-validated against the
    -- fight/pause state and the ability cooldown.
    if sim.gcd_active and now >= sim.gcd_expires then
        sim.gcd_active = false
        if sim.queued_ability then
            local queued = sim.queued_ability
            sim.queued_ability = nil
            sim.queue_timestamp = 0
            if sim.fight_active and not sim.attack_paused and st.practice.ABILITIES[queued] then
                local fire = true
                local ab = st.practice.ABILITIES[queued]
                if ab.type == "ability" then
                    local cd_key = queued .. "_cooldown_expires"
                    if sim[cd_key] and sim[cd_key] > now then
                        fire = false
                    end
                end
                if fire then
                    local scratch = {}
                    st.practice.cast(sim, queued, now, scratch)
                    out.gcd_started = scratch.gcd_started
                    out.gcd_blocked = scratch.gcd_blocked
                    out.queued = scratch.queued
                    out.seal_changed = scratch.seal_changed
                    out.twist_armed = scratch.twist_armed
                    out.buff_changed = out.buff_changed or scratch.buff_changed
                    out.cooldown_set = scratch.cooldown_set
                    out.attack_resumed = out.attack_resumed or scratch.resumed_attack
                    out.ignored = scratch.ignored
                    if scratch.judged_seal then out.judged_seal = scratch.judged_seal end
                    if scratch.held_swing then out.held_swing = true end
                    out.queue_ready = true
                end
            end
        end
    end

    -- Swing completion (archive 3413-3424). While a stopattack is pending the completed
    -- swing is held until the next resume.
    if sim.fight_active and not sim.attack_paused and sim.swing_active and now >= sim.swing_ends_at then
        if sim.attack_pause_pending then
            sim.attack_pause_pending = false
            sim.attack_paused = true
            sim.swing_held = true
            sim.swing_active = false
            out.attack_paused = true
        else
            sim.swing_active = false
            out.swing_ready = true
        end
    end

    return out
end

--=========================================================================================
-- Swing completion evaluation
--=========================================================================================

-- Grade a completed swing (archive sim_on_swing 3430-3531, minus UI/DST/combat-pause).
-- Does NOT restart the swing: the caller calls start_swing() after processing this.
--   out.result        "twist" when both seals are up at swing time, else "miss"
--   out.twist_attempted  whether a seal swap armed a twist this cycle (pre-clear)
--   out.feedback      "TWIST!" / "MISS" for an armed twist, nil when none was attempted
--   out.seal_consumed label of the older seal consumed by a successful twist (or nil)
--   out.timeline_event { lane="melee", texture, result, seal, seal_active } - `seal` is
--     the seal active at swing time (blood wins), captured before the consume.
-- The DST proc is not run here (call maybe_dst_proc() after this, if enabled).
function st.practice.on_swing(sim, now, out)
    local result = (sim.n_active_seals >= 2) and "twist" or "miss"

    local seal = nil
    if sim.active_seals["blood"] then
        seal = "blood"
    elseif sim.active_seals["command"] then
        seal = "command"
    end

    out.result = result
    out.twist_attempted = sim.twist_attempted
    out.timeline_event = {
        lane = "melee",
        texture = "Interface\\Icons\\INV_Sword_04",
        result = result,
        seal = seal,
        seal_active = seal,
    }

    -- Twist timing: ms between the arming seal swap and this swing landing. The swap
    -- armed the fade window (cast() sets fading_seal_expires = swap_time +
    -- SEAL_FADE_SECONDS), so the swap time is recoverable without new sim state. Nil
    -- when the attempt has no measurable swap (the fade already expired before this
    -- call, or dual seals with no fade window such as a resume-swapped pair);
    -- clamped at 0 against clock skew.
    local lead_ms = nil
    if sim.twist_attempted and sim.fading_seal_label and sim.fading_seal_expires
        and sim.fading_seal_expires > 0 then
        lead_ms = (now - (sim.fading_seal_expires - st.practice.SEAL_FADE_SECONDS)) * 1000
        if lead_ms < 0 then
            lead_ms = 0
        end
        -- Round to 0.001 ms: the fade arithmetic rides binary floating point
        -- (2.4 - 0.4 is a hair above 2.0), and an unrounded 200.0000004 ms lead
        -- would grade B against an exact 200 ms cutoff.
        lead_ms = math.floor(lead_ms * 1000 + 0.5) / 1000
    end
    out.lead_ms = lead_ms

    -- Per-attempt grade: nil when no twist was attempted (not an attempt), "F" for an
    -- armed attempt that missed, otherwise the S/A/B/C/D timing grade below.
    local grade = nil
    if sim.twist_attempted then
        if result == "twist" then
            grade = st.practice.grade_twist(lead_ms)
        else
            grade = "F"
        end
    end
    out.grade = grade

    if sim.twist_attempted then
        if sim.n_active_seals >= 2 then
            out.feedback = "TWIST!"
        else
            out.feedback = "MISS"
        end
        sim.twist_attempted = false
    else
        out.feedback = nil
    end

    -- After a successful twist the older seal is consumed, the newer stays (archive
    -- 3487-3510). A fading seal is consumed first when present, else seal_1.
    local consumed = nil
    if sim.n_active_seals >= 2 then
        if sim.fading_seal_label then
            consumed = sim.fading_seal_label
            sim.active_seals[sim.fading_seal_label] = nil
            sim.fading_seal_label = nil
            sim.fading_seal_expires = 0
        elseif sim.seal_1_label and sim.seal_2_label then
            consumed = sim.seal_1_label
            sim.active_seals[sim.seal_1_label] = nil
        end

        sim.n_active_seals = 0
        sim.seal_1_label = nil
        sim.seal_2_label = nil
        for label in pairs(sim.active_seals) do
            sim.n_active_seals = sim.n_active_seals + 1
            if not sim.seal_1_label then
                sim.seal_1_label = label
            else
                sim.seal_2_label = label
            end
        end
    end
    out.seal_consumed = consumed

    return out
end

--=========================================================================================
-- DST proc (caller rolls the dice: PPM model)
--=========================================================================================

-- Pure DST proc check. `roll` is supplied by the caller (math.random() in game; tests
-- pass fixed values). Requires the 20 s ICD to be down and the buff to be inactive; on a
-- proc the buff runs 10 s and the ICD 20 s. Chance = PPM 4.0 * effective_speed / 60.
-- The archive gates the whole check on the enable setting and the rotation lock at the
-- call site; this function deliberately does not (gate it in phase 2).
function st.practice.maybe_dst_proc(sim, now, roll)
    if sim.has_dst then return false end
    if type(roll) ~= "number" then return false end
    if sim.dst_icd_expires > now then return false end
    local proc_chance = 4.0 * sim.effective_speed / 60
    if roll < proc_chance then
        sim.has_dst = true
        sim.dst_buff_expires = now + 10
        sim.dst_icd_expires = now + 20
        return true
    end
    return false
end

--=========================================================================================
-- Swing grading (archive 1669-1878)
--=========================================================================================

-- Classify one timeline event for grading (archive classify_swing_event 1669-1679).
function st.practice.CLASSIFY(event)
    if event.result == "twist" then
        return "twist"
    elseif event.seal_active == "blood" then
        return "blood_auto"
    elseif event.seal_active == "command" then
        return "cmd_auto"
    else
        return "no_seal"
    end
end

-- CS segment expected patterns (archive 1693-1705): the rotation sequences with
-- cs/cs_late stripped and the implicit auto added. 2/2/5 alternates between two
-- sub-patterns.
st.practice.CS_SEGMENT_PATTERNS = {
    ["1/2"] = { "blood_auto", "twist" },
    ["2/3"] = { "blood_auto", "twist", "twist" },
    ["1/3"] = { "blood_auto", "blood_auto", "twist" },
    ["2/4"] = { "blood_auto", "twist", "blood_auto", "twist" },
    ["2/5_blood"] = { "blood_auto", "blood_auto", "twist", "blood_auto", "twist" },
    ["2/5_command"] = { "cmd_auto", "cmd_auto", "twist", "cmd_auto", "twist" },
    ["2/2/5"] = {
        { "blood_auto", "twist" },
        { "blood_auto", "blood_auto", "twist" },
    },
    ["2007"] = { "blood_auto", "blood_auto" },
}

-- Implicit auto type for each rotation (archive 1708-1717): cmd_auto only for 2/5_command.
st.practice.IMPLICIT_AUTO = {
    ["1/2"] = "blood_auto",
    ["2/3"] = "blood_auto",
    ["1/3"] = "blood_auto",
    ["2/4"] = "blood_auto",
    ["2/5_blood"] = "blood_auto",
    ["2/5_command"] = "cmd_auto",
    ["2/2/5"] = "blood_auto",
    ["2007"] = "blood_auto",
}

-- Evaluate one CS-delimited segment (archive evaluate_segment 1721-1808, verbatim).
-- Returns results_fragment (event_index -> result) and the next 2/2/5 sub-pattern index.
local function evaluate_segment(segment_swings, rotation, is_opener, sub_pattern_idx)
    local results_fragment = {}
    local patterns = st.practice.CS_SEGMENT_PATTERNS[rotation]
    if not patterns then
        for _, sw in ipairs(segment_swings) do
            results_fragment[sw.event_index] = { skipped = true }
        end
        return results_fragment, sub_pattern_idx
    end

    local implicit_auto = st.practice.IMPLICIT_AUTO[rotation] or "blood_auto"

    -- Opener (before first CS): lenient on ordering, but limited to pattern length.
    -- Beyond pattern length, CS should have been cast - extra swings are wrong.
    if is_opener then
        local opener_pattern
        local is_alternating = (rotation == "2/2/5")
        if is_alternating then
            opener_pattern = patterns[sub_pattern_idx or 1]
        else
            opener_pattern = patterns
        end
        local max_opener = opener_pattern and #opener_pattern or 999

        for j, sw in ipairs(segment_swings) do
            local actual = sw.classified
            if j <= max_opener then
                if actual == "twist" or actual == implicit_auto then
                    results_fragment[sw.event_index] = {
                        expected = actual,
                        actual = actual,
                        correct = true,
                    }
                else
                    results_fragment[sw.event_index] = {
                        expected = implicit_auto,
                        actual = actual,
                        correct = false,
                    }
                end
            else
                results_fragment[sw.event_index] = {
                    expected = "cs",
                    actual = actual,
                    correct = false,
                }
            end
        end
        return results_fragment, sub_pattern_idx
    end

    -- Select the expected pattern for this segment (2/2/5 alternates).
    local pattern
    local next_sub_idx = sub_pattern_idx
    local is_alternating = (rotation == "2/2/5")
    if is_alternating then
        local idx = sub_pattern_idx or 1
        pattern = patterns[idx]
        next_sub_idx = (idx % #patterns) + 1
    else
        pattern = patterns
    end

    -- Compare position-by-position; beyond pattern length CS should have been used.
    for j, sw in ipairs(segment_swings) do
        if j <= #pattern then
            local expected_action = pattern[j]
            results_fragment[sw.event_index] = {
                expected = expected_action,
                actual = sw.classified,
                correct = (expected_action == sw.classified),
            }
        else
            results_fragment[sw.event_index] = {
                expected = "cs",
                actual = sw.classified,
                correct = false,
            }
        end
    end

    return results_fragment, next_sub_idx
end

-- Analyze swings against the rotation pattern, CS-anchored (archive
-- analyze_swing_correctness 1815-1878, verbatim apart from parameters).
--   events  - array of { lane, result, seal_active, texture, time }
--   count   - number of events to process (events[1..count])
--   bands   - array of { start_time, rotation } rotation bands
--   returns results[event_index] = { expected, actual, correct } or { skipped = true }
local function analyze_events(events, count, bands, band_count)
    local results = {}
    if not band_count or band_count == 0 then return results end

    local current_band = 1
    local rotation = bands[1].rotation
    local is_opener = true
    local sub_pattern_idx = 1
    local current_segment = {}

    local function flush_segment()
        if #current_segment > 0 then
            local fragment, next_sub = evaluate_segment(
                current_segment, rotation, is_opener, sub_pattern_idx
            )
            for idx, result in pairs(fragment) do
                results[idx] = result
            end
            sub_pattern_idx = next_sub
        end
        current_segment = {}
    end

    for i = 1, count do
        local event = events[i]

        -- Crossing into a new rotation band flushes against the OLD rotation.
        if current_band < band_count then
            local next_band = bands[current_band + 1]
            if event.time >= next_band.start_time then
                flush_segment()
                current_band = current_band + 1
                rotation = next_band.rotation
                is_opener = true
                sub_pattern_idx = 1
            end
        end

        if event.lane == "cs" then
            -- CS boundary: evaluate the segment, start fresh.
            flush_segment()
            is_opener = false
        elseif event.lane == "melee" then
            current_segment[#current_segment + 1] = {
                event_index = i,
                classified = st.practice.CLASSIFY(event),
            }
        elseif event.lane == "judge" and event.seal_active == "command" then
            -- Judging with SoC is always wrong (independent of segment analysis).
            results[i] = {
                expected = "judge_blood",
                actual = "judge_command",
                correct = false,
            }
        end
    end

    -- Evaluate the final (possibly incomplete) segment.
    flush_segment()

    return results
end

-- Grading entry point used by the tests and phase 2 (see the input contract above).
function st.practice.analyze(events, count, bands, band_count)
    return analyze_events(events, count, bands, band_count)
end

--=========================================================================================
-- Practice scoring: per-attempt grades, session score, personal bests (new design, no
-- archive source - the archived build graded TWIST!/MISS only and kept no score).
--
-- Timing model: a twist attempt is a seal swap, and the swing must land inside the
-- SEAL_FADE_SECONDS window the swap opens. The swap lead time (ms from the arming swap
-- to the swing landing, reported as on_swing's out.lead_ms) is the timing error: a
-- smaller lead is a tighter twist, because an early swap risks the fade expiring while
-- a late swap risks landing after the swing. Grades are monotonic in the lead.
--=========================================================================================

-- Grade cutoffs in ms of swap lead time, as fractions of the 400 ms twist window:
-- S/A/B split the window into quarters (tight/half/three-quarter window), C is a
-- success with margin, and anything slower is D (the twist held, but only just -
-- inside the fade with less than 50 ms to spare).
st.practice.GRADE_LEAD_MS_S = 100
st.practice.GRADE_LEAD_MS_A = 200
st.practice.GRADE_LEAD_MS_B = 300
st.practice.GRADE_LEAD_MS_C = 350

-- Grade points (0-100 scale): every attempt contributes, so a missed attempt (F = 0)
-- drags the session score exactly like a wrong answer on a test.
st.practice.GRADE_POINTS = { S = 100, A = 80, B = 60, C = 40, D = 20, F = 0 }

-- Grade rank for best-grade comparison (higher is better; F is the floor).
st.practice.GRADE_RANK = { S = 6, A = 5, B = 4, C = 3, D = 2, F = 1 }

-- Rolling window in attempts: the consistency readouts (rolling hit-rate / rolling
-- points) cover the last SCORE_WINDOW attempts, so early-session mistakes age out.
st.practice.SCORE_WINDOW = 20

-- Grade one successful twist by its swap lead time (ms). A nil/non-number lead means
-- the success has no measurable swap (dual seals with no fade window); it grades C,
-- the neutral middle, rather than rewarding or punishing an unmeasured attempt.
function st.practice.grade_twist(lead_ms)
    if type(lead_ms) ~= "number" then
        return "C"
    end
    if lead_ms <= st.practice.GRADE_LEAD_MS_S then
        return "S"
    elseif lead_ms <= st.practice.GRADE_LEAD_MS_A then
        return "A"
    elseif lead_ms <= st.practice.GRADE_LEAD_MS_B then
        return "B"
    elseif lead_ms <= st.practice.GRADE_LEAD_MS_C then
        return "C"
    end
    return "D"
end

-- Fresh session score accumulator (pure data; the caller owns it, typically one per
-- practice session on the UI side).
function st.practice.new_score()
    return {
        attempts = 0,       -- twist attempts recorded (swings with no attempt are not attempts)
        hits = 0,           -- successful twists (any grade but F)
        total_points = 0,   -- sum of GRADE_POINTS over all attempts
        error_sum_ms = 0,   -- sum of measured leads over successful twists
        error_count = 0,    -- successful twists with a measured lead
        best_grade = nil,   -- best single-attempt grade by GRADE_RANK
        last_grade = nil,   -- most recent attempt grade
        recent_points = {}, -- ring of the last SCORE_WINDOW attempt point values
        recent_hits = 0,    -- hits inside recent_points (F is the only 0-point grade)
    }
end

-- Record one graded attempt. A nil grade means "no attempt" and records nothing.
-- Deterministic: no clock, no randomness; repeated sequences give identical states.
function st.practice.record_attempt(score, grade, lead_ms)
    if not score or not grade then
        return score
    end
    local points = st.practice.GRADE_POINTS[grade] or 0
    score.attempts = score.attempts + 1
    score.total_points = score.total_points + points
    score.last_grade = grade
    local hit = grade ~= "F"
    if hit then
        score.hits = score.hits + 1
        score.recent_hits = score.recent_hits + 1
        if type(lead_ms) == "number" then
            score.error_sum_ms = score.error_sum_ms + lead_ms
            score.error_count = score.error_count + 1
        end
    end
    local rank = st.practice.GRADE_RANK[grade] or 0
    if not score.best_grade or rank > (st.practice.GRADE_RANK[score.best_grade] or 0) then
        score.best_grade = grade
    end
    local recent = score.recent_points
    recent[#recent + 1] = points
    if #recent > st.practice.SCORE_WINDOW then
        -- Evict the oldest attempt; only F carries 0 points, so a positive eviction
        -- was a hit and the rolling hit count drops by one.
        if table.remove(recent, 1) > 0 then
            score.recent_hits = score.recent_hits - 1
        end
    end
    return score
end

-- Summarize a score accumulator. The session score (0-100, rounded half up) is the
-- mean grade points per attempt: accuracy is in it (every F contributes 0) and so is
-- consistency (every attempt counts equally, so scattered misses drag the mean).
-- The rolling hit-rate / rolling points (last SCORE_WINDOW attempts) and the mean
-- timing error ride alongside it as the accuracy + consistency readouts. An empty
-- accumulator scores 0 with zero rates and a nil mean error.
function st.practice.score_summary(score)
    local s = score or st.practice.new_score()
    local attempts = s.attempts or 0
    local hits = s.hits or 0
    local recent = s.recent_points or {}
    local recent_n = #recent
    local recent_points = 0
    for i = 1, recent_n do
        recent_points = recent_points + recent[i]
    end
    local summary = {
        attempts = attempts,
        hits = hits,
        hit_rate = (attempts > 0) and (hits / attempts) or 0,
        mean_points = (attempts > 0) and ((s.total_points or 0) / attempts) or 0,
        rolling_hit_rate = (recent_n > 0) and ((s.recent_hits or 0) / recent_n) or 0,
        rolling_points = (recent_n > 0) and (recent_points / recent_n) or 0,
        mean_error_ms = ((s.error_count or 0) > 0)
            and (s.error_sum_ms / s.error_count) or nil,
        best_grade = s.best_grade,
        last_grade = s.last_grade,
    }
    summary.score = (attempts > 0) and math.floor(summary.mean_points + 0.5) or 0
    return summary
end

--=========================================================================================
-- Generic scenario harness (C1): the reusable sim/timing engine.
--
-- Scenario lifecycle, forced-move windows, timing queries and the scoring pipeline live
-- here; every trainer is a scenario spec registered through
-- st.practice.harness.register_scenario, and the paladin twist sim is consumer #1
-- (registered at the bottom of this section). The harness is PURE like the rest of the
-- module: the caller owns the clock and feeds `now` explicitly.
--
-- The direct engine entry points above are deliberately untouched: the shipped practice
-- UI keeps driving the paladin sim exactly as before (the regression bar), while a
-- harness-driven session wraps the same functions - tests/practice_state.lua pins that
-- both paths produce identical sim state for identical inputs.
--
-- Scenario spec contract (key/title required; everything else optional):
--   key          unique string id
--   title        human-readable label
--   class        "PALADIN"|"HUNTER"|"WARRIOR"|"DRUID"|"SHAMAN"|"ROGUE" (nil = any class)
--   kind         one of H.SCENARIO_KINDS
--   description  one-line summary for a future scenario picker
--   new_state    function(now, opts) -> scenario state table (default {})
--   windows      function(now, opts) -> window list on the caller's clock (default none)
--   begin        function(session, now, opts)
--   tick         function(session, now, elapsed, out)
--   finish       function(session, now)
--   event        function(session, now, key) -> result   (exact-time action hook)
--   queries      map name -> function(session, now) -> value (timing queries)
--
-- Session contract (the caller drives everything; nothing runs on its own):
--   session = H.new_session(key, now, opts)          -- nil, err for an unknown key
--   H.begin_session(session, now, opts)              -- builds windows, fires begin
--   H.tick_session(session, now, elapsed, out)       -- fires tick, returns out
--   H.scenario_event(session, key, now)              -- fires the exact-time event hook
--   H.end_session(session, now)                      -- fires finish
--   H.record_session_attempt(session, grade, lead_ms)
--   H.session_summary(session)                       -- the shared score summary
--   H.query(session, name, now)                      -- scenario timing query
--
-- Window contract: a window is { index, start_time, end_time, label }; start_time is
-- inclusive, end_time exclusive. Lists are expected sorted by start_time (build_windows
-- produces that shape).
--=========================================================================================
st.practice.harness = st.practice.harness or {}
local H = st.practice.harness

-- The scenario kinds the registry accepts. The seven shipped kinds keep their
-- meaning (the eight registered entries are unchanged); the five new kinds are the
-- per-class audit's taxonomy (bench/class_features_drills_2026-10-19.md §4.1):
--   rotation_run   the rotation SCENARIO - the class's actual wowsims rotation,
--                  run end to end and graded on the cast sequence
--   rotation_order the priority-order DRILL
--   rotation_window the cooldown / rotation-window DRILL
--   transition     the opener / transition DRILL
--   situational    the situational-decision DRILL
H.SCENARIO_KINDS = {
    paladin_twist = true,
    combo_windows = true,
    forced_move = true,
    execute_phase = true,
    energy_loop = true,
    weave_timing = true,
    swing_window = true,
    rotation_run = true,
    rotation_order = true,
    rotation_window = true,
    transition = true,
    situational = true,
}

H.SCENARIOS = H.SCENARIOS or {}
H.SCENARIO_ORDER = H.SCENARIO_ORDER or {}

-- Register a scenario spec (see the contract above). Returns the spec, or nil plus an
-- error string. The first registration wins; duplicates are rejected loudly.
function H.register_scenario(spec)
    if type(spec) ~= "table" then
        return nil, "scenario spec must be a table"
    end
    if type(spec.key) ~= "string" or spec.key == "" then
        return nil, "scenario needs a non-empty key"
    end
    if type(spec.title) ~= "string" or spec.title == "" then
        return nil, "scenario needs a non-empty title"
    end
    if spec.kind ~= nil and not H.SCENARIO_KINDS[spec.kind] then
        return nil, "unknown scenario kind: " .. tostring(spec.kind)
    end
    if H.SCENARIOS[spec.key] then
        return nil, "scenario already registered: " .. spec.key
    end
    H.SCENARIOS[spec.key] = spec
    H.SCENARIO_ORDER[#H.SCENARIO_ORDER + 1] = spec.key
    return spec
end

function H.get_scenario(key)
    if type(key) ~= "string" then
        return nil
    end
    return H.SCENARIOS[key]
end

-- Every registered scenario, in registration order; a class filter keeps specs whose
-- class matches or is unset (nil = all classes).
function H.scenarios_for_class(class)
    local list = {}
    for i = 1, #H.SCENARIO_ORDER do
        local spec = H.SCENARIOS[H.SCENARIO_ORDER[i]]
        if spec and (class == nil or spec.class == nil or spec.class == class) then
            list[#list + 1] = spec
        end
    end
    return list
end

--=========================================================================================
-- Harness: sessions
--=========================================================================================
function H.new_session(key, now, opts)
    local spec = H.SCENARIOS[key]
    if not spec then
        return nil, "unknown scenario: " .. tostring(key)
    end
    local state = {}
    if type(spec.new_state) == "function" then
        state = spec.new_state(now or 0, opts) or {}
    end
    return {
        key = spec.key,
        spec = spec,
        state = state,
        score = st.practice.new_score(),
        windows = {},
        started_at = now or 0,
        active = false,
    }
end

function H.begin_session(session, now, opts)
    if not session or not session.spec or session.active then
        return false
    end
    opts = opts or {}
    local spec = session.spec
    session.active = true
    session.started_at = now or 0
    if type(opts.windows) == "table" then
        session.windows = opts.windows
    elseif type(spec.windows) == "function" then
        session.windows = spec.windows(now or 0, opts) or {}
    else
        session.windows = {}
    end
    if type(spec.begin) == "function" then
        spec.begin(session, now, opts)
    end
    return true
end

function H.tick_session(session, now, elapsed, out)
    out = out or {}
    if not session or not session.spec or not session.active then
        return out
    end
    if type(session.spec.tick) == "function" then
        session.spec.tick(session, now, elapsed, out)
    end
    return out
end

function H.end_session(session, now)
    if not session or not session.spec or not session.active then
        return false
    end
    session.active = false
    if type(session.spec.finish) == "function" then
        session.spec.finish(session, now)
    end
    return true
end

-- Exact-time action hook: the caller reports one action (a cast, a shift, a movement
-- decision) with its true timestamp, so scenarios grade the action time, not the next
-- tick that observes its effect.
function H.scenario_event(session, key, now)
    if not session or not session.spec or not session.active then
        return nil
    end
    local fn = session.spec.event
    if type(fn) ~= "function" then
        return nil
    end
    return fn(session, now, key)
end

-- Scenario timing query; nil plus an error string for an unknown query name.
function H.query(session, name, now)
    if not session or not session.spec then
        return nil, "no session"
    end
    local queries = session.spec.queries
    local fn = queries and queries[name]
    if type(fn) ~= "function" then
        return nil, "unknown query: " .. tostring(name)
    end
    return fn(session, now)
end

--=========================================================================================
-- Harness: scoring pipeline (the same accumulator the paladin session uses)
--=========================================================================================
-- The grade-string pipeline is class-agnostic; the harness exposes it as the shared
-- scoring entry points and every session owns one accumulator.
H.new_score = st.practice.new_score
H.record_attempt = st.practice.record_attempt
H.score_summary = st.practice.score_summary

function H.record_session_attempt(session, grade, lead_ms)
    if not session then
        return nil
    end
    session.score = st.practice.record_attempt(session.score, grade, lead_ms)
    return session.score
end

function H.session_summary(session)
    if not session then
        return nil
    end
    return st.practice.score_summary(session.score)
end

-- Grade-band helper shared by the scenario graders: `bands` is an ordered list of
-- { max = <number>, grade = <string> }; the first band whose max covers the value wins
-- and a final band without a max is the fallback for everything larger. A non-number
-- value returns the fallback grade when one exists, else nil (never a grade on a guess).
function H.grade_band(value, bands)
    if type(bands) ~= "table" then
        return nil
    end
    local fallback = nil
    for i = 1, #bands do
        local band = bands[i]
        if band and band.grade then
            if band.max == nil then
                if fallback == nil then
                    fallback = band.grade
                end
            elseif type(value) == "number" and value <= band.max then
                return band.grade
            end
        end
    end
    return fallback
end

--=========================================================================================
-- Harness: windows (forced-move cadence and every other windowed mechanic)
--=========================================================================================
-- Build a deterministic window list: window i runs
-- [first_start + (i-1) * (duration + gap), + duration]. `first_start` is absolute in the
-- caller's clock domain; the same opts always produce the same windows (no randomness).
function H.build_windows(opts)
    opts = opts or {}
    local count = opts.count or 0
    local duration = opts.duration or 2
    local gap = opts.gap or 6
    local start = opts.first_start or 0
    local label = opts.label
    local windows = {}
    for i = 1, count do
        local window_start = start + (i - 1) * (duration + gap)
        windows[i] = {
            index = i,
            start_time = window_start,
            end_time = window_start + duration,
            label = label,
        }
    end
    return windows
end

-- The window containing t (start inclusive, end exclusive), or nil.
function H.window_at(windows, t)
    if type(t) ~= "number" then
        return nil
    end
    for i = 1, #(windows or {}) do
        local w = windows[i]
        if w and w.start_time and w.end_time and t >= w.start_time and t < w.end_time then
            return w
        end
    end
    return nil
end

-- The first window that has not ended at t (the active one included), or nil.
function H.next_window(windows, t)
    if type(t) ~= "number" then
        return nil
    end
    for i = 1, #(windows or {}) do
        local w = windows[i]
        if w and w.end_time and t < w.end_time then
            return w
        end
    end
    return nil
end

-- Seconds until the next window starts: 0 while inside a window, nil when none is left.
function H.time_to_next_window(windows, t)
    local w = H.next_window(windows, t)
    if not w then
        return nil
    end
    if t >= w.start_time then
        return 0
    end
    return w.start_time - t
end

-- Seconds left in the window containing t (nil between windows).
function H.window_remaining(windows, t)
    local w = H.window_at(windows, t)
    if not w then
        return nil
    end
    return w.end_time - t
end

-- Total seconds of [from, to] covered by windows. Windows are expected sorted by
-- start_time; overlapping entries are merged so the span is counted once.
function H.overlap_seconds(windows, from, to)
    if type(from) ~= "number" or type(to) ~= "number" or to <= from then
        return 0
    end
    local total = 0
    local cursor = from
    for i = 1, #(windows or {}) do
        local w = windows[i]
        if w and w.start_time and w.end_time then
            local s = math.max(w.start_time, cursor)
            local e = math.min(w.end_time, to)
            if e > s then
                total = total + (e - s)
            end
            if w.end_time > cursor then
                cursor = w.end_time
            end
        end
    end
    return total
end

--=========================================================================================
-- Scenario shells (offline-testable primitives; the class sims land in later rounds)
--=========================================================================================

-- Consumer #1: the paladin twist sim, driven through the harness lifecycle. The hooks
-- call the existing sim functions verbatim, so a session driven through the harness is
-- equivalent to the direct engine calls the practice UI makes (pinned in the tests).
H.register_scenario({
    key = "paladin_twist",
    title = "Twist practice",
    class = "PALADIN",
    kind = "paladin_twist",
    description = "Seal-twist timing drill on the paladin swing sim (the shipped practice session).",
    new_state = function(now, opts)
        return st.practice.new_sim()
    end,
    begin = function(session, now, opts)
        st.practice.begin_fight(session.state, now, opts)
    end,
    tick = function(session, now, elapsed, out)
        st.practice.tick(session.state, now, elapsed, out)
    end,
    finish = function(session, now)
        st.practice.end_fight(session.state)
    end,
    queries = {
        time_to_swing = function(session, now)
            local sim = session.state
            if not sim or not sim.swing_active then
                return nil
            end
            return sim.swing_ends_at - (now or 0)
        end,
        twist_window_remaining = function(session, now)
            local sim = session.state
            if not sim or not sim.fading_seal_label or not sim.fading_seal_expires then
                return nil
            end
            local remaining = sim.fading_seal_expires - (now or 0)
            if remaining < 0 then
                return 0
            end
            return remaining
        end,
        rotation = function(session)
            return st.practice.determine_rotation(session.state)
        end,
    },
})

-- P5: combo-window drills (generic opener + required pieces). The paladin instantiation
-- is the Avenging Wrath combo: AW opens the window, the haste pieces must land inside
-- it, and the grade is the slowest piece's lag. The archived practice_aw_includes_pot /
-- practice_aw_includes_sob options are still deferred (new options are out of this
-- lane's scope): this ships the offline sim the future UI wiring consumes.
H.COMBO_DEFAULTS = { opener = "aw", pieces = { "hpot" }, window = 3 }

-- Piece-lag bands in seconds: S tight ... D barely inside the window; an incomplete
-- window grades F (see combo_evaluate).
H.COMBO_LAG_BANDS = {
    { max = 0.2,  grade = "S" },
    { max = 0.5,  grade = "A" },
    { max = 1.0,  grade = "B" },
    { max = 2.0,  grade = "C" },
    { grade = "D" },
}

function H.new_combo(opts)
    opts = opts or {}
    local given = opts.pieces or H.COMBO_DEFAULTS.pieces
    local pieces = {}
    for i = 1, #given do
        pieces[i] = given[i]
    end
    return {
        opener = opts.opener or H.COMBO_DEFAULTS.opener,
        pieces = pieces,
        window = opts.window or H.COMBO_DEFAULTS.window,
        open = false,
        opened_at = nil,
        recorded = {},
        order = {},
    }
end

-- The opener key opens the window. A window already running is not restarted (the first
-- opener wins); an opener arriving after the previous window expired starts a fresh
-- cycle (the piece log resets).
function H.combo_open(combo, now, key)
    if not combo or key ~= combo.opener then
        return false
    end
    if combo.open and type(now) == "number" and type(combo.opened_at) == "number"
        and (now - combo.opened_at) <= combo.window then
        return false
    end
    combo.open = true
    combo.opened_at = now
    combo.recorded = {}
    combo.order = {}
    return true
end

-- Record a required piece landing inside the window; first record per piece wins, and a
-- piece arriving after the window closed is rejected (the caller can see false).
function H.combo_record(combo, now, key)
    if not combo or not combo.open or type(now) ~= "number" then
        return false
    end
    if (now - combo.opened_at) > combo.window then
        return false
    end
    local is_piece = false
    for i = 1, #combo.pieces do
        if combo.pieces[i] == key then
            is_piece = true
            break
        end
    end
    if not is_piece or combo.recorded[key] then
        return false
    end
    combo.recorded[key] = now
    combo.order[#combo.order + 1] = key
    return true
end

function H.combo_missing(combo)
    local missing = {}
    if not combo then
        return missing
    end
    for i = 1, #combo.pieces do
        local key = combo.pieces[i]
        if not combo.recorded[key] then
            missing[#missing + 1] = key
        end
    end
    return missing
end

-- Evaluate the open window: { grade, lag, complete, missing }. A window with pieces
-- still missing grades F (the combo did not land); otherwise the grade bands on the
-- slowest piece's lag. Returns nil when no window is open.
function H.combo_evaluate(combo)
    if not combo or not combo.open then
        return nil
    end
    local missing = H.combo_missing(combo)
    local detail = { complete = (#missing == 0), missing = missing }
    if #missing > 0 then
        detail.grade = "F"
        detail.lag = nil
        return detail
    end
    local lag = 0
    for i = 1, #combo.pieces do
        local t = combo.recorded[combo.pieces[i]]
        if t and (t - combo.opened_at) > lag then
            lag = t - combo.opened_at
        end
    end
    detail.lag = lag
    detail.grade = H.grade_band(lag, H.COMBO_LAG_BANDS) or "F"
    return detail
end

function H.combo_window_remaining(combo, now)
    if not combo or not combo.open or type(now) ~= "number" then
        return nil
    end
    local remaining = combo.window - (now - combo.opened_at)
    if remaining < 0 then
        return 0
    end
    return remaining
end

H.register_scenario({
    key = "paladin_aw_combo",
    title = "Avenging Wrath combo",
    class = "PALADIN",
    kind = "combo_windows",
    description = "AW combo drill: Avenging Wrath opens the window, the haste pieces must land inside it.",
    new_state = function(now, opts)
        return {
            sim = st.practice.new_sim(),
            combo = H.new_combo(opts),
            aw_seen = false,
            piece_seen = {},
        }
    end,
    begin = function(session, now, opts)
        local state = session.state
        st.practice.begin_fight(state.sim, now, opts)
        state.combo = H.new_combo(opts)
        state.aw_seen = false
        state.piece_seen = {}
    end,
    -- Exact-time path: the caller reports each cast as it happens (best precision).
    event = function(session, now, key)
        local combo = session.state.combo
        if H.combo_open(combo, now, key) then
            return "opened"
        end
        if H.combo_record(combo, now, key) then
            return "recorded"
        end
        return nil
    end,
    tick = function(session, now, elapsed, out)
        local state = session.state
        st.practice.tick(state.sim, now, elapsed, out)
        out.combo_opened = false
        out.combo_recorded = nil
        local sim = state.sim
        -- Sim-driven path: AW's buff appearing opens the window, the haste buffs record.
        if sim.aw_buff_expires > 0 then
            if not state.aw_seen then
                state.aw_seen = true
                if H.combo_open(state.combo, now, "aw") then
                    out.combo_opened = true
                end
            end
        else
            state.aw_seen = false
        end
        local pieces = state.combo.pieces
        for i = 1, #pieces do
            local key = pieces[i]
            local active
            if key == "hpot" then
                active = sim.has_haste_pot
            elseif key == "abacus" then
                active = sim.has_abacus
            elseif key == "dst" then
                active = sim.has_dst
            end
            if active ~= nil then
                if active and not state.piece_seen[key] then
                    state.piece_seen[key] = true
                    if H.combo_record(state.combo, now, key) then
                        out.combo_recorded = key
                    end
                elseif not active then
                    state.piece_seen[key] = nil
                end
            end
        end
    end,
    finish = function(session, now)
        st.practice.end_fight(session.state.sim)
    end,
    queries = {
        combo_grade = function(session)
            return H.combo_evaluate(session.state.combo)
        end,
        combo_window_remaining = function(session, now)
            return H.combo_window_remaining(session.state.combo, now)
        end,
        combo_missing = function(session)
            return H.combo_missing(session.state.combo)
        end,
        time_to_swing = function(session, now)
            local sim = session.state.sim
            if not sim or not sim.swing_active then
                return nil
            end
            return sim.swing_ends_at - (now or 0)
        end,
    },
})

-- H5: forced-move drill. The shell models the forced-move cadence and grades cast
-- attempts around the windows: casting inside a window is F, a cast that would still be
-- running when the next window starts is C, and the bands reward finishing with margin.
-- (Whether the player actually moved is in-client state - UNCONFIRMED offline; this
-- shell grades the cast legality the sim can see.)
H.H5_DEFAULTS = { first_delay = 5, count = 5, duration = 2.5, gap = 5.5 }

function H.grade_move_cast(windows, cast_start, cast_time)
    if type(cast_start) ~= "number" then
        return nil
    end
    if H.window_at(windows, cast_start) then
        return "F"
    end
    local next_w = H.next_window(windows, cast_start)
    if not next_w then
        return "S"
    end
    local margin = next_w.start_time - (cast_start + (cast_time or 0))
    if margin <= 0 then
        return "C"
    elseif margin <= 0.5 then
        return "B"
    elseif margin <= 1.5 then
        return "A"
    end
    return "S"
end

H.register_scenario({
    key = "hunter_forced_move",
    title = "Forced-move drill",
    class = "HUNTER",
    kind = "forced_move",
    description = "Forced-move windows: stay mobile inside them, keep casts clear of the next window.",
    new_state = function(now, opts)
        return { in_window = false, current_index = nil }
    end,
    windows = function(now, opts)
        opts = opts or {}
        local defaults = H.H5_DEFAULTS
        return H.build_windows({
            count = opts.count or defaults.count,
            first_start = (now or 0) + (opts.first_delay or defaults.first_delay),
            duration = opts.duration or defaults.duration,
            gap = opts.gap or defaults.gap,
            label = opts.label or "move",
        })
    end,
    begin = function(session, now, opts)
        local state = session.state
        state.in_window = false
        state.current_index = nil
    end,
    -- Exact-time path: the caller reports each cast start with its cast time and the
    -- shell grades the cast legality against the windows (movement itself stays
    -- in-client). A number key is a cast start with no cast time; a table key carries
    -- { start = <time>, cast_time = <seconds> }. Anything else grades nothing.
    event = function(session, now, key)
        local start_time, cast_time
        if type(key) == "number" then
            start_time, cast_time = key, 0
        elseif type(key) == "table" and type(key.start) == "number" then
            start_time, cast_time = key.start, key.cast_time or 0
        else
            return nil
        end
        return H.grade_move_cast(session.windows, start_time, cast_time)
    end,
    tick = function(session, now, elapsed, out)
        local state = session.state
        local w = H.window_at(session.windows, now)
        out.move_started = false
        out.move_ended = false
        if w and not state.in_window then
            state.in_window = true
            state.current_index = w.index
            out.move_started = true
        elseif not w and state.in_window then
            state.in_window = false
            state.current_index = nil
            out.move_ended = true
        end
    end,
    queries = {
        in_move_window = function(session, now)
            return H.window_at(session.windows, now) ~= nil
        end,
        time_to_move = function(session, now)
            return H.time_to_next_window(session.windows, now)
        end,
        window_remaining = function(session, now)
            return H.window_remaining(session.windows, now)
        end,
    },
})

-- W6: execute-phase drill. The phase window is driven by the target's HP fraction
-- (caller-fed; there is no target sensor offline) and the entry grade bands the rage
-- pooled at the 20% crossing - the pre-execute "BANK" cue.
H.EXECUTE_DEFAULTS = { threshold = 0.20, entry_rage = 100 }

H.EXECUTE_ENTRY_BANDS = {
    { max = 0,    grade = "S" },
    { max = 0.25, grade = "A" },
    { max = 0.5,  grade = "B" },
    { max = 0.75, grade = "C" },
    { max = 1.0,  grade = "D" },
    { grade = "F" },
}

-- Advance the phase tracker with a fresh HP fraction; returns "entered"/"exited" on a
-- crossing and nil otherwise. A non-number fraction is an unknown reading: no change.
function H.execute_phase_update(state, now, hp_fraction)
    if not state or type(hp_fraction) ~= "number" then
        return nil
    end
    state.hp_fraction = hp_fraction
    local threshold = state.threshold or H.EXECUTE_DEFAULTS.threshold
    local in_phase = hp_fraction <= threshold
    if in_phase and not state.phase_active then
        state.phase_active = true
        state.phase_started_at = now
        state.entries = (state.entries or 0) + 1
        return "entered"
    elseif not in_phase and state.phase_active then
        state.phase_active = false
        state.phase_started_at = nil
        return "exited"
    end
    return nil
end

-- Grade the rage pooled at the phase entry: S at the full entry target, F at empty,
-- with the quarter bands between.
function H.grade_execute_entry(state, rage, opts)
    local target = (opts and opts.entry_rage) or state.entry_rage or H.EXECUTE_DEFAULTS.entry_rage
    if type(rage) ~= "number" or type(target) ~= "number" or target <= 0 then
        return nil
    end
    if rage <= 0 then
        return "F"
    end
    local fraction = rage / target
    if fraction > 1 then
        fraction = 1
    end
    return H.grade_band(1 - fraction, H.EXECUTE_ENTRY_BANDS)
end

-- SUPERSEDED (operator ruling, 2026-10-19): the class's own drill list owns the
-- execute-phase skill ("warrior_execute_burn" - the transition into the execute
-- phase: the rage dump and the repeated Execute presses below the threshold).
-- One skill, one truth, and the class list wins.
--
-- The built-in spec STAYS registered: the class's session wrappers and their
-- offline pins still resolve the old key (backward compatibility). What changed:
--   * the engine routes the warrior to its own drill list (the built-in drill is
--     not the session any more), and
--   * the built-in drill's grading is delegated to the class's drill below, so the
--     old truth never grades a player attempt.
H.register_scenario({
    key = "warrior_execute",
    title = "Execute-phase drill",
    class = "WARRIOR",
    kind = "execute_phase",
    description = "Execute-phase entry: hold the BANK, cross 20% with rage pooled.",
    new_state = function(now, opts)
        opts = opts or {}
        return {
            threshold = opts.threshold or H.EXECUTE_DEFAULTS.threshold,
            entry_rage = opts.entry_rage or H.EXECUTE_DEFAULTS.entry_rage,
            phase_active = false,
            phase_started_at = nil,
            entries = 0,
            hp_fraction = nil,
        }
    end,
    begin = function(session, now, opts)
        local state = session.state
        state.phase_active = false
        state.phase_started_at = nil
        state.entries = 0
        state.hp_fraction = nil
    end,
    -- Exact-time path: the caller reports each fresh HP reading (a number fraction) and
    -- the shell advances the phase tracker synchronously, so the crossing is graded at
    -- its true time rather than the next tick. The tick keeps reporting the latched
    -- flags for callers that poke state.hp_fraction directly; entry rage is graded
    -- through H.grade_execute_entry by the caller (the rage reading rides no query).
    event = function(session, now, key)
        if type(key) ~= "number" then
            return nil
        end
        session.state.hp_fraction = key
        return H.execute_phase_update(session.state, now, key)
    end,
    tick = function(session, now, elapsed, out)
        local transition = H.execute_phase_update(session.state, now, session.state.hp_fraction)
        out.execute_phase_entered = (transition == "entered")
        out.execute_phase_exited = (transition == "exited")
    end,
    queries = {
        in_execute_phase = function(session)
            return session.state.phase_active == true
        end,
        phase_time = function(session, now)
            if not session.state.phase_active or not session.state.phase_started_at then
                return nil
            end
            return (now or 0) - session.state.phase_started_at
        end,
    },
})

-- D7: powershift-loop drill. The 20-energy rule is the fixed model rule; the shift
-- refund is a sim constant (Furor-5/5 model) because the D1 talent/helm probe is BLOCKED
-- (UNCONFIRMED - bench/verify_bank.md section 3) - the shell renders its sim honestly
-- and never reads in-client talents.
--
-- The energy mechanics below (H.new_energy_state, H.energy_update, H.grade_powershift,
-- H.powershift_cycle) STAY: they are the harness's shared energy primitives (the
-- rogue's baseline energy drill reads them).
H.POWERSHIFT_DEFAULTS = {
    energy_max = 100,
    regen_per_second = 10,
    shift_refund = 40,
    rule_energy = 20,
}

H.POWERSHIFT_BANDS = {
    { max = 20,   grade = "S" },
    { max = 30,   grade = "A" },
    { max = 40,   grade = "B" },
    { max = 60,   grade = "C" },
    { max = 80,   grade = "D" },
    { grade = "F" },
}

function H.new_energy_state(opts)
    opts = opts or {}
    local defaults = H.POWERSHIFT_DEFAULTS
    return {
        energy = opts.energy or 0,
        energy_max = opts.energy_max or defaults.energy_max,
        regen_per_second = opts.regen_per_second or defaults.regen_per_second,
        shift_refund = opts.shift_refund or defaults.shift_refund,
        last_update_at = nil,
        shifts = 0,
    }
end

-- Advance the energy pool to `now` (continuous regen, capped at the pool size). The
-- first call only establishes the clock baseline.
function H.energy_update(state, now)
    if not state then
        return nil
    end
    local energy = state.energy or 0
    if type(now) == "number" then
        local last = state.last_update_at
        if type(last) == "number" and now > last then
            energy = energy + (state.regen_per_second or 0) * (now - last)
        end
        state.last_update_at = now
    end
    local max = state.energy_max or 100
    if energy > max then
        energy = max
    end
    state.energy = energy
    return energy
end

function H.energy_spend(state, now, amount)
    if not state then
        return nil
    end
    H.energy_update(state, now)
    local energy = (state.energy or 0) - (amount or 0)
    if energy < 0 then
        energy = 0
    end
    state.energy = energy
    return energy
end

-- Grade the energy at the moment of a shift (lower is better; the rule boundary is
-- POWERSHIFT_DEFAULTS.rule_energy).
function H.grade_powershift(state)
    if not state then
        return nil
    end
    return H.grade_band(state.energy or 0, H.POWERSHIFT_BANDS)
end

-- Apply one shift cycle: grade the energy, then grant the fixed refund (capped at the
-- pool) and count the shift. Returns grade, energy.
function H.powershift_cycle(state, now)
    if not state then
        return nil
    end
    H.energy_update(state, now)
    local grade = H.grade_powershift(state)
    local energy = (state.energy or 0) + (state.shift_refund or 0)
    local max = state.energy_max or 100
    if energy > max then
        energy = max
    end
    state.energy = energy
    state.shifts = (state.shifts or 0) + 1
    return grade, energy
end

-- SUPERSEDED (operator ruling, 2026-10-19): the class's own drill list owns the
-- shift rule ("druid_powershift_rework" - the SIM's trigger: the TBC fixed line
-- below 10 energy, the classic/sod cost trigger). The built-in drill's old truth
-- was the addon's own 20-energy rule, which the sims do not use: one skill, two
-- truths. One skill, one truth - the class list wins.
--
-- The built-in spec STAYS registered (the class's session wrappers and their
-- offline pins still resolve the old key - backward compatibility). What changed:
--   * the engine routes the druid to its own drill list (the built-in drill is not
--     the session any more), and
--   * the built-in drill's grading is DELEGATED to the class's drill below, so the
--     20-energy rule never grades a player attempt.
H.register_scenario({
    key = "druid_powershift",
    title = "Powershift-loop drill",
    class = "DRUID",
    kind = "energy_loop",
    description = "Powershift cadence: the shift rule as the sims read it (the class's own drill).",
    new_state = function(now, opts)
        return H.new_energy_state(opts)
    end,
    begin = function(session, now, opts)
        -- Re-baseline the regen clock without draining the pool: a re-begin after the
        -- session ended must not grant phantom regen across the gap.
        session.state.last_update_at = nil
    end,
    -- Exact-time path: the caller reports each powershift and the shell grades it.
    -- The grade comes from the CLASS's own drill (the class list is the single
    -- source of the shift rule); the shell's own model is the last-resort fallback
    -- for a flavour that ships no class drill at all.
    event = function(session, now, key)
        if key ~= "shift" then
            return nil
        end
        local delegated = H.delegate_drill_grade("druid_powershift", session.state, now, key)
        if delegated ~= nil then
            return delegated
        end
        local grade = H.powershift_cycle(session.state, now)
        return grade
    end,
    tick = function(session, now, elapsed, out)
        out.energy = H.energy_update(session.state, now)
    end,
    queries = {
        energy = function(session, now)
            return H.energy_update(session.state, now)
        end,
        grade_next_shift = function(session)
            return H.grade_powershift(session.state)
        end,
    },
})

-- S7: weave-timing drill, on weave.lua's math (marker fraction / safe start / clip). A
-- clipped cast grades F; a safe cast bands on the margin left before the marker (a tight
-- start near the marker is the skilled one). The shell returns nil when weave.lua is not
-- loaded - never a grade on a guess.
H.WEAVE_DEFAULTS = { swing_duration = 2.6, effective_cast = 1.5, latency = 0.1 }

H.WEAVE_MARGIN_BANDS = {
    { max = 0.02, grade = "S" },
    { max = 0.05, grade = "A" },
    { max = 0.10, grade = "B" },
    { max = 0.20, grade = "C" },
    { grade = "D" },
}

function H.weave_marker_fraction(swing_duration, effective_cast, latency)
    local weave = st.weave
    if not weave or not weave.get_marker_fraction then
        return nil
    end
    return weave.get_marker_fraction(swing_duration, effective_cast, latency)
end

-- Seconds until the latest safe cast start, through weave.lua's model; nil without it.
function H.weave_safe_start_in(state, now, next_swing_expiration)
    local weave = st.weave
    if not weave or not weave.get_safe_start_in or not state then
        return nil
    end
    return weave.get_safe_start_in(next_swing_expiration, now, state.latency, state.effective_cast)
end

-- Grade a cast start (swing fraction) plus its measured clip amount. Returns grade,
-- marker; grade nil when the inputs cannot be scored.
function H.grade_weave_cast(state, cast_start_fraction, clip_amount)
    if not state then
        return nil
    end
    local marker = H.weave_marker_fraction(state.swing_duration, state.effective_cast, state.latency)
    if marker == nil then
        return nil
    end
    local weave = st.weave
    if weave.is_clipped and weave.is_clipped(clip_amount, cast_start_fraction, marker) then
        return "F", marker
    end
    if type(cast_start_fraction) ~= "number" then
        return nil, marker
    end
    local margin = marker - cast_start_fraction
    if margin < 0 then
        margin = 0
    end
    return H.grade_band(margin, H.WEAVE_MARGIN_BANDS), marker
end

-- SUPERSEDED (operator ruling, 2026-10-19): the class's own drill list owns the
-- weave decision ("shaman_mw_weave" - the same weave.lua maths, re-sourced with
-- the Maelstrom-stack condition). One skill, one truth - the class list wins.
--
-- The built-in spec STAYS registered (the class's session wrappers and their
-- offline pins still resolve the old key - backward compatibility). The engine
-- routes the shaman to its own drill list (the built-in drill is not the session
-- any more) and the built-in drill's grading is delegated to the class's drill.
H.register_scenario({
    key = "shaman_weave",
    title = "Weave-timing drill",
    class = "SHAMAN",
    kind = "weave_timing",
    description = "Spell-weave timing: start the cast before the swing marker, never clip.",
    new_state = function(now, opts)
        opts = opts or {}
        local defaults = H.WEAVE_DEFAULTS
        return {
            swing_duration = opts.swing_duration or defaults.swing_duration,
            effective_cast = opts.effective_cast or defaults.effective_cast,
            latency = opts.latency or defaults.latency,
        }
    end,
    -- Exact-time path: the caller reports each cast start and the shell grades it
    -- through weave.lua's marker/clip model. A number key is the swing fraction with no
    -- measured clip; a table key carries { start = <fraction>, clip = <amount> }.
    -- The grade comes from the CLASS's own drill (the class list is the single
    -- source of the weave rule); the shell's own model is the last-resort fallback
    -- for a flavour that ships no class drill at all.
    event = function(session, now, key)
        local state = session.state
        local start_fraction, clip_amount
        if type(key) == "number" then
            start_fraction = key
        elseif type(key) == "table" and type(key.start) == "number" then
            start_fraction, clip_amount = key.start, key.clip
        else
            return nil
        end
        local delegated = H.delegate_drill_grade("shaman_weave", state, now, key,
            { start = start_fraction, clip = clip_amount })
        if delegated ~= nil then
            return delegated
        end
        local grade = H.grade_weave_cast(state, start_fraction, clip_amount)
        return grade
    end,
    queries = {
        marker_fraction = function(session)
            local state = session.state
            return H.weave_marker_fraction(state.swing_duration, state.effective_cast, state.latency)
        end,
    },
})

--=========================================================================================
-- Rogue drills (Round 2, Slice D)
--=========================================================================================
-- Energy pooling (rogue_research §1.3, CONFIRMED): a 2 s tick, never pool above 65
-- pre-tick / 85 post-tick, and spend the finisher BEFORE the tick that would cap the
-- pool. The drill grades where in the tick cycle the spend starts: the marker is the
-- latest safe start (one latency before the tick), and a start past it is a tick clip
-- (F) because the capped tick already landed. Bands are the shared weave margin bands -
-- a later, tighter spend is the skilled one. A nil marker (ambiguous tick: proc energy /
-- missing reads, the H4 rule) grades nil, never a guessed tick.
H.ROGUE_ENERGY_DEFAULTS = { tick_interval = 2, latency = 0.1 }

function H.energy_tick_marker(state)
    if type(state) ~= "table" or state.tick_known == false then
        return nil
    end
    if type(state.tick_marker) == "number" then
        if state.tick_marker ~= state.tick_marker then
            return nil
        end
        return state.tick_marker
    end
    local interval = state.tick_interval
    if type(interval) ~= "number" or interval ~= interval or interval <= 0 then
        return nil
    end
    local latency = state.latency or 0
    if type(latency) ~= "number" or latency ~= latency or latency < 0 then
        return nil
    end
    local marker = 1 - (latency / interval)
    if marker < 0 then
        marker = 0
    end
    return marker
end

-- Grade one spend start as a fraction of the tick cycle. A measured clip or a start
-- past the marker is F; otherwise the margin to the marker bands through the shared
-- weave bands. A nil marker or a non-number start grades nil (unscored).
function H.grade_energy_spend(state, start_fraction, clip_amount)
    local marker = H.energy_tick_marker(state)
    if marker == nil then
        return nil
    end
    if type(start_fraction) ~= "number" or start_fraction ~= start_fraction then
        return nil, marker
    end
    if type(clip_amount) == "number" and clip_amount > 0 then
        return "F", marker
    end
    if start_fraction > marker then
        return "F", marker
    end
    local margin = marker - start_fraction
    if margin < 0 then
        margin = 0
    end
    return H.grade_band(margin, H.WEAVE_MARGIN_BANDS), marker
end

H.register_scenario({
    key = "rogue_energy_pool",
    title = "Energy-pooling drill",
    class = "ROGUE",
    kind = "energy_loop",
    description = "Spend late in the 2 s energy-tick cycle: start before the tick marker, never cap the pool.",
    new_state = function(now, opts)
        opts = opts or {}
        local defaults = H.ROGUE_ENERGY_DEFAULTS
        return {
            tick_interval = opts.tick_interval or defaults.tick_interval,
            latency = opts.latency or defaults.latency,
            tick_known = opts.tick_known ~= false,
        }
    end,
    -- Exact-time path: a number key is the spend-start fraction of the tick cycle; a
    -- table key is { start = <fraction>, clip = <measured tick clip> }.
    event = function(session, now, key)
        local start_fraction, clip_amount
        if type(key) == "number" then
            start_fraction = key
        elseif type(key) == "table" and type(key.start) == "number" then
            start_fraction, clip_amount = key.start, key.clip
        else
            return nil
        end
        return H.grade_energy_spend(session.state, start_fraction, clip_amount)
    end,
    queries = {
        tick_marker = function(session)
            return H.energy_tick_marker(session.state)
        end,
    },
})

-- Era SS-after-swing (rogue_deep §2.1, CONFIRMED on Classic Era):
-- classicroguecraft.com/swing-timing-guide/ sims a 0.1 s delay after the mainhand
-- swing as perfect and 0.2 s as average (Horde sword +35 vs +26-27 dps). The drill
-- grades that offset: inside [0.1, 0.2] the distance from the 0.1 s ideal bands S..D;
-- anything earlier or later is F (the window was missed). This is an Era-only melee
-- technique - the caller selects the drill on Era, and TBC+ shows no cue (rogue_deep
-- §2.1: Sno removed it deliberately). An unreadable swing record grades nil, never a
-- guessed window.
H.ROGUE_SS_DEFAULTS = { window_start = 0.1, window_end = 0.2, ideal = 0.1 }

H.ROGUE_SS_MARGIN_BANDS = {
    { max = 0.02, grade = "S" },
    { max = 0.04, grade = "A" },
    { max = 0.06, grade = "B" },
    { max = 0.08, grade = "C" },
    { max = 0.10, grade = "D" },
    { grade = "F" },
}

function H.grade_ss_after_swing(state, offset)
    if type(state) ~= "table" or state.swing_known == false then
        return nil
    end
    if type(offset) ~= "number" or offset ~= offset then
        return nil
    end
    local window_start = state.window_start or H.ROGUE_SS_DEFAULTS.window_start
    local window_end = state.window_end or H.ROGUE_SS_DEFAULTS.window_end
    if type(window_start) ~= "number" or window_start ~= window_start
        or type(window_end) ~= "number" or window_end ~= window_end then
        return nil
    end
    if offset < window_start or offset > window_end then
        return "F"
    end
    local ideal = state.ideal or H.ROGUE_SS_DEFAULTS.ideal
    if type(ideal) ~= "number" or ideal ~= ideal then
        return nil
    end
    local delta = offset - ideal
    if delta < 0 then
        delta = -delta
    end
    return H.grade_band(delta, H.ROGUE_SS_MARGIN_BANDS) or "F"
end

H.register_scenario({
    key = "rogue_ss_window",
    title = "SS-after-swing drill",
    class = "ROGUE",
    kind = "swing_window",
    description = "Classic Era sword timing: Sinister Strike 0.1-0.2 s after the mainhand swing lands.",
    new_state = function(now, opts)
        opts = opts or {}
        local defaults = H.ROGUE_SS_DEFAULTS
        return {
            window_start = opts.window_start or defaults.window_start,
            window_end = opts.window_end or defaults.window_end,
            ideal = opts.ideal or defaults.ideal,
            swing_known = opts.swing_known ~= false,
        }
    end,
    -- Exact-time path: a number key is the offset in seconds between the mainhand swing
    -- landing and the Sinister Strike start.
    event = function(session, now, key)
        if type(key) ~= "number" then
            return nil
        end
        return H.grade_ss_after_swing(session.state, key)
    end,
    queries = {
        window = function(session)
            local state = session.state
            return {
                start_time = state.window_start,
                end_time = state.window_end,
                ideal = state.ideal,
            }
        end,
    },
})

--=========================================================================================
-- Hunter post-fight shot analytics (H2)
--=========================================================================================
-- Pure stats math over the hunter shot log (classes/hunter.lua record_shot_sample):
-- samples are plain tables { clipped = bool, latency = seconds|nil, at = seconds }.
-- WoW-free by design (the twist.lua / weave.lua discipline): no globals, no clock
-- reads, every number arrives as an argument. The presentation (the practice-report
-- screen) lives in practice_ui.lua.
--
-- HST proves the demand (bench/competitor_gaps_2026-10-19.md §1.9: clip counter +
-- "optimization hint after a fight" + "how much latency buffer you are using").

-- The hint turns advisory once this fraction of the logged shots clipped.
st.practice.SHOT_CLIP_WARN_RATE = 0.2

-- Summarize a shot log: totals, clip rate and the mean observed latency. count caps
-- the samples read (nil or invalid = the whole array). A non-table log summarizes
-- empty; non-table entries are skipped; samples without a numeric latency simply do
-- not feed the mean. An empty summary scores zeros with a nil mean, never a guess.
function st.practice.summarize_shots(samples, count)
    local summary = { total = 0, clipped = 0, clip_rate = 0, mean_latency = nil }
    if type(samples) ~= "table" then
        return summary
    end
    local n = #samples
    if type(count) == "number" and count >= 0 then
        n = math.min(math.floor(count), n)
    end
    local latency_sum, latency_n = 0, 0
    for i = 1, n do
        local sample = samples[i]
        if type(sample) == "table" then
            summary.total = summary.total + 1
            if sample.clipped == true then
                summary.clipped = summary.clipped + 1
            end
            if type(sample.latency) == "number" then
                latency_sum = latency_sum + sample.latency
                latency_n = latency_n + 1
            end
        end
    end
    if summary.total > 0 then
        summary.clip_rate = summary.clipped / summary.total
    end
    if latency_n > 0 then
        summary.mean_latency = latency_sum / latency_n
    end
    return summary
end

-- Fraction of a cast window eaten by latency (the "how much latency buffer you are
-- using" readout): mean_latency / cast_window. Nil unless the mean is a non-negative
-- number and the window is a positive number.
function st.practice.shot_buffer_fraction(mean_latency, cast_window)
    if type(mean_latency) ~= "number" or type(cast_window) ~= "number"
        or cast_window <= 0 or mean_latency < 0 then
        return nil
    end
    return mean_latency / cast_window
end

-- One-line optimization hint for a shot summary (the "optimization hint after a
-- fight"). Pure and total: every branch is pinned in tests/practice_state.lua.
-- cast_window is the seconds width of the live cast window (the hunter_window
-- cast_window of the observed latency); nil omits the buffer clause, never guesses it.
function st.practice.shot_hint(summary, cast_window)
    if type(summary) ~= "table" or (summary.total or 0) <= 0 then
        return "No shots logged yet."
    end
    local total = summary.total
    local clipped = summary.clipped or 0
    local shots_word = (total == 1) and "shot" or "shots"
    local text
    if clipped <= 0 then
        text = string.format("Clean: no clips in %d %s.", total, shots_word)
    else
        local rate = (summary.clip_rate or 0) * 100
        local tail
        if rate >= st.practice.SHOT_CLIP_WARN_RATE * 100 then
            tail = "Start each cast earlier or widen the cast window."
        else
            tail = "Tighten the next cast start."
        end
        text = string.format("%d of %d %s clipped (%d%%). %s",
            clipped, total, shots_word, math.floor(rate + 0.5), tail)
    end
    local mean = summary.mean_latency
    if type(mean) == "number" and type(cast_window) == "number" and cast_window > 0 then
        local frac = st.practice.shot_buffer_fraction(mean, cast_window)
        if frac ~= nil then
            text = text .. string.format(" Latency %dms of a %dms window (%d%% buffer used).",
                math.floor(mean * 1000 + 0.5), math.floor(cast_window * 1000 + 0.5),
                math.floor(frac * 100 + 0.5))
        end
    end
    return text
end

--=========================================================================================
-- Hunter prepull checklist (hunter_open §2)
--=========================================================================================
-- One-shot APL prepulls are the wrong shape for the per-tick guide engine (no
-- pull-timer input exists on the classic clients), so they live here as pure
-- checklist data for the report layer: the generic union of the three
-- SIM-CONFIRMED prepull sets (TBC Hawk 27044 -20s; SoD Falcon/Aimed/Blood-Fury/
-- Hawk spread; Forever Mark 14325 -22s + Hawk 25296 -20s). Trap/move tech lives
-- in HUNTER_WEAVE_STEPS below (the melee-weave/move-cue checklist). WoW-free by
-- design (the twist.lua / weave.lua discipline): every state arrives as an
-- argument, and the presentation lives in practice_ui.lua.
st.practice.HUNTER_PREPULL_STEPS = {
    { key = "mark",   label = "Hunter's Mark" },
    { key = "aspect", label = "Hawk aspect" },
    { key = "potion", label = "Haste potion" },
}

-- Missing steps for a `have` map (key -> true when done), in checklist order.
-- A non-table `have` misses everything; a nil/false entry is missing (unknown
-- never counts as done). Returns an array of step labels (empty = ready).
function st.practice.hunter_prepull_missing(have)
    local missing = {}
    for i = 1, #st.practice.HUNTER_PREPULL_STEPS do
        local step = st.practice.HUNTER_PREPULL_STEPS[i]
        if type(have) ~= "table" or have[step.key] ~= true then
            missing[#missing + 1] = step.label
        end
    end
    return missing
end

-- One-line readiness readout for a missing list: "Ready." when nothing is
-- missing, else the missing labels joined. Pure and total.
function st.practice.hunter_prepull_hint(missing)
    if type(missing) ~= "table" or #missing == 0 then
        return "Ready."
    end
    return "Prepull: " .. table.concat(missing, ", ") .. "."
end

--=========================================================================================
-- Hunter weave/move-cue checklist (hunter_open §1 + rotation audit §§TBC/SoD/Wrath)
--=========================================================================================
-- The melee-weave/move tech the stateless per-tick engine cannot express (no
-- slot left in any full set, no move/wait input): TBC APL Melee weave=true
-- with Wait-at-melee 400ms and the min(0.5s, 25% swing) buffer; SoD p7
-- 12yd<->5yd moves on autoTimeToNext/gcdTimeToReady; Wrath pre-trap + the
-- 2000ms trap-weave window (presets.ts timeToTrapWeaveMs); SoD Raptor melee
-- fills from the 8yd minimum range. All SIM-CONFIRMED via the fetched sim
-- APLs (bench/hunter_open_2026-10-19.md, bench/hunter_rotation_audit_2026-10-19.md).
-- Pure checklist data for the report layer, the prepull union's sibling:
-- WoW-free by design (the twist.lua / weave.lua discipline), every state
-- arrives as an argument, and the presentation lives in practice_ui.lua.
st.practice.HUNTER_WEAVE_STEPS = {
    { key = "trap",  label = "Trap down before the pull" },
    { key = "melee", label = "Melee weave inside 5 yd" },
    { key = "move",  label = "Move on the swing gap" },
}

-- Missing steps for a `have` map (key -> true when done), in checklist order.
-- A non-table `have` misses everything; a nil/false entry is missing (unknown
-- never counts as done). Returns an array of step labels (empty = set).
function st.practice.hunter_weave_missing(have)
    local missing = {}
    for i = 1, #st.practice.HUNTER_WEAVE_STEPS do
        local step = st.practice.HUNTER_WEAVE_STEPS[i]
        if type(have) ~= "table" or have[step.key] ~= true then
            missing[#missing + 1] = step.label
        end
    end
    return missing
end

-- One-line readiness readout for a missing list: "Weave set." when nothing is
-- missing, else the missing labels joined. Pure and total.
function st.practice.hunter_weave_hint(missing)
    if type(missing) ~= "table" or #missing == 0 then
        return "Weave set."
    end
    return "Weave: " .. table.concat(missing, ", ") .. "."
end

--=========================================================================================
-- Combat resource pools (sim-resources lane)
--=========================================================================================
-- Pure resource math for the practice drills: generation follows the sim's rules,
-- costs follow the sim's numbers, timing rides the caller's clock (gains apply on
-- the caller's swing/tick events). WoW-free by design (the twist.lua / weave.lua
-- discipline): every number arrives as an argument or a cited constant below.
--
-- Rage (warrior, FIRST per operator order). Generation, cap and costs are
-- SIM-CONFIRMED from wowsims/classic (fetched 2026-10-19):
--   * sim/core/rage.go: MaxRage = 100.0; white (MH/OH auto only) generation is
--     damage * 7.5 / rageConversion; damage-taken generation is
--     damage * 2.5 / conversion; misses generate nothing; dodges/parries use
--     the pre-outcome damage; Bloodthirst refunds 0.8 of its cost on a miss.
--   * sim/core/rage.go GetRageConversion: level 25 -> 82.25 and level 40 ->
--     140.5 (both tested); below 45 a linear fit; otherwise the quadratic base
--     formula (target-adjusted in game per the Kalgan post, so the sim value is
--     the base). The sim's <45 branch squares with Go's ^ (xor) operator; the
--     pool below uses the true square the formula intends (the level-60+ path
--     every drill uses is unaffected either way).
--   * sim/warrior/bloodthirst.go: BT 23894, cost 30, CD 6 s.
--     sim/warrior/whirlwind.go: WW 1680, cost 25, CD 10 s.
--     sim/warrior/slam.go: Slam 11605, cost 15 (plus the swing reset).
--     sim/warrior/overpower.go: OP rage 5, 5 s proc window.
--     sim/warrior/execute.go (TBC/SoD): Execute drains ALL rage.
--     (Costs banked in bench/warrior_rotation_audit_2026-10-19.md.)
-- Heroic Strike / Cleave costs are rank-variable and NOT tabled here: the live
-- read is classes/warrior.lua rage_cost_of (GetSpellPowerCost on the client's
-- own ranks) - the drill feeds the cost as an argument, never a guessed table.
--
-- Mana: only the pool mechanics live here (cap, fail-closed spend). Fixed costs
-- and regen are NOT modelled: costs are rank-dependent per client (live via
-- GetSpellPowerCost; paladin seams classes/paladin.lua get_guide_mana_pct +
-- twist_mana_threshold) and regen is spirit/gear/buff-dependent under the 5 s
-- rule - no offline source in tree. FILED, not faked.
-- Focus (hunter, Cata+ only): only the pool mechanics live here. Costs and
-- regen (Steady-gen and friends) need cata-sim numbers not in tree, and the
-- hunter drill grades forced-move windows with no costed casts. FILED, not
-- faked.
-- Energy: already modelled (H.POWERSHIFT_DEFAULTS + H.ROGUE_ENERGY_DEFAULTS) -
-- untouched.
--=========================================================================================

-- Rage constants (wowsims/classic sim/core/rage.go + bloodthirst.go above).
st.practice.RAGE_MAX = 100
st.practice.RAGE_DEALT_MULT = 7.5
st.practice.RAGE_TAKEN_MULT = 2.5
st.practice.RAGE_BT_REFUND = 0.8

-- Fixed warrior ability costs (bench/warrior_rotation_audit_2026-10-19.md; the
-- sim spell files behind each number). Execute has no fixed cost (drains all);
-- HS/Cleave are caller-fed (rank-variable, see the header).
st.practice.WARRIOR_RAGE_COSTS = { bt = 30, ww = 25, slam = 15, op = 5 }

-- Rage conversion value for an attacker level (sim GetRageConversion). Nil on a
-- non-positive or unreadable level (never a conversion on a guess).
function st.practice.rage_conversion(level)
    if type(level) ~= "number" or level ~= level or level <= 0 then
        return nil
    end
    if level == 25 then
        return 82.25
    end
    if level == 40 then
        return 140.5
    end
    if level < 45 then
        return 0.0215 * level * level + 2.66 * level + 0.89
    end
    return 0.0091107836 * level * level + 3.225598133 * level + 4.2652911
end

-- Rage from one landed white swing (sim OnSpellHitDealt): damage * mult /
-- conversion. The caller passes the pre-outcome damage for dodges/parries and
-- nil for a miss (misses generate nothing - unknown-hides, never zero-filled
-- by the pool). mult defaults to RAGE_DEALT_MULT.
function st.practice.rage_white_gain(damage, conversion, mult)
    if type(damage) ~= "number" or damage ~= damage or damage <= 0 then
        return nil
    end
    if type(conversion) ~= "number" or conversion ~= conversion or conversion <= 0 then
        return nil
    end
    local m = mult
    if type(m) ~= "number" or m ~= m or m <= 0 then
        m = st.practice.RAGE_DEALT_MULT
    end
    return damage * m / conversion
end

-- Rage from damage taken (sim OnSpellHitTaken): damage * mult / conversion
-- with the TAKEN default. Same nil discipline as the white path.
function st.practice.rage_taken_gain(damage, conversion, mult)
    if type(damage) ~= "number" or damage ~= damage or damage <= 0 then
        return nil
    end
    if type(conversion) ~= "number" or conversion ~= conversion or conversion <= 0 then
        return nil
    end
    local m = mult
    if type(m) ~= "number" or m ~= m or m <= 0 then
        m = st.practice.RAGE_TAKEN_MULT
    end
    return damage * m / conversion
end

-- Fresh rage pool (sim rageBar currentRage/MaxRage). max defaults to RAGE_MAX;
-- a starting value clamps into [0, max]. Unknown options read as empty.
function st.practice.new_rage_state(opts)
    opts = opts or {}
    local max = opts.max
    if type(max) ~= "number" or max ~= max or max <= 0 then
        max = st.practice.RAGE_MAX
    end
    local rage = opts.rage
    if type(rage) ~= "number" or rage ~= rage then
        rage = 0
    end
    if rage < 0 then
        rage = 0
    end
    if rage > max then
        rage = max
    end
    return { rage = rage, max = max }
end

-- Bank a rage gain, capped at the pool max (sim AddRage). Non-positive or
-- unreadable amounts bank nothing and read nil (never a guess).
function st.practice.rage_gain(state, amount)
    if type(state) ~= "table" then
        return nil
    end
    if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
        return nil
    end
    local rage = (state.rage or 0) + amount
    local max = state.max or st.practice.RAGE_MAX
    if rage > max then
        rage = max
    end
    state.rage = rage
    return rage
end

-- Spend rage for one ability (sim SpendRage, fail-closed): true and deducted
-- when the pool covers the cost, false and untouched otherwise. Unknown,
-- NaN or negative costs never spend (never a guess); a zero cost is a free
-- no-op. Unlike the live rotation gate (which degrades to ALLOW on unknown
-- reads so prompting continues), the pool must not spend what it cannot see.
function st.practice.rage_spend(state, cost)
    if type(state) ~= "table" then
        return false
    end
    if type(cost) ~= "number" or cost ~= cost or cost < 0 then
        return false
    end
    if cost == 0 then
        return true
    end
    local rage = state.rage or 0
    if rage ~= rage or rage < cost then
        return false
    end
    state.rage = rage - cost
    return true
end

-- Execute: drain the whole pool (sim execute.go drains ALL rage). Returns the
-- rage consumed (0 on an empty or unreadable pool), never nil on a table.
function st.practice.rage_drain_all(state)
    if type(state) ~= "table" then
        return nil
    end
    local drained = state.rage or 0
    if type(drained) ~= "number" or drained ~= drained or drained < 0 then
        drained = 0
    end
    state.rage = 0
    return drained
end

-- Affordability over the pool (sim-pool twin of ST.WARRIOR.composite_rage_gate
-- in classes/warrior.lua): true when the pool covers cost + reserve. The live
-- gate degrades to ALLOW on unknown reads; the pool fails closed instead (an
-- unreadable pool or cost is not spendable). A nil/NaN reserve counts as 0.
function st.practice.rage_can_spend(state, cost, reserve)
    local rage = type(state) == "table" and state.rage or nil
    if type(rage) ~= "number" or rage ~= rage then
        return false
    end
    if type(cost) ~= "number" or cost ~= cost or cost < 0 then
        return false
    end
    local reserved = reserve
    if type(reserved) ~= "number" or reserved ~= reserved or reserved < 0 then
        reserved = 0
    end
    return rage >= cost + reserved
end

-- Drill-spend grade for the shared score pipeline: S when the pool covers
-- cost + reserve (the spend leaves the core intact), F when it would starve
-- it. Nil when the inputs cannot be judged (never a grade on a guess).
function st.practice.rage_spend_grade(state, cost, reserve)
    if type(state) ~= "table" then
        return nil
    end
    if type(cost) ~= "number" or cost ~= cost or cost < 0 then
        return nil
    end
    if type(state.rage) ~= "number" or state.rage ~= state.rage then
        return nil
    end
    if st.practice.rage_can_spend(state, cost, reserve) then
        return "S"
    end
    return "F"
end

-- Fresh mana pool. max is caller-fed (level/gear/buff-dependent, no offline
-- source): nil means an uncapped pool that still spends fail-closed.
function st.practice.new_mana_state(opts)
    opts = opts or {}
    local max = opts.max
    if type(max) ~= "number" or max ~= max or max <= 0 then
        max = nil
    end
    local mana = opts.mana
    if type(mana) ~= "number" or mana ~= mana then
        mana = 0
    end
    if mana < 0 then
        mana = 0
    end
    if max and mana > max then
        mana = max
    end
    return { mana = mana, max = max }
end

-- Bank mana, capped only when the max is known. Same nil discipline as rage.
function st.practice.mana_gain(state, amount)
    if type(state) ~= "table" then
        return nil
    end
    if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
        return nil
    end
    local mana = (state.mana or 0) + amount
    if type(state.max) == "number" and mana > state.max then
        mana = state.max
    end
    state.mana = mana
    return mana
end

-- Spend mana, fail-closed (mirrors rage_spend; the live cost feed is owed -
-- see the header).
function st.practice.mana_spend(state, cost)
    if type(state) ~= "table" then
        return false
    end
    if type(cost) ~= "number" or cost ~= cost or cost < 0 then
        return false
    end
    if cost == 0 then
        return true
    end
    local mana = state.mana or 0
    if mana ~= mana or mana < cost then
        return false
    end
    state.mana = mana - cost
    return true
end

-- Mana affordability (same gate shape as rage_can_spend; unknown fails closed).
function st.practice.mana_can_spend(state, cost)
    local mana = type(state) == "table" and state.mana or nil
    if type(mana) ~= "number" or mana ~= mana then
        return false
    end
    if type(cost) ~= "number" or cost ~= cost or cost < 0 then
        return false
    end
    return mana >= cost
end

-- Fresh focus pool (hunter, Cata+ only). max is caller-fed like mana: the
-- client cap with no offline source in tree. Costs/regen are filed (header).
function st.practice.new_focus_state(opts)
    opts = opts or {}
    local max = opts.max
    if type(max) ~= "number" or max ~= max or max <= 0 then
        max = nil
    end
    local focus = opts.focus
    if type(focus) ~= "number" or focus ~= focus then
        focus = 0
    end
    if focus < 0 then
        focus = 0
    end
    if max and focus > max then
        focus = max
    end
    return { focus = focus, max = max }
end

-- Bank focus, capped only when the max is known.
function st.practice.focus_gain(state, amount)
    if type(state) ~= "table" then
        return nil
    end
    if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
        return nil
    end
    local focus = (state.focus or 0) + amount
    if type(state.max) == "number" and focus > state.max then
        focus = state.max
    end
    state.focus = focus
    return focus
end

-- Spend focus, fail-closed (mirrors rage_spend).
function st.practice.focus_spend(state, cost)
    if type(state) ~= "table" then
        return false
    end
    if type(cost) ~= "number" or cost ~= cost or cost < 0 then
        return false
    end
    if cost == 0 then
        return true
    end
    local focus = state.focus or 0
    if focus ~= focus or focus < cost then
        return false
    end
    state.focus = focus - cost
    return true
end

-- Focus affordability (same gate shape as mana_can_spend).
function st.practice.focus_can_spend(state, cost)
    local focus = type(state) == "table" and state.focus or nil
    if type(focus) ~= "number" or focus ~= focus then
        return false
    end
    if type(cost) ~= "number" or cost ~= cost or cost < 0 then
        return false
    end
    return focus >= cost
end

--=========================================================================================
-- Rotation scenario + drill contract (the shared engine the per-class lanes plug into)
--=========================================================================================
-- The operator taxonomy (2026-10-19, bench/class_features_drills_2026-10-19.md §1):
--   SCENARIO = run the class's actual wowsims rotation end to end and grade the
--               sequence the player cast. It is the primary practice mode.
--   DRILL    = a focused single-skill trainer (twist timing, weave fit, powershift,
--               forced-move, execute phase). A class may own several.
--
-- The class contract (fixed by the orchestrator; the six per-class lanes code
-- against exactly this - do not change it):
--
--   ST.<CLASS>.practice_scenario_step(self, ctx)
--     -> { action = "<spell key>", reason = "<text>" } | nil
--     -> { action = nil, hold = true, reason = "<text>" }   -- an explicit HOLD
--     ctx = { now, last_action, resources, cooldowns }
--     `self` is the addon (ST) - exactly like ST.<CLASS>.gather_guide_inputs(self, out).
--     nil means "cannot decide": the engine grades that step UNKNOWN. It never
--     records a wrong action and never invents an expectation.
--
--     The HOLD statement (operator ruling HU-8, hands-up 2026-10-19: a hold is a
--     DECISION, unknown is not). A class that decides to hold says so explicitly
--     (`action = nil, hold = true`); the engine then grades the step as a hold:
--     casting any action during it is an ILLEGAL CAST (F), doing nothing during
--     it is CORRECT - recorded, but never worth points (a player could otherwise
--     farm them by idling, so a correct hold records no attempt at all). A nil
--     step with NO hold statement stays UNKNOWN: no attempt, never a wrong grade.
--     A step that names an action is an action - the hold flag is ignored, so a
--     class that means to hold must not name an action.
--
--   ST.<CLASS>.practice_drills
--     = { { key = "<registry key>", label = "<label>",
--          grade = function(self, ctx) -> "S"|"A"|"B"|"C"|"D"|"F"|nil end }, ... }
--     A nil grade means "not judgeable": the engine shows UNKNOWN and records no
--     attempt (a grade is never guessed).
--
--   ST.<CLASS>.practice_neutral_actions
--     = { heal = true, shield = true }                  -- the same set everywhere
--     = { ERA = { heal = true }, TBC = { heal = true } } -- per family
--     The NEUTRAL action set: the action keys that are legitimate but NOT
--     rotation actions (a heal, a shield, food, a potion, a movement ability).
--     The panel offers the class's whole ability list, so a player can press an
--     action the rotation never asks for; that press is NOT a mis-pick. The step
--     is NEUTRAL: no attempt is recorded (no points, no streak, no XP) and the
--     run counts it in its neutral tally.
--     A class that publishes NOTHING leaves every non-rotation press a mis-pick,
--     exactly as before - the engine never guesses a neutral set.
--
-- Everything below is PURE: no clock read, no randomness, no WoW API. The caller
-- injects `now` and the class's answers; this module owns the comparison, the
-- outcome classes and the grade.
--=========================================================================================

-- The addon object (the AceAddon table): the CLASS MODULES live there
-- (ST.PALADIN, ST.WARRIOR, ...), not on this module's namespace table. The
-- lookup is guarded on purpose: the offline sandbox (and any flavour without
-- the addon object) has no LibStub, and the namespace table is the fallback -
-- never the first place looked at.
local function addon_object()
    if type(LibStub) ~= "function" then
        return nil
    end
    local ok, ace = pcall(LibStub, "AceAddon-3.0")
    if not ok or type(ace) ~= "table" or type(ace.GetAddon) ~= "function" then
        return nil
    end
    local ok_get, addon = pcall(ace.GetAddon, ace, addon_name)
    if not ok_get or type(addon) ~= "table" then
        return nil
    end
    return addon
end

-- The built-in drills a class's OWN drill list supersedes (operator ruling,
-- 2026-10-19: one skill, one truth - the class list wins). The built-in spec
-- stays registered so the class's session wrappers and their offline pins still
-- resolve the old key; what the ruling changes is:
--   * the engine routes the class to its own drill list instead of the built-in
--     drill (the built-in drill is not the session any more), and
--   * the built-in drill's grading is DELEGATED to the class's drill, so the old
--     truth never grades a player attempt.
--
-- The mapping is per built-in key and names the class's drill that owns the
-- skill. A built-in drill with no entry here is still the class's own drill
-- (the class's list does not cover its skill) and keeps its grading.
H.SUPERSEDED_DRILLS = {
    druid_powershift = "druid_powershift_rework",
    shaman_weave = "shaman_mw_weave",
    warrior_execute = "warrior_execute_burn",
}

-- The context a delegated built-in drill hands its class's drill: the shell's own
-- state (flat - the class graders read the flat names first), the clock and the
-- action, with the numeric state fields also published as the resources view.
function H.drill_context(state, now, last_action, extra)
    local ctx = { now = now, last_action = last_action }
    local resources = {}
    if type(state) == "table" then
        for key, value in pairs(state) do
            if ctx[key] == nil then
                ctx[key] = value
            end
            if type(value) == "number" then
                resources[key] = value
            end
        end
    end
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            ctx[key] = value
        end
    end
    if next(resources) ~= nil then
        ctx.resources = resources
    end
    return ctx
end

-- Grade through the class's own drill when a built-in drill is superseded by it.
-- Returns nil when there is no such class drill (the caller keeps its own
-- model), and nil when the class's grader cannot judge (never a guessed grade).
function H.delegate_drill_grade(scenario_key, state, now, last_action, extra)
    local drill_key = H.SUPERSEDED_DRILLS[scenario_key]
    if type(drill_key) ~= "string" or drill_key == "" then
        return nil
    end
    local spec = H.SCENARIOS[scenario_key]
    local class_key = spec and spec.class or nil
    local module = H.practice_class_module(class_key)
    if not module then
        return nil
    end
    local addon = addon_object()
    if not addon then
        return nil
    end
    local ctx = H.drill_context(state, now, last_action, extra)
    return H.practice_drill_grade(module, drill_key, addon, ctx)
end

-- The class module that owns the practice contract. The argument is the class
-- module itself or a class key.
--
-- A class key is resolved from the ADDON OBJECT (the AceAddon table) FIRST:
-- that is where the class tables live, so the engine finds a class's
-- practice_scenario_step / practice_drills without any per-class alias. The
-- namespace table (this module's own table) is the fallback only, and the
-- lookup is nil-safe per class: an unknown class answers nil, never a throw and
-- never another class's module.
function H.practice_class_module(class_or_module)
    if type(class_or_module) == "table" then
        return class_or_module
    end
    if type(class_or_module) ~= "string" or class_or_module == "" then
        return nil
    end
    local addon = addon_object()
    if addon then
        local module = addon[class_or_module]
        if type(module) == "table" then
            return module
        end
    end
    local module = st[class_or_module]
    if type(module) ~= "table" then
        return nil
    end
    return module
end

-- Does the class provide a rotation scenario? (the class lane owns the answer)
function H.practice_scenario_available(class_key)
    local module = H.practice_class_module(class_key)
    if not module then
        return false
    end
    return type(module.practice_scenario_step) == "function"
end

-- Ask the class what it wants cast next.
--   -> { action = "<key>", reason = "<text>" } | nil
--   -> { action = nil, hold = true, reason = "<text>" }   -- an explicit HOLD
-- nil covers every "cannot decide" case: no class module, no step function, a
-- throwing step, a non-table answer, an empty action, a step that names neither
-- an action nor a hold. The engine treats them all the same way - the step is
-- UNKNOWN, never a wrong action.
--
-- The hold statement (HU-8) is the one answer that is NOT "cannot decide": a
-- class that holds has DECIDED, so the step is a hold - the player casting
-- during it is wrong and the player doing nothing is right.
function H.practice_scenario_step(class_key, self, ctx)
    local module = H.practice_class_module(class_key)
    if not module or type(module.practice_scenario_step) ~= "function" then
        return nil
    end
    local ok, result = pcall(module.practice_scenario_step, self, ctx)
    if not ok or type(result) ~= "table" then
        return nil
    end
    local action = result.action
    local reason = result.reason
    if type(reason) ~= "string" then
        reason = nil
    end
    if type(action) ~= "string" or action == "" then
        -- No action: the only non-unknown answer left is an explicit hold.
        if result.hold == true then
            return { action = nil, hold = true, reason = reason }
        end
        return nil
    end
    -- An action was named: this is a decision to cast, whatever the hold flag says.
    return { action = action, reason = reason }
end

-- The class's drill list: the entries that carry a key and a grade function. A
-- malformed entry (no key, no grader) is dropped - unknown-hides: the panel never
-- offers a button that cannot be graded.
function H.practice_drills(class_key)
    local module = H.practice_class_module(class_key)
    if not module then
        return nil
    end
    local list = module.practice_drills
    if type(list) ~= "table" then
        return nil
    end
    local out = {}
    for i = 1, #list do
        local entry = list[i]
        if type(entry) == "table" and type(entry.key) == "string" and entry.key ~= ""
            and type(entry.grade) == "function" then
            out[#out + 1] = {
                key = entry.key,
                label = (type(entry.label) == "string" and entry.label ~= "") and entry.label or entry.key,
                grade = entry.grade,
            }
        end
    end
    if #out == 0 then
        return nil
    end
    return out
end

-- One drill of a class by its registry key, or nil.
function H.practice_drill_by_key(class_key, drill_key)
    if type(drill_key) ~= "string" or drill_key == "" then
        return nil
    end
    local drills = H.practice_drills(class_key)
    if not drills then
        return nil
    end
    for i = 1, #drills do
        if drills[i].key == drill_key then
            return drills[i]
        end
    end
    return nil
end

-- Grade one drill attempt. A nil grade means "not judgeable" (the engine shows
-- UNKNOWN); a throwing grader is the same - it never invents a grade.
function H.practice_drill_grade(class_key, drill_key, self, ctx)
    local drill = H.practice_drill_by_key(class_key, drill_key)
    if not drill then
        return nil
    end
    local ok, grade = pcall(drill.grade, self, ctx)
    if not ok or type(grade) ~= "string" then
        return nil
    end
    if not st.practice.GRADE_POINTS[grade] then
        return nil
    end
    return grade
end

-- The class's NEUTRAL action set: the action keys that are legitimate but NOT
-- rotation actions (a heal, a shield, food, a potion, a movement ability).
--
-- The published shape is the class's own statement:
--   { heal = true, shield = true }                   -- the same set everywhere
--   { ERA = { heal = true }, TBC = { heal = true } } -- per family
--
-- A family-scoped publish (a table-valued entry) is resolved for the CURRENT
-- family (st.family). A family the class published no bucket for answers nil:
-- the engine never guesses a set for a client the class did not describe.
--
-- The returned set is a fresh table of `key = true` entries (the published table
-- is never handed out), and nil means "this class published no neutral set" -
-- unknown-hides: the caller then grades every non-rotation press as it did
-- before, a mis-pick.
--
-- The argument is a class key OR the class module itself (the same shape
-- H.practice_class_module accepts).
function H.practice_neutral_actions(class_key)
    local module = H.practice_class_module(class_key)
    if not module then
        return nil
    end
    local published = module.practice_neutral_actions
    if type(published) ~= "table" then
        return nil
    end
    local source = published
    -- A table-valued entry means the publish is family-scoped.
    local family_scoped = false
    for _, value in pairs(published) do
        if type(value) == "table" then
            family_scoped = true
            break
        end
    end
    if family_scoped then
        local family = st.family
        if type(family) ~= "string" or family == "" then
            return nil
        end
        source = published[family]
        if type(source) ~= "table" then
            return nil
        end
    end
    local out = {}
    for key, value in pairs(source) do
        if type(key) == "string" and key ~= "" and value == true then
            out[key] = true
        end
    end
    if next(out) == nil then
        return nil
    end
    return out
end

-- The CANONICAL key of an action key: the class's own alias table maps every
-- spelling the engine, the practice sim or the guide may report onto the
-- canonical key (the paladin's "consecration" -> "cons"; the sim's own
-- "consec" -> "cons"). A class with a single key space publishes no table, and
-- the normaliser is then the identity.
--
-- WHY IT EXISTS: the panel offers every action under its canonical key and the
-- grader compares canonical keys, so a press is graded by the SPELL it
-- represents and not by the spelling that reached the engine. Without it the
-- paladin's icon button ("consecration") and the rotation's own key ("cons")
-- were two different actions, and pressing the spell the prompt named graded
-- OUT OF ORDER - an F, a broken streak and no XP.
--
-- The argument is a class key OR the class module itself (the same shape
-- H.practice_class_module accepts). A key that is not a string, a class that
-- publishes no normaliser and a normaliser that answers nothing all answer the
-- key UNCHANGED - the identity is the one safe fallback.
function H.practice_canonical_key(class_key, key)
    if type(key) ~= "string" or key == "" then
        return key
    end
    local module = H.practice_class_module(class_key)
    if type(module) ~= "table" then
        return key
    end
    local normaliser = module.practice_canonical_key
    if type(normaliser) ~= "function" then
        return key
    end
    local ok, canonical = pcall(normaliser, key)
    if not ok or type(canonical) ~= "string" or canonical == "" then
        return key
    end
    return canonical
end

-- The run length: [DESIGN] ten GCD chains, so every class's scenario produces the
-- same number of decisions (the audit's per-class bands are written for it).
H.ROTATION_RUN_STEPS = 10

-- The run grade bands on the mis-pick count. A miss counts as a mis-pick: the
-- rotation wanted an action and the player did not cast it. [DESIGN] - addon
-- policy, not a sim number (the audit's UNCONFIRMED ledger U-15).
H.ROTATION_RUN_BANDS = {
    { max = 0,    grade = "S" },
    { max = 1,    grade = "A" },
    { max = 2,    grade = "B" },
    { max = 3,    grade = "C" },
    { max = 5,    grade = "D" },
    { grade = "F" },
}

-- The outcome classes of one decision.
H.ROTATION_OUTCOMES = {
    correct = true,      -- the cast matched the expected action
    out_of_order = true, -- a different action was cast
    miss = true,         -- nothing was cast before the step closed
    unknown = true,      -- the class could not decide: nothing to compare
    hold_ok = true,      -- nothing was cast during an explicit hold: correct
    illegal_cast = true, -- an action was cast during an explicit hold: wrong
    neutral = true,      -- a neutral action was cast: legitimate, not asked for
}

-- The attempt grade each outcome feeds to the scoring model: a correct decision
-- is a perfect hit (S), a wrong or missing one is a miss (F, zero points). An
-- unknown decision records NO attempt at all.
--
-- A CORRECT HOLD has no entry here, and that absence IS the rule (HU-8): the
-- hold was the right thing to do, so the step counts as correct in the run, but
-- it must never feed the scoring model - a player could otherwise farm points by
-- idling. A NEUTRAL action has no entry here for the same reason: the player did
-- nothing wrong, so the step records no attempt and awards no points (and it is
-- not a mis-pick either). This map is the single gate for "an attempt happened":
-- an outcome without a grade records no attempt and awards no points.
H.ROTATION_OUTCOME_GRADES = {
    correct = "S",
    out_of_order = "F",
    miss = "F",
    illegal_cast = "F",
}

-- A fresh rotation run.
function H.new_rotation_run(opts)
    opts = opts or {}
    local max_steps = opts.max_steps
    if type(max_steps) ~= "number" or max_steps ~= max_steps or max_steps < 1 then
        max_steps = H.ROTATION_RUN_STEPS
    end
    max_steps = math.floor(max_steps)
    return {
        max_steps = max_steps,
        steps = 0,
        decisions = {},
        correct = 0,
        mispicks = 0,
        misses = 0,
        unknown = 0,
        holds = 0,
        illegal_casts = 0,
        neutral = 0,
        finished = false,
    }
end

-- Close one decision.
--   expected = the action the class wanted (nil = the class could not decide)
--   actual   = the action the player cast (nil = nothing was cast)
--   hold     = true when the class stated an explicit HOLD for this step (HU-8)
--   neutral  = the class's neutral action set (nil = the class published none):
--              an action in that set is legitimate but was not asked for, so the
--              step is NEUTRAL - no attempt, no points, no mis-pick.
-- Returns the decision record, or nil when the run is already finished.
function H.rotation_run_decide(run, expected, actual, hold, neutral)
    if type(run) ~= "table" or run.finished == true then
        return nil
    end
    local has_expected = type(expected) == "string" and expected ~= ""
    local has_actual = type(actual) == "string" and actual ~= ""
    local is_hold = hold == true
    local is_neutral = has_actual and type(neutral) == "table" and neutral[actual] == true
    local outcome
    if is_hold then
        -- A hold is a DECISION (HU-8): casting during it is wrong (F), doing
        -- nothing during it is right (and worth nothing - the grade map has no
        -- entry for a correct hold, so no attempt is recorded).
        --
        -- The hold wins over the neutral set: the class stated "cast nothing",
        -- the prompt says so, and a player who casts anyway is doing the thing
        -- the rotation forbade. Letting a neutral press skip the illegal cast
        -- would make the grading free (spam a heal through every hold).
        if has_actual then
            outcome = "illegal_cast"
        else
            outcome = "hold_ok"
        end
    elseif has_expected and has_actual and actual == expected then
        -- The rotation action itself: unaffected by the neutral set (a class
        -- that published a rotation action as neutral still gets its hit).
        outcome = "correct"
    elseif is_neutral then
        -- A legitimate action the rotation did not ask for: no attempt, no
        -- points, no streak - and NOT a mis-pick either.
        outcome = "neutral"
    elseif not has_expected then
        outcome = "unknown"
    elseif not has_actual then
        outcome = "miss"
    else
        outcome = "out_of_order"
    end
    run.steps = (run.steps or 0) + 1
    local decision = {
        index = run.steps,
        outcome = outcome,
        expected = has_expected and expected or nil,
        actual = has_actual and actual or nil,
        hold = is_hold or nil,
        neutral = is_neutral or nil,
    }
    run.decisions[run.steps] = decision
    if outcome == "correct" then
        run.correct = (run.correct or 0) + 1
    elseif outcome == "hold_ok" then
        -- A correct hold is a correct decision, and it is counted as one - but it
        -- is not a graded attempt (no points, no streak, no mastery tick).
        run.correct = (run.correct or 0) + 1
        run.holds = (run.holds or 0) + 1
    elseif outcome == "neutral" then
        -- A neutral action is neither a hit nor a mis-pick: it is counted in its
        -- own tally (the summary shows it) and it feeds the scoring model not at
        -- all (the grade map has no entry for it).
        run.neutral = (run.neutral or 0) + 1
    elseif outcome == "out_of_order" then
        run.mispicks = (run.mispicks or 0) + 1
    elseif outcome == "illegal_cast" then
        -- An illegal cast is a mis-pick: it counts against the run's band.
        run.mispicks = (run.mispicks or 0) + 1
        run.illegal_casts = (run.illegal_casts or 0) + 1
    elseif outcome == "miss" then
        run.misses = (run.misses or 0) + 1
    else
        run.unknown = (run.unknown or 0) + 1
    end
    if run.steps >= run.max_steps then
        run.finished = true
    end
    return decision
end

-- The run's summary. `grade` is nil when nothing in the run was gradeable (every
-- step unknown): the run reads UNKNOWN, never a perfect S.
function H.rotation_run_summary(run)
    if type(run) ~= "table" then
        return nil
    end
    local mispicks = (run.mispicks or 0) + (run.misses or 0)
    local graded = (run.correct or 0) + mispicks
    return {
        steps = run.steps or 0,
        max_steps = run.max_steps or H.ROTATION_RUN_STEPS,
        correct = run.correct or 0,
        mispicks = run.mispicks or 0,
        misses = run.misses or 0,
        unknown = run.unknown or 0,
        holds = run.holds or 0,
        illegal_casts = run.illegal_casts or 0,
        neutral = run.neutral or 0,
        grade = (graded > 0) and H.grade_band(mispicks, H.ROTATION_RUN_BANDS) or nil,
        finished = run.finished == true,
    }
end
