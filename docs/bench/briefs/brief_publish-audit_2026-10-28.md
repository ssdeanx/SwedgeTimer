# Brief — publish-audit (2026-10-28) — READ-ONLY

Desk: `publish-audit`. You are the independent verifier for a release candidate. This is a
READ-ONLY lane: you may run commands, read every file, and run the test suite, but you must
NOT edit product code, tests, TOCs or configs. Your only writes are your bench report and
your desk journal.

## Context

SwedgeTimer 2.1.3 (version deliberately NOT bumped). Today's wave, all landed in the working
tree by four lanes and reconciled by the orchestrator:

1. `hunter-tint` — the hunter Raptor/Steady queue tint now requires a live main-hand melee
   cycle and every clear path repaints the fill (a hunter at range can no longer recolour
   the melee bar).
2. `bars-decouple` — ranged/offhand visibility is receipt-driven (a real shot/swing opens a
   2-cycle window; combat state alone shows nothing); Shoot/Throw/Shoot Wand removed from
   the melee swing-reset list; generic shot->melee-reset guard on the engine's own
   `preventSwingReset` for every class; offhand renders at the mainhand size; the power bar
   owns the row below the melee stack and re-points on a position change.
3. `layout-finish` — login-time ranged placement rule; `melee_bar_height` pair key (MH+OH);
   `/st diag` BAR STATE line per hand; the F2 discovery (appearance migration could never
   run on a live profile).
4. `appearance-fix` — F2 fixed with `rawget`/`rawset` and a real `'**'`-AceDB fixture.
5. `ranged-forced` — the operator ordered the placement rule FORCED: the ranged row moves
   into the new layout even when the saved row was dragged or scaled (no drag-wins
   exception).
6. `widgets-guard` (may still be landing) — latent AceDB metatable trap in `widgets.lua`
   (a table could reach `PlaySoundFile` unguarded).

Operator rulings in force: the power-bar row under the melee stack is never given up; the
standalone distance bar (`weave_range.lua`) is a melee-range aid, independent of the swing
bars, and must stay uncoupled; offhand width always equals mainhand width; version stays
2.1.3.

## Your job — produce a publish-gate verdict, not a summary

Run and record every check below with the evidence (command, output tail, file:line). Where
you cannot verify something offline, say exactly what a client would have to show.

A. Gate: `bash tests/run.sh` (expect 54 steps / 0 failed) and luacheck counts. Rerun twice
   to catch order dependence.

B. Write-scope integrity: list every file modified today (mtimes) and map it to the lane
   that claims it. Flag anything modified outside a declared scope, any file edited by two
   lanes (bars_state.lua is known-shared: §12 by ranged-forced, §12e by appearance-fix —
   verify both sets of pins exist and neither was clobbered), and any lane whose reported
   "byte-identical" claims do not hold.

C. Silent-failure sweep (the reason this audit exists — `/st diag` once said "errors none"
   while a bar was wrong):
   1. Every plain table read of a possibly-missing AceDB key used for a decision or passed
      to an API (the `'**'` metatable trap). List all remaining instances.
   2. Every `pcall` and `st.guard.run` site that can swallow a failure; which ones can hide
      a permanently dead subsystem.
   3. Does `/st diag` now surface: dead engine, dead hand, hidden-but-expected bar, queue
      tint stuck, activity gate stuck closed, power bar orphaned? Name the gaps.
   4. Any place an error is caught and only printed once (so a recurring failure looks like
      one event).

D. Cross-client invariants: no bare client API outside `compat.lua`; family gates intact;
   all 7 TOCs list every module in load order; the base TOC advertises only classic-line
   interfaces; version 2.1.3 consistent in all 7 TOCs + `main.lua`; no leaked debug
   prints/`print(` in product files; no TODO/FIXME introduced.

E. New-wave regression hunt: geometry hopping or writes from OnUpdate; per-tick work added
   by the placement/pair-height rules; options that no longer do what they say (the
   offhand Height/Width story); any hand that can be permanently hidden by the activity
   gate (including the hunter cast bar owning the ranged bar frame — the known narrow gap);
   power-bar row behaviour when `power_bar_height` is customised; idempotence of every
   login-time rule (run each twice, assert no second write).

F. Release artefacts: `docs/` untouched; `bench/` reports present for every lane; the
   journal and hands-up rows match what landed. `CHANGELOG.md` and `README.md` are NOT yet
   updated — say what they must say, do not edit them.

G. In-client checklist: the exact steps the operator must run on TBC Anniversary AND Classic
   Era to close the release (bars, tints, placement after a drag, pair height, diag lines).

## Output

`bench/publish_audit_2026-10-28.md`, structured by A-G, every finding with severity
(BLOCKER / HIGH / MED / LOW / INFO), file:line evidence, and a final verdict line:
**READY TO PUBLISH PENDING IN-CLIENT TEST** or **NOT READY** with the blocking list.

Rules: run the lane skills first (`bench-read`, `desk-open` for `publish-audit`,
`desk-journal`, `signal-write` at the end). No git. No edits. Never claim in-client proof.
