# rogue-skeleton — Journal

## 2026-10-19 — Desk opened (Round 1, Slice A)
- **Purpose:** sixth-class skeleton + wiring for the rogue: `classes/rogue.lua`, ROGUE
  defaults, ROGUE options section, TOC appends, `tests/rogue_state.lua` + pins.
  NO behavior in this slice: HUD silent-until-enabled, guide renders "…".
- **Scope:** per `bench/briefs/brief_rogue-skeleton_2026-10-19.md`. OUT (parallel pure
  lane owns; collision if touched): root `rogue_guide.lua`, `tests/rogue_guide_state.lua`.
- **Next step:** read bench journal + `bench/rogue_readiness_2026-10-19.md` §§1/3/5-Slice-A
  and `bench/lessons.md`, then implement the writer lane.

## 2026-10-19 — Slice A implemented (writer lane)
- **Worked on:** new `classes/rogue.lua` (open pattern, empty SPELL_IDS/POISON_IDS,
  9 HUD_SLOTS + cleared nil-state provider, 7-slot guide provider with
  `inputs_unknown=true`, `on_bar_update` driving nextaction_ui then hud, `post_init`,
  mainhand-preserving `on_combat_exit`); `ST.ROGUE.defaults` class keys
  (energy/pooling, SnD/Rupture/EA/Shiv/Tea cues + colours, nextaction_* OFF,
  hud_show_* ON); `ST.class_opts_funcs.ROGUE`; TOC lines; `tests/rogue_state.lua`
  (178 checks) + toc_check pins/order; run.sh step.
- **Integration note:** TOCs also gained `rogue_guide.lua` in the guide group
  (after `hunter_guide.lua`) because the pure lane's file was on disk unlisted and
  the harness was 7 toc failures at lane start; readiness §3 item 8 places that line
  here. No edit to `rogue_guide.lua` or `tests/rogue_guide_state.lua`.
- **Validation:** `bash tests/run.sh` = 36 steps, 0 failed; luacheck 2 warnings /
  0 errors (floor held). `tests/rogue_state.lua` 178/0; `tests/toc_check.lua`
  788/0. Mutation proofs on /tmp/opencode copies: M1 drop class TOC line (rogue_state
  2 fail, toc_check 3 fail), M2 drop `out.inputs_unknown` (4 fail), M3 clear mainhand
  in on_combat_exit (2 fail), M4 leave a stale HUD state field (1 fail); restored copy
  clean. No git run.
- **Current state:** Slice A complete in-tree; no default-visible rogue change (guide
  and HUD masters ship off; spell slots intentionally id-less until in-client fill).
- **Next step:** orchestrator validation/reconcile (`desks/journal.md` lane row), then
  Slice B (energy tick + Era swing cue) on this skeleton.
