# The rogue's APL utility layer — 2026-10-20

Desk: `rogue-apl`. **The APL gap analysis is the input, not the authority**: every
id, index, name and condition below was re-fetched from the sim sources on
2026-10-20 (the six rogue APL files with every `groupReference` expanded inline,
plus the sims' own spell data) and checked against the shipped file. The gap
analysis's rogue section (`bench/rotation_gap_vs_apl_2026-10-20.md` §3) carries
**nine errors** — the corrections and their citations are in §4.

**Scope:** `classes/rogue.lua` (the rotation table's spine rows, the prepull
table, the gather reads, the rotation-label names), `rogue_guide.lua` (the arms,
the rule order, the practice input names), `tests/rogue_state.lua`,
`tests/rogue_guide_state.lua`. No git, no lint-config change, no TOC/version/
option change, no other class touched.

**Rulings applied:**

* **HU-12 (prepull split):** the APL's spell rows ride the rotation table; the
  APL's `prepullActions` rows live in their own table (`ST.ROGUE.practice_prepulls`,
  the hunter's shape).
* **HU-13 (the two flags, cross-class):** `live` = the line's read exists (in
  `compat.lua` today) and the line can be evaluated; `engine` = the frozen guide
  engine has an arm that can ask for it. A `live = false` row names the exact
  read (or APL gate) it waits for in `needs`.

---

## 1. What landed

### 1.1 The rotation table's utility spine (`ST.ROGUE.practice_rotation`)

The shipped table carried 12 keys — every one of them a damage ability, a
debuff or a cooldown pop. The spine adds **24 rows** (36 in the table): the
sims' own utility rows, each with the APL file + priority index, the per-family
spell id + the client's English name, the family gate, and the two flags.

| # | action | label | families | ids (per family) | live | engine | APL |
|---|---|---|---|---|---|---|---|
| 13 | `vanish` | Vanish | SOD | 1856 | true | true | sod i=7 |
| 14 | `poisoned_knife` | Poisoned Knife | SOD | 425012 | true | true | sod i=5 |
| 15 | `saber_slash` | Saber Slash | SOD | 424785 | true | **false** | sod i=3, i=11 |
| 16 | `vanish` | Vanish | WRATH | 26889 | true | true | wotlk mutilate i=4 |
| 17 | `tricks_of_the_trade` | Tricks of the Trade | WRATH | 57934 | true | true | wotlk combat i=13 / mutilate i=8 |
| 18 | `killing_spree` | Killing Spree | WRATH | 51690 | true | true | wotlk combat i=14 |
| 19 | `hypersharp` | Hypersharp Weapon | WRATH | 54758 | **false** | true | wotlk combat i=10,11 / mutilate i=6 |
| 20 | `mutilate` | Mutilate | WRATH | 48666 | true | **false** | wotlk mutilate i=12 |
| 21 | `ambush` | Ambush | FOREVER | 11269 | true | true | forever i=1 |
| 22 | `garrote` | Garrote | FOREVER | 11290 | true | true | forever i=2 |
| 23 | `vanish` | Vanish | FOREVER | 1857 | **false** | true | forever i=3 |
| 24 | `preparation` | Preparation | FOREVER | 14185 | true | true | forever i=5 |
| 25 | `premeditation` | Premeditation | FOREVER | 14183 | true | true | forever i=17 |
| 26 | `venom` | Venom | FOREVER | 1310703 | true | true | forever i=19 |
| 27 | `blood_fury` | Blood Fury | FOREVER | 20572 | true | true | forever i=11 |
| 28 | `elunes_light` | Elune's Light | FOREVER | 1259799 | true | true | forever i=12 |
| 29 | `gnome_eureka` | Gnome Eureka | FOREVER | 1259812 | **false** | true | forever i=13 |
| 30 | `mutilate` | Mutilate | FOREVER | 1241584 | true | **false** | forever i=26 |
| 31 | `hemorrhage` | Hemorrhage | FOREVER | 16511 | true | **false** | forever i=24 |
| 32 | `backstab` | Backstab | FOREVER | 11281 | true | **false** | forever i=25 |
| 33 | `ghostly_strike` | Ghostly Strike | FOREVER | 14278 | true | **false** | forever i=23 |
| 34 | `mutilate` | Mutilate | TBC | 34413 | true | **false** | tbc i=13 |
| 35 | `hemorrhage` | Hemorrhage | TBC | 26864 | true | **false** | tbc i=10 |
| 36 | `backstab` | Backstab | TBC | 26863 | **false** | **false** | tbc i=11 (dead row) |

**Why the builder rows carry `engine = false`:** the engine's single `builder`
action already plays them — the class's candidate chain resolves the spell by
NAME (`resolve_builder_entry`), so a dedicated `mutilate` / `hemorrhage` /
`backstab` / `saber_slash` / `ghostly_strike` arm would be a second builder path
and would double-prompt. The rows still ship: the table is the APL's citation
surface, and the ids are the family-split ones the gap analysis called out.

**The slice (`practice_rotation_for`) is the rows the engine can ACTUALLY ask
for** (`entry.engine ~= false and entry.live ~= false`): the panel's button row
is a fixed strip, and a row the engine can never emit — a builder row (the
builder arm plays it) or a filed row (its read does not exist yet) — is a
button that can never be the right answer.

**The SoD is its own slice.** The table used to map the `SOD` token onto the
`ERA` slice; it no longer does. The SoD rows ride the same action keys as the
Era rows (the provider's SoD latch), so the shared rows carry `SOD` as well —
but the SoD-ONLY rows (the Saber Slash builder, the Poisoned Knife window, the
SoD Vanish) are gated on the `SOD` token alone. The plain Era APL carries none
of them, and the Era client must never see them.

### 1.2 The pre-pull table (`ST.ROGUE.practice_prepulls`)

The APLs' `prepullActions` rows, keyed by family, each with the action, the
label, the spell, the offset in seconds relative to the pull (negative = before
it), the kind (`spell` = a cast the opener drill grades; `aura` = an aura
activation, which the drill never grades) and the APL citation.

| family | rows |
|---|---|
| SOD | `blood_fury` 20572 @ −1.5 s |
| ERA | `ar` 13750 @ −1 s (the imp-eneral-APL build; the plain Era APL carries no prepullActions) |
| TBC | `ar` 13750 @ −1 s |
| WRATH | `vanish_buff` 58426 @ −1 s (an **aura** activation — the name is UNCONFIRMED) |
| FOREVER | `bf` 13877 @ −2 s, `premeditation` 14183 @ −2 s, `stealth` 1787 @ −1 s (an aura) |

The class's practice ctx publishes the running family's first ready **cast**
row (`ctx.prepull_action` + `ctx.prepull_at`), and the engine's opener drill
grades that row at the APL's own mark. The TBC's behaviour is unchanged (the
shipped TBC Adrenaline Rush at −1 s).

### 1.3 The engine arms (`rogue_guide.lua`)

Every row with `engine = true` has a pure, family-gated arm:

| arm | families | the APL's condition |
|---|---|---|
| `vanish_verdict` | SOD, WRATH | SoD: NOT the Master of Subtlety aura (425096) AND cp == 5 AND Envenom castable. WotLK: NOT the 58426 aura. |
| `forever_opener_verdict` | FOREVER | the cluster in the APL's order: Ambush (i=1), Garrote (i=2), Preparation (i=5) |
| `premeditation_verdict` | FOREVER | cp <= 3 |
| `venom_verdict` | FOREVER | the 1310703 buff is down AND cp >= 3 |
| `poisoned_knife_verdict` | SOD | the target carries 4+ Deadly Poison stacks AND cp < 5 AND energy <= 80 |
| `hypersharp_verdict` | WRATH | filed (see §3) |
| `tricks_verdict` | WRATH | energy <= 50 |
| `killing_spree_verdict` | WRATH | energy <= 50 |
| `forever_paired_pop_verdict` | FOREVER | the Adrenaline Rush's time to ready is at/above 1.9 m (114 s) |

**The rule order** (the shipped rules keep their relative order; the new arms
slot into the house convention — upkeep first, the builder last):

```
0   unknown
1   expose            1a  TBC EA release        1x  the Forever opener cluster
1b  snd               1c  hfb                   1d  vanish (SOD / WRATH)
1e  poisoned_knife (SOD)                        2   shiv
3   envenom           3a  premeditation (FOREVER)   3b  venom (FOREVER)
4   dying dump        5   planned finisher
5b  ar                5c  bf      5d  coldblood
5e  hypersharp (WRATH) 5f tricks (WRATH)  5g killing_spree (WRATH)
5h  blood_fury (FOREVER) 5i elunes_light (FOREVER)
6   tea               7   pool-vs-spend
```

**The Forever opener cluster rides above the Slice and Dice upkeep** (the
Forever APL casts Ambush/Garrote/Vanish/Preparation at i=1/2/3/5 and its SnD
upkeep at i=18). Every other new arm rides in the upkeep or the cooldown
cluster.

### 1.4 The gather's reads (`classes/rogue.lua`)

**Only the running family's rows are read** — every utility row is family-gated,
so a client never pays for another client's rows. The reads are the existing
compat wrappers: `api.GetSpellCooldown` (through the class's own helper),
`api.scan_unit_aura` (through `utility_aura_present`), `api.is_spell_known`,
`api.IsSpellUsable`. **No new client API anywhere.**

The SoD reads Vanish, Envenom, Poisoned Knife and the 425096 aura; the WotLK
reads Vanish, Tricks, Killing Spree and the 58426 aura; the Forever client
reads the opener cluster, Premeditation, Venom, Blood Fury, Elune's Light and
the three auras (462707 / 1310703 / 11290) plus the Vanish and Adrenaline Rush
cooldowns. The Era and TBC clients read **nothing** new (their utility rows are
all builder rows).

---

## 2. The two flags, row by row (HU-13)

`live = false` means the line's read does not exist today, so the line cannot
be evaluated; the row names the exact read (or APL gate) in `needs`. Four rows
are filed:

| row | the read (or gate) it waits for |
|---|---|
| `vanish` (FOREVER) | the Garrote spell's **current energy cost** — the APL compares the energy with `spellCurrentCost(11290)`. compat.lua has no wrapper for a spell's energy cost, and a guessed constant is not a read. |
| `hypersharp` (WRATH) | a read that proves the enchant is **not applied yet** — the enchant spell reads off cooldown forever once it is applied, so `api.GetSpellCooldown` cannot tell "pending" from "already applied". |
| `gnome_eureka` (FOREVER) | the Adrenaline Rush's **known-vs-on-cooldown split** (the class's `ar_ready` cannot tell them apart), the Adrenaline Rush's **buff aura** (13750) and the Gnome Eureka's **base cooldown** (`api.GetSpellBaseCooldown` on 1259812). |
| `backstab` (TBC) | the APL's own **"Use Backstab" gate** — a `const false` on the TBC build (the row cannot fire there at all). |

---

## 3. Where the gap analysis is wrong (nine corrections)

1. **1857 is VANISH RANK 2 on the TBC and Forever clients — not Cloak of
   Shadows.** `wowsims/tbc-new sim/rogue/spell_data_auto_gen.go`: `Vanish:
   Ranked(1856, 1857, 26889)`; `wowsims/forever`: `Vanish: spelldata.Ranked(1856,
   1857)`. The TBC client's generated data has no `CloakOfShadows` field at all
   (the spell was removed in 2.3). The gap's `cloak_of_shadows` row is refuted;
   the Forever APL's i=3/i=4 rows are **Vanish** (the "Use Stealth/Vanish for
   Damage" context and the i=5 Preparation row, which prepares *while Vanish is
   not ready*, agree).
2. **14183 is PREMEDITATION on the Forever client — not Shadowstep.**
   `wowsims/forever sim/rogue/spell_data_auto_gen.go`: `Premeditation:
   spelldata.Ranked(14183)`. The Forever APL's i=17 (`castSpell 14183` while
   `cp <= 3`) is the combo-point opener, not a Shadowstep.
3. **1241584 is MUTILATE RANK 4 on the Forever client — not Shadowstep.**
   `Mutilate: spelldata.Ranked(1310707, 399956, 1241582, 1241584)`. The Forever
   APL's i=26 is a builder row (its condition is the same builder chain as
   i=24/i=25/i=27).
4. **26867 is RUPTURE on the TBC client — not Deadly Poison.** `Rupture: Ranked(
   1943, 8639, 8640, 11273, 11274, 11275, 26867)`; the TBC APL's i=7 is the
   Rupture row (`NOT(dotIsActive(26867))`). The TBC APL casts no Deadly Poison
   at all — the Shiv (5938) applies it (27187, the TBC sim's `rogue.DeadlyPoison`).
   The gap's `deadly_poison` row is refuted.
5. **51662 is HUNGER FOR BLOOD on the WotLK client — not Mutilate.** The WotLK
   mutilate APL's i=12 casts **48666** (`wowsims/wotlk sim/rogue/mutilate.go`:
   `var MutilateSpellID int32 = 48666`), and its i=3 casts 51662 with
   `auraRemainingTime(51662) <= 1s` — the Hunger for Blood upkeep the shipped
   `hfb` row already plays.
6. **The Era and TBC APLs carry no Vanish row at all.** The Era APLs have 5 and
   7 rows, the TBC APL 17 — none of them casts 1856/1857/26889. The gate is
   SoD + WotLK (+ the Forever rank 2).
7. **1259799 is "Elune's Light"** — the Forever **druid** APL's own variable
   (`"Elune's Light now"` → `castSpell 1259799`,
   `wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json`) — and
   1259812 is **"Gnome Eureka"** (the rogue APL's own variables "Gnome Eureka -
   Should Cast" and "Gnome Eureka - Active or Not Ready"). The gap called
   1259812 "Gnome Eureka" (right) and 1259799 UNCONFIRMED (now named).
8. **1310703 is VENOM on the Forever client** (`Venom: spelldata.Ranked(1310703)`)
   — not an "Expose" row and not UNCONFIRMED. The gap's `expose_forever` row is
   refuted and renamed.
9. **14278 is GHOSTLY STRIKE on the Forever client** (`GhostlyStrike:
   spelldata.Ranked(14278)`) — the gap's "Subtlety talent id, UNCONFIRMED".
10. (bonus) **The Forever APL's `valueVariables` are CONSTANTS**, not
    sim-computed states: `Use Stealth/Vanish for Damage` = true,
    `Use Ambush Opener` = false, `Use Backstab` = true, `Use Expose Armor` =
    false. So every Forever row is a plain client read — the "stealth for
    damage" state the gap assumed was missing is a constant. The TBC's own
    `Use Backstab` = **false** → the TBC's Backstab row (i=11) is dead on that
    build, and the Forever's Hemorrhage row at i=27 is dead (its `Use Backstab`
    disjunct is true) while i=24 lives.

---

## 4. The divergences this lane leaves on the table (filed, not fixed)

* **The engine's upkeep-first spine is not the literal APL order.** The SoD
  APL casts Poisoned Knife (i=5) *above* its Slice and Dice upkeep (i=6); the
  engine's SnD rule (1b) sits above the Poisoned Knife arm (1e). Re-cutting the
  shipped rule order is out of scope (the order is a documented contract) — and
  the two rows rarely collide (the SoD SnD needs cp >= 4, the Poisoned Knife
  window cp < 5).
* **The WotLK's new pops can be shadowed by a ready Adrenaline Rush.** The
  combat APL puts Tricks (i=13) and Killing Spree (i=14) *above* its
  Adrenaline Rush (i=15); the engine's shipped order puts AR (5b) first. The new
  pops therefore ride at 5f/5g, behind AR and Blade Flurry. The AR/BF order was
  already out of APL order before this lane (the combat APL has BF at i=9); the
  lane did not re-cut it.
* **The Forever's Premeditation (i=17) sits below the Slice and Dice upkeep
  (i=18) in the engine.** Same cause, same filed status.
* **The guide's slot contract is frozen (11 slots).** The new actions are
  slot-less, exactly like the shipped SnD / AR / Blade Flurry / Cold Blood /
  Hunger for Blood rows: the rotation label names them
  (`ACTION_FALLBACK_NAMES`), no icon lights.

## 5. The default-visible change (stated plainly)

* **The guide can now prompt the new utility actions** (Vanish, Ambush,
  Garrote, Preparation, Premeditation, Venom, Poisoned Knife, Tricks of the
  Trade, Killing Spree, Blood Fury, Elune's Light) — each one only when its
  APL condition is fully proven. Unreadable state hides (unknown-hides).
* **The practice panel's button row grows** by the live engine-facing utility
  rows (the row's height follows its button lines — `practice_ui.lua`'s
  `practice_row_set_height`). The builder rows and the filed rows stay out.
* **The opener drill now grades the family's pre-pull row** (the TBC's own
  behaviour is unchanged).

## 6. Validation

| check | result |
|---|---|
| `tests/rogue_state.lua` | **PASS — 922 checks** (818 before this lane; +104 new) |
| `tests/rogue_guide_state.lua` | **PASS — 896 checks** (776 before; +120 new) |
| full harness (`bash tests/run.sh`) | **41 steps, 0 failed** |
| luacheck | **2 warnings / 0 errors in 83 files** (the floor; the four files this lane touched: 0 warnings) |
| line endings | `classes/rogue.lua` and `rogue_guide.lua` stay pure CRLF; the two test files stay pure LF |
| mutation proofs (`/tmp/opencode` copies) | **24 / 24 killed** (`python3 /tmp/opencode/mutations_rogue_apl.py`) |

The mutation set (each applied to a `/tmp/opencode` copy of the tree): the seven
family-split ids reverting (the Forever Vanish 1857, Premeditation 14183 and
Mutilate 1241584, the TBC/Forever Hemorrhage pair, the SoD/Wrath Vanish pair),
**the four "buff-up line still prompts" mutants** (the Master of Subtlety gate,
the 58426 gate, the Venom buff gate and the Garrote dot gate removed — the
SoD/Wrath/Forever arms would prompt while the buff they wait on is up), the
Tricks energy gate, the Poisoned Knife stack gate, the Preparation gate, the
SOD family gate widened, the Vanish family gate, the engine filter removed, the
live filter removed, a filed row claiming `live = true`, a filed row's `needs`
dropped, the TBC pre-pull's offset, the Forever pre-pull's kind, the gather's
family gate and the gather reading every family.

---

## Update (2026-10-20, later the same day) — the four filed rows are closed

Desk `rogue-apl-reads` closed the four `live = false` rows this file filed in
§2: the **Forever Vanish** and the **Forever Gnome Eureka** are WIRED (the
Garrote's energy cost and the racial's three readable disjuncts), the **WotLK
Hypersharp** row's filed reason and name are corrected (54758 is "Hyperspeed
Acceleration", the belt enchant's effect - not a permanent enchant) and its
dead arm is removed, and the **TBC Backstab** stays honestly off (its gate is
the APL's build CONSTANT, not a client-side state). Two name corrections land
with it (1259812 is the Gnome racial "Eureka!", not "Gnome Eureka").

The full record: `bench/rogue_apl_residual_reads_2026-10-20.md`. This file's
§1 (what landed), §4 (the divergences) and §5 (the default-visible change)
still stand; §5's "the guide can now prompt the new utility actions" now also
covers the Forever Vanish and the Eureka! racial.
