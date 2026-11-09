# Buildout: changelog — release notes + doc matrix through the full round (N1 included)
Date: 2026-10-17. Desk: changelog. Brief: bench/briefs/brief_changelog_2026-10-17.md.
Status: **done, docs only** (no code touched, no git).

## 1. Sections added (CHANGELOG.md, [Unreleased] only — no released history rewritten)
- `### Added` bullet 1 (universal build): Retail now `12.1.x (120100, 120105)` — N1, living statement so updated in place.
- Twist bullet: R3 P1-on-Forever "classic-line only" notice documented.
- New `### Build-out round + hardening (2026-10-17 ...)` subsection: lust window (C2/H2/P3), diag tick counters, C3/C6/D3 + mouse anchoring, paladin P1/P2/P6/P7/CD-row, warrior W1/W2/W3/BS-glow + 4 slot toggles, hunter H1/H2/FD/Readiness/cast-zone/pet-badges/Aimed, shaman S2/S3/S4/RB/shield + weave round 2 (2-3-stack markers, zone band, clip, Flurry/DW), druid D2-D6/Omen/GCD-tick, practice C1 + P5/H5/W6/D7/S7 + reset/timeline/design targets, enemy-swing bar, 27+4 toggles + `(future)` copy, enterprise-grade 5-lane wave, oracle R1–R4 hardening, harness 35/0 + luacheck 2/0. Every in-client behavior marked UNCONFIRMED.

## 2. N1 lines changed
- README.md:66 → `` `12.1.x (120100, 120105)` ``.
- TESTING.md:16 → `` `12.1.x (120100, 120105)` ``; TESTING.md:120 header → `### Retail / Live (12.1.x — 120100, 120105)` + new 12.1.0/12.1.5 no-out-of-date-flag row.
- CHANGELOG.md:8 → `Retail (120100, 120105)` (living [Unreleased] line, not released history — updated, not noted-away); plus the 120105 bullet in the round subsection.

## 3. TESTING checklist vs oracle-audit §checklist (added rows; none removed)
- R1 `/dump` spellId slot-type check + twist success/JotC refresh cadence (Era/TBC + WotLK JotC row).
- P3 lust narrowing + H2 Steady-spam cue under live Bloodlust/Heroism.
- TF/Berserk liveness/glow; Mangle runeless-Era hide + row reflow; combat-exit deferred reflow.
- Weave 2-3-stack markers + zone band + clip state + Flurry ICD + DW sync badges.
- Aimed-shot re-point, hunter safe-to-move cast zone, warrior bank/SB/Shout badges.
- Practice reset re-anchor + timeline drag/close; design-mode practice_rotation/timeline targets.
- NEW `### Enemy swing (classic line only)` section (classic-line bar expected; Forever/Retail nothing-draws).
- Retail stand-in + `/st diag` secrets rows already present — kept.

## 4. Consistency statement
- Versions match AGENTS.md matrix + tocs: base `SwedgeTimer.toc` and `_Mainline.toc` advertise 120100+120105; `tests/toc_check.lua` pins both; README/TESTING/CHANGELOG now all read `12.1.x (120100, 120105)`.
- `lua5.1 tests/toc_check.lua` → **732 checks, 0 failures** (docs-only, tree untouched).
- Endings preserved: CHANGELOG.md CRLF; README.md / TESTING.md UTF-8 no-CRLF (all as before).
- Scope held: CHANGELOG.md, README.md, TESTING.md only. No git.

## 5. Files changed (complete list)
CHANGELOG.md, README.md, TESTING.md.
