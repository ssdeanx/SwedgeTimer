# hunter-drills — Journal

## 2026-10-19 — Desk opened
- **Purpose:** the hunter half of the practice build: the rotation scenario, the audited
  drill set and the class-side feature closures from the audit's §2.3 (A) — the rows
  that need no new external data (Serpent / LnL / ISS / Readiness / Black Arrow).
- **Scope:** `classes/hunter.lua`, `hunter_guide.lua`, `hunter_ui.lua` (untouched),
  `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`. Out of scope: the shared
  engine (`practice.lua`, `practice_ui.lua`, `practice_progress*.lua`), the options
  and config files, every other class, `main.lua`, `diag.lua`, `compat.lua`, `hud.lua`,
  `bars.lua`, `run.sh`, the TOCs, the versions, the docs. No git, no lint-config change.
- **Next step:** read `bench/class_features_drills_2026-10-19.md` §2.3 and the shared
  engine's contract block in `practice.lua`, then build the three contract fields and
  the pins.

## 2026-10-19 — The hunter practice surface landed
- **Worked on:** the three contract fields (`practice_rotation` with the per-family sim
  priority slices and a source citation per entry, `practice_scenario_step`,
  `practice_drills` with the audit's four drills), plus the engine's optional
  accessors (`practice_rotation_for`, `practice_rotation_family`, `practice_scenario_key`,
  `practice_context`), the pure clip-margin helper in `hunter_guide.lua`
  (`st.hunter_guide.cast_margin`), and the class-side feature closures: the Lock and
  Load gather wiring (the audit's H-05, on the class's own existing throttled aura
  probe), the Serpent guard's semantics (H-03 — withhold only on a KNOWN-down sting),
  the sourced Serpent ranks and the Wrath Lock-and-Load source traps (H-04/H-16), the
  Readiness facts and the reset list (H-17), and the ISS id and duration (H-18).
- **Current state:** `tests/hunter_state.lua` 1046 PASS, `tests/hunter_guide_state.lua`
  1397 PASS, luacheck 0/0 in the touched files and the tree floor (2 warnings / 0
  errors) held. Full harness 41 steps / 0 failed on the tree as it stood; the final
  re-run showed two failures in the **shaman lane's** suites (its guide grew to 17
  slots mid-flight — `shaman_state`, `shaman_guide_state`, `hud_state`'s shaman pins),
  both green in the hunter's own suites. 8/8 mutation proofs killed on
  `/tmp/opencode/mut_hunter` copies (script: `/tmp/opencode/mut_hunter/mutate.sh`).
  Report: `bench/hunter_rotation_drills_2026-10-19.md`.
- **Dead ends worth remembering:** (a) the drill press carries **no player action**
  (`practice_ui.lua:4812` builds the ctx with `last_action = nil`), so the first
  drill design (comparing a pressed action) could never grade in the panel — the
  drills were rebuilt as **moment judges** with the pick read from the ctx when the
  class's own ctx injects it (the live cast); (b) the engine's cooldown map is keyed
  by the gathered input **without** its `_remaining_cd` suffix (`kc`, `bw`,
  `killshot`), not by the action key — the class reads the engine's names and keeps
  the action key as an alias; (c) the cast-shot lookup must be by the guide's **input**
  family, not the action: the Wrath Aimed is instant on WotLK, so `wrath_aimed` is
  not a cast shot and reading it as one graded every Wrath clip as F; (d) the engine's
  default ctx path reads an **undefined `SCENARIO_RESOURCE_KEYS`**
  (`practice_ui.lua:4325`) and would raise on the first scenario tick — the hunter is
  immune (it publishes its own `practice_context`), every class that does not is not
  (engine lane's fix; filed in the bench report §5).
- **Filed for the owner (not done here, out of scope):** the Serpent **target-debuff**
  read (compat.lua exposes no target-aura scan → the upkeep and the naked-Chimera
  guard stay dormant); the guide's trap slot (the Wrath six-slot set is full, so the
  Black Arrow / Explosive Trap tier is tracked by the trap machine but never
  prompted); the guide's Readiness arm (no slot) and the ISS arm (per
  `bench/hunter_open_2026-10-19.md` §1 the engine must **not** branch on it); the
  pre-pull opener's offset reading (the bench read the TBC `currentTime <= 0.5s` entry
  as a pre-pull, the APL reads it as the first half second **of the fight** — the
  bench's reading is superseded in the drill); the in-client `GetSpellInfo` reads for
  every new id (Serpent 13554/25295/49001, Black Arrow 63672, Explosive Trap 49067).
- **Next step:** orchestrator validation (owns Done). The engine lane may want the
  `practice_rotation` consumer: the table is a **per-family map**
  (`ST.HUNTER.PRACTICE_ROTATIONS[family]`) with `ST.HUNTER.practice_rotation` holding
  the running client's slice — the sibling lanes' flat `entry.family` filter does not
  apply here.

## 2026-10-19 — [signal:done] The hunter practice surface landed
- Signal `desks/hunter-drills/.signals/2026-10-19T22-10-00Z.json` (done).
- 4 files touched in scope only (`classes/hunter.lua`, `hunter_guide.lua`,
  `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`); `hunter_ui.lua` needed no
  change (the feature closures live in the class and the guide). The bench report is
  NEW (`bench/hunter_rotation_drills_2026-10-19.md`). Harness 41 steps / 0 failed
  (the two later reds are the shaman lane's mid-flight slot growth); luacheck floor
  held (2/0 tree, 0/0 touched); 8/8 mutations killed.
