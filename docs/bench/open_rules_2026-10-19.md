# Open rules: H6 lockout/wait, fight-remaining-time, Victory Rush — 2026-10-19

Desk: open-rules. READ-ONLY: no addon file touched, no git, no bench file
overwritten. Evidence bar: sim claims cite a raw file fetched this session
(URL + content quoted) = CONFIRMED; anything sourced from another audit
without a re-fetch = marked UNCONFIRMED in caps. Our-side refs are
`file:line` on the current tree (all re-read this session).

Scope read: `bench/rogue_rotation_audit_2026-10-19.md` (H6 = §7 item 6),
`bench/paladin_rotation_audit_2026-10-19.md` (§SoD 10%-remaining, hidden
technique #5 fight-remaining input), `bench/warrior_rotation_audit_2026-10-19.md`
(truncated mid-G1 on disk; headline + follow-ups recovered from
`desks/warrior-rotfix/journal.md`), `bench/verify_bank.md`,
`bench/rogue_rotation_gaps_closed_2026-10-19.md` (follow-up #4 = H6),
`rogue_guide.lua`, `warrior_guide.lua`, `classes/warrior.lua`,
`classes/paladin.lua`, `nextaction.lua`, `classes/rogue.lua`,
`docs/research/forever_beta.md`.

Sim files fetched raw this session (all 200 OK unless noted):
- TBC rogue: `https://raw.githubusercontent.com/wowsims/tbc-new/master/ui/specs/rogue/dps/apls/swords.apl.json`
- Forever rogue: `https://raw.githubusercontent.com/wowsims/forever/master/ui/specs/rogue/dps/apls/default.apl.json`
- Forever warrior VR: `https://raw.githubusercontent.com/wowsims/forever/master/sim/warrior/victory_rush.go`
- Forever warrior fury: `.../ui/specs/warrior/dps/apls/fury.apl.json`
- Forever warrior arms: `.../ui/specs/warrior/dps/apls/arms.apl.json`
- Classic rogue: `https://raw.githubusercontent.com/wowsims/classic/master/ui/rogue/apls/combat_sinister_strike.apl.json`
- SoD rogue: `https://raw.githubusercontent.com/wowsims/sod/master/ui/rogue/apls/P5_Saber.apl.json`
- SoD paladin: `https://raw.githubusercontent.com/wowsims/sod/master/ui/retribution_paladin/apls/p8-twist.apl.json`
- SoD paladin p4-twist: 404 at `ui/paladin/apls/p4-twist.apl.json` (wrong path
  guess; paladin-audit §SoD claims about p4-twist are therefore UNCONFIRMED
  this lane — p8-twist above carries the 10% rule independently).

---

## 1. H6 — TBC EA minimum + pool-for-EA wait + Forever finisher lockout

### What the sims do (CONFIRMED, fetched this session)

TBC (`tbc-new/.../swords.apl.json`), spell is Expose Armor 26866 rank 6:

- `valueVariables`: `"Minimum EA Time" = 15s`, `"Shiv Minimum EA Time" = 4s`,
  `"EA Fall Imminent" = auraRemainingTime(26866r6, target) <= 6s AND Imp EA
  talented`, `"At or Above Pool Threshold" = energy >= 71`,
  `"EA Above Minimum" = (Shiv AND EA >= 4s) OR (non-Shiv AND EA >= 15s)
  OR (Imp EA not talented)`.
- Group `"Cast Expose or Pool"`: at 5CP when Imp-EA talented and NOT EA Above
  Minimum, `waitUntil(EA Fall Imminent OR At or Above Pool Threshold)` — i.e.
  hold (neither builder nor finisher) while EA is below-minimum-but-not-imminent
  and energy is below the pool line and SnD is healthy — then cast 26866r6.
- The same `EA Above Minimum` / `EA and SnD Safe` gates also pause SnD, Rupture
  (26867), and Shiv (5938) entries: the whole spender set yields to the EA
  duty window.

Forever (`forever/.../default.apl.json`), spell is Expose Armor 11198:

- `"Expose - Low Duration" = Use Expose Armor AND (EA 11198 missing on target
  OR remains <= 16s)`.
- `"Expose - Prevent Other Finishers" = Use Expose Armor AND Low Duration`.
  While live it suppresses: SnD (6774), **Venom (1310703 at 3+CP)**, Rupture
  (11275 at 3+CP), Cold Blood (14177 at 5CP), and Eviscerate (11300, every
  branch incl. the 3CP fight-end branch). It does NOT suppress AR (13750),
  builders, Tea (7676), or potion lines.
  **CORRECTED 2026-10-20 (desk `corpus-corrections`):** this line used to say
  "**Riposte** (1310703 at 3+CP)" — 1310703 is **Venom** on the Forever
  client (`wowsims/forever sim/rogue/spell_data_auto_gen.go`:
  `Venom: spelldata.Ranked(1310703)`); the Forever APL's i=19 row is the Venom
  row. Evidence: `bench/rogue_apl_utility_build_2026-10-20.md` §3.8;
  `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **R7**.
- `"Maintain Expose"` group casts 11198 at 5CP when `"Expose - Should Cast
  Check"` (5CP AND Low Duration). `"Use Expose Armor"` defaults to `false` —
  the entire lockout is opt-in (duty toggle), exactly like our `ea_duty`.
- `"Fight About to End" = remainingTime <= 6s` additionally suppresses SnD
  and Rupture (but NOT the Evisc dump — the dump's fight-end branch survives).

### What our engine does

- `rogue_guide.lua:651-668` `ea_verdict`: duty + (missing OR remains <= window)
  → `"expose"`. Windows per family (`:298-303`): ERA 3, TBC 6, WRATH 3,
  FOREVER 16 — i.e. only the imminent/low lines shipped.
- Rule 1 (`:904-906`) puts expose above every spender — matches the sims'
  priority. But there is NO 15s-minimum concept, NO pool-for-EA wait (rule 7
  pool-vs-spend, `:961-969`, never yields to an EA duty), and NO finisher
  lockout (rules 1b/4/5 fire through a live EA-low exactly where the sims
  withhold). Filed as H6 in three places: header `:49-50`, data comment
  `:295-297`, and rotfix follow-up #4
  (`bench/rogue_rotation_gaps_closed_2026-10-19.md:42-44`: "new rule semantics
  needing APL-literal design + options; not safely separable here").
- Duty gating is already opt-in and nil-safe: `classes/rogue.lua:796`
  (`inputs.ea_duty = db.rogue_ea_duty == true`), `ea_verdict` returns nil
  unless duty is exactly true.

### Verdict: BUILD (small, APL-literal, nil-safe)

Build shape (pure engine + DATA, no new client queries, no new slots):

1. DATA: `EA_MINIMUM_BY_FAMILY = { TBC = 15, ... }` (+ Shiv-context 4 —
   Shiv-context needs the Mutilate-known probe which is itself filed, so ship
   the non-Shiv 15 first and note Shiv-4 as gated on that probe).
2. Wait rule (TBC): when 5CP + ea_duty + EA below minimum + NOT imminent
   (<=6) + energy below pool line (71 TBC) + SnD healthy → HOLD/POOL instead
   of builder/finisher (mirror of `waitUntil(EA Fall Imminent OR pool)`).
   Releases to `"expose"` through the existing rule 1 the moment either
   disjunct goes true — byte-identical to the APL group.
3. Lockout (Forever): when ea_duty + (EA missing OR <=16) → suppress rules
   1b (snd), 4 (dying dump), 5 (planned finisher), and the future Cold Blood
   prompt; keep rule 1 (expose), builders, tea, AR/BF live — the exact
   suppression set of `"Expose - Prevent Other Finishers"`.
4. All of it behind the existing `ea_duty` toggle (default off → zero
   default-visible change); minimum stays DATA, not an option, until the
   owner asks for tuning.

Why build instead of cut: the sim lines are APL-literal (ids + seconds quoted
above), the semantics are separable pure functions on inputs the gather
already feeds (cp, energy, ea_remains, snd_remains, band), and the duty
toggle makes the whole thing inert by default. Owner of validation:
orchestrator; the build lane owes per-branch pins + the filed Shiv/Mutilate
context as a second step.

---

## 2. Fight-remaining-time source

### What the sims do (CONFIRMED unless marked)

Sims read an encounter clock the addon cannot see — two shapes:

- Absolute seconds (`remainingTime`): classic rogue SnD at 1+CP when
  fight >= 6s, 5CP refresh when fight > 9s, Evisc (31016) at 5CP when
  fight < 6s (`combat_sinister_strike.apl.json`); SoD rogue Tea at <= 10
  energy OR (fight <= 15s AND energy <= 40), SnD only when fight >= 20s,
  Envenom/builder fight-end branches at <= 4s (`P5_Saber.apl.json`); Forever
  rogue `"Fight About to End" = remainingTime <= 6s` gating SnD/Rupture off
  and the 3CP Evisc dump on (`default.apl.json`).
- Percent of fight (`remainingTimePercent`): SoD paladin reseals Seal of
  Martyrdom (rune 429152-gated) only below 10% remaining and spams HoW
  (24239r3) below 10% (`p8-twist.apl.json`, two lines).
- HP-threshold instead of clock (warrior): both Forever APLs gate Execute
  (20662) on `isExecutePhase E20` — target HP%, never a remaining-time term
  (fury + arms APLs fetched; no `remainingTime` line in either).
- TBC shaman FS fight >= 12s gate: per `bench/shaman_rotation_audit_2026-10-19.md`
  §TBC, NOT re-fetched this lane → UNCONFIRMED here.

### What our engine does

- Paladin: `fight_remaining_pct` input EXISTS in the FCFS contract
  (`nextaction.lua:62`, `:812-814`) with `SOD_EXECUTE_FIGHT_PCT = 10`
  (`:359-361`) and the burn rule (`:877-892`: HoW without the hp read below
  10%). The provider feeds it **nil on every call**
  (`classes/paladin.lua:2770-2773`: "needs a boss-HP / encounter-timer
  source"), so the burn arm is correctly dormant and the archived hp-only
  rule carries — sim-faithful shape, zero live behavior.
- Rogue: NO fight-remaining input by design. The target-based equivalent
  ships instead: `ttd` numeric-only EMA input (`rogue_guide.lua:103-110`,
  `TTD_EMA_ALPHA = 0.25`, `:382`), rule 4 dying dump (`:921-924`, per-family
  CP floors) and `finisher_for_ttd` (`:478+`). Covers the single-target
  substance of "Fight About to End" (6s) without an encounter clock.
- Druid: `time_to_die` sampler (`classes/druid.lua:1541-1589`,
  `:1654`); ERA ignores it, WRATH executes on last-10s — target-based, same
  substitution.
- Warrior: NO fight-remaining input; Execute keys on `target_health_pct <
  execute_pct` (`warrior_guide.lua:538-542`, `:609-611`) — the same HP%
  shape the warrior sims use (`isExecutePhase E20`).

### Verdict: CUT (no new sensor, keep the substitutions, keep the stub)

Reason: no WoW API exposes encounter-remaining (seconds or percent). The
only honest sources would be boss-unit HP scans or boss-mod
(DBM/BigWigs) coupling — new surface, multi-target/phase-change semantics
(a dying add is not a dying boss), all UNCONFIRMED in-client. TTD (rogue,
druid) and target HP% (warrior, paladin) already cover the single-target
execute substance: the Forever 6s lockout-release maps onto our rule-4 dump,
and the warrior sims never use a clock at all. Concretely: keep
`fight_remaining_pct` nil-fed and dormant (it documents the sim shape for
the day a source exists); do NOT build a boss-HP/encounter-timer probe this
wave. If the owner later wants the TBC shaman FS fight gate, the cheap
honest form is a TTD floor on the shaman rule — a new input on that engine,
not an encounter clock. In-client confirmation owed before any of that:
none (nothing to confirm — that is the point).

---

## 3. Victory Rush handling

### What the sims do (CONFIRMED, fetched this session)

- `forever/sim/warrior/victory_rush.go`: registers an Execute-like nuke + heal
  gated on `ExtraCastCondition = victoriousAura.IsActive()` (the Victorious
  aura from a killing blow), deactivating the aura on press. File comment
  verbatim: `// This spell works but the Sim never kills a target` — the
  rotation never sees the aura because sim fights never produce a kill.
- Neither Forever APL casts it: `fury.apl.json` and `arms.apl.json`
  (both fetched, full contents inspected) contain NO Victory Rush line —
  Execute appears only as 20662 gated on `isExecutePhase E20`. The sim
  models the spell and the APL never prompts it. There is nothing to match.
- Beta guides list Victory Rush as a Forever arms/prot/fury spell
  (`docs/research/forever_beta.md:37`) but give no id — guide-exists,
  sim-unused, id-unknown.

### What our engine does

- Bypass, not a slot: `warrior_guide.lua:136-143` (input contract),
  `:172-174` (rule-2 spec: ready Victory Rush bypasses the health gate
  "like the SoD Sudden Death bypass"), `:538-553` (implementation: rule 2
  fires Execute at any health when `inputs.victory_rush == true`, still
  behind OP and before Slam/BT/WW). Reuses the execute slot
  (`classes/warrior.lua:2180-2181`: "Victory Rush reuses the execute slot").
- Provider (`classes/warrior.lua:2500-2518`): Forever-only; requires
  family + (id-known 34428 OR name-known "Victory Rush") + `IsSpellUsable`.
  Id 34428 is the WotLK Victory Rush id, carried UNCONFIRMED for Forever
  (`:227-235`, west explicit: "a wrong id fails safe to nil"). Nil on every
  other family and whenever neither probe answers — the bypass is dormant
  there exactly like before. Filed as follow-up (f) in
  `desks/warrior-rotfix/journal.md`: "Victory Rush stays UNCONFIRMED (no
  Forever APL line; sims never kill the target)".

### Verdict: HOLD DORMANT (keep the bypass, cut all wiring work)

Reason: cutting the bypass buys nothing (it is already inert wherever the
probes fail, adds no slot, changes no default-visible behavior) and building
on it now would mean guessing: the Forever spell id (34428 UNCONFIRMED),
the Victorious aura id/duration (no source anywhere — not in the sim, not
in beta guides), and the usable semantics. The sim side is decisive about
one thing: there is no APL behavior to be faithful TO (the sim never kills
a target, both APLs confirm by absence). Keep the three-line bypass + the
nil-safe probe exactly as-is; do NOT add a Victory Rush slot, aura scan, or
options toggle until a Forever in-client pass confirms (a) the VR spell id,
(b) the Victorious aura id + duration, (c) that `IsSpellUsable` actually
tracks the post-kill window. Checklist item for the owner test session, not
a build lane. (Bloodthrill, `classes/warrior.lua:220-225`, is in the same
boat — name-only by design — and stays untouched for the same reason.)

---

## Validation owner

Orchestrator. Offline pins holding this report: the six fetched APL/Go files
(contents quoted above — re-fetch the URLs to verify), and the our-side
`file:line` refs (re-read this session, no addon files touched by this
lane). In-client confirmations owed: H6 none (pure engine, needs pins not
probes); Victory Rush ids/aura on 1.60.x; fight-clock: nothing (cut).
