# Brief: bars start, end, and reset perfectly (2026-10-22)

## Operator correction (binding)
The ranged bar is the FULL swing timer on every client — not "the .5s
window". The hidden-cast portion is part of the cycle display, never the
whole bar. Ranged, mainhand, and offhand must each sweep their full cycle,
stop at expiry, and reset on the next swing. Anything less is not done.

## Objective
Prove — then guarantee — end-to-end START → UPDATE → STOP → full-state for
all three hands: classic_era, classic_anniversary, titanforge via the
vendored lib path (v32, untouched); Retail/Forever via their own API
(inert stand-in / swing_source). No protected calls, 2.1.1, HU-22/HU-23
stand.

## Context (read via @bench-read, journals first)
- desks/journal.md lane table; bench/swing_display_2026-10-22.md (display
  contract + U1-U5); bench/swing_engine_fix_2026-10-22.md (bring_up_hand,
  dispatcher, U-oweds); bench/proctor_swing_gap_2026-10-22.md (Pins 1-3,
  now landed); HU-25/HU-27/HU-28/HU-29/HU-31.
- Full harness is green (48/0, luacheck 2/0) — green suites are the floor,
  not the proof. Your job is the behavior the suites don't yet pin.

## What perfect means (assert every one through the real lib + real v7)
1. mh: CLEU SWING_DAMAGE → START with UnitAttackSpeed; bar sweeps to zero;
   expiry → STOP → full state; next swing re-STARTs (no stale freeze).
2. oh: same, incl. offhand-flag routing on SWING_MISSED (overkill slot).
3. ranged: SUCCEEDED(75)+autorepeat → START with UnitRangedDamage; full
   sweep including the TBC 0.5s cast portion; STOP at expiry; no double-drive
   when lib + fallback could both fire (both gate outcomes).
4. No cross-talk: a ranged cycle never moves steady/auto displays wrongly and
   vice versa (shared-state provenance holds under reset/equip/option paths).

## Write scope (nothing else)
main.lua dispatcher/handlers/build points, bars.lua, classes/hunter.lua,
hunter_ui.lua, swing_source.lua if the Forever joint needs it, plus legs in
tests/real_wire_state.lua and/or tests/bars_lazy_state.lua for every assert
above that lacks one. Do NOT touch run.sh, vendored Libs, TOCs, versions,
options (beyond what exists).

## Validation
Focused suites only + luacheck on touched files; red-first mutations on
/tmp/opencode copies (each new leg fails with the defect restored, removed
after). Full run.sh is the orchestrator's. Report skills-confirmation,
per-hand verdicts, files+lines, outputs, mutations, UNVERIFIED closers.
