# Practice progress UI — buildout (spec step 3, 2026-10-19)

Lane: **practice-progress-ui** (desk `desks/practice-progress-ui/`).
Spec: `bench/practice_gamification_design_2026-10-19.md` §3 (stats section) / §4
(achievements); build order §7 **step 3** — the Progress options page + the stats frame.

## What was built

### 1. NEW `practice_progress_ui.lua` (1212 lines)

The read model + the stats frame. It **reads** the live data the hook lane (step 2)
writes into `SwedgeTimerDB.profile.practice` and renders it; it never recomputes a
number the pure modules own.

- **The read model** — `ui.scope_model(ST, scope_key)` composes the two pure read
  models: `st.practice_stats.snapshot(stats_state)` (runs / attempts / hits / misses /
  accuracy lifetime + rolling-20 + last session / best score / best grade / time active
  / the per-drill table / the bounded history) and
  `st.practice_progress.profile_snapshot(progress, stats_snapshot, scope_key)` (level /
  renown / XP / per-drill mastery + tier / streaks / unlock flags). Every figure on the
  page therefore comes from the rules that produced the data.
- **The renderers** — `render_level`, `render_xp_bar` (20 cells), `render_mastery`
  (tier + mastery % + attempts + accuracy), `render_achievements` (unlocked/locked),
  `render_stats` (runs, attempts, accuracy, rolling-20, last session, time active, best
  score, best grade, best streak), `render_page`.
- **The stats frame** — built on the first open, hidden otherwise: the accuracy
  **sparkline** over the last 50 sessions (one pooled bar + a top marker per session,
  coloured by accuracy band), the **per-drill table**, the **per-class table** (shown
  when more than one class has data), and the **session history** (newest first, wheel
  scrolled, with a thumb that tracks the offset).
- **The scope** — the frame shows the player's own class by default and a "Scope" button
  cycles through every class that has data plus the account scope ("All classes").
- **The reset** — `ui.request_reset` arms, a second call performs, `ui.disarm_reset`
  cancels. The performed reset replaces **only** `db.profile.practice` with
  `st.practice_progress.new_profile()`, drops the hook lane's live cache (its next save
  would otherwise restore the erased state) and refuses a blob written by a **newer**
  build (`schema_version` above ours) — that data is not ours to erase.
- **Drill names** — a drill id that is a registered practice scenario is named after the
  scenario's own title (`paladin_twist` → "Twist practice"); anything else falls back to
  the raw id (never a guess).

### 2. `option_tables.lua` — the NEW top-level **Progress** group (order 1.47, next to
Practice 1.46)

`progress_desc`, `progress_level`, `progress_xp_bar`, `progress_mastery_header` +
`progress_mastery`, `progress_achievements_header` + `progress_achievements`,
`progress_stats_header` + `progress_stats`, `progress_account` (the all-classes line,
only when it holds more than the class does), `progress_open_stats` (opens the frame),
`progress_reset_header` + `progress_reset` + `progress_reset_cancel`.

**No existing practice / design / class-slot key is touched** — the group is purely
additive and **none of its widgets carries a `get`/`set`**, so the page writes no db key
at all; the reset goes through the module. The description widgets' `name` is a function,
so the page always carries the live numbers.

### 3. The 7 flavour TOCs — `practice_progress_ui.lua` after `practice_progress.lua`
(base + Vanilla/TBC/Wrath/Mainline/Cata/Mists). CRLF preserved on every one; the base
toc's `## Interface: 11509, 20506, 38002` line is untouched.

### 4. Tests
- NEW `tests/practice_progress_ui_state.lua` (252 checks): the load surface (no frame
  at file load), the read model with **no data** (missing key, missing half, corrupt
  blob, wrong-typed blob, malformed scope, no pure modules), the read model **with
  data** (level, XP, drill rows, achievements, stats, class list, account scope), the
  renderers, the frame (build on first open, sparkline bar per session, the tables, the
  scope cycle, the empty frame), the wheel scroller (offset + clamping) and the reset
  (arm / confirm / cancel / newer-blob refusal / hook-cache drop / sibling profile keys
  untouched).
- `tests/options_load_state.lua`: the three pure + UI modules are now loaded in the
  sandbox, an `eq` helper was added, and **section 20** pins the Progress page (the
  group in every class's tree, its widget set and types, no db key, no collision with a
  Practice key, the Practice panel's own keys still intact, the renderers with and
  without data, the two-step reset and its cancel, the stats-frame button wiring).
- `tests/run.sh`: +1 step (`practice_progress_ui_state`).

## Validation (in-tree, 2026-10-19)

| Check | Result |
| :--- | :--- |
| `tests/practice_progress_ui_state.lua` | **252 checks, 0 failed** |
| `tests/options_load_state.lua` | **3251 checks, 0 failed** |
| `tests/toc_check.lua` | **830 checks, 0 failures** |
| full harness `bash tests/run.sh` | **41 steps, 0 failed** |
| `luacheck .` | **2 warnings / 0 errors** in 82 files (the repo floor; 0 in the 4 touched files) |
| mutation proofs (`/tmp/opencode/practice_progress_ui_mutations.py`) | **33 / 33 killed** |

Mutation classes covered: a **missing consumer** (the toc line removed → `toc_check`
red), a **bad default** (the page's order moved, a db key added to the page, the XP bar
width, the model always "has data"), the reset wiring (never arms, does not replace the
blob, keeps the hook lane's cache, erases a newer blob), the sparkline (no bars, wrong
height), the history order and the scroll (does nothing, unclamped, no wheel), the
per-class table always shown, and the formatters.

## Notes / limits (UNCONFIRMED in-client)

- **In-client behaviour is UNCONFIRMED**, like every offline pin. The frame's look, the
  sparkline's colours and the wheel scrolling need an owner test session.
- The **history list is scrolled by this module**, not by a client `ScrollFrame`: the
  offset and the thumb are computed here, so the scroll is fully offline-provable and
  does not depend on the client's scroll semantics. The newest sessions are visible
  even if the wheel never fires.
- The frame's position is **session-local** (no new db key — the scope forbids
  `config_presets.lua`).
- The page shows the **current class** scope; the account total appears as a second
  block when it holds more than the class does.
- The lane **read** `db.profile.practice` and wrote nothing to it except the confirmed
  reset.
