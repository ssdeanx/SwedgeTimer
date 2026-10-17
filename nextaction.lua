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
--     filler_kind (nil|"consecration"|"exorcism"|"how", the last Era-only),
--     prediction_hold, waiting_judgement.
--   * inputs.waiting_judgement is the current judgement-cue latch; out.waiting_judgement
--     is the updated latch — the caller feeds it back in on the next tick.
--
-- Optional inputs beyond the frozen set (each falls back to the archived db default, so
-- callers that omit them get the archive's behaviour):
--   * gcd_before_swing             — archived st.bar.get_gcd_time_before_swing(), i.e.
--     G plus the configured GCD padding; default G.
--   * mana_exorcism_threshold      — db.nextaction_filler_mana_exorcism or 30.
--   * mana_consecration_threshold  — db.nextaction_filler_mana_consecration or 35.
-- Era-correctness opt-ins (sourced Era 1.15.9 ret; absent means the archived
-- behaviour, so old callers are unaffected — the live paladin provider sets them):
--   * cs_known                     — false when Crusader Strike is unknown on this
--     client (Era-base: the spell does not exist). Default true. False disables
--     the CS override entirely and resolves every no-seal reseal tiebreak to
--     Command (there is no CS timing to wait for).
--   * era                          — true on the Era family. Default false. Era lifts
--     the Consecration AoE-only gate (single-target is mana permitting on Era),
--     enables the Hammer of Wrath execute cue below, and costs the
--     judge-feasibility reseal as a single GCD (Judge plus the one SoR->SoC
--     reseal, not the TBC double reseal).
--   * target_health_pct            — target health percent (0-100), or nil when
--     unknown. Only read on Era.
--   * how_remaining                — Hammer of Wrath cooldown remaining (seconds);
--     nil (or the 999 sentinel) means unknown on this client, like
--     filler_remaining. Only read on Era.
-- Out extension: filler_kind gains "how" (Era execute, hp < 20% with HoW ready).
-- It flows through the provider mapping untouched; the shipped 7-slot frame has
-- no HoW icon, so the frame drops the unknown key without error until a slot
-- exists for it.
-- TBC-correctness opt-ins (sourced TBC 2.5.6 ret; absent means the archived
-- behaviour, so old callers are unaffected — the live paladin provider sets them):
--   * judge_require_fit            — TBC judge-feasibility gate (default false =
--     the archived cue); true requires Judgement's GCD plus the SoB->SoC double
--     reseal to fit before the next swing's twist window.
--   * jotc_remaining               — target Judgement-of-the-Crusader seconds left
--     (default nil = untracked = the archived Blood-only cue); an expiring JotC
--     outranks judging Blood.
--   * target_count                 — enemies in Consecration range (default nil =
--     unknown = the archived suggestion); 1 or 0 withholds Consecration, which
--     is AoE-only on TBC single-target.
-- Forever opt-in (UNCONFIRMED beta behaviour; docs/research/forever_beta.md):
--   * forever                        — true on the Forever family. Default false
--     (archived). Twist of Light alternates Seal of Command / Seal of
--     Righteousness after auto attacks (the provider feeds SoR into the
--     twist-seal position, reusing these landmarks; the optimal window is
--     still unknown per the beta guides, so the 0.4 s landmarks stand),
--     Judgement no longer consumes seals (the fit gate costs Judgement's own
--     GCD only, no reseal), Consecration is a single-target filler (the beta
--     Ret ST lists it), and Hammer of Wrath cues below 20% (beta Ret ST).
--     Holy Strike has no sourced spell id and is not probed.
--=========================================================================================
-- Retail (12.x) inertness: st.family == "RETAIL" short-circuits evaluate to the
-- empty display shape before any branch below. The inert stand-in never reports a
-- swing, but seals, cooldowns, mana and creature type all answer on Retail, so the
-- tree below would prompt (soc reseals, the CS override, fillers, the judgement
-- cue) with no swing at all. Every other family - including Forever, which swings
-- - runs the archived tree unchanged; a nil family (offline callers that predate
-- it) keeps the old behaviour too.
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

-- Pure: TBC twist-weapon suitability label for a weapon speed in seconds per
-- swing. "optimal" at/above the 3.8 best-proc-rate speed, "slow" down to the
-- 3.0 twist floor, "fast" below it (twists poorly). Non-numbers default to
-- 3.0 like calculate_rotation. Label only: rotation selection is untouched.
function st.nextaction.classify_twist_weapon(attack_speed)
    if type(attack_speed) ~= "number" then
        attack_speed = 3.0
    end
    if attack_speed >= st.nextaction.TBC_TWIST_BEST_SPEED then
        return "optimal"
    elseif attack_speed >= st.nextaction.TBC_TWIST_MIN_SPEED then
        return "slow"
    end
    return "fast"
end

-- Pure: the swing's landmark name from its three relative offsets, the ladder the
-- decision tree branches on. Module scope on purpose: evaluate() runs on the 20 Hz hot
-- path and must not allocate a closure per call.
local function where_is_swing_at(rel_div, rel_gap, rel_swing)
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

-- TBC twist-weapon suitability labels (sourced TBC 2.5.6 ret;
-- docs/research/tbc_minmax.md): slow weapons (>= 3.0 s) twist; 3.8 is the
-- highest-SoC-proc-rate speed (~44.3% [uncertain] community parse data),
-- 3.6 the common raid speed (~42%). The rotation thresholds above already
-- cadence every speed, so classify_twist_weapon only labels for callers.
st.nextaction.TBC_TWIST_MIN_SPEED = 3.0
st.nextaction.TBC_TWIST_BEST_SPEED = 3.8
-- TBC Seal of Command proc delay (~0.5 s after the white hit; the 0.4 s twist
-- window sits inside it). Documentary: the landmarks below take the window as
-- an input, so this is not wired into the math.
st.nextaction.TBC_SOC_PROC_DELAY = 0.5

-- TBC judge constants (sourced TBC 2.5.6 ret; plain constants, no new options).
-- TBC_JUDGE_SEAL_GCDS is Judgement's own GCD plus the SoB->SoC double reseal
-- that judging consumes. JOTC_REFRESH_LEAD is how far ahead of JotC expiry the
-- Crusader-priority cue fires: JotC lasts 10 s
-- (LibClassicDurations/classAbilities.lua line 837, "Judgement of the
-- Crusader"), so this lead leaves one Judge GCD plus reaction before it falls
-- off. Confirm the lead in-client; the engine treats a nil JotC reading as
-- untracked (archived Blood-only cue).
local TBC_JUDGE_SEAL_GCDS = 3
local JOTC_REFRESH_LEAD = 3

-- Era constants (sourced Era 1.15.9 ret). ERA_JUDGE_SEAL_GCDS is Judgement's
-- own GCD plus the single SoR->SoC reseal that judging consumes on Era (the
-- TBC cost above carries the SoB->SoC double reseal). ERA_HOW_HEALTH_PCT is
-- the Hammer of Wrath execute window, strict: HoW is unusable at 20%+.
local ERA_JUDGE_SEAL_GCDS = 2
local ERA_HOW_HEALTH_PCT = 20

-- FOREVER_JUDGE_SEAL_GCDS is Judgement's own GCD alone: on the Forever family
-- Judgement no longer consumes seals (docs/research/forever_beta.md,
-- UNCONFIRMED beta), so judging costs no reseal. TBC pays the SoB->SoC double
-- reseal above, Era the single SoR->SoC reseal.
local FOREVER_JUDGE_SEAL_GCDS = 1

-- Pure: one engine tick (archived nextaction.lua:186-465, compute() minus
-- practice/editmode/UI). Reads `inputs`, writes into the caller-owned `out` table and
-- returns it. See the module header for the input/output contract.
function st.nextaction.evaluate(inputs, out)
    inputs = inputs or {}
    if type(out) ~= "table" then
        out = {}
    end

    if st.family == "RETAIL" then
        -- Retail (12.x): no live swing exists (see the header), so the tree
        -- prompts nothing - no action, no ride, no filler, no judgement cue.
        out.action = nil
        out.hold = false
        out.riding = false
        out.judge_call = false
        out.filler_kind = nil
        out.prediction_hold = 0
        out.waiting_judgement = false
        return out
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
    -- TBC default: researched CS delay is under 1 s; the archived 1.7 s
    -- over-delays CS and bleeds twists. CONFLICT: Wrath wants ~0 (no twist to
    -- protect) — one default cannot serve both families; revisit with a family
    -- branch if the guide ever targets Wrath FCFS (out of scope). The option
    -- range in option_tables.lua is unchanged.
    local cs_delay_max = inputs.cs_delay_max or 0.9
    local melee_count = inputs.melee_count or 0
    local mana_pct = inputs.mana_pct or 0
    local creature_type = inputs.creature_type
    local seal = inputs.seal or "none"
    local cs_remaining = inputs.cs_remaining or 0
    local judge_remaining = inputs.judge_remaining or 0
    -- Era opt-ins (header contract): cs_known defaults to true (archived), era
    -- defaults to false (archived). Every branch below is byte-identical unless
    -- the caller sets them.
    local cs_known = inputs.cs_known ~= false
    local era_mode = inputs.era == true
    -- Forever opt-in (header contract): defaults to false (archived). Every
    -- branch below is byte-identical unless the caller sets it.
    local forever_mode = inputs.forever == true

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
                if (not cs_known) or cs_remaining <= check + G then
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
                if (not cs_known) or cs_remaining <= check + G then
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
        local at = where_is_swing_at(rel_div, rel_gap, rel_swing)
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
                if (not cs_known) or cs_remaining <= G then
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
                if (not cs_known) or cs_remaining <= G then
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
    -- delay budget, CS becomes the next action (375-396). Era-base has no
    -- Crusader Strike (cs_known false from the client's spell book), so the
    -- override never fires there.
    if action == "twist" then
        cs_delay_max = cs_delay_max + 0.1
    end
    local cs_when = prediction_hold + G + reaction
    local cs_delay = cs_remaining - cs_when + cs_delay_max
    if cs_known and cs_delay <= 0 then
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
        -- Era/Forever execute first: Hammer of Wrath below 20% target health
        -- outranks the rotation fillers (its window is conditional, theirs is
        -- not), when its own cooldown is back by the time the GCD frees.
        -- Forever reuses the window: the beta Ret ST lists Hammer of Wrath
        -- below 20% (UNCONFIRMED). Anything else (unknown health,
        -- unknown/unready HoW) falls through to the rotation fillers below.
        local target_hp = inputs.target_health_pct
        local how_remaining = inputs.how_remaining
        local how_ready = how_remaining ~= nil and how_remaining < 999
            and how_remaining <= gcd_remaining
        if (era_mode or forever_mode) and type(target_hp) == "number"
            and target_hp < ERA_HOW_HEALTH_PCT and how_ready then
            candidate = "how"
        elseif creature_type and st.nextaction.exorcism_target_types[creature_type] then
            if mana_pct > (inputs.mana_exorcism_threshold or 30) then
                candidate = "exorcism"
            end
        else
            -- TBC single-target has no Consecration: it is an AoE filler and
            -- fires only with a real multi-target signal (target_count > 1).
            -- Unknown (nil) keeps the archived suggestion so old callers are
            -- unaffected; the live provider reports single-target until a
            -- target counter exists. Exorcism above is untouched (valid ST
            -- filler vs Undead/Demon). Era lifts the gate: Consecration is a
            -- mana-permitting single-target filler on Era. Forever lifts it
            -- too: the beta Ret ST lists Consecration (UNCONFIRMED tuning).
            local ntargets = inputs.target_count
            if (era_mode or forever_mode or ntargets == nil or ntargets > 1)
                and mana_pct > (inputs.mana_consecration_threshold or 35) then
                candidate = "consecration"
            end
        end
        if candidate then
            local remaining = inputs.filler_remaining
            if candidate == "how" then
                -- The execute reads its own cooldown, not the mirrored filler
                -- one (the gather mirrors the filler it would pick; HoW is a
                -- separate spell with its own id set).
                remaining = inputs.how_remaining
            end
            -- The archived get_filler_remaining() also returned a "known" flag; nil or a
            -- 999 sentinel means the same thing here (spell not known / no reading).
            local known = remaining ~= nil and remaining < 999
            if known and remaining <= gcd_remaining then
                filler_kind = candidate
            end
        end
    end

    -- Judgement cue. Blood path (archive): judge the active Seal of Blood before
    -- twisting back to Command; suppressed while riding — judging would consume
    -- the seal and ruin the blood auto, so the cue appears once the ride ends at
    -- the reseal point (434-456). TBC feasibility (judge_require_fit, set by the
    -- live provider): Judgement's own GCD plus the SoB->SoC double reseal (3
    -- GCDs) must still fit before the next swing's twist window opens (rel_gap2)
    -- — judging then costs at most one twist; otherwise the guide keeps
    -- twisting. Crusader path: a JotC that needs refresh outranks Blood (judge
    -- the Crusader debuff first); it bypasses the fit gate (debuff uptime beats
    -- one twist) but never fires mid-ride. Twist/CS/Exorcism-vs-Undead/Demon
    -- are untouched.
    local judge_call = false
    local jotc_remaining = inputs.jotc_remaining
    local crusader_due = jotc_remaining ~= nil and jotc_remaining < JOTC_REFRESH_LEAD
    if action == "soc" and seal == "sob" and not riding then
        local a_rel
        if where_is_swing_at(rel_div, rel_gap, rel_swing) == "before div" then
            a_rel = rel_div
        else
            a_rel = rel_div2
        end
        local blood_due = judge_remaining < a_rel
        if blood_due and inputs.judge_require_fit then
            -- One reaction of tolerance: rel_gap2 embeds none, and the cue is
            -- acted on by a human a tick later.
            -- Era re-arms with a single reseal (Judgement plus the one
            -- SoR->SoC reseal), not the TBC double reseal, so the fit costs
            -- one GCD less. Forever re-arms with Judgement alone (no seal is
            -- consumed there), so the fit costs no reseal at all.
            local judge_seal_gcds = TBC_JUDGE_SEAL_GCDS
            if era_mode then
                judge_seal_gcds = ERA_JUDGE_SEAL_GCDS
            elseif forever_mode then
                judge_seal_gcds = FOREVER_JUDGE_SEAL_GCDS
            end
            blood_due = (judge_remaining + judge_seal_gcds * G)
                <= (rel_gap2 + reaction)
        end
        if crusader_due or blood_due then
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
-- Wrath FCFS + SoD Exodin live below (evaluate_fcfs): same out channels, new
-- branches only. TBC / Era / Retail never set inputs.fcfs_mode, so evaluate()
-- above runs bit-identically there.
if st.debug then st.utils.print_msg('-- Parsed nextaction.lua correctly') end

--=========================================================================================
-- Wrath FCFS + SoD Exodin (first-come-first-served winner): pure, no WoW API.
--
-- Sourced ret min/max (docs/research/rotations_wrath.md, rotations_sod.md):
--   * Wrath FCFS (single target): CS > Judge > DS > Cons > Exo-instant-via-AoW >
--     Holy Wrath (Undead/Demon only). Never-wait: a ready lower-priority ability
--     beats waiting on a higher-priority cooldown.
--   * SoD Exodin: Exo (core, every target) > CS > DS > Judge > Cons (mana, 3+
--     targets) > HoW (< 20%). Exo < 10% is subsumed (Exo is already first).
--   * 2pc-T10 note: NO explicit set-bonus input. Post-2pc DS resets surface as
--     ds_remaining readiness (the live client cooldown), so this walk elevates DS
--     automatically; the ORDER is unchanged pre/post 2pc. Explicit set-bonus
--     detection is deferred (no offline-testable probe).
--
-- evaluate_fcfs(inputs, out) contract:
--   * inputs.fcfs_mode selects the table: "wrath" or "sod". Any other mode (or
--     Retail, which never sets a mode) yields the empty display shape.
--   * Cooldown inputs (seconds remaining; nil or the 999 sentinel means unknown
--     on this client and withholds the ability, never prompts it):
--     cs_remaining, judge_remaining, ds_remaining, cons_remaining,
--     exo_remaining, hw_remaining (Wrath Holy Wrath), how_remaining (SoD HoW).
--   * Gates: cs_known (default true, like evaluate), has_aow (Wrath Exo only),
--     mana_pct with mana_consecration_threshold (35) / mana_exorcism_threshold
--     (30), creature_type (Wrath HW eligibility via exorcism_target_types),
--     target_count (SoD Cons cleave gate), target_health_pct (SoD HoW window).
--   * Ready = remaining <= max(gcd_remaining, 0): castable when the GCD frees.
--   * out reuses the archived channels so the provider mapping is untouched:
--     action "cs"; action "sob" (Divine Storm - the sob slot carries the DS
--     texture on FCFS families, same key); judge_call (Judgement cue);
--     filler_kind "consecration" | "exorcism" | "how" (Holy Wrath on Wrath,
--     Hammer of Wrath on SoD). hold is true only when nothing is ready (wait on
--     the first known ability); riding never; waiting_judgement always false.
--=========================================================================================

-- Priority orders, first match wins (sourced above; index order is the contract).
local FCFS_ORDER_WRATH = { "cs", "judge", "ds", "cons", "exo", "hw" }
local FCFS_ORDER_SOD = { "exo", "cs", "ds", "judge", "cons", "how" }

-- Pure: known cooldown (nil / 999 sentinel means the spell is unavailable here).
local function fcfs_known(remaining)
    return remaining ~= nil and remaining < 999
end

-- Pure: eligibility WITHOUT readiness (known spell + mode gates). Readiness is
-- tested separately so the nothing-ready fallback can wait on a known ability.
local function fcfs_eligible(mode, key, inputs)
    if key == "cs" then
        return inputs.cs_known ~= false and fcfs_known(inputs.cs_remaining)
    elseif key == "judge" then
        return fcfs_known(inputs.judge_remaining)
    elseif key == "ds" then
        return fcfs_known(inputs.ds_remaining)
    elseif key == "cons" then
        if not fcfs_known(inputs.cons_remaining) then
            return false
        end
        if (inputs.mana_pct or 0) <= (inputs.mana_consecration_threshold or 35) then
            return false
        end
        if mode == "sod" then
            -- Exodin: Consecration is mana- AND cleave-gated (3+ targets);
            -- unknown (nil) keeps the suggestion, mirroring the archived rule.
            local ntargets = inputs.target_count
            return ntargets == nil or ntargets >= 3
        end
        return true
    elseif key == "exo" then
        if not fcfs_known(inputs.exo_remaining) then
            return false
        end
        if (inputs.mana_pct or 0) <= (inputs.mana_exorcism_threshold or 30) then
            return false
        end
        if mode == "wrath" then
            -- Wrath Exorcism is instant ONLY under Art of War; hard casts are a
            -- DPS loss and are never prompted.
            return inputs.has_aow == true
        end
        -- SoD Exodin: Exorcism is the core button vs every target, no AoW gate.
        return true
    elseif key == "hw" then
        -- Wrath Holy Wrath: Undead/Demon only ("if eligible"), own cooldown.
        return fcfs_known(inputs.hw_remaining)
            and inputs.creature_type ~= nil
            and st.nextaction.exorcism_target_types[inputs.creature_type] == true
    elseif key == "how" then
        -- SoD Hammer of Wrath: below 20% target health, own cooldown.
        return fcfs_known(inputs.how_remaining)
            and type(inputs.target_health_pct) == "number"
            and inputs.target_health_pct < 20
    end
    return false
end

-- Pure: the remaining time of one priority key for the readiness test. Every
-- caller gates on fcfs_eligible first, so this only ever returns a number.
local function fcfs_remaining(key, inputs)
    if key == "cs" then
        return inputs.cs_remaining
    elseif key == "judge" then
        return inputs.judge_remaining
    elseif key == "ds" then
        return inputs.ds_remaining
    elseif key == "cons" then
        return inputs.cons_remaining
    elseif key == "exo" then
        return inputs.exo_remaining
    elseif key == "hw" then
        return inputs.hw_remaining
    elseif key == "how" then
        return inputs.how_remaining
    end
    return nil
end

-- Pure: one FCFS tick. Reads `inputs`, writes into the caller-owned `out` table
-- and returns it (no per-call allocation: the order tables are module-level,
-- the walk is index-based). See the block above for the contract.
function st.nextaction.evaluate_fcfs(inputs, out)
    inputs = inputs or {}
    if type(out) ~= "table" then
        out = {}
    end

    local mode = inputs.fcfs_mode
    local order = nil
    if st.family ~= "RETAIL" then
        if mode == "wrath" then
            order = FCFS_ORDER_WRATH
        elseif mode == "sod" then
            order = FCFS_ORDER_SOD
        end
    end

    local gcd_remaining = inputs.gcd_remaining or 0
    if gcd_remaining < 0 then
        gcd_remaining = 0
    end

    local action = nil
    local hold = false
    local judge_call = false
    local filler_kind = nil
    if order then
        -- Never-wait: the first READY ability in priority order wins (a ready
        -- lower-priority ability beats waiting on a higher-priority cooldown).
        local winner = nil
        for n = 1, #order do
            local key = order[n]
            if fcfs_eligible(mode, key, inputs)
                and fcfs_remaining(key, inputs) <= gcd_remaining then
                winner = key
                break
            end
        end
        if winner == nil then
            -- Nothing castable: wait on the soonest-known ability (hold), never
            -- prompt an unknown spell. Priority order breaks readiness ties. No
            -- known ability at all: stay empty.
            local best_rem = nil
            for n = 1, #order do
                local key = order[n]
                if fcfs_eligible(mode, key, inputs) then
                    local rem = fcfs_remaining(key, inputs)
                    if best_rem == nil or rem < best_rem then
                        winner = key
                        best_rem = rem
                        hold = true
                    end
                end
            end
        end
        if winner == "cs" then
            action = "cs"
        elseif winner == "judge" then
            judge_call = true
        elseif winner == "ds" then
            action = "sob"
        elseif winner == "cons" then
            filler_kind = "consecration"
        elseif winner == "exo" then
            filler_kind = "exorcism"
        elseif winner == "hw" or winner == "how" then
            filler_kind = "how"
        end
    end

    out.action = action
    out.hold = hold
    out.riding = false
    out.judge_call = judge_call
    out.filler_kind = filler_kind
    out.prediction_hold = 0
    out.waiting_judgement = false
    return out
end
