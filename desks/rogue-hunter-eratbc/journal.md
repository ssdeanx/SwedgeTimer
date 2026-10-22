# rogue-hunter-eratbc — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Make rogue + hunter next-action/HUD/practice/designer fully working on Classic Era/SoD + TBC Anniversary (Era/SoD/TBC branches only).
- **Scope:** ONLY classes/rogue.lua, rogue_guide.lua, classes/hunter.lua, hunter_guide.lua, hunter_ui.lua, tests/rogue_state.lua, tests/rogue_guide_state.lua, tests/hunter_state.lua, tests/hunter_guide_state.lua.
- **Next step:** verify per family (ERA/SOD/TBC) guide vs sim APL, HUD resolution, practice grading, designer hooks; fix in-scope or file with file:line.

## 2026-10-19 — Verified green, two HUD gaps filed, zero edits
- **Worked on:** Ran bench-read (rogue/hunter rotation audits, wrath_leftovers, perclass verify, lessons) + journals; opened this desk; drove both pure engines with frozen sim-line inputs for ERA/SOD/TBC (42/42 in /tmp/opencode/verify_eratbc.lua): rogue E-C1/T-M2/S-C1 + pools/windows/tea/shiv gates, hunter Era weave + SoD Chimera/LnL + TBC KC/BW/RF priority. Confirmed HUD resolution paths (rogue all-vanilla names; hunter rank-1 + name-agnostic + re-point), practice S/A/B/C/F + nil (practice_state 1208/0), designer hooks (setup_rogue_visuals, hunter_ui, bars/design/hud_templates pins). Shared files read-only; lust absence verified (rogue M5 canary pre-existing, hunter zero); no Wrath/Forever edits.
- **Current state:** Done. Artifact: bench/rogue_hunter_eratbc_2026-10-19.md (green claims + 2 FILED gaps: H-HUD-1 Era dead HUD slots needs hud_state census + options; H-HUD-2 TBC Steady 56641 needs in-client GetSpellInfo). Harness 38/0, luacheck 2/0 floor, zero touched lines so zero mutations owed.
- **Next step:** Orchestrator validation + in-client confirmations (GetSpellInfo(56641) on 2.5.6, Era slot census, TESTING.md visuals).

## 2026-10-19 — [signal:done] rogue+hunter Era/SoD/TBC verified, gaps filed
- 42/42 frozen sim-line checks + 38/0 harness + luacheck floor; bench file above; owed out-of-scope: hud_state census + options (H-HUD-1), in-client id probes (H-HUD-2).
