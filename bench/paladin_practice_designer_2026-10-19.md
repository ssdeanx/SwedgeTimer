# Paladin practice + designer — build report (2026-10-19)

Lane: paladin-practice-designer. Owner steers followed: (1) extend the existing
panel-icons + options-toggle flow, no new invocation; (2) paladin behavior
byte-identical, paladin options section untouched; (3) archive pattern TBC ≡
Forever verified by cmp (11 files identical); (4) designer gap closed per
archive descriptor shape; (5) branch-verified APIs; (6) build from the archives,
no interim reports; (7) enterprise quality gate.

## Archive diff (done by this lane, not the operator)

`docs/swedge/SwedgeTimer_TBC` vs `.../SwedgeTimer_Forever`: cmp-clean on
practice.lua, settings_ui.lua, core.lua, editmode.lua, hud.lua, nextaction.lua,
main.lua, import_export.lua, bar.lua, rotationtext.lua, player.lua. One pattern.

Reconcile (archive → current, paladin):

| # | Archive pattern | Current | Verdict |
|---|---|---|---|
| 1 | `/st practice` toggles (core 172-177) | main.lua:1737-1741 same seam | FOLLOWED, untouched |
| 2 | Options Start/Stop (core 948-965) | paladin section practice_toggle | FOLLOWED, untouched |
| 3 | Practice page + tabs (settings_ui 567-583) | absent | BUILT: top-level Practice group, archive tab shape |
| 4 | Simulation rows: weapon_speed, aw_includes_pot/sob, dst_enabled, queue_window (core 972-1025) | only weapon_speed; rest deferred | BUILT all 5 with live consumers |
| 5 | Boss row: bl_delay | not wired (begin_fight already takes it) | BUILT (opts passthrough) |
| 6 | Rotation/Timeline rows (defaults true/40/6/always/width/pps) | always-on, no options (pinned) | FILED: adding enable toggles would break byte-identical defaults; page carries status text |
| 7 | Feedback rows | paladin section has them | MIRRORED on the page (same keys) |
| 8 | ELEMENTS icons + success (editmode 311-539) | missing (deliberately not ported) | BUILT per archive shape |
| 9 | Live preview (editmode header 19-20) | none | FOLLOWED via design-gated force-show |
| 10 | practice_key_* persistence, position export (import_export 29-73) | session-local by design | FILED (needs new options, out of scope) |
| 11 | bar_overlays / practice_bar_mappings (core 521) | deferred stub | FILED (documented) |
| 12 | Keybind capture (practice 261-332) | exists | FOLLOWED as-is |

Macro mechanics restored exactly (archive sim_cast_buff 3198-3208): pot sets the
buff directly — no GCD, dup- and lock-guarded (activate_haste_pot 2654);
SoB casts the full seal when the GCD is free (sim_cast_seal 3026+, twist-arming
included). The current GCD-gated `cast()` path is NOT used for the pieces —
routing them through it would gcd-block the second piece.

## Files changed

- `classes/paladin.lua` (owned): `designing()` probe; seal apply/save/reset
  trio (db `seal_icons_detached/x/y`, nil = attached); twist-text trio
  (`twist_text_detached/x/y`); setup branches call the applies; design-gated
  force-show in `update_seal_icons` + the success-text updater (Retail gate
  untouched — Retail stays hidden).
- `designmode.lua` (paladin descriptors only): `seal_icons` + `success_text`
  with archive shape (key/title/get_frame/save/reset + enable_path/card/
  settings `{page="class"}` data for the future cards lane). Drag detaches,
  double-click reset re-attaches. Effects chip (virtual) NOT built:
  `design.lua` normalise requires get_frame and there is no card infra —
  filed with rationale.
- `option_tables.lua` (new top-level Practice group only, order 1.46):
  toggle (same `st.practice_ui.toggle` seam), weapon_speed mirror,
  aw_includes_pot/sob, dst_enabled, queue_window (ms), bl_delay, rotation/
  timeline status text, feedback mirrors. Paladin section byte-intact
  (my diff = one hunk, verified).
- `practice_ui.lua` (paladin session regions only): start seeds dst/bl/queue
  (nil = current defaults); `cast_key` AW macro per the archive mechanics
  above, merged out-flags, sob lane logging. `practice.lua` untouched
  (registry already complete: twist + AW combo, 8 scenarios pinned).
- `tests/paladin_state.lua` (owned): +81 pins — stub parent/GetScale
  recording; bar-children parentage; detach round-trips; design force-show
  on Era/TBC/Forever + Retail suppression; module init wiring; practice_sync
  + parse_seals branch; full Practice-page load (structure, toggle seam,
  widget defaults/round-trips).

## Verification

- `tests/paladin_state.lua` 520/520; `practice_state`, `practice_ui_state`,
  `design_state`, bars/hud/rotation/templates all PASS.
- Full harness 38 steps: 3 red, all out of scope — (a) designmode_state
  count pins 9→11 / 10→12: MY two descriptors, orchestrator to update the
  pins (mechanical); (b) options_load_state SODOPT shaman pins: sibling
  lane's unlanded expectations, no paladin content; (c) wiring_check dead
  hooks in druid/hunter/rogue/shaman class files: sibling-owned, zero
  paladin/practice_ui/designmode/option_tables findings.
- luacheck: 2 warnings / 0 errors = floor (compat/main pre-existing,
  KEEP-ruled); my 5 files 0 warnings.
- Mutations (disposable /tmp copies, restored green): seal-save invert,
  designing()=false, page-toggle cut, macro-pot invert, queue-assign cut —
  all killed by the committed pins.
- Behavioral probe (22 checks, /tmp script, real sim + real start/cast):
  seeding (dst/bl/queue incl. nil defaults), macro pot/sob/lock/GCD-busy/
  plain/cooldown paths. Caught one real issue pre-land: queue_window
  persists across sessions (`reset()` doesn't restore it), so start always
  assigns (nil → 0.4). Also confirmed the rotation lock persists across
  sessions (archive behavior, probe isolates it).

## Branch verification (read-only git show, no checkout)

- `SetPoint("CENTER", UIParent, …)`: classic_era +
  classic_anniversary `Blizzard_WowTokenUI.lua:89`; origin/forever
  `Blizzard_DelvesDifficultyPicker.lua:138`.
- `GetScale`: `SimpleRegionAPIDocumentation.lua:50` (Era/TBC), `:52` (Forever).
- `UIParent` refs: 47/47/19 hits in UIParentPanelManager per branch.
- No new combat-log / PLAYER_SWING / event touches; Retail gate reused.

## Filed (not built, with reason)

- Rotation/timeline enable + tuning options (#6): conflicts byte-identical
  defaults; always-on is the pinned shipped behavior.
- Effects chip (#8 virtual): needs registry + card infra (another lane).
- Keybind persistence, position export, bar overlays (#10/#11): need new
  options/persistence, out of scope, already documented as deferred.
- Rank-1 advice, SoD seal-maintenance slot, pull-timer source: with UI/options
  lanes per the standing filed lists.

Validation owner: orchestrator. Reconcile owed: designmode_state count pins
(9→11, 10→12) + two by_key title pins for seal_icons/success_text.
