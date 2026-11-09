# Brief: swing-wire-hunt2 — bars still dead on Era + Anniversary WITH the strip in tree

Date: 2026-10-22. Operator in-client report (no further testing available —
operator done for the day): swing bars dead on Classic Era AND Classic
Anniversary with the current tree. The dispatcher strip (`main.lua:944-951`)
is in the tree, so D1-as-shipped does not explain it. Prior hunt:
`desks/swing-wire-hunter/journal.md` (D1–D7/U1–U7). Build + proctor for the
Forever items are done and PASS. This lane re-opens the Era/Anniversary
kill chain under the post-strip constraint. HU-25's harness route is now
the ONLY proof route (no in-client sessions); HU-29 (vendored lib) still
rules any `Libs/` touch — this lane is READ-ONLY and specs the harness,
it does not build it.

## Seat + mode

- Seat: `hunter`. READ-ONLY: no code edits, no file writes, no test runs,
  no git. Return the report as reply text; the orchestrator files it.
- Skills first (operator order): `skills_list`, then `skill_view` the
  lane skills (`bench-read`, `desk-open`, `desk-journal`, `signal-write`).
  Then journals before artifacts: `desks/journal.md`, your desk journal
  if present, `desks/swing-wire-hunter/journal.md`,
  `desks/swing-wire-build/journal.md`, `desks/swing-wire-proctor/journal.md`,
  `bench/lessons.md`. Missing skill → state which, proceed per
  `workshop.md` / `CAIRN.md` / `AGENTS.md`.
- `/home/sam/wow-ui-source`: `read`/`grep` blocked — use
  `ast_grep_search` (`lang: "lua"`); checked-out branch is `classic_era`
  only, so branch every claim; uncheckable = UNVERIFIED with exact
  close-out. If `ast_grep_search` is absent from your catalog, say so and
  use `search_files` inside the repo + mark branch claims UNVERIFIED.
- Standing: no git. Do not conclude from plausibility — every defect
  needs a file:line chain; every gap gets a U-item, never a guess.

## Verified inputs (exist on disk 2026-10-22)

- `main.lua:12` (lib load), `:20-46` (stub + 3-engine pick),
  `:75-77` (`SwingTimerInfo` closure over the `STL` upvalue),
  `:316-424` (`OnInitialize`: class read, DB, options, `lrc_ready=false`,
  `stl_ready = not SWING_ENGINE_AVAILABLE`, the two ready-callbacks,
  the 5 s deadline `:393-411` which reassigns `STL = make_swing_stub()`
  when the lib never reports),
  `:682-760` (`init_libs`: once-gate, `lrc_ready AND stl_ready` gate
  `:689-692`, `activate_class`, `init_timers`, `register_timer_callbacks`
  `:770-777` — six `SWING_TIMER_*` regs on whatever `STL` currently is),
  `:918-962` (dispatcher + strip), `:1042-1190` (handlers, speed-first),
  `:2058-2140` (diag: wire counts, `swing_last`, `proj=/exp=/bcc=`).
- `Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:2`
  (`local loadedAddonName = ...` — the LOADING addon's name),
  `:9-11` (frame + tooltip), `:264-274` (`SwingTimerInfo`),
  `:288-302` (`ADDON_LOADED`: returns unless
  `addOnName == loadedAddonName`, then creates player/target units),
  `:300-337` (`PLAYER_ENTERING_WORLD`: speeds then fires
  `UNIT_SWING_TIMER_INFO_INITIALIZED`), `:383-466` (CLEU),
  `:786-810` (frame event registrations + dispatch),
  `:817-845` (legacy re-fire + self-registration).
- `bars.lua:58-60`, `:713-722`, `:731-948` (incl. `engine_dead` render
  `:591-612`); `compat.lua:39-127` (family detect).
- Reference (operator: fully functioning on Era/TBC):
  `/home/sam/SuperSwingTimer-WoW/SuperSwingTimer.lua` (own CLEU frame,
  `RegisterEvents`, `OnEvent → HandleCLEU`) and
  `/home/sam/SuperSwingTimer-WoW/SuperSwingTimer_State.lua`
  (`HandleCLEU` ~`:1272`, `StartSwing`, `StartRangedSwing`,
  `ResetTimer`). It uses NO swing library — direct CLEU only.
- `SwedgeTimer.toc:15,18,24`, `SwedgeTimer_TBC.toc`,
  `SwedgeTimer_Vanilla.toc` (ship v7 registry + lib + swing_source).

## Questions (file:line chains only)

1. `loadedAddonName` gate: `...` at lib file scope under SwedgeTimer's
   TOC equals what — and does the client's `ADDON_LOADED` payload for
   OUR addon ever equal it (exact name incl. folder-name dependence)?
   If the units are never created: no `INFO_INITIALIZED` → deadline
   substitutes the stub at 5 s. Trace what happens next — which object
   gets the six callback registrations, what `init_timers` seeds, and
   whether any later lib traffic can still reach the bars. Is this a
   TOTAL kill (worse than D1: silent, all hands, both clients)?
2. Deadline ordering: enumerate every path where `init_libs` runs with
   the STUB as `STL` (deadline fired first) vs the lib. On the stub
   path, do the six registrations no-op forever (stub `RegisterCallback`
   is a no-op) even if the lib reports ready at 6 s? Is there any
   re-registration? What do the bars render on each path?
3. `init_libs` gate `:689-692`: on Era/Anniversary, what sets
   `lrc_ready` (LRC `CHECKERS_CHANGED` — does it fire there?) and
   `stl_ready` (lib `INFO_INITIALIZED` — gated on Q1)? If either never
   fires AND the deadline already ran, what is the steady state?
4. Registry delivery: v7 `Dispatch` with a FUNCTION callback
   (`self.callback_event_handler`) — confirm in
   `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` that function
   callbacks receive `(eventname, ...)` exactly like the lib's own
   self-registration expects. Any string-vs-function asymmetry between
   the app's six regs and the lib's internal regs?
5. Bar-side death: assuming events DO arrive post-strip, what in
   `bars.lua` / `check_weapons` / `init_visuals_template` / class
   activation could still leave every hand dark on every class (both
   clients)? Check `db.enabled` defaults, weapon checks, frame
   visibility, `OnUpdate` install per hand.
6. SST contrast: list every swing-sensing input SST handles DIRECTLY
   that SwedgeTimer delegates to the lib (own CLEU frame, ADDON_LOADED
   independence, no readiness gate, no registry). For each lib-side
   single point of failure, state the in-tree symptom it would produce
   and whether it matches "dead on Era AND Anniversary, no error".

## Deliverable (reply text; orchestrator files it)

- Ranked defects D8..Dn: symptom (hands/clients), root chain
  (file:line), verdict BROKEN/DEGRADED, fix direction in words
  (never touching `Libs/` without HU-29; app-side workarounds you may
  propose freely).
- Harness SPEC for the builder (HU-25 route, the only proof left):
  REAL vendored lib + REAL shipped v7 registry + REAL dispatcher,
  driven per family (Era / Anniversary): exact event sequence
  (`ADDON_LOADED` with the exact name payload, `PLAYER_ENTERING_WORLD`,
  CLEU `SWING_DAMAGE`, `SUCCEEDED(75)`, autorepeat), asserting each
  hand's bar state advances; plus the negative (deadline-first ordering)
  if Q2 confirms it. The spec must be written so the harness FAILS on
  the current tree.
- UNVERIFIED list with exact close-outs (all offline closers only —
  no in-client items: the operator is done for the day).
- Explicit non-findings + one-line residuals.
