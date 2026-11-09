# 20261109-1436-ab83-forever-aura-row-placement-and-size: Forever aura row placement and size

- **Tags**: aura_icons, Forever, layout, size
- **Status**: doing · 2026-11-09 14:40:26 · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c
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
the cast bar appears/disappears. If still overlapped, capture the cast frame height and
the row's anchor offsets from `A.anchor`.

## Process

- Size (2026-11-09): `aura_icons.A.DEFAULTS.size` 22 -> 27 and
  `config_presets.aura_icons_size` 22 -> 27. `A.init` migrates a profile saved at 22 to
  27 once, guarded by `aura_icons_size_27`, then leaves later explicit sizes alone.
- Placement: the row still anchors above the topmost visible swing bar; `A.anchor` now
  adds a reserved band from `ST.hunter_ui.cast_frame` and `.rapid_fire_bar` heights
  (+2 px each). The reservation is visibility-independent, so the Auto Shot cast bar
  cannot appear over an unreserved row, and no aura container is measured. The key is
  included in the re-anchor comparison.
- Tests: `aura_icons_state` 860/0 (default 27, 22->27 migration, hunter reservation and
  restore, both rows); mutants M7 reservation removed (2 fails), M8 default 22 (13
  fails); full harness 59/0; luacheck 2/0 tree floor.
- UNCONFIRMED: the live Auto Shot/cast-frame heights and the exact on-screen clearance;
  the in-client Auto Shot observation is the only close.

## Conclusion

Offline aura row sizing and hunter-stack reservation are complete. In-client verification
of the Auto Shot clearance and the 27 px edge is pending.

## Execution Log

<!-- Maintained by the script: appended by new / claim / set / release / log / close. Do not edit.
     Backfill with: progress log --id 20261109-1436-ab83-forever-aura-row-placement-and-size --note "...". -->
- 2026-11-09 14:36:34 · new · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · created
- 2026-11-09 14:36:55 · claim · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · claimed → doing
- 2026-11-09 14:40:26 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Icon edge 22->27 with one-time 22->27 migration; A.anchor reserves hunter cast_frame + rapid_fire_bar heights (+2 each) above the top bar. aura_icons_state 860/0, mutants M7/M8 killed, full 59/0. Next: reload and confirm Auto Shot cast bar clearance.
