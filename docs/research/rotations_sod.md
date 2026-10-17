# Season of Discovery Phase 8 — DPS Rotations (min/max)

Scope: hunter (MM Chimera), warrior (fury runes), paladin (Exodin), druid (feral King of the Jungle + Berserk + powershift), shaman (enhancement MW + Lava Burst + Lava Lash + Feral Spirit). Sources: Wowhead SoD guides (rotation/cooldowns/abilities pages, rune guides), Icy Veins SoD guides, Odealo classic, repo code (spell IDs). Warcraft Logs is bot-walled/unreachable — parse-specific timings not verified (⚠). Uncertainty marked ⚠.

## Warcraft Logs
- **Unreachable** (bot-walled / requires auth) for all classes. Rankings/parse data not scraped; rotations derived from guide priority lists only. ⚠ Top-parse nuance (exact cooldown stacking timings) may differ from guide consensus.

---

## 1. Hunter — Marksmanship (Chimera)

### Runes
- **Chimera Shot** (core shot; highest priority; auto-refreshes Serpent Sting). Wowhead: https://www.wowhead.com/guide=22606 (Ranged Hunter DPS Talent Builds and Runes - SoD); https://www.wowhead.com/guide=25641 (Ranged Hunter DPS Rotation, Cooldowns, and Abilities - SoD).
- Pet runes (Beast Mastery pet) too strong to skip in top parses. ⚠

### Priority (ranged)
1. Auto Shot maximization (never clip Auto Shot).
2. Chimera Shot (on CD).
3. Auto Shot.
4. Aimed Shot.
5. Auto Shot.
6. Multi-Shot.
- If skipping Chimera Shot (pet-rune builds): drop Chimera Shot, fill gaps with melee weaving (Raptor Strike) from 8yd min range.

### Breakpoints / numbers
- Weapon speed ~3.0s: full rotation (weapon >3.0s) vs clipped rotation (weapon <3.0s) — inherited from classic model. ⚠ Not explicitly re-stated for SoD; assumed.
  - Full: Auto, Chimera/Aimed, Auto, Multi, Auto, (open spot), Auto, Aimed.
  - Clipped: Auto, Chimera/Aimed, Auto, Multi, Auto, (open spot), Aimed.
- Open spot: Feign Death trinket swap or melee weaving.

### Cooldown stacking
- Rapid Fire + on-use trinkets/Berserking stacked on pull; don't lose extra uses.

### vs Era-base
- Era: Auto Shot maximization; Aimed Shot + Multi-Shot only; no Serpent Sting/Arcane Shot (magic, no AP scaling; debuff slot) except SoM debuff-limit removal makes Serpent Sting viable. SoD adds Chimera Shot as new core shot that auto-refreshes Serpent Sting.

### vs TBC
- TBC hunter uses Steady Shot (replaces Aimed as filler), Kill Command, Auto Shot weaving with cast-time shots; no melee weaving meta. SoD/Era lack Steady Shot; Aimed Shot is the cast shot.

---

## 2. Warrior — Fury (Consumed by Rage / Blood Surge / Sudden Death / Raging Blow)

### Runes
- **Consumed by Rage** (rage >60 buff), **Blood Surge** (instant Slam proc, aura id 46916), **Sudden Death** (Execute proc), **Raging Blow**, **Wild Strikes** (proc fishing via Hamstring), **Single-Minded Fury** (DW), **Flagellation**. Wowhead: https://www.wowhead.com/guide=22578 (Warrior DPS Talent Builds and Runes - SoD); https://www.wowhead.com/guide=25605 (Warrior DPS Rotation, Cooldowns, and Abilities - SoD).

### Priority
1. Pool rage >60 (Consumed by Rage).
2. Sunder stacks unless Homunculi priest.
3. Battle Shout.
4. Execute dump Sudden Death procs.
5. Slam on Blood Surge proc (instant).
6. Death Wish + Rampage on CD (save last for execute phase).
7. Bloodthirst.
8. Whirlwind.
9. Raging Blow.
10. Hamstring (fish Wild Strikes/Windfury).
11. Heroic Strike (excess rage dump).

### Breakpoints / numbers
- Rage pooling >60 for Consumed by Rage.
- Execute phase <20% HP.
- Heroic Strike rage dump when ≥30 rage and 2-3s until next BT/WW (Era baseline, carried).
- Blood Surge aura id 46916 (repo-verified).

### Cooldown stacking
- Death Wish + Rampage on CD; save last Rampage for execute phase. ⚠ Exact stacking timings not WCL-verified.

### vs Era-base
- Era: Bloodthirst on CD, Whirlwind on CD, Heroic Strike rage dump ≥30 rage, Execute spam <20%, Overpower if specced. SoD adds rune-based procs (Blood Surge, Sudden Death, Consumed by Rage) and Wild Strikes fishing, rage pooling >60.

### vs TBC
- TBC fury uses Bloodthirst/Whirlwind/Slam (Bloodsurge-like proc), Heroic Strike rage dump, no Raging Blow/Wild Strikes runes; TBC has Rampage talent baseline. SoD adds rune-based procs and Wild Strikes fishing.

---

## 3. Paladin — Retribution "Exodin"

### Runes
- **Seal of Martyrdom** (main seal), **Crusader Strike**, **Divine Storm**, **Exorcism** (Exodin build), **Sheath of Light**, **Aura Mastery**, **Avenging Wrath**. Wowhead: https://www.wowhead.com/guide=22614 (Paladin DPS Talent Builds and Runes - SoD); https://www.wowhead.com/guide=25575 (Paladin DPS Rotation, Cooldowns, and Abilities - SoD).

### Priority
1. Sanctity Aura.
2. Blessing.
3. Seal of Crusader + Judgement if mob >20s.
4. Keep Seal of Martyrdom.
5. Avenging Wrath.
6. Aura Mastery.
7. Exorcism on CD.
8. Crusader Strike on CD.
9. Divine Storm on CD.
10. Judgement on CD.
11. Consecration (mana / 3+ targets).
12. Hammer of Wrath <20%.
13. Exorcism <10% (if HoW unavailable).
14. Crusader Strike for mana.

### Breakpoints / numbers
- Mob >20s for SoC debuff.
- <20% HP: Hammer of Wrath.
- <10% HP: Exorcism spam (if HoW unavailable).
- Seal twist window ~0.4s before auto swing (SoD guide states .4s). ⚠ Classic similar; fast weapon favors twist.
- Seal twisting: SoM + SoC twist possible but currently behind fast 2H build (⚠ guide says twisting DPS slightly behind).

### Cooldown stacking
- Avenging Wrath + Aura Mastery on CD; ⚠ exact stacking timings not WCL-verified.

### vs Era-base
- Era: Sanctity Aura, Seal of Command (or SoR), Judgement to maintain Seal of Crusader debuff, Crusader Strike, Consecration (mana permitting), Exorcism (undead/demon), Hammer of Wrath <20%. Seal twisting (SoC/SoR → SoB/SoM) for top parses. SoD adds Exorcism-focused "Exodin" build and Holy Power (Inquisition 2-set) in Phase 8. ⚠ Holy Power/Inquisition is Phase 8 tier-set dependent.

### vs TBC
- TBC ret uses Crusader Strike, Judgement of Command/Blood, Seal of Blood twisting, Consecration, Hammer of Wrath; has Art of War/Divine Storm (later). SoD adds Exorcism-focused "Exodin" build.

---

## 4. Druid — Feral (King of the Jungle + Berserk + powershift)

### Runes
- **King of the Jungle** (Tiger's Fury +15% phys damage snapshot on bleeds, +60 energy), **Berserk**, **Omen of Clarity**, **Mangle**, **Rake**, **Rip**, **Savage Roar**, **Faerie Fire (Feral)**, **Furor** (powershift), plus SoD items (Glowing Gneuro-Linked Cowl, Catnip). Wowhead: https://www.wowhead.com/guide=22617 (Feral Druid DPS Phase 8 Talent Builds and Runes - SoD); https://www.wowhead.com/guide=25696 (Feral Druid DPS Rotation, Cooldowns, and Abilities - SoD).

### Priority
1. Faerie Fire (Feral) on pull.
2. Mangle.
3. Rake.
4. Savage Roar (refresh).
5. Glowing Cowl + Catnip after armor debuffs.
6. Tiger's Fury on CD at ≤40 energy (King of the Jungle).
7. Berserk immediately after TF.
8. Omen procs → Shred.
9. Rip at 5 CP (prefer under TF).
10. Shred filler.
11. Powershift at 0 energy.

### Breakpoints / numbers
- Tiger's Fury at ≤40 energy (to not overcap with +60).
- Rip snapshot under TF (King of the Jungle +15% phys damage).
- Powershift at ~0 energy after tick (Furor 40 energy on shift).
- Energy tick timing.

### Cooldown stacking
- Tiger's Fury → Berserk immediately after; ⚠ exact stacking timings not WCL-verified.

### vs Era-base
- Era: Powershifting meta: Furor (40 energy on shift), Wolfshead Helm, Manual Crowd Pummeler. Priority: Faerie Fire (Feral), Mangle, Rake, Savage Roar, Shred filler, Rip at 5 CP, Tiger's Fury, Omen of Clarity procs → Shred, Ferocious Bite at 5 CP on crit. Powershift at ~0 energy after tick. SoD adds King of the Jungle snapshot (+15% phys, +60 energy) and SoD-specific items (Glowing Cowl, Catnip).

### vs TBC
- TBC feral uses Mangle, Shred, Rip, Rake, Savage Roar, Tiger's Fury, Berserk, Omen; powershifting less dominant (energy regen changes). SoD keeps classic powershifting + adds King of the Jungle snapshot and SoD-specific items. ⚠ SoD Phase 8 tier items (Glowing Cowl) are phase-specific.

---

## 5. Shaman — Enhancement (MW + Lava Burst + Lava Lash + Feral Spirit)

### Runes
- **Windfury Weapon** (both weapons), **Stormstrike**, **Lava Lash**, **Lava Burst**, **Feral Spirit**, **Shamanistic Rage**, **Rolling Thunder**, **Spirit of the Alpha**, **Totemic Projection**, **Maelstrom Weapon** (stacks → Lightning Bolt/Chain Lightning). Wowhead: https://www.wowhead.com/guide=22599 (Enhancement Shaman DPS Talent Builds and Runes - SoD); https://www.wowhead.com/guide=25452 (Enhancement Shaman DPS Rotation, Cooldowns, and Abilities - SoD).

### Priority
1. Lightning Shield active.
2. Feral Spirit pre-pull + on CD.
3. Spirit of the Alpha on ally.
4. Totems + Searing Totem.
5. Shamanistic Rage on CD when mana low.
6. Stormstrike on CD.
7. Lava Burst / Lightning Bolt at ~5 Maelstrom stacks (prefer under Stormstrike debuff).
8. Alternate Flame Shock / Earth Shock (spend Rolling Thunder).
9. Lava Lash on CD.

### Breakpoints / numbers
- Maelstrom Weapon: 20% cast-time reduction per stack, instant at 5 stacks. SoD aura id 408505 (repo-verified); Wrath-era id 53817. Duration 30s (Wowhead spell page: https://www.wowhead.com/classic/spell=408505).
- Stormstrike debuff window for Lava Burst.
- Feral Spirit spell id 51533 (repo-verified via LibClassicSwingTimerAPI).

### Cooldown stacking
- Feral Spirit pre-pull + on CD; Shamanistic Rage on CD when mana low; ⚠ exact stacking timings not WCL-verified.

### vs Era-base
- Era: Windfury Weapon (main), Stormstrike on CD, Earth Shock/Flame Shock, Windfury procs, Searing Totem, totems (WF, SoE, GoA, MS), Blood Fury (orc) pre-pull. Enhancement not top raid DPS in Era; buff-bot role. SoD adds Maelstrom Weapon, Lava Lash, Lava Burst, Feral Spirit, Shamanistic Rage, Rolling Thunder, Spirit of the Alpha, Totemic Projection, Windfury both weapons.

### vs TBC
- TBC enhancement uses Stormstrike, shocks, Windfury, Maelstrom Weapon (5 stacks → instant cast), Lava Lash, Feral Spirit (later), Shamanistic Rage. SoD mirrors TBC Maelstrom model closely but adds Rolling Thunder, Spirit of the Alpha, Totemic Projection, and rune-based Lava Burst. ⚠ SoD is closer to TBC enhancement than Era is.

---

## Cross-cutting notes
- Era hunter/warrior/paladin/druid rotations are classic (no runes); SoD adds rune-driven abilities that change priority lists significantly.
- TBC model differences: hunter Steady Shot, warrior Bloodsurge baseline, paladin Crusader Strike/SoB, druid less powershifting, shaman Maelstrom Weapon (SoD already adopts this).
- Warcraft Logs unreachable (bot-walled) — parse-specific timings not verified. ⚠
- Breakpoints (weapon speed ~3.0s hunter; rage >60 warrior; energy ≤40 druid; Maelstrom ~5 shaman) from guides; exact sim-optimal values may vary by gear. ⚠
- Rune spell IDs verified where repo code exposes them: Maelstrom Weapon 408505 (SoD) / 53817 (Wrath), Feral Spirit 51533, Blood Surge 46916. Other rune IDs not present in repo; ⚠ not independently verified via Wowhead (spell pages 404 for some).