# Buildout: rogue-options parity (2026-10-19)

Lane: rogue-options (writer). Brief:
`bench/briefs/brief_rogue-options-parity_2026-10-19.md`. Desk:
`desks/rogue-options/`. Scope held: ONLY `config_presets.lua` (`ST.ROGUE.defaults`),
`option_tables.lua` (`ST.class_opts_funcs.ROGUE` + its `hud_rotation_widgets` call
args) and `tests/options_load_state.lua`. `compat.lua` / `classes/rogue.lua`
read-only (parallel compat lane); practice/TOCs/version/CHANGELOG untouched.

## Files changed

- `config_presets.lua` — `ST.ROGUE.defaults` (CRLF preserved, 855->883 lines):
  - Added the consumed-but-undefaulted keys: `show_rogue_ss_window`,
    `rogue_ss_color`, `show_rogue_swap_cue`, `rogue_swap_color`,
    `show_rogue_poison_cue`, `rogue_poison_color` (toggles false = off;
    colours 0-255 RGB + 0-1 alpha).
  - Added `rogue_ea_duty = false` (Imp-EA duty opt-in; nil = off).
  - Added the six guide thresholds with the pure engine's own defaults
    (`rogue_rupture_refresh = 4`, `rogue_rupture_min_ttd = 8`,
    `rogue_finisher_min_cp = 5`, `rogue_ea_refresh = 3`,
    `rogue_shiv_refresh = 2`, `rogue_tea_energy_max = 40`) — matches the
    druid/shaman/warrior sibling pattern (`guide_rip_refresh` etc.).
  - Comments de-sliced: no "Slice A/B" or "this slice" wording left; the NAG
    note now says the provider reports `inputs_unknown` -> "…".
- `option_tables.lua` — `ST.class_opts_funcs.ROGUE` (LF preserved):
  - Energy copy: "the controls ship now, the visuals land with the energy
    slice" -> describes the shipped spark/tint + unknown-hides rule.
  - Cues copy: SS-window sentence moved out; keeps the shipped
    nil-safe/unknown-hides wording.
  - New: `rogue_ea_duty` toggle (2.6, distinct from the `show_rogue_ea_cue`
    cue row, renamed to plain "Expose Armor" to avoid a duplicate label).
  - New: "Guide Thresholds" header + six nil-safe ranges (2.71-2.76). Getter
    reads the db key, falls back to the engine constant then the literal, so
    the field never renders empty for a pre-options profile; setters write the
    db key only (no bar reconfigure chain). Helpers `rogue_threshold_get` /
    `rogue_threshold_set` are file-scope, unused-path-free.
  - New: "Post-swing & Weapon Cues" section (3.x): SS-window toggle+colour,
    weapon-swap toggle+colour, poison-reminder toggle+colour; copy states the
    Era/sword gate, the Era/TBC/Forever swap families (Wrath off, Retail none),
    the `GCD + swing reset` cost and "no charge counts".
  - NAG renumbered 3.x -> 4.x; copy now names POOL/NOW and the unknown "…"
    rule (aura reads included).
  - `hud_rotation_widgets` call: stale "Slice A ships no rogue glow cue" ->
    the shipped glow (SnD/Rupture/EA final 3 s, gated by the toggle); hud_desc
    mentions the glow.
- `tests/options_load_state.lua` (LF preserved): section 4 now walks Rogue's
  HUD slots (same machinery as hunter/warrior/druid/shaman); new section 9
  "ROGUE panel: panel <-> defaults <-> class-key round-trip":
  - copy scan over the ROGUE section source: stale phrases gone, no lowercase
    "slice"; shipped `0.1-0.2` SS timing and `GCD + swing reset` pinned;
    "glow" documented.
  - class-key scan: every `db.<key>` in `classes/rogue.lua` (23 keys) has a
    widget AND a shipped default; get/set resolve through the class handler.
  - round-trips through the real handlers: toggles (true/nil), colours
    (0-255 conversion), inputs (x/y), thresholds (nil -> engine default;
    set -> read back); generic class setters are resolution-checked only (the
    sandbox has no bar frames for their reconfigure chain).
  - explicit required-control list for the brief's Round-2 keys (toggles,
    colours, ranges, select/input).
  - defaults shape: 12 opt-in toggles ship false, `nextaction_locked` true, all
    10 ROGUE colours are 0-255+alpha tables; the six thresholds equal the
    `rogue_guide` constants (pure module now loaded in the sandbox).
  - colour rows disabled-gated by their own toggle (10 pairs, disabled()
    executed both ways).
- Added `rogue_guide.lua` to the sandbox `MODULES` (pure module; lets section 9
  pin defaults == engine constants and exercise the live fallback).

## Key coverage (panel <-> defaults <-> class)

Consumed keys (`db.` reads in `classes/rogue.lua`, 23/23): all have a widget +
default + handler wiring. New controls: `show_rogue_ss_window`/`rogue_ss_color`,
`show_rogue_swap_cue`/`rogue_swap_color`, `show_rogue_poison_cue`/
`rogue_poison_color`, `rogue_ea_duty`, `rogue_rupture_refresh`,
`rogue_rupture_min_ttd` (TTD), `rogue_finisher_min_cp`, `rogue_ea_refresh`,
`rogue_shiv_refresh`, `rogue_tea_energy_max`.

### Key mismatch (reported, not fixed - class file is the compat lane's)

10 keys exist in the panel + defaults with **no consumer** in
`classes/rogue.lua` today: `show_rogue_snd_cue`, `rogue_snd_color`,
`show_rogue_rupture_cue`, `rogue_rupture_color`, `show_rogue_ea_cue`,
`rogue_ea_color`, `show_rogue_shiv_cue`, `rogue_shiv_color`,
`show_rogue_tea_cue`, `rogue_tea_color`. They are the skeleton lane's Slice-A
placeholders; the cues lane delivered the upkeep trackers as HUD slots
(`hud_show_*`) and guide actions instead. They stay shipped (required by the
brief's control list; pinned by `tests/rogue_state.lua`) but are inert. No
consumed key is missing from the panel (checked both directions).

## Validation

- `lua5.1 tests/options_load_state.lua`: **919 checks, 0 failed** (clean copy in
  `/tmp/opencode/rogue_options_mut` identical).
- `bash tests/run.sh`: **37 steps, 0 failed**; luacheck **2 warnings / 0 errors**
  (floor; one mid-run read showed 6 warnings - the parallel compat lane's
  transient flap, re-run clean).
- Mutation proofs `/tmp/opencode/muts_rogue_options.py` on
  `/tmp/opencode/rogue_options_mut`: **9/9 bitten**, restored copy green:
  1. M1 remove SS-window widget -> class-key widget check;
  2. M2 revert glow copy to "Slice A ships no rogue glow cue" -> copy scan;
  3. M3 ungate SS colour row -> disabled() gate check;
  4. M4 threshold getter ignores db -> set/read-back check;
  5. M5 `show_rogue_swap_cue = true` -> ships-false check;
  6. M6 drop `rogue_ea_duty` default -> defaults-presence check;
  7. M7 threshold default drift (40->30) -> engine-constant pin;
  8. M8 reintroduce "the energy slice" copy -> copy scan;
  9. M9 drop a HUD slot from the builder call -> section 4 slot check.
- No git run; no lint-config change; touched-lines whitespace consistent;
  CRLF (config_presets) and LF (option_tables/tests) preserved.

## Residuals for the orchestrator

- Orphan-key row above (10 keys) - decide wire-later or strip in a class lane.
- In-client check unchanged: the panel copy's Era/swap gates and unknown-hide
  wording describe `classes/rogue.lua` behaviour; nothing visual is new here.
