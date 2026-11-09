# Shaman practice + designer lane (2026-10-19): build + audit + residuals

Desk: shaman. Scope held: `classes/shaman.lua`, `shaman_guide.lua` (untouched — engine
frozen), `tests/shaman_state.lua`, `tests/shaman_guide_state.lua` (untouched) fully owned;
shared files edited ONLY in shaman regions (`option_tables.lua` SHAMAN 5.x block,
`practice_ui.lua` shaman branches + `use_shaman_drill`/`shaman_*` fns). `designmode.lua`,
`practice.lua` untouched (verified zero diff). No git, no lint-config changes, endings
preserved (shaman/options/tests LF, practice_ui CRLF), touched-lines whitespace only.

## 1. Archive pattern (verified first-hand, not taken on faith)

`docs/swedge/SwedgeTimer_TBC` vs `docs/swedge/SwedgeTimer_Forever`: `cmp` clean on all 8
files checked (`practice.lua`, `core.lua`, `settings_ui.lua`, `editmode.lua`,
`import_export.lua`, `main.lua`, `hud.lua`, `nextaction.lua`) — one pattern. Reconciled
with the current tree for shaman; followed vs deferred below.

Followed (built):
- `core.lua:171-177` /st practice → toggle + `core.lua:948-964` options Start/Stop
  Practice execute (dynamic Start/Stop name, calls toggle): current `main.lua:1737-1740`
  already routes /st practice into `st.practice_ui.toggle` generically; the SHAMAN panel
  now carries the same execute toggle (`option_tables.lua` SHAMAN 5.1, mirrors the
  warrior 5.x entry shape). Both-ways start holds for shaman with no main.lua change.
- `settings_ui.lua:567-585` Practice Mode page shape (minigame desc + toggle, Simulation
  weapon speed, Feedback result styling, panel position): mirrored as the SHAMAN 5.x
  block (5.0 header "Weave Practice", 5.05 desc, 5.1 toggle, 5.2 speed, 5.3/5.31 result
  duration/size, 5.32/5.33 hit/miss colours, 5.34/5.35 panel x/y, 5.36 reset). Shaman
  wording describes the weave drill (grades S-F), never the twist sim.
- Session `st.practice.toggle/start`, panel Start Fight button, keybind casts
  (`practice.lua` identical in both archives): mirrored on the hunter lane's in-tree
  shape — `use_shaman_drill()` + `shaman_cast_def` + `shaman_start_session` /
  `shaman_tick_session` / `shaman_cast_drill` in `practice_ui.lua`, class seam in
  `classes/shaman.lua` (`practice_sync`, `practice_scenario_key`,
  `new/begin/end_practice_session`, `practice_cast`, `tick_practice_session`,
  `practice_status`, `practice_fight_elapsed`, cast lookup/spell-id/seconds/latency
  helpers). The drill runs the registered `shaman_weave` harness scenario end to end:
  toggle → session → icons cast simulated LB/CL → grade by margin/clip → shared score.
- `editmode.lua:311-539` descriptor shape (key/title/frame/enable_path/card/settings/
  save/reset, `EM.register`): audited against what shaman creates (below). The current
  `design.lua` normaliser keeps extra fields, so archive-shaped data would survive —
  but no new descriptor was needed (count pinned at 9).

Deferred (not built, with reason):
- Archive seal-icons / success-text / effects-chip elements: shaman has no analogues
  (no standalone frames at all — zero `CreateFrame` in `classes/shaman.lua`, pinned).
  Every shaman visual anchors to a bar visuals frame (child of the bar) or a shared
  module frame; the five generic descriptors (bars/HUD/rottext/NAG/practice) position
  them. Bar children move with the bar overlay by the port's deliberate design.
- The top-level Practice page (`option_tables.lua:377+`, parallel lane's turf): not
  touched; the shaman class-panel block is the in-scope entry.
- Result-popup text stays grade letters; hit colour = S/A/B/C, miss = D/F (shared
  `show_result` drill-grade rule extended to shaman, hunter behaviour unchanged).

## 2. Designer audit (shaman element inventory → covering descriptor)

| Shaman creates | Frame | Positioned by |
|---|---|---|
| mainhand/offhand swing bars + all weave visuals (marker, spark, zone, spell row, DW sync, lust, badges, FS/SS bars, WF strip, shields) | bar visuals frames (children of bar anchors) | `bar_mainhand` / `bar_offhand` overlays |
| 8-slot Cooldown HUD | `st.hud.frame` | `hud` descriptor (hud_x/y) |
| rotation label | `st.rotation_text.frame` | `rottext` descriptor |
| Next Action Guide | `st.nextaction_ui.frame` | `nag` descriptor |
| practice panel / rotation / timeline | `st.practice_ui.*` | `practice_panel` / `practice_rotation` / `practice_timeline` |

No gap found: zero new descriptors (the `designmode_state.lua` count pin at 9 is held
by not touching `designmode.lua`). Coverage pinned in `tests/shaman_state.lua` §36
(source scans + runtime provider wiring + defaults-chain keys).

## 3. Client matrix (Era / TBC Anniversary / Forever)

Verified read-only against `/home/sam/wow-ui-source` (`git show <branch>:path`, never
checked out; checked-out branch is `classic_era`):
- `classic_era:SpellDocumentation.lua:190`, `classic_anniversary:...:190`: legacy
  `GetSpellInfo` (id-or-name, may return nothing) — compat primary path.
- `origin/forever:...:416` `C_Spell.GetSpellInfo` (incl. name identifiers) + `:1189`
  `originalIconID` — compat fallback path; nil-safe on unknown.
- `C_Timer` all three branches (`UITimerDocumentation.lua:5`).
- `BackdropTemplate` / `CooldownFrameTemplate`: in-tree proof — `hud.lua:512,515` +
  `nextaction_ui.lua:188,197` ship in `SwedgeTimer_Mainline.toc` and build on Forever
  shaman clients today; the drill reuses the same templates (no new template risk).
- TOCs: all 7 ship `practice.lua` + `practice_ui.lua`.
The drill is family-independent by construction (own swing clock, catalogue reads with
harness-default fallback, 0-latency fallback, unknown-hides icon); family matrix
pinned ERA/TBC/FOREVER in `tests/shaman_state.lua` §35, including no-catalogue runs.
UNCONFIRMED: Forever Lightning Bolt/Chain Lightning name resolution in-client (the
drill degrades to blank icons + default cast and still grades; never throws).

## 4. Validation (offline)

- `tests/shaman_state.lua`: 590 checks PASS (was 252 at lane start; +338: §§33-36).
- `luacheck` on the 4 touched files: 0/0. Repo-wide: 2 warnings / 0 errors (the floor,
  both pre-existing KEEP-ruled).
- Mutation proofs on `/tmp/opencode/mut_shaman` (full-tree copy, restored
  byte-identical after each): M1 catalogue-fallback bypass → 4 FAILs; M2 clip-table
  drop → clip-decision FAIL (got D, want F); M3 toggle rewiring → tab-entry FAIL;
  M4 injected CreateFrame → designer zero-frames FAIL; M5 bogus scenario key →
  lifecycle FAILs; M6 family remap → lookup FAILs.
- Full `bash tests/run.sh`: 38 steps, 3 failed — ALL classified below, none mine:
  (a) `designmode_state` count 9→11: parallel-lane crossfire (pips +1 in
  `designmode.lua`, untouched by this lane); (b) `wiring_check` druid/hunter/rogue dead
  hooks: parallel-lane seams without callers yet (files untouched by this lane; my one
  dead surface was removed — `practice_summary` dropped, UI owns the score per the
  hunter shape); (c) `options_load_state` SODOPT 6 fails: stale absence pins
  superseded by this operator-ordered lane (file out of scope — orchestrator updates).

## 5. Residuals for the orchestrator (validation owner)

- R1 (stale pins, `tests/options_load_state.lua`, NOT in this lane's scope — update
  needed): SODOPT shaman absence pins now contradict the shipped feature:
  "shaman carries no practice_toggle / weapon_speed / reset_position",
  "practice_ui.lua names no shaman consumer", "names no weave consumer" (x2),
  "ST.SHAMAN.post_init builds no practice session" (x2). The "Twist Practice is
  paladin-only" rotation-text pin still holds (kept verbatim; the label has no
  practice branch) and the paladin-toggle pin holds.
- R2 (shared text now stale, other lane's turf): `practice_ui.lua` scoring comment
  "Practice stays paladin-only" predates the hunter/shaman drills; left byte-identical
  per scope.
- R3 (cosmetic wart inherited from the hunter pattern): the Start/Stop Fight button
  label reads the paladin sim, so it never flips to "Stop Fight" during a drill run;
  `toggle_fight` itself works (reads drill `.active`).
- R4 (UNCONFIRMED in-client): Forever LB/CL name resolution + drill feel; Era/TBC
  drill feel; weave-marker-vs-drill-swing readability.
