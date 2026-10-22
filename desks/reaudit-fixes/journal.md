# reaudit-fixes — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the final re-audit's three MEDIUM findings and two easy LOWs:
  M-1 (the logout flush discards its error), M-2 (the druid guesses an action key
  for an unknown hold text), M-3 (the session-completion bonus sits outside the
  daily anti-grind cap), L-1 (the panel's OnHide flush can end a live run),
  L-5 (the M4 cap notice cannot fire again after a mid-session reset).
- **Scope:** `main.lua`, `classes/druid.lua`, `practice_progress.lua`,
  `practice_ui.lua` and the suites that own their pins
  (`tests/main_init_state.lua`, `tests/druid_state.lua`, `tests/practice_state.lua`,
  `tests/practice_ui_state.lua`). NOT in scope: `compat.lua`, `classes/rogue.lua`,
  the other class files, `option_tables.lua`, `config_presets.lua`,
  `practice_progress_ui.lua`, `bars.lua`, `hud.lua`, `run.sh`, the TOCs, the
  versions, the docs. No git, no lint-config change.
- **Source of truth:** the dispatch brief's findings (M-1/M-2/M-3/L-1/L-5, each with
  file:line, mechanism and required fix), the house error contract in `guard.lua`,
  `bench/practice_persist_2026-10-20.md` (the H2/M1/M4 fix wave this lane re-audits),
  `bench/lessons.md`.
- **Gap (named, not papered over):** the re-audit's own report file is NOT on disk —
  no desk or bench file carries the M-1/M-2/M-3/L-1/L-5 text. The findings used here
  are the ones the dispatch brief carries (file:line + mechanism + required fix); every
  one of them was re-verified against the live source before the edit. The re-audit's
  report id/path is owed by the orchestrator if it is to be filed.
- **Next step:** M-1 (main.lua's logout flush through the house contract), then M-2
  (the druid's unknown hold text), then M-3 (the bonus against the cap), then L-1 and
  L-5 in `practice_ui.lua`; pins + mutation proofs on `/tmp/opencode` copies after
  each step.

## 2026-10-20 — all five findings closed, pinned and mutation-proofed
- **Worked on:** the five findings, one at a time, each re-verified against the live
  source before the edit.
  - **M1** — `main.lua`'s `PLAYER_LOGOUT` flush ran under a bare `pcall` and threw
    the error away. It now runs under the house contract,
    `st.guard.run(self, "practice:logout", pui.flush_progress_session, self)`: the
    failure is counted in `bar_hook_errors.by_site["practice:logout"]`, the first one
    is announced once, and `/st diag`'s `bar_hook_errors=` line shows the count.
    `guard.lua` loads before `main.lua` in all seven TOC variants, and the test
    sandbox now mirrors that order (it loads the REAL `guard.lua`), so the pin runs
    against the real contract.
  - **M2** — the druid's slug fallback for an unknown hold text is gone: the
    unknown case is `return nil, nil`, so the step is UNKNOWN (no attempt, no wrong
    action) and the priority drill banks no mis-pick. The closed-vocabulary pin
    (`tests/druid_guide_state.lua`) stays the tripwire, unchanged.
  - **M3** — the completion bonus is no longer a flat +25 for ten ATTEMPTS: it is a
    SHARE (0.5) of what the session actually EARNED through the capped attempt
    path, clamped to the flat +25, and paid ONCE per session (the paid amount is
    remembered on the session). Ten misses now earn no bonus and the day's total
    stays inside `cap x (1 + share)` — the cap still bounds the total. The brief's
    first option ("charge the bonus against the drill's cap") was rejected on
    evidence: it zeroes the bonus on exactly the session the bonus exists for and
    breaks three existing pins (see the bench file).
  - **L1** — the panel's `OnHide` no longer ends a live run: the flush applies only
    when the run is over, and a live run keeps (or re-opens) its progression
    session, so the score and the recording cannot diverge.
  - **L5** — the M4 cap notice is cleared with the mid-session reset, so it can
    fire again.
- **Current state:** harness **41 steps / 0 failed**; luacheck **2 warnings / 0
  errors in 83 files** (the floor — neither warning is in a touched line). The
  owned suites: `tests/main_init_state.lua` 903, `tests/druid_state.lua` 1298,
  `tests/practice_ui_state.lua` 1455, `tests/practice_progress_state.lua` 445 —
  all green. **6 / 6 mutants killed**
  (`/tmp/opencode/reaudit_mutations.py`, disposable copies under
  `/tmp/opencode/reaudit_mut/base`): the "flush error discarded" mutant, the
  "guessed hold key" mutant, the "bonus ignores the cap" mutant (both from the pure
  suite and from the UI side), the "hide ends a live run" mutant and the "cap
  notice never cleared" mutant.
- **Evidence:** `bench/reaudit_fixes_2026-10-20.md` (the findings, the mechanism,
  the pins, the mutation table, the house-rule checklist and the gaps).
- **Scope deviation (one, named):** the M-3 pins live in
  `tests/practice_progress_state.lua` — the suite that OWNS `practice_progress.lua`'s
  pins. The dispatch's scope list named `tests/practice_state.lua` (the suite for
  `practice.lua`, the simulation engine, which has no bonus pins at all), so the
  enumerated list appears to abbreviate. The change there is ADDITIVE: no existing
  pin in that suite was edited, and every one of its pins still holds.
- **Known consequences (documented, not hidden):** a session of misses now earns no
  completion bonus (that is the finding), and a session that earns less than 50 XP
  earns a proportional bonus instead of the flat +25. `SESSION_BONUS_XP_SHARE = 0.5`
  is a balance value, not a truth; the pins state the rule, and a different balance
  is a one-constant change.
- **Gaps:** the re-audit's own report file is NOT on disk (the findings used here
  are the dispatch brief's, each re-verified against the source — raised as HU-16,
  see below); everything here is verified OFFLINE — the logout announcement and the
  `/st diag` line still want an in-client look; `/st diag` shows the COUNT, not the
  per-site breakdown (adding a per-site reader would change the diag line's shape —
  out of scope).
- **Next step:** the orchestrator validates (in-client: the logout announcement and
  the diag line; and the re-audit's report text, if it is to be filed, checked
  against this lane's five findings).

## 2026-10-20 — [signal:done] M-1 / M-2 / M-3 / L-1 / L-5 closed and pinned
- Signal file: `desks/reaudit-fixes/.signals/2026-10-20T12-05-00Z.json`.
- Artifact: `bench/reaudit_fixes_2026-10-20.md` (the findings, the mechanism, the
  pins, the six mutation proofs, the house-rule checklist, the scope deviation and
  the gaps).

## 2026-10-20 — [signal:hands-up] the re-audit's report file is not on disk
- Signal file: `desks/reaudit-fixes/.signals/2026-10-20T12-20-00Z-hands-up.json`.
- Escalation row: **HU-16** in `hands-up.md`.
- The question for the operator: the brief cites a re-audit report under `desks/`
  that does not exist on disk. The lane worked from the brief and re-verified every
  finding against the source, so the five named findings ARE closed - but if the
  report carries more (the sibling publish-gate re-audit recorded seven LOWs, and
  only two of the practice-persistence LOWs were named here), the rest is
  UNADDRESSED. The report should be filed on the bench so the trail has it.
- This does not block the lane: harness 41/0, luacheck floor held, 6/6 mutants
  killed.
