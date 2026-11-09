# rogue_rotation_gaps_closed_2026-10-19 — engine-side closure + filed follow-ups

Desk: rogue-rotfix. Spec: bench/rogue_rotation_audit_2026-10-19.md (wowsims sims).
Scope: classes/rogue.lua, rogue_guide.lua, tests/rogue_state.lua,
tests/rogue_guide_state.lua ONLY. No other file touched (verified: full-tree
luacheck floor 2/0 held; guide_contract/rotationtext/options_load all green).

## Closed in-engine (behavioral, nil-safe, tested)

| Audit | Change | Where |
|---|---|---|
| F0/H1 core | SnD upkeep verdict + 1b rule (missing prompts, TBC min-CP 2 from the 10 s minimum, per-CP durations [9,12,15,18,21] as data). Slot-less ("snd", icons filed) | rogue_guide.lua + gather |
| E-C1/H2 | Finisher spine split: ERA Eviscerate-first; TBC/WRATH/FOREVER rupture-first | FINISHER_MODES + rule 5 |
| T-C1 | Dying dump split: ERA any-CP/8, TBC 5CP/5, WRATH 4CP/4, FOREVER 3CP/6 | DUMP floors + rule 4 |
| T-M1/H5 | Pool bands: TBC single 71, FOREVER 65/75, ERA/WRATH 65/85 kept | POOL_BANDS |
| E-G1 | ERA sweaty spend override at 79+ (visual 0.5 s widening filed) | SWEATY_SPEND + rule 7 |
| T-G2/E-G4/V-G2/H4 | EA windows per family: ERA 3, TBC 6, WRATH 3, FOREVER 16 | EA_REFRESH_BY_FAMILY |
| T-G3/H9 | Rupture recast-when-missing on TBC/FOREVER (window 0); ERA/WRATH 4 | RUPTURE_REFRESH_BY_FAMILY |
| V-G3/W-G2 | Planned-CP floors: FOREVER 3, WRATH 4 (ERA/TBC 5) | FINISHER_MIN_CP_BY_FAMILY |
| E-G3/T-G5/V-G4/H10 | Tea lines per family: ERA 29, TBC 30, WRATH 40, FOREVER 15 | TEA_ENERGY_MAX_BY_FAMILY |
| T-G4/H7 | Shiv family gate ERA+TBC (Mutilate/EA-context filed) | SHIV_FAMILIES + rule 2 |
| F3/H11 core | AR verdicts (ERA <59+tick<1, TBC 40, WRATH 50, FOREVER 50 w/ SnD) + BF verdict (SnD ride + EA-healthy-on-duty), rules 5b/5c, slot-less | ar/bf_verdict + gather |
| F1/H12 minimal | Builder chain Saber Slash > Mutilate > dagger Backstab > SS via client spell data (Hemo excluded as uncertain); CP/stack/rune APL gating filed | resolve_builder_entry |
| F2 residual | AR-aware tick: +40 re-anchors while AR rides (spark + predictor) | TICK_AR_ENERGY + sample |
| S-C1 partial | SOD Envenom-primary data + verdict ship (unreachable until SoD detection lands — filed); ERA evisc-first already stops SoD Rupture prompts | ENVENOM_RULES.SOD |
| MATCHes | E-M1/T-M2/T-M3/V-M1/V-M2/W-M1 + E-G4 pinned (no behavior change) | tests |

Suites: rogue_guide_state 433/0 (was 251), rogue_state 385/0. 13/13 mutation
kills proven on /tmp/opencode/mutwork copies (script + log with operator).

## Filed follow-ups (need files outside this lane's scope — reason each)

1. Guide icons for snd/ar/bf (slots 8-10) + guide_contract 7-slot pin update +
   nextaction_ui mapping. Reason: contract frozen for this lane; slot-less
   actions ride NOW + rotation label meanwhile.
2. Options widgets + config_presets defaults for snd/ar/bf thresholds and
   upkeep rows. Reason: options_load three-way contract (db key ⇒ widget +
   default); this lane added zero db keys deliberately.
3. SoD detection (compat family token or rune probe) to reach ENVENOM_RULES.SOD
   + 4CP lines + Poisoned Knife + Vanish→Envenom + CttC. Reason: no SoD family
   token exists; needs compat + options.
4. H6: TBC 15 s EA minimum + pool-for-EA wait + Forever finisher lockout.
   Reason: new rule semantics needing APL-literal design + options; not safely
   separable here.
5. Shiv Mutilate-known + EA-context gating. Reason: provider-side design +
   in-client proof, filed to keep this lane's gate minimal and safe.
6. Eureka-25 Tea + SoD 10-or-40-end Tea. Reason: need detection probes.
7. Cold Blood / Tricks / Venom (1310703) / Killing Spree / HfB / Overkill /
   Vanish prompts. Reason: need slots + design (same filed icon wiring as #1).
   **CORRECTED 2026-10-20 (desk `corpus-corrections`):** the third name used
   to be "**Riposte**" — 1310703 is **Venom** on the Forever client
   (`bench/rogue_apl_utility_build_2026-10-20.md` §3.8;
   `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **R7**).
8. Wrath 2-4CP Rupture durations + glyph + Forever fight-end exclusion + CttC
   interplay. Reason: only 2 of 5 rows sim-sourced; no sim rule consumes them.
9. Sweaty 0.5 s visual widening. Reason: needs in-client proof (audit direction).
10. Retail sim verification. Reason: no retail sim repo in the brief set.
11. Crossfire (not mine): warrior_state (HS table), shaman_guide_state (weave
    slots) and wiring_check (warrior is_hamstring hook) fail on files modified
    09:51-09:54 by parallel lanes; all rogue wiring lines are ok. Reconcile
    owns the re-green.
