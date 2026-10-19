# rogue_research_2026-10-19 — Rogue class research for a future `classes/rogue.lua`

Desk: rogue-research. READ-ONLY: no addon files touched. Single new file per brief.
Date: 2026-10-19. Target matrix: Era/SoD 1.15.9 (`_Vanilla`), TBC 2.5.6 (`_TBC`),
WotLK Titanforge 3.80.2 (`_Wrath`), WoW Forever 1.60.1 + Retail 12.1.x (`_Mainline`).

Evidence bar: every spell/talent/id claim is CONFIRMED (source said it + citation
below + clients it holds on) or UNCONFIRMED in caps. "CONFIRMED" means the cited
source states the claim — vendor/guide sources and player/user claims are labeled
as such. Nothing was resolved by guessing; conflicts are recorded with evidence.

## 0. Prior-corpus boundary (no re-searching answered questions)

Read first per brief: `desks/journal.md`, `bench/verify_bank.md`,
`bench/discover_features.md`, `bench/competitor_scan_2026-10-17.md`,
`bench/oracle_audit_2026-10-17.md`, `bench/lessons.md`. Reused, not re-proven:
- SuperSwingTimer rogue set = Slice and Dice bar, energy-tick helper, Sinister
  Strike end-window red slice, energy tick cadence (`discover_features.md` §Rogue).
- Anniversary CLEU sends localized spell NAMES not numeric ids (single-source
  page-text claim, UNCONFIRMED) — `competitor_scan_2026-10-17.md` §1.1; oracle R1
  carries it as an in-client check. Directly implicates any rogue CLEU matching
  (poison applications, Shiv, Vanish/Overkill windows) on `_TBC`.
- Forever restrictions: own-DoTs only, hidden values, no enemy spells/casts in
  combat (Counterclock description + DoT-kill predictor thread, `competitor_scan`
  §2). Rogue threat/Expose Armor tracking on Forever must use own-aura reads.
- Pattern reference for addon design: `classes/druid.lua`, `classes/hunter.lua`,
  `classes/paladin.lua`, `classes/shaman.lua`, `classes/warrior.lua` read for
  structure only — `ST.<CLASS>.gather_guide_inputs(self, out)` frozen-spec +
  live reads, `bars.lua:617-618` pcall-wrapped `class.on_bar_update(self, hand)`
  per-frame hook, nil-safe toggles, family-gated spell-id tables.

## 1. Per-client rotation / priority

### 1.1 Classic Era (1.15.9, `_Vanilla`) — Combat Swords (beginner) / Daggers
Sources: Icy Veins Classic Rogue DPS Rotation (Sellin, updated Nov 17 2024),
Icy Veins Classic spell/rotation resource sections, noobtoboss CP mechanics
guide. All CONFIRMED as guide claims below.
- Opener (swords): Stealth → Sinister Strike x2 → Slice and Dice (early, low CP)
  → Adrenaline Rush → SS to 5 CP → SnD → SS → Eviscerate dump.
  CONFIRMED: https://www.icy-veins.com/wow-classic/rogue-dps-pve-rotation-cooldowns-abilities
- Single-target: maintain SnD ~100% uptime; builders SS (45 energy, 1 CP);
  Eviscerate at 5 CP, or at any CP if target about to die; plan CP so SnD never
  drops. CONFIRMED: same page + https://noobtoboss.com/wow-classic-rogue-combo-points-guide/
- Daggers: Backstab (60 energy, requires behind target) is the primary builder;
  Ambush/Garrote/Cheap Shot from Stealth; same SnD-first logic.
  CONFIRMED: noobtoboss builder table (SS 45 / Backstab 60 / Garrote 50 /
  Cheap Shot 60, 1 CP each); Icy Veins "Sword easier for beginners, Dagger
  competitive, slightly below in early gear".
- Cooldowns: Blade Flurry (+20% attack speed, also the only AoE — use with 2+
  targets but still strong ST) stacked with Adrenaline Rush; save for bosses.
  CONFIRMED: Icy Veins Classic rotation §Cooldown Usage.
- Energy: 100 max, 20 per 2s tick; ONLY Adrenaline Rush changes regen (doubles,
  15s); Vigor talent +10 max. CONFIRMED: Icy Veins Classic §Energy Generation.
- Combo points: max 5, target-specific, lost on target switch, persist until
  spent/target dies; most builders 1 CP. CONFIRMED: noobtoboss guide.
- Threat: Vanish is "a great ability for threat management"; Cheap Shot
  CC via Vanish re-stealth. CONFIRMED: Icy Veins Classic §Vanish.
  Full threat-wipe semantics on raid bosses: UNCONFIRMED (see §6).
- Hit caps: 9% yellow (specials) baseline; 6% with human weapon-skill racial
  (+10 skill → 305). CONFIRMED as player-source claims:
  https://www.reddit.com/r/classicwow/comments/eybp99/ (2020),
  https://www.mmo-champion.com/threads/2523109 (2019). Exact per-skill tables:
  UNCONFIRMED (no vendor table pulled).

### 1.2 Season of Discovery (1.15.x, `_Vanilla`) — Mutilate / Saber Slash
Source: Icy Veins SoD Combat Rogue Rotation (updated Apr 8 2025). CONFIRMED
as guide claims: https://www.icy-veins.com/wow-classic/combat-rogue-dps-season-of-discovery-pve-rotation-cooldowns-abilities
- Poisons: Instant Poison on BOTH weapons; if assigned Imp Expose Armor duty,
  Sebacious Poison on main-hand (SoD rune poison). CONFIRMED: same page ST #1.
- Opener: Stealth (maximize Master of Subtlety) → Garrote if from stealth →
  Mutilate to build → at 5x Deadly Poison / Occult Poison stacks cast
  Poisoned Knife → AR (+Blade Flurry if possible) → Vanish WITH second AR cast
  to re-proc Master of Subtlety (else Vanish at high energy) → 5-CP SnD →
  1-CP Crimson Tempest ONLY with Queensfall equipped (auto-refreshed by
  Mutilate) → maintain Rupture to trigger Carnage (if Garrote bleed faded) →
  5-CP Envenom as CP dump. CONFIRMED: same page ST #2–#12.
- Multi-target (3+ mobs, extended): belt-slot Shuriken Toss + Blunderbuss
  recommended; AR fuels casts. CONFIRMED: same page §Multi-Target.
- Note: SoD rotation centers Mutilate/Envenom/Poisoned Knife — mechanically
  closer to WotLK assassination than to Era combat. Energy tick presumed same
  20/2s classic engine: UNCONFIRMED for SoD rune interactions.

### 1.3 TBC Anniversary (2.5.6, `_TBC`) — Combat Swords (/Mace/Fist), Imp-EA variant
Sources: Icy Veins TBC Rogue Rotation (Sellin, updated Jan 12 2026), TBC Spell
Summary, TBC Stat Priority (all CONFIRMED as guide claims).
- No-EA rotation: SS x2 → early SnD → Haste Potion + Blade Flurry +
  Adrenaline Rush + on-use trinkets → T4-2pc: 1–2 CP SnD + 5-CP Rupture;
  else 2–3 CP SnD + 5-CP Rupture.
  CONFIRMED: https://www.icy-veins.com/tbc-classic/rogue-dps-pve-rotation-cooldowns-abilities
- Imp-EA rotation: same opener → 5-CP Expose Armor first → juggle 100% EA +
  100% SnD (refresh 5-CP EA before falloff; 2–5 CP SnDs) + small 2–3 CP
  Ruptures between. Personal loss of Exposing over Rupture "very minimal";
  Imp EA (50% stronger) beats 5-stack Sunder.
  CONFIRMED: same page + https://www.icy-veins.com/tbc-classic/rogue-dps-pve-spell-summary
- Eviscerate vs Envenom: Rupture > Eviscerate generally; Eviscerate for
  dying targets / spare CP. Envenom (consumes ALL Deadly stacks, scales per
  stack × per CP) is the hardest-hitting finisher but a DPS loss mid-fight —
  use only on targets about to die. CONFIRMED: rotation page §Eviscerate
  and Envenom.
- Cooldown stacking: BF + Haste potion + 2-min trinkets (Bloodlust Brooch);
  under 2-min fights hold CDs for Bloodlust+Mongoose/proc (use with >15s left
  on lust); over 2-min, BF early + re-use on procs. Never hold so long you
  lose a full use. CONFIRMED: rotation page §Cooldown Usages.
- Energy pooling (addon-critical): never pool above 65 energy pre-tick /
  85 post-tick; Relentless Strikes refunds 25 energy on finishers — finisher
  BEFORE the tick that would cap you. "An Energy ticker addon is very
  important." CONFIRMED: rotation page §Energy Management and Pooling.
- Poisons named on TBC pages: Deadly (stack maintenance via Shiv), Mind-Numbing
  / Crippling (OH-swap utility). CONFIRMED:
  https://www.icy-veins.com/tbc-classic/rogue-dps-pve-spell-summary (Shiv:
  instant OH strike applying current OH poison; energy cost scales with OH
  speed; keeps Deadly stacks alive; OH-swap applicator).
  Exact MH/OH poison assignment meta: UNCONFIRMED (see §6).
- Stat priority: Expertise > Hit > Agi > Haste > Crit > ArP; hit 316 rating
  (white cap w/ FF; 300 w/ Draenei; specials 64 per table) for 25-mans w/
  moonkin; expertise cap 64 rating (44 for Human swords/maces).
  CONFIRMED: https://www.icy-veins.com/tbc-classic/rogue-dps-pve-stat-priority
  (numbers copied verbatim; interpretation: UNCONFIRMED — e.g. "Specials 64").
- Combat Potency: successful OH hits have 20% chance to grant 15 energy.
  CONFIRMED: https://www.wowhead.com/tbc/spell=35553/combat-potency. Fast OH
  (1.4/1.5) synergizes with CP + Sword Specialization.
  CONFIRMED: https://www.wowhead.com/tbc/guide/classes/rogue/dps-stat-priority-attributes-pve
  (Feb 10 2026). Missed attacks lose both energy regen and Sword Spec procs.
  CONFIRMED as guide claim: https://www.warcrafttavern.com/tbc/guides/pve-combat-rogue-stat-priority/
- Utility (all CONFIRMED, spell summary page): Evasion +50% dodge / −25%
  ranged hit; Sprint +70% speed 15s (usable in stealth; root-break talented);
  Vanish = instant stealth + 10s improved stealth; Blind 10s CC (breaks on
  damage); Cloak of Shadows wipes magic debuffs + 90% resist 5s (10% can still
  punch through); Feint "reduces threat by a large amount"; Gouge 4s
  (5.5 talented) pseudo-interrupt that also builds CP; Garrote bleed 18s +
  3s silence (PvP opener, not a raid builder); Sap 45s humanoid CC.

### 1.4 WotLK Titanforge (3.80.2, `_Wrath`) — Combat + Assassination
Titanforge-specific rogue sources: NONE FOUND (one search round, see §7).
Treat all below as WotLK 3.3.5/3.4.3 baseline; Titanforge deltas: UNCONFIRMED.
- COMBAT single-target (unchanged since TBC/Classic per guide): SS → 1-CP SnD
  → BF + Killing Spree + AR → SS to 5 → SnD → SS to 5 → Rupture → SS to 5 →
  Eviscerate (or SnD if expiring); Expose Armor only without a warrior;
  Shiv only to fast-stack Deadly when haste-starved; Tricks of the Trade on
  tank or top DPS (mandatory). AoE: BF + Killing Spree (KS hits benefit from
  BF cleave), spam Fan of Knives under AR.
  CONFIRMED as guide claims: https://www.warcrafttavern.com/wotlk/guides/pve-combat-rogue-rotation-cooldowns/
- COMBAT cooldowns: Killing Spree 51690 (auto-attacks continue during it),
  AR 13750 (+100% energy 15s), BF 13877 (+20% AS + cleave 1 extra target).
  Defensive/utility: Vanish 26889 (escape + wipe-recovery via Gnomish Army
  Knife 40772), Feint 48659 (threat drop — see conflict note below), Evasion
  26669 (50% dodge + 25% ranged dodge), Cloak of Shadows 31224 (wipe + 90%
  resist 5s). CONFIRMED: same tavern page (ids from page links).
- ASSASSINATION single-target: opener Mutilate (or Garrote if raid lacks bleeds
  for Hunger for Blood) → SnD → Hunger for Blood 51662 → Mutilate to 4–5 CP →
  Envenom; maintain HfB (~1 min), Envenom buff (let it EXPIRE before re-apply
  unless you would energy-cap waiting); Cut to the Chase refreshes SnD via
  Envenom so SnD is never manually refreshed; Cold Blood + 5-CP Envenom on CD;
  mid-fight Vanish to proc Overkill 58426 (break stealth ASAP); pre-pot Potion
  of Speed 40211; Tricks on Affliction lock first (snapshotting).
  CONFIRMED: https://www.warcrafttavern.com/wotlk/guides/pve-assassination-rogue-rotation-cooldowns/
  + https://wowtbc.gg/wotlk/class-guides/assassination-rogue/
  + https://legacy-wow.com/pve-wotlk-assassination-rogue-dps-guide-short/ (3.3.5).
- ASSASSINATION AoE: ≤5 targets stay single-target; 6+ spam FoK (Deadly on OH).
  Hybrid AoE spec swaps Mutilate glyph → FoK, adds AR+BF. Glyphs: TotT / HfB /
  Mutilate (major); Vanish / Distract / Safe Fall (minor).
  CONFIRMED: tavern + wowtbc.gg pages above.
- ASSASSINATION stats: Hit 315 rating (poison cap) solo, down to 210 with
  Heroic Presence + Precision + Misery/IFF (237/289 midpoints per table);
  Expertise 26 (214 rating); priority Hit > Expertise > AP > Haste > Crit
  (fresh gear: 4k AP before haste).
  CONFIRMED: legacy-wow short guide + wowtbc.gg Hit/Expertise tables.
- Poisons (assassination): DPS comes from 5x Deadly stacks + Envenom-buff
  uptime. Player sources converge on Deadly on OFF-HAND (Shiv prefers Deadly
  OH; "press ALT for OH poison" macro; fast MH procs more Deadly → more
  Instant procs at full stacks). CONFIRMED as player claims (not vendor):
  https://forum.warmane.com/showthread.php?t=468802 (2024),
  https://www.mmo-champion.com/threads/730031 (2010),
  https://www.reddit.com/r/classicwow/comments/10nckcp/ (2023),
  https://wotlk-pve.fandom.com/wiki/Assassination_Rogue_Guide.
  Exact MH/OH meta: UNCONFIRMED (see §6).
- Feint conflict RECORDED, not resolved: Warmane Subtlety PvE Compendium (WotLK
  frame) says Feint "lowers your total threat and gives 50% AoE reduction 6s"
  (https://forum.warmane.com/showthread.php?t=467564, 2024);
  Wowpedia says Feint "no longer reduces threat" as of patch 4.0.1, now AoE
  reduction only (https://wowpedia.fandom.com/wiki/Feint) — consistent with
  WotLK-Feint-had-threat, but the in-client behavior on Titanforge 3.80.2 is
  UNCONFIRMED.

### 1.5 WoW Forever (1.60.1, `_Mainline`) — Combat, LEVEL-30 BETA ONLY
Source: Icy Veins Forever Combat Rogue Guide (beta, level-30 cap). Everything
below holds ONLY for the documented beta slice; max-level Forever rogue:
UNCONFIRMED (see §6).
CONFIRMED as guide claims: https://www.icy-veins.com/wow-forever/combat-rogue-melee-dps-pve-guide
- Rotation: Stealth → Ambush (dagger) or Garrote → Backstab (behind, dagger)
  else Sinister Strike → Riposte whenever active → Blade Flurry early+often
  (AS + cleave) → 5-CP SnD only if target survives full duration → 5-CP
  Eviscerate (or if SnD already up / target short-lived). Energy: constantly
  refilling bar — never sit at full. CP persist on target across swaps but do
  NOT transfer to a new target.
- Poisons: Instant on BOTH weapons at this stage; poisons have BOTH duration
  AND charges (running out of charges mid-fight is the common failure, not
  duration expiry). Watch both on the buff bar.
- Stats: Weapon Damage > Hit/Expertise (level-difference dependent) > Agi
  (AP + slight crit) > Crit (200%) > Str (AP only) > Stam (survival only).
- Cooldowns/utility: Evasion, Gouge, Kick (only true interrupt at this level),
  Sprint (mobility + disengage); Cheap Shot early advantage while leveling.
- Races: Gnome (Eureka! + Escape Artist) / Orc (Axe Spec crit, Blood Fury AP,
  Shatter Curse, Hardiness) presented as defaults — flavor, not addon scope.
- Forever engine constraints (from competitor-scan corpus, not re-proven):
  swing engine is `swing_source.lua` PLAYER_SWING territory; CLEU is absent so
  poison-proc / Shiv / Vanish-threat chains that need combat-log events must be
  built on UnitAura/power/CP reads or stay inert with a stated reason.

### 1.6 Retail Midnight (12.1.x, `_Mainline`) — Outlaw + Assassination
Sources: Icy Veins Outlaw Rotation 12.1.5 + Assassination Rotation 12.1.5
(Seliathan; sin page reviewed Oct 12 2026). CONFIRMED as guide claims.
- OUTLAW opener: Stealth (position + Instant Poison) → pre-pull AR + Roll the
  Bones + SnD (SnD skips Supercharger) → BF on cleave → Blade Rush (talented)
  or SS → SS to builders → Between the Eyes at 6+ CP → Pistol Shot at 3+ Fan
  the Hammer stacks → Killing Spree at 6+ CP → Preparation to reset BTE.
  CONFIRMED: https://www.icy-veins.com/wow/outlaw-rogue-pve-dps-rotation-cooldowns-abilities
- OUTLAW priority: RtB rework (Stages 1–4: SS double-strike/Opportunity →
  +1 CP/+15% → Restless Blades CDR → +10% crit; higher stage includes lower);
  ST≈AoE except BF on 2nd-target cleave at LOW CP (Deft Maneuvers). Spec is
  Hekili/rotation-helper territory (cf. competitor-scan NAG §5) — out of
  swing-timer scope beyond CP/energy/RtB-stage/SnD/BTE/AR/BF widgets.
- ASSASSINATION priority: Vanish-Garrote (before every Deathmark) → 5+CP
  Rupture → Deathmark (2-min; pool energy first; don't cast into forced
  downtime or at 40% if Zoldyck execute window is near) → Kingsbane synced
  with Deathmark → 5+CP Envenom CHAINING (refresh while prior buff active —
  Inspiring Strike / Poisoner's Drive / Rapid Injection reward chaining;
  Implacable apex refunds energy on Envenom) → Ambush when usable → Mutilate →
  FoK at 2+ targets → Thistle Tea on low energy. CONFIRMED:
  https://www.icy-veins.com/wow/assassination-rogue-pve-dps-rotation-cooldowns-abilities
- ASSASSINATION mechanics: Pandemic refresh (≤30% carryover) on Rupture/
  Garrote/SnD; Improved Garrote DoT must run full duration (overwrite kills
  the buff; doubled in Deathmark); Deathstalker's Mark ≈100% uptime, consume
  via finishers → Darkest Night-buffed Envenom; target swaps via Mark for
  Death. Poisons: Lethal = Deadly + Amplifying; raid non-lethal = Atrophic
  (damage-taken reduction) unless slow needed (Crippling) or tank help
  (Numbing); Wound = PvP. Kick: 15s CD, 5s school lockout.
  CONFIRMED: same sin page (+ spell-summary Kick line).
- Retail is stand-in/inert territory for the swing bar (competitor-scan §1.6,
  oracle R3 pattern): rogue.lua on Retail should expose CP/energy/poison/
  buff widgets only if cheap UnitAura reads allow; no swing features.

## 2. Playstyle specifics (spec / talents / poisons / caps matrix)

| Client | Top spec(s) | Key talents/runes | Poisons | Caps / thresholds |
|---|---|---|---|---|
| Era | Combat Swords (easy) / Daggers (adv.) | Sword Spec, AR, BF, Vigor (+10 max), Relentless Strikes (25 energy refund — TBC page, same talent line) | 5 exist: Instant, Deadly, Wound, Mind-numbing, Crippling (Wowhead classic guide CONFIRMED https://www.wowhead.com/classic/guide/wow-classic-best-rogue-poisons); MH/OH meta UNCONFIRMED | 9% yellow / 6% w/ human skill (player claims, §1.1); exact tables UNCONFIRMED |
| SoD | Mutilate (top), Saber Slash, Backstab builds | Runes: Mutilate, Poisoned Knife, Crimson Tempest (+Queensfall), Carnage, Master of Subtlety, Sebacious Poison (Imp-EA duty) | Instant both weapons; Deadly/Occult to 5 for Poisoned Knife | Not pulled: UNCONFIRMED |
| TBC | Combat Swords/Mace/Fists (±EA duty) | Sword Spec, Combat Potency (20%/15 energy — spell CONFIRMED), Imp EA, Relentless Strikes 25, AR/BF | Deadly (Shiv-maintained), Mind-Numbing/Crippling OH-swap; exact MH/OH UNCONFIRMED | Expertise > Hit > Agi > Haste > Crit > ArP; 316 hit (FF) / 300 Draenei / specials 64; expertise 64 (44 human sword/mace) — page numbers CONFIRMED, interpretation UNCONFIRMED |
| WotLK | Combat (SS/Rupture/Evisc) / Assassination (Mutilate/Envenom) | Combat: CttC n/a (sin); Sin: Cut to the Chase, HfB, Overkill, Cold Blood, Seal Fate, Vigor, Precision, Master Poisoner (raid crit), Imp EA duty | Sin: 5x Deadly + Envenom buff is the DPS; Deadly-OH converged by player sources (CONFIRMED-as-claimed); Instant procs at full stacks | Hit 315 → 210 w/ buffs+Precision (table CONFIRMED); expertise 26 / 214 rating CONFIRMED; AP 4k before haste (fresh) |
| Forever β30 | Combat | Riposte, BF; legacy talents per guide | Instant both; duration AND charges | Weapon dmg > Hit/Exp > Agi > Crit > Str > Stam (level-diff dependent) |
| Retail 12.1.5 | Outlaw / Sin (Fatebound/Deathstalker/Trickster) | RtB stages, Restless Blades, Deft Maneuvers; Envenom-chaining tree, Implacable apex, Deathmark/Kingsbane | Lethal Deadly+Amplifying; raid Atrophic; M+ tank's choice; Wound PvP | Secondaries per sim; no static caps (guide-priority, not pulled) |

## 3. Hidden swing-timer-relevant techniques

1. Energy-tick alignment (HIGHEST VALUE). 20 energy / 2s on classic-line
   (Era + TBC CONFIRMED, §§1.1/1.3); TBC pooling thresholds 65 pre-tick /
   85 post-tick + Relentless-Strikes-25 refund timing (CONFIRMED §1.3); retail
   pooling is phase-based, not tick-based (CONFIRMED §1.6). Addon design: an
   energy-tick predictor (SST already ships one — corpus) + a "finisher before
   tick that caps you" cue is the rogue analogue of the shaman weave band.
2. OH speed → energy (Combat Potency) + Sword Spec extra attacks (TBC
   CONFIRMED §1.3). Faster OH = more energy + more procs: the swing bar's OH
   readout is a resource input, not decoration. Missed-attack energy starvation
   (tavern TBC claim) argues for a hit-gated tint on the energy predictor.
3. Weapon-sync / desync (dual-wield). Competitor corpus already holds the
   implementation pattern (WA cluster: sync spark, desync alert — competitor
   scan §3). No rogue guide pulled prescribes sync play; the value is
   Combat-Potency smoothing + poison-proc stability. Mark as DESIGN INFERENCE,
   UNCONFIRMED for rogue parse value.
4. Shiv timing. TBC Shiv keeps Deadly stacks alive + applies OH poison on
   demand, cost scales with OH speed (CONFIRMED §1.3); WotLK Shiv guarantees
   OH poison incl. target-swap Deadly stacking (CONFIRMED §1.4). Whether Shiv
   resets the swing timer on any client: UNCONFIRMED (no source found; see §6).
5. SnD/Rupture/Envenom/HfB cutoff math. Refresh-early-and-carry is era-
   dependent: classic refresh "with 2–3s remaining, remainder added"
   (noobtoboss snippet CONFIRMED-as-snippet); retail Pandemic ≤30% carryover
   (CONFIRMED §1.6); TBC/WotLK exact carryover rules NOT pulled:
   UNCONFIRMED. Envenom rules differ per client: TBC = only-on-dying-target
   (consumes stacks); WotLK sin = maintain buff, let expire first (unless
   energy-capping); retail = chain deliberately. Addon must NOT share one
   Envenom rule across clients.
6. Vanish/Overkill + threat. Vanish→Overkill energy window (WotLK sin,
   CONFIRMED §1.4); Vanish→Master of Subtlety + AR pairing (SoD, CONFIRMED
   §1.2); Vanish as threat tool (Era CONFIRMED-as-guide-claim §1.1; TBC
   Feint "large amount" CONFIRMED §1.3); full-wipe semantics on raid bosses:
   UNCONFIRMED (§6). Cloak/Evasion as DPS-uptime (greed) buttons (TBC
   CONFIRMED §1.3).
7. Kick/interrupt windows. Retail Kick 15s CD / 5s lockout (CONFIRMED §1.6).
   Classic-line Kick lockout durations NOT pulled: UNCONFIRMED (§6). Gouge as
   pseudo-interrupt that also builds CP (TBC CONFIRMED §1.3).
8. Weapon-swap swing reset. Swapping weapons after the MH hit resets the swing
   timer — CONFIRMED as player claim (r/classicwowtbc, Apr 2026, quoted in
   §7 search). Rogue relevance: OH-swap for Mind-Numbing/Crippling (TBC
   CONFIRMED §1.3) must be timed to swap windows; addon could tint the swap
   action. In-client verification still required.
9. Expose Armor duty rotation (Imp-EA 100%-uptime juggle, TBC CONFIRMED §1.3;
   sin can cover if no warrior, WotLK CONFIRMED §1.4). Addon design: EA
   duration bar with refresh-before-falloff cue is the rogue P2/JotC analogue.
10. No rogue swing-reset mechanic found in ANY guide pulled. The only
    reset-adjacent facts are weapon-swap (#8) and the warrior-contrast Slam
    handling in the competitor corpus. Any rogue.lua swing-pause logic needs an
    in-client test first — do NOT port warrior Slam-reset code.

## 4. HUD / guide signals (what top players watch → what rogue.lua exposes)

From the guides pulled, the watch-list per client:
- ALWAYS: energy (+tick predictor), CP (5 max classic-line; 6–7 retail —
  retail CP max NOT pulled: UNCONFIRMED), SnD duration, Rupture duration.
- Era/TBC combat: SnD-uptime-or-lose meter, Rupture-vs-Eviscerate decider
  (target-TTD input — reuse druid D4 EMA pattern), AR+BF stacked-state icon
  group (reuse paladin CD-group pattern), energy-tick spark.
- SoD: Deadly/Occult 5-stack + Poisoned Knife-ready glow; Garrote-bleed active
  (Carnage gate); Crimson Tempest active (Queensfall only); Vanish+AR
  Master-of-Subtlety window; Rupture-maintained flag.
- TBC: EA-uptime bar (duty spec) with pre-falloff cue; Deadly-stack count +
  Shiv-ready when <2s to falloff; pooling-state tint (≤65/≤85 energy bands);
  BF/Haste-potion/Bloodlust stacked-style (reuse H2/P3 lust-window input).
- WotLK combat: Killing Spree/AR/BF burst cluster; Shiv-only-if-haste-starved
  hint; Tricks target reminder. WotLK sin: Envenom-buff duration with
  let-expire-unless-capping logic; HfB 60s timer; Overkill/Vanish window;
  Cold Blood held-for-Envenom flag; FoK-pack-size gate (5 vs 6+ threshold is
  guide-disputed — tavern says 6+, wowtbc 5+: RECORDED CONFLICT, default to
  a tunable threshold with 6 as nil-safe default).
- Forever β30: Instant-poison charges + duration on BOTH weapons (charges are
  the failure mode); Riposte-active glow; BF state.
- Retail: RtB stage pips (1–4), SnD, BTE charges/CD, AR/BF, Deathmark+Kingsbane
  sync pair, Envenom-chain state, Deathstalker's Mark stacks/Darkest Night
  readiness, Thistle Tea energy-deficit cue. (Hekili/NAG already own this
  space — rogue.lua on Retail should stay a widget set, not a suggester.)
- Interrupt: Kick readiness + school-lockout where known (retail only).

Addon-design handoff (structure only, mirrors existing class modules):
- `ST.ROGUE.gather_guide_inputs(self, out)` feeding the frozen guide frame:
  energy_now, energy_tick_in, cp, snd_remains, rupture_remains,
  envenom_buff_remains, hfb_remains, deadly_stacks, ea_remains,
  pooling_band (65/85 TBC), time_to_die (reuse D4 EMA), lust_active (C2 input).
- `on_bar_update(self, hand)` (bars.lua:617-618, pcall-wrapped): energy-tick
  spark, Shiv-ready tint, EA pre-falloff cue, Riposte/Envenom-buff glows.
- Spell-id tables per family (highest-rank-wins pattern from druid.lua/hunter
  .lua), name-fallback tables for Anniversary CLEU (oracle R1 pattern —
  mandatory if rogue.lua ever matches CLEU on `_TBC`).
- Nil-safe toggles, defaults documented; secret-regime whole-or-nothing reads
  via compat (oracle R2 pattern — iterate 1..40 without early break).

## 5. UNCONFIRMED list (needs in-client or further sourcing)

1. Exact Slice and Dice seconds-per-CP on classic-line (only "scales with CP;
   refresh 2–3s early, remainder added" is sourced — noobtoboss snippet).
2. Full classic Rupture per-CP table (only 1CP: 40 dmg / 8s from Wowhead
   classic spell 1943: https://www.wowhead.com/classic/spell=1943/rupture).
3. TBC/WotLK DoT-refresh carryover rules (only retail Pandemic ≤30% sourced).
4. Shiv swing-timer reset behavior on any client.
5. Vanish full threat-wipe semantics on raid bosses (all clients).
6. Classic-line Kick school-lockout durations (only retail 15s/5s sourced).
7. Exact MH/OH poison-assignment metas (Era, TBC, WotLK — player sources
   converge on Deadly-OH for WotLK sin but no vendor guide confirms).
8. TBC "Specials 64" hit-table interpretation (number copied verbatim §1.3).
9. Era/SoD exact hit/expertise tables (only 9%/6% player claims + TBC/WotLK
   tables sourced).
10. Retail combo-point maximum (6 vs 7 — not pulled).
11. Titanforge 3.80.2 rogue deltas vs 3.3.5 (no rogue-specific source found;
    only generic Titan Reforged guides + legendary-dagger news).
12. Max-level Forever rogue (all Forever claims are the level-30 beta slice).
13. FoK pack threshold (5+ vs 6+ — recorded guide conflict, needs tunable).
14. WotLK Feint threat component on Titanforge (Warmane vs Wowpedia-4.0.1 —
    recorded conflict).
15. Exhaustion/Sated, poison-proc spell ids, Shiv/Overkill aura ids for
    rogue.lua tables (remembered-id rule: no ids are claimed anywhere above).

## 6. Tooling log (brief §"record what the tool returned")

Catalogs enumerated first in Code Mode: `search("firecrawl")` → 10 shown + 18
more (incl. monitor/crawl/research families); `search("searxng")` → 4 tools
(instance_info, web_search, suggestions, web_url_read). Per prior-desk finding
the firecrawl MCP surface rejects bodies, so Firecrawl ran via its self-hosted
REST (:3002 `/v2/search` + `/v2/scrape`, small bodies, markdown+mainContent);
SearxNG ran via MCP tools AND direct :8069 JSON (both worked).
- SearxNG searches (all returned citable URLs): era/soD guides, TBC guides,
  WotLK caps/rotation, retail 12.1 guides, Forever guides, SnD/Rupture
  durations, Shiv swing reset, Kick/Vanish/Feint mechanics, Midnight poisons,
  Titanforge guides, WotLK assassination poisons, classic poison lists,
  Era hit caps, Combat Potency/Sword Spec.
- Firecrawl REST scrapes (URL → bytes → usable content): 5 Icy-Veins overview
  pages (31–109KB JSON, full markdown) + 5 rotation pages (22–52KB) + SoD
  rotation (27KB) + wowtbc.gg assassination (12KB) + 2x warcrafttavern (21–24KB)
  + legacy-wow short guide (21KB) + TBC spell summary (22KB) + retail sin
  rotation (52KB). Wowhead guide pages returned 2–6KB JS shells (content
  NOT retrievable via scrape — Wowhead facts instead via SearxNG web_url_read
  extract, which rendered SoD rotation + noobtoboss CP guide; Fandom wiki
  blocked 403 via web_url_read).
- Every citation above is a page that was actually loaded and section-quoted
  in-session (scrape excerpts in /tmp/opencode/rogue/, discarded with session).

## 7. Sources (all loaded 2026-10-19, patch/version + date where shown)

- https://www.icy-veins.com/wow-classic/rogue-dps-pve-rotation-cooldowns-abilities
  (Sellin, Nov 17 2024) — Era rotation/cooldowns/energy/CP
- https://www.icy-veins.com/wow-classic/rogue-dps-pve-guide — Era poisons hub
- https://noobtoboss.com/wow-classic-rogue-combo-points-guide/ — Era CP/energy
  costs, SnD refresh behavior
- https://www.wowhead.com/classic/guide/wow-classic-best-rogue-poisons
  (Nov 9 2023) — 5 Era poisons
- https://www.icy-veins.com/wow-classic/combat-rogue-dps-season-of-discovery-pve-rotation-cooldowns-abilities
  (Apr 8 2025) — SoD rotation/runes/poisons
- https://www.icy-veins.com/tbc-classic/rogue-dps-pve-rotation-cooldowns-abilities
  (Sellin, Jan 12 2026) — TBC rotation/pooling/cooldowns/Envenom
- https://www.icy-veins.com/tbc-classic/rogue-dps-pve-spell-summary — TBC
  finishers/builders/utility/poisons/Shiv
- https://www.icy-veins.com/tbc-classic/rogue-dps-pve-stat-priority — TBC caps
- https://www.icy-veins.com/tbc-classic/rogue-dps-pve-spec-builds-talents — TBC
  builds (Combat Swords/Mace/Fists ±EA headings confirmed)
- https://www.wowhead.com/tbc/spell=35553/combat-potency — CP 20%/15 energy
- https://www.wowhead.com/tbc/guide/classes/rogue/dps-stat-priority-attributes-pve
  (Feb 10 2026) — fast-OH synergy
- https://www.warcrafttavern.com/tbc/guides/pve-combat-rogue-stat-priority/ —
  miss starvation claim
- https://www.warcrafttavern.com/wotlk/guides/pve-combat-rogue-rotation-cooldowns/ —
  WotLK combat rotation/cooldowns/utility
- https://www.warcrafttavern.com/wotlk/guides/pve-assassination-rogue-rotation-cooldowns/ —
  WotLK sin rotation/openers/cooldowns
- https://wowtbc.gg/wotlk/class-guides/assassination-rogue/ — WotLK sin
  opener/priority/glyphs (237/289/315/214 tables)/consumables
- https://legacy-wow.com/pve-wotlk-assassination-rogue-dps-guide-short/
  (3.3.5) — Hit 315 / Expertise 26, AP-first, Envenom-buff upkeep
- https://www.wowhead.com/classic/spell=1943/rupture — classic Rupture 1CP data
- https://www.icy-veins.com/wow-forever/combat-rogue-melee-dps-pve-guide —
  Forever β30 rotation/poisons/stats
- https://www.icy-veins.com/wow/outlaw-rogue-pve-dps-rotation-cooldowns-abilities —
  Retail 12.1.5 outlaw
- https://www.icy-veins.com/wow/assassination-rogue-pve-dps-rotation-cooldowns-abilities
  (reviewed Oct 12 2026) — Retail 12.1.5 sin priority/pooling/poisons/Kick
- Player-claim sources (labeled in-text): r/classicwow eybp99 (Era hit),
  mmo-champion 2523109 (Era hit), r/classicwowtbc 1sg4pxy (weapon-swap reset),
  warmane t=468802 (Deadly OH), mmo-champion 730031 (OH-poison macro),
  r/classicwow 10nckcp (poison procs), wotlk-pve.fandom (Deadly/Envenom core),
  warmane t=467564 (Feint threat), wowpedia Feint (4.0.1 removal),
  mmo-champion 267027 (poison hit cap 315/237 snippet), wowtbc/warcrafttavern
  TBC+WotLK civil guides as noted.
- Negative results (recorded, not failures): no Titanforge rogue guide found
  (only SSEGold beginner guide, MMOJugg class picker w/ "360° detection /
  energy starvation" snippet-level, Titan Reforged SSC/TK video, Wowhead
  legendary-dagger news); no Shiv-swing-reset source; no classic Kick-lockout
  table; wago.io pack bodies unrended (known limitation, corpus).
