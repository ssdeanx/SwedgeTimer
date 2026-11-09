# Warrior rotation scenario + drills + feature gaps — 2026-10-19

Desk: warrior-drills. Lane scope: `classes/warrior.lua`, `warrior_guide.lua`,
`tests/warrior_state.lua`, `tests/warrior_guide_state.lua` (nothing else).
Spec: `bench/class_features_drills_2026-10-19.md` §2.2 (the warrior section)
+ the orchestrator's fixed interface contract.

## 1. What landed

### 1.1 The three contract surfaces (the shared engine looks them up by player_class)

| Surface | Shape | Where |
|---|---|---|
| `ST.WARRIOR.practice_rotation` | the rotation table in the engine's compiled rule order; every entry carries `action`, `reason`, `source` (the sim citation) and `families` (the client families whose APL carries the line) | `classes/warrior.lua` (the practice section) |
| `ST.WARRIOR.practice_scenario_step(self, ctx)` | `{ action = "<spell key>", reason = "<short text>" }` or **nil** (the engine grades "unknown", never a wrong action) | same |
| `ST.WARRIOR.practice_drills` | the four audited drills, each `{ key, label, kind, title, description, grade = function(self, ctx) }` | same |

The decision engine is the one the live guide already uses
(`st.warrior_guide.evaluate` through `ST.WARRIOR.guide.evaluate`, so the
composite rage gate applies): the practice pick and the live pick can never
disagree.

**The context the engine feeds** (documented in the class header):
`now`, `last_action` (the player's last press, as an action key),
`resources` (rage, hs_cost, cleave_cost, bt_cost, ww_cost, target_health_pct,
execute_pct, hs_queued, cleave_queued, has_bloodsurge, slam_casting,
overpower_remaining, swing_remaining, gcd_remaining, hs_rage_floor,
core_reserve_window, execute_spam, sunder_stacks, sunder_remaining,
rend_remaining, rend_upkeep_enabled, hamstring_known,
hamstring_rage_threshold, sudden_death, victory_rush, stance,
phase_started_at — the optional execute-phase crossing) and `cooldowns` (bt,
ww, op, execute, slam, hs, cleave, raging_blow, ms, bladestorm). Every reading
is optional; an unknown reading stays absent and the engine withholds.

**The scenario step answers nil** whenever the engine has no action — a HOLD
or a RIDE means "no press to make", so the engine grades it as unknown rather
than as a wrong press. The four drills grade ONE decision each and answer nil
when they cannot judge it.

### 1.2 The rotation table (sim priority order, every line cited)

The engine's rule order (`warrior_guide.lua`'s matrix) is the compiled table
(the audit's own words). The sources, fetched 2026-10-19 from the wowsims
master branches:

| # | action | source |
|---|---|---|
| 1 | `op` | classic `sim/warrior/overpower.go` (OverpowerAura 5 s, `ExtraCastCondition = OverpowerAura.IsActive()`, Battle stance only); sod `sim/warrior/overpower.go` (the same + the Taste for Blood rune); tbc-new `sim/warrior/overpower.go` (`ExtraCastCondition = StanceMatches(BattleStance)`); the Era APL fires Overpower through `autocastOtherCooldowns` before its Execute line; the tbc-new fury APL's Overpower Weaving group casts Battle Stance (2457) before Overpower (11585) |
| 2 | `execute` | classic `sim/warrior/execute.go` (`ExtraCastCondition = sim.IsExecutePhase20()`, `BattleStance\|BerserkerStance`, the cast spends the whole pool: `600 + 15*extraRage`); tbc-new `sim/warrior/execute.go` (`StanceMatches(Berserker\|Battle) && IsExecutePhase20()`, `925 + 21*extraRage`); the tbc-new fury APL casts 25236 when `isExecutePhase E20` |
| 3 | `slam` | classic `sim/warrior/slam.go` (11605, cost 15, a 1.5 s cast, `StopMeleeUntil(..., true)` = the cast resets the swing); Blood Surge 46916 (Wrath) / 413399 (the SoD rune) |
| 4 | `sunder` | the tbc-new fury APL's Sunder Armor group: `castSpell 25225` when the stacks are below 5, or the debuff has 10 s or less left (the same group in the arms APL) |
| 5 | `rend` | the arms Rend upkeep (47465, a 15 s debuff) + the SoD Rend (11574 with the Blood Frenzy rune 412507, operator-confirmed in-client 2026-10-19) |
| 6 | `bt` | classic `sim/warrior/bloodthirst.go` (23894, cost 30, a 6 s cooldown); the tbc-new fury APL casts 30335 above its Whirlwind line |
| 7 | `ww` | classic `sim/warrior/whirlwind.go` (1680, cost 25, a 10 s cooldown); the tbc-new fury APL gates Whirlwind (1680 tag1) on `spellTimeToReady 30335 >= 1.5 s` (the Delay Check) |
| 8 | `raging_blow` | the SoD rune Raging Blow 402911 (costs no rage) |
| 9 | `bladestorm` | the arms Bladestorm (63784; the 90 s swipe fallback still needs in-client confirmation) |
| 10 | `ms` | the arms Mortal Strike (the Taste for Blood affected-spells list; a 6 s filler) |
| 11 | `hamstring` | the Era line is 7373 above 80 rage; the TBC line is **25212** (the TBC Hamstring) in the tbc-new fury APL. **CORRECTED 2026-10-20** (desk `corpus-corrections`): this cell used to read "the tbc-new fury APL casts 18499 when the Delay Check holds and Improved Hamstring (20500) is known" — that is the shipped `classes/warrior.lua` citation, and it is **wrong**: **18499 is Berserker Rage** (`wowsims/classic sim/warrior/berserker_rage.go:14`), and 20500 is the Improved Hamstring **buff** the APL only tests for; the TBC APL's Hamstring row is **25212** (i=19). Evidence: `bench/warrior_apl_utility_build_2026-10-20.md` §1/§4; `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **W1**/**W4** |
| 12 | `hs` | classic `sim/warrior/heroic_strike_cleave.go` (the queue needs rage >= the cost); the tbc-new fury APL casts 29707 tag1 at one target with `currentRage >= 40` outside the execute phase |
| 13 | `cleave` | the tbc-new fury APL casts 25231 tag1 (Cleave rank 5) above one target with `currentRage >= 40`; the Era APL casts 20569 tag1 rank 5 |

### 1.3 The four drills (the audited target set, §2.2 (C))

| key | kind | per-decision grade |
|---|---|---|
| `warrior_core_order` | rotation_order | S = the engine's own pick; **F** = a spend that starved a core sitting inside the reserve window (the audit's hard F); D = any other mis-pick; nil = no press / an undecidable state |
| `warrior_ww_delay` | rotation_window | the Whirlwind press only (the sim's Delay Check): the margin `bt_remaining - 1.5` banded S (>= 1.0 s) / A (>= 0.5) / B (>= 0.2) / C (>= 0) / D (inside the window); F = Bloodthirst was already ready, or the pool covered neither core (the shared rage model) |
| `warrior_sunder_upkeep` | situational | S/A/B/C/D/F by the stack count the press LEAVES the debuff at (a Sunder application adds one stack, capped at five); F = a press the rotation should have yielded (a proc / the Execute range / a queued ride) or a dropped upkeep; nil = an unknown stack count |
| `warrior_execute_burn` | transition | the phase-entry decision: S = a full pool (100 rage = the classic cap, the same target the registered `warrior_execute` drill uses) within one GCD of the crossing, A = one GCD late, B = two, C = a short pool with a clean burn, D = a short pool with a late burn; F = the core was spent during the phase, or Execute was pressed above the threshold; nil = an unknown target health, or a state where the engine is holding the core (the TBC reservation) |

The rage state is the shared model's (`st.practice.rage_can_spend`,
`st.practice.new_rage_state`, `st.practice.WARRIOR_RAGE_COSTS` — read-only
here), not a placeholder. The run-level band tables (the audit's [DESIGN]
edges) live in `warrior_guide.lua` as pure helpers
(`core_order_band`, `ww_delay_band`, `sunder_upkeep_band`,
`execute_burn_band`) so the shared engine can aggregate a run the audit's
way without the class owning the run state.

**The interpretation notes** (the audit's bands are [DESIGN], not sim facts):
- D-W3 grades the stack count the press LEAVES the debuff at. The sim's own
  upkeep line fires below five stacks, so a sim-exact re-stack (at four
  stacks) leaves five and grades S. The audit's raw wording ("re-stacked at 5
  stacks ... A = 4 stacks") would have graded the sim-exact press an A; the
  table is implemented so the sim-aligned play is the S.
- D-W4's lateness is optional: without a `phase_started_at` reading the pool
  band alone decides (S full / C short). The pool at the press stands in for
  the pool at the crossing (the pool regenerates slowly).

## 2. The §2.2 (A) feature gaps — closed / filed

| # | Feature | Disposition | Evidence / reason |
|---|---|---|---|
| **W-06** | Overpower **stance gate** (Battle-only) | **CLOSED** | The classic, sod and tbc-new sims all register Overpower with a Battle-stance requirement (classic/sod `RegisterSpell(BattleStance, ...)`, tbc-new `ExtraCastCondition = StanceMatches(BattleStance)`), and the tbc-new fury APL casts Battle Stance (2457) before Overpower (11585). The stance is now read from the client's own stance aura (the sim's ids: Battle 2457, Defensive 71, Berserker 2458 — `wowsims/classic sim/warrior/stances.go`, fetched 2026-10-19) in the EXISTING aura walk (no new client read, no form index — the per-family form map stays UNCONFIRMED). The Overpower and Execute rules withhold the prompt on a known stance outside the sim's set; an unknown stance withholds nothing, and the provider feeds the stance only on the families whose sims carry the requirement (ERA incl. SoD, TBC). Aggressive Stance has no cited id → unknown → nothing withheld (in-client confirm owed). **This is a visible behaviour change** (fewer false prompts for a spell the client refuses to cast) — flagged for the operator in the desk journal. |
| **W-08** | Execute **drains the rage pool** | **CLOSED** | The classic sim spends the WHOLE pool (`extraRage := CurrentRage()` then `SpendRage(extraRage)`, damage `600 + 15*extraRage`) and the tbc-new sim caps the extra rage at `maxRage - cost` and spends that too (`925 + 21*extraRage`). The pool after Execute is therefore empty on the draining families. Modelled as the pure helper `st.warrior_guide.rage_after_execute(rage, cost, drains_all)` and consumed by the execute-burn drill (the burn empties the pool). |
| **W-20** | Devastate (TBC DW-arms rage > 60 filler) — **the id 25212 is NOT Devastate** | **FILED (with the audit's figure corrected; the id's NAME corrected 2026-10-20)** | The sim line is CONFIRMED — the tbc-new **fury** APL: `castSpell 25212` when the Delay Check holds (Bloodthirst 30335 >= 1.5 s AND Whirlwind 1680 >= 1.5 s) and `currentRage > 60` (the audit's "rage > 60" figure comes from the FURY APL; the **arms** APL's Devastate line is `DW Arms` + the Delay Check + `currentRage >= 40`). **CORRECTED 2026-10-20** (desk `corpus-corrections`): this row used to be headed "Devastate **25212**" — **25212 is the TBC Hamstring**, not Devastate; the Devastate row's own id is **not sourced in the corpus** (UNCONFIRMED — do not build on 25212 for it). Evidence: `bench/rotation_gap_vs_apl_2026-10-20.md` §0.3 ("25212 is Hamstring in TBC") and §0.0 **W4**. It is not implementable in our engine as a live rule: (1) it sits BELOW the Heroic Strike line in the same APL, and both are on-next-attack abilities in our engine (the HS dump already covers the role), so a rule placed above HS would prompt a spell the sim never prefers there; (2) its own conditions need the DW/2H read (the APL's "DW Arms" is the Slam cast time > 0.5 s — no reader in tree) and a TBC arms branch (our TBC set is the fury set: op/execute/slam/hs/bt/ww/sunder); (3) a slot would be needed (the TBC guide set is at 7 of the 8 the contract allows) and the HUD mirror is pinned by `tests/hud_state.lua` (another lane's file). Filed for a TBC-arms lane. |
| W-15 | Forever Rend toggle | FILED (unchanged) | the rule exists and is dormant on Forever; the toggle + its options widget live in `option_tables.lua` / `config_presets.lua` (out of this lane's scope) |
| W-17 | SoD stance-dance aura 426969 | FILED (unchanged) | UNCONFIRMED id — in-client confirmation owed before the rule can be armed |
| W-19 | Victory Rush (Forever) | FILED (unchanged) | operator SKIP (no Forever APL line; the sims never kill the target) |
| W-21 | Sunder/Rend/Hamstring **HUD mirror** | FILED (unchanged) | the TBC HUD row is pinned at eight slots by `tests/hud_state.lua` (the HUD lane's file); the guide slots already ship |

## 3. Filed for OTHER lanes (out of this lane's scope)

| # | Item | Where | Why |
|---|---|---|---|
| F-1 | **The warrior panel still runs the SHARED twist session** — the audit's note (the warrior's progression mastery row is the paladin twist drill, not a warrior drill) | `practice_ui.lua:636` (`PRACTICE_DRILL_KEYS.WARRIOR = "paladin_twist"`) | `practice_ui.lua` is the shared engine's file (the sibling lane owns it). The warrior now owns its own drills, so the map entry should point at a warrior key — `warrior_core_order` (the core rotation, the natural mastery row) with the scenario `warrior_rotation` alongside it. The map change itself is the engine lane's. |
| F-2 | Registering the four drills + the `warrior_rotation` scenario in the shared registry | `practice.lua` (`H.register_scenario`) | the shared engine registers the class's drills (the contract's surfaces are the class's side only; this lane registers nothing) |
| F-3 | The per-class practice map must change shape | `practice_ui.lua:630-637` / `practice_progress.lua` | §4.2 of the spec: `class -> { scenario = <key>, drills = { <key>, ... } }` |
| F-4 | The HUD mirror for a Devastate slot (if a TBC-arms lane builds it) | `classes/warrior.lua` HUD sets + `tests/hud_state.lua` | the HUD row is pinned by another lane's suite |
| F-5 | The Forever Rend toggle + the stance/threshold options | `option_tables.lua` / `config_presets.lua` | the options lane |

## 4. Verification

- `tests/warrior_state.lua`: **1148 checks, 0 failed**.
- `tests/warrior_guide_state.lua`: **1705 checks, 0 failed**.
- `tests/wiring_check.lua`: **PASS** (564 checks) — the class's three surfaces
  are data/hooks the shared engine reads, not dead hooks, so the check is
  satisfied without a dispatch site of their own.
- Full harness: **41 steps, 3 failed** — the three failures are the parallel
  class lanes' in-flight edits in OTHER classes' files
  (`tests/hunter_state.lua`: the trap-id count; `tests/druid_state.lua`: the
  shift/Roar drill bands; `tests/hunter_guide_state.lua`: the Serpent known
  read). **No warrior file is in any failing step**, and the earlier
  `wiring_check` crossfire (the sibling lanes' unwired
  `practice_rotation_for` / `practice_context` hooks) is resolved.
- luacheck: the four lane files are **0 warnings / 0 errors** (the tree's
  5 warnings are in the sibling lanes' files — `classes/rogue.lua`,
  `compat.lua`, `main.lua`, `tests/practice_state.lua`,
  `tests/practice_ui_state.lua`; the floor was 2 before this wave).
- Line endings preserved: `classes/warrior.lua` + `warrior_guide.lua` CRLF,
  the two suites LF.
- Mutation proofs: **27/27 killed** on a `/tmp/opencode/mut_warrior` copy
  (both stance gates, both stance verdicts, the Execute drain, every band
  table, the action reasons, the exported constants, the stance read, the
  gather's family scope, the drill list, the scenario step, every drill
  grade, the rotation table's action/reason). The copy is restored
  byte-identically after the run.
