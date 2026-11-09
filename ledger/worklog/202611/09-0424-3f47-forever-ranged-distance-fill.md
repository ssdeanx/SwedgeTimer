# 20261109-0424-3f47-forever-ranged-distance-fill: Forever ranged distance fill

- **Tags**: range, weave_range, Forever, exact-distance
- **Status**: doing · 2026-11-09 15:35:26 · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c
- **Created**: 2026-11-09 04:24:49 · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c

<!-- Header lines are maintained by the script, fixed order: Tags → Status → Created → Sealed.
     The `- **Tags**: …` line is inserted at the top by new --tags; omitted when there are no tags
     (category goes to the ledger and history only, never into this document).
     The `- **Sealed**: …` line is appended on close. -->

## Background

Operator 2026-11-09: the horizontal range bar stayed grey and the previous pass did not
find why. The bar must know exact yards, fill fully at melee range, and unfill with
distance; WoW Forever only; no other client behavior change. The operator also asked
whether the vendored LibRangeCheck could be guarded and used. Later the operator reported
that the bar, anchored above the top bar, covered the aura icon row and asked for it to
move below the power bar.

## To Do

- In-client: after `/reload`, confirm the bar hangs BELOW the power bar and clear of the
  aura icon row and the hunter Auto Shot/cast stack.
- In-client: target an enemy at ~5 / 10 / 20 / 35 yd and confirm `/st diag` shows
  `weave=on:yes:...:src=exact` with a real yard count; full at melee, empty at the far
  bound.
- In-client: repeat in a dungeon/instance. If `UnitPosition` is restricted there, the
  bar consumes the left indicator's own computed `helper_state` first (`src=spell`), so
  it paints the same band as the working left strip; grey is only the last resort.
- Confirm no other client calls `UnitPosition` (pinned offline by `range_source_state` §8f).

## Next

`/reload`, then read `/st diag`'s `weave=` token and check the bar's position under the
power bar. Expected `src=exact`; if `src=spell`, the bottom bar paints the same band as
the left indicator; if `src=none`, capture the three `/run` outputs (SwingTimer query,
event validity, UnitDistanceSquared). Source points:
`weave_range.lua` `bottom_anchor` / `layout`; `compat.lua` `api.UnitDistance` /
`position_distance`.

## Process

- Root cause of grey: `weave_range.lua` grey is reached only when both tiers are nil.
  Tier 1 `UnitDistanceSquared` is group-only/#noinstance (`checkedDistance` false for an
  enemy); tier 2 polls `C_SwingTimer.IsTargetWithinSwingRange`, which can be nil from
  addon code.
- Exact source found: `origin/forever:…/UnitDocumentation.lua:2714 UnitPosition` returns
  x, y, z, mapID; Blizzard's `Blizzard_TutorialTutorials.lua:985-988` computes target
  distance from `UnitPosition("target")` coordinates against a yard range. That is the
  missing exact source.
- Implemented in `compat.lua`: `position_distance` plus a Forever-gated fallback in
  `api.UnitDistance` (2D yards, same map, finite numbers, secret rejects, pcall).
  Non-Forever clients never call `UnitPosition`.
- Placement (2026-11-09): `weave_range.layout` now uses `bottom_anchor`: the shown
  `st.power_bar.frame`, else the lowest visible melee bar; `TOPLEFT` anchors to its
  `BOTTOMLEFT` at `-BAR_GAP`; width follows the anchor; top and bottom screen clamps.
  The aura row above the top bar is no longer in the same space.
- Bottom-bar in-instance fallback (2026-11-09): the LEFT indicator is the proven working
  one. `hunter_ui.range_band()` exposes its computed `helper_state` directly
  (melee / sweet_spot / ranged / out_of_range) and `weave_range` consumes that first; the
  helper's `spell_range_band()` (same Auto Shot / Wing Clip / Raptor Strike probes and
  numeric IDs) is the next fallback, then the old name-only duplicate. The state is
  cleared when the left strip hides, so the bottom cannot use stale data. `wr.update`
  tries swing -> spell and records `src=spell`. This is a band, not an invented yard
  count; the exact `UnitPosition` tier still wins when it answers.
- LRC: not used and not patched. Vendored `LibRangeCheck-2.0.lua` sets
  `modernSpellRange` true on Forever and deliberately builds no spell checkers; its
  interact ladder was removed because `CheckInteractDistance` is protected. `GetRange`
  returns nil. `Libs/` is untouched.
- Tests: `range_source_state` 161/0; `weave_bar_state` 190/0 (below-power anchor,
  hidden-power fallback, clamp, left helper_state, helper bridge); mutations M17 left
  state ignored (3 fails), M6 old above-anchor (4), M15 helper bridge ignored (1), M13
  spell band removed (8), M1 exact fallback removed (2), M5 map guard disabled (1); full
  harness 59/0; luacheck 2/0.
- UNCONFIRMED: `UnitPosition` availability/values in a live instance and the exact
  on-screen placement; the in-client test is the only close.

## Conclusion

Offline exact-yard path and the below-power placement are implemented and Forever-gated.
When exact yards are unavailable in an instance, the bar paints the same spell-probe band
as the working left indicator instead of grey. In-client verification is pending. LibRangeCheck is not a viable source as vendored and
was not modified.

## Execution Log

<!-- Maintained by the script: appended by new / claim / set / release / log / close. Do not edit.
     Backfill with: progress log --id 20261109-0424-3f47-forever-ranged-distance-fill --note "...". -->
- 2026-11-09 04:24:49 · new · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · created and claimed
- 2026-11-09 04:42:10 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Exact source implemented: UnitPosition fallback in compat.lua api.UnitDistance (2D yards, same-map/non-finite/secret guards, Forever only); range_source_state 161/0, mutants M1/M5 killed, full 59/0. LRC not used, Libs untouched. Next: in-client /st diag weave= token.
- 2026-11-09 14:40:23 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Placed below the power bar via bottom_anchor (shown power frame, else lowest visible melee bar); TOPLEFT/BOTTOMLEFT -BAR_GAP; width follows anchor; top+bottom screen clamp. weave_bar_state 170/0, mutant M6 killed, full 59/0. Next: reload + in-client bar position and /st diag src=exact.
- 2026-11-09 15:07:20 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Bottom-bar grey in instances fixed with wr.spell_band: same Auto Shot / Wing Clip / Raptor Strike api.IsSpellInRange probes as the working left helper; update tries swing then spell and records src=spell. weave_bar_state 182/0, M13 killed, full 59/0. Next: in-client src=spell should paint the band instead of --.
- 2026-11-09 15:23:49 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Bottom bar still grey because the duplicate spell probe used names/tokens; exported hunter_ui.spell_range_band() using the left helper's exact probe_in_range tokens and numeric IDs, and weave_range now calls that bridge first. weave_bar_state 186/0, M15 killed, full 59/0. Next: reload; if still --, print SwedgeTimer.hunter_ui.spell_range_band() and /st diag weave token.
- 2026-11-09 15:35:26 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Bottom bar now consumes the working LEFT indicator's computed helper_state via hunter_ui.range_band() first (melee/sweet_spot/ranged/out_of_range), then spell_range_band probes. State cleared when the left strip hides. weave_bar_state 190/0, M17 killed, full 59/0. Next: reload and print helper-band/probe-band if still --.
