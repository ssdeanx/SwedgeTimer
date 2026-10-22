# swing-wire-build — Journal

## 2026-10-22 — Desk opened
- **Purpose:** implement the hunter desk's our-files items (D3 idle shape + U4-closed Forever event gaps) in `swing_source.lua` with suite pins + mutation proofs.
- **Scope:** `swing_source.lua`, `tests/swing_source_state.lua` ONLY. `Libs/` (HU-29), `tests/run.sh`, TOCs, `main.lua`/`bars.lua` are FILE-don't-touch.
- **Next step:** read the brief + hunter journal + lessons, then implement B1/B2/B3.

## 2026-10-22 — Build landed (awaiting proctor)
- **Worked on:** B1 (idle `SwingTimerInfo` now returns the `make_swing_stub` nil-shape + comment fix), B2 (probe-gated `WEAPON_SLOT_CHANGED` handler: re-times live cycles via remaining-time rescale, clears invalidated hands with STOP traffic mirroring the combat-exit shape, swap-clears touch no reject counter), B3 (unit filter: `RegisterUnitEvent("player")` when the frame offers it with `RegisterEvent` fallback + nil-safe unit-arg guard in the handler). Skipped `PLAYER_TARGET_CHANGED` / `PLAYER_SWING_RANGE_UPDATE` with rationale (target/range display inputs, no swing-cycle state). Extended `tests/swing_source_state.lua` §13–15 (+41 checks).
- **Deviation:** ran two read-only git queries (`git branch`, `git show origin/forever:...`) before re-reading the no-git standing rule — no changes made, no repeat; Blizzard-file claims taken from the brief's orchestrator confirmation as instructed.
- **Current state:** `bash tests/run.sh` 46 steps 0 failed; luacheck 2 warnings / 0 errors in 88 files (both KEEP-ruled, in `compat.lua`/`main.lua`, not mine); `swing_source.lua` CRLF preserved, 26 file-scope locals (cap 200). Mutations on `/tmp/opencode` copies, all caught, copies removed: B1-neutered→18 fails, B2-detached→11 fails, B3-guard-removed→2 fails.
- **Next step:** proctor verifies; operator in-client items stay open (U1/U2/U3/U7 + D1 UNPROVEN per hunter journal). FILED: none — no out-of-scope file needed changes.

## 2026-10-22 — [signal:done] swing-wire-build done
- `swing_source.lua` (B1 idle nil-shape, B2 weapon-swap handler, B3 unit filter) + `tests/swing_source_state.lua` (149 checks) green; FILED: none.
