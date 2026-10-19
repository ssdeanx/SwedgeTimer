# Brief: options — wire every new toggle (round close-out)
Date: 2026-10-17. Orchestrator-issued.

## Read first
desks/options/journal.md · desks/journal.md · every bench/buildout_*_2026-10-17.md report — the §"option defaults" / "options pass" sections are the AUTHORITATIVE toggle list (each lane documented its toggles there) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
option_tables.lua, option_table_presets.lua, config_presets.lua, config.lua, tests/options_load_state.lua. NOTHING else.

## Task
- Collect every toggle documented across the round's reports (at least: `diag_tick_counters`; `design_mouse_anchor`; hunter H3 manual multi-target toggle + hunter's others; warrior's; paladin P1 counters + paladin's others; `show_shaman_stormstrike_bar`, `show_shaman_wf_hold_tint`, Rockbiter badge; druid's §5 list; practice's; `enemy_swing_enabled`; plus whatever shaman-weave lands — its report will say, treat that as a later addendum row).
- Wire each as an AceConfig widget in the correct group, default per its report (nil = OFF; NO default-visible change), one-line description matching the report's wording.
- Match EXACT existing key names from the reports (nil-safe reads already exist in the class code — the widget must read the same key).
- Update tests/options_load_state.lua expectations for the new widgets.
- Do NOT rename existing keys; do NOT flip any default to visible/on.

## Validation
bash tests/run.sh — your step green (bars_state/hud_state are the final reconcile wave — do not touch them). luacheck 0 errors. Mutation proof: in a /tmp copy flip one wired default to ON and show which check catches the default-visible change; if nothing catches it, note that gap in the report (do not invent a test).

## Deliverables
Code · desks/options/journal.md entry · signal JSON in desks/options/.signals/ · bench/buildout_options_2026-10-17.md (toggle table: key → group → default → source report; mutation evidence; gaps). Final reply ≤6 lines. NEVER run git.
