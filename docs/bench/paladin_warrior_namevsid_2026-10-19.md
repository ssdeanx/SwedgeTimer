# paladin + warrior name-vs-id application — 2026-10-19

Desk: paladin-warrior-eratbc (follow-up to the Era/SoD/TBC verify lane, zero-code).
Scope executed: ONLY `classes/paladin.lua`, `classes/warrior.lua`,
`tests/paladin_state.lua`, `tests/warrior_state.lua`,
`tests/warrior_guide_state.lua`. Read-only: `nextaction.lua`, `twist.lua`
(pure, no API calls), `compat.lua` (owns `api.get_spell_query`, rogue lane),
`nextaction_ui.lua` (slot icon path), TBC Anniversary FrameXML (contract check).

Rule (operator-confirmed, bench/lessons.md): TBC Anniversary resolves by
NAME, never bare id; Classic Era resolves by id. Family branch via
`st.family`, never version strings. Consumer: compat's
`api.get_spell_query(name, id)` (TBC→name, else id) with an inline family
branch as fallback. Cold-book discipline: names resolve through the client's
own GetSpellInfo and cache; an unresolvable name falls back to the id
(smoke.lua's id-only TBC profile must keep passing and is out of scope).

## What changed

`classes/paladin.lua` (CRLF kept): shared `resolve_spell_name` /
`spell_query` / `is_spell_known_query` / `aura_matches` + per-table name boxes;
parse_seals (8 seal tables), both JotC scans, lust scan (resolved or literal
English names) match name-or-id on TBC / id-only on Era; ALL cooldown reads
(CS/judge/DS/HW/HS/AM/HoW via the central `get_guide_cooldown_remaining`,
Judgement marker, CD slots, Wings) query through `spell_query`; ALL
knowledge probes (CS, SOC rank-1, DS/HW/HS/AM resolvers, SoD rune legs,
racial) go through `is_spell_known_query`. Retained: AoW id (no TBC
existence), ERA-gated SoD auras, FOREVER echo tables, filler/hud_slot_name/
hud_no_mana/hud_out_of_range (already name-first), slot spell ids (icon
descriptors via GetSpellInfo, id-valid on both families), event-arg id
matches (client-provided values, not resolves), LCD input (vendored lib).

`classes/warrior.lua` (CRLF kept): same helper shape; `get_guide_cooldown`
+ all 9 power-cost reads + both IsCurrentSpell loops query through
`spell_query`; Blood Surge aura scan matches through `aura_matches`; ALL
knowledge probes (arms, SoD runes, hamstring, SoD rend rune, Bladestorm,
Victory Rush) go through `is_spell_known_query`. Retained: SD/TFB/rampage/
shout/debuff/rend/sunder/shield/overpower/slam matchers (already
id+localized+literal superset — covers TBC names), Victory Rush name reads,
slot spell ids (icon descriptors), `get_family_spell_id`/`GetSpellInfo`
resolver chains, event-arg id matches.

`warrior_guide.lua`: NO CHANGE (pure engine, no API calls — verified
read-only; strict-sandbox load pins it).

Tests: sandboxes emulate name-capable clients (GetSpellCooldown /
GetSpellPowerCost / IsSpellKnown answer names via book maps + record query
keys). New pins: TBC string queries vs Era numeric queries (cooldowns,
costs, probes, IsCurrentSpell); TBC name-only latches (wrong id + right name
matches; cold book falls back to id, never errors); Era id-only latches
(wrong id + right name does NOT match); slots stay numeric ids on both;
static wiring pins (`api.get_spell_query`, `st.family == "TBC"`,
no version strings).

## Validation (all on the in-tree state unless noted)

- In-scope suites: paladin_state **423/0**, warrior_state **852/0**,
  warrior_guide_state **1410/0** (was 38-step harness: these three green).
- luacheck on the 5 touched files: **0 warnings / 0 errors**.
- Mutation battery `/tmp/opencode/muts_namevsid_palwar.py` (fresh tree
  copies): control PASS + **6/6 KILLED** (paladin/warrior query dead,
  aura-match dead, probe bypass, each side).
- Line endings kept (CRLF sources, LF tests); touched-lines whitespace only.

## Residuals / handed up (NOT built — out of scope, orchestrator owns)

- H1 (hands-up HU-new): `tests/hud_state.lua` 8 fails + `tests/guide_contract.lua`
  4 fails — id-keyed TBC fixtures vs name queries. All 12 share one root
  cause; fixes are one-token re-keys (names already resolve in those
  sandboxes): hud_state `cooldowns[35395]`→`["Crusader Strike"]` (§5/§7),
  `cooldowns[31884]`→`["Avenging Wrath"]` (§7), `known_spells[35395]`→add
  `["Crusader Strike"]`; guide_contract `pal.cooldowns[35395]`→`["Crusader
  Strike"]`, `pal.cooldowns[20271]`→`["Judgement"]`, `pal.known`→add the
  name key (lines 758-760, 977-978). Filed as hands-up, not built.
- Tree luacheck floor moved 2→8 by parallel-lane files (druid.lua 4,
  shaman_state.lua 2) — untouched here; reconcile owns.
- In-client truth (does TBC's IsSpellKnown/C_Spell chain accept the name
  probes the same way rogue's already do): UNCONFIRMED — owner test session.
  Fallback design means a wrong premise degrades to today's id behavior.
