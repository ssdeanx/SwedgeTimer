# druid-hold-ride — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the deep-audit's H1 (HIGH): the druid is the only class of six
  that turns the guide's HOLD into a synthetic ACTION. The bear chain's "RIDE"
  (a queued Maul) means PRESS NOTHING, but `classes/druid.lua`'s `druid_expected`
  mapped it to a "ride" key, so the engine graded an idle as a miss (F) and a
  press of the rendered "ride" button as an S with points — and the class's own
  priority drill banked a false mis-pick for every real pick.
- **Scope:** `classes/druid.lua`, `druid_guide.lua`, `tests/druid_state.lua`,
  `tests/druid_guide_state.lua`. Nothing else.
- **Next step:** split the guide's hold texts into the spell-naming holds (the
  action to press) and the one press-nothing hold ("RIDE"); state the
  press-nothing hold as `{ action = nil, hold = true, reason = "RIDE" }`; make
  the priority drill skip hold steps; pin both halves.

## 2026-10-20 — H1 closed (the press-nothing hold split, pinned, mutation-proven)
- **Worked on:** `classes/druid.lua` (the hold vocabulary split into
  `ST.DRUID.PRACTICE_HOLD_KEYS` / `ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING`,
  `druid_expected` answering no action for the press-nothing hold, the scenario
  step stating `{ action = nil, hold = true, reason = "RIDE" }`, the priority drill
  skipping the hold step), `druid_guide.lua` (comments only: RIDE is the
  press-nothing hold), `tests/druid_state.lua` (§41: the RIDE hold is never an
  action, the engine's three states, the drill banks no mis-pick, no "ride" button
  in the published vocabulary, a spell-naming hold still grades as that spell) and
  `tests/druid_guide_state.lua` (§21: the guide's hold vocabulary is closed).
- **Current state:** harness **41 steps, 0 failed**; luacheck **2 warnings / 0
  errors** (the floor, unchanged); `druid_state` 1291 and `druid_guide_state`
  95944 green; **5/5 mutants killed** on `/tmp/opencode/druid-hold-mut`
  (`/tmp/opencode/druid_hold_mutations.py`). Report:
  `bench/druid_hold_ride_2026-10-20.md`.
- **Next step:** the orchestrator (a) adds the lane row to `desks/journal.md` with
  the dispatch's session id, (b) owes the CHANGELOG line, (c) owns the in-client
  confirmation (a queued Maul in bear form: no "ride" button, a cast during the
  hold grades F, doing nothing grades correct-with-no-points).
- **Note for the next session:** `bench/class_hold_statements_2026-10-20.md` §2
  claims the druid has no hold concept — that claim is the defect's origin and is
  now superseded (the new bench file is the pointer; the old file was not
  overwritten).

## 2026-10-20 — [signal:done] H1 closed
- `desks/druid-hold-ride/.signals/2026-10-20T13-52-00Z.json` (execution/done,
  run_id `druid-hold-ride-2026-10-20`). Artifacts on the bench:
  `bench/druid_hold_ride_2026-10-20.md`. Harness 41/0, luacheck 2/0, 5/5 mutants
  killed.
