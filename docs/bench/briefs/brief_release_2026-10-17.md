# Brief: release — version bump 2.1.0 + pre-publish accuracy pass
Date: 2026-10-17. Orchestrator-issued. Owner: test session next, then publish.

## Read first (all verified on disk)
desks/release/journal.md · desks/journal.md · bench/buildout_changelog_2026-10-17.md (what the docs now claim) · bench/oracle_audit_2026-10-17.md (verdict + checklist) · CHANGELOG.md · README.md · TESTING.md · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
All 7 toc variants (the `## Version` line ONLY), main.lua (the `local version` field ONLY — line 5; leave the line-6 comment alone), CHANGELOG.md, README.md, TESTING.md. NOTHING else.

## Task
1. **Bump 2.0.8 → 2.1.0** in all 7 tocs + main.lua:5 (feature round, semver minor). Verify with repo-wide grep for `2.0.8`: update genuine version claims; leave CHANGELOG release-history lines + bench/desks historical records (report them as intentional).
2. **CHANGELOG accuracy:** every [Unreleased] claim spot-checked against the tree (features exist? toggles real — all 31 wired? counts sane?). Fix inaccuracies. Keep [Unreleased] as the header — the version header gets cut at publish AFTER owner testing, not now.
3. **README accuracy:** install/load instructions, feature list vs shipped reality, version/client refs (12.1.x done — verify), commands (`/st` verbs incl. diag).
4. **TESTING.md accuracy:** checklist covers oracle §checklist + every lane's in-client items (verify against the bench reports); client versions current (12.1.5 present); no dead steps.
5. **Publish checklist:** all shipped modules in all flavor tocs (re-confirm via toc_check, green expected); grep for debug leftovers (`TODO`/`FIXME`/`XXX`/stray dumps — the wired `print` alias is legitimate, report don't touch); endings preserved (tocs CRLF).

## Rules
Metadata + docs only — zero behavior change. No git, no lint-config. Wire-not-strip N/A (no warnings in scope expected; report if any appear).

## Validation
bash tests/run.sh → 35 steps, 0 failed. luacheck 2 warnings / 0 errors (the standing 2). toc_check green. grep-zero for live 2.0.8 outside history records.

## Deliverables
Metadata + docs · desks/release/journal.md entry · signal JSON · bench/buildout_release_2026-10-17.md (bump table, accuracy fixes, publish checklist with verdict). Final reply ≤6 lines. NEVER run git.
