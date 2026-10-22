# Publish-Gate Pins — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the last three findings of the final publish-gate re-audit —
  all three are **test pins** (no live defect): F-1 (MEDIUM) the canonicalisation
  seam had no guard against two different spells collapsing onto one canonical
  key, F-2 (LOW) the CHANGELOG's "per-class sets" passage had no mechanical pin,
  F-3 (LOW) the harness registry guard was self-referential and the step count
  was unpinned.
- **Scope:** `tests/practice_ui_state.lua`, `tests/neutral_actions_state.lua`,
  `tests/toc_check.lua`; `tests/run.sh` only if a registry line was genuinely
  needed (it was not); `classes/paladin.lua` only if the collision pin needed a
  small accessor (it did not). Nothing else — no other class file, no
  `practice*.lua`, no options/config/main/diag/compat/hud/bars, no TOCs, no
  versions, no README/CHANGELOG/docs, no git, no lint-config change.
- **Source:** the dispatch brief. **The re-audit's own report file is NOT on
  disk** — `desks/final-reaudit/` does not exist (the same gap the
  `reaudit-fixes` desk filed as a hands-up). Every finding was therefore
  re-derived from the live tree and verified against it before anything was
  written.
- **Next step:** read the seam (`scenario_action_order`, `scenario_action_spell_id`),
  the six publish tables and the CHANGELOG passage; write the three pins; prove
  each one fails on a broken condition; journal and signal.

## 2026-10-20 — [signal:done] the three pins are landed and every one is proven to fail
- **Worked on:** three pins, one per finding.
  - **F-1** (`tests/practice_ui_state.lua` §29f, +34 checks): the class's own
    published panel vocabulary (the guide slots, the rotation rows, the common
    abilities) is walked per class and per family, every key is canonicalised
    through the class's own normaliser, and two *different* keys that land on one
    canonical key must denote the same spell (the guide slots' icon ids agree,
    the common abilities' ladder heads agree, the spell names agree). The
    normaliser's shape is pinned too: the five single-key-space classes publish
    an identity normaliser, the paladin publishes one that really merges. No
    class-side accessor was needed — the vocabulary is assembled from what the
    classes already publish — so `classes/paladin.lua` was NOT touched.
  - **F-2** (`tests/toc_check.lua`, +150 checks): the `- **The per-class sets.**`
    bullet of `CHANGELOG.md` is parsed (the class a key belongs to is the class
    named before it; a key's family claim is the list after it; a "WITHOUT" clause
    is negative; a "the same N keys" clause resolves to the list before it) and
    compared with each class's `practice_neutral_actions` table, parsed out of the
    class source. The per-class key sets, the per-key family claims, the
    flat/family-scoped shape and the "no bucket for Cata, Mists or Retail" claim
    are all checked.
  - **F-3** (`tests/neutral_actions_state.lua`, +3 checks): a counter-guard in a
    DIFFERENT suite — `tests/run.sh` must register the suite that carries the
    registry guard (`tests/toc_check.lua`) exactly once, and the registry must
    hold at least 41 registered suites (a floor, so a legitimate suite ADDITION
    passes; a legitimate removal lowers the floor in the same change). The two
    guards are mutual, so neither can be switched off alone. **No registry line
    was added and `tests/run.sh` was not touched** — the orchestrator owns it and
    nothing was needed from it.
- **Current state:** harness **43 steps, 0 failed**; luacheck **2 warnings / 0
  errors in 85 files** (the standing floor, both pre-existing); the three touched
  test files are 0/0 on their own. **12 mutation proofs, 12 kills, 0 escapes** on
  disposable copies under `/tmp/opencode/mutproof` (the script is
  `/tmp/opencode/mutation_proofs.sh`): M1 the paladin's alias table merges two
  different spells, M2 a common ability merges onto a rotation key, M3 a
  single-key-space class grows an alias table, **M4 two common abilities merge
  (the new pin is the ONLY guard — all 6 failing checks are from the new
  block)**, M5 the passage drops a key, M6 the tree publishes a new key, M7 the
  tree's 4.0+ bucket gains `sotc`, M8 the passage excludes the wrong key, M9 the
  passage attaches a key to the wrong family, M10 the tree gives the warrior a
  Cata bucket with an existing key, M11 `run.sh` loses the `toc_check` line (the
  full harness on that mutant: **42 steps, 2 failed** — it was 42 steps, 0 failed
  before this lane), M12 `run.sh` loses the `neutral_actions_state` line. The
  control copy is green in all three suites. LF kept in the test files; the class
  file, the CHANGELOG, the TOCs, the versions, the README, the docs and the lint
  config are untouched.
- **Artifact:** `bench/publish_gate_pins_2026-10-20.md` (the findings, the
  mechanism, the proof table and the honest limits of each pin).
- **Cross-fire seen (not this lane's):** while the proofs ran, another lane was
  editing `classes/rogue.lua` (the central HU-7 fix — the per-class namespace
  mirror `st.ROGUE = ST.ROGUE` came out) and `tests/rogue_state.lua` /
  `tests/wiring_check.lua` with it. The harness was briefly red on
  `tests/rogue_state.lua` ("the class table is mirrored onto the addon
  namespace (HU-7)") — a file this lane never touched, and the rogue suite
  reads none of the three files this lane changed. The other lane finished at
  19:57 and the harness went green again (**43 steps, 0 failed**, luacheck back
  to 2/0). Recorded so the orchestrator does not read it as a pin failure.
- **Next step:** the orchestrator validates (the harness and luacheck are the
  orchestrator's to hold) and decides whether the F-2 pin's per-class mode table
  ("list" vs "delta" — the passage's own shape) should be hardened. Nothing is
  left open in this desk's scope.
