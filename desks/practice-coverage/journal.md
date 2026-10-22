# practice-coverage — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Audit every class for practice-drill coverage; add missing drills only.
- **Scope:** practice.lua, practice_ui.lua (minimal), tests/practice_state.lua, tests/practice_ui_state.lua. No class files, guides, engines, options, config, bars, hud, compat, smoke, run.sh, TOCs, docs, versions; no git; no invented mechanics (mirror rogue_energy_pool / rogue_ss_window / twist-practice patterns only).
- **Next step:** read the harness registry in-lane, audit per-class, pin S/A/B/C/D + nil, verify harness + luacheck + mutations.

## 2026-10-19 — Audit complete: no missing drills, no changes
- **Worked on:** read harness registry in-lane (practice.lua:1492-2669): 8 scenarios covering all 6 classes — PALADIN 2 (paladin_twist, paladin_aw_combo), HUNTER 1 (hunter_forced_move/H5), WARRIOR 1 (warrior_execute/W6), DRUID 1 (druid_powershift/D7), SHAMAN 1 (shaman_weave/S7), ROGUE 2 (rogue_energy_pool, rogue_ss_window). Verified each drill's grade-band + nil pins in tests/practice_state.lua: twist S-F+nil (grade_twist + on_swing F/nil), combo S/A/B/C/D/F+nil (closed=nil), warrior S/A/B/C/D/F+nil (nil rage + unknown HP), druid S/A/B/C/D/F+nil-via-event (dance ignored), shaman S/A/B/C/D/F+nil, rogue-energy S/A/B/C/D/F+nil (incl NaN-tick nil), rogue-SS S/A/B/C/D/F+nil (incl swing_known=false + NaN window). Hunter H5 grades S/A/B/C/F+nil with no D band by established design — adding D would invent mechanics (prohibited), so left as-is.
- **Current state:** no files changed (registry already complete). practice_state 1193 PASS, practice_ui_state 849 PASS, tests/run.sh 37/0, luacheck 0 warnings in scope (repo floor 2/0). Mutations 2/2 killed on /tmp/opencode copies (S-cutoff 100->99: 2 fails; SS-D-max 0.10->0.05: 1 fail); in-tree untouched. practice_ui.lua needs no changes (harness shells remain UI-unwired by design; hunter report already present).
- **Next step:** orchestrator validation (harness + luacheck owner-verified). No follow-ups: nothing needs class-side inputs.

## 2026-10-19 — [signal:done] every class has drill coverage
- Registry audit + pins verified, harness green, mutations killed, zero edits.
