# Shared practice-UI fixes (F2/F4/F5/F7/F9/F10/F11) — 2026-10-20

**Desk:** `desks/practice-ui-fixes` · **Scope:** `practice_ui.lua`,
`option_tables.lua` (the `practice_mode_note` text only),
`tests/practice_ui_state.lua`, `tests/options_load_state.lua` (the mode-note
pins only).

> The scenario-100% audit report is **not on disk** — the central ledger still
> shows the `scenario-100-audit` lane as *queued*. The findings below were taken
> from the dispatch brief (each carries file:line, trigger and impact) and each
> was re-verified against the code before it was touched. Every claim below is
> marked with its evidence.

---

## 1. F2 (CRITICAL) — the drill-list panel could not supply a pick

**Trigger.** `drill_list_press` built the ctx with `last_action = nil`
(`practice_ui.lua:4924-4926` before the fix). Every pick-based grader answers
nil without a pick, so the press reported `unknown: <drill key>` and recorded
nothing.

**What the class graders actually read** (evidence, not inference):

| Class | Drill | Where the pick is read |
|---|---|---|
| paladin | `paladin_fcfs_priority`, `paladin_judge_fit` | `classes/paladin.lua:4336` — `ctx.last_action`, normalised through `practice_action_aliases` / `PRACTICE_ACTION_LABELS` |
| warrior | `warrior_core_order`, `warrior_ww_delay`, `warrior_sunder_upkeep` | `classes/warrior.lua:3968, 3991, 4037, 4154` — `ctx.last_action` |
| druid | `druid_finisher_order` | `classes/druid.lua:3257` — `ctx.last_action` |
| shaman | `shaman_enh_priority`, `shaman_mw_weave` | `shaman_guide.lua:919-932` (`get_practice_pick` reads `action` / `pick` / `pressed` / `choice` / `last_action`), `:1073`, `:1158` |
| rogue | `rogue_finisher_order` | `classes/rogue.lua:2445-2540` (the same alias family) |
| hunter | `hunter_shot_order` | `classes/hunter.lua:3233-3251` — the ctx's OWN `ctx.pick` (the live cast), which is why the hunter was the one class that worked |

**The fix.** The drill-list row now carries the class's **actions** as the pick
channel (the same vocabulary the scenario row uses:
`practice_rotation_entries` + the guide slots + the actions the class asked
for). The action press grades the selected drill with the pressed action; the
drill press carries the pick in hand. The ctx rides every alias the graders
read, and the engine's own `last_action` field carries it (the class's own
`practice_context(self, now, last_action)` receives it too).

**Why the pick cannot be the drill key.** A drill key is not an action key
(`paladin_fcfs_priority` is neither `judge` nor `soc`): a drill-key pick can
never satisfy `practice_action`, and the drill that wants a SPECIFIC press
(`warrior_ww_delay` wants `ww`) would answer nil forever. The action vocabulary
is the only source that can answer both shapes.

**Pin.** `tests/practice_ui_state.lua` §24 — a grader with the real class
graders' shape (reads `ctx.last_action`, nil without a pick, `S`/`F` against the
rotation's answer) returns a letter; the suite's old stub graders returned `A`
whatever the ctx said, which is why the defect was invisible.

## 2. F4 (HIGH) — the shaman's and the druid's own sessions were unreachable

**Trigger.** `practice_class_list_wins()` checked the SUPERSESSION (a) before the
shipped session (b). The shaman's `practice_scenario_key()` names
`shaman_weave` and the druid's names `druid_powershift` — both retired
built-ins that `H.SUPERSEDED_DRILLS` maps onto one of the class's own drills —
so the list won, `ui.start` took the drill-list branch, and
`use_shaman_drill()` / `use_druid_drill()` were never reached. The class's panel
icons then hit `shaman_cast_drill` / `druid_cast_shift` with a nil session: a
**silent no-op**.

**The fix.** The shipped session is checked FIRST: a class with a session of its
own keeps it. One skill, one truth is preserved — the session grades through
the class's own drill (`H.delegate_drill_grade`, `practice.lua:3381`). The
drill list stays reachable as the `drills` mode on top of it.

**The second half.** Any drill cast with **no session** is now LOUD: the
`practice:cast` site prints the reason and counts it (`st.guard.refusal`, the
same contract as the start refusal — count + print every time, never a silent
no-op). The four class cast paths (hunter / shaman / rogue / druid) carry it.

**Pins.** §24d (the shaman keeps its own session), §24e (the cast with no
session prints and counts).

## 3. F5 (MEDIUM) — the scenario row leaked frames

**Trigger.** `scenario_row_sync` rebuilt the button set on every step
open/close; the old buttons were only hidden, never released — ~200-300 hidden
frames per run.

**The fix.** The row's buttons are REUSED from the row's own pool (keyed by the
group and the entry key). The label and the icon update in place (the icon
texture is created once per button, not once per rebuild). A rebuild is a pass:
`practice_row_begin` → the groups claim their buttons → `practice_row_finish`
hides every pooled button no group claimed. The pool only grows to the largest
set the row ever showed.

**Pin.** §24c — twenty scenario steps create no new frame.

## 4. F7 (MEDIUM) — no Retail gate

**Trigger.** The options advertised a rotation scenario the retail client cannot
run (its swing engine is the inert stand-in), and the practice surface produced
ten unknown steps instead of saying so.

**The fix.** The rotation scenario is gated on a LIVE swing engine. The probe is
the engine mode `main.lua` records on the addon object (`ST.swing_engine`:
`vendored-lib` / `forever-source` / `inert-standin`). Only the EXPLICIT
stand-in counts as dead — a client that has not reported its engine yet is
unknown, and an unknown engine never blocks a session. The refusal is loud:
"Practice scenario is not available on this client (no live swing engine)."

`practice_mode_note` (`option_tables.lua:465-482`, the only change in that
file) now reports the truth for the family the player is on: the same sentence
is appended when the client cannot run the scenario.

**Pins.** §24f + the mode-note pins in `tests/options_load_state.lua`.

## 5. F9 (LOW) — the drill counter store was keyed on the addon object

**Trigger.** The paladin's and the rogue's drill counters hang off
`ctx.session` / `ctx.session_id` / **the session object** — and the engine
passed the ADDON OBJECT as the session (`H.practice_drill_grade(class, drill,
ST, ctx)`). The store therefore outlived every session: a band's mis-picks
survived into the next session and a drill decayed S → F for the life of the
profile. The druid's priority window had the same shape (`ctx.state`).

**The fix.** The drill-list session owns an identity and a state
(`ui.drill_list_session`, `ui.drill_list_state`, both fresh per session) and
the drill press publishes them in the ctx. The counters die with the session.

**Pin.** §24b — a new session gets a new identity and a new window.

## 6. F10 (LOW — operator ruling) — the twist minigame is the paladin's

**The fix.** (a) The twist drill leads the PALADIN's drill list (its press
starts the twist session — the flagship practice stays reachable from the
paladin's panel); (b) a class that publishes no drills of its own and owns no
twist drill (MAGE / PRIEST / WARLOCK / MONK / DEMONHUNTER / EVOKER) is refused
LOUDLY — "No practice for this class." — instead of inheriting the paladin's
minigame. `practice_class_runs_sim_session()` follows: the twist sim is built
only for the class that owns the twist drill.

**Pins.** §24g + the warrior refusal pin in section 11 of the suite.

## 7. F11 (LOW) — the stale comment

`practice_ui.lua`'s progression header said the panel's level badge is OFF by
default. It ships ON (`config_presets.lua`: `practice_panel_badge = true`, the
operator gate of 2026-10-19). The comment now states the truth: ON by default,
opt-out, and the read is still nil-safe and exact (`== true`).

---

## Evidence

* **Harness:** `bash tests/run.sh` → **41 steps, 0 failed**.
* **luacheck:** **2 warnings / 0 errors in 83 files** — the standing floor
  (`compat.lua:36`, `main.lua:81`); the touched files are clean.
* **Offline only.** Nothing here is proven in a client: the swing-engine gate
  and the loud refusals are code paths, not observed behaviour.
* **Mutation proofs** on disposable copies (`/tmp/opencode/mut_practice_ui.sh`):
  **8/8 killed**, both baselines clean.

| Mutant | Killed by |
|---|---|
| M1 the drill press carries no pick | §24 ("the grader received the pressed action as the pick") |
| M2 the cast with no session is silent | §24e ("the cast with no session prints the refusal") |
| M3 the row creates a fresh button per pass | §24c ("twenty scenario steps create no new frame") |
| M4 the class's own session is unreachable again | §24d / §22h ("the shaman/druid keeps its own session") |
| M5 the scenario is not gated on the swing engine | §24f ("the scenario does not start on a client with no live swing engine") |
| M6 a class with no practice inherits the paladin minigame | section 11 ("No practice for this class.") |
| M7 the drill counters outlive the session | §24b ("a new session gets a new drill-counter identity") |
| M8 the options note hides the dead client | the mode-note pins in `tests/options_load_state.lua` |

## Two pins had to move (the ruling changed, not the code)

* §22h / §22j pinned "the class's list wins" (the druid trains its own list
  instead of its own session). F4's ruling is the opposite: the session stays
  reachable and grades through the class's own drill. Both pins now say so.
* The "the warrior runs the shared twist session" pin encoded a routing the
  operator has since ruled against. The warrior without drills of its own is
  now refused loudly; the pool mechanics that test exercised were re-pinned
  against the twist session (the class that owns it) — the pool is
  session-level, so the mechanic under test is unchanged.

## Notes for the next lane

* `practice_ui.lua` is at the **Lua 5.1 local limit** (200 locals in the main
  chunk) and the closure upvalue limit (60). The new helpers are inlined on
  purpose: a future file-scope local must be counted first.
* The drill-list row grew: the actions (46 px, 4 per row) sit above the drills
  (96 px, 2 per row), and the row's height follows the button lines
  (`practice_row_set_height`). The scenario mode is unchanged (one line of
  buttons → the row keeps its 74 px).
* The class-side contract the drill graders read is now
  `{ now, last_action, pick, pressed, action, resources, cooldowns, session,
  session_id, state }`. The class lanes do not need to change: they already read
  `ctx.last_action` (or one of its aliases) and the counters already prefer
  `ctx.session` over the session object.
