# The drill-list pick channel — the contract, pinned against the REAL graders
**2026-10-20** · **Desk:** `desks/drill-pick-contract` · **Lane:** the
test-sufficiency audit's **Gap 5**.

## 0. What the gap was

The wave's headline fix (bench/practice_ui_fixes_2026-10-20.md §1, "F2 CRITICAL")
was: *the drill list answered UNKNOWN on every press for five of the six classes*,
because the drill-list row built the ctx with no pick.

The fix added an **alias block** in `practice_ui.lua:5280-5284` so the pick rides
in every ctx field the class graders read:

```lua
    if type(pick) == "string" and pick ~= "" then
        if ctx.pick == nil then ctx.pick = pick end
        if ctx.pressed == nil then ctx.pressed = pick end
        if ctx.action == nil then ctx.action = pick end
    end
```

plus the engine's own guaranteed field, `ctx.last_action`
(`practice_ui.lua:4555`, `scenario_context`).

The **only** pin for that was `tests/practice_ui_state.lua` §24 — and §24 drives a
**hand-written** grader shaped like the paladin's (`ctx.last_action` only). The
alias block was therefore never exercised against a reader that reads a
**different** alias, and the class-side readers were never driven end to end:

| Class | Its own reader | Reads first |
|---|---|---|
| paladin | `classes/paladin.lua:4969` `practice_action` | `ctx.last_action` (only) |
| warrior | `classes/warrior.lua:5172,5195,5241,5289,5358,5466` | `ctx.last_action` (only) |
| druid | `classes/druid.lua:3763,3942` `druid_ctx_value(ctx,"last_action")` | `ctx.last_action` (only) |
| rogue | `rogue_guide.lua:2132` `get_practice_pick` | **`ctx.action`** |
| shaman | `shaman_guide.lua:1163` `get_practice_pick` | **`ctx.action`** |
| hunter | `classes/hunter.lua:3776` `practice_pressed` | **`ctx.pick`** |

## 1. What this lane built

`tests/practice_ui_state.lua` **§27** — the CONTRACT, pinned against the six
classes' **real** graders.

* The sandbox grew one option, `opts.class_modules`: the class's own pure guide
  first, then the class module itself (`classes/<class>.lua`). The six class
  tables now exist on the sandbox's addon object (as `main.lua` creates them),
  so the engine's own `H.practice_class_module` finds the class module.
* The sandbox has no client, so each class's **live gather** (its data source) is
  stubbed with a fixture. **The grader under test is the class's own** — the real
  module, the real guide, the real alias reader. The wrapper around the real
  grader only observes the ctx and delegates.
* Every class is driven **end to end through the drill-list path**: the row's
  ACTION button is pressed (that press IS the pick), then the DRILL button is
  pressed (the pick stays in hand). Both presses must reach the class's own
  grader and answer a letter.

### 27a — the alias readers, each with the ctx shape it actually reads

The ctx the class's own grader received is replayed with **exactly one** pick
alias carried (and, for the negative case, with none):

* the paladin / the warrior / the druid: a ctx carrying only `last_action` →
  the real grader answers a letter; the same ctx with no pick → **nil** (UNKNOWN,
  never a guess).
* the rogue / the shaman: a ctx carrying only `action`, only `pick`, only
  `pressed`, only `last_action` → a letter each; no pick → nil.
* the hunter: only `pick`, only `pressed`, only `action`, only `last_action` → a
  letter each; no pick → nil.

The negative half is what makes the positive half mean something: the grader
answers nil when the alias is gone, so the letter in the positive half is
attributable to that alias and to nothing else.

### 27b — the alias-delivery contract (the block is what delivers the pick)

On both presses the ctx the real grader received is asserted to carry the pick
in **all four** aliases the graders read: `last_action`, `pick`, `pressed`,
`action`. This is the pin that fails when a future change drops an alias from
`practice_ui.lua:5280-5284` — behaviourally, on the ctx, with no source-text
assertion.

### 27c — the end-to-end drive

Per class: the action press and the drill press each reach the class's own
grader, each answers a letter, each records a graded attempt, and the pick the
class's rotation wanted is graded **S** (the pressed action IS the rotation's
own answer — the pick was compared, not merely received).

| Class | Drill graded | Pick | Grade |
|---|---|---|---|
| PALADIN | `paladin_fcfs_priority` | `judge` | S |
| WARRIOR | `warrior_core_order` | `hs` | S |
| DRUID | `druid_finisher_order` | `shred` | S |
| ROGUE | `rogue_finisher_order` | `eviscerate` | S |
| SHAMAN | `shaman_enh_priority` | `flameshock` | S |
| HUNTER | `hunter_shot_order` | `silencing_shot` | S |

**The picks are the rotation's own answer at the fixture**, so a rotation change
moves them — the `CLASSES` table in §27 is the one place to update (the same
shape as the rotation pins the tree already carries, e.g.
`tests/rogue_guide_state.lua:1531`). The pick channel itself is what §27 pins;
the key that carries it is fixture data.

## 2. Evidence

* **Harness:** `bash tests/run.sh` → **41 steps, 0 failed** at the time this lane
  landed (`tests/practice_ui_state.lua` 1623 checks, up from 1455).
* **luacheck:** **2 warnings / 0 errors in 83 files** — the standing floor
  (`compat.lua:36`, `main.lua:81`) at the time this lane landed; the touched file
  is clean on its own (`luacheck tests/practice_ui_state.lua` → 0/0). The floor
  drifted to 6-7 during the lane on the SIBLING lanes' in-flight edits
  (`classes/hunter.lua:98`, `tests/shaman_state.lua` × 4 shadowing) — not this
  lane's file.
* **Crossfire (not this lane's red):** a later harness run showed
  `tests/shaman_state.lua` red — "the guide ships twenty-two slots (got 13, want
  22)". The cause is the shaman lane's new `ST.SHAMAN.apply_family_slots()` in
  `post_init` (`classes/shaman.lua:1457`), which narrows
  `ST.SHAMAN.guide.slots` to the running family's 13 rows; the untouched
  expectation is `tests/shaman_guide_state.lua:1636`. The shaman lane owns that
  update. This lane's own suite is green on the same tree.
* **Offline only.** Nothing here is proven in a client: the presses are code
  paths, not observed behaviour.

### Mutation proofs (disposable copies under `/tmp/opencode/gap5mut`)

**12/12 killed**, both baselines clean (`PASS … 1623 checks`).

| Mutant | Killed by |
|---|---|
| M1 the alias block drops `ctx.pick` | §27b "the pick rides in ctx.pick" (all six classes) |
| M2 the alias block drops `ctx.pressed` | §27b "the pick rides in ctx.pressed" (all six) |
| M3 the alias block drops `ctx.action` | §27b "the pick rides in ctx.action" (all six) |
| M4 the whole alias block is removed | §27b (the three alias checks, all six) |
| M5 `scenario_context` stops delivering `ctx.last_action` | §27c "the class's own grader answered a letter" + §27b |
| M6 the drill press carries no pick | §27c "the drill press answered a letter" + §27b |
| M7 the rogue's reader drops `ctx.action` | §27a "the real grader resolves the pick from a ctx carrying only action" |
| M8 the hunter's reader drops `ctx.pick` | §27a "… only pick" (HUNTER) |
| M9 the shaman's reader drops `ctx.pressed` | §27a "… only pressed" (SHAMAN) |
| M10 the paladin's reader drops `ctx.last_action` | §27a "… only last_action" (PALADIN) |
| M11 the warrior's reader drops `ctx.last_action` | §27a "… only last_action" (WARRIOR) |
| M12 the druid's reader drops `ctx.last_action` | §27a "… only last_action" (DRUID) |

## 3. FILED — the production change the shipped behaviour still needs

**The lane may not edit `practice_ui.lua` or the class files (three sibling
lanes own them), so the change is filed here with the exact spec.**

### F-1 (MEDIUM) — a class-published pick alias SHADOWS the drill-list pick

**Where:** `practice_ui.lua:5280-5284` (the alias block in `drill_list_grade`).

**Trigger.** The block only fills an alias the class's ctx left EMPTY
(`if ctx.pick == nil then …`). A class that publishes its own pick alias
therefore keeps it — and the class's own reader, which reads that alias FIRST,
then grades the class's value instead of the player's press.

**Evidence A — the HUNTER, reachable today.** `classes/hunter.lua:4177-4188`
publishes `ctx.pick` = the shot that is casting right now (the live cast). The
hunter's reader (`classes/hunter.lua:3776-3794`) reads `ctx.pick` FIRST. So a
drill-list press made **while a Steady Shot is casting** is graded against the
live cast, not against the player's press.

Measured in the sandbox (the real class module + the real guide + the real
`practice_pressed`, the drill-list path):

```
the drill-list press of "aimed" while a steady cast is in flight:
  ctx.pick = "steady"   ctx.pressed = "aimed"   ctx.action = "aimed"   ctx.last_action = "aimed"
  grade = F        (the player's press was ignored; the live cast was graded)
```

The hunter's own comment says why this is a collision and not a design:
*"The engine's drill press carries no action, so the live cast is the player's
own pick"* (`classes/hunter.lua:4177-4178`). That was true **before** the F2
fix — the engine's drill press carried no action. After the F2 fix the
drill-list press **does** carry an action, so the class-published alias now
shadows it. The scenario path still wants the live cast (there the pick IS the
cast); the drill-list path wants the player's press.

**Evidence B — the ROGUE/SHAMAN shape, reachable the moment a class publishes
`ctx.action`.** `rogue_guide.lua:2132` and `shaman_guide.lua:1163` read
`ctx.action` FIRST. A class ctx that publishes `ctx.action` grades the class's
own value: the sandbox's measured result for the rogue is **grade A** (one
mis-pick banked) for a press of the CORRECT action — the player's press is
graded as a mis-pick. No class publishes `ctx.action` today: of the three
classes that publish a `practice_context` at all (the paladin, the rogue and the
hunter), none of them sets `ctx.action` — the hunter sets `ctx.pick` (the live
cast, see Evidence A), the other two set no pick alias; the shaman, the warrior
and the druid publish no `practice_context` at all. So this is a latent hole,
not a shipped defect.

**The exact change (shape, not a patch — the owner lane writes it):**

`practice_ui.lua`, `drill_list_grade`, the alias block at `:5280-5284`. The
drill-list press **is** the pick: the player's press must win over a
class-published alias. Either

```lua
    if type(pick) == "string" and pick ~= "" then
        ctx.pick = pick
        ctx.pressed = pick
        ctx.action = pick
    end
```

or (the narrower shape, if the class's own pick must survive on the SCENARIO
path) the drill-list press builds its ctx without the class's published pick at
all — e.g. `scenario_context` gains an `opts` that suppresses the class's pick
alias, and only the drill-list path passes it.

**What must NOT change:** the scenario path's behaviour (the hunter's live cast
stays the pick there), and the class-side readers (`rogue_guide.lua`,
`shaman_guide.lua`, `classes/hunter.lua`) — they are correct as they are.

**The pin that must land with the fix** (a new case in §27, or a new section in
the owning class's suite): a drill-list press made while the class's ctx
publishes its own pick alias grades the **player's** press, not the class's
value. §27 as it stands does NOT pin this: the hunter's fixture has no live
cast, so the current (shadowing) behaviour is invisible to it.

**Owner:** the lane that owns `practice_ui.lua` (the drill-list shell) together
with the hunter lane (`classes/hunter.lua`). The operator rules whether the
drill-list press wins outright or the class's own pick is scoped to the
scenario path.

## 4. What this lane did NOT do

* No production file was edited. `tests/practice_ui_state.lua` is the only
  `.lua` file touched (§27 plus the two sandbox lines the class modules need).
* No `run.sh` change (the new cases live in an existing suite — a sibling lane
  owns that line).
* No git commit.
* No lint-config change.
* No new suite file.

## 5. Notes for the next lane

* `practice_ui.lua` is at the **Lua 5.1 local limit** (200 locals in the main
  chunk) and the closure upvalue limit (60) — the sandbox's class-module loader
  is in the TEST file, so it costs the addon nothing.
* The class modules load cleanly under the practice-UI sandbox (no extra
  stubs): the class's own pure guide first, then the class module. The class
  modules need `st.practice`, `st.nextaction` and their own guide — all present
  in that sandbox already.
* The class-side readers' own suites already pin the pure readers
  (`tests/rogue_guide_state.lua:1483-1489`, `tests/shaman_guide_state.lua:3676-3683`).
  What was missing was the **end-to-end** drive and the **hunters'/paladin's/
  warrior's/druid's** readers, whose functions are file-local and reachable only
  through the class's own drill grader — which is what §27 now does.
