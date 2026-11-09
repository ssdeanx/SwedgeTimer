# design-mode-ux (2026-10-21) — design + implementation lane, DONE

Desk: `desks/design-mode-ux/`. Brief: `bench/briefs/brief_design-mode-ux_2026-10-21.md`.
Facts used (orchestrator-supplied, cited throughout): `bench/design_mode_client_facts_2026-10-21.md`.

## Files changed (exactly the owned scope)

| File | Change |
|---|---|
| `designmode.lua` | strata/level contract vs the options panel, mouse-surface split of the overlays, Esc/UISpecialFrames coordination, control panel + session lock (CRLF preserved; 55 file-scope locals, limit 190) |
| `tests/designmode_state.lua` | client-faithful Show/Hide, options-dialog + Esc modelling, R1–R6 sections 18–23, reworked pins (LF preserved) |

No other file touched (no `option_tables.lua`, `main.lua`, TOCs, `tests/run.sh`, `Libs/`). No git ops. No lint-config changes.

## The mechanism, per the orchestrator's facts (cited, not re-derived)

- **Fact A** — the options panel is the AceGUI "Frame" container at **FULLSCREEN_DIALOG / level 100**
  (`Libs/AceGUI-3.0/widgets/AceGUIContainer-Frame.lua:189-190`); the design layer was `BACKGROUND`
  and the guides `DIALOG` → **report #2 "design starts behind it" is proven by strata**. The
  AceConfig validation popup is `TOOLTIP / 100` (`AceConfigDialog-3.0.lua:554-555`) and stays on top.
- **Fact B** — the panel's title drag starts on the title's mouse-down and only ENDS in the title's
  own mouse-up (`AceGUIContainer-Frame.lua:40-43`, `:233-237`); a mouse-enabled design frame over the
  panel can eat that press → **report #1 "i cant move the options frame"**. Design mode now pins its
  input strata deterministically instead of inheriting the target frame's.
- **Fact C** — the panel is NOT in `UISpecialFrames`, the design layer IS (`designmode.lua` old :254):
  Esc hid the layer, its `OnHide` ran `DM.stop(true)` → **report #3**. Verified against the reference
  FrameXML: `CloseSpecialWindows()` hides **every shown** `UISpecialFrames` entry
  (`/home/sam/wow-ui-source .../UIParentPanelManager.lua:1041-1050`), reached from `CloseWindows`
  (`:1087`), and AceConfigDialog wraps that global to run `CloseAll` in the same press
  (`AceConfigDialog-3.0.lua:1845-1851`).

## R1 — the options panel stays usable  ✅ (code + tests; **in-client owed**)

What changed in `designmode.lua`:
- `CHROME` constants block, :74-85 — the whole layering contract in one place.
- `ensure_layer` :318-320 — strata `FULLSCREEN_DIALOG`, level **110**, and now explicitly
  `layer:EnableMouse(false)` (the veil + grid cover the panel's pixels, never its mouse).
- `ensure_guides` :358-360 — same strata, level 140, `EnableMouse(false)` (unchanged flag, now above the panel).
- `make_overlay` :463-466 + `attach` :620-629 — each element's overlay is now **two frames on
  UIParent with pinned strata** (no inheritance from the target): the mouse-enabled INPUT button at
  strata `FULLSCREEN` (a whole strata below the panel's `FULLSCREEN_DIALOG`, so it can never take a
  press meant for the panel), and a mouse-transparent VISUAL twin at `FULLSCREEN_DIALOG / 130`.
- The only design-owned mouse surface above the panel is the small control panel (its own ≤220×72
  rect) — R1's explicit exception; full-screen chrome is mouse-transparent everywhere.

Tests: section **18** (`tests/designmode_state.lua:1883-1924`) pins chrome transparency, input strata,
visual transparency, control-panel size, and that design mode never re-stratas/re-anchors the panel;
§19 runs a full drag with the panel open.

## R2 — design visuals draw above the options dialog  ✅ (code + tests; **in-client owed**)

- Z-order inside `FULLSCREEN_DIALOG`: **panel 100 < veil+grid 110 < overlay visuals 130 < guides 140 <
  control 150** (levels set in `ensure_layer` :319, `make_overlay`/`attach` :629, `ensure_guides` :359,
  `ensure_control` :1098-1101); input buttons at `FULLSCREEN / 1` (:621-622).
- Drag maths untouched: both overlay frames anchor to the element's `box` (`attach` :624-633), so they
  ride the target through the drag tick; `centre_offsets`/`move_centre`/`screen_rect` unchanged; the
  drop still calls `d.save(...)` → the db keys stay the single source of truth (`OnDragStop`, unchanged).
- Overlay show/hide now drives both frames (`refresh` :669/:675, `stop` :1207).

Tests: section **19** (`:1926-1967`) — strata/level ladder over the open panel, visual shown while the
panel is open, a real drag (grid snap 52/62), anchors on the box during the drag, and the bar's own
save seam receiving the snapped drop. NOTE: the ride-along is pinned **structurally** (anchors reference
the box; the client computes the geometry) — visual confirmation is in-client.

## R3 — closing the options panel never ends design mode  ✅ (code + tests)

Current behaviour first (brief requirement): nothing in `designmode.lua` hooks the panel's lifetime —
pinned as-is in §20(a) before the Esc work. Then:
- `options_window_open()` :280-287 — nil-safe: the floating AceConfig dialog (`ACD.OpenFrames[app]`
  shown) **or** the Classic `InterfaceOptionsFrame` host counts as open.
- `sync_esc_registration()` :298-313 — while **active and** an options window is open, the layer
  leaves `UISpecialFrames` (Esc's `CloseSpecialWindows` can't reach it, and AceConfigDialog's wrapper
  still closes the panel in the same press); it returns the moment the options are gone. Driven from
  `enter` :1187 and every layer `OnUpdate` frame :345 — so one Esc closes the options and KEEPS the
  session, and the NEXT Esc (nothing else open) ends design mode as before.
- OnHide backstop :327-337 — if the hide lands inside the ≤1-frame race window (options opened, sync
  not yet run), the layer re-shows itself and re-syncs instead of stopping.
- Inactive sessions keep the historic permanent registration (`want = not (active and options_open)`),
  a hidden layer in the list being a no-op — R6-safe.

Tests: section **20** (`:1969-2048`) — open/close pins, the two-Esc sequence (options die, session
lives → re-register → session ends), the OnHide race backstop, the Interface Options host, and the
inactive-registration pin. The Esc model is the client's own: `CloseSpecialWindows` hides every shown
entry, then `CloseAll` (helper `client_escape`, `:633-641`).

## R4 — control panel with LOCK/EXIT  ✅ (code + tests)

- `ensure_control()` :1095-1149 — built on the first **enter** (never at load, never in combat),
  `FULLSCREEN_DIALOG / 150`, movable (`SetMovable` + `RegisterForDrag` with a combat guard), title
  "SwedgeTimer design mode" (font applied **before** `SetText`, via `st.utils.apply_font`), LOCK button
  ("Lock frames" ⇄ "Unlock frames" — the label IS the visible state) and EXIT button ("Exit" →
  `DM.exit()`, the same path `/st design` takes). Hidden on `stop` :1220.
- `DM.is_locked()` / `DM.set_locked(v)` :1161-1169; session state only — **no db key**, nil = off,
  reset on enter :1186 and on stop :1203 (a fresh session always starts unlocked).
- Locked = overlays stay **shown but frozen**: `OnDragStart` guard :513, `OnDoubleClick` guard :543
  (reset would move a frame, so it freezes too — "frames frozen in place"), tooltip line :501-503
  announces the lock. Registry `desc.lock` seams (timers_locked etc.) are untouched and unrelated.

Tests: section **21** (`:2050-2123`) — default drag works, lock flips state + label, locked overlay
shown-but-refused (drag, tick, reset, position write), unlock restores the save seam, tooltip line,
exit-while-locked kills the session + lock, fresh-enter starts unlocked.

## R5 — no protected calls, no frame creation in combat  ✅

- All new API is non-secure (`CreateFrame`, `SetMovable`, `RegisterForDrag`, `StartMoving`,
  `EnableMouse`, `SetText`); frame creation happens only inside `DM.enter` **after** the
  `InCombatLockdown` guard (:1180-1187), and a fight start hides the control panel through the
  existing `stop`.
- Tests: section **22** (`:2125-2162`) — enter under lockdown creates **0 frames** (control panel
  included), refused exit in combat changes nothing, fight-start close hides the panel + clears the
  lock, and a static source sweep for protected-call patterns.

## R6 — no behaviour change outside design mode  ✅

- Nothing is created at load (`created_frames == 0` pin); after `stop` every design surface (veil,
  guides, inputs, visuals, control) is hidden, the lock is off, the options panel keeps its own state,
  and a second enter/exit cycle rebuilds nothing.
- Tests: section **23** (`:2164-2201`) + the existing load/teardown pins (updated for the new frames).

## Test numbers (exact)

- `lua5.1 tests/designmode_state.lua`: **655 checks, 0 failed** (baseline before this lane: **512 / 0**; +143 checks).
- `bash tests/run.sh`: **43 steps, 0 failed**; luacheck line: **Total: 2 warnings / 0 errors in 85 files** —
  the standing floor held (both warnings pre-existing, other files).
- My two files under luacheck: **0 warnings / 0 errors**.
- `tests/toc_check.lua` (inside the harness): `designmode.lua: 55 file-scope locals (limit 190, headroom 145)`; toc 1081/0.
- Line endings re-verified: `designmode.lua` CRLF, `tests/designmode_state.lua` LF.

## Mutation proofs — 16/16 KILLED (copies on `/tmp/opencode`, tree without `Media/`, `docs/`, `.git`)

Procedure: `rsync -a --exclude=Media --exclude=docs --exclude=.git` → per-mutation fresh copy → one
exact string replace → run `lua5.1 tests/designmode_state.lua` → non-zero exit required.
Driver kept at `/tmp/opencode/dmx_mutate.py`, base copy `/tmp/opencode/dmx_base`.

| # | Mutation (file: designmode.lua unless noted) | Result |
|---|---|---|
| M1 | `layer:EnableMouse(false)` removed | **killed** exit=1, 2 failed — "the layer never takes mouse (got nil, want false)" |
| M2 | layer strata → `"BACKGROUND"` | **killed** exit=1, 2 failed — "the layer sits above the options panel (got BACKGROUND…)" |
| M3 | `input_strata` → `"FULLSCREEN_DIALOG"` (input rises onto the panel) | **killed** exit=1, 7 failed — "the input sits below the options panel's strata" |
| M4 | visual `SetFrameStrata` → `"MEDIUM"` | **killed** exit=1, 2 failed — "the visual draws above the options panel" |
| M4b | visual `SetFrameLevel` → 50 (below the panel) | **killed** exit=1, 2 failed — "the visual draws over the panel and the veil (got 50, want 130)" |
| M5 | OnHide race backstop condition → `if false` | **killed** exit=1, 2 failed — "R3: OnHide re-shows the layer… (got false, want true)" |
| M6 | `sync_esc_registration` → `local want = true` | **killed** exit=1, 3 failed — "R3: while the panel is open the layer is out of UISpecialFrames (got true…)" |
| M7 | lock guard removed from `OnDragStart` | **killed** exit=1, 2 failed — "R4: locked, the drag is refused (got true, want nil)" |
| M8 | lock guard removed from `OnDoubleClick` | **killed** exit=1, 1 failed — "R4: locked, no position is written (got 11, want nil)" |
| M9 | `control:Hide()` removed from `stop` | **killed** exit=1, 4 failed — "exit hides the control panel (got true, want false)" |
| M10 | `DM.set_locked(false)` removed from `stop` | **killed** exit=1, 2 failed — "R4: the session lock dies with the session (got true…)" |
| M11 | `control:Show()` removed from `enter` | **killed** exit=1, 3 failed — "the control panel is shown with the session (got false…)" |
| M12 | `ensure_control()` moved before the combat guard in `enter` | **killed** exit=1, 3 failed — "enter in combat creates no frames (got 3, want 0)" |
| M14 | `ensure_control()` invoked at file load | **killed** exit=1, 7 failed — "no frames are created at file load (got 3, want 0)" |
| M15 | `guides:EnableMouse(false)` removed | **killed** exit=1, 2 failed — "the guides never take mouse (got nil…)" |
| M16 | `InterfaceOptionsFrame` branch removed from `options_window_open` | **killed** exit=1, 1 failed — "R3: an open Interface Options window drops the layer too" |

Two first-attempt mutations exposed test-harness flaws (a 3-arg `check(...)` call and a finder that
depended on `guides.mouse`); the suite was fixed first, then the full battery re-run — the table above
is the re-run. Both fixes are in the owned test file only.

## Deliberately left out (with reasons)

1. **No db key for the lock** — the brief allows persistence but requires session semantics; a session
   state is strictly safer (no fresh-install delta, no `== false`/nil matrix to document for the options pass).
2. **`option_tables.lua` copy untouched** — the Design Mode page text ("Esc or /st design ends it") is
   still true when no options window is open; adding control-panel/lock wording is a copy edit in a file
   this lane does not own. FILED as an optional follow-up for the options lane (not required by R1–R6).
3. **Blizzard center-panel Esc path unchanged** — `CloseWindows` (UIParentPanelManager.lua:1087) also
   runs `CloseSpecialWindows` when ANY Blizzard center panel opens, so opening e.g. the Character panel
   with design mode on and no options open still ends the session — this is pre-existing behaviour,
   outside R1–R6 (which cover the AceConfig dialog), and deliberately not changed.
4. **No `SetUserPlaced`/position cache for the control panel** — its position survives within a play
   session (pooled frame, hidden not destroyed) but is not written to the client layout cache, keeping
   "no persisted default-visible behaviour" literally true.
5. **No TOC/test-runner changes** — no new files were added.

## UNCONFIRMED (honest list)

1. **In-client confirmation of R1/R2 is OWED BY THE OPERATOR** — that the options panel can be dragged
   with design mode on, and that the grid/veil/guides/overlay outlines now draw over the panel
   (offline tests pin strata/level/mouse flags; they cannot render).
2. **The veil now dims the options panel** (35% black over it, per R2's explicit "grid/veil … must be
   visible while the options panel is open"). Readability under the veil is an operator call; if it
   reads badly in client, the lever is the veil's alpha/strata (filed, not changed).
3. **`layer:Show()` inside `OnHide`** (the race backstop) is standard client behaviour but not
   executable offline; the PRIMARY mechanism (list membership) is plain Lua and fully pinned. If the
   client ever suppresses re-show-from-OnHide, only the ≤1-frame race window regresses (Esc right as
   the panel opens) — worth one in-client probe: open options, Esc immediately, design mode must live.
4. **Mouse fall-through of a mouse-transparent frame sitting above the panel** (overlay visuals, veil)
   is core WoW hit-testing, cited from FrameXML/strata rules, not executed offline — same in-client
   confirmation as item 1 covers it.
5. **Control panel default position** (UIParent top-left, 20/-96) vs the user-placed options panel
   could overlap on some resolutions; the panel is movable and so is the control panel, but the default
   clearance is UNCONFIRMED in client.
6. **Mainline/Forever clients**: `InterfaceOptionsFrame` does not exist there (nil-safe skip); the
   floating-dialog check works on every family. Esc-coordination for the *retail Settings hub* is
   UNVERIFIED — the operator's report and facts A–C are Classic Era.
7. **Overlay staleness ≤0.5s**: overlays are no longer children of their target, so a target that hides
   between refresh ticks keeps its overlay until the next tick (was instant). Session-only, cosmetic,
   called out rather than hidden.

## Validation run (final tree)

- `lua5.1 tests/designmode_state.lua` → **655 checks, 0 failed**
- `bash tests/run.sh` → **43 steps, 0 failed** (luacheck **2 warnings / 0 errors in 85 files**)
- Mutations → **16/16 killed** (table above)
