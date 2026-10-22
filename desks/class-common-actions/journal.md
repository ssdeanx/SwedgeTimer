# Class Common Actions — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the gap the class lane filed — make the practice panel
  actually OFFER the common abilities (a heal, a shield, food, a potion, a
  movement spell) so a legitimate mid-practice press is graded NEUTRAL instead of
  a mis-pick. Each class gains the common abilities in its OWN practice-panel
  ability list (real spell id + icon per family) and publishes them as neutral.
- **Scope:** `classes/paladin.lua`, `classes/warrior.lua`, `classes/rogue.lua`,
  `classes/shaman.lua` + `tests/neutral_actions_state.lua` +
  `tests/warrior_state.lua` + `tests/rogue_state.lua` + `tests/shaman_state.lua`.
  The engine half (`practice.lua`, `practice_ui.lua`) is the sibling desk
  `practice-neutral-actions` and is OUT OF SCOPE. The hunter and the druid are
  sibling lanes — their sets/abilities are FILED in the report, not built here.
- **Context:** the engine contract is `bench/practice_neutral_actions_2026-10-20.md`
  (the accessor `H.practice_neutral_actions`, the `neutral` outcome, the UI
  wording). The class half and the filed gap are
  `bench/class_neutral_actions_2026-10-20.md` (§2 the four sets, §2 the "no key
  in the class file" gap). The id corpus is
  `bench/rotation_gap_vs_apl_2026-10-20.md` (§0.0 correction log).
- **Next step:** work out each class's common-ability list with per-family ids
  from the in-tree sources (never an invented id), wire it into the class's own
  practice-panel vocabulary, publish it as neutral (family-scoped where a common
  ability IS a rotation action on some family), and pin the closed-list contract
  in `tests/neutral_actions_state.lua`.

## 2026-10-20 — The four classes' common abilities landed
- **Worked on:** each of the four classes gained a PUBLISHED practice-panel ability
  list (`ST.<CLASS>.practice_common_actions` — key + label + the client's English
  spell name + the cited ids + an optional family gate), a resolver
  (`resolve_practice_common_action`: name first, then the cited id ladder; the
  query is the NAME on TBC and the numeric id elsewhere; an ability the client
  does not have is dropped), a panel-slot accessor (`practice_panel_slots`) and a
  widening seam (`apply_practice_panel_actions`). The seam runs INSIDE the
  `if st.practice_ui …` block of `post_init` — AFTER the guide frame built its
  icons, BEFORE `practice_ui.init` — the shaman's `apply_family_slots`
  precedent, so the live next-action guide is untouched and the practice panel's
  action row offers the common abilities with their icons. The neutral sets grew
  to match: paladin flat (+6), warrior family-scoped (4 buckets), rogue
  family-scoped (4 buckets), shaman flat (5).
- **Current state:** harness **43 steps, 0 failed**; luacheck **2 warnings / 0
  errors** (the standing floor, both pre-existing; the eight touched files are
  0/0); mutation proofs **9/9 killed** on `/tmp/opencode/mut_common` copies;
  CRLF kept in the paladin/warrior/rogue class files, LF in the shaman's (it was
  already LF) and in the test files. The cross-class suite grew 720 → 2880
  checks (it now also pins the published list, the family gates, the offer pin
  and the widening seam). `tests/paladin_state.lua` and `tests/guide_contract.lua`
  (other lanes' files) are untouched and green — the guide slot counts did not
  move.
- **Judgement calls (the orchestrator may rule otherwise):** the panel's button
  label is the KEY (the panel's label map only covers the rotation entries — an
  engine-side fix); the neutral publish is keyed on `st.family`, so the SoD build
  cannot have a neutral key that is a rotation action on the Era build (the
  warrior's Battle Shout is therefore WRATH-only and the shaman's Lightning
  Shield is deliberately out); the DRILL-list press path is not neutral (the
  engine's neutral outcome lives in the rotation scenario — the engine lane owns
  that seam); food/potions ARE spells (the client's use effects), so they can
  carry an icon.
- **Next step:** the orchestrator dispatches the hunter's and the druid's lists
  (bench file §5) to their lanes.

## 2026-10-20 — [signal:done] The four classes' common abilities landed
- **Artifact:** `bench/class_common_actions_2026-10-20.md` (the mechanism, the
  four sets, the id citations, the hunter/druid proposals, the mutation table,
  the judgement calls and the UNCONFIRMED list). Harness 43/0, luacheck 2/0,
  9/9 mutation proofs killed.
- **Signal:** `.signals/20261020T185111Z-done.json`.
