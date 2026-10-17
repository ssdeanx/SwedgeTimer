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
local _, st = ...

st.practice = st.practice or {}

-- Seconds the older seal keeps twisting after a new seal is cast (archive sim_cast_seal).
st.practice.SEAL_FADE_SECONDS = 0.4

-- Ability definitions (archive 132-143, verbatim). "stop" is the stopattack action;
-- cast("stop") routes to pause_attack(). Seals have no cooldown; hpot/abacus have their
-- own activation rules; aw carries its buff duration.
st.practice.ABILITIES = {
    soc    = { name = "Seal of Command",        spell_id = 20375, type = "seal",    cooldown = 0, seal_label = "command" },
    sob    = { name = "Seal of Blood",          spell_id = 31892, type = "seal",    cooldown = 0, seal_label = "blood" },
    sotc   = { name = "Seal of the Crusader",   spell_id = 21082, type = "seal",    cooldown = 0, seal_label = "crusader" },
    cs     = { name = "Crusader Strike",        spell_id = 35395, type = "ability", cooldown = 6 },
    judge  = { name = "Judgement",              spell_id = 20271, type = "ability", cooldown = 8 },
    consec = { name = "Consecration",           spell_id = 26573, type = "ability", cooldown = 8 },
    aw     = { name = "Avenging Wrath",         spell_id = 31884, type = "buff",    cooldown = 180, duration = 20 },
    hpot   = { name = "Haste Potion",           spell_id = 28507, type = "haste_consumable", cooldown = 0, duration = 15 },
    abacus = { name = "Abacus of Violent Odds", spell_id = 33807, type = "haste_trinket",    cooldown = 120, duration = 10 },
    stop   = { name = "Stop Attack", texture = "Interface\\Icons\\Ability_DualWield", type = "stopattack", cooldown = 0 },
}

-- UI/keybind order (archive 146).
st.practice.ABILITY_ORDER = { "soc", "sob", "cs", "judge", "sotc", "consec", "aw", "hpot", "abacus", "stop" }

-- Locked-rotation presets (archive 122-127): speed/gcd pairs that force a rotation via
-- determine_rotation(). While locked, apply_haste() uses these and ignores all haste.
st.practice.PRESETS = {
    ["1/2"] = { speed = 3.5, gcd = 1.5  },
    ["2/3"] = { speed = 2.3, gcd = 1.15 },
    ["2/4"] = { speed = 1.8, gcd = 1.15 },
}

-- Session-local default keybinds (archive reset_all_mappings 3952-3956): the practice
-- UI copies this into its own table at session start. Persistence (the archived
-- practice_key_* db keys) needs new options and is deliberately not wired here.
st.practice.DEFAULT_KEYBINDS = {
    soc = "1", sob = "2", cs = "3", judge = "4", sotc = "5",
    consec = "6", aw = "7", hpot = "8", abacus = "9", stop = "",
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
    if base:find("^CTRL%-") then mods = "C"; base = base:sub(6) end
    if base:find("^SHIFT%-") then mods = "S"; base = base:sub(7) end
    if base:find("^ALT%-") then mods = "A"; base = base:sub(5) end

    local np = base:match("^NUMPAD(.+)")
    if np then
        local np_map = {
            DECIMAL = ".", PLUS = "+", MINUS = "-", MULTIPLY = "*", DIVIDE = "/",
        }
        base = "N" .. (np_map[np] or np)
    end

    if base == "MOUSEWHEELUP" then base = "MU"
    elseif base == "MOUSEWHEELDOWN" then base = "MD"
    elseif base:match("^BUTTON(%d)") then base = "M" .. base:match("^BUTTON(%d)")
    end

    local pad_map = {
        PAD1 = "P1", PAD2 = "P2", PAD3 = "P3", PAD4 = "P4",
        PADLSHOULDER = "LB", PADRSHOULDER = "RB",
        PADLTRIGGER = "LT", PADRTRIGGER = "RT",
        PADLSTICK = "LS", PADRSTICK = "RS",
        PADDUP = "DU", PADDDOWN = "DD", PADDLEFT = "DL", PADDRIGHT = "DR",
        PADFORWARD = "FW", PADBACK = "BK",
        PADLSTICKUP = "LU", PADLSTICKDOWN = "LD",
        PADLSTICKLEFT = "LL", PADLSTICKRIGHT = "LR",
        PADRSTICKUP = "RU", PADRSTICKDOWN = "RD",
        PADRSTICKLEFT = "RL", PADRSTICKRIGHT = "RR",
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
        active_seals = {},          -- [seal_label] = true
        n_active_seals = 0,
        seal_1_label = nil,         -- oldest seal (or only seal)
        seal_2_label = nil,         -- newest seal (during the twist window)
        fading_seal_label = nil,    -- seal fading after a new seal was cast
        fading_seal_expires = 0,

        effective_speed = 3.5,      -- weapon speed after haste
        effective_gcd = 1.5,        -- GCD after haste

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
        swing_held = false,         -- swing completed during stopattack, held until resume

        twist_attempted = false,    -- a seal swap armed a twist this swing cycle

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
        sim.fight_bl_fired = true      -- locked rotations never auto-Bloodlust
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
        attempts = 0,      -- twist attempts recorded (swings with no attempt are not attempts)
        hits = 0,          -- successful twists (any grade but F)
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
