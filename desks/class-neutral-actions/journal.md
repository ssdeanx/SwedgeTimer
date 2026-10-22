# Class Neutral Actions — Journal

## 2026-10-20 — Desk opened
- **Purpose:** the CLASS half of the NEUTRAL action feature — each class publishes
  the legitimate-but-ungraded action keys the shared practice engine treats as
  neutral instead of a mis-pick.
- **Scope:** `classes/paladin.lua`, `classes/warrior.lua`, `classes/rogue.lua`,
  `classes/shaman.lua` + `tests/neutral_actions_state.lua` + the three class
  suites. The engine half (`practice.lua`, `practice_ui.lua`) is the sibling
  desk `practice-neutral-actions`; the hunter and the druid are other lanes.
- **Next step:** read `bench/practice_neutral_actions_2026-10-20.md` (the engine
  contract), then work out each class's set from its OWN ability list.

## 2026-10-20 — The four sets landed
- **Worked on:** published `ST.<CLASS>.practice_neutral_actions` for the four
  classes I own — paladin flat `{sotc, aw, hpot, abacus, stop}`, warrior
  family-scoped `{FOREVER = {cleave}}`, rogue family-scoped
  `{ERA = {coldblood}, WRATH = {coldblood, shiv}, FOREVER = {shiv}}`, shaman flat
  and EMPTY. New cross-class suite `tests/neutral_actions_state.lua` (720
  checks): the publish shape, the exact set per family, the grading-integrity pin
  ("a rotation action can never be neutral"), the closed-list pin ("every panel
  key is classified: rotation / neutral / intentional mis-pick") and the engine's
  own reader. Per-class pins in the warrior / rogue / shaman suites (the
  paladin's pin lives in the new suite — `tests/paladin_state.lua` belongs to
  another lane).
- **Current state:** harness **41 steps, 0 failed**; luacheck **2 warnings / 0
  errors** (the standing floor, both pre-existing; my six touched files are
  0/0); mutation proofs **8/8 killed** on `/tmp/opencode/neutral/mut` copies;
  CRLF kept in the paladin / warrior / rogue class files, LF in the shaman's
  (it was already LF). The new suite is NOT in `tests/run.sh` (contested): the
  exact line is reported in the bench file §5.
- **Judgement calls (the orchestrator may rule otherwise):** the neutral set
  covers the class's PANEL vocabulary only — an ability the class has no practice
  key for (the paladin's heals, the warrior's potions, the shaman's heals) cannot
  be published, because publishing it would invent a key the class does not have
  ("do not invent a key"). The classes' own DRILL cast keys (the rogue's
  `evisc`/`ss`, the shaman's `weave_lb`/`weave_cl`, the druid's `shift`, the
  hunter's `aimed`) are the drills' own truth and are never neutral. The
  orchestrator's per-class name lists are wider than the shipped panels: most of
  those abilities have no key in the class file at all.
- **Next step:** the orchestrator dispatches the hunter's and the druid's sets
  (bench/class_neutral_actions_2026-10-20.md §3) to their lanes and adds the one
  `run.sh` line (§5).

## 2026-10-20 — [signal:done] The four class sets landed
- **Artifact:** `bench/class_neutral_actions_2026-10-20.md` (the sets, the
  reasoning, the hunter/druid proposals, the mutation table, the `run.sh` line
  the orchestrator must add). Harness 41/0, luacheck 2/0, 8/8 mutation proofs
  killed.
- **Signal:** `.signals/20261020T191500Z-done.json`.
