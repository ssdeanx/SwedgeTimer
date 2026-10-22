# CLEU parity: SuperSwingTimer-WoW vs our chain (2026-10-22, desk `swing-cleu-parity`)

Scope: main.lua, swing_source.lua, compat.lua event paths, hunter_ui.lua cast reads,
tests/real_wire_state.lua legs. Untouched: run.sh, vendored Libs (byte-identical,
HU-29), TOCs, versions, options, bars.lua, classes/*.lua. Client scope HU-31
(lib path: era/anniversary/titanforge; Retail/Forever own API).

Reference (read-only, compared not lifted): /home/sam/SuperSwingTimer-WoW/
(SuperSwingTimer_State.lua =(HandleCLEU/HandleSpellcast*), SuperSwingTimer.lua
= event registration/dispatch, SuperSwingTimer_Constants.lua = spell tables).
Ours: vendored LibClassicSwingTimerAPI v32 + main.lua dispatcher/handlers +
swing_source.lua. Cross-client truth via `git -C /home/sam/wow-ui-source`
(classic_era, classic_anniversary, classic_titan, live, origin/forever).

## Skills confirmation

@bench-read ran (desks/journal.md lane table + swing_display + swing_engine_fix +
proctor_swing_gap + HU-22/25/27/28/29/31; journals before artifacts, new material
only). @desk-open ran (desks/swing-cleu-parity/ created, journal first, worked
there only). @desk-journal running (this lane's trail in desks/swing-cleu-parity/
journal.md). @signal-write runs at close (done signal + journal marker).

## Fixed in our side (main.lua only, 3 gaps)

### F1 — SPELL_EXTRA_ATTACKS never suppressed the swing restart
- SST: HandleCLEU counts extraAttackPending on SPELL_EXTRA_ATTACKS
  (State.lua:1337-1339) and consumes it INSTEAD of StartSwing on the next
  SWING_DAMAGE/MISSED (State.lua:1308/1322) — an extra attack never resets
  the cycle.
- Ours: the lib has NO extra-attack handler (HU-29 D5, confirmed); every Sword
  Spec / Windfury / Thrass extra swing re-anchored the bar via the lib's
  SwingStart. Paladin counted its own twist_extra_attacks_pending
  (classes/paladin.lua:900-906) but that arms twist attempts only, never the bar.
- Fix (main.lua:1011-1036 neutral pre-pass, :1273-1287 START, :1336-1350 STOP):
  SPELL_EXTRA_ATTACKS (player source) arms ST.extra_attack_pending; the lib's
  cancel-STOP while pending arms suppression; the extra's START is consumed
  instead of restarting (pending--, tail arm for the extra's own STOP, both
  STOPs ignored); ranged never suppresses; a direct START with a stale count
  and no STOP restarts normally and clears the count (self-healing — this is
  what the lib-free bars_state twist fixture shape needs); multi-extra chains
  re-arm through the tail branch. Effective on CLEU-registered classes only
  (paladin/warrior — registration contract pinned by bars_state:2495-2508 and
  main_init §13, deliberately NOT re-cut: out of this lane's write scope).

### F2 — incoming PARRY never hasted our cycle (lib arm dead, HU-29 D4)
- SST: target==player SWING_MISSED+PARRY shortens mh by 40% floored at 20%
  (State.lua:1365-1369 + ApplyParryHaste State.lua:1176-1194).
- Ours: lib:415 arm unreachable behind the lib:397 generic catch (confirmed);
  nothing our-side read incoming parries at all.
- Fix (main.lua:1045-1071 apply_parry_haste via the same pre-pass): remaining
  -40% floored at 20%, both ends moved together; nearly-ready cycles untouched;
  outgoing PARRY and non-PARRY misses ignored (pinned). Source/target gated on
  player_guid.

### F3 — druid form change never reset the melee cycle
- SST: SPELL_AURA_APPLIED on a druid form id resets the mh timer
  (State.lua:1356-1362).
- Ours: UPDATE_SHAPESHIFT_FORM only recoloured + set recent_form_change; the
  bar kept showing the dead cycle after a shift.
- Fix (main.lua UPDATE_SHAPESHIFT_FORM): on a real form change, mainhand
  is_full=true + on_bar_inactive (built-guarded, unbuilt-safe); the engine's
  next swing re-anchors.

## Assessed non-gaps (verified, no change)

- N1 SPELL_CAST_SUCCESS (CLEU Auto Shot, SST State.lua:1329): the UNIT path
  covers it everywhere — lib SUCCEEDED(75) Era/BCC/Wrath tables + our TBC
  fallback (maybe_drive_ranged_fallback). Redundant driver, not a gap.
  Cross-client: UNIT_SPELLCAST_SUCCEEDED documented on all four branches.
- N2 SPELL_DAMAGE queued-melee mh restart (SST State.lua:1343): the lib
  restarts mh on CAST via next_melee_spells (Era lib:890, BCC lib:983, Wrath
  lib:1125+ — HS/Cleave/Raptor/Maul all covered); SST's damage-land restart is
  a ~same-tick re-restart. Timing delta only, no our-side fix available
  (lib-owned) or needed.
- N3 SPELL_AURA_REMOVED / prevent lists: lib:436-444 handles pause-prevent +
  auraPreventSwingReset; our on_aura_change is scan-based (implicit removal).
- N4 UNIT_DIED/UNIT_DESTROYED enemy reset: enemy_swing.lua:599 handles it
  (reference State.lua:1373-1379). Covered.
- N5 UNIT_SPELLCAST_STOP/DELAYED: the lib deliberately does not register them;
  our shaman/warrior hooks (weave re-anchor/end, slam end) match or exceed
  SST's casting=false bookkeeping. Hunter pushback self-corrects via live
  UnitCastingSpell reads (display lane provenance contract).
- N6 swing_source (Forever): SST has no Forever model to compare (classic-only
  addon). Source covers PLAYER_SWING all hands + speed re-read + combat-exit
  STOP + WEAPON_SLOT_CHANGED equip rebuild (B2) + INFO-once; RANGE_UPDATE
  deliberately unregistered (display-only). Adequate; no gap names it.
- N7 compat event paths: UNIT_SPELLCAST_* payloads pass through raw;
  shaman/warrior tolerate nil ids via live-name fallback; hunter FAILED_QUIET/
  SUCCEEDED index by numeric spell_id (payloads numeric on every family).
  No compat change needed. START_AUTOREPEAT gated by probe, TARGET_SET_ATTACKING
  by family gate — both verified present-or-gated.
- N8 CURRENT_SPELL_CAST_CHANGED queue tint: SST does not use it; ours is a
  superset (HS/Cleave/Raptor/Maul tint). No parity gap.

## Filed, not fixed (needs another lane — out of this write scope)

- G1 Stale queue tint on INTERRUPTED/FAILED (warrior hs/cleave,
  hunter raptor/steady, druid maul: cleared on SUCCEEDED/FAILED_QUIET only;
  SST clears queued melee on interrupt, State.lua:1129+). The flags live in
  classes/*.lua — untouchable here (wiring_check §10 bans ST.<CLASS> in shared
  code). Severity LOW (CURRENT_SPELL_CAST_CHANGED re-probe self-heals most
  paths). Needs a class-lane follow-up.
- G2 Registration expansion (CLEU for hunter/druid/shaman/rogue so F1/F2 cover
  all classes): needs bars_state § + main_init §13 pin re-cuts — out of scope.
  Filed as follow-up; F1/F2 close the loop for paladin/warrior today.
- G3 Slam pause/extend on Era/BCC (SST PAUSE_SWING_SPELLS incl. Slam ids,
  Constants.lua:777+; lib Era/BCC pause tables EMPTY so Slam SUCCEEDED resets
  instead of extending; Wrath lib pauses correctly). Lib table content +
  in-client mechanics truth both needed; main cannot intercept a lib-internal
  reset. Filed HU-29-adjacent (lib content), mechanics UNVERIFIED (no sim
  truth that Era Slam pauses rather than resets).
- G4 Slashdot utility rows (HoJ/Holy Wrath/Repentance-style SUCCEEDED resets):
  SST RESET_SWING_SPELLS vs lib reset_swing_spells table-content delta,
  lib-owned, no dispatcher-level fix. Same HU-29-adjacent bucket as G3.

## Cross-client truth (git show, HU-31 scope)

- COMBAT_LOG_EVENT_UNFILTERED documented on classic_era, classic_anniversary,
  classic_titan AND live AND origin/forever (CombatLogDocumentation.lua on all
  five) — but per the standing in-tree decision only the classic line fires
  the classic combat log; Retail/Forever stay on their own APIs and our CLEU
  registration stays `not st.is_mainline` (unchanged). PLAYER_SWING documented
  ONLY on origin/forever (SwingTimerDocumentation.lua) — swing_source stays
  Forever-only. Correct per scope; no change.
- UNIT_SPELLCAST_SUCCEEDED / FAILED_QUIET / START_AUTOREPEAT_SPELL /
  STOP_AUTOREPEAT_SPELL / PLAYER_ENTER/LEAVE_COMBAT / UNIT_ATTACK_SPEED:
  documented on all of classic_era, classic_anniversary, classic_titan,
  origin/forever (UnitDocumentation/SpellBookDocumentation per branch).
  Our unconditional UNIT_* registrations + probed autorepeat gates hold on
  every in-scope family.

## Files + lines (this lane)

- main.lua: registration comment (:650-657), COMBAT_LOG_EVENT_UNFILTERED +
  note_extra_attack_or_parry + apply_parry_haste (:994-1071),
  SWING_TIMER_START suppression (:1266-1293), SWING_TIMER_STOP pairing
  (:1329-1352), UPDATE_SHAPESHIFT_FORM reset (druid block).
- tests/real_wire_state.lua: app_cleu/app_extra/app_incoming_miss helpers
  (:705-723) + 8 new legs (cleu-extra/-stop/-hands/-parry/-parry-neg/
  -stale/-chain/-form/-dispatch, :1763+).

## Validation (focused — full run.sh is the orchestrator's)

- lua5.1 tests/real_wire_state.lua → 760 checks, 0 failures (3 xfail HU-29).
- lua5.1 tests/main_init_state.lua → 975 PASS. tests/bars_state.lua → 885 PASS
  (an earlier suppression cut broke 2 paladin-band legs — the lib-free fixture
  drives CLEU without engine STARTs, leaving the count stale; fixed by the
  armed-flag redesign, re-verified green).
- Class suites: warrior 2046 / paladin 1234 / hunter 1744 / druid 1580 /
  shaman 1064 / rogue 1114 / hunter_guide 1970 — all PASS.
- luacheck: 2 warnings / 0 errors floor holds (main.lua:87 table.pack shim is
  pre-existing, line-shifted only).
- Mutations (fresh /tmp/opencode copies, removed after — all kill red):
  M1 EXTRA arm neutered → 8 FAIL; M2 START suppression neutered → 5 FAIL;
  M3 STOP pairing neutered → 7 FAIL (incl. both STOP legs after strengthening —
  the first cut was timing-lucky and passed vacuously, caught and fixed);
  M4 parry math zeroed → 1 FAIL; M5 form reset removed → 2 FAIL; M6 stale-clear
  removed → 3 FAIL.

## UNVERIFIED (needs in-client evidence)

- U1 Extra suppression live: sword-proc/WF/Thrash evening — bar holds cycle
  instead of jumping; /st diag swing counts climb without extra STARTs.
- U2 Parry haste live: mob parries → remaining shortens (diag/bar arithmetic).
- U3 Druid shift live: bar shows full face until the next swing after a shift.
- U4 G3/G4 mechanics truth (Era Slam pause vs reset) + G1 interrupt paths.
- U5 G2 expansion decision (operator call).
