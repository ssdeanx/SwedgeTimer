# hunter-deep journal (filed by orchestrator — hunter has no write tools)

## 2026-10-19 — FINAL deep enterprise audit (ses_eaa98586ecffepElQEB3S89Vj3M)

Full report: `bench/deep_audit_2026-10-19.md` (ranked findings F1–F14, per-feature call-path
trace table, per-client API truth table, justified exceptions, positive findings, limitations).

VERDICT: FINDINGS 14 — 2 material (F1 diag error-ring never installed → "errors none" is a
false negative; F2 PLAYER_TARGET_SET_ATTACKING handler body unreachable because `has_oh` is
never true), 4 medium (F3 print fallback, F4 TBC name-vs-id resolution, F5 write-only counter,
F6 base-TOC load-throw hazard), 8 low/smell.

Orchestrator independently confirmed F1 (no caller for `install_error_handler` in the tree) and
F2 (`has_oh` assigned false at main.lua:408, never true) and F6 (base TOC line 1 advertises
120100/120105/16001 while line 18 ships LibClassicSwingTimerAPI).

Mid-edit at audit time (foundation lane owned): practice_progress.lua, practice_stats.lua,
config_presets.lua, tests/run.sh, the 7 TOCs.

Owed: a cross-client truth pass against wow-ui-source (the auditor could not read it —
permission.rejected; the API table is cited from compat.lua instead).
