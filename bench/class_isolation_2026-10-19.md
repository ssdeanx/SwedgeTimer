# bench/class_isolation_2026-10-19 — full-tree class isolation sweep (READ-ONLY)

Desk: class-isolation. Date: 2026-10-19. No addon files touched; no code edits; no git.
Single NEW file per `bench/briefs/brief_class-isolation-sweep_2026-10-19.md` (absent-at-start confirmed via glob: no `bench/class_isolation*` before write).

Subject (read in-tree 2026-10-19): `classes/druid.lua`, `classes/hunter.lua`,
`classes/paladin.lua`, `classes/shaman.lua`, `classes/warrior.lua`,
`classes/rogue.lua` (full), root `druid_guide.lua`, `hunter_guide.lua`,
`shaman_guide.lua`, `warrior_guide.lua`, `rogue_guide.lua` (full),
`twist.lua`, `weave.lua`, `nextaction.lua`, `druid_energy.lua` (full),
`compat.lua` (reference only — the single cross-client layer, supposed to be called by all).

Extends, never re-derives: `bench/rogue_client_isolation_2026-10-19.md`
(F1 HIGH + F2/F3/F4), `bench/class_matrix_2026-10-19.md` (§§10/12 TOC + visuals),
`bench/lessons.md` (remembered-id, no-mainline-gate, enumerate-before-scrape rules).
Rogue F1 fix state from journal: vendored into `st.rogue_guide`, closure pin
`tests/rogue_state.lua:679-680` — verify closure holds, don't re-audit as new.

Evidence bar: every file:line below was read on current disk 2026-10-19.
Code-vs-comment separated for every hit. Anything not provable offline would be
marked UNCONFIRMED — there are none in this sweep (all verdicts are static
presence/absence proofs, not client behaviour).

## 0. Verdict (orchestrator summary)

- **Runtime-reached cross-class deps: 0.** No class file executes a read of
  another class's `ST.<CLASS>` table, `st.<other>_guide`, `st.druid_energy`
  (non-druid), `st.twist` (non-paladin), `st.weave` (non-shaman),
  `st.nextaction` (non-paladin), or `st.hunter_window` (non-hunter) on any live path.
- **Rogue F1 closure: HOLDS (CLOSED).** Zero `st.druid_energy` strings in
  `classes/rogue.lua` (grep-negative); rogue hot path reads only own
  `st.rogue_guide`. Prior HIGH is fixed, not re-filed.
- Everything else is one of three allowed shapes: (a) comment-only precedent
  cites (dead text), (b) own-module reads of a TOC-shipped helper
  (druid_energy/hunter_window/twist/weave/nextaction/own guide, guarded where
  archival), (c) shared infra every class is supposed to call
  (st.api/st.family/st.hud/st.nextaction_ui/st.lust_supported/st.practice_ui).
- **Fix lanes needed: 0.** Every hit below carries an actionable disposition:
  NO ACTION (with rationale) or ALREADY-CLOSED (with pin).

## 1. Findings (file:line + reachability + severity + fix direction)

### C1–C5 INFO — comment-only `ST.<OTHERCLASS>` mentions (dead text, no action)

Each found by grep `ST\.(DRUID|HUNTER|PALADIN|SHAMAN|WARRIOR|ROGUE)` per class
file excluding self, then read to confirm `--` comment prefix:

- C1 `classes/druid.lua:2051-2052` — rotation-contract header: "following the
  paladin's shape (ST.PALADIN. get_rotation_key in rotationtext.lua)". Reachability:
  dead comment. Severity: INFO. Fix: NO ACTION (precedent cite, the permitted use
  of comments per rogue F3).
- C2 `classes/hunter.lua:1474-1475` — same shape note (ST.PALADIN). Dead comment.
  INFO. NO ACTION.
- C3 `classes/shaman.lua:2690-2691` — same shape note (ST.PALADIN). Dead comment.
  INFO. NO ACTION.
- C4 `classes/warrior.lua:2829-2830` — same shape note (ST.PALADIN). Dead comment.
  INFO. NO ACTION.
- C5 `classes/rogue.lua:1398-1399` — rotation-contract header: "following the
  hunter's shape (ST.HUNTER. get_rotation_key in classes/hunter.lua:1337-1352)".
  Dead comment; no code path calls it (rogue `get_rotation_key` at `:1438-1445`
  reads only own `ST.ROGUE.guide` + `st.rogue_guide`). INFO. NO ACTION.

### R1 CLOSED — rogue F1 closure (was HIGH, now verified fixed)

- Lines: `classes/rogue.lua` grep `st\.druid_energy` → **zero hits**
  (code or comment — the word does not appear in the file); own-EMA header
  `:30-32` ("TTD via the rogue-owned HP/s EMA (st.rogue_guide, vendored from the
  druid D4 precedent)") and `:498-500` ("vendored from the druid D4 precedent
  into st.rogue_guide … no cross-class runtime read") are precedent cites, dead
  text. Runtime TTD at `:505-506` reads `local rg = st.rogue_guide` only.
  Test pin `tests/rogue_state.lua:679-680` asserts the absence
  (`rogue_src:find("st.druid_energy", 1, true) == nil`).
- Reachability: N/A (absent). Severity: was HIGH, now CLOSED. Fix direction:
  ALREADY FIXED — vendored EMA lives in `rogue_guide.lua:193-241`
  (`TTD_EMA_ALPHA`, `TTD_SAMPLE_SECONDS`, `update_hp_velocity`,
  `get_time_to_die`); keep the static pin; do not reintroduce a
  `st.druid_energy` read. No lane.

### O1 ALLOWED — druid reads own `st.druid_energy` + own `st.druid_guide`

- Own-helper upvalue `classes/druid.lua:47` (`local druid_energy = st.druid_energy`).
  Uses: `:747` (`is_tick_gain`), `:778-779` (`get_energy_tick_fraction` +
  `ENERGY_TICK_SECONDS`), `:800` (`get_form_label`), `:823-824`
  (`get_gcd_tick_fraction`), `:867` (`get_time_to_energy_cost`), `:1578`
  (`TTD_SAMPLE_SECONDS` after guard). Guards: `:976` (`if not enabled or not
  druid_energy`), `:1305-1307` (`if not druid_energy then return` — HUD runs
  before the gate at `:1302-1303` so HUD works without the module),
  `:1393`/`:1405` (debuff-scan gates), `:1542-1544` (TTD sampler gate).
  Reachability: runtime-reached, own module. Severity: NONE (own helper, not
  cross-class). Fix: NO ACTION — `druid_energy.lua` ships in all 7 TOCs
  (representative `SwedgeTimer_Mists.toc:41`; all seven verified §5), loads
  before `classes/`; guards cover archival flavours. Note: the bare upvalue at
  `:47` is safe only because every deref site is gated — do not add an
  ungated `druid_energy.*` deref.
- Own guide: `:843` (`(st.druid_guide and st.druid_guide.SHRED_COST_TBC) or 42`,
  nil-guarded), `:1762-1763` (`if st.druid_guide and st.druid_guide.evaluate`),
  `:2094` (`local engine = st.druid_guide`). Runtime-reached, own. NO ACTION.

### O2 ALLOWED — hunter reads own `st.hunter_window` + own `st.hunter_guide`

- Own-helper upvalue `classes/hunter.lua:185` (`local hunter_window =
  st.hunter_window`, comment `:183-184` documents TOC-before-classes ordering).
  Consumed through guarded call sites per prior audits; no other class reads
  `st.hunter_window` (repo-wide grep: only `classes/hunter.lua:185`,
  `hunter_guide.lua:374,412,450,488,673`, `hunter_ui.lua`, `practice_ui.lua:3296`
  orchestrator stub, tests). Reachability: runtime-reached, own family.
  Severity: NONE. Fix: NO ACTION.
- Own guide: `:1283-1284` (`if st.hunter_guide and st.hunter_guide.evaluate`),
  `:1516` (`local engine = st.hunter_guide`). NO ACTION.
- `hunter_guide.lua:374-377` (`local hunter_window = st.hunter_window` +
  `if not (hunter_window and hunter_window.time_until_next_shot and
  hunter_window.is_cast_safe) then return false`) — own-helper read inside own
  guide, nil-guarded. ALLOWED. NO ACTION.

### O3 ALLOWED — paladin reads own `st.twist` + `st.nextaction`

- `st.twist` (paladin seal-twist engine, ships all 7 TOCs): `classes/paladin.lua`
  `:569` (`SOC_PROC_IDS`), `:618` (`detect_twist_attempt`), `:638/640/644`
  (`detect_twist_success[_name]`), `:930`/`1374` (`is_twist_seal_active`),
  `:936` (`get_reseal_marker_fraction`), `:1146` (`get_window_seconds`),
  `:1523` (`is_twist_impossible`). All unguarded — correct, because `twist.lua`
  loads before `classes/` on every flavour. No non-paladin file reads
  `st.twist` (repo grep: only `classes/paladin.lua`). Reachability:
  runtime-reached, own-supporting. Severity: NONE. Fix: NO ACTION.
- `st.nextaction` (paladin decision engine, ships all 7 TOCs):
  `:1156-1157` (GUARDED: `st.nextaction and st.nextaction.apply_lust_window
  and …` with comment `:1148-1150` documenting the archival-loader degrade),
  `:2530` (`local na = st.nextaction` in gather), `:2797/:2835/:2843`
  (provider wiring), `:2935-2937` (`st.nextaction and st.nextaction.CS_SPELL_ID`),
  `:2950` (`st.nextaction and st.nextaction.JUDGEMENT_SPELL_ID or 20271`),
  `:3022` (`st.nextaction and st.nextaction.exorcism_target_types`).
  No non-paladin class file reads `st.nextaction` (only orchestrators:
  `rotationtext.lua:228,252-253`, `practice.lua:388`, `practice_ui.lua`
  — out of scope, allowed multiplexing). Reachability: runtime-reached, own.
  Severity: NONE. Fix: NO ACTION — do not add an unguarded deref outside the
  `:1156` pattern; the lust-window guard is the template.

### O4 ALLOWED — shaman reads own `st.weave` + own `st.shaman_guide`

- `st.weave` (shaman weave engine, ships all 7 TOCs): `classes/shaman.lua`
  `:327-328` (`SPELL_GROUPS`), `:404-405` (`FAMILIES`), `:460-461`
  (`MW_MAX_STACKS`), `:552` (`get_max_haste_multiplier`), `:590`
  (`has_maelstrom_weapon`), `:599/601` (`get_maelstrom_multiplier` +
  `get_effective_cast_time`), `:662` (`get_cast_start_fraction`), `:1127-1135`
  (`MW_MAX_STACKS`/`get_mw5_spender`/`get_flame_shock_remaining`/
  `should_hold_mw5`), `:1144-1145` (`FAMILIES`), `:1167`
  (`get_marker_fraction`), `:1184-1185` (`get_clip_amount`/`is_clipped`),
  `:1188` (`clamp_fraction`), `:1195/1197`
  (`get_projected_impact_fraction`/`get_spark_fraction`), `:1242/1248/1253`
  (windfury ICD + tint), `:1400-1409` (flameshock), `:1490-1499`
  (stormstrike), `:1525-1534`/`:1602-1609` (cooldown + stormstrike-hold),
  `:1627` (`clamp_fraction`), `:1742` (`get_shield_tracker_state`),
  `:1821/1823` (`LAVA_BURST_COLOR`/`FAMILY_COLORS`), `:1877-1909`
  (position-state + marker), `:1939` (`get_cast_zone_bounds`), `:1986-1988`
  (`get_dw_sync_offset`/`is_dw_desynced`), `:2004`
  (`get_flurry_icd_remaining`), `:2069` (`clamp_fraction`), `:2182/2195-2196/2219`
  (marker visuals). Guard exemplar `:2738-2740` (`if st.weave == nil then return
  nil` in `get_rotation_key`); hot-path sites assume presence because
  `weave.lua` loads before `classes/` on every flavour. No non-shaman class
  reads `st.weave` (only `practice.lua:2414,2423,2440` grading orchestrator —
  out of scope). Reachability: runtime-reached, own. Severity: NONE. Fix:
  NO ACTION.
- Own guide: `:2479` (`st.shaman_guide and st.shaman_guide.MAGMA_REFRESH_DEFAULT
  or 3`), `:2514-2515` (`if st.shaman_guide and st.shaman_guide.evaluate`),
  `:2734` (`local engine = st.shaman_guide`). NO ACTION.

### O5 ALLOWED — warrior reads own `st.warrior_guide`

- `classes/warrior.lua:1671` (`local guide = st.warrior_guide` in slam helper),
  `:1841` (same in second call site), `:2539-2540`
  (`if st.warrior_guide and st.warrior_guide.evaluate`), `:2871`
  (`local engine = st.warrior_guide`). All guarded at the evaluate sites;
  comments `:1667`, `:1813`, `:2093`, `:2531` document the contract. No other
  class reads `st.warrior_guide`. Reachability: runtime-reached, own.
  Severity: NONE. Fix: NO ACTION.

### O6 ALLOWED — rogue reads own `st.rogue_guide` (F1 fixed shape)

- `classes/rogue.lua:506` (`local rg = st.rogue_guide` in `get_time_to_die`,
  guarded `:507` `type(rg) ~= "table"` → nil TTD), `:623` (`local engine =
  st.rogue_guide`), `:663` (`local rg = st.rogue_guide` in gather),
  `:891` (visuals), `:1236-1239` (`st.rogue_guide and st.rogue_guide.POOL_BANDS`
  guarded band read), `:1440` (`local engine = st.rogue_guide` in
  `get_rotation_key`). No `st.druid_energy` anywhere in the file (R1).
  Reachability: runtime-reached, own. Severity: NONE. Fix: NO ACTION — keep
  the `:507`/`:1236` guards as the template; never cross-read another
  class's guide.

### S1 ALLOWED — shared infra every class is supposed to call (not class code)

- `st.api` (compat wrappers): `druid.lua` et al via `local api = st.api`;
  `compat.lua` is the single crossing point per AGENTS.md. All six classes
  call it; `compat.lua` calls zero class tables (§4). ALLOWED. NO ACTION.
- `st.family`: read in `druid.lua:743`, `rogue.lua:1108/1239`,
  `druid.lua:843` (`shred_countdown_cost`), `hunter.lua`, `shaman.lua:2490`
  (`is_totem_twist_family(st.family)` arg — family *value* passed in, not a
  class read), etc. Family token, not class code. ALLOWED. NO ACTION.
- `st.hud` (shared HUD frame): guarded `if st.hud then st.hud.init(self)` /
  `st.hud.on_bar_update(self, hand)` in all six — `paladin.lua:224-225,
  1329-1330`; `shaman.lua:961-962,2116-2117`; `rogue.lua:1336-1337,1375-1376`;
  `hunter.lua:383-384,403-404`; `druid.lua:262-263,1302-1303`;
  `warrior.lua:543-544,2064-2065`. ALLOWED (sibling-pattern frames).
  NO ACTION.
- `st.nextaction_ui` (shared guide frame): guarded init/apply/tick in all six
  — `paladin.lua:197-198,1318-1323`; `druid.lua:255-256,1289-1294`;
  `hunter.lua:376-377,422-427`; `shaman.lua:953-954,2104-2109`;
  `warrior.lua:536-537,2052-2057`; `rogue.lua:1330-1331,1365-1370`.
  ALLOWED. NO ACTION.
- `st.lust_supported` (compat-owned flag): `paladin.lua:1153`,
  `shaman.lua:1323,1344`, `rogue.lua:574,583`, `hunter.lua:1245`. Compat-owned,
  not class-owned. ALLOWED. NO ACTION.
- `st.practice_ui` / `st.practice` (practice-mode guards): `paladin.lua:216-217,
  251,277,588,2894,2898`; rogue/paladin `on_bar_update` practice branches.
  Shared frame. ALLOWED. NO ACTION.

### P1–P4 CLEAN — pure root modules touch only their own table

- P1 `twist.lua:18-168` — only `st.twist` (self-registration + self-calls
  `:63`, `:87`, `:95`, `:153`). Zero `ST.<CLASS>`, zero other `st.*`.
  WoW-free pinned (`:168`). CLEAN. NO ACTION.
- P2 `weave.lua:22-615` — only `st.weave` (self-calls throughout, e.g.
  `:176`, `:191`, `:235`, `:302-305`). One comment mention
  `:562-563` ("through compat's api.GetTotemInfo wrapper (ST.SHAMAN.
  refresh_twist_from_totems)") — dead text describing the caller, not a read.
  INFO. NO ACTION on the comment.
- P3 `nextaction.lua:98-830` — only `st.nextaction` (self-calls `:198`,
  `:343`; pure helpers `:704` note). Zero cross refs (grep for
  `st.(druid_energy|rogue_guide|…|twist|weave)` → none). CLEAN. NO ACTION.
- P4 `druid_energy.lua:15-261` — only `st.druid_energy` (self-calls
  `:58`, `:72-73`, `:98-99`, `:217`, `:221`, `:247`, `:249`). Zero cross refs.
  WoW-free (`:5`, `:260-261`). CLEAN. NO ACTION. Note: despite the
  `druid_`-prefixed name it is a root pure module consumed only by
  `classes/druid.lua` (§O1) since rogue vendored its copy — the name is now
  accurate, not a shared dependency.

### G1 CLEAN — root guides touch only their own table (+ own helper)

- `druid_guide.lua:307+` only `st.druid_guide`; comments `:4,6,9`
  (ST.<CLASS> contract shape) and `:144` (druid_energy anchor note) are dead
  text. No code read of any other guide/helper. CLEAN. NO ACTION.
- `hunter_guide.lua:340+` only `st.hunter_guide` (+ guarded own-helper
  `st.hunter_window` at `:374-377`, §O2); comments `:4,7,16` dead text.
  CLEAN. NO ACTION.
- `shaman_guide.lua:161+` only `st.shaman_guide`; comments `:4,6,10` and
  `:141-142` (`st.weave.is_totem_twist_family` mentioned as the *gather's*
  behaviour, not a read — the guide itself never dereferences `st.weave`).
  Verified: grep `st.weave` in `shaman_guide.lua` → comments only.
  CLEAN. NO ACTION.
- `warrior_guide.lua:257+` only `st.warrior_guide` (self-call `:364`);
  comments `:4,6,9` dead text. CLEAN. NO ACTION.
- `rogue_guide.lua:137+` only `st.rogue_guide` (self-calls throughout
  `:215`, `:247`, `:266-271`, `:512-584`); header comments `:4,7,39` dead
  text; `:186-189` documents the vendored EMA provenance ("no cross-class
  runtime reads on the guide hot path") — dead text recording R1.
  CLEAN. NO ACTION (reword `:186-189` only if the EMA constants ever change).

### T1 VERIFIED — TOC coverage (pure modules load for every family that uses them)

- All 7 TOCs list `twist.lua`, `weave.lua`, `druid_energy.lua`,
  `nextaction.lua`, `warrior_guide.lua`, `druid_guide.lua`,
  `shaman_guide.lua`, `hunter_guide.lua`, `rogue_guide.lua` in dependency
  order before `classes/` (representative `SwedgeTimer_Mists.toc:38-47`;
  identical tails per `bench/class_matrix_2026-10-19.md` §10, not re-derived).
  Unguarded own-module derefs (§O3–O4 hot paths) are therefore safe on every
  shipped flavour; the few guarded sites (`paladin.lua:1156`,
  `shaman.lua:2738`, all `*.guide.evaluate` dispatches, `druid.lua:976+`)
  cover archival loaders only. NO ACTION.

### N1 NOTED — orchestrator multiplexing (explicitly not class-to-class, no action)

For the record, so a future grep does not re-file these as hits (all OUT of
the subject scope, all supposed to touch multiple classes):
`config.lua:58-66` (aggregates `ST.*.defaults`), `config_presets.lua`
(per-class `ST.*.defaults` blocks), `option_tables.lua` (per-class sections +
`st.rogue_guide` threshold read `:4360` for widget wiring),
`rotationtext.lua:222` (`ST.PALADIN.get_rotation_key` lives there by documented
cut-and-paste; dispatches by `player_class`), `main.lua`/`bars.lua`/`diag.lua`
(hook/provider dispatch), `practice.lua:2414,2423,2440` (`st.weave` grading),
`practice_ui.lua`/`hunter_ui.lua` (own-family helpers + orchestrator stubs),
`tests/` (sandbox fixtures + pins, incl. `tests/rogue_state.lua:442`
harness-scope module list — mirror of old F2, harness-only).
None is a class file reading another class file. NO ACTION.

## 2. Per-client note

No per-client divergence exists in the isolation surface: the 0 cross-class
reads hold on every family because the reads are absent from the source, not
gated per client. TOC shipping is identical across all 7 flavours (§T1), and
shared-frame calls are nil-guarded on every client (§S1). No UNCONFIRMED items
— isolation is a static property, fully provable offline.

## 3. Tooling log

Code Mode only, no web. `read` in-tree for every anchor above; `grep` for the
absence proofs (per-class `ST\.(OTHER)` sweeps §C1–C5; `st\.(guide|energy|
twist|weave|nextaction|hunter_window|enemy_swing|weave_range|hud|practice)`
sweeps §O1–O6/S1; guide-file `ST\.|st\.(…)` sweeps §G1; pure-module sweeps
§P1–P4; `compat.lua` both-direction sweeps §S1; TOC tail grep §T1).
`glob` confirmed `bench/class_isolation*` absent before write. No suite runs
(read-only brief — harness baseline cited from `desks/journal.md:8`, 37/0,
not re-proven in-lane).
