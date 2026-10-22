# Final Gate Tests — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the final test-sufficiency audit's four gaps (Gap 1 the harness
  registry's own guard, Gap 2 the CHANGELOG's false claim, Gap 3 the unpinned
  guide-vocabulary leg, Gap 4 the unpinned zero-neutral guard).
- **Scope:** `tests/practice_ui_state.lua`, `tests/toc_check.lua`, `CHANGELOG.md` -
  nothing else (no addon file, no other test file, no run.sh, no TOCs, no git).
- **Next step:** the orchestrator validates; the desk is done unless the audit's
  owner wants the pins widened.

## 2026-10-20 — The four gaps closed (landed, harness green)
- **Worked on:** (1) §27b in `tests/practice_ui_state.lua` pins the scenario strip's
  GUIDE leg for all six classes - the class's own guide key (a key its rotation does
  not rank), the common ability with the CLIENT'S OWN resolved id, and the negative
  half (a client that knows none of the common spells offers none of them). (2)
  `CHANGELOG.md:780,788-789` now says what the tree ships: six of six publish a
  neutral set, the hunter and the druid family-scoped (no `raptor` / no `rake` on
  WotLK and Forever), no Cata/Mists/Retail bucket for the four family-scoped
  classes, cited to `bench/class_neutral_family_coverage_2026-10-20.md` §1.2/§5.
  (3) `tests/toc_check.lua` gained the harness registry self-check (both
  directions + the count), inside an already-registered step. (4) §22n now finishes
  the run and asserts the run summary and the panel readout name NO neutral for a
  class with no published set.
- **Current state:** harness **43 steps / 0 failed**; luacheck **2 warnings / 0
  errors in 85 files** (the standing floor); `practice_ui_state.lua` 1760 checks
  (was 1697), `toc_check.lua` 871 checks (was 865). Every mutant was proved on a
  `/tmp/opencode/mut_*` copy - the repo tree was never mutated (`diff -rq` against
  the pre-edit copy shows exactly the three in-scope files). Evidence:
  `bench/final_gate_tests_2026-10-20.md`.
- **Next step:** the orchestrator owns validation. If a family-scoped class changes
  its guide slot set or its neutral bucket, update §27's table
  (`PRACTICE_CLASS_SPECS`: `family_id`, `guide_key`, `common`, `client_id`) - it is
  the one place, exactly like the other rotation pins in the tree.

## 2026-10-20 — [signal:done] Four gaps closed, harness green
- `desks/final-gate-tests/.signals/2026-10-20T205634Z.json`; evidence on the bench:
  `bench/final_gate_tests_2026-10-20.md`.

