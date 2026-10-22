# Practice Gamification — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build the practice-gamification foundation (operator order: practice is a
  minigame — level up, XP, saved scores, stats). Step 1 of the design spec
  (`bench/practice_gamification_design_2026-10-19.md` §7): pure modules + persistence
  shape + defaults + unit tests. No UI in this lane.
- **Scope (this session, step 1 only):**
  - NEW `practice_progress.lua` — pure progression (XP, level curve, prestige, mastery,
    streaks, daily cap, achievement predicates) + persistence schema/migrate/validate.
  - NEW `practice_stats.lua` — pure lifetime stats, per-drill table, 50-session history
    ring, snapshot + JSON export payload.
  - NEW `tests/practice_progress_state.lua`, NEW `tests/practice_stats_state.lua`.
  - `config_presets.lua` (new practice progress/stats defaults only), `tests/run.sh`
    (2 new steps), the 7 flavor TOCs (2 new module lines, after `practice.lua`, before
    `practice_ui.lua`).
  - Out of scope: `practice.lua`, `practice_ui.lua`, class files, guides, HUD, bars,
    options UI, `option_tables.lua`, compat, main, diag, designmode, guide_contract,
    versions, README, CHANGELOG, docs, git, lint config.
- **Next step:** read the spec + the existing scoring model (`st.practice.GRADE_POINTS`,
  `SCORE_WINDOW`), then design the two pure modules and their persistence shape.

## 2026-10-19 — Foundation built: 2 pure modules + persistence + defaults + 2 suites
- **Worked on:** NEW `practice_progress.lua` (XP per attempt from `GRADE_POINTS`, the
  `floor(100 * n^1.35)` level curve with the 50-level cap → renown, per-class + account
  scopes, per-drill mastery: recency-weighted accuracy over the last 100 attempts with a
  30-attempt half-life, the 20-attempt volume gate → Unranked, and the Bronze/Silver/Gold/
  Platinum tiers; the session / best / daily streaks, where a missed day FREEZES the daily
  streak; the daily per-drill XP cap at 3× the drill's median attempt XP) and NEW
  `practice_stats.lua` (runs / attempts / hits / misses, accuracy lifetime + rolling-20 +
  last session, best session score, best grade, best S-run, time active from an injected
  duration, the per-drill attempt table, the bounded 50-session history ring, the snapshot
  and the JSON export payload). Both are WoW-free: no os.time, no randomness, no clock read,
  dates/durations injected, every aggregate guarded (NaN / infinity / type → zero).
  The generic unlock registry (operator order 2026-10-19): `P.UNLOCKS` + `register_unlock`
  with the kinds achievement / cosmetic / **drill_variant**, the requirement forms level /
  achievement / predicate, and per-scope flags. A drill variant MUST name the NEW scenario
  it grants; an unlock never touches a drill (pinned). Persistence: `profile.practice` with
  `schema_version`, `migrate()` and `validate()` (repair, never throw, never mutate the
  input, never touch a sibling saved variable, a newer blob is left alone).
  `config_presets.lua` gained `ST.PRACTICE_DEFAULTS` (new keys only), `tests/run.sh` gained
  the 2 steps, and all 7 flavour TOCs gained the 2 module lines
  (`practice.lua` → `practice_stats.lua` → `practice_progress.lua` → … → `practice_ui.lua`).
- **Current state:** `tests/practice_progress_state.lua` 390 checks PASS ·
  `tests/practice_stats_state.lua` 415 checks PASS · `tests/toc_check.lua` PASS (the disk
  completeness check pins the two new modules on every flavour) · luacheck 0 warnings /
  0 errors in all 5 touched files (the repo total moved 2 → 3 warnings; the extra one is in
  `main.lua` + `tests/main_init_state.lua`, another lane's files) · **mutation proofs 51/51
  killed** on `/tmp/opencode/practice-gamification-mut` (script
  `/tmp/opencode/practice_gamification_mutations.py`, one mutant per rule) · full harness
  **40 steps, 0 failed**. Two reds appeared mid-lane (`diag_state` 1, `main_init_state` 2)
  and cleared by themselves: they were another lane's in-flight rewrites of `diag.lua`
  (19:38), `main.lua` (19:39) and `bars.lua` (19:40) — neither suite loads the practice
  modules. Bench artifact: `bench/buildout_practice_gamification_foundation_2026-10-19.md`.
- **Next step:** orchestrator validation (owns Done). The hook lane (spec §7 step 2) wires
  `db.profile.practice`: `config.lua` owns `ST.defaults` and needs
  `practice = ST.PRACTICE_DEFAULTS` inside `ST.defaults.profile` (config.lua was outside
  this lane's scope, so it was NOT touched). In-client behaviour of everything new is
  UNCONFIRMED, like every offline pin.

## 2026-10-19 — [signal:done] Foundation lane complete, 51/51 mutations killed
- Both pure modules + both suites green (390 / 415 checks), TOC coverage green, full harness
  40 steps / 0 failed, luacheck clean in every touched file; the two mid-lane harness reds
  were another lane's in-flight edits (evidence in the bench artifact).
