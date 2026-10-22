# superseded-wrappers — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Close the engine lane's open item (bench/practice_scenario_engine_2026-10-19.md
  §5 + §9): the class wrappers started the SUPERSEDED built-in drill session directly,
  so a class's own drill was not what the class's session ran. Also drop the shaman
  namespace alias stopgap (HU-7) now that the engine resolves the class module from
  the AceAddon table first.
- **Scope (fixed by the orchestrator):** `classes/druid.lua`, `classes/shaman.lua`,
  `classes/warrior.lua`, `tests/druid_state.lua`, `tests/shaman_state.lua`,
  `tests/warrior_state.lua`. OUT: `practice*.lua`, `option_tables.lua`,
  `config*.lua`, `main.lua`, `diag.lua`, `compat.lua`, `hud.lua`, `bars.lua`, the
  guide files, `run.sh`, TOCs, versions, README/CHANGELOG/docs, git, lint-config.
- **Sibling lane:** `shaman-slots` was editing `classes/shaman.lua` (LS/CoE/Searing
  guide slots) while this lane ran. It closed before this lane's shaman edits; the
  shaman edits were kept to the two briefed points (the alias removal + the wrapper
  re-point) plus the published drill key.
- **Next step:** read the bench + the engine lane's artifact, then re-point the three
  class wrappers and pin that a wrapper still starting the built-in fails.

## 2026-10-19 — The wrappers now run the class's OWN drill
- **Worked on:** each class publishes `PRACTICE_DRILL_KEY` +
  `practice_drill_key()` (the class's own drill that owns the superseded skill:
  `druid_powershift_rework`, `shaman_mw_weave`, `warrior_execute_burn`); the druid
  and shaman wrappers build a session for THAT drill (the harness's shared energy /
  weave primitives as the state, the class's own grade function as the only truth);
  the shaman alias `st.SHAMAN = ST.SHAMAN` is gone; the warrior names its drill and
  its live-feed rows carry that drill key.
- **Kept on purpose:** `practice_scenario_key()` still names the retired built-in -
  it is the engine's ROUTING key (practice_ui's `use_*_drill()` and the engine's
  supersession rule read it), and the built-in must keep resolving for backward
  compatibility.
- **Current state:** harness 41 steps / 0 failed; luacheck 2 warnings / 0 errors (the
  floor); druid_state 911, shaman_state 670, warrior_state 1153, shaman_guide_state
  1378; wiring_check 589/0; mutations 7/7 killed on /tmp/opencode/mut_swd.
- **Next step:** the orchestrator validates. Two items are filed for other lanes in
  bench/superseded_wrappers_2026-10-19.md §6: the panel map's `mode` (engine lane)
  and the one out-of-scope pin in tests/shaman_guide_state.lua.

## 2026-10-20 — [signal:done] the class wrappers run their own drill; the shaman alias is gone
- 41/0 harness, luacheck floor held, 7/7 mutations killed, pins green in the four
  touched suites; one scope exception recorded (tests/shaman_guide_state.lua's alias
  pin). Artifact: bench/superseded_wrappers_2026-10-19.md.
- Validation owner: orchestrator.
