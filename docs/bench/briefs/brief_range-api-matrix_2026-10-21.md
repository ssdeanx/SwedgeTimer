# Brief: range-api-matrix (2026-10-21) — READ-ONLY research lane

## Objective
Settle the client-API facts the range fix depends on: which range APIs exist on each
supported client family, and which of them are PROTECTED (i.e. an addon call raises
`ADDON_ACTION_BLOCKED` / "tried to call the protected function"). One bench report,
no code edits.

## Why (the operator's in-client evidence, 2026-10-21)
The operator on Classic Era 1.15.9 reported (BugGrabber):
```
[ADDON_ACTION_BLOCKED] AddOn 'SwedgeTimer' tried to call the protected function 'UNKNOWN()'.
[LibRangeCheck-2.0.lua]:498: in function <...:497>
[SwedgeTimer/main.lua]:1797: in function <SwedgeTimer/main.lua:1790>
```
`Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua:498` is
`return IsItemInRange(item, unit)` inside the item checker, and the lib resolves the
global at line 422 as `(C_Item and C_Item.IsItemInRange) or _G.IsItemInRange`.
The call is NOT catchable by the addon's `pcall` (the client blocks the action, it
does not raise a Lua error) — so the addon's dead-man pcall cannot suppress it.

## Already answered by the orchestrator (DO NOT re-derive — build on it)
Verified in `/home/sam/wow-ui-source` with `git grep` per branch (orchestrator has shell):
- `Interface/AddOns/Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:29`
  (`IsItemInRange = C_Item.IsItemInRange;`) exists on `classic_era`,
  `classic_anniversary`, `classic_titan` — so on the three classic branches the LEGACY
  global IS the modern C_Item function (item-id call shape is invalid there).
  On `origin/live` and `origin/forever` the legacy global does not exist at all, but
  the lib still resolves `C_Item.IsItemInRange`.
- NO legacy `IsSpellInRange` global is defined on ANY of the five branches
  (`classic_era`, `classic_anniversary`, `classic_titan`, `origin/live`,
  `origin/forever`). Only `C_Spell.IsSpellInRange` exists, plus
  `C_SpellBook.IsSpellBookItemInRange(index, spellBank)` (seen on live/forever in
  `Interface/AddOns/Blizzard_Deprecated/11_0_0_SpellBookAPITransitionGuide.lua:47`).
- `CheckInteractDistance` exists on all five branches
  (`Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua`,
  `Blizzard_UnitPopupShared/UnitPopupSharedUtils.lua`).
- On the operator's client the interact-based MELEE checker ran without a block
  (it is called at `main.lua:1791`, before the blocked call at `main.lua:1797`), so
  `CheckInteractDistance` is callable from addon code on Classic Era.

## Your scope (READ-ONLY)
1. **Client source (classic_era branch is checked out at `/home/sam/wow-ui-source`)** —
   you have NO shell: use `ast_grep_search` with
   `paths: ["/home/sam/wow-ui-source/Interface"]`, `lang: "lua"`.
   - Does `C_SpellBook.IsSpellBookItemInRange` exist on the checked-out branch
     (classic_era)? Find its call sites and its argument shape (index + spellBank?)
     and its return contract (true/false/nil).
   - Find how Blizzard's own code calls `C_Spell.IsSpellInRange` (CooldownViewer,
     HostileTargetingActionBar) — the argument shape and the return contract.
   - Find any client-side list, comment or doc that marks an API as
     protected/blocked/restricted (search for "protected", "blocked", "restricted",
     "ADDON_ACTION_BLOCKED", "taint"). Report what the source can and cannot prove.
   - ast-grep CANNOT see a string literal inside a table constructor — if a
     pattern sweep "misses" a name, say so; do not report it as absent.
2. **Web (protected-API list)** — use the SearxNG MCP (`searxng_web_search`,
   `web_url_read`) and/or Firecrawl MCP (`firecrawl_search`, `firecrawl_scrape`).
   Enumerate BOTH catalogs first (Code-Mode `search("firecrawl")` + `search("searxng")`).
   Question: which WoW APIs are flagged protected (addon call ->
   "tried to call the protected function") as of the 11.x / 1.15.x client line?
   Specifically `C_Item.IsItemInRange` and `C_Spell.IsSpellInRange`.
   Cite the URL and what the page actually showed. If the web cannot settle it, say
   UNCONFIRMED — do not guess.

## Scope / write permission
- NO code edits. NO git. NO lint-config changes.
- Exactly ONE new bench file: `bench/range_api_matrix_2026-10-21.md` (confirm it does
  not exist before writing).
- Your own desk: `desks/range-api-matrix/` (journal + `.signals/`).

## Mechanics (skills — CALL these tools, in order)
`bench-read` (your desk journal + `bench/lessons.md` + the bench, journals before
artifacts) -> `desk-open` `desks/range-api-matrix/` -> `desk-journal` (append what you
did, the current state, the next step) -> `signal-write` (done/checkpoint/hands-up JSON
into `desks/range-api-matrix/.signals/`).

## Rules
- Every stated fact: CONFIRMED with a file:line or a URL, or UNCONFIRMED in caps.
- Name every gap explicitly (what you could not determine, what you tried, what
  evidence would close it). An unverified area is UNVERIFIED, never "it is fine".
- Read-only: you have no write tools for the repo except the bench file and your desk
  (if your desk write fails, report the report text in your final answer so the
  orchestrator can file it).

## Validation owner
The orchestrator. The range-fix lane is dispatched AFTER this report and after the
operator's in-client probe; your report decides which path the fix takes.
