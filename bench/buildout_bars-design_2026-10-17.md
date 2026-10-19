# buildout_bars-design — C3 overlay service, C6 design registration + snap templates, D3 pips, mouse anchoring (build-out round 1)

Date: 2026-10-17. Desk: bars-design. Brief: `bench/briefs/brief_bars-design_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").

## 1. Changes

Writable scope held exactly: `bars.lua`, `designmode.lua`, `design.lua`, `tests/design_state.lua`, `tests/designmode_state.lua`. No other file touched; no git ops. Line endings preserved (design.lua/designmode.lua stay CRLF, the rest LF).

### bars.lua — C3: unified swing-safe overlay service (additive)
- New section after the property funcs; new file locals `LCG` (LibCustomGlow-1.0) and `floor`.
- `ST:register_zone(zone_id, draw_fn, priority) -> handle` — validates (non-empty string id, function draw_fn), rejects duplicates with `nil, err`, returns `handle = { zone_id, priority, unregister(), set_priority(p) }`. Ordering: ascending priority, ties keep registration order (monotonic seq); `set_priority` re-sorts in place; a removed handle cannot re-add itself. Registry lives at `self.zones` (`list`/`by_id`/`count`/`seq`/`ctx`).
- `ST:update_zones(hand)` — dispatch, one reused ctx table (no per-tick allocation): `hand, frame` (visuals frame), `state` (`self[hand]`), `db` (hand table), `width, height`, `time` (`st.api.get_time()`), `progress`. No-op with no zones (and no clock read).
- One additive call site in `onupdate_common`, after the class hook, before the LDB feed: `if self.zones and self.zones.count > 0 then self:update_zones(hand) end`. When nothing is registered this is one table read; existing band drawing (paladin twist band, warrior Slam band, shaman weave visuals, hunter clip tint) is untouched and no existing call site was refactored. **No production consumer registers this round** — the API ships for the later class migrations; the test suite registers consumers and pins ordering/dispatch/removal (interpretation of "this round registers new consumers only" recorded here deliberately).

### bars.lua — D3: generic pips widget (frozen contract, consumed by the druid lane)
- `ST:new_pips(parent, opts) -> frame` with `frame:set(count)` and `frame:glow_full(bool)` (colon-callable). Installed signature, verbatim:
  - `ST:new_pips(parent, opts)` — call from class code as `self:new_pips(parent, opts)` (the druid lane's existing probe `pcall(ST.new_pips, ST, parent, opts)` is already the correct colon shape).
  - `frame:set(count)` — 0..count (default count 5); clamps, rounds to the nearest pip, any non-number reads as 0 (nil-safe, never stale).
  - `frame:glow_full(on)` — arms/disarms the full-glow; the gold pulse (LibCustomGlow PixelGlow on the row frame) shows only while `set` count is full. Default disarmed.
- 5-rect row (verify_bank D3 row: the Wago feral-pack standard). Defaults: 10 px pips, 2 px gap, gold fill `{255, 210, 64, 1}`, empty = same hue at alpha 0.15, glow = the same gold. `opts`: `count, size, gap, point, x, y, color, empty_color, glow_color` (0-255 rgb + 0-1 alpha arrays), `texture`, `design` (below). Nil-safe on a bad parent (returns nil).
- The pips frame carries no per-tick cost: it is push-driven by `set`/`glow_full`; the glow pulse is library-driven.

### bars.lua — C6: design-target registration + snap-to-row template
- Every pips instance registers itself as a design target (designmode registry) unless `opts.design == false`: key `opts.design.key` or auto `pips_<n>`, title default "Combo points", `get_frame` = the row frame. Generic `save` centres the row on the dropped offsets (session-only) and generic `reset` re-anchors it to its construction point; `opts.design.save`/`reset` override both (that is the seam the druid lane uses for persisted positions).
- The row also registers a snap-to-row template (`<key>_cells`) whose `get_cells` returns the five pip cell rects in the UIParent-centre offset domain (slots reused per tick; nil while the frame has no readable centre).

### design.lua — pure additions (WoW-free, no clock)
- `D.row_boxes(count, size, gap, x, y, axis)` — stacked-layout cell rects (`{l,r,t,b}`); axis "x" (default) rightwards, "y" downwards; nil on degenerate input; fresh tables per call.
- `D.normalise_template(t)` — validates `{ id, get_cells[, border] }`, returns a copy or `nil, err`; never calls the callbacks (templates are registered before frames exist).

### designmode.lua — snap templates + mouse anchoring
- `DM.templates` registry + `DM.register_template(t)` / `DM.unregister_template(id)` (duplicate ids refused; dense list kept on removal).
- `collect_lines` now also offers every registered template's cells to the drag magnets (reach-filtered through the existing `offer_lines`; `pcall`-guarded providers; slot tables reused — no new steady-state allocation).
- Mouse anchoring (discover #17, Gnosis-style): class key `design_mouse_anchor`; when `true` the dragged element's centre follows the cursor instead of preserving the grab offset (`nil`/false = the existing grab-offset behaviour, byte-identical). Snapping still applies (grid/magnet), so Shift gives free placement at the cursor. The overlay tooltip gains one line while the mode is on.

## 2. Option default (standing-rule record for the options pass)

- Key: class table `design_mouse_anchor` (the same table `design_grid*`/`design_snap*` live in).
- `nil` = OFF (default; nothing shipped in config defaults this pass). `true` = mouse-anchored dragging in design mode. Widget should default to false; no default-visible change in any client.
- The pips widget has no user toggle of its own this round (the druid lane owns the show/hide wiring); its colours/size are per-call opts with the defaults above.

## 3. Evidence

- `lua5.1 tests/design_state.lua`: **PASS, 317 checks** (was 270 before this round; +47: row_boxes, normalise_template, C3/C6/D3 wiring pins).
- `lua5.1 tests/designmode_state.lua`: **427 checks, 0 failed** (was 283; +144: the sandbox now loads the real `bars.lua` with the fixture wired to the real accessor chain anchor -> bar_frame -> visuals_frame, plus sections 12–15: zone service, pips contract, design target + template, template snap integration + mouse anchoring).
- `luacheck .`: **0 errors**; tree total at the final run "45 warnings / 0 errors in 71 files" (the parallel lanes' files included). My five files: design.lua 0, designmode.lua 0, tests/design_state.lua 0, tests/designmode_state.lua 0, bars.lua 9 — **all 9 pre-existing lines** (41, 185, 549, 561, 694, 721, 779, 783, 792), none in the added sections.
- Full harness `bash tests/run.sh`: **35 steps, 3 failed at the final run** — none of the failures are in my files: `shaman_state.lua` (shaman lane), `hud_state.lua` (druid lane HUD slots), `bars_state.lua` (12/733, all frame/texture/fontstring **count** assertions — see §4). Earlier runs of this round also showed `smoke.lua` (druid-lane crash) and `weave_state.lua` (shaman lane) failing and then passing as those lanes progressed — the tree is shared and moving. My two suites are green in every full run of this round.
- Mutation proofs on `/tmp/opencode/mut_bars-design/` (full copy; each mutation applied, checked, restored — `cmp` confirms byte-identical restores, both suites green after):
  1. `bars.lua` `register_zone` duplicate guard (`if zones.by_id[zone_id] then` -> `if false then`): **4 FAILs** — "a duplicate zone id is rejected", "...naming the duplicate", "a rejected registration changes nothing", "the count drops". Restored.
  2. `design.lua` `row_boxes` step (`local step = size + gap` -> `local step = size`): **4 FAILs** — "the step is size + gap (second cell left)", "third cell right", "the column steps downwards", "an unknown axis reads as horizontal". Restored.
  3. `designmode.lua` mouse-anchor branch (`if db().design_mouse_anchor == true then` -> `if false then`): **4 FAILs** — the mouse-anchor on/Shift position checks. Restored.

## 4. New frame/texture counts (for the bars_state reconcile — NOT edited, per the brief)

- `bars.lua` itself: **0 frames, 0 textures, 0 fontstrings, 0 lines** at file load and during the whole init arc (the C3 registry and the design/template registrations are plain tables; nothing is created until a class calls the factory).
- The D3 pips factory: **1 frame + `count` textures (5 by default) per instance**, created only when a class calls `ST:new_pips`. The druid lane's wiring is the caller in the shared tree today.
- `bars_state.lua` current DRUID row: frames got 7 / want 6, textures got 21 / want 14, fontstrings got 9 / want 7 — of those deltas the pips contribute **+1 frame and +5 textures**; the remaining +2 textures / +2 fontstrings are the druid lane's other new widgets. PALADIN/WARRIOR/HUNTER count rows and the pre-init count are the other class lanes' new widgets. No functional bars_state check fails.
- `designmode.lua`/`design.lua`: no new frames at all (templates are tables; the overlays/guides/layer pools are unchanged).

## 5. Frozen contract confirmation (druid lane)

Installed and reported in §1: `ST:new_pips(parent, opts)` with `frame:set(count 0-5)` and `frame:glow_full(bool)`. The druid lane's probe (`pcall(ST.new_pips, ST, parent, opts)` then `widget:set`/`widget:glow_full`) resolves on the second path — the reconcile pass can prune their `st.bars.new_pips` / `st.bar.new_pips` probes. Design registration is skipped automatically in sandboxes without `st.designmode`, so the druid tests stay inert there.

## 6. UNCONFIRMED items

- **In-client visual behaviour is UNCONFIRMED**: pip fill/empty contrast and the gold pulse at 5, the pulse stopping/restarting across count changes, the template guide lines during a real drag, and mouse-anchored dragging all need a client session. The offline checks pin the calls and the maths, not the pixels.
- **UNCONFIRMED**: whether `design_mouse_anchor` (as the cursor-centre reading) is what the operator wants from discover #17; a persistent cursor-following anchor was NOT built (only the drag-time anchoring) — flagged for the options round.
- **UNCONFIRMED**: template guide-line density with many registered rows (each row offers 3 lines per cell; the reach filter bounds it, but a busy layout is untested in a client).
- No git operations performed; the tree is left with all changes in place and stated.
