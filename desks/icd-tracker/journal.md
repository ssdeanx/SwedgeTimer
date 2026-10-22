# Desk: icd-tracker — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Competitor gap X1 (cross-class ICD status tracker) + X3 read-only settings-panel check.
- **Scope:** ONLY hud.lua (verify shared row; change only if a guessed-countdown path is proven offline), compat.lua (probe ONLY if a shape is missing), per-class trinket inputs (all six declare trinket1/2 — verify wiring, pin the uncovered class), tests/hud_state.lua + tests/secret_guard_state.lua (+ per-class state pins for new inputs). OUT: options panels, docs, TOCs, run.sh, version.
- **Priors read:** desks/journal.md (37/0, luacheck 2/0 floor), bench/competitor_gaps_2026-10-19.md §1.5 + X1/X3, desks/shaman-icd/journal.md (S1 landed: lust state + TRINKET_DATA UNCONFIRMED header + secret_guard 13d).
- **Next step:** baseline harness (done: 37/0, 2/0), then pin rogue trinket inputs (only class without hud_state coverage) + CombatLog probe pair in secret_guard + X3 per-flavor verdict.

## 2026-10-19 — lane done
- **Worked on:** X1 cross-class ICD row: no hud.lua/compat.lua change (verified shapes present; S1 owns the header/probe). Added hud_state §19 rogue trinket pins (12 descriptors, order, inv_slots 13/14, unresolved-spell contract, 12-icon build, provider cleared-table, unknown-icd idle) + ROGUE sandbox table + §17 wiring list; secret_guard build combat_log hook + §13e CLEU pair (control/absent).
- **Current state:** my suites green (hud 461, secret 328); full harness 37/0, luacheck 2/0 (75 files). 6/6 mutations kill on /tmp copies (M1 inv_slot, M2 invented state, M3 stripped descriptor, M4 stripped init, M5 stripped hook, M6 broken probe); /tmp copies removed after byte-identical restore.
- **Next step:** orchestrator reconcile. X3 verdict + UNCONFIRMED ledger in lane summary (bench report or handoff); X3 needs no code (registration path shared, in-client appearance UNCONFIRMED).

## 2026-10-19 — [signal:done] X1 lane complete, ready for reconcile
- Harness 37/0, luacheck 2/0; 6/6 mutations kill; signals emitted.
