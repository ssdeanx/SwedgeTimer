# rogue-nameid (2026-10-19) — TBC-name / Era-id conversion

Desk: rogue-nameid. Objective: operator name-vs-id rule (bench/lessons.md: TBC resolves
by NAME never bare id; Era by id; pin both). Scope: classes/rogue.lua,
rogue_guide.lua, compat.lua (helper only), tests/rogue_state.lua,
tests/rogue_guide_state.lua, tests/secret_guard_state.lua (compat pins only).

## Helper (compat.lua, LF kept — one addition, nothing else)

- Verified missing first: no `get_spell_query` / `spell_query` / `name_or_id` /
  `resolve_spell` in compat.lua (only hunter_ui.lua has a local `resolve_spell`,
  unrelated). Existing `get_family_spell_id` (bare-id) untouched — out of scope.
- Added `api.get_spell_query(name, id)`: TBC→name, else→id. No new client probe,
  family branching only. Comment cites operator rule 2026-10-19.

## Rogue classification (classes/rogue.lua, CRLF kept — every id use)

| # | Use | Families | Disposition |
|---|---|---|---|
| 1 | ROGUE_LUST_IDS 2825/32182 via scan_player_aura | TBC+ path (lust_supported false on Era) | CONVERTED: added ROGUE_LUST_NAMES Bloodlust/Heroism; TBC predicate matches name, else matches id |
| 2 | resolve_named_spell GetSpellInfo(name)→id | init, both | CONVERTED: TBC accepts name-only entry (id may be nil); Era requires numeric id |
| 3 | apply_spell_ids slot.spell / slot.spell_id = entry.id | all | CONVERTED: stores rogue_query(entry) + spell_name (name on TBC, id on Era) so HUD/nextaction icons via GetSpellInfo never bare-id on TBC |
| 4 | find_unit_aura(wanted_id, wanted_name) dual-match | all aura reads | CONVERTED: branches inside — TBC name-only, else id-only |
| 5 | spell_cooldown(entry.id) | AR/BF/Shiv/CB/Tea/Kick/Kidney/Restealth/Bandage | CONVERTED: takes query (number\|string), calls GetSpellCooldown(query) |
| 6 | is_spell_known(entry.id) ×6 + IsSpellUsable(entry.id) | gather + HUD | CONVERTED: via rogue_query(entry) |
| 7 | IsSpellInRange(entry.name) Kick/Kidney | range | CONVERTED: via rogue_query(entry) (name on TBC, id on Era) |
| 8 | rotation_ability_name GetSpellInfo(spell_id) | label | CONVERTED: TBC returns cached slot name (no API call, never bare id); Era GetSpellInfo(id) |
| 9 | ROGUE_SOD_ENVENOM_RUNE_ID 399963 via is_spell_known | ERA-gated latch | KEPT (Era-by-id, correct): `st.family=="ERA" and ...` short-circuits, TBC never probes |
| 10 | Item probes (Tea/Bandage names, inventory ids) | both | NOT spell ids — untouched (name-based items correct on both) |
| 11 | Pickpocket / CttC | — | ZERO uses in file — nothing to convert (static pin) |
| 12 | SPELL_IDS / POISON_IDS | — | Stay empty (no remembered ids) |
| rogue_guide.lua | — | pure engine | ZERO spell-id uses (grep: no spell_id/GetSpellInfo/is_spell_known/GetSpellCooldown) — no conversion |

`rogue_query(entry)` prefers the shared helper, inline `st.family=="TBC"` fallback
so the module never depends on load order.

## Pins

- tests/rogue_state.lua §19 (new, 30 checks): helper TBC/Era/Wrath; slots
  TBC-name/Era-id (HUD + guide, all-known Saber leads); cooldown TBC-name-only /
  Era-id-only + cross-miss; aura TBC-name-only / Era-id-only + cross-miss; lust
  TBC-name / Wrath-id; rotation TBC-no-bare-id-call / Era-id; SoD Era-latch /
  TBC-never; static (no Pickpocket, single bare id = gated SoD, LUST_NAMES ships,
  rogue_query funnels). Suite: 482 checks, 0 failures.
- tests/secret_guard_state.lua §15 (new, 16 checks): helper TBC→name, Era→id,
  Wrath→id, nil-safety both. Suite: 336 checks, 0 failures.
- tests/rogue_guide_state.lua: untouched, 642/0 (pure, zero uses).
- tests/smoke.lua: 183/0 (helper additive).

## Validation

- Scoped: rogue_state 482/0, rogue_guide_state 642/0, secret_guard 336/0,
  smoke 183/0; luacheck scoped files 1 warning/0 errors (pre-existing
  compat.lua:36 `addon_name` KEEP floor, zero new).
- Mutations on /tmp/opencode/muts_rogue_nameid: 8/8 bitten (helper TBC/Era flip,
  aura branch flip, cooldown bypass, lust id-on-TBC, slot id-on-TBC, SoD
  un-gated, rotation bare-id) + clean-copy sanity PASS.
- Full harness NOT green (crossfire + one owned break, both for orchestrator):
  tests/guide_contract.lua parity-cb fails (its GetSpellCooldown stub answers id
  5111 only; TBC now queries "Blade Flurry" — correct per rule, but the file is
  out of scope so left untouched); shaman_state (shaman.lua:740 nil entry),
  druid_guide_state (Mangle), shaman_guide_state (weave catalogue) are sibling-lane
  mid-edits, not this lane.
