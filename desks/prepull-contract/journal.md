# prepull-contract — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the test-sufficiency audit's **Gap 3** (flag strictness for the
  paladin) and **Gap 4** (the pre-pull contract), and fix the one wrong spell name in
  `CHANGELOG.md`. Gap 4's complaint: the six classes each publish an APL pre-pull rows
  table and the per-class suites pin the SHAPE of those tables — but only three of them
  are actually graded. The pins over the three dead tables read like pre-pull coverage
  for six classes when three classes have none. A shape pin cannot tell a live table
  from a dead one; only the RELATIONSHIP can.
- **Scope:** `tests/paladin_state.lua` (strict flags + the needs-when-unread rule),
  `classes/druid.lua` (the citation-only marking only), NEW `tests/prepull_contract_state.lua`,
  `CHANGELOG.md` (one word). `tests/run.sh` is CONTESTED — this lane does not edit it and
  reports the line instead. `tests/hunter_state.lua` belongs to the sibling hunter lane
  (two writers in one file is crossfire this project keeps paying for) — verified only.
- **Build:** (1) the paladin's flags become STRICT booleans and the needs-when-unread
  rule covers BOTH axes (the paladin files on the ARM axis, so the briefed `live ==
  false` rule alone would be vacuous); (2) the druid's citation-only marking; (3) a new
  contract suite that asserts the RELATIONSHIP per published pre-pull table — GRADED
  (proven at runtime by mutation, plus cross-isolation) or CITATION-ONLY (proven by a
  whole-tree no-reader scan plus the source marker); (4) the CHANGELOG's "10301 on
  Forever" → "Retribution Aura 10301 on Forever".
- **Next step:** read the bench trail (done: `bench/lessons.md`, the central journal),
  implement, pin, prove the mutations on `/tmp/opencode` copies, report.

## 2026-10-20 — The contract landed
- **Worked on:** four files. `tests/paladin_state.lua` gained the strict boolean sweep
  on both flags plus the needs-when-unread rule over both axes (the three un-armed
  paladin rows are `live = true, engine = false` and name their need, so the rule is
  non-vacuous). `classes/druid.lua` gained the "NO CONSUMER (stated here so nothing
  implies coverage that does not exist): this table is CITATIONS ONLY" marker above
  `ST.DRUID.PRACTICE_PREPULLS`, worded like the sibling shaman lane's marker (the druid
  was the one citation-only table with no marking). NEW `tests/prepull_contract_state.lua`
  is the contract suite: 124 checks over the eight published pre-pull tables (the druid,
  hunter x2, paladin, rogue, shaman, warrior x2) — a GRADED table's drill must change
  its verdict when that table is mutated and must NOT change when another class's table
  is mutated; a CITATION table must have no code reference anywhere in the addon tree
  and must carry the marker plus the no-consumer statement in the comment block above its
  declaration. `CHANGELOG.md` line 615 now reads "Retribution Aura 10301 on Forever"
  (10301 is Retribution Aura, confirmed and pinned at `tests/paladin_state.lua`; the
  corpus had called it "Redemption"). CRLF preserved (838 CRLF lines, the file's last
  line has no terminator — pre-existing).
- **Current state:** `bash tests/run.sh` → **42 steps, 0 failed** at 14:10 (the tree this
  lane validated against); luacheck **2 warnings / 0 errors in 85 files** (the floor; the
  new suite is luacheck-clean, 0 warnings). The 14:43 re-run shows **42 steps, 1
  failed** — `tests/hud_state.lua`, whose six failures are all the sibling hunter lane's
  in-flight HUD FAMILY slot pins (Era/Cata/Mists slot counts, Bestial Wrath slot, Raptor
  rank); `classes/hunter.lua` was edited at 14:34 and the hunter suites at 14:38-14:40.
  Nothing in that failure touches the pre-pull layer. This lane's own suites are green:
  `lua5.1 tests/prepull_contract_state.lua` → **PASS (124 checks)**;
  `lua5.1 tests/paladin_state.lua` → PASS (1041 checks);
  `lua5.1 tests/druid_state.lua` → PASS (1298 checks). Nine mutants on
  `/tmp/opencode` copies — **9/9 killed** (the hunter's drill stops reading its table;
  the druid's marker deleted; the druid's table gains a reader; the warrior's drill
  reads the hunter's table; the paladin's seal spec stops being per-order; a class
  publishes an undeclared seventh pre-pull table; the rogue's ctx builder stops reading
  its table; the hunter's drill stops reading its late-band table; the shaman's marker
  deleted). Bench file: `bench/prepull_contract_2026-10-20.md`.
- **What did not work / was hard:** the brief's paladin clause does not match the tree.
  It asks that "the drill's grader must read that class's own pre-pull table" over the
  four drill keys (including `paladin_prepull`) and, in the same sentence, that "a class
  with **no** pre-pull drill must be explicitly marked citation-only — the paladin
  already does this in a comment". The paladin HAS a pre-pull drill, and that drill
  grades the class's own per-order SEAL SPEC (`local PRACTICE_PREPULL`, file-local, no
  published symbol) — NOT `ST.PALADIN.practice_prepull_rows`, which has no consumer
  anywhere in the tree (verified by a whole-tree symbol scan). The suite therefore
  asserts what is true: the paladin's drill follows the class's own per-order spec (two
  orders with different seals grade differently), and its published rows table is the
  marked citation layer. The paladin's own comment says exactly this, so the tree and
  the suite agree; making the drill grade the APL rows instead would be a behaviour
  change to `classes/paladin.lua` and needs an operator ruling, not a test change —
  filed as residual 1. Also: a Lua 5.1 read-trap cannot proxy an ARRAY (no `__len` in
  5.1), so the lateness-band tables are proven by MUTATION (replace the bands with one
  `{ max = 99, grade = "Z" }`) rather than by a proxy; the family-keyed row tables could
  have used either. The rogue's link runs through the class's own ctx builder, so the
  rogue drive reports the ctx's pre-pull fields next to the verdict, and the rotation
  model is stubbed (a test double for the engine — the contract under test is the
  pre-pull link, not the rotation).
- **Next step:** the orchestrator validates and adds the harness line
  `run "lua5.1 tests/prepull_contract_state.lua" lua5.1 tests/prepull_contract_state.lua`
  (this lane did not edit `tests/run.sh` — it is contested). Residual 1 (the paladin's
  clause) needs an operator ruling; residual 4 (the suite asserts the sibling shaman
  lane's marker wording) needs a re-check if that lane rewords it.

## 2026-10-20 — [signal:done] the pre-pull contract is pinned and the citation-only tables are labelled
- Gap 3 and Gap 4 are closed offline: the paladin's flags are strict booleans with the
  needs rule over both axes; the new `tests/prepull_contract_state.lua` (124 checks)
  asserts the drill↔table RELATIONSHIP for all eight published pre-pull tables and the
  citation-only marking for the three dead ones; the druid's table is labelled; the
  CHANGELOG's wrong spell name is corrected. Nine mutants, nine kills.
