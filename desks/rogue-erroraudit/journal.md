# rogue-erroraudit — desk journal

## 2026-10-19 — audit complete (READ-ONLY)

- Worked on: read-only error-path audit of the 5 stable rogue surfaces per
  `bench/briefs/brief_rogue-erroraudit_2026-10-19.md` (rogue_guide.lua, 5
  compat probes, practice rogue drills, ROGUE options wiring, guide-state
  matrix). `classes/rogue.lua`, `diag.lua`, `config_presets.lua` read for
  orientation only, nothing graded (PROVISIONAL notes).
- Current state: filed `bench/rogue_erroraudit_2026-10-19.md` (new file;
  confirmed absent at lane start). 8 findings: 1 medium-low orchestrator
  decision (F3 cooldown unknown-as-idle), 4 lows (F1 NaN drill grades —
  proven via stub-harness execution, NaN marker→D, NaN window→early-guard
  bypass; F2 count passthrough; F4/F5 matrix gaps), 3 info/provisional
  (F6 unknown-family finishers, F7 negative TTD, F8 pool-band fallback vs
  in-flight defaults). H1–H6/M1–M7 closure verified for rogue paths on the
  stable side (H4/M4/M5/M6/M7 hold; H1/H5/H6 provider halves provisional).
  Validation: full harness 37/0 + luacheck 2/0 re-run in-lane; the five
  rogue-relevant suites green (206 + 1151 + 756 + 919 + 320 checks).
- Next step: DONE — orchestrator reconciles vs writer lanes (F3 accept vs
  distinguish; F8 defaults ownership; F1/F4/F5 hardening placement).
