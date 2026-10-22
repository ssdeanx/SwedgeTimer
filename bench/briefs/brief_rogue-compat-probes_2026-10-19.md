# Brief: rogue-compat-probes (2026-10-19)

## Objective
Close the cues-lane residual: move rogue's raw client probes into `compat.lua` as `st.api.*` wrappers (AGENTS.md cross-engine rule: never call a cross-client API outside compat). Writer lane.

## Scope (ONLY these files)
- `compat.lua`: NEW wrappers (pcall/rawget-safe, family-gated, nil when absent — mirror existing wrapper style `:205-274` spell/cooldown + `:993-1087` family-spell-id): weapon-enchant read (presence probe), item count, item cooldown, item info, unit guid (only if not already wrapped — grep first). Keep the wrappers dumb and shape-stable; no behavior.
- `classes/rogue.lua`: replace the local `rawget(_G, ...)` probe block (`:57-64` region per grep) with `st.api.*` calls; keep every behavior/copy identical; the throttled cold-book retry logic stays in the class module.
- Tests: extend `tests/secret_guard_state.lua` (control/secret/throwing/absent pairs for the new wrappers, bite proofs) + adjust `tests/rogue_state.lua` pins if any read the old probe shape + `tests/smoke.lua` profile assertion only if a wrapper is family-gated.
- Explicitly OUT: `config_presets.lua`, `option_tables.lua` (options lane owns — collision), `practice.lua`, TOCs, version, CHANGELOG.

## Rules
No git. No lint-config. Wire-not-strip. Touched-lines whitespace. CRLF preserved (`classes/rogue.lua` + `compat.lua` are CRLF — verify). Harness green + floor + mutations on /tmp/opencode copies. A parallel options lane runs concurrently with disjoint files — transient harness flap from its half-landed edits is expected; never edit outside scope to "fix" it.

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write)
bench-read (journal, review-readiness §4 residuals incl. compat rule, cues-lane journal `desks/rogue-cues/journal.md`, lessons); desk-open `desks/rogue-compat/`; journal + `done` signal (files + harness result).

## Validation owner
Orchestrator: grep proves zero raw `rawget(_G,` client probes remain in `classes/rogue.lua`; wrappers nil-safe on absent globals; harness green; mutations bite.
