# secret-core-fix — Journal

## 2026-11-06 — Desk opened: secret-value CORE fixes (SEC-1/2/3/4/7/11 + shared helpers)

- **Purpose:** take the secret/restricted-value core lane from the two 2026-11-06 audits:
  stop raw secret comparisons (UnitGUID / UnitIsUnit / UnitCreatureType), pass the ToT
  secret boolean through the sanctioned `SetAlphaFromBoolean` sink, remove the
  `hunter_ui` aura-scan breaks, harden the classic `UnitAura` compat branch and the
  combat-rating wrappers, fix the Forever Hunter's Mark dead unknown branch, and add the
  shared helpers the guide fix needs (`get_cooldown_remaining`,
  `spell_aura_may_be_secret`, `power_may_be_secret`).
- **Scope (write):** `compat.lua`, `hunter_ui.lua`, `classes/hunter.lua`,
  `classes/druid.lua`, `forever_guide.lua` (ONLY the UnitCreatureType guard + Hunter's
  Mark branch), `tests/secret_guard_state.lua`, `tests/hunter_state.lua`,
  `tests/druid_state.lua`, `tests/forever_guide_state.lua`, `desks/secret-core-fix/**`,
  `bench/secret_core_fix_2026-11-06.md`. NOT mine: other class files, hud.lua,
  power_bar.lua/bars.lua/main.lua/swing_source.lua/weave_range.lua, TOCs/docs/run.sh.
  No git, no version fields.
- **Priors read:** `bench/secret_api_matrix_2026-11-06.md` (SEC-1..4/7/11 + pass-through
  sink matrix), `bench/secret_consumers_audit_2026-11-06.md` (H3/H5/H6/M1/M6 + verified
  clean), `desks/journal.md` 2026-11-06 secret wave (fix order + lane split).
- **Lane skills:** bench-read, desk-open, desk-journal, signal-write (loaded earlier in
  this session; all present).
- **Baseline:** tree 2.1.8; `bash tests/run.sh` 57/0; luacheck 2/0 (Lead-verified).
- **Worked on:** (filled in below).
- **Current state:** in progress.

## 2026-11-06 — Worked on (final state)

- **SEC-1/H6:** `classes/hunter.lua` queue tint now routes target identity through
  `api.UnitGUID` (nil-on-secret); an unknown identity keeps the tint (cycle-end backstop
  clears it), a readable identity only clears against a readable baseline, and the store
  side never baselines an opaque value. `classes/druid.lua` TTD sampler uses
  `api.UnitGUID` and drops the baseline on nil (no cross-identity diff).
- **SEC-2/M1:** new `compat.api.UnitIsUnit` returns `(readable_bool, false)` /
  `(opaque_bool, true)` / `(nil,false)`; `ST.HUNTER.get_target_warning` returns the
  tri-state; `hunter_ui.update_target_warning` passes a restricted boolean through
  `SetAlphaFromBoolean(secret, 1, 0)` (frame shown, no text/colour branch), hides with a
  one-time notice when the sink is absent, and keeps the readable path byte-identical.
  Legacy 1/0 spellings preserved.
- **SEC-3/M6:** new `compat.api.UnitCreatureType` (pcall + is_secret → nil);
  `forever_guide.lua` Exorcism glow uses it — unknown (nil) is never "not undead".
- **H3:** `live_hunters_mark` distinguishes unreadable from absent via the new
  `api.spell_aura_may_be_secret(HUNTERS_MARK.id)` (fallback `api.auras_may_be_secret()`);
  the bridge turns "unknown" into no-cue + `restricted_seen`, so `evaluate` publishes
  `inputs_unknown` (HOLD face) instead of re-marking.
- **SEC-7/H5:** removed the three `if not name then break` aura-scan truncations in
  `hunter_ui.lua`; the 40-row cap and throttles remain.
- **SEC-4:** classic `UnitAura` compat branch now mirrors the C_UnitAuras branch —
  per-index `C_Secrets` precheck + pcall + whole-entry guard, 10-value arity kept.
- **SEC-11:** `api.GetCombatRating`/`GetCombatRatingBonus` guarded (nil on secret/throw;
  no-API 0 shape kept).
- **Helpers (additive):** `api.get_cooldown_remaining`, `api.spell_aura_may_be_secret`,
  `api.power_may_be_secret`; no existing wrapper contract changed.
- **Tests:** red-first per area. Final owned suites: secret_guard_state **521**,
  hunter_state **2123**, druid_state **1796**, forever_guide_state **1542** — all green.
  Cross-dependent suites re-run green (bars/bars_state, bars_lazy, hud, neutral_actions,
  guide_contract, forever_hud_gate, forever_guide_gate, main_init, range_source, smoke,
  real_wire). Lead-authorised one-file scope addition: re-cut
  `tests/forever_secret_compat_state.lua` §2 to the new SEC-4 contract (177/0).
- **Mutations:** **12/12 killed** on an isolated `/tmp` copy (control runs green) —
  raw UnitGUID, raw UnitIsUnit, nil ToT passthrough, raw UnitCreatureType, dead HM
  branch, re-added break, classic-aura pcall, classic-aura precheck, raw rating,
  restricted cooldown flag, non-boolean aura probe, druid raw GUID.
- **Current state:** full `bash tests/run.sh` + luacheck recorded below; report filed
  (`bench/secret_core_fix_2026-11-06.md`).
- **Next step (Lead):** the in-client closes are in the report's UNVERIFIED section
  (predicate triggers/availability, SetAlphaFromBoolean presence, classic shim presence);
  SEC-6/8/9/10/12 + H4 belong to the queued guide/hud lanes.

## 20261106T214659Z — [signal:done] Full gate green; report filed
- `bash tests/run.sh` (final tree): **57 steps, 0 failed**; `luacheck .` **2 warnings /
  0 errors in 100 files** (unchanged floor).
- Report: `bench/secret_core_fix_2026-11-06.md`; done signal
  `desks/secret-core-fix/.signals/20261106T214659Z.json`.
- No version fields touched (tree 2.1.8), no git, no other writer's files changed except
  the Lead-authorised `tests/forever_secret_compat_state.lua` §2 re-cut.
