--=========================================================================================
-- Shaman next-action guide: pure decision engine, no WoW API and no clock.
--
-- The fourth provider for the frozen ST.<CLASS>.guide contract (nextaction_ui.lua's
-- header; the paladin ships the first, the warrior the second, the druid the third).
-- The live reads live in classes/shaman.lua (ST.SHAMAN.gather_guide_inputs); this
-- module only consumes the gathered inputs, so it is unit-tested offline by
-- tests/shaman_guide_state.lua.
--
-- FROZEN SPEC - display slots (ST.SHAMAN.guide.slots, ordered, eighteen):
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
--                                          known-gated, nil while unknown; SoD feeds
--                                          by name, see below)
--   fireele      Fire Elemental    2894   (swipe: the client-reported cooldown;
--                                          known-gated, nil while unknown - id
--                                          UNCONFIRMED, needs in-game confirmation)
--   magma        Magma Totem       8190   (swipe: the fire-slot totem window;
--                                          WRATH/TBC-fed only, nil elsewhere - id
--                                          UNCONFIRMED, needs in-game confirmation)
--   lavalash     Lava Lash         60103  (no swipe: cooldown unknown, the client
--                                          length rides while one runs; known-gated,
--                                          nil while unknown - id UNCONFIRMED, needs
--                                          in-game confirmation; SoD feeds by name)
--   shamanisticrage Shamanistic Rage 30823 (no swipe: the client length rides while
--                                          one runs; known-gated, nil while unknown;
--                                          SoD feeds by name)
--   chainlightning Chain Lightning 10605 (no swipe: SKELETON, the enemy-count sensor
--                                          does not exist, so no producer feeds
--                                          target_count and this never fires)
--   moltenblast  Molten Blast      425339 (no swipe: the SoD rune has no cooldown to
--                                          ride; known-gated, nil while unknown - id
--                                          UNCONFIRMED, needs in-game confirmation;
--                                          SoD feeds by name)
--   wftotem      Windfury Totem    10614  (no swipe: persistent totem, no window
--                                          to ride; Era-base slot-presence feed,
--                                          nil while unknown/up - id UNCONFIRMED,
--                                          needs in-game confirmation)
--   goa          Grace of Air Totem 10627 (no swipe: the fallback air totem, due
--                                          only on an empty slot while Windfury
--                                          is unknown; same known gate - id
--                                          UNCONFIRMED, needs in-game
--                                          confirmation)
--   lightningshield Lightning Shield 49281 (no swipe: a shield BUFF with charges,
--                                          not a cooldown - the maintain rides the
--                                          player's own aura (the charge row's
--                                          walk), not a timer; WRATH/FOREVER-fed
--                                          and the SoD build on the ERA token,
--                                          nil elsewhere - id UNCONFIRMED, needs
--                                          in-game confirmation; the icon resolves
--                                          by name)
--   searing      Searing Totem     10438  (no swipe: a persistent totem has no
--                                          window to ride; the due-or-nil feed
--                                          lights the slot; ERA-fed only (Era-base
--                                          and SoD), nil elsewhere - id
--                                          UNCONFIRMED, needs in-game confirmation)
--   coe          Call of the Elements 66842 (no swipe: the totem-multi-cast drop
--                                          is a maintain, not a cooldown to ride;
--                                          the due flag lights the slot;
--                                          WRATH-fed only - the id is
--                                          CLIENT-SOURCED (the shipped clients'
--                                          own Constants.lua totem-multi-cast
--                                          list))
--   bloodlust    Bloodlust        2825  (no swipe: the party cooldown's own
--                                          client length rides while one runs;
--                                          known-gated, nil while unknown;
--                                          WRATH-fed only - the Wrath
--                                          enhancement APL's i=1/i=2 row)
--   strength_of_earth Strength of Earth Totem 10442 (no swipe: a persistent
--                                          totem has no window to ride - the
--                                          due-or-nil feed lights the slot;
--                                          ERA/TBC/FOREVER-fed; the shipped id
--                                          is the Era rank-4 id and the icon
--                                          resolves by name)
--   mana_spring  Mana Spring Totem 25570 (no swipe: a persistent totem; the
--                                          due-or-nil feed lights the slot;
--                                          TBC-fed only - the TBC APL's Totems
--                                          group row 4)
--   frostshock   Frost Shock      25464 (no swipe: the shock's own client
--                                          cooldown rides; TBC-fed only - the
--                                          TBC APL's Shocks group row 2, the
--                                          alternative "Filler Shock" choice)
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
--   weave_sub5_ready                        SoD ANY-stack weave fit (G1) + Wrath
--                                           sub-5 fit (M1): true only when the
--                                           gather has verified a sub-5
--                                           Lightning Bolt / Lava Burst hardcast
--                                           fits the live swing on a WF-imbue
--                                           build (SoD: ERA + observed MW, ANY
--                                           stacks incl 0-1, WF imbue up,
--                                           catalogue resolves, swing known,
--                                           cast + latency + 0.10 s fits;
--                                           Wrath: MW 3-4, LB 49238 known,
--                                           swing known, cast + latency +
--                                           0.30 s fits); false = known-not-fit,
--                                           nil = unknown (wrong family, no MW,
--                                           no entry, no swing, casting - never
--                                           prompts, old behaviour)
--   weave_sub5_cast_seconds                 effective sub-5 cast seconds at the live
--                                           MW stacks (observability; the engine
--                                           consumes ready, not this); nil = unknown
--   weave_sub5_is_lavaburst                 true = the fit spell is Lava Burst
--                                           (SoD rune known, slot shows LvB);
--                                           false = Lightning Bolt; nil = unknown
--                                           (never prompts - both sub-5 rules
--                                           require a boolean)
--   flameshock_remaining                    target Flame Shock seconds from the
--                                           tracker; nil = the target does not carry it
--   flameshock_refresh                      db threshold, default 3
--   flameshock_allowed                       Era-base veto: false suppresses the
--                                           maintain where the sims never cast Flame
--                                           Shock (Era without the SoD rune); nil
--                                           reads as allowed so older callers keep
--                                           the old behaviour
--   fight_elapsed                            seconds since combat start (the gather's
--                                           fight stamp; nil = unknown - no stamp yet,
--                                           out of combat). Rule 6 (SoD/TBC Flame Shock
--                                           opener) withholds while under 12 s; unknown
--                                           prompts as before - never a withheld opener
--                                           on a guess. Every other rule ignores it.
--   stormstrike_remaining                   client cooldown after the gather's GCD-echo
--                                           filter; nil/<= 0 = off cooldown
--   stormstrike_hold_enabled                opt-in for the Windfury-fishing hold
--                                           (rule 8); nil/false presses Stormstrike
--                                           on cooldown (every sim does - the default)
--   windfury_icd_remaining                  Windfury ICD seconds from the last swing,
--                                           while the imbue is up (1.5 s window on
--                                           ERA, 3 s elsewhere); nil = unknown (the
--                                           engine never holds on a guess)
--   firenova_remaining                      client Fire Nova cooldown after the
--                                           gather's GCD-echo filter; nil/<= 0 = ready
--   fireele_active                          a live Fire Elemental holds the fire
--                                           slot (SUCCEEDED stamp inside its uptime
--                                           window, confirmed against the slot clock);
--                                           true suppresses Fire Nova (the TBC sim
--                                           never replaces it); nil reads as absent
--   twist_remaining                         totem-twist seconds from the twist model;
--                                           nil = unknown (SKELETON: always nil live
--                                           outside TBC)
--   twist_mana_threshold                    twist mana-pause gate (TBC 0.10);
--                                           nil = no pause (the old behaviour);
--                                           a gated threshold never pauses on
--                                           unknown mana
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
--   sr_remaining                            Shamanistic Rage cooldown after the
--                                           GCD-echo filter AND known/name gate;
--                                           nil = unknown (never prompts)
--   sr_mana_threshold                       family mana gate (TBC 0.10, SoD 0.65);
--                                           nil falls back to the TBC/ERA family
--                                           default below (Wrath and unknown
--                                           families prompt on cooldown)
--   mana_fraction                           player mana 0..1; nil = unknown (a gated
--                                           threshold never prompts on a guess; the
--                                           ungated paths read old behaviour)
--   shock_remaining                         shared shock cooldown after the GCD-echo
--                                           filter; nil/<= 0 = ready
--   target_count                            enemy count for the multi-target rule;
--                                           nil = unknown (the sensor does not
--                                           exist - no client API counts enemies,
--                                           so no producer ever feeds it and the
--                                           rule stays dead)
--   moltenblast_remaining                   Molten Blast readiness (SoD name/known
--                                           gate); nil = unknown (never prompts)
--   wftotem_remaining                         Era Windfury Totem maintain (G2):
--                                           0 = due (Era-base air slot
--                                           affirmatively empty, or holding Grace
--                                           of Air while Windfury is known - the
--                                           sim's priority); nil = up, unknown,
--                                           or any other family (never prompts)
--   goatotem_remaining                        Era Grace of Air fallback (G2):
--                                           0 = due (Era-base air slot
--                                           affirmatively empty while Windfury is
--                                           unknown - never overwrites a known
--                                           Windfury); nil = up, unknown, or any
--                                           other family (never prompts)
--   clearcasting_active                     Elemental Focus proc up (Forever
--                                           Clearcasting -> Fire Nova); nil reads as
--                                           down
--   searing_down                            the fire slot affirmatively holds NO
--                                           Searing Totem (the gather's fire-slot
--                                           reader): true = the maintain is due,
--                                           false = the slot holds Searing or another
--                                           totem, nil = unknown (never prompts)
--   mw_observed                             the SoD MW-rune latch (the ERA token's
--                                           SoD build): true = the rune was observed,
--                                           nil/false = Era-base. It picks the
--                                           Searing fight-age gate (Era 20 s, SoD
--                                           30 s) on the shared ERA family token.
--   lightningshield_due                     the Lightning Shield maintain
--                                           (WRATH, FOREVER and the SoD build
--                                           on the ERA token):
--                                           true = no shield aura is up on the
--                                           player (the cast is needed), false = a
--                                           Lightning or Water Shield aura is up
--                                           (nothing to do - a Water Shield build
--                                           never sees the prompt), nil = unknown
--                                           (the aura walk has not run, or the
--                                           client may hide auras - never prompts)
--   water_remaining                         the water-totem clock (S-20 / U-10):
--                                           the seconds left on the water totem
--                                           (the client's own slot 3); 0 = the
--                                           slot is affirmatively empty (the CoE
--                                           drop is due), nil = unknown (an
--                                           unreadable slot - never prompts)
--   water_duration                          the water totem's full length when the
--                                           client reports one; nil = unknown (the
--                                           pair's duration half)
--   strength_of_earth_remaining             the EARTH totem slot clock (the
--                                           Strength of Earth Totem upkeep):
--                                           0 = the slot is affirmatively empty
--                                           (the drop is due), the seconds left
--                                           while a totem is up, nil = unknown
--                                           (an unreadable slot - never prompts)
--   mana_spring_remaining                   the WATER totem slot clock (the
--                                           Mana Spring Totem upkeep on TBC, where
--                                           the water slot carries Mana Spring):
--                                           the same tri-state as the earth clock
--   bloodlust_remaining                     Bloodlust cooldown after the gather's
--                                           GCD-echo filter AND known gate;
--                                           nil = unknown (never prompts)
--   frostshock_remaining                    Frost Shock cooldown after the
--                                           gather's GCD-echo filter AND known
--                                           gate; nil = unknown (never prompts)
--   filler_shock                            the TBC APL's "Filler Shock" choice:
--                                           "FROST" when the player runs Frost
--                                           Shock as the shock filler (the
--                                           class feeds it from the player's own
--                                           guide_filler_shock option), nil (or
--                                           anything else) = the APL's DEFAULT
--                                           (Earth Shock - the valueVariables
--                                           entry). The default stands until the
--                                           player picks Frost Shock
--
-- FROZEN SPEC - rule order (first match wins; exactly these rules):
-- FROZEN SPEC - rule order (first match wins; exactly these rules):
--   1. casting -> no action, hold = true, hold_text = "RIDE" (never weave or press
--      anything mid-cast).
--   2. fireele_remaining a number <= 0 -> action "fireele" (Wrath #1; the known
--      gate feeds nil while the spell is unknown, so this never fires on a guess).
--   3. feralspirit_remaining a number <= 0 -> action "feralspirit" (Wrath #2,
--      SoD #1; same known gate, plus the SoD name feed).
--   3b. family == "WRATH" AND bloodlust_remaining a number <= 0 -> action
--      "bloodlust" (the Wrath enhancement APL's i=1/i=2 row: 2825, the party
--      haste cooldown, cast on cooldown the way every other cooldown row is;
--      the known gate feeds nil while the spell is unknown, so a client
--      without it never sees the prompt).
--   4. sr_remaining a number <= 0 AND (sr_mana_threshold nil OR mana_fraction
--      known and <= threshold) -> action "shamanisticrage" (SoD #3 at mana
--      <= 65%, TBC top-group at mana < 10%, Wrath #5 on cooldown with no mana
--      gate). A nil threshold falls back to the TBC/ERA family default (Wrath
--      stays ungated); a gated threshold never prompts on unknown mana (no
--      prompt on a guess); nil sr_remaining never prompts.
--   5. mw_available and mw_stacks >= 5 -> action "weave" (the broadcast instant; the
--      rule does not require weave_available - the slot's fallback icon covers an
--      unresolved catalogue). On Era-base/TBC mw_available is false, so no weave is
--      ever prompted where Maelstrom Weapon cannot exist. MW5-ONLY for the instant:
--      the sub-5 hardcast lives in rules 5b (LvB) and 12b (LB) below, both
--      fit-verified (G1) - a sub-5 hardcast that clips the swing is a DPS loss.
--   5b. weave_sub5_ready == true AND weave_sub5_is_lavaburst == true ->
--      action "weave" (SoD LvB ANY-stack fit, G1 HIGH: the SoD sim weaves Lava
--      Burst at ANY stacks when the cast fits, above Stormstrike; the gather
--      verifies the fit on a WF-imbue SoD build with ANY stacks incl 0-1, so
--      5 stacks stay on rule 5. Strict booleans:
--      nil/false ready never prompts, nil is_lavaburst never prompts -
--      older callers keep the MW5-only behaviour).
--   5c. weave_sub5_ready == true AND weave_sub5_is_lavaburst == false AND
--      family == "WRATH" -> action "weave" (Wrath LB sub-5 fit, M1 HIGH: the
--      default_wf sim weaves Lightning Bolt at MW >= 3 when 300 ms + cast
--      fits, between MW5 and Stormstrike; the gather verifies the fit on a
--      WF-imbue Wrath build, so 5 stacks stay on rule 5 and the FT builds
--      stay MW5-only. Same strict-boolean gate as rule 5b).
--   6. flameshock_allowed ~= false AND (flameshock_remaining nil or
--      <= flameshock_refresh) AND NOT a young fight on SoD/TBC ->
--      action "flameshock". A remaining of exactly the threshold refreshes; nil
--      always refreshes. Era-base vetoes the maintain (allowed == false): the Era
--      sim never casts Flame Shock, so the rule falls through there; SoD keeps
--      it (allowed when the MW rune is observed). OPENER GATE (audit 2026-10-19
--      SoD P6 + TBC default APL: FS only once the fight is older than 12 s, so
--      the opener spends the early GCDs on Feral/SR/SS/twist instead): on SoD
--      (ERA with allowed) and on TBC, a fight_elapsed under 12 s falls through;
--      unknown age (nil/NaN, out of combat) prompts as before - never a withheld
--      opener on a guess. Wrath, Forever and every other family ignore the gate
--      (Wrath phase_3 gates on fight-REMAINING, a different input that does not
--      exist here - filed M5; the Forever sim has no fight gate).
--   7. twist_remaining a number <= 0 AND NOT mana-paused -> action "twist"
--      (SKELETON: scripted inputs only outside TBC; live inputs are nil there - Wrath has no twisting, and
--      Forever never twists: party-buff totem model, totems coexist with imbues).
--      TBC CADENCE (docs/research/tbc_minmax.md, [uncertain]): 9 s WF pulse on a
--      ~10 s alternation cycle (~83% GoA uptime); each twist eats a 3 s GCD (~20%
--      shock / ~10% Stormstrike damage), so the counter - not eagerness - drives
--      the drop. WF rank 1 downranked for mana. MANA PAUSE (audit 2026-10-19
--      TBC §): the sim pauses the alternation at mana <= 10% instead of
--      downranking - a numeric twist_mana_threshold with mana at or below it
--      suppresses the prompt (nil threshold = no pause, unknown mana never
--      pauses); the live feed is filed, so this stays dormant until fed.
--   8. stormstrike_hold_enabled == true AND stormstrike off cooldown BUT the
--      Windfury ICD expires within this swing
--      (0 < windfury_icd_remaining <= swing_remaining) -> no action, hold = true,
--      hold_text = "WAIT" (delay-if-fishing-WF: let the ICD clear so the
--      Stormstrike-empowered swing can proc Windfury). OPT-IN ONLY: every sim
--      casts Stormstrike on cooldown, so the default (nil/false) presses it -
--      the hold only arms behind the wf-hold-tint opt-in. TBC MICRO
--      (docs/research/tbc_minmax.md): the 3 s ICD (1.5 s on ERA) caps output at
--      20 procs/min shared across hands (totem has no ICD); double WF wants the
--      slowest weapons in both hands (documented, not modelled - no weapon-speed
--      input). GCD-agnostic: the tick
--      re-evaluates, so a running GCD just re-holds or moves on.
--   8a. the Strength of Earth Totem upkeep is due (see
--      get_strength_of_earth_due) -> action "strength_of_earth" (the APL
--      UTILITY layer, bench/rotation_gap_vs_apl_2026-10-20.md §5): the Era
--      enhancement APL's i=0 row (10442 r4, cast when the aura is NOT active),
--      the TBC APL's Totems group row 3 (25528, refreshed at 5 s left) and
--      the Forever APL's i=4 row (25361, the earth slot empty). The read is
--      the client's EARTH totem slot clock - the same wrapper the water clock
--      uses - so an unreadable slot never prompts (unknown-hides). ERA-BASE
--      only on the ERA token: the SoD build runs no SoE rotation row (its
--      SoE is a PRE-PULL row), so the MW latch keeps it silent there. The
--      chain places the upkeep with the other totem upkeeps (the twist is
--      above it), the same slot the TBC APL's Totems group owns - the APL
--      ranks that whole group BELOW Stormstrike (i=3 against i=1), a
--      documented divergence of the frozen chain, not of this rule.
--   8b. wftotem_remaining a number <= 0 -> action "wftotem" (Era Windfury
--      Totem maintain, G2: the sim refreshes Windfury first, above
--      Stormstrike; the feed is Era-base slot-presence only - a due feed on
--      any other family never happens, so the old chains run byte-identical).
--   8c. goatotem_remaining a number <= 0 -> action "goa" (Era Grace of Air
--      fallback, G2: due only while Windfury is unknown, so it can never
--      overwrite a known Windfury and thrash the shared air slot).
--   8d. family == "TBC" AND the Mana Spring Totem upkeep is due (the water
--      slot clock at or under 5 s) -> action "mana_spring" (the TBC APL's
--      Totems group row 4: 25570, refreshed at 5 s left - the same refresh
--      window as the Strength of Earth row above it and the same air-slot
--      group's order). TBC-only: the SoD and Forever Mana Spring rows are
--      PRE-PULL rows (HU-12), not rotation rows.
--   9. stormstrike_remaining nil or <= 0 -> action "stormstrike" ("off cooldown").
--   9b. searing_down == true AND the fight is older than the family's Searing gate
--      (Era 20 s, SoD 30 s) -> action "searing" (the Searing Totem maintain, S-17:
--      the classic default APL keeps Searing down once the fight is older than
--      20 s, the SoD phase_6 APL past 30 s; the fire-slot reader feeds due and the
--      fight clock feeds the age). The TBC sim uses Searing as the low-mana
--      fire-totem fallback and quotes no threshold, the Wrath APL ranks Magma
--      instead and the Forever static-totem maintain is filed - so only the ERA
--      token (Era-base and SoD) ever fires this rule; no number is invented).
--   9c. family == "WRATH" AND water_remaining a number under
--      COE_WATER_REFRESH_SECONDS (20) -> action "coe" (the Call of the Elements,
--      S-20 / U-10: all three wowsims/wotlk enhancement APLs rank CoE 66842
--      between Earth Shock 49231 and Magma Totem 58734, gated on the water totem
--      being under 20 s - default_wf.apl.json [9], default_ft.apl.json [9],
--      phase_3.apl.json [8]). The chain places it exactly there: below
--      Stormstrike (9) and the Searing maintain (9b), above Magma (10). WRATH-
--      only - the Era/TBC/Forever sims run no CoE line, and an unknown water read
--      (nil) never prompts (unknown-hides). The engine's Earth Shock sits at the
--      BOTTOM of this chain (14/17 - it is the shock-capped filler, a frozen
--      TBC-parity order), so the APL's "Earth Shock above CoE" relation cannot
--      be honoured without moving Earth Shock itself - a documented divergence of
--      the frozen chain, not of this rule.
--   10. magma_remaining a number <= magma_refresh -> action "magma" (fire-totem
--      maintain; WRATH/TBC-fed, nil elsewhere - never prompts on a guess).
--   11. firenova_remaining nil or <= 0 AND family is neither ERA nor FOREVER AND
--      fireele_active ~= true -> action "firenova" (Fire Nova on cooldown). The
--      Era sim runs no Fire Nova (Searing holds the fire slot); the Forever sim
--      ranks it below Earth Shock (rule 16); a live Fire Elemental is never
--      replaced (the TBC sim suppresses Nova while it is out).
--   11b. lightningshield_due == true -> action "lightningshield" (the Wrath
--      Lightning Shield maintain, S-19: all three wowsims/wotlk enhancement APLs
--      maintain it iff inactive, above Lava Lash and below Fire Nova - the slot
--      order the rotation table records; the SoD phase_6 APL's i=8 row and the
--      Forever APL's i=6 row cast 10432 the same way. The family gate is
--      get_lightningshield_family_gate: WRATH, FOREVER and the SoD build on the
--      ERA token (the MW-rune latch); the Era-base and TBC sims run no Lightning
--      Shield row, so they never see the prompt).
--   12. lavalash_remaining a number <= 0 -> action "lavalash" (Wrath #11 last
--      resort; the known gate feeds nil while the spell is unknown, plus the SoD
--      name feed).
--   12b. weave_sub5_ready == true AND weave_sub5_is_lavaburst == false ->
--      action "weave" (SoD LB ANY-stack fit, G1 LOW: the SoD sim weaves
--      Lightning Bolt at ANY stacks when the cast fits, below Lava Lash and
--      above the multi-target Chain Lightning; same strict-boolean gate as
--      rule 5b - nil/false ready never prompts, nil is_lavaburst never
--      prompts. Unreachable on Wrath: rule 5c catches the same feed first,
--      so the Wrath high rank always wins there. The FS-above ordering is
--      the pre-existing FS-high divergence, not G1 scope).
--   13. mw_available and mw_stacks >= MW_CL_MIN_STACKS (4) and target_count >=
--      CL_MIN_TARGETS (2) -> action "chainlightning" (SoD multi-target: MW >= 4
--      with 2+ targets). SKELETON, and the row claims NO arm: the enemy-count
--      sensor does not exist (no client API counts enemies - the clients'
--      FrameXML carries no Chain Lightning reference on any branch), so no
--      in-tree producer ever feeds target_count and this branch is unreachable.
--      The cut (accept a non-client count source, or drop the rule) is the
--      operator's O-4 decision - bench/filed_closure_sweep_2026-10-19.md §10.
--   13b. family == "TBC" AND filler_shock == "FROST" AND frostshock_remaining a
--      number <= 0 -> action "frostshock" (the TBC APL's Shocks group row 2:
--      25464 r5, the ALTERNATIVE "Filler Shock" choice - the group's row 3
--      (25454 r8, Earth Shock) is the valueVariables DEFAULT, so this arm
--      only fires when the player states the Frost Shock choice (the live
--      gather never does, so the default stands). The two rows are mutually
--      exclusive: with the Frost Shock choice stated, rules 14 and 17 stay
--      silent and the Earth Shock filler never answers).
--   14. shock_remaining nil or <= 0 AND the Earth Shock fallback is permitted
--      (rule 17) AND the TBC filler shock is NOT Frost Shock -> action
--      "earthshock" (the shock-capped filler: ES only answers
--      while the shared shock cooldown is actually ready, so the SoD Molten Blast
--      filler below alternates on the shock global the way the sim does).
--   15. moltenblast_remaining a number <= 0 -> action "moltenblast" (SoD filler
--      below Earth Shock; the name/known gate feeds nil while unknown).
--   16. family == "FOREVER" AND firenova_remaining nil or <= 0 AND
--      (clearcasting_active == true OR mana_fraction known and > 0.10) ->
--      action "firenova" (Forever free/mana-dump Nova, ranked below Earth Shock
--      the way the sim ranks it; nil mana never dumps on a guess).
--   17. otherwise -> action "earthshock" when permitted, else no action (the
--      shock filler; permitted everywhere except Era-base at mana < 50% - the Era
--      sim only casts ES at mana >= 50%, so the guide stays silent there instead
--      of prompting a filler the sim never casts).
--
--   Wrath order notes (docs/research/rotations_wrath.md deviations, all TBC-parity
--   forced): Earth Shock ranks #9 above Fire Nova #10 in the research, but the
--   frozen TBC chain prompts Nova above the filler - reordering would change TBC
--   behaviour, so Nova stays above Earth Shock. Lava Lash (#12) sits above the
--   shock-capped Earth Shock rule so the gated slot can fire at all; Shamanistic
--   Rage (#4) prompts on cooldown with no mana gate (Wrath has no sim-backed
--   threshold). Lightning Shield (#8 in the research) now has a slot (rule 11b,
--   below Fire Nova and above Lava Lash - the slot order the rotation table
--   records); the Shield CHOICE (Water Shield vs Lightning Shield is a Wrath
--   spec option, audit S-29) is still deferred, so the maintain only fires
--   while NO shield aura is up at all.
--   SoD notes (docs/research/rotations_sod.md): the MW latch already enables rules
--   5/10-class behaviour on SoD (ERA + observed); the 5-stack spender choice (Lava
--   Burst under the Stormstrike debuff when the rune is known, else Lightning Bolt)
--   is surfaced by re-pointing the weave slot at Lava Burst in resolve_guide_icons -
--   the engine keeps prompting "weave". FS/ES already alternate (rules 6 and 14),
--   which spends Rolling Thunder; the Stormstrike-debuff read for the spender is
--   deferred (needs a target-debuff tracker plus in-game confirmation). Feral
--   Spirit / Lava Lash / Molten Blast feed by name on SoD (the Wrath ids never
--   resolve there); Shamanistic Rage gates at mana <= 65%. G1 (SoD ANY-stack
--   weave): rules 5b (LvB fit, high - above Stormstrike) + 12b (LB fit, low -
--   below Lava Lash) prompt "weave" when the gather verifies the sub-5 cast
--   fits the swing on a WF-imbue SoD build at ANY stacks incl 0-1; 5 stacks
--   stay on rule 5, TBC/Forever/Era-base stay nil (never prompt).
--   M1 (Wrath sub-5, bench/wrath_leftovers_2026-10-19.md §S3): rule 5c (LB
--   fit, high - between MW5 and Flame Shock) prompts "weave" when the gather
--   verifies the MW>=3 LB 49238 hardcast fits the swing on a WF-imbue Wrath
--   build (300 ms buffer); the FT builds stay MW5-only (rule 5 covers them).
--   G2 (Era static totems, audit 2026-10-19 Era §): rules 8b (WF) + 8c (GoA)
--   prompt "wftotem"/"goa" when the Era-base air slot is affirmatively empty
--   (8b also when it must take the slot back from GoA while Windfury is
--   known - the sim's priority; 8c only while Windfury is unknown, so the
--   shared slot never thrashes). Both sit between the fishing hold and
--   Stormstrike the way the sim ranks them (WF > GoA > SS); a third air totem
--   (Nature Resistance and friends) is unmodeled and left alone, and the
--   sim's buff-keyed WF refresh (imbue 10611 <= 1.5 s) needs a buff-expiry
--   read that does not exist - filed remainder (F2 class) - so the feed is
--   slot-presence only. Era-base only: SoD/TBC/Wrath/Forever feeds stay nil
--   (never prompt), and the HUD mirror is deferred (guide-only, the same
--   13-vs-8 precedent as the Wrath additions).
--   S-17 (Searing Totem maintain): rule 9b prompts "searing" on the ERA token
--   (Era-base and SoD) once the fight is older than the family's gate (20 s /
--   30 s) and the fire slot affirmatively holds no Searing. The TBC low-mana
--   fallback (S-25) quotes no threshold and the Forever static-totem maintain
--   (S-27) has unconfirmed ids, so no other family fires it - no number is
--   invented. The due feed is the fire-slot reader + the fight clock, both of
--   which already ship.
--   S-20 (Call of the Elements 66842) is LIVE: rule 9c prompts it on WRATH when
--   the water totem is under 20 s (the three wowsims/wotlk enhancement APLs
--   rank it between Earth Shock and Magma Totem), and the gather feeds the
--   water clock from the client's own slot 3 (CLIENT-SOURCED - the shipped
--   clients' own Constants.lua carries both the slot map and the id 66842 in
--   its totem-multi-cast list). The rule's rank is no longer provisional: it
--   is the APL's own order. An unreadable water slot feeds nil, so the rule
--   never prompts on a guess.
--   Frost Shock is the TBC APL's ALTERNATIVE shock filler, not a rotation row of
--   its own: the Shocks group picks ONE filler (the "Filler Shock" variable,
--   Earth Shock by default), so the engine answers "frostshock" only when the
--   player states that choice (rule 13b) and keeps the Earth Shock filler
--   silent in that case (rules 14 and 17). On every other family the spell has
--   no line: the WotLK and SoD shock rows are Flame Shock and Earth Shock.
--   Chain Lightning multi-target (MW >= 4 with 2+ targets, rule 13) needs an
--   enemy-count input no client API supplies - the rule is live but the gather
--   feeds nil, so it stays dead until the sensor lands (pinned by test).
--
--   Retail (12.x) inertness: st.family == "RETAIL" short-circuits evaluate to the
--   empty display shape before any rule below. The inert stand-in never reports a
--   swing, but the cast flag (rule 1), the absent-debuff default (rule 6, where nil
--   always refreshes) and the idle-cooldown defaults (rules 9 and 11, where nil
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
--     extend the fifteen-slot contract (deferred).
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
-- Flame Shock opener gate (audit 2026-10-19: SoD P6 requires fight > 12 s, TBC
-- default requires fight >= 12 s): withhold while under 12 s; exactly 12 prompts
-- (the TBC edge - a SoD frame landing exactly on 12.0 is unhittable either way).
st.shaman_guide.FS_FIGHT_GATE_SECONDS = 12
-- Family mana gates for the Shamanistic Rage rule (audit 2026-10-19): TBC prompts
-- below 10% (configurable 5/10/20/30 in the sim - 10% is the sim default), SoD at
-- or below 65%. Wrath prompts on cooldown (no sim-backed threshold, nil).
st.shaman_guide.SR_MANA_THRESHOLD_TBC = 0.10
st.shaman_guide.SR_MANA_THRESHOLD_SOD = 0.65
-- Era mana floor for the Earth Shock filler (audit 2026-10-19 Era §): the Era sim
-- only casts ES at mana >= 50%.
st.shaman_guide.ES_MANA_FLOOR_ERA = 0.5
-- Forever mana-dump floor for Fire Nova (audit 2026-10-19 Forever §: the sim ranks
-- FN below ES and only dumps it above 10% mana, or free on Clearcasting).
st.shaman_guide.FN_MANA_FLOOR_FOREVER = 0.10
-- Chain Lightning multi-target gate (audit 2026-10-19 §4: SoD sim, MW >= 4 with
-- 2+ targets).
st.shaman_guide.MW_CL_MIN_STACKS = 4
st.shaman_guide.CL_MIN_TARGETS = 2
-- SoD ANY-stack weave fit (G1, audit 2026-10-19 SoD § + live-gate G1): the sim
-- weaves LB/LvB at ANY stacks when the cast fits (autoTimeToNext >= cast +
-- 100 ms), including the 0-1 hardcast filler - the guide floor is 0 and the
-- fit gate still withholds whatever clips. 5 stacks stay on rule 5. The
-- buffer below is the sim's 100 ms; the gather reads it with a 0.10
-- fallback so older callers keep the exact old behaviour. (The assist bar
-- still gates at 2+ stacks, weave.lua MW_MIN_WEAVE_STACKS - weave.lua is out
-- of scope here, so the bar stays dim at 0-1 while the guide prompts. Filed
-- remainder for a future weave-lane alignment.)
st.shaman_guide.WEAVE_SUB5_MIN_STACKS = 0
st.shaman_guide.WEAVE_SUB5_FIT_BUFFER_SECONDS = 0.10
-- Wrath sub-5 hardcast (M1, bench/wrath_leftovers_2026-10-19.md §S3): the
-- default_wf APL hardcasts LB 49238 at MW >= 3 when 300 ms + cast fits the
-- swing; the FT builds are MW5-only (rule 5 covers them). LvB is
-- Elemental-only on Wrath, so the fit spell is always Lightning Bolt (the
-- gather feeds is_lavaburst false there). WF-imbue builds only, same gate as
-- SoD; 5 stacks stay on rule 5.
st.shaman_guide.WEAVE_SUB5_MIN_STACKS_WRATH = 3
st.shaman_guide.WEAVE_SUB5_FIT_BUFFER_WRATH_SECONDS = 0.30
-- The Searing Totem maintain gates (audit 2026-10-19 §2.6 S-17): the classic default
-- APL keeps Searing down once the fight is older than 20 s, the SoD phase_6 APL past
-- 30 s. Both live in the engine (rule 9b) and in the practice drill (D-S4), so the
-- gate has exactly one source.
st.shaman_guide.SEARING_UPKEEP_FIGHT_GATE_ERA = 20
st.shaman_guide.SEARING_UPKEEP_FIGHT_GATE_SOD = 30
-- The Call of the Elements' due window (S-20 / U-10). SIM-CONFIRMED: all three
-- wowsims/wotlk enhancement APLs gate the CoE drop on the WATER totem being
-- under 20 s - the condition is
--   {"cmp":{"op":"OpLt","lhs":{"totemRemainingTime":{"totemType":"Water"}},
--           "rhs":{"const":{"val":"20s"}}}}
-- (default_wf.apl.json [9], default_ft.apl.json [9], phase_3.apl.json [8] - each
-- between the Earth Shock 49231 line and the Magma Totem 58734 line). The rule
-- sits in the same place in this chain: below Stormstrike and the Searing
-- maintain, above Magma.
st.shaman_guide.COE_WATER_REFRESH_SECONDS = 20
-- The APL UTILITY layer's refresh windows (bench/rotation_gap_vs_apl_2026-10-20.md
-- §5). The Strength of Earth Totem upkeep reads the client's EARTH totem slot
-- clock; the threshold is the APL's own condition per family:
--   ERA     ui/enhancement_shaman/apls/default.apl.json i=0 - "not auraIsActive
--           (10442 r4)" - cast only when the buff is DOWN, so the window is 0 s
--           (the slot clock answers 0 exactly when the slot is empty).
--   TBC     ui/specs/shaman/enhancement/apls/default.apl.json i=3 group Totems
--           row 3 - "auraRemainingTime(25528) <= 5s" - the refresh window.
--   FOREVER ui/specs/shaman/enhancement/apls/default.apl.json i=4 -
--           "totemRemainingTime(Earth) <= 0s" - the empty-slot window (0 s).
st.shaman_guide.SOE_REFRESH_TBC = 5
st.shaman_guide.SOE_REFRESH_DEFAULT = 0
-- The Mana Spring Totem upkeep (TBC only): the same Totems group, row 4 -
-- "auraRemainingTime(25570) <= 5s" - the same refresh window as the Strength
-- of Earth row above it.
st.shaman_guide.MANA_SPRING_REFRESH_TBC = 5
-- The TBC APL's "Filler Shock" variable (valueVariables: "Filler Shock" =
-- const "Earth Shock"): the ALTERNATIVE choice, Frost Shock (the Shocks group
-- row 2, 25464 r5). The class feeds the choice from the player's own option
-- (the shaman's guide_filler_shock key - classes/shaman.lua's gather), so the
-- default below is what a fresh profile reads: the APL's Earth Shock.
st.shaman_guide.FILLER_SHOCK_EARTH = "EARTH"
st.shaman_guide.FILLER_SHOCK_FROST = "FROST"

-- Pure: is the Searing Totem due? Only on the families whose sims keep it down and
-- only past the fight-age gate. The TBC sim uses Searing as the low-mana fire-totem
-- fallback and the audit quotes no threshold for it, the Wrath APL ranks Magma
-- instead, and the Forever static-totem maintain is filed (audit S-25/S-27) - so
-- those families never grade a Searing here (no number is invented).
--   family      the client family token (ERA covers Era-base and SoD)
--   fight_elapsed  seconds since combat start (the gather's fight stamp)
--   searing_down   the fire slot affirmatively holds no Searing (the gather's reader)
--   sod_observed   the MW rune was observed (the SoD latch on the ERA token)
function st.shaman_guide.get_searing_upkeep_due(family, fight_elapsed, searing_down, sod_observed)
    if searing_down ~= true then
        return false
    end
    if type(fight_elapsed) ~= "number" or fight_elapsed ~= fight_elapsed then
        return false
    end
    if family ~= "ERA" then
        return false
    end
    local gate = st.shaman_guide.SEARING_UPKEEP_FIGHT_GATE_ERA
    if sod_observed == true then
        gate = st.shaman_guide.SEARING_UPKEEP_FIGHT_GATE_SOD
    end
    return fight_elapsed > gate
end

-- Pure: is the Strength of Earth Totem upkeep due? The APL's own condition per
-- family (bench/rotation_gap_vs_apl_2026-10-20.md §5):
--   ERA     the Era enhancement APL's i=0 row - cast when the 10442 r4 aura is
--           NOT active, so the window is 0 s (the earth-slot clock answers 0
--           exactly when the slot is affirmatively empty).
--   TBC     the TBC APL's Totems group row 3 - refresh at 5 s left.
--   FOREVER the Forever APL's i=4 row - the earth slot empty (0 s).
-- The read is the client's EARTH totem slot clock (the same wrapper the water
-- clock uses), so an unreadable slot feeds nil and never prompts
-- (unknown-hides). ERA-BASE only on the ERA token: the SoD build runs no
-- Strength of Earth rotation row (its Strength of Earth is a PRE-PULL row),
-- so the MW latch keeps it silent there.
--   family      the client family token
--   remaining   the earth-slot clock (0 = the slot is empty, nil = unknown)
--   mw_observed the SoD MW-rune latch on the ERA token
function st.shaman_guide.get_strength_of_earth_due(family, remaining, mw_observed)
    if type(remaining) ~= "number" then
        return false
    end
    local threshold = st.shaman_guide.SOE_REFRESH_DEFAULT
    if family == "TBC" then
        threshold = st.shaman_guide.SOE_REFRESH_TBC
    elseif family == "ERA" then
        if mw_observed == true then
            return false
        end
    elseif family ~= "FOREVER" then
        return false
    end
    return remaining <= threshold
end

-- Pure: is the Mana Spring Totem upkeep due? TBC only: the TBC APL's Totems
-- group row 4 (25570) refreshes the mana totem at 5 s left, the same window
-- as the Strength of Earth row above it. The read is the client's WATER totem
-- slot clock - on TBC the water slot carries Mana Spring (the SoD and Forever
-- Mana Spring rows are PRE-PULL rows, HU-12). An unreadable slot feeds nil and
-- never prompts.
function st.shaman_guide.get_mana_spring_due(family, remaining)
    if family ~= "TBC" then
        return false
    end
    if type(remaining) ~= "number" then
        return false
    end
    return remaining <= st.shaman_guide.MANA_SPRING_REFRESH_TBC
end

-- Pure: does the Lightning Shield maintain apply on this client? WRATH (the
-- three wowsims/wotlk enhancement APLs maintain it iff inactive, above Lava
-- Lash), FOREVER (the Forever APL's i=6 row: 10432, the same "not auraIsActive"
-- condition) and the SoD build on the ERA token (the SoD phase_6 APL's i=8
-- row: 10432 r7, the same condition - the MW-rune latch separates SoD from
-- Era-base, and the Era-base APL and the TBC APL run no Lightning Shield row
-- at all: wowsims/classic ui/enhancement_shaman/apls/default.apl.json and
-- wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json carry no
-- Lightning Shield spell).
--   family      the client family token
--   mw_observed the SoD MW-rune latch on the ERA token (true = the SoD build)
function st.shaman_guide.get_lightningshield_family_gate(family, mw_observed)
    if family == "WRATH" or family == "FOREVER" then
        return true
    end
    if family == "ERA" and mw_observed == true then
        return true
    end
    return false
end

-- Pure: does the player run Frost Shock as the TBC shock filler? The TBC
-- APL's Shocks group picks ONE filler (the "Filler Shock" valueVariable, Earth
-- Shock by default). Only the explicit Frost Shock choice flips it; the live
-- gather states the choice from the player's own option (the shaman's
-- guide_filler_shock key), and a nil choice reads as the APL's default (Earth
-- Shock).
local function uses_frost_shock_filler(inputs)
    return st.family == "TBC"
        and inputs.filler_shock == st.shaman_guide.FILLER_SHOCK_FROST
end

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

-- Opener gate for rule 6 (SoD P6 + TBC default APL: no Flame Shock in the first
-- 12 s of the fight): true while the fight is provably young on a gated family.
-- SoD rides the ERA token with the maintain allowed (the MW-rune signal); TBC is
-- its own family. Wrath, Forever and every other family (including a nil offline
-- family) never gate. Unknown age (nil/NaN) prompts as before, so every caller
-- that predates the input keeps the exact old behaviour.
local function fs_fight_too_young(inputs)
    local gated = st.family == "TBC"
        or (st.family == "ERA" and inputs.flameshock_allowed == true)
    if not gated then
        return false
    end
    local elapsed = inputs.fight_elapsed
    return type(elapsed) == "number" and elapsed == elapsed
        and elapsed < st.shaman_guide.FS_FIGHT_GATE_SECONDS
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

    -- The Earth Shock fallback permission (rule 17): everywhere except Era-base at
    -- low mana. Era-base vetoes the maintain (flameshock_allowed == false) AND mana
    -- is known below the Era floor: the Era sim only casts ES at mana >= 50%.
    -- Unknown mana reads permitted (no silence on a guess); SoD (allowed) and every
    -- other family are always permitted.
    local es_permitted = st.family ~= "ERA"
        or inputs.flameshock_allowed ~= false
        or type(inputs.mana_fraction) ~= "number"
        or inputs.mana_fraction >= st.shaman_guide.ES_MANA_FLOOR_ERA

    -- Family default for the Shamanistic Rage gate: the gather feeds the
    -- threshold explicitly, but direct engine callers that omit it still get
    -- the sim-exact gate (TBC 10%, ERA/SoD 65%); Wrath and unknown families
    -- keep the old ungated prompt. No live-visible change: the live gather
    -- always feeds an explicit threshold wherever it feeds a cooldown.
    local sr_gate = inputs.sr_mana_threshold
    if sr_gate == nil and st.shaman_guide then
        if st.family == "TBC" then
            sr_gate = st.shaman_guide.SR_MANA_THRESHOLD_TBC
        elseif st.family == "ERA" then
            sr_gate = st.shaman_guide.SR_MANA_THRESHOLD_SOD
        end
    end

    if inputs.casting == true then
        -- 1. A cast is in flight: hold.
        hold = true
        hold_text = "RIDE"
    elseif type(inputs.fireele_remaining) == "number" and inputs.fireele_remaining <= 0 then
        -- 2. Fire Elemental ready (Wrath #1).
        action = "fireele"
    elseif type(inputs.feralspirit_remaining) == "number" and inputs.feralspirit_remaining <= 0 then
        -- 3. Feral Spirit ready (Wrath #2, SoD #1).
        action = "feralspirit"
    elseif st.family == "WRATH" and type(inputs.bloodlust_remaining) == "number"
        and inputs.bloodlust_remaining <= 0 then
        -- 3b. Bloodlust ready (the Wrath enhancement APL's i=1/i=2 row). The
        -- known gate feeds nil while the spell is unknown, so a client without
        -- it never sees the prompt.
        action = "bloodlust"
    elseif type(inputs.sr_remaining) == "number" and inputs.sr_remaining <= 0
        and (sr_gate == nil
            or (type(inputs.mana_fraction) == "number"
                and inputs.mana_fraction <= sr_gate)) then
        -- 4. Shamanistic Rage ready inside its family mana gate (SoD <= 65%,
        -- TBC <= 10% with the family default; Wrath prompts on cooldown). A
        -- gated threshold never prompts on unknown mana; nil sr_remaining
        -- never prompts.
        action = "shamanisticrage"
    elseif mw_ok and type(inputs.mw_stacks) == "number" and inputs.mw_stacks >= 5 then
        -- 5. Five Maelstrom Weapon stacks: the weave is instant (MW5-only).
        action = "weave"
    elseif inputs.weave_sub5_ready == true and inputs.weave_sub5_is_lavaburst == true then
        -- 5b. SoD Lava Burst fit (G1 HIGH): the gather verified the sub-5 cast
        -- fits the live swing on a WF-imbue SoD build. Strict booleans: nil or
        -- false ready never prompts, nil is_lavaburst never prompts - older
        -- callers keep the MW5-only behaviour.
        action = "weave"
    elseif inputs.weave_sub5_ready == true and inputs.weave_sub5_is_lavaburst == false
        and st.family == "WRATH" then
        -- 5c. Wrath Lightning Bolt fit (M1 HIGH): the gather verified the
        -- MW>=3 LB hardcast fits the live swing on a WF-imbue Wrath build
        -- (300 ms buffer). Ranked between MW5 and Flame Shock the way the
        -- default_wf APL ranks it (MW5 -> LB fit -> SS). SoD LB (ERA family)
        -- falls through to rule 12b below; the family gate keeps both ranks.
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
        if inputs.flameshock_allowed ~= false
            and (type(inputs.flameshock_remaining) ~= "number"
                or inputs.flameshock_remaining <= refresh)
            and not fs_fight_too_young(inputs) then
            -- 6. Flame Shock missing or inside its refresh window (vetoed on
            -- Era-base, where the sim never casts it; withheld on a young
            -- SoD/TBC fight, where both sims open without it).
            action = "flameshock"
        elseif type(inputs.twist_remaining) == "number" and inputs.twist_remaining <= 0
            and not (type(inputs.twist_mana_threshold) == "number"
                and type(inputs.mana_fraction) == "number"
                and inputs.mana_fraction <= inputs.twist_mana_threshold) then
            -- 7. Totem twist due (SKELETON: live inputs are nil outside TBC),
            -- suppressed while mana sits at or below the pause threshold (the
            -- same strictly-numeric boundary as should_pause_twist_for_mana:
            -- nil threshold twists as before, unknown mana never pauses).
            action = "twist"
        elseif inputs.stormstrike_hold_enabled == true
            and is_off_cooldown(inputs.stormstrike_remaining)
            and should_delay_stormstrike(inputs) then
            -- 8. Stormstrike ready but the Windfury ICD clears within this swing:
            -- hold it rather than waste the empowered proc chance. Opt-in only:
            -- every sim casts Stormstrike on cooldown, so the default presses it.
            hold = true
            hold_text = "WAIT"
        elseif st.shaman_guide.get_strength_of_earth_due(st.family,
            inputs.strength_of_earth_remaining, inputs.mw_observed) then
            -- 8a. The Strength of Earth Totem upkeep (the APL utility layer):
            -- the Era APL's i=0 row (the aura down), the TBC APL's Totems group
            -- row 3 (refresh at 5 s left) and the Forever APL's i=4 row (the
            -- earth slot empty). The read is the earth's slot clock; an
            -- unreadable slot feeds nil and never prompts.
            action = "strength_of_earth"
        elseif type(inputs.wftotem_remaining) == "number"
            and inputs.wftotem_remaining <= 0 then
            -- 8b. Era Windfury Totem maintain (G2): the sim refreshes
            -- Windfury first. The gather feeds due only on Era-base (an
            -- affirmatively emptied air slot, or Grace of Air holding it
            -- while Windfury is known), so every other family falls through
            -- exactly as before.
            action = "wftotem"
        elseif type(inputs.goatotem_remaining) == "number"
            and inputs.goatotem_remaining <= 0 then
            -- 8c. Era Grace of Air fallback (G2): due only while Windfury
            -- is unknown, so it can never overwrite a known Windfury and
            -- thrash the shared air slot.
            action = "goa"
        elseif st.shaman_guide.get_mana_spring_due(st.family,
            inputs.mana_spring_remaining) then
            -- 8d. The Mana Spring Totem upkeep (TBC only): the TBC APL's Totems
            -- group row 4, refreshed at 5 s left. The read is the water slot
            -- clock - on TBC the water slot carries Mana Spring.
            action = "mana_spring"
        elseif is_off_cooldown(inputs.stormstrike_remaining) then
            -- 9. Stormstrike is ready.
            action = "stormstrike"
        elseif st.shaman_guide.get_searing_upkeep_due(st.family, inputs.fight_elapsed,
            inputs.searing_down, inputs.mw_observed) then
            -- 9b. The Searing Totem maintain (S-17): the fire slot affirmatively
            -- holds no Searing and the fight is older than the family's gate
            -- (Era 20 s, SoD 30 s). ERA-only - the helper returns false on every
            -- other family, so no other client ever sees the prompt.
            action = "searing"
        elseif st.family == "WRATH" and type(inputs.water_remaining) == "number"
            and inputs.water_remaining < st.shaman_guide.COE_WATER_REFRESH_SECONDS then
            -- 9c. Call of the Elements (S-20 / U-10): the Wrath enhancement APLs
            -- rank CoE between Earth Shock and Magma Totem, gated on the water
            -- totem being under 20 s. WRATH-only - the Era/TBC/Forever sims run
            -- no CoE line, so the feed is the only place they could see it and
            -- this gate keeps them silent. An unknown water read (nil) never
            -- prompts (unknown-hides).
            action = "coe"
        elseif type(inputs.magma_remaining) == "number"
            and inputs.magma_remaining <= magma_refresh then
            -- 10. Magma Totem due for (re-)drop.
            action = "magma"
        elseif st.family ~= "ERA" and st.family ~= "FOREVER"
            and is_off_cooldown(inputs.firenova_remaining)
            and inputs.fireele_active ~= true then
            -- 11. Fire Nova ready while Stormstrike is down - except on Era (the
            -- sim runs no Nova there), on Forever (ranked below Earth Shock, rule
            -- 16), and while a live Fire Elemental holds the fire slot (the sim
            -- never replaces it).
            action = "firenova"
        elseif st.shaman_guide.get_lightningshield_family_gate(st.family, inputs.mw_observed)
            and inputs.lightningshield_due == true then
            -- 11b. The Lightning Shield maintain (S-19): the Wrath enhancement APLs
            -- maintain it iff inactive, above Lava Lash; the SoD phase_6 APL's i=8
            -- row and the Forever APL's i=6 row cast 10432 the same way. The family
            -- gate is the helper's: WRATH, FOREVER and the SoD build on the ERA
            -- token (the MW-rune latch); the Era-base and TBC sims run no Lightning
            -- Shield row, so they never see the prompt. A nil feed never prompts
            -- (unknown-hides).
            action = "lightningshield"
        elseif type(inputs.lavalash_remaining) == "number"
            and inputs.lavalash_remaining <= 0 then
            -- 12. Lava Lash ready.
            action = "lavalash"
        elseif inputs.weave_sub5_ready == true and inputs.weave_sub5_is_lavaburst == false then
            -- 12b. SoD Lightning Bolt fit (G1 LOW): same strict-boolean gate as
            -- rule 5b, ranked below Lava Lash the way the sim ranks it (LL >
            -- LB fit > CL). Nil/false ready never prompts, nil is_lavaburst
            -- never prompts.
            action = "weave"
        elseif mw_ok and type(inputs.mw_stacks) == "number"
            and inputs.mw_stacks >= st.shaman_guide.MW_CL_MIN_STACKS
            and type(inputs.target_count) == "number"
            and inputs.target_count >= st.shaman_guide.CL_MIN_TARGETS then
            -- 13. Multi-target Chain Lightning (SoD: MW >= 4 with 2+ targets).
            -- SKELETON, unreachable: the enemy-count sensor does not exist (no
            -- client API counts enemies), so no producer ever feeds target_count
            -- and the rotation row claims no engine arm (live = false,
            -- engine = false). The cut is the operator's O-4 decision.
            action = "chainlightning"
        elseif uses_frost_shock_filler(inputs)
            and type(inputs.frostshock_remaining) == "number"
            and inputs.frostshock_remaining <= 0 then
            -- 13b. Frost Shock as the TBC shock filler (the APL's Shocks group
            -- row 2, 25464 r5): the ALTERNATIVE "Filler Shock" choice. The
            -- group's row 3 (Earth Shock) is the valueVariables default, so
            -- this arm only fires when the choice is stated - and then rules
            -- 14 and 17 stay silent, because the group picks ONE filler.
            action = "frostshock"
        elseif es_permitted and is_off_cooldown(inputs.shock_remaining)
            and not uses_frost_shock_filler(inputs) then
            -- 14. The shock-capped Earth Shock filler: only while the shared shock
            -- cooldown is actually ready, so Molten Blast below alternates on the
            -- shock global. Silent while the TBC filler shock is Frost Shock
            -- (rule 13b owns the shock slot then).
            action = "earthshock"
        elseif type(inputs.moltenblast_remaining) == "number"
            and inputs.moltenblast_remaining <= 0 then
            -- 15. Molten Blast ready (SoD filler below Earth Shock).
            action = "moltenblast"
        elseif st.family == "FOREVER"
            and is_off_cooldown(inputs.firenova_remaining)
            and (inputs.clearcasting_active == true
                or (type(inputs.mana_fraction) == "number"
                    and inputs.mana_fraction > st.shaman_guide.FN_MANA_FLOOR_FOREVER)) then
            -- 16. Forever Fire Nova: free on Clearcasting, else a mana dump above
            -- 10% - ranked below Earth Shock the way the sim ranks it.
            action = "firenova"
        elseif es_permitted and not uses_frost_shock_filler(inputs) then
            -- 17. The shock filler.
            action = "earthshock"
        end
        -- Era-base at low mana reaches here with es_permitted false: no action, no
        -- hold (the Era sim casts no filler there either).
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

--=========================================================================================
-- PRACTICE SURFACE (bench/class_features_drills_2026-10-19.md §2.6 C + D)
--
-- The practice layer the shared engine drives (practice.lua:3223-3477). It rides the
-- guide contract above: the same display slots, the same frozen input set and the
-- same rule order - the scenario step IS the live engine's verdict, so the practice
-- surface teaches exactly what the guide shows. The S-19 / S-17 slots and rules
-- (Lightning Shield, Searing Totem) landed with it, and so did S-20 (Call of the
-- Elements): its slot, its rule (9c) and the water clock.
--
--   st.shaman_guide.build_practice_inputs(ctx, out)
--       The frozen input set, written from a practice ctx
--       ({ now, last_action, resources, cooldowns }) into the caller's table. Every
--       field it owns is written on every call, so a reused table never keeps a
--       stale value - the same rule the live gather follows.
--   st.shaman_guide.practice_step(ctx, out)
--       The rotation's next action: { action = "<slot key>", reason = "<text>" } or
--       nil when the engine cannot decide (an idle engine, or a hold - RIDE / WAIT).
--   st.shaman_guide.grade_enh_priority / grade_mw_weave / grade_stormstrike_hold /
--       grade_totem_upkeep
--       The audit's four target drills (§2.6 C: D-S1..D-S4). Each returns ONE
--       attempt's grade ("S".."F") or nil when the attempt is not judgeable (the
--       engine shows UNKNOWN and records no attempt). The session band on the
--       mis-pick count (S = clean, A = 1, ... F = more than 5 - the audit's D-S1
--       bands) belongs to the shared engine's run summary (practice.lua:3370-3377,
--       ROTATION_RUN_BANDS); the per-decision grade here is S (the expected action)
--       or F (anything else), the same outcome grades the engine grades with
--       (practice.lua:3390-3394).
--
-- Every number below is either a value already frozen in this module (cited above) or
-- a [DESIGN] band the audit writes. Nothing here invents a spell id.
--=========================================================================================

-- The reason line per action key: one short sentence for the scenario panel.
st.shaman_guide.PRACTICE_REASONS = {
    fireele = "Fire Elemental ready",
    feralspirit = "Feral Spirit ready",
    bloodlust = "Bloodlust ready",
    shamanisticrage = "Shamanistic Rage ready",
    weave = "Maelstrom stacks - weave now",
    flameshock = "Flame Shock due",
    twist = "Totem twist due",
    strength_of_earth = "Strength of Earth Totem due",
    wftotem = "Windfury Totem due",
    goa = "Grace of Air due",
    mana_spring = "Mana Spring Totem due",
    stormstrike = "Stormstrike off cooldown",
    searing = "Searing Totem due",
    coe = "Call of the Elements due",
    magma = "Magma Totem due",
    firenova = "Fire Nova ready",
    lightningshield = "Lightning Shield due",
    lavalash = "Lava Lash ready",
    chainlightning = "Chain Lightning - two or more targets",
    frostshock = "Frost Shock filler",
    earthshock = "Earth Shock filler",
    moltenblast = "Molten Blast ready",
}

-- The frozen input names the practice ctx feeds through ctx.cooldowns: each entry is
-- { ctx key, frozen input name }. The ctx key is the ACTION KEY the rotation table
-- and the guide slots use (stormstrike, firenova, ...); where the action key and
-- the frozen input name differ (Grace of Air, the shared shock cooldown) the alias
-- is listed next to it, and the "_remaining" spelling of the frozen input name is
-- accepted for every one of them. A missing read stays nil (unknown-hides: the
-- engine never prompts on a guess).
st.shaman_guide.PRACTICE_COOLDOWN_FIELDS = {
    { "stormstrike", "stormstrike_remaining" },
    { "flameshock", "flameshock_remaining" },
    { "firenova", "firenova_remaining" },
    { "fireele", "fireele_remaining" },
    { "feralspirit", "feralspirit_remaining" },
    { "lavalash", "lavalash_remaining" },
    { "shamanisticrage", "sr_remaining" },
    { "magma", "magma_remaining" },
    { "moltenblast", "moltenblast_remaining" },
    { "shock", "shock_remaining" },
    { "earthshock", "shock_remaining" }, -- the shared shock cooldown (the ES action key)
    { "twist", "twist_remaining" },
    { "wftotem", "wftotem_remaining" },
    { "goatotem", "goatotem_remaining" },
    { "goa", "goatotem_remaining" }, -- the Grace of Air action key
    { "searing", "searing_down" }, -- the Searing maintain's due flag (not a timer)
    { "lightningshield", "lightningshield_due" }, -- the Lightning Shield maintain's due flag
    { "strength_of_earth", "strength_of_earth_remaining" }, -- the earth-slot clock (0 = due)
    { "mana_spring", "mana_spring_remaining" }, -- the water-slot clock (0 = due)
    { "bloodlust", "bloodlust_remaining" },
    { "frostshock", "frostshock_remaining" },
}

-- The frozen input names the practice ctx feeds through ctx.resources (the same
-- names the live gather writes - the audit's §4.5 "the input writer must use the
-- engine's own frozen input names").
st.shaman_guide.PRACTICE_RESOURCE_FIELDS = {
    "speed", "swing_remaining", "gcd_remaining", "casting",
    "mw_available", "mw_stacks", "weave_available",
    "weave_sub5_ready", "weave_sub5_cast_seconds", "weave_sub5_is_lavaburst",
    "flameshock_refresh", "flameshock_allowed",
    "fight_elapsed", "stormstrike_hold_enabled", "windfury_icd_remaining",
    "fireele_active", "twist_mana_threshold", "sr_mana_threshold",
    "mana_fraction", "target_count", "clearcasting_active", "magma_refresh",
    "mw_observed", "water_remaining", "water_duration", "filler_shock",
}

-- One reused input table and one reused output table for the practice path: the
-- scenario asks at the GCD rate and the drills re-read the same state, so no
-- per-call allocation is wanted here either (the same rule the live gather
-- follows).
st.shaman_guide.practice_inputs = {}
st.shaman_guide.practice_out = {}

-- Pure: the practice ctx's resource bag (an empty table when the ctx carries none,
-- so a reader never has to nil-check).
function st.shaman_guide.get_practice_resources(ctx)
    if type(ctx) == "table" and type(ctx.resources) == "table" then
        return ctx.resources
    end
    return {}
end

-- Pure: the family the practice run is on: ctx.resources.family when the simulator
-- states one, else the client's own family (st.family) - the same family token the
-- engine's own gates read.
function st.shaman_guide.get_practice_family(ctx)
    local family = st.shaman_guide.get_practice_resources(ctx).family
    if type(family) ~= "string" or family == "" then
        family = st.family
    end
    return family
end

-- Pure: the action under test. The contract's ctx names it last_action; "action",
-- "pick", "pressed" and "choice" are accepted as aliases so the shared engine can
-- name it either way. A non-string or an empty string reads as "nothing cast".
function st.shaman_guide.get_practice_pick(ctx)
    if type(ctx) ~= "table" then
        return nil
    end
    local value = ctx.action
    if type(value) ~= "string" then value = ctx.pick end
    if type(value) ~= "string" then value = ctx.pressed end
    if type(value) ~= "string" then value = ctx.choice end
    if type(value) ~= "string" then value = ctx.last_action end
    if type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

-- Pure: write the frozen input set from a practice ctx into the caller's table.
-- Every field this function owns is written on every call (nil when the ctx does
-- not carry it), so a reused table never keeps a stale value.
function st.shaman_guide.build_practice_inputs(ctx, out)
    local guide = st.shaman_guide
    out = out or {}
    local resources = nil
    local cooldowns = nil
    if type(ctx) == "table" then
        if type(ctx.resources) == "table" then resources = ctx.resources end
        if type(ctx.cooldowns) == "table" then cooldowns = ctx.cooldowns end
    end
    for i = 1, #guide.PRACTICE_COOLDOWN_FIELDS do
        out[guide.PRACTICE_COOLDOWN_FIELDS[i][2]] = nil
    end
    for i = 1, #guide.PRACTICE_RESOURCE_FIELDS do
        out[guide.PRACTICE_RESOURCE_FIELDS[i]] = nil
    end
    for i = 1, #guide.PRACTICE_COOLDOWN_FIELDS do
        local key = guide.PRACTICE_COOLDOWN_FIELDS[i][1]
        local input = guide.PRACTICE_COOLDOWN_FIELDS[i][2]
        local value = nil
        if cooldowns then
            value = cooldowns[key]
            if value == nil then value = cooldowns[input] end
        end
        if value == nil and resources then
            value = resources[key]
            if value == nil then value = resources[input] end
        end
        if value == nil and type(ctx) == "table" then
            value = ctx[key]
            if value == nil then value = ctx[input] end
        end
        if value ~= nil then
            out[input] = value
        end
    end
    for i = 1, #guide.PRACTICE_RESOURCE_FIELDS do
        local name = guide.PRACTICE_RESOURCE_FIELDS[i]
        local value = nil
        if resources then value = resources[name] end
        if value == nil and type(ctx) == "table" then value = ctx[name] end
        if value ~= nil then
            out[name] = value
        end
    end
    return out
end

-- Pure: the engine's verdict for a practice ctx. Returns the out table (the frozen
-- display fields) and the inputs it was built from.
function st.shaman_guide.practice_expected(ctx, out)
    local guide = st.shaman_guide
    local inputs = guide.build_practice_inputs(ctx, guide.practice_inputs)
    local res = guide.evaluate(inputs, out or guide.practice_out)
    return res, inputs
end

-- Pure: the short reason line for a verdict.
function st.shaman_guide.practice_reason(res, inputs)
    local action = res and res.action
    if action == "weave" then
        if type(inputs) == "table" and type(inputs.mw_stacks) == "number"
            and inputs.mw_stacks >= 5 then
            return "Five Maelstrom stacks - instant weave"
        end
        return "Sub-5 weave fits the swing"
    end
    return st.shaman_guide.PRACTICE_REASONS[action] or "Follow the rotation"
end

-- Pure: the rotation's next action for a practice ctx.
--   -> { action = "<slot key>", reason = "<text>" } | nil
-- nil means "cannot decide": an idle engine (no action), a hold (RIDE while a cast
-- is in flight, WAIT while the Stormstrike is fished) or a missing guide module. The
-- engine grades such a step UNKNOWN - it never records a wrong action.
function st.shaman_guide.practice_step(ctx, out)
    local guide = st.shaman_guide
    if not (guide and guide.evaluate) then
        return nil
    end
    local res, inputs = guide.practice_expected(ctx, out)
    if res.hold then
        return nil
    end
    if type(res.action) ~= "string" or res.action == "" then
        return nil
    end
    return { action = res.action, reason = guide.practice_reason(res, inputs) }
end

-- Pure: band a value against a band table (the same shape the shared engine's
-- H.grade_band uses: the first band whose max the value fits wins, the open band
-- is the fallback).
function st.shaman_guide.band_grade(value, bands)
    if type(bands) ~= "table" then
        return nil
    end
    local fallback = nil
    for i = 1, #bands do
        local band = bands[i]
        if type(band) == "table" and band.grade then
            if band.max == nil then
                if fallback == nil then fallback = band.grade end
            elseif type(value) == "number" and value <= band.max then
                return band.grade
            end
        end
    end
    return fallback
end

--=========================================================================================
-- Drill D-S1 - the enhancement priority (audit §2.6 C, D-S1)
--=========================================================================================
-- What it grades: the spine the sims encode - Feral Spirit -> Shamanistic Rage ->
-- the weave -> Stormstrike -> Flame Shock -> Earth Shock -> Molten Blast -> Chain
-- Lightning. The expected action is the GUIDE's own verdict (the audit's §2.6 D
-- "expected-sequence comparison": st.shaman_guide.evaluate at every tick), so the
-- drill teaches the same priority the live guide shows.
-- Per-decision grade: S when the cast matches the verdict, F when it does not
-- (the shared engine grades the run's mis-pick count into the session band).
-- A hold (RIDE / WAIT) or an idle engine grades nil - there is no decision to
-- judge, and D-S3 owns the Stormstrike hold.
st.shaman_guide.PRACTICE_DRILL_PRIORITY = "shaman_enh_priority"

function st.shaman_guide.grade_enh_priority(ctx)
    local guide = st.shaman_guide
    if not (guide and guide.evaluate) then
        return nil
    end
    local res = guide.practice_expected(ctx, guide.practice_out)
    if res.hold then
        return nil
    end
    if type(res.action) ~= "string" or res.action == "" then
        return nil
    end
    local pick = guide.get_practice_pick(ctx)
    if pick == nil then
        return nil
    end
    if pick == res.action then
        return "S"
    end
    return "F"
end

--=========================================================================================
-- Drill D-S2 - the stack decision (audit §2.6 C, D-S2)
--=========================================================================================
-- What it grades: whether to weave NOW - the Maelstrom stack count the build plays,
-- the cast-time fit against the swing and the buffer. The maths is weave.lua's own
-- (the marker fraction and the clip amount), so the drill grades the real
-- marker/clip window the assist draws, not a copy of it.
-- Bands [DESIGN, the audit's D-S2]: the shared weave margin bands (practice.lua:
-- 2405-2411) - a clip is F, otherwise S <= 0.02 s, A <= 0.05, B <= 0.10, C <= 0.20,
-- D beyond. A weave taken BELOW the family's stack floor is a wrong pick (F):
-- SoD weaves at ANY stack (the sim's 100 ms fit gate), the Wrath default_wf APL
-- hardcasts at MW >= 3, and every other family has no Maelstrom Weapon at all, so
-- the floor there is the MW5 instant.
st.shaman_guide.PRACTICE_DRILL_MW_WEAVE = "shaman_mw_weave"

-- The weave drill's defaults: the shared harness WEAVE_DEFAULTS (practice.lua:2403).
st.shaman_guide.WEAVE_DRILL_DEFAULTS = {
    swing_duration = 2.6,
    effective_cast = 1.5,
    latency = 0.1,
}

-- The margin bands: the shared weave bands (practice.lua:2405-2411).
st.shaman_guide.WEAVE_MARGIN_BANDS = {
    { max = 0.02, grade = "S" },
    { max = 0.05, grade = "A" },
    { max = 0.10, grade = "B" },
    { max = 0.20, grade = "C" },
    { grade = "D" },
}

-- The Maelstrom stack floor per family (the audit's S-02 / S-03 / S-04 and the
-- engine's WEAVE_SUB5_MIN_STACKS / WEAVE_SUB5_MIN_STACKS_WRATH).
st.shaman_guide.MW_STACK_FLOOR_SOD = 0
st.shaman_guide.MW_STACK_FLOOR_WRATH = 3
st.shaman_guide.MW_STACK_FLOOR_DEFAULT = 5

-- Pure: the Maelstrom stack floor for a family. The SoD case is the ERA token plus
-- the observed MW rune (the SoD latch, bench/lessons.md); an Era-base client never
-- observes the rune, so its floor is the MW5 instant (it has no weave at all).
function st.shaman_guide.get_mw_stack_floor(family, mw_observed)
    if family == "ERA" then
        if mw_observed == true then
            return st.shaman_guide.MW_STACK_FLOOR_SOD
        end
        return st.shaman_guide.MW_STACK_FLOOR_DEFAULT
    end
    if family == "WRATH" then
        return st.shaman_guide.MW_STACK_FLOOR_WRATH
    end
    return st.shaman_guide.MW_STACK_FLOOR_DEFAULT
end

-- Pure: the weave marker fraction through weave.lua's model; nil when weave.lua is
-- absent or the cast time is unresolvable (never a marker on a guess).
function st.shaman_guide.get_weave_marker(duration, cast, latency)
    local weave = st.weave
    if not (weave and weave.get_marker_fraction) then
        return nil
    end
    return weave.get_marker_fraction(duration, cast, latency)
end

-- Pure: the clip amount through weave.lua's model; nil when weave.lua is absent.
function st.shaman_guide.get_weave_clip(now, latency, cast, swing_ends_at)
    local weave = st.weave
    if not (weave and weave.get_clip_amount) then
        return nil
    end
    return weave.get_clip_amount(now, latency, cast, swing_ends_at)
end

function st.shaman_guide.grade_mw_weave(ctx)
    local guide = st.shaman_guide
    local res = guide.get_practice_resources(ctx)
    local pick = guide.get_practice_pick(ctx)
    -- Only a weave press is scored: the drill grades the weave decision, not the
    -- rotation around it (D-S1 grades the order).
    if pick ~= "weave" then
        return nil
    end
    local defaults = guide.WEAVE_DRILL_DEFAULTS
    local cast = res.weave_cast_seconds
    if type(cast) ~= "number" then cast = res.effective_cast end
    if type(cast) ~= "number" then cast = defaults.effective_cast end
    local duration = res.swing_duration
    if type(duration) ~= "number" or duration <= 0 then duration = defaults.swing_duration end
    local latency = res.latency
    if type(latency) ~= "number" then latency = defaults.latency end
    local swing_remaining = res.swing_remaining
    if type(swing_remaining) ~= "number" then
        return nil
    end
    -- The stack floor: a weave below it is a wrong pick whatever the timing.
    local floor = guide.get_mw_stack_floor(guide.get_practice_family(ctx), res.mw_observed)
    if type(res.mw_stacks) == "number" and res.mw_stacks < floor then
        return "F"
    end
    local marker = guide.get_weave_marker(duration, cast, latency)
    if marker == nil then
        return nil
    end
    local now = 0
    if type(ctx) == "table" and type(ctx.now) == "number" then
        now = ctx.now
    end
    local elapsed = duration - swing_remaining
    if elapsed < 0 then elapsed = 0 end
    local fraction = elapsed / duration
    if fraction > 1 then fraction = 1 end
    local clip = guide.get_weave_clip(now, latency, cast, now + swing_remaining)
    if type(clip) == "number" and clip > 0 then
        return "F"
    end
    local margin = marker - fraction
    if margin < 0 then margin = 0 end
    return guide.band_grade(margin, guide.WEAVE_MARGIN_BANDS)
end

--=========================================================================================
-- Drill D-S3 - the Stormstrike decision (audit §2.6 C, D-S3)
--=========================================================================================
-- What it grades: the one place the sims and our history disagree - holding
-- Stormstrike for the Windfury proc instead of pressing it on cooldown. Every
-- fetched sim casts Stormstrike on cooldown (audit §2.6 S-01), so the default
-- presses it; the hold is our own behaviour and is opt-in (the guide's
-- stormstrike_hold_enabled input).
-- Bands [DESIGN, the audit's D-S3]: S = pressed the moment it came off cooldown,
-- A/B/C = late by at most one / two / three GCDs, D = later still. F = the
-- Stormstrike was held with the opt-in OFF (a dead GCD). With the opt-in on, a hold
-- is legitimate and grades nil (nothing to judge).
st.shaman_guide.PRACTICE_DRILL_SS_HOLD = "shaman_stormstrike_hold"

-- The GCD length the "late by one GCD" band counts on: the module's own GCD
-- default (classes/shaman.lua's hud_gcd_remaining falls back to 1.5 s). A caller
-- may state its own through ctx.resources.gcd.
st.shaman_guide.GCD_SECONDS_DEFAULT = 1.5

st.shaman_guide.SS_HOLD_LATENESS_BANDS = {
    { max = 0, grade = "S" },
    { max = 1.5, grade = "A" },
    { max = 3.0, grade = "B" },
    { max = 4.5, grade = "C" },
    { grade = "D" },
}

function st.shaman_guide.grade_stormstrike_hold(ctx)
    local guide = st.shaman_guide
    local res = guide.get_practice_resources(ctx)
    local pick = guide.get_practice_pick(ctx)
    local enabled = res.stormstrike_hold_enabled == true
    local now = nil
    if type(ctx) == "table" then now = ctx.now end
    local ready_at = res.ss_ready_at
    if type(ready_at) == "number" and type(now) == "number" then
        local lateness = now - ready_at
        if lateness < 0 then lateness = 0 end
        if pick == "stormstrike" then
            local gcd = res.gcd
            if type(gcd) ~= "number" or gcd <= 0 then
                gcd = guide.GCD_SECONDS_DEFAULT
            end
            local bands = {
                { max = 0, grade = "S" },
                { max = gcd, grade = "A" },
                { max = gcd * 2, grade = "B" },
                { max = gcd * 3, grade = "C" },
                { grade = "D" },
            }
            return guide.band_grade(lateness, bands)
        end
        if pick == nil then
            -- Nothing was cast: there is no press to judge.
            return nil
        end
        -- The Stormstrike was held.
        if enabled then
            -- The opt-in is on: the hold is the player's own choice, not a mistake.
            return nil
        end
        -- The opt-in is off: every sim casts Stormstrike on cooldown, so holding it
        -- is a dead GCD.
        return "F"
    end
    -- No ready stamp: the Stormstrike's own cooldown decides. An unknown
    -- cooldown grades nothing (never a verdict on a guess).
    local inputs = guide.build_practice_inputs(ctx, guide.practice_inputs)
    local remaining = inputs.stormstrike_remaining
    if type(remaining) ~= "number" then
        return nil
    end
    if remaining > 0 then
        -- Still on cooldown: the decision has not come up yet.
        return nil
    end
    if pick == nil then
        return nil
    end
    if pick == "stormstrike" then
        return "S"
    end
    if enabled then
        return nil
    end
    return "F"
end

--=========================================================================================
-- Drill D-S4 - the totem upkeep (audit §2.6 C, D-S4)
--=========================================================================================
-- What it grades: keeping the air slot (Windfury Totem / Grace of Air) and the fire
-- slot (Magma / Searing) occupied, and never replacing a live Fire Elemental.
-- The Searing line is the groundwork the audit lists unwired (audit §2.6 S-17: the
-- fight clock and the fire-slot reader ship, no rule reads them) - the practice
-- surface is where they are consumed; the live guide still has no Searing slot
-- (filed, see the class module).
-- Bands [DESIGN, the audit's D-S4]: S = the due slot was re-dropped inside its
-- window, A/B/C = late by at most 1 / 2 / 3 s, D = the slot was left empty past
-- its window, F = the Fire Elemental was overwritten.
st.shaman_guide.PRACTICE_DRILL_TOTEM_UPKEEP = "shaman_totem_upkeep"

st.shaman_guide.TOTEM_LATENESS_BANDS = {
    { max = 0, grade = "S" },
    { max = 1, grade = "A" },
    { max = 2, grade = "B" },
    { max = 3, grade = "C" },
    { grade = "D" },
}

-- The Searing Totem maintain gates and the pure due-predicate live with the rule
-- matrix above (rule 9b): the live guide and this drill grade the same gate, so
-- there is exactly one source for it.

-- The due upkeep slot for a practice ctx: the air slot first (the sim's priority -
-- Windfury before Grace of Air), then the fire slot (Magma before Searing, the
-- TBC sim's order). nil when nothing is due.
function st.shaman_guide.get_totem_upkeep_due(ctx, inputs)
    local guide = st.shaman_guide
    inputs = inputs or guide.build_practice_inputs(ctx, guide.practice_inputs)
    if type(inputs.wftotem_remaining) == "number" and inputs.wftotem_remaining <= 0 then
        return "wftotem"
    end
    if type(inputs.goatotem_remaining) == "number" and inputs.goatotem_remaining <= 0 then
        return "goa"
    end
    if type(inputs.magma_remaining) == "number" then
        local refresh = inputs.magma_refresh
        if type(refresh) ~= "number" then
            refresh = guide.MAGMA_REFRESH_DEFAULT
        end
        if inputs.magma_remaining <= refresh then
            return "magma"
        end
    end
    local res = guide.get_practice_resources(ctx)
    -- The Searing legs come from the frozen inputs the writer owns (the same names
    -- the live gather writes); the ctx resource is the fallback for a caller that
    -- builds the inputs by hand.
    local searing_down = inputs.searing_down
    if searing_down == nil then
        searing_down = res.searing_down
    end
    local sod_observed = inputs.mw_observed
    if sod_observed == nil then
        sod_observed = res.mw_observed
    end
    if guide.get_searing_upkeep_due(guide.get_practice_family(ctx), inputs.fight_elapsed,
        searing_down, sod_observed) then
        return "searing"
    end
    return nil
end

function st.shaman_guide.grade_totem_upkeep(ctx)
    local guide = st.shaman_guide
    local res = guide.get_practice_resources(ctx)
    local pick = guide.get_practice_pick(ctx)
    if pick == nil then
        return nil
    end
    local inputs = guide.build_practice_inputs(ctx, guide.practice_inputs)
    -- The Fire Elemental holds the fire slot: replacing it is the F case (the TBC
    -- sim never replaces the Elemental).
    if inputs.fireele_active == true and (pick == "magma" or pick == "searing") then
        return "F"
    end
    local due = guide.get_totem_upkeep_due(ctx, inputs)
    if due == nil then
        -- Nothing was due: the drill has no decision to judge.
        return nil
    end
    if pick ~= due then
        -- The due slot was left empty (or another slot was taken instead).
        return "D"
    end
    local due_at = res.totem_due_at
    local now = nil
    if type(ctx) == "table" then now = ctx.now end
    if type(due_at) ~= "number" or type(now) ~= "number" then
        -- The window cannot be measured without the due stamp: the right drop
        -- grades as on time, the wrong one as an empty slot (above).
        return "S"
    end
    local lateness = now - due_at
    if lateness < 0 then lateness = 0 end
    return guide.band_grade(lateness, guide.TOTEM_LATENESS_BANDS)
end
