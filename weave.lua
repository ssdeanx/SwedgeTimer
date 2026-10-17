--=========================================================================================
-- Weave: spell-weaving assist for Enhancement Shamans. Pure math, no WoW API.
--
-- Ported from the read-only reference SuperSwingTimer-WoW/SuperSwingTimer_Weaving.lua:
--   * GetEffectiveSpellCastTime (lines 95-235): live spell haste is maxed against buff
--     haste (Bloodlust/Heroism/Berserking), never multiplied with it; Maelstrom Weapon
--     cuts 20% of the cast per stack, capped at 5 stacks, and is instant at 5; the
--     instant-cast buffs (Nature's Swiftness, Elemental Mastery, Power Surge) return 0.
--   * BuildDisplayInfo (lines 498-601): the swing-relative timing model. Marker fraction
--     is the latest swing fraction a cast may start at and still land before the next
--     swing; safe_start_in counts down to that start; clip_amount measures how far the
--     cast would overrun the swing; projected impact fraction is where the cast lands
--     on the swing; spark fraction travels from the cast start toward that landing.
--
-- This module is deliberately PURE (no WoW API calls, no tables owned by the addon) so
-- it can be unit-tested offline with the harness in tests/weave_state.lua. WoW-facing
-- code (cast tracking, auras, bars, options) calls into these helpers rather than
-- re-implementing the rules, so the behaviour has a single source.
--=========================================================================================
local _, st = ...

st.weave = st.weave or {}

-- Spell families shown by the weave assist, in display order.
st.weave.FAMILIES = { "LB", "CL", "HW", "LHW", "CH" }

-- Family colors (r, g, b, a), mirroring the reference WEAVE_SPELL_FAMILY_COLORS
-- (SuperSwingTimer_Constants.lua:812-818).
st.weave.FAMILY_COLORS = {
    LB  = { 0.45, 0.75, 1.00, 1 },  -- light blue
    CL  = { 0.15, 0.45, 0.95, 1 },  -- dark blue
    HW  = { 0.25, 0.90, 0.35, 1 },  -- green
    LHW = { 0.55, 1.00, 0.55, 1 },  -- light green
    CH  = { 1.00, 0.90, 0.20, 1 },  -- yellow
}

-- Tracked spell families. IDs run low rank -> high rank; the runtime resolves the
-- highest known rank for the active character (reference ResolveSpellInfo walks the
-- list backwards, SuperSwingTimer_Weaving.lua:271-294).
st.weave.SPELL_GROUPS = {
    { abbrev = "LB",  label = "Lightning Bolt",      ids = { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208, 25448, 25449 } },
    { abbrev = "CL",  label = "Chain Lightning",     ids = { 421, 930, 2860, 10605, 25439, 25442 } },
    { abbrev = "HW",  label = "Healing Wave",        ids = { 331, 332, 547, 913, 939, 959, 8005, 10395, 10396, 25357, 25391, 25396 } },
    { abbrev = "LHW", label = "Lesser Healing Wave", ids = { 8004, 8008, 8010, 10466, 10467, 10468, 25420 } },
    { abbrev = "CH",  label = "Chain Heal",          ids = { 1064, 10622, 10623, 25422, 25423 } },
}

-- Maelstrom Weapon: max 5 stacks, each stack cuts 20% of the cast time; 5 stacks make
-- the cast instant (reference SuperSwingTimer_Weaving.lua:183-222).
st.weave.MW_MAX_STACKS = 5
st.weave.MW_PER_STACK = 0.20

-- Pure: does Maelstrom Weapon exist on this client family? Wrath and later have it
-- (the Wrath Enhancement talent 53817; retail keeps it as an Enhancement proc), but
-- TBC has NO Maelstrom Weapon at all, and Classic Era-base has none either - LB/CL
-- hard-casts there always clip the swing, so the breakpoint markers and the MW guide
-- rules would teach the wrong play. Unknown/nil families read true (preserve the
-- current behaviour wherever MW cannot be ruled out).
-- SoD REFINEMENT (live): Season of Discovery shares the ERA family token but HAS
-- Maelstrom Weapon as a rune (408505, already in the aura scan). The second arg is
-- the aura-observed latch the shaman module feeds (true once the MW aura/stack
-- signal has actually been seen this session): ERA + observed reads true, ERA never
-- observed stays false, TBC stays false even when observed (no MW there - never
-- enable on a guess), and every other family ignores the latch (Wrath behaviour
-- byte-identical). Only boolean true enables; anything else reads as unobserved.
-- FOREVER NOTE (UNCONFIRMED, docs/research/forever_beta.md): Maelstrom Weapon at
-- 60 is theorycraft-unconfirmed ("sims will eventually tell us"), but Forever
-- keeps the unconditional read for now - tests/bars_state.lua pins the Forever
-- shaman's weave breakpoint marker with no aura observed, so latch-gating
-- Forever would regress the pinned visuals. Revisit once MW at 60 is confirmed
-- in-game (the aura scan already matches the 408505/53817 ids AND the
-- "Maelstrom Weapon" name fallback, so a Forever rank would latch by name).
-- RESIDUAL SoD specifics (partly modelled): the 5-stack spender choice
-- (Lightning Bolt vs Lava Burst) is surfaced by re-pointing the weave slot at
-- Lava Burst when the rune is known (classes/shaman.lua resolve_guide_icons); Lava
-- Lash / Feral Spirit priority rides the Wrath cooldown slots on SoD clients that
-- know those spells; Rolling Thunder stack-gen is not modelled - FS/ES already
-- alternate. The engine prompts the generic weave slot at 5 stacks only.
function st.weave.has_maelstrom_weapon(family, mw_observed)
    if family == "TBC" then return false end
    if family == "ERA" then return mw_observed == true end
    return true
end

-- Pure: clamp a fraction into [0, 1]; non-numbers read as 0 (reference ClampFraction,
-- SuperSwingTimer_Weaving.lua:445-451).
function st.weave.clamp_fraction(v)
    if type(v) ~= "number" then return 0 end
    return math.max(0, math.min(v, 1))
end

-- Pure: spell-haste percent -> cast-speed multiplier. Missing or negative haste reads
-- as 0% -> multiplier 1 (reference SuperSwingTimer_Weaving.lua:52-54).
function st.weave.get_haste_multiplier(spell_haste_percent)
    local haste = spell_haste_percent
    if type(haste) ~= "number" or haste < 0 then haste = 0 end
    return 1 + (haste / 100)
end

-- Pure: live haste multiplier. Buff haste is maxed against the spell-haste multiplier,
-- never multiplied with it (reference SuperSwingTimer_Weaving.lua:92).
function st.weave.get_max_haste_multiplier(spell_haste_percent, buff_multiplier)
    local haste = st.weave.get_haste_multiplier(spell_haste_percent)
    local buff = buff_multiplier
    if type(buff) ~= "number" then buff = 1 end
    return math.max(haste, buff)
end

-- Pure: Maelstrom Weapon cast-time multiplier for a stack count, clamped into
-- [0, MW_MAX_STACKS]; never below 0 (reference SuperSwingTimer_Weaving.lua:189-190).
function st.weave.get_maelstrom_multiplier(stacks)
    local n = stacks
    if type(n) ~= "number" or n < 0 then
        n = 0
    elseif n > st.weave.MW_MAX_STACKS then
        n = st.weave.MW_MAX_STACKS
    end
    local mult = 1 - (st.weave.MW_PER_STACK * n)
    if mult < 0 then mult = 0 end
    return mult
end

-- Pure: effective cast time in seconds.
--   instant          : an instant-cast buff is up -> nothing to schedule (0).
--   maelstrom <= 0   : 5 stacks (or the caller reporting the instant state) -> 0.
--   Otherwise base / haste * maelstrom, with a dead or missing haste treated as 1 and
--   a missing Maelstrom multiplier treated as 1 (no reduction). Never negative.
function st.weave.get_effective_cast_time(base_cast_seconds, haste_multiplier, maelstrom_multiplier, instant)
    if instant then return 0 end
    local mw = maelstrom_multiplier
    if type(mw) ~= "number" then mw = 1 end
    if mw <= 0 then return 0 end
    local base = base_cast_seconds
    if type(base) ~= "number" or base <= 0 then return 0 end
    local haste = haste_multiplier
    if type(haste) ~= "number" or haste <= 0 then haste = 1 end
    local effective = (base / haste) * mw
    if effective < 0 then effective = 0 end
    return effective
end

-- Pure: swing fraction of the latest safe cast start. A cast begun after this fraction
-- lands after the next swing. duration <= 0 -> 0 (reference
-- SuperSwingTimer_Weaving.lua:552).
function st.weave.get_marker_fraction(duration, effective_cast_seconds, latency_seconds)
    if type(duration) ~= "number" or duration <= 0 then return 0 end
    local cast = effective_cast_seconds or 0
    local latency = latency_seconds or 0
    return st.weave.clamp_fraction((duration - (cast + latency)) / duration)
end

-- Pure: seconds until the latest safe cast start; negative once the window has passed.
-- Deliberately unclamped (reference SuperSwingTimer_Weaving.lua:541).
function st.weave.get_safe_start_in(next_swing_expiration, now, latency, effective_cast)
    return (next_swing_expiration or 0) - (now or 0) - (latency or 0) - (effective_cast or 0)
end

-- Pure: how far a running cast would overrun the next swing, floored at 0
-- (reference SuperSwingTimer_Weaving.lua:542).
function st.weave.get_clip_amount(now, latency, cast_remaining, next_swing_expiration)
    local amount = ((now or 0) + (latency or 0) + (cast_remaining or 0)) - (next_swing_expiration or 0)
    if amount < 0 then amount = 0 end
    return amount
end

-- Pure: is the cast clipped? True when it overruns the swing (clip_amount > 0) or was
-- started after the latest safe start (cast_start_fraction beyond the marker)
-- (reference SuperSwingTimer_Weaving.lua:570).
function st.weave.is_clipped(clip_amount, cast_start_fraction, marker_fraction)
    if (clip_amount or 0) > 0 then return true end
    if cast_start_fraction ~= nil and cast_start_fraction > marker_fraction then return true end
    return false
end

-- Pure: where the running cast is projected to land within the current swing, as a
-- fraction from the swing's start (reference SuperSwingTimer_Weaving.lua:554).
function st.weave.get_projected_impact_fraction(now, cast_remaining, latency, swing_start, duration)
    local impact = (now or 0) + (cast_remaining or 0) + (latency or 0)
    return st.weave.clamp_fraction((impact - (swing_start or 0)) / (duration or 0))
end

-- Pure: where the cast started within the current swing, as a fraction from the
-- swing's start (reference SuperSwingTimer_Weaving.lua:492 and 557).
function st.weave.get_cast_start_fraction(cast_start_time, swing_start, duration)
    return st.weave.clamp_fraction(((cast_start_time or 0) - (swing_start or 0)) / (duration or 0))
end

-- Pure: spark position within the swing. The spark travels from where the cast started
-- toward where it is projected to land as the cast progresses
-- (reference SuperSwingTimer_Weaving.lua:563): start + (projected - start) * progress.
-- Both endpoints are clamped into [0, 1] first, and the progress is clamped the same
-- way the reference clamps it (elapsed / duration before use).
function st.weave.get_spark_fraction(cast_start_fraction, projected_impact_fraction, cast_progress)
    local start = st.weave.clamp_fraction(cast_start_fraction)
    local projected = st.weave.clamp_fraction(projected_impact_fraction)
    local progress = st.weave.clamp_fraction(cast_progress)
    return st.weave.clamp_fraction(start + ((projected - start) * progress))
end

--=========================================================================================
-- Shaman trackers (ported from the reference's shaman block,
-- SuperSwingTimer_ClassMods.lua 3334-4513): windfury weapon ICD (3766-3848), flame shock
-- target bar (3850-4056), Stormstrike / Shamanistic Rage badges (3695-3760) and the
-- shield charge tracker (4058-4209). Kept pure and separately testable like the weave
-- math above; classes/shaman.lua owns the WoW API reads and the widgets.
--=========================================================================================

-- Windfury Weapon internal cooldown: 3 s counted from the last mainhand swing
-- (reference SuperSwingTimer_ClassMods.lua:3766). Tint thresholds are the reference's
-- (3838-3846): remaining > 2 s is "red" (just procced), down to > 0.5 s "orange",
-- otherwise "green" (ready).
st.weave.WINDFURY_ICD_SECONDS = 3
st.weave.WINDFURY_TINT_RED_ABOVE = 2.0
st.weave.WINDFURY_TINT_ORANGE_ABOVE = 0.5

-- Windfury Weapon proc ceiling: max 20 procs/min (the 3 s ICD is shared across
-- hands, so dual wielding cannot circumvent it; Windfury Totem has NO ICD -
-- docs/research/tbc_minmax.md). SLOWEST-WEAPON NOTE (documented, not modelled):
-- double WF wants the slowest weapons in BOTH hands (more damage per proc, fewer
-- ICD collisions); there is no weapon-speed input here, so the engine cannot
-- score it - the delay-if-fishing rule in shaman_guide.lua is the modelable half
-- (hold Stormstrike while the ICD clears inside this swing).
st.weave.WINDFURY_MAX_PROCS_PER_MINUTE = 20

-- Pure: is the Windfury proc budget spent? count >= 20 reads capped; a
-- missing/non-number count never caps (the engine never holds on a guess).
function st.weave.is_windfury_proc_capped(procs_this_minute)
    return type(procs_this_minute) == "number" and procs_this_minute >= st.weave.WINDFURY_MAX_PROCS_PER_MINUTE
end

-- Flame Shock target bar: the fallback duration covers auras whose duration payload is
-- missing; the glow window is the reference's final 4 s (SuperSwingTimer_ClassMods.lua
-- 3850-3852, 3866).
st.weave.FLAME_SHOCK_FALLBACK_DURATION = 12
st.weave.FLAME_SHOCK_GLOW_SECONDS = 4

-- Shield charge tracker: Lightning Shield can reach 4 charges (talent/era variants),
-- Water Shield tops out at 3 (reference SuperSwingTimer_ClassMods.lua:4058-4209 draws a
-- fixed row per shield type, with the empty slots dimmed).
st.weave.SHIELD_MAX_CHARGES = {
    lightning = 4,
    water = 3,
}

-- Pure: seconds left on the windfury internal cooldown, measured from the last mainhand
-- swing stamp. A missing/non-positive stamp returns nil (nothing to show); a stamp in
-- the future or an elapsed cooldown floors at the full window / 0 (reference
-- SuperSwingTimer_ClassMods.lua:3836-3838).
function st.weave.get_windfury_icd_remaining(last_swing_time, now)
    if type(last_swing_time) ~= "number" or last_swing_time <= 0 then return nil end
    local since_swing = (now or 0) - last_swing_time
    if since_swing < 0 then since_swing = 0 end
    local remaining = st.weave.WINDFURY_ICD_SECONDS - since_swing
    if remaining < 0 then remaining = 0 end
    return remaining
end

-- Pure: windfury ICD tint bucket for a remaining countdown: "red" | "orange" | "green".
-- Missing readings read "green" (ready); the strip only draws while the buff is up, so
-- nil never reaches a tint (reference SuperSwingTimer_ClassMods.lua:3840-3846).
function st.weave.get_windfury_tint_bucket(remaining)
    if type(remaining) ~= "number" then return "green" end
    if remaining > st.weave.WINDFURY_TINT_RED_ABOVE then return "red" end
    if remaining > st.weave.WINDFURY_TINT_ORANGE_ABOVE then return "orange" end
    return "green"
end

-- Pure: remaining seconds of the Flame Shock debuff for display, floored at 0, plus the
-- bar's total span. A missing/non-positive expiration stamp falls back to the full
-- duration, and a missing/non-positive duration falls back to the Flame Shock default
-- (reference SuperSwingTimer_ClassMods.lua:4028-4036).
function st.weave.get_flame_shock_remaining(duration, expiration_time, now)
    local total = duration
    if type(total) ~= "number" or total <= 0 then
        total = st.weave.FLAME_SHOCK_FALLBACK_DURATION
    end
    local expires = expiration_time
    if type(expires) == "number" and expires > 0 then
        local remaining = expires - (now or 0)
        if remaining < 0 then remaining = 0 end
        return remaining, total
    end
    return total, total
end

-- Pure: should the Flame Shock bar glow? Only while the debuff is up and inside the
-- final seconds (reference SuperSwingTimer_ClassMods.lua:3866).
function st.weave.should_flame_shock_glow(remaining)
    return type(remaining) == "number"
        and remaining > 0 and remaining <= st.weave.FLAME_SHOCK_GLOW_SECONDS
end

-- Pure: remaining seconds of a spell cooldown, or nil when the spell is ready (or the
-- client reports no usable cooldown). Reference GetShamanCooldownRemaining,
-- SuperSwingTimer_ClassMods.lua:3665-3677.
function st.weave.get_cooldown_remaining(start_time, duration, now)
    if type(start_time) ~= "number" or type(duration) ~= "number" or duration <= 0 then
        return nil
    end
    local remaining = (start_time + duration) - (now or 0)
    if remaining <= 0 then return nil end
    return remaining
end

-- Pure: shield charge tracker display state. slots is the fixed rectangle count for the
-- shield type (0 when the type is unknown); filled is the aura's charge count clamped
-- into [0, slots], with a missing/non-positive count reading as full (reference
-- SuperSwingTimer_ClassMods.lua:4141-4144 falls back to the full row).
function st.weave.get_shield_tracker_state(shield_type, count)
    local slots = st.weave.SHIELD_MAX_CHARGES[shield_type]
    if type(slots) ~= "number" then return 0, 0 end
    local filled = count
    if type(filled) ~= "number" or filled < 1 then
        filled = slots
    else
        filled = math.floor(filled + 0.5)
    end
    if filled > slots then filled = slots end
    return slots, filled
end

-- Totem twisting (TBC Enhancement core: WF <-> GoA alternation, WF rank 1 downranked):
-- the raid keeps both the Windfury weapon imbue and the Grace of Air agility aura by
-- re-dropping the OTHER air totem roughly every TOTEM_TWIST_PERIOD_SECONDS seconds
-- (the weapon imbue outlives its totem). CADENCE MODEL (docs/research/tbc_minmax.md,
-- community-tested, [uncertain]): the WF totem pulses its 9 s buff
-- (TOTEM_TWIST_PULSE_SECONDS); the alternation cycle is ~10 s, holding ~83% GoA
-- uptime. GCD-LOCKOUT COST (documented, not modelled: no shock/SS damage inputs
-- here): each twist eats a 3 s GCD, costing ~20% shock and ~10% Stormstrike
-- damage - twist on the 8-10 s counter, never early. DOWNRANK NOTE: twist with
-- WF rank 1 (mana sustain alongside Judgement of Wisdom / Shamanistic Rage /
-- Mana Spring Totem); max rank drains the mana pool in 1-2 min of twisting.
-- LIVE: classes/shaman.lua stamps the last
-- drop on every Windfury/Grace of Air SUCCEEDED (id, name token or live spell name,
-- so unconfirmed ranks stamp by name) and reconciles it with the air-slot totem
-- clock through compat's api.GetTotemInfo wrapper (ST.SHAMAN.
-- refresh_twist_from_totems); the gather feeds the stamp through
-- get_totem_twist_remaining TBC-only, and the engine's rule 4 prompts when it reads
-- due (0). IN-GAME CONFIRMATION NEEDED on 2.5.6: the air-slot totem ids (WF rank 1
-- downrank, GoA ranks - plug-in point WEAVE_TWIST_TOTEM_IDS), the 8512 icon id, the
-- ~10 s alternation cadence, and the GetTotemInfo start stamp (swing stagger
-- <= 0.4 s is swing-engine territory, out of scope here).
-- FOREVER MODEL (docs/research/forever_beta.md): NO twisting on Forever - totems
-- are party buffs dropped 4-at-once via Call of the Elements and coexist with the
-- Windfury Weapon imbue, so there is no weapon-enchant twist to prompt. The
-- family gate below keeps the feed nil there (pinned by tests); any prompt that
-- assumes weapon-enchant twisting must stay suppressed on FOREVER.
st.weave.TOTEM_TWIST_PERIOD_SECONDS = 10
st.weave.TOTEM_TWIST_PULSE_SECONDS = 9

-- Pure: does this client family twist totems? TBC only. Wrath never twists (its
-- own totem set has no WF/GoA alternation), and Forever runs the party-buff
-- model (totems coexist with imbues - nothing to alternate). Unknown/nil
-- families read false (no prompt on a guess).
function st.weave.is_totem_twist_family(family)
    return family == "TBC"
end

-- Pure: seconds until the next twist drop is due, floored at 0; nil when the last drop
-- is unknown (no prompt on a guess). A future stamp reads the full period (clock
-- skew), mirroring get_windfury_icd_remaining.
function st.weave.get_totem_twist_remaining(last_twist_time, now)
    if type(last_twist_time) ~= "number" or last_twist_time <= 0 then return nil end
    local since_drop = (now or 0) - last_twist_time
    if since_drop < 0 then since_drop = 0 end
    local remaining = st.weave.TOTEM_TWIST_PERIOD_SECONDS - since_drop
    if remaining < 0 then remaining = 0 end
    return remaining
end

-- Magma Totem maintain (Wrath Enhancement #7, docs/research/rotations_wrath.md):
-- the fire totem the guide keeps down. Duration 20 s UNCONFIRMED (needs in-game
-- confirmation on 3.80.2); the refresh window mirrors the Flame Shock default and
-- lives in shaman_guide.lua (MAGMA_REFRESH_DEFAULT, no option: options are frozen).
st.weave.MAGMA_TOTEM_DURATION_SECONDS = 20

-- Pure: seconds until the Magma Totem needs re-dropping, floored at 0; nil when the
-- last drop is unknown (no prompt on a guess). A future stamp reads the full
-- duration (clock skew), mirroring get_totem_twist_remaining.
function st.weave.get_magma_remaining(last_drop_time, now)
    if type(last_drop_time) ~= "number" or last_drop_time <= 0 then return nil end
    local since_drop = (now or 0) - last_drop_time
    if since_drop < 0 then since_drop = 0 end
    local remaining = st.weave.MAGMA_TOTEM_DURATION_SECONDS - since_drop
    if remaining < 0 then remaining = 0 end
    return remaining
end

-- Helpers above are reachable via st.weave and pure (no WoW globals).
if st.debug then st.utils.print_msg('-- Parsed weave.lua correctly') end
