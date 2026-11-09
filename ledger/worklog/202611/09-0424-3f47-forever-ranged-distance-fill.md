# 20261109-0424-3f47-forever-ranged-distance-fill: Forever ranged distance fill

- **Tags**: range, weave_range, Forever, exact-distance
- **Status**: doing · 2026-11-09 04:42:10 · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c
- **Created**: 2026-11-09 04:24:49 · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c

<!-- Header lines are maintained by the script, fixed order: Tags → Status → Created → Sealed.
     The `- **Tags**: …` line is inserted at the top by new --tags; omitted when there are no tags
     (category goes to the ledger and history only, never into this document).
     The `- **Sealed**: …` line is appended on close. -->

## Background

Operator 2026-11-09: the horizontal range bar stayed grey and the previous pass did not
find why. The bar must know exact yards, fill fully at melee range, and unfill with
distance; WoW Forever only; no other client behavior change. The operator also asked
whether the vendored LibRangeCheck could be guarded and used.

## To Do

- In-client: target an enemy at ~5 / 10 / 20 / 35 yd and confirm `/st diag` shows
  `weave=on:yes:...:src=exact` with a real yard count; the fill is full at melee and
  empty at the far bound.
- In-client: repeat in a dungeon/instance. If `UnitPosition` is restricted there,
  capture the `weave=` token and the three `/run` outputs; the native swing-range band
  is the fallback, and grey is only the last resort.
- Confirm no other client calls `UnitPosition` (pinned offline by
  `range_source_state` §8f).

## Next

Run `/st diag` in the grey moment and read the `weave=` token. Expected: `src=exact`.
If `src=none`, capture the three `/run` outputs (SwingTimer query, event validity,
UnitDistanceSquared) and report. Source points: `compat.lua` `api.UnitDistance` /
`position_distance`; `weave_range.lua:551`.

## Process

- Root cause: `weave_range.lua:589` grey is reached only when both tiers are nil. Tier 1
  `UnitDistanceSquared` is group-only/#noinstance (`checkedDistance` false for an
  enemy); tier 2 polls `C_SwingTimer.IsTargetWithinSwingRange`, which can be nil from
  addon code.
- Exact source found: `origin/forever:…/UnitDocumentation.lua:2714 UnitPosition` returns
  x, y, z, mapID; Blizzard's `Blizzard_TutorialTutorials.lua:985-988` computes target
  distance from `UnitPosition("target")` coordinates against a yard range. That is the
  missing exact source.
- Implemented in `compat.lua`: `position_distance` plus a Forever-gated fallback in
  `api.UnitDistance` (2D yards, same map, finite numbers, secret rejects, pcall).
  Non-Forever clients never call `UnitPosition`. `weave_range.lua` and
  `main.lua` consume `api.UnitDistance` unchanged.
- LRC: not used and not patched. Vendored `LibRangeCheck-2.0.lua` sets
  `modernSpellRange` true on Forever and deliberately builds no spell checkers; its
  interact ladder was removed because `CheckInteractDistance` is protected. `GetRange`
  returns nil. `Libs/` is untouched.
- Tests: `range_source_state` 161/0 (new §8); mutation M1 exact fallback removed (2
  fails), M5 map guard disabled (1 fail); full harness 59/0; luacheck 2/0 tree floor.
- UNCONFIRMED: `UnitPosition` availability/values in a live instance; the in-client test
  is the only close.

## Conclusion

Offline exact-yard path implemented and Forever-gated. The grey face remains only when
both the exact and native-band sources are silent. In-client verification is pending.
LibRangeCheck is not a viable source as vendored and was not modified.

## Execution Log

<!-- Maintained by the script: appended by new / claim / set / release / log / close. Do not edit.
     Backfill with: progress log --id 20261109-0424-3f47-forever-ranged-distance-fill --note "...". -->
- 2026-11-09 04:24:49 · new · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · created and claimed
- 2026-11-09 04:42:10 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Exact source implemented: UnitPosition fallback in compat.lua api.UnitDistance (2D yards, same-map/non-finite/secret guards, Forever only); range_source_state 161/0, mutants M1/M5 killed, full 59/0. LRC not used, Libs untouched. Next: in-client /st diag weave= token.
