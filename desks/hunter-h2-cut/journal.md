# hunter-h2-cut — Journal

## 2026-10-19 — Desk opened
- **Purpose:** CUT the hunter lust-gated Steady-spam cue (H2) per operator order (sim-faithful, best for practice); leave a clean re-enable path for a future conservative-playstyle opt-in toggle (follow-up, not this lane).
- **Scope:** ONLY classes/hunter.lua, hunter_guide.lua, tests/hunter_state.lua, tests/hunter_guide_state.lua. OUT: everything else (no option tables/config, no bars/hud/practice/smoke/run.sh/TOCs/docs/version).
- **Design:** remove the lust branch from the Steady logic so haste flows only through live synced-duration clip math; nil-safe, no default-visible change beyond the removal itself; unknown-hides; st.api.get_time(); swing-activity gating never st.is_mainline-alone.
- **Next step:** cut engine branch + gather producer in the two source files, re-pin both suites (lust cue gone, clip math covers haste; mutations must fail if reintroduced), full harness green + luacheck 2/0 + mutation proofs on /tmp/opencode copies.

## 2026-10-19 — H2 CUT landed, verified offline
- **Worked on:** removed the lust-gated Steady-spam cue. hunter_guide.lua: dropped the frozen lust_remaining input doc, the lust_window local, the 6a/6b `and not lust_window` gates (haste now flows only through live synced-duration clip math); rule-6 carries the CUT note + re-enable path. classes/hunter.lua: dropped the lust_ids set, LUST_RESCAN_INTERVAL, the gather aura-scan producer; gather site carries the CUT note + re-enable path; ISS comment reworded off the removed discipline. tests/hunter_guide_state.lua: H2 block re-pinned (windowed==windowless, 6a/3.56-3.55 boundary under window, zero/negative/absent ignored) + engine source-absence pins; gather block re-pinned (no window write, zero aura scans incl. Era) + class-module source pins. tests/hunter_state.lua: R4 block replaced with H2-CUT nil/source pins; build comment updated to ISS/Viper.
- **Current state:** in-tree suites green (hunter_state 569, hunter_guide_state 1121); full harness 37/0, luacheck 2 warnings / 0 errors (floor held); identifier grep clean in both source files (no lust_remaining/lust_window/hunter_lust/LUST_RESCAN/lust_ids/lust_supported/lust_spell_ids); CRLF preserved on both source files, LF on tests. 4/4 mutations kill with exit 1 on /tmp/opencode/mut_h2_m{1..4} copies (M1 6a-suppression back: 4 fails; M2 6b-suppression back: 3 fails; M3 producer back: 6 guide + 4 state fails; M4 id-set back: 1 source-pin fail). In-tree files untouched by mutations. Scope held: only the 4 allowed files.
- **Next step:** orchestrator validation (validation owner: orchestrator) + in-client checklist; future conservative-playstyle opt-in toggle is a follow-up, not this lane.

## 2026-10-19 — [signal:done] H2 CUT offline-complete, handed to orchestrator
- Engine + gather lust path removed, re-enable path in code comments + bench refs; pins green; 4/4 mutations kill; harness 37/0, luacheck 2/0.
