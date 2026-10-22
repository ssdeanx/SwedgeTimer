# Audit Fixes — Journal

Focus: the MATERIAL findings (F1, F2) plus the main.lua-local mediums (F3, F5, F7, F11)
from `bench/deep_audit_2026-10-19.md`.

## 2026-10-19 — Desk opened
- **Purpose:** Close the two material audit findings (F1 error-handler chain never
  installed; F2 `PLAYER_TARGET_SET_ATTACKING` guard unreachable) and the main.lua-local
  mediums (F3 print fallback, F5 HUD CLEU counter reader, F7 dead `needs_gcd`,
  F11 `assert(event == event)` tautologies).
- **Scope:** `main.lua`, `diag.lua`, `tests/diag_state.lua`, `tests/main_init_state.lua`.
  Nothing else — sibling lanes own the other files. No git, no lint-config changes.
- **Baseline:** harness 40 steps / 0 failed, luacheck 2 warnings / 0 errors (the floor:
  `compat.lua:36` unused `addon_name`, `main.lua:77` `table.pack` shim).
- **Next step:** implement F1 (install/uninstall the error chain, two distinguishable
  empty states), then F2 (drive `has_oh` from `check_weapons`), then F3/F5/F7/F11,
  with a kill-mutant per fix on `/tmp/opencode` copies.

## 2026-10-19 — [signal:done] F1, F2, F3, F5, F7, F11 closed (6/6)
- **Worked on:** the two material audit findings plus the main.lua-local mediums from
  `bench/deep_audit_2026-10-19.md`.
- **F1:** `main.lua` installs the chained error handler in `init_libs` (after
  `interfaces_are_initialised`) and removes it in the new `PLAYER_LOGOUT` handler;
  `diag.lua` `error_lines()` now distinguishes "nothing threw (handler installed)"
  from "nothing was watched (no handler)".
- **F2:** WIRED, not deleted. `check_weapons()` derives `has_oh` from the same
  `api.UnitAttackSpeed` offhand-speed probe that fills `offhand.has_weapon`; the
  handler guards on the init flag, `has_oh`, a new `ST:has_hand("offhand")` (a
  paladin/druid has an offhand weapon but no offhand bar - the recolour would have
  touched frames that do not exist), and nil/zero-safe cycle operands; the clock is
  `api.get_time()`; the re-sync moves both ends (`start` + `ends_at`) so the bar's
  `(ends_at - start)` span can never go negative.
- **F3:** `diag.print_line` falls back to `st.utils.print_msg` when the global print
  is absent/broken and announces the switch once.
- **F5:** `ST.print_runtime_diag` now carries `hud_cleu_register_errors=<n>` (the
  reader hud.lua's comment promised). hud.lua itself untouched (sibling lane).
- **F7:** `ST:needs_gcd()` deleted (no callers; its hand-table reads auto-created
  synthetic AceDB tables). The GCD underlay is gated per hand in bars.lua.
- **F11:** the seven `assert(event == event)` tautologies replaced by named
  `_event`-style parameters; nothing silenced in a body.
- **Verification:** harness 40 steps / 0 failed; luacheck 2 warnings / 0 errors (the
  floor held); 10/10 mutants killed by named pins (`/tmp/opencode/mutate.py`).
  `tests/main_init_state.lua` grew sections 15-17 and its fixture is now
  class-parameterised (`opts.class`, `opts.use_offhand`); the old `T.has_oh = true`
  hand-sets are gone (they are what hid F2).
- **Artifacts:** `bench/audit_fixes_2026-10-19.md`; signal
  `desks/audit-fixes/.signals/2026-10-19T20-15-00Z.json`.
- **Current state:** all six findings closed in-tree; the central ledger
  (`desks/journal.md`) is the orchestrator's to update.
- **Next step:** the orchestrator validates (harness + mutation proofs) and closes
  F1/F2/F3/F5/F7/F11 in the audit ledger. F4/F8/F9/F10/F12/F13/F14 stay with their
  own lanes; F6 was closed by a sibling lane (the base TOC is now classic-line only).

