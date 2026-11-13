[Skip to main content](https://wowforeverguides.com/addons/code-templates#main)

Addon guide page 5 of 7

Copy these templates for interface 16001: hello world, SavedVariables, a secret-safe bar, the addon compartment and combat lockdown. They follow the Warcraft Wiki's Mainline docs and beta-era reports, so verify each one on your client.

## Ask Our Sweaty Degenerate AI About Addon Code Templates

Hello World, SavedVariables, Secret-Safe Bars, Addon Compartment & More?

Anything our guides cover. Answers come from this page and the rest of our guides, with the real values charted and the guide sections linked. It's AI, so check the source before you quote it.

Your question about this page![](https://wowforeverguides.com/assets/tools/ask-goblin/goblin-still.webp)Ask

Try

Interface 16001 TOC settingSavedVariables setup in the TOCSecret-safe health barAddon compartment TOC fieldsC\_Timer.After instead of OnUpdateProtected waypoint call on ForeverItem lookup cache timingSettings API options panelCombat lockdown queue templateDetect a Forever client

Each block is a complete pattern for interface 16001. The folder name and the TOC file name must match.

TOC interface16001Reported

SavedVariablesBug reported fixedUnverified

Addon compartmentUntested hereUnverified

Combat lockdownQueue until regenReported

This library is part of the [WoW Forever addon developer guide](https://wowforeverguides.com/addons/developers). For the client design behind these snippets, see [WoW Forever addon patterns](https://wowforeverguides.com/addons/patterns). To check individual signatures, use the [Forever API cheat sheet](https://wowforeverguides.com/addons/api-cheatsheet). For a finished, downloadable addon that wires notes, a probe, the compartment and a secret-safe bar together, inspect the [Forever Beacon reference addon](https://wowforeverguides.com/addons/forever-beacon).

This site has not run any of these templates in a Forever client. They are dated beta-era examples that follow the Warcraft Wiki's Mainline documentation, the cited beta reports and retained Blizzard client source from build 70338. The separate project-ID probe ran in game; that does not make these examples live-tested.

The October 13 additions cite the retained 70338 client extract. Linked source mirrors can show a later build.

## Functions With More Than One Command

A Lua function can contain several statements. Put each operation on its own line between `function` and `end`; they run in order when you call the function. This example prints a local message and plays one UI sound:

Ready.luaCopy Ready.lua

```
local function AnnounceReady()
    print("[Forever Notes] Ready.")
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

AnnounceReady()
```

You do not need multiple function definitions or semicolons. An early `return` ends the function, and an uncaught error stops the remaining statements.Source: [Lua 5.1 Reference Manual, function definitions and blocks](https://www.lua.org/manual/5.1/manual.html#2.5.9) and [error handling](https://www.lua.org/manual/5.1/manual.html#2.7), checked Oct 13, 2026. Lua statements are different from macro slash commands such as `/cast`. These examples print text and play a sound; they do not implement protected combat actions.

In chat, the equivalent diagnostic is `/run print("Ready."); PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)`. Keep reusable code in a Lua file listed in your TOC. The [sound IDs cheat sheet](https://wowforeverguides.com/addons/api-cheatsheet#sound-ids-cheat-sheet) lists the constants used here.

## Message Command and Slash Command Aliases

For a message only you can see, use `print("Hello.")` or `DEFAULT_CHAT_FRAME:AddMessage("Hello.", 1, 0.82, 0)`. In chat, type `/run print("Hello.")`. These print locally; they do not send a party message or whisper.

To define one function with more than one slash command, give the same `SlashCmdList` key numbered aliases. This complete two-file example makes both `/wfgmessage Hello` and `/wfgmsg Hello` print the supplied text locally:

WFGMessageExample.tocCopy WFGMessageExample.toc

```
## Interface: 16001
## Title: WFG Message Example
## Notes: Two slash commands for one local message handler.
## Version: 0.1.0

WFGMessageExample.lua
```

WFGMessageExample.luaCopy WFGMessageExample.lua

```
local function ShowLocalMessage(text)
    if not text:find("%S") then
        print("Usage: /wfgmessage Hello")
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage("[WFG Message] " .. text, 1, 0.82, 0)
end

SLASH_WFGMESSAGEEXAMPLE1 = "/wfgmessage"
SLASH_WFGMESSAGEEXAMPLE2 = "/wfgmsg"
SlashCmdList["WFGMESSAGEEXAMPLE"] = ShowLocalMessage
```

Use the folder name `WFGMessageExample`, then restart the client when adding it. The uppercase registration key must match both `SLASH_` globals. Register aliases at file load, not each time the handler runs. Blizzard's slash command registry uses this same numbered-global pattern.Source: [Blizzard's slash command registry](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommandsRegistry.lua), retained client build 70338, inspected Oct 13, 2026.

If "message command" means sending chat to other people, that is a separate operation: `C_ChatInfo.SendChatMessage("Hello.", "PARTY")` sends to party chat when the client permits it. Call it only for a deliberate player action, and check the current chat restrictions. The generated docs mark this API `HasRestrictions`; this page does not claim arbitrary automated sending is allowed.Source: [Blizzard's ChatInfo documentation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua), `SendChatMessage`, retained client build 70338, inspected Oct 13, 2026.

## Display a Popup Message

Register an addon-specific entry in `StaticPopupDialogs`, then call `StaticPopup_Show` with that key. This example displays a fixed informational message with an Okay button and Escape dismissal. Put it in a Lua file loaded by your TOC:

PopupMessage.luaCopy PopupMessage.lua

```
StaticPopupDialogs["WFG_EXAMPLE_READY_MESSAGE"] = {
    text = "Forever Notes is ready.",
    button1 = OKAY,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

SLASH_WFGPOPUPEXAMPLE1 = "/wfgpopup"
SlashCmdList["WFGPOPUPEXAMPLE"] = function()
    StaticPopup_Show("WFG_EXAMPLE_READY_MESSAGE")
end
```

After loading the addon, type `/wfgpopup`. The message stays until dismissed because `timeout = 0`. Use your own key, leave Blizzard's dialog definitions intact, and request the popup deliberately rather than repeating it from an update loop. This example has not been exercised in the Forever client.Source: [Blizzard's StaticPopup implementation](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_StaticPopup/StaticPopup.lua), `StaticPopup_Show`, `timeout`, `whileDead` and `hideOnEscape`, retained client build 70338, inspected Oct 13, 2026.

## Hello

The smallest addon: it prints once on login and never touches a name that could be secret.

HelloForever.tocCopy HelloForever.toc

```
## Interface: 16001
## Title: Hello Forever
## Notes: Prints once on login, without touching a secret name.
## Author: YourName
## Version: 0.1.0
## Category: Miscellaneous

HelloForever.lua
```

HelloForever.luaCopy HelloForever.lua

```
local addonName = ...
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function()
    print("|cffd4a85a[" .. addonName .. "]|r Forever client accepted this addon.")
end)
frame:RegisterEvent("PLAYER_LOGIN")
```

## SavedVariables

Declare the table in the TOC: `## SavedVariables: BeaconNotesDB`. The name is a global because the client fills it in after your files run. Touch it only in `ADDON_LOADED`, and merge default keys so you never overwrite a player's settings.

SavedVariables.luaCopy SavedVariables.lua

```
local addonName, ns = ...
local defaults = { scale = 1, locked = false }

local events = {}
function events:ADDON_LOADED(loaded)
    if loaded ~= addonName then return end
    BeaconNotesDB = BeaconNotesDB or {}
    local db = BeaconNotesDB
    for key, value in pairs(defaults) do
        if db[key] == nil then db[key] = value end
    end
    ns.db = db
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...)
    if events[event] then events[event](self, ...) end
end)
frame:RegisterEvent("ADDON_LOADED")
```

Don't set `BeaconNotesDB = BeaconNotesDB or {}` at file scope. It is trap 08 in the [common AI addon pitfalls](https://wowforeverguides.com/addons/pitfalls).

## Secret-Safe Bar

On build 69913, `UnitHealth("player")` came back as a secret number. The Warcraft Wiki's Midnight rules say `UnitHealthMax` can be secret too. You can't compute a percent from them in Lua, but a `StatusBar` accepts them directly.

HealthBar.luaCopy HealthBar.lua

```
local bar = CreateFrame("StatusBar", nil, UIParent)
bar:SetSize(200, 14)
bar:SetPoint("CENTER", 0, -40)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetStatusBarColor(0.55, 0.12, 0.12)

local function Paint()
    -- Both values may be secret. The bar may have them. Lua may not do math on them.
    bar:SetMinMaxValues(0, UnitHealthMax("player"))
    bar:SetValue(UnitHealth("player"))
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", Paint)
frame:RegisterUnitEvent("UNIT_HEALTH", "player")
frame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
```

## Addon Compartment

The minimap addon compartment needs no LibDataBroker: the TOC names global functions and the client calls them. The Warcraft Wiki documents these fields for Mainline. This site hasn't tested them on a Forever client, so check that the entry appears.

CompartmentStub.tocCopy CompartmentStub.toc

```
## Interface: 16001
## Title: Compartment Stub
## Notes: Minimap compartment without LibDataBroker.
## IconTexture: Interface\Icons\INV_Misc_Note_01
## AddonCompartmentFunc: CompartmentStub_OnClick
## AddonCompartmentFuncOnEnter: CompartmentStub_OnEnter
## AddonCompartmentFuncOnLeave: CompartmentStub_OnLeave

CompartmentStub.lua
```

CompartmentStub.luaCopy CompartmentStub.lua

```
function CompartmentStub_OnClick()
    print("|cffd4a85a[Stub]|r compartment click")
end

function CompartmentStub_OnEnter(_, owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("Compartment Stub", 1, 0.82, 0.45)
    GameTooltip:Show()
end

function CompartmentStub_OnLeave()
    GameTooltip:Hide()
end
```

## Combat Lockdown Queue

In combat, while `InCombatLockdown()` is true, addons can't show, hide, move or change the attributes of protected frames. Queue those changes and run them when `PLAYER_REGEN_ENABLED` fires.

Queue.luaCopy Queue.lua

```
local pending = {}

local function Queue(fn)
    if InCombatLockdown() then
        pending[#pending + 1] = fn
    else
        fn()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function()
    for i = 1, #pending do pending[i]() end
    wipe(pending)
end)

-- Use Queue only for protected frames.
-- Your own unprotected frames may Show() during combat.
```

For prompts that produce code in this shape, see the [ready-to-use AI prompts](https://wowforeverguides.com/addons/ai-prompts).

## Write for Forever; Compare the Named Project ID Constant

`WOW_PROJECT_ID` was **18** in the retained live probe on Forever beta build **1.60.1.70338**, October 12, 2026. Blizzard's source names that value `WOW_PROJECT_CAMELOT`. `WOW_PROJECT_MAINLINE` was 1 and `WOW_PROJECT_CLASSIC` was 2, so the usual `if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` branch was false on that build. The older community report of `1` belongs to build 69913; retain its build number rather than treating it as today's constant.Source: [Blizzard's Camelot project constants](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua), retained 70338 client files, inspected Oct 13, 2026. Constants measured in the 1.60.1.70338 beta client Oct 12, 2026.

An add-on that only ever runs on Forever has nothing to branch on. Write the Forever version and say so in a comment, so the next reader does not go looking for the branch.

Detect.luaCopy Detect.lua

```
-- Build 70338 recorded WOW_PROJECT_ID 18, named WOW_PROJECT_CAMELOT.
-- WOW_PROJECT_MAINLINE was 1 and WOW_PROJECT_CLASSIC was 2, so an
-- "is this Retail" or "is this Classic" branch was false; retest.
-- A Forever-only add-on writes for Forever directly.
local FOREVER_PROJECT_ID = WOW_PROJECT_CAMELOT
```

The wiki's older example labels a branch "camelot/forever" because Forever is a game type inside the Mainline family. That shared architecture does not determine its project ID. Blizzard's WoW UI Discord statement, quoted by Wowhead, calls Forever and Midnight "two game types within the Mainline code family." The same statement, made during the beta, calls Forever's type "Camelot (to be renamed before launch)" and says Forever shares "the vast majority of APIs available in 12.1.5," which is why the Mainline wiki pages below apply at all.Source: [WoW: Forever Will Have Addon Changes from Midnight](https://www.wowhead.com/news/wow-forever-will-have-addon-changes-from-midnight-382921), checked Sep 28, 2026.

For shared add-ons that target several clients, compare `WOW_PROJECT_ID` with `WOW_PROJECT_CAMELOT` when that constant exists, then check the feature's API. A Forever-only addon can target Forever directly. You can also split files through the TOC. For the current ruleset, Hardcore flag or Classic/Modern experience preset, use the [GameRules reference](https://wowforeverguides.com/addons/api-cheatsheet#get-the-current-ruleset-with-the-ui-api); a client ID does not answer those questions.

<details><summary>Technical Notes: expansion constants</summary>

The retained wiki example nests `LE_EXPANSION_LEVEL_CURRENT` and `LE_EXPANSION_CLASSIC` inside its Mainline project-ID branch. That branch is false on the captured 70338 Forever client. The Midnight-era client is another game type in the Mainline family; do not infer its project ID from that relationship.

</details>

### Split Files With TOC Variables

The `[Family]` and `[Game]` TOC variables expand at load time, so one `AddonName.toc` can point at different files for each client with no Lua branch at all.

Split.tocCopy Split.toc

```
## Interface: 16001
## Title: Split Example

[Family]\File.lua
[Game]\File.lua
```

`[Family]` becomes Mainline or Classic. `[Game]` becomes Camelot on a Forever client. The other listed game types include Standard, Vanilla and TBC.Source: [TOC format](https://warcraft.wiki.gg/wiki/TOC_format), checked Sep 28, 2026.

The same page lists a `camelot` client-specific suffix, so `AddonName_Camelot.toc` loads in place of the default file. When checked on September 28, 2026, its interface table put `16001` on the row named "Forever Beta" and left "Forever Test" and "Forever" blank. Questie's live Forever TOC declares 16001.Source: [Questie repository: Questie\_Forever.toc](https://github.com/Questie/Questie/blob/master/Questie_Forever.toc), checked Nov 8, 2026. Confirm the number on your client with `/dump select(4, GetBuildInfo())`.

## Look Up an Item Without Racing the Cache

`C_Item.GetItemInfo` returns 18 separate values, not one table: name, link, quality, level and on through `itemDescription`. It answers `nil` until the client has cached that item, whether or not the item exists.Source: [C\_Item.GetItemInfo](https://warcraft.wiki.gg/wiki/API_C_Item.GetItemInfo), checked Sep 28, 2026.

### Request the Data, Then Read the Event

ItemLookup.luaCopy ItemLookup.lua

```
local function OnItemData(_, event, itemID, success)
    if not success then return end
    local name = C_Item.GetItemInfo(itemID)
    if name then print(name, "is cached now") end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", OnItemData)
frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")

C_Item.RequestLoadItemDataByID(4306)
```

Since patch 10.0.5, the server can answer `success = false` for a specific item ID, so check that flag before you call `GetItemInfo` again on the same session.Source: [ITEM\_DATA\_LOAD\_RESULT](https://warcraft.wiki.gg/wiki/ITEM_DATA_LOAD_RESULT), checked Sep 28, 2026.

`RequestLoadItemDataByID` also accepts a full item link, so you can pass along whatever a tooltip hook or chat link handed you, without parsing out the numeric ID first.

## Look Up a Spell the Same Way

`C_Spell.GetSpellInfo` returns one table, unlike the item call: `spellInfo.name`, `spellInfo.iconID`, `spellInfo.castTime` and the rest. It replaced the older `GetSpellInfo` and `C_SpellBook.GetSpellInfo`globals.Source: [C\_Spell.GetSpellInfo](https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellInfo), checked Sep 28, 2026.

SpellLookup.luaCopy SpellLookup.lua

```
local function OnSpellData(_, event, spellID, success)
    local info = C_Spell.GetSpellInfo(spellID)
    if not info then return end
    -- success == false can still mean a partial record, such as no description.
    print(info.name, info.castTime, success and "full" or "partial")
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", OnSpellData)
frame:RegisterEvent("SPELL_DATA_LOAD_RESULT")

C_Spell.RequestLoadSpellData(2061)
```

The wiki says `success` "Might return false when only partial spell data is available," such as everything except the description.Source: [SPELL\_DATA\_LOAD\_RESULT](https://warcraft.wiki.gg/wiki/SPELL_DATA_LOAD_RESULT), checked Sep 28, 2026. That's why the template reads the table even on a false result instead of bailing out. The [AI addon pitfalls](https://wowforeverguides.com/addons/pitfalls) list covers other places where a generated answer skips a guard like this.

Both calls take a spell ID or a spell name. When you pass a name, `C_Spell.GetSpellInfo` looks for the player's current override of that spell first, so a transformed ability can return the overriding spell's icon.

## Delay Work Without an OnUpdate Script

`C_Timer.After` schedules a one-shot callback. A Blizzard post quoted on the wiki says the timer system only does work when a timer is created or destroyed, while an `OnUpdate` handler costs a Lua call every rendered frame.Source: [C\_Timer.After](https://warcraft.wiki.gg/wiki/API_C_Timer.After), checked Sep 28, 2026.

Debounce.luaCopy Debounce.lua

```
local pendingSave = false

local function ScheduleSave()
    if pendingSave then return end
    pendingSave = true
    C_Timer.After(2, function()
        pendingSave = false
        -- update an in-memory table or refresh a preview here
    end)
end
```

Use this to debounce follow-up work after a setting changes, such as updating an in-memory table or refreshing a preview. The timer does not write SavedVariables to disk; the client persists declared variables on logout or UI reload.

## Read Your Own TOC Metadata

`C_AddOns.GetAddOnMetadata(name, variable)` reads `Title`, `Notes`, `Author`, `Version`, or any custom `X-` field straight from your own TOC file, case insensitive.Source: [C\_AddOns.GetAddOnMetadata](https://warcraft.wiki.gg/wiki/API_C_AddOns.GetAddOnMetadata), checked Sep 28, 2026.

Version.luaCopy Version.lua

```
local addonName = ...
local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
print(("%s v%s loaded"):format(addonName, version))
```

Unlike the older global `GetAddOnMetadata`, this call raises an error for a name that doesn't match an installed addon, so wrap any lookup you are not sure of in `pcall`. Print the version in a compartment tooltip so a player reporting a bug can give it to you without opening the TOC file.

## Add an Options Panel With the Settings API

The wiki says the Settings API was redone in patch 10.0.0, with more breaking changes in 11.0.2. Options code copied from a pre-10.0 tutorial won't match the calls below, and neither will an AI answer trained on those tutorials.Source: [Settings API](https://warcraft.wiki.gg/wiki/Settings_API), checked Sep 28, 2026.

Options.luaCopy Options.lua

```
local addonName, ns = ...

function ns.BuildOptions(db)
    local category = Settings.RegisterVerticalLayoutCategory("Beacon Notes")
    local setting = Settings.RegisterAddOnSetting(
        category, "BeaconNotes_Locked", "locked", db,
        "boolean", "Lock the notes frame", false
    )
    Settings.CreateCheckbox(category, setting, "Prevents dragging the frame.")
    Settings.RegisterAddOnCategory(category)
end

-- Call ns.BuildOptions(ns.db) at the end of your ADDON_LOADED handler.
```

Build the panel inside `ADDON_LOADED`, after the SavedVariables pattern above has filled the table. At file scope the saved table doesn't exist yet, so the setting would bind to `nil`.

## Set a Waypoint Without a Protected Call

A community beta report on Warcraft Forever says `C_SuperTrack.SetSuperTrackedUserWaypoint` is protected on this client. The call fails silently and only adds one to an interface-error counter in the AddOns panel, which "only resets on a full client restart, not on /reload."Source: [Addons](https://warcraftforever.games/addons), checked Sep 28, 2026. The same report names `C_Map.SetUserWaypoint` as the safe way to drop a pin. Treat both as unconfirmed until you test them.

Waypoints are where guide addons live. [Zygor Guides](https://wowforeverguides.com/zygorguides) advertises a "3D Waypoint Arrow" and [RestedXP](https://wowforeverguides.com/restedxp) uses "Follow the arrow" as its slogan, so check how a route addon behaves on the beta before you build your own pin code on top of it.

Waypoint.luaCopy Waypoint.lua

```
local mapID = C_Map.GetBestMapForUnit("player")

if mapID and C_Map.CanSetUserWaypointOnMap(mapID) then
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromVector2D(mapID, pos))
    end
end
```

The same report lists `ChatFrame_OpenChat` and writing secure attributes onto Blizzard's own unit frames as protected too, with `HandleModifiedItemClick` as the safe route for shift-click links. None of the three throws a catchable error, so a `pcall` wrapper won't tell you the call failed. Cross-check a new template against the [addon developer guide](https://wowforeverguides.com/addons/developers) and the [Forever Beacon download](https://wowforeverguides.com/addons/forever-beacon) before you ship it, since nothing on this page has run on a Forever client yet.

## Key Facts

- TOC interface Changed16001 in the Forever Beta row of the Warcraft Wiki TOC table; confirm with /dump select(4, GetBuildInfo())Classic: Classic Era lists 11509 on the same table.Reported
- SavedVariablesReported lost between sessions in mid-September; a September 25 reply says build 70009 loads them againUnverified
- Addon compartment New in ForeverTOC fields are documented for Mainline; not yet tested on a Forever client hereUnverified
- Combat lockdown Same as ClassicProtected frames cannot be shown, hidden or moved in combat; queue until PLAYER\_REGEN\_ENABLEDReported

## Sources

01. [TOC format](https://warcraft.wiki.gg/wiki/TOC_format) Warcraft Wiki
02. [Saving variables between game sessions](https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions) Warcraft Wiki
03. [WOWF Beta: Addon SavedVariables appear to write correctly to disk but are not restored at startup](https://us.forums.blizzard.com/en/wow/t/wowf-beta-addon-savedvariables-appear-to-write-correctly-to-disk-but-are-not-restored-at-startup/2356559) World of Warcraft Forums (player bug report)Sep 21, 2026
04. [Addon compartment](https://warcraft.wiki.gg/wiki/Addon_compartment) Warcraft Wiki
05. [InCombatLockdown](https://warcraft.wiki.gg/wiki/API_InCombatLockdown) Warcraft Wiki
06. [Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values) Warcraft Wiki
07. [Addons](https://warcraftforever.games/addons) Warcraft Forever
08. [WOW\_PROJECT\_ID](https://warcraft.wiki.gg/wiki/WOW_PROJECT_ID) Warcraft Wiki
09. [WoW: Forever Will Have Addon Changes from Midnight](https://www.wowhead.com/news/wow-forever-will-have-addon-changes-from-midnight-382921) WowheadSep 16, 2026
10. [C\_Item.GetItemInfo](https://warcraft.wiki.gg/wiki/API_C_Item.GetItemInfo) Warcraft Wiki
11. [ITEM\_DATA\_LOAD\_RESULT](https://warcraft.wiki.gg/wiki/ITEM_DATA_LOAD_RESULT) Warcraft Wiki
12. [C\_Spell.GetSpellInfo](https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellInfo) Warcraft Wiki
13. [C\_Timer.After](https://warcraft.wiki.gg/wiki/API_C_Timer.After) Warcraft Wiki
14. [C\_AddOns.GetAddOnMetadata](https://warcraft.wiki.gg/wiki/API_C_AddOns.GetAddOnMetadata) Warcraft Wiki
15. [Settings API](https://warcraft.wiki.gg/wiki/Settings_API) Warcraft Wiki
16. [What the WoW Forever beta breaks for addons: secret health values, dead secure snippets, new APIs](https://wowforeverbuilds.com/news/what-the-wow-forever-beta-breaks-for-addons-secret-health-values-dead-secure-sni) WoW Forever BuildsSep 18, 2026
17. [SPELL\_DATA\_LOAD\_RESULT](https://warcraft.wiki.gg/wiki/SPELL_DATA_LOAD_RESULT) Warcraft Wiki
18. [RestedXP home page](https://www.restedxp.com/) RestedXP
19. [Zygor Guides home page](https://zygorguides.com/ref/Decarebia/?campaign=wowforeverguides.com) Zygor Guides
20. [Blizzard client source: ProjectConstants.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua) Blizzard Entertainment (source mirrored by Gethe)
21. [Blizzard client source: SlashCommandsRegistry.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommandsRegistry.lua) Blizzard Entertainment (source mirrored by Gethe)
22. [Blizzard client source: StaticPopup.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_StaticPopup/StaticPopup.lua) Blizzard Entertainment (source mirrored by Gethe)
23. [Lua 5.1 Reference Manual](https://www.lua.org/manual/5.1/manual.html#2.5.9) Lua.org
24. [Blizzard client source: ChatInfoDocumentation.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua) Blizzard Entertainment (source mirrored by Gethe)
25. [Questie repository: Questie\_Forever.toc](https://github.com/Questie/Questie/blob/master/Questie_Forever.toc) GitHub
26. [error handling](https://www.lua.org/manual/5.1/manual.html#2.7)

## Keep Reading

- [AddonsWoW Forever Addons](https://wowforeverguides.com/addons)
- [Leveling addonsWoW Forever Leveling Addons](https://wowforeverguides.com/leveling/addons)
- [Macro builderWoW Forever Class Macros](https://wowforeverguides.com/tools/macros)

Roll on analytics? **Need** = Clicky, GA4 & Microsoft Clarity with cookies and session replays, to see which guides help. **Pass** = no analytics at all. [Privacy](https://wowforeverguides.com/privacy#your-analytics-choice)

NeedPass