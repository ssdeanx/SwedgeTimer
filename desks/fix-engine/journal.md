# fix-engine — Journal

## 2026-10-19 — Desk opened
- **Purpose:** writer lane for the engine/dispatch/range half of the hunter audit (`bench/briefs/brief_fix-engine-dispatch_2026-10-19.md`).
- **Scope:** `main.lua`, `bars.lua`, `swing_source.lua`, `enemy_swing.lua` + their four `tests/*_state.lua` suites. H1/H2/H3/H5/H6/M1/M2/M7 only. Explicitly out: weave/nextaction/compat/classes/hud/TOCs/version/CHANGELOG.
- **Next step:** bench-read done (journal + hunter/proctor audits + lessons + hands-up); implement H/M items, extend pins, run `bash tests/run.sh`, mutation-prove each new pin on `/tmp/opencode` copies, append end-of-session entry + done signal.

## 2026-10-19 — Lane complete (H1/H2/H3/H5/H6/M1/M2/M7)
- **Worked on:** all eight items from the brief, no files outside the declared scope.
  - H1 `main.lua:19-29` stub returns `nil, nil, nil`; `init_timers` (`main.lua:630-646`) sets per-hand `engine_dead` instead of inventing a 1 s cycle; `bars.lua:579-590` + `bars.lua:916-925` render dim + "engine offline", and nil-speed paths in `set_bar_texts`/`set_deadzone_width`/`set_gcd_marker_positions`/`onupdate_common` no longer do nil maths.
  - H2 `bars.lua:517-556` `run_guarded` isolates the class hook (`bars.lua:681`) and every zone (`bars.lua:566`): first throw per site prints once, all throws counted in `ST.bar_hook_errors`, site quarantined after 25.
  - H3 `main.lua:791-816` `callback_event_handler` pcalls the per-event handler, counts per event, one notice per event.
  - H5 `swing_source.lua:97-141, 206/211/233/238/244/271, 277, 314` reject + speed-read-keep counters, one-time sustained-reject chat notice; surfaced through `main.lua:1662-1690 print_runtime_diag` (called from `/st diag`, `main.lua:1729`) via `diagnostic_text`.
  - H6 `main.lua:1113-1150` all seven thin UNIT_SPELLCAST_* handlers early-return pre-init; the callee `ST:class_on_spellcast_event` (`main.lua:1755`) has no init guard (verified read).
  - M1 `main.lua:1432-1510` bounded retry (3 attempts, 0.05/0.1/0.2 s backoff) before the existing one-time session-disable; consecutive counter resets on success.
  - M2 `main.lua:1447-1456` nil-checker re-arm capped at 100 laps, folds into `lrc_unavailable` + `rf_checker_exhausted` + one-time notice.
  - M7 `enemy_swing.lua:119-156, 355, 452-495, 574` cycle provenance (`live`/`cached`/`fallback`): fallback cycles dim the fill and show the target name, measured cycles restore red + countdown; a nil clock hides the bar instead of freezing.
- **Current state:** `bash tests/run.sh` → **35 steps, 0 failed** (confirmed twice: before and after the sibling lanes' transient reds). Our four suites 329/761/108/250 checks 0 failures. Mutation proofs (guard-stripped /tmp/opencode copies) bite for all eight items: H1 main+bars, H2 bars (first throw escapes), H3 main, H6 main, M1 main (3×fail list), M2 main, H5 swing_source (counter), M7 enemy_swing (name/dim). Scope clean: no weave/nextaction/compat/classes/hud/TOC/version/CHANGELOG edits. Cross-lane observation only: twice the shared harness flapped red while the fix-guides-weave lane's files were half-landed (`tests/weave_state.lua`, then `tests/paladin_state.lua`); both self-resolved without any edit from this lane, so no hands-up was raised. Note for the orchestrator: a green full run is only achievable at a sibling-quiescent moment; our in-scope suites are green in every observed tree state.
- **Next step:** orchestrator validation (file:line + harness + mutation proofs above); reconcile against fix-guides-weave (no shared files). In-client remains the real check for the "engine offline" render and the quarantined-hook notice.
