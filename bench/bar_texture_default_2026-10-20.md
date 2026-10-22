# Bar texture default: the operator's Wglass on the progress bars

Desk: `bar-texture-default` — 2026-10-20
Operator order: make `Media/StatusBar/Wglass.tga` the addon's **default status-bar
texture**. That order IS the gate for the default-visible change.

Status: LANDED. Full harness 41 steps / 0 failed, luacheck 2 warnings / 0 errors
(the standing floor, unchanged). 5/5 mutants killed.

---

## 1. What landed (5 files, no TOC change, no version bump)

| File | Change |
|---|---|
| `main.lua` | Registered the medium: `LSM:Register("statusbar", "Wglass", [[Interface\Addons\SwedgeTimer\Media\StatusBar\Wglass.tga]])` — the same shape as the existing "Minimalist" registration. The comment states the operator order as the gate. |
| `config_presets.lua` | `ST.bar_defaults.bar_texture_key = "Wglass"` and `ST.bar_defaults.gcd_texture_key = "Wglass"`. The deadzone keeps `"Solid"` (marker, not a progress bar) with a comment saying why. |
| `bars.lua` | New module-local `fetch_statusbar_texture(key)`: the requested key -> the shipped fallback key `"Minimalist"` -> the client's own white pixel `Interface\Buttons\WHITE8X8`. pcall-guarded, so a throwing media library cannot abort the configuration pass. Used at all 5 statusbar fetch sites in the file. |
| `tests/bars_state.lua` | LSM mock gained two nil-fetch modes (`opts.lsm_missing_key`, `opts.lsm_missing_all`); the two texture pins were re-cut to `Texture\Wglass`; new section 9 pins the registration, the shipped defaults, the deadzone, and BOTH degradation levels. |
| `tests/options_load_state.lua` | New section 28: source pins on the registration (main.lua), the shipped defaults (config_presets.lua), the absence of any per-class texture override, and the dropdown's value source. |

Line endings preserved: `main.lua` CRLF, `config_presets.lua` / `bars.lua` /
`tests/*.lua` LF. No trailing whitespace introduced (luacheck clean on all
touched files).

## 2. The dropdown needs no new widget

`option_table_presets.lua` was **not** changed, and it did not need to be.
`LibSharedMedia:HashTable(mediatype)` returns the LIVE media table
(`Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua:262-264`), so a medium
registered under `"statusbar"` appears in every widget that reads that table.
All four texture dropdowns already do:

* `bar_texture_key` — `option_table_presets.lua:271-280`
* `background_texture_key` — `option_table_presets.lua:296-305`
* `gcd_texture_key` — `option_table_presets.lua:672-681`
* `deadzone_texture_key` — `option_table_presets.lua:909-918`

All four use `values = LSM:HashTable("statusbar")` + `dialogControl = "LSM30_Statusbar"`.
The key the user sees in the dropdown is literally `"Wglass"`.

## 3. Inventory of every statusbar-texture consumer in the tree

Active addon (repo root + `classes/`). The archived `docs/swedge/*` builds are a
separate shipped-elsewhere addon and were NOT touched (per AGENTS.md).

| Site | Consumer | Classification | Default | Changed? |
|---|---|---|---|---|
| `bars.lua:254` | swing bar fill | **PROGRESS BAR** | `bar_texture_key` -> Wglass | default + nil-safe fetch |
| `bars.lua:255` | GCD underlay (configure_bar_appearances) | **PROGRESS BAR** | `gcd_texture_key` -> Wglass | default + nil-safe fetch |
| `bars.lua:392` | GCD underlay (configure_gcd_underlay) | **PROGRESS BAR** | same key | nil-safe fetch only |
| `bars.lua:284` | deadzone strip | MARKER (a shaded latency region) | `deadzone_texture_key` -> "Solid" | nil-safe fetch only; **default deliberately unchanged** |
| `bars.lua:370` | bar backdrop `bgFile` | BACKDROP, not a bar | `background_texture_key` -> "Solid" | nil-safe fetch only; **default deliberately unchanged** |
| `hunter_ui.lua:349` | hunter cast bar + Rapid Fire bar | **PROGRESS BARS** | reads the hand's `bar_texture_key` -> Wglass automatically | out of scope; not touched |

Non-consumers (checked, so the operator does not have to): `hud.lua` draws
spell icons, not statusbar media (`hud.lua:473` `f.default_texture = slot.texture
or spell_icon(slot.spell)`); `enemy_swing.lua` uses `SetColorTexture` (a solid
colour) for its bg and bar (`enemy_swing.lua:391-400`), no LSM fetch at all.

**Operator decisions still open** (deliberately not taken by this desk):
the deadzone marker and the bar backdrop both still use "Solid". They are
markers/backdrop, not progress bars, so the order ("default status bar texture
for the progress bars") does not reach them. If the operator wants the glass on
those too, it is a one-line change each in `config_presets.lua`.

## 4. Packaging: no TOC entry is needed

Checked, not assumed.

1. **The precedent holds.** `Media/Textures/Minimalist.tga` (the previously
   shipped default for the same two bars) and `Media/Fonts/Expressway.ttf` (the
   font every bar text uses) are in **no** TOC in this repo — not in the base
   toc, not in any of the 6 flavor tocs. The addon ships and works on all seven
   flavors, so the client resolves both by path at runtime.
2. **The client does not require it.** No Blizzard toc in the reference client
   source lists a texture file at all: `git grep -iE '\.(tga|png|jpg)$' live --
   'Interface/AddOns/*/*.toc'` over `/home/sam/wow-ui-source` (branch `live`)
   returns **no** matches. Textures are loaded by path, not by toc entry.
3. **LibSharedMedia accepts the path on every family.** Its `Register` rejects a
   path that does not start with `interface` when the client restricts file
   access (`LibSharedMedia-3.0.lua:230-235`, `RESTRICTED_FILE_ACCESS` is true
   on mainline-code clients). `Interface\Addons\SwedgeTimer\Media\StatusBar\Wglass.tga`
   lowercases to a path that starts with `interface`, so the registration
   succeeds on classic-line AND on Retail/Forever.

**Conclusion: NO toc line was added, and `tests/toc_check.lua` was not re-cut.**
The media is a runtime-path asset, exactly like Minimalist.tga and Expressway.ttf.

## 5. The presets question

`bar_appearance_preset` is **not** an appearance-preset data table — it is the
AceConfig *group* for the "Progress Bar Appearance" panel
(`option_table_presets.lua:222`, consumed at `option_tables.lua:6846`). There
are no named appearance presets in this addon, so no preset can pin "Minimalist"
and silently override the default.

The only other thing that could override the default is a per-CLASS defaults
block. All ten of them (`ST.DEATHKNIGHT` / `DRUID` / `HUNTER` / `MAGE` /
`PALADIN` / `PRIEST` / `ROGUE` / `SHAMAN` / `WARLOCK` / `WARRIOR`) were checked
and **none** sets `bar_texture_key` or `gcd_texture_key` — they inherit
`ST.bar_defaults` through `['**']`. This is now pinned
(`tests/options_load_state.lua` section 28, with a non-vacuity floor of 9
blocks walked).

## 6. The degradation, and what it can and cannot detect

`fetch_statusbar_texture(key)` (bars.lua:34-55):

```
LSM:Fetch('statusbar', key)          -- the operator's / the user's choice
  -> LSM:Fetch('statusbar', "Minimalist")   -- the shipped fallback key
     -> "Interface\Buttons\WHITE8X8"       -- the client's own white pixel
```

* A **nil fetch** (the key is not in the registry, or the registered path is
  empty) now degrades to the shipped "Minimalist" texture instead of leaving the
  bar with no texture at all.
* A **dead registry** (every statusbar fetch nil) degrades to the client's white
  pixel — the bar is still visible, just flat.
* The fetch is pcall-guarded, so a throwing media library cannot abort the
  configuration pass mid-way and leave the bar untextured.

**Honest limit:** a *missing .tga file* cannot be detected by the fetch — LSM
returns the path regardless, and the client silently renders nothing for a path
that does not exist. The chain protects against a **nil/empty fetch** (a failed
registration, a broken registry, a key this build does not ship), not against a
file that was left out of the package. The file IS in the tree
(`Media/StatusBar/Wglass.tga`, 65580 bytes, Targa RGBA 256x64) and the
registration path matches it exactly, so this is a packaging risk only.

## 7. Mutation proofs (`/tmp/opencode/mut_wglass`)

The copy is the repo minus `.git`, `Media`, `docs`, `desks` (none are loaded by
the harness; `bench/` IS included because `tests/hunter_state.lua` reads a bench
file). Baseline on the copy: **41 steps, 0 failed, luacheck 2/0**.

| Mutant | Killed by |
|---|---|
| A — `bar_texture_key` back to "Minimalist" | bars_state (16 texture pins) + options_load_state ("the swing bar's default texture is the operator's Wglass") |
| A2 — `gcd_texture_key` back to "Minimalist" | bars_state (16 texture pins) + options_load_state (GCD default pin) |
| B — the degradation removed (a nil fetch leaves the bar textureless) | bars_state (7 checks, incl. "a nil fetch never leaves a bar textureless") |
| B2 — the degradation stops at the fallback key (no last resort) | bars_state (4 checks, incl. "a dead media registry still leaves the swing bar with the client's white pixel") |
| C — the Wglass medium is never registered | bars_state ("the Wglass medium is registered in the statusbar registry with the operator's path") + options_load_state (registration source pin) |
| D — the deadzone marker follows the progress bars' texture | bars_state ("the deadzone marker keeps Solid" x2) + options_load_state (deadzone default pin) |

**5/5 killed (0 survived).** Driver: `/tmp/opencode/mut_wglass_run.py`.

## 8. Operator notes / residual

* **Existing profiles keep their saved texture.** AceDB keeps a saved
  `bar_texture_key`; the new default applies to FRESH profiles (and to any hand
  the user never touched). An existing user must pick "Wglass" in the dropdown
  (Progress Bar Appearance -> Texture, and the GCD underlay panel) to see it.
  The operator's order was "default", so this is the honest consequence — not
  a defect — but it is the thing most likely to look like "the change did not
  work" in-game.
* **`Media/StatusBar/atlas.tga` (2.3 MB) is referenced NOWHERE** in the addon
  (checked: no .lua/.toc/.xml file outside `docs/` mentions it, and the only
  "StatusBar" matches are the `statusbar` LSM mediatype string). Its siblings
  `mask/` (2.6 MB), `png_color/` (528 KB), `Borders/` (24 KB) and `composite/`
  (20 KB) are unreferenced too. Reported, NOT deleted (out of scope). For
  context, the whole `Media/` folder is 187 MB.
* The operator's file was not moved or renamed.

## 9. In-client verification still owed

Offline proves: the registration, the defaults, the dropdown wiring, the
degradation chain, and that no other suite moved. It cannot prove that the
client renders a 256x64 Targa the way the operator intends on each of the seven
client families. An in-client look at the swing bar and the GCD underlay on one
classic-line client and one mainline-code client is still owed.
