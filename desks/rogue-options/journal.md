# rogue-options — Journal

## 2026-10-19 — Desk opened (Round 2, brief_rogue-options-parity_2026-10-19)
- **Purpose:** writer lane bringing the ROGUE options panel to parity with SHAMAN/WARRIOR.
- **Scope:** ONLY `config_presets.lua` `ST.ROGUE.defaults`, `option_tables.lua`
  `ST.class_opts_funcs.ROGUE` (+ its `hud_rotation_widgets` call args), and
  `tests/options_load_state.lua`. `compat.lua` / `classes/rogue.lua` read-only
  (parallel compat lane) — key mismatches reported in the done signal, not edited.
- **Next step:** bench-read done (journal, readiness §§3-2/3-3, cues + practice lane
  journals, rogue_state source pins, lessons); implement panel↔defaults round-trip.

## 2026-10-19 — Lane complete (ROGUE panel parity)
- **Worked on:** per `bench/briefs/brief_rogue-options-parity_2026-10-19.md`, only the three
  scoped files. `config_presets.lua` ROGUE defaults: added `show_rogue_ss_window`/
  `show_rogue_swap_cue`/`show_rogue_poison_cue` (false) + their colours, `rogue_ea_duty`
  (false), and the six guide thresholds with the engine constants (4/8/5/3/2/40; sibling
  pattern); de-sliced comments; CRLF kept. `option_tables.lua` ROGUE section: stale copy
  replaced with shipped reality (energy spark/tint, HUD glow), new "Guide Thresholds"
  ranges (nil-safe getters: db -> engine constant -> literal), new "Post-swing & Weapon
  Cues" section (SS window / swap / poison, family+cost copy), `rogue_ea_duty` toggle,
  NAG renumbered 4.x with POOL/NOW + "…" copy; LF kept. `tests/options_load_state.lua`:
  Rogue added to the HUD/rotation parity loop (section 4) + new section 9 pinning
  class-key -> panel -> defaults round-trip (23/23 keys), handler get/set resolution,
  toggle/colour/range/input round-trips, colour disabled-gating, copy scan (no
  future-slice wording), thresholds == rogue_guide constants; rogue_guide.lua added to
  the sandbox MODULES.
- **Current state:** `lua5.1 tests/options_load_state.lua` 919/0; `bash tests/run.sh`
  37 steps/0 failed; luacheck 2 warnings/0 errors (floor; one mid-run 6-warning read was
  the parallel compat lane's transient flap). Mutation proofs 9/9 bitten on
  `/tmp/opencode/rogue_options_mut` (script `/tmp/opencode/muts_rogue_options.py`),
  restored copy green. Artifact: `bench/buildout_rogue-options_2026-10-19.md`.
- **Key mismatch (reported, not edited):** 10 inert keys ship in panel+defaults with no
  consumer in `classes/rogue.lua` — the skeleton's Slice-A cue placeholders
  (`show_rogue_snd_cue`/`rogue_snd_color`, `show_rogue_rupture_cue`/`rogue_rupture_color`,
  `show_rogue_ea_cue`/`rogue_ea_color`, `show_rogue_shiv_cue`/`rogue_shiv_color`,
  `show_rogue_tea_cue`/`rogue_tea_color`); the cues lane delivered upkeep as HUD slots +
  guide actions instead. No consumed key is missing from the panel.
- **Next step:** orchestrator validation (round-trip + copy + mutations), then decide the
  orphan-key row (wire in a class lane or strip) at reconcile.

## 2026-10-19 — [signal:done] ROGUE options parity shipped to the bench
- Signal file: `desks/rogue-options/.signals/2026-10-19T11-35-15Z.json`.
- Handoff: `bench/buildout_rogue-options_2026-10-19.md` (files, key coverage, mismatch
  note, validation, mutation proofs).
