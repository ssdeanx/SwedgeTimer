# Options-Hooks — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Wire the toggles the feature lanes left owed (all default-off, nil-safe) + fight-scoped log reset hook. Verify each in-tree first — pin if already wired, build only real gaps.
- **Scope:** ONLY option_tables.lua (hunter/shaman/druid/paladin sections), config_presets.lua (matching defaults), main.lua (combat-enter hook only), classes/hunter.lua (hook-call side only if needed), tests/options_load_state.lua (pins), tests for the main hook (locate in-lane, likely tests/main_init_state.lua). Everything else OUT — especially classes/warrior.lua + warrior tests.
- **Next step:** Read cited sources in-lane (hunter, druid, paladin, shaman entries above), verify wiring, implement gaps, pin in tests, harness + luacheck + mutations.

## 2026-10-19 — Options + combat-hook lane done
- **Worked on:** (1) Hunter ToT toggle `hunter_target_warning_enabled` (nil=off) wired in option_tables HUNTER §3.5 + §6 pin; (2) shot-report execute button `hunter_shot_report` in HUNTER §7.3 routing to practice_ui.toggle_hunter_report + dedicated pin (Show/Hide name, nil-safe); (3) main.lua PLAYER_REGEN_DISABLED hunter-only reset_shot_log hook + main_init §12 pin; (4) `show_druid_ttd_readout` (DRUID §13.16) + `reseal_marker_enabled` (PALADIN §3.44) toggles + §6 pins; (5) shaman lust verified already-covered (widget 4152 + `~= true` consumer + §6 + shaman_state nil-off/no-scan + secret_guard M5/13d pins) — no new toggle. No config_presets entries (nil=off by absence, same as all round-2 keys); no classes/*.lua changes.
- **Current state:** options_load 922/0, main_init 339/339, full harness 36/37 (bars_state 3 count pins are foreign: paladin +1 texture = P1 reseal marker, druid +1 fontstring = D1 TTD text, warrior +1 texture = active writer lane — reconcile-owned), luacheck 2/0 floor held, 6/6 mutations killed on /tmp copies. Endings preserved (LF option_tables/tests, CRLF main.lua).
- **Next step:** orchestrator reconcile of the 3 bars_state count pins; in-client checklist (ToT label, report frame, TTD readout, reseal marker, fight-scoped reset).

## 2026-10-19 — [signal:done] Options + combat-hook lane complete, handed to orchestrator
- 3 toggles + 1 report button + 1 combat hook wired, all nil-safe/off-default; shaman lust pinned as already-covered (no toggle added).
