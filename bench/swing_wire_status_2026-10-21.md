# Swing wire + options panel — status at the end of the operator session (2026-10-21)

Operator closed the session here. This file is the honest state; it is not a
claim that anything was verified in a game.

## Landed in the tree (uncommitted; the operator copies files by hand)

1. `main.lua` — the callback dispatcher drops the classic engine's leading
   unit-id on `SWING_TIMER_*` events, so the vendored lib's wire shape
   (`unitId, speed, expiry, hand`) and swing_source's (`speed, expiry, hand`)
   land on the same handler shape. Plus per-hand receipt counters
   (`note_swing_wire`) and a `/st diag` runtime line
   (`swing_<hand>=START/UPDATE/STOP`, `swing_last=KIND:hand:age`,
   `proj=`, `exp=`, `bcc=`).
2. `option_tables.lua` — `class_activation.sorting` was a two-argument
   comparator; AceConfigDialog calls `sorting(info)` and expects the ordered
   key array back, so the options panel threw on open. Now a literal array
   (the file's own convention, cf. `show_bar_conditions_sorting`).
3. `tests/main_init_state.lua` §14b — wire-shape pins through the real
   dispatcher (classic unit-id lead, Forever speed-first, hand-only STOP) and
   the diag-line pins.
4. `tests/options_load_state.lua` — the widget walker now resolves every
   select's `sorting` the way AceConfigDialog does (call-with-info, array
   back, keys covered both ways) + an Auto-first order pin.
5. `tests/secret_guard_state.lua` — the removed `api.CheckInteractDistance`
   block replaced by an absence pin (432 checks).

## Offline proof (this is the only proof that exists)

- `bash tests/run.sh` → 46 steps, 0 failed; `luacheck .` → 2 warnings / 0
  errors in 88 files.
- M1: the unit-id strip neutered → §14b fails.
- M2: over-strip any leading string → §14b fails (it eats Forever's
  hand-only STOP).
- M3: the options comparator restored on a `/tmp/opencode` copy → the walker
  fails with the exact production error
  (`option_tables.lua:219: attempt to compare table with nil`) on every class
  walk.

## NOT proven — owed, in-client

- The ranged bar on TBC Anniversary (hunter) and the mainhand bar on every
  client. The operator's last observations were on the PRE-fix files (nothing
  had been copied), so there is no post-fix in-client evidence at all. Treat
  the ranged bar as UNPROVEN, not as fixed.
- The vendored lib's per-family runtime behaviour in a real client
  (`isBCC` detection, per-shot `UNIT_SPELLCAST_SUCCEEDED` on Anniversary).

## Left unreconciled (read this before trusting the tree)

`main.lua`, `hunter_ui.lua` and the vendored `LibRangeCheck-2.0` also carry the
`range-engine-tbc` lane's work (exact-yard range state, per-subfeature guard
sites, the interact-checker removal). That lane died on a rate limit AFTER
writing its files and report; its suite is green, but the orchestrator never
re-read that diff. Report: `bench/range_engine_tbc_2026-10-21.md`.

## If the session resumes

1. Copy `main.lua` + `option_tables.lua` (the two test files are offline
   only). Nothing else changed in this wave.
2. Before any further in-client ask: build a harness that runs the REAL
   vendored `LibClassicSwingTimerAPI` (v32 — byte-identical to the operator's
   paste, untouched) plus the real dispatcher, driving each family's real
   event sequence. The current suites stub the engine, which is exactly why
   the wire defect survived them.
