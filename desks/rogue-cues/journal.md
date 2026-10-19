# rogue-cues — Journal

## 2026-10-19 — Desk opened (Round 2, brief_rogue-cues-provider_2026-10-19)
- **Purpose:** writer lane for Slice B (tick + Era cue) + Slice C (provider/HUD-live) + TTD wiring.
- **Scope:** ONLY `classes/rogue.lua`, `rogue_guide.lua`, `tests/rogue_state.lua`,
  `tests/rogue_guide_state.lua`, `tests/guide_contract.lua`. OUT: practice.lua, option_tables.lua,
  diag.lua, TOCs, main.lua, bars.lua, compat.lua (parallel practice lane is file-disjoint).
- **Next step:** bench-read done (journal, rogue_readiness §§2/4/5-B/C, fix buildouts/buildout
  journals, both rogue research files, lessons, hands-up); implement proc-aware tick predictor,
  Era SS window, swap/poison cues, live HUD/provider, TTD EMA + M7 guard; extend the three suites;
  run harness + luacheck + mutation proofs on /tmp/opencode copies; journal + done signal.
