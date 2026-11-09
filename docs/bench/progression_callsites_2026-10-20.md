# Progression call sites + the drill-list pick contract — 2026-10-20

Desk: `desks/progression-callsites`. Lane: land the call sites the three progression
lanes left **FILED**, plus the drill-list pick contract.

**VERDICT: FIXED (6 filed call sites) + the pick contract + 1 filed pin set pasted.**

---

## 1. What this lane changed (and ONLY these files)

| File | Change |
|---|---|
| `practice_ui.lua` | §7.1 the account scope at the session end; §7.3 ONE day numbering; §7.4 the grade is validated before the live score counts it; §7.5 the two cap notices' wording; **F1** the drill-list press wins over a class-published pick alias |
| `practice_progress_ui.lua` | §7.2 the history day is read **SIGNED** (the `NO_DAY` sentinel survives) |
| `tests/practice_ui_state.lua` | the UI lane's filed pins (§7 of `bench/progression_ui_fixes_2026-10-20.md`); §26d rewritten; §28 the five filed call sites' pins; §29 the F1 pick-contract pins |
| `tests/practice_progress_ui_state.lua` | §9 the `NO_DAY` sentinel reaches the renderer |

NOT touched: `practice_progress.lua`, `practice_stats.lua` (a sibling lane owns them),
the class files, `option_tables.lua`, `config*.lua`, `main.lua`, `diag.lua`,
`compat.lua`, `hud.lua`, `bars.lua`, `run.sh`, the TOCs, the versions, the docs. No
git commit. No lint-config change.

`practice_ui.lua` is still at **199 of Lua 5.1's 200 file-scope locals** (verified
with `luac5.1 -l -l`) — every new piece of state rides the `ui` table or a
function-local, so there was no need for a new file-scope local.

---

## 2. The pure lane's filed call sites (§7.1–§7.5)

### 2.1 §7.1 — the ACCOUNT scope is evaluated at the session end

`practice_ui.lua:1503-1508` — `P.evaluate_unlocks(progress, snapshot, class_key)` was
the only production call site, and the class scope is one of two scopes: the account
scope's unlock flags live in `progress.global.unlocks`, so every account-scoped
achievement stayed locked for good.

```lua
    local stats_snapshot = S.snapshot(stats)
    local snapshot = P.profile_snapshot(progress, stats_snapshot, class_key)
    -- M2 (progression audit 2026-10-20): the ACCOUNT scope is a scope of its own -
    -- its unlock flags live in progress.global.unlocks - so it needs its own
    -- evaluation, or every account-scoped achievement stays locked for good.
    local account = P.profile_snapshot(progress, stats_snapshot, P.GLOBAL_SCOPE)
    local unlocked = P.evaluate_unlocks_both(progress, class_key, snapshot, account)
```

The stats snapshot is read once and handed to both scope models. The merged
`newly` list is de-duplicated by the pure module, so an id earned in both scopes is
announced ONCE.

**Pin (§28a):** after one S grade and a session end, BOTH
`progress.classes.PALADIN.unlocks.first_s` and `progress.global.unlocks.first_s` are
`true`, and the two scopes are separate tables.

### 2.2 §7.2 — the history day is read SIGNED

`practice_progress_ui.lua:433-449` — `count(entry.day)` clamped the stats module's
`NO_DAY` sentinel (-1) to 0, so a no-date session rendered **1970-01-01** instead of
"-". The day is now read with `num(entry.day, no_day)`, and `no_day` comes from the
pure module's own `S.NO_DAY` when it answers.

**Pin (`tests/practice_progress_ui_state.lua` §9):** a session recorded with no date
keeps `day == -1` through the read model, `format_day` answers nil, and the history
row renders **"-"** — never "1970-01-01".

### 2.3 §7.3 — ONE day numbering

`practice_ui.lua:1040-1060` — the `time()`/UTC fallback is GONE. It was a UTC day
count, a DIFFERENT numbering from the civil "YYYY-MM-DD" form the pure layer's day
ordinal is built from, and mixing the two rolled the day over at the wrong hour. The
`date` global exists on every shipped client family (the pure lane's RJ-2 ruling,
cited in `bench/progression_fixes_2026-10-20.md` §6), so the branch is unreachable in
practice; a client with no calendar now has NO day — the pure layer's own no-day
path, which is REPORTED (the M4 notice), never hidden.

**Pin (§26d, rewritten + §28c):** a client with no calendar stores NO day
(`drill.daily_day == nil`) and its daily cap cannot reset; a client WITH a calendar
stores the CIVIL ordinal (`P.day_ordinal("2026-10-19")`), which is the same numbering
the pure module builds from the string form.

> The old §26d pin asserted the opposite (a clock-only client still gets a day and
> the cap resets). It contradicted the shipped rule and was rewritten to pin the new
> contract — the whole point of the pin is to fail when the rule changes.

### 2.4 §7.4 — the grade is validated BEFORE the live score counts it

`practice_ui.lua:1445-1461` — the live scoring model counts ANY grade it is handed
(`points = GRADE_POINTS[grade] or 0`, but the attempt and the HIT counters still
move), while the pure modules drop a grade outside the scoring model's set. The
score and the progression could therefore diverge.

```lua
    local P = st.practice_progress
    if P and type(P.known_grade) == "function" and not P.known_grade(grade) then
        return
    end
```

**Pin (§28b):** an unknown grade ("Z") is not an attempt, not a hit and never
becomes the last grade on the live score, and the live score's attempt count equals
the progression's after a known grade.

### 2.5 §7.5 — the two cap notices describe the SHIPPED cap

The cap is `max(3 × median(HIT points), best hit)` (the H-1 fix), so:

* the H-2 notice now says **"3x its median hit XP"** (was "3x its median attempt XP");
* the M4 notice now says **"this drill earns XP only up to its cap until the client
  provides a date"** (was "this drill earns no XP until the client provides a
  date" — false: the cap has a floor, so the drill earns up to its cap).

**Pins (§28d):** the notice names "median hit XP" and never "median attempt XP";
the no-calendar notice says "earns XP only up to its cap" and never "earns no XP".

---

## 3. F-1 — the drill-list press is the pick (the pick contract)

`practice_ui.lua:5399-5416` (`drill_list_grade`) — the alias block only filled an
**EMPTY** alias, so a class that publishes its own pick alias kept it, and the
class's own reader (which reads that alias FIRST) graded the class's value instead
of the player's press.

The block now OVERWRITES the alias, so the press wins:

```lua
    if type(pick) == "string" and pick ~= "" then
        ctx.pick = pick
        ctx.pressed = pick
        ctx.action = pick
    end
```

**What did NOT change (and why):**

* **the scenario path** — the hunter's live cast stays the pick there. That path is a
  DIFFERENT call site (`scenario_context(now, ui.scenario_last_action)`), and the
  alias block is not in it;
* **the hunter's own drill behaviour** — a drill press with NO pick still judges the
  shot that is actually in flight. The overwrite only happens when there IS a press,
  so the class's own `ctx.pick` (the live cast) survives a press-less drill press;
* **the class-side readers** (`rogue_guide.lua`, `shaman_guide.lua`,
  `classes/hunter.lua`) — untouched; they are correct as they are.

**Pins (§29, `tests/practice_ui_state.lua`):**

* **Case A — the HUNTER, reachable today.** The class's own ctx publishes
  `ctx.pick` = the live cast and the hunter's reader reads `ctx.pick` FIRST. The
  fixture publishes a Steady Shot in flight; the drill-list press of the rotation's
  own answer ("silencing_shot") must be graded **S**. Measured before the fix: the
  ctx carried `ctx.pick = "steady"` and the press graded **F**.
* **Case B — the ROGUE/SHAMAN shape (latent today).** The sandbox wraps the class's
  own ctx builder to publish `ctx.action` (the alias the rogue and the shaman read
  FIRST) and no `ctx.pick`; the press must still ride in `ctx.action` and
  `ctx.pick`.
* **Case C — the hunter's own drill behaviour.** A drill press with NO pick still
  delivers the class's live cast to the grader and still grades a letter (not
  UNKNOWN).

**The mutation proof the lane was asked for** (a "class pick shadows the press"
mutant must fail a pin): `F1a-class-pick-shadows-the-press` — the alias block
restored to the fill-only-empty form — dies on **three** pins (§29 case A ×2, case B
×1). See §5.

---

## 4. The filed pins that came in from the UI lane

`bench/progression_ui_fixes_2026-10-20.md` §7 filed three pins for the lane that
owns `tests/practice_ui_state.lua`. They are pasted verbatim into that file as
**§26i** (the H-2 cap notice), **§26j** (the M-1 refusal notice + the flush
reporting the write) and **§26k** (the reserved `_unknown` bucket on both sides).
The baseline they were proved against was 1637 checks; the suite now reads **1666**.

---

## 5. Verification

**Harness:** `bash tests/run.sh` → **41 steps, 0 failed**; luacheck **2 warnings / 0
errors in 83 files** (the standing floor: `compat.lua:36`, `main.lua:81`). The four
touched files are **0 warnings / 0 errors** on their own.

**Own suites:** `tests/practice_ui_state.lua` **1666 checks / 0 failures**,
`tests/practice_progress_ui_state.lua` **290 checks / 0 failures**.

**File-scope locals:** `luac5.1 -l -l practice_ui.lua` → `199 locals` (unchanged;
the Lua 5.1 limit is 200). CRLF preserved on `practice_ui.lua`;
`practice_progress_ui.lua` and the two test files are LF (unchanged). No trailing
whitespace on any touched line.

**Mutation proofs** (`/tmp/opencode/progcalls_muts.py`, a fresh copy of the tree per
mutant under `/tmp/opencode/progcalls_mut`; both baselines clean):

| mutant | killed by |
|---|---|
| `F1a-class-pick-shadows-the-press` (the alias block fills only an EMPTY alias again) | §29 "the press wins over the class's published pick (ctx.pick)", "the PRESS is graded, not the live cast", "the press wins over the class's published ctx.action" |
| `M2a-account-scope-never-evaluated` | §28a "the account scope holds its own flag too" |
| `L4a-unknown-grade-counts-on-the-live-score` | §28b ×4 ("not an attempt" / "not a hit" / "never the last grade" / "the same attempts") |
| `L6a-the-clock-fallback-is-back` (the second numbering returns) | §26d "a client with no calendar has no day, so the cap cannot reset" + §28c "a client with no calendar stores no day at all" |
| `W1a-the-cap-notice-describes-the-old-cap` | §28d ×2 ("names the cap's own rule" / "no longer describes the old cap") |
| `W1b-the-no-calendar-notice-claims-nothing-is-earned` | §28d ×2 ("earns up to its cap" / "no longer claims the drill earns nothing") |
| `M3a-the-no-day-sentinel-is-clamped` | §9 ×4 (the sentinel survives the read model / renders as no date / the row renders "-" / never the epoch) |

**7 killed, 0 survived.** The script also reports a mutant that BREAKS the file
instead of failing a pin as INVALID (not as a kill) — the first run of the W1a mutant
was a syntax error, not a pin failure, and was corrected before the final run.

**Offline only.** Nothing here is proven in a client: the presses are code paths, not
observed behaviour.

---

## 6. Deliberately NOT done

* **No class-file change.** The hunter's own comment at `classes/hunter.lua` ("The
  engine's drill press carries no action, so the live cast is the player's own pick")
  is now STALE — the drill press DOES carry an action. The class file is out of this
  lane's scope, so the comment is left for the hunter lane; the production behaviour
  is correct without it (the press wins, and the class's own pick survives a
  press-less press).
* **No bench artifact for the pure side** — `practice_progress.lua` /
  `practice_stats.lua` belong to a sibling lane and were not touched.
* **The per-drill-per-day cap latch stays in memory** (the UI lane's decision, §11 of
  its artifact) — unchanged by this lane.
* **The `date` fallback is gone, so the `time` global is no longer read** by
  `practice_ui.lua`. The sandbox's `clock_epoch` option survives in
  `tests/practice_ui_state.lua` and is now used to PROVE the clock is not a day
  source (§26d) — the option is not dead.
