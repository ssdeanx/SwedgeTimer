# progression UI fixes (H-2, M-1, M-4, M-5, L-2, L-5) — 2026-10-20

Lane: `progression-ui-fixes` (desk `desks/progression-ui-fixes/`).
Source of the findings: `desks/progression-audit/journal.md` (VERDICT: FINDINGS 13 —
2 HIGH, 5 MEDIUM, 6 LOW). This lane owns H-2, M-1, M-4, M-5, L-2 and L-5 — the
progression-surface findings that live on the UI side.

Scope touched (and ONLY these):
`practice_ui.lua`, `practice_progress_ui.lua`, `main.lua` (the logout handler only),
`tests/practice_progress_ui_state.lua`.

NOT touched (a sibling lane owns them): `practice_progress.lua`, `practice_stats.lua`,
`tests/practice_ui_state.lua`, `tests/practice_progress_state.lua`,
`tests/practice_stats_state.lua`, `option_tables.lua`, `config*.lua`, `diag.lua`,
`compat.lua`, `hud.lua`, `bars.lua`, `run.sh`, the TOCs, versions, docs.

---

## 1. H-2 (HIGH) — the daily-cap swallow is detected but never reported → FIXED

The detection was already there (`practice_ui.lua`: the session XP before/after the
attempt); the only consumer was the M4 notice, gated on `day == nil`. With a VALID
day the swallow was COMPLETELY silent — the badge showed no "+N XP", the XP bar
stopped, the level stopped, the score kept counting and the player was told nothing.
It happens to every player, every day, after ~3 attempts on a drill.

- `practice_ui.lua:1404` — the detection is now explicit and shared by both notice
  paths: `local swallowed = (xp_after <= xp_before) and (after.xp <= before.xp)`
  (the session's XP **and** the scope's XP must both not move).
- `practice_ui.lua:1424-1437` — the new notice, **once per drill per day**. The latch
  `ui.progress_cap_notice_days` maps the drill's bucket → the day it was told for;
  the next calendar day tells it again. The latch is cleared by the Progress page's
  reset (`practice_ui.lua:1593`), because the reset wipes the drill's daily XP.
- The notice goes through `self:Print` — deliberately NOT the badge-gated
  `announce()`: a progression dead end must be reported even when the badge is off.
- `practice_ui.lua:1390-1401` — the grade's points are read with a `nil` seed, not
  `0`. The old seed (`points = 0`) made the pure module's own copy of the grade
  table unreachable (`type(0) == "number"`), so a grade the live table does not know
  read as "worth nothing" and the detection could not fire for it. This is a
  latent defect in the detection path this fix owns; it is corrected here.

Text: `"Practice XP: this drill has reached today's XP cap (3x its median attempt XP);
it earns again after the next day."`

## 2. M-1 (MEDIUM) — a "written by a newer build" blob: protected, silent → FIXED

- `practice_ui.lua:1133-1146` — `ui.announce_not_persistable(self)`: one notice per
  session ("this session's XP is not being saved"), printed through `self:Print`
  (NOT the badge-gated `announce()`). The latch `ui.progress_persist_notice` is
  cleared with the session (`practice_ui.lua:1329`), so a NEW session says it again
  while the refusal is still in force.
- `practice_ui.lua:1178-1187` — the refusal is reported at the DETECTION point
  (`ensure_progress_profile`), and `practice_ui.lua:1211-1217` reports it at the
  WRITE point (`persist_progress`), so the player hears about it whichever path
  notices first.
- `practice_ui.lua:1178` — **one source of truth owns the rule**: the inline
  `version > P.SCHEMA_VERSION` comparison is GONE. `P.migrate` returns a newer
  build's blob UNCHANGED (the pure module's own rule) and the shared helper
  `P.is_current` answers "is this blob one this build understands?". The hook asks
  the helper; it never compares schema versions itself.
  **The legacy path is unchanged**: a blob with no `schema_version` is still
  migrated and repaired (it is not "not ours" — `P.migrate` repairs it into a
  current one).
- `practice_ui.lua:1512` / `:1555` — the flush reports the **WRITE**, not the close.
  `end_progress_session` puts the write's outcome on the result
  (`result.persisted`), and `flush_progress_session` returns
  `result.persisted == true`. Before: a session whose blob a newer build owns closed
  cleanly and reported SUCCESS while nothing was written.
- `main.lua:1146-1152` — the logout boundary SEES the refusal: the flush's result
  is captured (`local flushed, wrote = st.guard.run(...)`) and a `false` write calls
  the (idempotent, once-per-session) notice. The flush's own return value is the
  write, so `st.guard`'s error counter is untouched — this is a refusal, not a throw.

## 3. M-4 (MEDIUM) — the daily streak is computed and never displayed → FIXED

`model.daily_streak` was computed (`practice_progress_ui.lua:376`) and no renderer
read it.

- `practice_progress_ui.lua:617-622` — the stats summary now carries
  `"Best streak %d  |  Daily streak %d"` (the lifetime best and the daily streak on
  one line; the best streak used to sit alone on that line).
- `practice_progress_ui.lua:1126-1131` — the frame's summary line now carries
  `"... |  Daily streak %d"`.
- Both read `model.daily_streak` — NEVER recomputed.

## 4. M-5 (MEDIUM) — the reset's armed state never expires → FIXED

- `practice_progress_ui.lua:61` — `RESET_ARM_SECONDS = 15`: how long the first click
  stays armed. Long enough for a deliberate double-click, short enough that a stale
  "Confirm: reset all practice progress" cannot wipe every level, XP, mastery,
  achievement and saved session minutes later.
- `practice_progress_ui.lua:645-654` — `ui.now()`: the addon's aligned clock
  (`st.api.get_time()`, the GetTime() domain), nil-safe.
- `practice_progress_ui.lua:659-669` — `ui.reset_arm_expired()`: the deadline is
  checked LAZILY, at every decision point.
- `practice_progress_ui.lua:671-691` — `ui.reset_armed()` disarms an expired arm on
  the spot; `request_reset` (`:695`) re-checks the deadline before it confirms (so a
  stale "Confirm" label can never wipe anything — the click only re-arms);
  `disarm_reset` (`:707`) / `perform_reset` (`:735`) clear the arm's stamp.

Why the time window and not an "options panel closed" hook: this module cannot see
the AceConfig dialog close without patching a vendored library, and the window
covers the same hole — the options page re-reads `reset_armed()` on every redraw
(the button's label and the Cancel button's visibility both call it), so an expired
arm cannot leave a stale "Confirm" behind either.

## 5. L-2 (LOW) — the reserved `_unknown` bucket → FIXED (both halves)

- `practice_ui.lua:1099` + `:1383-1385` — the attempt is recorded on the STATS side
  under the SAME reserved key the pure progress module uses (`_unknown`), so the
  merged row is coherent (the progress side's attempts next to a real accuracy, not
  a fabricated 0.0%).
- `practice_progress_ui.lua:53` + `:248` — the bucket gets a display name
  ("Unknown drill") instead of the raw key.

## 6. L-5 (LOW) — the write throttle was overstated → FIXED (the header only)

The write SHAPE is unchanged (it is what makes the logout flush land). The module
header now states the real contract:

- `practice_ui.lua:935-947` — the profile KEY is replaced at session end, at a
  level-up and at most once every `PROGRESS_SAVE_INTERVAL` seconds; the throttle
  decides how often the key is SWAPPED, never how current the data is (the wrapper
  holds REFERENCES to the live tables, so the profile always mirrors the live
  state). Durability is the CLIENT's: the SavedVariables are serialised at logout.
- `practice_ui.lua:1024-1028` and `:1187-1191` — the two inline comments that repeated
  the same claim.

---

## 7. FILED PINS — for the sibling lane that owns `tests/practice_ui_state.lua`

**These pins are NOT in the repo.** `tests/practice_ui_state.lua` is another lane's
file, so the pins below are filed here for that lane to paste in. They were PROVED
on a `/tmp/opencode` copy of the tree (the copy carries the fixes + the pins): the
unmutated copy PASSES (1637 checks) and every mutant below dies.

Paste them into `tests/practice_ui_state.lua` **before** the final
`if failures == 0 then ... end` block:

```lua
--=========================================================================================
-- 26i) H2 (progression audit 2026-10-20): the daily cap's swallow is REPORTED.
--
-- The detection was already in record_progress_attempt (a grade that earns points but
-- moves nothing means the cap swallowed the whole award), but the only consumer was
-- the M4 notice, gated on "no calendar day". With a VALID day the swallow was
-- COMPLETELY silent: the badge showed no "+N XP", the XP bar stopped, the level
-- stopped, the score kept counting and the player was told NOTHING - for every
-- player, every day, after ~3 attempts on a drill. The notice is now per DRILL per
-- DAY.
do
    local function cap_notices(prints)
        local n = 0
        for _, line in ipairs(prints) do
            if line:find("XP cap", 1, true) ~= nil then n = n + 1 end
        end
        return n
    end

    local b = build({ with_db = true, clock_epoch = 1790000000 })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    eq(cap_notices(F.prints), 0, "H2: nothing is printed before the cap bites")
    -- Three A grades fill the drill's daily cap (3 x its median attempt XP = 240);
    -- the fourth award is swallowed whole.
    for _ = 1, 6 do
        u.record_graded_attempt(T, "A")
    end
    local scope = F.profile_store.practice.progress.classes.PALADIN
    eq(scope.xp, 240, "H2: the capped drill earns its capped XP")
    eq(cap_notices(F.prints), 1, "H2: the capped drill prints the notice once")
    -- Once per drill per day: another attempt on the same day prints nothing.
    u.record_graded_attempt(T, "A")
    eq(cap_notices(F.prints), 1, "H2: the notice is printed once per drill per day")
    -- The next calendar day resets the cap, and the cap bites again (and the player
    -- is told again).
    F.day = "2026-10-21"
    for _ = 1, 4 do
        u.record_graded_attempt(T, "A")
    end
    eq(cap_notices(F.prints), 2, "H2: the notice fires again on the next day")
    u.stop(T)
end

--=========================================================================================
-- 26j) M1 (progression audit 2026-10-20): a saved blob a NEWER build wrote is
-- protected, but the refusal was SILENT and the logout flush reported success while
-- nothing was written.
--
-- The player keeps practising - the badge climbs, the level moves, the XP accrues -
-- and at the session end nothing is saved and nothing is said. The guard sees no
-- error, so /st diag stays clean. The refusal now prints a notice (once per
-- session) and the flush reports the WRITE, not the close.
do
    local newer = { schema_version = 99, progress = { classes = {} }, stats = {} }
    local b = build({ with_db = true, practice_blob = newer, clock_epoch = 1790000000 })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    check(#F.prints > 0, "M1: the newer blob prints a refusal notice")
    local refused = false
    for _, line in ipairs(F.prints) do
        if line:find("not being saved", 1, true) ~= nil then refused = true end
    end
    check(refused, "M1: the refusal notice names the dead end")
    local prints_after = #F.prints
    u.record_graded_attempt(T, "A")
    eq(#F.prints, prints_after, "M1: the refusal notice is printed once per session")
    eq(F.practice_writes, 0, "M1: the newer blob is never written over")
    -- The flush reports the WRITE: a session whose blob a newer build owns closed
    -- cleanly and reported success while NOTHING was written.
    eq(u.flush_progress_session(T), false, "M1: the flush reports that nothing was written")
    eq(F.practice_writes, 0, "M1: the flush wrote nothing")
    u.stop(T)
end

--=========================================================================================
-- 26k) L2 (progression audit 2026-10-20): the reserved "_unknown" drill bucket is
-- recorded on BOTH sides, so the merged row is coherent (the progress side's
-- attempts next to a real accuracy, not a fabricated 0.0%).
do
    local b = build({ with_db = true })
    local u, T, F = b.st.practice_ui, b.ST, b.sb
    u.init(T)
    F.clock = 0
    u.start(T)
    -- An attempt with no usable drill id lands in the reserved bucket.
    u.progress_drill_key = nil
    u.record_graded_attempt(T, "A")
    local blob = F.profile_store.practice
    local stats_drills = blob.stats.classes.PALADIN.drills
    local progress_drills = blob.progress.classes.PALADIN.drills
    check(type(stats_drills) == "table" and type(stats_drills._unknown) == "table",
        "L2: the stats side records the reserved bucket")
    eq(type(stats_drills) == "table" and type(stats_drills._unknown) == "table"
        and stats_drills._unknown.attempts or nil, 1,
        "L2: the reserved bucket counts the attempt")
    check(type(progress_drills) == "table" and type(progress_drills._unknown) == "table",
        "L2: the progress side records the reserved bucket")
    u.stop(T)
end
```

Notes for the sibling lane:
- the sandbox's calendar day is `sb.day` (default `"2026-10-19"`) — the day changes
  through `F.day = "2026-10-21"`, NOT through `F.epoch` (the calendar wins over the
  clock: `current_day()` reads `date` first);
- `F.practice_writes` counts the profile-key swaps (a newer build's blob is never
  swapped);
- the H-2 pin counts the prints that contain `"XP cap"` rather than counting every
  print, so an unrelated notice (a level-up) cannot break it.

---

## 8. The pins that live in the repo (`tests/practice_progress_ui_state.lua`)

- §4 (the renderers): the stats summary shows the daily streak
  (`"Daily streak " .. tostring(lmodel.daily_streak)`) and the model's own value is
  pinned (`lmodel.daily_streak == 2`).
- §5 (the stats frame): the frame's summary line carries the daily streak and the
  model's own value.
- §7 (new): the reserved `_unknown` bucket is a coherent row — the display name is
  "Unknown drill", the attempts are counted, the accuracy is the stats side's
  measurement (0.75), and the mastery table never shows the raw key.
- §8 (new): the reset's armed state EXPIRES — the arm survives inside its window,
  an expired arm is disarmed on the spot, a click on the stale "Confirm" only
  re-arms (the saved blob is untouched), and a deliberate adjacent second click
  still performs the reset.

---

## 9. Mutation proofs (`/tmp/opencode` copies)

Baseline: the tree + the filed pins → `PASS practice_ui_state.lua (1637 checks)` and
`PASS practice_progress_ui_state.lua (282 checks)`.

| # | Mutant | File | Pin that dies |
|---|--------|------|----------------|
| 1 | the cap swallow is detected but never reported (`if false and day ~= nil and ...`) | `practice_ui.lua` | H2 × 3 (the notice is printed once / once per day / again next day) |
| 2 | the flush reports success while writing nothing (`return result ~= nil`) | `practice_ui.lua` | M1: "the flush reports that nothing was written" |
| 3 | the daily streak is dropped from the stats summary | `practice_progress_ui.lua` | M4 × 2 (the summary shows the daily streak / the model's value) |
| 4 | the daily streak is dropped from the frame's summary line | `practice_progress_ui.lua` | M4 × 2 (the summary carries the daily streak / the model's value) |
| 5 | the reset's arm never expires | `practice_progress_ui.lua` | M5 × 7 (the expired arm is disarmed / the stale confirm does not wipe / the adjacent confirm still works) |
| 6 | the reserved bucket is recorded on the progress side only | `practice_ui.lua` | L2 × 2 (the stats side records the reserved bucket / it counts the attempt) |
| 7a | the refusal notice is silent at the detection point | `practice_ui.lua` | M1: "the refusal notice names the dead end" |
| 7b | the refusal notice is silent everywhere | `practice_ui.lua` | M1: "the refusal notice names the dead end" |

Every mutant was applied to a fresh copy of the tree (the tree + the filed pins) and
the matching suite was run: **8 of 8 killed**.

---

## 10. Verification state

- `bash tests/run.sh` → **41 steps, 0 failed**, luacheck `2 warnings / 0 errors in
  83 files`.
- Mid-session the harness showed 2 failures (`tests/hunter_state.lua`,
  `tests/hunter_guide_state.lua`). They were **not this lane's**: the failing checks
  MOVED between two harness runs (first the Steady rank id, then the ERA engine
  flags) while another lane (`desks/hunter-steady-family/`) was editing
  `classes/hunter.lua` and `tests/hunter_guide_state.lua`, and neither suite loads
  ANY file this lane touched (`tests/hunter_state.lua` loads
  compat/utils/hunter_window/classes-hunter/hunter_ui/hunter_guide/practice;
  `tests/hunter_guide_state.lua` loads hunter_window/hunter_guide/practice). The
  concurrent lane landed its fix and the harness is green.
- This lane's suites: `practice_progress_ui_state.lua` 282/282,
  `practice_ui_state.lua` 1623/1623 (1637/1637 with the filed pins applied on the
  /tmp copy), `main_init_state.lua` 903/903, `options_load_state.lua` 3494/3494.
- luacheck: the two warnings are pre-existing (`compat.lua:36` unused `addon_name`,
  `main.lua:81` `table.pack`). This lane's four files: `practice_ui.lua OK`,
  `practice_progress_ui.lua OK`, `main.lua 1 warning` (the pre-existing
  `main.lua:81`), `tests/practice_progress_ui_state.lua OK`. The floor was 6 warnings
  before the session and is 2 now (other lanes fixed 4); this lane added none.
- CRLF preserved on `practice_ui.lua` and `main.lua`; `practice_progress_ui.lua` and
  `tests/practice_progress_ui_state.lua` are LF (unchanged).
- No new file-scope local was added to `practice_ui.lua` (the module sits at 199 of
  Lua 5.1's 200 file-scope locals): the new state rides the `ui` table
  (`ui.UNKNOWN_DRILL_KEY`, `ui.progress_persist_notice`,
  `ui.progress_cap_notice_days`) and the new entry point is a `ui` field
  (`ui.announce_not_persistable`), not a local.

## 11. Deliberately NOT done

- The per-drill-per-day cap latch is IN MEMORY (per client session). It is not
  written to the profile: the write shape is frozen by L-5 and the reserved bucket
  belongs to the pure module. A player who relogs on the same day can see the
  notice twice — acceptable, and the notice says "once per drill per day" only in
  the sense of the session's own latch.
- The account-scope achievement evaluation (M-2), the `NO_DAY` sentinel clamp (M-3),
  `register_unlock`'s kind coercion (L-1), the account-scope drill merge (L-3), the
  unknown-grade path (L-4) and the cap's backwards-clock reopen (L-6) belong to the
  `practice_progress.lua` / `practice_stats.lua` lane. **No change was needed in
  `practice_progress.lua`**, so no filed change is owed there.
- The rulings RJ-1 (a misses-only session as a completed day) and RJ-2 (is the
  no-calendar path reachable) are untouched.
