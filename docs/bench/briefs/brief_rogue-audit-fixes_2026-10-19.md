# Brief: rogue-audit-fixes (2026-10-19)

## Objective
Close the small audit findings in `bench/rogue_erroraudit_2026-10-19.md`.
Writer lane, small hardenings + pins only.

## Items (all VERIFIED in the audit; read it first, don't re-derive)
- **F1** (LOW): NaN drill inputs grade D/B instead of nil. `is_num`-guard
  the marker + window/ideal reads in `practice.lua` (`:2505-2525`,
  `:2530-2548`, `:2605-2623` — verify lines in-lane): NaN → nil marker /
  nil grade (H4-symmetric). Add two NaN pins in `tests/practice_state.lua`.
- **F2** (LOW): `api.GetItemCount` passes non-number success values through
  (`compat.lua:1105-1114` — verify). Add the `type(count) == "number"`
  check for symmetry with its siblings; pin the pair in
  `tests/secret_guard_state.lua`.
- **F4** (LOW coverage): pin the 2 unasserted POOL_BANDS cells
  (`WRATH.post`, `FOREVER.pre`) in `tests/rogue_guide_state.lua:81-92`.
- **F5** (LOW coverage): add the 3 missing rule-order one-liners
  (shiv-due+envenom-due → shiv; EA-due+envenom-due → expose; shiv-due+dying
  → shiv) in `tests/rogue_guide_state.lua:336-367` area.
- **F6** (INFO, intent CONFIRMED by orchestrator): rules 4/5 firing on
  unknown/nil family is INTENDED (every rogue client has Rupture/Eviscerate;
  unknown family ≠ unknown reads; the M6 bit still suppresses everything).
  Add one `BOGUS + cp=5` pin in `tests/rogue_guide_state.lua` documenting
  the behavior so it can't drift. No engine change.
- **F3/F7/F8**: NO ACTION. F3 accepted as documented residual (unknown-idle
  is the designed E2-family contract; worst case a Tea prompt on real CD →
  press is a no-op, no cast mistiming; item-CD secrecy UNCONFIRMED).
  F7 adequate as-is by audit. F8 moot — pool-band defaults kept in
  `config_presets.lua` (verify in-lane).

## Scope
- `practice.lua`, `tests/practice_state.lua`, `compat.lua`,
  `tests/secret_guard_state.lua`, `tests/rogue_guide_state.lua`.
  Explicitly OUT: everything else (rotation provider, diag, options,
  docs, TOCs, run.sh, version).

## Rules
No git. No lint-config. Touched-lines whitespace. Endings preserved
(`file`-check first). Full harness green + luacheck floor (2/0) + mutation
proofs on `/tmp/opencode` copies (each new pin must fail when its guard is
stripped).

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write)
1. bench-read: `desks/journal.md`, `bench/rogue_erroraudit_2026-10-19.md`
   (the whole file — findings + H-closure table + coverage notes),
   `bench/lessons.md`.
2. desk-open: `desks/rogue-auditfixes/` (create or resume).
3. desk-journal append + signal-write `done` JSON (per-item disposition +
   harness result).

## Validation owner
Orchestrator: F1/F2/F4/F5/F6 closed with pins + mutations; F3/F7/F8
recorded no-action with rationale; harness + floor green.
