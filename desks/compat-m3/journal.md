# compat-m3 — Journal

## 2026-10-20 — Desk opened
- **Purpose:** close the deep-audit's **M3 (MEDIUM)** — a documentation-vs-code contract
  mismatch in the compat layer. `compat.lua`'s spell-knowledge comment claims a client with
  none of the probes "reports 'unknown' instead of erroring", but `api.is_spell_known`
  returns **`false`** there. Every current caller treats `false` as fail-closed, so the
  behaviour is safe, but the contract is wrong: a caller cannot tell "no probe answered on
  this client" from "the player does not know the spell", and a future row that needs
  unknown-hides has no way through this API.
- **Scope:** `compat.lua`, `tests/smoke.lua` (the compat client-profile probes) and/or
  `tests/secret_guard_state.lua` (whichever owns the compat probes — verified by grep:
  the spell-knowledge probes live in `tests/secret_guard_state.lua` §10 "R7", `smoke.lua`
  owns family detection / spell-id resolution only). Class files, `practice*.lua`,
  `option_tables.lua`, `config_presets.lua`, `main.lua`, `diag.lua`, `hud.lua`, `bars.lua`,
  `run.sh`, TOCs, versions and docs are owned by sibling lanes — read-only here. No git.
- **Next step:** the M3 lane itself — pick the reading that keeps every caller's behaviour
  identical (tri-state `nil` vs. corrected comment), prove it against every caller in the
  tree, and pin the contract so the mismatch cannot be reintroduced silently.

## 2026-10-20 — M3 closed: reading (b) + an additive state accessor
- **Worked on:** took reading **(b)** — the boolean stays binary, the comment now states the
  contract the code implements. Reading (a) (`nil` for "no probe answered") is **not**
  behaviour-neutral: the full census (64 matched lines, 59 consumer lines) found two raw
  consumers that would flip — `classes/rogue.lua:1263` → `rogue_guide.lua:1614`
  (`args.ar_known == false`) and `diag.lua:506` → `diag.lua:482`
  (`type(known) == "boolean"`). Both files belong to sibling lanes, so (a) could not be
  made neutral from inside `compat.lua`. The distinction is instead delivered
  **additively**: `api.is_spell_known_state(spell_id)` → `true,"known"` / `false,"not_known"`
  / `false,"unknown"` (`compat.lua:234`), the same shape as the repo's own
  `api.get_family_spell_id_state` (compat-f4 lane). `api.is_spell_known` (`compat.lua:249`)
  is unchanged and now reads that one implementation. The comment above them
  (`compat.lua:178-202`) states the binary contract, the fail-closed meaning of a `false`
  on a probe-less client, and the per-family truth (C_SpellBook.IsSpellKnown is documented
  on all five target families; the classic global is Blizzard's deprecated shim over it).
- **Current state:** `compat.lua` + `tests/secret_guard_state.lua` (410 checks, was 373);
  full harness **41 steps / 0 failed**; luacheck **2 warnings / 0 errors** (the floor);
  behavioural equivalence against the pre-lane `compat.lua` **150 checks / 0 failed**
  (8 client profiles × 4 ids, `/tmp/opencode/m3_equiv.lua`); mutation proofs **10/10
  killed** (`/tmp/opencode/m3_mut_run.sh`, on copies). Bench artifact:
  `bench/compat_m3_contract_2026-10-20.md`.
- **Open for the operator:** (1) the state accessor is **inert today** — no caller needs it
  *yet*; the brief said "add the tri-state only where a caller actually needs it", so the
  operator rules on keeping the additive accessor or dropping it (HU-15). (2) §10b pins
  three lines in files other lanes own (`classes/rogue.lua:1263`, `rogue_guide.lua:1614`,
  `diag.lua:482`): a rewrite there turns this suite red — that is the intended signal
  (the contract's justification changed), but the owning lane should expect it.
- **Next step:** none for this desk — the M3 contract is closed and pinned. If the
  operator rules HU-15 "drop the accessor", the change is a small deletion of
  `compat.lua:229-245` plus the §10b state pins; nothing else in the lane moves.
- **Note on the harness:** an early full-harness run showed 2 red checks in
  `tests/druid_state.lua` ("the queued Maul is a press too") — parallel-lane crossfire: a
  druid lane rewrote `tests/druid_state.lua` (and `classes/druid.lua`, `druid_guide.lua`)
  mid-run. Re-run after the lane settled: green. The lesson stands — read the failing
  label against the file on disk before believing it.

## 2026-10-20 — [signal:done] M3 closed and pinned
- `desks/compat-m3/.signals/2026-10-20T13-50-31Z-done.json` — the lane is landed: the
  contract comment, the binary boolean and the additive state accessor are in
  `compat.lua`; the pins are in `tests/secret_guard_state.lua` §10 / §10b; the proof is
  in `bench/compat_m3_contract_2026-10-20.md`; harness 41/0, luacheck 2/0, equivalence
  150/0, mutations 10/10.

## 2026-10-20 — [signal:hands-up] HU-15 raised
- `desks/compat-m3/.signals/2026-10-20T13-51-04Z-hands-up.json` + the HU-15 row in
  `hands-up.md` — the operator rules whether the additive, inert
  `api.is_spell_known_state` stays. Not blocking: the lane is green under either ruling.
