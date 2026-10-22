# options-wire — Journal

## 2026-10-19 — Desk opened
- **Purpose:** wire the filed options widgets from the last wave (druid RipCP shape + shaman hold/SR/ES surfacing specs) within option_tables.lua, config_presets.lua, tests/options_load_state.lua only.
- **Scope:** option_tables.lua, config_presets.lua, tests/options_load_state.lua. No other files.
- **Next step:** verify each candidate widget has a live in-tree consumer; build only the wired ones, file the rest with key shape + missing consumer.

## 2026-10-19 — RipCP widget wired, shaman/paladin surfacing filed
- **Worked on:** built the one widget with a live consumer (druid `guide_rip_min_cp` range 2-5 step 1 default 4: widget option_tables.lua:4234, default config_presets.lua:263) + rewrote §13(d) pins from filed-unwired to wired (1394 checks incl. shape/order/getter/setter/default/source + refresh-window order non-collision). Shaman hold/SR/ES + paladin rank-1 stay filed (keys would be inert — no db reader in gather/engine; filed with key shape + missing consumer below).
- **Validation:** options suite 1387/0, full harness 38/0, luacheck 0/0 on all three touched files (tree floor 2/0 held: compat + main KEEP). Endings preserved (tables LF, presets CRLF, tests LF). 7/7 mutation kills on full-repo /tmp/opencode/options-wire copies (M1 min-span, M2 default-5, M3 key-gone, M4 order-collision, M5 inert-sr-widget-filed-pin, M6/M7 inert-default-filed-pins; M6 first attempt was a no-op injection into a key absent from presets — redone properly, killed). Copies restored byte-identical (md5-verified).
- **Filed (owner: orchestrator):** (1) dedicated WF-hold opt-in (e.g. `stormstrike_hold` bool false): live hold stays tint reuse (classes/shaman.lua:2679), no dedicated-key reader — needs gather + engine design; (2) twist mana-pause surfacing (pct 5/10/20/30 default 10 = weave.lua:632): engine reads inputs.twist_mana_threshold (shaman_guide.lua:382-384) but gather never feeds it from db (feed filed at classes/shaman.lua:2920-2925); (3) SR surfacing (TBC 0-30 dflt 10 = shaman_guide.lua:258, SoD 0-100 dflt 65 = :259): gather feeds hardcoded constants (classes/shaman.lua:2772,2778), never db; (4) ES floor surfacing (Era 0.50 = shaman_guide.lua:262, consumed :328): no db override path; (5) paladin rank-1 opt-in stays filed (UI decision owed). Twist-mana widget already shipped (option_tables.lua:1694) — not duplicated.
- **Next step:** orchestrator validates + reconciles (options pins 1387) + in-client test session. No further offline work owed by this lane.

## 2026-10-19 — [signal:done] RipCP wired, rest filed
- Signal `desks/options-wire/.signals/2026-10-19T120000Z.json` (done); 3 files touched in-scope only, harness 38/0, 7/7 mutations killed.
- Validation owner: orchestrator.

## 2026-10-19 — R-M1 + D-1 HUD widgets wired (kidney/restealth/bandage + claw)
- **Worked on:** wired the 4 filed HUD slot toggles with live consumers, in-scope 3 files only (option_tables.lua, config_presets.lua, tests/options_load_state.lua). No class/guide/engine/compat/bars/hud/practice/main/diag/contract/run/TOC/README/docs/versions touched; no git.
- **Built (widgets, option_tables.lua):** rogue R-M1 row between kick and coldblood (HUD_SLOTS order :1047-1049): hud_show_kidney/kidney Shot, hud_show_restealth/Re-stealth, hud_show_bandage/Bandage toggles + consumer comment (shortcd_wanted :442 == true, provider :1268-1332); druid D-1 claw toggle between shred and tf (HUD order :1979): hud_show_claw + consumer comment (provider :2217-2222 == true). R-T3 template comment updated (widgets now exist).
- **Built (defaults, config_presets.lua):** hud_show_kidney/restealth/bandage = false + hud_show_claw = false, each with consumer + no-visible-change comment (== true gate, nil/false hide; R-T3 template turns rogue three on). R-T3 provisional comment updated (widgets + false defaults now ship).
- **Built (pins, tests/options_load_state.lua):** §14 header R-M1/D-1 filed→wired; R-M1 block (widget type/order/get-set resolves, true/nil getter round-trip, HUD_SLOTS descriptor exists, false default + no true default, shortcd_wanted consumer exists); D-1 block (same shape for claw + descriptor + consumer). Suite 1547->1583/0.
- **Validation:** options_load 1583/0, luacheck 0/0 on 3 touched files (tree floor 2/0 held), endings preserved (tables LF, presets CRLF, tests LF). 7/7 mutations KILL on /tmp/opencode full-repo copies (M1 drop-kidney, M2 kidney-false→true, M3 drop-claw, M4 claw-false→true, M5 drop-restealth, M6 bandage-false→true, M7 claw-key-rename — every suite FAILs each, baseline PASS; copies removed).
- **Crossfire (reconcile-owned, out of scope):** full harness 36/38 — tests/hud_templates_state.lua 6 FAIL (rogue exemption pins §2 stale: now expects no widget/default, wired ships both; that file is OUT of scope, orchestrator reconciles the exemption away) + tests/hunter_state.lua 2-3 FAIL (filed IsItemInRange/CLEU probes, hunter.lua mtime after my edits — parallel-lane morph, zero options-load path). All in-scope suites green on the tree as-met.
- **Next step:** orchestrator validation + reconcile (hud_templates exemption removal) + in-client toggle check (R-T3 pick shows kidney/restealth/bandage; claw toggle shows Claw with GCD swipe).

## 2026-10-19 — [signal:done] R-M1 + D-1 wired
- Signal desks/options-wire/.signals/2026-10-19T19-06-20Z.json (done); 3 files touched in-scope only, options_load 1583/0, 7/7 mutations killed, harness 36/38 (hud_templates exemption + hunter crossfire reconcile-owned).
