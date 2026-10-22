# Shaman CoE + Stormstrike — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build spec **BS-4** (shaman class side only) from
  `bench/filed_closure_sweep_2026-10-19.md` §7:
  - **4a / S-20 / U-10** — the Call of the Elements live slot (id `66842`, water
    totem slot `3`), the water-clock feed (`inputs.water_remaining` /
    `inputs.water_duration`), the engine rule (9c), and the HUD mirror.
  - **4b / S-23 / U-09** — the per-family Stormstrike fallback
    (Era 20 / SoD 6 / TBC 10 / Wrath 8) on the guide slot and the HUD mirror.
  - **4c is NOT mine** — the Flame Shock default flip belongs to the sibling
    options lane (`config_presets.lua` + `tests/shaman_guide_state.lua`).
- **Scope:** `classes/shaman.lua`, `shaman_guide.lua`, `tests/shaman_state.lua`,
  `tests/guide_contract.lua` (shaman section only), `tests/hud_state.lua`
  (shaman section only).
- **Out of scope (per the dispatch):** `config_presets.lua`,
  `tests/shaman_guide_state.lua`, `practice*.lua`, `option_tables.lua`,
  `compat.lua`, other classes, `main.lua`, `diag.lua`, `hud.lua`, `bars.lua`,
  `run.sh`, TOCs, versions, README/CHANGELOG/docs, no git, no lint-config.
- **Validation owner:** orchestrator.
- **Next step:** implement the water clock + CoE slot/rule + the per-family
  Stormstrike fallback, pin them, run the harness + luacheck, then the mutation
  proofs on `/tmp/opencode` copies.

## 2026-10-19 — BS-4a + BS-4b built (harness 41/0, luacheck 2/0, 23/23 mutations)
- **Worked on:** the Call of the Elements line (water clock → gather feed → engine
  rule 9c → guide slot 18 → HUD mirror) and the per-family Stormstrike fallback
  (guide slot's static `swipe_duration` + the HUD mirror's own fallback).
- **Sources (all re-fetched this session, not remembered):** the water slot 3 and
  the id 66842 from the clients' own `Constants.lua` (read via
  `git -C /home/sam/wow-ui-source show`, READ-ONLY, against
  `classic_titan` / `origin/forever`); the CoE APL rank and the 20 s window from
  the three `wowsims/wotlk` enhancement APLs; the four Stormstrike lengths from
  the four families' own `stormstrike.go`.
- **Current state:** the tree is green — `bash tests/run.sh` = **41 steps / 0
  failed**, `luacheck .` = **2 warnings / 0 errors** (the standing floor, both
  pre-existing in `compat.lua` + `main.lua`; none of my files warns). The four
  touched suites: `shaman_state` 719, `shaman_guide_state` 1389,
  `guide_contract` 1042, `hud_state` 675. Mutation proofs on the
  `/tmp/opencode/shaman-coe-ss-mut` copy: **23 killed / 0 survived**.
- **Next step:** the orchestrator validates in-tree. The options pass still owes
  the `hud_show_coe` widget + default (`config_presets.lua` /
  `option_tables.lua` — **not mine**); the in-client pass still owes the 66842
  behaviour on 3.80.2 (does `GetSpellCooldown` answer? does the water-slot read
  report?) and the Wrath 4pc Glad-4pc 6 s Stormstrike variant.
- **Scope deviation (raised as hands-up HU-10):** the dispatch excluded
  `tests/shaman_guide_state.lua`, but the 18th guide slot breaks that file's
  slot-count pins (and crashes it on a nil icon name). I made the **minimum
  mechanical** update there — the slot counts, the expected key/icon lists, the
  `SPELL_INFOS` fixture entry for 66842, the frozen-input mirror, the rotation
  line's live flag and the reason list — and touched **no Flame Shock pin**
  (the sibling options lane still owns those). Without it the harness cannot be
  green, so the operator should rule on the boundary.

## 2026-10-19 — [signal:hands-up] the `tests/shaman_guide_state.lua` scope boundary
- Signal: `desks/shaman-coe-ss/.signals/2026-10-20T03-40-00Z.json`; row **HU-10**
  in `hands-up.md`.
- The 18th guide slot breaks the excluded file's slot-count pins (and crashes it on
  a nil icon name), so the harness cannot be green without a change there. The lane
  made the minimum mechanical update and touched **no Flame Shock pin**.
- The operator rules: (a) keep the update (recommended) or (b) revert it and make
  the CoE slot WRATH-only.

## 2026-10-19 — [signal:done] BS-4a + BS-4b landed
- Signal: `desks/shaman-coe-ss/.signals/2026-10-20T03-42-00Z.json`.
- Bench artifact: `bench/shaman_coe_ss_2026-10-19.md`.
- Tree state at the close: `bash tests/run.sh` = 41 steps / 0 failed, `luacheck .` =
  2 warnings / 0 errors (the standing floor), 23/23 mutations killed on the
  `/tmp/opencode` copy.
- Note for the next session: the sibling **options** lane landed the Flame Shock
  default flip (3 → 0) during this lane - `config_presets.lua:1077` now reads
  `guide_flameshock_refresh = 0` and its pins in `tests/shaman_guide_state.lua` are
  the sibling's, not this lane's. The two writers did not collide (the suite is
  green and this lane's slot-count pins are intact).

## Notes carried in
- The tree's "UNCONFIRMED against FrameXML" note on the water slot is **stale**:
  the slot map and the id are in the shipped clients' own `Constants.lua`.
- The CoE **APL rank is sourceable** (the three wowsims/wotlk enhancement APLs
  rank CoE between Earth Shock and Magma Totem), so it did not have to be filed.
- `classes/shaman.lua` is at Lua 5.1's **200-local limit** for its main chunk:
  every new constant has to be published on the class namespace
  (`ST.SHAMAN.*`) or the file stops compiling. The lane folded the four totem
  slot constants into one cited table (`WEAVE_TOTEM_SLOTS`) to make room. The
  next lane that needs a constant will hit this wall again.
