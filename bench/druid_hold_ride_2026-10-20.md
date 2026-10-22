# bench/druid_hold_ride_2026-10-20.md — the druid's press-nothing hold (the deep-audit's H1)

Desk: `druid-hold-ride`. Date: 2026-10-20. Validation owner: **orchestrator**.

The druid was the only class of six that turned the guide's HOLD into a synthetic
ACTION. Nine of the guide's ten hold texts mean *"cast this spell"* (the guide has no
slot for the spell, so the hold overlay names it) and those were right. **One is not:
`"RIDE"`** — the bear chain's queued Maul, where the guide rides the queue the player
already placed, so the player presses **nothing**.

---

## 1. The defect (verified, file:line)

* `classes/druid.lua` `druid_expected` mapped EVERY hold text to an action key
  (`DRUID_HOLD_KEYS[out.hold_text]`, with a slugified fallback), so the guide's
  press-nothing hold became a synthetic `"ride"` action.
* `druid_guide.lua`'s rule 1 (the bear chain) is the source of that text:
  `maul_queued -> no action, hold = true, hold_text = "RIDE"` — the guide already
  said "no action"; only the class's practice adapter invented one.
* Consequences (both directions wrong):
  * the player presses nothing (correct) → the engine reads it as a **miss → F**
    (the streak breaks and the band decays);
  * the player presses the rendered **"ride"** button → **correct → S with points** —
    points for idling, which the engine's contract forbids (`practice.lua`'s hold
    statement: a correct hold records no attempt, so idle time cannot be farmed);
  * the class's own priority drill (`expected == actual` against the synthetic
    `"ride"`) banked a **false mis-pick** for every real pick.

## 2. The fix (the shape the other five classes already use)

`classes/druid.lua`:

1. The guide's hold vocabulary is split in two, as two published tables next to each
   other (one source of truth for the class's practice vocabulary):
   * `ST.DRUID.PRACTICE_HOLD_KEYS` — the nine **spell-naming** holds → the action key
     to press (`TIGER'S FURY` → `tigers_fury`, …). Unchanged behaviour.
   * `ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING` — the ONE **press-nothing** hold
     (`RIDE` → true). It never becomes a key.
2. `druid_expected` answers a press-nothing hold with **no action** and the guide's
   own caption (`nil, "RIDE"`); a spell-naming hold still answers its key.
3. `ST.DRUID.practice_scenario_step` states the press-nothing hold as
   `{ action = nil, hold = true, reason = "RIDE" }` — the engine's own contract: a
   cast during it is an **illegal cast (F)**, doing nothing during it is **correct
   but worth no points**.
4. The priority drill (`druid_finisher_order`) **skips the hold step**: it answers
   nil (UNKNOWN → no attempt), so a hold never banks a mis-pick.

No general hold concept was invented for the druid: the nine spell-naming holds stay
actions, exactly as before.

`druid_guide.lua` — comments only (the verdict is unchanged): rule 1, the B1 appendix
row and the code comment now say that `RIDE` is the **press-nothing** hold.

## 3. The pins (the audit's own gap — the old suite could not see this)

`tests/druid_state.lua` §41 (new): the RIDE hold is **never** graded as an action —
the step names no action and states `hold = true` with the guide's caption; the
shared engine's accessor keeps the hold statement; the three states through
`H.rotation_run_decide` (a cast → `illegal_cast`/F/an attempt; nothing → `hold_ok`/
no attempt/no points; unknown → unknown/no attempt); the priority drill grades
nothing on a hold and its window banks **no mis-pick** (`state.druid_priority_window`
stays nil); the published rotation slices carry **no "ride" key** and the class never
asks the panel for one; the class's hold vocabulary has exactly one press-nothing
hold and "RIDE" is in neither spell-naming table. A **spell-naming hold still grades
as that spell** (the Tiger's Fury hold → `tigers_fury`, and the drill grades that
pick an S).

`tests/druid_guide_state.lua` §21 (new): the guide's hold vocabulary is **closed** —
every `hold_text` the guide can write (read out of the source) is covered by exactly
one of the class's two tables, "RIDE" is the only press-nothing one, and no hold text
maps to the "ride" key. A new hold text in the guide fails this pin, so it can never
be graded by a guessed slug.

The two stale pins that asserted the old (wrong) behaviour were **re-cut, not
deleted**: the "queued Maul is a press too" pin now reads "the queued Maul names no
action: RIDE means press nothing" + "the queued Maul states an explicit hold".

## 4. Mutation proofs — 5 of 5 killed

Disposable copy: `/tmp/opencode/druid-hold-mut` (a copy of the tree; the repo tree is
never touched). Script: `/tmp/opencode/druid_hold_mutations.py`.

| # | mutation | killed by |
|---|---|---|
| M1 | **the RIDE hold is graded as an action** (the press-nothing branch is gone) | `druid_state` — 12 checks: the step names no action, the hold statement, the engine's three states (`out_of_order` instead of `illegal_cast`, `miss` instead of `hold_ok`, F instead of no attempt), the drill grades A instead of nothing, the drill banks a mis-pick, the class asks for a "ride" key |
| M2 | **every hold becomes a press-nothing hold** (the spell-naming holds are lost) | `druid_state` — "a Tiger's Fury hold is the spell key", "a spell-naming hold still grades as that spell", "the priority drill grades the named spell as a hit" |
| M3 | the priority drill grades a hold as an action (the hold skip is gone) | `druid_state` — "the priority drill grades nothing on a hold" + "banks no mis-pick on a hold" |
| M4 | the class's press-nothing table is emptied (RIDE falls back to a key) | `druid_state` + `druid_guide_state` |
| M5 | the guide's RIDE verdict names an action again (the guide stops holding) | `druid_state` + `druid_guide_state` |

## 5. Verification

* `bash tests/run.sh` → **41 steps, 0 failed**.
* luacheck → **2 warnings / 0 errors** (the shipped floor: `compat.lua:36`,
  `main.lua:81`); this lane adds none.
* The suites it owns: `druid_state` 1291, `druid_guide_state` 95944 — green.
* Line endings preserved: `classes/druid.lua` and `druid_guide.lua` stay CRLF
  (CR count == line count); the two test files stay LF. No trailing whitespace on
  any touched line.
* Nil-safe: both lookups are `type(...) == "table"`-guarded, so a missing table can
  never throw the step.
* **A sibling lane was writing `practice_ui.lua` / `tests/practice_ui_state.lua`
  during this lane.** One harness run in that window showed `practice_ui_state`
  red (its own badge/XP and daily-cap pins, mid-edit). Proven NOT to be this
  lane's: on the same tree with this lane's druid fix reverted, the identical four
  checks still fail (`/tmp/opencode/druid-hold-cross`, the fix reverted in place).
  The sibling lane finished its iteration and the harness is green again.

## 6. Files changed (this lane's scope — nothing else)

`classes/druid.lua`, `druid_guide.lua`, `tests/druid_state.lua`,
`tests/druid_guide_state.lua`.

**NOT touched** (out of scope by the dispatch): `practice.lua`, `practice_ui.lua`,
`option_tables.lua`, `config_presets.lua`, the other five class modules, `main.lua`,
`diag.lua`, `compat.lua`, `hud.lua`, `bars.lua`, `tests/run.sh`, the TOCs, the
versions, the docs. No git write, no lint-config change.

## 7. For the orchestrator

* **A bench claim is now superseded.** `bench/class_hold_statements_2026-10-20.md` §2
  states that the **druid has no hold concept** ("every guide hold names a spell to
  PRESS … and the bear's `RIDE` = the queued Maul"). That claim is the defect's
  origin: `RIDE` means PRESS NOTHING. The file was left untouched (a bench file is
  superseded by a pointer, not overwritten) — this file is the pointer.
* The CHANGELOG has no entry for this fix (docs are out of this lane's scope): the
  release pass owes one line.
* The central lane ledger (`desks/journal.md`) has no row for this lane: the
  orchestrator adds it on reconcile, with the session id exactly as returned by the
  dispatch.
* **In-client confirmation owed** (nothing offline can prove it): with a queued Maul
  in bear form, the practice panel shows the RIDE hold (no "ride" button), pressing
  anything during it grades F, and doing nothing grades correct-with-no-points.
