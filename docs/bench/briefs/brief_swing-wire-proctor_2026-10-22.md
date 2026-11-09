# Brief: swing-wire-proctor — independent verdict on the Forever engine fix

Date: 2026-10-22. Verifies the builder lane
(`bench/briefs/brief_swing-wire-build_2026-10-22.md`,
`desks/swing-wire-build/journal.md`) against the repo, independently.
You do not implement, you do not edit. Your verdict (PASS / NEEDS FIXES)
is what lets the operator approve — nothing is complete on the builder's
claim.

## Seat + mode

- Seat: `proctor`. READ-ONLY: no code edits, no file writes, no test
  runs (no shell on this seat — anything you cannot execute is
  UNVERIFIED with the exact closer, never "fine").
- Skills first (operator order): call `skills_list`, then `skill_view`
  the lane skills you need (`bench-read`, `desk-open`, `desk-journal`,
  `signal-write`). Then journals before artifacts: `desks/journal.md`
  (lane ledger + standing rules), your desk journal,
  `desks/swing-wire-build/journal.md`, `desks/swing-wire-hunter/journal.md`
  (D3/U4 — the findings built on), `bench/lessons.md`. If a skill is
  absent from your catalog, state which and proceed per `workshop.md` /
  `CAIRN.md` / `AGENTS.md`.
- Tool rule for `/home/sam/wow-ui-source`: `read`/`grep` are blocked
  there — use `ast_grep_search` with `paths` + `lang: "lua"`; it sees
  only the checked-out `classic_era` branch, so branch every claim.
  Blizzard Forever facts you may reuse without re-proving (orchestrator
  `git show origin/forever`, 2026-10-22): the swing manager re-evaluates
  on `WEAPON_SLOT_CHANGED`, and handles `PLAYER_TARGET_CHANGED` /
  `PLAYER_SWING_RANGE_UPDATE` as target/range display inputs.

## What changed (verify each; all exist on disk 2026-10-22)

In `swing_source.lua` (CRLF, +75/-6):
- B1: idle `SwingTimerInfo` returns `(nil, nil, nil)` + comment fix
  (~`:388-394`). Contract: `main.lua:19-30` (`make_swing_stub`
  nil-shape) and `main.lua:739-757` (`init_timers`: non-number first
  return → nil speed/ends_at/start + `engine_dead` when no engine).
  Confirm the idle path now matches the stub EXACTLY and no caller can
  mistake nils for a cycle (check every `SwingTimerInfo` consumer —
  `main.lua:75-77` closure and anywhere else that reads the triple).
- B2: `on_weapon_slot_changed()` (~`:281-334`): re-times live cycles by
  remaining-time rescale, clears invalidated hands with STOP mirroring
  the combat-exit shape (`:276-290` area pre-edit); swap-clears must not
  touch the H5 reject counters; secret/throwing readers keep old
  schedules. Confirm the rescale math equals the attack-speed path's
  (remaining × new/old, floored at 0, no division by zero when
  old_speed is 0/nil) and the STOP traffic matches the shape
  `main.lua`'s handlers take (`ST:SWING_TIMER_STOP(_, hand)`).
- B2 wiring: `WEAPON_SLOT_CHANGED` in `engine_events` + `OnEvent`
  dispatch (~`:404-435`), probe-gated via `is_event_valid`
  (`:49-62`). Confirm a probe-absent client never registers it and the
  gate cannot throw.
- B3: `on_unit_attack_speed(unit)` unit guard + `RegisterUnitEvent`
  with `RegisterEvent` fallback (~`:227-236`, `:413-421`). Confirm the
  fallback condition cannot misdetect (frame always has
  `RegisterEvent`; `RegisterUnitEvent` absence is the only trigger),
  nil-unit direct calls still re-read, non-player units are ignored.
- Skips: `PLAYER_TARGET_CHANGED` / `PLAYER_SWING_RANGE_UPDATE`
  deliberately unregistered with a code comment (~`:404-406`). Confirm
  neither carries cycle state per the Blizzard facts above.

In `tests/swing_source_state.lua` (108→149 checks, §1/§2/§13/§14/§15):
- Confirm every new pin asserts SHIPPED behavior (not the test's own
  fixture echo): idle nil per-hand, live triple intact, five events in
  order + unit filter, swap re-time math / clear-STOP / no-reject /
  no-cycle-silence / throwing-reader keep / probe gating, B3
  target-ignored + player/unit-less re-time.
- Confirm the builder's three mutation claims would actually fail:
  B1-neutered-to-1s (18 fails), B2-detached (11 fails), B3-guard-removed
  (2 fails) — trace each mutation to the pin that kills it by reading
  the suite, since you cannot execute it.

Scope + standing rules (fail the lane on violation):
- Only `swing_source.lua` + `tests/swing_source_state.lua` changed
  (plus ledgers/briefs). Any `Libs/` touch, TOC/`run.sh`/`main.lua`/
  `bars.lua` edit, or stray artifact = NEEDS FIXES.
- Endings preserved (CRLF on `swing_source.lua`, LF on the suite),
  26 file-scope locals (cap 200), no new user-visible toggle, no
  default-visible change beyond the brief's gated B1 intent
  (stuck-full → idle path on Forever).

## Deliverable (reply text; orchestrator files it)

- Verdict: PASS or NEEDS FIXES, one line, with the reason.
- Finding list F1..Fn (or "none"): each with file:line, severity
  (wrong-behavior / pin-gap / scope-violation), and the exact fix.
- UNVERIFIED list: harness re-run, luacheck floor, mutation execution
  (no shell on this seat) — the orchestrator closes these with its own
  run and hands you the output only if you are re-dispatched.
- Explicit non-findings: contract points you traced and hold.
