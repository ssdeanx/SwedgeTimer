# Grader Seam — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the final publish-gate deep audit's HIGH-1 (the scenario
  grader compared RAW press keys while the classification and offer-gate layers
  normalise the class's alias key space, so a correct press graded F).
- **Scope:** `practice_ui.lua`, `practice.lua` (the engine-side class-contract
  helper only), `tests/practice_ui_state.lua`, `tests/neutral_actions_state.lua`.
  No class module, no option/config/TOC/version/docs/CHANGELOG file, no git.
- **Next step:** the orchestrator owns the validation; the desk is done unless the
  audit's owner wants the pin widened.

## 2026-10-20 — HIGH-1 closed (both halves), harness green
- **Worked on:** (1) the panel now offers ONE spelling per spell: the action row
  canonicalises every key through the class's own alias table
  (`ui.canonical_key` -> `H.practice_canonical_key`) and the button's key IS the
  canonical key, so the paladin's Consecration is one button ("cons"), not two
  ("cons" bare text + "consecration" with the icon). The icon lookup
  (`scenario_action_spell_id`) goes through the same alias table, so the ONE
  button carries the spell's icon. (2) the grader's seam normalises the press
  and (defensively) the class's answer before the comparison
  (`scenario_close_step`); the ENGINE stays pure - `H.rotation_run_decide` still
  compares the two strings it is handed and knows nothing of the class's alias
  table. (3) the drill-list path normalises the pick the same way
  (`drill_list_grade` + `drill_list_pick_press`).
- **Current state:** harness **43 steps / 0 failed**; luacheck **2 warnings / 0
  errors in 85 files** (the standing floor); `practice_ui_state.lua` **2455
  checks** (was 1760; +695 from the new §29/§29e), `neutral_actions_state.lua`
  **7023 checks** (was 6224; +799 from the new Retail slice). Three mutants
  proved on `/tmp/opencode` copies (the repo tree was never mutated): M1 no
  panel canonicalisation (6 checks fail), M2 no grader normalisation (114
  checks fail), M3 no drill-list normalisation (5 checks fail). Evidence:
  `bench/grader_seam_2026-10-20.md`.
- **Crossfire absorbed:** the `paladin-scenario` lane landed the audit's
  MEDIUM-2 fix in `classes/paladin.lua` (outside this lane's scope) while the
  mutants were being proved — the paladin's neutral publish became
  family-scoped (Cata / Mists / Retail carry no `sotc`). The closed-list
  suite is THIS lane's file, so the Cata / Mists expectations were re-pinned
  against the tree and a Retail slice was added; the harness is green again.
  If that lane also edits `tests/neutral_actions_state.lua`, the orchestrator
  reconciles the two deltas (both are small and mechanical).
- **Next step:** the orchestrator validates. If a class publishes a NEW alias
  spelling, the class's own alias table is the one place to add it - the panel,
  the grader seam and the closed-list model all read it.

## 2026-10-20 — [signal:done] HIGH-1 closed, harness green
- `desks/grader-seam/.signals/2026-10-20T174500Z.json`; evidence on the bench:
  `bench/grader_seam_2026-10-20.md`.
