# buildout_practice — C1 harness split + P5/H5/W6/D7/S7 scenarios + ui.design_targets (build-out round 1)

Date: 2026-10-17. Desk: practice. Brief: `bench/briefs/brief_practice_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").

## 1. Changes (writable scope held exactly)

Writable scope was held: `practice.lua`, `practice_ui.lua`, `tests/practice_state.lua`, `tests/practice_ui_state.lua`. No other file touched; no git ops; CRLF endings preserved in both addon files (verified: every line of both files ends CRLF), LF preserved in both test files.

### practice.lua (additive only — no existing line changed)

New trailing section "Generic scenario harness (C1): the reusable sim/timing engine." (~967 lines) containing:

- **Scenario registry/lifecycle**: `H.register_scenario` (validates key/title/kind, rejects duplicates), `H.get_scenario`, `H.scenarios_for_class`, `H.new_session`, `H.begin_session` (builds windows, fires `begin`), `H.tick_session`, `H.end_session`, `H.scenario_event` (exact-time action hook), `H.query` (named scenario timing queries). Spec contract: `key/title/class/kind/description/new_state/windows/begin/tick/finish/event/queries`.
- **Shared scoring pipeline**: `H.new_score` / `H.record_attempt` / `H.score_summary` reference the existing single implementation; `H.record_session_attempt` / `H.session_summary` drive a per-session accumulator; `H.grade_band(value, bands)` (ordered `{max, grade}` bands + fallback, non-number → fallback or nil).
- **Window model (forced-move cadence and every other windowed mechanic)**: `H.build_windows` (deterministic `first_start + (i-1)*(duration+gap)` cadence), `H.window_at` (start inclusive / end exclusive), `H.next_window`, `H.time_to_next_window` (0 inside, nil after the last), `H.window_remaining`, `H.overlap_seconds` (span-clamped, overlapping windows merged).
- **P5 combo primitives**: `H.COMBO_DEFAULTS` (`aw` + `hpot`, 3 s), `H.COMBO_LAG_BANDS` (S ≤0.2 / A ≤0.5 / B ≤1.0 / C ≤2.0 / D fallback), `H.new_combo`, `H.combo_open` (first opener wins while the window runs; a later opener after expiry starts a fresh cycle), `H.combo_record` (piece inside the window only, first record wins), `H.combo_missing`, `H.combo_evaluate` (`{grade, lag, complete, missing}`; incomplete → F), `H.combo_window_remaining`.
- **H5 primitives**: `H.H5_DEFAULTS` (first_delay 5 / count 5 / duration 2.5 / gap 5.5), `H.grade_move_cast(windows, cast_start, cast_time)` — inside a window F, cast overlapping the next window start C, finishing ≤0.5 s before it B, ≤1.5 s A, else S.
- **W6 primitives**: `H.EXECUTE_DEFAULTS` (threshold 0.20 / entry_rage 100), `H.EXECUTE_ENTRY_BANDS`, `H.execute_phase_update` (returns "entered"/"exited"/nil; non-number HP = no change), `H.grade_execute_entry` (S at the full target, quarter bands, F at empty).
- **D7 primitives**: `H.POWERSHIFT_DEFAULTS` (pool 100 / regen 10 per s / shift_refund 40 fixed / rule_energy 20), `H.POWERSHIFT_BANDS` (S ≤20 / A ≤30 / B ≤40 / C ≤60 / D ≤80 / F), `H.new_energy_state`, `H.energy_update`, `H.energy_spend`, `H.grade_powershift`, `H.powershift_cycle`.
- **S7 primitives**: `H.WEAVE_DEFAULTS` (2.6 / 1.5 / 0.1), `H.WEAVE_MARGIN_BANDS` (S ≤0.02 / A ≤0.05 / B ≤0.10 / C ≤0.20 / D), `H.weave_marker_fraction` and `H.weave_safe_start_in` (delegate to `st.weave`), `H.grade_weave_cast` (clip → F via `st.weave.is_clipped`; else bands on the margin before the marker; nil when weave.lua is absent — never a grade on a guess).
- **Scenario registrations** (section 3 below), including the paladin consumer #1 spec.

### practice_ui.lua (minimal in-place edits + one appended section)

- Added `TIMELINE_DEFAULT_X = 0` / `TIMELINE_DEFAULT_Y = -200` next to the other timeline constants; `build_timeline` now anchors from `ui.timeline_x` / `ui.timeline_y` (defaulted to those constants) — the default layout is byte-identical to the previous literal `0, -200`.
- Appended `ui.design_targets` (section 4 below). No frames added: the UI suite's "init creates exactly 69 frames" pin still holds.

### tests/practice_state.lua

- Loads `weave.lua` in the sandbox before `practice.lua` (mirrors TOC order; needed by S7).
- New harness block: API surface, registry validation/order, windows (edges, cadence, overlap merge), session lifecycle (inert inactive tick, windows override, no double begin/end), queries/events, scoring pipeline, `grade_band`, P5 combo (defaults, open/record/missing/evaluate, all lag bands, cycle reopen), the `paladin_aw_combo` scenario via both the exact-time event path and the sim-driven tick path, H5 grading bands, W6 tracker + entry grades + tick flags, D7 energy math + grades + scenario query, S7 marker/margin grades, and the **paladin equivalence proof** (section 6).

### tests/practice_ui_state.lua

- Loads `design.lua` in the sandbox (pure) so the descriptors are checked against the real `normalise_descriptor` contract.
- New section 21: `ui.design_targets` shape (3 entries, key/title/get_frame/available/save/reset), pre-init nil frames / unavailable, post-init frames / in-session available, per-element save/reset round-trips (panel persists `practice_panel_x/y` through `save_position`; rotation stores `rot_x/rot_y`; timeline stores `timeline_x/y`), session gating after stop, and registry-normaliser compatibility for all three descriptors.

## 2. Harness API surface (the C1 deliverable)

```lua
local H = st.practice.harness
-- registry:   register_scenario(spec) -> spec | nil,err ; get_scenario(key) ; scenarios_for_class(class)
-- sessions:   new_session(key, now, opts) -> session | nil,err
--             begin_session(session, now, opts) -> bool
--             tick_session(session, now, elapsed, out) -> out
--             end_session(session, now) -> bool
--             scenario_event(session, key, now) -> result   (exact-time action hook)
--             query(session, name, now) -> value | nil,err
-- scoring:    new_score / record_attempt / score_summary            (shared implementation)
--             record_session_attempt(session, grade, lead_ms) ; session_summary(session)
--             grade_band(value, bands)
-- windows:    build_windows(opts) ; window_at ; next_window ; time_to_next_window ;
--             window_remaining ; overlap_seconds
-- scenarios:  paladin_twist (consumer #1) ; paladin_aw_combo ; hunter_forced_move ;
--             warrior_execute ; druid_powershift ; shaman_weave
```

Session contract: the caller owns the clock and drives everything; nothing runs on its own. Scenario specs may add `windows(now, opts)`, `event(session, now, key)` and `queries` handlers; `tick` hooks reset their own out flags (same convention as the engine).

## 3. Scenario list

| Key | Class | Kind | What it models | Notes |
|---|---|---|---|---|
| `paladin_twist` | PALADIN | `paladin_twist` | Consumer #1: wraps the shipped twist sim (`new_sim`/`begin_fight`/`tick`/`end_fight`) | Queries: `time_to_swing`, `twist_window_remaining`, `rotation`. Equivalence pinned (section 6). |
| `paladin_aw_combo` | PALADIN | `combo_windows` | P5: AW opens the window, haste pieces must land inside it; grade = slowest piece's lag | Sim-backed (own sim; tick observes AW/haste buff transitions) **and** exact-time `event` path; queries `combo_grade`, `combo_window_remaining`, `combo_missing`, `time_to_swing`. Archived pot/sob options still deferred (section 5). |
| `hunter_forced_move` | HUNTER | `forced_move` | H5: forced-move windows on a fixed cadence; tick flags `move_started`/`move_ended` | Queries `in_move_window`, `time_to_move`, `window_remaining`; `grade_move_cast` grades cast legality (movement itself is in-client, section 8). |
| `warrior_execute` | WARRIOR | `execute_phase` | W6: phase crossing at the HP threshold; entry grade bands the rage pooled at the crossing ("BANK") | HP fed by the caller; tick flags `execute_phase_entered`/`_exited`; queries `in_execute_phase`, `phase_time`. |
| `druid_powershift` | DRUID | `energy_loop` | D7: continuous-regen energy pool + fixed shift refund; grade by energy at the shift (20-energy rule) | Refund is a sim constant — the D1 talent/helm probe stays BLOCKED, so the sim renders honestly (section 8). Queries `energy`, `grade_next_shift`. |
| `shaman_weave` | SHAMAN | `weave_timing` | S7: weave.lua marker/clip model; grade by margin before the marker, clip → F | Query `marker_fraction`; `grade_weave_cast` returns `nil` when weave.lua is absent. |

## 4. Design targets (C6 handoff)

`st.practice_ui.design_targets` — an ordered array of designmode-registry descriptors (same shape the `design.lua` normaliser validates: `key`, `title`, `get_frame`, `available`, `save(x,y)`, `reset`):

1. `practice_panel` — the control panel. Save re-anchors through `save_position` (persists `practice_panel_x` / `practice_panel_y`); reset restores the 0/0 archive layout and re-applies.
2. `practice_rotation` — the centre-screen rotation display. Position is **session-local** (`ui.rot_x`/`ui.rot_y`; no db keys in this lane) — save/reset only move the live frame.
3. `practice_timeline` — the fight timeline. Position is session-local too (`ui.timeline_x`/`ui.timeline_y`, defaults `0, -200`).

`get_frame` returns nil before init / before the frame exists and `available()` is true only while a session runs — the design-mode refresh skips both silently. All three descriptors pass the real `design.lua` normaliser (pinned in the UI suite). C6 wires them into `designmode.lua`; nothing in this lane calls into design mode.

## 5. Option defaults (standing-rule record for the options pass)

- **This lane adds no toggles and no options.** Every new API is inert until called; there is no default-visible change to scoring, UI layout, or the paladin session.
- Deferred option needs for a later pass (unchanged from the archived deferral, now with the offline engine ready): `practice_aw_includes_pot` / `practice_aw_includes_sob` to wire the P5 drill into the UI, plus a scenario-picker option if the shells become playable. Nil-safe rule applies: `== false` hides, nil = off, defaults documented then.

## 6. Evidence

- `tests/practice_state.lua`: **1069 checks PASS** (was 1065 before the combo-cycle fix; includes the new harness block).
- `tests/practice_ui_state.lua`: **790 checks PASS** (includes new section 21).
- `luacheck` on the four writable files: **0 warnings / 0 errors**. Repo-wide `luacheck .`: **0 errors** (warnings present belong to other lanes' files).
- **Regression bar**: the S–F grade cutoffs, session score, rolling window and persistent-bests tests are unchanged and green; the UI suite's 20 prior sections (session lifecycle, combat pause, driver tick, scoring/bests, design targets aside) are unchanged and green; `practice` stays paladin-playable exactly as shipped.
- **Paladin equivalence proof** (the "paladin is consumer #1" claim): one identical action sequence (begin with `bl_delay=2`, `soc` swap, fade tick, `sob` swap, tick, `on_swing`) is driven through the direct engine and through `H.begin_session`/`H.tick_session` on `paladin_twist`; **38 sim fields + the active_seals set + cast/tick/on_swing flags + lead/grade compare equal**. The harness finish ends the sim fight; the direct sim is untouched by the harness.
- **Mutation proofs on `/tmp/opencode/mut_practice/`** (copy of the needed files; baseline green, restored green):
  1. Harness timing rule — `window_at` start edge `t >= w.start_time` → `t >`: **FAIL "window_at includes the start edge"** (1 of 1069). Restored → PASS.
  2. D7 timing rule — `POWERSHIFT_BANDS` first band `{ max = 20 }` → `{ max = 30 }`: **FAIL "21 energy drops to A" + "the query grades the current energy"** (2 of 1069). Restored → PASS (both suites).
- **Full `bash tests/run.sh`**: the suite was a moving target across this lane's runs (35 steps; 4→7 failures as concurrent lanes landed edits mid-run — `classes/druid.lua` 10:09, `bars.lua` 10:10, `designmode_state.lua` 10:11, `weave.lua`/`classes/shaman.lua` later still). Every observed failure is outside this lane's scope and traces to those in-flight edits: `smoke.lua` (`classes/druid.lua:116 get_class_table` nil), `bars_state.lua` (PALADIN 29 vs 11 frames + WARRIOR/HUNTER count drift), `hud_state.lua` (druid 10 vs 8 slots), `designmode_state.lua` (`bars.lua` `st.register_zone`/`st.new_pips`), `weave_state.lua` / `shaman_state.lua` (shield-charge fallback expectations vs the shaman lane's in-flight `weave.lua`), `druid_guide_state.lua` (D4 EMA), `wiring_check.lua` (`classes/shaman.lua` dead hook + pre-existing accepted entries). Grep-verified: none of the failing files reports a practice-related FAIL, and `tests/practice_state.lua` + `tests/practice_ui_state.lua` are green in every run. This lane's "all green" claim is scoped to its own suites and lint; the repo-wide green gate belongs to the orchestrator's reconcile after all lanes land.

## 7. Honesty note on "extract" (interpretation)

The generic engine is **additive**: the paladin sim functions are untouched and the shipped UI keeps calling them directly (the regression bar), while paladin becomes consumer #1 through the harness lifecycle wrappers — equivalence is pinned by the test above. The scoring pipeline is **re-exposed** under the harness (`H.new_score`/`H.record_attempt`/`H.score_summary` reference the single existing implementation) rather than physically moved into the harness namespace; a physical move would be mechanical churn with zero behavioural gain. If the operator wants the literal namespace split (paladin aliases → harness-owned definitions), it is a small follow-up flagged here.

## 8. UNCONFIRMED items

- **H5 movement compliance** — whether the player actually moved during a forced-move window is in-client state; the offline shell grades only cast legality around the windows. UNCONFIRMED in-client.
- **W6 inputs** — HP fraction and rage are caller-fed; there is no offline target sensor (target-count feasibility remains UNCONFIRMED per `bench/verify_bank.md` §7).
- **D7 model value** — `shift_refund = 40` is a fixed Furor-5/5-model constant, never read from talents (D1 probe stays BLOCKED: no published Furor talent id; Wolfshead Helm item 8345 per `bench/verify_bank.md`). The trainer renders its sim honestly per the brief.
- **P5 wiring** — the archived `practice_aw_includes_pot` / `practice_aw_includes_sob` options remain deferred; seal-piece (SoB) observation is not modelled; the sim-driven path measures lag from the tick that observes AW (the `event` hook exists for exact cast times).
- **S7 coupling** — depends on `weave.lua`'s marker formula (shaman lane owns that file); the S7 checks pin its values, so a weave.lua change will trip them by design.
- **In-client behaviour of anything new** — UNCONFIRMED; offline only. Practice remains paladin-playable as today, and the four shells are not wired to any UI (other classes through the shells only).
