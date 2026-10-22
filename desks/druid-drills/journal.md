# druid-drills — Journal

## 2026-10-19 — Desk opened
- **Purpose:** the druid half of the practice build: the rotation scenario, the audited
  drill set and the class-side feature closures from the audit's §2.5.
- **Scope:** `classes/druid.lua` + `tests/druid_state.lua` only. No other file, no
  git, no lint-config change.
- **Next step:** read `bench/class_features_drills_2026-10-19.md` §2.5, the class
  contract in `practice.lua:3232-3250`, then build the three contract fields and the
  pins.

## 2026-10-19 — The druid practice surface landed
- **Worked on:** the three contract fields (`practice_rotation` with a per-family sim
  priority slice, `practice_scenario_step`, `practice_drills` with the audit's four
  drills), the ctx reader (the engine's `resources` / `cooldowns` shape, the stripped
  cooldown base names, the class's own gather as the fallback), the reason text (the
  state plus the engine rule id), the rotation-family helpers, the re-sourced
  powershift drill (the sim trigger, not the addon's 20-energy rule), and the two
  class-side feature closures: the Omen-ICD probe (DU-13, the proc buff as the
  witness) and the world-latency read (DU-22, the sim's `max(gcd, latency)` leeway).
  New drill-side gather fields: `sr_expired_seconds` and `sr_seen` (the Roar's own
  window; they reset with the fight).
- **Current state:** `tests/druid_state.lua` 903/903 PASS (+272 pins; the sandbox
  now loads `druid_guide.lua` so the step and the priority drill run the shipped
  engine), `druid_guide_state` 95 462 PASS unchanged, full harness 41 steps / 0
  failed, luacheck 2 warnings / 0 errors (the tree floor; both touched files 0/0).
  13/13 mutation proofs killed on `/tmp/opencode/mut_druid` copies (the copy is
  restored byte-identically; the baseline is green). Report:
  `bench/druid_drills_2026-10-19.md`.
- **Dead ends worth remembering:** (a) the first drill design graded the *player's
  action* — the engine's drill press carries none (`practice_ui.lua:4519`
  `scenario_context(now, nil)`), so the drills were rebuilt as moment judges; (b) the
  two new `ST.DRUID.*` helpers were dead hooks for the wiring check until the
  scenario step started calling them (the check counts a qualified call inside the
  owning module); (c) any new `GetSpellPowerCost` probe breaks the guide suite's
  cost-query counters (it pins "the cost is queried once"), so the trick-window
  costs are filed, not built; (d) a state merge written as `gathered and
  gathered[name] or nil` silently drops a proven `false` - the SoD S2 branch reads
  `tf_ready == false`, so the merge copies the value as it is (mutation M13).
- **Filed for the owner (not done here, out of scope):** the shipped
  `druid_powershift` registry entry (`practice.lua:2363`, the 20-energy bands at
  `:2279-2286`) still grades the addon's own rule — the owner should re-point or
  retire it in favour of `druid_powershift_rework`; the trick-window / pooling rules
  and the clipRoar glyph extension (engine side, `druid_guide.lua`); the in-game
  SHIFT prompt (the Furor talent has no sourced id/tab, so no honest probe exists);
  the Omen-ICD assumption (the ICD and the proc buff share one window) is
  UNCONFIRMED in-client.
- **Next step:** orchestrator validation. The engine lane may want a
  `practice_rotation` consumer (the table is a flat array; filter on `entry.family`).
  In-client confirmations owed: the Omen-ICD window, the ERA/SoD Shred cost (the
  drill's frozen 42 is the TBC spell data), the live bite / shred costs for the
  trick windows.

## 2026-10-19 — [signal:done] The druid practice surface landed
- Signal `desks/druid-drills/.signals/2026-10-20T01-05-00Z.json` (done).
- 2 files touched in scope only (`classes/druid.lua`, `tests/druid_state.lua`); the
  bench report is NEW (`bench/druid_drills_2026-10-19.md`); full harness 41 steps /
  0 failed; luacheck floor held (2/0); 13/13 mutations killed.
