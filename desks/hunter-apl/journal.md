# hunter-apl — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Build the hunter's missing APL rotation lines (the utility layer:
  the Serpent Sting upkeep, the Aspect of the Viper / Hawk / Falcon /
  Dragonhawk swaps, the Kill Shot execute, and the APL's melee/trap rows) into
  `ST.HUNTER.PRACTICE_ROTATIONS` with the APL priority citations, the per-family
  spell id + name, the family gates and the `live` flags — and fix the two wrong
  ids the gap analysis found (`explosive`, `kill_shot`).
- **Scope:** `classes/hunter.lua`, `hunter_guide.lua`, `hunter_ui.lua`,
  `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`. One new bench file.
  No git, no lint-config change, no TOC/version/option change.
- **Source of truth:** `bench/rotation_gap_vs_apl_2026-10-20.md` §2 (the hunter),
  re-verified against the fetched APL files (`wowsims/{classic,sod,tbc-new,
  forever,wotlk}` master) and the sims' own spell data.
- **Next step:** read the gap file's hunter section + the shipped rotation
  table, re-verify every id/index against the APL JSON, write the table, pin
  it in the hunter suites, prove the mutations on `/tmp/opencode` copies.

## 2026-10-20 — The utility spine landed
- **Worked on:** re-fetched all six hunter APL files and expanded every group
  inline, so the priority indices and the pre-pull offsets came from the files,
  not from the gap analysis; named every id on its own client page (Wowhead,
  per version) and against the sims' own data (`spell_data_auto_gen.go`, the
  per-ability `.go` files, `proto/hunter.proto`). Wrote the rotation table's
  spine rows (Era 2, SoD 8, TBC 2, Wrath 7, Forever 9), fixed the wrong ids
  (kill shot 53351 → 61006, explosive 53301 → 60053) plus two family-split ids
  the gap analysis missed (TBC steady 56641 → 34120 — 56641 does not exist on
  the TBC client; Forever steady 56641 → spell-less — the Forever client has no
  Steady Shot at all), and gave every row the same shape (action, label,
  spell_id + spell_name, families, live, engine, needs, source).
- **Current state:** `tests/hunter_guide_state.lua` PASS (1747 checks),
  `tests/hunter_state.lua` PASS (1158 checks), luacheck on
  `classes/hunter.lua` 0/0. The full harness is 41 steps / 0 failed and the
  tree's luacheck floor is 2 warnings / 0 errors (both pre-existing, in
  untouched files). 11/11 mutations killed on `/tmp/opencode` copies
  (`python3 /tmp/opencode/mutations_hunter_apl.py` reproduces them).
  Artifact: `bench/hunter_apl_utility_build_2026-10-20.md`.
- **Decisions worth the trail:** the hunter needs TWO flags where the warrior
  needs one — `live` = the line's READ exists in the shipped tree today (the
  task's wording), `engine = false` = the frozen guide engine has no arm for
  the line on this family. The Serpent and Viper rows have their reads but no
  engine rule; the aspect rows have neither. A spine row must never reach the
  engine: without the `engine` guard the Era scenario's expected action flips
  from `multi` to `rapid_fire` (pinned, and proved by mutation 11).
  `practice_rotation_for` returns the ENGINE-FACING rows only: the practice
  row is a fixed 74 px strip with four buttons per row, so the full thirteen-row
  Wrath spine would push a third button row out of the strip — and
  `practice_ui.lua` is out of this lane's scope (filed, not fixed).
  The SoD's Serpent Sting and the Forever's Hawk stay in the prepull table
  (HU-12): they are pre-pull rows in their APLs, not spell rows.
- **New findings for the bench:** the gap analysis's hunter section is wrong in
  five places (the kill-shot ids, the Era Arcane Shot, the Aspect of the Wild's
  name, the Forever Hawk's family, the Era pre-pull's name) — the corrections
  and their citations are in the bench file §5.
- **Next step:** the orchestrator validates. The next build lane is the one
  that gives the spine rows their engine rules and their reads (the `needs`
  field names each one), and the `practice_ui` row-height pass that would let
  the panel show the full spine.
