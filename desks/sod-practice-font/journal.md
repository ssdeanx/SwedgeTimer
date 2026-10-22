# Sod Practice Font — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Fix live SoD crash `FontString:SetText(): Font not set` from `practice_ui.lua` `build_result_frame` (:737 CreateFontString, :741 SetText) via `init` (:722) <- `classes/shaman.lua:1218 post_init`. Mirror `hud.lua` `create_icon` hardening.
- **Scope:** `practice_ui.lua` (font-at-creation fix only + full-file CreateFontString-then-SetText audit) and `tests/practice_ui_state.lua` (+ `tests/practice_state.lua` only if it covers the result frame).
- **Next step:** Implement font-before-SetText + STANDARD→FRIZQT fallback chain, pcall-guarded, nil-safe; pin with SoD-faithful stub mutants; hold 38/0 + luacheck floor.

## 2026-10-19 — Fix landed, verified offline
- **Worked on:** `practice_ui.lua` result-frame SoD crash (`build_result_frame` SetText-before-font via `init` <- `classes/shaman.lua:1218 post_init`). Added `apply_result_font` (mirrors `hud.lua apply_font`: LSM -> STANDARD_TEXT_FONT -> FRIZQT__.TTF, all pcall-guarded, nil-safe); font-before-first-SetText in `build_result_frame`; `update_result_font` re-applies through the same helper. Audited all 30 CreateFontString sites: no other SetText-before-font ordering survives. `tests/practice_state.lua` glob-verified: no result-frame coverage, untouched.
- **Current state:** `tests/practice_ui_state.lua` stub is SoD-faithful (SetText w/o font throws, SetFont(nil) latches nothing) + 1008 checks incl. new SoD section (strict creation, nil-LSM, throwing-Fetch, missing-LSM, STANDARD-hidden result-path pins, single-restyle-path source pins). Mutants killed on /tmp/opencode copies: font-strip (live `Font not set` crash repro), literal-fallback break, unguarded Fetch, gutted restyle path. Harness 38/0, luacheck 2/0 floor held; both touched files luacheck-clean; CRLF/LF preserved; touched-lines whitespace clean.
- **Next step:** Orchestrator validation (owns Done). Filed, no side quest: panel's direct `SetFont(STANDARD_TEXT_FONT)` sites (e.g. hint_text :944-946) are unguarded if STANDARD were ever absent -- live clients define it, and hardening them is out of scope for this lane. In-client SoD confirmation still owed (UNCONFIRMED, like all offline pins).

## 2026-10-19 — [signal:done] SoD practice result-frame font fix verified offline
- Harness 38/0 + luacheck 2/0 held; 4/4 mutants killed; audit 30/30 clean.
