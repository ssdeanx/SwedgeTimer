--=========================================================================================
-- Next action guide (paladin seal twisting): pure decision engine, no WoW API.
--
-- Ported from the archived builds under docs/swedge/SwedgeTimer_TBC (byte-identical to
-- the *_Forever copy); reference lines:
--   * rotation.lua:37-70    sequences / descriptions / display_names tables
--   * rotation.lua:91-111   get_gcd_duration (cast time -> GCD, clamped [1.0, 1.5])
--   * rotation.lua:114-119  get_haste_amount (1.5 - gcd)
--   * rotation.lua:140-172  calculate_rotation thresholds, in priority order
--   * nextaction.lua:146-155 get_seal_remaining
--   * nextaction.lua:162-177 get_active_seal (Command freshness rule)
--   * nextaction.lua:186-465 compute(): landmarks 208-214, seal=="sob" branches
--     240-261, GCD-busy table 262-324, GCD-ready table 325-363, prediction_hold
--     floor 366-368, filler suppression 370-373, CS override 375-396, filler
--     selection 398-429, judgement cue 434-456.
--
-- This module is deliberately PURE (no WoW API calls, no addon-owned state) so it can
-- be unit-tested offline with the harness in tests/nextaction_state.lua. The WoW-facing
-- call sites gather the live values (swing timer, GCD, cooldowns, seals, mana, target)
-- and call into these helpers rather than re-implementing the rules.
--
-- evaluate(inputs, out) contract:
--   * inputs are plain numbers/strings, all optional (missing ones fall back to the
--     archived defaults). Frozen input names: speed, swing_remaining, G, gcd_remaining,
--     twist_window, reaction, cs_remaining, judge_remaining, seal, cs_delay_max,
--     waiting_judgement, melee_count, mana_pct, creature_type, filler_remaining.
--   * out is caller-owned and reused across ticks; evaluate writes the result fields
--     into it and returns it — no per-call result table is allocated.
--   * out fields: action ("soc"|"sob"|"twist"|"cs"), hold, riding, judge_call,
--     filler_kind (nil|"consecration"|"exorcism"), prediction_hold, waiting_judgement.
--   * inputs.waiting_judgement is the current judgement-cue latch; out.waiting_judgement
--     is the updated latch — the caller feeds it back in on the next tick.
--
-- Optional inputs beyond the frozen set (each falls back to the archived db default, so
-- callers that omit them get the archive's behaviour):
--   * gcd_before_swing             — archived st.bar.get_gcd_time_before_swing(), i.e.
--     G plus the configured GCD padding; default G.
--   * mana_exorcism_threshold      — db.nextaction_filler_mana_exorcism or 30.
--   * mana_consecration_threshold  — db.nextaction_filler_mana_consecration or 35.
--=========================================================================================
local _, st = ...

st.nextaction = st.nextaction or {}

-- Spell ids (archived nextaction.lua:35-42; SOC/SOB were the texture ids).
st.nextaction.CS_SPELL_ID = 35395           -- Crusader Strike
st.nextaction.JUDGEMENT_SPELL_ID = 20271    -- Judgement
st.nextaction.CONSECRATION_SPELL_ID = 26573
st.nextaction.EXORCISM_SPELL_ID = 879
st.nextaction.SOC_ID = 20375                -- Seal of Command
st.nextaction.SOB_ID = 31892                -- Seal of Blood / Martyr

-- Rotation definitions (archived rotation.lua:37-70), ported verbatim; the eight keys
-- are also the priority order of calculate_rotation below.
st.nextaction.sequences = {
    ["1/2"] = {"cs", "twist"},
    ["2/3"] = {"cs", "twist", "twist"},
    ["2/2/5"] = {"cs", "twist", "cs_late", "blood_auto", "twist"},
    ["2/4"] = {"cs", "twist", "blood_auto", "twist"},
    ["1/3"] = {"cs", "blood_auto", "twist"},
    ["2/5_blood"] = {"cs", "blood_auto", "twist", "blood_auto", "twist"},
    ["2/5_command"] = {"cs", "cmd_auto", "twist", "cmd_auto", "twist"},
    ["2007"] = {"blood_auto", "cs"},
}

st.nextaction.descriptions = {
    ["1/2"] = "CS, Twist",
    ["2/3"] = "CS, Twist, Twist",
    ["2/2/5"] = "CS, Twist, CS (late), Auto, Twist",
    ["2/4"] = "CS, Twist, Auto, Twist",
    ["1/3"] = "CS, Auto, Twist",
    ["2/5_blood"] = "CS, Auto, Twist, Auto, Twist",
    ["2/5_command"] = "CS, Cmd Auto, Twist, Cmd Auto, Twist",
    ["2007"] = "Ride Blood & CS",
}

st.nextaction.display_names = {
    ["1/2"] = "1/2",
    ["2/3"] = "2/3",
    ["2/2/5"] = "2/2/5",
    ["2/4"] = "2/4",
    ["1/3"] = "1/3",
    ["2/5_blood"] = "2/5 Blood",
    ["2/5_command"] = "2/5 Command",
    ["2007"] = "2007",
}

-- UnitCreatureType returns localized strings; these are the Undead/Demon names in all
-- client locales the archived build shipped (archived nextaction.lua:51-61). Unknown
-- locales fall back to the Consecration suggestion.
st.nextaction.exorcism_target_types = {
    ["Undead"] = true, ["Demon"] = true,
    ["Untoter"] = true, ["Dämon"] = true,
    ["Mort-vivant"] = true, ["Démon"] = true,
    ["No-muerto"] = true, ["Demonio"] = true,
    ["Morto-vivo"] = true, ["Demônio"] = true,
    ["Нежить"] = true, ["Демон"] = true,
    ["언데드"] = true, ["악마"] = true,
    ["亡灵"] = true, ["恶魔"] = true,
    ["不死族"] = true, ["惡魔"] = true,
}

-- Pure: GCD duration from the base cast time in seconds, clamped to [1.0, 1.5]
-- (archived rotation.lua:91-111, where the cast time came from the flash-heal spell;
-- nil -> base 1.5).
function st.nextaction.get_gcd_duration(base_cast_seconds)
    local gcd = 1.5
    if type(base_cast_seconds) == "number" then
        gcd = base_cast_seconds
    end
    if gcd >= 1.5 then
        gcd = 1.5
    elseif gcd < 1.0 then
        gcd = 1.0
    end
    return gcd
end

-- Pure: haste amount = base GCD (1.5) minus the current GCD, floored at 0
-- (archived rotation.lua:114-119).
function st.nextaction.get_haste_amount(gcd)
    if type(gcd) ~= "number" then
        gcd = 1.5
    end
    local haste = 1.5 - gcd
    if haste < 0 then
        haste = 0
    end
    return haste
end

-- Pure: rotation selection from attack speed (seconds per swing) and GCD. Thresholds
-- and their order are verbatim from the archived rotation.lua:140-172; attack speed
-- defaults to 3.0 and the GCD to 1.5. Returns nil when no threshold matches (the
-- archive's cache and live reads are dropped here).
function st.nextaction.calculate_rotation(attack_speed, gcd)
    if type(attack_speed) ~= "number" then
        attack_speed = 3.0
    end
    if type(gcd) ~= "number" then
        gcd = 1.5
    end
    local haste = st.nextaction.get_haste_amount(gcd)

    local rotation = nil

    if attack_speed > 2.6 then
        -- Slowest weapons: simple 1 twist per CS cycle
        rotation = "1/2"

    elseif attack_speed >= math.max(1.9, 2 * gcd - 0.35) and haste > 0.1 then
        -- Fast enough with high haste: 2 twists per CS cycle
        rotation = "2/3"

    elseif attack_speed >= 2.4 or (attack_speed >= 2.3 and haste > 0.05) then
        -- Medium speed: complex pattern with late CS
        rotation = "2/2/5"

    elseif attack_speed >= math.max(1.5, 1.5 * gcd + 0.05) and haste > 0.1 then
        -- Fast with high haste: 2 twists in 4 actions
        rotation = "2/4"

    elseif attack_speed >= 1.9 then
        -- Standard rotation: 1 twist per 3 actions
        rotation = "1/3"

    elseif attack_speed >= (gcd + 0.07) then
        -- Very fast: ride Blood between twists
        rotation = "2/5_blood"

    elseif attack_speed > 1.0 then
        -- Extremely fast: ride Command for procs
        rotation = "2/5_command"

    elseif attack_speed >= 0.01 then
        -- Ludicrous speed (full Bloodlust + haste): just ride Blood and CS
        rotation = "2007"
    end

    return rotation
end

-- Pure: active seal for the decision tree: "sob", "soc", or "none" (archived
-- nextaction.lua:146-177). Blood wins during the dual-seal twist window (the correct
-- next step after twisting is to re-seal Command). Command only counts with >1 s
-- remaining — the freshness rule: a Command seal whose tracked expiry is nil reads as
-- fresh, an expiry at or inside 1 s reads as "none" (the archive treated practice-mode
-- seals as never expiring; that is the caller's concern here).
function st.nextaction.get_seal_state(has_soc, has_sob, soc_remaining_seconds)
    if has_sob then
        return "sob"
    end
    if has_soc then
        local remaining = soc_remaining_seconds
        if remaining == nil or remaining > 1 then
            return "soc"
        end
    end
    return "none"
end

-- Pure: one engine tick (archived nextaction.lua:186-465, compute() minus
-- practice/editmode/UI). Reads `inputs`, writes into the caller-owned `out` table and
-- returns it. See the module header for the input/output contract.
function st.nextaction.evaluate(inputs, out)
    inputs = inputs or {}
    if type(out) ~= "table" then
        out = {}
    end

    local speed = inputs.speed or 3.0
    local swing_remaining = inputs.swing_remaining or 0
    local G = inputs.G or 1.5
    local gcd_remaining = inputs.gcd_remaining or 0
    if gcd_remaining < 0 then
        -- The archive only ever used a positive running GCD; a negative timer is idle.
        gcd_remaining = 0
    end
    local twist_window = inputs.twist_window or 0.4
    local reaction = inputs.reaction or 0.1
    local cs_delay_max = inputs.cs_delay_max or 1.7
    local melee_count = inputs.melee_count or 0
    local mana_pct = inputs.mana_pct or 0
    local creature_type = inputs.creature_type
    local seal = inputs.seal or "none"
    local cs_remaining = inputs.cs_remaining or 0
    local judge_remaining = inputs.judge_remaining or 0

    -- Time from now until each landmark, mirroring the archive's nextSwing / divWhen /
    -- twistGap and their next-swing equivalents (208-214). "div" is the last moment a
    -- seal GCD can start and still finish before the twist window opens.
    local rel_swing = swing_remaining - reaction / 2
    local rel_div = swing_remaining - twist_window - G - reaction / 2
    local rel_gap = swing_remaining - twist_window - reaction / 4
    local rel_div2 = swing_remaining + speed - twist_window - G
    local rel_gap2 = swing_remaining + speed - twist_window

    local prediction_land = gcd_remaining + G

    local action = out.action      -- seeded like the archive's last action; every branch overwrites it
    local hold = false
    local filler = false
    local riding = false
    local prediction_hold = 10
    local waiting_judgement = inputs.waiting_judgement or false

    local function where_is_swing_at()
        if rel_div < 0 and rel_gap < 0 and rel_swing < 0 then
            return "swing ready"
        elseif rel_div > 0 then
            return "before div"
        elseif rel_gap < 0 then
            return "in twist"
        elseif rel_swing > 0 then
            return "after div"
        else
            return "swing ready"
        end
    end

    if seal == "sob" then
        -- Blood is up: decide directly from the swing timer whether a twist for THIS
        -- swing still fits (reseal Command) or whether the swing lands as a blood auto
        -- (ride it). The reseal deadline is the bar's own GCD marker: Command's GCD must
        -- free before the swing lands so Blood can be recast inside the twist window.
        action = "soc"
        local reseal_deadline = (inputs.gcd_before_swing or G) + reaction
        if (swing_remaining - gcd_remaining) > reseal_deadline then
            -- Reseal now (or queue it for the end of the running GCD)
            prediction_hold = reaction + math.max(rel_gap, 0)
        elseif rel_gap > 0 then
            -- Blood auto: ride the seal, resealing only once the twist window opens
            -- (a reseal inside the window preserves the blood swing)
            hold = true
            riding = true
            filler = true
            prediction_hold = reaction + math.max(prediction_land, rel_gap2)
        else
            -- Window open: resealing now preserves the blood swing
            prediction_hold = reaction + rel_gap2
        end
    elseif gcd_remaining > 0 then
        -- GCD busy: decide based on when it frees relative to the swing landmarks
        local check = gcd_remaining
        if rel_div >= check then
            -- GCD frees before div
            if seal ~= "soc" then
                action = "soc"
                prediction_hold = reaction + rel_gap
            else
                action = "twist"
                hold = true
                filler = true
                prediction_hold = reaction + rel_gap
            end
        elseif check > rel_gap and check < rel_swing then
            -- GCD frees inside the twist gap
            if seal == "soc" then
                action = "twist"
                prediction_hold = -1
            else
                if cs_remaining <= check + G then
                    action = "soc"
                else
                    action = "sob"
                end
                prediction_hold = reaction + gcd_remaining
            end
        elseif check < rel_gap then
            -- GCD frees after div but before the twist gap
            if seal == "soc" then
                action = "twist"
                hold = true
                prediction_hold = reaction + rel_gap
            else
                if cs_remaining <= check + G then
                    action = "soc"
                else
                    action = "sob"
                end
                prediction_hold = reaction + gcd_remaining
            end
        elseif rel_div2 >= check then
            -- GCD frees before the next swing's div
            if seal ~= "soc" then
                action = "soc"
                prediction_hold = reaction + math.max(prediction_land, rel_gap2)
            else
                action = "twist"
                hold = true
                filler = true
                prediction_hold = reaction + math.max(prediction_land, rel_gap2)
            end
        else
            -- GCD frees after the next swing's div
            if seal == "soc" then
                action = "twist"
                hold = true
                prediction_hold = reaction + math.max(prediction_land, rel_gap2)
            else
                action = "soc"
                prediction_hold = reaction + gcd_remaining
            end
        end
    else
        -- GCD ready: decide based on where the swing is right now
        local at = where_is_swing_at()
        if at == "before div" or at == "swing ready" then
            if seal ~= "soc" then
                action = "soc"
                prediction_hold = reaction + rel_gap
            else
                action = "twist"
                hold = true
                filler = true
                prediction_hold = reaction + rel_gap
            end
        elseif at == "in twist" then
            if seal == "soc" then
                action = "twist"
                prediction_hold = -1
            else
                if cs_remaining <= G then
                    action = "soc"
                else
                    action = "sob"
                end
                prediction_hold = 0
            end
        elseif at == "after div" then
            if seal == "soc" then
                action = "twist"
                hold = true
                prediction_hold = reaction + rel_gap
            else
                if cs_remaining <= G then
                    action = "soc"
                else
                    action = "sob"
                end
                prediction_hold = 0
            end
        end
    end

    if prediction_hold < 0 then
        prediction_hold = 0
    end

    -- No filler if CS comes back before the current GCD would finish (370-373)
    if filler and (cs_remaining + 0.05) < G then
        filler = false
    end

    -- Crusader Strike override: if delaying CS any longer would exceed the allowed
    -- delay budget, CS becomes the next action (375-396)
    if action == "twist" then
        cs_delay_max = cs_delay_max + 0.1
    end
    local cs_when = prediction_hold + G + reaction
    local cs_delay = cs_remaining - cs_when + cs_delay_max
    if cs_delay <= 0 then
        action = "cs"
        hold = false
        riding = false
        if gcd_remaining <= 0 then
            if cs_remaining > 0.1 then
                hold = true
            end
        else
            if cs_remaining + 0.1 > gcd_remaining then
                hold = true
            end
        end
    end

    -- Filler suggestion (Consecration / Exorcism) when there is room in the rotation.
    -- The kind is chosen first (target type + mana), then gated on that spell's own
    -- cooldown being back by the time the GCD frees (398-429)
    local filler_kind = nil
    if filler and speed > 2.2 and melee_count > 2 then
        local candidate = nil
        if creature_type and st.nextaction.exorcism_target_types[creature_type] then
            if mana_pct > (inputs.mana_exorcism_threshold or 30) then
                candidate = "exorcism"
            end
        else
            if mana_pct > (inputs.mana_consecration_threshold or 35) then
                candidate = "consecration"
            end
        end
        if candidate then
            local remaining = inputs.filler_remaining
            -- The archived get_filler_remaining() also returned a "known" flag; nil or a
            -- 999 sentinel means the same thing here (spell not known / no reading).
            local known = remaining ~= nil and remaining < 999
            if known and remaining <= gcd_remaining then
                filler_kind = candidate
            end
        end
    end

    -- Judgement cue: judge the active Seal of Blood before twisting back to Command.
    -- Suppressed while riding — judging would consume the seal and ruin the blood
    -- auto; the cue appears once the ride ends at the reseal point (434-456)
    local judge_call = false
    if action == "soc" and seal == "sob" and not riding then
        local a_rel
        if where_is_swing_at() == "before div" then
            a_rel = rel_div
        else
            a_rel = rel_div2
        end
        if judge_remaining < a_rel then
            judge_call = true
            if judge_remaining > 0 and speed > 2.3 then
                if not hold then
                    hold = true
                    waiting_judgement = true
                end
            elseif waiting_judgement then
                hold = false
                waiting_judgement = false
            end
        end
    else
        waiting_judgement = false
    end

    out.action = action
    out.hold = hold
    out.riding = riding
    out.judge_call = judge_call
    out.filler_kind = filler_kind
    out.prediction_hold = prediction_hold
    out.waiting_judgement = waiting_judgement
    return out
end

-- Helpers above are reachable via st.nextaction and pure (no WoW globals).
if st.debug then st.utils.print_msg('-- Parsed nextaction.lua correctly') end
