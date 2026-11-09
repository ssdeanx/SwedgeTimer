# Buildout: release — version 2.1.0 bump + pre-publish accuracy pass
Date: 2026-10-17. Desk: release. Brief: bench/briefs/brief_release_2026-10-17.md.
Status: **done, metadata + docs only** (zero behavior change, no git).

## 1. Version bump 2.0.8 → 2.1.0 (semver minor: feature round)
| File | Line | Before → After |
|---|---|---|
| SwedgeTimer.toc | 5 (`## Version`) | 2.0.8 → 2.1.0 |
| SwedgeTimer_Vanilla.toc | 5 | 2.0.8 → 2.1.0 |
| SwedgeTimer_TBC.toc | 5 | 2.0.8 → 2.1.0 |
| SwedgeTimer_Wrath.toc | 5 | 2.0.8 → 2.1.0 |
| SwedgeTimer_Cata.toc | 5 | 2.0.8 → 2.1.0 |
| SwedgeTimer_Mists.toc | 5 | 2.0.8 → 2.1.0 |
| SwedgeTimer_Mainline.toc | 5 | 2.0.8 → 2.1.0 |
| main.lua | 5 (`local version`) | 2.0.8 → 2.1.0 (line-6 comment untouched) |
| TESTING.md | 33 (diag example) | version=2.0.8 → 2.1.0 |

Repo-wide `2.0.8` grep after bump: 4 hits, all intentional history records —
CHANGELOG.md:203 (`## [2.0.8] -- 2023-05-09` release history),
bench/briefs/brief_release_2026-10-17.md (brief text ×2), desks/release/journal.md:4
(desk scope line). Zero live version claims remain.

## 2. CHANGELOG [Unreleased] accuracy (spot-checked vs the tree, no changes needed)
- Universal build + Retail `12.1.x (120100, 120105)`: matches tocs + toc_check pin.
- Lust scan 1..40 HELPFUL over ids 2825/32182, TBC+ only, Era/UNKNOWN closed:
  compat.lua:127 (`st.lust_supported`), compat.lua:509-511 (index cap 40). Match.
- `diag_tick_counters` default OFF, zero cost, applies next login: config.lua:30
  (`= false`). Match.
- `enemy_swing_enabled` default OFF, classic-line only: config.lua:34,
  enemy_swing.lua:61-62 (`family_supported`). Match.
- Paladin gates on `not st.is_retail` (paladin.lua:473/832/872/1996/2189), never
  `is_mainline` alone — Forever parity claim holds.
- `hunter_multi_target` ships toggle-only with "(future)" copy:
  option_tables.lua:3320-3330. Match.
- Hardening (R1 string fallbacks, R2 full 1..40 walks in compat/paladin/warrior/
  shaman/druid, R4 `== true` standardisation): per oracle-fixes + secret-hole
  reports; header stays [Unreleased] — version header cuts at publish AFTER
  owner testing, not now.

## 3. README accuracy fixes (4 lines)
- Stale harness count `24 steps` → `35 steps` in 3 places (tech-stack row,
  scripts-reference row, contributing step 4). Tree runs 35 steps (verified below).
- Tooling row: `/st` verbs completed — now lists `practice` / `design` / `diag`
  (previously practice only; main.lua:1570-1610 `open_menu` implements all four).
- Client matrix (`12.1.x (120100, 120105)`), feature list (twist band/guide/
  trainer, weave assist, on-next-attack colouring, HUD/provider contract,
  design mode, LDB, PLAYER_SWING Forever path): all match shipped reality.

## 4. TESTING.md accuracy (1 line changed, checklist re-confirmed)
- Diag example `version=2.0.8` → `2.1.0` (matches bumped `ST.addon_version`).
- Checklist already covers oracle §checklist + every lane in-client item
  (R1 `/dump`, P3/H2 lust, TF/Berserk, Mangle hide + reflow, weave
  stacks/clip/Flurry/DW, Aimed re-point, cast zone, bank/SB/Shout, practice
  reset/timeline, design targets, enemy-swing classic-only section, Retail
  stand-in + `/st diag` secrets rows); client versions current (12.1.0 + 12.1.5
  no-out-of-date-flag row). No dead steps found. No change needed beyond version.

## 5. Publish checklist
- [x] All shipped modules in all flavor tocs: toc_check green (inside 35/0 run).
- [x] Debug leftovers: `TODO/FIXME/XXX` grep over shipped Lua (excl. Libs/docs)
  → zero hits. Stray `print(` hits are commented-out code + `st.utils.print_msg`
  alias + tests/ harness output (legitimate; not touched per scope).
- [x] Endings preserved: 7 tocs CRLF, main.lua CRLF, CHANGELOG CRLF,
  README/TESTING UTF-8 no-CRLF (all as before).
- [x] Scope held: tocs (Version lines), main.lua:5, TESTING diag line, README
  (counts + verbs). CHANGELOG untouched (already accurate).
- [x] `bash tests/run.sh` → **35 steps, 0 failed**; `luacheck` → **2 warnings /
  0 errors** (standing 2, KEEP-ruled: compat.lua:34, main.lua:72).

## 6. Files changed (complete list)
SwedgeTimer.toc, SwedgeTimer_Vanilla.toc, SwedgeTimer_TBC.toc,
SwedgeTimer_Wrath.toc, SwedgeTimer_Cata.toc, SwedgeTimer_Mists.toc,
SwedgeTimer_Mainline.toc, main.lua, TESTING.md, README.md.
