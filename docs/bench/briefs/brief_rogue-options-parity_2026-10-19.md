# Brief: rogue-options-parity (2026-10-19)

## Objective
Bring the ROGUE options panel to full parity with the other five classes ("including in options" — owner directive). Writer lane, disjoint from the compat lane.

## Scope (ONLY these files)
- `config_presets.lua`: `ST.ROGUE.defaults` only — verify/fill class keys so EVERY rogue toggle reachable in the options panel round-trips; nil-safe (`== false` hides, nil = off); defaults documented; no default-visible change.
- `option_tables.lua`: `ST.class_opts_funcs.ROGUE` only (plus the shared `hud_rotation_widgets` call it makes). Fix stale copy (e.g. "the visuals land with the energy slice", "Slice A ships no glow cue" — the cues lane landed those; copy must match the shipped reality). Ensure every Round-2 opt-in key has a control: tick/pooling bands (data + colors), SnD/Rupture/EA/Shiv/Tea toggles+colors, swap-tint, poison-reminder, post-MH SS window, TTD, `inputs_unknown`/lust-unknown affordances — parity with the SHAMAN section shape (`:3930-4263`) and WARRIOR (`:2595+`). Nil-safe getters; `disabled = function()` gating on color rows consistent with siblings; slot toggles via the shared builder.
- `tests/options_load_state.lua`: pin the ROGUE section loads, every rogue key has getter/setter wiring, copy references only shipped features (no future-slice language), color rows disabled-gating; bite proof.
- If a key exists in `classes/rogue.lua` but nowhere in the panel (or vice versa): report it as a one-line note to the orchestrator in your done signal — do NOT edit `classes/rogue.lua` (compat lane owns it this round).
- Explicitly OUT: `compat.lua`, `classes/rogue.lua`, `practice.lua`, tests other than options_load_state, TOCs, version, CHANGELOG.

## Rules
No git. No lint-config. Wire-not-strip. Touched-lines whitespace. CRLF preserved. Harness green + floor + mutations. Parallel compat lane runs concurrently, disjoint files — transient flap expected, never edit outside scope.

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write)
bench-read (journal, readiness §3-2/§3-3, cues + practice lane journals for the keys they shipped, lessons); desk-open `desks/rogue-options/`; journal + `done` signal (files + key coverage list + any key-mismatch notes).

## Validation owner
Orchestrator: panel↔defaults round-trip complete for every rogue key, copy accurate vs shipped reality, harness green, mutations bite.
