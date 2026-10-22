# Progression Fix — Journal

## 2026-10-20 — Desk opened
- **Purpose:** fix the progression/gamification audit's HIGH (H-1) and the pure-module
  MEDIUMs (M-2, M-3) plus the cheap LOWs (L-1, L-4, L-6) in the pure practice
  progression surface.
- **Scope:** `practice_progress.lua`, `practice_stats.lua`,
  `tests/practice_progress_state.lua`, `tests/practice_stats_state.lua` ONLY.
  `practice_ui.lua` and `practice_progress_ui.lua` belong to sibling lanes — changes
  there are FILED for the orchestrator, not edited.
- **Source of the findings:** `desks/progression-audit/journal.md` (read-only audit,
  session `ses_ea616dd2cffeWFceVBxbz3Z2Ok`, verdict FINDINGS 13 — 2 HIGH, 5 MEDIUM,
  6 LOW).
- **Next step:** implement H-1 (the daily XP cap must have a non-zero floor), M-2
  (the account scope's unlocks must be evaluated), M-3 (the NO_DAY sentinel must
  survive a signed read), L-1 (an unknown unlock kind is rejected), L-4 (one shared
  grade-set predicate), L-6 (a one-directional day rollover + one day numbering),
  pin each one, and run the mutation proofs on /tmp/opencode copies.

## 2026-10-20 — H-1, M-2, M-3, L-1, L-4, L-6 fixed in the pure layer
- **Worked on:** the pure progression surface only — `practice_progress.lua`,
  `practice_stats.lua` and their two suites. H-1 (the daily cap is now 3× the
  median **hit** points, floored by the best hit in the window — two independent
  defences, either one alone stops the cap collapsing to 0); M-2
  (`P.evaluate_unlocks_both` evaluates the class scope AND the account scope and
  merges the two `newly` lists; the registry's doc comment now states the scope
  contract); M-3 (the history day is read SIGNED, so `NO_DAY` (-1) survives to the
  UI instead of becoming 1970-01-01); L-1 (an unknown unlock kind is rejected, not
  coerced to cosmetic); L-4 (`P.known_grade` / `S.known_grade` — one shared
  predicate over the scoring model's grade set, used by both `record_attempt`s);
  L-6 (the day rollover is ONE-DIRECTIONAL — a backwards clock can no longer wipe a
  day — and the day numbering is pinned to the civil-day count, documented in both
  modules' `day_ordinal`).
- **Current state:** own suites green (progress 494 checks / 0, stats 558 checks /
  0, both UI suites green); `luacheck` clean on all four touched files (0 warnings /
  0 errors) and the repo floor held (2 warnings / 0 errors in 83 files); mutation
  proofs 11 killed / 0 survived (+ 1 documented equivalent mutant) via
  `/tmp/opencode/progression_muts.sh`. The full harness shows 3 failures
  (`hunter_state` 1/1191, `hunter_guide_state` 2/1862, `hud_state` 1/731) — a
  **parallel lane's** in-flight edit to `classes/hunter.lua` (11:46, the Forever
  `steady` shot); none of those suites load `practice_progress.lua` or
  `practice_stats.lua` (grep 0). Report + the five FILED sibling-lane diffs:
  `bench/progression_fixes_2026-10-20.md`.
- **Also answered:** the audit's open ruling **RJ-2** — the `date` global EXISTS on
  every target family (Blizzard's own code calls it on classic_era,
  classic_anniversary, classic_titan, origin/forever and live), so the UTC `time()`
  fallback in `practice_ui.lua:current_day()` is dead code AND the only source of
  the second day numbering. It is filed for removal (§7.3 of the bench report).
- **Next step:** the orchestrator (validation owner) routes the five filed diffs:
  `practice_ui.lua` §7.1 (evaluate the account scope at session end), §7.3 (one day
  numbering), §7.4 (validate the grade before the live score counts it), §7.5 (the
  two cap notices' wording), and `practice_progress_ui.lua` §7.2 (read the history
  day signed). Until §7.1 lands, the account scope's achievements still never fire
  in production; until §7.2 lands, the history row still renders 1970-01-01.

## 2026-10-20 — [signal:done] H-1 + the pure-layer MEDIUMs/LOWs fixed, 5 call-site diffs filed
- Six findings closed in the pure layer; the call-site changes that need the
  sibling lanes' files are filed with exact diffs in
  `bench/progression_fixes_2026-10-20.md`.
- Signal file: `desks/progression-fix/.signals/2026-10-20T160500Z-done.json`.

