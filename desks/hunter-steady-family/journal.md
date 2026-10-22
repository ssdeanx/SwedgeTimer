# Hunter Steady Family — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Close release-gate blocker **B2** (the test-sufficiency audit): the hunter's
  **HUD** Steady Shot id is family-blind and asserted nowhere, and the **Forever guide** slot
  set still certifies a Steady Shot row the corpus says the Forever client cannot have.
- **Scope:** `classes/hunter.lua`, `hunter_guide.lua` (the frozen spec header only),
  `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`, `tests/hud_state.lua`
  (the hunter census only). No git, no lint config, no other class, no docs/TOC/version.
- **Also in scope (operator addition):** the strict **HU-13** flag sweep in the two hunter
  test files (`type(entry.live) == "boolean"`, `type(entry.engine) == "boolean"`, and the
  cross-row rule that a `live == false` row names a non-empty `needs`).
- **Evidence of record:** `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **H3** (TBC Steady
  = 34120; 56641 does not exist on the TBC client) and **H4** (the Forever client has no
  Steady Shot at all), `bench/hunter_utility_live_2026-10-20.md` §1 (the Forever rotation row
  is gone), `CHANGELOG.md` §[2.1.1] "the TBC Steady Shot is 34120 … the Forever client has no
  Steady Shot at all — its row was removed".
- **Next step:** family-correct the HUD Steady slot (TBC → 34120, Forever → the slot is
  filtered out, Era unchanged), drop the Forever guide's Steady row, amend the pins, prove
  both with mutation proofs on `/tmp/opencode` copies.

## 2026-10-20 — B2 closed: the Steady id is family-correct, the Forever row is gone
- **Worked on:** the HUD's Steady Shot id (family-blind 56641 → the family's own id,
  re-pointed at the client's own rank like the guide slot and the Aimed HUD mirror);
  the Forever HUD dead-slot filter (the client has no Steady Shot); the Forever guide
  slot set (the Steady row dropped, 12 → 11 slots, fixture no longer hands the sandbox a
  spell the client cannot have); the Forever steady cast-time fallback (removed) and the
  now nil-guarded per-frame Steady probe; the **strict HU-13 sweep** the operator added
  (both hunter test files) — which found 46 rotation rows that declared NO `engine` flag
  (the truthiness test passed them as engine-facing); every row now declares it.
- **Current state:** harness **41 steps, 0 failed**; luacheck **2 warnings / 0 errors**
  (the floor, both pre-existing in files this lane never touched); **8/8 mutants killed**
  on `/tmp/opencode` copies; CRLF preserved in `classes/hunter.lua` + `hunter_guide.lua`.
  Report: `bench/hunter_steady_family_2026-10-20.md`.
- **Next step:** the orchestrator validates (it owns the release gate) and rules on the
  three filed residuals: the other HUD slots are still family-blind (the same fix would
  cover them); the Era client's Steady Shot existence is UNCONFIRMED (the shipped tree
  contradicts itself there); the TBC Arcane row is a dormant arm that still shows a
  practice-panel button (making it `engine = false` would remove a button — out of scope).

## 2026-10-20 — [signal:done] B2 closed
- The HUD's Steady id is family-correct and pinned per family (TBC 34120 / Wrath the
  client's own rank / Forever the slot absent / Era unchanged); the Forever guide set
  matches the corpus correction (eleven slots, no Steady row) and the suite no longer
  certifies a row the client cannot have; the strict HU-13 sweep is in both hunter test
  files. 41/0 harness, luacheck 2/0, 8/8 mutants killed.
- Artifact: `bench/hunter_steady_family_2026-10-20.md`. Validation owner: the
  orchestrator. Three residuals filed there for a ruling (the other family-blind HUD
  slots, the Era Steady existence question, the dormant TBC Arcane arm).
