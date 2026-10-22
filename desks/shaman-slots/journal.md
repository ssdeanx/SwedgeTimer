# shaman-slots — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Close the shaman feature gap the drill/audit lanes filed: the rotation's
  Lightning Shield (S-19), Call of the Elements (S-20) and Searing Totem (S-17) lines are
  practiced but never taught — they have no live guide slot.
- **Scope:** `classes/shaman.lua`, `shaman_guide.lua`, `tests/shaman_state.lua`,
  `tests/shaman_guide_state.lua`, `tests/guide_contract.lua` (shaman sections only),
  `tests/hud_state.lua` (shaman census only). OUT: `practice*.lua`, `option_tables.lua`,
  `config*.lua`, `main.lua`, `diag.lua`, `compat.lua`, `hud.lua`, `bars.lua`, `run.sh`,
  TOCs, versions, README/CHANGELOG/docs, other classes, git, lint-config.
- **Spec:** `bench/shaman_drills_2026-10-19.md` §2 (S-17/S-19/S-20 filed rows) +
  `bench/class_features_drills_2026-10-19.md` §2.6 A (the shaman feature checklist).
- **Next step:** read the guide/HUD seams, then land the LS + Searing slots (rules + gather
  feeds), file CoE with its exact probe, mirror the HUD where flaggable, and re-pin the
  rotation table's `live` flags.

## 2026-10-19 — S-19 + S-17 taught, S-20 filed with its probe, HUD mirrored, 17/17 mutations
- **Worked on:** closed the slotless-line gap the drill lane filed (bench/shaman_drills_2026-10-19.md
  §2). `shaman_guide.lua`: the two maintain slots + two rules (11b Lightning Shield between
  Fire Nova and Lava Lash; 9b Searing Totem between Stormstrike and Magma - the audit's pure
  `get_searing_upkeep_due` moved up from the practice surface so the live guide and the D-S4
  drill grade ONE gate), three new frozen inputs (`lightningshield_due`, `searing_down`,
  `mw_observed`), the practice reasons + ctx mappings. `classes/shaman.lua`: the guide slots
  15→17, the aura walk's "the walk ran" latch, the gather feeds (the LS maintain rides the
  charge row's own aura walk - free; the Searing is known-gated like the Fire Elemental, so a
  talentless player is never prompted), the client-name icon resolution for both UNCONFIRMED
  ids, the HUD mirror 8→10 (nil = off, provider-level hide, glow = the upkeep cue), and the
  rotation table's `live` flags (searing + lightningshield now true). `tests/guide_contract.lua`
  gained the shaman's own section §7 (the contract is per class - the paladin's and the rogue's
  sections are untouched: only two additive SPELL_INFOS fixtures + the `SHAMAN = {}` sandbox
  entry). `tests/hud_state.lua` = the shaman census only. CoE FILED with the exact probe (the
  water-slot GetTotemInfo reader + the gather feed + the rule above Magma + the slot/contract/
  HUD/options cut; 66842 UNCONFIRMED) - no faked clock.
- **Current state:** harness **41 steps / 0 failed** at this lane's close, luacheck **2
  warnings / 0 errors** (the floor; my six files 0/0), my four suites green
  (shaman_guide_state 1378, shaman_state 663, guide_contract 1031, hud_state 668).
  Mutations **18/18 killed, 0 void** on /tmp/opencode/shaman-slots-mut copies
  (mutate.sh + m13.py); the repo tree is byte-identical to the pre-mutation copy. Bench artifact:
  bench/shaman_slots_2026-10-19.md. No git, no lint-config, no out-of-scope file touched.
  (A later harness run shows 41/1: `tests/druid_state.lua` — the parallel druid lane's
  mid-edit, `classes/druid.lua` changed at 22:03; that suite loads none of this lane's
  files. Crossfire for the orchestrator to reconcile.)
- **Next step:** orchestrator validates; the options pass owns `hud_show_lightningshield` /
  `hud_show_searing` (default false) + the widgets in config_presets.lua / option_tables.lua;
  the in-client pass owns 49281, the Searing id and the `IsSpellKnown`-on-a-totem-talent answer;
  a future CoE lane takes the filed water-clock probe.

## 2026-10-19 — [signal:done] S-19 + S-17 taught, S-20 filed with its probe
- 17 guide slots + 2 rules + 2 HUD mirrors + the rotation `live` flags; CoE filed with the exact
  water-clock probe; harness 41/0, luacheck 2/0; 18/18 mutations kill.
  desks/shaman-slots/.signals/20261019T215800Z.json
- Validation owner: orchestrator.
