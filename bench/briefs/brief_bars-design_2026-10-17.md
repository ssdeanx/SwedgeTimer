# Brief: bars-design — build-out round 1
Date: 2026-10-17. Orchestrator-issued, round plan approved in desks/journal.md.

## Read first (all verified on disk)
desks/bars-design/journal.md · desks/journal.md (decisions) · bench/verify_bank.md (C3/C6, D3 rows — BINDING) · bench/discover_features.md (#17 row) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
bars.lua, designmode.lua, design.lua, tests/designmode_state.lua, tests/design_state.lua. NOT tests/bars_state.lua (class lanes changed its frame counts; it is reconciled in a later wave — report your new frame/texture counts in your bench report instead). NOTHING else: no class files, no tocs, no run.sh, no hud.lua, no lint config.

## Task
- **C3 unified swing-safe overlay service, ADDITIVE**: expose a small registration API (register(zone_id, draw_fn, priority) → handle) that can host clip/slam/twist-style bands. Keep the existing band drawing 100% working — this round registers new consumers only; do NOT refactor existing call sites beyond the minimum. Differentiator note (verify_bank §6.4): registered-service model beats SuperSwingTimer's hardcoded consolidation.
- **C6 design-mode registration + snap templates**: every new widget registers as a design target so design mode can select/move it; add snap-to-row templates for stacked layouts.
- **D3 pips widget (generic contract, frozen for the parallel druid lane)**: factory `new_pips(parent, opts)` returning a frame exposing `set(count)` for 0–5 and `glow_full(bool)`; 5-rect row, gold pulse at 5 (standard: Wago feral packs, verify_bank D3 row). Druid lane (parallel) codes against THIS contract — match it exactly, report the final installed signature in your bench report.
- **Mouse anchoring** (discover #17, Gnosis-style): anchor bars/frames to mouse in design mode; default OFF toggle.

## Cross-client rules
Never gate on st.is_mainline alone (Forever is mainline-code) — probe via st.api. st.api.get_time() for precise timing. New toggles nil-safe (`== false` hides, nil = off), defaults documented; no default-visible change without explicit gate. Minimal in-place edits, preserve formatting/line endings, no `_` renames, no unused-variable work (owner directive).

## Validation (run yourself)
bash tests/run.sh — all green (33 steps). luacheck 0 errors. Mutation proof: copy repo to /tmp/opencode/mut_bars-design/, break one new guard, show the check fails, restore; cite output. Extend tests/bars_state.lua, designmode_state.lua, design_state.lua — never weaken.

## Deliverables
Code in scope · desks/bars-design/journal.md entry (worked on / current state / next step) · signal JSON in desks/bars-design/.signals/ (subtype done|blocked) · bench/buildout_bars-design_2026-10-17.md (changes, evidence, option defaults list, UNCONFIRMED items). Final reply ≤6 lines. NEVER run git.
