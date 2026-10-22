# class-f4-latch — Journal

## 2026-10-19 — Desk opened
- **Purpose:** close the class-side residual of audit finding F4 (`bench/deep_audit_2026-10-19.md`,
  F4 bench artifact `bench/f4_family_spell_id_2026-10-19.md`): the compat lane now returns a
  three-valued verdict — `resolved` / `absent` (final) / `unresolved` (retryable) — but
  `classes/druid.lua` and `classes/warrior.lua` still latch `false` on any nil, so a transient
  "unresolved" (a cold TBC spell book, a restricted read) poisons the rank for the whole session.
- **Scope:** `classes/druid.lua`, `classes/warrior.lua`, `tests/druid_state.lua`,
  `tests/warrior_state.lua` (pins). Read-only elsewhere: `compat.lua` (owned by the compat-f4
  desk), plus `main.lua`, `diag.lua`, `hud.lua`, `bars.lua`, the practice/options/config files,
  the guides, `tests/run.sh`, the TOCs, the versions, README/CHANGELOG/docs — all owned by
  sibling lanes. No git, no lint-config changes.
- **Precedent:** the rogue lane's retry-able latch (`classes/rogue.lua`, `ROGUE_SPELL_RETRY`)
  is the in-tree shape for a retry-able lookup.
- **Next step:** switch both class latches to `api.get_family_spell_id_state`, latch `false`
  only on `absent`, retry on `unresolved`; pin both directions (TBC-name / Era-id) plus the
  absent/unresolved split; prove it with mutation copies on `/tmp/opencode`.

## 2026-10-19 — F4 class side closed: both latches distinguish absent from unresolved
- **Worked on:** rewrote the rank latch in `classes/druid.lua` and `classes/warrior.lua`
  onto `api.get_family_spell_id_state`: `resolved` → the id latches, `absent` → the
  negative latches (final), `unresolved` → **nothing** latches and the next attempt asks
  again. Added a 5 s per-rank-table retry backoff (the rogue lane's `ROGUE_SPELL_RETRY`
  shape) because `resolve_rank` is also called from the **per-frame**
  `gather_guide_inputs` path — an unbounded retry would re-walk the table every frame on
  a client that cannot answer. Pins: `tests/druid_state.lua` §37 and
  `tests/warrior_state.lua` §35 pin the absent direction, the unresolved direction
  (nothing latched → the attempt after the backoff asks again → the rank resolves and
  latches), the Era-id direction (the client is never asked by name) and the TBC-name
  direction (a name-only client that answers no id still resolves the rank — the name
  path decided it). The two fixtures grew a query log, a throwing client and a name-only
  TBC client (with the `C_Spell` id → name bridge).
- **Current state:** harness **41 steps / 0 failed**; luacheck **2 warnings / 0 errors**
  (the floor — `compat.lua:36`, `main.lua:77`; zero new, both class files 0/0); mutation
  battery **10/10 killed** (`/tmp/opencode/mut_class_f4.py`, fresh tree copies, every
  mutant parse-checked with `luac5.1 -p` first so a syntax error cannot count as a kill).
  Bench artifact: `bench/class_f4_latch_2026-10-19.md`.
- **Next step:** orchestrator validates. Two things stay open and are *not* this lane's:
  HU-6 (the operator's in-client check on TBC Anniversary — which query form the native
  `GetSpellInfo` answers) still decides whether the name path reads correctly in-client;
  and the plain-resolver callers that are **not** latches (`classes/hunter.lua`'s twelve
  call sites, `classes/warrior.lua`'s `get_slam_fallback_duration`) still run on the
  two-valued contract — converting them is a separate call, not F4's residual.
- **Note for the orchestrator:** the central lane row belongs to the orchestrator (it owns
  the session id); this desk did not edit `desks/journal.md`.

## 2026-10-19 — [signal:done] F4 class side landed and proven
- **Done:** both class latches distinguish `absent` from `unresolved`; both directions
  (TBC-name / Era-id) pinned; harness 41/0; luacheck 2/0 (the floor, zero new); 10/10
  mutants killed. Bench artifact: `bench/class_f4_latch_2026-10-19.md`; signal:
  `desks/class-f4-latch/.signals/2026-10-19T20-20-00Z-done.json`.
- **Open for the operator (not blocking):** HU-6 — the in-client TBC Anniversary check
  still decides whether the native `GetSpellInfo` answers a name or an id. This lane's
  pin proves the class *consumes* the name-path verdict; it cannot prove the client
  produces it.


