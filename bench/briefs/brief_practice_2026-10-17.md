# Brief: practice — build-out round 1
Date: 2026-10-17. Orchestrator-issued, round plan approved in desks/journal.md.

## Read first (all verified on disk)
desks/practice/journal.md · desks/journal.md · bench/verify_bank.md (C1 row + P5/H5/W6/D7/S7 rows — BINDING) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
practice.lua, practice_ui.lua, tests/practice_state.lua, tests/practice_ui_state.lua. NOTHING else — do not touch class files, guide engines, or scoring grades.

## Task
- **C1 harness split** (architectural, verify §6.2 — we'd be first to ship a generalized sim harness): extract the generic sim/timing harness (scenario lifecycle, move windows, timing queries, scoring pipeline) out of the paladin-only core into a reusable engine within practice.lua; paladin becomes the first consumer. Existing practice behavior (S–F grades, session score, persistent bests) must NOT change — that's the regression bar.
- **P5 AW combo drills** (novel standard): paladin scenario additions for Awakening/Avenger Wrath-style combo windows, offline sim first.
- **Scenario shells for the other four trainers**, offline-testable primitives only (not full class sims this round): **H5 movement trainer** (forced-move windows), **W6 execute-phase trainer**, **D7 powershift-loop trainer** (20-energy rule from bank; D1 probe stays blocked so D7 renders its sim honestly independent of in-client talents), **S7 weave-timing trainer** (uses weave.lua math).
- **`ui.design_targets`**: expose practice UI elements as design-mode targets (consumed by C6 on the bars-design lane).

## Cross-client rules
No default-visible behavior change (scoring, UI layout). New toggles nil-safe, defaults documented. Minimal in-place edits, preserve formatting/line endings, no `_` renames, no unused-variable work.

## Validation
bash tests/run.sh — all green. luacheck 0 errors. Mutation proof on /tmp/opencode/mut_practice/ (break one harness timing rule, show the check fails, restore). Practice stays paladin-playable as today; other classes through the shells only.

## Deliverables
Code · desks/practice/journal.md entry · signal JSON · bench/buildout_practice_2026-10-17.md (harness API surface, scenario list, evidence, option defaults, UNCONFIRMED items). Final reply ≤6 lines. NEVER run git.
