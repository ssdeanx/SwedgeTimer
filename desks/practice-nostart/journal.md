# Practice Nostart — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Silent practice-start failures (operator: no-start in-game, no error text) + per-class fidelity/scoring audit.
- **Scope:** `practice_ui.lua` (start-path diagnosis + fixes only) and `tests/practice_ui_state.lua` (pins only). Class files READ-ONLY; `main.lua`/options/defaults sibling-owned.
- **Next step:** Trace every fail-closed start path, fix, pin, verify 38/0 + luacheck floor.

## 2026-10-19 — Start-path diagnosis + cross-class sweep landed
- **Worked on:** every `ui.start` gate now speaks once + counts in `bar_hook_errors` (`practice:start`, read by /st diag): no-engine (legacy message kept), combat (legacy), panel-nil (lazy `ui.init` retry first, then panel-not-built message), per-drill session-rejected messages, per-class key-drift messages. Hardened: nil-safe `resolve_base_speed`/db reads/`show_result`/`apply_settings`, pcall-isolated class shells (starters, readouts, stop/start_fight/fight-timer), order validation, shaman weave-marker resolvability gate, ST-qualified dispatch literals kept for the wiring check.
- **Cross-class sweep:** whole start/session/panel path audited for calls resolving only via another class's module; remaining direct class calls are type-guarded + pcall-isolated with fail-loud counters. No cross-class stragglers left on the shaman path.
- **Per-class fidelity (operator bar):** paladin order==ABILITY_ORDER pinned; hunter/shaman/rogue panel order follows shell orders pinned; rogue 2 s tick + shaman/rogue swing==equipped speed pinned; warrior routing pinned as documented shared session (no native drill shell exists — filed with seam spec, behavior kept). Scoring chain verified per class (record_attempt/update_score/show_result/bests; hunter always grades in-fight, rogue marker resolves via defaults, druid always grades, shaman marker gated at start). Filed (header + reason, class-side owed): hunter per-client cast_times, hunter latency comp, rogue live latency reader, druid live regen/cost readers, warrior native sim.
- **Current state:** `tests/practice_ui_state.lua` 1075 checks PASS; full harness 38/0; luacheck 2/0 floor held; both files lint-clean; CRLF/LF preserved. Mutation proofs 6/6 killed on /tmp/opencode/mut-nostart (M1-M6).
- **Next step:** Orchestrator validation (owns Done). Live in-client confirmation still owed (UNCONFIRMED), like all offline pins.

## 2026-10-19 — [signal:done] Practice start speaks on every path, per-class verified
- Harness 38/0 + luacheck floor held; 6/6 mutants killed; journal + signal filed.
