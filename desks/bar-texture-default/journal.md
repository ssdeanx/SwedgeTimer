# Bar Texture Default — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Make the operator's texture (`Media/StatusBar/Wglass.tga`) the default
  status-bar texture for SwedgeTimer's progress bars (swing bar + GCD underlay),
  registered through LibSharedMedia so it appears in the existing texture dropdown,
  with a real fallback so a failed fetch never leaves a bar textureless.
- **Scope:** `main.lua` (media registration), `config_presets.lua` (the two texture
  defaults), `bars.lua` (nil-safe fetch), `option_table_presets.lua` (only if the
  dropdown needs an explicit entry), `tests/{hud_state,bars_state,options_load_state}.lua`
  (pins only). Out of scope: practice*.lua, class files, `option_tables.lua`,
  `config.lua`, `compat.lua`, `diag.lua`, `hud.lua`, `designmode.lua`, `run.sh`,
  versions, README/CHANGELOG/docs, git, lint config, moving the .tga.
- **Gate:** the operator explicitly ordered this default — that IS the gate for the
  default-visible change (standing rule: no default-visible change without an
  explicit gate).
- **Next step:** inventory every statusbar-texture consumer, land the registration +
  defaults + nil-safe fetch, cut the pins, run the harness + mutation proofs.

## 2026-10-20 — Landed: Wglass is the default for the two progress bars
- **Worked on:** registered `"statusbar"` / `"Wglass"` ->
  `Interface\Addons\SwedgeTimer\Media\StatusBar\Wglass.tga` in `main.lua` (same shape
  as the existing Minimalist registration); set `ST.bar_defaults.bar_texture_key` and
  `gcd_texture_key` to `"Wglass"` in `config_presets.lua`; added
  `fetch_statusbar_texture` to `bars.lua` (requested key -> "Minimalist" ->
  `Interface\Buttons\WHITE8X8`, pcall-guarded) and used it at all 5 statusbar fetch
  sites; re-cut the two `tests/bars_state.lua` texture pins and added section 9
  (registration + defaults + both degradation levels); added
  `tests/options_load_state.lua` section 28 (source pins: registration, defaults,
  no per-class override, dropdown value source).
- **Decisions:** NO toc line — `Minimalist.tga` and `Expressway.ttf` are in no toc and
  the client resolves both by path, and no Blizzard toc in `wow-ui-source` lists a
  texture file at all. `option_table_presets.lua` needed NO change: `LSM:HashTable`
  returns the live registry, so the key appears in all four texture dropdowns.
  `bar_appearance_preset` is an options GROUP, not a preset table, and no class
  defaults block sets a texture — so no preset silently overrides the default. The
  deadzone marker and the bar backdrop keep "Solid" (markers/backdrop, not progress
  bars) — the operator can order that separately.
- **Current state:** harness 41 steps / 0 failed, luacheck 2 warnings / 0 errors
  (the floor, unchanged). 5/5 mutants killed on the `/tmp/opencode/mut_wglass`
  copy (driver `/tmp/opencode/mut_wglass_run.py`). Bench artifact:
  `bench/bar_texture_default_2026-10-20.md`. Changed files: `main.lua`,
  `config_presets.lua`, `bars.lua`, `tests/bars_state.lua`,
  `tests/options_load_state.lua`. `tests/hud_state.lua` needed no pin (the HUD
  draws spell icons, not statusbar media). `tests/toc_check.lua` untouched.
- **Residual for the operator:** existing profiles keep their SAVED texture (AceDB
  keeps the stored value) — the new default lands on fresh profiles only, so an
  existing user must pick "Wglass" in the dropdown to see it.
  `Media/StatusBar/atlas.tga` (2.3 MB) plus `mask/`, `png_color/`, `Borders/`,
  `composite/` are referenced nowhere — reported, NOT deleted. In-client rendering
  of the 256x64 Targa on each family is still owed.
- **Next step:** orchestrator validates; operator does an in-client look at the swing
  bar + GCD underlay on one classic-line and one mainline-code client, and rules on
  the deadzone/backdrop "Solid" question.
