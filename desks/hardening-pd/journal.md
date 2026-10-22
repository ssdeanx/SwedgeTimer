# hardening-pd journal

## 2026-10-19 — hardening session (post-practice audits)
- **Worked on:** All 14 hunter-postpd findings (H1-H8, M1-M6) + proctor-postpd gap pins (G1-G3, G6; G4 filed, G5/changelog owned by orchestrator). Files: practice_ui.lua, designmode.lua, option_tables.lua, classes/{paladin,druid,hunter,shaman,rogue}.lua (post_init seams only), tests/{practice_ui_state,designmode_state,options_load_state,rogue_state}.lua.
- **Current state:** DONE. Harness 38/0, luacheck 2/0 floor held. 7/7 mutation proofs on /tmp/opencode copies bite (H1 tick, H2 GCD, H4 drift, H7 toggle, M5 lockdown, count, H3 bridge). Rulings honored: H6 report-stands (copy fixed), M4 desc rewritten, G4 hunter_report options widget NOT built.
- **Next step:** Orchestrator validation + CHANGELOG [2.1.1] wave entries (separate step, explicitly out of scope here).
