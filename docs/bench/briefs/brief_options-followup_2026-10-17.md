# Brief: options-followup — warrior slot toggles + reset re-anchor + pips position probe
Date: 2026-10-17. Orchestrator-issued. Owner: "anything that needs to be fixed for everything function properly, complete it now."

## Read first (all verified on disk)
desks/options/journal.md · desks/journal.md · bench/buildout_options-grade_2026-10-17.md §6 (gaps) · bench/buildout_hud-grade_2026-10-17.md §5 finding #1 (the missing toggles) · bench/buildout_practice-grade_2026-10-17.md §1-G4/practice_reset note · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
option_tables.lua, config_presets.lua, config.lua, tests/options_load_state.lua. hud.lua + bars.lua are READ-ONLY for shape verification (do not touch).

## Task
1. **Warrior arms/SoD slot toggles.** Keys `hud_show_rend`, `hud_show_ms`, `hud_show_bladestorm`, `hud_show_raging_blow` exist nowhere (hud-grade §5). First READ hud.lua's `icon_should_show` + the hud_show_tf precedent (`hud.lua:463 show_key` → `:611 == false hides`): match that exact shape. Add the 4 defaults (config_presets.lua, alongside the other slot keys) as **true (hide-on-false)** — this preserves the current always-drawn rendering, so no default-visible change. Add 4 widgets in the WARRIOR HUD group. Pin all four in options_load_state (widget, key, default, consumer-read).
2. **practice_reset_position re-anchor.** option_tables writes `practice_panel_x/y = 0` without re-anchoring (practice-grade flagged it). Fix: route through the panel's position applier (or re-anchor after the write) so the button visibly works. Pin with a check.
3. **Pips x/y probe.** grep the pips factory (bars.lua `new_pips` — READ-ONLY) for position consumption: if the factory consumes `druid_pips_x/y`, wire widgets + defaults + pins; if it does not, do NOT touch bars.lua — write the factory-side spec into your report for a bars follow-up.

## Rules
Wire-not-strip; never `_`. No git, no lint-config, endings preserved. No default-visible change (defaults true / nil-off per precedent). hud-reflow lane runs in parallel (hud.lua is its file — you only read it).

## Validation
bash tests/run.sh → 35 steps, 0 failed expected. options_load_state extended, never weakened. luacheck scope files 0 errors. Mutation proof on /tmp/opencode copy (flip one new default → pinned check fails).

## Deliverables
Code · desks/options/journal.md entry · signal JSON · bench/buildout_options-followup_2026-10-17.md (toggle table, reset fix, pips probe result + factory spec if unwired, UNCONFIRMED list). Final reply ≤6 lines. NEVER run git.
