# paladin-forever-ids — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Land spec BS-5 from `bench/filed_closure_sweep_2026-10-19.md` §7 — the paladin's
  Forever id tables (Echo of Command / Echo of Righteousness / Holy Strike), the SoD
  strictSequence hard-wait render in the guide's HOLD/RIDE overlay, and the class-side
  counter for a failed `LCD.Register`.
- **Scope:** `classes/paladin.lua`, `nextaction.lua`, `nextaction_ui.lua`, `tests/paladin_state.lua`,
  the **paladin section only** of `tests/guide_contract.lua`. No other class's files, no
  `main.lua` / `diag.lua` / `compat.lua` / options / TOCs / versions / docs.
- **Next step:** Read the priors (benches: `filed_closure_sweep_2026-10-19.md` §7 BS-5,
  `ids_research_2026-10-19.md` §2), re-read the cited anchors, then build and pin.

## 2026-10-19 — BS-5 landed: Forever ids (name-anchored), the hard-wait pin, the LCD counter
- **Worked on:** Filled the two Forever Echo id tables (`1311703` Echo of Command, `1311704`
  Echo of Righteousness) and added Holy Strike `10333`, all WEB-CONFIRMED /
  CLIENT-UNCONFIRMED / name-resolved. The discipline is one helper,
  `confirmed_forever_id(ids, expected_name)`: the confirmed id whose OWN client-resolved
  name (the class's existing `resolve_spell_name` path) is the expected name — nil for a
  cold book and nil for a WRONG id, so a wrong id leaves `has_echo_command` /
  `has_echo_twist` / `holy_strike_known` unknown and the archived seal input stands
  (never a wrong prompt). The aura match is name-primary: name + proven id, never the raw
  id. `sor_forever_ids` stays deliberately empty (no source names an id for Forever's
  *Seal of Righteousness*) and its comment now says so. Holy Strike is published as a
  plug-in point (`self.holy_strike_known` → `inputs.holy_strike_known`); the engine does
  not read it (the ten guide slots are frozen), and `nextaction.lua:127-135` states that.
  Added the BS-8 class-side counter `ST.PALADIN.lcd_register_errors` (one increment on the
  failed `pcall(LCD.Register, …)` path; the diag reader is main.lua's, the engine lane's).
- **Also learned:** the SoD hard-wait render was ALREADY in the tree
  (`nextaction_ui.lua:596-603` paints WAIT; the provider feeds `out.hard_wait` at
  `classes/paladin.lua:3597`) — so `nextaction_ui.lua` needed no change. I tried one
  defensive edit (adding `or out.hard_wait == true` to the overlay's light condition) and
  **reverted it**: the engine only publishes the wait with a hold, so the term is dead code
  and no pin could kill it. The file is byte-identical to its pre-lane state. What the
  lane owed that file is the pin, which landed in the paladin section of
  `tests/guide_contract.lua` (WAIT lights the overlay; ten slots stay).
- **Current state:** offline-verified. Harness **41 steps / 0 failed**; luacheck **2
  warnings / 0 errors** (the standing floor, both pre-existing and in other lanes' files);
  `paladin_state` 663 PASS (was 643), `guide_contract` 1040 PASS (was 1035). CRLF kept in
  the two addon files, LF in the two test files. **7/7 mutations killed** on
  `/tmp/opencode/bs5-mut` (script `/tmp/opencode/bs5_mutations.py`): the id-only latch,
  the name-less confirmation, the removed Holy Strike id, the dropped counter increment,
  the removed WAIT branch, the unfed `out.hard_wait`, the unconditional "down" latch.
  Report: `bench/buildout_paladin_bs5_2026-10-19.md`.
- **Next step:** the orchestrator validates. Owed elsewhere: the runtime-diag line that
  reads `st.PALADIN.lcd_register_errors` (engine lane, `main.lua`); a Holy Strike guide
  slot + rule after a slot-budget ruling; the operator's 1.60.x `GetSpellInfo` for the
  three ids (and their localized names on a non-English client — the anchors are compared
  verbatim, so a localized client stays unknown/inert until they are added).

## 2026-10-19 — [signal:done] BS-5 landed
- Harness 41/0, luacheck floor 2/0 held, `paladin_state` 663 PASS, `guide_contract` 1040
  PASS, 7/7 mutations killed. Signal:
  `desks/paladin-forever-ids/.signals/2026-10-19T230500Z.json`. Report:
  `bench/buildout_paladin_bs5_2026-10-19.md`.
