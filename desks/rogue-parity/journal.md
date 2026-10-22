# rogue-parity desk journal

## Worked on
- 2026-10-19: desk opened; read desks/journal.md, brief_rogue-parity_2026-10-19.md,
  rogue_readiness §§1-2 + §4, rogue_deep §4, lessons.md, hands-up.md.
- Decision (Gap 2): REMOVE the 10 inert cue keys. Rationale: every promised state
  already has exactly one live consumer — SnD/Rupture/EA/Tea via HUD slots
  (presence + final-3s glow + greyed-missing, classes/rogue.lua get_hud_state),
  Expose/Shiv/Tea via guide actions (rules 1/2/6, rogue_guide.lua). A second bar
  presentation would duplicate live state with its own unknown-regime handling
  and add code without signal. No unwired purpose survived the trace (warrior
  bank cue = new composite state; shaman wf_hold_tint = weave-marker tint;
  rogue cues = third copy of HUD/guide state).

## Current state
- Lane COMPLETE 2026-10-19. Harness `bash tests/run.sh`: 37 steps, 0 failed.
  luacheck 2 warnings / 0 errors (floor held; all six touched files 0/0).
- Gap 1 SHIPPED: `ST.ROGUE.get_rotation_key` (classes/rogue.lua, hunter shape:
  action -> localized name via guide slot descriptors + per-id cache, POOL
  while holding, nil when idle/unknown; RETAIL/no-band idle -> nil).
- Gap 2 CLOSED by REMOVE: the 10 inert cue keys are gone from
  config_presets.lua (defaults + removal-rationale comment) and
  option_tables.lua (widgets + cues_header/desc replaced by an Upkeep Duty
  header/desc pointing at the HUD + guide as the live consumers; rogue_ea_duty
  kept). Full loop closure: absence pins (rogue_state §§2/3), REQUIRED/
  COLOUR_GATES/opt-in lists trimmed (options_load §9), §9(c) three-way scan
  auto-adapts.
- Mutations (all on /tmp/opencode copies, all failed as required): provider
  always-nil (3 pins each suite), hold-branch stripped (POOL pin, both
  suites), one cue default reintroduced (absence pin). Copies removed.
- Signal: desks/rogue-parity/.signals/2026-10-19_writer_done.json.

## Next step
- None for this lane. Validation owner (orchestrator): rotation label renders
  the action name for rogue; zero inert keys; harness + floor green (above).
