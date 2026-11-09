# Per-client truth — FINAL pass (2026-10-20)

Desk: **perclient-truth-final** · Scope: the publish-gate re-audit's per-client checklist
(**P1–P12**) plus `bench/final_gate_audit_2026-10-20.md` §6 (**C1–C7**), executed with
shell access. · Reference repo: `/home/sam/wow-ui-source` — **read-only**:
`git show <branch>:<path>` and `git grep <branch>` only. **No checkout, no modification**;
the checked-out branch (`classic_era`) was never touched. · Client spell data: the
operator's own export at `/home/sam/wow.export` (the 1.15.9 SoD client), read-only. ·
**No addon/test/bench file other than this one was written.**

---

## 0. Method, branches, and what could not be reconstructed

### Branches (each read on its own branch; nothing carried over from another)

| branch | client family the addon targets | interface | read? |
|---|---|---|---|
| `classic_era` | Classic Era / SoD 1.15.9 → `_Vanilla` | 11509 | yes |
| `classic_anniversary` | TBC Anniversary 2.5.6 → `_TBC` | 20506 | yes |
| `classic_titan` | WotLK Titanforge 3.80.2 → `_Wrath` | 38002 | yes |
| `origin/forever` | WoW Forever 1.60.1 → `_Mainline` | 16001 | yes |
| `live` | Retail 12.x → `_Mainline` | 120105 | yes |

### Which method actually answered

**`git show` + `git grep` (shell) — every row below.** `ast_grep_search` was **not** used and
**could not** have answered the documentation rows: the API-doc files are table
constructors, and ast-grep cannot see a string literal inside one (the failure mode recorded
at `bench/lessons.md:75-81`). Every `Name = "…"` / `Documentation = { "…" }` line cited below
was read with `git show <branch>:<path> | cat -n`; every **absence** was checked with
`git grep -c` / `git grep -l` over the **whole branch** (not a path subset), so each
"ABSENT" row means "absent from the branch", never "absent from the client".

### The P-row texts

The re-audit's own report file is **not on disk** (`hands-up.md` HU-16 — the filed report is
`bench/final_gate_audit_2026-10-20.md`). The P1–P8 rows below are the ones the dispatch
carried; **P9–P12 are reconstructed** from the four in-client rows of that filed report's
§6 checklist (C3, C4, C5, C6) and are marked **reconstructed** in §6. Nothing in this file
rests on the re-audit's unfiled text.

---

## 1. The checklist — one row per check

| P-row | question | answer | the deciding evidence |
|---|---|---|---|
| **P1** `classic_era` | (a) does the classic **global** `GetSpellInfo` take a **name**? (b) how many values, is the id **7th**? | (a) **UNPROVEN from the tree** (Era) · (b) **UNPROVEN** (positions 1–3 proven) | `classic_era:…/Blizzard_ObjectAPI/Classic/Spell.lua:39` (id form) · the only name-form call is in the **Mists** file, not loaded on Era (P2) · no call site unpacks 4+ |
| **P3** `classic_anniversary` | same | (a) **UNPROVEN from the tree** (TBC) · (b) **UNPROVEN** | `classic_anniversary:…/Blizzard_ObjectAPI/Classic/Spell.lua:39` (id form) · name-form only at `…/Mists/Blizzard_TalentUI.lua:671` |
| **P4** `classic_titan` | same | (a) **UNPROVEN from the tree** (Wrath) · (b) **UNPROVEN** | `classic_titan:…/Blizzard_ObjectAPI/Classic/Spell.lua:39` (id form) · name-form only at `…/Mists/Blizzard_TalentUI.lua:671` |
| **P5** `origin/forever` | same | (a) **UNPROVEN from the tree** · (b) **UNPROVEN** | **no `Blizzard_TalentUI` folder on the branch** → no name-form call site at all; the id-form sites are gated to other game types (`Blizzard_UIPanels_Game.toc:186` `Cata\PetStable.lua [AllowLoadGameType cata, mists]`) |
| **P6** `live` | same | (a) **PROVEN — the global takes a NAME on Retail** · (b) **UNPROVEN** | `live:…/Blizzard_TalentUI/Mists/Blizzard_TalentUI.lua:671` `GetSpellInfo(talentName)`, and that file **is** loaded on Retail (`live:…/Blizzard_TalentUI_Mists.toc:8`) |
| **P2** | is the **Mists** folder's `Blizzard_TalentUI` loaded by the **classic_era** client (live source or vendored dead code)? | **VENDORED DEAD CODE on the Era client**; live source on a **Mists** client and on **Retail** | `classic_era:…/Blizzard_TalentUI_Vanilla.toc:4-8` loads `Classic\…`; `…/Blizzard_TalentUI_Mists.toc:6` loads `Mists\…`; `Classic/Blizzard_TalentUI.lua` has **0** `GetSpellInfo` hits |
| **P7** | Seal of the Crusader: 20308 / the ladder 21082·20162·20305-20308 against the **client's own spell data** | **PROVEN for the Era/SoD client**; **nothing** said about Cata/Mists | `/home/sam/wow.export/Spell.csv` (21082 `Rank 1` … 20308 `Rank 6`, identical "spirit of a crusader" description, all six **Retribution** abilities); the *name* is confirmed by the client's own `20335` / `28852` descriptions |
| **P8** | Healthstone: **5720** vs **6262** against the client's own spell data | **PROVEN for the Era/SoD client** (5720 = Healthstone, 6262 = **Minor** Healthstone) → the tree's claim is **CONFIRMED**; the **Cata/Mists** claim stays open | `Spell.csv` row 5699 `…restore $5720s1 health.` · row 6201 `…Minor Healthstone… $6262s1 health.` |
| **P9–P12** | the four in-client rows | **OPERATOR-ONLY** | §6 below, in the live script's step format |

**The tree's arity assumption (`compat.lua:157-176`): NOT refuted, NOT confirmed.** See §5.

---

## 2. P1 / P3 / P4 / P5 / P6 — the classic global `GetSpellInfo` and `C_Spell.GetSpellInfo`

### 2.1 The global is native everywhere — there is no definition to read

```
git grep -cE "^\s*(function GetSpellInfo|GetSpellInfo\s*=)" <branch> -- '*.lua'
```

→ **no match on any of the five branches** (classic_era, classic_anniversary,
classic_titan, origin/forever, live). The global is a C++ API; the tree can only read
Blizzard's **call sites**, never its signature. This is the root cause of every "UNPROVEN"
in this section.

### 2.2 (b) the return arity — what the tree can and cannot know

**Positions 1–3 are proven on the classic branches** (call sites, quoted):

```
classic_era:Interface/AddOns/Blizzard_Collections/Classic/Blizzard_MountCollection.lua:641
	local spellName, _, spellIcon = GetSpellInfo(self.spellID);
```
```
classic_era:Interface/AddOns/Blizzard_Commentator/Blizzard_CommentatorSpell.lua:7
	self.Icon:SetTexture(select(3, GetSpellInfo(spellID)))
```
```
classic_era:Interface/AddOns/Blizzard_TalentUI/Cata/Blizzard_TalentUI.lua:672-673
	local function PlayerTalentFramePanel_UpdateBonusAbility(bonusFrame, spellId, spellId2, formatString, desaturated)
		local name, subname, icon = GetSpellInfo(spellId);
```
→ **1 = name**, **2 = subname / rank**, **3 = icon (a fileID)**. That is exactly the tree's
`compat.lua:157` first three slots ("name, rank, icon, castTime, minRange, maxRange,
spellID") and the tree's `compat.lua:169` C_Spell mapping (`info.name, nil,
info.originalIconID, info.castTime, info.minRange, info.maxRange, info.spellID`).

**Positions 4–7 are UNPROVEN on every branch.** The check:

```
git grep -nE "local [^=]*,[^=]*,[^=]*,[^=]*=[^=]*GetSpellInfo\(" <branch> -- '*.lua'
```
→ **zero matches on all five branches** (the `C_Spell.` / `C_SpellBook.` forms are excluded —
they return a table, not multiple values). No Blizzard code on any branch unpacks more than
**three** values from the global. There is also **no documentation entry for the global on
any branch**: the only `GetSpellInfo` in `Blizzard_APIDocumentationGenerated/` is the
**`C_Spell`** namespace entry (below).

**Per-branch table (the global):**

| branch | id-form call site (quoted) — and is it **loaded** on that client? | name-form call site | max values unpacked |
|---|---|---|---|
| `classic_era` | `…/Blizzard_ObjectAPI/Classic/Spell.lua:38-40` → `return (GetSpellInfo(self:GetSpellID()));` (loaded on the classic-line clients: `classic_era:…/Blizzard_ObjectAPI/Blizzard_ObjectAPI_Classic.toc:5` `## AllowLoadGameType: classic`, `:9` `Classic\Spell.lua`) | **none in a loaded file** (see P2) | 3 |
| `classic_anniversary` | `…/Blizzard_ObjectAPI/Classic/Spell.lua:39` — same line, same text | none in a loaded file | 3 |
| `classic_titan` | `…/Blizzard_ObjectAPI/Classic/Spell.lua:39` — same line, same text | none in a loaded file | 3 |
| `origin/forever` | `…/Blizzard_UIPanels_Game/Cata/PetStable.lua:321` → `local spellName = GetSpellInfo(CALL_PET_SPELL_IDS[self:GetParent():GetID()]);` — **NOT loaded on the camelot client**: `origin/forever:…/Blizzard_UIPanels_Game/Blizzard_UIPanels_Game.toc:186` = `Cata\PetStable.lua [AllowLoadGameType cata, mists]`. The other id-form site, `…/Blizzard_Collections/Classic/Blizzard_MountCollection.lua:624`, is reached via `Blizzard_Collections.toc:25` `[Family]\Blizzard_MountCollection.lua`; that tocs' own header (`:13` `## AllowLoadGameType: wrath, cata, mists, mainline`) **excludes camelot** while sibling entries (`:16,:21,:23,:27`) carry camelot tags — **mixed in the tree, not claimed as live** | **none on the branch** (the branch has **no `Blizzard_TalentUI` folder** at all) | 3 |
| `live` | `…/Blizzard_TalentUI/Cata/Blizzard_TalentUI.lua:673` (id form) — **not loaded on Retail**: `live` ships only `Blizzard_TalentUI_Mists.toc`, and `live:…/Blizzard_Collections_Classic.toc:8` is `## AllowLoadGameType: wrath, cata, mists` (the Retail client loads `Blizzard_Collections_Mainline.toc:14` → `Mainline\Blizzard_MountCollection.lua`, which does not call the global), and `live:…/Blizzard_Commentator_Classic.toc:6` is `## AllowLoadGameType: classic` | **`…/Blizzard_TalentUI/Mists/Blizzard_TalentUI.lua:671`** — **the only global call site Retail loads** (see 2.4) | 3 |

> **Consequence for P6.** On Retail the **sole** live call site of the classic global in the
> entire tree is the **name-form** one. On WoW Forever the tree shows **no** live global call
> site at all (the id-form ones are gated to other game types) and **no** name-form one
> anywhere on the branch.

### 2.3 `C_Spell.GetSpellInfo` — one table, and the name is documented

```
classic_era / classic_anniversary / classic_titan:
Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua:190-204
	190				Name = "GetSpellInfo",
	191				Type = "Function",
	192				MayReturnNothing = true,
	193				Documentation = { "Returns nil if spell is not found" },
	197					{ Name = "spellIdentifier", Type = "SpellIdentifier", Nilable = false, Documentation = { "Spell ID, name, name(subtext), or link; Using name will always check for an override on that spell" } },
	202					{ Name = "spellInfo", Type = "SpellInfo", Nilable = false },
```
```
origin/forever: …/SpellDocumentation.lua:416-431   (same block + SecretArguments = "AllowedWhenTainted" at :419)
live:          …/SpellDocumentation.lua:375-390   (same block + SecretArguments at :378)
```
The `SpellInfo` struct (the table the tree maps at `compat.lua:169`) —
`classic_era:…/SpellDocumentation.lua:782-793`:
```
786				{ Name = "name", Type = "string", Nilable = false },
787				{ Name = "iconID", Type = "fileID", … },
788				{ Name = "originalIconID", Type = "fileID", Nilable = false },
789				{ Name = "castTime", Type = "number", Nilable = false },
790				{ Name = "minRange", Type = "number", Nilable = false },
791				{ Name = "maxRange", Type = "number", Nilable = false },
792				{ Name = "spellID", Type = "number", Nilable = false },
```
(`origin/forever:…:1183-1195`, `live:…:1109-1121` — same field list.)

**Answer (both halves):** `C_Spell.GetSpellInfo` returns **ONE** `SpellInfo` table and its
identifier accepts **id, name, name(subtext) or link** on **all five branches** — that half
is **PROVEN**. The tree's `compat.lua:162-170` (the C_Spell branch, which manufactures the
7-value shape itself) is therefore **self-consistent on every branch**.

### 2.4 (a) does the **global** accept a spell **name**?

**PROVEN on Retail (`live`).** The global is called with a **name** in a file Retail loads:

```
live:Interface/AddOns/Blizzard_TalentUI/Blizzard_TalentUI_Mists.toc:8
	Mists\Blizzard_TalentUI.lua
```
```
live:Interface/AddOns/Blizzard_TalentUI/Mists/Blizzard_TalentUI.lua:670-671
	670				local _, talentName = GetTalentInfoByID(self:GetID(), talentGroup);
	671				local spellName, subSpellName = GetSpellInfo(talentName);
```
`GetTalentInfoByID` returns the talent's **name** in slot 2, so `talentName` is a **name
string**; the call passes it to the global and reads a name back. `live` ships **only**
`Blizzard_TalentUI_Mists.toc` (no `_Mainline` / `_Cata` variant), so this is the TalentUI the
Retail client runs — the name-form call is **live source**, not vendored code. Two
corroborations in the same file: line 672 then feeds the **returned** name into
`IsPassiveSpell(spellName)`, and the global's return is a *name*; and the file is shipped,
so the global still exists on Retail 12.x.

**It is also the *only* live global call site on Retail** (see the table in 2.2: the Cata
TalentUI variant and the `Classic/` Commentator variant are both gated away from the
mainline game type, and `Blizzard_Collections_Mainline.toc` loads the `Mainline/` variant,
which does not call the global). Nothing else in Retail's live FrameXML touches it.

**UNPROVEN from the tree for Era / TBC / Wrath.** The **same** name-form call exists in the
three classic branches — `classic_era` / `classic_anniversary` / `classic_titan`:
`Interface/AddOns/Blizzard_TalentUI/Mists/Blizzard_TalentUI.lua:671` — but those clients do
**not** load the Mists folder (P2). A whole-branch sweep finds **no other** name-form call:
```
git grep -nE 'GetSpellInfo\("'        <branch> -- '*.lua'   → 0 matches (all five branches)
git grep -nE 'GetSpellInfo\([A-Za-z_]*([Nn]ame|[Tt]itle|[Ll]abel)' <branch> -- '*.lua'
```
→ only the Mists TalentUI line above (classic branches) and the same line on `live`; on
`origin/forever` **nothing** (the branch has no `Blizzard_TalentUI` folder at all).

**What this does and does not do to the standing rule.** The operator's in-game rule
(`bench/lessons.md:29-31`: "TBC Anniversary API takes spell NAMES, not ids; Classic Era
needs ids") is an **in-client observation** and stands. The source now agrees with it in the
direction that matters: on the classic branches the global is only ever *shown* working with
an **id**; nothing in the tree shows a name **failing**, and nothing shows a name **working**
on those three clients either. This is exactly the state `hands-up.md` HU-6 recorded, and
`bench/f4_family_spell_id_2026-10-19.md` §1 already noted ("the source shows ids working,
not names failing"). **No tree change is owed**: the shipped resolver
(`compat.get_family_spell_id`, name path primary on TBC, id fallback) works under both
readings.

The Retail proof adds one thing the earlier bench files did not have: **the global's
name-acceptance is not a TBC-only quirk — it is a property of the shared native**, proven
on the client family whose file set actually exercises it.

---

## 3. P2 — is the Mists folder's `Blizzard_TalentUI` live on the `classic_era` client?

**ANSWER: VENDORED DEAD CODE on the Era/SoD client.** The name-form call at
`…/Blizzard_TalentUI/Mists/Blizzard_TalentUI.lua:671` is live source only on a **Mists**
client and on **Retail**; on the Era client the file that loads is the `Classic/` one, which
never calls the global at all.

### 3.1 The five tocs of the addon (all on `classic_era`)

```
Interface/AddOns/Blizzard_TalentUI/Blizzard_TalentUI_Vanilla.toc     (8 lines)
	1	## Title: Blizzard Talent UI
	2	## LoadOnDemand: 1
	3	## Dependencies: Blizzard_HelpPlate
	4	Classic\Blizzard_TalentUI_Shared.lua
	5	Classic\Blizzard_TalentUI_Shared.xml
	6	Classic\Blizzard_TalentUI.lua
	7	Classic\Blizzard_TalentUI.xml
	8	Classic\Localization.lua
```
`_TBC.toc` and `_Wrath.toc` are **identical** to `_Vanilla.toc` (same five `Classic\…`
entries); `_Cata.toc:6` = `Cata\Blizzard_TalentUI.lua`; `_Mists.toc:6` = `Mists\Blizzard_TalentUI.lua`.

### 3.2 Which toc the Era client loads — the game type is `vanilla`

The dispatch is **not** by file name alone: the branch carries the game-type vocabulary and
the Era client's project id proves which game type it is.

```
classic_era:Interface/AddOns/Blizzard_FrameXMLBase/Blizzard_FrameXMLBase_Vanilla.toc:6
	## AllowLoadGameType: vanilla
```
```
classic_era:Interface/AddOns/Blizzard_FrameXMLBase/Blizzard_FrameXMLBase_Vanilla.toc:15-17
	15	Classic\Constants.lua
	16	Shared\Constants.lua
	17	Vanilla\Constants.lua
```
```
classic_era:Interface/AddOns/Blizzard_FrameXMLBase/Vanilla/Constants.lua:91-97
	91	    WOW_PROJECT_MAINLINE = 1;
	92	    WOW_PROJECT_CLASSIC = 2;
	93	    WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5;
	94	    WOW_PROJECT_WRATH_CLASSIC = 11;
	95	    WOW_PROJECT_CATACLYSM_CLASSIC = 14;
	96	    WOW_PROJECT_MISTS_CLASSIC = 19;
	97	    WOW_PROJECT_ID = WOW_PROJECT_CLASSIC;
```
→ the **`vanilla`** game type *is* the Era/SoD client (`WOW_PROJECT_ID = 2`), and the addon's
own map says so: `compat.lua:53-54` → `if project_id == WOW_PROJECT_CLASSIC then family = "ERA"`.
The same branch also carries the other flavours of that toc —
`Blizzard_FrameXMLBase_TBC.toc:6` (`tbc`), `_Wrath.toc:6` (`wrath`), `_Cata.toc:6` (`cata`),
`_Mists.toc:6` (`mists`) — so the branch is a union tree and the **client** picks.

(The repo's own summary doc is loose on this point — `reference/VERSION_BRANCHES.md:20` reads
"`Vanilla/` | Original Vanilla (pre-1.12)", while its §"Vanilla (4 addons)" says "-- Vanilla
Classic (seasonal/original) uses Vanilla directory". The **code** settles it: the `vanilla`
game type's own `Vanilla\Constants.lua:97` sets `WOW_PROJECT_ID = WOW_PROJECT_CLASSIC` — the
Era project id — and the addon's `compat.lua:53-54` maps that to the `ERA` family. The doc
row is not used as evidence anywhere in this file.)

The per-file variant of the same mechanism, quoted from a toc that uses it:
```
classic_era:Interface/AddOns/Blizzard_UIPanels_Game/Blizzard_UIPanels_Game_Classic.toc:7,15-16
	 7	## AllowLoadGameType: classic
	15	Cata\SpellBookProfessions.lua [AllowLoadGameType cata, mists]
	16	Vanilla\SpellBookFrame.lua [AllowLoadGameType vanilla, tbc, wrath]
```
(the repo's own summary of the suffix mechanism: `reference/VERSION_BRANCHES.md:216-237`
— "Client looks for `.toc` matching its version suffix … If no version match, falls back to
bare `.toc` without suffix".)

### 3.3 The decisive content check

```
git show classic_era:Interface/AddOns/Blizzard_TalentUI/Classic/Blizzard_TalentUI.lua | grep -c GetSpellInfo     → 0
git show classic_era:Interface/AddOns/Blizzard_TalentUI/Classic/Blizzard_TalentUI_Shared.lua | grep -c GetSpellInfo → 0
```
→ the file the **Era** client loads (and its shared companion) never calls the global, by
**name** or by id. The name-form call exists only in the `Mists/` and `Cata/` variants.

### 3.4 Robustness of the answer (the suffix vocabulary does not change it)

The suffix vocabulary on this branch is wider than "Vanilla": 44 tocs end in `_Classic.toc`,
22 in `_Mists.toc`, 18 in `_Cata.toc`, 16 in `_Mainline.toc`, 13 in `_Wrath.toc`, 12 in
`_Vanilla.toc`, 11 in `_TBC.toc` — and the `_Classic.toc` variants carry **their own** game-type
headers, e.g. `classic_era:…/Blizzard_ActionBar_Classic.toc:5` `## AllowLoadGameType: classic`
(the classic-line union), `…/Blizzard_AchievementUI_Classic.toc:8` `## AllowLoadGameType: tbc, wrath`,
`…/Blizzard_AuctionHouseUI_Classic.toc:9` `## AllowLoadGameType: cata, mists`.

Two independent reasons make the P2 answer stable:

1. **`Blizzard_TalentUI` has no `_Classic.toc`** — its five variants are `_Vanilla`, `_TBC`,
   `_Wrath`, `_Cata`, `_Mists`, and the first three load the **same** `Classic\` file set.
   So whichever classic-line variant the Era client selects, the file that runs is
   `Classic\Blizzard_TalentUI.lua` — **never** the `Mists\` one.
2. **The `Mists\` folder becomes live only for a `mists`-game-type client** (and for Retail,
   whose only TalentUI toc is `_Mists`, §2.4). The `Cata\` folder becomes live only for a
   `cata` client. Neither is the Era/SoD client.

**Consequences for the audits:**
* The final gate audit's §6 note — "the classic global `GetSpellInfo` is called with an id
  on classic-line clients (`Blizzard_ObjectAPI/Classic/Spell.lua:39`) and with a name in the
  Cata/Mists UI code (`Blizzard_TalentUI/Cata/Blizzard_TalentUI.lua:673`)" — is **half
  wrong in its detail**: the **Cata** file's `:673` is an **id** call
  (`local name, subname, icon = GetSpellInfo(spellId);`), and the **name** call is at
  `Mists/Blizzard_TalentUI.lua:671`. The corrected citation is in §2.4 above.
* The **name**-form evidence for the *classic global* therefore applies to **Mists** and
  **Retail**, not to Era/TBC/Wrath — and the tree's own comments already say as much
  ("the NAME-first leg finds the client's own rank only where the client ANSWERS the name,
  and whether the classic-line global takes a name at all is UNCONFIRMED in-client",
  `classes/druid.lua:4236-4238`). **That comment is now narrowed, not contradicted**: the
  global's name-acceptance is PROVEN on Retail and Mists, still UNCONFIRMED for Era/TBC/Wrath.

---

## 4. P7 / P8 — the client's own spell data (`/home/sam/wow.export`, the 1.15.9 SoD client)

### 4.0 What this export is, and what it therefore cannot do

* It is the **operator's own 1.15.9 SoD client** export: `Spell.csv`, `Item.csv`,
  `SkillLine.csv`, `SkillLineAbility.csv`, `SpellEffect.csv`, `SpellDuration.csv`,
  `SpellCategory.csv`, `SpellCastTimes.csv`, `SpellTotems.csv`, `SpellLevels.csv`,
  `SpellShapeshift.csv`, `SpellShapeshiftForm.csv`, `Talent.csv`, `TalentTab.csv`,
  `TotemCategory.csv`.
* **`Spell.csv` has no spell-name column.** Header: `ID;NameSubtext_lang;Description_lang;AuraDescription_lang`.
  There is no `Name_lang` anywhere in the export (checked: `Spell.csv`, `Item.csv`,
  `SkillLineAbility.csv` headers). **An id → name join is only possible through the
  description text**, where Blizzard's own data embeds `$<spellID>` tokens. That is the
  method used below, and it is the reason several names are "PROVEN by the client's own
  description" rather than "PROVEN by a name column".
* **It is Era/SoD data.** It says nothing about Cata/Mists (or about any other client).
  Every Cata/Mists statement below is explicitly **UNPROVEN / OPERATOR-ONLY**.

### 4.1 P7 — Seal of the Crusader: 20308 and the ladder 21082·20162·20305-20308

`/home/sam/wow.export/Spell.csv` (all six rows carry the **identical** description):

| id | `NameSubtext_lang` | description (verbatim, truncated) |
|---|---|---|
| 21082 | `Rank 1` | "Fills the Paladin with the spirit of a crusader for $d, granting $s1 melee attack power. The Paladin also attacks $s2% faster, but deals less damage with each attack. Only one Seal can be active on the Paladin at any one time." |
| 20162 | `Rank 2` | same |
| 20305 | `Rank 3` | same |
| 20306 | `Rank 4` | same |
| 20307 | `Rank 5` | same |
| 20308 | `Rank 6` | same |

* **It is a paladin Retribution seal family, 6 ranks.**
  `SkillLine.csv:184` → `184;Retribution;…`; and `SkillLineAbility.csv` carries one row per
  rank with the spell in column 3 and `ClassMask = 2` (Paladin):
  `:4046` → `11547;184;20162;…` · `:4068` → `11576;184;20305;…` · `:4069` → `11577;184;20306;…`
  · `:4070` → `11578;184;20307;…` · `:4071` → `11579;184;20308;…` · `:4263` → `11956;184;21082;…`.
* **The client's own data names the spell.** `Spell.csv:8084` (id **20335**, `Rank 1`):
  *"Increases the melee attack power bonus of your **Seal of the Crusader** and the Holy
  damage increase of your Judgement of the Crusader by $s1%."* — and `Spell.csv:10527`
  (id **28852**): *"Increases the melee attack power bonus of your **Seal of the Crusader** by
  $s1 and the Holy damage increase of your Judgement of the Crusader by $s2."*
  The client therefore refers to "your Seal of the Crusader" for the buff these ranks grant
  → the six-rank family above **is** the Seal of the Crusader.
* **20308 = rank 6** of it — the id the tree uses for the Forever pre-pull row
  (`classes/paladin.lua:5237-5240`) and for the rank-art ladder.
* **Corroboration inside the tree (not evidence of its own):** `classes/paladin.lua:143`
  already carries the ladder `{ 21082, 20162, 20305, 20306, 20307, 20308, 27158 }`, and
  `practice.lua:89` uses `sotc = { name = "Seal of the Crusader", spell_id = 21082, … }`
  (rank 1) — the export confirms that id is the rank-1 member of this family.
* **Side finding (supports the tree's family-scoped seal table):** `27158` (Seal of
  Righteousness) is **ABSENT** from the 1.15.9 SoD spell table
  (`grep -c "^27158;" Spell.csv` → **0**). The SoD client has the Crusader seal and not the
  Righteousness one — consistent with the tree's family scoping.

**ANSWER P7: PROVEN for the Era/SoD client** — the ladder, the rank of 20308, the class, the
family and the *name* ("Seal of the Crusader", via the client's own 20335/28852 descriptions)
are all confirmed by the client's own data.
**NOT proven:** anything about Cata/Mists (the seal was removed in 4.0) or about the
*name string* those clients would answer for a name query — the export has no name column,
so the TBC-name leg still needs an in-client read (see §6).

### 4.2 P8 — the Healthstone: 5720 vs 6262

**The client's own data, by description token:**

```
/home/sam/wow.export/Spell.csv:2417   (id 5699)
	5699;;"Creates a Healthstone that can be used to instantly restore $5720s1 health.
/home/sam/wow.export/Spell.csv:2859   (id 6201)
	6201;;"Creates a Minor Healthstone that can be used to instantly restore $6262s1 health.
/home/sam/wow.export/Spell.csv:2862   (id 6202)
	6202;;"Creates a Lesser Healthstone that can be used to instantly restore $6263s1 health.
/home/sam/wow.export/Spell.csv:4853   (id 11729)
	11729;;"Creates a Greater Healthstone that can be used to instantly restore $5723s1 health.
/home/sam/wow.export/Spell.csv:4856   (id 11730)
	11730;;"Creates a Major Healthstone that can be used to instantly restore $11732s1 health.
```
→ **5720 = the Healthstone's use spell**; **6262 = the *Minor* Healthstone's use spell** (a
different spell); 6263 = Lesser, 5723 = Greater, 11732 = Major.

The two spell rows agree with that reading:
```
/home/sam/wow.export/Spell.csv:5720 →  5720;;Instantly restores $s1 life.
/home/sam/wow.export/Spell.csv:6262 →  6262;;Instantly restores $s1 life.
```
(identical description, **no** rank subtext on either — neither is a rank of the other), and
each has exactly **one** effect row in `SpellEffect.csv`:
```
/home/sam/wow.export/SpellEffect.csv:4990 → 684547;0;0;10;0;0;0;0;499;…;1,0;5720   → Effect 10 (HEAL), EffectBasePoints 499
/home/sam/wow.export/SpellEffect.csv:3653 → 683069;0;0;10;0;0;0;0;99;…;1,0;6262    → Effect 10 (HEAL), EffectBasePoints 99
```
(i.e. ~500 instant heal for the Healthstone, ~100 for the Minor one — the export's
`SpellEffect` header is column-mangled on the right-hand side, so the spell id is the
**trailing** field; the left-hand columns are aligned, which is why Effect (col 4) and
EffectBasePoints (col 9) are quoted as-is). Neither id has a `SkillLineAbility` row →
neither is a player-learned ability; both are **item-use** spells, as Healthstones are.

**This CONFIRMS the tree's own claim**, which is written in six class files:
`classes/druid.lua:4231-4233` — *"the Healthstone (the clients' own rank is 6262 — the Era id
5720 answers 'Not Found' there, and **6262 is a DIFFERENT spell on the classic clients —
'Minor Healthstone'** — so the ladder is NOT extended with it…)"* (mirrored at
`classes/hunter.lua:4964-4965`, `classes/rogue.lua:2994-2995`, `classes/warrior.lua:4896-4897`,
`classes/paladin.lua:4622-4623`). The "Minor Healthstone" half of that sentence is now
**PROVEN by the client's own data** instead of resting on a web page.

**ANSWER P8 (Era/SoD): PROVEN.** 5720 = Healthstone, 6262 = Minor Healthstone, and the tree's
deliberate decision **not** to extend the id ladder with 6262 is correct.

**NOT proven (and the export cannot prove it — it is Era/SoD data):**
* "the **Cata and Mists** clients' own rank is **6262**" — the tree's claim. On the Cata/Mists
  clients the *name* "Healthstone" must resolve to whichever id those clients use; the Era
  export cannot speak for them (and note that on Era the name "Healthstone" is 5720, so the
  name-first leg on a Cata/Mists client would land on 6262 **only if** those clients answer
  the name that way — the operator's in-client read, §6 P12-c).
* "the Era id **5720** answers 'Not Found' on Cata/Mists" — also a Cata/Mists claim, equally
  unprovable here.
* the **spell-name strings** the tree queries by name on TBC (`"Healthstone"`) — the export
  has no name column; only the descriptions carry names.

---

## 5. Does the tree's `compat.lua:157-176` assumption hold?

The tree's assumption, quoted:
```
compat.lua:156  -- Spell info -----------------------------------------------------------------------------
compat.lua:157  -- Classic shape: name, rank, icon, castTime, minRange, maxRange, spellID
compat.lua:158  -- Retail shape:  C_Spell.GetSpellInfo returns a SpellInfo table.
compat.lua:160  if GetSpellInfo then
compat.lua:161  	api.GetSpellInfo = GetSpellInfo
compat.lua:162  elseif C_Spell and C_Spell.GetSpellInfo then
compat.lua:163  	api.GetSpellInfo = function(spell)
compat.lua:164  		local info = C_Spell.GetSpellInfo(spell)
compat.lua:169  		return info.name, nil, info.originalIconID, info.castTime, info.minRange, info.maxRange, info.spellID
compat.lua:173  	api.GetSpellInfo = function()
compat.lua:174  		return nil, nil, nil, 1500, 0, 0, nil
```

**VERDICT: the assumption is NEITHER REFUTED NOR CONFIRMED offline. Its first three slots
are confirmed; slots 4–7 are an engine-side fact the reference repo cannot reach.**

| slot | offline status | evidence |
|---|---|---|
| 1 name | **PROVEN** — in a file the classic-line clients **load** | `classic_era:…/Blizzard_Collections/Classic/Blizzard_MountCollection.lua:641` `local spellName, _, spellIcon = GetSpellInfo(self.spellID);` (loaded: `Blizzard_Collections_Cata.toc`/`_Mists.toc`/`_Wrath.toc` are all `## AllowLoadGameType: classic` and all list `Classic\Blizzard_MountCollection.lua` at `:13`) |
| 2 rank / subname | **PROVEN** on the classic branch — by the **Cata/Mists-variant** files (`Cata/Blizzard_TalentUI.lua:673` `local name, subname, icon = …`; `Mists/SpellBookFrame.lua:906` `local name, subname = …`); **no file the Era client loads shows slot 2** | same native, other family variants |
| 3 icon | **PROVEN** — same line as slot 1 (`spellIcon`), and `select(3, GetSpellInfo(spellID))` → `SetTexture` | as above |
| 4 castTime | **UNPROVEN** | no call site unpacks 4+ on any branch |
| 5 minRange | **UNPROVEN** | same |
| 6 maxRange | **UNPROVEN** | same |
| 7 spellID | **UNPROVEN** | same |

Three consequences the orchestrator should carry forward:

1. **The C_Spell branch (`:162-170`) is self-consistent on all five branches** — it
   *manufactures* the 7 values from the documented `SpellInfo` struct, so on a client where
   the global is absent the shape is guaranteed. Nothing to fix.
2. **The classic-global branch (`:160-161`) is the only arity-sensitive path — and it is
   taken on *every* client where the global still exists, including Retail and Forever.**
   `compat.lua:160` prefers the **global** over `C_Spell`; the global demonstrably still
   exists on Retail (§2.4: `live:…/Mists/Blizzard_TalentUI.lua:671` calls it) and on the
   classic clients (`Blizzard_ObjectAPI/Classic/Spell.lua:39`). So the "is the 7th value the
   spell id?" question is **live on every shipped client**, not only on the classic line.
3. **The failure mode is a silent nil, not a crash.** If a client returned fewer than seven
   values, `spell_id` would be `nil` at the seven `pcall(api.GetSpellInfo, …)` call sites —
   the id-leg lookups would degrade (no icon / no rank art / an unresolved rank), with no
   error and no red test. That is exactly the shape of HIGH-2's "client's own rank art"
   question, so the arity probe in §6 **P12-a** is worth running on **every** client the
   operator has, not only one.

---

## 6. The operator's in-client list (P9–P12) — ready to paste into the live script

The live script lives at `bench/live_test_script_2026-10-19.md` (operator-run; read-only
scope). The rows below are written in its step format. **P9–P12 are RECONSTRUCTED** from the
four in-client rows of `bench/final_gate_audit_2026-10-20.md` §6 (C3, C4, C5, C6) plus the
probes this lane's evidence makes necessary (P12-a…c). Nothing here changes the addon.

**P9 — the Consecration icon button (reconstructed from C3).** On **TBC / Wrath / SoD /
Forever**: open the paladin practice scenario, wait for a step whose prompt reads
`next: cons`, and press the **icon** button (the one labelled by the guide vocabulary
`consecration`, not the bare text button `cons`). **Expect:** the press grades OK and the
step advances. **Report:** the exact grader line. *Pre-fix expectation (audit C3) was
`out of order: wanted cons, cast consecration` — that string means HIGH-1's fix did not
reach your client; a clean grade confirms the fix in-client.*

**P10 — the Seal of the Crusader button on Cata/Mists (reconstructed from C4).** On a
**Cata or Mists** client: open the paladin practice panel and list every offered button.
**Expect (MEDIUM-2 fix):** **no** "Seal of the Crusader" button — the seal was removed in 4.0
and the publish must be family-scoped. **Report:** the full button list. (P7's evidence
above shows the spell is absent from a 1.15.9-era table; the Cata/Mists absence is a
separate, in-client fact.)

**P11 — the shaman's common abilities on Cata/Mists (reconstructed from C5).** On a **Cata
or Mists** client: open the shaman practice panel and list every offered button.
**Expect (MEDIUM-1 fix):** the common abilities **are** offered (the `post_init` call to
`apply_practice_panel_actions()` landed, so the early return in `apply_family_slots` no
longer skips the panel). **Report:** the full button list.

**P12 — the family-scoped HUD ids + the three probes this lane needs (reconstructed from
C6).** On **every** client you can log into:
* **P12-a (the arity probe — the one this lane could not close).** Pick a spell the client
  **has** (Era/TBC/Wrath: `20308`; on any other client: any id from your own spellbook —
  **report which id you used**), then run exactly:
  `/run local n,r,i,ct,mn,mx,sid=GetSpellInfo(<ID>); print("SPELLINFO",n,r,i,ct,mn,mx,sid)`
  **Report the whole line verbatim, per client.** What settles it: `ct`/`mn`/`mx` are numbers
  (cast time, min/max range) and `sid` is the **same id you passed** → the 7-value shape and
  "the id is the 7th" are confirmed on that client; `sid` empty or nil → the shape is
  shorter there and the tree's `compat.lua:157-176` assumption does **not** hold on that
  client (record the client and the values that did come back). **Use a spell the client
  has** — a probe on a spell the client does not have answers nil for every slot and says
  nothing about the arity. (The line prints in the chat frame; keep
  `/console scriptErrors 1` on, per the script's preconditions.)
* **P12-b (the name probe).** Run both, on every client:
  `/run print("SPELLNAME", GetSpellInfo("Fireball"))` → a name → the global takes names there;
  `nil` → it does not.
  `/run print("SOTC", GetSpellInfo("Seal of the Crusader"))` → the classic-line rows.
  **Report the lines, per client.** (On Retail/Forever/Cata/Mists the seal does not exist, so
  only the "Fireball" line says anything there; the seal line is for Era/TBC/Wrath.)
* **P12-c (the Healthstone id on Cata/Mists).** On a **Cata or Mists** client run:
  `/run print("HS", GetSpellInfo(5720), GetSpellInfo(6262), GetSpellInfo("Healthstone"))`
  **Report the line.** What settles it: which of 5720 / 6262 answers, and whether the
  **name** "Healthstone" answers and which id it resolves to (the tree claims 6262 is the
  Cata/Mists Healthstone — §4.2 shows that on Era 6262 is the *Minor* Healthstone, so the
  tree's Cata/Mists id claim is **UNPROVEN** until this line comes back).
* **P12-d (the C6 row itself).** **Forever:** the hunter HUD has **no Steady Shot** slot.
  **Cata/Mists:** the hunter HUD has **no `raptor` slot**. **Report:** the slot list per
  client.

---

## 7. What is still open after this pass

| # | item | why it is still open | who |
|---|---|---|---|
| 1 | the classic global's **return arity** (slots 4–7; is the id the 7th?) | engine-side (C++); no Lua definition, no doc entry, no call site unpacks 4+ on any of the five branches | operator — P12-a |
| 2 | does the classic global take a **name** on **Era / TBC / Wrath** | the only name-form call site on those branches sits in the Mists file, which those clients do not load; proven on Retail/Mists only | operator — P12-b (+ the standing TBC rule, `bench/lessons.md:29-31`) |
| 3 | the **Cata/Mists** Healthstone id (5720 vs 6262) and "5720 answers Not Found" | the operator's export is Era/SoD data; a Cata/Mists export would settle it | operator — P12-c |
| 4 | the **Cata/Mists** Seal-of-the-Crusader absence | the spell was removed in 4.0; the Era export cannot prove a Cata/Mists absence | operator — P10 |
| 5 | the **Cata/Mists** name strings for the name-first leg | the export has **no** name column at all; only descriptions carry names | operator — P12-b/c |
| 6 | the spell **name** strings on TBC (the query the tree actually issues) | the tree resolves names on TBC; the source shows only that ids work there | operator — P12-b (TBC) |

Nothing in this file requires a tree change. The two tree comments that name the open
question (`classes/druid.lua:4236-4238` and the five sibling copies) are **narrowed**, not
contradicted: the global's name-acceptance is now PROVEN on Retail and Mists, and still
UNCONFIRMED in-client for Era/TBC/Wrath.

---

## 8. Provenance

* Reference repo: `/home/sam/wow-ui-source` — `git show`/`git grep` only; the checked-out
  branch (`classic_era`) was never changed; no checkout was performed.
* Client spell data: `/home/sam/wow.export` (the operator's 1.15.9 SoD client) — read-only.
* Prior art not re-searched: `bench/perclient_api_truth_2026-10-20.md` (the 19-check table,
  checks 16 = `C_Spell.GetSpellInfo`), `bench/perclient_api_audit_2026-10-19.md` §1,
  `bench/f4_family_spell_id_2026-10-19.md` §1, `bench/lessons.md:29-31`, `hands-up.md`
  HU-6 / HU-16 / HU-17.
* Validation owner: **orchestrator**. This lane changed no addon, no test and no other bench
  file.
