# Build-out: core-wiring (rest-of-tree warnings, wire-not-strip)

Date: 2026-10-17. Desk: wiring. Brief: `bench/briefs/brief_core-wiring_2026-10-17.md`.
Owner order (verbatim): "when u see any unused variable that u use them properly,
dont remove them unles they absolutely serve no purpose, but make sure u trace it
bcuz there probably is a purpose."

## Scope (as briefed)

bars.lua, compat.lua, main.lua, LibGlobalCooldown.lua, LibLatencyMonitor.lua,
utils.lua, classes/druid.lua, classes/paladin.lua, classes/warrior.lua (listed
lines only), tests/druid_guide_state.lua. FORBIDDEN (untouched): main.lua diag
hook block, tests/bars_state.lua, tests/hud_state.lua, tests/run.sh, all tocs.
No git, no lint-config changes, endings preserved, never gated on
`st.is_mainline` alone (no family gates added at all).

## Result

luacheck on the 10 files: 33 warnings -> 2 warnings, 0 errors. Both remaining
are KEEP-with-rationale (see table). Full tree: 5 warnings / 0 errors (the other
3 live outside this scope, in other lanes' files).
Harness `bash tests/run.sh`: all touched suites PASS — druid_guide_state
65757 checks (not weakened vs the ~66k baseline), secret_guard, main_init,
options_load, diag, design, rotationtext, all class/guide suites. Four failing
steps are other lanes' pins (bars_state 12, hud_state 4, designmode_state,
toc_check) — proven independent of this lane on a /tmp/opencode pristine copy
(see Non-ownership proofs).

## Verdict table (file:line -> traced purpose -> verdict + evidence)

| Warning | Traced purpose | Verdict | Evidence |
|---|---|---|---|
| bars.lua:41 unused `db` | Hand table for init; line 68 re-fetched the same table for `LWIN.RegisterConfig` | WIRE: pass `db` at line 68 | M1: revert reproduces `unused db@41` only |
| bars.lua:724 unused `db` | Dead fetch in `set_gcd_width`; body never reads it; `get_hand_table` is a pure table return (main.lua:189-191), no side effects | REMOVE with rationale | M2: re-add reproduces `unused db@724` only |
| bars.lua:782 unused `db_class` | Dead fetch in `set_gcd_marker_positions`; body uses only `db_hand` | REMOVE with rationale | M3: re-add reproduces `unused db_class@782` only |
| bars.lua:786 unused `hand_is_full` | Stale debug local (`GetTime() >= ends_at`); canonical full-state is `self[hand].is_full` (delay-timer driven, main.lua:910-914), used consistently at bars.lua:566,590,801,820,878,890,902,929; commented print at 787 referenced it | REMOVE with rationale (+ stale debug comment 787) | M3: re-add reproduces `unused hand_is_full@786` only |
| compat.lua:34 unused `addon_name` | Documents the `(addonName, st)` vararg shape per module convention (AGENTS.md); nothing in compat creates frames, so no honest use exists; renaming to `_` would be silencing (forbidden) | KEEP with rationale (no code change) | grep: zero other refs in file; convention cited |
| main.lua:48 unused `print` | `st.utils.print_msg` debug shorthand; all live `print(` hits were comments, so the alias had no live use | WIRE: route the one live debug call (1644, `st.debug` gate) through `print` — byte-identical behavior | M4: revert reproduces `unused print@48` only |
| main.lua:70 setting `table.pack` | Intentional Lua 5.1 shim: 5.1 has no `table.pack`; pinned by tests/main_init_state.lua:71 and the enemy_swing.lua:235 header note | KEEP with rationale + intent comment (any definition of the field warns; no lint-config edit allowed) | main_init_state PASS; M5: comment-only change |
| main.lua:113,125 loop at most once | Iterator closures (`iter_hands`, `generic_iter`): `while i <= n do return ... end` executes at most once per resumption by construction — semantically `if`; callers (`bars`, `main`, `option_tables` `for hand in` loops) behave identically | WIRE: `while` -> `if` in both | M6: revert reproduces exactly the 2 loop-once warnings |
| LibGlobalCooldown.lua:72 unused `simple_floor` | Dead helper; sole contemplated call site was commented out (line ~116); live comparison (line ~119) operates on raw floats pinned by secret_guard (`eq(current_spell_gcd, 1.5)`); bare-`floor` upvalue is a latent hazard outside the client | REMOVE with rationale (+ stale commented call + its intro comment) | M7: re-add reproduces `unused simple_floor@72` only; 0 `simple_floor` refs remain in tree |
| LibGlobalCooldown.lua:216 unused `time_started` | Interrupt handler needs only the duration (`== 0` releases the lock); the sibling full read in `poll_gcd` (line ~139) is untouched | WIRE: narrow to `select(2, GetSpellCooldown(...))` — no `_`, zero behavior change | M8: revert reproduces `unused time_started` only; secret_guard interrupt checks PASS |
| LibLatencyMonitor.lua:57 `not (x == y)` | Operands are `old_home` (nil pre-first-poll, else ms number from `GetNetStats`) vs nil — never a table, NaN `~= nil`; in-file precedent line 52 already uses `~=` on the same values | WIRE: `old_home ~= nil` | M9: revert reproduces the replaceable-`not` warning only |
| utils.lua:46 trailing WS | `else ` | TOUCH (strip 1 space, CRLF kept) | M10 batch |
| class-file lines (druid 277/305, paladin 485/494, warrior 558/585) | Comment trailing spaces + whitespace-only lines; scope = these lines only | TOUCH (strip, CRLF kept) | M10 batch: all 20 whitespace warnings return at original lines on full revert |
| LibGlobalCooldown 62/63/127, bars 185/552/564/697/791, main 109/398/661/1181, latency 51 whitespace | Same class: trailing spaces / whitespace-only lines inside touched regions | TOUCH (strip/blank, endings kept) | M10 batch |
| tests/druid_guide_state.lua:2824 shadow `tick` (line 909) | Inner helper closes over `TST/t` (D4 EMA end-to-end block); outer closes over `ST/sandbox`. File precedent: distinct per-block names (`stick` 2422, `ftick` 2648, `etick` 1599, `ctick` 1014) | WIRE: rename inner `tick` -> `btick` + 3 callsites (first tried `etick`, collided with the pre-existing 1599 helper — renamed again, documented) | M11: revert reproduces exactly the single shadow warning; suite still 65757 PASS |

## Validation

- `luacheck` (10 files): 33 -> 2 warnings / 0 errors. `luacheck .`: 5 warnings / 0 errors.
- `bash tests/run.sh`: 35 steps; every suite this lane touches is PASS.
- `luac5.1 -p` on root + classes: PASS (incl. a mid-task repair: one edit briefly
  left `function table.pack(...)` bodyless; repaired immediately to the
  commented shim, syntax re-verified before proceeding).
- Mutation proofs: /tmp/opencode/mut_* (per-change reverse-mutation, luacheck
  target check) + /tmp/opencode/mut/ws (whitespace batch) + /tmp/opencode/pristine_proof
  (full-tree reverse, non-ownership). Every wiring change reproduces exactly its
  original warning on reversal and nothing else.

## Non-ownership proofs (failures NOT from this lane)

- toc_check (`SwedgeTimer.toc` Interface 120105 vs 120100 pin): .toc files are
  FORBIDDEN to this lane and untouched; pristine copy fails identically (732 checks, 1 failure).
- designmode_state (pips registry 10 vs 8 + overlay pins): driven by the
  bars-design lane's `register_zone`/`new_pips` additions in bars.lua:413-424,961-983
  (present but never touched by this lane); pristine copy fails the same pips pin.
- bars_state (12) + hud_state (4): the known reconcile-wave count pins; this
  lane was briefed to expect them and touched neither file.
- Note: designmode_state showed 1 failed in-tree vs 3 failed on the pristine
  copy (overlay pins vary run-to-run) — suggests parallel-lane interference or
  order dependence; flagged for the reconcile wave, not investigated here
  (out of scope).

## UNCONFIRMED

- Whether the toc Interface pin (120100 vs 120105) reflects an intended dual
  Retail/Forever advertisement (AGENTS.md matrix lists both) or a stale test
  expectation — tocs are another lane's artifact.
- Whether designmode_state overlay-pin variance is parallel-edit tearing or
  genuine order dependence — needs a quiescent re-run in the reconcile wave.
- In-client behavior of the `~/=` and `if`-iterator edits: offline-equivalent
  by construction (same operands, same single-shot semantics), but per CAIRN
  this is "verified offline", never "verified in-client".
