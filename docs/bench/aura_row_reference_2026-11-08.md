# WoW Forever aura icon row — reference extraction and SwedgeTimer port map (2026-11-08)

**Lane:** read-only research (`aura-reference-analyst`). **Task:** t2.
**Mode:** read-only. No product file, test, TOC, config, doc or reference-addon edit was made by this lane.
This report is the source material for `bench/briefs/brief_aura_row_impl_2026-11-08.md` (lane T3).

---

## 1. Scope, sources, and pins

| Item | Value |
|---|---|
| Reference addon (read-only) | `/home/sam/SuperSwingTimer-WoW/` — aura code in `SuperSwingTimer_Forever.lua` (2156 lines), lifecycle call site `SuperSwingTimer_UI.lua:2824-2825`, wiring doc `WIRING.md:258-285`, helper contract `SuperSwingTimer_Constants.lua` |
| Target repo (read-only for this lane) | `/home/sam/SwedgeTimer` (`SwedgeTimer.toc` is the one authoritative load order; `## Interface: 11509, 20506, 38002, 40402, 50500, 120100, 120105, 16001`) |
| Client API source (read-only) | `/home/sam/wow-ui-source`, branch `origin/forever`, tip `eac30af597e5aaa43a60f6675ef5fdcea100375f` ("1.60.1 (70790)", 2026-11-04), `version.txt` = `1.60.1.70790` |
| Client spell data (corroboration only) | `/home/sam/wow.export/Spell.csv` — the **1.15.9 SoD/Era client** dump, *not* Forever. Presence does not prove Forever presence; absence does not prove Forever absence (see §4.7) |
| Prior bench art this report does not repeat | `bench/secret_api_matrix_2026-11-06.md`, `bench/secret_consumers_audit_2026-11-06.md`, `bench/forever_display_audit_2026-11-06.md`, `bench/forever_toc_range_power_2026-11-07.md`, `desks/journal.md` tail, `bench/lessons.md` |
| Web search | none used (brief: no web search) |

**Reproducing the id tables.** The reference file loads in plain Lua 5.1 with a bare namespace table, because its file-scope work only touches `ns.HasNativeSwingTimer` / `CreateFrame` behind guards. The extraction used (read-only, `/tmp`):

```lua
local f = assert(loadfile("/home/sam/SuperSwingTimer-WoW/SuperSwingTimer_Forever.lua"))
local ns = {}; f("SuperSwingTimer_Forever.lua", ns)   -- ns.isForever = false, ns.hasAuraContainer = false
-- then walk ns.FOREVER_{STANCE,BUFF,DEBUFF}_SPELLS etc.
```

Every `file:line` below was re-read at the cited line before this report was written (`bench/lessons.md`: "a bench citation's line number is a claim, not a fact").

---

## 2. Executive summary — what the reference actually proves

1. **The native path works and needs no aura *data* read at all.** The addon declares spell ids; the client matches them and writes icon, duration text, stacks and duration bar through secret-safe widget APIs (`SuperSwingTimer_Forever.lua:14-18`, `801-916`). Our port therefore reads **no** `AuraData` field, no `spellId`, no `expirationTime`, ever — that is the whole point of using `AuraContainer`.
2. **Own-caster debuffs are a *filter string*, not a combat-log correlation.** `"HARMFUL|PLAYER"` (`:1582`); `PLAYER` is the client's own-caster filter (`origin/forever:Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua:274`). No `COMBAT_LOG_EVENT_UNFILTERED` and no `PLAYER` bookkeeping is needed. **Answer to the brief's open question: CLEU is not required.**
3. **The container's size is written by the client through `secretwrap`** (`origin/forever:…/Blizzard_CustomAuraContainer.lua:796,800`). Reading the container's `GetWidth/GetHeight/GetTop/GetPoint` can therefore return a *secret* — the reference already discovered this empirically and refuses to measure the debuff row (`:1380-1398`). Our port must never measure an aura container; it anchors by plain numbers and by the *bars'* geometry only. **This is the single biggest porting hazard and it invalidates the naive "anchor the buff row to the debuff row's top" design.**
4. **`includeSpellIDs` is a copied set, and identity matching is privilege-gated.** The client validates and *securecopies* the table (`:236-240`), so the shared/racial merge is frozen at `AddAuraGroup` time — later mutation of our table is ignored by the client (a second documented reason for the brief's "merge at container creation only"). And `includeSpellIDs` only works for helpful auras on player-controlled/group units or harmful auras on non-assistable units (`Blizzard_AuraContainerUtil.lua:52-107`): on a **friendly** target the client rejects every harmful candidate, so the debuff row is empty there by design. That is a feature, not a bug.
5. **`UnitAura` does not exist on Forever.** The global is only installed by the class-gated deprecated shims (`Blizzard_Deprecated.toc` `[AllowLoadGameType classic]`; `Shared/Deprecated_12_1_0.lua` has no `UnitAura`). The reference's "legacy fallback" branch (`SuperSwingTimer_Constants.lua:428-440`) is dead code on Forever. Our port needs **no classic fallback** (confirmed as the brief hoped).
6. **Forever-only is a three-part gate, not one flag.** `st.family == "FOREVER"` + `C_AuraContainerUtil` + the two sort-enum globals, and the *creation* probe is the `CreateFrame` call itself. The reference gates on a native-API probe too (`:36-60`); the healthiest port keeps SwedgeTimer's own family discriminator as the first gate so that non-Forever clients never reach any aura API.
7. **The brief's own throttle number is right and `WIRING.md` is stale.** `MAINTAIN_INTERVAL = 0.15` (`:1643`); `WIRING.md:270` says 0.25 s. Several other `WIRING.md`/comment claims are stale — enumerated in §3.9 so nobody copies them.

**Verdict:** implement the row as a **new Forever-only module, native containers only, zero aura-data reads, zero classic fallback, debuff row above the bar and buff row above a *reserved fixed band*** (not above the measured debuff row). Nothing in the reference requires editing `bars.lua`.

---

## 3. Reference code map (file:line)

All line numbers are `SuperSwingTimer_Forever.lua` unless the path is given.

### 3.1 Client detection and support gates

| What | Lines | Detail (verbatim behaviour) |
|---|---|---|
| `IsForeverClient()` | 36-38 | `type(ns.HasNativeSwingTimer) == "function" and ns.HasNativeSwingTimer() == true` — i.e. `C_SwingTimer` + `Enum.PlayerSwingType` (`SuperSwingTimer_Constants.lua:206-211`) |
| `ns.isForever` | 40 | assigned at file scope, **before** any frame work; the whole file is a no-op when false (`:20-22`) |
| `GetGlobal(name)` | 42-44 | `rawget(_G, name)` — every optional global is read through this, never `_G.X` (a missing global would be nil either way, but `rawget` documents the intent) |
| `HasAuraContainerSupport()` | 50-58 | requires `C_AuraContainerUtil` **table**, `AuraContainerSortMethod` **table**, `AuraContainerSortDirection` **table**; three separate `type` checks, no pcall |
| `ns.hasAuraContainer` | 60 | assigned once at load |
| file-scope frame work | 1757, 2144 | the only frame-creating blocks are `if ns.isForever and ns.hasAuraContainer then` (`:1757`) and `if ns.isForever then` (`:2144`) — proof that a false gate creates nothing |

### 3.2 Secrecy helpers (and what they are *not* used for)

| What | Lines | Detail |
|---|---|---|
| `ns.IsAuraDataSecret()` | 71-85 | `C_Secrets.ShouldAurasBeSecret()` when present; **fail closed** — `pcall` failure returns `true`; a missing `C_Secrets`/function returns `false` (classic line is never secret) |
| `ns.GetSpellAuraSecrecy(id)` | 93-110 | `C_Secrets.GetSpellAuraSecrecy(id)`, returns nil when the client cannot answer; enum values documented at `88` (`0 NeverSecret, 1 AlwaysSecret, 2 ContextuallySecret`) and confirmed at `origin/forever:…/SecretWrapperConstantsDocumentation.lua:13-15` |
| `ns.IsSpellAuraReadable(id)` | 117-133 | `NeverSecret` → true, `AlwaysSecret` → false, `ContextuallySecret` → `not IsAuraDataSecret()` |
| `ns.GetForeverPlayerAura(id)` | 141-169 | the only `C_UnitAuras` read in the file: skips the call when `IsSpellAuraReadable` is false (`:152-154`, because `GetPlayerAuraBySpellID` is `RequiresNonSecretAura`), `pcall`s it, rejects a secret table and secret `spellId/applications/duration/expirationTime`, then `SafeNumber`s each field |
| call sites of `IsAuraDataSecret` | 71, 121, 132, 1857 | **only** inside the secrecy helpers and the diagnostics snapshot. It does **not** gate the native rows — see §3.9 |
| `ns.IsSecretValue(value)` | `SuperSwingTimer_Constants.lua:79-117` | `issecretvalue` when present, then a *behavioural* probe: number → `math.max` survives, string → `string.upper`+table-index survives, table → `next` survives. Any doubt ⇒ secret |
| `ns.SafeNumber` / `ns.SafeString` / `ns.Scrub` | `…Constants.lua:128-158`, `161-187`, `189-220` | documented scrubbing path (`scrubsecretvalues`) with a fixed-arity fallback |

**Porting rule taken from this:** our module never needs any of these helpers on the row itself, because it never reads an aura. `st.api.is_secret` (`compat.lua:183`) is the target-side equivalent if we ever probe a frame read (we should not).

### 3.3 Spell lists and their merge rules

| Block | Lines | Detail |
|---|---|---|
| `FOREVER_STANCE_SPELLS` | 326-376 | left-side single-slot states (aspects/stances/seals/shields/forms/stealth). **Out of scope for our row** (we are not porting the left stance slot); reproduced in §4.1 for completeness because the class lists must not leak stance ids into the buff row |
| `FOREVER_BUFF_SPELLS` | 382-455 | temporary player procs / short cooldown buffs; the header comment (`:378-381`) states permanent/passive/stance buffs (Aspects, Trueshot Aura, Seals, Shields, Battle Shout, Totems, Weapon Imbues) are **deliberately excluded** so the row stays empty until a proc fires |
| `FOREVER_DEBUFF_SPELLS` | 467-525 | player-cast target debuffs, `HARMFUL`; id-provenance note at `:461-466` ("for a direct Apply Aura debuff the client exposes the same spell ID as the cast"; verified list: Serpent Sting 25295, Flame Shock 29228, Rend 11574, Thunder Clap 6343, Demoralizing Shout 1160, Sunder Armor 7386; talents that *trigger* a separate aura differ: Flurry 12320, Vengeance 20050, Seal of Fury 1311647, Venom 1310703, Deep Wounds 12721) |
| `FOREVER_NEW_ABILITY_CANDIDATES` | 531-562 | new Forever abilities that may or may not apply an aura; is a **set** member, so a non-aura id is a harmless no-op (`:527-530`) |
| `FOREVER_SHARED_BUFFS` | 567-573 | deliberately **not** merged into any class list (`:564-566`) |
| `FOREVER_RACIAL_BUFFS` | 578-589 | keyed by race token: `UnitRace` second return first, localized name second (`GetPlayerRacialBuffList`, `:1080-1103`); `Scourge` is the file token for Undead |
| `AppendUnique(list, values)` | 591-602 | in-place, `type(value) == "number"` only, dedupes against the existing list |
| candidates merged into buffers | 604-615 | **both** loops: candidates are appended to the buff list **and** the debuff list for each class. Verified consequence: 18 ids (every candidate) end up in both sets (§4.6) |
| `FOREVER_EXTRA_BUFFS` / `_EXTRA_DEBUFFS` | 625-647 | empty tables (`WARRIOR = { ... }` commented out); the merge loop exists but does nothing today |
| `BuildAuraSpellIDMap(list)` | 652-660 | `map[spellID] = true` for numeric entries; no pcall, no dedupe bookkeeping (set semantics) |

### 3.4 Container creation

| What | Lines | Detail |
|---|---|---|
| `AURA_FRAME_STRATA` | 683 | `"DIALOG"` |
| `PROC_MAX_DURATION` | 684 | `180` (buff group `maxDuration`) |
| sizing constants | 685-700 | `LEFT_STANCE_MIN/MAX_SIZE` 18/24, `LEFT_STANCE_SIZE_BONUS` 2, `BUFF_ICON_WIDTH_TRIM` 2, `BUFF_ICON_HEIGHT_TRIM` 7, `MIN_BUFF_ICON_SIZE` 8, `DEBUFF_TEXT_CLEARANCE` 16, `QUESTION_MARK_ICON` |
| `GetDB()` / `GetFontPath()` / `GetBarTexture()` | 702-715 | optional-chained SuperSwingTimer helpers; **not portable** — SwedgeTimer has `db`, `st.utils.fetch_font_path`, `LibSharedMedia` |
| `CreateAuraContainerFrame()` | 922-933 | `pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")`; on failure retries with `"CustomAuraContainerTemplate"` alone; returns nil if both fail. **The comma-joined template string is a single argument** — Blizzard itself joins templates this way (`Blizzard_AuraContainerFrameProviders.lua:34`) |
| `CreateAuraGroupContainer(groupKey, unitToken, filter, spellList, options)` | 942-1008 | 948 `spellMap = BuildAuraSpellIDMap`; 950-955 `spellCount == 0` ⇒ nil (an empty set never creates a container); 957 one `pcall` around the whole setup; 958 `SetSize(1,1)`; 959 `SetFrameStrata(AURA_FRAME_STRATA)`; 960 `SetUnit(unitToken)`; 962-965 `maxFrames = min(spellCount, 16)`; 967-970 `candidateFilters = { includeSpellIDs = spellMap }` (+`maxDuration` when given); 972-983 `groupOptions = { candidateFilters, maxFrameCount, layout = { elementWidth, elementHeight, elementSpacing = 3 }, initializeFrame = StyleAuraButton }`; 985-992 `sortMethod = AuraContainerSortMethod.Expiration`, `sortDirection = AuraContainerSortDirection.Normal` **only when the globals look right**; 994 `AddAuraGroup(groupKey, filter, groupOptions)`; 999 `SetFlowLayoutAnchorPoint("BOTTOMLEFT")`; 1000 `SetEnabled(true)`; 1001 `Show()` |
| buff group | 1527-1534 | `CreateAuraGroupContainer("forever_buffs", "player", "HELPFUL", containerBuffList, { size, width, height, withBar = false, withCooldown = true, maxDuration = PROC_MAX_DURATION })` |
| debuff group | 1576-1593 | `CreateAuraGroupContainer("forever_debuffs", "target", "HARMFUL|PLAYER", debuffList, { size, withBar = true, withCooldown = false })`; the `PLAYER` rationale is quoted at `:1577-1581` ("Include only auras that were cast by the player, or by the player's pet or vehicle … keeps another hunter's Serpent Sting … off this row") |
| stance slot | 1543-1574 | separate container + `AddAuraSlot("forever_stance", "HELPFUL", { candidateFilters, initializeFrame })` — the only `AddAuraSlot` use (single icon, manually anchored) |
| `StyleAuraButton(frame, options)` | 807-916 | 810-815 `SetSize(width,height)` (bail out if it throws); 818-823 icon texture (`CreateTexture(nil,"BACKGROUND")`, `SetAllPoints`, `SetTexCoord(0.07,0.93,0.07,0.93)`, `SetIcon`); 826-844 4-edge 1px outline via `SetColorTexture(0,0,0,0.65)`; 847-856 duration `FontString` (`SetDurationText(fontString, { textColor = GetLowTimeTextColor() })`); 859-866 stack count (`SetApplicationCount`); 869-895 optional 3px `StatusBar` (`SetDurationBar(bar, { direction = Enum.StatusBarTimerDirection.RemainingTime })`); 898-915 optional `Cooldown` frame (`CooldownFrameTemplate` when available, `SetReverse(true)`, `SetHideCountdownNumbers(true)`, then `SetDurationCooldown`) — **every step is its own `pcall`**, and `SetSize` failure aborts styling so a half-built button is not registered |
| `CreateLowTimeTextColor()` | 763-799 | builds a `C_CurveUtil.CreateColorCurve()` over `Enum.DurationTextBindingProperty.RemainingDuration` (red ≤ 4 s, white above) and hands the **curve** to `SetDurationText`, "so the client's DurationTextBinding evaluates the curve against the secret duration internally and only the resulting colour reaches the font string" (`:757-762`) |
| `ResizeGroupFrames(container, groupKey, w, h)` | 1619-1640 | `GetAuraGroupFrameCount` → `SafeNumber` ("the count is derived from aura frames and can be secret; a numeric for limit would raise", `:1628-1633`) → loop `GetAuraGroupFrame` + `SetSize` in pcall |

### 3.5 Anchor and lifecycle

| What | Lines | Detail |
|---|---|---|
| runtime state table `ns.foreverAura` | 1013-1031 | containers, stance slot, sizes, `lastYOffset/lastBuffWidth/lastBuffHeight/lastDebuffSize/lastDebuffPopulated/lastBuffVisible/lastAnchorBar`, `initAttempts`, `initError` |
| `ns.foreverNativeAuraIcons` | 1034 | "True once the native groups are live; the classic updaters then stand down" |
| `GetAnchorBar()` | 1038-1050 | Hunter: visible+alpha>0 MH else visible+alpha>0 ranged else `ranged or mh`; everyone else: `ns.mhBar or ns.rangedBar`. **A fixed two/three-frame preference, not a topmost-bar computation** — our bars can be anywhere, so the port replaces this with real geometry (§5.4) |
| `GetBuffToggle` / `GetDebuffToggle` / `GetStanceToggle` | 1052-1075 | per-class db keys (`showWarriorBuffIcons` … via `BUFF_TOGGLE_BY_CLASS` `:665-672`), `~= false` (nil ⇒ on) |
| `CountVisibleDebuffBars()` | 730-746 | counts *SuperSwingTimer's own* classic debuff bar frames (`DEBUFF_BARS_BY_CLASS` `:720-728`), `bar:IsShown()` on addon-owned frames |
| `ComputeIconYOffset()` | 748-755 | `8 + visibleDebuffBars * (DEBUFF_BAR_HEIGHT + 2)`; `DEBUFF_BAR_HEIGHT` is SuperSwingTimer state (default 8) |
| `IsForeverDebuffRowPopulated(probeOk, height)` | 1380-1398 | **the secret-height rule**: a probe failure ⇒ false; `IsSecretValue(height)` ⇒ **true** ("A secret height therefore means *populated*"); else `height > 1`. Header comment: "the client hands it back as a SECRET number while the row is populated; … Comparing that height raises" |
| `IsDebuffRowPopulated(container)` | 1403-1409 | `pcall(container.GetHeight)` then the classifier |
| `ApplyContainerAnchors()` | 1415-1452 | debuff row: `ClearAllPoints` + `SetPoint("BOTTOM", bar, "TOP", 0, yOffset)`; buff row: anchored to the **debuff container** (`BOTTOM` → `TOP`, `DEBUFF_TEXT_CLEARANCE = 16`) when the debuff row is populated, else to the bar with `yOffset`; then the stance icon; then records the six `last*` fields |
| `ns.UpdateForeverAuraIcons(elapsed)` | 1649-1732 | 1655-1663 throttle (`MAINTAIN_INTERVAL = 0.15`, `elapsed <= 0` forces a pass); 1667-1679 show/hide by toggle **inside pcall**; 1683-1714 size changes → `SetAuraGroupLayout` + `ResizeGroupFrames`; 1716-1731 re-anchor **only when** bar identity, yOffset, icon w/h, debuff size, populated flag or buff visibility changed |
| init retry | 1757-1784 | event frame created only when `ns.isForever and ns.hasAuraContainer` (`:1757`); `PLAYER_LOGIN` + `PLAYER_ENTERING_WORLD` call `InitForeverAuraIcons` (`:1759-1763`); an `OnUpdate` retries every 0.5 s (`:1765-1782`) and gives up after `initAttempts >= 20` (`:1776-1780`) |
| `InitForeverAuraIcons()` | 1489-1608 | idempotent (`:1491-1493`); nil when not Forever/no container support/no class/no anchor bar (`:1494-1499`); lists at 1502-1507; sizes 1509-1511; container buff list = class ∪ shared ∪ player racials, class list stays pure (`:1513-1524`); containers 1526-1593; success only when at least one container exists (`:1595-1597`); then `foreverNativeAuraIcons = true`, wrap legacy updaters, `activeBuffIconCount = 0`, `ApplyContainerAnchors()`, `UpdateForeverAuraIcons(0)` (`:1599-1607`) |
| `WrapLegacyIconUpdaters()` | 1458-1485 | wraps the six `Update<Class>BuffIcons` (+`UpdateHunterAspect`) so they return early while `foreverNativeAuraIcons` is true; keeps a name-keyed `wrappedLegacyUpdaters` table because "functions cannot carry fields in Lua 5.1" (`:1454-1457`) |
| diagnostics | 1792-1861 | `GetDebuffRowProbe()` returns `"secret"`/`"none"`/`"unreadable"`/height; `GetForeverAuraDiagnostics()` exposes container presence, frame counts (scrubbed), sizes, `auraSecret`, `initAttempts`, `initError` |
| second update call site | `SuperSwingTimer_UI.lua:2824-2825` | `ns.UpdateForeverAuraIcons(0)` at the end of the UI's full-refresh path (an un-throttled pass after a settings/layout change) |

### 3.6 Own-caster debuff filter — is CLEU needed?

No.

* `"HARMFUL|PLAYER"` (`:1582`) is a **client-side filter string**; `PLAYER` is documented as "Include only auras that were cast by the player, or by the player's pet or vehicle" (`origin/forever:Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua:274`), and `AuraUtil.IsValidFilterString` tokenizes on `"| "` and validates each component against `AuraUtil.AuraFilters` (`:294-330`).
* The equivalent candidate filter `isFromPlayerOrPlayerPet` also exists (`Blizzard_CustomAuraContainer.lua:126-137` boolean-only filter list), but the filter string is the documented and reference-proven route; using both would be redundant.
* Consequence of `includeSpellIDs` privilege gating (`Blizzard_AuraContainerUtil.lua:89-107`): on an **assistable/friendly** target, `CanApplyIdentityCandidateFilters` returns false and the `includeSpellIDs` branch then *rejects every aura* — the debuff row shows nothing on friendly targets. On hostile targets identity matching is permitted. Document this to the operator: it is the client protecting against "Move now!"-style encounter debuff detection (`:53-59`).

### 3.7 What is Forever-only and what is shared

Every Forever branch in the reference:

| Branch | Lines |
|---|---|
| `ns.isForever` file-scope assignment and the two guarded frame blocks | 40, 1757, 2144 |
| `ns.hasAuraContainer` | 60, 1494, 1757 |
| `IsAuraDataSecret()` (used by the secrecy helpers, the legacy readers' behaviour and diagnostics) | 121, 132, 1857 |
| `GetSpellAuraSecrecy` / `IsSpellAuraReadable` | 101, 118, 152 |
| `ns.GetForeverPlayerAura` / Maelstrom readers (weave input, not icons) | 141-240 |
| `WrapLegacyIconUpdaters` (permanently stands the classic updaters down once native rows exist) | 1458-1485 |

Shared/not-Forever-specific: the constants, `GetAnchorBar`, `CountVisibleDebuffBars`, `ComputeIconYOffset`, `GetBuffToggle/GetDebuffToggle/GetStanceToggle`, `GetBuffSize/GetDebuffSize`, `StyleAuraButton`, `ResizeGroupFrames`, `GetForeverAuraDiagnostics` — all read SuperSwingTimer db keys that SwedgeTimer does not have. **None of these are copy-pasteable** (§7).

### 3.8 Hand-over between the classic icon groups and the native row

The code does exactly one thing: once any native container exists, the classic updaters become permanent no-ops (`:1599-1600`, `:1470-1483`). There is no per-tick secrecy switch, no "which row owns the aura" arbitration, and no un-wrapping path (the wrap is idempotent, `:1470`, `:1481`). On failure of native setup the classic groups were never suppressed, so nothing needs restoring (`:1777-1779`).

### 3.9 Stale claims in the reference's own documentation — do not copy

The reference's comments/doc drift from its code. Each row was verified against the code:

| Claim | Where | Reality |
|---|---|---|
| "throttled (0.25 s)" | `WIRING.md:270` | `MAINTAIN_INTERVAL = 0.15` (`:1643`) |
| "they no-op while `ns.foreverAuraPending` or `ns.foreverNativeAuraIcons` is set" | `WIRING.md:272-274` | `ns.foreverAuraPending` **does not exist anywhere in the tree** (grep: 0 hits); only `foreverNativeAuraIcons` is consulted (`:1473`) |
| "The classic per-class icon groups are **NOT** wrapped or disabled" | `:1737-1743` | they **are** wrapped and permanently suppressed (`WrapLegacyIconUpdaters`, `:1458-1485`, called at 1600 and 1665) |
| "The native buff row is shown only while `ns.IsAuraDataSecret()` is true, so the two rows never display the same aura" | `:1744-1747` | `IsAuraDataSecret` is never consulted for row visibility (call sites: 71, 121, 132, 1857). Row visibility is the per-class db toggle only (`:1667-1679`) |
| `DEBUFF_BARS_BY_CLASS.PALADIN` includes `"paladinSealVengeanceBar"` | `:724` | the same file says Seal of Vengeance/Corruption do not exist in Forever (`:507`); the bar name is dead weight in a *count* function only |

**Lesson for the port:** copy the mechanics, never the prose.

**Intent vs code (worth an upstream note).** The *intended* hand-over — "classic UnitAura updaters remain active when auras are readable and suppressed only while secret" — appears in the reference's own header (`:20-22` implies it) and is the behaviour the workshop's Forever-audit checklist expects, but the shipped code suppresses unconditionally (§3.8). Our port does not need it (there is no classic icon row in SwedgeTimer); if the operator ever wants the SuperSwingTimer addon corrected, that is a **separate** fix in the reference addon, not in ours.

---

## 4. Per-class spell-id tables with provenance

### 4.1 Legend and method

* Lists below are the **post-merge** tables the reference actually ships (class list + `FOREVER_NEW_ABILITY_CANDIDATES`, `:604-615`). Arrays are in reference order; the `AppendUnique` merge appends candidates last, which is why the last ids of each list are new-Forever ones.
* Markers, per id group:
  * `F` — the reference carries an explicit Forever statement for the id/group (a "Forever:" note, a Forever value/duration, or a Forever-new id `12xxxxx/13xxxxx/14xxxxx/4xxxxx`).
  * `C` — classic-line id, no Forever comment; **present** in the 1.15.9 client `Spell.csv`.
  * `C-` — classic-line id, no Forever comment, **absent** from the 1.15.9 `Spell.csv` (tracked anyway by the reference; unknown elsewhere).
  * `N` — non-aura / candidate by the reference's own words ("may or may not apply an aura", "passive; no aura, harmless").
  * `X-TBC` — the reference explicitly marks it TBC-only. **Excluded from the port.**
  * `X-REMOVED` — the reference explicitly says it was removed from Forever. **Never added.**
  * `U` — unverified beyond the reference (no client-data corroboration and no Forever comment).
* Client-data caveat: `Spell.csv` is the **1.15.9** client, so `C` is corroboration only. Counter-example that proves the dump cannot be used as a gate: the reference ships `FOREVER_SHARED_BUFFS` (Bloodlust 2825, Heroism 32182, Drums 35476/35477, Haste Potion 28507) and **all five are absent from 1.15.9** while the reference ships them as Forever buffs — Forever is a custom server with spells the SoD client does not have.

### 4.2 WARRIOR

**Buffs (26 ids)** — reference `:383-402`, candidates `:532-536`:

| ids | reference comment | marker |
|---|---|---|
| 7384, 7887, 11584, 11585 | Overpower r1-r4 | C |
| 2565 | Shield Block (Forever: 7 s) | F |
| 12319, 12320 | Flurry talent + rank-1 buff aura | C |
| 12292 | Death Wish (Forever: 30 s) | F |
| 1719 | Recklessness (Forever: 15 s) | F |
| 12328 | Sweeping Strikes | C |
| 20230 | Retaliation | C |
| 871 | Shield Wall (Forever: 12 s) | F |
| 12975 | Last Stand | C |
| 23920 | Spell Reflection | C |
| 18499 | Berserker Rage | C |
| 30033 | Rampage | C- |
| 2687 | Bloodrage | C |
| 12317 | Enrage | C |
| 23881, 23892, 23893, 23894 | Bloodthirst r1-r4 (Forever: new 10 s self buff) | F |
| 1329555 | Reckless Swings (Forever: new, 8 s) | F |
| 402927 | Victory Rush (candidate) | N, U |
| 1310222 | Spearing Strike (candidate) | N, U |
| 1240193 | Slam (Forever rebuild) (candidate) | N, F |

**Debuffs (29 ids)** — reference `:468-474`, candidates `:532-536`:

| ids | reference comment | marker |
|---|---|---|
| 772, 6546, 6547, 6548, 11572, 11573, 11574 | Rend (Forever: unchanged) | F |
| 12721, 12834 | Deep Wounds aura + talent candidate | C |
| 7386, 7405, 8380, 11596, 11597, 25225 | Sunder Armor (unchanged, 5 stacks) | C / 25225 = C- |
| 6343, 8198, 8204, 8205, 11580, 11581 | Thunder Clap (10 s, 20% slow) | F |
| 1160, 6190, 11554, 11555, 11556 | Demoralizing Shout (Forever: 45 s) | F |
| 402927, 1310222, 1240193 | (candidates, merged into both lists) | N, U |

### 4.3 PALADIN

**Buffs (17 ids)** — reference `:403-411`, candidates `:552-555`:

| ids | reference comment | marker |
|---|---|---|
| 31884 | Avenging Wrath | C- |
| 642, 1020 | Divine Shield r1-r2 | C |
| 10278, 1022, 5599 | Blessing of Protection r1-r3 | C |
| 20925, 20927, 20928, 1239570 | Holy Shield r1-r4 (r4 new in Forever) | F |
| 498, 5573 | Divine Protection r1-r2 | C |
| 20049, 20050 | Vengeance talent + rank-1 buff aura | C |
| 1310735 | Unsealed Wrath (Forever: new, 15 s / 3 stacks) | F |
| 679 | Holy Strike (candidate) | N, C- |
| 1311606 | Holy Shock (Forever: 10 s cooldown) (candidate) | N, F |

**Debuffs (19 ids)** — reference `:498-508`, candidates `:552-555`:

| ids | reference comment | marker |
|---|---|---|
| 20188, 20300, 20301, 20302, 20303 | Judgement of the Crusader r2-r6 (Forever: 40 s) | F |
| 20185, 20344, 20345, 20346 | Judgement of Light r1-r4 (Forever: 40 s) | F |
| 20186, 20354, 20355 | Judgement of Wisdom r1-r3 (Forever: 40 s) | F |
| 20183, 20411, 20412, 20413, 20414 | Judgement of Fury r3-r7 (Forever: new 3 s taunt) | F |
| — | "Seal of Vengeance / Seal of Corruption do not exist in Forever." | X-REMOVED (not in lists) |
| 679, 1311606 | (candidates, merged into both lists) | N |

### 4.4 SHAMAN

**Buffs (9 ids)** — reference `:412-421`, candidates `:549-551`:

| ids | reference comment | marker |
|---|---|---|
| 30823 | Shamanistic Rage | C- |
| 16280 | Flurry (Classic rank) | C |
| 16256 | Flurry (Forever talent; buff aura is server-side) | F |
| 29180 | Elemental Devastation | C |
| 425336 | Rage of the Farseer (Forever: new, +30% attack speed, 25 s) | F |
| 408505 | Maelstrom Weapon aura (Instant, 30 s, -20% Lightning Bolt) | F |
| 408498 | Maelstrom Weapon talent/buff record (passive; harmless if not an aura) | N, F |
| 1223031 | Improved Stormstrike (Forever: 15 s mana-regen buff) | F |
| 408341 | Fire Nova (candidate) | N, U |

**Debuffs (19 ids)** — reference `:490-497`, candidates `:549-551`:

| ids | reference comment | marker |
|---|---|---|
| 8050, 8052, 8053, 10447, 10448, 29228 | Flame Shock (Forever: 12 s) | F |
| 17364 | Stormstrike (Forever: 12 s) | F |
| 8056, 8058, 10472, 10473 | Frost Shock (Forever: 8 s slow) | F |
| 8042, 8044, 8045, 8046, 10412, 10413, 10414 | Earth Shock r1-r7 (2 s school lockout; harmless if the client exposes it as a plain debuff aura) | C |
| 408341 | (candidate, merged into both lists) | N, U |

### 4.5 DRUID

**Buffs (12 ids)** — reference `:422-430`, candidates `:543-548`:

| ids | reference comment | marker |
|---|---|---|
| 16870 | Clearcasting | C |
| 5217 | Tiger's Fury | C |
| 22842 | Frenzied Regeneration | C |
| 22812 | Barkskin | C |
| 1850, 9821 | Dash r1-r2 | C |
| 5229 | Enrage | C |
| 29166 | Innervate | C |
| 407995 | Primal Bite (replaces Mangle) (candidate) | N, F |
| 16958 | Blood Frenzy (passive; no aura, harmless) (candidate) | N |
| 1223246 | Rend and Tear (passive; no aura, harmless) (candidate) | N |
| 417051 | Natural Reaction (passive; no aura, harmless) (candidate) | N |

**Debuffs (30 ids)** — reference `:480-489`, candidates `:543-548`:

| ids | reference comment | marker |
|---|---|---|
| 1079, 9492, 9493, 9752, 9894, 9896, 27008 | Rip (Forever: 12 s) | F / 27008 = C- |
| 1822, 1823, 1824, 9904, 27006 | Rake (r4 = 9904; 9907 is Faerie Fire) | C / 27006 = C- |
| 1328617, 1328616, 414644, 1235826, 1235827 | Lacerate (Forever r1-r5, 15 s / 5) | F |
| 770, 778, 9749, 9907 | Faerie Fire (Forever: usable in forms, 40 s) | F |
| 99, 1735, 9490, 9747, 9898 | Demoralizing Roar (Forever: 30 s) | F |
| — | "Mangle 33876/33878 and Faerie Fire (Feral) 16857 were removed from Forever 1.60.1 (Primal Bite 407995 replaces Mangle and has no debuff); do not add them back." | X-REMOVED (33876, 33878, 16857 — keep out) |
| 407995, 16958, 1223246, 417051 | (candidates, merged into both lists) | N |

### 4.6 ROGUE

**Buffs (22 ids)** — reference `:440-454`, candidates `:537-542`:

| ids | reference comment | marker |
|---|---|---|
| 5171, 6774 | Slice and Dice r1-r2 (Forever: 9-21 s by CP) | F |
| 13750 | Adrenaline Rush | C |
| 13877 | Blade Flurry (Forever: +20% attack speed, 15 s) | F |
| 14177 | Cold Blood | C |
| 5277 | Evasion | C |
| 2983, 8696, 11305 | Sprint r1-r3 | C |
| 1856, 1857 | Vanish r1-r2 | C |
| 14179 | Premeditation (Classic rank) | C |
| 14183 | Premeditation (Forever: 20 s) | F |
| 36554 | Shadowstep | C- |
| 31209 | Cloak of Shadows | C- |
| 14278 | Ghostly Strike (Forever: 7 s) | F |
| 1329328, 1310703 | Venom ability + triggered buff aura | F |
| 1329283 | Shank (off-hand strike, not a swing) (candidate) | N, U |
| 399956 | Mutilate (candidate) | N, U |
| 1329256 | Blood Splatter (passive; no aura, harmless) (candidate) | N |
| 1328825 | Poised (passive; no aura, harmless) (candidate) | N |

**Debuffs (19 ids)** — reference `:475-479`, candidates `:537-542`:

| ids | reference comment | marker |
|---|---|---|
| 1943, 8637, 8639, 8640, 11273, 11274, 11275, 26867 | Rupture (Forever r6 = 11275) | F / 26867 = C- |
| 8647, 8649, 8650, 11197, 11198, 26996 | Expose Armor (Forever: 30 s) | F / 26996 = C- |
| 16511 | Hemorrhage (Forever: 15 s) | F |
| 1329283, 399956, 1329256, 1328825 | (candidates, merged into both lists) | N |

### 4.7 HUNTER

**Buffs (11 ids)** — reference `:431-439`, candidates `:556-561`:

| ids | reference comment | marker |
|---|---|---|
| 19574 | Bestial Wrath | C |
| 3045 | Rapid Fire | C |
| 34692 | The Beast Within | C- |
| 6150 | Quick Shots | C |
| 34949 | Rapid Killing | C- |
| 34477 | Misdirection | C- |
| 19552 | Deadly Aspects (Forever: new, +30% melee haste, 12 s) | F |
| 1317257 | Strider Kick (candidate) | N, U |
| 19306 | Counterattack (candidate) | N |
| 1495 | Mongoose Bite (candidate) | N |
| 2973 | Raptor Strike (candidate) | N |

**Debuffs (45 ids, 44 after excluding the TBC rank)** — reference `:509-524`, candidates `:556-561`:

| ids | reference comment | marker |
|---|---|---|
| 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295 | Serpent Sting; "Forever rank 9 is 25295 (level 60)" | F |
| **27019** | "27019 is the TBC rank and is kept only for TBC Anniversary" | **X-TBC — EXCLUDE** |
| 2974, 14267, 14268 | Wing Clip: Forever ranks 2/3 are 14267/14268 | F |
| 5116, 13585, 13586, 13587, 13588, 13589, 13590, 27068 | Concussion Shot | C / 13588 and 27068 = C- |
| 13795, 14302 | Immolation Trap | C |
| 13813, 14303, 14304, 14305 | Explosive Trap | C |
| 1499, 14310, 14311, 3355, 14308, 14309 | Freezing Trap | C |
| 13809, 13810 | Frost Trap | C |
| 1130, 14323, 14324, 14325 | Hunter's Mark: Forever ranks 1-4 are 1130/14323/14324/14325 (120 s) | F |
| 1310533 | Lacerating Strikes (Forever: 21 s bleed) | F |
| 1265831 | Savage Rend (Forever pet bleed, 18 s) | F |
| 1317257, 19306, 1495, 2973 | (candidates, merged into both lists) | N |

### 4.8 STANCE list (documented, **not** ported)

The reference's third tier (`:326-376`) is a **single left-side slot** beside the bar (`AddAuraSlot`, `:1558`), not a row. Our brief is a buff/debuff *row above the bars*; porting the stance slot is a separate feature. Reproduced so the impl lane can prove stance ids never leak into the buff row:

* HUNTER (19): 27044, 25296, 14322, 14321, 14320, 14319, 14318, 13165 (Aspect of the Hawk r1-r8); 34074 (Viper); 13163 (Monkey); 5118, 13159 (Cheetah/Pack); 1299447, 1299446, 1299445, 13161, 13171 (Aspect of the Beast Forever r1-r4 + Classic); 20190, 20043 (Wild r1-r2)
* WARRIOR (3): 2457 Battle Stance, 71 Defensive Stance, 2458 Berserker Stance
* PALADIN (36): 20920, 20919, 20918, 20915, 20375 (Seal of Command r1-r5); 1311649, 1311656, 1311647, 20423, 20422, 20421, 20419, 20163 (Seal of Fury ability + triggered buff ranks); 20308, 20307, 20306, 20305, 20162, 21082 (Seal of the Crusader r1-r6); 20293, 20292, 20291, 20290, 20289, 20288, 20287, 21084, 20154 (Seal of Righteousness r1-r8); 20357, 20356, 20166 (Seal of Wisdom r1-r3); 20349, 20348, 20347 (Seal of Light r1-r4); 20165, 20164 (Seal of Justice)
* SHAMAN (8): 10432, 10431, 8134, 945, 905, 325, 324 (Lightning Shield r1-r7, shows remaining charges); 52127 (Water Shield)
* DRUID (6): 9634 Dire Bear, 5487 Bear, 768 Cat, 24858 Moonkin, 783 Travel, 1066 Aquatic
* ROGUE (4): 1787, 1786, 1785, 1784 (Stealth r1-r4)

Reference test corroboration: stances must not appear in the buff lists (`SuperSwingTimer_Tests.lua:3057-3105` `StanceSpells_SegregatedFromProcBuffs`), all new ids are tracked somewhere (`:3039-3055` `NewAbilities_AreTracked` — includes 402927, 1310222, 1329555, 1240193, 1329283, 1329328, 399956, 1328825, 1328617, 407995, 1223246, 417051, 408498, 425336, 408341, 1223031, 679, 1311649, 20183, 1310735, 1317257, 1310533, 19306, 19552, 13161, 1265831), and the druid removals (`:3128-3140`).

### 4.9 Shared and racial

`FOREVER_SHARED_BUFFS` (`:567-573`) — 2825 Bloodlust, 32182 Heroism, 35476 Drums of Battle, 35477 Drums of Speed, 28507 Haste Potion. All `C-` (absent from 1.15.9), i.e. Forever-only by reference assertion; merged into the **buff** container only, never into a class list (`:564-566`, `:1513-1524`).

`FOREVER_RACIAL_BUFFS` (`:578-589`), buff container only, player's own race only:

| race token | ids | marker |
|---|---|---|
| Orc | 20572 Blood Fury | C |
| Troll | 26297 Berserking | C |
| Draenei | 28880 Gift of the Naaru | C- / U |
| BloodElf | 28730 Arcane Torrent | C- / U |
| Human | 20600 Perception | C |
| Dwarf | 20594 Stoneform | C |
| Gnome | 20589 Escape Artist | C |
| Undead | 7744 Will of the Forsaken | C |
| Scourge | 7744 (UnitRace file token for Undead) | C |
| NightElf | 58984 Shadowmeld | C- / U |

`GetPlayerRacialBuffList` reads `UnitRace("player")` → `(localizedName, raceFile)`, probes the **file token first**, then the localized name, and skips everything when the token is secret (`SafeString` ⇒ nil) — `:1080-1103`. Note the two-key design (`Scourge`/`Undead`) exists because clients disagree on the file token.

### 4.10 Exact ported sets (what the impl lane must ship)

`AURA_ICONS_BUFFS` — class arrays exactly as in §4.2-4.7 (26 / 17 / 9 / 12 / 22 / 11 → total 97 ids, 18 of them duplicated in the debuff arrays).
`AURA_ICONS_DEBUFFS` — same tables **minus 27019** (29 / 19 / 19 / 30 / 19 / 44 → total 160 ids).
`AURA_ICONS_SHARED` — 5 ids (§4.9).
`AURA_ICONS_RACIAL` — the 10-key table in §4.9.

Overlap audit (verified by script, §4 method): the 18 ids that appear in both a buff and a debuff array are exactly the `FOREVER_NEW_ABILITY_CANDIDATES` of the six classes — 402927, 1310222, 1240193 (WARRIOR); 679, 1311606 (PALADIN); 408341 (SHAMAN); 407995, 16958, 1223246, 417051 (DRUID); 1329283, 399956, 1329256, 1328825 (ROGUE); 1317257, 19306, 1495, 2973 (HUNTER). No stance id overlaps a buff or debuff array in the reference (verified: 0 stance/buff, 0 stance/debuff hits).

**Port decision on candidates — recommended: keep the reference's double merge.** Rationale: `includeSpellIDs` is a set and an id that never produces an aura of the opposite type matches nothing, so the cost is zero; dropping the debuff-side merge would silently lose any Forever ability that only applies a *target* debuff (the reference cannot tell which of the candidates do, and neither can we offline). Pin it with a test so it is a decision, not an accident. The alternative (candidates only in the buff array) is a one-line change the Lead may prefer for tidiness; if chosen, record it in the module header and in the test name.

**Port decision on `27019` — exclude** (reference says TBC-only, §4.7), and record the exclusion in the module header so a future "restore parity with SuperSwingTimer" pass does not re-add it.

---

## 5. API confirmation table (`origin/forever`, tip `eac30af5`, `1.60.1.70790`)

Every row was read from the cited file at the cited line. "RUNTIME" rows are behaviours no offline source can prove — they are in the UNCONFIRMED register (§8).

### 5.1 Templates and intrinsic type

| Claim | Citation | Verdict |
|---|---|---|
| `CustomAuraContainerTemplate` exists and is **declared for external creation** | `Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.xml:4-13` — `<ScopedModifier useForbiddenObjectTable="true" allowUntaintedCreation="true">` wrapping `<AuraContainer name="CustomAuraContainerTemplate" virtual="true">` with `CustomAuraContainerInboundMixin … secureDelegates="true"` and `editModePreviewEnabled = true` | CONFIRMED (declaration) |
| `CustomAuraButtonTemplate` exists, but is **not** marked `allowUntaintedCreation` | `Blizzard_CustomAuraButton.xml:4-12` — same shape without that attribute | CONFIRMED — the addon never creates buttons itself; the container's frame provider does (`Blizzard_AuraContainerFrameProviders.lua:78`) |
| `DisableUntrustedLayoutScriptsTemplate` exists and is meant for **addon-created frames that anchor to a container** | `Interface/AddOns/Blizzard_SharedXMLBase/ForbiddenAspectTemplates.xml:5-22` — header comment: "These templates are exposed for user addons that need to opt their own Lua-created frames into disallowing script execution via forbidden aspects, as we don't allow implicit inheritance of forbidden aspects through SetParent / SetPoint calls at this time, nor tainted calls to AddForbiddenAspects on frames created by tainted code"; the template sets `ForbiddenAspect aspect="UntrustedLayoutScriptExecution"` | CONFIRMED |
| Why the reference puts the template **on the container** | `Blizzard_CustomAuraContainer.lua:318-324`: "Aura groups resize the container … it is impossible for user addons to anchor other frames that don't have this aspect applied to the container once a group is set — for that, they can inherit DisableUntrustedLayoutScriptsTemplate on those frames at the point of creation"; then `self:AddForbiddenAspects(Enum.ForbiddenAspect.UntrustedLayoutScriptExecution)` | CONFIRMED as source text. **The reference's own one-line rationale (`:918-920`) is a paraphrase** — keep the template (faithful, harmless) and treat the *precise* reason as UNCONFIRMED |
| `AuraContainer` intrinsic frame | `Blizzard_AuraContainer.xml:4-18` — `<ScopedModifier … allowUntaintedCreation="true"><Frame name="AuraContainer" intrinsic="true">`, KeyValues `enabled=true`, `unitToken="none"`, scripts `OnLoad_Intrinsic/OnShow_Intrinsic/OnHide_Intrinsic/OnEvent_Intrinsic`, `AuraContainerInboundMixin … secureDelegates="true"` | CONFIRMED |
| `CreateFrame(..., "<tplA>, <tplB>")` comma-joined template strings are a supported pattern | `Blizzard_AuraContainerFrameProviders.lua:34`: `string.join(", ", "CustomAuraButtonTemplate", unpack(description.templateNames or {}))` | CONFIRMED as Blizzard's own usage |

### 5.2 Enums and container constants

| Claim | Citation | Verdict |
|---|---|---|
| `AuraContainerSortMethod` global with `Expiration = 4` | `Blizzard_AuraContainerShared.lua:40-51` (table), `:46` `Expiration = 4`, re-exported `_G.AuraContainerSortMethod = securecopy(...)` at `:262` | CONFIRMED |
| `AuraContainerSortDirection` global with `Normal = 0`, `Reverse = 1` | `:53-57`, re-export `:263` | CONFIRMED |
| Sort values are validated against the enum | `Blizzard_CustomAuraContainer.lua:29-32` `ValidateSortOptions` → `EnumUtil.IsValid(AuraContainerSortMethod, sortMethod)`; defaults `Default`/`Normal` at `:127-153` | CONFIRMED |
| `C_AuraContainerUtil` namespace exists, functions are `AllowedWhenUntainted` | `Blizzard_APIDocumentationGenerated/AuraContainerUtilDocumentation.lua:3-5` (`Name = "AuraContainerUtil"`, `Namespace = "C_AuraContainerUtil"`, `Environment = "All"`), each `Process*Options` has `SecretArguments = "AllowedWhenUntainted"` | CONFIRMED as documentation. **Runtime existence on Forever: RUNTIME** |
| Frame batch size and taint access restriction | `Blizzard_AuraContainerShared.lua:103-109` — `FrameCreationBatchSize = 10` ("Must be sufficiently high to obfuscate the number of auras"), `AccessRestrictionFlags = Enum.ScriptObjectAccessRestriction.DenyTaintedAccessWhenAurasAreSecret` | CONFIRMED — expect ~10 button frames per group even with zero auras, and expect button frames to be **taint-inaccessible while auras are secret** |
| Container internals: aura processing policy, flow layout created in `OnLoad`, default layout | `Blizzard_CustomAuraContainer.lua:577-587` | CONFIRMED |
| Self-refresh events the container already handles | `:596-606` — `PLAYER_ENTERING_WORLD`, `PLAYER_LEAVING_WORLD`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, `PLAYER_SPECIALIZATION_CHANGED`, `UNIT_FACTION`, `UNIT_FLAGS` | CONFIRMED — no addon subscription needed for those |
| Container layout defaults (flow layout axis/growth/padding/line size) | `Blizzard_AuraContainerShared.lua:114-125` (`axis = AnchorUtil.FlowLayoutAxis.Horizontal`, `anchorPoint = "TOPLEFT"`, growth `Right`/`Down`, padding 0, `maximumLineSize = math.huge`) applied by `CustomAuraContainerPrivateMixin:ApplyFlowLayoutDefaults` (`:760-768`) | CONFIRMED |
| Flow-layout enum values | `Interface/AddOns/Blizzard_SharedXMLBase/AnchorUtil.lua:465-476` — `FlowLayoutAxis {Horizontal=0, Vertical=1}`, `FlowDirection {Left=-1, Right=1, Up=1, Down=-1}` | CONFIRMED |

### 5.3 Group/slot creation API

| Claim | Citation | Verdict |
|---|---|---|
| `AddAuraGroup(groupKey, filterString, options)` asserts a non-empty unique key and `AuraUtil.IsValidFilterString(filterString)` | `Blizzard_CustomAuraContainer.lua:286-290`; filter grammar `Blizzard_FrameXMLUtil/AuraUtil.lua:266-330` | CONFIRMED |
| Inbound options are **validated, merged over defaults and securecopied** | `:236-240` `CopyAndValidateInboundTable(untrustedOptions, defaultOptions, validationFunction)` → `MergeTable(mergedOptions, securecopy(untrustedOptions))`; `GetInboundAddAuraGroupOptions` `:252-256` | CONFIRMED — our `includeSpellIDs` table is copied at creation; later mutation of our table is invisible to the client |
| `includeSpellIDs` is a **map keyed by spell id** (`map[spellId] = true`) | `:79-88` validation; `Blizzard_AuraContainerUtil.lua:101-107` membership test `not candidateFilters.includeSpellIDs[auraData.spellId]` | CONFIRMED |
| Identity filtering is privilege-gated (helpful on player/group, harmful on non-assistable, never-secret exempt) | `Blizzard_AuraContainerUtil.lua:52-84` (`CanApplyIdentityCandidateFilters`), `:89-110` (`DoesAuraPassCandidateFilters`, including "Auras that can't be matched by spell ID are rejected outright"), comment `:53-63` | CONFIRMED |
| `maxDuration` = maximum aura duration (not remaining), non-nil hides permanent auras | `Blizzard_CustomAuraContainer.lua:104-110` | CONFIRMED |
| `AddAuraGroup` binds a custom frame provider (batch 10), registers the group and adds the layout | `:292-312` | CONFIRMED |
| `AddAuraSlot` renders **one** aura, manually anchored, batch = 1 | `Blizzard_CustomAuraContainer.lua:417-440`; `:772-785` `CreateAuraSlotFrame` (batchSize = 1); defaults doc `Blizzard_AuraContainerShared.lua:167-186` — "An aura slot renders a single aura at the front of a priority list. They do not take part in dynamic layout and must be manually anchored." | CONFIRMED → **`AddAuraGroup` is the right call for a row of N auras; `AddAuraSlot` only for a single icon** |
| `SetAuraGroupLayout(groupKey, {elementWidth, elementHeight, elementSpacing, …})` | `:409-415`; validator `:141-175` | CONFIRMED |
| `SetFlowLayoutAnchorPoint(point)` / `SetFlowLayoutGrowthDirection(h, v)` | `Blizzard_AuraContainerFlowLayout.lua:19-25`, `:33-42` (`EnumUtil.IsValid(AnchorUtil.FlowDirection, …)`) | CONFIRMED |
| Inbound mixin composition (all row methods are on the **inbound** mixin) | `Blizzard_CustomAuraContainer.lua:574` — `CustomAuraContainerInboundMixin = CreateFromMixins(ManagedAuraContainerInboundMixin, AuraContainerFlowLayoutInboundMixin, CustomAuraContainerSharedMixin)` | CONFIRMED |
| Container `SetEnabled(bool)` / `SetUnit(unitToken)` exist and refresh the display | `Blizzard_AuraContainer.lua:24-46` (`SetEnabled` → `UpdateEventRegistrations` + `UpdateAllAuras`; `SetUnit` asserts a string) | CONFIRMED |
| Frame enumeration (`GetAuraGroupFrameCount`, `GetAuraGroupFrame`) is exposed and non-existent groups behave as empty | `Blizzard_CustomAuraContainer.lua:344-360` | CONFIRMED |
| `initializeFrame` runs in the secure environment with the button's **object table**, and access restrictions are applied *after* it | `Blizzard_AuraContainerFrameProviders.lua:77-101`: `CreateFrameOutbound("AuraButton", nil, parent, templateString)`, `securecallfunction(self.initializeFrame, auraFrame:GetObjectTable())`, then `ApplyAccessRestrictions(...)`, then `UpdateAuraDisplay()` | CONFIRMED — this is why the style callback may create textures/font strings, and why every style step must be pcall'd |
| The container sizes **itself** through `secretwrap` | `Blizzard_CustomAuraContainer.lua:794-801`: `element:SetPoint(secretwrap(anchorPoint, container, anchorPoint, offsetX, offsetY))` and `container:SetSize(secretwrap(width, height))` | **CONFIRMED — container geometry can be secret; never read it** |

### 5.4 Aura button (display) API

| Claim | Citation | Verdict |
|---|---|---|
| `SetIcon(texture)` | `Blizzard_CustomAuraButton.lua:243-252` | CONFIRMED |
| `SetDurationText(fontString, options)` — options are `securecopy`d through `C_AuraContainerUtil.ProcessCustomAuraButtonDurationTextOptions`; the font string gets `SecretAspect.Text`, `.Alpha`, `.VertexColor`; the client binds duration and an optional colour curve | `:178-215` | CONFIRMED — the countdown text is written by the client, so it is secret-safe by construction |
| `SetApplicationCount(fontString, options)` — `SecretAspect.Text`, `.Shown` | `:87-101` | CONFIRMED |
| `SetDurationBar(statusBar, options)` — `SecretAspect.BarValue` | `:224-235` | CONFIRMED |
| `SetDurationCooldown(cooldown)` — requires an object of type `Cooldown`, adds `SecretAspect.Cooldown`, `.Shown` | `:159-170` | CONFIRMED |
| Every setter validates the passed region against the button (`ValidateInboundScriptObject` + `RequireObjectType`) | `:159-161`, `:178-180`, `:224-226`, `:87-89`, `:243-246` | CONFIRMED — a wrong widget type throws, hence one pcall per style step |
| `shown`/`alpha` of aura frames/buttons can be secret | `:159-170` (`SecretAspect.Shown`), reference `:1287-1301` (never boolean-test the stance slot's `IsShown`) | CONFIRMED → **never read back the row's own state; keep our own booleans** |

### 5.5 Secrecy predicates and aura readers

| Claim | Citation | Verdict |
|---|---|---|
| `C_Secrets` namespace (`Name = "SecretUtil"`, `Namespace = "C_Secrets"`, `Environment = "All"`) | `SecretPredicateAPIDocumentation.lua:3-5` | CONFIRMED |
| `ShouldAurasBeSecret()` → "Returns true if queries for aura data will generally produce secret values" | `:119-127` | CONFIRMED |
| `ShouldSpellAuraBeSecret(spellIdentifier)` | `:139-153` | CONFIRMED |
| `GetSpellAuraSecrecy(spellIdentifier)` → `SecrecyLevel` | `:45-59` | CONFIRMED |
| `HasSecretRestrictions()` → "true if this client build has secret value restrictions enabled" | `:93-101` | CONFIRMED |
| `ShouldUnitAuraIndexBeSecret` / `ShouldUnitAuraInstanceBeSecret` / `ShouldUnitAuraSlotBeSecret` exist | `:220-237`, `:238-254`, `:255-271` | CONFIRMED |
| `Enum.SecrecyLevel`: `NeverSecret = 0`, `AlwaysSecret = 1`, `ContextuallySecret = 2` | `SecretWrapperConstantsDocumentation.lua:6-16` | CONFIRMED |
| Readers: `C_UnitAuras.GetAuraDataByIndex` / `GetAuraDataBySlot` / `GetAuraDataByAuraInstanceID` are `RequiresUnitAuraAccess` + `SecretWhenUnitAuraRestricted` + `SecretArguments = "AllowedWhenUntainted"` | `UnitAuraDocumentation.lua:208-225`, `:227-243`, `:191-206` | CONFIRMED |
| `C_UnitAuras.GetPlayerAuraBySpellID` is `SecretWhenUnitAuraRestricted` + `RequiresNonSecretAura` + `SecretArguments = "AllowedWhenTainted"` | `:397-414` | CONFIRMED — the reference's `RequiresNonSecretAura` comment (`:150-154`) is accurate |
| `C_UnitAuras.GetAuraDataBySpellName` / `GetUnitAuraBySpellID` are `RequiresNonSecretAura` | `:245-262`, `:447-465` | CONFIRMED |
| `RequiresNonSecretAura` predicate text: "…will return no values" (not an error) | `SecretPredicatesDocumentation.lua:26-31` | CONFIRMED |
| `RequiresUnitAuraAccess` failure mode is `Error` | `:69-73` | CONFIRMED |
| `SecretWhenUnitAuraRestricted`: secret "when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual spells may be flagged as never or always secret, which takes priority" | `:80-85` | CONFIRMED |
| `SecretWhenAurasRestricted` is on the **`UNIT_AURA` event**, not on the readers | `UnitAuraDocumentation.lua:641-658` (`Name = "UnitAura"`, `LiteralName = "UNIT_AURA"`, `SecretWhenAurasRestricted = true`) | CONFIRMED — the brief's `SecretWhenAurasRestricted` annotation belongs to the event |
| `UnitAura` global does not exist on a mainline-code client | only `Blizzard_Deprecated/Classic/Deprecated_1_15_8.lua:10` and `Classic/Deprecated_2_5_5.lua:10` define it (each behind `if not GetCVarBool("loadDeprecationFallbacks") then return end`), and `Blizzard_Deprecated.toc` gates both to `[AllowLoadGameType classic]`; none of `Mainline/Deprecated_12_0_*.lua` / `Shared/Deprecated_12_1_0.lua` define `UnitAura` | CONFIRMED → **no classic fallback needed on Forever** |
| `UnitAura`-equivalent normalisation used by the reference | `SuperSwingTimer_Constants.lua:395-...` (`ns.UnitAura` wrapper: `C_UnitAuras.GetAuraDataByIndex` primary, deprecated global fallback, secret-probed) | Informational — **not ported** |
| `PLAYER` filter token = own caster | `Blizzard_FrameXMLUtil/AuraUtil.lua:274` | CONFIRMED |

---

## 6. Proposed SwedgeTimer port — `aura_icons.lua`

Design rule for every decision below: **the module never learns anything about an aura.** It declares ids, owns frames it creates, and reads only its own configuration and the *bars'* plain geometry.

### 6.1 Module skeleton and public surface

```lua
-- aura_icons.lua  (Forever-only; inert everywhere else)
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)

st.aura_icons = st.aura_icons or {}
local A = st.aura_icons

A.BUFFS   = { WARRIOR = {...}, PALADIN = {...}, SHAMAN = {...}, DRUID = {...}, ROGUE = {...}, HUNTER = {...} }
A.DEBUFFS = { ... }            -- same six keys, 27019 excluded
A.SHARED  = { 2825, 32182, 35476, 35477, 28507 }
A.RACIAL  = { Orc = {20572}, Troll = {26297}, Draenei = {28880}, BloodElf = {28730},
              Human = {20600}, Dwarf = {20594}, Gnome = {20589}, Undead = {7744},
              Scourge = {7744}, NightElf = {58984} }

A.state = {                    -- one table, no file-scope locals for state
    buff_container = nil, debuff_container = nil,
    driver = nil, shown = {}, attempts = 0, error = nil,
    last = { bar = nil, bar_top = nil, size = nil, spacing = nil,
             buff_on = nil, debuff_on = nil },
}

function A.init(self)                -- idempotent; the ONLY entry point from main.lua
function A.on_update(elapsed)        -- throttled maintenance (0.15 s)
function A.apply_settings(self)      -- re-read db: size / spacing / grow / toggles
function A.anchor(force)             -- recompute the top bar and place the rows
function A.diagnostics()             -- plain table for a later /st diag lane
```

Exposed names are `st.aura_icons.*` only. No SuperSwingTimer name is referenced anywhere (`ns.*` must not appear in the file).

**Functions that must exist and be pinned by tests:** `init`, `on_update`, `apply_settings`, `anchor`, `build_buff_list(class, race)`, `build_debuff_list(class)`, `gate()` (returns bool + reason), `diagnostics`.

### 6.2 Forever-only gate — the exact expression

Three layers, cheapest first, **no side effects before the last**:

```lua
-- layer 1 (load time, pure reads): the client discriminator is SwedgeTimer's own
local function client_can_have_aura_rows()
    if st.family ~= "FOREVER" then return false end
    if type(rawget(_G, "C_AuraContainerUtil")) ~= "table" then return false end
    if type(rawget(_G, "AuraContainerSortMethod")) ~= "table" then return false end
    if type(rawget(_G, "AuraContainerSortDirection")) ~= "table" then return false end
    return true
end
A.available = client_can_have_aura_rows()          -- false on every other family
-- layer 2 (init time, no frame): class has a list?
-- layer 3 (init time, creates ONE frame): pcall CreateFrame with the template pair;
--          failure => retry later (never a permanent latch on creation failure)
```

* `st.family` is set by `compat.lua:119` (`FOREVER` for `WOW_PROJECT_CAMELOT`/18, for Interface `>= 16000`, and whenever `C_SwingTimer` exists — `compat.lua:56-117`). It is the **authoritative** discriminator in this repo; `st.is_mainline` must **not** be used (Forever is mainline-code — `bench/lessons.md`).
* **Do not** probe `C_Secrets` as a gate: aura secrecy is *not* a capability test, and the native path is correct in both secrecy states.
* On a non-Forever client `A.available` is false at load, `A.init` returns `false` before any `CreateFrame`/`RegisterEvent`/`_G` write, and the option group is hidden by the same family check (§6.6). The only cross-family delta is one table lookup + one call at login.

### 6.3 Init seam (main.lua `post_init`)

Bars exist by the time `ST:post_init()` runs: `ST:init_libs` (`main.lua:859`) calls `self:init_timers()` (`:883`, which ends in `self:bring_up_hand(hand)` — `main.lua:946-970`) and then `self:post_init()` (`:885`) in the same pass. Bars are **lazy** (HU-22: "frames exist only when the hand is enabled AND in use", `main.lua:968-970`), and `post_init` already hosts guarded seams (`main.lua:1054-1123`: class hook via `st.guard.run`, `init_weave_range`, `st.power_bar.init`). Add **one** call in the same style, immediately after the `show_bar` loop / power-bar init:

```lua
	-- Forever-only aura icon row (aura_icons.lua). Inert on every other family:
	-- the module returns false before creating a frame. Guarded so a throwing
	-- module costs only the row.
	self:init_aura_icons()
```

with a 20-line helper modelled on `ST:init_weave_range` (`main.lua:1029-1052`):

```lua
function ST:init_aura_icons()
	local A = st.aura_icons
	if type(A) ~= "table" or type(A.init) ~= "function" then
		return false                     -- absent module (harness sandbox): no-op
	end
	if A.state.driver ~= nil then return true end
	if A.inert == true then return false -- the module proved the client cannot do it
	local ok, err = pcall(A.init, self)
	if not ok then
		if not self.aura_icons_init_notice_shown then
			self.aura_icons_init_notice_shown = true
			self:Print("The aura icon row could not be created and was isolated: " .. tostring(err))
		end
		return false
	end
	return A.state.driver ~= nil
end
```

Why `post_init` and not a class hook: `hud.lua` is initialised from the class modules (`classes/paladin.lua:458-459` etc.), but class files are **out of the impl lane's write scope** (`brief_aura_row_impl_2026-11-08.md:50-53`). `post_init` is the only shared, already-guarded seam that runs after the bars exist. The module keeps its own driver frame for the throttled pass, so nothing else needs a hook.

### 6.4 Containers — the exact configuration

Two containers, one group each (faithful to `:1527` / `:1582`; a single container with two groups would put both rows in one flow layout and lose the fixed stacking).

```lua
local STRATA_FALLBACK  = "MEDIUM"   -- config.lua:52 ships profile.frame_strata = "MEDIUM"
local LEVEL_OFFSET     = 1          -- config.lua:53 ships draw_level = 10 -> bar level 11
local MAX_FRAMES       = 16         -- reference :962-965
local BUFF_MAX_DURATION = 180       -- reference :684 (hides permanent/passive auras)
local ICON_TEXCOORD    = { 0.07, 0.93, 0.07, 0.93 }  -- reference :821
```

**Buff row** (`HELPFUL`, unit `player`):

```lua
local list = A.build_buff_list(class, race)        -- class ∪ SHARED ∪ RACIAL[race]
container = create_container("ST_AuraIcons_Buffs")
container:SetUnit("player")
container:AddAuraGroup("buffs", "HELPFUL", {
    candidateFilters = { includeSpellIDs = to_set(list), maxDuration = BUFF_MAX_DURATION },
    maxFrameCount    = math.min(#list, MAX_FRAMES),
    layout           = { elementWidth = size, elementHeight = size, elementSpacing = spacing },
    sortMethod       = AuraContainerSortMethod.Expiration,
    sortDirection    = AuraContainerSortDirection.Normal,
    initializeFrame  = style_button,
})
container:SetFlowLayoutAnchorPoint("BOTTOMLEFT")   -- after AddAuraGroup
container:SetEnabled(true)
container:Show()
```

**Debuff row** (`HARMFUL|PLAYER`, unit `target`):

same shape with `A.DEBUFFS[class]`, **no** `maxDuration`, `withBar = true` in the button style (3 px duration bar under the icon), `withCooldown = false`. Filter string is quoted in the module header with the own-caster rationale + the "empty on friendly targets" consequence (§3.6).

**Style callback** (runs inside the provider's `securecallfunction`, receives the button's object table — `Blizzard_AuraContainerFrameProviders.lua:83-86`). Every step in its own `pcall`, and the whole callback must not assume the object table supports a call:

```lua
local function style_button(frame)
    pcall(function() frame:SetSize(size, size) end)          -- group layout sizes it anyway
    pcall(function()                                          -- icon (client writes the texture)
        local icon = frame:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints(); icon:SetTexCoord(...)
        frame:SetIcon(icon)
    end)
    pcall(function()                                          -- 4 x 1px dark border
        ... CreateTexture(nil, "OVERLAY", nil, -1) + SetColorTexture(0,0,0,0.65)
    end)
    pcall(function()                                          -- countdown text (client-owned)
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("BOTTOM", frame, "TOP", 0, 2)
        st.utils.apply_font(fs, font, text_size, outline)     -- utils.lua loads before hud.lua
        frame:SetDurationText(fs)
    end)
    pcall(function()                                          -- stacks
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        frame:SetApplicationCount(fs)
    end)
    if with_bar then pcall(function()                         -- 3 px duration bar (debuffs)
        local bar = CreateFrame("StatusBar", nil, frame)
        bar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
        bar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
        bar:SetHeight(3)
        bar:SetStatusBarTexture(texture); bar:SetMinMaxValues(0, 1); bar:SetValue(0)
        frame:SetDurationBar(bar, { direction = Enum.StatusBarTimerDirection.RemainingTime })
    end) end
end
```

Notes for the impl lane:
* `SetDurationText(fs)` **without** options deliberately drops the reference's red-under-4 s curve. That curve is a *nice-to-have* built from `C_CurveUtil.CreateColorCurve` + `Enum.DurationTextBindingProperty.RemainingDuration` (reference `:763-799`); it is not needed for the row to work and it is one more optional-global surface. Add it later behind a probe if the operator asks.
* Do **not** create a `Cooldown` frame on the buff row (`withCooldown`) in v1: the row is a proc/uptime display above the bar; the bars already own urgency. If desired later, the reference's exact recipe is `:898-915`.
* `maxDuration` on the buff row is doing real work: it hides permanent/passive ids that the lists legitimately carry (e.g. 12319 Flurry talent record, 408498 Maelstrom talent record, 16958/1223246/417051 druid passives) — "any non-nil value implicitly hides permanent auras" (`Blizzard_CustomAuraContainer.lua:104-110`). Keep 180.

### 6.5 Anchoring above the top bars (the core new code)

**Which bar is "top"?** Compute from geometry, over the public helpers the brief names (`main.lua:132` `iter_hands`, `bars.lua:939-966`):

```lua
local function topmost_visible_bar()
    local best, best_top = nil, nil
    for hand in ST:iter_hands() do
        local frame = ST:get_bar_frame(hand)          -- bars.lua:963
        if frame and frame:IsShown() then
            local top = frame:GetTop()                 -- addon-created frame: plain geometry
            if type(top) == "number" and (best_top == nil or top > best_top) then
                best, best_top = frame, top
            end
        end
    end
    return best, best_top
end
```

* Bars are addon-created frames whose geometry the addon itself set with plain numbers (`bars.lua:88-129` creates `anchor_frame` → `hiding_anchor_frame` → `bar_frame`(BackdropTemplate) → `visuals_frame`; `bars.lua:592-700` sizes and `SetPoint`s them; moves come from `LWIN.RestorePosition(anchor_frame)`), so `GetTop()` on `bar_frame` is plain. **Verified:** no `SetScale` call exists in `bars.lua`/`main.lua`, so all bars share UIParent's scale and raw `GetTop()` values are directly comparable. If a future change introduces per-hand scale, normalise with `top * frame:GetEffectiveScale()` (ordering is preserved) — note this in a comment next to the comparator.
* **Lazy bars:** a hand's frames may not exist yet (HU-22 — `main.lua:968-970`: "frames exist only when the hand is enabled AND in use"; `ST:bring_up_hand` can build them long after `post_init`, e.g. on a weapon swap or a settings change). `ST:get_bar_frame(hand)` is nil-safe (`bars.lua:963-966`), so the iterator must treat `nil` as "not visible". This is the second reason the placement runs on a throttled poll instead of a one-shot at init: a bar that appears later is picked up on the next pass.
* "Visible" is `bar_frame:IsShown()`: `ST:show_bar`/`ST:hide_bar` (`main.lua:278`, `332`) call `bar_frame:Show()/Hide()`. Do **not** use alpha: bar alpha is used for the *fill* dim (`bars.lua:1155` `frame.bar:SetAlpha(0.35)`), not the frame.
* Hunter: the ranged bar is the top bar when shown; `hunter_ui.apply_melee_stack` anchors mainhand/offhand `TOPLEFT` to the ranged bar's `BOTTOMLEFT` (`hunter_ui.lua:376-429`, `parent = ranged_anchor.bar_frame`, mainhand first then offhand below it) — the geometry comparison handles that with no class special-case. That is a real improvement over the reference's fixed `mhBar or rangedBar` preference (`:1038-1050`), which would put the row in the wrong place for a stacked/relocated SwedgeTimer layout.

**Where the rows go** (the secret-height rule):

```
        ┌──────────── buff row (HELPFUL, player) ────────────┐   bottom = band_top + BUFF_GAP
        └────────────────────────────────────────────────────┘
        ┌──────────── debuff row (HARMFUL|PLAYER) ───────────┐   bottom = bar_top + DEBUFF_GAP
        └────────────────────────────────────────────────────┘
        ═══════════════ topmost visible swing bar ═══════════════
```

```lua
local top = topmost_visible_bar()
if not top then hide_rows(); return end
local bar_top = top:GetTop()
local debuff_on = buff_on_or_debuff_on and db.aura_icons_show_debuffs ~= false
local debuff_band = debuff_on and (size + BAR_CLEARANCE) or 0   -- RESERVED, plain numbers only
debuff_row:SetPoint("BOTTOM", top, "TOP", 0, DEBUFF_GAP)
buff_row:SetPoint("BOTTOM", top, "TOP", 0, DEBUFF_GAP + debuff_band + BUFF_GAP)
```

* **Why not anchor the buff row to the debuff container's top** (the reference's `:1434-1441`): the client sets the container's size through `secretwrap` (`Blizzard_CustomAuraContainer.lua:800`), so `GetHeight`/`GetTop` can be secret — which the reference itself documents and handles with a *classifier* rather than a measurement (`:1380-1398`). A port that anchors to the measured debuff container would either raise on a secret comparison or produce a wrong offset. Reserving a **fixed band** from the configured icon size makes the whole layout plain: no aura-container read at all.
* Cosmetic consequence to document: with no debuffs the buff row sits one icon-height higher than it strictly needs to. That is the price of never reading secret geometry; state it in the module header.
* `SetPoint`/`ClearAllPoints` calls stay inside `pcall` and are retried on the next pass (the reference does the same — `:1428-1441`), because whether a tainted `SetPoint` on a container with secret anchoring is always allowed is UNCONFIRMED (§8); a failure must never throw.
* **Never** call `GetSize/GetWidth/GetHeight/GetTop/GetPoint/GetRect/IsShown` on `buff_row`/`debuff_row` or on their children. Track visibility ourselves (`A.state.shown.buffs`) — the reference learned this for the stance slot (`:1287-1301`).

**Re-anchor triggers** (all folded into one throttled comparison, mirroring `:1716-1731`):

| Trigger | How it is detected |
|---|---|
| top bar changed (a lower bar became visible/hidden, form/spec change, hunter stack reflow) | `bar ~= last.bar` |
| bar moved or resized (drag, `/st` position, scale/width change, UI scale) | `bar_top ~= last.bar_top` |
| row size / spacing changed (options) | `size`, `spacing` vs `last.*` |
| toggles changed | `buff_on`, `debuff_on` vs `last.*` |
| world entry / resolution change / frame position reset | force a pass on `PLAYER_ENTERING_WORLD` (the module's own event frame) and once from `apply_settings` |
| bar hidden entirely | `topmost_visible_bar()` returns nil ⇒ hide both rows |

The pass runs on the module's own driver `OnUpdate`, accumulating `elapsed` and acting at `>= MAINTAIN = 0.15` (`0`/`nil` forces a pass, exactly like `:1649-1663`) so the very first placement is immediate. Polling (not event hooks) is required because bar drags/resizes have no event, and it is the same trade the reference made. Cost per pass: six `iter_hands` iterations (≤ 3 hands) + a handful of comparisons; no aura API is touched.

### 6.6 Options and defaults

`config_presets.lua`, in `ST.class_defaults` next to the HUD block (`config_presets.lua:46-70`), with the family note spelled out:

```lua
    -- Aura icon row (aura_icons.lua): WoW Forever only. The module is inert on every
    -- other family (st.family ~= "FOREVER" returns before a frame exists), so these
    -- values are unreachable there and no classic default changes. Nil-safe: the module
    -- hides on == false and treats nil as the shipped default (on).
    aura_icons_enabled       = true,   -- Forever default ON (operator order 2026-11-08)
    aura_icons_show_debuffs  = true,   -- own-caster target debuffs row
    aura_icons_size          = 22,     -- square icon edge, px (reference debuff 22 / buff 25)
    aura_icons_spacing       = 3,      -- px between icons (reference elementSpacing = 3)
    aura_icons_grow          = "right",-- "right" | "left" (row origin inside the container)
```

`option_tables.lua`, in the shared HUD/design section after the HUD block (the HUD header sits at `order = 2.0`, `option_tables.lua:598-601`), a new group at `order = 2.9`:

| widget | type | get/set | hidden rule |
|---|---|---|---|
| `aura_icons_header` | header, "Aura icons (WoW Forever)" | — | `st.family ~= "FOREVER"` |
| `aura_icons_enabled` | toggle | `db.aura_icons_enabled ~= false` / write + `st.aura_icons.apply_settings(ST)` | same |
| `aura_icons_show_debuffs` | toggle | `db.aura_icons_show_debuffs ~= false` | same |
| `aura_icons_size` | range 12-48, step 1 | `db.aura_icons_size or 22` | same |
| `aura_icons_spacing` | range 0-12, step 1 | `db.aura_icons_spacing or 3` | same |
| `aura_icons_grow` | select `right`/`left` | `db.aura_icons_grow or "right"` | same |

* Hidden on non-Forever with the existing pattern (`option_tables.lua:465-468` uses `hidden = function() ... end`; `:120-121` already branches on `st.family ~= "FOREVER"`). The control must not even print on classic clients — a hidden group is the requirement, not a disabled one.
* `st.aura_icons.apply_settings(ST)` must be a no-op when `available` is false (nil-safe on every family).
* **`option_table_presets.lua` does not need an entry** unless the HUD templates (`ST.<CLASS>.HUD_TEMPLATES`) should carry aura-row keys; recommend not touching it in v1 (keeps the template diff out of this lane).
* No change to any existing default for any client.

### 6.7 TOC and load order

* `SwedgeTimer.toc`: insert `aura_icons.lua` immediately **after** `hud.lua` (current tail order: `… power_bar.lua`, `ldb.lua`, `nextaction_ui.lua`, `practice_ui.lua`, `hud.lua`, `diag.lua`, `rotationtext.lua`, `designmode.lua`, `config_presets.lua`, `option_table_presets.lua`, `option_tables.lua`, `config.lua`, `classes\…`). Rationale: `utils.lua` (font chain) and `guard.lua` load far earlier; `hud.lua` is the closest sibling module and the last UI module before `diag.lua`; `classes/*` load after `main.lua`, so nothing here may depend on class modules.
* `tests/toc_check.lua` consequences: (a) the disk-completeness check requires the new file to be listed (`:284-291`); (b) if the module calls `st.utils.apply_font` (`utils.lua:109`, signature `(text, path, size, outline)`) or `st.utils.fetch_font_path` (`utils.lua:90`), add `"aura_icons.lua"` to `FONT_CONSUMERS` (`:130-133`) — otherwise no edit is needed; (c) if the module calls `st.guard.run`, add it to `GUARD_CONSUMERS` (`:123-125`); (d) consider adding `"aura_icons.lua"` to `REQUIRED_MODULES` (`:400-402`) so a "delete file + line" regression cannot slip through; (e) the file-scope-local ceiling is 190 (`:1006`), so keep state on `st.aura_icons`.
* `tests/run.sh`: register the suite next to the other Forever suites (`tests/run.sh:75-76` are `forever_hud_gate_state` / `forever_guide_gate_state`). Keep the harness line format exactly (`run "lua5.1 tests/aura_icons_state.lua" lua5.1 tests/aura_icons_state.lua`).

### 6.8 Tests — `tests/aura_icons_state.lua`

Harness = the established offline pattern (`loadfile` + `setfenv(chunk, env)` + `chunk("SwedgeTimer", st)`; see `tests/hud_state.lua:466-467`, `tests/forever_hud_gate_state.lua:1-120`), with counters on `CreateFrame`, `RegisterEvent`, `_G` writes and the aura namespaces.

| # | Case | Asserts |
|---|---|---|
| 1 | Forever happy path | exactly 2 containers created, each with one `AddAuraGroup` call, group keys `buffs`/`debuffs`, filter strings `"HELPFUL"`/`"HARMFUL|PLAYER"`, unit tokens `player`/`target` |
| 2 | idempotent init | second `init` creates 0 new frames; `attempts` unchanged |
| 3 | per-class `includeSpellIDs` (6 cases) | the exact set incl. shared+racial for the buff group; exact set for the debuff group; **no cross-class leak** (`assert` no foreign id); `27019` absent everywhere; stance ids absent from both |
| 4 | racial merge | `UnitRace` stub returns a file token and a localized name in turn; `Scourge`/`Undead` both resolve 7744; an unknown race adds nothing; the *class* array is unmodified after the merge (purity) |
| 5 | non-Forever inert (ERA/TBC/WRATH/CATA/MISTS/RETAIL) | `available == false`; zero `CreateFrame`, zero `RegisterEvent`, zero `_G` writes; `init` returns false; zero calls into `C_AuraContainerUtil`/`C_UnitAuras`/`C_Secrets` |
| 6 | missing pieces | `C_AuraContainerUtil` absent, then each sort enum absent ⇒ `available == false`, no throw |
| 7 | template probe failure | `CreateFrame` returns nil ⇒ `init` false, `error` recorded, **no latch**: a later `init` (after the stub starts succeeding) creates the rows |
| 8 | secret gate / no aura reads | `C_Secrets.ShouldAurasBeSecret()` true and false ⇒ identical container calls, and **zero** `C_UnitAuras`/`UnitAura`/`GetAuraData*` calls in both; identical behaviour |
| 9 | own-caster filter | filter string is `HARMFUL|PLAYER` (regression pin: dropping `|PLAYER` shows another player's debuff — mutation M2) |
| 10 | anchoring: topmost visible bar | three hands, geometry stub: visible ranged above melee ⇒ ranged chosen; ranged hidden ⇒ melee chosen; all hidden ⇒ rows hidden and no `SetPoint` call; `get_bar_frame` returning nil for an unbuilt (lazy) hand ⇒ that hand is skipped, not an error |
| 11 | anchoring: re-anchor triggers | move one bar 100 px up ⇒ one `SetPoint` on the next pass; unchanged geometry ⇒ **no** `SetPoint` (idempotent pass); size/spacing change ⇒ re-anchor; `PLAYER_ENTERING_WORLD` ⇒ forced pass |
| 12 | anchoring: no secret geometry | stub `GetHeight`/`GetTop` on the **containers** to raise/return a secret; the pass must not call them (call counter = 0) and must not throw |
| 13 | throttle | `on_update(0.05)` ×2 does nothing; the third (0.15 total) runs one pass; `on_update(0)` runs immediately |
| 14 | combat deferral | `InCombatLockdown() == true` ⇒ no frame; `false` ⇒ created; a throw in `AddAuraGroup` ⇒ `init` isolated, classic bars untouched (assert no `ST.show_bar`/`hide_bar` calls) |
| 15 | options | `aura_icons_enabled == false` ⇒ both containers `Hide()`d, frames still exist; `nil` ⇒ shown; `show_debuffs == false` ⇒ debuff container hidden and the reserved band collapses; each setter calls `apply_settings` |
| 16 | class with no list | stub `BUFFS.MAGE = nil, DEBUFFS.MAGE = nil` ⇒ `init` false, zero frames (fail closed, never another class's auras) |
| 17 | TOC/registry | `toc_check.lua` stays green (module listed once; load order after `hud.lua`) |

**Mutation proofs** (≥ 5, each on an isolated copy of the tree in `/tmp` — `rsync -a --exclude=Media --exclude=docs --exclude=.git`, per `bench/lessons.md`), each with the exact failing check count and exit code recorded:

| M | Mutation | Must fail |
|---|---|---|
| M1 | delete `st.family ~= "FOREVER"` from the gate | case 5 (non-Forever inert) |
| M2 | change the debuff filter to `"HARMFUL"` | case 9 |
| M3 | invert the `top > best_top` comparator | case 10 |
| M4 | replace the fixed debuff band with `debuff_row:GetHeight()` | case 12 (and case 10 on a secret stub) |
| M5 | drop the shared/racial merge from the buff set | case 3/4 |
| M6 | latch `A.inert = true` on a creation failure | case 7 |
| M7 | remove `27019` from the exclusion (i.e. re-add it) | case 3 |
| M8 | make `on_update` un-throttled | case 13 |

### 6.9 Risks, and the do-not-copy list

| Risk | Why | Mitigation |
|---|---|---|
| Reading container geometry | client sizes containers via `secretwrap` (`Blizzard_CustomAuraContainer.lua:800`) | fixed band, no container reads (§6.5); test 12 |
| Reading button/row shown/alpha | `SecretAspect.Shown` (`Blizzard_CustomAuraButton.lua:159-170`) | keep our own booleans; never read back |
| Many button frames despite no auras | `FrameCreationBatchSize = 10` (`Blizzard_AuraContainerShared.lua:105`) | accept (client design); count them in `diagnostics()` |
| Deep-copy of our includeSpellIDs table | `securecopy` + `MergeTable` (`Blizzard_CustomAuraContainer.lua:236-240`) | merge at creation, never mutate after; a settings change rebuilds the set on the next creation |
| `SetPoint` on a container during combat | taint rules; runtime UNCONFIRMED | pcall + retry next pass; never change strata/parent after creation |
| Row wider than the bar with 16 icons | `maximumLineSize = math.huge`, one line | cosmetic; v2 could wrap by bar width (needs `SetFlowLayoutMaximumLineSize`) |
| Operator confusion: debuff row empty on friendly targets | client identity-filter rule (`Blizzard_AuraContainerUtil.lua:89-107`) | document in the module header and the option `desc` |
| Per-hand scale in a future refactor | raw `GetTop()` comparison assumes one scale | comment the comparator; normalise with `GetEffectiveScale()` if scale is ever added |
| Copy-paste of SuperSwingTimer names | `ns.*` / `ns.foreverAura` / `ns.mhBar` / `showWarriorBuffIcons` do not exist in SwedgeTimer | the module header must say "no `ns.*` reference"; a grep assertion in the test (`file must not contain "ns%."`) is cheap insurance |
| A lazy bar appears after `post_init` | HU-22 bars are built on demand (`main.lua:968-970`), so the first pass can run with zero bars | the pass hides the rows and re-tries; a later pass picks the new bar up (test case 10, risk accepted) |

**Do not copy** (each is a SuperSwingTimer-only assumption):
`ns.isForever`/`ns.hasAuraContainer` (use `st.family` + globals), `ns.playerClass`, `ns.mhBar`/`ns.rangedBar`/`ns.hunterRangeHelperBar`/`ns.rogueEnergyTickBar`/`ns.druidEnergyTickBar`/`ns.shamanLightningContainer`, `ns.DEBUFF_BAR_HEIGHT`, `ns.activeBuffIconCount`, `ns.hunterAspectIcon`, `ns.foreverAura`, `ns.foreverNativeAuraIcons`, `ns.WrapLegacyIconUpdaters` (we have no classic icon row to stand down), `BUFF_TOGGLE_BY_CLASS`/`BUFF_SIZE_BY_CLASS`/`DEBUFF_BARS_BY_CLASS`, `GetDB()`/`ns.DB_DEFAULTS` (use `ST:get_class_table()`), `ns.GetDefaultFont`/`ns.GetBarTexture` (use `st.utils.fetch_font_path` / LibSharedMedia), `ns.Scale`, the stance container/slot and `EnsureShapeshiftIcon`, `CountVisibleDebuffBars`/`ComputeIconYOffset`, the Hunter distance bar and Maelstrom readers (unrelated features in the same file), and the `FOREVER_STANCE_SPELLS` tier itself.

---

## 7. UNCONFIRMED register and in-client checklist

Nothing in this table can be settled offline; each row says what to run and what should be seen. Every row must be closed in a Forever session before the row is called shipped.

| # | Item | Why unproven | In-client probe | Expected |
|---|---|---|---|---|
| U1 | Tainted creation of `CustomAuraContainerTemplate` succeeds | the `allowUntaintedCreation="true"` declaration suggests it, but the XSD has no semantics (`UI.xsd:1269`) and the only other in-tree user is secure code (`SecureGroupHeaders.lua:112`) | `/run local f=CreateFrame("AuraContainer",nil,UIParent,"CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate"); print(tostring(f))` | a frame userdata, not `nil` |
| U2 | `AddAuraGroup` with `includeSpellIDs` shows an icon for a live buff | runtime matching | buff up, then `/run local A=SwedgeTimer and st and st.aura_icons; print(A and A.diagnostics and A.state.buff_container)` — assert the container exists and inspect the row visually | icon appears within one 0.15 s pass |
| U3 | Secret-safe in combat/instance | `SecretWhenUnitAuraRestricted` says auras go secret under restrictions; the native path *should* be unaffected but only the client can prove it | enter a dungeon/raid, pull, buff up, look at the row; `/run print(C_Secrets.ShouldAurasBeSecret())` | icons keep updating (icon/duration/stacks), no Lua error |
| U4 | Own-caster debuff filter in a group | two players applying the same debuff | with a second player of the same class applying the same debuff on the same mob, the row shows **one** icon (yours) | one icon |
| U5 | Debuff row on a friendly target is empty | documented rule, runtime effect unverified | target a friendly player, apply nothing, look | empty row (no error) |
| U6 | Container geometry is secret (the band design is required) | the `secretwrap` source is conclusive that the *client* may secret it; whether `GetHeight` then returns a secret is runtime | in combat with auras up: `/run local c=st.aura_icons.state.debuff_container; print(pcall(c.GetHeight, c))` | either a plain number while unrestricted, or a secret/blocked read while restricted — **never** a crash in our module (we never call it) |
| U7 | Topmost-bar choice matches the visual stack per class | geometry logic is offline-provable, the on-screen stack is not | one check per class: WARRIOR/ROGUE/HUNTER (3 hands), SHAMAN (2), DRUID/PALADIN (1); move the bars, change form/spec | the row sits above the highest *visible* bar and follows drags within one pass |
| U8 | `SetPoint` on a container is allowed in combat (no blocked-action error) | taint rules + `UntrustedLayoutScriptExecution` aspect | drag a bar in combat with the row visible | row follows; at worst it re-anchors when combat ends (no error spam) |
| U9 | Icon content for each class list | ids are the reference's; a wrong id simply never matches | per class: apply each spell in the list and see the icon | every intended proc/CD appears once |
| U10 | `27019` and the stance ids really are absent on Forever | reference assertion + absence from the 1.15.9 dump only | `/run print(C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(27019))` and `/run print(GetSpellInfo(27019))` | `nil` on Forever (no icon ever appears for it either way) |
| U11 | `C_AuraContainerUtil` and the sort-enum globals exist at runtime on Forever | doc namespace + reference gate only | `/run print(type(C_AuraContainerUtil), type(AuraContainerSortMethod), type(AuraContainerSortDirection))` | `table table table` |
| U12 | 1.15.9 client data is not a gate for Forever ids | proven by the shared-buff counter-example (§4.1) | `/run print(GetSpellInfo(2825))` | non-nil on Forever if Bloodlust exists there |
| U13 | Aura row does not fight the HUD/guide for space | placement is relative to the bars only | visually inspect a full HUD (HUD above bars, aura row between) | no overlap; if they collide, raise the HUD default (out of this lane) |

---

## 8. Appendix — where this report could be wrong

* **The reference's Forever behaviour is asserted, not measured.** This lane did not run a Forever client. Every "Forever: …" duration/behaviour above is the reference's claim, in-client-confirmed by *its* author, not by this lane. Treat the *id lists* as provenance-marked data and the *durations* as claims.
* **1.15.9 `Spell.csv` presence is corroboration only.** It is the SoD/Era client; the Forever client is 1.60.1 and carries custom spells (the shared-buff counter-example proves both directions are unreliable).
* **`WIRING.md` was treated as untrusted.** Four of its aura claims are contradicted by the code (§3.9); a future reader should cite `SuperSwingTimer_Forever.lua`, never the wiring doc.
* **The `PLAYER` filter token's exact semantics for pets/vehicles** are quoted from `AuraUtil.lua:274`; whether a *pet's* debuff should also appear on the row is a product decision the operator has not stated. The reference accepts it (the comment includes "or by the player's pet or vehicle"). If the operator wants strictly the player's own application, that requires a different filter (`HARMFUL` + `isFromPlayerOrPlayerPet = true` has the same pet caveat) or CLEU correlation — which cannot be done secret-safely. Recommend: keep `HARMFUL|PLAYER` and note the pet inclusion in the option `desc`.

---

**Hand-off:** the impl lane (T3) can build `aura_icons.lua` from §6 without opening the reference addon. The two things it must not "improve" without a client check are the `PLAYER` filter (§3.6) and the fixed-band anchor (§6.5, U6).
