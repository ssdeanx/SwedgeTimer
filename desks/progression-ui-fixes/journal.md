# progression-ui-fixes — Journal

Purpose: fix the progression-surface findings that live on the UI side — H-2, M-1,
M-4, M-5, L-2, L-5 from `desks/progression-audit/journal.md` (VERDICT: FINDINGS 13).
Scope: `practice_ui.lua`, `practice_progress_ui.lua`, `main.lua` (the logout handler
only), `tests/practice_progress_ui_state.lua`. NOT `practice_progress.lua`,
`practice_stats.lua` or `tests/practice_ui_state.lua` (a sibling lane owns those —
pins for them are FILED, not applied).

## 2026-10-20 — H-2, M-1, M-4, M-5, L-2, L-5 fixed; filed pins + mutation proofs landed

- **Worked on:** H-2 (the daily-cap swallow is now REPORTED once per drill per day,
  through `self:Print`, never the badge gate); M-1 (a newer build's blob refuses
  LOUDLY — one notice per session — the flush reports the WRITE instead of the
  close, and the hook asks the pure module's shared `P.is_current` instead of
  comparing schema versions itself); M-4 (the daily streak is on the stats summary
  and on the frame's summary line, read from `model.daily_streak`); M-5 (the reset's
  arm EXPIRES after 15 s — checked lazily at every decision point, so a stale
  "Confirm" can never wipe the saved data); L-2 (the reserved `_unknown` bucket is
  recorded on the stats side under the same key and gets a display name); L-5 (the
  module header now states the real write contract: the profile always mirrors the
  live state, the client serialises at logout — the write SHAPE is unchanged).
- **Also fixed (in the code this lane owns):** the grade-points seed in the
  detection path was `0`, which made the pure module's own grade table unreachable
  (`type(0) == "number"`) — a grade the live table does not know read as "worth
  nothing". Seed is `nil` now.
- **Current state:** `bash tests/run.sh` → **41 steps, 0 failed**, luacheck 2 warnings
  / 0 errors. (Mid-session the harness showed 2 hunter failures; they were **not**
  this lane's — the failing checks MOVED between two runs while
  `desks/hunter-steady-family/` was editing `classes/hunter.lua` and
  `tests/hunter_guide_state.lua`, and neither hunter suite loads any file this lane
  touched. That lane landed its fix and the harness went green.) This lane's suites:
  `practice_progress_ui_state` 282/282, `practice_ui_state` 1623/1623,
  `main_init_state` 903/903, `options_load_state` 3494/3494. Eight mutants proved
  against `/tmp/opencode` copies (cap unreported, flush lies, streak hidden in the
  summary, streak hidden in the frame, arm never expires, `_unknown` half-recorded,
  refusal silent at the detection point / everywhere) — every one dies on a pin.
- **Artifacts:** `bench/progression_ui_fixes_2026-10-20.md` — the fixes with
  file:line citations, **the FILED PINS for `tests/practice_ui_state.lua`** (the
  sibling lane's file: H-2, M-1 and L-2 blocks, proved on a /tmp copy), the
  mutation table and the verification state.
- **Next step:** the sibling lane that owns `tests/practice_ui_state.lua` pastes the
  filed pins in. Nothing is owed in `practice_progress.lua`: no change was needed
  there, so no filed change is owed.

## 2026-10-20 — [signal:done] H-2, M-1, M-4, M-5, L-2, L-5 fixed; pins filed
- Six findings closed on the UI side; the fixes live in `practice_ui.lua`,
  `practice_progress_ui.lua` and `main.lua`'s logout handler, with pins in
  `tests/practice_progress_ui_state.lua`.
- The pins for the sibling lane's `tests/practice_ui_state.lua` are FILED in
  `bench/progression_ui_fixes_2026-10-20.md` §7 (proved on a /tmp copy: the copy
  passes, every mutant dies).
- Harness: 41 steps, 0 failed, luacheck 2 warnings / 0 errors (both pre-existing).
  This lane's suites are green.
- Signal file: `desks/progression-ui-fixes/.signals/20261020T121000Z.json`.
