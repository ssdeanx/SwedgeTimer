# Range-API matrix — classic_era observations, web context, LRC API-call audit (2026-10-21)

Desk: `range-api-matrix` (read-only research lane)
Brief: `bench/briefs/brief_range-api-matrix_2026-10-21.md`
Cross-branch authority: `bench/range_api_orchestrator_matrix_2026-10-21.md` (orchestrator, shell-verified).
Nothing in that file is re-derived here; it is used as given.

## 0. Scope and reading rules

- This lane has NO shell. It can read the CHECKED-OUT `classic_era` branch of
  `/home/sam/wow-ui-source` (ast-grep) and it can make HTTPS fetches. Every
  branch-specific statement below carries its branch; nothing is generalised from
  classic_era to live/forever.
- WEB = CONTEXT ONLY. A wiki/forum "protected" claim is NOT proof for the 1.15.x
  classic backport. The only proof of a block is the operator's own in-client
  `ADDON_ACTION_BLOCKED` report (2026-10-21, Era 1.15.9) for the item-range API.
- The modern spell-range path (R3) is DEFERRED by operator order; the shipped fix
  uses no client range API beyond the interact bands. Nothing in this report
  proposes wiring it. "C_Spell.IsSpellInRange looks safe" is filed as an OPEN
  FOLLOW-UP (FU-1) needing one in-client confirmation, NOT as a finding.
- ast-grep limitation carried through: it cannot see string literals inside table
  constructors, so a name held in a string table is NOT-VISIBLE to it. A sweep miss
  is never reported as an absence; Sourcegraph full-repo plain-text search was
  used to close that hole for classic_era.
- LRC = the vendored `Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua`
  in this repo. All LRC line numbers below are the CURRENT on-disk revision.

## 1. Q1 — `C_SpellBook.IsSpellBookItemInRange` on classic_era

### 1.1 Presence in the classic_era client SOURCE: ABSENT — CONFIRMED

- ast-grep, local checkout, whole `Interface` tree, lang lua:
  - pattern `C_SpellBook.IsSpellBookItemInRange` -> no matches.
  - pattern `C_SpellBook.IsSpellBookItemInRange($$$)` -> no matches.
  - pattern `C_SpellBook[$S]` (string-indexed access) -> no matches.
  - pattern `"IsSpellBookItemInRange"` (string literal) -> no matches, BUT this
    sweep is NOT-VISIBLE by tool limitation and contributes nothing.
- Sourcegraph full-repo plain-text search, upstream branch `classic_era`
  (HEAD sha `8165d4cd6e48d606369336cc3a7977902310e81e`), query
  `repo:^github\.com/Gethe/wow-ui-source$ rev:classic_era IsSpellBookItemInRange`
  -> `matchCount=0`, 0 content matches. This sweep DOES see string literals, so it
  closes the ast-grep hole for this name on classic_era.
- classic_era's own generated API doc, upstream `classic_era`
  `Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua`:
  87 `Name =` entries; the C_SpellBook functions present are FindBaseSpellByID,
  FindFlyoutSlotBySpellID, FindSpellOverrideByID, HasPetSpells, IsSpellInSpellBook,
  IsSpellKnown, IsSpellKnownOrInSpellBook (+ events). No IsSpellBookItemInRange.
- classic_era has NO `11_0_0_SpellBookAPITransitionGuide.lua` (that file exists on
  live/forever only, upstream). That guide (upstream live/forever, lines 46-47) is
  where the index form's modern replacement is introduced:
  `IsSpellInRange(spellID/name) C_Spell.IsSpellInRange(spellIdentifier)` /
  `IsSpellInRange(index, bookType) C_SpellBook.IsSpellBookItemInRange(index, spellBank)`.
  -> the index-form replacement belongs to the 11.0 spellbook revamp.

### 1.2 NOT PROVEN: presence in the classic_era client BINARY — UNCONFIRMED

FrameXML is not the API surface. Proof that classic_era's generated doc file is
INCOMPLETE: classic_era ships `C_SpellBook.GetSpellBookItemInfo` — called at
`Interface/AddOns/Blizzard_SpellSearch/Blizzard_SpellSearchUtil.lua:64`
(`C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)`; local ast-grep) — while
that same name is absent from classic_era's `SpellBookDocumentation.lua`.
Therefore "absent from the classic_era doc file" is weak evidence; the strong
evidence is the 0-hit full-tree search (1.1) plus the transition-guide provenance.
Closing evidence for the binary: the type dump in FU-1 (§5).

### 1.3 Argument shape / return contract of the index form (live/forever only) — CONFIRMED for those branches

Upstream `live` `.../Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua:596-611`
(identical entry at upstream `forever` `:616-631`):
- Arguments: `spellBookItemSlotIndex` (luaIndex, Nilable=false),
  `spellBookItemSpellBank` (SpellBookSpellBank, Nilable=false),
  `targetUnit` (UnitToken, Nilable=true, optional).
- Returns: `inRange` bool, Nilable=true — "May be nil if the range check was
  invalid, ie due to unknown/invalid spell, missing/invalid target, etc".
- `SecretArguments = "AllowedWhenUntainted"`.

## 2. Q2 — how Blizzard's own code calls `C_Spell.IsSpellInRange` (classic_era), and client-side protected markers

### 2.1 The classic_era callsite — CONFIRMED (1 callsite)

`Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua` (upstream classic_era
and the local checkout agree, same line numbers):

- :708  `local baseSpellID = self:GetBaseSpellID();`
- :709  `self.needsRangeCheck = baseSpellID and C_Spell.SpellHasRange(baseSpellID);`
- :711  `self.rangeCheckSpellID = baseSpellID;`
- :712  `C_Spell.EnableSpellRangeCheck(self.rangeCheckSpellID, true);`
- :713  `self.spellOutOfRange = C_Spell.IsSpellInRange(self.rangeCheckSpellID) == false;`

- ARGUMENT SHAPE: exactly ONE argument — the spell ID (`self.rangeCheckSpellID`).
  No `targetUnit` is passed. (Blizzard's doc for the function allows an optional
  second `targetUnit`; Blizzard's own code omits it, so the call answers "is the
  player's current target in range".)
- RETURN CONTRACT AS USED: the result is compared `== false`, so `nil` (invalid
  range check) is treated as "NOT out of range" — i.e. Blizzard treats nil as unknown, never as out-of-range.
- The function's documented contract (upstream classic_era
  `.../Blizzard_APIDocumentationGenerated/SpellDocumentation.lua:601-614`):
  Arguments `spellIdentifier` (SpellIdentifier, Nilable=false), `targetUnit`
  (UnitToken, Nilable=true, optional); Returns `inRange` bool, Nilable=true —
  "May be nil if the range check was invalid, ie due to unknown/invalid spell,
  missing/invalid target, etc"; Documentation: "Returns true if the current target
  is within range of the spell; False if out of range; Nil if range check was invalid".
- Count: exactly ONE callsite in the classic_era tree (local ast-grep: 1 match;
  Sourcegraph classic_era "IsSpellInRange": 2 hits total = this callsite + the doc entry).
  classic_era has NO `HostileTargetingActionBar.lua` range call and no second caller.

### 2.2 Client-side marker that an API is protected — classic_era CANNOT name one — CONFIRMED

- The classic_era client DOES have the protected-function mechanism:
  upstream classic_era `.../Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua`
  - :11-26 `C_RestrictedActions.CheckAllowProtectedFunctions(object, silent)` —
    "Returns true if the calling context has permissions to call protected functions
    on the supplied object"; `silent`: "If true, don't signal blocked action errors if
    protected function calls are disallowed".
  - :72-81 event `ADDON_ACTION_BLOCKED`, SynchronousEvent, payload
    `{ isTainted: cstring, function: cstring }`.
  - `RestrictedActionsConstantsDocumentation.lua` lists only `AddOnRestrictionState` (Inactive/Activating/Active) and `AddOnRestrictionType`
    (Combat, Encounter, ChallengeMode, PvPMatch, Map, Chat) — NO range/spell type.
- The classic_era client source contains NO list, comment or doc that names any API
  as protected/blocked/restricted:
  - Sourcegraph classic_era `"protected function"` -> `matchCount=0`.
  - Sourcegraph classic_era `"Protected = true"` -> `matchCount=0`.
  - classic_era `Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/*` uses
    "protected" only about FRAME protection (`IsProtected`, protected frame handles),
    not about APIs.
  - `Blizzard_RestrictedAddOnEnvironment/RestrictedEnvironment.lua` and
    `RestrictedExecution.lua`: 0 hits for "IsItemInRange"/"IsSpellInRange"/
    "ADDON_ACTION_BLOCKED"/"protected" (only one unrelated comment at
    RestrictedExecution.lua:418 "…taint the protected…").
- classic_era also dispatches the event to addons — Blizzard's own UI registers it:
  `Interface/AddOns/Blizzard_UIParent/Vanilla/UIParent.lua:92`
  `self:RegisterEvent("ADDON_ACTION_BLOCKED")` (plus :657 handler; TBC :93/:665,
  Wrath :92/:792, Cata :91/:828, Mists :96/:842).
- classic_era has NO `SecretArguments` field in its generated API docs (0 hits; the
  only classic-era use is Blizzard's own `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:457,512`
  helper) — the Midnight secret-value layer is not in the classic client; the
  classic-era mechanism is the older protected-function one.

=> The classic client source can prove the MECHANISM (protected functions, blocked
action events) but can never name the protected set. Only the operator's in-client
report proves a specific API is blocked on Era 1.15.9.

## 3. Q3 — web: which APIs are flagged protected (CONTEXT ONLY)

All pages below were fetched 2026-10-21. wiki.gg was in a published offline window
("All wiki.gg wikis are currently offline out of an abundance of caution… The patch
is expected to be released on October 21 at 14:00 UTC") and returned 502 on many
attempts; successful fetches are cited, failures are named in §6.

- W1 — https://warcraft.wiki.gg/wiki/API:IsItemInRange (legacy global).
  Patch changes shown on the page: "Hotfix (2023-11-16): Protected. May no longer be
  called in combat by insecure code. (Build: 10.2.0.52188)" and "Hotfix (2023-12-11):
  Partially unrestricted. Querying enemy units while in combat is once again permitted.
  (Build: 10.2.0.52485)". Page categories include "API functions/restricted".
  Game Types shown: standard + 2.0.1 - 10.2.6 / mists + 1.13.2 - 4.4.0 /
  tbc + 1.13.2 - 2.5.5 / vanilla + 1.13.2 - 1.15.2.
  CONTEXT ONLY: both hotfixes are RETAIL 10.2.0 builds; the page carries NO
  classic-build hotfix note, so it does NOT prove the 1.15.x classic protection.
  The proof for classic is the operator's Era 1.15.9 report, not this page.
- W2 — https://warcraft.wiki.gg/wiki/API:C_Item.IsItemInRange.
  Game Types: standard + 10.2.6 / forever + 1.60.1 / mists + 4.4.0 /
  tbc + 2.5.5 / vanilla + 1.15.2. Predicate "AllowedWhenUntainted". Signature
  `C_Item.IsItemInRange(itemInfo, targetToken)` -> `result boolean ?`. No protection/patch note on the page.
- W3 — https://warcraft.wiki.gg/wiki/API:C_Spell.IsSpellInRange.
  Game Types: standard + 11.0.0 / forever + 1.60.1 / mists + 4.4.1 /
  tbc + 2.5.5 / vanilla + 1.15.4. Predicate "AllowedWhenTainted". Signature
  `C_Spell.IsSpellInRange(spellIdentifier [, targetUnit])` -> `inRange boolean ?`.
  No protection/patch note on the page. CONTEXT ONLY — says nothing about the
  classic protection state.
- W4 — https://warcraft.wiki.gg/wiki/API:IsSpellInRange (legacy global).
  Signature `IsSpellInRange(spellName, unit)` / `IsSpellInRange(index, bookType, unit)`
  -> 1 / 0 / nil. Game Types: standard + 2.0.1 - 11.0.0 / mists + 1.13.2 /
  tbc + 1.13.2 / vanilla + 1.13.2 (no upper bound on the vanilla tag).
  CONTEXT ONLY, and it CONFLICTS with the orchestrator matrix row "legacy global IsSpellInRange exists NOWHERE": the matrix was established by
  grepping FrameXML source, and a global implemented in the client BINARY would not
  appear there. UNRESOLVED -> FU-2.
- W5 — https://warcraft.wiki.gg/wiki/ADDON_ACTION_BLOCKED.
  "Fires when a protected function is being called from tainted code, e.g. taint from
  an addon." Payload: `isTainted` (string), `function` (string). Game Types:
  standard + 2.3.0 / forever / mists + 1.13.2 / tbc / vanilla -> the event exists on
  the classic client line (consistent with the operator's Era report).
- W6 — the protected-API LIST page  https://warcraft.wiki.gg/wiki/Category:API_functions%2Frestricted
  could NOT be retrieved: HTTP 502 on every attempt (3 URL forms x up to 8 tries)
  while wiki.gg was offline. The complete list of protected APIs is therefore
  UNRETRIEVED; the only list membership shown anywhere in this report is the
  legacy `IsItemInRange` sitting in "API functions/restricted" (W1).

## 4. LRC API-call audit (the vendored copy in this repo)

### 4.1 Which client APIs the vendored LRC captures and calls

- :420 `local CheckInteractDistance = CheckInteractDistance`
- :421 `local IsSpellInRange = IsSpellInRange`            (LEGACY GLOBAL capture)
- :422 `local IsItemInRange = (C_Item and C_Item.IsItemInRange) or _G.IsItemInRange`
- Guard flags: :441 `local modernItemRange = (C_Item and C_Item.IsItemInRange) ~= nil`
  and :447 `local spellRangeAvailable = type(IsSpellInRange) == "function"`.

### 4.2 Reachability under those guards — CONFIRMED

- Item checkers are built only `if itemList and not modernItemRange` (:594-606) and
  the HarmItems[15] minRangeCheck only `if HarmItems[15] and not modernItemRange`
  (:801-814). Per the orchestrator matrix, `C_Item.IsItemInRange` resolves on all
  five branches, so `modernItemRange` is TRUE on all five and the item checker list
  is never built.
- Spell checkers are built only `if spellList and spellRangeAvailable` (:608-632).
  Per the orchestrator matrix the legacy global is absent on all five branches, so
  the spell checker list is never built either.
- Consequently the ONLY client range API the vendored LRC can still CALL is
  `CheckInteractDistance` (:464 minRangeCheck fallback, :523 `checkers_Interact`,
  :856/:858 interact-band minRangeCheck) — and the operator's client ran exactly that path (melee checker at main.lua:1791) WITHOUT a block (orchestrator matrix).
- Dead-but-present call sites (reachable only if a guard flips):
  `IsItemInRange` at :512 and :809; `IsSpellInRange` at :477, :495, :826, :842.

### 4.3 Call-shape audit — the part that is NOT by design

- ITEM path: the LRC calls `IsItemInRange(item, unit)` where `item` is an ITEM ID
  (the HarmItems tables). On the three classic branches the resolved function IS
  `C_Item.IsItemInRange`, whose documented signature is
  `(itemInfo: ItemInfo, targetToken: cstring) -> boolean ?`
  (upstream classic_era `.../Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:923-935`;
  wiki W2). So the call shape is invalid for the modern function AND the call is
  blocked on Era 1.15.9 (operator's in-client `ADDON_ACTION_BLOCKED`).
  => NOT BY DESIGN: calling the item-range API where the client blocks it, with a
  call shape that is invalid for the function that is actually there.
- SPELL path: the LRC's spell checkers use the LEGACY INDEX/BOOKTYPE shape
  `IsSpellInRange(spellIdx, BOOKTYPE_SPELL, unit)` (:477, :495, :826, :842). That is
  NOT the modern ID/name shape `C_Spell.IsSpellInRange(spellIdentifier, targetUnit)`
  — the LRC never calls the modern spell API. R3 stays deferred; this is a statement
  of call shape only, not a proposal to wire anything.
- BY DESIGN (upstream LRC): the legacy-global capture at :421 and the item tables
  themselves. The LRC's own comment (:470-473) already says "IsSpellInRange was
  removed on Mainline-code clients (C_Spell.IsSpellInRange replaces it)". These are
  upstream design and are not defects.
- The 2026-10-21 guard block in the vendored copy (:435-448) is what converts the
  two dead paths into "never built"; the operator's crash came from a build WITHOUT
  that block (see §6 G6 for the line-number drift).

### 4.4 Client range APIs called by the ADDON itself (outside the LRC) — fact, not a proposal

`compat.lua:915-941` builds `api.IsSpellInRange(spell, unit)`:
- :915 `local is_spell_in_range = rawget(_G, "IsSpellInRange")`
- :916 `local c_spell_is_spell_in_range = C_Spell and C_Spell.IsSpellInRange`
- :918-941 the wrapper: legacy global first (:919-925), else `C_Spell.IsSpellInRange`
  (:926-939, normalising true->1, false->0, nil/secret->nil), else nil (:940).

Per the orchestrator matrix the legacy global is absent on all five branches, so
this wrapper takes the `C_Spell.IsSpellInRange` branch on every supported client.
Runtime consumers: `classes/hunter.lua:2953`, `classes/rogue.lua:1508` and `:1543`,
plus the "out of range" helpers in `classes/hunter.lua:3197`,
`classes/shaman.lua:3879`, `classes/druid.lua:2669`, `classes/warrior.lua:4248`.
=> The addon's own code already calls the modern spell-range API at runtime on Era.
Whether that API is BLOCKED on Era 1.15.9 is UNCONFIRMED (the operator's report
does not clear it — those class paths may simply not have run). This is the reason
FU-1 exists; no change is proposed here.

Comment-truth note (low severity, for the fix lane to consider): `compat.lua:911-914`
says the classic global "is preferred" and that on "the Mainline-code clients, where
the global is removed, C_Spell.IsSpellInRange … is used", while the LRC comment
(:442-447) says the legacy global is absent on EVERY supported client. Per the
orchestrator matrix the LRC wording is the accurate one; the compat comment is stale.
No code change requested here.

## 5. OPEN FOLLOW-UPS — each needs ONE in-client confirmation

The operator declined the probe on 2026-10-21 ("i have to copy all files over. so use
a test, like we always do."). Both commands below are paste-in-chat only, no file
copying, so they can ride along in the next in-client session.

FU-1 — Is `C_Spell.IsSpellInRange` callable from addon code on Era 1.15.9?
(Needed before ANY claim that the modern spell path is safe; it does not authorise
wiring it — R3 stays deferred.)

 /run local f=CreateFrame("Frame"); f:RegisterEvent("ADDON_ACTION_BLOCKED"); f:SetScript("ADDON_ACTION_BLOCKED",function(_,_,fn) print("BLOCKED:",fn) end); print("types:",type(IsSpellInRange),type(C_Spell and C_Spell.IsSpellInRange),type(C_Item and C_Item.IsItemInRange),type(C_SpellBook and C_SpellBook.IsSpellBookItemInRange)); print("cspell call:",C_Spell.IsSpellInRange(2050))

Read: a "BLOCKED:" line => the modern spell API is blocked on Era too (and the
addon's own compat path in §4.4 is affected). No "BLOCKED:" line plus a
true/false/nil "cspell call:" value => callable, nil meaning "invalid range check".

FU-2 — Does the legacy global `IsSpellInRange` exist in the 1.15.9 BINARY?
(Decides whether the shipped LRC guards are inert or the legacy index/bookType call
is live on Era; also resolves the W4 vs orchestrator-matrix discrepancy.)

    /run print("legacy:",type(IsSpellInRange),"cspell:",type(C_Spell and C_Spell.IsSpellInRange),"citem:",type(C_Item and C_Item.IsItemInRange),"cbook:",type(C_SpellBook and C_SpellBook.IsSpellBookItemInRange))

Read: `legacy: function` on Era => `spellRangeAvailable` is TRUE there, the LRC's
spell checkers ARE built (§4.2), and the legacy index/bookType call (:477/:495/:826/:842)
runs — that call then needs its own block check (add the FU-1 listener).

FU-3 (optional) — the full protected-API list is not in the client source (§2.2) and
the wiki list page was offline (§3 W6). It can be pulled later from
https://warcraft.wiki.gg/wiki/Category:API_functions%2Frestricted or from the
client's own API Docs UI, if a complete list is ever needed.

## 6. GAPS — what could NOT be determined

- G1. Whether `C_SpellBook.IsSpellBookItemInRange` exists in the classic_era client
  BINARY. Source and generated docs prove only that Blizzard's classic client neither
  calls nor documents it, and that the classic generated doc file is demonstrably
  incomplete (§1.2). Closes with FU-1's type dump.
- G2. The complete set of protected APIs: the wiki category page was 502 across all
  attempts (§3 W6) and the client ships no list (§2.2).
- G3. The protected state of every API other than the item-range one on Era 1.15.9
  (no in-client probe has been run).
- G4. TOOLING: the SearxNG and Firecrawl MCP catalogs were NOT discoverable in this
  lane's Code Mode catalog — `search({query:"searxng"})`, `search({query:"firecrawl"})`
  and every other query returned `{"items":[],"remaining":0,"next":null}` — and the
  operator-hosted SearxNG at `http://localhost:8069` was unreachable from this
  sandbox ("Unable to connect"). DuckDuckGo (lite + html), Bing and Mojeek all
  served bot-challenge/captcha pages, so there was NO general web-search coverage.
  The web side was done exclusively by direct HTTPS fetches of known URLs
  (warcraft.wiki.gg, raw.githubusercontent.com/Gethe/wow-ui-source, api.github.com,
  sourcegraph.com). Any web claim that is not a direct page fetch is UNCONFIRMED.
- G5. The local checkout's exact commit is unknown (reading `/home/sam/wow-ui-source/.git` is blocked for this lane). Corroboration that local
  == upstream classic_era for everything cited: the two client-source lines checkable
  locally (`Deprecated_ItemScript.lua:29`, `CooldownViewer.lua:713`) are identical in
  position and text to upstream classic_era HEAD, and Sourcegraph's classic_era match
  counts ("IsItemInRange" = 2, "IsSpellInRange" = 2) equal the local ast-grep counts.
  The generated-API-doc line numbers (601/614, 923/935) come from upstream classic_era
  only and are NOT verifiable in the local checkout (ast-grep cannot see the string
  keys that carry them).
- G6. The operator's stack cited `LibRangeCheck-2.0.lua:498` as the item-range call.
  In the CURRENT on-disk vendored copy line 498 is `if r == 1 then` inside the SPELL
  checker (`checkers_SpellWithMin`); the item-range call is at :512. The operator's
  build therefore predates the 2026-10-21 guard block (:435-448) that the copy now
  carries — so that stack line number must not be chased in the current file.
  (The upstream (unmodified) lib's line numbering could not be checked: the upstream
  raw mirror tried returned 404.)
- G7. No in-client observation of my own was possible: this lane is read-only and
  has no client session. Everything about runtime behaviour is either the operator's
  report or UNCONFIRMED.

## 7. CONFIRMED / UNCONFIRMED index

CONFIRMED (classic_era, this lane's own observation unless marked otherwise):
- C_SpellBook.IsSpellBookItemInRange: absent from the classic_era client source
  (0 hits, whole tree, incl. string literals) and absent from classic_era's
  generated C_SpellBook doc; the index-form replacement arrives with the 11.0
  spellbook revamp (transition guide, live/forever only).
- classic_era has exactly ONE C_Spell.IsSpellInRange callsite:
  CooldownViewer.lua:713 — one argument (spell ID), result compared `== false`
  (nil = unknown, not out-of-range).
- classic_era's own generated doc for it (SpellDocumentation.lua:601-614):
  (spellIdentifier, optional targetUnit) -> bool? (nil when the check is invalid).
- classic_era ships the protected-function MECHANISM
  (C_RestrictedActions.CheckAllowProtectedFunctions, ADDON_ACTION_BLOCKED payload)
  but NO client-side list/comment naming any protected API.
- classic_era dispatches ADDON_ACTION_BLOCKED to addons (UIParent.lua:92 etc.).
- The vendored LRC can now call only `CheckInteractDistance`; its item and spell
  checker lists are never built under the 2026-10-21 guards; the item call shape is
  invalid for the modern function; the LRC's legacy captures/tables are upstream design.
- The addon's own `api.IsSpellInRange` (compat.lua:915-941) takes the
  C_Spell.IsSpellInRange branch on every supported client per the orchestrator matrix.

CONTEXT ONLY (web, not proof for the 1.15.x classic backport):
- The retail hotfixes that made the legacy IsItemInRange protected (10.2.0.52188 /
  10.2.0.52485) and its "API functions/restricted" category membership (W1).
- The per-version existence tags for C_Item.IsItemInRange (vanilla 1.15.2+), the
  C_Spell.IsSpellInRange (vanilla 1.15.4+) and the legacy IsSpellInRange (vanilla
  1.13.2+, no upper bound) (W2, W3, W4).
- The ADDON_ACTION_BLOCKED event description and payload (W5).

UNCONFIRMED:
- The protected state of every API except the item-range one on Era 1.15.9 (FU-1).
- Whether the legacy global IsSpellInRange exists in the 1.15.9 binary (FU-2).
- Whether C_SpellBook.IsSpellBookItemInRange exists in the classic_era binary (G1).
- The complete protected-API list (G2).
