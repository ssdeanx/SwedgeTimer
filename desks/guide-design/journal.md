# guide-design — Journal

## 2026-10-17 — Desk opened
- **Purpose:** enterprise-grade next-action guide + designer pass — rotation-table correctness, frame wiring (icons/HOLD/RIDE/swipes), every widget registered as a design target, snap templates + mouse anchoring working.
- **Scope:** nextaction.lua, nextaction_ui.lua, design.lua, designmode.lua, tests/nextaction_state.lua, tests/design_state.lua, tests/designmode_state.lua only. tests/bars_state.lua is FORBIDDEN (reconcile wave — report counts instead).
- **Next step:** execute bench/briefs/brief_guide-design-grade_2026-10-17.md. luacheck reports zero warnings in this scope — the job is completeness, not wiring.

## 2026-10-17 — [signal:done] guide-design grade pass complete
- **Worked on:** verified rotation tables + thresholds byte-identical to the archive (docs/swedge/SwedgeTimer_TBC/rotation.lua); audited the guide frame's icon/HOLD/RIDE/swipe/rotation-text wiring (all live, no placeholder — mapping audit in the buildout report); completed the C6 handoff by registering practice_rotation + practice_timeline as delegating design targets in designmode.lua; added rotation-text resolution pins (all 8 patterns) + section-16 delegation/drag/reset/availability pins + static-wiring needles. Detail: `bench/buildout_guide-design-grade_2026-10-17.md`.
- **Evidence:** nextaction_state 443 PASS, design_state 319 PASS, designmode_state 460 checks/0 failed; luacheck 0 warnings/0 errors in scope; 2 mutation proofs on /tmp/opencode/mut_guide-design (delegation break → 11 FAILs; display-name blank → 2 FAILs; restores byte-identical via cmp). Full `bash tests/run.sh`: 35 steps, 3 failed — 12 bars_state + 4 hud_state count pins (reconcile wave, untouched per brief) + 1 toc_check Interface-number mismatch (120100 vs 120105, cross-lane toc edit, not this scope).
- **Decisions:** bar-relative sidebars (paladin JotC/CD, enemy swing) stay covered by the bar overlay — no standalone targets (rationale in report). No engine change: twist pins intact, never gated on st.is_mainline.
- **Next step:** reconcile wave (bars_state/hud_state counts) → oracle audit → CHANGELOG → owner in-client test session. UNCONFIRMED: all new visuals in-client.
