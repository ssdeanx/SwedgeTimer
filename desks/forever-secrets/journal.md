# forever-secrets — Journal

## 2026-11-05 — Desk opened

- **Purpose:** implement the WoW Forever (Camelot 1.60.1 / Interface 16001) restricted-read
  (secret value) compat paths: a cooldown read that no longer collapses to "ready" when the
  client hides `SpellCooldownInfo.startTime`/`duration`, and an aura read that no longer
  lets `C_UnitAuras.GetAuraDataByIndex` raise (the BugSack error) on a secret row.
- **Scope (exact):** `compat.lua`, NEW `tests/forever_secret_compat_state.lua`, the one-line
  registration in `tests/run.sh`, this desk journal + done signal. `classes/*.lua`,
  `hud.lua`, `nextaction_ui.lua`, `forever_guide.lua`, TOCs and `main.lua` are off-limits.
- **Priors read:** central ledger `desks/journal.md` (status/decisions + standing desk
  rules), `bench/lessons.md` not re-read for this narrow lane; the dispatch carried the
  origin/forever API facts (so no git was run — standing no-git rule kept).
- **Next step:** read the exact regions of `compat.lua` before editing; implement A (aura
  precheck + pcall), B (all-return secret check + duration-object fallback), C (fifth
  `restricted` return); then the suite and mutation proofs.

## 2026-11-05 — A/B/C landed; suite + mutations green

- **Worked on:**
  - **A — `api.UnitAura`, `C_UnitAuras` branch only** (`compat.lua`): new
    `aura_index_is_secret(unit, index, filter)` resolves `C_Secrets` via
    `rawget(_G, "C_Secrets")`, calls `ShouldUnitAuraIndexBeSecret` through `pcall` when it is
    a function, and skips the row **only** on an exact `true`. `GetAuraDataByIndex` is now
    `pcall`-wrapped (error -> absent). The existing whole-entry `aura_entry_is_secret` guard
    is kept. The classic `if UnitAura` branch is untouched: no precheck, no pcall, all ten
    returns identical.
  - **B — `raw_query_spell_cooldown`** (`compat.lua`): all four classic-global returns are
    secret-checked before any use (`spell_cooldown_values_are_secret`), so a secret duration
    never reaches the `duration == 0` comparison; the `C_Spell.GetSpellCooldown` info table is
    checked on all four fields too. On a restricted read **and** `st.is_mainline`, the new
    `cooldown_duration_fallback(token)` calls `C_Spell.GetSpellCooldownDuration` via `pcall`,
    requires `HasSecretValues()` to be callable and to return **exactly `false`**, reads
    `GetRemainingDuration`/`GetTotalDuration`/`GetStartTime` through `pcall`, requires all
    three to be finite numbers and `total > 0`, then returns
    `(now - (total - remaining), total, 1, 1)` on the `api.get_time()` clock. Anything else
    keeps the degraded zeros and sets the restricted flag. The fallback is gated on
    `st.is_mainline`, so Era/TBC/Wrath can never reach it (no secrets exist there anyway).
  - **C — `api.GetSpellCooldown`**: same four values in the same order, plus a fifth
    `restricted` that is `true` only when a restricted read was hit and no readable source
    (primary, `fallback_id`, or the duration object) produced a duration; otherwise `nil`.
  - **Tests:** NEW `tests/forever_secret_compat_state.lua` (114 checks) with a throwaway
    client sandbox (`env._G = env`, `issecretvalue` sentinels, `UnitAura` absent,
    `C_UnitAuras`, `C_Secrets`, `C_Spell.GetSpellCooldown`/`IsSpellUsable`/
    `GetSpellCooldownDuration`, `LuaDurationObject` stub). Registered as run.sh step at
    `tests/run.sh:103`, next to the other compat suites.
- **Current state (verified in-tree, 2026-11-05):**
  - `lua5.1 tests/forever_secret_compat_state.lua` -> `114 checks, 0 failed`, exit 0.
  - `luacheck compat.lua tests/forever_secret_compat_state.lua` -> `0 warnings / 0 errors`.
  - Whole-tree luacheck floor unchanged: `2 warnings / 0 errors in 100 files` (both
    pre-existing KEEP-ruled, not in my files).
  - Adjacent compat suites re-run green (not the whole harness, per the brief):
    `secret_guard_state` 433, `spell_query_family_state` 76, `spell_known_state` 251,
    `engine_matrix_state` 101, `range_source_state` 148 checks — all exit 0.
  - Line endings LF preserved in all three touched files; no trailing whitespace; run.sh
    passes `bash -n`.
- **Mutation proofs (14/14 killed, isolated copy `/tmp/opencode/st-mut`, pristine restore
  after each; `lua5.1 tests/forever_secret_compat_state.lua` in the copy):**
  - `M1_aura_precheck_ignored` (early `return false`) -> exit 1, 3 fails.
  - `M2_precheck_truthiness` (`secret == true` -> `secret and true`) -> exit 1, 2 fails.
  - `M3_aura_read_unwrapped` (drop the pcall) -> exit 1, 2 fails (raise propagates).
  - `M4_aura_guard_dropped` (skip whole-entry secret guard) -> exit 1, 1 fail.
  - `M5_classic_aura_prechecked` (precheck added to the classic branch) -> exit 1, 1 fail.
  - `M6_classic_s_only` (revert to checking only `s`) -> exit 1, 15 fails.
  - `M7_no_duration_fallback` (`if false and restricted...`) -> exit 1, 7 fails.
  - `M8_has_secret_truthiness` (`secret ~= false` -> `not secret`) -> exit 1, 7 fails.
  - `M9_no_family_gate` (drop `st.is_mainline`) -> exit 1, 3 fails.
  - `M10_no_restricted_fifth` -> exit 1, 18 fails.
  - `M11_wrong_start_formula` (`now - total`) -> exit 1, 1 fail (got 88, want 91).
  - `M12_no_finite_check` -> exit 1, 4 fails (inf object returns a duration).
  - `M13_no_object_start` (skip `GetStartTime`) -> exit 1, 2 fails.
  - `M14_info_start_only` (check only `info.startTime`) -> exit 1, 2 fails (secret duration
    leaked as `duration=900002`).
  - Restore re-run: `114 checks, 0 failed`, exit 0.
- **UNVERIFIED / handoff:**
  - In-client behaviour on Forever combat is UNVERIFIED offline: the real
    `LuaDurationObject` method surface, the exact `HasSecretValues()` return, and whether
    `GetSpellCooldownDuration` is callable for every spell token can only be proven in the
    client. The suite pins the documented contract with stubs, not the shipped binary.
  - **No consumer reads the fifth return yet** (out of scope: `hud.lua`,
    `nextaction_ui.lua`, `forever_guide.lua`, `classes/*`). Consumers that unpack only the
    four values still render the degraded `0,0,0,0` as "ready" in restricted combat. The
    follow-up lane should read `restricted` and render unknown, not ready.
  - `C_Secrets.HasSecretRestrictions` is stubbed in the suite but deliberately not used by
    `compat.lua`: the per-index probe is the specified gate, and a blanket restriction is not
    evidence that a specific row is secret.
- **Next step:** orchestrator runs the full harness (step count grows by one) and closes the
  consumer lane above; operator in-client check: enter combat on Forever with the HUD +
  guide open, confirm no BugSack aura error and that cooldown icons behave (real numbers or
  an explicit unknown state, never "ready" while restricted).

## 2026-11-05 — [signal:done] forever-secrets done

- `compat.lua` (A aura precheck+pcall, B all-return secret check + Mainline-only duration
  fallback, C fifth `restricted` return) + `tests/forever_secret_compat_state.lua` (114
  checks) + `tests/run.sh:103`; 14/14 mutations killed; adjacent compat suites green.
