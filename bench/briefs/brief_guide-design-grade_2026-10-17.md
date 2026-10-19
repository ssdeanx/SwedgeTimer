# Brief: guide-design-grade — next-action + designer enterprise review
Date: 2026-10-17. Orchestrator-issued. Owner bar: enterprise grade, ready for in-game testing.

## Read first (all verified on disk)
desks/guide-design/journal.md · desks/journal.md · bench/buildout_paladin_2026-10-17.md (P3 + CD group) · bench/buildout_bars-design_2026-10-17.md (C3 service, C6 templates, pips signature, mouse anchor) · bench/buildout_practice_2026-10-17.md (design_targets) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
nextaction.lua, nextaction_ui.lua, design.lua, designmode.lua, tests/nextaction_state.lua, tests/design_state.lua, tests/designmode_state.lua. NOTHING else. tests/bars_state.lua is FORBIDDEN (reconcile wave — report counts instead). luacheck reports ZERO warnings in this scope — the job is completeness, not wiring.

## Task — guide correct, designer complete
- Next-action guide: rotation-table correctness per pattern (twist windows, lust overrides via the C2 contract, HOLD/RIDE states); every frame element wired — icons, rotation text, cooldown swipes all update from live state, nothing frozen or placeholder.
- Designer: every widget shipped this round registered as a design target (bars-design C6 + practice design_targets + class additions — audit the registry against what exists); snap-to-row templates apply; mouse anchoring works; design mode moves what it claims to move.
- Hunt for half-wiring: registered targets with no frame, frames with no target, template entries pointing at renamed widgets. Fix in scope; rest in the report.

## Rules
No git, no lint-config, endings preserved. Twist pins in nextaction_state must not weaken. Never gate on st.is_mainline alone. Other lanes parallel (count fails expected — do NOT touch bars_state/hud_state).

## Validation
bash tests/run.sh (your three suites green; only known count pins fail). luacheck 0 errors, still 0 warnings in scope. Mutation proofs on /tmp/opencode copy.

## Deliverables
Code · desks/guide-design/journal.md entry · signal JSON · bench/buildout_guide-design-grade_2026-10-17.md (rotation-pattern verification; target-registry audit table; count deltas; UNCONFIRMED in-client items). Final reply ≤6 lines. NEVER run git.
