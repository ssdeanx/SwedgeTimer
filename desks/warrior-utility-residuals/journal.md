# Warrior Utility Residuals — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the three residuals the utility-live lane filed for the warrior
  (bench/warrior_apl_utility_live_2026-10-20.md §7 and the filed residuals):
  the `gladiator_stance` row with no honest arm, the missing `practice_rotation_for`
  accessor, and the APL's target-count / Bloodlust-alignment / execute-phase gates.
- **Scope:** `classes/warrior.lua`, `warrior_guide.lua`, `tests/warrior_state.lua`,
  `tests/warrior_guide_state.lua` only. No git, no lint-config, no options/UI files.
- **Context:** the utility-live lane made the thirteen APL utility rows live and gave
  twelve of them an engine arm; the residuals are what it could not close.
- **Next step:** read the filed residuals, decide each one (close it or file it with a
  sharper reason), implement, pin with tests, prove with mutations on /tmp/opencode.

## 2026-10-20 — Residuals closed (1 closed, 1 closed, 1 partly closed + filed)
- **Worked on:** (1) `gladiator_stance` — the filed reason was WRONG on the facts: the
  SoD APL's gate is `auraIsKnown(457817 / 464241)`, and in the sim `auraIsKnown` is a
  REGISTERED-aura check, so the gate is the SoD T1 damage SET bonus (an equipment
  fact), not a rune. The row keeps `engine = false`; the `needs` now names the exact
  missing read (the six item ids of "S03 - Item - T1 - Warrior - Damage", buildable
  from the existing `api.is_item_equipped`) and the half that IS client-readable
  (the Forecast buff's remaining time through the HELPFUL aura walk).
  (2) The rotation slice the panel publishes — `practice_rotation_for` +
  `practice_rotation_family` (the hunter's shape). The gate is the class's own
  resolved guide slot set (the engine's askable vocabulary per family and spec)
  plus `engine ~= false` / `live ~= false`; the compiled-order rows gained labels.
  (3) The three APL gates: the EXECUTE-PHASE gate is now WIRED (the read exists -
  the class's own target health; the APL's NOT-E20 clause on the Heroic Strike dump
  on TBC / Forever, provider-armed, the Era APL allows the dump); the TARGET-COUNT
  and BLOODLUST-ALIGNMENT gates are FILED with the exact read each needs.
- **Current state:** the warrior's suites are green (1822 + 2040 checks), the lane's
  four files are luacheck-clean, and 18/18 mutants die on the expected pins
  (/tmp/opencode/mut_warrior_residuals.py). The bench file is
  `bench/warrior_utility_residuals_2026-10-20.md`.
- **Next step:** the orchestrator validates. Six items are filed for the operator:
  the Gladiator set ids, an enemy-count sensor, a Bloodlust-plan option, the WotLK
  Bloodrage ceiling (20, not 90) + its stance condition, the SoD Bloodrage order
  gap, and the Forever stance dance. The execute-phase wire is a visible behaviour
  change on TBC / Forever and wants an in-client look.
- **Note:** the full harness showed the ROGUE lane's files RED while this lane ran
  (classes/rogue.lua mid-edit with a syntax error, tests/rogue_state.lua,
  tests/rogue_guide_state.lua, tests/options_load_state.lua) — the rogue lane is
  editing them in parallel; their timestamps land after this lane's last edit. The
  last run was 41 steps / 1 failed, the single red being the rogue options pins.
  Every other step, both warrior suites included, is green; the luacheck floor is
  2 warnings / 0 errors. Not this lane's files; not fixed here.
