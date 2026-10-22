# Range fix: the vendored LibRangeCheck-2.0 item checker and the dead spell ladder

Lane `range-lrc-guard`, 2026-10-21. Brief: `bench/briefs/brief_range-lrc-guard_2026-10-21.md`.
Cross-branch authority cited: `bench/range_api_orchestrator_matrix_2026-10-21.md`
(orchestrator-verified with shell). My own per-line citations below come from
`git -C /home/sam/wow-ui-source show <branch>:<path>` / `git grep` and are marked
CONFIRMED-SOURCE. Everything else is either offline test output or UNCONFIRMED.

**This is an OFFLINE proof only.** No client was loaded by this lane. In-client
confirmation on Classic Era 1.15.9 is owed by the operator (the orchestrator asks for it).

## 1. What changed (R1 + R2 only)

File: `Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua` (CRLF preserved;
22 lines added / 3 removed in total, no reformatting, no vendored file re-copied).

| # | file:line | change |
|---|---|---|
| 1 | `LibRangeCheck-2.0.lua:435-441` | new load-time probe `local modernItemRange = (C_Item and C_Item.IsItemInRange) ~= nil`, with the WHY in client terms (block, not a catchable error; the classic legacy global IS the modern function). |
| 2 | `LibRangeCheck-2.0.lua:442-447` | new load-time probe `local spellRangeAvailable = type(IsSpellInRange) == "function"` (the legacy global is captured at :421; it exists nowhere). |
| 3 | `LibRangeCheck-2.0.lua:594-596` | `createCheckerList`: the item list is only walked `if itemList and not modernItemRange` — no item checker can enter a checker list where `C_Item.IsItemInRange` exists. |
| 4 | `LibRangeCheck-2.0.lua:607-610` | `createCheckerList`: the spell list is only walked `if spellList and spellRangeAvailable` — dead spell checkers are no longer added, so the existing empty-list fallback (`if interactList and not next(res)`, unchanged at :633) installs the interact bands. |
| 5 | `LibRangeCheck-2.0.lua:801-803` | `lib:init`: `if HarmItems[15] and not modernItemRange then` — the item-based `minRangeCheck` is not built where the modern item API exists (it falls through to the class-spell branch / interact bands as before). |

`checkers_Item` (:509-517) and `checkers_Spell` / `checkers_SpellWithMin` are untouched;
they are file-local and now unreachable from a modern client's lists (pinned by test 6).

Deliberately **not** changed:
- the interact fallback condition (`interactList and not next(res)`) — skipping the dead
  spell list is what makes it fire; adding an extra `or not spellRangeAvailable` term
  would have been an untestable branch and would coarsen the ladder on a hypothetical
  legacy-item client where the item checkers DO answer;
- `minRangeCheck`'s class-spell branch — its only consumer is the min-range spell checker
  (`checkers_SpellWithMin`), which cannot be in a list when the spell API is absent, so a
  guard there would have been behaviourally unobservable (an earlier draft had one; it
  was removed rather than shipped untested);
- the item-info request machinery (`processItemRequests`) — it only calls the allowed
  `GetItemInfo`; no blocked range call, no behavioural need.

`tests/lrc_guard_state.lua` (LF preserved) extended from 59 checks to 129 (non-vacuity
floor raised 30 → 80). The pre-existing section-3 bite (IsSpellInRange absence guards) had
to grow the R2 mutation into its setup: with R2 in place that dead spell list is never
built, so the absence guard is only reachable through the double mutation — which is
itself evidence that R2 is load-bearing.

## 2. Before / after per client profile

`C_Item.IsItemInRange` exists on all five branches (ItemDocumentation: `classic_era`/
`classic_anniversary`/`classic_titan`:923, `origin/live`:1513, `origin/forever`:1550 —
CONFIRMED-SOURCE). The legacy `IsSpellInRange` global exists on none (zero definitions in
`git grep -nE '(^|[^_.[:alnum:]])IsSpellInRange[[:space:]]*=' <branch> -- Interface`;
live/forever list the removal in `11_0_0_SpellBookAPITransitionGuide.lua:46-47`).
So **all five shipped families take the same two guards**.

| profile | BEFORE (vendor + earlier patches) | AFTER (this lane) |
|---|---|---|
| `classic_era` / `classic_anniversary` / `classic_titan` | item checkers built for every cached HarmItem (the observed block proves at least one was); spell checkers also built and always answer `nil`; whenever any entry existed the interact bands were not installed. `GetHarmMaxChecker(30)`/`(35)` could resolve an item checker → `ADDON_ACTION_BLOCKED` (`LibRangeCheck-2.0.lua:498` from `main.lua:1797`, operator log). Where it resolved a spell checker the ranged check answered `nil` forever. | no item checkers, no spell checkers → harm list = interact bands. `GetHarmMinChecker(2)` → interact 3 (8 yd; Tauren 6, Scourge 7). `GetHarmMaxChecker(30)` and `(35)` → interact 4 (28 yd; Tauren 25, Scourge 27). `GetRange("target")` → numbers (`0-8` / `8-28` / `28-N/A`). No client range call. |
| `origin/live` (Retail 12.1.x) | item checkers built where `GetItemInfo` was cached — the legacy global is absent on this branch, so the resolved `C_Item.IsItemInRange` was still the call (also an invalid path for the addon); spell checkers dead (`nil`). | same as above: interact bands only, no item path, no client range call. |
| `origin/forever` (WoW Forever 1.60.1) | legacy `IsItemInRange` global absent, `C_Item.IsItemInRange` resolved by the lib: item checkers could be built and called; spell checkers dead. | same as above: interact bands only. |
| pre-`C_Item` legacy client (hypothetical; none of the five) | legacy item + spell globals, item/spell checkers answer. | **unchanged** — both guards are inert (`modernItemRange` false, `spellRangeAvailable` true): same 25 item checkers, same order, same answers (test 7). |

Accepted consequences (stated plainly, not hidden):
- The ladder is coarse: melee = the 8-yd interact band, ranged = the 28-yd band. For a
  30-yd spell (rogue Throw) the ranged check flips at 28 yd instead of 30; for a hunter
  (`main.lua` asks for 35) the ranged band is 28 instead of the old 35-yd item band. The
  hunter at 29-41 yd will read "out of range" where Auto Shot could still fire.
- Melee "in range" now means the interact-3 band (8 yd) on every modern client. That was
  already the operator's observed behaviour (the brief's established fact: the melee
  checker at `main.lua:1791` was interact 3), but a client that previously resolved a
  cached 2-4 yd item checker will see the melee band widen. That is the accepted trade for
  never calling the blocked API.
- These are exactly the precision limits the deferred R3 path would remove.

## 3. R3 — DEFERRED, with the exact probe

R3 was declined by the operator on 2026-10-21 ("i have to copy all files over. so use a
test, like we always do."). This lane uses **no** `C_Spell.IsSpellInRange`, adds no feature
flag and leaves no dead branch for it. `C_Spell.IsSpellInRange` exists on all five
branches (SpellDocumentation:601 classic branches, :879 live, :948 forever —
CONFIRMED-SOURCE) but whether the client BLOCKS it from addon code is not decidable
offline (matrix §"Evidence status"; the item block is the only PROVEN block).

The operator would have to run this in the client on Classic Era, on a live target (a
training dummy or any hostile mob), and report whether a red `ADDON_ACTION_BLOCKED` line
appears:

```
/run local ok, r = pcall(C_Spell.IsSpellInRange, 2764, "target") print("ST range probe:", ok, r)
```

(2764 = Throw; swap in any spell id the character has. One line, no addon copy needed.)
Outcome mapping: prints `true`/`false` and no red line → the modern ID-form path is
usable and R3 can be built; a red `ADDON_ACTION_BLOCKED` naming
`C_Spell.IsSpellInRange` → it is blocked, R3 stays closed; prints `nil` → inconclusive
(unknown spell / no valid target), rerun with a known spell id and a live target.

## 4. R4 — every client API the lib calls, audited

Status: **modern** = exists on all five branches under `C_*`; **legacy-only** = a global
that is gone or replaced; **UNCONFIRMED** = no source proof of addon-callability.
`classic_*` = the three classic branches unless split. All lines below are verified in
`/home/sam/wow-ui-source` per branch (CONFIRMED-SOURCE) unless marked UNCONFIRMED.

| API (lib site) | path the lib takes | status | source line verified |
|---|---|---|---|
| `C_Spell.GetSpellInfo` (:403-407) | modern; returns a table, lib reads `.name/.minRange/.maxRange` | modern | `SpellDocumentation.lua` Namespace `C_Spell`:5; `GetSpellInfo` at :190 (`classic_era`, same lines `classic_anniversary`/`classic_titan`), :375 `live`, :416 `origin/forever` |
| `_G.GetSpellInfo` (:408) | fallback only | legacy-only | no assignment anywhere in `Interface` on `classic_era`; removed on live/forever (`11_0_0_SpellBookAPITransitionGuide.lua:132` maps `C_SpellBook.GetSpellInfo = C_Spell.GetSpellInfo`) |
| `C_Item.GetItemInfo` (:415) | modern; truthiness only (era returns the multi-return list) | modern | `ItemDocumentation.lua` Namespace `C_Item`:5; `GetItemInfo` :393 classic, :604 `live`, :626 `origin/forever` |
| `_G.GetItemInfo` (:415 fallback) | fallback only | legacy-only | `Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:42` (`classic_era`; same file `live`) |
| `C_Item.IsItemInRange` (:422, called :498) | **the blocker** | modern + **client-blocked** | `ItemDocumentation.lua:923` classic / `:1513` live / `:1550` forever (arg typed `ItemInfo`, no Protected/Secret marker in the doc); block PROVEN by the operator's 2026-10-21 log |
| `_G.IsItemInRange` (:422 fallback) | not used where `C_Item` exists (i.e. not on any of the five) | legacy-only | `Deprecated_ItemScript.lua:29` on `classic_era`/`classic_anniversary`/`classic_titan` — it IS `C_Item.IsItemInRange`. NOTE: the same file also exists on `live` at :29 (CVar-gated by `GetCVarBool("loadDeprecationFallbacks")`, :4), so live may expose the blocked function under the legacy name too; the matrix line "legacy global ABSENT" is true for `_G` by default but not for this CVar path. Behaviourally moot: R1 keys on `C_Item`, so all five take the guard. |
| `_G.IsSpellInRange` (:421, guarded :470/:491/:816/:831) | **never answers** | legacy-only, ABSENT everywhere | zero definitions in `git grep -nE '(^|...)IsSpellInRange[[:space:]]*='` on all five; removed per `11_0_0_SpellBookAPITransitionGuide.lua:46-47` (live/forever) |
| `C_Spell.IsSpellInRange` (:601 era, :879 live, :948 forever) | **not used (R3)** | modern, addon-callability UNCONFIRMED | `SpellDocumentation.lua` as cited; on live/forever marked `SecretArguments = "AllowedWhenTainted"` |
| `CheckInteractDistance` (:420, called :524/:528) | the new sole ladder | global on all five; **addon-callable on Classic Era PROVEN in-client**; live/forever/Retail UNCONFIRMED | `PlayerScriptDocumentation.lua:101` classic / `:105` live / `:114` forever; Blizzard itself calls it at `Blizzard_UnitPopupShared/UnitPopupSharedUtils.lua:194` classic / `:203` live+forever; live/forever carry `SecretArguments = "AllowedWhenUntainted"` |
| `GetSpellBookItemName` (:412, called :571) | only when `getNumSpells() > 0` (guarded) | legacy-only, guarded | present on classic: `Blizzard_UIPanels_Game/Classic/SpellBookFrame.lua:244`; live/forever: `C_SpellBook.GetSpellBookItemName` (`11_0_0_SpellBookAPITransitionGuide.lua:97`, `SpellBookDocumentation.lua:359`/`:379`) |
| `GetNumSpellTabs` / `GetSpellTabInfo` (:413-414, guarded :561-566) | guarded to 0 on modern | legacy-only, guarded | classic: `SpellBookFrame.lua:468` / `:455,:473`; live/forever: `C_SpellBook.GetNumSpellBookSkillLines` (`11_0_0_SpellBookAPITransitionGuide.lua:87`) |
| `UnitClass` / `UnitRace` (:423-424, called :792-793) | load/init only | global on all five | `UnitDocumentation.lua`: `UnitClass` :495 classic / :900 live / :911 forever; `UnitRace` not in the classic generated docs (partial) but used by Blizzard UI (`Blizzard_AchievementUI/Classic/Blizzard_AchievementUI.lua:1567`) and documented at :2836 live / :2925 forever |
| `UnitCanAttack` / `UnitCanAssist` / `UnitExists` / `UnitIsVisible` / `UnitIsDeadOrGhost` (:416-419, called :712-724, :979-994) | every poll | global on all five | `UnitDocumentation.lua`: `UnitCanAttack` :372 classic / :752 live / :763 forever; `UnitCanAssist` :357 / :734 (live); `UnitExists` :675 / :1164 / :1192; `UnitIsVisible` :1399 / :2339 / :2428; `UnitIsDeadOrGhost` :1857 live / :1931 forever, used at `Blizzard_CompactRaidFrames/Classic/Blizzard_CompactRaidFrameManager.lua:637` (classic) |
| `GetInventoryItemLink` (:425, called :868/:1049) | hand-slot change detection | legacy global on all five; `C_Inventory.GetInventoryItemLink` **UNCONFIRMED** | no `C_Inventory` namespace in the generated docs on any checked branch, so the lib's `(C_Inventory and C_Inventory.GetInventoryItemLink)` half is nil; the global is used by Blizzard at `Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:1045` classic / :1140 live / :1208 forever |
| `GetInventorySlotInfo` (:427) | once at load (`"HANDSSLOT"`) | global; documented live/forever, classic by usage | `PaperDollInfoDocumentation.lua:155` live / :164 forever; classic `Blizzard_CharacterFrame/Classic/DressUpFrames.lua:189`; also PROVEN by the lib loading in-client |
| `GetTime` (:426) | item-request timeout | global on all five | `LuaDurationClockAPIDocumentation.lua:10` classic / :11 live+forever |
| `CreateFrame` (:1172) | one hidden frame | global on all five | documented `PingManagerSecureDocumentation.lua:16` (live/forever); used at `Blizzard_AsyncRequest/Blizzard_AsyncRequest.lua:98` (classic); PROVEN by the lib loading in-client |
| `C_EventUtils.IsEventValid` (:1178, :1183) | event registration guards (earlier lane) | modern, guarded | `EventUtilsDocumentation.lua:25` classic / :26 live+forever |
| `BOOKTYPE_SPELL` (:433, :463/:481) | argument of the legacy spell calls | legacy-only, never evaluated on modern (the call is guarded before) | listed only as a mapping note at `11_0_0_SpellBookAPITransitionGuide.lua:16` on live/forever |
| `LibStub` (:45) | vendored dependency | n/a (addon-side) | `Libs/LibStub` |
| `tinsert`/`tremove`/`wipe`/`pairs`/`next`/`type`/`tostring`/`tonumber`/`setmetatable`/`print` (:391-400) | utility | stable on all clients | WoW Lua globals (not an API surface under change) |

No other blocked-looking call was found in the lib: the only range API calls are the item
checker (now unreachable) and the spell checkers (now not built). `GetItemInfo` is
addon-callable on every branch; it is not the blocked function.

## 5. Tests (offline)

`lua5.1 tests/lrc_guard_state.lua` → **PASS, 129 checks, exit 0**.

What the new checks prove (all execute the real vendored file in a sandboxed client env):

1. **Static pins, exact counts** (7 new): the two probes exist once each; the item-list
   guard, the spell-list guard and the `HarmItems[15]` guard exist exactly once each. A
   silently vanished or duplicated guard fails the suite.
2. **Section 6 — MODERN profile** (`C_Item.IsItemInRange` + `C_Item.GetItemInfo` present,
   no legacy `IsSpellInRange`, `CheckInteractDistance` present, spellbook + spell info
   present so the old code WOULD have built item and spell checkers):
   - (a) the `C_Item.IsItemInRange` spy is **never called** (`item_range_calls == 0`);
   - (b) `harmRC` is exactly `interact:4` (28) then `interact:3` (8); `GetHarmMaxChecker(30)`
     and `(35)` answer a checker + 28, `GetHarmMinChecker(2)` answers a checker + 8, and
     the checkers answer `true`/nil per band;
   - (c) `GetRange("target")` answers `8,28` / `0,8` / `28,nil` in the three band states —
     numbers, no raise; every returned range is a number;
   - the Tauren race override yields 25/6.
3. **Section 7 — LEGACY profile** (legacy `GetItemInfo`/`IsItemInRange`/`IsSpellInRange`,
   no `C_Item`): the harm list is exactly the same **25 item checkers in the same order**
   (exact `range` and `info` sequence pinned), `GetRange` answers `200,nil` with every
   item out of range and `0,2` with every item in range, and the legacy global is still
   the checker being called. R5 proven.
4. **Section 8 — HYBRID guard-isolation profile** (`C_Item` present AND a working legacy
   spell API; no shipped client has both): the min-range spell checker falls through to
   `minRangeCheck`, and the item spy is never called — R1's "do not build the
   `HarmItems[15]` minRangeCheck" clause proven behaviourally.
5. The pre-existing 5 guard sections still pass (spellbook absence, IsSpellInRange absence,
   secret readings, missing CheckInteractDistance). The IsSpellInRange bite now strips the
   R2 spell-list guard together with the absence guards, because R2 is what keeps that
   dead list out of a client's checker tables (documented in the suite).

Full harness: `bash tests/run.sh` → **43 steps, 0 failed**; luacheck
**2 warnings / 0 errors in 85 files** (the two KEEP-ruled floor warnings:
`compat.lua:36 addon_name`, `main.lua:81 pack`). No crossfire reds in this run.

## 6. Mutation proofs (on `/tmp/opencode/range-lrc-guard-mut/tree`, never the working tree)

Tree copied with `rsync -a --exclude=Media --exclude=docs --exclude=.git` (21 MB). Each
mutation applied to the copy's lib only, then `lua5.1 tests/lrc_guard_state.lua`; the
pristine copy restored after each. **All five mutations: exit 1.**

| # | mutation | failing evidence (excerpt) |
|---|---|---|
| M1 | `if itemList and not modernItemRange then` → `if itemList then` | static pin 0≠1; `modern: the harm list is exactly the interact bands (got 25, want 2)`; `harmRC[1] = item:75208`; `GetHarmMaxChecker(30)` → 30; **23 of 129 failed** |
| M2 | `if spellList and spellRangeAvailable then` → `if spellList then` | static pin 0≠1; `modern: ... (got 1, want 2)`; `harmRC[1] = spell:355:Taunt`; `GetHarmMaxChecker(30) answers a checker` FAIL; **23 of 129 failed** |
| M3 | `if HarmItems[15] and not modernItemRange then` → `if HarmItems[15] then` | static pin 0≠1; `hybrid: the blocked item-range API is never called (got 1, want 0)`; **2 of 129 failed** |
| M5 | `local modernItemRange = (C_Item and ...) ~= nil` → `local modernItemRange = true` (R5 breaker: guard over-applied to a legacy client) | static pin; `legacy: the harm list keeps its 25 item checkers (got 1, want 25)`; every order/info pin; `GetHarmMinChecker(2) → 30`; `GetRange → 30` not `200`; legacy global not called; **10 of 129 failed** |
| M6 | `local spellRangeAvailable = type(IsSpellInRange) == "function"` → `= true` | static pin; `modern` list = dead spell checker; `GetHarmMaxChecker(30)` nil; **22 of 129 failed** |

M4 in an earlier draft (the init `minRangeCheck` or-term) was removed with the redundant
guard itself, so there is no untested guard left in the patch.

## 7. UNCONFIRMED / open items

1. **In-client confirmation on Classic Era 1.15.9 is OWED**: the operator must load the
   deployed files, target a mob at <8 yd, 8-28 yd and >28 yd, and confirm (a) no
   `ADDON_ACTION_BLOCKED` from `main.lua` any more, (b) the range string shows numbers
   (`0 - 8` / `8 - 28` / `28 - N/A`), (c) the ranged/melee states follow the bands.
2. **R3 probe** (§3) — the only way to know whether `C_Spell.IsSpellInRange` is blocked;
   until then the coarse ladder is the shipped behaviour.
3. `CheckInteractDistance` addon-callability on `origin/live`, `origin/forever` and Retail
   12.1.x is UNCONFIRMED (`SecretArguments` markers in their generated docs); only the
   Classic Era call is proven in-client.
4. The `C_Inventory.GetInventoryItemLink` half of the lib's capture is UNCONFIRMED — no
   `C_Inventory` namespace in the generated docs on the checked branches; the legacy
   global is what is actually used.
5. `UnitRace` on the classic branches: no generated doc entry (partial classic docs), only
   Blizzard usage + the lib loading in-client. Not ranged-path critical.
6. Hunter precision: the 35-yd request now resolves to the 28-yd band (§2); no code
   change is needed or made, but it is a user-visible coarsening until R3.
7. `live` may expose `_G.IsItemInRange` via the CVar-gated deprecation file
   (`Deprecated_ItemScript.lua:29` on the live branch) — a correction to the matrix's
   "ABSENT" line; behaviourally moot because R1 keys on `C_Item`.

## 8. Filed for other owners (no edits made outside scope)

- **Orchestrator / release docs**: CHANGELOG entry for the range fix (file names, the
  ADDON_ACTION_BLOCKED report, the new coarse ladder), and a TESTING.md in-client check
  for the three bands. Not touched by this lane.
- **R3 builder (future lane)**: needs the §3 probe result first; then the accurate path is
  `C_Spell.IsSpellInRange(spellIdentifier, unit)` as an additional checker *source*, with
  the item checkers staying dead on all five branches.

## 9. Provenance

- Changes: `Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua:436-447,
  594-596, 607-610, 801-803`; `tests/lrc_guard_state.lua` (sections at :280-292, :521,
  :639, :718; floor :761).
- Client sources: `/home/sam/wow-ui-source`, branches `classic_era` (checked out),
  `classic_anniversary`, `classic_titan`, `live`, `origin/forever`, read via
  `git show <branch>:<path>` and `git grep` (2026-10-21).
- Mutation copy + log: `/tmp/opencode/range-lrc-guard-mut/` (local, not committed).

---

# FOLLOW-UP (2026-10-21) — R7: one uniform ladder on every family

Operator instruction: "this must work classic era, classic anniversary, etc. because
classic era and tbc anniversary are different, also need forever/live."

## F1. Why the landed guard was family-dependent

> **Supersedes:** §1–§4 describe the first landing. Where they state "the legacy global
> exists on none" as a load-time fact, or quote the old probe/guard comment text, R7
> below supersedes them; the file itself is one coherent, revised patch (31 insertions /
> 3 deletions cumulative) and F3 is the authoritative behaviour table.

The first landing builds the spell list only `if spellList and spellRangeAvailable`
(`spellRangeAvailable = type(IsSpellInRange) == "function"`). The legacy global is absent
from FrameXML on all five branches, but a global implemented in the client BINARY never
appears in FrameXML — so on `classic_era` / `classic_anniversary` / `classic_titan` its
runtime presence was UNCONFIRMED (`bench/range_api_matrix_2026-10-21.md` FU-2, §1.2). If
it exists there, the guard flips true and the LRC's legacy index/bookType spell checker
(`:483`, `:501`, `:835`, `:851`) is built and called. That is exactly the family-dependent
behaviour the operator rejected.

## F2. What changed (R7)

File: `Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua` (CRLF preserved;
cumulative diff for both landings: 31 insertions / 3 deletions).

| # | file:line | change |
|---|---|---|
| 6 | `LibRangeCheck-2.0.lua:448-454` | new load-time probe `local modernSpellRange = (C_Spell and C_Spell.IsSpellInRange) ~= nil`, with the client-terms WHY: the lib's spell checkers use the LEGACY index/bookType shape; the index-form modern replacement (`C_SpellBook.IsSpellBookItemInRange`) exists only on the 11.0-revamp clients (live/forever), not on the classic branches; on a client shipping the modern range API the legacy shape is superseded, so no spell checker is built and the ladder is identical on every family with ZERO client range calls. `C_Spell.IsSpellInRange` itself is not called (R3 deferred); only its presence is probed. |
| 7 | `LibRangeCheck-2.0.lua:615-619` | `createCheckerList` guard is now `if spellList and spellRangeAvailable and not modernSpellRange then` — the legacy spell path is built only on a client that has the legacy global AND does not ship the modern API (the ancient-client path, kept working by test §7). |

Unchanged from the first landing: the item probe/guards (`:441`, `:603`, `:812`), the
`spellRangeAvailable` probe (`:447`), the interact fallback condition (still
`interactList and not next(res)`), and everything outside the two owned files. R3 is still
not wired; no feature flag; no dead branch.

## F3. Per-family behaviour after R7 (one row per family)

`C_Spell.IsSpellInRange` is present on all five (generated docs + Blizzard callsites:
`SpellDocumentation.lua:601` classic / `:879` live / `:948` forever;
`CooldownViewer.lua:713` classic / `:737` live+forever), so `modernSpellRange` is TRUE on
every shipped family and the spell list is never built — independently of whether the
legacy binary global exists (FU-2 can no longer change the behaviour).

| family | item checker | spell checker | ladder (Human) | ladder (Tauren) | ladder (Scourge) |
|---|---|---|---|---|---|
| `classic_era` | never built | never built | melee 8 / ranged 28 | 6 / 25 | 7 / 27 |
| `classic_anniversary` | never built | never built | melee 8 / ranged 28 | 6 / 25 | 7 / 27 |
| `classic_titan` | never built | never built | melee 8 / ranged 28 | 6 / 25 | 7 / 27 |
| `origin/live` (Retail 12.1.x) | never built | never built | melee 8 / ranged 28 | 6 / 25 | 7 / 27 |
| `origin/forever` (WoW Forever 1.60.1) | never built | never built | melee 8 / ranged 28 | 6 / 25 | 7 / 27 |

For every row: `GetHarmMinChecker(2)` → the interact-3 checker (answers true/nil at the
melee band), `GetHarmMaxChecker(30)` and `(35)` → the interact-4 checker (true/nil at the
ranged band), `GetRange("target")` → `0 - 8` / `8 - 28` / `28 - N/A` (numbers, no raise).
Zero client range API calls. Accepted coarsening (unchanged from the first landing): 8-yd
melee / 28-yd ranged on EVERY family — a hunter's 35-yd request and a rogue's 30-yd Throw
both land on the 28-yd band.

## F4. Tests and mutations (offline)

`lua5.1 tests/lrc_guard_state.lua` → **PASS, 170 checks** (129 before this follow-up).
`bash tests/run.sh` → **43 steps, 0 failed**; luacheck **2 warnings / 0 errors in 85
files** (the two KEEP-ruled floor warnings). No crossfire.

New/updated coverage:
- 2 new static pins: the `modernSpellRange` probe and the
  `spellList and spellRangeAvailable and not modernSpellRange` guard, exact counts.
- New **§9 Era/FU-2 execution profile** — the operator's actual case: legacy
  `IsSpellInRange` present AND `C_Spell.IsSpellInRange` present (plus C_Item, the
  spellbook and a 33-yd spell so an unguarded build WOULD produce a spell checker). Proves
  the harm list is exactly the two interact bands, `GetHarmMaxChecker(30|35)` → 28,
  `GetHarmMinChecker(2)` → 8, `GetRange` answers numbers in all three band states, and
  the legacy spell spy, the modern spell spy and the item spy are ALL at 0 calls.
- **§7 legacy profile made more faithful**: no `C_Item`, **no `C_Spell`**, legacy
  `_G.GetSpellInfo` + `_G.IsSpellInRange` + `_G.IsItemInRange`. It now proves the ancient
  client still BUILD the legacy spell checker (spell at 33, exact 25-item + 1-spell list
  pinned, spell global still called) — R7 must not suppress that path.
- §6 modern and §8 hybrid profiles stay green unchanged.

Mutation proofs on `/tmp/opencode/range-lrc-guard-mut/tree` (rsync without `Media/`,
`docs/`, `.git`; pristine restored after each) — **7/7 exit 1**:

| # | mutation | evidence |
|---|---|---|
| M1 | item list guard removed | 40/170 fail, `harmRC[1]=item:75208` |
| M2 | old spell-list guard (`... and spellRangeAvailable then`) | 41/170, `spell:355:Taunt` |
| **M7** | **R7 guard removed (`... and not modernSpellRange`)** | **19/170: `era/FU-2: the harm list is exactly the interact bands (got 1, want 2)`, `harmRC[1]=spell:355:Taunt`, `GetHarmMaxChecker(30)` nil; legacy spell spy called** |
| M3 | init item minRangeCheck guard removed | 2/170, hybrid spy called |
| **M8** | **`modernSpellRange` forced true (ancient client loses its spell path)** | **14/170: legacy list 26→25, spell checker gone, secret profile flips** |
| M5 | `modernItemRange` forced true (guard over-applied to a legacy client) | 12/170, legacy list 26→1 |
| M6 | `spellRangeAvailable` forced true | 22/170, modern list = dead spell checker |

## F5. R3 — still an OPEN FOLLOW-UP (unchanged, not a recommendation)

The accurate per-class ladder (the modern `C_Spell.IsSpellInRange` path) remains DEFERRED
by operator order and needs ONE in-client confirmation before any code is written. The
probe, paste-in-chat, no file copying (from `bench/range_api_matrix_2026-10-21.md` FU-1):

```
/run local f=CreateFrame("Frame"); f:RegisterEvent("ADDON_ACTION_BLOCKED"); f:SetScript("ADDON_ACTION_BLOCKED",function(_,_,fn) print("BLOCKED:",fn) end); print("types:",type(IsSpellInRange),type(C_Spell and C_Spell.IsSpellInRange),type(C_Item and C_Item.IsItemInRange),type(C_SpellBook and C_SpellBook.IsSpellBookItemInRange)); print("cspell call:",C_Spell.IsSpellInRange(2050))
```

Read: a `BLOCKED:` line → the modern spell API is blocked; no red line plus a
true/false/nil `cspell call:` → callable. This also answers FU-2 (`types:` prints
`legacy:`-style presence), though R7 has already made FU-2 irrelevant to the ladder.
The accepted coarsening stands until then: **8-yd melee / 28-yd ranged on every family**.

## F6. Still UNCONFIRMED

1. In-client confirmation on Classic Era 1.15.9 for both landings (no block, numbers in
   the range string, band transitions) — owed by the operator.
2. R3/FU-1 (above), FU-2's binary presence (now behaviourally moot), the complete
   protected-API list, and addon-callability of `CheckInteractDistance` on live/forever/
   Retail (`SecretArguments` markers only prove the doc field, not a block).
3. `compat.lua:915-941 api.IsSpellInRange` already calls `C_Spell.IsSpellInRange` at
   runtime on every family (consumers: `classes/hunter.lua:2953`,
   `classes/rogue.lua:1508`, `:1543`, and the class out-of-range helpers). That path is
   OUTSIDE this lane's scope and is not changed; if FU-1 proves the API blocked, it is a
   separate fix lane. Recorded here so the operator sees it is not covered by R7.

