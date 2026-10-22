# display-gaps — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build the two filed display gaps: SoD shockadin HS/AM render (proctor-filed P-HS/AM) + hunter Era HUD family-pick (sweep-filed H-HUD-1).
- **Scope:** ONLY classes/paladin.lua (HS/AM slots), classes/hunter.lua (Era HUD pick), nextaction_ui.lua (untouched — generic mapping already covers), guide_contract.lua (paladin sections), tests/hud_state.lua, tests/paladin_state.lua, tests/hunter_state.lua.
- **Next step:** Build + pin + mutate, then validate via harness.

## 2026-10-19 — Both gaps built, harness green
- **Worked on:** bench-read (proctor audit, rogue_hunter_eratbc §5, sod variants, wrath_sod, lessons) + journals; opened this desk. Paladin: 2 guide slots (holy_shock 20930 L16, aura_mastery 407624 L17, filler shape, unknown-hides), header/comment updates; NO nextaction_ui edit (display_active already maps any filler_slot key generically); NO paladin HUD change (census holds 7). Hunter: load-time Era filter (drop steady/kill_command/bestial_wrath → 6 live slots; SoD covered by same ERA token). Tests: guide_contract 8→10 slots + HS/AM shape pins + frame 24→28 + reference hs/am targets + 3 parity ticks (2 lit + 1 withheld) + fcfs-aware reference; paladin_state §20 filed→shipped + withhold pin; hunter_state Era/SoD HUD census; hud_state project opt + paladin guide-only census + Era 6-slot census + live Aimed read.
- **Current state:** Done. Harness 38/0 (twice), luacheck 2/0 floor. Mutations 6/6 killed on /tmp/opencode/disp copies (HS id, AM level, filler mapping nilled ×2 suites, KC exclusion dropped ×2 suites, Era block removed ×2 suites); copies removed. nextaction_ui.lua diff in tree is the hard-wait lane's, not this desk's. guide_contract rogue §6 hunk is another lane's; this desk touched paladin sections + shared fixture only.
- **Next step:** Orchestrator validates (re-run harness, spot-check hunks); in-client session owns HS/AM castability + Era slot absence + TESTING.md visuals (all UNCONFIRMED).
- [signal:done] HS/AM render + Era HUD pick built with lit/withheld/census pins, validation owned by orchestrator.
