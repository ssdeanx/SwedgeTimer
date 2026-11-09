# Brief: rogue-changelog-cuefix (2026-10-19)

## Objective
Fix stale CHANGELOG lines left by a parallel lane. Tiny docs edit.

## Problem (VERIFIED)
`CHANGELOG.md:237-239` says the ten Skeleton-lane cue keys "ship with panel
+ defaults but no class consumer yet — inert, wire-or-strip decision owed to
a class lane." The rogue-parity lane has since REMOVED those keys
(defaults + widgets + header/desc gone; absence pinned in
`tests/rogue_state.lua` §§2/3 and `tests/options_load_state.lua` §9 —
verify in-lane before editing). The paragraph now describes a state that no
longer exists.

## Scope
- `CHANGELOG.md` ONLY (the Rogue section `:203-240`). Rewrite the stale
  lines to record the removal + rationale (HUD slots + guide actions already
  cover the upkeep; duplicate bar presentation would add no signal) and
  point at the parity lane's desk (`desks/rogue-parity/`). Keep
  `[Unreleased]`. Touch nothing else.

## Rules
Factual only; no behavior claims beyond pins. No git.

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write)
This is a continuation-style fix — use the existing `desks/rogue-docs/`
desk (journal exists; append, don't reopen): verify the removal in-tree
first, edit, journal append, signal-write `done` JSON.

## Validation owner
Orchestrator: CHANGELOG Rogue section coherent with the tree (no cue-key
claims surviving anywhere but history).
