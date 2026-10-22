# Buildout — rogue-pd (rogue practice + designer, 2026-10-19)

Session: rogue-pd lane (`ses_eaa01e200ffePpgnl1ZZIRsX9u`). Validation owner: orchestrator.

## 1. Archive diff (operator-ordered, read don't guess)

`docs/swedge/SwedgeTimer_TBC` vs `docs/swedge/SwedgeTimer_Forever`: `cmp`-clean on all
10 practice-touching files (`practice.lua`, `core.lua`, `settings_ui.lua`, `editmode.lua`,
`import_export.lua`, `main.lua`, `hud.lua`, `nextaction.lua`, `rotationtext.lua`,
`st_data.lua`). One pattern, verified — not taken on word.

### Patterns reconciled with the current tree (for ROGUE)

1. **Session**: `st.practice.toggle/start`, panel, Start Fight button, keybind casts —
   FOLLOWED. Rogue extends the existing `practice_ui` session (no new flow).
2. **Both-ways start**: `/st practice` (`core.lua:172-177`) + options Start/Stop execute
   (`core.lua:948-965`) — FOLLOWED. `/st practice` routes generically
   (`main.lua` → `st.practice_ui.toggle`); the ROGUE panel toggle calls the same
   function (`option_tables.lua` rogue `practice_toggle`); the drill predicate
   routes rogues to the drill shell inside `ui.start`.
3. **Own options page** (`settings_ui.lua:567-583`, group "Guides & Practice", shown to
   all classes) — page SHAPE followed inside the rogue-keyed region (ROGUE panel
   Practice block mirrors the paladin 7.x block: toggle / weapon speed / feedback /
   panel position). The shared top-level page itself is parallel-lane work
   (`ST.opts_table.args.practice`, order 1.46) — NOT touched (out of scope, avoids
   5-lane collision). No rogue entry needed there: routing is class-gated in `ui.start`.
4. **Defaults** (`core.lua:481-521`) — no new db keys (config_presets out of scope);
   every rogue widget reads class-table keys with inline fallbacks citing the shipped
   shared values (0 / 0.8 / 28 / green / red / 0,0). Nil-safe, no default-visible change.
5. **HUD practice-aware** (`hud.lua:72-133`) — druid precedent followed: rogue HUD reads
   LIVE cooldowns during the drill (the drill mirrors only the swing clock, no seals,
   no GCD writes). No sim-cooldown HUD branches (nothing to mirror).
6. **nextaction practice-aware** (`nextaction.lua:10-11,65-168`) — same: guide reads live.
7. **rotationtext practice-aware** (`rotationtext.lua:30-34`) — the center-screen
   rotation DISPLAY is generic session UI (runs); the rogue LABEL reads the live guide
   decision (never guesses off sim state — pinned).
8. **`main.lua` init** (`main.lua:70-73`) — port inits per-class post_init; rogue now
   calls `st.practice_ui.init` (guarded), like paladin/druid.
9. **import_export practice keys** — no import_export module in the port (deferred
   upstream); session-local keybinds, nothing to persist. No action.
10. **editmode ELEMENTS** (9 descriptors via `EM.register`, `editmode.lua:311-539`) —
    diffed against what rogue creates: bars/HUD/rotation/guide/practice panel/rotation/
    timeline all covered by the generic `designmode.lua` descriptors (verified live +
    source pins). Bar-child visuals (tick spark/pool wash/SS window/swap/poison) ride
    the bar overlay per the port's documented rule (no separate descriptor — same as
    the paladin mini-bar exclusion). Seal icons / success text / effects chip: paladin-
    only or virtual, rogue creates none — nothing to add. Zero `designmode.lua` edits.

## 2. What was built (rogue scope)

- `classes/rogue.lua` (owned): post_init builds the practice panel frames (guarded);
  practice seam — `practice_sync` (returns 0, no seals), scenario keys for
  `rogue_energy_pool` + `rogue_ss_window`, create/begin/tick/end session wrappers,
  `practice_spend` / `practice_ss` graders, `practice_cast` (shell entry: spend
  fraction from the drill tick clock, SS offset from the drill swing), `practice_status`
  (tick countdown), `practice_fight_elapsed`, `practice_shift_pause`,
  `practice_cast_order` (Era-filtered: SS icon Era-only, TBC+/Forever pool only),
  `practice_cast_label` / `practice_cast_spell_id` (name-art, no remembered ids).
  `practice_summary` deliberately NOT shipped (no consumer; scoring flows through
  `record_attempt` into the shared score like hunter/shaman — cut with reason).
- `practice_ui.lua` (rogue-keyed regions only): `use_rogue_drill()` (key-match fails
  closed), `rogue_cast_order` guard (ST.ROGUE-qualified call), `rogue_cast_def`,
  HINT_ROGUE_* pair, `rogue_start_session` / `rogue_tick_session` / `rogue_cast_drill`
  shells, and rogue branches at every hunter/shaman integration point (start/stop/
  fight/tick/pause-shift/sync/panel title+order+icons+widget-skip/keybinds/rebind/
  labels/display-name/info/fight-clock/button/hint/show-result/teardown).
- `option_tables.lua` (ROGUE section only): Practice block 7.0-7.36, same page shape
  as the paladin block, rogue-truthful copy, all consumers verified live in
  `practice_ui.lua`.
- `tests/rogue_state.lua` (owned): section 15 — seam surface, 3-client family matrix
  (Era project 2 / TBC default / Forever project 18), nil-safety, end-to-end drill
  runs through the shell contract, live sandbox drive (toggle → graded casts → tick →
  stop; Era both icons, TBC pool-only, combat refusal), options + shell + designer pins.

## 3. Validation

- `tests/rogue_state.lua`: **678 checks, 0 failed** (was 452; +226 pins).
- `practice_ui_state` + `practice_state` + `rogue_guide_state`: green.
- Full harness on the landed tree: **38 steps, 3 failed — all three are parallel-lane
  crossfire, zero rogue attribution** (evidence below).
- `luacheck`: my 4 files 0 warnings; tree holds the 2-warning floor.
- Mutations (on `/tmp/opencode/rogue-mut-tree` full-tree copies, restored after):
  M1 sync→1 kills 3; M2 drop post_init init kills 6; M3 drop sync elseif kills 2;
  M4 drop record call kills 1; M5 rogue-span toggle break kills 1; M6 wrong drill key
  kills 3; M7 predicate key drift kills shell pins; M8 Era-gate removal kills 3
  (TBC/Forever order + TBC SS icon). M2/M3 pin holes found mid-lane (dead-code edit,
  untested pin text) were fixed and re-proven — see journal.
- Client API surface (operator order; `/home/sam/wow-ui-source`, read-only, no checkout):
  my hunks add **zero WoW API calls** (grep-verified). The newly exposed path
  (`practice_ui.init` on rogue) uses only `CreateFrame`, `InCombatLockdown`,
  `C_Timer.After` — each cited on all three branches:
  `classic_era` / `classic_anniversary` / `origin/forever` :
  `Interface/AddOns/Blizzard_FrameXML/Classic/AlertFrameSystems.lua:1184`
  (CreateFrame), `.../SecureTemplates.xml:16` (InCombatLockdown),
  `Interface/AddOns/Blizzard_SharedXML/ModelSceneMixin.lua:472,481` (C_Timer.After).
  TOCs ship practice/practice_ui on all 7 flavors (3/3 each). No probe-gate needed;
  everything else is addon-internal with nil-guards. No load errors possible from
  this lane (guarded inits + pure-Lua seam).

## 4. Crossfire inventory (orchestrator-owned, not this lane)

- `tests/options_load_state.lua` SODOPT x6: `classes/shaman.lua` gained practice
  content mid-flight (shaman-pd lane) — this lane never touched shaman files.
- `tests/designmode_state.lua` x2: registry 9→11/12 (pips + sibling descriptors) —
  `designmode.lua` untouched by this lane.
- `tests/wiring_check.lua`: druid x3 + hunter x1 dead-hook flags on THEIR seams
  (sibling pd-lanes converging on drivers). **Zero rogue flags** — every
  `ST.ROGUE.*` in this lane has a live addon call site (verified).
- Isolation proof: with everything except my 4 files reverted to HEAD,
  all suites pass except pins that depend on siblings' uncommitted defaults;
  my section is fully green in isolation too.

## 5. Standing notes

- `practice_summary` cut (no consumer); `practice_ss` on non-Era grades pure math but
  the panel never offers the icon there (Era gate in `practice_cast_order`, pinned).
- The drill tick clock is shell-owned (`ui.rogue_tick`); the harness session holds
  only the grading state — same split as the shaman shell.
