# Desk `swing-clock` — journal

Seat: clock lane, session ses_e9ae0e644ffeFG8GGPpjzoSC3g.
Brief: operator rule GetTimePreciseSec = main timer, GetTime = fallback only.
Scope: raw `GetTime()` in shipped code → `st.api.get_time()`; Libs/docs/tests-run.sh/TOCs out.

## Worked on
- 2026-10-22: bench-read manual pass (central journal lane table through the
  clock-dispatch row; HU-22 LAZY-BARS row; bench/swing_display_2026-10-22.md;
  bench/swing_engine_fix_2026-10-22.md). No new bench material since dispatch
  except the queued CLEU-parity row (runs after this lane, untouched).
- Product-wide `GetTime` sweep (comments blanked via lua): the orchestrator's
  candidate list (paladin/shaman/practice_progress_ui/ldb/nextaction_ui/hunter
  files) is already clean — 0 code hits in every one of those files. The only
  raw `GetTime()` calls in shipped code are main.lua x4 (1170/1218/1274/2334),
  bars.lua x2 (684/1051), swing_source.lua x1 (fallback inside `now()`, primary
  is already `st.api.get_time()` — kept, fallback-only is the rule).
  LibLatencyMonitor.lua:35 + LibGlobalCooldown.lua:136 are vendored/out of
  scope per brief (noted, not touched).
- tests/wiring_check.lua check 5 pins the old shape: ALLOWLIST_CLOCK allows
  raw GetTime in main/bars/swing_source/compat/2 libs (baseline 876 checks,
  0 failures, 9 hits). Removing main/bars hits makes those two entries stale
  (stale = FAIL), so the allowlist entries go with the code change.

## Current state (LANDED 2026-10-22)
- edits: bars.lua 684/1051 → `st.api.get_time()` (matches :664); main.lua
  1170/1218/1274/2334 → direct `api.get_time()` (matches PLAYER_STOPPED_MOVING
  :1559 precedent). swing_source.lua:78 untouched (fallback-only, compliant).
  LibLatencyMonitor.lua:35 + LibGlobalCooldown.lua:136 untouched (vendored,
  out of scope — file as note). wiring_check.lua ALLOWLIST_CLOCK drops
  main.lua + bars.lua entries + hit-count comment 11→3.
- deviation + recovery: first pass used the guarded
  `(type(get_time) == "function")` idiom; wiring_check check 3 flipped
  START/UPDATE to "guarded in handler" (2 stale ACCEPTED, rc=1). Root cause:
  function_span counts the WORD `function` even inside the string literal,
  extending the span over real guard lines. Re-cut to direct calls; spans
  byte-identical to baseline apart from the callee name. CHECKER FRAGILITY
  (for orchestrator): no `(type(x) == "function")` literal may appear inside
  any main.lua handler span — it silently extends the span. Filed in bench
  report §5.
- validation: wiring_check 870/0/3/0; bars_state 885; main_init 975;
  real_wire 671+3xfail; swing_source 149; bars_lazy 37; hunter 1744/1970/213;
  guide_contract 1052; hud 817; smoke 232; enemy 250; paladin 1234; shaman
  1064 — all 0 failures. luacheck touched files: floor holds (main 87:10
  table.pack pre-existing; bars + wiring_check clean). M1/M2/M3 kill on
  /tmp/opencode copies (removed after).

## Next step
- DONE. Bench report bench/clock_align_2026-10-22.md filed; done signal
  written. Reconcile back to orchestrator (full run.sh stays orchestrator).
