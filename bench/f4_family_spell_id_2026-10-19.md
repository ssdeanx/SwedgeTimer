# F4 — compat.get_family_spell_id: TBC name path + "unresolved ≠ absent" (2026-10-19)

Desk: **compat-f4** (session `ses_ea97ceaa6ffeWHYdLP9XZzl0s9`). Scope: `compat.lua`,
`tests/smoke.lua`, `tests/secret_guard_state.lua` — nothing else. No git, no TOC/option/
class/doc edits.

Audit source: `bench/deep_audit_2026-10-19.md` F4 — *"`compat.get_family_spell_id`
(`compat.lua:1268-1282`) walks a rank table calling `api.GetSpellInfo(id)` with numeric
ids, but TBC Anniversary resolves by NAME (operator-confirmed rule,
`bench/lessons.md:29-32`) → every lookup returns nil on TBC, indistinguishable from
'rank absent', and callers latch false (`classes/druid.lua:94`, `classes/warrior.lua:369`)
so a cold TBC book never re-resolves."*

The audit itself flagged the gap as **UNVERIFIED**: its per-client API table was cited
from the addon's own `compat.lua`, not from the client source, and it closed with "a
dedicated cross-client truth pass against wow-ui-source is still owed (F4 in particular
against `classic_anniversary`)". That pass is part of this lane.

---

## 1. Cross-client truth pass (read-only, `git show <branch>:<path>`; no checkout)

Branches read: `classic_era` (Era/SoD 1.15.9), `classic_anniversary` (TBC Anniversary
2.5.6.70006), `classic_titan` (Wrath Titanforge), `origin/forever` (WoW Forever 1.60.1),
`live` (Retail). Citations are `branch:file:line`.

| Fact | Evidence |
|---|---|
| `C_Spell.GetSpellInfo(spellIdentifier)` takes **"Spell ID, name, name(subtext), or link"** and returns a `SpellInfo` structure | `classic_era:Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua:190-197`; `classic_anniversary:...:190-197`; `classic_titan:...:190-197`; `origin/forever:...:416-424`; `live:...:375-383` (byte-identical block on the three classic branches) |
| The `SpellInfo` structure has a non-nilable `name` string (plus `iconID`, `originalIconID`, `castTime`, `minRange`, `maxRange`, `spellID`) | `classic_era/classic_anniversary/classic_titan:.../SpellDocumentation.lua:782-786`; `origin/forever:...:1183-1187`; `live:...:1109-1113` |
| The `C_Spell` namespace answers for spells the player has **not** learned — it is the spell **database**, not the player's spell book | `DoesSpellExist`, "Returns true if the spell exists, regardless of whether the player has learned it" — `classic_anniversary:.../SpellDocumentation.lua:21-23` (identical `classic_era:...:21-23`) |
| The native global `GetSpellInfo` is **called in id form by Blizzard's own code** on the classic path | `classic_anniversary:Interface/AddOns/Blizzard_ObjectAPI/Classic/Spell.lua:39` — `return (GetSpellInfo(self:GetSpellID()))`, the spell book's canonical name accessor, loaded through `Interface/AddOns/Blizzard_ObjectAPI/Blizzard_ObjectAPI_Classic.toc` (`## AllowLoadGameType: classic`) |
| The native global is native on every branch (no Lua definition to read) | `git grep "^GetSpellInfo\s*="` is empty on all five branches (already recorded in `bench/perclient_api_audit_2026-10-19.md` §1) |

**What the evidence says about the operator rule.** The operator's rule
(`bench/lessons.md:29-32`, "TBC Anniversary API takes spell NAMES, not ids; Classic Era
needs ids") is an in-game confirmation and stands. For `GetSpellInfo` **specifically** the
client source shows the classic-line global being indexed by id (the ObjectAPI accessor
above), i.e. the source and the rule disagree about that one function. The two facts are
not reconcilable from source alone — the operator read the live client, the source shows
the shipped FrameXML.

**Therefore the fix is built to work under BOTH readings** — the name path is the primary
query on TBC and the id form is the documented fallback. Neither reading can regress.

## 2. What changed (`compat.lua`, one section)

`api.get_family_spell_id` keeps its contract (a candidate id or nil) and is now built on
three new locals in the "Per-family spell data helpers" section:

- **`client_spell_name(id)`** — the client's own name for a candidate id, from two
  sources in order: (1) the native global's id form (Blizzard's own accessor,
  `Spell.lua:39`); (2) the `C_Spell` namespace (`SpellDocumentation.lua:190-197`), which
  is the source that still answers when the global only answers names. A restricted
  (secret) answer is never used as a query and never compared.
- **`spell_data_present(ok, value)`** — one answer reduced to `true` (the client has this
  spell) / `false` (the client answered "not found") / `nil` (the call threw, or the
  answer was restricted). The secret branch matters: comparison with a secret value
  raises in-client, so it is checked with `is_secret` first.
- **`family_spell_exists(id)`** — the family-correct probe. Non-TBC keeps today's id
  form. TBC builds the query through the existing helper
  `api.get_spell_query(name, id)` (the name-vs-id lane's helper, `compat.lua` "Spell
  query" block) and falls back to the id form when the name index misses.

New public API: **`api.get_family_spell_id_state(id_table)` → `id, state`** with
`state ∈ {"resolved", "absent", "unresolved"}`:

| state | meaning |
|---|---|
| `resolved` | a candidate was confirmed on this client (the id is returned) |
| `absent` | the client's own spell data refuted every candidate — **final** |
| `unresolved` | the client could not answer (threw, or the answer was restricted) — **retryable** |

`api.get_family_spell_id(id_table)` is now a thin wrapper over it, so **every existing
caller keeps its exact contract** and no class file had to change.

### Why the latch can no longer be poisoned by a cold book

1. The rank resolution now reads the client's **spell database**, not the player's
   spell book (the client's own wording: "regardless of whether the player has learned
   it", `SpellDocumentation.lua:21-23`). A cold book cannot take the answer away.
2. On TBC the query is the **name** (the operator's rule), so the id-form miss that used
   to look like "rank absent" no longer happens; the name path resolves the TBC rank.
3. "Could not answer" is a **separate verdict** from "not here": the caller can tell
   `absent` (final) from `unresolved` (retryable) and latch a negative only for the
   first. `classes/druid.lua:94` / `classes/warrior.lua:369` still latch `false` on a nil
   result (class files are out of this lane's scope) — but on TBC the resolver no longer
   returns nil for a rank the client knows, so that latch is no longer reached by the
   cold-book case. **Residual for the class-file lane: switch the two latches to the
   state API (`unresolved` → retry, `absent` → latch false).** The rogue lane's
   retry-able latch (`classes/rogue.lua:203-224`) is the in-tree precedent.

## 3. Pins

**`tests/smoke.lua`** (the suite that owns the compat client-profile probes — its own
header says so; `tests/secret_guard_state.lua` owns the helper-level pins):

- New `tbc-name` profile: the native global indexes **names only** (an id query finds
  nothing) + the `C_Spell` bridge. Pins: HS → `29707`, Maul → `26996` ("through the NAME
  path"); "the client was asked by NAME"; the state variant reports `resolved` /
  `absent`.
- New `era-id` profile: the global indexes ids only. Pins: HS → `29707` by ID; "the
  client is never asked by name"; state `resolved` / `absent`.
- New `unresolved` profile: the global throws. Pins: no rank resolved, state
  `unresolved`.
- Existing pins kept green: wrath/era/legacy-20506/retail/cata/mists spell-id walks.

**`tests/secret_guard_state.lua`** (extends §15, the existing name-vs-id section):

- §15b — the rank walk in both directions (TBC name path, Era id path), the
  `absent` vs `unresolved` split, and the secret discipline: a restricted spell name
  resolves no rank, reports `unresolved`, and **never leaves as a query** (the sandbox
  now records `GetSpellInfo` queries for that proof).
- The sandbox's `GetSpellInfo` stub gained `sb.spell_info_throws` (the file's existing
  `*_throws` idiom) and a query log.

Suites: `tests/smoke.lua` 206 checks / 0 failures · `tests/secret_guard_state.lua`
373 checks / 0 failures (was 359 before this lane).

## 4. Validation

- `bash tests/run.sh` → **40 steps, 0 failed**; luacheck **2 warnings / 0 errors**
  (the floor: `compat.lua:36` unused `addon_name`, `main.lua:77` `table.pack` — both
  pre-existing, both KEEP-ruled; this lane adds zero warnings).
- `luacheck compat.lua` → 1 warning (the pre-existing floor one), 0 errors.
- Mutation battery `/tmp/opencode/mut_f4.py` (fresh tree copies, pristine control
  green): **11/11 killed** —
  M1 the TBC name path removed → the `tbc-name` resolution pin dies ·
  M2 the `C_Spell` id→name bridge dropped → the `tbc-name` resolution pin dies ·
  M3 the id-form fallback dropped → the legacy-20506 TBC walk dies ·
  M4/M5 `spell_data_present` never reports "not found" / never reports "present" →
  the era/wrath walks die · M6/M7 the state never reports `unresolved` / never reports
  `absent` → the state pins die · M8 the secret guard dropped from
  `client_spell_name` → "a restricted spell name never leaves as a query" dies · M9 the
  secret guard dropped from `spell_data_present` → "a restricted spell name resolves no
  rank" dies · M10 the family query always uses the id (the name-vs-id branch dead) →
  the `tbc-name` resolution pin dies · M11 `get_family_spell_id` claims the highest
  candidate regardless of the state → the era walk dies.

## 5. What is NOT proven here

- **In-client, on TBC Anniversary 2.5.6**: which query form the native global really
  answers. The fix works under both readings; the operator's rule was not overridden and
  the source contradiction is recorded above rather than argued away.
- **The class-file latches** (`classes/druid.lua:94`, `classes/warrior.lua:369`) still
  latch a negative on a nil result. Out of this lane's scope; the state API is there for
  the lane that owns those files (see §2 residual).
- No default-visible change: the resolver returns the same id on every family where the
  old walk resolved one, and nil where the old walk returned nil.
