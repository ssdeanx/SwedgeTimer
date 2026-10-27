# appearance-options — Journal

## 2026-10-25 — Desk opened
- **Purpose:** the defaults/options side of two operator appearance requests:
  (1) opaque bar BACKDROP (not the coloured fill), with a one-time migration that
  raises only an untouched default; (2) the ranged distance bar as a standalone
  horizontal bar, ON by default for HUNTER, opt-in for every other class.
- **Scope (write):** `config_presets.lua`, `option_tables.lua`, `config.lua`,
  `tests/options_load_state.lua`, NEW `tests/appearance_defaults_state.lua`.
  NOT mine: `bars.lua`, `weave_range.lua` (bars-range-hunter lane), classes/**,
  main.lua, practice*.lua, hud.lua, TOCs, `tests/run.sh`, CHANGELOG/README/docs,
  Libs/**.
- **Read first:** AGENTS.md, CAIRN.md, workshop.md (lessons 1-18, esp. 5 one
  writer per file, 14 the operator's AddOns folder is the client), bench/lessons.md,
  `desks/journal.md` tail, `hands-up.md` later.
- **Next step:** verify the stored colour shape in AceDB before writing the
  migration; make the minimal edits; pin with a new suite + mutation proofs.

## 2026-10-25 — landed: opaque backdrop + hunter ranged-bar default
- **Worked on:** Task A (backdrop opacity + one-time migration) and Task B (weave_range
  defaults/option copy), both proven offline.
  - `config_presets.lua:173` background_color `{0,0,0,0.85}` → `{0,0,0,1.0}` (black kept,
    only alpha). Fill `bar_color_default` (:160) and border (:176) untouched.
  - `config.lua:79-181` migration: exact-match raise of `{0,0,0,0.85}` only, skips a hand
    whose ACTIVE theme preset owns the colour (Classic Retro ships the same bytes),
    once-per-profile via `appearance_defaults_213`, nil-safe, returns the change count.
  - `option_tables.lua:7377-7390`: `ST:set_opts()` calls it first (the seam main.lua:424
    hits after AceDB at :416; bars build later at :795/:860). Both calls pcall'd.
  - `config_presets.lua:536` `ST.HUNTER.defaults.weave_range_enabled = true` (operator
    gate), shared default stays false (:104), new
    `ST.weave_range_default_enabled` (:1599) is the getter's single source of truth.
  - `option_tables.lua:195-224` copy rewritten for the standalone horizontal bar; key
    unchanged; nil reads the class default (hunter ON), explicit false stays OFF.
- **Current state:** `lua5.1 tests/appearance_defaults_state.lua` 145/0;
  `lua5.1 tests/options_load_state.lua` 3596/0 (+35); luacheck clean on the 5 files;
  hud_templates_state 965/0 and bars_state 957/0 as shared-seam cross-checks.
  10/10 mutations kill (control green). Report: `bench/appearance_options_2026-10-25.md`.
  Known-and-filed: `tests/toc_check.lua` now fails exactly 2 checks because the new suite
  is not registered in `tests/run.sh` (orchestrator-owned, one-writer rule).

## 2026-10-25 — [signal:done] opaque backdrop + hunter ranged-bar default landed
- Bench: `bench/appearance_options_2026-10-25.md`. Signal:
  `desks/appearance-options/.signals/2026-10-25T165500Z.json`.
- Owed: run.sh registration (orchestrator), the horizontal bar + `nil == ON for HUNTER`
  runtime gate in `weave_range.lua` (bars lane), operator in-client checks §7.
- **Next step:** orchestrator adds the run.sh line, then the operator's in-client list
  (bench report §7). The bars lane still owes the horizontal standalone implementation
  (`weave_range.lua` is still the vertical bar) and the `nil == ON for HUNTER` runtime
  gate at `:210` — the option copy is ahead of that module until it lands.

## 2026-10-25 (later) — ranged-bar desc corrected to the landed module
- **Worked on:** the bars-range-hunter lane landed the standalone horizontal bar and
  reported my `weave_range_enabled` desc was factually wrong ("banded where it only has
  range checks"; HU-23 has no band fallback). Applied their verbatim §6 replacement
  (`bench/bars_range_hunter_2026-10-25.md`), get/set/disabled untouched. Verified every
  copy claim against `weave_range.lua` first: NEAR 5 (:63), FAR 30 (:64), HUNTER_FAR 35
  (:65), `format_yards` (:208-213), state words (:183-189), UnitDistance-only + hide
  (:420-428), 200×10 own frame (:76-77/:275-277).
- **Pins:** `tests/options_load_state.lua` §29 now rejects "banded"/"range check"/
  "librangecheck", requires "exact distance" + the three state words, and reads
  5/30/35 out of the module so copy and code cannot drift. Note: the follow-up asked to
  ban the substring "band", but the mandated copy itself says "35 yd band"/"30 yd band" —
  pinned the defect wording instead; stated on the bench.
- **Supersedes** the previous entry's "copy is ahead of the module" note; §6.2 (the
  `weave_range.lua` nil-parity request) is CLOSED — `:108-113` now calls
  `ST.weave_range_default_enabled`, `:117-135` implements true/false/nil.
- **Current state:** options 3606/0 (+10), appearance 145/0, luacheck 0/0 on both files,
  mutations M-A (stale wording → 2 FAIL) and M-B (hunter band 35→30 → 1 FAIL) on
  `/tmp/opencode` copies, deleted. Bench append filed.
- **Next step:** orchestrator registers `tests/appearance_defaults_state.lua` in
  `tests/run.sh`; operator runs the bench report's in-client checks (incl. the hunter bar
  default and the 5/35 yd fill).

## 2026-10-25 (later) — [signal:done] ranged-bar desc corrected
- Bench append: `bench/appearance_options_2026-10-25.md` (supersedes §5.4, closes §6.2).
- Signal: `desks/appearance-options/.signals/2026-10-25T173500Z.json`.
- Tests: options 3606/0, appearance 145/0, luacheck 0/0; mutations M-A/M-B kill.
- Owed: `tests/run.sh` registration (orchestrator); operator in-client checks.
- **Next step:** nothing open in this lane except the orchestrator's run.sh line and the
  operator's in-client pass.
