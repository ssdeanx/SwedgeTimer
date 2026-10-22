# practice-scenario-engine — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build the SHARED rotation-SCENARIO engine + the drill-registry plumbing
  that six per-class lanes (disjoint files) plug into. Spec:
  `bench/class_features_drills_2026-10-19.md` §1, §2(D), §3, §4.
- **Scope (fixed by the orchestrator):** `practice.lua`, `practice_ui.lua`,
  `practice_progress.lua`, `option_tables.lua`, `tests/practice_state.lua`,
  `tests/practice_ui_state.lua`, `tests/practice_progress_state.lua`,
  `tests/options_load_state.lua`. NOTHING else — no `classes/*.lua`, no
  `config_presets.lua`, no `config.lua` / `main.lua` / `diag.lua` / `compat.lua` /
  `hud.lua` / `bars.lua` / `run.sh` / TOCs / versions / docs, no git, no
  lint-config changes.
- **Operator taxonomy (fixed):** SCENARIO = run the class's actual wowsims rotation
  end-to-end and grade the cast sequence. DRILL = a focused single-skill trainer.
  Today every registry entry is a drill; no class has a scenario.
- **Contract (fixed — the six class lanes code against exactly this):**
  - `ST.<CLASS>.practice_scenario_step(self, ctx) -> { action = "<spell key>",
    reason = "<text>" } | nil`; `ctx = { now, last_action, resources, cooldowns }`;
    `nil` = cannot decide → the engine grades "unknown", never a wrong action.
  - `ST.<CLASS>.practice_drills = { { key = "<registry key>", label = "<label>",
    grade = function(self, ctx) -> "S"|"A"|"B"|"C"|"D"|"F"|nil end }, ... }`;
    `nil` = not judgeable → the engine shows "unknown".
- **Sources read:** `bench/class_features_drills_2026-10-19.md` (§1 taxonomy, §2(D)
  scenario specs, §3 parity, §4 shared build-lane requirements, §5 UNCONFIRMED
  ledger); `desks/class-drills-spec/journal.md`; `bench/lessons.md`;
  `CAIRN.md`; `workshop.md`; `hands-up.md`; `desks/journal.md` (lane table).
- **Next step:** read the tree files in scope, then implement the engine + registry
  and prove it with the offline harness + mutation proofs on /tmp/opencode copies.

## 2026-10-19 — Engine landed (the first cut)
- **Worked on:** the pure half in `practice.lua` (the rotation run state machine, the
  grade bands, the contract accessors) and the session half in `practice_ui.lua`
  (the scenario session, the generic drill routing, the practice row, the mode
  select) + `option_tables.lua` (the Practice page select) + `practice_progress.lua`
  (the unlock registry's requirement copy + `unlock_scenario`).
- **Current state:** the four suites this lane owns are green; luacheck adds no
  warning. The registry keeps the eight shipped built-ins (backward compatibility).
- **Next step:** the operator's corrections (the panel map, the registry
  reconciliation, the class-module lookup) land next.

## 2026-10-19 — Operator correction 1: the panel map (the warrior)
- **Worked on:** `PRACTICE_DRILL_KEYS.WARRIOR` = the warrior's own drill
  (`warrior_core_order`), never the shared twist key; the live scope resolves per
  drill; a class with its own drills never falls back to the twist session; the
  panel builds no twist-sim widgets for such a class.
- **Current state:** the warrior's session is its own drill list; the paladin, the
  hunter and the rogue keep their shipped sessions.
- **Next step:** the registry reconciliation (the operator's next message).

## 2026-10-19 — Operator correction 2: the registry reconciliation (one skill, one truth)
- **Worked on:** the druid lane's `druid_powershift_rework` (the sim's trigger) vs
  the built-in `druid_powershift` (the addon's 20-energy rule) — the same drill, two
  truths. First attempt retired three built-ins outright; that reddened three CLASS
  suites (`druid_state`, `warrior_state`, `shaman_state` — 24 pins + 2 crashes).
- **Correction applied (the operator's instruction):** keep BACKWARD COMPATIBILITY —
  all eight built-ins stay registered (the class wrappers and their pins still
  resolve the old keys). What changed: `H.SUPERSEDED_DRILLS` names the class drill
  that owns each superseded skill, the engine routes the class to its own drill list
  when its list supersedes the built-in drill, and the built-in's grading is
  DELEGATED to the class's drill (`H.delegate_drill_grade`) so the old truth never
  grades a player attempt.
- **Pins broken by the reconciliation: NONE.** `druid_state` 903, `warrior_state`
  1148, `shaman_state` 640, `hunter_state` 1046, `rogue_state` 757 — all pass
  unchanged.
- **Current state:** the harness is green except `tests/hunter_guide_state.lua`
  (the hunter lane's own in-flight file: `ST.HUNTER.practice_family` does not exist
  yet there — not this lane's file, not this lane's change).
- **Next step:** the class-module lookup correction (HU-7), then the bench file, the
  signal and the final report.

## 2026-10-19 — Operator correction 3: the class-module lookup (HU-7)
- **Worked on:** the pure half resolved the class module from the NAMESPACE table
  (`st[class_key]`), but the class tables live on the ACEADDON table
  (`ST.PALADIN`, `ST.WARRIOR`, …) — the shaman lane found it (HU-7) and added a
  class-side alias as a stopgap. Fixed centrally: the class key now resolves from
  the AceAddon table FIRST (a guarded `LibStub("AceAddon-3.0"):GetAddon`), the
  namespace only as the fallback, and the lookup is nil-safe per class (an unknown
  class answers nil; the session refuses loudly).
- **Current state:** the engine finds a class module WITHOUT any per-class alias —
  the shaman lane's `st.SHAMAN = ST.SHAMAN` stopgap is not needed by the engine.
- **Next step:** bench file, signal, final report.

## 2026-10-19 — [signal:done] the shared scenario + drill engine landed
- **Worked on:** the shared rotation-SCENARIO engine (pure state machine + bands in
  `practice.lua`), the scenario session and the generic drill routing
  (`practice_ui.lua`), the Practice page's mode select (`option_tables.lua`), the
  unlock registry's copy rule (`practice_progress.lua`) and the four suites.
- **Evidence:** `bash tests/run.sh` → 41 steps, 1 failed (the hunter lane's own
  in-flight suite); luacheck 2 warnings (the shipped floor, none from this lane);
  43/44 mutations killed on `/tmp/opencode` copies (the survivor is an equivalent
  mutant: the inherited-key safety net is unreachable while every class's map entry
  names its own drill).
- **Artifact:** `bench/practice_scenario_engine_2026-10-19.md`.
- **Current state:** the four suites this lane owns are green
  (`practice_state` 1443, `practice_ui_state` 1306, `practice_progress_state` 431,
  `options_load_state` 3280). The class lanes' suites are green too.
- **Next step:** the orchestrator validates and dispatches the class lanes against
  the contract (the desk journal + the bench file carry the contract details).
