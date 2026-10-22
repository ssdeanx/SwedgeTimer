# Druid-Paladin Gaps — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build competitor gaps D1 (EMA TTD), D2 (proc-aware energy-tick predictor), P1 (GCD-aware reseal marker) per bench/competitor_gaps_2026-10-19.md §1 + §Druid + §Paladin.
- **Scope:** ONLY ttd helper module + tests, classes/druid.lua, druid_energy.lua, tests/druid_state.lua, twist.lua, classes/paladin.lua, tests/twist_state.lua, tests/paladin_state.lua. Everything else OUT.
- **Next step:** Read owning files + wow-ui-source API shapes, implement pure WoW-free math, wire inputs, run harness + luacheck + mutations.

## 2026-10-19 — D1/D2/P1 implemented, harness-checked
- **Worked on:** D1 TTD readout (druid_energy.format_time_to_die + vf.druid_ttd_text, show_druid_ttd_readout == true, nil = off); D2 proc-aware tick (druid_energy.adjust_gain_for_procs/is_tick_gain + SoD-gated TF +60 supplier via sod edge, family ERA + rune probe, legacy verbatim elsewhere; no invented amounts); P1 reseal marker (twist.get_reseal_marker_fraction + vf.reseal_marker, reseal_marker_enabled == true, nil = off). Tests: twist_state 66, druid_state 473, paladin_state 248 — all PASS. Full harness: only bars_state count pins (paladin +1 texture, druid +1 fontstring — reconcile-owned; warrior/hunter deltas are sibling lanes) + wiring_check hunter dead-hook (sibling lane) fail. My 7 files luacheck 0/0. Mutations 5/5 killed on /tmp/opencode copies.
- **Current state:** Done, awaiting orchestrator validation. No TOC edits (out of scope) — no new files created, so toc_check stays green. API shapes verified against wow-ui-source classic_era/live/origin-forever (Unit/UnitDocumentation + SpellDocumentation). SST reseal behavior + TF/SoD numbers beyond cited sources remain UNCONFIRMED in-client.
- **Next step:** Orchestrator: reconcile bars_state/hud_state count pins, wire option keys (show_druid_ttd_readout, reseal_marker_enabled) in options pass, in-client test session.
- **Deviation note:** brief allowed a NEW ttd helper module; not created — a new root .lua without TOC edits fails toc_check, and TOCs are OUT of scope. The shared EMA already lives in druid_energy.lua (rogue reuses it); D1 shipped as the readout reusing it. TOC wiring owed: none (no new files).

## 2026-10-19 — [signal:done] D1/D2/P1 ready for orchestrator validation
- Files: druid_energy.lua, twist.lua, classes/druid.lua, classes/paladin.lua, tests/druid_state.lua, tests/twist_state.lua, tests/paladin_state.lua. Harness/mutations/UNCONFIRMED in entry above.
