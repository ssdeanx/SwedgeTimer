# Class Neutral Hunter Druid — Journal

## 2026-10-20 — Desk opened
- **Purpose:** land the hunter's and the druid's NEUTRAL action sets and their
  common-ability lists (the two classes the `class-neutral-actions` /
  `class-common-actions` lanes filed for the orchestrator).
- **Scope:** `classes/hunter.lua`, `classes/druid.lua`,
  `tests/hunter_state.lua`, `tests/druid_state.lua`,
  `tests/neutral_actions_state.lua` (the hunter/druid rows only) + the bench
  artifact. The engine (`practice.lua`, `practice_ui.lua`) is NOT touched — the
  mechanism already exists.
- **Specs (read first):** `bench/class_neutral_actions_2026-10-20.md` (§3 the
  filed hunter/druid sets) and `bench/class_common_actions_2026-10-20.md` (§5
  the filed common abilities with their cited ids).
- **Next step:** implement the two classes' publish + common list + resolver +
  widening seam (the paladin's shape), then the suite rows, then the harness +
  luacheck + mutation proofs.

## 2026-10-20 — Hunter + druid neutral sets and common abilities landed
- **Worked on:** `classes/hunter.lua` and `classes/druid.lua` (the neutral publish,
  the practice-panel ability list, the resolver, the panel slot list, the widening
  seam, the build-aware pick) + `tests/neutral_actions_state.lua` (the hunter's
  and the druid's five slices each) + `tests/hunter_state.lua` and
  `tests/druid_state.lua` (the class-level pins). Bench artifact:
  `bench/class_neutral_hunter_druid_2026-10-20.md`.
- **Current state:** landed and green. Harness 43 steps / 0 failed; luacheck
  2 warnings / 0 errors (the standing floor, pre-existing); the cross-class suite
  4313 checks (was 2880), hunter_state 1704, druid_state 1574; 14/14 mutation
  proofs killed on `/tmp/opencode` copies (each kill a pin failure, no crash).
  CRLF kept in the two class files, LF in the three test files.
- **Deviations from the filed spec (all recorded in the bench artifact §2):**
  (1) the hunter's publish is family-scoped, not flat - the WotLK panel offers no
  Raptor Strike key (a flat publish would invent one) and the Forever rotation
  asks for that spell under `raptor_strike` (a flat publish would make a wrong
  Raptor Strike press free); (2) the ERA bucket is BUILD-AWARE in both classes -
  the SoD build shares the ERA token with the Era-base build and the SoD
  rotations ask for the Raptor Strike / the Rake, so the class's own build
  decision drops them there (the tree's own precedent: the hunter's build-aware
  HUD pick, bench/hunter_sod_build_2026-10-20.md); (3) the filed Regrowth
  ladder's 9844 is a Rejuvenation id (the Classic spell page titles it
  "Rejuvenation"), so it is not published as Regrowth - and the Healing Touch
  ladder was completed from the corpus's Restoration skill line.
- **Next step:** the operator's in-client pass (the panel row, the icons, the
  NEUTRAL popup). Open for the orchestrator: the Cata/Mists clients carry no
  bucket in either publish, so the common abilities the panel offers there are
  mis-graded (the same shape the four already-landed classes publish).
