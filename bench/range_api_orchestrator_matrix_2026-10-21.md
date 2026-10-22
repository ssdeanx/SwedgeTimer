# Cross-client range-API matrix (orchestrator-verified, 2026-10-21)

ORCHESTRATOR-VERIFIED with shell (`git grep` per branch in `/home/sam/wow-ui-source`).
The read-only research desk has NO shell and can only see the checked-out
`classic_era` branch, so this file is the cross-branch authority. Do not restate
these as the desk's own observations.

| branch | `C_Spell.IsSpellInRange` | legacy global `IsSpellInRange` | `C_SpellBook.IsSpellBookItemInRange` | legacy global `IsItemInRange` |
|---|---|---|---|---|
| `classic_era` | YES — 1 callsite, `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua:713` (ID form) | ABSENT (0 hits) | ABSENT (0 hits) | present, but it IS the modern C function: `Interface/AddOns/Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:29` -> `IsItemInRange = C_Item.IsItemInRange;` |
| `classic_anniversary` | YES — `CooldownViewer.lua:713` | ABSENT | ABSENT | same as above (`Deprecated_ItemScript.lua:29`) |
| `classic_titan` | YES — `CooldownViewer.lua:713` | ABSENT | ABSENT | same as above (`Deprecated_ItemScript.lua:29`) |
| `origin/live` | YES — 2 callsites (`CooldownViewer.lua:737`, `Interface/AddOns/Blizzard_Deprecated/11_0_0_SpellBookAPITransitionGuide.lua:46`) | ABSENT | YES — 1 (`11_0_0_SpellBookAPITransitionGuide.lua:47`, `Blizzard_APIDocumentationGenerated/SpellDocumentation.lua`) | legacy global present but CVar-gated — CORRECTION (2026-10-21, desk `range-lrc-guard`): `Interface/AddOns/Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:29` DOES define `IsItemInRange = C_Item.IsItemInRange;` on `origin/live` too, behind `GetCVarBool("loadDeprecationFallbacks")`. The row above originally said "ABSENT" — corrected here. Behaviourally moot: the fix keys on `C_Item.IsItemInRange`, not on the legacy global, so the guard fires on live either way. |
| `origin/forever` | YES — 3 callsites (`CooldownViewer.lua:737`, `11_0_0_SpellBookAPITransitionGuide.lua:46`, `Interface/AddOns/Blizzard_GamepadActionBars/TargetActionBars/HostileTargetingActionBar.lua:152`) | ABSENT | YES — 1 | legacy global ABSENT; the lib still resolves `C_Item.IsItemInRange` |

`CheckInteractDistance` exists on all five branches
(`Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua`,
`Interface/AddOns/Blizzard_UnitPopupShared/UnitPopupSharedUtils.lua`) and is
CALLABLE from addon code on the operator's Classic Era client: the melee checker
(`LRC:GetHarmMinChecker(2)` -> interact band 3) ran at `main.lua:1791` WITHOUT a
block, immediately before the blocked call at `main.lua:1797`.

## Consequences
1. The only modern range API on ALL five branches is the ID/name form
   `C_Spell.IsSpellInRange(spellIdentifier, targetUnit)` -> `true` / `false` / `nil`.
2. The INDEX form's modern replacement (`C_SpellBook.IsSpellBookItemInRange`) exists
   only on `live` + `forever`, NOT on the three classic branches — so the vendored
   LibRangeCheck's index-based checker has no modern equivalent on Classic Era.
3. The legacy global `IsSpellInRange` is not DEFINED in FrameXML on any of the five
   branches, so the vendored LRC's spell checkers (which capture it at load,
   `LibRangeCheck-2.0.lua:421`) can never answer from FrameXML.
   **CORRECTION (2026-10-21, desk `range-api-matrix`): this row originally read
   "the legacy global exists NOWHERE". That was established by grepping FrameXML
   ONLY, and a global implemented in the client BINARY would not appear there. The
   wiki's per-version tag for the legacy `IsSpellInRange` reads "vanilla + 1.13.2"
   with NO upper bound (bench/range_api_matrix_2026-10-21.md §3 W4), i.e. it claims
   the global is still present on the classic line. Both can be true. Binary
   presence is UNCONFIRMED — closed by the FU-2 type dump
   (`/run print("legacy:",type(IsSpellInRange), ...)`).
   CONSEQUENCE for the shipped fix: the guard
   `spellRangeAvailable = type(IsSpellInRange) == "function"`
   (`LibRangeCheck-2.0.lua:447`) is evaluated IN THE CLIENT, so if the legacy global
   does exist in the 1.15.9 binary the LRC's spell checkers are built and the legacy
   index/bookType call (`:477`, `:495`, `:826`, `:842`) runs — its protected state is
   unknown (the wiki shows no protection note for that API; the retail protection
   wave hit `IsItemInRange`, §3 W1). The operator's next `/reload` is the natural
   test: if the ADDON_ACTION_BLOCKED report is GONE, the legacy path is either
   absent or callable; if it PERSISTS, FU-2 decides and the strict variant (never
   build the spell list on a client that ships `C_Spell.IsSpellInRange`) is the
   follow-up.
4. The legacy global `IsItemInRange` exists only on the three classic branches, and
   there it IS `C_Item.IsItemInRange` (an ItemInfo-based, client-blocked function) —
   so the LRC's item checker is broken on all five branches, in two different ways:
   blocked call (classic) / missing legacy global (live, forever).

## Evidence status for "protected / blocked"
- PROVEN for the ITEM-range API on Classic Era 1.15.9: the operator's own in-client
  report, 2026-10-21 — `[ADDON_ACTION_BLOCKED] AddOn 'SwedgeTimer' tried to call the
  protected function 'UNKNOWN()'` with the stack `LibRangeCheck-2.0.lua:498` ->
  `main.lua:1797`.
- UNCONFIRMED for every other API (including `C_Spell.IsSpellInRange`): the operator
  declined the in-client probe on 2026-10-21 ("i have to copy all files over. so use a
  test, like we always do."). A wiki or forum claim about a "protected" API is NOT
  proof for the 1.15.x classic backport.
- The modern spell-range path (`R3`) is DEFERRED by operator order: the shipped fix
  uses NO client range API beyond the interact-distance bands.
