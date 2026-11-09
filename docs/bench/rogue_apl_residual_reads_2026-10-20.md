# The rogue's utility-layer residuals — 2026-10-20

Desk: `rogue-apl-reads`. **Extends** `bench/rogue_apl_utility_build_2026-10-20.md`
(the utility-layer lane) — it does not replace it: that file's §1 (what landed),
§4 (the divergences left on the table) and §5 (the default-visible change) still
stand. This file records what closed the four rows that file left **filed**
(§2's table: four rows shipped `live = false`).

**Scope:** `classes/rogue.lua`, `rogue_guide.lua`, `tests/rogue_state.lua`,
`tests/rogue_guide_state.lua`. No git, no lint-config change, no TOC/version/
option change, no other class touched, no shared file touched
(`practice.lua`, `practice_ui.lua`, `option_tables.lua`, `config_presets.lua`,
`compat.lua`, `main.lua`, `bars.lua`, `hud.lua` are untouched).

**Rulings applied (unchanged from the lane they came from):**

* **HU-13 (the two flags):** `live` = the line's read exists in the shipped tree
  today and the line can be evaluated; `engine` = the frozen guide engine has an
  arm that can ask for it. A `live = false` row names the exact read (or APL
  gate) it waits for in `needs`.
* **HU-12 (the prepull split):** unchanged — the pre-pull rows stay in their own
  table.
* **unknown-hides:** a state the client cannot answer is nil, never false; a
  line whose gate cannot be read is never asked for.

---

## 1. The headline: two name corrections (the client is the authority)

Both were re-fetched on 2026-10-20 from the **client's own spell table** — the
`spellIcons` section of the sims' generated client database
(`wowsims/wotlk assets/database`, `wowsims/forever assets/database`; it is the
client's own DB2 spell dump, not a web page).

| id | the shipped name | the CLIENT's own name | what it actually is |
|---|---|---|---|
| 54758 (WotLK) | "Hypersharp Weapon" | **"Hyperspeed Acceleration"** | the Engineering **belt enchant's EFFECT** ("Hyperspeed Accelerators", enchant effect 3604) |
| 1259812 (Forever) | "Gnome Eureka" | **"Eureka!"** | the **Gnome RACIAL** (the rogue's row lowers the energy cost) |

* **"Hypersharp Weapon" does not exist in the WotLK client at all** — zero hits
  across the client's spell, enchant and item tables (the Tier-10 two-handed
  weapon enchant is "Berserking", effect 3789 → spell 59621). The sim models
  54758 as the belt enchant's effect: a **60 s cooldown that activates a 12 s
  haste aura** (`wowsims/wotlk sim/common/wotlk/enchant_effects.go`, enchant
  effect 3604 — `character.NewTemporaryStatsAura("Hyperspeed Acceleration",
  actionID, stats.Stats{stats.MeleeHaste: 340, stats.SpellHaste: 340},
  time.Second*12)`).
* **1259812 is the Gnome racial** on the Forever client: `sim/core/racials.go`
  — `case proto.Race_RaceGnome: applyExpansiveMind(character); applyEureka(character)`
  and, for the rogue, `spellID, resourceType = 1259812, proto.ResourceType_ResourceTypeEnergy`
  (the racial lowers the rogue's ENERGY cost and raises its damage, for the
  racial's own duration and cooldown). 1259799 ("Elune's Light") is the Night
  Elf racial in the same file — the previous lane's name was right.

These are corrections in the same class as the nine the utility layer already
recorded — the **APL gap analysis's names were the input, not the authority**,
and this time the previous lane's own table carried the wrong names forward.

## 2. The four residuals, one by one

### 2.1 The Forever Vanish (1857) — WIRED

The APL's i=3 row (`wowsims/forever ui/specs/rogue/dps/apls/default.apl.json`):

```
NOT(dotIsActive(11290)) AND currentEnergy >= spellCurrentCost(11290)
AND NOT(Use Ambush Opener) AND Use Stealth/Vanish for Damage
AND Current Points less than 5 AND NOT(SnD Fall Imminent)
```

The filed read was "the Garrote spell's CURRENT energy cost". **That read
exists** — the previous lane's reason ("compat.lua has no wrapper for a spell's
energy cost") was too narrow:

* `api.GetSpellPowerCost` (compat.lua:298-304) is a pass-through to
  `_G.GetSpellPowerCost` or `C_Spell.GetSpellPowerCost`, and the client returns
  **one entry per power type**, each with `.type` and the flat amount in
  `.cost`.
* The **client's own code** reads that shape on both target clients:
  `classic_era` and `origin/forever`
  `Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua` (the
  "ManaAndEnergy" overlay strategy: `costInfo.type == Enum.PowerType.Energy`)
  and `Blizzard_PersonalResourceDisplay.lua` (`costInfo.cost` for the matching
  power type).
* `Enum.PowerType.Energy` is the client's own enum, read at load time; a client
  that does not expose it leaves the read **unknown** (nil) — never a guessed
  type.

So the class reads the Garrote's energy cost (by the client's own spell data,
through the class's name resolution) and compares it with **the class's own
energy pool** (`inputs.energy_now`, `api.UnitPower("player", 3)`) — the APL's
comparison, literally.

**What landed**

* `classes/rogue.lua`: `ROGUE_ENERGY_POWER_TYPE` + `energy_cost_of(costs)`
  (the house's `rage_cost_of` shape with the client's power type as the
  selector), and the gather's `inputs.garrote_energy_cost`.
* `rogue_guide.lua`: the **opener cluster** (which owns the APL's own row
  order) gains the i=3 Vanish row: the Garrote dot down, the energy at/above
  the Garrote's cost, `cp < 5` and the Slice and Dice **not** about to fall
  (`snd_remains > 2` — the APL's `auraRemainingTime(6774) <= 2s`).
  `vanish_verdict` stays silent for that family (the row rides the cluster, so
  the APL's order is kept).
* The row's flags: `live = true`, `engine = true`; `needs` is gone (nothing is
  waited for any more).

### 2.2 The WotLK Hypersharp row (54758) — the filed reason was wrong; the row stays filed, and the dead arm is gone

**What the brief inherited was wrong.** The filed reason said "the enchant
spell reads off cooldown forever once it is applied" — i.e. that 54758 was a
permanent enchant. It is not: 54758 is the **belt enchant's effect** (a 60 s
cooldown that applies a 12 s haste aura in the sim), and the permanent enchant
spell is 54999 ("Hyperspeed Accelerators").

**What the class can read on the client:** 54758 is an **item effect**, not a
spell in the rogue's spellbook:

* `api.is_spell_known(54758)` reads false (item effects are not known spells),
  so the house's readiness shape can never prove it;
* `api.GetSpellCooldown(54758)` cannot see the item's cooldown;
* the haste buff's **aura id is UNCONFIRMED in-client**, and the belt's own
  item cooldown would need `api.GetItemCooldown` on the belt's **item name**
  (unknown to the class).

So the row's line still **cannot be evaluated**, and under HU-13 that is
exactly `live = false`. What changed:

* `needs` now names the **exact** missing read (the belt enchant's own
  AVAILABILITY — the item effect's cooldown and the buff's aura id), instead of
  the wrong "permanent enchant" story;
* the row's **name and citation are corrected** ("Hyperspeed Acceleration" —
  the client's own name; the belt enchant's effect, with the sim's own
  implementation cited);
* `engine = false` is now **literally true**: the dead `hypersharp_verdict` arm
  (its input `hypersharp_pending` was never produced by anything, so it could
  never fire) and its rule slot **5e** are **removed**, along with the action's
  entries in `OPENER_RANK`, the practice reasons and the rotation label.

**The decision, stated plainly:** the brief offered "`live = true, engine =
false` with the reason" on the premise that a permanent buff is always up. The
premise is refuted by the client's own spell table and by the sim's own
implementation, so the honest state is the filed one — with a true reason. The
row's flags were already truthful; what was not truthful was the filed reason
and the dead arm, and both are fixed. **No behaviour changes** (the arm could
never fire): the row stays out of the WotLK slice exactly as before.

### 2.3 The Forever Gnome Eureka! (1259812) — WIRED (three of the APL's four disjuncts)

The APL's i=13 row is the APL's own **"Gnome Eureka - Should Cast"** variable
(`valueVariables`), expanded:

```
spellIsKnown(1259812) AND spellIsReady(1259812) AND (
  NOT spellIsKnown(13750)                    -- the Adrenaline Rush is not known
  OR auraIsActive(13750)                      -- the Adrenaline Rush's buff rides
  OR spellTimeToReady(13750) > spellFullCooldown(1259812)
  OR remainingTime < spellTimeToReady(13750) ) -- the fight is about to end
```

**What exists in the shipped tree** — all three of the brief's reads:

| the APL's leg | the shipped read |
|---|---|
| `spellIsKnown(1259812) AND spellIsReady(1259812)` | the house's `utility_ready` (known + usable + off cooldown) |
| `NOT spellIsKnown(13750)` (the **known-vs-on-cooldown split** `ar_ready` cannot make) | `api.is_spell_known(ar_query)` — the new `inputs.ar_known` |
| `auraIsActive(13750)` | `api.scan_unit_aura` through the class's `utility_aura_present` — the new `inputs.ar_buff_active` |
| `spellTimeToReady(13750)` | the already-read `inputs.ar_cd_remaining` |
| `spellFullCooldown(1259812)` | `api.GetSpellBaseCooldown` — the new `inputs.gnome_eureka_full_cd` (milliseconds → seconds; a non-positive reading is "no value" → nil) |

**What does NOT exist:** the fourth disjunct — the **fight's remaining time**
(`remainingTime`). The class has no fight clock (its `ttd` is the *target's*
death, not the encounter's end). An OR is true when **any** leg is proven
true, so the row fires off the three proven legs and **under-prompts** when
only the fourth would have fired. That is the safe direction (no advice beats
wrong advice), and it is stated in the arm's own comment.

**What landed:** the new `gnome_eureka_verdict` arm (FOREVER-only), the rule
slot **5j** (after the paired pops, in the APL's order: i=13 sits after i=11/i=12),
the five new inputs, the practice ctx's frozen input names and cooldown row,
and the rotation label ("Eureka!"). The row's flags: `live = true`,
`engine = true`.

### 2.4 The TBC Backstab (26863) — honestly off, and the reason is now exact

The brief: "if the gate is a client-side condition the class can read, wire it;
otherwise keep it honestly off with the reason."

**The gate is not a client-side condition.** `Use Backstab` is a **build
constant** in the TBC APL's own `valueVariables`
(`wowsims/tbc-new ui/specs/rogue/dps/apls/swords.apl.json`: `{"name": "Use
Backstab", "value": {"const": {"val": "false"}}}`) — the sim's build choice, not
a state of the character. There is nothing on the client to read: the row is
dead **in the sim itself**, and the class never evaluates it.

So the row stays `live = false, engine = false`, and `needs` now says exactly
that ("NOTHING TO READ: … a BUILD CONSTANT … not a client-side state … filed by
construction and never evaluated"). The class's **builder arm** is what plays
Backstab (on a dagger mainhand) — the same de-duplication the other builder
rows carry.

## 3. The builder rows: `engine = false` is a de-duplication, never a gap

The brief asked for this to be visible where a reader sees it. It now is, in
**three** places:

1. the rotation table's header comment (the `engine` field's own definition);
2. **every builder row's own `note`** — the Saber Slash, the three Mutilates,
   the two Hemorrhages, the two Backstabs:
   *"the engine's builder action already plays it - engine = false is a
   de-duplication, not a gap"*;
3. the class suite **pins** it: a builder row with `engine = false` whose note
   does not say so fails the suite.

## 4. The default-visible change (stated plainly)

* **The Forever client's guide can now prompt two more actions**: "Vanish"
  (the APL's i=3 opener, gated on the Garrote's energy cost) and "Eureka!"
  (the Gnome racial, rule 5j). Both are slot-less, exactly like the shipped
  SnD/AR/BF/CB/HfB rows — the rotation label names them; no icon lights (the
  guide's slot contract is frozen).
* **The Forever practice panel's button row grows by two** (the two rows that
  are now engine-facing). The builder rows and the filed rows stay out.
* **Nothing else changes**: the WotLK loses a dead rule slot (5e) it could
  never fire, and no other family's slice, HUD slot, option or default moves.
* The **Era and TBC clients are untouched** (their APL utility rows are all
  builder rows).

## 5. Validation

| check | result |
|---|---|
| `tests/rogue_state.lua` | **PASS — 939 checks** (938 before the last pins; 922 at the utility layer's landing) |
| `tests/rogue_guide_state.lua` | **PASS — 921 checks** (896 at the utility layer's landing) |
| full harness (`bash tests/run.sh`) | **41 steps, 0 failed** |
| luacheck | **2 warnings / 0 errors in 83 files** (the floor; the four files this lane touched: 0 warnings) |
| line endings | `classes/rogue.lua` and `rogue_guide.lua` stay pure CRLF; the two test files stay pure LF |
| trailing whitespace | none in the four touched files |
| mutation proofs (`/tmp/opencode` copies) | **27 / 27 killed** (`python3 /tmp/opencode/mutations_rogue_reads.py`) |

The mutation set (each applied to a `/tmp/opencode` copy of the tree): the
gather's energy-cost read dropped, the power-type selector ignored (the cost
table's mana entry taken instead), the energy-type guard removed, the engine's
energy gate dropped, the Slice-and-Dice fall-imminent line loosened, the
cluster's Vanish row removed, the cluster's Vanish row ignoring the Garrote
dot, the ctx input names dropped (the cost and the Eureka's readiness), the
gather's four new reads dropped one by one, the Eureka's readiness gate, its
family gate, its three disjuncts and its base-cooldown comparison each
weakened, the Eureka's arm unreachable from the rule chain, the ctx cooldown
row dropped, the two wired rows' `live` flags flipped back to filed, the two
corrected names reverted, the two filed `needs` reasons hidden, a builder row's
flag note dropped, and the rotation label losing the new racial.

## 6. Filed, not fixed (for the next desk)

* **The fight's remaining time** (`remainingTime`) has no read — the Gnome
  Eureka! row's fourth disjunct stays unreadable (the row under-prompts).
* **The belt enchant's availability** (the WotLK 54758 row) has no read — it
  needs the belt's **item name** for `api.GetItemCooldown`, and the haste
  buff's aura id is UNCONFIRMED in-client.
* **The item-effect rows** (the WotLK belt row) are not rogue abilities at all:
  the class cannot ask for them, and the row says so.
* **The TBC's builder divergence** (the class's builder chain may play Backstab
  on a dagger mainhand while the TBC APL's build constant says "Use Backstab =
  false") is unchanged — the builder chain is a shipped behaviour outside this
  lane's scope.
* **The ids remain citations**: the class resolves every spell by NAME through
  the client's own spell data (the house rule), so in-client confirmation of
  the two corrected names is still owed.
