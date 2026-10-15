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

-- Helpers above are reachable via st.weave and pure (no WoW globals).
if st.debug then st.utils.print_msg('-- Parsed weave.lua correctly') end
