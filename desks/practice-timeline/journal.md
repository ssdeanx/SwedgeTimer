# practice-timeline — Journal

## 2026-10-25 — Desk opened: the moving practice timeline

- **Purpose:** make practice mode actually cue the player — the operator's report
  "the practice mode doesnt really work. it should be like a timeline that moves so
  you know when to click on each ability."
- **Scope (write):** `practice_ui.lua`, `practice.lua`, `tests/practice_state.lua`,
  `tests/practice_ui_state.lua`, NEW `tests/practice_timeline_state.lua`, this desk,
  `bench/practice_timeline_2026-10-25.md`. Everything else held off.
- **Worked on:**
  - Diagnosed the start path end to end (`/st practice` → toggle → start →
    `practice_start_drill` → provider `session.start` → `begin_drill_session`) and
    against the real hunter provider (`classes/hunter.lua:5647-5749`, read-only).
    Three real defects: class drills had NO timeline at all (no frame, no toggle,
    `timeline_visible` never set); the timeline that existed was a post-fight log
    auto-scrolled to its newest end; and its lanes/indices were the paladin's for
    every class (verified the brief's archive citation at
    `docs/swedge/SwedgeTimer_TBC/practice.lua:2246` + `:2358-2364` — same log, not a
    playhead, so not copied).
  - Built the moving cue strip: pure geometry + cadence schedule in `practice.lua`
    (`TL_*`, `timeline_playhead_x/pps/event_x/window/slice/cadence`), the frame +
    one OnUpdate + pooled icons in `practice_ui.lua`, the class data contract
    (`practice_panel.timeline_lanes`, `practice_panel.upcoming`), the press-cue
    emphasis, and the History switch that keeps the old log one click away.
  - Data contract is published for the class lanes; the hunter's own `upcoming`
    provider is a follow-up (the shared fallback runs its published
    `practice_rotation` as a labelled cadence preview today).
  - Tests: extended `practice_state` (+49 pure pins) and `practice_ui_state`
    (section 16 rewritten for the History default, new section 31 against the real
    init + a hunter fixture); added `tests/practice_timeline_state.lua` (102 checks,
    self-contained sandbox that builds ONLY the strip). 19/19 mutations killed on
    `/tmp/opencode` copies, copies deleted.
- **Current state:** three suites green (1582 / 2608 / 102), luacheck 0/0 on the five
  files, LF preserved, `practice_ui.lua` densest prototype 163 → 168 locals (limit
  190). `run.sh` line owed to the orchestrator:
  `run "lua5.1 tests/practice_timeline_state.lua" lua5.1 tests/practice_timeline_state.lua`.
- **Next step:** operator in-client read of the strip (bench §D), then the class-lane
  `upcoming` follow-up (hunter windows → cues) using the contract in bench §B. Filed
  cross-lane items are in bench §A5 (drill keybind defaults, reset_keybinds wording,
  swallowed provider error, toggle_fight's per-class block, fixed row layout, design
  target).

## 2026-10-25 — [signal:done] stale-pin re-cut (orchestrator reconciliation)

- **Worked on:** `tests/rogue_state.lua:2614-2624` pinned the old literal
  `ui.practice_begin_fight(self, api.get_time())`. The Start Fight drill branch reads
  the clock once (`practice_ui.lua:5784`) and feeds `drill_now` to
  `practice_begin_fight` (:5785), `playhead_refresh` (:5786) and `playhead_draw`
  (:5787) — the pin was stale, not the code. Re-cut to assert the one clock read and
  all three consumers. No production code changed.
- **Current state:** `lua5.1 tests/rogue_state.lua` → 1137 checks / 0 failures
  (+3 net checks; the orchestrator's 1134 was pre-re-cut); `practice_ui_state.lua`
  green (2608). Three mutations on a `/tmp/opencode` copy kill the new pin (old
  literal, second clock read, stale source).
- **Next step:** unchanged — operator in-client read (bench §D) + the hunter
  `upcoming` follow-up (bench §B/F).
