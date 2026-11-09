# Brief: fix-engine-dispatch (2026-10-19)

## Objective
Fix the engine/dispatch/range half of `bench/feature_hunter_audit_2026-10-19.md`. Writer lane.

## Scope (disjoint — ONLY these addon files)
- `main.lua`: H1 (dead-engine sentinel — stub returns nil-shaped idle or per-hand `engine_dead` rendered unknown, never a plausible 1 s cycle), H3 (guard the `callback_event_handler` fan-out with per-event error capture + `diag` counter, keep per-handler init guards), H6 (add `interfaces_are_initialised` early-return to the 7 thin UNIT_SPELLCAST_* fan-in handlers unless a callee-side guard is cited in-file with file:line), M1 (bounded retry+backoff for `rf_update` before session-disable + `diag` count), M2 (cap the nil-checker re-arm loop, fold into deadline state + one-time notice + `diag` flag).
- `bars.lua`: H2 (isolate `class.on_bar_update` + zone `draw_fn` per tick — bar fill/text still paint, first error per session recorded chat-once + `diag` counter, optional quarantine after N throws; never silent), H1-render (read the engine-dead sentinel: dim + "engine offline" text instead of a live-looking cycle).
- `swing_source.lua`: H5 (payload/speed-read reject counters surfaced in `/st diag` verbose + one-time chat notice on sustained rejects; keep-old-cycle behavior unchanged).
- `enemy_swing.lua`: M7 (render fallback-2.0 cycles distinctly from measured — dim/hatched or target-name text instead of fake countdown; hide, not freeze, when `now()` is nil).
- Tests (pins for the above; extend, don't rewrite): `tests/main_init_state.lua`, `tests/bars_state.lua`, `tests/swing_source_state.lua`, `tests/enemy_swing_state.lua`. New pins get mutation proofs (guard-stripped `/tmp/opencode` copies fail the new pin).
- Explicitly OUT (owned by fix-guides-weave lane — touch it and you collide): `weave.lua`, `nextaction.lua`, `nextaction_ui.lua`, `compat.lua`, `classes/`, `hud.lua`, TOCs, version fields, CHANGELOG.

## Standing rules
No git. No lint-config changes. Wire-not-strip for any luacheck fallout. Whitespace fixes only inside touched lines. Endings preserved (CRLF). New toggles nil-safe (`== false` hides, nil = off, defaults documented). Full `bash tests/run.sh` green before done (35 steps baseline + new pins).

## Workshop mechanics (mandatory — skills: bench-read, desk-open, desk-journal, signal-write)
1. bench-read: `desks/journal.md`, `bench/feature_hunter_audit_2026-10-19.md`, `bench/feature_proctor_audit_2026-10-19.md` (G1/G4 context only — G-pins are the other lane's), `bench/lessons.md`, `hands-up.md`.
2. desk-open: ensure `desks/fix-engine/` exists; resume if live.
3. desk-journal append + signal-write `done` JSON listing every file changed + harness result.

## Validation owner
- Orchestrator: every H-item closes with file:line + harness proof + mutation proof; M-items close or carry a one-line justification. Reconciles against fix-guides-weave (no shared files).
