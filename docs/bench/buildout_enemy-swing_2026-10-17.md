# buildout: enemy-swing — hostile-target swing bar (round 1)

Date: 2026-10-17 · Desk: enemy-swing · Brief: bench/briefs/brief_enemy-swing_2026-10-17.md
Status: **code complete, offline-verified**; in-client checks outstanding (marked UNCONFIRMED below).

## What shipped

| Artifact | Change | Evidence |
|---|---|---|
| `enemy_swing.lua` | NEW, 643 lines — SuperSwingTimer-port enemy mainhand swing bar (pure helpers + self-wiring driver + lazy bar frame) | `luac5.1 -p` OK; luacheck 0 warnings / 0 errors |
| 7 toc variants | +1 line each: `enemy_swing.lua` after `swing_source.lua` | diff = exactly one added line per toc; CRLF preserved (see below) |
| `tests/enemy_swing_state.lua` | NEW, 598 lines / 228 checks | `lua5.1 tests/enemy_swing_state.lua` → 228 checks, 0 failures |
| `tests/run.sh` | exactly TWO new steps: `tests/paladin_state.lua`, `tests/enemy_swing_state.lua` | 33 → 35 steps |

Nothing else was touched (no `bars.lua`, `main.lua`, class files, `compat.lua`, config/option tables). No git commands. No lint-config change. No `_` renames.

## TOC diffs (exact)

Insertion point: directly after the `swing_source.lua` line (dependency order: compat → swing_source → enemy_swing → utils/main; the module is load-order independent by design).

| toc | inserted line | line no. | diff (cat -A) |
|---|---|---|---|
| SwedgeTimer.toc | `enemy_swing.lua` | 24 | `23a24 > enemy_swing.lua^M$` |
| SwedgeTimer_Vanilla.toc | `enemy_swing.lua` | 24 | `23a24 > enemy_swing.lua^M$` |
| SwedgeTimer_TBC.toc | `enemy_swing.lua` | 24 | `23a24 > enemy_swing.lua^M$` |
| SwedgeTimer_Wrath.toc | `enemy_swing.lua` | 24 | `23a24 > enemy_swing.lua^M$` |
| SwedgeTimer_Mainline.toc | `enemy_swing.lua` | 23 | `22a23 > enemy_swing.lua^M$` |
| SwedgeTimer_Cata.toc | `enemy_swing.lua` | 23 | `22a23 > enemy_swing.lua^M$` |
| SwedgeTimer_Mists.toc | `enemy_swing.lua` | 23 | `22a23 > enemy_swing.lua^M$` |

- All seven remain `ASCII text, with CRLF line terminators` (`file(1)` after edit); every other line is byte-identical (diff output shows only the addition).
- Line-number difference (24 vs 23) is the pre-existing per-flavor divergence: Mainline/Cata/Mists omit the `LibClassicSwingTimerAPI` line.
- `lua5.1 tests/toc_check.lua` → **732 checks, 0 failures** (casing, duplicates, module coverage, family invariants).

## Family gate matrix (implemented)

Gate = `st.family` (compat.lua) membership in the classic-line set, plus the `C_EventUtils.IsEventValid("COMBAT_LOG_EVENT_UNFILTERED")` probe where the client exposes one. Never keyed on a Mainline-code boolean or a version string.

| family | module state | basis |
|---|---|---|
| ERA, TBC, WRATH, CATA, MISTS | **armed**: driver frame + 6 events registered | classic combat log (CLEU `SWING_DAMAGE`/`SWING_MISSED`) |
| FOREVER | **inert**: no frame, no event, no reads | Mainline-code, no classic combat log |
| RETAIL | **inert** | inert stand-in swing engine |
| UNKNOWN | **inert** | no evidence either way |

Hardening: an approving probe must not arm an off-family client (family gate dominates — pinned by test); a rejecting probe leaves a classic family inert (pinned).

## Option defaults (documented for the options pass)

- Key: `ST.db.profile.enemy_swing_enabled` — **default OFF**: nil/absent = off; only an explicit `== true` arms it (nil-safe read; missing addon/db/profile/key all read as off).
- Options pass should add: `enemy_swing_enabled = false` to `ST.defaults.profile` + a top-level checkbox, and optionally live width/position settings (current module constants: `BAR_WIDTH=200`, `BAR_HEIGHT=10`, `BAR_GAP=2`, `BAR_PADDING=1`, red fill / 60 % black bg).
- Design-mode pass may make the bar draggable; it is currently a child of the mainhand bar frame (`ST:get_bar_frame("mainhand")`, the hunter-cast-bar / paladin-sidebar layout hook) and hides whenever that bar hides.

## Behaviour pinned offline (tests/enemy_swing_state.lua)

- Pure: family matrix (5 true / FOREVER+RETAIL+UNKNOWN+nil+non-string false); off-hand rule (only explicit true is off-hand; nil/false count as mainhand); GUID matching; target eligibility; speed precedence (live > cached > 2.0); cycle progress/remaining with both-edge clamps; rescale (proportional remaining, <0.01 s no-op returns the same table, expired-cycle case); visibility matrix; toggle read.
- Runtime (frame sandbox): driver registers exactly the six events in order; no frame built while the toggle is off; lazy bar build on the mainhand bar frame (parent/anchor/size/level/colours/OnUpdate identity); show/hide on regen + tracked hostile target; CLEU `SWING_DAMAGE` starts the cycle at `api.get_time()` with `UnitAttackSpeed("target")`; off-hand hits / wrong source GUID / non-swing subevents ignored; `SWING_MISSED` mainhand restarts; `UNIT_ATTACK_SPEED` rescale formula; target switch clears the cycle; `UNIT_DIED` clears; combat exit clears + hides; world entry re-tracks and adopts `UnitAffectingCombat`; nil payload / nil addon / bar-stack getter error all degrade without throwing; the bar frame is built once, never rebuilt.
- Static contract: source contains no raw clock token, no `st.is_mainline`, and keeps `st.api.get_time(` + `CombatLogGetCurrentEventInfo` + the family gate.

## Validation evidence

- `lua5.1 tests/enemy_swing_state.lua` → **228 checks, 0 failures**
- `lua5.1 tests/toc_check.lua` → **732 checks, 0 failures**
- `luacheck enemy_swing.lua tests/enemy_swing_state.lua` → **0 warnings / 0 errors**; full `luacheck .` → **0 errors** (warning count fluctuates with other lanes' in-flight edits; the two new files are 0/0).
- `bash tests/run.sh` at exit → **35 steps, 3 failed**, all other lanes' in-flight state, none touched by this desk (`enemy_swing_state` itself PASSes; the tree was still moving between runs):
  1. `tests/paladin_state.lua` — file not yet landed by the paladin lane (my run.sh step references it per the brief).
  2. `tests/bars_state.lua` — 7 checks pinning PALADIN/WARRIOR frame/texture/fontstring counts mid-edit (the paladin CD-icon and warrior features landing in parallel). `bars_state.lua` loads a static module list that excludes `enemy_swing.lua`, so it cannot be affected by this desk's files.
  3. `tests/design_state.lua` — `main function has more than 200 local variables` (appeared during the final run; the bars+design lane is mid-edit on `design.lua`). Not touched by this desk.
- Mutation proof on `/tmp/opencode/mut_enemyswing/` (module + suite copy; restore verified green after each):
  - **M1 family gate**: `FOREVER = true` added to `CLEU_FAMILIES` → **6 FAILs** (FOREVER matrix rows + approving-probe row) → restored → 228/0.
  - **M2 off-hand rule**: `return "offhand"` → `return "mainhand"` → **7 FAILs** (hand rule + cascade: off-hand hits counted, rescale drift) → restored → 228/0.

## Discrepancy + UNCONFIRMED

- **Brief arithmetic inconsistency (recorded, not hidden):** the run.sh duty says "Expected counters 33 → 35" while the validation line says "37 steps after your edits". Actual = **35** (33 + exactly the two mandated steps). The explicit two-step duty was followed.
- UNCONFIRMED (in-client): bar placement/size/colours under a real bar stack; label text legibility; `UnitAttackSpeed("target")` fidelity per classic family; whether `UNIT_ATTACK_SPEED` fires for enemy haste changes (the bar re-reads on every swing start regardless, so the worst case is a resync at the next swing); Cata/Mists CLEU `SWING_*` presence is family-gate-assumed and not client-checked here.
- UNCONFIRMED (design): the bar is a child of the mainhand bar frame, so it hides whenever that bar hides — deliberate layout-hook behaviour, revisitable in the options/design pass.
