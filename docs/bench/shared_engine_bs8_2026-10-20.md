# bench/shared_engine_bs8_2026-10-20.md — the shared engine: HU-8 hold, the paladin counter, the live pull clock, the drill routing

Desk: `shared-engine-bs8`. Date: 2026-10-20. Validation owner: **orchestrator**.

Closes four items in one lane, because all four touch the shared engine files:

1. **HU-8 — the hold verdict** (operator ruling, hands-up HU-8, resolved 2026-10-19:
   *HOLD-IS-A-DECISION*): the class contract grows an explicit hold statement, the pure
   engine grades it, and the practice UI shows it.
2. **BS-8 item 1 — JE-1**: the paladin's `LCD.Register` degrade counter gets its reader
   on `main.lua`'s runtime-diag line.
3. **BS-8 item 2 — P-17**: `main.lua` publishes the live pull clock the prepull rule
   needs.
4. **The drill-key routing fix** filed by the superseded-wrappers lane
   (`bench/superseded_wrappers_2026-10-19.md` §6 item 1).

Files changed (the lane's scope):
`practice.lua`, `practice_ui.lua`, `main.lua`, `tests/practice_state.lua`,
`tests/practice_ui_state.lua`, `tests/main_init_state.lua`.
**Scope files NOT touched, and why:** `diag.lua` (the counter's reader is the
runtime-diag line, per BS-8 item 1 — the verbose report has no per-class counter
section to extend), `practice_stats.lua` / `practice_progress.lua` (a correct hold
records **no attempt**, so the XP / mastery / stats layers need no new rule: the
grade map's absence of an entry is the gate), `tests/diag_state.lua` (nothing in
`diag.lua` changed).
No `classes/*.lua`, no guide file, no `option_tables.lua` / `config_presets.lua`, no
`compat.lua` / `hud.lua` / `bars.lua`, no `run.sh`, no TOC, no version, no
README/CHANGELOG/docs, no git write, no lint-config change.

---

## 1. HU-8 — a hold is a decision, unknown is not

### 1.1 The class contract (the change every class lane codes against)

`practice.lua`'s contract block (the one the six class lanes code against) now says:

```
ST.<CLASS>.practice_scenario_step(self, ctx)
  -> { action = "<spell key>", reason = "<text>" } | nil
  -> { action = nil, hold = true, reason = "<text>" }   -- an explicit HOLD
```

* a **hold statement** is a decision: the engine grades the step as a hold;
* a **nil step with no hold statement** stays UNKNOWN — no attempt, never a wrong
  grade (unchanged);
* a step that names an **action** is an action: the hold flag is ignored, so a class
  that means to hold must not name an action (a mis-specified step never punishes a
  cast the class actually asked for).

`H.practice_scenario_step` (the accessor) accepts the hold statement: it used to
drop a nil action and answer `nil` (unknown) for every answer without an action.

### 1.2 The pure engine decides everything

`H.rotation_run_decide(run, expected, actual, hold)` — the hold flag is **injected**
(no clock, no randomness, no WoW API inside the decision math):

| step | cast | outcome | attempt? | grade |
|---|---|---|---|---|
| hold | none | `hold_ok` | **no** (no points — idling must not farm points) | — |
| hold | any action | `illegal_cast` | yes | **F** (counts as a mis-pick: it breaks the streak and the band) |
| action expected | the expected action | `correct` | yes | S |
| action expected | another action | `out_of_order` | yes | F |
| action expected | none | `miss` | yes | F |
| **no** expectation, no hold | anything | `unknown` | **no** | — |

The grade map `H.ROTATION_OUTCOME_GRADES` is the **single gate** for "an attempt
happened": `correct = S`, `out_of_order = F`, `miss = F`, `illegal_cast = F`, and
**`hold_ok` has no entry** — that absence IS the rule (a correct hold is recorded in
the run, but it awards no points, no streak and no mastery tick). The run carries
`holds` and `illegal_casts` counters, and the summary reports them.

A correct hold counts as a *correct decision* in the run's own counters (it is one),
but it is not a graded attempt. The 4th argument is optional, so every pre-existing
caller (`H.rotation_run_decide(run, expected, actual)`) keeps its old behaviour.

### 1.3 The UI

* the scenario prompt shows the hold and the class's own reason:
  `next: HOLD - pool the resource first`;
* a press during a hold is graded as the illegal cast: the popup reads
  **ILLEGAL CAST** (the miss colour, the same rule the "OUT OF ORDER" label uses) and
  the status line reads `illegal cast: the rotation is holding - <reason>`;
* doing nothing during a hold (the decision window closes) is correct: the popup
  reads **HOLD OK**, the status line reads `hold: correct - nothing cast - <reason>`,
  and **no attempt is recorded**;
* the run's status line and the panel's info line carry the hold counters — the info
  line only when they are non-zero, so a run without a hold reads exactly as before.

The buttons stay live during a hold on purpose: the press is what has to be punished.

### 1.4 What is NOT in this lane

The **class-side hold statements** are a separate lane (every `classes/*.lua` is out of
scope here). The engine is ready for them; the classes that already have a hold in
their own guide can now say so:

* the rogue's POOL verdict (`bench/rogue_drills_rotation_2026-10-19.md` §5.7 — the
  filing that raised HU-8): the rogue's `practice_scenario_step` returns `nil` for a
  POOL today, so the step reads UNKNOWN. It should return
  `{ action = nil, hold = true, reason = "..." }`;
* the shaman's guide already computes a hold (`shaman_guide.lua:1017` `if res.hold then
  return nil end`) and drops it — the same conversion applies.

Until a class states a hold, nothing changes for it: a nil step is still UNKNOWN.

---

## 2. BS-8 item 1 — the paladin's `LCD.Register` degrade is visible

The class-side counter landed in the BS-5 lane (`classes/paladin.lua:65` and the
failure path at `:399`): every failed `pcall(LCD.Register, LCD, addon_name)` increments
`ST.PALADIN.lcd_register_errors`, and **nothing read it** — a degraded guide frame
showed no diagnostic at all.

`main.lua`'s `print_runtime_diag` now reads it, in the same shape as the HUD's
counter (`hud_cleu_register_errors=N`):

```
paladin_lcd_register_errors=0
```

The read is `self.PALADIN` — the class table lives on the **addon object** (the
AceAddon table), not on the namespace table, so `st.PALADIN` would read nil.

---

## 3. BS-8 item 2 — the live pull clock

`nextaction.lua`'s prepull rule reads `inputs.time_to_pull_seconds`
(`PREPULL_SEAL_LEAD_SECONDS` at `:395`, `out.prepull_ready` at `:849-855`), and
`nextaction_ui.lua`'s idle frame reads the same input (`:694-697`). The **practice
session** has its own synthetic pull clock (the drill's countdown); the **live guide**
needed a real one, and the class-side provider (`classes/paladin.lua:3274`) writes
`inputs.time_to_pull_seconds = nil` with the comment *"needs a pull timer (main.lua)"*.

### 3.1 The client has no pull-timer API (the reason the clock is the addon's own)

Checked 2026-10-19 against the shipped client sources
(`/home/sam/wow-ui-source`, branches `classic_era` 1.15.9, `classic_anniversary`
2.5.6, `classic_titan` 3.80.2, `origin/forever` 1.60.1, `live` 12.1.0): **no**
`pulltimer`, **no** `GetPullTime`, **no** `SetPullTimer` anywhere under
`Interface/AddOns` on any branch. There is no Blizzard pull-timer contract to read.

### 3.2 What `main.lua` publishes

```
ST.pull_at              the absolute pull timestamp (api.get_time() domain);
                        nil = unknown (never a guess)
ST:set_pull_at(at)      arm the clock at an absolute timestamp; nil disarms
ST:set_pull_in(seconds) arm the clock `seconds` from now
ST:pull_in_seconds(now) the countdown in seconds; nil when unknown
```

The read is **one timestamp** (the stored pull moment against the injected clock) —
no per-frame scan, no client call in the reader.

### 3.3 The live source

* **the fight's own pull** — `PLAYER_REGEN_DISABLED` stamps the clock (the pull
  happened; the countdown reads 0) and `PLAYER_REGEN_ENABLED` clears it (the NEXT
  pull is unknown);
* **the pre-pull** — while the player is out of combat and **their own target**
  starts a cast, the pull is projected to that cast's **END**: the real "the boss is
  casting, pull now" cue. The cast's start and end come from the client
  (`api.UnitCastingSpell`), so **no number is invented** here.

The projection is deliberately narrow, because a wrong prepull prompt is worse than
no prepull prompt: the player's TARGET only (a pull is the boss's opening cast, never
the player's own), out of combat only, and only when the player is **in a group inside
an instance** (a pull is a group event, so an open-world mob casting can never arm
the clock).

### 3.4 The practice side

`practice_ui.lua`'s scenario/drill context now carries the same moment
(`ctx.pull_at` — the absolute timestamp, `ctx.pull_in_seconds` — the countdown), so
the prepull drills and the prepull rule read **one** truth. A context that already
carries its own pull clock (a drill's synthetic one) keeps it — the live clock never
overwrites a caller that knows better.

**Residual (filed, in-client):** the pre-pull projection is a heuristic — the boss's
opening cast is the pull. It is narrow by construction (target + out of combat + group
+ instance), and the *cue* itself only lights when a class provider feeds
`inputs.time_to_pull_seconds` — which no class does yet (the class-side read is
another lane). In-client confirmation is the operator's session.

---

## 4. The drill-key routing fix

`PRACTICE_DRILL_KEYS.<CLASS>.mode` still named each class's **first** drill
(`druid_finisher_order`, `shaman_enh_priority`, `warrior_core_order`) while the class
wrappers now run the superseding drill (`druid_powershift_rework`, `shaman_mw_weave`,
`warrior_execute_burn`) — so the mastery row, the session and the panel's offered
drill were three different things, and the map's `mode` keys are pick-drills that
never grade in the drill-list session (the press carries no `last_action` there), so
the default scope was a dead drill for those three classes.

**One line per class**, naming the drill the class's session actually runs:

| class | mode before | mode now |
|---|---|---|
| DRUID | `druid_finisher_order` | `druid_powershift_rework` |
| SHAMAN | `shaman_enh_priority` | `shaman_mw_weave` |
| WARRIOR | `warrior_core_order` | `warrior_execute_burn` |

The other three (paladin / hunter / rogue) are unchanged: their sessions still run
the drill their map names (`paladin_twist`, `hunter_forced_move`, `rogue_energy_pool`).
The class drill list stays the single source of truth: the map's `mode` is only
honoured when the class owns that drill (`practice_owns_drill`), and the class's own
list still wins over the table everywhere else.

---

## 5. The pins

| pin | file |
|---|---|
| the accessor accepts a hold statement; a step with neither an action nor a hold stays unknown; a non-boolean hold flag is not a hold; a named action wins over the hold flag | `tests/practice_state.lua` (the new `hold_tests` block) |
| the two new outcome classes; `illegal_cast = F`; **`hold_ok` has no grade** (no attempt, no points) | `tests/practice_state.lua` |
| the run counters: `holds`, `illegal_casts`, the illegal cast counts as a mis-pick; a nil step with no hold stays unknown and is never a mis-pick | `tests/practice_state.lua` |
| the summary carries the hold counters; determinism over hold sequences | `tests/practice_state.lua` |
| the prompt shows the hold and the class's reason; a press during the hold is the illegal cast (an attempt, a miss, the popup reads ILLEGAL CAST, the status names the reason); a correct hold records **no** attempt and awards no hit; the popup reads HOLD OK | `tests/practice_ui_state.lua` (§22k) |
| the drill routing: the map names the drill the class's session runs (three source pins + the three "no longer the first drill" pins) and the mastery row is that drill in behaviour (§22i, §22j) | `tests/practice_ui_state.lua` |
| the ctx carries the live pull clock (both context paths) and a ctx that already has one keeps it (§22l) | `tests/practice_ui_state.lua` |
| the runtime-diag line reads the paladin's counter, and renders zero without one (§19) | `tests/main_init_state.lua` |
| the pull clock: unknown by default, arming (absolute + relative), the countdown (negative after the pull), the combat-enter stamp, the combat-exit clear, the pre-pull projection, and the two source guards (a solo player, the open world) (§20) | `tests/main_init_state.lua` |

## 6. Mutation proofs — 11 of 11 killed

Disposable copy: `/tmp/opencode/bs8-mut` (a copy of the tree; the repo tree is never
touched). Script: `/tmp/opencode/bs8_mutations.py`.

| # | mutation | killed by |
|---|---|---|
| M1 | **the hold is treated as unknown** (the engine drops the hold flag) | `practice_state` + `practice_ui_state` |
| M2 | **an illegal cast is not punished** (the grade map loses the illegal-cast entry) | `practice_state` + `practice_ui_state` |
| M3 | the accessor drops the hold statement | `practice_state` + `practice_ui_state` |
| M4 | a correct hold is worth points (the grade map gains the entry) | `practice_state` + `practice_ui_state` |
| M5 | the illegal cast does not count against the run's band | `practice_state` |
| M6 | the UI does not hand the hold flag to the engine | `practice_ui_state` |
| M7 | the paladin counter is not on the runtime diag line | `main_init_state` |
| M8 | the pre-pull projection is gone | `main_init_state` |
| M9 | combat exit keeps the last fight's stale pull | `main_init_state` |
| M10 | the drill routing reverts (the map names the first drill again) | `practice_ui_state` |
| M11 | the context stops carrying the live pull clock | `practice_ui_state` |

## 7. Verification

* `bash tests/run.sh` → **41 steps, 0 failed**.
* luacheck → **2 warnings / 0 errors** (the shipped floor: `compat.lua:36`,
  `main.lua:81`; this lane adds none).
* The suites it owns: `practice_state` 1478, `practice_ui_state` 1355,
  `main_init_state` 788 — all green.
* Line endings preserved: `practice.lua`, `practice_ui.lua`, `main.lua` stay CRLF
  (CR count == line count); the three test files stay LF. No trailing whitespace on
  any touched line.

## 8. Filed for other lanes (not this lane's scope)

1. **The class-side hold statements** (the classes are out of scope here): the rogue's
   POOL verdict and the shaman's guide hold (§1.4) should return
   `{ action = nil, hold = true, reason = "..." }` instead of `nil`. Until then a hold
   is still UNKNOWN for those classes — the engine side is ready.
2. **The class-side pull-clock read** (out of scope): the paladin's gather
   (`classes/paladin.lua:3274`) should feed
   `inputs.time_to_pull_seconds = self:pull_in_seconds(now)` so the prepull cue can
   light live; the *seal choice* per family stays filed (P-17's other half).
3. **In-client confirmation** of the pre-pull projection (the operator's session): the
   boss's opening cast → the pull at the cast's end.
