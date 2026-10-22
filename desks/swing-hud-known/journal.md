# swing-hud-known — Journal

## 2026-10-22 — Desk opened
- **Purpose:** Gate every HUD icon/slot on spell-known (leveling usability) via the HU-15 seam: api.is_spell_known / api.is_spell_known_state; "client cannot answer" stays fail-visible, only confirmed-unknown hides. Binding Era=id, Anniversary=name, separate legs.
- **Scope:** hud.lua + per-class HUD icon/slot definitions (classes/*.lua HUD_SLOTS + get_hud_state). Off-limits: swing bars, dispatcher, options, run.sh, vendored Libs, TOCs, versions.
- **Next step:** Implement central fail-visible gate in hud.lua, align 3 per-class binary hide-gates (paladin band/AM, shaman searing), extend hud_state (fixture + Era/TBC legs + 7c re-cut), run focused suites + luacheck + red-first mutations on /tmp/opencode copies.

## 2026-10-22 — Lane done, all green
- **Worked on:** Central fail-visible gate in hud.lua (HUD.spell_known_allows + family-correct hud_known_query, applied in update_display, preview skipped); paladin band (hor/how_wrath) + AM and shaman searing gates converted binary→tri-state fail-visible. hud_state: fixture book now fully trained (ids+names), 7c decline re-cut to SHOW, new §7d (unit truth table + TBC name leg + Era id leg with row-reflow), band static pin re-cut to `~="unknown"`.
- **Current state:** hud_state 838 PASS, hud_templates_state 928/0, spell_known_state 251/0, paladin_state 1241 PASS, shaman_state 1073 PASS; luacheck 0/0 on all 4 touched files. Mutations (full-tree /tmp/opencode copies, removed): M1 neutered→6 FAIL, M2'' hide-one-known→7 FAIL, M3 fail-hidden→3 FAIL, M4 band revert→2 FAIL. M2-full aborts suite at §3 (row collapses). Copies removed; stray luac.out removed.
- **Next step:** Orchestrator: full run.sh + reconcile. In-client owed: level an alt / unlearned spell hides its icon; learned shows; no ADDON_ACTION_BLOCKED from the per-tick book probes.
- **Signal:** done 20261022T040000Z (desks/swing-hud-known/.signals/).
