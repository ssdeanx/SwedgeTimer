# Brief: options-grade — options-file warnings + fine-tune audit
Date: 2026-10-17. Orchestrator-issued. Owner directive: wire-not-strip + options fine-tuned.

## Read first (all verified on disk)
desks/options/journal.md · desks/journal.md · bench/buildout_options_2026-10-17.md (the 27-toggle table — AUTHORITATIVE for keys/defaults/groups) · bench/lessons.md · CAIRN.md · AGENTS.md (conventions)

## Scope — writable files (hard boundary)
config.lua, config_presets.lua, option_table_presets.lua, option_tables.lua, tests/options_load_state.lua. NOTHING else.

## Task A — trace and wire (BINDING warning list, luacheck 2026-10-17 verified)
- `config.lua:5` unused `LSM` · `config.lua:8` unused `LWIN` · `config_presets.lua:5` unused `LSM` — trace: LibSharedMedia (and whatever LWIN is) fetched but never used. If SharedMedia font/status lookups were intended, WIRE them (media actually applied); if genuinely unneeded after tracing, REMOVE with rationale.
- `option_table_presets.lua:4` unused `st` — trace what the presets should read from the addon object; wire or remove-with-rationale.
- `option_tables.lua:51` unused `print` · `option_tables.lua:4397` unused `title` — `title` especially: a computed label going nowhere usually means a widget missing its label — wire it.
- `option_tables.lua:96` shadowing upvalue `english_class` (line 78) · `option_tables.lua:680,686` shadowing upvalue argument `self` (line 655) — shadowing is a suspected wrong-variable bug until proven otherwise: trace which binding each use-site MEANT and fix so the intended one is read.
- Whitespace-only warnings in these files: fix ONLY inside lines you already touch.

## Task B — fine-tune audit
Verify every one of the 27 wired toggles end-to-end: widget reads the EXACT key the class code reads; default matches its buildout report; group placement sensible; description accurate; no default-visible change. Fix mismatches in scope. Confirm the §6 gaps from the options report are still correctly unwired (no in-scope consumer) — do not wire them.

## Rules
Wire-not-strip: WIRE / REMOVE-with-rationale / KEEP-with-rationale; never `_`. No git, no lint-config, endings preserved. Other lanes work in parallel (bars_state/hud_state count fails expected — do NOT touch those files).

## Validation
bash tests/run.sh (your step green; only the 16 known count pins fail). options_load_state extended, never weakened. luacheck: all Task-A warnings cleared (or KEEP-ruled in report). Mutation proofs on /tmp/opencode copy for every wiring change.

## Deliverables
Code · desks/options/journal.md entry · signal JSON · bench/buildout_options-grade_2026-10-17.md (per-warning verdict table: file:line → traced purpose → WIRE/REMOVE/KEEP + evidence; fine-tune audit table: toggle → widget → key → default → verdict; UNCONFIRMED list). Final reply ≤6 lines. NEVER run git.
