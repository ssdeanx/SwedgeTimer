# Hud-Slot-Pins — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Close filed gap G1 (operator no-gaps bar): tests/hud_state.lua:1188-1198 pins 12 PALADIN HUD slot keys from source with no equivalent for the other 5 classes.
- **Scope:** tests/hud_state.lua ONLY (new parity pins). Out of scope: practice_ui_state (sibling lane), addon code, options/config, run.sh, TOCs, versions, docs, git, lint-config.
- **Next step:** Add per-class key blocks mirroring the paladin shape, reading each class HUD_SLOTS as source of truth; verify + mutation-proof on /tmp/opencode copies.

## 2026-10-19 — G1 closed: all 6 classes HUD keys pinned
- **Worked on:** Added 5 per-class source-pin blocks to tests/hud_state.lua §12 mirroring the paladin 1188-1198 shape (warrior 15 true union, druid 10 true + claw false, hunter 9 true TBC base, shaman 8 true, rogue 10 true + 3 false). Each block matches ST.<CLASS>.defaults with next-class/HUD_TEMPLATES terminator; keys from each class HUD_SLOTS (warrior union via hud_slot_* locals + family branches, druid 1980-1992 + tf/berserk locals, hunter 2133-2143 TBC base, shaman 3121-3130, rogue 1034-1057).
- **Current state:** hud_state 599→660 checks (+61) PASS; full harness 38 steps, 0 failed (practice_ui_state green in-tree, sibling-excluded); luacheck 2 warnings / 0 errors floor held; LF endings preserved (0 CRLF); touched-lines only.
- **Evidence:** 6 drop-a-key mutations on /tmp/opencode/mut_hud_g1 copies each FAIL the suite (warrior op true->false; druid claw false->true + maul true->false; hunter steady true->false; shaman twist true->false; rogue kidney false->true + snd true->false), restored clean.
- **Next step:** orchestrator validation + reconcile (no further edits in this lane).

## 2026-10-19 — [signal:done] G1 HUD slot parity pins complete
- 660 checks green; harness 38/0; luacheck 2/0; 6/6 mutations kill on /tmp/opencode copies.
