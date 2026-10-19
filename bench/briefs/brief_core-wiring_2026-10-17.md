# Brief: core-wiring — rest-of-tree warnings, wire-not-strip
Date: 2026-10-17. Orchestrator-issued. Owner directive verbatim: "when u see any unused variable that u use them properly, dont remove them unles they absolutely serve no purpose, but make sure u trace it bcuz there probably is a purpose."

## Read first (all verified on disk)
desks/wiring/journal.md · desks/journal.md · bench/lessons.md · CAIRN.md · AGENTS.md (conventions + gotchas — Libs policy, main.lua hook rules)

## Scope — writable files (hard boundary)
bars.lua, compat.lua, main.lua, LibGlobalCooldown.lua, LibLatencyMonitor.lua, utils.lua, classes/druid.lua, classes/paladin.lua, classes/warrior.lua, tests/druid_guide_state.lua. FORBIDDEN: main.lua diag hook block (~lines 636-642, diag lane's), tests/bars_state.lua, tests/hud_state.lua, tests/run.sh, any toc. In class files: fix ONLY the listed lines, nothing else.

## Task — trace every warning (luacheck 2026-10-17 verified list; whitespace fixed only inside lines you touch)
- `bars.lua:41` unused `db` · `bars.lua:724` unused `db` · `bars.lua:782` unused `db_class` · `bars.lua:786` unused `hand_is_full` — trace each to its function's intent (profile/db reads? full-hand state?) and WIRE (use as the logic requires).
- `compat.lua:34` unused `addon_name` (pre-existing) — trace; wire or remove-with-rationale.
- `main.lua:48` unused `print` · `main.lua:70` setting undefined field `table.pack` — trace (compat shim? debug capture?) and make intentional.
- `main.lua:113,125` loop executed at most once — trace: intentional early-exit or broken iteration? Prove with a check either way.
- `LibGlobalCooldown.lua:72` unused function `simple_floor` · `:216` unused variable `time_started` — root-level library-style files (NOT vendored Libs/, editable): trace; wire the timing if the GCD math needs it.
- `LibLatencyMonitor.lua:57` `not (x == y)` → `~=` (only if neither side can be table/NaN — prove it) · `utils.lua:46`, class-file and LibGlobalCooldown whitespace lines: touch only.
- `tests/druid_guide_state.lua:2824` shadowing `tick` (line 909) — prove which binding is read; fix so the intended one is.

## Rules
Verdict per warning: WIRE / REMOVE-with-rationale / KEEP-with-rationale — never `_`. No git, no lint-config, endings preserved. Never gate on st.is_mainline alone. Other lanes parallel (their files are theirs — the 10 files above are yours alone; count fails expected, do NOT touch bars_state/hud_state).

## Validation
bash tests/run.sh (your touched suites green; only the 16 known count pins fail). luacheck: every Task warning cleared or KEEP-ruled. druid_guide_state (~66k checks) must not weaken. Mutation proofs on /tmp/opencode copy for every wiring change.

## Deliverables
Code · desks/wiring/journal.md entry · signal JSON · bench/buildout_core-wiring_2026-10-17.md (per-warning verdict table: file:line → traced purpose → verdict + evidence; UNCONFIRMED list). Final reply ≤6 lines. NEVER run git.
