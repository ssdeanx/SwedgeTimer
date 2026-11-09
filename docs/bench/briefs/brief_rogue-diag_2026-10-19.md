# Brief: rogue-diag (2026-10-19)

## Objective
One-line parity gap with a pin. Writer lane.

## Gap (VERIFIED)
`diag.lua:51`: `PROVIDER_CLASSES = { "PALADIN", "WARRIOR", "DRUID", "SHAMAN",
"HUNTER" }` — ROGUE missing, so `/st diag` never reports rogue guide
enablement. Add `"ROGUE"`.

## Scope
- `diag.lua` (the one line; read the surrounding contract in-lane).
- `tests/diag_state.lua` (exists — read in-lane; extend the provider-class
  pins to cover ROGUE, including the absent-provider degradation shape).
- Explicitly OUT: everything else. No other lane owns these files this wave.

## Rules
No git. No lint-config. Touched-lines whitespace. Endings preserved
(`file`-check first). `bash tests/run.sh` green + luacheck floor before
done. Mutation proof on a `/tmp/opencode` copy (strip ROGUE → pin fails).

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write)
1. bench-read: `desks/journal.md`, `bench/lessons.md`.
2. desk-open: `desks/rogue-diag/` (create or resume).
3. desk-journal append + signal-write `done` JSON.

## Validation owner
Orchestrator: diag reports ROGUE provider state; pins green; harness + floor.
