# Practice Hook — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build spec step 2 of the practice gamification — hook the pure
  progress/stats modules (`practice_progress.lua`, `practice_stats.lua`) into the LIVE
  game: session lifecycle → XP / mastery / streaks / time active, achievement
  evaluation, throttled persistence, and the practice panel's level badge + session XP
  bar (toggleable, OFF by default).
- **Design source:** `bench/practice_gamification_design_2026-10-19.md` (§2 progression,
  §3 stats, §6 engineering) and the foundation lane's handoff
  `bench/buildout_practice_gamification_foundation_2026-10-19.md` (§Handoff step 1).
- **Scope (this session):**
  - `config.lua` — `ST.defaults.profile.practice = ST.PRACTICE_DEFAULTS`.
  - `practice_ui.lua` — session lifecycle → progress, time active, achievements,
    persistence, panel badge + XP bar.
  - `practice_progress.lua`, `practice_stats.lua` — only if the hook needs a new
    pure-layer entry point (they are the foundation's, already tested).
  - `tests/practice_ui_state.lua`, `tests/practice_progress_state.lua`,
    `tests/practice_stats_state.lua` — the offline proofs.
  - OUT of scope: class files, `main.lua`, `diag.lua`, `compat.lua`, `hud.lua`,
    `bars.lua`, guides, engines, `option_tables.lua` (the Progress page is the NEXT
    lane), `config_presets.lua`, `tests/run.sh`, TOCs, versions, README, CHANGELOG,
    docs, git, lint config.
- **Next step:** read the spec + the foundation handoff, then read the live session
  lifecycle in `practice_ui.lua` (start/stop, the attempt feed, the score line) before
  writing the hook.

## 2026-10-19 — Hook built: live session → XP / mastery / streaks / time active + the badge
- **Worked on:** `config.lua` (the AceDB default `ST.defaults.profile.practice =
  ST.PRACTICE_DEFAULTS`), `practice_ui.lua` (a NEW "practice progression hook" section:
  the load-time migration + profile-key replacement, the graded-attempt feed through
  one public entry point `ui.record_graded_attempt` that all five grading sites now
  use, the time active from the injected monotonic clock, the session end (runs /
  history / completion bonus / daily streak / achievement evaluation), the throttled
  writes - load, session end, level-up and at most one every 300 s while a session
  runs, never per attempt - and the panel's level badge + session XP bar), and
  `practice_progress.lua` (`profile_snapshot` now lifts the stats scalars to the top
  level, so the achievement predicates read one flat snapshot instead of a hand-merged
  one). Tests: `tests/practice_ui_state.lua` (+section 21, 13 sub-sections),
  `tests/practice_progress_state.lua` (+the lift, +the save/load round trip, +the
  config wiring), `tests/practice_stats_state.lua` (+the save/load round trip, +the
  live summary shape).
- **Current state:** 1205 / 420 / 433 checks green · full harness **41 steps, 0
  failed** · luacheck **2 warnings / 0 errors** (the floor; both warnings are
  `compat.lua` + `main.lua`, KEEP-ruled, not this lane's files) · **mutation proofs
  26/26 killed** on `/tmp/opencode/practice-hook-mut` (script
  `/tmp/opencode/practice_hook_mutations.py`). Bench artifact:
  `bench/buildout_practice_gamification_hook_2026-10-19.md`. The step-3 lane
  (`practice-progress-ui`) landed its module + TOC lines + suite WHILE this lane ran
  and was red for ~6 minutes (its own history-row order); it declares this lane's
  files as read-only inputs, so there was no file overlap.
- **Next step:** orchestrator validation (owns Done).

## 2026-10-19 — [signal:done] Hook lane complete, 26/26 mutations killed
- The live session now feeds the pure progress/stats modules; the achievements
  evaluate at the session end; the panel badge renders when the opt-in is on;
  41/0 harness and the luacheck floor held. The default-flip request is filed below
  (not applied).

## 2026-10-19 — FILED for the operator: the badge default-flip request
- **Request:** flip the practice level badge (and the progression chat notices) from
  OFF to ON by default, or land it as an option on the Progress page and let the
  player choose. **Not applied by this lane.**
- **Why:** the spec's standing rule is "no default-visible change without an
  explicit operator gate". The operator has NOT gated the badge, so this lane ships
  the toggle OFF: the db key `practice_panel_badge` on the class table must be
  exactly `true` (nil = off, `== false` hides) for the badge to draw, and the chat
  notices ride the same opt-in. The data collection itself is always on and silent:
  the XP, the mastery, the streaks, the time active and the unlock flags are
  collected and saved either way.
- **Who owns the rest:** the Progress options page (the widget for the toggle) is the
  step-3 lane; the toast and the cosmetics are the step-4 lane. This lane ships the
  db key, the nil-safe read and `ui.set_badge_enabled(self, enabled)` for both.
- **Evidence:** `bench/buildout_practice_gamification_hook_2026-10-19.md` (§"Open /
  filed for the operator") and the section-21 pins in `tests/practice_ui_state.lua`
  ("the badge is hidden by default", "no chat notice fires while the opt-in is off").
