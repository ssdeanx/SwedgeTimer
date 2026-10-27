# spell-resolution — Journal

## 2026-10-25 — Desk opened
- **Purpose:** make every spell STATE QUERY use the token its client family actually
  takes (`id` vs localized `name`), additively, without touching a single spell id.
- **Scope:** `compat.lua` (`api.get_spell_query`, the existence/rank walk) and the six
  class token helpers in `classes/{paladin,warrior,rogue,hunter,shaman,druid}.lua`,
  plus the offline suites that pin them.
- **Binding ruling (verbatim):** "titanforge aka wotlk doesnt use spell ids either.
  stop guessing. each has their own client." / "tbc is classic_anniversary and doesnt
  take spell ids it needs spell names." / "if u remove shit u will have to research the
  spell ids again."
- **Matrix:** ERA (1.15.9, SoD included) -> ids; TBC (2.5.6) -> names; WRATH/Titanforge
  (3.80.2) -> names; FOREVER/CATA/MISTS/RETAIL -> ids unchanged. No combined branch.
- **Absolute:** no id added/removed/replaced; every id table byte-identical
  (`steady_id_by_family`, hunter rank tables, rogue name/id tables, shot guard included).

## 2026-10-25 — Session: state-query token matrix landed

### What was done
- `compat.lua:1665` `api.get_spell_query` — explicit per-family branches (TBC name,
  WRATH name, else id); a nil name on a name family returns nil, never the id.
- `compat.lua:1570` `family_spell_exists` — name path on TBC and WRATH, and the
  `or id` fallback + its second id re-probe removed. "Absent" therefore stays an
  Era-only verdict; a name-family miss is `unresolved` (retryable at the callers'
  existing throttles). Documented in the bench report, not hidden.
- `classes/paladin.lua:186`, `classes/warrior.lua:207` `spell_query` — name families
  resolve the name, no id fallback; an already-resolved string token passes through.
- `classes/rogue.lua:239` `rogue_query` — name on TBC/WRATH; `resolve_named_spell`
  (:219) accepts a name-family entry with no id (name alone is enough there).
- `classes/hunter.lua:27` `spell_token` — id on ERA/FOREVER, name on TBC/WRATH, nil on a
  cold cache; `queue_tokens` (:46) same gate (one family name per rank table).
- `classes/shaman.lua:153` `spell_query` and `:528` `resolve_family_spell` — name on
  TBC/WRATH (the weave catalogue's known-rank read included).
- `classes/druid.lua:89` `spell_query` and `:361` the queued-Maul probe — name on
  TBC/WRATH.
- Every `get_spell_query(...) or id` caller fixed; no such fallback remains outside tests
  (pinned statically by the new suite).
- New suite `tests/spell_query_family_state.lua` (56/0): per-family helper pins, the
  no-id-re-probe walk pins, hunter `spell_token`/`queue_tokens` per family + cold cache,
  and exact source pins that each class helper gates WRATH separately.
- Existing suites re-cut only where the contract really changed: smoke,
  hunter_state, hunter_guide_state, shaman_state, shaman_guide_state, druid_state,
  druid_guide_state, paladin_state, warrior_state, rogue_state, secret_guard_state.
  Every re-cut is listed in `bench/spell_resolution_2026-10-25.md` §"pins re-cut".
- Mutations: 10 one-line mutations on `/tmp/opencode/mut<N>` copies (deleted after each),
  including the separate-gate proof (WRATH-only vs TBC-only), the nil-name fallback, the
  hunter/rogue/druid/shaman class gates, and the static fallback pin.
- Bench artifact: `bench/spell_resolution_2026-10-25.md` (new file, not an overwrite).

## 2026-10-25 — [signal:done] family-correct state-query tokens landed
- Signal: `desks/spell-resolution/.signals/20261025T235409Z.json`.
- Focused suites green (new 56/0 plus 12 existing suites); 10 mutation proofs; no id
  table touched. Owed by the orchestrator: the `run.sh` line for the new suite.

### Current state
- Focused suites green, no `tests/run.sh` run (orchestrator owns it):
  new 56/0; smoke 232/0; spell_known 251/0; hunter 1831/0; hunter_guide 1976/0;
  shaman 1083/0; shaman_guide 1570/0; druid 1621/0; druid_guide 95944/0;
  paladin 1270/0; warrior 2085/0; rogue 1137/0; secret_guard 433/0.
- `luac5.1 -p` clean; luacheck on the changed files 0 errors / 1 pre-existing warning
  (`compat.lua:36 addon_name`, untouched line). Line endings preserved per file.
- No id table touched; no git command run.

### Next step
- Orchestrator: add `tests/spell_query_family_state.lua` to `tests/run.sh`, reconcile
  this lane, and list the changed files for the operator's client copy.
- Operator in-client check on Titanforge 3.80.2: state reads by NAME (guides, HUD
  cooldowns, queue colours) and so the final word on the WRATH branch. Also still open
  from the standing correction: `steady_id_by_family.ERA = 56641` (Era range token) is
  untouched and needs a fresh id research before any change.
- Reviewed, deliberately unchanged: `hud.lua:786` `hud_known_query` (Titanforge's
  IsSpellKnown is the id-only `C_SpellBook.IsSpellInSpellBook`), the
  `practice_common_action` ladders (icon-only tokens), druid `resolve_guide_icons`
  (icon descriptors), and the aura id matchers (classic_titan's aura payload carries
  `spellId` - verified in `origin/classic_titan` AuraUtil.lua).

## 2026-10-25 — [signal:done] family-correct state-query tokens landed
- Signal: `desks/spell-resolution/.signals/20261025T235409Z.json`.
- Focused suites green (new 56/0 plus 12 existing suites); 10 mutation proofs; no id
  table touched. Owed by the orchestrator: the `run.sh` line for the new suite.

## 2026-10-26 — CORRECTION session: id fallback restored (operator fact)

### What was done
- Operator fact (binding): **"i never banned fallback to ids. someone made that up."**
  The cancelled session's no-fallback design was wrong. Restored the id fallback and
  kept the WRATH/Titanforge extension:
  - `compat.api.get_spell_query`: `TBC -> name or id`, `WRATH -> name or id`, else id.
  - `compat.family_spell_exists`: HEAD's version ported (name path, then the bare-id
    re-probe) with the gate widened to TBC **or** WRATH.
  - paladin / warrior `spell_query`, rogue `rogue_query`, hunter `spell_token`,
    shaman / druid `spell_query`: TBC+WRATH name first, `or <id>` fallback.
  - hunter `queue_tokens` unchanged (skip unnamed entries; no mixed id list); the shot
    guard, all id tables, `steady_id_by_family` and 3044/1978 untouched.
  - All "banned / never a bare id" claims in the touched comments corrected; the
    fallback is documented as operator-approved.
- `tests/spell_query_family_state.lua` rewritten off the false premise: 69/0, pins the
  name-first + id-fallback behaviour on both name families, Era/Forever/SoD ids, the
  walk's three verdicts, hunter token/queue behaviour, and static presence of every
  approved fallback. The old "no `or id`" static check is gone.
- Fixture/pin repairs where the restored fallback made the old expectation wrong
  (warrior_guide_state, bars_state, warrior_state, smoke, secret_guard_state,
  hunter_guide_state; comment-only in hunter_state/druid_state) — each listed in
  `bench/spell_resolution_2026-10-25.md` § CORRECTION.

### Current state
- All brief-listed focused suites green; extra focused checks (`hud_state`,
  `warrior_state`, `spell_known_state`, `real_wire_state`, `swing_source_state`,
  `class_activation_state`, `guide_contract`, `rogue_guide_state`, `toc_check`) green.
  `luac5.1 -p` clean; luacheck 0 errors / 1 pre-existing warning.
- Six mutation proofs on `/tmp/opencode` copies (all deleted): each fallback removal
  turns the new suite red.
- No id table touched; no git commands run; line endings preserved (compat/rogue/
  shaman LF; paladin/warrior/druid/hunter CRLF).

### Next step
- Orchestrator: reconcile and list changed files for the operator's client copy. The
  full `run.sh` was not run by this desk. Operator in-client confirmation on Titanforge
  3.80.2 remains the final word for the WRATH name-first branch.
