# Brief: rogue-skeleton (Round 1, Slice A — 2026-10-19)

## Objective
Sixth-class skeleton + wiring. NO behavior: HUD silent-until-enabled, guide renders "…" until inputs exist. Writer lane.

## Scope (ONLY these files)
- NEW `classes/rogue.lua`: open pattern (`local addon_name, st = ...` + `GetAddon` + `local api = st.api`, cf. `classes/paladin.lua:4-9`); spell/poison id tables EMPTY (no remembered ids — lessons rule; in-client fill later); `ST.ROGUE.HUD_SLOTS` + `get_hud_state` stubs returning nil-state (frozen contract `hud.lua:20-60`); guide `ST.ROGUE.guide` + `gather_guide_inputs` returning `inputs_unknown=true` (contract `nextaction_ui.lua:13-82`); `on_bar_update` driving `st.nextaction_ui.on_bar_update` then `st.hud.on_bar_update` with lockdown-safe frame-not-ready retry (cf. druid `:215`, shaman `:968`, warrior `:1310`); `on_combat_exit` preserving the mainhand record (G4 contract — speed/start/ends_at/is_full untouched); NO CLEU registration, NO spellcast hook (omit — Slice A consumes no casts); throw-safe by construction, no per-tick allocation.
- `config_presets.lua`: expand `ST.ROGUE.defaults` (`:569-598`) with class keys (energy-tick toggle, pooling-band data, SnD/rupture/EA cue toggles + colors, Shiv/Tea cues, `nextaction_*` OFF-default per shaman `:630-641`, `hud_show_*` ON-with-master-off per shaman `:643-654`). Nil-safe rule: `== false` hides, nil = off, defaults documented; no default-visible change.
- `option_tables.lua`: ADD `ST.class_opts_funcs.ROGUE` (dispatch `:701-706`; mirror SHAMAN `:3930-4263` shape with slot toggles via `hud_rotation_widgets` `:804-814`), nil-safe reads throughout.
- 8 TOCs (`SwedgeTimer.toc:66-70`, `_Vanilla`, `_TBC`, `_Wrath`, `_Cata`, `_Mists`, `_Mainline:65-69`): append `classes\rogue.lua` AFTER `classes\warrior.lua` (backslash, exact case). `_Mainline` keeps no swing-lib line.
- Tests: NEW `tests/rogue_state.lua` (sandbox + fake clock, behavior outcomes: load-order presence, defaults nil-safe shape, HUD silent-until-enabled, guide "…", combat-exit preservation) + `tests/toc_check.lua` class-coverage pins + register the rogue_state step in `tests/run.sh` (35→36; orchestrator adds the parallel pure-lane step separately).
- Explicitly OUT (parallel pure lane owns — collision if touched): root `rogue_guide.lua`, `tests/rogue_guide_state.lua`. Everything else in the tree is out.

## Timing + cross-engine law (all writer lanes)
- Timing math uses `st.api.get_time()` (aligned GetTimePreciseSec) — raw `GetTimePreciseSec()` never leaves compat; `GetTime()` fallback only. New code compares in the `GetTime()` domain like `bars.lua`.
- Never gate on `st.is_mainline` alone — gate on swing activity (Forever is Mainline-code and must weave/guide; Retail stand-in never swings so activity-gating hides it automatically).

## Standing rules
No git. No lint-config. Wire-not-strip. Whitespace only inside touched lines. CRLF preserved. Full `bash tests/run.sh` green + luacheck floor (2/0) + mutation proofs on `/tmp/opencode` copies before done.

## Workshop mechanics (skills: bench-read, desk-open, desk-journal, signal-write)
1. bench-read: `desks/journal.md`, `bench/rogue_readiness_2026-10-19.md` §§1/3/5-Slice-A, `bench/lessons.md`.
2. desk-open `desks/rogue-skeleton/`; 3. journal append + `done` signal (every file changed + harness result).

## Validation owner
Orchestrator: pins green, harness 36/0, floor held, scopes disjoint vs pure lane (shared: nothing).
