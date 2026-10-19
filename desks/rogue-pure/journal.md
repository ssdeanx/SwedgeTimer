# rogue-pure — Journal

## 2026-10-19 — Desk opened
- **Purpose:** writer lane for bench/briefs/brief_rogue-pure-guide_2026-10-19.md — NEW WoW-free root rogue_guide.lua + NEW tests/rogue_guide_state.lua only.
- **Scope:** rogue_guide.lua (CRLF, root-guide convention), tests/rogue_guide_state.lua (LF, tests convention). Explicitly OUT: tests/run.sh, nextaction.lua, classes/rogue.lua, every other file.
- **Next step:** write the pure module + suite, validate standalone, bite proofs, done signal.

## 2026-10-19 — Module + suite written, standalone green
- **Worked on:** read brief + desks/journal.md + rogue_readiness §§2/5-Slice-C + both rogue research files + lessons; wrote rogue_guide.lua (pooling-band DATA tables, TTD decider, per-client Envenom tables, EA/Shiv/Tea rules, unknown contract) and tests/rogue_guide_state.lua (194 checks).
- **Current state:** standalone green — lua5.1 tests/rogue_guide_state.lua 194/0; luacheck 0/0 on both files. Bite proofs on /tmp/opencode copies: unknown-gate strip → 9 failures; ERA Envenom corruption → 2 failures; TTD off-by-one → 1 failure; clean copy 194/0. Scope held: classes/rogue.lua still absent (no skeleton-lane collision), tests/run.sh + nextaction.lua untouched (mtimes pre-session), run.sh has no rogue refs (orchestrator registers at reconcile).
- **Next step:** orchestrator reconcile (register suite step in run.sh, wire classes/rogue.lua provider against the frozen input/action names).

## 2026-10-19 — [signal:done] rogue pure guide delivered
- Files: rogue_guide.lua + tests/rogue_guide_state.lua (NEW, scope-only).
- Results: 194/0 standalone, luacheck 0/0, 3/3 bite proofs fail-loud, floor held, no collisions.
