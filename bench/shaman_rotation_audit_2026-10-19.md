# shaman rotation audit vs wowsims sims — 2026-10-19

Desk: shaman-rotation. Scope: read-only. Our files: classes/shaman.lua,
shaman_guide.lua, weave.lua, tests/shaman_state.lua,
tests/shaman_guide_state.lua, tests/weave_state.lua.
Sim sources: wowsims/sod, wowsims/classic, wowsims/tbc-new,
wowsims/forever (all `master`), plus wowsims.github.io (characterised only).

## Source map (sim rotation = UI APL JSON + spec test wiring)

- SoD: `ui/enhancement_shaman/apls/phase_4.apl.json`, `phase_6.apl.json`
  (P6 latest, P4 level-60 comparison); tests wire SyncType Auto.
  Rune ids: `proto/shaman.proto:97-98,111-113,116-117`
  (FeralSpirit=440580, LavaBurst=408490, LavaLash=408507,
  MoltenBlast=425339, MaelstromWeapon=408498, MentalDexterity=415140).
- Era: `wowsims/classic/.../ui/enhancement_shaman/apls/default.apl.json`.
- TBC: `wowsims/tbc-new/.../ui/specs/shaman/enhancement/apls/default.apl.json`;
  spec wiring `sim/shaman/enhancement/enhancement_test.go`
  (SyncType Auto, WF/WF imbues, ShieldProcrate 0).
- Forever: `wowsims/forever/.../ui/specs/shaman/enhancement/builds/testing.build.json`
  (rotation embedded; 2H-only ItemFilter, imbue variants WF/FT/FB/RB).
- wowsims.github.io: built-site mirror repo (branches + PR from wowsims/s*).
  No rotation logic of its own — distribution surface only. Not cited further.

## Cross-sim findings (apply to every client)

1. MATCH — Stormstrike on cooldown, never delayed. All four sims cast SS
   unconditionally at its priority slot (SoD P6 #5, P4 #10; Era #5;
   TBC action #2; Forever #9). No sim holds SS for any ICD.
   CONFLICT — our rule 7 WAIT (`shaman_guide.lua:246-250`, impl
   `shaman_guide.lua:179-184`, pure `weave.lua:441-445`, badge/wash
   `classes/shaman.lua:1529-1535,1593-1633`) delays SS while the WF ICD
   clears inside the swing. Impact: every delayed SS risks CD drift and lost
   SS casts over a fight for an unproven proc gain. No sim backs it.
   Recommend orchestrator decision: remove or gate behind an explicit opt-in.
2. GAP — autocast cooldowns lead every sim (SoD P6 #2, Era #4, TBC #5,
   Forever #3: trinkets/racials). Our engine has no on-use-pop cue at all.
   Impact: medium (free DPS, portable as a prompt). No file to cite — absent.
3. GAP — Flame Shock refresh timing. All sims re-apply FS only when the dot
   is INACTIVE (`not dotIsActive`); none refresh early. Ours refreshes at
   <= 3 s (`shaman_guide.lua:238-241`, default
   `shaman_guide.lua:164`). Impact: low-medium (early refresh clips ~3 s of
   dot + spends the GCD early, every cycle).
4. GAP — multi-target Chain Lightning. SoD sim: MW >= 4 (not 5) AND
   targets >= 2 → CL 10605 r4 (P6 #8, P4 #6). Our engine is MW5-only
   (`shaman_guide.lua:226-228`) with no target-count input (already deferred,
   `shaman_guide.lua:127-129`). Impact: medium on cleave; needs an
   enemy-count sensor that does not exist.
5. MATCH — FS duration 12 s. SoD sim 4 ticks x 3 s
   (`sod/sim/shaman/flame_shock.go:34-35`); TBC SS debuff 12 s
   (`tbc-new/sim/shaman/stormstrike.go:16`); TBC SS CD 10 s (`:78-80`).
   Matches `weave.lua:397,491-492`, swipe 10
   (`classes/shaman.lua:2334-2335,2579-2587`).
6. MATCH — Fire Nova 15 s CD on TBC (`tbc-new/sim/shaman/fire_totems.go:141-143`,
   spell 25537) vs `classes/shaman.lua:126-127` + swipe 15. TBC Magma 20 s
   (10 ticks x 2 s, `:80,102-103`) vs `weave.lua:601`,
   `classes/shaman.lua:167`. Searing 25530 (`:16`) has no slot in our engine.
7. Technique — Lava Burst deals bonus damage with FS on target (both
   `sod/sim/shaman/lava_burst.go` and `forever/sim/shaman/lava_burst.go`;
   Forever notes Lightning Overload skips LvB). Neither sim gates LvB on FS —
   ordering emerges from priority, not a condition. Our spender
   (`weave.lua:95-100`) matches the no-gate shape; the FS-first micro
   ordering is unsurfaced. Impact: low.

## SoD (ERA family + MW-observed latch)

Sim shape (P6; P4 noted where different): Feral Spirit 440580 >
autocast CDs > Shamanistic Rage 425336 at mana <= 65% > Lava Burst 408490
iff swing-fit (`autoTimeToNext >= cast + 100 ms`, ANY stacks) > SS >
Lava Lash 408507 > Lightning Bolt 15208 iff swing-fit (ANY stacks) >
CL 10605 iff MW >= 4 and targets >= 2 > Lightning Shield 10432 >
FS 29228 iff inactive (P6 also requires fight > 12 s) > Earth Shock 10414 >
Molten Blast 425339 > Searing 10438 iff inactive and fight > 30 s. P4 adds
Berserking 26297 on CD and potion <= 55%; P1 consumes run Rockbiter MH+OH.

- MATCH — swing-fit weave model. Sim condition `autoTimeToNext >= cast+100ms`
  is exactly our latest-safe-start model (`weave.lua:225-236`) with 0.1 s
  latency. Our position row (`classes/shaman.lua:1826-1955`) is the sim rule
  made visible.
- CONFLICT — MW-stack gating. Sim weaves LB/LvB at ANY stack count when the
  cast fits (including 0-1: hardcast filler). Our guide is MW5-only
  (`shaman_guide.lua:226-228`); our assist gates at >= 2
  (`weave.lua:130-133`). The assist is closer to the sim than the guide.
  Impact: high for SoD (guide stays silent while sim casts). Our MW5-only
  stance cites Wrath min/max; SoD sim disagrees.
- GAP — Feral Spirit never prompted (sim #1). Our slot id 51533
  (`classes/shaman.lua:161-162`) is Wrath-only; the known gate
  (`classes/shaman.lua:2305-2310`) feeds nil on SoD, so rule 3
  (`shaman_guide.lua:222-224`) is dead there. Impact: high. Fix direction:
  name-based resolution like LvB (`classes/shaman.lua:372-397`).
- GAP — Lava Lash never prompted (sim #6 P6 / #13 P4, unconditional). Same
  Wrath-id cause (60103, `classes/shaman.lua:168`). Impact: high.
- GAP — Molten Blast 425339 has no slot at all (sim unconditional filler).
  Impact: high. No file to cite — absent.
- GAP — Shamanistic Rage at mana <= 65% (sim #3 P6/P4). No SR rule in our
  engine (deferred, `shaman_guide.lua:110-117`). Note threshold differs from
  TBC's 10%. Impact: medium-high (mana sustain defines SoD enhance).
- GAP — WF ICD is 1.5 s in the SoD sim
  (`sod/sim/shaman/windfury_weapon.go:68`), not 3 s. Our strip
  (`weave.lua:320`), S3 hold (`weave.lua:441-445`) and rule 7 all use 3 s.
  Impact: medium (strip overstates ICD; WAIT holds up to 2x too long on SoD).
- GAP — SoD Stormstrike CD is 6 s (`sod/sim/shaman/stormstrike.go:37-39`),
  not 10. Our swipe 10 (`classes/shaman.lua:2335,2580`) is wrong pre-first-cast
  (live client length rides after). Impact: low.
- MATCH — MW rune gate shape. Sim CL-multi uses `auraIsKnown(408505)`;
  our ERA latch (`weave.lua:84-88`, `classes/shaman.lua:563-571`) is the
  same idea. SoD P1 Rockbiter consumes support the Rockbiter badge
  (`classes/shaman.lua:107-110,1639-1677`).
- Divergence noted, not a gap — Searing (fight > 30 s opener) vs Magma:
  SoD P6 runs Searing, no Magma; our Magma is WRATH-only
  (`classes/shaman.lua:2466`), correct to stay silent on SoD, but Searing has
  no slot. Impact: low-medium.

## Era (classic repo default APL)

Sim shape: prepull LS 10442 > WF totem 10614 > GoA 10627 > Searing 10438;
priority LS refresh > WF totem 10614 refresh (imbue buff 10611 <= 1.5 s) >
GoA 10627 when inactive > autocast CDs > SS > Searing iff fight > 20 s >
ES 10414 iff mana >= 50%. No Flame Shock. No Fire Nova. No MW (none exists).

- CONFLICT — Flame Shock. Our rule 5 (`shaman_guide.lua:238-241`, nil always
  refreshes) prompts FS maintain on Era; the sim never casts FS on Era
  (mana-starved, no runes). Impact: high for ERA family (wrong GCD + mana
  every cycle). Recommend family-gating rule 5 off on ERA without MW-observed.
- GAP — mana-gated filler. Sim ES only at mana >= 50%; ours unconditional
  (rule 12, `shaman_guide.lua:265-267`). Mana tint exists
  (`classes/shaman.lua:2672-2675`) but never suppresses the prompt. Impact:
  medium on Era.
- GAP — Searing Totem maintain (fight > 20 s). No slot. Impact: medium.
- GAP — Fire Nova prompted (rule 10) where sim runs none on Era. Impact:
  low-medium (FN totem competes with Searing for the fire slot).
- MATCH — no weave on Era (`weave.lua:84-88` ERA+unlatch=false;
  `classes/shaman.lua:586-591`), no twist (TBC-only `weave.lua:582-583`),
  WF-totem name fallback covers 10614 (`classes/shaman.lua:94,686-696`).
  GoA 10627 static (not twist) on Era — our skeleton feed stays nil there
  (`classes/shaman.lua:2489-2493`), correct.

## TBC (tbc-new repo default APL)

Sim shape: SR group (mana < 10%, configurable 5/10/20/30) > SS >
Fire Ele group (ready AND trinket-stack → WoA 3738 + weapon-swap + FE 2894) >
Totems group (twist WF 25587 when imbue-buff 25580 <= 0.5 s; GoA 25359
<= 5 s gated on WF-buff >= 5 s or not-twisting; static SoE 25528, MS 25570
<= 5 s) > autocast CDs + stat-buff CDs > Shocks (FS 25457 iff target lacks
it and fight >= 12 s; filler ES 25454 default, Frost 25464 optional) >
Fire Totems (FN 25537 twisted, suppressed while Fire Ele out; Magma 25550
filler incl. overwriting Searing; Searing 25530 fallback or when mana low).

- GAP — Shamanistic Rage (mana < 10%): no rule. Impact: medium-high.
- GAP — Fire Ele snapshot setup: WoA-first + weapon swap + trinket stacking.
  Swap is not portable (combat lockdown); the line-up cue is. Our rule 2
  (`shaman_guide.lua:220-221`) fires bare. Impact: medium.
- GAP — twist keyed on the weapon-imbue buff (<= 0.5 s re-drop), not a drop
  timer. Ours: 10 s stamp timer (`weave.lua:574-575,588-595`,
  `classes/shaman.lua:705-721,2489-2493`). Cadence matches (~9.5-10 s);
  the buff-keyed re-drop is self-correcting (covers resist/miss). Impact:
  medium. Hidden technique: GoA re-drop gated on WF-buff >= 5 s (never
  overwrite a fresh WF early).
- GAP — mana-pause on twisting (sim pauses at 10%, configurable); max-rank
  twisting (sim twists 25587, no downrank). CONFLICT with our downrank note
  (`classes/shaman.lua:130-148`, `weave.lua:548-568` "twist with WF rank 1").
  Impact: medium — sim sustains max-rank twist via mana pause instead.
- GAP — Magma Totem on TBC (sim default filler fire totem). Our Magma is
  WRATH-only (`classes/shaman.lua:2466`). Impact: medium-high for TBC.
- CONFLICT — Fire Nova while Fire Ele is out. Sim suppresses FN when the
  fire slot holds Fire Ele (`auraIsInactive 2894`); our rule 10
  (`shaman_guide.lua:258-260`) fires whenever SS is down, which would
  replace a live Fire Ele totem. Impact: medium (wasted 10-min CD). Needs a
  fire-slot-occupancy guard.
- MATCH on default — Earth filler (rule 12) vs sim default Earth; Frost
  option absent in ours (documented `shaman_guide.lua:125`). Gap only if the
  option is wanted.
- MATCH — WF ICD 3 s shared (`tbc-new/sim/shaman/weapon_imbues.go:98`)
  backs `weave.lua:320-331` on TBC only; totem has no ICD (same source,
  backs `weave.lua:324-330` comment).

## Forever (testing build rotation)

Sim shape: potion < 80% + Demonic Rune 12662 < 70% > autocast CDs >
air totem 10614 / earth totem 25361 / fire Searing 10438 when slot empty >
Fire Nova 408345 iff Clearcasting 16246 > LS 10432 > SS 17364 >
MW5 (auraIsKnown 408505, stacks >= 5) → LB 15208 >
FS 29228 iff inactive > ES 10414 > Fire Nova 408345 iff mana > 10%.
2H-only, imbue variants WF/FT/FB/RB. No twist (matches
`weave.lua:582-583`). Sim ASSUMES MW exists at 60 (auraIsKnown gate) —
backs our unconditional Forever read (`weave.lua:71-77`), outcome-equivalent
(stacks stay 0 if it does not exist).

- GAP — static totem maintain on Forever (WF 10614, earth 25361, Searing).
  No maintain feed on Forever (twist gate false, Magma WRATH-only). Also id
  mismatch: our twist slot is 8512 (`classes/shaman.lua:129,2342`) while
  Forever drops 10614 (name fallback `classes/shaman.lua:148` would catch
  "Windfury Totem" only through the twist path, which is family-dead).
  Impact: medium.
  **CORRECTED 2026-10-20** (desk `corpus-corrections`): 8512 is a real
  **Windfury Totem rank-1** id (the client's rank-1 fallback), so the twist
  slot is not a wrong id — and the **TBC APL's own air-slot rows cast 25587 r5
  (Windfury) / 25359 r3 (Grace of Air)**, which is a *filed* question about
  the twist row's ranks, not an error in this file. Evidence:
  `bench/shaman_apl_utility_build_2026-10-20.md` §2 **C5**;
  `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **S5**.
- GAP — Clearcasting (16246) → Fire Nova. No Clearcasting input anywhere in
  our engine. Hidden Forever technique: free FN on Elemental Focus proc.
  Impact: low-medium (proc frequency dependent).
- GAP — Fire Nova as mana-dump filler (mana > 10%, below ES). Our FN sits
  above LL/ES (`shaman_guide.lua:258-267`); sim ranks it lowest. Impact: low
  (ordering only).
- MATCH — MW5 → LB shape (`shaman_guide.lua:226-228`); FS re-apply on
  expiry (same early-refresh divergence as §3); SS unconditional (same
  rule-7 conflict as §1); 2H meta makes our DW badge moot by design
  (`classes/shaman.lua:1987` hides without OH).
- Note — consumable weaving (potion/rune thresholds) is out of addon scope.

## Wrath — no sim repo in scope (coverage gap)

wowsims/wotlk was not in the brief's URL set. Our WRATH rules
(`shaman_guide.lua:110-117`) were validated against
`docs/research/rotations_wrath.md` only, which is itself guide-derived and
WCL-unconfirmed (doc `:3`). Divergences vs that doc: SR #5 on CD/line-up
(no rule — GAP, same as TBC/SoD); ES "when FS active" (doc `:115`) vs ours
unconditional fallback (minor); MW "3+ stacks even better, don't clip"
(doc `:109`) vs our MW5-only + clip model (our clip guard is the "don't
clip" half; the sub-5 hardcast half is rejected by design). Recommend a
follow-up lane against wowsims/wotlk when available. Validation owner:
orchestrator.

## Ranked gaps (all clients)

1. Rule-7 WAIT hold contradicts every sim (SS always on CD). Remove or opt-in.
2. SoD Feral Spirit / Lava Lash / Molten Blast missing (sim top-half).
3. ERA Flame Shock over-prompt (sim: never on Era).
4. TBC Magma + FN-while-Fire-Ele guard + SR (10%) + buff-keyed twist.
5. WF ICD 1.5 s on Era/SoD sims vs hardcoded 3 s (strip + hold + rule 7).
6. FS early-refresh (<= 3 s) vs re-apply-on-expiry (all sims).
7. SoD SR-65% / TBC SR-10% thresholds (no SR rule anywhere).
8. CL multi-target rule MW >= 4 + targets >= 2 (needs enemy-count sensor).
9. Forever totem maintain + Clearcasting→FN.
10. Wrath coverage: no wotlk sim repo checked.

## UNCONFIRMED (could not verify from sim sources)

- 16387 (Forever hidden prepull), 25361 name (earth totem by slot
  elimination; likely Strength of Earth custom rank), 25570 name (water slot
  by elimination; likely Mana Spring TBC rank), 425339 role (Molten Blast by
  rune-enum `proto/shaman.proto:113`, cast shape = instant filler).
- SoD SS 6 s CD trigger (rune vs base — sim models flat 6 s).
- In-client feel of every finding; sims are not the game (notably Forever,
  whose sim bakes 2H + custom ids).
