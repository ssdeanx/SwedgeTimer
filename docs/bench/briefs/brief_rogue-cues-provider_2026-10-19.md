# Brief: rogue-cues-provider (Round 2 HELD — dispatch AFTER skeleton + pure reconcile, 2026-10-19)

## Objective
Slice B (tick + Era cue) + Slice C (provider/HUD-live) + TTD wiring. Single writer: everything here lands in `classes/rogue.lua` + `rogue_guide.lua`. HELD until Round 1 reconciles.

## Scope (ONLY these files)
- `classes/rogue.lua`: proc-aware 2 s tick predictor (Combat-Potency 15-energy grants NEVER re-anchor the clock — Yam rule, `bench/rogue_deep_2026-10-19.md` §2.2; ambiguous tick → nil/hidden, H4 rule); energy-tick spark + 65/85 pooling tint (data-driven); Era-only post-MH 0.1–0.2 s SS window (family-gated `_Vanilla` + sword-relevant loadout; NEVER on `_TBC`+); weapon-swap tint with GCD+reset cost in copy; MH/OH poison reminder (+charges where probe shape confirmed in-client); full `get_hud_state` live (SnD/Rupture/EA/AR/BF/Tea/Kick/trinkets); `gather_guide_inputs` live incl. `inputs_unknown` ownership (paladin `:2482,2749` pattern) + lust-unknown latch (M5 pattern, reuse `api.auras_may_be_secret()`); labels POOL/NOW overrides; TTD EMA wiring (druid D4 reuse) + M7 provenance guard (consume `live` provenance or own tracker, never fallback-2.0); `on_spellcast_event` ONLY if consuming casts (Tea/Shiv — with callee self-guard, H6 rule).
- `rogue_guide.lua` (extends Round 1 pure file): EA-duty/Shiv/Tea live rules only if they need engine-side changes; `nextaction.lua` stays untouched.
- Tests: extend `tests/rogue_state.lua` (predictor re-anchor cases, Era gate both directions, nil-tick hide, swap-cost copy, TTD/provenance refusal, "…" latch) + `tests/rogue_guide_state.lua` + `tests/guide_contract.lua` gather→evaluate→frame parity (degenerate inputs, latch).
- Explicitly OUT: `practice.lua`, `option_tables.lua` ROGUE-section copy, `diag.lua` (closed unless orchestrator opens), TOCs, version, CHANGELOG, `main.lua`/`bars.lua`/`compat.lua` (read-only reference).

## Law + rules
`st.api.get_time()` for timing; swing-activity gating (never `st.is_mainline` alone); secret-regime unknown rendering (M5); CLEU only with R1 id+name-fallback tables (default: no CLEU — aura/power/CP reads). Standing: no git/lint-config, wire-not-strip, touched-lines whitespace, CRLF, nil-safe toggles, harness green + luacheck floor + mutations.

## Mechanics
bench-read (journal, readiness §§2/4/5-B/C, both fix buildouts, research files, lessons, hands-up); desk-open `desks/rogue-cues/`; journal + `done` signal.

## Validation owner
Orchestrator: every cue pinned both directions (Era gate!), "…" + lust-unknown cases, provenance refusal, harness + mutations green.
