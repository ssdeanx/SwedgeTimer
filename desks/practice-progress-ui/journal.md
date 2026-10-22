# Practice Progress UI — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build spec step 3 of the practice gamification — the **Progress options
  page** and the **practice stats frame** (sparkline + tables + history). Design spec:
  `bench/practice_gamification_design_2026-10-19.md` §3 (stats section) / §4
  (achievements); build order §7 step 3.
- **Scope (this session, step 3 only):**
  - `option_tables.lua` — NEW top-level **Progress** group next to Practice (level + XP
    bar, per-drill mastery, achievements, stats summary, confirmed reset). No existing
    practice / design / class-slot key is touched.
  - NEW `practice_progress_ui.lua` — the stats frame (accuracy sparkline over the last
    50 sessions, per-drill table, per-class table, history list).
  - The 7 flavour TOCs — `practice_progress_ui.lua` after `practice_progress.lua`.
  - `tests/options_load_state.lua` (new Progress-page section), NEW
    `tests/practice_progress_ui_state.lua`, `tests/run.sh` (+1 step).
- **Read-only inputs:** `practice_progress.lua`, `practice_stats.lua` (sibling lane owns
  them), `db.profile.practice` (the hook lane wires that key; read defensively).
- **Out of scope:** `practice.lua`, `practice_ui.lua`, `practice_progress.lua`,
  `practice_stats.lua`, `config.lua`, `config_presets.lua`, class files, `main.lua`,
  `diag.lua`, `compat.lua`, `hud.lua`, `bars.lua`, guides, engines, versions, README,
  CHANGELOG, docs, git, lint config.
- **Next step:** read the pure modules' read model, then write
  `practice_progress_ui.lua` + the Progress group.

## 2026-10-19 — Progress page + stats frame built (spec §7 step 3)
- **Worked on:** NEW `practice_progress_ui.lua` (1212 lines) — the read model that
  composes the two pure read models (`st.practice_stats.snapshot` +
  `st.practice_progress.profile_snapshot`), the renderers (level, XP bar, per-drill
  mastery, achievements, stats summary), and the stats frame: the accuracy **sparkline**
  over the last 50 sessions (a pooled bar + a top marker per session, coloured by
  accuracy band), the **per-drill table**, the **per-class table** (only when more than
  one class has data) and the **session history** (newest first, wheel-scrolled by the
  module itself, with a thumb that tracks the offset). The frame is built on the first
  open and hidden otherwise. The scope defaults to the player's class and a "Scope"
  button cycles the classes with data plus the account scope. The reset arms, then
  confirms: it replaces **only** `db.profile.practice` with a fresh profile, drops the
  hook lane's live cache (its next save would restore the erased state) and refuses a
  blob written by a newer build.
  NEW top-level **Progress** group in `option_tables.lua` (order 1.47, next to Practice
  1.46): level + XP bar, per-drill mastery table, achievements list, stats summary, the
  all-classes line, "Open the stats frame" and the confirmed reset. **No existing
  practice / design / class-slot key is touched** and none of the page's widgets
  carries a `get`/`set` — the page writes no db key at all. The 7 flavour TOCs gained
  `practice_progress_ui.lua` after `practice_progress.lua` (CRLF preserved; the base
  toc's `## Interface: 11509, 20506, 38002` line untouched). NEW
  `tests/practice_progress_ui_state.lua`, `tests/options_load_state.lua` section 20
  (+ the three pure modules in the sandbox, + an `eq` helper), `tests/run.sh` +1 step.
- **Current state:** `tests/practice_progress_ui_state.lua` **252 checks PASS** ·
  `tests/options_load_state.lua` **3251 checks PASS** · `tests/toc_check.lua` **830
  checks, 0 failures** · full harness **41 steps, 0 failed** · luacheck **2 warnings /
  0 errors** in 82 files (the repo floor; 0 in the 4 touched files) · **mutation proofs
  33/33 killed** (`/tmp/opencode/practice_progress_ui_mutations.py`; classes: a missing
  consumer — the toc line removed → toc_check red; a bad default — the page's order
  moved, a db key added to the page, the XP bar width; the reset wiring; the
  sparkline; the history order and the scroll; the per-class table; the formatters).
  Bench artifact: `bench/buildout_practice_progress_ui_2026-10-19.md`.
  **In-client behaviour is UNCONFIRMED**, like every offline pin — the frame's look,
  the sparkline colours and the wheel scroll need an owner test session.
  **Crossfire note:** two harness reds appeared during this lane and were NOT mine —
  `tests/practice_ui_state.lua` (a frame-count pin, 69→70) while the practice-hook lane
  added the panel badge to `practice_ui.lua`, and `tests/hunter_state.lua` (the
  "absent resolver hides" pin) while the hunter lane edited `classes/hunter.lua` at
  20:24. Both cleared when their own lanes landed their pins; the final harness run is
  **41 steps, 0 failed**.
- **Next step:** orchestrator validation (owns Done). Two things a later lane may want:
  the frame's position is session-local (no new db key — `config_presets.lua` was out of
  this lane's scope); the page shows the current class scope, with the account total as
  a second block when it holds more than the class does.

## 2026-10-19 — [signal:done] Progress page + stats frame complete, 33/33 mutations killed
- The Progress page renders with real data and with none, the stats frame draws the
  sparkline, the TOC coverage is green on all 7 flavours, the harness is green
  (41 steps / 0 failed) and the luacheck floor held (2/0). The lane read
  `db.profile.practice` and wrote to it only through the confirmed reset.
