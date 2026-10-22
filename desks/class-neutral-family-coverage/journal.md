# Class Neutral Family Coverage — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the family-coverage gap the hunter/druid neutral lane filed
  (`bench/class_neutral_hunter_druid_2026-10-20.md` §6 "The Cata and Mists
  clients carry no bucket"): make the panel's common-ability OFFER list
  family-aware for all six classes, so an ability is offered on a family only
  where that family publishes it (as neutral) or the rotation ranks it there.
- **Scope:** `classes/paladin.lua`, `classes/warrior.lua`, `classes/hunter.lua`,
  `classes/rogue.lua`, `classes/druid.lua`, `classes/shaman.lua` (the
  offer-list / neutral-bucket logic ONLY) + `tests/neutral_actions_state.lua`
  (the per-family offer pins) + a bench artifact.
- **Out of scope (sibling lanes own them):** `practice.lua`, `practice_ui.lua`,
  `practice_progress*.lua`, `practice_stats.lua`, `option_tables.lua`,
  `config_presets.lua`, `config.lua`, `main.lua`, `diag.lua`, `compat.lua`,
  `hud.lua`, `bars.lua`, `guide_contract.lua`, `run.sh`, the TOCs, the versions,
  README, CHANGELOG, docs. No git commits, no lint-config changes.
- **Specs (read first):** `bench/class_neutral_hunter_druid_2026-10-20.md` and
  `bench/class_common_actions_2026-10-20.md`; the engine contract is
  `bench/practice_neutral_actions_2026-10-20.md`.
- **Next step:** the derived offer gate in the six class modules, the per-class
  CATA/MISTS decision, the per-family offer pins in the cross-class suite, then
  the harness + luacheck + the mutation proofs.

## 2026-10-20 — Desk opened, orientation done
- **Worked on:** read the bench trail (the two class-lane artifacts + the engine
  contract), the six class modules' neutral publish / common list / panel slot
  code, `tests/neutral_actions_state.lua`, and the client-family map
  (`compat.lua`'s CATA / MISTS detection, the `SwedgeTimer_Cata.toc` /
  `SwedgeTimer_Mists.toc` load orders).
- **Current state:** nothing written yet. The plan is settled; see the next
  entry.
- **Next step:** implement.

## 2026-10-20 — The family-coverage lane landed
- **Worked on:** the six class modules (the offer gate + the published-set
  accessor + the Cata / Mists answer) + `tests/neutral_actions_state.lua` (the
  CATA and MISTS slices, the offer pins, the data pin, the runtime-faithful
  vocabulary) + the bench artifact
  `bench/class_neutral_family_coverage_2026-10-20.md`.
- **Current state:** landed and green. Harness 43 steps / 0 failed; luacheck
  2 warnings / 0 errors (the standing floor; the 7 touched files are 0/0);
  `tests/neutral_actions_state.lua` 6239 checks (was 4313); the class suites
  unchanged and green (warrior 2017, hunter 1704, rogue 1095, druid 1574,
  shaman 1035, paladin 1041); 10/10 mutation proofs killed (each a pin failure,
  no crash) + 2 documented equivalent survivors. CRLF kept in the five class
  files, LF in the shaman and the test file.
- **What landed:** (1) ONE offer gate in all six classes
  (`practice_neutral_set` / `practice_rotation_action_set` /
  `practice_canonical_key` / `practice_common_offer_allowed`), driven by the
  class's own published set - the publish is the single source of truth, so the
  offer list and the neutral set can never disagree per family; (2) the Cata /
  Mists answer, PER CLASS: the paladin and the shaman publish FLAT, so their
  common abilities are offered there and neutral there; the warrior, the hunter,
  the rogue and the druid publish no rotation for those two clients and
  therefore no bucket, so the gate offers NO common ability there (the trap is
  closed by exclusion, with the clients' own spell pages cited to show the
  abilities ARE on those clients); (3) the paladin's `bop` entry carries both
  client names ("Blessing of Protection" / "Hand of Protection" - the spell was
  renamed in 3.0, so the name path never answered on the WotLK / Cata / Mists
  clients).
- **Deviations / judgement calls (all in the bench artifact §5):** a bucket
  follows the rotation (the four family-scoped classes publish one only for a
  family they play); the gate is stricter than the ruling's letter (it refuses
  to offer a rotation action - the landed pin says the same); the guide
  vocabulary on the Cata / Mists clients stays out of scope (the classes publish
  no rotation there, so every guide slot is a mis-pick there - now PINNED per
  family so the shape is visible).
- **Open items for other lanes (bench §6):** the classes publish no rotation
  for the Cata / Mists (or the Retail) clients, so their guide vocabularies
  there are not client-verified (the druid's flat cat chain, the rogue's
  4.0-removed Shiv, the hunter's Mists slot set, the warrior's base set); the
  paladin's FLAT publish carries `sotc` (the Seal of the Crusader), which the
  4.0+ clients do not have - fixing it means a family-scoped paladin publish
  (the paladin lane's call, its class suite pins the flat shape); the Holy
  Light id on the Cata / Mists clients is not in the tree.
- **Next step:** the orchestrator validates. If it rules that the four excluded
  classes should publish a CATA / MISTS bucket instead, the ids are cited in
  the bench artifact §1.2 and the change is one bucket each (the offer gate
  picks it up with no further change).

## 2026-10-20 — [signal:done] The family-coverage lane is landed and green
- Signal: `desks/class-neutral-family-coverage/.signals/20261020T164000Z.json`
  (`execution` / `done`, run_id `class-neutral-family-coverage-2026-10-20`).
- Artifact: `bench/class_neutral_family_coverage_2026-10-20.md` (the rule, the
  per-class Cata / Mists answer with the cited spell pages, the pins, the
  verification, the judgement calls and the open items).
- The orchestrator validates: harness 43/0, luacheck floor held, 10/10 mutation
  proofs killed, CRLF preserved.
