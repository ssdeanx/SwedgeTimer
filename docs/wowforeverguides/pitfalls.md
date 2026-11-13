[Skip to main content](https://wowforeverguides.com/addons/pitfalls#main)

Addon guide page 4 of 7

Models copy interface 120001 or 11503 where the wiki lists 16001, and they do math on UnitHealth, which came back as a secret number on build 69913.

## Ask Our Sweaty Degenerate AI About Addon Pitfalls

Interface Numbers, Secret Health Math, WOW\_PROJECT\_ID, Combat Log Gaps, Beta Sound Traps & More?

Anything our guides cover. Answers come from this page and the rest of our guides, with the real values charted and the guide sections linked. It's AI, so check the source before you quote it.

Your question about this page![](https://wowforeverguides.com/assets/tools/ask-goblin/goblin-still.webp)Ask

Try

Addon interface number for ForeverSecret health math in addonsWhy models default to these mistakesCombat log in Forever addonsWOW\_PROJECT\_ID value on ForeverChecking build number and interfacePlaying sound files in betaVerifying a fix before shipping

These are mistakes a model can make when a WoW addon prompt does not name the Forever client. Each pairs the line it may emit with the line to write instead. Porting from Retail or another client? Check each API against your target build before shipping.

Wrong interface number16001Reported

Secret health mathh + 1 failsReported

WOW\_PROJECT\_ID18 (Camelot)Reported

Combat logReported unavailableUnverified

This breakdown is part of the [WoW Forever addon developer guide](https://wowforeverguides.com/addons/developers). To see why these mistakes happen, read [WoW Forever addon patterns](https://wowforeverguides.com/addons/patterns) and the [Forever API cheat sheet](https://wowforeverguides.com/addons/api-cheatsheet). You can head most of them off with the [ready-to-use AI prompts](https://wowforeverguides.com/addons/ai-prompts).

## Twelve Traps

### 0101\. Shipping Interface 120001 or 11503

Models copy Midnight guides or Classic templates. The Warcraft Wiki lists 16001 for the Forever beta. A different number can make the client you are testing flag the addon as out of date.

[![WoW AddOn List with Zygor Guide Viewer 8 checked and the Load out of date AddOns box ticked at the top](https://wowforeverguides.com/assets/leveling/zygor/wow-forever-zygor-addon-list-out-of-date.webp)](https://wowforeverguides.com/assets/leveling/zygor/wow-forever-zygor-addon-list-out-of-date.webp "Open full size")Share Image: WoW AddOn List with Zygor Guide Viewer 8 checked and the Load out of date AddOns box ticked at the top

[Share image link on X (opens in a new tab)](https://x.com/intent/tweet?url=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpitfalls%23wfg-image-c1a98d4cdf&text=WoW+AddOn+List+with+Zygor+Guide+Viewer+8+checked+and+the+Load+out+of+date+AddOns+box+ticked+at+the+top "Share image link on X (opens in a new tab)")[Share image link on Facebook (opens in a new tab)](https://www.facebook.com/sharer/sharer.php?u=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpitfalls%23wfg-image-c1a98d4cdf "Share image link on Facebook (opens in a new tab)")[Share image link on Telegram (opens in a new tab)](https://t.me/share/url?url=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpitfalls%23wfg-image-c1a98d4cdf&text=WoW+AddOn+List+with+Zygor+Guide+Viewer+8+checked+and+the+Load+out+of+date+AddOns+box+ticked+at+the+top "Share image link on Telegram (opens in a new tab)")[Share image link by email](mailto:?subject=WoW%20AddOn%20List%20with%20Zygor%20Guide%20Viewer%208%20checked%20and%20the%20Load%20out%20of%20date%20AddOns%20box%20ticked%20at%20the%20top&body=WoW%20AddOn%20List%20with%20Zygor%20Guide%20Viewer%208%20checked%20and%20the%20Load%20out%20of%20date%20AddOns%20box%20ticked%20at%20the%20top%0Ahttps%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpitfalls%23wfg-image-c1a98d4cdf "Share image link by email")

[Open image](https://wowforeverguides.com/assets/leveling/zygor/wow-forever-zygor-addon-list-out-of-date.webp "Open image")[Download image](https://wowforeverguides.com/assets/leveling/zygor/wow-forever-zygor-addon-list-out-of-date.webp "Download image")

Copy this link

The AddOn List in Zygor's manual, with the Load out of date AddOns box ticked at top right.Source: [Zygor manual: enabling](https://wowforeverguides.com/addons/pitfalls#source-6efc028be6ec)`content.zygorguides.com/support/manual/enabling`.

It writesCopy It writes

```
## Interface: 120001
```

You shipCopy You ship

```
## Interface: 16001
```

### 0202\. Branching on `WOW_PROJECT_ID`

On build 1.60.1.69913, `WOW_PROJECT_ID` reportedly returned 1, the Mainline value. The retained October 12 probe on build **70338** instead records **18**, matching Blizzard's `WOW_PROJECT_CAMELOT` constant. A Classic-only branch misses Forever; a catch-all branch can mistake it for another client. Compare the named constant, then check the feature's API.Source: [Blizzard's Camelot project constants](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua), retained 70338 extract inspected Oct 13, 2026; WFG probe captured Oct 12. The mirror may show a later build.

It writesCopy It writes

```
if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
    -- Assumes every non-Mainline client is Classic; 70338 Forever enters here.
end
```

You shipCopy You ship

```
local isForever = WOW_PROJECT_CAMELOT ~= nil
    and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
if isForever then
    ns:UseForeverPath()
    -- Only a feature that reads the preset needs this capability.
    local canReadPreset = C_GameRules
        and type(C_GameRules.GetForeverExperiencePreset) == "function"
    if canReadPreset then
        local preset = C_GameRules.GetForeverExperiencePreset()
        -- Use preset for your optional preset-specific feature.
    end
end
```

The older Warcraft Wiki example combined `WOW_PROJECT_MAINLINE` with `LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CLASSIC`. That first condition is false on the captured 70338 client. The revised snippet is source-checked, not tested in game; `ns:UseForeverPath()` represents your own addon code.

### 0303\. Adding One to UnitHealth

In a test on build 69913, `type(UnitHealth("player"))` prints `number`, yet `h + 1` fails. WoW Forever Builds saw Grid2 throw "attempt to perform arithmetic on a secret number value".

It writesCopy It writes

```
local h = UnitHealth("player")
local pct = h / UnitHealthMax("player")
```

You shipCopy You ship

```
local bar = ns.healthBar
bar:SetMinMaxValues(0, UnitHealthMax("player"))
bar:SetValue(UnitHealth("player"))
```

This example is not tested in game; check that both setters accept the value on your build.

### 0404\. Printing a Name That Might Be Secret

Warcraft Forever reports that unit and creature names may be secret strings. It also says printing one throws an error and can blank your frame. Check first, then fall back to a value you chose.

It writesCopy It writes

```
print("Hello " .. UnitName("player"))
```

You shipCopy You ship

```
local name = UnitName("player")
if type(issecretvalue) == "function" and issecretvalue(name) then
    name = "adventurer"
end
print("Hello " .. name)
```

### 0505\. GetSpellInfo and GetItemInfo

Both were missing on build 69913, along with `GetSpellBookItemName` and the old talent globals. `C_Spell.GetSpellInfo` returns one table. `C_Item.GetItemInfo` returns the same list of values as the old global.

It writesCopy It writes

```
local name, _, icon = GetSpellInfo(8690)
```

You shipCopy You ship

```
local info = C_Spell.GetSpellInfo(8690)
if not info then
    C_Spell.RequestLoadSpellData(8690)
    return
end
local name, icon = info.name, info.iconID
```

### 0606\. A Damage Meter, Politely Disguised

On Midnight, registering the combat log event throws an error. Testers report it unavailable on Forever. Blizzard said Forever includes a built-in damage meter and cooldown manager.

It writesCopy It writes

```
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
```

You shipCopy You ship

```
-- Presentation only. Let the built-in meter count.
frame:RegisterUnitEvent("UNIT_HEALTH", "player")
```

### 0707\. Click-Cast via a Secure Snippet

Secure snippets failed to compile on build 69913. Even if a later build fixes that, Warcraft Forever lists secure attributes on Blizzard unit frames as protected, and `pcall` does not make the failure go away.

It writesCopy It writes

```
SecureHandlerWrapScript(button, "OnClick", button, [[\
    self:SetAttribute("type", "spell")\
]])
```

You shipCopy You ship

```
-- Own button, plain script, no secure attribute
-- on a Blizzard unit frame.
button:SetScript("OnClick", function()
    -- open your panel, do not cast for the player
end)
```

### 0808\. SavedVariables at File Scope

SavedVariables are `nil` while your file loads. The client loads saved data after your files run, and it replaces whatever your file set. A default assigned at the top is either overwritten or read too early. Players also reported the beta losing saved data between sessions until build 70009.

It writesCopy It writes

```
MyAddonDB = MyAddonDB or { enabled = true }
```

You shipCopy You ship

```
function events:ADDON_LOADED(loaded)
    if loaded ~= addonName then return end
    MyAddonDB = MyAddonDB or {}
    if MyAddonDB.enabled == nil then
        MyAddonDB.enabled = true
    end
    ns.db = MyAddonDB
end
```

See the full lifecycle in the [SavedVariables template](https://wowforeverguides.com/addons/code-templates).

### 0909\. Canceling C\_Timer.After

`After` returns nothing. The timer object comes from `NewTimer` or `NewTicker`.

It writesCopy It writes

```
local t = C_Timer.After(5, func)
t:Cancel()
```

You shipCopy You ship

```
local t = C_Timer.NewTimer(5, func)
t:Cancel()
```

### 1010\. Protected Calls Hidden in Pcall

Warcraft Forever reports that `ChatFrame_OpenChat`, `C_SuperTrack.SetSuperTrackedUserWaypoint` and secure attributes on Blizzard frames fail without a Lua error. The only symptom is an interface-action counter that `/reload` does not reset.

It writesCopy It writes

```
pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
```

You shipCopy You ship

```
local point = UiMapPoint.CreateFromCoordinates(uiMapID, x, y)
C_Map.SetUserWaypoint(point)
```

`C_Map.SetUserWaypoint` places the pin; the wiki documents `C_SuperTrack.SetSuperTrackedUserWaypoint` as the separate call that tracks it. Warcraft Forever's page, captured September 28, lists that call as protected but names no client build, so retest on yours.

### 1111\. Faction Tests That Lie

Warcraft Forever reports that `UnitIsEnemy` and `UnitCanAttack` mean "attackable right now" on this client, not "other faction": both answer false for an unflagged enemy, in a sanctuary or on another shard. Its secret-value list names `UnitCanAttack`, not `UnitIsEnemy`, as a secret boolean. The report names no build, so retest on yours.

It writesCopy It writes

```
if UnitIsEnemy("player", unit) then
```

You shipCopy You ship

```
local them = UnitFactionGroup(unit)
local mine = UnitFactionGroup("player")
if them and mine and them ~= mine then
```

### 1212\. Slash Commands That Never Register

The global must be `SLASH_NAME1` and the `SlashCmdList` key must be the same `NAME`, spelled the same way. A local, or a key that does not match, never registers.

It writesCopy It writes

```
local SLASH_fb1 = "/fb"
SlashCmdList.fb = function() end
```

You shipCopy You ship

```
SLASH_FOREVERBEACON1 = "/fb"
SlashCmdList["FOREVERBEACON"] = function(msg)
end
```

For complete safe bars, combat queues and addon compartments, see the [code templates](https://wowforeverguides.com/addons/code-templates).

## Four More Traps From the Beta

The twelve above cover the biggest breaks. These four are smaller. Traps 13 and 14 are unverified community beta reports from Warcraft Forever. Traps 15 and 16 come from the Warcraft Wiki's Mainline API pages, the UI family Forever runs. They have not been retested on a Forever build.

### 1313\. Playing a Sound File the Classic Way

Warcraft Forever reports that `PlaySoundFile` with a `Sound\Interface\*.ogg` path fails silently on this client. Nothing errors and nothing prints; the sound never plays.

It writesCopy It writes

```
PlaySoundFile("Sound\\Interface\\LevelUp.ogg")
```

You shipCopy You ship

```
-- Warcraft Wiki, PlaySound: play by SoundKitID, not a file path.
PlaySound(SOUNDKIT.READY_CHECK)
```

The wiki's `PlaySound` page documents playing by SoundKitID or a `SOUNDKIT` key. Warcraft Forever also says to check the master volume before blaming the addon.

### 1414\. Trusting a Nameplate the Instant It Appears

Warcraft Forever reports that `NAME_PLATE_UNIT_ADDED` fires before the unit is populated, and that plate frames carry no `namePlateUnitToken` on this client. Reading the unit in the same handler gets nothing useful.

It writesCopy It writes

```
frame:SetScript("OnEvent", function(self, event, unit)
    self.name:SetText(UnitName(unit))
end)
```

You shipCopy You ship

```
frame:SetScript("OnEvent", function(self, event, unit)
    C_Timer.After(0, function()
        self.name:SetText(UnitName(unit))
    end)
end)
-- Or sweep nameplate1..nameplate40 yourself a moment later.
```

### 1515\. Assuming a Metadata Lookup Fails Quietly

The wiki says `C_AddOns.GetAddOnMetadata`, unlike the old global, raises an "Invalid AddOn name" error when the addon does not exist. A model that ports the old call and keeps its `nil` check would stop the file on a missing optional dependency. Test the guarded pattern below on your Forever build.

It writesCopy It writes

```
local ver = C_AddOns.GetAddOnMetadata("SomeOtherAddon", "Version")
if not ver then return end
```

You shipCopy You ship

```
local ok, ver = pcall(C_AddOns.GetAddOnMetadata, "SomeOtherAddon", "Version")
if not ok or not ver then return end
```

### 1616\. Wiring the Settings Panel Through the Old Globals

The wiki dates the Settings API rewrite to patch 10.0.0, with more breaking changes in 11.0.2. Its documented pattern registers a category and opens it through `Settings`, not the older `InterfaceOptionsFrame_OpenToCategory` that Classic Era templates call.

It writesCopy It writes

```
InterfaceOptionsFrame_OpenToCategory(MyAddonOptionsPanel)
```

You shipCopy You ship

```
local category = Settings.RegisterVerticalLayoutCategory("My Addon")
Settings.RegisterAddOnCategory(category)
-- Later, from a slash command:
Settings.OpenToCategory(category:GetID())
```

Register the category once at load, then open it from a slash command or an addon compartment entry like the one in the [Forever Beacon sample addon](https://wowforeverguides.com/addons/forever-beacon).

## Why Models Default to These Mistakes

These examples show a risk, not a measured error rate. Without the target client named, a model asked for a health bar may reach for arithmetic, and one asked for options may call a panel API from an older interface.

[![](https://wowforeverguides.com/assets/video-posters/C8AYMjWB-Rk.webp?v=37e6509a674a)Plays from YouTube](https://www.youtube.com/watch?v=C8AYMjWB-Rk)

Kenneth Henseler goes through four errors where an AI said a function did not exist when it did, September 25, 2026.

The fix is context, not a cleverer prompt. Tell the model the interface number, the project ID and the APIs the beta reports, and start from the [prompt templates for Forever addons](https://wowforeverguides.com/addons/ai-prompts).

Established addons are adapting the same way, by testing on the beta. [RestedXP](https://wowforeverguides.com/restedxp)'s free guide addon has shipped Forever route fixes in its GitHub releases through September 2026, and [Zygor Guides](https://wowforeverguides.com/zygorguides) says its Forever guides reach Elite subscribers at launch.

[![RestedXP RXPGuides GitHub release v4.11.12 from September 30, 2026, listing Barrens, Mulgore, Teldrassil and dungeon guide changes for Forever](https://wowforeverguides.com/assets/leveling/restedxp/wow-forever-restedxp-github-release-v4-11-12.webp)](https://wowforeverguides.com/assets/leveling/restedxp/wow-forever-restedxp-github-release-v4-11-12.webp "Open full size")Share Image: RestedXP RXPGuides GitHub release v4.11.12 from September 30, 2026, listing Barrens, Mulgore, Teldrassil and dungeon guide changes for Forever

[Share image link on X (opens in a new tab)](https://x.com/intent/tweet?url=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpitfalls%23wfg-image-ab489dd31f&text=RestedXP+RXPGuides+GitHub+release+v4.11.12+from+September+30%2C+2026%2C+listing+Barrens%2C+Mulgore%2C+Teldrassil+and+dungeon+guide+changes+for+Forever "Share image link on X (opens in a new tab)")[Share image link on Facebook (opens in a new tab)](https://www.facebook.com/sharer/sharer.php?u=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpitfalls%23wfg-image-ab489dd31f "Share image link on Facebook (opens in a new tab)")[Share image link on Telegram (opens in a new tab)](https://t.me/share/url?url=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpitfalls%23wfg-image-ab489dd31f&text=RestedXP+RXPGuides+GitHub+release+v4.11.12+from+September+30%2C+2026%2C+listing+Barrens%2C+Mulgore%2C+Teldrassil+and+dungeon+guide+changes+for+Forever "Share image link on Telegram (opens in a new tab)")[Share image link by email](mailto:?subject=RestedXP%20RXPGuides%20GitHub%20release%20v4.11.12%20from%20September%2030%2C%202026%2C%20listing%20Barrens%2C%20Mulgore%2C%20Teldrassil%20and%20dungeon%20guide%20changes%20for%20Forever&body=RestedXP%20RXPGuides%20GitHub%20release%20v4.11.12%20from%20September%2030%2C%202026%2C%20listing%20Barrens%2C%20Mulgore%2C%20Teldrassil%20and%20dungeon%20guide%20changes%20for%20Forever%0Ahttps%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpitfalls%23wfg-image-ab489dd31f "Share image link by email")

[Open image](https://wowforeverguides.com/assets/leveling/restedxp/wow-forever-restedxp-github-release-v4-11-12.webp "Open image")[Download image](https://wowforeverguides.com/assets/leveling/restedxp/wow-forever-restedxp-github-release-v4-11-12.webp "Download image")

Copy this link

RestedXP's v4.11.12 release notes list Forever changes for Barrens, Mulgore, Teldrassil and its dungeon guides.Source: [RXPGuides releases on GitHub](https://github.com/RestedXP/RXPGuides/releases), captured Sep 30, 2026.

## Verifying a Fix Before You Ship It

None of these sixteen fixes is guaranteed to survive the next beta build. Retest each one on the build you are running.

Start with `/run print(select(2, GetBuildInfo()), select(4, GetBuildInfo()))`, which prints the build and the interface number. Then run WoW Forever Builds' health test from trap 03: `/run local h = UnitHealth("player"); print(type(h), pcall(function() return h + 1 end))`. On build 69913 it printed `number false`: `pcall` caught an error, so the addition was refused. If it prints `true`, that read is no longer secret on your build. That result covers only this test; test the status bar example separately.

For trap 08, log out fully and back in, not just `/reload`, and check that your saved table survived. Players reported a SavedVariables restore bug from Sep 21, 2026, and one player said build 70009 fixed it on Sep 25. Blizzard hasn't confirmed a fix.

Test trap 11 against an unflagged enemy player, in a sanctuary or on another shard. Warcraft Forever reports that `UnitIsEnemy` and `UnitCanAttack` both return false there.

For the protected calls in traps 07 and 10, watch the AddOns panel's interface-action counter rather than `pcall`'s return value. `/reload` does not reset that counter, so restart the client before you retest, or an old count will make a working fix look broken.

Note the build number next to any fix you rely on, the way the [API cheat sheet](https://wowforeverguides.com/addons/api-cheatsheet) marks rows observed on build 69913. A trap fixed on one build can reopen on the next.

## Key Facts

- Wrong interface number ChangedModels copy 120001 or 11503; the wiki lists 16001 for the Forever betaReported
- Secret health math Changedtype() says number, but h + 1 fails; pcall returns false instead of a sumReported
- WOW\_PROJECT\_ID Changed18 (WOW\_PROJECT\_CAMELOT) in the October 12 WFG probe on build 70338; older build 69913 reported 1Classic: Classic Era returns 2 (WOW\_PROJECT\_CLASSIC).Reported
- Combat log RemovedRegistering COMBAT\_LOG\_EVENT\_UNFILTERED errors on Midnight; reported unavailable on ForeverUnverified

## Sources

01. [What the WoW Forever beta breaks for addons: secret health values, dead secure snippets, new APIs](https://wowforeverbuilds.com/news/what-the-wow-forever-beta-breaks-for-addons-secret-health-values-dead-secure-sni) WoW Forever BuildsSep 18, 2026
02. [Addons](https://warcraftforever.games/addons) Warcraft Forever
03. [TOC format](https://warcraft.wiki.gg/wiki/TOC_format) Warcraft Wiki
04. [Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values) Warcraft Wiki
05. [Patch 12.0.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) Warcraft Wiki
06. [C\_Item.GetItemInfo](https://warcraft.wiki.gg/wiki/API_C_Item.GetItemInfo) Warcraft Wiki
07. [Saving variables between game sessions](https://warcraft.wiki.gg/wiki/Saving_variables_between_game_sessions) Warcraft Wiki
08. [WOWF Beta: Addon SavedVariables appear to write correctly to disk but are not restored at startup](https://us.forums.blizzard.com/en/wow/t/wowf-beta-addon-savedvariables-appear-to-write-correctly-to-disk-but-are-not-restored-at-startup/2356559) World of Warcraft Forums (player bug report)Sep 21, 2026
09. [C\_Map.SetUserWaypoint](https://warcraft.wiki.gg/wiki/API_C_Map.SetUserWaypoint) Warcraft Wiki
10. [C\_AddOns.GetAddOnMetadata](https://warcraft.wiki.gg/wiki/API_C_AddOns.GetAddOnMetadata) Warcraft Wiki
11. [Settings API](https://warcraft.wiki.gg/wiki/Settings_API) Warcraft Wiki
12. [PlaySound](https://warcraft.wiki.gg/wiki/API_PlaySound) Warcraft Wiki
13. [RXPGuides releases](https://github.com/RestedXP/RXPGuides/releases) RestedXP (GitHub)
14. [Zygor's World of Warcraft Forever guides launching this November](https://zygorguides.com/blog/zygors-world-of-warcraft-forever-guides-launching-this-november/ref/Decarebia/?campaign=wowforeverguides.com) Zygor GuidesSep 15, 2026
15. [Blizzard client source: ProjectConstants.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua) Blizzard Entertainment (source mirrored by Gethe)
16. [Zygor manual: enabling](https://content.zygorguides.com/support/manual/enabling)

## Keep Reading

- [AddonsWoW Forever Addons](https://wowforeverguides.com/addons)
- [Leveling addonsWoW Forever Leveling Addons](https://wowforeverguides.com/leveling/addons)
- [Macro builderWoW Forever Class Macros](https://wowforeverguides.com/tools/macros)

Roll on analytics? **Need** = Clicky, GA4 & Microsoft Clarity with cookies and session replays, to see which guides help. **Pass** = no analytics at all. [Privacy](https://wowforeverguides.com/privacy#your-analytics-choice)

NeedPass