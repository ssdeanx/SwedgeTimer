# The last stale claims of the final-gate fix wave (2026-10-20)

**Desk:** `stale-claims` · **Scope:** `CHANGELOG.md` (the "per-class sets" passage),
the comment lines of `classes/hunter.lua`, `classes/druid.lua`, `classes/rogue.lua` ·
**Status:** landed, harness green.

The source: `bench/final_gate_fixes_2026-10-20.md` §5 "Filed for the orchestrator"
(items 1 and 2), which the previous lane could not touch (the CHANGELOG and the three
class files were not its files). The truth those two items had to be rewritten against:
`bench/final_gate_audit_2026-10-20.md` §6 C1 (the classic-line **name** leg is
UNCONFIRMED in-client) and the family-scoped paladin publish that landed in
`classes/paladin.lua:4437-4535`.

---

## 1. The CHANGELOG passage (`CHANGELOG.md:780-799`)

**Before:** the paladin was described as publishing a **flat** set with `sotc`, and the
sentence closing the passage read "the flat paladin and the flat shaman still answer
every family".

**After:** the passage states what the tree does.

* the **paladin** is **family-scoped** — `sotc`, `aw`, `hpot`, `abacus`, `stop` plus
  the six common abilities on **Era, TBC, WotLK and Forever**, and **the same ten keys
  WITHOUT `sotc`** on **Cata, Mists and Retail** (the Seal of the Crusader went away
  in 4.0; a press of that key on the 4.0+ clients is a mis-pick — the rogue's Shiv
  treatment on the same clients);
* the four classes that publish **no bucket** for Cata/Mists/Retail are now **named**
  (the warrior, the rogue, the hunter and the druid) — the count (four) was already
  right, only the parenthetical was wrong;
* the closing parenthetical now says "the paladin and the shaman still answer every
  family: the paladin with its ten-key 4.0+ bucket, the shaman with its flat set" —
  the shaman's publish is **still flat** (`classes/shaman.lua:4609-4615`, verified).

**Verified against the tree, not copied:** the paladin's seven buckets
(`classes/paladin.lua:4437-4535`: ERA/TBC/WRATH/FOREVER carry `sotc`, CATA/MISTS/
RETAIL do not — ten keys each); the four bucketless classes
(`classes/warrior.lua:4841`, `classes/rogue.lua:2937`, `classes/hunter.lua:4909`,
`classes/druid.lua:4166` — ERA/TBC/WRATH/FOREVER only); the shaman's flat publish
(`classes/shaman.lua:4609`); the offer gate that keeps a common ability off a family
with no neutral bucket (`classes/hunter.lua:5299-5306` and the class's own peers).

Nothing else in the file was touched; the passage's following sentences (the
practice-panel ability list, the unknown-hides rule, the closed list) still hold.

---

## 2. The six "rank art" comment sites

The claim was **false**: the resolver's fallback hands the ERA corpus's rank-1 id, and
the classic-line name leg is UNCONFIRMED in-client (audit §6 C1). Every site now says
what the code does, in the wording the previous lane landed for the paladin, the
warrior and the shaman (so one house form covers the six classes):

| file | site (before the edit) | now |
|---|---|---|
| `classes/hunter.lua` | 5149-5152 (`THE IDS` bullet) | the name leg, its UNCONFIRMED status, and the id table as citation + fallback |
| `classes/hunter.lua` | 5224-5228 (resolver note) | "the English name first (a client that indexes it answers its own rank id …)" |
| `classes/druid.lua` | 4413-4416 (bullet) | same |
| `classes/druid.lua` | 4522-4526 (resolver note) | same |
| `classes/rogue.lua` | 2151-2154 (the drill icon rule) | "a client that answers the name shows its own rank art - whether the classic-line global GetSpellInfo takes a name at all is UNCONFIRMED in-client" |
| `classes/rogue.lua` | 3126-3129 (bullet) | the name leg, its UNCONFIRMED status, and the id table as citation + fallback |
| `classes/rogue.lua` | 3196-3200 (resolver note) | "the English name first (a client that indexes it answers its own rank id …)" |

**What the code actually does** (read before the wording was written, cited here so
the next desk does not re-derive it):

* the name leg — `pcall(api.GetSpellInfo, name)`; the id the client answers **with
  that name** is the client's own rank id (`classes/hunter.lua:5255`,
  `classes/druid.lua:4553`, `classes/rogue.lua:3229` — the three copies of
  the same function). **UNCONFIRMED in-client** for the classic line (audit §6 C1).
* inside that leg, a client that answers the name **without** a numeric id falls to
  `action.ids[1]` — the ERA corpus's **rank-1** id (`classes/hunter.lua:5263`,
  `classes/druid.lua:4561`, `classes/rogue.lua:3237`);
* outside it, the cited id ladder is walked by `api.get_family_spell_id_state`
  (`compat.lua:1555-1591`, called at `classes/hunter.lua:5275`,
  `classes/druid.lua:4573`, `classes/rogue.lua:3249`), which takes the **highest**
  cited id the running client actually has — so it is the client's own rank **where
  the ladder carries it**, and `nil` where it does not (the Healthstone: the single
  cited id 5720 answers "Not Found" on the Cata and the Mists clients, whose own
  rank is 6262 — the ladder is deliberately not extended with it,
  `bench/class_neutral_family_coverage_2026-10-20.md` §1.2), and the ability is then
  **dropped** (unknown-hides), not shown with a wrong art;
* the query is family-correct: the **name** on TBC, the numeric id on every other
  family (the operator's name-vs-id rule, `bench/lessons.md`).

The rogue's third site (2151) is the **drill icon** path, not the common-ability
resolver: `practice_ui.lua:529-534` resolves the texture with
`api.GetSpellInfo(<English name>)`, so the same name leg applies and an unanswered
name leaves the icon blank rather than guessed — that half of the old sentence was
true and is kept.

---

## 3. The verification

* **Harness:** **43 steps, 0 failed** (`bash tests/run.sh`).
* **luacheck:** **2 warnings / 0 errors in 85 files** — the standing floor
  (`compat.lua:36`, `main.lua:81`), both pre-existing and KEEP-ruled.
* **The three stale-phrase pins still fail on the old wording.** The pins
  (`tests/paladin_state.lua:3599`, `tests/warrior_state.lua:5658`,
  `tests/shaman_state.lua:3704`) are **source-shape pins on the ABSENCE** of the
  phrase "every client family answers its own rank art", plus a presence pin on the
  corrected statement ("answers its own rank id"). They read `classes/paladin.lua`,
  `classes/warrior.lua` and `classes/shaman.lua` — **none of which this lane
  touched** — so they needed **no re-wording** and are unchanged.
* **Mutation proofs** (on `/tmp/opencode/stale_claims_mut`, a copy of the tree minus
  `Media/`, `docs/`, `.git`, `desks/`, `bench/`; the repo tree was never mutated):
  the old wording was restored in each of the three class files and the suites were
  re-run:

  | mutant | killed by | exit |
  |---|---|---|
  | M1 the stale phrase is back in `classes/paladin.lua` | `paladin_state.lua`: 2 of 1234 checks failed | 1 |
  | M2 the stale phrase is back in `classes/warrior.lua` | `warrior_state.lua`: 2 of 2046 checks failed | 1 |
  | M3 the stale phrase is back in `classes/shaman.lua` | `shaman_state.lua`: 2 of 1064 checks failed | 1 |

  **3 kills, 0 escapes**, and the control run on the unmutated copy was green
  (`paladin_state.lua` 1234/0, `warrior_state.lua` 2046/0, `shaman_state.lua` 1064/0).
* **No behaviour changed.** Every edited line in the three class files is a comment
  (`--`), verified mechanically; no id, no table, no resolution branch was touched.
  The three class suites' counts are unchanged (1234 / 2046 / 1064).
* **Line endings:** CRLF kept in `CHANGELOG.md` (993 CRLF, 0 lone LF),
  `classes/hunter.lua` (5363/0), `classes/druid.lua` (4639/0), `classes/rogue.lua`
  (3695/0). The shaman (LF) was not touched.
* **No git, no TOCs, no versions, no README/TESTING/docs, no lint config, no other
  addon file, no pin added or removed.**

---

## 4. Filed for the orchestrator (out of this lane's scope)

The same false claim survives in five more places. None was in this lane's scope, so
none was edited — they are filed here with the exact line.

1. **`classes/hunter.lua:4967`**, **`classes/druid.lua:4233-4234`** and
   **`classes/rogue.lua:2997`** — the "FOR THE RECORD" notes inside the three neutral
   publishes still say "the NAME-first resolution finds the client's own rank". That
   is the same **UNCONFIRMED** name leg (audit §6 C1); it should read as a
   consequence of the name leg answering, not as a fact.
2. **`practice_ui.lua:419-423`** (the shaman drill icon) still says "so Era, TBC and
   Forever each answer their own rank art", and **`practice_ui.lua:508-512`** (the
   rogue drill icon) leans on "the shaman drill's name-art rule" — the same claim.
   `practice_ui.lua` is out of this lane's scope (and it sits at the 200-local
   ceiling, baseline 199).
3. **Coverage gap:** the stale-phrase source-shape pins exist only in the **paladin,
   warrior and shaman** suites. **Nothing** would catch a reintroduction of the false
   claim in `classes/hunter.lua`, `classes/druid.lua` or `classes/rogue.lua` — the
   three files this lane corrected. The natural fix is one pin per file, in the
   file's own suite (`tests/hunter_state.lua`, `tests/druid_state.lua`,
   `tests/rogue_state.lua`), in the same shape as the three existing ones
   (absence of the old phrase + presence of "answers its own rank id").
4. **The CHANGELOG has no mechanical pin** — no suite reads `CHANGELOG.md`
   (`grep -rl CHANGELOG tests/` → no hits), so a doc-truth regression there is
   invisible to the harness. Noted, not fixed.
5. `bench/final_gate_fixes_2026-10-20.md` §5 items 1 and 2 are **closed by this
   lane**; the file was not edited (the bench is never overwritten) — the pointer
   lives here.

---

## 5. UNCONFIRMED / not proven here

* **In-client:** whether the classic-line global `GetSpellInfo` takes a spell **name**
  at all (audit §6 C1) — the operator's in-client pass still owes it. Every rewording
  above keeps that leg marked UNCONFIRMED; none of them claims it.
* **The ERA rank-1 id as the client's own art:** the fallback's id is the ERA
  corpus's rank-1 id, and it is the client's own rank only where that id still
  exists on it (the Healthstone on Cata/Mists: "Not Found"). Whether the icon a
  client paints for a name query is its own rank's art is an in-client question, not
  an offline one.
* **The CHANGELOG's four-bucketless-classes count** was verified against the four
  publish tables in the tree (cited above); the *offer-gate* consequence (no common
  ability offered on Cata/Mists/Retail for those four) is **offline-proven only** —
  the in-client panel is the operator's check.
