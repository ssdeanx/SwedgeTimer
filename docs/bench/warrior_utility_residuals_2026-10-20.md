# The warrior's utility residuals close — 2026-10-20

Desk: `warrior-utility-residuals`. The lane that closes the three residuals the
utility-live lane filed (bench/warrior_apl_utility_live_2026-10-20.md §7 and the
filed residuals): the `gladiator_stance` row with no honest arm, the missing
`practice_rotation_for` accessor, and the APL's target-count / Bloodlust-alignment /
execute-phase gates.

**What changed (4 files, all in scope):**

| file | change |
|---|---|
| `classes/warrior.lua` | the rotation slice the panel publishes (`practice_rotation_for` + `practice_rotation_family` + the slot-set gate), the labels on the compiled-order rows, the execute-phase clause on the rage dump (the provider's family gate), and the Gladiator Stance row's sharper filing |
| `warrior_guide.lua` | the pure helper `dump_blocked_in_execute` and the rule-7 gate (the APL's execute-phase clause on the Heroic Strike dump) |
| `tests/warrior_state.lua` | the new section 40 (the accessors + the per-family slices + the provider's phase gate + the Gladiator filing) |
| `tests/warrior_guide_state.lua` | the new execute-phase gate section (the pure helper + the rule-7 integration) |

Nothing else moved: no option, no toggle, no default-visible UI, no new client API
(every read is an existing wrapper or an existing input), no TOC, no version.

---

## 1. Residual 1 — `gladiator_stance` (412513): the gate is the SET bonus, not a rune

**Verdict: `engine = false` stands. The reason is now sharp, and the missing read is
named.**

The filed reason said the SoD APL gates the row on "a rune aura the client cannot
answer". That was wrong on the facts, and the wrong taxonomy is what kept the row
unresolvable. The truth, read out of the sim sources:

* The SoD APL's Gladiator Stance rows (`[0]` and `[4]`) are gated on
  `auraIsKnown(457817)` and `auraIsKnown(464241)`
  (wowsims/sod `ui/warrior/apls/phase_6_dw.apl.json`).
* In the sim, `auraIsKnown` answers **"the aura is REGISTERED on the unit"**, not
  "the aura is active" (wowsims/sod `sim/core/apl_values_aura.go`:24-26 —
  `value.aura.Get() ~= nil`; the sibling `auraIsActive` is the one that asks
  `.IsActive()`).
* The auras those ids name are the **SoD T1 damage set bonus**, not a rune:
  `464241` is the 2-piece "Tactician", `457816` / `457817` are the 6-piece
  "Battle Forecast" / "Berserker Forecast" (wowsims/sod
  `sim/warrior/item_sets_pve_phase_4.go`:78-215 — `applyT1Damage2PBonus` /
  `applyT1Damage6PBonus`; wowsims/sod `ui/core/proto_utils/action_id.ts`:765-766
  names 457816 / 457817 "Battle Forecast" / "Berserker Forecast" with their wowhead
  links). The SoD **rune** ids are the proto's (wowsims/sod
  `proto/warrior.proto`:131 — `RuneGladiatorStance = 412513`).

So the gate is an **equipment fact** — "the player wears the six pieces of the T1
damage set" — and the client's aura list cannot answer it, because the aura list
reports the ACTIVE auras only.

**What the client CAN answer (the row's second clause):** the "Berserker Forecast"
aura 457817 exists in the 1.15.9 client's spell table (wow.export `Spell.csv` —
`457816` "Increases Physical damage done by $s1%.", `457817` "Increases Critical
Strike chance by $s1%.", `464241` "Reduces the rage cost of your next offensive
ability by $s1."), and the class's HELPFUL aura walk (`api.UnitAura`, compat.lua:457)
reports an ACTIVE aura's id and its expiration — so `auraRemainingTime(457817) <= 3 s`
is readable **while the Forecast buff is up**.

**What the client CANNOT answer (the exact missing read):** the set ownership. The
buildable read is an equipped-item / set-membership read — *are the six pieces of the
SoD T1 warrior damage set equipped* — and it is buildable from the EXISTING wrapper
`api.is_item_equipped(item_id)` (compat.lua:1121) **once the six item ids are
cited**. They are not cited in any fetched source today: the sim's item DB is not in
the corpus, and the client's own `GetItemSetInfo(setID)` (wow-ui-source
`classic_era`: `Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua`:645)
wants a set id the addon has no read for. **That is the filed read: the six item
ids of the "S03 - Item - T1 - Warrior - Damage" set** (or a set-membership wrapper).

**Both halves are needed.** The sim's row also fires when the aura is known but NOT
active (the remaining time reads 0, which is `<= 3 s`), and the client's "the buff
is absent" cannot tell "no set" from "set, buff down" — so the ownership read is
what makes the whole clause reproducible. The row therefore stays `engine = false`
(the two-flag convention doing its job: the read exists, the arm does not), and the
row's `needs` now carries the whole chain, cited.

## 2. Residual 2 — the rotation slice the panel publishes

**Verdict: closed.** The warrior publishes `ST.WARRIOR.practice_rotation_for(family)`
and `ST.WARRIOR.practice_rotation_family()` (the hunter's shape; the panel calls the
first argument-free and falls back to the guide slot vocabulary when a class
publishes none — practice_ui.lua:848-890).

**The slice rule:** a rotation row joins the family's slice when

1. the running client's own **guide vocabulary** names its action — the class's
   resolved slot set (`ST.WARRIOR.guide.slots`, re-picked per family and per spec in
   post_init), which is exactly the set of actions the engine can name on that
   client (the utility lane gave every engine-armable utility row a slot); and
2. the row is askable: `engine ~= false` (cleave — no rule ever outputs it — and
   the Gladiator Stance row, which has no arm) and `live ~= false` (a row whose read
   does not exist is never a button that can be the right answer).

The slice is cut from the rotation table's own order (the compiled rule order, then
the APL's utility spine). The panel's strip is a button set, not a priority list —
the engine's ask order interleaves the two blocks (the APL's high rows sit above the
core).

**The per-family slices** (the pinned lists, the class's own vocabulary each):

| family | slice |
|---|---|
| ERA | op, execute, slam, bt, ww, hamstring, hs, berserker_stance, bloodrage, battle_shout, death_wish, berserker_rage, blood_fury |
| SOD | op, execute, slam, rend, bt, ww, raging_blow, hs, battle_stance, berserker_stance, recklessness, death_wish |
| TBC | op, execute, slam, sunder, bt, ww, hs, battle_stance, berserker_stance, bloodrage, battle_shout, recklessness, death_wish, sweeping_strikes, berserker_rage |
| WRATH (fury) | op, execute, slam, bt, ww, hs, berserker_stance, bloodrage, shattering_throw, heroic_throw |
| WRATH (arms) | op, execute, rend, bladestorm, ms, hs, bloodrage, thunder_clap |
| FOREVER | op, execute, slam, sunder, hamstring, hs, battle_stance, bloodrage, battle_shout, recklessness, death_wish, sweeping_strikes |

The compiled-order rows now carry a **label** (the spell's English name) so the
panel's buttons read as spells, not action keys (the panel falls back to the action
key when a class publishes no label).

**Two documented deviations, both filed below:** the SoD strip carries no Bloodrage
(the SoD APL's `[7]` row is not in the engine's SoD order — the utility lane's order
table gap), and the strip mirrors the ENGINE's vocabulary, not the APL's row list
(the SoD strip carries Execute, which the SoD APL has no row for, because the
engine's SoD guide can name it).

## 3. Residual 3 — the three unmodelled APL gates

The utility lane filed them as "not modelled, no read exists". That was true for two
of the three and wrong for the third.

### 3a. The execute-phase gate — **WIRED** (the read exists)

The Execute phase is the warrior's own domain and the class already knows it: the
target's health fraction against the class's execute percentage (`inputs.target_health_pct`
/ `inputs.execute_pct`) — the same read the Execute rule (rule 2) already uses. The
gate that was missing is the APL's **NOT**-in-phase clause on the **Heroic Strike
dump**:

| APL | row | clause |
|---|---|---|
| wowsims/tbc-new `ui/specs/warrior/dps/apls/fury.apl.json` `[18]` | Heroic Strike 29707 | `numberTargets == 1 AND NOT isExecutePhase E20 AND currentRage >= 40` |
| wowsims/forever `ui/specs/warrior/dps/apls/arms.apl.json` `[27]` | Heroic Strike 25286 | `NOT isExecutePhase E20 AND currentRage >= 90` |
| wowsims/classic `ui/warrior/apls/dps_no_reck.apl.json` `[18]` | Heroic Strike 25286 | `numberTargets == 1 AND (currentRage >= 40 OR isExecutePhase E20)` — the Era APL **allows** the dump inside the phase |
| wowsims/sod `ui/warrior/apls/phase_6_dw.apl.json` `[8]` | Heroic Strike 25286 | no phase clause |
| wowsims/wotlk `ui/warrior/apls/{arms,fury}.apl.json` | (no Heroic Strike row) | the fury APL's phase row is Execute 47471 `[12]` |

So the clause is a **TBC + Forever** clause, and the provider now arms it there and
only there (`inputs.execute_phase_dump_gate`; nil on Era / SoD / WotLK, so those
families keep their legacy shape byte-identically). The engine's rule 7 withholds
the dump on a KNOWN sub-threshold target.

Reading the unknown: a target with no known health is **not** in the phase (there is
no target), so the clause holds and the dump keeps its legacy shape; a KNOWN
sub-threshold health withholds it. The gate is a prohibition on a filler, not a
spend the player cannot afford, so an unreadable phase never silences the dump.

**The consequence, stated plainly:** on TBC / Forever, inside the execute phase, the
guide no longer answers "Heroic Strike" when the Execute row is itself withheld by
the core's rage reservation (the house's own deviation from the APL: the engine
never spends at the core's expense, the APL's Execute row has no rage clause). The
guide shows no action there instead of an action the APL forbids.

### 3b. The target-count gate — **FILED** (no read exists)

The APL's `numberTargets` gates the multi-target rows:

| APL | row | clause |
|---|---|---|
| wowsims/tbc-new fury/arms `[10]`, `[11]`, `[15]`, `[18]`, `[4]` | Sweeping Strikes 12723, Whirlwind 1680, Cleave 25231, Heroic Strike 29707, Sunder group | `numberTargets > 1` / `== 1` |
| wowsims/classic `dps_no_reck` `[14]`, `[18]`, `[19]` | Whirlwind 1680, Heroic Strike 25286, Cleave 20569 | `numberTargets > 1` / `== 1` |
| wowsims/forever arms/fury `[5]`, `[6]`, `[12]`, `[26]` | Sunder group, Sweeping Strikes 12723, Heroic Strike 20569 | `numberTargets > 1` / `== 1` |
| wowsims/wotlk arms `[3]`, `[4]`, `[11]` / fury `[4]`, `[5]`, `[6]` | Overpower, Mortal Strike, Thunder Clap | `numberTargets > 1` / `== 1` |

**The missing read:** the sim's `numberTargets` — the number of enemies in the
player's vicinity. The client-side candidate is a hostile-unit scan (the nameplate /
target units the client exposes, filtered for hostility and melee range); **no
compat wrapper supplies it today**, and the other classes' `target_count` inputs are
skeletons (the shaman's feeds nil; the paladin's is "1 when a creature is known").
Until that read exists, the rows that carry the clause are asked on their
cooldown + buff alone — a documented deviation, now named.

### 3c. The Bloodlust-alignment gate — **FILED** (no read exists, and it needs an option)

The TBC APL aligns three rows to the raid's Bloodlust with `multipleCdUsages` against
the base spell 2825 and the "Bloodlust time" variable
(wowsims/tbc-new `ui/specs/warrior/dps/apls/fury.apl.json` `[8]` Death Wish 12292,
`[9]` Recklessness 1719, `[10]` Sweeping Strikes 12723; the group's opener is `[1]`,
`currentTime >= "Bloodlust time"`). The Forever APL carries the same shape for
Sweeping Strikes `[12]`.

**The missing read:** the raid's Bloodlust plan — the fight-time offset at which the
raid's Bloodlust lands (the sim's user-set variable) — plus the target cooldown's
remaining time. The addon has no Bloodlust clock and no such option; the fight
clock alone would not do it, because the Bloodlust time is a raid plan, not a fact
the client can read. **This needs a new option** (the fight-time offset), which
lives in the out-of-scope option files (`option_tables.lua` / `config_presets.lua`) —
so it is filed here rather than built. The druid's Bloodlust row filed the same gap.

### 3d. Two more gates the residual list did not name (found while reading the APLs)

* **The WotLK Bloodrage rage ceiling.** The class's `bloodrage` line carries one
  ceiling, 90 (the Era / TBC / Forever APLs' `currentRage < 90`). The WotLK APLs use
  **20** (wowsims/wotlk `ui/warrior/apls/arms.apl.json` `[1]` — `currentRage < 20`;
  `fury.apl.json` `[1]` — in Berserker Stance AND `currentRage <= 20`). The class
  therefore asks for Bloodrage on WotLK far more eagerly than the APL does, and it
  ignores the fury APL's stance condition. **The reads exist** (the rage pool and
  the stance walk), so this is buildable — but it is a per-family ceiling in the
  utility table plus a stance gate in the engine's line verdict, i.e. a second lane's
  worth of work. FILED, not built.
* **The Forever stance dance.** The Forever APL's stance rows are the "Stance Dance
  ON/OFF" group and carry the execute phase (arms `[19]` / `[25]`). The class models
  the Forever upkeep as "always Battle Stance" (the toggle ships off), so the
  phase-flip inside the dance is unbuilt. The read the phase flip needs exists
  (the phase); the group's toggle state does not (the sim's `actionGroupUsed` is
  the APL's own bookkeeping and has no client analogue). FILED.

### 3e. One gap in the utility lane's own order table

The SoD APL's `[7]` (Bloodrage 2687) sits above the SoD core, but the utility
lane's `orders.SOD` carries only Death Wish and Recklessness, so the engine never
asks for Bloodrage on SoD and the SoD strip carries no Bloodrage row. The APL row
is real (and the SoD pre-pull casts 2687 too). FILED — adding it to the order table
is a live-path change (a new prompt on SoD) and belongs to the operator's call, not
to a residuals lane.

---

## 4. Validation

* `bash tests/run.sh` → **40 of the 41 steps PASS on the lane's tree state**; the
  warrior's own suites and every other class's suites are green (druid, hunter,
  paladin, shaman, guide-contract, bars, hud, practice, options are all PASS).
  **The rogue lane's in-flight files were RED while this lane finished** —
  `classes/rogue.lua` (a syntax error mid-edit, which also failed the `luac5.1 -p`
  step while it stood), `tests/rogue_state.lua`, `tests/rogue_guide_state.lua` and
  `tests/options_load_state.lua` (the options-load step reads the rogue class).
  The failing pins are all rogue APL / rogue options pins; the file timestamps land
  after this lane's last edit, and no rogue file is in this lane's scope. The last
  run before this report went out was **41 steps, 1 failed** — the single red being
  the rogue lane's options-load pins.
* The warrior's own suites: `tests/warrior_state.lua` → **PASS (1822 checks)** (was
  1635), `tests/warrior_guide_state.lua` → **PASS (2040 checks)** (was 2019).
* luacheck → this lane's four files: **0 warnings / 0 errors**. The tree total is
  the floor, **2 warnings / 0 errors** (the pre-existing `compat.lua` and
  `main.lua` warnings) — measured on the tree after the rogue lane's syntax error
  was repaired.
* **Mutation proofs: 18/18 killed** on `/tmp/opencode` copies (the script is at
  `/tmp/opencode/mut_warrior_residuals.py`, the tree copy at
  `/tmp/opencode/mut_warrior_residuals`): the slice dropping the engine flag, the
  slice dropping the slot-set gate, the live flag inverted, the family accessor
  forgetting the SoD branch, the per-family map losing the TBC vocabulary, the
  WotLK token ignoring the spec, a rotation row losing its label, the engine
  dropping the execute-phase gate, the pure helper ignoring the provider gate, the
  pure helper treating an unknown health as a phase, the pure helper ignoring the
  threshold, the provider not arming the TBC clause, the provider not arming the
  Forever clause, the provider arming the Era clause, the practice surface dropping
  the gate, the filing losing the set-membership read, the filing losing the
  set-bonus source, and the Gladiator Stance row claiming an arm it does not have —
  every one fails the suite on the expected pin.
* No in-client verification. Per `CAIRN.md` ("two proofs, two words") this is a
  source-cited build with a mutation-proofed offline pass, not a verified-in-client
  one. The execute-phase gate in particular is a behaviour change on TBC / Forever
  and wants an in-client look.

## 5. What is left for the operator

1. **The Gladiator Stance read** — the six item ids of the SoD T1 warrior damage
   set (or a set-membership wrapper). The row stays `engine = false` until then.
2. **The target-count read** — an enemy-count sensor (the sim's `numberTargets`).
3. **The Bloodlust plan** — a new option (the fight-time offset of the raid's
   Bloodlust) plus the fight clock; the option files are out of this lane's scope.
4. **The WotLK Bloodrage ceiling + stance condition** — a per-family rage ceiling
   in the utility table and a stance gate in the engine's line verdict.
5. **The SoD Bloodrage order gap** — one word in the utility lane's `orders.SOD`
   (a live-path change: a new prompt on SoD).
6. **The Forever stance dance** — the execute-phase flip inside the "Stance Dance
   ON/OFF" group.

**Validation owner: the orchestrator.**
