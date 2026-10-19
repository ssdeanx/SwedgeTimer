# Rogue Practice — Journal

## 2026-10-19 — Desk opened (Round 2, Slice D: practice + options copy)
- **Purpose:** rogue practice drills (`practice.lua` scenarios) and the ROGUE
  options copy for hide-on-unknown discoverability.
- **Scope:** `practice.lua`, `tests/practice_state.lua`, `option_tables.lua`
  ROGUE section only. `classes/rogue.lua`, `rogue_guide.lua`,
  `tests/rogue_state.lua`, `tests/rogue_guide_state.lua`,
  `tests/guide_contract.lua` belong to the parallel cues lane. `diag.lua`
  stays CLOSED.
- **Next step:** consume the brief
  `bench/briefs/brief_rogue-practice-polish_2026-10-19.md` (HELD flag lifted)
  and report through journal + `done` signal.

## 2026-10-19 — Slice D complete
- **Worked on:** two `class = "ROGUE"` scenarios registered through
  `H.register_scenario` — `rogue_energy_pool` (energy-pooling drill: spend-start
  fraction vs the 2 s tick marker, reusing `H.WEAVE_MARGIN_BANDS`) and
  `rogue_ss_window` (Era SS-after-swing drill: 0.1–0.2 s after the mainhand
  swing, 0.1 s ideal, custom S..D margin bands). Both grade nil when the tick
  prediction / mainhand swing record is unknown (never a guessed state).
  Updated `tests/practice_state.lua` registry counts (6 → 8) and added
  S/A/B/C/D + F-clip pins plus nil-tick / nil-swing unscored pins. Refresh of
  the ROGUE options copy: energy/pooling cues and NAG state that unknown inputs
  hide (no guessed tick) or render "…" instead of advice; cues copy notes the
  Era-only SS window. No toggle keys, getters, setters or defaults changed.
- **State:** `bash tests/run.sh` 37/0; `luacheck` 2 warnings / 0 errors (floor);
  `tests/practice_state.lua` 1151 checks, 0 failed. Mutation proofs on
  `/tmp/opencode/rogue-practice-mut` (4 mutations, each fails the matching new
  pin): nil-tick fallback, tick-clip guard, SS early-window guard, SS
  unknown-swing guard.
- **Next step:** orchestrator validation (copy accuracy, disjoint check vs the
  cues lane, in-client drill feel once the Slice B visuals exist).

## 2026-10-19 — [signal:done] Slice D shipped to the bench
- Signal file: `desks/rogue-practice/.signals/2026-10-19T10-34-35Z.json`.
- Handoff: `bench/buildout_rogue-practice_2026-10-19.md` (files changed,
  validation, mutation proofs, and the late-SS-edge note).
- No files outside the brief scope were edited; harness re-run green (37/0).
