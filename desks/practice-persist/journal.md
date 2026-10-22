# Practice Persist — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the three deep-audit defects in the PRACTICE PERSISTENCE path —
  H2 (a completed session is silently lost on logout / `/reload`), M1 (a Progress-page
  reset during a live session drops every later attempt) and M4 (a client without the
  `date` global freezes the daily XP cap forever).
- **Scope:** `practice_ui.lua`, `practice_progress_ui.lua`, `main.lua` (the
  `PLAYER_LOGOUT` handler ONLY), `tests/practice_ui_state.lua`,
  `tests/practice_progress_ui_state.lua`, `tests/main_init_state.lua`.
  NOT in scope: `practice.lua`, `practice_progress.lua`, `practice_stats.lua`,
  `option_tables.lua`, `config_presets.lua`, class files, `compat.lua`, `hud.lua`,
  `bars.lua`, `run.sh`, TOCs, versions, docs. No git.
- **Next step:** read the three call sites, design the flush, implement, pin each
  defect with a mutation proof on a `/tmp/opencode` copy.

## 2026-10-20 — H2 / M1 / M4 fixed and pinned
- **Worked on:** the practice-persistence path. H2 (a completed session was lost on
  logout): a dedicated `ui.flush_progress_session` (ends the progression session,
  persists it, no frame teardown, idempotent, honest return value) now has three
  callers — `ui.stop`, `main.lua`'s `PLAYER_LOGOUT` and the practice panel's new
  `OnHide`. M1 (a mid-session Progress-page reset dropped every later attempt):
  `record_progress_attempt` ensures the profile itself, and the reset now asks the
  hook lane to clear the live session's counters (`ui.reset_progress_session`, a
  fresh pure session + a badge repaint). M4 (a client without `date` froze the
  daily XP cap forever): `current_day()` falls back to the client's clock
  (`floor(time()/86400)`, an opaque day ordinal the pure layer accepts), and a
  client with neither a calendar nor a clock now gets ONE printed notice instead
  of a silent 0 XP.
- **Current state:** all three fixed and pinned. `bash tests/run.sh` → 41 steps,
  0 failed; luacheck 2 warnings / 0 errors (the standing floor, neither warning in
  a touched file). The three owned suites: 1441 / 792 / 255 checks, green. Ten
  mutation proofs on disposable copies under `/tmp/opencode/mut`, all killed.
  Artifact: `bench/practice_persist_2026-10-20.md`.
- **Next step:** the orchestrator validates. The central lane row
  (`desks/journal.md`) is the orchestrator's to write — this desk did not touch it.

## 2026-10-20 — What the next desk should know
- `practice_ui.lua` was at **199** file-scope locals (Lua 5.1's limit is 200) and
  this lane added **zero**; every new piece of state rides the `ui` table. Count
  before adding a local.
- The `/reload` half of H2 is **not** fixable by an addon: a UI reload fires no
  `PLAYER_LOGOUT` and writes no SavedVariables (the client serialises them at
  logout only). The logout flush is the fix for the logout case; a reload loses
  the in-flight session whatever the addon does. Recorded in the bench artifact.
- Dead end worth keeping: the test sandbox's `_G` mirror cannot restore an
  ABSENT global (a nil previous value drops the key from the restore table), so
  `date`/`time` leaked between builds and the first M4 pin read a stale calendar.
  The M4 builds now clear the leak themselves. The same leak is why
  `practice_ui.lua:1781` reads `STANDARD_TEXT_FONT` through `rawget(_G, ...)` — do
  not "fix" the mirror without auditing that read.
- The M1 fix has two halves because the badge hides one of them: with the badge
  ON, `update_badge` re-creates the profile; with the badge OFF it returns before
  it does. Both paths are pinned (26c / 26c-bis).

## 2026-10-20 — [signal:done] H2 / M1 / M4 closed, pinned and mutation-proofed
- Signal file: `desks/practice-persist/.signals/2026-10-20T14-18-00Z.json`.
- Artifact: `bench/practice_persist_2026-10-20.md` (the findings, the pins, the
  ten mutation proofs, the harness result and the caveats for the next desk).


