# lazy-bars — Journal

## 2026-10-22 — Desk opened
- **Purpose:** option-on build point for HU-22 lazy swing bars (option_tables per-hand enabled setter → ST:bring_up_hand) + committed tests/bars_lazy_state.lua.
- **Scope:** option_tables.lua per-hand enabled setter ONLY; NEW tests/bars_lazy_state.lua. No main.lua, bars.lua, hunter, compat, swing_source, run.sh, Libs, TOCs, versions.
- **Next step:** implement enabled_setter + widget rewire, write suite, run focused validation + mutations, report.

## 2026-10-22 — option-on build point landed
- **Worked on:** per-hand Enabled setter in option_tables.lua (new ST.opts_funcs[hand].enabled_setter: writes db, on enable calls ST:bring_up_hand(h) nil-safe; Enabled widget set "setter"→"enabled_setter") + NEW tests/bars_lazy_state.lua (37 checks: disabled+weaponed unbuilt; option-on builds once; enable+equip→built+tick; disable no-op + nil-seam pcall-clean; widget/generic-setter/class-master source pins).
- **Current state:** in-tree green: bars_lazy_state 37/0, bars_state 885, main_init 975, options_load 3501, wiring_check 876; luacheck 0/0 on both touched files; LF endings kept. Mutations M1 (build neutered→3 FAIL incl. exact frame counts), M2 (widget reverted→routing FAIL), M3 (nil-guard dropped→nil-seam FAIL) all kill on /tmp/opencode copies, removed after. Scope held: option_tables.lua + new suite only.
- **Next step:** orchestrator adds the run.sh line + full harness; owed in-client: enable-at-runtime shows bar with no reload.
- **Skills:** @bench-read (journal + display/engine/proctor + HU-22/25/31 + brief), @desk-open (desk created, journal read first), @desk-journal (this entry), @signal-write (done signal filed) — all four ran.

## 2026-10-22 — [signal:done] option-on build point
- done: setter + suite landed and proven per above; run.sh line + full run.sh are orchestrator-owned.
