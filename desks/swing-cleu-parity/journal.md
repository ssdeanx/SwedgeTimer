# swing-cleu-parity — Journal

## 2026-10-22 — Desk opened
- **Purpose:** event-by-event CLEU parity: SuperSwingTimer-WoW (read-only reference) vs our chain (vendored LibClassicSwingTimerAPI v32 + main.lua dispatcher/handlers + swing_source.lua). List every SST-handled subevent/unit event we drop or mishandle, then fix OUR side only (lib byte-identical, HU-29; HU-31 client scope).
- **Scope:** main.lua, swing_source.lua, compat.lua event paths, hunter_ui.lua cast reads if a gap names them, plus legs in tests/real_wire_state.lua for every fixed gap. Off-limits: run.sh, vendored Libs, TOCs, versions, options.
- **Next step:** run @bench-read (done: journal lane table + swing_display + swing_engine_fix + proctor_swing_gap + HU-22/25/27/28/29/31), then map SST event handling vs ours with file:line both sides.

## 2026-10-22 — CLEU parity done (main.lua-only fixes + 9 legs)
- **Worked on:** mapped SST HandleCLEU/HandleSpellcast*/registration/tables vs lib v32 + main dispatcher/handlers + swing_source + compat + hunter_ui; cross-client truth via git show (5 branches); fixed F1 extra-attack suppression (pending + armed-flag START suppression + STOP pairing), F2 incoming-parry haste, F3 druid form-change reset — all main.lua; 9 new real_wire legs (760/0, 3 xfail); 6/6 mutations kill red on /tmp copies (removed).
- **Current state:** DONE. Report: bench/swing_cleu_parity_2026-10-22.md (new file). Diff: main.lua + tests/real_wire_state.lua only. Suites: real_wire 760/0, main_init 975, bars_state 885, all class suites green; luacheck floor 2/0. Filed-not-fixed: G1 stale queue tint (class-lane), G2 registration expansion (pin re-cuts), G3/G4 lib table content (HU-29-adjacent).
- **Next step:** orchestrator reconcile (full run.sh) + operator copy/in-client U1-U5.

## 2026-10-22 — [signal:done] CLEU parity complete
- 3 gaps fixed our-side (F1/F2/F3), 8 non-gaps assessed, 4 follow-ups filed (G1-G4); 760/0 + 6/6 mutations; report on bench.
