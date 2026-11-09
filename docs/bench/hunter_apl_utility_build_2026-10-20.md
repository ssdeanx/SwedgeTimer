# The hunter's APL utility layer — 2026-10-20

Desk: `hunter-apl`. **The APL gap analysis is the input, not the authority**: every
id, index and name below was re-fetched from the sim sources on 2026-10-20 and
checked against the shipped file. The gap analysis's hunter section
(`bench/rotation_gap_vs_apl_2026-10-20.md` §2) carries four errors, corrected in
§5 below.

**Scope:** `classes/hunter.lua` (the rotation table + the engine-facing slice),
`tests/hunter_guide_state.lua`, `tests/hunter_state.lua`. `hunter_guide.lua` and
`hunter_ui.lua` were in scope and needed no change (the guide engine's action
vocabulary is unchanged; `hunter_ui.lua` never reads the rotation table).

**Ruling applied (HU-12, orchestrator):** the rotation table carries the APL's
SPELL rows; the APL's PRE-PULL rows stay in `ST.HUNTER.PRACTICE_PREPULLS` (the
table the hunter already has). So the SoD's Serpent Sting (a `prepullActions`
row) and the Forever's Hawk (also a pre-pull row) are **not** rotation rows.

---

## 1. The APLs, re-fetched and expanded (the evidence)

Fetched 2026-10-20 from `raw.githubusercontent.com/wowsims/{classic,sod,tbc-new,
forever,wotlk}/master`, every `groupReference` expanded inline, every spell id
read out of the JSON. The indices below are the `priorityList` index; the
conditions are the rows' own.

**ERA — `wowsims/classic ui/hunter/apls/p1.apl.json`**

| i | id | condition |
|---|---|---|
| 0 | — | `autocastOtherCooldowns` (a sim-harness row) |
| 1 | 3045 | autoTimeToNext(Ranged) < 0.1 s and Aimed Shot ready |
| 2 | 20904 r6 | autoTimeToNext > 1 s |
| 3 | 25294 r4 | autoTimeToNext > 0.5 s |
| 4 | 25295 r8 | dotRemainingTime(25295) < 5 s (the Serpent upkeep) |
| 5 | item 18641 | (an item use — a sim-harness row) |

Pre-pull: 25296 (Aspect of the Hawk) @−10 s; 20904 @−3.5 s.

**SOD — `wowsims/sod ui/hunter/apls/p7_weave.apl.json`**

| i | id | condition |
|---|---|---|
| 0 | OtherActionPotion | (a potion — a harness row) |
| 1 | item 12662 | (a harness row) |
| 2 | cancelAura 415423 | (the Viper is cancelled before the Chimera) |
| 3 | 409433 | dotRemainingTime(25295 r9) <= 5 s (the Serpent rollover) |
| 4,5 | — | `move` (the weave rows) |
| 6 | — | `autocastOtherCooldowns` |
| 7 | 3045 | fight >= 4 s |
| 8,9,10 | item 236334 / item 215162 / cancelAura | (harness rows) |
| 11 | 409433 | |
| 12,13 | 409593 | (Rapid Fire up or E20) and Arcane Shot castable |
| 14 | 25294 r5 | |
| 15 | 409433 | |
| 16 | 14266 r8 | |
| 17 | 458482 | |
| 18,19,20 (HIDE),21 | 409593 | |
| 22 | 415423 | mana < 5% |
| 23 | 14287 r8 | |
| 24 | 469145 | neither the Viper nor the Falcon is up |
| 25 | 20572 | (Blood Fury — a racial; the gap analysis omits it, and it is left out here too) |
| 26 | item 233985 | (a harness row) |
| 27 | 14268 r3 | |

Pre-pull: 469145 @−5 s, 20904 @−3.5 s, 20572 @−1.95 s, 3045 @−0.45 s, 25295 r9 @−0.45 s.

**TBC — `wowsims/tbc-new ui/specs/hunter/dps/apls/default.apl.json`**

| i | id | condition |
|---|---|---|
| 0 | group "Mana management" | 0.g.1 item 22832 (a potion, hidden), **0.g.2 34074** (the Viper inactive and mana < Viper start), **0.g.3 27044 r8** (the Hawk inactive and mana >= Viper stop) |
| 1 | — | `autocastOtherCooldowns` |
| 2 | 34026 | |
| 3 | 34120 r1 | currentTime <= 0.5 s |
| 4 | group "Weave" | (movement) |
| 5 | 27021 r6 | |
| 6 | 27019 r9 | |
| 7 | 34120 r1 | |
| 8 | 27021 r6 | |
| 9 | 27019 r9 | |

Pre-pull: 27044 r8 @−20 s; group "Move to starting range" @−19 s.

**FOREVER — `wowsims/forever ui/specs/hunter/dps/apls/default.apl.json`**

| i | id | condition |
|---|---|---|
| 0 | — | `autocastOtherCooldowns` |
| 1 | 14266 | |
| 2 | 14325 | (the Mark is not up) |
| 3 | 14271 | |
| 4 | 1317257 | (Forever-only, UNCONFIRMED — not landed) |
| 5 | 14305 | |
| 6 | 14268 | |
| 7 | group "Weave" | (movement) |
| 8 | 25295 | |
| 9,10 | — | `resetSequence` / `sequence` (the Hawk sequence) |
| 11 | 1293527 | |
| 12 | 14287 | |
| 13 | 2643 | |
| 14 | 20904 | |
| 15 | — | `wait` |

Pre-pull: 14325 @−22 s, 25296 @−20 s, group "Move to starting range" @−19 s.

**WOTLK MM — `wowsims/wotlk ui/hunter/apls/mm.apl.json`**

| i | id | condition |
|---|---|---|
| 0 | — | `autocastOtherCooldowns` (fight > 10 s) |
| 1 | 34074 | the Viper inactive and mana < 10% |
| 2 | 61847 | the Dragonhawk inactive and mana > 30% |
| 3 | 34490 | |
| 4 | 61006 | |
| 5 | 49001 | the dot is not active |
| 6 | 49067 | the dot is not active |
| 7 | 53209 | |
| 8 | 49050 | |
| 9 | 49048 | |
| 10 | 49045 | HIDE |
| 11 | 49052 | |

**WOTLK SV — `wowsims/wotlk ui/hunter/apls/sv.apl.json`**: the same list with
`i=3` 61006, `i=4` 60053, `i=5` 60052, `i=7` 49001, `i=8` 63672, `i=9` 49050,
`i=10` 49048, `i=11` 49052 (no Silencing Shot, no Chimera Shot).

## 2. The names, confirmed from the client spell pages

Every id the table cites was named on its own client page (Wowhead, the version
path the family lives on): 3045 Rapid Fire, 20904 Aimed Shot, 25294 Multi-Shot,
25295 Serpent Sting, 13554 Serpent Sting, 25296 Aspect of the Hawk, 27044 Aspect
of the Hawk, 34074 Aspect of the Viper, 415423 Aspect of the Viper, 469145
Aspect of the Falcon, 409433 Chimera Shot, 409593 Kill Shot, 61006 Kill Shot,
53351 Kill Shot, 60052/60053 Explosive Shot, 53301 Explosive Shot, 49001 Serpent
Sting, 49067 Explosive Trap, 63672 Black Arrow, 34490 Silencing Shot, 49052
Steady Shot, 34120 Steady Shot, 14287 Arcane Shot, 14266 Raptor Strike, 14268
Wing Clip, 14271 Mongoose Bite, 14305 Immolation Trap, 14325 Hunter's Mark,
**61847 Aspect of the Dragonhawk**.

The sims' own labels agree (`wowsims/wotlk sim/hunter/aspects.go:32-34` — the
WotLK client renamed the Wild aspect to the Dragonhawk).

## 3. What landed in `ST.HUNTER.PRACTICE_ROTATIONS`

The engine-facing rows keep their shipped order (the order the guide plays them
and the order the practice panel's buttons carry); the APL's spine rows follow,
in the APL's own priority order.

| family | new rows (action, id, APL position) |
|---|---|
| ERA | `rapid_fire` 3045 (i=1) — `serpent` 25295 (i=4) |
| SOD | `rapid_fire` 3045 (i=7) — `kill_shot` 409593 (i=12) — `raptor_strike` 14266 (i=16) — `wyvern_strike` 458482 (i=17) — `aspect_viper` 415423 (i=22) — `arcane` 14287 (i=23) — `aspect_falcon` 469145 (i=24) — `wing_clip` 14268 (i=27) |
| TBC | `aspect_viper` 34074 (i=0, the mana group) — `aspect_hawk` 27044 (i=0, the mana group) |
| WRATH | `aspect_viper` 34074 (i=1) — `aspect_dragonhawk` 61847 (i=2) — `silencing_shot` 34490 (i=3, MM) — `serpent` 49001 (i=5/i=7) — `explosive_trap` 49067 (i=6) — `multi` 49048 (i=9/i=10) — `black_arrow` 63672 (i=8, SV) |
| FOREVER | `raptor_strike` 14266 (i=1) — `hunters_mark` 14325 (i=2) — `mongoose_bite` 14271 (i=3) — `immolation_trap` 14305 (i=5) — `wing_clip` 14268 (i=6) — `serpent` 25295 (i=8) — `arcane` 14287 (i=12) — `multi` 2643 (i=13) — `aimed` 20904 (i=14) |

**The id fixes**

| row | was | now | why |
|---|---|---|---|
| WRATH `kill_shot` | 53351 | **61006** | both WotLK APLs cast 61006 (`sim/hunter/kill_shot.go:12`); 53351 is the client's rank-1, the guide slot's fallback |
| WRATH `explosive` | 53301 | **60053** | the SV APL casts the LnL-downrank pair 60053/60052 (`sim/hunter/explosive_shot.go:21,25`); 53301 is the client's rank-1 |
| TBC `steady` | 56641 | **34120** | 56641 is the **WotLK** Steady Shot rank-1 and does not exist on the TBC client (wowhead TBC 56641: no such spell); the TBC APL casts 34120 r1 |
| FOREVER `steady` | 56641 | **nil** (spell-less) | the Forever client has **no** Steady Shot at all (the spell arrived in 2.3; the Forever spell data carries no `SteadyShot` table — `wowsims/forever sim/hunter/spell_data_auto_gen.go`; wowhead classic 34120/56641: no such spell). The row now ships spell-less, like the hawk and sniper rows above it. The guide's own Forever steady slot keeps its fallback id — that is the slot's business, not the table's (filed). |

## 4. The two flags, and why the hunter needs both

* `live` — **the line's READ exists in the shipped tree today.** `true`: the
  Serpent Sting (the target-debuff scan, `read_serpent_active`), the Aspect of
  the Viper (`is_viper_active` / `is_viper_known` plus the mana fraction), the
  Rapid Fire and Multi cooldowns the gather already probes. `false`: the row
  names the exact read it is waiting for in `needs`.
* `engine = false` — **the frozen guide engine has no arm for the line on this
  family.** Such a row never feeds the engine's inputs and never joins the
  practice panel's action vocabulary.

The hunter needs both axes because they come apart here (they do not in the
warrior lane): the Serpent and Viper rows have their reads but no engine rule,
while the aspect rows have neither.

**The panel constraint (why `practice_rotation_for` returns the engine-facing
slice).** The practice row is a fixed 74 px strip with four buttons per row
(`practice_ui.lua:184-188`), so the action vocabulary holds eight actions. The
full spine is thirteen rows on Wrath: showing it would push a third button row
out of the strip, and `practice_ui.lua` is out of this lane's scope. So
`ST.HUNTER.practice_rotation_for(family)` returns the engine-facing rows only
(the shipped vocabulary, byte-identical) and the full spine stays in
`ST.HUNTER.practice_rotation` / `PRACTICE_ROTATIONS[family]`, where the next
lane (a `practice_ui` row-height pass) can pick it up. **Filed, not fixed here.**

## 5. The gap analysis's hunter section is wrong in four places

1. **`kill_shot` ids (gap §2.3).** The row says "14287 (SoD/TBC/Forever) / 61006
   (WotLK)". 14287 is the **Arcane Shot** r8 (the same table's own arcane row
   says so) — the SoD's Kill Shot is 409593 (`proto/hunter.proto:153`,
   `RuneLegsKillShot = 409593`), and the TBC and Forever APLs cast no Kill Shot
   at all, so the TBC/Forever ids have no row to belong to.
2. **`arcane_shot` on Era (gap §2.3).** The row says "Era i=3". The Era APL's
   i=3 is Multi Shot 25294; the Era APL has **no** Arcane Shot row.
3. **`aspect_wild` (gap §2.3).** The id 61847 is right; the NAME is not — the
   WotLK client calls it **Aspect of the Dragonhawk** (the sim's own label is
   too, `sim/hunter/aspects.go:34`). The shipped row is named
   `aspect_dragonhawk` with the client's name.
4. **The Forever Hawk (gap §2.3).** The gap lists 25296 as the Forever Hawk id
   and gates the line on the Forever family — but in the Forever APL the Hawk
   is a **pre-pull** row (`prepullActions` i=1), so under HU-12 it stays in the
   prepull table (where it already is) and is not a rotation row.
5. (bonus) The gap calls the Era pre-pull 25296 "Aspect of the Cheetah"; the
   client page says 25296 is the **Aspect of the Hawk** (the Cheetah is 5118).
   The shipped prepull table already labels it "Aspect of the Hawk" — correct.

## 6. The filed reads (the `live = false` rows)

| family | row | the read it needs |
|---|---|---|
| SOD | `kill_shot` | the rank 409593 in `kill_shot_ids` + `api.GetSpellCooldown` (the execute's health read is gated on `kill_shot_current_id`) |
| SOD | `raptor_strike` | the rank 14266 in `raptor_strike_ids` + `api.GetSpellCooldown` (the table stops at 14265) |
| SOD | `wyvern_strike` | `api.GetSpellCooldown` on 458482 |
| SOD | `arcane` | the rank 14287 in `arcane_shot_ids` + `api.GetSpellCooldown` |
| SOD | `aspect_falcon` | `api.scan_player_aura` on 469145 (the `is_viper_active` reader's shape) |
| SOD | `wing_clip` | `api.GetSpellCooldown` on 14268 |
| TBC | `aspect_hawk` | `api.scan_player_aura` on 27044 + the mana fraction |
| WRATH | `aspect_dragonhawk` | `api.scan_player_aura` on 61847 + the mana fraction |
| WRATH | `silencing_shot` | `api.GetSpellCooldown` on 34490 |
| WRATH | `explosive_trap` | `api.GetSpellCooldown` on 49067 |
| WRATH | `multi` | the rank 49048 in `multi_shot_ids` + `api.GetSpellCooldown` |
| WRATH | `black_arrow` | `api.GetSpellCooldown` on 63672 |
| FOREVER | `raptor_strike` | the rank 14266 in `raptor_strike_ids` + `api.GetSpellCooldown` |
| FOREVER | `hunters_mark` | `api.scan_unit_aura` on the target for 14325 (the `read_serpent_active` scan's shape) |
| FOREVER | `mongoose_bite` | `api.GetSpellCooldown` on 14271 |
| FOREVER | `immolation_trap` | `api.GetSpellCooldown` on 14305 |
| FOREVER | `wing_clip` | `api.GetSpellCooldown` on 14268 |
| FOREVER | `arcane` | the rank 14287 in `arcane_shot_ids` + `api.GetSpellCooldown` |
| FOREVER | `aimed` | `api.GetSpellCooldown` on the Aimed Shot rank, with the gather's aimed block ungated for the Forever family (it runs on the Era set only) |

Every one of them is a compat wrapper that exists today (no new client API) —
pinned by `tests/hunter_state.lua` section 26.

## 7. Validation

* `tests/hunter_guide_state.lua` — PASS (1747 checks; +233 pins).
* `tests/hunter_state.lua` — PASS (1158 checks; +96 pins; one re-cut, the
  source-wide "14287 stays out" scan, now scoped to the `arcane_shot_ids` table
  it was written about — the ROTATION table legitimately cites 14287 as the
  SoD/Forever APL's Arcane Shot row).
* luacheck on `classes/hunter.lua` — 0 warnings / 0 errors (the tree's floor is
  2 warnings / 0 errors, both pre-existing in untouched files).
* 11/11 mutations killed on `/tmp/opencode` copies: the kill-shot id, the
  explosive id and the TBC steady id reverting; the serpent id and the serpent
  row's name changing; the serpent row dropped; a `live = false` row claiming
  its read exists; a filed `needs` string dropped; a row losing its family
  gate; a spine row starting to feed the engine; and **the engine guard itself
  removed from the scenario input build** — that last one flips the Era
  scenario's expected action from `multi` to `rapid_fire`, which is the pinned
  proof that the shipped verdict did not move.
  Reproduce with `python3 /tmp/opencode/mutations_hunter_apl.py` (it builds a
  disposable copy per mutation and cleans up after itself).
