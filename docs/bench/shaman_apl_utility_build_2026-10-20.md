# Shaman APL utility layer — build report (2026-10-20)

Desk: `shaman-apl`. Scope: `classes/shaman.lua`, `shaman_guide.lua`,
`tests/shaman_state.lua`, `tests/shaman_guide_state.lua` (+ one mechanical
re-cut of `tests/guide_contract.lua`'s shaman slot-count pins — the HU-10
precedent: a count pin must match the shipped slot set, not a stale one).
No git, no lint-config change, no TOC/version/option change, no other class
touched.

Source of truth: `bench/rotation_gap_vs_apl_2026-10-20.md` §5 (the shaman),
**re-verified against the fetched APL files** (the gap analysis was not
trusted on its own — the hunter lane found five errors in its own section, and
this one had five as well, see §3):

| family | file fetched (2026-10-20, master) |
|---|---|
| ERA | `wowsims/classic` `ui/enhancement_shaman/apls/default.apl.json` |
| SoD | `wowsims/sod` `ui/enhancement_shaman/apls/phase_6.apl.json` |
| TBC | `wowsims/tbc-new` `ui/specs/shaman/enhancement/apls/default.apl.json` |
| FOREVER | `wowsims/forever` `ui/specs/shaman/enhancement/apls/default.apl.json` |
| WRATH | `wowsims/wotlk` `ui/enhancement_shaman/apls/default_wf.apl.json` |

plus the sims' own ability files (`sim/shaman/*.go`) and the Forever spell
data (`sim/shaman/spell_data_auto_gen.go`).

---

## 1. What landed

### 1.1 Four new rotation lines (the utility layer)

Every line carries the same shape: `action`, `label`, `spell_id` + `spell_name`
(the era id and the TBC name — TBC resolves by NAME, bench/lessons.md), the
per-family id map `spell_ids`, `families`, `source` (APL file + index + the sim
citation), and the HU-13 two flags.

| # | action | families | ids (per family) | APL position | read | live | engine |
|---|---|---|---|---|---|---|---|
| 3 | `bloodlust` | WRATH | WRATH 2825 | `default_wf.apl.json` i=1, i=2 | `api.GetSpellCooldown` (known-gated) | true | true |
| 8 | `strength_of_earth` | ERA, TBC, FOREVER | ERA 10442 · TBC 25528 · FOREVER 25361 | `default.apl.json` i=0 (Era) · `default.apl.json` i=3 group `Totems` row 3 (TBC) · `default.apl.json` i=4 (Forever) | the client's **EARTH** totem slot clock (`api.GetTotemInfo`, slot 2) | true | true |
| 11 | `mana_spring` | TBC | TBC 25570 | `default.apl.json` i=3 group `Totems` row 4 | the client's **WATER** totem slot clock (slot 3) | true | true |
| 19 | `frostshock` | TBC | TBC 25464 | `default.apl.json` i=6 group `Shocks` row 2 (the ALTERNATIVE `Filler Shock` choice) | `api.GetSpellCooldown` (known-gated) | true | true |

The id citations:

* `strength_of_earth` — `wowsims/classic sim/shaman/earth_totems.go`:
  `StrengthOfEarthTotemSpellId = {0, 8075, 8160, 8161, 10442, 25361}`;
  `wowsims/tbc-new sim/shaman/totems.go`:
  `strengthOfEarthTotemRank = spellData.StrengthOfEarthTotem.BySpellID(25528)`;
  `wowsims/forever sim/shaman/spell_data_auto_gen.go`:
  `StrengthOfEarthTotem: spelldata.Ranked(8075, 8160, 8161, 10442, 25361)`.
  (25361 is therefore the **r5** id on every client — which is why the SoD
  pre-pull casts 25361 r5.)
* `mana_spring` — `wowsims/tbc-new sim/shaman/totems.go`:
  `manaSpringTotemRank = spellData.ManaSpringTotem.BySpellID(25570)`;
  `wowsims/classic sim/shaman/water_totems.go`:
  `ManaSpringTotemSpellId = {0, 5675, 10495, 10496, 10497}` (the SoD/Forever
  pre-pull row's 10497 = r4).
* `frostshock` — `wowsims/tbc-new sim/shaman/shocks.go`:
  `frostShockRank = spellData.FrostShock.BySpellID(25464)`. (The WotLK Frost
  Shock is **49236** — `wowsims/wotlk sim/shaman/shocks.go:115` — and no WotLK
  APL carries it.)
* `bloodlust` — `wowsims/wotlk sim/shaman/bloodlust.go:7-9`:
  `BloodlustActionID() = core.ActionID{SpellID: 2825}`.

### 1.2 The engine arms (shaman_guide.lua)

| rule | arm | family gate | gate condition |
|---|---|---|---|
| 3b | `bloodlust` | WRATH | the cooldown is ready (nil = unknown = silent) |
| 8a | `strength_of_earth` | ERA (Era-base only), TBC, FOREVER | the earth-slot clock at or under the family's window (ERA/FOREVER 0 s = the empty slot, TBC 5 s = the refresh) |
| 8d | `mana_spring` | TBC | the water-slot clock at or under 5 s (the refresh) |
| 13b | `frostshock` | TBC | the cooldown is ready **and** the player stated the APL's `Filler Shock` choice (`FROST`) |

* The Strength of Earth helper (`get_strength_of_earth_due`) reads the
  **slot** clock, not the buff clock: the client wrapper `api.GetTotemInfo`
  gives the tri-state the tree's other totem readers use (0 = the slot is
  affirmatively empty, the seconds left while a totem is up, nil = unknown).
  An unreadable slot never prompts (unknown-hides).
* The SoD build is kept silent on the ERA token: the SoD APL has **no**
  Strength of Earth rotation row (its Strength of Earth is a pre-pull row), so
  the MW-rune latch keeps rule 8a Era-base only.
* Rule 13b and rules 14/17 are mutually exclusive: the TBC `Shocks` group
  picks **one** filler (the `Filler Shock` valueVariable defaults to Earth
  Shock), so with the Frost Shock choice stated the Earth Shock filler answers
  nothing at all. The live gather never states a choice, so the APL's default
  stands on every live client and the arm is dark until the practice ctx says
  otherwise (`ctx.resources.filler_shock = "FROST"`).

### 1.3 The flags (HU-13, two flags)

* `live` = the line's **read** exists and the line can be evaluated.
* `engine` = the frozen engine has an **arm** that can ask for it.

Both flags are now declared on **every** row, and the one honest flip the
convention forces: **`chainlightning` is `live = false, engine = true`**. The
Chain Lightning rule (13) and its slot exist, but the enemy-count read does
not (the gather feeds `target_count = nil` — the sensor is filed), so the line
can never be evaluated live. It now names the read it waits for in `needs`.
The old pin ("no rotation line without a guide slot claims to be live") was
re-cut to the two-flag invariant: *every line the engine can play names a
declared guide slot*, and *every live line names one too*.

### 1.4 The pre-pull table (HU-12)

`ST.SHAMAN.PRACTICE_PREPULLS` (the hunter's shape: `action`, `label`, `spell`,
`at`, `source`), one list per family, the offsets taken from the APLs' own
`doAtValue`:

| family | rows (action: spell @ offset) |
|---|---|
| ERA | strength_of_earth 10442 @-6 · wftotem 10614 @-4.5 · goa 10627 @-3 · searing 10438 @-1.5 |
| SOD | lightningshield 10432 @-10 · mana_spring 10497 @-8.25 · goa 25359 @-6.75 · strength_of_earth 25361 @-5 · searing 10438 @-2.75 · blood_fury 20572 @-1.25 |
| TBC | twist 25587 @-8 · strength_of_earth 25528 @-5 · mana_spring 25570 @-4 · firenova 25537 @-3 · goa 25359 @-2 · drums 35476 @-1 |
| FOREVER | goa 25359 @-8 · flametongue 16387 @-7 · strength_of_earth 25361 @-6 · mana_spring 10497 @-5 |
| WRATH | coe 66842 @-3 |

The consumable rows (the potions, the drum item, the SoD item/activateAura
rows) are not rotation decisions and are not listed.

### 1.5 The guide slots

Four new slots (the guide's eighteenth → twenty-second): `bloodlust`,
`strength_of_earth`, `mana_spring`, `frostshock`. No swipe on any of them (a
persistent totem has no window to ride; the two cooldowns ride the
client-reported length). The Strength of Earth / Mana Spring / Frost Shock
icons re-point by NAME at `post_init` (the TBC ids are the TBC client's own,
so the shipped era id would leave a blank icon there) — the same convention as
the Lightning Shield and Searing Totem maintain slots.

The guide frame stacks its icons (one fades in at a time), so twenty-two
slots do not overflow it. The **practice panel's** scenario buttons do grow
by four (they are built from the guide slot vocabulary and the strip grows
with the button lines — `practice_ui.lua:185-195`); that is a cosmetic
follow-up for the practice_ui lane, not a cut-off row.

---

## 2. Corrections to the gap analysis (§5 of `bench/rotation_gap_vs_apl_2026-10-20.md`)

The desk's shaman section had **five** errors. Each was re-verified against
the fetched APL and the sims' own data before the build.

**C1 — "Nature's Wrath" (17364) is NOT a separate line. (This is the headline
correction, and the brief's own premise was built on it.)**
The Era APL's i=4 row casts `17364` rank 1 — and **17364 is Stormstrike**:
`wowsims/classic sim/shaman/stormstrike.go:20` (`ActionID{SpellID: 17364}`),
the tree's own `WEAVE_STORMSTRIKE_SPELL_ID = 17364` (classes/shaman.lua:98),
`bench/verify_bank.md` ("Stormstrike nature-vuln debuff (target) | 17364 |
CONFIRMED, 12 s, +20 % nature damage taken") and the vendored
`Libs/LibClassicDurations/classAbilities.lua:754` (`Spell( 17364, { duration =
12 }) -- Stormstrike`). No fetched wowsims shaman sim has a "Nature's Wrath"
ability at all (no `nature_wrath.go` in classic/sod/tbc-new/forever/wotlk), and
the same id sits at the same priority slot in every other APL (SoD i=4, TBC
i=1, Forever i=8, Wrath i=6). → **no `nature_wrath` line was built**: the
APL's row is the Stormstrike row the table already carries, and a second line
on the same id would have taught the wrong thing. The brief's "no Nature's
Wrath line" is therefore *not* a gap.

**C2 — 29228 is Flame Shock rank 6, not the Flametongue Weapon.**
`wowsims/forever sim/shaman/spell_data_auto_gen.go`:
`FlameShock: spelldata.Ranked(8050, 8052, 8053, 10447, 10448, 29228)`. The
SoD APL's i=9 and the Forever APL's i=10 are Flame Shock rows. The bench's
`flametongue_weapon` line (29228 as a weapon imbue) is a mislabel. The
Flametongue **Totem** is `16387` (r4 —
`FlametongueTotem: Ranked(8227, 8249, 10526, 16387)`) and it is a **pre-pull**
row (the Forever APL's prepullActions i=1), so it lives in the pre-pull table.

**C3 — the WotLK shock ids.** `wowsims/wotlk sim/shaman/shocks.go`:
49231 = **Earth Shock** (nature school, line 52), 49233 = **Flame Shock**
(fire school, the dot, line 62), 49236 = **Frost Shock** (frost school, line
115). The bench's §5.2 called 49231 "Lightning Shock"; the WotLK APL's i=8
row (49231, unconditional) is the **Earth Shock** row and the WotLK APL has no
Lightning Shock row at all.

**C4 — the Rockbiter id.** The bench's `rockbiter` line cites 10497 as the
Rockbiter Weapon id; **10497 is Mana Spring Totem rank 4** (classic
`sim/shaman/water_totems.go`). Neither the SoD nor the Forever APL pre-pull
list carries a Rockbiter row, so there is no APL row to build (the bench's own
§5.4 already calls the Rockbiter/Frostbrand rows "not an APL line").

**C5 — the Windfury Totem id split (a filed note, not a change).** The
shipped `twist` row carries 8512 (the Windfury Totem **rank-1** id —
`wowsims/forever spell_data_auto_gen.go`: `WindfuryTotem: Ranked(8512, 10613,
10614)`), while the TBC APL's air-slot rows cast 25587 r5 (Windfury) and
25359 r3 (Grace of Air). 8512 is a real Windfury Totem id, so the row is not
wrong — it is the client's rank-1 fallback and the name-based icon/label
resolution covers the real rank. **Filed** for the orchestrator: the TBC APL's
own ranks (25587 / 25359) are the sim-exact ids if the row is ever re-cut.

---

## 3. Findings the gap analysis did not list

**F1 — the Lightning Shield maintain on SoD and Forever is a per-family gap.**
The SoD APL's i=8 casts 10432 r7 "if the aura is not active" and the Forever
APL's i=6 casts 10432 the same way — but the shipped `lightningshield` row is
WRATH-only (49281) and the engine's rule 11b is WRATH-gated. **Not built
here**: it is an extension of a *shipped* line (a family change plus a re-cut
of the WRATH pins), not one of the missing lines this lane was ordered to
add. The exact work is filed in §5.

**F2 — the practice panel's button vocabulary grows by four.** The scenario
buttons are built from the guide slot vocabulary; the strip grows with the
button lines (nothing is cut off), so this is cosmetic only.

---

## 4. Validation

* `lua5.1 tests/shaman_state.lua` — **PASS (764 checks)**.
* `lua5.1 tests/shaman_guide_state.lua` — **PASS (1535 checks)**.
* `lua5.1 tests/guide_contract.lua` — **PASS (1052 checks)** (the shaman slot
  count re-cut).
* `luacheck classes/shaman.lua shaman_guide.lua tests/shaman_state.lua
  tests/shaman_guide_state.lua` — **0 warnings / 0 errors**; the tree's floor
  (2 warnings, in `compat.lua` and `main.lua` — both untouched) is unchanged.
* `luac5.1 -p` — clean; `classes/shaman.lua` still carries **199 top-level
  locals** (Lua 5.1's 200-local ceiling — the new constants and the four new
  slots are table fields on `ST.SHAMAN`, not locals, for exactly this reason).
* **Mutation proofs: 14/14 killed** (`python3 /tmp/opencode/mutations_shaman_apl.py`,
  disposable copies under `/tmp/opencode`): the TBC refresh threshold, the
  Strength of Earth family gate, the **buff-up line still prompts on an
  unknown read** (the brief's named mutant), the Mana Spring and Bloodlust
  family gates, the Frost Shock / Earth Shock mutual exclusion, the Frost
  Shock choice token, the earth-slot and Bloodlust feeds, the per-family id
  map, the pre-pull offset, the Chain Lightning `live` flip, the practice ctx
  mapping and the guide slot.
* **Crossfire note:** while this lane ran, the hunter, warrior and druid lanes
  were editing `classes/hunter.lua`, `classes/warrior.lua` and
  `classes/druid.lua` in the same tree (`classes/warrior.lua` was mid-edit
  with Lua 5.1's "more than 200 local variables" error at 02:01, and the
  druid/hunter/warrior files changed again at 02:09). The full-harness run at
  that moment therefore showed the **warrior/hunter/druid/bars/hud/
  rotationtext/secret_guard/smoke** steps red — none of them in this lane's
  scope and none of them caused by it. The three suites this lane owns were
  green throughout, and the re-cut of `tests/guide_contract.lua` is the only
  file outside the lane's own scope that was touched. **The final full-harness
  run on a settled tree is the orchestrator's** (the tree was still moving when
  this desk finished).

---

## 5. Filed (not built here)

* **F1 — the Lightning Shield maintain on SoD and Forever.** Exact work: the
  `lightningshield` row's `families` → `{ "WRATH", "SOD", "FOREVER" }` with
  `spell_ids = { WRATH = 49281, SOD = 10432, FOREVER = 10432 }`; the gather's
  `lightningshield_due` gate → WRATH **or** FOREVER **or** (ERA + the MW-rune
  latch, i.e. the SoD build); the engine's rule 11b family gate to match; the
  row's `source` to cite `wowsims/sod .../phase_6.apl.json i=8` and
  `wowsims/forever .../default.apl.json i=6`. The read already exists (the
  player's own shield-aura walk matches the Lightning Shield by name), so no
  new client API is needed.
* **C5 — the TBC twist row's ranks** (25587 / 25359 instead of the rank-1
  8512 fallback).
* **The Frost Shock choice as an option.** The engine models the APL's
  `Filler Shock` variable as a frozen input (`filler_shock`), fed by nobody
  live. A real option (an options-panel widget, a saved variable) would need
  `option_tables.lua` + `config_presets.lua` — out of this lane's scope.
* **The Chain Lightning enemy-count sensor** (the `target_count` read the
  rule 13 needs) — unchanged from the tree's filed remainder.

---

## 6. Sources

* The five APL files and the sim ability files fetched on 2026-10-20 from
  `wowsims/{classic,sod,tbc-new,forever,wotlk}` (master) — the paths are in
  the table at the top of this file and inline in every row's `source`.
* `bench/rotation_gap_vs_apl_2026-10-20.md` §5 (the gap analysis this lane
  built from — with §3's corrections).
* `bench/lessons.md` (the TBC-name / Era-id rule) and `bench/verify_bank.md`
  (17364 = Stormstrike CONFIRMED).
* Offline only: nothing was loaded in a game client. Per `CAIRN.md` ("two
  proofs, two words") this desk has produced a *source-cited* build, not a
  verified-in-client one. **Validation owner: the orchestrator.**
