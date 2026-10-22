# Font Sweep — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Fix the live `FontString:SetText(): Font not set` crash the operator's TBC client shows at `hunter_ui.lua:309` (the hunter target-warning label), and sweep the whole tree for the same defect class (a FontString given text before any `SetFont`).
- **Scope:** `hunter_ui.lua` (the crash), `bars.lua` (font lines only, if the sweep finds one), `utils.lua` (the shared font chain - chosen over a new module, see the entry below), `tests/hunter_state.lua` (owns hunter_ui pins), `tests/bars_state.lua` (owns bars pins). Out of scope per dispatch: `classes/rogue.lua`, `practice_ui.lua`, `option_tables.lua`, `config_presets.lua`, `main.lua`, `diag.lua`, `compat.lua`, `run.sh`, the TOCs, versions, README, CHANGELOG, docs.
- **Next step:** Implement the shared chain in `utils.lua`, fix the four hunter_ui FontStrings, harden the `bars.lua` font lines, pin both in their owning suites, prove the pins with mutants on `/tmp/opencode` copies, hold the harness green + the luacheck floor.

## 2026-10-20 — Tree-wide sweep done (read-only) — findings
- **Worked on:** Read every `CreateFontString` site in the tree (79 sites, script + per-file read; `Libs/`, `docs/`, `tests/` excluded). Classified each as font-before-text / never-fonted / template-font.
- **Current state — the defect class (text before any font) exists ONLY in `hunter_ui.lua`, 4 sites:**
  - `hunter_ui.lua:308-313` — the target-warning label: `SetText` at :309 runs BEFORE `SetFont` at :312 → **the operator's live crash**.
  - `hunter_ui.lua:256-259` — the Rapid Fire bar label (`bar.label`): **never given a font at all**; text is written per frame at :945 and :971.
  - `hunter_ui.lua:340-342` — the badge text (`frame.text` in `create_badge`): **never given a font**; text is written at :1029, :1082, :1206, :1285, :1367.
  - `hunter_ui.lua:217-224` — the cast-bar text: `SetFont` is guarded by `if font_path`, so an unresolvable LSM key leaves it fontless and the :590 `SetText` would crash the same way.
- **Second-order hole (same family):** `hunter_ui.lua:350` and `bars.lua:293` call `LSM:Fetch("font", <key>)` unguarded; a key that no longer resolves (the operator's `Expressway` lives in another addon's LSM - if that addon is ever disabled) returns nil. `bars.lua` then calls `SetFont(nil, …)`, which throws; `hunter_ui.lua` skips the font and crashes on the first `SetText`. `LSM:Fetch` itself never throws (verified in `Libs/LibSharedMedia-3.0` :251-256 — a nil key is a read, and an unknown key returns nil), so the hole is the nil result, not the call.
- **Verified SAFE (font before text, non-nil path, no throw) — no change needed:**
  - `hud.lua:493` (own `apply_font`, pinned by `tests/hud_state.lua` §21) — untouched on purpose.
  - `practice_ui.lua` (own `apply_result_font`; all 30 sites audited) — OUT OF SCOPE (sibling lane), and clean of the defect class anyway.
  - `rotationtext.lua:318` (own `apply_font`, applied at :324 before the first `set_text`), `designmode.lua:389` (`SetFont(STANDARD_TEXT_FONT, …)` at creation), `nextaction_ui.lua:249/395/404/414` (literal paths before `SetText`), `practice_progress_ui.lua:794/845` (`SetFontObject`), `weave_range.lua:172` + `enemy_swing.lua:402` (the `GameFontNormalSmall` template sets a font), `ldb.lua` (a GameTooltip, not a FontString), `widgets.lua` + `classes/hunter.lua` (no FontStrings at all).
  - The four class modules with FontStrings: `classes/druid.lua` (5 sites), `classes/shaman.lua` (10), `classes/warrior.lua` (6), `classes/paladin.lua` (4) — every site calls `SetFont` at creation, and their resolver (`get_tracker_font_path`, three identical copies) already falls back to `STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"`, so the path is never nil. `classes/rogue.lua` (3 sites) is OUT OF SCOPE and is clean too.
- **Next step:** Implement. Shared chain goes in `utils.lua` (NOT a new module - see below).

## 2026-10-20 — Fix landed, verified offline
- **Worked on:** `utils.lua` — the shared font chain (`st.utils.fetch_font_path` + `st.utils.apply_font`: the caller's path -> `STANDARD_TEXT_FONT` -> `Fonts\FRIZQT__.TTF`, every step pcall-guarded, never throws). `hunter_ui.lua` — all four FontStrings fonted before their first `SetText` (the target-warning label = the operator's crash; the Rapid Fire label and the badge text, which never had a font at all; the cast-bar text, whose `if font_path then` hole is closed) and the key resolved through the shared chain. `bars.lua` — the font lines only: the raw `LSM:Fetch` + `SetFont` are now the shared chain, so an unresolvable key can no longer hand `SetFont` a nil path. Pins: `tests/hunter_state.lua` §28 (SoD-faithful FontString stub: `SetText` with no font throws *Font not set*), `tests/bars_state.lua` §10 (nil-path-safe fontstring stub), `tests/toc_check.lua` (*utils.lua loads before every font consumer*, 7 TOCs).
- **Decision — why `utils.lua` and not a new module:** `utils.lua` is already in all 7 flavor TOCs and loads before every font consumer, so the shared chain needs NO TOC edit, NO `toc_check` module-coverage change, and cannot break a client that never loads it. A new `fonts.lua` would have needed 7 TOC lines from the orchestrator first - a window where the addon breaks. The load order is pinned instead.
- **Current state:** harness **43 steps, 0 failed**; luacheck **2 warnings / 0 errors** (the pre-existing floor: `compat.lua:36`, `main.lua:81`). `hunter_state` 1708 -> **1736** checks, `bars_state` 896 -> **907**, `toc_check` **1081** — all green. CRLF kept on `utils.lua` (137/137), LF on `hunter_ui.lua`/`bars.lua`/the suites; no trailing whitespace on touched lines; no new file-scope locals (`utils.lua` 3, `toc_check` reports the tightest file still `practice_ui.lua` at 199).
- **Mutation proofs** (`/tmp/opencode/mut_font`, sources only - no Media/docs): M1 the old order on the target warning -> the suite **aborts with the exact live error** `hunter_ui.lua:317: Font not set`; M2 the badge text loses its font -> `hunter_ui.lua:1041: Font not set`; M6 the Rapid Fire label loses its font -> `hunter_ui.lua:983: Font not set`; M3 the STANDARD step removed from the chain -> 2 clean FAILs; M4 `bars.lua` back to the raw fetch + `SetFont` -> 6 clean FAILs; M5 M1 with a non-raising sandbox -> the source-order pin + the label-text pin fail cleanly. The copy was restored byte-identical to the tree.
- **Next step:** Orchestrator validation (owns Done). Left for other lanes / the operator (documented in `bench/font_sweep_2026-10-20.md` §6): `practice_ui.lua` and `classes/rogue.lua` keep their unguarded `SetFont(STANDARD_TEXT_FONT, …)` sites (both out of scope here), `designmode.lua:390` likewise, and in-client confirmation on the operator's TBC client is still owed (every pin here is offline).

## 2026-10-20 — [signal:done] Font sweep: the crash fixed, the tree audited, the pins proven
- Harness 43/0 + luacheck 2/0 held; 6/6 mutants killed (3 of them with the client's exact `Font not set` error); 82/82 FontString sites audited. Artifact: `bench/font_sweep_2026-10-20.md`.

## 2026-10-20 — Crossfire red, NOT this lane's
- **Observed:** a later harness run reports 43 steps / **1 failed** — `tests/rogue_state.lua`, pin *practice: the class table is mirrored onto the addon namespace (HU-7)*.
- **Cause:** another lane's in-flight edit. `classes/rogue.lua` was rewritten at 19:48 and dropped the `st.ROGUE = ST.ROGUE` namespace mirror (its own comment at `:3690` says so); `tests/rogue_state.lua` is still at 18:47 and pins the old shape.
- **Proof it is not mine:** with this lane's `utils.lua` change fully reverted in a `/tmp/opencode/rogue_check` copy, the same pin fails identically (1099 checks, 1 failure).
- **This lane's own suites:** `hunter_state` 1736/0, `bars_state` 907/0, `toc_check` 1081/0, `wiring_check` 772/0 — green.
- **Also not this lane's:** the wave briefly added a third luacheck warning (`tests/wiring_check.lua:1654`, shadowing upvalue — that file was rewritten at 19:53; the count is back to the 2-warning floor now). This lane's six files are luacheck-clean on their own (0 warnings).
- **Next step:** the owning lane lands its pin update; the orchestrator reconciles. Nothing for this desk to change.



