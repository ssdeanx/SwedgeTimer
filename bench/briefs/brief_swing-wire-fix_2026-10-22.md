# Brief: swing-wire-fix — HU-25 real-lib harness (red first) + D8 deadline rewire

Date: 2026-10-22. Follows `desks/swing-wire-hunt2/journal.md` (per-client
hop trace: Era all-WIRED, Anniversary WIRED-except-D2-ranged; D8
deadline-trap; D10 stale-copy; HU-25 harness spec §3). Operator rule: no
in-client testing, no fixed/working claims without tree evidence. HU-29
still rules any `Libs/` touch — NOT this lane. Proctor verifies after you.

## Seat + mode

- Seat: `builder`. You implement; you do not mark anything complete.
- Skills first: `skills_list`, then `skill_view` (`bench-read`,
  `desk-open`, `desk-journal`, `signal-write`). Then journals before
  artifacts: `desks/journal.md`, your desk journal,
  `desks/swing-wire-hunt2/journal.md` (the spec you build),
  `desks/swing-wire-hunter/journal.md` (D1–D7),
  `bench/lessons.md` (mutation-copy + one-writer rules). Missing skill →
  state which, proceed per `workshop.md` / `CAIRN.md` / `AGENTS.md`.
- Context discipline: targeted greps + surgical patches. Never read a
  whole class file or suite.

## Scope (and the one overlap)

- OWN: NEW harness suite file (name it `tests/real_wire_state.lua`;
  if that name collides, pick the closest free `*_state.lua` name and
  say so) + NARROW `main.lua` edits confined to the deadline block
  (`:393-411`), the INFO_INITIALIZED ready-callback (`:382-386`), and
  `register_timer_callbacks` (`:770-777`) plus one rewire guard.
- `main.lua` overlaps the dead range-engine-tbc lane (HU-27,
  unreconciled): touch ONLY the regions above, nothing else in the file.
  The orchestrator reconciles.
- FILE-don't-touch: `tests/run.sh` and every TOC (orchestrator-owned —
  emit the exact `run.sh` line for the new suite as a `FILED:` block),
  `Libs/` (HU-29), `bars.lua`, `compat.lua`, `classes/`, `swing_source.lua`
  (proctor-PASS, do not reopen), `diag.lua`.
- Check the `toc_check.lua` 200-local compiler guard for `main.lua`
  before adding file-scope locals — new state goes on `ST.*`, never a
  file-scope `local` near the cap.

## B1 — harness per the hunt2 spec (build FIRST, watch it fail)

- Assembly, all REAL and unmodified: Lua 5.1 sandbox, scripted WoW API
  (event bus + manual `C_Timer` clock), LibStub, the SHIPPED v7
  `CallbackHandler-1.0`, the REAL vendored
  `LibClassicSwingTimerAPI.lua`, the REAL `main.lua`
  init/reg/dispatcher/handler path, `bars.lua` seed/render with stubbed
  frames. No fixture may answer in the lib's shape (lesson 11).
- Legs per profile (Era `WOW_PROJECT_ID=2`; Anniversary `=5` with
  `LE_EXPANSION_LEVEL_CURRENT=1` AND a `nil` variant — the runtime value
  is binary-provided and unknowable offline, orchestrator-confirmed):
  ADDON_LOADED asserts lib units; PEW asserts app-observed
  INFO_INITIALIZED + `stl_ready`; assert the six regs land IN THE LIB's
  v7 registry object (registry identity, not a counter); CLEU
  `SWING_DAMAGE` → mh advances (`engine_dead=false`); `SUCCEEDED(75)` +
  autorepeat → ranged advances (Era).
- Negative leg (D8): hold INFO past 5 s, run the deadline, deliver the
  lib late → assert `STL` identity is the lib and bars advance. MUST FAIL
  on the current tree — record the red output in your report before fixing.
- Anniversary-`nil` leg (D2): ranged advances — MUST FAIL on the current
  tree; encode as expected-fail-pending-HU-29 (todo/skip with the HU-29
  reference), NEVER fake green.
- Happy legs must be green on the current tree (they prove the strip +
  wire shape with the real lib — the claim no suite has ever made).

## B2 — D8 rewire (only after the red is recorded)

- App-side only: a late `INFO_INITIALIZED` after a stub substitution
  must re-point `STL` at the reporting engine and re-run
  `register_timer_callbacks` under a double-reg guard (stash the real
  engine in a separate upvalue before any swap — the deadline currently
  overwrites `STL` itself, `main.lua:405`), then re-seed the hands so
  bars leave `engine_dead`. Alternatively a `needs_rewire` flag set by
  the deadline instead of swapping `STL`. Pick the smaller shape that
  keeps every existing pin green.
- Constraints: no new user-visible toggle; the "unavailable" notice and
  `deadline=fired` diag stay truthful (a rewired session must read
  rewired, not still-unavailable); nil-safe; endings preserved; no
  behavior change on the lib-first happy path.
- After the fix: D8 negative leg green, all happy legs still green,
  D2-`nil` leg still expected-fail (HU-29), full `run.sh` green.

## Proof (owed, all of it)

- The recorded RED (negative + D2 legs failing on the pre-fix tree) and
  the post-fix GREEN, both pasted as counts in your report.
- Full `bash tests/run.sh` green + luacheck at the 2/0 floor.
- Mutations on `/tmp/opencode` copies (`rsync -a --exclude=Media
  --exclude=docs --exclude=.git`, removed after): rewire detached →
  negative leg red; strip neutered → happy legs red. Minimum 2, all caught.
- Desk journal + `done` signal with a `FILED:` block (the `run.sh` line)
  and one-line residuals. Reply text is the deliverable: files/lines,
  red→green counts, mutation results, FILED items.
