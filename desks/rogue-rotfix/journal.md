# rogue-rotfix — Journal

## 2026-10-19 — Audit gaps closed in-engine, wiring filed
- **Worked on:** Implemented all sim-sourced rogue rotation fixes in rogue_guide.lua (family DATA: bands/spine/floors/windows/tea/AR/sweaty/shiv/BF + snd/ar/bf verdicts + SOD data) and classes/rogue.lua (gather snd/ar/bf, builder chain, AR-aware tick, slot-less label fallbacks). Zero new guide slots (contract pins 7), zero new db keys (options three-way). Tests: rogue_guide_state 251→433/0, rogue_state →385/0; guide_contract/rotationtext/options_load green; luacheck floor 2/0 held; endings preserved; 13/13 mutation kills on /tmp/opencode/mutwork.
- **Current state:** Done. Artifact: bench/rogue_rotation_gaps_closed_2026-10-19.md (per-gap disposition + 11 filed follow-ups with reasons). Crossfire noted: warrior/shaman/wiring failures are parallel-lane edits (09:51-09:54 mtimes), not this lane — reconcile owns.
- **Next step:** Orchestrator validation + reconcile; follow-up lanes for icons/options/SoD/H6/slots.

## 2026-10-19 — [signal:done] rogue-rotfix complete
- Engine closure shipped; harness green on scope + frozen consumers; mutations kill
- 11 follow-ups filed with reasons in bench/rogue_rotation_gaps_closed_2026-10-19.md
