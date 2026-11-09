# bench/hunter_rotation_drills_2026-10-19.md — the hunter rotation scenario, the drill set and the class-side feature closures

Desk: `hunter-drills`. Date: 2026-10-19. Lane scope: `classes/hunter.lua`,
`hunter_guide.lua`, `hunter_ui.lua` (untouched), `tests/hunter_state.lua`,
`tests/hunter_guide_state.lua`. No other file touched, no git, no lint-config change.

Validation owner: **orchestrator**.

---

## 0. Sources read this session

| Source | What it contributed |
|---|---|
| `bench/class_features_drills_2026-10-19.md` §2.3 | the hunter spec (A checklist, B inventory, C target drills, D target scenario) and the §4/§5 shared-lane rules |
| `bench/hunter_rotation_audit_2026-10-19.md` | the per-client sim verdict (the six-arm Wrath priority, the TBC KC-first APL, the SoD Chimera, the Forever gaps) |
| `bench/hunter_open_2026-10-19.md` | the build shapes (traps/ISS/Readiness = badge layer, mana/prepull = practice layer, hawk count = cut) and the fetched sim URLs |
| `bench/wrath_leftovers_2026-10-19.md` | the wowsims/wotlk URL prefix used for the fresh sim fetches below |
| `docs/research/rotations_wrath.md`, `docs/research/rotations_sod.md`, `docs/research/forever_beta.md` | the guide-derived priority lists the rotation table cites |
| `practice.lua` §"Rotation scenario + drill contract" (the shared engine, 2026-10-19) | the frozen class contract, the engine's ctx builder, the run bands |
| `practice_ui.lua` (`scenario_context`, `drill_list_press`, `practice_rotation_entries`, `practice_rotation_family`) | the ctx the engine actually builds and the optional accessors it reads |
| sibling class lanes (`classes/druid.lua`, `classes/shaman.lua`, `classes/rogue.lua`) | the house shape for `practice_scenario_key`, `practice_rotation_for/family`, the drill `kind`/`description` fields and the moment-judge discipline |

**Fresh sim fetches this session** (the audit's URLs, fetched again so every id below
is quoted from the source, not from memory):

- `https://raw.githubusercontent.com/wowsims/tbc-new/master/ui/specs/hunter/dps/apls/default.apl.json`
  → prepullActions: **Aspect of the Hawk 27044 r8 at −20 s**, "Move to starting range"
  at −19 s. Priority list: Kill Command **34026** first, then the priority entry
  `currentTime <= 0.5s` → **Steady Shot 34120 r1** (the pull opener), then the Weave
  group (Multi 27021), the Arcane entry (**27019 r9**) and the Steady filler.
- `https://raw.githubusercontent.com/wowsims/sod/master/ui/hunter/apls/p7_weave.apl.json`
  → prepullActions: **Aspect of the Falcon 469145 at −5 s**, **Aimed Shot 20904 r6 at
  −3.5 s**, **Blood Fury 20572 at −1.95 s**, **Rapid Fire 3045 at −0.45 s**, **Serpent
  Sting 25295 r9 at −0.45 s** (the APL's own `dotRemainingTime 25295` upkeep is the
  same spell). Priority: Chimera **409433** (the `spellCanCast 409433` line) above
  the weave.
- `https://raw.githubusercontent.com/wowsims/forever/master/ui/specs/hunter/dps/apls/default.apl.json`
  → prepullActions: **Hunter's Mark 14325 at −22 s**, **Aspect of the Hawk 25296 at
  −20 s**. Priority: Raptor 14266 → Mark 14325 (if not on the target) → Serpent
  **25295** upkeep → the HHA sequence → Multi 2643 → Aimed 20904.
- `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/hunter/black_arrow.go`
  → Black Arrow **SpellID 63672**, duration 30 s.
- `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/hunter/explosive_trap.go`
  → Explosive Trap **SpellID 49067**, duration 30 s.
- `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/hunter/serpent_sting.go`
  → Serpent Sting **SpellID 49001**.
- `https://raw.githubusercontent.com/wowsims/wotlk/master/sim/hunter/talents.go`
  → Readiness **23989**, 3 min cooldown, resets RF / Multi / Arcane / KillShot /
  Raptor / ExplosiveTrap / KC / Aimed / Silencing / Chimera / BlackArrow, and the
  **smart double-RF delay**: it is not used while Rapid Fire is **< 10 s** from ready.
  Lock and Load **56344**.

---

## 1. The class contract (what the shared engine reads)

The engine looks the class up by `player_class` and reads:

| Member | Shape | Status |
|---|---|---|
| `ST.HUNTER.practice_scenario_step(self, ctx)` | `{ action = "<spell key>", reason = "<text>" }` or **nil** (undecidable → the engine grades UNKNOWN) | built |
| `ST.HUNTER.practice_drills` | `{ { key, label, kind, description, grade(self, ctx) } }` — nil grade = "not judgeable" | built (the audit's four) |
| `ST.HUNTER.practice_rotation` | the running family's table, in the sim's priority order, every entry citing its source | built |
| `ST.HUNTER.practice_rotation_for(family)` | the engine's optional accessor (the panel's buttons) | built |
| `ST.HUNTER.practice_rotation_family()` | the engine's optional accessor (the panel's readout) | built |
| `ST.HUNTER.practice_scenario_key()` | the harness drill key, registry-guarded (the sibling lanes' shape) | built (`hunter_forced_move`) |
| `ST.HUNTER.practice_context(self, now, last_action)` | the engine's optional ctx builder | built (the live state in the engine's vocabulary) |

### 1.1 The ctx the engine actually builds (and what the class reads)

`practice_ui.lua`'s `scenario_context(now, last_action)`:
* `now`, `last_action` — injected by the engine (the drill press passes
  `last_action = nil`: **the drill press carries no player action**);
* `resources` — the gathered resource numbers (a table or nil);
* `cooldowns` — the gathered cooldown readings, keyed by the gathered input **without
  its `_remaining_cd` suffix** (`kc_remaining_cd` → `kc`, `killshot_remaining_cd` →
  `killshot`), so the class reads the engine's key names;
* the class's own `practice_context` is preferred when it exists — the hunter
  publishes one, so the ctx carries the live cycle, the compensated latency, the
  execute read, the mana fraction and the **live cast as the pick** (`ctx.pick`).

**The class's extras** (each absent = the documented default): `cycle_duration`,
`latency`, `target_hp_frac`, `spec` ("MM"/"SV"), `rotation_family`, `family`,
`time_to_pull`, `ready_at`, `late_seconds`, `mispicks`, `pick`/`pressed`/`action`.

---

## 2. The rotation tables (the sim priority order, per family)

`ST.HUNTER.PRACTICE_ROTATIONS` — the compiled order is the engine's own rule order
(`hunter_guide.lua`), which the audit matched to the sims:

| Family | Order | Source per entry |
|---|---|---|
| ERA | `aimed, multi` | wowsims/classic `sim/hunter/hunter.go` Initialize (Aimed shares the auto-shot timer with Arcane; the Multi timer) |
| SOD | `chimera, aimed, multi` | wowsims/sod `sim/hunter/chimera_shot.go` (409433, 6 s CD) + `p7_weave.apl.json` + `docs/research/rotations_sod.md:16-23` |
| TBC | `kill_command, bestial_wrath, rapid_fire, arcane, multi, steady` | wowsims/tbc-new `default.apl.json` (KC first) + `sim/hunter/steady_shot.go` (34120, 1500 ms) + `sim/hunter/multi_shot.go` (27021, 500 ms) |
| WRATH | `kill_shot, chimera, explosive, aimed, arcane, steady` | wowsims/wotlk `sim/hunter/*` + `ui/hunter/presets.ts` + `docs/research/rotations_wrath.md:9-16` (guide-derived, not sim) |
| FOREVER | `hawk, sniper, steady` | wowsims/forever `sim/hunter/summon_hawk.go` + `sim/hunter/sniper_shot.go` + `default.apl.json` |

Only the actions the frozen engine can emit appear in a table: the melee surface
(Raptor Strike) and the upkeeps the engine does not model (Serpent Sting, the Era
Arcane Shot, the traps, Volley, Mongoose, Wing Clip) are the audit's filed gaps
(H-04, H-14, H-16), not rotation entries — an action the engine can never emit would
make the scenario expect a shot that never comes.

The SoD swap is the guide's own detector: the Chimera rune (409433) known on the ERA
token → `practice_rotation` re-points to the SoD table at `post_init`
(`resolve_guide_icons`), exactly like the guide's slot swap.

---

## 3. The drill set (the audit's §2.3 (C))

The engine's drill press carries **no player action** (`practice_ui.lua:4812` builds
the ctx with `last_action = nil`), so every drill here judges the **moment**; a drill
that needs the player's pick reads it from the ctx and answers **nil** when there is
none (unknown-hides, never a guessed grade — the druid seam's discipline).

| Drill | Kind | What it grades | Bands |
|---|---|---|---|
| `hunter_shot_order` | `rotation_order` | the pick against the engine's own answer (the same decision the scenario asks for) | S = the wanted shot · F = a mis-order (or a cast inside a HOLD window) · the run's mis-pick tally (ctx.mispicks) grades the session: S/A/B/C/D/F at 0/1/2/3/5+ (the audit's D-H1) |
| `hunter_weave_clip` | `rotation_window` | the moment's clip margin for the shot the rotation wants (the highest-priority cast shot that is off cooldown) | the shipped weave bands (`practice.lua:2405-2411`): S ≤ 0.02 · A ≤ 0.05 · B ≤ 0.10 · C ≤ 0.20 · D beyond · **F = the cast would clip** |
| `hunter_kill_command` | `situational` | the TBC pops: Kill Command → Bestial Wrath → Rapid Fire | with a pick: S = the right pop · F = the wrong pop or the wrong order · A/B/C = late by ≤1/≤2/≤3 GCD (the 1.5 s GCD default, `practice.lua:233`) · without a pick: the moment's place in the order (S = KC up, A = BW, B = RF) |
| `hunter_prepull` | `transition` | the pre-pull sequence and the pull opener | with a pick: S = on time · A/B/C/D = late by ≤1/≤3/≤5 s (the audit's D-H4) · D = the due opener was missed · without a pick: the moment inside the opener's window is an S; the drill owns its **synthetic pull clock** (the audit's D-H4: "a new synthetic pull clock belongs to the drill, not to the guide") |

**The pre-pull sequences** (the sim APLs' own offsets, `at` = seconds relative to the
pull): TBC — Aspect of the Hawk 27044 at **−20 s**, Steady Shot 34120 at **+0.5 s**;
SoD — Aspect of the Falcon 469145 (−5 s), Aimed Shot 20904 r6 (−3.5 s), Blood Fury
20572 (−1.95 s), Rapid Fire 3045 (−0.45 s), Serpent Sting 25295 r9 (−0.45 s);
Forever — Hunter's Mark 14325 (−22 s), Aspect of the Hawk 25296 (−20 s).

---

## 4. The class-side feature closures (the audit's §2.3 (A))

| Row | Feature | Verdict now | What landed |
|---|---|---|---|
| **H-05** | Lock and Load (Wrath 56344 / SoD 415413) | **CLOSED (the probe)** | the gather now writes `inputs.lnl_ready` from the class's **existing** throttled aura probe (`get_lnl_remaining`) — no new client read, no second scan; the probe runs only on the families that have the talent (Wrath, and the SoD rune on the Era family), so TBC and Era spend no scan (pinned) |
| **H-03** | the naked-Chimera guard (Serpent Sting) | **CLOSED (the guard) + FILED (the debuff)** | the guard now withholds the Chimera only when the sting is **known to be down** (`serpent_active == false`); an unknown debuff is "allow", as the header always said. The class knows the sting (the sourced ranks below) and the debuff stays unknown → the guard can never silence the prompt |
| **H-04** | Serpent Sting upkeep | **FILED (the debuff source)** | the sourced ranks are in the tree (13554 / 25295 / 49001); the **target-debuff read** does not exist (compat.lua exposes no target-aura scan) → `serpent_active` stays nil and the guide never prompts the sting. Needs a compat target-debuff probe |
| **H-16** | the Wrath trap tier (Black Arrow / Explosive Trap) | **PARTIAL (the data)** | the two Lock-and-Load source traps are now tracked by the trap machine (63672 / 49067, 30 s each, the sim's durations); the guide still never prompts a trap (the six-slot set is full) → the slot stays filed |
| **H-17** | Readiness 23989 as a rotation event | **PARTIAL (the data)** | the sourced facts are in the tree (3 min cooldown, the reset list, the 10 s smart double-RF delay) and the practice layer uses the reset list: a Readiness cast makes the whole kit ready and the rotation pops it. The live guide arm stays filed (no Readiness slot) |
| **H-18** | Improved Steady Shot 53220 | **CLOSED (the data) / filed (the guide arm)** | the id and the sim's 12 s duration are exported; the window is already visible in the HUD (the Steady/Aimed tint). Per `bench/hunter_open_2026-10-19.md` §1 the guide engine must **not** branch on it (no APL does) — no prompt change |
| **H-11/H-12/H-13/H-14/H-15/H-19/H-20/H-22/H-23/H-24** | mana group, melee weave, Era upkeep, Sniper Training, hawk count, Forever Multi, the HHA sequence | **FILED / CUT** | unchanged: the bench's verdicts (CUT from the guide engine; the count source does not exist; the Forever Multi conflict needs a client answer) |

### 4.1 The UNCONFIRMED ledger (this lane)

| Item | Status |
|---|---|
| Serpent Sting 13554 / 25295 / 49001 | SIM-CONFIRMED (the SoD p7 APL, the Forever APL, wowsims/wotlk serpent_sting.go) — **CLIENT-UNCONFIRMED** (in-client `GetSpellInfo` owed) |
| Black Arrow 63672, Explosive Trap 49067 | SIM-CONFIRMED (wowsims/wotlk) — **CLIENT-UNCONFIRMED** |
| Lock and Load 56344 / 415413 | SIM-CONFIRMED — **CLIENT-UNCONFIRMED** (unchanged from the badge lane) |
| ISS 53220, 12 s | SIM-CONFIRMED — **CLIENT-UNCONFIRMED** (unchanged) |
| Readiness 23989, 3 min, the 10 s RF delay | SIM-CONFIRMED — **CLIENT-UNCONFIRMED** (unchanged) |
| The TBC Steady opener's offset (+0.5 s) | the APL's own entry is `currentTime <= 0.5s`; the bench read it as a 0.5 s prepull, the APL reads it as the first half second **of the fight**. The drill implements the APL reading (the offset is +0.5 s) — **the bench's reading is superseded here** |
| Every grading band | **[DESIGN]** — addon policy, not sim numbers (the audit's U-15) |
| The scenario's 3.5 s cycle and 1.5 s GCD | the shipped practice defaults (`practice.lua:232-233`), not sim numbers |
| The pre-pull window after the last opener (5 s) | **[DESIGN]** — the sim's spacing bounds the gaps between the openers, nothing bounds the last one |

---

## 5. Cross-lane findings (not fixed here — out of scope)

1. **`practice_ui.lua`'s `scenario_context` reads an undefined
   `SCENARIO_RESOURCE_KEYS`** (`practice_ui.lua:4325`; the name appears nowhere else
   in the tree). The default ctx path therefore raises on the first scenario tick.
   The hunter is not affected (it publishes its own `practice_context`, so the
   engine's default path is skipped), but every class that does **not** publish one
   would hit it. The engine lane owns the fix.
2. The engine reads `module.practice_scenario_key` as a **string or a function**
   (`practice_ui.lua:713-726`); the hunter publishes the function form (the sibling
   lanes' shape) ✓.
3. The engine's cooldown map is keyed by the gathered input without its
   `_remaining_cd` suffix (`kc`, `bw`, `killshot`, …). The class reads those names ✓
   and also accepts the action key as an alias.
4. **Cost note for the operator:** the H-05 closure makes the gather spend the
   throttled Lock-and-Load aura scan (at most 40 `UnitAura` reads every 0.5 s) on the
   Wrath and SoD families, and only while the guide frame ticks (the guide's own
   driver calls the gather). TBC and Era spend nothing (pinned). If the operator
   wants that scan behind a toggle, the seam is the `db` read in the gather — the
   options pass owns the key.

---

## 6. Validation state

* `tests/hunter_state.lua` — **1046 checks PASS** (the class-only sandbox: the
  sourced ids, the gather wiring, the LnL probe scope, the trap ids).
* `tests/hunter_guide_state.lua` — **1397 checks PASS** (the engine sandbox: the
  pure `cast_margin`, the Serpent guard semantics, the rotation tables, the scenario
  step, the four drills, the class's own ctx).
* Full harness: **41 steps, 0 failed**, luacheck **2 warnings / 0 errors** (the tree
  floor) — re-run twice at the lane's close. Two runs during the lane showed reds
  in the **shaman lane's** suites (`shaman_state`, `shaman_guide_state`,
  `hud_state`'s shaman pins — the shaman guide grew to 17 slots mid-flight); the
  hunter suites were green in every run.
* luacheck: **2 warnings / 0 errors** in 82 files (the tree floor, unchanged);
  **0/0** in the four touched files.
* Mutation proofs: **8/8 killed** on `/tmp/opencode/mut_hunter` copies (the script
  is `/tmp/opencode/mut_hunter/mutate.sh`; the scratch tree is restored from the
  real tree between cases): M1 the rotation table's action key, M2 the clip
  margin's 0.03 s latency floor, M3 the LnL gather wiring, M4 the Serpent guard
  semantics, M5 the shot-order mis-pick grade, M6 the class ctx's live cycle, M7
  the scenario step never deciding, M8 the pre-pull offset.

**Not validated here** (honest limits): no in-client behaviour was observed; the
scenario's panel flow was exercised offline only (the engine's own UI paths are the
engine lane's); every id above still needs its in-client `GetSpellInfo` read.
