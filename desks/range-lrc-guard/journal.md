# range-lrc-guard — Journal

## 2026-10-21 — Desk opened
- **Purpose:** ship the range-checker fix for the `ADDON_ACTION_BLOCKED` report
  (Classic Era 1.15.9, 2026-10-21): stop the vendored LibRangeCheck-2.0 item
  checker from calling the client-blocked `IsItemInRange`, and keep the
  melee/ranged ladder answering via the interact-distance bands when the
  spell-range API cannot answer. R1 + R2 only; R3 (the `C_Spell.IsSpellInRange`
  modern path) is DEFERRED by operator decision.
- **Scope:** `Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua`
  and `tests/lrc_guard_state.lua` ONLY. No main.lua / compat.lua / TOC /
  run.sh edits — anything needed elsewhere is filed on the bench.
- **Contract:** `bench/briefs/brief_range-lrc-guard_2026-10-21.md`.
- **Next step:** read the lib + the existing suite, implement R1/R2 with dated
  minimal patches, extend the suite (static pins + modern/legacy execution
  proofs), run mutation proofs on a `/tmp/opencode` copy (excluding Media/,
  docs/, .git), then write `bench/range_lrc_guard_2026-10-21.md`.

## 2026-10-21 — R1+R2 landed (offline-proven)

- **Worked on:** the vendored `Libs/LibRangeCheck-2.0/.../LibRangeCheck-2.0.lua`
  range fix. Two probes at :441 (`modernItemRange` = `C_Item.IsItemInRange`
  exists) and :447 (`spellRangeAvailable` = legacy `IsSpellInRange` exists), and
  three guards: item list suppressed at :596, spell list suppressed at :610 (so
  the existing empty-list interact fallback installs the 8/28 bands), item
  `minRangeCheck` suppressed at :803. No `main.lua`/`compat.lua`/TOC edits.
- **Tests:** `tests/lrc_guard_state.lua` 59 → 129 checks; new static pins (exact
  counts), a MODERN-profile execution block (item spy must stay at 0 calls,
  harm list exactly `interact:4`/`interact:3`, `GetHarmMaxChecker(30|35)` → 28,
  `GetHarmMinChecker(2)` → 8, `GetRange` numbers, Tauren 25/6), a LEGACY-profile
  block (exact 25 item checkers, same order/answers, legacy global still called)
  and a HYBRID guard-isolation block for the `HarmItems[15]` clause.
  `lua5.1 tests/lrc_guard_state.lua` PASS 129; `bash tests/run.sh` 43/0;
  luacheck 2/0 (85 files, the KEEP floor).
- **Mutations:** 5/5 killed on `/tmp/opencode/range-lrc-guard-mut/tree` copy
  (M1 item list, M2 spell list, M3 init item minRangeCheck, M5 guard over-applied
  to a legacy client, M6 spell flag always true).
- **Decisions:** an extra `or not spellRangeAvailable` term on the interact
  fallback and a `minRangeCheck` spell guard were drafted then REMOVED — both
  untestable (unreachable given the other guards), and the first would coarsen a
  hypothetical legacy-item ladder. Suite pre-existing IsSpellInRange bite now
  carries the R2 mutation in its setup (documented in the suite).
- **Current state:** offline green, bench report written
  (`bench/range_lrc_guard_2026-10-21.md`). NOT in-client verified.
- **Next step:** orchestrator deploys the changed lib to the client and the
  operator confirms on Classic Era: no ADDON_ACTION_BLOCKED, range string shows
  `0 - 8` / `8 - 28` / `28 - N/A`. R3 (`C_Spell.IsSpellInRange`) stays DEFERRED
  until the operator runs the probe in the bench report §3.

## 2026-10-21 — [signal:done] R1+R2 landed, offline-proven

- Bench: `bench/range_lrc_guard_2026-10-21.md`. Signal:
  `desks/range-lrc-guard/.signals/2026-10-21T131122Z_done.json`.
- Suite 129 checks PASS; harness 43 steps / 0 failed; luacheck 2/0 (85 files);
  5/5 mutations killed on the `/tmp/opencode` copy.
- Owed: in-client confirmation on Classic Era + the R3 probe command.

## 2026-10-21 — R7 follow-up: uniform ladder on all five families

- **Why:** the R2 guard keyed on the legacy `IsSpellInRange` global's binary presence,
  which FrameXML cannot disprove on the three classic branches (FU-2 in
  `bench/range_api_matrix_2026-10-21.md`). If the binary global exists there, the legacy
  index/bookType spell checker would be built — family-dependent behaviour.
- **What changed:** `LibRangeCheck-2.0.lua:448-454` adds
  `local modernSpellRange = (C_Spell and C_Spell.IsSpellInRange) ~= nil`, and the spell
  list guard at `:615-619` is now
  `if spellList and spellRangeAvailable and not modernSpellRange then`. Since
  `C_Spell.IsSpellInRange` ships on all five branches (docs + Blizzard callsites), the
  spell list is now never built on ANY shipped family — the ladder is the interact bands
  everywhere (8/28; Tauren 6/25; Scourge 7/27), zero client range calls, and FU-2 can no
  longer change the behaviour. The ancient-client path (no modern API) still builds its
  legacy spell checker.
- **Tests:** suite 129 → 170 checks. New static pins for the probe and the guard; new §9
  Era/FU-2 execution profile (legacy global present AND modern API present) proving the
  spell list is not built and neither spell API is ever called; §7 legacy profile made
  faithful (no `C_Item`, **no `C_Spell`**, legacy `_G.GetSpellInfo`) and now proves the
  ancient spell path is still built and called. Harness 43/0; luacheck 2/0 (85 files).
- **Mutations:** 7/7 killed on the `/tmp/opencode` copy — the five from the first landing
  plus M7 (R7 guard removed → the legacy spell checker is built and called on the
  Era/FU-2 profile) and M8 (`modernSpellRange` forced true → the ancient client loses its
  spell path).
- **Current state:** offline green. Bench report appended with section "FOLLOW-UP
  (2026-10-21) — R7" (per-family table, diff lines, mutation table).
- **Next step:** unchanged: operator in-client confirmation on Classic Era (no
  `ADDON_ACTION_BLOCKED`, numbers in the range string); R3 stays an OPEN follow-up
  pending the FU-1 probe. Accepted coarsening stands: 8-yd melee / 28-yd ranged on every
  family.


