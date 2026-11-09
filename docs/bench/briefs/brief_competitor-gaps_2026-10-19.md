# Brief: competitor-gaps (2026-10-19)

## Objective
Read-only competitor gap research: what rival addons show per class that SwedgeTimer doesn't. Ranked, implementable, cited. Feeds the next build wave — no code this lane.

## Inputs (read first, extend never re-derive)
bench/competitor_scan_2026-10-17.md, bench/rogue_deep_2026-10-19.md §3 (9-row teardown: Sno TBC WA suite, PepsiRogue, SS-timing WA, NugEnergy/ticker bars, Wick's Poisons, Wowhead lists), bench/discover_features.md, bench/verify_bank.md.

## Method
Web first for CURRENT state (enumerate BOTH catalogs: search firecrawl + search searxng, prefer SearxNG/extract pulls, small bodies, record URL + what the tool returned): WeakAuras class packs (wago.io), TellMeWhen, Gnosis, Quartz, SuperSwingTimer, ClassTimer, energy-tick trackers, poison trackers. Per class (all six): what do they surface that we don't? Each candidate: feature, classes affected, evidence/citations, implementation shape (which files would own it — no edits), delight×feasibility rank, UNCONFIRMED where in-client.

## Scope
READ-ONLY except one NEW bench file + own desk. Output: bench/competitor_gaps_2026-10-19.md (confirm absent at start; supersede-with-pointer if present).

## Rules
No code edits. No git. Per-claim CONFIRMED+citation or UNCONFIRMED. No re-searching answered questions.

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write — perform via file ops)
1. bench-read: the four input files + desks/journal.md + lessons.md.
2. desk-open: desks/competitor-gaps/ (create or resume).
3. desk-journal append + signal-write done JSON.

## Validation owner
Orchestrator: ranked gap list with evidence + owning files per item; feeds next wave.
