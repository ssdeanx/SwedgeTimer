# Buildout — rogue-practice (Slice D: practice + options copy, 2026-10-19)

Session: rogue-practice desk. Brief:
`bench/briefs/brief_rogue-practice-polish_2026-10-19.md` (HELD flag lifted;
Round 1 reconciled). Validation owner: orchestrator.

## Files changed
- `practice.lua` (CRLF preserved, 2490 → 2659 lines)
  - `H.SCENARIO_KINDS.swing_window = true`.
  - `H.ROGUE_ENERGY_DEFAULTS`, `H.energy_tick_marker`,
    `H.grade_energy_spend` — 2 s tick, marker = 1 − latency/interval (0.95 with
    defaults), grades the spend-start fraction against the marker with
    `H.WEAVE_MARGIN_BANDS`; a start past the marker or a measured clip is F; a
    nil marker grades nil.
  - `rogue_energy_pool` (`class = "ROGUE"`, kind `energy_loop`): exact-time
    event takes a number (tick-cycle fraction) or `{ start, clip }`; query
    `tick_marker`.
  - `H.ROGUE_SS_DEFAULTS`, `H.ROGUE_SS_MARGIN_BANDS`,
    `H.grade_ss_after_swing` — Era SS-after-swing window 0.1–0.2 s, ideal 0.1 s
    (rogue_deep §2.1 / classicroguecraft swing-timing guide); S..D bands on the
    distance from the ideal, F outside the window; nil swing record grades nil.
  - `rogue_ss_window` (`class = "ROGUE"`, kind `swing_window`): exact-time event
    takes the offset in seconds; query `window` (`start_time`, `end_time`,
    `ideal`).
  - Scenario contract comment now lists `"ROGUE"`.
- `tests/practice_state.lua` (LF)
  - Registry pins 6 → 8; two ROGUE specs, order, kinds.
  - Harness helper exposure: `energy_tick_marker`, `grade_energy_spend`,
    `grade_ss_after_swing`.
  - Grade pins: energy S/A/B/C/D + F (past marker) + F (measured clip) + nil
    start + nil tick; SS S/A/B/C/D + F early + F late + nil offset + nil swing;
    session event paths, scoring (S = 100), and nil-tick / nil-swing unscored
    sessions.
- `option_tables.lua` (LF, ROGUE section only)
  - `energy_desc` / tick marker / pooling tint copy: cues hide while the tick
    prediction is unknown instead of drawing a guessed tick.
  - `cues_desc`: unknown aura/CP reads hide a cue; the Classic Era SS-after-swing
    window is Era-only and needs a readable mainhand swing record.
  - `nag_desc`: unknown swing/energy/CP reads render "…" instead of advice.
  - No keys, toggles, getters, setters, defaults or ordering changed.

Out of scope and untouched: `classes/rogue.lua`, `rogue_guide.lua`,
`tests/rogue_state.lua`, `tests/rogue_guide_state.lua`,
`tests/guide_contract.lua`, `diag.lua`, TOCs, version, CHANGELOG. No git, no
lint-config changes.

## Validation
- `bash tests/run.sh` → **37 steps, 0 failed** (harness green).
- `luacheck .` → **2 warnings / 0 errors** (the floor; both KEEP-ruled).
- `lua5.1 tests/practice_state.lua` → **1151 checks, 0 failed**.
- Mutation proofs on `/tmp/opencode/rogue-practice-mut` (final files copied):
  1. nil-tick guard replaced by a `marker = 1.0` fallback → nil-tick unscored
     pin fails (got B, want nil).
  2. tick-clip guard (`start_fraction > marker`) stripped → 2 F pins fail
     (got S, want F).
  3. SS early-window guard stripped → early F pin fails (got S, want F).
  4. SS unknown-swing guard stripped → 2 nil pins fail (got B, want nil).
  Restored copy re-passes 1151/0.

## Notes for validation
- The late SS-window F pin is satisfied through the band fallback (delta
  > 0.10 → F), so mutation 3 shows the early-window guard is load-bearing but
  the window-end guard is defensive; remove/keep call is the orchestrator's.
- Parallel cues lane ran concurrently; no files outside the scope above were
  edited. Harness was re-run at the end and is green.
