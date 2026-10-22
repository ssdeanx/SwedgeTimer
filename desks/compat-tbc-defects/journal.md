# compat-tbc-defects — Desk Journal

## 2026-10-21 — Desk opened
- **Purpose:** close the two compat.lua defects the operator hit in-client on TBC Anniversary
  (2026-10-21): the protected interaction-distance call and the deprecated-shim spell-knowledge
  throw on a spell NAME.
- **Scope:** `compat.lua` (owner) and the NEW `tests/spell_known_state.lua` (owner). The parallel
  lane owns `main.lua`, `hunter_ui.lua`, `Libs/LibRangeCheck-2.0/**`, `tests/range_source_state.lua`,
  `tests/lrc_guard_state.lua`, `tests/main_init_state.lua`, `tests/hunter_state.lua`, and `tests/run.sh`.
- **Contract:** `bench/briefs/brief_compat-tbc-defects_2026-10-21.md` (read in full before opening
  this desk).
- **Next step:** read the compat sections (targeted greps only), implement both fixes, add the
  suite, prove with `lua5.1 tests/spell_known_state.lua` + compat-touching suites + luacheck,
  run mutation proofs on a `/tmp/opencode` copy, file the `tests/run.sh` line.

## 2026-10-21 — Both defects fixed, offline proofs complete

- **Worked on:** `compat.lua` defect 1 (removed `api.CheckInteractDistance` + its `rawget`, kept
  the WHY comment at 988-997 naming `api.UnitDistance` as the only distance source) and defect 2
  (`spell_known_name_id` 241-250, `api.is_spell_known_state` 261-292, `api.is_spell_known`
  294-297: token guard, pcall on every probe, lazy one-time name→id retry only on a throwing
  probe, secret answer skipped, tri-state). New `tests/spell_known_state.lua` loads the real
  compat over a TBC deprecated-shim sandbox.
- **Current state:** suite 244 checks / 0 failures. Compat-touching suites green: smoke 232/0,
  shaman 1064, warrior 2046, rogue 1114, paladin 1234, hud 817, class_activation 70,
  weave_range 149, neutral_actions 7026, lrc 141. `luacheck .` 2 warnings / 0 errors in 87
  files; compat.lua 1 standing warning; new suite 0. Six mutation proofs (no pcall, no id
  retry, no secret guard, numeric resolution, wrapper reintroduced, no token guard) all fail
  their owning checks on `/tmp/opencode/mut`; revert-to-fail with the pre-fix compat exits 1
  with the client-shaped shim error. Harness snapshot 22:14:57Z: 44 steps / 5 failed — all
  five attributed away from this lane (hunter_state + bars_state + main_init_state reproduce
  identically with the pre-fix compat in `/tmp/opencode/isolate2`; secret_guard_state pins the
  removed wrapper; toc_check waits on the filed run.sh line). Deliverable:
  `bench/compat_tbc_defects_2026-10-21.md`.
- **Next step:** orchestrator adds the run.sh line after line 91 and applies the filed
  `secret_guard_state.lua` replacement (lines 90, 203, 1412-1415). Operator in-client re-test on
  TBC Anniversary (hunter post_init + range helper) remains the only real confirmation.

## 2026-10-21 — Orchestrator citations folded into the comments/bench

- **Worked on:** the defect-1 comment now carries the orchestrator's `classic_anniversary`
  provenance: the only Blizzard caller is secure popup code
  (`UnitPopupSharedUtils.lua:194`); the generated API doc
  (`PlayerScriptDocumentation.lua:101`) has NO protection marker, so the in-client
  `ADDON_ACTION_BLOCKED` log — not the doc — is the authority; and the addon-callable source is
  `UnitDistanceSquared` from insecure unit-frame Lua (`CompactUnitFrame.lua:1069`), trusted only
  when `checkedDistance` is true. The literal identifier stays out of `compat.lua`, so the
  suite's strict scan keeps its teeth; the bench names it in full.
- **Current state:** suite now **251 checks / 0 failures** (7 new citation pins). A 7th mutation
  (strip `UnitPopupSharedUtils.lua:194`) fails its pin; M1-M6 unchanged and all still fail.
  `luacheck` still 2 warnings / 0 errors in 87 files; grep for the identifier in compat.lua
  still exits 1.
- **Next step:** unchanged — run.sh line + `secret_guard_state.lua` fix, then the operator's
  in-client re-test.
