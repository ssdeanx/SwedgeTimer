# WotLK 3.3.5 (Titanforge 3.80.2) Rotation Research

Scope: min/max TOP-PARSE priorities for hunter (MM P3+, SV P1-2), warrior (fury + arms), paladin (ret FCFS pre/post 2pc-T10), druid (feral EJ priority), shaman (enhancement MW5). Sources: Wowhead WotLK Classic guides (scraped 2026-10-17). WCL logs were not reachable (bot-walled) — priorities below are guide-derived, not log-validated; treat as provisional until in-game/WCL confirmation.

## Hunter — Marksmanship (P3+)

Source: https://www.wowhead.com/wotlk/guide/classes/hunter/marksmanship/dps-rotation-cooldowns-abilities-pve

Priority (single target, >20% HP):
1. Kill Shot (execute, ≤20% HP) — always highest when available
2. Serpent Sting (initial; refreshed by Chimera Shot, do not manually reapply)
3. Chimera Shot
4. Aimed Shot (instant in WotLK)
5. Arcane Shot (early phases; dropped once enough ArP)
6. Steady Shot x3 (x4 with enough haste) filler
Always cast Explosive Trap on CD except <20% (Kill Shot priority). Silencing Shot + Kill Command off-GCD, macro into shots.

Opening: cooldown macro → Serpent Sting → Chimera → Aimed → Explosive Trap → Readiness → Chimera → Aimed → normal. Pre-trap on Saurfang/Festergut/Rotface/LK.

TBC-model delta: TBC was rhythm-based (1:1, 1:2, 5:5:1:1) avoiding Auto Shot clipping; WotLK Auto Shot fires during Steady Shot casts, so rotation becomes priority-based. Steady Shot demoted from main shot to filler.

## Hunter — Survival (P1-2)

Source: https://www.wowhead.com/wotlk/guide/classes/hunter/survival/dps-rotation-cooldowns-abilities-pve

Priority (single target):
1. Kill Shot (≤20%)
2. Explosive Shot (highest outside execute)
3. Serpent Sting (manual upkeep; never refresh early)
4. Black Arrow OR Explosive Trap (Trap Launcher preferred over BA)
5. Multi-Shot (multi-target) / Aimed Shot (single, Sniper Training)
6. Steady Shot filler

Lock and Load "434": Rank4 ES → Rank3 ES → Rank4 ES (ranks do not override). Macro: /castsequence reset=2/target Explosive Shot, Explosive Shot(Rank 3).

Notes: Arcane Shot never used (shares CD with ES). Explosive Trap > Black Arrow where possible. Pre-trap rotation swaps BA in after ES.

TBC-model delta: same rhythm→priority shift; trap weaving/melee weaving optional high-risk.

## Warrior — Fury

Source: https://www.wowhead.com/wotlk/guide/classes/warrior/fury/dps-rotation-cooldowns-abilities-pve

Priority (ST): Bloodthirst (primary, 20% Bloodsurge proc) → Whirlwind (primary on 2+ targets) → Slam (instant on Bloodsurge proc, 5s window) → Rend (only if Improved Rend, no Bloodsurge proc, BT/WW not coming off CD, Battle Stance) → Execute (lowest priority, even execute phase; only with excess rage + no BT proc + everything on CD) → Heroic Strike (rage dump when excess rage and won't delay main abilities).

AoE: Whirlwind > Bloodthirst > Cleave > Slam > Execute.

TBC-model delta: Execute severely nerfed vs TBC (no longer spam in execute phase); Bloodsurge/Slam proc system new.

## Warrior — Arms

Source: https://www.wowhead.com/wotlk/guide/classes/warrior/arms/dps-rotation-cooldowns-abilities-pve

Priority (ST, all HP): Rend (maintain; enables Taste for Blood→Overpower; don't reapply early) → Sunder Armor (if no one else maintains) → Execute (Sudden Death procs above 20%; below 20% almost exclusively Execute except Overpower if insufficient rage) → Overpower (Taste for Blood every 2nd Rend tick; also dodge procs) → Bladestorm (CD; ensure Rend won't fall off, no SD proc, Overpower used in current TfB cycle) → Mortal Strike (filler) → Slam (early tiers filler) → Heroic Strike (excess rage).

AoE: Rend → Sweeping Strikes → Overpower → Thunder Clap → Bladestorm → Cleave.

TBC-model delta: Sudden Death allows Execute above 20%; Overpower via Taste for Blood new; Deep Wounds/ArP scaling.

## Paladin — Retribution (FCFS)

Source: https://www.wowhead.com/wotlk/guide/classes/paladin/retribution/dps-rotation-cooldowns-abilities-pve ; 2pc T10 bonus: https://www.wowhead.com/wotlk/guide/raids/tier-10-sets-overview (Retribution: Lightsworn Battlegear 2pc: melee attacks 40% chance to reset Divine Storm cooldown).

Base FCFS priority (single target):
1. Crusader Strike
2. Judgement of Wisdom
3. Divine Storm
4. Consecration
5. Exorcism
6. Holy Wrath (if eligible)

AoE priority: Consecration → Divine Storm → Judgement → Holy Wrath → Crusader Strike → Exorcism.

Seals: Seal of Vengeance/Corruption (ST, faction) or Seal of Command (multi). Avenging Wrath on CD early (line up with Bloodlust/trinkets). Divine Plea for mana.

Pre-2pc T10: DS on 10s CD, priority as above.
Post-2pc T10: melee attacks 40% reset DS CD → DS becomes near-spammable; priority rises (use DS whenever available, effectively above Consecration/Exorcism). Guide: "ability to continuously spam Divine Storm after auto attack refreshes"; rush 2pc T10 in ICC.

TBC-model delta: TBC ret had different seal twisting; WotLK FCFS with instant DS resets post-2pc.

## Druid — Feral (EJ priority)

Source: https://www.wowhead.com/wotlk/guide/classes/druid/feral/dps-rotation-cooldowns-abilities-pve

Decision tree (first applies):
1. If <40 Energy and Tiger's Fury off CD → Tiger's Fury
2. If Berserk available and TF on CD ≥15s → Berserk
3. If ≥1 CP and Savage Roar expired → Savage Roar
4. If Clearcasting proc → Shred
5. If 5 CP and Rip expired → Rip (pool energy)
6. If Rake expired → Rake
7. If Mangle (Cat) expired → Mangle (Cat) (skip if Arms warrior Trauma present)
8. If enough energy reserve for SR/Rip/Rake/Mangle reapplication → Shred
9. Otherwise pool energy (bearweave opportunity)

Bearweave (when <40 energy, no Clearcasting, >4.5s until Rip expires, Berserk not active): shift Dire Bear; Mangle (Bear) if ≥15 rage & off CD; Lacerate if ≥13 rage; Maul queue; shift back if >70 energy or Rip <3s or Clearcasting. Lacerateweaving variant prioritizes 5-stack Lacerate maintenance (+~2% over Mangleweaving).

Notes: Ferocious Bite only last 10s of fight. Let bleeds fall off completely before reapplying (no clipping). Powershifting no longer works (Furor changed).

TBC-model delta: TBC used powershifting (Wolfshead+Furor) for 60 energy; WotLK replaces with bearweaving (rage bar). Ferocious Bite removed from mid-fight rotation.

## Shaman — Enhancement (MW5)

Source: https://www.wowhead.com/wotlk/guide/classes/shaman/enhancement/dps-rotation-cooldowns-abilities-pve

Single target priority:
1. Fire Elemental Totem (if full 2min)
2. Feral Spirit (if full duration)
3. Maelstrom Weapon 5 stacks → Chain Lightning/Lightning Bolt (3+ stacks even better for DPS; don't clip white hits)
4. Stormstrike (on CD)
5. Shamanistic Rage (on CD / line up)
6. Flame Shock (maintain)
7. Magma Totem (maintain)
8. Lightning Shield (maintain, Static Shock)
9. Earth Shock (when FS active)
10. Fire Nova
11. Lava Lash (last resort)

Lightning Weaving: use MW stacks <5 between swings, finishing cast before swing (else DPS loss). Weapon speed sync for Flurry charge efficiency. Double FT: main hand 1 rank lower than off-hand.

AoE: Fire Elemental → Feral Spirit → Magma Totem → Fire Nova (CD) → MW 5 → Stormstrike → Shamanistic Rage → Flame Shock → Lightning Shield → Earth Shock → Lava Lash.

TBC-model delta: MW5 casting integrated with swing timer; Lightning Weaving new; weapon sync for Flurry.

## Uncertainty / validation

- WCL (Warcraft Logs) is bot-walled/unreachable in this environment; priorities are guide-derived, not log-validated. Top-parse nuances (exact haste/ArP thresholds, rage/energy/CP breakpoints, trinket timing) not fully captured by guides — flag for in-game validation.
- Titanforge 3.80.2 may differ from WotLK Classic 3.4.3 guides in spell tuning; verify in client.
- ArP cap / haste thresholds for MM 4th Steady Shot not specified in scraped guides (guide says "enough haste rating"); needs sim/log data.