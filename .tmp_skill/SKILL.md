---
name: wow-forever-addon-audit
description: "Audits WoW addons for WoW Forever compatibility from local wow-ui-source, traces load failures, gates Forever-only behavior without removing shared code, verifies Forever spell and aura IDs, selects secret-return distance APIs for Forever bars, audits Forever Camelot talent and spec readouts using C_Traits, and audits Forever HUD, aura-row, and hunter range-bar behavior including truncating integer HUD text, visible Auto Shot cast anchoring, HUNTER_GAP clearance, and bottom-bar helper_state consumption; use when asked to audit WoW Forever compatibility, gate Forever player buffs, target debuffs, or shaman weaving, verify Maelstrom, Lightning Bolt, or Chain Lightning IDs, wire the Forever module into the TOC, fix secret aura data, fix a hidden Forever hunter distance bar, audit Forever loot tooltip or zone row behavior, document the classic versus Camelot split in AGENTS.md, fix Forever HUD float text, fix aura icons covering Auto Shot, or fix a grey bottom range bar."
whenToUse: "Use when a user asks for a WoW Forever audit, Forever-only gating, Forever player buffs, target debuffs, shaman weaving, Maelstrom Weapon aura verification, Lightning Bolt or Chain Lightning rank IDs, Serpent Sting or Flame Shock own-caster tracking, AuraContainer native groups, secret-value conversion guards, TOC Interface updates to 16001, a Forever hunter distance bar that stays hidden on a mob, ClosestUnitPosition or UnitDistanceSquared fallback selection, a read-only post-revert audit in SuperSwingTimer-WoW, Forever Camelot talent or spec audits, C_Traits GetGroupDisplayInfoByTreeID or GetGroupCurrencyInfo, INSPECT_TRAIT_CONFIG_ID, validInspect, dual spec, primary tree by highest points, secondary tree only when dual spec is present, Forever loot tooltip native behavior, a Forever zone row, a Camelot-only spec icon or tree table, or documenting classic versus Camelot in AGENTS.md. a Forever HUD truncating integer formatter, CreateNumericRuleFormatter with threshold 0, step 1, rounding Down, and integer format, a DurationTextBinding SetFontString on a dedicated native FontString, guarded GCD_OBJECT opaque-handle pass-through, an aura row anchored to a visible Auto Shot cast bar with a 12px gap, a no-cast gap of at least 15px above the ranged bar, HUNTER_GAP pixel proof, a bottom range bar consuming left helper_state with stale-clear, an IsSpellInRange spell-band fallback, or mutation-proven guards."
---

# WoW Forever Addon Audit

## Steps

1. Locate local source of truth first (prefer source over web search).
   - Run: cd /home/sam/wow-ui-source and git show origin/forever:version.txt to verify the Forever version (16001).
   - Extract Blizzard TOC Interface values: git grep -n "Interface" origin/forever -- *.toc
   - Inspect AddonList incompatible logic: git grep -n incompatible origin/forever -- Interface/AddOns/Blizzard_AddOnList/
   - Compare to SuperSwingTimer.toc and add 16001 while preserving every classic Interface value. Never remove classic interfaces.
   - Open a desk with journal (sst-forever) and spawn read-only subagents with explicit no-edit constraints for parallel research.

2. Trace actual load failures before changing code. Read-only inventory:
   - git status --short; git diff --stat; git ls-files --others --exclude-standard; git log --oneline -3
   - stat -c %y %n for SuperSwingTimer_SoD.lua, SuperSwingTimer_Weaving.lua, SuperSwingTimer_ClassMods.lua, SuperSwingTimer_Constants.lua, SuperSwingTimer.toc, run_tests.lua, SuperSwingTimer_Forever.lua
   - ls -1 *.toc; grep -rn Version: *.toc *.lua
   - Read each TOC in order, read top of each Lua file, grep compat gates: grep -rn isForever, isSoD, GetSoDAuraData in *.lua.
   - Check Blizzard API availability for Forever modules only against origin/forever.
   - Report concrete incompatibilities with source file and line evidence. Post-revert rule: if user says just audit do not touch anything, perform only read-only commands, verify only Forever file remains, and report status, diff stat, untracked list and mtimes with zero edits.

3. Enumerate secret-bearing APIs from origin/forever. Do not guess them.
   - cd /home/sam/wow-ui-source and git grep -n SecretWhen, SecretReturns, SecretArguments in origin/forever
   - git grep -n secretwrap, C_Secrets in origin/forever
   - Study CastingBarFrame data-flow via git show origin/forever path to CastingBarFrame.lua: secret values pass only through secretwrap and secret-safe widgets, never read, compared or formatted directly.
   - Check predicates issecretvalue, IsSecretValue, IsAuraDataSecret in origin/forever.
   - Check AuraContainer: git grep AddAuraGroup, includeSpellIDs, initializeFrame, SetApplicationCount, SetDurationText, SetDurationBar in Blizzard_AuraContainer.
   - Verify CombatLog restrictions and deprecated shims via git grep CombatLog, DEPRECATED in origin/forever.
   - Check aura filter semantics in AuraUtil.lua: PLAYER means own-caster only (player, pet or vehicle).

4. Gate Forever-only behavior; never remove shared code.
   - Add explicit ns.isForever branches in Forever module and Constants.lua helpers. Other clients keep exact old code paths unchanged.
   - Run git diff --stat before and after every edit, and git diff for SuperSwingTimer_SoD.lua. If SoD or classic file was touched, revert immediately with git checkout -- file. Never present SoD logic as Forever behavior.

5. Verify spell and aura IDs; never guess from classic.
   - Search local research first: grep -rn 408505, 408498, Lightning Bolt, Chain Lightning in bench/.forever-research/ and bench/forever-melee-changes.md, then read relevant files.
   - Maelstrom Weapon: aura ID 408505 scanned first; talent ID 408498 is fallback only. Wire behind ns.isForever; do not use ns.GetSoDAuraData for Forever.
   - Direct debuffs: aura ID equals spell ID (verified btt25295 Serpent Sting, btt29228 Flame Shock, btt11574 Rend, btt6343 Thunder Clap, btt1160 Demoralizing Shout, btt7386 Sunder Armor). Only triggered talents have separate aura IDs; list both IDs for those.
   - Lightning Bolt and Chain Lightning: collect every rank ID, cast time and mana cost per rank (or rank 10 where source gives it) from local research, wow-ui-source origin/forever, wowhead.com/forever/spell pages, and foreverdb.net/spell pages. Use firecrawl scraping only when instructed (formats rawHtml, onlyMainContent false, maxAge 0, extract btt records); on daily limit or timeout fall back to web_fetch, advance_fetch, or nether tooltip endpoint. Cite every ID with local file or URL; zero guessed IDs.
   - When a task specifies the local Firecrawl, use POST to http://127.0.0.1:3002/v1/scrape with markdown format, cite the ForeverDB build, and document the extracted rank table in a scraped-data file instead of using hosted web fetch.
   - Before keeping a fallback spell ID, check live ForeverDB presence for that spell. If a spell is confirmed absent in Forever 1.60.1, remove its IDs from the tracked list (for example 33876, 33878, 16857 when confirmed gone), keep present IDs, and update tests and release/Mnemon documentation to match.

6. Audit own-caster debuffs and per-class lists.
   - Grep all aura calls: UnitAura, UnitBuff, UnitDebuff, GetAuraDataByIndex, GetPlayerAuraBySpellID, GetAuraDataBySpellName. Read Forever reader.
   - Debuff containers must use HARMFUL|PLAYER or equivalent own-caster filter and pass secret-safe aura fields through secret-safe widgets. Serpent Sting and Flame Shock must show only player own debuffs.
   - Lists strictly per class: FOREVER_BUFF_SPELLS[class], FOREVER_DEBUFF_SPELLS[class], FOREVER_NEW_ABILITY_CANDIDATES[class]; no cross-class or racial merging into per-class lists. Merge shared or racial buffs only at native container creation.

7. Implement isolated Forever module in SuperSwingTimer_Forever.lua.
   - Own Forever Maelstrom read, stack clamp and cast-time multiplier and secret-safe aura reader ns.GetForeverPlayerAura. SuperSwingTimer_Weaving.lua delegates to it for Forever only; keep exact old SoD and classic path for others.
   - Create native AuraContainer buff and debuff groups using spell-ID sets (includeSpellIDs) and secret-safe widgets; never read secret AuraData fields directly.
   - Classic UnitAura updaters remain active when auras readable and suppressed only while secret.

8. Wire module into TOC and bump version without touching other clients.
   - Edit SuperSwingTimer.toc: add SuperSwingTimer_Forever.lua immediately after SuperSwingTimer_SoD.lua and set Version v0.3.1.
   - Register Forever file in run_tests.lua and CI syntax list; update every Lua file referencing version to v0.3.1 after grep.
   - Re-check git diff --stat to prove no SoD or classic or other-client Lua path altered.

9. Select secret-return distance API for Forever bars.
   - Diagnose a Forever hunter distance bar that stays hidden on a mob before changing code: it must be gated to ns.isForever and playerClass HUNTER, with Hide otherwise.
   - In /home/sam/wow-ui-source, grep UnitDocumentation for distance APIs and SecretReturns: git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua | grep -n -B 12 "SecretReturns = true" and grep -n 'Name = "UnitPosition"' -A 22; also git grep -n "ClosestUnitPosition\|ClosestGameObjectPosition" origin/forever -- Interface/AddOns/ to find client usage such as Blizzard_TutorialRangeManager.
   - Rule out UnitDistanceSquared as the sole target-distance source: it is group-only, so it cannot drive a target distance bar. Choose ClosestUnitPosition(UnitCreatureID('target')) as the primary secret-return distance API, with UnitDistanceSquared only as fallback.
   - Implement the two-source reader in SuperSwingTimer_Forever.lua (ns.ReadForeverTargetDistance) behind pcall, deriving squared distance from the primary API returns, and wire it through ns.UpdateForeverHunterDistanceBar with the existing DISTANCE_MAX_SQUARED clamp, secret-safe value handling, and melee pinned-full behavior.
   - Update SuperSwingTimer_Diag.lua: rewrite the addCheck("distance", "hunter distance", ...) check to cover the new distance source and gating to Forever hunter.
   - Update SuperSwingTimer_Tests.lua with DistanceBar tests for the new source, including ReadsCreatureDistanceFirst, UpdatesFromDistanceApi, GatedToForeverHunter, ValuePassesThroughAndClamps, and ColorBandsMatchRangeHelper.
   - Update CHANGELOG.md and README.md to accurately describe the two-source behavior: primary ClosestUnitPosition(UnitCreatureID('target')), fallback UnitDistanceSquared, secret-safe by construction.
   - Verify with lua5.1 run_tests.lua, luacheck ., and luac5.1 -p on the changed Lua files; report the total test count.

10. Fix secret-value conversion guard using traceback operation.
   - Probe must use operation from traceback (math.max in SyncRangedTimerSpeed), not only math.abs. Simulate issecretvalue false while operation raises and confirm guard catches it.
   - Guard SafeNumber and SafeString in Constants.lua: check ns.IsSecretValue and _G.issecretvalue, wrap operation in pcall, fall back safely so undetected secret cannot leak to call-site math.
   - Add a test for issecretvalue false with raising operation.

11. Mutation proof. Copy addon to scratch, remove conversion guard, run suite and confirm guard test fails. Restore guard, run full suite again, confirm all passing and lint clean with shared classic paths unchanged.

12. Run lint and tests with Forever file loaded and report results: lua5.1 run_tests.lua, luac syntax check, repo-wide luacheck. Report 0 warnings and 0 errors and total test count including ForeverGate tests.

13. Forever talent and spec audit from local origin/forever documentation. Do not assume classic or retail behavior.
   - Read the AGENTS.md client-families section first. For documentation-only tasks, change only AGENTS.md and do not touch main.lua, options.lua, or LibForeverInspector.
   - Verify the client family and version:
     cd /home/sam/wow-ui-source
     git show origin/forever:version.txt
     git grep -n "Interface" origin/forever -- '*.toc' | head
     git grep -n "Camelot" origin/forever -- 'Interface/AddOns/Blizzard_PlayerSpells/**/*.lua' | head
   - Classic talent API absence sweep:
     git grep -n "Blizzard_DeprecatedSpecialization" origin/forever -- '*.toc'
     git grep -n "GetNumTalentTabs\|GetTalentTabInfo\|GetActiveTalentGroup" origin/forever -- 'Interface/AddOns/Blizzard_DeprecatedSpecialization/**' || true
     grep -n "spec_table\|talents_table" Libs/LibForeverInspector/LibForeverInspector.lua
     Conclusion: `spec_table` and `talents_table` are classic-client data and are not valid on Forever.
   - Modern Camelot APIs:
     git grep -n "INSPECT_TRAIT_CONFIG_ID" origin/forever -- '*.lua'
     git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/TraitConstantsDocumentation.lua | sed -n '340,360p'
     git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua | grep -n "GetGroupDisplayInfoByTreeID\|GetGroupCurrencyInfo\|spentInTree\|displayName\|icon"
     git grep -n "GetNumSpecGroups" origin/forever -- 'Interface/AddOns/Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua'
   - validInspect behavior:
     git show origin/forever:Interface/AddOns/Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua | sed -n '870,895p'
     git grep -n "inspectUnit =" origin/forever -- 'Interface/AddOns/Blizzard_PlayerSpells/Blizzard_PlayerSpellsFrame.lua'
     State that `validInspect=true` means the client has the inspected player trait config loaded.
   - Primary and secondary model:
     A Forever class has three talent trees. Primary is the tree with the highest `spentInTree` value from `C_Traits.GetGroupCurrencyInfo(INSPECT_TRAIT_CONFIG_ID, groupIDs)`.
     Secondary is shown only when `C_SpecializationInfo.GetNumSpecGroups()` is greater than 1; Blizzard gates the second tab on that condition at ClassTalentsFrame.lua:124.
     Do not use a retail single-spec assumption or classic `GetTalentTabInfo` behavior.
   - Inactive group attempt:
     Attempt `C_SpecializationInfo.GetTalentInfo` with `isInspect = true`, `target = <unit>`, and `groupIndex = <g>`; render the second line only when the client returns data.
   - Gate and preserve old code:
     grep -n "show_talents and not isForever\|show_talents and isForever\|CI:IsForever\|isForever" main.lua Libs/LibForeverInspector/LibForeverInspector.lua
     Keep the old talent block gated as `show_talents and not isForever` byte-identical and add a separate `show_talents and isForever` branch.
   - Spec icon or tree table:
     If Forever needs spec icons or tree names, use a Camelot-only table or read from `C_Traits`; gate every change on `isForever` or `CI:IsForever()`; never build it from `lib.spec_table` or `lib.talents_table`.

14. Forever loot tooltip must remain native.
   - Verify local documentation:
     git grep -n "SetLootItem" origin/forever -- '*.lua' | head
     git grep -n "ProcessInfo" origin/forever -- 'Interface/AddOns/Blizzard_GameTooltip/**/*.lua' | head
     git grep -n "secret" origin/forever -- 'Interface/AddOns/Blizzard_GameTooltip/**/*.lua' | head
   - Rule: do not add item rows, re-font, cap, or restyle the Forever loot-window GameTooltip; its OnShow must not read loot tooltip info from a tainted hook; normal item tooltips remain unaffected.
   - Gate any Forever loot handling on `isForever` plus a dedicated loot predicate.
   - Tests: loot tooltip line count is unchanged, no TacoTip item rows are added, and a normal item tooltip with the same link still receives rows.

15. Forever zone row is gated to watched frames.
   - Verify local documentation:
     git show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua | sed -n '45,65p;305,330p;690,712p'
     git grep -n "ZONE" origin/forever -- 'Interface/AddOns/Blizzard_FriendsFrame/**/*.lua' | head
   - Rule: `C_Map.GetBestMapForUnit(unit)` only works for the player and party members; draw the row only where the client answers; use `C_Map.GetMapInfo(mapID).name`; use the client ZONE label.
   - Scope is the owner frame unit: player, target, party, or raid only. Exclude nameplates, focus, pets, and target-of-target. Never guess a zone when the API returns nil.
   - Tests cover shown and not-shown owner units.

16. Forever talent reader returns nil safely.
   - A Forever-only accessor such as `GetForeverTalentData` returns nil when `C_Traits`, `GetNumSpecGroups`, or the config is missing or invalid, and never throws on non-Forever clients.
   - Tests mock absent APIs and assert that no Talents line renders.

17. Forever dual-spec verification and harness gates.
   - Confirm secondary display is conditional on verified dual-spec availability from local documentation or code.
   - Confirm the talent gate remains intact and unrelated old code is not churned.
   - Run:
     bash Tests/harness/run_all.sh
     LUA=lua5.4 bash Tests/harness/run_all.sh
     LUA=luajit bash Tests/harness/run_all.sh
     luacheck .
     bash Tools/verify_release.sh --worktree
     bash Tools/verify_release_extras.sh --worktree
   - Expected: FOREVER pins pass, including 108/108 in this window; luacheck reports 0 warnings and 0 errors; both release verifiers report PASS.

18. Document the classic versus Camelot split in AGENTS.md.
   - For documentation-only tasks, change only AGENTS.md; do not touch main.lua, options.lua, or LibForeverInspector.
   - Record these facts:
     - Classic era, TBC, and titanforge use classic talent APIs; old `spec_table` and `talents_table` data are classic-only and are not valid for Forever.
     - Forever 16001 is Camelot and mainline; its UI lives in Camelot folders; a specialization is class-level with three talent trees.
     - Tree names and icons come from `C_Traits.GetGroupDisplayInfoByTreeID`; per-tree points come from `C_Traits.GetGroupCurrencyInfo(...).spentInTree`.
     - The inspected player config is `Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID = -1` from TraitConstantsDocumentation.lua, loaded by Blizzard_ClassTalentsFrame.lua:887; `validInspect=true` means it is loaded.
     - Primary is chosen by highest points; secondary is shown only when dual spec is present.
     - Any Forever spec icon or tree table must be Camelot-only or read from `C_Traits`, gated on `isForever`, and never built from classic tables.
     - Every Forever change is gated on `isForever` or `CI:IsForever()`; the old block keeps `show_talents and not isForever` byte-identical.
   - Verify that no addon code file changed, for example with `git diff --stat`.

19. Forever HUD, aura row, and hunter range-bar audit (SwedgeTimer).
   - HUD truncating integer formatter:
     - In compat.lua, use C_StringUtil.CreateNumericRuleFormatter, not CreateSecondsFormatter or CreateAbbreviatedNumberFormatter, with one breakpoint threshold=0, step=1, rounding=Enum.NumericRuleFormatRounding.Down (or 2), format="%.0f". Expose api.create_duration_number_formatter and feed it through the existing DurationTextBinding:SetFormatter path; binding SetFontString targets a dedicated native FontString (icon.native_text), never the custom countdown string, so the secret Text aspect cannot taint addon text.
     - HUD text is the bare truncated integer ("4", not "4 Seconds" or "2.518"). The HUD ticks at TICK; the binding updates its own string; never read GetFormattedText/GetText after the Text aspect attaches.
     - The duration object is a non-secret opaque handle: C_Spell.GetSpellCooldownDuration has no SecretWhen* predicate; C_DurationUtil binding and CooldownFrame:SetCooldownFromDurationObject consume it. Cite origin/forever FrameAPICooldownDocumentation.lua SetCooldownFromDurationObject and CooldownViewer.lua:1017 where GetInventoryItemCooldown returns isOnGCD as the fourth value.
     - GCD object channel is additive and guarded: register LGC.GCD_OBJECT_STARTED/OVER only when LGC exposes them; ST:GCD_OBJECT_STARTED stores self.gcd.gcd_object and self.gcd.gcd_on_gcd; the provider supplies an opaque handle plus a plain on-GCD flag; the HUD uses it only as a pass-through sink; older libraries keep the numeric path.
     - HUD cache tracing: trace caches by operation and IsSecretValue/issecretvalue guards; SafeNumber and SafeString in Constants.lua wrap the traceback operation (math.max, not only math.abs) in pcall and fall back safely.
   - Aura row anchoring:
     - Native AuraContainer only, HARMFUL|PLAYER own-caster filter, zero AuraData reads; never measure container geometry (GetTop/GetHeight can be secret).
     - Anchor from plain geometry of the addon's own bars: highest GetTop among ST.iter_hands/get_bar_frame visible swing bars; hunter widgets cast_frame, rapid_fire_bar, target_warning. If a visible hunter widget is higher than the top swing bar, anchor above it with BAR_GAP + HUNTER_GAP (12px total). If no visible cast widget exists for a hunter, anchor at least 15px above the ranged bar (HUNTER_RANGED_GAP 29), with the buff row reserving the debuff band (size + TEXT_CLEARANCE). HUNTER_GAP applies only to hunter-widget anchors.
     - Pixel proof: copy a screenshot into .tmp_img, crop and upscale, measure the before-fix clearance (~2px), then verify the anchor change.
     - Aura icon default is the previous size plus 5px (22 -> 27) with one-time migration in A.init.
     - The range bar sits below the shown power bar, else the lowest visible melee bar (never above the ranged bar), so it no longer overlaps aura icons.
   - Hunter range bar:
     - The bottom bar must not use a separate divergent probe that yields '--'. First consume the left indicator's computed helper_state through ui.range_band(); clear helper_state on hide/disable/no target/no answered probes so stale state is never shown.
     - Fallback to the left helper's exact exported bridge ui.spell_range_band() (IsSpellInRange probes Auto Shot/Wing Clip/Raptor Strike with numeric IDs 75/2974/2973), then a duplicated probe only as a last resort.
     - Tests: weave_bar_state passes spell-band tests; affected suites report aura 863 checks and weave 186 checks; the full harness reports 59 steps, 0 failed.
   - Mutation-proven guards:
     - Copy the addon to scratch with rsync excluding .git/docs/bench/desks/Media/images, mutate one behavior, run the affected tests, and expect a non-zero exit; restore and rerun the full harness.
     - Prove M6 range-above-anchor, M7 aura-reservation-removed, M8 aura-size-22, M9 seconds-formatter-restored, M11 hunter-widget-anchor-ignored, M12 float-format-restored, M13 spell-band-removed, M14 hunter-clearance-removed, M15 helper-bridge-ignored, M16 hidden-cast-used, M17 left-state-ignored, and M18 hunter-fallback-6.
     - Run bash tests/run.sh and expect 59 steps, 0 failed; luacheck . reports 0 warnings and 0 errors.

## Pitfalls

- Guessing IDs or assuming classic equals Forever: solution is Steps 3 and 5, cite local research, wow-ui-source, wowhead forever or foreverdb for every ID.
- Using SoD path for Forever (ns.GetSoDAuraData): solution is Forever-owned reader and Maelstrom in SuperSwingTimer_Forever.lua behind ns.isForever.
- Editing other clients, especially SuperSwingTimer_SoD.lua: solution is git diff --stat before and after every edit and immediate revert if touched.
- Removing shared code instead of gating: solution is Forever-owned gated branches with classic paths byte-identical.
- Confusing cast ID with aura ID: direct debuffs aura equals spell ID, triggered talents differ; verify via btt records.
- Cross-class list merging causes missed IDs: solution is strictly per-class tables, merge shared only at container creation.
- Firecrawl timeout or daily limit: fall back to web_fetch, advance_fetch or nether tooltip, never stop silently. When the local Firecrawl endpoint is specified, do not substitute hosted web fetch.
- Keeping removed Forever spell IDs as fallbacks from Classic assumption: solution is a live ForeverDB presence check; remove confirmed-absent IDs and update tests and documentation.
- Using only UnitDistanceSquared for target distance: it is group-only and the bar stays hidden on a mob; solution is Step 9, primary ClosestUnitPosition(UnitCreatureID('target')) with UnitDistanceSquared fallback.
- Assuming underscore-prefixed locals suppress luacheck unused-variable warnings: test with luacheck and handle unused returns only in ways luacheck accepts.
- Wrong conversion guard probe (math.abs only): probe with exact traceback math.max while issecretvalue lies.
- Tone rewrite does not authorize adding purposes, promises or deadlines not in source.
- Assuming Forever uses classic talent globals or a retail single-spec model: use Camelot `C_Traits` APIs and `GetNumSpecGroups`.
- Building a Forever spec icon or tree table from `lib.spec_table` or `lib.talents_table`: use a Camelot-only table or `C_Traits`, gated on `isForever`.
- Showing a secondary tree without verified dual spec: condition it on `GetNumSpecGroups() > 1` and a successful inactive-group read.
- Churning old code or the talents gate: keep `show_talents and not isForever` byte-identical and use a separate `show_talents and isForever` branch.
- Treating `validInspect` as unknown or optional: `validInspect=true` means the inspected player trait config is loaded; cite the Camelot docs.
- Editing addon code during an AGENTS.md-only task: change only AGENTS.md.
- Restyling or adding rows to the Forever loot tooltip: keep it native and avoid tainted OnShow reads.
- Guessing a zone when `C_Map.GetBestMapForUnit` returns nil: draw no row and limit scope to watched player frames.
- Letting a Forever talent reader throw when Camelot APIs are missing: return nil and render no Talents line.

- Using a seconds formatter for the HUD countdown: it appends "4 Seconds"; use CreateNumericRuleFormatter with threshold 0, step 1, rounding Down, format "%.0f" through the proven SetFormatter path.
- Anchoring the aura row to a guessed cast-bar height or a visibility-agnostic anchor: use the actual highest GetTop among the swing bar and visible cast/Rapid/target-warning widgets; otherwise use at least 15px above the ranged bar.
- Applying HUNTER_GAP to non-hunter or swing-bar anchors: apply it only when a hunter widget is the anchor.
- Letting the bottom range bar use a separate divergent probe or stale helper_state: consume ui.range_band() first and clear helper_state on hide.
- Binding SetFontString to the custom countdown string: attach the secret Text aspect to a dedicated native FontString.
- Reading aura-container geometry (GetTop/GetHeight) on Forever: treat it as secret; use addon bar geometry only.
- Running mutation proofs without an isolated scratch copy or without restoring: always mutate a copy and rerun the pristine suite.

## Verification

- Forever version and Blizzard TOC Interface values cited from local wow-ui-source origin/forever, 16001 added, classic interfaces preserved.
- Report shows file-scope load order, compat-gate grep results, concrete incompatibilities with file and line evidence; read-only mode shows git status, diff stat, untracked list, mtimes with no files modified.
- Every Lightning Bolt and Chain Lightning rank ID, cast time and mana cost listed with cited local file, wow-ui-source, wowhead forever or foreverdb URL; firecrawl errors handled with fallback.
- Prune decisions based on live ForeverDB scrape; removed IDs absent from the list when confirmed gone, present IDs remain; tests and release documentation reflect the final decision.
- Maelstrom: aura 408505 first, talent 408498 fallback only, behind ns.isForever; Forever file owns read, stack and multiplier and Weaving delegates; no SoD call on Forever path.
- Player buffs, target debuffs and weaving use Forever-specific secret-safe reader branch; non-Forever paths unchanged.
- Serpent Sting 25295 and Flame Shock 29228 own-caster filtering present; complete Forever ranks in strictly per-class lists.
- TOC lists SuperSwingTimer_Forever.lua after SoD module with Version v0.3.1, consistent across TOC and Lua, no other-client paths changed.
- Native AuraContainer groups use includeSpellIDs, never read secret AuraData fields; classic updaters active when readable, suppressed only while secret.
- Forever hunter distance bar uses ClosestUnitPosition(UnitCreatureID('target')) as primary secret-return distance with UnitDistanceSquared fallback, gated to Forever hunter; Diag and Tests cover the new distance source and gating; CHANGELOG/README accurately describe the two-source behavior.
- Conversion guard mutation: removing guard in scratch fails guard test, restoring returns full suite to passing; probe uses math.max with issecretvalue false.
- luac, repo-wide luacheck and lua5.1 run_tests.lua all pass with test count reported; git diff --stat shows shared classic code preserved.
- Forever talent audit cites origin/forever Camelot paths and `C_Traits` APIs rather than classic or retail assumptions.
- AGENTS.md records `INSPECT_TRAIT_CONFIG_ID = -1` with TraitConstantsDocumentation.lua and Blizzard_ClassTalentsFrame.lua:887.
- AGENTS.md states that old `spec_table` and `talents_table` data are classic-only and invalid for Forever.
- Forever loot tooltip line count is unchanged, no TacoTip item rows are added, and normal item tooltips still receive rows.
- Forever zone row appears only for players on watched frames and only when `C_Map` answers.
- Forever reader returns nil on missing APIs; primary is chosen by highest points; secondary appears only with dual spec.
- Harness and release verifiers pass with dual-spec inspect pins.
- HUD countdown renders a bare truncated integer via CreateNumericRuleFormatter threshold 0, step 1, rounding Down, format "%.0f"; hud_state and forever_secret_compat_state pass.
- Aura row anchor uses a 12px gap above the highest visible cast/Rapid/target-warning widget, or at least 15px above the ranged bar with the buff row reserving the debuff band; HUNTER_GAP applies only to hunter-widget anchors; screenshot clearance proof shows ~2px before the fix.
- Bottom range bar consumes ui.range_band() helper_state first, clears it on hide, and falls back to ui.spell_range_band(); mutants M16-M18 fail while pristine passes.
- GCD_OBJECT callbacks are guarded and the provider supplies an opaque handle plus a plain on-GCD flag; binding SetFontString targets a dedicated native FontString.
- Duration-object pass-through cites origin/forever SetCooldownFromDurationObject and CooldownViewer.lua:1017 isOnGCD.
- Aura-row Forever port audit identifies native AuraContainer only, HARMFUL|PLAYER own-caster filter, zero aura-data reads, and flags secret GetHeight/GetTop geometry hazard.
- Mutation proofs M6-M18 fail on mutated scratch copies and the pristine full harness passes 59 steps, 0 failed with luacheck clean.
