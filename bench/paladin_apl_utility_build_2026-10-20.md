# The paladin's APL utility layer — 2026-10-20

Desk: `paladin-apl`. **The APL gap analysis is the input, not the authority**:
every APL file was re-fetched on 2026-10-20 from
`raw.githubusercontent.com/wowsims/{classic,sod,tbc-new,forever,wotlk}/master`,
every `groupReference` was expanded inline (so the indices below are the FULL
priority order, not the group-stub order), and every id and name was re-checked
against the sims' own spell data, the per-ability `.go` files and the Classic
1.15 client's own spell tables (`wow.export`'s `SkillLineAbility.csv`).

**The gap analysis's paladin section (§6 of
`bench/rotation_gap_vs_apl_2026-10-20.md`) carries FOUR errors** — corrected in
place in §3 below, with the evidence.

**Scope:** `classes/paladin.lua`, `nextaction.lua`, `tests/paladin_state.lua`,
`tests/nextaction_state.lua`, `tests/guide_contract.lua` (the paladin section
only). One new bench file. No git, no lint-config change, no TOC/version/
option/config change, no other class touched.

**Rulings applied:**

* **HU-12 (prepull split):** the rotation table carries the APL's SPELL rows;
  the APL's `prepullActions` rows live in the pre-pull table
  (`ST.PALADIN.practice_prepull_rows`).
* **HU-13 (the two flags, cross-class):** `live` = the line's read exists (in
  `compat.lua` today) and the line can be evaluated; `engine` = the frozen
  engine has an arm that can ask for it. A line without an arm names the
  exact read (or the exact rule) it waits for in `needs`.

---

## 1. The APLs, re-fetched and expanded (the evidence)

### ERA — `wowsims/classic ui/retribution_paladin/apls/basic_ret.apl.json`

| i | row | condition |
|---|---|---|
| 0 | 20271 Judgement | `spellCanCast(20271)` |
| 1 | `castPaladinPrimarySeal` (the macro) | `currentSealRemainingTime <= 1` |
| 2 | 20375 (the twist's seal side) | `autoTimeToNext(Melee) < 0.4 s` AND `auraIsActive(20293 r8)` |
| 3 | 20293 (the twist's seal side) | `autoTimeToNext(Melee) < 0.4 s` AND `auraIsActive(20375 r1)` |

Pre-pull: `castPaladinPrimarySeal` @−1.5 s.

### SoD — five APLs (`wowsims/sod ui/retribution_paladin/apls/`)

| APL | rows (index: cast) |
|---|---|
| `p8-twist` | 0 wait · 1 cancelAura · 2 autocast · 3 item · 4 20271 · 5/6 the twist macro casts · 7 24239 · 8-15 the twist's strict sequences · 16-20 the filler macro casts (16 407778, 17 415073, 18 407676, 19 10318, 20 20924) |
| `p8-exodin` | 0 autocast · 1 item · 2 20271 · 3 the primary-seal macro · 4 407778 · 5 wait · 6 415073 · 7 407676 |
| `p8-stack` | 0 autocast · 1 item · 2 20920 · 3 407798 · 4 407778 · 5 407676 · 6 415073 · 7 10318 · 8 20924 · 9 20271 |
| `p8-shockadin-1h` | 0 item · 1 **16322** · 2 autocast · 3 item · 4 20271 · 5 the primary-seal macro · 6 407624 · 7 20930 · 8 415073 · 9 407624 · 10 20930 · 11 407676 |
| `p8-shockadin-2h` | the same shape as the 1h file (item, **16322**, autocast, item, 20271, macro, 407624, 20930, 415073, 407624, 20930, 407676) |
| `p8-wrath` | 0 autocast · 1 item · 2 **16322** · 3 item · 4 20271 · 5 the primary-seal macro · 6 wait · 7 407778 · 8 407676 · 9 415073 · 10 407778 · 11 20271 · 12 20924 |

Pre-pull: `p8-stack` 20920 @−3 s + 407798 @−1.5 s; `p8-twist` 20920 @−1.5 s
(the StopAttack macro cast) + 407798 @0 s (the StartAttack macro cast);
`p8-exodin` the primary seal @−2.5 s; `p8-shockadin-1h/2h` and `p8-wrath` the
primary seal @−1.5 s.

### TBC — `wowsims/tbc-new ui/specs/paladin/retribution/apls/default.apl.json`

| i | row | condition |
|---|---|---|
| 0 | autocast | `currentTime >= "Delay Major CDs"` |
| 1 | 31892 (the twist's Blood seal) | `auraIsActive(20375 r1)` AND `autoTimeToNext(MeleeAuto) <= .4 s` |
| 2 | 35395 Crusader Strike | `auraIsActive(31892 r1)` |
| 3 | 20271 Judgement | `auraIsActive(31892 r1)` AND `gcdIsReady` AND `autoTimeSinceLast(AnyAuto) <= .8 s` |
| 4 | group `ExoOrConsec` → 27138 / 27173 | `auraIsActive(31892 r1)` + the `Use Exorcism` / `Use Consecrate` variables |
| 5 | 20375 (the reseal) | `auraIsInactive(20375 r1)` AND NOT `spellIsReady(20271)` AND … |

Pre-pull: 20218 @−18.5 s, group `PrepullSeal` @−1.5 s (27158 **or** 20375),
group `PrepullJudge` @0 s (20271), group `PullSeal` @0 s (31892 **or** 20375).

### FOREVER — `wowsims/forever ui/specs/paladin/retribution/apls/`

`twist_of_light`: 0 autocast · 1 20271 · 2 24239 · 3 **10333** · 4 20920 ·
5 20293 · 6 group `Consecration` → 20924 · 7 group `Exorcism` → 10314.
`holy_shock`: 0 autocast · 1 20271 · 2/3 the itemSwap rows · 4 20924 · 5 24239 ·
6 20293 · 7 **10333** · 8 **20216** · 9 20930 · 10 10314.

Pre-pull: `twist_of_light` 10301 @−10 s, 20920 @−3 s, 20308 @−1.5 s;
`holy_shock` 10301 @−10 s, 20308 @−1.5 s.

### WOTLK — `wowsims/wotlk ui/retribution_paladin/apls/default.apl.json`

| i | row | condition |
|---|---|---|
| 0 | autocast | — |
| 1 | **67485** | — |
| 2 | **48806** | — |
| 3 | **53408** | — |
| 4 | 35395 Crusader Strike | — |
| 5 | 53385 Divine Storm | — |
| 6 | 48801 Exorcism | `auraIsActive(53488)` |
| 7 | 48819 Consecration | `remainingTime > 4 s` |

Pre-pull: `OtherActionPotion` @−1 s (a potion — a harness row).

## 2. What landed

### 2.1 The rotation table (`ST.PALADIN.practice_rotation`)

The shipped table carried **12** keys — every one of them a damage ability, a
seal, a judgement or a shockadin cooldown. The APL layer adds **five** rows
(17 in the table) and gives **every** row both HU-13 flags.

| # | action | label | families | ids | live | engine | APL position |
|---|---|---|---|---|---|---|---|
| 13 | `hor` | Hand of Reckoning | WRATH | 67485 | true | **true** | wotlk `default.apl.json` i=1 (the APL's TOP row) |
| 14 | `how_wrath` | Hammer of Wrath (WotLK) | WRATH | 48806 | true | **true** | wotlk i=2 |
| 15 | `judgement_of_wisdom` | Judgement of Wisdom | WRATH | 53408 | true | **false** (filed) | wotlk i=3 |
| 16 | `holy_strike` | Holy Strike | FOREVER | 10333 | true | **false** (filed) | forever `twist_of_light` i=3, `holy_shock` i=7 |
| 17 | `divine_favor` | Divine Favor | FOREVER | 20216 | true | **false** (filed) | forever `holy_shock` i=8 |

The twelve shipped rows now carry `live = true, engine = true` as well: every
one of them is named by a shipped order, so the frozen engine can press it.

**The rows the shipped orders DO cover** (nothing was invented): the Era APL's
Judgement / Seal of Command / Seal of Righteousness pair is the class's own
twist tree (`soc` + the twist-seal channel), the SoD APL's rows are the shipped
SoD orders (Exodin / stack / shockadin / wrath-like), the TBC APL's rows are
the shipped twist order, and the Forever APL's rows are the shipped twist tree
plus the three rows above.

### 2.2 The engine arms (`nextaction.lua`)

The **WotLK APL's utility band** rides the Wrath FCFS order:

```
FCFS_ORDER_WRATH = { "hor", "how_wrath", "cs", "judge", "ds", "cons", "exo", "hw" }
                     └─ the APL's i=1 ─┘ └─ the APL's i=2 ─┘  └─ the shipped damage rows, in their shipped order ─┘
```

| arm | gate | condition |
|---|---|---|
| `hor` | WRATH only | the cooldown is known and back (`api.GetSpellCooldown(67485)` behind the client's own spell-book gate) |
| `how_wrath` | WRATH only | the cooldown is back **and** the target is below 20 % — the sim's own `ExtraCastCondition: sim.IsExecutePhase20()` (sim `wowsims/wotlk sim/paladin/hammer_of_wrath.go:31-32`) |

**CITATION CORRECTION 2026-10-20 (desk `paladin-audit-close`):** this table
cited `hammer_of_wrath.go:18` for `ExtraCastCondition`. The fetched file has
`ExtraCastCondition` at **:31** and `IsExecutePhase20()` at **:32** — `:18` is
the `ManaCost` `BaseCost` line. The file's other citation here (`:12` for the
spell id 48806) matches exactly, so the file is the same one and the line
number was simply off by 13 (the same defect the HUD band lane found and filed
in `bench/paladin_hud_utility_band_2026-10-20.md` §2.1, and the same lesson in
`bench/lessons.md`). The code that carried the wrong line — `nextaction.lua`'s
`how_wrath` input contract and arm, and `classes/paladin.lua`'s `how_wrath`
rotation row — now cites `:31-32` too.

New frozen inputs: `hor_remaining`, `how_wrath_remaining` (nil or the 999
sentinel = unknown = withheld, never prompted).

**The damage rows keep their shipped relative order.** The full APL re-cut
(`hor, how_wrath, jow, cs, ds, exo, cons`, with the shipped `judge`/`hw` rows
dropped because the WotLK APL has no row for them) is the operator-visible
item the gap analysis filed (`bench/rotation_gap_vs_apl_2026-10-20.md` §6.5)
and it is **not** done here.

### 2.3 The guide slots (the count pin re-cut)

Two new slots — `hor` (67485) and `how_wrath` (48806) — so the guide can
light them. The paladin declares **twelve** slots now (ten → twelve); the
contract's count pin was re-cut with them (the HU-10 precedent: a count pin
must match the shipped slot set, not a stale one). The two rows land on the
**action** channel (like the Crusader Strike icon) and pop over the fillers
exactly like every other action icon.

### 2.4 The gather's reads (`classes/paladin.lua`)

Two new reads, both through wrappers that exist in `compat.lua` today —
**no new client API**:

* `api.GetSpellCooldown(67485 / 48806)` through the class's own
  `get_guide_cooldown_remaining` helper, **behind the client's spell-book
  gate** (`api.is_spell_known`): a build without the talent answers "unknown"
  and is never prompted. (The spell-book probe on a **talent** id is
  in-client UNCONFIRMED — it is the same gate the class's Divine Storm
  resolver uses for its WotLK talent spell, `classes/paladin.lua`'s
  `resolve_ds_spell_id`; if the client answers "unknown" for a learned
  talent the row stays **silent** — unknown-hides, never a wrong prompt —
  and the operator's in-client check decides whether another gate is needed.)
* `api.UnitHealth` / `api.UnitHealthMax` (the target health) now also reach
  the WotLK client, where the APL's Hammer of Wrath row is an execute-phase
  cast. An unknown health withholds the row.

### 2.5 The pre-pull table (HU-12)

`ST.PALADIN.practice_prepull_rows` grew from **2** rows to **11** — every
`prepullActions` row the fetched APLs carry, each with its family gate, its
offset and its citation:

| family | rows (id @ lead) |
|---|---|
| TBC | 20218 @18.5 · 20375 @1.5 · 27158 @1.5 · 20271 @0 · 31892 @0 · 20375 @0 |
| FOREVER | 10301 @10 · 20920 @3 · 20308 @1.5 |
| SOD | 20920 @3 · 407798 @1.5 |

The class's own `PRACTICE_PREPULL` table (the seal + the lead per order) is
what the pre-pull DRILL grades; this table is the citation layer. **No
pre-pull row appears in the combat rotation** (pinned).

### 2.6 The practice surface

The practice key space learned the two new presses (`hor`,
`how_wrath` — the engine's answer maps onto them, with spell-name aliases
that do NOT collide with the Era/Forever execute Hammer of Wrath the `how`
key names), and the **panel's button vocabulary** carries them: they ride the
Wrath order, so `practice_rotation_for("wrath")` publishes them. The three
rows **without** an engine arm stay out of the vocabulary (the hunter lane's
rule: a row the engine can never emit is a button that can never be the right
answer).

## 3. Corrections to the gap analysis (§6 of the corpus)

**C1 — 20216 is DIVINE FAVOR, not Devotion Aura.**
The corpus's §6.3 row reads "`devotion_aura` | Devotion Aura | 20216 |
FOREVER only | NEW PROBE — `api.scan_player_aura` on 20216". The **name and
the proposed read are both wrong**:
* `wowsims/forever sim/paladin/spell_data_auto_gen.go:183` —
  `DivineFavor: spelldata.Ranked(20216)`, and the client's own sim file
  (`wowsims/classic sim/paladin/divine_favor.go:28`) labels it
  `Label: "Divine Favor"`, `ActionID: core.ActionID{SpellID: 20216}`.
* The 1.15 client's own spell tables put **20216 in the Holy skill line**
  (next to Seal of Righteousness 20293 and Holy Shock 20930) — it is a
  Holy spell, not an aura.
* The Forever Devotion **Aura**'s own ladder is
  `spelldata.Ranked(465, 10290, 643, 10291, 1032, 10292, 10293)` — 20216 is
  not in it.
* The APL's row is a **spell cast**, not an aura upkeep, so the corpus's
  proposed read (`scan_player_aura`) was the wrong shape for it.
→ the row ships as `divine_favor` (Divine Favor), and the corpus's
"Devotion Aura" row is withdrawn.

**C2 — 53408 is JUDGEMENT OF WISDOM, not Judgement of Light.**
`wowsims/wotlk sim/paladin/judgement.go`:
`registerJudgementOfWisdomSpell` → `ActionID{SpellID: 53408}` (line 22) and
`registerJudgementOfLightSpell` → `ActionID{SpellID: 20271}` (line 64). The
corpus's §6.3 row (`jOL` | "Judgement of Light" | 53408) and §6.5.2 ("`judge`
on WotLK is Judgement of Light (53408)") are name-swapped. The corpus's
**id** was right; its **name** was wrong — and the shipped `judge` row
(`classes/paladin.lua`, whose WotLK id is 20271) is Judgement of **Light**,
so the two rows really are different spells, as the corpus said.
→ the new row is `judgement_of_wisdom` (Judgement of Wisdom), and the
shipped `judge` row's source now names 53408 correctly.

**C3 — 20375 is SEAL OF COMMAND on the Era client (not Seal of the Crusader).**
The corpus's §0.3 trap list and §7.3 call 20375 "Seal of the Crusader in
Era/SoD and Seal of Command in TBC". The **1.15 client's own spell tables**
put **20375 in the Retribution skill line** (skill line 184) and the
Classic sim's own Seal of Command table starts at 20375 (rank 1, level 20:
`wowsims/classic sim/paladin/soc.go`); the Era Seal of the **Crusader**'s
ranks are 21082, 20162, 20305, 20306, 20307, 20308
(`wowsims/classic sim/paladin/sotc.go`) — 20375 is not among them. So 20375 is
Seal of Command on **every** shipped family, and the shipped `soc` row's
label is right. The corpus's `sotc` row ("the Seal of the Crusader has no
rotation line anywhere") describes a row the Era APL does **not** carry (the
Era APL twists 20375 ↔ 20293), so no `sotc` rotation row was built.

**C4 — 10301 is RETRIBUTION AURA, not Redemption.**
The corpus's §7.4 listed 10301 as UNCONFIRMED ("the TBC table calls 10301
'Retribution Aura'; the Forever prepull's meaning is not pinned") and the
shipped pre-pull row was labelled "Redemption" with the name UNCONFIRMED. The
**name is now pinned**: `wowsims/forever sim/paladin/retribution_aura.go:11`
cites `https://www.wowhead.com/forever/spell=10301`, and the 1.15 client's
own tables put 10301 in the Retribution skill line. → the pre-pull row is
labelled "Retribution Aura" and its source carries the correction.

**C5 (extra) — the SoD's "Purity 16322" is a DEAD ROW.**
The corpus's §6.3 lists `purity` | Purity | 16322 | SoD only | `p8-shockadin-1h`
i=1 · `p8-wrath` i=2 | NEW PROBE. **16322 is absent from the 1.15 client's own
spell tables** (`SkillLineAbility.csv` — no row for it) and the client's own
spell pages name it **"Juju Flurry"** (a battle elixir, a Nature-school
buff), not a paladin spell; the SoD sim registers no spell with that id
either, so the sim's APL interpreter ignores the row. The corpus's "Purity"
name has no source at all. → **no row was built**: a row the client cannot
cast is not a rotation line. (Filed here so the corpus's claim is not
silently inherited.)

**C6 (extra) — the corpus's "the Blessings / Divine Favor / Rallying Cry of
the Dragonslayer / Avenging Wrath" cluster.** The brief's list names them as
APL rows; **the fetched APLs carry none of them**: no Blessing row, no
Avenging Wrath row (the WotLK sim's `autocastOtherCooldowns` pops it — a
sim-harness row, not a rotation decision), no Rallying Cry row (it is a
Naxxramas item effect, not a spell). The only Divine Favor row in the corpus
is the one C1 corrects. The rows that ARE in the APLs and that the shipped
orders did not cover are exactly the five in §2.1.

## 4. Filed, not built (and why)

| row | what it waits for |
|---|---|
| `judgement_of_wisdom` (WRATH, 53408) | an arm needs a slot that does not collide with the shipped judgement cue: 53408 (Judgement of Wisdom) and 20271 (Judgement of Light) share the WotLK **10 s judgement cooldown** (sim `wowsims/wotlk sim/paladin/judgement.go:38` — one `cdTimer` for both judgements), so the two rows can never be ready apart and an arm would **replace** the shipped judgement cue on the WotLK client. That is the operator-visible re-cut `bench/rotation_gap_vs_apl_2026-10-20.md` §6.5 filed. The read exists (`api.GetSpellCooldown(53408)`) → the row is **live**, with no arm. |
| `holy_strike` (FOREVER, 10333) | an arm needs the **Forever twist order** re-cut onto the APL's priority list (judgement > hammer of wrath > holy strike > seal of command > seal of righteousness > consecration > exorcism). Holy Strike has **no cooldown of its own** on the Forever client (the client's own sim registers it without a CD — `wowsims/forever sim/paladin/holy_strike.go`), so a "ready" arm would fire on **every GCD** and displace the twist cue the class's Forever guide exists for. The read exists (the class's own spell-book probe, `self.holy_strike_known` — the class's own header calls this a "plug-in point pending a slot ruling") → the row is **live**, with no arm. |
| `divine_favor` (FOREVER, 20216) | an arm needs the APL's own condition modelled: "the Divine Favor buff is DOWN" (the sim's buff is consumed by the next Holy Shock hit — `wowsims/classic sim/paladin/divine_favor.go:37`), AND "Holy Shock is ready" (the APL's `spellIsReady(20930 r4)`), AND the target-aura clause on 1310905 (the Forever client's Consecrated Ground — `wowsims/forever sim/paladin/spell_data_auto_gen.go:176`). The cooldown read exists, but the shipped tree has **no Holy-Shock cooldown read on the Forever family** and **no read that separates "the buff is absent" from "the buff could not be read"** (`api.scan_player_aura` answers nil for both — `compat.lua:514`), so an arm built on the cooldown alone **could ask for a buff that is up** — the one thing the brief forbids. → **live** (the cooldown read exists), **no arm**, the exact reads filed. |
| the SoD's 16322 row | a dead row (C5) — the client has no such spell. Nothing to build. |
| the WotLK **HUD mirror** for the two new guide slots | the HUD slot count is pinned in `tests/hud_state.lua`, which is out of this lane's scope. The guide slots are guide-only for now (the same precedent the shaman lane took). |
| the full WotLK APL order re-cut | the operator's call (§2.2). |

## 5. Validation

* `bash tests/run.sh` → **41 steps, 0 failed**.
* `luacheck .` → **2 warnings / 0 errors in 83 files** — the tree's floor
  (both warnings are the pre-existing ones in `compat.lua` and `main.lua`,
  untouched by this lane). The three files this lane touched: 0 warnings.
* `tests/paladin_state.lua` → **PASS (1041 checks)** (was 956 before this
  lane's §26 pins): the utility layer's shape, its flags, its ids, its
  citations, the corpus corrections, the slice rules, the two new guide slots,
  the gather's reads (the family gate, the spell-book gate, the
  unknown-hides), the pre-pull table's eleven rows and the practice mapping.
* `tests/nextaction_state.lua` → **PASS (625 checks)** (the Wrath order pins
  re-cut for the utility band + the two arms' pins).
* `tests/guide_contract.lua` → **PASS (1052 checks)** (the paladin slot-count
  pin re-cut: ten → twelve, and the frame-count pin 28 → 32).
* **Mutation proofs: 14 / 14 killed** (`python3 /tmp/opencode/paladin_apl_mutations.py`,
  disposable copies under `/tmp/opencode/paladin-apl-mut`):

| mutant | killed by |
|---|---|
| the Hand of Reckoning arm is removed | the arm pin |
| the WotLK Hammer of Wrath loses its execute-phase gate | the execute pin |
| an unknown target health no longer withholds the Hammer of Wrath | the unknown-hides pin |
| the utility band is dropped from the Wrath order | the order pins |
| the gather feeds Hand of Reckoning without the spell-book gate | the unknown-hides pin |
| the utility band leaks onto every family | the family-gate pin (the Era client must not even ASK its book) |
| **the buff-up line starts prompting** (the Divine Favor row is armed without the buff-down read) | the "claims NO engine arm" pin + the vocabulary pin |
| the Divine Favor row's id is swapped for the corpus's Devotion Aura id | the id pin |
| the Judgement of Wisdom row's id is swapped for Judgement of Light | the id pin |
| the corpus correction is reverted (53408 called Judgement of Light) | the correction pin |
| the pre-pull row's 10301 label reverts to "Redemption" | the correction pin |
| the guide loses the two new APL-band slots | the slot pins |
| the practice mapping drops the Hand of Reckoning press | the practice-mapping pin |
| the pre-pull table loses the Forever Seal of the Crusader row | the pre-pull pin |

* **Line endings:** `classes/paladin.lua` stays pure CRLF (5851 CRLF, 0 bare
  LF); `nextaction.lua` stays pure CRLF (1440 / 0); the three test files stay
  pure LF. No trailing whitespace on any touched line.
* **Offline only.** Nothing here was loaded in a game client. Per `CAIRN.md`
  ("two proofs, two words") this is a source-cited build with a
  mutation-proofed offline pass, not a verified-in-client one. **Validation
  owner: the orchestrator.**

## 6. The operator-visible change (read this before the release)

The two armed rows change what the **WotLK** guide shows: while Hand of
Reckoning is off cooldown (two minutes) or the WotLK Hammer of Wrath is off
cooldown in the execute phase, the guide now prompts those instead of
Crusader Strike — which is the WotLK APL's own order (i=1, i=2 above the
damage rows). Every other family is untouched: the band's reads are Wrath-gated
and spell-book-gated, so an Era/TBC/Forever/SoD client never even asks its
book about the two spells.

The rest of the WotLK order is **not** re-cut: the shipped damage rows keep
their relative order, and the shipped Judgement and Holy Wrath rows stay where
they were (the WotLK APL has no row for either). Re-cutting the order onto the
APL's full priority list — which would also drop the shipped `judge` and `hw`
rows — is the operator's call (§4).

## 7. Sources

* The ten APL files, fetched 2026-10-20 from
  `raw.githubusercontent.com/wowsims/{classic,sod,tbc-new,forever,wotlk}/master`
  (the paths are in §1 and inline in every row's `source`).
* The sims' own ability files: `wowsims/wotlk sim/paladin/{hand_of_reckoning,
  hammer_of_wrath, judgement, divine_storm, exorcism, consecration,
  crusader_strike}.go`, `wowsims/forever sim/paladin/{holy_strike,
  devotion_aura, retribution_aura, spell_data_auto_gen}.go`,
  `wowsims/classic sim/paladin/{soc, sotc, sor, divine_favor}.go`,
  `wowsims/tbc-new sim/paladin/spell_data_auto_gen.go`.
* The Classic 1.15 client's own spell tables (`/home/sam/wow.export`'s
  `SkillLineAbility.csv` + `SkillLine.csv`): 20216 → the Holy skill line,
  20375 → Retribution, 20308 → Retribution, 10301 → Retribution, 16322 →
  **absent**.
* `bench/rotation_gap_vs_apl_2026-10-20.md` §6 (the gap analysis this lane
  built from — with §3's corrections) and `bench/lessons.md` (the TBC-name /
  Era-id rule).
