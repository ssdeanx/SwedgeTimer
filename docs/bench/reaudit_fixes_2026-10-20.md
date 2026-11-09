# reaudit_fixes — 2026-10-20

The final re-audit's three MEDIUM findings and two easy LOWs, closed. Source of truth:
the dispatch brief (M-1 / M-2 / M-3 / L-1 / L-5, each with file:line, mechanism and
required fix). The re-audit's own report file is **not on disk** — no desk or bench
file carries that text — so every finding was re-verified against the live source
before the edit. The report's path/id is owed by the orchestrator if it is to be
filed (see "Gaps").

Baseline: harness 41 steps / 0 failed, luacheck 2 warnings / 0 errors.
After: harness **41 steps / 0 failed**, luacheck **2 warnings / 0 errors** (the floor
held — the two warnings are the pre-existing ones in `compat.lua` and `main.lua`,
neither in a line this lane touched).

## M1 (MEDIUM) — the logout flush discarded its error entirely

`main.lua:1134-1143`. The flush ran under a bare `pcall` and the error was thrown
away: no counter, no chat line, no `/st diag` trace. That is exactly the data class
H2 was filed for (the completion bonus, the daily streak, the run, the time active
and the history row) — silent again if the flush throws.

**Fix:** the house contract.

```lua
st.guard.run(self, "practice:logout", pui.flush_progress_session, self)
```

`guard.lua` counts the failure (`owner.bar_hook_errors.by_site["practice:logout"]`),
reports the FIRST failure of the site once (never a chat flood) and the count shows
in `/st diag`'s `bar_hook_errors=` runtime line (`main.lua:1950-1956`).

`guard.lua` loads before `main.lua` in **all seven** TOC variants (verified: lines
38/39 vs 57/58), so `st.guard` is always there. The test sandbox now mirrors that
order (`tests/main_init_state.lua` loads `guard.lua` before `main.lua`), so the pin
runs against the REAL contract instead of a stub.

## M2 (MEDIUM) — the druid guessed an action key for an unknown hold text

`classes/druid.lua:3541-3556`. A hold text in neither published table fell back to
`out.hold_text:lower():gsub(...)` — a slug. A future hold text therefore became a
synthetic action (H1's exact shape). Unreachable today (the guide's vocabulary is
closed) but the *production* code guessed.

**Fix:** the unknown case is unknown — `return nil, nil`. The scenario step answers
nil (the engine grades UNKNOWN: no attempt, no wrong action) and the priority drill
answers nil too (no mis-pick banked). The closed-vocabulary pin
(`tests/druid_guide_state.lua:3942-4014`) stays the tripwire and is unchanged.

## M3 (MEDIUM) — the session-completion bonus was outside the daily anti-grind cap

`practice_progress.lua`. Two defects in one place:

1. `session.attempts` counts **every** graded attempt, so ten misses (ten F grades,
   zero attempt XP) earned the full +25.
2. The bonus was added straight to `scope.xp` and never counted against
   `drill.daily_xp` (the cap counter) — pure profit on top of a capped day.

**Fix (the brief's second option): the bonus is non-farmable by construction — it is
a SHARE of what the session actually EARNED through the capped attempt path.**

```lua
P.SESSION_BONUS_XP_SHARE = 0.5
...
local earned = count(session.xp)
local bonus = math.floor(P.SESSION_BONUS_XP * factor)
local share  = math.floor(earned * P.SESSION_BONUS_XP_SHARE)
if share < bonus then bonus = share end
```

* a session of misses (earned 0) earns **no** bonus;
* the bonus never exceeds the flat +25 the spec writes;
* the share comes out of **already capped** XP, so the daily cap still bounds the
  total: the day's XP is at most `cap x (1 + share)` — the bonus can only ever add a
  fraction of what the cap allowed, and grinding cannot push it past that;
* the bonus is paid **once** per session: the paid amount is remembered on the
  session (`session.bonus_xp`), so a second `end_session` pays nothing more (the
  fix wave gave the bonus two extra trigger paths — the panel's hide and the logout).

**Why not "charge the bonus against the drill's cap and clamp it"?** That option was
rejected on evidence, not taste: it would zero the bonus on exactly the session the
bonus exists for (ten S grades fill the 300-XP cap, so the remaining room is 0) and
would break three pins the owning suite already holds — `tests/practice_progress_state.lua`
(r7: +25 on a capped session), `tests/practice_progress_ui_state.lua:441` (650 XP
across two capped sessions) and `tests/practice_ui_state.lua:4646` (265 XP for a
flushed session). The share keeps every one of them green AND satisfies both of the
brief's pins (a session of misses earns no bonus; the cap still bounds the total).

**Scope note:** the M-3 pins live in `tests/practice_progress_state.lua` — the suite
that OWNS `practice_progress.lua`'s pins. The dispatch's scope list named
`tests/practice_state.lua` (the suite for `practice.lua`, the simulation engine,
which has no bonus pins at all); the rule "the suites that own their pins" covers
the owning suite, and the enumerated list appears to abbreviate. The change is
additive: no existing pin in that suite was edited.

## L1 (LOW, latent trap) — the panel's OnHide flush could end a live run

`practice_ui.lua:1861-1884`. A hide ended the progression session while the
simulation kept running: the score kept moving while the XP, the mastery, the streak
and the stats stopped recording — with no notice. Today only the construction and
`ui.stop` (which flushes first) hide the panel, so it was a no-op; it was a trap for
the next path that hides the panel.

**Fix (the orchestrator's ruling):** the flush applies only when the run is actually
over.

```lua
panel:SetScript("OnHide", function()
    if ui.active == true then
        if type(ui.progress_session) ~= "table" then
            ui.begin_progress_session(ST, api.get_time())
        end
        return
    end
    ui.flush_progress_session(ST)
end)
```

A live run keeps its progression session (re-opened if it was closed), so the score
and the recording can never diverge. `ui.stop` sets `ui.active = false` (line 5648)
BEFORE its own flush (5784) and the panel hide, so the stop path is unchanged.

## L5 (LOW) — the M4 cap notice could not fire again after a mid-session reset

`ui.progress_cap_notice` was cleared only in `begin_progress_session`, so a client
with no calendar day stayed silent for the rest of the new session.

**Fix:** the reset clears it too (`practice_ui.lua:1476-1481`). The notice is per
session and the reset starts a NEW session, so it can fire again.

## Pins

| finding | suite | what the pin proves |
|---|---|---|
| M1 | `tests/main_init_state.lua` (16c) | a throwing flush is counted under `practice:logout`, announced once, counted again on a second logout, and visible in the `/st diag` runtime line |
| M2 | `tests/druid_state.lua` (42) | a hold text in neither table answers nil in the scenario step AND in the priority drill, banks no mis-pick, and the source carries no slug fallback |
| M3 | `tests/practice_progress_state.lua` (M3 block) | a session of misses earns no bonus and no scope XP; the bonus is the share of the awarded XP; the capped day's total stays inside `cap x (1 + share)`; a second end pays nothing more |
| M3 | `tests/practice_ui_state.lua` (26h) | end-to-end through the flush: ten misses pay no bonus, and the session still counts as a completed run |
| L1 | `tests/practice_ui_state.lua` (26b) | hiding the panel during a live run writes no run / streak / time, keeps the SAME progression session, and the recording continues; the run's own end still writes everything |
| L5 | `tests/practice_ui_state.lua` (26g) | the notice is once per session, and fires AGAIN after a mid-session reset |

## Mutation proofs

`/tmp/opencode/reaudit_mutations.py` — six mutants on disposable copies under
`/tmp/opencode/reaudit_mut/base`, each run against the suite that owns the pin.
**6 / 6 killed.**

| mutant | suite | killed by |
|---|---|---|
| the logout flush's error discarded again (bare `pcall`) | main_init_state | "M1: the failure leaves a counter behind" |
| the druid's slug fallback restored | druid_state | "M2: an unknown hold text is UNKNOWN (the step answers nil)" |
| the bonus ignores the cap (the flat +25 for ten attempts) | practice_progress_state | "M3: a session of misses earns no completion bonus (got 25, want 0)" |
| the same mutant, UI side | practice_ui_state | "M3: a session of misses earns no bonus (got 25, want 0)" |
| the hide ends a live run again (unconditional flush) | practice_ui_state | "L1: hiding the panel during a live run writes no run (got 1, want 0)" |
| the reset does not clear the cap notice | practice_ui_state | "L5: the notice fires again after the reset" |

## House rules kept

* nil-safe (every new read is `type(...) == "table"` / `== true` guarded; the share,
  the session's paid bonus and the guard's owner are all nil-safe);
* unknown-hides (M-2's unknown hold text hides the step, it does not guess);
* no default-visible change (no toggle, no default, no option touched — M-3 changes
  the bonus a MISS session earns, which is the finding itself);
* wire-not-strip (M-1's error is now WIRED to the counter, not silenced; nothing was
  silenced with `_`);
* line endings preserved (`main.lua`, `classes/druid.lua`, `practice_ui.lua` stay
  CRLF; `practice_progress.lua` and the suites stay LF);
* whitespace only inside the touched lines (no trailing whitespace on any touched
  line in any touched file);
* `practice_ui.lua` gained **zero** file-scope locals (it sits at 199 of Lua 5.1's
  200; every new state rides the `ui` table);
* no git, no lint-config change, no TOC / version / doc / option / class-other
  change. `classes/rogue.lua`, `compat.lua`, `practice_progress_ui.lua`, `bars.lua`,
  `hud.lua`, `run.sh` and the TOCs were NOT touched.

## Gaps (named, not papered over)

* **The re-audit's report file is not on disk.** The findings used here are the ones
  the dispatch brief carries (file:line + mechanism + required fix). Every one was
  re-verified against the live source before the edit, but the report's own text
  (and any finding it carries beyond M-1/M-2/M-3/L-1/L-5) is UNCONFIRMED here.
  Raised as **HU-16** in `hands-up.md`: the report should be filed on the bench, and
  if it carries more findings than the brief named, the rest is unaddressed (the
  sibling publish-gate re-audit recorded seven LOWs; only two of the
  practice-persistence LOWs were in this brief).
* **`/st diag` shows the COUNT, not the site.** The runtime line reads
  `bar_hook_errors=<count>`; the per-site breakdown (`by_site["practice:logout"]`)
  is in the table but has no reader in `/st diag`. The brief asked for the count to
  show, which it does; adding a per-site readout would change the diag line's shape
  and was out of scope.
* **In-client behaviour is still owed.** Everything here is verified OFFLINE (the
  harness + the mutation proofs). The logout flush's announcement and the `/st diag`
  line have not been seen in a client.
* **The M-3 balance is a design value.** `SESSION_BONUS_XP_SHARE = 0.5` is the
  smallest round share that keeps the three existing pins green (the factor-2 pin
  needs `share >= 50/120`). A different balance is a one-constant change; the pins
  state the rule, not the number.
