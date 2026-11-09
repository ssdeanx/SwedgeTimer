# Filing note (orchestrator, 2026-10-19)
Lane `feature-proctor` (session ses_eac70cf7cffes5O2sznCOWvgui) completed read-only but had no write-capable tool in its session, so it could not create this file, `desks/feature-proctor/journal.md`, or its signal JSON. Body below is the lane's returned text verbatim. Treat this file as the lane's done-signal content.

---
### Test Coverage Analysis: Feature Proctor Audit 2026-10-19 (SwedgeTimer 2.1.0, 35/0 harness)

#### Scope

**Files changed:** 0 (read-only audit of the current tree; no PR diff — full feature set as of 2.1.0)

**Relevant test files inspected:** 12 directly (full read) + 6 by header/spot-check

**Test files added or modified:** 0

**Test surfaces examined:** Unit / Integration / Contract / Static-wiring / TOC-matrix

Direct reads: `tests/run.sh`, `tests/smoke.lua`, `tests/toc_check.lua`, `tests/twist_state.lua`, `tests/weave_state.lua`, `tests/nextaction_state.lua`, `tests/swing_source_state.lua`, `tests/enemy_swing_state.lua`, `tests/weave_range_state.lua`, `tests/main_init_state.lua`, `tests/secret_guard_state.lua`, `tests/lrc_guard_state.lua`, `tests/diag_state.lua`, `tests/guide_contract.lua`, `tests/wiring_check.lua` (large — sampled §§0-6), `bench/verify_bank.md`, `bench/oracle_audit_2026-10-17.md`, `TESTING.md`, `desks/journal.md`, `bench/lessons.md`, `hands-up.md`.
Spot-checked headers: `tests/bars_state.lua` (1-60), `tests/hud_state.lua` (1-60), `tests/practice_state.lua` (1-60).
Feature files referenced (read-only, via grep + cited lines): `compat.lua`, `main.lua`, `bars.lua`, `swing_source.lua`, `enemy_swing.lua`, `weave_range.lua`, `twist.lua`, `weave.lua`, `nextaction.lua`, `classes/paladin.lua`, `config_presets.lua`.

#### Summary

The offline harness is unusually strong for a WoW addon: 35 steps / 0 failed + `luacheck` 2/0 claimed in `desks/journal.md`, pure-logic suites (`twist`/`weave`/`nextaction`/`practice`) with per-case pins, execution suites that load the **real** modules (`main_init`, `bars`, `hud`, `swing_source`, `enemy_swing`, `weave_range`, `guide_contract`, `secret_guard`, `lrc_guard`), a static wiring checker with non-vacuity floors and accepted-defect tracking, and a TOC matrix that pins per-flavor engine divergence in both directions. Mutation/bite proofs are the norm, not the exception (`secret_guard`, `lrc_guard`, `swing_source` §§8-11, `enemy_swing` §3).

That strength is concentrated on **pure helpers + one-module integration**. The highest remaining offline value is in **composition and family-matrix holes**: places where two pinned halves are never asserted together (lust scan → twist window; lag calibration → impossible warning; haste+MW+latency → weave prompt), and where two supported families (`CATA` project 14, `MISTS` project 19) never appear in any family-matrix test. None of these duplicate `TESTING.md` in-client steps — every proposal below is runnable today under `lua5.1` with the existing sandbox discipline.

**Overall Assessment:** ADEQUATE

The changed behavior of the last year (Forever engine, enemy swing, weave range, guides, HUD, practice, secret/LRC hardening, deadline rescue) is pinned against realistic regressions. The gaps below are real but none is a ship-blocker: they are ms-scale mistimings, silent inertness on two minor flavors, or re-introduction of a double-compensation the standing rules forbid. The owner in-client session remains the only place swing feel can be proven.

#### Coverage Mapping

| Changed Behavior | Relevant Test(s) | Coverage Status | Important Missing Scenario |
|---|---|---|---|
| Twist attempt/success core (numeric CLEU) | `tests/smoke.lua:745-815`, `tests/twist_state.lua:44-60` | Direct | None — two-seal/extra-attack/single-seal/combat-exit all pinned |
| Twist Anniversary string-payload fallback | `tests/twist_state.lua:62-76` (name path), oracle R1 | Direct (pure) | Live `spellId` slot-type still UNCONFIRMED in-client (correctly left to `TESTING.md:58-60`, not proposed here) |
| Twist window math (None/Dynamic/Fixed, caps) | `tests/twist_state.lua:78-86` | Direct | Composition with lag calibration + lust scale not pinned (G2/G3) |
| Twist impossible warning | `tests/twist_state.lua:88-104` | Direct | Wiring of `db.lag_multiplier/offset` into the call unpinned (G3) |
| Lust family gate + aura scan + R2 hole fix | `tests/smoke.lua:295-430` | Direct | End-to-end narrowing 0.4→0.24 through paladin gather → band unpinned (G2) |
| CLEU availability gate (classic vs Forever/Retail) | `tests/smoke.lua:398-410`, `tests/main_init_state.lua:886-913` | Direct | None — inertness pinned both directions |
| Weave math (haste/MW/cast-time/marker/safe-start/clip/spark/ICD/Flurry/DW/FS/SS/shields/MW5/positions/zone/totem/magma) | `tests/weave_state.lua:37-541` | Direct | Cross-term composition (haste+MW+latency→prompt) unpinned (G5) |
| Weave range band vs exact distance | `tests/weave_range_state.lua:46-479` | Direct | None — precedence, gates, throttle, wrapper degrades all pinned |
| Next-action engine (rotation/GCD/haste/seal/CS/fillers/B1-B5/ride/judge/JotC/Era/Forever/FCFS) | `tests/nextaction_state.lua:39-1026` | Direct | None at pure level — the most exhaustive suite in the tree |
| Guide frame contract + paladin provider parity | `tests/guide_contract.lua:268-1083+` | Direct + Integration | None — fake-provider, degenerate, gather, parity, and real-frame ticks all pinned |
| Forever swing engine (START/UPDATE/STOP/supersession/rescale/combat-exit/INIT/probe/family/Enum) | `tests/swing_source_state.lua:107-426` | Direct | None for Forever itself; Cata/Mists family inertness only partially covered (G1) |
| 5s deadline + late-library recovery + both-missing stand-in + idempotence + LGC-nil default + rf dead-man | `tests/main_init_state.lua:519-1070+` | Direct | None — the strongest integration suite; Cata/Mists engine selection not exercised (G1) |
| Enemy swing hostile-target bar | `tests/enemy_swing_state.lua:44-592` | Direct | None — static clock ban, pure helpers, driver, family matrix, probe dominance all pinned |
| Secret-value regime (cooldowns/LGC/power/auras/health/speed/haste/casts/range/creature/HUD) | `tests/secret_guard_state.lua:348-1120` | Direct | None — control+secret pairs throughout; hunter lane owns any residual error-path (see pointer) |
| LRC Mainline guards + bite proofs | `tests/lrc_guard_state.lua:216-469` | Direct | None |
| TOC load order + engine-per-flavor + Interface matrix | `tests/toc_check.lua:120-310` | Direct | Cata/Mists runtime behavior beyond "does not ship lib" unpinned (G1) |
| Event/dispatch/init-guard/api-contract/clock/hook-resolution | `tests/wiring_check.lua:§§1-6` | Contract | None — non-vacuity floors + ACCEPTED/stale reporting are exemplary |
| Bars OnUpdate + per-class widgets + family gates | `tests/bars_state.lua:1-60` (header) + wiring refs | Indirect | Twist-band lust-narrowed alpha + lag-calibrated impossible tint not isolated as a case (G2/G3) |
| HUD slots + trinkets + paladin provider | `tests/hud_state.lua:1-60` (header) | Indirect | No gap identified from header; full read deferred |
| CATA (14) / MISTS (19) runtime family | none found | No identified coverage | Family mapping + spell-id + engine selection (G1) |
| Player combat-enter/exit swing continuity | `tests/main_init_state.lua:§5` (guards), `tests/enemy_swing_state.lua:488-497` (enemy only) | Partial | Player mainhand/offhand cycle across REGEN_DISABLED/ENABLED unpinned (G4) |
| Deadzone vs lag-calibration separation | `AGENTS.md:52` (rule), `tests/twist_state.lua` (pure) | Uncertain | No pin that the twist path uses lag keys and *not* deadzone (G6) |

#### Critical Gaps — Rating 9–10

None. No data-loss, security-bypass, load-error, or broken-core-loop gap survived the search — the family gates are probe-first, the deadline rescue is executed, the secret guards degrade to no-ops with bite proofs, and the TOC matrix fails in both directions (missing line or wrong engine library). Withdrawing a critical finding is the honest result here.

#### Important Improvements — Rating 7–8

**Gap 1: CATA / MISTS runtime family never exercised (project 14/19)**

**Rating:** 7/10

**Location:** `compat.lua:family detection` (~11509/20506/38002/16001 branches + `WOW_PROJECT_*` constants); `main.lua:swing-engine selection`; `tests/smoke.lua:121-290`; `tests/main_init_state.lua:860-913`; `tests/toc_check.lua:233-255,632-638`

**Existing Coverage:** `toc_check` pins that `SwedgeTimer_Cata/Mists.toc` do *not* ship `LibClassicSwingTimerAPI` and `diag_state` renders all eight families as strings. `smoke` covers ERA(2)/TBC(5)/WRATH(11)/FOREVER(18)/RETAIL(1)/legacy-20506/legacy-16001/Titan-38002 but never builds a `project=14` or `project=19` profile. `main_init` covers vendored/forever/forever-inert/absent+Retail but never a Cata/Mists boot.

**Risk:** A wrong family string or a truthy `lust_supported`/engine branch on Cata/Mists is a silent in-client no-op or wrong-engine selection (vendored lib expected absent → stand-in expected). The TOC half is pinned; the runtime half is not, so a compat refactor that maps 14/19 to the wrong bucket passes 35/0.

**Suggested Test:** Extend the `smoke.lua` client-profile block with two profiles (`project=14`, `project=19`, no `C_Spell` DB): assert `family` is `CATA`/`MISTS`, `is_mainline==false`, `gcd_probe_spell_id==29515`, `get_family_spell_id` resolves the TBC-era rank set, and `lust_supported==true`. Add one `main_init_state` boot per family asserting `swing_engine=="inert-standin"` + single engine notice (mirroring the `absent` case), proving the lib-absent flavors degrade instead of indexing nil spell tables.

**Priority Rationale:** 7, not 9: Cata/Mists are live supported flavors per the base TOC matrix, the failure is silent, and the test is cheap (two profiles + two boots, zero new harness). Downgraded from critical because the TOC direction already fails loudly and Retail/Forever stand-in paths prove the mechanism.

**Gap 2: Lust scan → twist-window narrowing is pinned only in halves**

**Rating:** 7/10

**Location:** `classes/paladin.lua:1035-1055` (`get_twist_window_time_before_swing` + `apply_lust_window(window, lust ~= nil)`); `nextaction.lua:331` (`apply_lust_window`); `tests/smoke.lua:329-396`; `tests/nextaction_state.lua:970-980`; `tests/bars_state.lua:§3` (twist band alphas)

**Existing Coverage:** `smoke` pins the scan math (remaining/stacks/hole/clamp/C_ path). `nextaction_state` pins the pure 0.6× scale (`LUST_TWIST_WINDOW_SCALE==0.6`, 0.4→0.24, passthrough on false/nil). What is *not* pinned is the composition the player feels: a live Bloodlust aura → `lust ~= nil` → narrowed window → narrower twist band + earlier HOLD at ms scale (Era never narrows). `bars_state` drives the band through the CLEU chain but the lust-active case is not isolated as a scenario in the sampled header.

**Risk:** A wiring slip (wrong predicate, unthrottled scan, scale applied twice or not at all, Era narrowing) changes the twist decision by up to 160 ms on a 400 ms window — the exact split-second behavior the proctor brief calls out — while every existing twist/lust test stays green.

**Suggested Test:** `paladin_state`-style sandbox: stub `UnitAura` with `{2825, duration 40, expiration now+30}`, run `on_aura_change` + `get_twist_window_time_before_swing`, assert the window is `0.6 × base` (and `== base` with no aura / on ERA family). Optionally one `bars_state` tick asserting the band width/alpha follows the narrowed window. Keep the Anniversary `/dump` question in-client per `TESTING.md:58-60` — do not duplicate it.

**Priority Rationale:** 7: top-level parse impact (P3 is a STANDARD top-parser behavior per `verify_bank`), regression likelihood is real (two-file composition across throttle + pure helper), and the pin shape is already proven by neighboring suites.

#### Moderate Improvements — Rating 5–6

**Gap 3: Twist lag-calibration wiring (`lag_multiplier`/`lag_offset` → window → impossible)**

**Rating:** 6/10

**Location:** `classes/paladin.lua:1043` (`raw_ms * (db.lag_multiplier or 1.4) + (db.lag_offset or 15)`), `paladin.lua:1365-1367` (`is_twist_impossible(..., db.lag_multiplier, db.lag_offset, window)`); `config_presets.lua:443-444`; `tests/twist_state.lua:78-104`

**Existing Coverage:** `twist_state` pins every pure branch including nil-multiplier fallback, caps, and boundary strictness. What is unpinned is the paladin getter that feeds them: custom `db` values, nil-db defaults (1.4/15), and the no-double-deadzone rule from `AGENTS.md:52`.

**Risk:** A default change, key rename, or deadzone double-apply shifts the impossible warning by tens of ms at the exact moment the guide says HOLD — either spurious holds or missed twists — with all pure tests green.

**Suggested Test:** Sandbox `get_twist_window_time_before_swing` + `is_twist_impossible` inputs over a stubbed `world_ms`: (a) defaults 1.4/15 reproduce the pinned baseline; (b) `lag_multiplier=2.0/offset=0` widens the impossible region predictably; (c) deadzone value varied independently does not move the window (static + execution pin for the ban).

**Priority Rationale:** 6: ms-scale, top-level (P1 hit-rate is a differentiator), offline-cheap, and the rule is already written down — it just has no executable guard.

**Gap 4: Player swing continuity across combat-enter/exit**

**Rating:** 5/10

**Location:** `main.lua:977-987` (`PLAYER_REGEN_ENABLED/DISABLED` → `on_combat_exit`); `classes/paladin.lua:1454`, `classes/warrior.lua:539`, `classes/shaman.lua:864`, `classes/hunter.lua:467`, `classes/druid.lua:257`; `tests/main_init_state.lua:§5`; `tests/enemy_swing_state.lua:488-497`

**Existing Coverage:** Pre-init/init-window guards are pinned (no frame touches, no hook reach). Enemy-swing cycle clear/hide/re-show on combat exit/re-entry/world-entry is pinned thoroughly. The *player* mainhand/offhand cycle across the same transitions (no stuck full bar, no double STOP, timers shifted not expired — the behavior `TESTING.md:100` checks in-client for practice) has no isolated offline case found.

**Risk:** A combat-exit handler that drops or duplicates the player cycle produces a frozen or instantly-expiring bar on the next pull — silent (nil-guards render nothing) and class-agnostic.

**Suggested Test:** `main_init`-style boot to ready, seed `mainhand.{start,speed,ends_at}`, fire `PLAYER_REGEN_DISABLED` → `PLAYER_REGEN_ENABLED` → target-change, asserting exactly one inactive/active transition, cycle preserved-or-cleared per the documented contract, and no frame error. Mirror the enemy-swing §2 shape but against `ST.mainhand`.

**Priority Rationale:** 5: meaningful edge, integration-realistic, but the enemy-swing precedent proves the pattern and the in-client checklist already covers the visible half.

**Gap 5: Weave cross-term composition (haste × MW × latency → marker/prompt)**

**Rating:** 5/10

**Location:** `weave.lua:get_effective_cast_time/get_marker_fraction/get_safe_start_in/is_clipped/get_spell_position_state/can_prompt_weave`; `classes/shaman.lua:366-376,refresh_weave_haste`; `tests/weave_state.lua:67-136,414-435`; `tests/bars_state.lua:§3` (breakpoint marker + spark)

**Existing Coverage:** Every function is pinned in isolation with NaN/nil/negative/clamp cases, and `bars_state` drives the marker/spark/ICD widgets. What is unpinned is a single realistic composition, e.g. 30% haste + 3 MW stacks + 100 ms latency on a 2.6 s swing → effective cast → marker fraction → `ready` vs `clip` verdict.

**Risk:** An argument-order or unit slip (ms vs s, haste mult vs amount, MW mult applied twice) preserves every unit test while moving the breakpoint marker by a few hundred ms — the difference between a safe weave and a clipped swing.

**Suggested Test:** Three `weave_state` composition cases (0-stack LB baseline, 3-stack with haste+latency, 5-stack instant short-circuit) asserting `get_effective_cast_time` → `get_marker_fraction` → `get_spell_position_state`/`can_prompt_weave` end to end. No in-client duplication (live-swing feel stays in `TESTING.md:64-66,90`).

**Priority Rationale:** 5: moderate impact, high offline-testability, near-zero maintenance (pure functions, no frames).

**Gap 6: Deadzone/lag double-compensation ban has no executable pin**

**Rating:** 5/10

**Location:** `AGENTS.md:52`; `option_tables.lua:1701-1732`; `bars.lua` deadzone width; `classes/paladin.lua:1043`

**Existing Coverage:** Rule is documented; `twist_state` pins the lag side; `bars_state` pins deadzone width from latency. No test asserts the two calibrations are independent (twist uses lag keys only).

**Risk:** Applying both calibrations to the twist path double-penalizes high-ping players at exactly the 0.4 s window scale.

**Suggested Test:** Static pin (twist path references `lag_multiplier`/`lag_offset`, never `deadzone`) + one execution case varying deadzone alone with window fixed. Fold into Gap 3's proposed suite to avoid a new file.

**Priority Rationale:** 5: cheap, prevents a specific standing-rule violation, but the bug has not been observed — insurance, not repair.

#### Lower-Priority Observations — Rating 1–4

- **Rating 4 — SoD spell-id resolution under classic `GetSpellInfo` with partial rank knowledge.** `swing_source_state.lua:374-387` pins the Forever `C_Spell` highest-known-wins + all-unknown→nil fallback. The classic-line equivalent (Era/SoD profile with only SoD ranks known, e.g. `ERA_RANKS` in `smoke.lua:107-111`) is covered for HS/Maul/Cleave but not asserted as a *fallback contract* (unknown→nil so callers keep rank-1). **Benefit:** closes the last rank-resolution direction. **Recommendation:** Optional — one `smoke` assertion (`get_family_spell_id({48480,26996}) → nil` already exists at `smoke.lua:190`; promote the comment to a named fallback contract). **Reasoning:** low marginal value; the mechanism is already proven on both sides.
- **Rating 3 — `hunter_multi_target` inert toggle readability.** `oracle N3` documents it as deliberately inert (H3 engine is a future round). No behavioral test can pin an unwired toggle beyond the options-load shape. **Recommendation:** Defer to the engine round or append "(future)" copy per the oracle note; do not add coverage now.
- **Rating 2 — Twist sound map / rotation-text display names / ICD constants.** Pinned (`guide_contract.lua:663-664`, `nextaction_state.lua:946-963`, `weave_state.lua:160-167`). No further coverage warranted. **Recommendation:** Skip.
- **Rating 1 — Exact `Interface` numbers for future patches.** `toc_check.lua:260-299` pins 11509/20506/38002/16001/120100/120105 and rejects 30401. Adding speculative future Interfaces would churn on every patch. **Recommendation:** Skip; update only on owner-confirmed matrix changes (per the 120105 precedent).

*Hunter-lane pointer (per brief §Method, one line): any error-path hardening beyond the secret/nil guards above (throwing readers, hostile metatables, absent-addon degradation) belongs to the hunter lane — proctor found no uncovered error path that is not already a hunter-owned shape.*

#### Test Quality Issues

No material quality issue found. The suites are behavior-focused (observable outcomes, not internals), resilient (sandbox + fake clock + captured timers, not wall-clock), and bite-proven (guard-stripped `/tmp/opencode` copies in `lrc_guard`/`secret_guard`; count pins with explicit mutation rationale in `bars`/`hud` reconcile notes). Assertions verify outcomes (remaining seconds, window fractions, fade targets, swipe anchors, frame counts, notice text) rather than "runs without error" alone. Independence is good (throwaway client per `make_client`/`build`/`make_sb`; `for k in pairs(out)` table reuse hygiene in `nextaction`).

Two watch-items, neither rated above 3:

- **Clarity (Rating 3):** `tests/main_init_state.lua` (~1070+ lines) and `tests/guide_contract.lua` (~1080+ lines) are long because they pin long arcs — justified, but future editors should keep the numbered-section headers (§1–§10) since they are the only map. No change proposed.
- **Resilience (Rating 2):** `tests/toc_check.lua:233-255` hard-codes the three classic-line TOCs that ship the swing library. Correct today (Cata/Mists tables are nil), but a future lib fix that enables Cata/Mists would require touching both the TOCs and this pin — intended coupling, already commented. No change proposed.

#### Positive Observations

- `tests/smoke.lua:372-396` — the R2 secret-hole regression test (lust below a secret row still found) is the ideal regression pin: minimal, named, and tied to the oracle finding.
- `tests/swing_source_state.lua:§§8-11` + `tests/enemy_swing_state.lua:§§8-11` + `tests/enemy_swing_state.lua:§3` — family-gate-dominates-probe in both directions, Enum-absent fallback, and attack-speed shape immunity are exactly the Forever-vs-classic discipline the standing rules demand.
- `tests/main_init_state.lua:§§9-10` — the LGC-nil crash found *by the suite* and the rf-update dead-man are proof the harness catches real defects, not counts.
- `tests/lrc_guard_state.lua` + `tests/secret_guard_state.lua` — static-count pins plus guard-stripped bite proofs with honest control/secret pairs; the standard every new guard should meet.
- `tests/wiring_check.lua` — non-vacuity floors, ACCEPTED-with-reason + stale-accept reporting, and the clock/API double-report ban show how to keep static checks honest.
- `tests/nextaction_state.lua` + `tests/guide_contract.lua` — pure-engine exhaustiveness plus provider→frame parity (including Era/Forever/Retail branches and the HoW slot) is the deepest behavioral coverage in the tree.

#### Recommended Priority

1. Gap 1 (Cata/Mists runtime family + engine selection) — closes the only unsupported-flavor hole; cheapest rank-7 available.
2. Gap 2 (lust → twist-window composition) — highest ms-scale parse value.
3. Gap 3 (+ Gap 6 folded in: lag-calibration wiring + deadzone independence) — one suite, two bans.
4. Gap 5 (weave cross-term composition) — three pure cases, zero frames.
5. Gap 4 (player combat-enter/exit continuity) — mirror the enemy-swing shape for the player cycle.
6. Optional: the Rating-4 rank-fallback contract promotion. Skip Ratings 1–3 unless the hunter lane or owner session surfaces them.

#### Limitations

- No suite was executed; the 35/0 + 2/0 baseline is taken from `desks/journal.md:8` (verified in-tree 2026-10-17, four times) and not re-proven here.
- `bars_state`, `hud_state`, `practice_state`, `wiring_check` (tail), `guide_contract` (tail), and the class `*_state`/`*_guide_state` suites were header/spot-checked, not fully read — a full-read pass could promote or retire Gaps 2–5.
- Family-matrix claims for Cata/Mists rest on TOC + compat text, not on a live 14/19 client; SoD behavior rests on the ERA-family + rune-latch model per `weave_state.lua:369-375`.
- In-client timing feel, `/dump` slot types (R1), live lust/haste windows, and all `TESTING.md` visuals are explicitly out of scope and were not duplicated.
- Desk mechanics (`bench-read`/`desk-open`/`desk-journal`/`signal-write`) could not be executed — no write-capable tool is available in this session. This report is delivered as the proctor response for the orchestrator to file and reconcile against the hunter lane (every gap above carries feature→pin→gap + rank + proposed pin shape as required).
