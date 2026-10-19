# Brief: practice-grade — practice enterprise review
Date: 2026-10-17. Orchestrator-issued. Owner bar: enterprise grade, ready for in-game testing.

## Read first (all verified on disk)
desks/practice/journal.md · desks/journal.md · bench/buildout_practice_2026-10-17.md (harness API, scenario list — the regression bar) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
practice.lua, practice_ui.lua, tests/practice_state.lua, tests/practice_ui_state.lua. NOTHING else. luacheck reports ZERO warnings in this scope — the job is completeness, not wiring.

## Task — every path wired end-to-end
- S–F grade path, session score, persistent bests: full save/load round-trip verified by checks (bests survive reload semantics as the code models them).
- All 5 scenario shells (`paladin_aw_combo`, `hunter_forced_move`, `warrior_execute`, `druid_powershift`, `shaman_weave`) dispatch correctly with no dead stubs; every button/command/option in the practice UI does something observable; every displayed value updates from live sim state (no frozen placeholders).
- `ui.design_targets` descriptors pass the real design.lua normaliser (already pinned — keep green).
- Hunt for half-wiring: callbacks registered but never fired, fields written but never read, branches that can't trigger. Fix in scope; anything out of scope goes in the report, not in your files.

## Rules
No git, no lint-config, endings preserved. Wire-not-strip applies to anything you find (no `_` silencing). Regression bar intact: S–F grades, session score, persistent bests behavior unchanged. Other lanes parallel (bars_state/hud_state count fails expected — do NOT touch).

## Validation
bash tests/run.sh (practice suites green; only known count pins fail). luacheck 0 errors, still 0 warnings in scope. Mutation proofs on /tmp/opencode copy for behavior changes.

## Deliverables
Code · desks/practice/journal.md entry · signal JSON · bench/buildout_practice-grade_2026-10-17.md (gap list → fix/verify each; UNCONFIRMED in-client items). Final reply ≤6 lines. NEVER run git.
