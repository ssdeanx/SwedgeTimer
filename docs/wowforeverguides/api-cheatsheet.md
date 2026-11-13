[Skip to main content](https://wowforeverguides.com/addons/api-cheatsheet#main)

Addon guide page 3 of 7

GetSpellInfo and GetItemInfo were missing on beta build 69913, so write C\_Spell and C\_Item calls. Events replace the combat log, which is reported unavailable to addons.

## Ask Our Sweaty Degenerate AI About Addon API

C\_Spell Calls, Secret Values, Combat Log Events, TOC Interface 16001, Settings API & More?

Anything our guides cover. Answers come from this page and the rest of our guides, with the real values charted and the guide sections linked. It's AI, so check the source before you quote it.

Your question about this page![](https://wowforeverguides.com/assets/tools/ask-goblin/goblin-still.webp)Ask

Try

Replacing GetSpellInfo and GetItemInfoCombat log replacement eventsTOC interface 16001 for ForeverSecret values in addonsDetecting Forever with WOW\_PROJECT\_IDWhy secure snippets fail to compileSavedVariables load orderCalls that fail silentlyAddon Compartment without TOC fields

‹›

![](https://wowforeverguides.com/assets/tools/ask-goblin/goblin-still.webp)Your question, sticky barAskHide Answer

![](https://wowforeverguides.com/assets/tools/ask-goblin/goblin-still.webp)Ask

This is a quick reference for the 12.1.5-era API as it applies to WoW: Forever. Older observations name beta build 1.60.1.69913. The ruleset, sound and detection examples are source-checked against Blizzard's retained build 1.60.1.70338 client files. Other examples follow Warcraft Wiki Mainline documentation. None were tested in game by this author.

TOC interface16001Reported

Old spell and item globalsC\_Spell, C\_ItemReported

Combat logUnavailableUnverified

API familyMainline 12.1.5Reported

This reference is part of the [WoW Forever addon developer guide](https://wowforeverguides.com/addons/developers). For client architecture and secret values, read [WoW Forever addon patterns](https://wowforeverguides.com/addons/patterns). To see how models get these calls wrong, read the [common AI addon pitfalls](https://wowforeverguides.com/addons/pitfalls).

The October 13 additions cite the retained 70338 client extract. Linked source mirrors can show a later build.

## Globals That Were Gone

WoW Forever Builds found these Classic-era globals missing on build 69913. Models trained on old code still write them:

| AI will write | Use instead | Notes |
| --- | --- | --- |
| `GetSpellInfo(id)` | `C_Spell.GetSpellInfo(id)` | Returns one table (`name`, `iconID`, `castTime` and more). `nil` if the spell isn't found. |
| `GetItemInfo(id)` | `C_Item.GetItemInfo(id)` | Returns the same list of values as the old global. `nil` until cached. |
| `GetSpellBookItemName` | `C_SpellBook.GetSpellBookItemName` | Old spellbook global was missing on 69913. |
| `GetTalentInfo` / `GetNumTalentTabs` | `C_Traits` | WoW Forever Builds: talents run on the trait system. |
| `GetAddOnMetadata(name, field)` | `C_AddOns.GetAddOnMetadata` | Same namespace move as Mainline. |
| `CombatLogGetCurrentEventInfo()` | No verified replacement here | Reported unavailable. Test on your build before you drop the feature. |

## Spells and Items

Lookups can come back empty. `C_Spell.GetSpellInfo` or `C_Item.GetItemInfo` on a record the client has not loaded yet can return `nil`.

SpellLookup.luaCopy SpellLookup.lua

```
local info = C_Spell.GetSpellInfo(spellID)
if not info then
    C_Spell.RequestLoadSpellData(spellID)
    return
end
-- A field can still be secret. Guard before you print it.

local itemName, itemLink = C_Item.GetItemInfo(itemID)
if not itemName then
    C_Item.RequestLoadItemDataByID(itemID)
    return
end
```

Listen for `SPELL_DATA_LOAD_RESULT` (spellID, success) and `ITEM_DATA_LOAD_RESULT` (itemID, success). A `nil` can mean the record has not loaded or was not found. If the load event returns success false, treat the ID as not found.

## Units and Secrets

Blizzard said Midnight's secret values are active on Forever. Doing math on a secret value, or comparing one, throws an error:

| Call | Can be secret | Safe use |
| --- | --- | --- |
| `UnitHealth` / `UnitHealthMax` | Yes, number | `StatusBar:SetMinMaxValues` and `StatusBar:SetValue` |
| `UnitName` / creature names | Yes, string | Show only after `issecretvalue` is false |
| `UnitCanAttack` / `UnitExists` | Yes, boolean | Do not branch until the guard says plain |
| `UnitIsEnemy` | Often the wrong question | Means attackable now, not opposite faction |
| `UnitFactionGroup` | Check before compare | `them ~= mine` is the faction test |

The "can be secret" column for names and booleans comes from Warcraft Forever's beta notes. Health comes from WoW Forever Builds' test. Run this guard before you branch on a value or display it:

Guard.luaCopy Guard.lua

```
local function Sealed(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end
```

The [code templates](https://wowforeverguides.com/addons/code-templates) and the [Forever Beacon sample](https://wowforeverguides.com/addons/forever-beacon) have guarded status-bar examples. Test them on your current build.

## Events Instead of the Combat Log

On Midnight, registering `COMBAT_LOG_EVENT_UNFILTERED` throws an error (Warcraft Wiki, Patch 12.0.0 API changes). Warcraft Forever reports that the combat log reader is unavailable on Forever. Register unit events instead:

| You wanted | Register |
| --- | --- |
| **Player health** | `RegisterUnitEvent("UNIT_HEALTH", "player")` |
| **Power** | `UNIT_POWER_UPDATE` |
| **A cast started or finished** | `UNIT_SPELLCAST_START`, `_STOP`, `_SUCCEEDED`, `_FAILED`, `_INTERRUPTED` |
| **Auras** | Let Blizzard's aura frames draw them. `UNIT_AURA` is not a license to read aura data in combat. |
| **Entering and leaving combat** | `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED` |
| **A boss pull** | `ENCOUNTER_START` and `ENCOUNTER_END`, if the encounter fires them |
| **Zone changes** | `ZONE_CHANGED_NEW_AREA`, `PLAYER_ENTERING_WORLD` |

[![Guidelime v6.000 GitHub release notes, including Initial work to support WoW Forever and an Add arrow ETA and TomTom option entry](https://wowforeverguides.com/assets/leveling/free-addons/wow-forever-guidelime-github-release-v6000.webp)](https://wowforeverguides.com/assets/leveling/free-addons/wow-forever-guidelime-github-release-v6000.webp "Open full size")Share Image: Guidelime v6.000 GitHub release notes, including Initial work to support WoW Forever and an Add arrow ETA and TomTom option entry

[Share image link on X (opens in a new tab)](https://x.com/intent/tweet?url=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fapi-cheatsheet%23wfg-image-ff75259810&text=Guidelime+v6.000+GitHub+release+notes%2C+including+Initial+work+to+support+WoW+Forever+and+an+Add+arrow+ETA+and+TomTom+option+entry "Share image link on X (opens in a new tab)")[Share image link on Facebook (opens in a new tab)](https://www.facebook.com/sharer/sharer.php?u=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fapi-cheatsheet%23wfg-image-ff75259810 "Share image link on Facebook (opens in a new tab)")[Share image link on Telegram (opens in a new tab)](https://t.me/share/url?url=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fapi-cheatsheet%23wfg-image-ff75259810&text=Guidelime+v6.000+GitHub+release+notes%2C+including+Initial+work+to+support+WoW+Forever+and+an+Add+arrow+ETA+and+TomTom+option+entry "Share image link on Telegram (opens in a new tab)")[Share image link by email](mailto:?subject=Guidelime%20v6.000%20GitHub%20release%20notes%2C%20including%20Initial%20work%20to%20support%20WoW%20Forever%20and%20an%20Add%20arrow%20ETA%20and%20TomTom%20option%20entry&body=Guidelime%20v6.000%20GitHub%20release%20notes%2C%20including%20Initial%20work%20to%20support%20WoW%20Forever%20and%20an%20Add%20arrow%20ETA%20and%20TomTom%20option%20entry%0Ahttps%3A%2F%2Fwowforeverguides.com%2Faddons%2Fapi-cheatsheet%23wfg-image-ff75259810 "Share image link by email")

[Open image](https://wowforeverguides.com/assets/leveling/free-addons/wow-forever-guidelime-github-release-v6000.webp "Open image")[Download image](https://wowforeverguides.com/assets/leveling/free-addons/wow-forever-guidelime-github-release-v6000.webp "Download image")

Copy this link

Guidelime's v6.000 release notes include a fix to skip secret values in UNIT _SPELLCAST_ SUCCEEDED on WoW Forever.Source: [Guidelime v6.000 on GitHub](https://github.com/max-ri/Guidelime/releases/tag/v6.000), captured Sep 30, 2026.

## Frames, Time, Chat

Frames that need a backdrop inherit `BackdropTemplate`. Timers use `C_Timer`:

Basics.luaCopy Basics.lua

```
local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
f:SetSize(240, 48)
f:SetPoint("CENTER")
f:SetScript("OnEvent", function(self, event, ...) end)

C_Timer.NewTimer(2, function() end)      -- cancellable
C_Timer.After(2, function() end)         -- returns nothing

SLASH_MYADDON1 = "/myaddon"
SlashCmdList["MYADDON"] = function(msg) end

DEFAULT_CHAT_FRAME:AddMessage(text, 0.83, 0.66, 0.35)
```

### SetTexCoord Parameter Order

`SetTexCoord` takes `left`, `right`, `top`, `bottom`, not `left, top, right, bottom`. Pass fractions from `0` to `1`, not pixels.

## Calls That Fail Silently

Warcraft Forever's page, captured September 28, lists these calls as protected on the Forever beta but names no client build:

| Avoid | Use |
| --- | --- |
| `ChatFrame_OpenChat` / `ChatEdit_ActivateChat` | Leave chat editing to the client; use `HandleModifiedItemClick` for shift-click links |
| `C_SuperTrack.SetSuperTrackedUserWaypoint` | `C_Map.SetUserWaypoint` with a `UiMapPoint` |
| Secure attributes on Blizzard unit frames | Your own buttons |
| `PlaySoundFile` on `Sound\Interface\*.ogg` | `PlaySound` with a `SOUNDKIT` ID |
| `pcall` around a blocked action | Nothing; `pcall` does not unblock it |

## TOC Fields That Matter Here

A Forever-only addon declares interface `16001` on the beta:

MyAddon.tocCopy MyAddon.toc

```
## Interface: 16001
## Title: My Addon
## Notes: What it does in one line
## Author: YourName
## Version: 0.1.0
## SavedVariables: MyAddonDB
## SavedVariablesPerCharacter: MyAddonCharDB
## IconTexture: Interface\Icons\INV_Misc_Note_01
## Category: Miscellaneous
## AddonCompartmentFunc: MyAddon_OnCompartmentClick
```

Compartment callbacks must be real globals, because the client looks them up by name. Keep everything else in your files as file-scoped locals. SavedVariables names are globals too. The client loads them after your files run, then fires `ADDON_LOADED` for your addon.

## Settings API

The Settings API replaced the old Interface Options panel, and it is part of the Mainline code Forever shares. Prefer it over a private options window when you only need checkboxes and sliders. If you build a custom window, inherit `BackdropTemplate`, save the anchor on drag stop, and do not move protected frames during combat lockdown.

`InterfaceOptions_AddCategory` is the older options call, and models still reach for it. Ask for the Settings API instead.

## Choosing the Modern API Over Classic's

On the September 17 developer Q&A, a developer was asked whether Forever would use Midnight's addon restrictions, the Classic API, or something else, and answered: "we did opt for the modern API approach." **Confirmed**, from the [World of Warcraft Developer Q&A](https://wowforeverguides.com/news/wow-forever-developer-qa-stream) replay at 01:20:52.

Wowhead, reporting Blizzard's WoW UI Discord announcement, says the same API changes "caused WeakAuras to stop development before Midnight and almost every addon to update." **Reported**. When you port, start from an addon's Midnight build, which already handles these rules, not its Classic Era branch. Big projects are doing this: the [RestedXP](https://wowforeverguides.com/restedxp) guide addon lists a "WoW Forever" file on CurseForge.

### What Blizzard Built in Instead

On the same stream, the panel said Forever offers its own damage meter and cooldown manager. **Confirmed** for both. A swing timer came up only as a possible later addition. Check whether a built-in panel already does the job before you ship a duplicate.

## Detecting Forever From Your Own Code

A guard written as `if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then` will not detect this game. WoW Forever Builds' older test on build 69913 reported `1`, the same value as `WOW_PROJECT_MAINLINE`. The retained live probe on build **70338**, October 12, instead records `WOW_PROJECT_ID = 18`, `WOW_PROJECT_MAINLINE = 1` and `WOW_PROJECT_CLASSIC = 2`. Blizzard's Camelot project constants set `WOW_PROJECT_CAMELOT = 18`. **Reported client observation**: the older number is historical, not a current detection rule.Source: [Blizzard's Camelot project constants](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua), inspected in the retained 70338 client files Oct 13, 2026; live probe captured Oct 12.

For a shared addon, compare the named constant when it exists, then check the specific API your feature needs. A Forever-only addon can target Forever directly:

Detect.luaCopy Detect.lua

```
local isForever = WOW_PROJECT_CAMELOT ~= nil
    and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
local canReadPreset = C_GameRules
    and type(C_GameRules.GetForeverExperiencePreset) == "function"
if isForever and canReadPreset then
    -- Read the preset; do not infer combat permissions from a project ID.
end
```

The same page shows another route, through the TOC: declare `## X-Family: [Family]` and `## X-Game: [Game]`, then read them with `C_AddOns.GetAddOnMetadata`. In the wiki's example, family `Mainline` with game `Camelot` means Forever.

<details><summary>Technical Notes: older detection examples</summary>

The Warcraft Wiki's retained September example paired `WOW_PROJECT_MAINLINE` with `LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CLASSIC` and labeled the branch "camelot/forever." That Mainline project-ID condition is false on the captured 70338 client. Mainline UI architecture does not mean a Mainline project ID. A library that only loads on Classic silently fails to load, and no error says why.

</details>

## Get the Current Ruleset With the UI API

Use `C_GameRules` for game-mode queries. The current ruleset is not the same question as the client project ID, a Hardcore flag, or the player's Classic/Modern experience preset. Choose the value your feature actually needs:

| You need | Read | Result in the 70338 docs |
| --- | --- | --- |
| Current game-mode record | `C_GameRules.GetCurrentGameModeRecordID()` | Numeric record ID; no Forever ID mapping is asserted here |
| Active game mode | `C_GameRules.GetActiveGameMode()` | `GameMode` enum value |
| Hardcore rule active | `C_GameRules.IsHardcoreActive()` | Boolean |
| A particular game rule | `C_GameRules.IsGameRuleActive(gameRule)` | Boolean; pass the documented `GameRule` value |
| Classic/Modern experience preset | `C_GameRules.GetForeverExperiencePreset()` | `Enum.ForeverExperiencePreset`, or `nil` |
| Chat-channel ruleset | `C_ChatInfo.GetChannelRuleset(channelIndex)` | `Enum.ChatChannelRuleset`; not the game ruleset |

These signatures are in Blizzard's generated client documentation, not guessed from Classic tutorials.Source: [Blizzard's GameRules documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/GameRulesDocumentation.lua) and [ChatInfo documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua), retained client build 70338, inspected Oct 13, 2026.

For a quick diagnostic after entering the world, type `/dump C_GameRules.GetCurrentGameModeRecordID()`. To read the Forever experience preset from addon code:

Ruleset.luaCopy Ruleset.lua

```
local function ReadExperiencePreset()
    if not C_GameRules
        or type(C_GameRules.GetForeverExperiencePreset) ~= "function" then
        return "API unavailable"
    end
    local preset = C_GameRules.GetForeverExperiencePreset()
    if preset == nil then return "Preset unavailable" end
    if preset == Enum.ForeverExperiencePreset.Classic then return "Classic" end
    if preset == Enum.ForeverExperiencePreset.Modern then return "Modern" end
    return "Unknown preset"
end

print(ReadExperiencePreset())
```

The enum uses Classic `0` and Modern `1`. This example reads the preference; it changes nothing. `GAME_RULES_CHANGED` and `ACTIVE_GAME_MODE_UPDATED` are documented events for refreshing game-rule and active-mode displays. Their presence does not prove that every preset change fires either event. The captured probe's recorded function list includes these functions; it did not measure their returned game-mode IDs or exercise this example.

## Sound IDs Cheat Sheet

Use `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)` for a built-in UI sound. Blizzard's 70338 `SoundKitConstants.lua` supplies these sound kit IDs:

| Sound | `SOUNDKIT` key | ID |
| --- | --- | --- |
| Checkbox on | `IG_MAINMENU_OPTION_CHECKBOX_ON` | 856 |
| Checkbox off | `IG_MAINMENU_OPTION_CHECKBOX_OFF` | 857 |
| Menu opens | `IG_MAINMENU_OPEN` | 850 |
| Menu closes | `IG_MAINMENU_CLOSE` | 851 |
| Character tab | `IG_CHARACTER_INFO_TAB` | 841 |
| Raid warning | `RAID_WARNING` | 8959 |

These are sound kit IDs, not spell IDs or audio FileDataIDs. Prefer the named constants in addon files. To preview one manually, type `/run PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)`. We inspected the IDs in the client source; we did not listen to these previews.Source: [Blizzard's sound kit constants](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Mainline/SoundKitConstants.lua), retained client build 70338, inspected Oct 13, 2026.

On this build, Blizzard aliases `PlaySound` to `C_Sound.PlaySound`. The generated signature uses a `UISoundSubType` as its second argument. The one-argument example avoids copying an older `"Master"` or `"SFX"` channel-string signature into this client. A silent preview can reflect sound settings; do not turn on or increase a player's audio automatically.Source: [Blizzard's Sound.lua](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Mainline/Sound.lua) and [Sound API documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SoundDocumentation.lua), retained client build 70338, inspected Oct 13, 2026.

For functions with several statements, slash command aliases, a local message command and a popup message, use the [practical code templates](https://wowforeverguides.com/addons/code-templates#functions-with-more-than-one-command).

## Why Secure Snippets Can Fail to Compile

WoW Forever Builds traced a second break to Blizzard's own restricted-execution code. `RestrictedExecution.lua` calls an engine function, `loadstring_untainted`, and build 69913 never provides it. `/run print(type(loadstring_untainted))` prints `nil`, and every secure snippet fails with a call-to-nil error. **Reported**. The outlet, WoW Forever Builds, reads this as a missing piece, not policy, because Blizzard's code expects the function.

Addons use secure snippets for combat-safe work such as action bar paging, secure group headers and click-casting. If yours throws that exact error, the snippet system is down on your build, not your code. Retest on each new build.

### The Action-Failed Counter

A protected call like `ChatFrame_OpenChat` does not raise a Lua error you can catch on this client, so `pcall` will not warn you. Warcraft Forever's page, captured September 28 with no build named, reports that the client posts "Interface action failed because of an AddOn" and bumps a counter in the AddOns panel, which clears only on a full restart, not `/reload`. **Unverified** community report. A rising counter means you should check your protected calls.

## What Tainted Code Can Still Do With a Secret Value

The "Units and secrets" table covers arithmetic and comparisons. The wiki's rules go further, and they cut both ways: some things are allowed, some are not. Tainted code can store a secret in a variable, an upvalue, or a table value, and pass it to Lua functions. C functions accept one only when Blizzard marks them to. Tainted code can also concatenate secret strings and numbers, and pass them to `string.format`, `string.concat`, or `string.join`.

Tainted code cannot do arithmetic on a secret, compare it, use the length operator on it, store it as a table key, index into it, or call it. A truthiness test works on a secret string or number, since only the value is hidden, but not on a secret boolean. `type(secret)` still returns the real type. Each forbidden operation throws immediately, so guard before you branch.

## SavedVariables Load Order, and the Beta's Restore Bug

The client runs your addon's files, then loads its `SavedVariables` and `SavedVariablesPerCharacter` and fires `ADDON_LOADED` for it, one addon at a time. `PLAYER_LOGIN` fires once every non-load-on-demand addon has loaded. To make a last change before the file is written, use `PLAYER_LOGOUT`, the final event before the save.

A Blizzard Forums bug report from September 21 showed Soundtrack's settings written correctly to the `WTF` folder but missing after the next launch. Other addon authors in the thread reported the same. **Unverified**, community-reported. On September 25, a different author said SavedVariables were loading again on build 1.60.1.70009. Retest your own addon before you trust the fix.

### Two Porting Traps From the Same Report

The Soundtrack port first failed inside AceDB-3.0 with a nil `regionKey`. On the beta, `GetCurrentRegion()` returned a region ID the bundled library did not recognize, and patching AceDB to tolerate unknown IDs fixed it. The author also split one `IsRetail` flag in two, because on Forever "use the modern API" and "enable Retail-only content" are different questions.

## Nameplate Timing on the Beta Client

Warcraft Forever reports that `NAME_PLATE_UNIT_ADDED` fires before the unit is populated, with no `namePlateUnitToken` on the plate frames. **Unverified**. The reported workaround is to recheck the unit a moment later, or to sweep `nameplate1` through `nameplate40` yourself.

## Addon Compartment: Registering Without TOC Fields

The TOC fields above cover a compartment button that never changes. If yours picks its icon or label at runtime, the Warcraft Wiki documents a manual call:

Compartment.luaCopy Compartment.lua

```
AddonCompartmentFrame:RegisterAddon({
    text = "My Addon",
    icon = "Interface\\Icons\\TEMP.blp",
    notCheckable = true,
    func = function(button, menuInputData)
        print("Clicked " .. menuInputData.buttonName)
    end,
})
```

This comes from Mainline documentation, not a Forever test, so confirm it fires on your build. If you draft with an AI system prompt, the [AI prompt library for addon code](https://wowforeverguides.com/addons/ai-prompts) keeps these constraints in one place. For the player side, the [addons that work in Forever](https://wowforeverguides.com/addons) page tracks what still runs.

## Key Facts

- TOC interface Changed16001 in the Forever Beta row of the Warcraft Wiki TOC table; confirm with /dump select(4, GetBuildInfo())Classic: Classic Era lists 11509 on the same table.Reported
- Old spell and item globals RemovedGetSpellInfo and GetItemInfo missing on build 69913; use C\_Spell and C\_ItemReported
- Combat log RemovedCombatLogGetCurrentEventInfo reported unavailable to addons on the betaClassic: Classic Era addons read every event through COMBAT\_LOG\_EVENT\_UNFILTERED.Unverified
- API family ChangedShares Mainline UI architecture and "the vast majority of APIs available in 12.1.5"Reported
- Captured project ID Changed18 (WOW\_PROJECT\_CAMELOT) in the October 12 live probe on build 70338; older 69913 reports said 1Reported

## Sources

01. [What the WoW Forever beta breaks for addons: secret health values, dead secure snippets, new APIs](https://wowforeverbuilds.com/news/what-the-wow-forever-beta-breaks-for-addons-secret-health-values-dead-secure-sni) WoW Forever BuildsSep 18, 2026
02. [Addons](https://warcraftforever.games/addons) Warcraft Forever
03. [WoW: Forever Will Have Addon Changes from Midnight](https://www.wowhead.com/news/wow-forever-will-have-addon-changes-from-midnight-382921) WowheadSep 16, 2026
04. [TOC format](https://warcraft.wiki.gg/wiki/TOC_format) Warcraft Wiki
05. [C\_Item.GetItemInfo](https://warcraft.wiki.gg/wiki/API_C_Item.GetItemInfo) Warcraft Wiki
06. [Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values) Warcraft Wiki
07. [Patch 12.0.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) Warcraft Wiki
08. [Addon compartment](https://warcraft.wiki.gg/wiki/Addon_compartment) Warcraft Wiki
09. [Saving variables between game sessions](https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions) Warcraft Wiki
10. [C\_Map.SetUserWaypoint](https://warcraft.wiki.gg/wiki/API_C_Map.SetUserWaypoint) Warcraft Wiki
11. [WOW\_PROJECT\_ID](https://warcraft.wiki.gg/wiki/WOW_PROJECT_ID) Warcraft Wiki
12. [World of Warcraft Developer Q&A (replay and YouTube automatic captions)](https://www.youtube.com/watch?v=Y5zzSMSVhRo) World of WarcraftSep 17, 2026
13. [WOWF Beta: Addon SavedVariables appear to write correctly to disk but are not restored at startup](https://us.forums.blizzard.com/en/wow/t/wowf-beta-addon-savedvariables-appear-to-write-correctly-to-disk-but-are-not-restored-at-startup/2356559) Blizzard ForumsSep 21, 2026
14. [RestedXP Guide on CurseForge](https://www.curseforge.com/wow/addons/restedxp-guide) CurseForge
15. [Blizzard client source: ProjectConstants.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua) Blizzard Entertainment (source mirrored by Gethe)
16. [Blizzard client source: GameRulesDocumentation.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/GameRulesDocumentation.lua) Blizzard Entertainment (source mirrored by Gethe)
17. [Blizzard client source: SoundKitConstants.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Mainline/SoundKitConstants.lua) Blizzard Entertainment (source mirrored by Gethe)
18. [Blizzard client source: Sound.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Mainline/Sound.lua) Blizzard Entertainment (source mirrored by Gethe)
19. [Blizzard client source: SoundDocumentation.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SoundDocumentation.lua) Blizzard Entertainment (source mirrored by Gethe)
20. [Blizzard client source: ChatInfoDocumentation.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua) Blizzard Entertainment (source mirrored by Gethe)
21. [Guidelime v6.000 on GitHub](https://github.com/max-ri/Guidelime/releases/tag/v6.000)

## Keep Reading

- [AddonsWoW Forever Addons](https://wowforeverguides.com/addons)
- [Leveling addonsWoW Forever Leveling Addons](https://wowforeverguides.com/leveling/addons)
- [Macro builderWoW Forever Class Macros](https://wowforeverguides.com/tools/macros)

Roll on analytics? **Need** = Clicky, GA4 & Microsoft Clarity with cookies and session replays, to see which guides help. **Pass** = no analytics at all. [Privacy](https://wowforeverguides.com/privacy#your-analytics-choice)

NeedPass