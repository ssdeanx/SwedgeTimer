# Practice gamification — enterprise design spec (2026-10-19)

Operator order: practice should be a **minigame** — level up from practice, XP, saved
scores, and a stats section (total runs, accuracy, time active, and more) — with each
class's practice mirroring real combat as closely as the sim allows.

Status: **built** — the foundation, the session hook, the Progress page + stats frame and
the visibility gate all landed (see `bench/buildout_practice_gamification_foundation_2026-10-19.md`,
`.../buildout_practice_gamification_hook_2026-10-19.md`, `.../buildout_practice_progress_ui_2026-10-19.md`,
`.../buildout_gamification_visibility_2026-10-19.md`).

**Corrected 2026-10-20** in the Phase-8 documentation truth pass
(`bench/final_completion_plan_2026-10-19.md` Phase 8). The corrections, in one line each:
this build ships **no import/export surface**, so progress is **local-only** (§0 rule 3,
§6's export bullet, §7 step 5); the rewards section now carries all three of the
operator's decisions — cosmetics **+ level-gated harder drill variants**, the **static**
achievement set and the **no-punishment** streak (§5); and the operator decisions are
marked **RESOLVED** (§9). Nothing else in the spec changed.

---

## 0. Design rules (non-negotiable)

1. **Practice stays practice.** Every drill remains 100% usable with zero progress.
   Progression never gates a feature; it only rewards.
2. **Rewards never degrade existing content.** Unlocks change colors, titles, themes,
   popup styles — and may gate **additional harder drill variants**. They never change
   sim fidelity, grading, timings, or difficulty of an existing drill.
3. **Local only.** No network, no accounts, no telemetry, no PII. Everything lives in
   `SwedgeTimerDB`, and it stays there: **this build ships no import/export surface**
   (§6), so a progress payload cannot be moved between machines. (Corrected 2026-10-20 —
   the original wording here said "and is exportable as JSON", which is wrong for this
   build; the payload is JSON-*shaped*, nothing writes it out.)
4. **Deterministic core.** Progression/stat math is a pure function of its inputs.
   No `os.time`, no randomness, no clock reads inside the pure modules — time and dates
   are injected, so every rule is unit-testable offline.
5. **Never lose player data.** Corrupt or partial progress data repairs itself on load
   instead of throwing or wiping.

---

## 1. Core loop

```
cast in a drill → grade (S/A/B/C/D/F) → points (100/80/60/40/20/0)
   → session score  → XP  → level  → mastery of that drill  → unlock (cosmetic)
   → session end    → stats + achievements + history
```

The existing scoring model is the input (`st.practice.GRADE_POINTS`,
`SCORE_WINDOW = 20`, `record_attempt`, `new_score`). Progression consumes it; it does
not replace it.

---

## 2. Progression model — `practice_progress.lua` (pure)

| Element | Rule |
| :--- | :--- |
| XP per attempt | `GRADE_POINTS[grade]` (F still earns 0 — a miss costs nothing, it just doesn't earn) |
| Session completion bonus | `+25 * completion_bonus_factor` when a session ends with ≥ 10 attempts (rewards finishing, not grinding) |
| Level curve | `xp_for_level(n) = floor(100 * n^1.35)` — diminishing returns, no wall |
| Level cap | 50 per class, then **prestige**: level 51+ increments a renown counter |
| Scope | **Per class** (warrior XP ≠ paladin XP) + a **global account total** across classes |
| Anti-grind | XP is capped per drill per day at 3× the drill's median XP — one drill cannot be farmed for infinite levels |

### Mastery per drill (per class)
- `mastery_pct` = recency-weighted accuracy over the last 100 attempts, exponential decay (half-life 30 attempts).
- **Volume gate**: below 20 attempts the drill reads **Unranked** — one lucky S never grants mastery.
- Tiers: Unranked → Bronze (60% / 20 att) → Silver (75% / 50) → Gold (85% / 100) → Platinum (95% / 200).

### Streaks
- `session_streak` — consecutive non-F attempts in the current session.
- `best_streak` — lifetime best.
- `daily_streak` — consecutive calendar days with ≥ 1 completed session. A missed day does not reset it; it simply stops incrementing (no punishment for a rest day).

---

## 3. Stats section — `practice_stats.lua` (pure) + a stats frame

Lifetime aggregates per class and global:
- **Runs** — completed sessions.
- **Attempts / hits / misses** and **accuracy** (lifetime, rolling-last-20, last session).
- **Time active** — `h:mm:ss` accumulated from the injected monotonic clock, counted **only while a session is live** (not while the panel sits idle).
- **Best session score**, best single grade, best streak.
- **XP total, level, progress toward next level.**
- **Per-drill table**: attempts, accuracy, mastery %, tier.
- **History**: last **50** sessions (bounded ring buffer) — score and accuracy per session.

Display:
- **Options page "Progress"** — level, XP bar, per-drill mastery table, achievements list, stats summary, reset (with confirm).
- **Stats frame** (opened from the page) — accuracy-over-time sparkline (50 sessions), full per-drill and per-class tables.
- **Practice panel** — small level badge + session XP bar (toggleable).

---

## 4. Achievements (data-driven, id table)

Evaluated on every session end; each has an id, a predicate over the stats snapshot, and
unlock state. Examples: `first_s`, `perfect_ten` (10 S in a row), `hundred_attempts`,
`all_drills_gold`, `level_10`, `week_streak`, `ten_hours`. Unlocks fire a toast + chat
notice once. The table lives in the pure module so predicates are testable.

---

## 5. Rewards (operator-decided 2026-10-19 — RESOLVED)

Two kinds of reward, both driven by one unlock registry (id → requirement → unlocked):

1. **Cosmetic unlocks** — practice-panel themes, grade-popup styles (color/size/outline),
   panel accent colors, and a title string rendered in the practice panel header.
2. **Harder drill variants** — level-gated *additional* drills (tighter windows, extra
   constraints, longer fight sequences). A gated variant is **new content**, never a
   change to an existing drill: an existing drill's sim fidelity, grading, timings, and
   difficulty are frozen once shipped.

**Rule: unlocks never alter the grading of an existing drill.** The sim/grading path
reads no unlock state; unlocked variants register as their own scenarios.

Two more operator decisions travel with the rewards, because they are the same kind of
call (what the player is rewarded for, and what is never taken away):

3. **Achievements — a static set.** No rotating daily objectives, no expiring tasks. The
   seven shipped ids are `first_s`, `perfect_ten`, `hundred_attempts`, `all_drills_gold`,
   `level_10`, `week_streak`, `ten_hours` (spec §4).
4. **Streak — no punishment.** A missed day never resets the daily streak; it simply
   stops incrementing (spec §2, Streaks). Nothing is taken back from the player.

**What actually shipped (2026-10-20 correction, for the record).** The unlock registry
carries all three kinds (`achievement` / `cosmetic` / `drill_variant`) and the seven
achievements are registered; the **cosmetic and drill-variant catalogues are empty in
this build** — the registry is the mechanism, not a shipped catalogue. That is a
deliberate state, not a missing feature claim: the rewards *rule* above is the contract
the registry enforces.

---

## 6. Engineering (enterprise bar)

- **Pure modules, WoW-free**: `practice_progress.lua`, `practice_stats.lua`. No WoW API,
  no `os.time`, no randomness — time/date injected. Fully unit-tested offline.
- **Persistence**: `SwedgeTimerDB.profile.practice` with `schema_version` and a
  `migrate()` path. Load-time **validation + repair**: unknown keys ignored, bad types
  reset to defaults, a corrupt blob falls back to a fresh state **without throwing** and
  without wiping other saved variables.
- **Write throttling**: save at session end, on level-up, and at most every 5 minutes
  during a live session — never per attempt.
- **Bounded memory**: history ring buffer (50 sessions), rolling attempt window (100).
- **Clock discipline**: durations from `st.api.get_time()` (aligned monotonic domain),
  injected into the pure layer. Calendar-day maths takes an injected date value.
- **Guards**: NaN/overflow/type guards on every aggregate; a malformed stats snapshot
  degrades to zeros, never to an error.
- **Export — NOT BUILT in this build (corrected 2026-10-20).** The original bullet here said
  *"the stats/progress payload rides the existing settings export/import path (JSON), so a
  profile can move between machines"* — **that claim was wrong**. This build ships **no
  import/export surface at all**: there is no `import_export.lua` in the shipped addon (the
  only two in the repo are `docs/swedge/SwedgeTimer_TBC/import_export.lua` and
  `docs/swedge/SwedgeTimer_Forever/import_export.lua`, which belong to the **archived** addons
  and are not part of this build). Nothing in the shipped tree writes a profile out or reads
  one in, so the progress is **local-only**: it lives in `SwedgeTimerDB.profile.practice` on
  the one machine that played it and cannot be moved between machines in this build. What
  *is* true: `P.export_payload(progress)` and `S.export_payload(state)` are pure, JSON-safe
  payload builders, so the data is *shaped* for a future export — but nothing writes it out
  (spec §7 step 5, also corrected).

---

## 7. Build order

1. **Foundation** — pure modules + persistence + defaults + unit tests (dispatched now).
2. **Hook** — session end → progress update; panel level badge + XP bar.
3. **Progress page + stats frame** — options page, sparkline, tables.
4. **Achievements + cosmetics + unlock flow.**
5. **Export/import integration — NOT BUILT (corrected 2026-10-20).** This build ships no
   import/export surface, so step 5 is not part of the shipped scope: progress is
   local-only (§6's export bullet). The JSON-safe payload builders are in place for a
   future lane, but nothing writes one out.

---

## 8. Risk register

| Risk | Mitigation |
| :--- | :--- |
| Saved-variable bloat | bounded history + rolling windows |
| Write amplification | throttled saves, never per attempt |
| Grinding pressure replacing practice | rewards are additive only (cosmetics + *additional* level-gated drill variants, never a change to a shipped drill); no feature gates; daily XP cap per drill |
| Perceived unfairness across classes | per-class progression; no cross-class competition; no leaderboard |
| Corrupt save on load | schema version + validate/repair, never throw |
| Stats skewing sim behavior | progress state lives outside the sim/grading path |

---

## 9. Operator decisions

**RESOLVED 2026-10-19** (re-stated as RESOLVED on 2026-10-20 by the Phase-8 documentation
truth pass; the decisions themselves did not change):

1. **Rewards — cosmetics + level-gated harder drill variants** (spec §5). Existing drills
   stay frozen; a variant is new content, never a change to an existing drill.
2. **Achievements — a static set**, no rotating daily objectives (spec §4/§5.3).
3. **Streak — no punishment**: a missed day never resets the daily streak (spec §2/§5.4).

**Settled by the same decisions — not open questions** (was listed under "still open"
before the 2026-10-20 correction; neither is a pending decision, both are the standing
state):

4. **Daily objectives are not built** — the static achievement set is the whole set.
5. **Cross-class comparison / leaderboard is not built** — progression is local and
   per-class; the account scope is a total, never a comparison.
