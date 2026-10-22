# Gamification Visibility — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Phase 4 of `bench/final_completion_plan_2026-10-19.md` — turn the
  practice gamification's visible surface ON by default: the practice panel's level
  badge + session XP bar and the level-up / achievement chat notices.
- **Scope (this session):** `config_presets.lua` (the default) and
  `tests/options_load_state.lua` (the pins). The default is the ONLY production
  change: the visible surface already exists and already rides one db key.
- **Gate:** the operator's explicit request for visible practice levels/XP
  ("start at lvl 1, gain xp each practice, level up") is the gate for this
  default-visible change; it is recorded in the code as the gate.
- **Read-only inputs:** `practice_ui.lua` (a sibling lane owns it), `config.lua`,
  `option_tables.lua`, `practice_progress.lua`, `practice_stats.lua`.
- **Out of scope:** `practice_ui.lua`, `practice.lua`, `practice_progress.lua`,
  `practice_stats.lua`, `option_tables.lua`, class files, `main.lua`, `diag.lua`,
  `compat.lua`, `hud.lua`, `bars.lua`, `tests/run.sh`, TOCs, versions, README,
  CHANGELOG, docs, git, lint config.
- **Next step:** read the badge read path in `practice_ui.lua` (the `== true`
  read and the notice gate), then add the default + the pins.

## 2026-10-19 — The default landed + the pins are in
- **Worked on:** `config_presets.lua` — `ST.class_defaults.practice_panel_badge = true`
  with the operator order named as the gate in the comment above it (the shared class
  defaults are the AceDB default for EVERY class table, so the key reaches a fresh
  profile of all ten class tokens; a saved `false` still wins, and an old profile with
  no key still reads off because `practice_ui.lua` compares `== true`).
  `tests/options_load_state.lua` — NEW section 24 (129 checks). The pins are
  BEHAVIOURAL: a mini sandbox loads the real `practice_stats.lua` +
  `practice_progress.lua` + `practice_ui.lua` and drives the real session path
  (begin → attempts → end), so the notice gate is exercised end to end. Four groups:
  (a) the default is true, is the only default the key carries, and the operator order
  is named as the gate in the code + `config.lua`'s `'**'` inheritance is intact;
  (b) for all ten class tokens: fresh → on, saved false → off, no class table
  overrides the shared default; (c) the badge's read/write entry points exist and the
  toggle ROUND-TRIPS (write → class table → read, both ways), the badge frame carries
  its four readouts, and the module rides exactly ONE db key; (d) the notices: no key
  → silent, `false` → silent, fresh → the level-up notice fires, an `S` → the
  achievement notice fires, `false` → the achievement notice does not fire.
- **Current state:** `tests/options_load_state.lua` **3380 checks, 0 failed** ·
  full harness **41 steps, 0 failed** · luacheck **2 warnings / 0 errors** in 83 files
  (the floor; `luacheck config_presets.lua tests/options_load_state.lua` → 0 warnings)
  · **mutation proofs 5/5 killed** on `/tmp/opencode/gamvis-mut` (script
  `/tmp/opencode/gamification_visibility_mutations.py`): M1 "default removed" (16 pins
  die), M2 "default false" (16), M3 "notice ignores the toggle" (3), M4 "nil-safe read
  broken" (1), M5 "the toggle write is dead" (2). Bench artifact:
  `bench/buildout_gamification_visibility_2026-10-19.md`.
- **Dead end worth remembering:** a source-text pin on `practice_ui.lua`'s `announce`
  was the first plan; it was dropped for the mini sandbox, because a sibling lane owns
  that file and a textual pin would crossfire on any refactor of it. The behavioural
  route also has teeth on the same mutant (M3 kills it).
- **Next step:** orchestrator validation (owns Done).

## 2026-10-19 — [signal:hands-up] HU-9: the badge is visible by default and there is NO in-game way to turn it off
- The key `practice_panel_badge` has no options widget anywhere (`grep` in
  `option_tables.lua` / `option_table_presets.lua` → 0 hits). The Progress page
  (step 3) is read-only by design (`option_tables.lua:657-669`), although the hook lane
  had filed the widget as the Progress page's job. With the default now ON the player
  can only turn it off through the SavedVariables file.
- `option_tables.lua` was out of this lane's scope → nothing was added. Filed as
  HU-9 for the operator: land the toggle widget on the Progress page, or ship the
  badge as unconditional-on.
- Also filed (cosmetic, no action taken): `tests/practice_ui_state.lua:3632`'s label
  still reads "the badge is hidden by default" — the PIN is still correct (that
  fixture's class table has no key, so it pins the nil-safe read), only the wording is
  stale. That file is out of this lane's scope.

## 2026-10-19 — [signal:done] Gamification visibility ON for a fresh profile, 5/5 mutations killed
- The level badge, the session XP bar and the level-up / achievement notices ship ON
  for a fresh profile (operator order 2026-10-19 = the gate, recorded in the code).
  The notices ride the same key, the toggle still round-trips, and a profile that
  turned it off keeps it off. 41/0 harness, the luacheck floor held, 5/5 mutants
  killed. HU-9 (no in-game off-switch) is with the operator.
