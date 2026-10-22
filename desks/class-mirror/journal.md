# Class Mirror — Journal

## 2026-10-20 — Desk opened
- **Purpose:** the class-module "namespace mirror" defect class: a class file publishing
  its class table onto the addon namespace (`st.<CLASS> = ST.<CLASS>`), and the guards
  that keep it out of the tree.
- **Scope:** `classes/rogue.lua`, `classes/hunter.lua` (the two files that carried the
  mirror), `tests/wiring_check.lua` (the static + load-time guards), and the class
  suites whose pins moved (`tests/rogue_state.lua`).
- **Context:** the operator hit a live client crash on the TBC client
  (`LUA_WARNING: SwedgeTimer/SwedgeTimer_TBC.toc:77 Error loading SwedgeTimer/classes/rogue.lua`).
  The orchestrator's brief attributed it to the namespace mirror at the end of
  `classes/rogue.lua` (the HU-7 stopgap), and asked for the mirror to be removed and
  guarded so it cannot come back.
- **Next step:** work the brief (remove the mirrors, prove the engine still finds all
  six class modules, add the static guard and the client-load guard, prove the guard
  is not vacuous on a `/tmp/opencode` copy), then report the mechanism finding:
  the tree's OWN house idiom writes to the namespace at file scope in 326 places, so
  "the namespace is protected" is not the mechanism — see the bench report.

## 2026-10-20 — Mirrors removed, guards landed (brief complete)
- **Worked on:** removed the namespace mirror from `classes/rogue.lua` (was `:3698`) and
  `classes/hunter.lua` (was `:3320`), replacing each with the shaman-lane note; added
  **check 7** (static namespace write guard: 7a class modules must not write to the
  namespace at file scope, 7b no addon file may put a class table on the namespace at
  any scope) and **check 8** (class-module load guard in a namespace proxy that
  records every write, plus the engine-resolution pin over all six class keys) to
  `tests/wiring_check.lua`; moved the rogue suite's mirror pin in
  `tests/rogue_state.lua` to the shaman-suite shape (alias absent + the engine still
  finds the module).
- **Current state:** repo tree green — harness **43 steps, 0 failed**, luacheck
  **2 warnings / 0 errors** (floor held), `wiring_check` **772 checks, 0 failures**.
  Guard proven non-vacuous on `/tmp/opencode` copies: one re-added mirror → 4 failures
  (exit 1); three mirrors at once (shaman + hunter class files + a central one in
  `main.lua`) → 9 failures (exit 1). Full harness on the mutated copy: 43 steps,
  1 failed. Bench report: `bench/class_mirror_guard_2026-10-20.md`.
- **Dead ends worth knowing:** the brief's mechanism ("the namespace is protected") is
  **not supported by the evidence** — the tree's own idiom is 326 file-scope namespace
  writes in 30 root modules (all of which load on the operator's client) and Blizzard's
  own addons do the same in the reference client source. The mirror is the only
  namespace write in a *class* module, and every class file is in every TOC, so its
  file scope runs on every client — that differential is what the guards lock down.
  The crash cause itself is **UNCONFIRMED** offline.
- **Next step:** the operator re-tests in-client (the error text above the
  `LUA_WARNING` line would settle the cause). If the operator rules that the blanket
  "no file-scope namespace write in ANY addon file" rule is wanted, the 326 root-module
  bootstrap writes need a count-pinned accept list first (the count is printed on every
  run).

## 2026-10-20 — [signal:done] brief complete, artifacts on the bench
- Mirrors removed from `classes/rogue.lua` + `classes/hunter.lua`; check 7 (static
  namespace write guard) and check 8 (class-module load guard + engine resolution) in
  `tests/wiring_check.lua`; the rogue suite's mirror pin moved in
  `tests/rogue_state.lua`. Repo tree green (43/0, luacheck 2/0); the guard is proven
  non-vacuous on `/tmp/opencode` copies. Bench:
  `bench/class_mirror_guard_2026-10-20.md`. Signals:
  `.signals/2026-10-21T00-00-08Z-done.json`.

## 2026-10-20 — [signal:hands-up] the brief's stated cause is not supported by the evidence
- The brief's mechanism ("the addon namespace is protected, so a file-scope namespace
  write crashes the client") is contradicted by the tree's own 326 file-scope namespace
  writes in 30 root modules (all of which load on the operator's client) and by
  Blizzard's own addons in the reference client source. The crash cause stays
  **UNCONFIRMED** offline; the operator's ruling is wanted on (1) the blanket
  file-scope rule (it would fail the tree's own bootstrap writes) and (2) the client's
  own error text / an in-client re-test. Signal:
  `.signals/2026-10-21T00-00-30Z-hands-up.json`.
