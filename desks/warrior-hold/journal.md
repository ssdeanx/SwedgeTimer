# Warrior Hold — Journal

## 2026-10-20 — Desk opened
- **Purpose:** the warrior's half of the HU-8 class ruling — the warrior guide has
  three real holds ("CANCEL" / "RIDE" / "HOLD", `warrior_guide.lua:1286` / `:1303`
  / `:1346` / `:1399`) and the class's scenario step must state them, so the shared
  engine can tell a hold (a decision) from an unknown (cannot decide). Plus the
  operator's ruling on the one new HUD mirror: `hud_show_sunder` ships OFF.
- **Scope:** `classes/warrior.lua`, `config_presets.lua` (the sunder default only),
  `tests/warrior_state.lua`, `tests/warrior_guide_state.lua`,
  `tests/options_load_state.lua` (the sunder-default pin only),
  `tests/hud_state.lua` (the sunder-default pin only). Nothing else.
- **Priors read:** `bench/class_hold_statements_2026-10-20.md` (the other four
  classes' shape; §6 files the warrior's semantics), `bench/lessons.md`,
  `desks/journal.md`, `hands-up.md` (HU-8 ruling), the `class-hold-statements`
  desk journal, the `warrior-hs-queue` desk journal (the sibling lane that filed
  the sunder default question).
- **Engine contract (read from the landed code, `practice.lua:3450`):**
  `{ action = "<key>", reason = "<text>" }` | `{ action = nil, hold = true,
  reason = "<text>" }` | nil. An action wins over the hold flag; a step with
  neither stays unknown.
- **Next step:** implement the step, flip the sunder default, re-cut the stale
  "a HOLD verdict answers nil" pin, pin the three states through the engine.

## 2026-10-20 — The warrior states its hold; the sunder mirror defaults off
- **Worked on:** (1) `ST.WARRIOR.practice_scenario_step` (`classes/warrior.lua:3926`)
  now asks the guide's own verdict: an action stays an action, a verdict that
  holds (RIDE / HOLD) becomes `{ action = nil, hold = true, reason = out.hold_text }`,
  and a state the guide cannot read stays unknown. (2) `config_presets.lua:1303`:
  `hud_show_sunder` flipped `true` → `false` (the mirror ships, the fresh-profile
  HUD row does not change; the provider already hides it unless the key reads
  exactly true). The stale comment above the key was rewritten (it claimed the
  HUD master is off and that the TBC mirror had not landed — both stale).
- **The one judgement call (documented, not hidden):** the guide's third hold
  verdict, **CANCEL** (`warrior_guide.lua:1286`), NAMES an action
  (`action = "execute"`, `hold = true`, `hold_text = "CANCEL"`). The brief's own
  rule — "a step that names an action stays an action" — plus the class's own
  invariant ("the practice pick and the live pick can never disagree",
  `classes/warrior.lua:3831-3832`) decide it: the CANCEL state stays an action.
  A CANCEL hold would teach the opposite of the live guide (which lights the
  Execute icon) and would grade the correct press as an illegal cast. The cue is
  a live-gather reading (`classes/warrior.lua:2929`) the practice path never
  feeds, so the practice path never produces that verdict; no input was added
  for it (it would be unpinnable — the step's answer is the same either way).
  If the operator rules otherwise it is one line, and it needs their word.
- **Pins:** the stale "a HOLD verdict answers nil" pin was RE-CUT (not deleted) at
  `tests/warrior_state.lua:4329`; the new section 37 (`:4632`) pins the RIDE and
  the HOLD statements (the guide's own caption), the unknown, and the three
  states through the engine (illegal cast / no attempt / no attempt). The
  sunder-default pins were re-cut in `tests/hud_state.lua:1215`,
  `tests/options_load_state.lua:608` and `tests/hud_templates_state.lua:81`.
- **One file outside the enumerated scope:** `tests/hud_templates_state.lua` — the
  brief named two sunder-default pin files, the harness proved a third (its §2
  pins "hud_show_<key> ships true" for every slot). Re-cut mechanically with the
  suite's own `ship_false` mechanism (the druid Claw shape). Flagged in the bench
  artifact §6.
- **Current state:** harness **41 steps, 0 failed**; luacheck **2 warnings / 0
  errors** (the floor: `compat.lua:36`, `main.lua:81` — this lane adds none).
  **10 of 10 mutation proofs killed** on `/tmp/opencode/warrior-hold-mut`
  (script `/tmp/opencode/warrior_hold_mutations.py`). Line endings preserved
  (`classes/warrior.lua` CRLF, the rest LF); no trailing whitespace in any of the
  six touched files. Artifact: `bench/warrior_hold_statements_2026-10-20.md`.
- **Not verified in-client** (offline proofs only): the practice panel's hold
  prompt and the TBC HUD row without the Sunder icon need a client.
- **Next step:** the orchestrator validates. If the operator rules that CANCEL
  must be a hold statement, the change is one line in
  `classes/warrior.lua:3926` (and the §37 pin grows a CANCEL case).

## 2026-10-20 — [signal:done] the warrior states its hold; the sunder mirror defaults off
- The warrior's three guide hold verdicts are handled by the guide's own verdict:
  RIDE and HOLD state an explicit hold (the guide's own caption), CANCEL names the
  Execute and therefore stays an action (the brief's rule + the class's own
  invariant). `hud_show_sunder` ships false; the mirror is one click away and a
  fresh profile's HUD row is unchanged.
- Harness 41/0, luacheck 2/0 (the floor), 10/10 mutation proofs killed.
- One file outside the enumerated scope (`tests/hud_templates_state.lua` — a third
  sunder-default pin, proved by the harness) — flagged in the bench artifact §6.
- Artifact: `bench/warrior_hold_statements_2026-10-20.md`.
- Signal file: `.signals/2026-10-20T04-48-14Z.json`.
