# 20261109-1436-ab83-forever-aura-row-placement-and-size: Forever aura row placement and size

- **Tags**: aura_icons, Forever, layout, size
- **Status**: doing · 2026-11-09 15:07:23 · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c
- **Created**: 2026-11-09 14:36:34 · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c

<!-- Header lines are maintained by the script, fixed order: Tags → Status → Created → Sealed.
     The `- **Tags**: …` line is inserted at the top by new --tags; omitted when there are no tags
     (category goes to the ledger and history only, never into this document).
     The `- **Sealed**: …` line is appended on close. -->

## Background

Operator 2026-11-09: the aura icon row was covering the hunter Auto Shot bar, and the
operator asked for the icons to be 5 px larger in both dimensions. The row must clear the
Auto Shot cast bar / Rapid Fire stack without measuring secret aura-container geometry.

## To Do

- In-client: after `/reload`, confirm the aura row no longer covers the Auto Shot cast bar
  or the Rapid Fire widget above the ranged bar.
- In-client: confirm the icon edge is 27 px (a profile saved at the old 22 px default is
  migrated once) and both rows still re-anchor on bar moves.
- Confirm no addon error / no secret-geometry read while the row is anchored during a pull.

## Next

`/reload`, start an Auto Shot cast in a pull and look at the cast bar and the aura rows.
Expected: the cast bar is unobstructed, the icons are 27 px, and neither row jumps when
the cast bar appears/disappears. If still overlapped, capture which frame `A.anchor`
chose (swing bar vs cast/Rapid Fire/target warning) and its `GetTop`; no height guess.

## Process

- Size (2026-11-09): `aura_icons.A.DEFAULTS.size` 22 -> 27 and
  `config_presets.aura_icons_size` 22 -> 27. `A.init` migrates a profile saved at 22 to
  27 once, guarded by `aura_icons_size_27`, then leaves later explicit sizes alone.
- Placement: the row anchors above the highest plain `GetTop` among the topmost visible
  swing bar, `ST.hunter_ui.cast_frame`, `.rapid_fire_bar` and `.target_warning`; the
  chosen widget becomes the `BOTTOM`/`TOP` anchor at `BAR_GAP`. This uses actual frame
  geometry (not a guessed cast-bar height), never measures an aura container, and moves
  the row above the Auto Shot cast bar when that widget is higher.
- Tests: `aura_icons_state` 863/0 (default 27, 22->27 migration, hunter widget anchor and
  restore, both rows); mutants M11 hunter-widget anchor ignored (2 fails), M7 reservation
  removed (2), M8 default 22 (13); full harness 59/0; luacheck 2/0 tree floor.
- UNCONFIRMED: the live hunter widget tops and the exact on-screen clearance; the
  in-client Auto Shot observation is the only close.

## Conclusion

Offline aura row sizing and actual hunter-widget anchoring are complete. In-client
verification of the Auto Shot clearance and the 27 px edge is pending.

## Execution Log

<!-- Maintained by the script: appended by new / claim / set / release / log / close. Do not edit.
     Backfill with: progress log --id 20261109-1436-ab83-forever-aura-row-placement-and-size --note "...". -->
- 2026-11-09 14:36:34 · new · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · created
- 2026-11-09 14:36:55 · claim · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · claimed → doing
- 2026-11-09 14:40:26 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Icon edge 22->27 with one-time 22->27 migration; A.anchor reserves hunter cast_frame + rapid_fire_bar heights (+2 each) above the top bar. aura_icons_state 860/0, mutants M7/M8 killed, full 59/0. Next: reload and confirm Auto Shot cast bar clearance.
- 2026-11-09 15:07:23 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Aura row now anchors to the highest plain GetTop among the topmost swing bar, hunter cast_frame, rapid_fire_bar and target_warning (no guessed height). aura_icons_state 863/0, M11 killed, full 59/0. Next: reload and confirm Auto Shot cast bar clearance.
