# swing-finish2 — Journal

## 2026-10-22 — Desk opened
- **Purpose:** Finish G1-G4 open from CLEU-parity (queued-tint clears, all-class extra/parry, Era/BCC Slam pause, utility resets) — our side only, lib byte-identical, HU-31 scope.
- **Scope:** classes/*.lua, main.lua dispatcher/handlers, tests/bars_state.lua + tests/main_init_state.lua pin re-cuts, legs in tests/real_wire_state.lua. Off-limits: run.sh, vendored Libs, TOCs, versions, options.
- **Next step:** map SST State.lua vs ours with file:line both sides, then implement G1-G4.

## 2026-10-22 — G1-G4 done, all green
- **Worked on:** mapped SST SuperSwingTimer_State.lua (1129-1149 interrupt clears, 1308/1322 extra suppression, 1176-1194 parry, 1041-1043/1416-1418 pause, 1455-1466 resets) + Constants.lua RESET/PAUSE sets vs lib Era:851-966/BCC:967-1078/Wrath:1080-1230 tables; implemented G1 (warrior/hunter/druid on_spellcast_event INTERRUPTED/FAILED clears, CURRENT_SPELL self-heal intact), G2 (CLEU registration all classic-line classes + re-cut bars_state matrix/main_init §13/warrior_state gate pins with rationale), G3 (warrior Slam pause arm Era/TBC + main START convert, Wrath untouched), G4 (neutral SST RESET set on SUCCEEDED, HU-31 gated). Legs: bars_state G1 Era+TBC per class + G3 arm/convert/stale/Wrath-negative, real_wire G2 reg Era/Anniv/Titan+Retail/Forever-neg + functional anniv/titan + G3 Era/Anniv/Titan-neg/stale + G4 Era/Anniv(id+name)/Titan + Retail/Forever-neg.
- **Current state:** DONE. Focused suites all green (bars 935, main_init 975, real_wire 882/0 + 3 xfail, warrior 2046, hunter 1744, hunter_guide 1970, druid 1580, shaman 1064, paladin 1234, rogue 1114, wiring 872/0/3/0, hud 817, guide_contract 1052); luacheck 2 warnings/0 errors floor; 7 mutations kill red on /tmp/opencode copies (removed); CLEU audit clean (only main.lua:661 registers); GetTime sweep clean (compat clock + swing_source fallback + comments only). No bench file written (HU-32: lane files its own artifacts - report carries the trail; orchestrator decides the bench write).
- **Next step:** orchestrator reconcile (full run.sh) + operator in-client U1-U4.

## 2026-10-22 — [signal:done] G1-G4 complete
- 4 gaps closed our-side, Era + Anniversary verdicts separately, Titanforge native where applicable; full per-gap file:line in the handoff report.
