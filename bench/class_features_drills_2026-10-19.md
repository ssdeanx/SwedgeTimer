# bench/class_features_drills_2026-10-19.md — per-class feature checklist + practice spec

Desk: `class-drills-spec`. Date: 2026-10-19. **Read-only lane** — one NEW bench
file only (this one; glob-verified ABSENT in-lane before writing). No addon file,
no test file, no other bench file touched, no git. `practice.lua` / `practice_ui.lua`
were READ (a sibling lane owns them); class files were READ only.

Validation owner: **orchestrator** (per every lane record in this workshop).

> **⚠ CORRECTED 2026-10-20 (desk `corpus-corrections`).** The five utility-layer
> build lanes (`warrior-apl`, `hunter-apl`, `rogue-apl`, `druid-apl`,
> `shaman-apl` — all 2026-10-20) re-fetched the wowsims sources and disproved
> **three rows of this file**: **W-16** (the Hamstring id), **W-20** (the
> "Devastate 25212" id) and **R-20** ("Riposte 1310703"). Each is corrected
> **in place** with a dated note naming the old value and the evidence; the
> superseded value is never silently dropped. The full log — 31 corrections
> across the corpus — is `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0.
> Rows this file already carried correctly (1857 Cloak of Shadows, 14183
> Shadowstep, 9850-as-Mangle, 17364-as-Nature's-Wrath, 29228-as-Flametongue,
> 10497-as-Rockbiter, 56641-as-a-TBC-Steady) are listed in the log for
> completeness but did not appear here.

---

## 0. Method, evidence bar, how to read this file

**Sources read** (bench + desk journals, 2026-10-19):

| Source | What it contributed |
|---|---|
| `bench/class_matrix_2026-10-19.md` | the 6×12 shared-system feature matrix (HUD/guide/rotation-key/TOC/practice cells) |
| `bench/paladin_rotation_audit_2026-10-19.md` | paladin sim-vs-engine verdicts, per client |
| `bench/warrior_rotation_audit_2026-10-19.md` (+ `desks/warrior-rotfix/journal.md`) | warrior verdicts; the audit file is truncated mid-G1 on disk, the desk journal carries the gap list |
| `bench/hunter_rotation_audit_2026-10-19.md` | hunter verdicts, per client |
| `bench/rogue_rotation_audit_2026-10-19.md` + `bench/rogue_rotation_gaps_closed_2026-10-19.md` | rogue verdicts + the engine-side closure table |
| `bench/druid_rotation_audit_2026-10-19.md` (+ `desks/druid-rotfix/journal.md`) | druid verdicts + closure |
| `bench/shaman_rotation_audit_2026-10-19.md` (+ `desks/shaman-rotation-fix/journal.md`) | shaman verdicts + closure |
| `bench/sod_paladin_variants_2026-10-19.md` | the six SoD paladin p8 APLs (twist/exodin/stack/shockadin-1h/shockadin-2h/wrath) |
| `bench/wrath_leftovers_2026-10-19.md` | wowsims/wotlk value ledger (shaman S1-S5, druid D1-D9) |
| `bench/rogue_hunter_eratbc_2026-10-19.md` | Era/SoD/TBC guide + HUD + drill status for rogue/hunter |
| `bench/hunter_wa_map_2026-10-19.md` | TBC hunter WA ids, mana group, Arcane rank conflict |
| `bench/practice_gamification_design_2026-10-19.md` + `bench/buildout_practice_gamification_foundation_2026-10-19.md` | the unlock registry contract a drill variant must satisfy |
| `bench/shaman_drill_designer_2026-10-19.md`, `bench/hunter_practice_designer_2026-10-19.md`, `bench/paladin_practice_designer_2026-10-19.md` | the archive pattern the existing drills follow (panel icons + shared score + designer coverage) |
| `bench/lessons.md` | the standing rules (no invented ids, unknown-hides, no default-visible change, operator owns git) |

**Evidence bar.** Every sim-derived value in this file carries its source (the wowsims
APL or `.go` file that produced it, named in the per-class audit that quotes it).
Values that are addon policy (grading bands, drill durations chosen by us) are marked
**[DESIGN]** so the build lane never mistakes a design number for a sim number.
Where a value is only client-observed or only beta-documented it stays **UNCONFIRMED**
in caps.

**Verdict vocabulary** (per class, feature checklist):

- **WIRED** — the behaviour exists in the tree; cited as `file:line`.
- **DEGRADED** — the behaviour exists but is partial, dormant, or unsourced; cited as
  `file:line` **+ what is missing**.
- **MISSING** — no implementation and no rule; cited as the audit row that proves the
  sim does it.

**Practice vocabulary** (operator order, 2026-10-19, two corrections applied):

- **SCENARIO** = running the class's actual wowsims rotation end-to-end. This is the
  primary practice mode for every class.
- **DRILL** = a focused single-skill trainer (twist timing, weave fit, powershift,
  forced-move, execute phase).
- Baseline resource behaviour (a drill that only teaches "don't waste the resource")
  **does not count** toward the drill target. By operator ruling,
  `rogue_energy_pool` is baseline resource behaviour.

---

## 1. Taxonomy, counts, and what the tree has today

### 1.1 Effective counts

| Class | Registry entries | Real DRILLS (operator ruling) | Notes |
|---|---|---|---|
| PALADIN | 2 | **2** | twist timing + AW burst-window — two different skills |
| WARRIOR | 1 | **1** | execute-phase entry (rage pooled at the 20 % crossing) |
| HUNTER | 1 | **1** | forced-move cadence |
| ROGUE | 2 | **1** | `rogue_energy_pool` = BASELINE resource; `rogue_ss_window` = the real drill |
| DRUID | 1 | **1** | powershift cadence |
| SHAMAN | 1 | **1** | weave timing |

**No class has a rotation SCENARIO.** Every one of the eight registry entries is a
DRILL. The primary practice mode for every class is therefore still missing.

### 1.2 The eight registry entries (`practice.lua` `H.register_scenario`)

| # | key | class | kind | practice.lua | Grades |
|---|---|---|---|---|---|
| 1 | `paladin_twist` | PALADIN | `paladin_twist` | `:1798` | the seal-twist **window timing** (0.4 s / 0.2 s SoD) |
| 2 | `paladin_aw_combo` | PALADIN | `combo_windows` | `:1969` | the AW **burst-window sequencing** (opener + haste pieces inside a 3 s window; grade = slowest piece lag) |
| 3 | `hunter_forced_move` | HUNTER | `forced_move` | `:2093` | **forced-move cadence** + cast legality around the windows |
| 4 | `warrior_execute` | WARRIOR | `execute_phase` | `:2214` | **execute-phase entry**: the rage pooled at the 20 % crossing |
| 5 | `druid_powershift` | DRUID | `energy_loop` | `:2363` | the **powershift cadence** (energy at the moment of the shift) |
| 6 | `shaman_weave` | SHAMAN | `weave_timing` | `:2454` | the **weave fit** (marker fraction / clip) |
| 7 | `rogue_energy_pool` | ROGUE | `energy_loop` | `:2554` | **baseline resource**: the spend start vs the 2 s energy-tick marker |
| 8 | `rogue_ss_window` | ROGUE | `swing_window` | `:2635` | the **Era SS-after-swing window** (0.1–0.2 s) |

Harness facts the build lane must respect:

- `H.SCENARIO_KINDS` (`practice.lua:1495-1503`) is a **closed set**; `register_scenario`
  rejects an unknown kind with an error string (`practice.lua:1520-1522`). A rotation
  scenario therefore needs a **new kind** — see §4.1.
- Registry pins live at `tests/practice_state.lua:1375-1403` (`#H.SCENARIO_ORDER == 8`,
  per-class counts, order pins, rejection pins). Every new entry breaks the `8` pins
  and needs new pins.
- `practice_ui.lua:630-637` `PRACTICE_DRILL_KEYS` maps a class to **exactly one** drill
  key (PALADIN → `paladin_twist`, WARRIOR → `paladin_twist` — the shared twist session,
  HUNTER → `hunter_forced_move`, SHAMAN → `shaman_weave`, ROGUE → `rogue_energy_pool`,
  DRUID → `druid_powershift`). A scenario + N drills per class breaks this shape —
  see §4.2.
- `practice_progress.lua` (`P.register_unlock`, `P.KIND_DRILL_VARIANT`) requires a
  variant unlock to name the NEW scenario it grants (`spec.scenario`), and hard-forbids
  touching an existing drill's grading
  (`bench/buildout_practice_gamification_foundation_2026-10-19.md` §"The generic unlock
  registry"). Every drill/scenario key in §2 is therefore also the future
  `drill_id` on the mastery table and the `spec.scenario` of a level-gated variant.

---

## 2. The six per-class feature checklists, drill inventories, target sets

Each class below carries: **(A)** the rotation-feature checklist the sim APL implies,
**(B)** the drill inventory, **(C)** the target drill set (≥3 distinct skills), and
**(D)** the target rotation SCENARIO.

### 2.1 PALADIN

#### (A) Feature checklist

| # | Feature the sim implies | Sim source | Verdict | Anchor / what is missing |
|---|---|---|---|---|
| P-01 | Twist window 0.4 s | classic `basic_ret.apl.json`; tbc-new `default.apl.json` (`autoTimeToNext <= .4s`) | WIRED | `twist.lua:38` `BASE_WINDOW_SECONDS = 0.4` |
| P-02 | Twist window 0.2 s (SoD) | sod `p4-twist.apl.json`, `p8-twist.apl.json` (`<= 200ms`) | WIRED | `twist.lua:45` `SOD_WINDOW_SECONDS = 0.2` |
| P-03 | Twist pair SoC↔SoR (Era) / SoC↔SoB (TBC) | classic `20375r1↔20293r8`; tbc-new `20375r1→31892r1` | WIRED | `classes/paladin.lua:96-112` (`ERA_TWIST_SEAL_ID = 21084`) |
| P-04 | SoC proc ids + 1 s ICD | classic `soc.go`; forever `seal_of_command.go` | WIRED | `twist.lua:22-29`, `twist.lua:72-83` (`SOC_PROC_ICD_SECONDS = 1`) |
| P-05 | SoC scored as 7 PPM, white hits only | both sims' `soc.go` | DEGRADED | `twist.lua:60-65` — the attempt model arms on **any** dual-seal swing and ignores the ICD/P; reactive CLEU detection is unaffected, but the *attempt score* over-counts in fast chains (audit "GAP (low)") |
| P-06 | Twist on SoC **rank 1** (20375r1) | classic + tbc-new APLs cast `20375r1` | DEGRADED | every rank is detected, rank choice is never advised; `nextaction.lua` accepts `soc_rank1_known` as an input but no slot/option exists (`desks/paladin-fixes/journal.md:11` — filed "SoC Rank-1 advice") |
| P-07 | Command freshness / reseal under 1 s | classic APL `currentSealRemainingTime < 1` | WIRED | `nextaction.lua:393` `SEAL_MAINTAIN_RESEAL_SECONDS = 1`; used at `:1207` |
| P-08 | SoD FCFS order `exo > cs > ds > judge > cons > how` | sod `p8-exodin.apl.json` | WIRED | `nextaction.lua:947` `FCFS_ORDER_SOD` |
| P-09 | SoD **seal-stacking** variant (two independent seal timers; Judge only on dual-seal) | sod `p8-stack.apl.json` | DEGRADED | the order table exists (`nextaction.lua:959` `FCFS_ORDER_SOD_STACK`) but the engine has a **single** `seal_remaining_seconds` input (`nextaction.lua:1202`, spec at `:77`), so two live seals cannot be represented — `bench/sod_paladin_variants_2026-10-19.md` §3 = BUILD (new state machine, not a tweak) |
| P-10 | SoD **Shockadin 1H / 2H** (Holy Shock, Aura Mastery, Sunlight/Templar) | sod `p8-shockadin-1h.apl.json`, `p8-shockadin-2h.apl.json` | MISSING | no holy-damage caster rule anywhere; `bench/sod_paladin_variants_2026-10-19.md` §4/§5 = BUILD |
| P-11 | SoD **Wrath-like** variant (HP-stack-gated DS, T2-2pc Judge gate, reseal ≤ 0.5 s) | sod `p8-wrath.apl.json` | MISSING | `bench/sod_paladin_variants_2026-10-19.md` §6 = BUILD; must be a SoD-native mode, never an alias of `FCFS_ORDER_WRATH` |
| P-12 | Holy-Power stack count (1226461) + set-known (1226460) | all six p8 APLs | MISSING | `grep 1226461 classes/paladin.lua` = no hits (`sod_paladin_variants` §7.1) — blocks P-09/P-10/P-11 |
| P-13 | Templar remaining (1226464), Sunlight (1239543), Templar stacks (1240574) | p8-wrath / shockadin APLs | MISSING | `sod_paladin_variants` §7.2-7.3 |
| P-14 | Era has **no Crusader Strike** | classic sim has no CS spell | WIRED | `nextaction.lua` `cs_known = false` path (audit MATCH) |
| P-15 | Era Hammer of Wrath execute below 20 % HP | classic APL `isExecutePhase`-style execute; HoW 24275 ranks | WIRED | `nextaction.lua:721-735` (the HoW gate: `ERA_HOW_HEALTH_PCT = 20` at `:359`) |
| P-16 | Judgement **stopattack** | classic `retribution.go` `IsUsingJudgementStopAttack`; sod `paladinCastWithMacro` StopAttack | DEGRADED | the engine emits `out.stopattack` (advisory) but no macro/UI consumes it — `nextaction_ui.lua:48-49` renders STOP, and `desks/paladin-fixes/journal.md:11` filed "Era Judgement-stopattack (macro/UI)" |
| P-17 | Prepull the primary seal (Era −1.5 s; SoD exodin −2.5 s / stack −3 s / twist −1.5 s; TBC SoC 27158r7 + Judges at 0 s) | classic + all p8 APLs + tbc-new | DEGRADED | `out.prepull_ready` + `time_to_pull_seconds` exist (`nextaction.lua:74-76`), but the **pull-timer source** is filed to `main.lua` (`desks/paladin-fixes/journal.md:11`) |
| P-18 | TBC JotC maintenance | tbc-new `default.apl.json` (prepull SoC 27158r7) | WIRED | `classes/paladin.lua:1951-1956` (JotC mini-bar, 21183) |
| P-19 | TBC **Delay Major CDs 11 s** (CS does not fire on the pull) | tbc-new `default.apl.json` | WIRED | `nextaction.lua:372` `TBC_PULL_CS_HOLD_SECONDS = 11` |
| P-20 | TBC reseal guard `autoTimeSinceLast >= .5s` | tbc-new `default.apl.json` | WIRED | `nextaction.lua:376` `TBC_RESEAL_AUTO_GUARD_SECONDS = 0.5` |
| P-21 | TBC fillers are opt-in (Exorcism/Consecration default off) | tbc-new `default.apl.json` valueVariables | WIRED | `nextaction.lua:744-760` (Exorcism > 30 mana, Consecration > 35 mana) and the FCFS fillers `:1013` / `:1054`; the Consecration AoE gate reads `target_count`, and an unknown target keeps the suggestion |
| P-22 | TBC mana-sustain governor on twisting | `docs/research/tbc_minmax.md:27` | DEGRADED | `nextaction.lua:63-65` `twist_mana_threshold` plug-in exists, but the shipped value is filed to the options pass (`desks/paladin-fixes/journal.md:11`) |
| P-23 | SoD execute burn below 10 % fight remaining (rune 429152) | sod `p4-twist.apl.json`, `p8-twist.apl.json` | WIRED | `nextaction.lua:383` `SOD_EXECUTE_FIGHT_PCT = 10`, used `:1101` |
| P-24 | Forever **Echo of Command / Echo of Righteousness** aura model (recast-on-Echo-inactive, not swing timing) | forever `twist_of_light_test.go`, `twist_of_light.apl.json` | MISSING | no Echo auras, no Echo-driven reseal (`bench/paladin_rotation_audit_2026-10-19.md` §Forever CONFLICT) |
| P-25 | Forever **Holy Strike** (10333r8) as the sim's #2 button | forever `twist_of_light.apl.json` | MISSING | no sourced id; the discipline is documented at `nextaction.lua:127` ("Holy Strike has no sourced spell id and is not probed") |
| P-26 | Forever HoW instant-cast / 0.2 s post-auto window | forever `twist_of_light.apl.json` | WIRED | `nextaction.lua` `how_cast_seconds` + `FOREVER_HOW_AUTO_WINDOW = 0.2` (`desks/paladin-fixes/journal.md:9`) |
| P-27 | Forever Exorcism is a generic filler (no Undead/Demon gate) | forever `twist_of_light.apl.json` | WIRED | creature-gate bypass (`desks/paladin-fixes/journal.md:9`) |
| P-28 | Wrath FCFS order `cs > judge > ds > cons > exo > hw` | `docs/research/rotations_wrath.md:64-70` (guide-derived; **no wowsims/wotlk in scope**) | WIRED | `nextaction.lua:946` `FCFS_ORDER_WRATH` |
| P-29 | Wrath 2pc-T10 resets surface as DS readiness | `docs/research/rotations_wrath.md:76-77` | DEGRADED | deferred explicit detection (`nextaction.lua:859-869`); documented |
| P-30 | SoD `strictSequence` twist (cast + wait the swing out) | sod `p8-twist.apl.json` | DEGRADED | `out.hard_wait` is advisory; the render is filed to `nextaction_ui` (`desks/paladin-fixes/journal.md:11`) |
| P-31 | Retail is inert | no Retail sim in scope | WIRED | `nextaction.lua:446` (the evaluate short-circuit) + `:1171` (the FCFS never runs) |

#### (B) Drill inventory

| Drill | Skill graded | Covers | Does NOT cover |
|---|---|---|---|
| `paladin_twist` (`practice.lua:1798`) | rotation-window **timing** | the 0.4 s / 0.2 s twist window | priority order, mana, cooldown usage, opener |
| `paladin_aw_combo` (`practice.lua:1969`) | cooldown **burst-window usage** | AW opens; haste pieces must land inside the 3 s window (`H.COMBO_DEFAULTS.window = 3`, `practice.lua:1846`) | priority order, opener, situational decisions |

Skill coverage: timing-window ✅, burst-window ✅, **priority order ❌, transition/opener ❌,
situational ❌**.

#### (C) Target DRILL set — paladin (2 → 5)

**D-P1 — `paladin_fcfs_priority` — "the FCFS order"**
- **kind:** NEW `rotation_order` (see §4.1) · **class:** PALADIN
- **Skill category:** **rotation priority order**
- **What it grades:** at each decision point the drill names the highest-priority
  action the rotation wants; the player must press that action. A wrong pick is a
  mis-order, not a late pick.
- **State / inputs:** the drill holds a frozen copy of the family's FCFS table and a
  live "what is due" set; the player answers with an action key (the same key space
  the guide emits: `soc`, `sob`, `twist`, `cs`, `judge`, `ds`, `cons`, `exo`, `how`,
  `hw`).
- **Grade bands [DESIGN]:** S = 100 % correct picks · A = ≤1 mis-pick in 10 decisions ·
  B = ≤2 · C = ≤3 · D = ≤5 · F = >5 mis-picks. (The bands mirror the decision-per-GCD
  granularity of the sim APLs: one decision per GCD, so a 10-decision sample is one
  GCD chain.)
- **UI needs:** one panel icon per action in the family's table + a keybind per action;
  the result popup shows the mis-picks in order.
- **Class seam / target:** `nextaction.lua:946-961` (the four FCFS tables +
  `FCFS_ORDER_SOD_STACK/SHOCK/WRATH`) and `classes/paladin.lua:3014`
  (`ST.PALADIN.gather_guide_inputs`) to feed the "due" set; registration in
  `practice.lua` next to `:1969`.
- **Citation:** order tables from the p8 APLs — exodin `bench/sod_paladin_variants_2026-10-19.md` §2;
  wrath `docs/research/rotations_wrath.md:64-70` (guide-derived, not sim).

**D-P2 — `paladin_prepull` — "the opener"**
- **kind:** NEW `transition` (see §4.1) · **class:** PALADIN
- **Skill category:** **transition / opener**
- **What it grades:** the seal that must be up before the pull, cast inside the
  prepull lead, and the opener sequence that follows it.
- **State / inputs:** `seal` (which seal is up), `time_to_pull_seconds` (the drill
  supplies a synthetic countdown), the seal that is due.
- **Grade bands [DESIGN]:** S = the due seal was up **and** cast inside the lead ·
  A = up, ≤ 0.5 s late · B = ≤ 1.0 s late · C = ≤ 1.5 s late · D = up only after the
  pull · F = the wrong seal / no seal.
- **UI needs:** a seal icon per family seal + a countdown label; one extra keybind.
- **Class seam / target:** `nextaction.lua` `out.prepull_ready` + the
  `PREPULL_SEAL_LEAD_SECONDS` constant; `nextaction_ui.lua:50-51` already defines the
  PULL overlay; `classes/paladin.lua:3014` for the seal state.
- **Citation:** classic APL prepulls the primary seal at **−1.5 s**;
  sod `p8-exodin` **−2.5 s**, `p8-twist`/`p8-shockadin-*`/`p8-wrath` **−1.5 s**,
  `p8-stack` **−3 s** (SoC at −3 s, SoM at −1.5 s); tbc-new prepulls SoC 27158r7 +
  Judges at 0 s — all in `bench/sod_paladin_variants_2026-10-19.md` §1-§6 and
  `bench/paladin_rotation_audit_2026-10-19.md` §Era.

**D-P3 — `paladin_judge_fit` — "the Judgement decision"**
- **kind:** NEW `situational` (see §4.1) · **class:** PALADIN
- **Skill category:** **situational decision**
- **What it grades:** whether Judgement is worth spending the GCD on, given the seal
  state and the time to the next swing. It is the decision the sim gates hardest.
- **State / inputs:** `seal` (SoB/SoC/none), `gcd_remaining`, `swing_remaining`,
  `mana_pct`, `target_health_pct`, `fight_remaining_pct`.
- **Grade bands [DESIGN]:** S = the drill's due action matches the guide's verdict and
  was pressed inside the window · A/B/C = the verdict matched but the press was late by
  ≤1 GCD · D = the verdict matched but late by >1 GCD · F = the wrong verdict (judged
  when the seal is down / the fit fails / the fight is over).
- **UI needs:** the existing judgement cue slot (the guide frame already paints it) plus
  a "verdict" line in the result popup.
- **Class seam / target:** `nextaction.lua:801-812` (the fit model:
  `TBC_JUDGE_SEAL_GCDS = 3` at `:351`, Era 2 at `:358`, Forever 1 at `:365`),
  `nextaction.lua:791-792` (the JotC priority), `classes/paladin.lua:3014`.
- **Citation:** tbc-new `default.apl.json` judges only on SoB with the GCD ready and
  `autoTimeSinceLast <= .8s`; the classic APL reseals when `currentSealRemainingTime < 1`
  — `bench/paladin_rotation_audit_2026-10-19.md` §TBC "GAP (low) — Judge gate shape".

#### (D) Target SCENARIO — paladin

**S-P — `paladin_rotation` — "the Ret rotation, end to end"**
- **kind:** NEW `rotation_run` (see §4.1) · **class:** PALADIN
- **Rotation table source:** the family's FCFS priority list, taken from the sim APLs:
  SoD exodin `p8-exodin.apl.json` → `nextaction.lua:947`;
  Wrath `docs/research/rotations_wrath.md:64-70` → `nextaction.lua:946`;
  Era `classic basic_ret.apl.json` (seal freshness + twist + CS + HoW execute);
  TBC `tbc-new default.apl.json` (the 11 s major-CD delay, the .5 s reseal guard, the
  JotC line-up).
- **Tick model:** swing clock (weapon speed, default **3.5 s** — the shipped practice
  default, `practice.lua:232`) + GCD clock (**1.5 s** default, `practice.lua:233`;
  haste-shortened via `st.practice.apply_haste`, `practice.lua:332`) + mana (no regen
  model exists → the scenario runs a **mana budget** rather than a regen clock; see
  §4.4) + the twist window (0.4 s / 0.2 s SoD).
- **Expected-sequence comparison:** the scenario calls
  `st.nextaction.evaluate(inputs, out)` (`nextaction.lua:440`) at every GCD tick with
  the simulated state; `out.action` (+ `out.hold` / `out.hold_text` /
  `out.stopattack` / `out.hard_wait`) is the **expected** action. The player's cast is
  reported through `H.scenario_event` and compared against `out.action`:
  match = correct decision; a different action = mis-pick (recorded with the expected
  action so the report can show "you pressed X, the rotation wanted Y"); a cast when
  `out.hold` was true = an illegal cast (the twist window / the RIDE hold was open).
- **Grade bands [DESIGN]:** S = 0 mis-picks and 0 illegal casts over the run ·
  A = 1 mis-pick · B = 2 · C = 3 · D = 4-5 · F = >5 mis-picks or any illegal cast
  inside a twist window. Grading is per-decision, mirroring the APL's one-decision-per-
  GCD granularity; the run length is fixed **[DESIGN] 10 GCD chains** so every class's
  scenario produces a comparable number of decisions.
- **UI needs:** the panel icon set of the running family's FCFS table (the guide frame
  already owns those icons — `ST.PALADIN.guide.slots`), a per-decision timeline, and a
  run summary listing the mis-picks with the expected action.
- **Class seam / target:** driver `st.nextaction.evaluate` (`nextaction.lua:440`);
  input source `ST.PALADIN.gather_guide_inputs` (`classes/paladin.lua:3014`);
  the paladin drill branch in `practice_ui.lua` (sibling lane owns the file — the
  scenario needs the same panel/score plumbing the hunter/shaman drills already use,
  `bench/hunter_practice_designer_2026-10-19.md` §"Files changed").
- **Citations:** the per-client APL list above; the existing twist drill's sim
  (`st.practice.new_sim`, `practice.lua:223`) supplies the fight/swing/GCD scaffolding
  the scenario reuses.

---

### 2.2 WARRIOR

#### (A) Feature checklist

| # | Feature the sim implies | Sim source | Verdict | Anchor / what is missing |
|---|---|---|---|---|
| W-01 | Bloodthirst 30 rage / 6 s CD | classic `bloodthirst.go` (`Cost: 30`, `Duration: 6s`); sod `bloodthirst.go`; tbc-new + forever APLs | WIRED | `classes/warrior.lua:966` `WARRIOR_COMPOSITE_BT_COST = 30`; the cooldown reader rides the client |
| W-02 | Whirlwind 25 rage / 10 s CD | classic `whirlwind.go`; tbc-new fury APL `1680 tag1`; sod DW APL `1680`; forever fury APL `1680` | WIRED | `classes/warrior.lua:967` `WARRIOR_COMPOSITE_WW_COST = 25` |
| W-03 | `ww_ids` must hold only the real WW ranks | all four sims register WW as **1680** | WIRED | the G1 bug (OP R3/R4 11584/11585, Rend 25208, Battle Shout 47436, Tiger's Fury 6794, Growl 6795, creature spell 47435) was closed — `desks/warrior-rotfix/journal.md:9` |
| W-04 | WW only when BT is > 1.5 s away (WW-delay gate) | all sim APLs gate WW on `BT > 1.5s` | WIRED | `warrior_guide.lua` WW-delay gate (`desks/warrior-rotfix/journal.md:9` item 5) |
| W-05 | Overpower: 5 s aura window, spell CD 5 s, rage 5 | classic `overpower.go` (`Duration: 5s`) | WIRED | `classes/warrior.lua:61` `WARRIOR_OVERPOWER_PROC_WINDOW = 5.0` |
| W-06 | OP **stance gate** (Berserker vs Battle) | tbc-new `ExtraCastCondition` = Berserker stance | DEGRADED | the OP rule has no stance read (`warrior_guide.lua:827-836`); stance reads exist as `inputs.stance_form` (`warrior_guide.lua:136-140`) but the per-family stance **index map is UNCONFIRMED** — `desks/warrior-rotfix/journal.md:25` filed "stance index map" |
| W-07 | Execute below 20 % HP | classic + sod + tbc-new APLs `isExecutePhase E20` | WIRED | `warrior_guide.lua:355` `EXECUTE_PCT_DEFAULT = 20` |
| W-08 | Execute **drains all rage** (TBC `925 + 21*extraRage`; SoD drains all) | tbc-new `execute.go`; sod `execute.go` | DEGRADED | the rule picks Execute (`warrior_guide.lua:837-863`) but no rage-drain is modelled (no drain input) |
| W-09 | Heroic Strike / Cleave need **rage ≥ 40** | Era/TBC-fury/DW-arms/Forever APLs | WIRED | `desks/warrior-rotfix/journal.md:9` item 4 (Era 30→40, TBC 50→40); Wrath floor 50 and SoD floor 60 are **HELD** as design decisions (no sim source) |
| W-10 | Slam: 1.5 s cast, resets the swing, gated on Blood Surge | classic `slam.go` (11605, `StopMeleeUntil(...,true)`) | WIRED | `warrior_guide.lua:864-875` (rule 3) |
| W-11 | Blood Surge aura: Wrath 46916 **and SoD 413399** | both SoD APLs gate Slam 11605 on 413399 | WIRED | `desks/warrior-rotfix/journal.md:9` item 3 |
| W-12 | HS ranks: TBC 29707 (R9) / 30324 (R10) | tbc-new fury + arms APLs cast 29707 | WIRED | `desks/warrior-rotfix/journal.md:9` item 2 |
| W-13 | Cleave 20569 r5 (Era) | classic APL `20569 tag1 rank 5` | WIRED | `desks/warrior-rotfix/journal.md:9` |
| W-14 | **Sunder upkeep**: stacks < 5, refresh ≤ 10 s | tbc-new + forever APL single-target groups | WIRED | `warrior_guide.lua:400-401` `SUNDER_STACKS_MAX = 5`, `SUNDER_REFRESH_DEFAULT = 10`; rule S at `:880-887` |
| W-15 | **Rend upkeep** (SoD 11574 + rune 412507; Forever 11574 toggle ≤ 3 s) | sod DW APLs; forever APL | DEGRADED | the pure rule exists (`warrior_guide.lua:393` `REND_REFRESH_DEFAULT = 3`, rule R `:888-894`) but the **Forever toggle is not in-tree** (the rule is dormant there) — `desks/warrior-rotfix/journal.md:25` filed "Forever Rend toggle + options" |
| W-16 | **Hamstring weave** at rage > 80 (Era 7373) | classic APL (Era 7373 rage > 80) | WIRED | `warrior_guide.lua:502` `HAMSTRING_RAGE_THRESHOLD_ERA = 80`; rule W. **CORRECTED 2026-10-20** (desk `corpus-corrections`): this row used to read "(Era 7373; hidden 18499)" with the source "TBC 18499" — **18499 is Berserker Rage**, not a Hamstring, and the **TBC Hamstring is 25212** (`wowsims/classic sim/warrior/berserker_rage.go:14` names 18499 Berserker Rage; the tbc-new fury APL's i=19 casts 25212 = Hamstring). Evidence: `bench/warrior_apl_utility_build_2026-10-20.md` §1/§4 and `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **W1**/**W4** |
| W-17 | SoD **stance-dance OP** (11585 + aura 426969) | sod stance-dance APL group | DEGRADED | the arm exists (`desks/warrior-rotfix/journal.md:24` item 3) but the aura id **426969 is UNCONFIRMED** and the stance map is UNCONFIRMED |
| W-18 | Era core reserve window (BT/WW buffer) | the 2–3 s ground-truth window | WIRED | `classes/warrior.lua:258` `ERA_CORE_RESERVE_WINDOW = 2.5` (midpoint); TBC default 1.5 (`warrior_guide.lua:378`) |
| W-19 | Victory Rush (Forever) | forever `victory_rush.go` | DEGRADED | reuses the execute slot (`warrior_guide.lua:838-841` `inputs.victory_rush`), but **no Forever APL line exists** — operator SKIP on building a prompt (`desks/warrior-rotfix/journal.md:11` item f) |
| W-20 | Devastate (TBC DW-arms rage > 60 filler) — **the id 25212 is NOT Devastate** | tbc-new arms APL | MISSING | `desks/warrior-rotfix/journal.md:11` item (h) — filed, no action. **CORRECTED 2026-10-20** (desk `corpus-corrections`): this row used to read "Devastate **25212**" — **25212 is the TBC Hamstring**, not Devastate. The build stays filed; the Devastate row's own id is **not** sourced in the corpus (UNCONFIRMED — do not build on 25212 for it). Evidence: `bench/rotation_gap_vs_apl_2026-10-20.md` §0.3 ("25212 is Hamstring in TBC") and §0.0 **W4**; `bench/warrior_apl_utility_build_2026-10-20.md` §1 |
| W-21 | Sunder/Rend/Hamstring **HUD mirror** | — | DEGRADED | the guide slots shipped (TBC/Forever sunder, SoD rend, Era hamstring) but the HUD row is deferred (`desks/warrior-rotfix/journal.md:38-39`) |

#### (B) Drill inventory

| Drill | Skill graded | Covers | Does NOT cover |
|---|---|---|---|
| `warrior_execute` (`practice.lua:2214`) | **situational decision** (execute-phase entry) | the rage pooled at the 20 % crossing (`H.EXECUTE_DEFAULTS.threshold = 0.20`, `entry_rage = 100`, `practice.lua:2164`); the phase tracker is driven by the live feed in `classes/warrior.lua:1208-1290` and rendered by the execute report screen (`practice_ui.lua:6056-6155`) | priority order, the core rotation (BT/WW/Slam), upkeep, opener |

> **Honest note for the build lane:** the warrior's registered `warrior_execute`
> scenario is **not** the scenario the warrior's practice panel starts — the panel
> runs the SHARED twist session (`practice_ui.lua:636` `WARRIOR = "paladin_twist"`),
> and the execute drill runs as a live-feed report over real combat rather than as a
> harness session. So the warrior's progression mastery row today is the **twist**
> drill, not the execute one. §4.2 covers the map change that fixes this shape for
> every class.

Skill coverage: situational ✅, **priority order ❌, cooldown/rotation-window ❌,
transition/opener ❌**.

> Note for the build lane: the drill's own bands (`H.EXECUTE_ENTRY_BANDS`,
> `practice.lua:2166-2173`) grade a **fraction of the pooled-rage target**, i.e. a
> design metric. The 20 % threshold and the 100-rage entry target are the sim-aligned
> parts (`isExecutePhase E20`; 100 is the classic rage cap).

#### (C) Target DRILL set — warrior (1 → 4)

**D-W1 — `warrior_core_order` — "the core rotation"**
- **kind:** NEW `rotation_order` · **class:** WARRIOR
- **Skill category:** **rotation priority order**
- **What it grades:** the order of the core spenders — Overpower window → Execute
  (below 20 %, when the core's rage is reserved) → Bloodsurge Slam → Bloodthirst →
  Whirlwind → the Heroic Strike / Cleave dump. The player must pick the same action
  the engine wants, and must **not** spend the core's rage while the core is about to
  come up (the reserve window).
- **State / inputs:** `rage`, `bt_remaining`, `ww_remaining`, `overpower_remaining`,
  `has_bloodsurge`, `target_health_pct`, `hs_queued`, `core_reserve_window`.
- **Grade bands [DESIGN]:** S = 100 % correct picks, 0 reserve violations ·
  A = ≤1 mis-pick · B = ≤2 · C = ≤3 · D = ≤5 · F = >5 mis-picks, or any spend that
  starved a core that was inside the reserve window.
- **UI needs:** one panel icon per core action (op / execute / slam / bt / ww / hs) with
  a keybind each; the result popup lists the mis-picks.
- **Class seam / target:** `warrior_guide.lua:762` (`st.warrior_guide.evaluate`) +
  `classes/warrior.lua:2779` (`ST.WARRIOR.gather_guide_inputs`); registration beside
  `practice.lua:2214`.
- **Citation:** the order as the engine already encodes it (rule 1 OP, rule 2 Execute,
  rule 3 Slam, rule 5 BT, rule 6 WW, rule 7 HS dump — `warrior_guide.lua:827-1000`),
  which the audit matched to the sim APLs: OP-first on Era (`M8`),
  Execute at E20 (`M4`), BT 30/6 s (`M1`), WW 25/10 s (`M2`).

**D-W2 — `warrior_ww_delay` — "the core window"**
- **kind:** NEW `rotation_window` (see §4.1) · **class:** WARRIOR
- **Skill category:** **cooldown / rotation-window usage**
- **What it grades:** the gap discipline between the two core cooldowns — Whirlwind
  must not be spent while Bloodthirst is inside **1.5 s** of coming up, and vice versa.
- **State / inputs:** `bt_remaining`, `ww_remaining`, `rage`, `ww_cost`, `bt_cost`.
- **Grade bands [DESIGN]** on the **distance from the blocked window** (the drill's
  metric is the margin by which the player stayed clear):
  S = the WW press happened at least **1.0 s** before BT came up · A = ≥ 0.5 s ·
  B = ≥ 0.2 s · C = ≥ 0 s (inside the window) · D = the press starved BT by < 1 GCD ·
  F = the press starved BT by more than a GCD / the player pressed with the rage for
  neither.
- **UI needs:** a "core next" label (BT or WW, with the countdown) beside the two
  icons; no new frame needed.
- **Class seam / target:** `warrior_guide.lua` WW-delay gate (the engine's
  `bt_remaining > 0` condition, rule 6) + `classes/warrior.lua:2779`.
- **Citation:** all four sim APLs gate WW on **BT > 1.5 s** and the arms DW APL gates
  Execute on **WW > 1.5 s** (`desks/warrior-rotfix/journal.md:18`); tbc-new
  `ExtraCastCondition` = Berserker stance.

**D-W3 — `warrior_sunder_upkeep` — "the debuff upkeep"**
- **kind:** NEW `situational` · **class:** WARRIOR
- **Skill category:** **situational decision** (maintenance vs damage priority)
- **What it grades:** dropping Sunder below the stack cap and refreshing it inside the
  final window, while still yielding the window to a proc, Execute range and a queued
  ride.
- **State / inputs:** `sunder_stacks`, `sunder_remaining`, `sunder_duration`,
  `target_health_pct`, `overpower_remaining`, `hs_queued`.
- **Grade bands [DESIGN]:** S = re-stacked at **5 stacks** before the refresh window ·
  A = 4 stacks · B = 3 · C = 2 · D = 1 · F = let the debuff expire. A press that the
  rotation should have yielded (proc / Execute / ride open) grades F for the drill.
- **UI needs:** one Sunder icon + a stack pip row (the guide slot exists; the HUD
  mirror is deferred).
- **Class seam / target:** `warrior_guide.lua:400-401` + `:436-441`
  (`should_refresh_sunder`) + `:880-887` (rule S); `classes/warrior.lua:3045-3048`
  (the gather's target scan).
- **Citation:** tbc-new + forever APL single-target Sunder groups — stacks < 5,
  refresh ≤ 10 s (`desks/warrior-rotfix/journal.md:18`).

**D-W4 — `warrior_execute_burn` — "the execute burn"**
- **kind:** NEW `transition` · **class:** WARRIOR
- **Skill category:** **transition / opener** (the fight's phase change)
- **What it grades:** the transition into the execute phase — the rage dump and the
  repeated Execute presses below the threshold, with the core deliberately released.
- **State / inputs:** `target_health_pct` (or a synthetic HP ladder fed by the drill),
  `rage`, `execute_remaining`, `execute_pct`.
- **Grade bands [DESIGN]:** S = the phase was entered with a full pool **and** the
  first Execute landed within one GCD of the crossing · A = one GCD late ·
  B = two · C = the pool was short but the burn was clean · D = the pool was short and
  the burn was late · F = the core was spent during the phase (no burn) or Execute was
  pressed above the threshold.
- **UI needs:** the execute-phase report already exists
  (`practice_ui.lua:6033-6147` `build_warrior_execute_report` / `render_warrior_execute_report`);
  the drill needs one extra row for the phase-entry decision.
- **Class seam / target:** `classes/warrior.lua:1208-1290` (the live execute log +
  the practice-armed glow) + `warrior_guide.lua:837-863` (rule 2).
- **Citation:** `isExecutePhase E20` on the Era/sod/tbc-new APLs; SoD Execute also fires
  on a Sudden-Death aura (sod `execute.go`).

#### (D) Target SCENARIO — warrior

**S-W — `warrior_rotation` — "the Arms/Fury rotation, end to end"**
- **kind:** NEW `rotation_run` · **class:** WARRIOR
- **Rotation table source:** the family's priority from the sim APLs —
  Era `classic ui/warrior/apls/dps_reck.apl.json` (OP via `autocastOtherCooldowns`
  before Execute, Slam never cast without Blood Surge),
  SoD `sod ui/warrior/apls/phase_6_dw.apl.json` / `phase_6_2h.apl.json`,
  TBC `tbc-new ui/specs/warrior/dps/apls/fury.apl.json` + `arms.apl.json`,
  Forever `forever ui/specs/warrior/dps/apls/fury.apl.json` + `arms.apl.json`.
  The engine's rule order (`warrior_guide.lua:827-1000`) is the compiled table.
- **Tick model:** swing clock (weapon speed; **3.5 s** default — `practice.lua:232`) +
  GCD clock (**1.5 s** — `practice.lua:233`) + **rage**: the scenario runs a rage
  ledger that spends the cost of the pressed action and regenerates on the classic
  model; the audited rage facts are BT 30 / WW 25 / OP 5 (`classes/warrior.lua:966-967`,
  `warrior_guide.lua` OP cost) — the **regeneration rate itself is not in any in-scope
  sim source** and must be marked UNCONFIRMED (see §5) rather than invented.
- **Expected-sequence comparison:** `st.warrior_guide.evaluate(inputs, out)`
  (`warrior_guide.lua:762`) at every GCD tick → `out.action` is the expected action;
  `out.hold`/`out.hold_text` ("RIDE" on a queued HS/Cleave, "CANCEL" when a queued
  spend must be killed for the Execute) is the expected **hold**. The player's cast
  arrives via `H.scenario_event` and is compared against `out.action`; a press during a
  hold window is an illegal cast.
- **Grade bands [DESIGN]:** S = 0 mis-picks, 0 illegal casts · A = 1 · B = 2 · C = 3 ·
  D = 4-5 · F = >5 or any illegal cast.
- **UI needs:** the six core icons (op / execute / slam / hs / bt / ww) with keybinds,
  a per-decision timeline, and a run summary.
- **Class seam / target:** driver `st.warrior_guide.evaluate` (`warrior_guide.lua:762`);
  inputs `ST.WARRIOR.gather_guide_inputs` (`classes/warrior.lua:2779`); the warrior
  branch in `practice_ui.lua` (sibling lane).
- **Citations:** the APL list above; `bench/warrior_rotation_audit_2026-10-19.md` §1
  (source inventory) + §2 (Era rows M1-M8).

---

### 2.3 HUNTER

#### (A) Feature checklist

| # | Feature the sim implies | Sim source | Verdict | Anchor / what is missing |
|---|---|---|---|---|
| H-01 | Kill Shot at ≤ 20 % target HP | wowsims/wotlk hunter kit + `docs/research/rotations_wrath.md:5-38` | WIRED | `hunter_guide.lua:705-710` (rule W1, `target_hp_frac` ≤ 0.20); spec at `:251-253` |
| H-02 | Chimera Shot (SoD 409433, 6 s CD; Wrath 53209, 10 s CD) | sod `sim/hunter/chimera_shot.go`; wotlk `chimera_shot.go` | WIRED | `hunter_guide.lua:723-728` (W2) and `:762-768` (rule 5b) |
| H-03 | Chimera must not be naked (Serpent up) | sod `p3_ranged_mm.apl.json` / `p7_weave.apl.json`; wotlk `chimera_shot.go` (Serpent rollover + 53353 proc) | DEGRADED | the engine gate exists (`serpent_known` / `serpent_active`, `hunter_guide.lua:206-213`, `:261-262`) but the **gather writes nil** — `classes/hunter.lua:2252-2253` — (the target-debuff source needs compat work — filed) |
| H-04 | Serpent Sting upkeep itself | sod + wotlk APLs (`not dotIsActive 13554 → cast`) | DEGRADED | **no Serpent slot in any family set** (`hunter_guide.lua:49-51` "Serpent Sting is never prompted"); the Wrath set is full at 6/6 |
| H-05 | Lock and Load (Wrath 56344, 22 s ICD, 2 stacks; SoD 415413) | wotlk `talents.go applyLockAndLoad`; sod `runes.go applyLockAndLoad` | DEGRADED | the engine arms exist (W-LnL `hunter_guide.lua:254-258`, SoD-LnL `:294-297`) but `lnl_ready` is written **nil** by the gather — `classes/hunter.lua:2251` — no confirmed aura source |
| H-06 | Explosive Shot downrank pair **60053 R4 / 60052 R3** | wowsims/wotlk `explosive_shot.go` | WIRED | `classes/hunter.lua:144-146` `explosive_shot_ids = { 53301, 60052, 60053 }` — the pair landed after the audit row; the audit's "our table names only the base id" note is **superseded**. **CORRECTED 2026-10-20** (desk `corpus-corrections`): the *rotation table's* WotLK `explosive` row carried 53301 alone — the SV APL casts **60053/60052** — and the hunter APL build lane re-cut that row to 60053. Evidence: `bench/hunter_apl_utility_build_2026-10-20.md` §3; `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **H2** |
| H-07 | Steady Shot rank (TBC sim casts rank **34120**) | tbc-new `steady_shot.go BySpellID(34120)` | DEGRADED | we resolve the **highest known rank** (`classes/hunter.lua` rank resolution); audit records the risk at LOW, no id change on the audit alone. **CORRECTED 2026-10-20** (desk `corpus-corrections`): the TBC *rotation* row carried **56641**, which **does not exist on the TBC client** (56641 is the WotLK Steady Shot rank-1) — the hunter APL build lane re-cut it to 34120. And the **Forever client has no Steady Shot at all** (the spell arrived in 2.3), so its row was removed. Evidence: `bench/hunter_apl_utility_build_2026-10-20.md` §3, `bench/hunter_utility_live_2026-10-20.md` §1; `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **H3**/**H4** |
| H-08 | Steady as the demoted filler; Aimed instant on Wrath; Arcane dropped on SV | wowsims/wotlk kit | WIRED | `hunter_guide.lua:733-747` (rules W4-W6), `:737-742` (Arcane suppressed when Explosive is known) |
| H-09 | TBC BM priority: Kill Command first, then BW, then RF | tbc-new `default.apl.json` (KC 34026 position 1) | WIRED | `hunter_guide.lua:753-761` (rules 3-5) |
| H-10 | TBC **Arcane Shot 27019** as a core filler | tbc-new `default.apl.json` (`Use Arcane Shot` + several Arcane-gated entries) | DEGRADED | the engine arm 5c exists (`hunter_guide.lua:796-797`) but it is **dormant** behind `TBC_ARCANE_ENABLED = false` (`hunter_guide.lua:479`) — the base set is full 6/6 and there is no arcane slot. The id table already carries the sim's 27019 (`classes/hunter.lua:162-164`) |
| H-11 | TBC mana group (Viper 34074 / Hawk 27044 / mana potion) | tbc-new `default.apl.json` `Mana management` group | MISSING | no mana input in the gather; the guide keeps prompting Steady into OOM |
| H-12 | TBC **melee weave** is the sim default (wait at melee 400 ms, buffer `min(0.5 s, 25% swing)`, `Next cycle gap after steady`) | tbc-new `default.apl.json` valueVariables | MISSING | the engine has no weave/move/wait cue; `weave_band` exists but **no rule reads it** (`hunter_guide.lua:221-235`) |
| H-13 | TBC prepull (Hawk 27044 at −20 s; Steady at 0.5 s) | tbc-new `default.apl.json` | MISSING | no prepull/mark surface |
| H-14 | Era: Serpent / Arcane / traps / Volley / Mongoose / Wing Clip upkeep | classic `sim/hunter/hunter.go` Initialize | MISSING | the Era set is aimed/raptor/multi only (`hunter_guide.lua:27-33`) — the guide is silent on all of it |
| H-15 | Era melee-weave movement tech | classic `sim/hunter/hunter.go` (AutoSwingMelee, Mongoose/Wing) | MISSING | rule 7 only RIDE-surfaces an already-queued Raptor |
| H-16 | Wrath **Black Arrow / trap tier** + `timeToTrapWeaveMs: 2000` | wowsims/wotlk `presets.ts` | MISSING | six slots are full; the LnL source itself is never prompted (H-05) |
| H-17 | Wrath **Readiness 23989** as a rotation event (resets the whole kit) | wowsims/wotlk `talents.go registerReadinessCD` | DEGRADED | the RF double-window helper exists (`classes/hunter.lua:816` `get_readiness_window`) but the **guide models no double-cooldown window** — no readiness input reaches the rule matrix |
| H-18 | Wrath **Improved Steady Shot 53220** window | wowsims/wotlk `steady_shot.go` | MISSING | no proc/counter input; the ISS window is invisible |
| H-19 | Wrath **Sniper Training 53304** stationary buff | wowsims/wotlk `talents.go applySniperTraining` | MISSING | no stationary/movement input (positioning aid, not rotation) |
| H-20 | Forever **SniperShot** ids 1310687 / 1310785 / 1310786 | forever `spell_data_auto_gen.go` | DEGRADED | the table ships **empty** by design (`classes/hunter.lua:194-195`); the engine arm F2 exists (`hunter_guide.lua:311-318`) but the ids are CLIENT-UNCONFIRMED |
| H-21 | Forever **Summon Hawk** ids 1293241 / 1293525 / 1293526 / 1293527 (+ triggers 1293248 / 1312639) | forever `spell_data_auto_gen.go` | DEGRADED | as H-20 — the table is empty by design (`classes/hunter.lua:187-188`) |
| H-22 | Forever **hawk count** source (EffectN(3) count, round-robin replacement) | forever `summon_hawk.go` | MISSING | `inputs.hawk_active_count` is written nil (`classes/hunter.lua:2222`) — rule F1 is dormant by construction |
| H-23 | Forever **Multi-Shot 2643** in the default APL | forever `default.apl.json` (`Use Multi-Shot=true`) | DEGRADED | deliberately omitted (`hunter_guide.lua:75-76`) — the sharpest Forever conflict |
| H-24 | Forever **HHA sequence** (2× Hawk 1293527 + Arcane 14287, shared cooldown) | forever `default.apl.json` | MISSING | hawk/sniper are prompted independently; no sequence state |
| H-25 | Forever Sniper buff extends Auto range (42–45 yd) | forever `TestSniperShotExtendsAutoShotRange` | DEGRADED | rule 2b HOLDs on `target_in_range == 0` (`hunter_guide.lua:241-247`); the bypass input `sniper_range_buff_active` is written nil (`classes/hunter.lua:2254`) |
| H-26 | No Bloodlust/Heroism suppression on the weave | no fetched APL models a lust branch | WIRED (by operator order, H2 CUT) | `hunter_guide.lua:337-347` |
| H-27 | TBC **Arcane rank conflict** (WA 14287 vs sim 27019) | tbc-new APL vs the TBC WA pack | WIRED (sim wins) | `bench/hunter_wa_map_2026-10-19.md` §4 — 14287 stays out by design |
| H-28 | Retail is inert | no Retail sim | WIRED | `hunter_guide.lua` (RETAIL short-circuit) |

#### (B) Drill inventory

| Drill | Skill graded | Covers | Does NOT cover |
|---|---|---|---|
| `hunter_forced_move` (`practice.lua:2093`) | **movement / rotation-window usage** | the forced-move cadence (`H.H5_DEFAULTS = { first_delay 5, count 5, duration 2.5, gap 5.5 }`, `practice.lua:2069`) and cast legality around the windows (`H.grade_move_cast`, `practice.lua:2071-2091`) | priority order, cooldown usage, opener, clip timing of the shots themselves |

Skill coverage: movement-window ✅, **priority order ❌, cooldown/rotation-window ❌,
transition/opener ❌, situational ❌**.

#### (C) Target DRILL set — hunter (1 → 4)

**D-H1 — `hunter_shot_order` — "the shot priority"**
- **kind:** NEW `rotation_order` · **class:** HUNTER
- **Skill category:** **rotation priority order**
- **What it grades:** which shot the rotation wants next — the cooldown priority
  (Kill Shot → Chimera → Explosive → Aimed → Arcane → Steady on Wrath; Kill Command →
  Bestial Wrath → Rapid Fire → the weave on TBC; Chimera → Aimed → Multi on Era-SoD).
- **State / inputs:** the family's known-spell flags + cooldowns + the live clip
  state (`aimed_cast_seconds`, `multi_cast_seconds`, `steady_cast_seconds`,
  `latency`, `synced_duration`).
- **Grade bands [DESIGN]:** S = 100 % correct picks · A = ≤1 mis-pick in 10 ·
  B = ≤2 · C = ≤3 · D = ≤5 · F = >5.
- **UI needs:** one icon per action in the running family's set (the guide frame owns
  them) + a keybind each.
- **Class seam / target:** `st.hunter_guide.evaluate` (`hunter_guide.lua:651`) +
  `ST.HUNTER.gather_guide_inputs` (`classes/hunter.lua:1963`).
- **Citation:** the rule order as written in `hunter_guide.lua:237-360`; the audit
  matched it to the sim kits (Wrath six-arm priority MATCH; TBC KC #1 MATCH; SoD Chimera
  top MATCH).

**D-H2 — `hunter_weave_clip` — "the clip"**
- **kind:** NEW `rotation_window` · **class:** HUNTER
- **Skill category:** **cooldown / rotation-window usage** (the shot must fit the swing)
- **What it grades:** starting a shot that **fits** the ranged cycle — the cast plus
  the latency must land before the next Auto Shot, and the shot must not be started
  inside the hidden window.
- **State / inputs:** `synced_duration` (the live cycle), the cast seconds of the
  chosen shot, `latency`, the hidden-window bounds.
- **Grade bands [DESIGN]** on the margin (the same metric the shaman weave drill uses,
  `H.WEAVE_MARGIN_BANDS`, `practice.lua:2405-2411`): a press that clips = **F**;
  otherwise S ≤ 0.02 s of margin, A ≤ 0.05, B ≤ 0.10, C ≤ 0.20, D beyond. (The band
  values are the shipped in-tree weave bands — reuse, not a new number.)
- **UI needs:** the cast-zone widget already exists on the ranged bar
  (`bench/hunter_wa_map_2026-10-19.md` §2, the cast tick / cast zone), so the drill can
  reuse it; a "too late" marker on the zone.
- **Class seam / target:** `hunter_window.is_cast_safe` + `hidden_window` (used by
  `hunter_guide.lua:319-337`) + `classes/hunter.lua:1963`.
- **Citation:** the clip guards in every fetched APL (cast time + buffer vs
  time-to-next-auto) — audit §Cross-client "Clip-math direction MATCHES sim APL
  guards everywhere; only the constants differ".

**D-H3 — `hunter_kill_command` — "the cooldown pops"**
- **kind:** NEW `situational` · **class:** HUNTER
- **Skill category:** **situational decision** (when to spend the burst)
- **What it grades:** popping the TBC cooldowns — Kill Command first, then Bestial
  Wrath, then Rapid Fire — in that order, and **not** clipping the weave by popping
  into a shot that was already going to land.
- **State / inputs:** `kc_remaining_cd`, `bw_remaining_cd`, `rf_remaining_cd`,
  the clip state of the pending shot.
- **Grade bands [DESIGN]:** S = the three pops in order, each in the window the
  rotation allows · A/B/C = the order right, the timing late by ≤1 GCD (A), ≤2 (B),
  ≤3 (C) · D = the order right but a pop clipped a pending shot · F = a wrong order or
  a pop that clipped.
- **UI needs:** three icons (kc / bw / rf) + keybinds; the guide frame already has the
  slots (`hunter_guide.lua:22-26`).
- **Class seam / target:** `hunter_guide.lua:753-761` (rules 3-5) +
  `classes/hunter.lua:1963`.
- **Citation:** tbc-new `default.apl.json` (KC 34026 at priority position 1; BW 19574 /
  RF 3045 as on-CD pops — audit §TBC MATCH).

**D-H4 — `hunter_prepull` — "the opener"**
- **kind:** NEW `transition` · **class:** HUNTER
- **Skill category:** **transition / opener**
- **What it grades:** the pre-pull sequence — the Hawk at −20 s, the Steady at 0.5 s,
  the Serpent/mark upkeep that has to be up before the pull.
- **State / inputs:** a synthetic pull countdown, the spell known-flags, the upkeep
  state (sting / mark / aspect).
- **Grade bands [DESIGN]:** S = every due opener/upkeep landed inside its window ·
  A = ≤1 late by ≤1 s · B = ≤1 late by ≤3 s · C = ≤2 late · D = a due opener missed ·
  F = nothing pre-pulled.
- **UI needs:** a countdown label + the upkeep icons; no new frame.
- **Class seam / target:** the same `time_to_pull_seconds` shape the paladin prepull
  drill uses (`nextaction.lua:74-76`); the hunter has no such input yet — a new
  synthetic pull clock belongs to the drill, not to the guide.
- **Citation:** tbc-new `default.apl.json` (Hawk 27044 at −20 s, Steady at 0.5 s);
  forever `default.apl.json` (Aspect of the Hawk 25296 prepull) — audit §TBC GAP
  "prepull/opener", §Forever GAP.

#### (D) Target SCENARIO — hunter

**S-H — `hunter_rotation` — "the ranged rotation, end to end"**
- **kind:** NEW `rotation_run` · **class:** HUNTER
- **Rotation table source:** the family's priority from the sim APLs —
  SoD `sod ui/hunter/apls/p7_weave.apl.json` + `p3_ranged_mm.apl.json`,
  Era `classic sim/hunter/hunter.go` Initialize (Aimed/Arcane/Multi/Raptor/Mongoose/
  WingClip/traps/Volley/Serpent),
  TBC `tbc-new ui/specs/hunter/dps/apls/default.apl.json`,
  Wrath `wowsims/wotlk ui/hunter/presets.ts` + the six-arm priority,
  Forever `forever ui/specs/hunter/dps/apls/default.apl.json`.
  The engine's rule matrix (`hunter_guide.lua:237-360`) is the compiled table.
- **Tick model:** the **ranged cycle** (`synced_duration`, the live Auto Shot cycle —
  the hunter's clock is not a melee swing) + the GCD clock + the shot cast times
  (Aimed **3.0 s** Era, Multi **0.5 s**, Steady **1.5 s** TBC / **2 s** Wrath — the
  per-client fallbacks documented at `hunter_guide.lua:106-108`, `:143-148`) + the
  hidden-window bounds from `hunter_window`.
- **Expected-sequence comparison:** `st.hunter_guide.evaluate(inputs, out)`
  (`hunter_guide.lua:651`) at every GCD tick → `out.action` is the expected shot,
  `out.hold`/`out.hold_text` ("HOLD" inside the hidden window / out of range,
  "RIDE" on a queued shot) is the expected hold. The player's cast arrives via
  `H.scenario_event` and is compared against `out.action`; a press inside a hold
  window is an illegal cast (it would clip the Auto Shot).
- **Grade bands [DESIGN]:** S = 0 mis-picks, 0 illegal casts · A = 1 · B = 2 · C = 3 ·
  D = 4-5 · F = >5 or any illegal cast.
- **UI needs:** the family's shot icons with keybinds; the drill also wants the
  existing **shot analytics** (`st.practice.summarize_shots`, `practice.lua:2690`)
  extended to the scenario so the run report carries the clip rate and the mean
  latency (the competitor-gap demand recorded in `bench/competitor_gaps_2026-10-19.md`).
- **Class seam / target:** driver `st.hunter_guide.evaluate` (`hunter_guide.lua:651`);
  inputs `ST.HUNTER.gather_guide_inputs` (`classes/hunter.lua:1963`); the hunter drill
  branch in `practice_ui.lua` (sibling lane) — the hunter drill plumbing already exists
  (`classes/hunter.lua:1299-1430`, `bench/hunter_practice_designer_2026-10-19.md`).
- **Citations:** the APL list above.

---

### 2.4 ROGUE

#### (A) Feature checklist

| # | Feature the sim implies | Sim source | Verdict | Anchor / what is missing |
|---|---|---|---|---|
| R-01 | **Slice and Dice upkeep** on every client | classic `combat_sinister_strike.apl.json` (1+CP at fight ≥ 6 s); tbc-new `swords.apl.json` (10 s minimum); forever `default.apl.json` (1+CP, clip ≤ 0 s); wotlk `combat.apl.json` (≤ 1 s); sod `P5_Saber` (4+CP) | WIRED (logic) / DEGRADED (display) | rule 1b (`rogue_guide.lua:207-210`) + the per-CP durations `[9,12,15,18,21]`; **no slot exists** (the 7-slot contract is frozen) — the rotation label names it instead (`rogue_guide.lua:88-93`) |
| R-02 | Per-CP SnD durations | tbc-new/classic `slice_and_dice.go` (`[0,9,12,15,18,21]s`) | WIRED | `rogue_guide.lua:359` `SND_DURATION_BY_CP = { [1] = 9, [2] = 12, [3] = 15, [4] = 18, [5] = 21 }` (the spec header at `:40-47`) |
| R-03 | **Builder identity** (Sinister Strike / Backstab / Mutilate / Saber Slash) | classic ships separate SS and Backstab APLs; tbc-new `swords.apl.json` branches on SS 26862 / Backstab 26863 / Mutilate 34413 / Hemo 26864; sod Saber 424785 / Mutilate 399956; forever Backstab 11281 / Mutilate 1241584 / Hemo 16511 / SS 11294 | DEGRADED | `resolve_builder_entry` resolves the chain Saber Slash > Mutilate > dagger Backstab > SS; **Hemo is excluded as uncertain**, and the CP/stack/rune APL gating is filed (`bench/rogue_rotation_gaps_closed_2026-10-19.md` row F1/H12). **CORRECTED 2026-10-20** (desk `corpus-corrections`): the TBC branch used to read "SS 26864 … Hemo 26862" — the two are **swapped**; 26862 = **Sinister Strike**, 26864 = **Hemorrhage** (`bench/filed_closure_sweep_2026-10-19.md` §9-N1's wowhead redirect slugs; the rogue APL build lane's sim-sourced TBC table, `bench/rogue_apl_utility_build_2026-10-20.md` §1.1 rows 34-36) |
| R-04 | Finisher spine per family | classic APLs are Evisc-only (E-C1); tbc-new = Rupture-first (T-M2); forever = Evisc (V-M1) | WIRED | `rogue_guide.lua:282` `FINISHER_MODES` |
| R-05 | Planned-finisher CP floors (ERA 5 / TBC 5 / WRATH 4 / FOREVER 3) | forever `default.apl.json` (3+CP); wotlk `combat.apl.json` (4+CP) | WIRED | `rogue_guide.lua:292` `FINISHER_MIN_CP_BY_FAMILY` |
| R-06 | Dying-target dump floors (ERA any-CP/8 s, TBC 5CP/5 s, WRATH 4CP/4 s, FOREVER 3CP/6 s) | tbc-new `swords.apl.json` (5CP, ≤ 5 s); wotlk `combat.apl.json` (4+CP, fight ≤ 4 s) | WIRED | `rogue_guide.lua:322` `DUMP_MIN_CP_BY_FAMILY` |
| R-07 | Pool lines (TBC single **71**; Forever **75** cap-danger; ERA/WRATH 65/85) | tbc-new `swords.apl.json` valueVariables (≥ 71); forever `default.apl.json` (≥ 75) | WIRED | `rogue_guide.lua:271` `POOL_BANDS` |
| R-08 | Expose Armor windows (ERA **3 s**; TBC imminent **6 s** + **15 s** minimum; FOREVER **16 s** lockout) | tbc-new `swords.apl.json`; forever `default.apl.json` | WIRED | `rogue_guide.lua:367` `EA_REFRESH_BY_FAMILY`; the TBC wait/release is rule 1a (`rogue_guide.lua:201-206`) |
| R-09 | Forever **EA finisher lockout** | forever `default.apl.json` ("Expose — Prevent Other Finishers") | DEGRADED | rule order puts expose first when due (`rogue_guide.lua:197`), but the explicit lockout on Rupture/Evisc/Cold Blood is filed (`bench/rogue_rotation_gaps_closed_2026-10-19.md` follow-up 4) |
| R-10 | Rupture recast-when-missing (TBC/Forever) vs a 4 s window (ERA/WRATH) | tbc-new `swords.apl.json` (`not dotIsActive`) | WIRED | `rogue_guide.lua:302` `RUPTURE_REFRESH_BY_FAMILY` |
| R-11 | Rupture per-CP durations (1CP 8 s … 5CP 16 s, +glyph 20 s) | wotlk `rupture.go` (`RuptureTicks = 3+CP`, 2 s ticks) | DEGRADED | the 1CP and 5CP rows ship as DATA (`rogue_guide.lua:337` `RUPTURE_DURATION_BY_CP = { [1] = 8, [5] = 16 }`) but **no sim rule consumes them**; 2-4CP are UNCONFIRMED |
| R-12 | Thistle Tea lines (ERA 29 / TBC 30 / WRATH 40 / FOREVER 15 (+25 Eureka) / SOD 10, 40 at ≤ 15 s) | classic `sweaty` APL (≤ 29); tbc-new (≤ 30); forever (≤ 15); sod `P5_Saber` | WIRED / DEGRADED | `rogue_guide.lua:404` `TEA_ENERGY_MAX_BY_FAMILY`; the Eureka-25 line and the SoD 10/40 line are filed (follow-ups 6) |
| R-13 | Adrenaline Rush energy gates (ERA < 59 + tick < 1; TBC ≤ 40; WRATH ≤ 50; FOREVER ≤ 50 with SnD) | classic/tbc-new/wotlk/forever APLs | WIRED (slot-less) | `rogue_guide.lua:234-236` (rule 5b) + `ar_verdict`; no icon slot (follow-up 1) |
| R-14 | Blade Flurry behind SnD + EA | tbc-new `swords.apl.json`; forever `default.apl.json` | WIRED (slot-less) | rule 5c (`rogue_guide.lua:237-239`) |
| R-15 | Cold Blood 14177 (TBC with SnD; FOREVER at 5 CP) | tbc-new + forever APLs | WIRED (slot-less) | rule 5d (`rogue_guide.lua:239-241`) |
| R-16 | Shiv gating (TBC: Mutilate-not-known, < 5 CP, EA context) | tbc-new `swords.apl.json` + `shiv.go` (cost 10×OH swing speed) | DEGRADED | the family gate (ERA+TBC) and the Mutilate/CP gates shipped; the **EA-context check** is filed (follow-up 5) |
| R-17 | Energy-tick model 20 per 2 s, AR re-anchors (+40) | classic `combat_sinister_strike` APL (`timeToEnergyTick < 1` at energy < 59) | WIRED | `classes/rogue.lua:94-96` (`TICK_PERIOD 2.0`, `TICK_ENERGY 20`, `TICK_AR_ENERGY 40`); the never-re-anchor grants are `classes/rogue.lua:105` `PROC_ENERGY_GAINS = { [15] = true, [25] = true }` (Combat Potency 15, Relentless Strikes 25) |
| R-18 | SoD **Envenom-primary** (4+CP), Poisoned Knife 425012, Vanish→Envenom sequence, Cut-to-the-Chase rune | sod `P5_Saber.apl.json` + `mutilate.apl.json` + `sim/rogue/envenom.go` | DEGRADED / MISSING | the SOD data + verdict ship (`ENVENOM_RULES.SOD`) but are **unreachable until SoD detection lands** (follow-up 3); Poisoned Knife / Vanish-sequence / CttC are unmodelled |
| R-19 | Wrath **sin upkeep triad** (Hunger for Blood 51662 ≤ 1 s, SnD, Cut to the Chase 57934) + Vanish 26889 / Overkill 58426 | wotlk `mutilate.apl.json`, `combat.apl.json` | MISSING | no HfB / Vanish / Overkill concept (audit W-G1) |
| R-20 | Tricks 57934 / Killing Spree 51690 / **Venom 1310703** prompts | wotlk `combat.apl.json`; forever `default.apl.json` | MISSING | follow-up 7 (needs slots + design). **CORRECTED 2026-10-20** (desk `corpus-corrections`): this row used to read "Riposte 1310703" — **1310703 is Venom** on the Forever client (`wowsims/forever sim/rogue/spell_data_auto_gen.go`: `Venom: spelldata.Ranked(1310703)`); the Forever APL's i=19 row is the Venom row, not a Riposte row. Evidence: `bench/rogue_apl_utility_build_2026-10-20.md` §3.8 and `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **R7** |
| R-21 | Sweaty swing-gate: SS within ~0.5 s of the swing **or energy ≥ 79 regardless of phase** | classic `combat_sinister_strike_sweaty.apl.json` | DEGRADED | the **≥ 79 override** shipped (`SWEATY_SPEND`); the 0.5 s window widening is filed pending in-client proof (follow-up 9) |
| R-22 | Retail sim verification | no retail sim repo in scope | UNCONFIRMED | follow-up 10 |

#### (B) Drill inventory

| Drill | Skill graded | Covers | Does NOT cover |
|---|---|---|---|
| `rogue_energy_pool` (`practice.lua:2554`) | **baseline resource** (operator ruling: does not count) | the spend start vs the 2 s energy-tick marker (`H.ROGUE_ENERGY_DEFAULTS = { tick_interval = 2, latency = 0.1 }`, `practice.lua:2503`) | everything else |
| `rogue_ss_window` (`practice.lua:2635`) | **rotation-window timing** (Era sword timing) | the 0.1–0.2 s post-MH-swing window, ideal 0.1 (`H.ROGUE_SS_DEFAULTS`, `practice.lua:2597`) | priority order, CP management, cooldown usage, opener |

Skill coverage: timing-window ✅ (one), **priority order ❌, cooldown/rotation-window ❌,
transition/opener ❌, situational ❌**.

#### (C) Target DRILL set — rogue (1 → 4)

**D-R1 — `rogue_finisher_order` — "the finisher order"**
- **kind:** NEW `rotation_order` · **class:** ROGUE
- **Skill category:** **rotation priority order**
- **What it grades:** at the right combo-point count, the right finisher — Expose duty →
  SnD upkeep → Shiv upkeep → Envenom (where the family plays it) → the dying-target
  dump → the planned finisher (Eviscerate-first on Era, Rupture-first on TBC/Wrath/
  Forever) → AR/BF/Cold Blood → Tea.
- **State / inputs:** `cp`, `energy_now`, `ttd`, `snd_remains`, `snd_min_cp`,
  `ea_duty`, `ea_remains`, `rupture_remains`, `deadly_stacks`, `envenom_buff_remains`,
  `family`.
- **Grade bands [DESIGN]:** S = 100 % correct picks · A = ≤1 mis-pick in 10 ·
  B = ≤2 · C = ≤3 · D = ≤5 · F = >5. A pick that is *nearly* right (e.g. Rupture
  instead of Eviscerate on Era) is a mis-pick — that is the whole point of the drill.
- **UI needs:** one icon per finisher/upkeep action + keybinds; the result popup lists
  the mis-picks with the wanted finisher.
- **Class seam / target:** `st.rogue_guide.evaluate` (`rogue_guide.lua:1127`) +
  `ST.ROGUE.gather_guide_inputs` (`classes/rogue.lua:833`).
- **Citation:** the rule order as written (`rogue_guide.lua:193-250`) and the per-family
  data it reads (POOL_BANDS `:271`, FINISHER_MODES `:282`, FINISHER_MIN_CP_BY_FAMILY
  `:292`, DUMP_MIN_CP_BY_FAMILY `:322`, EA_REFRESH_BY_FAMILY `:367`,
  TEA_ENERGY_MAX_BY_FAMILY `:404`).

**D-R2 — `rogue_cp_finish` — "the combo-point decision"**
- **kind:** NEW `situational` · **class:** ROGUE
- **Skill category:** **situational decision**
- **What it grades:** when to commit a finisher — at the family's finisher CP floor,
  and at the dump floor when the target is dying, and **not** below them.
- **State / inputs:** `cp`, `ttd`, `energy_now`, `family`, the dump floor and the
  planned-finisher floor for that family.
- **Grade bands [DESIGN]** on the CP the player acted at, relative to the floor:
  S = at or above the floor and on the right finisher · A = one CP late ·
  B = two CP late · C = at the floor but the wrong finisher · D = below the floor but
  the target was dying (forgiven) · F = below the floor on a healthy target (CP
  wasted).
- **UI needs:** a CP counter in the panel + the finisher icons.
- **Class seam / target:** `rogue_guide.lua:292` + `:322` (the per-family floors) +
  `classes/rogue.lua:833`.
- **Citation:** ERA/TBC 5 CP (classic `combat_sinisher_strike.apl.json`; tbc-new
  `swords.apl.json`), FOREVER 3+CP (forever `default.apl.json`), WRATH 4+CP
  (wotlk `combat.apl.json`); TBC dump = 5 CP / ≤ 5 s, WotLK = 4+CP / fight ≤ 4 s.

**D-R3 — `rogue_snd_upkeep` — "the debuff upkeep"**
- **kind:** NEW `rotation_window` · **class:** ROGUE
- **Skill category:** **cooldown / rotation-window usage**
- **What it grades:** keeping Slice and Dice up — the per-CP duration table, the
  family's minimum-CP line, and the "do not build while SnD is about to fall"
  pause.
- **State / inputs:** `cp`, `snd_remains`, `snd_min_cp`, the family's duration table,
  `energy_now`.
- **Grade bands [DESIGN]:** S = refreshed inside the family's own window (the
  per-CP duration minus the re-cast travel) · A = one "tick" late (≤ 2 s) ·
  B = ≤ 4 s late · C = the debuff expired · D = expired **and** the builder was pressed
  over the window · F = never maintained.
- **UI needs:** a SnD icon + a duration pip row (the slot is filed — the icon can ride
  the rotation label until the 7-slot contract is widened).
- **Class seam / target:** rule 1b (`rogue_guide.lua:207-210`) + the SND data
  (`rogue_guide.lua:359` `SND_DURATION_BY_CP`) + `classes/rogue.lua:833`.
- **Citation:** the per-CP durations `[9,12,15,18,21]` (tbc-new/classic
  `slice_and_dice.go`), the TBC 10 s minimum (which excludes 1 CP), forever 1+CP with
  clip ≤ 0 s, wotlk ≤ 1 s, sod 4+CP.

**D-R4 — `rogue_opener` — "the opener"**
- **kind:** NEW `transition` · **class:** ROGUE
- **Skill category:** **transition / opener**
- **What it grades:** the opening sequence — the prepull and the first-finisher
  decision, and the AR/swing pairing that the sim builds around.
- **State / inputs:** a synthetic pull countdown, `cp`, `energy_now`, `ar_ready`,
  `snd_usable`, `family`.
- **Grade bands [DESIGN]:** S = the opener order and the timing both correct ·
  A/B/C = correct order, the timing late by ≤1 GCD (A), ≤2 (B), ≤3 (C) ·
  D = the order correct but an opener missed · F = the wrong order.
- **UI needs:** a countdown label + the AR / finisher icons.
- **Class seam / target:** a synthetic pull clock in the drill (no client pull timer
  exists for the rogue); `rogue_guide.lua:1127` + `classes/rogue.lua:833`.
- **Citation:** the AR prepull shapes (tbc-new AR prepull −1 s and AR at energy ≤ 40;
  forever AR at ≤ 50 with SnD; classic AR at energy < 59 with tick < 1) — audit §F3.

#### (D) Target SCENARIO — rogue

**S-R — `rogue_rotation` — "the combat rotation, end to end"**
- **kind:** NEW `rotation_run` · **class:** ROGUE
- **Rotation table source:** the family's priority from the sim APLs —
  Era `classic ui/rogue/apls/combat_sinister_strike.apl.json` (+ `_sweaty`, `_iea`),
  SoD `sod ui/rogue/apls/P5_Saber.apl.json` + `mutilate.apl.json`,
  TBC `tbc-new ui/specs/rogue/dps/apls/swords.apl.json`,
  Wrath `wowsims/wotlk ui/rogue/apls/combat.apl.json` + `mutilate.apl.json`,
  Forever `forever ui/specs/rogue/dps/apls/default.apl.json`.
  The engine's rule order (`rogue_guide.lua:193-250`) is the compiled table.
- **Tick model:** the **energy tick** (20 energy per **2 s** — `classes/rogue.lua:94-95`
  `TICK_PERIOD 2.0` / `TICK_ENERGY 20`) + the GCD clock + the auto-attack clock
  (the sweeper's 0.1–0.2 s post-swing window for the Era sword build —
  `classes/rogue.lua:111-113`) + the debuff clocks (SnD per-CP duration, Rupture, EA).
- **Expected-sequence comparison:** `st.rogue_guide.evaluate(inputs, out)`
  (`rogue_guide.lua:1127`) at every GCD tick → `out.action` is the expected action
  (`expose`, `snd`, `shiv`, `envenom`, `eviscerate`, `rupture`, `ar`, `bf`,
  `coldblood`, `tea`, `builder`), `out.hold`/`out.hold_text` ("POOL") is the expected
  hold. The player's cast arrives via `H.scenario_event` and is compared against
  `out.action`; a press while the verdict is "POOL" is an illegal cast.
- **Grade bands [DESIGN]:** S = 0 mis-picks, 0 illegal casts · A = 1 · B = 2 · C = 3 ·
  D = 4-5 · F = >5 or any illegal cast. A **wrong finisher** (Eviscerate where the
  family plays Rupture) counts as a mis-pick — the spine is the point.
- **UI needs:** the finisher/upkeep icons with keybinds; the existing **energy tick
  bar** (the one the rogue already has) can be reused as the clock display; the run
  report shows the mis-picks and the CP at each.
- **Class seam / target:** driver `st.rogue_guide.evaluate` (`rogue_guide.lua:1127`);
  inputs `ST.ROGUE.gather_guide_inputs` (`classes/rogue.lua:833`); the rogue drill
  branch in `practice_ui.lua` (sibling lane) — the rogue drill plumbing already exists
  (`classes/rogue.lua:1723-1990`).
- **Citations:** the APL list above; the energy-tick facts from
  `bench/rogue_rotation_audit_2026-10-19.md` §F2.

---

### 2.5 DRUID

#### (A) Feature checklist

| # | Feature the sim implies | Sim source | Verdict | Anchor / what is missing |
|---|---|---|---|---|
| DU-01 | Tiger's Fury at the energy threshold (SoD ≤ 40; Wrath dynamic `40 − 10×leeway`) | sod `tigers_fury.go` (KotJ +60 energy); wotlk `rotation.go doTigersFury` | WIRED | `druid_guide.lua:459` `TF_ENERGY_WRATH = 40`; the dynamic line at `:606`; the KotJ +60 grant is modelled (`classes/druid.lua:389`) |
| DU-02 | Berserk (no energy gate; Rip up; no proc; TF ≥ 15 s away) | wotlk `rotation.go berserkNow` + `berserk.go` (50334, 15 s, 3 min, −50 % cost) | WIRED | rule W2 (`druid_guide.lua:296-299`); Forever F1b (`druid_guide.lua:216-220`) |
| DU-03 | Savage Roar upkeep (SoD ≥ 1 CP expired; Wrath expiry) | sod `rotation.go` (SR first branch, `!hasRoar`); wotlk `roarNow` | WIRED | rule S3/W3 (`druid_guide.lua:300-302`) |
| DU-04 | SR durations 14/19/24/29/34 s by CP (+8 s T8-4pc) | sod `savage_roar.go`; wotlk `savage_roar.go` (52610) | WIRED | `druid_guide.lua:495` `SOD_SR_DURATION = { 14, 19, 24, 29, 34 }` |
| DU-05 | Omen of Clarity → spend it on Shred | sod/classic `rotation.go` (`isClearcast → Shred`) | WIRED | rules S4/E0/F2/W4 |
| DU-06 | Rip at 5 CP, expiry-only | sod/classic `canRip`; wotlk `ripNow` | WIRED | rules E1/S5/W5/F3 (the SoD TF-snapshot clip was removed to match the sim) |
| DU-07 | Rip needs a fight gate (8 s at 5 CP / 10 s otherwise) | classic `canRip` fight gates | WIRED | `druid_guide.lua:582-586` (`fight_is_young`) + the fight stamp (`classes/druid.lua:1612-1625`) |
| DU-08 | Mangle (TBC 40 energy, 2pc-T6 35; live cost probe) | tbc-new `feralcat.go` (`CurrentMangleCatCost`) | WIRED | `druid_guide.lua:425-426` `MANGLE_COST_TBC = 40` / `SHRED_COST_TBC = 42`; the live probe `classes/druid.lua:1668-1681` |
| DU-09 | Ferocious Bite = end-of-fight only (minima Rip ≥ 4 s and SR ≥ 4 s; energy < 67; execute ≤ 10 s) | wotlk `canBite`/`biteNow` (`BiteTime 4`, `endThresh 10`) | WIRED | `druid_guide.lua:463-464` `FB_RIP_MIN_SECONDS = 4` / `FB_SR_MIN_SECONDS = 4`, `:469` `FB_EXECUTE_TTD_SECONDS = 10`; the Era/SoD mid-fight Bite branches were removed to match the sim |
| DU-10 | Rake upkeep (expiry-only on Wrath/Forever) | wotlk `rakeNow` | WIRED | rule W7/F4 |
| DU-11 | Rake **DPE check** + glyph-extension gate | wotlk `rakeNow` (`rakeDpeCheck`, `remainingExt`) | MISSING | needs AP/DPE + glyph inputs — `bench/wrath_leftovers_2026-10-19.md` §D4 (filed M7) |
| DU-12 | **clipRoar** glyph extension (RipLeeway 4 s; MinRoarOffset 12/14/25/27/34 s by set) | wotlk `rotation.go clipRoar` | DEGRADED | the SoD cover-to-end clip shipped (`druid_guide.lua:634` `sod_should_clip_roar`, spec at `:343-346`) but the **glyph/set extension** is absent — `wrath_leftovers` §D3 (filed M6) |
| DU-13 | **Faerie Fire omen-fishing** (Wrath ffThresh 87 / 15 in Berserk; MaxFfDelay 100 ms) | wotlk `rotation.go ffNow` | DEGRADED | the rule exists (W1b `druid_guide.lua:289-295`, F6c) but it is **dormant in game**: `omen_icd_ready` has no probe (`druid_guide.lua:109-116`) |
| DU-14 | **Pooling** as a cast-gate (`pendingPool` → `floatingEnergy`; Forever 2 s/1 s horizons) | wotlk `rotation.go` pooling block; forever `apl_sweep_test.go` `afterBuilder` | MISSING | ours is **display-only** on the energy tick bar (W9) — `wrath_leftovers` §D6 (filed M9) |
| DU-15 | **Trick windows** (BiteTrick 2+CP / ≤ 39 energy; RakeTrick `[biteCost,mangleCost)`; MangleTrick double; ripweave ≥ 52 energy; Era/SoD ShredTrick/RipTrick) | tbc-new `feralcat/rotation.go`; classic/sod `rotation.go` | MISSING | the inputs are reserved but **no rule reads them** (`druid_guide.lua:175-181`, `classes/druid.lua:1715-1720`) |
| DU-16 | **Powershift** (`<10 energy → shift`, Furor + Wolfshead 8345, OOM tracking) | classic `rotation.go tryPowershift/shiftNow/shouldPoolMana`; tbc-new `feralcat.go HasItemEquipped(8345)` | MISSING | the SHIFT branch was **removed** — the gather writes `can_powershift = nil` (`druid_guide.lua:66-72`); the Wolfshead id 8345 is sim-confirmed but unconfirmed in-client (`druid_guide.lua:182-190`) |
| DU-17 | Shifting Power (Forever): ceiling **50**, **40** on Clearcast; +40 energy; 16 s CD (8 s ISPP); refused at full | forever `shifting_power.go`, `mechanics_test.go` | WIRED | `druid_guide.lua:490-491` `SP_ENERGY_FOREVER = 50` / `SP_ENERGY_FOREVER_CLEARCAST = 40`; rule F1 (`:211-215`) |
| DU-18 | **Claw** builder when Shred cannot land | forever `apl_sweep_test.go` (`CannotShredTarget`) | DEGRADED | the slot is declared (`druid_guide.lua:18-19`, id 9850) but **no rule exists** — `can_shred` has no position probe (`druid_guide.lua:117-120`) |
| DU-19 | **Bear**: Maul on the queue, rage sufficiency, Mangle | sod/classic `maul.go`; forever `TestCatQueuesMaulOntoTheBearSwing` | WIRED | bear rules 1-3 (`druid_guide.lua:135-146`) |
| DU-20 | **Faerie Fire manual maintain** (`MaintainFaerieFire`) | classic/sod `rotation.go` | MISSING | manual by stance (documented) |
| DU-21 | Position input (behind the target for Shred/Mangle) | forever `CannotShredTarget`; wotlk `InFrontOfTarget` | MISSING | no probe exists (`druid_guide.lua:117-120`) |
| DU-22 | Latency term in W1 (`max(gcd, latency)`) | wotlk `doTigersFury` | DEGRADED | `inputs.latency` is written nil (`classes/druid.lua:1706`); the line degrades to the GCD alone |
| DU-23 | TBC RipCP is user-configurable (we freeze 4) | tbc-new `setupRotation` (`RipMinComboPoints`) | DEGRADED | `druid_guide.lua:438` `RIP_MIN_CP_TBC = 4`; the override input exists (`inputs.rip_min_cp`) but the **option widget is filed** (`desks/druid-rotfix/journal.md:64`) |
| DU-24 | Consumables / mana layer (Tea ≤ 20, potion fit, Innervate when mana-short) | forever `apl_sweep_test.go` | MISSING | no inputs (out of scope, noted) |
| DU-25 | Bearweave / flowerweave / snekweave / powerbear | wotlk `rotation.go` weave subsystem | MISSING | documented scope cut (`druid_guide.lua`, §W-9) |

#### (B) Drill inventory

| Drill | Skill graded | Covers | Does NOT cover |
|---|---|---|---|
| `druid_powershift` (`practice.lua:2363`) | **resource/timing decision** (the powershift cadence) | the energy at the moment of the shift (`H.POWERSHIFT_DEFAULTS = { energy_max 100, regen_per_second 10, shift_refund 40, rule_energy 20 }`, `practice.lua:2272-2277`); the grade is the energy band (`H.POWERSHIFT_BANDS`, `practice.lua:2279-2286`) | priority order, upkeep, opener |

> **Honest note for the build lane (not a drill-quality complaint, a sourcing note):**
> the drill's `rule_energy = 20` is the **addon's own rule**, not a sim number — the
> file's own comment says so ("The 20-energy rule is the fixed model rule; the shift
> refund is a sim constant (Furor-5/5 model) because the D1 talent/helm probe is
> BLOCKED"). The sims shift on a different trigger (`classic rotation.go`:
> `shiftNow when nextEnergy < cost`; `tbc-new feralcat/rotation.go`: `<10 energy →
> shift`). The drill is therefore **teaching a rule the sims do not use**. If the
> build lane re-sources this drill, the rule must change (see D-D2). Until then the
> drill stays as-is and the drift is recorded here.

Skill coverage: resource/timing ✅, **priority order ❌, cooldown/rotation-window ❌,
transition/opener ❌, upkeep ❌**.

#### (C) Target DRILL set — druid (1 → 4)

**D-D1 — `druid_finisher_order` — "the cat priority"**
- **kind:** NEW `rotation_order` · **class:** DRUID
- **Skill category:** **rotation priority order**
- **What it grades:** the cat rotation order — Tiger's Fury → Berserk → Savage Roar →
  Omen proc → Rip → Mangle → Rake → Bite → Shred, per family.
- **State / inputs:** `energy`, `combo_points`, `tf_ready`, `tf_cd_remaining`,
  `berserk_ready`, `sr_remaining`, `clearcast`, `rip_remaining`, `rake_remaining`,
  `mangle_remaining`, `time_to_die`, `target_short_lived`, `family`.
- **Grade bands [DESIGN]:** S = 100 % correct picks · A = ≤1 mis-pick in 10 ·
  B = ≤2 · C = ≤3 · D = ≤5 · F = >5.
- **UI needs:** one icon per cat action (tf / berserk / sr / rip / mangle / rake /
  bite / shred) + keybinds; the mis-pick list in the report.
- **Class seam / target:** `st.druid_guide.evaluate` (`druid_guide.lua:796`) +
  `ST.DRUID.gather_guide_inputs` (`classes/druid.lua:1750`).
- **Citation:** the rule order as written (`druid_guide.lua:133-312`) and the per-family
  appendices (TBC T1-T6, Forever F1-F7, Era E0-E2, SoD S1-S8, Wrath W1-W9).

**D-D2 — `druid_powershift_rework` — "the shift rule, re-sourced"**
- **kind:** NEW `energy_loop` (reuse the existing kind) · **class:** DRUID
- **Skill category:** **situational decision** (the shift-vs-spend decision)
- **What it grades:** the shift decision itself — shift when the pool is too low to
  cover the next builder, spend when it is. This is the drill the sim's whole DPS
  engine turns on.
- **State / inputs:** `energy`, the live builder cost (`mangle_cost` / the Shred cost),
  `tick_remaining`, the regen rate.
- **Grade bands [DESIGN]** on the energy at the moment of the decision, measured
  against the **builder cost** rather than a fixed line: S = the shift was taken below
  the cost the sim uses · A = ≤ 10 energy above it · B = ≤ 20 above · C = ≤ 30 above ·
  D = the shift was taken above the cost (a wasted shift) · F = the pool capped (the
  shift was never taken).
- **UI needs:** the energy bar + the tick marker (the druid already has both); no new
  frame.
- **Class seam / target:** `druid_energy.lua` (`get_tick_remaining`,
  `is_energy_in_window` — reserved helpers) + `classes/druid.lua:1715-1720`
  (`inputs.tick_remaining`) + `classes/druid.lua:1668-1681` (the live cost probe) +
  `druid_guide.lua:425-426`.
- **Citation:** classic `rotation.go` (`shiftNow when nextEnergy < cost`);
  tbc-new `feralcat/rotation.go` (`<10 energy → shift`, `MaxWaitTime = 1 s`,
  `shouldPoolMana` with Furor); the OOM tracker (`numShiftsToOom`) in the same file.
  The **regen rate** and the **shift refund** in the shipped drill
  (`regen_per_second = 10`, `shift_refund = 40`) are the addon's Furor-5/5 model, not
  sim-verified — see §5.

**D-D3 — `druid_roar_upkeep` — "the roar upkeep"**
- **kind:** NEW `rotation_window` · **class:** DRUID
- **Skill category:** **cooldown / rotation-window usage**
- **What it grades:** keeping Savage Roar up — the per-CP duration, the expiry-only
  refresh, and the SoD cover-to-end clip (the Roar that covers the fight instead of
  the one that expires).
- **State / inputs:** `sr_remaining`, `combo_points`, `time_to_die`, `fight_elapsed`,
  `target_short_lived`.
- **Grade bands [DESIGN]:** S = the Roar was cast to cover the target's remaining life
  (the clip) or inside the per-CP window · A = ≤ 2 s late · B = ≤ 4 s late ·
  C = the Roar expired before the next builder · D = expired and a builder was burned ·
  F = never maintained.
- **UI needs:** a Roar icon + a duration pip row; the guide frame's hold overlay
  already paints "SAVAGE ROAR" (`druid_guide.lua:300-302`).
- **Class seam / target:** rule S3/W3 (`druid_guide.lua:300-302`) + the clip helper
  (`druid_guide.lua:634` `sod_should_clip_roar`) + `classes/druid.lua:1750`.
- **Citation:** sod `rotation.go` (`roarNow`, `clipRoar`), wotlk `rotation.go`
  (`roarNow` + `clipRoar` with `RipLeeway = 4 s`); the durations
  `SOD_SR_DURATION = {14,19,24,29,34}`.

**D-D4 — `druid_bite_execute` — "the execute"**
- **kind:** NEW `transition` · **class:** DRUID
- **Skill category:** **transition / opener** (the fight's end phase)
- **What it grades:** the end-of-fight transition — holding Bite for the execute window
  instead of spending it mid-fight, and the Rip/Bite minima that guard it.
- **State / inputs:** `time_to_die`, `target_short_lived`, `combo_points`,
  `rip_remaining`, `sr_remaining`, `energy`, `clearcast`.
- **Grade bands [DESIGN]:** S = the Bite landed in the execute window with both minima
  met · A = the Bite landed in the window, one minimum missed by ≤ 2 s ·
  B = ≤ 4 s · C = the Bite landed outside the window · D = a mid-fight Bite (the sim
  never Bites there) · F = no Bite at all in the execute window.
- **UI needs:** a TTD label + the Bite icon (the guide slot exists).
- **Class seam / target:** rule T3/W8/F6a-F6b (`druid_guide.lua:228-231` F6a/F6b,
  `:315-320` W8, `:1030-1032` the minima check) + `classes/druid.lua:1750`.
- **Citation:** tbc-new `biteAtEnd` (`RipEndThresh = 10 s`); wotlk `canBite`
  (`Rip ≥ 4 s && SR ≥ 4 s`, `endThresh = 10 s`, `energy < 67`, `≤ 25` in Berserk);
  forever `TestMonocatBitesOnlyAtTheEnd`; sod/era `canBite` commented out (no Bite).

#### (D) Target SCENARIO — druid

**S-D — `druid_rotation` — "the cat rotation, end to end"**
- **kind:** NEW `rotation_run` · **class:** DRUID
- **Rotation table source:** the family's priority from the sim rotation files —
  Era `classic sim/druid/feral/rotation.go` (clearcast → Rip → ShredTrick → builder),
  SoD `sod sim/druid/feral/rotation.go` (SR → clearcast → Rip → clipRoar → ShredTrick
  → builder) + `savage_roar.go` + `tigers_fury.go`,
  TBC `tbc-new sim/druid/feralcat/rotation.go` (the NerdEgghead port),
  Wrath `wowsims/wotlk sim/druid/feral/rotation.go`,
  Forever `forever sim/druid/feralcat/apl_sweep_test.go` (`catAPL`).
  The engine's appendices (`druid_guide.lua:165-312`) are the compiled tables.
- **Tick model:** the **energy tick** (20 energy per **2 s** — `druid_energy.lua:19,23`;
  window 19–22 — `druid_energy.lua:25-29`) + the GCD clock + the swing clock +
  the debuff clocks (SR per-CP duration, Rip, Rake, Mangle).
- **Expected-sequence comparison:** `st.druid_guide.evaluate(inputs, out)`
  (`druid_guide.lua:796`) at every GCD tick → `out.action` is the expected action,
  `out.hold`/`out.hold_text` ("TIGER'S FURY", "BERSERK", "SAVAGE ROAR",
  "FAERIE FIRE") is the expected hold. The player's cast arrives via
  `H.scenario_event` and is compared against `out.action`; a press while the verdict is
  a hold is an illegal cast.
- **Grade bands [DESIGN]:** S = 0 mis-picks, 0 illegal casts · A = 1 · B = 2 · C = 3 ·
  D = 4-5 · F = >5 or any illegal cast.
- **UI needs:** the cat action icons with keybinds; the energy tick bar already exists
  and can carry the tick clock.
- **Class seam / target:** driver `st.druid_guide.evaluate` (`druid_guide.lua:796`);
  inputs `ST.DRUID.gather_guide_inputs` (`classes/druid.lua:1750`); the druid drill
  branch in `practice_ui.lua` (sibling lane) — the druid drill plumbing already exists
  (`classes/druid.lua:2307-2406`).
- **Citations:** the sim rotation files listed above (the audit's §0 source list).

---

### 2.6 SHAMAN

#### (A) Feature checklist

| # | Feature the sim implies | Sim source | Verdict | Anchor / what is missing |
|---|---|---|---|---|
| S-01 | **Stormstrike on cooldown, never delayed** | all four sims cast SS unconditionally at its priority slot | WIRED | rule 8; the WF-hold is **opt-in** (`stormstrike_hold_enabled`, `shaman_guide.lua:104-106`) and the default presses SS |
| S-02 | Maelstrom 5 → weave | SoD P6 #5, P4 #10; Era #5; TBC #2; Forever #9 | WIRED | rule 5 (`shaman_guide.lua:182-187` in the header) |
| S-03 | SoD **ANY-stack** weave fit (cast + 100 ms ≤ time-to-next-auto) | sod `phase_4/6.apl.json` (`autoTimeToNext >= cast + 100 ms`) | WIRED | rule 5b; `shaman_guide.lua:388-389` `WEAVE_SUB5_MIN_STACKS = 0`, `WEAVE_SUB5_FIT_BUFFER_SECONDS = 0.10` |
| S-04 | Wrath **MW ≥ 3** swing-fit hardcast (WF-imbue build only) | wowsims/wotlk `default_wf.apl.json` (MW ≥ 3 AND 300 ms + cast < autoTimeToNext) | WIRED | rule 5c; `shaman_guide.lua:396-397` `WEAVE_SUB5_MIN_STACKS_WRATH = 3`, `WEAVE_SUB5_FIT_BUFFER_WRATH_SECONDS = 0.30` |
| S-05 | Flame Shock **re-apply on expiry** (never early) | all sims (`not dotIsActive`) | DEGRADED | the engine still refreshes at ≤ **3 s** (`flameshock_refresh` default 3, `shaman_guide.lua:88-91`); the sims refresh on expiry — filed to the options pass (explicit-0 is honoured by the engine) |
| S-06 | Flame Shock is **never cast on Era** | classic default APL (no FS) | WIRED | `flameshock_allowed` veto (`shaman_guide.lua:91-95`) |
| S-07 | Shamanistic Rage (SoD mana ≤ 65 %; TBC mana < 10 %; Wrath on cooldown) | sod P6 #3; tbc-new SR group; wotlk (generic MCD) | WIRED | rule 4; `shaman_guide.lua:367-368` `SR_MANA_THRESHOLD_TBC = 0.10`, `SR_MANA_THRESHOLD_SOD = 0.65` |
| S-08 | Feral Spirit (SoD #1; Wrath #1) | sod `phase_6.apl.json`; wotlk `feral_spirit.go` (51533, 3 min, 45 s) | WIRED | rule 3 (`shaman_guide.lua:172-175`); the SoD name feed shipped |
| S-09 | Lava Lash (SoD #6, unconditional) | sod `phase_6.apl.json`; wotlk `lavalash.go` (60103, 6 s, OH-only) | WIRED | rule 12 (`shaman_guide.lua:591`) |
| S-10 | Molten Blast 425339 (SoD unconditional filler) | sod `phase_6.apl.json`; `proto/shaman.proto:113` | WIRED | rule 15 (`shaman_guide.lua:613`); the SoD name feed shipped |
| S-11 | Chain Lightning (MW ≥ **4** AND targets ≥ 2) | sod P6 #8, P4 #6 | DEGRADED | rule 13 + the slot are live but the **enemy-count sensor does not exist** — `target_count` is fed nil (`shaman_guide.lua:147-149`) |
| S-12 | Fire Nova (TBC 15 s; suppressed while the Fire Ele holds the fire slot; Forever: Clearcasting → FN, else mana > 10 %) | tbc-new `fire_totems.go` (25537); forever `default.apl.json` | WIRED | rules 11/16 (`shaman_guide.lua:587`, `:621`); the Fire-Ele suppression is `fireele_active` (`shaman_guide.lua:113-117`) |
| S-13 | Magma Totem (TBC default fire totem; Wrath 58734 gated on `magma <= 100 ms AND NOT FE 2894`) | tbc-new `fire_totems.go`; wotlk `fire_totems.go` | WIRED | rule 10; the TBC feed was extended (`desks/shaman-rotation-fix/journal.md:9`) |
| S-14 | Windfury Totem **twist** (TBC) + mana pause at 10 % | tbc-new `weapon_imbues.go` | WIRED | the twist slot + `twist_mana_threshold`; `weave.lua:632` `TWIST_MANA_PAUSE_THRESHOLD_TBC = 0.10`; rule 7 |
| S-15 | Twist **keyed on the imbue buff** (≤ 0.5 s re-drop), GoA re-drop gated on WF-buff ≥ 5 s | tbc-new `weapon_imbues.go` | DEGRADED | ours is a **10 s stamp timer** (`weave.lua:574-575,588-595`); the buff-keyed re-drop is filed (no buff-expiry read exists) |
| S-16 | **Static totem maintain** (WF 10614, GoA 10627 on Era) | classic default APL (WF totem refresh, GoA when inactive) | WIRED | rules 8b/8c (`shaman_guide.lua:566-572`) |
| S-17 | **Searing Totem** maintain (Era fight > 20 s; SoD P6 fight > 30 s) | classic default APL; sod P6 | DEGRADED | the groundwork shipped (`fight_elapsed`, `searing_down`) but **no rule reads it** (`desks/shaman-rotation-fix/journal.md:40`) |
| S-18 | **Fire Elemental snapshot line-up** (WoA-first + weapon swap + trinket stacking) | tbc-new APL (Fire Ele group) | DEGRADED | the pure predicate exists (`weave.lua:671` `is_fireele_lineup_ready`) but **nothing wires it**; the swap is not portable (combat lockdown) |
| S-19 | **Lightning Shield 49281** (maintain-iff-inactive, above LL) | all three wotlk APLs + `lightning_shield.go` | MISSING | no slot — the guide ships **15** slots today (`classes/shaman.lua:3192-3197`), so LS needs a 16th; filed M2 |
| S-20 | **Call of the Elements 66842** (water totem < 20 s) | wotlk APLs + `totems.go` | MISSING | no water-slot clock; filed (cut-with-reason) — `desks/shaman-rotation-fix/journal.md:67-72` |
| S-21 | **Earth Shock** (unconditional below FS; era mana ≥ 50 %) | classic/tbc-new/wotlk APLs | WIRED | rules 14/17 (`shaman_guide.lua:609`, `:624`); `shaman_guide.lua:371` `ES_MANA_FLOOR_ERA = 0.5` |
| S-22 | **Windfury Weapon ICD 1.5 s** on Era/SoD (3 s on TBC) | sod `windfury_weapon.go` (1.5 s); tbc-new `weapon_imbues.go` (3 s) | WIRED | `weave.lua` ICD helper shared by the strip/badge/wash/guide |
| S-23 | **Stormstrike cooldown per family** (Era 20 s / SoD 6 s / TBC 10 s / Wrath 8 s, 6 s with Glad-4pc) | classic/sod/tbc-new/wotlk `stormstrike.go` | DEGRADED | the shipped fallback is **10** and the live client length rides after the first cast — the fallback only matters pre-first-cast (Era −10 s is the worst direction) |
| S-24 | **Autocast cooldowns** (trinkets / racials) lead every sim | SoD P6 #2, Era #4, TBC #5, Forever #3 | MISSING | no on-use cue anywhere — no portable display in scope (`desks/shaman-rotation-fix/journal.md:23` F1) |
| S-25 | **Searing on TBC** as the low-mana fire totem fallback | tbc-new APL (Searing fallback / when mana low) | DEGRADED | tied to S-17 (no rule) |
| S-26 | **Twist rank**: max-rank 25587 + mana pause vs our downrank-to-rank-1 note | tbc-new APL | DEGRADED | an open decision, not a bug — `desks/shaman-rotation-fix/journal.md:25` F3 |
| S-27 | **Forever static totem maintain** (WF 10614, earth 25361, Searing 10438) | forever `testing.build.json` | MISSING | the Forever twist slot is 8512 while the sim drops 10614 (`desks/shaman-rotation-fix/journal.md:27` F5). **CORRECTED 2026-10-20** (desk `corpus-corrections`): 8512 is a real **Windfury Totem rank-1** id (the client's rank-1 fallback), not a wrong id — and the **TBC APL's own air-slot rows cast 25587 r5 (Windfury) / 25359 r3 (Grace of Air)**, so the twist row's ranks are a *filed* question, not an error. Evidence: `bench/shaman_apl_utility_build_2026-10-20.md` §2 **C5**; `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **S5** |
| S-28 | **Clearcasting (16246) → Fire Nova** | forever `default.apl.json` | WIRED | rule 16 (`shaman_guide.lua:621`) |
| S-29 | **Wrath LS/shield choice** (WaterShield vs LightningShield is a spec option) | wotlk `enhancement_test.go` | MISSING | same cut as S-19 |

#### (B) Drill inventory

| Drill | Skill graded | Covers | Does NOT cover |
|---|---|---|---|
| `shaman_weave` (`practice.lua:2454`) | **rotation-window timing** (the weave fit) | the marker fraction / safe start / clip, on `weave.lua`'s maths (`H.WEAVE_DEFAULTS = { swing_duration 2.6, effective_cast 1.5, latency 0.1 }`, `practice.lua:2403`); a clipped cast = F | priority order, upkeep, cooldown usage, opener, the MW-stack decision |

Skill coverage: timing-window ✅, **priority order ❌, cooldown/rotation-window ❌,
transition/opener ❌, upkeep ❌**.

#### (C) Target DRILL set — shaman (1 → 4)

**D-S1 — `shaman_enh_priority` — "the enhancement priority"**
- **kind:** NEW `rotation_order` · **class:** SHAMAN
- **Skill category:** **rotation priority order**
- **What it grades:** the spine the sims encode — Feral Spirit → autocast CDs →
  Shamanistic Rage → the weave (LvB at any stack when it fits / LB at MW ≥ 3 on Wrath)
  → Stormstrike → Flame Shock → Earth Shock → Molten Blast → Chain Lightning.
- **State / inputs:** `mw_stacks`, `mw_available`, `weave_available`,
  `weave_sub5_ready`, `weave_sub5_is_lavaburst`, `stormstrike_remaining`,
  `flameshock_remaining`, `flameshock_allowed`, `sr_remaining`, `sr_mana_threshold`,
  `mana_fraction`, `shock_remaining`, `target_count`, `family`.
- **Grade bands [DESIGN]:** S = 100 % correct picks · A = ≤1 mis-pick in 10 ·
  B = ≤2 · C = ≤3 · D = ≤5 · F = >5.
- **UI needs:** one icon per action (feralspirit / sr / weave / stormstrike /
  flameshock / earthshock / moltenblast / chainlightning / firenova / lavalash) with
  keybinds; the mis-pick list in the report.
- **Class seam / target:** `st.shaman_guide.evaluate` (`shaman_guide.lua:437`) +
  `ST.SHAMAN.gather_guide_inputs` (`classes/shaman.lua:2738`).
- **Citation:** the rule order as written (`shaman_guide.lua:168-300`) and the sim
  spines (SoD P6, Era #5, TBC #2, Forever #9) from the audit §SoD / §Era / §TBC /
  §Forever.

**D-S2 — `shaman_mw_weave` — "the stack decision"**
- **kind:** NEW `rotation_window` · **class:** SHAMAN
- **Skill category:** **cooldown / rotation-window usage** (the weave window + the
  stack threshold)
- **What it grades:** whether to weave *now* — the MW stack count the build plays, the
  cast-time fit against the swing, and the buffer.
- **State / inputs:** `mw_stacks`, the weave cast seconds, `swing_remaining`,
  `latency`, `family`, the build imbue state.
- **Grade bands [DESIGN]** on the fit margin (reusing the shipped weave bands,
  `H.WEAVE_MARGIN_BANDS`, `practice.lua:2405-2411`): a clip = **F**; otherwise
  S ≤ 0.02 s, A ≤ 0.05, B ≤ 0.10, C ≤ 0.20, D beyond. A weave taken **below** the
  family's stack floor (5 on Wrath/TBC, any on SoD) is an extra mis-pick.
- **UI needs:** the weave marker/zone widgets the shaman already has on the bars
  (`bench/shaman_drill_designer_2026-10-19.md` §2 element inventory) + the MW badge.
- **Class seam / target:** `shaman_guide.lua:388-397` (the stack/buffer constants) +
  `classes/shaman.lua:2738`.
- **Citation:** sod `autoTimeToNext >= cast + 100 ms` (the SoD fit, the 0.10 s buffer
  in `shaman_guide.lua:389`); wotlk `default_wf.apl.json` MW ≥ 3 + 300 ms (the 0.30 s
  buffer, `shaman_guide.lua:397`); the MW5 instant (all sims).

**D-S3 — `shaman_stormstrike_hold` — "the CD decision"**
- **kind:** NEW `situational` · **class:** SHAMAN
- **Skill category:** **situational decision** (hold the SS for the proc, or press it)
- **What it grades:** the one place the sims and our history disagree — holding
  Stormstrike for the Windfury proc instead of pressing it on cooldown.
- **State / inputs:** `stormstrike_remaining`, `stormstrike_hold_enabled`,
  `windfury_icd_remaining`, `mw_stacks`, `swing_remaining`.
- **Grade bands [DESIGN]:** S = the SS was pressed the moment it came off cooldown
  (the default every sim plays) · A/B/C = pressed late by ≤1 GCD (A), ≤2 (B), ≤3 (C) ·
  D = pressed late enough to lose the next Stormstrike window · F = the SS was held
  with the opt-in off (a dead GCD).
- **UI needs:** the Stormstrike icon + the WF strip (both exist); the report says
  whether the opt-in was on.
- **Class seam / target:** `shaman_guide.lua:104-106` (the opt-in input) + rule 8 +
  `classes/shaman.lua:2738`.
- **Citation:** every fetched sim casts SS unconditionally (audit §Cross-sim #1) —
  the hold is our own historical behaviour, now opt-in.

**D-S4 — `shaman_totem_upkeep` — "the totem upkeep"**
- **kind:** NEW `rotation_window` · **class:** SHAMAN
- **Skill category:** **cooldown / rotation-window usage** (the air/fire slots)
- **What it grades:** keeping the air slot (Windfury Totem / Grace of Air) and the
  fire slot (Magma / Searing) occupied, and not replacing a live Fire Elemental.
- **State / inputs:** `wftotem_remaining`, `goatotem_remaining`, `magma_remaining`,
  `magma_refresh`, `fireele_active`, `searing_down`, `fight_elapsed`, `family`.
- **Grade bands [DESIGN]:** S = every slot due was re-dropped inside its window and no
  live totem was replaced · A/B/C = one re-drop late by ≤1 s (A), ≤2 (B), ≤3 (C) ·
  D = a slot was left empty past its window · F = the Fire Elemental was overwritten.
- **UI needs:** the totem icons (the shaman already has the totem waits in the guide
  set) + the fight clock label.
- **Class seam / target:** rules 8b/8c/10/11 (`shaman_guide.lua:550-587`) +
  `classes/shaman.lua:2738` + the Searing groundwork (`desks/shaman-rotation-fix/journal.md:40`).
- **Citation:** classic default APL (WF totem refresh / GoA when inactive);
  sod P6 (Searing iff inactive and fight > 30 s); tbc-new (WF twist at imbue-buff
  ≤ 0.5 s; GoA ≤ 5 s gated on WF-buff ≥ 5 s; Magma 25550 filler; Searing fallback);
  wotlk (Magma iff `magma-dot <= 100 ms AND NOT FE 2894`).

#### (D) Target SCENARIO — shaman

**S-S — `shaman_rotation` — "the enhancement rotation, end to end"**
- **kind:** NEW `rotation_run` · **class:** SHAMAN
- **Rotation table source:** the family's priority from the sim APLs —
  SoD `sod ui/enhancement_shaman/apls/phase_6.apl.json` (+ `phase_4.apl.json`),
  Era `classic ui/enhancement_shaman/apls/default.apl.json`,
  TBC `tbc-new ui/specs/shaman/enhancement/apls/default.apl.json`,
  Wrath `wowsims/wotlk ui/enhancement_shaman/apls/default_ft.apl.json` +
  `default_wf.apl.json` (+ `phase_3.apl.json`),
  Forever `forever ui/specs/shaman/enhancement/builds/testing.build.json`.
  The engine's rule order (`shaman_guide.lua:168-300`) is the compiled table.
- **Tick model:** the swing clock (the weave's own clock — the weave model runs on
  `weave.lua`'s marker maths) + the GCD clock + the **Windfury Weapon ICD** (1.5 s on
  Era/SoD, 3 s on TBC) + the mana model (the SR gate reads `mana_fraction`) + the
  shock CD (the shared 6 s shock cooldown) + the debuff clocks (FS 12 s, SS 12 s).
- **Expected-sequence comparison:** `st.shaman_guide.evaluate(inputs, out)`
  (`shaman_guide.lua:437`) at every GCD tick → `out.action` is the expected action
  (`fireele`, `feralspirit`, `shamanisticrage`, `weave`, `flameshock`, `twist`,
  `wftotem`, `goa`, `stormstrike`, `magma`, `firenova`, `lavalash`, `chainlightning`,
  `earthshock`, `moltenblast`), `out.hold`/`out.hold_text` ("RIDE" while casting) is
  the expected hold. The player's cast arrives via `H.scenario_event` and is compared
  against `out.action`; a press while the verdict is a hold is an illegal cast.
- **Grade bands [DESIGN]:** S = 0 mis-picks, 0 illegal casts · A = 1 · B = 2 · C = 3 ·
  D = 4-5 · F = >5 or any illegal cast.
- **UI needs:** the action icons with keybinds; the existing weave marker/zone widgets
  carry the fit window.
- **Class seam / target:** driver `st.shaman_guide.evaluate` (`shaman_guide.lua:437`);
  inputs `ST.SHAMAN.gather_guide_inputs` (`classes/shaman.lua:2738`); the shaman drill
  branch in `practice_ui.lua` (sibling lane) — the shaman drill plumbing already exists
  (`classes/shaman.lua:3405-3660`).
- **Citations:** the APL list above.

---

## 3. Class parity table

### 3.1 Practice-mode parity (what each class has today vs the target)

| Class | SCENARIO (rotation, end-to-end) | DRILL: priority order | DRILL: cooldown / rotation-window | DRILL: transition / opener | DRILL: situational decision | DRILL: timing-window | Real drills today | Target drills | Gap |
|---|---|---|---|---|---|---|---|---|---|
| PALADIN | ✗ | ✗ | ✓ `paladin_aw_combo` | ✗ | ✗ | ✓ `paladin_twist` | 2 | 5 | +3 drills, +1 scenario |
| WARRIOR | ✗ | ✗ | ✗ | ✗ | ✓ `warrior_execute` | ✗ | 1 | 4 | +3 drills, +1 scenario |
| HUNTER | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ `hunter_forced_move` | 1 | 4 | +3 drills, +1 scenario |
| ROGUE | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ `rogue_ss_window` (+1 baseline `rogue_energy_pool`) | 1 | 4 | +3 drills, +1 scenario |
| DRUID | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ `druid_powershift` | 1 | 4 | +3 drills, +1 scenario |
| SHAMAN | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ `shaman_weave` | 1 | 4 | +3 drills, +1 scenario |

**Reading the table.** Every class is missing the same three things: the rotation
SCENARIO (all six), the priority-order drill (all six), and the opener/transition
drill (all six). The cooldown-window drill exists only for the paladin (the AW combo)
and the situational drill only for the warrior (the execute phase). The timing-window
drill is the one that is broadly covered — the paladin twist, the hunter forced move,
the rogue SS window, the shaman weave, the druid powershift — which is why the
resource/timing family is the only one that looks healthy.

### 3.2 Guide-engine parity (the rotation driver each scenario will use)

| Class | Rotation driver (pure) | Gather (live inputs) | Guide slot set | Retail | Note |
|---|---|---|---|---|---|
| PALADIN | `st.nextaction.evaluate` (`nextaction.lua:440`) | `classes/paladin.lua:3014` | `ST.PALADIN.guide.slots` (`classes/paladin.lua:3374-3375`) | inert (`nextaction.lua:446`) | four FCFS tables at `nextaction.lua:946-961` |
| WARRIOR | `st.warrior_guide.evaluate` (`warrior_guide.lua:762`) | `classes/warrior.lua:2779` | `ST.WARRIOR.guide.slots` (`classes/warrior.lua:3078`); HUD family sets `:3158-3206` | inert (`warrior_guide.lua:768-779`) | rule order `warrior_guide.lua:827-1000` |
| HUNTER | `st.hunter_guide.evaluate` (`hunter_guide.lua:651`) | `classes/hunter.lua:1963` | `ST.HUNTER.guide.slots` (`classes/hunter.lua:2276`); HUD `:2333` | inert | rule matrix `hunter_guide.lua:237-360` |
| ROGUE | `st.rogue_guide.evaluate` (`rogue_guide.lua:1127`) | `classes/rogue.lua:833` | `ST.ROGUE.guide.slots` (`classes/rogue.lua:761-762`, 7 slots, frozen) | n/a (no sim) | rule order `rogue_guide.lua:193-250`; slot-less actions (snd/ar/bf/coldblood) |
| DRUID | `st.druid_guide.evaluate` (`druid_guide.lua:796`) | `classes/druid.lua:1750` | `ST.DRUID.guide.slots` (`classes/druid.lua:1957-1958`, 7 slots) | inert | five family appendices `druid_guide.lua:165-312` |
| SHAMAN | `st.shaman_guide.evaluate` (`shaman_guide.lua:437`) | `classes/shaman.lua:2738` | guide 15 slots (`classes/shaman.lua:3192-3197`); HUD 8 (`classes/shaman.lua:3237-3246`) | n/a | rule order `shaman_guide.lua:168-300` |

**Consequence for the build lane:** the scenario driver is uniform — every class
already ships a pure `evaluate(inputs, out)` that returns `out.action` (a slot key)
plus `out.hold` / `out.hold_text`. One scenario kind can therefore serve all six
classes, and one grader can compare "the action the engine wanted" against "the action
the player pressed". The class-specific work is (a) the simulated input state per
family, and (b) the icon set.

---

## 4. Shared build-lane requirements

**4.1 A new harness kind.** `H.SCENARIO_KINDS` (`practice.lua:1495-1503`) is closed and
`register_scenario` rejects unknown kinds (`practice.lua:1520-1522`). The build lane
needs three new kinds (or one kind with a mode flag):

- `rotation_run` — the rotation SCENARIO (all six classes).
- `rotation_order` — the priority-order DRILL (all six classes).
- `rotation_window` / `transition` / `situational` — the remaining drill kinds; each
  can reuse the existing primitives:
  - `rotation_window` ≈ `weave_timing` / `swing_window` (both already grade a margin
    against a marker).
  - `transition` ≈ `combo_windows` (opener + pieces inside a window).
  - `situational` ≈ `execute_phase` (a phase crossing + a graded entry).

**4.2 The per-class → practice-mode map must change shape.**
`practice_ui.lua:630-637` maps a class to **one** drill key. With a scenario plus N
drills per class it has to become a map of
`class → { scenario = "<key>", drills = { "<key>", ... } }` — and the progression
scope (`progress_drill_key`, `practice_ui.lua:692-697`) then resolves per drill, not
per class. `practice_progress.lua` already supports one mastery row per `drill_id`
(`bench/buildout_practice_gamification_foundation_2026-10-19.md` §2), so the keys in
§2 are the `drill_id`s.

**4.3 The unlock registry.** A level-gated harder variant is a **new scenario**, named
by `spec.scenario`; an unlock never touches an existing drill's grading
(`bench/buildout_practice_gamification_foundation_2026-10-19.md` §"The generic unlock
registry"). The §2 keys are therefore stable and can be referenced by a later unlock
lane without renumbering.

**4.4 Registry + test pins.** `tests/practice_state.lua:1375-1403` pins
`#H.SCENARIO_ORDER == 8` and the per-class counts; every new registration breaks those
pins and needs replacements. The new pins must also cover: the new kinds are accepted
and an unknown kind is still rejected; the scenario's `evaluate` comparison path; the
per-class drill lists; the grade-band boundaries.

**4.5 The scenario's own state machine.** The six scenario specs in §2 share a
skeleton:

```
state = { t, gcd_timer, swing_timer, resource, cooldowns{}, debuffs{}, decisions[], }
on GCD tick:  expected = engine.evaluate(inputs, out)
player cast:  compare to expected -> record { expected, actual, ok }
on end:       grade by the §2 bands, feed H.record_session_attempt
```

The class-specific parts are the input writer (the simulated state → the engine's
frozen input names) and the icon set. **The input writer must use the engine's own
frozen input names** — they are documented per class in the guide headers
(`nextaction.lua:22-127`, `warrior_guide.lua:76-220`, `hunter_guide.lua:90-235`,
`rogue_guide.lua:98-192`, `druid_guide.lua:21-132`, `shaman_guide.lua:55-167`).

**4.6 Family gating.** Every engine short-circuits on Retail
(`nextaction.lua:359-371`, `warrior_guide.lua:768-779`, the hunter/druid equivalents).
The scenarios must not be offered on Retail, and the family must select the slot set,
the input writer and the rotation table (the same shape the guide slots already use:
`classes/hunter.lua:2333`, `classes/warrior.lua:3158-3206`).

**4.7 One rule the build lane must not break.** A drill or scenario may not change an
existing drill's sim fidelity, grading, timings or difficulty
(`bench/practice_gamification_design_2026-10-19.md` §5 rule 2). The existing eight
entries keep their keys, kinds, bands and behaviour; everything in §2 is **additive**.

---

## 5. UNCONFIRMED ledger

Nothing below blocks the specs; each item needs in-client or sim-source proof before
it is wired into a live prompt. These are **not** reasons to block the build lane —
they are the items the build lane must carry as UNCONFIRMED.

| # | Item | Where it bites | Source of the doubt |
|---|---|---|---|
| U-01 | Warrior **rage regeneration rate** — the scenario's rage ledger needs one | §2.2 S-W | no in-scope sim source quotes a regeneration rate; the shipped drill models 10/s (`practice.lua:2274`) as an addon model |
| U-02 | Druid **powershift refund (40) and regen (10/s)** | §2.5 D-D2 | the drill's own comment calls the refund a "Furor-5/5 model"; the Furor probe is BLOCKED (`bench/verify_bank.md` §3) |
| U-03 | Druid **Wolfshead 8345** | §2.5 D-D2, D-D1 | the sim checks it (`tbc-new feralcat.go HasItemEquipped(8345)`); in-client presence unconfirmed |
| U-04 | Rogue **Hemo builder** | §2.4 D-R1 | `resolve_builder_entry` excludes Hemo as uncertain |
| U-05 | Rogue **per-CP Rupture durations 2–4 CP** | §2.4 D-R3 | only the 1 CP and 5 CP rows are sim-sourced (`rogue_guide.lua:337`) |
| U-06 | Hunter **Forever Sniper/Hawk ids** and the **hawk-count source** | §2.3 S-H | sim-confirmed ids, CLIENT-UNCONFIRMED; the count source does not exist |
| U-07 | Hunter **Serpent Sting target-debuff source** (the gather writes `serpent_known` / `serpent_active` nil) | §2.3 D-H1, S-H | no compat debuff source exists for the target; the engine arm is live but unreachable |
| U-08 | Hunter **TBC Steady rank 34120** | §2.3 D-H1 | the sim downranks for mana; we resolve the highest known rank. **CORRECTED 2026-10-20** (desk `corpus-corrections`): the TBC *rotation* row's **56641** does not exist on the TBC client — the build lane re-cut it to 34120; and the **Forever client has no Steady Shot at all** (its row was removed). Evidence: `bench/hunter_apl_utility_build_2026-10-20.md` §3; `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **H3**/**H4** |
| U-09 | Shaman **Per-family Stormstrike fallback** (Era 20 / SoD 6 / Wrath 8) | §2.6 S-S | sim values are confirmed; the shipped fallback is 10 and only matters pre-first-cast |
| U-10 | Shaman **water totem slot / CoE 66842** on 3.80.2 | §2.6 (not built) | filed, cut-with-reason (a 16th guide slot — the set grew from 13 to 15 in the G2 lane — plus no water clock) |
| U-11 | Paladin **Holy-Power stack 1226461**, Templar/Sunlight, Aura-Mastery rune, dual-seal timers | §2.1 (SoD variants not built) | `bench/sod_paladin_variants_2026-10-19.md` §7 — the shared input shopping list |
| U-12 | Paladin **Holy Strike** id on Forever | §2.1 P-25 | no sourced id |
| U-13 | Warrior **stance index map** and the SoD aura 426969 | §2.2 D-W1/D-W3 | UNCONFIRMED per `desks/warrior-rotfix/journal.md:24-25` |
| U-14 | All **in-client** behaviour of every sim number | everywhere | sim-match is not client proof (the standing note in every audit) |
| U-15 | Every **grading band** in §2 | everywhere | **[DESIGN]** — addon policy, deliberately not sim-sourced |

---

## 6. What was NOT compared (out of scope, no claim)

- Retail rotation behaviour for any class (no retail sim repo in scope; the rogue
  Retail rows stay guide-sourced and UNCONFIRMED).
- AoE rotations (the druid audit explicitly excludes `rotation_aoe.go`).
- Tank rotations, balance/resto specs, item-set and trinket-proc modelling.
- Any in-client measurement: latency, cast times, clip amounts, cooldown lengths.
  Every number in this file is either a sim value (with its citation), a value already
  frozen in the tree (cited to its `file:line`), or a **[DESIGN]** grading band.
- The `docs/swedge/SwedgeTimer_TBC` / `_Forever` archives beyond the pattern the three
  practice-designer records already documented (read, not re-derived).

---

## 7. Validation

**Owner: orchestrator.**

How to check this file:
1. Every `file:line` anchor can be grepped on the current tree; the guide headers
   quote the rule orders, so the anchors move only if the guide files change.
2. Every sim citation resolves to one of the per-class rotation audits
   (which quote the raw APL/`.go` file), or to `bench/wrath_leftovers_2026-10-19.md`
   (which carries the full wowsims/wotlk URL list), or to
   `bench/sod_paladin_variants_2026-10-19.md` (the six p8 paladin APLs).
3. The registry claims in §1.2 can be re-verified by reading `practice.lua:1495-1503`,
   `:1798`, `:1969`, `:2093`, `:2214`, `:2363`, `:2454`, `:2554`, `:2635` and
   `practice_ui.lua:630-637`.
4. `bench/class_features_drills_2026-10-19.md` is NEW (glob-verified absent before
   writing); no other bench file, addon file or test file was modified by this lane;
   no git command was run.

**Not validated by this lane** (honest limits): no test suite was run (read-only
brief); no in-client behaviour was observed; the warrior audit file is **truncated
mid-G1 on disk**, so the warrior rows lean on `desks/warrior-rotfix/journal.md` for the
gap list, and the warrior checklist inherits that dependency.
