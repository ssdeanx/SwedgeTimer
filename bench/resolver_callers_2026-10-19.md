# F4 plain-resolver callers — the hunter's rank resolution and the warrior's Slam fallback (2026-10-19)

Desk: **resolver-callers**. Scope: `classes/hunter.lua`, `classes/warrior.lua`,
`tests/hunter_state.lua`, `tests/warrior_state.lua` (pins). Nothing else was touched —
`compat.lua` is settled (the compat-f4 desk owns it), and `main.lua`, `diag.lua`,
`hud.lua`, `bars.lua`, the practice/options/config files, the guides, `tests/run.sh`,
the TOCs, the versions and the docs belong to sibling lanes. No git, no lint-config
change.

Audit source: `bench/deep_audit_2026-10-19.md` F4 → bench artifact
`bench/f4_family_spell_id_2026-10-19.md` (§2: the resolver answers `id, state ∈
{resolved, absent, unresolved}`) and `bench/class_f4_latch_2026-10-19.md` (§5: the
plain-resolver callers that are **not** latches — "classes/hunter.lua (12 call sites)"
and `classes/warrior.lua`'s `get_slam_fallback_duration` — "still run on the two-valued
contract … converting them is a separate call").

**The count is ten, not twelve.** `classes/hunter.lua` had exactly **ten**
`api.get_family_spell_id(...)` call expressions (the nil-guard on line 1243 and a
comment on line 2195 are not calls). They cover **fifteen rank tables**: the guide's
seven direct slots (steady, raptor, kill command, multi, bestial wrath, rapid fire,
aimed), the seven knowledge-gated slots behind the shared `resolve_known` helper (kill
shot, chimera (Wrath), explosive, aimed (Wrath), arcane, hawk, sniper) and the SoD
chimera table. The drill's three shot icons ride the same tables (steady, multi,
aimed), so they add no walk of their own.

---

## 1. What changed

### 1.1 `classes/hunter.lua` — a cached, three-valued, bounded rank resolution

The class had no resolver of its own: every site called the plain two-valued resolver
and read a `nil` as "this rank does not exist". Because `resolve_guide_icons()` runs
**once** (at `post_init`), a transient "the client could not answer" was permanent for
the session: the slot kept its rank-1 fallback and the guide's `*_known` flags stayed
false, so the prompt never came.

The class now owns the same shape the druid/warrior latch lane built (audit F4):

```lua
local RANK_RESOLVE_RETRY = 5.0
local rank_resolved = {}   -- per rank table: the latched verdict (an id, or false)
local rank_retry_at = {}   -- per rank table: the next allowed retry after "unresolved"
local pending_ranks = {}   -- the tables whose verdict is still "unresolved"

local function resolve_rank(ids)
    local cached = rank_resolved[ids]
    if cached ~= nil then
        if cached == false then return nil end   -- absent: FINAL, the negative is latched
        return cached
    end
    if api.get_family_spell_id_state == nil then return nil end   -- no resolver: hide
    local now = api.get_time()
    if type(now) == "number" and now < (rank_retry_at[ids] or 0) then return nil end
    local id, state = api.get_family_spell_id_state(ids)
    if id ~= nil then
        rank_resolved[ids] = id; pending_rank_drop(ids); return id
    end
    if state == "absent" then
        rank_resolved[ids] = false; pending_rank_drop(ids); return nil
    end
    -- "unresolved": nothing is latched; the next attempt asks again, after the backoff.
    pending_rank_add(ids)
    if type(now) == "number" then rank_retry_at[ids] = now + RANK_RESOLVE_RETRY end
    return nil
end
```

- **`absent` is the only latch for a negative** (the client's own spell data refuted
  every candidate — final, the table is never walked again).
- **`unresolved` latches nothing**: the table joins the retry set and the next attempt
  asks again, so a cold spell book can no longer poison the rank for the session.
- **The nil guard moved with the call**: the old `api.get_family_spell_id == nil`
  guard in `practice_shot_spell_id` became `api.get_family_spell_id_state == nil`
  inside `resolve_rank`, so every site (not just the drill) hides instead of throwing
  when the resolver is absent.

**The retry is driven from the per-frame path, bounded.** `gather_guide_inputs` is the
per-frame gather (the guide's tick calls it every frame), and it now opens with the
retry driver:

```lua
local function retry_pending_ranks(now)
    if #pending_ranks == 0 then return false end
    for i = 1, #pending_ranks do
        local retry_at = rank_retry_at[pending_ranks[i]] or 0
        if type(now) ~= "number" or now >= retry_at then
            ST.HUNTER.resolve_guide_icons()   -- the same pass re-points the icons
            return true
        end
    end
    return false
end
```

Two bounds, both needed, each covering the other one's blind spot:

| bound | where | what it stops |
|---|---|---|
| the per-table backoff (5 s) | `resolve_rank` | any single caller (the drill's icon read, a direct `resolve_guide_icons` call) from walking a table in a hot loop |
| the driver's due check | `retry_pending_ranks` | the per-frame gather from re-running the whole resolution pass every frame |

Without them a client that cannot answer would re-walk all fifteen rank tables on
every frame of the guide tick. With them the cost is **one walk per pending table per
5 s window**, and a client that answers at post_init pays **nothing at all** (the
retry set is empty, so the driver returns on its first line).

**The drill shares the guide's verdict.** `practice_shot_spell_id` now reads the same
cached resolution, so the drill's icon read costs no second walk and can never
disagree with the guide.

**One deliberate one-shot: the SoD slot-set swap.** The SoD branch swaps
`ST.HUNTER.guide.slots` to the Era-SoD four-slot set. The shared guide frame is built
from that table at `nextaction_ui.init` and is **never rebuilt**, so a swap after
post_init could not reach the icons. The branch therefore decides **once** (a
`sod_slot_set_decided` flag) and the SoD table is resolved through the cached resolver
like every other table (a client that cannot answer is not a client that refutes the
rune) — but a late answer cannot change the decided slot set. Everything else in the
branch is unchanged.

### 1.2 `classes/warrior.lua` — the Slam cast bar's fallback duration

`get_slam_fallback_duration()` walked the whole Slam rank table **on every Slam cast**
through the plain resolver, and read a `nil` as "no rank". It now reads the class's own
cached, three-valued resolution — the same `resolve_rank` the guide already uses for
the Slam table:

```lua
local function get_slam_fallback_duration()
    slam_current_id = resolve_rank(slam_ids, slam_current_id)
    local id = slam_current_id
    if id then
        local _, _, _, cast_ms = api.GetSpellInfo(id)
        if type(cast_ms) == "number" and cast_ms > 0 then
            return cast_ms / 1000
        end
    end
    return 1.5
end
```

- The **first** cast resolves the rank (one walk); every later cast reads the cache —
  no probe per cast.
- **`absent`** latches the negative (final): no further walk, the reference's 1.5 s
  default applies.
- **`unresolved`** latches nothing: the next cast asks again once the shared 5 s
  backoff has passed, and the rank that answers then reaches the cast-time read.

**One structural change was needed for the cache to be shared:** `local slam_current_id`
was declared in the guide section (line 2538), *below* the cast-bar code, so the cast
bar could not see it. It moved up to the spell-data section next to `hs_current_id` /
`cleave_current_id` (one declaration moved, the guide's own use unchanged). Without
that move the class would have kept **two** caches for one rank table and walked it
twice.

## 2. Pins

### `tests/hunter_state.lua` — new section 25

| Pin | What it proves |
|---|---|
| F4 guide | the class never uses the plain resolver (0 calls) and resolves through the state API; the Steady slot carries the client's rank |
| F4 drill | the drill's icon reads the resolved rank and **shares the guide's verdict** (no second walk) |
| F4 absent | the client is asked; after the retry window the negative is **final** (the resolver is never called again) |
| F4 unresolved | the client is asked; the backoff **holds** the walk (no hot loop per frame); the drill's read inside the window does not walk either; after the backoff the client is asked **again**, the rank resolves, the guide's `steady_known` flips to true and the slot is re-pointed |
| F4 Era | the rank resolves **by id** and the client is **never asked by name** |
| F4 TBC | a client that answers **no id at all** (the name-only client with the `C_Spell` bridge) still resolves the rank — the **name path** decided it — and the client *is* asked by name |

### `tests/warrior_state.lua` — new section 36

| Pin | What it proves |
|---|---|
| F4 slam | the first cast resolves the rank and reads its cast time (2.0 s from the fixture's client); the client is asked **once**; the class never uses the plain resolver; a later cast reads the cached rank (same duration, **no** second walk) |
| F4 slam absent | a refuted rank falls back to the reference's 1.5 s; after the retry window the negative is **final** (never re-walked) |
| F4 slam unresolved | an unanswered rank falls back to 1.5 s; the backoff **holds** the walk; after the backoff the client is asked again and the **late answer reaches the cast-time read** (2.0 s) |
| F4 slam Era | the rank resolves by id and the client is **never asked by name** |
| F4 slam TBC | the rank resolves through the **name path** (the client answers no id) and the client *is* asked by NAME |

### Fixture work (the two suites)

`tests/hunter_state.lua` gained the pieces the pins needed: a **query log**
(`sb.spell_queries`), a **known-spell map** (`opts.known`, answered under the
synthetic `Spell <id>` names), a **restricted client** (`secret_spell_info` — every
spell read comes back as a secret value, so the resolver reports `unresolved` instead
of `absent`; the secret check is scoped to that one marker value), a **name-only TBC
client** (`opts.name_only_client` plus the `C_Spell` id → name bridge, the shape the
compat lane verified on the client source) and the **resolver counters** (the plain
resolver is counted too, so the pin "the class resolves through the state API, not the
plain one" bites). The default fixture's spell data (the Multi-Shot ranks) is
unchanged, so every pre-existing expectation still holds.

`tests/warrior_state.lua` needed one field: `cast_ms` (the cast time the client's
spell data reports, default 0 = "no cast time"), so a pin can observe *which* rank the
cast-time read used.

One **pre-existing pin was updated, not deleted**: the hunter's "drill: absent resolver
hides (never throws)" nilled the *plain* resolver. The class resolves through the
state API now, so the pin nils `api.get_family_spell_id_state` instead (in a fresh
sandbox, so the cached resolution cannot answer it). The intent — the class never
throws when the resolver is unavailable — is unchanged.

Suites: `tests/hunter_state.lua` **1023 checks / 0 failures** · `tests/warrior_state.lua`
**1066 checks / 0 failures**.

## 3. Mutation battery (`/tmp/opencode/mut_resolver_callers.py`, fresh tree copies)

Control: the pristine copy is green on both suites. **13/13 mutants killed** — every
kill is a real pin failure, and every mutant is parse-checked with `luac5.1 -p` before
the suite runs, so a syntax error can never count as a kill:

| Mutant | Killed by |
|---|---|
| M1 hunter: `unresolved` latches false (the exact F4 residual) | "F4 unresolved: the attempt after the backoff asks again" + "the late answer reaches the guide" + "the late answer re-points the guide slot" |
| M2 hunter: the retry backoff removed | "F4 unresolved: the drill's read inside the backoff window does not walk" |
| M3 hunter: the class ignores the state API (plain resolver again) | "F4 guide: the class never uses the plain resolver" + "F4 absent: the negative is final" |
| M4 hunter: `absent` never latches | "F4 absent: the negative is final (never re-walked)" + "the retry backoff holds the walk" |
| M5 hunter: the resolved id is never used | the pre-existing guide pins ("TBC: Kill Command still resolves", "Wrath MM: Chimera is known", …) |
| M6 hunter: the drill walks the rank table again | "F4 drill: the drill shares the guide's verdict (no second walk)" |
| M7 hunter: the per-frame retry driver never runs | "F4 unresolved: the attempt after the backoff asks again" (+2) |
| M8 warrior: the Slam fallback uses the plain resolver again | "F4 slam: the class never uses the plain resolver" (+3) |
| M9 warrior: the Slam fallback walks the rank table on every cast | "F4 slam: a later cast does not walk the rank table again" (+3) |
| M10 warrior: `unresolved` latches false (the exact F4 residual) | "F4 unresolved: the attempt after the backoff asks again" + the §35 class-latch pins |
| M11 warrior: `absent` never latches | "F4 absent: the negative is final" + "F4 slam absent: the negative is final" |
| M12 warrior: the resolved id is never used | "the queued Heroic Strike rank is the cost that gets queried" (+3) |
| M13 hunter: **both** retry bounds removed | "F4 unresolved: the retry backoff holds the walk" + "the drill's read inside the backoff window does not walk" |

**One equivalent mutant, recorded rather than hidden:** removing *only* the driver's
due check (M13 without the inner backoff) does **not** change the observable probe
count, because the inner per-table backoff still bounds the walks. The two bounds are
redundant for the probe count and complementary for the per-frame cost (the inner one
bounds a single caller, the driver's one avoids re-running the whole resolution pass
every frame). Both are kept, and M13 therefore removes **both** to prove the bound is
really there.

## 4. Validation

- `bash tests/run.sh` → **41 steps, 0 failed**; luacheck **2 warnings / 0 errors**
  (the floor: `compat.lua:36` unused `addon_name`, `main.lua:77` `table.pack` — both
  pre-existing, both KEEP-ruled; this lane adds **zero** warnings).
  `luacheck classes/hunter.lua classes/warrior.lua` → 0/0.
- Line endings preserved: both class files stay CRLF (every line), both test files stay
  LF. No trailing whitespace, no tabs, in any of the four files.
- No default-visible change, no new toggle, no user-visible string: on a client that
  answers, the same ids land in the same slots and the same durations drive the same
  widgets. Only the "cannot answer" path changed, and it changed from *permanently
  poisoned* to *retryable*.

## 5. What is NOT proven here

- **In-client**: that a real TBC Anniversary 2.5.6 client reaches the `resolved`
  verdict through the name path. The compat lane owns that half of F4 and recorded the
  open operator check (HU-6: `/run print(GetSpellInfo(29707))` vs
  `/run print(GetSpellInfo("Heroic Strike"))`). This lane's TBC pin proves the class
  *consumes* the name-path verdict; it cannot prove the client produces it.
- **A pre-existing gap this lane did NOT touch** (filed, not fixed): the Slam cast
  bar's fallback reads the rank's cast time through `api.GetSpellInfo(id)` — the
  **id** form. On a TBC client that answers names only, that read finds nothing, so
  the fallback stays at the reference's 1.5 s even when the rank resolved. The
  class-latch lane's `spell_query(name, id)` helper is the name-vs-id answer for the
  *other* reads, but the Slam fallback has no name for the rank (the class resolves
  the localized names separately, in `resolve_slam_names`). Changing it would alter a
  visible value (1.5 s → the client's real cast time on TBC), which is a
  default-visible change and therefore **not** this lane's call. Filed for the
  operator: a follow-up lane may take it, with the name-vs-id read and a pin.
- The hunter's **own** cast-time read in the gather (`api.GetSpellInfo(steady
 _current_id or guide_slot_steady.spell_id)`) is unguarded — a restricted read would
  raise inside the gather, where the guide's caller pcalls it and degrades to "…".
  Pre-existing, unchanged by this lane; noted because the restricted-client fixture
  in `tests/hunter_state.lua` models exactly that condition.
- The retry interval (5 s) is the rogue lane's / class-latch lane's value, not an
  in-client measurement. It only bounds a probe rate on a client that cannot answer;
  it never changes a resolved rank.
- The SoD slot-set swap stays a **one-shot** decision (see §1.1): a client that cannot
  answer at post_init keeps the Era slot set for the session, exactly as before this
  lane. The frames are built once, so a later swap could not reach the icons anyway.

## 6. Files changed

| File | Change |
|---|---|
| `classes/hunter.lua` | the cached three-valued rank resolver + the bounded per-frame retry driver; every one of the ten plain-resolver call sites now goes through it; the SoD slot-set swap became a one-shot decision |
| `classes/warrior.lua` | the Slam cast bar's fallback duration reads the class's cached, three-valued resolution (no walk per cast); `local slam_current_id` moved to the spell-data section so the cast bar and the guide share one cache |
| `tests/hunter_state.lua` | fixture (query log, known-spell map, restricted client, name-only TBC client, resolver counters) + new section 25 + the one updated "absent resolver" pin |
| `tests/warrior_state.lua` | fixture (`cast_ms`) + new section 36 |
