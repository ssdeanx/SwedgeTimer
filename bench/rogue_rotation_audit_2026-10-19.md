# rogue_rotation_audit_2026-10-19 — Rogue guide vs wowsims sims, per client

Desk: rogue-rotation-audit. READ-ONLY: no addon file touched. Single new file
per brief. Date: 2026-10-19.

Scope read: `classes/rogue.lua`, `rogue_guide.lua`, `tests/rogue_state.lua`,
`tests/rogue_guide_state.lua`. Compared against the wowsims sim/APL sources
below (all pages/files actually fetched in-session; no ids invented — every
spell id quoted is verbatim from the fetched sim file).

Sim sources (brief URL set + one supplement):
- ERA — `wowsims/classic`: `ui/rogue/apls/combat_sinister_strike.apl.json`,
  `combat_sinister_strike_sweaty.apl.json`,
  `combat_sinister_strike_iea.apl.json`, `sim/rogue/slice_and_dice.go`,
  `sim/rogue/rupture.go`, `sim/rogue/eviscerate.go`
  (`https://github.com/wowsims/classic/blob/master/...`)
- SoD (ERA family) — `wowsims/sod`: `ui/rogue/apls/P5_Saber.apl.json`,
  `ui/rogue/apls/mutilate.apl.json`, `sim/rogue/envenom.go`
  (`https://github.com/wowsims/sod/blob/master/...`)
- TBC — `wowsims/tbc-new`: `ui/specs/rogue/dps/apls/swords.apl.json`,
  `sim/rogue/slice_and_dice.go`, `sim/rogue/rupture.go`,
  `sim/rogue/envenom.go`, `sim/rogue/shiv.go`
  (`https://github.com/wowsims/tbc-new/blob/master/...`)
- FOREVER — `wowsims/forever`: `ui/specs/rogue/dps/apls/default.apl.json`,
  `sim/rogue/rogue.go`
  (`https://github.com/wowsims/forever/blob/master/...`)
- WRATH — `wowsims/wotlk` (SUPPLEMENT, not in the brief URL set; needed for
  the WRATH family): `ui/rogue/apls/mutilate.apl.json`,
  `ui/rogue/apls/combat.apl.json`, `sim/rogue/envenom.go`,
  `sim/rogue/rupture.go`, `sim/rogue/slice_and_dice.go`
  (`https://github.com/wowsims/wotlk/blob/master/...`)
- RETAIL — no sim repo in the brief URL set (`wowsims.github.io` is the static
  Pages host for sod/classic builds, not sim code; the retail sim lives at
  wowsims.com under an unlisted repo; org API was rate-limited in-session).
  RETAIL rows below are guide-sourced (bench/rogue_research §1.6, Icy Veins
  12.1.5) and the sim-APL side is marked UNCONFIRMED. Not re-derived.

Our-side anchors: `rogue_guide.lua` (pure engine), `classes/rogue.lua`
(provider). Rule numbers below are the FROZEN SPEC header
(`rogue_guide.lua:105-133`).

Verdict vocabulary: MATCH (agree) / GAP (sim does something we don't, with
impact) / CONFLICT (we advise the opposite of the sim). Impact scale:
HIGH (core finisher/upkeep wrong or missing) / MEDIUM (visible DPS or
wrong-window advice) / LOW (consumable/CD polish, tunable).

## 0. Cross-client findings (apply everywhere noted)

### F0. No Slice-and-Dice prompt anywhere in the guide — GAP, HIGH
Sim-side: EVERY sim APL maintains SnD. Classic: 1+CP SnD when fight>=6s,
5CP refresh when SnD<3s and fight>9s (`combat_sinister_strike.apl.json`);
TBC: SnD with 10s minimum + EA/SnD-safe gates (`swords.apl.json`,
valueVariables Minimum SnD Time 10s); Forever: SnD at 1+CP, clip<=0s
(`default.apl.json`: "At or Below SnD Clipping Threshold" = 0s);
WotLK: SnD refresh at <=1s, incl. builder+SnD strict sequence
(`combat.apl.json`, `mutilate.apl.json`); SoD: SnD at 4+CP remains<=1s
(`P5_Saber.apl.json`) / 4+CP (`mutilate.apl.json`). Sim durations are
exact per-CP tables: TBC `[0,9,12,15,18,21]s`
(`tbc-new/.../slice_and_dice.go`); classic same ×ImpSnD, level-scaled haste
(`classic/.../slice_and_dice.go`); WotLK same +ImpSnD/glyph
(`wotlk/.../slice_and_dice.go`).
Our-side: the guide slot table has NO SnD action
(`classes/rogue.lua:594-604` — builder/rupture/eviscerate/envenom/expose/
shiv/tea only); gather reads no SnD remains (`classes/rogue.lua:662-778`).
SnD is HUD-only. The single most-used finisher in every sim APL has no
guide prompt on any client. GAP, HIGH, all clients.

### F1. No builder distinction — GAP, MEDIUM
Sim-side: separate APLs/builders per weapon path — classic ships distinct
`combat_sinister_strike` AND `combat_backstab` APLs (API listing,
`classic/ui/rogue/apls/`); TBC APL branches SS (26862) / Backstab (26863) /
Mutilate (34413) / Hemo (26864) on known-spell + variable
gates (`swords.apl.json`); SoD builders are Saber Slash (424785) /
Mutilate (399956) with rune/CP/stack gates (`P5_Saber`/`mutilate.apl.json`);
Forever builders branch Backstab (11281) / Mutilate (1241584) /
Hemo (16511) / SS (11294) (`default.apl.json`).
**CORRECTED 2026-10-20 (desk `corpus-corrections`):** the TBC branch used to
read "SS (26864) … Hemo-Ghostly fallback (26862)" — the two are **swapped**.
26862 = **Sinister Strike**, 26864 = **Hemorrhage**. Evidence:
`bench/filed_closure_sweep_2026-10-19.md` §9-N1 (the client's own wowhead
redirect slugs: `/tbc/spell=26862` → `/sinister-strike`,
`/tbc/spell=26864` → `/hemorrhage`) and the rogue APL build lane's
sim-sourced TBC table — `hemorrhage` 26864 / `backstab` 26863 / `mutilate`
34413 (`bench/rogue_apl_utility_build_2026-10-20.md` §1.1 rows 34-36).
Our-side: one generic `builder` slot (`rogue_guide.lua:41`, provider
`classes/rogue.lua:599` resolves only "Sinister Strike" as
`GUIDE_SPELL_NAMES.builder`, `classes/rogue.lua:150-158`). Dagger/Backstab
positioning and Mutilate/Saber 2-CP builder paths are invisible to the
engine. GAP, MEDIUM, all clients.

### F2. Energy-tick model matches classic sim, sims elsewhere use static lines
Sim-side: classic APL gates AR on `timeToEnergyTick < 1` (energy<59) and
Tea on `timeToEnergyTick > 1` (energy<=29) — discrete-tick modeling
(`combat_sinister_strike` + `sweaty` APLs). TBC/Forever/WotLK/SoD APLs use
static energy thresholds only (71 / 75-cap-danger / 85-cap-exception /
10-40), no tick reference.
Our-side: proc-aware 2s predictor, TICK_PERIOD 2.0 / TICK_ENERGY 20
(`classes/rogue.lua:72-73`), Combat Potency 15 + Relentless 25 never
re-anchor (`classes/rogue.lua:78-82`, rogue_guide-research CONFIRMED).
MATCH on classic-line tick mechanics. Residual (documented, no action):
during Adrenaline Rush ticks grant 40, which the predictor reads as an
unrecognised grant and hides on (H4, `classes/rogue.lua:431-434`) — safe
(no wrong advice) but the spark goes dark exactly when tick timing
matters most. GAP, LOW (spark availability under AR).

### F3. No cooldown/utility prompts (AR/BF/Cold Blood/Tricks) — GAP, MEDIUM
Sim-side: TBC prepull AR (-1s) + AR at energy<=40, BF with SnD+EA active,
Cold Blood (14177) with SnD (`swords.apl.json`); classic AR at
energy<59+tick<1, autocast-CDs behind SnD; Forever AR at energy<=50 w/ SnD,
BF when SnD not imminent, Cold Blood (14177) at 5CP, **Venom (1310703)** at
3+CP (`default.apl.json`); WotLK Tricks (57934) at energy<=50, Killing
Spree (51690) at energy<=50, AR phase-gated at energy<=50, potion with AR
(`combat.apl.json`).
**CORRECTED 2026-10-20 (desk `corpus-corrections`):** this row used to say
"**Riposte** (1310703) at 3+CP" — **1310703 is Venom** on the Forever client
(`wowsims/forever sim/rogue/spell_data_auto_gen.go`: `Venom:
spelldata.Ranked(1310703)`); the Forever APL's i=19 row is the Venom row.
Evidence: `bench/rogue_apl_utility_build_2026-10-20.md` §3.8;
`bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **R7**.
Our-side: AR/BF are HUD aura/cooldown states only
(`classes/rogue.lua:871-907`); the guide never prompts a cooldown. The
stacked-glow predicate exists (`rogue_guide.lua:470-484`) but no
go/no-go advice. GAP, MEDIUM (AR/BF stacking is the Era/TBC burst play).

## 1. ERA (`_Vanilla`, wowsims/classic)

### E-M1. 5CP finisher line — MATCH
Sim casts finishers at 5CP (SnD refresh, Evisc 31016)
(`combat_sinister_strike.apl.json`) vs FINISHER_MIN_CP_DEFAULT 5
(`rogue_guide.lua:181,403`). MATCH.

### E-C1. Rupture-first planned finisher vs sim Evisc-only — CONFLICT, HIGH
Sim-side: neither `combat_sinister_strike` nor `combat_sinister_strike_iea`
APL casts Rupture at all — the rotation is SnD + Evisc (31016 at 5CP when
SnD active OR energy>=79 OR fight<6s). Rupture is absent from the Era
combat sim rotation.
Our-side: rule 5 routes 5CP + healthy Rupture through
`finisher_for_ttd`, which prompts "rupture" whenever TTD>8 and Rupture is
missing/inside-refresh (`rogue_guide.lua:289-322,567-575`). On Era the
engine will routinely prompt Rupture where the sim plays Evisc-only.
CONFLICT, HIGH (Era combat). The TBC-sourced Rupture-first rule
(rogue_research §1.3) does not hold on the Era sim. (SoD APLs likewise
omit Rupture — see S-C1.)

### E-G1. Sweaty swing-gate is wider than our window and has an energy override — GAP, MEDIUM
Sim-side: `combat_sinister_strike_sweaty.apl.json` gates SS (11294) on
`autoTimeToNext(MH) > swingTime - 0.5` (i.e. ~0.5s post-swing window) OR
fight<6s OR energy>=79. No weapon-type check in the APL.
Our-side: 0.1–0.2s post-MH window (`classes/rogue.lua:88-90`), ERA-only
(`classes/rogue.lua:90`), AND sword mainhand required
(`classes/rogue.lua:1107-1117`). Ours is 2.5–5× narrower, sword-only, and
lacks the cap override (sim fires SS regardless of swing phase at
energy>=79). GAP, MEDIUM. Direction for the options/recorded pass: widen
toward 0.5s needs in-client proof (Sno simmed 0.1–0.2s per rogue_deep §1);
the energy>=79 override is sim-sourced and portable.

### E-G2. SnD at 1CP early — GAP, HIGH (instance of F0)
Sim: 1+CP SnD when fight>=6s and SnD inactive. We have no SnD action.

### E-G3. Tea line 29–30 vs default 40 — GAP, LOW
Sim: Tea (item 7676) at energy<=29 with tick>1, CP<5, no AR
(`sweaty` APL); base APL has no Tea (AR-only line). Our
TEA_ENERGY_MAX_DEFAULT 40 (`rogue_guide.lua:184`) over-fires by ~10 energy
on Era. Tunable (`tea_energy_max`), default wrong for Era. GAP, LOW.

### E-G4. IEA variant: EA<=3s at 5CP — MATCHES our default, TBC does not
Sim-side: `combat_sinister_strike_iea.apl.json` casts EA (11198) at 5CP
when remains<=3s (fight>=3s), and gates the 5CP SnD refresh on EA>15s.
Our EA_REFRESH_DEFAULT 3 (`rogue_guide.lua:182`) MATCHES the Era IEA sim
exactly. Keep for ERA; the same default mismatches TBC (see T-G2). No
action on Era.

## 2. TBC (`_TBC`, wowsims/tbc-new)

### T-M1. Pooling exists; threshold differs — MATCH with GAP, MEDIUM
Sim: single "At or Above Pool Threshold" = energy>=71 gates all builders
(`swords.apl.json` valueVariables). Ours: pre 65 / post 85 bands
(`rogue_guide.lua:149-154`, TBC CONFIRMED per research). Concept MATCH;
numbers GAP: sim pools 6 energy later (71 vs 65) and has NO post-tick 85
line — at 80 energy with a tick coming the sim still spends (71 rule)
while we pool-then-spend. GAP, MEDIUM (direction: sim-validated 71 for
TBC; 65/85 came from guide text, rogue_research §1.3).

### T-M2. Rupture > Evisc ordering — MATCH
Sim: Rupture (26867) when dot missing + EA/SnD-safe at 3–5CP (ImpEA path
3+CP, else 5CP); Evisc (26865) only at 5CP with fight<=5s (or Shiv-build
filler). Ours: rule 5 Rupture-first on living targets, rule 4 Evisc dump
on dying targets (`rogue_guide.lua:550-575`). Ordering MATCH. Windows
differ (see T-C1).

### T-C1. Dump line: any-CP <=8s vs 5CP-only <=5s — CONFLICT, MEDIUM
Sim: the only sub-5CP Evisc path is the Shiv-build filler; execute Evisc
is 5CP with remaining<=5s. Our rule 4 dumps Evisc at ANY CP>=1 when
ttd<=min_ttd (8s) (`rogue_guide.lua:503-504,564-566`). On a 6–8s target
with 1–4CP we prompt Evisc where the sim builds toward a 5CP finisher.
CONFLICT, MEDIUM (Era any-CP rule, rogue_research §1.1, leaks into the
shared rule — TBC sim wants 5CP/5s).

### T-G1. No SnD prompt — GAP, HIGH (instance of F0)
Sim maintains SnD behind a 10s minimum + EA/SnD-safe gates, incl. the
"Cast Expose or Pool" wait_until group (pool until EA-imminent or
pool-threshold). We have neither SnD nor pool-for-EA. GAP, HIGH.

### T-G2. EA windows 6s/15s vs default 3s — GAP, MEDIUM
Sim: "EA Fall Imminent" = EA remains<=6s; "EA Above Minimum" = remains>=15s
(non-Shiv) / >=4s (Shiv); Minimum EA Time 15s (`swords.apl.json`).
Ours: EA_REFRESH_DEFAULT 3 (`rogue_guide.lua:182`, `ea_verdict`
`rogue_guide.lua:434-451`). Our default matches the Era IEA sim (E-G4),
not TBC: on TBC we alert ~3s late vs the sim's 6s imminent line and have
no 15s-minimum concept (sim withholds EA duty juggling inside 15s; we
prompt at 3s only). GAP, MEDIUM. Per-client EA windows needed (ERA 3 /
TBC 6+15 / FOREVER 16 — see V-G2).

### T-G3. Rupture early-refresh at 4s vs sim recast-when-missing — GAP, LOW
Sim: Rupture cast condition is `not dotIsActive` (plus EA/SnD-safe + CP
gates) — no early refresh; Rupture is recast after falloff. Ours:
RUPTURE_REFRESH_DEFAULT 4 prompts refresh inside 4s
(`rogue_guide.lua:179,289-322`). We over-refresh vs the sim by up to one
tick. GAP, LOW.

### T-G4. Shiv gating: Mutilate-unknown + EA context vs unconditional — GAP, LOW
Sim: Shiv (5938) only when Mutilate (34413) NOT known, CP<5, (EA-fall-
imminent OR Spam-Shiv=false-path), AND (Deadly dot<1s OR stacks<5, or
Spam Shiv) — i.e. combat-spec Deadly stacking inside EA windows; Shiv
cost scales with OH speed (`shiv.go`: `getShivCostModifier` = 10×OH
swing speed). Ours: rule 2 fires on any family whenever shiv_ready and
Deadly<=window (`rogue_guide.lua:554-560`), with no Mutilate-known or
EA-context check. Over-prompts for Mutilate builds and outside EA
windows. GAP, LOW (TBC).

### T-M3. Envenom ~never in combat APL — MATCH (dying_only compatible)
Sim: no Envenom (32645) cast in `swords.apl.json` at all; the sim models
Envenom as consume-stacks-for-AP (base 180×consumed + 0.03×CP×AP,
`envenom.go`) but never presses it mid-fight. Ours: TBC dying_only
(5CP + stacks + ttd<=8, `rogue_guide.lua:156-172,339-362`) — fires only
on dying targets, ~never mid-fight. Behaviour MATCH.

### T-G5. Tea line 30 vs 40; AR<=40 — GAP, LOW
Sim: Tea (item 7676) at energy<=30; AR (13750) prepull −1s and at
energy<=40 (`swords.apl.json`); Blade Flurry (13877) with SnD+EA active.
Ours: tea default 40 (over-fires 10), no AR/BF prompt (F3). GAP, LOW.

## 3. SoD, ERA family (`_Vanilla` map, wowsims/sod)

Note: our ERA family carries the TBC values (POOL_BANDS ERA = 65/85,
`rogue_guide.lua:149-154`; ENVENOM ERA = dying_only,
`rogue_guide.lua:156-172`) NEEDS-IN-CLIENT per the header. The SoD sim
upgrades several of those to conflicts.

### S-C1. Envenom-withhold + Rupture-first vs sim Envenom-primary, no Rupture — CONFLICT, HIGH
Sim-side: NEITHER `P5_Saber.apl.json` NOR `mutilate.apl.json` casts
Rupture; Envenom (rune 399963) is the primary dump — mutilate APL:
4+CP → Envenom, 2+CP → Envenom when fight<=3s, Vanish (1856) at 5CP when
Envenom-buff (425096) absent, strict Vanish→Envenom sequence at 5CP;
Saber APL: 5CP → Envenom, 3+CP when fight<=4s, 4+CP with energy>=70.
Sim Envenom requires poison stacks (Deadly/Occult active,
`sod/.../envenom.go` ExtraCastCondition) and scales per consumed dose.
Our-side: ERA dying_only withholds Envenom unless ttd<=8
(`rogue_guide.lua:339-362`), and rule 5 prompts Rupture as the planned
finisher. On SoD we would prompt Rupture (which the sim never casts) and
withhold Envenom (which the sim casts as its main dump) — exactly
backwards. CONFLICT, HIGH for SoD. Upgrades the recorded deferral
("ERA dying_only under-prompts SoD", `rogue_guide.lua:160-161`) to a
sim-evidenced conflict. SoD needs its own Envenom mode (4CP+stacks
primary) if the family is ever served, or an explicit SoD-unsupported
mark.

### S-G1. 4CP lines vs 5CP default — GAP, MEDIUM
Sim: SnD at 4+CP (both APLs), Envenom from 4CP, Poisoned Knife (425012)
at 4+ Deadly stacks with CP<5 and energy<=80. Ours: FINISHER_MIN_CP 5
(`rogue_guide.lua:181`), Envenom min_cp 5 (`rogue_guide.lua:167-168`).
GAP, MEDIUM (SoD).

### S-G2. SoD-specific actions unmodeled — GAP, MEDIUM
Sim: Poisoned Knife at 5 Deadly stacks (CP<5, energy<=80), Saber Slash
builder gating (CP<4 with stack/clock conditions), Vanish+Envenom strict
sequence, Cut-to-the-Chase rune (Envenom refreshes SnD —
`sod/.../envenom.go` `cutToTheChase` path; no SnD hard-cast needed while
it rides). Our engine has no Poisoned Knife / Vanish-sequence / CttC
concepts. GAP, MEDIUM (SoD).

### S-M1. Tea exists with fight-end exception — MATCH (partial)
Sim: Tea (item 7676) at energy<=10, or <=40 when fight<=15s
(`P5_Saber.apl.json`). Our default 40 matches the fight-end case and
over-fires otherwise. Partial MATCH; GAP, LOW outside fight-end.

## 4. FOREVER (`_Mainline` map, wowsims/forever)

### V-M1. Envenom-never — MATCH
Sim: `default.apl.json` contains no Envenom cast; the dump is Evisc
(11300). Ours: FOREVER mode never (`rogue_guide.lua:170,334-336`).
MATCH.

### V-M2. 5CP cap — MATCH
Sim: MaxComboPoints 5 (`forever/.../rogue.go` NewRogue EnableEnergyBar).
Ours: finisher line 5. MATCH.

### V-G1. No SnD prompt — GAP, HIGH (instance of F0)
Sim: SnD (6774) at 1+CP when clipping (<=0s); builders explicitly gated
on NOT SnD-fall-imminent (SnD<=2s blocks SS/Backstab/Mutilate/Hemo
unless energy-capped or EA-low or Eureka state). SnD is the highest-
frequency finisher in the APL. We have no SnD action and no SnD-aware
builder pausing. GAP, HIGH.

### V-G2. EA window 16s vs default 3s — GAP, MEDIUM
Sim: "Expose - Low Duration" = EA (11198) missing or remains<=16s; cast
at 5CP; "Expose - Prevent Other Finishers" lockout holds Rupture/Evisc/
Cold Blood while EA-low (`default.apl.json`). Ours: ea_refresh 3
(`rogue_guide.lua:182`) — alerts ~13s late on Forever, and has no
finisher lockout (though rule order puts expose first when due,
`rogue_guide.lua:554-556`). GAP, MEDIUM.

### V-G3. 3CP Rupture/Evisc vs 5CP default — GAP, MEDIUM
Sim: Rupture (11275) at 3+CP when no dot (with bleed/buff gates, not
fight-end, not EA-locked); Evisc (11300) from 3CP (4CP+Mutilate-known
variant, 4+CP with SnD<=6s, 3+CP fight-end at <=6s). Ours waits for 5CP
for every planned finisher (`rogue_guide.lua:403,567`). Under-spends
CP on Forever. GAP, MEDIUM.

### V-G4. Tea 15 (25 Eureka) vs 40 — GAP, LOW
Sim: Tea (item 7676) at energy<=15, or <=25 with Eureka (1259812) active
(`default.apl.json`). Ours 40 over-fires by 15–25. GAP, LOW.
**CORRECTED 2026-10-20 (desk `corpus-corrections`):** the id's **name** is now
settled — 1259812 = **"Gnome Eureka"** (the Forever rogue APL's own variable
"Gnome Eureka - Should Cast"; `bench/rogue_apl_utility_build_2026-10-20.md`
§3.7). The **client** proof of the id is still owed, so the gap stands.

### V-G5. AR<=50/BF/Cold Blood/Venom unprompted; Shiv absent from sim — GAP, LOW-MEDIUM
Sim: AR (13750) at energy<=50 w/ SnD (+Blood Fury 20572 sequencing),
BF (13877) when SnD not imminent, Cold Blood (14177) at 5CP gated off
EA-lockout/AR-buff, **Venom (1310703)** at 3+CP when aura inactive; NO Shiv
cast in the default APL. Ours: no AR/BF/CB/Venom prompts (F3); Shiv
rule 2 WOULD fire on Deadly falloff where the sim never Shivs —
over-prompt risk on Forever. GAP, LOW-MEDIUM (Shiv side is the sharper
edge: consider family-gating Shiv to TBC-combat, see T-G4).
**CORRECTED 2026-10-20 (desk `corpus-corrections`):** this bullet used to say
"**Riposte** (1310703)" — the id is **Venom** on the Forever client (§0.0
**R7** of `bench/rotation_gap_vs_apl_2026-10-20.md`; evidence
`bench/rogue_apl_utility_build_2026-10-20.md` §3.8).

### V-G6. Cap-danger line 75 vs band.post 85 — GAP, LOW
Sim: "In Danger of Energy Capping" = energy>=75 pauses builders for
SnD/EA/CP reasons (`default.apl.json`). Ours: band.post 85
(`rogue_guide.lua:154`, FOREVER carried). 10-energy late on Forever.
GAP, LOW.

## 5. WRATH (`_Wrath`, wowsims/wotlk — supplement, not in brief set)

### W-M1. Envenom let_expire + 85-energy cap exception — MATCH (strong)
Sim: `mutilate.apl.json` casts Envenom (57993) at 4+CP when buff absent
OR energy>=85. Ours: WRATH let_expire, min_cp 4, min_stacks 5, buff
withholds unless energy>=band.post (`rogue_guide.lua:169,363-392`);
band.post is 85 (`rogue_guide.lua:153`). CP line, stack line, buff line,
AND cap-exception value all agree. STRONG MATCH. (Sim buff: +15%
Deadly chance / +0.75 Instant PPM, duration 1+CP s, `envenom.go` —
mechanically consistent with "let it expire".)

### W-M2. 1CP Rupture = 8s — MATCH; higher-CP durations — GAP, MEDIUM
Sim: RuptureTicks = 3+CP (+2 Glyph of Rupture), 2s ticks → 1CP 8s …
5CP 16s (20s glyphed) (`rupture.go`: `RuptureDamage`/`RuptureTicks`/
`RuptureDuration`). Ours: RUPTURE_MIN_TTD_DEFAULT 8
(`rogue_guide.lua:180`) = exactly the 1CP row. MATCH at 1CP; GAP above:
at 5CP Rupture pays on targets living up to 16s, but our flat min_ttd 8
routes 9–16s-TTD targets to Evisc. Per-CP TTD table needed. GAP, MEDIUM.

### W-G1. No SnD (<=1s) / HfB (<=1s) upkeep, no CttC — GAP, HIGH
Sim: SnD refresh at <=1s (or builder+SnD strict sequence), Hunger for
Blood (51662) at <=1s, Vanish (26889) mid-fight when Overkill (58426)
absent, prepull Overkill + potion (`mutilate.apl.json`); combat keeps
SnD>rupture-math with 4s/2s/1s SnD gates and Rupture recast when missing
at 5CP (4CP variants) (`combat.apl.json`). Cut to the Chase makes sin
SnD self-sustaining via Envenom (no hard refresh while riding). Our
engine: no SnD action (F0), no HfB, no Vanish/Overkill, no CttC — and any
future SnD prompt that ignores CttC will over-refresh on sin. GAP, HIGH
(HfB/SnD are mandatory sin upkeep).

### W-G2. Combat Evisc at 4CP vs min_cp 5 — GAP, LOW-MEDIUM
Sim combat: Evisc (48668) at 4+CP when fight<=4s, or SnD>=4s & AR>=4s, or
Rupture>=10s (`combat.apl.json`). Ours: planned finishers need 5CP
(`rogue_guide.lua:403,567`); 4CP falls to Tea/pool. GAP, LOW-MEDIUM
(WotLK combat; the 5CP line is correct for TBC/classic).

## 6. RETAIL (`_Mainline` map) — sim side UNCONFIRMED this lane

No retail sim repo in the brief URL set (see header). Guide-sourced
posture retained from bench/rogue_research §1.6 (Icy Veins Outlaw 12.1.5
+ Assassination 12.1.5, Seliathan): our RETAIL chain mode (5CP unless
stacks proven empty, `rogue_guide.lua:171,393-405`) matches the
Envenom-chaining direction; no tick band (RETAIL nil,
`rogue_guide.lua:154`) matches phase-based pooling. Known guide-side
gaps (NOT sim-verified this lane, no new claims): no Deathmark/Kingsbane
sync pair, no pandemic-refresh modeling, no RtB/BTE/Deathstalker
concepts, CP-max assumption unmodeled. Sim-APL verification for Retail
remains open work for a lane with the retail sim repo.

## 7. Ranked hidden-technique / coverage gaps for the options+engine pass

1. H1 — SnD prompt + per-CP duration tables (sim-exact: TBC/classic
   [9,12,15,18,21]s; WotLK +ImpSnD/glyph; Forever 1CP-clip model; SoD
   4CP+CttC). Missing on all clients. HIGH.
2. H2 — Era Rupture-first is sim-contradicted (classic APLs Evisc-only;
   SoD APLs Envenom-primary, no Rupture). Family-split the finisher
   spine: ERA Evisc-first / TBC Rupture-first / SoD Envenom-primary (or
   mark SoD unsupported). HIGH.
3. H3 — WotLK sin upkeep triad HfB/SnD/CttC + Vanish→Overkill; SoD
   Vanish→Envenom sequence + Poisoned Knife. Unmodeled. HIGH (Wrath
   sin) / MEDIUM (SoD).
4. H4 — Per-client EA windows (ERA 3s / TBC 6s-imminent+15s-minimum /
   FOREVER 16s-lockout) vs single default 3. MEDIUM.
5. H5 — Pool lines per sim (TBC 71 single / Forever 75 cap-danger /
   WotLK 85 cap-exception / classic tick-gated AR+Tea) vs 65/85 carried
   everywhere. MEDIUM.
6. H6 — TBC pool-for-EA wait (sim "Cast Expose or Pool" group) and
   Forever EA finisher-lockout. Unmodeled. MEDIUM.
7. H7 — Shiv family-gating (sim: TBC combat non-Mutilate only; never on
   WotLK/Forever defaults) vs unconditional rule 2. LOW-MEDIUM.
8. H8 — Sweaty swing-gate (0.5s window + energy>=79 override, no weapon
   check) vs our 0.1–0.2s sword-only Era window. Needs in-client proof
   before widening; the >=79 override is portable now. MEDIUM.
9. H9 — Rupture durations scale with CP (sim 8–16s, +glyph 20s) vs flat
   min_ttd 8; TBC/sim recast-when-missing vs our 4s early refresh. MEDIUM/LOW.
10. H10 — Tea defaults (Era 29 / TBC 30 / Forever 15 / SoD 10-or-40-end /
    WotLK 50-potion-line) vs single default 40. LOW (tunable).
11. H11 — AR/BF/Cold Blood energy-gated prompts (sim: AR at 40–59 low
    energy + tick<1; BF behind SnD+EA; CB at 5CP). Unmodeled. MEDIUM.
12. H12 — Builder identity (Backstab/Mutilate/Saber/Hemo) vs single
    generic builder slot. MEDIUM.

## 8. Tooling / provenance notes

- GitHub HTML pages for the five brief repos render without file bodies;
  the API contents endpoints enumerated `sim/rogue` + APL directories
  (sod, classic, tbc-new, forever listings fetched OK), then raw file
  fetches supplied all APL/Go content above. Late in the lane the org
  API began rate-limiting (403/rate-limit JSON on
  `api.github.com/orgs/wowsims/repos`); raw.githubusercontent fetches
  were unaffected. No `git` used anywhere (standing rule).
- `wowsims/wotlk` was pulled as a supplement for the WRATH family (not
  in the brief URL set — flagged at every W-row). All W-rows should be
  re-checked by a lane tasked with the wotlk repo directly if the
  operator wants brief-pure sourcing.
- Negative results: no rogue rotation code found under
  `wowsims.github.io` (Pages host, no sim tree); no SoD Rupture usage in
  either fetched SoD APL; no Shiv in Forever default APL; no Envenom in
  TBC swords APL or Forever default APL; no Tea/AR prompt model in our
  engine (HUD-only, F3).
- Remembered-id rule kept: our side ships no ids (`classes/rogue.lua`
  SPELL_IDS/POISON_IDS empty, `classes/rogue.lua:127-128`); sim spell
  ids quoted above are sim-side evidence only, never proposed for our
  tables.

Validation owner: orchestrator.
