# Rogue Isolation — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Read-only audit: rogue class isolation + per-client correctness (Era/SoD, TBC Anniversary, WotLK Titanforge, Cata, Mists, Retail, WoW Forever).
- **Scope:** classes/rogue.lua, rogue_guide.lua, tests/rogue_state.lua, tests/rogue_guide_state.lua (subject) + compat.lua, main.lua, nextaction.lua, nextaction_ui.lua (shared-engine reference). OUT: warrior/hunter/druid/paladin/shaman class modules, hunter_ui, practice, hud, twist, warrior_guide, druid_energy, new TTD helper.
- **Next step:** Run isolation sweep + per-client matrix, emit bench/rogue_client_isolation_2026-10-19.md.

## 2026-10-19 — Isolation + per-client audit complete
- **Worked on:** Read classes/rogue.lua (1451 lines), rogue_guide.lua, both rogue suites + compat/main/nextaction/nextaction_ui reference; grepped full cross-class surface (code vs comments); verified WoW API shapes against wow-ui-source branches (classic_era/anniversary/titan, live, origin/forever, origin/classic).
- **Current state:** Bench artifact written: bench/rogue_client_isolation_2026-10-19.md. F1 HIGH (st.druid_energy runtime reachability, fix = vendor EMA into rogue), F2 LOW (harness), F3 INFO (comments), F4 verified-absent; 0 proven-failing cells; 16 UNCONFIRMED.
- **Next step:** Orchestrator owns validation + in-client test session; F1 fix is a writer-lane follow-up (druid_energy.lua is OUT for this lane).

## 2026-10-19 — [signal:done] Rogue isolation audit delivered
- 1 runtime cross-class ref (F1 HIGH) + 0 failing cells + 16 UNCONFIRMED on the bench.
