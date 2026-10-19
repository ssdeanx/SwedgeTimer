# reconcile — Journal

## 2026-10-17 — Desk opened
- **Purpose:** final code wave — update the 16 count pins (bars_state 12, hud_state 4) to verified quiescent values, resolve the SwedgeTimer.toc Interface pin (120105 vs 120100), strip 3 whitespace lines. Target: 35/35 green, luacheck 2-warning floor.
- **Scope:** tests/bars_state.lua (pins only), tests/hud_state.lua (pins only), SwedgeTimer.toc (Interface line only), option_tables.lua (3 ws lines only).
- **Next step:** execute bench/briefs/brief_reconcile_2026-10-17.md. Any got/want mismatch = stop and report, do not guess.

## 2026-10-17 — Reconcile executed (done)
- **Quiescent check:** re-ran both suites pre-edit; every got-value matched the brief (bars 29/14/8, 34/19, 20/23/13, 7/21/9, pre-init 28; hud slots 10 / order maul,mangle,rip,rake,bite,shred,tf,berserk,t1,t2 / icons 10 / width 302 — order confirmed against classes/druid.lua:1703-1714).
- **Edits (scope-held):** tests/bars_state.lua 12 pins (PAL tx11/fs5/xf23; WAR tx25/fs10; HUN tx14/fs4/xf6; DRU tx18/fs6/xf1; pre-init 28); tests/hud_state.lua 4 pins (slots 10, expected +tf/berserk, icons 10, width 8*36+7*2 + labels); SwedgeTimer.toc Interface → 120100 (CRLF 70/70 preserved); option_tables.lua 3 trailing spaces stripped (lines 6, 494, 4658). Numbers/expressions only — stale widget-breakdown comments in bars_state.lua CLASSES table now lag (flagged for owner, not touched: pins-only scope).
- **Validation:** `bash tests/run.sh` → 35 steps, 0 failed. `luacheck .` → 2 warnings / 0 errors, both KEEP-ruled (compat.lua:34 addon_name; main.lua:72 table.pack). Mutation proof on /tmp/opencode/reconcile-mut: icons pin 10→8 → exact FAIL returns; restored → PASS + `diff -r tests/` byte-identical.
- **Interface ambiguity (owner call):** base toc restored to 120100 per toc_check + AGENTS.md matrix, but `SwedgeTimer_Mainline.toc` (read-only) advertises `120100, 120105, 16001` — 120105 present there. If Retail genuinely bumped, matrix + toc_check + base toc all need a joint update by the owning lane; I changed nothing beyond the brief's default.
- **Report:** bench/buildout_reconcile_2026-10-17.md. Signal: desks/reconcile/.signals/2026-10-17T15-03-30Z.json.
