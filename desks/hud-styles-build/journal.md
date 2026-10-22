# hud-styles-build — Journal

## 2026-10-19 — Desk opened
- **Purpose:** HUD finishing touches from the four style-gallery shortlists
  (warrior/rogue/druid/paladin _2026-10-19): apply shortlist items to HUD
  slots + templates, or file with reason. Hunter/shaman already mapped, untouched.
- **Scope:** classes/rogue.lua, classes/druid.lua, classes/paladin.lua,
  classes/warrior.lua (HUD slots/tints only), config_presets.lua (templates),
  option_tables.lua (template/panel entries), tests/rogue_state.lua,
  tests/druid_state.lua, tests/paladin_state.lua, tests/warrior_state.lua,
  tests/hud_state.lua, tests/hud_templates_state.lua, tests/options_load_state.lua.
- **Priors read:** desks/journal.md (ledger), workshop.md, CAIRN.md, hands-up.md,
  all four *_styles_2026-10-19.md, bench/hud_templates_2026-10-19.md,
  bench/designer_templates_2026-10-19.md.
- **Next step:** apply edits (paladin 5-slot template/default/widget expansion;
  druid claw template coverage; warrior sunder template/default/widget +
  hamstring widget G1 close), then harness + luacheck + mutations on
  /tmp/opencode copies.

## 2026-10-19 — Build landed, harness 38/0, 7/7 mutations kill
- **Worked on:** applied the four shortlists to HUD slots + templates; no guide
  rule touched; rogue/druid/paladin/warrior class files unchanged except one
  stale ownership comment (paladin.lua:3384).
- **Paladin (styles §0/S2/S8/S10):** SoD-native slots extend P-T2, not P-T1.
  config_presets: 5 defaults ship true + all 3 templates expanded 7→12
  (twist_core new=false, full_ret new=true, minimal new=false). option_tables:
  5 toggles at 8.48-8.52. Pins: hud_templates §1/§2/§3, hud_state §12,
  options WIRED P-M2 (converts the old FILED P-M2 tripwire).
- **Druid (styles shortlist #3, Meatslab D3):** D-T1 stays 4-icon minimal.
  config_presets: claw into all 3 templates (bleed_core false, full_feral true,
  bear_guard false) 10→11. Default stays false + widget pre-exists (D-1);
  hud_templates ship_false pin covers it. D-T3 stays provisional (no bear-tank
  source — gallery-filed, no copy change).
- **Warrior (styles shortlist #2, family-full):** config_presets: hud_show_sunder
  = true + sunder into all 3 templates 14→15 (W-T2 true, W-T1/W-T3 false).
  option_tables: hamstring + sunder widgets (closes designer G1). Pins:
  hud_templates §1/§2, options §4 (13→15) + WIRED W-M1 (converts FILED W-M1).
  Bars-side borrows (rage number, queue highlight) filed: bars.lua out of scope.
- **Rogue (styles shortlist):** zero code edits — every item already applied
  (R-T1 anchor unchanged, Sno grammar = R-T3 + stacked glow, Redtuzk = poison
  text, Era cue = red window + SnD tri-state) or filed watch (thresholds,
  Comfy/Minimal in-client checks). Reconciled the STALE rogue exemption in
  hud_templates_state: kidney/restealth/bandage now ship_false (false default
  + widget, landed by options-widgets) — baseline was red on exactly this.
- **Filed with reason (no code):** druid TBC Cat-rotation cross-check (guide
  frozen); warrior W1 shout/Sunder-bars/AQS-glow/Afenar (engine/bars/debuff
  domains); paladin S1/S3/S5 band/tick language (bars), S4 positioning
  (differentiators, no borrow), S10 SoD P-T1 extension (no cited slot set —
  not invented); rogue S6/S7 watch items; all in-client side-by-sides owed to
  the TESTING.md session (pixel geometry UNCONFIRMED throughout).
- **Validation (all verified offline, none of it in-client):** harness 38/0
  (baseline was 37/38 — pre-existing rogue-exemption red from options-widgets
  crossfire, reconciled here); luacheck 2/0 floor, 0/0 on the 6 touched files;
  7/7 mutations kill on /tmp/opencode copies (M1 sunder-cover, M2 sunder-default,
  M3 soc-widget, M4 claw-cover, M5 claw-default, M6 hamstring-widget, M7 kidney-default).
- **Incident (honest record):** first mutation round wrote through `cp -as`
  symlinks into the live tree (3 spots: soc/hamstring widgets, kidney default).
  Repaired with exact re-insertion, re-verified (grep counts + harness 38/0),
  redid M3/M6/M7 on real files — all kill. Copies removed.
- **Current state:** tree holds 38/0. Nothing further provable offline.
- **Next step:** orchestrator validation, then the final audit goes out.
