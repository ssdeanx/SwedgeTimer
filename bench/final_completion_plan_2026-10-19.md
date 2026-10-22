# Final completion plan — 2026-10-19 (operator order: right, not fast)

Operator instruction: take the time to get this **right**; keep going until nothing is left
that can be found or built; then it ships. This file is the definition of done for the
pre-publish wave. Items are executed in order; each is verified in-tree by the orchestrator
before the next phase starts (no parallel squeeze — parallel writers are what produced the
crossfire reds all wave).

## Current state (orchestrator-verified)

- Harness **41 steps / 0 failed**, luacheck **2 warnings / 0 errors** (the shipped floor).
- Six classes ship: bars, cooldown HUD, rotation label, next-action guide, practice
  (drills + rotation scenario), designer (design mode), options.
- Gamification: XP / levels / renown, per-drill mastery + tiers, streaks, achievements,
  per-class + global stats, 50-session history, Progress page with sparkline.
- Deep audit (14 findings): F1–F12 closed; F10 in flight; F13 filed (bounded O(n²) trim);
  F14 closed (TOC coverage).

## Phase 1 — land the in-flight wave (running)

| Lane | Owns | State |
|---|---|---|
| wrappers | class drill wrappers → own drill; shaman namespace alias removed | running |
| F10 + engine crash | one shared isolation helper; `SCENARIO_RESOURCE_KEYS` undefined-constant crash (druid/warrior/shaman context path) | running |
| shaman toggles | `hud_show_lightningshield` / `hud_show_searing` widgets + defaults | running |

## Phase 2 — warrior Heroic Strike / Cleave queue drill (operator order)

**The mechanic:** queueing Heroic Strike (or Cleave) makes the offhand swing happen inside a
spell, so the offhand takes the normal **7% spell cap** instead of the **~24% dual-wield
penalty** it would otherwise cost — the reason "queued HS means my offhand never misses".

**Drill:** `warrior_hs_queue` — press HS/Cleave in the window before the offhand swing.
Too early → the ability goes off before the swing (no benefit). Too late → the offhand
already swung and took the penalty. Grades the timing window (S/A/B/C bands).
Cite the sim's offhand logic where wowsims states it; where it does not, mark the drill a
client mechanic (UNCONFIRMED in-client) rather than inventing a sim number.

## Phase 3 — HU-8 hold verdict (one coherent lane: engine + all six classes)

Ruling (hands-up HU-8): **hold is a decision; unknown is not.**
- A class may state a hold explicitly (the contract grows a hold signal).
- Casting during a hold = **illegal cast → F**.
- Doing nothing during a hold = correct (no attempt, no penalty).
- A nil step with no hold statement stays **unknown** → no attempt, never a wrong grade.
Files: `practice.lua` (pure engine: accessor + `rotation_run_decide` + outcome grades),
`practice_ui.lua` (session side), the six class files, their suites.

## Phase 4 — gamification visibility gate (operator request)

The operator explicitly asked for visible levels/XP, so the panel badge + notices are
**operator-gated ON** (default `true`), with the request recorded in code as the gate.
Files: `config_presets.lua` (default), `practice_ui.lua` (gate read), suites.

## Phase 5 — per-class scenario-100% audit (read-only: hunter + proctor, then fix lanes)

For EACH of the six classes, all must hold:
1. Rotation table exists, in sim priority order, every entry cited.
2. `practice_scenario_step` answers from that class's own guide engine (practice teaches
   what the guide teaches).
3. ≥3 distinct drills, each grading a different skill; energy/resource behavior is
   baseline, not a drill.
4. The panel offers the class's OWN drills — never another class's.
5. Grading: correct → S, wrong/out-of-order → F, miss → F, unknown → **no attempt**.
6. XP / mastery / streak / stats move from a real session and persist across reload.
7. Family matrix: Era, SoD, TBC, Wrath, Forever each pinned; Retail degrades loudly.
8. No dead hooks, no cross-class leakage, no unguarded path.
Every failure becomes a fix lane scoped to that class.

## Phase 6 — filed-item closure sweep

Every item filed "with reason" (the audit's ~15 UNCONFIRMED entries + the per-class filed
lists) is re-examined: close whatever is closable with a source; keep the rest filed with a
sharper, testable reason. Read-only research first, then build lanes for the closable ones.

## Phase 7 — final deep audit (hunter + proctor), after every wave

The full sweep again (smells, hidden failures, error risks, call-path traces, per-client API
truth against wow-ui-source), plus the test-sufficiency audit. Gate: zero HIGH findings.

**Operator triage rule (2026-10-20):** fix every **HIGH** finding, and fix **MEDIUM** findings
that are **low risk** (mechanical, behaviour-preserving, covered by a pin). A MEDIUM that is a
behaviour change, a default-visible change, or a design decision is **filed, not built** — with
the reason and the operator's call recorded. LOW findings are filed unless they are one-line
truth fixes in a file the lane already owns.

## Phase 8 — documentation truth pass

- **CHANGELOG** — the whole wave: rotation scenarios + per-class drills, gamification +
  Progress page, the audit fixes, the base-TOC change, the F10 consolidation.
- **TESTING.md** — the new surfaces: scenario session, per-class drills, Progress page,
  designer element list.
- **README** — refresh the feature lines (scenarios, XP/levels/stats, Progress page).
- **bench/practice_gamification_design_2026-10-19.md** — correct §6: this build ships **no
  import/export surface**, so progress is local-only (the spec's export claim was wrong).
- **bench/live_test_script_2026-10-19.md** — the operator's in-client script updated for every
  new surface (scenario, drills, progress, stats, designer).

## Phase 9 — release decisions (operator)

- **Version** — **2.1.1, and it stays 2.1.1 (operator ruling, 2026-10-20).** No bump, no
  skip, no "feature wave ⇒ minor version" reasoning — the operator publishes this as 2.1.1 and
  explicitly rejected a 2.2.0 recommendation. The 8 version fields (7 TOCs + `main.lua`)
  already agree at 2.1.1 and the CHANGELOG's top section is `## [2.1.1]`; nothing may change
  them. (`bench/release_readiness_2026-10-20.md` keeps the superseded recommendation as
  history, with the ruling on top.)
- **Screenshots + project URLs** — operator-supplied (README marks screenshots pending).

## Standing rules for every phase

- Wire-not-strip (never silence with `_`); nil-safe; unknown-hides; no default-visible change
  without an operator gate.
- TBC-name / Era-id with both pinned; per-family behavior pinned; no invented ids or numbers
  (sim/archive cited, else UNCONFIRMED-tagged).
- Mutation proofs on `/tmp/opencode` copies; line endings preserved; no git; no lint-config
  changes; no changes to `Libs/`.
- The orchestrator verifies each phase in-tree (read the code, not the report) before the
  next phase starts.
