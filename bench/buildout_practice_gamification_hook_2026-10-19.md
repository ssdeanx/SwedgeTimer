---
name: practice-gamification-hook
date: 2026-10-19
lane: practice-gamification
scope: spec §7 step 2 - wire the pure progress/stats modules into the live session
  (session -> XP / mastery / streaks / time active, achievements, throttled
  persistence) + the practice panel's level badge and session XP bar.
---

# Practice gamification — hook lane (spec §7 step 2)

Design source: `bench/practice_gamification_design_2026-10-19.md` (§2 progression,
§3 stats, §4 achievements, §6 engineering) and the foundation lane's handoff
`bench/buildout_practice_gamification_foundation_2026-10-19.md` (§Handoff step 1).

## What landed

| File | Change |
| :--- | :--- |
| `config.lua` | `ST.defaults.profile.practice = ST.PRACTICE_DEFAULTS` (the AceDB default for the profile key) |
| `practice_ui.lua` | NEW "practice progression hook" section: the session feed, the time active, the achievement evaluation, the throttled persistence, the panel's level badge + XP bar |
| `practice_progress.lua` | `profile_snapshot` now LIFTS the stats scalars to the top level (the achievement predicates read one flat snapshot) |
| `practice_stats.lua` | unchanged (the hook needed no new entry point) |
| `tests/practice_ui_state.lua` | NEW section 21 (13 sub-sections, the hook + the badge) |
| `tests/practice_progress_state.lua` | +the lifted-snapshot pins, +the save/load round trip, +the `config.lua` wiring pin |
| `tests/practice_stats_state.lua` | +the save/load round trip, +the live summary shape |

No git, no lint-config change, no version/README/CHANGELOG/docs touch, no TOC
change (the modules were already listed), no `option_tables.lua` (the Progress page
is the step-3 lane), no `config_presets.lua`, no `main.lua`/`diag.lua`/`compat.lua`/
`hud.lua`/`bars.lua`, no class files, no `tests/run.sh` change.

## The hook (`practice_ui.lua`)

### The profile (load-time migration + replacement, never mutation)

```
ui.ensure_progress_profile(self)
  -> db.profile.practice = st.practice_progress.migrate(db.profile.practice or {})
```

* The profile KEY is REPLACED with a NEW table on every write (the AceDB default
  `ST.PRACTICE_DEFAULTS` is never touched - AceDB copies the defaults into the
  profile, and the hook never edits the default's tables).
* A blob a NEWER build wrote (`schema_version > 1`) is left EXACTLY as it is and is
  never written over: the hook runs in memory only until that build comes back
  ("we never wipe what we do not understand").
* A corrupt blob is repaired by `migrate` (never throws) and a sibling profile key
  is untouched.

### The session feed

`ui.record_graded_attempt(self, grade, lead_ms)` is the single entry point every
graded attempt goes through (the engine's grading path calls it), so the session
score and the progression can never drift apart. It feeds:

* `P.record_attempt(progress, session, class_key, drill_id, grade, day)` - XP under
  the daily per-drill cap, the session streak, the per-drill mastery window;
* `S.record_attempt(stats, class_key, grade, drill_id)` - the lifetime counters, the
  per-drill table, the best grade, the best S-run.

The five call sites (hunter / shaman / rogue / druid casts + the paladin tick) now
route through it. The drill key per class is the harness scenario key
(`paladin_twist`, `hunter_forced_move`, `shaman_weave`, `rogue_energy_pool`,
`druid_powershift`); the warrior panel runs the shared twist session, so it grades
the twist drill.

### Time active

The session's live window, measured on the injected monotonic clock
(`st.api.get_time()`), never a wall clock: `duration = api.get_time() - started_at`,
where `started_at` is stamped when the session begins. Only the time between the
session's start and its end counts - the idle time between two sessions never lands
in the total (pinned).

### The session end

`ui.end_progress_session` (called from `ui.stop`):

1. `S.record_session(stats, class_key, summary, duration, day)` - the run, the time
   active, the best session score and the bounded 50-session history ring (a
   session with no attempts is not a completed session);
2. `P.end_session(progress, session, class_key, day, {})` - the completion bonus and
   the daily streak (a missed day FREEZES it);
3. `P.evaluate_unlocks(progress, P.profile_snapshot(...), class_key)` - the
   achievement predicates (spec §4), the class scope;
4. one write.

### The writes (throttled, never per attempt)

| When | Write |
| :--- | :--- |
| load (the migration) | yes - the profile key is replaced with the repaired blob |
| session end | yes |
| level-up | yes (the only write an attempt can cause) |
| live session | at most once every `PROGRESS_SAVE_INTERVAL` = 300 s (checked in the driver tick) |
| any other attempt | NO |

### The panel badge (opt-in, OFF by default)

A small companion frame UNDER the panel's bottom-left corner: the panel's own rows
are full (the title, the icon grid and the rotation grid span its whole width), so
the badge hangs below the panel instead of overlapping anything, and the panel's
height is untouched (the badge is an overlay, not a new row).

* `badge.level` - "Lv 3" (or "Lv 50 +2" past the level cap)
* `badge.xp` - "80/100" (the XP into the level / the XP for the next level)
* `badge.bar_fill` - the level-progress bar
* `badge.session` - "+80 XP" (the XP this session earned)

The toggle is the db key `practice_panel_badge` on the CLASS table
(`db.practice_panel_badge == true`; nil = off, `== false` hides). `ui.set_badge_enabled`
writes it and repaints. **The badge ships OFF**: the operator has not gated a
default-visible change, so the default-flip request is filed in the desk journal.

The chat notices (level-up, achievement unlocked) ride the SAME opt-in: with the
toggle off the progression runs silently - the data is still collected and saved,
but nothing is printed and nothing is drawn. The unlock lane (spec §7 step 4) owns
the toast.

## The pure-module change (`practice_progress.lua`)

`P.profile_snapshot` now lifts the stats scalars (`runs`, `attempts`, `hits`,
`misses`, `accuracy`, `rolling_accuracy`, `last_session_accuracy`,
`best_session_score`, `best_grade`, `best_s_streak`, `time_active_seconds`) to the
TOP level of the merged snapshot, next to the level, the streaks and the drill rows
that were already there. The achievement predicates read exactly that flat shape
(`snapshot.best_grade`, `snapshot.best_s_streak`, `snapshot.attempts`,
`snapshot.time_active_seconds`), so the caller evaluates them with the snapshot the
read model already produces - no second merge by hand. The `.stats` sub-table is
unchanged (the Progress page reads it), and an absent value stays absent (never a
zero that would read as a real measurement). The foundation's own test had already
assumed this shape ("the stats side supplies the grade" - it set `snap.best_grade`
by hand).

## Verification

* `lua5.1 tests/practice_ui_state.lua` -> **1205 checks, 0 failures** (the new
  section 21 covers: no-db inertness, the migration, the corrupt blob, the newer
  blob, the live feed through the real engine path, the time active, the daily
  streak, the achievements, the daily XP cap, the write throttle, the level-up
  write, the badge off/on, the level / XP / bar / session-XP readouts and the
  nil-safe toggle).
* `lua5.1 tests/practice_progress_state.lua` -> **420 checks, 0 failures**.
* `lua5.1 tests/practice_stats_state.lua` -> **433 checks, 0 failures**.
* `bash tests/run.sh` -> **41 steps, 0 failed** (the sibling step-3 lane added its
  own step while this lane ran). luacheck **2 warnings / 0 errors in 82 files** -
  the floor, unchanged (the two warnings are `compat.lua` and `main.lua`, both
  KEEP-ruled and not this lane's files).
* **mutation proofs: 26/26 killed** on `/tmp/opencode/practice-hook-mut` (script
  `/tmp/opencode/practice_hook_mutations.py`) - one mutant per rule: the badge
  default, the toggle read, the badge visibility, the bar fill, the level / XP /
  session-XP texts, the badge's parent, the profile-key replacement (three ways:
  never replaced, edited in place, the newer blob overwritten), the write throttle,
  the level-up write, the XP feed, the injected day, the stats feed, the drill key,
  the session-end record, the time active, the daily streak, the achievement
  evaluation, the notice gate, the session start, the lifted snapshot scalars, the
  config wiring.

## Crossfire seen during the lane (NOT this lane's files)

The step-3 lane (`desks/practice-progress-ui/`, `practice_progress_ui.lua` +
`option_tables.lua` + the TOCs + `tests/run.sh`) landed **while this lane was
running**: its new module appeared in the tree at 19:58 and its new suite
(`tests/practice_progress_ui_state.lua`) was red for a few minutes at ~20:05 (24
checks, the history-row order) before it went green at ~20:11. That lane declares
`practice_ui.lua`, `practice_progress.lua`, `practice_stats.lua` and `config.lua`
as its read-only inputs, so there is no file overlap. Its module reads
`P.profile_snapshot` for the level / renown / XP / streaks / drills / unlocks -
all unchanged by this lane's additive lift.

## Open / filed for the operator

1. **Default-flip request (filed, not applied):** the practice level badge and the
   progression chat notices ship OFF (the db key `practice_panel_badge` must be
   exactly true). The operator has not gated a default-visible change, so the
   default stays off; the request is to flip it to ON by default (or to add the
   option to the Progress page and let the player choose).
2. **The options widget is the step-3 lane's job:** the Progress page owns the
   toggle widget; this lane only ships the db key, the nil-safe read and the
   `ui.set_badge_enabled` entry point it can call.
3. **The toast is the step-4 lane's job:** this lane prints a chat notice (gated
   on the same opt-in); the unlock lane owns the toast and the cosmetics.
4. **In-client behaviour is UNCONFIRMED**, like every offline pin: the live
   session feed, the badge's rendering and the AceDB save have not been observed in
   a client.
