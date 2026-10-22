# bench/superseded_wrappers_2026-10-19.md — the class wrappers run their OWN drill

Desk: `superseded-wrappers`. Date: 2026-10-19. Validation owner: **orchestrator**.

Closes the engine lane's open item (`bench/practice_scenario_engine_2026-10-19.md`
§5 + §9): the class wrappers started the **superseded built-in** drill session
directly, so a class's own drill was not what the class's session ran.

Files changed (the lane's scope):
`classes/druid.lua`, `classes/shaman.lua`, `classes/warrior.lua`,
`tests/druid_state.lua`, `tests/shaman_state.lua`, `tests/warrior_state.lua`.
One pin outside the scope (see §6): `tests/shaman_guide_state.lua`.
No `practice*.lua`, no `option_tables.lua`, no `config*.lua`, no `main.lua`,
no `diag.lua`, no `compat.lua`, no `hud.lua`, no `bars.lua`, no guide file, no
`run.sh`, no TOC, no version, no docs, no git, no lint-config change.

---

## 1. What shipped

### 1.1 Each class names the drill its session runs

| class | the drill the session runs | the retired built-in (still registered) |
|---|---|---|
| DRUID | `druid_powershift_rework` | `druid_powershift` |
| SHAMAN | `shaman_mw_weave` | `shaman_weave` |
| WARRIOR | `warrior_execute_burn` | `warrior_execute` |

Each class module publishes it:

* `ST.<CLASS>.PRACTICE_DRILL_KEY` — the class's own drill that owns the skill the
  retired built-in used to own (`practice.lua H.SUPERSEDED_DRILLS` names the same
  pair, so the class and the engine agree).
* `ST.<CLASS>.practice_drill_key()` — the key **only when the class publishes that
  drill** (the class's own `practice_drills` list carries it with a grade
  function). Nil otherwise: unknown-hides, never a guessed key.

### 1.2 The wrapper starts the class's OWN drill session

`ST.DRUID.new_practice_session` / `ST.SHAMAN.new_practice_session` no longer call
`pr.harness.new_session("<built-in>", ...)`. They build the session for the class's
own drill:

* the **session key** is the class's own drill key,
* the **session state** is the shared harness primitive the old session used (the
  druid: the energy pool `H.new_energy_state` / `H.energy_update`; the shaman: the
  weave swing state `H.WEAVE_DEFAULTS`) — the MODEL, never its grade,
* the **grading** goes through the class's own drill function
  (`H.practice_drill_grade(ST.<CLASS>, <class drill>, ST, ctx)` with the ctx the
  engine hands the drills: `H.drill_context`), so the retired rule's truth never
  grades a player attempt.

The built-in stays registered (the engine's own key still resolves; the engine's
delegation map is untouched) and the panel's routing is untouched.

`practice_scenario_key()` keeps naming the retired built-in on purpose: it is the
**routing key** the shared engine reads (`practice_ui`'s `use_druid_drill()` /
`use_shaman_drill()` and the engine's supersession rule
`practice_own_drill_supersedes_route()`), and the built-in must keep resolving for
backward compatibility.

### 1.3 The shaman alias is gone

`st.SHAMAN = ST.SHAMAN` (the HU-7 stopgap) is **removed** from
`classes/shaman.lua`. The engine resolves the class module from the AceAddon
table first (`H.practice_class_module` → `LibStub("AceAddon-3.0"):GetAddon`), so
no per-class alias is needed. Pinned: the alias is absent **and** the engine
still finds the class (`H.practice_class_module("SHAMAN")`, `H.practice_drills`,
`H.practice_scenario_available`) — in `tests/shaman_state.lua` and in
`tests/shaman_guide_state.lua`.

### 1.4 The warrior

The warrior has **no** session wrapper of its own: the shared engine already
routes its class session to its own drill list (the panel map's `warrior_core_order`
scope), so there was no built-in session to re-point. What the warrior gained is
the ownership statement: the class names the drill that owns the execute-phase
skill (`warrior_execute_burn`) and the live feed's sample rows carry that drill
key, so a row never reads as a run of the retired built-in. The feed's **grade**
is unchanged (the harness's pool band — a measurement of the banked rage at the
crossing, not a player attempt; the class's own drill grades the press).

---

## 2. What the pins now prove (the classes' own suites)

| pin | file |
|---|---|
| the session's key IS the class's own drill (`druid_powershift_rework`, `shaman_mw_weave`) | `tests/druid_state.lua` §32, `tests/shaman_state.lua` §34 |
| the class publishes the drill its session runs | all three class suites |
| the retired built-in stays registered and names the class drill (`H.SUPERSEDED_DRILLS`) | `tests/druid_state.lua` §32, `tests/warrior_state.lua` (c) |
| the retired 20-energy rule never grades: the shift at 50 energy grades **A** (the class's rule), not **C** (the retired rule) | `tests/druid_state.lua` §32 |
| the class's drill grades the weave: a weave **below the Maelstrom-stack floor** grades **F** (the retired weave model has no stack condition) | `tests/shaman_state.lua` §34 |
| the alias is gone and the engine still finds the class | `tests/shaman_state.lua`, `tests/shaman_guide_state.lua` |
| the warrior's module never starts the retired built-in (source pin) | `tests/warrior_state.lua` (c) |

## 3. Mutation proofs — 7 of 7 killed

Disposable copy: `/tmp/opencode/mut_swd` (script:
`/tmp/opencode/mut_superseded.py`; the copy is a full tree copy, the repo tree is
untouched).

| # | mutation | killed by |
|---|---|---|
| 1 | the druid wrapper starts `druid_powershift` again | `tests/druid_state.lua` — "the run is the class's own drill" |
| 2 | the retired 20-energy rule grades the attempt again | `tests/druid_state.lua` — "grades A through the class drill" |
| 3 | the shaman wrapper starts `shaman_weave` again | `tests/shaman_state.lua` — "the run is the class's own drill" |
| 4 | the namespace alias comes back | `tests/shaman_state.lua` — "carries no namespace alias" |
| 5 | the class drill loses the Maelstrom-stack floor | `tests/shaman_state.lua` — "below the stack floor grades F" |
| 6 | the warrior names `warrior_execute` again | `tests/warrior_state.lua` — "names the drill that owns the execute phase" |
| 7 | the warrior's module starts the retired built-in | `tests/warrior_state.lua` — "never starts the retired built-in" |

## 4. Verification

* `bash tests/run.sh` → **41 steps, 0 failed**.
* luacheck → **2 warnings / 0 errors** (the shipped floor; this lane adds none).
* The suites: `druid_state` 911, `shaman_state` 670, `warrior_state` 1153,
  `shaman_guide_state` 1378 — all green.
* `tests/wiring_check.lua` → 589 checks, 0 failures (the new class hooks are
  wired: `practice_drill_key` is called inside its own class module).
* Line endings preserved: `classes/druid.lua` and `classes/warrior.lua` CRLF,
  `classes/shaman.lua` and the suites LF. No trailing whitespace on any touched
  line.

## 5. Behaviour changes (all opt-in, no default-visible change)

* The class wrappers' sessions now run the class's own drill. The panel's
  class-mode session was ALREADY the class's own drill list (the engine's
  routing, pinned by `tests/practice_ui_state.lua` §22h) — the wrapper path is
  the class-side API the panel's per-class session branches call, and those
  branches are unreachable today because the drill list wins first. So nothing
  visible changes for the player.
* The druid's shift grading is now the class's own rule (the sim's trigger):
  on a family with no shift basis (Wrath, Forever) the drill answers **nil**
  (unknown-hides) instead of the retired 20-energy rule's grade. On Era/SoD/TBC
  the bands shift (the shift at 50 energy is an **A**, the retired rule said C).
* The shaman's weave grading is now the class's own drill, which adds the
  Maelstrom-stack condition: a weave below the stack floor is an **F** even when
  the timing is tight (the retired weave model had no stack condition).

## 6. Filed for other lanes (not this lane's scope)

1. **The panel map's `mode` (engine lane, `practice_ui.lua`).** The map's `mode`
   is "the drill key this class's session grades" and it still names the class's
   FIRST drill (`druid_finisher_order`, `shaman_enh_priority`,
   `warrior_core_order`) while the class wrappers now run the superseding drill
   (`druid_powershift_rework`, `shaman_mw_weave`, `warrior_execute_burn`). One
   line per class in `PRACTICE_DRILL_KEYS` would make the mastery row, the
   session and the panel's drill one drill. The map also matters because its
   `mode` keys are pick-drills that never grade in the drill-list session (the
   press carries no `last_action` there), so the default scope is a dead drill
   for all three classes today.
2. **`tests/shaman_guide_state.lua` (scope exception).** Its pin
   `eq(st.SHAMAN, ST.SHAMAN, ...)` asserted the alias this lane had to remove;
   the pin now asserts the alias is absent and the engine finds the class
   without it. One line + its comment; the file's owner lane
   (`shaman-slots`) had already closed when this edit was made.

## 7. Not done (and why)

* The warrior's live-feed grade still comes from the harness's pool band
  (`H.grade_execute_entry`). The class's own drill grades the **press** (the
  burn's decision), and the feed's sample is a **measurement** at the crossing
  (no press), so routing it through the class's drill would grade a guess. The
  two are complementary, not conflicting; changing the feed's bands would be a
  default-visible change to the Execute report (out of this lane's rule).
* `practice.lua` / `practice_ui.lua` were not touched: the built-ins stay
  registered, the delegation map is unchanged, and the panel's routing already
  sends all three classes to their own drill lists.
