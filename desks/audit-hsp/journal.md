# Audit HSP — Journal

## 2026-10-22 — Desk opened
- **Purpose:** RELEASE AUDIT hunter + shaman + paladin (operator: no buggy release, classes as close to perfect).
- **Scope:** classes/hunter.lua, classes/shaman.lua, classes/paladin.lua, hunter_ui.lua, nextaction.lua, nextaction_ui.lua, weave.lua + owning suites ONLY. No other classes, no main/bars/compat/swing_source/hud/options/practice/Libs/TOCs/versions/run.sh.
- **Next step:** run bench-read inputs, then audit rotation/guide correctness, swing/shot/procs/twist/weave/maelstrom, id-vs-name on every payload path, spell-known gating, leveling behavior; fix crash+wrong, pin everything.

## 2026-10-22 — [signal:done] Release audit complete, 1 wrong-behavior fixed + pinned
- **Worked on:** bench-read (journal lane table through 2026-10-22 wave, swing_hunter_bars, swing_display, HU-15/HU-22/HU-29/HU-31); full id-vs-name sweep of all 7 scope files; rotation/APL structure sampling; twist/weave/MW consumers; spell-known + leveling pins; 9 focused suites + luacheck; red-first M1'/M2/M3 on /tmp copies (removed after).
- **Current state:** F1 FIXED in classes/hunter.lua (FD/Readiness/trap SUCCEEDED sites + Steady channel fallback were id-only against the tree's own pinned R1 name-carrying rule; +17 legs in tests/hunter_state.lua, 1776 green). Everything else verified clean (see bench/audit_hsp_findings_2026-10-22.md). One open wrong-behavior: C3 hunter guide melee-gated at range (nextaction_ui should_show + mainhand-only tick gate) - fix shape documented, NOT implemented (needs operator visibility gate; no default-visible change without one).
- **Next step:** orchestrator owns validation (full run.sh) + operator in-client copy/proof; C3 awaits operator gate.
