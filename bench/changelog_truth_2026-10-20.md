# changelog-truth — the CHANGELOG made true against the tree (2026-10-20)

Desk: `desks/changelog-truth/`. **Scope: `CHANGELOG.md` only** (plus this bench
file, which was verified absent before it was written). No `.lua`, no `README.md`,
no `TESTING.md`, no `bench/live_test_script_2026-10-19.md` (a sibling lane owns
those three), no other bench file, no TOC, no version, no git, no lint-config
change.

**Everything below is verified offline. Nothing here claims in-client proof.**
The tree state at the time of writing: `bash tests/run.sh` → **43 steps, 0
failed**; `luacheck .` → **2 warnings / 0 errors in 85 files** (both pre-existing:
`compat.lua:36` unused `addon_name`, `main.lua:81` `table.pack`).

---

## 0. The inputs

* `desks/docstruth-audit/journal.md` — the documentation-truth audit, findings
  F6 / F7 / F8 / F14 / F15 / F16 / F17 (F18 was out of the dispatch's scope and
  stays open).
* `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 — the id correction log (the
  "do not trust the old ids" corpus).

Every claim was re-read in the tree before it was written down. The audit is an
input, not an authority: where the audit's line numbers had drifted, the symbol
was cited instead.

---

## 1. The findings, closed

### F6 — the paladin pre-pull names (CLOSED)

**The false claim.** The `[2.1.1]` paladin bullet named two pre-pull rows
"Divine Storm 20920" and "Holy Shock 20308".

**The tree's truth.** `ST.PALADIN.practice_prepull_rows` (the table the bullet
describes) labels its own rows:

| row | the tree's label | id | family | where |
|---|---|---|---|---|
| `soc_prepull` | **Seal of Command** | 20920 | FOREVER | `classes/paladin.lua` `practice_prepull_rows` |
| `soc_prepull` | **Seal of Command** | 20920 | SOD | same table |
| `sotc_prepull` | **Seal of the Crusader** | 20308 | FOREVER | same table |
| `som_prepull` | Seal of Martyrdom | 407798 | SOD | same table |

The two spells the changelog had named are different spells in this tree:
**Divine Storm is 407778 (SoD) / 53385 (WotLK)** (`classes/paladin.lua`'s `ds`
row: `ids = { SOD = 407778, WRATH = 53385 }`) and **Holy Shock is 20930** (the
`hs` row and the guide slot). Neither is a row of the pre-pull table.

**The fix.** The two names were corrected to the table's own labels and the
changelog now says where the names come from. The eleven-row count was
re-counted from the table (11 entries) and stands.

**Corroboration.** The class's own seal ladder puts 20920 in the Seal of
Command ids (`soc_ids`), and the Forever client's own ladder agrees
(`SealOfCommand Ranked(20375, 20915, 20918, 20919, 20920)` — cited in the
row's own `source`).

**Raised, not papered over (a code-side item, NOT a doc fix).** The tree
disagrees with itself on the **SoD** 20920 row: the pre-pull table labels it
"Seal of Command", while the class's own `sob` rotation row's source comment
calls the same SoD 20920 r5 "**Seal of Martyrdom**" (that rotation row's own
SoD id is 407798; the 20920 in its `source` names the APL's p8-stack row i=2).
The corpus carries both readings: `bench/rotation_gap_vs_apl_2026-10-20.md`
§6 calls the p8-stack i=2 row "20920 r5 Seal of Martyrdom", while
`bench/sod_paladin_variants_2026-10-19.md` §"Spell/id names" reads the
**client's own** spell page for 20920 as "Seal of Command". The changelog
follows the pre-pull table (the thing the bullet describes) and says so
explicitly. **The code owner should settle the label in
`classes/paladin.lua`; this lane changed no `.lua`.**

### F7 — "the warrior included" (CLOSED)

**The false claim.** "a class that publishes no drills of its own and owns no
twist drill — **the warrior included** — is refused loudly".

**The tree's truth.** The warrior publishes **six** drills:
`warrior_core_order`, `warrior_ww_delay`, `warrior_sunder_upkeep`,
`warrior_execute_burn`, `warrior_hs_queue`, `warrior_prepull`
(`classes/warrior.lua` `ST.WARRIOR.practice_drills`; the exact key list is
pinned by `tests/warrior_state.lua`). The warrior is therefore not a
no-drill class.

**The fix.** The parenthetical was dropped and the sentence now says the
warrior is not one of them, with the drill count and the suite that pins it.

### F8 — "13 design targets" (CLOSED)

**The false claim.** The designer bullet counted the design registry at 13 with
no qualification.

**The tree's truth.** The base registry holds **13** elements
(`tests/designmode_state.lua`: "the registry holds the thirteen real elements"),
but the count is **class-dependent**: the druid registers the Combo Points pips
as a fourteenth design target (`classes/druid.lua` — the pips widget is created
with `design = { key = "druid_pips", title = "Combo Points" }`, and
`bars.lua`'s `ST:new_pips` registers the element in the design registry).

**The fix.** "13 design targets — **14 on a druid**, which registers the Combo
Points pips as a fourteenth".

### F14 — the void correction notice (CLOSED)

**The false claim.** The "Audit-fix wave" section carried a "Correction to the
earlier release notes in this section" notice saying the "Scenario surface +
APL utility layer" entry above "still says the druid 'states **none**'". It does
not: that entry was **already corrected in the same document** and even points
forward at the Audit-fix wave.

**The fix.** The notice is reworded as a **dated history note** (2026-10-20):
the earlier wording was corrected in place when the HIGH defect was fixed, so
no correction is owed to it now. The druid's two hold shapes and the two
published tables stay in the note. Nothing was deleted from the record.

### F15 — the `hunter_multi_target` copy marker (CLOSED)

**The false claim.** "the `hunter_multi_target` copy marked '(future)'".

**The tree's truth.** The shipped option's `name` is **"Multi-target mode
(manual, not wired yet)"** (`option_tables.lua`).

**The fix.** The changelog now quotes the shipped copy verbatim.

### F16 — the two strings are not the same (CLOSED)

**The false claim.** The changelog quoted one string and said the Practice page
"says the same".

**The tree's truth.** Two different strings for one behaviour:

| surface | the string | where |
|---|---|---|
| the refusal | "Practice scenario is not available on this client (no live swing engine)." | `practice_ui.lua` |
| the Practice page's note | "The rotation scenario cannot run on this client (no live swing engine)." | `option_tables.lua` |

**The fix.** Each is quoted exactly and the changelog says they are two strings
for one behaviour.

### F17 — "pips 10->12" (CLOSED)

**The false claim.** The designer bullet and the reconcile bullet both carried
"pips 10->12". That matches no shipped number.

**The tree's truth.** The pips row is **five** cells: `bars.lua` has
`PIPS_COUNT = 5`, `PIPS_SIZE = 10`, `PIPS_GAP = 2` — five 10 px cells on a
12 px step, row width 58 (`tests/designmode_state.lua`: "five pip textures are
created" / "the default row is five 10 px pips with 2 px gaps" / "pip N steps
by size + gap"). The `10` is the cell size and the `12` the step, in pixels;
neither is a pip count.

**The fix.** The phrase was **dropped** from both bullets (it named a change
that never happened) and the design-target count in the first bullet was
corrected per F8.

---

## 2. The new wave entries (appended, history intact)

A new dated section was appended to the `[2.1.1]` block — **"Neutral actions,
family scope, HUD ids, progression and contracts (2026-10-20, verified offline,
UNCONFIRMED in-client)"** — after the Audit-fix wave and before `## [2.0.8]`. No
existing section was rewritten; the F6/F7/F8/F14/F15/F16/F17 corrections were
made in place because those are the corrections the audit asked for.

Each entry carries its bench citation and the "verified offline, UNCONFIRMED
in-client" marking.

| entry | the tree evidence it was written from | the bench citation |
|---|---|---|
| the NEUTRAL action (the engine half) | `practice.lua`: the accessor `H.practice_neutral_actions` (nil for an unknown class, a **copy** of the published set, a family with no bucket answers nil), the `neutral` outcome in `H.rotation_run_decide` (no attempt, no points, no streak, no mastery tick, no XP, not a mis-pick), the HOLD precedence and the expected-action precedence; `practice_ui.lua`: the `NEUTRAL` popup and status line, the summary count only above zero | `bench/practice_neutral_actions_2026-10-20.md` |
| the per-class neutral sets | the four published sets read from the tree: paladin (flat, 11 keys), warrior (family-scoped), rogue (family-scoped), shaman (flat, 5 keys) — and the **hunter** and the **druid** publish **none** (no `practice_neutral_actions` in either class file). The practice-panel ability list (`ST.<CLASS>.practice_common_actions`, the name-first resolution, the `post_init` widening seam) | `bench/class_neutral_actions_2026-10-20.md`, `bench/class_common_actions_2026-10-20.md` |
| the shaman's family-scoped rotation and slots | `classes/shaman.lua`: `practice_rotation_for`, `practice_rotation_family`, `practice_build_family`, `family_guide_slots`, `apply_family_slots` (called from `post_init` and from the SoD latch); the per-family slices **Era 13 / TBC 13 / WotLK 13 / Forever 7**, the SoD build's own slice **14** (`tests/shaman_state.lua`'s derived-slice pins); `ST.SHAMAN.PRACTICE_PREPULLS` has no consumer and the file says so | `bench/shaman_family_scope_2026-10-20.md` |
| the hunter's family-correct HUD ids | `classes/hunter.lua`: one owner `SPELL_ID_BY_FAMILY` for the HUD slot and the guide slot, the dead-slot filter `FOREVER = { steady = true, kill_command = true }`, the re-point loop that re-points every spell slot. The per-family slot counts **Era base 6 / Era-SoD 7 / TBC 9 / WotLK 9 / Forever 7 / Cata 9 / Mists 8 / Retail 9** (`tests/hunter_state.lua`'s per-family census; `tests/hud_state.lua` §13c for the Forever seven) | `bench/hunter_hud_family_2026-10-20.md` |
| the progression fixes (six) | the daily-cap floor (`practice_progress.lua`: the cap over `hit_points_window`, `max(3 x median hit, best hit)`), the cap notice (`practice_ui.lua`, the exact shipped sentence), the account scope (`P.evaluate_unlocks_both`, called at the session end), the streak readout (`practice_progress_ui.lua`: "Best streak %d  |  Daily streak %d"), the reset-arm expiry (`RESET_ARM_SECONDS = 15`, `ui.reset_arm_expired()`), the NO_DAY sentinel (`practice_stats.lua`: `S.NO_DAY = -1`, read signed) | `bench/progression_fixes_2026-10-20.md`, `bench/progression_ui_fixes_2026-10-20.md` |
| the drill-list pick contract | `practice_ui.lua`: the press is written into `ctx.pick` / `ctx.pressed` / `ctx.action` **unconditionally**; a class's own pick survives a press-less drill press; the scenario path is a different call site. The six classes' real graders are driven end to end by `tests/practice_ui_state.lua` §27 | `bench/drill_pick_contract_2026-10-20.md` |
| the pre-pull contract suite | NEW `tests/prepull_contract_state.lua`: the eight published pre-pull tables, each proved GRADED or CITATION-only; a citation table has no reader in the addon tree and carries the marker; a drill reads its own table and no other class's; the paladin's flags are strict booleans | `bench/prepull_contract_2026-10-20.md` |
| the documentation-truth corrections | the sibling lane's own record: `/st diag verbose` does not exist (`main.lua`'s slash handler matches only the empty argument, `practice`, `design`, `diag`); the rogue's SnD slot is armed (`classes/rogue.lua`) and its Forever pre-pull is Blade Flurry 13877 @-2 with the builder chain `{Saber Slash, Mutilate, Hemorrhage}`; the Cata (40402) and Mists (50500) flavours ship without the swing-engine library (their TOCs carry no `LibClassicSwingTimerAPI`); the diag shape carries the ticks line; the trinket gate and the W-21 mirror got operator steps | `desks/docstruth-audit/journal.md`, and the three corrected files themselves |

---

## 3. Line endings and hygiene

* `CHANGELOG.md` stays **CRLF** (982 of 983 lines; the last line has no
  terminator, pre-existing). No line ending was changed by this lane.
* No tab, no trailing whitespace on any touched line.
* No `.lua` was touched, so the tree's offline state is unchanged: **43 steps,
  0 failed**, luacheck **2 / 0 in 85 files**.

---

## 4. Open items for the operator / the code owner

1. **F6, the SoD 20920 label (code side).** The tree's pre-pull table says
   "Seal of Command" and the `sob` row's source comment says "Seal of
   Martyrdom" for the same SoD id. The changelog follows the pre-pull table and
   says so. A code-side decision is owed.
2. **The hunter's and the druid's neutral sets are not landed.** Their lists are
   worked out and filed (`bench/class_neutral_actions_2026-10-20.md` §3,
   `bench/class_common_actions_2026-10-20.md` §5); the changelog says so
   explicitly rather than implying six published sets.
3. **F18 stays open** (the dated per-suite check counts in the dated sections) —
   out of this dispatch's scope.
4. The `[2.1.1]` section now spans several waves; the version bump is still the
   operator's call.

---

## 5. Validation owner

**The orchestrator.** Nothing in this lane was proven in a client; every row
stays UNCONFIRMED in-client.
