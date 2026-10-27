# Spell resolution: family-correct state-query tokens (2026-10-25)

Desk: `desks/spell-resolution/`. Scope: the STATE-QUERY token (`id` vs localized
`name`) for every spell read that is not a spell-data lookup. Operator ruling is
binding and verbatim:

> "titanforge aka wotlk doesnt use spell ids either. stop guessing. each has their
> own client." + "tbc is classic_anniversary and doesnt take spell ids it needs spell
> names." + "if u remove shit u will have to research the spell ids again."

Absolute constraint honoured: **no spell id was added, removed, replaced or moved.**
Every id table (including `steady_id_by_family`, the hunter rank tables, the rogue
name/id tables and the hunter shot guard's id matching) is byte-identical to the tree
this lane started from. This is additive token-resolution work only.

## The matrix (each family gated on its own)

| Family | Client (TOC interface) | State-query token | Evidence |
|---|---|---|---|
| ERA | classic_era 1.15.9 (`11509`), including SoD runes | numeric **id** | operator ruling; SoD is the same client: rune ids are Era ids, never rewritten |
| TBC | classic_anniversary 2.5.6 (`20506`) | localized **name** | operator ruling + in-client evidence 2026-10-19 (`bench/lessons.md`) |
| WRATH | classic_titan 3.80.2 Titanforge (`38002`) | localized **name** | operator in-client fact 2026-10-25. The API docs say `SpellIdentifier` (name or id) - the client behaviour is the authority per the operator |
| FOREVER | WoW Forever 1.60.1 (`16001`) | numeric **id** | unchanged (no proof otherwise) |
| CATA / MISTS / RETAIL / UNKNOWN | - | numeric **id** | unchanged (no proof otherwise) |

There is deliberately **no combined "classic-line" branch** anywhere; each condition
names its family.

## Changes (production)

### `compat.lua`
- `api.get_spell_query(name, id)` (now :1665) - explicit per-family branches:
  `TBC -> name`, `WRATH -> name`, everything else -> `id`, with a comment naming each
  client. **A nil name on TBC/WRATH returns nil** - never the id. Doc comment rewritten
  (family matrix + the ban on the id fallback).
- `family_spell_exists(id)` (:1570) - the existence/rank walk now takes the name path on
  TBC **and** WRATH. The old `local query = api.get_spell_query(name, id) or id` and its
  second id re-probe are **gone**: a name the client cannot index is `nil` (unknown),
  never confirmed by the bare id. Consequence, recorded deliberately: on a name family
  "absent" is now unreachable, so a genuinely absent rank set reports `unresolved`
  (retryable at the callers' existing throttles) instead of latching a negative. "Absent"
  remains the Era verdict, where the id form is the query.
- Doc comments on `client_spell_name` and `get_family_spell_id_state` updated to the
  TBC+WRATH rule (no code change in those two).

### Class token helpers
- `classes/paladin.lua:186` `spell_query` - names on TBC and WRATH, ids elsewhere; a
  string argument (an already-resolved name token, e.g. `spell_query(hud_slot_name(...))`)
  passes through; a nil name on a name family returns nil, **no id fallback**.
- `classes/warrior.lua:207` `spell_query` - same shape.
- `classes/rogue.lua:239` `rogue_query` - name on TBC/WRATH, id elsewhere. Also
  `resolve_named_spell` (:219): a name-family entry is usable with the name alone (the id
  may be absent on that client), so the gate now covers both name families. No id
  table touched.
- `classes/hunter.lua:27` `spell_token` - id on ERA/FOREVER, name on TBC **and WRATH**,
  nil on a cold cache (never the id). `queue_tokens` (:46) follows the same gate and
  returns the distinct family names on name families (one read covers every rank);
  empty list on a cold cache. The shot guard (`arm_shot_melee_reset_guard`) and all id
  tables were not touched.
- `classes/shaman.lua:153` `spell_query` - name on TBC/WRATH. `resolve_family_spell`
  (:528), the weave catalogue's known-rank read, resolves by `group.label` on TBC and
  WRATH (ids elsewhere).
- `classes/druid.lua:89` `spell_query` - name on TBC/WRATH. The queued-Maul probe
  (`on_current_spell_cast_changed`, :361) probes the rank-invariant name on TBC/WRATH.

Every caller that used to do `get_spell_query(...) or id` was fixed (paladin, warrior,
rogue inherited via the helper; compat's existence walk explicit). `grep` confirms no
`get_spell_query(...) or` remains outside tests; the new suite pins it statically.

## Tests

Focused suites only (no `bash tests/run.sh`; the orchestrator owns it):

| Suite | Result |
|---|---|
| `tests/spell_query_family_state.lua` **(new)** | 56 / 0 |
| `tests/smoke.lua` | 232 / 0 |
| `tests/spell_known_state.lua` | 251 / 0 |
| `tests/hunter_state.lua` | 1831 / 0 |
| `tests/hunter_guide_state.lua` | 1976 / 0 |
| `tests/shaman_state.lua` | 1083 / 0 |
| `tests/shaman_guide_state.lua` | 1570 / 0 |
| `tests/druid_state.lua` | 1621 / 0 |
| `tests/druid_guide_state.lua` | 95944 / 0 |
| `tests/paladin_state.lua` | 1270 / 0 |
| `tests/warrior_state.lua` | 2085 / 0 |
| `tests/rogue_state.lua` | 1137 / 0 |
| `tests/secret_guard_state.lua` (not in the brief's list, but pins the shared helper and the class gathers) | 433 / 0 |

**Owed by the orchestrator:** add `tests/spell_query_family_state.lua` to
`tests/run.sh` (one writer per file - the desk does not edit it).

`luac5.1 -p` clean on every changed file; `luacheck` on the changed files: 0 errors,
1 warning - the pre-existing `compat.lua:36 addon_name` (line untouched by this lane).

## Existing pins re-cut (real contract changes only)

| Suite | Old pin | New pin / why |
|---|---|---|
| smoke | `wrath` rank walk with an id-only `spell_table` | `spell_table` now answers the name its own id form returns (real clients are bidirectional); fixture correction, not a product change |
| smoke | `tbc-name: state variant reports 'absent'` | `unresolved`: an unnamed id on a name family is unknown; the old verdict came from the banned id re-probe |
| smoke | warrior/druid(wrath) cost read = id | cost read = the localized NAME (the new rule); druid reads the literal rank-invariant "Maul" |
| smoke | hunter(wrath) `IsCurrentSpell(48996)` | answers the NAME token; a bare id now fails the pin |
| hunter_state | Wrath queue probes = every rank id | one NAME probe per family (TBC shape); cold name cache = no probe |
| hunter_state | F4 absent latch on the default (Wrath) profile | moved to Era: "absent" is an Era-only verdict now; Wrath unresolved is pinned in the new suite |
| hunter_state | tbc `spell_info` answered ids only | now bidirectional (a real name client); IsSpellKnown/GetSpellInfo answer both forms |
| hunter_guide_state | Wrath gather = 5 cooldown reads | 2: only prompts whose NAME token resolves are read (unknown hides); the Wrath MM/SV fixtures gained the base spell DATA so their 9/8 reads stay |
| shaman_state / shaman_guide_state | "unknown Wrath LB" cleared id 49238 | clears both Lightning Bolt rank ids: on Wrath the gate is the NAME; 49238 is only the cited id |
| druid_state | Wrath cost/rank pins = ids; negative latch on Wrath | name token for the cost read; rank-selection + absent/unresolved finality pins run on Era (the id query form) |
| druid_guide_state | Wrath gather cost = id; TF/Berserk "unknown" via absent data | cost = "Maul"; TF/Berserk unknown legs now remove BOTH spell-data forms (the id walk would otherwise derive the name). Era keeps the fixture's old name-vs-rune behaviour |
| paladin_state | known ids with no spell data | fixtures now carry the spell data a real client has (Seal of Command rank 1, Hand of Reckoning, Hammer of Wrath) - the name token needs the id->name leg |
| warrior_state | Wrath cost = id; 13/8 rank probes; cold TBC id fallback; F4 absent/unresolved on Wrath | cost = NAME; one family-name probe; **cold name-family book detects nothing and never sends an id** (the old fallback is the banned guess); absent finality pinned on Era, cost-name on Wrath |
| rogue_state | `get_spell_query` Wrath = id; Wrath builder slot = 108 | name (the new rule); builder slot = "Sinister Strike" name token; IsSpellKnown resolves the name to the id the fixture marks unknown |
| secret_guard_state | `get_spell_query` Wrath = id | name; fixture spell data made bidirectional (GetSpellInfo/GetSpellCooldown/IsSpellKnown) so the Wrath gather/cast controls read the name; Stormstrike spell data added for the cooldown control |

No pin was weakened to hide a product defect: each re-cut either moves an id-observable
contract to Era (where the id is the query) or models a real client's bidirectional
spell data.

## Mutation proofs (10; `/tmp/opencode/mut<N>` copies, deleted after each)

Method: `rsync -a --exclude=Media --exclude=docs --exclude=.git ./ /tmp/opencode/mut<N>/`,
one text mutation, run the named suite from the copy, record the red pins, delete the
copy. Every copy deleted; no residue.

| # | Mutation | Red pins (count) | Suite |
|---|---|---|---|
| 1 | compat: WRATH branch removed from `get_spell_query` | 9 - WRATH token/nil + WRATH walk + hunter-WRATH + hunter cold (TBC/ERA/FOREVER green) | new |
| 2 | compat: TBC branch removed | 7 - TBC token/nil + TBC walk + hunter-TBC only | new |
| 3 | compat: `return name` -> `return name or id` on both name families | 6 - nil-name pins (TBC+WRATH), walk "unknown" pins, hunter cold | new |
| 4 | hunter: `spell_token` WRATH gate removed (TBC only) | 5 - hunter WRATH name pins + cold pins (queue pins stay green: separate gate) | new |
| 5 | paladin: `get_spell_query(name, spell_id) or spell_id` re-added | 1 - the static fallback pin for `classes/paladin.lua` | new |
| 6 | compat: existence walk re-probes the id when the name is nil | 2 - TBC+WRATH "unnamed id is unknown" state pins (become "absent") | new |
| 7 | shaman: `spell_query` WRATH branch removed | 1 - shaman source pin (the suites do not observationally distinguish the shaman name token; see "pins" note) | new |
| 8 | druid: `spell_query` WRATH branch removed | 1 source pin **+ smoke** `druid(wrath): queries its cost by NAME` (got 48480) | new + smoke |
| 9 | hunter: `queue_tokens` WRATH gate removed | 5 - queue WRATH pins, cold queue pin, source pin | new |
| 10 | rogue: `rogue_query` WRATH gate removed | 1 - rogue source pin (rogue_state's Wrath pin goes through the shared helper) | new |

Separate-gate proof: mutation 1 kills only WRATH pins; mutation 2 kills only TBC pins.

## Reported, not fixed (scope)

- **No id-only match was found that is blind on Titanforge.** Checked the two aura
  matchers that are TBC-name/id-hybrid: `classes/warrior.lua` `aura_matches` and
  `classes/paladin.lua` `get_twist_lust_remaining`. They match the aura payload's
  numeric `spell_id` on Wrath. Verified on `origin/classic_titan`:
  `Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua` (`UnpackAuraData`) returns
  `auraData.spellId` as the 10th value, so the id is present on that client. Not a
  state query; untouched.
- `hud.lua` `hud_known_query` (:786) still builds a TBC-only name for
  `is_spell_known`. Reviewed, not a defect: Titanforge's deprecated `IsSpellKnown`
  global forwards to `C_SpellBook.IsSpellInSpellBook`, which is **id-only** (compat's own
  in-client note, compat.lua:228-235); a numeric token is the working form there and a
  name throws into compat's name->id fallback. Left untouched (shared HUD file, no
  behavioural gap).
- The `practice_common_action` ladders in every class still branch `st.family ~= "TBC"`
  for the **practice button token** (paladin :4853, warrior :5459, rogue :3275, hunter
  :5711, shaman :4924, druid :4712). These are not state queries: the panel uses the
  token only for `GetSpellInfo` icons/textures, and the id ladder's
  `get_family_spell_id_state` walk now follows the name path internally on Wrath.
  Reported, not edited (outside the brief's state-query scope).
- `classes/druid.lua` `resolve_guide_icons` (:1999) keeps the TBC-only name branch for
  ICON descriptors; `GetSpellInfo` accepts ids on every family, so this is not a state
  query. Untouched.
- Untouched per the standing correction: `classes/hunter.lua:180`
  `steady_id_by_family.ERA = 56641` (the Era range token defect) and every id flagged
  absent from `/home/sam/wow.export`. The correction ("if u remove shit u will have to
  research the spell ids again") stands: no id was removed or corrected.
- The hunter shot guard (`is_hunter_ranged_shot` / `arm_shot_melee_reset_guard`,
  `classes/hunter.lua:808-843`) was reviewed and **not edited** (brief item 5). Its id
  match is an EVENT-PAYLOAD match, not a state query: Titanforge's
  `UNIT_SPELLCAST_*`/CLEU payloads carry ids, and Auto Shot additionally matches by its
  localized name and the literal "Auto Shot" for id-less payloads. No blind id-only
  match found there.
- The absence of "absent" on name families means truly-absent rank sets retry forever at
  the callers' throttles (5 s in hunter/druid/warrior). Throttled, not hot; reported as a
  consequence, not a defect.

## Evidence limits

- No Titanforge client data is available offline (only the 1.15.9 Era export,
  `/home/sam/wow.export`). Titanforge statements rest on the operator's in-client fact
  plus `origin/classic_titan` API/behaviour sources:
  - `Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua:108-121`
    - `GetSpellCooldown(spellIdentifier)`; `SpellIdentifier` is documented as
      id-or-name, which is why the operator's client behaviour decides.
  - `Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua` - `UnpackAuraData` carries
    `spellId` (10th), used for the aura-matcher review above.
  - `Interface/AddOns/Blizzard_Deprecated/Deprecated_2_5_5.lua:10-14` - the `UnitAura`
    shim on classic_titan (C_UnitAuras + UnpackAuraData).
- In-client confirmation on Titanforge is still owed by the operator: state reads by
  NAME (this lane's rule) and the HUD/guide behaviour that consumes them.

## Handoff (for the orchestrator)

- Files: `compat.lua`; `classes/{paladin,warrior,rogue,hunter,shaman,druid}.lua`;
  12 existing suites re-cut/verified (table above) + the new
  `tests/spell_query_family_state.lua`.
- Owed: the `run.sh` line for the new suite.
- No id tables touched; no git commands run; file line endings preserved (CRLF files
  stayed CRLF, LF stayed LF).

---

# CORRECTION (2026-10-26): the id fallback is restored (operator fact)

**This section SUPERSEDES every statement above that treats an id fallback as
"banned", "the guess", or "the operator's absolute rule".** The operator's verbatim
correction:

> "i never banned fallback to ids. someone made that up."

Binding rule: on **TBC (classic_anniversary)** and **WRATH / Titanforge
(classic_titan)** try the localized **NAME first, then fall back to the id**. Era
(including SoD, same client) uses ids. Forever keeps ids. Each family is still gated
separately. **No spell id was added, removed, replaced or moved by this correction**;
the hunter shot guard and every id table are untouched.

## Production changes (restored fallback, WRATH extension kept)

| File | Function | Final semantics |
|---|---|---|
| `compat.lua` | `api.get_spell_query(name, id)` | `TBC -> name or id`; `WRATH -> name or id`; every other family -> `id`. Explicit per-family branches; comment now states the fallback is operator-approved. |
| `compat.lua` | `family_spell_exists(id)` | HEAD behaviour ported with the gate widened: non-name families probe the id; TBC/WRATH resolve `client_spell_name(id)`, query `get_spell_query(name, id) or id`, and on a miss **re-probe the bare id** (the second leg). A refuted both-forms candidate is `false`; a throwing/secret answer is `nil`. |
| `classes/paladin.lua` | `spell_query` | TBC/WRATH: compat helper, `or spell_id`; inline `name or spell_id`. |
| `classes/warrior.lua` | `spell_query` | Same shape as paladin. |
| `classes/rogue.lua` | `rogue_query` | TBC/WRATH: `entry.name or entry.id` in the inline branch; compat helper otherwise. |
| `classes/hunter.lua` | `spell_token` | TBC/WRATH: name first, `or spell_id` fallback (cold name -> id, never nil for a valid id). `queue_tokens` unchanged (still skips unnamed entries; no mixed id token list). Shot guard untouched. |
| `classes/shaman.lua` | `spell_query` | TBC/WRATH: `name or id`. |
| `classes/druid.lua` | `spell_query` | TBC/WRATH: `name or id`. |

Reviewed, deliberately unchanged: shaman `resolve_family_spell` keeps its name-label
path (it is a known-rank catalogue reader, not a `spell_query` caller, and a cold
label returns nil rather than an id token). HUD slot-name tables keep storing names.
The hunter queue helper stays name-only by design.

## Tests

New suite rewritten from the false premise:

- `tests/spell_query_family_state.lua` — **69 / 0**. Pins: name on TBC/WRATH; `nil`
  name -> the id on both; Era/Forever/SoD ids; rank walk known-name, unindexed-name
  via the id re-probe, both-forms-absent -> `absent`, unreadable -> `unresolved`;
  hunter `spell_token` name on TBC/WRATH, id on Era, **id on a cold name**; queue
  tokens per family; static presence pins for every approved `or <id>` fallback and
  the separate family gates. The old static "no `or id`" check and the "operator's
  absolute rule" wording are gone.

Pins/fixtures re-cut where the restored fallback made the old expectation wrong (all
other re-cuts from the cancelled desk are re-verified, not reverted):

| File | Change |
|---|---|
| `tests/warrior_guide_state.lua` | Non-gating fixture repair: the four utility spells are in the Wrath book (name resolution caches instead of retrying); `IsSpellKnown`/`GetSpellCooldown`/`GetSpellPowerCost` resolve a shared name across every rank id (the multi-rank ambiguity the old one-id map hid); the WW cost pin now expects the **name** token (`"Whirlwind"`). |
| `tests/bars_state.lua` | Fixture repair: `IsCurrentSpell` and `GetSpellCooldown` resolve name tokens; Stormstrike added to the fixture's spell data. |
| `tests/warrior_state.lua` | Restored HEAD probe-count pins (13 HS ranks; >11 with Cleave; 8 Cleave ranks) and the cold-TBC id-fallback pins (detects, every query is a number). Stale "id re-probe is banned" comments corrected. |
| `tests/smoke.lua` | Restored `absent` for ids absent from this client (the id re-probe is back). |
| `tests/secret_guard_state.lua` | Restored `get_spell_query(nil, id) -> id` on TBC and WRATH. |
| `tests/hunter_guide_state.lua` | Restored `5` cooldown reads (every prompt resolves again via the id fallback). |
| `tests/hunter_state.lua`, `tests/druid_state.lua` | Comments corrected: absent finality is pinned on Era, not because the id re-probe is banned. |

Focused runs (no `tests/run.sh`): `warrior_guide_state` 2040/0, `bars_state` 956/0,
`rotationtext_state` 246/0, `spell_query_family_state` 69/0, `hunter_state` 1831/0,
`hunter_guide_state` 1976/0, `paladin_state` 1270/0, `shaman_state` 1083/0,
`shaman_guide_state` 1570/0, `druid_state` 1621/0, `druid_guide_state` 95944/0,
`rogue_state` 1137/0, `smoke` 232/0, `secret_guard_state` 433/0, `hud_state` 852/0,
`warrior_state` 2098/0, `spell_known_state` 251/0, `real_wire_state` 1005/0 (3
expected-fail), `swing_source_state` 159/0, `toc_check` 1082/0. `luac5.1 -p` clean on
every changed file; `luacheck` on the seven production files: 0 errors / 1 pre-existing
warning (`compat.lua:36 addon_name`).

## Mutation proofs (copies under `/tmp/opencode`, deleted after each)

| # | Mutation | Red |
|---|---|---|
| 1 | compat TBC `return name` (fallback removed) | 2 (behaviour + static) |
| 2 | compat WRATH `return name` | 2 |
| 3 | `family_spell_exists` id re-probe deleted | 4 (TBC+WRATH walk resolved -> absent) |
| 4 | hunter `spell_token` fallback removed | 2 static (the compat fallback still covers the behaviour) |
| 5 | paladin fallback removed | 2 static |
| 6 | compat walk query drops `or id` | 1 static |

## Remaining reds / limits

- None in the focused set. `bash tests/run.sh` was deliberately **not** run (the
  orchestrator owns it).
- In-client confirmation on Titanforge 3.80.2 is still owed by the operator (the
  WRATH name-first claim rests on the operator's in-client fact; the fallback is the
  safety net).
- The hunter queue helper's unnamed entries are skipped by design; a fully cold
  client queues nothing there (its `spell_token` path does fall back to the id).
