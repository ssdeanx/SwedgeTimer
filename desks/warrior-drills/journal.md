# warrior-drills — Journal

## 2026-10-19 — Desk opened
- **Purpose:** the warrior's rotation scenario + its own drills + the §2.2 (A)
  class-side feature gaps (the drill-build lane's warrior half).
- **Scope:** ONLY `classes/warrior.lua`, `warrior_guide.lua`,
  `tests/warrior_state.lua`, `tests/warrior_guide_state.lua`. Everything else
  is out (practice.lua, practice_ui.lua, option_tables, config_presets, the
  other classes, main.lua, compat, hud, bars, run.sh, the TOCs, the versions,
  the docs) — the shared engine owns the registration and the panel map.
- **Next step:** read `bench/class_features_drills_2026-10-19.md` §2.2, then
  implement the orchestrator's three surfaces (practice_rotation,
  practice_scenario_step, practice_drills) and close the class-side gaps.

## 2026-10-19 — The three surfaces landed, the class gaps closed or filed
- **Worked on:** (1) `ST.WARRIOR.practice_rotation` — the engine's compiled
  rule order, every line carrying its sim source (13 entries: op, execute,
  slam, sunder, rend, bt, ww, raging_blow, bladestorm, ms, hamstring, hs,
  cleave). (2) `ST.WARRIOR.practice_scenario_step(self, ctx)` — the engine's
  pick through the SAME path the live guide uses (so the practice pick and
  the live pick can never disagree), `{ action, reason }` or nil (a HOLD/RIDE
  is "no press to make" → the engine grades it unknown, never a wrong press).
  (3) `ST.WARRIOR.practice_drills` — the four audited drills
  (`warrior_core_order`, `warrior_ww_delay`, `warrior_sunder_upkeep`,
  `warrior_execute_burn`), each grading ONE decision and answering nil when
  it cannot judge. The rage state is the shared model's
  (`st.practice.rage_can_spend` / `new_rage_state` / `WARRIOR_RAGE_COSTS`),
  read-only, not a placeholder. The audit's run-level band tables live in
  `warrior_guide.lua` as pure helpers so the engine can aggregate a run
  without the class owning the run state.
- **Class gaps:** W-06 (the Overpower stance gate) **CLOSED** — the classic,
  sod and tbc-new sims all register Overpower with a Battle-stance
  requirement, so the stance is now read from the client's own stance aura
  (the sim's ids: Battle 2457, Defensive 71, Berserker 2458 — fetched
  2026-10-19) in the EXISTING aura walk (no new client read; the form index
  stays UNCONFIRMED) and the Overpower/Execute rules withhold a known stance
  outside the sim's set. An unknown stance withholds nothing. **Visible
  behaviour change** (fewer false prompts for a spell the client refuses) —
  see the operator note below. W-08 (the Execute rage drain) **CLOSED** — the
  classic sim spends the whole pool and the tbc-new sim spends the capped
  extra, so the pool after Execute is empty; modelled as
  `st.warrior_guide.rage_after_execute`. W-20 (Devastate 25212) **FILED**
  with the reason (the sim line is CONFIRMED — the tbc-new FURY APL: the
  Delay Check + `currentRage > 60`, below the Heroic Strike line, both
  on-next-attack, so it is unreachable in our rule order; it also needs a
  DW/2H read and a TBC arms branch that do not exist, plus a slot the HUD
  lane's suite pins).
- **Filed for other lanes:** F-1 the warrior panel still runs the SHARED
  twist session (`practice_ui.lua:636` `PRACTICE_DRILL_KEYS.WARRIOR =
  "paladin_twist"`) — the map must point at a warrior key
  (`warrior_core_order`), the engine lane's file; F-2/F-3 the shared
  registration + the per-class map shape (§4.2 of the spec); F-5 the options
  lane. The audit's note ("the warrior's mastery row is the twist drill") is
  therefore resolved on the class side (the warrior owns four drills of its
  own) and filed on the engine side (the map entry).
- **Current state:** warrior_state 1148 checks, warrior_guide_state 1705
  checks, both green; luacheck 0/0 on the four lane files; line endings kept
  (the two .lua files CRLF, the two suites LF); 27/27 mutations killed on a
  /tmp/opencode/mut_warrior copy (the tree restored byte-identically).
  Full harness: 41 steps, 3 failed — the three failures are the parallel
  class lanes' in-flight edits in other classes' files
  (`tests/hunter_state.lua` the trap-id count, `tests/druid_state.lua` the
  shift/Roar drill bands, `tests/hunter_guide_state.lua` the Serpent known
  read). `tests/wiring_check.lua` PASSES (the class's three surfaces are read
  by the shared engine, not dead hooks). No warrior file is in any failing
  step.
- **Next step:** orchestrator validation + the in-client checklist (the stance
  auras: does the client report Battle 2457 / Berserker 2458 / Defensive 71
  on the player, and does Aggressive Stance need an id; the Execute drain in
  the burn drill; the TBC sunder/HUD mirror stays filed).

## 2026-10-19 — [signal:done] handed to the orchestrator
- The three contract surfaces + the four drills + the stance gate + the
  Execute drain, in scope only; pins green; 27/27 mutations killed; the
  harness's warrior steps and wiring_check are green (the three failing steps
  are the parallel class lanes' in-flight edits in the hunter and druid
  files).
- **Operator note (visible behaviour change):** the Overpower and Execute
  prompts now respect the sims' stance requirements on the Era (incl. SoD)
  and TBC families. A player standing in a non-Battle stance no longer sees
  an Overpower prompt (the client refuses the cast) and a player in Defensive
  stance no longer sees an Execute prompt. Every other family is untouched,
  and an unknown stance (no stance aura, or Aggressive Stance, which has no
  cited id) keeps today's behaviour. If the operator wants this behind a
  gate, the two `stance_allows_*` verdicts are the single seam to flip.
