# The warrior's APL utility lines go LIVE — 2026-10-20

Desk: `warrior-utility-live`. The lane that answers the operator's "wire the arms":
the APL's utility rows were in the rotation table as documentation (`live = false`,
"no engine rule can ask for them yet"); this lane gives the frozen engine the arms
and the reads, so the practice scenario can ask for them and the guide can light them.

**Source spec:** `bench/warrior_apl_utility_build_2026-10-20.md` (the build lane: the
thirteen rows, their ids, their family gates, their APL positions) and
`bench/rotation_gap_vs_apl_2026-10-20.md` section 1 (the gap analysis).

**What changed (4 files, all in scope):**

| file | change |
|---|---|
| `warrior_guide.lua` | the utility spine: the per-line verdict, the order walk, the stance upkeep arm, the weave arm, the new inputs and the new rules in the matrix |
| `classes/warrior.lua` | `WARRIOR_UTILITY` (the one source of truth for the ids, the family gates, the labels, the citations and the slots), the aura walk's buff stamps, the gather's utility reads, the guide slots, the generated rotation block 2, the `warrior_prepull` drill |
| `tests/warrior_state.lua` | the re-cut pins (the slot counts, the drill list, the flags) and a new section 39 (the provider's reads + the pre-pull drill) |
| `tests/warrior_guide_state.lua` | the re-cut slot pins and a new section 0b/0c (the pure verdict, the order walk, the stance arms, the engine-level picks) |

---

## 1. The flag convention (HU-13, the orchestrator's ruling)

Two flags, cross-class, on EVERY rotation row:

* `live` — the line's **read exists** and the line can be evaluated.
* `engine` — the **frozen engine has an arm** that can ask for the line.

The build lane shipped `live = false` on all thirteen rows (the warrior's way: one
flag, meaning "the engine can play it"). The hunter lane shipped `live = true` plus
`engine = false` on the rows it could not play (the hunter's way: two flags). The
orchestrator ruled the hunter's shape, so the warrior now carries both:

* block 1 (the compiled rule order): `live = true, engine = true` on every row but
  `cleave` — the engine never emits `cleave` (it is the one compiled key no rule
  outputs), so that row is `live = true, engine = false`.
* block 2 (the APL's utility spine): `live = true` on all thirteen rows (the reads
  exist now) and `engine = true` on twelve of them. **`gladiator_stance` is
  `engine = false`** — see §4.

## 2. The reads (no new client API)

Every read is an existing `compat.lua` wrapper or an existing aura walk:

| read | wrapper | notes |
|---|---|---|
| the spell's own cooldown | `api.GetSpellCooldown` (compat.lua:229) through the class's own `get_guide_cooldown` (the GCD echo filtered) | the TBC client resolves by NAME (`api.get_spell_query`, compat.lua:1544) — the name is the primary key there |
| the client knows the spell | `api.is_spell_known` (compat.lua:208) through the class's own `is_spell_known_query` | a line the client lacks is never asked for |
| the row's buff | the class's own HELPFUL aura walk (`ST.WARRIOR.on_aura_change`) | the Battle Shout row rides the existing id table + name fallback; the other four ride their literal English name (no buff id is cited in any fetched sim source, and a guessed id could match the wrong aura) |
| the current stance | the same aura walk, `WARRIOR_STANCES.ids` | **412513 (the SoD Gladiator Stance) is now in the id table** — the gap analysis's finding that it was missing |
| the rage pool | `api.UnitPower` (compat.lua:349) | the APL's own rage ceiling (Bloodrage: `currentRage < 90`) |

The family gate lives in the **provider** (the engine stays family-agnostic): a line
the running family's APL does not carry is never read, never fed and never asked for.
The SoD branch rides the ERA token but has its OWN APL, so the SoD rows carry a `sod`
flag (the SoD APL carries no Battle Shout, no Berserker Rage and no Blood Fury row).
The WotLK rows carry a `specs` gate (Thunder Clap is the arms row, Shattering Throw
and Heroic Throw the fury rows).

## 3. The engine's arms (`warrior_guide.lua`)

The engine is pure and family-agnostic; the provider feeds the reads and the running
family's APL order, and the engine walks the order.

* `utility_line_due(line, inputs)` — the per-row verdict. A row is asked for only
  when **every** gate is a known gate: the client knows the spell, the cooldown is
  READ and ready, the buff is READ and **not up**, and the rage pool is known and at
  or under the APL's ceiling. An unreadable buff, cooldown, knowledge probe or rage
  pool never prompts (unknown hides).
* `utility_spine_pick(order, inputs)` — the APL's own priority order decides; the
  first due row wins.
* `utility_stance_action(stance, wanted)` — the stance upkeep row (the APL's last row
  on every family that carries one: "cast the stance when its aura is NOT active").
  A stance the player is already in is never asked for; an unknown stance never asks.
* `utility_weave_stance(stance, weave, op_context)` — the Overpower weave's first
  step (the dance into Battle Stance). The sims register Overpower with a
  Battle-stance requirement, so the weave is what makes the Overpower castable; the
  APL's own rows are the SoD strictSequence (`[2457, 11585]` behind the gate aura
  426969), the TBC `Overpower Weaving` group (`wait -> 2457 -> 11585 -> 2458`) and
  the WotLK strictSequence (`[2457, 7384, 2458]`).

**Where the rows sit in the matrix** (the APL's own positions, per family):

| rule | position | rows |
|---|---|---|
| W0 (the weave's first step) | ahead of rule 1 (the Overpower) | `battle_stance` (SOD / TBC / WotLK) |
| U1 (the HIGH rows) | ahead of rule 1 (the Overpower) | the rows the APL puts above the core: Bloodrage on WotLK (`[1]`), Death Wish / Recklessness / Sweeping Strikes on TBC (`[8]`-`[10]`) and Forever (`[10]`-`[12]`), Death Wish / Recklessness on SoD (`[12]`, `[14]`) |
| M (the stance upkeep) | above the core, under the procs and the Execute range | `berserker_stance` (ERA / SOD / TBC / WotLK), `battle_stance` (Forever: its Stance Dance toggle ships off, so the player sits in Battle Stance) |
| U2 (the LOW rows) | above the filler (never after the rage dump) | the rows the APL puts below the core: the Era APL's five rows (`[3]`, `[7]`, `[21]`-`[23]`), the TBC Bloodrage / Berserker Rage / Battle Shout (`[20]`-`[22]`), the Forever Bloodrage / Battle Shout (`[28]`, `[29]`), the WotLK Thunder Clap / Shattering Throw / Heroic Throw |

The per-family order and the split are the APL's own priority list, read out of the
fetched files on 2026-10-20 (`wowsims/{classic,sod,tbc-new,forever,wotlk} master`).
The APL's conditions that the engine could NOT read honestly are not guessed (see §4).

**One documented deviation in the relative order:** the weave's first step (W0) sits
above the HIGH rows, because the weave IS the rule-1 cast and the Overpower window is
time-critical. The TBC APL puts its `Overpower Weaving` group (`[16]`) BELOW its
Death Wish / Recklessness / Sweeping Strikes rows (`[8]`-`[10]`), so on TBC the
engine asks for the stance first. The SoD APL puts its stance rows (`[0]`-`[6]`)
above its Bloodrage row (`[7]`), which the engine reproduces exactly.

## 4. The one row with no arm: `gladiator_stance`

The SoD APL's Gladiator Stance rows (`[0]` and `[4]`) are gated on the rune auras
`457817` and `464241` with `auraIsKnown` — a condition the client's aura list cannot
answer (it reports the ACTIVE auras only) and a rune id that no fetched sim file
names. The line's own READ now exists (412513 is in `WARRIOR_STANCES.ids`, so the
stance walk resolves the rune stance like the other three), so the row is
`live = true`; but there is no honest gate for the rule, so it stays
`engine = false` and the engine never asks for it. That is the two-flag convention
doing its job: the read exists, the arm does not.

## 5. The pre-pull table

`ST.WARRIOR.PRACTICE_PREPULLS` (the build lane's table) is wired into the practice
flow the way the hunter's is: a `warrior_prepull` drill (kind `transition`) that
grades the opening sequence in the APL's own order, with the offset relative to the
pull. The drill owns the pull clock (the caller's own pull moment wins; the drill's
synthetic clock opens the countdown at the family's first opener — the hunter's
shape). The combat rotation never asks for these rows: the rotation table carries
no pre-pull row (Charge and Intercept are in no rotation block), and the rotation
scenario's own pick comes from the engine, which never emits one.

## 6. The guide slots

The engine can now emit the utility rows, so the guide needs a slot for each one
(the guide frame lights the slot the action names; an action with no slot lights
nothing). Each family's slot set gained exactly the rows its APL carries: TBC eight,
Era six, SoD four, Forever six, WotLK fury four, WotLK arms two. The icons are the
rows' own spell ids (the TBC family uses the TBC client's ids: Battle Shout rank 8
`2048`, Death Wish rank 1 `12292`; the Era / Forever clients use the older ranks).
The HUD mirror (`ST.WARRIOR.HUD_SLOTS`) is **unchanged** — the HUD is the cooldown
row, not the guide, and `config_presets.lua` (out of scope) carries the
`hud_show_*` defaults. The slots are stacked on the frame's centre (one fades in at
a time), so the frame's geometry does not change.

## 7. What this lane did NOT do

* No new client API (every read is an existing wrapper or the existing aura walk).
* No new option, no toggle, no default-visible change beyond the rows the APL asks
  for: the guide's slot set grew by the rows the running family's APL carries, and
  the guide's next-action pick can now name them.
* No `practice_rotation_for` for the warrior (the build lane filed it as a separate
  follow-up: "a lane that adds it must publish the LIVE lines only"). The practice
  panel's button vocabulary therefore still comes from the guide slots — which now
  carry the utility rows.
* The APL's conditions that need a target count (Sweeping Strikes' `numberTargets >
  1`), a Bloodlust alignment (the TBC / Forever `multipleCdUsages` rows), a rune
  aura (`auraIsKnown`) or an execute-phase gate are **not** modelled: the tree has no
  target-count read and no Bloodlust clock, and a guessed gate would prompt wrongly.
  The rows that carry them are asked for on their cooldown + buff gates alone; that
  is a documented deviation, not a silent one.
* No in-client verification. Per `CAIRN.md` ("two proofs, two words") this is a
  source-cited build with a mutation-proofed offline pass, not a verified-in-client
  one.

## 8. Validation

* `bash tests/run.sh` → **41 steps, 0 failed**. The warrior's own suites:
  `tests/warrior_state.lua` → **PASS (1635 checks)** (was 1564), 
  `tests/warrior_guide_state.lua` → **PASS (2019 checks)** (was 1728).
* luacheck → the tree total is back at the floor: **2 warnings / 0 errors** (the
  pre-existing `compat.lua:36` and `main.lua:81` warnings, both untouched by this
  lane). This lane's four files: **0 warnings / 0 errors**. (Mid-lane the tree
  carried three extra warnings from the rogue lane's in-flight work; they are
  gone now.)
* **Mutation proofs: 13/13 killed** on `/tmp/opencode` copies (the script is at
  `/tmp/opencode/mut_warrior_utility.py`, the tree copy at
  `/tmp/opencode/mut_warrior_utility`): the engine's buff gate dropped, the
  provider's buff stamp dropped, the family gate dropped, the knowledge probe
  dropped, the cooldown gate dropped, the rage ceiling dropped, the stance upkeep
  asking for the stance the player is in, the weave asking outside the Overpower
  window, the Gladiator Stance row given an arm, the Era build grading the TBC
  pre-pull sequence, the pre-pull drill picking the last row, the practice surface
  stopping to feed the utility rows, and the APL's utility order reversed — every
  one fails the suite on the expected pin. The "buff-up line still prompts" mutant
  is the first one.
* **Validation owner: the orchestrator.**
