# Drill Pick Contract — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the test-sufficiency audit's **Gap 5** — the drill-list pick
  channel was pinned only through a hand-written paladin-shaped stub, so the real
  grader shapes (the rogue's `get_practice_pick`, the shaman's `get_practice_pick`,
  the hunter's `practice_pressed`) were unprotected end to end.
- **Scope:** `tests/practice_ui_state.lua` (the new cases only). READ ONLY: the
  class files and guide files whose graders are driven (`classes/rogue.lua`,
  `rogue_guide.lua`, `classes/shaman.lua`, `shaman_guide.lua`, `classes/hunter.lua`,
  `hunter_guide.lua`, `classes/paladin.lua`, `classes/warrior.lua`,
  `classes/druid.lua`, `warrior_guide.lua`, `druid_guide.lua`, `druid_energy.lua`).
  NO production edit: any change that IS needed is filed with an exact spec.
- **Next step:** drive the six classes' REAL graders through the drill-list path,
  pin the alias-delivery contract, and file the production change the shipped
  behaviour needs (the class-published `ctx.pick` shadowing).

## 2026-10-20 — Gap 5 closed: the six classes' real graders, driven end to end
- **Worked on:** `tests/practice_ui_state.lua` §27. The sandbox grew
  `opts.class_modules` (a class's own pure guide first, then the class module) and
  the six class tables on the addon object, so the ENGINE's own
  `H.practice_class_module` finds the real class module. Each class's live gather
  is stubbed (the sandbox has no client) — the grader under test is the class's
  own. Per class: the row's ACTION button press (the pick) and the DRILL button
  press (the pick in hand) each reach the real grader and answer **S**; the ctx
  the real grader received is asserted to carry the pick in `last_action`,
  `pick`, `pressed` and `action`; and the ctx is replayed with exactly ONE pick
  alias to pin each class's own reader (a letter with the alias, nil without it).
- **Current state:** harness **41/0**; `tests/practice_ui_state.lua` 1623 checks
  (was 1455); luacheck **2 warnings / 0 errors in 83 files** (the floor); **12/12
  mutation proofs killed** on disposable copies (`/tmp/opencode/gap5mut`), both
  baselines clean. Bench artifact: `bench/drill_pick_contract_2026-10-20.md`.
- **Next step:** the operator rules on **F-1** (filed, MEDIUM): a class-published
  pick alias SHADOWS the drill-list pick, because the alias block only fills an
  EMPTY alias (`practice_ui.lua:5280-5284`). Reachable today for the **hunter**
  (`classes/hunter.lua:4177-4188` publishes `ctx.pick` = the live cast; the
  hunter's reader reads `ctx.pick` FIRST): a drill-list press made while a
  Steady Shot is casting is graded against the live cast, not the player's press
  (measured: the press of "aimed" graded **F** with `ctx.pick = "steady"`).
  The fix belongs to the `practice_ui.lua` owner + the hunter lane; §27 does NOT
  pin it (the hunter's fixture has no live cast).

## 2026-10-20 — What did not work (so the next lane does not repeat it)
- The class-side alias readers (`practice_action`, `practice_pressed`, the
  warrior's and the druid's inline reads) are **file-local**: they cannot be
  called directly from a test. The only way to reach them is through the class's
  own exported drill grader, which is why §27 drives the class's REAL drill
  instead of a hand-written stub.
- A hand-built ctx does not survive the class's decision machinery (the hunter's
  `practice_decision` reads `ctx.last_action` to model the cast, so stripping the
  aliases changes the verdict). §27 therefore REUSES the ctx the drill-list path
  really delivered and only strips the pick aliases — the ctx stays the class's
  own, the alias is the only variable.
- The class modules load cleanly in the practice-UI sandbox with NO extra stubs
  (the class's own guide first, then the class module). That was not obvious
  from the class files' size and cost the first probe run.

## 2026-10-20 — [signal:hands-up] F-1: a class-published pick alias shadows the drill-list pick
- **Why:** the alias block (`practice_ui.lua:5280-5284`) only fills an EMPTY
  alias, so a class that publishes its own pick alias keeps it — and the reader
  that reads that alias FIRST grades the class's value, not the player's press.
  Reachable today for the **hunter** (`classes/hunter.lua:4177-4188` publishes
  `ctx.pick` = the live cast; the reader reads `ctx.pick` FIRST): the press of
  "aimed" during a Steady Shot cast graded **F** with `ctx.pick = "steady"`.
  Latent for the **rogue** and the **shaman** (they read `ctx.action` first).
- **Needed from the operator:** who owns the pick in the drill-list path — the
  player's press, or the class's own published pick? The lane may not edit
  `practice_ui.lua` or the class files.
- **Spec filed:** `bench/drill_pick_contract_2026-10-20.md` §3 (file:line, the
  two candidate shapes, what must not change, and the pin that must land with
  the fix).
- **Signal:** `.signals/2026-10-20T15-38-22Z.json` (escalation / hands-up).

## 2026-10-20 — [signal:done] Gap 5 closed
- `tests/practice_ui_state.lua` §27: the six classes' real graders driven end to
  end through the drill list (action press + drill press, both answering S), each
  class's own alias reader pinned with the ctx shape it reads, and the
  alias-delivery contract pinned behaviourally on the ctx the real grader
  received.
- Harness **41/0**; the suite 1623 checks (was 1455); luacheck **2/0** (the
  floor); **12/12** mutation proofs killed, both baselines clean.
- **Signal:** `.signals/2026-10-20T15-38-22Z-done.json` (execution / done).
- **Next step:** the operator validates; the `practice_ui.lua` owner + the hunter
  lane take F-1.

## 2026-10-20 — Crossfire note (not this lane's red)
- The harness shows **41 steps, 1 failed**: `tests/shaman_state.lua` →
  "the guide ships twenty-two slots (got 13, want 22)" and "every live rotation
  line names a declared guide slot".
- **Not this lane's work.** The failing check is `tests/shaman_guide_state.lua:1636`
  (untouched since 03:39); the cause is `classes/shaman.lua:1457` — the shaman
  lane's new `ST.SHAMAN.apply_family_slots()` in `post_init` narrows
  `ST.SHAMAN.guide.slots` to the RUNNING FAMILY's 13 rows, so the untouched
  22-slot expectation no longer holds. `classes/shaman.lua` was written at
  11:39:44, five minutes after this lane's last edit.
- This lane's own suite is green (**1623 checks**) on that same tree, and the
  shaman case in §27 passes with the narrowed vocabulary: the pick "flameshock"
  is still one of the family's rows, and the row-offer check
  ("the drill-list row offers the class's action") would fail LOUDLY if a
  vocabulary change ever drops it.
- The shaman lane owns the `tests/shaman_guide_state.lua` expectation update.
- The **luacheck floor also drifted** during the lane (2 warnings → 6 → 7) and the
  extra warnings are all in the siblings' files: `classes/hunter.lua:98`
  (unused `steady_id_by_family`, the hunter lane) and `tests/shaman_state.lua`
  (4 shadowing warnings, the shaman lane). **This lane's file is clean**
  (`luacheck tests/practice_ui_state.lua` → 0 warnings / 0 errors), so the floor
  is the siblings' to restore, not this lane's.



