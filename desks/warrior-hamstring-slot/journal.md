# warrior-hamstring-slot — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Wire the warrior hamstring-weave filler into guide + HUD slots on the existing engine (hamstring_known input, pure should_weave_hamstring, gather mapping).
- **Scope:** ONLY classes/warrior.lua (slot additions + gather mapping), warrior_guide.lua (slot prompt docs, no evaluate() change), tests/warrior_state.lua, tests/warrior_guide_state.lua. OUT: options files, compat, guide_contract, smoke, run.sh, TOCs, bars.lua, hud.lua, practice, main, docs, versions; no Victory Rush; no git; ids 7373/18499 only.
- **Next step:** implement base-set slot + gather cooldown + pins, keeping TBC/Era/Wrath/SoD at six.

## 2026-10-19 — Hamstring slot live on the base set, verification green
- **Worked on:** guide_slot_hamstring (7373 fallback, rank-resolved through hamstring_ids) + hud_slot_hamstring appended sixth on the base set only (TBC/Era/Wrath-fury/arms/SoD untouched at six); hamstring_current_id cache + resolve in resolve_guide_icons; hamstring_remaining/duration gather via get_guide_cooldown (GCD-echo filtered, ready when unlearned); HUD_COOLDOWN_FALLBACK hamstring = 0; docblock updates in both modules (base six, Forever sixth, Era/TBC still filed for slot-space). No evaluate() change: no rule names "hamstring" yet (prompt + threshold/toggle options wiring stays filed).
- **Current state:** warrior_state 788 + warrior_guide_state 1112 green; full harness 38/0; luacheck 2/0 floor (0/0 on the 4 touched files); endings preserved (lua CRLF, tests LF). 6/6 mutations caught on /tmp/opencode/mut_hamstring (base-slot strip errors the suite; cooldown strip, known-flag strip, HUD strip, icon re-point strip each fail their pins; evaluate-change simulation breaks 36 pins); tree copy restored byte-identical.
- **Next step:** orchestrator validation + in-client checklist (Hamstring swipe on base/Forever, GCD fallback feel, Era/TBC slot-space decision for the weave prompt).

## 2026-10-19 — [signal:done] hamstring slot live, handed to orchestrator
- Base sixth slot + HUD + gather cooldown live; 788 + 1112 pins green; harness 38/0, luacheck 2/0; 6/6 mutations caught; Era/TBC weave prompt needs a slot-space decision (filed).
