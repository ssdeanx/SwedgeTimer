# Brief: rogue-practice-polish (Round 2 HELD — dispatch AFTER skeleton + pure reconcile, 2026-10-19)

## Objective
Slice D: practice drills + target polish + discoverability. Writer lane, file-disjoint from the parallel cues-provider lane. HELD until Round 1 reconciles.

## Scope (ONLY these files)
- `practice.lua`: two `class = "ROGUE"` scenarios via `H.register_scenario` (`:1509-1543`): (1) energy-pooling drill — cast-start fraction vs tick marker, grade bands reuse `H.WEAVE_MARGIN_BANDS` (`:2404-2410`); (2) Era SS-timing drill — post-MH 0.1–0.2 s window (`bench/rogue_deep_2026-10-19.md` §2.1). Nil markers unscored for free (`practice.lua:2436-2438`).
- `tests/practice_state.lua`: scenario grade-band pins (S/A/B/C/D + F-clip mirror) for both drills.
- `option_tables.lua` (ROGUE section ONLY — created Round 1): discoverability copy for hide-on-unknown states (`weave_range`-style expectation-setting), no toggle-behavior changes.
- `diag.lua`: CLOSED — do not touch unless the orchestrator explicitly opens it at dispatch. Session state + visible affordances already ship (M3 counter, lust-unknown latch).
- Explicitly OUT: `classes/rogue.lua`, `rogue_guide.lua`, `tests/rogue_state.lua`, `tests/rogue_guide_state.lua`, `tests/guide_contract.lua` (parallel cues lane owns all of these); TOCs, version, CHANGELOG.

## Standing rules
No git. No lint-config. Touched-lines whitespace. Endings preserved. Harness green + floor + mutation proofs (guard-stripped `/tmp/opencode` copies fail the new pins).

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write)
bench-read (journal, readiness §5-D, rogue_deep §2.1, practice.lua registry patterns, lessons); desk-open `desks/rogue-practice/`; journal + `done` signal.

## Validation owner
Orchestrator: drills grade correctly incl. nil-tick unscored, copy accurate, harness + mutations green, disjoint vs cues lane.
