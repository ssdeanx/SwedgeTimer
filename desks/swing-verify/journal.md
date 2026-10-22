# swing-verify — Journal

## 2026-10-22 — Desk opened
- **Purpose:** verify/fix swing START/END/RESET per hand per family (brief_swing-verify_2026-10-22.md). Operator correction binding: ranged = FULL swing timer, 0.5s cast is part of cycle display.
- **Scope:** main.lua dispatcher/handlers/build points, bars.lua, classes/hunter.lua, hunter_ui.lua, swing_source.lua if needed, tests/real_wire_state.lua and/or tests/bars_lazy_state.lua legs only.
- **Next step:** bench-read done (journal lane table + display/engine/proctor reports + HU-22/25/27/28/29/31); now inspect current tree files.

## 2026-10-22 — Verify lane: reset + fallback legs landed, no product change
- **Worked on:** read journal lane table + display/engine/proctor reports + HU-22/25/27/28/29/31; inspected main.lua dispatcher/handlers/build points, bars.lua lazy gate, hunter sync, sandbox. Added legs to tests/real_wire_state.lua only: Era/Anniv/Titan mh+ranged reset (+Era oh reset, cross-hand isolation), anniv-nil fallback full lifecycle (START/STOP/full/re-START), live-engine suppression, converge-single-STOP, retail/forever inert, auto-repeat+spell gates, Forever mh/oh reset. Header extended.
- **Current state:** real_wire_state 671 checks 0 failures (3 xfail HU-29 stand: parry, extra-attacks, D2); was 482. luacheck 0/0 on the touched file. Mutations M1-M7 on /tmp/opencode copies all kill on the intended legs (M6 single-gate green by documented triple-cover design; M6' pair-off red); copies removed. Zero product-file diffs: behavior already holds, nothing to fix.
- **Next step:** orchestrator runs full run.sh + wires the run.sh line if a new step is wanted (no new file added; legs live in the existing real_wire step). Owed in-client: U1/U2/U3/U-H5 diag + visible bars after operator copy.

## 2026-10-22 — Operator correction (binding): cast window is Era + Anniversary
- **Correction recorded:** the 0.5s Auto Shot cast window is NOT TBC-only. Both classic-line clients share the mechanic; the vendored lib gates its CAST_START (lib:456) and FAILED_QUIET (lib:772) ranged arms on `isClassic` (lib:42, project == 2, Era only), so Anniversary never gets the window from the lib. That gating IS the gap under test (HU-29 rules Libs/ — lib stays untouched).
- **Verified in-tree (read-only grep, no edits):** lib:456 `if isClassic and spell and ranged_swing[spell]...` drives the UPDATE; lib:772 `if isClassic and spell and ranged_swing[spell] and unit.isShooting...` sets `GetTime() + 0.5 + autoShotCastTime`. Anniversary (project 5) fails the gate on both.
- **Impact on this lane's legs (checked, no change needed):** none of the new legs pins the Anniversary exclusion as desired behavior — reset/lifecycle legs ride the SUCCEEDED(75) path (no family gate, lib:600-606); the fallback driver (`maybe_drive_ranged_fallback`, main.lua:~1647-1727) carries NO family key (gates: spell 75, vendored-lib engine, not-mainline, has-hand, auto-repeat, stamp-silence, speed source) and is pinned serving BOTH families — fb-silence on anniv-nil, fb-suppress + fb-converge on era. The D2 xfail stays exactly where it is: the HU-29 marker for the lib gap, not a behavior pin.
- **Next step:** none — reading updated, legs already conform. Owed in-client items unchanged.
