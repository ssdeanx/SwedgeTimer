# warrior-hs-queue — Journal

## 2026-10-20 — Desk opened
- **Purpose:** the operator's Heroic Strike / Cleave queue drill (a first-class
  drill in the warrior's own drill list) + the two warrior items the closure
  sweep filed: W-15 (the Forever Rend provider read) and W-21 (the
  Sunder/Rend/Hamstring HUD mirror).
- **Scope:** ONLY `classes/warrior.lua`, `warrior_guide.lua`,
  `tests/warrior_state.lua`, `tests/warrior_guide_state.lua`,
  `tests/hud_state.lua` (**warrior census only**). Out: `practice*.lua`,
  `option_tables.lua`, `config_presets.lua`, `compat.lua`, the other classes,
  `main.lua`, `diag.lua`, `hud.lua`, `bars.lua`, `run.sh`, the TOCs, the
  versions, README/CHANGELOG/docs. No git, no lint-config changes.
- **Next step:** fetch the sim sources for the offhand mechanic, then build the
  drill + the two filed items and validate them.

## 2026-10-20 — The drill landed (with its citations), W-15 and W-21 closed
- **Worked on:** (1) **The HS/Cleave queue drill** — `warrior_hs_queue`, the
  fifth entry in `ST.WARRIOR.practice_drills`. The sim states the mechanic
  outright (`wowsims/tbc-new sim/warrior/heroic_strike_cleave.go`: "The queue
  lifts the dual-wield miss penalty"; the same `DisableDWMissPenalty = true` on
  the queue aura in classic/sod/tbc-new/forever; the penalty it lifts is
  +19 % in `sim/core/spell_outcome.go`, over a 5 % white base in
  `sim/core/target.go:312` → 24 % together; the queue replaces the mainhand
  swing, so the window is the gap between the mainhand's last swing and the
  offhand's next one). The pure verdict (`st.warrior_guide.hs_queue_grade`)
  and the margin bands (`hs_queue_band`) live in `warrior_guide.lua`; the
  readings are the addon's OWN swing data (the gather's new
  `offhand_swing_remaining` + `dual_wielding`, beside the shipped
  `swing_remaining` + `speed`). Grades: F outside the window (too early = the
  ability fires before the offhand swing; too late = the offhand already
  swung), S/A/B/C/D on the margin (250/150/80/20 ms). The sim's own 250 ms
  queue delay is exposed as a cited constant but deliberately NOT used as a
  window edge — it is the sim's reaction-time MODEL, and the in-client lift
  timing is **UNCONFIRMED IN-CLIENT**. The operator's "7 % spell cap" is
  carried as the operator's in-client figure, never as a sim number.
  (2) **W-15** — the Forever Rend provider read landed
  (`elseif is_forever_guide and db.guide_forever_rend_upkeep == true`): the
  key ships (options pass), the rule was dormant, now the toggle arms it.
  Nil = off, family-scoped, the stale "toggle filed" comment gone.
  (3) **W-21** — the Sunder mirror joins the TBC HUD row (9 slots) and the
  three maintenance slots became display-only mirrors: Sunder/Rend return
  before the cooldown read (no cooldown of their own to ride), Hamstring
  keeps the rotational GCD path, and each hides unless its `hud_show_<key>`
  reads exactly true (nil = off, the druid-Claw shape).
- **Current state:** harness **41 steps / 0 failed**; luacheck **2 warnings / 0
  errors** (the standing floor: `compat.lua:36` + `main.lua:81`, files this
  lane never touched). Suites: warrior_state 1182, warrior_guide_state 1728,
  hud_state 682 — all green; the hud suite grew by exactly the seven new
  warrior pins, so no other class's census moved. Line endings kept (the two
  class files CRLF, the three suites LF). **30 / 30 mutations killed, 0 void**
  on a `/tmp/opencode/mut_warrior` copy. Bench artifact:
  `bench/warrior_hs_queue_2026-10-20.md`.
- **Filed for other lanes:** (F-1) `hud_show_sunder = false` in
  `config_presets.lua` if the operator wants the TBC mirror off by default
  (the gate is nil-off, the shipped key is on — the options lane's file);
  (F-2) the stale "Show the Rend icon (with its GCD swipe)" description in
  `option_tables.lua:4050` (the Rend mirror no longer rides the GCD swipe);
  (F-3) the shared registration of the new drill (the engine owns it; the class
  list wins over the fallback map, so nothing is needed for the drill to
  appear); (F-4) the in-client confirmation of the queue window.
- **Next step:** the orchestrator validates. If the operator rules that the
  TBC Sunder mirror must ship hidden, the options lane flips that one default
  (the gate needs no change).

## 2026-10-20 — [signal:checkpoint] one open operator decision
- The TBC HUD row now carries one more visible icon than before: the Sunder
  mirror shows because `config_presets.lua` ships `hud_show_sunder = true`
  (the options lane's documented "the union of the family sets ships on"). The
  mirror GATE is the druid-Claw shape (`== true`, so nil = off) ✓ — only the
  shipped VALUE is on, and that file is the options lane's. Accept it as is,
  or let the options lane flip the one default; the gate needs no change.
- Evidence: `bench/warrior_hs_queue_2026-10-20.md` §4.3.

## 2026-10-20 — Close: the tree's crossfire is the sibling lanes', not this lane's
- **Worked on:** a final validation sweep after the sibling lanes landed the
  HU-8 change ("hold is a decision") in the shared engine: the class lanes'
  scenario-step pins are catching up (at this close: `tests/shaman_guide_state`
  and `tests/hunter_guide_state` red, earlier `tests/rogue_state` and
  `tests/paladin_state`; the luacheck floor moved 2 → 3 with a new warning in
  `tests/paladin_state.lua:2890`).
- **Current state:** **this lane's own files are clean** — `warrior_state`
  1182 ✓, `warrior_guide_state` 1728 ✓, `hud_state` 682 ✓, `guide_contract`
  1042 ✓, `practice_state` 1478 ✓, and luacheck **0 warnings / 0 errors** on
  the five lane files. Every red in the tree is in a sibling lane's file, which
  that lane owns; the harness was **41 steps / 0 failed** when this lane's
  last edit landed (the reds appeared afterwards, from the parallel class
  lanes' own edits).
- **Next step:** the orchestrator validates and reconciles the crossfire.
