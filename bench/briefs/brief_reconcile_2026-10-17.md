# Brief: reconcile — count pins + Interface pin + whitespace floor (final code wave)
Date: 2026-10-17. Orchestrator-issued. Quiescent tree (all feature/wiring/grade lanes landed).

## Read first (all verified on disk)
desks/reconcile/journal.md · desks/journal.md · bench/buildout_hud-grade_2026-10-17.md §6 (exact count deltas) · bench/buildout_options-grade_2026-10-17.md §4 (toc observation) · bench/buildout_guide-design-grade_2026-10-17.md §5 · AGENTS.md (toc conventions + Interface matrix) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
tests/bars_state.lua (12 count pins ONLY), tests/hud_state.lua (4 druid pins ONLY), SwedgeTimer.toc (the `## Interface` line ONLY), option_tables.lua (3 trailing-whitespace lines ONLY: 6, 494, 4658 — strip the trailing space, nothing else). NOTHING else.

## Task
1. **Count pins → verified values.** Re-run `lua5.1 tests/bars_state.lua` and `lua5.1 tests/hud_state.lua` on the quiescent tree FIRST and confirm the got-values match: bars PALADIN 29/14/8, WARRIOR textures 34/fontstrings 19, HUNTER 20/23/13, DRUID 7/21/9, pre-init 28; hud druid slots 10 / order `maul, mangle, rip, rake, bite, shred, tf, berserk, trinket1, trinket2` / icons 10 / width 302. ONLY if every got-value matches, update the want-values. Any mismatch = stop, report, do not guess.
2. **Interface pin.** `SwedgeTimer.toc` reads `11509, 20506, 38002, 16001, 120105`; toc_check + the AGENTS.md matrix agree on `120100` in the final position; the file change has no scoped owner (three lanes observed it mid-wave, none owned it). Default action: restore `120100`, document the ambiguity in your report for the owner (Retail may genuinely have bumped — owner call; do NOT rewrite the matrix or the test on a hunch).
3. **Whitespace floor.** Strip the trailing space on the 3 KEEP-ruled comment lines (they sit in your scope file; zero behavior change). Target end state: `luacheck .` → 2 warnings / 0 errors, both KEEP-ruled (compat addon_name, table.pack shim — verify both still stand, do not touch).

## Validation
`bash tests/run.sh` → 35 steps, 0 failed. `luacheck .` → 2 warnings / 0 errors. Mutation proof on /tmp/opencode copy: revert one count pin → exact FAIL returns; restore.

## Deliverables
Code · desks/reconcile/journal.md entry · signal JSON · bench/buildout_reconcile_2026-10-17.md (pin table old→new, Interface decision + ambiguity note, whitespace lines, mutation evidence). Final reply ≤6 lines. NEVER run git.
