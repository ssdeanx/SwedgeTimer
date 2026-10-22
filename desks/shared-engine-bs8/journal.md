# shared-engine-bs8 — Journal

## 2026-10-20 — Desk opened
- **Purpose:** One shared-engine lane carrying three things that all touch the engine
  files: (1) the **HU-8 hold verdict** (operator ruling, hands-up HU-8: a hold is a
  DECISION, unknown is not) in the pure engine + the practice UI; (2) **BS-8 item 1**
  — the paladin's `LCD.Register` degrade counter read on `main.lua`'s runtime-diag
  line; (3) **BS-8 item 2** — the live pull clock `main.lua` publishes for the
  prepull rule (`nextaction.lua` `PREPULL_SEAL_LEAD_SECONDS` / `out.prepull_ready`);
  plus (4) the **drill-key routing fix** filed by the superseded-wrappers lane
  (`bench/superseded_wrappers_2026-10-19.md` §6 item 1) — the panel map's `mode`
  must name the drill the class's session actually runs.
- **Scope (fixed by the orchestrator):** `practice.lua`, `practice_ui.lua`, `main.lua`,
  `diag.lua`, `practice_stats.lua`, `practice_progress.lua`, `tests/practice_state.lua`,
  `tests/practice_ui_state.lua`, `tests/main_init_state.lua`, `tests/diag_state.lua`.
  OUT: every `classes/*.lua` and every guide file (the class-side hold statements are
  a separate lane), `option_tables.lua`, `config_presets.lua`, `compat.lua`, `hud.lua`,
  `bars.lua`, `nextaction.lua`, `nextaction_ui.lua`, `run.sh`, TOCs, versions,
  README/CHANGELOG/docs, git, lint-config.
- **Sources read first:** `bench/filed_closure_sweep_2026-10-19.md` §7 BS-8 (§4.6 P-17,
  §2 JE-1), `hands-up.md` HU-8 (resolved: HOLD-IS-A-DECISION),
  `bench/superseded_wrappers_2026-10-19.md` §6, `bench/class_features_drills_2026-10-19.md`
  §2 (P-17, D-P2), `bench/rogue_drills_rotation_2026-10-19.md` §5.7 (the POOL verdict
  that motivates the hold), `bench/buildout_paladin_bs5_2026-10-19.md` §5 (the class-side
  counter).
- **Next step:** read the in-scope files, implement the engine hold + the UI, publish
  the diag counter and the live pull clock, fix the three drill-map lines, then the
  pins + mutation proofs on `/tmp/opencode` copies.

## 2026-10-20 — The hold verdict, the diag counter, the pull clock, the drill routing
- **Worked on:** (1) **HU-8** — the class contract grew the explicit hold statement
  (`{ action = nil, hold = true, reason = "..." }`); `H.practice_scenario_step` accepts
  it (it used to drop a nil action and answer "unknown"); the PURE engine grades it:
  `H.rotation_run_decide(run, expected, actual, hold)` returns `hold_ok` (nothing cast
  → correct, **no attempt, no points** — the grade map's ABSENCE of a `hold_ok` entry
  is the rule) or `illegal_cast` (any cast → **F**, a mis-pick that breaks the streak
  and the band). A nil step with no hold statement stays **unknown** — unchanged. The
  UI shows the hold in the prompt with the class's reason, grades a press during it as
  ILLEGAL CAST (miss colour, the reason in the status line) and a correct hold as HOLD
  OK (no attempt). (2) **JE-1** — `main.lua`'s runtime-diag line reads
  `ST.PALADIN.lcd_register_errors` (`paladin_lcd_register_errors=N`, the class table
  lives on the addon object, so the read is `self.PALADIN`). (3) **P-17** — `main.lua`
  publishes the live pull clock (`ST.pull_at` + `set_pull_at` / `set_pull_in` /
  `pull_in_seconds`; one timestamp, no per-frame scan). The source: the fight's own
  pull (combat enter stamps it, combat exit clears it) and the pre-pull (the player's
  TARGET casting out of combat → the pull is the cast's END, the client-sourced "boss
  is casting, pull now" cue), guarded to group + instance so an open-world mob can
  never arm it. The practice ctx carries the same moment (`ctx.pull_at`,
  `ctx.pull_in_seconds`), and a ctx that already has one keeps it. (4) The drill-key
  routing fix: three one-line changes to `PRACTICE_DRILL_KEYS` (druid →
  `druid_powershift_rework`, shaman → `shaman_mw_weave`, warrior →
  `warrior_execute_burn`) so the mastery row, the session and the panel's offered drill
  are ONE drill.
- **Also found and recorded:** the shipped clients have **no pull-timer API** (checked
  all five client branches: no `pulltimer` / `GetPullTime` / `SetPullTimer`) — which is
  why the clock is the addon's own. The class-side hold statements (the rogue's POOL
  verdict, the shaman's guide hold) and the class-side pull read are FILED for the
  class lanes; the engine is ready for them.
- **Current state:** harness **41 steps / 0 failed**; luacheck **2 warnings / 0
  errors** (the shipped floor; this lane adds none). The suites it owns:
  `practice_state` 1478, `practice_ui_state` 1355, `main_init_state` 788 — all green.
  Mutations **11 of 11 killed** on `/tmp/opencode/bs8-mut` (script
  `/tmp/opencode/bs8_mutations.py`), including the two the brief names: "the hold is
  treated as unknown" and "an illegal cast is not punished". CRLF kept on the three
  addon files, LF on the three test files; no trailing whitespace on a touched line.
  Artifact: `bench/shared_engine_bs8_2026-10-20.md`.
- **Next step:** the orchestrator validates in-tree. Two filed items need a class lane
  (the hold statements, the pull-clock provider read) and one needs the operator's
  in-client session (the pre-pull projection's behaviour).

## 2026-10-20 — [signal:done] crossfire seen and cleared
- **Worked on:** a mid-lane harness run showed 2 reds in `tests/hud_state.lua` /
  `tests/warrior_guide_state.lua` (the warrior's TBC HUD row grew a sunder mirror:
  9 slots where the pins wanted 8) and then 1 red in `tests/warrior_state.lua` (the
  warrior's own drill list grew a fifth drill, `warrior_hs_queue`). **Not this lane's
  work and not this lane's files** — a concurrent warrior lane was landing the W-21
  HUD mirror + a new drill, and its own pin updates followed.
- **Current state:** the tree is back to **41 steps / 0 failed** with the luacheck
  floor (2 warnings / 0 errors) once that lane's pins landed. This lane's own
  suites never went red (`practice_state` 1478, `practice_ui_state` 1355,
  `main_init_state` 788, `diag_state` 260 — all green throughout).
- **Next step:** the orchestrator validates; the reconcile wave owns the warrior
  lane's pins if they are still moving.
