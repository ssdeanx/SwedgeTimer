# Brief: diag — build-out round 1
Date: 2026-10-17. Orchestrator-issued, round plan approved in desks/journal.md.

## Read first
desks/diag/journal.md · desks/journal.md · bench/verify_bank.md (C4 row — BINDING) · bench/discover_features.md (#23 row: /tmw-cpu-style) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
main.lua (OnUpdate hook lines only), diag.lua, tests/diag_state.lua. NOTHING else — tests/main_init_state.lua must stay green (run the full harness).

## Task
- **C4 per-tick budget audit**: count what each OnUpdate runs per frame tick (throttle coordinator): per-site tick counts, on-update time attribution where measurable, surfaced through `/st diag` lines. Counters must be flat-zero overhead when diag is disabled (nil-safe, default OFF — no default-visible behavior change).
- Reuse existing diag output format/patterns; keep line labels stable. discover #23 is the UX model (/tmw cpu).

## Cross-client rules / style
st.api.get_time() discipline. Minimal in-place edits in main.lua (hook lines only), preserve formatting/line endings, no `_` renames, no unused-variable work.

## Validation
bash tests/run.sh — all green. luacheck 0 errors. Mutation proof on /tmp/opencode/mut_diag/ (break a counter, show the check fails, restore).

## Deliverables
Code · desks/diag/journal.md entry · signal JSON in desks/diag/.signals/ · bench/buildout_diag_2026-10-17.md (changes, evidence, sample /st diag output block, option defaults, UNCONFIRMED items). Final reply ≤6 lines. NEVER run git.
