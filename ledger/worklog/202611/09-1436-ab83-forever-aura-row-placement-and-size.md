# 20261109-1436-ab83-forever-aura-row-placement-and-size: Forever aura row placement and size

- **Tags**: aura_icons, Forever, layout, size
- **Status**: doing · 2026-11-09 15:35:24 · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c
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

- In-client: after `/reload`, confirm the aura row clears the visible Auto Shot cast bar
  and sits at least 15 px above the ranged bar when no cast is visible.
- In-client: confirm the icon edge is 27 px (a profile saved at the old 22 px default is
  migrated once) and both rows still re-anchor on bar moves.
- Confirm no addon error / no secret-geometry read while the row is anchored during a pull.

## Next

`/reload`, start an Auto Shot cast in a pull and look at the cast bar and the aura rows.
Expected: the cast bar is unobstructed while casting; when idle the row is 15 px above
the ranged bar. If still overlapped, run the `aura-anchor` diagnostic and report the
chosen frame, `bar_top`, and 12/55 or 15/58 offsets; no height guess.

## Process

- Size (2026-11-09): `aura_icons.A.DEFAULTS.size` 22 -> 27 and
  `config_presets.aura_icons_size` 22 -> 27. `A.init` migrates a profile saved at 22 to
  27 once, guarded by `aura_icons_size_27`, then leaves later explicit sizes alone.
- Placement (operator rule, 2026-11-09): if the hunter cast bar is SHOWN, the row anchors
  above the highest visible hunter widget (`cast_frame` / `rapid_fire_bar` /
  `target_warning`) at `BAR_GAP + HUNTER_GAP` (6 + 6 = 12 px). If no cast widget is
  visible, the row sits `HUNTER_RANGED_GAP` (15 px) above the ranged bar. Hidden cast
  frames are ignored, so an invisible cast bar cannot reserve a misleading position.
  This uses plain `IsShown`/`GetTop` (never aura-container geometry).
- Tests: `aura_icons_state` 865/0 (default 27, 22->27 migration, visible-cast 12/55 px,
  hidden-cast 15/58 px, both rows); mutants M16 hidden cast used (2 fails), M18 15 px
  fallback shrunk (4), M14 hunter clearance removed (2), M11 hunter-widget anchor ignored
  (2), M7 reservation removed (2), M8 default 22 (13); full harness 59/0; luacheck 2/0.
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
- 2026-11-09 15:23:47 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Screenshot crop proved the row was correctly above the cast bar but only ~2 px clear. Added A.HUNTER_GAP=6 on top of BAR_GAP=6 for hunter-widget anchors; 12/55 px offsets. aura_icons_state 863/0, M14 killed, full 59/0. Next: reload and re-check the Auto Shot edge.
- 2026-11-09 15:35:24 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Operator rule implemented exactly: visible Auto Shot cast bar -> aura row above the highest visible cast/rapid/target-warning widget at 12 px; no visible cast -> 15 px above ranged. Hidden cast frames ignored. aura_icons_state 865/0, M16/M18 killed, full 59/0. Next: reload and run aura-anchor diagnostic if still touching.
