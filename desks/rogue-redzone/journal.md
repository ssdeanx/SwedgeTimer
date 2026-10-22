# rogue-redzone — desk journal

Lane: rogue-redzone (writer). Brief: bench/briefs/brief_rogue-redzone_2026-10-19.md (verified on disk).
Scope: classes/rogue.lua, config_presets.lua (ROGUE block), option_tables.lua (ROGUE section),
tests/rogue_state.lua, tests/options_load_state.lua (ROGUE pins). Nothing else touched.

## Worked on
- Read-first corpus: desks/journal.md (lane ledger), bench/lessons.md,
  bench/rogue_deep_2026-10-19.md §1 (SS-after-swing CONFIRMED Era / REFUTED TBC,
  wago SS-timing WA precedent) + §2.1/§4 handoff table, bench/rogue_readiness_2026-10-19.md
  §§1-2/§4 (contract checklist, guide-engine fit, residuals). No re-derivation.
- Verify-existing step: rogue ss_band + "SS" caption textures exist
  (classes/rogue.lua setup_rogue_visuals); generic deadzone is bars.lua's separate
  mechanism (rogue mainhand enable_deadzone=true) - the SS band is independent, no
  deadzone change. "SS" = Sinister Strike (no Scourge-Strike cue built; rogues have
  no such spell). Gate shape already correct: exact family equality ERA + confirmed
  sword mainhand (GetInventoryItemID 16 subclass), never st.is_mainline alone;
  hidden on unknown weapon, off-family, engine-dead, toggle-off.

## Current state
- Req 1 DONE: SS window ships RED {255, 64, 48, 0.85} and VISIBLE by default
  (show_rogue_ss_window=true) per OWNER ORDER 2026-10-19 - recorded as the explicit
  gate for this default-visible exception in config_presets.lua ROGUE comment +
  classes/rogue.lua header/fallback comments. Reads stay nil-safe (== true shows);
  toggle + color widgets exist with the color disabled-gate; option copy updated
  (postswing_desc + toggle desc note red/on-by-default/unknown-hides).
- Req 2 DONE (both-directions pass): scripted audit of every ROGUE defaults key -
  all 19 class-level keys have a class consumer (db.* read) AND a ROGUE panel widget;
  generic keys (nextaction_*, hud_show_*) consumed by nextaction_ui/hud with widgets.
  Zero gaps. Bar sub-block keys (enable_deadzone/bar_width/...) ride the shared
  bar machinery like all five classes (wiring_check.lua green). One stale-copy fix:
  option_tables ROGUE comment claimed "no rotation source" - parity lane added
  ST.ROGUE.get_rotation_key, so the comment now names it.
- Validation: full harness 37 steps, 0 failed; luacheck 2 warnings / 0 errors
  (floor held); 4 mutation proofs on /tmp/opencode copies ( since removed):
  M1 default true->false fails both suites' ships-true pins; M2 red->gold fails
  both suites' red pins; M3 family-gate strip fails 3 off-family hide pins;
  M4 band-render gold fails the red-render pin.
- Files changed (5, in scope): classes/rogue.lua, config_presets.lua,
  option_tables.lua, tests/rogue_state.lua, tests/options_load_state.lua.
  Endings preserved (rogue.lua/config_presets CRLF; others LF).

## Next step
- Lane complete. Orchestrator validates Era rogue shows the red post-swing zone
  (option-gated, red default per owner order); zero unwired rogue keys.
