# progression-audit journal (filed by orchestrator — hunter has no write tools)

## 2026-10-20 — progression/gamification surface audit (ses_ea616dd2cffeWFceVBxbz3Z2Ok)

Read-only, 9 files (practice_progress.lua, practice_stats.lua, practice_progress_ui.lua, the
progression half of practice_ui.lua, config_presets/config wiring, option_tables' Progress
page, the 3 progress suites). 27 error-handling/fallback locations reviewed.
Disposition: 11 confirmed defects, 2 needing a ruling, 4 justified exceptions.

VERDICT: FINDINGS 13 — 2 HIGH, 5 MEDIUM, 6 LOW.

### HIGH
- H-1 `practice_progress.lua:308-321,391-396,604-635` — the daily cap is `3 × median(grade points
  over the window)`; F=0 points, so below 50% rolling accuracy the median is 0 → cap 0 → **every
  award is 0 forever** (≈50 consecutive hits to escape, and the tier ladder is accuracy-gated
  too). Fix: the cap needs a floor that cannot be zero (e.g. `max(median*3, points(current grade))`)
  or the median must be over HITS only. Root is the spec wording ("3× the drill's median XP").
- H-2 `practice_ui.lua:1315-1342` — the daily-cap swallow is **detected but never reported**
  (the notice is gated on `day == nil`). The badge/XP bar/level silently stop for the day while
  the score keeps counting. Fix: one notice per drill per day, printed through the same
  non-badge-gated path the M4 notice uses.

### MEDIUM
- M-1 `practice_ui.lua:1126-1135,1157-1173,1439-1448` + `main.lua:1134-1143` — a blob written by a
  NEWER build is protected (never overwritten) but the refusal is **silent** and the logout flush
  reports success while nothing is written. Fix: one notice, and the flush must report the WRITE.
- M-2 `practice_progress.lua:859-903` + `practice_ui.lua:1407` — the ACCOUNT scope's achievements are
  never evaluated in production (only the class scope is) → the account model reports 0 of 7.
- M-3 `practice_stats.lua:603-604` + `practice_progress_ui.lua:425` — `count()` clamps the
  `NO_DAY` sentinel (-1) to 0, so the "if day < 0" branch is dead code and the history row renders
  **1970-01-01** instead of "-".
- M-4 `practice_progress_ui.lua:358,585-596,1046-1052` — the DAILY STREAK is computed into the read
  model and **never displayed** (the page shows the lifetime best instead).
- M-5 `practice_progress_ui.lua:615-633` — the reset's armed state never expires and is not
  disarmed when the options panel closes → a stale "Confirm: reset" button can wipe everything.

### LOW
- L-1 `practice_progress.lua:758-768` — `register_unlock` coerces an unknown kind to "cosmetic"
  (a typo'd kind silently grants nothing) → reject instead.
- L-2 `practice_progress.lua:604-610` vs `practice_stats.lua:297-306` — the reserved `_unknown`
  bucket is recorded on one side only → a self-contradictory row ("Bronze, 60% mastery, 0.0% accuracy").
- L-3 `practice_progress.lua:1023-1034` — the account-scope drill merge is last-writer-wins (latent:
  every shipped drill id is class-prefixed).
- L-4 `practice_ui.lua:1356-1365` vs `practice.lua:1389-1395` — an unknown grade advances the live
  score but is dropped by both pure modules (latent).
- L-5 `practice_ui.lua:1157-1187` — the 5-minute write throttle is inert (the profile always holds
  the live tables); the spec overstates it as a durability guarantee. Do not change the write shape.
- L-6 `practice_progress.lua:620-624` + `practice_ui.lua:1040-1054` — the cap re-opens on a backwards
  clock, and the two day-ordinal numberings (local-date vs UTC) are not interchangeable.

### Rulings needed
- RJ-1 — does a misses-only session count as a "completed day" for the daily streak?
- RJ-2 — is the no-calendar path reachable in a shipped client? (`date`/`time` are Lua globals;
  check `/home/sam/wow-ui-source` with shell access.)

### Justified exceptions (documented, not defects)
J-1 unknown unlock flags kept on downgrade; J-2 a newer blob is never overwritten; J-3 the chat
notices ride the badge toggle (the toggle's own description says so); J-4 the M4 notice deliberately
bypasses that gate — the pattern H-2 must follow.

### Positive
The pure/core split is honest (no clock, no randomness, every date injected); the repair path is
non-destructive and total; the newer-blob protection works; "replace, never mutate" holds; the
Progress page recomputes NOTHING (every number comes from the pure models); the frame does not
leak; the scroller cannot go out of bounds; no NaN/infinity/negative/div-by-zero reaches a pixel;
the session-end write is idempotent (stop → panel-hide → logout cannot double-count a run).
