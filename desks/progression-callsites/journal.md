# Progression Call Sites — Journal

## 2026-10-20 — Desk opened
- **Purpose:** land the call-site changes the three progression lanes left FILED —
  the pure lane's §7.1–§7.5 (`bench/progression_fixes_2026-10-20.md`), the UI
  lane's filed pins (`bench/progression_ui_fixes_2026-10-20.md` §7) and the
  drill-list pick contract F-1 (`bench/drill_pick_contract_2026-10-20.md` §3).
- **Scope:** `practice_ui.lua`, `practice_progress_ui.lua`,
  `tests/practice_ui_state.lua`, `tests/practice_progress_ui_state.lua` — and
  NOTHING else. `practice_progress.lua` / `practice_stats.lua` are owned by a
  sibling lane (the pure side is done); the class files, the options, `main.lua`,
  `diag.lua`, `compat.lua`, `hud.lua`, `bars.lua`, `run.sh`, the TOCs, the
  versions and the docs are all out of scope. No git commit, no lint-config
  change.
- **Hard constraint:** `practice_ui.lua` sits at 199 of Lua 5.1's 200 file-scope
  locals — every new piece of state must ride the `ui` table, never a new
  file-scope local (the second one is a LOAD FAILURE).
- **Next step:** read the three bench artifacts, apply the five filed diffs, paste
  the filed pins, implement F-1 (the drill-list press wins over a class-published
  pick alias) and pin it, then run the harness + luacheck and prove the mutants
  die on `/tmp/opencode` copies.

## 2026-10-20 — Baseline read
- **Worked on:** read `bench/progression_fixes_2026-10-20.md` (§7.1–§7.5),
  `bench/progression_ui_fixes_2026-10-20.md` (§7 pins) and
  `bench/drill_pick_contract_2026-10-20.md` (§3); read the four in-scope files
  and the pure modules' contracts.
- **Current state:** harness **41 steps / 0 failed**, luacheck **2 warnings / 0
  errors in 83 files** (the floor) — the tree is green before this lane touches
  anything. `practice_ui.lua` is CRLF; `practice_progress_ui.lua` and the two
  test files are LF.
- **Next step:** apply the diffs.

## 2026-10-20 — The filed call sites landed + the pick contract
- **Worked on:** applied the pure lane's §7.1–§7.5 to `practice_ui.lua` and
  `practice_progress_ui.lua`; pasted the UI lane's filed pins (§26i/§26j/§26k) into
  `tests/practice_ui_state.lua`; wrote §28 (the five filed call sites' pins) and §29
  (the F-1 pick-contract pins) there; wrote §9 (the `NO_DAY` sentinel reaches the
  renderer) in `tests/practice_progress_ui_state.lua`; implemented F-1 in
  `drill_list_grade` (the press OVERWRITES `ctx.pick` / `ctx.pressed` / `ctx.action`
  instead of filling only an empty alias).
- **Current state:** harness **41 steps / 0 failed**; luacheck **2 warnings / 0
  errors in 83 files** (the floor). Own suites: `practice_ui_state.lua` **1666
  checks**, `practice_progress_ui_state.lua` **290 checks**, both 0 failed.
  `practice_ui.lua` is still at **199 file-scope locals** (`luac5.1 -l -l`). CRLF
  preserved. Mutation proofs: **7 killed, 0 survived**
  (`/tmp/opencode/progcalls_muts.py`, fresh copy per mutant).
- **Next step:** the orchestrator validates. One follow-up is owed by another lane
  (see below).

## 2026-10-20 — [signal:done] the lane's work, and the one gap it leaves
- **Delivered:** the account scope's achievements evaluate at the session end; the
  `NO_DAY` sentinel reaches the renderer; ONE day numbering (the civil calendar, the
  UTC clock fallback is gone); an unknown grade cannot move the live score; the two
  cap notices describe the shipped cap (3x the median HIT XP, and "up to its cap"
  when there is no calendar); the UI lane's filed pins are in the suite; and a
  drill-list press grades the PRESS, not the class's live cast.
- **The gap (another lane's file, deliberately NOT touched):** the comment at
  `classes/hunter.lua` ("The engine's drill press carries no action, so the live
  cast is the player's own pick") is now STALE — after the F2 fix the drill press
  DOES carry an action, and the press is the pick. The production behaviour is
  correct without the comment; the class file is out of this lane's scope, so the
  hunter lane owns the comment.
- **What did not work / was deliberately not done:** the pure lane's §26d pin in
  `tests/practice_ui_state.lua` asserted the OLD rule (a clock-only client still
  gets a day and the cap resets) and had to be REWRITTEN — it contradicted the
  shipped rule, so it could not stay. The narrower F-1 shape (§3's "the drill-list
  press builds its ctx without the class's published pick at all") would have
  BROKEN the hunter's own drill behaviour (a press-less drill press would answer
  UNKNOWN instead of judging the shot in flight); the wide shape (overwrite, but
  only when there IS a press) keeps it. The mutation harness also reports a mutant
  that breaks the file as INVALID rather than as a kill — the first W1a mutant was
  a syntax error, not a pin failure, and was corrected before the final run.

