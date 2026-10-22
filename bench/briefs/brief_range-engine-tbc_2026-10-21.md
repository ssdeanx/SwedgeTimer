# Brief: range engine on TBC (2026-10-21) — no protected calls, no quarantine cascade

**Operator in-client report, 2026-10-21 (TBC Anniversary, HUNTER):** "the bars started
working at first. But then when i cast steady shot on tbc. the bar came up but nothing
happened. Then they stopped working. Also i dont see the distance bar".

Client evidence (the same BugGrabber dump):
- `ADDON_ACTION_BLOCKED ... protected function 'check_interact_distance()'` with the stack
  `compat.lua:954` <- `hunter_ui.lua:877 update_range_helper` <- `hunter_ui.lua:1510
  update` <- `hunter_ui.lua:1539 on_bar_update` <- `classes/hunter.lua:909` <-
  `guard.lua:178 run` <- `bars.lua:693`.
- The operator's range state then dies for the session: `main.lua` `rf_update` wraps the
  poll in a pcall and, after `RF_MAX_POLL_FAILURES = 3` failures, calls
  `disable_range_checking()` (main.lua:1870-1885) — so `in_melee_range` /
  `in_ranged_range` / `target_min_range` / `target_max_range` stop updating within ~0.15 s.
- The class hook dies too: `guard.run` quarantines a site after
  `st.guard.QUARANTINE_THROWS = 25` throws (guard.lua), and the hunter's optional range
  helper throws EVERY FRAME inside `ui.update` — so after 25 frames the whole
  `class:HUNTER:on_bar_update` site is quarantined: cast bar, rapid fire, aspects, range
  helper, all of it. That is "the bar came up but nothing happened, then they stopped
  working".

**A parallel lane owns the compat-side fixes** (`api.CheckInteractDistance` is being
DELETED from `compat.lua`; `api.is_spell_known` is being made throw-proof). Do NOT edit
`compat.lua` or `tests/spell_known_state.lua`.

## Why this happened (own it in the record)

An earlier fix replaced the blocked `IsItemInRange` path with the "interaction band"
ladder. On this client the interaction bands are themselves a protected function, so the
fix moved the failure one call sideways. The only distance source that is **not** a
protected range/inspect function is `UnitDistanceSquared` — already wrapped, probed and
normalised as `api.UnitDistance(unit)` (compat.lua:966-990): exact yards, `nil` when the
client cannot answer.

## Required

### R1. `main.lua` — the range state comes from exact yards, not from LibRangeCheck
`init_range_finders` + `rf_update` (main.lua:1770-1890) currently build
`LRC:GetHarmMaxChecker(...)` / `GetHarmMinChecker(...)` and call `LRC:GetRange("target")`
every 50 ms. With item/spell checkers suppressed, those resolve to the **interact
checkers** — the protected call. Replace the source:
- Read `api.UnitDistance("target")` once per poll. `nil` = unknown (never a guess, never a
  zero).
- `in_melee_range = yards ~= nil and yards <= MELEE_RANGE` (5 yd: the vendored lib's own
  melee checker distance, `MeleeRange`-based; cite it in the comment).
- `in_ranged_range = yards ~= nil and yards <= RANGED_RANGE and not in_melee_range`
  (30 yd, hunter 35 yd — the values the current code already uses; keep them, but as one
  named constant pair, not two copies).
- `target_min_range, target_max_range` must keep feeding `bars.lua`'s range text
  (`%s - %s`): set them from the exact reading (`floor` / `ceil` of yards) so the text stays
  truthful and never invents a band. Also publish the exact reading as `ST.target_distance`
  for consumers that want one number (`weave_range.lua` already prefers
  `api.UnitDistance`, so it needs no change — do not edit it).
- The range state must NO LONGER depend on LibRangeCheck being loaded: today an
  `lrc_unavailable` (init deadline / zero checkers) returns early and kills the poll.
  Exact yards need no library. Keep the library for whatever else uses it, but the
  melee/ranged/text state must work when LRC is missing or disabled. Update `/st diag`'s
  wording only if it now lies (keep the counters).
- Keep the poll's failure/backoff structure, but a `nil` reading is NOT a failure (it is
  "unknown", the ordinary state with no target).

### R2. `Libs/LibRangeCheck-2.0/.../LibRangeCheck-2.0.lua` — build no interact checkers
`createCheckerList` adds `checkers_Interact[index]` whenever the item/spell lists produced
nothing (line ~641-648), and `minRangeCheck` falls back to `checkers_Interact[4]/[3]`
(line ~860-868). On this client that is the protected call, from the library itself.
- Suppress the interact checkers the same way the item/spell checkers are already
  suppressed, with a comment carrying the 2026-10-21 in-client evidence (protected function
  on TBC Anniversary).
- `minRangeCheck` must be `nil`-safe (a `nil` min-check leaves a checker list with no
  min check, which the library already handles).
- The library must then make ZERO calls to `CheckInteractDistance` on every family. Any
  remaining caller (`GetRange`, `GetHarmMaxChecker`) must return `nil` rather than call it.

### R3. `hunter_ui.lua` — the distance bar, without the protected call, and no cascade
- `update_range_helper` (hunter_ui.lua:840-897) must derive `sweet` from
  `api.UnitDistance("target")` (the reference's index-3 band is the ~10 yd "just outside
  melee" band — name the constant and cite it). No `api.CheckInteractDistance` call:
  that API is being deleted.
- The helper must actually SHOW when a target is attackable and any probe answers
  (`helper:Show()`), and hide when disabled, without a target, or when every probe is
  unknown. The operator reported it missing; the current code never reaches `Show()`
  because the throw aborts it.
- **Isolation (the cascade fix):** `ui.update` (hunter_ui.lua:1494-1518) calls ten
  `update_*` sub-features in a row, all inside ONE guard site. Wrap each sub-feature in
  its own `st.guard.run` site (e.g. `"hunter_ui:range_helper"`, `"hunter_ui:cast_bar"`, ...)
  so a throw in one costs only that feature and NEVER quarantines the whole class hook.
  Keep the existing once-per-site reporting and the quarantine threshold (they are the
  session protection, not the problem).
- No behaviour change for a non-hunter class (this file only runs for hunters).

### R4. `main.lua` — a class module must not be able to abort init
`post_init` calls `self[self.player_class].post_init(self)` unguarded (main.lua:830-832).
A class module that throws there (a bad spell probe, a missing global) aborts the rest of
`post_init` AND the caller `init_libs`. Wrap it in `st.guard.run` with the site
`"class:" .. tostring(self.player_class) .. ":post_init"`, so a class failure is counted,
reported once, and the addon still finishes initialising. Same treatment for any other
unguarded class-module hook you find on that path (FILE anything outside `main.lua`).

## Proof required (offline, mutation-proofed — the operator asked for tests, not probes)

NEW suite `tests/range_source_state.lua`, modelling the failing client:
- `UnitDistanceSquared` returns `(yards^2, true)` for a target at a chosen distance;
- `CheckInteractDistance` is a THROWING global that RECORDS every call;
- the vendored LibRangeCheck is loaded as shipped.
Pin:
1. `init_range_finders` + several `rf_update` runs make **zero** `CheckInteractDistance`
   calls (the recorder stays empty) and never take the disable path
   (`lrc_unavailable`/`rf_failure_count` stay clean).
2. The state follows the yards: 4 yd -> melee only; 8 yd -> neither melee nor (if the
   hunter budget is 35) still ranged; 20 yd -> ranged; 40 yd -> neither; `nil`/unchecked ->
   unknown (never melee, never a guess).
3. The range text fields are fed (`target_min_range`/`target_max_range` numbers, and
   `ST.target_distance` equals the exact reading).
4. The range state still works with LibRangeCheck ABSENT (init-deadline path).
5. `hunter_ui.update_range_helper` shows the helper with a target and a reading, hides it
   with none, and calls no protected function.
6. **Cascade proof:** make one sub-feature throw on every call inside `ui.update`; the
   OTHER sub-features still run for every frame (their call counters keep rising) and the
   class hook site is never quarantined.
7. `main.lua`'s class `post_init` throw is isolated: `init_libs` still completes, the
   guard records the site once.

Update the existing suites that pin the old source (at least `tests/lrc_guard_state.lua`,
`tests/main_init_state.lua`, `tests/hunter_state.lua`; find any others that assert the
checker funcs or `LRC:GetRange`). Then `bash tests/run.sh` green with the exact numbers,
`luacheck` at the standing floor (2 warnings / 0 errors), and MUTATION PROOFS on a
`/tmp/opencode` copy (never the working tree) for every new guard: remove the guard, the
suite must fail. FILE the new `tests/run.sh` line — do not edit run.sh (orchestrator owns
it).

## Scope / write permission
- YOU OWN: `main.lua`, `hunter_ui.lua`,
  `Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua`,
  `tests/range_source_state.lua` (new), `tests/lrc_guard_state.lua`,
  `tests/main_init_state.lua`, `tests/hunter_state.lua` (and any other suite that pins the
  old checker source — find them).
- YOU MUST NOT edit: `compat.lua` (the parallel lane), `classes/**`, `bars.lua`, `hud.lua`,
  `weave_range.lua`, `tests/spell_known_state.lua`, `tests/run.sh`, `Libs/` other than the
  LibRangeCheck file named above. FILE anything else with file:line.
- **Context discipline:** do NOT read whole files. `main.lua` is 79 KB, `hunter_ui.lua`
  ~60 KB, the library ~40 KB. Targeted greps and small `sed -n` reads only. A previous lane
  died silently from a context blowup.
- No git. No lint-config changes. Preserve file endings (main.lua, hunter_ui.lua and the
  library are CRLF — keep them CRLF). Warnings traced, never silenced with `_`. No new
  protected/secure calls.

## Mechanics (skills — CALL these tools, in order)
`bench-read` (desk journal + `bench/lessons.md` + the bench, journals before artifacts) ->
`desk-open desks/range-engine-tbc/` -> `desk-journal` -> `signal-write`.

## Deliverable
`bench/range_engine_tbc_2026-10-21.md` (confirm absent before writing): each requirement
with what changed, the exact-yard constants and their citations, the suite numbers, the
mutation list, the run.sh line filed, everything you left, and every UNCONFIRMED item
(especially what still needs in-client confirmation on TBC Anniversary).

## Validation owner
The orchestrator (re-runs the harness, re-reads the diff, hands the operator the copy list
and the in-client checklist).
