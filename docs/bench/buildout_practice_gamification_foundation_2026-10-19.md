---
name: practice-gamification-foundation
date: 2026-10-19
lane: practice-gamification
scope: pure modules + persistence + defaults + unit tests (design spec §7 step 1). No UI.
---

# Practice gamification — foundation lane (spec §7 step 1)

Design source: `bench/practice_gamification_design_2026-10-19.md` (§2 progression, §3 stats,
§4 achievements, §5 rewards, §6 engineering). Operator order 2026-10-19 added to the brief:
the unlock registry must carry **two** kinds — cosmetic (themes, popup styles, titles) AND
level-gated harder **drill variants** (new scenarios).

## What landed (files changed by this lane)

| File | Change |
| :--- | :--- |
| `practice_progress.lua` | NEW — pure progression + unlock registry + persistence |
| `practice_stats.lua` | NEW — pure aggregates + history + snapshot/export |
| `tests/practice_progress_state.lua` | NEW — 387 checks |
| `tests/practice_stats_state.lua` | NEW — 410 checks |
| `config_presets.lua` | NEW `ST.PRACTICE_DEFAULTS` (the `profile.practice` shape) — new keys only |
| `tests/run.sh` | +2 steps (the registry is explicit per file) |
| the 7 flavour TOCs | +2 lines each: `practice.lua` → `practice_stats.lua` → `practice_progress.lua` → … → `practice_ui.lua` |

No git, no lint-config change, no version/README/CHANGELOG/docs touch. `practice.lua`,
`practice_ui.lua`, class files, guides, HUD, bars, options, `option_tables.lua`, compat,
main, diag, designmode, `guide_contract` untouched.

## Module contracts (the next lanes need these)

### `practice_progress.lua` (loads SECOND, after `practice_stats.lua`)

- `P.new_state()` — `{ version, classes = {}, global = { daily_streak, last_session_day, unlocks } }`
- `P.new_session()` — `{ attempts, hits, streak, best_streak, xp }` (caller-owned, one per session)
- `P.record_attempt(progress, session, class_key, drill_id, grade, day)` → mutates both, returns progress
- `P.end_session(progress, session, class_key, day, opts)` → `{ attempts, xp_earned, bonus_xp, leveled_up, level, renown, daily_streak }`
  - `opts.completion_bonus_factor` scales the +25 bonus (default 1.0)
- `P.xp_for_level(n)` / `P.xp_total_for_level(L)` / `P.level_info(xp)` — `floor(100 * n^1.35)`, cap 50 → renown
- `P.mastery(drill)` → `{ mastery_pct, tier, tier_name, ranked, attempts, hits }`
- `P.drill_daily_cap(drill)` — 3× the drill's median attempt XP (nil when no attempt yet)
- `P.scope_xp(progress, scope_key)` — a class's XP; the account scope is the SUM over the classes (derived, never stored twice)
- `P.scope_best_streak` / `P.scope_daily_streak` / `P.unlocked_ids` / `P.is_unlocked`
- `P.profile_snapshot(progress, stats_snapshot, scope_key)` — the merged read model
- `P.export_payload(progress)` — JSON-safe

### The generic unlock registry (operator order)

- `P.UNLOCKS` — id → definition `{ id, kind, label, requirement, scenario, scope }`
- `P.register_unlock(id, spec)` — later lanes register cosmetics and drill variants
- kinds: `P.KIND_ACHIEVEMENT` ("achievement"), `P.KIND_COSMETIC` ("cosmetic"), `P.KIND_DRILL_VARIANT` ("drill_variant")
- requirements: `{ type = "level", level = N }`, `{ type = "achievement", id = "…" }`, `{ type = "predicate", test = fn }`
- `P.evaluate_unlocks(progress, snapshot, scope_key)` → `{ newly = {ids}, unlocked = {ids} }`
- a `drill_variant` unlock MUST name the NEW scenario it grants (`spec.scenario`); without it the registration is rejected
- `scope = "class" | "account"` is optional (both by default); the flags live in the scope, so a class unlock never leaks into another class
- **HARD RULE (pinned):** an unlock never touches a drill — a variant is registered as its OWN scenario; there is no grading/sim code in the module at all

### Persistence (`SwedgeTimerDB.profile.practice`)

- `P.SCHEMA_VERSION = 1`; shape `{ schema_version, progress, stats }`
- `P.new_profile()` — the fresh profile
- `P.migrate(blob)` / `P.validate(blob)` — migrate + repair; never throws; returns a NEW table (the input is never mutated, sibling saved variables are never touched)
- `P.is_current(blob)` — false for a blob a NEWER build wrote; `migrate` returns such a blob UNCHANGED (we never wipe what we do not understand)
- repair rules: unknown keys dropped · bad types reset to the defaults · an unknown grade in the recent ring becomes F · the hits are clamped to the attempts · the history is trimmed to 50 · an unknown unlock flag is KEPT (a downgrade must not un-unlock a cosmetic)

### `practice_stats.lua` (loads FIRST)

- `S.new_state()` / `S.new_scope()` — one scope per class + the account scope
- `S.record_attempt(state, class_key, grade, drill_id)` — runs/attempts/hits/misses/points/best grade/best S-run/rolling-20/per-drill table; the account scope always updates too
- `S.record_session(state, class_key, summary, duration_seconds, day)` — runs, time active, best session score, the 50-session history ring; a session with 0 attempts is NOT a completed session
- `S.snapshot(state)`, `S.export_payload(state)`, `S.repair_state(state)`, `S.format_duration(seconds)`, `S.json_safe(value)`
- `S.day_ordinal(day)` — a "YYYY-MM-DD" string or a numeric day counter → a day ordinal (civil calendar, no `os.time`)

## Cross-module rules (no duplicated numbers)

- XP per attempt = `GRADE_POINTS[grade]` (the live `st.practice.GRADE_POINTS` wins; the mirror is the offline fallback)
- the rolling accuracy window = `SCORE_WINDOW` (20); the mastery window = 100; the history ring = 50
- the daily streak = consecutive calendar days with a completed session; **a missed day FREEZES it (no reset, no increment)**
- a session streak = consecutive non-F attempts; an F breaks it and earns nothing

## Verification

- `lua5.1 tests/practice_progress_state.lua` → 390 checks, 0 failures
- `lua5.1 tests/practice_stats_state.lua` → 415 checks, 0 failures
- `bash tests/run.sh` → **40 steps, 0 failed** (the lane's own steps: `practice_progress_state`,
  `practice_stats_state`, `toc_check`, `luacheck`)
- luacheck: the 5 touched files are **0 warnings / 0 errors**; the repo total is 3 warnings /
  0 errors — the extra warning is in `main.lua` + `tests/main_init_state.lua`, files another
  lane owns (the pre-lane floor was 2 warnings; this lane added none)
- TOC coverage: `tests/toc_check.lua` green — every root module on disk must be listed, so
  the two new modules are pinned on all 7 flavours; both new suites also pin the load order
  (`practice.lua` → `practice_stats.lua` → `practice_progress.lua` → … → `practice_ui.lua`)
- **mutation proofs: 51/51 killed** on `/tmp/opencode/practice-gamification-mut` (script
  `/tmp/opencode/practice_gamification_mutations.py`) — one mutant per rule (level curve,
  cap/renown, XP, daily cap, mastery window/half-life/gate/tiers, all three streaks, the
  account total, every achievement threshold, the unlock registry kinds + requirement types +
  scope isolation + the no-drill-touch rule, the reserved drill bucket, migrate/validate/
  repair/future-version, the rolling window, the history bound, the per-drill table, the
  export payload, the sanitiser, the snapshot)

## Crossfire seen during the lane (NOT this lane's files)

`tests/diag_state.lua` (1 check) and `tests/main_init_state.lua` (2 checks) went red at ~19:40
while this lane was running, and cleared again by ~19:45. Evidence it was another lane's
in-flight work: `diag.lua` (19:38:25), `main.lua` (19:39:41) and `bars.lua` (19:40:59) were
rewritten by another writer during this lane; `main_init_state.lua` boots `compat.lua` /
`utils.lua` / `main.lua` only (it never loads the practice modules, and it does not read the
toc), and the failing checks are the offhand recolour / offhand timer (`main.lua`'s
`PLAYER_TARGET_SET_ATTACKING` handler, reworked with an "F2 deep audit 2026-10-19" comment)
and the diag error ring. This lane's own suites, `toc_check.lua` and luacheck were green
throughout, and the final full-harness run is 40/0.


## Handoff to the next lanes (spec §7 steps 2-5)

1. **Hook lane (step 2):** wire `db.profile.practice` — `config.lua` owns `ST.defaults`, so it
   needs `practice = ST.PRACTICE_DEFAULTS` inside `ST.defaults.profile` (config.lua is outside
   the foundation lane's scope, so it was NOT touched here). The hook then does
   `db.profile.practice = st.practice_progress.migrate(db.profile.practice)` (REPLACE, never
   mutate the default in place) and feeds `record_attempt` / `end_session` with the session's
   drill key, the injected day (`date("%Y-%m-%d")` or a day counter) and the injected duration
   (`st.api.get_time()` deltas, live-session only).
2. **UI lane (step 3):** read `P.profile_snapshot(progress, S.snapshot(stats), scope)` — it
   already carries the level, the renown, the XP progress, the streaks, the per-drill mastery
   rows and the unlock flags.
3. **Unlock lane (step 4):** register cosmetics and drill variants with `P.register_unlock`;
   a drill variant is a NEW scenario (`spec.scenario`), never a mutation of an existing drill.
4. **Export lane (step 5):** `P.export_payload(progress)` + `S.export_payload(stats)` are
   JSON-safe and ride the existing settings export/import path.
