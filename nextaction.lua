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
--     prediction_hold, waiting_judgement, inputs_unknown.
--   * out advisory fields (all false unless the rule below fires; the guide
--     frame ignores unknown keys, so they are display-inert until a UI lane
--     consumes them): stopattack (the sim would StopAttack before this cue),
--     prepull_ready (prepull window open, seal down), seal_maintenance
--     (FCFS SoD only: primary seal needs its reseal), rank1_advice (SoC
--     Rank 1 is known: twist on rank 1), hard_wait (strictSequence: wait the
--     swing out, do not fill).
--   * inputs.waiting_judgement is the current judgement-cue latch; out.waiting_judgement
--     is the updated latch — the caller feeds it back in on the next tick.
--   * inputs.inputs_unknown (optional bool, M6): the caller's own "the core timing
--     reads are unusable" flag - the provider sets it when the swing fields cannot be
--     trusted. The engine threads it into out.inputs_unknown unchanged; the guide UI
--     renders "…" instead of an action while it is true. The engine never derives it
--     itself: an all-defaults input set is indistinguishable from a legitimate one here.
--
-- Optional inputs beyond the frozen set (each falls back to the archived db default, so
-- callers that omit them get the archive's behaviour):
--   * gcd_before_swing             — archived st.bar.get_gcd_time_before_swing(), i.e.
--     G plus the configured GCD padding; default G.
--   * mana_exorcism_threshold      — db.nextaction_filler_mana_exorcism or 30.
--   * mana_consecration_threshold  — db.nextaction_filler_mana_consecration or 35.
-- Sim-sourced optional inputs (each defaults to the archived behaviour when
-- absent; the live paladin provider sets the ones its client can answer):
--   * cs_hold_remaining            — pull-phase CS hold, seconds left (TBC sim
--     "Delay Major CDs" 11 s; TBC_PULL_CS_HOLD_SECONDS). While positive the
--     CS override never fires. nil/<=0 = archived.
--   * auto_age_seconds             — seconds since the last real auto landed
--     (nil = unknown = archived). Feeds the two recency rules below.
--   * reseal_auto_guard_seconds    — TBC reseal guard (TBC sim: no reseal
--     within TBC_RESEAL_AUTO_GUARD_SECONDS of the last auto). When set, a
--     fresh auto degrades the immediate reseal to a ride.
--   * twist_mana_threshold         — mana-sustain governor plug-in (percent;
--     unset = off = archived). When set and mana sits below it, the
--     immediate reseal degrades to a ride instead of spending the mana.
--   * how_cast_seconds             — Hammer of Wrath cast time, seconds
--     (nil = unknown = archived hp-only rule). An instant (<= 0) HoW cues
--     regardless of target health (Forever sim shape).
--   * fight_remaining_pct          — fight remaining, percent (nil = unknown =
--     archived). FCFS SoD only: below SOD_EXECUTE_FIGHT_PCT the HoW execute
--     fires without the hp read (SoD APL execute burn).
--   * hor_remaining                — Hand of Reckoning cooldown remaining,
--     seconds (nil or the 999 sentinel = unknown on this client). FCFS Wrath
--     only: the WotLK APL's TOP row (i=1, 67485). The provider feeds it only
--     when the client's own spell book knows the spell, so a build without the
--     talent never sees the prompt (the APL UTILITY layer, bench/
--     rotation_gap_vs_apl_2026-10-20.md §6.2).
--   * how_wrath_remaining          — Hammer of Wrath (WotLK 48806) cooldown
--     remaining, seconds (nil = unknown = withheld). FCFS Wrath only: the
--     WotLK APL's second row (i=2). The client's sim gates the cast on the
--     execute phase (sim wowsims/wotlk sim/paladin/hammer_of_wrath.go:31-32
--     ExtraCastCondition: sim.IsExecutePhase20()), so the arm asks for the
--     spell only below 20 % target health.
-- Follow-up optional inputs (each nil/false = archived; the live paladin
-- provider feeds the ones its client can answer, the rest stay filed):
--   * time_to_pull_seconds         — pull countdown, seconds (nil = unknown =
--     archived). The classic APL prepulls the primary seal at -1.5 s; the pull
--     timer itself lives outside this module (filed: main.lua).
--   * seal_remaining_seconds       — primary-seal remaining, seconds (nil =
--     unknown = archived). FCFS SoD only: below SEAL_MAINTAIN_RESEAL_SECONDS
--     the sim refreshes Judge above the damage order (filed: seal-aura source
--     per SoD build + guide slot + nextaction_ui).
--   * soc_rank1_known              — SoC Rank 1 (20375) in the book (nil/false =
--     archived). The min/max consensus twists on rank 1; the reader is the
--     live spell book (filed: guide slot + option).
--   * strict_sequence              — SoD strictSequence wait (nil/false =
--     archived). True on SoD twist builds (rune-gated): a held twist waits the
--     swing out instead of filling (filed: nextaction_ui hard-wait render).
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
--   * holy_strike_known              — Holy Strike (10333) in the player's book
--     on Forever (default nil = unknown = the archived behaviour). The id is
--     WEB-CONFIRMED but CLIENT-UNCONFIRMED (bench/ids_research_2026-10-19.md
--     §2), and the class resolves it by NAME before the book is asked, so a
--     wrong id leaves this unknown rather than answering. PLUG-IN POINT: the
--     engine does not read it yet - the frozen ten guide slots have no Holy
--     Strike slot, and a slot-budget ruling is owed before one is added - so
--     nothing prompts on it yet.
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
st.nextaction.CS_SPELL_ID = 35395        -- Crusader Strike
st.nextaction.JUDGEMENT_SPELL_ID = 20271 -- Judgement
st.nextaction.CONSECRATION_SPELL_ID = 26573
st.nextaction.EXORCISM_SPELL_ID = 879
st.nextaction.SOC_ID = 20375 -- Seal of Command
st.nextaction.SOB_ID = 31892 -- Seal of Blood / Martyr

-- Rotation definitions (archived rotation.lua:37-70), ported verbatim; the eight keys
-- are also the priority order of calculate_rotation below.
st.nextaction.sequences = {
    ["1/2"] = { "cs", "twist" },
    ["2/3"] = { "cs", "twist", "twist" },
    ["2/2/5"] = { "cs", "twist", "cs_late", "blood_auto", "twist" },
    ["2/4"] = { "cs", "twist", "blood_auto", "twist" },
    ["1/3"] = { "cs", "blood_auto", "twist" },
    ["2/5_blood"] = { "cs", "blood_auto", "twist", "blood_auto", "twist" },
    ["2/5_command"] = { "cs", "cmd_auto", "twist", "cmd_auto", "twist" },
    ["2007"] = { "blood_auto", "cs" },
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
    ["Undead"] = true,
    ["Demon"] = true,
    ["Untoter"] = true,
    ["Dämon"] = true,
    ["Mort-vivant"] = true,
    ["Démon"] = true,
    ["No-muerto"] = true,
    ["Demonio"] = true,
    ["Morto-vivo"] = true,
    ["Demônio"] = true,
    ["Нежить"] = true,
    ["Демон"] = true,
    ["언데드"] = true,
    ["악마"] = true,
    ["亡灵"] = true,
    ["恶魔"] = true,
    ["不死族"] = true,
    ["惡魔"] = true,
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

-- Sim-sourced pull/recency constants (bench/paladin_rotation_audit_2026-10-19.md).
-- TBC_PULL_CS_HOLD_SECONDS is the TBC APL's "Delay Major CDs" variable: major
-- cooldowns hold 11 s at pull, so the CS override suppresses that long. The
-- provider owns the combat-start clock and passes the remainder; the engine
-- only honours a positive remainder.
st.nextaction.TBC_PULL_CS_HOLD_SECONDS = 11
-- TBC_RESEAL_AUTO_GUARD_SECONDS is the TBC APL's reseal age guard: no reseal
-- within 0.5 s of the last auto. The provider passes it on the TBC twist path
-- only (nil elsewhere = archived); the age itself rides auto_age_seconds.
st.nextaction.TBC_RESEAL_AUTO_GUARD_SECONDS = 0.5
-- FOREVER_HOW_AUTO_WINDOW is the Forever sim's post-auto HoW window: HoW cues
-- when its cast time is 0 or within 0.2 s after the last auto (an
-- instant-cast/proc window, not an execute threshold).
st.nextaction.FOREVER_HOW_AUTO_WINDOW = 0.2
-- SOD_EXECUTE_FIGHT_PCT is the SoD APL execute burn: below 10% fight
-- remaining HoW spams without the hp read (FCFS SoD only).
st.nextaction.SOD_EXECUTE_FIGHT_PCT = 10

-- PREPULL_SEAL_LEAD_SECONDS is the classic APL prepull: the primary seal goes
-- up 1.5 s before the pull. The engine only reports the window (prepull_ready
-- below); which seal is family-specific and stays filed with the pull timer.
st.nextaction.PREPULL_SEAL_LEAD_SECONDS = 1.5

-- SEAL_MAINTAIN_RESEAL_SECONDS is the classic APL reseal freshness line (the
-- same <1 s the get_seal_state freshness rule already uses): a primary seal
-- inside it is maintained above the damage order on FCFS SoD.
st.nextaction.SEAL_MAINTAIN_RESEAL_SECONDS = 1

-- SoD variant reseal/maintenance constants (bench/sod_paladin_variants_2026-10-19.md
-- §3-§6, all six p8 APLs fetched in-lane; in-client behaviour UNCONFIRMED):
--   * SOD_STACK_SEAL_RESEAL_SECONDS: p8-stack independent refreshes (SoC <=1 s,
--     SoM <=1 s, two timers, §3).
--   * SOD_SHOCK_SEAL_RESEAL_SECONDS: shockadin seal/Judge maintenance at 1.5 s
--     (wider than Exodin's 1 s, §4).
--   * SOD_WRATH_RESEAL_SECONDS: p8-wrath reseal <=0.5 s (tightest, §6).
--   * SOD_WRATH_CONS_FALLBACK_SECONDS: p8-wrath Cons filler ONLY when DS/CS/Exo
--     all >1.5 s out (or stacks <3, §6).
--   * SOD_TEMPLAR_WAIT_SECONDS: p8-wrath Templar (1226464 <=1 s at 3 stacks)
--     wait-for-DS rule (§6); shockadin Templar-stack (1240574 <=1.5 s at
--     3 stacks, §4) reuses its own 1.5 s maintenance line below.
st.nextaction.SOD_STACK_SEAL_RESEAL_SECONDS = 1
st.nextaction.SOD_SHOCK_SEAL_RESEAL_SECONDS = 1.5
st.nextaction.SOD_WRATH_RESEAL_SECONDS = 0.5
st.nextaction.SOD_WRATH_CONS_FALLBACK_SECONDS = 1.5
st.nextaction.SOD_TEMPLAR_WAIT_SECONDS = 1

-- Bloodlust / Heroism override for the twist window (sourced TBC 2.5.6 ret;
-- bench/verify_bank.md P3 row): under a haste raid buff every action is busy
-- sooner, so the twist window the caller feeds the landmarks must shrink. The
-- scale is a plain constant (no option); the caller decides whether to apply
-- it (the paladin gather gates on its own option and on the live aura scan).
-- apply_lust_window(window_seconds, lust_active) is pure: without an active
-- buff the window passes through untouched (nil stays nil); with one it is
-- scaled by LUST_TWIST_WINDOW_SCALE and floored at 0.
st.nextaction.LUST_TWIST_WINDOW_SCALE = 0.6

function st.nextaction.apply_lust_window(window_seconds, lust_active)
    if type(window_seconds) ~= "number" then
        return window_seconds
    end
    if lust_active ~= true then
        return window_seconds
    end
    local scaled = window_seconds * st.nextaction.LUST_TWIST_WINDOW_SCALE
    if scaled < 0 then
        return 0
    end
    return scaled
end

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
        out.inputs_unknown = true
        out.stopattack = false
        out.prepull_ready = false
        out.seal_maintenance = false
        out.rank1_advice = false
        out.hard_wait = false
        return out
    end

    -- M6: the caller's explicit "core inputs unusable" bit is threaded through
    -- untouched; the UI renders "…" instead of advice while it is set. The engine
    -- itself only reports what the caller declared - the provider owns the reads.
    out.inputs_unknown = inputs.inputs_unknown == true

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

    -- Swing recency (header contract): seconds since the last real auto
    -- landed, or nil when the caller cannot time it (unknown = archived
    -- everywhere below).
    local auto_age = inputs.auto_age_seconds
    if type(auto_age) ~= "number" or auto_age ~= auto_age then
        auto_age = nil
    end

    -- Time from now until each landmark, mirroring the archive's nextSwing / divWhen /
    -- twistGap and their next-swing equivalents (208-214). "div" is the last moment a
    -- seal GCD can start and still finish before the twist window opens.
    local rel_swing = swing_remaining - reaction / 2
    local rel_div = swing_remaining - twist_window - G - reaction / 2
    local rel_gap = swing_remaining - twist_window - reaction / 4
    local rel_div2 = swing_remaining + speed - twist_window - G
    local rel_gap2 = swing_remaining + speed - twist_window

    local prediction_land = gcd_remaining + G

    local action = out.action -- seeded like the archive's last action; every branch overwrites it
    local hold = false
    local filler = false
    local riding = false
    local prediction_hold = 10
    -- twist_now marks the immediate (cast-now, inside the window) twist cue:
    -- the GCD-busy in-gap and GCD-ready in-twist branches below. It feeds the
    -- stopattack advisory at the end (the sim StopAttacks before a twist or a
    -- judge that lands inside the window).
    local twist_now = false
    local waiting_judgement = inputs.waiting_judgement or false

    if seal == "sob" then
        -- Blood is up: decide directly from the swing timer whether a twist for THIS
        -- swing still fits (reseal Command) or whether the swing lands as a blood auto
        -- (ride it). The reseal deadline is the bar's own GCD marker: Command's GCD must
        -- free before the swing lands so Blood can be recast inside the twist window.
        action = "soc"
        local reseal_deadline = (inputs.gcd_before_swing or G) + reaction
        -- TBC reseal age guard: no reseal within reseal_auto_guard_seconds of
        -- the last auto (nil guard or unknowable age = archived). Mana
        -- governor plug-in: below twist_mana_threshold the reseal's mana is
        -- kept and the swing rides instead (unset = off = archived).
        local reseal_guard = inputs.reseal_auto_guard_seconds
        if type(reseal_guard) ~= "number" or reseal_guard ~= reseal_guard then
            reseal_guard = nil
        end
        local auto_fresh = auto_age ~= nil and reseal_guard ~= nil
            and auto_age < reseal_guard
        local mana_throttle = type(inputs.twist_mana_threshold) == "number"
            and mana_pct < inputs.twist_mana_threshold
        if (swing_remaining - gcd_remaining) > reseal_deadline
            and not auto_fresh and not mana_throttle then
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
                twist_now = true
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
                twist_now = true
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
    -- override never fires there. Pull-phase hold (TBC sim "Delay Major CDs"):
    -- while cs_hold_remaining stays positive the override stays suppressed.
    if action == "twist" then
        cs_delay_max = cs_delay_max + 0.1
    end
    local cs_when = prediction_hold + G + reaction
    local cs_delay = cs_remaining - cs_when + cs_delay_max
    local cs_hold_left = inputs.cs_hold_remaining
    local cs_held = type(cs_hold_left) == "number" and cs_hold_left > 0
    if cs_known and cs_delay <= 0 and not cs_held then
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
        -- Instant-cast HoW cues regardless of target health (Forever sim
        -- shape; nil cast time = unknown = archived hp-only rule). Forever
        -- post-auto recency cues inside FOREVER_HOW_AUTO_WINDOW of the last
        -- auto (same sim shape; unknowable age = archived).
        local how_instant = type(inputs.how_cast_seconds) == "number"
            and inputs.how_cast_seconds <= 0
        local how_recent_auto = forever_mode and auto_age ~= nil
            and auto_age <= st.nextaction.FOREVER_HOW_AUTO_WINDOW
        if (era_mode or forever_mode) and how_ready
            and (how_instant or how_recent_auto
                or (type(target_hp) == "number"
                    and target_hp < ERA_HOW_HEALTH_PCT)) then
            candidate = "how"
        elseif forever_mode
            or (creature_type
                and st.nextaction.exorcism_target_types[creature_type]) then
            -- Forever treats Exorcism as a generic filler (the sim gates it
            -- on swing timing + mana, with no creature-type gate); the mana
            -- threshold below still applies, so the safe direction holds
            -- (withholds, never over-prompts).
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

    -- Follow-up advisories (all default off; each cites its sim shape in the
    -- header). Stopattack discipline (classic IsUsingJudgementStopAttack +
    -- SoD StopAttack/StartAttack twists/judges): cueing a twist-now or a
    -- judge while the swing sits inside the window collides with the auto, so
    -- the sim stops the attack first. Advisory only: the macro/UI that acts
    -- on it is filed (addons cannot cast anyway), and the frame ignores the
    -- key meanwhile.
    local swing_inside_window = swing_remaining <= twist_window
    local stopattack = (twist_now or judge_call) and swing_inside_window
    -- Prepull guidance (classic APL -1.5 s): the window is open while the pull
    -- is that close and no seal is up. The pull countdown itself is filed.
    local time_to_pull = inputs.time_to_pull_seconds
    local prepull_ready = type(time_to_pull) == "number"
        and time_to_pull == time_to_pull and time_to_pull >= 0
        and time_to_pull <= st.nextaction.PREPULL_SEAL_LEAD_SECONDS
        and seal == "none"
    -- Rank-1 advice (min/max consensus; sim APLs cast rank 1): a known book
    -- rank 1 reads as advice. The slot that would carry it is filed.
    local rank1_advice = inputs.soc_rank1_known == true
    -- strictSequence hard-wait groundwork (SoD twist APLs): a held twist on a
    -- strict build waits the swing out instead of filling. The render is filed.
    local hard_wait = inputs.strict_sequence == true and hold == true

    out.action = action
    out.hold = hold
    out.riding = riding
    out.judge_call = judge_call
    out.filler_kind = filler_kind
    out.prediction_hold = prediction_hold
    out.waiting_judgement = waiting_judgement
    out.stopattack = stopattack
    out.prepull_ready = prepull_ready
    out.seal_maintenance = false
    out.rank1_advice = rank1_advice
    out.hard_wait = hard_wait
    return out
end

-- Helpers above are reachable via st.nextaction and pure (no WoW globals).
-- Wrath FCFS + SoD Exodin + three SoD-native variants live below
-- (evaluate_fcfs): same out channels, new branches only. TBC / Era /
-- Retail never set inputs.fcfs_mode, so evaluate() above runs
-- bit-identically there.
if st.debug then st.utils.print_msg('-- Parsed nextaction.lua correctly') end

--=========================================================================================
-- Wrath FCFS + SoD Exodin + SoD stack / shockadin / wrath-like (first-come-
-- first-served winner): pure, no WoW API.
--
-- Sourced ret min/max (docs/research/rotations_wrath.md, rotations_sod.md):
--   * Wrath FCFS (single target): CS > Judge > DS > Cons > Exo-instant-via-AoW >
--     Holy Wrath (Undead/Demon only). Never-wait: a ready lower-priority ability
--     beats waiting on a higher-priority cooldown.
--   * SoD Exodin: Exo (core, every target) > CS > DS > Judge > Cons (mana, 3+
--     targets) > HoW (< 20%). Exo < 10% is subsumed (Exo is already first).
--   * SoD stack (bench/sod_paladin_variants_2026-10-19.md §3, p8-stack APL,
--     in-client UNCONFIRMED): independent SoC/SoM <=1 s refreshes; DS
--     stack-gated; CS; Exo; HW r2 Undead + Naxx-6pc; Cons r5; Judge dual-only.
--   * Shockadin (bench §4-§5, p8-shockadin-1h/2h APLs, in-client UNCONFIRMED):
--     seal/Judge 1.5 s maintenance (FILED: p8 primary role UNCONFIRMED);
--     Sunlight/Templar maintenance AM+HS weave; Exo > AM (Libram-gated,
--     3 stacks) > HS (3 stacks) > CS.
--   * Wrath-like (bench §6, p8-wrath APL, in-client UNCONFIRMED): Judge
--     T2-2pc-gated; reseal 0.5 s (FILED: primary role UNCONFIRMED, constant
--     carried here); Templar <=1 s at 3 stacks waits DS; DS (3 stacks) > CS >
--     Exo > DS ungated fallback > Judge GCD fallback > Cons (DS/CS/Exo all
--     >1.5 s out or stacks <3).
--   * 2pc-T10 note: NO explicit set-bonus input. Post-2pc DS resets surface as
--     ds_remaining readiness (the live client cooldown), so this walk elevates DS
--     automatically; the ORDER is unchanged pre/post 2pc. Explicit set-bonus
--     detection is deferred (no offline-testable probe).
--
-- evaluate_fcfs(inputs, out) contract:
--   * inputs.fcfs_mode selects the table: "wrath", "sod", "sod_stack",
--     "sod_shock" or "sod_wrath" (the last three are SoD-native, ERA-gated +
--     rune/item-gated in the gather, never client-version; bench file above).
--     Any other mode (or Retail, which never sets a mode) yields the empty
--     display shape. "sod" (Exodin) is unchanged by every branch below.
--   * Cooldown inputs (seconds remaining; nil or the 999 sentinel means unknown
--     on this client and withholds the ability, never prompts it):
--     cs_remaining, judge_remaining, ds_remaining, cons_remaining,
--     exo_remaining, hw_remaining (Wrath Holy Wrath), how_remaining (SoD HoW),
--     hs_remaining (shockadin Holy Shock), am_remaining (shockadin Aura Mastery),
--     hor_remaining (Wrath Hand of Reckoning), how_wrath_remaining (Wrath
--     Hammer of Wrath).
--   * Gates: cs_known (default true, like evaluate), has_aow (Wrath Exo only),
--     mana_pct with mana_consecration_threshold (35) / mana_exorcism_threshold
--     (30), creature_type (Wrath HW eligibility via exorcism_target_types;
--     stack HW adds Naxx-6pc), target_count (SoD Cons cleave gate),
--     target_health_pct (SoD HoW window), fight_remaining_pct (SoD HoW
--     execute burn: below SOD_EXECUTE_FIGHT_PCT the cue fires without the
--     hp read; nil = unknown = archived hp-only rule).
--   * SoD-variant gates (all nil/false = unknown = withheld, never prompted):
--     holy_power_stacks (1226461 stacks, APL-cited, in-client UNCONFIRMED),
--     holy_power_set_known (1226460, OR-gate for DS per the twist GAP),
--     sod_dual_seal_active (stack Judge dual gate), sod_t2_known (467518,
--     wrath Judge gate), sod_naxx_known (1219193, stack HW gate),
--     sod_libram_known (1214298, shock AM gate), am_rune_known (407624),
--     sunlight_remaining (1239543), templar_stack_remaining (1240574),
--     templar_wrath_remaining (1226464), soc_remaining_seconds /
--     som_remaining_seconds (stack dual timers, SoC 20920r5 + SoM 407798).
--   * Ready = remaining <= max(gcd_remaining, 0): castable when the GCD frees.
--   * out reuses the archived channels so the provider mapping is untouched:
--     action "cs"; action "sob" (Divine Storm - the sob slot carries the DS
--     texture on FCFS families, same key); judge_call (Judgement cue);
--     filler_kind "consecration" | "exorcism" | "how" (Holy Wrath on Wrath,
--     Hammer of Wrath on SoD) | "holy_shock" | "aura_mastery" (shockadin;
--     new slots carry them, same key). hold is true only when nothing is
--     ready (wait on the first known ability); riding never;
--     waiting_judgement always false.
--   * inputs.inputs_unknown (optional bool, M6) passes through to
--     out.inputs_unknown exactly as in evaluate above.
--=========================================================================================

-- Priority orders, first match wins (sourced above; index order is the contract).
--
-- WRATH carries the WotLK APL's UTILITY BAND at the front (the APL layer,
-- bench/rotation_gap_vs_apl_2026-10-20.md §6.2 - the APL file was re-fetched
-- on 2026-10-20 and every group expanded inline):
--   * "hor"        Hand of Reckoning 67485 - the APL's i=1, its TOP row.
--   * "how_wrath"  Hammer of Wrath 48806 - the APL's i=2 (the WotLK spell, not
--                  the Era/Forever execute Hammer of Wrath the "how" key names;
--                  the sim gates the cast on the execute phase, so the arm asks
--                  for it only below 20 % target health).
-- The damage rows below them keep their shipped relative order (cs, judge, ds,
-- cons, exo, hw): the utility band is ADDED above them, never a re-cut of the
-- shipped order. The APL's third row (Judgement of Wisdom 53408) is NOT in the
-- band - it shares the 10 s judgement cooldown with the shipped "judge" row
-- (Judgement of Light 20271), so an arm would displace the shipped judgement
-- cue; that row ships in the ROTATION TABLE with engine = false and the reason
-- filed (bench/paladin_apl_utility_build_2026-10-20.md §4).
local FCFS_ORDER_WRATH = { "hor", "how_wrath", "cs", "judge", "ds", "cons", "exo", "hw" }
local FCFS_ORDER_SOD = { "exo", "cs", "ds", "judge", "cons", "how" }
-- SoD-variant orders (bench/sod_paladin_variants_2026-10-19.md §3-§6):
--   * stack (§3): DS stack-gated > CS > Exo > HW (Undead + Naxx-6pc) > Cons r5 >
--     Judge dual-only last. Maintenance (dual 1 s refreshes) overrides below.
--   * shock (§4): Exo core > AM (Libram-gated, 3 stacks) > HS (3 stacks) > CS.
--     Sunlight/Templar maintenance elevates AM/HS above Exo below. No Cons/HW
--     line in the APL (order lacks them).
--   * wrath-like (§6): DS (3 stacks) > CS > Exo > Judge (T2-2pc-gated,
--     GCD fallback) > Cons (fallback ONLY when DS/CS/Exo all >1.5 s out or
--     stacks <3). Templar-wait holds for DS below. DS ungated fallback: when
--     CS/Exo/Judge/Cons are all ineligible, DS prompts if known+ready even
--     without stacks (second DS line in the APL).
local FCFS_ORDER_SOD_STACK = { "ds", "cs", "exo", "hw", "cons", "judge" }
local FCFS_ORDER_SOD_SHOCK = { "exo", "am", "hs", "cs" }
local FCFS_ORDER_SOD_WRATH = { "ds", "cs", "exo", "judge", "cons" }

-- The five priority tables, published so no caller has to copy them (the
-- practice rotation table and the priority-order drill read them instead of
-- duplicating the order; a copy would drift from the engine on the next
-- order change). READ-ONLY: the tables are module-level and shared, so a
-- caller that mutates one changes every later tick. fcfs_order(mode) returns
-- the table for one mode (nil for an unknown mode).
st.nextaction.FCFS_ORDERS = {
    wrath = FCFS_ORDER_WRATH,
    sod = FCFS_ORDER_SOD,
    sod_stack = FCFS_ORDER_SOD_STACK,
    sod_shock = FCFS_ORDER_SOD_SHOCK,
    sod_wrath = FCFS_ORDER_SOD_WRATH,
}

function st.nextaction.fcfs_order(mode)
    if type(mode) ~= "string" then
        return nil
    end
    return st.nextaction.FCFS_ORDERS[mode]
end

-- Pure: known cooldown (nil / 999 sentinel means the spell is unavailable here).
local function fcfs_known(remaining)
    return remaining ~= nil and remaining < 999
end

-- Pure: eligibility WITHOUT readiness (known spell + mode gates). Readiness is
-- tested separately so the nothing-ready fallback can wait on a known ability.
-- New SoD-variant branches (sod_stack / sod_shock / sod_wrath) only fire on
-- those modes; "wrath" and "sod" (Exodin) run bit-identically below.
local function fcfs_eligible(mode, key, inputs)
    if key == "cs" then
        return inputs.cs_known ~= false and fcfs_known(inputs.cs_remaining)
    elseif key == "judge" then
        if not fcfs_known(inputs.judge_remaining) then
            return false
        end
        if mode == "sod_stack" then
            -- p8-stack APL (bench §3): Judge ONLY when BOTH seals are
            -- simultaneously active (dual-seal gate, last line). Unknown
            -- (nil/false) withholds, never prompts.
            return inputs.sod_dual_seal_active == true
        end
        if mode == "sod_wrath" then
            -- p8-wrath APL (bench §6): Judge gated on S03 T2 Ret 2P Bonus
            -- known (467518, APL-cited, in-client UNCONFIRMED). Unknown
            -- withholds.
            return inputs.sod_t2_known == true
        end
        return true
    elseif key == "ds" then
        if not fcfs_known(inputs.ds_remaining) then
            return false
        end
        if mode == "sod_stack" or mode == "sod_wrath" then
            -- DS stack gate (bench §3/§6: DS stack-gated / DS at 3 stacks;
            -- Holy-Power stacks 1226461, APL-cited, in-client UNCONFIRMED).
            -- OR set-unknown mirrors the twist GAP pattern (bench §1: 3 stacks
            -- OR set-unknown 1226460): without the set the gate cannot apply,
            -- so DS prompts (archived); with the set DS needs 3 stacks.
            -- Unknown stacks + known set withholds (unknown-hides).
            if inputs.holy_power_set_known ~= true then
                return true
            end
            return inputs.holy_power_stacks == 3
        end
        return true
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
        if mode == "sod_wrath" then
            -- p8-wrath APL (bench §6): Cons filler ONLY when DS/CS/Exo all
            -- >1.5 s out (or stacks <3). Unknown cooldowns cannot prove the
            -- gap, so they withhold (unknown-hides); unknown stacks keep only
            -- the gap clause. Mana gate above still applies.
            local stacks = inputs.holy_power_stacks
            if type(stacks) == "number" and stacks == stacks and stacks < 3 then
                return true
            end
            local gap = st.nextaction.SOD_WRATH_CONS_FALLBACK_SECONDS
            local ds = inputs.ds_remaining
            local cs = inputs.cs_remaining
            local exo = inputs.exo_remaining
            return type(ds) == "number" and ds == ds and ds > gap
                and type(cs) == "number" and cs == cs and cs > gap
                and type(exo) == "number" and exo == exo and exo > gap
        end
        if mode == "sod_stack" then
            -- p8-stack APL (bench §3): Cons r5, mana-gated, no cleave gate
            -- named (single-target APL). Unknown (nil) keeps the archived
            -- mana-only suggestion.
            return true
        end
        if mode == "sod_shock" then
            -- p8-shockadin APLs (bench §4-§5): no Cons line (Exo/HS/CS only).
            return false
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
        if not fcfs_known(inputs.hw_remaining) then
            return false
        end
        if inputs.creature_type == nil
            or st.nextaction.exorcism_target_types[inputs.creature_type] ~= true then
            return false
        end
        if mode == "sod_stack" then
            -- p8-stack APL (bench §3): Holy Wrath r2 on Undead w/ Naxx-6pc
            -- (1219193, APL-cited, in-client UNCONFIRMED). Unknown withholds.
            return inputs.sod_naxx_known == true
        end
        if mode == "sod_shock" or mode == "sod_wrath" then
            -- Neither shockadin (§4-§5) nor wrath-like (§6) lists Holy Wrath.
            return false
        end
        return true
    elseif key == "hor" then
        -- Wrath Hand of Reckoning (the WotLK APL's top row, 67485): a pure
        -- cooldown. The provider feeds the remaining time only when the client's
        -- own spell book knows the spell, so an unknown read (nil) withholds it
        -- and a build without the talent is never prompted (unknown-hides).
        if mode ~= "wrath" then
            return false
        end
        return fcfs_known(inputs.hor_remaining)
    elseif key == "how_wrath" then
        -- Wrath Hammer of Wrath (48806): the WotLK APL's second row. The sim's
        -- own spell gates the cast on the execute phase
        -- (sim wowsims/wotlk sim/paladin/hammer_of_wrath.go:31-32
        -- ExtraCastCondition: sim.IsExecutePhase20()), so the arm asks for it
        -- only below 20 % target health. An unknown target health withholds it
        -- (unknown-hides): the arm never asks for a spell the client cannot
        -- cast.
        if mode ~= "wrath" then
            return false
        end
        if not fcfs_known(inputs.how_wrath_remaining) then
            return false
        end
        local hp = inputs.target_health_pct
        return type(hp) == "number" and hp == hp and hp < 20
    elseif key == "how" then
        if mode == "sod_stack" or mode == "sod_shock" or mode == "sod_wrath" then
            -- No HoW line in the stack (§3), shockadin (§4-§5) or wrath-like
            -- (§6) p8 APLs (stack uses HW, shock uses HS, wrath-like uses DS).
            return false
        end
        -- SoD Hammer of Wrath: below 20% target health, own cooldown. The
        -- execute burn fires below SOD_EXECUTE_FIGHT_PCT fight remaining
        -- without the hp read; nil fight data keeps the archived hp rule.
        if not fcfs_known(inputs.how_remaining) then
            return false
        end
        if type(inputs.target_health_pct) == "number"
            and inputs.target_health_pct < 20 then
            return true
        end
        local fight_left = inputs.fight_remaining_pct
        return type(fight_left) == "number"
            and fight_left < st.nextaction.SOD_EXECUTE_FIGHT_PCT
    elseif key == "hs" then
        -- Shockadin Holy Shock (bench §4: 20930r3, max rank per holy_shock.go;
        -- HS at 3 stacks; APL-cited, in-client UNCONFIRMED). Shock mode only;
        -- unknown stacks/cooldown withholds (unknown-hides). No mana gate
        -- named in the APL (UNCONFIRMED); readiness via the HS cooldown.
        if mode ~= "sod_shock" then
            return false
        end
        if not fcfs_known(inputs.hs_remaining) then
            return false
        end
        return inputs.holy_power_stacks == 3
    elseif key == "am" then
        -- Shockadin Aura Mastery (bench §4: 407624 legs rune, Sanctified
        -- holy-multiplier, Libram-of-Sanctity-gated 1214298; AM + HS at
        -- 3 stacks; APL-cited, in-client UNCONFIRMED). Shock mode only.
        if mode ~= "sod_shock" then
            return false
        end
        if not fcfs_known(inputs.am_remaining) then
            return false
        end
        if inputs.am_rune_known ~= true then
            return false
        end
        if inputs.sod_libram_known ~= true then
            return false
        end
        return inputs.holy_power_stacks == 3
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
    elseif key == "hor" then
        return inputs.hor_remaining
    elseif key == "how_wrath" then
        return inputs.how_wrath_remaining
    elseif key == "hs" then
        return inputs.hs_remaining
    elseif key == "am" then
        return inputs.am_remaining
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
        elseif mode == "sod_stack" then
            order = FCFS_ORDER_SOD_STACK
        elseif mode == "sod_shock" then
            order = FCFS_ORDER_SOD_SHOCK
        elseif mode == "sod_wrath" then
            order = FCFS_ORDER_SOD_WRATH
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
    -- M6: the caller's explicit "core inputs unusable" bit (the paladin provider
    -- sets it when the swing fields are not usable); the UI renders "…" on it.
    local inputs_unknown = inputs.inputs_unknown == true
    -- SoD seal maintenance (p8-exodin APL: Judge + primary-seal reseal above
    -- the damage order while the seal runs out). nil remaining = unknown =
    -- archived order. Wrath keeps the archived order (different seal cadence).
    -- The Judge elevation reuses the judge channel (no new slot); the reseal
    -- half is the seal_maintenance advisory below (its slot is filed).
    local seal_left = inputs.seal_remaining_seconds
    if type(seal_left) ~= "number" or seal_left ~= seal_left then
        seal_left = nil
    end
    local seal_expiring = mode == "sod" and seal_left ~= nil
        and seal_left < st.nextaction.SEAL_MAINTAIN_RESEAL_SECONDS
    -- Stack dual maintenance (p8-stack APL, bench §3): independent SoC <=1 s /
    -- SoM <=1 s refreshes (SoC 20920r5 + SoM 407798, APL-cited, in-client
    -- UNCONFIRMED). Either timer inside the line maintains (reseal advisory);
    -- unlike Exodin the Judge channel is NOT elevated here (stack Judge is
    -- dual-gated only, last APL line). Unknown (nil/NaN) maintains nothing.
    local soc_left = inputs.soc_remaining_seconds
    if type(soc_left) ~= "number" or soc_left ~= soc_left then
        soc_left = nil
    end
    local som_left = inputs.som_remaining_seconds
    if type(som_left) ~= "number" or som_left ~= som_left then
        som_left = nil
    end
    local stack_expiring = mode == "sod_stack"
        and ((soc_left ~= nil
                and soc_left < st.nextaction.SOD_STACK_SEAL_RESEAL_SECONDS)
            or (som_left ~= nil
                and som_left < st.nextaction.SOD_STACK_SEAL_RESEAL_SECONDS))
    -- Shockadin Sunlight/Templar maintenance (bench §4): Aura Mastery + Holy
    -- Shock woven on Sunlight (1239543 <=1.5 s) / Templar-stack (1240574
    -- <=1.5 s at 3 stacks). Either condition elevates AM/HS above Exo below
    -- (the sim shape); unknown withholds. Seal/Judge 1.5 s maintenance
    -- (primary role UNCONFIRMED for p8: SoR per P5/P7 predecessors vs SoM per
    -- P7 2H) is FILED in the gather (classes/paladin.lua) — this engine only
    -- carries the 1.5 s threshold constant for that lane.
    local function num_or_nil(v)
        if type(v) == "number" and v == v then
            return v
        end
        return nil
    end
    local sun_left = num_or_nil(inputs.sunlight_remaining)
    local tst_left = num_or_nil(inputs.templar_stack_remaining)
    local hp_stacks = inputs.holy_power_stacks
    if type(hp_stacks) ~= "number" or hp_stacks ~= hp_stacks then
        hp_stacks = nil
    end
    local shock_maint = mode == "sod_shock"
        and ((sun_left ~= nil and sun_left <= 1.5)
            or (tst_left ~= nil and tst_left <= 1.5 and hp_stacks == 3))
    -- Wrath-like Templar wait (bench §6: Templar 1226464 <=1 s at 3 stacks
    -- waits for DS). While the wait holds the tick holds on DS (no lower
    -- priority prompt); unknown withholds the wait (archived order).
    local twr_left = num_or_nil(inputs.templar_wrath_remaining)
    local templar_wait = mode == "sod_wrath" and twr_left ~= nil
        and twr_left <= st.nextaction.SOD_TEMPLAR_WAIT_SECONDS
        and hp_stacks == 3
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
        -- Seal maintenance above the damage order: an expiring seal judges
        -- first while Judge is ready, even under a ready higher-priority
        -- button (the sim shape). Otherwise the never-wait winner stands.
        -- Wrath-like Templar-wait and shockadin Sunlight/Templar maintenance
        -- elevate above it (their APL wait/weave outranks the seal line).
        if templar_wait and fcfs_known(inputs.ds_remaining) then
            winner = "ds"
            hold = true
        elseif shock_maint then
            if fcfs_eligible(mode, "am", inputs)
                and fcfs_remaining("am", inputs) <= gcd_remaining then
                winner = "am"
            elseif fcfs_eligible(mode, "hs", inputs)
                and fcfs_remaining("hs", inputs) <= gcd_remaining then
                winner = "hs"
            end
        elseif seal_expiring and fcfs_eligible(mode, "judge", inputs)
            and fcfs_remaining("judge", inputs) <= gcd_remaining then
            winner = "judge"
        end
        if winner == nil then
            -- Nothing castable: wait on the soonest-known ability (hold), never
            -- prompt an unknown spell. Priority order breaks readiness ties. No
            -- known ability at all: stay empty. Wrath-like DS ungated fallback
            -- (bench §6, second DS line): when CS/Exo/Judge/Cons are all
            -- ineligible, DS prompts if known+ready even without stacks.
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
            if winner == nil and mode == "sod_wrath"
                and fcfs_known(inputs.ds_remaining)
                and inputs.ds_remaining <= gcd_remaining then
                winner = "ds"
            end
        end
        if winner == "cs" then
            action = "cs"
        elseif winner == "hor" then
            -- The WotLK APL's top row (Hand of Reckoning 67485): its own slot
            -- key, so the frame lights the Hand of Reckoning icon.
            action = "hor"
        elseif winner == "how_wrath" then
            -- The WotLK APL's second row (Hammer of Wrath 48806): its own slot
            -- key (the "how" key is the Era/Forever execute Hammer of Wrath).
            action = "how_wrath"
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
        elseif winner == "hs" then
            filler_kind = "holy_shock"
        elseif winner == "am" then
            filler_kind = "aura_mastery"
        end
    end

    out.action = action
    out.hold = hold
    out.riding = false
    out.judge_call = judge_call
    out.filler_kind = filler_kind
    out.prediction_hold = 0
    out.waiting_judgement = false
    out.inputs_unknown = inputs_unknown
    out.stopattack = false
    out.prepull_ready = false
    out.seal_maintenance = seal_expiring or stack_expiring == true
        or shock_maint == true or templar_wait == true
    out.rank1_advice = false
    out.hard_wait = false
    return out
end
