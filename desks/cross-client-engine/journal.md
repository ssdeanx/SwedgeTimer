# cross-client-engine

## 2026-10-25 — opened

**Worked on:** opened for the cross-client engine wave: TASK A (restore the HU-23
LibRangeCheck protected-call removal, baseline RED) and TASK B (Forever/Retail native
swing engine vs classic vendored lib). Read AGENTS.md, CAIRN.md, workshop.md (lessons
1-18), bench/lessons.md, desks/journal.md tail, hands-up HU-23/25/28/29/31.

**Current state:** reading priors + the shipping swing_source.lua, compat.lua, main.lua
swing/range regions, the vendored LibRangeCheck, and Blizzard's origin/forever SwingTimer
before any edit.

**Next step:** confirm the RED baseline with the named suites, then TASK A restore.

## 2026-10-25 — TASK A landed (LibRangeCheck restored, offline green)

- **Root cause found:** the 2026-10-25 re-vendor commit `6e2bc2d` replaced the vendored
  `LibRangeCheck-2.0.lua` with a pre-patch upstream copy; every 2026-10-21 HU-23 change
  was gone. The post-patch file was recovered from the repo's own history (`29f1731`)
  and used as the reference implementation — **not** copied over: the 2026-10-25 base has
  unrelated upstream changes (MINOR_VERSION ...03, Mortal Coil entry, `useCombatCheckers`
  architecture) which are preserved. The guard package was ported 1:1.
- **Worked on:** `LibRangeCheck-2.0.lua:50-61` header; `:73-75` interact tables removed;
  `:402-417` modern-aware captures (`GetSpellInfo` shim via `C_Spell`, `GetItemInfo` /
  `IsItemInRange` via `C_Item`); `:429-456` `issecretvalue` + three probes; `:475`
  `minRangeCheck`; `:505-528` guarded `checkers_SpellWithMin` + `spell_min_range`;
  `:567-575` `getNumSpells` guard; `:627-673` 2-arg `createCheckerList` with the
  item/spell guards and no interact fallback; `:679-686` empty-list `getRange`;
  `:844-877` init `minRangeCheck` (`if HarmItems[15] and not modernItemRange`, warrior/
  rogue class-spell fallbacks); `:1196-1205` event guards.
- **Tests:** lrc_guard 141 PASS, range_source 148 PASS, secret_guard 432 PASS.
- **Mutations:** M1 (re-add interact checker + fallback) KILLED by both suites; M2
  (remove modern-item guard) KILLED 22/141.

## 2026-10-25 — TASK B landed (Forever native engine verified + two cycle fixes)

- **Cross-branch facts (shell-read):** `PLAYER_SWING` / `Blizzard_SwingTimer` exist ONLY
  on `origin/forever`; absent from `live`, `classic_era`, `classic_anniversary`,
  `classic_titan` (`git grep` / `git ls-tree` over `Interface`). Payload + enum cited:
  `SwingTimerDocumentation.lua:43-52`, `:71-82`.
- **Read Blizzard's bar line by line** (`Blizzard_SwingTimer.lua:141-161`, `:184-192`,
  `:319-330`). Two cycle-correctness fixes in `swing_source.lua`:
  1. `on_weapon_slot_changed` now **restarts** each live cycle at the equipped duration
     (was a proportional rescale) — mirrors Blizzard's `ResetSwingTimerForEquippedWeapon`
     and the classic lib's `PLAYER_EQUIPMENT_CHANGED`; same-speed swaps restart too.
  2. `on_player_entering_world` now **STOPs** live cycles before clearing (was a silent
     clear, which could leave a frozen bar).
- **Verified omissions, not added:** `PLAYER_TARGET_CHANGED` and
  `PLAYER_SWING_RANGE_UPDATE` are display-only arms in Blizzard's own engine (they never
  touch `swingDuration`/`swingEndTime`; the latter needs `C_SwingTimer.EnableRangeCheck`,
  which the addon never calls). Pinned as not-registered in the matrix.
- **Diag:** `main.lua:2690-2702` runtime line now leads with
  `swing_engine=vendored-lib(lib) | swing_source(PLAYER_SWING) | inert(no-feed)`.
- **New suite:** `tests/engine_matrix_state.lua` (101 checks) — era/anniversary/titan/
  forever/retail: family, engine, event set, payload shape, probe-reject, probe-approve,
  interface-only 16001.
- **Tests:** swing_source 159 PASS; main_init 1050 PASS (+3 diag pins); real_wire 882/0
  (2 xfail HU-29); smoke 232/0; engine_matrix 101 PASS.
- **Mutations:** 6/6 killed on `/tmp/opencode/engine-mut/tree`, every file restored
  byte-identical (M1/M2 LRC, M3 IsEventValid gate, M4 swing-type map, M5 swap restart,
  M6 diag label).
- **Current state:** offline green. Report filed:
  `bench/cross_client_engine_2026-10-25.md`. `run.sh` line for the new suite is FILED to
  the orchestrator (run.sh not edited).
- **Next step:** orchestrator adds the run.sh line + runs the full suite; operator does
  the in-client checks (Forever bars/swing engine line, Retail inert + one notice,
  Anniversary no ADDON_ACTION_BLOCKED).

## 2026-10-25 — addendum: hunter mainhand mixed with ranged (cast reset)

- **Lead verified per family** (shipped v32 tables): `UNIT_SPELLCAST_START` sets
  `casting`/`preventSwingReset`; `SUCCEEDED` resets BOTH melee hands for any cast not in
  `noreset_swing_spells` (`LibClassicSwingTimerAPI.lua:620-631`). Auto Shot 75: Era/BCC go
  through the casting branch (the concurrent class guard gates it by range), **Wrath has
  `reset_swing_spells[75] = true` (`:1161`) so it always resets**. Steady 34120/25258 is
  already exempt on BCC/Wrath (the lead's Steady suspicion was stale). Multi-Shot, Aimed
  (BCC all ranks; Wrath r2+), Arcane and Serpent were **not** exempt anywhere.
  Upstream `main` (MINOR 39) has the same gaps.
- **Fix chosen: (ii) per-version `noreset_swing_spells` entries** (branch tables at
  `:996`, `:1116`, `:1381`): full classic-line rank ladders for Multi-Shot, Aimed Shot,
  Arcane Shot and Serpent Sting (41 ids, `wowhead.com/wotlk/spell=<id>` redirect-verified;
  ids a client lacks are inert). Auto Shot 75 deliberately NOT added — its reset is
  range-dependent and owned by `classes/hunter.lua suppress_auto_shot_melee_reset`
  (bars-range-hunter lane); a blanket entry would kill the melee-weave reset.
  Why not the main.lua restore: the lib's decision is synchronous at START; an our-side
  restore depends on AceEvent-vs-lib frame ordering or a deferred `C_Timer.After(0)`
  unwind, while the table entry has no tick, no ordering and no one-frame phantom cycle.
- **Proof:** new `tests/real_wire_state.lua` "HUNTER CAST RESET" leg — era/anniv/titan,
  real lib + real v7 + real dispatcher: Multi/Aimed/Arcane/Serpent (and Steady where it
  exists) fire zero melee STARTs and leave the anchors; controls (Raptor Strike, a neutral
  cast) still reset. 978/0. Mutations M7/M8/M9 (drop one id from Era/BCC/Wrath) all kill.
- **Filed, not taken:** Titanforge `reset_swing_spells[75]` blocks the class guard's range
  rule — one-line removal recommended to the operator. `bench/bars_range_hunter_2026-10-25.md`
  was not on disk (their lane in flight); the UI re-anchor cause is theirs.
- **Current state:** all seven named suites green + hunter_state/hunter_window_state/
  bars_state crossfire green. Report updated (§2.6, §3, §3.1, §4, §5).
- **Next step:** operator in-client: Multi/Aimed/Arcane/Serpent at range must not move the
  melee bars; Raptor Strike still must. Orchestrator: run.sh line + full suite.
