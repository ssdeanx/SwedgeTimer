# warrior-apl — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Build the warrior's missing APL rotation lines (the operator's
  named set: Charge, Battle Stance, Berserker Stance, Bloodrage, and the rest
  of the utility layer) into `ST.WARRIOR.practice_rotation`, with the APL
  priority citations, the per-family spell ids + names, the family gates and
  the `live` flags — and the APL's PRE-PULL rows into a per-class prepull
  table (the `ST.HUNTER.PRACTICE_PREPULLS` shape), per the operator's HU-12
  ruling (rotation table = the APL's spell rows; prepull table = the APL's
  pre-pull rows).
- **Scope:** `classes/warrior.lua`, `warrior_guide.lua`,
  `tests/warrior_state.lua`, `tests/warrior_guide_state.lua` only. One new
  bench file. No git, no lint-config change, no TOC/version/option change.
- **Source of truth:** `bench/rotation_gap_vs_apl_2026-10-20.md` section 1
  (the warrior), re-verified against the fetched APL files
  (`wowsims/{classic,sod,tbc-new,forever,wotlk}` master).
- **Next step:** read the gap file's warrior section + the shipped rotation
  table, re-verify every id/index against the APL JSON, write the table +
  the prepull table, pin them in the warrior suites, prove the mutations on
  `/tmp/opencode` copies.

## 2026-10-20 — The utility spine + the pre-pull table landed
- **Worked on:** re-fetched all seven warrior APL files (`wowsims/{classic,sod,
  tbc-new,forever,wotlk}` master) and expanded every group inline, so the
  priority indices and the pre-pull offsets came from the files, not from the
  gap analysis. Confirmed every id's NAME from the sims' own data
  (`spell_data_auto_gen.go`, the per-ability `.go` files, `proto/warrior.proto`,
  `sim/core/racials.go`). Wrote `ST.WARRIOR.practice_rotation`'s second block
  (13 utility lines: the stances, the shout, Bloodrage, Recklessness, Death
  Wish, Sweeping Strikes, Thunder Clap, Shattering Throw, Heroic Throw,
  Berserker Rage, Blood Fury) and the new `ST.WARRIOR.PRACTICE_PREPULLS`
  (SOD/TBC/FOREVER/WRATH) in `classes/warrior.lua`; corrected the shipped
  `hamstring` row's 18499 citation; pinned both in `tests/warrior_state.lua`
  (new section 38, +334 checks).
- **Current state:** `bash tests/run.sh` → 41 steps / 0 failed, luacheck 2
  warnings / 0 errors (the two pre-existing ones, in untouched files).
  `tests/warrior_state.lua` PASS (1564 checks), `tests/warrior_guide_state.lua`
  PASS (1728, unchanged - the guide did not change). 11/11 mutations killed
  on `/tmp/opencode` copies (`/tmp/opencode/mut_warrior_apl.py`).
  Artifact: `bench/warrior_apl_utility_build_2026-10-20.md`.
- **Decisions worth the trail:** every utility line ships `live = false` and
  the guide has no rule for any of them, so nothing prompts (the "a line that
  no engine action can produce must not prompt" rule) - the test pins the
  guide's own twelve-key vocabulary, so a future rule forces a conscious
  `live` flip. Charge and Intercept live ONLY in the pre-pull table (HU-12).
  The gap analysis contradicts itself on the racials (§1.3 lists blood_fury as
  missing, §1.4 says the racials group is correctly absent): the Era APL's
  [7] is a real top-level row, the TBC/Forever appearances are the sim's
  pop-everything group, so the line is gated to the Era build alone and the
  reason is written into its source.
- **New findings for the bench:** `12292` is a family-split id the gap
  analysis missed (Death Wish on TBC, Sweeping Strikes on Forever); the SoD
  pre-pull carries no Blood Fury (the gap analysis says it does); the gap
  analysis listed only the WotLK fury pre-pull (the arms one differs); and its
  missing-line table omits the SoD Gladiator Stance (412513) that its own APL
  listing carries - added here, cited to `proto/warrior.proto:131` and
  `sim/warrior/stances.go:212`.
- **Next step:** the orchestrator validates. The next build lane is the one
  that gives each utility line its RULE and its READ (the `needs` field names
  both); nothing here is engine-playable yet, by design.

