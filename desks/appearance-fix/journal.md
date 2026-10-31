# appearance-fix — Journal

## 2026-10-28 — Desk opened (dispatch: bench/briefs/brief_appearance-fix_2026-10-28.md)
- **Purpose:** fix the proven F2 defect — `ST.migrate_appearance_defaults` (config.lua) can
  never run on a live profile because config.lua:162 reads the migration flag straight off
  the AceDB profile root, whose `'**'` defaults metatable CREATES and rawsets a
  defaults-filled table on any missing-key read (Libs/AceDB-3.0/AceDB-3.0.lua:88-107). The
  truthy read returns 0 forever, so the 2026-10-25 opaque-backdrop order never reached a
  saved profile.
- **Write scope (exact):** `config.lua`, `tests/appearance_defaults_state.lua`,
  `tests/bars_state.lua` — ONLY the accepted-known-defect pin at §12e (replaced with the
  positive assertion). No `tests/options_load_state.lua`, no `bars.lua`, no `Libs/`, no
  TOCs, no docs, no version bump (stays 2.1.3), no git.

## 2026-10-28 — Reconcile (orchestrator)
- Code landed by the lane: config.lua (rawget flag + rawget class row + rawset marker, plus
  the `== true` guard so a created '**' table is not accepted as "done"); tests/
  appearance_defaults_state.lua (real '**'-shaped AceDB profile fixture, sections 1-8).
- §12e pin in tests/bars_state.lua re-cut from accepted-defect to positive assertion;
  passes on the real booted AceDB profile.
- Verification: `bash tests/run.sh` = 54 steps, 1 failed — the single failure is the
  placement pins ("a non-CENTER anchor is a user layout (kept)", "a scaled row is a user
  layout (kept)") which are NOT in this desk's scope: they encode the old "a drag wins"
  rule that the operator's new ruling ("it should stay with the rest, aka the new way")
  supersedes. Those pins are the ranged-forced lane's job (R4), not this one.
  appearance_defaults_state.lua: PASS. luacheck 2 warnings / 0 errors in 97 files.
- Report filed: bench/appearance_fix_2026-10-28.md.
- Desk closed (code + ceremony complete). Remaining release-blocker: ranged-forced lane
  (dispatched next) re-cuts the placement pins.

## 2026-10-28 — Lane complete: F2 fixed and proven (offline); corrects the interim reconcile
- **Worked on:** the F2 repo-wide fix in the lane's write scope. `config.lua` now reads the
  flag `rawget(profile, FLAG) == true` (:177), reads class rows `rawget(profile, token)`
  (:185) and writes the marker `rawset(profile, FLAG, true)` (:201); `== true` is deliberate
  because a table at that key is exactly what the defective read created and the defective
  code could never reach its own write - a truthy check would strand every polluted profile
  at 0.85 (the same silent failure in a new shape). `tests/appearance_defaults_state.lua`
  loads the SHIPPED Libs/AceDB-3.0 and runs section 8 (:500-664) against a real
  `AceDB:New(...)` profile: fixture shape, no-junk key counts, exact-0.85/preset/ near-miss
  semantics, reload path, second-run 0, polluted marker, absent class row. 145 -> 183 checks.
  `tests/bars_state.lua` §12e (:3713-3739) re-cut from ACCEPTED-KNOWN-DEFECT to the positive
  assertion.
- **Corrections to the interim "Reconcile (orchestrator)" entry above:** (a)
  `preset_owns_background_color`'s `hand.theme_preset` was NOT changed to rawget and does not
  need it - the probe proved hand tables carry no `'**'` metatable (bar_defaults has no
  `'*'`/`'**'`), so the leaf read cannot create anything; (b) the gate is now **54 steps, 0
  failed**, luacheck 2 warnings / 0 errors in 97 files, on a hash-bracketed settled tree -
  the "1 failed" was the concurrent `ranged-forced` lane's stale placement pins; (c) the
  offline proof is against the SHIPPED AceDB library, not a synthetic '**' fixture.
- **Current state:** F2.1-F2.5 done or filed. Mutation proofs M1/M2/M3/M4/M6 killed, M5
  (rawset -> plain assignment) survives by design and is stated. Sweep: one latent
  out-of-scope trap filed (`widgets.lua:44-46` sound_channel, currently unreachable on the
  paladin-only panel); every other candidate classified safe. Report appended (final section)
  to `bench/appearance_fix_2026-10-28.md`. Nothing committed; version stays 2.1.3.
- **Next step:** the four in-client checks in report §9 (raise on the operator's own saved
  profile, the marker is `true` not a table in SavedVariables, visible backdrop per family,
  `/reload` + restart). Follow-up for another lane: `widgets.lua` sound-preview channel reads
  (rawget both keys, or fall back to "Master" on a non-string). The orchestrator should
  re-verify §12e survived the `ranged-forced` lane's final `tests/bars_state.lua` write - it
  was present and passing at this lane's close (bars_state 1230 checks, PASS).
