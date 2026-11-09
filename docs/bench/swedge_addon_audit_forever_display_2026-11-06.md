# SwedgeTimer Forever display audit — 2026-11-06

Baseline: HEAD 7207f80; all seven TOCs and main.lua at 2.1.8 (release-version desk). Offline harness: 57 steps, 0 failed. luacheck: 2 warnings / 0 errors (hunter_ui.lua:135-136 unused CAST_ZONE_SAFE/CAST_ZONE_UNSAFE). No product code edited; no paths under Libs/ touched.

## Auto Shot: firing vs display
- Firing evidence: AUTO_SHOT_SPELL_ID = 75 in main.lua; maybe_drive_ranged_fallback; START_AUTOREPEAT_SPELL / STOP_AUTOREPEAT_SPELL handlers; is_auto_shot checks; completed shot calls note_hand_activity("ranged", nil, "shot").
- Display/activity: ranged bar is activity-gated. hand_is_in_use("ranged") is true only when auto_repeat_active == true OR a shot receipt exists inside hand_activity_window (2 cycles, clamped 1.5-8s). handle_bar_visibility hides ranged with reason "idle" when the gate fails.
- Finding: Auto Shot can fire while the ranged bar stays hidden when auto-repeat is not armed and no recent shot receipt exists. This is intended gating, but it explains "firing works, bar not visible" reports. Forever notes offhand/ranged activity from PLAYER_SWING START when swing_engine == "forever-source"; ranged also gets shot receipts.

## Horizontal range bar
- weave_range.lua uses a separate, never-hidden driver frame (WeaveRangeDriver) with guarded poll(). The bar frame itself is hidden and cannot own the poll.
- update() hides for: disabled settings, no target, non-attackable target, non-numeric UnitDistance, or enable gates. Default enable is hunter-only via ST.weave_range_default_enabled; other classes default off.
- Layout reserves space above the bar via reserved_above() (cast bar + rapid fire bar) and anchors above the ranged bar; falls back to UIParent center when no ranged bar.
- Finding: driver availability is not the likely cause of a missing bar; check enable default, target/distance gates, and reserved-space/anchor conditions.

## Primary power bar
- power_bar.lua resolve() reads UnitPowerType, UnitPower, and UnitPowerMax through compat. On Forever, UnitPower and UnitPowerMax are SecretWhen...Restricted = true; UnitPowerType is not secret.
- compat.lua degrades secret UnitPower/UnitPowerMax to nil and secret UnitPowerType to nil. power_bar then reports why = "no-value" or "no-type" and hides.
- API evidence supports current nil degradation. Secret values cannot be used in Lua arithmetic/comparisons, so passthrough is not supported by evidence or tests. Keep degradation unless a secret-safe paint path is designed and tested.

## Performance
- Root-module OnUpdate sites: weave_range.lua driver; enemy_swing.lua frame; designmode.lua layer/drag; rotationtext.lua driver; practice_ui.lua driver/frame; power_bar.lua driver; hunter_ui.lua anchor tick; hud.lua driver; nextaction_ui.lua frame; main.lua per-hand bar frames.
- Guarded poll/quarantine patterns exist in weave_range, power_bar, and hunter_ui; hidden frames do not run OnUpdate, so never-hidden drivers are used where visibility gates exist.
- No edits under Libs/. luacheck remains 2 warnings / 0 errors.

## Release readiness
- Current synchronized version: 2.1.8 across all seven TOCs and main.lua. Archived docs/swedge and Libs not touched.
- If a next minor release is approved, target 2.2.0 and bump all seven TOCs plus main.lua together; tests currently 57/0.

## Mnemon
- Deferred: no writable memory source/action was exposed in this delegated session. Findings are recorded here and in the final audit answer.
