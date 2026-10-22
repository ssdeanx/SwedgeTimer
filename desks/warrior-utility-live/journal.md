# warrior-utility-live — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Make the warrior's APL utility lines LIVE — the thirteen rows the
  build lane (`desks/warrior-apl`) shipped as documentation (`live = false`,
  "no engine rule can ask for them yet") get the frozen engine's arms and the
  live reads, so the practice scenario can ask for them and the guide can light
  them. The pre-pull table goes into the practice flow the way the hunter's
  does, and the flags follow the orchestrator's HU-13 ruling (two flags:
  `live` = the read exists, `engine` = the engine has an arm).
- **Scope:** `classes/warrior.lua`, `warrior_guide.lua`, `tests/warrior_state.lua`,
  `tests/warrior_guide_state.lua` only. One new bench file
  (`bench/warrior_apl_utility_live_2026-10-20.md`). No git, no lint-config
  change, no TOC / version / option change, no other class touched.
- **Source of truth:** `bench/warrior_apl_utility_build_2026-10-20.md` (the
  build lane) and `bench/rotation_gap_vs_apl_2026-10-20.md` section 1.
- **Next step:** the engine arms, the provider's reads, the pre-pull drill, the
  honest flags, the pins, and the mutation proofs on `/tmp/opencode` copies.

## 2026-10-20 — The arms are wired; the rows are live
- **Worked on:** re-fetched the seven warrior APL files (the SoD / Era / TBC /
  Forever / WotLK priority lists) and read the sims' own `stances.go` and
  `overpower.go`, so the stance and Overpower conditions came from the files
  rather than from the gap analysis. The engine gained the utility spine
  (`utility_line_due`, `utility_spine_pick`, `utility_stance_action`,
  `utility_weave_stance`) and the four new matrix positions (W0 the weave's
  first step, U1 the HIGH rows, M the stance upkeep, U2 the LOW rows). The
  class module gained `WARRIOR_UTILITY` (the one source of truth for the ids,
  the family gates, the labels, the citations and the guide slots), the aura
  walk's buff stamps, the gather's utility reads, the generated rotation block
  2 and the `warrior_prepull` drill. 412513 (the SoD Gladiator Stance) is now
  in `WARRIOR_STANCES.ids`. The PRACTICE surface feeds the utility rows too
  (the shared engine's ctx carries their cooldowns and flags), so the
  scenario can ask for a row - the whole point of the lane.
- **Current state:** `bash tests/run.sh` → **41 steps, 0 failed** (the whole
  tree is green again — the rogue lane's in-flight step healed while this lane
  ran). `tests/warrior_state.lua` PASS (1635 checks), `tests/warrior_guide_state.lua`
  PASS (2019 checks), luacheck 0/0 on this lane's four files, **13/13 mutants
  killed** on the `/tmp/opencode` copy. Bench:
  `bench/warrior_apl_utility_live_2026-10-20.md`.
- **Next step:** the orchestrator validates. Filed residuals: the APL's
  target-count / Bloodlust-alignment / rune-aura gates are not modelled (no
  read exists for them, so the rows are asked for on their cooldown + buff
  gates alone); the Gladiator Stance row has a read but no arm
  (`engine = false`); no `practice_rotation_for` for the warrior (the build
  lane's separate follow-up).
