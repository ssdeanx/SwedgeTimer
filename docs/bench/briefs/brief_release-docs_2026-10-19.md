# Brief: release-docs (2026-10-19)

## Objective
Per OPERATOR ORDER (no version bump this wave): move the pending entries under the already-cut version. Tiny docs lane.

## Requirement
CHANGELOG.md: retitle `[Unreleased]` → `[2.1.1]`. Then verify (read-only, NO edits to version fields): all 8 version fields read 2.1.1 (7 TOCs line 5 + main.lua line 5 — grep, report). Then coherence scan of the 2.1.1 section: no dangling promises ("owed to a lane", "ships with no consumer", future-slice language) — fix any found with pointer lines to the closing lane/buildout, or file as a one-line note in your journal if it needs a code lane.

## Scope
- CHANGELOG.md (header + coherence lines only). Version fields: VERIFY ONLY.
- Explicitly OUT: everything else. No version bump, no behavior claims.

## Rules
No git. Factual only. Publish-time dating left alone (operator gates the publish).

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write — perform via file ops)
1. bench-read: desks/journal.md reconcile section + lessons.md.
2. desk-open: desks/release-docs/ (create or resume).
3. desk-journal append + signal-write done JSON.

## Validation owner
Orchestrator: CHANGELOG heads 2.1.1, version fields verified 2.1.1×8, no dangling promises.
