# Brief: rogue-parity (2026-10-19)

## Objective
Close the two rogue-vs-five-classes parity gaps in the class module. Writer lane.

## Gap 1 — rotation label provider (VERIFIED missing)
The frozen contract (`rotationtext.lua:18-24`): `ST.<CLASS>.get_rotation_key(self) -> key | nil`.
Implemented by all five siblings — PALADIN (`rotationtext.lua:222`), HUNTER
(`classes/hunter.lua:1337-1352`: action→localized ability name via slot
descriptors + name cache, hold→hold_text, else nil), WARRIOR
(`classes/warrior.lua:2733`), SHAMAN (`classes/shaman.lua:2616`), DRUID
(`classes/druid.lua:1993`). Rogue has none (grep-confirmed) while its options
panel already ships the shared rotation-label widgets — options present,
feature inert. Implement `ST.ROGUE.get_rotation_key` in `classes/rogue.lua`
following the hunter shape: resolve the guide's current action to the
localized spell name from `ST.ROGUE.guide.slots` descriptors (slots read at
`classes/rogue.lua:707+`: snd/rupture/ea/ar/bf/tea/kick/trinket1/trinket2),
return `hold_text` ("POOL") while holding, nil when idle/unknown. The guide
provider contract already supports labels (`nextaction_ui.lua:53`,
`:558-562`: POOL/NOW); `out.rotation_key` stays nil (`classes/rogue.lua:558`)
— the label is the action name, exactly like hunter.

## Gap 2 — ten inert cue keys (VERIFIED inert)
`show_rogue_snd_cue`/`rogue_snd_color`, `rupture`, `ea`, `shiv`, `tea` pairs
ship in `config_presets.lua:585-594` + the ROGUE options section
(`option_tables.lua` cues block `:4365+`, rows from `:4378`) with copy
promising upkeep cues — but `classes/rogue.lua` consumes only tick/pool/ss/
swap/poison (`:1016-1020`). Wire-not-strip: WIRE preferred — give each cue a
real consumer following the warrior/shaman cue patterns (read them in-lane:
warrior bank cue / battle-shout badge, shaman wf_hold_tint — trace, don't
assume). REMOVE only with an explicit rationale (e.g. HUD slots + guide
actions already cover it) AND full loop closure. Either way the lane ends
with zero inert keys.

## Scope
- `classes/rogue.lua` (both gaps live here — single writer, no one else touches it this wave).
- `tests/rogue_state.lua` (pins for both gaps), `tests/rotationtext_state.lua`
  (extend the provider loop at `:542-549` to all five...six classes with
  ROGUE cases mirroring the hunter idle/RIDE/named-action cases at `:552-570`).
- CONDITIONAL (cue-removal path ONLY): `config_presets.lua` (defaults),
  `option_tables.lua` (ROGUE rows), `tests/options_load_state.lua` (pins).
  No other lane owns these files this wave; if the wire path is chosen they
  stay untouched.
- Explicitly OUT: `diag.lua`, `rogue_guide.lua`, `compat.lua`, `practice.lua`,
  TOCs, `tests/run.sh`, version fields, CHANGELOG, all docs.

## Rules
No git. No lint-config. Wire-not-strip. Whitespace only inside touched
lines. Endings preserved — `file`-check each target first (lesson:
compat taught us never to assert CRLF blind). Nil-safe reads
(`== false` hides, nil = off); no default-visible change. New behavior
pinned + mutation-proven on `/tmp/opencode` copies (guard-strip must fail
the new pins). Full `bash tests/run.sh` green + luacheck floor (2/0) before
done. Timing via `st.api.get_time()`; swing-activity gating, never
`st.is_mainline` alone.

## Mechanics (skills: bench-read, desk-open, desk-journal, signal-write)
1. bench-read: `desks/journal.md`, `bench/rogue_readiness_2026-10-19.md` §§1-2,
   `bench/rogue_deep_2026-10-19.md` §4, `bench/lessons.md`, `hands-up.md`.
2. desk-open: ensure `desks/rogue-parity/` exists (journal.md + .signals/);
   resume if live. Confirm bench output name absent at start; if present,
   supersede with pointer (never overwrite).
3. desk-journal append + signal-write `done` JSON (files changed, cue
   wire-or-remove verdict with rationale, harness result).

## Validation owner
Orchestrator: rotation label renders the action name for rogue (parity with
hunter); zero inert cue keys with pins-or-rationale; harness + floor green.
