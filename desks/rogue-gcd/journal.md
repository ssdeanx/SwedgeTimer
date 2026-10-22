# rogue-gcd — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Give rogue the running-GCD swipe all five siblings have (bench/hud_parity_2026-10-19.md R-1).
- **Scope:** `classes/rogue.lua` (provider GCD path only) + `tests/rogue_state.lua` (pins only). No hunter files, no guide/engine, no options/compat/bars/hud/practice/main/diag/docs/TOCs/versions; no git.
- **Shape:** borrow hunter.lua:1901-1908 verbatim — `HUD_SKIP_GCD = {}` (all rogue slots rotational) + `hud_gcd_remaining` + borrow helper gated on ready (`remaining == 0`, not hidden, no SKIP entry); wrap each non-hidden provider return so a running CD/aura still short-circuits first.
- **Next step:** land provider edit + pins, then harness + luacheck + mutation proofs on /tmp/opencode copies.

## 2026-10-19 — R-1 built, lane green
- **Worked on:** `classes/rogue.lua`: added `HUD_SKIP_GCD = {}` + verbatim `hud_gcd_remaining` + `hud_borrow_gcd` gate (hidden/SKIP/ready-only), wrapped all 9 non-hidden provider returns (snd 1167, ar/bf 1195, rupture/ea 1203, tea 1238, kick 1251, coldblood 1266, kidney 1286, restealth 1303, bandage 1332); aura/CD paints + hidden + trinket paths untouched. `tests/rogue_state.lua`: new R-1 block (20 checks: nil/expired stamp, CD-wins, aura-wins, borrow across snd/rupture/ea/kick/tea/kidney/coldblood/bandage).
- **Current state:** rogue_state 498/0; luacheck 0/0 on touched files (tree holds 2/0 floor); 4 mutations killed on /tmp/opencode copies (nil-stamp, expired, CD-wins, SKIP-gate), copy cleaned. Full harness: 37/38 — the single FAIL is tests/hud_state.lua paladin-row geometry, crossfire from a parallel lane (paladin.lua + hud_state.lua mtimes 14:56/14:57, after my 14:55 edits); zero rogue/GCD FAIL lines in that suite.
- **Next step:** orchestrator validates + reconciles (hud_state red belongs to the parallel lane, not this one).

## 2026-10-19 — [signal:done] R-1 GCD swipe live with pins
- rogue_state 498/0, luacheck clean, 4/4 mutations killed; full harness 37/38 (hud_state red = parallel-lane crossfire, zero rogue lines).
