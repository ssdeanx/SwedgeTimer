# rogue-apl — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Add the rogue's missing APL rotation lines (the utility layer: Vanish,
  Preparation, Ambush, Garrote, Premeditation, Venom, Blood Fury, Gnome Eureka,
  Elune's Light, Poisoned Knife, Tricks of the Trade, Killing Spree, Hypersharp
  Weapon, and the builder-family rows Mutilate / Hemorrhage / Backstab / Ghostly
  Strike / Saber Slash) to `ST.ROGUE.practice_rotation`, and give the frozen guide
  engine (`rogue_guide.lua`) an arm for each so the practice scenario can ask for
  it and the guide can light it.
- **Scope:** `classes/rogue.lua`, `rogue_guide.lua`, `tests/rogue_state.lua`,
  `tests/rogue_guide_state.lua`. One new bench file. No git, no lint-config
  change, no TOC/version/option change, no other class touched.
- **Source of truth:** `bench/rotation_gap_vs_apl_2026-10-20.md` §3 (the rogue),
  re-verified against the fetched APL files (`wowsims/{classic,sod,tbc-new,
  forever,wotlk}` master, every `groupReference` expanded inline) and the sims'
  own spell data (`spell_data_auto_gen.go` / the per-ability `.go` files /
  `proto/rogue.proto`).
- **Flag convention (HU-13, orchestrator ruling 2026-10-20):** two flags.
  `live` = the line's read exists (in `compat.lua` today) and the line can be
  evaluated; `engine` = the frozen engine has an arm that can ask for it.
  A `live = false` row names the exact read it waits for in `needs`.
- **Prepull rows (HU-12):** the APL's pre-pull rows go into a per-class prepull
  table (`ST.ROGUE.practice_prepulls`), never the combat rotation. The hunter's
  shape is the model.
- **Next step:** write the rotation table's utility spine, the engine arms, the
  gather reads, the prepull table; pin them in the rogue suites; prove the
  mutations on `/tmp/opencode` copies; land the bench file.

## 2026-10-20 — The APL re-fetch (the gap analysis is the input, not the authority)
- **Worked on:** re-fetched all six rogue APL files (Era `combat_sinister_strike`
  + `..._iea`, SoD `P5_Saber`, TBC `swords`, Forever `default`, WotLK `combat` +
  `mutilate`) with every `groupReference` expanded inline, and read the sims' own
  spell data for the ids.
- **Current state:** the rotation table, the engine arms and the prepull table are
  NOT written yet — this entry records the re-fetch and the corrections it
  produced, so the next step starts from verified ground.
- **Decisions worth the trail:** the gap analysis's rogue section is wrong in
  **nine** places (the bench file §5 records them). The two that change the
  build: **1857 is Vanish rank 2 on the TBC and Forever clients** (not Cloak of
  Shadows — the gap's `cloak_of_shadows` row), and **14183 is Premeditation and
  1241584 is Mutilate rank 4 on the Forever client** (not Shadowstep — the
  gap's `shadowstep` row). The Forever APL's own `valueVariables` are CONSTANTS
  (`Use Stealth/Vanish for Damage` = true, `Use Ambush Opener` = false,
  `Use Backstab` = true), so every Forever row is client-evaluable — the
  "stealth for damage" state the gap assumed was missing is a constant, not a
  read.
- **Next step:** write the table, the arms, the gather reads and the prepull
  table.

## 2026-10-20 — [signal:done] The utility layer landed
- **Worked on:** wrote the rotation table's 24 utility rows (per-family ids +
  names, the family gates, the APL citations and the two HU-13 flags), the
  `ST.ROGUE.practice_prepulls` table, the engine's arms and rule order in
  `rogue_guide.lua`, the gather's per-family reads in `classes/rogue.lua`, the
  rotation-label names, the engine-facing slice filter, and the pre-pull wiring
  into the opener drill. The slice carries only the rows the engine can ACTUALLY
  ask for (`engine ~= false and live ~= false`): a builder row and a filed row
  are both buttons that can never be the right answer.
- **Current state:** `tests/rogue_state.lua` PASS (922 checks, +104),
  `tests/rogue_guide_state.lua` PASS (896 checks, +120), the full harness 41
  steps / 0 failed, luacheck 2 warnings / 0 errors (the floor; the four touched
  files: 0 warnings). Line endings held (the two addon files pure CRLF, the
  two test files pure LF). 24/24 mutations killed on `/tmp/opencode` copies
  (`python3 /tmp/opencode/mutations_rogue_apl.py`), including the four
  "buff-up line still prompts" mutants (the Master of Subtlety gate, the 58426
  gate, the Venom buff gate, the Garrote dot gate). Artifact:
  `bench/rogue_apl_utility_build_2026-10-20.md`.
- **Decisions worth the trail:** the gap analysis's rogue section is wrong in
  **nine** places — the two that change the build are **1857 = Vanish rank 2**
  (TBC and Forever) and **14183 = Premeditation / 1241584 = Mutilate rank 4**
  (Forever), so the "Cloak of Shadows" and "Shadowstep" rows it filed do not
  exist as such. The builder rows (Mutilate / Hemorrhage / Backstab / Saber
  Slash / Ghostly Strike) ship as **cited rows with `engine = false`**: the
  engine's single `builder` action already plays them, and a dedicated arm
  would be a second builder path. The `SOD` token stopped mapping onto the
  `ERA` slice — the SoD-only rows are gated on `SOD` alone, so the plain Era
  client never sees them. Four rows are `live = false` with the exact read
  filed: the Forever Vanish (the Garrote energy cost), the WotLK Hypersharp
  (the permanent enchant), the Forever Gnome Eureka (the AR split + buff +
  base cooldown) and the TBC Backstab (the APL's own const-false gate).
- **What this changes for the player:** the guide can now prompt the new
  utility actions (slot-less, like the shipped SnD/AR/BF/CB/HfB rows — the
  rotation label names them), the practice panel's button row grows by the
  engine-facing rows, and the opener drill grades the family's pre-pull row
  (the TBC's behaviour is unchanged). Stated in the bench file §5.
- **Open items for the operator / the next lane:** the divergences the engine's
  upkeep-first spine leaves against the literal APL order (bench §4); the
  guide's slot contract is still frozen (the new actions are slot-less); the
  ids are citations, and the class resolves its own ranks by NAME (in-client
  confirmation owed); the aura names 425096 / 462707 / 58426 are UNCONFIRMED
  (the ids are the APLs').
- **Next step:** the orchestrator validates. The next build lane is the one
  that gives the four filed rows their reads, and a `practice_ui` row-height
  pass if the panel's button strip needs a cap.
