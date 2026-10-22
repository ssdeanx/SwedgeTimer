# compat-f4 — Journal

## 2026-10-19 — Desk opened
- **Purpose:** fix audit finding F4 (`bench/deep_audit_2026-10-19.md`): `compat.get_family_spell_id`
  walked a rank table with numeric ids, which the TBC Anniversary client does not answer —
  so a TBC rank never resolved and callers latched `false` forever.
- **Scope:** `compat.lua`, `tests/smoke.lua`, `tests/secret_guard_state.lua`. Class files,
  `main.lua`, `diag.lua`, `hud.lua`, `bars.lua`, options/config, `run.sh`, TOCs, versions
  and docs are owned by sibling lanes — read-only here.
- **Next step:** the F4 lane itself (session `ses_ea97ceaa6ffeWHYdLP9XZzl0s9`) — see the
  entry below.

## 2026-10-19 — F4 fixed: TBC name path + "unresolved" is not "absent"
- **Worked on:** ran the cross-client truth pass the audit owed (read-only `git show` on
  `classic_era` / `classic_anniversary` / `classic_titan` / `origin/forever` / `live`),
  then rewrote the "Per-family spell data helpers" section of `compat.lua`: the rank walk
  now queries the client through `api.get_spell_query(name, id)` (name on TBC, id
  elsewhere), the name for a candidate id comes from the client's own spell data (the
  native global's id form, then the `C_Spell` namespace — `SpellDocumentation.lua:190-197`,
  identical on all five branches), and a new `api.get_family_spell_id_state` returns
  `id, state ∈ {resolved, absent, unresolved}` so "could not answer" stops looking like
  "not here".
- **Current state:** `compat.lua` + `tests/smoke.lua` (206 checks) + `tests/secret_guard_state.lua`
  (373 checks) green; `bash tests/run.sh` 40 steps / 0 failed; luacheck 2 warnings / 0
  errors (the floor, zero new); 11/11 mutations killed on `/tmp/opencode` copies
  (`/tmp/opencode/mut_f4.py`). Bench artifact: `bench/f4_family_spell_id_2026-10-19.md`.
- **Open for the operator / the class-file lane:** the operator's "TBC resolves by NAME"
  rule and the client source disagree about `GetSpellInfo` specifically (Blizzard's own
  `Blizzard_ObjectAPI/Classic/Spell.lua:39` calls the global with an id). The fix works
  under both readings and overrides neither. Second residual: `classes/druid.lua:94` and
  `classes/warrior.lua:369` still latch `false` on a nil result — they should switch to
  the state API (`unresolved` → retry, `absent` → latch false); the rogue lane's
  retry-able latch (`classes/rogue.lua:203-224`) is the precedent. Both files are out of
  this lane's scope.
- **Next step:** orchestrator validates; if the class-file lane wants the latch change,
  it picks up `api.get_family_spell_id_state` and the rogue-style retry. In-client check
  still owed on TBC Anniversary 2.5.6: which query form the native global answers.

## 2026-10-19 — [signal:done] F4 landed; [signal:hands-up] HU-6 raised
- **Done:** F4 fixed and proven — `bench/f4_family_spell_id_2026-10-19.md`, harness
  40/0, luacheck 2/0, 11/11 mutations killed.
- **Hands-up (HU-6):** the operator's TBC-name rule vs the shipped FrameXML (which calls
  the native `GetSpellInfo` with an id). Not blocking — the resolver works under either
  reading — but the answer decides whether the other lanes' landed name-vs-id
  conversions read correctly on TBC. One in-client check closes it:
  `/run print(GetSpellInfo(29707))` and `/run print(GetSpellInfo("Heroic Strike"))` on
  TBC Anniversary 2.5.6.
- **Next step:** operator rules HU-6; the class-file lane (druid/warrior latches) picks
  up `api.get_family_spell_id_state`.
