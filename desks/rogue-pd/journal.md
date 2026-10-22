# Rogue PD — Journal

## 2026-10-19 — Desk opened
- **Purpose:** rogue practice + designer, full class scope (lane rogue-pd, session ses_eaa01e200ffePpgnl1ZZIRsX9u).
- **Scope:** `classes/rogue.lua`, `rogue_guide.lua`, `tests/rogue_state.lua` (+ `tests/rogue_guide_state.lua`, glob-verified present) fully owned. Shared files (`option_tables.lua`, `practice_ui.lua`, `practice.lua`, `designmode.lua`) READ fully; edit ONLY rogue-keyed regions. No other classes' lines; verify with read-only `git diff`.
- **Next step:** implement rogue practice seam (mirror druid) + rogue options Practice toggle + rogue-keyed practice_ui branches; verify designer coverage for all rogue elements; pin in rogue_state; harness green + luacheck floor; mutation proofs on /tmp/opencode copies.

## 2026-10-19 — Practice + designer shipped for rogue [signal:done]
- **Worked on:** practice seam + drill shell + options entry + designer pins, all in
  scope (`classes/rogue.lua`, `rogue_guide.lua` untouched, `tests/rogue_state.lua`,
  `tests/rogue_guide_state.lua` glob-verified present; shared files edited ONLY in
  rogue-keyed regions — insertions + 4 rogue-gated condition extensions).
- **Current state:** rogue_state 678/0 (+226); practice/practice_ui/guide suites green;
  wiring zero rogue flags; luacheck clean on my files, tree at 2/0 floor. Full harness
  38/3 with all 3 failures proven sibling-lane crossfire (shaman SODOPT, pips registry
  count, druid/hunter dead hooks). Mutations M1-M8 kill on /tmp/opencode copies.
  Archive diff (TBC vs Forever, 10 files IDENTICAL) reconciled per-pattern in
  bench/buildout_rogue-pd_2026-10-19.md. Client citations (Era/TBC/Forever) filed there.
- **Dead ends fixed mid-lane:** M2 first cut broke syntax (miscounted `end`) — redone,
  kills 6; M3 pin text never matched (pin written but untested) — added live coverage,
  kills 2; predicate called the hunter-named getter (`get_practice_scenario_key`) —
  live-drive pins caught it, renamed to the seam's `practice_scenario_key`.
- **Next step:** orchestrator validation + reconcile (sibling seams vs wiring checker,
  shared Practice page per-class entries). Owed in-client: drill feel on Era/TBC/
  Forever (icons, grading, panel drag), SS window art on Era.
