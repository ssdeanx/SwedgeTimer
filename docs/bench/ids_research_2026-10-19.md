# ids research — spell/icon/aura/rune gaps with sourced evidence — 2026-10-19

Desk: ids-research. READ-ONLY: no addon file touched, no git, no bench file
overwritten (this file is NEW — confirmed absent before writing).
Method: gap list compiled from `bench/*_rotation_audit_2026-10-19.md` +
`bench/open_rules_2026-10-19.md` + `bench/hunter_open_2026-10-19.md`;
each id checked via searxng search this session + firecrawl scrape where
noted (small bodies). Evidence bar: WEB-CONFIRMED = wowhead page exists
with matching name/effect (URL quoted); SIM-CONFIRMED = wowsims raw file
fetched by an earlier lane (URL in the audit, not re-fetched here);
CLIENT-UNCONFIRMED = still needs in-client `GetSpellInfo`/probe.
Validation owner: orchestrator.

> **⚠ CORRECTED 2026-10-20 (desk `corpus-corrections`).** The five
> utility-layer build lanes (`warrior-apl`, `hunter-apl`, `rogue-apl`,
> `druid-apl`, `shaman-apl` — all 2026-10-20) re-fetched the wowsims
> sources and **named** several ids this file had left in the
> "Still-UNCONFIRMED" list, and **disproved** one pairing this file
> inherited. The changes:
>
> * **U10's TBC pair was swapped** — this file's list carries the ids in the
>   order "26864/26863/34413/26862/…", which the corpus read as
>   "SS 26864 … Hemo 26862". The client's own wowhead redirect slugs say the
>   opposite: **26862 = Sinister Strike, 26864 = Hemorrhage**
>   (`bench/filed_closure_sweep_2026-10-19.md` §9-N1), and the rogue APL
>   build lane's sim-sourced TBC table agrees — `hemorrhage` 26864 /
>   `backstab` 26863 / `mutilate` 34413
>   (`bench/rogue_apl_utility_build_2026-10-20.md` §1.1 rows 34-36).
> * **U9/U10/U12 — names now settled** (the *client* proof is still owed, so
>   the "SIM-CONFIRMED only" status stands): 1310703 = **Venom**,
>   1241584 = **Mutilate rank 4**, 14183 = **Premeditation**,
>   1857 = **Vanish rank 2** (TBC/Forever — not Cloak of Shadows),
>   1259799 = **"Elune's Light"**, 1259812 = **"Gnome Eureka"**,
>   14278 = **Ghostly Strike** (all from the Forever spell data —
>   `bench/rogue_apl_utility_build_2026-10-20.md` §3).
> * **U12's shaman set** — 17364 was already correct here (Stormstrike);
>   the corrections are that **29228 = Flame Shock r6** (not a Flametongue
>   Weapon), **49231 = Earth Shock** on WotLK (49236 = Frost Shock) and
>   **10497 = Mana Spring Totem r4** (not Rockbiter) —
>   `bench/shaman_apl_utility_build_2026-10-20.md` §2 C2/C3/C4.
> * **The hunter's Wrath/TBC ranks** — the WotLK APLs cast **61006** (Kill
>   Shot) and **60053/60052** (Explosive Shot), the TBC APL casts **34120**
>   (Steady Shot) and **56641 does not exist on the TBC client**, and the
>   **Forever client has no Steady Shot at all** —
>   `bench/hunter_apl_utility_build_2026-10-20.md` §3.
> * **The druid's 9850** — Claw r5 on Era, TBC **and** Forever; the **Forever
>   client has no Mangle at all** —
>   `bench/druid_apl_utility_build_2026-10-20.md` §5.1.
> * **The warrior's 18499 / 12292 / 33697** — 18499 = **Berserker Rage**,
>   12292 = **Death Wish on TBC / Sweeping Strikes on Forever**, 33697 =
>   **Blood Fury rank 2** —
>   `bench/warrior_apl_utility_build_2026-10-20.md` §1/§4.
>
> The full log — 31 corrections, each with its old value and its evidence —
> is `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0.

## 1. Gap list compiled (inputs)

- Hunter: SoD runes (415413/415399/409433/415423), Wrath ranks
  (60053/60052/49052/56344/23989/53304/53220/53209), TBC ranks
  (34120/27021/27019/34026/34074/27044), Forever ids
  (1310687s/1293241s/1293248/1312639 + bonus kit), hawk-count source.
- Open-rules: TBC EA 26866r6, Forever EA 11198, Victory Rush 34428,
  Victorious aura id, TBC shaman FS fight>=12s, p4-twist path.
- Shaman UNCONFIRMED: 16387, 25361, 25570, 425339, SoD SS 6s CD trigger.
- Paladin Forever: Echo 1311703/1311704, Holy Strike, HoW/Exo/Cons ranks.
- Warrior: BT 23894, WW 1680, Execute 25236/20662, HS/Cleave ranks, VR/aura.
- Druid: Wolfshead 8345, Berserk 417141, SP ceiling/CD.
- Rogue: SoD Envenom rune 399963 (+399956/424785/425012), per-client EA/TEA/Shiv/builder ids.

## 2. CONFIRMED table (web-verified this session)

| id | name | source URL | evidence | client applicability |
|---|---|---|---|---|
| 399963 | Envenom (Rune of Venom, legs) | https://www.wowhead.com/classic/spell=399963/envenom | scrape OK (35 Energy, Nature, Deadly Poison ref) | SoD (ERA family) |
| 399956 | Mutilate (Rune of Mutilation, gloves) | https://www.wowhead.com/classic/spell=399956/mutilate | search snippet | SoD |
| 424785 | Saber Slash (gloves rune) | https://www.wowhead.com/classic/spell=424785/saber-slash | search snippet | SoD |
| 425012 | Poisoned Knife (rune engraving) | https://www.wowhead.com/classic/spell=425012/poisoned-knife | search snippet | SoD |
| 415413 | Lock and Load (trap→free shot, SoD) | https://www.wowhead.com/classic/spell=415413/lock-and-load | scrape OK | SoD |
| 415399 | Sniper Training (legs rune) | https://www.wowhead.com/classic/spell=415399/sniper-training | search snippet | SoD |
| 409433 | Chimera Shot (gloves rune) | https://www.wowhead.com/classic/spell=409433/chimera-shot | search snippet | SoD |
| 415423 | Aspect of the Viper (SoD) | https://www.wowhead.com/classic/spell=415423/aspect-of-the-viper | search snippet (Phase 2 SoD) | SoD |
| 56344 | Lock and Load (talent) | https://www.wowhead.com/wotlk/spell=56344/lock-and-load | scrape OK | Wrath |
| 53220 | Improved Steady Shot (12s buff) | https://www.wowhead.com/wotlk/spell=53220/improved-steady-shot | scrape OK (Duration 12s) | Wrath |
| 53304 | Sniper Training (+crit/dmg still) | https://www.wowhead.com/wotlk/spell=53304/sniper-training | search snippet | Wrath |
| 53209 | Chimera Shot (125% + sting roll) | https://www.wowhead.com/wotlk/spell=53209/chimera-shot | search snippet | Wrath |
| 60053 | Explosive Shot R4 | https://www.wowhead.com/wotlk/spell=60053/explosive-shot | search snippet | Wrath |
| 49052 | Steady Shot | https://www.wowhead.com/wotlk/spell=49052/steady-shot | scrape OK (1.5s cast; sim models 2s base hasted — mechanics SIM-side) | Wrath |
| 34120 | Steady Shot (TBC rank) | https://www.wowhead.com/tbc/spell=34120/steady-shot | search snippet | TBC |
| 27021 | Multi-Shot (TBC rank) | https://www.wowhead.com/tbc/spell=27021/multi-shot | search snippet | TBC |
| 27019 | Arcane Shot (TBC rank) | https://www.wowhead.com/tbc/spell=27019/arcane-shot | search snippet | TBC |
| 34026 | Kill Command | https://www.wowhead.com/tbc/spell=34026/kill-command | search snippet | TBC |
| 34074 | Aspect of the Viper | https://www.wowhead.com/tbc/spell=34074/aspect-of-the-viper | search snippet (+classic/wotlk pages exist) | TBC (+Era/Wrath pages exist) |
| 27044 | Aspect of the Hawk (TBC rank) | https://www.wowhead.com/tbc/spell=27044/aspect-of-the-hawk | search snippet | TBC |
| 23989 | Readiness | https://www.wowhead.com/tbc/spell=23989/readiness | search snippet (+classic +forever pages exist) | TBC/Wrath; Forever page exists (CLIENT-UNCONFIRMED) |
| 26866 | Expose Armor (TBC rank) | https://www.wowhead.com/tbc/spell=26866/expose-armor | search snippet | TBC (r6 per sim) |
| 11198 | Expose Armor | https://www.wowhead.com/classic/spell=11198/expose-armor | search snippet | Era/Forever (rank per sim) |
| 25236 | Execute (925 + 21/rage) | https://www.wowhead.com/tbc/spell=25236/execute | search snippet (matches sim `925 + 21*extraRage`) | TBC |
| 20662 | Execute | https://www.wowhead.com/forever/spell=20662/execute | search snippet (+classic page exists) | Forever/Era |
| 23894 | Bloodthirst (45% AP) | https://www.wowhead.com/classic/spell=23894/bloodthirst | search snippet | Era/SoD |
| 1680 | Whirlwind | https://www.wowhead.com/classic/spell=1680/whirlwind | search snippet (+tbc page exists) | all classic-line |
| 34428 | Victory Rush (20s post-kill) | https://www.wowhead.com/wotlk/spell=34428/victory-rush | scrape OK | Wrath ONLY (Forever applicability UNCONFIRMED, §U3) |
| 32216 | Victorious (Victory Rush enabled) | https://www.wowhead.com/spell=32216/victorious | search snippet | Retail ONLY (WotLK/Forever aura UNCONFIRMED, §U3) |
| 16246 | Clearcasting (15s, Magic) | https://www.wowhead.com/classic/spell=16246/clearcasting | scrape OK (+tbc/wotlk pages exist) | Era/TBC/Wrath; Forever page NOT found (UNCONFIRMED) |
| 408345 | Fire Nova (off Fire totem) | https://www.wowhead.com/forever/spell=408345/fire-nova | search snippet | Forever |
| 8345 | Wolfshead Helm (item) | https://www.wowhead.com/item=8345/wolfshead-helm | search snippet | TBC (sim `HasItemEquipped(8345)`) |
| 417141 | Berserk (Primal Bite, cat) | https://www.wowhead.com/forever/spell=417141/berserk | search snippet (+classic page exists) | Forever/SoD |
| 1311703 | Echo of Command (SoC chance) | https://www.wowhead.com/forever/spell=1311703/echo-of-command | search snippet | Forever |
| 1311704 | Echo of Righteousness | https://www.wowhead.com/forever/spell=1311704/echo-of-righteousness | search snippet | Forever |
| 10333 | Holy Strike (50% + 97-121 Holy) | https://www.wowhead.com/forever/spell=10333/holy-strike | search snippet | Forever |
| 1310687 | Sniper Shot (+160, +10yd x3) | https://www.wowhead.com/forever/spell=1310687/sniper-shot | search snippet (scrape blocked by bot-wall) | Forever (CLIENT-UNCONFIRMED) |
| 1293241 | Summon Hawk | https://www.wowhead.com/forever/spell=1293241/summon-hawk | search snippet (scrape blocked by bot-wall) | Forever (CLIENT-UNCONFIRMED) |
| 16387 | Flametongue Totem | https://www.wowhead.com/forever/spell=16387/flametongue-totem | search snippet (forever page exists) | Forever — CORRECTS audit guess: NOT a hidden prepull, it is Flametongue Totem |
| 25361 | Strength of Earth Totem | https://www.wowhead.com/forever/spell=25361/strength-of-earth-totem | search snippet | Forever — confirms name-by-elimination |
| 25570 | Mana Spring Totem (20/2s) | https://www.wowhead.com/tbc/spell=25570/mana-spring-totem | search snippet | TBC — confirms name-by-elimination |
| 425339 | Molten Blast (gloves rune) | https://www.wowhead.com/classic/spell=425339/molten-blast | search snippet | SoD — confirms rune-enum guess |

Notes: wowhead `/forever/` scrapes are bot-walled (1310687 scrape failed;
search snippets used instead). 60052 R3 page existence via cited link in
https://github.com/Hekili/hekili/issues/2349 (direct snippet owed — §U17).

## 3. Still-UNCONFIRMED (no invention; probe owed)

- U1. Forever rank tables beyond 1310687/1293241: Sniper 1310785/1310786,
  SummonHawk 1293525/1293526/1293527, triggered 1293248/1312639 —
  SIM-CONFIRMED only; per-id pages + 1.60.x `GetSpellInfo` owed.
- U2. Hawk-count observation source (guardian-pet enumeration / UnitAura
  1293248/1312639 / combat-log) — no public contract found this lane;
  in-client probe owed (blocker per `hunter_open §3`).
- U3. Victory Rush on Forever: spell id (34428 is WotLK-only), Victorious
  aura id/duration on 1.60.x (retail 32216 exists; WotLK/Forever unknown),
  `IsSpellUsable` post-kill semantics — checklist for owner test session.
- U4. TBC shaman Flame Shock fight>=12s gate — sim-side UNCONFIRMED (not
  re-fetched this lane; per `open_rules §2`).
- U5. SoD p4-twist path (404 wrong guess; p8-twist carries the 10% rule
  SIM-CONFIRMED) — correct `ui/paladin/apls` path owed.
- U6. SoD Stormstrike 6s CD trigger (rune vs base) — sim models flat 6s.
- U7. In-client feel of every row (sims are not the game; notably Forever
  2H + custom ids).
- U8. Bloodthirst Forever (name-only by design) — same boat as U3.
- U9. Forever bonus kit (Arcane 14287, Serpent 25295, Mark 14325, Hawk
  25296, Raptor 14266, WingClip 14268, StriderKick 1317257, Falcon 469145,
  RF 3045, Feign 5384, Multi 2643, Aimed 20904, Mongoose 14271, Blood Fury
  20572) — SIM-CONFIRMED only.
- U10. Rogue per-client ids beyond §2 (Wrath 57993/51662/26889/58426/57934/
  51690/48668; TBC 26862/26863/34413/26864/5938/32645/26867/26865; Forever
  11281/1241584/16511/11294/6774/11275/11300/13750/7676/13877/14177/
  1310703; Era 31016; SoD 425096-buff/1856/CttC rune) — SIM-CONFIRMED only.
  **CORRECTED 2026-10-20**: the TBC segment used to read
  "26864/26863/34413/26862/…", which the corpus read as "SS 26864 … Hemo
  26862" — the two are **swapped**: **26862 = Sinister Strike, 26864 =
  Hemorrhage** (`bench/filed_closure_sweep_2026-10-19.md` §9-N1; the rogue
  APL build lane's sim-sourced TBC table,
  `bench/rogue_apl_utility_build_2026-10-20.md` §1.1). The names that were
  blank are now settled: 1310703 = **Venom**, 1241584 = **Mutilate r4**,
  14183 = **Premeditation**, 1857 = **Vanish r2** (§0.0 **R1**/**R2**/**R3**/**R7**
  of `bench/rotation_gap_vs_apl_2026-10-20.md`); the client proof is still
  owed.
- U11. Paladin per-client ids beyond §2 (SoC procs, CS, JotC 21183, HoW/Exo/
  Cons ranks, sealDuration, TwistOfLightTalents string) — guide/sim-sourced.
- U12. Shaman per-client ids beyond §2 (SS 17364 via verify_bank; FS/ES/LB/
  LL/MW/SR runes 440580/408490/408507/425339/408498/408505/425336; TBC
  totems; Forever totems/potion/rune thresholds) — SIM-CONFIRMED only.
- U13. Warrior per-client ids beyond §2 (OP window, Slam 11605, HS 25286/
  Cleave 20569 ranks, Blood Surge/Sudden Death, HS floors) — SIM-CONFIRMED.
- U14. Druid per-client ids beyond §2 (TF/Berserk 50334 WotLK, SP 50 vs 60
  ceiling, 16s CD/8s ISPP, SR 14–34s, Rip/Rake/Mangle costs, FF rules).
- U15. ISS mechanics (+15% dmg/−20% cost/consumed-on-cast) — page confirms
  12s buff; numbers are SIM-side only.
- U16. H2 lust-suppression — no APL lust branch in any fetched APL
  (SIM-DIVERGENT); orchestrator ruling owed, not an id.
- U17. 60052 R3 — page existence via cited link only; direct snippet owed.
