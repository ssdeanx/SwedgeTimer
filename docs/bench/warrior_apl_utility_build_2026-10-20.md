# The warrior's APL utility spine + the pre-pull table — 2026-10-20

Desk: `warrior-apl`. The build lane that answers the operator's "a rotation that
only carries the damage abilities is not the class's rotation" for the warrior.

**Source spec:** `bench/rotation_gap_vs_apl_2026-10-20.md` section 1 (the
warrior). Every id and every priority index below was re-read out of the APL
files themselves (fetched 2026-10-20, `wowsims/{classic,sod,tbc-new,forever,
wotlk}` master) rather than taken from the gap analysis, and the two places
where the fetched files disagree with the gap analysis are recorded in §4.

**What changed (4 files, 2 of them touched):**

| file | change |
|---|---|
| `classes/warrior.lua` | `ST.WARRIOR.practice_rotation` gains the APL's utility spine (13 lines) as a second block; the `hamstring` row's 18499 citation is corrected; `ST.WARRIOR.PRACTICE_PREPULLS` is new |
| `tests/warrior_state.lua` | the rotation-order pin becomes the two-block pin; new section 38 pins the utility spine, the corrections, the no-prompt proof and the pre-pull table |
| `warrior_guide.lua` | **not touched** — no new rule, so no new prompt (see §3) |
| `tests/warrior_guide_state.lua` | **not touched** — the guide's behaviour did not change |

---

## 1. The rotation table's second block

The shipped table carried 13 keys, every one of them a damage ability or a
debuff upkeep. The utility spine adds the rows the sims' priority lists carry
and the compiled rule order does not. Each line carries `action`, `label`,
`reason`, the id path (`spell_id`, or `spell_ids` where the id splits by
family), the TBC name path (`spell_name`), the family gate (`families`),
`live = false` and the `needs` field (the exact read + the exact rule the line
waits for). The `source` cites the APL file and the priority index.

| action | spell | id(s) | families | APL position | read it needs |
|---|---|---|---|---|---|
| `battle_stance` | Battle Stance | 2457 | ERA(SoD), TBC, FOREVER | sod [1] [5]; tbc [16] g; forever arms [13] [25] | **exists** (the stance walk) |
| `berserker_stance` | Berserker Stance | 2458 | ERA, TBC, WRATH, FOREVER | era [24]; sod [2] [3] [6]; tbc [16] g, [17], [23] [24]; forever arms [19], fury [20] [26] [27]; wotlk fury [16] | **exists** (the stance walk) |
| `gladiator_stance` | Gladiator Stance | 412513 | ERA(SoD) | sod [0] [4] | **missing** (412513 is not in `WARRIOR_STANCES.ids`) |
| `bloodrage` | Bloodrage | 2687 | ERA, TBC, WRATH, FOREVER | era [21]; sod [7]; tbc fury [20] / arms [21]; forever arms [28] / fury [23]; wotlk [1] | missing (`api.GetSpellCooldown` + rage) |
| `battle_shout` | Battle Shout | ERA 25289 / TBC 2048 / FOREVER 25289 | ERA, TBC, FOREVER | era [23]; tbc [22]; forever arms [29] / fury [25] | **exists** (the Battle Shout badge walk) |
| `recklessness` | Recklessness | 1719 | ERA(SoD), TBC, FOREVER | sod [14]; tbc [9]; forever arms [11] / fury [11] | missing (`api.GetSpellCooldown`) |
| `death_wish` | Death Wish | ERA 12328 / TBC 12292 / FOREVER 12328 | ERA, TBC, FOREVER | era [3]; sod [12]; tbc [8]; forever arms [10] / fury [10] | missing (`api.GetSpellCooldown` + the name query on TBC) |
| `sweeping_strikes` | Sweeping Strikes | 12723 | TBC, FOREVER | tbc [10]; forever arms [12] / fury [12] | missing (`api.GetSpellCooldown`) |
| `thunder_clap` | Thunder Clap | 47502 | WRATH | wotlk arms [11] | missing (`api.GetSpellCooldown`) |
| `shattering_throw` | Shattering Throw | 64382 | WRATH | wotlk fury [9] | missing (`api.GetSpellCooldown`) |
| `heroic_throw` | Heroic Throw | 57755 | WRATH | wotlk fury [15] | missing (`api.GetSpellCooldown`) |
| `berserker_rage` | Berserker Rage | 18499 | ERA, TBC, FOREVER | era [22]; tbc fury [21]; forever fury [24] | missing (`api.GetSpellCooldown`) |
| `blood_fury` | Blood Fury (Orc) | 20572 | ERA (the Era build) | era [7] | missing (`api.GetSpellCooldown` + the racial check) |

**Every read is an existing `compat.lua` wrapper** — `api.GetSpellCooldown`
(`compat.lua:229`), `api.UnitPower` (`compat.lua:349`), `api.scan_player_aura`
(`compat.lua:514`), `api.get_spell_query` (`compat.lua:1544`). **No new client
API.** The reads that do not exist yet are filed per line in the `needs`
field, with the exact call they need.

**Family gates.** The `families` field names the families whose APL carries
the line as a SPELL ROW. On the ERA family the SoD branch is the one that
plays the SoD-only lines (the table's header says so, and each such line's
source names which build plays it — the Era APL has no Battle Stance row, its
Recklessness rows are `IF false`, and its pre-pull carries no Blood Fury).

**The id splits** (the family-split id traps, each pinned in the test):
`25289` is Battle Shout rank 6 on Era/Forever and rank 7 on TBC, whose rank 8
is `2048`; `12292` is Death Wish on TBC **and Sweeping Strikes on Forever**;
`11578` is Charge rank 3 on TBC/Forever and `100` is rank 1; `25275` is
Intercept rank 5 on TBC and `20617` rank 3 on Forever; `33697` is Blood Fury
rank 2 on TBC and `20572` rank 1 elsewhere.

## 2. The pre-pull table (`ST.WARRIOR.PRACTICE_PREPULLS`)

The operator's ruling (HU-12, 2026-10-20): the rotation table carries the
APL's spell rows; the APL's pre-pull rows carry their own table — the shape
`ST.HUNTER.PRACTICE_PREPULLS` already uses. **Charge and Intercept are in no
rotation block.** The table is keyed by family (SOD = the SoD branch of the ERA
family; the Era build's APL has no `prepullActions` at all, so there is no ERA
list) and each row carries `action`, `label`, `spell`, `at` (seconds relative
to the pull, negative = before) and `source`.

| family | rows (action @ offset) |
|---|---|
| SOD | berserker_stance 2458 @ -1, bloodrage 2687 @ -5 |
| TBC | berserker_rage 18499 @ -4.5, bloodrage 2687 @ -3, battle_shout 2048 @ -3, charge 11578 @ -0.9, intercept 25275 @ -0.9 |
| FOREVER | berserker_rage 18499 @ -4.5, battle_stance 2457 @ -4 (arms only), bloodrage 2687 @ -3, battle_shout 25289 @ -3, charge 11578 @ -0.9, intercept 20617 @ -0.9 |
| WRATH | berserker_stance 2458 @ -20 (fury), bloodrage 2687 @ -10, berserker_rage 18499 @ -5 (fury), recklessness 1719 @ -3, battle_stance 2457 @ -2 (arms), death_wish 12292 @ -1.5 (fury) |

The consumable rows the APLs also carry (the Healthstone 22788, the Diamond
Flask 24427, the `OtherActionPotion` rows) are items, not spells, and stay out.

## 3. No prompt, no default-visible change

Every line of the utility spine is `live = false`, and the guide has **no rule**
for any of the thirteen keys: the guide's own vocabulary, read out of
`warrior_guide.lua`'s source, is twelve keys
(`bladestorm, bt, execute, hamstring, hs, ms, op, raging_blow, rend, slam,
sunder, ww`) — the thirteen compiled keys minus `cleave`, which no rule ever
outputs. A rotation line that no engine action can produce therefore never
prompts, and the practice surface never expects a cast it cannot grade. The
test pins that vocabulary, so a future lane that adds a guide rule for one of
these keys has to flip `live` consciously.

## 4. Where the fetched APLs disagree with the gap analysis

1. **A new family-split id trap the gap analysis missed: `12292`.** It is
   **Death Wish on TBC** (`wowsims/tbc-new sim/warrior/talents_arms.go:314`)
   and **Sweeping Strikes on the Forever client**
   (`wowsims/forever sim/warrior/spell_data_auto_gen.go:262` —
   `SweepingStrikes: 12292`). The gap analysis listed Sweeping Strikes as
   "12292 / 12723 (TBC)". The lines here carry the APL's cast id (12723 on
   both TBC and Forever) and the source records the split.
2. **The SoD pre-pull does not carry Blood Fury.** The gap analysis's
   `blood_fury` row says "SoD prepull". The fetched
   `wowsims/sod ui/warrior/apls/phase_6_dw.apl.json` pre-pulls 2458 (Berserker
   Stance) at -1 s, 24427 (the Diamond Flask item) at -1 s and 2687
   (Bloodrage) at -5 s. The `blood_fury` line is therefore gated to the ERA
   family's Era build, and its source says so.
3. **The gap analysis listed only the WotLK fury pre-pull.** The WotLK arms
   pre-pull is different: 2687 @ -10 s, 1719 @ -3 s, 2457 @ -2 s and an
   `OtherActionPotion` row. The pre-pull table carries the union with the spec
   marked (`specs = { arms = true }` / `specs = { fury = true }`, the marker
   the hunter's rotation table already uses).
4. **The gap analysis's missing-line table omits the Gladiator Stance**, which
   its own APL listing carries (the SoD APL's [0] and [4] — the APL's top
   row). Added, because it is the same utility layer the operator named, and
   cited to two sim sources: `wowsims/sod proto/warrior.proto:131`
   (`RuneGladiatorStance = 412513`) and `wowsims/sod sim/warrior/stances.go:212`.
   It is the one line whose READ does not exist (412513 is not in
   `WARRIOR_STANCES.ids`).
5. **Blood Fury's TBC id is a rank, not a different spell**: `33697` is Blood
   Fury rank 2 (`wowsims/tbc-new sim/core/racials.go:196`), `20572` rank 1
   (`wowsims/classic sim/core/racials.go:78`).

## 5. Deliberately NOT carried

* **The sim-harness rows** — the `CD: Trinkets` / `Engineering` /
  `CD: Racials` groups, the potion rows, `autocastOtherCooldowns`: the sim's
  pop-everything layer, not rotation decisions (gap analysis §1.4). The
  `CD: Racials` group is why the Blood Fury line is gated to the Era build
  alone and why **Berserking** (26296 on TBC, 20554 on Forever) is absent — it
  never appears as a spell row.
* **Demoralizing Shout** — no fetched warrior APL casts it (gap analysis
  §1.4).
* **Shield Wall 871 / Retaliation 20230** — every fetched APL's row is
  `IF false` (gap analysis §1.4).
* **The WotLK-only lines on the classic-line clients** (Thunder Clap,
  Shattering Throw, Heroic Throw): the classic-line clients carry the spells,
  but no fetched classic-line APL casts them.

## 6. Validation

* **Offline only.** Nothing here was loaded in a game client. Per `CAIRN.md`
  ("two proofs, two words") this is a source-cited build with a
  mutation-proofed offline pass, not a verified-in-client one. The lines whose
  id is marked UNCONFIRMED by the gap analysis (§7.4 of that file) are not
  among the thirteen built here; the four ids this desk confirmed from the
  sims' own data are 2457 / 2458 (the stance auras), 2687 (Bloodrage), 18499
  (Berserker Rage), 20572 (Blood Fury) and 412513 (the Gladiator Stance rune).
* `bash tests/run.sh` → **41 steps, 0 failed**; luacheck **2 warnings / 0
  errors in 83 files** (the two warnings are the pre-existing ones in
  `compat.lua:36` and `main.lua:81` — both untouched by this lane).
* `tests/warrior_state.lua` → **PASS (1564 checks)** (was 1230): the new
  section 38 adds 334 checks over the utility spine's shape, its citations, the
  two corrections, the no-prompt proof and the pre-pull table.
* `tests/warrior_guide_state.lua` → **PASS (1728 checks)**, unchanged (the
  guide did not change).
* **Mutation proofs: 11/11 killed** on `/tmp/opencode` copies (the script is
  at `/tmp/opencode/mut_warrior_apl.py`, the tree copy at
  `/tmp/opencode/mut_warrior_apl`): the family gate losing a family, either
  family-split id moving to the wrong family's id, a `live` flag flipping, the
  guide gaining a rule for a utility key, a citation losing its APL index, the
  old 18499 hamstring note coming back, a pre-pull row dropped, a pre-pull
  offset moved, a pre-pull id swapped, and Charge being put back into the
  rotation table — every one of them fails the suite on the expected check.
* **Validation owner: the orchestrator.**

## 7. What this lane did NOT do (the next lane's work)

* No guide rule, no engine prompt, no scenario change: the utility lines are
  documentation until a lane gives each one its rule and its read. The `needs`
  field names both.
* No `practice_rotation_for` for the warrior, so the practice panel's button
  vocabulary is unchanged (the panel falls back to the guide's slot keys).
  A lane that adds it must publish the **live** lines only.
* No option, no toggle, no default-visible change of any kind.
* The other five classes have no prepull table yet; the hunter's and now the
  warrior's are the only two.
