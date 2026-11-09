# Buildout: reconcile — count pins + Interface pin + whitespace floor
Date: 2026-10-17. Desk: reconcile. Brief: bench/briefs/brief_reconcile_2026-10-17.md.

## 1. Quiescent pre-check (all got-values matched the brief — no stop needed)
`lua5.1 tests/bars_state.lua` → 12 FAILs with got PALADIN 29/14/8, WARRIOR textures 34 / fontstrings 19 (frames pass, untouched), HUNTER 20/23/13, DRUID 7/21/9, pre-init 28. `lua5.1 tests/hud_state.lua` → 4 FAILs: druid slots 10, order, icons 10, width 302. Slot order verified against `classes/druid.lua:1703-1714` (maul, mangle, rip, rake, bite, shred, tf, berserk, trinket1, trinket2).

## 2. Pin table (old → new)
### tests/bars_state.lua (12 pins; derived: frames = 2 + hands*4 + extra, textures/fontstrings = hands*3 + spec)
| Class | Pin | Old | New |
|---|---|---|---|
| PALADIN | extra_frames / textures / fontstrings | 5 / 3 / 3 | 23 / 11 / 5 |
| WARRIOR | textures / fontstrings | 24 / 8 | 25 / 10 |
| HUNTER | extra_frames / textures / fontstrings | 4 / 8 / 2 | 6 / 14 / 4 |
| DRUID | extra_frames / textures / fontstrings | 0 / 11 / 4 | 1 / 18 / 6 |
| pre-init | `#sb.frames` | 10 | 28 |
WARRIOR frames, SHAMAN, all `lines` unchanged (passing — not touched). NOTE: the widget-breakdown comments above each CLASSES row still describe the old counts; left stale deliberately (pins-only scope) — a future lane should refresh them.

### tests/hud_state.lua (4 pins)
| Pin (line) | Old | New |
|---|---|---|
| `#slots` (1310) | 8 ("six ability slots…") | 10 ("eight ability slots…") |
| `expected` order (1311-1312) | …shred, trinket1, trinket2 | …shred, tf, berserk, trinket1, trinket2 |
| `#DHUD.icons` (1325) | 8 ("eight valid") | 10 ("ten valid") |
| `frame.width` (1326) | 6*36+5*2 ("six shown") | 8*36+7*2 = 302 ("eight shown") |

## 3. Interface decision + ambiguity note
`SwedgeTimer.toc:1` restored `120105` → `120100` (default per brief; matches toc_check + AGENTS.md matrix). CRLF endings verified preserved (70/70 lines). AMBIGUITY (owner call, read-only finding): `SwedgeTimer_Mainline.toc` advertises `120100, 120105, 16001` — 120105 is live there. If Retail genuinely bumped to 120105, the matrix, toc_check, and base toc need a joint update by the owning lane; nothing beyond the brief's default was changed here.

## 4. Whitespace floor
`option_tables.lua` lines 6, 494, 4658: one trailing space each stripped, nothing else. Post-check `grep -rPn ' +$'` over all four touched files → no matches.

## 5. Validation evidence
- `bash tests/run.sh` → **35 steps, 0 failed** (bars_state 733 PASS, hud_state 401 PASS, toc_check PASS, wiring_check PASS).
- `luacheck .` → **2 warnings / 0 errors** in 71 files; both KEEP-ruled and standing: `compat.lua:34:7 unused variable 'addon_name'`, `main.lua:72:10 setting undefined field 'pack' of global 'table'`.
- Mutation proof (`/tmp/opencode/reconcile-mut` copy): hud icons pin 10→8 → `FAIL druid: all ten valid slots build an icon (got 10, want 8)` + `1 of 401 checks failed`; restored → 401 PASS and `diff -r tests/` byte-identical.

## 6. Files changed (complete list)
tests/bars_state.lua, tests/hud_state.lua, SwedgeTimer.toc (line 1 only), option_tables.lua (3 whitespace chars). No git. No lint-config. New visuals unconfirmed in-client (unchanged by this lane).
