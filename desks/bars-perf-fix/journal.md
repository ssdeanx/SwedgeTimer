# bars-perf-fix — Journal

## 2026-11-06 — Desk opened: swing-bar per-tick perf + verified rounding fix (WoW Forever focus)

- **Purpose:** implement the safe mechanical wins from the current-tree bar perf audit:
  A1 pass the tick's clock into `set_bar_texts` (no second `api.get_time()` pair per tick),
  A2 make the leading-edge spark a configured decoration (cache the geometry/colour key),
  A3 one fill write per tick instead of two, A4 fix the verified `simple_round` truncation
  (8 of 28 one-decimal weapon speeds displayed a tenth low; only the bar speed/timer texts
  use it). No visible behaviour change except the verified rounding bug.
- **Scope (write):** `bars.lua`, `utils.lua`, `tests/bars_state.lua`, `desks/bars-perf-fix/**`,
  one NEW bench report `bench/bars_perf_fix_2026-11-06.md`. No TOCs, no version fields
  (a rogue desk wrongly bumped 2.1.8 -> 2.2.0; the Lead owns the restore), no git.
- **Lane skills loaded:** bench-read, desk-open, desk-journal, signal-write (all present).
- **Priors read:** `desks/journal.md` (2026-11-06 dispatch + verified inputs),
  `bench/lessons.md`, `desks/perf-audit/journal.md` (§ perf census + the A1-A4 plan),
  `AGENTS.md`. NOTE: `bench/bars_perf_audit_2026-11-06.md` is a 17-line stub written by a
  rogue read-only desk (Lead-confirmed) — NOT the audit; do not rely on it.
- **Baseline verified this session:** `lua5.1 tests/bars_state.lua` = 1261 checks green;
  `bash tests/run.sh` = 57 steps / 0 failed; luacheck 2/0. bars.lua/utils.lua LF.
- **Next step:** red-first pins, then implement.

## 2026-11-06 — [signal:done] A1+A2+A3+A4 landed, red-first pins + 4 mutation kills

- **Worked on:** (A1) `set_bar_texts(hand, now)` + all three tick call sites pass the
  tick clock (`bars.lua:1629`, call sites 1152/1166/1294); non-tick callers unchanged.
  (A2) spark decoration cache keyed on spark_width/spark_color/bar height, live-db read
  every tick, `show_spark` off invalidates the cache; per tick Show/Hide only
  (`bars.lua:1181-1234`). (A3) implemented as the dispatch's permitted RESTRUCTURE
  variant: the duplicate top-of-tick fill write is deleted, the 2026-10-28 final
  re-assert is the tick's single fill write and stays structurally last
  (`bars.lua:1341-1362`); 12c2/12c3 were NOT modified and stay green (no dirty flag was
  needed). (A4) `simple_round` = `floor(num/step + 0.5 + 1e-9)*step` with the WHY comment
  (`utils.lua:21-36`); 8 of 28 speeds fixed + half-up timers. `tests/bars_state.lua`:
  new §2a (44 checks) + fixture call counters (`time_precise_reads`/`time_reads`,
  per-region `size/point/clear/width/texcoord/color` counters) + one stale pre-existing
  pin corrected (1.95 s timer: "1.9" -> "2.0", with reason).
- **Current state:** `lua5.1 tests/bars_state.lua` = **1305 checks PASS** (baseline was
  1261); luacheck on changed files 0/0; LF preserved; `luac5.1 -p` clean. Red-first: the
  new pins failed 20/1305 before the fixes (exactly the intended ones). Mutations on
  fresh `/tmp` copies: M1 (revert simple_round) -> 10 fails; M2 (per-tick spark rebuild)
  -> 2 fails; M3 (re-add duplicate fill write) -> 4 fails, 12c2/12c3 green; M4 (stale/zero
  clock from the tick) -> 4 fails incl. the text value pin; M4b (A1 fully reverted) -> 4
  fails (both count pins). No in-client profiling claimed. Report:
  `bench/bars_perf_fix_2026-11-06.md`. No version field, TOC, run.sh or git touched.
- **Crossfire:** `bash tests/run.sh` oscillated 1-3 failures during the wave; final run
  57 steps / 2 failed = `engine_matrix_state.lua` (swing_source payload, other desk) and
  `wiring_check.lua` (main.lua swing-guard accepted-defect ledger, display-fix). Neither
  suite loads `bars.lua`; the two that load `utils.lua` never call `simple_round`. Full
  green must be re-certified by the Lead after all desks land.
- **Next step:** Lead re-runs `bash tests/run.sh` after display-fix/powerbar-fix land and
  restores the version fields (rogue 2.2.0 -> 2.1.8); if the rounding fix is visible in
  the operator's in-client pass, expect "1.4"/"2.8" etc. where it used to show a tenth
  low. Optional follow-ups listed in the report (`update_zones` clock, ldb clock, HUD/
  nextaction/hunter throttle).
