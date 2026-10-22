# Paladin Practice Contract — Journal

## 2026-10-19 — Desk opened
- **Purpose:** the paladin's class side of the practice rotation work: the
  rotation table, the scenario step and the focused drills the shared
  practice engine consumes, plus the class-side feature gaps from
  `bench/class_features_drills_2026-10-19.md` §2 (A).
- **Scope:** `classes/paladin.lua`, `nextaction.lua`, `tests/paladin_state.lua`,
  `tests/nextaction_state.lua`. The shared engine (`practice.lua`,
  `practice_ui.lua`), the options, the TOCs and the guide UI belong to other
  lanes — this desk only publishes the class-side contract.
- **Next step:** none — the first session landed the contract (see below).

## 2026-10-19 — the paladin practice contract landed
- **Worked on:** built `ST.PALADIN.practice_rotation`,
  `ST.PALADIN.practice_scenario_step(self, ctx)` and
  `ST.PALADIN.practice_drills` (three graders: `paladin_fcfs_priority`,
  `paladin_prepull`, `paladin_judge_fit`) on top of the guide's own engine
  (`st.nextaction.evaluate` / `evaluate_fcfs`), so a practice session teaches
  what the guide teaches. Published `st.nextaction.FCFS_ORDERS` so the
  rotation table and the priority drill read the engine's own order tables
  instead of copying them. Re-verified §2 (A): the SoD seal-stacking /
  shockadin / wrath-like variants, the Holy-Power stack and the
  Templar/Sunlight auras are already WIRED (the variants lane); every other
  open row needs a file this lane does not own or a new id/probe, so it is
  filed with the reason.
- **Current state:** `tests/nextaction_state.lua` 613 checks PASS,
  `tests/paladin_state.lua` 643 checks PASS, luacheck 0 warnings on the four
  touched files, 12/12 mutations killed on `/tmp/opencode` copies, and a
  runtime probe drives the shipped practice sim end-to-end (CS → Judgement
  cue → the Blood twist work). Full harness: 41 steps, 3 reds — all of them
  the shared practice-registry lane's in-flight crossfire (the
  druid/warrior/shaman registry entries are commented out in `practice.lua`
  right now). The paladin/nextaction suites are green; this lane never
  touched `practice.lua`. Report: `bench/paladin_practice_contract_2026-10-19.md`.
- **Next step:** the shared engine lane registers the scenario under
  `paladin_rotation` and the three drills under their keys, and feeds the
  context the report's §5 lists (the minimum: `now`, `cooldowns`, the
  swing/GCD clocks). Open items and the two contract decisions (a hold
  answers nil; the canonical key space is the guide's, with the sim's
  spellings aliased) are in the report's §7.

## 2026-10-19 — [signal:done] the paladin practice contract landed
- `ST.PALADIN.practice_rotation`, `practice_scenario_step`, `practice_drills`
  (3 graders) + `st.nextaction.FCFS_ORDERS` published; 613 + 643 checks PASS,
  luacheck 0 on the four files, 12/12 mutations killed; §2 (A) re-verified
  (SoD variants + Holy Power WIRED, the rest filed with the file/id each
  needs). Report: `bench/paladin_practice_contract_2026-10-19.md`.
- Signal: `desks/paladin-practice-contract/.signals/20261019T211200Z.json`.
- Validation owner: orchestrator.
