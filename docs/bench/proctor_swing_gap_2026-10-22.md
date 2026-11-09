# Proctor test-gap audit — swing engine (2026-10-22)

Lane: background proctor, no write scope. Report filed by orchestrator after
verifying each checkable claim against the tree (see verification notes at end).
Validation owner: orchestrator. **Nothing here proves the bars work.**

## Coverage: what each suite actually feeds

| Suite | Engine shape | Registry path | Hands driven | Families driven |
|---|---|---|---|---|
| `main_init_state.lua` §14b | **Stub** (`vendored_engine`: fixed `SwingTimerInfo` triple, zero lib logic) | **Direct** `T.callback_event_handler(...)` calls — bypasses CallbackHandler entirely | **ranged only** (§14 adds one valid `mainhand` START/STOP + bogus-hand guards, still direct-call) | **One TBC-shaped fixture** (`project=5/interface=20506`); the "Forever wire" is an arg-shape on that fixture, not a Forever boot |
| `real_wire_state.lua` | **Real** vendored lib (minor-32 pinned) + real `main.lua` via real `LibStub` | **Real shipped v7** (minor-7 pinned; six regs asserted by object identity, `assert_six_in_lib_registry`) | **mainhand + ranged only.** `UnitAttackSpeed` returns no offhand (`2.6, 0`); no offhand CLEU ever sent; no STOP ever driven or asserted | **era / anniv(1) / anniv-nil(xfail) / d8-era-profile only.** No Wrath, Cata, Mists, Retail, Forever leg |
| `swing_source_state.lua` | **Real `swing_source.lua`**, stub frame/timers | **Fake registry** (records `Fire`, forwards function callbacks — mimics the CBH calling convention but is **not** the shipped v7 `Dispatch`→xpcall path) | mh + oh + ranged mapping pinned, incl. B1 nil-shape for all hands | **FOREVER only** (+ inert pins for ERA/WRATH/RETAIL; no Cata/Mists/anniv/era-live legs) |
| `run.sh` | Runs all of the above (`real_wire_state` is step line 89); no `swing_engine_state` step exists | — | — | — |

`tests/swing_engine_state.lua` **does not exist** — nothing to audit there.

## Coverage map per hand per family (C=covered, S=stub-only, M=missing)

| Family | mainhand | offhand | ranged |
|---|---|---|---|
| Era | **C** (seed + CLEU `SWING_DAMAGE` advances) | **M** (never driven through the real lib) | **C** happy-path only (negatives unpinned) |
| TBC Anniversary | **C** happy-path only (anniv(1) `SWING_DAMAGE` advances) | **M** | **Partial** (anniv(1) happy shape advances; anniv-nil recorded EXPECTED-FAIL per D2/HU-29; TBC-only driver negatives **M**) |
| Wrath | **M** | **M** | **M** |
| Cata / Mists | S-by-design (`engine_dead` path in `main_init` stub fixtures; no real leg — correctly low value, lib isn't shipped there) | same | same |
| Retail | **S-only** (`main_init` absent-engine → inert-standin + one notice; no Retail leg in `real_wire`) | S-only | S-only |
| Forever | **S-only** (`swing_source_state` via fake registry; `main_init` forever/source fixtures via stub `source_engine`; no Forever leg in `real_wire` — the real-CBH→real-dispatcher joint is never executed) | S-only | S-only |

## The 10 named real paths: verdicts

1. **TBC SUCCEEDED(75)+START_AUTOREPEAT-only ranged — PARTIAL.** Anniv(1) happy leg drives exactly this. **Missing:** the negatives — SUCCEEDED(75) *without* autorepeat, autorepeat *without* SUCCEEDED, `CAST_START` must NOT drive ranged on TBC (`isClassic` gate, lib:454–464), `FAILED_QUIET` must NOT fire the hidden-cast update on TBC (lib:767–784). Era never drives `CAST_START`/`FAILED_QUIET` either, so the family-divergent driver table is unpinned; a gate swap stays green.
2. **The .5s hidden-cast window — ZERO.** No suite fires `FAILED_QUIET` or `START_AUTOREPEAT_SPELL`-then-`FAILED_QUIET` and asserts `expiration = now + 0.5 + autoShotCastTime` (lib:776) or the `0.52 * (rangedSpeed/rangedBaseSpeed)` rescale (lib:174, 760). The constants (0.5, 0.52) appear in no test.
3. **SWING_MISSED offhand-flag juggling — ZERO.** `real_wire` sends only `SWING_DAMAGE`. The lib re-reads the offhand flag from the `overkill` slot on MISSED (lib:397–401); a regression routing every miss to mainhand stays green on all families.
4. **PARRY arm reachability — ZERO, unreachable by construction (D4).** No suite sends `SWING_MISSED`/`PARRY` at all. A pin written today would encode dead behavior — must land *with* the HU-29 fix (red-first or second xfail, same pattern as D2).
5. **SPELL_EXTRA_ATTACKS absence — ZERO** (lib has no such handler; confirmed by grep). Windfury/sword-spec double-starts unpinned; no counterpart to the reference addon's suppression and no test. Red-first/xfail shape pending HU-29.
6. **Equipment-change re-probe — ZERO through the real lib.** `real_wire` never fires `PLAYER_EQUIPMENT_CHANGED`/`UNIT_ATTACK_SPEED`. `main_init` F2/§15 covers only the app side (stub engine, no re-seed assertion). `swing_source` B2 covers only the Forever `WEAPON_SLOT_CHANGED` path. The lib's all-hands `SwingStart` + ranged-base re-read (lib:726–738) is unexecuted.
7. **Login UNIT_ATTACK_SPEED burst — ZERO.** `real_wire` seeds via `init_timers` but never delivers `UNIT_ATTACK_SPEED`; the lib's proportional rescale incl. the `UnitRangedDamage` re-read (lib:468–537) is unexecuted. `main_init` uses `UnitAttackSpeed` as a static presence probe only.
8. **Hand-only STOP passthrough — ZERO through the real registry.** `main_init` §14b pins it only via direct `callback_event_handler` (stub path). `real_wire` never produces a STOP (clocks never pass an expiry; no `SwingEnd` awaited). A dispatcher regression eating hand-only STOPs through real v7 `Fire` freezes bars full with no failing test.
9. **Retail inert stand-in — STUB-ONLY.** Covered in `main_init` (absent engine → `inert-standin` + one notice, project 1). No Retail leg in `real_wire`. Low value (nothing *can* fire), but the "expected dead" leg is absent from the real harness.
10. **Forever PLAYER_SWING mapping — STUB-REGISTRY ONLY.** `swing_source_state` pins mapping/supersession/rescale/combat-exit STOP/INFO-once/Enum-fallback/B1–B3 thoroughly, but through the fake registry; no Forever leg in `real_wire`. The Forever `Fire(speed, expiry, hand)` → real v7 → real dispatcher → bar-state joint is never executed end-to-end.

## Top-3 missing pins (ordered by regression risk)

**Pin 1 — TBC ranged driver table through the real lib + real v7 (highest — the reported failure).**
Anniv-profile legs: (a) SUCCEEDED(75)+autorepeat advances ranged (exists — keep); (b) SUCCEEDED(75) *without* prior autorepeat does not advance; (c) `CAST_START` with a ranged spell does not advance ranged on anniv while it *does* (UPDATE with `autoShotCastTime`) on era; (d) `FAILED_QUIET` does not touch ranged on anniv while it sets the 0.5s window on era. **Why:** the current anniv(1) leg cannot distinguish "TBC wire correct" from "Era wire applied to TBC" — the D2 confusion surface, and the exact symptom (ranged dead, melee alive) the operator reported. Cost: small.

**Pin 2 — Full swing lifecycle per hand through the real v7 registry, incl. offhand and hand-only STOP (high — silent full-bar freeze).**
Era-profile legs: drive `START→UPDATE→hand-only STOP` for mainhand *and* offhand (needs an offhand-speed fixture — currently hardcoded `2.6, 0`), run the deferred STOP timer, assert the bar marks full; assert wire counters and `swing_last` diag agree. **Why:** STOP is the only hand-only payload and the strip's riskiest branch (M2 exists only at stub level); offhand is *entirely undriven* in the real harness. Cost: small–medium.

**Pin 3 — MISSED routing + PARRY + EXTRA_ATTACKS documented-behavior pins, red-first/xfail pending HU-29 (medium-high — silent wrong-hand bars, haste jitter).**
Real-lib legs: `SWING_MISSED` (main + offhand slots) routes to the correct hand; `SWING_MISSED`/`PARRY` and synthetic `SPELL_EXTRA_ATTACKS` pinned as EXPECTED-FAIL (same `xfail` mechanism as D2) so the ruled fix flips them green. Do NOT pin current dead-arm behavior as PASS. Cost: small.

*Deliberately not top-3:* equipment re-probe + login attack-speed burst (medium — `main_init` F2 + `swing_source` B2 cover the app/Forever halves); exact 0.5s/0.52 constants (medium — subsumed by Pin 1(d) if the window leg asserts expiry); Retail inert leg (low); Forever real-registry joint (medium — fake-registry suite thorough; residual risk is v7-`Fire` convention drift); Wrath leg (blocked on U-W1 ground truth); Cata/Mists eyeball (in-client only).

## MISSING-KNOWLEDGE

**Closable offline:** all pins above — the sandbox already scripts CLEU/`C_Timer`/project IDs; MISSED/PARRY/EXTRA_ATTACKS are plain `CombatLogGetCurrentEventInfo` tuples; offhand needs only a two-speed `UnitAttackSpeed` fixture; STOP needs clock advancement past expiry.

**Needs in-client evidence (no offline pin can close):** U2 (Anniversary `LE_EXPANSION_LEVEL_CURRENT`/project ground truth via `/st diag proj=/exp=/bcc=` — decides whether D2's xfail is permanent); U3 (`SUCCEEDED(75)` delivery + `UnitRangedDamage` shape on 2.5.6); U-H8/D10 (stale-copy ranking — whether the operator's folders carry the strip); U-H5 (Forever in-client swing proof); U-W1 (Wrath beyond the project half); U-H6 (LRC on Anniversary); U-H7 (Cata/Mists "engine offline" eyeball).

**Test-quality note (no finding filed):** `real_wire_state` is DAMP-clear; `main_init` §14b's direct-dispatch pins are honest stub tests misreadable as wire tests — recommend a one-line comment at §14b stating it bypasses the registry (real-registry counterpart is Pin 2 here), not a rewrite. `swing_source_state`'s fake registry is a faithful calling-convention double, but its fidelity claim should cite the v7 `Dispatch`→xpcall path explicitly so a future v7/v8 swap re-examines it (HU-28 context).

## Orchestrator verification notes (2026-10-22)

Claim-checks run against the tree before filing; all hold:
- `tests/swing_engine_state.lua` absent; `tests/run.sh` has no such step (`real_wire` is the line-89 step).
- `real_wire_state.lua:220` — `UnitAttackSpeed` returns `(2.6, 0)` with an explicit "no offhand weapon" comment; no `FAILED_QUIET`/`CAST_START`/`MISSED`/`PARRY`/`EXTRA_ATTACK` string anywhere in the file; the three-hand loop at :412 builds stub bar frames only (no drive).
- `main_init_state.lua:786-825` — direct `T.callback_event_handler(...)` calls confirmed.
- `swing_source_state.lua:59` — fake registry confirmed ("records every call and forwards function callbacks… not the shipped v7 path" per its own header).
- v7 identity pin (`minor 7`) at `real_wire_state.lua:81`; `assert_six_in_lib_registry` at :497, exercised at :542/:595/:642.
