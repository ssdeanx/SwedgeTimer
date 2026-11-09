# display-fix — Journal

## 2026-11-06 — Desk opened: Forever display defects (Auto Shot display, weave range bar)

- **Purpose:** fix the operator's Forever (Camelot 1.60.1 / Interface 16001, Mainline-code)
  display reports: (A) a Hunter Auto Shot that fires but is sometimes not displayed, and
  (B) the horizontal standalone range bar (`weave_range.lua`) that worked then stopped
  displaying. The Auto Shot red zone is display-only and must never gate the bar.
- **Scope (write):** `main.lua`, `hunter_ui.lua`, `weave_range.lua`, `classes/hunter.lua`,
  `swing_source.lua`, `tests/main_init_state.lua`, `tests/range_source_state.lua`,
  `tests/weave_bar_state.lua`, `tests/hunter_state.lua`, `tests/swing_source_state.lua`,
  `tests/engine_matrix_state.lua`, `tests/wiring_check.lua`, `desks/display-fix/**`, one
  new bench report. NOT mine: `bars.lua`/`utils.lua` (bars-perf), `power_bar.lua`/
  `compat.lua`/`diag.lua` (powerbar), TOCs/README/CHANGELOG, `tests/bars_state.lua`,
  `tests/power_bar_state.lua`, `tests/run.sh` (Lead), `Libs/`, git.
- **Priors read:** `desks/journal.md` (tail: 2026-11-06 dispatch), `bench/lessons.md`,
  `AGENTS.md` (Cross-engine + Gotchas), `bench/bars_perf_audit_2026-11-06.md` (on disk it
  is a 17-line summary without the cited §4/§5 — the full census is in
  `desks/perf-audit/journal.md`), `bench/forever_display_audit_2026-11-06.md`
  (A-1/A-2/A-3/A-4, B-1/B-5/B-6/B-7, §8 red-zone verdict).
- **Lane skills:** bench-read, desk-open, desk-journal, signal-write — all present.
- **Version warning:** the tree reads 2.2.0 in the 7 TOCs + `main.lua:5` (rogue read-only
  desk at 14:11). Operator-approved target is 2.1.8; Lead/release-version restores it.
  This desk touched no version field.

## 2026-11-06 — Worked on (final state)

- **A-1 HIGH (`swing_source.lua`):** a restricted/malformed `PLAYER_SWING` payload used
  to drop one cycle silently (the 5 s sustained notice cannot see one payload) and a
  secret duration could throw before any counter. Now: secret values are probed before
  any comparison; a bad duration on a known hand is RECOVERED from the equipped speed
  (`read_equipped_speed`: UnitAttackSpeed per-hand, UnitRangedDamage for ranged; pcall +
  secret-check); only "no readable speed" is a counted reject. First reject announced once
  per session; `speed_fallbacks`/`first_reject_notice` in `diagnostic_text`.
- **A-2/R1 HIGH (`main.lua`):** `rf_update` was the only visibility driver and could die
  for the session (visibility/alpha outside the pcall whose re-arm was last; early return
  on `rf_disabled`). Now: `run_bar_visibility_pass` pcalls visibility AND alpha
  separately (counted in `rf_heartbeat_errors`), the heartbeat re-arms unconditionally,
  and the disabled poll still runs both passes. Ranged START/UPDATE (Forever), completed
  shot receipt and hunter auto-repeat events each open the bar in the same event.
- **A-3/A-4 HIGH (`main.lua`, `classes/hunter.lua`):** `check_weapons` no longer turns an
  unknown/restricted stat read into "no weapon" (only a readable number moves the flag;
  readable 0 still clears); world entry re-probes; a Forever ranged/offhand START proves
  the weapon + runs the lazy build + re-runs visibility. Auto Shot armed cache now uses
  the numeric id 75 through ONE shared probe: forced from `SPELL_UPDATE_COOLDOWN` (before
  its early returns) and `START/STOP_AUTOREPEAT_SPELL`, throttled 4/s from the class tick;
  a change opens/closes the bar in that event. Ranged activity window falls back to the
  hunter sync's cycle before the first engine stamp.
- **Red zone (display-only):** audit §8 PASS confirmed; explicit contract comment in
  `hunter_ui.update_cast_zone` + behavioural pins (disabled/absent/throwing zone never
  hides the bar, rewrites `ranged.start/speed`, or stops the cast bar).
- **B-5/B-6/B-1/B-7 (`weave_range.lua`, `main.lua`):** unknown distance now renders an
  explicit neutral face (dim full fill + `--`) instead of disappearing; quarantine is
  recoverable (driver stays armed, last paint kept, 10 s→60 s backoff retry); init is a
  guarded idempotent seam retried once from `PLAYER_ENTERING_WORLD`; `weave=` diag token
  (enabled/shown/why/distance/state/failures/quarantine) appended to the runtime line.
- **Crossfire closed (Lead-assigned):** `tests/engine_matrix_state.lua` forever-payload
  pins re-cut to the new contract (fallback with a readable speed; reject without one);
  `tests/wiring_check.lua` lost the 2 stale ACCEPTED rows (START/UPDATE now guarded;
  STOP stays accepted).
- **Evidence:** own suites green — swing_source_state 188, main_init_state 1117,
  hunter_state 2080, weave_bar_state 140, weave_range_state 90, engine_matrix_state 110,
  wiring_check 905/0 (0 stale), bars_state 1305, diag_state 389, toc_check 1104;
  luacheck on the edited files clean except the pre-existing hunter_ui floor pair.
  17/17 mutations killed on an isolated `/tmp` copy (control runs green).
  Full report: `bench/display_fix_2026-11-06.md`.
- **Current state:** all fixes landed offline-proven; no in-client proof (the report's
  UNVERIFIED list is the close). Full-gate result recorded in the signal/bench follow-up
  line below.
- **Next step (Lead):** full `bash tests/run.sh` on the settled three-desk tree; restore
  version fields to 2.1.8; operator copies the changed files and runs the in-client
  checks (V1-V6); the filed follow-ups A-5/A-7/secret_guard_state §8/bars_state
  hide-reason pin are NOT done here.

## 2026-11-06 — [signal:done] Full gate green; report filed
- `bash tests/run.sh` (final, settled three-desk tree): **57 steps, 0 failed**;
  `luacheck .` **2 warnings / 0 errors in 100 files** (the pre-existing hunter_ui floor
  pair). The mid-wave `power_bar_state` reds were the powerbar desk's in-flight edits —
  resolved on the final tree, not touched here.
- Report: `bench/display_fix_2026-11-06.md`; done signal
  `desks/display-fix/.signals/20261106T194544Z.json`.
- In-client (UNVERIFIED, owed): skipped-shot attribution via the new `/st diag`
  counters (`swing source payload_rejects/unknown_type/malformed_duration/
  speed_fallbacks`, `swing_ranged`, `weave=`); `C_Spell.IsAutoRepeatSpell(75)` vs the
  name form; `UNIT_SPELLCAST_SUCCEEDED(75)` per Auto Shot; `checkedDistance` frequency
  on real targets; restricted `UnitRangedDamage`/`UnitAttackSpeed` reads.
- Follow-ups NOT done (out of this desk's verdict): A-5 combat-exit cycle clear,
  A-7 PLAYER_TARGET_CHANGED registration, stale `tests/secret_guard_state.lua` §8
  representation of `check_weapons`, the `tests/bars_state.lua` hide-reason pin, and the
  version restore to 2.1.8 (Lead).

## 2026-11-06 — [signal:done] Follow-up: secret_guard_state §8 re-cut (Lead scope extension)
- `tests/secret_guard_state.lua` §8 (R5) no longer re-implements the OLD `check_weapons`
  decision. It now pins the shipped contract: a local `weapon_decision(previous, speed)`
  mirror (`if type(speed) == "number" then has_weapon = speed > 0 end`) plus source-shape
  pins on `main.lua` for BOTH hands (readable number moves the flag; a secret/absent read
  keeps the previous value; the old `speed_offhand/speed_ranged or 0` shape must be gone)
  and the wrapper assertions are unchanged (a secret offhand degrades the whole
  `UnitAttackSpeed` read to nil; a readable 0 still clears; a readable speed counts).
- Evidence: `lua5.1 tests/secret_guard_state.lua` = **447 checks, 0 failures**; luacheck
  clean on the file. Mutation proof on a /tmp copy: reverting `check_weapons` to the old
  `or 0` shape fails exactly 2 pins (mutant exit 1). Only that test file was touched.
- Desk closed.
