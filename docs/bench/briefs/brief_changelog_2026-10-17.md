# Brief: changelog — release notes + doc matrix through the full round (N1 included)
Date: 2026-10-17. Orchestrator-issued.

## Read first
desks/changelog/journal.md · desks/journal.md (decisions + full lane table) · bench/buildout_*_2026-10-17.md (every round report — changes sections are the source of truth) · bench/oracle_audit_2026-10-17.md (verdict + checklist) · bench/buildout_oracle-fixes_2026-10-17.md · bench/buildout_secret-hole_2026-10-17.md · CHANGELOG.md (existing shape) · README.md (~line 66 Retail row) · TESTING.md (~lines 16, 94 Retail rows) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
CHANGELOG.md, README.md, TESTING.md. NOTHING else.

## Task
1. **CHANGELOG [Unreleased]:** entries through the entire round — build-out 10 lanes (features per class + C2/C3/C4/C6 + enemy-swing), shaman-weave round 2, options (27 toggles + 4 warrior + reset + pips probe), enterprise-grade wave (5), wire-not-strip (45→2 warnings), reconcile, 120105 matrix, hud-reflow, oracle R1–R4 + N2/N3, secret-hole closure. Mark every in-client-unverified item UNCONFIRMED (do not claim in-client behavior). Follow the file's existing entry shape; never rewrite released history — append under [Unreleased] only.
2. **N1 doc bump:** README Retail row + TESTING.md Retail rows → `12.1.x (120100, 120105)`. CHANGELOG:8 only if it is a living statement — read it first; if it is a released-history line, leave it and note why.
3. **TESTING.md:** confirm the in-client checklist covers the oracle-audit §checklist items (add missing rows; do not remove existing ones).

## Rules
Docs only. No git. Endings preserved. No behavior claims beyond "verified offline" + owner checklist pointers.

## Validation
`bash tests/run.sh` untouched-green not required (docs only) — but run `lua5.1 tests/toc_check.lua` to confirm no doc edit broke the tree (it shouldn't; docs aren't code — skip if N/A, state why). Re-read your three files for internal consistency (versions match AGENTS.md matrix + tocs).

## Deliverables
Docs · desks/changelog/journal.md entry · signal JSON · bench/buildout_changelog_2026-10-17.md (sections added, N1 lines changed, consistency statement). Final reply ≤6 lines. NEVER run git.
