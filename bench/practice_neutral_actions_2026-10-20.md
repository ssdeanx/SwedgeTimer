# The NEUTRAL action — the engine contract (2026-10-20)

**Desk:** `practice-neutral-actions` · **Scope:** `practice.lua`, `practice_ui.lua`,
`tests/practice_state.lua`, `tests/practice_ui_state.lua` · **Status:** landed, harness green.

## The problem (operator order)

The practice panel offers the class's whole ability list, so a player legitimately
presses a common spell that the rotation never asks for (a heal, a shield, food, a
potion, a movement ability). That press was graded `out_of_order` → **F** → a
mis-pick, a broken streak and a decayed band. The player did nothing wrong.

## The contract (for the class lane)

A class publishes its neutral action keys on its own module:

```lua
-- flat: the same set on every client
ST.PALADIN.practice_neutral_actions = { heal = true, shield = true }

-- per family: one bucket per family the class describes
ST.PALADIN.practice_neutral_actions = {
    ERA = { heal = true },
    TBC = { heal = true, food = true },
}
```

- The keys are **action keys** — the same vocabulary the panel's buttons use
  (`practice_rotation_entries` / the guide slot keys / the keys the class asks for).
- The value must be exactly `true`. Anything else is not a member.
- A family-scoped publish is recognised by a **table-valued** entry; the bucket for
  the current family (`st.family`) is used. A family the class published no bucket
  for answers **nil** — the engine never guesses a set.
- A class that publishes **nothing** keeps today's behaviour exactly: every
  non-rotation press is a mis-pick (F).

The engine reads it through one accessor, next to the existing
`H.practice_drills` / `H.practice_scenario_step` pair:

```lua
H.practice_neutral_actions(class_key) -> set | nil
```

It takes a class key **or** the class module, is nil-safe, answers nil for an
unknown class, and hands out a **copy** of the published set (never the table
itself).

## The engine (`practice.lua`)

`H.rotation_run_decide(run, expected, actual, hold, neutral)` — the fifth argument is
the class's set (nil when the class published none).

Outcome order (the first match wins):

| # | condition | outcome | attempt? |
|---|---|---|---|
| 1 | the class stated a HOLD and something was cast | `illegal_cast` | yes (F) |
| 2 | the class stated a HOLD and nothing was cast | `hold_ok` | no |
| 3 | `actual == expected` | `correct` | yes (S) |
| 4 | `actual` is in the neutral set | `neutral` | **no** |
| 5 | no expectation | `unknown` | no |
| 6 | nothing was cast | `miss` | yes (F) |
| 7 | anything else | `out_of_order` | yes (F) |

`H.ROTATION_OUTCOME_GRADES` has **no** entry for `neutral` — that absence IS the
rule (the same mechanism the correct hold uses): the step records no attempt, so no
points, no streak, no mastery tick, no XP, and it is **not** a mis-pick.

The run carries a `neutral` tally (`run.neutral`, `summary.neutral`); the neutral
step is excluded from the run band (`graded = correct + mispicks`), so a run of
nothing but neutral steps reads UNKNOWN — never a perfect S.

## The UI (`practice_ui.lua`)

- A neutral press shows **`NEUTRAL`** in the result popup and in the status line
  (`NEUTRAL: <action> - not a rotation action`), and the popup is **not** the miss
  colour (it reads like `HOLD OK`).
- No attempt is recorded → the score, the streak and the XP do not move.
- The run summary (the row's status line) and the panel's readout report the
  neutral count — **only when the count is > 0**, so a class with no published set
  reads exactly as before (no default-visible change).

## Judgement calls (the orchestrator may rule otherwise)

1. **A HOLD beats the neutral set.** A cast during an explicit HOLD stays an
   ILLEGAL CAST (F), even when the action is neutral. HU-8 is an operator ruling
   and the prompt says "next: HOLD"; letting a neutral press dodge it would make
   the grading free (spam a heal through every hold). Pinned by
   `a cast during a hold is an illegal cast, neutral or not`.
2. **The rotation action beats the neutral set** (`actual == expected` → `correct`),
   so a class that mis-publishes a rotation action still gets its hit.
3. **The neutral press CLOSES the step**, like every other press: the rotation's
   window is spent, but nothing is penalised. Re-opening the window would need a
   two-press step model and was not asked for.
4. **The popup colour is the hit colour**, like `HOLD OK`: a neutral action is no
   mistake, so it must not read as a miss.

## Verification

- Harness: **41 steps, 0 failed**; luacheck **2 warnings / 0 errors** (both
  pre-existing and KEEP-ruled; the 4 touched files are 0/0).
- `practice_ui.lua` file-scope locals: **199** (unchanged — the new state rides the
  `ui` table; the 200th is a load failure).
- Line endings: CRLF kept in `practice.lua` / `practice_ui.lua`, LF in the test files.
- Checks added: `tests/practice_state.lua` +54 (`neutral_tests()`), 
  `tests/practice_ui_state.lua` +31 (22m / 22n / 22o).
- Mutation proofs on `/tmp/opencode/mut_neutral` copies — **3/3 killed**:
  | mutant | killed by |
  |---|---|
  | `neutral = "F"` in `H.ROTATION_OUTCOME_GRADES` (a neutral action records an attempt) | `practice_state` + `practice_ui_state` |
  | the accessor ignores the published set | `practice_state` (16 FAILs) + `practice_ui_state` (12 FAILs) |
  | the UI drops `ui.scenario_neutral` at the call site | `practice_ui_state` (11 FAILs), `practice_state` green |

## The class lane landed against this contract (observed 2026-10-20)

The sibling lane's `tests/neutral_actions_state.lua` re-implements the resolution
rule independently ("the engine's own rule") and **passes (720 checks)** against the
classes' published sets — so the accessor here and the class lane agree:

- `ST.PALADIN.practice_neutral_actions` — flat: `sotc, aw, hpot, abacus, stop`.
- `ST.ROGUE.practice_neutral_actions` — family-scoped: `ERA = { coldblood }`,
  `WRATH = { coldblood, shiv }`, `FOREVER = { shiv, ... }`.
- `ST.WARRIOR.practice_neutral_actions` — family-scoped: `FOREVER = { cleave }`.
- `ST.SHAMAN.practice_neutral_actions` — `{}` (empty → the accessor answers nil →
  the shaman keeps today's behaviour).

Two consequences worth the orchestrator's eye:
- A family the class published **no bucket** for (the rogue on TBC, the warrior
  everywhere but FOREVER) reads as **no neutral set** → every non-rotation press
  stays a mis-pick. That matches the class lane's own expectation (an empty set
  for those slices).
- The class lane's grading-integrity pin ("no published neutral key may be a
  rotation action on the slice it is published for") is satisfied by the
  precedence here: the engine grades the EXPECTED action first, so a rotation
  press still hits even if a class mis-publishes it.

## UNCONFIRMED / not proven here

- **In-client:** the popup, the status line and the summary text are offline-proven
  only (the sandbox drives the real `practice_ui.lua`); the in-client look and the
  per-class key sets are the operator's / the class lane's to confirm.
- **The per-class sets** are a sibling lane's job — this lane builds the mechanism
  and the accessor only, and ships with **no** class publishing a set, so the
  shipped behaviour is unchanged.
