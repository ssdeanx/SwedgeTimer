# Practice UI Fixes — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the shared practice-UI defects from the per-class scenario-100%
  audit (F2 CRITICAL, F4 HIGH, F5, F7, F9, F10, F11).
- **Scope:** `practice_ui.lua`, `option_tables.lua` (the `practice_mode_note` text
  only), `tests/practice_ui_state.lua`, `tests/options_load_state.lua` (the
  mode-note pins only). No class file, no guide file, no engine file, no TOC, no
  version, no docs, no git.
- **Next step:** read the audit findings, fix them one at a time, pin each one.

## 2026-10-20 — The audit report was NOT on disk; the brief was the spec
- **Worked on:** located the audit. The central ledger (`desks/journal.md`) still
  shows the `scenario-100-audit` lane as **queued**, and no desk holds a
  scenario-audit report. The findings below were therefore taken from the
  dispatch brief (each item carries file:line, trigger and impact) and each one
  was re-verified against the code before it was touched.
- **Current state:** all seven findings fixed and pinned; harness 41/0; luacheck
  2 warnings / 0 errors (the floor); 8/8 mutation proofs killed on disposable
  copies.
- **Next step:** the orchestrator validates; the class lanes re-read the drill
  ctx contract (the pick now rides `ctx.last_action` / `ctx.pick` /
  `ctx.pressed` / `ctx.action`, and the drill counters hang off `ctx.session` /
  `ctx.session_id` / `ctx.state`).

## 2026-10-20 — What changed, finding by finding

| Finding | Fix | Pin |
|---|---|---|
| **F2** CRITICAL — the drill-list panel cannot supply a pick | the drill-list row now carries the class's ACTIONS as the pick channel: the action press grades the selected drill with the pressed action; the drill press carries the pick in hand. The ctx rides every alias the class graders read (`last_action`, `pick`, `pressed`, `action`) | `24` — a grader with the real class graders' shape (reads `ctx.last_action`, nil without a pick) returns a letter; the old suite's stub graders hid the defect |
| **F4** HIGH — the shaman's and the druid's own sessions unreachable | `practice_class_list_wins()` checks the SHIPPED session (b) BEFORE the supersession (a): a class with a session of its own keeps it (its session grades through the class's own drill, so one skill, one truth). Any drill cast with NO session is now LOUD (print + count, `practice:cast`) | `24d` (the shaman keeps its own session), `24e` (the cast with no session prints and counts) |
| **F5** MEDIUM — the scenario row leaks frames | the row's buttons are REUSED from the row's own pool (keyed by group + key); the label and the icon update in place; a rebuild is a pass (begin / set / finish) and the pooled buttons no group claimed are hidden | `24c` — twenty scenario steps create no new frame |
| **F7** MEDIUM — no Retail gate | the rotation scenario is gated on a LIVE swing engine (`ST.swing_engine`): the inert stand-in refuses the session loudly ("not available on this client"), and the Practice page's availability note says the same | `24f` (the scenario refuses on the inert client) + the mode-note pins in `tests/options_load_state.lua` |
| **F9** LOW — the drill counters hang on the addon object | the drill press supplies the drill-list session's OWN `ctx.session` / `ctx.session_id` / `ctx.state`; the counters (the paladin's and the rogue's mis-pick window, the druid's priority window) die with the session | `24b` — a new session gets a new identity and a new window |
| **F10** LOW — the twist minigame must be the paladin's | the twist drill leads the PALADIN's drill list (its press starts the twist session - the flagship practice stays reachable); a class with no drills of its own and no twist drill is refused LOUDLY ("No practice for this class.") instead of inheriting the paladin minigame | `24g` (the paladin's list leads with the twist; the warrior is never offered it) + the warrior refusal pin in section 11 |
| **F11** LOW — the stale badge comment | the comment now states the truth: the badge ships ON (opt-out), `practice_panel_badge` defaults to true | source read (the comment) |

## 2026-10-20 — Two pins had to move (the ruling changed, not the code)
- The old 22h/22j pinned "the class's list wins" (the druid trains its own list
  instead of its own session). F4's ruling is the opposite: the class's session
  stays reachable and grades through the class's own drill. Both pins now say so
  (the druid keeps its own session; the drill list is the `drills` mode on top).
- The old "the warrior runs the shared twist session" pin encoded a routing the
  operator has since ruled against (no class may be offered another class's
  drill): the warrior without drills of its own is now refused loudly. The pool
  mechanics that test exercised were re-pinned against the twist session (the
  class that owns it) - the pool is session-level, so the mechanic is unchanged.

## 2026-10-20 — Dead end worth recording
- The Lua 5.1 limits bite in this file: the main chunk was already at the 200
  local limit and the closure upvalue limit (60). The first cut of the fix added
  12 file-scope locals and the module stopped loading ("main function has more
  than 200 local variables"). The helpers were inlined until the module loaded
  again - the row helpers, the drill-list helpers and the twist entry are all
  inlined on purpose. A future lane that adds a file-scope local to
  `practice_ui.lua` must count first.
