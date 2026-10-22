# bench/druid_drills_2026-10-19.md — the druid practice surface + the class-side feature closures

Desk: `druid-drills`. Date: 2026-10-19. Scope: `classes/druid.lua` +
`tests/druid_state.lua` only (the spec: `bench/class_features_drills_2026-10-19.md`
§2.5). No other file touched, no git, no lint-config change.

Validation owner: **orchestrator**.

---

## 0. What shipped

The shared engine already implements the class contract (`practice.lua:3232-3250`:
`ST.<CLASS>.practice_scenario_step(self, ctx)`, `ST.<CLASS>.practice_drills` with
`key` / `label` / `grade`), and `practice_ui.lua` already calls both
(`practice_ui.lua:4285` the scenario step, `:4520` the drill grade). The druid now
answers that contract:

| Field | Where | Notes |
|---|---|---|
| `ST.DRUID.practice_rotation` | `classes/druid.lua:2647` | the sim priority order per family, one entry per priority slot, every entry citing its sim file |
| `ST.DRUID.practice_rotation_for(family)` | `classes/druid.lua:2776` | one family's slice (the bear chain is its own slice, family `BEAR`) |
| `ST.DRUID.practice_rotation_family()` | `classes/druid.lua:2793` | the rotation family the running client uses (`ERA`, `SOD`, `TBC`, `WRATH`, `FOREVER`) |
| `ST.DRUID.practice_scenario_step(self, ctx)` | `classes/druid.lua:2932` | the **guide engine's own answer** for the current state → `{ action, reason }`, nil = undecidable |
| `ST.DRUID.practice_drills` | `classes/druid.lua:3053` | the audited target set: `druid_finisher_order`, `druid_powershift_rework`, `druid_roar_upkeep`, `druid_bite_execute` |

### The ctx contract (the engine's writer)

The engine builds the ctx itself (`practice_ui.lua:4037` `scenario_context`):
`{ now, last_action, resources, cooldowns }`, where `resources` carries the resource
numbers the class's gathered inputs expose (energy / rage / combo_points / …) and
`cooldowns` carries the **stripped** base names of the gathered `*_remaining` fields
(`sr_remaining` → `sr`). The class therefore:

1. **gathers its own state** (`ST.DRUID.gather_guide_inputs`) — the engine's own rule
   ("a class that needs more gathers it itself"): the ctx never carries the Omen
   proc, the execute clock, the ready flags or the family;
2. **lets the ctx win** over the gather, so a caller that writes a simulated state
   gets exactly that state;
3. accepts the engine's stripped cooldown names as well as the guide's own names.

The reader (`druid_ctx_value`) is nil-safe: a missing value is nil (unknown) and
never a guess. The merge (`druid_state_inputs`) is one reused table per direction —
no per-step allocation.

### The scenario step

It runs the **shipped** `st.druid_guide.evaluate`, so the scenario and the Next
Action Guide can never disagree (the same decision model the guide shows). A hold
(`TIGER'S FURY`, `BERSERK`, `SAVAGE ROAR`, `FAERIE FIRE`, `SHIFTING POWER`, `RIDE`)
answers with the spell's key (`tigers_fury`, …), so a hold and an action are the
same shape for the engine. The reason is a short phrase built from the state the
engine wrote, plus the engine rule id from the rotation table (e.g.
`5 combo points, Rip expired (W5)`).

Retail: the guide is inert there (its own short-circuit), so the step answers nil
and the scenario is never offered (the audit's §4.6 family-gating rule).

---

## 1. The powershift drill, re-sourced (the operator ruling)

The audit's note (`bench/class_features_drills_2026-10-19.md` §2.5 (B)) is resolved
in the druid's own drill set: **`druid_powershift_rework` grades the sim's trigger,
not the addon's 20-energy rule.**

| Family | The sim's trigger | Source |
|---|---|---|
| TBC | **below 10 energy** the cat shifts | sim wowsims/tbc-new `sim/druid/feralcat/rotation.go` (the audit's §3 T-7: `<10 energy -> shift`) |
| ERA / SoD | shift when the energy **at the next tick** is still below the **builder cost** | sim wowsims/classic and wowsims/sod `sim/druid/feral/rotation.go`: `shiftNow` when `nextEnergy < cost` (the audit's §1 E-3 / §2 S-10) |
| Wrath | no shift basis (the Furor no longer refunds on a shift) | the audit's §4 "No powershifting on Wrath" |
| Forever | no shift basis (the APL has no shift rule) | the audit's §5 F-row |

The bands are the audit's [DESIGN] bands, measured against **that** line: below it
`S` (the shift belongs here), ≤10 above `A`, ≤20 `B`, ≤30 `C`, more `D` (the pool is
still high: a shift now would be wasted), a capped pool `F` (the shift was never
taken in time). The regen used for the next-tick reading is **10 energy/s** — the
sim's own energy-tick model (20 energy per 2 s tick, `core.EnergyPerTick` /
`core.EnergyTickDuration`, the model `druid_energy.lua` already freezes), not the
shipped drill's addon model.

Pins (the discriminating ones): TBC 15 energy → `A` (the 20-energy rule would have
said `S`), TBC 25 → `B`, TBC 45 → `D`, TBC 100 → `F`; ERA 30 → `S`, ERA 45 → `A`;
ERA 35 with a 1 s tick → `A` (the next-tick energy is what the sim reads); Wrath /
Forever → nil (no basis).

**Filed (not done here):** the shipped `druid_powershift` registry entry
(`practice.lua:2363`, bands at `practice.lua:2279-2286`, the `rule_energy = 20`
model at `:2276`) still grades the addon's own 20-energy rule. `practice.lua` is
**out of this lane's scope** (the sibling lane owns it) and §4.7 of the audit
forbids a build lane from changing an existing entry's grading. The owner should
either re-point that entry at the re-sourced rule or retire it in favour of
`druid_powershift_rework`; until then the drift stands and the new drill is the
sim-faithful one.

---

## 2. The class-side feature closures (the audit's §2.5 (A))

| Row | Verdict before | What this lane did | Status |
|---|---|---|---|
| **DU-13** FF omen-fishing | DEGRADED (dormant: `omen_icd_ready` had no probe) | the class now proves the Omen's internal cooldown: the Clearcasting proc buff (16870) is the witness — the proc up → the ICD is not ready (false); the proc gone for at least as long as the last proc lasted → the lockout has passed (true); before the first proc → nil (unknown). The Forever `omenFish` rule (`druid_guide.lua` F6c) can now fire in game instead of staying dormant. | **CLOSED (class side)** — see the UNCONFIRMED note below |
| **DU-22** W1 latency term | DEGRADED (`inputs.latency` written nil; the line degraded to the GCD alone) | the gather now reads main.lua's **raw** world latency (the sim's own `Latency` setting; the addon's calibrated reading is a display-alignment correction and is deliberately not applied). A client that has not measured reads nil and the line degrades exactly as before. | **CLOSED (class side)** — the W1 leeway is now `max(gcd_remaining, latency)` as the sim computes it |
| **DU-15** trick windows | MISSING (the inputs are reserved, no rule reads them) | the class-side inputs were already wired (`tick_remaining` from the tracker's anchor, the live TBC Mangle cost). The **rules** live in `druid_guide.lua`, which is out of this lane's scope, and they still need the live bite / shred costs (neither spell has a rank table in this module, so a cost probe on them would read an unconfirmed id). | **FILED** (engine side + the cost probe) |
| **DU-16** powershift (the in-game SHIFT prompt) | MISSING (the SHIFT branch was removed; `can_powershift = nil`) | the **practice** surface is closed (the re-sourced drill above). The in-game prompt stays blocked: the basis is the Furor talent, whose id / tab / index has **no source** in this codebase (main.lua's `talent_positions` covers Wrath only), and a name probe (`GetSpellInfo("Furor")`) is not a knowledge proof — the client answers a name for any spell it ships. The sim's item check (`HasItemEquipped(8345)`, the Wolfshead) is sim-confirmed but unread: an item probe alone cannot prove the energy refund, and an unread input would be dead code. | **FILED** (with the exact blocker) |
| **DU-18** Claw builder / **DU-21** position input | DEGRADED / MISSING | no honest probe exists: `IsSpellUsable` answers usability, never facing, and the sim's `CannotShredTarget` has no WoW API counterpart. The slot stays declared; `can_shred` stays nil. | **FILED** (no client source) |
| **DU-11** Rake DPE check | MISSING | needs AP / DPE and proc inputs the class does not gather (the sim's `rakeDpeCheck` + the glyph extension). | **FILED** (no inputs) |
| **DU-12** clipRoar glyph extension | DEGRADED | needs the Glyph-of-Shred / item-set inputs (the sim's `MinRoarOffset` 12/14/25/27/34 s + `RipLeeway` 4 s). The shipped cover-to-end clip (S3b) stays as it is. | **FILED** (no inputs) |
| **DU-14** pooling as a cast-gate | MISSING | engine side (`pendingPool` → `floatingEnergy`); the class already exposes the tick phase. | **FILED** (engine side) |
| **DU-20** Faerie Fire manual maintain | MISSING | manual by stance (the documented stance); the Wrath/Forever Omen-fish rules are live now (DU-13). | **FILED** (documented stance) |
| **DU-23** TBC RipCP user-config | DEGRADED | the engine input (`inputs.rip_min_cp`) and the gather are live; the **option widget** is `option_tables.lua` + `config_presets.lua` (out of scope). | **FILED** (widget) |
| **DU-24** consumables / mana layer | MISSING | no mana input and no guide slot for Tea / potion / Innervate. | **FILED** (no inputs) |
| **DU-25** bearweave / flowerweave / snekweave / powerbear | MISSING | the documented scope cut (a bear timer / rage input does not exist). | **FILED** (documented cut) |

**UNCONFIRMED — the Omen-ICD assumption (DU-13).** The client has no internal
cooldown query. The class treats the Clearcasting proc buff's own duration as the
witness: the proc is up → the Omen cannot proc again (proven); the proc has been
gone for at least as long as the last proc lasted → the lockout window has passed
(derived). The assumption that the Omen's ICD and its proc buff share one window is
**UNCONFIRMED in-client**; the failure mode is bounded (a fish spent at most one
ICD early, and only when nothing else is affordable after a GCD of regen). Before
the first proc of a session the answer is nil, so the fish stays dormant.

**Behaviour note (not a new toggle).** DU-13 and DU-22 make two shipped rules
reachable that were dormant/degraded: the Forever `omenFish` hold can now appear
(the guide's hold overlay), and the Wrath Tiger's Fury line now includes the
latency term (it can only fire *later*, never earlier). Both are the sim's own
behaviour, and both are the audited closures the brief asked for.

---

## 3. The drill set (the audit's §2.5 (C))

| Drill | Skill | The state it reads | The bands |
|---|---|---|---|
| `druid_finisher_order` | rotation priority order | the whole state (the guide's answer) + the player's pick when the ctx carries one | the audit's window over the last ten picks: no mis-pick `S`, one `A`, two `B`, three `C`, five `D`, more `F` (the ledger lives in the engine's session state, `ctx.state`) |
| `druid_powershift_rework` | situational decision | energy, the builder cost, the tick phase, the regen | the sim's trigger; the audit's bands (§1 above) |
| `druid_roar_upkeep` | cooldown / rotation window | `sr_remaining`, `sr_expired_seconds` (the class's own tracker), `combo_points`, `time_to_die` | the clip `S`; an on-time repair `S`; ≤2 s late `A`; ≤4 s `B`; a lapsed upkeep `C`; a lapsed upkeep that burned a builder `D`; never maintained `F` |
| `druid_bite_execute` | transition / opener | `time_to_die`, `rip_remaining`, `sr_remaining`, `combo_points` | in the window with both minima `S`; one minimum short by 2 s `A`, 4 s `B`; just outside the window `C`; a Bite the sim would never have cast (mid-fight, or a badly broken minimum) `D`; no Bite in the window `F` |

**The moment model.** The engine's drill press grades the *moment*
(`practice_ui.lua:4513` `drill_list_press` → `scenario_context(now, nil)`), so
every drill reads the current state (the class's own gather + the ctx) and judges
it; the bands above are moment bands, not event bands. Two consequences, both
documented in the code:

* `druid_finisher_order` needs the player's pick (the priority order is a sequence
  skill). The engine's drill press carries none, so the drill answers nil there —
  the rotation scenario (the engine's own `rotation_run_decide`) grades the
  sequence. When a ctx carries a pick, the drill compares it with the guide's answer
  and keeps the audit's ten-pick window.
* `druid_roar_upkeep` treats a cast while the Roar is still up (outside the sim's
  cover-to-end clip) as *not an upkeep event* → nil, because the sim refreshes the
  Roar on expiry and would have waited.

**The families.** The Roar drill answers nil off the SoD / Wrath sims (the runeless
Era and the TBC sims have no Roar rule); the execute drill answers nil off the Era /
SoD sims (the sim's `canBite` is commented out there). The shift drill answers nil
off Wrath / Forever (no shift basis). Unknown-hides, never a guess.

**The class-side state the drills need** (new gather fields, the guide does not
read them): `sr_expired_seconds` (how long the Roar has been down — the class
remembers the aura's last expiry) and `sr_seen` (true once the Roar was up this
fight, false when the fight is on and the scan never saw it, nil when unknown).
Both reset with the fight (`on_combat_exit`).

---

## 4. Validation

* `tests/druid_state.lua` **903 checks PASS** (was 631; +272 pins). The sandbox now
  loads `druid_guide.lua` as the TOCs order it, so the scenario step and the
  priority drill run the **shipped** engine, not a copy of it.
* `tests/druid_guide_state.lua` **95 462 checks PASS** (unchanged), `druid_energy_state`
  unchanged, `guide_contract` unchanged, `smoke` unchanged.
* **Full harness: 41 steps, 0 failed.** luacheck **2 warnings / 0 errors** (the tree
  floor; both touched files 0/0).
* **13/13 mutation proofs killed** on `/tmp/opencode/mut_druid` copies (the copy is
  restored byte-identically after every run; the baseline is green):
  M1 the TBC shift line 10 → 20 · M2 the cost trigger → the old 20-energy rule ·
  M3 the scenario's action → a constant · M4 the priority window's bands ·
  M5 the Omen ICD → always ready · M6 the latency → the calibrated reading ·
  M7 the Roar lateness bands · M8 the Bite minima 4 → 2 · M9 the Wrath order
  (Mangle / Rake swapped) · M10 the Roar clip removed · M11 the class's own gather
  removed from the state · M12 the engine's stripped cooldown names ignored ·
  M13 the state merge dropping a proven `false` (the SoD S2 branch reads
  `tf_ready == false`, so a dropped false silently kills the Berserk call).

---

## 5. Notes for the other lanes (no action required, listed for the record)

1. **`druid_guide.lua`'s header** still says the Omen ICD "has no honest client
   probe, so no gather writes it" and that F6c "stays dormant in game". Both are
   now stale (the class writes the probe). The guide's owner may re-word the
   comment; no behaviour depends on it.
2. **`tests/druid_guide_state.lua`'s label** "gather: no latency probe -> nil" is now
   stale in its wording: the value pin still holds (that sandbox has no latency
   table, so the input stays nil), but the reason is now "the client has not
   measured". The guide-suite owner may re-label it.
3. **The wiring check** now finds a call site for `ST.DRUID.practice_rotation_for` and
   `ST.DRUID.practice_rotation_family` (the scenario step calls both), so no dead
   hook is reported for the druid.
4. **The engine's rotation-table consumer** does not exist yet: `practice.lua` /
   `practice_ui.lua` read the class's `practice_scenario_step` and `practice_drills`
   but not `practice_rotation`. The table is a flat array whose entries carry
   `family` ("ERA" / "SOD" / "TBC" / "WRATH" / "FOREVER" / "BEAR"), `action`,
   `label`, `rule`, `note` and `source`; the engine can filter on `entry.family`
   and use `ST.DRUID.practice_rotation_for(family)` for a slice.

## 6. What was NOT done (out of scope, stated)

`practice.lua`, `practice_ui.lua`, `practice_progress*.lua`, `option_tables.lua`,
`config_presets.lua`, `config.lua`, `druid_guide.lua`, `druid_energy.lua`,
`compat.lua`, `main.lua`, `hud.lua`, `bars.lua`, `run.sh`, the TOCs, the versions,
the README, the CHANGELOG and the docs were not touched. No git command was run.
