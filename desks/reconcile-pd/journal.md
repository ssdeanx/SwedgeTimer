# Reconcile PD — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Reconcile the six landed per-class practice/designer lanes (all done, zero running). Close the 3 mechanical reds.
- **Scope:** `tests/options_load_state.lua` (6 SODOPT pins), `tests/designmode_state.lua` (registry count + pips), `practice_ui.lua` (4 dead-hook callers). No class files, no guides/engines/HUD/bars/compat/main/hud/diag/guide_contract/run.sh/TOCs/versions/README/CHANGELOG/docs; no git; no lint-config changes.
- **Next step:** Flip SODOPT pins to presence, update count pins, wire ST.DRUID/ST.HUNTER callers ST-qualified, harness 38/0 + mutations.

## 2026-10-19 — Reconcile landed, harness 38/0 [signal:done]
- **Worked on:** 6 SODOPT flips (shaman practice_toggle/weapon_speed/reset_position presence; shaman/weave consumers presence; SHAMAN post_init builds session); design count 9→11 + pips 10→12; hunter H.→ST.HUNTER qualified (wiring); druid drill routing (use_druid_drill ST.DRUID-qualified + HINTs + start/tick/cast/summary/end + stop/start_fight/toggle_fight/tick/sync/info/timer/button/hint/result/panel branches, all session-gated, no new player_class==DRUID literal so druid_state 2-branch pin holds).
- **Current state:** `bash tests/run.sh` 38/0, luacheck 2/0 floor (compat/main KEEP). Mutations on /tmp/opencode copies all kill: M1 SODOPT absence FAIL, M2 count 9 FAIL, M3 pips 10 FAIL, M4 hunter H. dead-hook FAIL, M5 shift delete FAIL, M6 summary delete FAIL, M7 end delete-all FAIL. CRLF kept (practice_ui), LF kept (tests), touched-lines only, nil-safe, no default-visible change (druid only when use_druid_drill).
- **Next step:** orchestrator validation + central ledger reconcile-pd running→done. Owed in-client: druid powershift feel, shaman Weave page, designer overlays.
