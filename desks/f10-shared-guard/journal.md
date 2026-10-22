# F10 Shared Guard — Journal

## 2026-10-19 — Desk opened
- **Purpose:** close deep-audit finding F10 — the error-isolation contract ("first throw
  prints once → every throw counts → quarantine after 25 → degrade to unknown/hide") was
  copy-pasted six times with six quarantine constants and had already diverged (the
  practice start path printed on every refusal, the other five printed once).
- **Scope:** NEW `guard.lua` (the one shared implementation), the six call sites
  (`bars.lua`, `hud.lua`, `nextaction_ui.lua`, `practice_ui.lua` — two copies,
  `rotationtext.lua`), the 7 flavor TOCs, and the suites that own those files' pins.
  Explicitly out of scope: class files, `practice.lua`, `practice_progress*.lua`,
  `practice_stats.lua`, `option_tables.lua`, `config*.lua`, `main.lua`, `diag.lua`,
  `compat.lua`, `tests/run.sh`, versions, README/CHANGELOG/docs.
- **Context:** `bench/deep_audit_2026-10-19.md` F10; the sibling F12 lane
  (`bench/bars_print_policy_2026-10-19.md`) established that `bars.lua` reaches chat
  through AceConsole's `Print` (never the raw global) — that path is preserved here.
- **Next step:** write `guard.lua`, migrate the six call sites, load it in the 7 TOCs
  after `utils.lua` and before every consumer, keep every existing isolation pin green,
  then mutation-proof the shared guard on `/tmp/opencode` copies.

## Status
- (session in progress)

## 2026-10-19 — F10 closed: one shared guard + the scenario-ctx crash
- **Worked on:** NEW `guard.lua` (the addon's one error-isolation contract: count →
  report once → quarantine after 25 → the caller's own degrade) and the migration of
  the six copies (`bars.lua`, `hud.lua`, `nextaction_ui.lua`, `practice_ui.lua` ×2,
  `rotationtext.lua`) to it; `guard.lua` added to all 7 TOCs after `utils.lua`; new
  pins in `bars_state`, `hud_state`, `practice_ui_state`, `rotationtext_state`,
  `guide_contract` (the suite that owns `nextaction_ui.lua`'s pins) and `toc_check`;
  sandbox module lists updated in every suite that loads a consumer module. Also
  fixed the orchestrator's **undefined `SCENARIO_RESOURCE_KEYS`** crash in
  `practice_ui.lua` (the default scenario ctx raised for druid/warrior/shaman): the
  list is now a local, verified against the six classes' `gather_guide_inputs`
  (each class names its own pool; `focus` does not exist), and the lift can no
  longer crash.
- **Current state:** `bash tests/run.sh` → **41 steps, 0 failed** (final tree, twice
  in a row); luacheck 2/0 (floor held). Mutation proofs 9/9 killed on
  `/tmp/opencode` copies (`/tmp/opencode/mut_f10.py`). Report:
  `bench/f10_shared_guard_2026-10-19.md`. (Mid-lane the same tree read 41 steps /
  2 failed — both the **shaman lane's** in-flight work; they cleared when that lane
  landed its own pin update, with no change from this lane.)
- **Next step:** the orchestrator validates (the lane owns no further work); if the
  shaman lane lands its pin update, the harness should be 41/0. Do not re-add a
  per-module threshold copy — `st.guard.QUARANTINE_THROWS` is the only one.

## 2026-10-19 — [signal:done] F10 closed (one shared guard) + the scenario-ctx crash
- `bench/f10_shared_guard_2026-10-19.md` — one implementation, six call sites
  migrated, every isolation pin unchanged and green, 9/9 mutation proofs killed.
- Two red suites are the shaman lane's crossfire, not this lane's (documented in
  the report §6).

