# Desk journal: rogue-diag

## Worked on
- `diag.lua:51`: appended `"ROGUE"` to `PROVIDER_CLASSES` (one-line scope change;
  CRLF endings preserved, verified with `file` before/after).
- `tests/diag_state.lua`: extended provider pins to six classes — healthy fixture
  (`ROGUE = {}` profile nil-gate + `ROGUE.guide` provider), `HEALTHY_LINE`
  `ROGUE:on`, empty-state loop, section-8 guides line (`all six`), `ROGUE = "on"`
  in the expected table, denominators `5/6` (one-missing) / `0/6` (none) /
  `6/6` (healthy verbose), plus a dedicated ROGUE-absent degradation block
  (`ROGUE:none` + `providers=5/6`). Header comment `five` → `six`.

## Current state
- `lua5.1 tests/diag_state.lua`: PASS (186 checks).
- `bash tests/run.sh`: 37 steps, 0 failed; luacheck 2 warnings / 0 errors (floor held).
- Mutation proof on `/tmp/opencode/rogue-diag-mut` (repo-relative layout, ROGUE
  stripped from the `diag.lua` copy only): 8 pin failures covering the healthy
  line, ROGUE states, and all three count denominators — pins are load-bearing.
  In-tree control re-run: PASS.
- Out of scope observed, not touched: sibling lanes' files (`compat.lua`,
  `classes/rogue.lua`, `config_presets.lua`, `option_tables.lua`, etc.) also
  modified in tree; final harness re-run already includes them (still 37/0).

## Next step
- Done. Awaiting orchestrator validation (diag reports ROGUE provider state).
