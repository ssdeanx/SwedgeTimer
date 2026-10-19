# buildout options-followup — warrior slot toggles + reset re-anchor + pips probe (2026-10-17)

Date: 2026-10-17. Desk: options. Brief: `bench/briefs/brief_options-followup_2026-10-17.md`.
Status: **done, offline-verified** (CAIRN two-proofs rule: "verified offline" below, NOT "verified in-client").

Scope held exactly: `option_tables.lua`, `config_presets.lua`, `tests/options_load_state.lua`
(`config.lua` needed no change — no profile-level keys). `hud.lua` / `bars.lua` read-only
for shape verification, untouched. No git. No lint-config. No `_` renames. Endings preserved
(`config_presets.lua` CRLF, `option_tables.lua` + suite LF — verified with `file(1)`).

## 1. Warrior arms/SoD slot toggles (hide-on-false, shipped true)

Consumer shape verified read-only first: `hud.lua:463` builds
`icon.show_key = "hud_show_" .. usable[i].key`; `hud.lua:611` hides on
`db[icon.show_key] == false` — the exact `hud_show_tf` precedent. Shipping `true` preserves
the current always-drawn rendering (nil behaves identically), so no default-visible change.

| Key | Default (`config_presets.lua` WARRIOR) | Widget (WARRIOR HUD group) | Consumer read |
|---|---|---|---|
| `hud_show_rend` | `true` | Rend toggle, 8.44 | `hud_slot_rend` (warrior.lua:2392) → `icon_should_show` |
| `hud_show_ms` | `true` | Mortal Strike toggle, 8.45 | `hud_slot_ms` (warrior.lua:2393) → `icon_should_show` |
| `hud_show_bladestorm` | `true` | Bladestorm toggle, 8.46 | `hud_slot_bladestorm` (warrior.lua:2394) → `icon_should_show` |
| `hud_show_raging_blow` | `true` | Raging Blow toggle, 8.47 | `hud_slot_raging` (warrior.lua:2396) → `icon_should_show` |

Toggles appended after `ww`, trinkets stay last (matching the HUD_SLOTS set shapes where
trinkets close the row). Slot descs mirror the sibling copy (rotational slots carry the GCD
swipe note like slam/hs; cooldown slots are plain like bt/ww). The WARRIOR HUD comment now
names all four family sets (was "both"). Suite §4 warrior slot list extended to the full
13-slot union; the ≥8.0 order scan stays collision-free (8.41–8.53 in 0.01 steps).

## 2. practice_reset_position re-anchor fix

**Was:** the execute func zeroed `practice_panel_x/y` without re-anchoring — the panel only
moved on the next manual drag or reload (practice-grade §1-G4 flagged, out of their scope).
**Fix (`option_tables.lua`, paladin panel §7.36, additive):** after the zero writes, route
through the panel's own position applier —
`if st.practice_ui and st.practice_ui.apply_settings then st.practice_ui.apply_settings(ST) end`
— mirroring the `update_result_font` guard in the same section (option_tables.lua:2027).
`apply_settings` (practice_ui.lua:3084) re-reads the offsets and defers internally under
combat lockdown, so the button visibly works out of combat and degrades to a deferred apply
in combat. Nil-safe: with no `practice_ui` loaded the offsets still zero.

## 3. Pips x/y probe — NOT wired (no consumer), factory spec for the bars follow-up

- Factory **does** consume position: `bars.lua:997-1000` (`point`/`tonumber(opts.x)`/
  `tonumber(opts.y)` → `SetPoint`). Probe pins added (§8c).
- The only call site (`classes/druid.lua:1115-1120`) passes **literals**
  (`point = "BOTTOMLEFT"`, `x = 0`, `y = -DRUID_PIPS_BOTTOM_GAP`) plus
  `design = { key = "druid_pips", title = "Combo Points" }` with **no** `save`/`reset`
  seam — so the row drops session-only and resets to its construction anchor.
- `druid_pips_x` / `druid_pips_y` appear **nowhere** repo-wide (no db key, no default, no
  widget) — confirmed nil hits in `classes/druid.lua`, `config_presets.lua`,
  `option_tables.lua` and pinned by §8c absence checks. Wiring widgets/defaults now would be
  options without a consumer — correctly left unwired per the brief.
- **Factory-side spec for a bars follow-up:** to make pips positions sticky, extend the
  druid call site to pass `design = { key, title, save = function(sx, sy) ... end,
  reset = function() ... end }` closing over two new class-db keys (e.g.
  `druid_pips_x`/`druid_pips_y`, owner-gated nil-off or default-0 like
  `practice_panel_x/y`), following the `ST:new_pips` `opts.design` contract
  (bars.lua:1076-1100: custom `save`/`reset`, else session-only drop + construction-point
  reset). The options side (widgets + defaults + pins) belongs to a follow-up once the
  caller seam exists. UNCONFIRMED: design-mode drop/reset behaviour of the pips row
  in-client.

## 4. Evidence

- `lua5.1 tests/options_load_state.lua` → **586 checks, 0 failed** (was 537; +12 from the
  §4 warrior slot union, +37 new §8: hide-on-false consumer shape, per-key get/set
  resolution + getter key reads, reset source + runtime + nil-safe runtime, pips
  factory/call-site/default/widget absence pins).
- `bash tests/run.sh` → **35 steps, 0 failed** (brief-expected 35/0). One transient:
  a mid-pass re-run showed 2 `hud_state.lua` druid-width fails while the parallel
  hud-reflow lane was mid-edit (`hud.lua` + `tests/hud_state.lua` mtimes after this
  pass's writes, both out of scope); the lane landed and the final run is 35/0.
- Scope luacheck: **0 warnings / 0 errors** in the 3 files + suite. Repo-wide: 0 errors /
  2 warnings (untouched lanes' files).
- **Mutation proofs on `/tmp/opencode/mut_of/`** (full-tree copy; each applied, checked,
  restored `cmp`-clean): M1 `hud_show_rend = true` → `false` → **1 FAIL**
  ("ships true in the defaults"); M2 reset `apply_settings` call removed → **2 FAILs**
  (source pin + "re-anchors through apply_settings"). Restored tree `cmp`-clean, 586/0.

## 5. UNCONFIRMED (in-client list)

- Rendered warrior HUD toggles + hidden-slot behaviour on arms/SoD clients (the suite pins
  the tree, not the pixels); TF/Berserk-style presentation parity assumed from the shared
  `icon_should_show` path.
- Reset button visibly moves the practice panel in-client (offline: offsets zero +
  applier invoked); combat-lockdown deferral path untested in-client.
- Everything in §3's factory spec; the pips row's design-mode drop/reset in-client.
- The recommended-true defaults from prior passes remain owner-gated (unchanged).
