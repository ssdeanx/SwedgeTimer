[Skip to main content](https://wowforeverguides.com/addons/patterns#main)

Addon guide page 2 of 7

Forever shares Mainline's UI. On build 70338, its project ID is 18 (WOW\_PROJECT\_CAMELOT); compare that constant, check the feature's API and retest on your current client.

## Ask Our Sweaty Degenerate AI About Forever Addon Patterns

Secret Values, Camelot Detection, Aura Containers, Settings Panels & More?

Anything our guides cover. Answers come from this page and the rest of our guides, with the real values charted and the guide sections linked. It's AI, so check the source before you quote it.

Your question about this page![](https://wowforeverguides.com/assets/tools/ask-goblin/goblin-still.webp)Ask

Try

Detect Forever addon clientForever WOW\_PROJECT\_ID valueAddon compartment versus minimap buttonSecret values in addonsPorting Midnight addons to ForeverPorting Classic Era addonsSettings panels on ForeverWhat Forever addons can buildAura containers on Forever

Classic Era is permissive and old. Midnight is restrictive and current. Forever is the original world running the Midnight UI family. Write for that overlap, or the addon won't load, or it loads and reports the wrong thing.

Addon APIModern APIConfirmed

API familyMainline 12.1.5Reported

WOW\_PROJECT\_ID18 (Camelot)Reported

Player healthSecret numberReported

This pillar is part of the [WoW Forever addon developer guide](https://wowforeverguides.com/addons/developers), alongside the [Forever API cheat sheet](https://wowforeverguides.com/addons/api-cheatsheet), [common AI addon pitfalls](https://wowforeverguides.com/addons/pitfalls) and the [Forever Beacon reference addon](https://wowforeverguides.com/addons/forever-beacon).

## Three Clients, One Mistake

The trap models and developers fall into most often is treating Forever as Classic Era with new zones, or as Midnight with the old world. It is neither.

| Surface | Classic Era | Midnight | Forever |
| --- | --- | --- | --- |
| **World** | Original world | Current expansion | Original world, new zones, cap 60 |
| **UI code** | Classic API | Mainline, 12.x | Mainline family, game type Camelot |
| **Interface** | 11509 | 120100 | 16001 on the beta |
| **Combat log** | Open to addons | Registering CLEU errors | Reported unavailable |
| **Health math** | Plain numbers | Secret under restrictions | Secret number seen on build 69913 |
| **`WOW_PROJECT_ID`** | 2 | 1 | 18 (`WOW_PROJECT_CAMELOT`) on build 70338; 1 reported on 69913 |

Interface numbers come from the Warcraft Wiki TOC table, and the Midnight combat log change comes from the wiki's Patch 12.0.0 API notes. The beta rows in the Forever column are community tests.

## Detect Forever Without Trusting the Project ID Alone

The older build 69913 report returned `WOW_PROJECT_ID = 1`, the Mainline value. The retained October 12 probe on build **70338** instead records **18**, and Blizzard's client constants name it `WOW_PROJECT_CAMELOT`. Compare that named constant when it exists, then check the API your feature needs. Blizzard said it would rename the internal name Camelot before launch, so retest it on your build.Source: [Blizzard's Camelot project constants](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua), retained 70338 extract inspected Oct 13, 2026; WFG probe captured Oct 12. The mirror may show a later build.

Detect.luaCopy Detect.lua

```
local function IsForever()
    return WOW_PROJECT_CAMELOT ~= nil
        and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
end

-- Example capability: check the API your feature actually uses.
local canReadPreset = C_GameRules
    and type(C_GameRules.GetForeverExperiencePreset) == "function"

local function HasSecrets()
    return type(issecretvalue) == "function"
end

-- For logs only: 16001 on the beta. Do not hardcode it as the test.
local iface = select(4, GetBuildInfo())
```

Check this probe against the [API reference tables](https://wowforeverguides.com/addons/api-cheatsheet) and the traps in [Twelve traps to avoid](https://wowforeverguides.com/addons/pitfalls), and run it on your build before you rely on it.

The retained Warcraft Wiki example pairs `WOW_PROJECT_MAINLINE` with `LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CLASSIC`, or reads a TOC game-type variable. Its Mainline project-ID condition is false on the captured 70338 client. Mainline UI architecture does not imply a Mainline project ID. The revised example is source-checked, not tested in game.

## The Secret Pipeline

Midnight introduced secret values to limit combat automation, and Blizzard said Forever has them too.

1. Call the API.
`type()` still reports number, string or boolean.

2. Ask `issecretvalue`
before you compare, branch on or print it.

3. If secret, use a widget.
Otherwise show a fixed label.

4. Don't trust `pcall` with protected actions.


You still get a value from the call, with its real type. `StatusBar:SetValue` is the wiki's example of a widget that accepts secrets. Do not wrap a protected action in `pcall` and call it handled: testers report the failure can be silent and sticky.

Under the Warcraft Wiki's Midnight rules, addon code can store secrets, pass them to functions, and concatenate or `string.format` them. It cannot do math on them, compare them, test them as booleans, index them or use them as table keys. The rules block those operations; an attempt throws a Lua error right away. Warcraft Forever reports that printing a secret throws on Forever, so guard before you print.

[![Questie GitHub release v12.0.1+v1.0.3 notes, with Added Forever client support first under New Features and Forever fixes below](https://wowforeverguides.com/assets/leveling/free-addons/wow-forever-questie-github-release-forever.webp)](https://wowforeverguides.com/assets/leveling/free-addons/wow-forever-questie-github-release-forever.webp "Open full size")Share Image: Questie GitHub release v12.0.1+v1.0.3 notes, with Added Forever client support first under New Features and Forever fixes below

[Share image link on X (opens in a new tab)](https://x.com/intent/tweet?url=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpatterns%23wfg-image-f6c6f62517&text=Questie+GitHub+release+v12.0.1%2Bv1.0.3+notes%2C+with+Added+Forever+client+support+first+under+New+Features+and+Forever+fixes+below "Share image link on X (opens in a new tab)")[Share image link on Facebook (opens in a new tab)](https://www.facebook.com/sharer/sharer.php?u=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpatterns%23wfg-image-f6c6f62517 "Share image link on Facebook (opens in a new tab)")[Share image link on Telegram (opens in a new tab)](https://t.me/share/url?url=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpatterns%23wfg-image-f6c6f62517&text=Questie+GitHub+release+v12.0.1%2Bv1.0.3+notes%2C+with+Added+Forever+client+support+first+under+New+Features+and+Forever+fixes+below "Share image link on Telegram (opens in a new tab)")[Share image link by email](mailto:?subject=Questie%20GitHub%20release%20v12.0.1%2Bv1.0.3%20notes%2C%20with%20Added%20Forever%20client%20support%20first%20under%20New%20Features%20and%20Forever%20fixes%20below&body=Questie%20GitHub%20release%20v12.0.1%2Bv1.0.3%20notes%2C%20with%20Added%20Forever%20client%20support%20first%20under%20New%20Features%20and%20Forever%20fixes%20below%0Ahttps%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpatterns%23wfg-image-f6c6f62517 "Share image link by email")

[Open image](https://wowforeverguides.com/assets/leveling/free-addons/wow-forever-questie-github-release-forever.webp "Open image")[Download image](https://wowforeverguides.com/assets/leveling/free-addons/wow-forever-questie-github-release-forever.webp "Download image")

Copy this link

Questie's release notes list a fix that adds safeguards against manipulating Secret Values in Forever.Source: [Questie release notes on GitHub](https://github.com/Questie/Questie/releases/tag/bundle/v12.0.1%2Bv1.0.3), captured Sep 30, 2026.

### Test You Can Paste in Game

Chat commandCopy Chat command

```
/run local h = UnitHealth("player"); print(type(h), pcall(function() return h + 1 end))
```

On build 69913 this printed `number false`. A `false` from `pcall` means the engine refused the addition. For status-bar examples, see the [code templates](https://wowforeverguides.com/addons/code-templates) and the [downloadable Beacon sample](https://wowforeverguides.com/addons/forever-beacon), then check them on your build.

## Auras Are Containers, Not Tables You Own

Blizzard said the `AuraContainer` and `AuraButton` changes from 12.1.0 are available on Forever, and that later UI changes should land on both Standard and Forever. The wiki's Midnight notes flag aura data as secret while combat restrictions are active. What holds up is to let Blizzard's aura frames decide what to show, skin what they give you, and never read the aura payload to decide a play.

## What Is Worth Building Now

Know what the client allows before you prompt a model or port old code:

| Surface | Verdict | Why |
| --- | --- | --- |
| **Bags, bank, vendor, tooltips** | Build | Presents data the UI already shows |
| **Quest log, map pins, route notes** | Build | `C_Map.SetUserWaypoint` is the safe pin, not the super-track call |
| **Nameplates and unit art** | Build carefully | Warcraft Forever: `NAME_PLATE_UNIT_ADDED` can fire before the unit is populated. Check again a moment later |
| **Secret-safe personal strip** | Build | The [Forever Beacon sample](https://wowforeverguides.com/addons/forever-beacon) is the reference |
| **Damage or healing meter** | Do not | Built-in meter; do not assume addon access to its restricted data |
| **Classic WeakAuras packs** | Do not port | Wowhead: WeakAuras stopped development before Midnight |
| **Click-cast healer frames** | Wait | Secure snippets failed to compile on 69913; may be a bug |
| **Action bar paging via snippets** | Wait | Same compile failure |

## Porting Order

### From Midnight

Add `16001` to the interface line, or ship a `_Camelot.toc`. Remove any branch that reads project ID `1` as "this is Midnight" and turns on Midnight-only features. Retest every secret-value path on the Forever client before release.

### From Classic Era

Treat it as a new addon that may keep your `SavedVariables` schema. Replace global item and spell calls with `C_Item` and `C_Spell` and their load events. The retained community notes report combat-log access unavailable. Test listener registration and reader results on your target build before you rely on the feature or delete it. Replace `PlaySoundFile` on interface `.ogg` paths with `PlaySound` and a `SOUNDKIT` ID. Replace faction checks that use `UnitIsEnemy`. Then read the file again for any math on health. For starter code, see the [copy-paste code templates](https://wowforeverguides.com/addons/code-templates).

## Beta Defects Versus Design

Label these in your patch notes so players don't blame your addon:

- **Secure snippet compilation failure:** WoW Forever Builds suspects a bug.
- **SavedVariables not loading:** reported after a restart in mid-September.
- **`WOW_PROJECT_ID` of 1:** historical build 69913 report.

Retest snippets before you replace a working click-cast with a weaker one for good. Players reported saved data missing, and a September 25 forum reply says build 70009 loads it again; retest before you add workarounds. WoW Forever Builds left the project ID unclear on build 69913. The retained 70338 probe records 18, named `WOW_PROJECT_CAMELOT`, despite Forever remaining in the Mainline family. Retest each build; compare the named constant and check feature APIs.

## The Addon Compartment Replaces the Minimap Button

Ask a model for a toggle button and it reaches for a minimap icon library from a Classic Era tutorial. Mainline has a lighter option: the addon compartment, a dropdown off the minimap that lists one entry per registered addon.Source: [Addon compartment](https://warcraft.wiki.gg/wiki/Addon_compartment), checked Sep 28, 2026.

The beta client includes it. In build 1.60.1.70009, the Blizzard\_Minimap TOC loads `AddonCompartment.lua` for the mainline game type, and a neighboring line that excludes camelot shows camelot counts as mainline.**Reported, client file read** An entry on a live Forever screen is still unconfirmed, as [Beacon's compartment notes](https://wowforeverguides.com/addons/forever-beacon) point out.

### Registering With the TOC or With Lua

Three TOC fields register an entry with no Lua call: `AddonCompartmentFunc` for the click, plus the optional `AddonCompartmentFuncOnEnter` and `AddonCompartmentFuncOnLeave` for the tooltip. The client calls the global functions you name, and loads a load-on-demand addon first if it has to.

An addon that changes its label or icon at runtime uses `AddonCompartmentFrame:RegisterAddon` instead, passing a table with `text`, `icon` and `func`. The wiki says that table resembles legacy `UIDropDownMenu` button setup, so Retail examples transfer.

### When a Minimap Button Still Makes Sense

A custom minimap button brings its own saved position and drag code, usually through a library. A compartment entry needs neither, because the client owns the menu. Start with the compartment. The same TOC still loads `MinimapButtonTemplate` for camelot, so a real minimap icon is still possible if players ask for one.

## Options Panels Follow the Same Swap

Settings follow the same rule: write Mainline code, not a Classic template. The wiki says the Settings API was rebuilt in patch 10.0.0, with more breaking changes in 11.0.2.Source: [Settings API](https://warcraft.wiki.gg/wiki/Settings_API), checked Sep 28, 2026. The beta's `Blizzard_Settings.lua` defines `Settings.RegisterAddOnCategory`, `Settings.RegisterAddOnSetting` and `Settings.OpenToCategory`.**Reported, client file read**

`RegisterAddOnCategory` adds your category to the game's options window. `RegisterAddOnSetting` binds a checkbox or slider to a key in your saved variables table, so the click writes the value with no separate handler to keep in sync. The [settings panel template](https://wowforeverguides.com/addons/code-templates) has a working checkbox with a callback.

[![WoW Forever Options window on Languages and Social, with the Preferred Online Language dropdown listing English, LatAm Spanish and Brazilian Portuguese](https://wowforeverguides.com/assets/blizzard/wow-forever-options-preferred-language.webp)](https://wowforeverguides.com/assets/blizzard/wow-forever-options-preferred-language.webp "Open full size")Share Image: WoW Forever Options window on Languages and Social, with the Preferred Online Language dropdown listing English, LatAm Spanish and Brazilian Portuguese

[Share image link on X (opens in a new tab)](https://x.com/intent/tweet?url=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpatterns%23wfg-image-358d3c280f&text=WoW+Forever+Options+window+on+Languages+and+Social%2C+with+the+Preferred+Online+Language+dropdown+listing+English%2C+LatAm+Spanish+and+Brazilian+Portuguese "Share image link on X (opens in a new tab)")[Share image link on Facebook (opens in a new tab)](https://www.facebook.com/sharer/sharer.php?u=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpatterns%23wfg-image-358d3c280f "Share image link on Facebook (opens in a new tab)")[Share image link on Telegram (opens in a new tab)](https://t.me/share/url?url=https%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpatterns%23wfg-image-358d3c280f&text=WoW+Forever+Options+window+on+Languages+and+Social%2C+with+the+Preferred+Online+Language+dropdown+listing+English%2C+LatAm+Spanish+and+Brazilian+Portuguese "Share image link on Telegram (opens in a new tab)")[Share image link by email](mailto:?subject=WoW%20Forever%20Options%20window%20on%20Languages%20and%20Social%2C%20with%20the%20Preferred%20Online%20Language%20dropdown%20listing%20English%2C%20LatAm%20Spanish%20and%20Brazilian%20Portuguese&body=WoW%20Forever%20Options%20window%20on%20Languages%20and%20Social%2C%20with%20the%20Preferred%20Online%20Language%20dropdown%20listing%20English%2C%20LatAm%20Spanish%20and%20Brazilian%20Portuguese%0Ahttps%3A%2F%2Fwowforeverguides.com%2Faddons%2Fpatterns%23wfg-image-358d3c280f "Share image link by email")

[Open image](https://wowforeverguides.com/assets/blizzard/wow-forever-options-preferred-language.webp "Open image")[Download image](https://wowforeverguides.com/assets/blizzard/wow-forever-options-preferred-language.webp "Download image")

Copy this link

The WoW Forever Options window, as Blizzard showed it in its Preferred Online Language screenshot.Source: [Blizzard, Deep Dive Panel Recap](https://worldofwarcraft.blizzard.com/en-us/news/24303313/world-of-warcraft-forever-deep-dive-panel-recap)

### Opening Options From the Compartment

A compartment click can call `Settings.OpenToCategory` instead of showing a frame you built. In the beta file it hands off to `C_SettingsUtil.OpenSettingsPanel`, a client function. Neither the wiki nor that file says whether the call works in combat, so test it in combat, or queue it until `PLAYER_REGEN_ENABLED` the way Beacon does.

### Route Addons Follow the Same Client

Quest and route addons are the biggest "Build" row in the table above, and two guide makers already sell them for Forever. [RestedXP](https://wowforeverguides.com/restedxp) opened Forever orders on September 14, 2026. [Zygor Guides](https://wowforeverguides.com/zygorguides) says Elite members get its Forever guides at launch. Both run inside this client, so the same compartment and settings rules apply to them.

The [prompt templates for Forever addons](https://wowforeverguides.com/addons/ai-prompts) build both patterns into the system prompt, so a model reaches for the compartment and the Settings API before a library.

## Key Facts

- Addon API ChangedForever uses the modern addon API, with Midnight's combat restrictionsClassic: Classic Era keeps the older API with the combat log open to addons.Confirmed
- API family ChangedShares Mainline UI architecture and "the vast majority of APIs available in 12.1.5"Reported
- WOW\_PROJECT\_ID Changed18 (WOW\_PROJECT\_CAMELOT) in the October 12 WFG probe on build 70338; older build 69913 reported 1Classic: Classic Era returns 2 (WOW\_PROJECT\_CLASSIC).Reported
- Combat log RemovedCombatLogGetCurrentEventInfo reported unavailable to addons on the betaClassic: Classic Era addons read every event through COMBAT\_LOG\_EVENT\_UNFILTERED.Unverified
- Player health ChangedUnitHealth came back as a secret number: type() says number, adding 1 failsClassic: Classic Era returns a plain number addons can do math on.Reported

## Sources

01. [World of Warcraft Developer Q&A (September 17 stream), add-on answer at 01:20:52](https://www.youtube.com/watch?v=Y5zzSMSVhRo&t=4852s) Blizzard Entertainment (YouTube)Sep 17, 2026
02. [WoW: Forever Will Have Addon Changes from Midnight](https://www.wowhead.com/news/wow-forever-will-have-addon-changes-from-midnight-382921) WowheadSep 16, 2026
03. [What the WoW Forever beta breaks for addons: secret health values, dead secure snippets, new APIs](https://wowforeverbuilds.com/news/what-the-wow-forever-beta-breaks-for-addons-secret-health-values-dead-secure-sni) WoW Forever BuildsSep 18, 2026
04. [Addons](https://warcraftforever.games/addons) Warcraft Forever
05. [TOC format](https://warcraft.wiki.gg/wiki/TOC_format) Warcraft Wiki
06. [WOW\_PROJECT\_ID](https://warcraft.wiki.gg/wiki/WOW_PROJECT_ID) Warcraft Wiki
07. [Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values) Warcraft Wiki
08. [Patch 12.0.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) Warcraft Wiki
09. [WOWF Beta: Addon SavedVariables appear to write correctly to disk but are not restored at startup](https://us.forums.blizzard.com/en/wow/t/wowf-beta-addon-savedvariables-appear-to-write-correctly-to-disk-but-are-not-restored-at-startup/2356559) World of Warcraft Forums (player bug report)Sep 21, 2026
10. [Addon compartment](https://warcraft.wiki.gg/wiki/Addon_compartment) Warcraft Wiki
11. [Settings API](https://warcraft.wiki.gg/wiki/Settings_API) Warcraft Wiki
12. [World of Warcraft Forever guides are up for order now](https://community.restedxp.com/world-of-warcraft-forever-guides-are-up-for-order-now/) RestedXP
13. [Zygor's World of Warcraft: Forever guides launching this November](https://zygorguides.com/blog/zygors-world-of-warcraft-forever-guides-launching-this-november/ref/Decarebia/?campaign=wowforeverguides.com) Zygor Guides
14. [Blizzard client source: ProjectConstants.lua (retained build 70338; mirror may change)](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua) Blizzard Entertainment (source mirrored by Gethe)
15. [Questie release notes on GitHub](https://github.com/Questie/Questie/releases/tag/bundle/v12.0.1%2Bv1.0.3)
16. [Blizzard, Deep Dive Panel Recap](https://worldofwarcraft.blizzard.com/en-us/news/24303313/world-of-warcraft-forever-deep-dive-panel-recap)

## Keep Reading

- [AddonsWoW Forever Addons](https://wowforeverguides.com/addons)
- [Leveling addonsWoW Forever Leveling Addons](https://wowforeverguides.com/leveling/addons)
- [Macro builderWoW Forever Class Macros](https://wowforeverguides.com/tools/macros)

Roll on analytics? **Need** = Clicky, GA4 & Microsoft Clarity with cookies and session replays, to see which guides help. **Pass** = no analytics at all. [Privacy](https://wowforeverguides.com/privacy#your-analytics-choice)

NeedPass