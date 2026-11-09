# The per-class NEUTRAL action sets — the class lane (2026-10-20)

**Desk:** `class-neutral-actions` · **Scope:** `classes/paladin.lua`,
`classes/warrior.lua`, `classes/rogue.lua`, `classes/shaman.lua` +
`tests/neutral_actions_state.lua` + the three class suites ·
**Status:** landed, harness green.

The engine half (the accessor, the outcome, the UI) is the sibling lane's:
`bench/practice_neutral_actions_2026-10-20.md` (desk `practice-neutral-actions`).
This file is the CLASS half: the four classes' published sets, the closed-list
contract behind them, and the hunter's / druid's sets (their lanes own those
files — the orchestrator dispatches them).

## 1. What a neutral action IS (the class-side contract)

The shared engine grades a press against the rotation: the action the rotation
asks for is a HIT, anything else is a MIS-PICK (F). A NEUTRAL action is
legitimate but ungraded — no attempt, no points, no streak change, and not a
mis-pick.

Each class publishes its own keys:

```lua
ST.<CLASS>.practice_neutral_actions = { heal = true, shield = true }                   -- flat
ST.<CLASS>.practice_neutral_actions = { ERA = { heal = true }, TBC = { heal = true } } -- per family
```

**THE CLOSED LIST.** The set is a deliberate list, never "everything except the
rotation". Every key is a key the class's OWN panel offers, and **no published
neutral key may be a rotation action on the slice it is published for** — the
engine grades the EXPECTED action first, so a rotation press still hits, but a
rotation action published as neutral would make a WRONG rotation press free.

**THE PANEL ABILITY VOCABULARY** (what every key is classified against):

```
panel(class, slice) = the rotation slice the panel grades against
                     + the class's own guide slot keys (the panel's action row)
                     + the shared sim's grid keys (the paladin only - practice.lua's
                       ABILITY_ORDER, the twist sim's ability list)
```

Every panel key gets exactly one label: **rotation** (the rotation grades it),
**neutral** (legitimate, ungraded) or **intentional mis-pick** (the rotation would
ask for it on another slice, or the client cannot cast it at all). A key nobody
classified **fails the suite** — the next ability someone adds cannot silently
become a free press.

## 2. The four published sets

| class | publish | keys |
|---|---|---|
| PALADIN | flat | `sotc`, `aw`, `hpot`, `abacus`, `stop` |
| WARRIOR | family-scoped | `FOREVER = { cleave }` |
| ROGUE | family-scoped | `ERA = { coldblood }`, `WRATH = { coldblood, shiv }`, `FOREVER = { shiv }` |
| SHAMAN | flat (empty) | `{}` |

### PALADIN — the twist sim's own ability list

The paladin is the only class that runs the shared sim session, so its panel
grid is the sim's ability list (`practice.lua`'s `ABILITY_ORDER`). Five of those
keys are legitimate but no rotation order ever asks for them:

* `sotc` — Seal of the Crusader: a real seal, and no order asks for it (the twist
  order asks for `soc` / `sob`), so a seal swap the rotation does not want is
  legitimate, not wrong.
* `aw` — Avenging Wrath: the burst cooldown (the AW combo drill was retired; the
  class's own drills are `paladin_fcfs_priority`, `paladin_prepull`,
  `paladin_judge_fit`, and none grades a cooldown).
* `hpot` — Haste Potion (a consumable).
* `abacus` — Abacus of Violent Odds (a trinket).
* `stop` — Stop Attack (the stop-attack macro; the paladin's stopattack
  discipline is a filed follow-up: `bench/paladin_followups_2026-10-19.md`).

NOT in the set: the rotation actions themselves; the guide slots' other
spellings (`consecration`, `exorcism`, `holy_shock`, `aura_mastery` — they ARE the
rotation actions under another spelling, `ST.PALADIN.practice_action_aliases`
maps them onto `cons` / `exo` / `hs` / `am`); and the abilities the class does
NOT offer as practice keys (Healing Flash, Lay on Hands, Divine Shield, Blessing
of Protection, Blessing of Sacrifice, food and drink) — the paladin's practice
surface has no key for them (the cooldown icon group carries spell IDS, not
practice action keys), so a player can never press them in a practice session.
Publishing them would invent keys the class does not have.

### WARRIOR — one key, one family

The warrior's guide slots are cut from the utility spine (`WARRIOR_UTILITY`:
Battle Shout, Bloodrage, Recklessness, Death Wish, Berserker Rage, the stances,
Blood Fury, Sweeping Strikes, Thunder Clap, Shattering Throw, Heroic Throw) plus
the compiled core order — and the utility spine IS the rotation table's own
second block. So every key the panel offers is a rotation action, with ONE
exception: **Cleave**, which the Forever guide slot set carries while the
class's own Cleave row is an ERA/TBC row (`families = { "ERA", "TBC" }`) whose
engine arm is filed (`engine = false`). On the Forever client no rotation row
asks for Cleave, so a Cleave press there is legitimate and ungraded → neutral,
published for `FOREVER` only.

Battle Shout is a rotation row on every family whose guide slots offer it
(ERA / TBC / FOREVER) and the SoD APL carries no Battle Shout row at all, so the
family that does not ask for it never offers the key either — there is nothing to
neutralise. The abilities the orchestrator named for this class (food and drink,
potions, Demoralizing Shout, Sprint, Defensive Stance, Stoneform) have NO key in
the warrior's own ability list (the APL's consumable rows are ITEMS, not spells —
the class's own pre-pull comment says so).

### ROGUE — family-scoped, and Rupture is the deliberate exclusion

* **Cold Blood** — the class's own row is a TBC/FOREVER row, so the Era branch
  and the WotLK client have no rotation row that asks for it while the talent
  exists on both → neutral there.
* **Shiv** — the class's own row is an ERA/SoD/TBC row, so the WotLK client and
  the Forever client have no rotation row that asks for it while the ability
  exists on both → neutral there.
* **Rupture** — deliberately published for NO family: on the Era client the spell
  does not exist at all (it is a TBC-era ability), so an Era press of it is an
  intentional mis-pick, not a neutral action. The panel offers the key (the
  guide slot set is flat) but the client cannot cast it.

The rogue's own drill cast keys (`PRACTICE_CAST_ORDER`: `evisc`, `ss`) are the
DRILL's graded casts, not rotation picks — the neutral set never touches a
drill's own truth (the same rule the shaman follows).

### SHAMAN — empty, and that is the class's truth

The shaman's panel vocabulary IS the rotation: the guide slots are cut from the
rotation table itself (`ST.SHAMAN.family_guide_slots`: a slot whose ROTATION row
names no family never joins a slice), and the rotation table carries one guide
slot per row. The slots a family does not play are filtered OUT of the panel
(Lightning Shield is a WRATH/SOD/FOREVER row, Strength of Earth an
ERA/FOREVER/TBC row), so "the rotation does not ask for it" never reaches the
panel on that family. The class's own drills grade rotation rows, and the weave
drill's cast keys (`weave_lb`, `weave_cl`) are the drill's own truth.

The keys the orchestrator named for this class (Healing Wave, Chain Heal, the
water shield, food and drink, potions, Lightning Shield, Strength of Earth,
Bloodlust) are accounted for above: the shields and the totems are rotation rows
(or filtered out of the panel on the families that do not play them), Bloodlust
is a WRATH rotation row, and the heals / food / potions have NO key in the
shaman's own ability list.

## 3. The hunter's and the druid's sets — FILED for the orchestrator

Their lanes own `classes/hunter.lua` / `classes/druid.lua`; these are the sets
this lane worked out from the classes' own ability lists, ready to dispatch.

### HUNTER — flat: `{ raptor = true }`

* `raptor` (Raptor Strike) is a guide slot on the ERA, SoD, TBC and Forever slot
  sets and is a rotation row on NONE of them (the hunter's rows are
  `kill_command`, `bestial_wrath`, `rapid_fire`, `arcane`, `multi`, `steady`,
  `aspect_viper`, `aspect_hawk` plus each family's own shot rows: the ERA set
  `aimed / multi / rapid_fire / serpent`, the SoD set `chimera / aimed /
  raptor_strike / wyvern_strike / aspect_falcon / wing_clip / …`, the TBC set
  `arcane / aspect_hawk / aspect_viper / bestial_wrath / kill_command / multi /
  rapid_fire / steady`, the WotLK set `kill_shot / chimera / explosive /
  aimed_wrath / arcane / steady / aspect_viper / aspect_dragonhawk /
  silencing_shot / serpent / explosive_trap / multi / black_arrow`, the Forever
  set `hawk / sniper / raptor_strike / hunters_mark / mongoose_bite /
  immolation_trap / wing_clip / serpent / arcane / multi`). A Raptor Strike
  press is legitimate on every client and is never graded → neutral, flat.
* The grid's `aimed` (Aimed Shot) is the HUNTER's own drill cast
  (`PRACTICE_SHOTS` / `PRACTICE_SHOT_ORDER`: steady, multi, aimed) — the drill's
  truth, not a rotation pick. Where a family's rotation has no Aimed Shot row
  (TBC, Forever) the key is an intentional mis-pick, never neutral.
* The orchestrator's other hunter names (food and drink, potions, Aspect of the
  Hawk / Monkey, Concussive Shot, Tranquilizing Shot, Sprint) have NO key in the
  hunter's own ability list: the two aspects ARE rotation rows on the families
  that play them (`aspect_hawk` on TBC, `aspect_viper` on TBC/SoD/WotLK/
  Forever), and the rest are not in the guide slot sets.

### DRUID — family-scoped: `{ ERA = { rake = true }, TBC = { rake = true } }`

* **Rake** is a guide slot on every family (the druid's guide slot set is flat)
  and a rotation row only on SOD / WRATH / FOREVER (`rake` rows: SOD S7, WRATH W7,
  FOREVER F4). On the Era client and the TBC client the cat rotation asks for
  neither Rake nor Bite, and Rake is a vanilla cat ability → neutral there.
* **Bite** (Ferocious Bite 24248) is deliberately published for NO family: its
  rows are TBC (T3), WRATH (W8) and FOREVER (F6a/F6b), so on the Era / SoD
  clients the spell does not exist at all → an intentional mis-pick.
* The druid's grid key `shift` is the powershift DRILL's own cast → the drill's
  truth, never neutral.
* The orchestrator's other druid names (food and drink, potions, Healing Touch,
  Regrowth, Rejuvenation, Swiftmend, Innervate, Leader of the Pack, Cat Form /
  Travel Form): **Innervate** (ERA / SoD / Forever), **Leader of the Pack** (ERA)
  and **Cat Form** (ERA / SoD / TBC / Forever) ARE rotation rows in the class's
  own table, and the heals / food / potions have NO key in the druid's own
  ability list.

## 4. The verification

* **New suite:** `tests/neutral_actions_state.lua` (720 checks) — the
  cross-class contract for the four classes this lane owns: the publish shape,
  the exact published set per family, the GRADING-INTEGRITY pin ("a rotation
  action can never be neutral"), the CLOSED LIST ("every panel key is
  classified"), the "every neutral key is a key of the class's own panel" pin,
  and the shared engine's own reader (when the engine publishes it, the class's
  publish must resolve to the family's set). The paladin's pin lives here
  because `tests/paladin_state.lua` belongs to another lane.
* **Class suites:** `tests/warrior_state.lua` (+ the neutral section),
  `tests/rogue_state.lua` (+ the neutral section), `tests/shaman_state.lua` (+ the
  neutral section) — each pins its own class's set, the family scoping and the
  grading integrity.
* **Harness:** **41 steps, 0 failed** (the new suite is NOT in `run.sh` yet — see
  §5).
* **luacheck:** **2 warnings / 0 errors in 84 files** — the standing floor
  (`compat.lua:36`, `main.lua:81`), both pre-existing and KEEP-ruled. The four
  touched addon files and the four touched test files are 0/0 on their own.
* **Line endings:** CRLF kept in `classes/paladin.lua`, `classes/warrior.lua`,
  `classes/rogue.lua`; LF in `classes/shaman.lua` and the test files (the
  shaman's file was already LF).
* **Mutation proofs** on `/tmp/opencode/neutral/mut` copies — **8/8 killed**
  (baseline green):

  | mutant | killed by |
  |---|---|
  | M1 the paladin publishes the rotation action `cons` as neutral | the published-set pin + the grading-integrity pin (6 FAILs) + the engine-reader pin |
  | M2 the rogue's ERA bucket gains the rotation action `shiv` | the grading-integrity pin ("a rotation action can never be neutral") + the published-set pin |
  | M3 the shaman publishes the rotation action `weave` as neutral | the published-set pin + the engine-reader pin |
  | M4 the warrior's FOREVER bucket gains the rotation action `ww` | the published-set pin + the grading-integrity pin |
  | M5 the paladin publishes an INVENTED key (`heal`) | the published-set pin + "is a key of the class's own panel" |
  | M6 the rogue's publish loses its family scoping (the union) | the grading-integrity pin (`shiv` becomes neutral on the Era branch) |
  | M7 a new UNCLASSIFIED panel key appears in the rogue's guide slots | the closed-list pin ("every panel key is classified") |
  | M8 the paladin's neutral set drops the potion (`hpot`) | the published-set pin |

## 5. What the orchestrator has to add (the one line `run.sh` needs)

`tests/run.sh` is contested (another lane owns it), so the new suite is not in
the harness yet. The exact line to add, **after** the `practice_ui_state` line
(currently line 78):

```bash
run "lua5.1 tests/neutral_actions_state.lua" lua5.1 tests/neutral_actions_state.lua
```

With that line the harness goes from 41 to **42 steps**.

## 6. UNCONFIRMED / not proven here

* **In-client:** the neutral press shows `NEUTRAL` in the popup and the status
  line — that is the ENGINE lane's half and it is offline-proven only (the
  sandbox drives the real `practice_ui.lua`). Nothing here is proven in a client.
* **The sets themselves** are derived from the classes' own published tables
  (rotation rows, guide slot sets, the shared sim's ability list) — the
  operator's in-client pass is the only way to confirm that a press the player
  would really make is covered.
* **The hunter's and the druid's sets** (§3) are a lane proposal, not landed
  code: their files belong to their own lanes.
