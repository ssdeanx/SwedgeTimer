# The practice-panel COMMON abilities — the class lane (2026-10-20)

**Desk:** `class-common-actions` · **Scope:** `classes/paladin.lua`,
`classes/warrior.lua`, `classes/rogue.lua`, `classes/shaman.lua` +
`tests/neutral_actions_state.lua` + `tests/warrior_state.lua` +
`tests/rogue_state.lua` + `tests/shaman_state.lua`.
**Status:** landed, harness green (43 steps / 0 failed), luacheck 2/0,
9/9 mutation proofs killed.

The engine half is the sibling desk `practice-neutral-actions`
(`bench/practice_neutral_actions_2026-10-20.md`: the accessor
`H.practice_neutral_actions`, the `neutral` outcome, the UI wording). The class
half that filed the gap is `bench/class_neutral_actions_2026-10-20.md` (§2 the
four sets, §2 the "the class does NOT offer as practice keys" gap). This file is
the follow-on: the classes now HAVE those keys.

## 1. The gap, closed

The class lane's finding (§2, the paladin): *"the abilities the class does NOT
offer as practice keys (Healing Flash, Lay on Hands, Divine Shield, Blessing of
Protection, Blessing of Sacrifice, food and drink) — the paladin's practice
surface has no key for them … so a player can never press them in a practice
session. Publishing them would invent keys the class does not have."*

So the common abilities had to be **added to the panel's ability list first**,
with their real ids and icons — and only then published as neutral.

### The mechanism (per class, in the class file)

1. **`ST.<CLASS>.practice_common_actions`** — the class's published
   PRACTICE-PANEL ability list: one entry per common ability, carrying the
   action `key`, the panel `label`, the client's English spell `names` (the
   lookup key) and the **cited** spell `ids`, plus an optional `families` gate.
2. **`ST.<CLASS>.resolve_practice_common_action(action)`** — resolves one entry
   against the client's own spell data: the **English name first** (every client
   family answers its own rank art through it — the rogue's `resolve_named_spell`
   rule), then the **cited id ladder** (`api.get_family_spell_id_state`, the
   locale fallback). The query is **family-correct** (the operator's name-vs-id
   rule): the NAME on TBC, the numeric id everywhere else. An ability the
   running client does not have is **dropped** (unknown-hides): the panel never
   offers a button the client cannot cast.
3. **`ST.<CLASS>.practice_panel_slots()`** — the panel's ability list: the
   class's own guide slots **plus** the common abilities the running client has.
4. **`ST.<CLASS>.apply_practice_panel_actions()`** — appends them to the class's
   own guide slot list. It runs **inside the `if st.practice_ui …` block of
   `post_init`**, i.e. AFTER the guide frame built its icons and BEFORE
   `practice_ui.init` — the shaman's `apply_family_slots` precedent. The frame
   stacks one icon per slot and fades in only the CURRENT action's, and the
   frame's icons are built once and never rebuilt, so **the live next-action
   guide is untouched** while the practice panel's action row (which reads the
   slot list LIVE) offers the common abilities with their icons.

**No default-visible change outside the practice panel:** the widening happens
only in the practice block, the guide frame keeps its own icon set, and the
HUD row reads `ST.<CLASS>.HUD_SLOTS` (a separate table).

## 2. The four published sets

| class | publish | the common abilities (the panel's own list) |
|---|---|---|
| PALADIN | flat | `holy_light`, `flash_of_light`, `lay_on_hands`, `divine_shield`, `bop`, `food` (+ the class's own `sotc`, `aw`, `hpot`, `abacus`, `stop`) |
| WARRIOR | family-scoped | `sprint`, `demoralizing_shout`, `healthstone`, `flask`, `food` on every family; `battle_shout` on **WRATH** only; `cleave` on **FOREVER** (the class lane's own) |
| ROGUE | family-scoped | `sprint`, `evasion`, `kick`, `healthstone`, `food` on every family; `coldblood` on ERA/WRATH; `shiv` on WRATH/FOREVER (the class lane's own) |
| SHAMAN | flat | `healing_wave`, `chain_heal`, `water_shield`, `healing_potion`, `food` |

### The ids, and where each one is sourced

The id sources are the **in-tree** ones: the Classic 1.15 client corpus
(`/home/sam/wow.export/Spell.csv` — the id plus the client's own description)
and the **client's spell names** from the Classic spell pages (the
`/data/spell/<id>` page on the warcraftdb site — its title carries the client's
own spell name; the URL is the operator-provided lookup AGENTS.md names).

| ability | ids | the citation |
|---|---|---|
| Holy Light | 19968 / 19980 / 19981 / 19982 | the corpus ladder ("Heals a friendly target for $s1."); the name confirmed on the Classic spell page (19968) |
| Flash of Light | 19750 / 19751 | the corpus ladder; the name confirmed on the Classic spell page (19750) |
| Lay on Hands | 633 / 2800 / 10310 | the class's OWN CD icon slot id (`classes/paladin.lua` CD_CORE_SLOTS) + the corpus ladder |
| Divine Shield | 642 / 1020 | the class's OWN CD icon slot id + `Libs/LibClassicDurations/classAbilities.lua` ("Spell({ 642, 1020 }") |
| Blessing of Protection | 1022 / 5599 / 10278 | `Libs/LibClassicDurations/classAbilities.lua` ("Spell({ 1022, 5599, 10278 }") |
| Food | 433 / 2639 / 5004 / 10256 / 10257 | the corpus ("Restores $o1 health over $d. Must remain seated while eating."); the name confirmed on the Classic spell page (433) |
| Sprint | 2983 | the corpus ("Increases the rogue's movement speed by $s1% for $d."); the name confirmed on the Classic spell page (2983) |
| Demoralizing Shout | 1160 / 6190 / 11554 / 11555 / 11556 | the class's OWN debuff-bar id table (`classes/warrior.lua` `demo_shout_ids`); the name confirmed on the Classic spell page (1160) |
| Healthstone | 5720 | the corpus ("Instantly restores $s1 life."); the name confirmed on the Classic spell page (5720) |
| Diamond Flask | 24427 | the corpus ("Restores $s2 health every $t2 sec and increases your Strength by $s1.") — the APL's own consumable row (24427) |
| Healing Wave | 331 / 332 / 547 / 913 / 939 / 959 / 25357 | the corpus ladder; the top rank 25357 is also in `Libs/LibClassicDurations/classAbilities.lua` ("[GetSpellInfo(25357)] — Healing Wave") |
| Chain Heal | 1064 / 10622 / 10623 | the corpus ladder ("Heals the friendly target for $s1, then jumps to heal additional nearby targets.") |
| Water Shield | 52127 / 52129 / 52131 / 24398 / 33736 / 33737 / 34827 / 57960 | the class's OWN shield-aura id table (`classes/shaman.lua` `WEAVE_WATER_SHIELD_IDS`); the names table beside it carries both client names ("Water Shield" and "Mana Shield" — the SoD rename) |
| Healing Potion | 439 / 440 / 441 / 2024 / 4042 / 17534 | the corpus ("Restores $s1 health."); the name confirmed on the Classic spell page (439) |
| Evasion | 5277 | the name confirmed on the Classic spell page (5277) |
| Kick | 1766 | the name confirmed on the Classic spell page (1766); the name is already in the class's own `SLOT_SPELL_NAMES` |
| Battle Shout | 6673 / 11549 / 25289 | the corpus ladder ("The warrior shouts, increasing the melee attack power of all party members …"); the names confirmed on the Classic spell pages; the TBC rank 8 (2048) is the class's own pre-pull row |

**Food and potions ARE spells** — the client's spell table carries the ITEM's use
effect (Food 433, Drink 430, Healing Potion 439, Healthstone 5720, Diamond
Flask 24427). The APLs' consumable rows are items (`bench/rotation_gap_vs_apl_
2026-10-20.md` §0.0: "they are items, not spells") — but the panel's vocabulary
is spells, and the use effect is the cited spell.

## 3. The three rules, and how they are held

1. **A rotation action may never be neutral.** The cross-class suite pins it per
   slice ("the neutral key X is not a rotation action (a rotation action can
   never be neutral)") and the class suites pin it per bucket. The engine grades
   the EXPECTED action first, so a rotation press still hits — but a rotation
   action published as neutral would make a WRONG rotation press free.
2. **A common ability that IS a rotation action on some family is neutral only
   on the families where it is not.** The one case in these four classes is the
   warrior's **Battle Shout**: an APL utility row on ERA, TBC and FOREVER, and
   **no row on the WotLK client** (whose guide slots do not offer the key either)
   → published for WRATH alone, and the panel offers it on WRATH alone (the
   `families` gate on the published entry).
   The shaman's **Lightning Shield** is deliberately NOT in the list: it is a
   rotation row on WRATH/SOD/FOREVER, and the SoD build shares the Era family
   token with the Era build (the engine's family-scoped publish reads `st.family`
   only), so publishing it as neutral on the Era family would make a WRONG
   Lightning Shield press free on the Era build. The class's own classic-era
   shield (**Water Shield**) is the non-rotation row instead.
3. **The closed list still holds.** The suite's panel vocabulary is now the
   rotation slice + the guide slot keys + the **class's own practice-panel
   ability list** (family-gated), and every panel key must be classified
   (rotation / neutral / intentional mis-pick). A new ability someone adds
   cannot slip in unclassified.

## 4. The verification

* **Harness:** **43 steps, 0 failed** (`bash tests/run.sh`; the step count moved
  from 42 because a sibling lane added a suite mid-session — this lane's suites
  are all green).
* **luacheck:** **2 warnings / 0 errors in 85 files** — the standing floor
  (`compat.lua:36`, `main.lua:81`), both pre-existing. The eight touched files
  are **0/0** on their own.
* **Line endings:** CRLF kept in `classes/paladin.lua`, `classes/warrior.lua`,
  `classes/rogue.lua`; LF in `classes/shaman.lua` and the four test files (the
  shaman's file was already LF).
* **Suites:** `tests/neutral_actions_state.lua` **2880 checks** (was 720) — the
  cross-class contract, now also pinning the published list (every entry names
  the client's spell, carries a label and cites at least one numeric id), the
  family gates, the offer pin ("the panel offers a common ability only where
  the rotation does not ask for it") and the widening seam (the slot list
  carries the common abilities the client has; the seam appends them and is
  idempotent). `tests/warrior_state.lua` **2017**, `tests/rogue_state.lua`
  **1095**, `tests/shaman_state.lua` **1035**.
* **Mutation proofs** on `/tmp/opencode/mut_common` copies — **9/9 killed**:

| mutant | killed by |
|---|---|
| M1 the paladin publishes the rotation action `cons` as neutral | the published-set pin + the grading-integrity pin + the engine-reader pin |
| M2 the warrior's WRATH bucket gains the rotation action `bloodrage` | the published-set pin + the grading-integrity pin |
| M3 the shaman publishes the rotation action `weave` as neutral | the published-set pin + the grading-integrity pin + the engine-reader pin |
| M4 the rogue's TBC bucket gains the rotation action `shiv` | the published-set pin + the grading-integrity pin |
| M5 the paladin's neutral set drops the common ability `food` | the published-set pin + the closed-list pin + the engine-reader pin |
| M6 the warrior's practice-panel ability list loses the `food` entry | "the neutral key food is a key of the class's own panel" |
| M7 the widening seam is removed (the panel offers no common abilities) | "the widening seam appends the common abilities to the slot list" |
| M8 the warrior's Battle Shout family gate is dropped | the offer pin ("the panel offers the common ability battle_shout only where the rotation does not ask for it") + the closed-list pin |
| M9 the rogue's neutral set publishes the drill's own cast (`evisc`) | "the neutral key evisc is a key of the class's own panel" + the published-set pin |

## 5. The hunter's and the druid's lists — FILED for the orchestrator

Their lanes own `classes/hunter.lua` / `classes/druid.lua`; these are the lists
this lane worked out, ready to dispatch. Every id below carries the same
citation (the Classic 1.15 client corpus + the Classic spell page).

### HUNTER — flat: the common abilities below

| key | label | ids | the citation |
|---|---|---|---|
| `concussive_shot` | Concussive Shot | 5116 | the corpus ("Dazes the target, slowing movement speed by $s1% for $d."); the name confirmed on the Classic spell page (5116); `Libs/LibClassicDurations/classAbilities.lua` carries the same id ("Spell(5116, …) -- Concussive Shot") |
| `sprint` | Sprint | 2983 | as the warrior's Sprint (the corpus + the Classic spell page) |
| `healthstone` | Healthstone | 5720 | as the warrior's Healthstone (the corpus + the Classic spell page) |
| `healing_potion` | Healing Potion | 439 / 440 / 441 / 2024 / 4042 / 17534 | as the shaman's Healing Potion (the corpus + the Classic spell page) |
| `food` | Food | 433 / 2639 / 5004 / 10256 / 10257 | as the paladin's Food (the corpus + the Classic spell page) |

None of them is a hunter rotation row (the hunter's rows are `kill_command`,
`bestial_wrath`, `rapid_fire`, `arcane`, `multi`, `steady`, the aspects and each
family's shot rows — `bench/class_neutral_actions_2026-10-20.md` §3), so the set
is flat. The hunter's **own drill cast** (`aimed` — `PRACTICE_SHOT_ORDER`) stays
the drill's truth and is never neutral.

### DRUID — flat: the common abilities below

| key | label | ids | the citation |
|---|---|---|---|
| `healing_touch` | Healing Touch | 9888 / 9889 (+ the rest of the ladder — the druid lane to complete it) | the corpus's druid Restoration skill line (the Healing Touch ranks 9888/9889 sit in it); the names confirmed on the Classic spell pages (9888 / 9889) |
| `rejuvenation` | Rejuvenation | 774 / 9839 / 9840 / 9841 / 9842 / 9843 | the corpus ("Heals the target for $o1 over $d."); the names confirmed on the Classic spell pages |
| `regrowth` | Regrowth | 8936 / 9856 / 9857 / 9858 / 9844 | the corpus ("Heals a friendly target for $s1 and another $o2 over $d."); the names confirmed on the Classic spell pages |
| `cheetah` | Aspect of the Cheetah | 5118 | the corpus ("The hunter takes on the aspects of a cheetah, increasing movement speed by $s1%."); the name confirmed on the Classic spell page (5118) — a movement spell |
| `healthstone` | Healthstone | 5720 | as the warrior's Healthstone |
| `healing_potion` | Healing Potion | 439 / 440 / 441 / 2024 / 4042 / 17534 | as the shaman's Healing Potion |
| `food` | Food | 433 / 2639 / 5004 / 10256 / 10257 | as the paladin's Food |

**Swiftmend is deliberately left out:** the Era client has no Swiftmend spell, and
the TBC/WotLK ids (47824 / 31216) are not in the Era corpus — the druid lane must
either source it for the families that have it or leave it out (never invent an
id). The druid's own rotation rows stay rotation actions: `rake` (already
neutral on ERA/TBC by the class lane's own set), `innervate`, `leader_of_the_pack`
and `cat_form` (the class lane's §3 list).

## 6. Judgement calls (the orchestrator may rule otherwise)

1. **The panel's button label is the KEY.** The practice row's label map is
   built from the ROTATION entries only (`practice_ui.lua`'s
   `scenario_action_order`), so a guide-slot button shows its key — the shipped
   behaviour for every guide slot ("consecration", "exorcism"). The common
   abilities therefore read "holy_light", "divine_shield" and so on. A nicer
   label needs the panel's label map to read the slot's own `label` field — an
   engine-side change (out of this lane's scope).
2. **The neutral set is family-scoped by `st.family`, not by the BUILD.** The
   SoD build runs on the Era client, so the engine cannot separate the SoD build
   from the Era build in the publish. That is why the warrior's Battle Shout is
   WRATH-only and the shaman's Lightning Shield is left out entirely. Closing
   that would need a build token in the engine's family-scoped publish (the
   engine lane's call).
3. **The drill-list press path is NOT neutral.** The engine's neutral outcome
   lives in `H.rotation_run_decide` (the ROTATION scenario). A drill-list press
   is graded by the class's own drill grader, so a common ability pressed during
   a drill session is still a mis-pick there. The engine lane owns that seam
   (the drill graders would need the neutral set).
4. **The SoD client's renamed Water Shield** is offered under the key
   `water_shield` with both client names ("Water Shield" / "Mana Shield") — the
   resolution takes the first name the client answers.
5. **The name-first resolution** means an English-locale client always resolves
   the CURRENT rank; a non-English client falls back to the cited id ladder
   (the tree's established English-name convention, and the ids are published so
   the fallback exists). On TBC the fallback cannot stand in (that client
   answers names only) — an ability whose name the client does not index is
   simply not offered there (unknown-hides).

## 7. UNCONFIRMED / not proven here

* **In-client:** the panel's action row offering the common abilities, the icons
  resolving through the name query, and the NEUTRAL popup are **offline-proven
  only** (the sandbox drives the real class modules; the panel's own rendering
  is the engine lane's offline proof). Nothing here is proven in a client.
* **The spell NAMES** are the client's own (the Classic spell page's title is
  the client's spell name) and the ids are the Era 1.15 corpus's — the TBC,
  WotLK and Forever clients spell the same abilities with their own rank ids,
  which the name-first resolution finds. The **in-client** ids are therefore
  still owed (the operator's pass).
* **The id ladders are partial** for the heals (Holy Light, Flash of Light,
  Healing Wave, Chain Heal, Rejuvenation, Regrowth, Healing Touch): the corpus
  carries every rank, but only the ranks this lane could name on the Classic
  spell pages are published. The name resolution does not depend on the ladder
  (it is the citation and the locale fallback).
* **The four classes' sets** are derived from the classes' OWN rotation tables
  and the client's own spell data — the operator's in-client pass is the only
  way to confirm that the press a player would really make is covered.
