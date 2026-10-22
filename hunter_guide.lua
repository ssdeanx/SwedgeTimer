--=========================================================================================
-- Hunter next-action guide: pure decision engine, no WoW API and no clock.
--
-- The fifth and last provider for the frozen ST.<CLASS>.guide contract (nextaction_ui.lua's
-- header; the paladin ships the first, the warrior the second, the druid the third, the
-- shaman the fourth). The live reads live in classes/hunter.lua
-- (ST.HUNTER.gather_guide_inputs); this module only consumes the gathered inputs, so it is
-- unit-tested offline by tests/hunter_guide_state.lua.
--
-- The module reuses the pure hunter window maths at call time (hunter_window.lua is a
-- later TOC entry than the guide modules, so nothing is cached at load):
-- time_until_next_shot times the next ranged shot and is_cast_safe applies the steady-shot
-- grace; the gather half calls hidden_window/cast_window to bound the hidden Auto-Shot
-- window.
--
-- FROZEN SPEC - display slots (ST.HUNTER.guide.slots, ordered):
-- The spell slots carry the RUNNING FAMILY's own rank for that spell - one owner
-- for the guide slot and the HUD slot (classes/hunter.lua's SPELL_ID_BY_FAMILY), so
-- the two surfaces can never disagree about which spell the client has. The ids
-- below are that family's own rank; the icon is re-pointed at the client's CURRENT
-- rank at post_init through api.get_family_spell_id.
--   base set (every family except ERA and MISTS, 6 of the 6 allowed):
--   steady        Steady Shot   TBC 34120 / WRATH 49052 / CATA-MISTS-RETAIL 56641
--                                       (56641 is the vanilla rank: the TBC client
--                                       does NOT have it (bench/rotation_gap_vs_apl_
--                                       2026-10-20.md §0.0 H3) while the WotLK and
--                                       the retail-line classic clients do;
--                                       swipe: the live cast window)
--   raptor        Raptor Strike ERA-SOD 14266 / TBC 27014 / WRATH 48996 /
--                                       FOREVER 14266 / CATA 2973 / RETAIL 186270
--                                       (the Cata CLASSIC client keeps the classic
--                                       rank 2973 - the retail Cata rank 48996 is
--                                       NOT in that client's spell table)
--   kill_command  Kill Command  34026  (TBC BM signature - the client has it on TBC,
--                                       Wrath, Cata, Mists and Retail and on no other
--                                       family; swipe-less prompt slot)
--   multi         Multi-Shot    ERA-SOD 25294 / TBC 27021 / WRATH 49048 /
--                                       FOREVER-CATA-MISTS-RETAIL 2643
--                                       (swipe-less prompt slot)
--   bestial_wrath Bestial Wrath 19574  (swipe-less prompt slot)
--   rapid_fire    Rapid Fire    3045   (RETAIL 257044; swipe-less prompt slot)
--   Mists set (st.family == "MISTS", 5 of the 6 allowed): the base set WITHOUT the
--   Raptor Strike - the Mists client's own spell data carries no Raptor Strike id
--   this tree knows (the classic ladder, the TBC rank and the WotLK ranks are all
--   absent there), so the slot is DROPPED rather than pointed at a spell that
--   client cannot have:
--   steady        Steady Shot   56641  (as on base)
--   kill_command  Kill Command  34026  (as on base)
--   multi         Multi-Shot    2643   (as on base)
--   bestial_wrath Bestial Wrath 19574  (as on base)
--   rapid_fire    Rapid Fire    3045   (as on base)
--   Era set (st.family == "ERA", the Era weave: Steady Shot does not exist on that
--   client, and Kill Command / Bestial Wrath never prompt there, so those slots
--   are dropped rather than shipped dark):
--   aimed         Aimed Shot    20904  (the Era client's own rank; swipe: the
--                                       live cast window, swipe_duration 3.0 s)
--   raptor        Raptor Strike 14266 (the declared melee surface, as on base)
--   multi         Multi-Shot    25294 (swipe-less prompt slot, as on base)
--   Wrath set (st.family == "WRATH", 6 of the 6 allowed: the WotLK min/max
--   priority, docs/research/rotations_wrath.md - Auto Shot fires during Steady
--   Shot casts on WotLK, so the matrix is cooldown-priority with no window hold
--   and no clip check on any arm):
--   kill_shot     Kill Shot      53351 (the execute: at or under 20% target health)
--   chimera       Chimera Shot   53209 (the MM signature; icon rank-resolved)
--   explosive     Explosive Shot 53301 (the SV signature; icon rank-resolved)
--   aimed         Aimed Shot     49050 (instant on Wrath: a swipe-less prompt, NOT
--                                       the Era 3 s cast slot)
--   arcane        Arcane Shot    49045 (MM early-phase; never prompted on SV -
--                                       Arcane shares its cooldown with Explosive)
--   steady        Steady Shot    49052 (demoted to filler; the live-cast swipe)
--   Wrath spec detection (no talent probe exists on the classic line): MM means
--   the client knows Chimera Shot, SV means it knows Explosive Shot (mutually
--   exclusive 51-point talents); neither means an unspecced/levelling hunter
--   (Kill Shot/Aimed/Arcane/Steady only). Serpent Sting is never prompted (MM
--   refreshes it through Chimera; SV upkeep needs aura tracking - deferred) and
--   neither is the Black Arrow/trap tier (no slot left in the six).
--   Era-SoD set (st.family == "ERA" with the SoD Chimera Shot rune known, 5 of
--   the 6 allowed: docs/research/rotations_sod.md - Auto/Chimera/Auto/Aimed/
--   Auto/Multi, the instant Chimera on cooldown above the Era weave):
--   chimera       Chimera Shot   409433 (the SoD gloves rune; icon rank-resolved)
--   aimed         Aimed Shot     20904  (as on Era)
--   raptor        Raptor Strike  14266 (as on Era)
--   multi         Multi-Shot     25294 (as on Era)
--   bestial_wrath Bestial Wrath 19574 (the SoD client HAS the spell: the 1.15.9
--                                       client's own spell data maps 19574 to the
--                                       Beast Mastery skill line - so the slot the
--                                       Era-base set drops ships here)
--   SoD detection: api.is_spell_known on the SoD-only rune id - SoD shares the
--   ERA family token, so the family alone never decides. A pet-rune build that
--   drops Chimera reads as plain Era (the Aimed/Multi weave plus melee gaps).
--   The one BUILD-dependent slot: the Bestial Wrath is in the SoD set and out of
--   the Era-base set. ONE decision (the rune probe) drives both surfaces - the
--   guide's slot set here and the HUD's dead-slot pick - so the two can never
--   disagree about which spells the running build has.
--   Forever set (st.family == "FOREVER", the beta upkeep plus the APL's spine,
--   docs/research/forever_beta.md): NO Steady Shot - the Forever client has no
--   Steady Shot at all (the corpus correction of 2026-10-20,
--   bench/rotation_gap_vs_apl_2026-10-20.md §0.0 H4: the spell arrived in 2.3 and
--   the Forever spell data carries no SteadyShot table), so the slot is DROPPED
--   rather than shipped dark - the same rule the Era set follows:
--   hawk          Summon Hawk   UNCONFIRMED (the beta guides name the spell but
--                               publish no spell id: the slot ships spell-less and
--                               texture-less until an id is confirmed in-client;
--                               swipe-less upkeep prompt, max 2 hawks + pet)
--   sniper        Sniper Shot   UNCONFIRMED (same: the MM signature, 4 s cast;
--                               knowing it IS the spec tell, the way Chimera-known
--                               means MM on Wrath; swipe: the live cast window,
--                               swipe_duration 4.0 s)
--   raptor        Raptor Strike 14266 (the declared melee surface, as on base)
--   Forever detection is the family token alone for the set, plus a knowledge
--   gate per prompt (both stay silent until their ids confirm). Multi-Shot is
--   deliberately NOT prompted on Forever: the beta rotations are sim-unconfirmed
--   (deferred). Hit rating (142/126/95/79, hunter_window.hit_cap_rating) never
--   enters any set: hit changes land chance, not shot timing, so the engine is
--   intentionally hit-blind and the caps are reserved for future HUD/badge
--   display (the option keys for that are frozen - deferred).
-- The rule matrix emits only actions "kill_shot" (Wrath only), "chimera" (Wrath
-- MM and Era-SoD only), "explosive" (Wrath SV only), "arcane" (Wrath non-SV
-- only), "aimed" (Era and Wrath), "multi", "steady", "kill_command", "bestial_wrath",
-- "rapid_fire", "hawk" (Forever only) and "sniper" (Forever only) (or none): the raptor slot is
-- the declared melee surface, and a queued Raptor Strike surfaces as rule 7's RIDE
-- hold. Every emitted action names a slot of the running family's set (the Era set
-- never emits the base-only actions and vice versa: the family gates below make the
-- cross-family arms unreachable).
--
-- FROZEN SPEC - inputs (all optional, nil never errors):
--   now, swing_start, swing_speed, swing_ends_at   ranged cycle, api.get_time() domain
--   synced_duration                                the synced Auto Shot cycle length
--                                                  (preferred over swing_speed, exactly
--                                                  like the cast bar's window maths)
--   latency                                        compensated world latency in seconds
--                                                  (calibrated when usable, raw
--                                                  fallback; never the twist lag
--                                                  calibration)
--   hidden_window_start, hidden_window_duration    the hidden Auto-Shot window bounds
--                                                  (cached module values or a
--                                                  hunter_window.hidden_window recompute)
--   auto_repeat_active                             last Auto Shot auto-repeat reading
--   raptor_strike_queued, steady_shot_queued       the module's queue flags
--   casting                                        any live cast/channel (compat's folding
--                                                  UnitCastingSpell read)
--   steady_cast_seconds                            Steady Shot's cast time (client spell
--                                                  data, per-client fallback
--                                                  TBC/WRATH/FOREVER 1.5 s)
--   steady_known                                   whether the client knows a Steady
--                                                  Shot rank (false on Era, where the
--                                                  spell does not exist: rule 6c never
--                                                  fires there and no fallback prompt
--                                                  is ever shown)
--   hawk_known, hawk_active_count,                 the Forever upkeep gate (rule F1,
--   hawk_remaining_cd                              NOT YET IMPLEMENTED): known on
--                                                  this Forever client, the live
--                                                  hawk count (nil = unknown,
--                                                  never guessed: the ids, and
--                                                  how hawks surface, are
--                                                  UNCONFIRMED - the gather
--                                                  always writes nil), plus the
--                                                  GCD-echo-filtered cooldown
--   sniper_known, sniper_remaining_cd,             the Forever cast gate (rule F2):
--   sniper_cast_seconds,                           known on this Forever client
--   sniper_remaining, sniper_duration              (the MM tell), its cooldown,
--                                                  its cast time (client spell
--                                                  data, per-client fallback
--                                                  FOREVER 4.0 s)
--                                                  and the live Sniper cast's
--                                                  remaining seconds and full
--                                                  length (nil unless a Sniper
--                                                  rank is the live cast; the
--                                                  sniper slot's swipe pair,
--                                                  and rule 1's RIDE arm)
--   steady_remaining                               the live Steady cast's remaining
--                                                  seconds (nil unless a Steady rank is
--                                                  the live cast)
--   steady_duration                                the live Steady cast's full length (the
--                                                  slot swipe's full length)
--   steady_remaining_cd                            Steady Shot's client cooldown after the
--                                                  gather's GCD-echo filter (<= 1.51 s
--                                                  ignored); nil/<= 0 = off cooldown
--   multi_remaining                                a live Multi-Shot cast's remaining
--                                                  seconds (nil unless a Multi-Shot rank
--                                                  is the live cast)
--   multi_cast_seconds                             Multi-Shot's cast time (client spell
--                                                  data, per-client fallback
--                                                  ERA/TBC/WRATH 0.5 s)
--   multi_remaining_cd                             Multi-Shot's client cooldown after the
--                                                  gather's GCD-echo filter; nil/<= 0 =
--                                                  off cooldown
--   multi_known                                    the gate for the Multi-Shot weave:
--                                                  the client knows a Multi-Shot rank
--                                                  AND the family is ERA or TBC;
--                                                  anything else never fires rule 6b
--   aimed_known, aimed_remaining_cd                the Era gate for Aimed Shot
--                                                  (rule 6a): known on this Era client
--                                                  (false on every other family, where
--                                                  the Era slot set is not declared),
--                                                  plus its GCD-echo-filtered cooldown
--   aimed_cast_seconds                             Aimed Shot's cast time (client spell
--                                                  data, per-client fallback
--                                                  ERA 3.0 s)
--   aimed_remaining, aimed_duration                the live Aimed cast's remaining
--                                                  seconds and full length (nil unless
--                                                  an Aimed Shot rank is the live
--                                                  cast; the Era slot's swipe pair)
--   kc_known, kc_remaining_cd                      the TBC gate for Kill Command (rule 3):
--                                                  known on this TBC client, plus its
--                                                  GCD-echo-filtered cooldown
--   bw_known, bw_remaining_cd                      the TBC gate for Bestial Wrath (rule 4)
--   rf_known, rf_remaining_cd                      the TBC gate for Rapid Fire (rule 5)
--   killshot_known, killshot_remaining_cd          the Wrath gate for Kill Shot
--                                                  (rule W1): known on this Wrath
--                                                  client, plus its
--                                                  GCD-echo-filtered cooldown
--   target_hp_frac                                 the target's health fraction
--                                                  (0-1; nil = unknown, never
--                                                  guessed): Kill Shot prompts
--                                                  at or under 0.20 only
--   chimera_known, chimera_remaining_cd             the Chimera gate: the Wrath MM
--                                                  signature (rule W2) or the SoD
--                                                  rune (rule 5b); every other
--                                                  client reads false
--   explosive_known, explosive_remaining_cd        the Wrath SV signature gate
--                                                  (rule W3)
--   wrath_aimed_known, wrath_aimed_remaining_cd    the Wrath Aimed gate (rule W4:
--                                                  the instant prompt; separate
--                                                  from the Era aimed_* cast
--                                                  weave)
--   arcane_known, arcane_remaining_cd              the Wrath Arcane gate (rule W5:
--                                                  MM early-phase; suppressed on
--                                                  SV, where Arcane shares its
--                                                  cooldown with Explosive)
--   target_in_range                                ranged range probe of the Steady Shot
--                                                  school; nil = unknown
--
--   lnl_ready                                      Lock and Load window live (Wrath SV
--                                                  56344 / SoD 415413, sim-confirmed,
--                                                  client-unconfirmed): true = free
--                                                  Explosive/Arcane (Wrath) or free
--                                                  Multi/Aimed (SoD) window; nil/false
--                                                  = no window (never guess). The gather
--                                                  writes nil (no confirmed aura source;
--                                                  wiring filed as follow-up).
--   serpent_known, serpent_active                   Serpent Sting upkeep (Wrath MM Chimera
--                                                  rollover / SoD Chimera bonus):
--                                                  known = the client knows the sting
--                                                  (the class resolves the rank once at
--                                                  post_init), active = the sting on the
--                                                  target, as a THREE-state feed: true
--                                                  (the sting is up on it), false (the
--                                                  scan ran against a real target and
--                                                  the sting is not on it), nil
--                                                  (unknown = allow, never guess).
--                                                  The naked-Chimera guard withholds the
--                                                  prompt only when the sting is KNOWN
--                                                  to be down (serpent_active == false):
--                                                  an unknown debuff never withholds
--                                                  it, so neither the knowledge alone
--                                                  nor an unreadable target can
--                                                  silence the Chimera prompt.
--                                                  The gather runs the target scan
--                                                  (compat's api.scan_unit_aura) only
--                                                  when the client knows a Serpent rank
--                                                  (with no known rank the guard can
--                                                  never withhold, so nothing is
--                                                  scanned and the state stays unknown).
--   sniper_range_buff_active                       Sniper-buff range extension (Forever
--                                                  MM: the buff extends Auto range past
--                                                  41yd for 3 shots, sim
--                                                  TestSniperShotExtendsAutoShotRange):
--                                                  true bypasses rule 2b; nil/false =
--                                                  hold as before. The gather writes nil
--                                                  (no buff source; filed as follow-up).
--   weave_band                                       the melee-weave distance band
--                                                  ("melee"/"ranged"/"out_of_range";
--                                                  nil = unknown): the WA Dynamic
--                                                  switch (wago J3U7jOhMI Mode 3)
--                                                  mapped onto our model: 2b HOLD
--                                                  while unshootable, clip-gated
--                                                  weave while shootable, RIDE on a
--                                                  queued Raptor. No rule reads it
--                                                  yet (filed: wait-at-melee/move
--                                                  timing is not expressible in a
--                                                  stateless engine; the WA "3w/2w"
--                                                  label semantics are UNCONFIRMED).
--                                                  Family-independent: main's
--                                                  LibRangeCheck poll feeds it on
--                                                  every family that reports.
--
-- FROZEN SPEC - the APL UTILITY layer (the class's utility lines, 2026-10-20):
-- The rule matrix below used to stop at the damage abilities: the Serpent Sting
-- upkeep, the aspect swaps, the Kill Shot execute and the APL's melee/trap rows
-- had no arm, so the guide could never ask for them. They do now, each at the
-- priority position its own family's APL gives it (bench/hunter_apl_utility_build_
-- 2026-10-20.md, the APL citations per arm):
--   ERA    i=1 Rapid Fire, i=4 Serpent Sting (behind the Multi at i=3)
--   SOD    i=7 Rapid Fire, i=12 Kill Shot, i=16 Raptor Strike, i=17 Wyvern
--          Strike, i=22 Aspect of the Viper, i=23 Arcane Shot, i=24 Aspect of
--          the Falcon, i=27 Wing Clip (the Chimera rune stays at i=3)
--   TBC    i=0 Aspect of the Viper / Aspect of the Hawk (the "Mana management"
--          group), behind the TBC pops at i=2
--   WRATH  MM: i=1 Aspect of the Viper, i=2 Aspect of the Dragonhawk, i=3
--          Silencing Shot, i=5 Serpent Sting, i=6 Explosive Trap, i=9 Multi-Shot
--          SV: i=6 Explosive Trap, i=7 Serpent Sting, i=8 Black Arrow, i=10
--          Multi-Shot
--   FOREVER i=1 Raptor Strike, i=2 Hunter's Mark, i=3 Mongoose Bite, i=5
--          Immolation Trap, i=6 Wing Clip, i=8 Serpent Sting, i=12 Arcane Shot,
--          i=13 Multi-Shot
-- Two arm shapes, both reading the live inputs only:
--   * a COOLDOWN line (an ability): known on this client and off cooldown.
--   * an AURA line (a buff or a debuff the line maintains): known on this client
--     and the buff is KNOWN DOWN. The aura feeds are three-state (true = up,
--     false = known down, nil = unknown) and only the FALSE reads as due: a line
--     whose buff is up is NEVER asked for, and an unreadable buff is never a
--     "cast it now" (unknown hides).
-- The MELEE rows (Raptor Strike, Wyvern Strike, Wing Clip, Mongoose Bite) also
-- read the weave band ("melee"): the APL casts them in the melee weave, so a
-- ranged player is never asked to swing in melee (an unknown band never prompts).
-- The aspect swaps read the mana fraction (the APL's own thresholds, the
-- constants below): an unknown mana never prompts a swap.
--
-- The new inputs (all optional, nil never errors):
--   rf_known, rf_remaining_cd                       the Rapid Fire burst (the
--                                                  TBC pop plus the ERA and SOD
--                                                  APL rows)
--   killshot_known, killshot_remaining_cd           the Kill Shot execute (the
--                                                  WotLK arm and the SoD rank)
--   serpent_known, serpent_active                   the Serpent Sting upkeep
--                                                  (the three-state target read)
--   raptor_strike_known, raptor_strike_remaining_cd the Raptor Strike weave
--   wyvern_strike_known, wyvern_strike_remaining_cd the Wyvern Strike bleed
--   wing_clip_known, wing_clip_remaining_cd         the Wing Clip debuff
--   mongoose_bite_known, mongoose_bite_remaining_cd the Mongoose Bite hit
--   immolation_trap_known, immolation_trap_remaining_cd the Immolation Trap
--   hunters_mark_known, hunters_mark_active         the Hunter's Mark (the
--                                                  three-state target read)
--   silencing_shot_known, silencing_shot_remaining_cd the Silencing Shot
--   explosive_trap_known, explosive_trap_remaining_cd the Explosive Trap
--   black_arrow_known, black_arrow_remaining_cd     the Black Arrow
--   utility_multi_known, utility_multi_remaining_cd the WotLK and Forever
--                                                  Multi-Shot (the weave's own
--                                                  multi_known stays the Era and
--                                                  TBC cast)
--   aspect_viper_known, aspect_viper_active         the Aspect of the Viper
--   aspect_hawk_known, aspect_hawk_active           the Aspect of the Hawk
--   aspect_falcon_known, aspect_falcon_active       the Aspect of the Falcon
--   aspect_dragonhawk_known, aspect_dragonhawk_active the Aspect of the
--                                                  Dragonhawk
--   mana_frac                                      the player's mana fraction
--                                                  (0-1; nil = unknown, never
--                                                  guessed: a swap arm never
--                                                  fires on an unknown mana)
--
-- FROZEN SPEC - rule order (first match wins; exactly these rules):
--   1. a live Steady Shot, Multi-Shot, Sniper Shot or (Era) Aimed Shot cast is in
--      progress (steady_remaining, multi_remaining, sniper_remaining or
--      aimed_remaining is a number) -> hold, hold_text = "RIDE".
--   2b. the ranged range probe reads exactly 0 (target_in_range == 0, byte-exact: nil
--      = unknown = allowed and boolean spellings are never treated) -> hold,
--      hold_text = "HOLD", ahead of every cooldown priority - the wrath arms (W1-W6)
--      included - and of rule 7's queued ride (conservative: out of range nothing
--      fires). Rule 1 above it still wins: a live cast continues riding. A live
--      Sniper range buff (sniper_range_buff_active == true, Forever MM) bypasses
--      this gate: the sim proves the buff extends Auto range past 41yd for 3 shots.
--   W1-W6. Wrath only (st.family == "WRATH"): the WotLK cooldown priority, with
--      no window hold and no clip check on any arm (Auto Shot fires during Steady
--      Shot casts there, so every shot is cooldown-ready by definition):
--      W1. Kill Shot is known (killshot_known == true), off cooldown and the
--          target is at or under 0.20 health -> action "kill_shot". Unknown
--          health never prompts (never guess the execute).
--      W1a/W1b. Wrath MM: the Serpent Sting upkeep (the sting on the target is
--          KNOWN down) and the Explosive Trap (known and off cooldown) - the MM
--          APL's i=5 and i=6, between the execute (i=4) and the Chimera (i=7).
--      W-LnL. Wrath Lock and Load (lnl_ready == true, sim 56344 22s ICD):
--          free Explosive (SV, explosive_known) or free Arcane (MM, arcane_known
--          with no Explosive) IGNORING cooldown (free + CD reset); sits below the
--          execute, above the normal priority. Nil/false = no window (never guess;
--          the gather writes nil - wiring filed as follow-up).
--      W2. MM: Chimera Shot is known (chimera_known == true) and off cooldown
--          -> action "chimera" (instant, so never a clip), withheld while a known
--          Serpent Sting is down (serpent_known == true with serpent_active == false:
--          no naked Chimera; unknown = allow - the gather's three-state feed never
--          turns an unreadable target into a withholding).
--      W3. SV: Explosive Shot is known (explosive_known == true) and off
--          cooldown -> action "explosive" (instant, so never a clip).
--      W3a/W3b/W3c. Wrath SV: the Explosive Trap (i=6), the Serpent Sting upkeep
--          (i=7) and the Black Arrow (i=8) - behind the Explosive Shot pair.
--      W4. Aimed Shot is known (wrath_aimed_known == true) and off cooldown ->
--          action "aimed" (instant on Wrath; the SV Multi/Aimed tier rides this
--          prompt - the WotLK Multi-Shot ranks are not in the reference table).
--      W4a. The WotLK Multi-Shot (utility_multi_known == true) off cooldown ->
--          action "multi" (the MM APL's i=9 and the SV APL's i=10).
--      W5. Arcane Shot is known (arcane_known == true), off cooldown and the
--          client does NOT know Explosive Shot -> action "arcane" (MM
--          early-phase; dropped at the ArP cap, which no probe can see - the
--          owner skips it then).
--      W6. Steady Shot is known here (steady_known == true) and off cooldown
--          -> action "steady" (the demoted filler: it has no cooldown of its
--          own, so it fires whenever nothing above is due - Steady x3/x4 falls
--          out of the cooldown gaps, not out of a counter).
--      W0a/W0b/W0c. The Wrath APL's TOP rows, ahead of the execute: the Aspect of
--          the Viper (i=1, the mana under 10%), the Aspect of the Dragonhawk (i=2,
--          the mana over 30%) and Silencing Shot (i=3, MM only).
--   2. every family except Wrath: now is inside the hidden Auto-Shot window
--      (inclusive bounds: now >= hidden_window_start and now <=
--      hidden_window_start + hidden_window_duration, matching
--      hunter_window.cast_bar_display's outside test) -> hold, hold_text =
--      "HOLD": a cast started now would clip the shot. Wrath never holds here
--      (no auto-shot management on WotLK, per the research).
--   3. TBC only: Kill Command is known on this client (kc_known == true) and off
--      cooldown (kc_remaining_cd nil or <= 0) -> action "kill_command". Instant, so
--      never a clip: the #1 TBC BM priority.
--   4. TBC only: Bestial Wrath is known (bw_known == true) and off cooldown ->
--      action "bestial_wrath" (instant: popped on cooldown).
--   5. Rapid Fire is known (rf_known == true) and off cooldown ->
--      action "rapid_fire" (instant: popped on cooldown). Three families ask for
--      it and the arm sits at each one's APL position: the ERA APL's i=1 (above
--      the weave), the SOD APL's i=7 (behind the Chimera rune at i=3) and the
--      TBC blanket cooldown layer (the TBC priority list has no Rapid Fire row
--      of its own).
--   5b. Era-SoD only (st.family == "ERA" with the rune known): Chimera Shot is
--      known (chimera_known == true) and off cooldown -> action "chimera"
--      (instant, so never a clip: above the Era weave, behind the window),
--      withheld while a known Serpent Sting is down (same naked-Chimera guard as
--      W2; unknown = allow, the gather writes nil - filed).
--   SoD-LnL. Era-SoD Lock and Load (lnl_ready == true, sim 415413 trap proc):
--      free Aimed (aimed_known, clip-gated) then free Multi (multi_known,
--      clip-gated) IGNORING cooldown, below Chimera, above the normal weave.
--      Nil/false = no window (the gather writes nil - filed).
--   5d-5j. SoD only (the ERA token with the Chimera rune known): the SoD APL's
--      utility spine, in the APL's own order - the Kill Shot execute (i=12, the
--      SoD rank 409593; only the E20 half of the APL's condition is modelled),
--      the Raptor Strike (i=16), the Wyvern Strike (i=17), the Aspect of the
--      Viper (i=22), the Arcane Shot (i=23), the Aspect of the Falcon (i=24)
--      and the Wing Clip (i=27). The melee rows also read the weave band.
--   F0a-F0f. Forever only: the Forever APL's utility spine, in the APL's own
--      order - Raptor Strike (i=1), Hunter's Mark (i=2), Mongoose Bite (i=3),
--      Immolation Trap (i=5), Wing Clip (i=6) and the Serpent Sting upkeep
--      (i=8). The melee rows also read the weave band.
--   5c. TBC Arcane filler (arcane_known == true, off cooldown -> action "arcane",
--      instant): DORMANT behind TBC_ARCANE_ENABLED == false (the base set is full
--      6/6 with no arcane slot; slot wiring filed as follow-up). Engine-tested
--      plug-in point, never a live prompt while false.
--   T0a/T0b. TBC only: the APL's "Mana management" group (i=0) - the Aspect of
--      the Viper (the mana under the 5% start) and the Aspect of the Hawk (the
--      mana back over the 25% stop). Both need the buff KNOWN down.
--   F3/F4. Forever only: the Arcane Shot (i=12) and the Multi-Shot (i=13), the
--      fillers behind the upkeep.
--   F1. Forever only (st.family == "FOREVER"): Summon Hawk upkeep - known
--      (hawk_known == true), fewer than HAWK_MAX_ACTIVE (2) hawks active and
--      off cooldown -> action "hawk" (instant, so never a clip: above the
--      Forever weave, behind the window, matching the beta rotation's
--      "if less than two are active" step). NOT YET IMPLEMENTED: the gather
--      writes hawk_active_count = nil (no confirmed count source - see
--      classes/hunter.lua), so this arm is currently unreachable by
--      construction; it is declared + engine-tested as the plug-in point, not
--      presented as a live prompt.
--   F2. Forever only: Sniper Shot is known (sniper_known == true, itself the MM
--      tell), off cooldown and the 4 s cast fits clip-safe: remaining =
--      sniper_cast_seconds + latency vs time_until_next_shot through
--      hunter_window.is_cast_safe with the steady-shot grace (Sniper Shot is
--      not a Multi-Shot rank, so the 0 grace never applies) -> action
--      "sniper". Whenever Sniper Shot is clip-safe, Multi-Shot and Steady Shot
--      are clip-safe too (shorter casts), so a due Sniper Shot always shadows
--      the weave while it is due.
--   6. the weave, first due first served:
--      a. Era only: Aimed Shot is known (aimed_known == true), off cooldown and the
--         3 s cast fits clip-safe: remaining = aimed_cast_seconds + latency vs
--         time_until_next_shot through hunter_window.is_cast_safe with the
--         steady-shot grace (Aimed Shot is not a Multi-Shot rank, so the 0 grace
--         never applies) -> action "aimed". The primary Era filler, so it shadows
--         Multi-Shot while both are due.
--      b. Era and TBC: Multi-Shot is known (multi_known == true), off cooldown and
--         the cast fits clip-safe: remaining = multi_cast_seconds + latency vs
--         time_until_next_shot through hunter_window.is_cast_safe with the
--         multi-shot grace (0) -> action "multi".
--      c. Steady Shot is known here (steady_known == true), off cooldown
--         (steady_remaining_cd nil or <= 0) and the cast fits clip-safe: remaining
--         = steady_cast_seconds + latency vs time_until_next_shot through
--         hunter_window.is_cast_safe with the steady grace -> action "steady".
--         The known gate keeps Era (and any client without the spell) on the old
--         silent behaviour instead of prompting the rank-1 fallback.
--      d. Era only (the ERA token without the SoD rune): the Serpent Sting upkeep
--         (the ERA APL's i=4, behind the Multi at i=3): the sting on the target
--         is KNOWN down -> action "serpent".
--      Unknown ranged state (no ttl) is NOT clip-safe: the engine never guesses.
--      H2 CUT (operator order 2026-10-19, bench/hunter_open_2026-10-19.md
--      section 5): no Bloodlust/Heroism-family suppression on any weave arm.
--      Haste shortens the live cycle length, so the synced-duration clip math
--      alone withholds casts that genuinely do not fit (sim-faithful: no fetched
--      APL models a lust branch). Re-enable path (future
--      conservative-playstyle opt-in, a follow-up, not this lane): re-add the
--      frozen weave input carrying the live aura's remaining seconds on the
--      player, the throttled compat scan in gather_guide_inputs writing it
--      every call, and the rules 6a/6b gate on the live window; re-pin the H2
--      blocks in tests/hunter_guide_state.lua and the gather pins in
--      tests/hunter_state.lua.
--      Whenever Aimed Shot is clip-safe, Multi-Shot is clip-safe too (shorter cast,
--      no grace), so a due Aimed Shot always shadows Multi-Shot while both are due;
--      whenever Steady Shot is clip-safe, Multi-Shot is clip-safe too, so the
--      steady-only behaviour is intact on TBC while Multi-Shot is on cooldown or
--      unknown. The weapon-speed breakpoint (~3.0 s) falls out of the clip checks
--      themselves: the 3 s Aimed cast only fits a slow (or freshly fired) Auto
--      cycle, while the 0.5 s Multi-Shot fits almost any live cycle. Explicit
--      full-vs-clipped sequencing (which shot alternation to run) is NOT modelled:
--      the stateless engine prompts whatever fits; the live swing reads
--      (synced_duration) already make every prompt weapon-speed-adaptive.
--   7. raptor_strike_queued or steady_shot_queued -> no action, hold = true, hold_text =
--      "RIDE" (the queued on-next-swing state is already showing on the bar).
--   8. no action.
--   auto_repeat_active, casting, target_in_range and weave_band ride the frozen input set; the
--   rules above are the complete decision matrix. Rules 3-5 carry their TBC gate in
--   the inputs (the *_known flags the gather derives from st.family), rule 5b its
--   Era-plus-rune gate (chimera_known) plus the Serpent guard, rule 5c its
--   TBC_ARCANE_ENABLED plug plus the TBC family gate, the SoD-LnL arms their ERA
--   family gate plus lnl_ready, rules F1-F2 their FOREVER family gate
--   plus their knowledge gates (hawk_known/sniper_known), rules W1-W6 and W-LnL their
--   WRATH family gate plus their known-rank gates, rule 6a its Era gate
--   (aimed_known), rule 6b its Era-or-TBC gate (multi_known) and rule 6c its
--   known-rank gate (steady_known), so every other client runs exactly the old
--   matrix: rules 1, 2, 6b (TBC), 6c (where known), 7, 8. The window hold
--   (rule 2) stays compiled in on Forever: the beta "Auto Shot no longer
--   clipped" note is sim-unconfirmed in-client, so instants keep the
--   conservative TBC-style hold until a Forever client proves otherwise.
--
--   The eWS/ratio outputs below are display data, never rule inputs: the
--   stateless engine prompts whatever fits clip-safe (the live swing reads
--   already make every prompt weapon-speed-adaptive), while explicit
--   full-vs-clipped sequencing (which shot alternation to run) is NOT modelled.
--
--   Retail (12.x) inertness: st.family == "RETAIL" short-circuits evaluate to the
--   empty display shape before any rule below. The inert stand-in reports no ranged
--   cycle (rules 2 and 6 stay silent on their own), but a live cast (rule 1), the
--   cooldown-shaped reads behind rules 3-5 and the queue flags (rule 7) all answer
--   on Retail, so those rules would prompt or hold with no swing at all. Every
--   other family runs the matrix above unchanged; a nil family (offline callers
--   that predate it) keeps the old behaviour too.
--
-- Output: the frozen display fields are overwritten on every call:
--   action, hold, hold_text, filler_slot = nil, judge_slot = nil, rotation_key = nil,
--   waiting_judgement = false, plus the TBC micro display pair (never rule
--   inputs, always recomputed, nil when the ranged cycle is unknown):
--   effective_weapon_speed                 the live cycle length (synced_duration
--                                          preferred over swing_speed), which IS
--                                          the effective weapon speed once the
--                                          client's haste applies - the quiver x
--                                          talent decomposition it verifies
--                                          against lives in
--                                          hunter_window.effective_weapon_speed
--   steady_ratio                           hunter_window.steady_ratio_band over
--                                          that length ("one_to_one", "french"
--                                          or "one_to_two").
--=========================================================================================
local _, st = ...

st.hunter_guide = st.hunter_guide or {}

-- Rule constants (frozen; the hunter guide exposes no options panel thresholds).
st.hunter_guide.STEADY_CAST_SECONDS_DEFAULT = 1.5
st.hunter_guide.STEADY_GRACE_DEFAULT = 0.5
st.hunter_guide.MULTI_CAST_SECONDS_DEFAULT = 0.5
st.hunter_guide.MULTI_GRACE_DEFAULT = 0
st.hunter_guide.AIMED_CAST_SECONDS_DEFAULT = 3.0
st.hunter_guide.KILL_SHOT_EXECUTE_FRAC = 0.20
st.hunter_guide.SNIPER_CAST_SECONDS_DEFAULT = 4.0

-- Rotation-text tiers (docs/hunter-wa.json "Attack Speed || Rotation", wago
-- eEJOoHci-, tocversion 20505 = TBC Anniversary): the WA's speed→label readout
-- over UnitRangedDamage("player"), first threshold the speed strictly exceeds
-- wins (WA `if speed > t.val` verbatim, customText). CLIENT-OBSERVED (the pack
-- ran on a TBC client), SIM-UNCONFIRMED (no fetched sim APL emits these labels;
-- sims model weave/turret choice, never a speed string). Display-only: evaluate
-- never reads them (like effective_weapon_speed/steady_ratio below), so a tier
-- can never divert a prompt. Custom texts/colors ride the WA's own option keys
-- (text_*/color_*) and stay filed with them (options scope); the tables carry
-- the WA defaultText labels only - and neither color set (the WA init defColors
-- disagree with the shipped authorOptions defaults, hunter_wa_map §1).
-- Mode 3 (Dynamic) is FILED, not resolved here: the WA picks Mode 2 vs 1
-- through a hand-rolled 5 yd item-range probe (Voodoo Charm; id in
-- hunter_wa_map §1), which the hunter scope must not spend (tests/
-- hunter_state.lua §20b pins its absence; the vendored LibRangeCheck-2.0 owns
-- the 5-yard checker). The caller passes the resolved
-- 1/2; a raw 3 reads Standard (the WA's own no-valid-target default).
st.hunter_guide.ROTATION_TIERS_STANDARD = {
    { speed_gt = 2.33, label = "5:4:1:1" },
    { speed_gt = 1.95, label = "5:5:1:1" },
    { speed_gt = 1.74, label = "5:6:1:1" },
    { speed_gt = 1.27, label = "1:1" },
    { speed_gt = 1.09, label = "5:9:1:1" },
    { speed_gt = 0.90, label = "2:3" },
    { speed_gt = 0.70, label = "1:2" },
    { speed_gt = 0.57, label = "2:5" },
    { speed_gt = 0, label = "1:3" },
}
-- The "3w/2w/1w" suffixes are the WA's own cycle notation, UNCONFIRMED beyond
-- the labels (hunter_wa_map §5).
st.hunter_guide.ROTATION_TIERS_WEAVE = {
    { speed_gt = 1.83, label = "5:5:1:1 3w" },
    { speed_gt = 1.62, label = "2:2 1w" },
    { speed_gt = 1.22, label = "6:9:1:1 3w" },
    { speed_gt = 0.94, label = "6:11:1:1 3w" },
    { speed_gt = 0, label = "3:7 2w" },
}

-- Pure: the WA tier lookup verbatim. Returns the label, or nil when the speed
-- is unknown (nil/non-number/NaN - never a guess; the WA only ever runs with a
-- live speed, where NaN cannot occur). mode 2 reads the weave table; every
-- other mode (including the filed dynamic 3) reads Standard.
function st.hunter_guide.rotation_tier(speed, mode)
    if type(speed) ~= "number" or speed ~= speed then
        return nil
    end
    local tiers = st.hunter_guide.ROTATION_TIERS_STANDARD
    if mode == 2 then
        tiers = st.hunter_guide.ROTATION_TIERS_WEAVE
    end
    for i = 1, #tiers do
        if speed > tiers[i].speed_gt then
            return tiers[i].label
        end
    end
    return tiers[#tiers].label
end

-- TBC Arcane filler plug (bench/hunter_rotation_audit_2026-10-19.md finding 4):
-- the sim APL's core filler (27019, already in arcane_shot_ids) with no slot to show
-- it in (the base set is full 6/6). Engine-tested but ships false: slot + options
-- wiring is filed as follow-up, so no live prompt changes until then.
st.hunter_guide.TBC_ARCANE_ENABLED = false

-- Summon Hawk upkeep cap (docs/research/forever_beta.md: "if less than two are
-- active", max 2 hawks + pet). The engine compares the live count strictly
-- below this; an unknown count never prompts (never guess the upkeep).
st.hunter_guide.HAWK_MAX_ACTIVE = 2

-- The APL utility layer's mana gates (the APL rows' own conditions, cited per
-- arm in the rule matrix below). A mana read the client cannot answer is
-- UNKNOWN and never prompts (unknown hides): only a known fraction moves a
-- swap arm.
--   VIPER_MANA_FRAC       the OOM swap: the TBC and SoD APLs cast the Aspect of
--                         the Viper when the mana is under 5% (the shipped OOM
--                         band, ST.HUNTER.OOM_VIPER_FRAC).
--   VIPER_MANA_FRAC_WRATH the WotLK APL's own threshold (mana below 10%).
--   HAWK_MANA_FRAC        the TBC APL's "mana back over the Viper stop" (the
--                         25% stop the shipped OOM band documents).
--   DRAGONHAWK_MANA_FRAC  the WotLK APL's "mana over 30%".
st.hunter_guide.VIPER_MANA_FRAC = 0.05
st.hunter_guide.VIPER_MANA_FRAC_WRATH = 0.10
st.hunter_guide.HAWK_MANA_FRAC = 0.25
st.hunter_guide.DRAGONHAWK_MANA_FRAC = 0.30

-- "Off cooldown": nothing left to wait for. gather filters the GCD echo before the inputs
-- reach this module, so a positive value is a real ability cooldown.
local function is_off_cooldown(remaining)
    return not (type(remaining) == "number" and remaining > 0)
end

-- The APL UTILITY arms' two gates (the class's utility layer, 2026-10-20).
-- Every arm names a line the class's own APL asks for at a stated priority
-- position; the arm fires only when the line is READY:
--   * a COOLDOWN line (an ability): known on this client and off cooldown.
--   * an AURA line (a buff or a debuff the line maintains): known on this
--     client and the buff is KNOWN DOWN. The aura read is three-state (true =
--     up, false = known down, nil = unknown) and only the FALSE reads as due:
--     an unreadable buff is never a "cast it now" (unknown hides).
local function utility_ready(inputs, known_key, cd_key)
    if inputs[known_key] ~= true then
        return false
    end
    return is_off_cooldown(inputs[cd_key])
end

local function utility_due(inputs, known_key, active_key)
    return inputs[known_key] == true and inputs[active_key] == false
end

-- The mana gates: a fraction the client cannot answer is unknown and never
-- prompts (the engine never guesses a swap).
local function mana_below(inputs, frac)
    local mana = inputs.mana_frac
    if type(mana) ~= "number" or mana ~= mana then
        return false
    end
    return mana <= frac
end

local function mana_above(inputs, frac)
    local mana = inputs.mana_frac
    if type(mana) ~= "number" or mana ~= mana then
        return false
    end
    return mana >= frac
end

-- The hidden Auto-Shot window containment, inclusive at both edges (the same outside test
-- hunter_window.cast_bar_display applies: only now < start or now > end is outside).
local function is_in_window(window_start, window_duration, now)
    return type(window_start) == "number" and type(window_duration) == "number"
        and window_duration > 0 and type(now) == "number"
        and now >= window_start and now <= window_start + window_duration
end

-- Rule 6c's clip-safety check through the pure hunter_window maths (the same kernels the
-- cast bar tints with). False whenever the ranged cycle is unknown: no ttl, no prompt -
-- the engine never guesses a cast it cannot prove clip-safe.
local function cast_is_clip_safe(inputs)
    local hunter_window = st.hunter_window
    if not (hunter_window and hunter_window.time_until_next_shot
        and hunter_window.is_cast_safe) then
        return false
    end
    local cycle_duration = inputs.synced_duration
    if type(cycle_duration) ~= "number" then
        cycle_duration = inputs.swing_speed
    end
    local ttl = hunter_window.time_until_next_shot(
        inputs.now, inputs.swing_start, cycle_duration, inputs.swing_ends_at)
    if type(ttl) ~= "number" then
        return false
    end
    local cast_seconds = inputs.steady_cast_seconds
    if type(cast_seconds) ~= "number" then
        cast_seconds = st.hunter_guide.STEADY_CAST_SECONDS_DEFAULT
    end
    local latency = inputs.latency
    if type(latency) ~= "number" then
        latency = 0
    end
    local grace = hunter_window.STEADY_SHOT_GRACE
    if type(grace) ~= "number" then
        grace = st.hunter_guide.STEADY_GRACE_DEFAULT
    end
    -- The frozen formula: the cast plus the latency must fit inside the next-shot window
    -- under the steady-shot grace (is_cast_safe floors its own latency buffer).
    return hunter_window.is_cast_safe(cast_seconds + latency, ttl, grace, latency) == true
end

-- Rule 6b's clip-safety check: the same kernels as the steady check below, with the
-- Multi-Shot cast time and the multi-shot grace (0). Kept as a separate function so
-- the steady path below stays byte-identical: whenever Steady Shot is clip-safe,
-- Multi-Shot is clip-safe too (shorter cast, no grace), so a due Multi-Shot always
-- shadows Steady Shot and the steady-only behaviour is intact while Multi-Shot is on
-- cooldown or unknown.
local function multi_is_clip_safe(inputs)
    local hunter_window = st.hunter_window
    if not (hunter_window and hunter_window.time_until_next_shot
        and hunter_window.is_cast_safe) then
        return false
    end
    local cycle_duration = inputs.synced_duration
    if type(cycle_duration) ~= "number" then
        cycle_duration = inputs.swing_speed
    end
    local ttl = hunter_window.time_until_next_shot(
        inputs.now, inputs.swing_start, cycle_duration, inputs.swing_ends_at)
    if type(ttl) ~= "number" then
        return false
    end
    local cast_seconds = inputs.multi_cast_seconds
    if type(cast_seconds) ~= "number" then
        cast_seconds = st.hunter_guide.MULTI_CAST_SECONDS_DEFAULT
    end
    local latency = inputs.latency
    if type(latency) ~= "number" then
        latency = 0
    end
    local grace = hunter_window.MULTI_SHOT_GRACE
    if type(grace) ~= "number" then
        grace = st.hunter_guide.MULTI_GRACE_DEFAULT
    end
    -- The frozen formula: the cast plus the latency must fit inside the next-shot window
    -- under the multi-shot grace (is_cast_safe floors its own latency buffer).
    return hunter_window.is_cast_safe(cast_seconds + latency, ttl, grace, latency) == true
end

-- Rule 6a's clip-safety check: the same kernels as the steady check above, with the
-- Era Aimed Shot cast time (3.0 s base) under the steady-shot grace (Aimed Shot is
-- not a Multi-Shot rank, so the 0 grace never applies). Kept as a separate function
-- so both paths above stay byte-identical: whenever Aimed Shot is clip-safe,
-- Multi-Shot is clip-safe too (shorter cast, no grace), so a due Aimed Shot always
-- shadows Multi-Shot while both are due.
local function aimed_is_clip_safe(inputs)
    local hunter_window = st.hunter_window
    if not (hunter_window and hunter_window.time_until_next_shot
        and hunter_window.is_cast_safe) then
        return false
    end
    local cycle_duration = inputs.synced_duration
    if type(cycle_duration) ~= "number" then
        cycle_duration = inputs.swing_speed
    end
    local ttl = hunter_window.time_until_next_shot(
        inputs.now, inputs.swing_start, cycle_duration, inputs.swing_ends_at)
    if type(ttl) ~= "number" then
        return false
    end
    local cast_seconds = inputs.aimed_cast_seconds
    if type(cast_seconds) ~= "number" then
        cast_seconds = st.hunter_guide.AIMED_CAST_SECONDS_DEFAULT
    end
    local latency = inputs.latency
    if type(latency) ~= "number" then
        latency = 0
    end
    local grace = hunter_window.STEADY_SHOT_GRACE
    if type(grace) ~= "number" then
        grace = st.hunter_guide.STEADY_GRACE_DEFAULT
    end
    -- The frozen formula: the cast plus the latency must fit inside the next-shot window
    -- under the steady-shot grace (is_cast_safe floors its own latency buffer).
    return hunter_window.is_cast_safe(cast_seconds + latency, ttl, grace, latency) == true
end

-- Rule F2's clip-safety check: the same kernels as the aimed check above, with the
-- Forever Sniper Shot cast time (4.0 s base) under the steady-shot grace (Sniper
-- Shot is not a Multi-Shot rank, so the 0 grace never applies). Kept as a separate
-- function so every path above stays byte-identical: whenever Sniper Shot is
-- clip-safe, Multi-Shot and Steady Shot are clip-safe too (shorter casts), so a
-- due Sniper Shot always shadows the weave while it is due.
local function sniper_is_clip_safe(inputs)
    local hunter_window = st.hunter_window
    if not (hunter_window and hunter_window.time_until_next_shot
        and hunter_window.is_cast_safe) then
        return false
    end
    local cycle_duration = inputs.synced_duration
    if type(cycle_duration) ~= "number" then
        cycle_duration = inputs.swing_speed
    end
    local ttl = hunter_window.time_until_next_shot(
        inputs.now, inputs.swing_start, cycle_duration, inputs.swing_ends_at)
    if type(ttl) ~= "number" then
        return false
    end
    local cast_seconds = inputs.sniper_cast_seconds
    if type(cast_seconds) ~= "number" then
        cast_seconds = st.hunter_guide.SNIPER_CAST_SECONDS_DEFAULT
    end
    local latency = inputs.latency
    if type(latency) ~= "number" then
        latency = 0
    end
    local grace = hunter_window.STEADY_SHOT_GRACE
    if type(grace) ~= "number" then
        grace = st.hunter_guide.STEADY_GRACE_DEFAULT
    end
    -- The frozen formula: the cast plus the latency must fit inside the next-shot window
    -- under the steady-shot grace (is_cast_safe floors its own latency buffer).
    return hunter_window.is_cast_safe(cast_seconds + latency, ttl, grace, latency) == true
end

-- Pure: the clip margin of a cast start - the seconds between the press and the LATEST
-- safe start (the last moment the cast still fits before the next Auto Shot). A
-- negative margin means the cast would clip the shot. The arithmetic mirrors
-- is_cast_safe exactly, so the margin and the engine's verdict can never disagree:
--   safe  <=>  cast + latency <= ttl + grace - max(latency, 0.03)
--        <=>  ttl >= cast + latency - grace + max(latency, 0.03)
-- so the deadline the cast has to beat is
--   deadline = cast + latency - grace + max(latency, 0.03)
-- and the margin is (ttl - deadline). A nil input (an unknown cast time, an unknown
-- time to the next shot) reports nil - never a guess.
function st.hunter_guide.cast_margin(cast_seconds, latency, time_until_next_shot, grace)
    if type(cast_seconds) ~= "number" or cast_seconds ~= cast_seconds then
        return nil
    end
    if type(time_until_next_shot) ~= "number" or time_until_next_shot ~= time_until_next_shot then
        return nil
    end
    if type(latency) ~= "number" or latency ~= latency then
        latency = 0
    end
    if type(grace) ~= "number" or grace ~= grace then
        grace = st.hunter_guide.STEADY_GRACE_DEFAULT
    end
    local safety_buffer = math.max(latency, 0.03)
    local deadline = cast_seconds + latency - grace + safety_buffer
    return time_until_next_shot - deadline
end

-- Pure: one engine tick. Reads `inputs`, writes the frozen display fields into the
-- caller-owned `out` table and returns it. See the module header for the rule matrix.
function st.hunter_guide.evaluate(inputs, out)
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
        out.effective_weapon_speed = nil
        out.steady_ratio = nil
        return out
    end

    local action
    local hold = false
    local hold_text

    -- The Wrath matrix is cooldown-priority (no auto-shot management): its arms
    -- sit ahead of the window hold, and the window hold itself is compiled out
    -- on Wrath. Both gates read st.family, so every other family runs the exact
    -- old chain below.
    local is_wrath = st.family == "WRATH"

    -- The Forever upkeep/cast arms (rules F1-F2) sit with the TBC cooldowns:
    -- behind the window hold, above the weave. Only this gate reads st.family,
    -- so every other family runs the exact old chain below.
    local is_forever = st.family == "FOREVER"

    -- The SoD shares the ERA family token: the rune (chimera_known) is the
    -- discriminator, exactly like rule 5b's gate. is_sod is therefore NEVER a
    -- family read on its own.
    local is_era = st.family == "ERA"
    local is_sod = is_era and inputs.chimera_known == true
    local is_tbc = st.family == "TBC"

    if type(inputs.steady_remaining) == "number"
        or type(inputs.multi_remaining) == "number"
        or type(inputs.sniper_remaining) == "number"
        or type(inputs.aimed_remaining) == "number" then
        -- 1. A live Steady Shot, Multi-Shot, Sniper Shot or (Era) Aimed Shot cast
        --    is in progress: ride it.
        hold = true
        hold_text = "RIDE"
    elseif inputs.target_in_range == 0 and inputs.sniper_range_buff_active ~= true then
        -- 2b. The ranged range probe reads out of range: nothing prompts, ahead
        --    of every cooldown priority - the wrath arms included - and of the
        --    rule-7 queue ride. Byte-exact == 0 only (nil = unknown = allowed;
        --    boolean spellings are never treated as hold), matching the gather's
        --    raw IsSpellInRange shape on the shipped clients. A live Sniper range
        --    buff (Forever MM, sim-proven) bypasses this gate: the sim extends
        --    Auto range past 41yd for 3 shots, so the buffed shots still land.
        hold = true
        hold_text = "HOLD"
    elseif is_wrath and utility_due(inputs, "aspect_viper_known", "aspect_viper_active")
        and mana_below(inputs, st.hunter_guide.VIPER_MANA_FRAC_WRATH) then
        -- W0a. Wrath: the Aspect of the Viper (the APL's i=1, both the MM and the
        -- SV spine): the Viper is KNOWN down and the mana is under the APL's 10%.
        -- The buff is up -> never asked for; the mana is unknown -> never guessed.
        action = "aspect_viper"
    elseif is_wrath and utility_due(inputs, "aspect_dragonhawk_known", "aspect_dragonhawk_active")
        and mana_above(inputs, st.hunter_guide.DRAGONHAWK_MANA_FRAC) then
        -- W0b. Wrath: the Aspect of the Dragonhawk (the APL's i=2): the aspect is
        -- KNOWN down and the mana is over the APL's 30%.
        action = "aspect_dragonhawk"
    elseif is_wrath and inputs.killshot_known == true
        and is_off_cooldown(inputs.killshot_remaining_cd)
        and type(inputs.target_hp_frac) == "number"
        and inputs.target_hp_frac <= st.hunter_guide.KILL_SHOT_EXECUTE_FRAC then
        -- W1. Wrath: Kill Shot is ready and the target is in execute range.
        -- The execute sits above the WotLK APL's Silencing Shot row (i=3): the
        -- shipped rotation research calls the execute "always highest when
        -- available" (docs/research/rotations_wrath.md:9-16) and it is a burst
        -- moment - a ready interrupt must never shadow it.
        action = "kill_shot"
    elseif is_wrath and utility_ready(inputs, "silencing_shot_known", "silencing_shot_remaining_cd") then
        -- W0c. Wrath MM: Silencing Shot (the APL's i=3, the interrupt): known and
        -- off cooldown. It sits below the execute and above the upkeep rows.
        action = "silencing_shot"
    elseif is_tbc and utility_due(inputs, "aspect_viper_known", "aspect_viper_active")
        and mana_below(inputs, st.hunter_guide.VIPER_MANA_FRAC) then
        -- T0a. TBC: the Aspect of the Viper (the APL's i=0, the "Mana management"
        -- group): the Viper is KNOWN down and the mana is under the 5% start.
        action = "aspect_viper"
    elseif is_tbc and utility_due(inputs, "aspect_hawk_known", "aspect_hawk_active")
        and mana_above(inputs, st.hunter_guide.HAWK_MANA_FRAC) then
        -- T0b. TBC: the Aspect of the Hawk (the APL's i=0, the mana group): the
        -- Hawk is KNOWN down and the mana is back over the 25% stop.
        action = "aspect_hawk"
    elseif is_forever and utility_ready(inputs, "raptor_strike_known", "raptor_strike_remaining_cd")
        and inputs.weave_band == "melee" then
        -- F0a. Forever: Raptor Strike (the APL's i=1, the melee weave): known, off
        -- cooldown and the player is in melee range (the weave band; an unknown
        -- band never prompts).
        action = "raptor_strike"
    elseif is_forever and utility_due(inputs, "hunters_mark_known", "hunters_mark_active") then
        -- F0b. Forever: Hunter's Mark (the APL's i=2): the mark on the target is
        -- KNOWN down.
        action = "hunters_mark"
    elseif is_forever and utility_ready(inputs, "mongoose_bite_known", "mongoose_bite_remaining_cd")
        and inputs.weave_band == "melee" then
        -- F0c. Forever: Mongoose Bite (the APL's i=3, the melee hit): known, off
        -- cooldown and in melee range.
        action = "mongoose_bite"
    elseif is_forever and utility_ready(inputs, "immolation_trap_known", "immolation_trap_remaining_cd")
        and inputs.weave_band == "melee" then
        -- F0d. Forever: Immolation Trap (the APL's i=5, cast at melee range):
        -- known, off cooldown and in melee range.
        action = "immolation_trap"
    elseif is_forever and utility_ready(inputs, "wing_clip_known", "wing_clip_remaining_cd")
        and inputs.weave_band == "melee" then
        -- F0e. Forever: Wing Clip (the APL's i=6, the melee debuff): known, off
        -- cooldown and in melee range.
        action = "wing_clip"
    elseif is_forever and utility_due(inputs, "serpent_known", "serpent_active") then
        -- F0f. Forever: the Serpent Sting upkeep (the APL's i=8): the sting on the
        -- target is KNOWN down.
        action = "serpent"
    elseif is_wrath and inputs.lnl_ready == true
        and inputs.explosive_known == true then
        -- W-LnL. Wrath SV: Lock and Load free Explosive (ignores the cooldown:
        -- free + CD reset, sim 56344 22s ICD). Below the execute, above the
        -- normal priority; nil/false reads no window (the gather writes nil).
        action = "explosive"
    elseif is_wrath and inputs.lnl_ready == true
        and inputs.arcane_known == true
        and inputs.explosive_known ~= true then
        -- W-LnL (MM): the same free window spends Arcane (never on SV, where it
        -- shares its cooldown with Explosive Shot).
        action = "arcane"
    elseif is_wrath and inputs.chimera_known == true
        and utility_due(inputs, "serpent_known", "serpent_active") then
        -- W1a. Wrath MM: the Serpent Sting upkeep (the MM APL's i=5, between the
        -- execute at i=4 and the Chimera at i=7): the sting on the target is
        -- KNOWN down.
        action = "serpent"
    elseif is_wrath and inputs.chimera_known == true
        and utility_ready(inputs, "explosive_trap_known", "explosive_trap_remaining_cd") then
        -- W1b. Wrath MM: the Explosive Trap (the MM APL's i=6): known and off
        -- cooldown.
        action = "explosive_trap"
    elseif is_wrath and inputs.chimera_known == true
        and is_off_cooldown(inputs.chimera_remaining_cd)
        and (inputs.serpent_known ~= true or inputs.serpent_active ~= false) then
        -- W2. Wrath MM: Chimera Shot is ready (no naked Chimera while a known
        -- Serpent Sting is KNOWN to be down; an unknown debuff never withholds it,
        -- so the knowledge alone can never silence the prompt).
        action = "chimera"
    elseif is_wrath and inputs.explosive_known == true
        and is_off_cooldown(inputs.explosive_remaining_cd) then
        -- W3. Wrath SV: Explosive Shot is ready.
        action = "explosive"
    elseif is_wrath and inputs.explosive_known == true
        and utility_ready(inputs, "explosive_trap_known", "explosive_trap_remaining_cd") then
        -- W3a. Wrath SV: the Explosive Trap (the SV APL's i=6, behind the
        -- Explosive Shot pair at i=4/i=5): known and off cooldown.
        action = "explosive_trap"
    elseif is_wrath and inputs.explosive_known == true
        and utility_due(inputs, "serpent_known", "serpent_active") then
        -- W3b. Wrath SV: the Serpent Sting upkeep (the SV APL's i=7): the sting on
        -- the target is KNOWN down.
        action = "serpent"
    elseif is_wrath and inputs.explosive_known == true
        and utility_ready(inputs, "black_arrow_known", "black_arrow_remaining_cd") then
        -- W3c. Wrath SV: the Black Arrow (the SV APL's i=8): known and off
        -- cooldown.
        action = "black_arrow"
    elseif is_wrath and inputs.wrath_aimed_known == true
        and is_off_cooldown(inputs.wrath_aimed_remaining_cd) then
        -- W4. Wrath: Aimed Shot is ready (instant: the shared MM/SV tier).
        action = "aimed"
    elseif is_wrath and utility_ready(inputs, "utility_multi_known", "utility_multi_remaining_cd") then
        -- W4a. Wrath: the Multi-Shot (the MM APL's i=9 and the SV APL's i=10): the
        -- WotLK rank (49048), known and off cooldown. The WotLK Multi is an
        -- instant, so it takes no clip check (the WotLK arms never do).
        action = "multi"
    elseif is_wrath and inputs.arcane_known == true
        and inputs.explosive_known ~= true
        and is_off_cooldown(inputs.arcane_remaining_cd) then
        -- W5. Wrath MM early-phase: Arcane Shot is ready (never on SV, where it
        -- shares its cooldown with Explosive Shot).
        action = "arcane"
    elseif is_wrath and inputs.steady_known == true
        and is_off_cooldown(inputs.steady_remaining_cd) then
        -- W6. Wrath: Steady Shot is the demoted filler (no clip check: Auto Shot
        -- fires during the cast on WotLK).
        action = "steady"
    elseif not is_wrath
        and is_in_window(inputs.hidden_window_start, inputs.hidden_window_duration, inputs.now) then
        -- 2. Inside the hidden Auto-Shot window: starting a cast now would clip it.
        hold = true
        hold_text = "HOLD"
    elseif inputs.kc_known == true and is_off_cooldown(inputs.kc_remaining_cd) then
        -- 3. TBC: Kill Command is ready: the #1 BM priority (instant, never a clip).
        action = "kill_command"
    elseif inputs.bw_known == true and is_off_cooldown(inputs.bw_remaining_cd) then
        -- 4. TBC: Bestial Wrath is ready: popped on cooldown (instant).
        action = "bestial_wrath"
    elseif st.family == "ERA" and inputs.chimera_known == true
        and is_off_cooldown(inputs.chimera_remaining_cd)
        and (inputs.serpent_known ~= true or inputs.serpent_active ~= false) then
        -- 5b. Era-SoD: the Chimera Shot rune is ready (instant: above the Era
        -- weave, behind the window; no naked Chimera while a known Serpent is
        -- KNOWN to be down, unknown = allow like W2).
        action = "chimera"
    elseif st.family == "ERA" and inputs.lnl_ready == true
        and inputs.aimed_known == true
        and aimed_is_clip_safe(inputs) then
        -- SoD-LnL: free Aimed above the normal weave (ignores the cooldown, still
        -- clip-gated; sim 415413 trap proc. Nil/false reads no window).
        action = "aimed"
    elseif st.family == "ERA" and inputs.lnl_ready == true
        and inputs.multi_known == true
        and multi_is_clip_safe(inputs) then
        -- SoD-LnL: free Multi below Aimed (same window, mirroring the weave order).
        action = "multi"
    elseif inputs.rf_known == true and is_off_cooldown(inputs.rf_remaining_cd) then
        -- 5. Rapid Fire is ready: popped on cooldown (instant). Three families
        --    ask for it and the arm sits at each one's APL position: the ERA APL's
        --    i=1 (above the weave), the SOD APL's i=7 (behind the Chimera rune at
        --    i=3) and the TBC blanket cooldown layer (the TBC priority list has no
        --    Rapid Fire row of its own).
        action = "rapid_fire"
    elseif is_sod and inputs.killshot_known == true
        and is_off_cooldown(inputs.killshot_remaining_cd)
        and type(inputs.target_hp_frac) == "number"
        and inputs.target_hp_frac <= st.hunter_guide.KILL_SHOT_EXECUTE_FRAC then
        -- 5d. SoD: the Kill Shot execute (the APL's i=12, the SoD rank 409593):
        -- ready and the target is in the E20 phase. The APL's other half ("Rapid
        -- Fire up") is not modelled (the guide has no Rapid Fire aura read), so
        -- only the execute half fires.
        action = "kill_shot"
    elseif is_sod and utility_ready(inputs, "raptor_strike_known", "raptor_strike_remaining_cd")
        and inputs.weave_band == "melee" then
        -- 5e. SoD: the Raptor Strike (the APL's i=16, the melee weave): known, off
        -- cooldown and in melee range.
        action = "raptor_strike"
    elseif is_sod and utility_ready(inputs, "wyvern_strike_known", "wyvern_strike_remaining_cd")
        and inputs.weave_band == "melee" then
        -- 5f. SoD: the Wyvern Strike (the APL's i=17, the bleed): known, off
        -- cooldown and in melee range.
        action = "wyvern_strike"
    elseif is_sod and utility_due(inputs, "aspect_viper_known", "aspect_viper_active")
        and mana_below(inputs, st.hunter_guide.VIPER_MANA_FRAC) then
        -- 5g. SoD: the Aspect of the Viper (the APL's i=22, the OOM swap at 5%
        -- mana): the Viper is KNOWN down.
        action = "aspect_viper"
    elseif is_sod and utility_ready(inputs, "arcane_known", "arcane_remaining_cd") then
        -- 5h. SoD: the Arcane Shot (the APL's i=23, the SoD filler): known and off
        -- cooldown.
        action = "arcane"
    elseif is_sod and utility_due(inputs, "aspect_falcon_known", "aspect_falcon_active")
        and utility_due(inputs, "aspect_viper_known", "aspect_viper_active") then
        -- 5i. SoD: the Aspect of the Falcon (the APL's i=24: "neither the Viper
        -- nor the Falcon is up"): the Falcon is KNOWN down AND the Viper is KNOWN
        -- down - an unknown state on either never prompts.
        action = "aspect_falcon"
    elseif is_sod and utility_ready(inputs, "wing_clip_known", "wing_clip_remaining_cd")
        and inputs.weave_band == "melee" then
        -- 5j. SoD: the Wing Clip (the APL's i=27, the melee debuff): known, off
        -- cooldown and in melee range.
        action = "wing_clip"
    elseif is_forever and inputs.hawk_known == true
        and type(inputs.hawk_active_count) == "number"
        and inputs.hawk_active_count < st.hunter_guide.HAWK_MAX_ACTIVE
        and is_off_cooldown(inputs.hawk_remaining_cd) then
        -- F1. Forever: the Summon Hawk upkeep is due (instant: above the
        -- Forever weave, behind the window). An unknown count never prompts -
        -- and the gather always writes unknown today (NOT YET IMPLEMENTED,
        -- see the header), so this arm is dormant-safe by construction.
        action = "hawk"
    elseif is_forever and inputs.sniper_known == true
        and is_off_cooldown(inputs.sniper_remaining_cd)
        and sniper_is_clip_safe(inputs) then
        -- F2. Forever: Sniper Shot is due and the 4 s cast fits before the
        -- next shot (the MM tell: unknown off-Forever, so no other client can
        -- reach this arm through its own gather).
        action = "sniper"
    elseif is_forever and utility_ready(inputs, "arcane_known", "arcane_remaining_cd") then
        -- F3. Forever: the Arcane Shot (the APL's i=12, the filler behind the
        -- upkeep): known and off cooldown.
        action = "arcane"
    elseif is_forever and utility_ready(inputs, "utility_multi_known", "utility_multi_remaining_cd") then
        -- F4. Forever: the Multi-Shot (the APL's i=13, the filler behind the
        -- upkeep): known and off cooldown.
        action = "multi"
    elseif st.hunter_guide.TBC_ARCANE_ENABLED == true and st.family == "TBC"
        and inputs.arcane_known == true
        and is_off_cooldown(inputs.arcane_remaining_cd) then
        -- 5c. TBC: Arcane Shot filler (instant, sim APL core). DORMANT: ships
        -- false (no TBC arcane slot exists - base set full 6/6, wiring filed),
        -- so no live prompt changes until the slot lands.
        action = "arcane"
    elseif inputs.aimed_known == true and is_off_cooldown(inputs.aimed_remaining_cd)
        and aimed_is_clip_safe(inputs) then
        -- 6a. Era: Aimed Shot is due and the 3 s cast fits before the next shot.
        action = "aimed"
    elseif inputs.multi_known == true and is_off_cooldown(inputs.multi_remaining_cd)
        and multi_is_clip_safe(inputs) then
        -- 6b. Era and TBC: Multi-Shot is due and the cast fits before the next
        --    shot (the synced-duration clip math alone decides under haste).
        action = "multi"
    elseif is_era and not is_sod and utility_due(inputs, "serpent_known", "serpent_active") then
        -- 6d. Era: the Serpent Sting upkeep (the ERA APL's i=4, behind the Multi
        --    at i=3): the sting on the target is KNOWN down. The SoD never takes
        --    this arm (its Serpent is a pre-pull row, and the Chimera rune's own
        --    guard reads the same state).
        action = "serpent"
    elseif inputs.steady_known == true and is_off_cooldown(inputs.steady_remaining_cd)
        and cast_is_clip_safe(inputs) then
        -- 6c. Steady Shot is known here and ready, and the cast fits before the
        -- next shot. The known gate keeps clients without the spell (Era) silent
        -- instead of prompting the rank-1 fallback.
        action = "steady"
    elseif inputs.raptor_strike_queued == true or inputs.steady_shot_queued == true then
        -- 7. A queued on-next-swing ability is already showing on the bar: ride it.
        hold = true
        hold_text = "RIDE"
    end
    -- 8. Anything else: no action.

    -- The TBC micro display pair (header: display data, never rule inputs). The
    -- live cycle length (synced_duration preferred, exactly like the cast bar's
    -- window maths) IS the effective weapon speed once the client's haste
    -- applies; the ratio band falls out of it. Unknown cycle, unknown ratio:
    -- the engine never guesses either.
    local effective_weapon_speed
    local steady_ratio
    do
        local hunter_window = st.hunter_window
        if hunter_window and hunter_window.steady_ratio_band then
            local cycle_duration = inputs.synced_duration
            if type(cycle_duration) ~= "number" then
                cycle_duration = inputs.swing_speed
            end
            if type(cycle_duration) == "number" then
                effective_weapon_speed = cycle_duration
                steady_ratio = hunter_window.steady_ratio_band(cycle_duration)
            end
        end
    end

    out.action = action
    out.hold = hold
    out.hold_text = hold_text
    out.filler_slot = nil
    out.judge_slot = nil
    out.rotation_key = nil
    out.waiting_judgement = false
    out.effective_weapon_speed = effective_weapon_speed
    out.steady_ratio = steady_ratio
    return out
end
