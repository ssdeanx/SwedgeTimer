# paladin-audit-close — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Close the paladin-side items the deep audit and the HUD-mirror lane
  filed: the M2 family gate on the paladin's practice rotation slice, the two
  WotLK HUD-mirror option widgets + defaults, the paladin HUD templates' re-cut
  (12 -> 14 slots) and the off-by-13 sim citation.
- **Scope:** `classes/paladin.lua`, `nextaction.lua`, `option_tables.lua` (the two
  paladin widgets only), `config_presets.lua` (the two defaults + the paladin
  template rows only), `tests/paladin_state.lua`,
  `tests/options_load_state.lua` (the two widgets' pins only),
  `tests/hud_state.lua` (paladin section only),
  `tests/hud_templates_state.lua` (paladin section only) and the one bench file
  that carries the wrong citation. No git, no lint-config change, no TOC/version/
  README/CHANGELOG/doc change, no other class touched.
- **Source of truth:** `bench/paladin_hud_utility_band_2026-10-20.md` §2.1/§4
  (the citation correction + the filed widgets/defaults/templates),
  `bench/lessons.md` (the re-read-the-citation lesson), the rogue/warrior/druid
  family-gate shapes, and the paladin engine's own arms in `nextaction.lua`.
- **Next step:** the family gate first (it decides the practice strip), then the
  widgets/defaults/templates, then the citation; harness + luacheck floor +
  mutation proofs on `/tmp/opencode` copies.

## 2026-10-20 — the four items landed
- **Worked on:** (1) **M2** — `ST.PALADIN.practice_rotation_for` now applies the
  rogue's `families` predicate (on the order-key path **and** the APL-row path).
  The family token comes from the ORDER (the SoD game runs on the ERA client, so
  the SoD variants' own orders name `SOD`; the twist order answers the client's
  own family). The TBC strip loses the execute "Hammer of Wrath" button the TBC
  rotation can never ask for (the engine's execute arm is Era/Forever only).
  (2) The two WotLK mirrors are switchable in-game: the widgets
  (`hud_show_hor` 8.53, `hud_show_how_wrath` 8.54) and the defaults
  (`false`, the druid-Claw shape) with the consumer cited. (3) The paladin
  templates now name all **fourteen** slots; the band rides P-T2 "Full Ret"
  (true) and stays off in P-T1/P-T3 — the SoD-native "extends P-T2, not P-T1"
  rule and the druid's Claw shape. (4) The off-by-13 citation
  (`hammer_of_wrath.go:18` → `:31-32`) is corrected in `classes/paladin.lua`,
  `nextaction.lua` (both places) and the APL bench file (with a correction note).
  Plus the operator's mid-session instruction: the band's spell-book gate reads
  `api.is_spell_known_state` (the tri-state) instead of the binary, so the gate
  tells "not known" from "the client cannot answer"; both still hide
  (unknown-hides) and the last answer per slot is recorded on
  `ST.PALADIN.hud_band_spell_state` (the HUD's frozen state table has no room
  for a reason). `api.is_spell_known` itself untouched.
- **Current state:** harness **41 steps / 0 failed**; luacheck **2 warnings / 0
  errors in 83 files** (the floor; the touched files are clean);
  `tests/paladin_state.lua` **1056 checks**, `tests/hud_state.lua` **731**,
  `tests/hud_templates_state.lua` **928**, `tests/options_load_state.lua`
  **3465** — all green. **18 / 18 mutations killed**
  (`/tmp/opencode/paladin_audit_close_mutations.py`). CRLF preserved in
  `classes/paladin.lua` (5991/0) and `nextaction.lua` (1440/0), LF preserved
  elsewhere; no trailing whitespace on any touched line; the diff against the
  band lane's snapshot touches only the listed regions.
- **Evidence:** `bench/paladin_audit_close_2026-10-20.md` (the report, the
  per-family slice table, the mutation table, the caveats).
- **Known consequences (documented, not hidden):** the Era client's *rotation*
  strip loses the `cons` / `exo` rows (the corpus's family gate: the Era APL
  carries no filler row) — the presses stay reachable through the panel's
  asked-for vocabulary; and with the `false` defaults the two band icons are
  hidden at the HUD level, so the shipped profile runs 10 provider calls where
  the HUD band lane's nil-toggle census read 12 (the visible row is the same).
- **Next step:** orchestrator validation (in-client confirmations still owed:
  the spell-book probe on a talent id, and the WotLK client's own cooldown
  lengths).

## 2026-10-20 — [signal:done] the paladin-side audit items are closed
- M2's family gate landed on the rotation slice (the TBC strip no longer offers
  a button the TBC rotation can never ask for); the two WotLK HUD mirrors are
  switchable in-game (widgets + `false` defaults); the paladin templates cover
  all fourteen slots; the off-by-13 sim citation is corrected in the code and
  the bench. Harness 41/0, luacheck floor held, 18/18 mutations killed.
  Report: `bench/paladin_audit_close_2026-10-20.md`.
