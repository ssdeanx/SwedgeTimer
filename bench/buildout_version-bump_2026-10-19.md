# Buildout: version-bump — 2.1.0 → 2.1.1
Date: 2026-10-19. Desk: version-bump. Brief: `bench/briefs/brief_version-bump_2026-10-19.md`.
Status: **done, metadata only** (zero behavior change, no git, no lint-config changes).

## 1. Version bump (8 fields, line 5 each)
| File | Line | Before → After |
|---|---|---|
| SwedgeTimer.toc | 5 (`## Version`) | 2.1.0 → 2.1.1 |
| SwedgeTimer_Vanilla.toc | 5 | 2.1.0 → 2.1.1 |
| SwedgeTimer_TBC.toc | 5 | 2.1.0 → 2.1.1 |
| SwedgeTimer_Wrath.toc | 5 | 2.1.0 → 2.1.1 |
| SwedgeTimer_Cata.toc | 5 | 2.1.0 → 2.1.1 |
| SwedgeTimer_Mists.toc | 5 | 2.1.0 → 2.1.1 |
| SwedgeTimer_Mainline.toc | 5 | 2.1.0 → 2.1.1 |
| main.lua | 5 (`local version`) | 2.1.0 → 2.1.1 (line-6 `-- local version = "2.0"` untouched) |

`## Interface` lines, load orders, CHANGELOG.md, README, TESTING, classes/ untouched.

## 2. Leftover grep proof
`grep -rn '2\.1\.0' --include='*.toc' --include='main.lua' .`
→ zero matches (exit 1). No live 2.1.0 version claims remain.

## 3. Line endings (preserved)
All 8 changed files report `ASCII text, with CRLF line terminators` before and after
(`file` check). No LF churn.

## 4. Harness (read-only verification, in-tree)
`bash tests/run.sh` → **35 steps, 0 failed**; luacheck **2 warnings / 0 errors** (71 files).
Exit 0. Same standing floor as `desks/journal.md` Status (2 KEEP-ruled warnings).

## 5. Collision check
Other 2026-10-19 briefs (feature-proctor, feature-hunter, rogue-research) are
read-only and do not write these 8 files. No collision observed; scope held.

## 6. Files changed (complete list)
SwedgeTimer.toc, SwedgeTimer_Vanilla.toc, SwedgeTimer_TBC.toc,
SwedgeTimer_Wrath.toc, SwedgeTimer_Cata.toc, SwedgeTimer_Mists.toc,
SwedgeTimer_Mainline.toc, main.lua.

## 7. Next step
Orchestrator reconcile: confirm 2.1.1 in all 8 fields, harness green, no leftover
2.1.0. CHANGELOG stays `[Unreleased]` until post-test publish (per journal Status).
