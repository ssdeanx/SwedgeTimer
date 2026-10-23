# swing-nil-sweep — Journal

## 2026-10-22 — Desk opened
- **Purpose:** nil-safety sweep of the six class files only (warrior/rogue/hunter/druid/shaman/paladin); fix every UNGUARDED per-frame/per-event index chain with the file's own guard idiom.
- **Scope:** classes/{warrior,rogue,hunter,druid,shaman,paladin}.lua + owning suites for legs. Off-limits: main.lua, bars.lua, compat, hud, options, practice, run.sh, Libs, TOCs, versions.
- **Context in:** desks/journal.md lane table (release-audit wave running, rwd still open), bench/swing_display_2026-10-22.md (display contract, ensure_bar provenance), hands-up HU-15 (is_spell_known stays binary, state accessor is the seam).
- **Next step:** grep per-frame/per-event handlers in all six class files, classify GUARDED/UNGUARDED, fix, leg, mutate.

## 2026-10-22 — Nil-sweep complete, awaiting orchestrator reconcile
- **Worked on:** full per-frame/per-event nil audit of classes/{warrior,rogue,hunter,druid,shaman,paladin}.lua; 41 guard fixes (W1-W11 except W-numbering: 11 warrior sites, R1-R2, H1-H4, D1-D6, S1-S6, P1-P12); red-first NILSWEEP legs in all six owning suites (50 legs); full before-proof + 55/55 per-fix mutations on /tmp/opencode copies (removed after); luacheck 0/0 on all 12 touched files.
- **Current state:** all six suites green in-tree (warrior 2096, rogue 1134, hunter 1787, druid 1621, shaman 1083, paladin 1270). Zero behavior change when profile tables exist (guards only fire on nil). Two leg-driven corrections made during the work: druid set_bar_color frame guard moved AFTER the talent refresh (pinned by suite §11), and 5 legs strengthened to arm the guarded branch (W3/W5b/W9x/H3b/D3b/P4b) after the first red-run exposed short-circuit/untouched-frame weaknesses. Dropped one non-mutant (M-H2 half-guard removal = syntax break, covered by luacheck). 4 mutations show expected shared-entry coupling (S1→S4, P5→P9, P6→P11, W10→W9x), zero non-NILSWEEP failures anywhere.
- **Next step (orchestrator):** full run.sh + commit. Do NOT amend: tree also carries other lanes' uncommitted work (bars/main/options/practice + HSP hunter changes); my diff is classes/{6} guards + 6 tail-hunk leg sections only. UNVERIFIED: in-client behavior (Retail unknown-class profile, unbuilt-hand ticks) — needs operator copy session.
