# shaman-apl — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Build the shaman's missing APL rotation lines (the utility layer:
  the Strength of Earth and Mana Spring totem upkeeps, the TBC Frost Shock
  filler and the Wrath Bloodlust party cooldown) into
  `ST.SHAMAN.practice_rotation` with the APL priority citations, the per-family
  spell id + name, the family gates and the HU-13 two flags (`live` = the read
  exists, `engine` = the frozen engine has an arm) — and give the frozen guide
  engine (`shaman_guide.lua`) an arm for each so the practice scenario can ask
  for it and the guide can light it.
- **Scope:** `classes/shaman.lua`, `shaman_guide.lua`, `tests/shaman_state.lua`,
  `tests/shaman_guide_state.lua`. One new bench file. No git, no lint-config
  change, no TOC/version/option change, no other class touched.
- **Source of truth:** `bench/rotation_gap_vs_apl_2026-10-20.md` §5 (the
  shaman), re-verified against the FETCHED APL files and the sims' own spell
  data (`wowsims/{classic,sod,tbc-new,forever,wotlk}` master): the five
  enhancement APLs and the per-ability `.go` files.
- **Next step:** re-verify every id/index against the APL JSON, write the
  rotation rows + the pre-pull table (HU-12), add the engine arms, pin them in
  the two shaman suites, prove the mutations on `/tmp/opencode` copies.

## 2026-10-20 — The APL utility layer landed
- **Worked on:** re-fetched the five enhancement APLs and the sims' own
  ability files (`wowsims/{classic,sod,tbc-new,forever,wotlk}` master) and
  expanded every group inline, so the indices and the ids came from the files
  and not from the gap analysis. Landed four rotation lines (Bloodlust 2825,
  Strength of Earth 10442/25528/25361, Mana Spring 25570, Frost Shock 25464),
  their four engine arms (rules 3b / 8a / 8d / 13b) with the new frozen
  inputs, four guide slots, the `ST.SHAMAN.PRACTICE_PREPULLS` table (HU-12),
  and the HU-13 two flags on every row — including the honest flip the
  convention forces: `chainlightning` is `live = false, engine = true` (the
  enemy-count read does not exist) with the missing read in `needs`.
- **Current state:** `tests/shaman_state.lua` PASS (764 checks),
  `tests/shaman_guide_state.lua` PASS (1535 checks), `tests/guide_contract.lua`
  PASS (1052 checks — its shaman slot-count pins re-cut, the HU-10
  precedent). luacheck 0/0 on the four lane files; the tree's floor (2
  warnings, `compat.lua` + `main.lua`, untouched) is unchanged. `classes/shaman.lua`
  still carries 199 top-level locals (Lua 5.1's 200 ceiling — the new
  constants and the new slots are `ST.SHAMAN` table fields, not locals).
  14/14 mutations killed (`python3 /tmp/opencode/mutations_shaman_apl.py`,
  copies under `/tmp/opencode`). Artifact:
  `bench/shaman_apl_utility_build_2026-10-20.md`.
- **Decisions worth the trail:** the gap analysis's shaman section had FIVE
  errors, and the headline one is the brief's own premise — **there is no
  "Nature's Wrath" line to add**: the Era APL's i=4 row casts 17364, and
  17364 is **Stormstrike** (`classic sim/shaman/stormstrike.go:20`, the
  tree's own `WEAVE_STORMSTRIKE_SPELL_ID`, `bench/verify_bank.md` CONFIRMED);
  no fetched wowsims shaman sim has a Nature's Wrath ability at all. The
  other four: 29228 is Flame Shock r6 (not the Flametongue Weapon), the WotLK
  49231 is Earth Shock (not Lightning Shock; 49236 is the WotLK Frost Shock),
  the bench's Rockbiter id (10497) is Mana Spring r4, and the shipped `twist`
  id 8512 is the Windfury Totem rank-1 fallback (the TBC APL casts 25587 /
  25359 — filed, not changed). The Strength of Earth upkeep reads the client's
  **EARTH totem slot** clock (the water clock's shape, the tri-state the
  tree's totem readers use), not the buff: the slot clock is the read that
  exists in `compat.lua` today, and an unreadable slot never prompts. The
  TBC Frost Shock is the APL's ALTERNATIVE `Filler Shock` choice, so its arm
  answers only when the choice is stated (a frozen input the live gather
  never feeds — the APL's Earth Shock default stands) and rules 14/17 stay
  silent in that case.
- **Filed for the orchestrator:** the Lightning Shield maintain on SoD and
  Forever (a per-family gap in a SHIPPED line — the exact work is in the
  bench file §5); the Frost Shock choice as a real option (needs
  `option_tables.lua`, out of scope); the Chain Lightning enemy-count sensor
  (unchanged). The practice panel's scenario buttons grow by four (the strip
  grows with the button lines — cosmetic, practice_ui lane).
- **Crossfire:** the hunter and warrior lanes were editing
  `classes/hunter.lua` / `classes/warrior.lua` / `classes/druid.lua` in the
  same tree during this session (`classes/warrior.lua` was mid-edit with
  Lua 5.1's "more than 200 local variables" error at 02:01, and the warrior
  and druid files changed again at 02:06). The full-harness run at that
  moment showed the warrior/hunter/bars/hud/rotationtext/secret_guard/smoke
  steps red — none of them in this lane's scope and none caused by it; this
  lane's three suites were green throughout. The orchestrator owns the final
  harness run on a settled tree.
- **Next step:** the orchestrator validates (the full harness on a settled
  tree, then the in-client checklist for the four new prompts: the totem
  upkeeps' earth/water slot reads, the Bloodlust cooldown, the Frost Shock
  choice).

## 2026-10-20 — [signal:done] The APL utility layer landed
- `desks/shaman-apl/.signals/2026-10-20T06-07-14Z.json` (execution/done,
  run_id `shaman-apl-2026-10-20`).
- The signal's headline: the gap analysis's "Nature's Wrath" line does not
  exist (17364 is Stormstrike on every client) — the proof is in
  `bench/shaman_apl_utility_build_2026-10-20.md` §3 C1, and no line was built
  on the Stormstrike id.
