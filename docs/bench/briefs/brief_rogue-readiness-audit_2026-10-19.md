# Brief: rogue-readiness-audit (HELD — dispatch AFTER fix-engine + fix-guides reconcile, 2026-10-19)

## Objective (dispatch only when both fix lanes are reconciled)
Deep read-only audit of the ENTIRE app to prep the full `classes/rogue.lua` implementation: architecture readiness, not bug-hunting (the hunter/proctor lanes own defects/coverage — extend them, never re-derive). Output: NEW file `bench/rogue_readiness_2026-10-19.md`.

## Questions
1. Class-module contract: what every `classes/*.lua` must provide (colors/procs/defaults keys, `gather_guide_inputs` frozen-spec, `on_bar_update`, `on_spellcast_event`, combat-enter/exit) — file:line-anchored checklist a rogue module must satisfy, incl. which parts are convention vs harness-pinned (`tests/*_state.lua`, `guide_contract.lua`, wiring floors).
2. Guide-engine fit: does `nextaction.lua`'s decision model + `nextaction_ui.lua` frame cover rogue's needs (energy/CP/SnD/rupture windows, HOLD/RIDE equivalents), or where does it strain? Name the smallest extension shape.
3. TOC/options/HUD/practice wiring a sixth class must touch (every flavor TOC in load order, `config_presets.lua` defaults, `option_tables.lua` toggles nil-safe, HUD slots, practice scenarios) with the exact file list.
4. Post-fix integration: re-read the two fix-lane buildouts and mark anything in 1–3 that changed; unresolved hunter/proctor items that constrain rogue design (CLEU R1, secret-regime M5, unknown-input M6) called out as build prerequisites.
5. Sequenced build plan: rogue module broken into 2–4 disjoint implementable slices with per-slice scope, pins, and validation.

## Boundary
READ-ONLY except the one new bench file + own desk journal/signals. No code edits. Held for post-fix dispatch so the audit reads the fixed tree.

## Workshop mechanics (mandatory — skills: bench-read, desk-open, desk-journal, signal-write)
bench-read first (`desks/journal.md`, both fix-lane buildouts, `bench/rogue_research_2026-10-19.md`, `bench/rogue_deep_2026-10-19.md`, `bench/feature_hunter_audit_2026-10-19.md`, `bench/feature_proctor_audit_2026-10-19.md`, `bench/lessons.md`); desk-open `desks/rogue-readiness/`; journal + `done` signal.

## Validation owner
- Orchestrator: checklist complete with file:line anchors, extension shapes minimal, build slices disjoint with pins.
