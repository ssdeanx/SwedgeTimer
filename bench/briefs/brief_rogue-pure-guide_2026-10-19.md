# Brief: rogue-pure-guide (Round 1, pure engine — 2026-10-19)

## Objective
NEW WoW-free root `rogue_guide.lua`: the rogue decision model (sibling of `twist.lua`/`weave.lua`/`nextaction.lua`; cf. `warrior_guide.lua`, `druid_guide.lua`, `shaman_guide.lua`, `hunter_guide.lua` at root). Pure Lua 5.1, deterministic, unit-tested. Writer lane, file-disjoint from the parallel skeleton lane.

## Scope (ONLY these files)
- NEW `rogue_guide.lua` (root): pooling-band predicate (65-pre/85-post TBC bands as DATA tables per client, not constants); Rupture-vs-Eviscerate decider on TTD input; per-client Envenom rule table — NEVER one shared Envenom rule (`bench/rogue_research_2026-10-19.md` §3.5: Era combat / TBC / WotLK / Forever-Retail each its own rule); EA-duty refresh rule; Shiv upkeep rule; Thistle-Tea deficit cue; TTD consumed as a numeric INPUT (Round 2 wires the druid-D4-EMA tracker — this module never reads units/health); unknown-input contract (nil/unusable reads → caller-visible unknown, never a guessed verdict — H4 rule).
- NEW `tests/rogue_guide_state.lua`: pure-matrix cases per client, TTD-boundary decider cases, Envenom-per-client cases, unknown-input cases. Bite proofs on `/tmp/opencode` copies.
- Explicitly OUT: `tests/run.sh` (orchestrator registers this file's step at reconcile — validate standalone via `lua5.1 tests/rogue_guide_state.lua` + `luacheck rogue_guide.lua tests/rogue_guide_state.lua`); `nextaction.lua` untouched (no engine change); `classes/rogue.lua` (parallel skeleton lane owns it); every other file.

## Constraints
- WoW-free: no WoW API, no `st` references, no allocation-per-call discipline where the provider will tick it (caller-owned tables in/out). Timing inputs in seconds (GetTime domain); the provider converts.
- Evidence: `bench/rogue_research_2026-10-19.md` §§1–3 (rotations, Envenom, caps), `bench/rogue_deep_2026-10-19.md` §2 (tick/CP, SS window data as constants-needs), §4 handoff table. Per-client rules that differ stay different.

## Standing rules
No git. No lint-config. CRLF or LF to match root-guide convention (check `warrior_guide.lua` first — preserve). Standalone suite green before done.

## Workshop mechanics (skills: bench-read, desk-open, desk-journal, signal-write)
1. bench-read: `desks/journal.md`, `bench/rogue_readiness_2026-10-19.md` §2 + §5-Slice-C(pure part), both rogue research files, `bench/lessons.md`.
2. desk-open `desks/rogue-pure/`; 3. journal append + `done` signal (files + standalone results).

## Validation owner
Orchestrator: matrix green standalone, floor held, `nextaction.lua` untouched, disjoint vs skeleton lane.
