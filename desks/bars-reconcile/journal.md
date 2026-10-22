# bars-reconcile — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Reconcile bars_state count pins (P1 reseal + D1 TTD + W1 desync + verify rogue/hunter) + warrior desync options (default/widget/pin); W2 stays UNBUILT.
- **Scope:** ONLY tests/bars_state.lua, option_tables.lua (warrior section), config_presets.lua (warrior block), tests/options_load_state.lua (warrior pins). Everything else OUT.
- **Next step:** Verify no live writer (journal Status = all done), read widget creation sites, pin counts, wire option, harness+mutations.

## 2026-10-19 — Reconcile done (bars pins + warrior desync options)
- **Worked on:** (1) bars_state.lua CLASSES pins only: PALADIN textures 11->12 (reseal_marker texture, classes/paladin.lua:1217), WARRIOR textures 25->26 (desync spark, classes/warrior.lua:1517), DRUID fontstrings 6->7 (druid_ttd_text, classes/druid.lua:1191); rogue 4/3 + hunter 14/5 verified already-pinned, untouched. (2) Warrior desync option: nil-off default documented in config_presets.lua warrior block (no true entry, ~= true read in classes/warrior.lua:1821, same as bank_cue/battle_shout); widget show_warrior_desync_alert order 3.18 in option_tables.lua warrior section; key added to Warrior KEYS in tests/options_load_state.lua:692-694. W2 Battle-Shout stays UNBUILT per brief (no free guide slot).
- **Current state:** bash tests/run.sh 37/0 green; luacheck 2 warnings / 0 errors (floor); 5/5 mutations killed on /tmp/opencode copies (M1 paladin pin, M2 warrior pin, M3 druid pin, M4 widget strip, M5 true-default inject); all 4 touched files byte-identical post-restore; endings preserved (CRLF config_presets 886 CRs, LF others 0 CRs). No live writer was active (journal Status: all lanes done).
- **Next step:** Orchestrator validation (in-client: reseal marker, TTD readout, desync spark 0.3s window on Forever/Classic swing stamps; desync toggle on/off).

## 2026-10-19 — [signal:done] Reconcile complete, handed to orchestrator
- bars_state 3 pins + warrior desync option wired; 37/0 + luacheck 2/0 + 5/5 muts; W2 UNBUILT; in-client confirmations owed
