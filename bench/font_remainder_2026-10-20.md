# Font remainder — the last unguarded font sites, routed through the shared chain

Date: 2026-10-20. Desk: `font-remainder`. Lane scope: the sites the `font-sweep`
lane flagged in its own files (`practice_ui.lua`, `designmode.lua`,
`nextaction_ui.lua:415`, `classes/rogue.lua`) plus SoD-faithful sandbox FontStrings
in the suites that own those pins.

## 1. What the sweep left (the "before" state)

The sweep's report (`bench/font_sweep_2026-10-20.md` §6) left four files with a
bare `SetFont(...)`:

| File | Site (the sweep's own line numbers) | Before |
|---|---|---|
| `practice_ui.lua` | 13 sites (`:2144`, `:2526`, `:2531`, `:2925`, `:2933`, `:3073`, `:3172`, `:3211`, `:3520`, `:3684`, `:3815`, `:7905`, `:8025`) | `X:SetFont(STANDARD_TEXT_FONT, <size>, <flags>)` |
| `designmode.lua` | `:390` (the overlay title) | `o.title:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")` |
| `nextaction_ui.lua` | `:415` (the rotation pattern) | `frame.rotation_text:SetFont("Fonts\\2002.TTF", 12, "OUTLINE")` |
| `classes/rogue.lua` | `:1639`, `:1653`, `:1663` (the Era SS caption, the weapon-swap cost, the poison reminder) | `X:SetFont(STANDARD_TEXT_FONT, <size>, "OUTLINE")` |

Verified against the pre-edit tree (the 18:46 copy at
`/tmp/opencode/mutproof/control/practice_ui.lua:2144` reads
`panel.hint_text:SetFont(STANDARD_TEXT_FONT, 9, "")`), so the "before" shape is
confirmed, not assumed.

**Why the bare `SetFont` was a hole and not a nit.** `STANDARD_TEXT_FONT` is a
*global path string* the client defines per locale, not a font object:
`/home/sam/wow-ui-source/Interface/AddOns/Blizzard_Fonts_Shared/Shared/GameFonts.xml`
defines it as `Fonts\2002.TTF` (koKR), `Fonts\ARKai_T.ttf` (zhCN),
`Fonts\blei00d.TTF` (zhTW), `Fonts\FRIZQT___CYR.TTF` (ruRU) and
`Fonts\FRIZQT__.TTF` (everything else). It exists on every live client, so the
bare call works today — but it is **unguarded**: a client without the global hands
`SetFont` a nil path, the FontString stays fontless, and the next `SetText` throws
the operator's live error (`FontString:SetText(): Font not set`). The literal
`Fonts\2002.TTF` was the same hole with a file that a client may not ship: a
missing file leaves the FontString fontless (blank text today, the same latent
failure tomorrow).

## 2. The fix — one implementation, the shared chain

Everything goes through `st.utils.apply_font` (`utils.lua`: the caller's path →
`STANDARD_TEXT_FONT` → `Fonts\FRIZQT__.TTF`; every step pcall-guarded; a font the
FontString refuses hands over to the next candidate; the call never throws).

> **Provenance.** When this session sat down, the source half for `practice_ui.lua`,
> `designmode.lua` and `classes/rogue.lua` was already in the tree (file mtimes
> 20:02, right after the TBC client's font list was fetched at 20:01 — the desk
> journal had no entry, so the lane that made those edits is unattributed). This
> session **verified those 17 sites line by line** against the pre-edit copy
> (§1), completed `nextaction_ui.lua` (the three literal caption fonts, which were
> still bare `SetFont` calls), and landed the whole suite half. The numbers below
> describe the tree as it stands now.

* **`practice_ui.lua`** — the 13 bare `SetFont` calls are now
  `st.utils.apply_font(X, STANDARD_TEXT_FONT, <size>, <flags>)`. The font that
  renders is **unchanged**: the chain's first candidate is the same path the bare
  call passed.
* **`designmode.lua:390`** — the overlay title goes through the chain the same way.
* **`nextaction_ui.lua`** — the rotation pattern keeps `"Fonts\\2002.TTF"` as the
  chain's first candidate (the file that renders today), and the three literal
  caption fonts (`caption`, `hold.text`, `label`, all
  `"Fonts\\FRIZQT__.TTF"`) now go through the chain too, so the file is no longer a
  bare assumption. Same first candidate everywhere → **no default-visible change**.
* **`classes/rogue.lua`** — the three captions go through the chain; the font
  lines only, nothing else in the file touched.

`utils.lua` needed **no extension**: the helper's existing defaults (size 12,
outline `""`) cover every call site, and the chain already refuses a font the
FontString will not take.

**Load order.** `utils.lua` loads before all four consumers in **all 7** flavor
TOCs (`utils.lua` at :38 / :37; `nextaction_ui.lua` :61/:60, `practice_ui.lua`
:62/:61, `designmode.lua` :66/:65, `classes\rogue.lua` :77/:76). No TOC change.

## 3. The sandbox is now SoD-faithful in the suites this lane touches

A `SetText` with no font must **throw** in the sandbox, so a fontless site fails
the suite instead of the client's chat box.

| Suite | Before | After |
|---|---|---|
| `tests/practice_ui_state.lua` | already SoD-faithful (the `sod-practice-font` lane) | kept; `GetFont` now also reports a font object (the client reports the font object's own path); the `_G` mirror no longer leaks a stub into the next build (§3.1) |
| `tests/designmode_state.lua` | `SetFont` always latched, `SetText` never threw | `SetFont(nil)` latches nothing and returns false; `SetText` with no font throws `Font not set` |
| `tests/rogue_state.lua` | `SetFont` always latched, `SetText` never threw | same shape as above |
| `tests/nextaction_state.lua` | no UI sandbox (it loads the pure engine only) | a per-site source scan over `nextaction_ui.lua` (see §4) |

### 3.1 A sandbox leak found while pinning the fallback

The practice sandbox mirrors its stubs into `_G` for the duration of `compat.lua`'s
load and restores `_G` afterwards. The restore loop iterated `pairs(mirrored)`,
and `mirrored[name] = rawget(_G, name)` **stores nothing when the previous value
was nil** — so a stub whose previous value was nil was never restored, and the
sandbox's `STANDARD_TEXT_FONT` stayed in `_G` for every later build. The env's
`__index = _G` then handed it back to any build that asked for a *missing*
standard font, which would have made every "missing `STANDARD_TEXT_FONT`" check
vacuous. The names are now kept in a list and restored by name (assigning nil
removes the key), and a pin states the rule: a build without a standard font
really has none, and the sandbox leaves no `STANDARD_TEXT_FONT` behind. Mutant
M14 (the leak back) is killed by that pin.

The designmode sandbox does not mirror into `_G`, so it never had the leak.

## 4. The pins

* **`tests/practice_ui_state.lua`** (2493 → **2522** checks) — new section
  *"SoD font (2)"*: the init never throws; the hint line carries the standard
  font; the six font-object panel lines carry a font; a missing
  `STANDARD_TEXT_FONT` falls back to the classic client font; the shared chain's
  own contract (a refused font degrades to `STANDARD_TEXT_FONT`; a caller without
  a path gets `STANDARD_TEXT_FONT`; the chain without `STANDARD_TEXT_FONT` lands
  the classic client font); the sandbox states the rule it now keeps (a build
  without a standard font really has none, and no stub is left behind); a
  **source scan over every `CreateFontString` site in `practice_ui.lua`** — the
  font must be applied before the first `SetText`, matched on the variable
  expression so a same-named variable in another function cannot satisfy a site;
  no direct `SetFont` survives in the file.
* **`tests/designmode_state.lua`** (497 → **512**) — new section *17*: entering
  design mode never throws; every overlay title carries a font (the standard
  font, proven with a distinctive value); a missing `STANDARD_TEXT_FONT` falls
  back to the classic client font; the source order (the chain call precedes the
  first `o.title:SetText`) and no direct `SetFont` survives in `designmode.lua`.
* **`tests/nextaction_state.lua`** (625 → **631**) — new section: a source scan
  over `nextaction_ui.lua` (4 FontString sites, every one fonted before its first
  `SetText`); the rotation pattern goes through the chain with its own file
  first; no direct `SetFont` survives in the file.
* **`tests/rogue_state.lua`** (1100 → **1116**) — new section: `post_init` never
  throws; the three captions carry the standard font and keep their text; the
  source order per caption; no direct `SetFont` survives in `classes/rogue.lua`.

The scanner is the same shape in the three suites that own one (per site,
expression-matched, a helper call counts as the font application).

## 5. Mutation proofs (`/tmp/opencode/font_rem`, sources only — no Media/docs/bench)

Base: a byte copy of the tree. Each mutant = the base plus ONE edit.

| # | Mutation | Result |
|---|---|---|
| M1 | `practice_ui.lua`: the hint line loses its font | suite **aborts with the client's exact error**: `practice_ui.lua:2145: Font not set` (exit 1) |
| M2 | the hint line is texted **before** its font (the sweep's M1 shape) | same abort: `practice_ui.lua:2145: Font not set` (exit 1) |
| M3 | the keybind prompt loses its font (a site the sandbox never builds) | abort: `practice_ui.lua:2584: Font not set` — the **source scan** catches it (exit 1) |
| M4 | `designmode.lua`: the overlay title loses its font | abort: `designmode.lua:520: Font not set` (exit 1) |
| M5 | `nextaction_ui.lua`: the rotation pattern goes back to a bare `SetFont` | 3 clean FAILs (the chain pin, the order pin, the no-direct-SetFont pin) |
| M6 | the rotation pattern loses its font | 4 clean FAILs (the scan reports it as never fonted) |
| M7 | `classes/rogue.lua`: the SS caption loses its font | abort: `classes/rogue.lua:1639: Font not set` (exit 1) |
| M8 | `utils.lua`: the chain loses its `STANDARD_TEXT_FONT` step | 2 clean FAILs in `practice_ui_state` (the refused-font and the no-path pins) |
| M9 | `practice_ui.lua`: the hint line goes back to a bare `SetFont` | 1 clean FAIL (no direct `SetFont` survives) |
| M10 | `designmode.lua`: the overlay title goes back to a bare `SetFont` | 3 clean FAILs |
| M11 | `classes/rogue.lua`: the SS caption goes back to a bare `SetFont` | 2 clean FAILs |
| M12 | `utils.lua`: the chain loses its **classic-client fallback** step | the designmode suite fails (the overlay title gets no font → `designmode.lua:521: Font not set`) |
| M13 | the same, against the practice suite | 3 clean FAILs (the panel's hint line gets no font → `practice_ui.lua:2146: Font not set`) |
| M14 | the practice sandbox leaks `STANDARD_TEXT_FONT` into the next build again | 1 clean FAIL (the sandbox-fidelity pin) |

**14 of 14 killed.** The five "font stripped" mutants (M1, M2, M3, M4, M7) die
with the exact live error text, not a proxy; M12/M13 show the chain's fallback
step is load-bearing for the panel and the overlay.

## 6. Tree-wide state (the "Done means" clause)

A scanner over the shipped tree (82 `CreateFontString` sites, `Libs/`, `docs/`,
`tests/`, `Media/` excluded): **every site is fonted before its first `SetText`**.
The six sites the scanner cannot see are accounted for by hand:

* `bars.lua:148-150` — fonted in `configure_texts` through the shared chain
  (`bars.lua:321`, `:341`, `:361`) before any text is written.
* `rotationtext.lua:318` — fonted by its own `apply_font(self, frame.text)` in
  `RT.apply_settings` (`rotationtext.lua:388`), which `apply_settings` calls at
  creation (`:325`).
* `weave_range.lua:172` and `enemy_swing.lua:402` — created with the
  `GameFontNormalSmall` template, which carries the font.

`rotationtext.lua`'s own helper keeps a bare
`fs:SetFont(STANDARD_TEXT_FONT, size, outline)` fallback: on every live client the
global exists (the client's `GameFonts.xml` above), so it is not a hole today; it
is **out of this lane's scope** and is left as it is.

## 7. State of the tree

Harness **43 steps, 0 failed**; luacheck **2 warnings / 0 errors** (the
pre-existing floor: `compat.lua:36`, `main.lua:81`). The suites this lane
touched: `practice_ui_state` 2493 → **2522**, `designmode_state` 497 → **512**,
`nextaction_state` 625 → **631**, `rogue_state` 1100 → **1116** — all green.
`toc_check` **1081** (unchanged). Line endings kept (CRLF in the addon files, LF
in the suites); no trailing whitespace on the touched lines; **no new file-scope
local** (`practice_ui.lua` is still the tightest file at 199, `toc_check` says so
on every run). The nine files this lane touched are luacheck-clean on their own
(0 warnings / 0 errors).

## 8. Left for the orchestrator / other lanes (not changed here)

1. **`tests/toc_check.lua`'s `FONT_CONSUMERS` does not list this lane's four
   consumers** (it lists only `bars.lua` and `hunter_ui.lua`). The load order is
   correct today in all 7 TOCs (evidence in §2), but the machine check does not
   cover the new consumers. One-line follow-up in `tests/toc_check.lua:130`:
   add `"practice_ui.lua"`, `"designmode.lua"`, `"nextaction_ui.lua"`,
   `"classes\\rogue.lua"`. Left alone here (that suite is not in this lane's
   scope).
2. **`tests/guide_contract.lua` loads `nextaction_ui.lua` with a FontString stub
   that is not SoD-faithful.** A fontless site there would not fail that suite.
   Out of scope here; the nextaction pins live in `nextaction_state.lua`.
3. **In-client confirmation is still owed.** Every pin in this report is
   offline; the operator's TBC session is the real check (the font that renders
   is unchanged, so the visible result should be identical).
