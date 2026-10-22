# bench/wrath_leftovers_2026-10-19 — Wrath leftover verdicts vs wowsims/wotlk

Desk: wrath-sod-variants (research-only lane). Date: 2026-10-19.
Scope: the filed Wrath rows in `desks/shaman-rotation-fix/journal.md` F9
(SR line-up half, ES-on-FS micro-order, sub-5 hardcast, Lightning Shield
slot, per-client SS swipe) and the filed Druid Wrath rows in
`desks/druid-rotfix/journal.md` (TF dynamic, Berserk phasing, clipRoar-glyph
extension, Rake DPE, FF omen-fishing, pooling, Mangle cost, Bite minima,
latency term) — each checked against `wowsims/wotlk` (`master`,
fetched this session) plus the two SS-CD cross-checks
(`wowsims/sod`, `wowsims/classic`).
No addon file changed; no git; this file is NEW
(`bench/wrath_leftovers_*` globbed absent before writing).
In-client behaviour is UNCONFIRMED throughout; sim-match is not client proof.

## 0. Sources (all fetched this session — no invented URLs)

Wrath enhance APLs (the prior lane's "rate-limited, not cited" gap is closed —
all three fetched):
- `https://raw.githubusercontent.com/wowsims/wotlk/master/ui/enhancement_shaman/apls/default_ft.apl.json` (FT-imbue default)
- `https://raw.githubusercontent.com/wowsims/wotlk/master/ui/enhancement_shaman/apls/default_wf.apl.json` (WF-imbue default)
- `https://raw.githubusercontent.com/wowsims/wotlk/master/ui/enhancement_shaman/apls/phase_3.apl.json` (phase-3 variant)
- test wiring `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/enhancement/enhancement_test.go`
  (FT default + WF + phase_3 rotations; `enhShamFTFT` shield = LightningShield,
  imbues FT-downrank/FT; `enhShamWFWF` shield = WaterShield, imbues WF/WF)

Wrath shaman spell truths:
- SS `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/stormstrike.go`
  (CD 8s, 6s w/ Gladiator-4pc; debuff 12s/4 stacks/+20% nature, +28% glyph)
- SR `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/shamanistic_rage.go`
  (30823, 15s, 1min CD, generic MCD gate mana <= 20%)
- FE `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/feral_spirit.go`
  (51533, 3min CD, 45s wolves, DPS-MCD priority over lust/drums)
- LL `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/lavalash.go`
  (60103, 6s CD, OH-only, FT-imbue x1.25 / x1.35 glyph)
- LvB `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/lavaburst.go`
  (60043, 8s CD, Elemental-only — no enhance APL role)
- Fire totems `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/fire_totems.go`
  (Searing 58704 60s; Magma 58734 20s, 10 x 2s ticks)
- FE totem `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/fire_elemental_totem.go`
  (2894, 120s duration, 10min CD / 5min glyph; cancels Magma/Searing)
- FN `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/firenova.go`
  (61657, CD 10-3glyph-2*ImpFireNova)
- Shocks `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/shocks.go`
  (shared 6s shock CD -200ms*Reverberation; FS 49233 dot 6 ticks x 3s +3 T9-2pc,
  LvB +100% crit while FS active; ES 49231)
- LB `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/lightning_bolt.go`
  (49238, base cast 2500ms)
- LS `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/lightning_shield.go`
  (49281, 10min, 3+2*StaticShock stacks, Static Shock proc; orb 49279)
- Totems/CoE `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/shaman/totems.go`
  (66842 = Call of the Elements, drops all four at once)

Wrath druid rotation + spells:
- rotation `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/druid/feral/rotation.go`
  (`doTigersFury`/`berserkNow`/`roarNow`/`clipRoar`/`doRotation`/pooling/weave/`setupRotation`)
- TF `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/druid/tigers_fury.go`
  (50213, +20 energy x KotJ rank, +80 dmg, 30s CD -3s T4)
- SR `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/druid/savage_roar.go`
  (52610, 25 energy, 9+5/CP -> 14/19/24/29/34s, +8s T8-4pc)
- Berserk `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/druid/berserk.go`
  (50334, 15s +5s glyph, 3min CD, -50% cost)
- Mangle `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/druid/mangle.go`
  (Cat 48566: 45-2*ImpMangle-Ferocity, -5 T7-2pc)

Cross-client SS-CD checks (resolves the F9 "Era 20 UNCONFIRMED" note):
- SoD `https://raw.githubusercontent.com/wowsims/sod/master/sim/shaman/stormstrike.go`
  (CD 6s)
- Era `https://raw.githubusercontent.com/wowsims/classic/master/sim/shaman/stormstrike.go`
  (CD 20s)

## 1. Shaman F9 rows (filed `desks/shaman-rotation-fix/journal.md:31`)

APL shape (all three share the spine; differences noted per row).
FT order: FE 51533 > BL 2825(tag -1) > BL 2825 > autocastOtherCooldowns >
MW5(53817)==5 -> LB 49238 > SS 17364 > FS 49233 (dot<=0) >
SS iff SS-debuff inactive > ES 49231 > CoE 66842 (water<20s) >
Magma 58734 (magma-dot<=100ms AND NOT FE 2894) > FN 61657 >
LS 49281 (iff inactive) > LL 60103.
WF adds one MW>=3 swing-fit LB entry (row S3 below). Phase_3 gates FS on
dot<=0 AND fight-remaining>=8s and swaps the SS-safety above ES.

### S1. SR line-up half — CONFIRMED, keep as-is (no gate on Wrath)

Sim: SR is a GENERIC mana MCD, not an enhance APL rule —
`shamanistic_rage.go: ShouldActivate ... CurrentManaPercent() <= 0.2`.
None of the three APL priorityLists contains 30823; SR fires through the
`autocastOtherCooldowns` entry (all three APLs, slot #4). There is no SR
line-up / trinket-stack / snapshot rule anywhere in the enhance APLs.
Our engine: rule 4 prompts on cooldown with nil threshold on WRATH
(`shaman_guide.lua:354-362`, family default `shaman_guide.lua:335-342`
feeds TBC 0.10 / ERA-SoD 0.65, Wrath stays nil) — MATCHES the APL shape.
Do NOT copy the 20% MCD gate into the guide: it is the sim's generic
mana-CD fallback, and the audit already rejected inventing a Wrath SR
threshold without sim backing (`bench/wrath_sod_2026-10-19.md:51`).
Value: nil threshold on WRATH (prompt on cooldown). Applicability: WRATH only.

### S2. ES-on-FS micro-order — CONFIRMED, keep as-is (no FS gate on ES)

Sim: micro-order emerges from priority, not a condition. FT/WF: FS
(dotRemainingTime<=0s) sits above unconditional ES; phase_3 adds
fight-remaining>=8s to FS but ES stays unconditional below it. No APL
entry gates ES on FS-active, and LvB (the FS-consumer) never appears in
any enhance APL. Our engine: FS rule 6 (`shaman_guide.lua:375-380`) above
the unconditional shock-capped ES fallback rules 14/17
(`shaman_guide.lua:424-443`) with no FS-active condition — MATCHES.
The "ES when FS active" doc note (`docs/research/rotations_wrath.md`)
is guide prose, not a sim condition. Value: no FS-active gate.
Applicability: WRATH (same shape on all three APLs).

### S3. Sub-5 hardcast — CONFIRMED PRESENT in one build, stays filed by design

Sim: `default_wf.apl.json` contains, between the MW5 entry and SS:
MW(53817)>=3 AND (300ms + LB-49238 cast time < autoTimeToNext) -> LB 49238.
`default_ft.apl.json` and `phase_3.apl.json` do NOT contain it (MW==5 only).
So the WF-imbue build hardcasts at 3-4 stacks when the cast fits the swing;
the FT builds are MW5-only. Our engine is MW5-only everywhere
(`shaman_guide.lua:363-365`), matching FT/phase_3, diverging from default_wf.
This is the same swing-fit shape as the SoD sim (`autoTimeToNext >=
cast+100ms`) and our weave model — but building it needs an LB cast-time
model at MW3-4 (base 2500ms per `lightning_bolt.go`, MW-reduced) plus
imbue-build awareness the gather does not collect. Stays filed (M1);
do NOT build on a guessed cast time.
Value: MW>=3 + 300ms + cast < autoTimeToNext (default_wf ONLY).
Applicability: WRATH, WF-imbue builds only.

### S4. Lightning Shield slot — CONFIRMED PRESENT, stays filed (cut-with-reason)

Sim: all three APLs rank LS second-to-last: `NOT auraIsActive(49281) ->
cast 49281`, above LL 60103 last. Spell truth per `lightning_shield.go`:
49281, 10min duration, 3+2*StaticShock stacks, Static Shock proc 2%/pt
(+3% T8-2pc), orb 49279 (380 + 0.267*SP). Our engine has NO LS slot
(`shaman_guide.lua:197-204` documents the deferral: shield choice needs
mana awareness). CONFIRMED gap; cut-with-reason stands: the 13-slot
contract is frozen and shield selection needs mana awareness the guide
does not model. Stays filed (M2).
Value: 49281, maintain-iff-inactive, ranked above LL. Applicability: WRATH
(FT test spec runs `Shield: LightningShield`; WF spec runs WaterShield —
shield is a spec option, not a rotation constant).

### S5. Per-client SS swipe — CONFIRMED values, cut-with-reason stands

Sim values: Wrath 8s, 6s w/ Gladiator-4pc
(`stormstrike.go: cooldownTime = Ternary(HasSetBonus(GladiatorsEarthshaker,4),6,8)`);
SoD 6s (`sod/.../stormstrike.go: Duration: time.Second * 6`);
Era 20s (`classic/.../stormstrike.go: Duration: time.Second * 20`) —
this CONFIRMS the F9 "Era 20 UNCONFIRMED" note: Era is 20s, sim-sourced.
TBC 10s (prior audit). Debuff 12s all three (wotlk `Duration: 12s`).
APL usage: SS unconditional (FT #6, WF #7) + SS-iff-debuff-missing safety
(FT #8, phase_3 #7) — every sim casts SS on cooldown; no hold.
Our engine: guide slot `swipe_duration = 10`
(`classes/shaman.lua:2544-2545`) + HUD fallback `stormstrike = 10`
(`classes/shaman.lua:3016-3023`); live client length rides while a real
cooldown runs. Fallback delta pre-first-cast: TBC exact; Wrath +2s
(+4s Glad-4pc); SoD +4s; Era -10s (swipe completes early — the worst
direction, slot looks ready while the real 20s CD still runs).
Cut-with-reason STANDS (`bench/wrath_sod_2026-10-19.md:70-74`): the
fallback only matters pre-first-cast; one code path stays correct
everywhere once the first cooldown runs. Do NOT branch the swipe reader
per client; do NOT auto-switch on Glad-4pc (no set probe exists).
Stays filed (M4) for the options/HUD pass.
Values: Era 20 / SoD 6 / TBC 10 / Wrath 8 (6 Glad-4pc). Applicability: per family.

## 2. Druid Wrath rows (filed `desks/druid-rotfix/journal.md`)

### D1. TF dynamic line — CONFIRMED, keep as-is (latency input stays filed)

Sim (`rotation.go:doTigersFury`): skip unless TF ready; `leewayTime =
max(gcdTimeToRdy, cat.latency)`; `tfEnergyThresh = 40.0 - 10.0*(leewayTime
+ Ternary(clearcast, 1s, 0))`; TF iff `energy < thresh` and NOT Berserk-active
(+ Lacerateweave delay, bearweave-only). TF spell per `tigers_fury.go`:
50213, instantEnergy 20*KotJ, +80 dmg, 30s CD (-3s T4).
Our W1 (`druid_guide.lua:422`, `:550`): `TF_ENERGY_WRATH - 10*leeway`,
leeway = max(gcd_remaining, latency or 0) + 1s on clearcast — MATCHES.
Latency is nil until its probe lands, degrading to the GCD alone
(filed follow-up, M11; `LibLatencyMonitor` exists in-tree, no druid wiring).
Value: 40-10*leeway. Applicability: WRATH only.

### D2. Berserk waitForTf phasing — CONFIRMED, keep as-is

Sim (`rotation.go`): `waitForTf = Talents.Berserk && (TigersFury.ReadyAt <=
BerserkAura.Duration) && (TigersFury.ReadyAt+1s < remain-BerserkDur)`;
`berserkNow = Berserk ready && !waitForTf && Rip active && !clearcast`
(+ Lacerateweave final-Berserk delay). Berserk per `berserk.go`: 50334,
15s (+5s glyph), 3min CD, -50% cost on builders. NO energy gate.
Our W2 (`druid_guide.lua:423`, `:793-802`): 15s TF-CD gate + Rip-active +
no-proc, old 85 cap gone — MATCHES (the 15s gate is the waitForTf
approximation; exact TF/Berserk-CD phasing needs CD inputs the gather
does not collect).
Value: no energy gate; TF-CD>=15s + Rip + no-proc. Applicability: WRATH only.

### D3. clipRoar glyph extension — CONFIRMED PRESENT, stays filed

Sim (`rotation.go:clipRoar`): early-Roar iff current Roar expires before
projected Rip end + RipLeeway, where Rip end assumes FULL Glyph-of-Shred
extensions (`maxRipDur = maxRipTicks * tickLength`); `RipLeeway = 4s`;
`MinRoarOffset` set/weave-dependent per `setupRotation`: flower/bearweave-none
34s T8-4pc else 25s; bearweave 14s T7-2pc / 27s T8-4pc / else 12s.
`BiteTime` 4s monocat/flower, 10s bearweave (same function).
Our W3: expiry-only + S3b-style cover-to-end clip over `SOD_SR_DURATION`
(no glyph extension, no set table) — base MATCHES, extension ABSENT.
Needs glyph (Shred) + set (T7-2pc/T8-4pc) + maxRipTicks inputs that do not
exist. Stays filed (M6), cut-with-reason.
Values: RipLeeway 4s; MinRoarOffset 12/14/25/27/34 by set+weave; BiteTime 4/10.
Applicability: WRATH only.

### D4. Rake DPE + glyph-extension gates — CONFIRMED PRESENT, stays filed

Sim (`rotation.go:rakeNow`): after the base UseRake/!Rake/remain>duration/
rakeCcCheck gate — (a) `RakeDpeCheck`: `calcBuilderDpe` (rakeDPC vs
shredDPC over potential ticks) must favour Rake (skips Rake on trinket
procs); (b) glyph-extension: `remainingExt == 0 ||
(maxShredsPossible > remainingExt)` where `energyForShreds` includes
TF-expected +60. `RakeDpeCheck` defaults from idol (`!= 50456`).
Our W7: plain expiry Rake — both gates ABSENT. Needs AP/DPE + proc +
energy-projection inputs the gather does not collect. Stays filed (M7),
cut-with-reason, longer term.
Values: DPE compare + maxShredsPossible>remainingExt.
Applicability: WRATH only.

### D5. FF omen-fishing — CONFIRMED PRESENT, stays filed

Sim (`rotation.go`): `ffThresh = 87.0` (15 in Berserk = `BerserkFfThresh`
forced in `setupRotation`); `ffNow = FF can cast && !clearcast && energy <
ffThresh && (!ripNow || energy < ripCost)` + end-of-fight spend math
(`numShredsWithFF > numShredsWithoutFF`); `waitForFf` blocks Mangle/Rake
casts when FF < 1s-`MaxFfDelay` away and pooled energy < ffThresh
(`MaxFfDelay = 100ms` in `setupRotation`).
Our engine: `ff_ready`/`ff_cd_remaining` gathered (name probe), NO rule
reads them — ABSENT. Needs the spend-math design + Omen-ICD input (no ICD
input exists). Stays filed (M8; same input as the Forever omenFish row).
Values: ffThresh 87 / 15 Berserk; MaxFfDelay 100ms. Applicability: WRATH only.

### D6. Pooling cast-gates — CONFIRMED PRESENT, display-only in ours, stays filed

Sim (`rotation.go`): `pendingPool` over Rip/Rake/Mangle/Roar expiries with
Berserk-halved costs (`berserkExpectedAt`); `floatingEnergy` = pooled need;
`excessE = cur - floating` gates Shred/Mangle casts; cap-Shred at
`energy > 100-10*latencySecs`; `furorCap = min(20*Furor,85)`,
`weaveEnergy = furorCap-30-20*latencySecs` (Furor 4/5+ adjustments);
end-of-fight dump math; bear/flower/snek/powerbear branches.
Our W9: pooling shows on the energy tick bar only; the builder never waits.
Needs live builder costs + tick-phase upkeep (filed: `druid_energy`
helpers ready, no rule reads). Stays filed (M9).
Values: pendingPool->floatingEnergy->excessE gating; furorCap min(20*Furor,85).
Applicability: WRATH only.

### D7. Wrath Mangle cost — CONFIRMED value, keep-as-is (probe filed)

Sim (`mangle.go`): Cat 48566, cost `45.0 - 2*ImpMangle - Ferocity`
(-5 T7-2pc Thunderheart). Bear 48564 separate (20-Ferocity rage, 6s-0.5*ImpMangle CD).
Our engine: TBC costs frozen (Mangle 40 / Shred 42,
`druid_guide.lua:388-396`); Wrath Mangle cost unmodelled — but the guide
never gates Mangle on energy (absent-only rule W6), so no wrong hold
results. GAP LOW, keep-as-is; live-cost probe follow-up stands (M10).
Value: 45-2*ImpMangle-Ferocity (-5 T7-2pc). Applicability: WRATH only.

### D8. Bite minima + execute — CONFIRMED, keep as-is

Sim: `canBite = Rip>=BiteTime && SR>=BiteTime`; `biteNow =
(biteBeforeRip || biteAtEnd) && !clearcast && energy<67`
(`<= BerserkBiteThresh = 25` in Berserk); `endThresh = 10s`;
`MinCombosForBite = 5`. Our W8 (`druid_guide.lua:426-432`, `:876`):
minima 4s each + execute last-10s — MATCHES (old 8s guard corrected by
the rotfix lane to sim 4s). Values: BiteTime 4 (10 bearweave);
energy<67 (<=25 Berserk); execute 10s. Applicability: WRATH only.

### D9. SR durations + TF/Berserk ids — CONFIRMED, keep as-is

Sim (`savage_roar.go`): 52610, 25 energy, durations 9+5/CP = 14/19/24/29/34s
(+8s T8-4pc); multiplier x1.3 (+0.03 glyph). TF 50213 / Berserk 50334
per §D1/D2 sources. Our `SOD_SR_DURATION = {14,19,24,29,34}`
(`druid_guide.lua:458`) reused for the Wrath 5CP 34s; TF/Berserk ids
(`classes/druid.lua:433-436`) + SR fallback (`classes/druid.lua:498`) —
MATCHES. Applicability: WRATH (durations shared with SoD).

## 3. CONFIRMED table (value + sim source URL + client applicability)

| # | Value | Sim source URL | Applies to | Our side |
|---|---|---|---|---|
| S1 | SR: nil threshold on Wrath (prompt on CD; 20% is generic-MCD only, not an APL rule) | `.../sim/shaman/shamanistic_rage.go` (ShouldActivate<=0.2) + all three APLs (no 30823 entry) | WRATH | `shaman_guide.lua:335-362` |
| S2 | ES: no FS-active gate (order from priority only) | all three APLs (FS above unconditional ES) | WRATH | `shaman_guide.lua:375-380`, `:424-443` |
| S3 | WF-build only: MW>=3 + 300ms+cast<autoTimeToNext -> LB 49238 (FT builds MW5-only) | `.../ui/enhancement_shaman/apls/default_wf.apl.json` | WRATH (WF imbue) | filed M1; engine `shaman_guide.lua:363-365` stays MW5 |
| S4 | LS 49281 maintain-iff-inactive, above LL; 10min, 3+2*StaticShock stacks | all three APLs (LS entry) + `.../sim/shaman/lightning_shield.go` | WRATH | filed M2; no slot (`shaman_guide.lua:197-204`) |
| S5 | SS CD: Era 20 / SoD 6 / TBC 10 / Wrath 8 (6 Glad-4pc); debuff 12s | `.../sim/shaman/stormstrike.go` (cooldownTime Ternary 6/8) + `.../sod/.../stormstrike.go` (6s) + `.../classic/.../stormstrike.go` (20s) | per family | `classes/shaman.lua:2544-2545`, `:3016-3023` (fallback 10 + ride) |
| S6 | FE 51533 3min/45s, APL #1; LL 60103 6s OH-only FT-x1.25 (x1.35 glyph), APL last; Magma 58734 20s gated magma<=100ms AND NOT FE 2894; FN 61657 CD 10-3glyph-2*Imp; FS 49233 shock-shared 6s, 6x3s dot; LvB 60043 Elemental-only | `.../sim/shaman/feral_spirit.go` + `lavalash.go` + `fire_totems.go` + `fire_elemental_totem.go` + `firenova.go` + `shocks.go` + `lavaburst.go` + all three APLs | WRATH | rules 2-3/6/10-12/14-17 keep |
| D1 | TF line 40-10*leeway, leeway=max(gcd,latency)+1s-clearcast; TF 50213 30s(-3s T4) | `.../sim/druid/feral/rotation.go` (doTigersFury) + `.../sim/druid/tigers_fury.go` | WRATH | `druid_guide.lua:422`, `:550` |
| D2 | Berserk: no energy gate; waitForTf phasing; 50334 15s(+5s glyph)/3min/-50% | `.../sim/druid/feral/rotation.go` (berserkNow) + `.../sim/druid/berserk.go` | WRATH | `druid_guide.lua:423`, `:793-802` |
| D3 | RipLeeway 4s; MinRoarOffset 12/14/25/27/34 by set+weave; BiteTime 4 (10 bearweave) | `.../sim/druid/feral/rotation.go` (clipRoar + setupRotation) | WRATH | filed M6; W3 expiry-only keeps base |
| D4 | RakeDpeCheck + remainingExt/maxShredsPossible extension gate | `.../sim/druid/feral/rotation.go` (rakeNow/calcBuilderDpe) | WRATH | filed M7 |
| D5 | ffThresh 87 / 15 Berserk; MaxFfDelay 100ms; waitForFf + end-of-fight spend math | `.../sim/druid/feral/rotation.go` (ffNow/waitForFf) | WRATH | filed M8 |
| D6 | pendingPool->floatingEnergy->excessE cast-gating; furorCap min(20*Furor,85) | `.../sim/druid/feral/rotation.go` (pooling block) | WRATH | filed M9; bar display only |
| D7 | Mangle Cat 48566: 45-2*ImpMangle-Ferocity (-5 T7-2pc) | `.../sim/druid/mangle.go` | WRATH | filed M10; absent-only rule unaffected |
| D8 | canBite Rip/SR>=BiteTime; bite energy<67 (<=25 Berserk); execute 10s; 5CP | `.../sim/druid/feral/rotation.go` (canBite/doRotation/setupRotation) | WRATH | `druid_guide.lua:426-432` keep |
| D9 | SR 52610 25en 14/19/24/29/34s (+8s T8-4pc) | `.../sim/druid/savage_roar.go` | WRATH (+SoD shared) | `druid_guide.lua:458` keep |

Full-URL prefix for the table's `...`: `https://raw.githubusercontent.com/wowsims/wotlk/master`
(except S5 SoD/Classic rows, prefixed `https://raw.githubusercontent.com/wowsims/sod|classic/master`).

## 4. Still-missing list (filed, with what's needed — validation owner: orchestrator)

- M1 (shaman S3): sub-5 swing-fit hardcast (WF-build MW>=3 + 300ms+cast<swing).
  Needs: LB cast-time model at MW3-4 + imbue-build awareness + swing-fit input.
  Engine MW5-only stays until then.
- M2 (shaman S4): LS maintain (49281 iff inactive, above LL).
  Needs: 14th guide slot (13-slot contract frozen) + shield/mana awareness.
- M3 (shaman, UNFILED observation — orchestrator triage, not an F9 row):
  water-totem Call-of-Elements refresh (all three APLs: CoE 66842 iff water
  remaining <20s; `totems.go` confirms 66842 = Call of the Elements).
  No verdict; needs totem-timer inputs + slot design if ever scoped.
- M4 (shaman S5): per-client SS swipe fallback (SoD 6 / Wrath 8+6set / Era 20).
  Cut-with-reason: live client ride covers after the first cast. Revival needs
  a Glad-4pc set probe (does not exist) + options/HUD pass.
- M5 (shaman cross-ref, filed elsewhere): FS refresh <=3s vs expiry-only
  (all sims re-apply on expiry; phase_3 adds fight>=8s). Owned by the
  options lane (explicit-0 already honoured by the engine).
- M6 (druid D3): clipRoar glyph extension. Needs: Glyph-of-Shred +
  T7-2pc/T8-4pc set inputs + maxRipTicks tracking.
- M7 (druid D4): Rake DPE + extension gates. Needs: AP/DPE + proc inputs +
  energy-projection math (longer term; do not build on guessed AP).
- M8 (druid D5): FF omen-fishing rule. Inputs `ff_ready`/`ff_cd_remaining`
  gathered (name probe); needs: spend-math design + Omen-ICD input
  (none exists). Same input as the Forever omenFish row.
- M9 (druid D6): pooling cast-gates. Needs: live Shred/Rip/Rake costs
  (GetSpellPowerCost probe, filed) + guide-only tick upkeep.
- M10 (druid D7): Wrath Mangle live cost. Needs: rank-table/cost probe
  (filed); engine never withholds Mangle meanwhile.
- M11 (druid D1): W1 latency term. Needs: honest latency source
  (`LibLatencyMonitor` exists in-tree, no druid wiring — filed).
- M12 (druid, by design): bearweave/flowerweave/snekweave/powerbear.
  Documented scope cut; needs bear-timer/rage inputs (~5-7% per doc).

## 5. Validation

Owner: orchestrator. Method: re-fetch the §0 raw URLs, re-check each
our-side file:line in §1-§2, confirm this file is new (no bench overwrite:
`bench/wrath_sod_2026-10-19.md` untouched, still the variant-design record;
this file is the sim-sourced value ledger), `bash tests/run.sh` on reconcile
(no addon file touched by this lane).
UNCONFIRMED ledger (in-client or unfetched): Glad-4pc 6s SS ownership;
T7-2pc/T8-2pc/T8-4pc set ownership + Glyph-of-Shred presence; Wrath Mangle
live cost via GetSpellPowerCost; Omen ICD length; CoE 66842 behaviour on
3.80.2; all sim numbers are not client proof (guides are 3.4.3, target is
Titanforge 3.80.2).
