# practice persist — the H2 / M1 / M4 fixes (2026-10-20)

Desk: `practice-persist`. Scope: `practice_ui.lua`, `practice_progress_ui.lua`,
`main.lua` (the `PLAYER_LOGOUT` handler only), `tests/practice_ui_state.lua`,
`tests/practice_progress_ui_state.lua`, `tests/main_init_state.lua`.

Nothing outside that scope was touched: no `practice.lua`, `practice_progress.lua`,
`practice_stats.lua`, `option_tables.lua`, `config_presets.lua`, class file,
`compat.lua`, `hud.lua`, `bars.lua`, `run.sh`, TOC, version or doc. No git.

## The three findings, and what each one needed

### H2 (HIGH) — a completed session is lost on logout

`ui.end_progress_session` was the only writer of the completion bonus, the daily
streak (class + account), the run counter, the accumulated time active and the
bounded history row, and it had exactly one caller: `ui.stop`
(`practice_ui.lua`). `ST:PLAYER_LOGOUT` (`main.lua`) did not flush it.

**Fix — a dedicated flush, `ui.flush_progress_session(self, now)`:**

* it ends the progression session and persists it, and it does **not** tear the
  frames down (a logout is not a session end — `ui.stop`'s teardown is a separate
  risk: `ClearOverrideBindings`, the overlay detach, the proc-icon hides);
* it is idempotent (a session that is already closed flushes nothing) and it
  reports honestly whether it wrote (`end_progress_session` returns its result,
  `nil` when it refused to close a session it could not write);
* three callers: `ui.stop` (the session end), `main.lua`'s `PLAYER_LOGOUT`
  (the logout), and the practice panel's `OnHide` (the panel's hide).

The panel's `OnHide` script (`practice_ui.lua`, in `build_panel`) is new: hiding
the practice panel flushes the progression session. `ui.stop` already flushed
before it hides the panel, so the `OnHide` flush is a no-op there — it is the
safety net for any other hide path.

**Why the logout flush lands in the saved variables.** AceDB registers its own
`PLAYER_LOGOUT` handler at library load (`Libs/AceDB-3.0/AceDB-3.0.lua:389`), and
`AceDB-3.0.xml` loads before `AceEvent-3.0.xml` in every TOC, so AceDB's handler
runs first: it strips the defaults from the live profile
(`RegisterDefaults(nil)` → `removeDefaults`) and cleans the empty sections. The
addon's handler (registered through AceEvent) runs after it and writes the fresh
blob into `profile.practice` — i.e. into `sv.profiles[key]` — after the strip, so
the blob is not eaten by the default-stripping. The client serialises the
SavedVariables after `PLAYER_LOGOUT` is dispatched, so the write is on disk.

**Caveat (stated, not hidden):** a UI `/reload` fires **no** `PLAYER_LOGOUT` and
writes **no** SavedVariables — the client only serialises them at logout. No
addon-side hook can put a session on disk at reload time; the logout flush is
the fix for the logout case, and a reload loses the in-flight session whatever
the addon does. This is client behaviour, not an addon defect, and it is
recorded here so the next desk does not re-derive it.

### M1 (MEDIUM) — a Progress-page reset mid-session drops every later attempt

`clear_progress_cache` (`practice_progress_ui.lua`) nils the hook lane's live
cache; `ui.record_progress_attempt` then returned **before** `ui.update_badge`,
and nothing re-created the profile (`ensure_progress_profile` was only reached
from `update_badge`, which was skipped, or from `begin_progress_session`). The
score still moved; no XP, no mastery, no streak, no stats, no badge.

**Fix, two halves:**

1. `ui.record_progress_attempt` now calls `ui.ensure_progress_profile(self)`
   itself, so the profile exists before the attempt is recorded. The attempt
   cannot be dropped by a dropped cache again.
2. The reset also clears the **in-flight session's** counters: the reset lane
   calls the hook lane's new `ui.reset_progress_session()`, which replaces
   `ui.progress_session` with a fresh pure session (`P.new_session()` — the pure
   module owns the shape) and repaints the badge, so the erased XP does not stay
   on the badge's "+N XP" line.

The session itself keeps running (the score, the simulation and the panel are
untouched); only its progression bookkeeping restarts. The session's start stamp
(`ui.progress_started_at`) is deliberately **not** reset: the run's time active
then still matches the score summary the history row carries.

**The badge is why the fix has two halves.** With the badge ON, `update_badge`
re-creates the profile, so half 1 would look unnecessary; with the badge OFF,
`update_badge` returns before it re-creates the profile and half 1 is the only
thing that keeps the recording alive. Both paths are pinned (26c badge off, 26c
badge on).

### M4 (MEDIUM) — a client without `date` freezes the daily XP cap forever

`current_day()` returned `nil` when `date` was missing; `P.record_attempt`
(`practice_progress.lua:607-611`) resets `drill.daily_xp` only when the day
ordinal is non-nil and the day changed — so the counter accumulated across days
until the drill awarded **0 XP for good**, silently.

**Fix, in two layers (both in `practice_ui.lua`; `practice_progress.lua` is out of
scope):**

1. `current_day()` falls back to the client's own clock: `time()` gives the epoch
   seconds and the day index is `floor(now / 86400)` — an opaque day counter
   whose consecutive days differ by exactly 1, which is exactly what the pure
   layer's `day_ordinal` accepts of a number. So on a client with a clock but no
   `date`, the cap resets every day (the anti-grind still holds) and the daily
   streak still advances.
2. A client with **neither** a calendar nor a clock still has no day. The cap may
   then swallow an award, and that is no longer silent: `record_progress_attempt`
   compares the session's XP before and after the attempt and, when a grade that
   is worth points moved nothing and the day is unknown, it prints one notice
   naming the cause ("this client reports no calendar date, so the daily XP cap
   cannot reset"). Once per session, not once per attempt.

The notice goes through `self:Print` (not the badge-gated `announce`), because a
diagnostic that rides an opt-in toggle is a diagnostic nobody sees.

## What the pins cover

`tests/practice_ui_state.lua` — new section 26:

| Pin | What it holds |
|---|---|
| 26a | the flush writes the bonus, the streak, the run, the time and the history row, and it leaves the panel, the driver and the live session alone; a second flush closes nothing |
| 26b | the practice panel carries a hide script, and hiding the panel flushes the run, the streak and the time |
| 26c | a mid-session reset (the **shipped** `perform_reset`, driven through the real `practice_progress_ui.lua`) does not drop the later attempts: the XP, the streak and the stats are recorded again — with the badge OFF, where the hook lane's own ensure is load-bearing |
| 26c-bis | with the badge ON, the reset takes the erased XP off the badge and the next attempt shows only the post-reset XP |
| 26d | a client with no `date` but a clock: the cap resets on the next day (read from the clock) |
| 26e | a client with neither: the cap still bites, but it prints one notice naming the cause, once |
| 26f | a client with a calendar keeps using its own calendar day (the clock fallback never overrides a real date) |

`tests/practice_progress_ui_state.lua` — the reset drops the live cache **and**
asks the hook lane to clear the live session's counters; a hook lane without that
entry point does not break the reset.

`tests/main_init_state.lua` — `PLAYER_LOGOUT` calls the flush with the addon
object, unconditionally, and survives a missing practice UI module.

## Mutation proofs (disposable copies under `/tmp/opencode/mut`)

| Mutant | Change | Killed by |
|---|---|---|
| A | `main.lua`'s logout does not flush | `main_init_state`: 3 FAILs |
| B | `record_progress_attempt` does not ensure the profile (the pre-fix behaviour) | `practice_ui_state`: 5 FAILs |
| C | `current_day` has no clock fallback | `practice_ui_state`: 1 FAIL |
| D | `flush_progress_session` does not write | `practice_ui_state`: 27 FAILs |
| E | `reset_progress_session` does not clear the counters | `practice_ui_state`: 5 FAILs |
| F | `ui.stop` does not flush | `practice_ui_state`: 16 FAILs |
| G | the reset does not ask the hook lane | `practice_progress_ui_state`: 1 FAIL |
| H | the panel carries no hide script | `practice_ui_state`: 4 FAILs |
| I | the cap notice never prints | `practice_ui_state`: 2 FAILs |
| J | `main.lua`'s logout flush block removed | `main_init_state`: 3 FAILs |

## Harness

`bash tests/run.sh` → **41 steps, 0 failed**; luacheck **2 warnings / 0 errors in
83 files** (the standing floor: `compat.lua`'s unused `addon_name` and
`main.lua`'s `table.pack` — neither is in a touched file). The three suites this
lane owns: `practice_ui_state` 1441 checks, `main_init_state` 792 checks,
`practice_progress_ui_state` 255 checks — all green.

## Notes for the next desk

* **The Lua 5.1 limits still bite in `practice_ui.lua`.** The main chunk was at
  199 file-scope locals before this lane (the limit is 200); this lane added
  **zero** file-scope locals and kept every new piece of state on the `ui` table
  (`ui.progress_cap_notice`). A lane that adds a file-scope local must count
  first.
* **The sandbox's `_G` mirror leaks an absent global.** `tests/practice_ui_state.lua`
  mirrors its stubs into `_G` for the compat load and restores them after, but a
  nil previous value cannot be stored in the restore table (a nil assignment drops
  the key), so a global that was absent before a build stays in `_G` for the rest
  of the run. The M4 builds need a TRULY absent `date`/`time`, so they clear the
  leak themselves (`_G.date = nil` / `_G.time = nil`). The same leak is why
  `practice_ui.lua:1781` reads `STANDARD_TEXT_FONT` through `rawget(_G, ...)` —
  do not "fix" the mirror without auditing that read.
* **The file endings are per file:** `practice_ui.lua` and `main.lua` are CRLF;
  `practice_progress_ui.lua` and the three test files are LF. All four edited
  files kept their endings (checked with `grep -c $'\r$'`).
