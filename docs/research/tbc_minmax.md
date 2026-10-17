# TBC 2.5.6 Min/Max Micro-Details (Research)

Scope: TBC 2.5.6 (Anniversary / Titanforge-era) min/max micro-details per class that average guides miss. External research only; no repo edits. Sources cited per claim. Uncertainty marked `[uncertain]`.

## Hunter

- **Hit cap**: 142 rating (9%) vs boss specials; 126 (8%) with Draenei Heroic Presence; 95 (6%) with Improved Faerie Fire; 79 (5%) with both. Source: Wowhead TBC Hunter stat priority (https://www.wowhead.com/tbc/guide/classes/hunter/dps-stat-priority-attributes-pve), Reddit r/classicwowtbc (https://www.reddit.com/r/classicwowtbc/comments/t63dae/hunters_is_being_hit_capped_a_limit_or_a).
- **Quiver haste**: 15% from quiver, multiplicative with Serpent's Swiftness 20% → eWS = WS/1.38 for BM; SV starts at 15% → eWS = WS/1.15. Source: rotationtools (https://diziet559.github.io/rotationtools).
- **Steady ratios / rotations**: 1:1 at eWS 1.3–1.6s; French 5:5:1:1 standard for BM; 1:2/1:3 at high haste; combined 2:3/2:5; melee weaving variants (5:5:1:1 3w, 2:2 1w, 6:9:1:1 3w, 6:11:1:1 3w, 3:7 2w). Source: rotationtools.
- **Haste stacking**: up to 3.36 additional haste (4.64 total with BM talents) during stacked Rapid Fire + Bloodlust + Drums + Haste Potion + DST proc, eWS down to ~0.62s for ~10s. Source: rotationtools.
- **Pet**: scales with hunter stats (attack speed, crit); Go for the Throat feeds pet via hunter crits; pet abilities scale. `[uncertain]` exact pet ability scaling coefficients not verified from primary sources.
- **Weapon speed**: most TBC weapons 3.0; P1 best (Sunfury Bow) 2.9; preraid Wrathtide Longbow 3.0. Source: rotationtools.

## Warrior

- **Rage normalization (TBC classic)**: damage-based formula R=(15d/4c)+(f*s/2) with f=3.5 MH (c≈230.6 at 60, 274.7 at 70); slower weapons generate more rage per swing. Source: GitHub magey/tbc-warrior issue #6 (https://github.com/magey/tbc-warrior/issues/6), NoobToBoss (https://noobtoboss.com/wow-classic-warrior-rage-guide).
- **Rage normalization (Forever rework)**: 1H = speed×3.46, 2H = speed×4.50 per swing; auto-crits no longer generate extra rage. Source: Icy Veins (https://www.icy-veins.com/wow-forever/news/wow-forever-just-reworked-warrior-rage-and-players-cant-stop-talking-about-it), Warcraft Wiki (https://warcraft.wiki.gg/wiki/Rage).
- **HS cancel macro**: cancel queued Heroic Strike/Cleave before Execute/stance swap to avoid spending 15 rage; Tactical Mastery leaves max 25 rage on stance swap; Sweeping Strikes costs 30. Source: YouTube Sanmedina (https://www.youtube.com/watch?v=swt7Ij7BlIw), Reddit r/classicwow (https://www.reddit.com/r/classicwow/comments/jz70t7/list_of_classic_warrior_macros).
- **Execute phase weapon swap**: swap to fast/fast weapons during execute for flurry charges (4 swings per 3 flurry charges if same speed); weapon swap triggers GCD and loses rage. Source: Reddit r/classicwowtbc (https://www.reddit.com/r/classicwowtbc/comments/nk3pst/fury_warrior_oh_speed_question_in_tbc), YouTube Sanmedina.
- **Threat**: normalized instant attacks (Bloodthirst/Whirlwind/Mortal Strike use normalized weapon speed X, not actual speed). Source: NoobToBoss.

## Paladin

- **Twist window**: SoC proc delay ~0.5s after white hit; twist into second seal within last ~0.4s of swing timer. Source: Warmane forum (https://forum.warmane.com/showthread.php?t=352589), Wowhead SoD guide (https://www.wowhead.com/classic/guide/season-of-discovery/classes/paladin/dps-rotation-cooldowns-abilities-pve), YouTube TheRealBlayst (https://www.youtube.com/watch?v=PIjJ2pcnLVQ).
- **Weapon speed thresholds**: 3.8 speed highest SoC proc rate (44.3%); 3.6 common raid speed (~42%); slow weapon ≥3.0s required. Source: YouTube Parse 101 (https://www.youtube.com/watch?v=HgfrDRO2uFU), TikTok acrnmwow.
- **SoC Rank 1 only**: max rank drains mana; use Rank 1 for twisting. Source: YouTube TheRealBlayst.
- **Mana math**: twisting gives ~100-200 DPS boost over not twisting (cap ~2600 DPS, CS ~400-450 DPS); twisting at 100% uptime ooms in 1-2 min without mana support (50 mana on hit T6 bonus, JoW, Shamanistic Rage). Source: Reddit r/classicwowtbc (https://www.reddit.com/r/classicwowtbc/comments/n9pvba/tbc_classic_paladin_detailed_seal_twisting_guide), Warmane forum.
- **Triple proc**: twist shortly before AA → white hit + SoB from white + SoC chance + SoB from SoC = up to 3 bonus attacks on one swing. Source: Warmane forum.

## Druid

- **Powershift timing**: Furor + Wolfshead = 60 energy on shift; energy tick 20 every 2s; cycle 4s (shift at ~4.5s before 5s tick to catch tick → 80 energy). Source: Warcraft Tavern (https://www.warcrafttavern.com/tbc/guides/feral-dps-powershifting-rotation-guide), boosting-ground (https://boosting-ground.com/wow-classic/guides/the-burning-crusade-guides/tbc-classic-feral-druid-dps-rotation-powershifting).
- **Energy ticks don't reset on form change**: ticks continue every 2s regardless of form. Source: Warcraft Tavern.
- **Wolfshead vs T6**: 2pc T6 reduces Mangle cost by 5 (35 energy) → non-Wolfshead rotation; Wolfshead comparable in P3, non-Wolfshead better in P5 BiS. Source: Warcraft Tavern.
- **Snapshot rules**: Rip damage snapshots at cast; don't clip early; maintain Mangle debuff. Source: Reddit r/classicwowtbc (https://www.reddit.com/r/classicwowtbc/comments/1vj8c76/feral_cat_rotation).
- **GCD**: 1s in cat, 1.5s in caster/when shifting. Source: Warcraft Tavern.

## Shaman

- **WF ICD**: 3s internal cooldown on Windfury Weapon (cannot proc for 3s after proc, even dual wielding; cannot circumvent with multiple ranks); no ICD on Windfury Totem. Max 20 procs/min. Source: Warcraft Tavern advanced shaman guide (https://www.warcrafttavern.com/tbc/guides/advanced-shaman-guide-part-1), us.forums.blizzard.com (https://us.forums.blizzard.com/en/wow/t/enhance-windfury-weapon-vs-totem/887503).
- **Weapon sync**: prioritize slowest weapons both MH and OH for double WF. Source: Warcraft Tavern.
- **Totem twist**: WF totem pulses 9s buff; drop GoA between → ~83% GoA uptime; 3s GCD lockout; lose ~20% shock / ~10% stormstrike damage; twist on 8-10s counter. Source: enhancementshaman.wordpress.com (https://enhancementshaman.wordpress.com/2008/02/20/twisting-totems), Warmane forum (https://forum.warmane.com/showthread.php?t=355968).
- **Mana**: Judgement of Wisdom + Shamanistic Rage (9920 mana) + Mana Spring Totem for twisting sustain. Source: enhancementshaman.wordpress.com.
- **Downranking**: spell coefficients; use wowdownrank.ozgar.se. Source: Warcraft Tavern.

## Uncertainty / unreachable

- warcraftlogs.com is bot-walled (not scraped); claims above rely on EJ archives, class Discords, wowtbc.gg, icy-veins, wowhead, warcrafttavern, reddit, youtube transcripts.
- `[uncertain]` pet ability scaling coefficients; exact TBC (non-Forever) rage formula constants at level 70 (274.7 conversion) from community testing, not official.
- `[uncertain]` SoC proc rates (44.3% at 3.8) from community parse data, not official.
- `[uncertain]` WF totem pulse timing (9s) and GoA uptime (83%) from community testing.
- EJ archives (web.archive.org) referenced but not directly scraped in this pass; links in Warcraft Tavern guide.
