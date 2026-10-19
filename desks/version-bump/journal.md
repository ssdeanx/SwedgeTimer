# version-bump — Journal

## 2026-10-19 — Desk opened
- **Purpose:** version-field writer lane for SwedgeTimer release/test baselines.
- **Scope:** the `## Version` field in the 7 flavor TOCs + `local version` in `main.lua`. No behavior, docs, or CHANGELOG edits.
- **Next step:** execute the current dispatch brief (`bench/briefs/brief_version-bump_2026-10-19.md`), then hand to orchestrator for reconcile.

## 2026-10-19 — version 2.1.0 → 2.1.1 (8 fields)
- **Worked on:** bumped line 5 of all 7 TOCs (`## Version: "2.1.0"` → `"2.1.1"`) and `main.lua:5` (`local version = "2.1.0"` → `"2.1.1"`); line-6 comment untouched. CRLF preserved in all 8 files (`file` check before/after). Collision check: other 2026-10-19 briefs are read-only on disjoint files — no overlap.
- **Current state:** all 8 fields read 2.1.1; `grep -rn '2\.1\.0' --include='*.toc' --include='main.lua' .` → zero hits (exit 1). `bash tests/run.sh` → 35 steps, 0 failed; luacheck 2 warnings / 0 errors. Bench note: `bench/buildout_version-bump_2026-10-19.md`.
- **Next step:** orchestrator reconcile + grep proof; owner in-client test session unchanged. CHANGELOG stays `[Unreleased]` until post-test publish.

## 2026-10-19 — [signal:done] version-bump complete
- 8 fields at 2.1.1, harness green (35/0, luacheck 2/0), zero live 2.1.0 leftovers; signal JSON in `.signals/`.
