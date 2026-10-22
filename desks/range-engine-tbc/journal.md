# range-engine-tbc — Journal

## 2026-10-21 — Desk opened
- **Purpose:** the operator's order (2026-10-21): move the range state off the
  deprecated/blocked interact-distance probes onto exact yards. R1 main.lua range
  state from `api.UnitDistance`, R2 the vendored LibRangeCheck builds NO interact
  checkers, R3 hunter_ui sweet spot from exact yards + per-subfeature guard
  isolation, R4 class `post_init` isolated in `st.guard.run`.
- **Scope:** `main.lua` (range section, `init_libs`, LRC callback, `post_init`
  wiring, range diag), `hunter_ui.lua` (constants + `update_range_helper` +
  `ui.update` guard sites), `Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua`,
  and the suites that pin them (`tests/lrc_guard_state.lua`,
  `tests/main_init_state.lua`, `tests/hunter_state.lua`, new
  `tests/range_source_state.lua`).
- **Contract:** `bench/briefs/brief_range-engine-tbc_2026-10-21.md`.
- **Read-only for this lane:** `tests/run.sh`, `compat.lua`,
  `tests/spell_known_state.lua`, `classes/**`, `bars.lua`, `hud.lua`,
  `weave_range.lua`, other Libs.
- **Next step:** finish the stale sections of `tests/main_init_state.lua`,
  update `tests/hunter_state.lua`, add `tests/range_source_state.lua`, run the
  harness + luacheck, mutation proofs on a `/tmp/opencode` copy, then write
  `bench/range_engine_tbc_2026-10-21.md`.

## 2026-10-21 — Landed (R1–R4)

- **Worked on:** R1 `main.lua` exact-yard range state (`api.UnitDistance`, one probe
  per poll, `RF_MELEE_RANGE = 5` / `RF_RANGED_RANGE = 30` / hunter 35, floor/ceil text
  fields, `ST.target_distance`, LRC-independent, `nil` = unknown and not a failure);
  R2 vendored LibRangeCheck builds no interact checkers (zero
  `CheckInteractDistance(` calls, 2-arg `createCheckerList`, empty-list `getRange` ->
  `nil`, `minRangeCheck` stays nil); R3 `hunter_ui` sweet spot `5 < yards <= 10` plus
  ten per-subfeature `st.guard.run` sites; R4 class `post_init` wrapped as
  `class:<CLASS>:post_init`. New `tests/range_source_state.lua` (148 checks) pins brief
  items 1–7; `lrc_guard_state` (141), `main_init_state` (952), `hunter_state` (1738) and
  `bars_state` (907) updated.
- **Current state:** `bash tests/run.sh` → **46 steps, 0 failed**; `luacheck .` →
  **2 warnings / 0 errors in 88 files** (floor). Mutation proofs 9/9 killed on
  `/tmp/opencode/range-engine-mut2/tree`, every file restored byte-identical
  (transcript: `bench/range_engine_tbc_2026-10-21.proof.txt`). Deliverable:
  `bench/range_engine_tbc_2026-10-21.md`. `tests/run.sh:94` already carries the new
  suite (orchestrator-owned; this lane did not edit it). No open crossfire item:
  `toc_check` passes with 44 registered suites / 44 on disk and `secret_guard_state`
  (compat lane) asserts the removed wrapper and passes at 432 checks.
- **Next step:** operator in-client validation on TBC Anniversary hunter — §8 of the
  deliverable (no BugGrabber block, distance strip shows/hides, cast bar survives past
  25 frames, `/st diag` counters clean). The 10 yd sweet-spot reference file:line and
  non-TBC-family behaviour remain UNCONFIRMED until then.
