# Brief: swing-wire-build — Forever engine idle shape + missing equip-change handling

Date: 2026-10-22. Follows the read-only hunt
(`bench/briefs/brief_swing-wire-hunter_2026-10-22.md`,
`desks/swing-wire-hunter/journal.md` D1–D7/U1–U7). D1 is already fixed in
tree (in-client UNPROVEN, operator item). D2/D4/D5/D6 sit in the vendored
lib and are ruled by HU-29 (operator: upstream / fork-patch / accept) —
NOT this lane. D7 is by-design. This lane owns ONLY the OUR-files items:
D3 + the orchestrator-closed U4 Forever gaps.

## Seat + mode

- Seat: `builder`. You implement; `proctor` verifies after you; the
  operator merges. You do not mark anything complete — your signal says
  what you changed and what proves it.
- Skills first (operator order): call `skills_list`, then `skill_view`
  the lane skills you need (`bench-read`, `desk-open`, `desk-journal`,
  `signal-write`, plus `hermes-agent` only if your seat needs it). Then
  journals before artifacts: `desks/journal.md` (your row), your desk
  journal, `desks/swing-wire-hunter/journal.md` (the findings you build
  on), `bench/lessons.md` (mutation-copy + one-writer rules), then work.
  If a skill is absent from your catalog, state which and proceed per
  `workshop.md` / `CAIRN.md` / `AGENTS.md`.
- Context discipline (standing rule): targeted greps + surgical patches.
  Never read a whole class file or suite into context.

## Scope (two files; everything else is FILE-it-don't-touch)

OWN: `swing_source.lua`, `tests/swing_source_state.lua`. One writer per
file — no running lane owns either (compat-tbc-defects owns compat.lua;
range-engine-tbc owns main.lua/hunter_ui.lua/LRC). Do NOT touch `Libs/`
(vendored, HU-29), `tests/run.sh` or any TOC (orchestrator-owned — FILE
any needed pin/line as a `FILED:` block in your report), `main.lua` /
`bars.lua` (if a change there is truly required, FILE it with rationale,
do not edit).

## B1 — D3: idle `SwingTimerInfo` impersonates a live cycle (Forever)

- `swing_source.lua:326-334`: with no active cycle it returns
  `(1, start+1, start)` — a plausible 1 s cycle. The stub it claims to
  mirror returns the nil-shape since H1 (`main.lua:19-30`), and
  `init_timers` (`main.lua:739-757`) turns the nil-shape into the
  per-hand `engine_dead` idle path while the number-shape seeds a live
  cycle that no STOP ever ends (phantom full bar at login/post-combat).
- Change: return the nil-shape when no cycle is active, so the bars
  render the idle path. Fix the stale `:331` comment in the same edit.
- Intended-visible change, documented here as the gate: Forever login /
  post-combat bars move from stuck-full to the idle path. No new toggle
  (this restores the H1 contract, it does not add a display option).
- Pins (extend `tests/swing_source_state.lua`): idle hand returns
  nil-shape; active cycle still returns `(speed, expiration, start)`;
  comment matches the shipped stub shape.

## B2 — U4-closed: `WEAPON_SLOT_CHANGED` (Forever)

- Orchestrator-confirmed on `origin/forever`
  (`Blizzard_SwingTimer/Blizzard_SwingTimer.lua`): Blizzard's manager
  re-evaluates swing registration on `WEAPON_SLOT_CHANGED` (plus
  `PLAYER_ENTERING_WORLD` / `UNIT_ATTACK_SPEED`, both already handled).
  `swing_source.lua:344-367` registers `PLAYER_SWING` /
  `UNIT_ATTACK_SPEED` / `PLAYER_IN_COMBAT_CHANGED` /
  `PLAYER_ENTERING_WORLD` only — a mid-session weapon swap can strand a
  cycle on its old speed (stuck/stale bar, same complaint family).
- Change: handle `WEAPON_SLOT_CHANGED` probe-gated through the existing
  `is_event_valid` pattern (`swing_source.lua:49-62`): re-read speeds
  via the existing attack-speed path and clear cycles the swap
  invalidates, mirroring the combat-exit clear shape (`:276-290`). Keep
  the H5 counters truthful (a swap-clear is not a reject).
- `PLAYER_TARGET_CHANGED` / `PLAYER_SWING_RANGE_UPDATE` (same Blizzard
  file): implement ONLY if they carry swing-cycle state; they read as
  target/range display inputs — note-and-skip with a one-line rationale
  each is an acceptable finish. Hold scope.
- Pins: weapon-swap clears/re-times the affected hand(s) and fires the
  matching STOP/UPDATE traffic; probe-absent clients never register the
  event; skipped events have a rationale line in your report.

## B3 — optional: `UNIT_ATTACK_SPEED` unit filter

- Registered unfiltered (`:344-367`); the handler re-reads player only —
  noisy, harmless. `RegisterUnitEvent("player")` if it fits the probe
  pattern cleanly; note-and-skip with rationale if not. No pins owed for
  a skip.

## Standing rules

No git. No lint-config changes. Wire-not-strip. Whitespace only inside
touched lines; endings preserved (CRLF where the file has them — check
before you write). New reads nil-safe. Lua 5.1 local ceiling (file-scope
locals go on the module table, never new file-scope `local`s near the
cap). Mutation copies: `rsync -a --exclude=Media --exclude=docs
--exclude=.git`, clean `/tmp/opencode` between waves.

## Proof (owed, all of it)

- `bash tests/run.sh` green on the final tree + `luacheck` at the 2/0
  floor (75+ files; both current KEEP-ruled warnings stay).
- Mutation proofs on `/tmp/opencode` copies: B1 neutered (idle returns
  the old 1 s shape) fails the new pins; B2 handler detached fails the
  swap pins. Minimum 2 mutations, all caught, copies removed after.
- Desk journal (`desks/swing-wire-build/journal.md`: worked on / current
  state / next step, for someone starting from zero) + `done` signal
  with a `FILED:` block for anything outside your two files.
- Deliverable is the reply text: files changed (with lines), suite
  counts, mutation results, FILED items, residuals in one line each.
