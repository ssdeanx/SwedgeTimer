# Warrior: the Heroic Strike / Cleave queue drill + W-15 + W-21 — 2026-10-20

Desk: warrior-hs-queue. Lane scope: `classes/warrior.lua`, `warrior_guide.lua`,
`tests/warrior_state.lua`, `tests/warrior_guide_state.lua`, `tests/hud_state.lua`
(**warrior census only**). Validation owner: **orchestrator**.

Dispatch: the operator's Heroic Strike / Cleave queue drill (a first-class drill
in the warrior's own drill list, `ST.WARRIOR.practice_drills`), plus the two
closure-sweep items the warrior filed: **W-15** (the Forever Rend provider read)
and **W-21** (the Sunder/Rend/Hamstring HUD mirror).

---

## 1. What the sim says about the offhand (the citations)

Everything below was fetched **2026-10-19** from the wowsims master branches
(`raw.githubusercontent.com/wowsims/<branch>/master/...`). CONFIRMED = the source
said it, quoted here.

### 1.1 The queue lifts the dual-wield miss penalty

`wowsims/tbc-new sim/warrior/heroic_strike_cleave.go`, the comment on
`consumeQueue`:

> "The queue lifts the dual-wield miss penalty, so it ends after the hit roll.
> It ends before the damage is dealt: an extra main-hand swing procced by that
> damage must not become another queued Heroic Strike or Cleave."

and the queue aura itself — **the same code in all four classic-line sims**
(classic, sod, tbc-new, forever; `sim/warrior/heroic_strike_cleave.go`,
`makeQueueSpellsAndAura`):

```go
OnGain:   warrior.PseudoStats.DisableDWMissPenalty = true
OnExpire: warrior.PseudoStats.DisableDWMissPenalty = false
```

The core flag's own comment, `wowsims/classic sim/core/stats/stats.go:425`:

> `DisableDWMissPenalty bool // Used by Heroic Strike and Cleave`

### 1.2 The penalty it lifts: +19 %, over a 5 % white base

`wowsims/classic` (and sod, tbc-new, forever, wotlk) `sim/core/spell_outcome.go`:

```go
missChance := attackTable.BaseMissChance - spell.PhysicalHitChance(attackTable)
if spell.Unit.AutoAttacks.IsDualWielding && !spell.Unit.PseudoStats.DisableDWMissPenalty {
    missChance += 0.19
}
```

The white attack's own base miss chance, `wowsims/classic sim/core/target.go:312`:

```go
table.BaseMissChance = 0.05 + (targetDefense-weaponSkill)*0.002
```

**5 % + 19 % = 24 %** — the figure the operator quoted, and the number the drill
cites (`st.warrior_guide.DW_MISS_PENALTY = 0.19`,
`st.warrior_guide.WHITE_MISS_BASE = 0.05`).

### 1.3 WHEN the queue is up

* The aura expires when the queued auto spell fires — **the mainhand swing**,
  because the queue replaces it: `wowsims/classic
  sim/warrior/dps_warrior/dps_warrior.go:54` (`ReplaceMHSwing: war.TryHSOrCleave`)
  and `sim/core/attack.go`'s `swing()` ("Allow MH swing to be overridden for
  abilities like Heroic Strike").
* The activation is delayed by the sim's own realism ICD
  (`sim/warrior/warrior.go`: `Duration: time.Millisecond * time.Duration(
  warrior.WarriorInputs.QueueDelay)`), whose UI default is **250 ms**:
  `wowsims/classic ui/core/components/inputs/warrior_inputs.ts:21-27`
  ("HS/Cleave Queue Delay (ms)" — *"to delay re-queueing Heroic Strike/Cleave in
  order to simulate real reaction time and game delay"*); the same 250 ms
  default in `wowsims/sod` (same file), `wowsims/tbc-new`
  (`ui/specs/warrior/dps/presets.ts:238`) and `wowsims/forever`
  (`ui/specs/warrior/dps/presets.ts:145`).

### 1.4 What the sim does NOT state (never invented here)

* **The client's own lift timing.** The 250 ms above is the sim's *reaction-time
  model*, not a client fact: the live client queues the ability on the press.
  The in-client window is **UNCONFIRMED IN-CLIENT** (the operator's session owes
  it), so the drill grades the swing ORDER, not a reaction lag — the queue delay
  is exposed as a cited constant (`HS_QUEUE_DELAY_SECONDS = 0.25`) and is
  deliberately NOT used as a window edge.
* **The operator's "the normal 7 % spell cap."** The sim keeps the offhand's own
  white base miss chance (5 % at equal skill) when the penalty is disabled — it
  never swaps in a spell cap. The 7 % is the operator's in-client figure and is
  carried as such (in the drill's comment), **never as a sim number**.

---

## 2. The drill: `warrior_hs_queue` ("The queue window")

### 2.1 The window it grades

The offhand's next swing has to land **while the queue is up** — after the press
and before the mainhand swing that fires the queued ability. The press window
is therefore the gap between the mainhand's **last** swing and the offhand's
**next** swing:

| the press | what happens | grade |
|---|---|---|
| before the mainhand's swing | the ability fires at that swing, before the offhand's swing — the offhand swing falls outside the ability ("too early") | **F** |
| after the offhand's swing | the offhand already swung and took the penalty ("too late") | **F** |
| inside the gap | the offhand's swing lands inside the ability and the dual-wield penalty is lifted for it | S/A/B/C/D by the margin |

The margin is the room on the **tighter** of the two sides of that gap:
`min(since the mainhand's last swing, until the offhand's next swing)`.

The readings are the addon's **own swing data** — the client data the sim is
silent about:

| reading | source | where |
|---|---|---|
| `swing_remaining` | the mainhand bar's next landing (`ends_at`) | the gather (already shipped) |
| `speed` | the mainhand's weapon speed (the cycle length) | the gather (already shipped) |
| `offhand_swing_remaining` | the **offhand** bar's next landing | the gather (**new**) |
| `dual_wielding` | true only when the player really has an offhand weapon | the gather (**new**) |

### 2.2 The bands (DESIGN, not sim numbers)

`st.warrior_guide.HS_QUEUE_BANDS` — min thresholds, because a bigger margin is
a better press (unlike the mis-pick-count tables, whose value grows with the
mistake):

| band | margin on the tighter side |
|---|---|
| S | ≥ 250 ms |
| A | ≥ 150 ms |
| B | ≥ 80 ms |
| C | ≥ 20 ms |
| D | inside the window, a hair from an edge |
| F | the press missed the window (too early / too late) |

### 2.3 The surfaces

* `ST.WARRIOR.practice_drills` — the fifth entry, `warrior_hs_queue`, with the
  sim citation in a `source` field (the engine reads only `key`/`label`; the
  extra field is additive).
* The grade function lives in `classes/warrior.lua` (the class's own drill
  list) and delegates to the pure helper
  `st.warrior_guide.hs_queue_grade(inputs)`; the band table is
  `st.warrior_guide.hs_queue_band(margin)`.
* Only a **Heroic Strike / Cleave** press is this drill's decision; any other
  press answers nil (the engine grades it unknown, never a wrong action).
* **Opt-in**: the drill is opt-in through the class's own drill list (the
  shared engine's panel reads the class's list; nothing is force-enabled and no
  default-visible change rides).

---

## 3. W-15 — the Forever Rend provider read (landed)

`classes/warrior.lua`, in the gather (the read the options pass filed at
`option_tables.lua:3817-3844` → `bench/buildout_options_pass_2026-10-19.md` §4.1):

```lua
if inputs.sod == true and self.warrior_has_sod_rend_rune == true then
    inputs.rend_upkeep_enabled = true
elseif is_forever_guide and db.guide_forever_rend_upkeep == true then
    inputs.rend_upkeep_enabled = true
else
    inputs.rend_upkeep_enabled = nil
end
```

* The read is `== true` → **nil and false both leave the rule dormant** (the
  options suite's contract cannot rot silently).
* The key ships **no default** (`config_presets.lua:1255-1269`: nil stays off),
  so the rule stays dormant on the Forever client until the player chooses it.
* The branch is **family-scoped**: the Forever toggle never arms the rule on
  another family (pinned).
* The stale comment ("the Forever toggle lives with the options lane (OUT) …")
  is gone — the key ships, only the read was missing
  (`bench/buildout_options_pass_2026-10-19.md` §4.5).

---

## 4. W-21 — the Sunder/Rend/Hamstring HUD mirror (landed)

### 4.1 The gap

The guide slots for Sunder Armor / Rend / Hamstring already ship; the HUD row
did not mirror them. The per-family gap was exactly one slot: the **TBC row**
had no Sunder mirror (the TBC guide set carries `sunder`, the TBC HUD set did
not — the old comment called it "guide-only until the HUD lane mirrors it").
The Rend slot (the arms/SoD rows) and the Hamstring slot (the Era/Forever/base
rows) were already in their rows, but as ordinary rotational slots.

### 4.2 What shipped

* The **TBC HUD row** gains the Sunder mirror: `{ op, execute, slam, hs, bt, ww,
  sunder, trinket1, trinket2 }` (9 slots). The load-time TBC set matches.
* The three maintenance slots are now **display-only mirrors**:
  * Sunder and Rend have no cooldown of their own to ride → the provider
    returns before the cooldown read (the shaman's maintain-mirror shape);
  * Hamstring keeps the rotational GCD path (the druid Claw shape);
  * each hides unless its `hud_show_<key>` toggle reads **exactly true**
    (nil = off — the HUD treats a nil toggle as wanted, so the provider-level
    hide is the no-default-visible gate; the druid Claw shape).
* The slot descriptors are the module's own (no new id): Sunder **7386** (rank
  1, the TBC rank 25225 rides the same `sunder_armor_ids` table the guide
  uses), Rend **772**, Hamstring **7373** (the TBC rank **25212** rides the same
  `hamstring_ids` table).
  **CORRECTED 2026-10-20** (desk `corpus-corrections`): this line used to say
  "the TBC rank **18499** rides the same `hamstring_ids` table" — **18499 is
  Berserker Rage**, not a Hamstring, and the **TBC Hamstring is 25212**
  (`wowsims/classic sim/warrior/berserker_rage.go:14` names 18499 Berserker
  Rage; the tbc-new fury APL's i=19 casts 25212 = Hamstring). Evidence:
  `bench/warrior_apl_utility_build_2026-10-20.md` §1/§4;
  `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **W1**/**W4**.

### 4.3 The visibility note (for the operator / the options lane)

`config_presets.lua` ships `hud_show_rend = true`, `hud_show_hamstring = true`
and `hud_show_sunder = true` (the "union of the family sets ships on" rule).
The mirror gate reads `== true`, so:

* in the **offline sandbox** (no key) the mirrors are hidden and the row keeps
  its geometry — the druid-Claw shape, pinned in `tests/hud_state.lua`;
* in the **live client** the Sunder mirror is therefore **visible by default on
  the TBC row** (the toggle ships on), i.e. one new icon there. If the
  operator wants the mirror off by default (the sweep's own pin wording: "the
  mirrors are provider-hidden by default"), the one-line change is
  `hud_show_sunder = false` in `config_presets.lua` — **the options lane's
  file, not this lane's**. The gate itself is already the nil-off shape.
* The Rend mirror drops the **GCD swipe** (the spec's "no cooldown to ride"
  shape), so the options widget's description ("Show the Rend icon (with its
  GCD swipe)") is now stale — **a one-line options-lane follow-up**
  (`option_tables.lua:4050`).

---

## 5. Verification

- **Harness**: `bash tests/run.sh` → **41 steps / 0 failed**,
  `luacheck .` → **2 warnings / 0 errors** (the standing floor; the two
  warnings are the pre-existing ones in `compat.lua:36` and `main.lua:81`, in
  files this lane never touched).
- **Suites**: `tests/warrior_state.lua` **1182 checks PASS**,
  `tests/warrior_guide_state.lua` **1728 checks PASS**,
  `tests/hud_state.lua` **682 checks PASS** (the warrior census only: the
  suite's count grew by exactly the seven new warrior pins, so no other
  class's census moved).
- **Line endings preserved**: `classes/warrior.lua` + `warrior_guide.lua` CRLF,
  the three suites LF.
- **Mutation proofs**: **30 / 30 killed, 0 void** on a
  `/tmp/opencode/mut_warrior` copy (`/tmp/opencode/mut_warrior.py`): the F test
  (`>=` → `>` and inverted), both sides of the margin, the min/max, the three
  unknown-reading guards, the dual-wielding gate, all four band thresholds, the
  three cited numbers, the drill key, the press filter, the delegation to the
  pure verdict, every new gather reading (and the mainhand speed), the W-15
  read (dropped / not `== true` / not family-scoped), the HUD mirror gate
  (removed / `~= false`), the Sunder mirror in both HUD sets, and the drill's
  presence in the class list. The copy is restored byte-identically after the
  run.
- **Scope**: only the five lane files changed. The other files with fresh
  timestamps in the tree belong to the parallel sibling lanes (shaman, druid,
  options, practice, main, the docs) — this lane touched none of them.
- **Close note (crossfire)**: the harness was **41 steps / 0 failed** when this
  lane's last edit landed. Afterwards the parallel class lanes landed the HU-8
  change ("hold is a decision") in the shared engine and their own
  scenario-step pins went red (`tests/shaman_guide_state`,
  `tests/hunter_guide_state`, earlier `tests/rogue_state` /
  `tests/paladin_state`), with the luacheck floor moving 2 → 3 (the new
  warning is in `tests/paladin_state.lua:2890`, the paladin lane's file). **No
  warrior file is in any failing step**: `warrior_state` 1182 ✓,
  `warrior_guide_state` 1728 ✓, `hud_state` 682 ✓, `guide_contract` 1042 ✓,
  `practice_state` 1478 ✓, and luacheck **0/0** on the five lane files.

---

## 6. Filed for other lanes (not this lane's scope)

| # | Item | Where | Why |
|---|---|---|---|
| F-1 | `hud_show_sunder = false` (if the operator wants the TBC mirror off by default) | `config_presets.lua` | the options lane's file; the mirror gate is already nil-off |
| F-2 | the stale widget description ("Show the Rend icon (with its GCD swipe)") | `option_tables.lua:4050` | the Rend mirror no longer rides the GCD swipe |
| F-3 | the shared registration of the new drill + the per-class practice map | `practice.lua`, `practice_ui.lua` | the shared engine owns the registration; the class list wins over the fallback map, so nothing is needed for the drill to appear |
| F-4 | the in-client confirmation of the queue window (and the "7 % spell cap") | the operator's session | UNCONFIRMED IN-CLIENT by design: the sim's 250 ms is its own reaction model |

## 7. UNCONFIRMED carried by this lane

| Item | Where | Why |
|---|---|---|
| the client's own queue-lift timing | the drill's window | the sim's 250 ms is a reaction-time model, not a client fact |
| the "7 % spell cap" for the lifted offhand swing | the drill's comment | the sim keeps the offhand's own white base chance (5 % at equal skill); the 7 % is the operator's in-client figure |
| the HUD mirror's default visibility on TBC | `hud_show_sunder = true` | the options lane's shipped default; the gate is nil-off, the shipped key is on |
