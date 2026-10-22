# Rotation gap vs the wowsims APLs — 2026-10-20

Desk: `rotation-gap`. **Read-only** across the addon tree. The only file this desk
wrote is this one (`bench/rotation_gap_vs_apl_2026-10-20.md`, verified absent by
glob before writing). No addon file, no test file, no other bench file, no git.

> **Later writer.** Desk `corpus-corrections` edited this file on **2026-10-20**
> (the corrections pass) — it wrote §0.0, §9 and the in-place corrections, and
> touched nothing else in the workshop (no `.lua`, no test, no `desks/`, no
> `hands-up.md`, no git). The original `rotation-gap` text below is otherwise
> as written on 2026-10-20.

**The question the operator asked:** a rotation table that only carries the damage
abilities is not the class's rotation. The warrior table carries
op/execute/slam/bt/ww/ms/… and no utility set. This desk checked all six classes
the same way and produced, per class: the shipped action keys, the APL priority
list with citations, the missing-line specs (name + id per family, family gate,
APL position, probe requirement), and the lines that are **correctly absent**.

> **⚠ CORRECTED 2026-10-20.** The five utility-layer build lanes disproved
> **31 ids/names/gates** in this file. Every correction is applied **in place**
> and listed with its old value and its evidence in **§0.0 CORRECTION LOG**
> below; the summary of what changed is in **§9**. A superseded value is never
> silently overwritten — it is marked **SUPERSEDED 2026-10-20** in place.

---

## 0.0 CORRECTION LOG — 2026-10-20 (desk `corpus-corrections`)

**Parts of this file are superseded.** The five utility-layer build lanes
(`warrior-apl` + `warrior-utility-live`, `hunter-apl` + `hunter-utility-live`,
`rogue-apl`, `druid-apl`, `shaman-apl`) re-fetched every APL file and every
sim spell table out of the wowsims sources on 2026-10-20 and **disproved a
number of ids and names this file carries**. The corrections are applied
**in place** below — so a reader cannot copy a wrong id out of a table — and
each one is listed here with its **old value**, its **corrected value** and
the **evidence**. Nothing else in the file was rewritten; the APL priority
listings, the probe bill and the "correctly absent" lists stand as written.

The five build artifacts are the evidence of record:
`bench/warrior_apl_utility_build_2026-10-20.md`,
`bench/warrior_apl_utility_live_2026-10-20.md`,
`bench/hunter_apl_utility_build_2026-10-20.md`,
`bench/hunter_utility_live_2026-10-20.md`,
`bench/rogue_apl_utility_build_2026-10-20.md`,
`bench/druid_apl_utility_build_2026-10-20.md`,
`bench/shaman_apl_utility_build_2026-10-20.md`.

### Shaman

| # | old claim in this file | corrected | evidence |
|---|---|---|---|
| S1 | 17364 = "**Nature's Wrath**" (§5.1 prose, §5.2 Era i=4, §5.3 `nature_wrath`, §5.4, §5.5, §7.2) | 17364 = **Stormstrike** on every family. **No wowsims shaman sim has a Nature's Wrath ability at all** (no `nature_wrath.go` in classic/sod/tbc-new/forever/wotlk) | `shaman_apl_utility_build_2026-10-20.md` §2 **C1** — `wowsims/classic sim/shaman/stormstrike.go:20` (`ActionID{SpellID: 17364}`); `bench/verify_bank.md` (17364 = Stormstrike, CONFIRMED); `Libs/LibClassicDurations/classAbilities.lua:754` |
| S2 | 29228 = the "**Flametongue Weapon**" id (§5.2 SoD i=9 / Forever i=10, §5.3 `flametongue` + `flametongue_weapon`, §5.4, §7.2) | 29228 = **Flame Shock rank 6**. The Flametongue **Totem** is 16387 (r4) and it is a **pre-pull** row | `shaman_apl_utility_build_2026-10-20.md` §2 **C2** — `wowsims/forever sim/shaman/spell_data_auto_gen.go`: `FlameShock: spelldata.Ranked(8050, 8052, 8053, 10447, 10448, 29228)`; `FlametongueTotem: Ranked(8227, 8249, 10526, 16387)` |
| S3 | 49231 = "**Lightning Shock**" (§5.2 WotLK i=8) | 49231 = **Earth Shock**; 49233 = Flame Shock (the dot); 49236 = **Frost Shock**. The WotLK APL has no Lightning Shock row at all | `shaman_apl_utility_build_2026-10-20.md` §2 **C3** — `wowsims/wotlk sim/shaman/shocks.go:52,62,115` |
| S4 | 10497 = the "**Rockbiter Weapon**" id (§5.3 `rockbiter`) | 10497 = **Mana Spring Totem rank 4**. Neither the SoD nor the Forever APL pre-pull carries a Rockbiter row | `shaman_apl_utility_build_2026-10-20.md` §2 **C4** — `wowsims/classic sim/shaman/water_totems.go` `ManaSpringTotemSpellId = {0, 5675, 10495, 10496, 10497}` |
| S5 | 8512 is "the TBC air-slot totem" and the shipped id is "stale against the sim" (§5.5) | 8512 is a real **Windfury Totem rank-1** id (the client's rank-1 fallback), so the shipped row is not wrong — but the **TBC APL's own air-slot rows cast 25587 r5 (Windfury) / 25359 r3 (Grace of Air)**. Filed, not changed | `shaman_apl_utility_build_2026-10-20.md` §2 **C5** — `wowsims/forever sim/shaman/spell_data_auto_gen.go` `WindfuryTotem: Ranked(8512, 10613, 10614)` |

### Rogue

| # | old claim in this file | corrected | evidence |
|---|---|---|---|
| R1 | 1857 = "**Cloak of Shadows**" (§3.2 Forever i=3,4; §3.3 `cloak_of_shadows`; §3.4) | 1857 = **Vanish rank 2** on the **TBC and Forever** clients. The Forever APL's i=3/4 rows are **Vanish**; the TBC client's generated data has **no `CloakOfShadows` field at all** (the spell was removed in 2.3) | `rogue_apl_utility_build_2026-10-20.md` §3.1 — `wowsims/tbc-new sim/rogue/spell_data_auto_gen.go`: `Vanish: Ranked(1856, 1857, 26889)`; `wowsims/forever`: `Vanish: spelldata.Ranked(1856, 1857)` |
| R2 | 14183 = "**Shadowstep**" on Forever (§3.2 i=17, §3.3 `shadowstep`, §3.4) | 14183 = **Premeditation** — on Era/SoD/Wrath *and* on **Forever**. The Forever APL's i=17 (`castSpell 14183` while `cp <= 3`) is the combo-point opener | `rogue_apl_utility_build_2026-10-20.md` §3.2 — `wowsims/forever sim/rogue/spell_data_auto_gen.go`: `Premeditation: spelldata.Ranked(14183)` |
| R3 | 1241584 r4 = "**Shadowstep rank**" (§3.2 i=26, §3.3, §7.4) | 1241584 = **Mutilate rank 4** on the Forever client | `rogue_apl_utility_build_2026-10-20.md` §3.3 — `Mutilate: spelldata.Ranked(1310707, 399956, 1241582, 1241584)` |
| R4 | the `vanish` line is gated **Era, SoD, TBC, WotLK** (§3.3) | the **Era and TBC APLs carry no Vanish row at all** (5 / 7 / 17 rows; none casts 1856/1857/26889). The gate is **SoD + WotLK + (Forever, rank 2)** | `rogue_apl_utility_build_2026-10-20.md` §3.6 |
| R5 | 26867 = "**Deadly Poison**" on TBC (§3.3 `deadly_poison`, §3.4) | 26867 = **Rupture** on the TBC client. The TBC APL casts **no Deadly Poison at all** — the Shiv (5938) applies it | `rogue_apl_utility_build_2026-10-20.md` §3.4 — `Rupture: Ranked(1943, 8639, 8640, 11273, 11274, 11275, 26867)` |
| R6 | 51662 = "**Mutilate**" (WotLK) (§3.3 `mutilate`) | 51662 = **Hunger for Blood** on the WotLK client. The mutilate APL's i=12 casts **48666** (Mutilate) and its i=3 casts 51662 with `auraRemainingTime(51662) <= 1s` | `rogue_apl_utility_build_2026-10-20.md` §3.5 — `wowsims/wotlk sim/rogue/mutilate.go` `var MutilateSpellID int32 = 48666` |
| R7 | 1310703 = "the Forever **Expose**", UNCONFIRMED (§3.2 i=19, §3.3 `expose_forever`, §7.4) | 1310703 = **Venom** on the Forever client | `rogue_apl_utility_build_2026-10-20.md` §3.8 — `Venom: spelldata.Ranked(1310703)` |
| R8 | 1259799 UNCONFIRMED; 1259812 "Gnome Eureka" (§3.3 `blood_fury_pair`, §7.4) | 1259799 = **"Elune's Light"**; 1259812 = **"Gnome Eureka"** (both from the Forever APLs' own variables) | `rogue_apl_utility_build_2026-10-20.md` §3.7 — `wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json` `castSpell 1259799` under the variable "Elune's Light now"; the rogue APL's own "Gnome Eureka - Should Cast" |
| R9 | 14278 = "Subtlety talent id, UNCONFIRMED" (§3.2 i=23) | 14278 = **Ghostly Strike** on the Forever client | `rogue_apl_utility_build_2026-10-20.md` §3.9 — `GhostlyStrike: spelldata.Ranked(14278)` |

### Druid

| # | old claim in this file | corrected | evidence |
|---|---|---|---|
| D1 | 9850 = "**Mangle**" on TBC/Forever (§4.3 `shred_claw` + `mangle_cat`, §7.2) | 9850 = **Claw r5** on **Era, TBC and Forever alike**. The **Forever client has no Mangle spell at all** (no spell table, no per-ability file); the Mangle (Cat) ids are 33876 / 33983 / 33987 on TBC | `druid_apl_utility_build_2026-10-20.md` §5.1 — `wowsims/classic sim/druid/claw.go:14`; `tbc-new` Claw table (9850 r5); `forever` Claw ladder (…, 9850) |
| D2 | the Era APL's `[1]` row = "**13494 Faerie Fire (Feral)**" (§4.2, §4.3 `leader_of_the_pack`, §4.5) | the 1.15 client names **13494 "Haste"** (it is in no druid skill line); the client's **Leader of the Pack is 17007** (the Feral Combat skill line). The APL row casts Haste, so it is dead as written | `druid_apl_utility_build_2026-10-20.md` §5.2 — the Classic 1.15 client's own `Spell.csv` / `SkillLineAbility.csv` |
| D3 | the Era APL has a Rip row (§4.3 `ripe`, "Era i=?") | the Era APL has **no Rip row at all** (its rows: the Faerie Fire, the Leader of the Pack, the Ferocious Bite, the Shred, the Claw, the Innervate, the Cat Form) | `druid_apl_utility_build_2026-10-20.md` §5.3 |
| D4 | the Forever `mangle` row's citation `apl_sweep_test.go: mangleNow` (§4.3) | the Forever repo has **no `mangleNow`** — the Forever druid sim carries no Mangle (no spell table, no per-ability file, no mention in `feral.go` / `feralcat/*.go`) | `druid_apl_utility_build_2026-10-20.md` §5.4 |

### Hunter

| # | old claim in this file | corrected | evidence |
|---|---|---|---|
| H1 | WRATH `kill_shot` = 53351 (§2.1, §2.5) | the WotLK APLs cast **61006**; 53351 is the client's rank-1 (the guide slot's fallback) | `hunter_apl_utility_build_2026-10-20.md` §3 — `wowsims/wotlk sim/hunter/kill_shot.go:12` |
| H2 | WRATH `explosive` = 53301 (§2.1, §2.5) | the SV APL casts the LnL-downrank pair **60053 / 60052**; 53301 is the client's rank-1 | `hunter_apl_utility_build_2026-10-20.md` §3 — `wowsims/wotlk sim/hunter/explosive_shot.go:21,25` |
| H3 | TBC `steady` = 56641 (§2.1) | the TBC APL casts **34120 r1**; 56641 is the **WotLK** Steady Shot rank-1 and **does not exist on the TBC client** | `hunter_apl_utility_build_2026-10-20.md` §3 — wowhead TBC 56641: no such spell |
| H4 | FOREVER `steady` = 56641 (§2.1) | the **Forever client has no Steady Shot at all** (the spell arrived in 2.3; the Forever spell data carries no `SteadyShot` table). The Forever rotation row was **removed** by the live lane | `hunter_apl_utility_build_2026-10-20.md` §3; `hunter_utility_live_2026-10-20.md` §1 ("the Forever Steady Shot row is GONE") |
| H5 | 61847 = "**Aspect of the Wild**" (§2.2, §2.3 `aspect_wild`, §2.4) | 61847 = **Aspect of the Dragonhawk** (the WotLK client renamed the Wild aspect) | `hunter_apl_utility_build_2026-10-20.md` §2/§5.3 — `wowsims/wotlk sim/hunter/aspects.go:32-34` |
| H6 | the Era pre-pull 25296 = "**Aspect of the Cheetah**" (§2.2) | 25296 = **Aspect of the Hawk** (the Cheetah is 5118) | `hunter_apl_utility_build_2026-10-20.md` §5.5 |
| H7 | the Forever Hawk is a **rotation** line (§2.3 `aspect_hawk`) | in the Forever APL the Hawk is a **pre-pull** row (`prepullActions` i=1), so under HU-12 it stays in the pre-pull table and is not a rotation row | `hunter_apl_utility_build_2026-10-20.md` §5.4 |
| H8 | `kill_shot` ids "14287 (SoD/TBC/Forever)" (§2.3) | 14287 is **Arcane Shot r8**; the SoD's Kill Shot is the rune **409593** (`proto/hunter.proto:153`), and the TBC and Forever APLs cast **no Kill Shot at all** | `hunter_apl_utility_build_2026-10-20.md` §5.1 |
| H9 | the Era APL's i=3 = Arcane Shot (§2.3 `arcane_shot`) | the Era APL's i=3 is **Multi Shot 25294**; the Era APL has **no** Arcane Shot row | `hunter_apl_utility_build_2026-10-20.md` §5.2 |

### Warrior

| # | old claim in this file | corrected | evidence |
|---|---|---|---|
| W1 | 18499 = "Improved Hamstring" (the shipped `hamstring` row's citation) — this file already flagged it in §7.3 | 18499 = **Berserker Rage** (`classic sim/warrior/berserker_rage.go:14`); 20500 is the Improved Hamstring **buff** the APL only tests for. The wrong claim lives in `bench/warrior_practice_2026-10-19.md` and `bench/class_features_drills_2026-10-19.md` — both corrected there | `warrior_apl_utility_build_2026-10-20.md` §1/§4 |
| W2 | Sweeping Strikes ids "**12292 / 12723 (TBC)**" (§1.3) | 12292 is **Death Wish on TBC** *and* **Sweeping Strikes on the Forever client**; both APLs cast **12723** | `warrior_apl_utility_build_2026-10-20.md` §4.1 — `wowsims/tbc-new sim/warrior/talents_arms.go:314`; `wowsims/forever sim/warrior/spell_data_auto_gen.go:262` `SweepingStrikes: 12292` |
| W3 | "the TBC id is a **different spell** (33697 = Blood Fury, TBC rank)" (§1.3) | 33697 is **Blood Fury rank 2** (20572 is rank 1) — a rank of the same spell, not a different one | `warrior_apl_utility_build_2026-10-20.md` §4.5 — `wowsims/tbc-new sim/core/racials.go:196`; `wowsims/classic sim/core/racials.go:78` |
| W4 | 25212 carries the "**Devastate**" name in the corpus (`bench/warrior_practice_2026-10-19.md`, `bench/class_features_drills_2026-10-19.md`, `bench/filed_closure_sweep_2026-10-19.md`) | **25212 is the TBC Hamstring**, not Devastate. This file's own §0.3 already said so; the three corpus files carried the wrong name and are corrected there | `warrior_apl_utility_build_2026-10-20.md` §1 (the TBC APL's i=19 = 25212 = Hamstring) |

**Not corrected — recorded as still open.** §6 (the paladin) was not
re-verified: the paladin utility lane has not run, so every paladin id in
this file stands as written. The §7.4 UNCONFIRMED list is also re-scoped
below (four of its ids are now named, so they move out of "must not be built
on without a source" into the confirmed set — the *client* confirmation is
still owed).

---

## 0. Method, tooling log, and how to read the citations

### 0.1 What was fetched (all 2026-10-20, all CONFIRMED fetched)

| Repo | Branch | APL files read |
|---|---|---|
| `wowsims/classic` | `master` | `ui/warrior/apls/dps_no_reck.apl.json`, `ui/hunter/apls/p1.apl.json`, `ui/rogue/apls/combat_sinister_strike.apl.json` + `…_iea.apl.json`, `ui/feral_druid/apls/feral.apl.json`, `ui/enhancement_shaman/apls/default.apl.json`, `ui/retribution_paladin/apls/basic_ret.apl.json` |
| `wowsims/sod` | `master` | `ui/warrior/apls/phase_6_dw.apl.json`, `ui/hunter/apls/p7_weave.apl.json`, `ui/rogue/apls/P5_Saber.apl.json`, `ui/feral_druid/apls/phase_5.apl.json` (there is **no** `phase_6` druid APL in this repo — the tree ends at `phase_5`), `ui/enhancement_shaman/apls/phase_6.apl.json`, `ui/retribution_paladin/apls/p8-twist.apl.json`, `p8-exodin.apl.json`, `p8-stack.apl.json`, `p8-shockadin-1h.apl.json`, `p8-wrath.apl.json` |
| `wowsims/tbc-new` | `master` | `ui/specs/warrior/dps/apls/fury.apl.json` + `arms.apl.json`, `ui/specs/hunter/dps/apls/default.apl.json`, `ui/specs/rogue/dps/apls/swords.apl.json`, `ui/specs/druid/feralcat/apls/default.apl.json`, `ui/specs/shaman/enhancement/apls/default.apl.json`, `ui/specs/paladin/retribution/apls/default.apl.json` |
| `wowsims/forever` | `master` | `ui/specs/warrior/dps/apls/fury.apl.json` + `arms.apl.json`, `ui/specs/hunter/dps/apls/default.apl.json`, `ui/specs/rogue/dps/apls/default.apl.json`, `ui/specs/druid/feralcat/apls/default.apl.json`, `ui/specs/shaman/enhancement/apls/default.apl.json`, `ui/specs/paladin/retribution/apls/twist_of_light.apl.json` + `holy_shock.apl.json` |
| `wowsims/wotlk` | `master` | `ui/warrior/apls/arms.apl.json` + `fury.apl.json`, `ui/hunter/apls/mm.apl.json` + `sv.apl.json`, `ui/rogue/apls/combat.apl.json` + `mutilate.apl.json`, `ui/feral_druid/apls/default.apl.json`, `ui/enhancement_shaman/apls/default_wf.apl.json`, `ui/retribution_paladin/apls/default.apl.json` |

The WotLK repo was **not** in the earlier per-class rotation audits
(`bench/paladin_rotation_audit_2026-10-19.md:8-9`: "Wrath/Titanforge and
Retail/Cata/Mists have no sim among the in-scope repos"). It exists now, and it
changes two of the six answers — see §1.5 and §6.3.

### 0.2 How the priority list was extracted

The APL JSON has two shapes. The old shape (`wowsims/classic`) is
`{"type":"TypeAPL","priorityList":[…]}` with `action.castSpell.spellId` and
`action.condition`. The new shape (`sod`, `tbc-new`, `forever`, `wotlk`) is the
same `priorityList` but adds `groups` (named blocks) and `prepullActions`. A
`groupReference` action is a pointer into `groups[].actions`; **every group was
expanded inline** so the list below is the full priority order, not the
group-stub order. `wowsims/classic` has no `groups` key at all.

`[i]` in the tables below is the index in `priorityList` (group members keep
their own index inside the group, written `16.g.1`).

### 0.3 How spell names were resolved (and one trap)

Names come from **the sim's own spell data**, not from memory:

* `wowsims/tbc-new sim/<class>/spell_data_auto_gen.go` — the generated
  `shared.SpellDataTable` blocks, parsed for `SpellID:` → field name.
* `wowsims/forever sim/<class>/spell_data_auto_gen.go` — the same, `spelldata.Ladder` blocks.
* `wowsims/<repo> sim/<class>/<spell>.go` — the per-ability file; the file name
  plus the `core.ActionID{SpellID: N}` line is the citation.

**The trap:** a spell id is **not** the same spell in every client build, and
Wowhead's version paths disagree with the sim when the id was reused. Worked
examples, all confirmed in this session:

* `25289` is **Battle Shout** (an older rank) in the TBC/Forever client — not
  Berserking. `wowsims/tbc-new sim/warrior/spell_data_auto_gen.go` (BattleShout
  table, rank 7 = `SpellID: 25289`, rank 8 = `SpellID: 2048`).
* `25212` is **Hamstring** in TBC, not Shockwave. (Also not "Devastate" —
  see §0.0 **W4**; the corpus files that call it Devastate are corrected
  there.)
* `26865` is **Eviscerate** in TBC, not Shiv (`wowsims/tbc-new sim/rogue/eviscerate.go:8`).
* `14183` is **Premeditation** in Era/SoD/Wrath **and on Forever**
  (`wowsims/classic sim/rogue/premeditation.go:14`;
  `wowsims/forever sim/rogue/spell_data_auto_gen.go`:
  `Premeditation: spelldata.Ranked(14183)`) — it is *not* Shadowstep on any
  client (§0.0 **R2**).
* `20375` is **Seal of the Crusader** in Era/SoD and **Seal of Command** in TBC.
* `9850` is **Claw r5** on Era, TBC *and* Forever alike
  (`wowsims/classic sim/druid/claw.go:14`; the `tbc-new` Claw table's r5;
  the `forever` Claw ladder) — it is **not** Mangle on TBC/Forever, and the
  **Forever client has no Mangle spell at all** (§0.0 **D1**).
* `17364` is **Stormstrike** on every family — there is no Nature's Wrath
  in any wowsims shaman sim (§0.0 **S1**).
* `29228` is **Flame Shock r6** — not the Flametongue Weapon (§0.0 **S2**).
* `49231` is **Earth Shock** on WotLK (49233 = Flame Shock, 49236 = Frost
  Shock) (§0.0 **S3**).
* `12292` is **Death Wish on TBC** and **Sweeping Strikes on the Forever
  client** (§0.0 **W2**).
* `1857` is **Vanish rank 2** on TBC/Forever — there is no Cloak of Shadows
  on either client (§0.0 **R1**).

Anything this desk could not name from a sim source is written **UNCONFIRMED**
in caps. No id is guessed.

### 0.4 What "the shipped rotation table" means per class

| Class | Shape | Where |
|---|---|---|
| Warrior | one flat array, each entry carries `families` | `classes/warrior.lua:3636-3746` |
| Hunter | a per-family map `ST.HUNTER.PRACTICE_ROTATIONS[family]`, plus a separate `ST.HUNTER.PRACTICE_PREPULLS` | `classes/hunter.lua:2815-2906` (rotations), `:2921-2955+` (prepulls) |
| Rogue | one flat array, each entry carries `families` | `classes/rogue.lua:2174-2271` |
| Druid | one flat array, each entry carries `family` (+ a separate `BEAR` slice) | `classes/druid.lua:2826-2950` |
| Shaman | one flat array, each entry carries `families` | `classes/shaman.lua:4116-4189` |
| Paladin | **built** from `ST.PALADIN.practice_orders` = the twist order + the five FCFS tables published by `nextaction.lua` | `classes/paladin.lua:4146`, `:4173-4213`; `nextaction.lua:953-982` |

### 0.5 Probe vocabulary used in the specs

Every probe below is an **existing `compat.lua` wrapper** — no missing-line spec
needs a new client API, so no `wow-ui-source` branch/line is required for a
probe to be buildable. The wrappers that carry the reads:

| Probe | Wrapper | Where |
|---|---|---|
| spell cooldown | `api.GetSpellCooldown(spell)` → `start, duration, enabled, modRate` (0,0,0,0 on a secret read) | `compat.lua:229-254` |
| spell known | `api.is_spell_known(spell_id)` | `compat.lua:208-216` |
| spell name | `api.GetSpellInfo(spell)` | `compat.lua:163`, `:173` |
| player's own buff | `api.scan_player_aura(predicate)` → `remaining_seconds, stacks` (nil = unknown/absent) | `compat.lua:514-543` |
| target's debuff | `api.scan_unit_aura(unit, predicate, filter)` | `compat.lua:569` |
| raw aura row | `api.UnitAura(unit, index, filter)` | `compat.lua:457`, `:468`, `:485` |
| resource | `api.UnitPower(unit, power_type)` | `compat.lua:349` |
| spell usable | `api.IsSpellUsable(spell)` → `usable, insufficientPower` | `compat.lua:277` |
| target distance | `api.CheckInteractDistance(unit, index)` / `api.UnitDistance(unit)` | `compat.lua:917`, `:942` |
| per-family id resolution | `api.get_family_spell_id(id_table)` / `…_state` / `api.get_spell_query(name, id)` | `compat.lua:1533`, `:1495`, `:1544` |
| totem clock | `api.GetTotemInfo(slot)` | `compat.lua:1194` |

Client-API availability, cited from `/home/sam/wow-ui-source` (branch:file:line):

* `GetSpellCooldown` — `classic_era:Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua:108`; `classic_anniversary:` same file `:108`; `classic_titan:` same file `:108`; `origin/forever:` same file `:309`.
* `GetSpellInfo` — `classic_era:` `SpellDocumentation.lua:190`; `classic_anniversary:` `:190`; `classic_titan:` `:190`; `origin/forever:` `:416`.
* `UnitAura` — `classic_era:` `UnitAuraDocumentation.lua:477`; `classic_anniversary:` `:477`; `classic_titan:` `:477`; `origin/forever:` `:641`.
* `IsSpellKnown` — `classic_era:` `SpellBookDocumentation.lua:82`; `classic_anniversary:` `:82`; `classic_titan:` `:82`; `origin/forever:` `:738`.

---

## 1. WARRIOR

### 1.1 Shipped rotation table — current action keys

`classes/warrior.lua:3636-3746`, in shipped order, with the entry's own
`families` field:

| # | action | label | families | line |
|---|---|---|---|---|
| 1 | `op` | Overpower window | ERA, TBC | :3637 |
| 2 | `execute` | Execute below 20 % | ERA, TBC, WRATH | :3651 |
| 3 | `slam` | Bloodsurge Slam | WRATH, ERA | :3662 |
| 4 | `sunder` | Sunder upkeep | TBC, FOREVER | :3670 |
| 5 | `rend` | Rend upkeep | WRATH, ERA | :3678 |
| 6 | `bt` | Bloodthirst | ERA, TBC, WRATH | :3686 |
| 7 | `ww` | Whirlwind | ERA, TBC, FOREVER | :3694 |
| 8 | `raging_blow` | Raging Blow | ERA (SoD rune) | :3702 |
| 9 | `bladestorm` | Bladestorm | WRATH | :3709 |
| 10 | `ms` | Mortal Strike | WRATH | :3716 |
| 11 | `hamstring` | Hamstring weave | ERA, TBC | :3723 |
| 12 | `hs` | Heroic Strike dump | (no `families` = every family) | :3731 |
| 13 | `cleave` | Cleave dump | ERA, TBC | :3739 |

**13 keys. Every one of them is a damage or a debuff-upkeep ability.** There is
no stance, no shout, no rage tool, no racial, no cooldown-pop.

### 1.2 APL priority list, per family

**ERA — `wowsims/classic ui/warrior/apls/dps_no_reck.apl.json`**

| i | cast | name (source) |
|---|---|---|
| 0 | 11597 r5 | Sunder Armor (`tbc-new sim/warrior/spell_data_auto_gen.go`, SunderArmor table) |
| 1 | item 10646 | engineering trinket |
| 2 | item 18641 | engineering trinket |
| 3 | 12328 | **Death Wish** (`classic sim/warrior/talents.go:407` + `Label: "Death Wish"` :410) |
| 4 | 1719 | Recklessness (`classic sim/warrior/recklessness.go:16`) — condition `false`, i.e. the Fury build does not take it |
| 5 | 1719 | Recklessness — `[HIDE]`, `remainingTime <= 15s` |
| 6 | other | `OtherActionPotion` (Bloodlust) |
| 7 | 20572 | Blood Fury (Orc racial) |
| 8 | 24427 | **Diamond Flask** (`classic sim/warrior/items.go:25` — `NewTemporaryStatsAura("Diamond Flask", core.ActionID{SpellID: 24427}, …)`) |
| 9 | item 21180 | Strength Potion (item use) |
| 10 | 29602 | **Jom Gabbar** (the Horde Strength Potion item use; Wowhead `/classic/` id) |
| 11,12 | item 23041 | engineering trinket |
| 13 | — | `autocastOtherCooldowns` (the sim's own ability-pop layer) |
| 14 | 1680 | Whirlwind (targets > 1) |
| 15 | 20662 r5 | Execute (E20) |
| 16 | 23894 r4 | Bloodthirst |
| 17 | 1680 | Whirlwind (TTR(BT) > 1.5 s) |
| 18 | 25286 r8 | Heroic Strike |
| 19 | 20569 r5 | Cleave |
| 20 | 7373 r3 | Hamstring |
| 21 | 2687 | **Bloodrage** (`classic sim/warrior/bloodrage.go:10`) |
| 22 | 18499 | **Berserker Rage** (`classic sim/warrior/berserker_rage.go:14`) `[HIDE]` |
| 23 | 25289 r6 | **Battle Shout** (older rank) |
| 24 | 2458 | **Berserker Stance** (`classic sim/warrior/stances.go:124`) |

**SoD — `wowsims/sod ui/warrior/apls/phase_6_dw.apl.json`**

| i | cast | name |
|---|---|---|
| 0 | 412513 | **Gladiator Stance** (SoD rune stance) |
| 1 | 2457 | **Battle Stance** (SoD) |
| 2,3 | 2458 | Berserker Stance |
| 4 | 412513 | Gladiator Stance |
| 5 | 2457 | Battle Stance |
| 6 | 2458 | Berserker Stance |
| 7 | 2687 | Bloodrage |
| 8 | 25286 r9 | Heroic Strike |
| 9 | item 13442 | trinket |
| 10 | 426940 | **Rampage** (`sod sim/warrior/rampage.go`) |
| 11 | 11574 r7 | Rend |
| 12 | 12328 | Death Wish |
| 13 | — | `autocastOtherCooldowns` |
| 14 | 1719 | Recklessness |
| 15 | 11605 r4 | Slam (Blood Surge rune) |
| 16 | 23894 r4 | Bloodthirst |
| 17 | 1680 | Whirlwind |
| 18 | — | `strictSequence` (the stance-dance group) |
| 19 | 402911 | Raging Blow (`sod sim/warrior/raging_blow.go:32`) |
| 20 | 27584 r3 | Hamstring |

**TBC — `wowsims/tbc-new ui/specs/warrior/dps/apls/fury.apl.json`** (the arms
APL is identical in shape; differences noted in the table)

| i | cast | name |
|---|---|---|
| 0 | group `Recklessness ON/OFF` (empty) → 1719 at i=9 | Recklessness |
| 1 | group `Bloodlust + Drums` → 2825, 35476, 35476 | Bloodlust / drums |
| 2 | group `Engineering` → 23827, 10646, 23737, 23736, 11566, 18588 | consumables |
| 3 | group `CD: Trinkets` → 28485, 33831, 21670, 29383, 281739, 23041, 28288, 22954, 28041, 28121, 35702, 24128 | trinkets |
| 4 | group `Sunder Armor` → 25225 | Sunder Armor (TBC rank) |
| 5 | other | `OtherActionPotion` |
| 6 | item 22788 | Healthstone |
| 7 | group `CD: Racials` → 33697, 26296 ×5 | Blood Fury / **Berserking** (Troll) |
| 8 | 12292 | **Death Wish** (TBC Arms/Fury 51 talent — `tbc-new sim/warrior/talents_arms.go:314`) |
| 9 | 1719 | Recklessness |
| 10 | 12723 | Sweeping Strikes (`tbc-new sim/warrior/sweeping_strikes.go`) |
| 11 | 1680 | Whirlwind (targets > 1) |
| 12 | 30335 | Bloodthirst (TBC rank 5) |
| 13 | 1680 | Whirlwind (TTR(BT) ≥ 1.5 s) |
| 14 | 25236 | Execute (E20) |
| 15 | 25231 | Cleave |
| 16 | group `Overpower Weaving` → wait, **2457 (Battle Stance)**, 11585 (Overpower), 2458 (Berserker Stance) | the Overpower weave |
| 17 | 2458 | Berserker Stance (cast when BT or WW is about to be ready) |
| 18 | 29707 | Heroic Strike (TBC) |
| 19 | 25212 | **Hamstring** (TBC) |
| 20 | 2687 | Bloodrage |
| 21 | 18499 | Berserker Rage |
| 22 | 2048 | **Battle Shout** (rank 8) |
| 23,24 | 2458 | Berserker Stance (maintenance, `[HIDE]`) |
| 25-27 | 1719 / 20230 / 871 | Recklessness / Retaliation / Shield Wall — all `IF false` `[HIDE]` |

TBC **arms** APL differences: 12 = 25242 (Slam), 13 = 30330 (Mortal Strike),
19 = 29707, 20 = 25212, 21 = 2687, 22 = 2048; group `Overpower Weaving` at i=17
with the same 2457 → 11585 → 2458 order.

**Forever — `wowsims/forever ui/specs/warrior/dps/apls/arms.apl.json`**

| i | cast | name |
|---|---|---|
| 0-2 | groups `Recklessness ON/OFF`, `Stance Dance ON/OFF`, `Hamstring Weave ON/OFF` (all empty toggle groups) | — |
| 3 | group `Engineering` → 10646, 11566, 18588 | consumables |
| 4 | group `CD: Trinkets` → 21670, 23041, 22954, 29602, 21891, 274759 | trinkets |
| 5 | group `Sunder Armor` → 11597 | Sunder Armor |
| 6 | group `Sunder Armor: Refresh` → 11597 `[HIDE]` | Sunder refresh |
| 7 | other | `OtherActionOffensivePotion` |
| 8 | other | `OtherActionResourcePotion` |
| 9 | group `CD: Racials` → 20572, 20554, 1259813, 1259799 | Blood Fury / Berserking / two unknown racials (UNCONFIRMED) |
| 10 | 12328 | Death Wish |
| 11 | 1719 | Recklessness |
| 12 | 12723 | Sweeping Strikes |
| 13 | **2457** | **Battle Stance** |
| 14 | 21553 | **Mortal Strike** (`tbc-new` data: 21553 = Mortal Strike; Forever's own table lists 21553 under `MortalStrike`) |
| 15 | 11574 | Rend |
| 16 | 11585 | Overpower |
| 17 | 21553 | Mortal Strike |
| 18 | 1310222 | **UNCONFIRMED** (Forever-only; no name in the sim) |
| 19 | 2458 | Berserker Stance |
| 20,21 | 11605 | Slam |
| 22 | 1680 | Whirlwind |
| 23 | 7373 | Hamstring |
| 24 | 20662 | Execute |
| 25 | 2457 | Battle Stance (back) |
| 26 | 20569 | Cleave |
| 27 | 25286 | Heroic Strike |
| 28 | 2687 | Bloodrage |
| 29 | 25289 | Battle Shout |
| 30-32 | 1719 / 20230 / 871 | `IF false` `[HIDE]` |

Forever **prepull**: 18499 (Berserker Rage) @−4.5 s, group `Pre-pull: Stance` →
2457 (Battle Stance) @−4 s, 2687 (Bloodrage) @−3 s, 25289 (Battle Shout) @−3 s,
group `Pre-pull: Move` → 11578 r3 (Charge) / 20617 r3 (Intercept) @−0.9 s.

**WotLK — `wowsims/wotlk ui/warrior/apls/arms.apl.json`**

| i | cast | name |
|---|---|---|
| 0 | — | `autocastOtherCooldowns` |
| 1 | 2687 | Bloodrage (`wotlk sim/warrior/bloodrage.go:10`) |
| 2 | other | `OtherActionPotion` (E20) |
| 3 | 47520 | Cleave (`wotlk sim/warrior/heroic_strike_cleave.go:62`) |
| 4 | 47450 | Heroic Strike (`…/heroic_strike_cleave.go:16`) |
| 5 | 47467 | Sunder Armor (`wotlk sim/warrior/sunder_armor.go:14`) `[HIDE]` |
| 6 | 47465 | Rend (`wotlk sim/warrior/rend.go:20`) |
| 7 | 7384 | Overpower (`wotlk sim/warrior/overpower.go:45`) |
| 8 | 46924 | Bladestorm (`wotlk sim/warrior/talents.go:787`) |
| 9 | 47486 | Mortal Strike (`wotlk sim/warrior/mortal_strike.go:16`) |
| 10 | 47471 | Execute (`wotlk sim/warrior/execute.go:18`) |
| 11 | 47502 | Thunder Clap (`wotlk sim/warrior/thunder_clap.go:16`) |
| 12 | 47475 | Slam (`wotlk sim/warrior/slam.go:11`) |

WotLK **fury** APL: 0 autocast, 1 = 2687 Bloodrage, 2 = 47467 Sunder `[HIDE]`,
3 = item 40211, 4 = 47520 Cleave, 5 = 47450 Heroic Strike, 6 = 1680 Whirlwind,
7 = 23881 Bloodthirst, 8 = 1680, 9 = 64382 Shattering Throw
(`wotlk sim/warrior/shattering_throw.go:15`), 10 = 47475 Slam, 11 = 47467 `[HIDE]`,
12 = 47471 Execute, 13/14 = strict sequences (Rend / Sudden Death),
15 = 57755 Heroic Throw (`wotlk sim/warrior/heroic_throw.go:11`), 16 = 2458
Berserker Stance. WotLK **prepull**: 2458 @−20 s, 2687 @−10 s, 18499 @−5 s,
1719 @−3 s, 12292 (Death Wish) @−1.5 s.

### 1.3 Missing lines — the warrior's utility set (the operator's case)

Every row below is **absent from `ST.WARRIOR.practice_rotation`** but present
in that family's APL priority list.

| proposed key | spell | ids per family | family gate | APL position (citation) | state needed | probe |
|---|---|---|---|---|---|---|
| `battle_stance` | Battle Stance | 2457 (all clients; the sim registers the stance aura 2457 — `classic sim/warrior/stances.go:86`, `tbc-new …:72`, `sod …:89`, `wotlk …:67`) | SoD, TBC, Forever (priority lines); WotLK (prepull). **Not in the Era priority list** (the Era APL only ever goes to Berserker Stance, i=24) | SoD i=1,5; TBC i=16.g.1 / 17.g.1; Forever i=13,25; WotLK prepull | *stance aura active* | **PROBE EXISTS** — `self.warrior_stance` is already read from the player's own stance auras: `classes/warrior.lua:601-625` (`api.UnitAura("player", i, "HELPFUL")`), id table `WARRIOR_STANCES.ids` at `:327-331` (2457 → `battle`, 71 → `defensive`, 2458 → `berserker`), published at `:684`. A new rotation line needs **no new read**. |
| `berserker_stance` | Berserker Stance | 2458 (all) | Era, SoD, TBC, Forever, WotLK | Era i=24; SoD i=2,3,6; TBC i=16.g.3, 17, 23, 24; Forever i=19; WotLK fury i=16 | *stance aura active* | **PROBE EXISTS** — same walk as above (`WARRIOR_STANCES.ids[2458]`). |
| `bloodrage` | **Bloodrage** | 2687 (all five families) | **ERA, SoD, TBC, FOREVER, WRATH** — see the correction in §1.4 | Era i=21; SoD i=7; TBC i=20 (fury) / 21 (arms); Forever i=28 (arms) / 23 (fury); WotLK arms i=1, fury i=1 | *cooldown ready* + rage | **NEW PROBE** — nothing in the tree reads 2687 (`grep -n "2687" classes/warrior.lua` → no hit). The read is `api.GetSpellCooldown(2687)` (`compat.lua:229`) → `duration == 0` = ready. The APL's own condition is `rage() < 90`, and rage is already readable via `api.UnitPower("player", 2)` (`compat.lua:349`). No new client API. |
| `battle_shout` | Battle Shout | **11549 / 2048 / 25289** (older ranks) | Era 25289; TBC 2048; Forever 25289; SoD 12328 is Death Wish, not a shout | Era i=23; TBC i=22; Forever i=29 (+ prepull @−3 s) | *player buff aura + refresh window* | **PROBE EXISTS (badge only)** — the warrior already reads the Battle Shout aura (`classes/warrior.lua:645-658`, id table `WARRIOR_BATTLE_SHOUT_IDS` at `:85`, name fallback at `:88`) and publishes `self.warrior_battle_shout_expires` (`:677`). **What is missing is the rotation line**, not the read. |
| `recklessness` | Recklessness | 1719 | Era i=4/5 `[HIDE]`, SoD i=14, TBC i=9, Forever i=11, WotLK prepull @−3 s | Era/SoD/TBC/Forever/WotLK | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(1719)` (`compat.lua:229`). (The WotLK prepull is a real line; the Era Fury APL's own line is `IF false`, i.e. the build does not take it — see §1.4.) |
| `death_wish` | Death Wish | 12328 (Era, SoD, Forever) / **12292** (TBC) | Era, SoD, TBC, Forever — the WotLK **prepull** also casts 12292 (Death Wish on WotLK too), but the WotLK arms APL has no Death Wish **rotation** line | Era i=3; SoD i=12; TBC i=8; Forever i=10; WotLK prepull @−1.5 s (fury) | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(12328)` on Era/SoD/Forever, `api.GetSpellCooldown(12292)` on TBC. The id differs per family: `api.get_family_spell_id({ERA=12328, TBC=12292, …})` (`compat.lua:1533`) is the house way to carry that split. **Note (SUPERSEDED 2026-10-20):** 12292 is a **family-split id** — it is Death Wish on TBC *and* Sweeping Strikes on the Forever client (§0.0 **W2**). |
| `sweeping_strikes` | Sweeping Strikes | **12723** (the APL's cast id on both TBC and Forever) — the id **12292** is Death Wish on TBC *and* Sweeping Strikes on the **Forever** client (**SUPERSEDED 2026-10-20**: this row used to read "12292 / 12723 (TBC)"; see §0.0 **W2**) | TBC, Forever (and WotLK has the spell, but the WotLK APL does not use it) | TBC i=10; Forever i=12 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(12723)`. |
| `thunder_clap` | Thunder Clap | 47502 | **WRATH only** | WotLK arms i=11 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(47502)`. |
| `shattering_throw` | Shattering Throw | 64382 | **WRATH only** | WotLK fury i=9 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(64382)`. |
| `heroic_throw` | Heroic Throw | 57755 | **WRATH only** | WotLK fury i=15 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(57755)`. |
| `charge` | Charge | 100 (Era ranks) / **11578 r3** (TBC, Forever) | TBC + Forever (as the prepull `Pre-pull: Move` line). The Era client has the spell but the **Era APL has no Charge line** | TBC prepull `Pre-pull: Move` → 11578 r3; Forever prepull `Pre-pull: Move` → 11578 r3 (Battle Stance) / 20617 r3 (Berserker Stance) | *cooldown ready* + target distance (Charge needs 8-25 yd — `tbc-new sim/warrior/spell_data_auto_gen.go`: `MinRange: 8, MaxRange: 25`) | **NEW PROBE** — `api.GetSpellCooldown(11578)` (`compat.lua:229`) plus `api.CheckInteractDistance` / `api.UnitDistance` (`compat.lua:917`, `:942`) for the range gate. `11578` is **Charge rank 3** in the TBC/Forever client (`tbc-new sim/warrior/charge.go:9` — `spellData.Charge.BySpellID(11578)`); the Era rank-1 id is 100. |
| `intercept` | Intercept | 25275 r5 (TBC) / 20617 r3 (Forever) | TBC, Forever — the partner of Charge in the `Pre-pull: Move` group (the prepull casts Intercept in **Berserker** Stance) | TBC prepull; Forever prepull | *cooldown ready* + range | **NEW PROBE** — `api.GetSpellCooldown(25275)` (TBC) / `api.GetSpellCooldown(20617)` (Forever). |
| `berserker_rage` | Berserker Rage | 18499 | Era i=22 `[HIDE]`, TBC i=21, Forever prepull @−4.5 s | Era/SoD/TBC/Forever | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(18499)`. (This is the id the shipped `hamstring` row cites for the TBC weave; the sim's own file names it Berserker Rage — `classic sim/warrior/berserker_rage.go:14` — so the TBC "Hamstring weave" row's `18499` is a **Berserker Rage** cast, not a Hamstring. Worth a separate correction.) |
| `demoralizing_shout` | Demoralizing Shout | rank table `core.DemoralizingShoutSpellId[rank]` (`classic sim/warrior/demoralizing_shout.go:9`) | Era/SoD/TBC (the classic line); the APLs use 12328 (Death Wish) instead, so the **Demoralizing Shout has no APL line** in the five fetched APLs | — | *cooldown ready* | not an APL line — see §1.4. |
| `blood_fury` | Blood Fury (Orc racial) | 20572 | Era i=7, SoD prepull, TBC group `CD: Racials` (33697), Forever group `CD: Racials` (20572) | Era/SoD/TBC/Forever | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(20572)`. The TBC id is a **rank** of the same spell, not a different spell: **33697 is Blood Fury rank 2** (20572 is rank 1) — **SUPERSEDED 2026-10-20** (this row used to say "a different spell"); see §0.0 **W3**. `api.get_family_spell_id` again. |
| `berserking` | Berserking (Troll racial) | 26296 (TBC) / 20554 (Forever) | TBC group `CD: Racials` i=1-5; Forever group `CD: Racials` i=1 | TBC/Forever | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(26296)` (TBC) / `api.GetSpellCooldown(20554)` (Forever). |

**The operator's "Charge" and "Battle Stance" are real and both are missing.**
The operator's third example — *"Blood Rage is a WotLK warrior ability and must
NOT appear on TBC/Era"* — is **wrong for the sim's Bloodrage**; see §1.4.

### 1.4 Correctly absent (do not add)

* **Bloodrage 2687 is NOT WotLK-only.** The operator's example is corrected here:
  2687 sits in the **Era** APL (`dps_no_reck.apl.json` i=21, `IF rage() < 90`),
  the **SoD** APL (`phase_6_dw.apl.json` i=7), the **TBC** APLs
  (`ui/specs/warrior/dps/apls/fury.apl.json` i=20, `arms.apl.json` i=21), the
  **Forever** APLs (`arms.apl.json` i=28, `fury.apl.json` i=23) and the **WotLK**
  APLs (`arms.apl.json` i=1, `fury.apl.json` i=1). It is a classic-era ability
  on every family the tree supports. What is WotLK-only is a *different* spell
  also called "Blood Rage" (the blood-magic damage shield) — **no fetched APL
  contains it**, so it is correctly absent from the rotation table. A line built
  on 2687 must ship on all five families.
* **Demoralizing Shout** — the sim has the ability
  (`classic sim/warrior/demoralizing_shout.go:7-16`) but **no fetched warrior
  APL casts it**: the Era APL's shout slot is 25289 (Battle Shout) and the
  TBC/Forever APLs' shout slot is 2048/25289 (Battle Shout). Correctly absent.
* **Shield Wall 871 / Retaliation 20230** — present in every APL but each one
  is `IF false` `[HIDE]` (Era i=26/27, TBC i=26/27, Forever i=31/32): the sim's
  own condition makes them unreachable. Correctly absent.
* **Recklessness in the Era Fury APL** — the Era APL's Recklessness lines are
  `IF false` (i=4) and a `[HIDE]` `remainingTime <= 15s` line (i=5); the Era
  build does not take the talent. The line belongs on SoD/TBC/Forever/WotLK,
  where it is a live priority row.
* **Bloodrage's `IF rage() < 90` condition** — on the live client the
  condition is a rage read (`api.UnitPower("player", 2)`), not a new probe.
* **Charge on Era / SoD** — the Era and SoD warrior APLs contain **no** Charge
  line at all (the sim never charges in those builds; the SoD APL's prepull
  moves with no spell). Charge is a TBC/Forever prepull line, not a rotation
  line, on those families. If the operator wants a Charge cue it is a
  *pre-pull / gap-close* cue, not a rotation entry.
* **Sundering / Blood Fury / trinkets / consumables** — the `CD: Trinkets`,
  `Engineering`, `CD: Racials` groups and the `OtherActionPotion` rows are
  sim-harness rows (the sim's "pop everything" layer). They are not rotation
  decisions; a practice rotation should not carry them. Correctly absent from
  a rotation table, and they belong in a "pre-pull" list if anywhere.

### 1.5 Priority-position conflicts (present but at a different priority)

* **TBC Overpower is gated on Battle Stance**: the `Overpower Weaving` group
  (TBC fury i=16) is `wait → 2457 (Battle Stance) → 11585 (Overpower) → 2458
  (Berserker Stance)`. The shipped `op` row (`classes/warrior.lua:3637`) is
  first in the table and carries no stance gate in the rotation key itself —
  the stance gate lives in the guide engine (`warrior_guide.lua`), not in the
  rotation table. Adding the stance lines to the table would expose the
  ordering the APL actually has.
* **WotLK Overpower is at i=7, after Rend (i=6) and Sunder (i=5)**, while the
  shipped table puts `op` first for ERA/TBC and has no WotLK `op` row at all
  (the WotLK APL's Overpower is 7384, a *different id* from the TBC 11585 and
  the SoD/era 11585). The shipped `op` row carries `families = {ERA, TBC}` —
  WotLK is absent — which matches the id split, but the operator's "the
  rotation has op/execute/slam/bt/ww/ms" reading hides that **WotLK Overpower
  is a separate line with its own id**.

---

## 2. HUNTER

### 2.1 Shipped rotation table — current action keys

`classes/hunter.lua:2815-2906` (per-family map) + `:2921-2955+` (prepulls):

| family | action keys (in order) | line |
|---|---|---|
| ERA | `aimed` (19434), `multi` (2643) | :2816-2825 |
| SOD | `chimera` (409433), `aimed` (19434), `multi` (2643) | :2826-2839 |
| TBC | `kill_command` (34026), `bestial_wrath` (19574), `rapid_fire` (3045), `arcane` (27019, DORMANT), `multi` (2643), `steady` (**34120**) — **SUPERSEDED 2026-10-20**: this cell used to read `56641`, which does not exist on the TBC client (§0.0 **H3**) | :2840-2865 |
| WRATH | `kill_shot` (**61006**), `chimera` (53209, MM), `explosive` (**60053**, SV), `aimed` (49050), `arcane` (49045, MM), `steady` (49052) — **SUPERSEDED 2026-10-20**: this cell used to read `53351` / `53301` (§0.0 **H1**, **H2**) | :2866-2891 |
| FOREVER | `hawk` (no id, CLIENT-UNCONFIRMED), `sniper` (no id) — **SUPERSEDED 2026-10-20**: this cell used to carry a third key, `steady` (56641); the **Forever client has no Steady Shot at all** and the row was removed by the live lane (§0.0 **H4**) | :2892-2905 |

Prepulls (a separate table, so a prepull line does NOT appear in the rotation
table): TBC `aspect_hawk` 27044 @−20 s + `steady` 34120 @0.5 s (`:2922-2931`);
SoD `aspect_falcon` 469145 @−5 s, `aimed` 20904 @−3.5 s, `blood_fury` 20572
@−1.95 s, `rapid_fire` 3045 @−0.45 s, `serpent` 25295 @−0.45 s (`:2932-2953`);
Forever `aspect_hawk` 25296 @−20 s (`:2955+`).

### 2.2 APL priority list, per family

**ERA — `wowsims/classic ui/hunter/apls/p1.apl.json`**: 0 autocastOtherCooldowns,
1 = 3045 Rapid Fire, 2 = 20904 r6 Aimed Shot, 3 = 25294 r4 Multi Shot
(`tbc-new` data: 25294 = Multi Shot), 4 = 25295 r8 Serpent Sting, 5 = item 18641.
Prepull: 25296 **Aspect of the Hawk** @−10 s (**SUPERSEDED 2026-10-20**: this
line used to say "Aspect of the Cheetah" — the Cheetah is 5118; §0.0 **H6**),
20904 @−3.5 s.

**SoD — `wowsims/sod ui/hunter/apls/p7_weave.apl.json`**: 0 potion (mana < 55 %),
1 = item 12662 (mana < 65 %), 2 = cancelAura, 3 = 409433 Chimera Shot
(`sod sim/hunter/chimera_shot.go:19`), 4/5 = **MOVE** (the weave movement rows),
6 autocast, 7 = 3045 Rapid Fire (fight ≥ 4 s), 8/9 = items, 10 = cancelAura,
11 = 409433 (execute phase), 12/13 = 409593 **Kill Shot** (SoD rank),
14 = 25294 r5 Multi Shot, 15 = 409433, 16 = 14266 r8 **Raptor Strike**,
17 = 458482 **Wyvern Strike**, 18/19/20/21 = 409593, 22 = 415423 **Aspect of the
Viper** (mana < 5 %), 23 = 14287 r8 **Arcane Shot** (SoD rank), 24 = 469145
**Aspect of the Falcon** (`sod sim/hunter/aspects.go:143`), 25 = 20572 Blood Fury,
26 = item, 27 = 14268 r3 **Wing Clip**. Prepull: 469145, 20904, 20572, 26297,
items, 3045, 25295.

**TBC — `wowsims/tbc-new ui/specs/hunter/dps/apls/default.apl.json`**: 0 group
`Mana management` → item 22832, **34074 Aspect of the Viper** (mana < Viper
start), **27044 r8 Aspect of the Hawk** (mana ≥ Viper stop); 1 autocast (≥ 5 s);
2 = 34026 **Kill Command**; 3 = 34120 r1 **Steady Shot** (≤ 0.5 s); 4 group
`Weave` (wait/move/move); 5 = 27021 r6 Multi Shot; 6 = 27019 r9 Arcane Shot;
7 = 34120 r1 Steady Shot; 8 = 27021 r6 Multi Shot; 9 = 27019 r9 Arcane Shot.
Prepull: 27044 r8 @−20 s + group `Move to starting range` @−19 s.

**Forever — `wowsims/forever ui/specs/hunter/dps/apls/default.apl.json`**: 0
autocast (≥ 5 s); 1 = 14266 Raptor Strike; 2 = 14325 **Hunter's Mark** (if not
up); 3 = 14271 **Mongoose Bite**; 4 = 1317257 **UNCONFIRMED** (Forever-only,
melee-range row); 5 = 14305 **Immolation Trap**; 6 = 14268 Wing Clip; 7 group
`Weave`; 8 = 25295 Serpent Sting; 9/10 = reset/sequence (the Hawk sequence);
11 = 1293527 Summon Hawk (`forever sim/hunter/summon_hawk.go`);
12 = 14287 Arcane Shot; 13 = 2643 Multi Shot; 14 = 20904 Aimed Shot;
15 = wait (the weave). Prepull: 14325, 25296, group `Move to starting range`.

**WotLK — `wowsims/wotlk ui/hunter/apls/mm.apl.json`**: 0 autocast (> 10 s);
1 = 34074 Aspect of the Viper (mana < 10 %); 2 = 61847 **Aspect of the
Dragonhawk** (mana > 30 %) — **SUPERSEDED 2026-10-20**: this line used to say
"Aspect of the Wild"; the WotLK client renamed the Wild aspect to the
Dragonhawk (§0.0 **H5**); 3 = 34490 **Silencing Shot**; 4 = 61006 **Kill Shot**;
5 = 49001 **Serpent Sting**; 6 = 49067 **Explosive Trap**; 7 = 53209 Chimera Shot;
8 = 49050 Aimed Shot; 9 = 49048 Multi Shot; 10 = 49045 Arcane Shot `[HIDE]`;
11 = 49052 Steady Shot.

**WotLK SV — `wowsims/wotlk ui/hunter/apls/sv.apl.json`**: 0 autocast; 1 = 34074
Viper; 2 = 61847 Aspect of the Dragonhawk (see above); 3 = 61006 Kill Shot;
4 = 60053 **Explosive Shot** (the LnL-downrank pair;
`wotlk sim/hunter/explosive_shot.go:21,25`);
5 = 60052 (the other LnL rank); 6 = 49067 Explosive Trap; 7 = 49001 Serpent
Sting; 8 = 63672 **Black Arrow** (`wotlk sim/hunter/black_arrow.go:15`);
9 = 49050 Aimed Shot; 10 = 49048 Multi Shot; 11 = 49052 Steady Shot.

### 2.3 Missing lines

| proposed key | spell | ids per family | family gate | APL position | state needed | probe |
|---|---|---|---|---|---|---|
| `serpent` | Serpent Sting | 25295 (Era/SoD/Forever) / 49001 (WotLK) / 27019-era rank in TBC is 27019 (Arcane) — TBC's APL has **no** Serpent line | Era, SoD, Forever, WotLK | Era i=4; SoD prepull + the SoD APL's Chimera gate (dot < 5 s, i=3); Forever i=8; WotLK MM i=5, SV i=7 | *target debuff up* | **PROBE EXISTS** — `read_serpent_active()` (`classes/hunter.lua:2085-2100`) + `serpent_sting_ids` (`:217-219`) + name fallback `SERPENT_STING_NAME` (`:221`), published as `inputs.serpent_active` (`:2425`). What is missing is the **rotation line**, not the read. |
| `rapid_fire` | Rapid Fire | 3045 | Era i=1; SoD i=7 (+prepull); TBC (the shipped TBC table already has `rapid_fire`) | Era, SoD | *cooldown ready* | **NEW PROBE** (for the ERA/SoD rows) — `api.GetSpellCooldown(3045)` (`compat.lua:229`). |
| `arcane_shot` | Arcane Shot | 25294 (Era) / 14268 (SoD is Wing Clip; 14287 is the SoD Arcane) / 27019 (TBC) / 49045 (WotLK) | Era, SoD, TBC, WotLK | **the Era APL has no Arcane Shot row** (its i=3 is Multi Shot 25294) — **SUPERSEDED 2026-10-20**: this cell used to say "Era i=3" (§0.0 **H9**); SoD i=23; TBC i=6,9; WotLK MM i=10 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(id)` per family. The TBC row is already in the shipped table (and is marked DORMANT). |
| `multi_shot` | Multi Shot | 2643 / 25294 (Era) / 27021 (TBC) / 49048 (WotLK) | Era, SoD, TBC, Forever, WotLK | Era i=3; SoD i=14; TBC i=5,8; Forever i=13; WotLK i=9/10 | *cooldown ready* | **NEW PROBE** — but the shipped table already carries `multi` on ERA/SOD/TBC, so only the WotLK/Forever ids are new: `api.GetSpellCooldown(49048)` (WotLK) / `api.GetSpellCooldown(2643)` (Forever). |
| `kill_shot` | Kill Shot | **409593** (SoD) / 61006 (WotLK) — **SUPERSEDED 2026-10-20**: this cell used to read "14287 (SoD/TBC/Forever) / 61006 (WotLK)"; 14287 is **Arcane Shot r8**, and the TBC and Forever APLs cast **no Kill Shot at all** (§0.0 **H8**) | SoD, WotLK | SoD i=12,13,18-21 (409593 is the SoD rank of Kill Shot); WotLK i=4/3 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(409593)` / `api.GetSpellCooldown(61006)`. The shipped WotLK row carried 53351, a *third* id — the build lane re-cut it to 61006 (§0.0 **H1**). |
| `aspect_viper` | Aspect of the Viper | 34074 (TBC, WotLK) / 415423 (SoD) | TBC, SoD, WotLK | TBC i=0 group `Mana management`; SoD i=22 (mana < 5 %); WotLK i=1 | *player buff aura* + mana | **PROBE EXISTS** — `viper_ids = {34074, 415423}` (`classes/hunter.lua:252`), `is_viper_known()` (`:1015`), `is_viper_active()` (`:1026`). |
| `aspect_hawk` | Aspect of the Hawk | 27044 (TBC) / 25296 (Forever) / 469145 (SoD Falcon) | TBC, Forever, SoD | TBC i=0 (group `Mana management`) + prepull @−20 s; **in the Forever APL the Hawk is a pre-pull row** (`prepullActions` i=1), so under HU-12 it is not a rotation row there — **SUPERSEDED 2026-10-20** (§0.0 **H7**) | *player buff aura* | **PROBE EXISTS for TBC** — the prepull table carries it (`classes/hunter.lua:2924`), but the *rotation* line (the APL's group row) has no aura probe. The read is `api.scan_player_aura` (`compat.lua:514`) on 27044. |
| `aspect_dragonhawk` | Aspect of the Dragonhawk (the WotLK client's name for the old Aspect of the Wild) | 61847 | **WotLK only** | WotLK MM i=2 / SV i=2 | *player buff aura* + mana | **NEW PROBE** — `api.scan_player_aura` on 61847. **SUPERSEDED 2026-10-20**: this row used to be keyed `aspect_wild` and named "Aspect of the Wild" — the id is right, the name is not (§0.0 **H5**). |
| `silencing_shot` | Silencing Shot | 34490 | **WotLK only** | WotLK MM i=3 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(34490)`. |
| `explosive_trap` | Explosive Trap | 49067 | **WotLK only** | WotLK MM i=6, SV i=6 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(49067)`. |
| `black_arrow` | Black Arrow | 63672 | **WotLK only** | WotLK SV i=8 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(63672)`. |
| `explosive_shot` | Explosive Shot | 60053 / 60052 (the LnL-downrank pair) | **WotLK SV only** | WotLK SV i=4,5 | *cooldown ready* | The shipped table already has `explosive` on WotLK/SV — it carried 53301, the client's rank-1; the APL casts **60053/60052**. **SUPERSEDED 2026-10-20** (the build lane re-cut the row to 60053; §0.0 **H2**). A new read is `api.GetSpellCooldown(60053)`. |
| `raptor_strike` | Raptor Strike | 14266 | SoD, Forever | SoD i=16; Forever i=1 | *cooldown ready* (melee) | **NEW PROBE** — `api.GetSpellCooldown(14266)`. |
| `wyvern_strike` | Wyvern Strike | 458482 | **SoD only** | SoD i=17,19,20,21 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(458482)`. |
| `mongoose_bite` | Mongoose Bite | 14271 | **Forever only** | Forever i=3 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(14271)`. |
| `immolation_trap` | Immolation Trap | 14305 | **Forever only** | Forever i=5 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(14305)`. |
| `wing_clip` | Wing Clip | 14268 | SoD, Forever | SoD i=27; Forever i=6 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(14268)`. |
| `hunters_mark` | Hunter's Mark | 14325 | **Forever only** | Forever i=2 | *target debuff up* | **NEW PROBE** — `api.scan_unit_aura("target", …)` (`compat.lua:569`) on 14325. |
| `serpent_sting_wotlk` | Serpent Sting (WotLK rank) | 49001 | **WotLK only** | WotLK MM i=5, SV i=7 | *target debuff up* | **PROBE EXISTS** — `serpent_sting_ids` already carries the WotLK rank (`classes/hunter.lua:200-201` names 49001). |

### 2.4 Correctly absent

* **Traps (Freezing, Immolation) in the WotLK MM APL** — only 49067 (Explosive
  Trap) is in the WotLK APLs; the Freezing Trap does not appear in either
  WotLK APL. Correctly absent.
* **Volley / Raptor Strike in the Era APL** — the Era `p1.apl.json` has four
  spell lines (Rapid Fire, Aimed Shot, Multi Shot, Serpent Sting) and nothing
  else. The class's melee surface (Raptor Strike) and Volley are not APL rows
  there. The SoD/Forever APLs *do* carry Raptor Strike (14266), so the class
  can use it on those families only.
* **Aimed Shot on the TBC APL** — the TBC APL has no Aimed Shot row at all
  (Steady Shot is the filler). The shipped TBC table has no `aimed` row, which
  matches. Correctly absent.
* **Mongoose Bite on Era/SoD/TBC/WotLK** — only the Forever APL casts it.
* **Aspect of the Dragonhawk on non-WotLK** — WotLK only. **SUPERSEDED
  2026-10-20**: this bullet used to read "Aspect of the Wild"; the WotLK
  client's name for the id 61847 is the Dragonhawk (§0.0 **H5**).
* **Chimera Shot on Era/TBC/Forever** — the SoD and WotLK APLs carry it
  (409433 / 53209); Era, TBC and Forever do not (the hunter has no Chimera
  there). The shipped table already gates it to SoD/Wrath.
* **The `move` rows** (SoD i=4,5; TBC/Forever `Weave` group) — the sim's
  movement layer, not a rotation decision. Correctly absent from a rotation
  table.

### 2.5 Priority conflicts

* **Serpent Sting is a rotation upkeep, not a prepull-only line.** It is the
  APL's i=4 (Era), i=8 (Forever) and i=5/i=7 (WotLK) row. The shipped tree
  knows the *read* (`read_serpent_active`) but the rotation table does not
  carry the *line* on any family.
* **WotLK `explosive`** — the shipped row cited 53301; the SV APL casts
  60053/60052 (`wotlk sim/hunter/explosive_shot.go:21,25`). Present but the
  ids differ; the MM APL has no Explosive Shot row at all. **RESOLVED
  2026-10-20**: the build lane re-cut the row to 60053 (§0.0 **H2**).
* **WotLK `kill_shot`** — the shipped row cited 53351; both WotLK APLs cast
  61006 (`wotlk sim/hunter/kill_shot.go:12`). Same line, different id.
  **RESOLVED 2026-10-20**: the build lane re-cut the row to 61006 (§0.0
  **H1**).
* **TBC `steady`** — the shipped row cited 56641, which does not exist on the
  TBC client; the TBC APL casts 34120 r1. **RESOLVED 2026-10-20** (§0.0
  **H3**).
* **FOREVER `steady`** — the shipped row cited 56641; the Forever client has
  no Steady Shot at all. **RESOLVED 2026-10-20**: the row was removed (§0.0
  **H4**).
* **TBC `arcane`** — shipped 27019 (DORMANT in the engine, the base set is
  full 6/6); the TBC APL casts 27019 at i=6 and i=9, so the line is real and
  the engine is the thing that is dormant.

---

## 3. ROGUE

### 3.1 Shipped rotation table — current action keys

`classes/rogue.lua:2174-2271`, in shipped order, with `families`:

| # | action | rule | families | line |
|---|---|---|---|---|
| 1 | `expose` | 1 | ERA, TBC, WRATH, FOREVER | :2175 |
| 2 | `snd` | 1b | ERA, TBC, WRATH, FOREVER | :2183 |
| 3 | `hfb` | 1c | WRATH | :2191 |
| 4 | `shiv` | 2 | ERA, TBC | :2199 |
| 5 | `envenom` | 3 | ERA, TBC, WRATH, FOREVER | :2207 |
| 6 | `eviscerate` | 4/5 | ERA, TBC, WRATH, FOREVER | :2215 |
| 7 | `rupture` | 5 | TBC, WRATH, FOREVER | :2223 |
| 8 | `ar` | 5b | ERA, TBC, WRATH, FOREVER | :2231 |
| 9 | `bf` | 5c | ERA, TBC, WRATH, FOREVER | :2239 |
| 10 | `coldblood` | 5d | TBC, FOREVER | :2247 |
| 11 | `tea` | 6 | ERA, TBC, WRATH, FOREVER | :2255 |
| 12 | `builder` | 7 | ERA, TBC, WRATH, FOREVER | :2263 |

**12 keys — all of them damage, debuff or a cooldown pop.** No stealth, no
utility, no movement, no poison-upkeep, no racial.

### 3.2 APL priority list, per family

**ERA — `wowsims/classic ui/rogue/apls/combat_sinister_strike.apl.json`**: 0 =
6774 r2 Slice and Dice; 1 = 13750 **Adrenaline Rush** (`classic
sim/rogue/talents.go:374` — "Adrenaline Rush Action ID"); 2 = autocast;
3 = 31016 Eviscerate; 4 = 11294 r8 Sinister Strike.
**`…_iea.apl.json`** adds: 0 = item 7676 Thistle Tea; 1 = 11198 r5 Expose Armor;
2 = 6774 r2; 3 = 13750 Adrenaline Rush; 4 = autocast; 5 = 31016 Eviscerate;
6 = 11294 r8. Prepull: 13750 @−1 s.

**SoD — `wowsims/sod ui/rogue/apls/P5_Saber.apl.json`**: 0 = item 7676 Thistle
Tea; 1 = autocast; 2 = item 10646; 3 = **424785 Saber Slash** (`sod
sim/rogue/saber_slash.go`); 4 = 13877 Blade Flurry; 5 = **425012 Poisoned
Knife** (`sod sim/rogue/poisoned_knife.go`); 6 = 6774 r2 Slice and Dice;
7 = **1856 r1 Vanish** (`sod sim/rogue/vanish.go:11`); 8 = strictSequence (the
Envenom opener); 9 = 399963 Envenom; 10 = 11294 r8 Sinister Strike;
11 = 424785 Saber Slash; 12 = item 18641. Prepull: activateAura, 20572 Blood
Fury @−1.5 s, items.

**TBC — `wowsims/tbc-new ui/specs/rogue/dps/apls/swords.apl.json`**: 0 = 13750
Adrenaline Rush; 1 = item 7676 Thistle Tea; 2 = 13877 Blade Flurry; 3 = 14177
Cold Blood; 4 = autocast; 5 = group `Cast Expose or Pool` → waitUntil, **26866
r6 Expose Armor** (`tbc-new sim/rogue/expose_armor.go:8`); 6 = 6774 Slice and
Dice; 7 = **26867 Rupture** (`tbc-new` data, `spell_data_auto_gen.go`); 8 = 26865
r10 **Eviscerate** (`tbc-new sim/rogue/eviscerate.go:8`); 9 = **5938 r1 Shiv**
(`tbc-new sim/rogue/shiv.go:8`); 10 = 26864 Hemorrhage; 11 = 26863 r10 Backstab;
12 = 5938 r1 Shiv; 13 = 34413 Mutilate; 14 = 26862 r10 Sinister Strike;
15/16 = items. Prepull: item 24114, 13750 @−1 s.

**Forever — `wowsims/forever ui/specs/rogue/dps/apls/default.apl.json`**: 0 group
`Maintain Expose` → 11198 Expose Armor; 1 = 11269 **Ambush**; 2 = 11290
**Garrote**; 3/4 = 1857 r2 **Vanish** (**SUPERSEDED 2026-10-20**: this line
used to say "Cloak of Shadows" — 1857 is Vanish rank 2 and the Cloak of
Shadows spell does not exist on the TBC/Forever clients; §0.0 **R1**);
5 = 14185 **Preparation** (`classic sim/rogue/preparation.go:15`); 6 = autocast;
7 group `Energy Pooling Checks`; 8 = 13750 Adrenaline Rush; 9/10 = strict
sequences (the Energy Potion / Blood Fury ordering); 11 = 20572 Blood Fury;
12 = 1259799 (**"Elune's Light"** — the Forever druid APL's own variable;
**SUPERSEDED 2026-10-20**: this cell used to say "the racial pairing —
UNCONFIRMED"; §0.0 **R8**);
13 = 1259812 **Gnome Eureka** (the APL's own variable is `Gnome Eureka - Should Cast`);
14 = `OtherActionOffensivePotion`; 15 = item 7676 Thistle Tea; 16 = 13877 Blade
Flurry; 17 = 14183 **Premeditation** (**SUPERSEDED 2026-10-20**: this line
used to say "Shadowstep" — 14183 is Premeditation on the Forever client too;
§0.0 **R2**); 18 = 6774 r2 Slice and
Dice; 19 = 1310703 **Venom** (**SUPERSEDED 2026-10-20**: this cell used to
say "Forever-only, UNCONFIRMED"; §0.0 **R7**); 20 = 11275 **Rupture**
(`tbc-new` data) — the Forever APL's Rupture id; 21 = 14177 Cold Blood;
22 = 11300 Shiv; 23 = 14278 **Ghostly Strike** (**SUPERSEDED 2026-10-20**:
this cell used to say "Subtlety talent id, UNCONFIRMED"; §0.0 **R9**);
24 = 16511 **Hemorrhage**; 25 = 11281 **Backstab**; 26 = 1241584 r4 **Mutilate**
(**SUPERSEDED 2026-10-20**: this line used to say "Shadowstep rank" — 1241584
is Mutilate rank 4; §0.0 **R3**); 27 = 16511 Hemorrhage; 28 = 11294 Sinister
Strike. Prepull: 13877, 14183, 1787 r4.

**WotLK — `wowsims/wotlk ui/rogue/apls/combat.apl.json`**: 0 = autocast;
1 = 6774 Slice and Dice; 2 = sequence; 3 = 6774; 4/5 = 48672 Rupture;
6/7/8 = 48668 Eviscerate; 9 = 13877 Blade Flurry; 10/11 = 54758 **Hypersharp
Weapon**; 12 = item 40211; 13 = 57934 **Tricks of the Trade**; 14 = 51690
**Killing Spree**; 15/16 = 13750 Adrenaline Rush; 17 = 48638 Sinister Strike.
**`mutilate.apl.json`**: 0 autocast; 1 = 6774; 2 = sequence; 3 = 51662
**Hunger for Blood** (the upkeep row — **SUPERSEDED 2026-10-20**: this line
used to say "Mutilate"; 51662 is Hunger for Blood and the Mutilate spell on
this client is 48666; §0.0 **R6**);
4 = 26889 **Vanish** (`wotlk sim/rogue/vanish.go:11`); 5 = item 40211;
6 = 54758 Hypersharp Weapon; 7 = 13877 Blade Flurry; 8 = 57934 Tricks of the
Trade; 9 = item 7676; 10 = 14177 Cold Blood; 11 = 57993 Envenom; 12 = 48666
Mutilate.

### 3.3 Missing lines

| proposed key | spell | ids per family | family gate | APL position | state needed | probe |
|---|---|---|---|---|---|---|
| `vanish` | Vanish | 1856 (SoD) / 26889 (WotLK) / 1857 r2 (Forever) | SoD, WotLK, FOREVER — **SUPERSEDED 2026-10-20**: this cell used to read "1856 (Era/SoD/TBC) / 26889 (WotLK)" with the gate "Era, SoD, TBC, WotLK"; the **Era and TBC APLs carry no Vanish row at all** (§0.0 **R1**, **R4**) | SoD i=7; WotLK mutilate i=4; Forever i=3,4 | *cooldown ready* (SoD row is an Envenom-opener gate: `cp == 5` and Envenom ready) | **NEW PROBE** — `api.GetSpellCooldown(1856)` / `api.GetSpellCooldown(26889)` / `api.GetSpellCooldown(1857)`. |
| ~~`cloak_of_shadows`~~ → `vanish` (rank 2) | **Vanish rank 2** (not Cloak of Shadows) | 1857 | **TBC, Forever** | Forever i=3,4 | *cooldown ready* | **SUPERSEDED 2026-10-20** — **REFUTED**: 1857 is Vanish rank 2 on the TBC and Forever clients; the TBC client's generated data has **no `CloakOfShadows` field at all** (the spell was removed in 2.3). The `cloak_of_shadows` row is withdrawn; the `vanish` row above carries the id (§0.0 **R1**). |
| `preparation` | Preparation | 14185 | **Forever only** | Forever i=5 | *player buff aura* | **NEW PROBE** — `api.scan_player_aura` on 14185 (`compat.lua:514`). |
| `ambush` | Ambush | 11269 | **Forever only** | Forever i=1 | *cooldown ready* + stealth state | **NEW PROBE** — `api.GetSpellCooldown(11269)`. |
| `garrote` | Garrote | 11290 | **Forever only** | Forever i=2 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(11290)`. |
| ~~`shadowstep`~~ → `premeditation` | **Premeditation** (not Shadowstep) | 14183 | **Forever only** | Forever i=17 | *cooldown ready* | **SUPERSEDED 2026-10-20** — **REFUTED**: 14183 is Premeditation on the Forever client (`Premeditation: spelldata.Ranked(14183)`), and the APL's row is the combo-point opener (`cp <= 3`). The `shadowstep` row is withdrawn (§0.0 **R2**). **NEW PROBE** — `api.GetSpellCooldown(14183)`. |
| `blood_fury` | Blood Fury (Orc) | 20572 | SoD, Forever | SoD prepull @−1.5 s; Forever i=11 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(20572)`. |
| `blood_fury_pair` | the Forever racial pairing | 1259799 ("**Elune's Light**") / 1259812 ("**Gnome Eureka**") | **Forever only** | Forever i=12,13 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(1259799)` / `…(1259812)`. 1259812's name is **Gnome Eureka** (the APL's own variable name); 1259799's is **"Elune's Light"** — **SUPERSEDED 2026-10-20**: this cell used to say 1259799 is UNCONFIRMED (§0.0 **R8**); the druid's APL calls the same id "Elune's Light" — `wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json` group `Cooldowns` → `cast spell 1259799 IF var:Elune's Light now`. |
| `mutilate` | Mutilate | 34413 (TBC) / 48666 (WotLK) / 1241584 r4 (Forever) | TBC, WotLK, Forever | TBC i=13; WotLK mutilate i=12; Forever i=26 | *cooldown ready* | **SUPERSEDED 2026-10-20**: this cell used to read "34413 (TBC) / 51662 (WotLK) / 48666 (WotLK)" — **51662 is Hunger for Blood, not Mutilate** (§0.0 **R6**). **NEW PROBE** — `api.GetSpellCooldown(34413)` / `…(48666)` / `…(1241584)`. The shipped table folds Mutilate into `builder`, so a dedicated Mutilate line (and its own id per family) is a gap. |
| `hemorrhage` | Hemorrhage | 26864 (TBC) / 16511 (Forever) | TBC, Forever | TBC i=10; Forever i=24,27 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(26864)` / `…(16511)`. (The shipped table folds it into `builder`.) |
| `backstab` | Backstab | 26863 r10 (TBC) / 11281 (Forever) | TBC, Forever | TBC i=11; Forever i=25 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(26863)` / `…(11281)`. (Shipped: folded into `builder`.) |
| `saber_slash` | Saber Slash | 424785 | **SoD only** | SoD i=3,11 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(424785)`. (Shipped: folded into `builder`.) |
| `poisoned_knife` | Poisoned Knife | 425012 | **SoD only** | SoD i=5 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(425012)`. |
| `hypersharp` | Hypersharp Weapon | 54758 | **WotLK only** | WotLK combat i=10,11; mutilate i=6 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(54758)`. |
| `tricks_of_the_trade` | Tricks of the Trade | 57934 | **WotLK only** | WotLK combat i=13; mutilate i=8 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(57934)`. |
| `killing_spree` | Killing Spree | 51690 | **WotLK only** | WotLK combat i=14 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(51690)`. |
| ~~`deadly_poison`~~ → `rupture` | **Rupture** (not Deadly Poison) | 26867 | **TBC only** | TBC i=7 | *target debuff up* | **SUPERSEDED 2026-10-20** — **REFUTED**: 26867 is **Rupture** on the TBC client (`Rupture: Ranked(1943, 8639, 8640, 11273, 11274, 11275, 26867)`), and the TBC APL casts **no Deadly Poison at all** — the Shiv (5938) applies it. The `deadly_poison` row is withdrawn (§0.0 **R5**). **NEW PROBE** — `api.scan_unit_aura("target", …)` (`compat.lua:569`) on 26867. |
| `prep_mana` | Energy Potion (item use) | 13750 in the rogue sim is **Adrenaline Rush**, not a potion — the potion is item 11128 | Era/SoD/TBC/Forever/WotLK | (the potion is not a spell line in the rogue APLs) | — | not a spell — see §3.4. |
| ~~`expose_forever`~~ → `venom` | **Venom** (not the Forever Expose) | 1310703 | **Forever only** | Forever i=19 | *buff down* + cp | **SUPERSEDED 2026-10-20** — **REFUTED**: 1310703 is **Venom** on the Forever client (`Venom: spelldata.Ranked(1310703)`). The `expose_forever` row is withdrawn; the Forever's Expose Armor is 11198 (the APL's `Maintain Expose` group) (§0.0 **R7**). |

### 3.4 Correctly absent

* **Adrenaline Rush is already shipped** (`ar`, `classes/rogue.lua:2231`) — the
  id in the APLs is 13750, and the sim confirms it is Adrenaline Rush
  (`classic sim/rogue/talents.go:374` "Adrenaline Rush Action ID"), not the
  Energy Potion. No gap.
* **Energy Potion (item 11128)** — the rogue APLs' potion rows are the *item*
  7676 (Thistle Tea) and the *spell* 13750 (Adrenaline Rush). There is no
  Energy-Potion spell line. Correctly absent.
* **Deadly Poison as an APL row anywhere** — **SUPERSEDED 2026-10-20**: this
  bullet used to say "Deadly Poison on Era/SoD/Forever/Wrath — only the TBC APL
  carries 26867". It is **REFUTED**: 26867 is **Rupture** on the TBC client and
  the TBC APL casts no Deadly Poison at all (the Shiv, 5938, applies it) — the
  TBC APL's own i=7 row is the Rupture row (§0.0 **R5**).
* **Shadowstep on any family** — 14183 is Premeditation on Era/SoD/Wrath **and
  on Forever**, and neither the Era, SoD nor WotLK rogue APL casts a
  Shadowstep. **SUPERSEDED 2026-10-20**: the Forever half of this bullet is
  refuted too — the Forever APL's i=17 is Premeditation, not a Shadowstep
  (§0.0 **R2**).
* **Cloak of Shadows on any family** — **SUPERSEDED 2026-10-20**: this bullet
  used to read "Cloak of Shadows / Preparation / Ambush / Garrote outside
  Forever — the Forever APL only". The Cloak of Shadows spell does not exist
  on the TBC or the Forever client (it was removed in 2.3); 1857 is Vanish
  rank 2 there (§0.0 **R1**). Preparation / Ambush / Garrote remain
  Forever-only, correctly.
* **Hunger for Blood on non-Wrath** — the shipped table already gates `hfb` to
  WRATH (`classes/rogue.lua:2191`); the WotLK APLs carry it
  (`mutilate.apl.json` i=3 casts **51662 with `auraRemainingTime(51662) <= 1s`**
  — the Hunger-for-Blood upkeep). **SUPERSEDED 2026-10-20**: this bullet used
  to read "i=3 uses 51662 = Mutilate" — 51662 is **Hunger for Blood**, and the
  WotLK Mutilate spell is **48666** (i=12) (§0.0 **R6**). Correctly as shipped.
* **The `Pooling Checks` group / strict sequences** (Forever i=7,9,10) — the
  sim's energy-pooling machinery, not a rotation decision. Correctly absent.

### 3.5 Priority conflicts

* **TBC Shiv vs Eviscerate**: the TBC APL's i=8 is Eviscerate (26865) and its
  i=9/12 is Shiv (5938) — the shipped table's rule 2/4/5 order (`shiv` before
  `eviscerate`) is the engine's order, not the APL's, and the ids differ from
  the shipped `shiv` row (the shipped `shiv` cites 26865-era ids; the TBC APL's
  Shiv is 5938).
* **Rupture id split**: TBC 26867, Forever 11275, WotLK 48672 — three ids for
  one ability. The shipped `rupture` row carries no id, so nothing in the
  table tells the builder which id to look for.

---

## 4. DRUID

### 4.1 Shipped rotation table — current action keys

`classes/druid.lua:2826-2950`, one entry per family (a flat array with a
`family` field), plus a shared `BEAR` slice:

| family | action keys (in order) | line |
|---|---|---|
| ERA | `shred` (E0), `rip` (E1), `shred` (E2) | :2828-2836 |
| SOD | `tigers_fury` (S1), `berserk` (S2), `savage_roar` (S3), `savage_roar` (S3b), `shred` (S4), `rip` (S5), `mangle` (S6), `rake` (S7), `shred` (S8) | :2838-2864 |
| TBC | `rip` (T1), `mangle` (T2), `bite` (T3), `rip` (T4), `shred` (T5) | :2866-2880 |
| WRATH | `tigers_fury` (W1), `faerie_fire` (W1b), `berserk` (W2), `savage_roar` (W3), `shred` (W4), `rip` (W5), `mangle` (W6), `rake` (W7), `bite` (W8), `shred` (W9) | :2882-2911 |
| FOREVER | `shifting_power` (F1), `berserk` (F1b), `shred` (F2), `rip` (F3), `rake` (F4), `mangle` (F5), `bite` (F6a/F6b), `faerie_fire` (F6c), `shred` (F7) | :2913-2939 |
| BEAR | `ride` (1/B1), `maul` (2/B2), `mangle` (3/B3) | :2941-2949 |

**All damage, dots and the two cooldowns.** No form upkeep (Cat Form), no
Leader of the Pack, no Faerie Fire (Feral) on Era, no clearcast, no Omen
maintenance line, no Healthstone/ mana tool.

### 4.2 APL priority list, per family

**ERA — `wowsims/classic ui/feral_druid/apls/feral.apl.json`**: 0 = 17392 r4
**Faerie Fire (Feral)** (`tbc-new` data: 17392 = "Faerie Fire Feral"; the Era
sim file is `sim/druid/faerie_fire.go:28`); 1 = 13494 — **SUPERSEDED
2026-10-20**: this line used to say "13494 Faerie Fire (Feral)"; the 1.15
client names **13494 "Haste"** (it is in no druid skill line) while the
client's **Leader of the Pack is 17007** (the Feral Combat skill line), so the
APL row casts Haste and is dead as written (§0.0 **D2**);
2 = autocast; 3 = cancelAura; 4 = 31018 r4 **Ferocious Bite** (`tbc-new` data:
31018 = Ferocious Bite); 5 = 9830 r5 **Shred**; 6 = 9850 r5 **Claw**
(`classic sim/druid/claw.go:14` — the Era builder is **Claw**, not Mangle!);
7 = cancelAura; 8 = 17392 r4; 9 = item 10646; 10 = item 12662; 11 = potion;
12 = 23724 (item use); 13 = 29166 **Innervate** (`classic sim/druid/innervate.go:16`);
14 = 768 **Cat Form** (`classic sim/druid/forms.go:88`). Prepull: 17392 @−1 s,
9846 **Tiger's Fury** @−3.5 s (`tbc-new` data: 9846 = Tigers Fury). **The Era
APL has no Rip row at all** (§0.0 **D3**).

**SoD — `wowsims/sod ui/feral_druid/apls/phase_5.apl.json`**: 0 = 768 Cat Form;
1 = 407988 **Savage Roar** (`sod sim/druid/savage_roar.go:20`); 2 = item 12662;
3 = potion; 4 = 29166 Innervate; 5 = 768 Cat Form; 6 = 417045 **Tiger's Fury**
(`sod sim/druid/tigers_fury.go:65`); 7 = 417045 Tiger's Fury; 8 = autocast;
9 = 409828 **Mangle** (`sod sim/druid/mangle.go:89`); 10 = 9830 r5 Shred;
11 = 9896 r6 Rip; 12 = 9904 r4 Rake; 13 = 409828 Mangle; 14 = 31018 Ferocious
Bite; 15 = 9830 r5 Shred; 16 = 409828 Mangle.

**TBC — `wowsims/tbc-new ui/specs/druid/feralcat/apls/default.apl.json`**: 0 =
2825 r1 Bloodlust; 1 = group `Drums` → 35476, 35476; 2 = 27011 **Faerie Fire
(Feral)** (`tbc-new sim/druid/faerie_fire.go:8`); 3 = 27008 r7 Rip; 4 = 33983 r3
**Mangle (Cat)** (`tbc-new sim/druid/mangle.go:8`); 5 = 27002 r7 Shred
(`tbc-new sim/druid/shred.go:8`); 6/8/14/18/23 = group `Powershifting` (the
engineering / trinket / healthstone / **768 Cat Form** rows); 7 = 27008 r7 Rip;
9/10 = 33983 r3 Mangle; 11 = 24248 r6 Ferocious Bite
(`tbc-new sim/druid/ferocious_bite.go:7`); 12 = 27008 r7 Rip; 13 = 27003 r5 Rake
(`tbc-new sim/druid/rake.go:10`); 15 = 33983 r3 Mangle; 16 = 27002 r7 Shred;
17 = 24248 r6 Ferocious Bite; 19 = 27002 r7 Shred; 20 = 33983 r3 Mangle;
21 = 27002 r7 Shred; 22 = 33983 r3 Mangle.

**Forever — `wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json`**:
0 = item 10646; 1 = 768 Cat Form; 2 = group `Berserk` (two strict sequences);
3 = group `Cooldowns` → 1259799 (**Elune's Light**, per the druid APL's own
variable), item 7676, `OtherActionResourcePotion`, autocast; 4 = 9830 Shred;
5 = 9850 **Claw** — **SUPERSEDED 2026-10-20**: this line used to say "9850
Mangle"; 9850 is Claw r5 and the **Forever client has no Mangle spell at all**
(§0.0 **D1**);
6 = group `Bleeds` → 9896 Rip, 9904 Rake; 7 = 22829
**Ferocious Bite** (`tbc-new` data: 22829 = Ferocious Bite); 8 = 1322605
**Shifting Power**; 9 = group `Builders` → 9830 Shred, 9850 **Claw** (same
correction as i=5); 10 = 29166 Innervate; 11 = 9907 **Faerie Fire (Feral)**.

**WotLK — `wowsims/wotlk ui/feral_druid/apls/default.apl.json`**: 0 = autocast;
1 = 50334 Berserk (`IF false`); 2 = `catOptimalRotationAction` — the sim's own
Catanced rotation engine, not a spell list. Prepull: activateAura, 50334
Berserk @−1 s.

### 4.3 Missing lines

| proposed key | spell | ids per family | family gate | APL position | state needed | probe |
|---|---|---|---|---|---|---|
| `cat_form` | Cat Form | 768 | Era, SoD, TBC, Forever | Era i=14; SoD i=0,5; TBC (the `Powershifting` group); Forever i=1 | *player form aura* | **NEW PROBE** — the form is readable via `api.GetShapeshiftForm()` (`compat.lua:805`) but that returns the *form index*, and the comment at `classes/warrior.lua:3122-3125` already records the per-family form-index map as **UNCONFIRMED**. The reliable read is `api.scan_player_aura` on 768 (`compat.lua:514`). |
| `leader_of_the_pack` | Leader of the Pack | **17007** (Era) / 27011 (TBC, the Faerie Fire (Feral) debuff) / 9907 (Forever) — **SUPERSEDED 2026-10-20**: this cell used to read "17392 (Era) / 13494 (Era) / 27011 (TBC) / 9907 (Forever)"; the 1.15 client names **13494 "Haste"** (in no druid skill line) and the client's **Leader of the Pack is 17007** (§0.0 **D2**) | Era, TBC, Forever | Era i=0,1,8; TBC i=2; Forever i=11 | *player buff aura* / *target debuff* | **NEW PROBE** — `api.scan_player_aura` on 17007/17392 and `api.scan_unit_aura("target", …)` on 27011/9907. The shipped table has a `faerie_fire` key, but only for WRATH and FOREVER (W1b, F6c) — the **Era and TBC Faerie-Fire rows are missing**. |
| `shred_claw` | Claw (the Era builder) | 9850 (Era) / 9850 (TBC) / 9850 (Forever) | Era, TBC, Forever | Era i=6; Forever i=5,9.g.1 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(9850)`. **SUPERSEDED 2026-10-20**: this row used to say 9850 is "**Claw** on Era … and **Mangle** in the Forever/TBC data — a family-specific id split". There is **no** split: 9850 is Claw r5 on **Era, TBC and Forever alike**, and the **Forever client has no Mangle spell at all** (§0.0 **D1**). |
| `innervate` | Innervate | 29166 | Era, SoD, Forever | Era i=13; SoD i=4; Forever i=10 | *cooldown ready* (and a mana condition) | **NEW PROBE** — `api.GetSpellCooldown(29166)`. |
| `tigers_fury` | Tiger's Fury | 9846 (Era) / 417045 (SoD) | Era, SoD (+WRATH/FOREVER already shipped) | Era prepull @−3.5 s; SoD i=6,7 | *cooldown ready* | **PROBE EXISTS** for WRATH/FOREVER (`classes/druid.lua:2071-2088`, `druid_berserk_ids`/`guide_berserk_query`); the **ERA/SoD ids (9846/417045) are not in the shipped row's id set** — a per-family id, not a new read. |
| `berserk` | Berserk | 27011 is Faerie Fire (Feral) in TBC; Berserk's ids are 50334 (WotLK) and the SoD rune (the shipped `berserk` row is SOD+WRATH+FOREVER) | SoD, WRATH, FOREVER | WotLK i=1 (`IF false`) + prepull; Forever group `Berserk` i=2 | *cooldown ready* | **PROBE EXISTS** (`classes/druid.lua:2080-2086`, `berserk_ready`). |
| `savage_roar` | Savage Roar | 407988 (SoD) | SoD (+WRATH/FOREVER shipped) | SoD i=1 | *player buff aura* | **NEW PROBE** — `api.scan_player_aura` on 407988. |
| `mangle_cat` | Mangle (Cat) | 33983 r3 (TBC) / 409828 (SoD) / 33876, 33983, 33987 (the TBC ladder) — **the Forever client has NO Mangle spell** | TBC, SoD | TBC i=4,9,10,15,20,22; SoD i=9,13,16 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(33983)` / `…(409828)`. The shipped `mangle` row carries no id, so the builder must resolve the family's id. **SUPERSEDED 2026-10-20**: this cell used to carry "9850 (Forever)" and the gate "Forever"; the Forever has no Mangle at all, so the id and the gate are withdrawn (§0.0 **D1**, **D4**). |
| `shred_cat` | Shred | 9830 r5 (Era/SoD) / 27002 r7 (TBC) / 9830 (Forever) | Era, SoD, TBC, Forever | Era i=5; SoD i=10,15; TBC i=5,16,19,21; Forever i=4,9.g.0 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(9830)` / `…(27002)`. |
| `ripe` | Rip | 9896 (SoD) / 27008 r7 (TBC) | SoD, TBC, Forever | **the Era APL has NO Rip row** — **SUPERSEDED 2026-10-20**: this cell used to read "9896 (Era/SoD)" with "Era i=?" (§0.0 **D3**); SoD i=11; TBC i=3,7,12; Forever i=6.g.0 | *target debuff up* | **NEW PROBE** — `api.scan_unit_aura("target", …)`. |
| `rake_cat` | Rake | 9904 (Era/SoD) / 27003 r5 (TBC) | Era, SoD, TBC, Forever | SoD i=12; TBC i=13; Forever i=6.g.1 | *target debuff up* | **NEW PROBE** — `api.scan_unit_aura`. |
| `elunes_light` | Elune's Light | 1259799 | **Forever only** | Forever i=3.g.0 (group `Cooldowns`) | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(1259799)`. The name comes from the APL's own variable (`var:Elune's Light now`). |
| `bloodlust` | Bloodlust | 2825 | TBC | TBC i=0 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(2825)`. |

### 4.4 Correctly absent

* **Innervate / Faerie Fire as *rotation* lines on WotLK** — the WotLK druid
  APL is `autocast + Berserk (IF false) + catOptimalRotationAction`; there is
  no Innervate or Faerie-Fire row there. Correctly absent for WRATH.
* **Cat Form on WotLK** — the WotLK APL's cat rotation is the sim's own
  `catOptimalRotationAction`; no Cat-Form row appears. Correctly absent.
* **The `Powershifting` group rows (TBC i=6/8/14/18/23)** — engineering,
  trinkets, healthstone and the Cat Form row are the sim's power-shifting
  machinery, not rotation decisions. Correctly absent from a rotation table
  (the Cat Form row inside it is a real upkeep and is listed above).
* **Mangle (bear) / Maul** — the shipped `BEAR` slice is the only bear chain
  and no fetched bear APL exists; the shipped note
  (`classes/druid.lua:2947-2949`) already says so. Correctly as shipped.
* **Bloodlust 2825 on the non-TBC families** — only the TBC druid APL carries
  the Bloodlust row.

### 4.5 Priority conflicts

* **The Era slice is not the Era APL.** The shipped ERA rows cite the sim's
  **Go rotation** (`classes/druid.lua:2830`: "sim wowsims/classic
  sim/druid/feral/rotation.go: doRotation"), while the Era repo also ships an
  APL (`ui/feral_druid/apls/feral.apl.json`) whose own order is
  `17392 → 13494 (the "Haste" row — the client's Leader of the Pack is 17007)
  → 31018 (Ferocious Bite) → 9830 (Shred) →
  9850 (Claw) → 17392 → 29166 (Innervate) → 768 (Cat Form)`. **SUPERSEDED
  2026-10-20**: this line used to read "17392/13494 (Faerie Fire Feral)"; 13494
  is "Haste" on the 1.15 client (§0.0 **D2**). Two rows that APL
  has and the shipped ERA slice has **no key for**: the **Faerie Fire (Feral)
  row** and the **Claw builder** (the shipped ERA slice's `shred` stands in
  for both). The APL's builder is **Claw (9850)**, not Shred — the shipped
  note at `classes/druid.lua:2834-2836` already calls the second `shred` entry
  "the builder fallthrough (the Shred trick window)", which is the SoD
  wording, not the Era one. The APL also has **no Rip row** (§0.0 **D3**).
* **TBC `bite` vs `rip`** — the TBC APL's i=11/17 is Ferocious Bite and the
  shipped TBC slice is `rip, mangle, bite, rip, shred`; the APL's order is
  `rip(3) → mangle(4) → shred(5) → … → bite(11,17) → rip(12) → mangle(13)`.
  Present but at a different position.

---

## 5. SHAMAN

### 5.1 Shipped rotation table — current action keys

`classes/shaman.lua:4116-4189`, in shipped order, with `families`:

| # | action | families | line |
|---|---|---|---|
| 1 | `fireele` (Fire Elemental Totem) | WRATH, TBC | :4117 |
| 2 | `feralspirit` | ERA, WRATH | :4121 |
| 3 | `shamanisticrage` | ERA, TBC, WRATH | :4125 |
| 4 | `weave` (Lightning Bolt) | ERA, TBC, WRATH | :4129 |
| 5 | `flameshock` | ERA, TBC, WRATH, FOREVER | :4133 |
| 6 | `twist` (Windfury Totem) | TBC | :4137 |
| 7 | `wftotem` (Windfury Totem) | ERA | :4141 |
| 8 | `goa` (Grace of Air Totem) | ERA | :4145 |
| 9 | `stormstrike` | ERA, TBC, WRATH, FOREVER | :4149 |
| 10 | `searing` (Searing Totem) | ERA, TBC, FOREVER | :4153 |
| 11 | `magma` (Magma Totem) | WRATH, TBC | :4157 |
| 12 | `firenova` (Fire Nova Totem) | TBC, WRATH, FOREVER | :4161 |
| 13 | `lightningshield` | WRATH | :4165 |
| 14 | `lavalash` | ERA, WRATH | :4169 |
| 15 | `chainlightning` | ERA | :4173 |
| 16 | `earthshock` | ERA, TBC, WRATH, FOREVER | :4177 |
| 17 | `moltenblast` | ERA | :4181 |
| 18 | `coe` (Call of the Elements) | WRATH | :4185 |

**18 keys — totems, shocks, weapon imbues and two cooldowns.** The class's
**buff upkeeps** (Strength of Earth, Windfury, Grace of Air, Ancestral
Spirit) and its **weapon-imbuff maintenance** are the
classic-line shaman's actual rotation, and the table carries only *some* of
the totems (Windfury/Grace of Air/Searing/Magma/Fire Nova/CoE) — not Strength
of Earth, not Mana Spring, not Flametongue, not Rockbiter, not Ancestral
Spirit. **SUPERSEDED 2026-10-20**: this sentence used to end "…, not Nature's
Wrath" — there is **no Nature's Wrath in any wowsims shaman sim**; 17364 is
Stormstrike on every family (§0.0 **S1**).

### 5.2 APL priority list, per family

**ERA — `wowsims/classic ui/enhancement_shaman/apls/default.apl.json`**: 0 =
10442 r4 **Strength of Earth Totem** (`tbc-new` data: 10442 = "Strength Of Earth
Totem"); 1 = 10614 r3 Windfury Totem; 2 = 10627 r2 **Grace of Air Totem**;
3 = autocast; 4 = 17364 r1 **Stormstrike** — **SUPERSEDED 2026-10-20**: this
line used to say "**Nature's Wrath**" and then hedge that "the name is
**Stormstrike**'s id in the SoD/Wrath sims and Nature's Wrath in the Era APL".
The hedge is the error: **17364 is Stormstrike on every family** and no
wowsims shaman sim has a Nature's Wrath ability at all
(`wowsims/classic sim/shaman/stormstrike.go:20`; §0.0 **S1**);
5 = 10438 r6 Searing Totem; 6 = 10414 r7 Lightning Bolt. Prepull: 10442, 10614,
10627, 10438.

**SoD — `wowsims/sod ui/enhancement_shaman/apls/phase_6.apl.json`**: 0 = 440580
**Feral Spirit** (SoD rune); 1 = autocast; 2 = 425336 Shamanistic Rage
(`sod sim/shaman/shamanistic_rage.go:14`); 3 = 408490 **Lava Burst** (SoD rune);
4 = 17364 r1 Stormstrike; 5 = 408507 **Lava Lash** (SoD rune); 6 = 15208 r10
Lightning Bolt; 7 = 10605 r4 Chain Lightning; 8 = 10432 r7 **Lightning Shield**
(`tbc-new` data: 10432 = Lightning Shield); 9 = 29228 r6 **Flame Shock**
(`tbc-new` data: 29228 = Flame Shock); 10 = 10414 r7 Lightning Bolt;
11 = 425339 Molten Blast; 12 = 10438 r6 Searing Totem. Prepull: 10432, 10497
**Mana Spring Totem**, 25359 Windfury Totem, 25361 **Strength of Earth Totem**,
10438, 20572 Blood Fury, 26297, item.

**TBC — `wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json`**:
0 = group `Shamanistic Rage` → 30823 r1; 1 = 17364; 2 = group `Fire Elemental`
→ strict sequences (2894); 3 = group `Totems` → 25587 r5 Windfury Totem,
25359 r3 **Grace of Air Totem**, 25528 **Strength of Earth Totem**,
25570 **Mana Spring Totem**; 4 = autocast; 5 = castAllStatBuffCooldowns;
6 = group `Shocks` → 25457 r7 Flame Shock, 25464 r5 Frost Shock,
25454 r8 Earth Shock; 7 = group `Fire Totems` → 25537 Fire Nova Totem,
25550 r5 **Magma Totem**, 25530 r7 Searing Totem. Prepull: 25587, 25528, 25570,
25537, 25359, 35476.

**Forever — `wowsims/forever ui/specs/shaman/enhancement/apls/default.apl.json`**:
0 = `OtherActionResourcePotion` (mana < 80 %); 1 = item 12662 (mana < 70 %);
2 = autocast; 3 = 25359 Grace of Air Totem (air slot);
4 = 25361 Strength of Earth Totem (earth slot); 5 = 408345 (**UNCONFIRMED**);
6 = 10432 Lightning Shield; 7 = 10438 Searing Totem (fire slot); 8 = 17364;
9 = 15208 Lightning Bolt; 10 = 29228 Flame Shock; 11 = 10414 Lightning Bolt;
12 = 408345 (mana > 10 %). Prepull: 25359, 16387 **Flametongue Totem**
(`tbc-new` data: 16387 = "Flametongue Totem"), 25361, 10497 Mana Spring Totem.

**WotLK — `wowsims/wotlk ui/enhancement_shaman/apls/default_wf.apl.json`**: 0 =
51533 Feral Spirit (`wotlk sim/shaman/feral_spirit.go:16`); 1/2 = 2825
Bloodlust; 3 = autocast; 4/5 = 49238 **Lava Lash** (`wotlk
sim/shaman/lightning_bolt.go:17` carries 49238 — the *Lightning Bolt* id in
WotLK; the APL's 49238 is the **Lightning Shock/Lava Lash** pair per the
shipped table); 6 = 17364 Stormstrike; 7 = 49233 **Flame Shock**;
8 = 49231 **Earth Shock** — **SUPERSEDED 2026-10-20**: this line used to say
"49231 **Lightning Shock**"; the WotLK client has **no Lightning Shock** —
49231 is Earth Shock, 49233 is Flame Shock and 49236 is Frost Shock
(`wowsims/wotlk sim/shaman/shocks.go:52,62,115`; §0.0 **S3**);
9 = 66842 **Call of the Elements** (`wotlk sim/shaman/totems.go:157`);
10 = 58734 **Magma Totem** (`wotlk sim/shaman/fire_totems.go:62`);
11 = 61657 **Fire Nova** (`wotlk sim/shaman/firenova.go:16`);
12 = 49281 Lightning Shield (`wotlk sim/shaman/lightning_shield.go:15`);
13 = 60103 Lava Lash (`wotlk sim/shaman/lavalash.go:48`). Prepull: 66842.

### 5.3 Missing lines

| proposed key | spell | ids per family | family gate | APL position | state needed | probe |
|---|---|---|---|---|---|---|
| `strength_of_earth` | Strength of Earth Totem | 10442 r4 (Era) / 25528 (TBC) / 25361 (Forever) | Era, TBC, Forever (+SoD prepull 25361) | Era i=0; TBC i=3.g.2; Forever i=4 | *player totem aura* | **NEW PROBE** — the totem clock is `api.GetTotemInfo(slot)` (`compat.lua:1194`), but the shaman's own guide already reads the *fire* and *air* totems that way; the **earth** slot read is the same wrapper. (SoD prepull also carries it.) |
| `mana_spring` | Mana Spring Totem | 10497 (SoD prepull, Forever prepull) / 25570 (TBC) | SoD, TBC, Forever | TBC i=3.g.3 | *player totem aura* | **NEW PROBE** — `api.GetTotemInfo(slot)` on the mana-totem slot. |
| `flametongue` | Flametongue Totem | 16387 (r4 — the Forever pre-pull row) | Forever | Forever prepull | *player totem aura* | **NEW PROBE** — `api.GetTotemInfo(slot)` on the fire slot (the Flametongue Totem is a totem, not a weapon imbue). **SUPERSEDED 2026-10-20**: this cell used to read "16387 (Forever prepull) / 29228 (the TBC/SoD 'Flametongue Weapon' id)" with the gate "Forever, TBC, SoD"; **29228 is Flame Shock rank 6**, not a weapon imbue, and no fetched APL has a Flametongue-weapon row (§0.0 **S2**). |
| ~~`nature_wrath`~~ → the Stormstrike row | **Stormstrike** (not Nature's Wrath) | 17364 | Era, SoD, TBC, Forever, Wrath | Era i=4; SoD i=4; TBC i=1; Forever i=8; Wrath i=6 | *player buff aura* | **SUPERSEDED 2026-10-20** — **REFUTED**: 17364 is **Stormstrike** on every family (`wowsims/classic sim/shaman/stormstrike.go:20`); **no wowsims shaman sim has a Nature's Wrath ability at all**, so there is no separate line to build. The APL's row is the Stormstrike row the table already carries (§0.0 **S1**). |
| `ancestral_spirit` | Ancestral Spirit | (the classic-era Strength-of-Earth line; **not** in any fetched APL as a separate id) | — | — | — | not an APL line — see §5.4. |
| `fire_elemental` | Fire Elemental Totem | 2894 | TBC, WotLK | TBC i=2 group `Fire Elemental`; WotLK (the `auraInact(2894)` gate on the Magma row) | *player buff aura* | The shipped `fireele` row already carries it (WRATH, TBC) — **present**. |
| `frost_shock` | Frost Shock | 25464 r5 | **TBC only** | TBC i=6.g.1 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(25464)`. The shipped table has `earthshock` and `flameshock` but **no Frost Shock** — and the TBC APL's "FillerShock" variable can be set to Frost Shock. |
| ~~`rockbiter`~~ | **not an APL row** | — | — | — | — | **SUPERSEDED 2026-10-20** — **REFUTED**: this row cited **10497 as the Rockbiter Weapon id**; 10497 is **Mana Spring Totem rank 4** (`wowsims/classic sim/shaman/water_totems.go`). Neither the SoD nor the Forever APL pre-pull carries a Rockbiter row, so there is no APL row to build (§0.0 **S4**). |
| `frostbrand` | Frostbrand Weapon | (not in any fetched APL) | — | — | — | not an APL line — see §5.4. |
| `bloodlust` | Bloodlust | 2825 | WotLK (the druid's TBC row too, but the shaman's TBC APL has no Bloodlust row) | WotLK i=1,2 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(2825)`. |
| `lava_burst` | Lava Burst | 408490 | **SoD only** | SoD i=3 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(408490)`. |
| `molten_blast` | Molten Blast | 425339 | SoD (the shipped row says ERA, which is the SoD rune on the ERA token) | SoD i=11 | *cooldown ready* | **PROBE EXISTS** — the shipped `moltenblast` row carries 425339. |
| ~~`flametongue_weapon`~~ → `flameshock` | **Flame Shock** (rank 6 — not the Flametongue Weapon) | 29228 | SoD, TBC, Forever | SoD i=9; TBC (the `Shocks` group, 25457 r7 is the other rank); Forever i=10 | *cooldown ready* | **SUPERSEDED 2026-10-20** — **REFUTED**: 29228 is **Flame Shock rank 6** on the Forever client (`FlameShock: spelldata.Ranked(8050, 8052, 8053, 10447, 10448, 29228)`). The SoD APL's i=9 and the Forever APL's i=10 are **Flame Shock** rows, and the TBC APL's `Shocks` group carries 25457 r7 (Flame Shock), 25464 r5 (Frost Shock) and 25454 r8 (Earth Shock) — the `flametongue_weapon` row is withdrawn (§0.0 **S2**). |

### 5.4 Correctly absent

* **Ancestral Spirit (10442) in the TBC client** — the TBC APL's `Totems` group
  carries 25587 (Windfury), 25359 (Grace of Air), 25528 (Strength of Earth),
  25570 (Mana Spring). No Ancestral Spirit. Correctly absent.
* **Frostbrand / Rockbiter as *rotation* rows on Era** — the Era APL has six
  rows (Strength of Earth, Windfury, Grace of Air, autocast, **Stormstrike**,
  Searing Totem, Lightning Bolt). No weapon-imbuff row. Correctly absent.
  **SUPERSEDED 2026-10-20**: the list used to say "Nature's Wrath" where it
  means **Stormstrike** (17364) — there is no Nature's Wrath in any wowsims
  shaman sim (§0.0 **S1**).
* **Windfury Totem on SoD/Forever as a rotation row** — the SoD prepull casts
  25359 and the Forever prepull casts 25359, but the *priority lists* carry the
  air slot as Grace of Air (25359 is **Grace of Air Totem** in the tbc-new
  data — the id is the air-slot totem and its meaning is family-gated). The
  shipped table already carries `wftotem` (ERA) and `twist` (TBC) with the
  `WEAVE_WF_TOTEM_SPELL_ID` / `WEAVE_WINDFURY_TOTEM_SPELL_ID` split — present.
* **Call of the Elements on non-Wrath** — the shipped `coe` row is WRATH-only
  and only the WotLK APL carries 66842. Correctly as shipped.
* **Fire Nova on Era** — the Era APL has no Fire Nova row. The shipped
  `firenova` row is TBC/WRATH/FOREVER. Correctly as shipped.
* **Shamanistic Rage's `UseSRwhen` variable** (TBC i=0) — a sim tuning
  variable, not a rotation decision; the shipped `shamanisticrage` row is
  already there.

### 5.5 Priority conflicts

* **The TBC `TwistWindfuryTotem?` / `TwistFireNova?` / `TwistFlameShock?`
  variables** (TBC i=3.g.0, i=6.g.0, i=7.g.0) change what the air/fire slots
  mean from run to run. The shipped table splits `twist` (TBC) from `wftotem`
  (ERA) — the right shape, but the TBC row's `id` note is
  `WEAVE_WINDFURY_TOTEM_SPELL_ID` **UNCONFIRMED** (8512) while the sim's own
  TBC data says the air-slot totem is **25587 / 25359**, not 8512. The shipped
  id is stale against the sim. **SUPERSEDED 2026-10-20 — re-scoped**: 8512 is
  a real **Windfury Totem rank-1** id (the client's rank-1 fallback, not a
  wrong spell), so the shipped row is not *wrong*; what the sim's own ranks
  (25587 r5 Windfury / 25359 r3 Grace of Air) buy is filed, not a correction
  (§0.0 **S5**).
* ~~**17364 carries two different auras** (Nature's Wrath in the Era/TBC APLs,
  Stormstrike in the SoD/Wrath sims) — a `nature_wrath` rotation line must be
  family-gated, and the Stormstrike row that already exists must not be
  confused with it.~~ **SUPERSEDED 2026-10-20 — REFUTED**: 17364 is
  **Stormstrike on every family** and no wowsims shaman sim has a Nature's
  Wrath ability. There is one aura, one id, one row — the existing Stormstrike
  line (§0.0 **S1**).

---

## 6. PALADIN

### 6.1 Shipped rotation table — current action keys

`classes/paladin.lua:4173-4213` builds the table from
`ST.PALADIN.practice_orders` = the twist order (`:4146`) plus the five FCFS
tables published by `nextaction.lua:953-982`:

| order id | keys in priority order | source |
|---|---|---|
| `twist` | `cs`, `judge`, `twist`, `soc`, `sob`, `cons`, `exo`, `how` | `classes/paladin.lua:4146` |
| `wrath` | `cs`, `judge`, `ds`, `cons`, `exo`, `hw` | `nextaction.lua:953` |
| `sod` | `exo`, `cs`, `ds`, `judge`, `cons`, `how` | `nextaction.lua:954` |
| `sod_stack` | `ds`, `cs`, `exo`, `hw`, `cons`, `judge` | `nextaction.lua:966` |
| `sod_shock` | `exo`, `am`, `hs`, `cs` | `nextaction.lua:967` |
| `sod_wrath` | `ds`, `cs`, `exo`, `judge`, `cons` | `nextaction.lua:968` |

Union of keys: **12** — `cs`, `judge`, `twist`, `soc`, `sob`, `cons`, `exo`,
`how`, `ds`, `hw`, `am`, `hs`. All of them are damage, seals, judgements or
the two shockadin cooldowns. **No defensive, no aura, no utility, no
movement.**

### 6.2 APL priority list, per family

**ERA — `wowsims/classic ui/retribution_paladin/apls/basic_ret.apl.json`**:
0 = 20271 Judgement; 1 = `castPaladinPrimarySeal` (the primary-seal macro);
2 = 20375 r1 Seal of the Crusader (twist) `IF autoTimeToNext < 0.4s AND aura 20293`;
3 = 20293 r8 Seal of Righteousness (twist) `IF autoTimeToNext < 0.4s AND aura
20375`. Prepull: `castPaladinPrimarySeal` @−1.5 s.

**SoD — five APLs, one per build.** `p8-twist.apl.json`: 0 = wait (the swing
timer branch); 1 = cancelAura; 2 = autocast; 3 = item 241241; 4 = 20271
Judgement; 5/6 = `paladinCastWithMacro` (the twist cast); 7 = 24239 r3 Hammer
of Wrath; 8-15 = strict sequences (the twist + filler casts); 16-20 =
`paladinCastWithMacro` (the fillers).
`p8-exodin.apl.json`: 0 autocast; 1 = item 241241; 2 = 20271 Judgement;
3 = `castPaladinPrimarySeal`; 4 = **407778 Divine Storm**
(`wowhead /classic/` id, confirmed by the SoD sim's `sim/paladin/divine_storm.go`);
5 = wait; 6 = **415073 Exorcism**; 7 = **407676 Crusader Strike**.
`p8-stack.apl.json`: 0 autocast; 1 = item 241241; 2 = 20920 r5 **Seal of
Martyrdom**; 3 = **407798 Seal of Martyrdom** (the SoD rune rank);
4 = 407778 Divine Storm; 5 = 407676 Crusader Strike; 6 = 415073 Exorcism;
7 = 10318 r2 **Holy Wrath** (Undead only, `auraKnown(1219193)` + Undead target);
8 = 20924 r5 Consecration; 9 = 20271 Judgement.
`p8-shockadin-1h.apl.json`: 0 = item 241037; 1 = **16322 Purity**; 2 autocast;
3 = item 241241; 4 = 20271 Judgement; 5 = `castPaladinPrimarySeal`;
6 = **407624 Aura Mastery**; 7 = **20930 r3 Holy Shock**; 8 = 415073 Exorcism;
9 = 407624 Aura Mastery; 10 = 20930 r3 Holy Shock; 11 = 407676 Crusader Strike.
`p8-wrath.apl.json`: 0 autocast; 1 = item 241037; 2 = 16322 Purity; 3 = item
241241; 4 = 20271 Judgement; 5 = `castPaladinPrimarySeal`; 6 = wait;
7 = 407778 Divine Storm; 8 = 407676 Crusader Strike; 9 = 415073 Exorcism;
10 = 407778 Divine Storm; 11 = 20271 Judgement; 12 = 20924 r5 Consecration.

**TBC — `wowsims/tbc-new ui/specs/paladin/retribution/apls/default.apl.json`**:
0 = autocast (behind the 11 s "Delay Major CDs" variable); 1 = 31892 r1
**Seal of Blood** `IF aura 20375 AND autoTimeToNext <= .4s`; 2 = 35395 **Crusader
Strike** `IF aura 31892`; 3 = 20271 Judgement; 4 = group `ExoOrConsec` →
27138 r7 **Exorcism** / 27173 r6 **Consecration**; 5 = 20375 r1 **Seal of
Command** (reseal guard). Prepull: 20218 **Sanctity Aura** @−18.5 s, group
`PrepullSeal` @−1.5 s, group `PrepullJudge` @0 s, group `PullSeal` @0 s.

**Forever — `wowsims/forever ui/specs/paladin/retribution/apls/twist_of_light.apl.json`**:
0 autocast; 1 = 20271 Judgement; 2 = 24239 r3 Hammer of Wrath
(`spellCastTime == 0 OR autoTimeSinceLast < 0.2s`); 3 = **10333 r8 Holy
Strike** (`currentTime > 0.5s`) — `forever sim/paladin/holy_strike.go:12`
cites `https://www.wowhead.com/forever/spell=10333`; 4 = 20920 r5 Seal of
Command; 5 = 20293 r8 Seal of Righteousness; 6 = group `Consecration` → 20924
r5; 7 = group `Exorcism` → 10314 r6. Prepull: 10301 @−10 s, 20920 r5 @−3 s,
20308 r6 @−1.5 s.
**`holy_shock.apl.json`**: 0 autocast; 1 = 20271 Judgement; 2/3 = itemSwap;
4 = 20924 r5 Consecration; 5 = 24239 r3 Hammer of Wrath; 6 = 20293 r8 Seal of
Righteousness; 7 = 10333 r8 Holy Strike; 8 = **20216 Devotion Aura**
(`forever sim/paladin/devotion_aura.go:8-18`); 9 = 20930 r4 Holy Shock;
10 = 10314 r6 Exorcism. Prepull: 10301 @−10 s, 20308 r6 @−1.5 s.

**WotLK — `wowsims/wotlk ui/retribution_paladin/apls/default.apl.json`**:
0 autocast; 1 = **67485 Hand of Reckoning** (`wotlk
sim/paladin/hand_of_reckoning.go:16`); 2 = **48806 Hammer of Wrath** (`wotlk
sim/paladin/hammer_of_wrath.go:12`); 3 = **53408 Judgement of Light** (`wotlk
sim/paladin/judgement.go:22`); 4 = 35395 Crusader Strike (`wotlk
sim/paladin/crusader_strike.go:18`); 5 = **53385 Divine Storm** (`wotlk
sim/paladin/divine_storm.go:16`); 6 = 48801 Exorcism (`wotlk
sim/paladin/exorcism.go:12`) `IF aura 53488`; 7 = 48819 Consecration (`wotlk
sim/paladin/consecration.go:19`) `IF remainingTime > 4s`.

### 6.3 Missing lines

| proposed key | spell | ids per family | family gate | APL position | state needed | probe |
|---|---|---|---|---|---|---|
| `hor` | Hand of Reckoning | 67485 | **WRATH only** | WotLK i=1 — the APL's **top** priority | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(67485)` (`compat.lua:229`). |
| `how_wrath` | Hammer of Wrath (WotLK) | 48806 | **WRATH only** | WotLK i=2 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(48806)`. **The shipped `wrath` order has no Hammer of Wrath at all** — its `how` key is only in the `twist` and `sod` orders (`classes/paladin.lua:4146`, `nextaction.lua:954`). |
| `jOL` | Judgement of Light | 53408 | **WRATH only** | WotLK i=3 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(53408)`. |
| `holy_strike` | Holy Strike | 10333 r8 | **FOREVER only** | Forever twist i=3; holy_shock i=7 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(10333)`. This is the same gap the earlier audit already filed (`bench/paladin_rotation_audit_2026-10-19.md:169-173`: "Sim casts Holy Strike (10333r8) … we do not probe it"). |
| `devotion_aura` | Devotion Aura | 20216 | **FOREVER only** | Forever holy_shock i=8 | *player buff aura* | **NEW PROBE** — `api.scan_player_aura` on 20216 (`compat.lua:514`). |
| `purity` | Purity | 16322 | **SoD only** (the shockadin + wrath-like builds) | p8-shockadin-1h i=1; p8-wrath i=2 | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(16322)`. |
| `sanctity_aura` | Sanctity Aura | 20218 | **TBC only** | TBC **prepull** @−18.5 s | *player buff aura* | **NEW PROBE** — `api.scan_player_aura` on 20218. |
| `redemption` | Redemption | 10301 | **FOREVER only** (prepull @−10 s) | Forever prepull | *cooldown ready* | **NEW PROBE** — `api.GetSpellCooldown(10301)`. **UNCONFIRMED** name: the TBC data maps 10301 to "Retribution Aura", and the Forever prepull's name is not pinned by any fetched sim file. |
| `seal_renew` | the primary-seal macro | (the `castPaladinPrimarySeal` / `castPaladinPrimarySeal` action) | Era, SoD | Era i=1; p8-exodin i=3; p8-shockadin i=5; p8-wrath i=5 | *seal aura remaining* | The shipped `soc`/`sob`/`twist` keys already carry the seal work; the **reseal** line is in the engine (`nextaction.lua`), not in the rotation table. Present as a decision, absent as a line. |
| `sotc` | Seal of the Crusader | 20375 (Era, SoD) — the **same id** is Seal of Command on TBC | **Era, SoD** (on TBC the 20375 row is the `soc` line, not SoC) | Era i=2 (the twist's SoC side) and i=1 (the primary-seal macro) | *player seal aura* | **NEW PROBE** — `api.scan_player_aura` on 20375 (`compat.lua:514`). The **label exists** (`classes/paladin.lua:4099` `sotc = "Seal of the Crusader"`) but **no shipped order names the key**, so the Seal of the Crusader has no rotation line on any family. |
| `divine_storm` | Divine Storm | 407778 (SoD) / 53385 (WotLK) | SoD, WotLK | p8-exodin i=4; p8-stack i=4; p8-wrath i=7,10; WotLK i=5 | *cooldown ready* | The shipped table has `ds` — **present**, and the SoD/Wrath ids are split correctly by family in the engine's own tables (`nextaction.lua:953-968`). |
| `exorcism` | Exorcism | 415073 (SoD) / 27138 (TBC) / 10314 (Forever) / 48801 (WotLK) | SoD, TBC, Forever, WotLK | p8-exodin i=6; TBC i=4.g.0; Forever i=7.g.0 / holy_shock i=10; WotLK i=6 | *cooldown ready* | The shipped `exo` key — **present**. |
| `crusader_strike` | Crusader Strike | 407676 (SoD) / 35395 (TBC, WotLK) | SoD, TBC, WotLK | p8-exodin i=7; TBC i=2; WotLK i=4 | *cooldown ready* | The shipped `cs` key — **present**. |
| `consecration` | Consecration | 20924 r5 (SoD, Forever) / 27173 r6 (TBC) / 48819 (WotLK) | SoD, TBC, Forever, WotLK | p8-stack i=8; p8-wrath i=12; TBC i=4.g.1; Forever i=6.g.0; WotLK i=7 | *cooldown ready* | The shipped `cons` key — **present**. |
| `aura_mastery` | Aura Mastery | 407624 | **SoD only** | p8-shockadin-1h i=6,9 | *rune known* + cooldown | The shipped `am` key — **present** (`classes/paladin.lua:407624` is already in the tree, `classes/paladin.lua:2503`). |
| `holy_shock` | Holy Shock | 20930 r3 (SoD) / 20930 r4 (Forever) | SoD, Forever | p8-shockadin-1h i=7,10; Forever holy_shock i=9 | *cooldown ready* | The shipped `hs` key — **present**. |
| `holy_wrath` | Holy Wrath | 10318 r2 | **SoD only** (the stack build) | p8-stack i=7 | *cooldown ready* + Undead target | The shipped `hw` key — **present**, and its gate (Undead/Demon) is already in `nextaction.lua:1092-1107`. |

### 6.4 Correctly absent

* **Holy Wrath on the WotLK family** — the WotLK APL has **no** Holy Wrath row;
  the WotLK damage row is Exorcism (48801) and Consecration (48819). The
  shipped `hw` key is in the `wrath` order (`nextaction.lua:953`) **and** in
  `sod_stack` (`:966`) but is *absent* from `sod` (`:954`), `sod_shock` (`:967`)
  and `sod_wrath` (`:968`) — which matches the SoD APLs, where only
  `p8-stack` carries 10318. **But the Wrath order's `hw` is the one line whose
  presence the WotLK APL does not support** — see §6.5.
* **Consecration / Exorcism as *default-on* fillers** — the TBC APL has them
  behind the `Use Consecration` / `Use Exorcism` variables (default **false**,
  per `bench/paladin_rotation_audit_2026-10-19.md:109-114`). The shipped order
  has `cons`/`exo` in the `twist` order unconditionally. A line whose sim
  condition defaults it OFF is not a line to prompt by default — correctly
  absent *as a default*, and the engine's own "filler" gate already carries it.
* **The `itemSwap` rows** (Forever holy_shock i=2,3) — the sim's weapon-swap
  machinery, not a rotation decision. Correctly absent.
* **Hand of Reckoning outside WotLK** — WotLK only.
* **Devotion Aura / Holy Strike outside Forever** — Forever only.

### 6.5 Priority conflicts (the paladin's order is the weakest of the six)

1. **The Wrath order is missing the APL's top two rows.** The WotLK APL is
   `Hand of Reckoning → Hammer of Wrath → Judgement of Light → Crusader Strike
   → Divine Storm → Exorcism → Consecration`. The shipped `wrath` order is
   `cs, judge, ds, cons, exo, hw` — **no `hor`, no `how`, and `hw` (Holy
   Wrath) is a spell the WotLK APL does not contain at all**. The earlier audit
   (`bench/paladin_rotation_audit_2026-10-19.md:130-137`) matched this order
   against a *Wowhead guide* because "the WotLK sim repo is not among the
   five in-scope repos". The repo exists now, and the sim says the order is
   wrong at both ends.
2. **`judge` on WotLK is Judgement of Light (53408)**, and it sits at APL
   i=3 — *below* Hammer of Wrath. The shipped order puts `judge` at position 2.
3. **Hammer of Wrath's gate is a cast-time window** on Forever
   (`spellCastTime == 0 OR autoTimeSinceLast < 0.2s`, i=2) and unconditional
   on WotLK (i=2) — the shipped `how` key is only in the `twist` and `sod`
   orders, so **the WotLK and Forever Hammer-of-Wrath rows are both absent**.

---

## 7. Cross-class summary

### 7.1 What the six tables have and have not got

| Class | shipped keys | damage/rotation | utility / upkeep | offensive cooldowns |
|---|---|---|---|---|
| Warrior | 13 | op, execute, slam, bt, ww, ms, bladestorm, hamstring, hs, cleave | sunder, rend (2 of ~9) | **0** (no Bloodthirst-tier utility, no Recklessness/Death Wish/Bloodrage) |
| Hunter | 2/3/6/6/3 per family | aimed, multi, steady, arcane, explosive | serpent, aspect (2 of ~9) | kill_command, bestial_wrath, rapid_fire, kill_shot, chimera, hawk, sniper |
| Rogue | 12 | expose, snd, eviscerate, rupture, builder | hfb, shiv (2 of ~8) | ar, bf, coldblood, envenom, tea |
| Druid | 3/9/5/10/9 + BEAR 3 | shred, rip, mangle, rake, bite | ff, roar, tf, sp (4) | berserk |
| Shaman | 18 | weave, shocks, imbues, lavalash, moltenblast, chainlightning | totems (6 of 9) | fireele, feralspirit, sr, coe |
| Paladin | 12 | cs, judge, twist, seals, cons, exo, how, ds, hw | am, hs (2) | 0 |

**The pattern the operator named for the warrior is real on every class:** the
tables are built from the *damage* APL rows and the *upkeep* rows that the
engine already knew, and the **utility layer is missing almost everywhere**:
no shouts, no stances, no racials, no auras, no stealth, no prep-pull
utility, no WotLK cooldown-defensive set, no cooldown-pop utility.

### 7.2 The probe bill (all buildable on existing compat wrappers)

* **Zero new client APIs are needed.** Every missing line's read is an existing
  `compat.lua` wrapper (§0.5). The client-side availability of the two raw
  APIs behind them (`GetSpellCooldown`, `UnitAura`) is cited per branch in
  §0.5.
* **Probes that already exist** (the line is missing, the read is not):
  warrior stance (`classes/warrior.lua:601-625`, `:684`), warrior Battle Shout
  (`:645-658`, `:677`), hunter Serpent Sting (`:2085-2100`, `:2425`), hunter
  Aspect of the Viper (`:252`, `:1015`, `:1026`), druid Tiger's Fury / Berserk
  (`:2071-2088`), paladin Aura Mastery / Holy Shock (`:2503`, `:2475`).
* **New probes** (the read is missing): every remaining line in the six tables
  above. They are all of one of three shapes:
  1. *cooldown ready* → `api.GetSpellCooldown(id)` (`compat.lua:229`),
  2. *player buff up* → `api.scan_player_aura` (`compat.lua:514`),
  3. *target debuff up* → `api.scan_unit_aura` (`compat.lua:569`).
  Every one of them is a one-liner against a wrapper that already exists.
* **Family-gated ids** are the trap, not the probes: `25289` (Battle Shout on
  TBC/Forever, nothing in Era), `20375` (Seal of the Crusader on Era/SoD,
  Seal of Command on TBC), `12292` (Death Wish on TBC, Sweeping Strikes on
  the Forever client — §0.0 **W2**), `14183` (Premeditation on Era/SoD/Wrath
  **and on Forever** — not Shadowstep; §0.0 **R2**), `1857` (Vanish rank 2 on
  TBC/Forever — not Cloak of Shadows; §0.0 **R1**), `9850` (Claw r5 on Era,
  TBC **and** Forever — the Forever client has no Mangle at all; §0.0
  **D1**), `17364` (**Stormstrike on every family** — there is no Nature's
  Wrath; §0.0 **S1**), `29228` (**Flame Shock r6** — not the Flametongue
  Weapon; §0.0 **S2**), `13750` (Adrenaline Rush for the
  rogue, not a potion), `18499` (Berserker Rage, not "Improved Hamstring" as
  the shipped warrior row says). The house mechanism for this is already in
  place: `api.get_family_spell_id` / `api.get_family_spell_id_state`
  (`compat.lua:1533`, `:1495`) and `api.get_spell_query(name, id)`
  (`compat.lua:1544`).

### 7.3 Corrections to existing bench claims this desk found

1. **The warrior's `hamstring` row cites the wrong name for 18499.**
   `classes/warrior.lua:3726-3728` says "the tbc-new fury APL casts 18499 …
   Improved Hamstring (20500) is known". The sim's own file names 18499
   **Berserker Rage** (`classic sim/warrior/berserker_rage.go:14`,
   `tbc-new sim/warrior/berserker_rage.go:10`). 20500 is the *Improved
   Hamstring* **buff** id that the APL only tests for. The TBC APL's
   `18499` row is a Berserker Rage cast, not a Hamstring.
2. **The TBC Overpower weave casts Battle Stance first.** The shipped row
   (`classes/warrior.lua:3644-3648`) already says so — this desk confirms it
   against the group expansion (`tbc-new fury` i=16.g.1 = 2457, i=16.g.2 =
   11585) and adds the SoD/Forever/WotLK equivalents.
3. **The paladin's seal keys are family-specific, and one label has no line.**
   `classes/paladin.lua:4096-4110` defines `soc = "Seal of Command"`,
   `sob = "Seal of Blood / Martyr"`, `sotc = "Seal of the Crusader"`,
   `twist = "Twist"`. **`sotc` appears in no shipped order** — the six orders
   (`classes/paladin.lua:4146`, `nextaction.lua:953-968`) never name it — so
   the **Seal of the Crusader has no rotation line anywhere**, even though the
   Era APL's twist pair is `20375 (SoC) ↔ 20293 (SoR)`
   (`wowsims/classic ui/retribution_paladin/apls/basic_ret.apl.json` i=2,3),
   the TBC APL's reseal row is `20375` (i=5) and the SoD APLs cast `20920` /
   `407798` as their seal rows. And the id itself is family-split: 20375 is
   **Seal of the Crusader** on Era/SoD and **Seal of Command** on TBC
   (`wowsims/tbc-new sim/paladin/spell_data_auto_gen.go`).
4. **The WotLK repo exists and was not in the earlier audits.** It changes the
   paladin's Wrath order (§6.5) and adds the WotLK-only warrior/hunter/rogue
   lines the earlier audits filed as "no sim in scope".

**The 2026-10-20 correction pass added 31 further corrections** on top of the
four above. They are listed with their evidence in **§0.0** at the top of this
file (S1–S5, R1–R9, D1–D4, H1–H9, W1–W4) and are applied in place in the
tables. Two of them changed a *missing-line spec* into a withdrawn row
(`cloak_of_shadows` → `vanish`; `shadowstep` → `premeditation`;
`deadly_poison` → `rupture`; `expose_forever` → `venom`; `nature_wrath` →
the Stormstrike row; `rockbiter` → not an APL row; `flametongue_weapon` →
`flameshock`) and the rest corrected an id, a name or a family gate.

### 7.4 UNCONFIRMED (must not be built on without a source)

**Re-scoped 2026-10-20** (§0.0): four of the ids below are now **named** by
the sims' own data, so they move from "no name at all" to "the name is
confirmed, the **client** confirmation is still owed". The build obligation
is unchanged — an id with no client source is still not client-proved.

* 1310222 (Forever warrior arms APL i=18) — Forever-only, no name in any
  fetched sim file.
* 1317257 (Forever hunter APL i=4) — Forever-only, no name.
* 1259813 (Forever warrior `CD: Racials` group) — Forever-only, no name.
* 408345 (Forever shaman APL i=5, i=12) — Forever-only, no name.
* 409593 (SoD hunter) — the sim files place it under Kill Shot, but the exact
  SoD rank is not pinned. (The name is confirmed: **Kill Shot** — the SoD
  rune, `proto/hunter.proto:153` `RuneLegsKillShot = 409593`.)
* 10301 (Forever paladin prepull) — the TBC table calls 10301 "Retribution
  Aura"; the Forever prepull's meaning is not pinned.
* 1317257 / 14305 / 14271 (Forever hunter melee rows) — the Forever client
  alone.
* **NAMED since this list was written (2026-10-20) — the name is settled, the
  client proof is not:**
  * 1310703 = **Venom** (the Forever client) — was "Forever-only, no name"
    (§0.0 **R7**).
  * 1241584 r4 = **Mutilate rank 4** (the Forever client) — was "a Shadowstep
    rank in the Forever client" (§0.0 **R3**).
  * 1259799 = **"Elune's Light"**, 1259812 = **"Gnome Eureka"** — were
    "Forever-only; 1259812 is Gnome Eureka" (§0.0 **R8**).

### 7.5 How to build from this (suggested order, not a decision)

1. **Per-family id tables first.** Every spec above names at least one id whose
   meaning is family-specific. The tree already has the mechanism
   (`api.get_family_spell_id`). A rotation table that carries one id per
   family is the only shape that survives the family gate.
2. **The three probe shapes** (cooldown / player buff / target debuff) are
   uniform. One helper per shape, then each missing line is a row.
3. **A "utility" section per class table** — the damage rows already exist;
   the utility rows are what the operator is asking for. The APL order is the
   priority order; the table's `families` field is the gate.
4. **The prepull/priority split.** Charge, Intercept, Aspect of the Hawk,
   Sanctity Aura, Blood Fury, Battle Shout, Cat Form, Strength of Earth and
   the weapon-imbuffs are *prepull or upkeep* rows in the APLs, not rotation
   rows. The hunter already has a `PRACTICE_PREPULLS` table
   (`classes/hunter.lua:2921+`); the other five classes have no such table.
   The APL order cannot be represented in a single flat list without that
   split.
5. **Then re-derive the priority positions.** Several shipped orders are not
   the APL's order (§1.5, §2.5, §3.5, §4.5, §5.5, §6.5). The rotation table's
   value is that it *is* the priority list; the current tables are ordered by
   the engine's compiled rule matrix instead.

---

## 8. Validation

* Nothing in the addon tree, the test tree or any other bench file was
  modified by this desk. The only file written is this one.
  **2026-10-20 (`corpus-corrections`):** the *correction pass* that added
  §0.0 edited this file and sixteen other bench files (`bench/*.md` only) and
  touched no `.lua`, no test file, no `desks/` file other than its own desk,
  no `hands-up.md`. No git command was run by that desk either.
* No git command was run.
* Every APL id, index, file path and spell name in this document was read from
  a source fetched in this session on 2026-10-20; the sources are named inline
  with `repo` + `path` + `index` or `file:line`. Anything not pinned by a
  fetched source is in §7.4 in caps.
  **2026-10-20 correction pass:** every id the five utility lanes disproved
  was re-verified against *their* build artifacts, each of which re-fetched
  the same sources on the same day. The correction log (§0.0) names the
  artifact and the citation for all 31 corrections. The paladin section (§6)
  was **not** re-verified — no paladin utility lane has run — and says so.
* The claim "no new client API is needed" is bounded: it covers the missing
  lines listed in §1.3, §2.3, §3.3, §4.3, §5.3 and §6.3 only.
* **Offline only.** Nothing here was loaded in a game client; per `CAIRN.md`
  ("two proofs, two words") this desk has produced a *source-cited* gap
  analysis, not a verified-in-client one.
* **Validation owner: the orchestrator.** The re-check that matters before
  this file is used to build is a mutation-proofed offline pass on
  `/tmp/opencode` copies (a new family id or a new rotation row must break a
  pin), and an in-client pass for every line whose id is marked UNCONFIRMED.

---

## 9. What the 2026-10-20 correction pass changed (summary)

This is the file the correction pass touched most. It is the **seed** of most
of the wrong ids in the corpus: the five utility lanes each took their
class's section from here as a *spec*, then re-fetched the sources and found
the spec wrong. Anyone who copies an id out of a table below now gets the
corrected value, and the superseded value is still visible in the **SUPERSEDED
2026-10-20** marker beside it.

**The corrections, by class:**

* **Shaman (5).** 17364 is **Stormstrike**, not Nature's Wrath (no wowsims
  shaman sim has a Nature's Wrath ability at all) — the `nature_wrath` line
  is withdrawn. 29228 is **Flame Shock r6**, not the Flametongue Weapon — the
  `flametongue_weapon` line is withdrawn. 49231 is **Earth Shock** on WotLK
  (49233 = Flame Shock, 49236 = Frost Shock), not Lightning Shock. 10497 is
  **Mana Spring r4**, not Rockbiter — the `rockbiter` line is withdrawn (it
  was never an APL row). 8512 is a real Windfury Totem **rank-1** id (the
  client's fallback), not a wrong spell; the TBC APL's own ranks are
  25587 / 25359 — filed, not a correction.
* **Rogue (9).** 1857 is **Vanish rank 2** on TBC/Forever, not Cloak of
  Shadows (the spell does not exist on either client) — the
  `cloak_of_shadows` line is withdrawn. 14183 is **Premeditation** on
  Forever too, not Shadowstep — the `shadowstep` line is withdrawn. 1241584
  is **Mutilate r4**, not a Shadowstep rank. The **Era and TBC APLs carry no
  Vanish row at all** (the `vanish` gate is wrong). 26867 is **Rupture** on
  TBC, not Deadly Poison — the `deadly_poison` line is withdrawn. 51662 is
  **Hunger for Blood**, not Mutilate. 1310703 is **Venom**, not the Forever
  Expose — the `expose_forever` line is withdrawn. 1259799 = "Elune's Light"
  and 1259812 = "Gnome Eureka" (both named). 14278 = **Ghostly Strike**.
* **Druid (4).** 9850 is **Claw r5** on Era, TBC *and* Forever — the
  "9850 = Mangle on TBC/Forever" family split was wrong, and the **Forever
  client has no Mangle at all** (no `mangleNow` in the Forever repo). The
  Era APL's `[1]` row casts **13494 = "Haste"** on the 1.15 client; the
  client's Leader of the Pack is **17007**. The **Era APL has no Rip row**.
* **Hunter (9).** WRATH `kill_shot` = **61006** (not 53351); WRATH
  `explosive` = **60053** (not 53301); TBC `steady` = **34120** (56641 does
  not exist on TBC); the **Forever client has no Steady Shot** and the row
  was removed. 61847 = **Aspect of the Dragonhawk**, not the Aspect of the
  Wild. 25296 = **Aspect of the Hawk**, not the Aspect of the Cheetah (5118).
  The Forever Hawk is a **pre-pull** row, not a rotation row. `kill_shot`'s
  SoD id is the rune **409593** (14287 is Arcane Shot), and the Era APL has
  **no** Arcane Shot row.
* **Warrior (4).** The Sweeping Strikes id "12292 / 12723 (TBC)" was wrong:
  **12292 is Death Wish on TBC and Sweeping Strikes on the Forever client**,
  and both APLs cast 12723. 33697 is **Blood Fury rank 2** — a rank of the
  same spell, not a different spell. 18499 is **Berserker Rage**, not
  Improved Hamstring (this file already said so; the wrong claim lives in two
  other corpus files, both now corrected). **25212 is the TBC Hamstring**,
  not "Devastate" (three corpus files carried the wrong name; all three are
  corrected).

**Also re-scoped:** §7.4's UNCONFIRMED list — 1310703, 1241584, 1259799 and
1259812 are now *named* by the sims' own data, so they move from "no name" to
"the name is confirmed, the client proof is still owed". The build obligation
is unchanged.

**Not corrected, on purpose:** §6 (the paladin). No paladin utility lane has
run, so the paladin ids in this file stand as written. §7.2's probe bill,
the APL priority listings, the "correctly absent" lists and the priority
conflicts stand as written.

**The other sixteen bench files corrected** (all `bench/*.md`, no `.lua`):
`bench/class_features_drills_2026-10-19.md`,
`bench/warrior_practice_2026-10-19.md`,
`bench/warrior_hs_queue_2026-10-20.md`,
`bench/rogue_rotation_audit_2026-10-19.md`,
`bench/open_rules_2026-10-19.md`,
`bench/rogue_hunter_eratbc_2026-10-19.md`,
`bench/filed_closure_sweep_2026-10-19.md`,
`bench/ids_research_2026-10-19.md`,
`bench/perclass_hud_guide_verify_2026-10-19.md`,
`bench/shaman_rotation_audit_2026-10-19.md`,
`bench/hunter_rotation_audit_2026-10-19.md`,
`bench/rogue_drills_rotation_2026-10-19.md`,
`bench/rogue_rotation_gaps_closed_2026-10-19.md`,
`bench/shaman_drills_2026-10-19.md`,
`bench/rogue_research_2026-10-19.md`,
`bench/hunter_practice_designer_2026-10-19.md`.
Each carries a dated note naming the old value and the evidence.

**One extra defect found and fixed beyond the lanes' named corrections:** the
corpus's **TBC rogue Sinister Strike / Hemorrhage pairing was swapped**
(26862 = Sinister Strike, 26864 = Hemorrhage). `bench/filed_closure_sweep_2026-10-19.md`
§9-N1 had found it on 2026-10-19 and it was never applied; the rogue APL build
lane's sim-sourced TBC table agrees (`hemorrhage` 26864 / `backstab` 26863 /
`mutilate` 34413). Fixed in the three places N1 named —
`bench/class_features_drills_2026-10-19.md` (R-03),
`bench/rogue_rotation_audit_2026-10-19.md` (§1's TBC builder branch) and
`bench/ids_research_2026-10-19.md` (U10).
