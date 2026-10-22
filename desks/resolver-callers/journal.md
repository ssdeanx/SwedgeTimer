# resolver-callers — Journal

## 2026-10-19 — Desk opened
- **Purpose:** close the last plain-resolver callers of the F4 family resolver: the
  callers still run on the two-valued contract, where a transient "unresolved" (the
  client could not answer) is indistinguishable from "absent" (the client's own spell
  data refuted the spell). Targets: `classes/hunter.lua` (the rank-table resolution
  sites for the guide/HUD icons) and `classes/warrior.lua:1553`
  (`get_slam_fallback_duration`, one rank walk per Slam cast).
- **Sources read first:** `bench/f4_family_spell_id_2026-10-19.md` (the compat lane's
  three-valued API: `api.get_family_spell_id_state(id_table)` → `id, state ∈
  {resolved, absent, unresolved}`) and `bench/class_f4_latch_2026-10-19.md` (the
  established pattern: `absent` is the ONLY latch for a negative, `unresolved` latches
  nothing, plus a 5 s per-rank-table retry backoff because the resolver is read from a
  per-frame path). `bench/lessons.md` (TBC-name / Era-id rule).
- **Scope:** `classes/hunter.lua`, `classes/warrior.lua`, `tests/hunter_state.lua`,
  `tests/warrior_state.lua` (pins only). Read-only elsewhere. `compat.lua` is settled
  (the compat-f4 desk owns it). No git, no lint-config change, no TOC/version/doc edits.
- **Next step:** read the hunter/warrior fixtures, implement the cached three-valued
  resolution in both class files, pin absent/unresolved + TBC-name/Era-id both ways,
  prove with mutation copies on `/tmp/opencode`.

## 2026-10-19 — F4 plain-resolver callers closed: the hunter's rank resolution and the warrior's Slam fallback
- **Worked on:** `classes/hunter.lua` gained the class's own cached, three-valued rank
  resolver (`resolve_rank` → `api.get_family_spell_id_state`): `resolved` latches the
  id, `absent` latches the negative (final), `unresolved` latches nothing and the
  table joins a retry set. All **ten** plain-resolver call expressions (fifteen rank
  tables — the class-latch note said "twelve"; the exact count is ten calls) now go
  through it, and the per-frame gather (`gather_guide_inputs`) drives a bounded retry
  (a 5 s per-table backoff inside the resolver + the driver's own due check), so a
  client that cannot answer is asked again later instead of staying hidden for the
  session. The drill's shot icons share the guide's verdict (no second walk). The SoD
  slot-set swap became a **one-shot** decision (the guide frame is built once from
  `guide.slots` and never rebuilt, so a late swap could not reach the icons).
  `classes/warrior.lua`'s `get_slam_fallback_duration` now reads the class's cached
  resolution instead of walking the whole Slam rank table on every cast; the
  `local slam_current_id` declaration moved up to the spell-data section so the cast
  bar and the guide share ONE cache (without that move the class would have kept two
  caches for one table).
- **Pins:** `tests/hunter_state.lua` §25 and `tests/warrior_state.lua` §36 pin the
  absent direction (final), the unresolved direction (nothing latched → the attempt
  after the backoff asks again → the rank resolves and reaches the consumer), the
  probe bound (the backoff holds the walk; the drill's read inside the window does
  not walk either), and both resolution directions (Era resolves by id and is never
  asked by name; a name-only TBC client resolves through the NAME path and is asked
  by name). The hunter fixture grew a query log, a known-spell map, a restricted
  ("secret") client, a name-only TBC client with the `C_Spell` bridge and the
  resolver counters; the warrior fixture grew `cast_ms` so a pin can see WHICH rank
  the cast-time read used. One pre-existing hunter pin was updated (not deleted): the
  "absent resolver hides" pin now nils the state API instead of the plain one.
- **Current state:** harness **41 steps / 0 failed**; luacheck **2 warnings / 0 errors**
  (the floor — `compat.lua:36`, `main.lua:77`; zero new, both class files 0/0);
  mutation battery **13/13 killed** (`/tmp/opencode/mut_resolver_callers.py`, fresh
  tree copies, every mutant parse-checked with `luac5.1 -p` first). Suites:
  hunter_state 1023/0, warrior_state 1066/0. Bench artifact:
  `bench/resolver_callers_2026-10-19.md`.
- **Next step:** orchestrator validates. Two things are open and are **not** this
  lane's: HU-6 (the operator's in-client TBC Anniversary check — which query form the
  native `GetSpellInfo` answers) still decides whether the name path reads correctly
  in-client; and the **Slam cast bar's cast-time read still uses the id form**
  (`api.GetSpellInfo(id)`), so on a name-only TBC client the fallback stays at the
  reference's 1.5 s even when the rank resolved. Fixing that is a default-visible
  change (1.5 s → the client's real cast time) and needs the operator's call, so it
  is filed in the bench artifact rather than taken here.
- **Note for the orchestrator:** the central lane row belongs to the orchestrator (it
  owns the session id); this desk did not edit `desks/journal.md`.

## 2026-10-19 — [signal:done] F4 plain-resolver callers landed and proven
- **Done:** the hunter's ten plain-resolver call sites and the warrior's Slam cast
  fallback now distinguish `absent` from `unresolved`; the probes stay bounded; both
  directions (TBC-name / Era-id) pinned; harness 41/0; luacheck 2/0 (the floor, zero
  new); 13/13 mutants killed. Bench artifact:
  `bench/resolver_callers_2026-10-19.md`; signal:
  `desks/resolver-callers/.signals/2026-10-19T21-05-00Z-done.json`.
- **Open for the operator (not blocking):** HU-6 (the in-client TBC Anniversary
  check) and the Slam cast bar's id-form cast-time read (a default-visible change,
  filed in the bench artifact §5).

