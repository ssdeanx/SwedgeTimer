# druid-rotfix — Journal

## 2026-10-19 — Desk opened
- **Purpose:** close gaps in bench/druid_rotation_audit_2026-10-19.md (engine side only)
- **Scope:** classes/druid.lua, druid_guide.lua, druid_energy.lua, tests/druid_state.lua, tests/druid_guide_state.lua. No other files.
- **Next step:** read in-scope files fully, then implement per-gap fixes nil-safe with follow-ups filed here.

## 2026-10-19 — Engine fixes landed (druid_guide.lua + tests/druid_guide_state.lua only)
- **Worked on:** closed 14 audit gaps in the pure engine; filed the rest as follow-ups below. classes/druid.lua, druid_energy.lua, tests/druid_state.lua needed NO changes (all new rules consume already-gathered inputs; gather/sampler/scan untouched).
- **Closed (engine + pins):**
  - E-2: Era E1 Bite→Rip (5CP expiry-only, unknown=long); E-4: Era E0 Clearcast→Shred added. Era sweep now forbids mangle/rake/bite.
  - S-5/S-6: SoD S5 TF-snapshot clip removed (expiry-only); S-8 mid-fight Bite removed (no Bite branch at all, S9→S8).
  - S-4/S-11: SoD S3b Roar-clip added (cover-to-end over SOD_SR_DURATION 14/19/24/29/34, TTD-gated, unknown-hides).
  - T-8: SHORT_LIVED_TTD_SECONDS 12→10 (sim RipEndThresh); T-7: header now cites sim Wolfshead 8345 (comment only, in-client confirm still owed).
  - W-2: W1 static 40→dynamic 40-10*leeway (gcd_remaining +1s on clearcast; latency filed); stale "under 30" comment fixed.
  - W-3: W2 energy≤85 gate REMOVED (sim has none; BERSERK_ENERGY_WRATH const gone); added Rip-active + !clearcast gates.
  - W-10: FB minima 8→4 (sim BiteTime).
  - F-1/F-2: Forever ceiling 60→50 (40 on clearcast, sim underCap); F-3: Forever F1 no longer falls to legacy windows — new chain F2 cc→Shred, F3 5CP Rip expired, F4 Rake expired, F5 Mangle absent, F6a 5CP Bite end-only (TTD≤10/flag), F6b 3+CP Bite <3s, F7 Shred.
- **Validation:** druid_guide_state 95214 PASS, druid_state 473 PASS, guide_contract 763 PASS, luacheck 0/0 on both touched files (tree floor 2/0 held). Endings preserved (guide CRLF, tests LF). 10/10 mutation proofs on /tmp/opencode/druid-rotfix copies (verified passing baseline; M1 SP-60, M2 W1-static, M3 S5-clip, M4 T1-bite, M5 Forever-midbite, M6 shortlived-12, M7 FB-8, M8 clip-off, M9 Era-no-omen, M10 F6a-always — all KILLED).
- **Crossfire note:** full harness shows 8-9 failing suites across runs (warrior/twist/shaman_guide/rogue_guide/paladin/bars/secret_guard/wiring) — all in files OUTSIDE this lane's scope, non-deterministic between runs (e.g. wiring_check FAIL then PASS, luacheck 3→2 warnings). Parallel lanes are morphing the tree. classes/druid.lua, druid_energy.lua, tests/druid_state.lua show `M` from other lanes — NOT this desk (this desk edited only druid_guide.lua + tests/druid_guide_state.lua). My three in-scope suites + contract pass in-tree on every run.
- **Filed follow-ups (owner: orchestrator):**
  1. Fight-elapsed input (Era 8s/10s + Forever 10s Rip gates) — needs a fight-clock input in gather (classes/druid.lua, in-scope for a future lane) + options? No — engine constant default OK, wiring follow-up is the combat-start stamp.
  2. Trick windows (Era/SoD ShredTrick/RipTrick, TBC MangleTrick/RakeTrick/BiteTrick/ripweave, Wrath/Forever pooling horizons) — need tick-phase + live-cost inputs not yet gathered.
  3. Wrath/SoD clipRoar-glyph extension (MinRoarOffset/RipLeeway) + Rake DPE gate — need glyph/set/AP inputs.
  4. Omen-fishing FF (Wrath ffThresh + Forever omenFish) — needs an FF cooldown input in gather.
  5. W1 latency term (max(gcd,latency)) — needs a latency probe.
  6. Forever Berserk (417141 id is sim-only) + Claw + consumable/mana layer — needs id confirm + slot/sequence design (contract + options out of scope).
  7. TBC RipCP threshold (sim user-config, we freeze 4CP) — needs an option (option_tables/config_presets OUT OF SCOPE); engine side ready for an input override.
  8. TBC RakeTrick exclusion + TBC bear Mangle-debuff suppression + Cata/Mists bear rule-3 + all UNCONFIRMED numbers — in-client confirm.
- **Next step:** orchestrator owns validation + reconcile (count pins) + in-client test session. No further offline work owed by this desk.

## 2026-10-19 — [signal:done] druid rotation gaps closed engine-side
- 14 gaps closed in druid_guide.lua + tests/druid_guide_state.lua; 8 follow-ups filed above (inputs/options/client-proof owed)
- In-scope suites green every run (95214 + 473 + 763), luacheck 0/0 on touched files, 10/10 mutation kills; full-harness failures are parallel-lane crossfire in out-of-scope files

## 2026-10-19 — Follow-up build lane (trick/pooling inputs, FF/Claw/Berserk, RipCP groundwork)
- **Worked on:** built the filed follow-ups engine-side in druid_guide.lua, classes/druid.lua, druid_energy.lua + pins in tests/druid_guide_state.lua, tests/druid_state.lua. No option/config/contract/smoke/run/TOC/bars/hud/practice/compat/main/docs/version touched; no bar-frame widgets; no git; no invented sim behavior (new UNCONFIRMED marks in caps where the sims are silent).
- **Built:**
  - RipCP override: `inputs.rip_min_cp` (nil = frozen `RIP_MIN_CP_TBC = 4`, clamped 2-5) read by T1 (`druid_guide.lua:515-:520`, `:663-:666`). Default-visible unchanged (nil -> 4, all prior pins byte-identical).
  - Fight-elapsed gates: `inputs.fight_elapsed` from `ensure_druid_fight_stamp` (`classes/druid.lua:1612-:1625`, stamp `classes/druid.lua:250`, clear `classes/druid.lua:292`, gather `classes/druid.lua:1710`) via `st.api.get_time()`; E1/S5 withhold < 8 s (`druid_guide.lua:407`, `:725-:726`, `:760-:761`), F3 withholds < 10 s (`druid_guide.lua:408`, `:897-:898`); nil/NaN defaults to the long fight and Rips. Pure helper `fight_is_young` (`druid_guide.lua:526-:530`).
  - W1 latency term: `inputs.latency` (gather writes nil, `classes/druid.lua:1706`) read as `max(gcd, latency) + 1 s on proc` (`druid_guide.lua:539-:549`); nil/NaN degrades to the GCD alone.
  - Forever Berserk hold F1b: `berserk_ready` + Rip up (> 0) + no proc -> hold BERSERK (`druid_guide.lua:881-:890`), outranking F2-F7, outranked by F1; reuses the shared Berserk knowledge probe (417141 sim-only UNCONFIRMED, never a guessed id).
  - Trick/pooling plumbing (RESERVED, no rule reads): `inputs.tick_remaining` from the tracker anchor (`classes/druid.lua:1715-:1720`) via pure `druid_energy.get_tick_remaining` (`druid_energy.lua:267-`); window helper `druid_energy.is_energy_in_window` (same file). `classes/druid.lua:1704-:1706` writes nil `can_shred`/`rip_min_cp`/`latency`.
  - FF Omen-fishing plumbing (RESERVED, no rule reads): name-based `guide_ff_query = "Faerie Fire"` with GCD-echo filter (`classes/druid.lua:1440`, `:1810-:1816`); unknown stays nil.
- **Validation:** druid_guide_state 95324 PASS (+110 new pins), druid_state 496 PASS (+23), full harness 37/0, luacheck 0/0 on all five touched files (tree floor 2/0 held). Endings preserved (guide/classes CRLF, energy/tests LF). 10/10 mutation kills on /tmp/opencode/druid-followup copies (M1 rip_min_cp-5, M2 era-gate-0, M3 no-F1b, M4 forever-gate-0, M5 no-latency, M6 T1-hard4, M7 tick-nil, M8 window-false, M9 nostamp, M10 noFF — all KILLED, copy restored byte-identical).
- **Filed follow-ups (owner: orchestrator):**
  1. RipCP option widget (OUT OF SCOPE): needs a `guide_rip_min_cp` range 2-5 default 4 in option_tables.lua + default in config_presets.lua + options_load parity; engine side ready (`tbc_rip_min_cp`, `druid_guide.lua:515-:520`).
  2. Trick/pooling rules: BiteTrick/RakeTrick/MangleTrick/ripweave (TBC), ShredTrick/RipTrick (Era/SoD), pendingPool/floatingEnergy (Wrath), 2 s/1 s pooling (Forever) — need live bite/shred costs (rank-table probe via GetSpellPowerCost, filed) + guide-only tick upkeep (sampler currently needs tick bar or countdown on; `classes/druid.lua:1715-:1720` reuses the anchor with no extra upkeep). Pure helpers ready (`druid_energy.lua:267-`).
  3. Wrath/SoD clipRoar-glyph extension (MinRoarOffset/RipLeeway) + Rake DPE gate — need glyph/set/AP inputs (no probe exists; `sod_should_clip_roar` cover-to-end shape stays expiry-only otherwise, `druid_guide.lua:587-`).
  4. Omen-fishing FF rule (Wrath ffThresh 87/15 + waitForFf, Forever omenFish ICD/SP-left/regen gates): inputs gathered (`ff_ready`/`ff_cd_remaining`, `classes/druid.lua:1810-:1816`), no rule reads them yet — needs the spend-math design against live FF cooldown + Omen ICD (no ICD input exists).
  5. W1 latency probe: `inputs.latency` wired nil (`classes/druid.lua:1706`, math `druid_guide.lua:539-:549`); needs an honest latency source (LibLatencyMonitor exists in-tree but no druid wiring — filed).
  6. Forever Berserk SP-phasing + 417141 id confirm (in-client); Claw needs a six-slot contract change + position probe (both OUT OF SCOPE — `can_shred` stays nil, `classes/druid.lua:1704`); consumable/mana layer (Tea/potion/Innervate/mana) has no inputs — filed, no guide expression.
  7. TBC bear Mangle-debuff suppression (healthy Mangle currently never suppresses the bear fallback, `druid_guide.lua:650-`); Cata/Mists bear rule-3; all UNCONFIRMED numbers (SP 50/40/16 s, FF ranks, Wrath 2pc costs) — in-client confirm.
- **Next step:** orchestrator owns validation + reconcile (count pins: 95324 + 496) + in-client test session. No further offline work owed by this lane.

## 2026-10-19 — [signal:done] follow-up build complete
- Signal `desks/druid-rotfix/.signals/2026-10-19T14-53-52Z.json` (done); 7 files touched in-scope only, full harness 37/0, 10/10 mutations killed.

## 2026-10-19 — RipCP gather wired (engine already consumed it)
- **Worked on:** wired the filed RipCP gather input; no rule redesign, no widget, no other files.
- **Built:**
  - Gather: `inputs.rip_min_cp = db.guide_rip_min_cp` (`classes/druid.lua:1707`, comment `:1695-:1699`) — raw passthrough, nil until the widget ships; engine `tbc_rip_min_cp` (`druid_guide.lua:515-:520`) clamps 2-5 and defaults to the frozen `RIP_MIN_CP_TBC = 4` (`:401`, untouched). No default-visible change (db key absent everywhere → nil → 4, all prior pins byte-identical).
  - Pins: `tests/druid_guide_state.lua` +6 (nil/2/3/5/1-raw/nil-clear, §2 option block); `tests/druid_state.lua` +7 (nil/2/5/1-raw/nil-clear/stale-feed/stale-clear, new block before the final PASS). Engine clamp pins (§17: 1/6/NaN/"4" → 4) already stood.
- **Filed (owner: orchestrator) — RipCP widget exact shape, still OUT OF SCOPE:** `guide_rip_min_cp`, `type = "range"`, `min 2, max 5, step 1`, default `4` in `config_presets.lua` (`guide_rip_refresh = 4` shape at `:259-:260`) + widget in `option_tables.lua` (`guide_rip_refresh` shape at `:4210-:4219`) + `tests/options_load_state.lua` parity. No inert toggles: nothing ships until this widget lands; gather stays nil-safe meanwhile. `druid_guide.lua`, `option_tables.lua`, `config_presets.lua`, `tests/options_load_state.lua`, `druid_energy.lua`, compat/bars/hud/practice/main/guide_contract/smoke/run/TOC/docs/versions untouched.
- **Validation:** druid_guide_state 95330 PASS (+6), druid_state 503 PASS (+7), full harness 38/0, luacheck 0/0 on all touched files (tree floor 2/0 held). Endings preserved (classes CRLF, tests LF). 6/6 mutation kills on `/tmp/opencode/druid-ripcp` shadow-tree copies (M1 hardcode-nil, M2 `or 4`, M3 wrong key, M4 conditional-write/stale, M5 engine-ignores-override, M6 no-lower-clamp — all KILLED in both suites where pinned, shadow tree restored to symlinks).
- **Crossfire note:** one harness run showed `shaman_guide_state` 1/789 FAIL (shamanisticrage vs stormstrike, out-of-scope file); clean re-run passes 815/815 with zero tree change — parallel-lane flake, not this lane.
- **Next step:** orchestrator owns validation + reconcile (count pins: 95330 + 503) + widget lane + in-client test session. No further offline work owed by this lane.

## 2026-10-19 — [signal:done] RipCP gather wired
- Signal `desks/druid-rotfix/.signals/2026-10-19T15-40-41Z.json` (done); 3 files touched in-scope only (classes/druid.lua gather line + comment, tests/druid_state.lua +7, tests/druid_guide_state.lua +6), druid_guide.lua untouched, full harness 38/0, 6/6 mutations killed.

## 2026-10-19 — FF Omen-fishing + Claw slot build (W1b/F6c engine, claw slot/contract)
- **Worked on:** filed follow-ups #4 (FF spend-math + ICD) and #6-Claw (slot/contract) from the 2026-10-19 follow-up entry. FF name probe + GCD filter already live as plumbing - untouched.
- **Built (engine, druid_guide.lua only):**
  - W1b Wrath FF fish (sim wotlk ffNow): ff_ready + !proc + energy<87 + Rip-deferral (5CP due unless bar under Rip cost 30) + end-of-fight spend math (extra FF GCD must buy extra Shred; unknown TTD = long default). Hold "FAERIE FIRE" (no FF slot), ahead of Berserk like the sim.
  - waitForFf (sim wotlk, 1 s - 0.1 s MaxFfDelay, post-GCD energy <87, Rip not falling inside the second): pools W6/W7/W9 (nil action, no hold) while FF answers.
  - F6c Forever omen-fish (sim forever omenFish): ff_ready + !proc + omen_icd_ready + SP-left>=1 s + regen(energy+10) under frozen Shred/Rake/Rip costs + rakeSoon/ripSoon 1 s horizons. Hold "FAERIE FIRE", between F6b and F7 (APL-late like the sim).
  - Frozen FF constants: FF_ENERGY_WRATH 87, FF_WAIT 1, FF_MAX_DELAY 0.1, FF_SP_LEFT 1, FF_REGEN 10, FF_SHRED 42 / FF_RIP 30 / FF_RAKE 40 (Wrath/Forever UNCONFIRMED - no live-cost probe; in-game to confirm).
  - No other family touched: TBC/Era/SoD/legacy/bear/RETAIL byte-identical (family-gated branches only); prior pins all green.
- **Built (gather/slot, classes/druid.lua only):** guide_slot_claw (key claw, spell_id 9850 sim Forever id, no rank table - other ranks UNCONFIRMED), slots 6->7; can_shred stays nil (sim CannotShredTarget has no WoW API counterpart - filed); no Claw engine rule (out of scope for this lane); HUD unchanged (claw HUD slot filed with the rule).
- **Pins:** tests/druid_guide_state.lua 95457 PASS (+127: §2 seven-slot/frame-19/icon-claw updates, Era §6c 7-slot, §9/§14 sweeps green unchanged, new §20 FF constants/W1b/waitForFf/F6c/Claw incl. 32-energy regen boundary). tests/druid_state.lua 503 PASS (HUD untouched). tests/guide_contract.lua untouched (no druid sections exist - zero diff, no other class section touched). Full harness 38/0, luacheck 0/0 on touched files (tree floor 2/0 held in compat/main). Endings preserved (guide/classes CRLF, tests LF). 10/10 mutation kills on /tmp/opencode/druid-ffclaw shadow copies (M1 ff87->97, M2 no-ICD-gate, M3 no-wait, M4 ripcost-100, M5 no-claw-slot, M6 F6c-text, M7 spend-math-</<=, M8 regen->/>= caught by the new 32-energy pin, M9 claw-id, M10 no-W1b).
- **Filed follow-ups (owner: orchestrator):**
  1. Omen ICD probe (inputs.omen_icd_ready nil -> F6c dormant in game): needs Clearcasting proc-timestamp tracking in classes/druid.lua gather (future lane); Omen ICD duration itself UNCONFIRMED (sim auraIcdReady 16864, duration not pinned from sim core).
  2. Claw rule (can_shred false -> claw): needs behind-target probe - none exists in WoW API (IsSpellUsable answers usability, never facing); slot declared, gather nil, engine has no branch.
  3. Claw HUD slot + Claw rank table (9850 only; other ranks UNCONFIRMED) - with the rule.
  4. Wrath FF 15-in-Berserk line (sim BerserkFfThresh, forced 15 in setupRotation): needs Berserk-aura input (only berserk_ready cooldown exists); engine always fishes at 87 meanwhile.
  5. Live Shred/Rip/Rake cost probe for Wrath/Forever (frozen 42/30/40 UNCONFIRMED; TBC live mangle_cost pattern exists as precedent).
- **Next step:** orchestrator owns validation + reconcile (count pins: 95457 + 503) + in-client test session. No further offline work owed by this lane.

## 2026-10-19 — [signal:done] FF Omen-fishing + Claw slot built
- Signal `desks/druid-rotfix/.signals/2026-10-19T16-30-00Z.json` (done); 3 files touched in-scope only (druid_guide.lua FF rules, classes/druid.lua Claw slot, tests/druid_guide_state.lua +127 pins), guide_contract.lua untouched, full harness 38/0, 10/10 mutations killed.
