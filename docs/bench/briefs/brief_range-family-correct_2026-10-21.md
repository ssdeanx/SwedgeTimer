# Brief: range-family-correct (2026-10-21) — READY TO DISPATCH, AWAITING THE OPERATOR'S GATE

**Status: NOT DISPATCHED.** The operator was asked how the range should be derived and did
not answer. The standing rule ("no default-visible change without an explicit gate") applies:
every version of this lane changes what the bar's range readout prints on at least one
family. This brief is written and scoped so it can start the moment the operator says which
semantics they want.

## The problem
The range numbers and the melee/ranged flip points come from the vendored
`LibRangeCheck-2.0`'s **hardcoded distance table**:
`LibRangeCheck-2.0.lua:61-79` — `DefaultInteractList = { [3] = 8, [4] = 28 }` with race
overrides (Tauren `{3]=6, [4]=25`, Scourge `{3]=7, [4]=27}`). Those are the library author's
measurements from a *modern* client, not the running client's distances.

Two consequences the operator named on 2026-10-21 ("era inspect range is different"):
1. The numbers the bar prints (`bars.lua:952-966`, the `range_finder` text) are approximate
   on the classic families — they are not Era's or Anniversary's real distances.
2. The flip points follow the same table, so "in melee" means "inside the client's
   interact-3 band", whose yard meaning differs per family.

The pre-fix behaviour on Era was different (the library's spell checkers took their
boundaries from `GetSpellInfo` → per-expansion spell data), which is why the readout changed
when the blocked-call fix landed.

## What is already settled (do not re-litigate)
- The blocked-call fix stays (R1+R2+R7): no item checker, no spell checker, zero client
  range calls on any family. See `bench/range_lrc_guard_2026-10-21.md`.
- `compat.lua:978` already wraps `UnitDistanceSquared` → `api.UnitDistance(unit)` → exact
  yards, and the CHANGELOG records it answering on **Era, TBC Anniversary, Titanforge,
  Retail and WoW Forever**. `weave_range.lua` already uses it as its exact path, with the
  band as its fallback.
- The modern per-spell range API (`C_Spell.IsSpellInRange(spellID, unit)`, present on all
  five branches) is DEFERRED by operator order — its protected state is unverified
  (FU-1, `bench/range_api_matrix_2026-10-21.md` §5). It must NOT be wired in this lane.
- The client-side spell DATA is safe to read everywhere: `GetSpellInfo(spellId)` → minRange
  / maxRange, per expansion. That is a data read, not a range check.

## The three candidate semantics (the operator picks one)
**(a) Family-correct band.** The band boundaries come from the CLIENT's own spell data for
the running family (`GetSpellInfo` on the class's melee/ranged spell, resolved per family
through the class modules' existing per-family spell ids). The band readout stays a band
(e.g. "5 - 30" on Era), but the numbers are the family's own. The flip points follow the same
numbers, so "in melee" flips at the family's real melee reach.
**(b) Exact yards.** `api.UnitDistance("target")` drives both the readout (true yards, e.g.
"20 yd") and the flip points (compared against the family's spell ranges from `GetSpellInfo`).
Most precise; the readout changes shape from a band to a distance.
**(c) Keep the uniform interact bands.** Nothing changes; the coarseness is documented in
the CHANGELOG (already done).

## Scope / write permission (for whichever variant is chosen)
- Likely owners: `main.lua` (the range poll and the published state),
  `compat.lua` (only if a new wrapper is needed — `api.UnitDistance` already exists),
  the class modules that publish the per-family melee/ranged spell ids, `bars.lua` (only the
  readout text), `weave_range.lua` (its fallback path), and their suites.
- ONE writer per file. `tests/run.sh` and the TOCs belong to the orchestrator.
- No git. No lint-config changes. Line endings preserved. Warnings traced, never silenced
  with `_`. A user-visible change needs the operator's explicit gate recorded in the brief.

## Proof required
- The per-family spell data (min/max) for each class on each family must come from a
  citable source (the client's own spell data via `GetSpellInfo`, or the wow.export dump for
  1.15.9) — never a guessed number.
- Offline: the per-family ladder answers in an execution test per family profile, with the
  numbers pinned; MUTATION PROOFS on `/tmp/opencode` copies (no `Media/`, `docs/`, `.git`).
- The in-client confirmation is owed by the operator and must be listed in the report: the
  band/number the bar prints on Era, on Anniversary and on one modern client, against the
  real distance.

## Open question that only the operator can close
Whether the readout may change shape, and on which families. The operator was asked on
2026-10-21 and did not answer; the default is (c) — shipped, documented, no user-visible
change.
