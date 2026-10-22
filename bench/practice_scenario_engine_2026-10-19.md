# bench/practice_scenario_engine_2026-10-19.md — the shared rotation-scenario + drill engine

Desk: `practice-scenario-engine`. Date: 2026-10-19. Validation owner: **orchestrator**.

One NEW bench file (this one). Files changed: `practice.lua`, `practice_ui.lua`,
`practice_progress.lua`, `option_tables.lua`, `tests/practice_state.lua`,
`tests/practice_ui_state.lua`, `tests/practice_progress_state.lua`,
`tests/options_load_state.lua`. No class file, no `config_presets.lua`, no TOC, no
version, no git, no lint-config change.

---

## 1. What the operator asked for

1. The **shared rotation-SCENARIO engine** + the drill-registry plumbing that six
   per-class lanes (disjoint files) plug into.
2. The contract is FIXED — the six lanes code against exactly this:

   | member | shape |
   |---|---|
   | `ST.<CLASS>.practice_scenario_step(self, ctx)` | `{ action = "<spell key>", reason = "<text>" }` or `nil` (= "cannot decide" → the engine grades UNKNOWN, never a wrong action) |
   | `ctx` | `{ now, last_action, resources, cooldowns }` |
   | `ST.<CLASS>.practice_drills` | `{ { key = "<registry key>", label = "<label>", grade = function(self, ctx) -> "S".."F" | nil end }, ... }` |

   `self` is the **addon** (ST) — the same shape as
   `ST.<CLASS>.gather_guide_inputs(self, out)`.
3. The engine looks the contract up **by `player_class` at runtime**; a class that
   provides neither fails LOUDLY ("scenario not available for this class") — never a
   silent paladin sim.

Two operator corrections landed mid-lane and are implemented here (§4, §5).

## 2. What shipped

### 2.1 `practice.lua` — the pure half (offline-testable, WoW-free)

* `H.SCENARIO_KINDS` grew from 7 to 12 kinds: the shipped seven keep their meaning
  and the audit's taxonomy adds `rotation_run` (the rotation SCENARIO),
  `rotation_order`, `rotation_window`, `transition`, `situational` (the drill kinds).
  The eight registered entries are unchanged (backward compatibility — see §5).
* The **rotation engine** (new, pure, deterministic — the clock is injected):
  * `H.new_rotation_run(opts)` — a run of `H.ROTATION_RUN_STEPS` (10) decisions.
  * `H.rotation_run_decide(run, expected, actual)` — the four outcome classes:
    `correct` / `out_of_order` / `miss` / `unknown`. An unknown expectation (the
    class could not decide) is never a wrong action.
  * `H.rotation_run_summary(run)` — the counts and the run band; `grade` is **nil**
    when nothing in the run was gradeable (the run reads UNKNOWN, never a perfect S).
  * `H.ROTATION_RUN_BANDS` — S 0 mis-picks / A 1 / B 2 / C 3 / D 4-5 / F 6+.
    A miss counts as a mis-pick (the rotation wanted an action and none came).
    **[DESIGN]** — addon policy, not a sim number (the audit's U-15).
  * `H.ROTATION_OUTCOME_GRADES` — the attempt grade per outcome: `correct` → S,
    `out_of_order`/`miss` → F, `unknown` → **no attempt at all**.
* The **contract accessors** (pure, nil-safe per class):
  `H.practice_class_module`, `H.practice_scenario_available`,
  `H.practice_scenario_step`, `H.practice_drills`, `H.practice_drill_by_key`,
  `H.practice_drill_grade`.
  * A class key resolves from the **AceAddon table first** (that is where the class
    modules live — `ST.PALADIN`, `ST.WARRIOR`, …), the namespace table is the
    fallback, never the first place looked at. The lookup is guarded (no LibStub in
    the offline sandbox) and nil-safe per class: an unknown class answers nil, it
    never throws and never returns another class's module.
  * The class module may also be handed over directly (the UI resolves it once and
    passes the table) — both spellings resolve.

### 2.2 `practice_ui.lua` — the session half (frames + the injected clock)

* **Rotation scenario session**: start / stop / tick. Each step asks the class
  (`practice_scenario_step`), the player casts (the panel's own action buttons or
  the class's icon grid), the engine compares and grades the decision
  (correct / out of order / miss / unknown) and feeds every graded decision into
  `ui.record_graded_attempt` — the XP/mastery path is unchanged.
  * The decision window is `SCENARIO_STEP_SECONDS` (3 s, **[DESIGN]**); an expired
    step closes as a miss.
  * The class may publish its own context builder
    (`ST.<CLASS>.practice_context(self, now, last_action)`) and its own rotation
    table (`ST.<CLASS>.practice_rotation_for()` / `practice_rotation_family()`) —
    the engine uses them when they exist and falls back to its own gathered view
    otherwise. `self` stays the addon; the ctx's four contract fields always hold.
  * The class owns its scenario id (`ST.<CLASS>.practice_scenario_key`, a string or
    a function) — the engine reads it, the static table is the fallback.
* **Generic drill routing**: one panel button per drill in
  `ST.<CLASS>.practice_drills`; pressing one grades it through the class's own
  grader. A grader that cannot judge (nil) reads UNKNOWN and records no attempt.
* **The practice row**: a companion strip under the panel's content, created lazily
  on the first scenario/drill session (the shipped panel and its size are untouched
  until a session asks for it). The panel grows by the row's height while it is up
  and shrinks back when it goes away.
* **The mode select** (the Practice page): `class` (the shipped per-class session —
  the default, so a fresh profile sees exactly the panel it saw before),
  `scenario` (the class's rotation scenario), `drills` (the class's drill list).

### 2.3 `practice_progress.lua`

* The drill-variant unlock requires `spec.scenario` (the audit's §4.3 rule) — kept
  and pinned; `P.unlock_scenario(id)` reads the granted scenario back.
* The registry **copies** the requirement instead of aliasing it: an unlock can
  never reach into a live table (the hard rule — an unlock never changes how a drill
  behaves).

### 2.4 `option_tables.lua`

The Practice page carries the new `practice_mode` select (nil-safe: an unset or
unknown value means the shipped class session) plus an availability note that
names what the class actually ships (rotation scenario yes/no, the drill count).

## 3. The routing rules the engine enforces (all offline-pinned)

| rule | why |
|---|---|
| A class's **own drills win** over any inherited/shared key (the scope fallback is the class's own drill; an inherited key never wins) | operator correction |
| A class with its own drills **never** falls back to the paladin twist session (the twist drill is the paladin's) | operator correction |
| A class whose drill list **supersedes** the built-in drill its shipped session would run trains its own list (one skill, one truth) | operator ruling (the registry reconciliation) |
| A class that provides neither a scenario nor drills gets a **loud** refusal, never a silent paladin sim | the fixed contract |
| The panel's twist-sim widgets (icon grid, haste buttons, rotation selector, timeline toggle) are **not built** for a class that runs no sim session | no silent paladin sim |

## 4. Operator correction 1 — the panel map (the warrior)

`PRACTICE_DRILL_KEYS.WARRIOR` was `"paladin_twist"` (the shared twist drill). It is
now the warrior's own drill:

```lua
WARRIOR = {
    mode = "warrior_core_order",           -- the scope's own drill, never the shared one
    scenario = "warrior_rotation",
    drills = { "warrior_core_order", "warrior_ww_delay",
               "warrior_sunder_upkeep", "warrior_execute_burn" },
}
```

and the warrior's session is its own drill list (it publishes drills and does not
own the twist drill) — the twist session is gone from the warrior's panel, and the
panel carries no twist-sim widgets at all. Generalised for every class: the live
scope resolves **per drill** (the running mode's id wins), the class's own drills
win over an inherited key, and the static table is the fallback.

## 5. Operator correction 2 — the registry reconciliation (one skill, one truth)

The druid lane shipped `druid_powershift_rework` (the SIM's trigger) while the
built-in `druid_powershift` still graded the addon's own 20-energy rule — the same
drill, two truths.

**Backward compatibility first (the operator's instruction):** all **eight** built-in
drills stay registered, so the class's own session wrappers and their offline pins
still resolve the old keys. What changed is the truth and the routing:

* `H.SUPERSEDED_DRILLS` names, per built-in drill, the class drill that owns the
  skill:

  | built-in (still registered) | superseded by | verdict |
  |---|---|---|
  | `druid_powershift` | `druid_powershift_rework` | the shift rule — the operator's named case (the sim's trigger, not the addon's 20-energy rule) |
  | `shaman_weave` | `shaman_mw_weave` | the weave decision — the same weave.lua maths, re-sourced with the Maelstrom-stack condition |
  | `warrior_execute` | `warrior_execute_burn` | the execute phase |
  | `paladin_twist`, `paladin_aw_combo`, `hunter_forced_move`, `rogue_energy_pool`, `rogue_ss_window` | — | **kept**: the class's list covers a different skill (the twist timing / the AW burst window / the move cadence / the baseline resource / the Sinister-Strike window) |

* A superseded built-in's **grading is delegated** to the class's drill
  (`H.delegate_drill_grade`): the old truth never grades a player attempt. The
  delegation is best effort — a flavour that ships no class drill keeps the
  built-in model (never a throw, never a guessed grade).
* The engine **routes the class to its own drill list** when the class's list
  supersedes the built-in drill its shipped session would run. The paladin (twist),
  the hunter (forced move) and the rogue (energy pool) keep their shipped sessions —
  their class lists do not cover those skills.

### 5.1 Pins broken by the reconciliation

**None.** The eight built-in drills stay registered and their sessions keep their
shapes, so `tests/druid_state.lua` (903 checks), `tests/warrior_state.lua` (1148),
`tests/shaman_state.lua` (640), `tests/hunter_state.lua` (1046) and
`tests/rogue_state.lua` (757) all pass unchanged. The one pin that changed
*meaning* is the built-in powershift drill's grade inside a flavour that ships the
class drill: the sim's trigger replaces the 20-energy rule — that is the operator's
ruling, and the class lane's own suite exercises the wrapper with a practice
sandbox that has no class module (so the built-in model stands in there).

## 6. Operator correction 3 — the class-module lookup (HU-7, shaman lane)

The pure half resolved the class module from the **namespace** table
(`st[class_key]`), but the class tables live on the **AceAddon** table
(`ST.PALADIN`, …). Fixed centrally: the class key now resolves from the AceAddon
table FIRST (through a guarded `LibStub("AceAddon-3.0"):GetAddon(addon_name)`),
the namespace only as the fallback. The engine therefore finds a class module
**without any per-class alias** — the shaman lane's `st.SHAMAN = ST.SHAMAN`
stopgap is not needed by the engine (the shaman lane may drop it).

## 7. Evidence

* `bash tests/run.sh` → **41 steps, 1 failed** — the one failure is
  `tests/hunter_guide_state.lua`, the **hunter lane's own** suite in flight
  (`ST.HUNTER.practice_family()` does not exist yet in their file). Every other
  step passes, including the four suites this lane owns.
* luacheck: **2 warnings** (the shipped floor: `compat.lua:36` unused
  `addon_name`, `main.lua:81` `table.pack`) — this lane adds none.
* Mutation proofs on disposable copies (`/tmp/opencode/mut`): **43 of 44 killed**.
  The one survivor is an **equivalent mutant** by design: "the scope prefers the
  inherited key" cannot be observed while every class's map entry names its own
  drill (the operator's correction guarantees exactly that) — the safety net is
  unreachable, not untested. The mutation script lives at
  `/tmp/opencode/mutations.sh` (disposable; the bench copy of the results is here).
* The suites this lane owns: `practice_state.lua` 1443 checks,
  `practice_ui_state.lua` 1306, `practice_progress_state.lua` 431,
  `options_load_state.lua` 3280 — all green.

## 8. What the class lanes must know

* The contract is as specified above. `self` is the addon. `ctx` always carries
  `now` and `last_action`; `resources`/`cooldowns` are the engine's best-effort
  view (a class that wants more publishes `practice_context`).
* A class may publish `practice_scenario_key` (a string or a function),
  `practice_context(self, now, last_action)` and `practice_rotation_for()` /
  `practice_rotation_family()` — the engine uses them when they exist.
* The engine finds the class module on the **AceAddon** table; a per-class alias in
  the namespace is not needed (and not relied on).
* A class that publishes no drills keeps the shipped twist session (unchanged
  behaviour); a class that publishes drills trains its own list.
* The built-in drills that a class's list supersedes stay registered for backward
  compatibility, but they are no longer the class's session and their grading is
  delegated to the class's drill.

## 9. Open items (not this lane's scope)

* `tests/hunter_guide_state.lua` is red in the hunter lane's own file (their
  in-flight `practice_family` seam). Not this lane's file, not this lane's change.
* The audit's §2 drill inventory still lists the eight built-in drills as the
  shipped set; the class lists supersede three of them (§5). The audit file is the
  class-drills-spec desk's artifact — the reconciliation above is the newer ruling.
