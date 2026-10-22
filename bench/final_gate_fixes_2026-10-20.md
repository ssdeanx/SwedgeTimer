# The final gate's HIGH-3 and the three MEDIUMs (2026-10-20)

**Desk:** `final-gate-fixes` · **Scope:** `classes/paladin.lua`,
`classes/warrior.lua`, `classes/shaman.lua`, `tests/paladin_state.lua`,
`tests/warrior_state.lua`, `tests/shaman_state.lua`, `tests/toc_check.lua`
(the local-ceiling guard only) · **Status:** landed, harness green.

The source: `bench/final_gate_audit_2026-10-20.md` (session
`ses_ea50b69a7ffeT9t274D7oLIr6m`) - HIGH-3 (the file-scope local ceiling) and
MEDIUM-1 (the shaman's widening), MEDIUM-2 (the paladin's flat publish on the
4.0+ clients) and MEDIUM-3 (the two stale comments). HIGH-1 and HIGH-2 belong
to a sibling lane; this lane only corrected the HIGH-2 COMMENT in its own three
class files.

---

## 0. HIGH-3 - the local ceiling was a load failure, not a test failure

### 0.1 What the ceiling really is

Lua 5.1 caps one chunk at **200** local variables. Measured on this machine
(`luac5.1 -p` on a 250-local file):

```
luac5.1: t250.lua:201: main function has more than 200 local variables
```

Two facts matter for the guard:

* the limit is on the **active** locals of a chunk, and `luac5.1 -l -l` prints
  the chunk's **total** local declarations (`0+ params, N slots, 0 upvalues,
  N locals, ...`). The total is an upper bound on the active count, so it is
  the conservative metric - a file at 190 by that measure has at most 190
  active locals;
* a block-scoped local declared at file scope shares the chunk's budget
  (measured: 150 top-level locals plus 100 locals in separate `do ... end`
  blocks compiles fine; 250 top-level locals does not).

The count is therefore **the compiler's own**, and it counts **names**: one
`local a, b` line is two locals (measured: a file at 183 locals went to 185
after one such line was appended).

### 0.2 The counts, before and after

| file | before | after | headroom before | headroom after |
|---|---|---|---|---|
| `classes/paladin.lua` | **200** | **185** | 0 | 15 |
| `classes/warrior.lua` | **200** | **181** | 0 | 19 |
| `classes/shaman.lua` | 199 | **179** | 1 | 21 |

(The same metric the audit measured: `luac5.1 -l -l <file>`.)

### 0.3 What moved, and where it went

The class modules' own precedent (`APL_UTILITY`, `practice_action_meta`,
`practice_apl_rows`, `practice_prepull_rows` in the paladin; `WARRIOR_UTILITY`
in the warrior) is the module table - so the display constants moved there:

* `classes/paladin.lua` - `ST.PALADIN.aow_pulse` (6), `.twist_colors` (5),
  `.twist_glow` (4) = **15** locals moved;
* `classes/warrior.lua` - `ST.WARRIOR.hud_style` (5), `.bar_style` (12),
  `.HUD_COOLDOWN_FALLBACK` (1), `.HUD_SKIP_GCD` (1) = **19** locals moved;
* `classes/shaman.lua` - `ST.SHAMAN.flame_shock_style` (5),
  `.stormstrike_style` (5), `.shield_style` (6), `.position_style` (4) = **20**
  locals moved.

**54 file-scope locals moved, and every value is byte-identical.** Two proofs:

1. a literal-by-literal comparison of the old constants (base tree) against the
   new table fields: *checked 53 moved constants - PASS every moved constant
   carries the identical literal value* (`/tmp/opencode/equiv_check.py`; the
   two reference-shared entries - the Rampage tier colours and the clean
   desync tint - are compared by their target, and they still point at the
   same two values);
2. the new **style pins** in the three class suites (`tests/paladin_state.lua`
   +19 checks, `tests/warrior_state.lua` +25, `tests/shaman_state.lua` +23),
   which carry the archive's own numbers.

Nothing was mutated: the moves are table-field reads where a local read was
(a read-only constant in every case - the moved tables are never mutated).

### 0.4 The guard (`tests/toc_check.lua`, an already-registered step)

No new registry line: the check lives inside `tests/toc_check.lua`, which
`tests/run.sh` already runs.

* it counts **every** addon module (the repo root + `classes/` - 43 chunks,
  the ones the client loads; the test files are separate chunks);
* it fails above **190**, and the message names the file, the count and the
  headroom: `FAIL classes/druid.lua: 194 file-scope locals (limit 190,
  headroom 6)`;
* it prints every file's count, so **the next lane sees the headroom before
  it trips it** (the tightest file is named in a closing check);
* `practice_ui.lua` (199 - at the ceiling) is **not** this lane's file to
  change, so it carries a **baseline of 199**: a ratchet (it may shrink, never
  grow). Every other file is held to the 190 limit.

### 0.5 Is the count brittle?

**No.** The guard does not parse the source: it asks the compiler
(`luac5.1 -l -l`), so a refactor cannot change the number by accident and the
number cannot drift from the limit the compiler enforces. The one dependency
is `luac5.1` on PATH - which `tests/run.sh`'s first step
(`luac5.1 -p` on every addon file) already requires, so the floor is
unchanged; a machine without it is already red at step 1. The alternative (a
hand-written source scanner) was rejected: it would have to re-implement the
block/function nesting to match the compiler, and it could silently
under-count - the dangerous direction.

---

## 1. MEDIUM-1 - the shaman's panel now widens on every family

`classes/shaman.lua`'s `apply_family_slots` returns **before** the widening
when the running family carries no rotation row (the Cata and the Mists
clients), so `apply_practice_panel_actions()` was never reached there and the
panel offered the guide vocabulary alone - narrower than the class's own
`practice_panel_slots` on those two clients (the gap the owning lane's own
note recorded).

The fix is the other five classes' pattern: `ST.SHAMAN.post_init` now calls
`ST.SHAMAN.apply_practice_panel_actions()` itself, right after
`apply_family_slots()`. The call is idempotent (a strip that already carries a
common slot is left alone), so on a rotation family the behaviour is exactly
what it was.

**The pins** (`tests/shaman_state.lua`): the sandbox now answers the five
common abilities' names (a client that has the spell does), which makes the
widening observable end to end. Two pins that were **green but wrong** (the
strip's published list and the TBC slot count - the real client has always
carried the common slots on a rotation family) now state the truth, and a new
pin proves the widening on a family with **no** rotation row (the Cata
client): the five common abilities reach the panel.

---

## 2. MEDIUM-2 - the paladin's publish is family-scoped

`ST.PALADIN.practice_neutral_actions` is now **one bucket per family**:

| family | the seal (`sotc`) | the other ten keys |
|---|---|---|
| ERA (the SoD build rides the Era client), TBC, WRATH, FOREVER | published | published |
| CATA, MISTS, RETAIL | **not published** (the spell was removed in 4.0) | published |

**The classic line is unchanged** - a SoD build still rides the Era bucket, and
the ERA/TBC/WRATH/FOREVER buckets carry exactly the set the flat publish
carried. The only behaviour change is on the 4.0+ clients: a `sotc` press there
is a mis-pick instead of a silent neutral press - the same treatment the
rogue's 4.0-removed Shiv already gets (`bench/class_neutral_family_coverage_2026-10-20.md`
§1.2 and §6).

**Why the 4.0+ clients keep a bucket** (the judgement the audit left open):
the bucket is the class's own statement about the panel it offers there; the
ten keys are legitimate presses on those clients (the class publishes no
rotation for them, so none of them is rotation-ranked), and dropping the
bucket would also drop the offer list there - a behaviour change the audit did
not ask for and the CHANGELOG (which says the flat paladin answers every
family) does not describe. The buckets therefore differ in **exactly one
key**, and the offer gate picked the change up with no further change.

**The pins:** `tests/paladin_state.lua` (which now owns the publish's pin -
`tests/neutral_actions_state.lua` says so at its header) checks every family's
bucket, the seal's presence per family and the ten shared keys.

**No out-of-scope test edit was needed:** the sibling lane's
`tests/neutral_actions_state.lua` already carried the post-fix expectation
(the Cata/Mists/Retail slices without `sotc`, `sotc` as an intentional
mis-pick), and the suite was green on the first run of this lane's change.

---

## 3. MEDIUM-3 - the two comments are true again

1. `classes/warrior.lua`'s ability-list note claimed the common abilities
   "have NO key in the warrior's own ability list" while the class publishes
   exactly those keys. It now states the truth: food, the potions, the
   Demoralizing Shout and the Sprint have no key in the **rotation and guide**
   vocabulary (the APL's consumable rows are items, not spells) but they DO
   have one in the class's own **practice-panel ability list**, where the
   publish offers them per family; the Defensive Stance and the Stoneform
   still carry no key anywhere (the utility spine carries the Battle, the
   Berserker and the Gladiator stances).
2. The resolver note's "every client family answers its own rank art" is
   **false** (the audit's HIGH-2): the fallback hands the ERA corpus's rank-1
   id - the Healthstone's own Cata/Mists rank is 6262 and the Era 5720 answers
   "Not Found" there - and the classic-line name leg is UNCONFIRMED in-client
   (audit §6 C1). The three in-scope class modules now say what the code does.

**The pins:** three source-shape pins on the **absence** of the stale phrases
(a correct rewording still passes) and one on the presence of the corrected
statement.

---

## 4. The verification

* **Harness:** **43 steps, 0 failed** (`bash tests/run.sh`).
* **luacheck:** **2 warnings / 0 errors in 85 files** - the standing floor
  (`compat.lua:36`, `main.lua:81`), both pre-existing and KEEP-ruled. The one
  new warning this lane briefly added (an unused loop variable in a new pin)
  was **wired**, not silenced with `_`.
* **Suites:** `tests/paladin_state.lua` **1234** (was 1041), `tests/warrior_state.lua`
  **2046** (was 2017), `tests/shaman_state.lua` **1064** (was 1035),
  `tests/toc_check.lua` **917** (was 871). The other 39 suites are unchanged
  and green.
* **Line endings:** CRLF kept in `classes/paladin.lua` and `classes/warrior.lua`;
  LF kept in `classes/shaman.lua` (its tabs are intact) and in the four test
  files.
* **No git, no TOCs, no versions, no CHANGELOG/README/docs, no lint config,
  no other addon file.**

### 4.1 The mutation proofs (on `/tmp/opencode` copies - the repo tree was never mutated)

| mutant | killed by |
|---|---|
| M1 eleven extra file-scope locals in `classes/druid.lua` (183 -> 194) | the guard: `FAIL classes/druid.lua: 194 file-scope locals (limit 190, headroom 6)` |
| M2 the AoW overlap pulse length 0.4 -> 0.5 | the paladin suite: the style pin **and** the class's own P6 pulse-window pin |
| M3 the shaman's `post_init` widening call removed | the shaman suite: the two new "widening on a family with no rotation row" pins |
| M4 the paladin's publish carries a flat key again | the paladin suite ("the publish is family-scoped") **and** the neutral suite ("the family bucket sotc is a set") |
| M5 the Cata bucket publishes `sotc` again | the paladin suite ("the Seal of the Crusader is neutral on CATA") **and** the neutral suite (the published-set and mis-pick-list pins) |
| M6 the stale warrior ability-list comment is back | the warrior suite's comment-truth pin |
| M7 the stale "every client family answers its own rank art" claim is back | the warrior suite's two comment-truth pins |

**9 kills, 0 escapes**, and the five control runs on the unmutated copy are
green (`/tmp/opencode/mutation_proofs_output.txt`).

---

## 5. Filed for the orchestrator (out of this lane's scope)

1. **The CHANGELOG is now stale** (`CHANGELOG.md:780-793`, "The per-class
   sets"): it says the **paladin** publishes a *flat* set with `sotc` and that
   "the flat paladin and the flat shaman still answer every family". The
   paladin's publish is now family-scoped (the flat shape is kept only where
   it is exact - the classic line), and the Cata/Mists/Retail buckets carry no
   `sotc`. The CHANGELOG is not this lane's file; the doc lane owns the
   correction.
2. **The same false "rank art" claim** is still in `classes/hunter.lua:5151`
   and `:5225`, `classes/druid.lua:4415` and `:4523`, and
   `classes/rogue.lua:3128` and `:3197` - the same three in-scope files'
   correction applies to them, but they are not this lane's files.
3. **`practice_ui.lua` is at the ceiling** (199 of 200) and carries the guard's
   baseline. It is not this lane's file to change; the next lane that touches
   it should move a constant onto the module table and tighten the baseline
   to 190.
4. **/tmp is full** (a 16 GB tmpfs at 100%): other lanes' mutation copies
   (`/tmp/opencode/mut_gap3neg`, `mut_gap3seam`, `mut_gap4`, `mut_reg_a/b/c`,
   `tocdbg`, `shaman-slots-mut`, `m3_mut` - about 2 GB of them) were left in
   place; this lane's copies were trimmed to the tree minus `Media/`.

## 6. UNCONFIRMED / not proven here

* **In-client:** the panel's action row on a Cata or a Mists client (the dead
  Seal of the Crusader and the shaman's five common abilities) is
  **offline-proven only**. The audit's own checklist items C4 and C5 (the
  operator's in-client pass) still owe the runtime confirmation.
* **The 4.0 clients' own spell data:** the seal's absence on the Cata and the
  Mists clients rests on the expansion pages ("Not Found" for 20308 and for the
  whole 21082 / 20162 / 20305-20308 ladder), cited in
  `bench/class_neutral_family_coverage_2026-10-20.md` §1.2/§6 - not on an
  in-client read.
* **The local ceiling's in-client effect:** the counts are the compiler's, so
  the load-failure claim is exact; but no client was loaded to prove it.
