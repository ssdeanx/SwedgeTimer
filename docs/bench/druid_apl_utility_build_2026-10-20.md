# The druid's APL utility layer — 2026-10-20

Desk: `druid-apl`. **The APL gap analysis is the input, not the authority**: every
id, index and name below was re-fetched from the sim sources and the APL files on
2026-10-20 and checked against the shipped file. The gap analysis's druid section
(`bench/rotation_gap_vs_apl_2026-10-20.md` §4) carries **four errors**, corrected in
§5 below.

**Scope:** `classes/druid.lua` (the rotation table, the prepull table, the gather's
utility reads), `druid_guide.lua` (the frozen engine's arms), `tests/druid_state.lua`,
`tests/druid_guide_state.lua`. One new bench file. No git, no lint-config change, no
TOC / version / option / config change, no other class touched.

**Ruling applied (HU-12, orchestrator):** the rotation table carries the APL's SPELL
rows; the APL's PRE-PULL rows stay in a per-class prepull table (`ST.DRUID.PRACTICE_PREPULLS`,
the shape `ST.HUNTER.PRACTICE_PREPULLS` already uses). **HU-13 (the two flags):**
`live` = the line's read exists and the line can be evaluated; `engine` = the frozen
engine has an arm that can ask for it.

---

## 1. The evidence (re-fetched, every group expanded inline)

Fetched 2026-10-20 from `raw.githubusercontent.com/wowsims/{classic,sod,tbc-new,
forever,wotlk}/master`; every `groupReference` expanded inline, so the indices below
are the full priority order, not the group-stub order.

**ERA — `wowsims/classic ui/feral_druid/apls/feral.apl.json`**
pre-pull: 17392 r4 @ −1.0 s, 9846 r4 @ −3.5 s.
`[0]` 17392 r4 (the Feral Faerie Fire, refreshed at 1 s left) · `[1]` 13494 ·
`[2]` autocast · `[3]` 17061 r5 (harness) · `[4]` 31018 r4 (Ferocious Bite) ·
`[5]` 9830 r5 (Shred) · `[6]` 9850 r5 (Claw) · `[7]` 31018 r4 · `[8]` 17392 r4
(refresh at 14 s left) · `[9]` item 10646 · `[10]` item 12662 · `[11]` potion ·
`[12]` 23724 · `[13]` 29166 (Innervate) · `[14]` 768 (Cat Form).

**SOD — `wowsims/sod ui/feral_druid/apls/phase_5.apl.json`**
pre-pull: activateAura 407988 @ −8 s.
`[0]` 768 · `[1]` 407988 (Savage Roar) · `[2]` item 12662 · `[3]` potion ·
`[4]` 29166 · `[5]` 417141 (Berserk) · `[6]` 417045 (Tiger's Fury) · `[7]` 417045 ·
`[8]` autocast · `[9]` 409828 (Mangle) · `[10]` 9830 r5 (Shred, clearcasting) ·
`[11]` 9896 r6 (Rip) · `[12]` 9904 r4 (Rake) · `[13]` 409828 · `[14]` 31018 r4 ·
`[15]` 9830 r5 · `[16]` 409828.

**TBC — `wowsims/tbc-new ui/specs/druid/feralcat/apls/default.apl.json`**
pre-pull: 768 @ −10 s.
`[0]` 2825 r1 (Bloodlust, the "Bloodlust Time" variable, shipped value 5 s) ·
`[1]` group `Drums` (35476) · `[2]` 27011 r5 (Faerie Fire (Feral), when the target's
26993 r5 aura is inactive) · `[3]` 27008 r7 · `[4]` 33983 r3 (Mangle (Cat)) ·
`[5]` 27002 r7 (Shred) · `[6]` group `Powershifting` (the engineering / trinket /
healthstone rows and the Cat Form member) · `[7]` 27008 r7 · `[9]` 33983 r3 ·
`[10]` 33983 r3 · `[11]` 24248 r6 (Ferocious Bite) · `[12]` 27008 r7 ·
`[13]` 27003 r5 (Rake) · `[14]` 33983 r3 · `[15]` 33983 r3 · `[16]` 27002 r7 ·
`[17]` 24248 r6 · `[18]` 27008 r7 · `[19]` 27002 r7 · `[20]` 33983 r3 ·
`[21]` 27002 r7 · `[22]` 33983 r3 · `[23]` 33983 r3.

**FOREVER — `wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json`**
(no pre-pull rows.)
`[0]` item 10646 · `[1]` 768 · `[2]` group `Berserk` (417141) · `[3]` group
`Cooldowns` (1259799 "Elune's Light", item 7676, a resource potion, autocast) ·
`[4]` 9830 (Shred, clearcasting) · `[5]` 9830 / 9850 (the builder) · `[6]` group
`Bleeds` (9896 Rip, 9904 Rake) · `[7]` 22829 (Ferocious Bite) · `[8]` 1322605
(Shifting Power) · `[9]` group `Builders` (9830 Shred, 9850 Claw) · `[10]` 29166
(Innervate) · `[11]` 9907 (Faerie Fire).

**WOTLK — `wowsims/wotlk ui/feral_druid/apls/default.apl.json`**
pre-pull: activateAura 16870 @ −1 s, 50334 @ −1 s.
`[0]` autocast · `[1]` 50334 (Berserk, `IF false`) · `[2]` the sim's own
`catOptimalRotationAction`. **The WotLK APL carries no spell rows at all.**

## 2. The names, confirmed against the sims' own data and the 1.15 client

* `wowsims/classic sim/druid/faerie_fire.go:11,28` — 9907 the plain Faerie Fire,
  **17392 the Feral one**; `sim/druid/claw.go:14` — **9850 Claw**;
  `sim/druid/forms.go:88` — **768 Cat Form**; `sim/druid/innervate.go:16` — **29166
  Innervate**; `sim/druid/tigers_fury.go:10` — the level-60 Tiger's Fury is **9846**.
* `wowsims/sod sim/druid/savage_roar.go:20` — **407988**; `berserk.go:17` — **417141**;
  `tigers_fury.go:65` — **417045**; `mangle.go:89` — **409828** (the cat Mangle).
* `wowsims/tbc-new sim/druid/spell_data_auto_gen.go` — the FaerieFire table (9907 r4,
  26993 r5), the FaerieFireFeral table (17392 r4, **27011 r5**), the MangleCat table
  (33876 r1, **33983 r3**), the Claw table (**9850 r5**), the Rip table (27008 r7),
  the Rake table (27003 r5), the Shred table (27002 r7), the FerociousBite table
  (24248 r6), the TigersFury table (9846 r4); `sim/shaman/bloodlust.go:11` — **2825**.
* `wowsims/forever sim/druid/spell_data_auto_gen.go` — the Claw ladder (1082, 3029,
  5201, 9849, **9850**), the FaerieFire ladder (…, **9907**), the Rip ladder (…,
  **9896**), the Rake ladder (…, **9904**), the Shred ladder (…, **9830**), the
  FerociousBite ladder (…, **22829**), the Innervate ladder (**29166**), the
  LeaderOfThePack ladder (17007), Berserk `Talent(417141, 1)`, ShiftingPower
  `Talent(1322605, 1)` — **and no Mangle table at all**.
* `wowsims/wotlk sim/druid/{shred,rip,rake,ferocious_bite,mangle}.go` — 48572, 49800,
  48574, 48577, 48564 (the cat Mangle); `faerie_fire.go:11,22` — 770 and **16857**;
  `berserk.go:15` — 50334; `savage_roar.go:16` — 52610; `tigers_fury.go:10` — 50213.
* The Classic 1.15 client's own tables (wow.export `Spell.csv`, `SkillLineAbility.csv`,
  `SpellDuration.csv`): 768 "Shapeshift into cat form", 17007 the **Leader of the
  Pack** (in the Feral Combat skill line), 17392 "Rank 4", 9907 "Rank 4",
  9846 "Rank 4", 9850 "Rank 5", 9830 "Rank 5", 9896 "Rank 6", 9904 "Rank 4",
  31018 "Rank 5", 16870 the Clearcasting proc, and **33983 absent** (no Mangle on
  Era).

## 3. What landed

### 3.1 The utility spine (`ST.DRUID.practice_rotation`, after the BEAR slice)

Seven rows, each with `action` / `label` / `rule` / `note` / `families` (a set) /
`ids` (per family) / `tbc_name` / `source` (the APL file + index) / `live` /
`engine` / `needs`:

| action | families | ids | live | engine |
|---|---|---|---|---|
| `cat_form` | ERA, SOD, TBC, FOREVER | 768 on all | true | **false** (filed) |
| `leader_of_the_pack` | ERA | 17007 | true | true |
| `faerie_fire` | ERA, TBC | 17392 / 27011 | true | true |
| `claw` | ERA, FOREVER | 9850 / 9850 | **false** (filed) | false |
| `innervate` | ERA, SOD, FOREVER | 29166 on all | true | true |
| `elunes_light` | FOREVER | 1259799 | true | true |
| `bloodlust` | TBC | 2825 | true | **false** (filed) |

The shipped sim rows also carry their per-family `ids` and both flags now, and
their `source` names the APL row they correspond to (or states that the APL has no
row for them).

### 3.2 The pre-pull table (`ST.DRUID.PRACTICE_PREPULLS`, HU-12)

`ERA` (Faerie Fire (Feral) 17392 @ −1.0 s, Tiger's Fury 9846 @ −3.5 s) · `SOD`
(Savage Roar 407988 @ −8 s) · `TBC` (Cat Form 768 @ −10 s) · `WRATH` (Berserk 50334
@ −1 s). The Forever APL has no pre-pull row.

### 3.3 The engine's arms (`druid_guide.lua`)

Four holds, no new guide slot (the hold-overlay convention, like TIGER'S FURY):
`FAERIE FIRE` (the Era refresh row and the TBC row), `LEADER OF THE PACK` (the Era
row), `INNERVATE` (the mana row), `ELUNE'S LIGHT` (the Forever row). The gather
publishes their reads: `lop_known`, `lop_active`, `ff_debuff_remaining`,
`feral_ff_ready`, `innervate_ready`, `elunes_light_ready`, `mana_percent`,
`has_target`.

### 3.4 The module's id tables

`druid_tf_ids` += 417045, `druid_berserk_ids` += 417141, `druid_sr_ids` += 407988
(the SoD / Forever rune ids the id-first walk could not resolve before - the name
fallback carried them, the ids make it locale-independent).

## 4. The filed follow-ups (the exact read each line waits for)

* **Cat Form** (`engine = false`): the READ exists (the form index - the classic
  indices are 1 bear, 3 cat, 4 travel, 5 moonkin-tree, 6 flight, `compat.lua:790` -
  and the Cat Form aura scan through `api.scan_player_aura` on 768). What is missing
  is the RULE: **the guide has no feral-spec gate**, so an arm that fires when the
  form is not the cat form would nag every caster druid in combat (a resto druid in
  humanoid form reads exactly like a feral who shifted out of cat form). The tree's
  only spec evidence is `ST:get_druid_talent_info`'s `has_moonkin` /
  `has_tree_of_life`, and `main.lua`'s `talent_positions` table is **WRATH-only**
  (`main.lua:1571`), so on the families this line belongs to there is no gate at all.
* **Claw** (`live = false`): the READ that decides "the Shred cannot land" does not
  exist: the guide's `can_shred` input is RESERVED (nil) - the sim's
  `CannotShredTarget` has no WoW API counterpart (the position behind the target),
  and `api.IsSpellUsable` answers usability, never facing. The Forever APL's own row
  needs `NOT spellCanCast(9830)`, which the client could answer through
  `api.IsSpellUsable` (`compat.lua:277`), but the class never reads it and the
  classic `IsSpellUsable`'s resource semantics for an energy-cost spell in cat form
  are in-client UNCONFIRMED.
* **Bloodlust** (`engine = false`): the READ exists (`api.GetSpellCooldown` on 2825);
  the APL's own GATE does not: the row fires at the APL's **"Bloodlust Time"
  VARIABLE** (a sim user setting, 5 s in the shipped APL), and the addon has no
  equivalent option and no way to know the raid's plan (the practice panel's own
  Bloodlust button is the manual path).
* **Elune's Light**: the id is the APL's own; the NAME is the APL's variable name and
  is **UNCONFIRMED** outside it (the id is in no wowsims spell table and warcraftdb
  has no spell 1259799). The gather's knowledge gate (`api.GetSpellInfo` answering
  the literal name) keeps the line dormant until the client's own spell data answers
  it.

## 5. The gap analysis's druid section is wrong in four places

1. **"9850 is Mangle on TBC/Forever"** (§4.3, the `shred_claw` row) — **wrong**.
   9850 is the **Claw r5 on Era, TBC and Forever alike** (`classic sim/druid/claw.go:14`;
   `tbc-new` spell data: the Claw table's r5; `forever` spell data: the Claw ladder).
   The Mangle (Cat) ids are 33876 / 33983 / 33987 on TBC - and the **Forever client has
   no Mangle spell at all**.
2. **The Era APL's `[1]` row "13494 Faerie Fire (Feral)"** (§4.2/§4.3) — **wrong**.
   The 1.15 client names **13494 "Haste"** (it is in no druid skill line), while the
   client's Leader of the Pack is **17007** (the Feral Combat skill line, the Leader
   of the Pack description). The APL row casts Haste, so it is dead as written; the
   line it means is the Leader of the Pack, and that is what the table carries.
3. **The Era APL's Rip** (§4.3's `ripe` row, "Era i=?") — the Era APL has **no Rip row
   at all** (its rows: the Faerie Fire, the Leader of the Pack, the Ferocious Bite, the
   Shred, the Claw, the Innervate, the Cat Form). The shipped E1 Rip row keeps the
   sim's citation and now says so.
4. **The Forever `mangle` row (F5)** — the shipped row cited
   `apl_sweep_test.go: mangleNow`, **a function the Forever repo does not have**
   (the Forever druid sim carries no Mangle: no spell table, no per-ability file,
   no mention in `feral.go` / `feralcat/*.go`). The row's citation is corrected in
   place and the row carries **no id** for that family. **FILED for the operator:**
   the engine's FOREVER chain still prompts "mangle" when `mangle_remaining` is nil
   (which on the Forever client is always, because the Mangle spell does not exist),
   so the F6/F7 branches are unreachable there. Fixing that is a behaviour change to
   the shipped Forever chain - **out of this lane's scope** (the Claw builder row is
   the APL's own answer, and the Claw line's read is filed in §4).

## 6. Validation

* `tests/druid_state.lua` — PASS (1190 checks; +137 pins: the utility spine, the
  family gates, the ids, the flags, the filed needs, the pre-pull table, the slices).
* `tests/druid_guide_state.lua` — PASS (95582 checks; +64 pins: the four arms, their
  unknown-hides, their family gates, and the gather's new reads).
* luacheck on the four touched files — **0 warnings / 0 errors**. The tree's floor is
  untouched by this lane: the full run reports **2 warnings / 0 errors** (both
  pre-existing, in untouched files - `compat.lua` and `main.lua`).
* **21/21 mutations killed** on `/tmp/opencode` copies
  (`python3 /tmp/opencode/druid-apl/mutations_druid_apl.py` reproduces them) - among
  them the required "a buff-up line still prompts" mutant (the Leader of the Pack arm
  losing its aura check), the unknown-hides mutants (no target, an unreadable
  cooldown, an unreadable mana pool, an **unanswered debuff**), the family-gate
  mutants (the SoD picking up the Faerie Fire row, the Era Innervate row firing
  inside the cat form), the id mutants (Cat Form 768→767, the Leader of the Pack
  17007→13494, the SoD Tiger's Fury 417045→9846), the flag mutants (the Cat Form row
  claiming an arm, the Claw row claiming a read) and the slice/pre-pull mutants.
* The full harness: **41 steps, 0 failed**. (Mid-lane the tree showed one failure in
  `tests/rogue_guide_state.lua` - a **concurrent lane's** in-flight state, the rogue
  lane's files being written during this lane's run; it cleared on the final run.)
  **Verified offline** - no client run happened here, so every behaviour claim above
  is a simulation claim, not an in-client one.

### 6.1 The one design note worth the trail

The Faerie Fire debuff read is a **tri-state**, not the shipped debuff convention
(nil = "not on the target"): the target walk's answer and "the walk has not answered
yet" are different answers, and only the first may prompt. `inputs.ff_debuff_remaining`
is therefore a number (the debuff is up, with that remaining), **false** (the walk
answered: the debuff is not on the target) or **nil** (the walk has not answered -
unknown, never a prompt). The mutation "the arm prompts on an unanswered debuff" and
the mutation "the gather publishes the absent debuff as unknown" are both killed.
