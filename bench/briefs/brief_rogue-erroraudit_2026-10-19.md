# Brief: rogue-erroraudit (2026-10-19)

## Objective
Read-only error-path audit of the STABLE rogue surfaces. Findings, not fixes.

## Scope (READ-ONLY except one new bench file + own desk)
Audit these (all landed, none in flight this wave): root `rogue_guide.lua`
(pure engine — unknown-input discipline, per-client rule tables, TTD
boundaries), the five new `compat.lua` `st.api.*` probes (absent/secret/
throwing shapes — locate in-lane), `practice.lua` rogue scenarios +
`H.grade_energy_spend`/`H.grade_ss_after_swing` (nil-tick/nil-swing paths),
the ROGUE options wiring (`option_tables.lua` ROGUE section read-only:
every key↔default↔consumer round-trip), `tests/rogue_guide_state.lua`
(matrix coverage vs the per-client rules).
CONTEXT-ONLY (in-flight lanes own them — read for orientation, grade
nothing, mark anything here PROVISIONAL): `classes/rogue.lua`,
`diag.lua`, `config_presets.lua` cue defaults.
Output: NEW `bench/rogue_erroraudit_2026-10-19.md` (confirm absent at lane
start; supersede-with-pointer if present). No addon edits.

## Method (hunter discipline)
Swallowed failures, false-success shapes, silent fallbacks, hidden retry
exhaustion, weak diagnostics — each finding with file:line + evidence +
player-visible impact (casual vs top-level ms stakes) + UNCONFIRMED where
in-client. Extend, never re-derive: `bench/feature_hunter_audit_2026-10-19.md`
(H1-H6/M1-M7 are closed — verify closure holds for rogue paths, don't
re-audit them), `bench/rogue_deep_2026-10-19.md` §4 handoff.

## Rules
No code edits. No git. Findings carry evidence labels (proven offline /
UNCONFIRMED). Verdict: NEEDS FIXES or ADEQUATE.

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write)
1. bench-read first (journals before artifacts): `desks/journal.md`,
   `bench/rogue_readiness_2026-10-19.md` §4, the audit + buildouts above,
   `bench/lessons.md`, `hands-up.md`.
2. desk-open: `desks/rogue-erroraudit/` (create or resume).
3. desk-journal append + signal-write `done` JSON (verdict + finding count).

## Validation owner
Orchestrator reconciles findings against the in-flight writer lanes; every
finding has file:line + evidence label.
