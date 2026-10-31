# bars-decouple — Journal

## 2026-10-28 — Desk opened (dispatch: bench/briefs/brief_bars-decouple_2026-10-28.md)
- **Purpose:** decouple the ranged hand from melee/combat state: activity-driven ranged and
  offhand visibility, offhand size = mainhand, the power-bar slot below the bottom-most melee
  bar, and the power bar following its owning bar. Write scope: `main.lua`, `bars.lua`,
  `power_bar.lua`, `config_presets.lua`, `tests/bars_state.lua`, `tests/power_bar_state.lua`.
- **Scope:** SwedgeTimer (Lua 5.1 WoW addon, no build step). Offline gate only — no in-client
  session for this lane; every in-client claim in the report is marked UNVERIFIED.
- **Operator correction received in-session:** classic_era = Era, classic_anniversary = TBC —
  do not guess a family from a branch name. Also: the reported coupling is not only visibility:
  "ranged is showing for warrior, during mh swing and mh is activating when ranged goes off".
- **Next step:** read the swing engine's reset branch (bench/bars_range_hunter_2026-10-25.md
  §4 has the real-engine proof), then land the visibility/size/power-bar changes and the
  generic shot→melee-reset guard in main.lua, and pin each one offline.

## 2026-10-28 — Landed: activity-driven ranged/offhand, offhand size, power-bar slot (brief_bars-decouple)
- **Worked on:** the four operator complaints (ranged shows while meleeing; ranged sits in the
  power slot; offhand not the mainhand's size; power bar not below the offhand), plus the
  in-session correction "ranged is showing for warrior, during mh swing and mh is activating
  when ranged goes off".
- **Landed:**
  * `main.lua` — offhand/ranged bars are activity-driven: a genuine receipt (player CLEU
    SWING_DAMAGE/SWING_MISSED `isOffHand` for the offhand; a completed Auto Shot/Shoot/Throw/
    Shoot Wand for the ranged hand; Forever engine PLAYER_SWING START) opens a window of two of
    that hand's cycles; combat state alone can no longer show either hand. The engine's own
    START is NOT a receipt (it also fires on combat-enter/equipment/cast resets). Visibility is
    split into `hand_show_condition_met` + the activity gate.
  * `main.lua` — generic shot→melee-reset guard: a shot cast arms the vendored library's
    `preventSwingReset` (event + 0.05 s poll arm); Shoot/Throw/Shoot Wand left our own
    utility-reset list, so a ranged shot no longer restarts mainhand/offhand on ANY class
    (hunters already had a class guard; warriors/rogues did not).
  * `bars.lua` — offhand renders at the mainhand's width AND height (height path added), the
    mainhand pass cascades to the offhand, saved offhand keys untouched.
  * `power_bar.lua` — the offhand ROW owns the slot below the melee stack even while that hand
    is idle/hidden; no visible melee bar hides the bar; a rect change (drag/stack) re-points it.
  * `config_presets.lua` — rogue/warrior ranged default -166 → -98 (above the melee row).
- **Current state:** GREEN. `bash tests/run.sh` 54 steps / 0 failed; luacheck 2 warnings /
  0 errors in 97 files (pre-existing pair). bars_state 962 → 1040 checks, power_bar_state
  151 → 190. 11/11 mutation proofs killed on /tmp copies (M1–M12, see the bench report §3).
  Report filed: `bench/bars_decouple_2026-10-28.md`.
- **Re-cut pins (stated in the report):** power_bar_state §5 visibility→row ownership (this
  lane invalidated it); anchor_choice labels; ONE bars_state hunter-queue tint pin that the
  parallel `hunter-tint` lane's B1 contract invalidated (flagged, their contract, my file).
- **Next step:** the orchestrator's reconcile + an in-client pass on Era/TBC: (1) warrior/rogue
  shot must not restart the MH bar; (2) ranged/offhand bars must vanish after two idle cycles;
  (3) power bar sits under the offhand row (a one-row gap when the offhand is idle — operator
  visual call); (4) hunter cast bar/range helper/Rapid Fire stop painting while the ranged bar
  is hidden (pre-existing hunter_ui frame ownership; follow-up candidate for that lane); (5) a
  `weave_range.lua` follow-up was flagged (its distance bar shows while meleeing — out of this
  lane's scope). Open operator decisions D1–D5 in the report §6.
