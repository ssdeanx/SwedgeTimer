# Range engine on TBC: exact yards, zero interact checkers, per-feature isolation

Lane `range-engine-tbc`, 2026-10-21. Brief:
`bench/briefs/brief_range-engine-tbc_2026-10-21.md`.

**Offline proof only.** No client was loaded by this lane. In-client confirmation on
TBC Anniversary 2.5.x (hunter) is owed by the operator — checklist in §8.

Scope shipped: `main.lua` (R1, R4), the vendored
`LibRangeCheck-2.0/LibRangeCheck-2.0.lua` (R2), `hunter_ui.lua` (R3), the new
`tests/range_source_state.lua` and the four existing suites that pinned the old source.
`compat.lua`, `classes/**`, `bars.lua`, `hud.lua`, `weave_range.lua`,
`tests/spell_known_state.lua` and `tests/run.sh` were **not** edited by this lane.
No git. Line endings preserved: `main.lua` and the library stay CRLF, `hunter_ui.lua`
stays LF.

## 1. The failure this lane closes

The previous fix replaced the blocked `IsItemInRange` path with the interaction-band
ladder. On TBC Anniversary the interaction bands are themselves a protected function:
`CheckInteractDistance` raised `ADDON_ACTION_BLOCKED` every frame from
`hunter_ui.lua update_range_helper`, and after 25 throws `guard.run` quarantined the whole
`class:HUNTER:on_bar_update` site — "the bar came up but nothing happened, then they
stopped working". The range poll's own dead-man then disabled range state for the
session. Both cascades are removed by R1/R3; R2 removes the same protected call from the
library; R4 stops a class module from aborting init.

## 2. R1 — `main.lua`: range state from exact yards, not from LibRangeCheck

| file:line | change |
|---|---|
| `main.lua:1764-1786` | New range section header + the one constant trio: `RF_MELEE_RANGE = 5`, `RF_RANGED_RANGE = 30`, `RF_HUNTER_RANGED_RANGE = 35`. The old two-copy 30/35 literals are gone; the header states where 5/30/35 come from. |
| `main.lua:1788-1793` | `ST:ranged_range_yards()` — hunter 35, everyone else 30. |
| `main.lua:1807-1827` | `ST:update_range_state()`: **one** `api.UnitDistance("target")` per poll (`:1811`). `nil` clears everything and returns (`:1813-1819`). `in_melee_range = yards <= 5` (`:1820`), `in_ranged_range = yards <= budget and not in_melee` (`:1822`), `target_min_range = floor(yards)`, `target_max_range = ceil(yards)` (`:1825-1826`), `self.target_distance = yards` (`:1812`). |
| `main.lua:1829-1837` | `init_range_finders` seeds the published fields (`target_distance`, both flags, both text fields) and starts the poll. No checker construction, no `LRC:GetHarm*Checker`, no `LRC:GetRange`. |
| `main.lua:1843-1877` | `rf_update` keeps the failure/backoff structure (`RF_MAX_POLL_FAILURES = 3`, `RF_MAX_RETRY_DELAY = 0.4`). A `nil` reading is a successful poll (unknown), not a failure: `update_range_state` returns normally, `rf_failure_count` resets, the loop continues. |
| `main.lua:1795-1805` | `disable_range_checking` is now only the poll dead-man (`rf_disabled` + one-time notice). It no longer rewrites `lrc_unavailable`, so `/st diag`'s `lrc=fallback` keeps its single meaning: "LRC missed the init deadline". |
| `main.lua:370-405, 724-727` | `init_libs` no longer disables range checking when LRC declined; the late `CHECKERS_CHANGED` callback clears `lrc_unavailable` (`:378`) without re-running init. The flags now feed only the `/st diag` `lrc=` line, which remains truthful. |
| `main.lua:2052-2054` | `/st diag` runtime line keeps counters: `rf_failures=`, `rf_disabled=`, `rf_disabled_after_failures=`; the retired `rf_checker_laps=` / `rf_checker_exhausted=` fields are gone because the checker-lap re-arm branch is gone. |

No `LRC:GetRange`, `LRC:GetHarmMaxChecker` or `LRC:GetHarmMinChecker` call remains in
`main.lua` (`grep 'LRC:' main.lua` → no call sites; the object is used only for the
`CHECKERS_CHANGED` readiness callback at `main.lua:373`). `api.UnitDistance` is the only
distance source, and compat's wrapper (`compat.lua:1023-1039` in the current tree)
pcall-wraps `UnitDistanceSquared`, returns `nil` when the global is absent, the reading is
unchecked, secret, non-numeric, negative or non-finite.

**Replacement-source citations** (orchestrator-provided 2026-10-21; not re-verified by
this lane):

- `Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua:1069`
  (`classic_anniversary`) calls `UnitDistanceSquared(frame.displayedUnit)` from ordinary
  insecure unit-frame Lua and trusts it only when `checkedDistance` is true → the
  replacement source is addon-callable on TBC. `compat`'s `api.UnitDistance` normalises
  exactly that (orchestrator's matrix cites `compat.lua:966-990`; the compat lane's later
  edits put the same wrapper at `:1023-1039`).
- `CheckInteractDistance` is called only from Blizzard's secure popup code —
  `Blizzard_UnitPopupShared/UnitPopupSharedUtils.lua:194` (`classic_anniversary`). The
  addon block is runtime/client-side (the operator's 2026-10-21 `ADDON_ACTION_BLOCKED`
  log), **not** a documented API restriction; the in-client log is the evidence for the
  protection, the branch for the call sites.

**Constant citations.**
- `5` yd: the vendored library's own item ladder keys range by yards;
  `LibRangeCheck-2.0.lua:300-304` has `[5] = { 8149 --[[ Voodoo Charm]], ... }`,
  i.e. the library's 5-yard melee band. The library's `local MeleeRange = 2` is its
  **spell** range floor — a different quantity — so it is deliberately not the source
  (stated in `main.lua:1777-1780`).
- `30` / hunter `35`: carried unchanged from the pre-change implementation exactly as the
  brief specifies (classic 30 yd spell budget; hunter shots reach 35 yd).
- `nil` is never coerced: both flags are `false`, both text fields `nil`,
  `ST.target_distance` `nil`. Pinned at `tests/range_source_state.lua:1108-1125`.

## 3. R2 — vendored `LibRangeCheck-2.0`: builds no interact checkers

`Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua` (CRLF preserved):

| file:line | change |
|---|---|
| `:50-61` | `VENDORED CHANGE (2026-10-21)` header block: `CheckInteractDistance` is protected on TBC Anniversary 2.5.x, a block is not a catchable Lua error, the addon now reads exact yards, the interact ladder and its min-range fallback are retired. Revert = restore from upstream. |
| `:73-74, :520-521, :626-629, :845-850` | The interact-band tables, `checkers_Interact`, the interact fallback in `createCheckerList` and the interact branch of `minRangeCheck` are deleted, each with the dated evidence comment (comment mentions only; no call remains). |
| `:584` | `createCheckerList(spellList, itemList)` — the third (interact) parameter is gone; every caller updated (`:748-750`, `:853-859`). |
| `:634-640` | `getRange(unit, checkerList)` returns `nil` for `nil` or empty list before touching `checkerList[0]` / `[#+1]`. |
| `:788-850` | `minRangeCheck` stays `nil` when neither the item source nor the class-spell source exists; the retired interact fallback left no branch behind. |
| `:892-932` | `GetHarmMinChecker`, `GetHarmMaxChecker` (and the friend/misc siblings) delegate to `getMinChecker`/`getMaxChecker`, which return nothing on an empty list. `GetRange` on an empty list returns `nil` via `:634-640`. |

Static result: `grep -o 'CheckInteractDistance(' <lib> | wc -l` → **0**, on every family
(the file is the same bytes everywhere; there is no branch left that could call it).

## 4. R3 — `hunter_ui.lua`: sweet spot from yards, no cascade

| file:line | change |
|---|---|
| `hunter_ui.lua:51-61` | Constants `RANGE_HELPER_MELEE_RANGE = 5`, `RANGE_HELPER_SWEET_SPOT = 10`, with the band rule `5 < yards <= 10` and the reason for the lower bound (a 4 yd reading with a dead melee spell probe must not be labelled "sweet"). `CheckInteractDistance` is gone from this file; `api.CheckInteractDistance` does not exist. |
| `hunter_ui.lua:891-898` | `sweet` comes from `api.UnitDistance("target")`: `nil` when the client cannot answer (unknown → cannot make the helper show), `false` when known to be outside the band. |
| `hunter_ui.lua:855-915` | Show/hide contract: hide when the toggle is `false` (`:857`), hide without an attackable target (`:879`), hide when **every** probe is unknown (`melee == nil and sweet == nil and ranged == nil`, `:900-905`), otherwise `helper:Show()` (`:913-915`). The old code never reached `Show()` because the protected call threw first. |
| `hunter_ui.lua:1527-1542` | Ten `st.guard.run` sites — one per `update_*` sub-feature: `cast_bar`, `cast_zone`, `target_warning`, `range_helper`, `rapid_fire`, `pet_badges`, `oom_viper`, `lnl_badge`, `trap_badge`, `aspect_icon`. A throw costs one feature, never the class hook. Existing once-per-site reporting and `st.guard.QUARANTINE_THROWS = 25` are unchanged. `ui.sync_melee_anchor(self)` (layout sync, not an `update_*` feature) stays outside the sites. |

Non-hunter behaviour: this module only runs for hunters (`classes/hunter.lua` drives it);
no shared path changed.

## 5. R4 — `main.lua`: class `post_init` cannot abort init

`main.lua:822-838`: `self[self.player_class].post_init(self)` runs inside
`st.guard.run` with site `"class:" .. tostring(self.player_class) .. ":post_init"`.
The body is a closure (`function(addon) local class_module = addon[addon.player_class];
class_module.post_init(addon) end`) so the class name is read once and the call shape
stays visible to `tests/wiring_check.lua`'s `.post_init(` classifier. A throw is counted,
reported once, and quarantined after 25 — `init_libs` continues to the shared widgets
(frame lock state, bar visibility, TBC aura poll) and the readiness self-report.
No other unguarded class-module hook was found on the `post_init` path; nothing outside
`main.lua` needed filing.

## 6. Proof — suites

New: `tests/range_source_state.lua` — **148 checks PASS**. It models the failing client:
`UnitDistanceSquared` answers `(yards^2, true)` for a chosen distance; the global
`CheckInteractDistance` is a recording thrower; the vendored library is loaded as shipped
(it also re-loads the real library file for the empty-list block, `:919-1027`).

| brief item | test block | result |
|---|---|---|
| 1. zero protected calls, no disable path | `:1030-1059` — init + repeated `rf_update`; `interact_calls == 0`; `lrc_unavailable` false; `rf_failure_count` 0; LRC checker consumers never consulted | PASS |
| 2. state follows exact yards | `:1061-1134` — 4/5/5.5/8/20/30/31/40 yd + hunter 8/34/35/36 + `nil` + unchecked (`checked = false`) | PASS |
| 3. text fields + `ST.target_distance` | `:1134-1159` — floor/ceil numbers; distance equals the exact reading; `nil` clears all | PASS |
| 4. LRC absent (init-deadline path) | `:1160-1185` — poll keeps producing state after `lrc_unavailable` | PASS |
| 5. helper shows/hides, no protected call | `:1186-1218` — show with target+reading; hide with no target; hide when all probes unknown; recorder empty | PASS |
| 6. cascade proof | `:1219-1261` — one sub-feature throws every frame; the other features' counters rise every frame; class hook site never quarantined | PASS |
| 7. class `post_init` isolation | `:1262-1300` — `init_libs` completes, readiness self-report runs, site counted once and reported once | PASS |

Updated suites (all green, exact `lua5.1 tests/<file>.lua` counts):

| suite | checks | what changed |
|---|---|---|
| `tests/main_init_state.lua` | 952 | deadline/late-recovery expectations (range no longer disabled by LRC), `rf_update` dead-man rewritten around `api.UnitDistance` (throw → disable; `nil` → not a failure), checker-cap block removed, class `post_init` guard expectation |
| `tests/hunter_state.lua` | 1738 | `UnitDistanceSquared` fixture + `calls.distance`; range-helper section rewritten with yards bands (4/7/10/11 yd + all-unknown hide); `guard.lua` loaded before `hunter_ui` |
| `tests/bars_state.lua` | 907 | `UnitDistanceSquared` fixture replaces the `CheckInteractDistance` stub; `target_yards = 20` default; sweet at 7 yd |
| `tests/lrc_guard_state.lua` | 141 | rewritten to pin the vendored file's zero interact calls on every profile, 2-arg `createCheckerList`, empty-list `nil`, `minRangeCheck` nil-safe |

Harness: `bash tests/run.sh` → **46 steps, 0 failed** (the two newly registered suites
are `tests/spell_known_state.lua` and `tests/range_source_state.lua`). `tests/toc_check.lua`
passes — 1082 checks, 0 failures; its registry view reports **44 registered / 44 on disk**
(every suite accounted for, each run exactly once). Luacheck: **2 warnings / 0 errors in
88 files** — the standing floor, unchanged.

The `tests/run.sh` line this lane owed is live at `tests/run.sh:94`:

```
run "lua5.1 tests/range_source_state.lua" lua5.1 tests/range_source_state.lua
```

This lane did not edit `run.sh` (orchestrator owns it); the line was filed and is now
present, so no request remains open.

## 7. Mutation proofs (9/9 killed, `/tmp/opencode` copy only)

Copy: `/tmp/opencode/range-engine-mut2/tree` (working tree minus `Media`, `docs`, `.git`).
Each mutation is applied to exactly one line/block, the pinning suite is run, the file is
restored byte-for-byte from the working tree (`cmp` verified after every case). Full
transcript: `bench/range_engine_tbc_2026-10-21.proof.txt`.

| # | mutation | suite | result |
|---|---|---|---|
| M1 | `main.lua:1811` `api.UnitDistance("target")` → constant `20` | range_source_state | KILLED — 21/148 checks failed |
| M2 | `main.lua:1820` `<= RF_MELEE_RANGE` → `<` | range_source_state | KILLED — 2/148 (5 yd boundary) |
| M3 | `main.lua:1822` drop `and not in_melee` | range_source_state | KILLED — 2/148 (4 yd also ranged) |
| M4 | `hunter_ui.lua:897` `sweet = true` | range_source_state | KILLED — 1/148 |
| M5 | `hunter_ui.lua:1536` remove the `hunter_ui:range_helper` guard site | range_source_state | KILLED — 7/148 |
| M6 | `main.lua:829-834` unguarded `self[self.player_class].post_init(self)` | range_source_state | KILLED — 4/148 |
| M7 | `main.lua:1807` add `if self.lrc_unavailable then return end` | range_source_state | KILLED — 2/148 (LRC-absent path) |
| M8 | `hunter_ui.lua:894` add `CheckInteractDistance("target", 3)` | range_source_state | KILLED — 5/148 (recorder non-empty) |
| M9 | library `:634-640` remove the empty-list guard | range_source_state | KILLED — 3/148 |

Pre-mutation note: M6/M7/M9 needed the CRLF-aware apply; the first shell draft reported
"old text not found" for those three and was replaced by the Python runner now recorded in
the transcript. The surviving 9/9 run is the one cited.

## 8. In-client checklist (operator, TBC Anniversary hunter)

Not performed by this lane; every item below is **UNCONFIRMED** until the operator runs it.

1. Load the addon; confirm no `ADDON_ACTION_BLOCKED ... check_interact_distance()` in
   BugGrabber during a fight with a target selected.
2. With a target at ~7 yd, the distance strip appears and reads the "sweet" state; at
   ~20 yd it reads ranged; at ~40 yd it reads out of range; with no target it hides.
3. Cast Steady Shot repeatedly: the cast bar and the rest of the hunter UI keep updating
   past 25 frames (the old code quarantined the whole class hook at 25 throws).
4. `/st diag`: `lrc=` reflects only the library's init state (fallback or ok, never
   rewritten by a range-poll failure); the runtime line shows `rf_failures=0`,
   `rf_disabled=false`.
5. Bars' range text shows integer bounds around the true distance (e.g. `7 - 7`) and
   blank when the client cannot answer.

## 9. Left undone / unconfirmed

- **In-client validation** — §8, operator owed. The offline suites model the client but
  cannot prove the protected call is gone from the live client.
- **10 yd sweet-spot citation** — the band comes from the brief's statement that the
  reference's index-3 band is the ~10 yd "just outside melee" band. The reference addon's
  source is not in this repo, so the exact reference file:line is **UNCONFIRMED** by this
  lane; the constant and the band rule are pinned in `hunter_ui.lua:51-61`.
- **5 yd constant** — sourced from the vendored library's `HarmItems[5]` (item 8149,
  "Voodoo Charm", `LibRangeCheck-2.0.lua:300-304`), not from a client range API. It is a
  deliberate, documented approximation of "melee", not a client-verified melee radius.
- **Non-TBC families** — `api.UnitDistance` exists on Era/Titanforge/Retail/Forever per
  `compat.lua:1010-1020` (claimed present). Addon-callability is branch-confirmed for
  `classic_anniversary` by Blizzard's own insecure `CompactUnitFrame.lua:1069` call (see
  §2); the other families are not re-verified in-client here. On a client without
  `UnitDistanceSquared` the state is honestly `nil` (hidden/blank), never a guess.
- **Protection documentation** — the `CheckInteractDistance` block is runtime/client-side
  (operator log), not a documented API restriction; the branch citation only establishes
  where Blizzard itself calls it. This distinction is deliberate in every comment added.
- **`secret_guard_state.lua`** — during this lane's first harness run it failed because it
  still pinned `api.CheckInteractDistance`; the compat lane then rewrote that block to
  assert the wrapper is absent (`tests/secret_guard_state.lua:1410-1411`) and the suite now
  passes at 432 checks. No open crossfire item remains.
- **No git** was run; the working tree is shared with parallel lanes and this report does
  not claim a clean-tree diff.
