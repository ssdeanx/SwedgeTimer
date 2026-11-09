# The stale-claim guard, extended to all six classes (2026-10-20)

**Desk:** `stale-claims` (resumed) · **Scope:** the comment lines of
`classes/hunter.lua`, `classes/druid.lua`, `classes/rogue.lua`, `practice_ui.lua`
· **Status:** landed, harness green.

The source: `bench/stale_claims_2026-10-20.md` §4 "Filed for the orchestrator"
(items 1-3) — the five remaining sites of the false claim and the missing
stale-phrase pins for three of the six classes.

---

## 1. The five sites that still carried the false claim

The claim was **false**: the resolver's fallback hands the ERA corpus's rank-1
id, and the classic-line **name** leg is UNCONFIRMED in-client
(`bench/final_gate_audit_2026-10-20.md` §6 C1). Every site now states what the
code does, in the same house form the paladin, the warrior and the shaman
already carry.

| file | site (before) | now |
|---|---|---|
| `classes/hunter.lua` | 4966-4968 (the false phrase on 4967) | the id table is the citation and the fallback (the client's own rank only where that id still exists on it) + the NAME-first leg is conditional on the client ANSWERING the name + the classic-line name leg is UNCONFIRMED in-client |
| `classes/druid.lua` | 4232-4234 (the false phrase on 4233) | same |
| `classes/rogue.lua` | 2996-2997 (the false phrase on 2997) | same |
| `practice_ui.lua` | 419-423 (the shaman drill icon) | the drill's name-art rule — a client that answers the name shows its own rank art, whether the classic-line global takes a name at all is UNCONFIRMED in-client, an unanswered name leaves the icon blank |
| `practice_ui.lua` | 508-512 (the rogue drill icon) | same, spelled out in full (it no longer leans on "the shaman drill's name-art rule") |

**What the code actually does** (read before the wording was written — the
same derivation the previous lane filed, re-read here so this desk does not
re-derive it):

* the name leg — `pcall(api.GetSpellInfo, name)` (`classes/hunter.lua:5258`,
  `classes/druid.lua:4557`, `classes/rogue.lua:3233` — the three copies of the
  same function); the id the client answers **with that name** is its own rank
  id. **UNCONFIRMED in-client** for the classic line (audit §6 C1);
* a client that answers the name **without** a numeric id falls to
  `action.ids[1]` — the ERA corpus's **rank-1** id (`classes/hunter.lua:5266`,
  `classes/druid.lua:4565`, `classes/rogue.lua:3241`);
* outside it, the cited id ladder is walked by `api.get_family_spell_id_state`
  (`compat.lua:1555-1591` — it takes the **highest** id the client actually
  has; called at `classes/hunter.lua:5279`, `classes/druid.lua:4578`,
  `classes/rogue.lua:3254`), which gives the client's own rank **where the
  ladder carries it**, and `nil` where it does not (the Healthstone: the single
  cited id 5720 answers "Not Found" on the Cata and the Mists clients, whose
  own rank is 6262 — the ladder is deliberately not extended with it,
  `bench/class_neutral_family_coverage_2026-10-20.md` §1.2), and the ability is
  then **dropped** (unknown-hides), not shown with a wrong art;
* the query is family-correct: the **name** on TBC, the numeric id on every
  other family (the operator's name-vs-id rule, `bench/lessons.md`;
  `hands-up.md` HU-6 resolved as KEEP-BOTH-READINGS).

**The `practice_ui.lua` sites are the drill-icon path, not the common-ability
resolver.** `shaman_cast_def` resolves the texture with
`api.GetSpellInfo(<English name>)` — the label the class's own drill table
carries (`ST.SHAMAN.PRACTICE_CASTS` → "Lightning Bolt" / "Chain Lightning",
`classes/shaman.lua:4057-4060`); `rogue_cast_def` resolves it with
`api.GetSpellInfo(R.practice_cast_spell_id(key))`, and that accessor returns the
English **name** ("Eviscerate" / "Sinister Strike",
`classes/rogue.lua:2157-2163`) despite its name. So the same name leg applies,
and an unanswered name leaves the icon blank rather than guessed — that half of
the old sentences was true and is kept.

**The old wording was wrong about more than the name leg:** it said "Era, TBC
and Forever **each answer their own rank art**". Only the TBC client's
name-answering is operator-confirmed (`bench/lessons.md`: "TBC Anniversary API
takes spell NAMES, not ids; Classic Era needs ids", operator-confirmed
2026-10-19); the classic-line name leg is UNCONFIRMED in-client (audit §6 C1).
The new wording drops the family enumeration instead of restating it as a fact.

---

## 2. The guard, extended to all six classes

The stale-phrase source-shape pins existed only for the **paladin, warrior and
shaman** (`tests/paladin_state.lua:3599`, `tests/warrior_state.lua:5658`,
`tests/shaman_state.lua:3704`). Nothing would have caught a reintroduction in
the three files the previous lane corrected. Each file now has **its own** pin
in **its own** suite, in the same shape:

| suite | pin block | file it reads |
|---|---|---|
| `tests/hunter_state.lua:5154-5186` | the stale-claim guard | `classes/hunter.lua` |
| `tests/druid_state.lua:3990-4022` | the stale-claim guard | `classes/druid.lua` |
| `tests/rogue_state.lua:3821-3853` | the stale-claim guard | `classes/rogue.lua` |
| `tests/practice_ui_state.lua:6159-6197` | the stale-claim guard | `practice_ui.lua` |

**The four checks per class file** (the house form plus the file-local claim):

* the stale phrase **"every client family answers its own rank art"** is ABSENT;
* the stale phrase **"the NAME-first resolution finds the client's own rank"**
  is ABSENT (the file-local form of the same false claim);
* the house marker **"answers its own rank id"** is PRESENT (the resolver note
  says what the code does);
* the corrected statement **"the NAME-first leg finds the client's own rank
  only where the client ANSWERS the name"** is PRESENT (the `FOR THE RECORD`
  note states the name leg as conditional and UNCONFIRMED).

**The four checks for `practice_ui.lua`:**

* both stale phrases ("every client family answers its own rank art" and "each
  answer their own rank art") are ABSENT;
* **both** drill-icon notes carry the corrected name-art statement — the check
  is a **count** (>= 2), not a presence, so a note that drops back to the old
  wording loses its own copy and the count falls to 1;
* **both** drill-icon notes mark the name leg UNCONFIRMED in-client (count
  >= 2).

**THE MATCH IS ON PROSE, NOT ON SOURCE LINES.** The claim is wrapped across
three source lines in each class file, so a flat substring search would not see
it. Each pin flattens the file first — the line-leading comment marker dropped,
the lines joined with one space, the whitespace collapsed — and matches the
sentence whole. (The three existing paladin/warrior/shaman pins match a phrase
that happens to sit on one line, and are **unchanged** — they read files this
lane did not touch.)

**`practice_ui.lua` is at the 199-local ceiling** and stays there: the pins
live in the test suites, and the source change is comment-only (the compiler's
own count is still 199, `luac5.1 -l -l`).

---

## 3. The verification

* **Harness:** **43 steps, 0 failed** (`bash tests/run.sh`).
* **luacheck:** **2 warnings / 0 errors in 85 files** — the standing floor
  (`compat.lua:36`, `main.lua:81`), both pre-existing and KEEP-ruled. No new
  warning from the four new pin blocks.
* **Mutation proofs** (on `/tmp/opencode/stale_claims_guard_mut`, a copy of the
  tree minus `Media/`, `docs/`, `.git`, `desks/`; the repo tree was never
  mutated): each stale wording was restored and the owning suite re-run.

  | mutant | killed by | exit |
  |---|---|---|
  | M1 the stale phrase is back in `classes/hunter.lua` | `hunter_state.lua`: 2 of 1708 checks failed | 1 |
  | M2 the stale phrase is back in `classes/druid.lua` | `druid_state.lua`: 2 of 1578 checks failed | 1 |
  | M3 the stale phrase is back in `classes/rogue.lua` | `rogue_state.lua`: 2 of 1099 checks failed | 1 |
  | M4 the stale phrase is back in the shaman drill note (`practice_ui.lua`) | `practice_ui_state.lua`: 3 of 2459 checks failed | 1 |
  | M5 the rogue drill note is back to the old wording (`practice_ui.lua`) | `practice_ui_state.lua`: 2 of 2459 checks failed | 1 |
  | M6 the **house** stale phrase is dropped into `classes/hunter.lua` | `hunter_state.lua`: 1 of 1708 checks failed | 1 |

  **6 kills, 0 escapes**; the control run on the unmutated copy was green
  (`hunter_state.lua` 1708/0, `druid_state.lua` 1578/0, `rogue_state.lua`
  1099/0, `practice_ui_state.lua` 2459/0).
* **No behaviour changed — proven mechanically, not asserted.** For each of the
  four source files, the pre-edit version (the stale wording put back) and the
  post-edit version were compiled and their `luac5.1 -l -l` listings compared:
  **byte-identical** once the source line numbers and the heap addresses (which
  a comment edit necessarily shifts) are normalised. The instruction counts and
  byte counts are identical for every function. Separately, every changed line
  in the four files was checked to be a comment (`--`).
* **Line endings:** CRLF kept in all four source files (5366 CRLF / 0 lone LF in
  `classes/hunter.lua`, 4643/0 in `classes/druid.lua`, 3699/0 in
  `classes/rogue.lua`, 8087/0 in `practice_ui.lua`); the four test files are LF
  and their EOF bytes are unchanged.
* **Suite counts:** +4 checks each (hunter 1704 → 1708, druid 1574 → 1578,
  rogue 1095 → 1099, practice_ui 2455 → 2459). No behaviour pin moved.
* **No git, no TOCs, no versions, no README/CHANGELOG/docs, no lint config, no
  other addon file.** The pins this lane added are **source-shape comment
  guards** — no behaviour pin was added, removed or re-worded.

---

## 4. Filed for the orchestrator (out of this lane's scope)

1. **ONE false claim is left in the tree — `classes/warrior.lua:4899`.** The
   same `FOR THE RECORD` note the hunter, the druid and the rogue carry still
   reads "so the ladder is NOT extended with it and the NAME-first resolution
   finds the client's own rank), the" (`classes/warrior.lua:4892-4902`). The
   previous lane corrected the warrior's `THE IDS` bullet and its resolver note
   but not this note — it is the same false claim, in a file this lane was
   explicitly forbidden to touch ("DO NOT touch `classes/paladin.lua`,
   `classes/warrior.lua`, `classes/shaman.lua`"). **It is the only remaining
   instance in the six classes:** the four classes that publish NO Cata/Mists
   bucket are the warrior, the rogue, the hunter and the druid — exactly the
   four that carry the note. The paladin and the shaman publish for every
   family, so they carry no such note.
   The fix is the same wording this lane landed in the other three files, and
   the natural pin is one more check in `tests/warrior_state.lua` (which already
   reads `classes/warrior.lua` for the house stale phrase).
2. **The CHANGELOG still has no mechanical pin** — no suite reads `CHANGELOG.md`
   (`grep -rl CHANGELOG tests/` → no hits), so a doc-truth regression there is
   invisible to the harness. Carried over unchanged from
   `bench/stale_claims_2026-10-20.md` §4 item 4.
3. **The in-client question is still open** (unchanged): whether the
   classic-line global `GetSpellInfo` takes a spell **name** at all (audit §6
   C1) and whether the icon a client paints for a name query is its own rank's
   art. Every rewording above keeps that leg marked UNCONFIRMED; none of them
   claims it. `hands-up.md` HU-6 (TBC name-vs-id) is resolved as
   KEEP-BOTH-READINGS and does not change anything here.
