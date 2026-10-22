# shaman-residuals — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Close the four residuals the shaman APL utility lane filed in
  `bench/shaman_apl_utility_build_2026-10-20.md` §5: the Lightning Shield
  maintain's per-family gap (F1), the Frost Shock "Filler Shock" choice as a
  real option, the Chain Lightning sensor's honest flags, and the TBC twist
  row's sim-exact ranks (C5).
- **Scope:** `classes/shaman.lua`, `shaman_guide.lua`, `option_tables.lua`
  (the Frost Shock widget only), `config_presets.lua` (that widget's default
  only), `tests/shaman_state.lua`, `tests/shaman_guide_state.lua`,
  `tests/options_load_state.lua` (that widget's pins only). One new bench
  file. No git, no lint-config change, no TOC/version/doc change, no other
  class touched, no other option file touched.
- **Source of truth:** `bench/shaman_apl_utility_build_2026-10-20.md` §5 (the
  filed residuals) + the fetched APL files under `/tmp/opencode/shaman_apl/`
  (the lane's own artifacts, re-read here) + the clients' FrameXML in
  `/home/sam/wow-ui-source` (the Chain Lightning check) +
  `bench/filed_closure_sweep_2026-10-19.md` §4.1/§10 (S-11 and O-4, the
  operator decision the Chain Lightning row is filed under).
- **Next step:** read the residual spec, verify every id/index against the
  fetched APLs, implement the four changes, pin them in the three suites,
  prove the mutations on `/tmp/opencode` copies, and file the Chain Lightning
  finding on the bench.

## 2026-10-20 — The four residuals closed
- **Worked on:** (1) the Lightning Shield maintain's per-family gap — the row's
  `families` are now `{ "WRATH", "SOD", "FOREVER" }` with a per-family id map
  (49281 / 10432 / 10432), the gather and the engine's rule 11b share a new
  pure helper (`get_lightningshield_family_gate`: WRATH, FOREVER, or the ERA
  token with the MW-rune latch = the SoD build), and a known gate was added
  (the Lightning Shield is a talent — a build without it is never prompted).
  (2) the Frost Shock choice is now a real class-owned input: the gather
  reads `db.guide_filler_shock` and states the engine's frozen token only when
  the player picked Frost Shock; the widget is `option_tables.lua`'s
  `guide_filler_shock` select and the default is `config_presets.lua`'s
  `"earth"` (the APL's own default — no default-visible change).
  (3) the Chain Lightning row's flags are honest: the enemy-count sensor does
  not exist (re-verified: 0 Chain Lightning hits in the FrameXML of five
  client branches; the live gather feeds `target_count = nil`; the shared
  practice engine never states it), so the row is now `live = false,
  engine = false` and names the missing read in `needs`; rule 13 stays as the
  filed skeleton because cutting it is the operator's O-4 decision.
  (4) the twist row's ranks are reconciled: the shipped 8512 stays the
  rank-1 fallback (the module's mana-sustain downrank, the operator's O-1
  decision) and the TBC APL's sim-exact rank-5 id 25587 rides in
  `spell_ids`, with the alternation's Grace of Air half (25359) cited.
- **Current state:** `bash tests/run.sh` — **41 steps, 0 failed** on a settled
  tree (the tree's floor; luacheck **2 warnings / 0 errors**, both in
  `compat.lua` + `main.lua`, untouched). The lane's own suites: shaman_state
  **785**, shaman_guide_state **1551**, options_load_state **3449**,
  secret_guard_state **373** — all green; the four lane files are luacheck
  clean. `classes/shaman.lua` still carries 198 top-level locals (the new
  constants are `ST.SHAMAN` table fields, not locals).
  **Mutation proofs: 17/17 killed**
  (`python3 /tmp/opencode/mutations_shaman_residuals.py`) — including the
  brief's named mutant (`chainlightning_claims_arm`: the row's `engine`
  flipped back to `true` fails a pin in both shaman suites). Artifact:
  `bench/shaman_residuals_2026-10-20.md`.
- **Decisions worth the trail:** the Lightning Shield extension needed a
  **known gate** the lane's spec did not mention — without it the newly
  enabled SoD/Forever families could prompt a talent the player does not
  have, which is the residual's own "wrong value on some family" failure; the
  gate follows the Searing maintain's shape (the client's own resolved id, an
  unreadable answer stays silent). The HUD's Lightning Shield mirror was left
  alone on purpose: it is display-only, ships hidden, and gating it would
  move `tests/hud_state.lua`'s pins (that suite runs the TBC family). The
  gather's two new reads are guarded against a missing guide module — the
  class file must stay loadable standalone (the secret_guard sandbox loads
  it without `shaman_guide.lua`), which is why the guard mutant is killed
  there.
- **Crossfire:** the druid and rogue lanes were editing `classes/druid.lua`,
  `druid_guide.lua` and `classes/rogue.lua` in the same tree during the final
  harness runs, so the **druid** suites and, for a while, `luac5.1 -p` were
  red with their own in-flight edits — none of them in this lane's scope and
  none caused by it. One red remained at the end and is **not** this lane's:
  **`tests/options_load_state.lua` §9 (the ROGUE panel's db-key scan)** fails
  two pins because the rogue lane's new citation prose
  (`wowsims/wotlk assets/database/db.json` in `classes/rogue.lua`) matches
  that section's `db%.([%a_][%w_]*)` pattern, so a key called `json` is
  demanded from the rogue's panel and defaults. The rogue's file and that
  section are outside this lane's scope (the rogue lane owns the citation;
  §9 is not this lane's widget's pin) — filed for the orchestrator's
  reconcile. The full harness was green on the settled tree before those
  lanes started; this lane's own four suites are green throughout.
- **Filed for the orchestrator:** the Chain Lightning sensor's finding (the
  read does not exist; O-4 stands) and the cross-class flag convention — this
  lane reads `engine` as "an arm that can play the line with the inputs the
  shipped tree produces", while the rogue lane's rows keep `live = false,
  engine = true` for a rule whose input is never fed (HU-13 is still open).
- **Next step:** the orchestrator validates (the full harness on a settled
  tree, then the in-client checklist: the Lightning Shield known gate on the
  Wrath/SoD/Forever clients, the SoD build's Lightning Shield talent
  availability, and the Frost Shock option's pick).

## 2026-10-20 — [signal:done] The four residuals closed
- `desks/shaman-residuals/.signals/2026-10-20T03-52-00Z.json` (execution/done,
  run_id `shaman-residuals-2026-10-20`).
- The signal's headline: the Chain Lightning row's `engine` flag came down
  because the **practice** half of the claim was never checked - not only does
  the client have no enemy count (0 Chain Lightning hits in five branches'
  FrameXML), nothing in the tree feeds `target_count` either, so rule 13 has no
  producer. The artifact: `bench/shaman_residuals_2026-10-20.md`.


