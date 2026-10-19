# Brief: feature-proctor-audit (2026-10-19)

## Objective
Read-only test-sufficiency audit of the current feature set for casual + top-level play. Focus: behavioral coverage, regression risk, high-value test gaps. Produce `bench/feature_proctor_audit_2026-10-19.md`.

## Scope (read-only)
- Audit surface (read, do not edit): `tests/run.sh`, `tests/smoke.lua`, `tests/toc_check.lua`, `tests/twist_state.lua`, `tests/weave_state.lua`, `tests/nextaction_state.lua`, plus feature files `main.lua`, `bars.lua`, `compat.lua`, `swing_source.lua`, `twist.lua`, `weave.lua`, `nextaction.lua`, `classes/druid.lua`, `classes/hunter.lua`, `classes/paladin.lua`, `classes/shaman.lua`, `classes/warrior.lua`, `hud.lua`, `practice.lua`, `enemy_swing.lua`. Reference paths/lines.
- Question: what behaviors that matter in-client (split-second timing, per-client branches, combat-enter/exit, lib-missing fallbacks, Retail stand-in vs Forever engine) have NO offline pin, and which gaps are highest-value to close before owner testing?

## Context (read first)
- `desks/journal.md` (35 steps 0 failed; next = owner in-client test, nothing further provable offline), `bench/lessons.md`, `bench/oracle_audit_2026-10-17.md`, `bench/verify_bank.md`, `hands-up.md`, `TESTING.md` checklist (read for what the owner will cover in-client so you don't duplicate it — propose only offline-closable gaps).
- Standing: no code edits, no git, no lint-config changes. New-check proposals only (no implementation); any probe runs on /tmp/opencode copies.

## Method
- Map feature → existing offline pin (harness step / state suite / smoke profile / luacheck) → gap. Call out: uncovered per-client branches (Era/SoD, TBC, Titanforge, Forever, Retail), uncovered timing edges (twist lag calibration, weave Maelstrom/haste, next-action HOLD/RIDE, enemy-swing hostile path, weave_range exact-vs-band), uncovered fallback paths (5s deadline, LRC fallback, secret fallback, stand-in notice).
- Rank gaps by (regression risk × top-level impact × offline-testability). Each gap: behavior, why it matters at ms scale, what pin would look like (harness step or state-suite case), evidence label.
- Do NOT overlap hunter lane (proctor = coverage/gaps; hunter = error paths). One-line pointer if you spot an error-path issue.

## Boundary
- READ-ONLY except one new bench file + own desk journal/signals. Output: `bench/feature_proctor_audit_2026-10-19.md` (NEW file). Never overwrite.

## Workshop mechanics (mandatory)
1. `bench-read`: journals before artifacts.
2. `desk-open`: ensure `desks/feature-proctor/` exists; resume if live.
3. `desk-journal`: append entry at end.
4. `signal-write`: emit `done` JSON + journal marker.

## Validation owner
- Orchestrator reconciles against hunter findings; checks every gap has feature→pin→gap mapping + rank + proposed pin shape, and no duplication of TESTING.md in-client steps.
