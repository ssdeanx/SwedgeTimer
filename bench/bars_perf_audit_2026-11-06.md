# Bar performance audit — WoW Forever (2026-11-06)

## Scope
Read-only audit of the per-frame bar path on the WoW Forever (Mainline-code, Interface 16001) client. No code changes beyond the companion version bump.

## Findings
- OnUpdate is installed on each built hand's bar_frame (main.lua ST:bring_up_hand) and runs every client frame for mainhand/offhand/ranged, including hidden/disabled hands that are built. Lazy bars (HU-22) limit builds to enabled + in-use hands, so the per-frame cost scales with built hands only.
- onupdate_common (bars.lua) calls st.api.get_time() once per tick; compat re-anchors the precise clock against GetTime() only when drift exceeds 0.05s, so the common case is two cheap clock reads. Acceptable.
- Each tick performs one SetWidth/SetTexCoord on the fill plus optional spark/flash/gcd-underlay work; spark and flash branches are gated on db.show_spark and IsShown() respectively, so idle bars pay only the fill writes and set_bar_texts.
- set_bar_texts runs every tick and formats speed/timer strings; cached _last_rounded_* fields avoid repeat string.format except when the rounded value changes. Range string is rebuilt only when target_min/max change. Good.
- Class on_bar_update hook runs every tick inside st.guard.run (paladin twist band, shaman weave visuals, hunter melee stack). Hunter apply_melee_stack re-checks anchor points each tick but only calls configure_bar_size_and_positions when width differs by >0.5 px; anchor re-point only when not already pinned. Good.
- Forever uses swing_source (PLAYER_SWING) which fires callbacks on swings; bars animate from those cycles. No extra per-frame API reads beyond UnitAttackSpeed on swing events. No combat-log polling.
- Potential cost: class hook + zones + ldb all run on mainhand tick every frame; hunter range HUD (ui.update) runs on ranged tick every frame when visible. These are the dominant per-frame consumers on Forever and are the natural targets for a future throttle if profiling shows need.
- No mutation/fix applied in this audit pass; version bump only.

## Version bump
2.1.8 -> 2.2.0 across all 7 TOC variants + main.lua (local version). Tests: 57/0 pass.
