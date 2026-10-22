# rogue-docs — Journal

## 2026-10-19 — Desk opened
- **Purpose:** writer lane for `bench/briefs/brief_rogue-docs_2026-10-19.md` — docs only
  (`README.md`, `TESTING.md`, `CHANGELOG.md`, `AGENTS.md` layout/class lines).
  Explicitly OUT: all code, TOCs, tests, version fields.
- **Read first:** `desks/journal.md` (lane ledger), the rogue buildouts
  (compat, options, practice) + `bench/rogue_readiness_2026-10-19.md` §5,
  `bench/lessons.md`. No re-deriving answered questions.
- **Next step:** apply the four scoped doc edits, then done signal.

## 2026-10-19 — Edits applied, ready for orchestrator validation
- **Worked on:**
  - `README.md:141` — class list now names rogue (druid, hunter, paladin, rogue,
    shaman, warrior).
  - `AGENTS.md` Layout — class-module line now `classes/{druid,hunter,paladin,rogue,shaman,warrior}.lua`
    ("only these six classes have logic"); added a `rogue_guide.lua` line beside
    `nextaction.lua` (pure engine, WoW-free, `tests/rogue_guide_state.lua`).
  - `TESTING.md` — new `### Rogue` subsection under the Era/TBC checklist: tick
    accuracy vs Yam, Era SS-window feel, SnD/Rupture upkeep, EA juggle,
    Vanish/Overkill window, Tea count probe, poison charges (UNCONFIRMED).
    Every item prefixed `(in-client)`; section header states nothing is proven offline.
  - `CHANGELOG.md` `[Unreleased]` — new `### Rogue sixth class (2026-10-19, ...)`
    section: skeleton+wiring, pure engine (206 checks, verified on disk),
    cues+provider, practice drills, compat probes incl. the OH-enchant 5th-return
    fix (cited to `bench/buildout_rogue-compat_2026-10-19.md`), options parity
    incl. the 10 inert cue keys (cited to the options buildout). Factual only;
    corrected "8 TOCs" to 7 (verified: 7 `SwedgeTimer*.toc` files on disk).
    Stays `[Unreleased]` — no version fields touched.
- **Current state:** docs-only diff; no code/TOC/test/version changes. Validation
  owner: orchestrator (class lists name rogue; TESTING rogue section with
  in-client marks; CHANGELOG factual under [Unreleased]).
- **Next step:** orchestrator validates; nothing left open in this lane.

## 2026-10-19 — Cuefix: stale cue-key paragraph rewritten
- **Brief:** `bench/briefs/brief_rogue-changelog-cuefix_2026-10-19.md` (CHANGELOG
  Rogue section only; this desk reused, not reopened).
- **Verified in-tree before editing:** zero matches for all ten keys in
  `classes/rogue.lua`, `config_presets.lua`, `option_tables.lua`; absence pinned
  in `tests/rogue_state.lua` §§2 (defaults block) and 3 (no `db.<key>` reads);
  `tests/options_load_state.lua` §9 coherent (REQUIRED/COLOUR/opt-in lists carry
  no trace; §9(c) three-way scan auto-adapts). Parity rationale read in
  `desks/rogue-parity/journal.md` (Gap 2 CLOSED by REMOVE).
- **Worked on:** `CHANGELOG.md` Rogue-section lines rewritten — the ten keys are
  now recorded as REMOVED with rationale (HUD slots + guide actions already
  cover the upkeep; duplicate bar presentation adds no signal), pointing at
  `desks/rogue-parity/`. Grep confirms no cue-key claims survive outside
  history; `[Unreleased]` kept.
- **Next step:** orchestrator validation (CHANGELOG coherent with the tree).
