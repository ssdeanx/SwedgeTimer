# Audit fixes (F1, F2, F3, F5, F7, F11) — 2026-10-19

Desk: `audit-fixes`. Source: `bench/deep_audit_2026-10-19.md` (the hunter's read-only
audit, verdict FINDINGS 14). Scope of this lane: `main.lua`, `diag.lua`,
`tests/diag_state.lua`, `tests/main_init_state.lua`. Nothing else was touched
(no class files, no `hud.lua`/`bars.lua`/`compat.lua`, no TOCs, no versions, no
lint config, no git).

**VERDICT: 6/6 CLOSED.** Harness 40 steps / 0 failed, luacheck 2 warnings / 0 errors
(the floor: `compat.lua:36` unused `addon_name`, `main.lua:77` the `table.pack` shim).
10/10 mutation proofs killed.

---

## What was done

### F1 (HIGH) — the error-handler chain was never installed

`diag.install_error_handler()` had no caller anywhere, so `diag.error_ring` was never
written and `/st diag` printed "errors none" as a *fact* when nothing could have been
observed.

- `main.lua` `init_libs`: the chain is installed once, right after
  `self.interfaces_are_initialised = true` (before `init_timers`/`post_init`, so the
  rest of the session is covered). Guarded by
  `type(st.diag.install_error_handler) == "function"`.
- `main.lua`: `PLAYER_LOGOUT` is now registered (`OnInitialize`) and handled —
  `ST:PLAYER_LOGOUT` removes the chain again, so the next session never chains onto
  this session's handler.
- `diag.lua` `error_lines()`: the two empty states are now distinguishable —
  `errors none (handler installed, nothing thrown)` vs
  `errors not observed (no error handler installed)`.

### F2 (HIGH) — `PLAYER_TARGET_SET_ATTACKING` was a registered dead event

`self.has_oh` was initialised `false` in `OnInitialize` and never set again, so the
handler body always returned at its guard. The suite defeated the guard **by hand**
(`T.has_oh = true`), which is exactly what hid the defect. WIRED (not deleted):

- `main.lua` `check_weapons()`: `self.has_oh = self.offhand.has_weapon` — the same
  `api.UnitAttackSpeed("player")` offhand-speed probe that fills the bar's own weapon
  state, so the two can never disagree. It follows every weapon change
  (`PLAYER_EQUIPMENT_CHANGED` → `check_weapons`).
- `main.lua` `ST:PLAYER_TARGET_SET_ATTACKING()`: the guards now describe the real
  state, and every operand is nil-guarded:
  1. `interfaces_are_initialised` (unchanged),
  2. `self.has_oh` — the player really has an offhand weapon,
  3. `self:has_hand("offhand")` — **new** `ST:has_hand()` helper (the class hands
     list, the same authority `iter_hands()` uses). A paladin or a druid has an
     offhand weapon but *no offhand bar*: without this guard `set_bar_color("offhand")`
     would read `db.profile.<CLASS>.offhand`, which AceDB's `**` metatable
     auto-creates as a synthetic table — `bar_color_default` nil →
     `convert_color(nil)` → a Lua error in a live event handler,
  4. `type(offhand.speed) == "number"` and `type(offhand.start) == "number"` (nil
     before the first swing and on the inert stand-in) and `speed > 0` (a zero-length
     cycle would divide by zero in the bar's progress maths),
  5. the clock is `api.get_time()` (compat's aligned clock, same domain as the
     engine's `GetTime()` stamps) instead of the raw global.
  The re-sync moves **both** ends of the cycle (`start = t - speed`, `ends_at = t`):
  the bar divides by `(ends_at - start)`, so moving `start` alone could leave a
  negative span and a negative bar width.

### F3 (MED) — the report could vanish silently

`diag.print_line` used the bare global `print` as its only output path. Now: the
sink → the global `print` → **`st.utils.print_msg`** (the addon's own printer, which
writes to the chat frame). The switch is announced once
(`the global print is unavailable; the report goes to the chat frame`), so a report
that changed channel is never mistaken for a report that never ran. With neither
printer the report degrades to silence, never to an error.

### F5 (MED) — `HUD.cleu_register_errors` had no reader

The HUD's combat-log registration counter was write-only; hud.lua's comment named a
`/st diag` reader that did not exist. `ST.print_runtime_diag` (`main.lua`) is that
reader now: the runtime line carries `hud_cleu_register_errors=<n>` (0 when the HUD
module is absent). hud.lua itself was **not** touched (sibling lane).

### F7 (LOW) — `ST:needs_gcd()` deleted

No callers, and its `get_hand_table("offhand"/"ranged")` reads auto-create synthetic
AceDB tables — a future caller would have read a plausible non-real table. The GCD
underlay is gated per hand inside `bars.lua`'s `onupdate_common`
(`db.show_gcd_underlay and self.gcd.expires`), so nothing is lost.

### F11 (LOW) — the seven `assert(event == event)` tautologies

All seven production handlers (`CURRENT_SPELL_CAST_CHANGED`, `PLAYER_ENTERING_WORLD`,
`PLAYER_EQUIPMENT_CHANGED`, `UNIT_AURA`, `UNIT_POWER_FREQUENT`,
`UNIT_SPELLCAST_FAILED_QUIET`, `UNIT_SPELLCAST_SUCCEEDED`) now name their unused
arguments (`_event`, `_is_initial_login`, …). Nothing was silenced with `_` in a body;
the `.luacheckrc` already ignores unused arguments (code 212), so the asserts were
never needed for the linter either.

---

## Proof (mutations on `/tmp/opencode` copies, each killed by a pin)

| mutant | killed by |
|---|---|
| `F1-install-removed` | `F1: init installs the chained error handler once` |
| `F1-uninstall-removed` | `F1: PLAYER_LOGOUT removes the chained error handler` |
| `F1-empty-state-collapsed` | `verbose line 73 reports that no error handler was installed (F1)` |
| `F2-has_oh-not-derived` | `F2: has_oh is derived from the offhand probe, not hand-set` |
| `F2-class-guard-removed` | `F2: a class without an offhand bar leaves the offhand timer alone` |
| `F2-nil-guard-removed` | `F2: a nil offhand cycle does not error` |
| `F3-fallback-removed` | `F3: the report falls back to the addon's chat printer` |
| `F5-hud-counter-line-removed` | `F5: the runtime diag line reads the HUD's combat-log registration counter` |
| `F7-needs_gcd-restored` | `F7: the dead needs_gcd helper is gone from main.lua` |
| `F11-tautology-restored` | `F11: main.lua has no unused-argument tautology asserts` |

Script: `/tmp/opencode/mutate.py` (10/10 killed). The pins themselves live in
`tests/main_init_state.lua` (new sections 15-17) and `tests/diag_state.lua`
(new section 14b + the printer-robustness block).

## Test-harness changes worth knowing

`tests/main_init_state.lua`'s fixture is now class-parameterised (`opts.class`,
`opts.use_offhand`) and creates the anchor frames for **every** hand of that class
(`ST.class_hands`), not only the mainhand. The old `T.has_oh = true` hand-sets were
removed from the init-guard phases — they are what hid F2. `tests/diag_state.lua`'s
"errors none" pin now expects the not-installed wording.

## Still open (not this lane)

- **F4** (`compat.lua` `get_family_spell_id` on TBC) — compat lane.
- **F6** (base TOC advertises mainline interfaces while shipping the classic
  combat-log lib) — operator-level; a sibling lane closed it on 2026-10-19 (the base
  TOC is now the classic-line fallback, per the AGENTS.md cross-engine note).
- **F8/F9/F10/F12/F13/F14** — class files / `bars.lua` / `hud.lua` / practice /
  design files: sibling lanes.
