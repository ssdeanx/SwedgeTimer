# The hunter's and the druid's NEUTRAL sets and common abilities (2026-10-20)

**Desk:** `class-neutral-hunter-druid` · **Scope:** `classes/hunter.lua`,
`classes/druid.lua`, `tests/hunter_state.lua`, `tests/druid_state.lua`,
`tests/neutral_actions_state.lua` (the hunter/druid rows) · **Status:** landed,
harness green.

The specs this lane worked from: `bench/class_neutral_actions_2026-10-20.md`
(§3 the filed hunter/druid sets) and `bench/class_common_actions_2026-10-20.md`
(§5 the filed common abilities with their cited ids). The engine half is the
sibling lane's (`bench/practice_neutral_actions_2026-10-20.md`): the accessor
`H.practice_neutral_actions`, the `neutral` outcome and the UI wording. The
class half that filed the gap is the same two files above.

## 1. What landed

### HUNTER — a family-scoped publish, and the common abilities

```lua
ST.HUNTER.practice_neutral_actions = {
    ERA     = { raptor, concussive_shot, sprint, healthstone, healing_potion, food },
    TBC     = { raptor, concussive_shot, sprint, healthstone, healing_potion, food },
    WRATH   = {                 concussive_shot, sprint, healthstone, healing_potion, food },
    FOREVER = {                 concussive_shot, sprint, healthstone, healing_potion, food },
}
```

The common abilities (the panel's own list, `ST.HUNTER.practice_common_actions`):
`concussive_shot` (5116), `sprint` (2983), `healthstone` (5720),
`healing_potion` (439 / 440 / 441 / 2024 / 4042 / 17534), `food`
(433 / 2639 / 5004 / 10256 / 10257).

### DRUID — a family-scoped publish, and the common abilities

```lua
ST.DRUID.practice_neutral_actions = {
    ERA     = { rake, healing_touch, rejuvenation, regrowth, cheetah, healthstone,
                healing_potion, food },
    TBC     = { rake, healing_touch, rejuvenation, regrowth, cheetah, healthstone,
                healing_potion, food },
    WRATH   = {       healing_touch, rejuvenation, regrowth, cheetah, healthstone,
                healing_potion, food },
    FOREVER = {       healing_touch, rejuvenation, regrowth, cheetah, healthstone,
                healing_potion, food },
}
```

The common abilities: `healing_touch` (5185 … 25297 — the full ladder, §3),
`rejuvenation` (774 … 25299), `regrowth` (8936 … 9858), `cheetah` (5118),
`healthstone` (5720), `healing_potion` (439 … 17534), `food` (433 … 10257).

**Swiftmend is deliberately absent** (the filed spec's decision): the Era client
has no Swiftmend spell and the TBC/WotLK ids (47824 / 31216) are not in the Era
corpus - an id is never invented.

## 2. Where the landed sets differ from the filed ones - and why

The filed spec is the intent; three of its points could not be landed literally
without opening the grading hole the contract forbids ("a rotation action may
never be neutral"). Each deviation is recorded here with its reason.

### 2.1 The hunter's set is FAMILY-SCOPED, not flat

The filed §3 says *"HUNTER — flat: `{ raptor = true }`"*. Flat is not
implementable, for two independent reasons:

1. **The WotLK panel has no Raptor Strike key.** The closed list pins *"every
   neutral key is a key of the class's own panel"*: the WotLK guide slot set
   (`guide_slots_wrath`) carries no Raptor Strike, so a flat publish would
   publish a key the WotLK panel does not offer - an invented key.
2. **The Forever client asks for the Raptor Strike.** The Forever rotation's own
   row is `raptor_strike` (the APL's i=1), and the Forever guide set carries BOTH
   `raptor` and `raptor_strike` (the same spell, two keys). Publishing `raptor`
   as neutral there would make a **wrong Raptor Strike press free** - the same
   hole the contract forbids, spelled with a different key.

The landed publish therefore carries the Raptor Strike only where the rotation
never asks for that spell: the ERA bucket (the Era-base build) and the TBC bucket
(the TBC rotation has no Raptor Strike row and the TBC guide set carries only
the `raptor` slot).

### 2.2 The ERA bucket is BUILD-AWARE (both classes)

The SoD build runs on the Era client, so the engine's family-scoped publish (it
reads `st.family` only) cannot separate the two builds that share the ERA token.
On the SoD build the rotation DOES ask for the Raptor Strike (the SoD row
`raptor_strike`) and for the Rake (the SoD upkeep S7) - so the ERA bucket would
publish a rotation action as neutral there.

This is the same limit the four classes already landed hit (the shaman's
Lightning Shield, the warrior's Battle Shout - see
`bench/class_common_actions_2026-10-20.md` §6 judgement call 2). The tree
already answered it once inside a class module: the hunter's HUD dead-slot pick
is BUILD-AWARE, decided by the class's own Chimera-rune probe
(`bench/hunter_sod_build_2026-10-20.md`). This lane uses the same rule:

* **HUNTER** - the Raptor Strike is dropped from the ERA bucket on the SoD build.
  The decision is the ONE the class already makes (the SoD slot swap in
  `resolve_guide_icons`, which also swaps the rotation table), so the two
  surfaces cannot disagree.
* **DRUID** - the Rake is dropped from the ERA bucket on the SoD build. The
  decision is the class's own SoD probe (`sod_runes_present`, the Mangle /
  Savage Roar rune), the same latch the rotation family reads. The publish is
  corrected **inside the probe's own latch** (`sod_runes_present`), so the
  publish and the rotation the engine grades against always read the SAME
  decision - and the pick never consults the client, so it cannot move the
  probe's own latch (the behaviour `tests/druid_guide_state.lua` pins).

The result: the Era-base build publishes the Rake / the Raptor Strike (the cat
rotation asks for neither there); the SoD build does not (its rotation asks for
both). The published set is otherwise the filed one.

**When the latch lands.** The druid's SoD probe is consulted by the class's own
HUD provider on the ERA family (the Mangle slot's gate, `classes/druid.lua`'s
`get_hud_state`), so the HUD driver's first tick latches it - long before a
practice session starts, and therefore before the engine snapshots the publish
(`practice_ui.lua` reads `H.practice_neutral_actions` when the scenario starts).
The publish and the rotation the engine grades against therefore read the SAME
latched decision for the whole session.

### 2.3 The filed Regrowth ladder carried 9844 - it is a Rejuvenation id

The filed §5 lists Regrowth as *"8936 / 9856 / 9857 / 9858 / 9844"*. The
Classic 1.15 client corpus (`/home/sam/wow.export/Spell.csv`) describes 9844 as
*"Rank 10"* with **no description of its own**, and the Classic spell page
(`https://classic.warcraftdb.com/data/spell/9844`) titles it **"Rejuvenation"** -
it is the Improved Rejuvenation grant, not a Regrowth rank. The landed Regrowth
ladder is the corpus's own nine described ranks, and 9844 is not published.

The Healing Touch ladder was completed from the corpus's druid Restoration skill
line (`SkillLineAbility.csv`, skill line 573): the eleven ids the client's own
data describes as *"Heals a friendly target for $s1."* - 5185, 5186, 5187, 5188,
5189, 6778, 8903, 9758, 9888, 9889, 25297 - with the names confirmed on the
Classic spell pages (5185, 9888, 25297 all title "Healing Touch"). The
Rejuvenation ladder is the corpus's eleven described ranks (774 … 25299) plus
9842 / 9843 (the Improved Rejuvenation grants, named "Rejuvenation" on the
Classic spell page - the filed list already published those two).

## 3. The ids, and where each one is sourced

The id sources are the **in-tree** ones: the Classic 1.15 client corpus
(`/home/sam/wow.export/Spell.csv` - the id plus the client's own description)
and the client's spell names from the Classic spell pages (the
`/data/spell/<id>` title on the warcraftdb site - the operator-provided lookup
AGENTS.md names).

| ability | ids | the citation |
|---|---|---|
| Concussive Shot | 5116 | the corpus ("Dazes the target, slowing movement speed by $s1% for $d."); the name confirmed on the Classic spell page (5116); `Libs/LibClassicDurations/classAbilities.lua` carries the same id |
| Sprint | 2983 | the corpus ("Increases the rogue's movement speed by $s1% for $d." - the shared movement spell); the Classic spell page (2983) |
| Healthstone | 5720 | the corpus ("Instantly restores $s1 life."); the Classic spell page (5720) |
| Healing Potion | 439 / 440 / 441 / 2024 / 4042 / 17534 | the corpus ("Restores $s1 health."); the Classic spell page (439) |
| Food | 433 / 2639 / 5004 / 10256 / 10257 | the corpus ("Restores $o1 health over $d. Must remain seated while eating."); the Classic spell page (433) |
| Healing Touch | 5185 / 5186 / 5187 / 5188 / 5189 / 6778 / 8903 / 9758 / 9888 / 9889 / 25297 | the corpus's druid Restoration skill line (573) - every id described as "Heals a friendly target for $s1."; the names confirmed on the Classic spell pages (5185, 9888, 25297) |
| Rejuvenation | 774 / 1058 / 1430 / 2090 / 2091 / 3627 / 8910 / 9839 / 9840 / 9841 / 9842 / 9843 / 25299 | the corpus's Restoration line - every id described as "Heals the target for $o1 over $d." (9842 / 9843: the Improved Rejuvenation grants, named "Rejuvenation" on the Classic spell page) |
| Regrowth | 8936 / 8938 / 8939 / 8940 / 8941 / 9750 / 9856 / 9857 / 9858 | the corpus's Restoration line - every id described as "Heals a friendly target for $s1 and another $o2 over $d."; the names confirmed on the Classic spell pages (8936, 9856) |
| Aspect of the Cheetah | 5118 | the corpus ("The hunter takes on the aspects of a cheetah, increasing movement speed by $s1%."); the Classic spell page (5118) |

**Food and potions ARE spells** - the client's spell table carries the ITEM's
use effect (Food 433, Healing Potion 439, Healthstone 5720). The panel's
vocabulary is spells, and the use effect is the cited spell.

## 4. The keys that are deliberately NOT neutral

* **The hunter's `aimed` (Aimed Shot)** - the hunter's own drill cast
  (`PRACTICE_SHOT_ORDER`: steady, multi, aimed). It is a rotation action on the
  families whose rotation asks for it (ERA, SoD, WotLK) and an intentional
  mis-pick where the rotation does not (TBC, Forever) - the drill's own truth,
  never a neutral action. `steady` (the drill's other cast) is the same: a
  rotation action on TBC and WotLK, and an intentional mis-pick on the Era, SoD
  and Forever clients (none of them has the spell - it arrived in 2.3).
* **The hunter's `raptor_strike`** - the rotation-row key (the SoD and the
  Forever rotations ask for it): a rotation action can never be neutral.
* **The hunter's `bestial_wrath`** on the SoD build - the SoD rotation carries
  no Bestial Wrath row, so a press there is an intentional mis-pick (the
  Era-base build does not declare the slot at all).
* **The druid's `bite`** (Ferocious Bite 24248) - a rotation row on TBC (T3),
  WotLK (W8) and Forever (F6a/F6b). The spell does not exist at all on the Era
  and the SoD clients, so a press there is an intentional mis-pick (the panel
  offers the key - the druid's guide slot set is flat - but the client cannot
  cast it).
* **The druid's `shift`** - the powershift drill's own cast: the drill's truth,
  never a neutral action.
* **The druid's `innervate`, `leader_of_the_pack`, `cat_form`** and the
  rotation rows - the rotation grades those.

## 5. The verification

* **Harness:** **43 steps, 0 failed** (`bash tests/run.sh`).
* **luacheck:** **2 warnings / 0 errors in 85 files** - the standing floor
  (`compat.lua:36`, `main.lua:81`), both pre-existing. The five touched files
  are **0/0** on their own.
* **Line endings:** CRLF kept in `classes/hunter.lua` and `classes/druid.lua`;
  LF in the three test files.
* **Suites:** `tests/neutral_actions_state.lua` **4313 checks** (was 2880 - the
  cross-class contract now walks the hunter's and the druid's five slices each),
  `tests/hunter_state.lua` **1704**, `tests/druid_state.lua` **1574**.
* **The cross-class suite's new shape** (the vocabulary the two classes needed):
  the panel vocabulary is now the rotation slice + the guide slot keys + the
  shared sim's grid keys (the paladin) + **the class's own drill grid** (the
  hunter's `PRACTICE_SHOT_ORDER`, the druid's powershift cast) + the practice-
  panel ability list. The drill grid is the class's own drill cast keys - the
  panel's drill row - and a drill's own truth is never a neutral action.
* **Mutation proofs** on `/tmp/opencode/mut_hd_*` copies (a copy of the whole
  tree; the repo is never touched) - **14/14 killed**, every kill a pin failure
  (no crash):

  | mutant | killed by |
  |---|---|
  | M1 the hunter publishes the rotation action `kill_command` as neutral | the published-set pin + "the neutral key kill_command is a key of the class's own panel" + the engine-reader pin |
  | M2 the druid publishes the rotation action `rake` on WRATH | the published-set pin + the grading-integrity pin ("a rotation action can never be neutral") |
  | M3 the druid's SoD build keeps the Rake published (the probe's latch stops correcting the publish) | the SoD slice's published-set pin + the mis-pick pin + the engine-reader pin |
  | M4 the hunter's SoD build keeps the Raptor Strike published | the SoD slice's published-set pin + the mis-pick pin + the engine-reader pin |
  | M5 the druid's common list publishes the rotation action `rake` | the offer pin ("the panel offers the common ability rake only where the rotation does not ask for it") on three slices |
  | M6 the hunter's common list loses the Sprint entry | "the neutral key sprint is a key of the class's own panel" (three slices) |
  | M7 the hunter's widening seam is removed | "the widening seam appends the common abilities to the slot list" |
  | M8 the druid's Cheetah entry cites no spell id | "common action cheetah cites a spell id" (three slices) |
  | M9 the druid's publish drops the Cheetah | the published-set pin + the mis-pick pin + the engine-reader pin |
  | M10 the hunter's publish drops the Raptor Strike (ERA) | the published-set pin + the mis-pick pin + the engine-reader pin |
  | M11 the druid's publish drops the Rake (ERA) | the published-set pin + the mis-pick pin + the engine-reader pin |
  | M12 the hunter's Concussive Shot cites no spell id | "common action concussive_shot cites a spell id" (three slices) |
  | M13 the druid's Healing Touch carries no label | "common action healing_touch carries a label" |
  | M14 the hunter's resolver invents a slot the client lacks | "a client without the spells is offered no common ability" (the unknown-hides pin) |

## 6. UNCONFIRMED / not proven here

* **In-client:** the panel's action row offering the common abilities, the icons
  resolving through the name query and the NEUTRAL popup are **offline-proven
  only**. Nothing here is proven in a client; the operator's in-client pass is
  the only way to confirm that the press a player would really make is covered.
* **The in-client spell ids** are the Era 1.15 corpus's: the TBC, WotLK and
  Forever clients spell the same abilities with their own rank ids, which the
  name-first resolution finds (the ids are the citation and the locale
  fallback). The ids the running client actually uses are still owed.
* **The Cata and Mists clients carry no bucket** in either publish (the same
  shape the four classes already landed publish). The class ships no neutral set
  for them, so every non-rotation press on those clients stays a mis-pick -
  exactly as before this lane. The panel still OFFERS the common abilities
  there (the ability list is not family-gated), so a heal press on a Cata client
  is a mis-pick. Closing that needs either a CATA/MISTS bucket or a family gate
  on the ability list - a call for the orchestrator, not for this lane.
* **The drill grid for the druid** is the powershift drill's cast key (`shift`,
  `practice_ui.lua`'s `DRUID_DRILL_KEY`), read by the cross-class suite as a
  literal. The druid module does not publish it (the key is the practice
  layer's), so a change there would silently move the suite's expectation.
* **The hunter's two Raptor Strike keys** (`raptor` and `raptor_strike`, the
  same spell under two keys on the SoD and Forever panels) are a pre-existing
  shape of the class's guide slot sets, not this lane's. The landed publish
  never publishes the spell as neutral where the rotation asks for it, so the
  grading hole is closed - but the panel still shows two buttons for one spell.
