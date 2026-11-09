# Paladin rotation audit vs wowsims sims — 2026-10-19

Scope (read-only): `classes/paladin.lua`, `twist.lua`, `nextaction.lua`,
`tests/twist_state.lua`, `tests/nextaction_state.lua`, `tests/paladin_state.lua`.
Sim sources: `wowsims/sod`, `wowsims/forever`, `wowsims/classic`, `wowsims/tbc-new`
(master, fetched 2026-10-19). `wowsims/wowsims.github.io` is a Vite landing-page
template — no sim or rotation code, nothing to compare.
Wrath/Titanforge and Retail/Cata/Mists have no sim among the in-scope repos;
Wrath rows below are validated against `docs/research/rotations_wrath.md`
(Wowhead-guide-derived) only.

Conventions: MATCH = behavior agrees (cite both sides). GAP (impact) = sim does
something we don't, or vice versa. CONFLICT = we and the sim disagree on the same
decision. UNCONFIRMED = sim or guide data is beta/provisional.

## Cross-client core (all twist clients)

- MATCH — Twist window 0.4 s. Ours: `twist.lua:38` (`BASE_WINDOW_SECONDS = 0.4`,
  proc-delay 0.5 s documented `twist.lua:39`). Classic sim APL twists both
  directions when `autoTimeToNext < 0.4s`
  (`classic/.../apls/basic_ret.apl.json`). TBC sim APL twists SoC→SoB at
  `autoTimeToNext <= .4s`
  (`tbc-new/.../apls/default.apl.json`).
- MATCH — SoC proc ids. Ours `twist.lua:22-29` (20424/20944/20945/20946/20947 +
  TBC rank-6 29385). Classic sim `sim/paladin/soc.go` registers the same five
  procs per rank (20424 … 20947); 29385 is the TBC rank-6 extension.
- MATCH — Command freshness / reseal at 1 s. Ours `nextaction.lua:244-254`
  (SoC with ≤1 s left reads "none"). Classic APL reseals primary seal when
  `currentSealRemainingTime < 1`
  (`classic/.../apls/basic_ret.apl.json`).
- GAP (low) — 7 PPM + 1 s ICD proc model. Both sims model SoC as 7 PPM on
  white hits only with a 1 s ICD (`classic/.../soc.go`; `forever/.../seal_of_command.go`).
  Our attempt model (`twist.lua:60-65`) arms on any dual-seal swing and never
  considers the ICD, so swings <1 s after a proc are scored as live attempts
  that cannot proc. Reactive CLEU detection is unaffected; only the
  attempt/score semantics over-count in fast chains.
- GAP (low) — SoC Rank 1 discipline. Min/max consensus is Rank 1 only for
  twisting (`docs/research/tbc_minmax.md:26`); sim APLs cast rank 1
  (20375r1 in classic/TBC APLs). We detect all ranks but never advise rank
  choice.

## Era 1.15.9 (classic repo)

- MATCH — Twist pair is SoC↔SoR. Classic APL twists 20375r1↔20293r8 with the
  0.4 s rule; our Era twist seal is Righteousness (`classes/paladin.lua:110-112`,
  `ERA_TWIST_SEAL_ID = 21084`) fed into the twist-seal position
  (`classes/paladin.lua:2572-2576`).
- MATCH — No Crusader Strike. `cs_known=false` disables the CS override and
  resolves every no-seal tiebreak to Command (`nextaction.lua:403`,
  `nextaction.lua:517-536`); classic sim has no CS spell at all.
- MATCH — Single-target Consecration, HoW execute <20%. Era branch lifts the
  AoE-only gate (`nextaction.lua:618`) and cues HoW below 20% with its own
  cooldown (`nextaction.lua:601-602`); classic APL/sim has the same execute
  window (HoW 24275 ranks, `classes/paladin.lua:1838-1843`).
- GAP (low) — Judgement-stopattack. The classic sim exposes
  `IsUsingJudgementStopAttack` as a spec option
  (`classic/.../retribution/retribution.go`); our Judgement cue
  (`nextaction.lua:640-692`) never models stopattack, so judging inside the
  window is cued without the swing-cancel the sim assumes.
- GAP (low) — Prepull sequencing. Classic APL prepulls the primary seal at
  −1.5 s; we give no prepull/pull-seal guidance (guide starts at fight start).

## SoD / Exodin (sod repo)

- CONFLICT (medium) — Twist window 200 ms, not 400 ms. All SoD twist APLs use
  `autoTimeToNext <= 200ms` plus `strictSequence` cast+`wait(autoTimeToNext+200ms)`
  (`sod/.../apls/p4-twist.apl.json`, `sod/.../apls/p8-twist.apl.json`). The
  guide text we sourced says .4 s (`docs/research/rotations_sod.md:102`), but
  the sim that generates the numbers uses 200 ms. Our 0.4 s baseline
  (`twist.lua:38`) is therefore 2× the sim's window on SoD.
- GAP (medium) — Stopattack macros + swing-speed branches. `p8-twist` twists
  via `paladinCastWithMacro` StopAttack/StartAttack and branches fillers on
  swing speed (1.99 s / 3 s thresholds) with `StopAttack` filler casts for
  mid-speeds; `p4-twist` waits `autoTimeToNext−200ms` before filler casts.
  Our engine has no stopattack concept and gates fillers only on `speed > 2.2`
  (`nextaction.lua:589`).
- GAP (medium) — 10%-remaining refresh rule. SoD APLs refresh SoM only below
  10% fight-remaining (rune 429152-gated) and spam HoW <10% when HoW is
  unavailable (`p4-twist.apl.json`); our HoW cue is hp%+cooldown only
  (`nextaction.lua:601-602`) with no fight-remaining input.
- PARTIAL MATCH — Exodin FCFS order. Ours (`nextaction.lua:748`):
  exo > cs > ds > judge > cons > how. `p8-exodin.apl.json` order at the id
  level: Judge maintenance (seal <1 s) + primary-seal reseal first, then
  407778 → 415073 → 407676 (spell ids cited without role names — not mapped).
  Structural difference either way: the sim maintains seal/Judge above the
  damage order; our FCFS has no seal-maintenance rule (Judge is #4, no reseal
  concept).
- GAP (low) — Unmodeled SoD variants. Seal-stacking, Shockadin 1H/2H and
  Wrath-like builds are separate sim-tested rotations (`sod/.../retribution_test.go`:
  `TestSealStacking`, `TestShockadin1H/2H`, `TestWrathLike`); our SoD branch
  covers Exodin-style FCFS only.

## TBC Anniversary 2.5.6 (tbc-new repo)

- MATCH — Twist direction and window. TBC APL: SoC up (20375r1) and
  `autoTimeToNext <= .4s` → twist to SoB (31892r1); ours: same pair
  (`classes/paladin.lua:96-98`, `twist.lua:38`).
- MATCH — JotC/SotC maintenance concept. TBC APL prepulls Seal of the
  Crusader (27158r7) + Judges at 0 s, then twists; our JotC mini-bar tracks
  21183 (20 s, melee-refreshed) vs 10 s lower ranks
  (`classes/paladin.lua:1951-1956`, `classes/paladin.lua:2087-2103`) with a
  Crusader-priority cue (`nextaction.lua:653`).
- CONFLICT (medium) — Crusader Strike timing. TBC APL has no explicit CS
  entry: CS fires via `autocastOtherCooldowns`, itself gated behind the 11 s
  "Delay Major CDs" variable (`default.apl.json`). Our engine prompts CS via
  an explicit delay-budget override defaulting to 0.9 s
  (`nextaction.lua:393`, `nextaction.lua:565-583`). Pull-phase CS advice will
  differ (sim holds everything 11 s; we hold nothing at pull).
- CONFLICT (low-medium) — Filler defaults. TBC APL defaults `Use Exorcism`
  and `Use Consecrate` to false (opt-in). Our engine suggests Consecration
  whenever the target count is unknown (`nextaction.lua:618`: `ntargets ==
  nil` keeps the suggestion); with a known target we report single-target and
  withhold (`classes/paladin.lua:2641-2642`), which matches — the divergence
  is only the no-target-reading default.
- GAP (low) — Reseal guards. TBC APL reseals SoC only when Judgement is not
  ready AND `spellGcdHastedDuration <= .4s + autoTimeToNext` AND
  `autoTimeSinceLast >= .5s` (no reseal within 0.5 s of the last auto). Our
  reseal landmarks (`nextaction.lua:412-416`) have no since-last-auto guard.
- GAP (low) — No mana-sustain governor. TBC min/max notes twisting ooms in
  1–2 min without support (`docs/research/tbc_minmax.md:27`); sim APLs manage
  this via the disabled-by-default fillers + consumes, while our guide keeps
  prompting twists with no sustain input (filler mana thresholds
  `nextaction.lua:619` only gate fillers, never the twist itself).
- GAP (low) — Judge gate shape. TBC APL judges only on SoB with GCD ready and
  `autoTimeSinceLast <= .8s`; our Blood-path cue adds a reseal-fit cost model
  (3 GCDs, `nextaction.lua:310`, `nextaction.lua:662-677`) plus JotC priority
  — strictly richer, but unvalidated against sim DPS; the fit gate can hold a
  Judge the sim would take.

## Wrath / Titanforge 3.80.2 (no in-scope sim)

- MATCH (guide-level, UNCONFIRMED vs sim) — FCFS order. Ours
  (`nextaction.lua:747`): cs > judge > ds > cons > exo > hw, Exo instant-only
  under Art of War (`nextaction.lua:785-789`), HW Undead/Demon-only
  (`nextaction.lua:793-796`). Matches the Wowhead priority in
  `docs/research/rotations_wrath.md:64-70` verbatim, including the AoE
  omission (ST only, documented).
- MATCH (design) — 2pc-T10. Resets surface as live DS readiness, which the
  never-wait walk already elevates (`nextaction.lua:859-869`); documented as
  deferred explicit detection (`nextaction.lua:719-721`). Consistent with the
  guide note (`rotations_wrath.md:76-77`).
- GAP — No sim validation possible in scope. The WotLK sim repo is not among
  the five in-scope repos; FCFS pins are guide-derived
  (`tests/nextaction_state.lua:717-861`), not sim-derived.

## Retail 12.x (no sim in scope)

- MATCH (by design) — Inert. `evaluate` short-circuits to the empty display
  shape (`nextaction.lua:359-371`) and FCFS never runs on RETAIL
  (`nextaction.lua:838`); pinned (`tests/nextaction_state.lua:622-662`).
  Nothing to prompt with no live swing.

## WoW Forever 1.60.x (forever repo)

- MATCH — Twist pair SoC/SoR after autos; Judgement consumes no seal.
  Forever guides (beta, UNCONFIRMED) per `docs/research/forever_beta.md:59`;
  our Forever branch feeds SoR into the twist-seal position
  (`classes/paladin.lua:2569-2573`) and costs Judge at 1 GCD, no reseal
  (`nextaction.lua:324`, `nextaction.lua:673-674`).
- CONFLICT (medium) — Window source. Our Forever branch reuses the 0.4 s
  landmarks with the window explicitly UNCONFIRMED
  (`nextaction.lua:80-82`). The Forever sim has no swing-timing twist at all:
  Twist of Light is Echo-aura maintenance (Echo of Command 1311703 / Echo of
  Righteousness 1311704, one Echo at a time,
  `forever/.../retribution/twist_of_light_test.go`); the APL recasts a seal
  when its Echo is inactive, with reaction-time handling
  (`forever/.../apls/twist_of_light.apl.json`). We model neither Echo auras
  nor Echo-driven reseals.
- GAP (medium) — Holy Strike. Sim APL casts Holy Strike (10333r8) whenever
  `currentTime > 0.5s`, second in priority after Judgement; we do not probe it
  (no sourced spell id — documented `nextaction.lua:86`,
  `classes/paladin.lua:82-91` discipline). If Holy Strike ships as modeled,
  our guide misses the sim's #2 button.
- GAP (low-medium) — HoW shape. Sim casts HoW (24239r3) when its cast time is
  0 (instant) or within 0.2 s after the last auto — an instant-cast/proc
  window, not an execute threshold. Ours cues HoW below 20% hp with cooldown
  ready (`nextaction.lua:601-602`), missing the sim's post-auto instant-cast
  timing.
- GAP (low) — Filler gating. Sim gates Exorcism (10314r6) and Consecration
  (20924r5) on `autoTimeToNext > 1.5s` + mana ≥ 10%, no creature-type gate
  (`twist_of_light.apl.json` groups). Ours gates Exorcism on Undead/Demon +
  mana > 30 and Consecration on mana > 35 (`nextaction.lua:604-621`) — our
  TBC-era creature rule persists on Forever, where the sim treats Exorcism as
  a generic filler.
- GAP (low) — Seal duration model. Forever `sealDuration` is a shared const
  (`forever/.../seal_of_command.go`); our 30 s fallback
  (`classes/paladin.lua:39`) agrees numerically, and LCD never loads off
  Era/TBC — MATCH on value, no action.
- UNCONFIRMED (all Forever rows) — Beta guides + sim talent strings
  (`TwistOfLightTalents = "55003003--05225331101330321"`,
  `forever/.../retribution/retribution_test.go`) predate launch; any row
  above may move.

## Hidden techniques worth adopting (ranked)

1. SoD `strictSequence` twist: cast + `wait(autoTimeToNext+200ms)` after each
   twist seal (`p8-twist.apl.json`). Our `prediction_hold`
   (`nextaction.lua:436-446`) is advisory; the sim hard-waits the swing out.
   Medium impact on SoD.
2. Stopattack discipline: classic `IsUsingJudgementStopAttack` option; SoD
   `paladinCastWithMacro` StopAttack/StartAttack on twists, judges and
   mid-speed fillers. No equivalent anywhere in our guide. Medium impact.
3. Echo-aura maintenance (Forever): recast-on-Echo-inactive replaces swing
   timing entirely. Required for Forever accuracy if Twist of Light ships as
   simmed. Medium impact, Forever-only.
4. TBC reseal guard `autoTimeSinceLast >= .5s` + GCD-duration-vs-window fit
   (`default.apl.json`). Cheap to mirror in `is_twist_seal_active`-adjacent
   landmarks. Low impact.
5. Fight-remaining input (SoD 10% SoM/HoW rules). New input class; low impact
   outside execute-phase min/max.
6. PPM/ICD-aware attempt scoring (7 PPM, 1 s ICD, white-hits-only — both
   sims). Suppresses phantom attempts in fast chains; low impact, score-only.

## Validation owner

Orchestrator. Offline pins holding this audit: `twist_state.lua`,
`nextaction_state.lua`, `paladin_state.lua` (harness green per
`desks/journal.md`; re-run `bash tests/run.sh` on reconcile — no addon files
touched by this audit).
