# Trinket Usable — Journal

## 2026-10-19 — Desk opened
- **Purpose:** HUD trinket usable-only gate (operator order): on-use/proc with live effect show; passive stat sticks + unknown-effect hide (unknown-hides, never guess).
- **Scope:** ONLY hud.lua (trinket tracker/usable-gate) + tests/hud_state.lua (trinket pins). OUT: class files, guides, options/config, compat, bars, practice, main, diag, guide_contract, run.sh, TOCs, docs, versions, git.
- **Priors read:** desks/journal.md (full-feature-wave running, harness 38/0 floor), bench/lessons.md (nil-safe, no default-visible change without gate, endings), bench/hud_parity_2026-10-19.md §0/§6 (trinket tracker shared, no per-class gap), desks/icd-tracker/journal.md (X1 pins, TRINKET_DATA UNCONFIRMED header), hud.lua :138-200/:259-368/:638-651, tests/hud_state.lua trinket sections.
- **Next step:** implement usable gate in hud.lua + pins in hud_state.lua, then harness + luacheck + mutations on /tmp/opencode copies.

## 2026-10-19 — lane done
- **Worked on:** hud.lua usable-only gate (HUD.trinket_usable + trinket_has_on_use helpers; trinket_state returns hidden for unusable; icon_should_show non-design path uses usable instead of occupancy) + tests/hud_state.lua §20 (21 pins: proc/on-use show incl. ready-idle + on-CD swipe, passive/unknown/empty hide, never-guess).
- **Current state:** own suite green (hud_state 556 checks PASS, was 535); hud.lua + hud_state.lua luacheck-clean (0/0, floor 2/0 held tree-wide at last stable read); 3/3 mutations killed on /tmp copies (M1 no-hide, M2 inverted, M3 occupancy-revert) then copies removed. hud.lua CRLF + hud_state.lua LF preserved.
- **Next step:** orchestrator reconcile + validation. NOTE crossfire (not ours, zero trinket_usable refs in those files): hunter_state (8149 trap probes), shaman_state/guide (G1 hardcast/Wrath feed), hud_templates_state (rogue kidney/restealth/bandage defaults) fail while sibling lanes morph the tree; failing set shifts run-to-run. Files changed: hud.lua, tests/hud_state.lua only.

## 2026-10-19 — [signal:done] usable-only trinket gate complete, ready for reconcile
- Own pins + mutations prove the gate; tree-wide reds are sibling-lane crossfire owed to orchestrator.
