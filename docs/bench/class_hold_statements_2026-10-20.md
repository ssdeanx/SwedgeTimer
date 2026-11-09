# bench/class_hold_statements_2026-10-20.md — the class-side half of HU-8: every class states its own hold

Desk: `class-hold-statements`. Date: 2026-10-20. Validation owner: **orchestrator**.

The engine half landed and is verified: `bench/shared_engine_bs8_2026-10-20.md`
(the accessor accepts a hold statement, the pure engine grades it, the UI shows
it). This lane is the **class half**: each class now *states* its hold explicitly,
so the engine can tell a hold (a decision) from unknown (cannot decide).

Files changed (this lane's scope):
`classes/paladin.lua`, `classes/rogue.lua`, `classes/shaman.lua`,
`classes/hunter.lua`, `tests/paladin_state.lua`, `tests/rogue_state.lua`,
`tests/shaman_state.lua`, `tests/shaman_guide_state.lua`,
`tests/hunter_guide_state.lua`, `tests/druid_state.lua`.
`classes/druid.lua` was **not** touched (the druid has no hold to state — §2).
**Scope files NOT touched, and why:** `classes/warrior.lua` (a sibling lane owns it
right now — its semantics are filed in §6 for that lane), `practice.lua`,
`practice_ui.lua`, `practice_progress.lua`, `option_tables.lua`,
`config_presets.lua`, `compat.lua`, `main.lua`, `diag.lua`, `hud.lua`, `bars.lua`,
`guide_contract.lua`, `hud_state.lua`, `run.sh`, the TOCs, the versions, the docs.
No git write, no lint-config change.

---

## 1. The contract the classes code against (read from the landed code)

`practice.lua`'s accessor (`H.practice_scenario_step`, `practice.lua:3450`):

```lua
if type(action) ~= "string" or action == "" then
    -- No action: the only non-unknown answer left is an explicit hold.
    if result.hold == true then
        return { action = nil, hold = true, reason = reason }
    end
    return nil
end
```

* a **hold statement** is a decision: casting during it is an illegal cast (F);
  doing nothing is correct and records **no attempt** (no points);
* a step with **neither an action nor a hold** stays UNKNOWN (no attempt, never a
  wrong grade);
* a step that names an **action** is an action (the hold flag is ignored).

## 2. What each class's OWN engine says, and what the class now states

| class | the real hold (the class's own engine verdict) | what the step states | source |
|---|---|---|---|
| **PALADIN** | the twist tree's RIDE window, and the FCFS "nothing is ready" | `{ action = nil, hold = true, reason = <the engine's own line> }` | `classes/paladin.lua:4733` `practice_key_from_engine` (already returned `nil, "hold: ..."`), `classes/paladin.lua:4792` `practice_decision` (already carried `hold = key == nil`) |
| **ROGUE** | the **POOL** verdict (the 1a hold: the rotation wants nothing cast until the energy window opens) | `{ action = nil, hold = true, reason = "POOL" }` | `rogue_guide.lua:1430` (`hold = true, hold_text = "POOL"`), `rogue_guide.lua:1760` `practice_step` (dropped it), `rogue_guide.lua:1742` `practice_reason` (the reason line) |
| **SHAMAN** | the guide's **RIDE** (a cast is in flight) and **WAIT** (the Stormstrike is fished) | `{ action = nil, hold = true, reason = "RIDE" / "WAIT" }` | `shaman_guide.lua:623` (RIDE), `shaman_guide.lua:689` (WAIT), `shaman_guide.lua:784` (`out.hold` / `out.hold_text`), `shaman_guide.lua:1011` `practice_step` (dropped it) |
| **HUNTER** | the guide's **RIDE** (a cast is in flight) and **HOLD** (out of range, or inside the hidden Auto-Shot window) | `{ action = nil, hold = true, reason = "RIDE" / "HOLD" }` | `hunter_guide.lua:738` (RIDE), `hunter_guide.lua:748` / `:797` (HOLD), `hunter_guide.lua:892` (`out.hold` / `out.hold_text`), `classes/hunter.lua:3352` `practice_decision` (returns the engine's own out table) |
| **DRUID** | **SUPERSEDED 2026-10-20 — the claim below was the defect.** The guide's holds split in two: nine name a spell to PRESS (`TIGER'S FURY`, `BERSERK`, `SAVAGE ROAR`, `FAERIE FIRE`, `SHIFTING POWER`, …) and **one is press-nothing** (the bear's `RIDE` = the queued Maul). The old text called the druid the "no hold concept" class and mapped every hold to a key — that mapping is exactly what the deep audit's **H1** found: a press-nothing hold became a synthetic action, so correct play (pressing nothing) graded **F** and an idle press graded **S with points**. Fixed by `bench/druid_hold_ride_2026-10-20.md` (druid-hold-ride lane): `ST.DRUID.PRACTICE_HOLD_KEYS` (the nine spell-naming holds) + `ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING` (RIDE) — the step states `{ action = nil, hold = true, reason = "RIDE" }` and the priority drill skips hold steps (no attempt, no mis-pick banked). | **now yes** — the press-nothing hold is stated as a hold | `ST.DRUID.PRACTICE_HOLD_KEYS` / `ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING`; `bench/druid_hold_ride_2026-10-20.md` |

**The druid is NOT the "no hold concept" class.** Its guide's `hold` is a *call* for nine
texts (the key is the spell's, not the overlay text) and a **press-nothing** for one
(`RIDE`) — the two are now distinguished explicitly. The paragraph below is the lane's
original reasoning and is kept for the record: the druid's step now proves it states
**no** hold (`step.hold == nil`) for both a Tiger's Fury state and a queued Maul — that
claim was the bug, and the 2026-10-20 fix supersedes it (the queued-Maul case now states
a hold; the Tiger's Fury case still names an action).

### The rule each class follows

* the hold statement comes from the class's **own engine verdict** (`out.hold` /
  `out.hold_text`, or the class's own `practice_decision.hold`) — never a guess;
* the **reason is the engine's own text** ("POOL", "RIDE", "WAIT", "HOLD", the
  paladin's "hold: ..." line) — never a re-written sentence;
* **nil-safe**: a missing guide, a throwing engine, a non-table verdict and an
  unreadable state all still answer nil (unknown);
* **unknown stays unknown**: a state the engine cannot read never becomes a hold
  (the class asks the engine *which* it was, instead of deciding).

## 3. The class-side pull-clock read (BS-8 item 2 / P-17)

`main.lua` publishes the live pull clock on the **addon object** (the AceAddon
table): `ST.pull_at`, `ST:set_pull_at`, `ST:set_pull_in`, `ST:pull_in_seconds`.
The ctx field the engine reads is `ctx.pull_at` (the absolute timestamp) and
`ctx.pull_in_seconds` (the countdown) — the same shape the engine's own
`practice_ui.lua` builder publishes (`practice_ui.lua:4316` `apply_pull_clock`).

**The three classes that publish a ctx builder now carry the moment themselves**
(`classes/paladin.lua`, `classes/rogue.lua`, `classes/hunter.lua`): a local
`practice_apply_pull_clock(ctx, now)` reads the clock off the addon object and
publishes `ctx.pull_at` / `ctx.pull_in_seconds`. Nil-safe by construction: an
unarmed clock publishes nothing, a non-numeric value is never published, and a ctx
that already carries a clock keeps it.

**The two classes with NO ctx builder (the shaman and the druid) reach the moment
through the shared engine's fallback builder** — `practice_ui.lua`'s
`scenario_context` falls through to the engine's own builder when the class
publishes none, and that builder ends in `apply_pull_clock(ctx, now)`. **No class
ctx builder was added for them on purpose:** the engine's fallback IS the single
source of truth for those two classes' ctx shape (it copies the gathered inputs
into the resource bag), and mirroring it in a class file would be a second copy
that can drift. The class suites pin the fact instead (a builder without the pull
read would fail the pin — mutation M10/M11).

**No default-visible change:** the engine's own `apply_pull_clock` already
published the same two fields on the same ctx in the shipped path, so the class-side
read changes nothing the player sees — it makes the class's own ctx self-contained
(and provable in the class's own suite).

## 4. The pins

Every class with a hold proves the **three states** through the shared engine's
own decision (`H.rotation_run_decide`): a cast during the hold is the illegal cast
(F, an attempt), doing nothing during the hold is correct (no attempt, no points),
and an unknown step stays unknown (no attempt, never a mis-pick).

| pin | file |
|---|---|
| the paladin's idle FCFS tick and its RIDE window state an explicit hold (with the engine's reason); the unreadable state stays unknown; the three states through the engine; the ctx carries the pull moment (and an unarmed / non-numeric clock publishes nothing) | `tests/paladin_state.lua` (§24 + the updated scenario-step block) |
| the rogue's POOL verdict states an explicit hold; the three states; the ctx carries the pull moment | `tests/rogue_state.lua` (§23 + the updated scenario-step block) |
| the shaman's cast-in-flight states an explicit hold with the guide's caption; the three states; the shaman publishes no ctx builder (the engine's fallback owns it) and a pull-carrying ctx still answers the engine's verdict | `tests/shaman_guide_state.lua` (the scenario-step block + the engine block), `tests/shaman_state.lua` (§41) |
| the hunter's cast-in-progress states an explicit hold; the three states; the ctx carries the pull moment | `tests/hunter_guide_state.lua` (§6 + the ctx block) |
| the druid states **no** hold (a guide hold names a spell to press — Tiger's Fury and the queued Maul); the druid publishes no ctx builder; a pull-carrying ctx still answers the engine's verdict; an unknown decision records no attempt | `tests/druid_state.lua` (the practice-surface block + the new pull block) |

The stale pins that said "a hold reads as UNKNOWN" were **re-cut**, not deleted:
they now assert the hold statement (the class's own decision became explicit).

## 5. Mutation proofs — 11 of 11 killed

Disposable copy: `/tmp/opencode/hold-mut` (a copy of the tree; the repo tree is
never touched). Script: `/tmp/opencode/hold_mutations.py`.

| # | mutation | killed by |
|---|---|---|
| M1 | **the paladin's hold degrades to unknown** (the step answers nil) | `paladin_state` |
| M2 | **the rogue's POOL hold degrades to unknown** | `rogue_state` |
| M3 | **the shaman's RIDE hold degrades to unknown** | `shaman_guide_state` |
| M4 | **the hunter's HOLD degrades to unknown** | `hunter_guide_state` |
| M5 | **the druid INVENTS a hold** (the guide's hold becomes a hold statement) — the mirror of M1 for the one class that must never hold | `druid_state` |
| M6 | the paladin's ctx stops carrying the pull moment | `paladin_state` |
| M7 | the rogue's ctx stops carrying the pull moment | `rogue_state` |
| M8 | the hunter's ctx stops carrying the pull moment | `hunter_guide_state` |
| M9 | the pull read **guesses** a moment when the clock is unknown (publishes 0) | `paladin_state` |
| M10 | the shaman gains a ctx builder without the pull read | `shaman_state` |
| M11 | the druid gains a ctx builder without the pull read | `druid_state` |

## 6. Filed for the warrior lane (NOT touched here — a sibling lane owns it)

`classes/warrior.lua` is out of this lane's scope, so the warrior's hold semantics
are **read-only filed** here for that lane:

* `classes/warrior.lua:3914` `ST.WARRIOR.practice_scenario_step` calls
  `practice.expected(self, ctx)`, which returns **`out.action, out`** — the
  guide's own out table. The warrior's step currently answers nil whenever
  `out.action` is nil, so a hold reads UNKNOWN.
* The warrior's guide (`warrior_guide.lua`) has **three real holds**:
  * `hold_text = "CANCEL"` — a queued Execute must be cancelled
    (`warrior_guide.lua:1286`, rule 3);
  * `hold_text = "RIDE"` — `hs_queued` / `cleave_queued`
    (`warrior_guide.lua:1303` / `:1346`, rule 4);
  * `hold_text = "HOLD"` — the filler's rage shortfall
    (`warrior_guide.lua:1399`, rule 7).
* So the warrior **does** have a hold concept, and the lane that owns
  `classes/warrior.lua` should state it the same way the four classes here do:
  read `out.hold` / `out.hold_text` from the guide's own verdict and return
  `{ action = nil, hold = true, reason = out.hold_text }` — never a guessed
  action, and an unreadable state stays unknown.

## 7. Verification

* `bash tests/run.sh` → **41 steps, 0 failed**.
* luacheck → **2 warnings / 0 errors** (the shipped floor: `compat.lua:36`,
  `main.lua:81`; this lane adds none).
* The suites it owns: `paladin_state` 688, `rogue_state` 818, `shaman_state` 725,
  `shaman_guide_state` 1403, `hunter_guide_state` 1430, `druid_state` 933 — all
  green.
* Line endings preserved: `classes/paladin.lua`, `classes/rogue.lua`,
  `classes/hunter.lua` stay CRLF (CR count == line count); `classes/shaman.lua`
  and every test file stay LF. No trailing whitespace on any touched line.
