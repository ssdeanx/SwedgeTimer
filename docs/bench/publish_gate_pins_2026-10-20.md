# The publish-gate pins: F-1, F-2, F-3 (2026-10-20)

**Desk:** `publish-gate-pins` · **Scope:** `tests/practice_ui_state.lua`,
`tests/neutral_actions_state.lua`, `tests/toc_check.lua` (nothing else) ·
**Status:** landed, harness green (43 steps / 0 failed, luacheck 2 warnings /
0 errors in 85 files — the standing floor).

The three last findings of the final publish-gate re-audit. All three are **test
pins** (no live defect): the tree ships no collision, the CHANGELOG passage is
true today, and the harness registry is complete today — but nothing would have
caught a change that made any of the three false.

---

## 0. The named gap (read first)

**The re-audit's own report file is NOT on disk.** The brief cites
`desks/final-reaudit/`; that directory does not exist in the tree (the central
lane table `desks/journal.md` lists the `final-reaudit` lane as *running* with no
session id and no desk directory). The same gap was already filed by the
`reaudit-fixes` desk (`desks/reaudit-fixes/journal.md`, "the re-audit's report
file is not on disk" — a hands-up signal). This lane therefore worked **from the
brief alone**: the three findings, their mechanism and their fix were re-derived
from the live tree and verified against it before anything was written. Every
claim below is proven against the tree, not against the missing report.

---

## 1. F-1 (MEDIUM) — the canonicalisation seam had no collision guard

### The hazard

The panel **dedupes on the canonical key** (`practice_ui.lua`'s
`scenario_action_order` pushes the canonical key and skips a key it has already
pushed) and the **icon lookup takes the first matching slot**
(`scenario_action_spell_id` walks the guide slots and returns the first slot
whose key canonicalises to the wanted key). So two keys of **different spells**
that canonicalise onto one key cost the player three things at once: one button
silently vanishes, the survivor carries the *other* spell's icon, and a press of
the dropped ability grades as the other spell.

No such case exists in the shipped tree (the paladin's `sob` is ONE key whose
label names both the Blood and the Martyrdom seal, and it never surfaces as two
buttons) — but nothing would have caught a future one.

### The pin (`tests/practice_ui_state.lua` §29f, +34 checks)

Per class, on the class's **own published panel vocabulary**, on the families the
grader-seam block above already walks (the paladin on TBC, WotLK and Forever; the
warrior on Forever; the druid, the rogue, the shaman and the hunter on Era):

* **the vocabulary** = the class's own **guide slots** (the key and the slot's
  spell id — the icon id, which the class keeps rank-invariant) + the class's
  **rotation rows** for the running family (the key and the row's **label** —
  the spell's name, and the label the button carries) + the **common abilities**
  the class publishes for that family (the key, the label and the published id
  ladder's head). The common abilities are taken with the per-ability family
  gate only — the offer gate's other two clauses are deliberately **not**
  applied, because a canonicalisation merge is exactly what would make the offer
  gate hide a common ability, and the pin has to see the collision the merge
  would cause.
* **every key is canonicalised** through the class's own normaliser
  (`ST.<CLASS>.practice_canonical_key` — the same seam the panel reads) and
  grouped by the canonical key.
* **the rule**: two *different* keys that canonicalise onto the same key must
  denote the *same* spell. The evidence is checked per id space (the guide
  slots' icon ids among themselves; the common abilities' ladder heads among
  themselves) and across the name publishers (the rotation rows' labels and the
  common abilities' labels must agree).
* **the normaliser's shape is pinned too**, so the pin is not vacuous on either
  side: the five classes whose key space is one publish an **identity** normaliser
  (every vocabulary key canonicalises to itself) and the paladin — the only
  class with an alias table — publishes one that **really merges** (at least one
  vocabulary key canonicalises onto a different key).

**Why not a class-side accessor:** none was needed. The vocabulary is assembled
in the test from what the classes already publish (`guide.slots`,
`practice_rotation_for()`, `practice_common_actions`), so
`classes/paladin.lua` was **not touched** (and the file stays well under its
185/190 local budget).

### The mutation proofs (`/tmp/opencode/mutproof`, the repo tree was never mutated)

| mutant | killed by | failing checks |
|---|---|---|
| **M1** the paladin's alias table merges two different SPELLS (`exorcism = "cons"`) | the new pin ("the guide slots' spell ids agree (they differ: 26573, 879)") + the grader-seam icon pin | 6 |
| **M2** a common ability merges onto a rotation key (`holy_light = "cons"`) | the new pin ("the names agree (they differ: Consecration, Holy Light)") + the grader-seam press pins | 10 |
| **M3** a single-key-space class grows an alias table (the shaman: `weave = "twist"`) | the new pin (the guide ids differ: 403, 8512) + "the SHAMAN normaliser is the identity" | 6 |
| **M4** two common abilities merge (`flash_of_light = "holy_light"`) | **the new pin ALONE** — all 6 failing checks are from the new block | 6 |

**M4 is the proof the pin has its own value**: the grader-seam pins above it
(one button per spell, the canonical button carries the icon, the press grades
correct, the drill-list pick) all stay green on that mutant, because two common
abilities of different spells never reach the panel's button row.

---

## 2. F-2 (LOW) — the CHANGELOG's "per-class sets" passage had no mechanical pin

The passage tells the reader which neutral action keys each class publishes per
family. It is true today (verified key-for-key against all six publish tables),
and it **had to be repaired once already** (`bench/stale_claims_2026-10-20.md`
§4 item 4) — but no suite read `CHANGELOG.md`, so the next edit to the passage
**or** to a class's publish could make it false with a green harness.

### The pin (`tests/toc_check.lua`, the "per-class sets" block, +203 checks)

The check reads **both** sides and compares them:

* the **passage**: the `- **The per-class sets.**` bullet of `CHANGELOG.md`, cut
  at the end of the sentence that names the last class (the rest of the bullet is
  the mechanism, not a per-class claim);
* the **tree**: each class's `ST.<CLASS>.practice_neutral_actions` table, parsed
  out of the class source (the family buckets and their keys, or the flat set).

The parsing:

* a **key** is a backticked token that is shaped like an action key (the bench
  paths and `ST.<CLASS>.practice_common_actions` are not);
* a key belongs to the **class named before it** — the bold class name or the
  possessive ("the hunter's without `raptor`"), which is why the hunter's and
  the druid's keys (one sentence, interleaved) land on the right class;
* a key's **family claim** is the list after it ("`battle_shout` on WotLK"); a
  qualifier at the end of a list covers the whole list ("the common abilities
  `holy_light`, ..., `food` on Era, TBC, WotLK and Forever");
* a **"WITHOUT `key` on <families>"** clause is a negative claim, and a
  **"the same N keys"** clause resolves to the list before it minus the key it
  excludes (and the count is checked: "ten" is ten).

The checks, per class:

1. the keys the passage names are the keys the class publishes (the union over
   the published families) — or, for the two classes whose passage states only
   the key the tree drops (the hunter's `raptor`, the druid's `rake`), exactly
   that dropped key;
2. every family the passage attaches to a key **publishes** that key, and every
   family it excludes it from does **not**;
3. the "every family" keys are published on every published family;
4. a flat publish is stated as flat, a family-scoped publish as family-scoped;
5. the "no bucket for Cata, Mists or Retail" claim: the four classes the passage
   names publish no bucket for those families, and the paladin and the shaman
   still answer every family.

### The mutation proofs

| mutant | killed by | failing checks |
|---|---|---|
| **M5** the passage drops a key from the paladin's list (`hpot` out) | "the passage names the class's published keys" + the "the same ten keys" count | 2 |
| **M6** the tree publishes a new key (the paladin's `ERA` bucket gains `newkey`) | "the passage names the class's published keys" | 1 |
| **M7** the tree's 4.0+ bucket gains `sotc` (the passage says WITHOUT) | "the passage excludes 'sotc' on CATA" | 1 |
| **M8** the passage excludes the wrong key (`aw` instead of `sotc`) | the "the same ten keys" clause + the exclusion claim (6 checks) | 6 |
| **M9** the passage attaches a key to the wrong family (`battle_shout` on Era) | "the passage publishes 'battle_shout' on ERA" | 1 |
| **M10** the tree gives the warrior a Cata bucket (an existing key, so the key set does not move) | "the passage says it publishes no bucket for CATA, MISTS, RETAIL" + the "every family" claim | 5 |

**M10 is why checks 4 and 5 are there**: without them, a bucket that only
reuses an existing key would pass the key-set comparison.

---

## 3. F-3 (LOW) — the registry guard was self-referential

`tests/toc_check.lua` carries the "every suite on disk is registered in
`tests/run.sh`" guard. Deleting **that one registry line** in `tests/run.sh`
disabled the whole guarantee while the harness still printed green — **42 steps,
0 failed**. The re-audit named the step count as unpinned too.

### The fix (`tests/neutral_actions_state.lua`, the counter-guard block, +3 checks)

A **different** suite now carries the counter-guard:

* `tests/run.sh` must register **the suite that carries the guard**
  (`tests/toc_check.lua`) — exactly once;
* the **step-count floor**: the registry must hold at least **41** registered
  suites. A floor, not an equality: a legitimate suite **addition** raises the
  count and passes, a deleted registry line lowers it and fails. A legitimate
  **removal** lowers the floor in the same change that removes the suite. The
  harness prints two more steps than that (the `luac5.1 -p` syntax step and the
  `luacheck` step), so the floor is 41 = the 43 steps minus those two.

**The two guards are mutual, so neither can be switched off alone:**

* delete *this* suite's registry line → `toc_check`'s guard fails (the suite is
  on disk and unregistered);
* delete `toc_check`'s registry line → the counter-guard fails.

### The mutation proofs

| mutant | killed by | the full harness on the mutant |
|---|---|---|
| **M11** `tests/run.sh` loses the `tests/toc_check.lua` line | the counter-guard (2 checks: the guard registration + the floor) | **42 steps, 2 failed** (was 42 steps, 0 failed) |
| **M12** `tests/run.sh` loses the `tests/neutral_actions_state.lua` line | `toc_check`'s own guard ("unregistered: tests/neutral_actions_state.lua" + the count) | **42 steps, 2 failed** |

**No registry line was added and `tests/run.sh` was NOT touched** — the
counter-guard lives in a suite that is already registered. The orchestrator owns
`run.sh`; nothing was needed from it.

---

## 4. The verification

* **Harness:** `bash tests/run.sh` → **43 steps, 0 failed**.
* **luacheck:** **2 warnings / 0 errors in 85 files** — the standing floor
  (`compat.lua:36`, `main.lua:81`), both pre-existing. The three touched test
  files are **0/0** on their own.
* **Suites:** `tests/practice_ui_state.lua` 2459 → **2493** checks (§29f, +34),
  `tests/toc_check.lua` 924 → **1074** checks (the per-class sets block, +150),
  `tests/neutral_actions_state.lua` 7023 → **7026** checks (the counter-guard,
  +3). (The baselines were measured by removing the new blocks on a disposable
  copy — the numbers in the earlier bench notes are older, other lanes have
  added checks to `toc_check.lua` since.)
* **Mutation proofs:** **12 mutants, 12 kills, 0 escapes**; the control copy is
  green in all three suites (`practice_ui_state.lua` 2493/0, `toc_check.lua`
  1074/0, `neutral_actions_state.lua` 7026/0). The script is
  `/tmp/opencode/mutation_proofs.sh` (disposable; the copies are under
  `/tmp/opencode/mutproof`).
* **Line endings:** the three test files are **LF** (0 CR bytes) and their EOF
  bytes are unchanged; `classes/paladin.lua` was **not touched** (still CRLF,
  185/190 local budget untouched).
* **No git, no TOC, no version, no README/CHANGELOG/docs, no lint config, no
  other addon file.** `tests/run.sh` was not touched either.

### The cross-fire this lane saw (not its own)

While the proofs ran, **another lane** was editing `classes/rogue.lua` (the
central HU-7 fix — the per-class namespace mirror `st.ROGUE = ST.ROGUE` came
out) and `tests/rogue_state.lua` / `tests/wiring_check.lua` with it. The harness
was briefly red on `tests/rogue_state.lua` ("the class table is mirrored onto
the addon namespace (HU-7)") — a file this lane never touched, and the rogue
suite reads none of the three files this lane changed. That lane finished at
19:57 and the harness went green again (**43 steps, 0 failed**, luacheck back to
2/0). The mutation proofs were re-run on the settled tree: 12 kills, 0 escapes,
the control green.

---

## 5. What the pins do NOT cover (the honest limits)

1. **F-1, guide slot against rotation row.** The two live in different id
   spaces (the guide's rank-invariant icon id against the APL's cited rank), so
   they are not compared — a same-spell pair would read as two ids. The pair is
   covered by the *label* only when the rotation publishes one. A guide slot and
   a rotation row of DIFFERENT spells that canonicalise together is therefore
   **not** caught by the id rule; the label rule catches it when both publish a
   name (the rotation always does, the guide slot never does). The class's own
   offer gate is what keeps a common ability out of that collision, and the
   neutral set's disjointness from the rotation is already pinned elsewhere
   (`tests/neutral_actions_state.lua`'s grading-integrity pin).
2. **F-1, the common abilities' ladder head** is the ladder's first id (the
   rank-1 id), not the client's own rank — the pin is about the published
   vocabulary, not the client's spell data.
3. **F-2, the passage's per-family key enumeration** is only checked where the
   passage states it per key. The paladin's "the same ten keys … on Cata, Mists
   and Retail" is resolved and checked (the count, the ten keys, the three
   families); the hunter's and the druid's per-family splits are checked through
   the tree's per-family difference set and the negative claim, not through a
   per-key enumeration (the passage does not state one).
4. **F-3, the floor is a ratchet.** A legitimate suite *removal* must lower the
   floor in the same change; a legitimate *addition* needs nothing.
5. Nothing here is proven **in-client** — every pin is offline. The re-audit's
   three findings were test-pin findings, and the pins are the fix.
