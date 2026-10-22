# Paladin Scenario — Journal

## 2026-10-20 — Desk opened
- **Purpose:** the paladin's practice/scenario surface — the rotation scenario's
  own decision, the rotation table's citations, the running order's slice, and
  the APL layer (HU-12's ruling).
- **Scope:** `classes/paladin.lua`, `nextaction.lua`, `tests/paladin_state.lua`,
  `tests/guide_contract.lua` (paladin section only).
- **Next step:** read `bench/rotation_gap_vs_apl_2026-10-20.md` §6 and the
  audit brief; fix F1 (the ctx builder), cite the table (F6), make the running
  order reachable (F8), add the missing APL rows.

## 2026-10-20 — F1/F6/F8 + the APL layer landed
- **Worked on:** the class's own ctx builder now falls back to the live
  gather's inputs when the session state cannot answer the timing (the sim
  shape is untouched) — that is the CRITICAL: the paladin's scenario graded
  nothing in-game (ten UNKNOWN steps, no attempt, no XP). Every rotation row
  now carries its APL citation, its family gate and its family's spell id
  (TBC by name). `practice_rotation_for` takes an OPTIONAL order id and answers
  the running order's slice; the live gather publishes that order, so the three
  SoD variants are reachable. The WotLK APL's Hand of Reckoning (67485) and
  Hammer of Wrath (48806) ride the rotation table as cited, WRATH-gated rows;
  the APL's pre-pull rows (Sanctity Aura 20218, 10301) went to the pre-pull
  table (HU-12), never to the combat rotation.
- **Current state:** harness 41 steps / 0 failed; luacheck 2 warnings / 0
  errors (the floor; the three touched files are clean); paladin_state 880
  checks, guide_contract 1044; 10/10 mutation proofs killed on /tmp/opencode
  copies. Report: `bench/paladin_scenario_surface_2026-10-20.md`.
- **Boundary (deliberate):** `nextaction.lua` is UNCHANGED — the engine's FCFS
  orders stay the shipped prompt order. Re-cutting the Wrath order to the WotLK
  APL is operator-visible and cannot be done safely in this scope (the APL's
  judgement row is Judgement of Light 53408, a different spell from the
  class's `judge` key; and the guide has no slot for Hand of Reckoning, so a
  prompt would light no icon and read as a hold). The two rows therefore ride
  the rotation table as the APL layer, reachable in the WotLK slice.
- **Open for the operator:** HU-13 (the `live`/`engine` flag convention across
  the six classes) is still open — this lane did NOT introduce a new flag
  convention (the rows use `families` + a prose `note`, the rogue/druid shape).
  The Wrath order vs the WotLK APL (bench §6.5) and the `sotc` label without a
  row (bench §6.3) are filed in the report.
- **Next step:** the operator/validation owner runs the harness and the luacheck
  floor on the landed tree; the in-client check that the paladin's scenario now
  shows a decided step (and not "unknown") belongs to the owner's TESTING
  session.

## 2026-10-20 — [signal:done] the paladin's scenario surface is landed
- F1 (CRITICAL) closed: the live-shaped ctx decides (the scenario is no longer
  UNKNOWN in-game). F6: every rotation row is cited. F8: the running order's
  slice is reachable (all six orders). The WotLK APL's Hand of Reckoning and
  Hammer of Wrath rows are in, family-gated and cited; the APL's pre-pull rows
  are in the pre-pull table, not the combat rotation.
- Harness 41/0, luacheck 2/0 (the floor), paladin_state 880, guide_contract
  1044, 10/10 mutations killed. Report:
  `bench/paladin_scenario_surface_2026-10-20.md`.

