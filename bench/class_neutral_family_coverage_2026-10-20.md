# The NEUTRAL offer list — per-family coverage (2026-10-20)

**Desk:** `class-neutral-family-coverage` · **Scope:** `classes/paladin.lua`,
`classes/warrior.lua`, `classes/hunter.lua`, `classes/rogue.lua`,
`classes/druid.lua`, `classes/shaman.lua` (the offer-list / neutral-bucket logic
ONLY) + `tests/neutral_actions_state.lua` (the per-family offer pins) ·
**Status:** landed, harness green.

The specs this lane worked from: the orchestrator's ruling (below) and the two
filed bench artifacts - `bench/class_neutral_hunter_druid_2026-10-20.md` (§6 "The
Cata and Mists clients carry no bucket") and
`bench/class_common_actions_2026-10-20.md` (§2 the mechanism, §3 the three rules).
The engine half is the sibling lane's (`bench/practice_neutral_actions_2026-10-20.md`:
the accessor `H.practice_neutral_actions`, the `neutral` outcome, the UI wording).
**The engine was NOT touched** - the rule is implemented in the class modules.

## 0. The rule (the orchestrator's ruling)

> **an ability may only be OFFERED on a family where it is either a rotation
> action or a neutral action.** Offering an action that can only ever be a
> mis-pick is a trap - the player is invited to press something the grader will
> always punish. So the panel's offer list and the neutral set must be
> **consistent per family**: an ability with no neutral bucket on that family is
> not offered there (it stays available on the families where it is neutral).

Implemented as **one mechanism in all six class modules** - the class's own
**offer gate**, which the panel's common-ability offer list reads:

```lua
-- classes/<class>.lua
ST.<CLASS>.practice_neutral_set()          -- the published set for the RUNNING family
ST.<CLASS>.practice_rotation_action_set()  -- the running family's rotation actions
ST.<CLASS>.practice_canonical_key(key)     -- the class's own alias table (identity for 5)
ST.<CLASS>.practice_common_offer_allowed(action, neutral, rotation)
```

The gate's three clauses (all in `practice_common_offer_allowed`):

1. the class's own per-ability family gate (the entry's `families` field) names
   the running family;
2. **the running family's published neutral set carries the key** - a family the
   class published no bucket for offers nothing;
3. the running family's rotation does not rank the key (a rotation action is
   graded by the rotation, never an offered common ability).

`practice_neutral_set()` is the engine's own resolution rule, re-implemented in
the class (a FLAT publish answers itself, a family-scoped publish answers the
bucket for `st.family`, a family with no bucket answers nil) - the class never
asks the engine, and the offer list and the neutral set can never disagree
because **the publish is the single source of truth**.

## 1. What landed

### 1.1 The mechanism (all six classes)

* `practice_neutral_set()` - the published set for the running family (nil when
  the class published no bucket for it).
* `practice_rotation_action_set()` - the running family's rotation actions, read
  the way the panel reads them (the argument-free `practice_rotation_for()`
  call - `practice_ui.lua`'s `scenario_action_order`).
* `practice_canonical_key()` - the class's own alias table (the paladin has one;
  the other five use a single key space, so it is the identity).
* `practice_common_offer_allowed()` - the gate (the three clauses above).
* `practice_panel_slots()` now offers a common ability only through the gate.
  The classes that carried an inline `families` check (the warrior, the hunter,
  the rogue, the druid) read the gate instead; the paladin and the shaman had no
  such check and gain one.

**No behaviour change on the families that were already covered:** the published
sets and the per-ability gates already agreed, so the gate is a no-op there.
The one behaviour change is the Cata / Mists clients (§2).

### 1.2 The Cata and Mists clients - the per-class answer

| class | the Cata (40402) and the Mists (50500) clients | why |
|---|---|---|
| PALADIN | **covered** - the publish is FLAT, so it answers every family; the six common abilities are offered there and they are neutral there | the paladin's publish is the class's own flat statement ("these are neutral on every client the addon runs on"), and the rotation order names no row for those two clients - so none of the six is rotation-ranked there. Every one of them is present on both clients (cited below). |
| SHAMAN | **covered** - the same flat publish | the same: the rotation table carries no CATA / MISTS row, so none of the five is rotation-ranked there, and every one of them is present on both clients (cited below). |
| WARRIOR | **excluded** - no bucket, so the offer gate offers NO common ability there | the class publishes **no rotation** for either client (the rotation table carries no CATA / MISTS row and `ST.WARRIOR.utility_family` answers nil for both), and its guide vocabulary there is its own ERA-base set (neither client has a warrior slot set of its own). A bucket is the class's statement about a client it **plays**; the class plays neither. |
| HUNTER | **excluded** - the same | the class publishes **no rotation** for either client (`ST.HUNTER.PRACTICE_ROTATIONS` carries no CATA / MISTS table), and its guide vocabulary there is its own slot set - the Mists set even drops the Raptor Strike (the Mists client's own spell data carries no Raptor Strike id this tree knows, so `SPELL_ID_BY_FAMILY.raptor.MISTS` is deliberately empty). |
| ROGUE | **excluded** - the same | the class publishes **no rotation** for either client, and its guide vocabulary there is its own **flat** set - which is not the clients' own (the 4.0 client dropped the Shiv). |
| DRUID | **excluded** - the same | the class publishes **no rotation** for either client (the cat and the bear chains are cut per family and name ERA / SOD / TBC / WRATH / FOREVER), and its guide vocabulary there is its own **flat** cat and bear set - the 4.0 client reworked that chain. |

**The exclusion is a statement, not a gap.** The Cata and the Mists clients DO
carry every one of these abilities - the clients' own spell pages say so (the
`/data/spell/<id>` page on the warcraftdb site, on the Cataclysm and the MoP
expansion domains, whose title carries the client's own spell name):

| ability | the Era id the class publishes | the Cataclysm / the MoP page |
|---|---|---|
| Sprint | 2983 | "Sprint - Cataclysm" / "Sprint - MoP" |
| Demoralizing Shout | 1160 | "Demoralizing Shout - Cataclysm" / "- MoP" |
| Healthstone | 5720 | the clients' own rank is **6262** ("Healthstone - Cataclysm" / "- MoP"); the Era id 5720 answers "Not Found" there, and 6262 is a DIFFERENT spell on the classic clients ("Minor Healthstone") - so the ladder is **not** extended with it and the NAME-first resolution finds the client's own rank |
| Diamond Flask | 24427 | "Diamond Flask - Cataclysm" / "- MoP" |
| Food | 433 | "Food - Cataclysm" / "- MoP" |
| Concussive Shot | 5116 | "Concussive Shot - Cataclysm" / "- MoP" |
| Healing Potion | 439 | "Healing Potion - Cataclysm" / "- MoP" |
| Evasion | 5277 | "Evasion - Cataclysm" / "- MoP" |
| Kick | 1766 | "Kick - Cataclysm" / "- MoP" |
| Healing Touch | 5185 | "Healing Touch - Cataclysm" / "- MoP" |
| Rejuvenation | 774 | "Rejuvenation - Cataclysm" / "- MoP" |
| Regrowth | 8936 | "Regrowth - Cataclysm" / "- MoP" |
| Aspect of the Cheetah | 5118 | "Aspect of the Cheetah - Cataclysm" / "- MoP" |
| Healing Wave | 331 | "Healing Wave - Cataclysm" / "- MoP" |
| Chain Heal | 1064 | "Chain Heal - Cataclysm" / "- MoP" |
| Water Shield | 52127 | "Water Shield - Cataclysm" / "- MoP" |
| Holy Light | 19968 … 19982 | the Era ladder answers "Not Found" on both expansion pages; the spell is the Holy spec's heal there and the NAME-first resolution finds the client's own rank (the in-client id is owed - the operator's pass) |
| Flash of Light | 19750 | "Flash of Light - Cataclysm" / "- MoP" |
| Lay on Hands | 633 | "Lay on Hands - Cataclysm" / "- MoP" |
| Divine Shield | 642 | "Divine Shield - Cataclysm" / "- MoP" |
| Blessing of Protection | 1022 | the client RENAMED the spell in 3.0: the Classic and the TBC pages title 1022 "Blessing of Protection", the WotLK / Cataclysm / MoP pages title the same id **"Hand of Protection"** - so the paladin's entry now carries both names (the shaman's renamed Water Shield rule) |
| Food | 433 | "Food - Cataclysm" / "- MoP" |

So the four excluded classes are excluding by RULE ("a bucket is a statement
about a client the class plays"), not by a belief that the client lacks the
spells. A future lane that gives a class a Cata / Mists rotation can publish the
bucket with these cited ids and the offer gate will pick it up with no further
change.

### 1.3 The one naming fix the family coverage needed

The paladin's `bop` entry carried the name "Blessing of Protection" only. The
WotLK, the Cataclysm and the MoP clients spell that spell "**Hand of
Protection**" (the same id, 1022 - the pages above), so the name path never
answered there and only the id ladder carried the ability. The entry now carries
both names, exactly like the shaman's renamed Water Shield ("Water Shield" /
"Mana Shield"). The change is inside the practice panel's resolver, so it is
not a default-visible change outside it.

## 2. The trap this lane closed (the observable difference)

On a Cata or a Mists client, before this lane, the panel **offered** the four
family-scoped classes' common abilities (the offer list was not family-gated)
while the class published **no neutral bucket** for those families - so a heal
or a potion press there was a press the grader could only punish. The offer
list and the neutral set now agree per family:

```
CATA   before: [op, execute, slam, hs, cleave, hamstring,
                sprint*, demoralizing_shout*, healthstone*, flask*, food*]
       after : [op, execute, slam, hs, cleave, hamstring]
```

(the `*` marks a common ability). The paladin and the shaman are unchanged
there - their flat publish already carried the abilities, so the offer and the
neutral set already agreed.

**What is still a mis-pick on those two clients** (and is out of this lane's
scope - the guide vocabulary, not the offer list): every key of the class's own
guide slot set is an intentional mis-pick there, because the class publishes no
rotation for those clients at all - the druid's flat cat and bear set, the
rogue's flat set (with the 4.0-removed Shiv), the hunter's Cata and Mists slot
sets, the warrior's ERA-base set, the paladin's twist set, the shaman's full
vocabulary (its own rule: a family it carries no row for leaves the class's
vocabulary standing). The cross-class suite now PINS that shape per family
(the mis-pick lists), so it is visible rather than implied. A lane that gives
the classes a Cata / Mists rotation is the one that can close it.

## 3. The pins (tests/neutral_actions_state.lua)

The suite grew the per-family coverage and the offer pins:

* **FAMILY_PROJECT** gained `CATA = 14` and `MISTS = 19` (the two client project
  ids `compat.lua` detects; the two TOCs that ship the addon).
* **Two slices per class** (CATA and MISTS), each with the family's neutral set
  and the closed mis-pick list. The slices read the panel's own call: a family
  the class does not describe is read the ARGUMENT-FREE way
  (`practice_ui.lua` calls `practice_rotation_for()` with no argument and the
  class picks the running client's slice).
* **The vocabulary stays faithful to the runtime**: the warrior's guide slots
  fall back to the running client's own set when the family has no per-family
  set, and the shaman's fall back to its full `GUIDE_SLOTS` when the family cut
  is empty (the class's own `apply_family_slots` rule).
* **THE OFFER PINS** (over the class's OWN offer list - the list
  `practice_panel_slots` hands to the panel):
  * *the offered common ability X is either a rotation action or a neutral
    action on this family* - the orchestrator's rule, and the mutant this suite
    must kill;
  * *the offered common ability X is one the class's own data offers on this
    family*;
  * *the panel offers the common ability X only where the rotation does not ask
    for it* (the landed pin, kept);
  * and the other direction: an ability the rule offers (published as neutral
    here, not rotation-ranked, and the client has the spell) **must reach the
    panel**.
* **THE DATA PIN**: where the class publishes a bucket for a family, every
  common ability the class's list names (and whose own family gate allows that
  family) must be in that bucket - unless the rotation ranks it there. A
  bucket that dropped such a key would leave the class's own data offering an
  ability the family does not publish: the trap, in the data.

## 4. The verification

* **Harness:** **43 steps, 0 failed** (`bash tests/run.sh`).
* **luacheck:** **2 warnings / 0 errors in 85 files** - the standing floor
  (`compat.lua:36`, `main.lua:81`), both pre-existing. The seven touched files
  are **0/0** on their own.
* **Line endings:** CRLF kept in `classes/paladin.lua`, `classes/warrior.lua`,
  `classes/hunter.lua`, `classes/rogue.lua`, `classes/druid.lua`; LF in
  `classes/shaman.lua` (the shaman's file was already LF) and in the test file.
* **Suites:** `tests/neutral_actions_state.lua` **6239 checks** (was 4313).
  The class suites are unchanged and green: `tests/warrior_state.lua` 2017,
  `tests/hunter_state.lua`, `tests/rogue_state.lua`, `tests/druid_state.lua`,
  `tests/shaman_state.lua`, `tests/paladin_state.lua`.
* **Mutation proofs** on `/tmp/opencode/mut_famcov` copies (a copy of the whole
  tree; the repo is never touched) - **10/10 killed** (every kill a pin failure,
  no crash) + **2 documented equivalent survivors**:

  | mutant | killed by |
  |---|---|
  | M1 the warrior's offer gate stops reading the published neutral set | the offer pin ("the offered common ability sprint is either a rotation action or a neutral action on this family") on the CATA slice |
  | M2 the hunter's offer gate stops reading the published neutral set | the same offer pin (the CATA slice) |
  | M3 the rogue's offer gate stops reading the published neutral set | the same offer pin (the CATA slice) |
  | M4 the druid's offer gate stops reading the published neutral set | the same offer pin (the CATA slice) |
  | M5 the warrior's WRATH bucket drops the Battle Shout | the published-set pin (the class's own data offers an ability the family does not publish) |
  | M6 the hunter's SoD build pick stops dropping the Raptor Strike | the published-set pin (a rotation action published as neutral) |
  | M7 the rogue's WRATH bucket gains the Expose | the published-set pin (a rotation action published as neutral) |
  | M8 the shaman's flat publish drops the Chain Heal | the published-set pin (the class's own data offers an ability the family does not publish) |
  | M9 the paladin's flat publish drops the Divine Shield | the published-set pin (the same) |
  | M10 the druid's publish gains a Cata bucket the class does not play | the published-set pin (a bucket for a family the class publishes no rotation for) |
  | M11 the paladin's offer gate stops reading the published neutral set | **SURVIVES - an equivalent mutant**: the paladin's publish is FLAT, so the set always carries the class's common abilities and the break changes nothing. The pin that carries that class is the data pin (M9) |
  | M12 the shaman's offer gate stops reading the published neutral set | **SURVIVES - an equivalent mutant**, for the same reason (a flat publish) |

  The headline requirement - "an unneutralizable ability is offered" must fail a
  pin - is M1-M4: the four family-scoped classes, on a family that publishes no
  bucket. ✓

## 5. Judgement calls (the orchestrator may rule otherwise)

1. **A bucket follows the rotation.** The four family-scoped classes publish a
   neutral bucket only for a family they publish a rotation for; a family they do
   not play gets no bucket, and the offer gate then offers no common ability
   there. The paladin and the shaman publish FLAT, so their own statement
   already answers the Cata and the Mists clients. The alternative - giving the
   four a CATA / MISTS bucket - is one edit each, and the ids are cited above;
   it was not done here because the class suites' own contract is "a bucket only
   for a family the class describes" (`tests/warrior_state.lua`: "only a client
   family publishes a bucket") and the class publishes no rotation for those
   two clients.
2. **The offer gate is stricter than the ruling's letter.** The ruling allows
   offering a rotation action ("either a rotation action or a neutral action");
   the gate refuses it (clause 3), because the common-ability list is the
   class's statement of the abilities the rotation **never** grades. The landed
   pin ("the panel offers the common ability X only where the rotation does not
   ask for it") says the same, so the gate implements the shipped contract.
3. **The gate keeps the per-ability family gate** (the entry's `families`
   field) as clause 1. Only the warrior's Battle Shout uses it today; the
   publish says the same thing (the WRATH bucket carries the key and no other
   family does), so the two agree - and the suite's data pin keeps them in step.
4. **The guide vocabulary on the Cata / Mists clients stays out of scope.** The
   rule this lane implements is about the OFFER list (the common abilities). The
   guide slots on those two clients are every key the class offers and the
   rotation grades none of them - a guide/rotation question, and the suites now
   pin that shape per family so it is visible.

## 6. UNCONFIRMED / not proven here

* **In-client:** the panel's action row on a Cata or a Mists client (the
  buttons that are gone and the ones that stay) and the NEUTRAL popup are
  **offline-proven only**. Nothing here is proven in a client; the operator's
  in-client pass is the only way to confirm the real client's spell data.
* **The in-client spell ids** on the Cata and the Mists clients are the
  expansion pages' own ranks for the abilities cited above; the class's own id
  ladders stay the Era 1.15 corpus's (the name-first resolution finds the
  client's own rank, and the id ladder is the locale fallback). The Holy Light
  id on those two clients is **not** in the tree (the Era ladder answers "Not
  Found" on both expansion pages) - it is owed.
* **The four excluded classes' Cata / Mists guide vocabularies** are not
  client-verified (the druid's cat chain, the rogue's Shiv, the hunter's Mists
  slot set, the warrior's base set). The lanes that own those vocabularies are
  the ones that can say what those clients carry.
* **The shaman's widening seam does not run on a family it carries no row
  for** (its own `apply_family_slots` returns before the widening), so on the
  Cata and the Mists clients the shaman's practice panel offers its guide
  vocabulary alone and the class's five common abilities do not reach it. They
  are neutral there (the flat publish), so there is no trap - but the runtime's
  panel is NARROWER than the class's own `practice_panel_slots` on those two
  clients. The suite's offer pins read the class's own offer list, so they are
  conservative (they check a superset of what the runtime offers). The seam is
  the shaman's own call, not this lane's.
* **The paladin's flat publish** carries `sotc` (the Seal of the Crusader), and
  the 4.0+ clients do not have that seal (the Cata and the MoP pages answer "Not
  Found" for 20308 and for the whole 21082 / 20162 / 20305-20308 ladder). The
  key is a twist-sim grid key (the sim's own ability list), not an OFFERED
  common ability, so the offer list is not affected - but the flat publish's
  claim about the Cata and the Mists clients is not exact. Fixing it means a
  family-scoped paladin publish, which is the paladin lane's call (its class
  suite pins the flat shape).
* **The classes publish no rotation for the Retail client either** (the same
  shape as the Cata and the Mists clients). The four family-scoped classes offer
  no common ability there either - the offer gate reads the publish, and there
  is no Retail bucket. The paladin and the shaman (flat) offer theirs.
