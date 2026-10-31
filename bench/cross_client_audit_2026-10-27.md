# SwedgeTimer cross-client audit — 2026-10-27

Scope: full read-only inspection of /home/sam/SwedgeTimer (branch main, version 2.1.3)
plus the cross-client fixes and the two operator-requested UI changes. Method: whole-tree
static scans, the documented offline gate, branch-by-branch comparison against
/home/sam/wow-ui-source, and a targeted trace of every seam that changes a bar, a spell
token or a load-order decision. No in-client observations were available; anything that
needs the real client is marked UNVERIFIED.

## 1. Verified baseline (before changes)

- bash tests/run.sh: **53 steps, 0 failed**; luacheck . **2 warnings / 0 errors in 95 files**
  (both documented floor warnings: compat.lua:36 addon_name, main.lua:87 table.pack).
- 38 root Lua modules + 6 class modules, ~87,180 Lua lines, 7 TOCs.
- No bare cross-client API call outside compat.lua (whole-tree scan; tests/wiring_check.lua
  check 4 also enforces it).
- All 32 event literals registered by product code are documented on all five reference
  branches (see §3).
- get_spell_query(name,id) already implemented the requested rule; class helpers in
  paladin/warrior/rogue/hunter/shaman/druid followed it. Two exceptions were found and
  fixed (§5 F3/F4).

## 2. Reference branches (git show / git grep)

| Branch | Client | version.txt |
|---|---|---|
| classic_era | Classic Era 1.15.9 / SoD | 1.15.9.70003 |
| classic_anniversary | TBC Anniversary 2.5.6 | 2.5.6.70006 |
| classic_titan | WotLK Titanforge 3.80.2 | 3.80.2.69815 |
| origin/forever | WoW Forever 1.60.1 | 1.60.1.70532 |
| live | Retail 12.1.0 | 12.1.0.69814 |
| origin/ptr2 | Retail PTR 12.1.5 | 12.1.5.70340 |
| origin/ptr | Retail PTR 12.1.7 | 12.1.7.70493 |

120107 is PTR-only and is not advertised by any TOC. 120105 is live 12.1.5.

## 3. TOC matrix (after the fix)

| TOC | Interface | classic swing lib | power_bar.lua |
|---|---|---|---|
| SwedgeTimer.toc (base fallback) | 11509, 20506, 38002 | yes | yes |
| _Vanilla.toc | 11509 | yes | yes |
| _TBC.toc | 20506 | yes | yes |
| _Wrath.toc | 38002 | yes | yes |
| _Mainline.toc | 120100, 120105, 16001 | no | yes |
| _Cata.toc | 40402 | no | yes |
| _Mists.toc | 50500 | no | yes |

The base TOC had regressed to 11509, 20506, 38002, 120105, 120107, 16001 while still
shipping LibClassicSwingTimerAPI (its file-scope
RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") throws on mainline-code clients).
tests/toc_check.lua only checked "contains", so the extras passed. Both are fixed:
base/Mainline are exact-match now, and power_bar.lua is a required module on every TOC.

## 4. API / event matrix

No product file outside compat.lua calls a cross-client API directly. The wrappers used by
the new bar are documented on all five branches:

- UnitPower / UnitPowerMax / UnitPowerType: classic_era, classic_anniversary,
  classic_titan UnitDocumentation.lua; origin/forever and live UnitDocumentation.lua.
  compat.lua wraps them with secret-value guards (a restricted read returns nil, so the bar
  hides rather than painting 0).
- UNIT_POWER_FREQUENT, UNIT_POWER_UPDATE, UNIT_DISPLAYPOWER: documented on all five
  branches (UnitDocumentation.lua). UPDATE_SHAPESHIFT_FORM and PLAYER_EQUIPMENT_CHANGED
  were already registered by main.lua and are documented on all five.
- No protected call is added. The power bar is an insecure frame; only SetPoint/SetWidth/
  SetHeight/SetFrameStrata/SetFrameLevel are used, and strata/level changes are skipped
  under combat lockdown.

## 5. Findings and fixes

| ID | Severity | Finding | Fix |
|---|---|---|---|
| F1 | HIGH | Base TOC advertised mainline interfaces while shipping LibClassicSwingTimerAPI | Base interface exactly 11509, 20506, 38002; toc_check exact-match |
| F2 | MEDIUM | toc_check used "contains" for base/Mainline and could not catch F1 | Both tables moved to INTERFACE_EXACT; power_bar.lua added to REQUIRED_MODULES |
| F3 | MEDIUM | hunter_ui.resolve_spell returned the NAME on Era and had no id fallback on TBC (cold cache = permanently nil token) | Era returns the numeric id; TBC/Wrath return the localized name then the id; display name is a separate return; probe retries with the id when the name answers nil |
| F4 | MEDIUM | hunter queue_tokens skipped unnamed entries on name families (cold cache = empty probe list) | Names are emitted first (sorted) and cold entries contribute their rank ids (sorted); never empty when ids exist |
| F5 | LOW | tests/toc_check.lua's luac5.1 -l -l wrote the tracked luac.out on every run | luac output goes to os.tmpname(); luac.out added to .gitignore; operator may git rm --cached it |
| F6 | MEDIUM | .gitattributes was a foreign TacoTip file whose "Media/ export-ignore" excluded the required fonts, statusbar texture and 69 sounds from a git-archive release | Rewritten for SwedgeTimer: workshop/tests/docs/dotfiles/PNG/unreferenced media ignored, Media/Fonts, Media/Textures, Media/StatusBar and Media/Sounds stay |
| F7 | LOW | TOC metadata drift: base author AcidBomb vs Swedge, base icon full path vs relative transparent icon | All seven TOCs now use Author: Swedge and IconTexture: SwedgeTimer_v2_transparent.tga |
| F8 | LOW | TESTING.md diag examples still said 2.1.1; hunter comments claimed the retired re-anchor | Updated to 2.1.3 and rewrote the stack comments |
| F9 | FEATURE | No primary-resource bar | power_bar.lua, generic UnitPowerType-driven, default 14 px, under the bottom-most visible melee bar |
| F10 | FEATURE | Hunter MH/OH were 200 px at their own positions, not the ranged width, no stable stack | hunter_ui.apply_melee_stack: thin MH/OH under the ranged bar at its width; hunter_melee_stack toggle default on; restore path puts each hand back |

Reported, not changed:
- Literal English-name fallbacks in some druid/shaman guide paths (e.g. MAUL_NAME) are a
  locale limitation, not a missing compat call; the client's own name for the id is used
  where available. No id was removed or replaced.
- hud.lua's TBC-only name path is deliberate: on Titanforge IsSpellKnown is id-only.
- Practice-button ladders that branch on st.family ~= "TBC" use the token for icons/text,
  not for state queries.
- Open hands-up rows HU-12/18/19/20/24/25/27/28/29 remain operator decisions.

## 6. Spell-token matrix (verified in code and tests)

| Family | Client | get_spell_query | class helpers | hunter_ui range token | hunter queue token |
|---|---|---|---|---|---|
| ERA | Classic Era / SoD | id | id | id | ids |
| TBC | TBC Anniversary | name -> id fallback | name -> id fallback | localized name -> id fallback (probe retries id on nil) | distinct names, then cold rank ids |
| WRATH | Titanforge | name -> id fallback | name -> id fallback | localized name -> id fallback | distinct names, then cold rank ids |
| FOREVER | WoW Forever | id | id | id | ids |
| CATA / MISTS / RETAIL / UNKNOWN | - | id | id | id | ids |

The fallback is load-bearing: a name the client cannot index degrades to the id, never to
a nil token or an empty probe list. No spell-id table was added, removed or replaced.

## 7. Verification

- bash tests/run.sh: **54 steps, 0 failed** (includes the new tests/power_bar_state.lua).
- luacheck .: **2 warnings / 0 errors in 97 files** (the same two floor warnings).
- New/updated suites: power_bar_state (151 checks), hunter_state (1867), bars_state (962),
  spell_query_family_state (75), toc_check (TOC matrix + local budget + harness registry).
- git status after the gate: no luac.out modification (test run no longer writes it).
- Mutation proofs: see bench/cross_client_mutations_2026-10-27.md (10 mutations, each
  turns a named pin red).

## 8. UNVERIFIED (needs the real client)

1. Power bar in-client: exact 14 px look, width following the owning melee bar, colour by
   power type, text, and hiding when no melee bar is visible.
2. Hunter melee stack in-client: MH/OH pinned under the ranged bar at its width, drag
   behaviour (ranged moves the stack; MH snaps back while on), and the toggle-off restore.
3. Druid form swap repaint (mana/rage/energy) through UNIT_DISPLAYPOWER.
4. TBC/Wrath name-first client facts remain the operator's in-client evidence (the branch
   docs are ambiguous: Blizzard's classic_anniversary Spell.lua calls GetSpellInfo in id
   form while C_Spell.GetSpellInfo accepts both). The id fallback is the safety net.
5. Retail 12.1.7 is PTR-only and untested; 12.1.0/12.1.5 only.
