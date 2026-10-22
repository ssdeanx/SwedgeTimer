# Practice Neutral Actions — Journal

## 2026-10-20 — Desk opened
- **Purpose:** the NEUTRAL action concept in the practice engine — a legitimate action the rotation does not ask for (a heal, a shield, food, a potion, a movement ability) must NOT read as a mis-pick.
- **Scope:** `practice.lua` (the pure engine), `practice_ui.lua` (the panel), `tests/practice_state.lua`, `tests/practice_ui_state.lua`. The per-class sets are a SIBLING lane's job (`classes/*.lua` — out of scope here).
- **Next step:** build the mechanism + the accessor, keep the default behaviour identical until a class publishes a set.

## 2026-10-20 — Engine + UI half landed
- **Worked on:** `H.practice_neutral_actions(class_key) -> set | nil` (flat or family-scoped publish, nil-safe, unknown-hides, hands out a copy); the `neutral` outcome in `H.rotation_run_decide(run, expected, actual, hold, neutral)` with NO entry in `H.ROTATION_OUTCOME_GRADES` (no attempt, no points, no streak, no XP); the run's `neutral` tally and the summary counter; the UI (`ui.scenario_neutral` on the `ui` table — no new file-scope local, the file sits at 199/200) showing `NEUTRAL` in the popup and the status line and reporting the count in the run summary + the panel readout; +54 checks in `tests/practice_state.lua` (`neutral_tests()` in its own frame) and +31 in `tests/practice_ui_state.lua` (22m/22n/22o).
- **Current state:** harness **41 steps, 0 failed**; luacheck **2 warnings / 0 errors** (both pre-existing, KEEP-ruled; the 4 touched files are 0/0); `practice_ui.lua` file-scope locals still **199**; CRLF kept in both addon files. Mutation proofs **3/3 killed** on `/tmp/opencode/mut_neutral` copies: `neutral = "F"` in the grade map; the accessor ignoring the published set; the UI dropping `ui.scenario_neutral`.
- **Judgement calls (the orchestrator may rule otherwise):** a HOLD beats the neutral set (HU-8 stays: a cast during a hold is an illegal cast, so the grading cannot be made free); the rotation action beats the neutral set (`actual == expected` → `correct`); the neutral press CLOSES the step like every other press; the neutral step is neither a hit nor a mis-pick (excluded from the run band, so a neutral-only run reads UNKNOWN); the popup colour is the hit colour (like HOLD OK).
- **Next step:** the sibling lane publishes the per-class sets against the contract in `bench/practice_neutral_actions_2026-10-20.md` — the accessor answers nil until a class publishes, so the shipped behaviour is unchanged until then.

## 2026-10-20 — [signal:hands-up] HOLD vs NEUTRAL precedence
- One call is the operator's: a cast during an explicit HOLD stays an ILLEGAL CAST (F) even when the action is neutral. I chose **hold-wins** (HU-8 stands; a neutral press must not make the grading free), pinned by `a cast during a hold is an illegal cast, neutral or not`. The literal task wording could be read the other way — the orchestrator may rule neutral-wins; the change would be local to `H.rotation_run_decide` and its pins.
- Signal: `.signals/20261020T180023Z-hands-up.json`.

## 2026-10-20 — [signal:done] Engine + UI half landed
- Artifact: `bench/practice_neutral_actions_2026-10-20.md` (the contract the sibling lane codes against). Harness 41/0, luacheck 2/0, 199 file-scope locals preserved, 3/3 mutation proofs killed.
- Signal: `.signals/20261020T180105Z-done.json`.

## 2026-10-20 — The class lane landed against this contract (observed)
- The sibling lane's `tests/neutral_actions_state.lua` re-implements the resolution rule independently and **passes (720 checks)** against the classes' published sets (paladin flat, rogue/warrior family-scoped, shaman empty) — the accessor here and the class lane agree.
- Consequence to note: a family the class published **no bucket** for reads as "no neutral set" → every non-rotation press stays a mis-pick (the rogue on TBC, the warrior off FOREVER). That matches the class lane's own expectation (an empty set on those slices).
- **Next step:** nothing outstanding here — the mechanism is landed, pinned and mutation-proven; the orchestrator owns the reconciliation of the two lanes and the hold-vs-neutral ruling.

