# buildout_practice-grade — practice enterprise review (grade round)

Date: 2026-10-17. Desk: practice. Brief: `bench/briefs/brief_practice-grade_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").

## 1. Gap list → fix → verify

Scope held exactly: `practice.lua`, `practice_ui.lua`, `tests/practice_state.lua`, `tests/practice_ui_state.lua`. No other file touched; no git; CRLF preserved in both addon files, LF in both test files.

### G1. Four scenario shells had no action-input path (dead stubs)

- **Found:** `hunter_forced_move` had windows/tick/queries but no `event` (cast legality only callable as a bare helper, never through the session); `warrior_execute` tick read `state.hp_fraction` but nothing ever wrote it (no feed path); `druid_powershift` never called `powershift_cycle` (the shift action unreachable through the session); `shaman_weave` had queries only (no tick/event — `grade_weave_cast` unreachable through the session).
- **Fix (practice.lua, additive):** each shell gains an exact-time `event` hook — H5 grades a cast key (number = start, table = `{start, cast_time}`); W6 feeds an HP-fraction number key into `execute_phase_update` (returns the crossing, stores the reading for the tick); D7 runs `powershift_cycle` on the `"shift"` key; S7 grades a cast key (number = swing fraction, table = `{start, clip}`). Re-begin resets added where state could leak across sessions (H5/W6 transient flags, D7 regen-clock re-baseline keeping the pool).
- **Verify:** 37 new engine checks (event paths incl. bad-key nils, re-begin, and the manual caller pattern event→grade→`record_session_attempt`→`session_summary` per shell). The pre-existing H5 "unknown key" check still passes (key `"x"` → nil).

### G2. Timeline drag snapped back (write-only drag)

- **Found:** `build_timeline`'s `OnDragStop` called only `StopMovingOrSizing` — unlike the panel (`save_position`) and rotation display (`save_rotation_position`), a dragged timeline persisted nothing (`timeline_x/y` only changed via design-mode save).
- **Fix (practice_ui.lua, additive):** new `ui.save_timeline_position` (mirrors the rotation saver) wired into the timeline `OnDragStop`; frame script count unchanged (no new frames).
- **Verify:** new UI checks (drag stores offsets + re-anchors; firing the drag-stop script persists).

### G3. Timeline close button invisible

- **Found:** the timeline's 16×16 close button had no texture/label (the panel close uses `UIPanelCloseButton`) — functional (`toggle_timeline` wired) but undiscoverable.
- **Fix (practice_ui.lua, additive):** an `X` label FontString (not a frame — the 69-frame pin holds).
- **Verify:** new UI checks (label text, click toggles both ways).

### G4. Untested-but-wired paths now pinned (no code change)

Key-button `OnClick` → `cast_key`; timeline `OnMouseWheel` → scrollbar + auto-scroll latch; bests hardening — grade-only improvement keeps score but persists the grade, equal-score tiebreak takes the tighter mean error, non-table `practice_bests` reads empty and is repaired by the next save, wrong-typed fields fall back, and load-after-drop proves the reload round-trip. 38 new UI checks (790 → 828).

### Reviewed, no change (deliberate)

- S–F cutoffs, session score, rolling window, persistent-bests semantics: unchanged; equivalence proof + scoring pins green.
- `session.started_at`: written, never read — kept as session-age metadata (pinned by an existing check); removing it would churn the contract for zero behavioural gain.
- P5 tick only observes buff-backed pieces (`hpot`/`abacus`/`dst`); a `sob`-style seal piece grades only via the exact-time event path — matches the deferred pot/sob options (options pass owns it).
- `practice_reset_position` (option_tables) writes `practice_panel_x/y = 0` without re-anchoring — **out of scope** (option_tables not writable in this lane); flagged for the options-grade lane.
- W6 entry rage has no session query (queries take no rage arg) — caller-side `H.grade_execute_entry(state, rage)` + record is the pinned pattern (tested).

## 2. Evidence

- `tests/practice_state.lua`: **1106 checks PASS** (was 1069).
- `tests/practice_ui_state.lua`: **828 checks PASS** (was 790).
- `luacheck` on the four scope files: **0 warnings / 0 errors**. Repo-wide: 0 errors (5 warnings, all other lanes' files).
- **Regression bar intact:** S–F grades, session score, persistent bests behaviour unchanged; paladin harness equivalence still pinned.
- **Mutation proofs on `/tmp/opencode/mut_pg/`** (copy; baseline green; restored green):
  1. D7 `shift_refund` 40 → 50: **5 FAILs** (refund pins, D7 event grade/score knock-ons). Restored → PASS.
  2. Timeline close label `X` → `Y`: **1 FAIL** ("reads X"). Restored in-tree (scratch copy only).
  3. Timeline `OnDragStop` without the save call: **1 FAIL** ("drag-stop persists"). In-tree fix stands.
- **Full `bash tests/run.sh`:** 35 steps, 3 failed — `bars_state.lua` + `hud_state.lua` count pins (expected per brief; reconcile wave owns them, NOT touched) and `toc_check.lua` (`SwedgeTimer.toc` Interface lists 120105 where the check wants 120100 — another lane's toc edit mid-flight, out of scope). Zero practice FAILs; every other suite green.

## 3. UNCONFIRMED items

- In-client behaviour of everything new (event-hook timing, drag persistence, close button) — UNCONFIRMED, offline only.
- W6 HP/rage feeds, D7 fixed refund, H5 movement compliance — still caller/in-client state, as before.
- P5 pot/sob UI wiring + any scenario picker — still the options pass.
