# Brief: swing start/end/reset correct on every client (2026-10-22)

## Objective
Make the swing bars (ranged, mainhand, offhand) start, end, and reset
correctly on **classic_era, classic_anniversary (TBC), retail, and WoW
Forever**. Release stays 2.1.1; no protected client calls; lazy-bars and
exact-yards-only rules stand (HU-22, HU-23).

## Operator symptoms (exact, in-client, post-strip-copy)
- Ranged bar moves but is NOT the real timer: on TBC it must be the hidden
  0.5 s cast window, and it isn't.
- Mainhand bar never shows or works, for any class.
- Steady Shot / Auto Shot displays work, then break when the ranged bar is
  wrong (they share the ranged state — fix the source, not the displays).

## Established facts (do not re-prove; build on them)
- `Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua` is canonical v32
  (byte-identical to the operator's paste) and **stays unmodified**
  (AGENTS.md: vendored Libs update from upstream, never a silent local patch).
- `main.lua` `callback_event_handler` strips the lib's leading unit-id on
  `SWING_TIMER_*` (grep `SWING_TIMER_` in `main.lua` for the region); per-hand
  receipt counters + `/st diag` `swing_`/`proj`/`exp`/`bcc` line exist.
- `bench/proctor_swing_gap_2026-10-22.md` lists the exact coverage holes, in
  priority order: Pin 1 (TBC ranged driver table through the real lib + real
  v7: SUCCEEDED-without-autorepeat, CAST_START and FAILED_QUIET negatives per
  family), Pin 2 (full START→UPDATE→hand-only STOP per hand incl. offhand),
  Pin 3 (MISSED routing + PARRY/EXTRA_ATTACKS as xfail pending HU-29).
- The cancelled hunter lane produced no findings — there is nothing to reuse
  from it. The proctor report's cross-client statements are UNVERIFIED by its
  own admission (no shell on that seat); verify everything cross-client
  yourself per below.

## Method (cross-client truth, not assumptions)
- API truth lives in `/home/sam/wow-ui-source`, one branch per client:
  `classic_era`, `classic_anniversary`, `classic_titan`, `live`,
  `origin/forever`. Read other branches with
  `git -C /home/sam/wow-ui-source show <branch>:<path>` — never assume the
  checked-out branch (`classic_era`) speaks for another.
- Behavior reference (read-only, compare — do not lift code blindly, it is a
  different addon): `/home/sam/SuperSwingTimer-WoW/` (same lib lineage,
  worked on 2.5.x; see its `API_AUDIT_REPORT.md`/`DEEP_AUDIT_REPORT.md` for
  where its shot anchoring diverges from ours).
- Per-family driver facts to confirm in the lib + branches before changing
  anything: Era ranged uses `SPELL_CAST_START` + `FAILED_QUIET`
  (hidden-window `now + 0.5 + autoShotCastTime`, `0.52 * speed/base`
  rescale); Anniversary relies on SUCCEEDED(75) + START_AUTOREPEAT only;
  Retail is the inert stand-in (fires nothing); Forever comes through
  `swing_source.lua` (`PLAYER_SWING` mapping, speed-first, hand-only STOP
  passes through).

## Write scope (exclusive — nothing else)
- `main.lua`: the dispatcher/handlers region only.
- `bars.lua`, `classes/hunter.lua`, `hunter_ui.lua`: only the swing-state
  read/update lines your diagnosis names (cite line numbers in the journal).
- `tests/real_wire_state.lua`: new legs for Pins 1–3 above.
- Do NOT touch: `tests/run.sh` (orchestrator-owned wiring), vendored Libs,
  TOCs, version fields, options tables.

## Validation (focused — full suite is the orchestrator's)
- Run only the suites your change touches, e.g.
  `lua5.1 tests/real_wire_state.lua` directly; `luacheck` on touched files
  only — never the full `run.sh`.
- Mutation proof on `/tmp/opencode` copies (fresh copy per mutation, removed
  after): each fix leg must fail with the defect restored and pass with it.
- Leave `desks/swing-cross-client/journal.md` current (worked-on / state /
  next step) and emit `done`/`blocked` signals per signal-write; bench
  findings go to NEW dated files, never overwrites.
