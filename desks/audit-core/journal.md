# Audit-Core — Journal

## 2026-10-22 — Desk opened
- **Purpose:** RELEASE AUDIT, core engine (operator: no buggy release). Standard: in-game behavior only, no rulings, match the game. Era = spell ID, Anniversary = spell NAME, verified separately. Lib untouched (HU-29). HU-31 scope: lib path era/anniversary/titanforge; Retail/Forever own API.
- **Scope:** main.lua, bars.lua, compat.lua, swing_source.lua, diag.lua, utils.lua (+ core tests). LibLatencyMonitor vendored — off-limits, file findings.
- **Next step:** bench-read (done via prompt files), then sweep dispatcher/shapes/build points/lazy gates/nil-safety/clock/diag/init-equip-option-on/Retail-Forever, fix crash+wrong, pin everything.

## 2026-10-22 — Sweep + hardening landed, all green
- **Worked on:** Full per-hand frame-path sweep (GCD_OVER class): reachable paths already guarded by HU-22 (verified, no change); landed 6 unreachable-state hardenings (main.lua getters, bar_is_built full-chain, GCD_OVER vf/gcd_bar, hide/show hiding guards, handle_oor_hand db/frame, onupdate_common frame/d/db). Retracted 1 phantom (deadline "inert-standin" misspelling — byte-level od proved both lines already "inert-standin", no change). Verified clean: clock purity, dispatcher strip, CLEU indices, build points, Retail/Forever mapping, diag truth, secret surfaces. Pinned 19 new checks (bars_lazy §6 ×15, main_init §4b-iii ×4). Fixed 1 self-introduced luacheck unused-var. Line endings preserved.
- **Current state:** DONE. Report: bench/audit_core_2026-10-22.md. Suites: main_init 990, bars 935, bars_lazy 52, wiring 872/0, real_wire 882/0 (3 xfail HU-29), swing_source 149, diag 260, secret_guard 432, enemy 250/0, smoke 232/0. luacheck tree 2/0 floor. Mutations M1-M4 all red on /tmp/opencode copies (removed after). No blocker found.
- **Next step:** Orchestrator reconciles (full run.sh + in-client U1/U2 owned by validation). Nothing further owned by this desk.

## 2026-10-22 — [signal:done] core audit complete, no blocker
- Report filed: bench/audit_core_2026-10-22.md (skills-confirmation, file:line findings with severity, files changed, suite outputs, M1-M4 red proofs, UNVERIFIED U1-U3).
- 6 hardenings in main.lua/bars.lua + 19 pins; 1 phantom retracted with byte evidence. Tree green, floor held, copies removed.
