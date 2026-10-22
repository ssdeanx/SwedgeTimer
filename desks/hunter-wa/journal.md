# Hunter WA — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Consume TBC hunter WeakAura pack (docs/hunter-wa.json, React/Laxx Mod, wago eEJOoHci) + operator screenshots and map useful bits into hunter implementation.
- **Scope:** ONLY classes/hunter.lua, hunter_guide.lua, hunter_ui.lua, tests/hunter_state.lua, tests/hunter_guide_state.lua, tests/practice_state.lua (hunter pins ONLY).
- **Out of scope:** option tables/config, H2 lust logic (CUT, verify absence), compat, bars, hud.lua, practice.lua mechanics, main, diag, guide_contract, run.sh, TOCs, README, docs, versions, git, invented ids.
- **Next step:** read-only extract of WA JSON + current hunter files, then map with pins/conflicts/filed-extras.

## 2026-10-19 — Operator TBC-name fact wired + WA map (read-only extract first)
- **Worked on:** read-only extract of docs/hunter-wa.json (rotation tables, SWTMode 1/2, cast-tick math, Steady/Aimed/Multi/Auto + trap/debuff/buff ids, Wing Clip 2974 + item 8149 sweet spot) vs sim audits + hunter files. Then applied the operator fact: TBC state queries take names (spell_token/queue_tokens in classes/hunter.lua, resolve_spell in hunter_ui.lua); Era keeps ids. WA id->name mapping recorded in comments + bench/hunter_wa_map_2026-10-19.md (§8).
- **Current state:** hunter_state 654/654, hunter_guide_state 1121/1121 (incl. name-aware TBC cooldown-stub fix), practice_state 1208/1208; luacheck 0/0 on all 6 scope files; 3/3 mutations kill on /tmp/opencode copies (9+1+5 pins, Era pins held, byte-identical restores, copies removed). H2 CUT verified intact (no lust reads added). Tree harness 34/38 + luacheck 8 warnings are concurrent-lane crossfire (shaman/druid/rogue files only, untouched by this lane); hunter_guide.lua diff is another lane's, left alone.
- **Next step:** orchestrator validates + in-client TBC check (name reads live) and triages the filed WA-only extras (rotation text, SWTMode, trap machines, item-8149 probe).
- **Conflict/filed:** Arcane 14287 (WA) vs 27019 (sim wins, pin asserts absence); WA-only extras filed in bench §1/§2/§6 (not built: option widgets/HUD/bars/compat out of scope).

## 2026-10-19 — [signal:done] hunter-wa TBC-name wiring complete
- TBC-name/Era-id tokens wired with pins where sim-consistent; conflicts filed with both citations; WA-only extras filed (not built). Harness green on scope, luacheck floor on scope files, mutations kill.
