# Clock lane (2026-10-22, desk `swing-clock`): raw GetTime → aligned clock

Scope: operator rule — GetTimePreciseSec is the main timer, GetTime the
fallback only; every raw `GetTime()` in shipped code → `st.api.get_time()`
(compat's own clock + OnUpdate elapsed args excepted). Untouched: Libs/,
docs/, tests/run.sh, TOCs, versions.

## Sweep result (comments blanked, code only)

The brief's candidate list (paladin/shaman/practice_progress_ui/ldb/
nextaction_ui/hunter files) was already clean — 0 code hits in all of
classes/*.lua, hunter_ui.lua, hunter_guide.lua, hunter_window.lua,
practice_progress_ui.lua, practice_progress.lua, ldb.lua, nextaction_ui.lua,
hud.lua, enemy_swing.lua, practice_ui.lua, diag.lua, utils.lua. The only raw
`GetTime()` calls in shipped code were main.lua x4, bars.lua x2, and the
swing_source fallback x1 (primary already `st.api.get_time()` — kept:
fallback-only use complies with the rule).

## Files + lines (current tree)

- bars.lua:684 (`onupdate_common`) + :1051 (`set_bar_texts`):
  `local t = GetTime()` → `local t = st.api.get_time()` (matches :664).
- main.lua:1170 (`note_swing_wire` diag stamp), :1218 (`SWING_TIMER_START`
  `bar.start`), :1274 (`SWING_TIMER_UPDATE` clamp/fill compare), :2334
  (`/st diag` age): `GetTime()` → `api.get_time()` (matches
  PLAYER_STOPPED_MOVING :1559 direct-call precedent; file upvalue
  `local api = st.api` at :62).
- tests/wiring_check.lua: ALLOWLIST_CLOCK drops the `main.lua` + `bars.lua`
  entries (stale = FAIL); hit-count comment corrected (9 measured → 3).
- NOT touched: swing_source.lua:78 (fallback-only `return GetTime()`);
  LibLatencyMonitor.lua:35 + LibGlobalCooldown.lua:136 (vendored, no st.api
  access — out of scope per brief, filed as note instead of change).

## Suite outputs (focused; full run.sh is the orchestrator's)

- wiring_check 870 checks / 0 failures / 3 accepted / 0 stale (baseline was
  876/0/3/0; −6 = the removed allowlist ok-lines). Clock rule: 3 hits, all
  allowlisted (swing_source fallback + 2 vendored libs).
- bars_state 885 PASS; main_init_state 975 PASS; real_wire_state 671 PASS
  (3 xfail HU-29); swing_source_state 149 PASS; bars_lazy_state 37/0;
  hunter_state 1744; hunter_guide_state 1970; hunter_window 213;
  guide_contract 1052; hud_state 817; smoke 232; enemy_swing 250;
  paladin_state 1234; shaman_state 1064 — 0 failures throughout.
- luacheck on touched files: 0 errors; the 2 warnings are the floor
  (main.lua:87 `table.pack` KEEP-ruled, pre-existing; bars + wiring clean).
- CRLF intact (main.lua), LF intact (bars.lua, wiring_check); no touched
  line over 150 chars (main.lua:2400 184 chars is pre-existing).

## Mutations (fresh /tmp/opencode copies, removed after)

- M1 revert bars.lua:684 → `GetTime()`: wiring_check 2 FAIL
  (`bars.lua:684 GetTime( outside compat.lua` + non-vacuity 4-vs-3).
- M2 revert main.lua:1218 → `GetTime()`: wiring_check 2 FAIL (same pair).
- M3 behavior (`st.api.get_time` parens dropped at bars:684): bars_state
  hard-errors in `onupdate_common` via tick (proves the call site is
  load-bearing, not decorative).

## Residuals / follow-ups (not this lane)

1. tests/wiring_check.lua check 3 `function_span` counts the WORD
   `function` even inside string literals (strings survive blank_comments).
   A `(type(x) == "function")` guard inside any main.lua handler span
   silently extends the span over later guard lines and flips guard verdicts
   (this lane's first pass proved it: 2 stale ACCEPTED, rc=1; re-cut to
   direct calls). Future clock-style edits in main.lua must use direct
   `api.get_time()` (the :1559 precedent), or the checker needs
   string-content blanking in span scans. No product impact today.
2. swing_source.lua:78 keeps raw `GetTime()` as the no-api fallback
   (allowlist entry retained with reason). If the operator wants zero raw
   calls tree-wide, that site needs a defined fallback constant.
3. In-client proof owed (operator copy + `/st diag`): unchanged from the
   wave — offline only.

## UNVERIFIED

- U1: in-client swing/diag behavior after copy (operator session).
- Full `bash tests/run.sh` on the final tree (orchestrator-owned).
