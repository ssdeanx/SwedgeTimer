# enemy-swing — Journal

## 2026-10-17 — Desk opened
- **Purpose:** hostile-target swing bar — NEW module + toc entries + new offline suite + exactly one run.sh step.
- **Scope:** new enemy-swing module file, all 7 toc variants, tests/run.sh, new suite file only.
- **Next step:** wait for dispatch brief in bench/briefs/; toc path casing exact; module listed in every flavor toc.

## 2026-10-17 — [signal:done] build-out round 1 complete
- **Worked on:** `enemy_swing.lua` (NEW, 643 lines) — SuperSwingTimer-port hostile-target mainhand swing bar: pure helpers (family gate, off-hand rule, GUID matching, target eligibility, speed precedence, cycle progress/remaining, rescale, visibility matrix) + self-wiring driver frame (no main.lua edits allowed this round) + lazily built bar parented to the mainhand bar frame. Tocs: `enemy_swing.lua` added after `swing_source.lua` in all 7 variants (line 24 base/Vanilla/TBC/Wrath, line 23 Mainline/Cata/Mists; CRLF preserved byte-for-byte, diff = one added line each). `tests/enemy_swing_state.lua` (NEW, 228 checks). `tests/run.sh`: exactly two new steps (paladin_state, enemy_swing_state) — 33 → 35 steps.
- **Current state:** own step green; toc_check 732/0; luacheck 0 errors / 0 warnings on both new files. Mutation proof on /tmp/opencode/mut_enemyswing: family-gate mutation (FOREVER added to CLEU_FAMILIES) → 6 failures; off-hand-rule mutation → 7 failures; restored clean. Full harness at final observation: 35 steps, 3 failed — all other lanes' in-flight state (`tests/paladin_state.lua` not yet landed; `tests/bars_state.lua` 7 checks pinning paladin/warrior frame counts mid-edit; `tests/design_state.lua` 200-locals mid-edit by the bars+design lane), none touched by this desk.
- **Next step:** in-client confirmation of bar placement/colours + UnitAttackSpeed("target") fidelity; options pass adds `enemy_swing_enabled` (default false) + live width/position; design-mode pass may make it draggable. Brief's "37 steps" was inconsistent with its own "33 → 35" — recorded in the buildout report.

