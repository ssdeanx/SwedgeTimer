# Brief: rogue-docs (2026-10-19)

## Objective
Docs parity for the shipped rogue work. Writer lane, docs only.

## Gaps (VERIFIED)
- `README.md:141` lists `classes/` as `(druid, hunter, paladin, shaman,
  warrior)` — rogue shipped. Update the class list (read the section
  in-lane; touch only rogue-accurate lines).
- `TESTING.md` has zero rogue mentions (grep-verified) while the owner
  in-client session is next. Add a rogue checklist section mirroring the
  existing class sections' structure (read them in-lane): tick accuracy vs
  Yam overlay, Era SS-window feel, SnD/Rupture upkeep, EA juggle,
  Vanish/Overkill window, Tea count probe, poison charges (UNCONFIRMED —
  mark it so). Every item marked in-client (two-proofs rule: nothing here
  is proven by offline pins).
- `CHANGELOG.md` `[Unreleased]`: add rogue entries (skeleton+wiring, pure
  engine, cues+provider, practice drills, compat probes incl. the
  OH-enchant fix, options panel). Factual only — cite bench buildouts, no
  unverified behavior claims. Stays `[Unreleased]` (publish-time decision).
- `AGENTS.md` Layout section: update the class-module list line
  (`classes/{druid,hunter,paladin,shaman,warrior}.lua`) to include rogue,
  plus the root `rogue_guide.lua` alongside the other `*_guide.lua`
  entries. Read the section in-lane; minimal diff.

## Scope
- `README.md`, `TESTING.md`, `CHANGELOG.md`, `AGENTS.md` (Layout/classes
  lines only). Explicitly OUT: all code, TOCs, tests, version fields.

## Rules
No git. Behavior-accurate only: every claim traceable to a pin or marked
UNCONFIRMED/in-client. No default-visible or behavior statements beyond
what the buildouts prove.

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write)
1. bench-read: `desks/journal.md`, the rogue bench buildouts
   (`bench/buildout_rogue-compat_2026-10-19.md`,
   `bench/buildout_rogue-options_2026-10-19.md`,
   `bench/buildout_rogue-practice_2026-10-19.md`,
   `bench/rogue_readiness_2026-10-19.md` §5), `bench/lessons.md`.
2. desk-open: `desks/rogue-docs/` (create or resume).
3. desk-journal append + signal-write `done` JSON.

## Validation owner
Orchestrator: class lists name rogue; TESTING has a rogue section with
in-client marks; CHANGELOG entries factual under [Unreleased].
