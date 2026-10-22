# Desk: swing-display (display lane, ses_e9b0ee364ffez1Y1QmPOsCqJlH)

Write scope ONLY: bars.lua, classes/hunter.lua, hunter_ui.lua.
Do NOT touch: main.lua, compat.lua, swing_source.lua, run.sh, vendored Libs, TOCs, versions, options.

## Worked on
- 2026-10-22: opened desk. Read journals-first: desks/journal.md lane table
  (parallel dispatch row: display/engine/harness disjoint by file), bench/
  swing_wire_status_2026-10-21.md (offline-proven only, stubbed engine),
  bench/proctor_swing_gap_2026-10-22.md (Pins 1-3 are engine/harness-owned;
  usable as pin list, not API truth), hands-up HU-22 (lazy-bars gate:
  enabled AND in use), HU-25/HU-29/HU-30 (engine-side, not mine).
- Compared against read-only /home/sam/SuperSwingTimer-WoW (no lift):
  IsAutoShotSpell matches id OR name with English fallback; hidden window
  cached only while `now` inside it, future recomputed per tick; ranged bar
  shows swing progress, cast bar shows live-cast-or-hidden-window; hunter MH
  hidden while ranged active/cast visible (reference policy, not a bug).

## Current state
- Defects found in scope (all display/shared-state, engine START delivery
  explicitly out of scope):
  1. classes/hunter.lua gather_guide_inputs uses the cached hidden-window
     bounds with NO now-inside check (hunter_ui's get_hidden_window HAS the
     check) -> stale window poisons Steady/Auto after the cycle ends.
  2. hunter_ui.lua read_live_cast Auto Shot exclusion compares spell_id==75
     and name==ui.auto_shot_name; id-less classic payloads (spell_id nil)
     with a cold spell cache (auto_shot_name nil) slip through and render
     as a live "cast" instead of the 0.5s window.
  3. hunter_ui.lua get_hidden_window caches FUTURE windows (reference
     recomputes); harmless today, diverged.
  4. bars.lua: no bar_is_built/ensure_bar (HU-22 gate has no home in scope
     files); getters index missing frames. Build points in main.lua belong
     to the engine lane; this desk adds the predicate + constructor +
     nil-safety only, no behaviour change while init builds all hands.
- Edits: all 4 landed (see bench/swing_display_2026-10-22.md for files+lines).

## Next step
- DONE 2026-10-22. Focused suites green (bars 907 / hunter 1744 / window 213
  / guide 1970 / hud 817 / contract 1052 + shaman/warrior/paladin/druid/rogue
  green); luacheck 0/0 on touched files; 6/6 mutations kill (M1-M3 committed
  suites, M4-M6 ad-hoc /tmp/opencode/bars_check.lua, NOT committed); bench
  report filed as bench/swing_display_2026-10-22.md (new file only).
- Owed elsewhere, NOT this lane: engine START delivery (engine lane),
  ensure_bar build points in main.lua (engine lane), committed lazy-bars
  suite + run.sh line (orchestrator / queued lazy-bars lane), in-client
  proof U1-U3 (operator copy), cast spark U4 (follow-up).
