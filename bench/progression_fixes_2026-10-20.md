# Progression-surface fixes (H-1, M-2, M-3, L-1, L-4, L-6) — 2026-10-20

Desk: `progression-fix`. Source of the findings: `desks/progression-audit/journal.md`
(read-only audit, session `ses_ea616dd2cffeWFceVBxbz3Z2Ok`, verdict FINDINGS 13).

**Scope of this lane:** `practice_progress.lua`, `practice_stats.lua`,
`tests/practice_progress_state.lua`, `tests/practice_stats_state.lua` — and nothing
else. `practice_ui.lua` and `practice_progress_ui.lua` belong to sibling lanes; the
changes that need to happen there are FILED below with the exact diff, not edited.

**VERDICT: FIXED (6 findings) + 5 filed call-site changes.**

---

## 1. H-1 (HIGH) — the daily XP cap could be zero → every award swallowed

**Root:** the cap was `3 × median(grade points over the whole recent window)`. A miss
(F) earns 0 points, so below 50 % rolling accuracy the median was 0, the cap was 0,
and every award was 0 — for good (≈50 consecutive hits to escape, and the tier ladder
is accuracy-gated too).

**Fix (two independent defences, both in the pure module):**

1. `practice_progress.lua:346-370` — the cap is taken over the drill's **HITS**
   (`hit_points_window`): a miss earns nothing, so it must not drag the cap down.
   The spec's meaning is kept — 3× what the drill earns.
2. `practice_progress.lua:450-466` (`P.drill_daily_cap`) — the cap is
   `max(3 × median(hit points), best hit in the window)`. The best-hit floor is what
   makes "a hit always earns at least its own points" true: the attempt being
   recorded is already in the window when the cap is taken, so the floor is never
   below that attempt's grade points.

**Guarantees now stated in the module:**

* the cap is never 0 for a drill with a hit (the H-1 defect cannot return);
* the cap never exceeds 3× the best hit in the window (the anti-grind holds);
* on a fresh day a hit earns its full points;
* the day's awards never exceed the cap that was in force when they were made.
  (The cap is read from the live window, so a low hit can *lower* it during a day and
  the day's awards then stop — the day's total never exceeds the cap in force at the
  time of its award. A frozen per-day cap would need a persisted field and a schema
  bump; it was judged out of proportion to the corner case and is documented instead.)

**Pins** (`tests/practice_progress_state.lua:306-374`): a drill at 40 % accuracy
(6 misses + 4 hits) still earns 100 per hit; the day's total stays ≤ cap × (1 +
`SESSION_BONUS_XP_SHARE`); the cap is 3× the median hit and ≤ 3× the best hit; the
misses do not drag the median down; the best-hit floor holds; a drill with no hit
has no cap and its misses earn nothing.

---

## 2. M-2 (MEDIUM) — the account scope's achievements were never evaluated

**Root:** `P.evaluate_unlocks` was called with the **class** scope only
(`practice_ui.lua:1498` is the only production call site), so `progress.global.unlocks`
was never written and any `scope = "account"` unlock could never fire.

**Fix (pure side, in scope):** `practice_progress.lua:1007-1046` —
`P.evaluate_unlocks_both(progress, class_key, class_snapshot, account_snapshot)`
evaluates the class scope **and** the account scope and merges the two results:
`newly` is the sorted, de-duplicated merge of both scopes' new ids; `unlocked` is the
union of both scopes' unlocked sets. Without an account snapshot the function
degrades to the old single-scope behaviour.

**The contract is now stated in the registry's doc comment**
(`practice_progress.lua:811-825`): the unlock flags live in the scope they were
earned in; `scope = "class"` is only evaluated in a class scope, `scope = "account"`
only in the account scope, and **no scope in both**; an account-scoped achievement
can only fire when the account scope is evaluated, so the session-end path must
evaluate both.

**Pins** (`tests/practice_progress_state.lua:720-771`): the merged evaluation writes
the account scope's flag; an account-scoped unlock fires; a class-scoped unlock stays
out of the account scope; an id earned in both scopes is merged **once**; a second
evaluation finds nothing new; without an account snapshot the account scope is not
evaluated.

---

## 3. M-3 (MEDIUM) — the "no date recorded" sentinel was destroyed by `count()`

**Root:** `count()` clamps negatives to 0, so the `NO_DAY` sentinel (-1) became the
epoch and the `if day < 0` branch was dead code. The history row rendered
**1970-01-01** instead of "-".

**Fix (pure side, in scope):** `practice_stats.lua:618-630` — the history day is now
read **signed**: `num(entry.day, S.NO_DAY)`, floored, and any negative maps to
`S.NO_DAY`. A day of 0 (the epoch) is a real day and stays 0.

**Pins** (`tests/practice_stats_state.lua:288-330`): the sentinel survives the repair
and the export payload; a corrupt negative day maps to the sentinel; the epoch stays
0; a non-numeric / missing day maps to the sentinel.

**The UI read is FILED (sibling lane)** — see §7.2.

---

## 4. L-1 (LOW) — `register_unlock` coerced an unknown kind to "cosmetic"

**Fix:** `practice_progress.lua:837-847` — an unknown kind is **rejected** (returns
nil, nothing is registered), the same way the drill-variant branch already rejects a
missing scenario. A missing kind is rejected too: the kind is not optional.

**Pins** (`tests/practice_progress_state.lua:610-624`): a typo'd kind is rejected, a
kind-less spec is rejected, neither is registered, and the cosmetic count does not
grow.

---

## 5. L-4 (LOW) — an unknown grade advanced the live score but was dropped by the pure modules

**Fix (pure side, in scope):** both pure modules now expose the same predicate over
the scoring model's grade set — `P.known_grade(grade)` (`practice_progress.lua:196`)
and `S.known_grade(grade)` (`practice_stats.lua:149`) — and both `record_attempt`
paths use it (`practice_progress.lua:639`, `practice_stats.lua:278`). The live
scoring model's table is the truth; the mirror is the offline fallback.

The remaining half of the divergence (the live score counting a grade the pure
modules drop) is in `practice_ui.lua` and is **FILED** — see §7.4.

**Pins** (`tests/practice_progress_state.lua:220-249`,
`tests/practice_stats_state.lua:91-105`): both modules answer the same; every grade
of the live scoring model is known to both; an unknown / nil / non-string grade is
not known and is not an attempt on either side.

---

## 6. L-6 (LOW) — the day rollover was not one-directional, and the two day numberings were not interchangeable

**Fix (pure side, in scope):** `practice_progress.lua:682-695` — the rollover is now
**one-directional**: only a day strictly later than the stored one starts a new day.
The same day and an earlier day (a backwards clock) leave the day's XP alone, so a
backwards clock can never wipe a day that was already earned — and it can never hand
out a free extra day either.

**The numbering is now pinned to ONE:** the civil-day count since 1970-01-01, which is
what the "YYYY-MM-DD" form produces. Documented in both modules'
`day_ordinal` (`practice_progress.lua:234-244`, `practice_stats.lua:187-195`): a
numeric counter in a **different** numbering (a UTC day count) can sit one day away
from the string form, the module cannot detect that, so the caller must never mix the
two forms.

**RJ-2 answered (the audit's open ruling):** the `date` global **exists on every
target client family**. Blizzard's own code calls it on all five branches checked:

- `classic_era:Interface/AddOns/Blizzard_Communities/GuildNews.lua:107` — `date("*t")`
- `classic_anniversary:Interface/AddOns/Blizzard_ArchaeologyUI/Blizzard_ArchaeologyUI.xml:173` — `date("*t", …)`
- `classic_titan:Interface/AddOns/GlueXML/Shared/AccountReactivate.lua:90` — `date("*t", newTime)`
- `origin/forever:Interface/AddOns/Blizzard_EncounterJournal/Mainline/Blizzard_MonthlyActivities.lua:180` — `date("*t", …)`
- `live:Interface/AddOns/Blizzard_FrameXMLUtil/GameTimeUtil.lua:78` — `tonumber(date("%H"))` (the LOCAL time)

`date` is the LOCAL calendar in WoW, so the `"%Y-%m-%d"` path is the canonical
(civil) numbering on every shipped client. The UTC `time()` fallback in
`practice_ui.lua` is therefore dead code — and it is the ONLY source of the second
numbering. It is FILED for removal — see §7.3.

**Pins** (`tests/practice_progress_state.lua:375-401`): a backwards day does not wipe
the day's XP; the same day does not wipe it; the next day starts a new day from zero.

---

## 7. FILED for the sibling lanes (exact diffs — NOT applied by this lane)

### 7.1 `practice_ui.lua:1496-1500` — M-2: evaluate the account scope at session end

```diff
     -- The achievements: the merged snapshot feeds the predicates (spec §4).
     local snapshot = P.profile_snapshot(progress, S.snapshot(stats), class_key)
-    local unlocked = P.evaluate_unlocks(progress, snapshot, class_key)
+    -- M2 (progression audit 2026-10-20): the ACCOUNT scope is a scope of its own -
+    -- its unlock flags live in progress.global.unlocks - so it needs its own
+    -- evaluation, or every account-scoped achievement stays locked for good.
+    local account = P.profile_snapshot(progress, S.snapshot(stats), P.GLOBAL_SCOPE)
+    local unlocked = P.evaluate_unlocks_both(progress, class_key, snapshot, account)
     ui.progress_new_unlocks = unlocked.newly
     announce_unlocks(self, unlocked.newly)
```

`P.GLOBAL_SCOPE` is `"GLOBAL"` (`practice_progress.lua:122`).

### 7.2 `practice_progress_ui.lua:433-447` — M-3: read the history day SIGNED

```diff
     -- The session history (oldest first, as the pure module keeps it).
     local history = (type(stats_scope.history) == "table") and stats_scope.history or {}
+    -- M3 (progression audit 2026-10-20): the day is read SIGNED. The stats
+    -- module's NO_DAY sentinel (-1) means "no date recorded"; count() clamped it
+    -- to 0 (the epoch) and the row rendered as 1970-01-01 instead of "-".
+    local no_day = -1
+    if S and type(S.NO_DAY) == "number" then no_day = S.NO_DAY end
     for i = 1, #history do
         local entry = history[i]
         if type(entry) == "table" then
             model.history[#model.history + 1] = {
                 score = count(entry.score),
                 accuracy = num(entry.accuracy, 0),
                 attempts = count(entry.attempts),
                 hits = count(entry.hits),
-                day = count(entry.day),
+                day = num(entry.day, no_day),
                 duration = count(entry.duration),
             }
         end
     end
```

(The line numbers are against the file as of 11:50 on 2026-10-20 — the sibling lane
had already edited the file; the `day = count(entry.day)` read was still there.)

`S` is already in scope in `ui.scope_model` (`practice_progress_ui.lua:310`) and
`num` is a file-local guard (`:129`). `ui.format_day` already returns nil for a
negative ordinal (`:523`) and the renderer already falls back to `"-"` (`:1233`), so
the sentinel now renders as "-" with no further change.

### 7.3 `practice_ui.lua:1052-1066` — L-6: one day numbering

```diff
 local function current_day()
     local ok, day = pcall(date, "%Y-%m-%d")
     if ok and type(day) == "string" and day ~= "" then
         return day
     end
-    -- The client's clock: seconds since the epoch. The day index is the UTC day
-    -- number - consecutive days differ by exactly 1, which is what the pure
-    -- layer's numeric day ordinal expects of a number.
-    local ok_time, now = pcall(time)
-    if ok_time and type(now) == "number" and now == now
-        and now ~= math.huge and now ~= -math.huge then
-        return math.floor(now / 86400)
-    end
+    -- No calendar: the pure layer gets NO day. The numeric fallback that used to
+    -- live here was a UTC day count - a DIFFERENT numbering from the civil
+    -- calendar above - and mixing the two rolled the day over at the wrong hour.
+    -- The date global is present on every shipped client family (cited in
+    -- bench/progression_fixes_2026-10-20.md §6), so this branch is unreachable
+    -- in practice; the no-day path is the one the M4 notice already reports.
     return nil
 end
```

The pure side is already safe against the dangerous direction (a backwards switch
cannot wipe a day, see §6) — this filed change removes the second numbering
altogether.

### 7.4 `practice_ui.lua:1447-1465` — L-4: validate the grade before the live score counts it

```diff
 function ui.record_graded_attempt(self, grade, lead_ms)
     local pr = st.practice
     if not pr or not grade then
         return
     end
+    -- L4 (progression audit 2026-10-20): the live score model counts ANY grade it
+    -- is handed, while the pure modules drop a grade outside the scoring model's
+    -- set. Validate first, so the score and the progression can never drift apart.
+    local P = st.practice_progress
+    if P and type(P.known_grade) == "function" and not P.known_grade(grade) then
+        return
+    end
     if ui.score then
         pr.record_attempt(ui.score, grade, lead_ms)
     end
     ui.record_progress_attempt(self, grade)
 end
```

### 7.5 `practice_ui.lua:1405-1434` — wording: the two cap notices no longer describe the cap

Both notices were written against the old cap. The cap is now "3× the median **hit**
XP, floored by the best hit", and a drill with no calendar day no longer earns
nothing (the cap has a floor, so the drill earns up to its cap).

* line 1408-1409 (the M4 notice, no calendar): *"…this drill earns no XP until the
  client provides a date."* → now false. Suggested: *"…the daily XP cap cannot
  reset, so this drill earns XP only up to its cap until the client provides a date."*
* line 1430-1431 (the H-2 notice, today's cap): *"…today's XP cap (3x its median
  attempt XP)…"* → suggested: *"…today's XP cap (3x its median hit XP)…"*

---

## 8. Verification

**Harness:** `bash tests/run.sh` → 41 steps, 3 failed. The only failures are
`tests/hunter_state.lua` (1 of 1191), `tests/hunter_guide_state.lua` (2 of 1862) and
`tests/hud_state.lua` (1 of 731) — all of them the hunter's Forever **`steady`**
shot (its ranks, its fallback cast time and its HUD out-of-range report). That is a
**parallel-lane crossfire**: `classes/hunter.lua` was edited at 11:46 by another
lane, and none of the three suites loads `practice_progress.lua` or
`practice_stats.lua` (grep: 0 hits each). The failure count moved between 1 and 3
across the session for the same reason.
`luacheck .` → **2 warnings / 0 errors in 83 files** (the floor, unchanged; the
sibling lane's own warning came and went with their edits). The four files this
lane touched are **0 warnings / 0 errors** on their own.
Own suites: `practice_progress_state.lua` 494 checks / 0 failures,
`practice_stats_state.lua` 558 checks / 0 failures; the two UI suites
(`practice_progress_ui_state.lua` 255 checks, `practice_ui_state.lua` 1623 checks)
are green.

**Mutation proofs** (`/tmp/opencode/progression_muts.sh`, staged copies on
/tmp/opencode; a mutant is killed when a pin catches it):

| mutant | killed by |
|---|---|
| `H1a-cap-can-be-zero` (the original cap restored: median over every attempt, no floor) | **"H-1: a hit still earns its points below 50% accuracy (got 0, want 100)"** |
| `H1b-no-best-hit-floor` | "H-1: a hit earns its own points against a low median (the floor)" |
| `H1c-cap-equals-median` | "the daily cap holds the drill at 3x its median" |
| `M2a-account-scope-never-evaluated` | **"M-2: the account scope holds its own flag too"** |
| `M2b-class-scope-never-evaluated` | "M-2: the class scope holds its own flag" |
| `M3a-sentinel-clamped` (`count(entry.day)`) | **"M-3: the no-day sentinel survives the repair (got 0, want -1)"** |
| `M3b-sentinel-zeroed` | "M-3: the no-day sentinel survives the repair" |
| `L1a-unknown-kind-coerced` | "L-1: an unknown unlock kind is rejected" |
| `L4a-progress-accepts-any-grade` | "an unknown grade is not an attempt" |
| `L4b-stats-accepts-any-grade` | "an unknown grade is not an attempt" |
| `L6a-rollover-not-one-directional` | "L-6: the same day does not wipe the day's XP" |

**11 killed, 0 survived.** One further mutant is an *equivalent* one and is recorded
as such: dropping the `is_hit()` filter alone changes nothing (the `points > 0`
filter already drops a miss) — it documents that the two H-1 defences are
independent.

---

## 9. Not fixed here (out of this lane's scope)

* **H-2** (the silent daily-cap swallow) — the sibling lane has landed it in
  `practice_ui.lua`; only the wording follows up (§7.5).
* **M-1** (the newer-blob refusal is silent / the flush reports success) —
  `practice_ui.lua` + `main.lua`, not this lane's files.
* **M-4, M-5** (the daily streak is not displayed; the reset's armed state never
  expires) — `practice_progress_ui.lua`, not this lane's files.
* **L-2** (the `_unknown` bucket on one side only) — the sibling lane has already
  aligned it in `practice_ui.lua` (`ui.UNKNOWN_DRILL_KEY`).
* **L-3** (the account-scope drill merge is last-writer-wins), **L-5** (the 5-minute
  write throttle is inert) — not in this lane's scope, no change.
