# WoW Forever HUD — cooldown / GCD / secret API contract (2026-11-08)

Desk: `desks/forever-hud-api` (read-only research lane; task t1 of the
`swedge-forever-hud` team). Client: WoW Forever / Camelot **1.60.1 (70790)**, branch
`origin/forever` at commit **`eac30af597e5aaa43a60f6675ef5fdcea100375f`**
(`git -C /home/sam/wow-ui-source log -1 origin/forever` → `2026-11-04 1.60.1 (70790)`;
`version.txt` = `1.60.1.70790`).

Every client claim is cited `origin/forever:<path>:<line>`; every addon claim is cited
`<file>:<line>` in the tree at write time (`hud.lua`, `compat.lua`,
`LibGlobalCooldown.lua`, `diag.lua`, `nextaction_ui.lua`, `classes/*`). Line numbers were
re-read before writing; re-read again before editing (parallel lanes are moving).

**No web search was used. No product file, test, TOC, doc or git state was modified.**
Runtime-only facts are marked **UNCONFIRMED** with the exact `/run` probe that closes
them (§10, §11).

---

## 0. Supersedes / corrects

- **`bench/secret_api_matrix_2026-11-06.md:156` (and `bench/secret_hud_fix_2026-11-06.md:17`)
  are WRONG in one conclusion** and this report supersedes them:
  > "`CooldownFrame:SetCooldown` / … / `SetCooldownFromDurationObject` | `AllowedWhenUntainted`
  > … | **NO** | … The HUD swipe cannot be driven from a restricted read"

  Two facts were conflated. `AllowedWhenUntainted` constrains **secret arguments**, not the
  caller's taint (§4.1), and `SetCooldownFromDurationObject` carries **no
  `SecretArgumentsAddAspect`** and takes a **non-secret opaque handle** — it is precisely
  the sanctioned path for a tainted addon to render a secret cooldown. The *numeric*
  `SetCooldown(start, duration)` path is the one that cannot be fed a restricted read.
  The corrected matrix entry is §4.3 and §6/§9. Everything else in that report stands;
  its V8 probe is replaced by §10 probe P4.
- `bench/secret_api_matrix_2026-11-06.md:121` (item cooldown "fourth return") is refined
  by §7: on this client the fourth return of `GetInventoryItemCooldown` is `isOnGCD`
  (`origin/forever:…/Blizzard_CooldownViewer/CooldownViewer.lua:1017,1021`), **not** a
  restricted flag — `compat.lua:1565-1584` currently reads it as `restricted`.

---

## 1. Scope and method

- Read in full on `origin/forever`: `SecretPredicatesDocumentation.lua`,
  `SecretPredicateAPIDocumentation.lua`, `SecretWrapperConstantsDocumentation.lua`,
  `SecretAspectConstantsDocumentation.lua`, `SpellDocumentation.lua` (cooldown block),
  `ActionBarFrameDocumentation.lua` (cooldown block), `FrameAPICooldownDocumentation.lua`,
  `LuaDurationObjectAPIDocumentation.lua`, `DurationTextBindingObjectAPIDocumentation.lua`,
  `DurationTextBindingSharedDocumentation.lua`, `DurationUtilDocumentation.lua`,
  `StringUtilDocumentation.lua`, `SecondsFormatterAPIDocumentation.lua`,
  `NumericFormatterAPIDocumentation.lua`, `CurveUtilDocumentation.lua`,
  `SimpleFontStringAPIDocumentation.lua`, `SimpleStatusBarAPIDocumentation.lua`,
  `SimpleFrameAPIDocumentation.lua`, `SimpleFrameScriptObjectAPIDocumentation.lua`,
  `SimpleRegionAPIDocumentation.lua`, `SimpleTextureBaseAPIDocumentation.lua`,
  `FrameScriptDocumentation.lua`, `SpellSharedDocumentation.lua`,
  `AuraContainerUtilDocumentation.lua`, `ItemDocumentation.lua`,
  `ContainerDocumentation.lua`, `UnitAuraDocumentation.lua`.
- Read for call-site proof: `Blizzard_AuraContainer/Blizzard_AuraButton.lua`,
  `Blizzard_CustomAuraButton.lua`, `Blizzard_AuraContainerGroups.lua`,
  `Blizzard_AuraContainerShared.lua`, `Blizzard_CooldownViewer/CooldownViewer.lua`,
  `Blizzard_CooldownViewer/CooldownViewerSecure.lua`,
  `Blizzard_ActionBar/Shared/ActionButton.lua`,
  `Blizzard_UnitFrame/Shared/UnitFrameUtil.lua`,
  `Blizzard_EnvironmentCleanup/Mainline/EnvironmentCleanup.lua` (+ its TOC),
  `Blizzard_Deprecated/11_0_0_SpellBookAPITransitionGuide.lua`.
- Enumerated **every** generated API returning `LuaDurationObject` in the whole branch
  (`git grep -n "LuaDurationObject" origin/forever -- Interface/AddOns/Blizzard_APIDocumentationGenerated`):
  ActionBar ×3, DurationUtil ×1, EncounterTimeline ×1, FrameAPICooldown ×1,
  LossOfControl ×1, PvpInfo ×1, SimpleStatusBar ×2, SpellBook ×3, SpellDocumentation ×3,
  Totem ×1, UnitAura ×1, UnitDocumentation ×3. **None is an item/inventory cooldown**
  (§7).
- Prior art read (secondary, admitted only as a working pattern, never as client proof):
  `/home/sam/SuperSwingTimer-WoW/SuperSwingTimer_Forever.lua:755-789` (duration colour
  curve), `…:897-917` (`frame:SetDurationCooldown`), and its `bench/` documents. Its
  statements are quoted as *prior art* and are not used to prove a client rule.

---

## 2. Restriction states and predicates (question A)

### 2.1 The annotation text, verbatim

`origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua:89-93`

```lua
		{
			Name = "SecretWhenCooldownsRestricted",
			Type = "Secret",
			Documentation = { "Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual spells may be flagged as never or always secret, which takes priority over restrictions." },
		},
```

Three things follow, and all three matter to the operator's phrasing ("cooldowns in
combat/dungeons"):

1. The four named states are **combat, encounter, challenge mode, PvP match**. Note this is
   *not* the map-based predicate: `SecretOnRestrictedMaps` (`:69-73`) is the one worded
   "when the player is on an addon-restricted map such as a dungeon or raid", and it is
   **not** attached to the cooldown APIs (§3). A dungeon restricts cooldowns through the
   *combat* or *encounter* state being active, not through map identity.
   Which of the four states the Forever client actually raises is client-only → **UNCONFIRMED
   (U1)**.
2. Per-spell flags **override** the restriction state in both directions (never-secret and
   always-secret). The query surface is `C_Secrets` (§2.2).
3. The annotation is on the *function/event*, and the secrecy lands on **returned values**.

### 2.2 `C_Secrets` predicates relevant to a HUD

`origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua`
(namespace `C_Secrets`, `:1-8`). Every argument is a plain identifier, every answer is a
plain `bool` (`SecretArguments = "AllowedWhenUntainted"` on the ones that take an argument;
no `ConditionalSecret`/`NeverSecret` marker is needed because none of them is itself
guarded by a `SecretWhen*` predicate — the **answers are plain and safe to branch on**).

| Function | line | argument shape | answer |
|---|---|---|---|
| `C_Secrets.HasSecretRestrictions()` | `:92-101` | none | "Returns true if this client build has secret value restrictions enabled. If false, all APIs that are tagged as potentially returning secrets will never do so." (`:95`) |
| `C_Secrets.ShouldCooldownsBeSecret()` | `:128-137` | none | "Returns true if queries for cooldown data will generally produce secret values." (`:131`) |
| `C_Secrets.ShouldSpellCooldownBeSecret(spellIdentifier)` | `:171-186` | `SpellIdentifier` (id, name, name(subtext) or link) | "Returns true if a given spell identifier will produce secret values for cooldowns if queried." (`:175`) |
| `C_Secrets.ShouldActionCooldownBeSecret(actionID)` | `:102-117` | `luaIndex` | "…if a given action bar slot ID will produce secret values for cooldowns if queried." (`:106`) |
| `C_Secrets.ShouldSpellBookItemCooldownBeSecret(slotIndex, spellBank)` | `:154-170` | `luaIndex`, `SpellBookSpellBank` | "…if a given spellbook item will produce secret values for cooldowns if queried." (`:158`) |
| `C_Secrets.GetSpellCooldownSecrecy(spellIdentifier)` | `:76-91` | `SpellIdentifier` | `SecrecyLevel` — "Queries the base secrecy for a spell if queried as a cooldown." (`:80`) |
| `C_Secrets.ShouldAurasBeSecret()` | `:118-127` | none | "Returns true if queries for aura data will generally produce secret values." (`:121`) |
| `C_Secrets.ShouldSpellAuraBeSecret(spellIdentifier)` | `:138-153` | `SpellIdentifier` | "…if a given spell identifier would, if applied as an aura, produce secret values when queried." (`:142`) |

`SecrecyLevel` (`origin/forever:…/SecretWrapperConstantsDocumentation.lua:5-17`):
`NeverSecret = 0` ("Will never yield secret values when queried."), `AlwaysSecret = 1`
("Will always yield secret values when queried."), `ContextuallySecret = 2` ("May yield
secret values when queried depending upon factors such as addon restriction states, unit
disposition, etc.").

**Consequence for the HUD:** `GetSpellCooldownSecrecy(id)` distinguishes the per-spell
`NeverSecret`/`AlwaysSecret` override from `ContextuallySecret`; `ShouldSpellCooldownBeSecret(id)`
is the composite "is this spell's cooldown secret *right now*" answer. Both are plain
booleans/enums, so the HUD may **choose its face** with them without any secret risk. There
is **no** item-cooldown predicate in the list — §7.

The addon already surfaces the build-level switches: `diag.lua:754-789` prints
`secrets api=yes restrictions= cd= aura= power= stats= cast=`
(`SECRET_PROBES` = `HasSecretRestrictions`, `ShouldCooldownsBeSecret`, `ShouldAurasBeSecret`,
`ShouldUnitPowerBeSecret`, `ShouldUnitStatsBeSecret`, `ShouldUnitSpellCastingBeSecret`).

### 2.3 The practical moment

| API | return shape | secret when |
|---|---|---|
| `C_Spell.GetSpellCooldown` | `SpellCooldownInfo` table | `SecretWhenCooldownsRestricted` (`SpellDocumentation.lua:312`): `startTime`, `duration`, `modRate`, `activeCategory`, `timeUntilEndOfStartRecovery` can be secret |
| `C_Spell.GetSpellCooldownDuration` | `LuaDurationObject` | **never a secret value**; its *values* may be secret (probe `HasSecretValues()`) |
| `C_ActionBar.GetActionCooldown` | `SpellCooldownInfo` | `SecretWhenCooldownsRestricted` (`ActionBarFrameDocumentation.lua:167`) |
| `C_Item.GetItemCooldown`, `C_Container.GetItemCooldown`, `C_Container.GetContainerItemCooldown`, `GetInventoryItemCooldown` | 3–4 plain numbers | **no `SecretWhen*` predicate anywhere** (§7) |

Field-level: inside `SpellCooldownInfo`
(`origin/forever:…/SpellSharedDocumentation.lua:18-32`) only `isEnabled` (`:25`), `isActive`
(`:26`) and `isOnGCD` (`:30`) carry `NeverSecret = true`; `startTime` (`:23`), `duration`
(`:24`) and `modRate` (`:27`) carry no marker, i.e. they are the fields the predicate makes
secret. Inside `SpellChargeInfo` (`:5-17`) only `maxCharges` (`:11`) and `isActive` (`:15`)
are `NeverSecret`.

---

## 3. Cooldown read matrix (question A.3)

All rows are `origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/…`.

| API | annotation (verbatim) | returns | secret moment / readable substitute |
|---|---|---|---|
| `C_Spell.GetSpellCooldown(spellIdentifier)` `SpellDocumentation.lua:308-325` | `:312 SecretWhenCooldownsRestricted = true`; `:313 SecretArguments = "AllowedWhenTainted"`; `:311 MayReturnNothing = true` | `spellCooldownInfo` (`SpellCooldownInfo`) | restricted states ⇒ `startTime`/`duration`/`modRate` secret; `isEnabled`/`isActive`/`isOnGCD` stay readable (`SpellSharedDocumentation.lua:25,26,30`) |
| `C_Spell.GetSpellCooldownDuration(spellIdentifier, ignoreGCD = false)` `:326-343` | **no** `SecretWhen*`; `:330 SecretArguments = "AllowedWhenTainted"`; `:336 { Name = "ignoreGCD", Type = "bool", Nilable = false, Default = false }` | `duration` = `LuaDurationObject` (`:341`) | **the readable cooldown source while restricted** — the object is never a secret value; its values may be (§4) |
| `C_Spell.GetSpellChargeDuration(spellIdentifier)` `:273-289` | no `SecretWhen*`; `:277 SecretArguments = "AllowedWhenTainted"` | `LuaDurationObject` | readable recharge duration object (charges) |
| `C_Spell.GetSpellCharges(spellIdentifier)` `:290-307` | `:294 SecretWhenCooldownsRestricted = true` | `SpellChargeInfo` | `currentCharges`/`cooldownStartTime`/`cooldownDuration` may be secret; `maxCharges`/`isActive` readable |
| `C_Spell.GetSpellLossOfControlCooldownDuration(spellIdentifier)` `:466-482` | no `SecretWhen*`; `:470 SecretArguments = "AllowedWhenTainted"` | `LuaDurationObject` | readable LoC duration object (contrast `…Info` at `:483-…`, `:487 SecretWhenCooldownsRestricted = true`) |
| `C_ActionBar.GetActionCooldown(actionID)` `ActionBarFrameDocumentation.lua:163-179` | `:167 SecretWhenCooldownsRestricted = true`; `:168 SecretArguments = "AllowedWhenUntainted"`; `:166 RequiresValidActionSlot` | `SpellCooldownInfo` | same field split; the action id itself must not be a secret value from tainted code |
| `C_ActionBar.GetActionCooldownDuration(actionID, ignoreGCD = false)` `:180-197` | no `SecretWhen*`; `:184 SecretArguments = "AllowedWhenUntainted"`; `:190 ignoreGCD` default false | `LuaDurationObject` | readable action cooldown object. **The `AllowedWhenUntainted` vs `AllowedWhenTainted` difference is only about secret *arguments*** (§4.1) |
| `C_ActionBar.GetActionChargeDuration(actionID)` `:129-145` | no `SecretWhen*` | `LuaDurationObject` | readable |
| `C_ActionBar.GetActionLossOfControlCooldownDuration(actionID)` `:218-234` | no `SecretWhen*` | `LuaDurationObject` | readable |
| `C_Item.GetItemCooldown(itemInfo)` `ItemDocumentation.lua:433-449` | no `SecretWhen*`; `:436 SecretArguments = "AllowedWhenUntainted"` | `startTimeSeconds, durationSeconds, enableCooldownTimer` | numeric only, no duration object (§7) |
| `C_Container.GetItemCooldown(itemID)` `ContainerDocumentation.lua:336-353` | no `SecretWhen*` | `startTime, duration, enable` | numeric only |
| `C_Container.GetContainerItemCooldown(bag, slot)` `:121-138` | no `SecretWhen*` | `startTime, duration, enable` | numeric only |
| `GetInventoryItemCooldown(unit, slot)` | **not in the generated docs at all** (grep of the whole generated folder for `InventoryItem` returns only `TooltipInfo.GetInventoryItem*`) | Blizzard's own call site takes **four** values, the 4th being `isOnGCD` — `CooldownViewer.lua:1017` + `:1021` | numeric only; see §7 for the contract fix |

**Addon-side note (the classic global).** `compat.lua:345` captures `GetSpellCooldown` and
prefers it over `C_Spell.GetSpellCooldown`. On Mainline-code clients the deprecated global
is documented to return the **new table shape**, not four numbers:
`origin/forever:…/Blizzard_Deprecated/11_0_0_SpellBookAPITransitionGuide.lua:52-54` —
`"-- Both return new SpellCooldownInfo table (see SpellSharedDocumentation.lua)"` /
`GetSpellCooldown(spellID/name) = C_Spell.GetSpellCooldown(spellIdentifier)`. No Lua
definition of that global exists in the branch, so its presence is a client (or CVar)
fact → **UNCONFIRMED (U2)**. If it is present, `compat.lua:429-442` stores the *table* in
`start_time` and sets `readable = true`, and `compat.lua:459-461` then **clears a
`restricted` verdict reached by the `C_Spell` branch** — i.e. a restricted read can be
reported as readable zeros (READY-ON-UNKNOWN, the SEC-6 class), and a table can reach a
consumer that uses the first return without a duration guard (e.g.
`classes/paladin.lua:1321-1323`, `classes/druid.lua:3372-3376`). Exact runtime shape of the
global is probe P2 (§10).

---

## 4. Duration-object pass-through verdict (question B.1/B.2 — the core)

### 4.1 What `SecretArguments` means (documented prose, not inference)

The engine check behind `SecretArguments = "AllowedWhenUntainted"` is
`canaccessallvalues` — `origin/forever:…/FrameScriptDocumentation.lua:19-35`:
"Returns true if the immediate calling function has appropriate permissions to access and
operate on all supplied values." Blizzard states the resulting rule in prose at
`origin/forever:Interface/AddOns/Blizzard_UnitFrame/Shared/UnitFrameUtil.lua:484-488`:

```
-- Returns possibly-secret roleIconTexture/showRoleIcon for callers that draw the role icon themselves. options may set
-- displayRoleIcon, displayRaidRoleIcon, displayVehicleRoleIcon, iconSize, and a textureMap keyed by
-- VEHICLE/MAINTANK/MAINASSIST/TANK/HEALER/DAMAGER, whose values may be either an atlas name or a plain texture path/file ID.
-- Tainted callers must apply showRoleIcon with SetAlphaFromBoolean; SetShown does not accept secret arguments from tainted execution.
```

`SetShown` is `SecretArguments = "AllowedWhenUntainted"` (`SimpleFrameAPIDocumentation.lua:1483-1494`)
and `SetAlphaFromBoolean` is `AllowedWhenTainted` (`:1144-1156`). The sentence is therefore
explicit: **`AllowedWhenUntainted` refuses a *secret argument* from tainted execution — it
does not refuse a call whose argument is plain.** A plain (non-secret) argument is legal
from a tainted addon on every one of these functions. (Corroborating code:
`origin/forever:…/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:457-473` — "if the
tooltip data function doesn't accept secrets from tainted callers, this call will error".)

Corollary for the ARC: a *secret* number from a restricted read must never be handed to an
`AllowedWhenUntainted` argument; a *plain* number, string, bool, table or **opaque
non-secret duration object** may be.

### 4.2 The duration object is a non-secret handle; its values may be secret

| Evidence | citation |
|---|---|
| `GetSpellCooldownDuration` carries **no** `SecretWhen*` predicate, so its return is never a secret value | `SpellDocumentation.lua:326-343` (compare `GetSpellCooldown` at `:312`) |
| The object exposes its own secrecy probe: `HasSecretValues` — "Returns true if the duration has been configured with any secret values." and `ReturnsNeverSecret = true` | `LuaDurationObjectAPIDocumentation.lua:350-364` (`:353` the marker, `:354` the text) |
| `Copy` is `ReturnsNeverSecret = true` ("Returns a copy of this duration object.") | `:21-35` |
| `SetToDefaults` — "Resets all state on the duration, and clears the secret values flag." | `:469-477` |
| A *derived* value is declared conditionally secret: `DurationTextBinding:GetFormattedText` returns `{ Name = "text", Type = "string", …, ConditionalSecret = true }` | `DurationTextBindingObjectAPIDocumentation.lua:133-146` (`:144`) |
| Blizzard builds secret-valued duration objects by hand: `auraDuration:SetTimeFromEnd(secretwrap(auraData.expirationTime, auraData.duration, auraData.timeMod))` | `origin/forever:…/Blizzard_AuraContainer/Blizzard_AuraButton.lua:155-171` (`:167`; comment `:156-160`) |

`secretwrap` — "Converts all supplied values to secret values, preventing most operations on
them from occurring on tainted code paths." (`FrameScriptDocumentation.lua:425-441`, `:430`).

### 4.3 `CooldownFrame:SetCooldownFromDurationObject` — quoted annotations

`origin/forever:…/FrameAPICooldownDocumentation.lua:307-318`

```lua
		{
			Name = "SetCooldownFromDurationObject",
			Type = "Function",
			IsProtectedFunction = true,
			SecretArguments = "AllowedWhenUntainted",

			Arguments =
			{
				{ Name = "duration", Type = "LuaDurationObject", Nilable = false },
				{ Name = "clearIfZero", Type = "bool", Nilable = false, Default = true },
			},
		},
```

Compare the four numeric setters, every one of which **does** carry an aspect annotation:

| Setter | line | `IsProtectedFunction` | `SecretArgumentsAddAspect` | `SecretArguments` |
|---|---|---|---|---|
| `SetCooldown(start, duration, modRate)` | `:280-293` | `true` (`:283`) | `{ Enum.SecretAspect.Cooldown }` (`:284`) | `AllowedWhenUntainted` (`:285`) |
| `SetCooldownDuration(duration, modRate)` | `:294-306` | `true` (`:297`) | `{ Enum.SecretAspect.Cooldown }` (`:298`) | `AllowedWhenUntainted` (`:299`) |
| **`SetCooldownFromDurationObject(duration, clearIfZero)`** | `:307-318` | `true` (`:310`) | **none** | `AllowedWhenUntainted` (`:311`) |
| `SetCooldownFromExpirationTime(expirationTime, duration, modRate)` | `:319-332` | `true` (`:322`) | `{ Enum.SecretAspect.Cooldown }` (`:323`) | `AllowedWhenUntainted` (`:324`) |
| `SetCooldownUNIX(start, duration, modRate)` | `:333-346` | `true` (`:336`) | `{ Enum.SecretAspect.Cooldown }` (`:337`) | `AllowedWhenUntainted` (`:338`) |

The numeric setters accept a **secret argument** (from secure code only) and then *attach
the Cooldown aspect* to the frame — that is how a secret cooldown number is allowed to reach
a frame at all. The duration-object setter has **no aspect at all**, which is exactly what
one expects if no secret argument is ever passed: the confidentiality lives inside the
object and the native code consumes it without exposing a Lua value. `CooldownFrame:Clear()`
is `IsProtectedFunction` and takes no arguments (`:9-17`).

`IsProtectedFunction` is not "addons cannot call": `Frame:SetShown` is
`IsProtectedFunction = true` (`SimpleFrameAPIDocumentation.lua:1486`) and addons call it
routinely, and `CooldownFrame:SetCooldown` is `IsProtectedFunction` and is the single most
used cooldown call in the addon ecosystem. It marks the function as routed through the
secure/protected execution machinery (combat lockdown, forbidden objects) — the *secret*
boundary is `SecretArguments`.

### 4.4 Blizzard's own pass-through call sites

`origin/forever:Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua`

- `:598-605` — `local cooldown = UnpackDisplayElement(self.durationCooldown); … cooldown:SetCooldownFromDurationObject(auraDuration, clearIfZero);` (the frame is an **inbound, addon-supplied** `Cooldown` script object: `:159-168` `SetDurationCooldown` validates it with `AuraContainerUtil.ValidateInboundScriptObject`, then `cooldown:AddSecretAspect(Enum.SecretAspect.Cooldown)` / `…Shown`).
- `:607-613` — `binding:SetDuration(auraDuration); binding:SetEnabled(not auraDuration:IsZero());`
- `:615-623` — `statusBar:SetTimerDuration(auraDuration, interpolation, options.direction);`
- `:399` — `self.durationTextBinding = C_DurationUtil.CreateDurationTextBinding();`
- `:178-213` — the inbound `SetDurationText(fontString, options)`: the addon gives its own
  FontString, Blizzard adds `Text`/`Alpha`/`VertexColor` aspects to it (`:183-185`), then
  `binding:SetFontString(fontString); binding:SetDuration(self:GetAuraDuration());` (`:196-197`).
- `Blizzard_AuraContainerShared.lua:74-99` — the shared `C_StringUtil.CreateSecondsFormatter()`
  with `SetDefaultAbbreviation(OneLetter)`, `SetRounding(Truncate)`,
  `SetCanRoundUpLastUnit(true)`, `SetMinInterval(Seconds)`,
  `SetMaxIntervalCurve(C_CurveUtil.CreateCurve())`, `SetDesiredUnitCount(1)`.

**Verdict (documented surface):** a tainted addon may
`C_Spell.GetSpellCooldownDuration(id, false)` → hold the returned `LuaDurationObject` →
`CooldownFrame:SetCooldownFromDurationObject(obj, true)` and/or
`C_DurationUtil.CreateDurationTextBinding()` + `SetDuration(obj)` + `SetFontString(fs)`.
The object is a plain handle, the values stay native-side, and no Lua number is ever read.
The remaining risk is runtime-only (does the engine accept a *secret-valued* object from a
tainted caller, or does it demand an aspect?) → **UNCONFIRMED (U3)**, probe P4/P5.

### 4.5 Allowed vs forbidden `LuaDurationObject` methods when `HasSecretValues() == true`

Every method of the object is listed in `LuaDurationObjectAPIDocumentation.lua`. The
distinction that matters is *what you do with the answer*:

**Always safe to call from tainted code, on any object (plain results, no secret input):**

| Method | line | why |
|---|---|---|
| `HasSecretValues()` | `:350-364` | `ReturnsNeverSecret = true`; it is the documented pre-check |
| `Copy()` | `:21-35` | `ReturnsNeverSecret = true` |
| `GetClock()` / `GetClockTime()` | `:180-207` | no `SecretArguments`, no secret predicate |
| `GetModRate()` | `:256-269` | no `SecretArguments` |
| `Reset()` | `:411-419` | no arguments; "Resets the duration object to represent a zero duration time span." |
| `SetToDefaults()` | `:469-477` | no arguments; "clears the secret values flag" |
| `IsZero()` | `:397-410` | no `SecretArguments` — *but* its answer is cooldown state; see the caveat below |
| `Assign` / `SetTimeFromEnd` / `SetTimeFromStart` / `SetTimeSpan` / `SetClock` | `:10-20`, `:431-456`, `:457-468`, `:420-430` | callable, but a **secret** argument is refused from tainted code (`AllowedWhenUntainted`), so they are only usable with plain values — i.e. not usable to manufacture a secret-valued object |

**Legal to call, but the answer must not be used in Lua:** every numeric/boolean getter —
`GetRemainingDuration` (`:270-285`), `GetTotalDuration` (`:318-333`), `GetStartTime`
(`:302-317`), `GetEndTime` (`:240-255`), `GetElapsedDuration` (`:208-223`),
`GetElapsedPercent` (`:224-239`), `GetRemainingPercent` (`:286-301`), `HasStarted`
(`:365-380`), `IsActive` (`:381-396`), `HasExpired` (`:334-349`) — each has exactly one
argument, the plain `DurationTimeModifier` enum, so the *call* is not what
`AllowedWhenUntainted` constrains. When the object holds secret values the result is
expected to be secret by the taint rule; the generated doc does **not** carry a
`ConditionalSecret` marker on these returns (the marker exists and is used on
`DurationTextBinding:GetFormattedText`, `:144`), so the true runtime behaviour is
**UNCONFIRMED (U4)** — probe P6. The HUD design must assume the pessimistic case: **a
number from an object whose `HasSecretValues()` is true is not usable in Lua**
(no comparison, arithmetic, concat, table key or formatter).

**Forbidden / unavailable to a tainted addon:**

- Formatting a *secret* number yourself: `NumericFormatter:FormatNumber(number)` is
  `SecretArguments = "AllowedWhenUntainted"` (`NumericFormatterAPIDocumentation.lua:10-25`);
  `SecondsFormatter:Format(seconds, abbreviation)` likewise (`SecondsFormatterAPIDocumentation.lua:106-123`);
  `LuaDurationObject:FormatRemainingDuration(formatter)` likewise
  (`LuaDurationObjectAPIDocumentation.lua:144-161`, `:147 SecretWhenNumericFormatterSecret = true`).
  → **the binding/native side formats, you never do.**
- Declassifying anything: `secretunwrap` — "Unwraps all supplied secrets, converting them
  back to regular values." (`FrameScriptDocumentation.lua:407-424`, `HasRestrictions = true`)
  is **removed from the addon environment**: `secretunwrap = nil;`
  (`origin/forever:Interface/AddOns/Blizzard_EnvironmentCleanup/Mainline/EnvironmentCleanup.lua:280`;
  the addon is loaded for the family via `[Family]\EnvironmentCleanup.lua` at
  `…/Blizzard_EnvironmentCleanup/Blizzard_EnvironmentCleanup.toc:10`). Blizzard's own uses
  of `secretunwrap` are all in secure code (`Blizzard_AuraContainerGroups.lua:207,258`;
  `CooldownViewerSecure.lua:16,20`).
- Passing a secret value into any `AllowedWhenUntainted` argument, `SetShown`, layout
  (`SetPoint`/`SetSize`/`SetScale`), `SetReverse` (`FrameAPICooldownDocumentation.lua:491-500`),
  `SetCountdownFont`/`SetCountdownFormatter`/`SetMinimumCountdownDuration`/
  `SetHideCountdownNumbers` (`:358-377`, `:470-480`, `:460-469`), or the `StatusBar` timer
  setters below — those are fine with **plain** arguments only.

### 4.6 The other two duration-object sinks (for completeness)

| Sink | annotation | citation |
|---|---|---|
| `StatusBar:SetTimerDuration(duration, interpolation, direction)` | `SecretArguments = "AllowedWhenUntainted"`, **no aspect** | `SimpleStatusBarAPIDocumentation.lua:333-344` |
| `StatusBar:GetTimerDuration()` | no annotations | `:148-160` |
| `DurationTextBinding:SetDuration(duration)` | `SecretArguments = "AllowedWhenUntainted"`, no aspect | `DurationTextBindingObjectAPIDocumentation.lua:249-259` |
| `CooldownFrame:SetUseAuraDisplayTime(useAuraDisplayTime)` | `AllowedWhenUntainted` (plain bool) — "Setting this to true will adjust the display logic to stay in sync with aura timers." | `FrameAPICooldownDocumentation.lua:550-560` |

Prior art using the status-bar variant: `/home/sam/SuperSwingTimer-WoW/SuperSwingTimer_Forever.lua:895-897`
(`frame:SetDurationBar(bar, { direction = Enum.StatusBarTimerDirection.RemainingTime })`).

---

## 5. Countdown text verdict (question B.3)

### 5.1 The binding API (all callable from tainted code with plain arguments)

`C_DurationUtil` — `origin/forever:…/DurationUtilDocumentation.lua`:

| Function | line | annotation |
|---|---|---|
| `CreateDuration()` | `:10-19` | none (plain container) |
| `CreateDurationTextBinding()` | `:20-29` | none — "Creates a duration text binding, which automatically updates a font string with formatted text derived from a duration object." |
| `CreateManualClock()` | `:30-39` | none |

`DurationTextBinding` — `origin/forever:…/DurationTextBindingObjectAPIDocumentation.lua`:
`SetFontString` (`:282-292`, `:285 AllowedWhenUntainted`), `SetDuration` (`:249-259`, `:252`),
`SetFormatter` (`:293-303`, `:296`), `SetTextFormat(formatString, components)` (`:316-327`,
`:319`), `SetEnabled` (`:260-270`, `:263`), `Enable`/`Disable` (`:82-90`, `:73-81`, no args),
`UpdateFontString` (`:370-378`, no args), `SetUpdateInterval` (`:348-358`, `:351`),
`SetZeroDurationText` (`:359-369`), `SetExpiredText` (`:271-281`),
`SetTimeModifier` (`:328-338`), `SetTextColorCurve(curve, property)` (`:304-315`, `:307`),
`HasSecretValues()` (`:220-234`, `:223 ReturnsNeverSecret`), `GetFormattedText()`
(`:133-146`, `:144 ConditionalSecret = true`), `GetFormattedTextColor()` (`:147-161`,
`ConditionalSecret` on the colour), `CanFormatText`/`CanUpdateFontString` (`:21-48`),
`GetDuration` (`:91-104`), `Copy` (`:58-72`, `ReturnsNeverSecret`).

Formatter surface: `C_StringUtil.CreateSecondsFormatter()` / `CreateAbbreviatedNumberFormatter()`
/ `CreateNumericRuleFormatter()` — `origin/forever:…/StringUtilDocumentation.lua:10-39`, no
secret annotation on any of the three (creatable from tainted code). `SecondsFormatter`
setters (`SecondsFormatterAPIDocumentation.lua`): `SetDefaultAbbreviation` `:362-373`,
`SetRounding` `:450-461`, `SetCanRoundUpLastUnit` `:340-351`, `SetMinInterval` `:428-439`,
`SetMaxIntervalCurve` `:406-417`, `SetDesiredUnitCount` `:373-384`,
`SetMillisecondsThreshold(threshold)` `:417-427` — "Sets the threshold below which a value
will be formatted as a decimal number of seconds with one place for milliseconds (eg.
'3.4')" — this is exactly the knob that reproduces `HUD.format_time`'s `"%.1f"`-under-5.5s
look (`hud.lua:1231-1236`) without the addon doing any formatting.

Letters: `SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)` is what
Blizzard uses for aura durations (`Blizzard_AuraContainerShared.lua:93`); the HUD's current
face is a bare integer/decimal, which is `SetDesiredUnitCount(1)` + a `Step` interval curve
(`Blizzard_AuraContainerShared.lua:85-98`).

### 5.2 Colour-by-remaining-time without reading the number

`DurationTextBinding:SetTextColorCurve(curve, property)` (`:304-315`) evaluates a
`LuaColorCurveObject` against a duration property. Properties:
`Enum.DurationTextBindingProperty` = `RemainingDuration 0, RemainingPercent 1,
ElapsedDuration 2, ElapsedPercent 3, TotalDuration 4, StartTime 5, EndTime 6`
(`origin/forever:…/DurationTextBindingSharedDocumentation.lua:5-21`). Curve construction is
tainted-callable: `C_CurveUtil.CreateColorCurve()` (`CurveUtilDocumentation.lua:10-19`, no
annotation) and `LuaColorCurveObject:AddPoint(x, color)` (`LuaColorCurveObjectAPIDocumentation.lua:10-21`,
`:13 AllowedWhenUntainted` — plain numbers/colours only). This is the sanctioned way to
implement the HUD's warn colour (`hud.lua:1329-1336`) under secrecy, and the sibling addon
already ships it for its Forever icon row:
`/home/sam/SuperSwingTimer-WoW/SuperSwingTimer_Forever.lua:755-789` (comment at `:757-761`:
"With secret auras that read is illegal, so the client's DurationTextBinding evaluates the
curve against the secret duration internally and only the resulting colour reaches the font
string").

### 5.3 The font-string sink, and its cost

`FontString:SetText(text)` — `SecretArgumentsAddAspect = { Enum.SecretAspect.Text }`,
`SecretArguments = "AllowedWhenTainted"` (`SimpleFontStringAPIDocumentation.lua:663-673`;
`:666-667`). A **secret string** is accepted from tainted code and the Text aspect is
attached. `SetTextToFit` is identical (`:708-718`). `SetFormattedText` takes **one**
`cstring` argument and has the same taint rules (`:538-548`) — the documented signature has
no format/varargs, so `SetFormattedText("%d", secret_number)` is not a thing.

Two consequences the implementer must respect:

1. Once the HUD's countdown FontString receives a secret string, `GetText` returns a secret
   (`:352-365`, `SecretReturnsForAspect = { Enum.SecretAspect.Text }`) and the precondition
   `RequiresFontStringTextAccess` applies — "Guarded APIs reject access for tainted callers
   if the object has the secret Text aspect assigned."
   (`SecretPredicatesDocumentation.lua:21-26`). ⇒ **never read the countdown text back**,
   never use it as a cache key, never compare it.
2. `SetText` can accept the binding's own `GetFormattedText()` (a `ConditionalSecret`
   string, `:144`) — but then the addon owns the update cadence and the value is a secret
   string it cannot inspect. The binding's own font-string update (`Enable()` +
   `SetUpdateInterval`) is strictly better: no Lua value at all.

### 5.4 The CooldownFrame's own countdown numbers

`SetHideCountdownNumbers` (`FrameAPICooldownDocumentation.lua:460-469`), `GetHideCountdownNumbers`
(`:172-184`), `GetCountdownFontString` (`:77-89`), `GetCountdownFormatter` (`:90-102`),
`GetCountdownAbbrevThreshold`/`SetCountdownAbbrevThreshold` (`:63-76`, `:347-357`),
`GetCountdownMillisecondsThreshold`/`SetCountdownMillisecondsThreshold` (`:103-116`, `:378-388`),
`SetCountdownFont` (`:358-367`), `SetCountdownFormatter` (`:368-377`),
`GetMinimumCountdownDuration`/`SetMinimumCountdownDuration` (`:185-197`, `:470-480`) — every
setter is `SecretArguments = "AllowedWhenUntainted"`, so **plain arguments are fine from a
tainted addon**; the frame then renders and abbreviates its numbers natively. The
`SetMinimumCountdownDuration` doc is explicit that the threshold is compared against the
**total** duration, not the remaining one (`:474`), so it cannot reproduce the HUD's
"hide text for short cooldowns / GCD" rule by remaining value.

The HUD already creates `CooldownFrameTemplate` frames (`hud.lua:531`) and already suppresses
native numbers with `SetHideCountdownNumbers(true)` + `noCooldownCount`
(`hud.lua:1284-1292`, `:1300-1305`). Whether native numbers render correctly for a
secret-valued duration object is **UNCONFIRMED (U5)**, probe P7.

---

## 6. GCD verdict and proposed wiring (question B.4)

### 6.1 Does `GetSpellCooldownDuration(probe, false)` carry the GCD?

Documented facts: the second argument is `ignoreGCD`, type `bool`, **default `false`**
(`SpellDocumentation.lua:333-337`; identical shape at
`ActionBarFrameDocumentation.lua:187-191`), and the function "Returns a duration object
describing the active cooldown duration for a spell" (`:331`). With `ignoreGCD = false` the
returned duration therefore describes the cooldown *including* the GCD; with `true` it
describes the spell's own cooldown only. The exact numeric behaviour (does it return
`max(cooldown, gcd)`? a pure GCD duration when the spell has no cooldown? a zero object
when neither is running?) is not stated anywhere in the branch → **UNCONFIRMED (U6)**,
probe P3. Note there are **zero** call sites of `GetSpellCooldownDuration` in the whole
`origin/forever` Lua tree (`git grep` returns only the documentation line), so there is no
Blizzard call site to imitate either.

### 6.2 How the HUD knows the GCD is running without reading a number

`SpellCooldownInfo.isOnGCD` is `NeverSecret = true`
(`origin/forever:…/SpellSharedDocumentation.lua:30`): "Whether or not this spell is
considered to be on the global cooldown, do not trust this field unless responding to a
SPELL_UPDATE_COOLDOWN event." `isActive` (`:26`) and `isEnabled` (`:25`) are `NeverSecret`
too. So:

```lua
-- plain booleans only: no secret read, no arithmetic
local info = C_Spell.GetSpellCooldown(probe_id)          -- info may contain secret fields
local on_gcd = info and info.isOnGCD == true             -- NeverSecret field
local active = info and info.isActive == true            -- NeverSecret field
local dur    = C_Spell.GetSpellCooldownDuration(probe_id, false)  -- opaque handle
icon.cooldown:SetCooldownFromDurationObject(dur, true)   -- native swipe
```

`SPELL_UPDATE_COOLDOWN` is documented with a plain payload (`spellID`, `baseSpellID`,
`category`, `startRecoveryCategory`, `itemID` — `SpellBookDocumentation.lua:927-936`) and is
the event Blizzard tells you to trust `isOnGCD` on; `ACTIONBAR_UPDATE_COOLDOWN` has no
payload (`ActionBarFrameDocumentation.lua:1094-1096`). Neither carries a `SecretWhen*`
annotation, so driving the HUD's repaint from them is legal.

**GCD probe spell.** `st.gcd_probe_spell_id = 29515` on the classic line and **61304** on
Mainline-code clients (`compat.lua:126-133`); `LibGlobalCooldown.lua:58` reads it from
`st`. Whether 61304's cooldown is flagged `NeverSecret` on this client decides whether its
duration object is always plain → **UNCONFIRMED (U7)**, probe
`C_Secrets.GetSpellCooldownSecrecy(61304)`.

### 6.3 What `LibGlobalCooldown` may keep, and what it must stop caching

`LibGlobalCooldown.lua` today:

| Part | line | verdict |
|---|---|---|
| `calculate_expected_spell_gcd` (haste-rating → predicted GCD) | `:100-144` | **keep.** Inputs are guarded: `read_combat_rating_bonus` returns nil on a secret/non-number (`:42-48`), and the cast-time probe comes from `GetSpellInfo` (`:122-124`) whose structure has no secret fields (`SpellDocumentation.lua:1183-1195`). Everything stored (`current_spell_gcd`, `:139`) is a plain number derived from plain inputs. |
| `COMBAT_RATING_UPDATE` → `calculate_expected_spell_gcd` | `:176-191` | keep (the nil-guard at `:182-184` is the contract) |
| `PLAYER_LOGIN` / `UPDATE_SHAPESHIFT_FORM` phys-GCD table | `:193-217`, `:244-258` | keep (constants only) |
| **`poll_gcd` (live GCD detection)** | `:152-171` | **must change.** It reads `api.GetSpellCooldown(gcd_probe_spell_id)` (`:158`) and early-outs on `duration_reported == 0` (`:159-161`). Under restrictions compat reports exactly `0, 0, 0, 0, true` (`compat.lua:471-473`), so the live GCD never arms: `gcd_duration`/`gcd_started`/`gcd_expires` stay nil and `GCD_STARTED` never fires. This is the concrete reason "GCD does not work in combat" on Forever. |
| `UNIT_SPELLCAST_INTERRUPTED` release check | `:235-242` | same read; a restricted read answers 0 and would release the lock — harmless today because the lock never arms, but it must not become the *only* release path once the lock works. |
| cached fields `gcd_duration`, `gcd_started`, `gcd_expires`, `current_spell_gcd`, `current_spell_haste`, `phys_gcd`, `base_spell_gcd` | `:76-86`, `:81-82` | **plain today by construction**; the rule for the new path is in §8.3 |

### 6.4 Proposed GCD wiring (Forever-only, probe-gated)

1. In `compat.lua`, next to the existing cooldown wrappers (additive, no arity change):
   - `api.get_spell_cooldown_duration(spell)` → the `LuaDurationObject` or nil (`pcall`, type
     check on `HasSecretValues`).
   - `api.spell_cooldown_state(spell)` → `on_gcd|active|nil` from the two `NeverSecret`
     fields only.
   - `api.cooldown_secrecy(spell)` → `C_Secrets.ShouldSpellCooldownBeSecret(spell)` when the
     predicate exists, else nil (never a secret).
2. In `LibGlobalCooldown`, keep the prediction path untouched and add an object channel:
   store `lib.gcd_object` (the handle) + `lib.gcd_on_gcd` (plain bool) and fire a new
   callback with the object. Do **not** compute `gcd_expires` from it.
3. In `hud.lua`/`nextaction_ui.lua`, add a `s.duration_object` channel: when present, paint
   with `icon.cooldown:SetCooldownFromDurationObject(obj, true)`; when absent, keep the
   existing numeric path byte-identical (this is the "every other client is byte-identical"
   gate). Repaint on `SPELL_UPDATE_COOLDOWN` / `ACTIONBAR_UPDATE_COOLDOWN` and on an
   `isActive` transition instead of comparing start/duration each tick.
4. GCD text suppression: the HUD currently suppresses text for `duration < GCD_TEXT_HIDE`
   (`hud.lua:1317-1318`) — a readable-number rule. Under an object, gate on
   `s.on_gcd or not active` (plain) and on the binding's own zero/expired text
   (`SetZeroDurationText("")`, `SetExpiredText("")`).

---

## 7. Trinket / item verdict (question B.5)

**There is no duration-object API for item cooldowns on `origin/forever`.** The complete
enumeration of `LuaDurationObject` returners (§1) contains no item, container, bag or
inventory API, and no `C_Item`/`C_Container` cooldown function has a `…Duration` sibling
(`git grep -n "Cooldown" origin/forever -- Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`
→ only `:434 GetItemCooldown`; `ContainerDocumentation.lua` → `:122 GetContainerItemCooldown`,
`:337 GetItemCooldown`, `:669 BagUpdateCooldown`).

**No item-cooldown secrecy predicate either:** `C_Secrets` has no item predicate
(`SecretPredicateAPIDocumentation.lua`, whole file), and none of `C_Item.GetItemCooldown`
(`ItemDocumentation.lua:433-449`), `C_Container.GetItemCooldown`
(`ContainerDocumentation.lua:336-353`), `C_Container.GetContainerItemCooldown`
(`:121-138`) carries a `SecretWhen*` annotation. `GetInventoryItemCooldown` is not in the
generated documentation at all.

**Therefore the legal faces for an equipped on-use trinket are:**

1. readable numeric read (the documented surface carries no secrecy) → the existing numeric
   `SetCooldown(start, duration)` swipe is legal and correct;
2. if a runtime secret ever appears on one of the three numbers → the grey unknown face only
   (no object exists to pass through). `api.is_secret` on each returned value is the only
   available probe.

**Contract correction (the fourth return).** Blizzard's own Forever cooldown display reads
**four** values and names the fourth `isOnGCD`:

`origin/forever:Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua:1013-1045`

```lua
			local startTime, duration, enable, isOnGCD = GetInventoryItemCooldown("player", equipSlot);
			local endTime = startTime + duration;
			self.cooldownIsActive = endTime > timeNow;
			self.cooldownEnabled = enable == 1;
			self.isOnGCD = isOnGCD;
```
(`:1017`, `:1020`, `:1021`; consumed at `CooldownViewer.lua:960-974`
`ShouldDisplaySpellCooldown` → `if spellCooldownInfo.isOnGCD and self:GetEquipSlot() then
return false`). The Camelot `PaperDollFrame` reads three (`…/Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua:2196`),
which is legal Lua — but the four-value shape is the one Blizzard's Forever code depends on.

**The addon currently reads the fourth as `restricted`:**

- `compat.lua:1555-1584` — `api.GetInventoryItemCooldown` returns `start, duration, enabled`
  and a fourth `restricted = true` whenever a value `is_secret`.
- `hud.lua:341-350` (`trinket_has_on_use`) and `hud.lua:418-431` (`trinket_state`) consume
  that fourth as `use_restricted`.

If the client returns `isOnGCD` as the fourth value, `use_restricted == true` whenever the
trinket is on the GCD → the HUD paints the grey unknown face (`hud.lua:427-431`) and skips
the swipe for the whole GCD window. That is a cosmetic/logic defect, not a taint hazard
(the value is a plain bool), and it is independent of whether item cooldowns are ever
secret. Minimal fix: do not overload the fourth return — keep
`start, duration, enabled, is_on_gcd` (documented) and derive secrecy per value with
`api.is_secret` inside the wrapper, reporting it as a fifth/additive return only if the HUD
still needs the tri-state. Probe P8 fixes the arity question.

**`is_item_equipped` / item identity** (`compat.lua:1612-1660`) is unaffected: identity
reads are guarded by `api.is_secret` (`:1538-1541`, `:1549-1552`), and item identities are
not `SecretWhen*`-guarded.

---

## 8. Secret-value cache matrix (question C)

### 8.1 The documented cache rules, and why they are hard

| Rule | Evidence |
|---|---|
| A secret table **key** poisons every access: "Aura frame association maps require that the aura instance ID not be a secret value, as secret keys in tables make all accesses into that table produce secrets." … "We ban the use of secret values as keys in the association map so that attempts to do so immediately hard-error." | `origin/forever:Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerGroups.lua:11-30` (`:12-25`) |
| The secure-side escape hatch is `secretunwrap` + `settablesecurity(…, DisallowSecretKeys)` / `(…, DisallowTaintedAccess)` | `Blizzard_AuraContainerGroups.lua:27-29`; `Blizzard_CooldownViewer/CooldownViewerSecure.lua:3-36` (`:15-21` proxy, `:25-33` "Both tables disallow tainted access to ensure nothing can access our declassified instance IDs") |
| **Addons cannot use that escape hatch:** `secretunwrap = nil` in the environment cleanup, and `CreateSecureDelegate`, `SecureMixin`, `CreateFromSecureMixins`, `loadstring_untainted` are removed too | `…/Blizzard_EnvironmentCleanup/Mainline/EnvironmentCleanup.lua:275-280`; TOC `:10 [Family]\EnvironmentCleanup.lua` |
| `settablesecurity(table, option)` is itself `HasRestrictions = true` + `AllowedWhenUntainted` (`FrameScriptDocumentation.lua:489-501`), options `DisallowTaintedAccess = 0`, `DisallowSecretKeys = 1`, `SecretWrapContents = 2` (`:550-562`) — whether a *tainted* addon may call it is a runtime fact | **UNCONFIRMED (U8)**, probe P9 |
| Scrubbing is available and safe: `scrubsecretvalues(values…)` → "inputs that are secret values replaced by nil values" (`:373-389`); `scrub` additionally drops non-string/number/boolean (`:390-406`); `issecretvalue` (`:286-300`), `issecrettable` (`:269-285`), `canaccessallvalues`/`canaccessvalue`/`canaccesstable`/`canaccesssecrets` (`:19-80`) are all present | same file (none of these names appear in `EnvironmentCleanup.lua`) |
| Copying does not declassify: `securecopy` — "Copied values receive the current execution taint." | `:461-478` (`:466`) |
| Wrapping makes it worse on purpose: `secretwrap` — "…preventing most operations on them from occurring on tainted code paths." | `:425-441` (`:430`) |

**The rule the implementer must test:** *no secret value may enter a plain table (as key
or as value), a string, a comparison, arithmetic or a formatter; a cached entry must be
proven plain before use, or the cache must be cleared.* The proofs available are
`issecretvalue`/`issecrettable` on read-back, `scrubsecretvalues` at write, or — best — a
design in which the cache holds only plain values and opaque handles by construction.

### 8.2 `hud.lua`

| Cache | fields / line | what could be secret | can a later tick read it unchecked? | minimal fix |
|---|---|---|---|---|
| `HUD.known_names` (spell id → name) | `hud.lua:857`, written `:876-882`, used `:874-887` | the **value** comes from `api.GetSpellInfo` (`compat.lua:191-201`) — a `SpellInfo` whose fields carry no secret marker (`SpellDocumentation.lua:1183-1195`) and whose function has no `SecretWhen*`; the **key** is a slot spell id from static tables | safe today; **unsafe the moment a spell id could be secret**: `HUD.known_names[spell] = n` (`:880`) would hard-error on a secret key (`AuraContainerGroups.lua:12-25`) | guard the insert: `if type(spell) == "number" and not api.is_secret(spell)`; the name itself is never used in arithmetic |
| `known_cache` | `hud.lua:940` (weak-keyed by `slot` table), read `:953-956`, written `:958-963` | key = addon slot table (plain); value = bool from `api.is_spell_known_state` (`compat.lua:292-328`, guarded `:318`) | safe — both sides plain | none; keep the `is_secret` guard inside the wrapper |
| `HUD.layout_cache` | `hud.lua:656`, `:1165-1181`, `:1183-1206` | only saved-variable values (`LAYOUT_KEYS`) — user config | safe (no client read enters it) | none. Do not add frame-geometry read-backs (`GetWidth`/`GetPoint` can be secret for secret-anchored frames, `SecretPredicatesDocumentation.lua:74-78`) |
| `HUD.icons[i].cd_start`, `cd_duration`, `cd_reverse`, `cd_key` | `hud.lua:569`, `:1273-1308` | fed from `s.start`/`s.duration`, which compat guarantees plain (`compat.lua:471-473`, `:491-513`) | the compare `math.abs((icon.cd_start or 0) - start) > 0.05` (`:1277`) raises on a secret | **replace the numeric cache with the object**: store `icon.cd_object` (plain handle) + a plain `icon.cd_token` (event/`isActive` generation), and call `SetCooldownFromDurationObject(obj, true)`. Never derive `start`/`duration` from an object |
| `HUD.icons[i].text_value`, `text_color`, `tint`, `desaturated`, `texture_key`, `glowing`, `text_hidden` | `hud.lua:1325-1372`, `:1264-1267`, `:1337-1350` | all derived from plain state or db colours | safe, provided the provider never puts a secret in `s.remaining`/`s.text_remaining`/`s.duration`/`s.start` — the paint re-check covers exactly those four (`hud.lua:1255-1259`) | keep the re-check; extend it if a new numeric state field is added (`s.text_value` is computed locally, so it is plain by construction) |
| `HUD.trinkets[13/14]` — `item`, `buff`, `icd`, `texture`, `icd_expires`, `proc_expires`, `proc_duration` | `hud.lua:204`, `:289-304`, `:316-330`, `:407-419` | `proc_expires`/`proc_duration` come from `api.UnitAura` (`compat.lua:762-833`), which nils any secret field including `spell_id` (`:766`) | safe **only through the wrapper** — a direct `UnitAura` read would put a secret into `t.proc_expires` and the next tick's `s.remaining` compare would raise | keep the wrapper; add the arity/meaning fix of §7 so the fourth return stops masquerading as a secret flag |
| `TRINKET_STATE` / `PREVIEW_STATE` (module-level reused tables) | `hud.lua:238-239`, `:407-434`, `:1393-1430` | the *state* table is the hand-off between provider and paint, so any secret a provider writes lands in a plain table used by later ticks | yes — nothing scrubs on write | contract already states it (`hud.lua:1249-1254`); enforce at the provider boundary in `forever_guide.get_hud_state` and the class providers (keep `inputs_unknown`/`restricted`, never the number) |

### 8.3 `LibGlobalCooldown.lua`

| Cache | line | could be secret? | later-tick read | minimal fix |
|---|---|---|---|---|
| `gcd_duration`, `gcd_started`, `gcd_expires` | `:76-78`, set `:165-167`, cleared `:147-149` | today no: they are only set from `api.GetSpellCooldown`, which returns plain zeros when restricted (`compat.lua:471-473`) and the `== 0` early-out (`:159`) prevents any arithmetic | `:155`, `:236-238` read them after the fact | when the object channel lands, store **the object** (`lib.gcd_object`) and the plain `on_gcd` bool; compute no expiry |
| `current_spell_gcd` | `:83`, `:139` | derived from the guarded haste read (`:104-107`) + `GetSpellInfo` castTime (`:122-124`) → plain | fired to callbacks (`:140-141`) and consumed by bars arithmetic | keep; never feed a secret (a nil haste keeps the previous value — that is the documented degrade) |
| `current_spell_haste` | `:86`, `:186-188` | guarded by `read_combat_rating` (`:34-40`) | compared each `COMBAT_RATING_UPDATE` | keep |
| `phys_gcd`, `base_spell_gcd`, `has_bloodlust`, `has_breath_haste`, `cast_time_1500ms_spell_id`, `current_form` | `:72-91` | constants / class logic | — | none |

### 8.4 `compat.lua` wrappers (the only place a client read becomes plain)

| Wrapper | line | contract today | verdict |
|---|---|---|---|
| `api.GetSpellCooldown(spell, fallback_id)` | `:482-514` | classic four values, or `0,0,0,0,true` when nothing readable | **keeper** — the only issue is the classic-global shape (§3, U2) |
| `api.get_cooldown_remaining(spell, fallback_id)` | `:523-540` | `nil,nil,true` on restricted; type-checks both numbers | **keeper** (this is the shape every guide needs) |
| `api.GetInventoryItemCooldown(slot)` | `:1565-1584` | 4th return = `restricted` | **fix**: 4th return is `isOnGCD` (§7) |
| `api.UnitAura(unit, index, filter)` | `:762-833` | any secret field ⇒ nil entry, index precheck + pcall | **keeper** |
| `api.IsSpellUsable(spell)` | `:563-…` | secret or nil ⇒ unknown (`:570`) | **keeper** (`C_Spell.IsSpellUsable` has no secret predicate at all — `SpellDocumentation.lua:979-995`) |
| `api.GetSpellInfo(spell)` | `:191-201` | raw pass-through of a non-secret structure | keeper; never branch on a field that could later acquire a marker |
| `api.is_spell_known_state(spell_id, fallback_id)` | `:292-328` | `is_secret(known)` guarded (`:318`) | **keeper** |
| `api.is_secret(value)` | `:183-185` | exact `issecretvalue` adapter | **keeper** — use it at every cache-write boundary |
| `read_cooldown_duration_object` | `:368-384` | reads `GetRemainingDuration`/`GetTotalDuration`/`GetStartTime` **only** when `HasSecretValues()` is exactly `false`, all pcall'd | **keeper as the "readable" path**; it is *not* the restricted path — under restriction it correctly declines, and the new object channel is what fills the gap |

---

## 9. Decision table (question D)

Legend: **YES** = callable/usable from a tainted addon with plain arguments; **YES-OBJ** =
callable, and the secret lives inside the opaque object; **NO** = not from tainted code.
Every row whose behaviour depends on the live client is marked UNCONFIRMED with its probe.

| HUD need | API to call | Allowed from tainted? | Secret-safe sink | Cache rule | In-client check |
|---|---|---|---|---|---|
| Ability cooldown swipe (restricted) | `C_Spell.GetSpellCooldownDuration(id, false)` → `CooldownFrame:SetCooldownFromDurationObject(obj, true)` | **YES-OBJ** (object non-secret; setter `AllowedWhenUntainted` only refuses secret *arguments*) | native cooldown frame | store the **handle** (`icon.cd_object`), never `start`/`duration`; re-set on `SPELL_UPDATE_COOLDOWN` + `isActive` flip | P3, P4 |
| Ability cooldown swipe (readable, every other client + Forever out of restriction) | `C_Spell.GetSpellCooldown` → `SetCooldown(start, duration, modRate)` | YES (plain numbers) | numeric frame setter | unchanged (`hud.lua:1269-1308`) — byte-identical on non-Forever | P1/P2 |
| Countdown text | `C_DurationUtil.CreateDurationTextBinding()` + `SetDuration(obj)` + `SetFontString(icon.text)` + `SetFormatter(C_StringUtil.CreateSecondsFormatter())` + `SetUpdateInterval(0.05)` + `Enable()` | **YES** (all setters `AllowedWhenUntainted` with plain args) | the binding updates the font string natively; never `GetFormattedText` | never read the text back; `GetText` returns secret once the Text aspect is attached | P5 |
| Countdown warn colour (< N s) | `C_CurveUtil.CreateColorCurve()` + `AddPoint` + `binding:SetTextColorCurve(curve, Enum.DurationTextBindingProperty.RemainingDuration)` | **YES** | native curve evaluation → font-string colour | keep the curve (plain) global; never derive the colour in Lua | P5 |
| GCD swipe | `C_Spell.GetSpellCooldownDuration(probe, false)` + `isOnGCD`/`isActive` (NeverSecret) for the decision | **YES-OBJ** | cooldown frame / `StatusBar:SetTimerDuration` | store `lib.gcd_object` + plain bool; never `gcd_expires` | P3, P7 |
| GCD text suppression | `binding:SetEnabled(false)` / `text:Hide()` on `on_gcd` (plain bool) | **YES** | n/a (plain call) | no numeric threshold; `SetZeroDurationText("")`/`SetExpiredText("")` | P5 |
| Readable remaining seconds (guides, practice, non-restricted) | `api.get_cooldown_remaining` (compat) | YES | n/a | unchanged | P1 |
| Trinket on-use swipe (readable) | `GetInventoryItemCooldown` 3 numbers → `SetCooldown` | YES | numeric frame setter | numeric cache allowed only while plain; per-value `api.is_secret` | **P8**, P9 |
| Trinket restricted face | none exists — no item duration object | — | grey unknown face (`hud.lua:1355-1359`) | do **not** key on the 4th return | P8 |
| Restricted-unknown face (any slot) | `s.restricted` flag + `SetDesaturated(true)` + `SetVertexColor(…)` | YES (`SimpleTextureBaseAPIDocumentation.lua:416-426` `SetDesaturated`: `AllowedWhenTainted`; `SimpleRegionAPIDocumentation.lua:190-203` `SetVertexColor`) | texture sinks | the flag is a plain bool by construction | P2 |
| Desaturation driven by a possibly-secret bool | `Texture:SetDesaturated(bool)` / `SetAlphaFromBoolean(bool, a, b)` | **YES** (both `AllowedWhenTainted`, aspects `{Desaturation}` / `{Alpha}`) | texture/region | never branch on the secret bool; pass it into the sink | P9 |
| Mana / range tints | `api.IsSpellUsable`, `api.is_target_in_swing_range` → `SetVertexColor` | YES | `SetVertexColor` | plain values only | P1 |
| Proc glow | `LibCustomGlow` (texture churn) on a plain bool | YES | textures | plain only | — |
| Show/hide a region from a secret bool | `SetAlphaFromBoolean` — **not** `SetShown` | YES / **NO** for `SetShown` | alpha | — | P9 |
| Countdown numbers rendered by the frame itself | `SetHideCountdownNumbers(false)` + `SetCountdownFormatter(C_StringUtil.CreateSecondsFormatter())` + `SetMinimumCountdownDuration(ms)` | YES (plain args) | native | — | P7 (UNCONFIRMED) |
| Any layout from a secret | `SetPoint`/`SetSize`/`SetScale` | **NO** (`AllowedWhenUntainted`) | — | layout stays on readable numbers | — |

---

## 10. In-client test checklist (Forever only)

Run in the failing moment (a dungeon pull, in combat, with a spell on cooldown). Each probe
is a single `/run`; record the printed line verbatim in the lane's evidence note. Treat
every `error(...)` from a `pcall` as the answer to that probe, not as a failure of the
HUD.

| # | Probe | Expected if the mechanism works | Closes |
|---|---|---|---|
| P1 | `/run print(C_Secrets and C_Secrets.HasSecretRestrictions(), C_Secrets and C_Secrets.ShouldCooldownsBeSecret())` (and `/st diag` → `secrets … cd=`) | `true true` in a restricted moment | U1 |
| P2 | `/run local t={GetSpellCooldown(75)} print(#t, type(t[1]), type(t[1])=="table" and tostring(t[1].duration) or tostring(t[1]))` | either a table (Mainline shape) or 4 numbers; tells us whether `compat.lua:429-442` is on the table path | U2 |
| P3 | `/run local d=C_Spell.GetSpellCooldownDuration(61304,false) local i=C_Spell.GetSpellCooldown(61304) print(type(d), issecretvalue(d), d:HasSecretValues(), i and i.isOnGCD, i and i.isActive)` — during a GCD, then again idle | object is userdata, `issecretvalue(d)==false`, `HasSecretValues()` reflects restriction, `isOnGCD` true during GCD | U6, U7 |
| P4 | `/run local c=CreateFrame("Cooldown",nil,UIParent,"CooldownFrameTemplate") local d=C_Spell.GetSpellCooldownDuration(20271,false) print(pcall(function() c:SetCooldownFromDurationObject(d,true) end))` — in restricted combat, then move the frame on screen and look at it | `true` (no error) **and** a visible swipe | U3 |
| P5 | `/run local b=C_DurationUtil.CreateDurationTextBinding() local f=UIParent:CreateFontString(nil,"OVERLAY") f:SetPoint("CENTER") b:SetFontString(f) b:SetFormatter(C_StringUtil.CreateSecondsFormatter()) b:SetUpdateInterval(0.05) b:SetDuration(C_Spell.GetSpellCooldownDuration(20271,false)) b:Enable() print(b:HasSecretValues(), pcall(b.GetFormattedText,b))` | a countdown appears/ticks; `HasSecretValues()` answers the restricted state; note whether `GetFormattedText` returns a string or a secret | U3, U5 |
| P6 | `/run local d=C_Spell.GetSpellCooldownDuration(20271,false) print(d:HasSecretValues(), pcall(d.GetRemainingDuration,d), issecretvalue((select(2,pcall(d.GetRemainingDuration,d)))))` | tells us whether the getters return secrets on a secret-valued object (design assumption: yes) | U4 |
| P7 | `/run local c=CreateFrame("Cooldown",nil,UIParent,"CooldownFrameTemplate") c:SetSize(64,64) c:SetPoint("CENTER") c:SetHideCountdownNumbers(false) c:SetCountdownFormatter(C_StringUtil.CreateSecondsFormatter()) local d=C_Spell.GetSpellCooldownDuration(20271,false) print(pcall(function() c:SetCooldownFromDurationObject(d,false) end))` — restricted combat | native numbers render (and are not hidden by other addons) | U5 |
| P8 | `/run local a,b,c,e=GetInventoryItemCooldown("player",13) print(a,b,c,type(e),tostring(e))` — idle, then during the GCD right after pressing the trinket | 3 numbers + a 4th that flips to true/1 only during the GCD (= `isOnGCD`, not `restricted`) | U10 |
| P9 | `/run print(type(issecretvalue), type(scrubsecretvalues), type(canaccessallvalues), type(settablesecurity), type(secretunwrap))` then `/run local t={} print(pcall(settablesecurity,t,Enum.TableSecurityOption.DisallowSecretKeys))` | `secretunwrap` → `nil` (removed); `settablesecurity` prints whether a tainted caller is allowed | U8 |
| P10 | `/run print(C_Secrets.GetSpellCooldownSecrecy(20271), C_Secrets.ShouldSpellCooldownBeSecret(20271))` for one always-available spell, in and out of combat | enum value + bool that flip with the restriction state | U1, U9 |
| P11 | `/run print(issecretvalue(UnitAura("player",1,"HELPFUL")))` and `/run for i=1,3 do print(issecretvalue((UnitAura("player",i,"HELPFUL")))) end` | confirms the aura lane's premise (compat already nils the entry) | — |

`/st diag` already prints the build switches (`diag.lua:754-789`); run it in the same
session as the probes so each printed line can be attributed to a restriction state.

---

## 11. UNCONFIRMED register

| # | Fact | Why it is client-only | Probe |
|---|---|---|---|
| U1 | Which restriction states Forever actually raises (combat only? encounters? challenge mode? PvP? open-world?) and whether an open-world pull restricts cooldowns | `SecretWhenCooldownsRestricted` names the states; only the client knows which are active | P1, P10, `/st diag` |
| U2 | Whether the deprecated global `GetSpellCooldown` exists on Forever and returns the `SpellCooldownInfo` table (the transition guide says yes; no Lua definition exists in the branch) | implementation lives behind the deprecation CVar / native code | P2 |
| U3 | Whether `SetCooldownFromDurationObject` / `DurationTextBinding:SetDuration` accept a **secret-valued** duration object from *tainted* execution (the doc set says the object is not a secret argument, but the engine may still demand an aspect on the frame/font string) | engine execution-taint behaviour is not in the source tree | P4, P5 |
| U4 | Whether `LuaDurationObject` numeric getters return secret values when `HasSecretValues()` is true (no `ConditionalSecret` marker is declared on them) | engine taint propagation | P6 |
| U5 | Whether a `CooldownFrame`'s native countdown numbers and a binding-updated font string render correctly for secret-valued durations | native rendering path | P5, P7 |
| U6 | The exact value `GetSpellCooldownDuration(id, false)` describes for a spell with no cooldown of its own (pure GCD? `max(cooldown, gcd)`? zero object?) — zero call sites exist in the branch | not documented beyond the `ignoreGCD` argument | P3 |
| U7 | Whether spell 61304's cooldown is `NeverSecret` on this client (decides whether the GCD object is ever secret) | per-spell flags are data, not source | P3, P10 |
| U8 | Whether a **tainted** addon may call `settablesecurity` (`HasRestrictions = true`) | restriction enforcement at runtime | P9 |
| U9 | Whether `GetSpellCooldownSecrecy`/`ShouldSpellCooldownBeSecret` answers are stable across a cooldown restart window | runtime | P10 |
| U10 | The exact arity/meaning of `GetInventoryItemCooldown` on this client (Blizzard's Forever code names the 4th `isOnGCD`) | the global is unannotated/undocumented | P8 |
| U11 | Whether item cooldowns are ever restricted in practice (no `SecretWhen*` predicate exists, but the client could still hide them) | runtime | P8 in a restricted moment |
| U12 | `C_Spell.GetSpellCooldown` field-level secrecy in practice (does the whole table become secret, or only the three unmarked fields) | runtime | P3 |

---

## 12. Read-only attestation

- Files created by this lane: this report, `desks/forever-hud-api/journal.md`,
  `desks/forever-hud-api/.signals/<ts>.json`. Nothing else was written.
- No product file, test, TOC, `Libs/`, `docs/`, README/CHANGELOG or git state in
  `/home/sam/SwedgeTimer` was modified; `/home/sam/wow-ui-source` was read with
  `git show origin/forever:<path>` / `git grep … origin/forever` only (no checkout, no
  write); `/home/sam/SuperSwingTimer-WoW` was read only.
- No web search was used. Every claim above is either a quoted annotation/call site from
  `origin/forever` or an explicitly marked UNCONFIRMED runtime fact.
- Line numbers were verified against `git grep -n` on the branch (`eac30af59`); addon line
  numbers against the working tree on 2026-11-08. Re-verify before editing.
