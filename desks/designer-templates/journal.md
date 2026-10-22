# designer-templates — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Make designer + HUD templates fully working per class (bars, HUD slots, cooldown frame; template apply/persist + Custom fallback; location/size/spacing live).
- **Scope:** ONLY design.lua, designmode.lua, hud.lua, config_presets.lua (template tables + defaults), option_tables.lua (template widget + geometry controls), tests/hud_templates_state.lua, tests/hud_state.lua, tests/bars_state.lua (design pins only), classes/*.lua (per-class designer hooks ONLY — setup visuals, anchors, slot sets; no guide/engine/rule changes).
- **Next step:** audit per class, fix broken templates (rogue coldblood, warrior hamstring), pin + mutate, file preview/row-rhythm/widget gaps as UNCONFIRMED.

## 2026-10-19 — Audit + fixes built (done)
- **Worked on:** bench-read (hud_templates spec, journals, lessons) + desk-open (this desk); audited all 6 classes x designer/HUD/template/geometry/persistence (designmode registry, hud preview_state, template tables + widget, LAYOUT_KEYS, per-class post_init/on_bar_update). Fixed F1 rogue coldblood (templates + suite 12->13) + F2 warrior hamstring (default + templates + suite 13->14). Filed G1 hamstring widget (options-contract), G2 preview samples, G3 row rhythms, G4 template positions as UNCONFIRMED/beyond-contract.
- **Current state:** Done. Harness 38/0, luacheck 2/0 floor, 3/3 mutations kill on /tmp/opencode copies (M1 coldblood strip, M2 hamstring strip, M3 default strip); copies removed. Bench artifact bench/designer_templates_2026-10-19.md. Endings preserved, no trailing WS. No guide/engine/practice/compat/main/diag/contract/smoke/run/TOC/README/docs/version edits.
- **Next step:** Orchestrator validates (re-run harness, spot-check hunks); in-client session owns designer drag/preview/template apply visuals (all UNCONFIRMED in-client).
- [signal:done] designer + templates per class functional with pins, gaps filed
