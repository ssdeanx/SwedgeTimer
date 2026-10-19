# wiring — Journal

## 2026-10-17 — Desk opened
- **Purpose:** wire-not-strip pass over the rest of the tree — trace every luacheck warning in scope to its purpose; WIRE it properly if it serves one; REMOVE only if purposeless after tracing (with rationale); never silence with `_`.
- **Scope:** bars.lua, compat.lua, main.lua, LibGlobalCooldown.lua, LibLatencyMonitor.lua, utils.lua, classes/druid.lua, classes/paladin.lua, classes/warrior.lua (listed lines only in class files), tests/druid_guide_state.lua. FORBIDDEN: main.lua diag hook block, tests/bars_state.lua, tests/hud_state.lua, run.sh, tocs.
- **Next step:** execute bench/briefs/brief_core-wiring_2026-10-17.md. Full warning list with file:line is in the brief (verified from luacheck 2026-10-17: 45 warnings / 0 errors).

## 2026-10-17 — core-wiring done
- **Worked on:** traced + wired every Task warning in the 10 scoped files (brief verbatim order followed: WIRE / REMOVE-with-rationale / KEEP-with-rationale, never `_`).
- **Wired (8):** bars 41 (`db` reused at `LWIN.RegisterConfig`); main 48 (`print` now serves the `st.debug` call); main 113/125 (`while`→`if` in both iterators); LGC 216 (`select(2, ...)`); LLM 57 (`old_home ~= nil`); druid_guide 2824 (inner `tick`→`btick`; first try `etick` collided with pre-existing 1599 helper, renamed again).
- **Removed with rationale (4):** bars 724 dead `db`; bars 782 dead `db_class`; bars 786 stale `hand_is_full` + debug comment (canonical state is `self[hand].is_full`); LGC 72 `simple_floor` + stale commented call (tests pin raw floats; bare-`floor` hazard; 0 refs remain).
- **Kept with rationale (2):** compat 34 `addon_name` (vararg-shape convention, no `_` silencing); main 70 `table.pack` shim (pinned by main_init_state + enemy_swing note) + intent comment. Plus 20 whitespace-only touches (endings preserved: bars LF, rest CRLF/LF as found).
- **Current state:** 10-file luacheck 33 -> 2 warnings / 0 errors; tree 5 warnings / 0 errors. Harness: all touched suites PASS (druid_guide 65757, not weakened). bars/hud/designmode/toc failures are other lanes' pins — proven on /tmp/opencode/pristine_proof (identical failures with my changes reversed). Per-change mutation proofs in /tmp/opencode/mut_* + mut/ws.
- **Mid-task repair:** one edit briefly left `table.pack` bodyless; repaired immediately to the commented shim, syntax re-verified. No other files touched (compat untouched by design).
- **Next step:** reconcile wave owns bars/hud/designmode/toc pins; UNCONFIRMED items (toc 120100/120105, designmode variance, in-client behavior) are in bench/buildout_core-wiring_2026-10-17.md.
