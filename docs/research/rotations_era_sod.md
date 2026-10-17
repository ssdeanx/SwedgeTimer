# Top-Parse DPS Rotations — Classic Era 1.15.9 vs SoD Phase 8

Scope: hunter, warrior, paladin, druid, shaman. Sources: Icy Veins (classic + SoD), Wowhead (SoD), Odealo, Warcraft Logs (bot-walled — unreachable, noted). Uncertainty marked with ⚠.

## Warcraft Logs
- **Unreachable** (bot-walled / requires auth) for all classes. Rankings/parse data not scraped; rotations derived from guide priority lists only. ⚠ Top-parse nuance (e.g., exact cooldown stacking timings) may differ from guide consensus.

---

## 1. Hunter

### Classic Era 1.15.9 (BM/MM/Surv ranged)
- Priority: Auto Shot maximization; Aimed Shot + Multi-Shot only. No Serpent Sting/Arcane Shot (magic, no AP scaling; debuff slot) except SoM debuff-limit removal makes Serpent Sting viable if mana allows. (Icy Veins classic hunter: https://www.icy-veins.com/wow-classic/hunter-dps-pve-rotation-cooldowns-abilities)
- Two rotations by weapon speed breakpoint ~3.0s:
  - **Full rotation** (weapon >3.0s): Auto, Aimed, Auto, Multi, Auto, (open spot), Auto, Aimed.
  - **Clipped rotation** (weapon <3.0s): Auto, Aimed, Auto, Multi, Auto, (open spot), Aimed.
- Open spot: Feign Death trinket swap or melee weaving (Raptor Strike) from 8yd min range.
- Cooldowns: Rapid Fire + on-use trinkets/Berserking stacked on pull; don't lose extra uses.

### SoD Phase 8 (Marksmanship top)
- Runes: **Chimera Shot** (new core shot, highest priority), Serpent Sting auto-refreshed via Chimera Shot; pet runes (Beast Mastery pet) too strong to skip. (Icy Veins SoD MM hunter: https://www.icy-veins.com/wow-classic/marksmanship-hunter-dps-season-of-discovery-pve-rotation-cooldowns-abilities)
- Priority: Auto, Chimera Shot, Auto, Aimed Shot, Auto, Multi-Shot. If skipping Chimera Shot (pet runes), drop it and fill gaps with melee weaving.
- Breakpoint: weapon speed still ~3.0s for full vs clipped (guide inherits classic model). ⚠ Not explicitly re-stated for SoD; assumed.

### vs TBC model
- TBC hunter uses Steady Shot (replaces Aimed as filler), Kill Command, Auto Shot weaving with cast-time shots; no melee weaving meta. SoD/Era lack Steady Shot; Aimed Shot is the cast shot.

---

## 2. Warrior

### Classic Era 1.15.9 (Fury)
- Priority list (not strict rotation): Bloodthirst on CD, Whirlwind on CD, Heroic Strike as rage dump when ≥30 rage and 2-3s until next BT/WW; Execute spam <20%; Overpower if specced. (Icy Veins classic fury: https://www.icy-veins.com/wow-classic/fury-warrior-dps-pve-rotation-cooldowns-abilities; Wowhead: https://www.wowhead.com/classic/guide/classes/warrior/fury/dps-rotation-cooldowns-abilities-pve)
- Breakpoints: rage ≥30 for HS; weapon speed thresholds for flurry uptime. ⚠ Exact AP threshold (~2000 AP) for BT≈Execute noted in community (YouTube) but not guide-verified.

### SoD Phase 8 (Fury)
- Runes: **Consumed by Rage** (rage >60 buff), **Blood Surge** (instant Slam proc), **Sudden Death** (Execute proc), **Raging Blow**, **Wild Strikes** (proc fishing via Hamstring), **Single-Minded Fury** (DW), **Flagellation**. (Icy Veins SoD fury: https://www.icy-veins.com/wow-classic/fury-warrior-dps-season-of-discovery-pve-rotation-cooldowns-abilities)
- Priority: pool rage >60 (Consumed by Rage); Sunder stacks unless Homunculi priest; Battle Shout; Execute dump Sudden Death procs; Slam on Blood Surge proc; Death Wish + Rampage on CD (save last for execute phase); Bloodthirst; Whirlwind; Raging Blow; Hamstring (fish Wild Strikes/Windfury); Heroic Strike excess rage.
- Breakpoint: rage pooling >60 for Consumed by Rage; execute phase <20%.

### vs TBC model
- TBC fury uses Bloodthirst/Whirlwind/Slam (Bloodsurge-like proc), Heroic Strike rage dump, no Raging Blow/Wild Strikes runes; TBC has Rampage talent baseline. SoD adds rune-based procs (Blood Surge, Sudden Death, Consumed by Rage) and Wild Strikes fishing.

---

## 3. Paladin (Retribution)

### Classic Era 1.15.9
- Priority: Sanctity Aura, Seal of Command (or SoR), Judgement to maintain Seal of Crusader debuff, Crusader Strike, Consecration (mana permitting), Exorcism (undead/demon), Hammer of Wrath <20%. Seal twisting (SoC/SoR → SoB/SoM) for top parses. (Odealo classic ret: https://odealo.com/articles/the-best-pve-retribution-paladin-build-for-wow-classic; TBC wowtbc.gg seal twisting: https://wowtbc.gg/class-guides/retribution-paladin)
- Breakpoint: seal twist window ~0.4s before auto swing (SoD guide states .4s; classic similar ⚠). Fast weapon favors twist.

### SoD Phase 8 (Retribution "Exodin")
- Runes: **Seal of Martyrdom** (baseline-ish, main seal), **Crusader Strike**, **Divine Storm**, **Exorcism** (Exodin build), **Sheath of Light**, **Aura Mastery**, **Avenging Wrath**. (Icy Veins SoD ret: https://www.icy-veins.com/wow-classic/retribution-paladin-dps-season-of-discovery-pve-rotation-cooldowns-abilities; Wowhead SoD paladin: https://www.wowhead.com/classic/guide/season-of-discovery/classes/paladin/dps-rotation-cooldowns-abilities-pve)
- Priority: Sanctity Aura, blessing, Seal of Crusader + Judgement if mob >20s, keep Seal of Martyrdom, Avenging Wrath, Aura Mastery, Exorcism on CD, Crusader Strike on CD, Divine Storm on CD, Judgement on CD, Consecration (mana/3+ targets), Hammer of Wrath <20%, Exorcism <10% (if HoW unavailable), Crusader Strike for mana.
- Seal twisting: SoM + SoC twist possible but currently behind fast 2H build (⚠ guide says twisting DPS slightly behind).
- Breakpoint: mob >20s for SoC debuff; <20% HoW; <10% Exorcism spam.

### vs TBC model
- TBC ret uses Crusader Strike, Judgement of Command/Blood, Seal of Blood twisting, Consecration, Hammer of Wrath; has Art of War/Divine Storm (later). SoD adds Exorcism-focused "Exodin" build and Holy Power (Inquisition 2-set) in Phase 8. ⚠ Holy Power/Inquisition is Phase 8 tier-set dependent.

---

## 4. Druid (Feral DPS)

### Classic Era 1.15.9
- Powershifting meta: Furor (40 energy on shift), Wolfshead Helm, Manual Crowd Pummeler. Priority: Faerie Fire (Feral), Mangle, Rake, Savage Roar, Shred filler, Rip at 5 CP, Tiger's Fury, Omen of Clarity procs → Shred, Ferocious Bite at 5 CP on crit. Powershift at ~0 energy after tick. (Odealo classic feral: https://odealo.com/articles/the-best-pve-feral-druid-build-for-wow-classic; Wowhead classic feral: https://www.wowhead.com/classic/guide/classes/druid/feral/dps-overview-pve)
- Breakpoint: energy tick timing; powershift at 0 energy; crit-driven Ferocious Bite.

### SoD Phase 8 (Feral)
- Runes: **King of the Jungle** (Tiger's Fury +15% phys damage snapshot on bleeds, +60 energy), **Berserk**, **Omen of Clarity**, **Mangle**, **Rake**, **Rip**, **Savage Roar**, **Faerie Fire (Feral)**, **Furor** (powershift), plus SoD items (Glowing Gneuro-Linked Cowl, Catnip). (Icy Veins SoD feral: https://www.icy-veins.com/wow-classic/feral-druid-dps-season-of-discovery-pve-rotation-cooldowns-abilities)
- Priority: Faerie Fire (Feral) on pull; Mangle, Rake, Savage Roar (refresh); Glowing Cowl + Catnip after armor debuffs; Tiger's Fury on CD at ≤40 energy (King of the Jungle); Berserk immediately after TF; Omen procs → Shred; Rip at 5 CP (prefer under TF); Shred filler; powershift at 0 energy.
- Breakpoint: Tiger's Fury at ≤40 energy (to not overcap with +60); Rip snapshot under TF.

### vs TBC model
- TBC feral uses Mangle, Shred, Rip, Rake, Savage Roar, Tiger's Fury, Berserk, Omen; powershifting less dominant (energy regen changes). SoD keeps classic powershifting + adds King of the Jungle snapshot and SoD-specific items. ⚠ SoD Phase 8 tier items (Glowing Cowl) are phase-specific.

---

## 5. Shaman (Enhancement)

### Classic Era 1.15.9
- Priority: Windfury Weapon (both hands? main WF, off FT in SoD; classic: WF main), Stormstrike on CD, Earth Shock/Flame Shock, Windfury procs, Searing Totem, totems (WF, SoE, GoA, MS), Blood Fury (orc) pre-pull. Enhancement not top raid DPS in Era; buff-bot role. (Wowhead classic enhancement: https://www.wowhead.com/classic/guide/classes/shaman/enhancement/dps-overview-pve; wowisclassic: https://www.wowisclassic.com/en/class-guide/shaman/enhancement-pve-hl)
- Breakpoint: Stormstrike CD; shock on CD; mana management.

### SoD Phase 8 (Enhancement)
- Runes: **Windfury Weapon** (both weapons), **Stormstrike**, **Lava Lash**, **Lava Burst**, **Feral Spirit**, **Shamanistic Rage**, **Rolling Thunder**, **Spirit of the Alpha**, **Totemic Projection**, **Maelstrom Weapon** (stacks → Lightning Bolt/Chain Lightning). (Icy Veins SoD enhancement: https://www.icy-veins.com/wow-classic/enhancement-shaman-dps-season-of-discovery-pve-rotation-cooldowns-abilities; zockify: https://www.zockify.com/wowclassic/shaman/enhancement)
- Priority: Lightning Shield active; Feral Spirit pre-pull + on CD; Spirit of the Alpha on ally; totems + Searing Totem; Shamanistic Rage on CD when mana low; Stormstrike on CD; Lava Burst/Lightning Bolt at ~5 Maelstrom stacks (prefer under Stormstrike debuff); alternate Flame Shock/Earth Shock (spend Rolling Thunder); Lava Lash on CD.
- Breakpoint: Maelstrom ~5 stacks for cast; Stormstrike debuff window for Lava Burst.

### vs TBC model
- TBC enhancement uses Stormstrike, shocks, Windfury, Maelstrom Weapon (5 stacks → instant cast), Lava Lash, Feral Spirit (later), Shamanistic Rage. SoD mirrors TBC Maelstrom model closely but adds Rolling Thunder, Spirit of the Alpha, Totemic Projection, and rune-based Lava Burst. ⚠ SoD is closer to TBC enhancement than Era is.

---

## Cross-cutting notes
- Era hunter/warrior/paladin/druid rotations are classic (no runes); SoD adds rune-driven abilities that change priority lists significantly.
- TBC model differences: hunter Steady Shot, warrior Bloodsurge baseline, paladin Crusader Strike/SoB, druid less powershifting, shaman Maelstrom Weapon (SoD already adopts this).
- Warcraft Logs unreachable (bot-walled) — parse-specific timings not verified. ⚠
- Breakpoints (weapon speed ~3.0s hunter; rage >60 warrior; energy ≤40 druid; Maelstrom ~5 shaman) from guides; exact sim-optimal values may vary by gear. ⚠
