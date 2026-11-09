# bench/druid_rotation_audit_2026-10-19 — druid rotation vs wowsims sims, per client

Desk: druid-rotation-audit (subagent, read-only). Date: 2026-10-19.
Scope: `classes/druid.lua`, `druid_guide.lua`, `druid_energy.lua`,
`tests/druid_state.lua`, `tests/druid_guide_state.lua` vs the wowsims sims.
No addon file edited; no git; no existing bench file overwritten.
Evidence bar: every sim claim cites a fetched raw file (URL below) or a
local file read this session. `wowsims.github.io` carries no sim code
(verified 404 below) — the Wrath sim lives in `wowsims/wotlk`.
In-client behavior is UNCONFIRMED throughout; sim-match is not client proof.

## 0. Sources (all fetched or read this session — no invented URLs)

Our files (line refs verified by read):
- `classes/druid.lua` — engine: Maul queue/rage (`:90-:210`), TF proc gain
  `:389`, debuff ids `:424-:443`, SR fallback `:498`, player-buff scan
  `:658-:682`, TF proc supplier `:684-:697`, energy tick `:717-:784`
  (TBC anchor `:738-:744`), shred-countdown cost `:834-:846`, TTD sampler
  `:1541-:1589`, gather `:1594-:1748`, guide table `:1750-:1770`.
- `druid_guide.lua` — pure engine + frozen spec: slots `:12-:17`,
  inputs `:19-:84`, rules `:86-:117`, TBC `:119-:151`, FOREVER `:153-:174`,
  ERA `:175-:193`, WRATH `:195-:230`, SOD `:232-:260`, bear `:270-:291`,
  constants `:310-:364` (TBC costs `:317-:318`, T6 `:319`, 12s `:330`,
  Wrath TF/Berserk `:337-:339`, FB minima `:343-:344`, execute 10s `:349`,
  SoD TF 40 `:352`, Forever SP 40/60 `:363-:364`), eval TBC `:468-:497`,
  SOD `:498-:549`, ERA `:550-:562`, WRATH `:563-:626`, legacy+F1 `:627-:663`.
- `druid_energy.lua` — tick 2.0s `:19`, gain 20 `:23`, window 19–22 `:25-:29`,
  EMA alpha 0.25 / 0.25s `:31-:40`, glow 4s `:42`.
- `tests/druid_state.lua`, `tests/druid_guide_state.lua` — offline pins
  (T1 4CP Rip, W8 execute, SoD TF<=40, legacy 4.0s windows).
- Local research (read): `docs/research/rotations_sod.md`,
  `docs/research/rotations_era_sod.md`, `docs/research/rotations_wrath.md`,
  `docs/research/tbc_minmax.md`, `docs/research/forever_beta.md`;
  `bench/verify_bank.md` (§2 TF/Berserk ids), `bench/competitor_gaps_2026-10-19.md`
  (§Druid D1/D2).

Sim files (raw, fetched 2026-10-19):
- ERA/runeless: https://raw.githubusercontent.com/wowsims/classic/master/sim/druid/feral/rotation.go
- SoD: https://raw.githubusercontent.com/wowsims/sod/master/sim/druid/feral/rotation.go
- SoD TF KotJ/+60: https://raw.githubusercontent.com/wowsims/sod/master/sim/druid/tigers_fury.go
- SoD SR durations 14/19/24/29/34: https://raw.githubusercontent.com/wowsims/sod/master/sim/druid/savage_roar.go
- SoD APL values (pooling commented out): https://raw.githubusercontent.com/wowsims/sod/master/sim/druid/feral/apl_values.go
- TBC: https://raw.githubusercontent.com/wowsims/tbc-new/master/sim/druid/feralcat/rotation.go
- TBC cat setup (MangleCat, Wolfshead 8345, drums/BL scheduling): https://raw.githubusercontent.com/wowsims/tbc-new/master/sim/druid/feralcat/feralcat.go
- WRATH: https://raw.githubusercontent.com/wowsims/wotlk/master/sim/druid/feral/rotation.go
- FOREVER SP (40 energy, 16s, not-at-full): https://raw.githubusercontent.com/wowsims/forever/master/sim/druid/shifting_power.go
- FOREVER mechanics (Furor/Wolfshead+5/ISPP8s/mana55%/Maul-queue/prowl): https://raw.githubusercontent.com/wowsims/forever/master/sim/druid/feralcat/mechanics_test.go
- FOREVER APL bestCatAPL (ceiling 50, pooling 2s/1s, bite-end, omen-fish, Claw): https://raw.githubusercontent.com/wowsims/forever/master/sim/druid/feralcat/apl_sweep_test.go
- FOREVER rotation tests (Monocat stays Cat, Bites-only-at-end, Rake-kept-up, Berserk-with-builder): https://raw.githubusercontent.com/wowsims/forever/master/sim/druid/feralcat/rotation_test.go
- `wowsims.github.io`: https://api.github.com/repos/wowsims/wowsims.github.io/contents/sim?ref=master
  → 404 (no `sim/` tree; the Wrath sim is `wowsims/wotlk`, listed above).

Client map used below: ERA→classic, SOD→sod (ERA+sod_runes),
TBC→tbc-new, WRATH→wotlk (Titanforge 3.80.2 target; guides are 3.4.3),
FOREVER→forever (1.60.x). RETAIL short-circuits inert
(`druid_guide.lua:424-:435`) — no sim comparison (no Retail swing).

## 1. ERA — Classic Era 1.15.9 runeless (`inputs.family == "ERA"`, no runes)

Sim: classic `rotation.go` `doRotation` — Clearcast→Shred; else
`(cp >= MinCombosForRip || canRipTrick) && canRip`→Rip; else ShredTrick→Shred;
else PrimaryBuilder (= Shred; `setupRotation` picks Shred, MangleCat nil).
`canRip`: Rip active→false; 5CP needs fight>8s else >10s; trick→true.
Whole loop is powershift: `tryPowershift`, `shiftNow` when
`nextEnergy < cost || timeToNextTick > MaxWaitTime`, `shouldPoolMana` with
Furor, OOM events, `poolEnergy` at 5CP. `MaintainFaerieFire` option.

| # | Verdict | Our side | Sim side | Note |
|---|---|---|---|---|
| E-1 | MATCH | Builder Shred; ungated builder (`druid_guide.lua:550-:562` E2) | PrimaryBuilder Shred (`rotation.go` setup) | Both default to Shred where Mangle is untalented |
| E-2 | CONFLICT (HIGH) | E1: 5CP→Bite, never Rip (`druid_guide.lua:552-:557`); header "Rip never prompted on Era" (`:185-:188`) | 5CP finisher is Rip with 8s/10s fight gates; FB never appears (active `canBite` commented out) | If an Era user follows E1 they Bite where the sim Rips. Our own header marks the Era chain "byte-identical" to legacy research, not to the sim |
| E-3 | GAP (HIGH, by design) | No SHIFT ever (REMOVED notes `druid_guide.lua:127-:134`, `:181-:183`) | Entire Era DPS is powershifting (Furor/Wolfshead, shift <10 energy, OOM tracking) | Accepted: no honest Furor/Wolfshead probe (gather writes `can_powershift=nil`, `classes/druid.lua:1646-:1656`). Do not close without a probe |
| E-4 | GAP (MED) | No Clearcast rule on ERA | `isClearcast→Shred` first branch | Omen exists on Era (talent); sim spends the proc on Shred |
| E-5 | GAP (MED) | No trick inputs | `canShredTrick` / `canRipTrick` energy windows before tick/shift | Hidden technique: squeeze-a-cast windows (`timeToNextTick>1s`, `[ripCost,mangleCost)` bands) |
| E-6 | GAP (MED) | ERA never reads `time_to_die` | Rip fight gates 8s (5CP) / 10s (else) | Our D4 sampler feeds TTD (`classes/druid.lua:1654`) but ERA ignores it |
| E-7 | MATCH | No Mangle on runeless Era; bear 3e waits (`druid_guide.lua:96-:99`, `:456-:461`) | MangleCat nil → builder Shred; no Mangle branch | Both agree Era-base has no Mangle |
| E-8 | MATCH | Tick 2.0s / 20 / window 19–22 (`druid_energy.lua:19-:29`) | `core.EnergyPerTick`, `core.EnergyTickDuration`, `NextEnergyTickAt` (`rotation.go` throughout) | Same cycle model |

## 2. SoD — ERA token + `sod_runes` (`inputs.family == "ERA"`, `sod_runes == true`)

Sim: sod `rotation.go` `doRotation` — SR (cp≥1, !hasRoar) → Clearcast Shred →
Rip (`cp≥MinCombosForRip||ripTrick` + `canRip(sim,isTrick,usingRoar)` with
Roar-expiry `timeToCast` math + 8s/10s fight gates) → clipRoar → ShredTrick →
PrimaryBuilder (Mangle if talented else Shred). KotJ TF: +60 energy, 30s CD,
+15% phys (`tigers_fury.go` `registerTigersFurySpellKotJ`). SR: 25 energy,
durations 14/19/24/29/34 by CP (`savage_roar.go`). `setupRotation` hardcodes
`UseRipTrick=false`.

| # | Verdict | Our side | Sim side | Note |
|---|---|---|---|---|
| S-1 | MATCH | S1 TF ≤40 (`druid_guide.lua:507-:513`, `:352`) | KotJ +60 (`tigers_fury.go`); `docs/research/rotations_sod.md:136` | 100−60 headroom both sides |
| S-2 | MATCH | D2 proc-aware tick strips +60 (`classes/druid.lua:389`, `:684-:697`; `druid_energy.lua:76-:100`) | KotJ `AddEnergy(60.0)` (`tigers_fury.go`) | Same grant modelled |
| S-3 | MATCH | S3 SR ≥1CP expired→HOLD (`druid_guide.lua:519-:523`) | First branch SR when `!hasRoar` (`rotation.go`) | Expiry-only upkeep both sides |
| S-4 | GAP (MED) | No early-clip rule | `clipRoar`: fresh Roar covering the fight clips now; min-roars projection | Hidden technique: Roar-clip math saves full casts |
| S-5 | MATCH | S4 Omen→Shred (`druid_guide.lua:524-:526`) | `isClearcast→Shred` | Same proc spend |
| S-6 | CONFLICT (MED) | S5 5CP Rip, preferred under TF (`druid_guide.lua:527-:533`); header admits "may clip" (`:245-:246`) | Active `canRip` has NO TF-snapshot term; never clips (Rip-active→false) | We may clip a healthy Rip for the snapshot; sim would not. Doc (`rotations_sod.md:137`) wants TF-Rip; sim does not encode it |
| S-7 | CONFLICT (MED) | S7 Rake expired→rake (`druid_guide.lua:537-:540`) | Active `doRotation` has NO Rake branch at all | We match the doc (`rotations_sod.md` step 3) and the commented-out optimal `rakeNow`, but not the live sim path |
| S-8 | CONFLICT (MED) | S8 capped-CP Bite (`druid_guide.lua:541-:544`, "in-game to confirm") | No Bite anywhere in active rotation (`canBite` commented out) | Doc priority (`rotations_sod.md:121-:141`) lists no FB either. Our own UNCONFIRMED flag stands |
| S-9 | GAP (MED) | Fixed S1 ≤40, S2 TF-burned (`druid_guide.lua:507-:518`) | No Berserk branch in active rotation (MCD layer); `canShredTrick`/`shouldPoolMana` + WildStrikes wait | ShredTrick windows + WildStrikes pooling have no guide expression |
| S-10 | GAP (HIGH, by design) | Powershift REMOVED (`druid_guide.lua:255-:258`) | `tryPowershift`/`shiftNow`/OOM core loop; `poolMana` + `numShiftsToOom` | Same accepted probe gap as E-3 |
| S-11 | MATCH (partial) | SR fallback 34s (`classes/druid.lua:498`) | 5CP 34s (`savage_roar.go` 9+25) | Lower-CP durations (14–29s) not modelled — GAP LOW |
| S-12 | GAP (LOW) | FF pull-only, manual (SOD appendix note `druid_guide.lua:259-:260`) | `MaintainFaerieFire` + powershift-FF (`rotation.go` `tryPowershift`) | Opener-only; manual is the documented stance |

## 3. TBC — 2.5.6 (`inputs.family == "TBC"`)

Sim: tbc-new `feralcat/rotation.go` (NerdEgghead port). Powershift loop:
`<10 energy→shift`; `ripNow = cp≥RipCP && !ripDebuff (+ripweave ≥52 energy)`,
gated `remaining≥10s` (`RipEndThresh`); `biteAtEnd` (cp≥BiteCP, last 10s);
`mangleNow` (MangleCat && !ripNow && !mangleDebuff); `biteBeforeRip`
(`ripEnd−now ≥ BiteTime=0`); BiteTrick (2+CP, energy in `[biteCost,39]`,
`timeToNextTick>ReactionTime`); RakeTrick (energy in `[biteCost,mangleCost)`,
`>1s+Reaction`, `!rakeDebuff`); MangleTrick (2×mangle−20 … 22+mangle,
`≤1s`, `UseMangleTrick`); `≥22 energy` Shred/Mangle ladder; OOM branch;
`MaxWaitTime=1s`; Wolfshead 8345 (`feralcat.go` `HasItemEquipped(8345)`);
Faerie Fire maintenance.

| # | Verdict | Our side | Sim side | Note |
|---|---|---|---|---|
| T-1 | MATCH (partial) | T1 4+CP Rip expired, no window (`druid_guide.lua:476-:478`) | `ripNow` expiry-only (`!ripDebuff`), no window | Sim RipCP is user-config (`setupRotation` `RipMinComboPoints`); we freeze 4CP — GAP MED on the threshold |
| T-2 | CONFLICT (MED) | "Rake is never prompted on TBC" (`druid_guide.lua:135-:139`) | RakeTrick exists (`UseRakeTrick`, `[biteCost,mangleCost)` window) | Hidden technique we exclude by policy; sim Rakes situationally |
| T-3 | GAP (HIGH) | T3 only 5CP short-lived Bite (`druid_guide.lua:484-:486`) | BiteTrick (2CP/≤39 energy) + `biteAtEnd` execute + `BiteOverRip` mode + `biteBeforeRip` (BiteTime 0) | We miss the whole Bite-trick subsystem |
| T-4 | GAP (MED) | No ripweave | `ripweaveNow` (cp≥RipTrickCP, un-debuffed, energy≥52) | Early-Rip energy window |
| T-5 | GAP (MED) | T2 static 40 / live cost (`druid_guide.lua:479-:483`) | MangleTrick double-Mangle window + `UseMangleTrick` | We gate affordability; sim also gates a two-for-one window |
| T-6 | MATCH | Mangle 40 / Shred 42 (`druid_guide.lua:317-:318`); live `mangle_cost` probe (`:382-:390`; `classes/druid.lua:1668-:1681`) | Dynamic `CurrentMangleCatCost/CurrentShredCost` | Same cost model; 2pc-T6 35 (`druid_guide.lua:319`) mirrors `tbc_minmax.md:34` — sim read-through UNCONFIRMED both sides |
| T-7 | GAP (HIGH, by design) | Powershift REMOVED (`druid_guide.lua:127-:134`) | `<10→shift`, Wolfshead, OOM events, `waitingForTick`/`readyToShift` + latency | Accepted probe gap. NEW EVIDENCE: sim uses Wolfshead **8345** (`feralcat.go`), matching `verify_bank.md` D1 — our "no verified Wolfshead id" (`druid_guide.lua:129-:130`) is contradicted by sim source (still needs in-client confirm) |
| T-8 | CONFLICT (LOW) | `SHORT_LIVED_TTD_SECONDS=12` (`druid_guide.lua:330`) | `RipEndThresh=10s` (`rotation.go`) | 2s delta on the short-fight line |
| T-9 | MATCH | TBC anchor survives form flips (`classes/druid.lua:704-:711`, `:738-:744`) | — | Matches `tbc_minmax.md:32-:33` (ticks continue 2s regardless of form); sim has no reset either |
| T-10 | GAP (LOW) | No FF rule | `MaintainFaerieFire` first branch | Manual per our stance |

## 4. WRATH — 3.80.x (`inputs.family == "WRATH"`)

Sim: wotlk `feral/rotation.go` — `doTigersFury` (energy < 40−10×leeway,
leeway=max(gcdLeft,latency)+1s-if-clearcast, not during Berserk; Lacerateweave
delay); `berserkNow` (ready && !waitForTf && Rip active && !clearcast;
`waitForTf` from TF/Berserk CD phasing; Lacerateweave final-Berserk delay);
`roarNow` (cp≥1 && (!SR || `clipRoar` with Glyph-of-Shred-extended Rip
projection, `MinRoarOffset` 12–34s by set, `RipLeeway` 4s)); `ripNow`
(5CP, !Rip, remain≥10s, `ripCcCheck`); `biteAtEnd`/`biteBeforeRip`
(`canBite`: Rip≥BiteTime && SR≥BiteTime) / `biteNow` (`!clearcast`,
energy<67; ≤25 in Berserk `BerserkBiteThresh`); `mangleNow` (`!ripNow` &&
refresh/clipMangle with earliest-Mangle math); `rakeNow` (`UseRake`, !Rake,
remain>duration, `rakeCcCheck` + `RakeDpeCheck` trinket-DPE + glyph-extension
`remainingExt/maxShredsPossible` math); FF (`ffThresh` 87 / 15-in-Berserk,
`waitForFf`, end-of-fight spend math); pooling (`pendingPool` over
Rip/Rake/Mangle/Roar with Berserk-halved costs → `floatingEnergy`/`excessE`);
bear/flowerweave, snekweave, powerbear, MangleSpam/InFrontOfTarget, cap-Shred.
Doc: `docs/research/rotations_wrath.md:85-:100`.

| # | Verdict | Our side | Sim side | Note |
|---|---|---|---|---|
| W-1 | MATCH | W1–W4 order TF→Berserk→SR→Omen (`druid_guide.lua:572-:595`) | `doTigersFury`→`berserkNow`→`roarNow`→clearcast-Shred; doc steps 1–4 | Same priority spine |
| W-2 | CONFLICT (MED) | W1 static `energy<40` (`druid_guide.lua:572-:577`; `TF_ENERGY_WRATH=40` `:337`) | Dynamic `40−10×leeway` (latency/GCD/+1s if clearcast) | We over-prompt when leeway is high. Internal drift: code comment `:574` says "under 30 energy" while the constant is 40 — comment is stale |
| W-3 | GAP (MED) | W2 `energy≤85 && TF-CD≥15s` (`druid_guide.lua:578-:587`; `:338-:339`) | `berserkNow` has NO energy gate; `waitForTf` phasing + Rip-active + !clearcast | Our 85 cap is own-heuristic (doc step 2 has no number); sim phases on CDs, pools via `floatingEnergy` |
| W-4 | MATCH + GAP (MED) | W3 SR expiry-only (`druid_guide.lua:588-:592`) | `roarNow` base matches; PLUS `clipRoar` early-clip (Glyph-extended Rip projection, `MinRoarOffset`/`RipLeeway`) | Hidden technique: Roar-clip math |
| W-5 | MATCH | W5 5CP Rip expired, ungated (`druid_guide.lua:596-:601`) | `ripNow` 5CP expiry-only | Same finisher |
| W-6 | MATCH | W6 Mangle above Rake (`druid_guide.lua:602-:609`, 30% multiplier rationale) | `mangleNow` branch precedes `rakeNow` | Same order |
| W-7 | GAP (MED) | W7 plain expiry Rake (`druid_guide.lua:606-:609`) | `RakeDpeCheck` (skip Rake when Shred DPE higher on procs) + glyph-extension `remainingExt` math | Two hidden Rake gates |
| W-8 | GAP (MED) | No FF rule (manual) | `ffNow` Omen-fishing (`ffThresh` 87/15, `waitForFf`, spend math) | FF is an Omen engine, not just an opener |
| W-9 | GAP (HIGH, by design) | Bearweave NOT built (`druid_guide.lua:221-:223`) | Full weave subsystem (`weaveEnergy`/Furor cap/snek/powerbear/lacerateweave) | Documented scope cut; ~5–7% per doc |
| W-10 | CONFLICT (LOW) | W8 needs Rip≥8 && SR≥8 (`druid_guide.lua:343-:344`, `:610-:621`) | `canBite`: Rip≥BiteTime && SR≥BiteTime (BiteTime 4s, 10s bearweave) | Our 8s guard is own-heuristic ("in-game to confirm") |
| W-11 | MATCH | W8 execute last-10s (`FB_EXECUTE_TTD_SECONDS=10` `:349`) | `endThresh=10s`; doc "Bite only last 10s" | Same execute window; unknown defaults to long fight both sides |
| W-12 | GAP (LOW) | No position input | `MangleSpam`/`InFrontOfTarget` (Shred needs behind) | Can't express front-of-target Mangle |
| W-13 | GAP (LOW) | Pooling shown on tick bar (W9 `druid_guide.lua:622-:625`) | `pendingPool`→`floatingEnergy`→`excessE` gating + cap-Shred | Different pooling philosophy; ours is display, sim's is cast-gate |

## 5. FOREVER — 1.60.x (`inputs.family == "FOREVER"`)

Sim: APL `bestCatAPL` (`apl_sweep_test.go` `catAPL`): SP ceiling **50**
(clearcast −10 → 40), `wantShift = canCast(SP) && underCap`;
Rip = 5CP && !up && fight≥10s; Rake = !up (cut <6s left);
pool 2s-ahead Rip / 1s-ahead Rake (`afterBuilder` math); Bite only at end
(5CP && !long, or 3+CP <3s); FF-for-Omen (`omenFish`: !clearcast, ICD ready,
SP-left≥1s, regen<Shred/Rake/Rip costs); Clearcast→Shred (`ccShred`);
Berserk+builder sequences, Elune-after-window, Tea≤20, potion-fit, Innervate
when mana-short; Claw when Shred cannot land; Bearweave trip (≤20 energy,
SP-left≥3s) with Primal Bite+Maul. SP truth (`shifting_power.go`,
`mechanics_test.go`): +40 energy (45 Wolfshead), 16s CD (8s ISPP),
55%-base-mana, Cat-only, talent-gated, refused at full energy (Oct-8 hotfix).
Tests (`rotation_test.go`): Monocat stays Cat (only Innervate/Sapper exits),
Bites-only-at-end, Rake-kept-up (~10/90s), Berserk-with-builder.

| # | Verdict | Our side | Sim side | Note |
|---|---|---|---|---|
| F-1 | CONFLICT (HIGH) | F1 `energy≤60` (`SP_ENERGY_FOREVER=60`, `druid_guide.lua:363-:364`, `:634-:636`) | Ceiling **50** (40 if clearcast) — `underCap` math (`apl_sweep_test.go` `catAPL`) | 10-energy over-prompt; sim leaves 10-regen headroom over the GCD. Our own header flags 60/40 UNCONFIRMED (`:355-:362`) — sim now says 50 |
| F-2 | GAP (MED) | No clearcast adjustment on F1 | Clearcast ceiling −10 (`underCap`) | Omen keeps filling through the GCD — hidden headroom rule |
| F-3 | CONFLICT (MED) | F1 falls to legacy rules 4–8 with **4s refresh windows** (`druid_guide.lua:647-:655`) | Expiry-only Rip/Rake + 2s/1s pooling (`pooling`, `ripNow`/`rakeNow`) | We early-refresh (clip); APL pools and refreshes on expiry |
| F-4 | GAP (MED) | No FF rule on Forever | `omenFish` FF-for-Omen engine (ICD + SP-left + regen<cost gates) | We have the Omen glow (`classes/druid.lua:950-:964`) but no FF source |
| F-5 | CONFLICT (MED) | Legacy rule 7: 5CP→Bite anytime (`druid_guide.lua:656-:659`) | Bite only at end (`TestMonocatBitesOnlyAtTheEnd`; `biteEnd`/`biteLow`) | We Bite mid-fight; APL never does |
| F-6 | GAP (LOW) | No Claw (six slots frozen, `druid_guide.lua:262-:268`) | Claw builder when Shred cannot land (front/`CannotShredTarget`) | Position/target input missing |
| F-7 | GAP (LOW–MED) | No Berserk rule on Forever | Monocat casts Berserk 417141 with a builder (`rotation_test.go` stay-in-Cat) | Forever Berserk prompt missing |
| F-8 | MATCH | `SP_ENERGY_GAIN_FOREVER=40` (`druid_guide.lua:363`) | +40 (`mechanics_test.go` `TestShiftingPowerTradesManaForEnergy`) | Wolfshead 45 not modelled — GAP LOW |
| F-9 | MATCH (sim-confirmed) | 16s CD assumed UNCONFIRMED (`druid_guide.lua:171`, `:355-:362`) | 16s ready (`mechanics_test.go`); 8s ISPP; refused at full (`shifting_power.go`) | Sim confirms the numbers (still needs in-client); our F1 outcome-matches the hotfix (100≤60 false → dormant) |
| F-10 | MATCH | No TF rule on Forever (section-7 sweep pin, `druid_guide.lua:163`) | No TF in the APL | Both absent |
| F-11 | GAP (LOW) | Rake window 4s; Bite rule 7 | Rake kept up expiry-only (~10/90s); Tea≤20 / potion-fit / Innervate-mana-short / prepull-Clearcasting | Consumable/mana layer has no guide expression (out of scope, noted) |

## 6. Bear (all clients) — B1–B3e (`druid_guide.lua:270-:291`)

Sims model bear only via Maul-queue-on-swing (`forever`
`TestCatQueuesMaulOntoTheBearSwing`; sod/classic `maul.go`) and separate
tank sims (`sod` `sim/druid/tank`, `classic` `sim/druid/_tank`, `tbc-new`
`sim/druid/feralbear`, `forever` `sim/druid/feralbear` — listed, not
deep-read). No cat-rotation sim defines a bear DPS priority, so B1 RIDE /
B2 proven-Ma xid / B3 Mangle / B3e Era-wait have no direct sim counterpart:
NOT A CONFLICT. Note: TBC bear Mangle ranks/cooldown/debuff length stay
UNCONFIRMED in our header (`druid_guide.lua:288-:291`); Cata/Mists bear
keeping rule 3 is unassessed (same note).

## 7. Hidden techniques worth stealing (ranked, owner: orchestrator)

1. **Forever SP ceiling 50 (40 clearcast)** — correct F1 60→50 with a
   clearcast −10 (`apl_sweep_test.go` `underCap`). Small pure change, HIGH value.
2. **Pooling-before-refresh math** — `afterBuilder = energy−Shred+10 < Rip/Rake
   cost` with 2s/1s horizons (Forever) / `pendingPool`+`floatingEnergy`
   (WotLK) / `canShredTrick/canRipTrick` windows (Era/SoD). Texture: our tick
   bar already shows pooling; the engine could WAIT instead of windowing.
3. **ClipRoar** — SoD `clipRoar` (cover-to-end / cast-count projection),
   WotLK `clipRoar` (Glyph-extended Rip projection + `MinRoarOffset`).
   Pure math over durations we already gather.
4. **Omen-fishing with Faerie Fire** — WotLK `ffNow/ffThresh/waitForFf`,
   Forever `omenFish` (ICD + SP-left + regen gates). Needs an FF cooldown
   input we do not gather.
5. **TF dynamic threshold (WotLK)** — `40−10×leeway`. Replaces the frozen 40
   with GCD/latency/clearcast inputs the gather already has (`gcd_remaining`).
6. **Rake DPE + glyph-extension gates (WotLK)** — skip Rake on procs; block
   Rake when Shred extensions cannot fit before Rip falls. Needs AP/DPE
   inputs we do not gather — longer term.
7. **TBC trick trio** — BiteTrick (2CP/≤39), RakeTrick (window), MangleTrick
   (double), Ripweave (≥52). Small energy-window rules on live energy.
8. **Bite-end discipline** — everywhere the sim Bites only at the end
   (Era: never; SoD: never in active path; TBC: `biteAtEnd`; Wrath: 10s;
   Forever: end-only). Our ERA/SOD-mid-fight Bites and Forever rule 7 are the
   outliers.
9. **Wolfshead 8345** — TBC sim checks `HasItemEquipped(8345)`; our header
   says unverified. In-client check now has a concrete id to test.
10. **Bearweave/flowerweave/snekweave** — documented NOT-built; listed only so
    a future lane prices the bear-timer/rage inputs honestly.

## 8. What was NOT compared (out of scope, no claim)

- AoE rotations (`rotation_aoe.go` in sod/classic/wotlk) — guide is ST only.
- Tank sims, balance/resto, item sets, APL preset JSON on disk
  (`ui/specs/druid/feralcat/apls/` — referenced by `apl_sweep_test.go` but
  not fetched).
- `wowsims.github.io` UI presets/APL JSON (repo has no `sim/` tree — 404
  above); Wrath APL defaults in `wowsims/wotlk` `ui/` not pulled.
- In-client spell costs/cooldowns/durations — sim numbers are not client proof.

## 9. Validation

Owner: orchestrator. Method: re-fetch the raw URLs in §0, re-check each
table row's our-side line ref, confirm no bench file was overwritten
(this file is new). In-client follow-ups: Forever SP 50 vs 60 energy
headroom; TBC Wolfshead 8345 presence; SoD Rip-under-TF snapshot behavior;
Wrath TF leeway + Roar-clip + FF-fishing; Era E1 Bite-vs-Rip.
