# Cross-client engine: LibRangeCheck restore + native swing on Forever/Retail

Lane `cross-client-engine`, 2026-10-25. Desk: `desks/cross-client-engine/`.
Scope: `Libs/LibRangeCheck-2.0/.../LibRangeCheck-2.0.lua`, `swing_source.lua`,
`main.lua` (diag region only), `tests/{lrc_guard,range_source,swing_source,real_wire,main_init,smoke}_state.lua`
re-cuts where listed, new `tests/engine_matrix_state.lua`.
No git command that writes state was run. Line endings verified per file after editing
(LRC CRLF 1249/0; `swing_source.lua`, `main.lua`, all touched tests LF).

**Offline proof only.** No client was loaded by this lane. The in-client list is §7 and
those items are UNVERIFIED.

---

## 1. Baseline was RED: the 2026-10-25 re-vendor clobbered the HU-23 library patch

`bash tests/run.sh` failed lrc_guard_state (83/141), range_source_state (12/148), and the
duplicated range_source step. Root cause: commit `6e2bc2d` (2026-10-25, "AceGUI shared
media widgets and dependent libraries") re-vendored `Libs/**` from upstream and replaced
`LibRangeCheck-2.0.lua` with the **pre-patch** upstream copy (`MINOR_VERSION
10000000000003`). Every 2026-10-21 change was gone: the three API probes, the item/spell
list guards, the four `IsSpellInRange` guards, the empty-list `getRange` guard, the event
guards, and the interact-ladder removal. The tests still encoded the post-HU-23 state, so
the baseline was red exactly where the patch had been.

The post-patch file was recoverable from the repository's own history: `29f1731`
(2026-10-21 "update") contains the full HU-23 file. It was used as the **reference
implementation**, not copied over: the 2026-10-25 base carries unrelated upstream changes
(`MINOR_VERSION ...03`, `Mortal Coil` restored in `HarmSpells.WARLOCK`, the
`useCombatCheckers`/`minRangeCheck`-free architecture, `getCheckerForSpellWithMinRange`)
and those are preserved. The guard package was ported 1:1 onto that base.

### 1.1 Restored, file:line

| # | `LibRangeCheck-2.0.lua` | what |
|---|---|---|
| 1 | `:50-61` | `VENDORED CHANGE (2026-10-21, re-applied 2026-10-25)` header: `CheckInteractDistance` is protected on TBC Anniversary, a block is not catchable, the addon reads exact yards; revert = upstream restore. |
| 2 | `:73-75` | interact tables (`DefaultInteractList`, `InteractLists`) deleted; comment records why no data is kept. |
| 3 | `:402-417` | `GetSpellInfo` shim: `C_Spell.GetSpellInfo` table normalised into the legacy multi-return shape; legacy global the fallback. `GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo`; `IsItemInRange = (C_Item and C_Item.IsItemInRange) or _G.IsItemInRange`; the `CheckInteractDistance` capture is deleted. |
| 4 | `:429-456` | `issecretvalue` probe; `modernItemRange`, `spellRangeAvailable`, `modernSpellRange` probes. |
| 5 | `:475` | `minRangeCheck` local, nil-safe contract ("no min-range refinement, and no client call"). |
| 6 | `:505-528` | `checkers_SpellWithMin` metatable with the two secret/absence guards; `spell_min_range` fallback table (in-list min-range spell, else `minRangeCheck`). |
| 7 | `:567-575` | `getNumSpells` guard → 0 when `GetSpellTabInfo`/`GetNumSpellTabs` are absent (Mainline-code clients). |
| 8 | `:627-673` | `createCheckerList(spellList, itemList)` (2 args, no interact list); `if itemList and not modernItemRange`; `if spellList and spellRangeAvailable and not modernSpellRange`; interact fallback deleted. |
| 9 | `:679-686` | `getRange` empty-list guard: `if not checkerList or #checkerList == 0 then return nil end`. |
| 10 | `:844-877` | `lib:init`: item-based `minRangeCheck` only `if HarmItems[15] and not modernItemRange`; warrior/rogue class-spell fallback each with the absence + secret guards; no interact fallback. |
| 11 | `:1196-1205` | `LEARNED_SPELL_IN_TAB` and `PLAYER_TALENT_UPDATE` registrations guarded by `C_EventUtils.IsEventValid`. |

Static result: `grep -o 'CheckInteractDistance(' <lib> | wc -l` → **0**; no interact table,
no interact list, no 3-arg `createCheckerList`, no `interact:` checker can be built on any
profile. `secret_guard_state.lua`'s LibRangeCheck pin (line 14) is also green again.

### 1.2 Why the interact ladder is simply gone (not "guarded")

HU-23's ruling: `CheckInteractDistance` is protected on the shipped TBC client and a
block is not a catchable Lua error. The addon no longer consumes `LRC:GetRange` at all
(`main.lua` uses `api.UnitDistance`), so the library's only remaining consumers are
external; an empty checker list (nil) is the honest answer. No `pcall` wrapper, no feature
flag. On a hypothetical pre-`C_Item`, pre-`C_Spell` client the legacy item + spell
checkers still build (test §7), which is the only path that could still call
`IsItemInRange` — and that API does not exist there under `C_Item`.

### 1.3 Tests + mutation proof (TASK A)

`lua5.1 tests/lrc_guard_state.lua` → **PASS 141 checks**.
`lua5.1 tests/range_source_state.lua` → **PASS 148 checks**.

Mutation on `/tmp/opencode/engine-mut/tree` (rsync without `Media/`, `docs/`, `.git`),
restored byte-identical from the working tree after each run:

| # | mutation | result |
|---|---|---|
| M1 | re-add the `checkers_Interact` table and the interact fallback in `createCheckerList` (the exact HU-23 regression) | **KILLED**: lrc_guard `static pin: zero CheckInteractDistance calls (got 1, want 0)`, `interact checker table is gone (got 2, want 0)`, `empty: GetRange() ... CheckInteractDistance is protected on TBC Anniversary`; range_source `static pin: the vendored library carries zero CheckInteractDistance calls (got 1, want 0)`, `the harm checker list is empty (got 2, want 0)`, `GetRange() ... protected`. |
| M2 | `if itemList and not modernItemRange then` → `if itemList then` | **KILLED**: lrc_guard 22/141 (modern/hybrid item checkers built, blocked-API spy would be reached). |

Full transcript: `/tmp/opencode/engine-mut/run.log` (local, not committed).

---

## 2. TASK B — the per-branch engine matrix

Facts verified by shell against `/home/sam/wow-ui-source` (branch read via
`git show <branch>:<path>` / `git grep <pattern> <branch> -- Interface`):

| branch | `PLAYER_SWING` under `Interface` | `Blizzard_SwingTimer` addon |
|---|---|---|
| `classic_era` | **none** | **absent** |
| `classic_anniversary` | **none** | **absent** |
| `classic_titan` | **none** | **absent** |
| `live` (12.1.0) | **none** | **absent** |
| `origin/forever` (1.60.1) | `SwingTimerDocumentation.lua`, `Blizzard_SwingTimer/Blizzard_SwingTimer.lua`, `GamepadReticle.lua` | **present** |

So the engine split is a client fact, not a preference:

| branch | family (compat) | toc ships lib? | engine chosen | events registered | payload shape |
|---|---|---|---|---|---|
| Classic Era 1.15.9 | `ERA` | yes | `vendored-lib` | lib's own (CLEU + equip/world) | lib legacy re-fire `(unitId, speed, expiration, hand)` → dispatcher strips `player` |
| TBC Anniversary 2.5.6 | `TBC` | yes | `vendored-lib` | lib's own + our TBC ranged fallback driver | same |
| WotLK Titanforge 3.80.2 | `WRATH` | yes | `vendored-lib` | lib's own | same |
| WoW Forever 1.60.1 | `FOREVER` | no (`_Mainline`) | `forever-source` (`swing_source`) | `PLAYER_SWING`, `UNIT_ATTACK_SPEED` (unit-filtered `player`), `WEAPON_SLOT_CHANGED`, `PLAYER_IN_COMBAT_CHANGED`, `PLAYER_ENTERING_WORLD` | `START/UPDATE(speed, expiration, hand)`, `STOP(hand)` — speed-first |
| Retail 12.1.x | `RETAIL` | no (`_Mainline`) | `inert-standin` | none | `SwingTimerInfo` → `(nil, nil, nil)` (engine_dead) |

### 2.1 Blizzard's Forever implementation, cited line by line

`origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SwingTimerDocumentation.lua`

- `:43-52` `PLAYER_SWING(swingDuration:number, swingType:PlayerSwingType)`,
  `SynchronousEvent = true` — exactly the two arguments our `on_player_swing` takes.
- `:71-82` `Enum.PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 }` — exactly our
  `swing_type_hands` map (and the `Enum`-absent numeric fallback pins the same values).
- `:54-65` `PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange)` — **display
  data**, and only dispatched for types with an active `C_SwingTimer.EnableRangeCheck`
  (`:11-20`). The addon never calls `EnableRangeCheck` and reads range from
  `api.UnitDistance`, so this event cannot affect a cycle.
- `:22-37` `C_SwingTimer.IsTargetWithinSwingRange` — the pull form of the same display
  data; not used.

`origin/forever:Interface/AddOns/Blizzard_SwingTimer/Blizzard_SwingTimer.lua`

| line | Blizzard behaviour | our `swing_source.lua` |
|---|---|---|
| `:141-146` | `PLAYER_SWING` → if the frame's type matches, `ResetSwingTimer(swingDuration)` (`:333-355`: `swingEndTime = GetTime() + duration`, rejects `nil/<=0`) | `on_player_swing` (`:206-229`): validates type + duration, `begin_cycle` at `now`, fires `SWING_TIMER_START(speed, expiration, hand)`, scheduled STOP with 0.1 s grace. Same validity rules. |
| `:147-148` | `PLAYER_IN_COMBAT_CHANGED` → `UpdateShownState` only (never clears a cycle) | `on_combat_changed` (`:339-355`): records `in_combat` for the H5 notice, clears live cycles on **exit** with a `STOP` per hand. A swing cannot occur out of combat, and the clear is explicit (never silent). Deliberate divergence from the display-only arm. |
| `:149-150` | `PLAYER_TARGET_CHANGED` → `UpdateRangeState` (out-of-range alpha) | **not registered** — cannot start/retime/end a cycle; range comes from `main.lua`'s poll. |
| `:151-153` | `WEAPON_SLOT_CHANGED` → `UpdateFrameState` + `ResetSwingTimerForEquippedWeapon` (`:319-330`: a live cycle is **restarted** at `GetEquippedSwingDuration`) | `on_weapon_slot_changed` (`:285-337`): **changed this wave** from a proportional rescale to a full restart at the equipped duration; a hand with no usable speed is cleared with a `STOP`; throw/secret reads keep the schedule (`speed_read_keeps`). |
| `:154-155` | `PLAYER_ENTERING_WORLD` / `UNIT_ATTACK_SPEED` → `UpdateFrameState` (no cycle retime) | world entry clears live cycles **with a `STOP`** (changed this wave, never a silent drop) and reports `SWING_TIMER_INFO_INITIALIZED` once; `UNIT_ATTACK_SPEED` rescales the remaining time — kept from the classic library (`LibClassicSwingTimerAPI.lua:472-534`), because our surface must stay lib-compatible; Blizzard's own bar does not retime on haste, but it also has no consumer contract to keep. Documented divergence. |
| `:156-160` | `PLAYER_SWING_RANGE_UPDATE` → `SetOutOfRange` | **not registered** (display-only; see `:54-65`). |
| `:184-192` | `GetEquippedSwingDuration`: reads **all three** `UnitAttackSpeed("player")` returns and picks by type | `on_unit_attack_speed` / `on_weapon_slot_changed` read all three and map `mainhand/offhand/ranged` the same way. `UnitAttackSpeed` is `SecretWhenUnitStatsRestricted = true` (`UnitDocumentation.lua:682-697`), covered by `issecretvalue` guards. |
| `:164-182` | `HasOffHandWeapon` / `HasRangedWeapon` per-type reads; a hand with no weapon is not handled | PLAYER_SWING only fires for equipped hands on the client; our swap-clear covers the removed-weapon case. |

**Omissions verified, not assumed:** `PLAYER_TARGET_CHANGED` and
`PLAYER_SWING_RANGE_UPDATE` are display-only arms in Blizzard's own engine; neither
touches `swingDuration`/`swingEndTime`, and the latter is not even dispatched without
`C_SwingTimer.EnableRangeCheck`. Registering them would be dead wiring. Pinned as
**not registered** in `tests/engine_matrix_state.lua`.

### 2.2 Code changes in `swing_source.lua`

| region | change |
|---|---|
| `:1-25` header | citations for the doc (`:43-52`, `:71-82`) and Blizzard's bar (`:141-161`, `:184-192`, `:319-330`). |
| `:285-337` `on_weapon_slot_changed` | proportional rescale → **restart at the equipped duration** (mirrors Blizzard `:151-153`/`:319-330` and the classic lib's `PLAYER_EQUIPMENT_CHANGED` at `LibClassicSwingTimerAPI.lua:732-744`). Same-speed swaps also restart. No-live-cycle swaps fire nothing. |
| `:357-376` `on_player_entering_world` | live cycles are `STOP`ped before the clear (previously cleared silently, which left `main.lua`'s bar frozen because the scheduled stop could no longer match). |
| `:413-421` event-set comment | the two omitted events now carry the Blizzard line citations and the reason. |
| `:422-437` registration | unchanged: 5 events, `UNIT_ATTACK_SPEED` unit-filtered, every event through `C_EventUtils.IsEventValid` with the FOREVER-family fallback. |

### 2.3 `main.lua` — diag line

`ST:print_runtime_diag` (`main.lua:2690-2702`) now leads with
`swing_engine=<name>(<reason>)`:

- `swing_engine=vendored-lib(lib)` — a shipped `LibClassicSwingTimerAPI` won;
- `swing_engine=swing_source(PLAYER_SWING)` — Forever's native feed;
- `swing_engine=inert(no-feed)` — no engine (Retail, or a late/dead library).

`diag.lua`'s config line already carried `engine=`; this adds the same fact to the
runtime line, which prints even when the diag module is absent. No other `main.lua`
region was touched.

### 2.4 Retail path

Unchanged by design: `_Mainline.toc` ships no `LibClassicSwingTimerAPI`, `PLAYER_SWING`
does not exist on `live`, `swing_source.available` is false (family gate), so `main.lua`
selects the inert stand-in, prints exactly one notice, and `init_libs` completes on
LibRangeCheck alone. Proof: `tests/real_wire_state.lua` "Retail silent leg" (engine line,
one notice, every hand `engine_dead`, no wire traffic, deadline stands down) and
`tests/main_init_state.lua` §6 `engine = "absent"` (OnInitialize → options registration →
`init_libs` → range/GCD initialisation completes). No classic-lib fallback was added
(HU-31).

### 2.5 Classic-line reconciliation (no protected range calls in our code)

`grep -rn 'CheckInteractDistance|IsItemInRange' --include=*.lua` outside `Libs/` and
`tests/` → **no product call sites** (only comments and test spies).
`api.IsSpellInRange` remains the class helpers' range source (HU-24 open, `C_Spell`
namespace, not `CheckInteractDistance`); not touched under HU-23.
`main.lua`'s range state is `api.UnitDistance` only (`:2466`); the TBC ranged fallback is
gated to `swing_engine == "vendored-lib"` **and** `not st.is_mainline` (`:2056-2061`), so
Forever/Retail never enter it. No `LRC:GetRange`/`GetHarm*Checker` call sites remain.

### 2.6 Hunter mainhand "mixed up with ranged": the blanket cast reset (2026-10-25 addendum)

**Corrections to the lead (both verified in the shipped file):**
1. "Auto Shot 75 is in `noreset_swing_spells` (`:1030`)" is **not true**: `:1030` sits in
   the BCC `noreset` table and lists Steady Shot / bombs, not 75. Auto Shot is in no
   `noreset` table; on Wrath it is in `reset_swing_spells` (`:1161`).
2. Steady Shot is **already exempt** on BCC (34120, 25258) and Wrath (plus 49051/49052),
   so Steady casts do not restart melee bars. The real gaps are Multi-Shot, Aimed Shot
   (BCC all ranks; Wrath r2+), Arcane Shot and Serpent Sting.

**Mechanism (verified in the shipped v32 lib, LF):** `UNIT_SPELLCAST_START` sets
`unit.casting = true` and `unit.preventSwingReset = noreset_swing_spells[spell]`
(`LibClassicSwingTimerAPI.lua:683-684`). `UNIT_SPELLCAST_SUCCEEDED` then runs

```lua
if (spell and reset_swing_spells[spell]) or (unit.casting and not unit.preventSwingReset) then
    -- non-Retail:
    unit:SwingStart("mainhand", now, true)
    unit:SwingStart("offhand", now, true)
end
```

(`:596-605`). So **any** completed cast not in the per-version `noreset_swing_spells`
table restarts both melee bars. For a hunter that is every ranged shot except the
entries the tables already carried.

**Per-family verification (shipped v32 tables):**

| shot | Era (`:996`) | BCC (`:1115`) | Wrath (`:1380`) | result before this fix |
|---|---|---|---|---|
| Auto Shot 75 | not noreset, not reset list | not noreset, not reset list | **`reset_swing_spells[75] = true`** (`:1196`) | Era/BCC: reset only if a `START(75)` cast is live (the class guard gates it by range). Wrath: **always resets**, `preventSwingReset` cannot stop it (the OR's first branch). |
| Steady Shot 34120 / 25258 | — (no Steady on Era) | **noreset** | **noreset** (plus 49051/49052) | already exempt — the lead's Steady suspicion was stale |
| Multi-Shot 2643 + ranks | **not listed** | **not listed** | **not listed** | resets both melee bars on every cast |
| Aimed Shot 19434 + ranks | **not listed** | **not listed** | 19434 listed, higher ranks **not** | resets (BCC all ranks; Wrath r2+) |
| Arcane Shot 3044 + ranks | **not listed** | **not listed** | **not listed** | resets both melee bars |
| Serpent Sting 1978 + ranks | **not listed** | **not listed** | **not listed** | resets both melee bars |

Upstream is no better: `Ralgathor/LibClassicSwingTimerAPI` `main` (MINOR 39) has the same
gaps (Multi-Shot in no table; Aimed only rank 1 on Wrath). So this is an upstream-wide
gap, not a stale vendored copy.

**Fix chosen: (ii) per-version `noreset_swing_spells` entries in the vendored lib.**
Why not the our-side restore in `main.lua`:

- The lib's decision point is synchronous at `START`; a table entry needs no tick, no
  event-order assumption, and cannot flash a one-frame phantom cycle. An our-side
  restore must either run before the lib's `SUCCEEDED` (ordering is undefined between
  AceEvent and the lib's frame) or defer via `C_Timer.After(0)` and then unwind state it
  did not create — provable only for the orderings the test chooses.
- Id lists are not needed for classification this way; the ids are the shot ladder.
- The class module already owns Auto Shot's **range-dependent** rule
  (`classes/hunter.lua suppress_auto_shot_melee_reset`, the concurrent `bars-range-hunter`
  lane). A blanket `noreset[75]` would supersede that rule and remove the in-melee
  (melee-weaving) reset, so **75 is deliberately not added here**.

Patch (`Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua`, LF preserved, three
tables): the full classic-line rank ladders for Multi-Shot, Aimed Shot, Arcane Shot and
Serpent Sting — `:996-1023` (Era), `:1115-1131` (BCC), `:1380-1398` (Wrath; Aimed rank 1
already exempt further down, so its block starts at r2). Every id was checked against the
WotLK spell pages (`wowhead.com/wotlk/spell=<id>` redirects to the named shot; 41 ids);
an id a client does not have is inert. Ranks come from the repo's sourced hunter tables
(`classes/hunter.lua:303-470`) and the classic ladders; they are CLIENT-UNCONFIRMED per
those tables' own notes.

**Accepted tradeoffs, stated:**

- Multi/Arcane/Serpent are instant: the game does not reset a melee swing for an instant
  shot, so suppressing is a correctness fix, not a heuristic.
- Aimed Shot is a 3 s cast; a blanket exemption also suppresses a possible in-melee reset.
  This follows the lib's own Wrath precedent (`noreset[19434]`) and the operator's report;
  in-melee Aimed weaving is not a shipped rotation line.
- The `ranged_swing` table is untouched: these shots never started the ranged cycle; the
  ranged bar remains Auto Shot's (and Shoot/Throw/Wand's).

**Residual filed, not fixed:** on Titanforge, `reset_swing_spells[75] = true`
(`:1161`) forces the Auto Shot melee reset even when the class guard sets
`preventSwingReset` — the OR's first branch wins. Removing that one entry would put Wrath
on the same casting-branch path as Era/BCC, where the class guard's range rule works; it
is one line but changes Wrath behaviour beyond the reported shots, so it is filed for the
operator rather than taken here.

**Proof:** new `tests/real_wire_state.lua` section "HUNTER CAST RESET" — three profiles,
real lib + real v7 + real dispatcher (no class module, so only the lib's tables decide):
seven/eight shot casts per profile produce **zero** mainhand/offhand STARTs and leave the
live anchors untouched; the controls still fire (Raptor Strike resets mainhand; a neutral
cast takes the blanket path). `978 checks, 0 failures` (2 HU-29 xfail).

---

## 3. Tests (only the suites this lane owns/was told to run)

| suite | result | notes |
|---|---|---|
| `lua5.1 tests/lrc_guard_state.lua` | **PASS 141** | restored library |
| `lua5.1 tests/range_source_state.lua` | **PASS 148** | restored library |
| `lua5.1 tests/secret_guard_state.lua` | **PASS 432** | was red (2) from the same regression — the LibRangeCheck event-guard pin |
| `lua5.1 tests/swing_source_state.lua` | **PASS 159** | §14 re-cut: swap restart (mid-cycle), same-speed restart, world-entry STOP |
| `lua5.1 tests/engine_matrix_state.lua` | **PASS 101** | **new**; 5 branches + probe-reject + probe-approve + interface-only 16001 |
| `lua5.1 tests/real_wire_state.lua` | **978 checks, 0 failures** (2 expected-fail pending HU-29) | +96: the HUNTER CAST RESET section (§2.6) |
| `lua5.1 tests/main_init_state.lua` | **PASS 1050** | +3: the diag runtime engine field on vendored/Forever/Retail |
| `lua5.1 tests/smoke.lua` | **232 checks, 0 failures** | unchanged |

Crossfire checks run read-only (not claiming them): `hunter_state` 1824 PASS,
`hunter_window_state` 213 PASS, `bars_state` 956 PASS, `diag_state` 260 PASS,
`enemy_swing_state` 250/0.

`luacheck swing_source.lua main.lua tests/engine_matrix_state.lua tests/swing_source_state.lua
tests/main_init_state.lua` → **1 warning / 0 errors** (the KEEP-ruled `main.lua:87 table.pack`
floor warning). `luacheck .` → **2 warnings / 0 errors in 93 files** (the KEEP-ruled floor:
`compat.lua:36 addon_name`, `main.lua:87 pack`).

The FULL `bash tests/run.sh` was **not** run by this lane (orchestrator-owned). `run.sh`
needs one new line: `lua5.1 tests/engine_matrix_state.lua` (filed below).

### 3.1 Mutation proofs (all on `/tmp/opencode/engine-mut/tree`, restored byte-identical)

| # | mutation | suites | result |
|---|---|---|---|
| M1 | re-add interact checker + fallback (HU-23 regression) | lrc_guard, range_source | **KILLED** |
| M2 | remove `not modernItemRange` from the item-list guard | lrc_guard | **KILLED** (22/141) |
| M3 | `is_event_valid` always returns true | engine_matrix, swing_source | **KILLED** (3/101 + 5/159) |
| M4 | Enum `Ranged` maps to `mainhand` | engine_matrix, swing_source | **KILLED** (crash + 1/159) |
| M5 | weapon swap no longer restarts the cycle | swing_source | **KILLED** (4/159) |
| M6 | diag engine label loses the active-engine name | main_init | **KILLED** (1/1050) |
| M7 | drop `noreset[2643]` from the **Era** hunter block | real_wire | **KILLED** (9/978: `era-castreset: Multi-Shot r1 does not restart the mainhand (got 2, want 1)`, offhand, anchor cascade) |
| M8 | drop `noreset[19434]` from the **BCC** hunter block | real_wire | **KILLED** (7/978) |
| M9 | drop `noreset[49048]` from the **Wrath** hunter block | real_wire | **KILLED** (8/978) |

9/9 killed. The M1 and M7 runs' exact evidence is quoted in §1.3 / §2.6.

---

## 4. What is NOT proven here (UNVERIFIED)

1. **Forever in-client**: that `PLAYER_SWING` really fires with the documented payload for
   mainhand/offhand/ranged on the operator's client, that the bars sweep and stop, and
   that a weapon swap restarts the displayed cycle. The API source is CONFIRMED-SOURCE;
   the runtime feed is **UNVERIFIED**.
2. **Forever range display**: `PLAYER_SWING_RANGE_UPDATE` is display-only and unused;
   swapping targets/range in-client must not change a swing bar (not observable offline).
3. **Retail in-client**: the one-notice stand-in and the absence of any swing bar.
4. **Classic in-client (TBC Anniversary)**: after this restore, confirm no
   `ADDON_ACTION_BLOCKED` naming `check_interact_distance` and that the range display
   still shows exact-yard numbers. (Same owed item as HU-23.)
5. **TBC Anniversary `C_EventUtils.IsEventValid`** is present per
   `classic_anniversary:Interface/AddOns/Blizzard_APIDocumentationGenerated/EventUtilsDocumentation.lua`
   (namespace probed by the docs; exact line not re-fetched this wave) — the addon's
   guards tolerate its absence anyway.
6. **`UnitAttackSpeed` secret behaviour on Forever** is a doc marker
   (`SecretWhenUnitStatsRestricted`, `UnitDocumentation.lua:684`); the guard is
   unit-tested with simulated secrets, not observed on a restricted client.
7. **Hunter cast-reset fix in-client**: fire Multi-Shot / Aimed / Arcane / Serpent while
   a melee cycle is live and confirm the mainhand/offhand bars do **not** restart (only
   the ranged bar moves). Offline proof drives the real lib; the real cast events and the
   client's rank ids remain in-client checks. The `noreset` rank ladders are
   CLIENT-UNCONFIRMED (inherited from `classes/hunter.lua`'s sourced tables).
8. **Raptor Strike control in-client**: a real melee reset must still move the mainhand.

In-client checklist for the operator (copy tree → `/reload` → `/st diag`):

- Forever: `/st diag` shows `swing_engine=swing_source(PLAYER_SWING)` and `engine=forever-source`;
  mh/oh/ranged each sweep a full cycle, stop at expiry, reset on the next swing; a weapon
  swap restarts the bar at the new speed; no Lua error.
- Retail: `/st diag` shows `swing_engine=inert(no-feed)` / `engine=inert-standin`, exactly
  one "Swing timer bars are unavailable" notice, options open, range/GCD active.
- Anniversary hunter: no `ADDON_ACTION_BLOCKED`; range numbers follow exact yards; cast
  Multi/Aimed/Arcane/Serpent at range and confirm the melee bars do not restart; Raptor
  Strike in melee still restarts them.
- Titanforge hunter: **known residual** — Auto Shot still resets the melee bars (filed
  below); Multi/Aimed/Arcane/Serpent are fixed.

---

## 5. Cross-lane items (filed, not edited)

1. **Orchestrator — `tests/run.sh`**: add `lua5.1 tests/engine_matrix_state.lua` to the
   suite list (new file, 101 checks). This lane did not edit `run.sh`.
2. **`bars-range-hunter` lane (concurrent, owns `classes/hunter.lua` / `hunter_ui.lua`)**:
   - Its `suppress_auto_shot_melee_reset` is the range-dependent half and is **not**
     duplicated here; Auto Shot 75 is deliberately absent from the lib tables.
   - **Titanforge gap**: `reset_swing_spells[75] = true` (`LibClassicSwingTimerAPI.lua:1196`)
     forces the melee reset regardless of `preventSwingReset`, so that guard cannot work on
     Wrath. One-line fix (remove the entry) makes Wrath follow the same casting-branch path
     as Era/BCC; filed, not taken, because it changes Wrath behaviour beyond the reported
     shots.
   - Its UI root cause (`hunter_ui.sync_melee_anchor` hopping the melee bars under the
     cast bar during the Auto Shot hidden window) is a separate, real cause of the same
     operator phrase; its bench report `bench/bars_range_hunter_2026-10-25.md` was not on
     disk when this addendum was written (UNVERIFIED here).
3. **Orchestrator / release**: the 2026-10-25 re-vendor (`6e2bc2d`) silently reverted the
   HU-23 library patch. Recommend a bench lesson: *a vendored-library update must re-apply
   the documented patch and re-run `lrc_guard_state` / `range_source_state` /
   `secret_guard_state`; `git show <pre-revendor>:<path>` is the reference implementation.*
4. **`bench/range_lrc_guard_2026-10-21.md` and `bench/range_engine_tbc_2026-10-21.md`**:
   their file:line citations describe the pre-re-vendor base (`MINOR_VERSION ...01`, the
   old `minRangeCheck` architecture). This report supersedes their **line numbers** for
   the current file; their behaviour claims still hold.
5. **HU-23**: still owed in-client confirmation (checklist above).
6. **HU-24** (`api.IsSpellInRange` on Anniversary): unchanged; not touched.
7. **HU-29** (vendored `LibClassicSwingTimerAPI`): this wave adds a **second** documented
   local patch (the hunter shot ladders, §2.6) on top of the existing vendored copy. It is
   a table-only addition with behavioural pins and mutations, but it strengthens the case
   for option (a)/(b) on HU-29 — a re-vendor will silently drop it exactly as `6e2bc2d`
   dropped the LRC patch.
8. **Options/UI lane**: `/st diag`'s new `swing_engine=` field is additive; `diag.lua`
   already prints `engine=` in its config line, so no UI work is implied.

---

## 6. Provenance

- Changed files: `Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua`,
  `Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua` (three `noreset_swing_spells`
  tables, §2.6), `swing_source.lua`, `main.lua:2690-2702`,
  `tests/real_wire_state.lua` (HUNTER CAST RESET section),
  `tests/swing_source_state.lua`, `tests/main_init_state.lua`, new
  `tests/engine_matrix_state.lua`.
- Rank-id sources: `wowhead.com/wotlk/spell=<id>` redirect slugs (41 ids, 2026-10-25;
  ids listed in `tests/real_wire_state.lua` and §2.6) and the repo's sourced hunter
  tables (`classes/hunter.lua:303-470`).
- Reference implementation: `git show 29f1731:Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua`
  (read-only; the 2026-10-21 patched file).
- Client sources: `/home/sam/wow-ui-source`, branches `origin/forever` (`ca8368f2f`),
  `live` (`4e3cbb8c5`), `classic_era`, `classic_anniversary`, `classic_titan`, read with
  `git show` / `git grep` on 2026-10-25.
- Mutation copy: `/tmp/opencode/engine-mut/` (tree + `mutations.py` + `run.log`), local,
  not committed.
