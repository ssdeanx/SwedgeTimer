# Brief: version-bump (2026-10-19)

## Objective
Bump version 2.1.0 → 2.1.1 across all 7 TOCs + main.lua. No behavior changes. Test-baseline bump ahead of owner in-client test session.

## Scope (disjoint writer)
- ONLY these files:
  - `SwedgeTimer.toc` (line 5: `## Version: "2.1.0"`)
  - `SwedgeTimer_Vanilla.toc`
  - `SwedgeTimer_TBC.toc`
  - `SwedgeTimer_Wrath.toc`
  - `SwedgeTimer_Cata.toc`
  - `SwedgeTimer_Mists.toc`
  - `SwedgeTimer_Mainline.toc`
  - `main.lua` (line 5: `local version = "2.1.0"`)
- Change: `"2.1.0"` → `"2.1.1"` in the version field only. Do NOT touch `## Interface` lines, load orders, or the commented `-- local version = "2.0"` line in main.lua.
- Do NOT touch CHANGELOG.md (stays [Unreleased] until post-test publish per desks/journal.md Status), README, TESTING, classes/, or any other file.

## Boundary
- No other lane writes these 8 files this round. If you observe any other file needing a change, log it to the bench — do not side-quest.
- No git commands. No lint-config changes. Preserve CRLF/LF endings per file (check before edit).

## Workshop mechanics (mandatory)
1. `bench-read`: list `bench/`, read `desks/journal.md` current Status + Lanes, read `bench/lessons.md`. No re-searching answered questions.
2. `desk-open`: ensure `desks/version-bump/` exists with `journal.md` + `.signals/`; if exists, resume (do not overwrite).
3. `desk-journal`: append entry (worked on / current state / next step) at end.
4. `signal-write`: emit `done` JSON to `desks/version-bump/.signals/<timestamp>.json` + journal marker.

## Validation owner
- Orchestrator + offline harness. You must run: `bash tests/run.sh` in-tree (read-only verify, no mutation needed for this lane) and `grep -rn '2\.1\.0' --include='*.toc' --include='main.lua' .` to prove zero leftovers (excluding docs/history records). Report both outputs.
- List every file changed.

## Done means
- All 7 TOCs + main.lua read 2.1.1, harness still green, bench note written, signal emitted.
