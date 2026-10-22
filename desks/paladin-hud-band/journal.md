# paladin-hud-band — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Mirror the paladin's WotLK APL **utility band** (Hand of Reckoning
  67485, the WotLK Hammer of Wrath 48806) into the paladin's HUD row, the way the
  other display-only mirrors work, and re-cut the paladin census pins in
  `tests/hud_state.lua`.
- **Scope:** `classes/paladin.lua` (the HUD slot descriptors + the HUD
  provider's band branches only), `tests/hud_state.lua` (**paladin section
  only**). One new bench file. No git, no lint-config change, no TOC/version/
  option/config change, no other class touched.
- **Source of truth:** `bench/paladin_apl_utility_build_2026-10-20.md` §2.3 (the
  two new guide slots) and §4 (the filed "WotLK HUD mirror" row), plus the sims'
  own spell files for the cooldown + execute-gate evidence.
- **Next step:** the two band mirrors + the census re-cut; harness + luacheck
  floor + mutation proofs on `/tmp/opencode` copies.

## 2026-10-20 — the band mirrors landed
- **Worked on:** Two HUD descriptors appended to `ST.PALADIN.HUD_SLOTS` (`hor`
  67485, `how_wrath` 48806 — the APL's own ids, the same pair the guide's band
  slots carry). A provider gate with three gates in order — option (`hud_show_
  <key>` exactly true; nil = off, the druid-Claw shape), family (Wrath only),
  spell book (unknown hides) — placed **before** any read, so a hidden slot
  performs no read. A name-based cooldown read (rank-agnostic; the client's own
  duration drives the swipe, no hardcoded number) and the execute-phase
  desaturation for `how_wrath` (the sim's own `IsExecutePhase20()` gate, the same
  20 the engine arms on). The census in `tests/hud_state.lua` re-cut: 12 → 14
  slots, the two ids, the mirror keys, the icon/frame counts (14 / +59), the
  option-gate key list, the Era count, the paladin reflow provider counts
  (10 → 12) and two new blocks — the TBC family-gate pins and a whole new §7c
  Wrath sandbox.
- **Current state:** harness **41 steps / 0 failed**; luacheck **2 warnings / 0
  errors in 83 files** (the floor; the two touched files are clean);
  `tests/hud_state.lua` **PASS (714 checks)**; **9 / 9 mutations killed**;
  CRLF preserved in `classes/paladin.lua` (5928/0), LF preserved in
  `tests/hud_state.lua`. The diff against the APL lane's snapshot touches only
  the paladin regions — no other class's census changed.
- **Evidence:** `bench/paladin_hud_utility_band_2026-10-20.md` (the report, the
  sim citations, the filed items).
- **Next step:** orchestrator validation. Filed to the orchestrator: the options
  widget + the `hud_show_*` defaults (both in `config_presets.lua` /
  `option_tables.lua` — out of this lane's scope), the paladin HUD templates'
  twelve → fourteen re-cut, and `nextaction.lua`'s off-by-13 sim citation.

## 2026-10-20 — [signal:done] the HUD band mirrors landed
- Two WotLK band mirrors in the paladin's HUD row (hidden by default, no
  default-visible change), the census re-cut, harness 41/0, luacheck floor held,
  9/9 mutations killed. Report: `bench/paladin_hud_utility_band_2026-10-20.md`.
