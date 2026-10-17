--=========================================================================================
-- Shaman next-action guide: pure decision engine, no WoW API and no clock.
--
-- The fourth provider for the frozen ST.<CLASS>.guide contract (nextaction_ui.lua's
-- header; the paladin ships the first, the warrior the second, the druid the third).
-- The live reads live in classes/shaman.lua (ST.SHAMAN.gather_guide_inputs); this
-- module only consumes the gathered inputs, so it is unit-tested offline by
-- tests/shaman_guide_state.lua.
--
-- FROZEN SPEC - display slots (ST.SHAMAN.guide.slots, ordered, ten):
--   stormstrike  Stormstrike       17364  (swipe: the client-reported cooldown)
--   flameshock   Flame Shock       8050   (swipe: the tracker's target debuff window)
--   weave        catalogue         403    (icon resolved from the weave catalogue at
--                                          post_init; Lightning Bolt rank-1 fallback;
--                                          re-pointed at Lava Burst on SoD, see below)
--   firenova     Fire Nova Totem   1535   (swipe: the client-reported 15 s cooldown;
--                                          rank-1 id, TBC top rank 25547)
--   earthshock   Earth Shock       8042   (no swipe: instant, no cooldown)
--   twist        Windfury Totem    8512   (SKELETON: no swipe; the gather feeds nil
--                                          until a compat totem read lands, so this
--                                          never fires live - id UNCONFIRMED on 2.5.6)
--   feralspirit  Feral Spirit      51533  (swipe: the client-reported cooldown;
--                                          known-gated, nil while unknown)
--   fireele      Fire Elemental    2894   (swipe: the client-reported cooldown;
--                                          known-gated, nil while unknown - id
--                                          UNCONFIRMED, needs in-game confirmation)
--   magma        Magma Totem       8190   (swipe: the fire-slot totem window;
--                                          WRATH-fed only, nil elsewhere - id
--                                          UNCONFIRMED, needs in-game confirmation)
--   lavalash     Lava Lash         60103  (no swipe: cooldown unknown, the client
--                                          length rides while one runs; known-gated,
--                                          nil while unknown - id UNCONFIRMED, needs
--                                          in-game confirmation)
--
-- FROZEN SPEC - inputs (all optional, nil never errors):
--   speed, swing_remaining, gcd_remaining   swing/GCD (api.get_time() domain)
--   casting                                 the live weave cast state
--   mw_available                            the client CAN use Maelstrom Weapon
--                                           (family gate AND the weave_mw_enabled
--                                           kill-switch; nil reads as available so
--                                           older callers keep Wrath behaviour)
--   mw_stacks                               Maelstrom Weapon stacks
--   weave_available                         a catalogue spell resolves AND no cast is
--                                           running
--   flameshock_remaining                    target Flame Shock seconds from the
--                                           tracker; nil = the target does not carry it
--   flameshock_refresh                      db threshold, default 3
--   stormstrike_remaining                   client cooldown after the gather's GCD-echo
--                                           filter; nil/<= 0 = off cooldown
--   windfury_icd_remaining                  Windfury ICD seconds from the last swing,
--                                           while the imbue is up; nil = unknown (the
--                                           engine never holds on a guess)
--   firenova_remaining                      client Fire Nova cooldown after the
--                                           gather's GCD-echo filter; nil/<= 0 = ready
--   twist_remaining                         totem-twist seconds from the twist model;
--                                           nil = unknown (SKELETON: always nil live
--                                           outside TBC)
--   fireele_remaining                       Fire Elemental cooldown after the
--                                           gather's GCD-echo filter AND known gate;
--                                           nil = unknown (never prompts)
--   feralspirit_remaining                   Feral Spirit cooldown, same shape
--   magma_remaining                         Magma Totem seconds from the fire-slot
--                                           model; nil = unknown (never prompts)
--   magma_refresh                           re-drop window, default 3 (no option)
--   lavalash_remaining                      Lava Lash cooldown after the gather's
--                                           GCD-echo filter AND known gate;
--                                           nil = unknown (never prompts)
--
-- FROZEN SPEC - rule order (first match wins; exactly these rules):
--   1. casting -> no action, hold = true, hold_text = "RIDE" (never weave or press
--      anything mid-cast).
--   2. fireele_remaining a number <= 0 -> action "fireele" (Wrath #1; the known
--      gate feeds nil while the spell is unknown, so this never fires on a guess).
--   3. feralspirit_remaining a number <= 0 -> action "feralspirit" (Wrath #2;
--      same known gate).
--   4. mw_available and mw_stacks >= 5 -> action "weave" (the broadcast instant; the
--      rule does not require weave_available - the slot's fallback icon covers an
--      unresolved catalogue). On Era-base/TBC mw_available is false, so no weave is
--      ever prompted where Maelstrom Weapon cannot exist. MW5-ONLY: the old MW>=3
--      hardcast rule is gone (Wrath min/max is MW5-instant-only; a sub-5 hardcast
--      that clips the swing is a DPS loss and this engine cannot verify the cast
--      lands before the swing - Lightning Weaving stays deferred, see below).
--   5. flameshock_remaining nil or <= flameshock_refresh -> action "flameshock". A
--      remaining of exactly the threshold refreshes; nil always refreshes.
--   6. twist_remaining a number <= 0 -> action "twist" (SKELETON: scripted inputs
--      only outside TBC; live inputs are nil there - Wrath has no twisting, and
--      Forever never twists: party-buff totem model, totems coexist with imbues).
--      TBC CADENCE (docs/research/tbc_minmax.md, [uncertain]): 9 s WF pulse on a
--      ~10 s alternation cycle (~83% GoA uptime); each twist eats a 3 s GCD (~20%
--      shock / ~10% Stormstrike damage), so the counter - not eagerness - drives
--      the drop. WF rank 1 downranked for mana.
--   7. stormstrike off cooldown BUT the Windfury ICD expires within this swing
--      (0 < windfury_icd_remaining <= swing_remaining) -> no action, hold = true,
--      hold_text = "WAIT" (delay-if-fishing-WF: let the ICD clear so the
--      Stormstrike-empowered swing can proc Windfury). TBC MICRO
--      (docs/research/tbc_minmax.md): the 3 s ICD caps output at 20 procs/min
--      shared across hands (totem has no ICD); double WF wants the slowest
--      weapons in both hands (documented, not modelled - no weapon-speed input).
--      GCD-agnostic: the tick
--      re-evaluates, so a running GCD just re-holds or moves on.
--   8. stormstrike_remaining nil or <= 0 -> action "stormstrike" ("off cooldown").
--   9. magma_remaining a number <= magma_refresh -> action "magma" (Wrath #7;
--      WRATH-fed only, nil elsewhere - never prompts on a guess).
--   10. firenova_remaining nil or <= 0 -> action "firenova" (Fire Nova on cooldown).
--   11. lavalash_remaining a number <= 0 -> action "lavalash" (Wrath #11 last
--      resort; the known gate feeds nil while the spell is unknown).
--   12. otherwise -> action "earthshock" (the shock filler; SS-debuff gating needs a
--      target-debuff tracker plus in-game confirmation, so it is not modelled yet).
--
--   Wrath order notes (docs/research/rotations_wrath.md deviations, all TBC-parity
--   forced): Earth Shock ranks #9 above Fire Nova #10 in the research, but the
--   frozen TBC chain prompts Nova above the filler - reordering would change TBC
--   behaviour, so Nova stays above Earth Shock. Lava Lash (#11) sits above the
--   ungated Earth Shock fallback so the gated slot can fire at all (shock-cooldown
--   modelling deferred); Shamanistic Rage (#5) and Lightning Shield (#8) have no
--   slots yet (Rage line-up needs encounter context, Shield choice needs mana
--   awareness - both deferred).
--   SoD notes (docs/research/rotations_sod.md): the MW latch already enables rules
--   4/9-class behaviour on SoD (ERA + observed); the 5-stack spender choice (Lava
--   Burst under the Stormstrike debuff when the rune is known, else Lightning Bolt)
--   is surfaced by re-pointing the weave slot at Lava Burst in resolve_guide_icons -
--   the engine keeps prompting "weave". FS/ES already alternate (rules 5 and 12),
--   which spends Rolling Thunder; the Stormstrike-debuff read for the spender is
--   deferred (needs a target-debuff tracker plus in-game confirmation).
--   Frost Shock is NEVER prompted: no rule, no slot (Flame Shock maintain +
--   Earth Shock filler cover the shock globals; Frost has no Wrath/SoD slot).
--   Chain Lightning multi-target (MW5 ST LB vs CL) needs an enemy-count input no
--   client API supplies - deferred (the weave slot stays catalogue-driven); feeding
--   target_count today changes nothing (pinned by test).
--
--   Retail (12.x) inertness: st.family == "RETAIL" short-circuits evaluate to the
--   empty display shape before any rule below. The inert stand-in never reports a
--   swing, but the cast flag (rule 1), the absent-debuff default (rule 5, where nil
--   always refreshes) and the idle-cooldown defaults (rules 8 and 10, where nil
--   reads ready) all answer on Retail, so those rules would prompt with no swing at
--   all. Every other family runs the matrix above unchanged; a nil family (offline
--   callers that predate it) keeps the old behaviour too.
--
--   Forever (1.60.x) adaptation (docs/research/forever_beta.md, all UNCONFIRMED -
--   beta guides, "sims will eventually tell us"):
--   * NO twisting: the gather feeds twist_remaining only on TBC (st.weave.
--     is_totem_twist_family), so rule 6 is dead on Forever - totems are party
--     buffs dropped 4-at-once via Call of the Elements and coexist with the
--     Windfury Weapon imbue, leaving no weapon-enchant twist to prompt.
--   * Rage of the Farseer (personal Bloodlust) rides the buff-haste leg the aura
--     scan already maxes against spell haste (name match, no spell id published);
--     there is no dedicated icon cue - a cooldown-slot cue needs a lane that can
--     extend the ten-slot contract (deferred).
--   * Maelstrom Weapon at 60 is theorycraft-unconfirmed ("sims will eventually
--     tell us"), but the gate keeps the unconditional Forever read for now -
--     tests/bars_state.lua pins the Forever marker with no aura observed. The
--     aura scan already matches the MW ids AND the name fallback, so a Forever
--     rank latches the observed flag by name whenever rule 4 needs it.
--
-- Output: the frozen display fields are overwritten on every call:
--   action, hold, hold_text, filler_slot = nil, judge_slot = nil, rotation_key = nil,
--   waiting_judgement = false.
--=========================================================================================
local _, st = ...

st.shaman_guide = st.shaman_guide or {}

-- Rule constants (frozen; the options panel exposes only the Flame Shock threshold).
st.shaman_guide.FLAMESHOCK_REFRESH_DEFAULT = 3
st.shaman_guide.MAGMA_REFRESH_DEFAULT = 3

-- "Off cooldown": nothing left to wait for. gather filters the GCD echo before the
-- inputs reach this module, so a positive value is a real cooldown. NaN reads as
-- ready (NaN > 0 is false), matching the historical Stormstrike treatment.
local function is_off_cooldown(remaining)
    return not (type(remaining) == "number" and remaining > 0)
end

-- Delay-if-fishing-WF: Stormstrike is ready but the Windfury ICD clears inside this
-- swing, so pressing now wastes the Stormstrike-empowered proc chance. Strictly
-- numeric (nil/NaN never hold), and the ICD must be live (> 0): an elapsed ICD is no
-- reason to wait. swing_remaining <= 0 (the swing is landing now) also presses: the
-- next tick re-evaluates against the fresh swing.
local function should_delay_stormstrike(inputs)
    local wf = inputs.windfury_icd_remaining
    local swing = inputs.swing_remaining
    return type(wf) == "number" and wf > 0
        and type(swing) == "number" and swing > 0 and wf <= swing
end

-- Pure: one engine tick. Reads `inputs`, writes the frozen display fields into the
-- caller-owned `out` table and returns it. See the module header for the rule matrix.
function st.shaman_guide.evaluate(inputs, out)
    inputs = inputs or {}
    if type(out) ~= "table" then
        out = {}
    end

    if st.family == "RETAIL" then
        -- Retail (12.x): no live swing exists (see the header), so no rule may
        -- prompt - not an action, not a HOLD/RIDE/WAIT overlay.
        out.action = nil
        out.hold = false
        out.hold_text = nil
        out.filler_slot = nil
        out.judge_slot = nil
        out.rotation_key = nil
        out.waiting_judgement = false
        return out
    end

    local action
    local hold = false
    local hold_text

    -- Maelstrom availability: the family gate AND the user kill-switch, combined by
    -- the gather. Nil reads as available so callers that predate the input keep the
    -- exact Wrath behaviour.
    local mw_ok = inputs.mw_available ~= false

    if inputs.casting == true then
        -- 1. A cast is in flight: hold.
        hold = true
        hold_text = "RIDE"
    elseif type(inputs.fireele_remaining) == "number" and inputs.fireele_remaining <= 0 then
        -- 2. Fire Elemental ready (Wrath #1).
        action = "fireele"
    elseif type(inputs.feralspirit_remaining) == "number" and inputs.feralspirit_remaining <= 0 then
        -- 3. Feral Spirit ready (Wrath #2).
        action = "feralspirit"
    elseif mw_ok and type(inputs.mw_stacks) == "number" and inputs.mw_stacks >= 5 then
        -- 4. Five Maelstrom Weapon stacks: the weave is instant (MW5-only).
        action = "weave"
    else
        local refresh = inputs.flameshock_refresh
        if type(refresh) ~= "number" then
            refresh = st.shaman_guide.FLAMESHOCK_REFRESH_DEFAULT
        end
        local magma_refresh = inputs.magma_refresh
        if type(magma_refresh) ~= "number" then
            magma_refresh = st.shaman_guide.MAGMA_REFRESH_DEFAULT
        end
        if type(inputs.flameshock_remaining) ~= "number"
            or inputs.flameshock_remaining <= refresh then
            -- 5. Flame Shock missing or inside its refresh window.
            action = "flameshock"
        elseif type(inputs.twist_remaining) == "number" and inputs.twist_remaining <= 0 then
            -- 6. Totem twist due (SKELETON: live inputs are nil outside TBC).
            action = "twist"
        elseif is_off_cooldown(inputs.stormstrike_remaining)
            and should_delay_stormstrike(inputs) then
            -- 7. Stormstrike ready but the Windfury ICD clears within this swing:
            -- hold it rather than waste the empowered proc chance.
            hold = true
            hold_text = "WAIT"
        elseif is_off_cooldown(inputs.stormstrike_remaining) then
            -- 8. Stormstrike is ready.
            action = "stormstrike"
        elseif type(inputs.magma_remaining) == "number"
            and inputs.magma_remaining <= magma_refresh then
            -- 9. Magma Totem due for (re-)drop (Wrath #7).
            action = "magma"
        elseif is_off_cooldown(inputs.firenova_remaining) then
            -- 10. Fire Nova ready while Stormstrike is down.
            action = "firenova"
        elseif type(inputs.lavalash_remaining) == "number"
            and inputs.lavalash_remaining <= 0 then
            -- 11. Lava Lash ready (Wrath #11 last resort).
            action = "lavalash"
        else
            -- 12. The shock filler.
            action = "earthshock"
        end
    end

    out.action = action
    out.hold = hold
    out.hold_text = hold_text
    out.filler_slot = nil
    out.judge_slot = nil
    out.rotation_key = nil
    out.waiting_judgement = false
    return out
end
