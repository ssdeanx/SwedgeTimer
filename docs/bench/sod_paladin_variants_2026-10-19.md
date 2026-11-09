# bench/sod_paladin_variants_2026-10-19 — SoD ret build-variant APL verdicts

Desk: wrath-sod-variants (subagent, read-only except this NEW file). Date: 2026-10-19.
Scope: close `bench/wrath_sod_2026-10-19.md` §4 backlog — the four SoD variants cut for
"no APL fetched" (Seal-stacking, Shockadin 1H/2H, Wrath-like) plus re-verdict of the two
kept shapes (Twist, Exodin) against their p8 APL bodies.
No addon file changed; no git; no existing bench file overwritten. In-client behaviour
UNCONFIRMED throughout; sim-match is not client proof.

Method / tooling (per standing research rules — enumerate, then pick):
- `firecrawl` + `searxng` catalogs enumerated in-lane. Served this round: direct
  `fetch` of raw GitHub URLs (test + all six p8 APLs + builds + two sim spell files)
  and SearxNG web corroboration. `gh_grep` DOWN (HTTP 500 this session) — sim-spell
  identity resolved via raw-file fetch instead. `firecrawl_*` unused (no bare scrape
  needed; raw fetch is exact).
- `bench/sod_paladin_variants_2026-10-19.md` confirmed ABSENT before writing
  (`ls` no-such-file, in-lane).

## 0. Sources fetched this session (all URLs re-fetchable by orchestrator)

Sim (wowsims/sod, master):
- `sim/paladin/retribution/retribution_test.go` — six Test funcs
  (`TestRetribution`, `TestExodin`, `TestShockadin1H`, `TestShockadin2H`,
  `TestSealStacking`, `TestWrathLike`), each p8 case via
  `GetTestBuildFromJSON(..., "p8-<variant>")`. Only the p8 lines are live; all
  older-phase cases are commented out.
  https://raw.githubusercontent.com/wowsims/sod/master/sim/paladin/retribution/retribution_test.go
- p8 APLs (all six exist — the "no APL fetched" gap from the prior lane is CLOSED):
  `p8-twist` (10510 B), `p8-exodin` (1261 B), `p8-stack` (1722 B),
  `p8-shockadin-1h` (2559 B), `p8-shockadin-2h` (2558 B), `p8-wrath` (2281 B),
  under `ui/retribution_paladin/apls/` (25 files total, incl. p4–p7 predecessors).
  https://raw.githubusercontent.com/wowsims/sod/master/ui/retribution_paladin/apls/p8-<variant>.apl.json
- `ui/retribution_paladin/builds/` — all six `p8-<variant>.build.json` present.
- `sim/paladin/aura_mastery.go` — 407624 identity + behaviour (legs rune, Sanctified
  holy-multiplier 1.2/1.1, Libram-of-Sanctity interaction).
- `sim/paladin/holy_shock.go` — Holy Shock ranks (20473/20929/20930), 30 s CD,
  6 s with Infusion of Light waist rune.

Spell/id names (classic.warcraftdb.com pages viewed this session — title cited):
| id | page title as seen |
|---|---|
| 407798 | Seal of Martyrdom |
| 20920 | Seal of Command (APL uses rank 5) |
| 20271 | Judgement |
| 407778 | Divine Storm |
| 415073 | Exorcism |
| 407676 | Crusader Strike |
| 20930 | Holy Shock (APL uses rank 3, max rank per holy_shock.go) |
| 24239 | Hammer of Wrath (APL uses rank 3) |
| 10318 | Holy Wrath (APL uses rank 2) |
| 20924 | Consecration (APL uses rank 5) |
| 1226460 | S03 Scarlet Enclave Ret 2P Bonus (set-aura id; APL gates "known") |
| 1226461 | Holy Power (stack aura; APL gates stacks == 3) |
| 426157 | The Art of War |
| 429152 | Improved Hammer of Wrath (rune; APL gates SoM/HoW execute_REFRESH) |
| 467518 | S03 T2 Ret 2P Bonus (gates Judge in p8-wrath) |
| 1226464 | Templar (APL: wait-for-DS rule) |
| 1219193 | Naxx Ret 6P Bonus (gates Undead-only Holy Wrath / Exo lines) |
| 1214298 | Libram of Sanctity (gates Aura Mastery 407624 lines) |
| 1239543 | Sunlight (maintenance aura in shockadin APLs) |
| 1240574 | Templar (maintenance aura in shockadin APLs) |
| 16322 | Juju Flurry (consumable opener, prio #2 shockadin/wrath) |
| item 241241 | page title "Lucky Doubloon" — NAME UNCONFIRMED (see §8); ROLE clear: on-use upkeep (`auraRemainingTime < 1.5s` refresh, all six APLs) |
| item 241037 | page title "Abandoned Experiment" — NAME UNCONFIRMED (see §8); ROLE clear: unconditional opener (#1 shockadin/wrath) |

SearxNG corroboration (builds are real played shapes, not sim-only):
- "Wrath-like Ret" P8 video guides exist (May 2025, still referenced):
  https://www.youtube.com/watch?v=_Q9b-SG7H3s
- Shockadin P8 discussion (r/classicwow, Apr 2025):
  https://www.reddit.com/r/classicwow/comments/1k4zreq/shokadin_dps/

## 1. Twist (`p8-twist`) — MATCH (post-rotfix), keep + one new filed GAP

Sim shape (fetched `p8-twist.apl.json`, full 10510 B): prepull SoC(20920r5)@−1.5 s +
SoM(407798)@0; 200 ms hard-wait rule; autocast-CDs gated on stacks; trinket upkeep;
Judge rule split by swing speed (≥1.99 s: Judge iff both seals active and
`autoTimeToNext ≥ swing−200ms`; <1.99 s: Judge-with-StartAttack); execute: SoM reseal
<10% fight (429152-gated) + HoW spam <10%; twist reseals via `strictSequence`
cast+`wait(autoTimeToNext+200ms)` both directions on slow weapons; filler branches by
swing band (≥3 s: DS→Exo→CS with `wait(autoTimeToNext−200ms)`; 1.99–3 s: StopAttack
+`wait(gcd+100ms)`; <1.99 s: StartAttack variants incl. Holy Wrath + Cons).
Our engine: SoD 200 ms window + `prediction_hold` (paladin-rotfix lane); FCFS_SOD
order `exo > cs > ds > judge > cons > how` (`nextaction.lua:900`); seal-maintenance
constant + single-seal input (`nextaction.lua:393`, `:1024-1029`).
Verdict: MATCH, keep. No new slot/mode/key.
New GAP (LOW, filed — not built here): p8-twist gates filler DS/Exo/CS on
Holy-Power 3-stack (`auraNumStacks(1226461)==3`) OR set-unknown (`!auraIsKnown(1226460)`).
Our gather has ZERO Holy-Power input (`grep 1226461 classes/paladin.lua` = no hits) —
needs a new stack-count input before any APL-faithful DS gating. Same input serves
Exodin/stack/wrath-like below (§7 shared list).

## 2. Exodin (`p8-exodin`) — MATCH, keep (prior GAP now CLOSED in-tree)

Sim shape (fetched, 1261 B, smallest APL): prepull primary seal −2.5 s; autocast CDs;
trinket; Judge iff `currentSealRemainingTime ≤ 1s` AND GCD ready; reseal iff <1 s;
DS(407778) stack-gated (3×Holy Power or set-unknown); Art-of-War(426157) active →
hard wait out its duration; then Exo(415073) → CS(407676).
Our engine: FCFS_SOD (`nextaction.lua:900-901`, `evaluate_fcfs` `:991-1057`) +
`SEAL_MAINTAIN_RESEAL_SECONDS = 1` (`:393`) + `seal_remaining_seconds` input with
judge-lift on expiry (`:1024-1029`, `:1045-1046`) — landed by the paladin-followups
lane AFTER the rotation audit. The audit's "no seal-maintenance rule" GAP is therefore
CLOSED in-tree; no Exodin change owed.
Verdict: MATCH, keep. Filed refinement (LOW, shared input): DS 3-stack gate needs
§7 Holy-Power input; our walk never withholds DS on stacks today.

## 3. Seal-stacking (`p8-stack`) — BUILD (APL now in hand; scoped, not a tweak)

Sim shape (fetched, 1722 B — first read this lane): prepull SoC@−3 s + SoM@−1.5 s;
autocast CDs; trinket; INDEPENDENT refreshes (SoC ≤1 s, SoM ≤1 s — two seal timers,
not one); DS stack-gated; CS; Exo; Holy Wrath r2 on Undead w/ Naxx-6pc; Cons r5;
Judge(20271) ONLY when BOTH seals simultaneously active (dual-seal gate, last line).
Test basis: AP-weighted `Stats` (same EP as twist/exodin).
Why it is its own rotation, not a parameter: the engine's single
`seal_remaining_seconds` input (`nextaction.lua:1024`) cannot represent two live
seals; twist ALTERNATES seals while stack MAINTAINS both; Judge gating is inverted
(stack: Judge-only-on-dual vs twist: Judge-consumes-no-reseal cadence).
Verdict: BUILD with APL citation above. Design owed (for the build lane, not this one):
dual-seal timer inputs (SoC-remaining + SoM-remaining), dual ≤1 s refresh rules,
Judge dual-seal gate, plus §7 Holy-Power input for the DS line. No FCFS-order change
covers this — separate maintenance state machine.

## 4. Shockadin 1H (`p8-shockadin-1h`) — BUILD (APL now in hand; spellpower basis)

Sim shape (fetched, 2559 B): prepull primary seal −1.5 s; opener item 241037 → Juju
Flurry 16322; autocasts held until 5 s; trinket; seal/Judge maintenance at 1.5 s
(wider than Exodin's 1 s); Aura Mastery(407624, legs rune per `aura_mastery.go` —
Sanctified holy-multiplier, Libram-of-Sanctity-gated) + Holy Shock(20930r3) woven on
Sunlight(1239543 ≤1.5 s) / Templar(1240574 ≤1.5 s at 3 stacks) maintenance; then
Exo → (Libram-gated AM + HS at 3 stacks) → HS at 3 stacks → CS.
Test basis: `ShockadinStats` EP (spell-power-weighted) — different stat basis from
every other variant (which use AP `Stats`). P5/P7 predecessors run Seal of
Righteousness primary (`PlayerOptionsSealofRighteousness(NoAura)`).
Verdict: BUILD with APL citation above. Design owed: Holy-Shock-known input (talent
+ Infusion 6 s-CD shape per `holy_shock.go`), spellpower EP basis, Sunlight/Templar
remaining inputs, Aura-Mastery-rune + Libram inputs, SoR-primary seal plumbing
(current SoD seal plumbing is SoM/SoC-oriented). Guide has no holy-damage caster
rule anywhere — confirms this was never a tweak of FCFS.

## 5. Shockadin 2H (`p8-shockadin-2h`) — BUILD (same design as 1H; one sim quirk)

Sim shape (fetched, 2558 B): identical priority list to 1H except gear/build
(`p8-shockadin-2h` build; P7 predecessor runs SoM-primary `...SealofMartyrdomNoAura`
vs 1H's SoR). One SIM-SIDE QUIRK (UNCONFIRMED impact): the first Holy-Shock
Sunlight condition reads `"val":"1.5"` (no `s` unit) where 1H reads `"1.5s"`.
Whether the APL parser coerces it is unknown — flag to the build lane, do not
"fix" the sim from here.
Verdict: BUILD with APL citation above, shared with §4 (one design, two gear sets —
matches the test file running both under `ShockadinStats`).

## 6. Wrath-like (`p8-wrath`) — BUILD (APL now in hand; confirms the alias CUT)

Sim shape (fetched, 2281 B): prepull primary seal −1.5 s; autocasts ONLY at 3 stacks;
opener 241037 → Juju Flurry; trinket; Judge gated on T2-2pc-known (467518);
reseal ≤0.5 s (tightest of all variants); Templar(1226464 ≤1 s at 3 stacks) → wait
for DS; DS at 3 stacks → CS → Exo → DS (ungated fallback) → Judge-on-GCD fallback →
Cons filler ONLY when DS/CS/Exo all >1.5 s out (or stacks <3).
Why the prior CUT stands AND becomes a BUILD: the prior lane cut "alias
`fcfs_mode="wrath"` onto SoD" with reason "would prompt uncastable buttons" — the APL
confirms it: single different seal set, Holy-Power-stack-gated DS, T2-2pc Judge gate,
Templar-wait. Family-WRATH table (`FCFS_ORDER_WRATH`, `nextaction.lua:899`) shares
only the NAME. Verdict: BUILD as a SoD-native mode with APL citation above; needs
§7 stack inputs + Templar-remaining + T2-2pc-known. Never alias the Wrath table.

## 7. Shared new-input shopping list (all BUILD verdicts need these first)

No variant above is buildable on current gather alone. Common missing inputs, all
sourced to APL conditions fetched this session:
1. Holy-Power stacks `auraNumStacks(1226461)` + set-known `auraIsKnown(1226460)` —
   DS gating in twist/exodin/stack/wrath (zero hits in `classes/paladin.lua` today).
2. Templar `auraRemainingTime(1226464)` — wrath-like DS-wait rule.
3. Sunlight(1239543) + Templar-stack(1240574) remaining — shockadin HS/AM weave.
4. Aura-Mastery legs-rune-known + Libram of Sanctity(1214298)-known — shockadin AM lines
   (sim: `hasRune(RuneLegsAuraMastery)`, `aura_mastery.go`).
5. Holy-Shock-known (talent) + Infusion-of-Light 6 s-CD shape (`holy_shock.go`) —
   shockadin core button (APL rank 3 = max rank).
6. Dual-seal timers (SoC-remaining + SoM-remaining) — stack maintenance (§3); single
   `seal_remaining_seconds` insufficient by construction.
7. SoR-primary seal plumbing + spellpower EP basis — shockadin (§4/§5).
8. On-use item roles (241037 opener, 241241 upkeep) — structure-clear, names
   UNCONFIRMED (§8).

## 8. UNCONFIRMED ledger (nothing below blocks the verdicts; all need in-client/sim-source proof)

- In-client behaviour of every APL line ( castability, ranks, macro semantics).
- `p8-shockadin-2h` `"1.5"`-vs-`"1.5s"` quirk (§5) — parser behaviour unknown.
- Item names: warcraftdb-classic titles ("Lucky Doubloon" 241241, "Abandoned
  Experiment" 241037) do not match on-use-trinket roles; likely id-collision across
  data versions. NOT looked up in `sim/common` item sources (out of scope) — build
  lane to resolve via sim `items.go`/`itemhelpers` before wiring any icon/name.
- `20920r5` rank semantics (SoD Seal of Command ranks) — APL-cited, client-unconfirmed.
- P4–P7 predecessor APLs listed (§0) but NOT read — p8-only verdicts; predecessors
  may narrow the input list (e.g. `p5-seal-stacking-6CF-2DR`, `p7-exodin-fast-stack`).

## 9. Validation

Owner: orchestrator. Method: re-fetch the §0 raw URLs (test + six APLs + two sim
spell files), re-check our-side lines (`nextaction.lua:393,899-901,991-1057`;
`grep 1226461 classes/paladin.lua` still empty), confirm this file is NEW
(`ls bench/sod_paladin_variants_2026-10-19.md` exactly once), `bash tests/run.sh`
on reconcile (no addon file touched by this lane).
