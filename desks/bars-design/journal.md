# bars-design — Journal

## 2026-10-17 — Desk opened
- **Purpose:** bar-layer features: C3 overlay service (additive), C6 design-mode registration + snap templates, D3 pips widget, mouse-anchored positioning.
- **Scope:** bars.lua, designmode.lua (both exist — edit in place; no renames).
- **Next step:** wait for dispatch brief in bench/briefs/; harness green + mutation proofs required.

## 2026-10-17 — Build-out round 1 (brief_bars-design_2026-10-17) done
- **Worked on:** C3 zone service in bars.lua (`ST:register_zone(zone_id, draw_fn, priority)` → handle {zone_id, priority, :unregister(), :set_priority(p)}; dispatch `ST:update_zones(hand)` from onupdate_common, one table read when unused, ctx reused). D3 pips factory in bars.lua (`ST:new_pips(parent, opts)` → frame with `:set(count 0-5)` + `:glow_full(bool)`, 5 rects, gold pulse via LibCustomGlow). C6: design-target registration from the pips factory + `DM.register_template`/`DM.unregister_template` snap-to-row templates in designmode.lua, cells offered to the drag magnets; pure `D.row_boxes`/`D.normalise_template` in design.lua. Mouse anchoring in designmode.lua (class key `design_mouse_anchor`, nil = off; the dragged element centres on the cursor).
- **Current state:** my suites green — tests/design_state.lua 317 checks PASS, tests/designmode_state.lua 427 checks PASS (sandbox now loads the real bars.lua; fixture wires the anchor→bar_frame→visuals_frame chain). luacheck 0 errors; my five files contribute zero new warnings. Mutation proofs on /tmp/opencode/mut_bars-design (duplicate-zone guard, row_boxes step, mouse-anchor branch — each 4 FAILs, restored byte-identical). Full harness: 35 steps, 5 failed — all parallel-lane (smoke/druid crash, weave_state+shaman_state shaman lane, hud_state+bars_state class counts); bars_state's DRUID row includes the pips (+1 frame, +5 textures) per the brief's reconcile-later instruction. No git run.
- **Next step:** reconcile pass: confirm the druid lane's probe resolves at `ST:new_pips` (it does — bars_state DRUID counts show the widget built), prune their other two probe paths; options pass wires the `design_mouse_anchor` widget (nil = off default, documented in the bench report); in-client visual check of pips/glow/template guides still owed.

