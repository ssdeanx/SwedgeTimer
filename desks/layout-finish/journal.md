# layout-finish — Journal

## 2026-10-28 — Desk opened (dispatch: bench/briefs/brief_layout-finish_2026-10-28.md)
- **Purpose:** second wave of the 2026-10-28 bar work. Four operator orders:
  (1) the ranged hand must be re-placed out of the power-bar slot at RUNTIME for every melee
  class (not only for fresh profiles, and never fighting a saved/dragged position);
  (2) ROGUE must behave exactly like WARRIOR — ranged hidden unless actually used, never in
  the power-bar row (the gate must be class-agnostic, not warrior-shaped);
  (3) one adjustable height for the melee pair (mainhand + offhand together), plus honest
  per-hand height options; offhand width stays = mainhand width;
  (4) `/st diag` must expose per-hand bar state so a SILENT bar fault is visible
  ("/st diag said there was no errors, meaning something was missed/silent").
  L4 hold: `weave_range.lua` (the distance bar) is untouched — it is a melee-range aid with
  its own progress bar, independent of the swing bars.
- **Write scope (exact):** `main.lua`, `bars.lua`, `power_bar.lua`, `config_presets.lua`,
  `option_tables.lua`, `option_table_presets.lua`, `diag.lua`, `tests/diag_state.lua`,
  `tests/bars_state.lua`, `tests/power_bar_state.lua`, `tests/options_load_state.lua`.
  Out of scope and held: `classes/*`, `hunter_ui.lua`, `weave_range.lua`, `Libs/`, TOCs,
  `CHANGELOG.md`, `README.md`, `.luacheckrc`, `tests/run.sh`, `config.lua`.
- **Baseline before any edit:** `bash tests/run.sh` = 54 steps, 0 failed; luacheck
  2 warnings / 0 errors in 97 files. Version 2.1.3 (not bumped). sha256 of every scoped
  file + `weave_range.lua`/`hunter_ui.lua` recorded in `/tmp/layout_finish_baseline.sha256`
  (session temp) and the untouched-file hashes are restated in the bench report.
- **Next step:** read the first-wave reports (`bench/bars_decouple_2026-10-28.md`,
  `bench/hunter_tint_2026-10-28.md`) and their desk journals — done; then land L1 (ranged
  runtime re-placement), L3 (melee pair height), L5 (diag bar state), verify L2/L4, pin all
  of it offline, write `bench/layout_finish_2026-10-28.md`, journal + done signal.

## 2026-10-28 — Lane complete: ranged placement, melee pair height, per-hand diag (offline)
- **Worked on:** the four remaining operator orders (brief L1/L2/L3/L4/L5). Read the
  first-wave reports and both desk journals first; no answered question was re-searched.
- **Landed:**
  * `bars.lua:349-542` — the runtime ranged-placement rule. Constants (shipped x/point/scale
    and every y this addon has shipped: -166/-120/-98, 2 px gap), `saved_row_extent`,
    `melee_reserved_band` (melee stack + the power-bar slot, power_bar.lua read at call
    time), `row_intersects_band`, `shipped_ranged_y` and `migrate_ranged_placement`
    ("moved"/"kept"/"done"/"no-ranged"/"unknown"). It acts only while the ranged row is
    still EXACTLY a shipped default and demonstrably intersects the band, writes the ranged
    row only once, to the class's shipped row (else `ceil(band_top+gap+h/2)`), and latches
    the CLASS row with `rawget`. `main.lua:428-433` calls it once, pcall'd, before
    `set_opts()`.
  * `bars.lua:274-330` + `config_presets.lua:115-128` — `melee_bar_height`: ONE class-level
    height for mainhand+offhand (nil = shipped per-hand behaviour; documented as a comment
    because nil is the shipped value). The offhand's follow branch reads the mainhand's
    EFFECTIVE height so the pair cannot be undone.
  * `option_tables.lua:1336-1510`, `:7239-7306`, `:7383-7454`,
    `option_table_presets.lua:254-272` — the pair widget (Positioning, between the melee and
    ranged groups) with a reset button, and honest per-hand Height widgets: the offhand's is
    ALWAYS locked (it renders at the mainhand's height; its own key is inert) and the
    Appearance handler's getter/setter shows and edits the effective value.
  * `diag.lua:435-621`, `:900-912` — per-hand BAR STATE lines (built/shown/alpha/tick/
    start/speed/ends_at/now/progress/full/paused/dead/vf_width/fill/pos + the hunter queue
    flags on the mainhand line), print-only, pcall'd, `rawget` profile reads, capped through
    `append_section`; `MAX_LINES` 85 → 88 to keep the error ring's headroom.
- **Current state:** GREEN. `bash tests/run.sh` 54 steps / 0 failed; luacheck 2 warnings /
  0 errors in 97 files (same pre-existing pair). bars_state 1040 → 1117, diag_state 260 →
  294, options_load_state 3645 → 3743; power_bar_state 190 and hunter_state 1909 unchanged.
  **20/20 mutations killed** on a throwaway tree copy (M1-M20, bench report §6).
  `weave_range.lua`, `hunter_ui.lua`, `power_bar.lua` and `tests/power_bar_state.lua`
  hash-identical to baseline. Version 2.1.3; no git; no docs.
- **Re-cut pins (all in tests/diag_state.lua, all mechanical):** the verbose line indices and
  the 73 → 76 count (3 new hand lines shift everything after them), the cap-6/cap-10
  truncation pins now land on the bar section first, the errors-cap pin moved cap 75 → 80
  (5 base + 3 bars + 67 ids = 75 lines before the ring), and the default-cap fallback 73 →
  76. Nothing in bars_state or power_bar_state was invalidated; §12/§30 are new checks.
- **Findings:** F1 = AceDB's `'**'` metatable turns a missing-key READ into a persisted
  defaults table (both new keys are rawget-based, pinned). **F2 = the shipped
  `ST.migrate_appearance_defaults` (config.lua:162) can never run on a live profile** for
  exactly that reason — its flag read creates a truthy table, so the 2026-10-25 opaque
  backdrop default never reached saved profiles. config.lua is out of this lane's write
  scope; filed for the orchestrator (one-line rawget + a `'**'`-shaped fixture). F3 = the
  diag guide summary reads profile rows the same way (benign: all ten rows exist). F4 = the
  rule reserves the power row even with the power bar off (a row, not a widget) — stated.
- **Next step (in client):** on the operator's rogue/warrior profile confirm the ranged bar
  moved above the melee stack and stayed put across a reload/drag; on TBC + Era confirm the
  power bar sits under the offhand row; resize the melee pair height and confirm both bars
  and the hunter stack follow; check `/st diag` reads a live fill correctly. Full list in
  bench/layout_finish_2026-10-28.md §8. Also owed by the operator: a ruling on F2's fix and
  on whether the rule may assume the shipped melee rows when a profile's melee bars were
  dragged (U2), which today it deliberately does not.

### Correction/extension after the entry above (same session)
- The placement rule also announces an actual move ONCE through the addon's chat path
  ("no silent paths": a saved position changed, and the user must know it and that a drag
  wins). `self.ranged_placement_moved` was removed again - it had no reader; the outcome is
  the function's return value plus the notice. Pinned: one line on "moved", none on "kept",
  none on a latched "done".
- Mutation proofs are therefore **21/21 killed** (M1-M21; M21 removes the notice). M1's first
  form was a Lua syntax error and was re-run as a valid early return - the bench report §6
  records that. `tests/bars_state.lua` is now 1124 checks.

### Second extension (same session): F2 proven and accepted in-suite
- `tests/bars_state.lua` §12e now RUNS the real `ST.migrate_appearance_defaults` against the
  real AceDB profile of a booted Warrior holding the old `0.85` backdrop: it raises 0, the
  flag read leaves a created table behind, and the saved alpha is unchanged. Written as an
  ACCEPTED-KNOWN-DEFECT pin (prints the evidence, FAILS if the defect disappears) because
  `config.lua` is outside this lane's write scope. bars_state is now 1128 checks; gate still
  54/0 with luacheck 2 warnings / 0 errors in 97 files.
- **Next step:** the orchestrator dispatches the `rawget` fix in `config.lua` + a `'**'`-shaped
  fixture for `tests/appearance_defaults_state.lua`; removing the §12e acceptance belongs to
  that lane.
