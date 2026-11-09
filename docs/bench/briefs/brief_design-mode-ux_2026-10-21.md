# Brief: design-mode-ux (2026-10-21) — design + implementation lane

## Objective
Fix the design-mode UX the operator hit on Classic Era (2026-10-21), and add the
control frame the operator asked for.

## The operator's report (verbatim, Classic Era)
1. "when in design mode on classic era i cant move the options frame"
2. "design starts behind it" (the design visuals sit BEHIND the options panel)
3. "is it possible i can close options and keep in design mode"
4. "need a frame that has a button to lock frame mode"

## In-tree (read first, verify the shapes yourself)
- `designmode.lua` — the whole module. Key facts already established (re-verify, do
  not trust blindly):
  - `ensure_layer()` (~line 244): the full-screen design layer is created at frame
    strata `"BACKGROUND"` with a dim veil texture; it is registered in `UISpecialFrames`
    so Esc ends design mode, and its `OnHide` calls `DM.stop(true)`.
  - `ensure_guides()` (~line 271): a separate full-screen frame at strata `"DIALOG"`,
    `EnableMouse(false)`, carrying the snap guide lines.
  - `make_overlay(i)` (~line 372): one mouse-enabled `Button` per element, created with
    `CreateFrame("Button", nil, UIParent)`, `RegisterForDrag("LeftButton")`,
    `RegisterForClicks("LeftButtonUp")`, with the drag / double-click / tooltip handlers.
  - `attach(o, desc, frame)` (~line 500): `o:SetParent(frame)` and
    `o:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)` — a CHILD frame inherits its
    parent's strata, so an overlay cannot be raised above the AceConfig options dialog
    while it is parented to a low-strata element frame.
  - `DM.enter()` / `DM.stop()` / `DM.exit()` / `DM.toggle()` (~lines 976-1050).
- `tests/designmode_state.lua` — the offline suite you extend.
- `option_tables.lua:265-335` — the "Design Mode" options page (Start/Stop button +
  grid refresh buttons). READ ONLY for this lane unless the brief says otherwise.
- `main.lua:2039-2042` — `/st design` calls `st.designmode.toggle(self)`.

## Required behaviour (the contract)
R1. **The options panel must stay usable while design mode is on.** Nothing the design
    mode owns may swallow a mouse press over the options dialog: every full-screen
    design frame is explicitly mouse-transparent (`EnableMouse(false)`), and the
    mouse-enabled surface is limited to the per-element overlays and the new control
    frame. The operator must be able to drag the AceConfig options panel while design
    mode is active.
R2. **The design visuals must draw ABOVE the options dialog.** The grid/veil/guides and
    the element overlays must be visible while the options panel is open, so the
    operator can see what they are moving. (Today the layer is `"BACKGROUND"` and the
    overlays are children of low-strata element frames, so the options panel covers
    them.) Achieve this without breaking the overlay->target drag maths: if an overlay
    is re-parented to a high-strata container, it must keep tracking its target frame
    (drag tick included) and keep using the owning module's own save path
    (`desc.save`) — the db keys stay the single source of truth.
R3. **Closing the options panel must NOT end design mode.** Opening/closing the AceConfig
    dialog must leave design mode active and the visuals visible. Esc still ends
    design mode when nothing else is open. Verify the CURRENT behaviour offline first
    and pin it; if it already holds, pin it as a regression test rather than changing
    code.
R4. **A dedicated design-control frame with a LOCK button.** A small, movable panel
    (its own frame, above the design visuals, mouse-enabled only on its own buttons)
    that appears while design mode is active and offers:
      - a LOCK/UNLOCK toggle button: locked = the element overlays are shown but NOT
        draggable (frames frozen in place), unlocked = the current behaviour;
      - an EXIT button that ends design mode (the same path as `/st design`).
    Both buttons need readable labels and a visible state (label/text change), and the
    frame needs a title so the operator knows what it is. The lock state is a SESSION
    state like design mode itself: it must not change any persisted default-visible
    behaviour, must not add a db key that changes what a fresh install shows, and must
    be nil-safe (`== false` hides / nil = off) if you do persist anything.
R5. **No new protected/secure calls; no frame creation in combat.** Design mode already
    refuses to start in combat (`DM.enter`) and closes on combat start
    (`DM.on_combat_start`); the control frame follows the same rule (created on enter,
    hidden on stop).
R6. **No behaviour change outside design mode.** The control frame must not exist (or
    must be hidden) when design mode is off, and the options panel, the bars and the
    other elements must behave exactly as they do today.

## Scope / write permission
- YOU OWN: `designmode.lua`, `tests/designmode_state.lua`.
- YOU MUST NOT edit: any other `.lua` in the repo, `option_tables.lua`, `main.lua`,
  the TOCs, `tests/run.sh`, `Libs/`. If you believe a file outside your scope must
  change, FILE it on the bench with the file:line and the reason — do not edit it.
- No git. No lint-config changes. Preserve file line endings. Whitespace fixes only
  inside touched lines. Warnings: wire, never silence with `_`.

## Tests (the lane's own proof)
- Extend `tests/designmode_state.lua` with checks for R1-R6 (offline, SoD-faithful
  stubs). Where the suite cannot model a frame, say so in the report instead of
  pretending.
- Mutation proofs on a `/tmp/opencode` COPY (never the working tree): every new guard
  gets a mutation that must fail the suite. Copy the tree WITHOUT `Media/`, `docs/`
  and `.git` (the media tree is 187 MB and will fill the tmpfs).
- Run `lua5.1 tests/designmode_state.lua` and `bash tests/run.sh` at the end; report
  the exact numbers. If another lane's in-flight work breaks an unrelated suite, report
  it as a crossfire, do not "fix" it.

## Mechanics (skills — CALL these tools, in order)
`bench-read` (your desk journal + `bench/lessons.md` + the bench, journals before
artifacts) -> `desk-open` `desks/design-mode-ux/` -> `desk-journal` (append what you
did, the current state, the next step) -> `signal-write` (done/checkpoint/hands-up JSON
into `desks/design-mode-ux/.signals/`).

## Deliverable
Bench file `bench/design_mode_ux_2026-10-21.md` (confirm absent before writing): what
changed, per-requirement, with file:line, the test numbers, the mutation list, and
every UNCONFIRMED item. In-client confirmation is still owed by the operator for R1/R2
(what the options panel looks like over the design visuals) — say so.

## Validation owner
The orchestrator: it re-reads the diff, re-runs the suite, and asks the operator for
the in-client confirmation.
