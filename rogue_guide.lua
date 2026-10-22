--=========================================================================================
-- Rogue next-action guide: pure decision engine, no WoW API and no clock.
--
-- The sixth provider's decision model for the frozen ST.<CLASS>.guide contract
-- (nextaction_ui.lua's header; the paladin ships the first provider, the warrior
-- the second, the druid the third, the shaman the fourth, the hunter the fifth).
-- The live reads will live in classes/rogue.lua (ST.ROGUE.gather_guide_inputs -
-- owned by the parallel skeleton lane); this module only consumes the gathered
-- inputs, so it is unit-tested offline by tests/rogue_guide_state.lua.
--
-- Evidence (bench/rogue_research_2026-10-19.md, bench/rogue_deep_2026-10-19.md,
-- bench/rogue_rotation_audit_2026-10-19.md — the wowsims-sim comparison that
-- re-sourced every default below; sim spell ids are sim-side evidence only and
-- are never proposed for our tables):
--   pooling  rogue_research §1.3: never pool above 65 pre-tick / 85 post-tick;
--            Relentless Strikes refunds 25 on finishers - finisher BEFORE the tick
--            that would cap you. TICK 20 / 2 s is Era+TBC CONFIRMED (§§1.1/1.3);
--            retail pooling is phase-based, not tick-based (§1.6).
--            Rotation audit: TBC sim pools on a single 71 line (T-M1);
--            Forever cap-danger is 75 (V-G6); ERA keeps the tick-gated 65/85
--            (F2 MATCH); the Era sweaty APL spends at energy>=79 regardless of
--            swing phase (E-G1).
--   rupture  rogue_research §1.3: TBC Rupture > Eviscerate generally (T-M2
--            MATCH); Era sims are Evisc-only — Rupture-first is sim-contradicted
--            there (E-C1) so ERA plans Eviscerate; TBC/FOREVER recast when
--            missing, no early refresh (T-G3). Finisher floors are per-family
--            (ERA 8 / TBC 5 / WRATH 4 / FOREVER 6 — T-C1/W-M2/V-G3); the Wrath
--            1CP 8 s / 5CP 16 s durations ship as DATA below (2 of 5 rows
--            sim-sourced, W-M2; 2-4CP UNCONFIRMED — filed; no sim rule
--            consumes the table yet so the flat floors still govern).
--   envenom  rogue_research §3.5: the rules DIFFER per client - never share one
--            Envenom rule. TBC: only on dying targets (consumes stacks, mid-fight
--            DPS loss). WotLK sin: maintain the buff, let it EXPIRE before
--            re-apply unless energy-capping (W-M1 STRONG MATCH). Retail sin:
--            chain deliberately. Forever beta: Eviscerate dump, no Envenom
--            prompt. SoD (ERA family): the SOD primary table below, reached
--            only behind the provider's sod_envenom latch (ERA + the SoD-only
--            Envenom rune known - bench/sod_detect); without the latch ERA
--            keeps its dying-only shape (no global SoD token).
--   snd      Rotation audit F0/H1: EVERY sim APL maintains SnD (classic 1+CP
--            early, TBC 10 s minimum + EA/SnD-safe gates, Forever 1+CP clip 0,
--            WotLK <=1 s). Per-CP durations [9,12,15,18,21] s for CP 1-5
--            (classic/TBC sim-exact; WotLK +ImpSnD/glyph, Forever 1CP-clip,
--            SoD CttC filed as follow-ups). TBC 10 s minimum excludes 1CP
--            (9 s < 10 s) so TBC min CP is 2. Emitted as "snd" with NO slot yet
--            (the 7-slot contract is frozen — icon wiring is a filed follow-up
--            for a wider lane); the rotation label names it until then.
--   ea       rogue_research §1.3: Imp-EA 100%-uptime juggle (refresh before
--            falloff; 2-5 CP SnDs between). Rotation audit H4: the window is
--            per-client — ERA 3 s (E-G4 MATCH), TBC imminent 6 s (T-G2),
--            FOREVER lockout 16 s (V-G2); the TBC 15 s minimum below plus the
--            TBC wait-HOLD / pool-release (rule 1a) and the Forever finisher
--            lockout ride the same duty (H6).
--   shiv     rogue_research §1.3/§1.4: Shiv keeps Deadly stacks alive / stacks the
--            OH on demand. Watch-list window: Shiv-ready when <2 s to falloff
--            (rogue_research §4). Rotation audit H7/T-G4: sim support is TBC
--            combat non-Mutilate only below 5CP, never WotLK/Forever defaults;
--            the engine gates to ERA+TBC (ERA kept ungated: no sim either way,
--            under-prompts nowhere) plus the TBC Mutilate/CP gates; the
--            EA-context check (incl. the 4 s Shiv minimum) is filed.
--   tea      rogue_deep §2.3: Thistle Tea item cue on low energy (Sno tracks Tea
--            on the PvE cooldown bar). Rotation audit H10: the line is
--            per-client — ERA 29 / TBC 30 / FOREVER 15 (E-G3/T-G5/V-G4) /
--            SOD 10 + 40-end (S-M1: 40 while ttd<=15 s, via the latch + TTD);
--            WRATH keeps 40 (the 50 line is potion, not Tea); Eureka-25 needs
--            the Eureka in-client probe (1259812 CLIENT-UNCONFIRMED) — filed.
--   ar/bf    Rotation audit F3/H11: sim AR/BF are energy-gated behind upkeep
--            (TBC AR<=40, Forever AR<=50 w/ SnD, classic AR energy<59+tick<1,
--            WotLK AR<=50; TBC BF w/ SnD+EA). Emitted as "ar"/"bf" with NO slot
--            yet (same filed icon wiring as SnD). Cold Blood ships slot-less
--            too (TBC w/ SnD, Forever at 5CP — audit F3/V-G5; lockout-yielding;
--            AR-buff sequencing filed). Tricks / Riposte / Killing Spree / HfB
--            / Overkill / Vanish need slots + APL-literal design — filed.
--   stacked  rogue_deep §2.7 + competitor_gaps R3: multi-CD yellow glow when two
--            or more offensive CDs ride at once (Sno buff tracker). The counted
--            set (AR + BF) is UNCONFIRMED beyond Sno's list.
--
-- FROZEN SPEC - display slots (ST.ROGUE.guide.slots, owned by the skeleton lane;
-- suggested keys - this engine only emits these action names):
--   builder   the family builder (Sinister Strike / Backstab / Mutilate /
--             Saber Slash / Hemorrhage - the winner of the class's candidate
--             chain, family-gated by BUILDER_GATED_FAMILIES above)
--   rupture   Rupture
--   eviscerate
--             Eviscerate
--   envenom   Envenom (per-client rule below)
--   expose    Expose Armor (EA-duty only)
--   shiv      Shiv (Deadly upkeep)
--   tea       Thistle Tea (item deficit cue)
-- Slot-less (rotation audit F0/H1 + F3/H11 — emitted with NO slot until a wider
-- lane wires icons + options; the frame shows NOW, the rotation label names
-- them, never a guess, never a crash):
--   snd       Slice and Dice upkeep (per-client window + min-CP data below)
--   ar        Adrenaline Rush (per-client energy gate below)
--   bf        Blade Flurry (behind SnD + EA)
--   coldblood Cold Blood (TBC w/ SnD, Forever at 5CP — audit F3/V-G5)
--   vanish      Vanish (the stealth opener - the SoD's Vanish -> Envenom row, the
--             WotLK's Vanish pop, the Forever client's Vanish rank 2)
--   ambush      Ambush (the Forever client's opener, behind the 462707 aura)
--   garrote     Garrote (the Forever client's opener, while its dot is down)
--   preparation Preparation (the Forever client's prep, when Vanish is not ready)
--   premeditation Premeditation (the Forever client's CP opener at cp <= 3)
--   venom       Venom (the Forever client's 1310703 finisher, while its buff is down)
--   poisoned_knife Poisoned Knife (the SoD's 4-stack Deadly Poison window)
--   blood_fury  Blood Fury (the Forever client's paired pop with Adrenaline Rush)
--   elunes_light Elune's Light (the Forever client's paired pop, id 1259799)
--   gnome_eureka Eureka! (the Forever client's Gnome racial, id 1259812)
--   tricks_of_the_trade Tricks of the Trade (the WotLK energy pop)
--   killing_spree     Killing Spree (the WotLK energy pop)
-- Labels (skeleton lane): labels = { hold = "POOL", ride = "NOW" } - the HOLD
-- overlay text below is already explicit, so the labels only cover fallbacks.
--
-- The APL utility layer (the operator's "a rotation that only carries the damage
-- abilities is not the class's rotation", bench/rotation_gap_vs_apl_2026-10-20.md
-- §3): the arms below are the sim APLs' own rows, re-fetched 2026-10-20 from
-- wowsims/{sod,forever,wotlk}/master. Every arm is family-gated and every arm
-- hides when its read cannot prove the line (unknown-hides - no advice beats
-- wrong advice). The rotation TABLE lives in classes/rogue.lua
-- (ST.ROGUE.practice_rotation): each row carries its APL citation, its
-- per-family spell id + name, its family gate and the two flags (live = the
-- read exists, engine = the engine has an arm).
--
-- FROZEN SPEC - inputs (all optional, nil never errors):
--   family                                   compat.lua's st.family ("ERA", "TBC",
--                                            "WRATH", "FOREVER", "RETAIL", ...);
--                                            selects the pooling band and the
--                                            Envenom rule. Unknown (or nil) runs
--                                            no client-specific rule: Envenom
--                                            never prompts and pooling stays
--                                            silent (never a guessed verdict).
--   energy_now, energy_tick_in, max_energy   energy + seconds to the next 20-tick
--                                            (api.get_time() domain; the provider
--                                            converts); max_energy default 100
--                                            (Vigor +10 arrives through this input)
--   cp                                       combo points (nil = unreadable)
--   ttd                                      target seconds-to-die, NUMERIC INPUT
--                                            ONLY (the rogue-owned EMA below,
--                                            vendored from the druid-D4
--                                            precedent; this module never reads
--                                            units/health). nil = unknown. MUST be
--                                            live-provenance or EMA velocity -
--                                            never the enemy_swing 2.0 s fallback
--                                            (M7 corollary, rogue_readiness §4).
--   rupture_remains, rupture_refresh        Rupture seconds / refresh window
--                                            (default 4 - NEEDS IN-CLIENT
--                                            CONFIRMATION; no rogue source).
--   rupture_min_ttd                          TTD at/below which Rupture cannot pay
--                                            (default 8 = the sourced 1CP row,
--                                            rogue_research §5.2; the Wrath
--                                            per-CP durations ship as
--                                            RUPTURE_DURATION_BY_CP DATA
--                                            (1CP 8 s / 5CP 16 s, W-M2;
--                                            2-4CP UNCONFIRMED) and no sim
--                                            rule consumes them yet, so the
--                                            flat floors still govern).
--   finisher_min_cp                          CP needed for a planned finisher
--                                            (default 5 - the 5-CP Rupture /
--                                            Eviscerate / Envenom shape on every
--                                            classic-line client).
--   deadly_stacks                            Deadly Poison stacks (nil = unknown)
--   envenom_buff_remains                     Envenom buff seconds (nil = absent or
--                                            unanswered - prompts like the druid
--                                            rip/rake nil rule)
--   ea_duty, ea_remains, ea_refresh          Imp-EA duty flag + Expose Armor
--                                            seconds + refresh window (default is
--                                            per-family: ERA 3 / TBC 6 /
--                                            WRATH 3 / FOREVER 16 — audit H4;
--                                            explicit input still wins). The TBC
--                                            15 s minimum, the TBC wait/release
--                                            and the Forever lockout below all
--                                            ride this same flag (H6, default
--                                            off -> inert).
--   sod_envenom                              provider-owned SoD latch: exactly
--                                            true means this ERA player knows the
--                                            SoD-only Envenom rune (frozen at
--                                            post_init; nil/false reads
--                                            Era-base). Only rule 3 reads it.
--   snd_usable, snd_remains,                SnD upkeep: spell resolved + player
--   snd_refresh, snd_min_cp                   buff seconds + refresh window +
--                                            min CP (per-family: ERA 3s/1CP,
--                                            TBC 0s/2CP, WRATH 1s/1CP, FOREVER
--                                            0s/1CP, SOD 1s/4CP — audit F0/H1
--                                            + S-G1 (SOD via the latch);
--                                            explicit inputs still win;
--                                            missing (nil)
--                                            prompts — an upkeep gap, like the
--                                            druid rip/rake nil rule).
--   ar_ready, bf_ready                       AR / BF usability (known + usable +
--                                            no cooldown; the provider proves
--                                            each — nil never prompts).
--   coldblood_ready                          Cold Blood usability (known + usable +
--                                            no cooldown; the provider proves it —
--                                            nil never prompts; TBC + FOREVER
--                                            only — audit F3/V-G5).
--   shiv_ready, deadly_remaining,            Shiv usability + Deadly seconds to
--   shiv_refresh, mutilate_known,            falloff + refresh window (default 2,
--   cp (TBC gates)                             rogue_research §4 watch-list) +
--                                            Mutilate-known through the client's
--                                            own spell data (strict true reads
--                                            Mutilate; nil reads unknown — the
--                                            TBC Shiv gate withholds only on
--                                            exactly true) + CP (TBC Shivs
--                                            below 5CP).
--   tea_ready, tea_energy_max                Thistle Tea usability + the low-energy
--                                            line (per-family: ERA 29 / TBC 30 /
--                                            WRATH 40 / FOREVER 15 / SOD 10 +
--                                            40-end — audit H10 + S-M1 (SOD via
--                                            the latch); explicit input still
--                                            wins).
--   inputs_unknown                           explicit provider-owned M6 bit: true means
--                                            the live reads are unusable (or the secret
--                                            regime makes the auras unreadable), so no
--                                            rule may emit a verdict - the frame renders
--                                            "..." instead (no advice beats wrong advice).
--   pool_pre, pool_post                      optional band override (options tuning;
--                                            defaults come from POOL_BANDS below).
--   vanish_ready                             Vanish is known + usable + off
--                                            cooldown (the provider proves it — nil
--                                            never prompts). Per family the id
--                                            differs (SoD 1856 / Wrath 26889 /
--                                            Forever 1857 rank 2).
--   master_of_subtlety_active                the SoD's Master of Subtlety rune
--                                            aura (425096) is up - the SoD APL's
--                                            Vanish row wants it DOWN.
--   vanished_active                           the WotLK's 58426 aura is up - the
--                                            WotLK APL's Vanish row wants it
--                                            DOWN (the aura's NAME is
--                                            UNCONFIRMED; the id is the APL's).
--   ambush_ready, garrote_ready,             the Forever client's opener spells
--   preparation_ready, premeditation_ready,  (known + usable + off cooldown);
--   venom_ready, blood_fury_ready,           venom_ready is the 1310703 spell,
--   elunes_light_ready                       blood_fury_ready the Orc racial
--                                            20572, elunes_light_ready the
--                                            Forever client's 1259799.
--   ambush_cue_active                        the Forever client's 462707 aura is
--                                            up (the APL's Ambush cue - the
--                                            aura's NAME is UNCONFIRMED).
--   garrote_dot_active                       the target still carries the
--                                            Garrote dot (11290) - the Forever
--                                            APL's Garrote row wants it DOWN.
--   garrote_energy_cost                      the Garrote's CURRENT energy cost in
--                                            energy points (the APL's
--                                            spellCurrentCost(11290)) - the
--                                            Forever APL's Vanish row (i=3) fires
--                                            only while the energy covers it. nil
--                                            = the client cannot read the cost
--                                            (unknown-hides).
--   venom_buff_active                        the player carries the Venom aura
--                                            (1310703) - the Forever APL's Venom
--                                            row wants it DOWN.
--   ar_cd_remaining                          the Adrenaline Rush cooldown's
--                                            remaining seconds (nil = the AR is
--                                            off cooldown). The Forever APL pairs
--                                            its Blood Fury / Elune's Light rows
--                                            with the AR's time to ready.
--   ar_known                                 the Adrenaline Rush (13750) is known
--                                            (true) or not (false) - the split
--                                            ar_ready cannot make (the APL's
--                                            NOT(spellIsKnown) disjunct).
--   ar_buff_active                           the Adrenaline Rush's buff aura
--                                            (13750) is up (the APL's
--                                            auraIsActive(13750) disjunct).
--   gnome_eureka_ready                       the Gnome racial Eureka! (1259812)
--                                            is known + usable + off cooldown.
--   gnome_eureka_full_cd                     the Eureka! racial's FULL cooldown
--                                            in seconds (the APL's
--                                            spellFullCooldown(1259812)); nil =
--                                            the client cannot read it.
--   poisoned_knife_ready                     the SoD's Poisoned Knife rune spell
--                                            (425012) is known + usable + off
--                                            cooldown.
--   tricks_ready, killing_spree_ready        the WotLK's Tricks of the Trade
--                                            (57934) and Killing Spree (51690)
--                                            are known + usable + off cooldown.
--   envenom_ready                            Envenom (399963 on the SoD) is
--                                            known + usable + off cooldown - the
--                                            SoD APL's Vanish row is the
--                                            Vanish -> Envenom opener.
--
-- FROZEN SPEC - rule order (first match wins; exactly these rules):
--   0. unknown: inputs_unknown is true, or energy_now/cp is unusable -> out.unknown =
--      true, no action, no hold (the caller shows "..." - no advice beats wrong advice,
--      M6).
--   1. EA duty: ea_duty and (ea_remains nil or <= ea_refresh) -> "expose".
--      Nil prompts (missing upkeep, like the druid rip/rake nil rule). On
--      Forever the refresh prompts at 5CP only (the sim's Should-Cast-Check);
--      below 5CP the low-EA bar runs the lockout instead.
--   1a. TBC EA-duty window (H6): 5CP + ea_duty + EA known but below the
--      family minimum (EA_MINIMUM_BY_FAMILY) and above the imminent window:
--      SnD short of EA_WAIT_SND_MINIMUM (or energy at/above the pool post
--      line) releases into "expose" now (the sim's immediate cast); SnD
--      healthy + energy below the pool line holds (the sim's waitUntil).
--      Sits above SnD (the sim group outranks the SnD entry).
--   1b. SnD upkeep: snd_usable and cp >= snd_min_cp and (snd_remains nil or
--      <= snd_refresh) -> "snd". Nil prompts (missing upkeep). Slot-less until
--      the icon wiring lands (filed follow-up). Yields to the 1a hold and to
--      the Forever lockout (both sim-literal).
--   1x. The Forever opener cluster (the APL utility layer): the Forever APL
--      casts Ambush (i=1), Garrote (i=2), Vanish (i=3) and Preparation (i=5)
--      ABOVE its Slice and Dice upkeep (i=18), so the cluster sits above the
--      1b upkeep. Each row is its own APL condition (see the arms below).
--   1c. Hunger for Blood upkeep (Wrath sin, audit W-G1 / the class-feature
--      audit R-19): hfb_usable and (hfb_remains nil or <= hfb_refresh) ->
--      "hfb". The wowsims wotlk APL refreshes the buff when its aura has <= 1 s
--      left (ui/rogue/apls/mutilate.apl.json: auraRemainingTime(51662) <= 1s
--      -> cast 51662) - the same "refresh at the tail" shape as SnD. WRATH
--      only (the sim source is the wotlk repo); the spell id is sim-side
--      evidence only - the provider resolves the spell by its English name
--      through the client's own spell data and never ships an id. Nil prompts
--      (a missing buff is an upkeep gap, the SnD convention); an unreadable
--      clock hides. Yields to the 1a hold, to the Forever lockout and to the
--      dying-target skip (the SnD rule's own shape).
--   1d. Vanish (the stealth opener): the SoD APL's i=7 row (NOT the Master of
--      Subtlety aura AND cp == 5 AND Envenom castable) and the WotLK APL's
--      mutilate i=4 row (NOT the 58426 aura). Both need the read to prove the
--      spell is ready; an unreadable state hides.
--   1e. Poisoned Knife (the SoD's damage window): the SoD APL's i=5 row - the
--      target carries 4+ Deadly Poison stacks AND cp < 5 AND energy <= 80.
--   2. Shiv: shiv_ready with deadly falloff imminent
--      (deadly_remaining <= shiv_refresh) -> "shiv". A nil clock never prompts
--      (H4: ambiguous timing hides, never guesses). ERA+TBC only (audit H7);
--      TBC additionally needs Mutilate unknown (mutilate_known ~= true) and
--      cp below 5CP (audit T-G4); the EA-context check is filed.
--   3. Envenom: the per-client rule (ENVENOM_RULES - never shared):
--      ERA/TBC dying_only (ttd <= ttd_max, cp >= min_cp, stacks >= min_stacks);
--      WRATH let_expire (cp + 5 stacks prove it, buff active withholds unless
--      energy would cap); FOREVER never (beta dumps Eviscerate); RETAIL chain
--      (cp >= min_cp unless stacks are proven empty); SOD primary reached only
--      as ERA + sod_envenom == true (the provider's SoD latch). Yields to the
--      1a hold (the sim waits at 5CP instead of dumping).
--   3a. Premeditation (the Forever client's CP opener): the Forever APL's i=17
--      row - cast while cp <= 3. The Forever client's 14183 is Premeditation
--      (the Era/SoD/Wrath 14183 is the same spell; the Shadowstep id is
--      different on every client).
--   3b. Venom (the Forever client's 1310703 finisher): the Forever APL's i=19
--      row - the buff is DOWN AND cp >= 3. It sits above the dying dump and
--      the planned finisher because the APL casts it (i=19) before Rupture
--      (i=20).
--   4. dying-target dump: ttd known <= rupture_min_ttd (per-family: ERA 8 /
--      TBC 5 / WRATH 4 / FOREVER 6) and cp >= dump floor (ERA 1 / TBC 5 /
--      WRATH 4 / FOREVER 3) -> "eviscerate" (Era any-CP rule, §1.1, split per
--      T-C1). Yields to the 1a hold and to the Forever lockout.
--   5. planned finisher: cp >= finisher_min_cp (per-family: ERA 5 / TBC 5 /
--      WRATH 4 / FOREVER 3) -> ERA "eviscerate" (E-C1: Era sims are Evisc-only)
--      or finisher_for_ttd on the TTD (rupture-first elsewhere):
--      unknown TTD never guesses (nil); TTD at/below rupture_min_ttd ->
--      "eviscerate" (the target dies before a fresh finisher pays); Rupture
--      missing or inside its refresh window (per-family: TBC/FOREVER
--      recast-when-missing) -> "rupture"; otherwise -> "eviscerate".
--   5b. Adrenaline Rush: ar_ready and energy at/below the per-family line
--      (ERA <59 with tick<1 / TBC <=40 / WRATH <=50 / FOREVER <=50 w/ SnD) ->
--      "ar". Slot-less until the icon wiring lands (filed follow-up).
--   5c. Blade Flurry: bf_ready with SnD active (and EA healthy when on EA
--      duty) -> "bf". Slot-less until the icon wiring lands (filed).
--   5d. Cold Blood: coldblood_ready with SnD active (TBC) and at/above the
--      family CP line (FOREVER 5CP — audit V-G5) -> "coldblood". Slot-less
--      until the icon wiring lands (filed). Yields to the 1a hold and to
--      the Forever lockout (the sim suppresses CB while EA is low).
--   5e. RETIRED (the WotLK's Hypersharp row): the row's spell (54758) is the
--      Engineering belt enchant's EFFECT, not a spell the rogue casts, so
--      there is nothing to ask for and the arm is gone (the row keeps its
--      citation and its filed reason in classes/rogue.lua's rotation table).
--   5f. Tricks of the Trade (the WotLK's energy pop): the WotLK combat APL's
--      i=13 and mutilate i=8 rows - energy <= 50.
--   5g. Killing Spree (the WotLK's energy pop): the WotLK combat APL's i=14
--      row - energy <= 50.
--   5h. Blood Fury (the Forever client's paired pop): the Forever APL's i=11
--      row - the Adrenaline Rush's time to ready is at/above 1.9 m.
--   5i. Elune's Light (the Forever client's paired pop, id 1259799): the
--      Forever APL's i=12 row - the same Adrenaline Rush gate.
--   5j. Eureka! (the Forever client's Gnome racial, id 1259812): the Forever
--      APL's i=13 row (the APL's own "Gnome Eureka - Should Cast" variable) -
--      the racial is known + off cooldown AND one of the three readable
--      disjuncts holds (the Adrenaline Rush is unknown / its buff rides / its
--      time to ready outlasts the racial's full cooldown). The APL's fourth
--      disjunct (the fight is about to end) has no read, so the row can only
--      under-prompt.
--   6. Thistle Tea: tea_ready and energy_now <= tea_energy_max -> "tea".
--      SoD reads 10, or 40 while ttd <= 15 s (S-M1 fight-end exception).
--   7. pool-vs-spend (pool_verdict): the 1a hold reads "POOL" first; then
--      "spend" -> action "builder"; "pool" -> hold = true, hold_text = "POOL";
--      hold = true, hold_text = "POOL"; nil (no band for this client - RETAIL
--      pools by phase, not by tick) -> silent. ERA spends at >=79 regardless
--      of tick phase (sweaty override, E-G1).
--   8. no action.
--
-- Output: the frozen display fields are overwritten on every call:
--   action, hold, hold_text, filler_slot = nil, judge_slot = nil,
--   rotation_key = nil, waiting_judgement = false, unknown = bool.
--=========================================================================================
local _, st = ...

st.rogue_guide = st.rogue_guide or {}

-- Classic tick cadence: 20 energy / 2 s on the classic line (Era + TBC CONFIRMED,
-- rogue_research §§1.1/1.3). Retail is phase-based (rogue_research §1.6).
st.rogue_guide.TICK_ENERGY_DEFAULT = 20
st.rogue_guide.MAX_ENERGY_DEFAULT = 100

-- Pooling bands per client, as DATA (never bare constants): never pool above
-- `pre` with a tick coming, never sit above `post`. ERA keeps the tick-gated
-- 65/85 (classic MATCH, audit F2); TBC is the sim-validated single 71 line
-- (pre == post: at/above always spends — audit T-M1); WRATH keeps 65/85 (the
-- 85 cap-exception MATCHES W-M1); FOREVER caps at the sim's 75 cap-danger
-- line (audit V-G6). RETAIL is nil: phase-based pooling has no tick line.
st.rogue_guide.POOL_BANDS = {
    ERA     = { pre = 65, post = 85 },
    TBC     = { pre = 71, post = 71 },
    WRATH   = { pre = 65, post = 85 },
    FOREVER = { pre = 65, post = 75 },
}

-- Planned-finisher spine per client (audit H2): ERA sims are Evisc-only, so
-- ERA plans Eviscerate; every other classic-line client plans Rupture-first.
-- Unknown/RETAIL falls back to the rupture-first shape (every rogue client
-- has Rupture/Eviscerate — F6 pin).
st.rogue_guide.FINISHER_MODES = {
    ERA = "eviscerate",
    TBC = "rupture",
    WRATH = "rupture",
    FOREVER = "rupture",
}

-- Planned-finisher CP line per client (audit V-G3: Forever spends from 3CP;
-- W-G2: WotLK combat spends from 4CP; ERA/TBC hold 5CP; SoD 4CP needs a SoD
-- family token — filed).
st.rogue_guide.FINISHER_MIN_CP_BY_FAMILY = {
    ERA = 5,
    TBC = 5,
    WRATH = 4,
    FOREVER = 3,
}

-- Rupture refresh window per client (audit T-G3/H9): TBC and FOREVER sims
-- recast when missing (no early refresh — window 0); ERA/WRATH keep 4
-- (no sim refresh row there — status quo, UNCONFIRMED).
st.rogue_guide.RUPTURE_REFRESH_BY_FAMILY = {
    ERA = 4,
    TBC = 0,
    WRATH = 4,
    FOREVER = 0,
}

-- Finisher floor per client (audit T-C1/W-M2/V-G3): the TTD at/below which a
-- fresh finisher is not worth starting, and the CP the dying-target dump
-- needs. ERA any-CP at 8 (the sourced 1CP row + the Era any-CP rule, §1.1);
-- TBC 5CP at 5 s (sim execute is 5CP/remaining<=5s — the shared any-CP rule
-- leaking here was the T-C1 CONFLICT); WRATH 4CP at 4 s (combat Evisc 4+CP at
-- fight<=4s; recast-missing Rupture above it; the 2-4CP duration rows are
-- UNCONFIRMED — filed); FOREVER 3CP at 6 s (sim 3CP fight-end Evisc <=6s).
st.rogue_guide.RUPTURE_MIN_TTD_BY_FAMILY = {
    ERA = 8,
    TBC = 5,
    WRATH = 4,
    FOREVER = 6,
}
st.rogue_guide.DUMP_MIN_CP_BY_FAMILY = {
    ERA = 1,
    TBC = 5,
    WRATH = 4,
    FOREVER = 3,
}

-- Rupture duration per CP as DATA (audit W-M2 — sim-sourced rows only):
-- wotlk rupture.go ships RuptureTicks = 3+CP (+2 Glyph of Rupture) at 2 s
-- ticks, i.e. 1CP 8 s … 5CP 16 s (20 s glyphed). Only the 1CP 8 s and 5CP
-- 16 s endpoint rows are sim-quoted durations, so only those two ship;
-- [2]/[3]/[4] stay absent (UNCONFIRMED — never interpolated, never
-- guessed). Glyph +2 ticks, the Forever fight-end exclusion and CttC
-- interplay are filed (no sim rule consumes this table yet; the flat
-- RUPTURE_MIN_TTD_* floors above still govern every verdict).
st.rogue_guide.RUPTURE_DURATION_BY_CP = { [1] = 8, [5] = 16 }

-- SnD upkeep per client (audit F0/H1): refresh window + min CP. TBC casts
-- only behind its 10 s minimum, which excludes 1CP (9 s < 10 s) — min CP 2.
-- Per-CP durations [9,12,15,18,21] s for CP 1-5 (classic/TBC sim-exact;
-- WotLK glyph/ImpSnD rows, Forever 1CP-clip and SoD CttC filed). SoD upkeep
-- casts at 4+CP with remains<=1s (S-G1, sim P5_Saber/mutilate) — reached
-- only as ERA + sod_envenom (the SOD rows below); CttC interplay filed.
st.rogue_guide.SND_REFRESH_BY_FAMILY = {
    ERA = 3,
    TBC = 0,
    WRATH = 1,
    FOREVER = 0,
    SOD = 1,
}
st.rogue_guide.SND_MIN_CP_BY_FAMILY = {
    ERA = 1,
    TBC = 2,
    WRATH = 1,
    FOREVER = 1,
    SOD = 4,
}
st.rogue_guide.SND_DURATION_BY_CP = { [1] = 9, [2] = 12, [3] = 15, [4] = 18, [5] = 21 }
st.rogue_guide.SND_MIN_CP_DEFAULT = 1

-- Hunger for Blood upkeep (Wrath sin; audit W-G1, the class-feature audit's
-- R-19): the wowsims wotlk APL refreshes the buff when its aura has <= 1 s
-- left (ui/rogue/apls/mutilate.apl.json: auraRemainingTime(51662) <= 1s ->
-- cast 51662 - fetched 2026-10-19). The same "refresh at the tail" shape as
-- Slice and Dice, and the same rule order (SnD first, then Hunger for Blood).
-- WRATH only: the sim source is the wowsims wotlk repo, so no other family
-- prompts. The spell id is sim-side evidence only - the provider resolves the
-- spell through the client's own spell data by its English name and never
-- ships an id (the remembered-id rule).
st.rogue_guide.HFB_FAMILIES = {
    WRATH = true,
}
st.rogue_guide.HFB_REFRESH_BY_FAMILY = {
    WRATH = 1,
}
st.rogue_guide.HFB_REFRESH_DEFAULT = 1

-- EA-duty refresh window per client (audit H4): ERA 3 s (E-G4 MATCH), TBC
-- imminent 6 s (T-G2), FOREVER lockout 16 s (V-G2), WRATH unsourced — keeps 3.
-- The TBC 15 s minimum (EA_MINIMUM_BY_FAMILY), the TBC wait/release (rule 1a)
-- and the Forever finisher lockout (EA_LOCKOUT_FAMILIES) ship below (H6),
-- all behind the same ea_duty flag.
st.rogue_guide.EA_REFRESH_BY_FAMILY = {
    ERA = 3,
    TBC = 6,
    WRATH = 3,
    FOREVER = 16,
}

-- EA-duty minimum per client (audit H6, sim-literal): TBC 15 s non-Shiv (the
-- sim's "Minimum EA Time"; the Shiv-context 4 s needs the filed Mutilate-known
-- probe, so only the non-Shiv row ships). A family with no row has no minimum
-- concept: the wait/release below never applies there.
st.rogue_guide.EA_MINIMUM_BY_FAMILY = {
    TBC = 15,
}

-- SnD cover for the TBC EA wait (sim-literal): the sim's "Minimum SnD Time"
-- 10 s ("SnD Above Minimum" gates the wait — a short SnD releases into an
-- immediate Expose instead of waiting). The Shiv-context 1 s is filed with
-- the Mutilate probe above.
st.rogue_guide.EA_WAIT_SND_MINIMUM = 10

-- EA-duty finisher lockout per client (audit H6, sim-literal): while on duty
-- with EA low, the Forever sim withholds SnD, Riposte, Rupture, Cold Blood
-- and Eviscerate (every branch incl. the fight-end dump) but keeps Expose,
-- builders, Tea and AR live. Riposte / Cold Blood need slots + design and
-- are filed; the engine suppresses the shipped spender set (snd, dying dump,
-- planned finisher) in evaluate. A family with no row never locks out.
st.rogue_guide.EA_LOCKOUT_FAMILIES = {
    FOREVER = true,
}

-- Thistle-Tea line per client (audit H10): ERA 29 / TBC 30 / FOREVER 15;
-- WRATH keeps 40 (the sim's 50 line is potion, not Tea). SoD drinks at 10,
-- or 40 when the fight ends inside 15 s (S-M1, sim P5_Saber) — the SOD row
-- plus the fight-end data below, reached only as ERA + sod_envenom.
-- Eureka-25 needs the Eureka in-client probe (1259812 CLIENT-UNCONFIRMED) —
-- filed.
st.rogue_guide.TEA_ENERGY_MAX_BY_FAMILY = {
    ERA = 29,
    TBC = 30,
    WRATH = 40,
    FOREVER = 15,
    SOD = 10,
}

-- SoD Tea fight-end exception (S-M1): energy<=40 while ttd<=15 s. Unknown
-- TTD never guesses the exception (stays on the 10 line).
st.rogue_guide.SOD_TEA_FIGHT_END_TTD = 15
st.rogue_guide.SOD_TEA_FIGHT_END_MAX = 40

-- AR energy line per client (audit F3/H11): ERA <59 gated on tick<1 (classic
-- tick-gated AR); TBC <=40; WRATH <=50; FOREVER <=50 with SnD riding.
-- RETAIL has no sim source — nil, never prompts (filed with the retail sim).
st.rogue_guide.AR_ENERGY_MAX_BY_FAMILY = {
    ERA = 59,
    TBC = 40,
    WRATH = 50,
    FOREVER = 50,
}

-- Era sweaty override (audit E-G1): at energy>=79 the sweaty APL fires the
-- builder regardless of swing phase — a spend, never a pool. The 0.5 s window
-- widening needs in-client proof and is filed; only the override ships here.
st.rogue_guide.SWEATY_SPEND_BY_FAMILY = {
    ERA = 79,
}

-- Shiv family gate (audit H7/T-G4): sim support is TBC combat non-Mutilate
-- only, below 5CP, and never WotLK/Forever defaults. ERA is kept ungated
-- (no sim either way, and withholding there under-prompts a real upkeep).
-- The EA-context check (Shiv inside EA windows incl. the 4 s Shiv minimum)
-- needs APL-literal EA-window design — filed.
st.rogue_guide.SHIV_FAMILIES = {
    ERA = true,
    TBC = true,
}

-- TBC Shiv gates (audit T-G4): withhold while Mutilate is known, and at/above
-- 5CP (the sim Shivs below 5CP). Unknown Mutilate (nil) never withholds —
-- an unproven book keeps the upkeep.
st.rogue_guide.SHIV_MUTILATE_GATE_FAMILIES = {
    TBC = true,
}
st.rogue_guide.SHIV_CP_MAX_BY_FAMILY = {
    TBC = 4,
}

-- Envenom rules per client, as DATA (rogue_research §3.5 - NEVER one shared
-- rule; each family owns its table, even where the fields coincide, so a tuning
-- pass cannot silently recouple them):
--   dying_only TBC CONFIRMED (§1.3): only on dying targets (consumes stacks).
--              ERA carries the same shape for combat (dumps Eviscerate); SoD
--              mid-fight Envenom rides the SOD table via the sod_envenom latch.
--   let_expire WotLK-sin CONFIRMED (§1.4): buff active withholds re-apply
--              unless energy would cap waiting.
--   never      Forever beta (§1.5): the beta rotation dumps Eviscerate.
--   chain      Retail-sin CONFIRMED (§1.6): 5+CP chaining while the buff rides.
--   sod_primary SoD sim-CONFIRMED (P5_Saber/mutilate APLs): 4+CP primary dump
--              behind poison stacks, with the 2+CP fight-end exception. Reached
--              only as ERA + sod_envenom == true (the provider's SoD latch);
--              the Vanish→Envenom sequence and CttC ride the same latch as
--              follow-ups.
st.rogue_guide.ENVENOM_RULES = {
    ERA     = { mode = "dying_only", ttd_max = 8, min_cp = 5, min_stacks = 1 },
    TBC     = { mode = "dying_only", ttd_max = 8, min_cp = 5, min_stacks = 1 },
    WRATH   = { mode = "let_expire", min_cp = 4, min_stacks = 5 },
    FOREVER = { mode = "never" },
    RETAIL  = { mode = "chain", min_cp = 5 },
    SOD     = { mode = "sod_primary", ttd_max = 4, min_cp = 4, min_stacks = 1 },
}

-- The builder family gate, as DATA (BS-6, bench/filed_closure_sweep_2026-10-19.md
-- §3 U-04 / §7 BS-6): the candidate builders that are not a builder on every
-- client. Hemorrhage is a TBC/Forever/Era builder - the name is certain
-- ("Hemorrhage") and the ids are web-confirmed by wowhead's own redirect slugs
-- (TBC 26864, Era/Forever 16511; the bench corpus had the two swapped - 26862
-- is Sinister Strike). The class resolves the NAME through the client's own
-- spell data, so a wrong id can never produce a wrong builder. The SoD client
-- (the ERA token with the SoD-only Envenom rune known - the provider's frozen
-- latch) builds with a RUNE, never with Hemorrhage. A candidate with no row
-- here is a builder on every client that knows it (Saber Slash, Mutilate).
st.rogue_guide.BUILDER_GATED_FAMILIES = {
    ["Hemorrhage"] = { ERA = true, TBC = true, FOREVER = true },
}

-- Is this builder candidate a builder on this client? Pure: an ungated
-- candidate is always allowed; a gated candidate needs its family row and must
-- not be the SoD client (the "SOD" token, or the ERA token behind the
-- sod_envenom latch). An unknown family answers false - never a guess.
function st.rogue_guide.builder_candidate_allowed(name, family, sod_envenom)
    if type(name) ~= "string" then
        return false
    end
    local gated = st.rogue_guide.BUILDER_GATED_FAMILIES[name]
    if gated == nil then
        return true
    end
    if type(family) ~= "string" then
        return false
    end
    if family == "SOD" then
        return false
    end
    if family == "ERA" and sod_envenom == true then
        return false
    end
    return gated[family] == true
end

-- Refresh / threshold defaults. SHIV 2 s is the §4 watch-list window;
-- RUPTURE 4 s mirrors the druid rip/rake refresh, EA 3 s the warrior Rend
-- window, TEA 40 the deficit cue - all three NEED IN-CLIENT CONFIRMATION
-- (no rogue source). RUPTURE_MIN_TTD 8 s is the sourced 1CP row
-- (rogue_research §5.2); the per-CP durations ship as
-- RUPTURE_DURATION_BY_CP DATA (1CP 8 s / 5CP 16 s sim-sourced, W-M2;
-- 2-4CP UNCONFIRMED — never interpolated).
st.rogue_guide.RUPTURE_REFRESH_DEFAULT = 4
st.rogue_guide.RUPTURE_MIN_TTD_DEFAULT = 8
st.rogue_guide.FINISHER_MIN_CP_DEFAULT = 5
st.rogue_guide.EA_REFRESH_DEFAULT = 3
st.rogue_guide.SHIV_REFRESH_DEFAULT = 2
st.rogue_guide.TEA_ENERGY_MAX_DEFAULT = 40

-- Time-to-die EMA (rogue-owned; vendored from the druid D4 precedent in
-- druid_energy.lua - same smoothing, same inputs/outputs, behavior-preserving.
-- Each class is self-contained: no cross-class runtime reads on the guide hot
-- path (bench/rogue_client_isolation_2026-10-19.md F1). The velocity feeding
-- the estimator is an exponential moving average of HP/s (verify_bank §4.1 -
-- raw samples spike on crits and DoT ticks), never a raw sample. The EMA
-- weight of the newest sample: 0.25 keeps a ~4-sample horizon.
st.rogue_guide.TTD_EMA_ALPHA = 0.25
-- Minimum seconds between HP samples: the live read is per-frame, and dividing
-- by a near-zero dt would manufacture velocity noise; the throttle gives the
-- EMA a stable dt.
st.rogue_guide.TTD_SAMPLE_SECONDS = 0.25

-- Pure: one EMA step of HP/s. hp / prev_hp are hit points, dt the seconds
-- between the samples, alpha the weight of the newest sample. A heal
-- (hp > prev_hp) contributes zero velocity: healing does not resurrect a
-- time-to-die, and a negative velocity would flip the division below into
-- nonsense. The first sample (a non-number ema) seeds from the raw velocity;
-- every later sample smooths. Anything unreadable (missing/non-number/NaN hp,
-- a non-positive dt) returns nil, which the caller reads as "drop the baseline
-- and re-seed" - a poisoned sample must never linger in the EMA.
function st.rogue_guide.update_hp_velocity(ema, hp, prev_hp, dt, alpha)
    if type(hp) ~= "number" or type(prev_hp) ~= "number"
        or hp ~= hp or prev_hp ~= prev_hp
        or type(dt) ~= "number" or dt <= 0 or dt ~= dt then
        return nil
    end
    local weight = alpha
    if type(weight) ~= "number" or weight <= 0 or weight > 1 or weight ~= weight then
        weight = st.rogue_guide.TTD_EMA_ALPHA
    end
    local velocity = (prev_hp - hp) / dt
    if velocity < 0 then
        velocity = 0
    end
    if type(ema) ~= "number" or ema ~= ema then
        return velocity
    end
    return weight * velocity + (1 - weight) * ema
end

-- Pure: the time-to-die estimate from a smoothed HP/s and the live HP:
-- hp / velocity while the velocity is a positive number (a zero/negative
-- velocity has no finite crossing). Unreadable or NaN inputs read nil - the
-- caller treats that as unknown, never as an estimate.
function st.rogue_guide.get_time_to_die(hp, hp_velocity)
    if type(hp) ~= "number" or type(hp_velocity) ~= "number"
        or hp ~= hp or hp_velocity ~= hp_velocity or hp_velocity <= 0 then
        return nil
    end
    return hp / hp_velocity
end

-- Numeric and usable: the NaN-safe number check every rule below funnels through.
local function is_num(x)
    return type(x) == "number" and x == x
end

-- Pooling band for a family token (nil for RETAIL / unknown: no tick line there,
-- so pool_verdict stays silent instead of guessing).
function st.rogue_guide.band_for(family)
    return st.rogue_guide.POOL_BANDS[family]
end

-- Pool-vs-spend verdict: "spend" (a finisher/builder before the tick that would
-- cap you - the Relentless-Strikes-25 timing, §1.3), "pool" (hold for the tick),
-- nil (no band for this client, or an unusable energy read - never a guess).
-- tick_in unknown degrades to "pool": pooling wastes nothing by itself, while a
-- timed spend without a clock would be a guess.
function st.rogue_guide.pool_verdict(energy, tick_in, band, max_energy)
    if not is_num(energy) then
        return nil
    end
    if type(band) ~= "table" then
        return nil
    end
    if not is_num(band.pre) or not is_num(band.post) then
        return nil
    end
    if not is_num(max_energy) then
        max_energy = st.rogue_guide.MAX_ENERGY_DEFAULT
    end
    if energy >= max_energy then
        return "spend"
    end
    if energy + st.rogue_guide.TICK_ENERGY_DEFAULT > max_energy then
        return "spend"
    end
    if energy >= band.post then
        return "spend"
    end
    if energy >= band.pre then
        if is_num(tick_in) then
            return "spend"
        end
        return "pool"
    end
    return "pool"
end

-- Rupture-vs-Eviscerate decider on a NUMERIC TTD input: "rupture",
-- "eviscerate", or nil (unknown TTD or CP below the planned-finisher line -
-- never a guessed finisher; the dying-target any-CP dump lives in evaluate).
function st.rogue_guide.finisher_for_ttd(cp, ttd, rupture_remains, opts)
    opts = opts or {}
    local min_cp = opts.min_cp
    if not is_num(min_cp) then
        min_cp = st.rogue_guide.FINISHER_MIN_CP_DEFAULT
    end
    local refresh = opts.rupture_refresh
    if not is_num(refresh) then
        refresh = st.rogue_guide.RUPTURE_REFRESH_DEFAULT
    end
    local min_ttd = opts.rupture_min_ttd
    if not is_num(min_ttd) then
        min_ttd = st.rogue_guide.RUPTURE_MIN_TTD_DEFAULT
    end
    if not is_num(cp) or cp < min_cp then
        return nil
    end
    if not is_num(ttd) then
        return nil
    end
    if ttd <= min_ttd then
        return "eviscerate"
    end
    if rupture_remains == nil then
        return "rupture"
    end
    if not is_num(rupture_remains) then
        return nil
    end
    if rupture_remains <= refresh then
        return "rupture"
    end
    return "eviscerate"
end

-- Rupture duration lookup per CP: the sourced row or nil. Unknown-hides —
-- 2-4CP (UNCONFIRMED), out-of-range, nil/NaN CP never guess and never
-- interpolate; the flat RUPTURE_MIN_TTD_* floors still govern every verdict
-- (no sim rule consumes RUPTURE_DURATION_BY_CP yet — W-M2 filed follow-up).
function st.rogue_guide.rupture_duration_for_cp(cp)
    if not is_num(cp) then
        return nil
    end
    local d = st.rogue_guide.RUPTURE_DURATION_BY_CP[cp]
    if not is_num(d) then
        return nil
    end
    return d
end

-- Per-client Envenom verdict: "envenom" or nil. Reads ONLY its family's rule
-- table (unknown family never prompts). args is the caller-owned inputs table;
-- band is the resolved pooling band (for the Wrath cap exception).
function st.rogue_guide.envenom_verdict(family, args, band)
    args = args or {}
    local rule = st.rogue_guide.ENVENOM_RULES[family]
    if type(rule) ~= "table" then
        return nil
    end
    local mode = rule.mode
    if mode == "never" then
        return nil
    end
    local cp = args.cp
    local stacks = args.deadly_stacks
    if mode == "dying_only" then
        local ttd_max = rule.ttd_max
        if not is_num(ttd_max) then
            return nil
        end
        local min_cp = rule.min_cp
        if not is_num(min_cp) then
            return nil
        end
        local min_stacks = rule.min_stacks
        if not is_num(min_stacks) then
            return nil
        end
        if not is_num(cp) or cp < min_cp then
            return nil
        end
        if not is_num(stacks) or stacks < min_stacks then
            return nil
        end
        if not is_num(args.ttd) or args.ttd > ttd_max then
            return nil
        end
        return "envenom"
    end
    if mode == "let_expire" then
        local min_cp = rule.min_cp
        if not is_num(min_cp) then
            return nil
        end
        local min_stacks = rule.min_stacks
        if not is_num(min_stacks) then
            return nil
        end
        if not is_num(cp) or cp < min_cp then
            return nil
        end
        if not is_num(stacks) or stacks < min_stacks then
            return nil
        end
        local buff = args.envenom_buff_remains
        if is_num(buff) and buff > 0 then
            -- Buff rides: let it expire - unless energy would cap waiting.
            local energy = args.energy_now
            if type(band) == "table" and is_num(band.post)
                and is_num(energy) and energy >= band.post then
                return "envenom"
            end
            return nil
        end
        if buff ~= nil and not is_num(buff) then
            return nil
        end
        return "envenom"
    end
    if mode == "chain" then
        local min_cp = rule.min_cp
        if not is_num(min_cp) then
            return nil
        end
        if not is_num(cp) or cp < min_cp then
            return nil
        end
        if is_num(stacks) and stacks <= 0 then
            return nil
        end
        return "envenom"
    end
    if mode == "sod_primary" then
        -- SoD primary (sim-CONFIRMED): 4+CP primary dump behind poison stacks,
        -- with the 2+CP fight-end exception. Reached only as ERA +
        -- sod_envenom == true (evaluate maps the family; direct callers pass
        -- "SOD" themselves).
        local ttd_max = rule.ttd_max
        if not is_num(ttd_max) then
            return nil
        end
        local min_cp = rule.min_cp
        if not is_num(min_cp) then
            return nil
        end
        local min_stacks = rule.min_stacks
        if not is_num(min_stacks) then
            return nil
        end
        local punch = is_num(cp) and cp >= min_cp
        if not punch and is_num(cp) and cp >= 2
            and is_num(args.ttd) and args.ttd <= ttd_max then
            punch = true
        end
        if not punch then
            return nil
        end
        if not is_num(stacks) or stacks < min_stacks then
            return nil
        end
        return "envenom"
    end
    return nil
end

-- Shiv upkeep verdict: "shiv" when Shiv is usable and the Deadly clock proves a
-- falloff inside the window; nil otherwise (a nil clock never prompts - H4).
-- deadly_stacks rides the call shape for the provider but is intentionally
-- unread: a running falloff clock already proves stacks exist.
function st.rogue_guide.shiv_verdict(deadly_stacks, deadly_remaining, shiv_ready, window)
    if shiv_ready ~= true then
        return nil
    end
    if not is_num(window) then
        window = st.rogue_guide.SHIV_REFRESH_DEFAULT
    end
    if deadly_remaining == nil then
        return nil
    end
    if not is_num(deadly_remaining) then
        return nil
    end
    if deadly_remaining <= window then
        return "shiv"
    end
    return nil
end

-- Shiv family gate (audit T-G4): true when the family prompts Shiv at all and
-- the TBC Mutilate/CP gates pass. ERA carries no rows (ungated); an unknown
-- Mutilate (nil) never withholds; an unknown CP hides (never a guessed Shiv).
function st.rogue_guide.shiv_family_ok(family, args)
    args = args or {}
    if st.rogue_guide.SHIV_FAMILIES[family] ~= true then
        return nil
    end
    if st.rogue_guide.SHIV_MUTILATE_GATE_FAMILIES[family] == true
        and args.mutilate_known == true then
        return nil
    end
    local cp_max = st.rogue_guide.SHIV_CP_MAX_BY_FAMILY[family]
    if is_num(cp_max) then
        local cp = args.cp
        if not is_num(cp) or cp > cp_max then
            return nil
        end
    end
    return true
end

-- EA-duty refresh verdict: "expose" while on duty and the armor clock is missing
-- (nil prompts, like the druid rip/rake nil rule) or inside the window.
function st.rogue_guide.ea_verdict(ea_duty, ea_remains, window)
    if ea_duty ~= true then
        return nil
    end
    if not is_num(window) then
        window = st.rogue_guide.EA_REFRESH_DEFAULT
    end
    if ea_remains == nil then
        return "expose"
    end
    if not is_num(ea_remains) then
        return nil
    end
    if ea_remains <= window then
        return "expose"
    end
    return nil
end

-- EA-duty wait verdict (H6, TBC sim-literal): "expose" | "wait" | nil. Reads
-- ONLY its family's minimum row (nil row = no wait concept, never a guess).
-- At 5CP (the sim's group entry is OpEq 5; CP caps at 5) with duty on and EA
-- known but below the minimum and above the imminent window:
--   * SnD short of EA_WAIT_SND_MINIMUM (or missing) releases into "expose"
--     now (the sim skips the wait when SnD cannot cover it and casts);
--   * energy at/above the pool post line releases into "expose" now (the
--     sim's waitUntil pool disjunct casts on release);
--   * SnD healthy + energy below the pool line reads "wait" (the sim's
--     waitUntil hold — neither a builder nor a finisher).
-- A missing EA belongs to rule 1 (nil prompts); NaN anywhere, no duty, no
-- minimum row, no band line, or off-window EA all read nil (unknown-hides).
function st.rogue_guide.ea_wait_verdict(family, args, band, ea_window)
    args = args or {}
    if args.ea_duty ~= true then
        return nil
    end
    local minimum = st.rogue_guide.EA_MINIMUM_BY_FAMILY[family]
    if not is_num(minimum) then
        return nil
    end
    local remains = args.ea_remains
    if remains == nil then
        return nil
    end
    if not is_num(remains) then
        return nil
    end
    if remains >= minimum then
        return nil
    end
    if not is_num(ea_window) then
        ea_window = st.rogue_guide.EA_REFRESH_BY_FAMILY[family]
    end
    if not is_num(ea_window) then
        ea_window = st.rogue_guide.EA_REFRESH_DEFAULT
    end
    if remains <= ea_window then
        return nil
    end
    local cp = args.cp
    if not is_num(cp) or cp < 5 then
        return nil
    end
    local snd_remains = args.snd_remains
    if snd_remains == nil then
        if args.snd_usable ~= true then
            -- SnD state unreadable (the spell itself is unresolved): the wait
            -- machinery stays out and the normal rules run (unknown-hides).
            return nil
        end
        -- Genuinely missing SnD cannot cover the wait: cast now (the sim
        -- skips the wait when SnD is not above minimum).
        return "expose"
    end
    if not is_num(snd_remains) then
        return nil
    end
    local snd_healthy = snd_remains >= st.rogue_guide.EA_WAIT_SND_MINIMUM
    if not snd_healthy then
        return "expose"
    end
    local energy = args.energy_now
    if not is_num(energy) then
        return nil
    end
    if type(band) ~= "table" or not is_num(band.post) then
        return nil
    end
    if energy >= band.post then
        return "expose"
    end
    return "wait"
end

-- EA-duty finisher lockout (H6, Forever sim-literal): true while on duty with
-- EA missing or inside the window (the sim's "Expose - Low Duration"). While
-- true, evaluate withholds the shipped spender set (snd, dying dump, planned
-- finisher); Expose, builders, Tea and AR stay live exactly like the sim.
-- Off duty, off family, or a NaN clock reads false (unknown-hides).
function st.rogue_guide.ea_lockout_active(family, ea_duty, ea_remains, ea_window)
    if st.rogue_guide.EA_LOCKOUT_FAMILIES[family] ~= true then
        return false
    end
    if ea_duty ~= true then
        return false
    end
    if not is_num(ea_window) then
        ea_window = st.rogue_guide.EA_REFRESH_BY_FAMILY[family]
    end
    if not is_num(ea_window) then
        ea_window = st.rogue_guide.EA_REFRESH_DEFAULT
    end
    if ea_remains == nil then
        return true
    end
    if not is_num(ea_remains) then
        return false
    end
    return ea_remains <= ea_window
end

-- Slice-and-Dice upkeep verdict (audit F0/H1): "snd" when the spell is proven
-- resolved and CP sits at/above the family minimum, and the buff is missing
-- (nil — an upkeep gap, like the druid rip/rake nil rule) or inside the
-- family refresh window. A non-number clock hides (H4); families without a
-- refresh row (unknown/RETAIL) never prompt.
function st.rogue_guide.snd_verdict(family, args)
    args = args or {}
    if args.snd_usable ~= true then
        return nil
    end
    local min_cp = args.snd_min_cp
    if not is_num(min_cp) then
        min_cp = st.rogue_guide.SND_MIN_CP_BY_FAMILY[family]
    end
    if not is_num(min_cp) then
        min_cp = st.rogue_guide.SND_MIN_CP_DEFAULT
    end
    if not is_num(args.cp) or args.cp < min_cp then
        return nil
    end
    local window = args.snd_refresh
    if not is_num(window) then
        window = st.rogue_guide.SND_REFRESH_BY_FAMILY[family]
    end
    if not is_num(window) then
        return nil
    end
    local remains = args.snd_remains
    if remains == nil then
        return "snd"
    end
    if not is_num(remains) then
        return nil
    end
    if remains <= window then
        return "snd"
    end
    return nil
end

-- Hunger-for-Blood upkeep verdict (Wrath sin; audit W-G1, the class-feature
-- audit's R-19): "hfb" when the spell is proven resolved AND known (the
-- provider owns both reads - the spell resolves through the client's own data
-- by its English name, the talent gate is a strict true), and the buff is
-- missing (nil - an upkeep gap, the Slice-and-Dice nil rule) or inside the
-- family's refresh window (the wowsims wotlk APL refreshes it at <= 1 s
-- remaining: ui/rogue/apls/mutilate.apl.json). A non-number clock hides (H4);
-- a family without a row (every family but WRATH) never prompts.
function st.rogue_guide.hfb_verdict(family, args)
    args = args or {}
    if st.rogue_guide.HFB_FAMILIES[family] ~= true then
        return nil
    end
    if args.hfb_usable ~= true then
        return nil
    end
    local window = args.hfb_refresh
    if not is_num(window) then
        window = st.rogue_guide.HFB_REFRESH_BY_FAMILY[family]
    end
    if not is_num(window) then
        window = st.rogue_guide.HFB_REFRESH_DEFAULT
    end
    local remains = args.hfb_remains
    if remains == nil then
        return "hfb"
    end
    if not is_num(remains) then
        return nil
    end
    if remains <= window then
        return "hfb"
    end
    return nil
end

-- Adrenaline Rush verdict (audit F3/H11): "ar" when the cooldown is proven
-- ready and energy sits at/below the family line — ERA additionally needs a
-- tick inside 1 s (classic tick-gated AR), FOREVER needs SnD riding.
-- Families without an energy row (unknown/RETAIL) never prompt (filed with
-- the retail sim).
function st.rogue_guide.ar_verdict(family, args)
    args = args or {}
    if args.ar_ready ~= true then
        return nil
    end
    local max = st.rogue_guide.AR_ENERGY_MAX_BY_FAMILY[family]
    if not is_num(max) then
        return nil
    end
    local energy = args.energy_now
    if not is_num(energy) then
        return nil
    end
    if family == "ERA" then
        if energy >= max then
            return nil
        end
        if not is_num(args.energy_tick_in) or args.energy_tick_in >= 1 then
            return nil
        end
        return "ar"
    end
    if energy > max then
        return nil
    end
    if family == "FOREVER" then
        if not is_num(args.snd_remains) or args.snd_remains <= 0 then
            return nil
        end
    end
    return "ar"
end

-- Blade Flurry family gate (audit F3/H11): the TBC and Forever sims press BF
-- behind upkeep; ERA/WRATH keep the same shape (BF exists there, no sim
-- either way, under-prompts nowhere). RETAIL/unknown never prompt (filed).
st.rogue_guide.BF_FAMILIES = {
    ERA = true,
    TBC = true,
    WRATH = true,
    FOREVER = true,
}

-- Blade Flurry verdict: "bf" when the cooldown is proven ready with SnD
-- riding — and, while on EA duty, with EA healthy (the TBC "with SnD+EA
-- active" line; the EA rule itself fires first when EA is actually due).
function st.rogue_guide.bf_verdict(family, args)
    args = args or {}
    if args.bf_ready ~= true then
        return nil
    end
    if st.rogue_guide.BF_FAMILIES[family] ~= true then
        return nil
    end
    if not is_num(args.snd_remains) or args.snd_remains <= 0 then
        return nil
    end
    if args.ea_duty == true then
        if not is_num(args.ea_remains) or args.ea_remains <= 0 then
            return nil
        end
    end
    return "bf"
end

-- Cold Blood family gate (audit F3/V-G5): the TBC sim presses Cold Blood
-- with SnD riding; the Forever sim at 5CP. RETAIL/unknown never prompt
-- (no retail sim source — filed). Wrath Tricks/Killing Spree, HfB/Overkill
-- and Vanish lines need slots + APL-literal design — filed.
st.rogue_guide.CB_FAMILIES = {
    TBC = true,
    FOREVER = true,
}

-- Cold Blood CP line per client (audit V-G5: Forever presses at 5CP). TBC
-- carries no CP row (the sim gates on SnD only).
st.rogue_guide.CB_MIN_CP_BY_FAMILY = {
    FOREVER = 5,
}

-- Cold Blood verdict (slot-less like ar/bf): "coldblood" when the cooldown is
-- proven ready with SnD riding. The Forever EA-lockout suppression rides in
-- evaluate (open_rules: the lockout suppresses Cold Blood); AR-buff
-- sequencing needs APL-literal order — filed.
function st.rogue_guide.cb_verdict(family, args)
    args = args or {}
    if st.rogue_guide.CB_FAMILIES[family] ~= true then
        return nil
    end
    if args.coldblood_ready ~= true then
        return nil
    end
    if not is_num(args.snd_remains) or args.snd_remains <= 0 then
        return nil
    end
    local min_cp = st.rogue_guide.CB_MIN_CP_BY_FAMILY[family]
    if is_num(min_cp) then
        if not is_num(args.cp) or args.cp < min_cp then
            return nil
        end
    end
    return "coldblood"
end

-- Thistle-Tea deficit cue: "tea" when the item is usable and energy proves low.
function st.rogue_guide.tea_verdict(tea_ready, energy_now, energy_max)
    if tea_ready ~= true then
        return nil
    end
    if not is_num(energy_now) then
        return nil
    end
    if not is_num(energy_max) then
        energy_max = st.rogue_guide.TEA_ENERGY_MAX_DEFAULT
    end
    if energy_now <= energy_max then
        return "tea"
    end
    return nil
end

--=========================================================================================
-- The APL utility layer: the arms for the rotation table's utility rows
--=========================================================================================
-- bench/rotation_gap_vs_apl_2026-10-20.md §3 (the rogue) is the INPUT; every
-- condition below was re-read from the APL files themselves on 2026-10-20
-- (wowsims/{sod,forever,wotlk}/master, every group expanded inline) and the
-- ids were named against the sims' own spell data. The class's rotation TABLE
-- (classes/rogue.lua: ST.ROGUE.practice_rotation) carries the citations; this
-- half is the DECISION.
--
-- Every arm here obeys the house rule: an unreadable state HIDES. A readiness
-- flag that is not exactly true never prompts, and a state the client cannot
-- answer is nil, never false.

-- The Vanish family gate (the APL's stealth opener rows): the SoD build's
-- Vanish (1856 rank 1), the WotLK build's Vanish (26889) and the Forever
-- client's Vanish rank 2 (1857). The Era and TBC APLs carry NO Vanish row, so
-- no Era/TBC family is in the gate.
st.rogue_guide.VANISH_FAMILIES = {
    SOD = true,
    WRATH = true,
    FOREVER = true,
}

-- The Vanish verdict: "vanish" when the APL's own condition holds.
--   SOD    (sod ui/rogue/apls/P5_Saber.apl.json i=7): NOT(auraIsActive(425096))
--          AND cp == 5 AND spellCanCast(399963) - the Vanish -> Envenom opener.
--   WRATH  (wotlk ui/rogue/apls/mutilate.apl.json i=4): NOT(auraIsActive(58426))
--          - the Vanish pops when the player is not already vanished.
--   FOREVER(forever ui/specs/rogue/dps/apls/default.apl.json i=3): the Garrote
--          dot down, the energy at/above the Garrote's cost, cp < 5 and the
--          Slice and Dice not about to fall. That row rides the FOREVER
--          OPENER CLUSTER (forever_opener_verdict), which owns the APL's row
--          order - so this arm stays silent for that family.
function st.rogue_guide.vanish_verdict(family, args)
    args = args or {}
    if st.rogue_guide.VANISH_FAMILIES[family] ~= true then
        return nil
    end
    if args.vanish_ready ~= true then
        return nil
    end
    if family == "SOD" then
        -- The Master of Subtlety rune's aura must be DOWN (the APL's NOT).
        if args.master_of_subtlety_active == true then
            return nil
        end
        if not is_num(args.cp) or args.cp ~= 5 then
            return nil
        end
        if args.envenom_ready ~= true then
            return nil
        end
        return "vanish"
    end
    if family == "WRATH" then
        -- The 58426 aura must be DOWN (the APL's NOT).
        if args.vanished_active == true then
            return nil
        end
        return "vanish"
    end
    -- FOREVER: the row lives in the opener cluster (the APL's own order).
    return nil
end

-- The Forever opener cluster: the Forever APL's rows i=1 (Ambush), i=2
-- (Garrote), i=3 (Vanish) and i=5 (Preparation). They sit ABOVE the Forever
-- APL's Slice and Dice upkeep (i=18), so the cluster rides above the 1b rule.
--
-- The APL's own value variables are CONSTANTS on this build ("Use Stealth/Vanish
-- for Damage" = true, "Use Ambush Opener" = false, "Use Backstab" = true), so
-- every condition below is a plain client read:
--   i=1 Ambush      (auraIsActive(462707) OR false) AND cp < 5
--   i=2 Garrote     true AND cp < 5 AND NOT(dotIsActive(11290))
--   i=3 Vanish      NOT(dotIsActive(11290)) AND currentEnergy >=
--                   spellCurrentCost(11290) AND cp < 5 AND
--                   NOT(SnD Fall Imminent)
--   i=5 Preparation NOT(spellIsReady(1857))
st.rogue_guide.FOREVER_OPENER_FAMILIES = {
    FOREVER = true,
}

-- The Slice and Dice "fall imminent" line (the APL's own variable: the SnD
-- aura's remaining time <= 2 s). A missing SnD reads 0 s in the sim - so the
-- APL's NOT(...) withholds the row when the buff is down - and an unreadable
-- clock hides the row entirely (unknown-hides).
st.rogue_guide.FOREVER_SND_FALL_IMMINENT = 2

-- The Forever opener cluster's verdict: the first row whose APL condition
-- holds, in the APL's own order. nil when no row is due (or when the family is
-- not Forever).
function st.rogue_guide.forever_opener_verdict(family, args)
    args = args or {}
    if st.rogue_guide.FOREVER_OPENER_FAMILIES[family] ~= true then
        return nil
    end
    local cp = args.cp
    if not is_num(cp) then
        return nil
    end
    if args.ambush_ready == true and args.ambush_cue_active == true and cp < 5 then
        return "ambush"
    end
    if args.garrote_ready == true and args.garrote_dot_active ~= true and cp < 5 then
        return "garrote"
    end
    -- The Vanish row (i=3): the Garrote dot down, the energy at/above the
    -- Garrote's CURRENT cost, cp < 5 and the Slice and Dice not about to
    -- fall. Every leg needs its own read: an unreadable energy cost or an
    -- unreadable SnD clock hides the row (unknown-hides).
    if args.vanish_ready == true and args.garrote_dot_active ~= true and cp < 5 then
        local cost = args.garrote_energy_cost
        if is_num(cost) and is_num(args.energy_now) and args.energy_now >= cost then
            local snd_remains = args.snd_remains
            if is_num(snd_remains) and snd_remains > st.rogue_guide.FOREVER_SND_FALL_IMMINENT then
                return "vanish"
            end
        end
    end
    if args.preparation_ready == true and args.vanish_cd_remaining ~= nil
        and args.vanish_cd_remaining > 0 then
        -- Preparation (i=5): cast while Vanish is NOT ready.
        return "preparation"
    end
    return nil
end

-- The Premeditation verdict (the Forever APL's i=17): cast while cp <= 3.
-- The Forever client's 14183 is Premeditation - the same spell the Era, SoD and
-- WotLK clients know as 14183 (the gap analysis read it as Shadowstep; the
-- sims' own spell data names it Premeditation on every client).
st.rogue_guide.PREMEDITATION_FAMILIES = {
    FOREVER = true,
}

function st.rogue_guide.premeditation_verdict(family, args)
    args = args or {}
    if st.rogue_guide.PREMEDITATION_FAMILIES[family] ~= true then
        return nil
    end
    if args.premeditation_ready ~= true then
        return nil
    end
    if not is_num(args.cp) or args.cp > 3 then
        return nil
    end
    return "premeditation"
end

-- The Venom verdict (the Forever APL's i=19): the 1310703 buff is DOWN and
-- cp >= 3. The APL casts it (i=19) before its Rupture row (i=20), so the arm
-- rides above the planned finisher.
st.rogue_guide.VENOM_FAMILIES = {
    FOREVER = true,
}

function st.rogue_guide.venom_verdict(family, args)
    args = args or {}
    if st.rogue_guide.VENOM_FAMILIES[family] ~= true then
        return nil
    end
    if args.venom_ready ~= true then
        return nil
    end
    if args.venom_buff_active == true then
        return nil
    end
    if not is_num(args.cp) or args.cp < 3 then
        return nil
    end
    return "venom"
end

-- The Poisoned Knife verdict (the SoD APL's i=5): the target carries 4+ Deadly
-- Poison stacks AND cp < 5 AND energy <= 80. The SoD-only row - the Era, TBC,
-- Wrath and Forever APLs carry no Poisoned Knife row.
st.rogue_guide.POISONED_KNIFE_FAMILIES = {
    SOD = true,
}

function st.rogue_guide.poisoned_knife_verdict(family, args)
    args = args or {}
    if st.rogue_guide.POISONED_KNIFE_FAMILIES[family] ~= true then
        return nil
    end
    if args.poisoned_knife_ready ~= true then
        return nil
    end
    if not is_num(args.deadly_stacks) or args.deadly_stacks < 4 then
        return nil
    end
    if not is_num(args.cp) or args.cp >= 5 then
        return nil
    end
    if not is_num(args.energy_now) or args.energy_now > 80 then
        return nil
    end
    return "poisoned_knife"
end

-- The Tricks of the Trade verdict (the WotLK APL's i=13 in the combat list and
-- i=8 in the mutilate list): energy <= 50.
st.rogue_guide.TRICKS_FAMILIES = {
    WRATH = true,
}

function st.rogue_guide.tricks_verdict(family, args)
    args = args or {}
    if st.rogue_guide.TRICKS_FAMILIES[family] ~= true then
        return nil
    end
    if args.tricks_ready ~= true then
        return nil
    end
    if not is_num(args.energy_now) or args.energy_now > 50 then
        return nil
    end
    return "tricks_of_the_trade"
end

-- The Killing Spree verdict (the WotLK combat APL's i=14): energy <= 50.
st.rogue_guide.KILLING_SPREE_FAMILIES = {
    WRATH = true,
}

function st.rogue_guide.killing_spree_verdict(family, args)
    args = args or {}
    if st.rogue_guide.KILLING_SPREE_FAMILIES[family] ~= true then
        return nil
    end
    if args.killing_spree_ready ~= true then
        return nil
    end
    if not is_num(args.energy_now) or args.energy_now > 50 then
        return nil
    end
    return "killing_spree"
end

-- The Forever paired pops (the APL's i=11 Blood Fury and i=12 Elune's Light):
-- the Adrenaline Rush's time to ready is at/above 1.9 m - the sim pairs the
-- racial with the AR so the two land together.
st.rogue_guide.FOREVER_PAIRED_POP_FAMILIES = {
    FOREVER = true,
}

-- The Adrenaline Rush gate the paired pops share: the AR's remaining cooldown
-- must be at/above 1.9 m (114 s). nil when the AR's cooldown is unreadable -
-- the pops hide rather than guess.
st.rogue_guide.FOREVER_PAIRED_POP_AR_CD = 114

function st.rogue_guide.forever_paired_pop_verdict(family, args, ready_key, action)
    args = args or {}
    if st.rogue_guide.FOREVER_PAIRED_POP_FAMILIES[family] ~= true then
        return nil
    end
    if args[ready_key] ~= true then
        return nil
    end
    if not is_num(args.ar_cd_remaining) then
        return nil
    end
    if args.ar_cd_remaining < st.rogue_guide.FOREVER_PAIRED_POP_AR_CD then
        return nil
    end
    return action
end

-- The Gnome Eureka! verdict (the Forever APL's i=13): the APL's own "Gnome
-- Eureka - Should Cast" variable, expanded:
--   spellIsKnown(1259812) AND spellIsReady(1259812) AND (
--     NOT spellIsKnown(13750)                    -- the AR is not known at all
--     OR auraIsActive(13750)                      -- the AR's buff rides
--     OR spellTimeToReady(13750) > spellFullCooldown(1259812)
--     OR remainingTime < spellTimeToReady(13750) ) -- the fight is about to end
-- The first two legs are the provider's readiness read (known + usable + off
-- cooldown) and the third is the AR's time to ready against the racial's own
-- full cooldown. The FOURTH leg (the fight's remaining time) has no read in
-- the shipped tree, so the row can only fire off the three proven ones - it
-- under-prompts rather than guess (no advice beats wrong advice).
st.rogue_guide.GNOME_EUREKA_FAMILIES = {
    FOREVER = true,
}

function st.rogue_guide.gnome_eureka_verdict(family, args)
    args = args or {}
    if st.rogue_guide.GNOME_EUREKA_FAMILIES[family] ~= true then
        return nil
    end
    if args.gnome_eureka_ready ~= true then
        return nil
    end
    -- NOT spellIsKnown(13750): the Adrenaline Rush is not known at all.
    if args.ar_known == false then
        return "gnome_eureka"
    end
    -- auraIsActive(13750): the Adrenaline Rush's buff rides.
    if args.ar_buff_active == true then
        return "gnome_eureka"
    end
    -- spellTimeToReady(13750) > spellFullCooldown(1259812): the AR takes
    -- longer to come back than the racial does, so the racial goes now.
    local ar_cd = args.ar_cd_remaining
    local full_cd = args.gnome_eureka_full_cd
    if is_num(ar_cd) and is_num(full_cd) and ar_cd > full_cd then
        return "gnome_eureka"
    end
    return nil
end

-- Multi-CD stacked glow (R3): true when two or more offensive cooldowns ride
-- at once (rogue_deep §2.7: Sno buff tracker "highlighted with a yellow glow
-- ... when using multiple CDs at once", CONFIRMED as listing text
-- https://www.tbcguides.gg/rogue-ui/). Pure count predicate so the provider
-- (classes/rogue.lua count_stacked_offensives) stays testable here; the
-- counted set (AR + BF) is UNCONFIRMED beyond Sno's list (competitor_gaps R3).
function st.rogue_guide.stacked_glow(active_count)
    if not is_num(active_count) then
        return nil
    end
    if active_count >= 2 then
        return true
    end
    return nil
end

-- Unknown-input contract (H4/M6): the core reads are unusable (or the provider's
-- explicit M6 bit is set - e.g. the secret regime makes the auras unreadable), so no
-- rule below may emit a verdict. The provider owns the inputs_unknown bit (M6 pattern);
-- this is the pure half the provider calls.
function st.rogue_guide.is_unknown(inputs)
    if type(inputs) ~= "table" then
        return true
    end
    if inputs.inputs_unknown == true then
        return true
    end
    return not is_num(inputs.energy_now) or not is_num(inputs.cp)
end

-- Pure: one engine tick. Reads `inputs`, writes the frozen display fields into
-- the caller-owned `out` table and returns it. See the module header for the
-- rule matrix.
function st.rogue_guide.evaluate(inputs, out)
    inputs = inputs or {}
    if type(out) ~= "table" then
        out = {}
    end

    local action
    local hold = false
    local hold_text
    local unknown = st.rogue_guide.is_unknown(inputs)

    if not unknown then
        local family = inputs.family
        local band = st.rogue_guide.POOL_BANDS[family]
        if type(inputs.pool_pre) == "number" and type(inputs.pool_post) == "number" then
            band = { pre = inputs.pool_pre, post = inputs.pool_post }
        end

        -- SoD mapping (sod_detect ONE mechanism): ERA + the provider's
        -- sod_envenom latch reads the SOD tables (Envenom primary, SnD 4CP/1s,
        -- Tea 10 + fight-end 40). The planned-finisher spine and dump floors
        -- keep the ERA rows (no sim row for a stack-less SoD 5CP — filed).
        local env_family = family
        if env_family == "ERA" and inputs.sod_envenom == true then
            env_family = "SOD"
        end

        local ea_window = inputs.ea_refresh
        if not is_num(ea_window) then
            ea_window = st.rogue_guide.EA_REFRESH_BY_FAMILY[family]
        end
        if not is_num(ea_window) then
            ea_window = st.rogue_guide.EA_REFRESH_DEFAULT
        end
        local shiv_window = inputs.shiv_refresh
        if not is_num(shiv_window) then
            shiv_window = st.rogue_guide.SHIV_REFRESH_DEFAULT
        end
        local tea_max = inputs.tea_energy_max
        if not is_num(tea_max) then
            tea_max = st.rogue_guide.TEA_ENERGY_MAX_BY_FAMILY[env_family]
        end
        if not is_num(tea_max) then
            tea_max = st.rogue_guide.TEA_ENERGY_MAX_DEFAULT
        end
        if env_family == "SOD" and not is_num(inputs.tea_energy_max)
            and is_num(inputs.ttd)
            and inputs.ttd <= st.rogue_guide.SOD_TEA_FIGHT_END_TTD then
            -- SoD fight-end exception (S-M1): energy<=40 while ttd<=15 s.
            -- An explicit tuning line still wins; unknown TTD stays on 10.
            tea_max = st.rogue_guide.SOD_TEA_FIGHT_END_MAX
        end
        local min_cp = inputs.finisher_min_cp
        if not is_num(min_cp) then
            min_cp = st.rogue_guide.FINISHER_MIN_CP_BY_FAMILY[family]
        end
        if not is_num(min_cp) then
            min_cp = st.rogue_guide.FINISHER_MIN_CP_DEFAULT
        end
        local min_ttd = inputs.rupture_min_ttd
        if not is_num(min_ttd) then
            min_ttd = st.rogue_guide.RUPTURE_MIN_TTD_BY_FAMILY[family]
        end
        if not is_num(min_ttd) then
            min_ttd = st.rogue_guide.RUPTURE_MIN_TTD_DEFAULT
        end
        local dump_cp = st.rogue_guide.DUMP_MIN_CP_BY_FAMILY[family]
        if not is_num(dump_cp) then
            dump_cp = 1
        end
        local rupture_refresh = inputs.rupture_refresh
        if not is_num(rupture_refresh) then
            rupture_refresh = st.rogue_guide.RUPTURE_REFRESH_BY_FAMILY[family]
        end
        if not is_num(rupture_refresh) then
            rupture_refresh = st.rogue_guide.RUPTURE_REFRESH_DEFAULT
        end
        local max_energy = inputs.max_energy
        if not is_num(max_energy) then
            max_energy = st.rogue_guide.MAX_ENERGY_DEFAULT
        end
        local finisher_mode = st.rogue_guide.FINISHER_MODES[family]
        if finisher_mode ~= "eviscerate" then
            finisher_mode = "rupture"
        end

        local energy = inputs.energy_now
        local cp = inputs.cp
        local ttd = inputs.ttd

        -- H6: the TBC wait/release (rule 1a) and the Forever finisher lockout.
        local ea_wait = st.rogue_guide.ea_wait_verdict(family, inputs, band, ea_window)
        local ea_wait_hold = ea_wait == "wait"
        local ea_lockout = st.rogue_guide.ea_lockout_active(family, inputs.ea_duty,
            inputs.ea_remains, ea_window)
        -- The Forever opener cluster (1x): computed once, above the chain.
        local forever_opener = nil
        if not ea_wait_hold then
            forever_opener = st.rogue_guide.forever_opener_verdict(family, inputs)
        end

        if st.rogue_guide.ea_verdict(inputs.ea_duty, inputs.ea_remains, ea_window) ~= nil
            and not (ea_lockout and is_num(cp) and cp < 5) then
            -- 1. EA-duty refresh outranks every spender. On Forever the sim's
            -- Maintain Expose casts at 5CP only (Should-Cast-Check); below 5CP
            -- the low-EA bar runs the lockout instead (builders/AR/Tea/BF live).
            action = "expose"
        elseif ea_wait == "expose" then
            -- 1a. TBC EA-duty release: SnD too short to cover the wait, or
            -- energy already at the pool line - cast Expose now (the sim's
            -- immediate cast on either waitUntil disjunct; sits above SnD
            -- like the sim group does).
            action = "expose"
        elseif not ea_wait_hold
            and forever_opener ~= nil then
            -- 1x. The Forever opener cluster (the APL utility layer): Ambush
            -- (i=1), Garrote (i=2), Vanish (i=3) and Preparation (i=5) sit
            -- ABOVE the Forever APL's Slice and Dice upkeep (i=18), so the
            -- cluster rides above the 1b rule.
            action = forever_opener
        elseif not ea_wait_hold and not ea_lockout
            and not (is_num(ttd) and ttd <= min_ttd)
            and st.rogue_guide.snd_verdict(env_family, inputs) ~= nil then
            -- 1b. SnD upkeep before every spender (slot-less until icons land).
            -- SoD rides the SOD rows (4+CP, <=1 s) through the latch.
            -- Skipped on dying targets: rule 4 owns them (no SnD into a
            -- 5-second target — the TBC 10 s minimum direction). Yields to
            -- the 1a hold and to the Forever lockout (both sim-literal).
            action = "snd"
        elseif not ea_wait_hold and not ea_lockout
            and not (is_num(ttd) and ttd <= min_ttd)
            and st.rogue_guide.hfb_verdict(family, inputs) ~= nil then
            -- 1c. Hunger for Blood upkeep (Wrath sin, the wotlk APL's <= 1 s
            -- refresh). Slot-less like snd/ar/bf/coldblood: the slot contract
            -- is frozen, so the rotation label names it meanwhile. Yields to
            -- the 1a hold, to the Forever lockout and to the dying-target
            -- skip (the SnD rule's own shape).
            action = "hfb"
        elseif not ea_wait_hold and not ea_lockout
            and st.rogue_guide.vanish_verdict(env_family, inputs) ~= nil then
            -- 1d. Vanish (the stealth opener): the SoD APL's i=7 row and the
            -- WotLK APL's mutilate i=4 row. Both are readiness reads - an
            -- unreadable state hides.
            action = "vanish"
        elseif not ea_wait_hold and not ea_lockout
            and st.rogue_guide.poisoned_knife_verdict(env_family, inputs) ~= nil then
            -- 1e. Poisoned Knife (the SoD's 4-stack Deadly Poison window).
            action = "poisoned_knife"
        elseif not ea_wait_hold
            and st.rogue_guide.shiv_family_ok(family, inputs) == true
            and st.rogue_guide.shiv_verdict(inputs.deadly_stacks, inputs.deadly_remaining,
                inputs.shiv_ready, shiv_window) ~= nil then
            -- 2. Shiv upkeep before the Deadly clock falls off (ERA+TBC only;
            -- TBC gated on Mutilate-unknown + below 5CP). Yields to the 1a
            -- hold (the sim Shivs below 5CP, never into the wait); moot
            -- under the lockout (FOREVER never Shivs).
            action = "shiv"
        elseif not ea_wait_hold
            and st.rogue_guide.envenom_verdict(env_family, inputs, band) ~= nil then
            -- 3. Per-client Envenom rule. Yields to the 1a hold (the sim waits
            -- at 5CP instead of dumping); moot under the lockout (FOREVER
            -- never Envenoms).
            action = "envenom"
        elseif not ea_wait_hold and not ea_lockout
            and st.rogue_guide.premeditation_verdict(family, inputs) ~= nil then
            -- 3a. Premeditation (the Forever client's CP opener, cp <= 3).
            action = "premeditation"
        elseif not ea_wait_hold and not ea_lockout
            and st.rogue_guide.venom_verdict(family, inputs) ~= nil then
            -- 3b. Venom (the Forever client's 1310703 finisher) - the APL
            -- casts it (i=19) before its Rupture row (i=20).
            action = "venom"
        elseif not ea_wait_hold and not ea_lockout
            and is_num(ttd) and ttd <= min_ttd and is_num(cp) and cp >= dump_cp then
            -- 4. Dying-target dump (per-family CP floor: ERA any-CP, TBC 5CP,
            -- WRATH 4CP, FOREVER 3CP).
            action = "eviscerate"
        elseif not ea_wait_hold and not ea_lockout
            and is_num(cp) and cp >= min_cp then
            -- 5. Planned finisher: ERA Eviscerate-first (E-C1), rupture-first
            -- elsewhere via the TTD decider (unknown TTD yields nil and falls
            -- through - never a guessed finisher).
            if finisher_mode == "eviscerate" then
                if is_num(ttd) and ttd > min_ttd then
                    action = "eviscerate"
                end
            else
                action = st.rogue_guide.finisher_for_ttd(cp, ttd, inputs.rupture_remains, {
                    min_cp = min_cp,
                    rupture_refresh = rupture_refresh,
                    rupture_min_ttd = min_ttd,
                })
            end
        end

        if action == nil then
            if st.rogue_guide.ar_verdict(family, inputs) ~= nil then
                -- 5b. Adrenaline Rush on the sim energy line (slot-less for now).
                action = "ar"
            elseif st.rogue_guide.bf_verdict(family, inputs) ~= nil then
                -- 5c. Blade Flurry behind SnD (+EA when on duty; slot-less).
                action = "bf"
            elseif not ea_wait_hold and not ea_lockout
                and st.rogue_guide.cb_verdict(family, inputs) ~= nil then
                -- 5d. Cold Blood on the sim lines (TBC w/ SnD, Forever at 5CP;
                -- slot-less for now). Yields to the 1a hold and to the
                -- Forever lockout (the sim suppresses CB while EA is low).
                action = "coldblood"
            elseif st.rogue_guide.tricks_verdict(family, inputs) ~= nil then
                -- 5f. Tricks of the Trade (the WotLK energy pop).
                action = "tricks_of_the_trade"
            elseif st.rogue_guide.killing_spree_verdict(family, inputs) ~= nil then
                -- 5g. Killing Spree (the WotLK energy pop).
                action = "killing_spree"
            elseif st.rogue_guide.forever_paired_pop_verdict(family, inputs,
                "blood_fury_ready", "blood_fury") ~= nil then
                -- 5h. Blood Fury (the Forever client's paired pop).
                action = "blood_fury"
            elseif st.rogue_guide.forever_paired_pop_verdict(family, inputs,
                "elunes_light_ready", "elunes_light") ~= nil then
                -- 5i. Elune's Light (the Forever client's paired pop, 1259799).
                action = "elunes_light"
            elseif st.rogue_guide.gnome_eureka_verdict(family, inputs) ~= nil then
                -- 5j. Eureka! (the Forever client's Gnome racial, 1259812).
                action = "gnome_eureka"
            elseif st.rogue_guide.tea_verdict(inputs.tea_ready, energy, tea_max) ~= nil then
                -- 6. Thistle Tea on a proven energy deficit.
                action = "tea"
            else
                -- 7. Pool-vs-spend. The 1a hold reads POOL first (the sim's
                -- waitUntil - neither a builder nor a finisher); the sweaty
                -- override spends first (ERA 79+); a nil verdict (no band for
                -- this client) falls through silently (rule 8).
                local verdict
                local sweaty = st.rogue_guide.SWEATY_SPEND_BY_FAMILY[family]
                if ea_wait_hold then
                    verdict = "pool"
                elseif is_num(energy) and is_num(sweaty) and energy >= sweaty then
                    verdict = "spend"
                else
                    verdict = st.rogue_guide.pool_verdict(energy, inputs.energy_tick_in,
                        band, max_energy)
                end
                if verdict == "spend" then
                    action = "builder"
                elseif verdict == "pool" then
                    hold = true
                    hold_text = "POOL"
                end
            end
        end
    end
    -- 8. Anything else: no action. 0. Unknown: no action, no hold.

    out.action = action
    out.hold = hold
    out.hold_text = hold_text
    out.filler_slot = nil
    out.judge_slot = nil
    out.rotation_key = nil
    out.waiting_judgement = false
    out.unknown = unknown
    return out
end

--=========================================================================================
-- Practice surface: the pure half of the rotation table and the drill graders
--=========================================================================================
-- The class module (classes/rogue.lua) owns the rotation TABLE and the three
-- contract members the shared engine looks up; the DECISIONS live here, so every
-- number stays sim-cited and the whole path is unit-testable in the strict
-- sandbox (no WoW API, no clock).
--
-- The opener order (the practice audit's D-R4): the engine's own rule order, compiled
-- as a rank list so a drill can tell "the right step, late" (a timing failure) from
-- "the wrong step" (an order failure). The list is the shipped rule order (the header
-- above: EA duty -> SnD -> Hunger for Blood -> Shiv -> Envenom -> the dying-target
-- dump -> the planned finisher -> AR/BF/Cold Blood -> Tea -> the builder) with the
-- sim's prepull cooldown in front of it. Eviscerate and Rupture share the finisher
-- rank (they are the two ends of rule 4/rule 5, never both due at once).
st.rogue_guide.OPENER_RANK = {
    ar = 1,
    expose = 2,
    snd = 3,
    hfb = 4,
    shiv = 5,
    envenom = 6,
    eviscerate = 7,
    rupture = 7,
    builder = 8,
    -- The APL utility layer's openers (the stealth rows ride with the upkeep
    -- cluster; the cooldown pops ride with the builder).
    vanish = 3,
    ambush = 3,
    garrote = 3,
    preparation = 4,
    premeditation = 5,
    venom = 7,
    poisoned_knife = 6,
    blood_fury = 8,
    elunes_light = 8,
    gnome_eureka = 8,
    tricks_of_the_trade = 8,
    killing_spree = 8,
}

-- The rank of an action in the opener order, or nil when the action is not part of
-- it (an unknown key never ranks - it is not "the wrong order", it is not an opener
-- step at all).
function st.rogue_guide.opener_rank(action)
    if type(action) ~= "string" then
        return nil
    end
    local rank = st.rogue_guide.OPENER_RANK[action]
    if type(rank) ~= "number" then
        return nil
    end
    return rank
end

-- The prepull cooldown (the practice audit's D-R4): the TBC swords APL fires
-- Adrenaline Rush one second before the pull (ui/specs/rogue/dps/apls/swords.apl.json,
-- prepullActions: doAtValue -1s - the tbc-new rule fetched 2026-10-19). The other
-- families' Adrenaline Rush lines are in-combat energy gates, not prepulls (the
-- classic line at energy<59 with a tick inside 1 s, Forever at <=50 with SnD), so
-- only TBC carries a prepull shape here.
st.rogue_guide.PREPULL_FAMILIES = {
    TBC = true,
}
st.rogue_guide.PREPULL_LEAD_SECONDS = 1

-- The client's global cooldown (main.lua:get_spell_gcd_duration falls back to 1.5 s -
-- the addon's own client fact, not a sim number): the opener's timing bands are
-- counted in GCDs (the practice audit's D-R4 grades the timing in GCD steps).
st.rogue_guide.GCD_SECONDS = 1.5

-- The per-CP Slice and Dice duration (audit R-02 / F0-H1): the sourced rows only
-- ([9,12,15,18,21] s for CP 1-5, the classic/TBC slice_and_dice.go). A CP without a
-- sourced row reads nil - never interpolated, never guessed.
function st.rogue_guide.snd_duration_for_cp(cp)
    if not is_num(cp) then
        return nil
    end
    local d = st.rogue_guide.SND_DURATION_BY_CP[cp]
    if not is_num(d) then
        return nil
    end
    return d
end

-- The per-family floors the combo-point drill grades against (the practice audit's
-- D-R2): the planned finisher's CP line, the dying-target dump's CP line and the
-- TTD at/below which a fresh finisher cannot pay. Every value comes from the
-- engine's own tables, so a tuning pass moves the drill and the guide together.
function st.rogue_guide.family_floors(family)
    local floors = {}
    local finisher = st.rogue_guide.FINISHER_MIN_CP_BY_FAMILY[family]
    if is_num(finisher) then
        floors.finisher_min_cp = finisher
    end
    local dump = st.rogue_guide.DUMP_MIN_CP_BY_FAMILY[family]
    if is_num(dump) then
        floors.dump_min_cp = dump
    end
    local min_ttd = st.rogue_guide.RUPTURE_MIN_TTD_BY_FAMILY[family]
    if is_num(min_ttd) then
        floors.min_ttd = min_ttd
    end
    local snd_cp = st.rogue_guide.SND_MIN_CP_BY_FAMILY[family]
    if is_num(snd_cp) then
        floors.snd_min_cp = snd_cp
    end
    return floors
end

--=========================================================================================
-- Practice: the ctx contract and the pure graders
--=========================================================================================
-- The shared engine's ctx (the orchestrator's contract):
--   ctx.now          the clock (the engine's injected domain)
--   ctx.last_action  the action the player cast last (nil at the start of a run)
--   ctx.resources    the resource/state bag the simulator exposes
--   ctx.cooldowns    the remaining cooldowns the simulator exposes
-- The state bag carries the engine's OWN frozen input names (the header above), so
-- a drill grades the same state the guide reads.

-- The frozen input names the practice ctx feeds through ctx.resources (the same
-- names the live gather writes - the audit's §4.5 "the input writer must use the
-- engine's own frozen input names").
st.rogue_guide.PRACTICE_RESOURCE_FIELDS = {
    "family", "energy_now", "energy_tick_in", "max_energy", "cp", "ttd",
    "rupture_remains", "rupture_refresh", "rupture_min_ttd",
    "finisher_min_cp", "deadly_stacks", "deadly_remaining",
    "envenom_buff_remains", "ea_duty", "ea_remains", "ea_refresh",
    "sod_envenom", "snd_usable", "snd_remains", "snd_refresh", "snd_min_cp",
    "ar_ready", "bf_ready", "coldblood_ready",
    "shiv_ready", "shiv_refresh", "mutilate_known",
    "tea_ready", "tea_energy_max",
    "hfb_usable", "hfb_remains", "hfb_refresh",
    "vanish_ready", "master_of_subtlety_active", "vanished_active",
    "vanish_cd_remaining",
    "ambush_ready", "ambush_cue_active",
    "garrote_ready", "garrote_dot_active", "garrote_energy_cost",
    "preparation_ready", "premeditation_ready",
    "venom_ready", "venom_buff_active",
    "blood_fury_ready", "elunes_light_ready", "ar_cd_remaining",
    "ar_known", "ar_buff_active",
    "gnome_eureka_ready", "gnome_eureka_full_cd",
    "poisoned_knife_ready", "tricks_ready", "killing_spree_ready",
    "envenom_ready",
    "pool_pre", "pool_post", "inputs_unknown",
}

-- The cooldown rows the ctx may carry and the readiness flag each one proves: a
-- row at 0 means the action is off cooldown. A missing row stays nil (unknown -
-- the action never prompts).
st.rogue_guide.PRACTICE_COOLDOWN_FIELDS = {
    { "ar", "ar_ready" },
    { "bf", "bf_ready" },
    { "coldblood", "coldblood_ready" },
    { "shiv", "shiv_ready" },
    { "tea", "tea_ready" },
    { "vanish", "vanish_ready" },
    { "ambush", "ambush_ready" },
    { "garrote", "garrote_ready" },
    { "preparation", "preparation_ready" },
    { "premeditation", "premeditation_ready" },
    { "venom", "venom_ready" },
    { "blood_fury", "blood_fury_ready" },
    { "elunes_light", "elunes_light_ready" },
    { "gnome_eureka", "gnome_eureka_ready" },
    { "poisoned_knife", "poisoned_knife_ready" },
    { "tricks_of_the_trade", "tricks_ready" },
    { "killing_spree", "killing_spree_ready" },
    { "envenom", "envenom_ready" },
}

-- One reused input table and one reused output table: the practice path never
-- allocates (the same rule the live gather follows).
st.rogue_guide.practice_inputs = {}
st.rogue_guide.practice_out = {}

-- Pure: the practice ctx's resource bag (an empty table when the ctx carries none,
-- so a reader never has to nil-check).
function st.rogue_guide.get_practice_resources(ctx)
    if type(ctx) == "table" and type(ctx.resources) == "table" then
        return ctx.resources
    end
    return {}
end

-- Pure: the family the practice run is on: ctx.resources.family when the
-- simulator states one, else the client's own family (st.family) - the same
-- family token the engine's own gates read.
function st.rogue_guide.get_practice_family(ctx)
    local family = st.rogue_guide.get_practice_resources(ctx).family
    if type(family) ~= "string" or family == "" then
        family = st.family
    end
    if type(family) ~= "string" or family == "" then
        return nil
    end
    return family
end

-- Pure: the action under test. The contract's ctx names it last_action; "action",
-- "pick", "pressed" and "choice" are accepted as aliases so the shared engine can
-- name it either way. A non-string or an empty string reads as "nothing cast".
function st.rogue_guide.get_practice_pick(ctx)
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

-- Pure: a number the ctx carries, under any of the given names (the first one
-- that answers wins). nil when none of them is a usable number.
function st.rogue_guide.practice_number(ctx, ...)
    if type(ctx) ~= "table" then
        return nil
    end
    local names = { ... }
    for i = 1, #names do
        local value = ctx[names[i]]
        if is_num(value) then
            return value
        end
    end
    local resources = st.rogue_guide.get_practice_resources(ctx)
    for i = 1, #names do
        local value = resources[names[i]]
        if is_num(value) then
            return value
        end
    end
    return nil
end

-- Pure: a boolean the ctx carries, under any of the given names (the first one that
-- answers wins). nil when none of them is a boolean.
function st.rogue_guide.practice_flag(ctx, ...)
    if type(ctx) ~= "table" then
        return nil
    end
    local names = { ... }
    for i = 1, #names do
        local value = ctx[names[i]]
        if type(value) == "boolean" then
            return value
        end
    end
    local resources = st.rogue_guide.get_practice_resources(ctx)
    for i = 1, #names do
        local value = resources[names[i]]
        if type(value) == "boolean" then
            return value
        end
    end
    return nil
end

-- Pure: write the frozen input set from a practice ctx into the caller's table.
-- Every field this function owns is written on every call (nil when the ctx does
-- not carry it), so a reused table never keeps a stale value.
function st.rogue_guide.build_practice_inputs(ctx, out)
    local guide = st.rogue_guide
    out = out or {}
    local resources = nil
    local cooldowns = nil
    if type(ctx) == "table" then
        if type(ctx.resources) == "table" then resources = ctx.resources end
        if type(ctx.cooldowns) == "table" then cooldowns = ctx.cooldowns end
    end
    for i = 1, #guide.PRACTICE_RESOURCE_FIELDS do
        local name = guide.PRACTICE_RESOURCE_FIELDS[i]
        out[name] = nil
        local value = nil
        if resources then value = resources[name] end
        if value == nil and type(ctx) == "table" then value = ctx[name] end
        if value ~= nil then
            out[name] = value
        end
    end
    for i = 1, #guide.PRACTICE_COOLDOWN_FIELDS do
        local key = guide.PRACTICE_COOLDOWN_FIELDS[i][1]
        local flag = guide.PRACTICE_COOLDOWN_FIELDS[i][2]
        local remaining = nil
        if cooldowns then remaining = cooldowns[key] end
        if remaining == nil and resources then remaining = resources[key] end
        if remaining == nil and type(ctx) == "table" then remaining = ctx[key] end
        if is_num(remaining) and remaining <= 0 then
            -- Off cooldown: the readiness can be proven. A flag the resource bag
            -- already proved is never cleared here (the bag is the richer read).
            out[flag] = true
        end
    end
    local family = guide.get_practice_family(ctx)
    if family then
        out.family = family
    end
    return out
end

-- Pure: the engine's verdict for a practice ctx. Returns the out table (the frozen
-- display fields) and the inputs it was built from.
function st.rogue_guide.practice_expected(ctx, out)
    local guide = st.rogue_guide
    local inputs = guide.build_practice_inputs(ctx, guide.practice_inputs)
    local res = guide.evaluate(inputs, out or guide.practice_out)
    return res, inputs
end

-- The short reason line per action (the panel's one-liner).
st.rogue_guide.PRACTICE_REASONS = {
    expose = "Expose Armor is due",
    snd = "Slice and Dice is about to fall",
    hfb = "Hunger for Blood is about to fall",
    shiv = "Deadly Poison is about to fall off",
    envenom = "Envenom is due",
    eviscerate = "Eviscerate is due",
    rupture = "Rupture is due",
    ar = "Adrenaline Rush is off cooldown",
    bf = "Blade Flurry is off cooldown",
    coldblood = "Cold Blood is off cooldown",
    tea = "Thistle Tea for the energy deficit",
    builder = "the builder (spend the energy)",
    vanish = "Vanish (the stealth opener)",
    ambush = "Ambush (the opener)",
    garrote = "Garrote (the opener)",
    preparation = "Preparation (Vanish is not ready)",
    premeditation = "Premeditation (the combo-point opener)",
    venom = "Venom (the finisher is up)",
    poisoned_knife = "Poisoned Knife (the Deadly Poison window)",
    blood_fury = "Blood Fury (paired with Adrenaline Rush)",
    elunes_light = "Elune's Light (paired with Adrenaline Rush)",
    tricks_of_the_trade = "Tricks of the Trade is off cooldown",
    killing_spree = "Killing Spree is off cooldown",
    gnome_eureka = "Eureka! (the Gnome racial)",
}

-- Pure: the short reason line for a verdict.
function st.rogue_guide.practice_reason(res)
    local action = res and res.action
    if type(action) ~= "string" or action == "" then
        if res and res.hold then
            return res.hold_text or "POOL"
        end
        return nil
    end
    return st.rogue_guide.PRACTICE_REASONS[action] or "Follow the rotation"
end

-- Pure: the rotation's next action for a practice ctx.
--   -> { action = "<slot key>", reason = "<text>" } | nil
-- nil means "cannot decide": an idle engine, a HOLD (the engine's POOL) or a
-- missing guide module. The engine grades such a step UNKNOWN - it never records
-- a wrong action. (The audit's S-R calls a cast during a POOL an illegal cast,
-- but the shipped engine can only compare an EXPECTED ACTION: a nil expected
-- reads as UNKNOWN, so a hold must never become a guessed action key - filed.)
function st.rogue_guide.practice_step(ctx, out)
    local guide = st.rogue_guide
    if not (guide and guide.evaluate) then
        return nil
    end
    local res = guide.practice_expected(ctx, out)
    if res.hold then
        return nil
    end
    if type(res.action) ~= "string" or res.action == "" then
        return nil
    end
    return { action = res.action, reason = guide.practice_reason(res) }
end

--=========================================================================================
-- The drill graders (the practice audit's section C)
--=========================================================================================
-- Every grader returns nil when the attempt is not judgeable (the engine shows
-- UNKNOWN and records no attempt - a grade is never guessed).

-- Drill D-R1 - the finisher order (the audit's D-R1): the priority order - Expose
-- duty -> SnD upkeep -> Shiv upkeep -> Envenom -> the dying-target dump -> the
-- planned finisher -> AR/BF/Cold Blood -> Tea. The engine's own action IS the
-- expected order, so a nearly-right pick (Rupture instead of Eviscerate on Era) is
-- a mis-pick: that is the whole point of the drill.
-- Per-decision verdict: "S" when the cast matches the verdict, "F" when it does
-- not. The run's band (the audit's S/A/B/C/D/F on the mis-pick count) is the
-- class module's job - it owns the session counters.
st.rogue_guide.PRACTICE_DRILL_PRIORITY = "rogue_finisher_order"

function st.rogue_guide.grade_finisher_order(ctx)
    local guide = st.rogue_guide
    if not (guide and guide.evaluate) then
        return nil
    end
    local res = guide.practice_expected(ctx, guide.practice_out)
    if res.hold then
        -- A POOL step is not a decision (the engine's own rule: a hold grades
        -- nil, never a wrong action).
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

-- Drill D-R2 - the combo-point decision (the audit's D-R2): when to commit a
-- finisher, measured against the family's own floor (the planned finisher's CP
-- line, or the dying-target dump's line when the target is dying).
-- Bands [DESIGN, the audit's D-R2]: at/above the floor with the right finisher S,
-- one CP short A, two CP short B, at the floor with the wrong finisher C, below
-- the floor on a DYING target D (forgiven), below the floor on a healthy target F
-- (the combo points were wasted).
st.rogue_guide.PRACTICE_DRILL_CP_FINISH = "rogue_cp_finish"

-- The finisher actions the combo-point drill grades.
st.rogue_guide.PRACTICE_FINISHERS = {
    eviscerate = true,
    rupture = true,
    envenom = true,
}

function st.rogue_guide.grade_cp_finish(ctx)
    local guide = st.rogue_guide
    if not (guide and guide.evaluate) then
        return nil
    end
    local pick = guide.get_practice_pick(ctx)
    if pick == nil or not guide.PRACTICE_FINISHERS[pick] then
        -- Not a combo-point decision (a builder or an upkeep cast).
        return nil
    end
    local cp = guide.practice_number(ctx, "cp")
    if cp == nil then
        return nil
    end
    local floors = guide.family_floors(guide.get_practice_family(ctx))
    local required = floors.finisher_min_cp
    if required == nil then
        required = guide.FINISHER_MIN_CP_DEFAULT
    end
    local min_ttd = floors.min_ttd
    if min_ttd == nil then
        min_ttd = guide.RUPTURE_MIN_TTD_DEFAULT
    end
    local ttd = guide.practice_number(ctx, "ttd")
    local dying = (ttd ~= nil) and (ttd <= min_ttd)
    if dying then
        required = floors.dump_min_cp or 1
    end
    if dying and cp < required then
        -- Below the floor, but the target was dying: forgiven.
        return "D"
    end
    if cp >= required then
        local res = guide.practice_expected(ctx, guide.practice_out)
        if res.unknown then
            -- The state is unreadable: nothing to judge.
            return nil
        end
        if res.action == pick then
            return "S"
        end
        -- At the floor but the wrong finisher.
        return "C"
    end
    local short = required - cp
    if short <= 1 then
        return "A"
    end
    if short <= 2 then
        return "B"
    end
    -- Below the floor on a healthy target: the combo points were wasted.
    return "F"
end

-- Drill D-R3 - the debuff upkeep (the audit's D-R3): keeping Slice and Dice up.
-- The ctx states the debuff's state at the press: snd_remains (the buff's
-- remaining seconds - above zero means the refresh landed in time), or
-- snd_late_by (the seconds past the expiry; zero or less means it landed in
-- time), or snd_expired_at (the expiry timestamp against ctx.now).
-- Bands [DESIGN, the audit's D-R3]: refreshed while the debuff was still up S, one
-- tick late (<= 2 s) A, <= 4 s B, the debuff had expired C, the builder pressed
-- over the window D, down for longer than the debuff's own length F.
st.rogue_guide.PRACTICE_DRILL_SND_UPKEEP = "rogue_snd_upkeep"

function st.rogue_guide.grade_snd_upkeep(ctx)
    local guide = st.rogue_guide
    if type(ctx) ~= "table" then
        return nil
    end
    local pick = guide.get_practice_pick(ctx)
    if pick == nil then
        return nil
    end
    local resources = guide.get_practice_resources(ctx)
    local late = nil
    local expired = false
    local remains = resources.snd_remains
    if remains == nil then
        remains = ctx.snd_remains
    end
    if is_num(remains) then
        if remains > 0 then
            late = 0
        else
            late = -remains
            expired = true
        end
    end
    local late_by = resources.snd_late_by
    if late_by == nil then
        late_by = ctx.snd_late_by
    end
    if is_num(late_by) then
        late = late_by
        expired = late_by > 0
    else
        local expired_at = resources.snd_expired_at
        if expired_at == nil then
            expired_at = ctx.snd_expired_at
        end
        local now = ctx.now
        if is_num(expired_at) and is_num(now) then
            late = now - expired_at
            expired = late > 0
        end
    end
    if late == nil then
        -- No clock: the refresh cannot be scored (never a guess).
        return nil
    end
    if pick == "snd" then
        if not expired then
            -- Refreshed while the debuff was still up.
            return "S"
        end
        local cp = guide.practice_number(ctx, "cp")
        local duration = guide.snd_duration_for_cp(cp)
        if duration and late > duration then
            -- Down for longer than the debuff's own length: never maintained.
            return "F"
        end
        if late > 0 and late <= 2 then
            return "A"
        end
        if late > 0 and late <= 4 then
            return "B"
        end
        -- The debuff had expired.
        return "C"
    end
    if expired then
        if pick == "builder" then
            -- The builder was pressed over the window.
            return "D"
        end
        -- The upkeep was skipped entirely.
        return "F"
    end
    return nil
end

-- Drill D-R4 - the opener (the audit's D-R4): the prepull and the first-finisher
-- decision. The rogue has no client pull timer, so the drill carries its own
-- synthetic countdown (ctx.pull_at, or ctx.pull_in against ctx.now).
-- Bands [DESIGN, the audit's D-R4]: the right step on time S, one GCD late A, two
-- B, three C, the step far too late (or a due step skipped) D, the wrong order F.
st.rogue_guide.PRACTICE_DRILL_OPENER = "rogue_opener"

function st.rogue_guide.grade_opener(ctx)
    local guide = st.rogue_guide
    if not (guide and guide.evaluate) then
        return nil
    end
    if type(ctx) ~= "table" then
        return nil
    end
    local pick = guide.get_practice_pick(ctx)
    if pick == nil then
        return nil
    end
    local now = ctx.now
    local pull_at = guide.practice_number(ctx, "pull_at")
    if pull_at == nil then
        local pull_in = guide.practice_number(ctx, "pull_in")
        if pull_in ~= nil and is_num(now) then
            pull_at = now + pull_in
        end
    end
    if pull_at == nil then
        -- No pull clock: the opener cannot be scored (never a guess).
        return nil
    end
    local res = guide.practice_expected(ctx, guide.practice_out)
    if res.unknown then
        -- The state is unreadable: nothing to judge.
        return nil
    end
    if res.hold then
        -- The rotation holds: any cast in the opener window is wrong.
        return "F"
    end
    local expected = res.action
    local prepull = false
    local prepull_at = nil
    -- The pre-pull row (the APLs' prepullActions - the class publishes the
    -- table, ST.ROGUE.practice_prepulls, and the ctx names the running family's
    -- first ready CAST row). A ctx without a row falls back to the shipped TBC
    -- Adrenaline Rush row (the sim's -1 s mark).
    if type(ctx) == "table" then
        local resources = guide.get_practice_resources(ctx)
        local action = ctx.prepull_action
        if type(action) ~= "string" then
            action = resources.prepull_action
        end
        if type(action) == "string" and action ~= "" then
            local at = guide.practice_number(ctx, "prepull_at")
            if is_num(at) and guide.practice_flag(ctx, action .. "_ready") == true then
                prepull_at = at
                expected = action
                prepull = true
            end
        end
    end
    if not prepull and is_num(now) and pull_at > now
        and guide.PREPULL_FAMILIES[guide.get_practice_family(ctx)]
        and guide.practice_flag(ctx, "ar_ready") == true then
        -- The sim's prepull cooldown (the TBC Adrenaline Rush at -1 s).
        expected = "ar"
        prepull = true
        prepull_at = -guide.PREPULL_LEAD_SECONDS
    end
    if type(expected) ~= "string" or expected == "" then
        return nil
    end
    local expected_at
    if prepull then
        expected_at = pull_at + prepull_at
    else
        expected_at = pull_at + guide.GCD_SECONDS
    end
    if pick == expected then
        local late = now - expected_at
        if late <= 0 then
            return "S"
        end
        local gcd = guide.GCD_SECONDS
        if late <= gcd then
            return "A"
        end
        if late <= 2 * gcd then
            return "B"
        end
        if late <= 3 * gcd then
            return "C"
        end
        -- The opener step landed far too late: the opener was missed.
        return "D"
    end
    local pick_rank = guide.opener_rank(pick)
    local expected_rank = guide.opener_rank(expected)
    if pick_rank and expected_rank and pick_rank > expected_rank then
        -- A later step: the due step was skipped (an opener missed).
        return "D"
    end
    -- The wrong order.
    return "F"
end
