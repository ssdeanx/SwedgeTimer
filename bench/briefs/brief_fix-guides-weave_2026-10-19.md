# Brief: fix-guides-weave (2026-10-19)

## Objective
Fix the guides/weave/class-module half of `bench/feature_hunter_audit_2026-10-19.md` + close the proctor composition gaps. Writer lane.

## Scope (disjoint — ONLY these addon files)
- `weave.lua`: H4 (separate the signals — unresolvable base cast returns `nil`/unknown; `get_marker_fraction`/`get_spell_position_state` hide-or-dim the marker on unknown instead of rendering instant-0; keep the "never draw on a guess" discipline). Proctor G5: add 3 cross-term composition cases (0-stack LB baseline, 3-stack + haste + latency, 5-stack instant) end to end.
- `nextaction.lua` + `nextaction_ui.lua`: M6 (thread an `inputs_unknown` bit through `out` — guide renders "…" instead of an action when speed/G/seal are all defaulted — or cite the provider guarantee in-file with file:line).
- `classes/paladin.lua`: M3 (session `twist_unmatched_payloads` counter to `/st diag`, or document why the badge suffices), M4 (distinct "seal data unknown" band state when swing data unusable vs genuine single-seal, or cite the mirror-failure signal), M5-consumer (lust-unknown affordance, e.g. dimmed "?" while `C_Secrets` reports aura secrecy, or record the accepted residual), H6-half + M6-half (confirm/init-guard the provider gather nil-fields per the frozen spec `paladin.lua:1497-1528` — extend, don't re-derive), R4 (standardise `st.lust_supported == true`), proctor G2 (lust→0.6× window→band composition pin) + G3 (lag-calibration wiring pin incl. defaults 1.4/15, no deadzone double-apply per AGENTS.md:52; fold G6 static pin in).
- `classes/shaman.lua`: H4-catalogue side (resolve-or-nil contract toward `weave.lua`), catalogue-retry observability (confirm `diag`/chat footprint for sustained miss or accept hidden-with-retry as designed — hidden is the safe direction here).
- `classes/hunter.lua`: R4 lust-gate line ONLY (standardise on `== true`); nothing else in this file.
- `compat.lua` (bounded): observability-only additions for M5 (lust-unknown surfacing); the whole-entry secret-degrade rule itself (E2) stays untouched.
- Tests (pins for the above): `tests/weave_state.lua`, `tests/nextaction_state.lua`, `tests/guide_contract.lua`, `tests/secret_guard_state.lua`, `tests/paladin_state.lua`, `tests/shaman_state.lua`, `tests/hunter_state.lua`. New pins get mutation proofs on `/tmp/opencode` copies. Proctor G1 (Cata/Mists runtime profiles + engine selection) + G4 (player combat-enter/exit continuity): implement here (smoke profiles project=14/19, inert-standin boots, mainhand cycle transitions) — engine-selection assertions must not touch `main.lua`/`bars.lua` (read-only boot harness, same as existing `main_init_state` discipline).
- Explicitly OUT (owned by fix-engine-dispatch — touch it and you collide): `main.lua`, `bars.lua`, `swing_source.lua`, `enemy_swing.lua`, TOCs, version fields, CHANGELOG. G1/G4 pins stay in test files only.

## Standing rules
No git. No lint-config changes. Wire-not-strip. Whitespace only inside touched lines. Endings preserved (CRLF). New toggles nil-safe with documented defaults. Full harness green before done.

## Workshop mechanics (mandatory — skills: bench-read, desk-open, desk-journal, signal-write)
1. bench-read: `desks/journal.md`, `bench/feature_hunter_audit_2026-10-19.md`, `bench/feature_proctor_audit_2026-10-19.md`, `bench/lessons.md`, `hands-up.md`.
2. desk-open: ensure `desks/fix-guides/` exists; resume if live.
3. desk-journal append + signal-write `done` JSON listing every file changed + harness result.

## Validation owner
- Orchestrator: every item closes with file:line + harness proof + mutation proof, or a one-line justification citing the exact evidence line. Reconciles against fix-engine-dispatch (no shared files).
