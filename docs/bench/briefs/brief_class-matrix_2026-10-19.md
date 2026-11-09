# Brief: class-matrix (2026-10-19)

## Objective
Read-only feature-matrix audit: every class × every shared system. Findings, not fixes. This settles "what's missing" with evidence instead of claims.

## Matrix (verify each cell in-tree, cite file:line)
Rows: DRUID, HUNTER, PALADIN, SHAMAN, WARRIOR, ROGUE. Columns:
1. HUD slots + get_hud_state (frozen contract hud.lua:20-60)
2. guide provider + gather_guide_inputs (contract nextaction_ui.lua:13-82)
3. get_rotation_key (contract rotationtext.lua:18-24)
4. on_bar_update driving guide+HUD in order
5. on_combat_exit preserving the mainhand record (G4)
6. spell-id tables (highest-rank-wins + Anniversary name-fallback where CLEU matched)
7. practice scenarios (practice.lua registry)
8. diag provider listing (diag.lua PROVIDER_CLASSES)
9. options section (thresholds, copy accuracy, slot toggles, rotation widgets, disabled-gating, order uniqueness)
10. TOC wiring (all 7 flavor TOCs, load order)
11. test suites (state + contract + options + rotationtext + diag pins)
12. design/designmode integration + LibGlobalCooldown relevance + option_table_presets branch + gcd marker modes

## Scope
READ-ONLY except one NEW bench file + own desk. Output: bench/class_matrix_2026-10-19.md (confirm absent at lane start; supersede-with-pointer if present). Per cell: WIRED / MISSING / DEGRADED + evidence + severity (casual vs top-100 ms stakes) + owning lane for the fix (code / options / tests / docs). Writer lanes run in parallel on rogue + five-class files — grade the tree as-read; anything they own goes in a PROVISIONAL section, not the verdict.

## Rules
No code edits. No git. Extend prior audits, never re-derive (feature_hunter, feature_proctor, rogue_erroraudit, rogue_readiness §4). UNCONFIRMED where in-client.

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write — perform via file ops)
1. bench-read: desks/journal.md, readiness §4, both hunter audits, rogue_erroraudit, lessons.md, hands-up.md.
2. desk-open: desks/class-matrix/ (create or resume).
3. desk-journal append + signal-write done JSON (cell counts + verdict).

## Validation owner
Orchestrator reconciles matrix against writer lanes; every cell has evidence.
