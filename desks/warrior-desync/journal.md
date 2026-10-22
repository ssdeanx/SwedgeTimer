# warrior-desync — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build competitor-gap W1 (warrior desync indicator) from bench/competitor_gaps_2026-10-19.md §1.4 + §Warrior.
- **Scope:** ONLY classes/warrior.lua, warrior_guide.lua, tests/warrior_state.lua, tests/warrior_guide_state.lua. bars.lua/hud.lua/config+options are OUT (crossing is a defect).
- **Next step:** Implement pure sync math in warrior_guide.lua + spark widget in classes/warrior.lua + pins in both suites; W2 Battle-Shout evaluated for clean separation (else follow-up).

## 2026-10-19 — W1 built (desync spark shipped in-lane, default OFF)
- **Worked on:** Pure next-landing coincidence math in warrior_guide.lua (DESYNC_ALERT_GAP=0.3 provisional; swing_sync_gap/status/fraction, clash|clean|nil vocabulary mirroring slam_cast_safety); OH-landing spark widget in classes/warrior.lua (2px full-height marker on MH bar, green desynced-ideal / amber synced-alert per tazUI precedent, default-off `show_warrior_desync_alert ~= true`, unknown-hides, pixel+verdict churn guards, zero client reads — swing-engine stamps only); 30 pure pins in tests/warrior_guide_state.lua (§desync block); 30 widget pins in tests/warrior_state.lua (§31 + Retail profile). W2 evaluated: NOT separable — Battle Shout badge already shipped, the Commanding-suppression edge needs a new aura scan + engine input with no free guide slot (six-contract full) and no options/config room in this scope → filed as follow-up, no code.
- **Current state:** Lane suites green: warrior_state 681 checks PASS, warrior_guide_state 995 PASS; luacheck 0/0 on all 4 lane files; line endings preserved (CRLF/LF). Mutations 6/6 kill on /tmp/opencode copies (M1 toggle-gate, M2 unknown-hide→crash, M3 threshold, M4 NaN guard, M5 range clamp, M6 window fallback→error, M7 has_weapon gate). bars_state.lua WARRIOR texture pin now 35-vs-34 EXPECTED (my +1 spark texture) — reconcile owed to orchestrator, out of scope.
- **Next step:** Orchestrator: (1) reconcile bars_state WARRIOR textures 25→26 + comment; (2) options-lane defaults/widgets for show_warrior_desync_alert (nil-safe off until then); (3) in-client confirm 0.3s window + Forever/Classic swing-stamp shapes; (4) pre-existing tree failures NOT mine (hunter_state cast-read counts, wiring_check hunter dead-hooks, concurrent-lane churn in druid/hunter/rogue/luacheck — other desks mid-edit during my run).

## 2026-10-19 — [signal:done] W1 complete, follow-ups filed
- bars_state texture-count reconcile (orchestrator, out of scope)
- options defaults+widget for show_warrior_desync_alert (options lane)
- W2 Battle-Shout/Commanding suppression (needs scan+input+slot; not separable)
- in-client confirmations outstanding (see UNCONFIRMED in summary)
