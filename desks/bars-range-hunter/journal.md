# desk: bars-range-hunter

Lane `bars-range-hunter`, session `ses_e8c1621f9ffe2EsMz0luIPLGi1`
(central row: `desks/journal.md`, wave 2026-10-25).

Write scope: `bars.lua`, `weave_range.lua`, `classes/hunter.lua`, `hunter_ui.lua`,
`tests/weave_range_state.lua`, `tests/hunter_state.lua`,
`tests/hunter_guide_state.lua`, `tests/hunter_window_state.lua`,
new `tests/weave_bar_state.lua`; `tests/bars_state.lua` for a real contract pin only.
No git, no lint config, no TOC/main/compat/config/options/practice/nextaction/hud.

## worked on — 2026-10-25

### priors read
- `AGENTS.md`, `CAIRN.md`, `workshop.md` (lessons 1-18), `bench/lessons.md`,
  `desks/journal.md` (tail + 2026-10-22/23 swing entries), the wave's dispatch block.
- `bench/swing_hunter_bars_2026-10-22.md`, `bench/audit_hsp_findings_2026-10-22.md`,
  `bench/nil_sweep_tree_2026-10-22.md` §22.
- Orchestrator pre-reconcile findings (`desks/journal.md` 2026-10-25): the lib
  cast-reset lead, the weave-range shape, HU-23.

### Task A — hunter mainhand vs ranged: DIAGNOSED AND FIXED
1. **Per-hand write audit first** (no edits): every write to `self[hand]` is keyed by the
   event's own hand; no ranged event writes a melee hand and no melee event writes
   `ranged` on the classic line. Full truth table: `bench/bars_range_hunter_2026-10-25.md`
   §2. The mixing was never state ownership.
2. **Engine defect, proven on the SHIPPED lib** (scripted sandbox, real LibStub +
   CallbackHandler + `Libs/LibClassicSwingTimerAPI`): `START(75)+SUCCEEDED(75)` fires
   START for **mainhand, offhand AND ranged** — every Auto Shot restarted both melee
   bars. Steady 34120 fires nothing (it was already exempt; the orchestrator's note that
   Steady leaked was wrong). Aimed 19434 leaked too; the cross-client-engine lane has
   since exempted the ranged damage shots in the vendored tables and delegated Auto Shot
   to this lane.
3. **Layout defect**: `hunter_ui.sync_melee_anchor` (pre-fix :508-546) re-anchored the
   melee bars under the ranged bar whenever the cast bar was visible — and the cast bar
   is visible for the Auto Shot hidden-window face 0.5 s of every cycle, so at range with
   no melee the bars hopped into the ranged stack once per Auto Shot.
4. Fixes shipped: the melee re-anchor is retired (`hunter_ui.lua:472-488`, call sites and
   helpers removed); new class guard `ST.HUNTER.suppress_auto_shot_melee_reset`
   (`classes/hunter.lua:822-860`) arms the engine's own `preventSwingReset` while an Auto
   Shot cast is live **at range** and leaves the reset alone in melee (the reference's
   own rule, SuperSwingTimer_State.lua:1516-1536). Classic line only; +3 file-scope
   locals (176 -> 179 by the compiler count, gate 190).

### Task B — standalone horizontal ranged-distance bar: REBUILT
`weave_range.lua` rewritten (own top-level frame, horizontal fill, 1.0 at <=5 yd, 0.0 at
>=35 yd hunter / >=30 yd others, yards + MELEE/IN RANGE/OUT label, UnitDistance only,
nil = ON for hunters / OFF elsewhere, explicit false off, no distance read on any
disabled/unknown path, unknown never paints 0, anchor above the ranged bar with the
hunter stack reserved by height, screen clamp, 0.5 s disabled cadence and latched
paints). Pure maths + enable rule pinned in `tests/weave_range_state.lua` (83 checks);
frame/gating contract in the NEW `tests/weave_bar_state.lua` (96 checks).

## current state — DONE, all focused suites green

- `tests/weave_range_state.lua` 83/0; `tests/weave_bar_state.lua` 96/0 (NEW);
  `tests/hunter_state.lua` PASS 1824 (was 1796); `hunter_guide_state` 1976/0;
  `hunter_window_state` 213/0; `bars_state` 956/0; `smoke` 232/0;
  `bars_lazy_state` 52/0; `class_activation_state` 70/0; `main_init_state` 1050/0.
- `luacheck` on every touched file: 0 warnings / 0 errors.
- 7 mutation proofs on `/tmp/opencode/mut` (M1 pre-fix hunter_ui kills 9 pins; M2 guard
  disarmed kills 8 incl. the real-engine leg; M3 in-melee inverted 6; M4 far bound 5;
  M5 unknown-as-0 3; M6 disabled-path read 6; M7 cadence 4). Copy deleted.
- Bench report: `bench/bars_range_hunter_2026-10-25.md`.

## next step

- Orchestrator: add `run "lua5.1 tests/weave_bar_state.lua" lua5.1 tests/weave_bar_state.lua`
  to `tests/run.sh` (toc_check counts the registry against disk; three other lanes' new
  suites are also still unregistered).
- Appearance-options lane: replace the `weave_range_enabled` `desc` (exact text in bench
  §6 — it still promises a LibRangeCheck band fallback that HU-23 removed).
- `main.lua` owner: the comment at :985-990 still says the bar is "off by default".
- Operator in-client: (1) at range, auto-shooting, the mainhand bar must not sweep with
  the Auto Shot cycle and must not move toward the ranged bar; (2) melee swings still
  drive it; (3) the distance bar's placement/labels at the operator's UI scale.
  `/st diag` `swing_mainhand` STARTs are the receipt.

## second pass — 2026-10-25 (wave follow-up lead on the cast reset)

Lead: "Auto Shot 75 is in `noreset_swing_spells` (:1030) so it is exempt; Steady/Multi/
Aimed are not, so each shot restarts the melee bars."

**Verdict: mechanism CONFIRMED, exemption REFUTED, fix already shipped.**

- Static: no `[75]` in any `noreset_swing_spells` band (996-1044, 1115-1167, 1380-1448,
  1525-1560, 1629-1668, 1703-1713). Every `[75] = true` line is inside a `ranged_swing`
  table - the table that STARTS the ranged swing. The cited `:1030` was `ranged_swing[75]`.
- Dynamic, real lib, all three branches (Era 2/0, Anniversary 5/1, Titanforge 11/2):
  Auto Shot 75 sets `casting=true`, `preventSwingReset=false`, and SUCCEEDED fires
  `START:mainhand, START:offhand, START:ranged` on EVERY branch. Steady 34120 is exempt
  on Anniversary and Titanforge (Era has no Steady). Multi/Aimed/Arcane are exempt on all
  three as of the lib lane's same-day change (before it, Aimed leaked on Era and BCC).
- `st.family` does not choose the lib branch: the lib reads `WOW_PROJECT_ID` +
  `LE_EXPANSION_LEVEL_CURRENT` at load (`lib:44-54`); `st.family` is compat's parallel
  label (`compat.lua:38-99`).
- Fix options: lib `noreset[75]` REJECTED (kills the in-melee reset the reference keeps);
  main.lua snapshot/restore REJECTED (cast-reset START payload is identical to a real
  swing START). The shipped class guard is the minimal in-scope fix; no code change from
  this pass.
- Filed: `bench/bars_range_hunter_2026-10-25.md` §4.4 (truth table + option table) and
  §10 (open question). Hands-up signal emitted for the one operator design question:
  should an Auto Shot cast AT MELEE RANGE delay the melee swing (shipped: yes, reference
  rule) or never reset melee (one-line change)?

## current state (final, after the second pass)

- DONE. Focused suites green (weave_range_state 83/0, weave_bar_state 96/0,
  hunter_state 1824/0, hunter_guide 1976/0, hunter_window 213/0, bars_state 956/0,
  real_wire 978/0 + 2 expected-fail, smoke 232/0); luacheck 0/0 on every touched file;
  mutations M1-M7 kill.
- Signals: done (20261025T173500Z), hands-up (20261025T181500Z).
- Bench: `bench/bars_range_hunter_2026-10-25.md` (new, never overwritten).

## next step

- Orchestrator: `tests/run.sh` line for `tests/weave_bar_state.lua`; the options `desc`
  replacement (§6); the `main.lua:985-990` stale comment.
- Operator: the in-melee Auto Shot ruling (hands-up), plus the in-client receipts in
  bench §11.

## third pass — 2026-10-25 (cross-lane enable contract from appearance-options)

`weave_range.lua`'s nil gate now DELEGATES to `ST.weave_range_default_enabled(
ST.player_class)` (config_presets.lua:1599-1604), the same reader the options getter
(option_tables.lua:195-224) falls back to. No class token is hardcoded in the enable
rule any more: a helper that says off turns a hunter's nil off.

- `wr.class_default_on(ST)` (`weave_range.lua:108-115`) is the only place the default is
  read; `wr.enabled_for(class_db, profile_db, default_on)` (`:117-136`) stays pure and
  takes the resolved boolean. Explicit saved true/false still wins both ways.
- Tests: `tests/weave_range_state.lua` 90/0 (6 new `class_default_on` pins, the
  `enabled_for` block re-cut to the boolean signature); `tests/weave_bar_state.lua`
  105/0 (ST stub now carries the real dot-style helper; 5 new delegation pins incl.
  explicit-beats-default both ways, and no distance read when the default says off).
- Mutations: M8 (hardcode `player_class == "HUNTER"`) kills 5 pins; M9 (never consult
  the helper) kills 6+. Both on a `/tmp/opencode/mut2` copy, deleted.
- Still true and NOT part of this contract: `far_yards_for` keeps the 35 yd HUNTER band
  (the operator's own band spec), and the whole module still contains no LibRangeCheck
  read.
