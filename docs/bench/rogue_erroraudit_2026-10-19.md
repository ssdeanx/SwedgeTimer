# rogue_erroraudit_2026-10-19 — Read-only error-path audit of the STABLE rogue surfaces

Desk: rogue-erroraudit. No addon files touched. Single new file per
`bench/briefs/brief_rogue-erroraudit_2026-10-19.md` (confirmed absent at lane
start). Date: 2026-10-19. Tree state: harness **37 steps, 0 failed**, luacheck
**2 warnings / 0 errors** (floor), verified in-lane before filing.

Extends, never re-derives: `bench/feature_hunter_audit_2026-10-19.md`
(H1–H6/M1–M7 CLOSED — closure for rogue paths verified below, not re-audited),
`bench/rogue_deep_2026-10-19.md` §4 handoff, `bench/rogue_readiness_2026-10-19.md`
§4 residuals. Context-only (parallel writer lanes own them — read for
orientation, NOTHING graded): `classes/rogue.lua`, `diag.lua`,
`config_presets.lua` cue defaults. Any note touching those files is marked
PROVISIONAL.

Evidence bar: every file:line anchor below was read on current disk 2026-10-19.
Labels: proven offline (read and/or executed in a stub sandbox) vs UNCONFIRMED
(needs a live client). Verdict per brief: NEEDS FIXES or ADEQUATE.

## 0. Surfaces reviewed (5 stable) + validation runs

1. `rogue_guide.lua` (pure engine, :1-533) — unknown-input discipline,
   per-client tables, TTD boundaries.
2. `compat.lua` five rogue probes: `api.GetItemInfo` (:1078-1101),
   `api.GetItemCooldown` (:1119-1128), `api.GetItemCount` (:1105-1114),
   `api.GetWeaponEnchantInfo` (:1141-1153), `api.UnitGUID` (:1162-1171).
3. `practice.lua` rogue drills: `H.energy_tick_marker` (:2505-2525),
   `H.grade_energy_spend` (:2530-2548) + `rogue_energy_pool` scenario
   (:2551-2584), `H.grade_ss_after_swing` (:2605-2623) + `rogue_ss_window`
   (:2625-2659); shared `H.grade_band` (:1672-1690), `H.SCENARIO_KINDS`
   (:1495-1503), `register_scenario` (:1510-1529).
4. `option_tables.lua` ROGUE section (:4267-4760): threshold helpers,
   every widget, color-row gates, HUD builder call.
5. `tests/rogue_guide_state.lua` (:1-451, 206 checks) + `tests/guide_contract.lua`
   rogue parity (:1256-1344) as the matrix/contract pins.

In-lane runs (read-only, no edits): `tests/rogue_guide_state.lua` 206 checks
0 failed; `tests/practice_state.lua` 1151 checks 0 failed;
`tests/guide_contract.lua` PASS (756 checks); `tests/options_load_state.lua`
919 checks 0 failed; `tests/secret_guard_state.lua` PASS (320 checks);
`bash tests/run.sh` 37 steps 0 failed; `luacheck .` 2 warnings / 0 errors.

## 1. Findings (stable surfaces only)

### F1 [LOW — harden]: NaN drill inputs grade instead of scoring nil

Location: `practice.lua:2505-2525` (explicit-marker passthrough),
`practice.lua:2530-2548` (`grade_energy_spend`), `practice.lua:2605-2623`
(`grade_ss_after_swing` window reads), via `practice.lua:1672-1690`
(`grade_band` fallback).

Pattern: unvalidated numeric passthrough on a scoring path (H4-adjacent:
ambiguous input should be nil, never a guessed grade).

Current code: `energy_tick_marker` returns an explicit numeric `tick_marker`
with no NaN/range check (`:2509-2511`); window reads use `or DEFAULT`, which
keeps NaN (NaN is truthy). `grade_band` maps a NaN margin to the no-max
fallback band.

Evidence — proven offline (stub-harness execution, `st={practice={}}`
sandbox): `energy_tick_marker({tick_marker=0/0})` → `-nan` (truthy);
`grade_energy_spend({tick_marker=0/0}, 0.5)` → **"D"** (WEAVE bands
`:2405-2411` fall back to D, not F — a false *decent* grade); NaN
`window_start` bypasses the early-window guard (`0.05 < NaN` is false), so an
early offset 0.05 grades **"B"** instead of F. NaN `ideal` degrades safe
(SS bands fall back to F). So the energy drill fails UNSAFE on NaN while the
SS drill fails safe — asymmetric.

Impact: practice scores only, zero combat stakes. Live-unreachable on current
disk: no live writer of explicit `tick_marker` exists in-tree (only drill
`opts` + tests), and both drills' `new_state` defaults are clean
(`ROGUE_ENERGY_DEFAULTS` 2/0.1, `ROGUE_SS_DEFAULTS` 0.1/0.2/0.1). Any future
live-latency feed into drill opts is UNCONFIRMED. Casual: a misconfigured
drill awards D/B on garbage; top-level: none.

Fix direction (orchestrator/writer lanes): `is_num`-guard the marker and the
window/ideal reads (NaN → nil marker / nil grade) — three lines, H4-symmetric.
No suite change needed beyond two NaN pins.

### F2 [LOW]: `api.GetItemCount` passes non-number success values through

Location: `compat.lua:1105-1114`.

Current code: `ok` + `is_secret(count)` checked, but no
`type(count) == "number"` check — a non-number, non-secret success return
reaches callers as-is.

Evidence — proven offline (read). Live reachability UNCONFIRMED (the
documented contract returns a count; no failing shape sourced).

Impact: negligible — Tea-count display garbage at worst; the sibling wrappers
all coerce (`GetItemCooldown` nil→0, enchant booleans, guid string-check).
One-line hardening for symmetry; never a wrong-spend path (count gates a cue,
not a cast).

### F3 [MEDIUM-LOW — orchestrator decision]: `api.GetItemCooldown` unknown reads as idle-ready

Location: `compat.lua:1116-1128` (comment `:1116-1118` blesses the shape).

Pattern: the hunter-H4 structural shape — unknown (absent probe / throw /
secret) reports `(0, 0, 0)`, the exact shape every consumer treats as "no
cooldown". Unknown reads as ready.

Evidence — proven offline (read). Secret-regime reachability for item
cooldowns is UNCONFIRMED (no source; Midnight item-CD secrecy unsourced).

Impact: worst case, a Thistle-Tea prompt while Tea is actually on cooldown
under a secret/absent probe. Player presses Tea → no-op error, no item
consumed, no GCD waste beyond the attempt. Minor confusion, no DPS loss —
unlike H4 (mistimed hard-cast), nothing mistimes a real cast.

Consumer half is PROVISIONAL (parallel compat/options lanes own
`classes/rogue.lua` tea_ready derivation + options copy). Either (a) accept
as documented residual (E2 whole-or-nothing family: unknown-idle is the
designed contract, diag-visible nowhere for items), or (b) return
`nil, nil, nil` unknown and teach the consumer the third shape. Recommend (a)
unless the writer lane already distinguishes — reconcile, don't re-derive.

### F4 [LOW — coverage]: matrix pins 6 of 8 POOL_BANDS cells

Location: `tests/rogue_guide_state.lua:81-92`.

`TBC.pre/post`, `ERA.pre/post`, `WRATH.pre`, `FOREVER.post` asserted;
`WRATH.post` and `FOREVER.pre` never asserted. A typo in either unpinned cell
(e.g. `FOREVER.pre = 60`) passes the suite and silently shifts the pooling
band on that client.

Evidence — proven offline (read). Impact: silent band drift on Wrath/Forever
if ever mistyped; no live failure today (literals read correctly). Two-line
pin closes it.

### F5 [LOW — coverage]: no both-due rule-order pins

Location: `tests/rogue_guide_state.lua:336-367`; engine
`rogue_guide.lua:481-502`.

Pinned: EA > 5-CP finisher, EA > shiv, shiv > finisher, envenom > healthy
rupture. NOT pinned: shiv-due + envenom-due (rules 2v3, expect shiv),
EA-due + envenom-due (rules 1v3, expect expose), shiv-due + dying-dump
(rules 2v4, expect shiv). The engine order is correct by reading; only the
combined pins are missing, so a future reorder of rules 1–3 would stay green
while changing live priority.

Evidence — proven offline (read). Impact: regression-tripwire gap only.
Three evaluate one-liners close it.

### F6 [INFO — confirm intent]: rules 4/5 fire on unknown/nil family

Location: `rogue_guide.lua:488-502` (no family gate on the dying dump or the
planned finisher); header `:53-56` documents "unknown runs no client-specific
rule". Test pins unknown-family silence only for the pool path with 0 CP
(`tests/rogue_guide_state.lua:405-406`).

Reading: Envenom + pooling are family-gated; Rupture/Eviscerate/Expose/Shiv/Tea
are not. Defensible — every rogue client has Rupture/Eviscerate, and unknown
family with good reads is not the same as unknown reads (M6 bit still
suppresses everything). Default verdict ADEQUATE. Ask: orchestrator confirms
this asymmetry is intended; either way, add one `BOGUS + cp=5` pin documenting
the chosen behavior so it can't drift silently.

### F7 [INFO]: negative TTD reads as dying

Location: `rogue_guide.lua:252` (`ttd <= min_ttd`), `:301`, `:491`.

A negative TTD (already-dead target, clock skew) satisfies every dying-target
branch (Envenom dying_only, rule-4 any-CP dump). Impact: negligible — the
fight is over; prompting a finisher on a corpse wastes nothing live. No pin
requested; recorded so a future TTD-provider lane doesn't "fix" it into a
third state. ADEQUATE as-is.

### F8 [PROVISIONAL — reconcile vs writer lane]: pool-band widgets lack the triple fallback

Location (stable side): `option_tables.lua:4346-4363`
(`rogue_pool_band_pre/post` use the generic getter/setter). Contrast the six
guide thresholds, which read db → engine constant → literal and can never
render empty (`option_tables.lua:4267-4289`; positive P4 below).

Round-trip holds ON CURRENT DISK: `config_presets.lua:580-581` ships
`rogue_pool_band_pre = 65, rogue_pool_band_post = 85`, and the options lane's
section-9 scan pins all 23 consumed keys present with widget + default. But
`config_presets.lua` is owned by a parallel writer lane — if that lane drops
or renames these two defaults, the range widgets render nil (Ace range with
nil: blank-at-best, error-path UNCONFIRMED in-client), while the six
thresholds would survive. Orchestrator: either keep the defaults (no action)
or extend `rogue_threshold_get`-style fallback to the two band widgets. No
stable-surface edit proposed here.

## 2. H1–H6/M1–M7 closure for rogue paths (extend, not re-audit)

| ID | Rogue-path verdict | Basis |
|---|---|---|
| H1 engine_dead | HOLDS (stable) + PROVISIONAL (provider) | Pure engine takes no speed input — stub-speed dependence is structurally impossible (`rogue_guide.lua:57-68`). Era SS-cue `engine_dead`/nil-speed branching lives in `classes/rogue.lua` (in-flight) — not graded. |
| H2 run_guarded | HOLDS, throw-safe by construction | Every numeric use in `rogue_guide.lua` is behind `is_num` (`:198-227, :235-264, :295-347, :356-411`); non-table `inputs` short-circuits in `is_unknown` (`:417-425`); non-table `out` is reallocated (`:431-434`); `inputs` never written (immutability pinned `:443-447`). Inherits the `bars.lua:517-556,681` backstop without needing it. Minor note: the `pool_pre/post` override allocates one table per tick when used — provider-controlled, not a leak. |
| H3 fan-out pcall | HOLDS (vacuous) | No rogue CLEU matching exists on any stable surface; nothing new dispatches through `callback_event_handler`. If Shiv-cast matching is ever added, it inherits the `main.lua:791-816` guard; readiness §4 R1 name-fallback still applies. |
| H4 nil→unknown | HOLDS on stable side | Nil tick → nil grade (`practice.lua:2531-2533`, pinned nil-tick-unscored); nil swing → nil (`:2606-2608`, pinned); unknown core reads → `unknown=true`, no action/hold (`rogue_guide.lua:439,521-531`, pinned §5 + `guide_contract.lua:1339-1343` degenerate tick). Provider tick predictor is in-flight — PROVISIONAL. |
| H5 payload counters | HOLDS (vacuous) | Stable rogue surfaces parse no `PLAYER_SWING` payloads and emit no counters (none needed). Provider must read `swing_source` reject/speed counters via `/st diag`, not invent its own — PROVISIONAL. |
| H6 spellcast guard | HOLDS (vacuous) | Stable surfaces consume no spellcast lifecycle. Provider `on_spellcast_event` self-guard (if the hook exists at all) is in-flight — PROVISIONAL. |
| M1/M2 range | N/A | No rogue range polling on any stable surface. |
| M3 unmatched payloads | N/A | No rogue CLEU matching → no unmatched-payload path. Future Shiv/poison matching needs the M3 counter + R1 name-fallback (readiness §4). |
| M4 hidden degradation | HOLDS, documented | Guide separates unknown (`…`, `unknown=true`) from no-action (silent) — pinned `guide_contract.lua:1314-1318`, `rogue_guide_state.lua:308-310`. Bar-widget unknown-hide vs toggle-off look identical, but the options copy documents it (energy/cues descriptions) and the direction is H4-safe. |
| M5 secret lust | HOLDS trivially (pure) + PROVISIONAL (presentation) | The pure engine has NO lust/haste input — secret-regime lust cannot skew any verdict (pooling bands are energy-tick, haste-independent). The AR+BF stacked glow + `lust_unknown` latch live provider/frame-side; `guide_contract.lua:1334-1336` pins secret→latch→unknown on current disk, but the provider file is in-flight — PROVISIONAL. |
| M6 inputs_unknown | HOLDS (pure) + PROVISIONAL (provider) | Rule 0 suppresses every action/hold on the bit, including over a due EA refresh — pinned `:299-334` incl. explicit-false. Provider ownership of the bit is in-flight (latch case pinned in-contract on current disk). |
| M7 TTD provenance | HOLDS (contract) | TTD is numeric-provider-input-only, header-forbidden from the 2.0 s fallback (`rogue_guide.lua:62-68`); nil TTD guesses no finisher (rule 5 falls through to Tea/pool — pinned `:382-383`); unknown-TTD envenom never fires (pinned `:168-173`). EMA-velocity wiring is Round 2 (future work, not a gap). |

## 3. Positive findings (stable side)

- **P1. Total-on-inputs pure engine.** `evaluate` cannot throw on any input
  shape and never writes its inputs (see H2 row). Nil-safety section
  (`rogue_guide_state.lua:437-448`) + degenerate frame tick
  (`guide_contract.lua:1339-1343`) pin it. The H2 backstop stays a backstop.
- **P2. Enchant-presence normalization.** `api.GetWeaponEnchantInfo`
  (`compat.lua:1141-1153`) reads positions 1-and-5 and coerces
  non-boolean/secret/throw/absent to nil-nil — the exact latent client-shape
  bug class becomes unknown-never-unpoisoned. Pinned by `secret_guard_state`
  (320 checks) + the compat lane's 13/13 mutations.
- **P3. Loud scenario registration.** Unknown kinds reject with an error
  string (`practice.lua:1520-1522`); both rogue kinds are registered
  (`:1500,1502`); duplicate keys reject. No silent drill loss possible;
  registry 6→8 pinned.
- **P4. Threshold triple-fallback.** `rogue_threshold_get`
  (`option_tables.lua:4267-4278`) reads db → engine constant → literal, and
  `rogue_threshold_set` ignores non-numeric writes (`:4282-4289`). The six
  guide ranges + NAG x/y (`or 0`/`or -180`) can never render empty, even for
  predating profiles or a missing `rogue_guide` module. All 10 color rows are
  `disabled`-gated by their toggle (`:4322-4324` et al., 10/10 verified).

## 4. Coverage notes (matrix vs per-client rules)

`tests/rogue_guide_state.lua` (206 checks) covers: strict-sandbox load, all
four band tables + RETAIL-absent + unknown/nil family lookup, distinct-table
(no shared reference) for ERA/TBC bands and all Envenom tables, pool
predicate incl. pre/post/cap/Vigor/NaN, TTD decider incl. boundaries and
NaN/unknown, all four Envenom modes incl. Wrath cap-exception and
proven-empty chain break, EA/Shiv/Tea incl. boundaries and nil/NaN clocks,
rule order 0–7, frozen-field overwrite, input immutability, no-arg safety.
`guide_contract.lua` rogue parity adds provider→frame mapping (pool/spend/
expose/unknown/latch + degenerate tick, 7 action slots). Gaps are F4/F5/F6
above — all low/info. No per-client rogue rule from the research corpus lacks
a matrix case: Era combat (dying dump), TBC Imp-EA duty, WotLK let-expire +
cap, Forever never, retail chain + phase-pooling silence, SoD carried under
ERA (documented deferral, safe under-prompt).

## Summary

| Severity | Count | Items |
|---|---|---|
| MEDIUM-LOW (orchestrator decision) | 1 | F3 |
| LOW (harden when convenient) | 4 | F1, F2, F4, F5 |
| INFO / PROVISIONAL | 3 | F6, F7, F8 |

No finding mistimes a real cast, fabricates a confident prompt on unknown
data, or hides a failure on any stable surface — every load-bearing path
degrades to nil/unknown/silent with a pin. The three PROVISIONAL halves
(provider engine_dead branching, tick predictor, tea_ready/lust presentation)
belong to the parallel writer lanes; this audit places no constraint on them
beyond the already-pinned contracts.

### Verdict: ADEQUATE

F3 is a documented-design decision for the orchestrator (accept residual vs
distinguish unknown-idle), not a defect; F1/F2/F4/F5 are small hardenings;
F6–F8 are intent-confirmations. Nothing here blocks the writer lanes or the
owner in-client session.

*Limitations: read-only (no probes; every UNCONFIRMED above is a real
in-client check, not a hedge). `classes/rogue.lua`, `diag.lua`,
`config_presets.lua` read for orientation only — nothing graded there.*
