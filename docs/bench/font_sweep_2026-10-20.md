# Font sweep — the `FontString:SetText(): Font not set` defect class

Date: 2026-10-20. Desk: `font-sweep`. Lane scope: the operator's TBC crash at
`hunter_ui.lua:309` + a tree-wide sweep of the same defect class.

## 1. The defect class

A `FontString` created with `CreateFontString` and given text **before** any
`SetFont` is rejected by the client: `FontString:SetText(): Font not set` (and
the frame is tainted). The two earlier fixes today are the pattern to copy:
`hud.lua`'s `apply_font` and `practice_ui.lua`'s `apply_result_font` — LSM font →
`STANDARD_TEXT_FONT` → the literal `Fonts\FRIZQT__.TTF`, every step pcall-guarded.

## 2. Sweep result (82 `CreateFontString` sites, `Libs/` + `docs/` + `tests/` excluded)

| Site | Verdict |
|---|---|
| `hunter_ui.lua:313` — the H1 target-warning label | **DEFECT** — `SetText` before `SetFont` (the operator's crash) |
| `hunter_ui.lua:261` — the Rapid Fire bar label | **DEFECT** — never fonted; written per frame at `:958`/`:984` |
| `hunter_ui.lua:349` — the badge text (`create_badge`) | **DEFECT** — never fonted; written at `:1042`/`:1095`/`:1219`/`:1298`/`:1380` |
| `hunter_ui.lua:222` — the cast-bar text | **HOLE** — `SetFont` guarded by `if font_path`, so an unresolvable LSM key leaves it fontless (written at `:603`/`:605`) |
| `bars.lua:148-150` — the three bar texts | **HOLE** — fonted in `configure_texts` (font before text ✓) but `LSM:Fetch('font', …)` unguarded → a nil path reaches `SetFont(nil, …)`, which throws out of the bar build |
| `hud.lua:493` | OK — own `apply_font`, pinned by `tests/hud_state.lua` §21 |
| `practice_ui.lua` (30 sites) | OK — own `apply_result_font` (out of scope for this lane; clean of the class) |
| `rotationtext.lua:318` | OK — own `apply_font`, applied by `apply_settings` at creation (`:324` → `:385`) before the first `set_text` |
| `designmode.lua:389` | OK — `SetFont(STANDARD_TEXT_FONT, …)` at creation |
| `nextaction_ui.lua:249/395/404/414` | OK — a literal path before every `SetText` |
| `practice_progress_ui.lua:794/845` | OK — `SetFontObject` (a font object) |
| `weave_range.lua:172`, `enemy_swing.lua:402` | OK — the `GameFontNormalSmall` template sets the font |
| `classes/druid.lua` (5), `classes/shaman.lua` (10), `classes/warrior.lua` (6), `classes/paladin.lua` (4) | OK — every site fonts at creation; the resolver (`get_tracker_font_path`, three identical copies) never returns nil (`STANDARD_TEXT_FONT or "Fonts\FRIZQT__.TTF"`) |
| `classes/rogue.lua` (3) | OK — `SetFont(STANDARD_TEXT_FONT, …)` before `SetText` (out of scope for this lane) |
| `ldb.lua`, `widgets.lua`, `classes/hunter.lua` | OK — no FontStrings at all (`ldb.lua`'s `SetText` is a GameTooltip) |

`LSM:Fetch` itself never throws (`Libs/LibSharedMedia-3.0` :251-256: a nil key is a
table read, an unknown key returns nil), so the holes above are the **nil result**,
not the call.

## 3. The fix

### 3.1 The shared chain — `utils.lua` (no new module, no TOC edit)

`utils.lua` is already in **all 7 flavor TOCs** and loads before every consumer
(`utils.lua` :38 in the classic-line TOCs, :37 in Mainline/Cata/Mists; `hunter_ui.lua`
:53/:50, `bars.lua` :59/:58). Putting the chain there avoids a new module (and the
7 TOC lines + `toc_check` coverage a new module would need) with the same
one-implementation result. The load order is now machine-checked
(`tests/toc_check.lua`: *utils.lua loads before every font consumer*).

- `st.utils.fetch_font_path(key)` — resolves an LSM font key to a path; never
  throws (missing LSM / throwing `Fetch` / nil key → nil).
- `st.utils.apply_font(text, path, size, outline)` — the chain: the caller's path
  → `STANDARD_TEXT_FONT` → `Fonts\FRIZQT__.TTF`; every step pcall-guarded; a
  candidate the FontString refuses (`SetFont` returns false, or `GetFont` stays
  nil) hands over to the next one; never throws.

The operator's case is covered: LSM resolves `Expressway` to
`Interface\AddOns\ChonkyCharacterSheet\Media\Fonts\Expressway.ttf` and the
FontString **receives that path** (it is the first candidate, not a fallback).

### 3.2 `hunter_ui.lua` — the four FontStrings

- `create_target_warning` — the font goes on **before** `SetText` (the crash).
- `create_rapid_fire_bar` — the label is fonted at creation (it never was).
- `create_badge` — the badge text is fonted at creation (it never was).
- `create_cast_bar` — the `if font_path then` hole is closed; the chain always
  lands a font.
- `ui.build` resolves the key through `st.utils.fetch_font_path` instead of a raw
  `LSM:Fetch`.

The badge/label/cast-bar sizes are the hand's configured `text_size` (default 12),
the same size the cast-bar text already used.

### 3.3 `bars.lua` — the font lines only

`LSM:Fetch('font', …)` → `st.utils.fetch_font_path(...)`, and the three
`SetFont(font_path, …)` calls → `st.utils.apply_font(...)`. No other bar line
touched.

### 3.4 Deliberately NOT changed

`hud.lua` (its helper is pinned by `tests/hud_state.lua` §21 — the two
`pcall(text.SetFont` sites and the `apply_font(f.text` / `apply_font(icon.text, db)`
call sites are pinned), `practice_ui.lua` (out of scope: a sibling lane owns it),
`classes/rogue.lua` (out of scope: another lane owns a load failure there), and
the class modules (audited safe — every site fonts at creation through a resolver
that never returns nil).

## 4. Pins

- `tests/hunter_state.lua` §28 (new): the sandbox FontString is now SoD-faithful
  (`SetFont(nil)` latches nothing, `SetText` with no font throws *Font not set*).
  Pins: the build throws nothing; the target-warning label, the cast-bar text,
  the Rapid Fire label and both badge texts carry a font; the label keeps its
  text; an unresolvable LSM font falls back to `STANDARD_TEXT_FONT`; no LSM font
  **and** no `STANDARD_TEXT_FONT` falls back to `Fonts\FRIZQT__.TTF`; a throwing
  `Fetch` never throws; the shared chain refuses a FontString without `SetFont`,
  survives a throwing `SetFont`, and degrades past a refused path; the
  **source order** (the font precedes the first `SetText`); no direct `SetFont`
  call survives in `hunter_ui.lua`.
- `tests/bars_state.lua` §10 (new): the three bar texts carry a font; an
  unresolvable font key never throws out of the bar build and still leaves a font
  that exists; `bars.lua` has no direct `SetFont` call and resolves the key
  through the shared chain. The bars FontString stub is SoD-faithful for the nil
  path.
- `tests/toc_check.lua` (new): *utils.lua loads before every font consumer* in
  every flavor TOC.

Counts: `hunter_state` 1708 → **1736** checks, `bars_state` 896 → **907**,
`toc_check` **1081**, all green. Full harness **43 steps, 0 failed** and luacheck
**2 warnings / 0 errors** (the pre-existing floor: `compat.lua:36`,
`main.lua:81`) on the tree as of 19:47. The six files this lane touched are
luacheck-clean on their own (0 warnings).

**Crossfire note (not this lane's red):** a later harness run shows
`tests/rogue_state.lua` failing its HU-7 pin (*the class table is mirrored onto
the addon namespace*). That is another lane's in-flight edit: `classes/rogue.lua`
was rewritten at 19:48 and dropped the `st.ROGUE = ST.ROGUE` namespace mirror
(see its comment at `:3690`), while `tests/rogue_state.lua` (18:47) still pins the
old shape. Proof that it is not this lane's: with this lane's `utils.lua` change
fully reverted in a `/tmp` copy, the same pin fails identically (1099 checks,
1 failure). The same wave briefly added a third luacheck warning
(`tests/wiring_check.lua:1654`, shadowing upvalue — that file was rewritten at
19:53; the count is back to the 2-warning floor now). This lane's six files are
luacheck-clean on their own. This lane's own suites are green
(`hunter_state` 1736/0, `bars_state` 907/0, `toc_check` 1081/0, `wiring_check`
772/0).

## 5. Mutation proofs (`/tmp/opencode/mut_font`, sources only — no Media/docs)

| # | Mutation | Result (line numbers are the mutant's own) |
|---|---|---|
| M1 | `hunter_ui.lua`: `SetText` moved back **before** the font on the target-warning label | suite **aborts** with the exact live error: `hunter_ui.lua:317: Font not set` (exit 1) |
| M2 | the badge text loses its font | suite **aborts** with `hunter_ui.lua:1041: Font not set` (exit 1) |
| M6 | the Rapid Fire label loses its font | suite **aborts** with `hunter_ui.lua:983: Font not set` (exit 1) |
| M3 | the `STANDARD_TEXT_FONT` step removed from the shared chain | 2 clean FAILs: *an unresolvable LSM font falls back to STANDARD_TEXT_FONT*, *the refused path falls back to STANDARD_TEXT_FONT* (exit 1) |
| M4 | `bars.lua` back to the raw `LSM:Fetch` + `SetFont` (a nil path reaches `SetFont`) | 6 clean FAILs, including *an unresolvable font key still leaves the left text with a font* (exit 1) |
| M5 | M1 + a sandbox that records instead of raising (so the crash cannot preempt the pins) | 2 clean FAILs: *the target-warning label still carries its text*, *the target-warning label is fonted before its first SetText (source order)* (exit 1) |

The mutation copy was restored byte-identical to the tree after the proofs.

## 6. Left for the operator / other lanes (not changed here)

- `practice_ui.lua` — out of scope for this lane, but its direct
  `SetFont(STANDARD_TEXT_FONT, …)` sites (e.g. `:2144`, `:2526`) are unguarded if
  `STANDARD_TEXT_FONT` were ever absent. The sibling lane that owns the file may
  want to route them through `st.utils.apply_font`.
- `classes/rogue.lua` — out of scope; same unguarded `STANDARD_TEXT_FONT` shape
  (`:1639`, `:1653`, `:1663`).
- `designmode.lua:390` — same unguarded `STANDARD_TEXT_FONT` shape (safe in the
  client: the global is always defined).
- `nextaction_ui.lua:415` uses the literal `Fonts\2002.TTF`; if a client does not
  ship that file the text renders blank (no error). Left as designed.
- In-client confirmation of the fix is still owed (offline pins only) — the
  operator's TBC session is the check.
