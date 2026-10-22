# Per-client API truth table (2026-10-20)

Desk: `perclient-api-truth` · Scope: the 19 checks of the publish-gate re-audit's §3b
checklist, one row per API × branch, with `branch:file:line` + the quoted definition for
every claim. · Reference repo: `/home/sam/wow-ui-source` (read-only; `git show <branch>:<path>`
only — **no checkout, no modification**).

## 0. Method, branches, and the ground rules

Branches read (all five, each read on its own branch — never inferred from another):

| branch | client family the addon targets | interface |
|---|---|---|
| `classic_era` | Classic Era / SoD 1.15.9 → `_Vanilla` | 11509 |
| `classic_anniversary` | TBC Anniversary 2.5.6 → `_TBC` | 20506 |
| `classic_titan` | WotLK Titanforge 3.80.2 → `_Wrath` | 38002 |
| `origin/forever` | WoW Forever 1.60.1 → `_Mainline` | 16001 |
| `live` | Retail 12.1.x → `_Mainline` | 120105 |

Ground rules honoured: every claim carries `branch:file:line` and a quote; **ABSENT** is
used where the symbol is not in the tree; a branch's contents are never copied from another
branch; a symbol's *presence in the tree* is never claimed to prove a native C API exists
(the generated API-doc trees document the `C_*` namespaces only — a native global that
Blizzard's own FrameXML never calls will not appear there at all, and that is reported as
"absent from the tree", not "absent from the client").

A note on **load-game-type gating**, because it changes what a *file* means on
`origin/forever`: that branch ships one tree for several clients and selects files with
`[AllowLoadGameType …]` / `[ExcludeLoadGameType …]` (`Blizzard_FrameXMLBase.toc:15-23`,
`Blizzard_Deprecated.toc:4-10`). The WoW Forever client is the **`camelot`** game type
(the repo's own toc vocabulary; the addon's `WOW_PROJECT_CAMELOT` note in `AGENTS.md`).
Rows below mark this explicitly, because "the file exists on the branch" and "the file
loads on the client" are different claims.

**Provenance of the three findings this lane was sent to close (L-2 / L-3 / L-4):** the
publish-gate re-audit's own report file is **not on disk** — the findings reached this
desk through the dispatch brief only (the same gap the `reaudit-fixes` desk raised as
HU-16). Every finding was therefore re-verified against the reference repo from scratch
before anything was changed, and §4 records the verdict per finding with citations — two
confirmed and fixed, one **refuted**. Nothing in this file rests on the re-audit's text.

---

## 1. The truth table

### Check 1–4 — the classic global `IsSpellKnown`

Source on every branch: `Interface/AddOns/Blizzard_DeprecatedSpellBook/Deprecated_SpellBook.lua`
(file present on all five branches; the toc has **no** game-type gate —
`Blizzard_DeprecatedSpellBook.toc:7`).

| branch | file:line | quoted definition | shape |
|---|---|---|---|
| `classic_era` | `Deprecated_SpellBook.lua:16-20` | `function IsSpellKnown(spellID, isPet)` → `return C_SpellBook.IsSpellInSpellBook(spellID, spellBank, includeOverrides);` | 2 args, 1 return (bool) |
| `classic_anniversary` | `Deprecated_SpellBook.lua:16-20` | identical text (file is byte-identical to `classic_era` modulo line endings: md5 `5ec426b4…` vs `54777800…`) | 2 args, 1 return (bool) |
| `classic_titan` | `Deprecated_SpellBook.lua:16-20` | identical text (md5 `5ec426b4…`) | 2 args, 1 return (bool) |
| `origin/forever` | `Deprecated_SpellBook.lua:16-20` | identical text (md5 `54777800…`) | 2 args, 1 return (bool) |
| `live` | `Deprecated_SpellBook.lua:16-20` | identical text (md5 `54777800…`) | 2 args, 1 return (bool) |

The shim body (quoted from `classic_era`, identical elsewhere):

```lua
16:	function IsSpellKnown(spellID, isPet)
17:		local spellBank = isPet and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player;
18:		local includeOverrides = false;
19:		return C_SpellBook.IsSpellInSpellBook(spellID, spellBank, includeOverrides);
20:	end
```

**The deprecation shim still exists on all five branches** — with one nuance: it exists as
a *file*, but the *global* it defines only exists while the `loadDeprecationFallbacks` CVar
is on (check 5).

**Verdict — the addon's usage is correct on every branch.**
`compat.lua:207` reads it dynamically (`rawget(_G, "IsSpellKnown")`) and `compat.lua:236`
calls it with **one** argument (`spell_id`), so `isPet` is `nil` → `spellBank = Player`.
That is the shim's own default path. One semantic note worth keeping: the global answers
`C_SpellBook.IsSpellInSpellBook(..., includeOverrides = false)`, **not**
`C_SpellBook.IsSpellKnown` — so on a client where the global exists, the addon's first
probe is the *spellbook* question, not the *known* question (the two differ for
temporarily-granted abilities and for override spells). No gate is needed; the
`C_SpellBook.IsSpellKnown` probe behind it (check 6) is the stricter question.

### Check 5 — the `loadDeprecationFallbacks` CVar gate

| branch | file:line | quoted definition | verdict |
|---|---|---|---|
| `classic_era` | `Deprecated_SpellBook.lua:4-6` | `if not GetCVarBool("loadDeprecationFallbacks") then` / `return;` / `end` | **PRESENT** |
| `classic_anniversary` | `Deprecated_SpellBook.lua:4-6` | same | **PRESENT** |
| `classic_titan` | `Deprecated_SpellBook.lua:4-6` | same | **PRESENT** |
| `origin/forever` | `Deprecated_SpellBook.lua:4-6` | same | **PRESENT** |
| `live` | `Deprecated_SpellBook.lua:4-6` | same | **PRESENT** |

The gate is not confined to the spell book: the string `loadDeprecationFallbacks` occurs in
**33 files** on `classic_era`, 33 on `classic_anniversary`, 33 on `classic_titan`,
**31** on `origin/forever` and **40** on `live` (whole-tree counts via
`git grep -c`). Examples outside the spell book:
`Blizzard_Deprecated/Deprecated_1_15_8.lua:5`, `…/Deprecated_2_5_5.lua:5`,
`Blizzard_DeprecatedCombatLog/Deprecated_CombatLog.lua`, `Blizzard_DeprecatedSpellBook/…:4`,
`Blizzard_DeprecatedItemScript/…`, `Blizzard_DeprecatedActionBar/…` (the full 33-file list
is on `classic_era`; the count alone is enough to refute "nowhere in the tree").

**Verdict — the addon's usage is correct on every branch; no gate needed.**
`compat.lua` never depends on the deprecated globals being present: the probe chain
(`compat.lua:204-227`) is dynamic (`rawget`) and the no-probe branch is handled
(`compat.lua:234-245`). The CVar being off would remove the *global* on every branch at
once — never selectively — so the addon's per-branch behaviour does not change.

### Check 6 — `C_SpellBook.IsSpellKnown`

Source: `Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua`
(namespace declared at line 5: `Namespace = "C_SpellBook",` — identical on all five
branches).

| branch | file:line | quoted definition | shape |
|---|---|---|---|
| `classic_era` | `SpellBookDocumentation.lua:82` | `Name = "IsSpellKnown",` (block `:81-96`) | args `spellID:number`, `spellBank:SpellBookSpellBank` (default `Player`); returns `isKnown:bool` (`:94`) |
| `classic_anniversary` | `SpellBookDocumentation.lua:82` | same | same |
| `classic_titan` | `SpellBookDocumentation.lua:82` | same | same |
| `origin/forever` | `SpellBookDocumentation.lua:738` | `Name = "IsSpellKnown",` | same shape (`isKnown:bool`) |
| `live` | `SpellBookDocumentation.lua:684` | `Name = "IsSpellKnown",` | same shape (`isKnown:bool`) |

The classic_era block quoted in full:

```lua
81:		{
82:			Name = "IsSpellKnown",
83:			Type = "Function",
84:			Documentation = { "Returns true if a player knows a spell. This function can also return true for spells that aren't in the spellbook, such as temporarily-granted abilities" },
86:			Arguments =
87:			{
88:				{ Name = "spellID", Type = "number", Nilable = false },
89:				{ Name = "spellBank", Type = "SpellBookSpellBank", Nilable = false, Default = "Player" },
90:			},
92:			Returns =
93:			{
94:				{ Name = "isKnown", Type = "bool", Nilable = false },
95:			},
96:		},
```

**Verdict — the addon's usage is correct on every branch.**
`compat.lua:221-223` appends `C_SpellBook.IsSpellKnown` as probe #2 and calls it with one
argument (`spell_id`), so `spellBank` defaults to `Player` — the same question the classic
global answers. The API is documented on **all five** branches, so the probe is never
missing on a shipped client.

### Check 7 — `C_SpellBook.IsSpellKnownOrInSpellBook`

Same file as check 6.

| branch | file:line | quoted definition | shape |
|---|---|---|---|
| `classic_era` | `SpellBookDocumentation.lua:98` | `Name = "IsSpellKnownOrInSpellBook",` (block `:97-113`) | args `spellID`, `spellBank` (default `Player`), `includeOverrides:bool` (default `true`); returns `isKnownOrInSpellBook:bool` (`:111`) |
| `classic_anniversary` | `SpellBookDocumentation.lua:98` | same | same |
| `classic_titan` | `SpellBookDocumentation.lua:98` | same | same |
| `origin/forever` | `SpellBookDocumentation.lua:755` | `Name = "IsSpellKnownOrInSpellBook",` | same |
| `live` | `SpellBookDocumentation.lua:701` | `Name = "IsSpellKnownOrInSpellBook",` | same |

**The probe is NOT inert anywhere.** It exists on `classic_era` at
`SpellBookDocumentation.lua:98` — the same file, 16 lines below `IsSpellKnown`. (The
re-audit's premise of "0 hits on `classic_era`" is refuted in §4.2 below.)

**Verdict — the addon's usage is correct on every branch.**
`compat.lua:224-226` appends it as probe #3. It is the **loosest** of the three probes
(known **or** present in the spellbook, overrides included), so it can answer `true`
where `IsSpellKnown` would answer `false`. Because the chain is ordered
(global → `IsSpellKnown` → `IsSpellKnownOrInSpellBook`) and the first probe that *answers*
wins, probe #3 only ever runs on a client where the first two are absent **or declined**
(`compat.lua:236-243`: a probe that returns `nil` moves the chain on). No branch of the
shipped matrix reaches it with a stricter answer pending — but if one ever did, the
loosest answer would be the one that gets used. Worth a one-line note in the compat
comment; it is **not** a defect.

### Check 8 — the deprecated `UnitAura` shim

| branch | file:line | quoted definition | verdict |
|---|---|---|---|
| `classic_era` | `Interface/AddOns/Blizzard_Deprecated/Deprecated_1_15_8.lua:10-17` | `UnitAura = function(unitToken, index, filter)` → `return AuraUtil.UnpackAuraData(auraData);` | arity **3** |
| `classic_anniversary` | `Deprecated_1_15_8.lua:10-17` | same text (md5 `277e0917…` on both classic branches; `classic_era` differs only in line endings) | arity **3** |
| `classic_titan` | `Deprecated_1_15_8.lua:10-17` | same text | arity **3** |
| `origin/forever` | `Interface/AddOns/Blizzard_Deprecated/**Classic**/Deprecated_1_15_8.lua:10-17` | same text | arity **3**, but the file is `[AllowLoadGameType classic]` → **not loaded on the camelot game type** |
| `live` | `Interface/AddOns/Blizzard_Deprecated/**Classic**/Deprecated_1_15_8.lua:10-17` | same text | arity **3**, but the file is `[AllowLoadGameType classic]` → **not loaded on the mainline game type** |

On `origin/forever` / `live` the `Blizzard_Deprecated` toc is:

```
4:	Classic/Deprecated_1_15_8.lua [AllowLoadGameType classic]
5:	Classic/Deprecated_2_5_5.lua [AllowLoadGameType classic]
6:	Mainline/Deprecated_12_0_1.lua [AllowLoadGameType mainline]
…
10:	Shared/Deprecated_12_1_0.lua
```

and the only ungated file, `Shared/Deprecated_12_1_0.lua`, does **not** define `UnitAura`
(verified by grep over the whole file on both branches: it defines `getglobal`,
`setglobal`, `C_UnitAuras.AddPrivateAuraAppliedSound`, `CancelItemTempEnchantment`, …).
`Mainline/Deprecated_12_0_1.lua` / `_12_0_5` / `_12_0_7` / `_12_1_0` do not define it
either. A whole-branch grep (`git grep -n "UnitAura = "`) on `live` returns exactly two
Lua definitions — `Classic/Deprecated_1_15_8.lua:10` and `Classic/Deprecated_2_5_5.lua:10`
— both classic-gated. The bare global `UnitAura` is **not** a documented C API on any
branch (the `Name = "UnitAura"` hits in the API docs are the `UNIT_AURA` *event*,
`UnitAuraDocumentation.lua:600` on `live`).

**Verdict — the addon's usage is correct on every branch; the `else` branch is the live
path.** `compat.lua:492` takes the classic global when it exists, `compat.lua:503` the
`C_UnitAuras` namespace otherwise, `compat.lua:520-524` a nil-returning stub when neither
does. On Retail and on WoW Forever the global is **absent** (classic-gated file) and the
`C_UnitAuras` path answers; on the classic clients the global answers first. The addon
calls it with **three** arguments (`compat.lua:495`, `compat.lua:617`), matching the
shim's arity 3 exactly.

### Check 9 — `C_UnitAuras.GetAuraDataByIndex`

| branch | file:line | quoted definition | shape |
|---|---|---|---|
| `classic_era` | `UnitAuraDocumentation.lua:156` | `Name = "GetAuraDataByIndex",` (namespace `C_UnitAuras` at `:5`) | args `unit`, `index`, `filter`; returns `aura: AuraData` (nilable) |
| `origin/forever` | `UnitAuraDocumentation.lua:208` | `Name = "GetAuraDataByIndex",` | args `unit:UnitTokenRestrictedForAddOns`, `index:luaIndex`, `filter:AuraFilters`; returns `aura:AuraData` (nilable) |
| `live` | `UnitAuraDocumentation.lua:188` | `Name = "GetAuraDataByIndex",` | same as forever |

The AuraData field names the addon reads are not in the doc tree (the `AuraData` struct is
referenced by type but not defined there); the authoritative field list is Blizzard's own
unpacker, `Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua:40-61` — **byte-identical
on `origin/forever` and `live`**:

```lua
40:	function AuraUtil.UnpackAuraData(auraData)
45:		return auraData.name,
46:			auraData.icon,
47:			auraData.applications,
48:			auraData.dispelName,
49:			auraData.duration,
50:			auraData.expirationTime,
51:			auraData.sourceUnit,
52:			auraData.isStealable,
53:			auraData.nameplateShowPersonal,
54:			auraData.spellId,
55:			auraData.canApplyAura,
56:			auraData.isBossAura,
57:			auraData.isFromPlayerOrPlayerPet,
58:			auraData.nameplateShowAll,
59:			auraData.timeMod,
60:			unpack(auraData.points);
61:	end
```

So the AuraData fields are: `name`, `icon`, `applications`, `dispelName`, `duration`,
`expirationTime`, `sourceUnit`, `isStealable`, `nameplateShowPersonal`, `spellId`,
`canApplyAura`, `isBossAura`, `isFromPlayerOrPlayerPet`, `nameplateShowAll`, `timeMod`,
`points`. Note the count field is **`applications`**, not `count` — `count` is only the
addon's own local name.

**Verdict — the addon's usage is correct on every branch.**
`compat.lua:509-512` reads exactly: `aura.name, aura.icon, aura.applications,
aura.dispelName, aura.duration, aura.expirationTime, aura.sourceUnit, aura.isStealable,
aura.nameplateShowPersonal, aura.spellId` — field-for-field the unpacker's first ten
fields, in the same order. The whole-entry secret degrade (`compat.lua:485-490`,
`:513-516`) covers all ten. No gate needed.

### Check 10 — `GetTotemInfo`

Source on every branch: `Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua`
(the toc loads it on all five branches: `Blizzard_CooldownViewer.toc:20`; on
`origin/forever` the toc header is `## AllowLoadGameType: standard, camelot`, so it **is**
loaded on WoW Forever).

| branch | file:line | quoted definition | returns consumed |
|---|---|---|---|
| `classic_era` | `CooldownViewerItemData.lua:453` | `local hasTotem, name, startTime, duration, _icon, modRate, spellID = GetTotemInfo(slot);` | **7** (7th = `spellID`) |
| `classic_anniversary` | `CooldownViewerItemData.lua:453` | identical | **7** |
| `classic_titan` | `CooldownViewerItemData.lua:453` | identical | **7** |
| `origin/forever` | `CooldownViewerItemData.lua:836` | identical | **7** |
| `live` | `CooldownViewerItemData.lua:781` | identical | **7** |

The API-doc entry agrees on all five branches —
`Interface/AddOns/Blizzard_APIDocumentationGenerated/TotemDocumentation.lua`:

| branch | file:line | returns documented |
|---|---|---|
| `classic_era` | `TotemDocumentation.lua:56-74` | `haveTotem:bool`, `totemName:cstring`, `startTime:number`, `duration:number`, `icon:fileID`, `modRate:number`, `spellID:number` (`MayReturnNothing = true`) |
| `classic_anniversary` | `TotemDocumentation.lua:56-74` | same |
| `classic_titan` | `TotemDocumentation.lua:56-74` | same |
| `origin/forever` | `TotemDocumentation.lua:59-79` | same + `SecretWhenTotemSlotSecret = true` |
| `live` | `TotemDocumentation.lua:59-79` | same + `SecretWhenTotemSlotSecret = true` |

**The 7th return (`spellID`) is present on every branch — it is not a later addition
limited to some clients.** The *secret* annotation is the later addition, and it is on the
two Mainline-code branches (Forever + Retail), not on the classic ones.

**Verdict — the addon's usage is correct on every branch.**
`compat.lua:1234` consumes **seven** values (`have_totem, totem_name, start_time,
duration, icon, mod_rate, spell_id`) and `compat.lua:1242-1246` secret-checks all seven
before returning them — matching the `SecretWhenTotemSlotSecret` annotation on
Forever/Retail. The `MayReturnNothing` case is handled by `compat.lua:1239-1241`
(`have_totem == nil` → nil). No gate needed.

### Check 11 — the totem slot constants on the classic branches

Source: `Interface/AddOns/Blizzard_FrameXMLBase/**Classic**/Constants.lua`
(loaded first by every classic flavour toc — `Blizzard_FrameXMLBase_Vanilla.toc:15`,
`_TBC.toc:15`, `_Wrath.toc:15` all list `Classic\Constants.lua`; the flavour files
`Vanilla/`, `TBC/`, `Wrath/`, `Cata/`, `Mists/` contain **0** `TOTEM_SLOT` hits on every
classic branch, so `Classic/Constants.lua` is the only definition).

| branch | file:line | quoted definition |
|---|---|---|
| `classic_era` | `Classic/Constants.lua:286-289` | `FIRE_TOTEM_SLOT = 1;` / `EARTH_TOTEM_SLOT = 2;` / `WATER_TOTEM_SLOT = 3;` / `AIR_TOTEM_SLOT = 4;` |
| `classic_anniversary` | `Classic/Constants.lua:286-289` | identical |
| `classic_titan` | `Classic/Constants.lua:286-289` | identical |

(For reference, the same block on `classic_era` is preceded by `MAX_TOTEMS = 4;` at
`:284` and followed by `STANDARD_TOTEM_PRIORITIES = {1, 2, 3, 4};` at `:291`.)

### Check 12 — the totem slot constants on `origin/forever` / `live`

| branch | file:line | quoted definition |
|---|---|---|
| `origin/forever` | `Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:226-229` | `FIRE_TOTEM_SLOT = 1;` / `EARTH_TOTEM_SLOT = 2;` / `WATER_TOTEM_SLOT = 3;` / `AIR_TOTEM_SLOT = 4;` |
| `live` | `Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:241-244` | same four lines |

**Load-gating nuance on `origin/forever` (important, and new):** on that branch the file
is `Blizzard_FrameXMLBase/Constants.lua`, but its toc entry is
`Constants.lua [AllowLoadGameType mainline]` (`Blizzard_FrameXMLBase.toc:18`), while the
camelot game type (WoW Forever 1.60.1) loads `[Game]\Constants.lua`
(`Blizzard_FrameXMLBase.toc:16`, `[AllowLoadGameType camelot]`) → `Camelot/Constants.lua`
(the `[Family]` entry at `:15` is `[ExcludeLoadGameType camelot]`).
`Camelot/Constants.lua` is **12 lines long** (`CLASS_SORT_ORDER` + `MAX_CLASSES`) and
contains **no** `TOTEM_SLOT` definition; `Shared/Constants.lua` contains none either
(0 hits on every branch). So on the WoW Forever client the four constants are **not
defined as globals** — the definition lives only in the mainline-gated file.

### Checks 11 + 12 — verdict for the totem slot constants

**The addon's usage is correct on every branch — and it does not read these globals at
all.** The addon hard-codes the slot numbers in `classes/shaman.lua:226-231`:

```lua
226:	local WEAVE_TOTEM_SLOTS = {
227:		FIRE = 1,
228:		EARTH = 2,
229:		WATER = 3,
230:		AIR = 4,
231:	}
```

The constants are therefore **documentary** evidence that 1/2/3/4 are the right slot
numbers, not a runtime dependency. Two consequences:

* No gate, no degrade, nothing to file — the numbers are hard-coded and correct on every
  branch (the *values* are identical 1/2/3/4 in all five definitions).
* The citation in `compat.lua:1218` was wrong (see §4.1) and is now corrected per branch.
  The corrected citation should also say *why* it is documentary: on WoW Forever the
  globals are not even defined on the client.

### Check 13 — `GetSpellBaseCooldown`

| branch | file:line | quoted definition |
|---|---|---|
| `classic_era` | — | **ABSENT from the tree** (0 hits, whole tree, incl. `Blizzard_APIDocumentationGenerated/`) |
| `classic_anniversary` | — | **ABSENT from the tree** (0 hits) |
| `classic_titan` | — | **ABSENT from the tree** (0 hits) |
| `origin/forever` | — | **ABSENT from the tree** (0 hits) |
| `live` | — | **ABSENT from the tree** (0 hits) |

Method: `git grep -n "GetSpellBaseCooldown" <branch>` over the **whole** branch — 0
matching files on all five branches (FrameXML, generated API docs, everything). It is a
native classic-era C global with no Lua definition and no Blizzard call site on any
branch, so the tree cannot say whether the C API itself still exists on a given client —
only that no Blizzard code uses it there.

**Verdict — the addon's usage is correct on every branch; the absence is already
handled.** `compat.lua:346-361`: if the global exists it is wrapped (and a secret reading
degrades to `(0, 0)`); if it does not, `api.GetSpellBaseCooldown` returns `(0, 0)`.
Callers treat a non-positive base cooldown as "no value" and fall back to their own
constant (`classes/paladin.lua:312-313` says so in words). **No gate needed** — the
degrade is the contract.

### Check 14 — `GetSpellPowerCost`

The export exists on all five branches, in two forms.

**Form A — `C_Spell.GetSpellPowerCost`** (the namespace form, present everywhere):

| branch | file:line | quoted definition |
|---|---|---|
| `classic_era` | `SpellDocumentation.lua:300-314` | `Name = "GetSpellPowerCost",` … `Returns = { { Name = "powerCosts", Type = "table", InnerType = "SpellPowerCostInfo", Nilable = false } }` |
| `classic_anniversary` | `SpellDocumentation.lua:300-314` | same |
| `classic_titan` | `SpellDocumentation.lua:300-314` | same |
| `origin/forever` | `SpellDocumentation.lua:535` | same |
| `live` | `SpellDocumentation.lua:494` | same |

(namespace `C_Spell` at `SpellDocumentation.lua:5` on every branch.)

**Form B — the classic global `GetSpellPowerCost`**, whose two-argument form is documented
in Blizzard's own transition guide (`Interface/AddOns/Blizzard_Deprecated/11_0_0_SpellBookAPITransitionGuide.lua`,
present on `origin/forever` and `live`):

```
66:	-- Both return array of new SpellPowerCostInfo tables (see SpellSharedDocumentation.lua) which matches old return table structure
67:	GetSpellPowerCost(spellID/name) = C_Spell.GetSpellPowerCost(spellIdentifier)
68:	GetSpellPowerCost(index, bookType) = C_SpellBook.GetSpellBookItemPowerCost(index, spellBank)
```

So the **global has arity 1 (spell id/name) or 2 (index, bookType)**, and both forms
return the *same* array-of-`SpellPowerCostInfo` shape.

`SpellPowerCostInfo` (`SpellSharedDocumentation.lua:46-59` on `live`):

```lua
50:				{ Name = "type", Type = "PowerType", Nilable = false },
51:				{ Name = "name", Type = "string", Nilable = false, Documentation = { "The name or 'power token' for this power type (ex: MANA, FOCUS, etc)" } },
52:				{ Name = "cost", Type = "number", Nilable = false, … },
53:				{ Name = "minCost", Type = "number", Nilable = false, … },
54:				{ Name = "costPercent", … },
55:				{ Name = "costPerSec", … },
56:				{ Name = "requiredAuraID", … },
57:				{ Name = "hasRequiredAura", … },
```

**On the "3rd return":** the API has **one** return (a table). What the checklist calls the
"3rd return" is the **third element of that array** — the third *power type* the spell
costs. The addon's consumers do **not** index position 3:

* `classes/warrior.lua:995-1001` and `classes/druid.lua:157-163` read
  `costs[1].cost` — the **first** power-type entry (assumed to be rage; the classes'
  own comments say so).
* `classes/rogue.lua:457-472` (`energy_cost_of`) iterates the whole array and selects the
  entry whose `info.type == Enum.PowerType.Energy` — i.e. it selects **by power type**,
  not by index, which is the honest way to read an array whose order is a power-type
  enumeration.

Blizzard's own code uses the same two shapes: `Blizzard_ActionBar/Shared/ActionButton.lua:763`
and `:781` (`costTable = C_Spell.GetSpellPowerCost(actionID)`), and
`Blizzard_PersonalResourceDisplay.lua:648` (`costTable = C_Spell.GetSpellPowerCost(spellID) or {}`)
— identical line numbers on `classic_era`, `classic_anniversary`, `classic_titan` and
`live`.

**Verdict — the addon's usage is correct on every branch; the "3rd return" framing is
what needs correcting, not the code.** `compat.lua:334-335` prefers the classic global
and falls back to `C_Spell.GetSpellPowerCost`; both return the same array shape, so the
wrapper is transparent. The unknown-client stub (`compat.lua:338-340`) returns
`{ { cost = 0, minCost = 0 } }` — an array whose **first** entry has `.cost = 0`, which
is the shape the consumers read. Two residual notes (not defects): the stub's entry has
no `.type`, so the rogue's type-matched read returns nil on an unknown client (correct —
unknown, never a guess), and the classic global's **2-arg** form (`index, bookType`) is
never used by the addon — the addon always passes a spell id/name, the 1-arg form.

### Check 15 — `GetSpellCooldown`

| branch | file:line | quoted definition | shape |
|---|---|---|---|
| `classic_era` | `Interface/AddOns/Blizzard_UIPanels_Game/Classic/SpellBookFrame.lua:324` | `local start, duration, enable, modRate = GetSpellCooldown(slot, SpellBookFrame.bookType);` | classic global, **2-arg** `(index, bookType)` form, 4 returns |
| `classic_anniversary` | same path:line | same | 2-arg form, 4 returns |
| `classic_titan` | same path:line | same | 2-arg form, 4 returns |
| `origin/forever` | `Interface/AddOns/Blizzard_UIPanels_Game/**Cata**/SpellBookProfessions.lua:42` | `local start, duration, enable = GetSpellCooldown(spellIndex, SpellBookFrame.bookType);` | 2-arg form, 3 returns consumed |
| `origin/forever` | `Interface/AddOns/Blizzard_UIPanels_Game/Mainline/WorldMapActionButton.lua:110` | `local cooldownInfo = C_Spell.GetSpellCooldown(self.spellID);` | modern 1-arg form, `SpellCooldownInfo` table |
| `live` | `Interface/AddOns/Blizzard_UIPanels_Game/Mainline/WorldMapActionButton.lua:110` | `local cooldownInfo = C_Spell.GetSpellCooldown(self.spellID);` | modern 1-arg form, `SpellCooldownInfo` table |

**`Interface/AddOns/Blizzard_UIPanels_Game/Classic/SpellBookFrame.lua` does not exist on
`live`** (the tree has only `Mainline/` and `Shared/` there) and does not exist on
`origin/forever` either (that branch has `Cata/`, `Vanilla/`, `Mainline/`, `Shared/`,
`Camelot/`, `Standard/` — no `Classic/`). So the file named in the checklist is a
**classic-branch-only** file; the forever/live evidence is the `WorldMapActionButton.lua`
line above.

**"Does the retail branch use `C_Spell.GetSpellCooldown` only?" — yes.** On `live`, the
only `GetSpellCooldown` reference anywhere under `Blizzard_UIPanels_Game` is
`C_Spell.GetSpellCooldown(self.spellID)` (`WorldMapActionButton.lua:110`); the classic
2-arg global form has no call site on `live` at all. On `origin/forever` **both** forms
exist (the 2-arg classic global in `Cata/SpellBookProfessions.lua:42`, the modern form in
`Mainline/WorldMapActionButton.lua:110`).

The transition guide (`11_0_0_SpellBookAPITransitionGuide.lua:52-54`, on `origin/forever`
and `live`) states the mapping:

```
52:	-- Both return new SpellCooldownInfo table (see SpellSharedDocumentation.lua)
53:	GetSpellCooldown(spellID/name) = C_Spell.GetSpellCooldown(spellIdentifier)
54:	GetSpellCooldown(index, bookType) = C_SpellBook.GetSpellBookItemCooldown(index, spellBank)
```

`SpellCooldownInfo` (`SpellSharedDocumentation.lua:19-31` on `live`): `startTime:number`,
`duration:number`, `isEnabled:bool`, `isActive:bool`, `modRate:number`, …

**Verdict — the addon's usage is correct on every branch.**
`compat.lua:262-263` prefers the classic global and falls back to
`C_Spell.GetSpellCooldown`; `compat.lua:268` calls the classic form with **one**
argument (the spell id/name) — the 1-arg form, never the 2-arg `bookType` form, which is
correct because the addon always passes a spell identifier, never a spell-book index.
The retail branch reads `info.startTime`, `info.duration`, `info.isEnabled`, `info.modRate`
(`compat.lua:274-281`) — the first, second, third and seventh documented fields of
`SpellCooldownInfo`. No gate needed.

### Check 16 — `C_Spell.GetSpellInfo`

| branch | file:line | quoted definition |
|---|---|---|
| `classic_era` | `SpellDocumentation.lua:190` | `Name = "GetSpellInfo",` (returns `spellInfo: SpellInfo`) |
| `classic_anniversary` | `SpellDocumentation.lua:190` | same |
| `classic_titan` | `SpellDocumentation.lua:190` | same |
| `origin/forever` | `SpellDocumentation.lua:416-431` | `Name = "GetSpellInfo",` … `{ Name = "spellInfo", Type = "SpellInfo", Nilable = false }` |
| `live` | `SpellDocumentation.lua:375-390` | same |

The `SpellInfo` struct fields (the table the addon maps):

| branch | file:line | quoted fields |
|---|---|---|
| `classic_era` | `SpellDocumentation.lua:782-794` | `name`, `iconID`, `originalIconID`, `castTime`, `minRange`, `maxRange`, `spellID` |
| `classic_anniversary` | `SpellDocumentation.lua:782-794` | same |
| `classic_titan` | `SpellDocumentation.lua:782-794` | same |
| `origin/forever` | `SpellDocumentation.lua:1183-1195` | same |
| `live` | `SpellDocumentation.lua:1109-1121` | same |

```lua
1113:				{ Name = "name", Type = "string", Nilable = false },
1114:				{ Name = "iconID", Type = "fileID", Nilable = false, … },
1115:				{ Name = "originalIconID", Type = "fileID", Nilable = false },
1116:				{ Name = "castTime", Type = "number", Nilable = false },
1117:				{ Name = "minRange", Type = "number", Nilable = false },
1118:				{ Name = "maxRange", Type = "number", Nilable = false },
1119:				{ Name = "spellID", Type = "number", Nilable = false },
```

The checklist's file — `Interface/AddOns/Blizzard_WorldLootObjectList/Blizzard_WorldLootObjectList.lua`
— uses it identically on both branches:

| branch | file:line | quoted definition |
|---|---|---|
| `origin/forever` | `Blizzard_WorldLootObjectList.lua:31` | `local spellData = C_Spell.GetSpellInfo(spellInfo.spellID);` |
| `live` | `Blizzard_WorldLootObjectList.lua:31` | same (the file is identical on both branches at `:31-32`) |

The classic global `GetSpellInfo` (the fallback shape the addon also supports) is visible
in the classic branches' own code: `Blizzard_Collections/Classic/Blizzard_MountCollection.lua:641`
— `local spellName, _, spellIcon = GetSpellInfo(self.spellID);` and
`Blizzard_Commentator/Blizzard_CommentatorSpell.lua:7` —
`self.Icon:SetTexture(select(3, GetSpellInfo(spellID)))` — i.e. position 1 = name,
position 2 = subname/rank, position 3 = icon (a fileID).

**Verdict — the addon's usage is correct on every branch.**
`compat.lua:160-169`: the classic global is used when present; otherwise
`C_Spell.GetSpellInfo` is mapped to
`info.name, nil, info.originalIconID, info.castTime, info.minRange, info.maxRange, info.spellID`
(`compat.lua:169`) — position 3 = the **icon**, position 4 = the **cast time**, exactly
the classic positions (see the two quotes above). `originalIconID` is the documented
"non-overridden" icon on all five branches (`SpellDocumentation.lua:788` on the classic
branches, `:1189` on forever, `:1115` on live). No gate needed.

### Check 17 — `C_EventUtils.IsEventValid`

| branch | file:line | quoted definition | shape |
|---|---|---|---|
| `classic_era` | `EventUtilsDocumentation.lua:25-37` (namespace `C_EventUtils` at `:5`) | `Name = "IsEventValid",` → args `eventName:stringView`; returns `valid:bool` | 1 arg, 1 bool |
| `classic_anniversary` | `EventUtilsDocumentation.lua:25-37` | same | same |
| `classic_titan` | `EventUtilsDocumentation.lua:25-37` | same | same |
| `origin/forever` | `EventUtilsDocumentation.lua:26-39` | same (+ `SecretArguments = "AllowedWhenUntainted"`) | same |
| `live` | `EventUtilsDocumentation.lua:26-39` | same (+ `SecretArguments = "AllowedWhenUntainted"`) | same |

The framexml consumer named in the checklist,
`Interface/AddOns/Blizzard_SharedXML/EventUtil.lua:12`, is identical on all five
branches:

```lua
12:		assert(C_EventUtils.IsEventValid(event), ("Unknown event \"%s\""):format(event));
```

and the file is loaded on every branch (classic branches: `Blizzard_SharedXML_Vanilla.toc:41`;
`origin/forever`: `Blizzard_SharedXML.toc:37`; `live`: `Blizzard_SharedXML.toc:34`).

**Verdict — the addon's usage is correct on every branch.**
`swing_source.lua:49` probes `C_EventUtils ~= nil and C_EventUtils.IsEventValid ~= nil`
and `swing_source.lua:59` calls it with one argument; `swing_source.lua:61` falls back
to `st.family == "FOREVER"` when the namespace is missing. The vendored `LibRangeCheck`
does the same (`LibRangeCheck-2.0.lua:1146`, `:1151`). No gate needed.

### Check 18 — `C_Item.GetItemInfo`

| branch | file:line | quoted definition | positions 6/7 |
|---|---|---|---|
| `classic_era` | `Interface/AddOns/Blizzard_ItemButton/Shared/ItemButtonTemplate.lua:187` | `local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemIcon = C_Item.GetItemInfo(item);` | `itemType` / `itemSubType` |
| `classic_anniversary` | same path:line | identical | same |
| `classic_titan` | same path:line | identical | same |
| `origin/forever` | same path:line | identical | same |
| `live` | same path:line | identical | same |

The generated doc agrees on every branch:
`Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua` —
`Name = "GetItemInfo",` at `:393` (classic branches) / `:626` (forever) / `:604` (live),
with returns

```
616:					{ Name = "itemName", Type = "cstring", Nilable = false },
617:					{ Name = "itemLink", Type = "cstring", Nilable = false },
618:					{ Name = "itemQuality", Type = "ItemQuality", Nilable = false },
619:					{ Name = "itemLevel", Type = "number", Nilable = false },
620:					{ Name = "itemMinLevel", Type = "number", Nilable = false },
621:					{ Name = "itemType", Type = "cstring", Nilable = false },
622:					{ Name = "itemSubType", Type = "cstring", Nilable = false },
623:					{ Name = "itemStackCount", Type = "number", Nilable = false },
624:					{ Name = "itemEquipLoc", Type = "cstring", Nilable = false },
625:					{ Name = "itemTexture", Type = "fileID", Nilable = false },
626:					{ Name = "sellPrice", Type = "number", Nilable = false },
```

(line numbers above are `live`; the classic branches carry the same block at `:409-410`
for `itemType`/`itemSubType`, forever at `:643-644`.)

**Positions 6 and 7 are `itemType` / `itemSubType` on every branch — confirmed.** The
`C_Item` namespace is present on the classic branches too (`ItemDocumentation.lua:5` is
`Namespace = "C_Item",` on all five), so the addon's **preferred** probe answers
everywhere.

The **classic global** `GetItemInfo` is a native C API with **no** Lua definition and
**no** FrameXML call site on any branch (`git grep` for a bare `GetItemInfo(` → 0 files
on `classic_era`, `origin/forever` and `live`; Blizzard's own code has moved to
`C_Item.GetItemInfo` everywhere). Its classic shape
(`name, link, quality, iLevel, reqLevel, class, subclass, maxStackCount, equipSlot,
texture, sellPrice`) is therefore **not citable from the reference tree** — it is the
addon's own recorded model (`compat.lua:1279-1283` and the pins in
`tests/secret_guard_state.lua:1511-1519`). That limitation is recorded here rather than
papered over.

**Verdict — the addon's usage is correct, but its *naming* was not (see §4.3).**
`compat.lua:1262-1274` prefers `C_Item.GetItemInfo` (positions 6/7 = `itemType` /
`itemSubType`, **tree-citable on all five branches**) and falls back to the classic
global (positions 6/7 = `class` / `subclass` per the addon's own model). Both put the
item's **type** string in position 6 and the item's **subtype** string in position 7, so
the values agree — but the two shapes *name* those fields differently, and
`compat.lua:1288` named the locals `class, subclass`, which is accurate for the fallback
and misleading for the preferred probe. Corrected in §4.3: the wrapper now normalises
both shapes to one documented contract, `item_type, item_sub_type`.

### Check 19 — `INVSLOT_FIRST_EQUIPPED` / `INVSLOT_LAST_EQUIPPED`

| branch | file:line | quoted definition | range |
|---|---|---|---|
| `classic_era` | `Interface/AddOns/Blizzard_FrameXMLBase/Classic/Constants.lua:173` and `:192` | `INVSLOT_HEAD 		= 1; INVSLOT_FIRST_EQUIPPED = INVSLOT_HEAD;` … `INVSLOT_LAST_EQUIPPED = INVSLOT_TABARD;` (with `INVSLOT_TABARD = 19;` at `:191`) | **1..19** |
| `classic_anniversary` | `Classic/Constants.lua:173`, `:192` | identical | **1..19** |
| `classic_titan` | `Classic/Constants.lua:173`, `:192` | identical | **1..19** |
| `origin/forever` | `Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:136` and `:155` | `INVSLOT_HEAD 		= 1; INVSLOT_FIRST_EQUIPPED = INVSLOT_HEAD;` … `INVSLOT_LAST_EQUIPPED = INVSLOT_TABARD;` (`INVSLOT_TABARD = 19;` at `:154`) | **1..19** |
| `live` | `Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:153` and `:172` | identical | **1..19** |

Note: `Interface/AddOns/Blizzard_FrameXMLBase/**Classic**/Constants.lua` exists only on
the classic branches; on `origin/forever` and `live` the block lives in the
un-suffixed `Blizzard_FrameXMLBase/Constants.lua` (the file named in the checklist is
ABSENT on those two branches).

The slot table is identical on all five branches (head → tabard): `HEAD 1`, `NECK 2`,
`SHOULDER 3`, `BODY 4`, `CHEST 5`, `WAIST 6`, `LEGS 7`, `FEET 8`, `WRIST 9`, `HAND 10`,
`FINGER1 11`, `FINGER2 12`, `TRINKET1 13`, `TRINKET2 14`, `BACK 15`, `MAINHAND 16`,
`OFFHAND 17`, `RANGED 18`, `TABARD 19`.

**Verdict — the addon's usage is correct on every branch.**
`compat.lua:1161-1162` reads both through `rawget(_G, …)` and refuses to answer unless
both are numbers (`compat.lua:1163-1168` → nil = unknown, never false). The 1..19 range
assumption in `compat.lua:1148-1156` and in `classes/druid.lua:1955-1956` is confirmed on
all five branches, and the citations already in `compat.lua:1151-1153` match the table
above exactly. No gate needed.

---

## 2. Verdict summary per API

| # | API | `classic_era` | `classic_anniversary` | `classic_titan` | `origin/forever` | `live` | addon's usage |
|---|---|---|---|---|---|---|---|
| 1 | global `IsSpellKnown` | present (2 args/1 bool) | present | present | present | present | **correct everywhere** |
| 5 | `loadDeprecationFallbacks` gate | present | present | present | present | present | **correct everywhere** |
| 6 | `C_SpellBook.IsSpellKnown` | documented `:82` | `:82` | `:82` | `:738` | `:684` | **correct everywhere** |
| 7 | `C_SpellBook.IsSpellKnownOrInSpellBook` | documented `:98` | `:98` | `:98` | `:755` | `:701` | **correct everywhere** (loosest probe; only reached when the first two decline) |
| 8 | global `UnitAura` | present, arity 3 | present, arity 3 | present, arity 3 | present in the tree but **classic-gated** → absent on the camelot client | present in the tree but **classic-gated** → absent on Retail | **correct everywhere** (`C_UnitAuras` path answers on Forever/Retail) |
| 9 | `C_UnitAuras.GetAuraDataByIndex` | present | present | present | present | present | **correct everywhere** (10 fields read, field-for-field) |
| 10 | `GetTotemInfo` | 7 returns | 7 | 7 | 7 (+secret) | 7 (+secret) | **correct everywhere** |
| 11/12 | totem slot constants | `Classic/Constants.lua:286-289` | same | same | `Constants.lua:226-229` (**mainline-gated** → not defined on the camelot client) | `Constants.lua:241-244` | **correct everywhere** (not read at runtime; the numbers are hard-coded) |
| 13 | `GetSpellBaseCooldown` | absent from the tree | absent | absent | absent | absent | **correct everywhere** (degrades to `(0, 0)`) |
| 14 | `GetSpellPowerCost` | present (global + `C_Spell`) | present | present | present | present | **correct everywhere** (one array return; consumers read `[1].cost` / the type-matched entry) |
| 15 | `GetSpellCooldown` | global 2-arg form | global 2-arg | global 2-arg | global 2-arg + `C_Spell` 1-arg | `C_Spell` 1-arg only | **correct everywhere** (the addon uses the 1-arg form) |
| 16 | `C_Spell.GetSpellInfo` | present, `SpellInfo` struct | present | present | present | present | **correct everywhere** (`originalIconID`, `castTime` mapped) |
| 17 | `C_EventUtils.IsEventValid` | present | present | present | present | present | **correct everywhere** |
| 18 | `C_Item.GetItemInfo` | positions 6/7 = `itemType`/`itemSubType` | same | same | same | same | **correct**, naming fixed (§4.3) |
| 19 | `INVSLOT_FIRST/LAST_EQUIPPED` | 1..19 | 1..19 | 1..19 | 1..19 | 1..19 | **correct everywhere** |

**No API in the checklist needs a gate on any branch.** Two need a *documented* nuance
that is not a behaviour change:

* `UnitAura` (check 8) is absent on Retail and on the WoW Forever client — the addon
  already answers through `C_UnitAuras` there. Nothing to do; the compat comment should
  keep saying the global is the classic path and `C_UnitAuras` the modern one.
* The totem slot constants (checks 11/12) are not defined on the WoW Forever client
  (mainline-gated file, camelot game type loads `Camelot/Constants.lua`). The addon does
  not read them, so nothing to do — but the corrected comment must say so, otherwise a
  future reader will assume the globals exist there.

---

## 3. What the addon should do where a branch differs from `classic_era`

| difference | addon's action |
|---|---|
| `UnitAura` global absent on Forever/Retail (classic-gated shim) | **None** — `compat.lua:503` already answers via `C_UnitAuras.GetAuraDataByIndex`, which is documented on all five branches with the identical field set. Keep the `if UnitAura … elseif C_UnitAuras … else …` order. |
| `GetTotemInfo` slot is **secret** on Forever/Retail (`SecretWhenTotemSlotSecret`) but not on the classic branches | **None** — `compat.lua:1242-1246` already secret-checks all seven values and degrades the whole entry to nil. The comment's "On Mainline-code clients the slot can be secret" is accurate (the annotation is on `origin/forever` and `live`, absent on the three classic branches). |
| `GetSpellBaseCooldown` absent from every branch's tree | **None** — `compat.lua:357-360` degrades to `(0, 0)` and the callers already treat a non-positive value as "no value". |
| `C_Item.GetItemInfo` (preferred probe) vs the classic global `GetItemInfo` (fallback) name positions 6/7 differently | **Fix the naming, keep the behaviour** — done in §4.3: one documented contract (`item_type`, `item_sub_type`). |
| Totem slot constants not defined on the WoW Forever client | **None at runtime** (hard-coded numbers) — but the citation is corrected to the per-branch truth, including the load-gate caveat. |

Nothing here is "file it" material: no branch of the shipped matrix needs a new gate.

---

## 4. The re-audit's three findings — verified status

### 4.1 L-2 — the totem-slot citation in `compat.lua` — **CONFIRMED, corrected**

The re-audit was **right** about this one. The comment at `compat.lua:1218` cited
`Blizzard_FrameXMLBase/Constants.lua:239-244` for the totem slot map. Verified truth:

* the classic-line file is `Interface/AddOns/Blizzard_FrameXMLBase/**Classic**/Constants.lua`
  (the un-suffixed `Blizzard_FrameXMLBase/Constants.lua` does not exist on the classic
  branches at all — the classic trees ship `Cata/`, `Classic/`, `Mists/`, `Shared/`,
  `TBC/`, `Vanilla/`, `Wrath/` sub-directories);
* the block is **lines 286-289** on `classic_era`, `classic_anniversary` and
  `classic_titan`;
* on `origin/forever` the same four lines are at `Constants.lua:226-229`, and on `live`
  at `Constants.lua:241-244`.

Corrected in `compat.lua` with the per-branch citations and the load-gate caveat.

### 4.2 L-3 — the `bench/compat_m3_contract_2026-10-20.md` §5 claim — **REFUTED, re-cut with verified evidence**

The re-audit asserted two things:

1. *"on `classic_era` that file carries **no** `IsSpellKnown` entry"* — **FALSE.**
   `Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua:82` on
   `classic_era` reads `Name = "IsSpellKnown",` (block `:81-96`, returning `isKnown:bool`
   at `:94`). The bench file's citation `classic_era (SpellBookDocumentation.lua:82)` was
   **exactly right**.
2. *"the string `loadDeprecationFallbacks` appears nowhere in the tree"* — **FALSE.**
   It occurs in 33 files on `classic_era` (33 / 33 / 31 on the other branches, 40 on
   `live`), including `Blizzard_DeprecatedSpellBook/Deprecated_SpellBook.lua:4` itself.
   The bench file's citation `:4-6` was **exactly right**.

Both premises are the signature of an AST-pattern search that could not see a **string
literal inside a table constructor** (`Name = "IsSpellKnown",`) or a string inside a call
argument (`GetCVarBool("loadDeprecationFallbacks")`). The re-audit ran
`ast_grep_search` over the checked-out `classic_era` tree; both symbols are present there
(the working tree matches the branch — `git diff classic_era -- <file>` is empty).

The bench file's §5 claim is therefore **kept**, re-cut with the per-branch evidence and a
dated correction note that records the refutation and the two additional facts the re-audit
did establish: `IsSpellKnownOrInSpellBook` **is** present on `classic_era` (`:98`), and
the `loadDeprecationFallbacks` gate is on **all five** branches (not four).

### 4.3 L-4 — the `GetItemInfo` label defect in `compat.lua` — **CONFIRMED, fixed**

The re-audit was **right**: `compat.lua`'s wrapper named its 6th/7th returns
`class, subclass` (`compat.lua:1288`, `:1303`, `:1306`), which is the classic global's
naming, while the **preferred** probe (`C_Item.GetItemInfo`, `compat.lua:1264-1266`)
returns `itemType` / `itemSubType` at those positions on **every** branch
(`ItemDocumentation.lua:409-410` classic, `:643-644` forever, `:621-622` live;
`Blizzard_ItemButton/Shared/ItemButtonTemplate.lua:187` on all five branches).

The behaviour was already correct — position 7 is the item's subtype string in both
shapes (the repo's own pins already assert the equivalence:
`tests/secret_guard_state.lua:1546-1547`, "itemType lands at the class position",
"itemSubType lands at the subclass position") — but the names were not honest about
which probe answered, and the classic global's own naming is not citable from the
reference tree at all.

Fix: **one documented contract**, applied to both shapes and to the table-shaped read —
`api.GetItemInfo(item)` returns `name, link, quality, level, min_level, item_type,
item_sub_type`, where position 6 is the item's **type** string and position 7 the item's
**subtype** string, whichever probe answered. The locals are renamed to match, the
contract is stated in the file, and the rogue's `item_subclass` helper is renamed to
match. **No value changes** — the rename is label-only, and the pins are re-cut to prove
it.

---

## 5. Proof

| Proof | Result |
|---|---|
| `bash tests/run.sh` (whole harness) | **41 steps, 0 failed**; luacheck **2 warnings / 0 errors** in 83 files (the floor, unchanged) |
| `tests/secret_guard_state.lua` | **PASS, 433 checks** (was 410 before this lane) |
| Behavioural equivalence, old-locals vs. current `compat.lua` (`/tmp/opencode/mut/equiv.lua`) | **PASS, 15 checks, 0 failed** — 3 probe shapes (classic global multi-return, `C_Item` multi-return, table-shaped read) × 3 items (a reading, an unknown, a throwing probe): the returned tuple is **identical** in every case, and the unknown/throwing degrades still report nil. The L-4 change is label-only. |
| Mutation proofs (`/tmp/opencode/mut/run.sh`, on copies) | **14/14 killed** (baseline passes first) |

The 14 mutations (each must make `tests/secret_guard_state.lua` fail):

| # | mutation | killed by |
|---|---|---|
| m1 | the wrapper's locals go back to `class, subclass` | the behavioural pin ("the item type is the 6th return") |
| m2 | the wrapper returns the old `class, subclass` locals | the same behavioural pin |
| m3 | the contract comment loses the normalised names | the comment pin ("the comment names the 6th return item_type") |
| m4 | the contract comment loses the SUBTYPE statement | the comment pin ("the comment says position 7 is the item's subtype") |
| m5 | the `C_Item` field names are dropped from the comment | the comment pin ("the comment records the C_Item probe's own field names") |
| m6 | the rogue's `item_subclass` helper goes back to `class, subclass` | the rogue-shape pin |
| m7 | the wrapper stops secret-checking the 6th return | the behavioural pin ("item info secret item type") |
| m8 | the contract comment loses the `item_sub_type` name | the comment pin ("the comment names the 7th return item_sub_type") |
| m9 | the wrong totem citation (`Constants.lua:239-244`) comes back | the L-2 classic-line pin |
| m10 | the classic-line totem citation loses the `Classic/` path | the L-2 classic-line pin |
| m11 | the forever totem citation is wrong (`:236-239`) | the L-2 forever pin |
| m12 | the live totem citation is wrong (`:241-245`) | the L-2 live pin |
| m13 | the comment stops saying the slot numbers are hard-coded | the L-2 "hard-coded, not read" pin |

Reference repo: **read-only**. `git show <branch>:<path>` and `git grep <branch>` only —
no checkout, no branch switch, no write to `/home/sam/wow-ui-source`. The checked-out
branch (`classic_era`) was left untouched.

### 5.1 A note on one noisy harness reading

The **first** harness run of this lane reported `luacheck . (Total: 7 warnings / 0
errors in 83 files)` while every test step passed. Nothing in the tree changed between
that run and the next one, and three consecutive direct `luacheck .` runs plus two full
`tests/run.sh` runs then reported the standing **2 warnings / 0 errors** floor. The most
likely cause is a parallel lane editing a file inside the checked tree during that
window (the workshop runs several lanes at once) — the same crossfire the `compat-m3`
desk journal recorded. The tree as it stands reads **2/0**, and the two warnings are the
pre-existing ones (`compat.lua:36` unused `addon_name`, `main.lua:81` `table.pack`).
Recorded here rather than smoothed over, because a fluctuating lint count is exactly the
thing the floor exists to catch.

