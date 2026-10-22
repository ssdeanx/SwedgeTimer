# The final test-sufficiency gate: four pins (2026-10-20)

**Desk:** `final-gate-tests` · **Scope:** `tests/practice_ui_state.lua`,
`tests/toc_check.lua`, `CHANGELOG.md` (nothing else) · **Status:** landed, harness
green (43 steps / 0 failed, luacheck 2 warnings / 0 errors in 85 files).

This desk closed the four gaps the final test-sufficiency audit filed (the audit's
own report is the injected context of the dispatch; its four gaps are Gap 1 - the
harness registry's own completeness guard, Gap 2 - the CHANGELOG's false claim about
the published neutral sets, Gap 3 - the scenario strip's unpinned guide-vocabulary
leg, Gap 4 - the unpinned zero-neutral default-visible guard).

## 1. Gap 3 (BLOCKING) - the guide-vocabulary leg is pinned end to end

**The risk the audit named:** the action strip has three legs
(`practice_ui.lua`'s `scenario_action_order`): the class's published rotation, the
class's own GUIDE SLOT list, and the keys the class asked for. The common abilities
live in the middle leg - the class seam (`apply_practice_panel_actions`) appends them
to `guide.slots`, and the panel reads `guide.slots` LIVE. Every button key any suite
asserted was also a rotation action, so dropping the guide leg removed EVERY
neutral/common ability from the panel and the suite stayed green.

**The pin (`tests/practice_ui_state.lua` §27b, 60 new checks):** for each of the six
classes, in the real-class-module sandbox of §27, after `u.start(T)` in scenario
mode:

* (a) the strip's action group carries the class's OWN guide key - a key of the
  class's guide slot list that the running family's rotation does NOT rank (the
  pin asserts that premise itself through the class's own
  `practice_rotation_action_set()`);
* (b) the strip carries the class's common ability with **the CLIENT'S OWN resolved
  spell id** - the sandbox's client is seeded with one rank of that ability and the
  pin reads the resolved id back (the client's rank, NOT the ladder's first id: the
  food ladder starts at 433 and the pin demands the client's 10256);
* (c) the **negative half**: the same class on a client that knows NONE of the
  common spells offers NO common button (unknown-hides), while the class's own guide
  key still reaches the strip - so the negative half is not vacuous and the strip is
  not simply empty.

**The family is per class** (the guide vocabulary is family-scoped): Era for the
paladin, the druid, the rogue, the shaman and the hunter; **Forever for the
warrior**, whose own vocabulary IS its rotation vocabulary on Era and TBC (so its
pin needs the family whose slot set carries a key the rotation does not rank - the
Forever set's Cleave). The spec table is §27's own table, hoisted to file scope as
`PRACTICE_CLASS_SPECS` with four extra fields.

**Sandbox support (the only test-side change):** `build()` grew two options -
`opts.project_id` (the compat layer's own `WOW_PROJECT_ID` probe: the family the
sandbox pretends to be) and `opts.client_spells` (the spell ids the sandbox's client
knows, on top of the fixed base set - the client's own spell data).

### Mutation proofs (`/tmp/opencode` copies; the repo tree was never mutated)

| mutant | killed by |
|---|---|
| **M1** the guide leg dropped from `scenario_action_order` (`practice_ui.lua:4791-4799`) | 24 checks fail (4 per class: the strip offers neither the class's own guide key nor the common ability, in both the positive and the negative sandbox). **The full harness on the mutant: 43 steps, 1 failed - this pin is the ONLY guard.** |
| **M4** `compat.lua`'s `family_spell_exists` always answers true (the client never refuses an id) | the negative half fails for all six classes (the common abilities leak into the strip) AND the id pin fails (`got 10257, want 10256` - the ladder's highest id instead of the client's rank) |
| **M5** all six classes resolve the ladder's FIRST id instead of the client's rank | the id pin fails for all six classes (`got 433, want 10256` / `got 5185, want 25297`) - the pin reads the CLIENT's answer, not the tree's ladder |
| **M6** the class seam stops widening the guide slot list (all six classes) | the "the action strip offers the common ability" pin fails for all six classes (also caught by 3 other suites) |

## 2. Gap 2 (BLOCKING) - the CHANGELOG tells the truth about the six published sets

`CHANGELOG.md:787-788` claimed "The **hunter** and the **druid** publish none: their
lists are worked out and filed, not landed." The tree publishes **six of six**. The
clause now reads the tree, in two sentences plus the citation, inside the same
bullet ("The per-class sets"):

* the hunter and the druid publish family-scoped buckets - Era, TBC, WotLK and
  Forever for both, the hunter's without `raptor` on WotLK and Forever and the
  druid's without `rake` on WotLK and Forever;
* the four family-scoped classes publish **no bucket for Cata, Mists or Retail**, so
  on those three clients the offer gate offers **no** common ability at all (the
  flat paladin and the flat shaman still answer every family) - cited to
  `bench/class_neutral_family_coverage_2026-10-20.md` §1.2/§5.

Two counts in the same bullet had to move with it, or the file would still state the
falsehood the audit names: "Four of the six classes publish one today" -> "All six
classes publish one today", and "each of the four classes publishes a
**practice-panel ability list**" -> "each of the six classes" (all six publish
`ST.<CLASS>.practice_common_actions`). **Nothing outside that bullet changed** - the
diff is three hunks on lines 780 and 788-789, CRLF preserved on every line.

## 3. Gap 1 - the harness registry self-checks, both directions

`tests/run.sh` is an explicit per-suite registry; a suite added without its registry
line yields a GREEN harness that never runs the new suite (this tree has produced
that accident once - the pre-pull contract suite existed unregistered for a window).
The check lives **inside the already-registered `tests/toc_check.lua`** (no new
registry line needed) and pins:

* every suite on disk (`tests/*.lua`) is registered in `tests/run.sh`;
* every suite registered in `tests/run.sh` exists on disk;
* the registered count equals the number of `run "lua5.1 tests/…"` lines (a suite
  registered twice is caught too), and the registry and the disk agree in number.

Every failure names the offending file, the way `wiring_check.lua` prints evidence.

### Mutation proofs

| mutant | killed by |
|---|---|
| **M3a** a suite on disk with no registry line (`tests/orphan_suite.lua`) | `FAIL every suite on disk is registered in tests/run.sh (unregistered: tests/orphan_suite.lua)` |
| **M3b** a registry line naming a file that does not exist | `FAIL every suite registered in tests/run.sh exists on disk (missing on disk: tests/ghost_check.lua)` + `FAIL ... (unregistered: tests/wiring_check.lua)` |
| **M3c** a suite registered twice | `FAIL tests/run.sh runs every registered suite exactly once (41 registered, 42 registry lines)` |

## 4. Gap 4 - the zero-neutral default-visible guard is pinned

The shipped contract is "the neutral count is reported **only when > 0**", so a class
with no published set reads exactly as before. `tests/practice_ui_state.lua` §22n now
finishes the run (one step) after the mis-pick press and asserts that the run
summary and the panel readout contain **no** "neutral" text at all. The positive
half already lived in §22o (a class WITH a published set reports its count).

**Mutant:** `if neutral > 0` -> `if neutral >= 0` in both summary branches and
`(summary.neutral or 0) > 0` -> `>= 0` in the panel readout -> **both new assertions
die** (`FAIL the run summary of a class with no published set names no neutral`,
`FAIL the panel readout of a class with no published set names no neutral`). The full
harness on the mutant: 43 steps, 1 failed - again only the new pin catches it.

## 5. The verification

* **Harness:** `bash tests/run.sh` -> **43 steps, 0 failed**.
* **luacheck:** **2 warnings / 0 errors in 85 files** - the standing floor
  (`compat.lua:36`, `main.lua:81`), both pre-existing. The two touched test files
  are **0/0** on their own.
* **Suites:** `tests/practice_ui_state.lua` **1760 checks** (was 1697; +60 from §27b
  and +3 from §22n), `tests/toc_check.lua` **871 checks** (was 865; +6 from the
  registry block).
* **Line endings:** `CHANGELOG.md` CRLF kept (every changed line ends `\r\n`); the
  two test files are LF, as they were.
* **The repo tree was never mutated:** every mutant was proved on a
  `/tmp/opencode/mut_*` copy of the tree. A `diff -rq` against the pre-edit copy
  shows exactly three changed files - `CHANGELOG.md`, `tests/practice_ui_state.lua`,
  `tests/toc_check.lua` - and no addon file.

## 6. UNCONFIRMED / not proven here

* **In-client:** nothing here is proven in a client. The strip's buttons, the
  client's own resolved ids and the panel readout are offline-proven only; the
  operator's in-client pass remains the only way to confirm the real client's spell
  data.
* **The client's spell data is a fixture.** The sandbox client answers for the ids
  the pin seeds (the client's own rank of the ability). The real client answers for
  its own ranks; the pin proves the RESOLUTION reads the client (M4, M5), not that
  any real client has that exact rank.
* **The family choice is a fixture too.** The pin runs each class on one family
  (Era for five, Forever for the warrior). A family's slot set is the class's own
  statement, and a change to it moves the pin's `guide_key` - the same rule the
  other rotation pins in the tree follow (one table, one place to update).
