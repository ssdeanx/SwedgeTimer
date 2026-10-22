# design-mode-ux — Journal

## 2026-10-21 — Desk opened + R1–R6 landed (single session)
- **Purpose:** design-mode UX lane for the operator's Classic Era report (bench/briefs/brief_design-mode-ux_2026-10-21.md):
  options panel usable in design mode (R1), design visuals above it (R2), Esc/closing options keeps the
  session (R3), a control panel with a LOCK button (R4), no protected calls/combat creation (R5), no
  change outside design mode (R6). Scope: `designmode.lua` + `tests/designmode_state.lua` ONLY.
- **Worked on:** re-verified the orchestrator's facts file (bench/design_mode_client_facts_2026-10-21.md)
  against the vendored AceGUI/AceConfig libs + classic_era FrameXML (CloseSpecialWindows hides EVERY
  shown UISpecialFrames entry, UIParentPanelManager.lua:1041-1050). Split every overlay into a
  mouse-transparent VISUAL at FULLSCREEN_DIALOG/130 (above the panel) + an INPUT button at FULLSCREEN
  (below the panel, so it can never steal the panel's title-drag mouse); raised the veil/grid to
  FULLSCREEN_DIALOG/110 `EnableMouse(false)` and the guides to 140; added
  `options_window_open()` + `sync_esc_registration()` (layer leaves UISpecialFrames while an options
  window is open; OnHide race backstop re-shows); added `ensure_control()` (title + "Lock frames"⇄
  "Unlock frames" + "Exit", session-only lock, guards at designmode.lua:513/:543). Extended the suite
  with sections 18-23 and client-faithful Show/Hide + an Esc model (`client_escape`).
- **Current state:** DONE and green in-tree: designmode_state **655/0** (was 512/0), `bash tests/run.sh`
  **43 steps 0 failed**, luacheck **2 warnings / 0 errors in 85 files** (floor held; my files 0/0),
  designmode.lua 55/190 locals, CRLF+LF endings preserved. **16/16 mutation proofs killed** on
  /tmp/opencode copies (driver /tmp/opencode/dmx_mutate.py, base dmx_base). Deliverable:
  `bench/design_mode_ux_2026-10-21.md` (facts, per-R file:line, numbers, mutation table, 7 UNCONFIRMED).
  No other file touched; two out-of-scope items FILED there (options-page copy wording; pre-existing
  Blizzard-center-panel Esc path).
- **Next step:** orchestrator re-reads the diff + re-runs the harness; **operator in-client confirmation
  of R1/R2 owed** (drag the options panel with design mode on; visuals over it), plus the two Esc probes
  listed in the report's UNCONFIRMED section (Esc immediately after opening options; veil readability
  over the panel).

## 2026-10-21 — [signal:done] R1–R6 landed, suite 655/0, harness 43/0, 16/16 mutations killed
- Done signal: `desks/design-mode-ux/.signals/2026-10-21T13:53:49Z.json` (run_id ses_ea1775d2affe0oL1dUYK72EUHg).
- Deliverable: `bench/design_mode_ux_2026-10-21.md`; scope held to designmode.lua + tests/designmode_state.lua.
