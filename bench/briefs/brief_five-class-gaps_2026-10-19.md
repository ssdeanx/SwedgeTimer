# Brief: five-class-gaps (2026-10-19)

## Objective
Each of DRUID/HUNTER/PALADIN/SHAMAN/WARRIOR uses every shared system it can use. Fix gaps at top-100 bar (no confident-on-unknown regressions, ms-correct). Writer lane.

## Checklist (same contracts as the parallel matrix lane — find gaps yourself, don't wait for it)
HUD slots+provider, guide provider+gather, get_rotation_key, on_bar_update order, on_combat_exit record preservation, spell-id tables (+R1 name-fallback where CLEU matched), practice scenarios, designmode integration, spellcast lifecycle self-guards (H6 rule: callee guards, main.lua:1755 has none). Compare each class against its siblings; a system one class uses that another could use is a gap until proven otherwise.

## Scope
- classes/{druid,hunter,paladin,shaman,warrior}.lua + their tests (druid/hunter/paladin/shaman/warrior_state, class guide_state suites, practice_state class parts, guide_contract class parts).
- CONDITIONAL: diag.lua + tests/diag_state.lua (only if a class-scoped diag gap found — nobody else owns them), practice.lua (only for missing class scenarios + pins).
- Explicitly OUT (parallel lanes own them — log needs as follow-ups with file:line, NEVER edit): config_presets.lua, option_tables.lua, classes/rogue.lua, rogue_guide.lua, compat.lua, TOCs, run.sh, version fields, docs, CHANGELOG.

## Rules
No git. No lint-config. Wire-not-strip (REMOVE only purposeless-after-tracing + rationale). Touched-lines whitespace. Endings preserved (file-check). Nil-safe, no default-visible change without an explicit gate (owner gates only — otherwise gate + default off). Full harness green + floor + mutations on /tmp/opencode copies. No open-ended invention: wire existing systems; genuinely new features come from the competitor lane next wave.

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write — perform via file ops)
1. bench-read: desks/journal.md, readiness §§1/4, hunter+proctor audits, rogue_erroraudit H-closure table (holds for rogue paths — don't re-audit), lessons.md, hands-up.md.
2. desk-open: desks/five-class-gaps/ (create or resume).
3. desk-journal append + signal-write done JSON (per-class dispositions, options follow-ups, harness).

## Validation owner
Orchestrator: per-class gap list closed or filed as follow-up with evidence; harness + floor green.
