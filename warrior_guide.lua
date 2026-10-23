--=========================================================================================
-- Warrior next-action guide: pure decision engine, no WoW API and no clock.
--
-- The second provider for the frozen ST.<CLASS>.guide contract (nextaction_ui.lua's
-- header; the paladin ships the first). The live reads live in classes/warrior.lua
-- (ST.WARRIOR.gather_guide_inputs); this module only consumes the gathered inputs, so it
-- is unit-tested offline by tests/warrior_guide_state.lua.
--
-- FROZEN SPEC - display slots (ST.WARRIOR.guide.slots, ordered):
--   base set (6, the contract maximum: op, execute, slam, hs, cleave +
--     the Hamstring weave filler 7373): every family without a core reader
--     carries the filler in its sixth slot (Forever swings, so the 7373
--     weave filler has room there); the slot shows the GCD swipe until the
--     weave prompt + threshold/toggle options wiring lands (filed).
--     op       Overpower     7384
--     execute  Execute       5308
--     slam     Slam          1464     (icon rank-resolved at post_init)
--     hs       Heroic Strike 78       (icon rank-resolved at post_init)
--     cleave   Cleave        845      (icon rank-resolved at post_init)
--     hamstring Hamstring    7373     (icon rank-resolved at post_init)
--   TBC set (7): op, execute, slam, hs, bt, ww, sunder. The cleave
--   slot is replaced, not added past: cleave is the least-TBC-relevant slot (no
--   rule ever outputs "cleave" - the slot only ever showed the Cleave swipe, and
--   Cleave has no cooldown of its own on the classic line), while Bloodthirst and
--   Whirlwind are the TBC fury core. Sunder upkeep (stacks < 5 / refresh
--   <= 10 s, the TBC + Forever APL single-target groups) takes the seventh
--   slot. The cleave readers stay in the gather
--   (cost/queue/cooldown), so the RIDE path and a future slot re-add keep working.
--   The TBC HUD keeps the six-ability row (hud_state.lua pins it and that
--   suite is owned by another lane): the sunder slot is guide-only until
--   the HUD lane mirrors it (the shaman 13-vs-8 deferral precedent).
--   Era set (7): op, execute, slam, hs, bt, ww, hamstring - the same
--   keys as TBC. Bloodthirst and Whirlwind are vanilla spells that exist on Era
--   (resolved through the same rank tables), so Era shares the TBC slot shape;
--   the cleave replacement reason and the reader retention above apply verbatim.
--   The Hamstring weave filler (7373 above 80 rage, sim-cited) takes the
--   seventh slot; every other family keeps the filler on the base set only
--   (no number cited / toggle-gated, slot + threshold filed).
--   Wrath fury set (6): op, execute, slam, hs, bt, ww - the same keys as
--   TBC/Era. The fury priority (BT > WW > Slam-proc > Execute-demoted > HS
--   dump) names exactly these; the conditional Rend (only with Improved Rend,
--   no Bloodsurge, BT/WW not coming off CD) stays tracker-only (the Rend
--   debuff bar already covers it) with no guide slot. No target-count source
--   exists on the client, so the WW-first-on-2+ rule is documented, not built.
--   Wrath arms set (6): op, execute, rend, ms, bladestorm, hs. Bloodthirst /
--   Whirlwind / Cleave have no arms rule (arms never prompts them), Slam is
--   the deferred early-tier filler (readers kept, rule gated off, HS covers
--   the filler window), and Rend / Mortal Strike / Bladestorm take their
--   places. Spec rule (documented): Mortal Strike known = arms (Mortal
--   Strike ranks 12294 / 21551 / 21552 / 21553 / 25248 / 30330 / 47485 /
--   47486 per the Taste for Blood affected-spells list, wowhead.com/wotlk/
--   spell=56638). Slots are picked at post_init from the frozen spec probe;
--   a respec or rune change mid-session needs /reload (standard for slot
--   shapes; the engine flags freeze with the slots so the two never disagree
--   about which actions exist).
--   SoD set (8, ERA + runes): execute, slam, hs, bt, ww, raging_blow, rend,
--   op. Overpower returns for the stance-dance source (11585 + the gate aura
--   426969 UNCONFIRMED); Rend upkeep (11574 + rune 412507 CONFIRMED, Blood
--   Frenzy) takes the seventh slot. SoD detection (documented): st.family
--   == "ERA" and (Raging Blow 402911 or Consumed by Rage 425440,
--   wowhead.com/classic/spell=425440, known via api.is_spell_known). Hamstring
--   fishing stays filed (no SoD threshold cited - the slot waits on its
--   number); Sunder upkeep is TBC + Forever only (no SoD APL group).
--   SoD Rend fires on the rune alone (the APL gates on the rune, not a
--   toggle); the Forever Rend toggle is filed with the options lane, so no
--   slot names "rend" on Forever yet.
--   Forever set (7): op, execute, slam, hs, cleave, hamstring, sunder.
--   Victory Rush reuses the execute slot (the engine's victory_rush bypass
--   names "execute", so no extra slot is needed), Bloodthrill reuses the OP
--   dodge-window reader (it arms the same window), and Hamstring rides the
--   sixth slot (the Forever 7373 weave filler). Sunder upkeep (stacks < 5 /
--   refresh <= 10 s) takes the seventh slot. Forever Rend upkeep stays filed
--   (toggle-gated in the sim, no toggle in-tree: the window rides the gather
--   for the toggle lane, no slot names "rend" on Forever yet).
--
-- FROZEN SPEC - inputs (all optional, nil never errors):
--   speed, swing_remaining, gcd_remaining    swing/GCD (api.get_time() domain)
--   rage, hs_cost, cleave_cost               rage and the on-next-attack costs
--   hs_queued, cleave_queued                 on-next-attack queue state
--   insufficient_rage                        the bar-colour shortfall flag
--   has_bloodsurge, slam_casting             Bloodsurge proc / Slam cast state
--   overpower_remaining                      dodge-window countdown (nil once over)
--   target_health_pct                        nil = unknown (no target / no answer)
--   execute_pct                              db.guide_execute_pct, default 20
--   bt_remaining, ww_remaining               Bloodthirst / Whirlwind cooldowns (TBC
--                                            and Era readers; both are vanilla
--                                            spells that exist on Era and resolve
--                                            through the same rank tables);
--                                            nil = no reader on this family; the
--                                            BT/WW rules require a known reading,
--                                            so nil never prompts
--   bt_cost, ww_cost                         rage costs through the current ranks;
--                                            nil falls back to the fixed costs
--                                            below (BT 30, WW 25 - the same on Era)
--   hs_rage_floor                            HS dump floor (rage to spare): 40 on TBC,
--                                            40 on Era, 50 on Wrath (TBC-carried,
--                                            HELD - no Wrath sim source), 60 on SoD
--                                            (Consumed by Rage pooling, HELD -
--                                            needs a design decision, not a copy);
--                                            nil = no floor (every other family)
--   core_reserve_window                      Era BT/WW buffer (2.5 s, the midpoint of
--                                            the 2-3 s ground-truth window); nil =
--                                            the 1.5 s TBC default below (Wrath fury
--                                            and SoD carry their family's default:
--                                            1.5 s on Wrath, 2.5 s on SoD)
--   execute_spam                             Era Execute spam below 20 % (true skips
--                                            the rule-2 core reservation); nil/false
--                                            keeps the TBC reservation. SoD feeds
--                                            true as well (Sudden Death dumps and
--                                            the sub-20 % spam never wait on the
--                                            core)
--   execute_phase_dump_gate                  the APL's execute-phase clause on the
--                                            rage dump (provider-fed true only on
--                                            the families whose APL forbids the
--                                            dump inside the execute phase - TBC
--                                            and Forever; nil everywhere else, so
--                                            the legacy shape holds there): a
--                                            KNOWN sub-threshold target withholds
--                                            the dump (rule 7)
--   wrath_fury, wrath_arms                   Wrath branch flags (provider-fed from the
--                                            frozen spec probe; nil everywhere else,
--                                            so all other families keep the legacy
--                                            matrix byte-identically)
--   sod                                      SoD branch flag (ERA + runes; nil
--                                            elsewhere)
--   sudden_death                             Sudden Death proc active (aura 52437 on
--                                            Wrath, wowhead.com/wotlk/spell=52437;
--                                            440495 plus the literal name fallback on
--                                            SoD - in-game to confirm which SoD aura
--                                            id fires; nil = no proc)
--   tfb                                      Taste for Blood proc active (aura 60503,
--                                            wowhead.com/wotlk/spell=56638; nil = no
--                                            proc, so Overpower still needs its dodge
--                                            window; Rend-tick inference deferred)
--   sunder_stacks, sunder_remaining, sunder_duration
--                                            Sunder Armor upkeep window (TBC +
--                                            Forever only, single-target APL
--                                            groups; nil on every other family
--                                            and when the target scan finds
--                                            nothing). No rule consumes these
--                                            yet (no slot names "sunder") -
--                                            engine groundwork, slot + options
--                                            filed.
--   stance_form                              warrior stance form index via
--                                            api.GetShapeshiftForm (nil when
--                                            the probe answers 0/absent; the
--                                            per-family stance index map is
--                                            UNCONFIRMED). Consumed by rule D
--                                            (any non-zero form reads as "in a
--                                            stance" - the map stays filed).
--   stance                                   the CURRENT stance, as a key:
--                                            "battle" | "berserker" |
--                                            "defensive" | nil (unknown).
--                                            The provider reads it from the
--                                            client's own stance auras (the
--                                            sim's stance ids: Battle 2457,
--                                            Defensive 71, Berserker 2458 -
--                                            wowsims/classic sim/warrior/
--                                            stances.go, fetched 2026-10-19),
--                                            NOT from the form index (that map
--                                            stays UNCONFIRMED). nil = unknown
--                                            = no gate (the client's own stance
--                                            rules then decide). Consumed by
--                                            the Overpower and Execute stance
--                                            gates below: the classic, sod and
--                                            tbc-new sims all register
--                                            Overpower with a Battle-stance
--                                            requirement, and Execute with
--                                            Battle|Berserker, so a prompt for
--                                            an uncastable spell is a false
--                                            prompt. The provider feeds the
--                                            stance only on the families whose
--                                            sims carry the requirement (ERA
--                                            incl. SoD, TBC); every other
--                                            family feeds nil, so the gate is
--                                            inert there.
--   sod_stance_aura                          SoD OP stance-dance gate aura live
--                                            (426969 UNCONFIRMED; nil = absent).
--                                            Consumed by rule D.
--   sod_rend_rune_known                      SoD Rend rune known (412507
--                                            CONFIRMED, Blood Frenzy,
--                                            operator in-client 2026-10-19;
--                                            nil = unknown). Fed separately
--                                            from the SoD branch flag (never
--                                            widens SoD detection); gates rule
--                                            R on SoD.
--   rend_upkeep_enabled                      Rend upkeep outside arms enabled
--                                            (provider-fed true only on SoD
--                                            with the rune known; nil/false
--                                            never prompts - the Forever
--                                            toggle is filed with the options
--                                            lane, so Forever feeds nil).
--   hamstring_known                          Hamstring weave filler known
--                                            (post_init-frozen knowledge; nil =
--                                            unlearned/unknown). Consumed by
--                                            rule W with the threshold below.
--   hamstring_rage_threshold                 Hamstring weave rage threshold
--                                            (provider-fed 80 on Era-base,
--                                            sim-cited; nil everywhere else -
--                                            no number cited / toggle-gated,
--                                            so the weave rule stays dormant
--                                            there until the options lane
--                                            ships the tuning).
--   rend_remaining, rend_duration            Rend debuff window (nil = missing /
--                                            unknown, which prompts like the druid
--                                            rip/rake nil rule); rend_refresh is the
--                                            reapply threshold, default 3 (wotlk Rend
--                                            47465, 15 s duration,
--                                            wowhead.com/wotlk/spell=47465;
--                                            in-game to confirm the window)
--   ms_remaining, ms_duration                Mortal Strike cooldown (6 s,
--                                            wowhead.com/wotlk/spell=47486; nil =
--                                            no reader, never prompts - the known-
--                                            reading requirement, like BT/WW)
--   bladestorm_remaining, bladestorm_duration
--                                            Bladestorm cooldown (63784,
--                                            wowhead.com/wotlk/spell=63784; swipe
--                                            fallback 90 s, NEEDS IN-CLIENT
--                                            CONFIRMATION)
--   bladestorm_known                         Bladestorm talented (fresh
--                                            api.is_spell_known read; nil/false
--                                            never prompts an untalented slot)
--   raging_blow_remaining, raging_blow_duration
--                                            Raging Blow cooldown (8 s,
--                                            wowhead.com/classic/spell=402911;
--                                            nil = no reader)
--   execute_spam                             Era Execute spam below 20 % (true skips
--                                            the rule-2 core reservation); nil/false
--                                            keeps the TBC reservation
--   hs_cancel_cue                            TBC HS-cancel cue (provider-fed true only
--                                            on TBC): when rule 2 fires Execute with
--                                            HS/Cleave already queued, the overlay
--                                            reads CANCEL (cancel the queued
--                                            on-next-attack, don't spend its rage)
--                                            instead of riding it; nil everywhere
--                                            else (byte-identical)
--   victory_rush                             Forever Victory Rush ready (provider-fed
--                                            true only on FOREVER via the
--                                            family + knowledge + usable probe,
--                                            UNCONFIRMED id): Execute at any health,
--                                            like the SoD Sudden Death bypass
--                                            (still behind the OP window, still
--                                            before Slam/BT/WW); nil everywhere
--                                            else (byte-identical)
--   op_remaining, execute_remaining, slam_remaining, hs_remaining, cleave_remaining,
--   hamstring_remaining                  client cooldowns; gather filters the GCD
--                                            echo (duration <= 1.51 s) before they
--                                            reach here; the rule matrix reads
--                                            op_remaining / execute_remaining.
--                                            ms_remaining / bladestorm_remaining /
--                                            raging_blow_remaining ride the same
--                                            filter; rend_remaining is a debuff
--                                            window, not a cooldown.
--   utility_order, utility_order_low     the utility spine's APL order for the running
--                                            family, split into the rows the APL puts
--                                            above the core rotation and the rows it
--                                            puts below. nil = no utility spine on
--                                            this family (the engine stays inert).
--   utility_lines' reads                 the utility spine's per-line reads (the
--                                            names live in st.warrior_guide.
--                                            UTILITY_LINES, so the tick path never
--                                            builds a string):
--                                            <key>_known (the client has the spell),
--                                            <key>_remaining (the spell's own
--                                            cooldown, 0 = ready, nil = unknown),
--                                            <key>_duration (the client-reported
--                                            cooldown length, the slot's swipe),
--                                            <key>_buff (false = the buff is not up,
--                                            true = it is, nil = unknown),
--                                            <key>_rage_max (the APL row's own rage
--                                            ceiling, nil = no rage gate).
--   utility_stance                       the CURRENT stance, read from the client's
--                                            own stance auras, on every family the
--                                            utility spine can ask a stance on (the
--                                            existing inputs.stance gate stays on the
--                                            families whose sims gate Overpower and
--                                            Execute on a stance, so that gate keeps
--                                            its byte-identical shape).
--   utility_wanted_stance                the stance the APL's upkeep row wants
--                                            ("battle" / "berserker"), nil when the
--                                            family carries no stance row.
--   utility_weave                        true when the running family's APL weaves
--                                            into Battle Stance for the Overpower
--                                            (the SoD strictSequence, the TBC
--                                            Overpower Weaving group, the WotLK
--                                            strictSequence).
--   reaction                                 optional, default 0.1
--
-- FROZEN SPEC - rule order (first match wins; the legacy rules keep their numbers,
-- the branch rules slot between them as lettered inserts):
--   A. (arms only) Rend upkeep: rend_remaining nil or <= rend_refresh ->
--      action "rend". Nil prompts (missing Rend, like the druid rip/rake nil
--      rule); exactly the threshold refreshes. Inert everywhere else (no Rend
--      upkeep outside arms).
--   B. (arms only) Execute: Sudden Death active (sudden_death) OR target below
--      the threshold, with Execute off cooldown -> action "execute". Outranks
--      Overpower (rule 1): SD-Execute above 20 % and the sub-20 % spam both
--      come first; below 20 % almost exclusively Execute except OP if
--      insufficient rage. No core reservation (arms runs no BT/WW core).
--   1. the Overpower window is active (overpower_remaining > 0) - or, on arms,
--      the Taste for Blood proc is active (tfb) - and Overpower is off
--      cooldown -> action "op". A window of exactly 0 is already over.
--      The stance gate applies: the classic, sod and tbc-new sims all register
--      Overpower with a Battle-stance requirement, so a known non-Battle
--      stance withholds the prompt (an unknown stance never withholds).
--      D. (SoD only) the stance-dance source: the gate aura is live
--      (sod_stance_aura), the client reports a real stance form and
--      Overpower is ready -> action "op". The dodge window stays suppressed
--      on SoD (no dodge source in the SoD priority); every other family
--      keeps the legacy window shape (sod_dance is nil there).
--   2. target_health_pct is known and < execute_pct and Execute is off cooldown and
--      the core does not claim the next GCD (see the reservation below) -> action
--      "execute". The stance gate applies (the sims allow Execute in Battle or
--      Berserker only): a known stance outside that set withholds the prompt
--      (an unknown stance never withholds). A Sudden Death proc (sod and sudden_death) or a ready Victory
--      Rush (victory_rush, Forever only) bypasses the health gate entirely
--      (Execute regardless of target health, still before Slam/BT/WW). When the
--      TBC HS-cancel cue is armed (hs_cancel_cue) and HS/Cleave is already
--      queued, the prompt carries hold = true, hold_text = "CANCEL": cancel the
--      queued on-next-attack before it spends its rage (tbc_minmax.md), instead
--      of the rule-4 RIDE. Era spam (execute_spam) skips the reservation: below
--      20 % the guide spams Execute even when BT/WW is ready/soon, unlike the
--      TBC gate which never spends at the core's expense. SoD feeds
--      execute_spam as well. Skipped on arms (rule B above) and on wrath fury
--      (rule F below demotes it there).
--   3. has_bloodsurge and not slam_casting -> action "slam". On wrath fury the
--      delay gate applies: withheld while Bloodthirst or Whirlwind is ready
--      (the 5 s proc window covers the wait - BT/WW first, Slam woven between).
--      Skipped on arms (no slam slot; the early-tier filler is deferred and HS
--      covers the window). Inert on TBC and
--      Era: Blood Surge is a WotLK talent proc (aura 46916), so the aura read
--      never fires on 2.5.6 or 1.15.9 and this rule can never match there; the
--      logic is untouched. SoD's Blood Surge rune shares aura 46916, so the
--      same rule serves SoD (Execute-SD above it, BT/WW below it, matching the
--      SoD priority).
--   4. hs_queued or cleave_queued -> no action, hold = true, hold_text = "RIDE" (the
--      guide rides the queue the player already placed).
--   S. Sunder upkeep (TBC + Forever APL groups): should_refresh_sunder
--      (stacks < 5, or remaining inside the final 10 s) -> action "sunder".
--      Yields to procs, Execute range and a queued ride; outranks the core
--      rotation and the HS dump (maintenance before rotation, like the arms
--      Rend rule A). Nil on every other family (unknown hides). No
--      target-count source exists, so the single-target gate is documented,
--      not built (multi-target over-prompting is the known residual).
--   R. Rend upkeep outside arms: should_maintain_rend_outside_arms with
--      rend_upkeep_enabled (SoD rune-gated; the Forever toggle is filed, so
--      the rule stays dormant on Forever) -> action "rend". Missing applies
--      once enabled; yields to the same ride/proc/Execute shapes as rule S.
--   5. Bloodthirst is known (a TBC, Era, Wrath-fury or SoD reader exists) and ready
--      (bt_remaining <= 0) -> action "bt". Skipped on arms (no BT rule there).
--   6. Whirlwind is known and ready (ww_remaining <= 0) and no known
--      Bloodthirst lands inside the WW_DELAY window (1.5 s, the sim Delay
--      Check on Era / TBC / Forever - firing WW just before BT wastes the
--      GCD, so the guide waits) -> action "ww". A NaN BT reads as unknown.
--      Skipped on arms. (No target-count source exists, so the WW-first-on-2+
--      fury rule is documented, not built.)
--   F. (wrath fury only) Execute demotion: target below the threshold, Execute
--      off cooldown, BT/WW both cooling (neither ready), rage at/above the
--      floor and the core claiming nothing next (the rule-2 reservation with
--      the Execute spend) -> action "execute". Lowest priority even in Execute
--      phase: only with excess rage, no BT/WW up and everything else on CD.
--   G. (SoD only) Raging Blow: off cooldown -> action "raging_blow" (no rage
--      gate: the ability costs none). Sits after WW, before the HS dump,
--      matching the SoD priority.
--   H. (arms only) Bladestorm: bladestorm_known and off cooldown ->
--      action "bladestorm". Ordered by the earlier rules: Rend maintained
--      (rule A fires first when it lapses), no SD proc pending (rule B fires
--      first), Overpower current in its TfB cycle (rule 1 fires first). The
--      OP-used-in-cycle guard is deferred (no TfB cycle state yet).
--   I. (arms only) Mortal Strike: known and ready (ms_remaining <= 0) ->
--      action "ms" (the 6 s filler).
--   W. Hamstring rage-dump weave: should_weave_hamstring (rage above the
--      threshold with the filler known - Era 80 live, nil elsewhere) ->
--      action "hamstring". Below the core (BT/WW fire first), above the HS
--      dump: excess rage weaves instead of dumping.
--   W0. (utility spine) The Overpower weave's first step: the dance into Battle
--      Stance (utility_weave_stance). It sits ahead of rule 1 because the weave IS
--      the rule-1 cast - the sims register Overpower with a Battle-stance
--      requirement. Only where the running family's APL carries the weave, and
--      only while the Overpower window is live.
--   U1. (utility spine) The APL's HIGH utility rows, in the APL's own priority
--      order: the first row whose read says "ask for it" wins (utility_spine_pick).
--      The reads: the client knows the spell, the cooldown is ready, the row's buff
--      is not up and the rage pool is at or under the row's own ceiling. Every
--      gate is a known-gate (unknown hides).
--   M. (utility spine) The stance upkeep (utility_stance_action): the APL's last
--      row on the families that carry one - "cast the stance when its aura is not
--      active". It sits above the core rotation and yields to the procs, the
--      Execute range and a queued ride.
--   U2. (utility spine) The APL's LOW utility rows (the rows the APL puts below the
--      core rotation), in the APL's own priority order: the same reads as U1.
--   7. rage is known:
--        * insufficient (rage < hs_cost when both are known, else the module's
--          insufficient_rage flag) -> no action, hold = true, hold_text = "HOLD";
--        * else, when the floor is set (hs_rage_floor: 40 TBC, 40 Era) and rage
--          is below it -> no action and no hold: rage is being pooled for
--          Bloodthirst/Whirlwind, not missing;
--        * else, when the core claims the next GCD (ready now, or landing
--          inside the reserve window - 1.5 s TBC, 2.5 s Era via
--          core_reserve_window - with too little rage left after the HS spend
--          to cover its cost) -> no action and no hold, for the same reason;
--        * else, when the family forbids the dump inside the execute phase
--          (execute_phase_dump_gate - the provider arms it on TBC and Forever,
--          whose APL rows gate the dump on NOT isExecutePhase E20) and the
--          target's health is KNOWN and below execute_pct -> no action and no
--          hold: the phase is the APL's move, not the filler's. An unknown
--          target health is not a phase, so the dump keeps its legacy shape;
--        * else hs_cost known, rage >= hs_cost and the swing window allows queueing
--          -> action "hs";
--        * else falls through to rule 8.
--      The swing window mirrors the paladin engine's rel_swing landmark (nextaction.lua:
--      swing_remaining - reaction / 2): a prompt inside the final reaction half-step of
--      the swing cannot ride a swing the player can still react to, so it is withheld.
--      Heroic Strike is off the GCD, so a running gcd_remaining never closes the window
--      (the input rides the same landmark set for tuning).
--   8. no action.
--   "off cooldown" = the *_remaining input is nil or <= 0. The BT/WW/MS rules are
--   the exception: they additionally require a known reading (type() == "number"),
--   so a family without the core readers keeps the legacy six-rule behaviour
--   exactly. Bladestorm additionally requires bladestorm_known (an untalented
--   slot must stay dark). Sunder needs no known-reading gate beyond its own
--   helper (unknown stacks + fresh window hides, like the rule matrix pins).
--   Rend outside arms needs rend_upkeep_enabled == true (the provider feeds
--   it only on SoD with the rune known). Hamstring needs a numeric
--   hamstring_rage_threshold (the provider feeds 80 on Era-base only). The
--   family gating lives in the provider
--   (classes/warrior.lua feeds the bt/ww inputs, the floors, the Era window,
--   the Era/SoD spam flag, the Wrath/SoD branch flags, the upkeep windows
--   and the weave threshold/enable per family/spec);
--   this engine stays family-agnostic and pure.
--
--   Retail (12.x) inertness: st.family == "RETAIL" short-circuits evaluate to the
--   empty display shape before any rule below. The inert stand-in never reports a
--   swing, but target health (rule 2), the Blood Surge aura (rule 3), the queue
--   flags (rule 4) and rage/costs (rule 7, including its HOLD shortfall) all answer
--   on Retail, so those rules would prompt with no swing at all. Every other
--   family - including Forever, which swings - runs the matrix above unchanged; a
--   nil family (offline callers that predate it) keeps the old behaviour too.
--
-- Output: the frozen display fields are overwritten on every call:
--   action, hold, hold_text, filler_slot = nil, judge_slot = nil, rotation_key = nil,
--   waiting_judgement = false.
--=========================================================================================
local _, st = ...

st.warrior_guide = st.warrior_guide or {}

-- Rule constants (frozen; the options panel exposes only the execute threshold).
st.warrior_guide.EXECUTE_PCT_DEFAULT = 20
st.warrior_guide.REACTION_DEFAULT = 0.1

-- TBC fury core constants (sourced ground truth for the 2.5.6 fury priority:
-- Bloodthirst on CD > Whirlwind on CD > Heroic Strike dump only with rage to
-- spare, Execute below 20 % instead of HS and never at BT/WW's expense).
-- Bloodthirst costs 30 rage and Whirlwind 25 on TBC (fixed costs, used only when
-- the provider's live cost read is nil); Execute's base spend is 15 (it drains
-- extra rage into damage on top). The reserve window is one GCD: a core ability
-- landing inside it needs its rage now, so the dump must not take it.
-- Era (1.15.9) shares the costs (BT 30 / WW 25 / Execute 15 are vanilla values)
-- but feeds its own floor (40) and window (2.5 s) through the inputs above, and
-- Execute spam (no reservation) through execute_spam. Wrath fury carries a
-- 50-rage floor and the 1.5 s default window (TBC-carried, HELD: no Wrath sim
-- source in the warrior-rotfix re-verification, so the floor stays put rather
-- than guessing - warrior-rotfix journal 2026-10-19); SoD feeds
-- floor 60 (Consumed by Rage pooling, HELD: the SoD APLs gate 2H at rage >= 30
-- / DW unconditional + stance-dance rage management, which is a design
-- decision, not a number to copy - journal 2026-10-19) with the Era 2.5 s
-- window and spam.
local BT_RAGE_COST = 30
local WW_RAGE_COST = 25
local EXECUTE_RAGE_SPEND = 15
local CORE_RESERVE_WINDOW = 1.5

-- The reserve window, exposed for the practice surface (the core-order drill
-- asks whether a dump would have starved a core sitting inside it).
st.warrior_guide.CORE_RESERVE_WINDOW = CORE_RESERVE_WINDOW

-- Whirlwind delay (the sim "Delay Check"): Whirlwind fires only while
-- Bloodthirst is more than this far out. Era (classic dps_no_reck.apl.json:
-- spellTimeToReady BT > 1.5 s), TBC fury (BT 30335 >= 1.5 s) and Forever
-- (BT 23894 >= 1.5 s) all gate the WW line the same way - firing WW 0.5 s
-- before BT is a wasted GCD the sims never spend. Withheld while a known BT
-- lands inside the window (an unknown BT never withholds, like the
-- known-reading rule shape); the fall-through below re-waits instead of
-- spending (HS reservation covers the rage, or there is simply no action).
local WW_DELAY = 1.5

-- The Delay Check window, exposed for the practice surface (the drill that
-- grades the Whirlwind press measures its margin against this number).
st.warrior_guide.WW_DELAY = WW_DELAY

-- Rend upkeep window (arms rule A): reapply inside the final 3 s, never early.
-- Provisional (the guides only say "maintain / don't reapply early"); Rend's 15 s
-- duration is the wotlk 47465 value above. In-game to confirm.
local REND_REFRESH_DEFAULT = 3

-- Sunder upkeep window (TBC + Forever APL sunder groups, warrior-rotfix
-- journal 2026-10-19: re-stack below 5, refresh inside the final 10 s,
-- single-target only). Consumed by rule S (the TBC sunder slot + the
-- Forever sunder slot); the TBC HUD mirror waits on the HUD lane
-- (guide-only there, shaman 13-vs-8 precedent).
st.warrior_guide.SUNDER_STACKS_MAX = 5
st.warrior_guide.SUNDER_REFRESH_DEFAULT = 10

-- Tactical Mastery rage cap (tbc_minmax.md: cancel queued HS/Cleave before
-- Execute/stance swap, Tactical Mastery keeps at most 25 rage across the swap,
-- Sweeping Strikes costs 30). Pure and family-agnostic; the stance-event
-- wiring is deferred (no stance reads exist in the provider yet), so no rule
-- consumes this today - it pins the 25-cap maths for that wiring.
st.warrior_guide.TACTICAL_MASTERY_RAGE_CAP = 25

-- Rage surviving a stance swap: at most the cap with Tactical Mastery, nothing
-- without it (an unknown talent reads as no talent). Unknown rage answers nil.
function st.warrior_guide.rage_after_stance_swap(rage, tactical_mastery)
    if type(rage) ~= "number" or rage ~= rage then
        return nil
    end
    if rage < 0 then
        return 0
    end
    if tactical_mastery ~= true then
        return 0
    end
    if rage > st.warrior_guide.TACTICAL_MASTERY_RAGE_CAP then
        return st.warrior_guide.TACTICAL_MASTERY_RAGE_CAP
    end
    return rage
end

-- Sunder upkeep verdict (TBC + Forever APL groups): true when the stack count
-- is known-below-cap (re-stack regardless of the window) or the remaining
-- time is known-inside the refresh window, false otherwise. Unknown hides: a
-- non-numeric stack with a non-numeric remaining never prompts (an unreadable
-- debuff is not a readable need). A NaN input answers like unknown, never
-- like a need.
function st.warrior_guide.should_refresh_sunder(stacks, remaining, refresh_window)
    if type(refresh_window) ~= "number" or refresh_window ~= refresh_window then
        refresh_window = st.warrior_guide.SUNDER_REFRESH_DEFAULT
    end
    if type(stacks) == "number" and stacks == stacks
        and stacks < st.warrior_guide.SUNDER_STACKS_MAX then
        return true
    end
    if type(remaining) ~= "number" or remaining ~= remaining then
        return false
    end
    return remaining <= refresh_window
end

-- Rend upkeep outside arms (Forever Rend-weave 11574 at <= 3 s, toggle-gated;
-- SoD Rend 11574 + rune 412507 CONFIRMED, Blood Frenzy): the same 3 s window
-- as arms rule A. The helper takes an explicit enabled flag - nil/false never
-- prompts; the provider feeds true on SoD with the rune known and nil
-- everywhere else (the Forever toggle + the single-target gate live with the
-- options lane, OUT). A missing Rend (nil remaining) reads as apply once
-- enabled, like the arms/druid nil rule. Consumed by rule R (the SoD rend
-- slot; no slot names "rend" on Forever yet - filed).
function st.warrior_guide.should_maintain_rend_outside_arms(remaining, enabled, refresh_window)
    if enabled ~= true then
        return false
    end
    if type(refresh_window) ~= "number" or refresh_window ~= refresh_window then
        refresh_window = REND_REFRESH_DEFAULT
    end
    if remaining == nil then
        return true
    end
    if type(remaining) ~= "number" or remaining ~= remaining then
        return false
    end
    return remaining <= refresh_window
end

-- SoD Overpower stance-dance gate (warrior-rotfix journal 2026-10-19: OP R4
-- 11585, already in op_ids, + stances 2457/2458, gated by aura 426969 - all
-- three UNCONFIRMED on SoD, in-client to confirm). True only when the gate
-- aura is live, the client reports a real stance form (0 = unshifted/probe
-- missing, never a stance) and Overpower itself is ready. The from/to stance
-- index map is UNCONFIRMED per family (compat api.GetShapeshiftForm exists;
-- the warrior map needs in-client confirmation), so the helper requires "in
-- a stance", not a named one. Consumed by rule D (the SoD op slot).
st.warrior_guide.SOD_OP_STANCE_AURA_ID = 426969 -- UNCONFIRMED
function st.warrior_guide.should_stance_dance_op(has_gate_aura, stance_form, op_ready)
    if has_gate_aura ~= true then
        return false
    end
    if type(stance_form) ~= "number" or stance_form ~= stance_form then
        return false
    end
    if stance_form == 0 then
        return false
    end
    return op_ready == true
end

-- Hamstring rage-dump weave verdict (sim-cited ranks: Era 7373 above 80 rage,
-- TBC 18499 with Improved Hamstring 20500, Forever 7373 toggle-gated; the SoD
-- stance-dance OP path rides the gate above, not this). The threshold arrives
-- as a parameter (the provider feeds 80 on Era-base, sim-cited; nil
-- everywhere else - no number cited / toggle-gated, so the weave rule stays
-- dormant there until the options lane ships the tuning). Unknown rage or an
-- unlearned Hamstring never prompts either. Consumed by rule W (the Era
-- hamstring slot + the base/Forever sixth slot).
st.warrior_guide.HAMSTRING_RAGE_THRESHOLD_ERA = 80
function st.warrior_guide.should_weave_hamstring(rage, hamstring_known, rage_threshold)
    if hamstring_known ~= true then
        return false
    end
    if type(rage) ~= "number" or rage ~= rage then
        return false
    end
    if type(rage_threshold) ~= "number" or rage_threshold ~= rage_threshold then
        return false
    end
    return rage > rage_threshold
end

-- The APL's execute-phase clause on the rage dump. The TBC and Forever APLs gate
-- their Heroic Strike row on NOT being inside the execute phase (wowsims/tbc-new
-- ui/specs/warrior/dps/apls/fury.apl.json [18] - `numberTargets == 1 AND NOT
-- isExecutePhase E20 AND currentRage >= 40`; wowsims/forever
-- ui/specs/warrior/dps/apls/arms.apl.json [27] - `NOT isExecutePhase E20 AND
-- currentRage >= 90`), so inside the phase the dump is not the APL's move. The
-- Era APL's row explicitly ALLOWS the dump inside the phase (wowsims/classic
-- ui/warrior/apls/dps_no_reck.apl.json [18] - `currentRage >= 40 OR isExecutePhase
-- E20`) and the SoD / WotLK APLs carry no such clause, so the PROVIDER arms the
-- gate only on the families that carry it (classes/warrior.lua feeds
-- execute_phase_dump_gate).
--
-- The phase read is the one the Execute rule already uses: the target's health
-- fraction against the class's execute percentage. A target with no known health
-- is not in the phase (the clause holds, the dump keeps its legacy behaviour); a
-- KNOWN sub-threshold health withholds the dump. The gate is a prohibition on a
-- filler, not a spend the player cannot afford, so an unreadable phase keeps the
-- legacy shape instead of silencing the dump.
function st.warrior_guide.dump_blocked_in_execute(inputs, execute_pct)
    if type(inputs) ~= "table" then
        return false
    end
    if inputs.execute_phase_dump_gate ~= true then
        return false
    end
    local hp = inputs.target_health_pct
    if type(hp) ~= "number" or hp ~= hp then
        return false
    end
    if type(execute_pct) ~= "number" or execute_pct ~= execute_pct then
        return false
    end
    return hp < execute_pct
end

--=========================================================================================
-- Practice-facing pure helpers (the rotation scenario + the warrior's own drills).
--
-- The shared practice engine drives the class through three surfaces (the
-- orchestrator's fixed contract): ST.WARRIOR.practice_rotation (the rotation
-- table), ST.WARRIOR.practice_scenario_step (one expected action per tick) and
-- ST.WARRIOR.practice_drills (the class's own drills, each with a grade
-- function). The pure maths those surfaces need lives here, so it is unit
-- tested offline (tests/warrior_guide_state.lua) and never reaches for a client
-- read. The sources are the sim APLs and spell files (fetched 2026-10-19, the
-- wowsims master branches), the audited drill set
-- (bench/class_features_drills_2026-10-19.md section 2.2) and the operator's
-- own Heroic Strike / Cleave queue drill (the section further down, with its
-- own sim citations).
--=========================================================================================

-- The stance keys the provider reads (the sim's stance auras). The ids come
-- from the classic sim's stance registration (Battle 2457, Defensive 71,
-- Berserker 2458 - wowsims/classic sim/warrior/stances.go, fetched
-- 2026-10-19); the tbc-new fury APL switches with 2457 (Battle) and 2458
-- (Berserker), so the same two ids carry the TBC client too.
st.warrior_guide.STANCE_BATTLE = "battle"
st.warrior_guide.STANCE_BERSERKER = "berserker"
st.warrior_guide.STANCE_DEFENSIVE = "defensive"
-- The SoD rune stance (wowsims/sod proto/warrior.proto:131 - RuneGladiatorStance =
-- 412513; wowsims/sod sim/warrior/stances.go:212 - the Gladiator Stance aura's
-- ActionID). The client reports it as a stance aura like the other three, so the
-- provider's own stance walk reads it (classes/warrior.lua's WARRIOR_STANCES.ids).
st.warrior_guide.STANCE_GLADIATOR = "gladiator"

-- The action key each stance asks for (the utility spine's stance rows). The engine
-- names the row, never the client's spell id.
st.warrior_guide.STANCE_ACTIONS = {
    battle = "battle_stance",
    berserker = "berserker_stance",
    gladiator = "gladiator_stance",
}

-- Overpower's stance gate (the classic, sod and tbc-new sims all register
-- Overpower with a Battle-stance requirement: classic sim/warrior/overpower.go
-- `RegisterSpell(BattleStance, ...)`, sod sim/warrior/overpower.go the same,
-- tbc-new sim/warrior/overpower.go `ExtraCastCondition = StanceMatches(
-- BattleStance)`). An unknown stance never withholds (unknown hides, and the
-- legacy behaviour stays byte-identical where the provider feeds no stance).
function st.warrior_guide.stance_allows_op(stance)
    if stance == nil then
        return true
    end
    return stance == st.warrior_guide.STANCE_BATTLE
end

-- Execute's stance gate (the classic sim registers Execute with
-- `BattleStance|BerserkerStance` and the tbc-new sim with
-- `StanceMatches(BerserkerStance|BattleStance)`). An unknown stance never
-- withholds.
function st.warrior_guide.stance_allows_execute(stance)
    if stance == nil then
        return true
    end
    return stance == st.warrior_guide.STANCE_BATTLE
        or stance == st.warrior_guide.STANCE_BERSERKER
end

-- The rage pool after an Execute cast. The classic sim spends the WHOLE pool
-- (sim/warrior/execute.go: `extraRage := spell.Unit.CurrentRage()` then
-- `SpendRage(sim, extraRage)`, damage `600 + 15*extraRage`) and the tbc-new
-- sim caps the extra rage at `maxRage - cost` and spends that too (damage
-- `925 + 21*extraRage`), so the pool is empty afterwards on the draining
-- families. A family whose sim does not drain keeps the base spend. An
-- unreadable pool answers nil (never a guess).
function st.warrior_guide.rage_after_execute(rage, cost, drains_all)
    if type(rage) ~= "number" or rage ~= rage then
        return nil
    end
    if drains_all == true then
        return 0
    end
    local spend = cost
    if type(spend) ~= "number" or spend ~= spend then
        spend = EXECUTE_RAGE_SPEND
    end
    local left = rage - spend
    if left < 0 then
        left = 0
    end
    return left
end

-- The short reason each action carries in the practice surface (the scenario
-- step's "reason" field). The text names the rule that fired, not a judgement.
st.warrior_guide.ACTION_REASONS = {
    op = "Overpower window (dodge proc)",
    execute = "Execute below 20 %",
    slam = "Bloodsurge Slam",
    sunder = "Sunder upkeep (stacks / refresh window)",
    rend = "Rend upkeep",
    bt = "Bloodthirst",
    ww = "Whirlwind (the core is more than 1.5 s out)",
    raging_blow = "Raging Blow (costs no rage)",
    bladestorm = "Bladestorm",
    ms = "Mortal Strike",
    hamstring = "Hamstring weave (rage dump)",
    hs = "Heroic Strike dump",
    cleave = "Cleave dump",
    -- The utility spine (the APL's utility rows): the text names the row.
    battle_stance = "Battle Stance (the Overpower stance)",
    berserker_stance = "Berserker Stance (the damage stance)",
    gladiator_stance = "Gladiator Stance (the SoD rune stance)",
    bloodrage = "Bloodrage (the rage cooldown)",
    battle_shout = "Battle Shout (the attack-power buff)",
    recklessness = "Recklessness (the burst cooldown)",
    death_wish = "Death Wish (the damage cooldown)",
    sweeping_strikes = "Sweeping Strikes (the multi-target cooldown)",
    thunder_clap = "Thunder Clap (the area stun)",
    shattering_throw = "Shattering Throw (the ranged armour break)",
    heroic_throw = "Heroic Throw (the ranged filler)",
    berserker_rage = "Berserker Rage (the rage cooldown)",
    blood_fury = "Blood Fury (the Orc racial)",
}

-- The reason for an action, or nil for an unknown key (the caller shows no
-- reason rather than an invented one).
function st.warrior_guide.action_reason(action)
    if type(action) ~= "string" then
        return nil
    end
    return st.warrior_guide.ACTION_REASONS[action]
end

--=========================================================================================
-- The utility spine: the APL's utility rows, and the arm that plays them.
--
-- The rotation table's second block (classes/warrior.lua) carries the APL's utility
-- rows (the stance upkeep, the cooldown pops, the racial) as documentation; this is
-- the arm. The engine stays pure and family-agnostic: the provider
-- (classes/warrior.lua) feeds the per-line reads and the running family's APL order,
-- and the engine walks the order and asks each line.
--
-- THE PER-LINE READS (the flat input names; the table below holds them, so the tick
-- path never builds a string):
--   <key>_known      the client knows the spell. The family gate lives in the provider
--                    (a line the running family's APL does not carry is never fed at
--                    all), so this only answers "does this client have the spell".
--   <key>_remaining  the spell's own cooldown in seconds (0 = ready, nil = unknown).
--   <key>_duration   the client-reported cooldown length (the guide slot's swipe).
--   <key>_buff       the line's buff: false = not up, true = up, nil = unknown.
--   <key>_rage_max   the APL's own rage ceiling for the row (nil = no rage gate).
--
-- A LINE IS ASKED FOR only when every one of these holds:
--   * the client knows the spell (a spell the client lacks is never asked for),
--   * the cooldown is READ and ready (an unknown cooldown never prompts),
--   * the buff is READ and not up (an unreadable buff never prompts: unknown hides),
--   * the rage pool is known and at or under the APL's ceiling (when the row has one).
--
-- THE ORDER: the provider feeds the running family's APL order, split in two:
--   utility_order      the utility rows the APL puts ABOVE the core rotation
--   utility_order_low  the utility rows the APL puts BELOW it (the Era APL's rows,
--                      which come after the filler, and the TBC / Forever rows that
--                      close the list)
--
-- THE STANCE ROWS are not cooldown rows, so they carry their own arms (below): the
-- sims register every stance spell with
-- `ExtraCastCondition: !warrior.StanceMatches(stance)` (wowsims/classic
-- sim/warrior/stances.go) and the APLs gate their rows on `auraIsInactive(auraId)`,
-- so a stance the player is ALREADY in is never asked for.
--=========================================================================================

-- The utility line's input names (the tick path never builds a string: the names live
-- here). `rage_max` is present only on the rows whose APL row carries a rage ceiling.
st.warrior_guide.UTILITY_LINES = {
    bloodrage = {
        remaining = "bloodrage_remaining",
        duration = "bloodrage_duration",
        buff = "bloodrage_buff",
        known = "bloodrage_known",
        rage_max = "bloodrage_rage_max"
    },
    battle_shout = {
        remaining = "battle_shout_remaining",
        duration = "battle_shout_duration",
        buff = "battle_shout_buff",
        known = "battle_shout_known"
    },
    recklessness = {
        remaining = "recklessness_remaining",
        duration = "recklessness_duration",
        buff = "recklessness_buff",
        known = "recklessness_known"
    },
    death_wish = {
        remaining = "death_wish_remaining",
        duration = "death_wish_duration",
        buff = "death_wish_buff",
        known = "death_wish_known"
    },
    sweeping_strikes = {
        remaining = "sweeping_strikes_remaining",
        duration = "sweeping_strikes_duration",
        buff = "sweeping_strikes_buff",
        known = "sweeping_strikes_known"
    },
    thunder_clap = {
        remaining = "thunder_clap_remaining",
        duration = "thunder_clap_duration",
        buff = "thunder_clap_buff",
        known = "thunder_clap_known"
    },
    shattering_throw = {
        remaining = "shattering_throw_remaining",
        duration = "shattering_throw_duration",
        buff = "shattering_throw_buff",
        known = "shattering_throw_known"
    },
    heroic_throw = {
        remaining = "heroic_throw_remaining",
        duration = "heroic_throw_duration",
        buff = "heroic_throw_buff",
        known = "heroic_throw_known"
    },
    berserker_rage = {
        remaining = "berserker_rage_remaining",
        duration = "berserker_rage_duration",
        buff = "berserker_rage_buff",
        known = "berserker_rage_known"
    },
    blood_fury = {
        remaining = "blood_fury_remaining",
        duration = "blood_fury_duration",
        buff = "blood_fury_buff",
        known = "blood_fury_known"
    },
}

-- Pure: the utility row's verdict. True only when the APL's row asks for the line
-- right now. Every gate is a "known" gate (unknown hides): a spell the client does
-- not have, an unreadable cooldown, an unreadable buff and an unreadable rage pool
-- all withhold the prompt.
function st.warrior_guide.utility_line_due(line, inputs)
    if type(line) ~= "table" or type(inputs) ~= "table" then
        return false
    end
    if inputs[line.known] ~= true then
        return false
    end
    local remaining = inputs[line.remaining]
    if type(remaining) ~= "number" or remaining ~= remaining or remaining > 0 then
        return false
    end
    if inputs[line.buff] ~= false then
        return false
    end
    if line.rage_max then
        local ceiling = inputs[line.rage_max]
        local rage = inputs.rage
        if type(ceiling) ~= "number" or ceiling ~= ceiling then
            return false
        end
        if type(rage) ~= "number" or rage ~= rage then
            return false
        end
        if rage > ceiling then
            return false
        end
    end
    return true
end

-- Pure: the utility spine's pick - the first line of the fed order whose read says
-- the APL wants it now. nil when nothing is due (or the provider fed no order).
function st.warrior_guide.utility_spine_pick(order, inputs)
    if type(order) ~= "table" or type(inputs) ~= "table" then
        return nil
    end
    for i = 1, #order do
        local key = order[i]
        local line = st.warrior_guide.UTILITY_LINES[key]
        if line and st.warrior_guide.utility_line_due(line, inputs) then
            return key
        end
    end
    return nil
end

-- Pure: the stance upkeep row ("cast the stance when its aura is not active"). The
-- wanted stance rides in as an input (the provider picks it per family: Berserker
-- Stance on Era / SoD / TBC / WotLK, Battle Stance on Forever, whose Stance Dance
-- toggle ships off). nil when the stance is unknown (the guide would not know the
-- player is already in it) or when the player is already in it.
function st.warrior_guide.utility_stance_action(stance, wanted)
    if type(stance) ~= "string" or stance == "" then
        return nil
    end
    if type(wanted) ~= "string" or wanted == "" then
        return nil
    end
    if stance == wanted then
        return nil
    end
    return st.warrior_guide.STANCE_ACTIONS[wanted]
end

-- Pure: the Overpower weave's first step (the dance into Battle Stance). The sims
-- register Overpower with a Battle-stance requirement (wowsims/classic
-- sim/warrior/overpower.go; wowsims/tbc-new sim/warrior/overpower.go -
-- `ExtraCastCondition = StanceMatches(BattleStance)`), so the dance is what makes the
-- Overpower castable; the APL's own rows are the strictSequence (SoD:
-- [2457, 11585] behind the gate aura 426969) and the Overpower Weaving group (TBC:
-- wait -> 2457 -> 11585 -> 2458). The weave only runs where the running family's APL
-- carries it (the provider's family gate) and only while the Overpower window is
-- live. An unknown stance never asks (unknown hides).
function st.warrior_guide.utility_weave_stance(stance, weave, op_context)
    if weave ~= true or op_context ~= true then
        return nil
    end
    if type(stance) ~= "string" or stance == "" then
        return nil
    end
    if stance == st.warrior_guide.STANCE_BATTLE then
        return nil
    end
    return "battle_stance"
end

-- The audited drill bands (bench/class_features_drills_2026-10-19.md section
-- 2.2 (C)). Every table here is the audit's [DESIGN] band list, not a sim
-- number: the sims fix the rotation and the costs, the band edges are the
-- audit's grading design.

-- D-W1 (the core rotation), a RUN-level band over the mis-picks: S at no
-- mis-pick and no reserve violation, A at one, B at two, C at three, D at
-- five, F beyond that or at any reserve violation (a spend that starved a
-- core sitting inside the reserve window).
st.warrior_guide.CORE_ORDER_BANDS = {
    { max = 0, grade = "S" },
    { max = 1, grade = "A" },
    { max = 2, grade = "B" },
    { max = 3, grade = "C" },
    { max = 5, grade = "D" },
}

-- The run-level band for the core-order drill. A negative or unreadable
-- mis-pick count answers nil (never a grade on a guess); any reserve
-- violation is an F whatever the count.
function st.warrior_guide.core_order_band(mis_picks, violations)
    if type(mis_picks) ~= "number" or mis_picks ~= mis_picks or mis_picks < 0 then
        return nil
    end
    if type(violations) == "number" and violations == violations and violations > 0 then
        return "F"
    end
    for i = 1, #st.warrior_guide.CORE_ORDER_BANDS do
        local band = st.warrior_guide.CORE_ORDER_BANDS[i]
        if mis_picks <= band.max then
            return band.grade
        end
    end
    return "F"
end

-- D-W2 (the core window): the margin (seconds) by which the Whirlwind press
-- stayed clear of the sim's Delay Check (the APLs fire Whirlwind only at
-- Bloodthirst >= 1.5 s out). S at a full second of clearance, A at half a
-- second, B at a fifth, C at the window's edge, D inside it. The two F cases
-- (Bloodthirst already ready, or no rage for either core) are the caller's
-- verdict, because they are about the press, not the margin.
function st.warrior_guide.ww_delay_band(margin)
    if type(margin) ~= "number" or margin ~= margin then
        return nil
    end
    if margin >= 1.0 then
        return "S"
    end
    if margin >= 0.5 then
        return "A"
    end
    if margin >= 0.2 then
        return "B"
    end
    if margin >= 0 then
        return "C"
    end
    return "D"
end

-- D-W3 (the debuff upkeep): the stack count the Sunder press LEAVES the
-- debuff at. A Sunder Armor application adds one stack, capped at five (the
-- sim's own upkeep line fires below five stacks), so the band reads the
-- resulting count: five stacks is the full upkeep (S), one stack is nearly
-- gone (D), and an expired debuff is an F.
function st.warrior_guide.sunder_upkeep_band(stacks_after)
    if type(stacks_after) ~= "number" or stacks_after ~= stacks_after then
        return nil
    end
    if stacks_after >= 5 then
        return "S"
    end
    if stacks_after >= 4 then
        return "A"
    end
    if stacks_after >= 3 then
        return "B"
    end
    if stacks_after >= 2 then
        return "C"
    end
    if stacks_after >= 1 then
        return "D"
    end
    return "F"
end

-- D-W4 (the execute burn): the phase-entry decision. A full pool at the burn
-- is S (within one GCD of the crossing), A one GCD late, B two, and a short
-- pool is C (the burn was clean) or D (the burn was late). The lateness is
-- optional: without it the pool band alone decides.
function st.warrior_guide.execute_burn_band(pool_full, lateness_gcds)
    local late = type(lateness_gcds) == "number" and lateness_gcds == lateness_gcds
    if pool_full == true then
        if not late then
            return "S"
        end
        if lateness_gcds <= 1 then
            return "S"
        end
        if lateness_gcds <= 2 then
            return "A"
        end
        if lateness_gcds <= 3 then
            return "B"
        end
        return "D"
    end
    if not late then
        return "C"
    end
    if lateness_gcds <= 1 then
        return "C"
    end
    return "D"
end

--=========================================================================================
-- The Heroic Strike / Cleave queue window (the operator's offhand drill).
--
-- WHAT THE SIM STATES (fetched 2026-10-19 from the wowsims master branches):
--
--   * The queue LIFTS the dual-wield miss penalty. wowsims/tbc-new
--     sim/warrior/heroic_strike_cleave.go, the comment on consumeQueue:
--     "The queue lifts the dual-wield miss penalty, so it ends after the hit
--     roll." - and the queue aura itself, in all four classic-line sims
--     (classic, sod, tbc-new, forever; sim/warrior/heroic_strike_cleave.go,
--     makeQueueSpellsAndAura):
--         OnGain:   warrior.PseudoStats.DisableDWMissPenalty = true
--         OnExpire: warrior.PseudoStats.DisableDWMissPenalty = false
--     and the core flag's own comment, wowsims/classic
--     sim/core/stats/stats.go:425: "DisableDWMissPenalty bool // Used by Heroic
--     Strike and Cleave".
--   * The penalty it lifts: +19 %. wowsims/classic (and sod, tbc-new, forever,
--     wotlk) sim/core/spell_outcome.go:
--         if spell.Unit.AutoAttacks.IsDualWielding && !spell.Unit.PseudoStats.DisableDWMissPenalty {
--             missChance += 0.19
--         }
--     The white attack's own base miss chance is 5 % at equal skill
--     (wowsims/classic sim/core/target.go:312: "table.BaseMissChance = 0.05 +
--     (targetDefense-weaponSkill)*0.002"), so a dual-wield white swing costs
--     5 % + 19 % = 24 % - the figure the operator quoted.
--   * WHEN the queue is up: the aura activates on the queue spell's cast and
--     expires when the queued auto spell fires - the MAINHAND swing, because the
--     queue replaces it (wowsims/classic sim/warrior/dps_warrior/dps_warrior.go:54
--     "ReplaceMHSwing: war.TryHSOrCleave"; sim/core/attack.go's swing(): "Allow
--     MH swing to be overridden for abilities like Heroic Strike").
--     The activation is delayed by the sim's own realism ICD
--     (sim/warrior/warrior.go: "Duration: time.Millisecond * time.Duration(
--     warrior.WarriorInputs.QueueDelay)"), whose UI default is 250 ms
--     (wowsims/classic ui/core/components/inputs/warrior_inputs.ts:21-27,
--     "HS/Cleave Queue Delay (ms)" - "to delay re-queueing Heroic Strike/Cleave
--     in order to simulate real reaction time and game delay"; the same 250 ms
--     default in wowsims/sod, wowsims/tbc-new
--     (ui/specs/warrior/dps/presets.ts:238) and wowsims/forever
--     (ui/specs/warrior/dps/presets.ts:145)).
--
-- WHAT THE SIM DOES NOT STATE (never invented here):
--   * The CLIENT's own lift timing. The 250 ms above is the sim's REACTION-TIME
--     MODEL, not a client fact: the live client queues the ability on the
--     press. The in-client window is UNCONFIRMED IN-CLIENT (the operator's
--     session owes it), so the drill grades the swing ORDER, not a reaction lag.
--   * The operator's "the normal 7 % spell cap" for the lifted offhand swing.
--     The sim keeps the offhand's own white base miss chance (5 % at equal
--     skill) when the penalty is disabled - it never swaps in a spell cap. The
--     7 % is the operator's in-client figure and is carried as such here, never
--     as a sim number.
--
-- THE WINDOW (the mechanic the drill grades): the offhand's next swing has to
-- land while the queue is up - after the press and before the mainhand swing
-- that fires the queued ability. The press window is therefore the gap between
-- the mainhand's LAST swing and the offhand's NEXT swing:
--   * too early (the press lands before the mainhand's swing): the ability
--     fires at that swing, before the offhand's swing - the offhand swing falls
--     outside the ability;
--   * too late (the press lands after the offhand's swing): the offhand already
--     swung and took the penalty;
--   * inside the gap: the offhand's swing lands inside the ability and the
--     dual-wield penalty is lifted for it.
-- The readings that decide it are the addon's OWN swing data (the mainhand's
-- next landing, the offhand's next landing and the mainhand's weapon speed) -
-- the client data the sim is silent about.
--=========================================================================================

-- The drill's key (the class's own drill list; the shared engine reads it).
st.warrior_guide.HS_QUEUE_DRILL = "warrior_hs_queue"

-- The dual-wield miss penalty the queue lifts (+19 %, the sim's constant) and
-- the white base miss chance it falls back to (5 % at equal skill): the two
-- cited numbers behind the operator's "24 %".
st.warrior_guide.DW_MISS_PENALTY = 0.19
st.warrior_guide.WHITE_MISS_BASE = 0.05

-- The sim's queue delay (the HS/Cleave Queue Delay default, 250 ms). The sim
-- uses it as its reaction-time model; the live client queues on the press, so
-- the drill does NOT use it as a window edge (see the section header).
st.warrior_guide.HS_QUEUE_DELAY_SECONDS = 0.25

-- The margin bands (DESIGN, not sim numbers): how much room the press had on
-- BOTH sides of the window (after the mainhand's last swing, before the
-- offhand's next one). S = a quarter second of room on the tighter side,
-- A = 150 ms, B = 80 ms, C = 20 ms, and the open band D = inside the window
-- but a hair from an edge. The bands are MIN thresholds (a bigger margin is a
-- better press, so the list runs from the best band down), unlike the
-- mis-pick-count tables above, whose value grows with the mistake.
st.warrior_guide.HS_QUEUE_BANDS = {
    { min = 0.25, grade = "S" },
    { min = 0.15, grade = "A" },
    { min = 0.08, grade = "B" },
    { min = 0.02, grade = "C" },
}

-- Pure: the band for a press's margin (the room on the tighter of the two
-- edges). nil for an unreadable margin (never a guessed grade).
function st.warrior_guide.hs_queue_band(margin)
    if type(margin) ~= "number" or margin ~= margin then
        return nil
    end
    for i = 1, #st.warrior_guide.HS_QUEUE_BANDS do
        local band = st.warrior_guide.HS_QUEUE_BANDS[i]
        if margin >= band.min then
            return band.grade
        end
    end
    return "D"
end

-- Pure: the queue-window verdict for one press. The inputs are the addon's own
-- swing data (classes/warrior.lua's gather):
--   offhand_swing_remaining  seconds until the offhand's next swing
--   swing_remaining          seconds until the mainhand's next swing
--   speed                    the mainhand's swing duration (the weapon speed)
--   dual_wielding            true when the player really has an offhand weapon
-- nil when the drill cannot judge it (unknown readings, or no offhand weapon).
function st.warrior_guide.hs_queue_grade(inputs)
    if type(inputs) ~= "table" then
        return nil
    end
    if inputs.dual_wielding ~= true then
        -- The mechanic needs two weapons: a one-armed warrior has no offhand
        -- swing that could land inside the ability.
        return nil
    end
    local offhand = inputs.offhand_swing_remaining
    local swing = inputs.swing_remaining
    local speed = inputs.speed
    if type(offhand) ~= "number" or offhand ~= offhand then
        return nil
    end
    if type(swing) ~= "number" or swing ~= swing then
        return nil
    end
    if type(speed) ~= "number" or speed ~= speed or speed <= 0 then
        return nil
    end
    if offhand >= swing then
        -- The offhand's next swing lands after the mainhand swing that fires the
        -- ability: the press missed the window (the ability goes off before the
        -- swing, or the offhand had already swung).
        return "F"
    end
    -- The press sits between the mainhand's last swing and the offhand's next
    -- one; the room on each side is the margin. The elapsed side is the
    -- mainhand's own cycle minus the time left to its next landing (the swing
    -- engine keeps start = ends_at - speed, so the two always agree).
    local since_mainhand = speed - swing
    if since_mainhand < 0 then
        since_mainhand = 0
    end
    local margin = math.min(since_mainhand, offhand)
    return st.warrior_guide.hs_queue_band(margin)
end

-- Slam safe-window verdict (brainstorm W4: the Slam-safe band on the mainhand
-- bar reads green when the cast lands clean, red when it resets into the
-- deadzone). "clean" when the cast completes before the next swing lands (the
-- boundary still lands clean), "clash" when the swing lands mid-cast, nil when
-- either clock is unknown. swing_resets == false is the Forever client
-- (Forever Slam never resets the swing, so the cast cannot collide): always
-- "clean". A nil swing_resets keeps the classic assumption.
function st.warrior_guide.slam_cast_safety(cast_remaining, swing_remaining, swing_resets)
    if type(cast_remaining) ~= "number" or type(swing_remaining) ~= "number" then
        return nil
    end
    if cast_remaining ~= cast_remaining or swing_remaining ~= swing_remaining then
        return nil
    end
    if swing_resets == false then
        return "clean"
    end
    if cast_remaining <= swing_remaining then
        return "clean"
    end
    return "clash"
end

-- Dual-wield desync alert (competitor-gaps W1): the Desync Alert WA
-- (wago jFIL_JaSw) + Wowhead "remain out of sync" + SST "dual-wield desync"
-- tuning (bench/competitor_gaps_2026-10-19.md §1.4/§Warrior). Pure
-- next-landing coincidence math: two swings landing within the gap window
-- read as synced (the alert state - weapons colliding), wider reads as
-- clean (desynced - the ideal). The WA body is unrended and the SST tuning
-- is UNCONFIRMED in-client, so the 0.3 s window is provisional
-- (offline-tunable here; the widget's default-off gate lives in
-- classes/warrior.lua). No guide rule consumes this: the six-slot contract
-- is full, so this stays a visual alert only and the engine below runs
-- byte-identically with or without it.
st.warrior_guide.DESYNC_ALERT_GAP = 0.3

-- Absolute distance between the two next landings; nil when either clock is
-- unknown (never guess - an unreadable clock hides the widget, see the
-- widget path in classes/warrior.lua).
function st.warrior_guide.swing_sync_gap(mh_remaining, oh_remaining)
    if type(mh_remaining) ~= "number" or type(oh_remaining) ~= "number" then
        return nil
    end
    if mh_remaining ~= mh_remaining or oh_remaining ~= oh_remaining then
        return nil
    end
    return math.abs(mh_remaining - oh_remaining)
end

-- Verdict over the gap: "clash" (synced - the alert) within the window
-- (boundary inclusive, like the slam boundary above), "clean" outside it,
-- nil on an unknown gap. A non-numeric window falls back to the module
-- constant (never to 0 - a zero window would pin the alert on).
function st.warrior_guide.swing_sync_status(mh_remaining, oh_remaining, gap)
    local distance = st.warrior_guide.swing_sync_gap(mh_remaining, oh_remaining)
    if distance == nil then
        return nil
    end
    if type(gap) ~= "number" or gap ~= gap then
        gap = st.warrior_guide.DESYNC_ALERT_GAP
    end
    if distance <= gap then
        return "clash"
    end
    return "clean"
end

-- Position of the OH landing on the current MH swing (0 = MH start,
-- 1 = MH landing); nil when unplaceable (unknown clocks, a non-positive MH
-- speed, or an OH landing outside the current MH swing - the widget hides
-- instead of guessing).
function st.warrior_guide.swing_sync_fraction(mh_remaining, oh_remaining, mh_speed)
    if type(mh_remaining) ~= "number" or type(oh_remaining) ~= "number"
        or type(mh_speed) ~= "number" then
        return nil
    end
    if mh_remaining ~= mh_remaining or oh_remaining ~= oh_remaining
        or mh_speed ~= mh_speed then
        return nil
    end
    if mh_speed <= 0 then
        return nil
    end
    local fraction = 1 - (mh_remaining - oh_remaining) / mh_speed
    if fraction < 0 or fraction > 1 then
        return nil
    end
    return fraction
end

-- W2 Commanding suppression (competitor-gaps W2): the Battle Shout badge is
-- covered while Commanding Shout is live, so the badge must not prompt Battle
-- Shout then. Pure verdict: true only when the suppression toggle is on AND the
-- Commanding window is live (expires in the future). An unknown expiry, a
-- missing clock or a disabled toggle never suppresses. The class module owns
-- the capture (classes/warrior.lua on_aura_change) and the badge readout; this
-- stays family-agnostic and pure.
function st.warrior_guide.should_suppress_battle_shout(commanding_expires, now, suppress_enabled)
    if suppress_enabled ~= true then
        return false
    end
    if type(commanding_expires) ~= "number" or type(now) ~= "number" then
        return false
    end
    if commanding_expires ~= commanding_expires or now ~= now then
        return false
    end
    return commanding_expires > now
end

-- Commanding badge text: "CMD <seconds>s" while the window is live, nil when the
-- badge should hide (no capture, or the window already elapsed). The Battle
-- Shout badge doubles as its readout while suppressing (same widget, so the
-- build-time census holds); the fallback shadow is applied by the aura scan,
-- never here.
function st.warrior_guide.get_commanding_display(commanding_expires, now)
    if type(commanding_expires) ~= "number" or type(now) ~= "number" then
        return nil
    end
    if commanding_expires ~= commanding_expires or now ~= now then
        return nil
    end
    local remaining = commanding_expires - now
    if remaining <= 0 then
        return nil
    end
    return string.format("CMD %.0fs", remaining)
end

-- Execute-entry report (pure, family-agnostic): the rolling W6 drill readout over
-- the live log classes/warrior.lua gathers (one sample per phase entry). The
-- samples already carry their harness grade (S at a full pool, F at empty, nil
-- when rage was unreadable); this only counts and averages, never re-grades.
-- A NaN rage reads as unknown (never feeds the mean); a non-table log
-- summarizes empty (never a guess).
function st.warrior_guide.summarize_execute(samples, count)
    local summary = {
        total = 0,
        graded = 0,
        mean_rage = nil,
        grades = { S = 0, A = 0, B = 0, C = 0, D = 0, F = 0 },
    }
    if type(samples) ~= "table" then
        return summary
    end
    local n = #samples
    if type(count) == "number" and count >= 0 then
        n = math.min(math.floor(count), n)
    end
    local rage_sum, rage_n = 0, 0
    for i = 1, n do
        local sample = samples[i]
        if type(sample) == "table" then
            summary.total = summary.total + 1
            if type(sample.rage) == "number" and sample.rage == sample.rage then
                rage_sum = rage_sum + sample.rage
                rage_n = rage_n + 1
            end
            if summary.grades[sample.grade] ~= nil then
                summary.grades[sample.grade] = summary.grades[sample.grade] + 1
                summary.graded = summary.graded + 1
            end
        end
    end
    if rage_n > 0 then
        summary.mean_rage = rage_sum / rage_n
    end
    return summary
end

-- One-line readout for an execute summary (the report hint). Pure and total:
-- every branch is pinned in tests/warrior_guide_state.lua.
function st.warrior_guide.execute_hint(summary)
    if type(summary) ~= "table" or (summary.total or 0) <= 0 then
        return "No Execute entries logged yet."
    end
    local total = summary.total
    local grades = summary.grades or {}
    local good = (grades.S or 0) + (grades.A or 0)
    local entries_word = (total == 1) and "entry" or "entries"
    if good * 2 >= total then
        return string.format("Loaded: %d of %d %s crossed with S/A rage. Hold the BANK.",
            good, total, entries_word)
    end
    return string.format("Pool rage before 20%%: only %d of %d %s crossed with S/A rage.",
        good, total, entries_word)
end

-- "Off cooldown": nothing left to wait for. gather filters the GCD echo before the
-- inputs reach this module, so a positive value is a real ability cooldown.
local function is_off_cooldown(remaining)
    return not (type(remaining) == "number" and remaining > 0)
end

-- The swing window (rule 5): the paladin engine's rel_swing landmark, i.e. the swing
-- must still be more than a reaction half-step away for a queue prompt to be actionable.
local function swing_allows_queue(swing_remaining, reaction)
    if type(swing_remaining) ~= "number" then
        return false
    end
    if type(reaction) ~= "number" then
        reaction = st.warrior_guide.REACTION_DEFAULT
    end
    return swing_remaining > reaction / 2
end

-- One core ability's claim on the next GCD: ready now (it takes the GCD, so a
-- dump must never precede it), or landing inside the reserve window with too
-- little rage left after the dump's spend to cover its cost. A nil remaining
-- means this family has no reader, so the ability never claims. A nil window
-- falls back to the TBC 1.5 s default (the Era 2.5 s buffer arrives through
-- inputs.core_reserve_window).
local function core_claims_next_gcd(remaining, cost, cost_default, rage, spend, window)
    if type(remaining) ~= "number" then
        return false
    end
    if remaining <= 0 then
        return true
    end
    if type(cost) ~= "number" then
        cost = cost_default
    end
    if type(window) ~= "number" then
        window = CORE_RESERVE_WINDOW
    end
    return type(rage) == "number" and type(spend) == "number"
        and remaining <= window and rage - spend < cost
end

-- True when Bloodthirst or Whirlwind needs the rage/GCD next: the shared
-- reservation behind the Execute gate (rule 2, TBC only - Era spam skips it)
-- and the HS guard (rule 7, both families with their own window).
local function core_reserves_rage(inputs, spend)
    local rage = inputs.rage
    local window = inputs.core_reserve_window
    if type(window) ~= "number" then
        window = CORE_RESERVE_WINDOW
    end
    return core_claims_next_gcd(inputs.bt_remaining, inputs.bt_cost, BT_RAGE_COST,
            rage, spend, window)
        or core_claims_next_gcd(inputs.ww_remaining, inputs.ww_cost, WW_RAGE_COST,
            rage, spend, window)
end

-- The same reservation, exported for the practice surface: the core-order
-- drill asks whether a dump would have starved a core sitting inside the
-- reserve window (the audit's hard F).
st.warrior_guide.core_reserves_rage = core_reserves_rage

-- Pure: one engine tick. Reads `inputs`, writes the frozen display fields into the
-- caller-owned `out` table and returns it. See the module header for the rule matrix.
function st.warrior_guide.evaluate(inputs, out)
    inputs = inputs or {}
    if type(out) ~= "table" then
        out = {}
    end

    if st.family == "RETAIL" then
        -- Retail (12.x): no live swing exists (see the header), so no rule may
        -- prompt - not an action, not a HOLD/RIDE overlay.
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

    -- Branch flags (provider-fed; nil on every legacy family, so the legacy
    -- matrix below runs byte-identically there).
    local wrath_fury = inputs.wrath_fury == true
    local wrath_arms = inputs.wrath_arms == true
    local sod = inputs.sod == true
    local sd = inputs.sudden_death == true

    local execute_pct = inputs.execute_pct
    if type(execute_pct) ~= "number" then
        execute_pct = st.warrior_guide.EXECUTE_PCT_DEFAULT
    end

    if wrath_arms then
        local rend_refresh = inputs.rend_refresh
        if type(rend_refresh) ~= "number" then
            rend_refresh = REND_REFRESH_DEFAULT
        end
        local rend_remaining = inputs.rend_remaining
        if type(rend_remaining) ~= "number" or rend_remaining <= rend_refresh then
            -- A. Rend upkeep: missing (nil) or inside its refresh window.
            action = "rend"
        end
    end

    if action == nil and wrath_arms
        and (sd or (type(inputs.target_health_pct) == "number"
            and inputs.target_health_pct < execute_pct))
        and is_off_cooldown(inputs.execute_remaining) then
        -- B. Arms Execute: Sudden Death (any health) or sub-20 % spam, ahead of
        -- Overpower. No core reservation (arms runs no BT/WW core).
        action = "execute"
    end

    -- The Overpower window: the live dodge proc (the classic line's own 5 s stamp)
    -- or, on SoD, the stance-dance gate aura 426969 the APL's strictSequence rides.
    -- This is the context the utility spine's weave step needs.
    local op_context = (type(inputs.overpower_remaining) == "number"
            and inputs.overpower_remaining > 0)
        or (sod and inputs.sod_stance_aura == true)

    -- The stance upkeep row (the APL's last row: "cast the stance when its aura is
    -- not active"). The wanted stance rides in as an input (the provider picks it per
    -- family); nil wants nothing.
    local stance_action = st.warrior_guide.utility_stance_action(
        inputs.utility_stance, inputs.utility_wanted_stance)

    -- The utility spine's LOW rows (the rows the APL puts BELOW the core rotation).
    local low_pick = st.warrior_guide.utility_spine_pick(inputs.utility_order_low, inputs)

    if action == nil then
        -- W0. The Overpower weave's first step: the dance into Battle Stance. It
        -- sits ahead of rule 1 because the weave IS the rule-1 cast (the sims
        -- register Overpower with a Battle-stance requirement).
        local weave = st.warrior_guide.utility_weave_stance(
            inputs.utility_stance, inputs.utility_weave, op_context)
        if weave then
            action = weave
        end
    end

    if action == nil then
        -- U1. The utility spine's HIGH rows: the APL's utility rows that sit above
        -- the core rotation (the WotLK Bloodrage row is the APL's first row; the
        -- TBC / Forever Death Wish / Recklessness / Sweeping Strikes rows sit above
        -- the core too). The order is the APL's own priority order, fed by the
        -- provider.
        local pick = st.warrior_guide.utility_spine_pick(inputs.utility_order, inputs)
        if pick then
            action = pick
        end
    end

    -- D. (SoD only) the stance-dance OP source: the gate aura is live, the
    -- client reports a real stance form and Overpower itself is ready (the
    -- readiness is proven by the shared is_off_cooldown below, so the helper
    -- takes true). The dodge window stays suppressed on SoD (no dodge source
    -- in the SoD priority); every other family keeps the legacy window shape
    -- (sod_dance is nil there).
    local sod_dance = sod and st.warrior_guide.should_stance_dance_op(
        inputs.sod_stance_aura, inputs.stance_form, true)

    if action == nil and (not sod or sod_dance)
        and ((type(inputs.overpower_remaining) == "number"
                and inputs.overpower_remaining > 0)
            or (wrath_arms and inputs.tfb == true)
            or sod_dance)
        and is_off_cooldown(inputs.op_remaining)
        and st.warrior_guide.stance_allows_op(inputs.stance) then
        -- 1. Overpower: the dodge window is live - or, on arms, Taste for Blood
        -- allows it without a dodge, or, on SoD, the stance-dance gate - and
        -- the ability itself is ready. The stance gate: the sims register
        -- Overpower with a Battle-stance requirement, so a known non-Battle
        -- stance withholds the prompt (an unknown stance never withholds).
        action = "op"
    elseif action == nil and not wrath_arms then
        if not wrath_fury and ((type(inputs.target_health_pct) == "number"
                    and (inputs.target_health_pct < execute_pct
                        or (sod and sd)))
                or inputs.victory_rush == true)
            and is_off_cooldown(inputs.execute_remaining)
            and (inputs.execute_spam == true
                or not core_reserves_rage(inputs, EXECUTE_RAGE_SPEND))
            and st.warrior_guide.stance_allows_execute(inputs.stance) then
            -- 2. Execute range, unless Bloodthirst/Whirlwind needs the rage/GCD next
            -- (Execute instead of HS, never at the core's expense). Era spam
            -- skips the reservation: below 20 % the guide spams Execute even
            -- when BT/WW is ready/soon, unlike the TBC gate. SoD feeds the spam
            -- flag too, and Sudden Death bypasses the health gate (Execute at
            -- any health, still ahead of Slam/BT/WW). Victory Rush (Forever
            -- only) bypasses the health gate the same way: the provider only
            -- feeds it on FOREVER, so every other family keeps the legacy gate
            -- byte-identically. With the TBC HS-cancel cue armed, a queued
            -- HS/Cleave turns the prompt into CANCEL (kill the queued spend
            -- before it eats the Execute rage) instead of the rule-4 RIDE.
            -- Skipped on arms (rule B) and on wrath fury (rule F demotes it
            -- below BT/WW/Slam).
            action = "execute"
            if inputs.hs_cancel_cue == true
                and (inputs.hs_queued == true or inputs.cleave_queued == true) then
                hold = true
                hold_text = "CANCEL"
            end
        elseif inputs.has_bloodsurge == true and not inputs.slam_casting
            and (not wrath_fury
                or ((type(inputs.bt_remaining) ~= "number"
                        or inputs.bt_remaining > 0)
                    and (type(inputs.ww_remaining) ~= "number"
                        or inputs.ww_remaining > 0))) then
            -- 3. Bloodsurge: an instant Slam is worth more than anything below.
            -- On wrath fury the delay gate withholds it while BT/WW is up (the
            -- 5 s window covers the wait); the gate sits in the branch
            -- condition (not the body) so a withheld Slam falls through to the
            -- core below instead of swallowing it.
            action = "slam"
        elseif inputs.hs_queued == true or inputs.cleave_queued == true then
            -- 4. An on-next-attack ability is already queued: ride it.
            hold = true
            hold_text = "RIDE"
        elseif st.warrior_guide.should_refresh_sunder(inputs.sunder_stacks,
                inputs.sunder_remaining) then
            -- S. Sunder upkeep (TBC + Forever APL groups): re-stack below 5,
            -- refresh inside the final 10 s. Yields to procs, Execute range
            -- and a queued ride; outranks the core rotation and the HS dump
            -- (maintenance before rotation, like the arms Rend rule A). Nil
            -- on every other family (unknown hides).
            action = "sunder"
        elseif st.warrior_guide.should_maintain_rend_outside_arms(
                inputs.rend_remaining, inputs.rend_upkeep_enabled) then
            -- R. Rend upkeep outside arms (SoD rune-gated; the Forever toggle
            -- is filed with the options lane, so the rule stays dormant on
            -- Forever). Missing applies once enabled; yields to the same
            -- ride/proc/Execute shapes as rule S above.
            action = "rend"
        elseif stance_action ~= nil then
            -- M. The stance upkeep (the APL's last row on the families that carry
            -- one: "cast the stance when its aura is not active"). It sits above the
            -- core rotation (the TBC / Forever rows switch the stance before the
            -- core lands) and yields to the procs, the Execute range and a queued
            -- ride. nil when the family carries no stance row, and nil when the
            -- stance read is unknown (unknown hides).
            action = stance_action
        elseif type(inputs.bt_remaining) == "number" and inputs.bt_remaining <= 0 then
            -- 5. Bloodthirst: a core reader is present (TBC, Era, wrath fury or
            -- SoD) and ready. The known-reading requirement keeps families
            -- without the reader on the legacy path (nil never prompts). The
            -- GCD is intentionally not gated: the prompt leads the GCD and the
            -- player fires as it clears.
            action = "bt"
        elseif type(inputs.ww_remaining) == "number" and inputs.ww_remaining <= 0
            and (type(inputs.bt_remaining) ~= "number"
                or inputs.bt_remaining ~= inputs.bt_remaining
                or inputs.bt_remaining >= WW_DELAY) then
            -- 6. Whirlwind, same shape, below Bloodthirst - plus the delay
            -- gate: withheld while a known BT lands inside the window (the
            -- sims fire WW only at BT >= 1.5 s out, and waiting beats
            -- spending the GCD on WW). A NaN BT reads as unknown and never
            -- withholds. Falls through to the HS dump / no action below,
            -- like a withheld Slam does.
            action = "ww"
        end
    end

    if action == nil and not hold then
        if inputs.hs_queued == true or inputs.cleave_queued == true then
            -- 4. (branch path) An on-next-attack ability is already queued: ride
            -- it. The base path rides inside the block above; arms and wrath
            -- fury skip that block (no base rules there) and ride here instead.
            hold = true
            hold_text = "RIDE"
        elseif wrath_fury
            and type(inputs.target_health_pct) == "number"
            and inputs.target_health_pct < execute_pct
            and is_off_cooldown(inputs.execute_remaining)
            and (type(inputs.bt_remaining) ~= "number"
                or inputs.bt_remaining > 0)
            and (type(inputs.ww_remaining) ~= "number"
                or inputs.ww_remaining > 0)
            and not (type(inputs.hs_rage_floor) == "number"
                and type(inputs.rage) == "number"
                and inputs.rage < inputs.hs_rage_floor)
            and not core_reserves_rage(inputs, EXECUTE_RAGE_SPEND) then
            -- F. Wrath fury Execute demotion: only below the threshold, with
            -- BT/WW both cooling, rage at/above the floor and the core claiming
            -- nothing next. Lowest priority even in Execute phase. Every gate
            -- sits in the branch condition so a withheld Execute falls through
            -- to the HS dump below instead of swallowing it.
            action = "execute"
        elseif sod and is_off_cooldown(inputs.raging_blow_remaining) then
            -- G. SoD Raging Blow: the rune filler after WW (costs no rage).
            action = "raging_blow"
        elseif wrath_arms and inputs.bladestorm_known == true
            and is_off_cooldown(inputs.bladestorm_remaining) then
            -- H. Arms Bladestorm (Rend maintained, no SD pending and Overpower
            -- current by the order above).
            action = "bladestorm"
        elseif wrath_arms and type(inputs.ms_remaining) == "number"
            and inputs.ms_remaining <= 0 then
            -- I. Arms Mortal Strike filler (known reading required, like BT/WW).
            action = "ms"
        elseif st.warrior_guide.should_weave_hamstring(inputs.rage,
                inputs.hamstring_known, inputs.hamstring_rage_threshold) then
            -- W. Hamstring rage-dump weave (Era 80 live; every other family
            -- feeds a nil threshold until its number/toggle lands). Below the
            -- core (BT/WW fire first), above the HS dump: excess rage weaves
            -- instead of dumping.
            action = "hamstring"
        elseif low_pick ~= nil then
            -- U2. The utility spine's LOW rows: the utility rows the APL puts below
            -- the core rotation (the Era APL's rows come after the filler; the TBC /
            -- Forever rows close the list). They sit above the filler so a cooldown
            -- pop is never spent after the rage dump.
            action = low_pick
        elseif type(inputs.rage) == "number" then
            -- 7. Heroic Strike when rage covers it, clears the floor (50 TBC,
            -- 30 Era) and the core reservation (1.5 s TBC, 2.5 s Era), and the
            -- swing window is open; a known shortfall shows HOLD instead, while
            -- a floor/reservation withhold falls through silently (rage is
            -- pooled, not missing).
            --
            -- The APL's execute-phase clause: on the families whose APL forbids
            -- the dump inside the execute phase (TBC / Forever - the provider
            -- arms execute_phase_dump_gate there), a KNOWN sub-threshold target
            -- withholds the dump, so the phase is the APL's move and not the
            -- filler's. The Era / SoD / WotLK families carry no such clause, so
            -- the dump keeps its legacy shape there.
            local cost = inputs.hs_cost
            local insufficient
            if type(cost) == "number" then
                insufficient = inputs.rage < cost
            else
                insufficient = inputs.insufficient_rage == true
            end
            if insufficient then
                hold = true
                hold_text = "HOLD"
            else
                local floor = inputs.hs_rage_floor
                local floored = type(floor) == "number" and inputs.rage < floor
                if type(cost) == "number" and inputs.rage >= cost
                    and not floored
                    and not core_reserves_rage(inputs, cost)
                    and not st.warrior_guide.dump_blocked_in_execute(inputs, execute_pct)
                    and swing_allows_queue(inputs.swing_remaining, inputs.reaction) then
                    action = "hs"
                end
            end
        end
    end
    -- 8. Anything else: no action.

    out.action = action
    out.hold = hold
    out.hold_text = hold_text
    out.filler_slot = nil
    out.judge_slot = nil
    out.rotation_key = nil
    out.waiting_judgement = false
    return out
end
