# Brief: swing-wire-proctor2 — independent verdict on harness + D8 rewire

Date: 2026-10-22. Verifies the fix lane
(`bench/briefs/brief_swing-wire-fix_2026-10-22.md`,
`desks/swing-wire-fix/journal.md`) against the repo, independently.
You do not implement, you do not edit. Your verdict (PASS / NEEDS FIXES)
is what lets the operator approve — nothing is complete on the builder's
claim, per operator rule.

## Seat + mode

- Seat: `proctor`. READ-ONLY: no code edits, no file writes, no test runs
  (no shell on this seat — unexecutable items go UNVERIFIED with the exact
  closer, never "fine").
- Skills first: `skills_list`, then `skill_view` (`bench-read`,
  `desk-open`, `desk-journal`, `signal-write`). Then journals before
  artifacts: `desks/journal.md`, your desk journal,
  `desks/swing-wire-fix/journal.md`, `desks/swing-wire-hunt2/journal.md`
  (D8 + harness spec §3), `bench/lessons.md`. Missing skill → state which,
  proceed per `workshop.md` / `CAIRN.md` / `AGENTS.md`.
- `/home/sam/wow-ui-source`: `read`/`grep` blocked — `ast_grep_search`
  (`lang: "lua"`, checked-out `classic_era` only, branch every claim);
  if absent, say so, use `search_files` in-repo, mark branch claims
  UNVERIFIED.

## What changed (verify each; all exist on disk 2026-10-22)

NEW `tests/real_wire_state.lua` (~700 lines, 112 checks):
- Assembly must be REAL + unmodified: per-sandbox LibStub, shipped v7,
  real vendored lib, real `main.lua` path. Confirm NO fixture answers in
  the lib's shape (lesson 11) — every scripted API/sandbox seam listed
  and justified; the xpcall-forwarding shim + `geterrorhandler` recorder
  must cite the in-tree proof (Ace* ships `xpcall(func, err, ...)`).
- Legs: ADDON_LOADED asserts lib units; PEW asserts app-observed
  INFO_INITIALIZED + `stl_ready`; six regs land IN THE LIB's v7 registry
  object (identity, not a counter); CLEU `SWING_DAMAGE` → mh advances;
  `SUCCEEDED(75)` + autorepeat → ranged (Era + Anniversary(1) profiles);
  D8 negative leg (deadline-first → late INFO → STL identity is the lib +
  bars advance); Anniversary-`nil` leg encoded expected-fail-pending-HU-29
  (confirm it is a marked todo/skip, not green, not deleted).
- Trace each claimed kill: rewire-detached → 14 D8 failures (must match
  the recorded pre-fix red exactly); strip-neutered → 16 happy-leg fails.
  Confirm the red→green counts (pre 109 checks/14 fails → post 112/0 + 1
  expected-fail) are structurally entailed by the suite, not just quoted.

`main.lua` three narrow regions (CRLF, +50/-2 area):
- Stash upvalues `REAL_STL` / `REAL_SWING_ENGINE` after engine selection
  (~`:45-50`). Confirm placement is AFTER the three-way pick and BEFORE
  any use, and no other code path reassigns them.
- INFO callback rewire (~`:389-420`): `init_deadline_fired and STL ~=
  REAL_STL` → re-point STL, restore `SWING_ENGINE_AVAILABLE` +
  `swing_engine`, re-register, `check_weapons`, re-seed hands WITHOUT
  frame re-creation. Confirm: the re-seed matches `init_timers` semantics
  for state fields (and say if any field diverges); the rewire is
  chat-quiet truthfully (engine line + `deadline=fired` diag carry the
  truth — confirm both read rewired, not still-unavailable); a second
  late INFO cannot double-fire the rewire.
- Double-reg guard in `register_timer_callbacks` (~`:809-815`):
  `swing_timer_registered_on == STL` → return. Confirm the guard key
  cannot collide across engines and the first (happy-path) registration
  is unaffected.
- Confirm the only `main.lua` changes are these regions; confirm the
  `toc_check` 200-local guard still passes for the file (2 new
  file-scope locals).

Scope + standing (fail on violation): only `tests/real_wire_state.lua`
(NEW) + the three `main.lua` regions changed. Any `Libs/` touch,
TOC/`bars.lua`/`compat.lua`/`classes/`/`swing_source.lua`/`diag.lua`
edit = NEEDS FIXES. (`tests/run.sh` line added by orchestrator —
expected, not a violation.) Endings preserved; no new toggle; no
default-visible change on the happy path.

## Deliverable (reply text; orchestrator files it)

- Verdict: PASS or NEEDS FIXES, one line, with the reason.
- Findings F1..Fn (or "none"): file:line, severity, exact fix.
- UNVERIFIED list (harness re-run, luacheck, mutation execution —
  orchestrator closes with its own run).
- Explicit non-findings. In-client proof is out of scope for this
  verdict (operator done for the day) — say so once, do not hedge the
  verdict on it.
