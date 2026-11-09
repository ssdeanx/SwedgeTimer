# F4 class side — the druid/warrior rank latches tell "absent" from "unresolved" (2026-10-19)

Desk: **class-f4-latch**. Scope: `classes/druid.lua`, `classes/warrior.lua`,
`tests/druid_state.lua`, `tests/warrior_state.lua` (pins). Nothing else was touched —
`compat.lua` belongs to the compat-f4 desk, and `main.lua`, `diag.lua`, `hud.lua`,
`bars.lua`, the practice/options/config files, the guides, `tests/run.sh`, the TOCs, the
versions and the docs belong to sibling lanes. No git, no lint-config change.

Audit source: `bench/deep_audit_2026-10-19.md` F4 → bench artifact
`bench/f4_family_spell_id_2026-10-19.md` (§2 residual: "switch the two latches to the
state API — `unresolved` → retry, `absent` → latch false").

---

## 1. What changed

Both class latches had the same shape (`classes/druid.lua:92`, `classes/warrior.lua:367`):

```lua
local function resolve_rank(ids, cached)
    if cached == nil then
        return api.get_family_spell_id(ids) or false   -- any nil latched false
    end
    return cached
end
```

`api.get_family_spell_id` answers an id or nil, so a **transient** "the client could not
answer" (a cold spell book, a restricted read) was indistinguishable from the client's
own "this spell is not here" — and the negative latched for the rest of the session.
The compat lane fixed the resolver side (`api.get_family_spell_id_state` →
`id, state ∈ {resolved, absent, unresolved}`); the class side now uses that verdict:

```lua
local function resolve_rank(ids, cached)
    if cached ~= nil then
        return cached
    end
    local now = api.get_time()
    if type(now) == "number" and now < (rank_retry_at[ids] or 0) then
        return nil                       -- still backing off: no walk, no latch
    end
    local id, state = api.get_family_spell_id_state(ids)
    if id ~= nil then
        return id                        -- resolved: the id latches
    end
    if state == "absent" then
        return false                     -- absent: FINAL, the negative latches
    end
    -- unresolved: nothing is latched; the next attempt asks again
    if type(now) == "number" then
        rank_retry_at[ids] = now + RANK_RESOLVE_RETRY
    end
    return nil
end
```

- **`absent` is the only latch for a negative** (the client's own spell data refuted every
  candidate — final).
- **`unresolved` latches nothing**: the cached value stays as it was (nil = "not resolved
  yet"), and the next resolve attempt asks the client again.
- **No default-visible change**: on a client that answers, the verdict is `resolved` (the
  same id as before) or `absent` (the same `false` as before). Only the "cannot answer"
  path changes, and it changes from *permanently poisoned* to *retryable*.

### The retry backoff (why there is one)

`resolve_rank` is called from `gather_guide_inputs` — the **per-frame** gather path
(`classes/druid.lua:1854`, `classes/warrior.lua:2800`+) — not only from the power event.
Without a bound, a client that cannot answer would re-walk the whole rank table every
frame (10 candidates × ~2 probes each, 60×/s). The lane therefore mirrors the rogue
lane's retry-able latch (`classes/rogue.lua`, `ROGUE_SPELL_RETRY = 5.0`): a per-rank-table
backoff of 5 s, keyed by the rank table itself (`rank_retry_at[ids]`), so the tables back
off independently. The backoff is the *only* new timing behaviour, and it is invisible on
a client that answers.

## 2. Pins

**`tests/druid_state.lua`** (new section 37) and **`tests/warrior_state.lua`** (new
section 35) pin the same four things:

| Pin | What it proves |
|---|---|
| F4 absent | the client is asked once; a refuted rank reads no rage cost; after the retry window the walk does **not** happen again (the negative is final) |
| F4 unresolved | the client is asked once; an unanswered rank reads no rage cost; the retry backoff holds the walk (no hot loop); once the client answers, the attempt after the backoff asks again, the rank resolves, the cost query reads the confirmed rank id, and the rank then latches |
| F4 Era | the rank resolves **by id** (`ST.DRUID.guide.slots[1].spell_id` / `ST.WARRIOR.guide.slots[4].spell_id` = the client's rank) and the client is **never asked by name** (the recorded `GetSpellInfo` query log holds no string query) |
| F4 TBC | a client that answers **no id at all** (the name-only client: the id form finds nothing, `C_Spell` carries the id → name mapping) still resolves the rank — the **name path** decided it — and the client *is* asked by name |

Fixture work (the two class suites): the `GetSpellInfo` stub now records every query
(`sb.spell_queries`), can raise on demand (`sb.spell_info_throws` → compat's `pcall`
reports "could not answer" → `unresolved`), answers the client's own name for a known
spell (the name back-map), and can be built as a **name-only TBC client**
(`opts.name_only_client` + the `C_Spell` bridge) — the shape the compat lane verified on
the client source. The resolver counter now wraps `api.get_family_spell_id_state` (the
class's entry point); the plain resolver is counted too, so the pin "the class resolves
through the state API, not the plain one" bites.

Suites: `tests/druid_state.lua` 631 checks / 0 failures · `tests/warrior_state.lua`
1047 checks / 0 failures.

## 3. Mutation battery (`/tmp/opencode/mut_class_f4.py`, fresh tree copies)

Control: the pristine copy is green on both suites. **10/10 mutants killed** — every kill
is a real pin failure, and every mutant parses (`luac5.1 -p` is checked before the suite
runs, so a syntax error can never count as a kill):

| Mutant | Killed by |
|---|---|
| M1/M2 `unresolved` latches false (the exact F4 residual) | "F4 unresolved: the attempt after the backoff asks again" + "the resolved rank reaches the cost query" + "the resolved rank latches" |
| M3/M4 `absent` never latches (the negative is not final) | "F4 absent: the negative is final (never re-walked)" |
| M5/M6 the retry backoff removed (a hot re-walk per frame) | "F4 unresolved: the retry backoff holds the walk" (+2 more) |
| M7/M8 the class ignores the state API (plain resolver again) | "the class resolves through the state API, not the plain one" + "F4 absent: the negative is final" |
| M9/M10 the resolved id is never used (the rank never resolves) | "the queued Maul/Heroic Strike rank is the cost that gets queried" (+3 more) |

## 4. Validation

- `bash tests/run.sh` → **41 steps, 0 failed** (the tree's step count: the compat-f4 lane
  recorded 40 before the practice-progress lane added its suite to `tests/run.sh` — a
  sibling lane's file, not this lane's).
- `luacheck .` → **2 warnings / 0 errors** — the pre-existing floor
  (`compat.lua:36` unused `addon_name`, `main.lua:77` `table.pack`); this lane adds
  **zero** warnings. `luacheck classes/druid.lua classes/warrior.lua` → 0/0.
- Line endings preserved: the two class files stay CRLF (every line), the two test files
  stay LF. Touched lines carry no trailing whitespace and no tabs.
- No default-visible change, no new toggle, no user-visible string.

## 5. What is NOT proven here

- **In-client**: that a real TBC Anniversary 2.5.6 client reaches the `resolved` verdict
  for a rank through the name path. The compat lane owns that half of F4 and recorded the
  open operator check (HU-6: `/run print(GetSpellInfo(29707))` vs
  `/run print(GetSpellInfo("Heroic Strike"))`). This lane's TBC pin proves the class
  *consumes* the name-path verdict correctly; it cannot prove the client produces it.
- **The plain resolver's callers elsewhere are untouched** and stay on the two-valued
  contract: `classes/hunter.lua` (12 call sites) and `classes/warrior.lua:1552`
  (`get_slam_fallback_duration`, called once per Slam cast, not a latch). Those are not
  latches, so F4's residual does not apply to them; converting them is a separate call.
- The retry interval (5 s) is the rogue lane's value, not an in-client measurement. It
  only bounds a probe rate on a client that cannot answer; it never changes a resolved
  rank.

## 6. Files changed

| File | Change |
|---|---|
| `classes/druid.lua` | the rank latch (three-valued verdict + the 5 s per-table retry backoff) |
| `classes/warrior.lua` | the same latch, same shape |
| `tests/druid_state.lua` | fixture (query log, throwing client, name-only TBC client, the state-API counter) + the latch pins updated to the state API + new section 37 |
| `tests/warrior_state.lua` | fixture (same) + the latch pins updated to the state API + new section 35 |
