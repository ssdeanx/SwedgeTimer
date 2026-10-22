--=========================================================================================
-- Druid next-action guide: pure decision engine, no WoW API and no clock.
--
-- The third provider for the frozen ST.<CLASS>.guide contract (nextaction_ui.lua's
-- header; the paladin ships the first, the warrior the second). The live reads live in
-- classes/druid.lua (ST.DRUID.gather_guide_inputs); this module only consumes the
-- gathered inputs, so it is unit-tested offline by tests/druid_guide_state.lua.
--
-- FROZEN SPEC - display slots (ST.DRUID.guide.slots, ordered, all seven the
-- contract allows):
--   maul     Maul           6807  (icon rank-resolved at post_init)
--   mangle   Mangle         33878 (icon rank-resolved through the module's Mangle id
--                                  table at post_init, else this fallback)
--   rip      Rip            1079  (swipe: the tracker's own debuff window)
--   rake     Rake           1822  (swipe: the tracker's own debuff window)
--   bite     Ferocious Bite 22568
--   shred    Shred          5221
--   claw     Claw           9850  (sim Forever rank; no rank table exists, so the id
--                                  never re-points - other ranks UNCONFIRMED)
--
-- FROZEN SPEC - inputs (all optional, nil never errors):
--   speed, swing_remaining, gcd_remaining    swing/GCD (api.get_time() domain)
--   form_index                               live druid form (1 bear, 3 cat)
--   rage                                     bear rage (api.UnitPower player, 1)
--   energy                                   cat energy (api.UnitPower player, 3)
--   combo_points                             cat combo points, nil-safe (player, 4)
--   maul_queued                              the module's Maul queue flag
--   maul_cost                                Maul's rage cost at the current rank
--   insufficient_rage                        the bar-colour shortfall flag
--   rip_remaining, rake_remaining, mangle_remaining
--                                            target DEBUFF seconds from the module's
--                                            tracker; nil = the target does not carry
--                                            it (or the scan has not answered)
--   rip_refresh, rake_refresh                db thresholds, default 4
--   family                                   compat.lua's st.family ("ERA", "TBC",
--                                            "WRATH", "CATA", "MISTS", "RETAIL",
--                                            "FOREVER", ...); "TBC" runs the TBC
--                                            APPENDIX, "WRATH" runs the WRATH
--                                            APPENDIX, "ERA" runs the SOD APPENDIX
--                                            when sod_runes is true and the ERA
--                                            APPENDIX otherwise, anything else
--                                            (or nil) runs rules 4-8 exactly as below
--   sr_remaining                             SAVAGE ROAR buff seconds from the module's
--                                            player scan; nil = absent (or the scan
--                                            has not answered)
--   tf_ready                                 Tiger's Fury proven ready (true) or proven
--                                            on cooldown (false); nil = unknown (the
--                                            client cannot answer - never a guess)
--   tf_cd_remaining                          Tiger's Fury cooldown seconds, 0 when ready;
--                                            nil = unknown
--   tf_active                                the Tiger's Fury damage buff is up (true
--                                            only; the SoD King-of-the-Jungle snapshot)
--   berserk_ready                            Berserk proven ready (true only)
--   clearcast                                an Omen of Clarity proc is up (true only)
--   sod_runes                                SoD rune basis present on the ERA token
--                                            (true only; a known Mangle rank answers
--                                            api.is_spell_known, else a known Mangle
--                                            or Savage Roar answers GetSpellInfo by
--                                            name - Era-base knows neither)
--   time_to_die                              target seconds-to-die, when known
--                                            (D4: the EMA-smoothed HP/s estimate
--                                            from classes/druid.lua's sampler;
--                                            nil = unknown - no target, unreadable
--                                            or dead health)
--   target_short_lived                       explicit short-lived flag (true only)
--   can_powershift                           RESERVED (no rule reads it): the
--                                            Furor half of the powershift basis
--                                            has no honest client probe (see
--                                            the REMOVED note in the TBC
--                                            APPENDIX below), so the gather
--                                            always writes nil and no SHIFT
--                                            prompt exists anywhere.
--   wolfshead_equipped                       RESERVED (no rule reads it): the
--                                            Wolfshead Helm half of the same
--                                            basis, read by the gather through
--                                            api.is_item_equipped(8345) - the
--                                            sim's own HasItemEquipped(8345)
--                                            check (tbc-new feralcat.go) and the
--                                            wowhead-confirmed Wolfshead Helm
--                                            id. Tri-state: true = equipped,
--                                            false = the read worked and no
--                                            equipped slot holds it, nil =
--                                            unknown (the read is unavailable
--                                            or secret - unknown is never
--                                            false). The SHIFT call stays
--                                            removed: the Furor half is still
--                                            unproven, so the Helm read alone
--                                            is not the basis.
--   mangle_cost                              live Mangle energy cost from the
--                                            client's GetSpellPowerCost through the
--                                            module's current Mangle rank
--                                            (TBC-gated in the gather; nil = the
--                                            client cannot answer - the engine
--                                            falls back to MANGLE_COST_TBC below,
--                                            which keeps every other family and
--                                            every offline caller byte-identical)
--   sp_ready                                 Shifting Power proven ready (true) or
--                                            proven on cooldown (false); nil =
--                                            unknown (FOREVER-gated in the gather -
--                                            never a guess)
--   sp_cd_remaining                          Shifting Power cooldown seconds, 0 when
--                                            ready; nil = unknown
--   fight_elapsed                            seconds since combat start (the gather's
--                                            api.get_time() stamp; nil = unknown -
--                                            no stamp yet, out of combat - and the
--                                            engine takes its documented long-fight
--                                            default, never a withheld Rip)
--   tick_remaining                           seconds to the next energy tick from the
--                                            tracker's anchor (druid_energy
--                                            get_tick_remaining; nil = unknown -
--                                            the sampler is off or has not answered).
--                                            RESERVED (no rule reads it yet): the
--                                            trick/pooling windows file their rule
--                                            design against it - see the follow-up
--                                            note in the TBC APPENDIX below.
--   latency                                  client latency seconds (nil = unknown -
--                                            no probe yet; the W1 line degrades to
--                                            the GCD remainder alone)
--   ff_ready, ff_cd_remaining                Faerie Fire probe (name-based, GCD-echo
--                                            filtered like TF/SP; nil = unknown).
--                                            Wrath fishes live off them (W1b
--                                            below); Forever additionally needs
--                                            the Omen ICD (omen_icd_ready),
--                                            which has no probe yet - filed.
--   omen_icd_ready                           RESERVED (only the Forever F6c gate
--                                            below reads it): the Omen of Clarity
--                                            ICD the sim's omenFish requires
--                                            (auraIcdReady 16864) has no honest
--                                            client probe, so no gather writes it
--                                            (nil = unknown) and F6c stays dormant
--                                            in game - filed follow-up, offline
--                                            pins only.
--   can_shred                                RESERVED (no rule reads it): position
--                                            behind the target has no honest probe
--                                            (the sim's CannotShredTarget option
--                                            has no WoW API counterpart -
--                                            IsSpellUsable answers usability,
--                                            never facing), so the gather always
--                                            writes nil (assume Shred can land)
--                                            and no Claw prompt exists yet (the
--                                            claw slot is declared above; its
--                                            rule files its probe - filed
--                                            follow-up).
--   rip_min_cp                               TBC Rip threshold override (sim user-config
--                                            RipMinComboPoints; nil = the frozen 4;
--                                            the option widget is OUT OF SCOPE -
--                                            filed follow-up, engine side ready)
--   lop_known, lop_active                    the Leader of the Pack (the Era APL's
--                                            i=1 row): lop_known = the spell is in
--                                            the player's book (true only),
--                                            lop_active = the party buff is up on
--                                            the player (true), proven absent
--                                            (false) or unknown (nil - the
--                                            player's own aura walk has not
--                                            answered). The arm wants known +
--                                            proven absent + a young fight.
--   ff_debuff_remaining                      the target's Faerie Fire debuff
--                                            seconds (a number = the debuff is up
--                                            with that remaining; false = the
--                                            walk answered and the debuff is
--                                            NOT on the target; nil = the walk
--                                            has not answered yet - unknown, and
--                                            an unknown never prompts).
--   feral_ff_ready                           the Feral Faerie Fire is off cooldown
--                                            (true only; nil = unknown - the
--                                            client cannot answer).
--   innervate_ready                          Innervate is off cooldown (true only;
--                                            nil = unknown).
--   elunes_light_ready                       Elune's Light is off cooldown (true
--                                            only; nil = unknown - the Forever
--                                            name is UNCONFIRMED outside the APL,
--                                            so the knowledge gate keeps it
--                                            dormant until the client's own spell
--                                            data answers it).
--   mana_percent                             the player's mana fraction (nil =
--                                            unknown).
--   has_target                               the player has a target (true) or not
--                                            (false) - the Faerie Fire upkeep
--                                            needs a target to land on.
--   feral_spec                               the class's own SPEC read (true only):
--                                            the player proves Feral-tree points
--                                            through the client's spell knowledge
--                                            (api.is_spell_known on the family's
--                                            Feral-tree talent - the Faerie Fire
--                                            (Feral) on Era/SoD/TBC, the Leader
--                                            of the Pack on Forever). false = the
--                                            client answered and the player is not
--                                            a feral druid, nil = unknown (no
--                                            probe on this family - the WotLK
--                                            client, whose APL carries no Cat
--                                            Form row). It is the Cat Form
--                                            upkeep's caster gate: a resto or a
--                                            balance druid is never asked to
--                                            shift.
--   cat_form_active                          the player's own Cat Form aura (true =
--                                            up, false = proven absent by the
--                                            player's aura walk, nil = the walk
--                                            has not answered yet - unknown, and
--                                            an unknown never prompts). The APL's
--                                            form row is exactly this condition
--                                            ("cast it when the Cat Form aura is
--                                            not active").
--
-- FROZEN SPEC - rule order (first match wins; exactly these rules):
--   0a. The Cat Form upkeep (the APL's form row: the Era APL's i=14, the SoD
--      APL's i=0, the TBC APL's Powershifting group, the Forever APL's i=1) on
--      the families whose APL puts it ABOVE the Innervate row (SoD: i=0 vs
--      i=4; Forever: i=1 vs i=10): feral_spec == true (the player proves
--      Feral-tree points), cat_form_active == false (the Cat Form aura is
--      proven absent) and the form is the humanoid (0) or the travel (4) form
--      -> hold "CAT FORM" with action nil (the hold overlay carries the call;
--      no guide slot exists).
--   0. The Innervate (the APL utility layer's mana row): innervate_ready and the
--      mana at 40 % or less, in any form but the bear -> hold "INNERVATE" (the hold
--      overlay carries the call; no guide slot exists). The Era row is a caster row
--      (outside the cat form); the SoD row (the same family token plus the runes)
--      and the Forever row are cat rows. The bear form is never touched (the bear
--      rules own it).
--   0b. The Cat Form upkeep on the families whose APL puts it BELOW the
--      Innervate row (Era: i=14 vs i=13): the same three proofs, in the
--      humanoid or the travel form only -> hold "CAT FORM" (the bear and the
--      cat chains own their own forms, so this branch is the other forms).
--   Bear form (form_index == 1):
--     1. maul_queued -> no action, hold = true, hold_text = "RIDE" (the guide rides the
--        queue the player already placed). RIDE is the guide's PRESS-NOTHING hold: the
--        queued Maul is already going, so the player presses NO key (the other nine
--        hold texts name the spell to press).
--     2. rage sufficient -> action "maul". Sufficient = rage and maul_cost are both
--        numbers and rage >= maul_cost, and insufficient_rage is not true (the flag can
--        veto a proof, never stand in for one). A cost or rage the client cannot answer
--        is NOT sufficient: the engine never guesses a Maul it cannot prove affordable.
--     3. otherwise, off Era -> action "mangle" (the only Mangle prompt left;
--        SoD rides here too: sod_runes on the ERA token proves Mangle via rune).
--     3e. otherwise, on a client with NO Mangle spell -> wait (action nil, no
--        hold): runeless Era (the module's Mangle ids 33983/33987 are TBC+) and
--        the FOREVER client (no Mangle spell at all - the Forever sim carries no
--        Mangle table and the Forever APL's builders are 9830 Shred and 9850
--        Claw), so the guide pools rage instead of guessing a spell the client
--        cannot know.
--   Cat form (form_index == 3):
--     TBC (family == "TBC") -> the TBC APPENDIX (T1-T6), byte-identical.
--     FOREVER (family == "FOREVER") -> the FOREVER APPENDIX (F1-F4, F6-F7; the
--     F5 Mangle line was REMOVED - the Forever client has no Mangle spell).
--     ERA (family == "ERA") + sod_runes -> the SOD APPENDIX (S1-S8).
--     ERA (family == "ERA") without runes -> the ERA APPENDIX (E0-E2).
--     WRATH (family == "WRATH") -> the WRATH APPENDIX (W1-W9).
--     Anything else (or nil) -> rules 4-8 exactly as below:
--     4. rip_remaining nil or <= rip_refresh -> action "rip". A remaining of exactly
--        the threshold refreshes; nil (no Rip tracked) always refreshes.
--     5. else rake_remaining nil or <= rake_refresh -> action "rake".
--     6. else mangle_remaining nil -> action "mangle" (absent outright only: Mangle has
--        no refresh window).
--     7. else combo_points is a number >= 5 -> action "bite"; an unreadable combo count
--        cannot clear the threshold and falls through.
--     8. else -> action "shred".
--   Any other or unknown form (caster forms, no form, an unreadable form_index) -> no
--   action: unknown context never guesses a bear or cat action.
--
-- TBC APPENDIX - cat form only, when family == "TBC" (first match wins):
--   T0. The Faerie Fire upkeep (the TBC APL's i=2): the target does not carry the
--       Faerie Fire debuff, the Feral Faerie Fire is off cooldown and the player
--       has a target -> hold "FAERIE FIRE" with action nil (the hold overlay
--       carries the call; no FF slot exists). An unreadable debuff, an unreadable
--       cooldown or a missing target never prompts.
--   T1. combo_points >= rip_min_cp (default 4, the sim's RipMinComboPoints
--       user-config; the option widget is OUT OF SCOPE - filed follow-up) and
--       Rip expired (nil or <= 0, no window) -> "rip".
--   T2. mangle_remaining nil and energy >= 40 -> "mangle" (the TBC Mangle cost).
--   T3. combo_points >= 5 and a short-lived target -> "bite" (the only TBC Bite:
--       target_short_lived == true, or time_to_die <= 10, the sim's RipEndThresh).
--   T4. combo_points >= 5 -> "rip" (the long-fight finisher is always Rip).
--   T5. energy >= 42 -> "shred" (the TBC Shred cost).
--   T6. otherwise -> wait (action nil, no hold): pool energy, do not guess.
--   Trick/pooling groundwork (filed follow-up, no rule yet): the sim's
--   BiteTrick (2+ CP, [biteCost,39], time-to-next-tick > reaction), RakeTrick
--   ([biteCost,mangleCost) window), MangleTrick (double-Mangle window) and
--   ripweave (>= 52) all read tick_remaining plus live bite/shred costs the
--   gather does not prove yet (tick_remaining rides the tracker's anchor when
--   the sampler runs, else nil; costs file their rank-table probe). No rule
--   reads them, so every offline caller stays byte-identical.
--   REMOVED (was T6, the can_powershift SHIFT call): the shift basis is two
--   probes and only one of them is proven. The Wolfshead Helm half IS proven:
--   the sim checks Wolfshead Helm item 8345 (tbc-new feralcat/feralcat.go
--   HasItemEquipped(8345)), 8345 is the wowhead-confirmed Wolfshead Helm, and
--   the gather now reads it through api.is_item_equipped (compat.lua) - it
--   publishes the tri-state as the reserved input wolfshead_equipped (true =
--   equipped, false = the read worked and no equipped slot holds it, nil =
--   unknown). The Furor half is still unproven: main.lua's talent_positions
--   covers WRATH only (no verified TBC Furor tab/index, so any GetTalentInfo
--   read would be a guess). The gather still writes can_powershift = nil on
--   every tick, the branch advertised a prompt that could never show, and its
--   POWERSHIFT_SHORTFALL_TBC constant is gone with it. No rule reads
--   wolfshead_equipped either: the Helm read alone is not the basis, so do not
--   re-add the call until Furor is proven.
--   Rake is never prompted on TBC (the sim's RakeTrick window needs the
--   energy-tick phase plus live Mangle/Rip costs - filed follow-up; the rake
--   slot stays declared for the Wrath matrix). Tiger's Fury is never prompted
--   mid-rotation (pre-pull only); no rule names it. Bear form is rules 1-3 on
--   every non-Era family plus SoD (rule 3e waits on runeless Era only);
--   every non-TBC, non-Era, non-Wrath, non-Forever family runs rules 4-8 unchanged.
--
--   TBC MICRO (docs/research/tbc_minmax.md, Warcraft Tavern feral guide):
--   energy ticks continue every 2 s regardless of form (no reset on shift), so
--   the tick bar keeps its phase across powershifts on TBC (the anchor policy
--   lives in classes/druid.lua; the cycle maths in druid_energy.lua is
--   anchor-relative and needed no change). The 2pc-T6 bonus cuts Mangle (Cat)
--   to 35 energy (non-Wolfshead P5 rotation): T2 spends inputs.mangle_cost
--   when the gather proves it live, else the frozen 40. Whether TBC
--   GetSpellPowerCost reflects the set bonus is in-game to confirm. Rip
--   snapshots attack power at cast (trinket procs included): no trinket-proc
--   input exists (no buff list, no AP comparison), so no rule models the
--   snapshot - in-game to confirm before any prompt is built.
--
-- FOREVER APPENDIX - cat form only, when family == "FOREVER" (first match wins):
--   F1. sp_ready and energy with room for the Shifting Power gain (<= 50,
--       40 on Clearcasting - the proc keeps filling through the GCD, the sim's
--       underCap math) -> hold "SHIFTING POWER" with action nil (no free slot
--       exists, so the hold overlay carries the call). Cat-only by construction
--       (this branch never runs in bear).
--   F1b. berserk_ready and Rip up (> 0) with no proc -> hold "BERSERK" with
--       action nil (same slot rationale; the APL Berserk-with-builder sequence -
--       the 417141 id is sim-only UNCONFIRMED, so the call rides the shared
--       Berserk knowledge probe: proven ready via the client's own spell data,
--       never a guessed id; no energy gate, no TF phasing - Forever has no TF).
--   F1c. Elune's Light (the Forever APL's i=3, the Cooldowns group): the cooldown
--       is ready -> hold "ELUNE'S LIGHT" with action nil (same slot rationale).
--       The read is the APL's own id 1259799, but the NAME comes from the APL's
--       variable and is UNCONFIRMED outside it - the gather's knowledge gate
--       (api.GetSpellInfo answering the literal name) keeps the line dormant
--       until the client's own spell data answers it.
--   F2. clearcast -> "shred" (the APL ccShred: the Omen proc is a free Shred,
--       ahead of the finishers).
--   F3. combo_points >= 5 and Rip expired (nil or <= 0, no window) and the
--       fight-elapsed gate (nil = unknown/long -> Rip; < 10 s -> pool, the APL
--       10 s fight gate) -> "rip" (the APL ripNow).
--   F4. Rake expired (nil or <= 0, no window) -> "rake" (the APL rakeNow).
--   F5. REMOVED (was: mangle_remaining nil -> "mangle"): the Forever client has
--       NO Mangle spell at all, so that branch answered "mangle" on every tick
--       (mangle_remaining is always nil there) and the F6 (the Bite) and F7 (the
--       builder) branches below were unreachable. The Forever APL's own slot
--       there is EMPTY (its builders are 9830 Shred and 9850 Claw - the
--       Builders group at i=9), so the chain now falls through to the Bite and
--       the builder - exactly the APL's own order. The builder's Claw half stays
--       RESERVED (the behind-the-target probe does not exist - filed follow-up),
--       so the engine answers the APL's Shred.
--   F6. Bite end-only: 5 CP inside the execute window (short-lived flag, or
--       time-to-die <= 10, the Wrath execute convention), or 3+ CP inside the
--       last 3 s (the APL biteLow) -> "bite". Never mid-fight (the APL never
--       Bites there, unlike the legacy rule 7).
--   F6c. Omen-fishing Faerie Fire -> hold "FAERIE FIRE" with action nil (same
--       slot rationale; the APL omenFish: proven-ready FF with no proc, the
--       Omen ICD ready, Shifting Power not coming inside 1 s, and nothing the
--       rotation wants affordable after a GCD of regen - energy + 10 under
--       the frozen Shred/Rake/Rip costs. Dormant in game until the Omen-ICD
--       probe lands (filed follow-up); the offline pins prove the spend math).
--   F7. otherwise -> "shred" (the builder default; the APL 2 s/1 s pooling
--       horizons need Shred/Rip/Rake costs plus the tick phase - tick_remaining
--       rides the tracker's anchor when the sampler runs, costs file their
--       probe, so the builder pools here).
--   UNCONFIRMED (task-brief knowledge, beta docs conflict; in-game to confirm
--   before release): Tiger's Fury is ABSENT on Forever (no rule may ever hold
--   it here - the section-7 sweep pins that), Shifting Power is Cat-only with
--   a 16 s cooldown granting 40 energy for mana (docs/research/forever_beta.md
--   instead says "Shifting Power if <60 energy" with unknown energy values and
--   unknown mana gating - the <= 50 line follows the APL's underCap math, but
--   the 40 gain, the 16 s cooldown and the TF removal are all unverified). No
--   powershifting on Forever (no SHIFT rule exists anywhere since the
--   powershift branches were removed; the sweep pins that no hold ever reads
--   SHIFT). Weapon DPS scales forms on Forever: no weapon input exists, so
--   note only, no guide expression. The mana cost of Shifting Power is not
--   modelled (no mana input; the proven-ready cooldown is necessary but may not
--   be sufficient - in-game to confirm). No Claw rule yet (the claw slot is
--   declared above but can_shred has no position probe - filed follow-up),
--   and no Forever Faerie-Fire Omen-fishing in game yet (F6c below reads the
--   live FF probe plus the still-missing Omen ICD - filed follow-up).
--
-- ERA APPENDIX - cat form only, when family == "ERA" (first match wins):
--   E-FF. The Faerie Fire upkeep (the Era APL's i=0 and i=8): the target's
--       Faerie Fire debuff is absent or has 14 s or less left (the APL's own
--       refresh line - the debuff lasts about 16 s), the Feral Faerie Fire is off
--       cooldown and the player has a target -> hold "FAERIE FIRE" with action nil
--       (the hold overlay carries the call; no FF slot exists).
--   E-LOP. The Leader of the Pack (the Era APL's i=1): the spell is known, the
--       party buff is proven absent and the fight is younger than 90 s (the APL's
--       own window - the buff lasts three minutes) -> hold "LEADER OF THE PACK"
--       with action nil (same slot rationale).
--   E0. clearcast -> "shred" (the Omen of Clarity proc is a free Shred, ahead
--       of the finisher - the sim's first branch).
--   E1. combo_points >= 5 and Rip expired (nil or <= 0, no window) and the
--       fight-elapsed gate (nil = unknown/long -> Rip; < 8 s -> pool, the sim's
--       5CP 8 s fight gate) -> "rip" (the sim's canRip expiry shape; never Bite
--       - the sim's canBite is commented out, there is no Bite branch at all).
--   E2. otherwise -> "shred" (the Era builder, ungated: no verified Era cost
--       exists, so the builder is never withheld for energy; a healthy Rip at
--       5 CP pools here, the sim's Shred fallthrough).
--   REMOVED (was E2, the can_powershift SHIFT call): same dead input as the
--   TBC T6 above - it shared the removed POWERSHIFT_SHORTFALL_TBC constant,
--   which cannot survive its removal (a number > nil raises), so the branch
--   goes with it. Do not re-add without a confirmed Furor basis (the Helm
--   half now has one - see the TBC T6 note).
--   Mangle is never prompted on Era (its ids are TBC+; the code comment at
--   classes/druid.lua pins the tracker bar inert there too, and the Mangle guide
--   icon stays dark because no rule ever lights it). Rake and Bite are never
--   prompted on Era either (no Rake or Bite branch exists in the sim's active
--   rotation). SoD shares the ERA token but HAS
--   Mangle/Savage Roar/Tiger's Fury via runes: with sod_runes it runs the SOD
--   APPENDIX below, never this chain.
--   Bear form on Era is rules 1-2 plus 3e (wait); every non-Era, non-TBC, non-Wrath
--   family runs rules 1-3 / 4-8 unchanged.
--
-- WRATH APPENDIX - cat form only, when family == "WRATH" (first match wins):
--   W1. tf_ready and energy under the dynamic 40 - 10 * leeway line ->
--       hold "TIGER'S FURY" with action nil (no free slot exists, so the hold
--       overlay carries the call; the sim's doTigersFury - leeway is
--       max(gcd_remaining, latency) plus 1 s on Clearcasting; latency is nil
--       until its probe lands, so the line degrades to the GCD alone).
--   W1b. ff_ready and energy under 87 with no proc -> hold "FAERIE FIRE" with
--       action nil (same slot rationale; the sim's ffNow - the 87 line is the
--       sim's ffThresh, the 15-in-Berserk line needs a Berserk-aura input
--       that does not exist here, so the engine always fishes at 87 - filed
--       follow-up; a 5CP Rip due on a long fight outranks the fish unless the
--       bar cannot cover the Rip cost yet, and the end-of-fight spend math
--       withholds the fish when no extra Shred fits before the target dies).
--   W2. berserk_ready and TF on cooldown >= 15 s with Rip up and no proc ->
--       hold "BERSERK" with action nil (same slot rationale; the sim's
--       berserkNow has no energy gate, so the old 85 cap is gone, and the
--       waitForTf phasing is the 15 s TF gate).
--   W3. combo_points >= 1 and Savage Roar expired (nil or <= 0) ->
--       hold "SAVAGE ROAR" with action nil (same slot rationale; the doc's
--       step 3 - no clipping, expiry-only like the TBC Rip).
--   W4. clearcast -> "shred" (the doc's step 4: the Omen of Clarity proc is a
--       free Shred, ahead of the finishers).
--   W5. combo_points >= 5 and Rip expired (nil or <= 0) -> "rip" (the doc's
--       step 5; no energy gate - the guide shows the next action, the pooling
--       shows on the energy tick bar, the TBC-finisher convention).
--   W6. mangle_remaining nil and no FF imminent -> "mangle" (absent outright
--       only, the rule-6 convention - and ABOVE Rake: Mangle's 30% bleed
--       multiplier lifts every Rip/Rake tick, so a missing Mangle outranks a
--       missing Rake; the sim's waitForFf withholds it while FF answers
--       inside the second).
--   W7. Rake expired (nil or <= 0) and no FF imminent -> "rake" (the doc's
--       step 6; no clipping; same waitForFf hold-off).
--   W8. combo_points >= 5 and Rip and Savage Roar both healthy (>= the FB
--       minima below) and the target inside the last-10-seconds execute window
--       -> "bite" (the conditional Ferocious Bite: both bleeds must survive
--       the rebuild after the bite, and the bite itself only pays inside the
--       execute window - docs/research/rotations_wrath.md Notes: "Ferocious
--       Bite only last 10s of fight", "removed from mid-fight rotation").
--   W9. otherwise -> "shred" (the builder default, unless FF answers inside the
--       second: the sim's waitForFf pools the GCD instead of building;
--       pooling shows on the tick bar - the bearweave branch of the doc is
--       NOT built: no bear-form timer/rage input exists here, in-game to
--       confirm).
--   No powershifting on Wrath (Furor no longer refunds on shift): no rule
--   holds SHIFT here, ever. The last-10-seconds clause rides the frozen
--   execute inputs (target_short_lived, time_to_die <= 10); the D4 EMA
--   sampler now feeds time_to_die whenever the target's health is readable,
--   and an unknown target (no target, unreadable health) still defaults to
--   the long fight, so the mid-fight Bite falls through to Shred until the
--   estimate says the target dies inside the window (the research behaviour).
--
-- SOD APPENDIX - cat form only, when family == "ERA" with sod_runes
-- (first match wins; docs/research/rotations_sod.md):
--   S1. tf_ready and energy <= 40 -> hold "TIGER'S FURY" with action nil (King
--       of the Jungle grants +60 energy: 40 is the largest pool that cannot
--       overcap, 100 - 60; same slot rationale as W1).
--   S2. berserk_ready and TF burned (tf_ready == false) -> hold "BERSERK"
--       with action nil (Berserk immediately after TF, the doc's step 7).
--   S3. combo_points >= 1 and Savage Roar expired (nil or <= 0) ->
--       hold "SAVAGE ROAR" with action nil (the doc's step 4).
--   S3b. combo_points >= 1 and Roar clip (current Roar up but expiring before
--       the fight ends while one fresh Roar covers the end - durations per CP
--       in SOD_SR_DURATION: 14/19/24/29/34) -> hold "SAVAGE ROAR" (the sim's
--       clipRoar cover-to-end shape; unknown time-to-die never clips).
--   S4. clearcast -> "shred" (the doc's step 8: Omen procs become Shred).
--   S5. combo_points >= 5 and Rip expired (nil or <= 0, no window) and the
--       fight-elapsed gate (nil = unknown/long -> Rip; < 8 s -> pool, the sim's
--       5CP 8 s fight gate) -> "rip" (the sim's expiry-only canRip - no
--       TF-snapshot term exists there, so a healthy Rip under Tiger's Fury is
--       kept, not refreshed).
--   S6. mangle_remaining nil -> "mangle" (absent outright only, the doc's
--       step 2 ahead of Rake).
--   S7. Rake expired (nil or <= 0) -> "rake" (the doc's step 3; no verified
--       SoD refresh window exists, so expiry-only - in-game to confirm).
--   S8. otherwise -> "shred" (the builder, ungated: no verified SoD energy
--       cost exists, the E2 convention; a capped bar with a healthy Rip pools
--       here - the sim has no Bite branch at all).
--   REMOVED (was S6, the can_powershift SHIFT call at ~0 energy after the
--   tick): same dead input as the TBC T6 above, with its own
--   SOD_POWERSHIFT_MAX_ENERGY constant removed alongside. Do not re-add
--   without a confirmed Furor basis (see the TBC T6 note).
--   Faerie Fire (the pull-only opener), the Glowing Cowl / Catnip use-items
--   and trinket stacking have no guide expression and stay manual.
--
-- SLOT DECISION (seven slots; nextaction_ui.lua header expects other classes at
-- six or fewer, the paladin ships eight): all six original slots are live on
-- Wrath/SoD - Maul is the bear core, and Mangle/Rip/Rake/Bite/Shred all sit
-- in the Wrath cat priority, so no slot is expendable and none is replaced.
-- Claw therefore ships as the seventh slot (Forever front-of-target builder,
-- sim 9850) instead of replacing Shred. Savage Roar, Tiger's Fury, Berserk
-- and Faerie Fire therefore prompt through the hold overlay (the hold-overlay
-- convention), which the rotation text surfaces verbatim (get_rotation_key
-- returns hold_text), instead of through a lit icon.
--
-- BEAR APPENDIX - bear form only, every non-RETAIL family (first match wins):
--   B1. maul_queued -> hold "RIDE" (rule 1 above; every family, Era included) - the
--       press-nothing hold: the player presses NO key.
--   B2. proven-affordable Maul -> "maul" (rule 2 above; every family).
--   B3. otherwise, a client WITH Mangle -> "mangle" (rule 3 above: Wrath, TBC,
--       Cata, Mists - the only bear fallback the rotational slots can name).
--   B3e. otherwise, on a client with NO Mangle -> wait (rule 3e above: no
--       Mangle on runeless Era and none at all on the FOREVER client).
--   TBC bear runs B1-B3 unchanged: Mangle (Bear) is TBC+ (the module's Mangle
--   ids 33983/33987 resolve there and the 12 s tracker fallback is the
--   reference's TBC-era debuff length), and Lacerate/Swipe/Bash carry no guide
--   slot (the seven-slot contract names no Lacerate/Swipe/Bash), so no TBC
--   bear rule names them.
--   Era bear runs B1-B2 plus B3e: Maul/Swipe exist but Swipe has no slot, so
--   short of Maul rage the guide pools instead of guessing. SoD shares the
--   ERA token but HAS Mangle via rune: with sod_runes it rides rule 3 (not 3e),
--   so the SoD bear falls back to Mangle; runeless Era keeps B3e.
--   The FOREVER bear rides B3e too (HU-14, closed 2026-10-20): the Forever
--   client has no Mangle spell, so the bear chain pools instead of naming one.
--   Unlike the cat Mangle (rule 6, absent-only), the bear fallback has no
--   debuff-absence gate: it prompts whenever Maul is unproven. That is the
--   Wrath-pinned behaviour and stays byte-identical here; whether a healthy
--   Mangle debuff should suppress it on TBC is in-game to confirm.
--   UNCONFIRMED (own feral-tank knowledge, no offline source; in-game to
--   confirm before release): the 33878/33987 bear-vs-cat rank split, the TBC
--   Mangle (Bear) cooldown and exact debuff length, Cata/Mists bear keeping
--   rule 3 (Thrash and the MoP rework unassessed).
--
--   Retail (12.x) inertness: st.family == "RETAIL" short-circuits evaluate to the
--   empty display shape before any rule below. The inert stand-in never reports a
--   swing, but rage/energy costs (bear rule 2, TBC rules T2/T5), the queue flag
--   (bear rule 1) and the absent-debuff defaults (cat rules 4-6, where nil always
--   refreshes) all answer on Retail, so those rules would prompt with no swing at
--   all. Every other family runs the matrix above unchanged; a nil family (offline
--   callers that predate it) keeps the old behaviour too.
--
-- Output: the frozen display fields are overwritten on every call:
--   action, hold, hold_text, filler_slot = nil, judge_slot = nil, rotation_key = nil,
--   waiting_judgement = false.
--=========================================================================================
local _, st = ...

st.druid_guide = st.druid_guide or {}

-- Rule constants (frozen; the options panel exposes only the two refresh thresholds).
st.druid_guide.RIP_REFRESH_DEFAULT = 4
st.druid_guide.RAKE_REFRESH_DEFAULT = 4

-- TBC cat costs from the TBC 2.5.6 spell data: Mangle (Cat) 40 energy, Shred
-- 42 energy. Rip (30) and Ferocious Bite (35) are named, never gated: the guide
-- shows the next action, it never withholds a finisher for energy (the energy
-- tick bar shows the pooling instead).
st.druid_guide.MANGLE_COST_TBC = 40
st.druid_guide.SHRED_COST_TBC = 42
-- The 2pc-T6 bonus cuts Mangle (Cat) to 35 energy
-- (docs/research/tbc_minmax.md: "2pc T6 reduces Mangle cost by 5 (35
-- energy) -> non-Wolfshead rotation"). The engine never hardcodes the
-- cheaper prompt: T2 spends inputs.mangle_cost when the gather proves it
-- live, else MANGLE_COST_TBC above. Whether the client reports the reduced
-- cost through GetSpellPowerCost is in-game to confirm.
st.druid_guide.MANGLE_COST_T6_2PC_TBC = 35
-- TBC Rip threshold groundwork (sim user-config RipMinComboPoints): the frozen
-- 4 keeps every offline caller byte-identical; a future option writes
-- inputs.rip_min_cp (OUT OF SCOPE - filed follow-up) and T1 reads it. Clamped
-- to 2-5: below 2 would Rip on builders, above 5 could never Rip.
st.druid_guide.RIP_MIN_CP_TBC = 4
-- Fight-elapsed gates (sim canRip fight clocks): Era/SoD 5CP needs the fight
-- older than 8 s, Forever 5CP needs 10 s (wowsims classic/sod rotation.go,
-- forever apl_sweep_test.go catAPL). Nil (no stamp yet, out of combat) defaults
-- to the long fight and Rips - the documented E1/S5/F3 shape, never a withheld
-- finisher on unknown.
st.druid_guide.FIGHT_ELAPSED_ERA_SECONDS = 8
st.druid_guide.FIGHT_ELAPSED_FOREVER_SECONDS = 10
-- Short-lived means dying inside the sim's 10 s end threshold (see below);
-- the powershift branches and their shortfall constants were removed (see the
-- REMOVED notes in the appendices above), so no powershift constant ships
-- anymore. The sim's RipEndThresh is 10 s (tbc-new feralcat/rotation.go);
-- a target dying sooner takes the Bite there.
st.druid_guide.SHORT_LIVED_TTD_SECONDS = 10

-- Wrath cat lines (docs/research/rotations_wrath.md EJ decision tree, corrected
-- against the sim wowsims/wotlk feral/rotation.go): Tiger's Fury under a
-- dynamic 40 - 10 * leeway line (leeway = gcd_remaining + 1 s on Clearcasting;
-- latency has no probe yet, filed follow-up), Berserk once Tiger's Fury has
-- been on cooldown for 15 s or more with Rip up and no proc (the sim's
-- berserkNow has no energy gate, so the old 85 cap is gone with its rationale).
st.druid_guide.TF_ENERGY_WRATH = 40
st.druid_guide.TF_CD_GATE_BERSERK_SECONDS = 15
-- The conditional Ferocious Bite needs both Rip and Savage Roar healthy enough
-- to survive the post-bite rebuild: 4 s each (the sim's BiteTime).
st.druid_guide.FB_RIP_MIN_SECONDS = 4
st.druid_guide.FB_SR_MIN_SECONDS = 4
-- The Wrath execute window for that Bite: the last 10 s of the fight
-- (docs/research/rotations_wrath.md Notes: "Ferocious Bite only last 10s of
-- fight"). Unknown defaults to the long fight (nil time_to_die is never
-- execute, the TBC short-lived convention).
st.druid_guide.FB_EXECUTE_TTD_SECONDS = 10
-- SoD cat lines (docs/research/rotations_sod.md): Tiger's Fury at or under 40
-- energy (King of the Jungle grants +60: 100 - 60 cannot overcap).
st.druid_guide.TF_ENERGY_SOD = 40
-- Forever cat lines (UNCONFIRMED task-brief knowledge, beta docs conflict -
-- see the FOREVER APPENDIX in the module header): Shifting Power is ASSUMED
-- to grant 40 energy, so 60 is the largest pool that fits it (100 - 40 cannot
-- overcap - the SoD TF convention; docs/research/forever_beta.md prose says
-- "Shifting Power if <60 energy" with unknown values). No client source
-- publishes either number: F1 gates the call behind the Shifting Power
-- knowledge probe (sp_ready, proven via the GetSpellInfo name query - the
-- only probe Forever exposes, since no spell id is published), but the 60/40
-- values themselves are assumed until confirmed in-game. The invariant below
-- (60 == 100 - 40) is pinned by tests/druid_guide_state.lua.
-- Forever cat lines (sim wowsims/forever feralcat/apl_sweep_test.go catAPL
-- underCap math): Shifting Power with room for its 40 energy gain, ceiling 50
-- (40 on Clearcasting - the proc keeps filling through the GCD, so the headroom
-- grows by 10). The 50 leaves 10-regen headroom over the GCD per the APL; the
-- 40 gain, the 16 s cooldown and the mana cost stay UNCONFIRMED (see the
-- FOREVER APPENDIX in the module header).
st.druid_guide.SP_ENERGY_GAIN_FOREVER = 40
st.druid_guide.SP_ENERGY_FOREVER = 50
st.druid_guide.SP_ENERGY_FOREVER_CLEARCAST = 40
-- SoD Savage Roar durations by combo points (sim sod savage_roar.go:
-- 9 + 5/CP -> 14/19/24/29/34 s; 25 energy): the fresh-Roar length the S3b
-- clip math compares against the time-to-die.
st.druid_guide.SOD_SR_DURATION = { 14, 19, 24, 29, 34 }
-- Forever bite-low: 3+ CP dumped inside the last 3 s (the APL biteLow rule).
st.druid_guide.FOREVER_BITE_LOW_TTD_SECONDS = 3
-- Faerie Fire Omen-fishing (sim wowsims/wotlk feral/rotation.go ffNow +
-- wowsims/forever feralcat/apl_sweep_test.go omenFish): the Wrath fish line
-- is 87 energy (the sim's ffThresh; the 15-in-Berserk line needs a
-- Berserk-aura input that does not exist here - filed follow-up, so the
-- engine always fishes at 87); the wait/soon horizon is 1 s with a 0.1 s
-- MaxFfDelay (the sim forces MaxFfDelay 100ms); the SP-left gate is 1 s (the
-- sim's spellLeft(SP) >= 1s); the post-GCD regen is 10 energy (one GCD at
-- 10/s). Shred 42 is the TBC-verified cost (SHRED_COST_TBC); Rip 30 is named
-- in the TBC MICRO note; Rake 40 is the classic energy cost - all three ride
-- Wrath/Forever UNCONFIRMED (no live-cost probe exists there; whether the
-- clients report them through GetSpellPowerCost is in-game to confirm).
st.druid_guide.FF_ENERGY_WRATH = 87
st.druid_guide.FF_WAIT_SECONDS = 1
st.druid_guide.FF_MAX_DELAY_SECONDS = 0.1
st.druid_guide.FF_SP_LEFT_SECONDS = 1
st.druid_guide.FF_REGEN_ENERGY = 10
st.druid_guide.FF_SHRED_COST = 42
st.druid_guide.FF_RIP_COST = 30
st.druid_guide.FF_RAKE_COST = 40
-- The APL utility layer's frozen lines (the rotation table's utility spine in
-- classes/druid.lua; every value below is the APL's own, cited there):
--   LOP_FIGHT_WINDOW_ERA_SECONDS  the Leader of the Pack row's own gate: the Era APL
--                                 casts it while the fight is younger than 90 s (the
--                                 buff lasts three minutes, so it covers the fight)
--   FF_REFRESH_ERA_SECONDS        the Era APL's Faerie Fire row i=8: refresh the
--                                 Feral Faerie Fire when the target's debuff has 14 s
--                                 or less left (the debuff lasts about 16 s)
--   INNERVATE_MANA_FRACTION       the mana line the Innervate rows carry: 40 % or
--                                 less (the Era and SoD APLs' own condition)
st.druid_guide.LOP_FIGHT_WINDOW_ERA_SECONDS = 90
st.druid_guide.FF_REFRESH_ERA_SECONDS = 14
st.druid_guide.INNERVATE_MANA_FRACTION = 0.40

-- A threshold input: the caller's number, else the frozen default. 0 is a real value
-- (refresh only when the debuff is absent outright).
local function threshold(value, default)
    if type(value) == "number" then
        return value
    end
    return default
end

-- TBC: energy affordability is a proof, never a guess: the reading must be a
-- number that covers the cost. (NaN covers nothing: every comparison is false.)
local function tbc_can_spend(inputs, cost)
    local energy = inputs.energy
    return type(energy) == "number" and energy >= cost
end

-- TBC: the Mangle affordability line: the gather's live cost when it proves
-- one (the 2pc-T6 35), else the frozen 40. A non-number (nil, NaN-proofed by
-- the comparison below: NaN covers nothing) never lowers the line.
local function tbc_mangle_cost(inputs)
    if type(inputs.mangle_cost) == "number" then
        return inputs.mangle_cost
    end
    return st.druid_guide.MANGLE_COST_TBC
end

-- TBC: short-lived means Rip never pays back: an explicit flag, or a
-- time-to-die inside the sim's 10 s end threshold. Anything unknown defaults to
-- the long fight (nil is never short-lived).
local function tbc_target_is_short_lived(inputs)
    if inputs.target_short_lived == true then
        return true
    end
    local remaining = inputs.time_to_die
    return type(remaining) == "number"
        and remaining <= st.druid_guide.SHORT_LIVED_TTD_SECONDS
end

-- Wrath: execute means the Bite pays back: an explicit short-lived flag, or a
-- time-to-die inside the last-10-seconds window. Anything unknown defaults to
-- the long fight (nil is never execute).
local function wrath_target_is_execute(inputs)
    if inputs.target_short_lived == true then
        return true
    end
    local remaining = inputs.time_to_die
    return type(remaining) == "number"
        and remaining <= st.druid_guide.FB_EXECUTE_TTD_SECONDS
end

-- TBC: the Rip threshold: the caller's override (the future RipCP option),
-- else the frozen 4. Clamped to 2-5 so a junk number can neither Rip on
-- builders nor deadlock the finisher; NaN-safe (NaN is not a number).
local function tbc_rip_min_cp(inputs)
    local cp = inputs.rip_min_cp
    if type(cp) == "number" and cp == cp and cp >= 2 and cp <= 5 then
        return cp
    end
    return st.druid_guide.RIP_MIN_CP_TBC
end

-- Fight-elapsed gate (sim canRip fight clocks): a young fight withholds the
-- 5CP Rip (pool instead). Unknown (nil, NaN, out of combat) defaults to the
-- long fight and Rips - never a withheld finisher on unknown.
local function fight_is_young(inputs, gate)
    local elapsed = inputs.fight_elapsed
    return type(elapsed) == "number" and elapsed == elapsed
        and elapsed < gate
end

-- Wrath: the dynamic Tiger's Fury line (sim wotlk feral/rotation.go doTigersFury:
-- energy < 40 - 10 * leeway, leeway = max(gcdLeft, latency) + 1 s on Clearcasting).
-- The gather feeds gcd_remaining, latency (nil until its probe lands) and
-- clearcast. A NaN or unreadable input contributes nothing, so the line
-- degrades to the frozen 40.
local function wrath_tf_threshold(inputs)
    local leeway = 0
    local gcd = inputs.gcd_remaining
    if type(gcd) == "number" and gcd == gcd and gcd > leeway then
        leeway = gcd
    end
    local latency = inputs.latency
    if type(latency) == "number" and latency == latency and latency > leeway then
        leeway = latency
    end
    if inputs.clearcast == true then
        leeway = leeway + 1
    end
    return st.druid_guide.TF_ENERGY_WRATH - 10 * leeway
end

-- SoD: the fresh Savage Roar length at the current combo points (the SOD_SR_DURATION
-- table above, indexed 1-5; above-5 caps at 5CP). Anything unreadable answers nil -
-- the clip math then stays dormant, never a guess.
local function sod_sr_duration(combo_points)
    if type(combo_points) ~= "number" or combo_points ~= combo_points then
        return nil
    end
    if combo_points >= 5 then
        return st.druid_guide.SOD_SR_DURATION[5]
    elseif combo_points >= 4 then
        return st.druid_guide.SOD_SR_DURATION[4]
    elseif combo_points >= 3 then
        return st.druid_guide.SOD_SR_DURATION[3]
    elseif combo_points >= 2 then
        return st.druid_guide.SOD_SR_DURATION[2]
    elseif combo_points >= 1 then
        return st.druid_guide.SOD_SR_DURATION[1]
    end
    return nil
end

-- SoD: the Roar-clip call (sim clipRoar, cover-to-end shape): the current Roar is
-- still up but expires before the fight ends, while one fresh Roar cast now would
-- cover the end - refreshing early saves a full cast. Unknown time-to-die, an
-- expired Roar (S3 owns that), sub-1CP or an unreadable combo count never clips.
local function sod_should_clip_roar(inputs)
    local sr = inputs.sr_remaining
    if type(sr) ~= "number" or sr ~= sr or sr <= 0 then
        return false
    end
    local ttd = inputs.time_to_die
    if type(ttd) ~= "number" or ttd ~= ttd then
        return false
    end
    local fresh = sod_sr_duration(inputs.combo_points)
    if fresh == nil then
        return false
    end
    return sr < ttd and ttd <= fresh
end

-- Forever: the Shifting Power ceiling (sim forever underCap math): 50 normally,
-- 40 on Clearcasting (the proc keeps filling through the GCD).
local function forever_sp_ceiling(inputs)
    if inputs.clearcast == true then
        return st.druid_guide.SP_ENERGY_FOREVER_CLEARCAST
    end
    return st.druid_guide.SP_ENERGY_FOREVER
end

-- Wrath: the Faerie Fire Omen-fishing call (sim wotlk feral/rotation.go
-- ffNow): proven-ready FF, no proc, under the 87 line, a 5CP Rip due on a
-- long fight deferred unless the bar cannot cover the Rip cost yet, and the
-- end-of-fight spend math (an extra FF GCD must buy an extra Shred before
-- the target dies; unknown time-to-die defaults to the long fight and
-- fishes, an explicit short-lived flag with no readable clock spends
-- nothing). Anything unreadable hides the call, never a guessed FF.
local function wrath_ff_now(inputs)
    if inputs.ff_ready ~= true then
        return false
    end
    if inputs.clearcast == true then
        return false
    end
    local energy = inputs.energy
    if type(energy) ~= "number" or energy ~= energy then
        return false
    end
    if energy >= st.druid_guide.FF_ENERGY_WRATH then
        return false
    end
    -- Rip deferral (sim (!ripNow || energy < ripCost)): a 5CP Rip due
    -- outranks the fish unless the bar cannot cover the Rip cost yet.
    local cp = inputs.combo_points
    if type(cp) == "number" and cp >= 5
        and (type(inputs.rip_remaining) ~= "number"
            or inputs.rip_remaining <= 0)
        and energy >= st.druid_guide.FF_RIP_COST then
        return false
    end
    -- End-of-fight spend math (sim ffNow post-check): an extra FF GCD must
    -- buy an extra Shred before the target dies.
    local ttd = inputs.time_to_die
    if inputs.target_short_lived == true and type(ttd) ~= "number" then
        ttd = 0
    end
    if type(ttd) == "number" and ttd == ttd then
        if ttd < 0 then
            return false
        end
        local cost = st.druid_guide.FF_SHRED_COST
        local max_shreds = math.floor((energy + ttd * 10) / cost)
        local without = math.min(max_shreds, math.floor(ttd) + 1)
        local with = math.min(max_shreds + 1, math.floor(ttd))
        if with <= without then
            return false
        end
    end
    return true
end

-- Wrath: the FF-imminent hold-off (sim wotlk waitForFf): FF proven on a
-- short cooldown (< 1 s minus the 0.1 s MaxFfDelay) with the post-GCD energy
-- still under the 87 line, no proc, and Rip not falling inside the second (a
-- Rip due now outranks the wait). While true the chain pools (nil action, no
-- hold) until FF answers. Unknown inputs never wait.
local function wrath_wait_for_ff(inputs)
    if inputs.clearcast == true then
        return false
    end
    local cd = inputs.ff_cd_remaining
    if type(cd) ~= "number" or cd ~= cd or cd <= 0
        or cd >= st.druid_guide.FF_WAIT_SECONDS
            - st.druid_guide.FF_MAX_DELAY_SECONDS then
        return false
    end
    local energy = inputs.energy
    if type(energy) ~= "number" or energy ~= energy then
        return false
    end
    local latency = inputs.latency
    if type(latency) ~= "number" or latency ~= latency then
        latency = 0
    end
    if energy + (cd + latency) * 10 >= st.druid_guide.FF_ENERGY_WRATH then
        return false
    end
    local rip = inputs.rip_remaining
    if type(rip) == "number" and rip == rip and rip > 0
        and rip <= st.druid_guide.FF_WAIT_SECONDS then
        return false
    end
    return true
end

-- Forever: the Faerie Fire Omen-fishing call (sim forever
-- feralcat/apl_sweep_test.go omenFish): proven-ready FF, no proc, the Omen
-- ICD ready, Shifting Power not coming inside 1 s, and nothing the rotation
-- wants affordable after a GCD of regen. Anything unreadable hides the call,
-- never a guessed FF.
local function forever_omen_fish(inputs)
    if inputs.ff_ready ~= true then
        return false
    end
    if inputs.clearcast == true then
        return false
    end
    if inputs.omen_icd_ready ~= true then
        return false
    end
    local sp_left = inputs.sp_cd_remaining
    if type(sp_left) ~= "number" or sp_left ~= sp_left
        or sp_left < st.druid_guide.FF_SP_LEFT_SECONDS then
        return false
    end
    local energy = inputs.energy
    if type(energy) ~= "number" or energy ~= energy then
        return false
    end
    local regen = energy + st.druid_guide.FF_REGEN_ENERGY
    if regen >= st.druid_guide.FF_SHRED_COST then
        return false
    end
    -- Rake/rip soon (sim rakeSoon/ripSoon, 1 s horizons): a refresh due
    -- inside the second outranks the fish unless it too is unaffordable
    -- after the regen.
    local rake = inputs.rake_remaining
    local rake_soon = type(rake) ~= "number" or rake ~= rake or rake <= 0
        or rake < st.druid_guide.FF_WAIT_SECONDS
    if rake_soon and regen >= st.druid_guide.FF_RAKE_COST then
        return false
    end
    local cp = inputs.combo_points
    local rip = inputs.rip_remaining
    local rip_up = type(rip) == "number" and rip == rip and rip > 0
    local rip_soon = type(cp) == "number" and cp >= 5
        and not fight_is_young(inputs,
            st.druid_guide.FIGHT_ELAPSED_FOREVER_SECONDS)
        and (not rip_up or rip < st.druid_guide.FF_WAIT_SECONDS)
    if rip_soon and regen >= st.druid_guide.FF_RIP_COST then
        return false
    end
    return true
end

-- Does the running client have a Mangle spell at all? False = it does not, so no
-- rule may ever name it (the guide's Mangle prompts are the cat chains'
-- debuff-absence rules and this bear fallback). Runeless Era has no Mangle (the
-- module's Mangle ids 33983/33987 are TBC+) and the FOREVER client has no
-- Mangle spell AT ALL: the Forever sim carries no Mangle table and no
-- per-ability file (wowsims/forever sim/druid/spell_data_auto_gen.go - the
-- FaerieFire ladder is 770/778/9749/9907 and the LeaderOfThePack ladder is
-- 17007), the Forever APL's own builders are 9830 Shred and 9850 Claw
-- (wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=9, the
-- Builders group) and the APL carries no Mangle row anywhere. SoD shares the
-- Era token but proves Mangle through its rune (sod_runes), so it is not a
-- Mangle-less client.
local function druid_client_has_mangle(inputs)
    if inputs.family == "FOREVER" then
        return false
    end
    if inputs.family == "ERA" and inputs.sod_runes ~= true then
        return false
    end
    return true
end

-- The Cat Form upkeep (the APL's form row: the Era APL's i=14, the SoD APL's
-- i=0, the TBC APL's Powershifting group and the Forever APL's i=1 - all of
-- them "cast the Cat Form when the Cat Form aura is not active"). Three proofs
-- must hold before the call shows, so a caster druid is never nagged:
--   feral_spec      the class's own spec probe (true only when the player
--                   proves Feral-tree points through the client's spell
--                   knowledge - a resto or a balance druid never has them)
--   cat_form_active the player's own aura walk proves the Cat Form aura is
--                   ABSENT (false); nil = the walk has not answered, and an
--                   unknown never prompts
--   the form        the humanoid form (0) or the travel form (4): the bear form
--                   belongs to the bear chain, the cat form is already there,
--                   and the tree/moonkin (5) and flight (6) forms are not the
--                   cat rotation's
-- The APL order against the Innervate row is the caller's business (the Cat
-- Form row sits above the Innervate on SoD and Forever and below it on Era).
local function druid_cat_form_wanted(inputs, form)
    if inputs.feral_spec ~= true then
        return false
    end
    if inputs.cat_form_active ~= false then
        return false
    end
    if form ~= 0 and form ~= 4 then
        return false
    end
    if inputs.family == "ERA" or inputs.family == "TBC" or inputs.family == "FOREVER" then
        return true
    end
    -- The WotLK APL carries no Cat Form row (and no other family does).
    return false
end

-- The APL utility layer's arms (the rotation table's utility spine in
-- classes/druid.lua). Every one of them is a HOLD: the class has no guide slot for
-- the line, so the hold overlay carries the call (the TIGER'S FURY / SAVAGE ROAR
-- convention) and the rotation text surfaces it verbatim.
--
-- The Faerie Fire upkeep (the Era APL's i=0/i=8 and the TBC APL's i=2): the target
-- does not carry the Faerie Fire debuff (or, on Era, it is about to drop), the
-- Feral Faerie Fire is off cooldown and the player has a target. Unknown hides:
-- an unreadable debuff (the walk has not answered), an unreadable cooldown or a
-- missing target never prompts.
local function druid_ff_upkeep_wanted(inputs, form)
    if inputs.family ~= "TBC" then
        -- The Era APL carries the row; the SoD APL has no Faerie Fire row at all
        -- (its i=0 is the Cat Form row) and the SoD shares the Era token.
        if inputs.family ~= "ERA" or inputs.sod_runes == true then
            return false
        end
    end
    if form ~= 3 then
        return false
    end
    if inputs.has_target ~= true then
        return false
    end
    if inputs.feral_ff_ready ~= true then
        return false
    end
    local remaining = inputs.ff_debuff_remaining
    if remaining == nil then
        -- Unknown: the target walk has not answered yet (nil is the "not answered"
        -- answer - the gather publishes false for a proven absent debuff).
        return false
    end
    if remaining == false then
        -- The walk answered: the target carries no Faerie Fire debuff, so the
        -- upkeep is due.
        return true
    end
    if type(remaining) ~= "number" or remaining ~= remaining then
        return false
    end
    if inputs.family == "TBC" then
        -- The TBC APL's row fires only when the debuff is inactive.
        return false
    end
    -- The Era APL's row refreshes the debuff before it drops (14 s or less left).
    return remaining <= st.druid_guide.FF_REFRESH_ERA_SECONDS
end

-- The Leader of the Pack (the Era APL's i=1 row): the spell is known, the party buff
-- is proven absent and the fight is younger than the APL's own window (90 s - the
-- buff lasts three minutes, so casting it early covers the fight). The SoD shares
-- the Era token and has no Leader of the Pack row.
local function druid_lop_wanted(inputs)
    if inputs.family ~= "ERA" or inputs.sod_runes == true then
        return false
    end
    if inputs.lop_known ~= true then
        return false
    end
    if inputs.lop_active ~= false then
        return false
    end
    local elapsed = inputs.fight_elapsed
    if type(elapsed) ~= "number" or elapsed ~= elapsed then
        return false
    end
    return elapsed <= st.druid_guide.LOP_FIGHT_WINDOW_ERA_SECONDS
end

-- The Innervate (the Era, SoD and Forever APLs' mana row): the cooldown is ready
-- and the mana is short (the APLs' own 40 % line). The bear form is never touched
-- (the bear rules own it) and the Era row is a caster row (outside the cat form),
-- while the SoD row (the same family token plus the runes) and the Forever row are
-- cat rows.
local function druid_innervate_wanted(inputs, form)
    if inputs.innervate_ready ~= true then
        return false
    end
    local mana = inputs.mana_percent
    if type(mana) ~= "number" or mana ~= mana then
        return false
    end
    if mana > st.druid_guide.INNERVATE_MANA_FRACTION then
        return false
    end
    if form == 1 then
        return false
    end
    if inputs.family == "ERA" then
        if inputs.sod_runes ~= true and form == 3 then
            return false
        end
        return true
    end
    if inputs.family == "FOREVER" then
        return true
    end
    return false
end

-- Pure: one engine tick. Reads `inputs`, writes the frozen display fields into the
-- caller-owned `out` table and returns it. See the module header for the rule matrix.
function st.druid_guide.evaluate(inputs, out)
    inputs = inputs or {}
    if type(out) ~= "table" then
        out = {}
    end

    if st.family == "RETAIL" then
        -- Retail (12.x): no live swing exists (see the header), so no rule may
        -- prompt - not an action, not a HOLD/RIDE/SHIFT overlay.
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
    local form = inputs.form_index

    -- The Cat Form upkeep (the APL's form row) and the Innervate (the mana row)
    -- are ordered by the APLs themselves, not by a fixed rank: the Cat Form row
    -- sits ABOVE the Innervate on SoD (i=0 vs i=4) and on Forever (i=1 vs i=10)
    -- and BELOW it on Era (i=14 vs i=13, where the Innervate is the caster row
    -- outside the cat form). The TBC APL has no Innervate row and the WotLK APL
    -- has no Cat Form row, so those two pairings never overlap.
    local cat_form_wanted = druid_cat_form_wanted(inputs, form)
    local cat_form_first = inputs.family == "FOREVER" or inputs.sod_runes == true

    if cat_form_wanted and cat_form_first then
        -- The Cat Form upkeep: the player is a proven Feral-tree druid, the Cat
        -- Form aura is proven absent and the form is the humanoid or the travel
        -- form. The hold overlay carries the call (no free slot exists, the
        -- TIGER'S FURY convention).
        hold = true
        hold_text = "CAT FORM"
    elseif druid_innervate_wanted(inputs, form) then
        -- The Innervate (the APL utility layer's mana row): the cooldown is ready
        -- and the mana is short. The hold overlay carries the call (no free slot
        -- exists, the TIGER'S FURY convention).
        hold = true
        hold_text = "INNERVATE"
    elseif form == 1 then
        if inputs.maul_queued == true then
            -- 1. A queued Maul is already riding the next swing: ride it. RIDE is
            -- the press-nothing hold - the player presses NO key (the guide names
            -- the spell to press in every other hold).
            hold = true
            hold_text = "RIDE"
        else
            -- 2. Maul only when the gathered numbers prove it affordable; the module's
            -- shortfall flag can veto a proof but never stand in for one.
            local rage = inputs.rage
            local cost = inputs.maul_cost
            local sufficient = type(rage) == "number" and type(cost) == "number"
                and rage >= cost and inputs.insufficient_rage ~= true
            if sufficient then
                action = "maul"
            elseif druid_client_has_mangle(inputs) == false then
                -- 3e. A client with NO Mangle spell: pool rage instead of guessing
                -- a spell the client cannot know (wait: nil, no hold). Runeless Era
                -- (the module's Mangle ids 33983/33987 are TBC+) and the FOREVER
                -- client (no Mangle spell at all - the Forever sim carries no
                -- Mangle table and the Forever APL's builders are 9830 Shred and
                -- 9850 Claw) wait here. SoD shares the Era token but proves Mangle
                -- via rune and rides rule 3 below.
                action = nil
            else
                -- 3. The bear fallback.
                action = "mangle"
            end
        end
    elseif form == 3 then
        if inputs.family == "TBC" then
            -- TBC cat chain; see the TBC APPENDIX in the module header.
            local cp = inputs.combo_points
            if type(cp) ~= "number" then
                cp = 0
            end
            local rip_remaining = inputs.rip_remaining
            local rip_expired = type(rip_remaining) ~= "number" or rip_remaining <= 0
            if druid_ff_upkeep_wanted(inputs, form) then
                -- The Faerie Fire upkeep (the TBC APL's i=2: the target does not
                -- carry the Faerie Fire debuff). The hold overlay carries the call.
                hold = true
                hold_text = "FAERIE FIRE"
            elseif cp >= tbc_rip_min_cp(inputs) and rip_expired then
                -- T1. rip_min_cp+ CP with Rip expired: Rip (expiry-only, never a
                -- window; the threshold defaults to the frozen 4 until its option
                -- ships - filed follow-up).
                action = "rip"
            elseif inputs.mangle_remaining == nil
                and tbc_can_spend(inputs, tbc_mangle_cost(inputs)) then
                -- T2. Mangle absent and affordable: 40 energy, or the live
                -- cost (the 2pc-T6 35) when the gather proves one.
                action = "mangle"
            elseif cp >= 5 and tbc_target_is_short_lived(inputs) then
                -- T3. 5 CP on a short-lived target: the only TBC Bite.
                action = "bite"
            elseif cp >= 5 then
                -- T4. 5 CP on a long fight: always Rip, never Bite.
                action = "rip"
            elseif tbc_can_spend(inputs, st.druid_guide.SHRED_COST_TBC) then
                -- T5. Affordable at the TBC 42-energy cost: build with Shred.
                action = "shred"
            end
            -- T6. Otherwise: wait (action nil, no hold); pool, do not guess.
            -- (The old T6 powershift call was removed with its constant: the
            -- Furor half of the basis has no honest probe - the Wolfshead
            -- half has one and stays reserved - see the REMOVED note in the
            -- TBC APPENDIX above.)
        elseif inputs.family == "ERA" and inputs.sod_runes == true then
            -- SOD cat chain; see the SOD APPENDIX in the module header.
            local cp = inputs.combo_points
            if type(cp) ~= "number" then
                cp = 0
            end
            local energy = inputs.energy
            local sr = inputs.sr_remaining
            local sr_expired = type(sr) ~= "number" or sr <= 0
            if inputs.tf_ready == true and type(energy) == "number"
                and energy <= st.druid_guide.TF_ENERGY_SOD then
                -- S1. Tiger's Fury at or under 40 energy (King of the Jungle
                -- grants +60: 40 cannot overcap); the hold overlay carries the
                -- call, action stays nil.
                hold = true
                hold_text = "TIGER'S FURY"
            elseif inputs.berserk_ready == true and inputs.tf_ready == false then
                -- S2. Berserk immediately after Tiger's Fury (TF burned); the
                -- hold overlay carries the call, action stays nil.
                hold = true
                hold_text = "BERSERK"
            elseif cp >= 1 and sr_expired then
                -- S3. Savage Roar expired with combo points to spend; the hold
                -- overlay carries the call, action stays nil.
                hold = true
                hold_text = "SAVAGE ROAR"
            elseif cp >= 1 and sod_should_clip_roar(inputs) then
                -- S3b. Roar clip: the current Roar expires before the fight ends
                -- but one fresh Roar covers it (durations per CP in
                -- SOD_SR_DURATION above) - refreshing early saves a full cast.
                -- Unknown time-to-die never clips (expiry-only there).
                hold = true
                hold_text = "SAVAGE ROAR"
            elseif inputs.clearcast == true then
                -- S4. Omen of Clarity proc: a free Shred, ahead of the finishers.
                action = "shred"
            elseif cp >= 5 and (type(inputs.rip_remaining) ~= "number"
                or inputs.rip_remaining <= 0)
                and not fight_is_young(inputs,
                    st.druid_guide.FIGHT_ELAPSED_ERA_SECONDS) then
                -- S5. 5 CP Rip expired on a proven-old fight: Rip, never clipped
                -- (the sim's expiry-only canRip - no TF-snapshot term exists
                -- there, so a healthy Rip under Tiger's Fury is kept, not
                -- refreshed). A young fight (< 8 s) or an unknown clock pools
                -- to the builder below (unknown defaults to the long fight and
                -- Rips - the documented shape).
                action = "rip"
            elseif inputs.mangle_remaining == nil then
                -- S6. An absent Mangle prompts it, ahead of Rake.
                action = "mangle"
            elseif type(inputs.rake_remaining) ~= "number"
                or inputs.rake_remaining <= 0 then
                -- S7. Rake expired (no verified SoD window, so expiry-only).
                action = "rake"
            else
                -- S8. Anything else: build with Shred, ungated (no verified
                -- SoD cost exists, so the builder is never withheld for energy;
                -- a capped bar with a healthy Rip pools here - the sim has no
                -- Bite branch at all).
                action = "shred"
            end
        elseif inputs.family == "ERA" then
            -- ERA cat chain; see the ERA APPENDIX in the module header.
            local cp = inputs.combo_points
            if type(cp) ~= "number" then
                cp = 0
            end
            if druid_ff_upkeep_wanted(inputs, form) then
                -- The Faerie Fire upkeep (the Era APL's i=0 and i=8: the refresh
                -- before the debuff drops). The hold overlay carries the call.
                hold = true
                hold_text = "FAERIE FIRE"
            elseif druid_lop_wanted(inputs) then
                -- The Leader of the Pack (the Era APL's i=1: the party buff, cast
                -- early in the fight). The hold overlay carries the call.
                hold = true
                hold_text = "LEADER OF THE PACK"
            elseif inputs.clearcast == true then
                -- E0. Omen of Clarity proc: a free Shred, ahead of the finisher
                -- (the sim's first branch).
                action = "shred"
            elseif cp >= 5 and (type(inputs.rip_remaining) ~= "number"
                or inputs.rip_remaining <= 0)
                and not fight_is_young(inputs,
                    st.druid_guide.FIGHT_ELAPSED_ERA_SECONDS) then
                -- E1. 5 CP with Rip expired on a proven-old fight: Rip, never
                -- clipped (the sim's canRip expiry shape; a young fight
                -- (< 8 s) pools to the builder below, unknown defaults to the
                -- long fight and Rips).
                action = "rip"
            else
                -- E2. Anything else: build with Shred, ungated (no verified Era
                -- cost exists, so the builder is never withheld for energy; a
                -- healthy Rip at 5 CP pools here, the sim's Shred fallthrough).
                action = "shred"
            end
        elseif inputs.family == "WRATH" then
            -- WRATH cat chain; see the WRATH APPENDIX in the module header.
            local cp = inputs.combo_points
            if type(cp) ~= "number" then
                cp = 0
            end
            local energy = inputs.energy
            local sr = inputs.sr_remaining
            local sr_expired = type(sr) ~= "number" or sr <= 0
            if inputs.tf_ready == true and type(energy) == "number"
                and energy < wrath_tf_threshold(inputs) then
                -- W1. Tiger's Fury under the dynamic 40 - 10 * leeway line (the
                -- sim's doTigersFury: leeway is the GCD remainder plus 1 s on
                -- Clearcasting; latency filed); the hold overlay carries the
                -- call, action stays nil.
                hold = true
                hold_text = "TIGER'S FURY"
            elseif wrath_ff_now(inputs) then
                -- W1b. Omen-fishing Faerie Fire (the sim's ffNow: proven-ready
                -- FF under 87 energy with no proc, the Rip deferral and the
                -- end-of-fight spend math) - ahead of Berserk like the sim.
                -- The hold overlay carries the call, action stays nil (no FF
                -- slot exists, the W1/W2 convention).
                hold = true
                hold_text = "FAERIE FIRE"
            elseif inputs.berserk_ready == true
                and type(inputs.tf_cd_remaining) == "number"
                and inputs.tf_cd_remaining
                    >= st.druid_guide.TF_CD_GATE_BERSERK_SECONDS
                and type(inputs.rip_remaining) == "number"
                and inputs.rip_remaining > 0
                and inputs.clearcast ~= true then
                -- W2. Berserk once Tiger's Fury has been on cooldown for 15 s
                -- or more, with Rip up and no proc (the sim's berserkNow has no
                -- energy gate, so the old 85 cap is gone); the hold overlay
                -- carries the call, action stays nil.
                hold = true
                hold_text = "BERSERK"
            elseif cp >= 1 and sr_expired then
                -- W3. Savage Roar upkeep (>= 1 CP, expired); the hold overlay
                -- carries the call, action stays nil.
                hold = true
                hold_text = "SAVAGE ROAR"
            elseif inputs.clearcast == true then
                -- W4. Omen of Clarity proc: a free Shred, ahead of the finishers.
                action = "shred"
            elseif cp >= 5 and (type(inputs.rip_remaining) ~= "number"
                or inputs.rip_remaining <= 0) then
                -- W5. 5 CP with Rip expired: Rip, never clipped. No energy gate:
                -- the guide shows the next action, the pooling shows on the
                -- energy tick bar.
                action = "rip"
            elseif inputs.mangle_remaining == nil
                and not wrath_wait_for_ff(inputs) then
                -- W6. An absent Mangle prompts it - above Rake, whose ticks it
                -- multiplies; a running one never refreshes. FF imminent
                -- pools instead (the sim's waitForFf).
                action = "mangle"
            elseif (type(inputs.rake_remaining) ~= "number"
                or inputs.rake_remaining <= 0)
                and not wrath_wait_for_ff(inputs) then
                -- W7. Rake expired, never clipped. FF imminent pools instead
                -- (the sim's waitForFf).
                action = "rake"
            elseif cp >= 5
                and type(inputs.rip_remaining) == "number"
                and inputs.rip_remaining >= st.druid_guide.FB_RIP_MIN_SECONDS
                and type(sr) == "number"
                and sr >= st.druid_guide.FB_SR_MIN_SECONDS
                and wrath_target_is_execute(inputs) then
                -- W8. The conditional Ferocious Bite: 5 CP with both Rip and
                -- Savage Roar healthy enough to survive the rebuild, inside
                -- the last-10-seconds execute window (mid-fight falls to
                -- Shred: the research removed Bite from the mid-fight
                -- rotation).
                action = "bite"
            elseif not wrath_wait_for_ff(inputs) then
                -- W9. Anything else: build with Shred (pooling shows on the
                -- energy tick bar; the bearweave branch is not built). FF
                -- imminent pools instead (nil action, no hold - the sim's
                -- waitForFf).
                action = "shred"
            end
        else
            -- FOREVER F1 (see the FOREVER APPENDIX in the module header), then
            -- the legacy rules 4-8 unchanged: every other family skips F1 on
            -- the family gate, and an unproven Shifting Power (nil/false, or
            -- unreadable energy) falls through to the maintenance chain.
            local rip_refresh = threshold(inputs.rip_refresh, st.druid_guide.RIP_REFRESH_DEFAULT)
            local rake_refresh = threshold(inputs.rake_refresh, st.druid_guide.RAKE_REFRESH_DEFAULT)
            if inputs.family == "FOREVER" and inputs.sp_ready == true
                and type(inputs.energy) == "number"
                and inputs.energy <= forever_sp_ceiling(inputs) then
                -- F1. Shifting Power with room for its 40 energy: ceiling 50
                -- (40 on Clearcasting - the proc keeps filling through the GCD,
                -- the sim's underCap math). The hold overlay carries the call,
                -- action stays nil. UNCONFIRMED: the 50/40 values and the 16 s
                -- cooldown are APL-derived (no client source publishes the gain
                -- or the threshold); the call itself is gated behind the
                -- Shifting Power knowledge probe (sp_ready, proven via the
                -- GetSpellInfo name query - the only probe Forever exposes,
                -- since no spell id is published), so an unknown Shifting Power
                -- never calls.
                hold = true
                hold_text = "SHIFTING POWER"
            elseif inputs.family == "FOREVER" then
                -- Forever chain F1b-F7 (see the FOREVER APPENDIX in the module
                -- header): expiry-only refreshes, Bite end-only. The legacy
                -- 4 s windows never run here (the APL pools and refreshes on
                -- expiry); its pooling horizons file their cost probe.
                local fcp = inputs.combo_points
                if type(fcp) ~= "number" then
                    fcp = 0
                end
                local fttd = inputs.time_to_die
                local fend = inputs.target_short_lived == true
                    or (type(fttd) == "number"
                        and fttd <= st.druid_guide.FB_EXECUTE_TTD_SECONDS)
                if inputs.berserk_ready == true
                    and type(inputs.rip_remaining) == "number"
                    and inputs.rip_remaining > 0
                    and inputs.clearcast ~= true then
                    -- F1b. Berserk with Rip up and no proc (the APL
                    -- Berserk-with-builder sequence; the 417141 id is sim-only
                    -- UNCONFIRMED, so the call rides the shared Berserk
                    -- knowledge probe - proven ready via the client's own spell
                    -- data, never a guessed id; no energy gate, no TF phasing
                    -- - Forever has no TF). The hold overlay carries the call,
                    -- action stays nil. An untracked Rip, a proc, or an unproven
                    -- Berserk falls through to the maintenance chain below.
                    hold = true
                    hold_text = "BERSERK"
                elseif inputs.family == "FOREVER" and inputs.elunes_light_ready == true then
                    -- The Elune's Light (the Forever APL's i=3: the Cooldowns
                    -- group). The hold overlay carries the call (no free slot
                    -- exists, the F1/F1b convention).
                    hold = true
                    hold_text = "ELUNE'S LIGHT"
                elseif inputs.clearcast == true then
                    -- F2. Omen of Clarity proc: a free Shred, ahead of the
                    -- finishers (the APL ccShred).
                    action = "shred"
                elseif fcp >= 5 and (type(inputs.rip_remaining) ~= "number"
                    or inputs.rip_remaining <= 0)
                    and not fight_is_young(inputs,
                        st.druid_guide.FIGHT_ELAPSED_FOREVER_SECONDS) then
                    -- F3. 5 CP Rip expired on a proven-old fight (the APL ripNow:
                    -- 5CP, not up, fight older than 10 s). A young fight pools
                    -- to the builder below; unknown defaults to the long fight
                    -- and Rips - the documented shape.
                    action = "rip"
                elseif type(inputs.rake_remaining) ~= "number"
                    or inputs.rake_remaining <= 0 then
                    -- F4. Rake expired (the APL rakeNow, expiry-only).
                    action = "rake"
                elseif fcp >= 5 and fend then
                    -- F6a. 5 CP Bite inside the execute window (the APL biteEnd:
                    -- never mid-fight, unlike the legacy rule 7).
                    action = "bite"
                elseif fcp >= 3 and type(fttd) == "number"
                    and fttd < st.druid_guide.FOREVER_BITE_LOW_TTD_SECONDS then
                    -- F6b. 3+ CP dumped inside the last 3 s (the APL biteLow).
                    action = "bite"
                elseif forever_omen_fish(inputs) then
                    -- F6c. Omen-fishing Faerie Fire (the APL omenFish: nothing
                    -- affordable after a GCD of regen, so fish for the proc).
                    -- The hold overlay carries the call, action stays nil (no
                    -- FF slot exists, the F1/F1b convention). Dormant in game
                    -- until the Omen-ICD probe lands (filed follow-up).
                    hold = true
                    hold_text = "FAERIE FIRE"
                else
                    -- F7. Anything else: build with Shred (the APL pooling
                    -- horizons need Shred/Rip/Rake costs plus the tick phase -
                    -- filed follow-up, so the builder pools here).
                    action = "shred"
                end
            elseif type(inputs.rip_remaining) ~= "number" or inputs.rip_remaining <= rip_refresh then
                -- 4. Rip missing or inside its refresh window.
                action = "rip"
            elseif type(inputs.rake_remaining) ~= "number" or inputs.rake_remaining <= rake_refresh then
                -- 5. Rake missing or inside its refresh window.
                action = "rake"
            elseif inputs.mangle_remaining == nil then
                -- 6. An absent Mangle prompts it; a running one never does.
                action = "mangle"
            elseif type(inputs.combo_points) == "number" and inputs.combo_points >= 5 then
                -- 7. Combo points capped: spend with Ferocious Bite.
                action = "bite"
            else
                -- 8. Anything else: build with Shred.
                action = "shred"
            end
        end
    elseif cat_form_wanted then
        -- The Cat Form upkeep on the families whose APL puts it BELOW the
        -- Innervate row (Era: i=14 vs i=13) - the bear and cat chains own their
        -- own forms, so this branch is the humanoid or the travel form only.
        -- The hold overlay carries the call (no free slot exists, the TIGER'S
        -- FURY convention).
        hold = true
        hold_text = "CAT FORM"
    end
    -- Any other/unknown form: no action.

    out.action = action
    out.hold = hold
    out.hold_text = hold_text
    out.filler_slot = nil
    out.judge_slot = nil
    out.rotation_key = nil
    out.waiting_judgement = false
    return out
end
