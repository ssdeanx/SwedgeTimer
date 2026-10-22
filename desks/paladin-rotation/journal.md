# Paladin Rotation Audit — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Compare SwedgeTimer paladin rotation (twist + next-action guide) against wowsims sims per client; find gaps and hidden techniques.
- **Scope:** Read-only over classes/paladin.lua, twist.lua, nextaction.lua, tests/twist_state.lua, tests/nextaction_state.lua, tests/paladin_state.lua. wowsims sources: sod, forever, classic, tbc-new, wowsims.github.io. No addon edits, no git, no bench overwrites.
- **Next step:** Read our six files, then locate wowsims paladin sim/rotation code, then write bench/paladin_rotation_audit_2026-10-19.md with per-client MATCH/GAP/CONFLICT + file:line + sim source.

## 2026-10-19 — Audit done
- **Worked on:** Read all six in-scope files; fetched sim rotation code from wowsims/sod, classic, tbc-new, forever (retribution.go, retribution_test.go, APL JSONs, classic soc.go, forever seal_of_command.go + twist_of_light_test.go). wowsims.github.io verified as Vite template with no sim code.
- **Current state:** bench/paladin_rotation_audit_2026-10-19.md written (NEW, no overwrite). Per-client verdicts: Era MATCH + 2 low GAPs; SoD 1 medium CONFLICT (200ms vs 0.4s) + 2 medium GAPs; TBC MATCH core + 1 medium CONFLICT (CS pull timing) + filler-default CONFLICT; Wrath guide-level MATCH only (no in-scope sim); Retail inert MATCH; Forever 1 medium CONFLICT (Echo vs swing timing) + Holy Strike GAP. 6 ranked hidden techniques.
- **Next step:** Orchestrator validates; no addon files touched, no git ops.

## 2026-10-19 — [signal:done] Paladin rotation audit on the bench
- bench/paladin_rotation_audit_2026-10-19.md; validation owner: orchestrator.
