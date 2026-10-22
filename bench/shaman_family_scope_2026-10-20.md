# shaman-family-scope — the release-gate blocker B1 (2026-10-20)

Desk: `desks/shaman-family-scope/`. Scope: `classes/shaman.lua`,
`shaman_guide.lua` (untouched — the gate needed no engine change),
`tests/shaman_state.lua`, `tests/shaman_guide_state.lua`.

## 1. The blocker, as it stood

The shaman's practice surface was **not family-scoped**:

* `ST.SHAMAN.practice_rotation` (`classes/shaman.lua:4314` before this lane) is a
  flat 22-row table; every row carries a per-row `families` list, but **nothing
  read that field at runtime** — the list was token-validated by the suite and
  nothing else.
* There was **no `practice_rotation_for` accessor**, so
  `practice_ui.lua`'s `practice_rotation_entries` (`practice_ui.lua:848-875`)
  got nil and the panel fell back to the guide-slot vocabulary.
* `ST.SHAMAN.guide.slots` was a **single static 22-slot list** with no family
  filter (`classes/shaman.lua:3592` before this lane).

The live consequence: the panel's action strip (the rotation slice + the guide
slot keys + the keys the engine asked for — `practice_ui.lua`'s
`scenario_action_order`) offered **every** row on **every** client. A TBC
client was offered the Wrath-only Call of the Elements and Bloodlust rows and
the Era-only Molten Blast, Lava Lash, Chain Lightning, Windfury Totem and
Grace of Air rows — rows the TBC APL never plays, so pressing one of them
could only ever grade wrong. That is the direct violation of
`TESTING.md:183` ("A family that does not carry a row must never show it").

## 2. What landed

### 2.1 The family-scoped accessor (druid shape, `classes/druid.lua:3380-3395`)

| New function | Line | What it answers |
|---|---|---|
| `ST.SHAMAN.rotation_row_families(entry)` | `classes/shaman.lua:4462` | one rotation row's family set (the row's own `families` **list** — the cross-class convention is a set, this table is a list) |
| `ST.SHAMAN.practice_rotation_family()` | `classes/shaman.lua:4483` | the running client's family token (`compat.lua`'s) — the panel's readout |
| `ST.SHAMAN.practice_build_family()` | `classes/shaman.lua:4494` | the running **build's** own token: `"SOD"` on the ERA token once the MW-rune latch fires (the same latch the guide's SoD gates read) |
| `ST.SHAMAN.practice_rotation_for(family)` | `classes/shaman.lua:4525` | the family's rows, in the table's own order |

An **explicit** family answers that family alone (the pins walk the families
one by one); the **argument-free** call (the panel's call) answers the
client's family **plus** the running build's token, so the SoD build's own row
rides the ERA slice — the same shape as the paladin's SoD orders
(`classes/paladin.lua:4823-4866`). An unknown family answers an empty slice
(never a guess, never another family's rows).

### 2.2 The family-scoped guide slots

The guide's slot set is cut from the **same** `families` list, so the rotation
rows and the guide slots can never disagree about what a family carries:

* `ST.SHAMAN.GUIDE_SLOTS` (`classes/shaman.lua:3614`) — the class's **full**
  vocabulary (22 slots, the display order). It is the guide frame's own icon
  set; the frame stacks one icon per slot and fades in only the current
  action's, so the family's narrower set changes **nothing** the player sees
  in the frame.
* `ST.SHAMAN.family_guide_slots(family, extra)` (`classes/shaman.lua:4550`) —
  the family's cut, in the display order.
* `ST.SHAMAN.apply_family_slots()` (`classes/shaman.lua:4589`) — narrows the
  published `guide.slots` to the running family's set. It is called from
  `post_init` **after** the guide frame and the HUD are built and before the
  practice surface is wired (`classes/shaman.lua:1457`), because the panel
  reads `guide.slots` **live** while the frame's icons are built once and
  never rebuilt. The applied token makes the call idempotent, and the
  latch-driven re-cut (`classes/shaman.lua:857`, in
  `refresh_weave_mw_stacks`) re-runs it when the SoD build becomes known.

`rotation_ability_name` now reads the **full** vocabulary
(`classes/shaman.lua:4883`), so the rotation label resolves for every action
the engine can name — the label must not depend on the practice vocabulary.

### 2.3 The family truth (the shipped table, derived)

| Family | Rows the family's APL carries | Count |
|---|---|---|
| ERA | feralspirit, shamanisticrage, weave, flameshock, strength_of_earth, wftotem, goa, stormstrike, searing, lavalash, chainlightning, earthshock, moltenblast | 13 |
| SOD (the SoD build's own token) | lightningshield | 1 |
| TBC | fireele, shamanisticrage, weave, flameshock, twist, strength_of_earth, mana_spring, stormstrike, searing, magma, firenova, frostshock, earthshock | 13 |
| WRATH | fireele, feralspirit, bloodlust, shamanisticrage, weave, flameshock, stormstrike, magma, firenova, lightningshield, lavalash, earthshock, coe | 13 |
| FOREVER | flameshock, strength_of_earth, stormstrike, searing, firenova, lightningshield, earthshock | 7 |

The TBC strip therefore loses exactly the nine rows the audit named: `coe`,
`bloodlust`, `lightningshield` (Wrath-only for the strip) and `moltenblast`,
`lavalash`, `chainlightning`, `wftotem`, `goa`, `feralspirit` (Era-only).

### 2.4 The pre-pull table, labelled honestly

`ST.SHAMAN.PRACTICE_PREPULLS` has **no consumer**: the class ships no pre-pull
drill (only the warrior, the hunter and the rogue have one), and no production
file reads the table. The class file now says so
(`classes/shaman.lua:4620`, the paladin's wording), and the suite pins it: a
source scan of the production tree (`tests/shaman_state.lua:3418-3450`) fails if any
file outside `classes/shaman.lua` names `ST.SHAMAN.PRACTICE_PREPULLS`.

## 3. The pins

`tests/shaman_state.lua` (class side):

* **(a)** the per-family slice **derived from the shipped table**, asserted per
  family with the exact action set **and** order (`tests/shaman_state.lua:2821`,
  `:2852`) — the druid's shape (`tests/druid_state.lua:2757-2760`).
* **(b)** the accessor returns exactly that slice (same block).
* the family's guide slot set, its display order and its equality with the
  family's rotation rows (`tests/shaman_state.lua:2837`, `:2880`).
* every live rotation line names a declared guide slot — **per family** now
  (`tests/shaman_state.lua:2902`); the old flat pin could not hold once the
  slot list is the family's cut.
* **(c) the strip-vocabulary pin** (`tests/shaman_state.lua:2911-2945`): the
  TBC strip (rotation slice ∪ guide slot keys) carries **no** Wrath-only and
  **no** Era-only key, and every key it carries is a row the TBC APL plays.
  The published `guide.slots` is the running family's set.
* the SoD build: the argument-free accessor on the ERA token carries the ERA
  rows, and the latch adds the build's own row (`tests/shaman_state.lua:2946-2975`).
* the pre-pull table's "no consumer" scan (`tests/shaman_state.lua:3449`).

`tests/shaman_guide_state.lua` (engine side):

* every client's live answer (through the **real gather**) names a slot in
  that client's set (`tests/shaman_guide_state.lua:1846-1871`).
* every family gate that admits a row has that row in the family's set
  (`tests/shaman_guide_state.lua:1873-1906`).
* the SoD build's set carries the Lightning Shield row and keeps the shared
  rows; the Era-base set does not (`tests/shaman_guide_state.lua:1908-1919`).

## 4. Mutation proofs (`/tmp/opencode/mut_shaman_family`)

Nine mutants, **9/9 killed**:

| Mutant | Killed by |
|---|---|
| M1 the accessor loses its family gate | the per-family slice pins (22 rows instead of 13) |
| M2 the guide slot cut loses the family filter | the per-family guide slot pins |
| M3 the accessor loses the build token | the SoD slice pins |
| M4 `post_init` never applies the cut | "the published guide slots are the running family's set" |
| M5 the SoD latch is ignored | the SoD slice pins |
| M6 the row's family list walk drops its last token | the per-family slice pins |
| M7 the guide cut ignores the build token | the guide-side family-scope pins |
| M8 the published list is never narrowed | "the published guide slots…" + "the guide carries the TBC slots" |
| M9 a production file reads the pre-pull table | the "no consumer" scan |

## 5. Harness

`bash tests/run.sh` → **41 steps, 0 failed**; `luacheck .` → **2 warnings / 0
errors** (the floor, unchanged). The shaman's own suites: `shaman_state.lua`
**834 checks**, `shaman_guide_state.lua` **1570 checks**, `guide_contract.lua`
**1052 checks** (untouched), `practice_ui_state.lua` **1623 checks** (untouched).

`classes/shaman.lua` stays at **199 file-scope locals** (Lua 5.1's cap is
200): every new function is a `ST.SHAMAN` table field, no new file-scope local.

### Crossfire note

Between 11:45 and 11:57 the hunter suites (`hunter_state`, `hunter_guide_state`,
`hud_state`) were red while a parallel hunter lane was mid-edit on
`classes/hunter.lua` (mtime 11:52:19, `tests/hud_state.lua` 11:57:21). Those
suites never load the shaman module; the failures were the hunter's own Steady
rank / range-probe checks. The final run on the settled tree is green.

## 6. Residuals / not closed here

* **The ERA token carries two games.** The table's ERA rows are the token's
  truth: the SoD-only lines (moltenblast, lavalash, chainlightning,
  feralspirit) are listed under ERA, so an **Era-base** client is offered them
  too — the shipped table's claim, and the engine's gates keep those prompts
  dark. Splitting the two builds' rows needs a per-row build marker the table
  does not carry: a **filed refinement of the rotation table**, not a change
  made here. The task's own offender list calls those rows "(ERA)", so the
  slice follows the table.
* **The guide frame keeps the class's full 22-slot icon set.** The frame
  stacks one icon per slot and fades in only the current action's, so this is
  invisible to the player; `tests/guide_contract.lua`'s 22-slot pin (a
  different lane's file, out of scope here) is untouched and green.
* **`ST.SHAMAN.PRACTICE_PREPULLS` still has no consumer** — now labelled as
  such, with the pin that keeps the labelling honest.
* The Fire Elemental row is known-gated, not family-gated, in the gather, so
  the engine can still answer `fireele` on a client whose APL does not rank
  it. Pre-existing (the rule matrix is feed-gated); the row's own `families`
  list is the APL truth. Not changed here.
