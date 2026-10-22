# prepull-contract — the pre-pull contract between a class's pre-pull drill and that class's own pre-pull table

Lane: `prepull-contract` (session `ses_ea618ddf1ffeN3J4FMObHrrDaP`).
Date: 2026-10-20. Scope: the test-sufficiency audit's **Gap 3** (flag strictness for the
paladin) and **Gap 4** (the pre-pull contract), plus the one wrong spell name in
`CHANGELOG.md`.

Every line number below was re-read from the source at write time; the sibling lanes
were editing `classes/hunter.lua`, `classes/rogue.lua`, `classes/shaman.lua`,
`classes/warrior.lua` and `classes/paladin.lua` in parallel, so cite the SYMBOL (stable)
rather than the line.

---

## 1. The contract (the truth in the tree)

Eight published pre-pull tables across the six classes. Each is in exactly one of two
states, and the suite proves which:

| class | table (symbol) | declared at | state | who grades it |
|---|---|---|---|---|
| DRUID | `ST.DRUID.PRACTICE_PREPULLS` | `classes/druid.lua:3410` | CITATION | nobody |
| HUNTER | `ST.HUNTER.PRACTICE_PREPULLS` | `classes/hunter.lua:3713` | GRADED | `hunter_prepull` |
| HUNTER | `ST.HUNTER.PRACTICE_PREPULL_LATE_BANDS` | `classes/hunter.lua:3865` | GRADED | `hunter_prepull` |
| PALADIN | `ST.PALADIN.practice_prepull_rows` | `classes/paladin.lua:4903` | CITATION | nobody |
| ROGUE | `ST.ROGUE.practice_prepulls` | `classes/rogue.lua:3163` | GRADED | `rogue_opener` |
| SHAMAN | `ST.SHAMAN.PRACTICE_PREPULLS` | `classes/shaman.lua:4690` | CITATION | nobody |
| WARRIOR | `ST.WARRIOR.PRACTICE_PREPULLS` | `classes/warrior.lua:5096` | GRADED | `warrior_prepull` |
| WARRIOR | `ST.WARRIOR.PRACTICE_PREPULL_LATE_BANDS` | `classes/warrior.lua:5466` | GRADED | `warrior_prepull` |

Drill keys (each published by its own class only): `hunter_prepull`
(`classes/hunter.lua:4705`), `warrior_prepull` (`classes/warrior.lua:5694`), `rogue_opener`
(`classes/rogue.lua:3514`), `paladin_prepull` (`classes/paladin.lua:6016`). The druid and
the shaman publish none.

### The paladin is the one class with BOTH shapes

`paladin_prepull` grades the paladin's own pre-pull **SEAL SPEC** (the per-order
seal + lead table, `local PRACTICE_PREPULL` in `classes/paladin.lua` — file-local, so it
has no published symbol), while `ST.PALADIN.practice_prepull_rows` is the citation layer
and says so in its own comment (`classes/paladin.lua:4881`, "carried as citations only —
the table is the pre-pull layer, not the rotation"). The suite proves both halves: the
drill's verdict follows the class's own per-order spec, and mutating the citation layer
leaves the drill's verdict untouched.

**This is the one place the brief's wording and the tree disagree.** The brief asked for
"the drill's grader must read that class's own pre-pull table" over the four drill keys,
and for "a class with **no** pre-pull drill must be explicitly marked citation-only — the
paladin already does this in a comment". The paladin HAS a pre-pull drill, and that drill
does **not** read `ST.PALADIN.practice_prepull_rows` (the table has no consumer anywhere
in the tree — verified by a whole-tree symbol scan). The suite therefore asserts what is
true of the tree: the paladin's drill grades the class's own per-order seal spec, and
its published rows table is the marked citation layer. The other two citation-only tables
belong to the classes with **no** pre-pull drill (druid, shaman), and both are marked.

---

## 2. What landed

| file | change |
|---|---|
| `tests/prepull_contract_state.lua` | **NEW** — the contract suite (124 checks) |
| `tests/paladin_state.lua` | the flags are STRICT booleans on every row + the needs-when-unread rule over BOTH axes |
| `classes/druid.lua` | the "NO CONSUMER … CITATIONS ONLY" marker above `ST.DRUID.PRACTICE_PREPULLS` (the druid's table was the one citation-only table with no marking) |
| `CHANGELOG.md` | one word: "10301 on Forever" → "Retribution Aura 10301 on Forever" (10301 is Retribution Aura, confirmed and pinned at `tests/paladin_state.lua`; the corpus had called it "Redemption") |

Not touched (other lanes' files): `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`,
`classes/hunter.lua`, `classes/shaman.lua`, `classes/paladin.lua`, `classes/rogue.lua`,
`classes/warrior.lua`, `tests/run.sh` (contested — the orchestrator adds the line), TOCs,
versions, README, docs.

### The paladin's flag sweep (Gap 3)

`tests/paladin_state.lua` replaced the weak `entry.live ~= nil and entry.engine ~= nil`
test with `type(...) == "boolean"` on both flags, plus the cross-row rule. The rule covers
BOTH axes on purpose: the paladin files on the **ARM** axis (its three un-armed rows are
`live = true` but `engine = false`), so the briefed `live == false` rule alone would be
**vacuous** for the paladin. A row that is unread (`live == false`) OR that carries no
arm (`engine == false`) must name its need.

The hunter lane had already landed the same sweep in `tests/hunter_guide_state.lua`
(`type(entry.live) == "boolean"`, `type(entry.engine) == "boolean"` + the needs rule) and
in `tests/hunter_state.lua` (strict `live`/`engine` booleans on every row + the needs
rule + the compat-wrapper check). Verified, not edited.

---

## 3. The suite: what it proves (and how)

`tests/prepull_contract_state.lua` — plain Lua 5.1, no WoW client. It loads the REAL
`compat.lua`, `utils.lua`, the pure engines and all six class modules in one sandbox
(TBC family, `WOW_PROJECT_ID = 5`), and reads the class sources as text.

**Source side**

1. every published pre-pull table in the six class modules is declared in the contract
   (a seventh, undeclared table fails);
2. every contract row names a table that is really declared;
3. a CITATION table has **no code reference anywhere in the addon tree** outside its own
   declaration (root `*.lua` + `classes/*.lua`, comments AND string bodies blanked, so a
   mention in prose or in a message does not count as a reader);
4. a CITATION table's comment block directly above its declaration carries the marker
   ("citation") **and** the no-consumer statement ("no consumer" / "no drill" / "not
   consumed" / "nothing grades").

**Runtime side**

5. the drill registry: a class's pre-pull drill is published by that class with a
   `grade` function, and by no other class;
6. the drives must produce a REAL verdict (the on-time half must be `"S"`), so a
   degenerate drive cannot pass as evidence;
7. **the coupling**: mutating a table a drill grades must change that drill's verdict;
8. **cross-isolation**: mutating another class's pre-pull table must leave this drill's
   verdict untouched — so a drill reads ITS OWN table and no other class's;
9. a class with no pre-pull drill answers to none of the four drill keys.

The mutation is applied to the class's own table: the family's rows are rewritten with
different actions, and the lateness-band table is replaced with a single `{ max = 99,
grade = "Z" }` band. The plans (the due opener, the pull moments, the press) are computed
ONCE from the pristine table, so a mutation changes the drill's verdict instead of
silently following the mutated data.

Non-vacuity: every scan has a floor (the declaration must exist, the comment block must
exist, the drives must grade), and the paladin's per-order spec must name two orders
with different seals.

---

## 4. The mutants (all on `/tmp/opencode` copies, 9/9 killed)

| # | mutation | killed by |
|---|---|---|
| M1 | the hunter's prepull grade stops reading `ST.HUNTER.PRACTICE_PREPULLS` (hardcoded row) | the coupling check (`S/A -> S/A`) |
| M2 | the druid's citation-only marker is deleted | the marker check (citation + no-consumer) |
| M3 | something starts reading `ST.DRUID.PRACTICE_PREPULLS` | the no-reader check + the marker check (the comment block above the declaration is no longer the one that documents it) |
| M4 | the warrior's prepull grade reads the **hunter's** table | the baseline non-vacuity check (`D/D`) + the coupling check |
| M5 | the paladin's seal spec stops being per-order | the paladin drive check (`S/F/F/S`) |
| M6 | a class publishes a seventh, undeclared pre-pull table | the coverage check |
| M7 | the rogue's ctx builder stops reading `ST.ROGUE.practice_prepulls` | the coupling check |
| M8 | the hunter's prepull grade stops reading its late-band table | the coupling check (`S/A -> S/A`) |
| M9 | the shaman's citation-only marker is deleted | the marker check |

---

## 5. Verification

- `bash tests/run.sh` → **42 steps, 0 failed** at 14:10 (the tree this lane validated
  against). The new suite is **NOT** in the harness yet — `tests/run.sh` is contested
  and this lane did not edit it.
- The final re-run (14:43, after the sibling lanes had moved again) shows **42 steps,
  1 failed**: `tests/hud_state.lua`, whose six failures are all the hunter HUD FAMILY
  slot pins (`hunter Era: six live HUD slots`, `hunter Cata: the Raptor slot carries
  the client's own rank`, `hunter Mists: nine HUD slots`, `hunter Era: no Bestial
  Wrath slot ships`) — the sibling hunter lane's in-flight work (`classes/hunter.lua`
  edited 14:34, `tests/hunter_state.lua` 14:38, `tests/hunter_guide_state.lua` 14:40).
  Nothing in that failure touches the pre-pull layer; the lane's own files
  (`prepull_contract_state.lua`, `paladin_state.lua`, `druid_state.lua`) are green.
- `luacheck .` → **2 warnings / 0 errors in 85 files** at 14:10 — the standing floor
  (both KEEP-ruled, in `compat.lua` and `main.lua`). The count moved to 3 on the 14:43
  re-run when a sibling lane touched another file; the new suite is luacheck-clean
  (**0 warnings**).
- `lua5.1 tests/prepull_contract_state.lua` → **PASS (124 checks)**.
- `lua5.1 tests/paladin_state.lua` → PASS (1041 checks).
- `lua5.1 tests/druid_state.lua` → PASS (1298 checks).
- `CHANGELOG.md` line endings preserved: 838 CRLF lines, the file's last line has no
  terminator (pre-existing).

**The harness line the orchestrator must add** (not added here — `tests/run.sh` is
contested):

```sh
run "lua5.1 tests/prepull_contract_state.lua" lua5.1 tests/prepull_contract_state.lua
```

Place it next to the other class suites (e.g. after `run "lua5.1 tests/paladin_state.lua" …`).

---

## 6. Residuals (filed, not fixed here)

1. **The brief's paladin clause does not match the tree** (see §1). The suite asserts the
   truth; if the operator wants `paladin_prepull` to grade the APL rows table, that is a
   behaviour change to `classes/paladin.lua` (the paladin's own comment says the opposite
   today) and needs an operator ruling, not a test change.
2. The contract suite reads the class sources as text and scans for the symbol. A reader
   that reached a citation-only table through a computed key (`ST[cls]["PRACTICE_PREPULLS"]`)
   would not be seen by the source scan; the runtime coupling checks would still see it,
   because a computed read still changes a drive's verdict.
3. The rogue's pre-pull link runs through the class's own ctx builder
   (`ST.ROGUE.practice_context` → `ctx.prepull_action` → `rogue_guide.grade_opener`), so
   the suite's rogue drive reports the ctx's pre-pull fields alongside the verdict. The
   rotation model is stubbed in the rogue drive (a test double for the engine — the
   contract under test is the pre-pull link, not the rotation).
4. **The suite asserts the citation-only MARKING in the sibling lane's file.** The shaman
   lane owns `classes/shaman.lua` and wrote the "NO CONSUMER … CITATIONS ONLY" marker
   there; this lane's suite checks that the marker (the word "citation" plus a
   no-consumer statement) is present in the comment block above
   `ST.SHAMAN.PRACTICE_PREPULLS`. If that lane rewords the marker, this suite must be
   re-checked — the contract is the MARKING, not one exact wording, but the accepted
   vocabulary is "citation" + one of {no consumer, no drill, not consumed, nothing
   grades}. The druid's and the paladin's markers are in files this lane owns / already
   shipped.

