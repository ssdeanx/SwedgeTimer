# swing-wire-hunter — Journal

Read-only defect-hunt desk. Brief: `bench/briefs/brief_swing-wire-hunter_2026-10-22.md`.
Skills note: `skills_list` carries none of `bench-read`/`desk-open`/`desk-journal`/`signal-write` — worked per `workshop.md`+`CAIRN.md`+`AGENTS.md`. `ast_grep_search` not in tool catalog; `hermes_search_files` DID traverse `/home/sam/wow-ui-source` (positive-controlled) but sees only checked-out `classic_era`. All other-branch claims are UNVERIFIED with exact close-outs.

## 2026-10-22 — Report filed (read-only, no tree changes)

- **Worked on:** traced the vendored-lib fire-site-to-handler wire, the version gates, registration/init gating, TOC ship matrix, Forever path vs Blizzard's own, and SuperSwingTimer's direct-CLEU engine; answered brief Q1–Q7. Orchestrator verified every cited file:line against the tree before filing (all hold).
- **Current state:** 7 findings (below). D1 already fixed in tree, in-client UNPROVEN. D2 conditional on a runtime value only the client can report. D3 + Forever event gaps are fixable in OUR files (builder owns). D4/D5/D6 + D2's lib half are VENDORED — upstream-or-fork ruling owed (HU-29). D7 is by-design. Raw transcript: `/home/sam/.hermes/profiles/orchestrator/cache/delegation/live/deleg_e944edf9/task-0.log`.

### Ranked defects

- **D1 — BROKEN (fixed in tree, in-client UNPROVEN): unit-id-lead wire kills every hand on every classic-line client.** `Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:817-825` re-fires every `UNIT_SWING_TIMER_*` as `SWING_TIMER_*` keeping the unit-id lead → CallbackHandler v7 forwards verbatim (`Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua:59-64`) → pre-strip dispatcher passed it through → handlers (`main.lua:1063-1182`, speed-first) misaligned by one → unknown-hand guard → all bars frozen at init seed. Fix landed `main.lua:944-951`. Close-out: U1.
- **D2 — BROKEN (conditional, live now): Anniversary fails the lib's `isBCC` gate → all spell tables stay empty → ranged dead, melee alive.** `LibClassicSwingTimerAPI.lua:43` needs `WOW_PROJECT_ID==WOW_PROJECT_BURNING_CRUSADE_CLASSIC AND LE_EXPANSION_LEVEL_CURRENT==LE_EXPANSION_BURNING_CRUSADE`; no match → `ranged_swing`/`reset_ranged_swing`/`next_melee_spells` stay `{}` → `UNIT_SPELLCAST_SUCCEEDED(75)` no-ops; `SPELL_CAST_START`/`FAILED_QUIET` are `isClassic`-gated anyway. Melee survives via table-free CLEU `SWING_DAMAGE`. Anniversary project id = 5 CONFIRMED on `origin/classic_anniversary` (`Blizzard_FrameXMLBase/TBC/Constants.lua:93,97`); the expansion-level half is binary-provided (zero Lua assignments) → gate outcome UNVERIFIED (U2), needs the in-client `/st diag proj=/exp=/bcc=` line (`main.lua:2106-2108`, shipped). Fix direction: widen the lib's BCC condition to the observed identity — vendored file, upstream-or-fork ruling first, never a silent local patch.
- **D3 — DEGRADED (live now, Forever): `swing_source` idle shape impersonates a live cycle.** `swing_source.lua:326-334` returns `(1, start+1, start)` with a stale comment citing the pre-H1 stub; the stub returns nil-shape since H1 (`main.lua:19-30`). `init_timers` (`main.lua:739-757`) takes the number branch → phantom 1 s full cycle, no STOP ever comes. Fix: return the nil-shape when no cycle is active.
- **D4 — DEGRADED (vendored, all classic-line): parry-haste arm unreachable.** `LibClassicSwingTimerAPI.lua:397` catches all `SWING_MISSED` first; `:415` PARRY arm never runs. SST applies it (`SuperSwingTimer_State.lua:1364-1371`). Fix: test PARRY before generic MISSED (upstream).
- **D5 — DEGRADED (vendored, all classic-line): no `SPELL_EXTRA_ATTACKS` handling.** Windfury/sword-spec procs double-start cycles (jitter, not death). SST suppresses via `extraAttackPending` (`SuperSwingTimer_State.lua:1308-1310,1322-1324,1337-1339`). Fix: pending-counter suppression (upstream).
- **D6 — DEGRADED (Anniversary ranged robustness): single-source ranged speed.** Only `UnitRangedDamage` first return (`lib:170,309,521-530`); no `GetSpellCooldown(75)`/haste fallback chain (SST has both, `SuperSwingTimer_State.lua:100-129,686-729`). Anniversary runtime shape UNVERIFIED (U3).
- **D7 — BROKEN by design (confirm, not a bug): Retail/Cata/Mists bars expected dead.** Retail = inert stand-in; Cata/Mists ship NO lib (verified: no `LibClassicSwingTimerAPI` line in either TOC) → nil seed → `engine_dead` → "engine offline" + one-time notice (`main.lua:717-722`, `bars.lua:591-603`).

### Q verdicts

1. Strip WIRED post-fix (all six events + hand-only STOP; Forever numeric-first passes through; v7/v8 arg-shapes identical, bundled v8 never loaded; zero SwedgeTimer registrations on `UNIT_SWING_TIMER_*`).
2. Era wired; Anniversary conditional (drivers: Era `CAST_START`+`FAILED_QUIET`+`SUCCEEDED(75)`+autorepeat; Anniversary `SUCCEEDED(75)`+autorepeat only).
3. Six registrations suffice; `INFO_INITIALIZED` unconditional from lib; 5 s deadline degrades explicitly, never silent.
4. Ship matrix: lib in base/`_Vanilla`/`_TBC`/`_Wrath` `:18`; absent `_Mainline`/`_Cata`/`_Mists`. v7 everywhere `:15`. `swing_source.lua` on all seven.
5. Forever path matches Blizzard on every checkable point; gaps (orchestrator-confirmed on `origin/forever`): `WEAPON_SLOT_CHANGED` / `PLAYER_TARGET_CHANGED` / `PLAYER_SWING_RANGE_UPDATE` unhandled; `UNIT_ATTACK_SPEED` registered without unit filter (harmless, noisy).
6. SST-vs-lib: off-hand positions identical; AutoShot 75 both (SST adds name-form + `C_Spell` fallbacks the lib lacks); extra attacks / parry / `SPELL_UPDATE_COOLDOWN` / movement pinning are real lib gaps; `UNIT_RANGEDDAMAGE` roughly equivalent via lib polling; queued-melee roughly equivalent (table currency owed in-client).
7. Retail stand-in → `engine_dead` + notice + diag line: a Retail dead-bars report WITH the notice is by design.

### UNVERIFIED (exact close-outs)

- **U1** — post-strip wire in-client (nothing client-copied per 2026-10-21 close). Close-out: Era mh auto-attack advances mh bar; Anniversary hunter autoshot advances ranged; `/st diag` `swing_<hand>` counts climb. Alt: HU-25 real-lib harness.
- **U2** — Anniversary 2.5.6 project/expansion-level values. Close-out: Anniversary `/st diag` `proj=/exp=/bcc=` line.
- **U3** — Anniversary `SUCCEEDED(75)` delivery + `UnitRangedDamage` shape on 2.5.6. Close-out: in-client probe.
- **U4** — CLOSED by orchestrator 2026-10-22 via `git show origin/forever`: Blizzard manager handles `WEAPON_SLOT_CHANGED`, `PLAYER_TARGET_CHANGED`, `PLAYER_SWING_RANGE_UPDATE` + shared `UNIT_ATTACK_SPEED`; `swing_source` lacks the first three → builder item.
- **U5** — Era doc entries for `SPELL_EXTRA_ATTACKS` etc. (needed ast-grep skill, absent). Minor; builder can cite in-client behavior instead.
- **U6** — HU-27 unreconciled range-lane diff. Bounded (LRC constant + fire site intact; deadline bounds stalls). Still owed.
- **U7** — Cata/Mists "engine offline" eyeball (expected per D7).

### Non-findings (checked, hold)

Dispatcher strip shape for every event incl. hand-only STOP; v7/v8 identical, v8 unloaded; `INFO_INITIALIZED` + deadline rescue; `UnitRangedDamage` speed-first on Era (four FrameXML sites); `PLAYER_SWING` absent on Era; LLM/LGC/LRC constants defined; `SwingTimerInfo` closure reads `STL` dynamically; `get_class_hands`/`iter_hands` nil-safe.

### Residuals (one line each)

`lib:getUnit` target branch compares `self.player.id` (`lib:254-262`); `isMists` gate compares the constant to itself (`lib:46`, harmless while Mists ships no lib); `swing_source.lua:331` stale comment; `UNIT_ATTACK_SPEED` unit-unfiltered (noisy, harmless); HU-27 bounds init trust; HU-28: keep shipped v7.

- **Next step:** builder lane owns D3 + the U4-closed Forever event gaps (`WEAPON_SLOT_CHANGED` clear/re-read; consider `PLAYER_TARGET_CHANGED` only if it carries swing state, else note-and-skip) + `swing_source.lua:331` comment fix, with offline suite pins + mutation proofs. D2/D4/D5/D6 go to HU-29 (operator: upstream-or-local-fork for the vendored lib). U1/U2/U3/U7 are operator in-client items for the copy list.
