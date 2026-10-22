# hunter-final journal (filed by orchestrator — hunter has no write tools)

## 2026-10-19 — FINAL pre-production error sweep (ses_eaa5e01b4ffeZT9pz5zwdem9jU)

Read-only, 41 files. Prior corpus verified fixed, not re-reported.

### New findings (unguarded independent drivers — H2 bars fix does not cover)
- N1 HIGH: nextaction_ui.lua:425-427 self-driver calls gather/evaluate with no containment — wrap compute half in run_guarded pattern, degrade to … on failure.
- N2 MEDIUM: hud.lua:589-593 driver calls get_hud_state per icon, no pcall — per-icon guarded call, keep painting rest of row.
- N3 MEDIUM: rotationtext.lua:548-551 driver calls get_rotation_key, no pcall — pcall + hide on failure.
- N4 LOW: practice_ui.lua:665-669 session driver unguarded — guard compute half, freeze scoring for the tick.

### Verdict
VERDICT: FINDINGS 4. Fix lane dispatched (driver-containment).

## 2026-10-19 — driver-containment fix (N1-N4 + M1 pin)
- **Worked on:** wrapped all four sibling drivers in bars run_guarded discipline (one-time notice + self.bar_hook_errors counter + 25-throw quarantine, degrade unknown/hide never stale-confident, nil-safe): nextaction_ui.lua (N1 gather/evaluate guards), hud.lua (N2 per-icon guard via call_hud_provider helper preserving the wiring_check dynamic call site), rotationtext.lua (N3 decide_update pcall + hide), practice_ui.lua (N4 pr.tick + swing-grade + determine_rotation guards, scoring frozen on failure). Pins: N2 behavioral in tests/hud_state.lua, N3 behavioral in tests/rotationtext_state.lua, N4 behavioral in tests/practice_ui_state.lua, M1 filed-row grep-pin in tests/hunter_state.lua (hunter_ui.lua never reads hunter_weave_prog).
- **Current state:** harness 38 steps 0 failed, luacheck floor held at 2 warnings (pre-existing compat/main only; fixed 4 new pin warnings). Mutation proofs on /tmp/opencode copies: N2/N3/N4 guards removed -> pins FAIL; M1 probe string in hunter_ui.lua -> pin FAILs. Wiring check needed one rework (pcall(mod.get_hud_state,...) hides the call site; call_hud_provider helper restores it). Other lanes' uncommitted changes in the same test files left untouched.
- **Next step:** orchestrator validates (harness + luacheck + mutation proofs per lane standing rules).
