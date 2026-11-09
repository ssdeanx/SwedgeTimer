# aura-hud-verify — Journal

## 2026-11-08 — Desk opened (task t5, `swedge-forever-hud` team, attempt 1)

- **Purpose:** independent verifier. Verify both Forever HUD lanes (t3 secret-safe
  cooldown/GCD + cache hardening; t4 Forever-only aura row) and audit the Forever secret
  flow and every cache. Read-only on product / tests / TOC / config / options / docs, **no
  git in this repository**, no version change.
- **Scope of writes:** `bench/hud_forever_verification_2026-11-08.md`,
  `desks/aura-hud-verify/**` only. Mutation/harness copies lived in per-call `/tmp`
  throwaways (this environment gives each bash call a private `/tmp`, so a copy, its
  mutant, the suite run and the cleanup must happen inside one call).
- **Inputs read first:** the brief, `bench/forever_hud_api_2026-11-08.md`,
  `bench/aura_row_reference_2026-11-08.md`, both implementation reports, `AGENTS.md`,
  `desks/journal.md`, `bench/lessons.md`, then the code itself (`hud.lua` header + paint +
  trinket + cache blocks, `compat.lua` secret helpers, `LibGlobalCooldown.lua`,
  `aura_icons.lua` in full, the three suites, the TOC, run.sh, toc_check.lua,
  config_presets/option_tables wiring).
- **Independent client proof:** re-read every load-bearing claim with read-only
  `git -C /home/sam/wow-ui-source show origin/forever:<path>` (the checked-out branch there
  is `classic_era`; `show` used, never the worktree). Confirmed: no `SecretWhen*` on
  `GetSpellCooldownDuration`; no `SecretArgumentsAddAspect` on
  `SetCooldownFromDurationObject` (unlike the four numeric setters); `isEnabled/isActive/
  isOnGCD` `NeverSecret`; `HasSecretValues` `ReturnsNeverSecret`; `C_Secrets` predicates;
  the duration-text binding/seconds-formatter/colour-curve surfaces and the exact enum
  members used (`SecondsFormatterAbbreviation.None`, `…Interval.Seconds`,
  `…Rounding.Truncate`, `DurationTextBindingProperty.RemainingDuration`); the container
  template `allowUntaintedCreation="true"` + `DisableUntrustedLayoutScriptsTemplate`; every
  container/button method the aura module calls; `AnchorUtil.FlowDirection` values;
  `AddAuraGroup` option scheme and validation; `AuraContainerSortMethod.Expiration = 4`,
  `SortDirection.Normal = 0`, both exported with `securecopy`; `initializeFrame` running
  before the client applies access restrictions; `UnitExists`/`UnitCanAttack` plain;
  `UnitGUID` identity-restricted; `SetText`/`SetTextColor` still AllowedWhenTainted after
  the Text aspect attaches (only `GetText` turns secret).

## 2026-11-08 — [signal:done] Verification complete, both lanes PASS

- **Worked on:** the whole t5 checklist.
  1. **Harness re-run (independent):** `bash tests/run.sh` → **59 steps, 0 failed**;
     `luacheck .` → **2 warnings / 0 errors in 105 files** (both pre-existing
     `hunter_ui.lua:135-136`, untouched, mtime 2026-11-06); `luac5.1 -p` clean on every
     changed file; LF only; no lint-config change; no `luacheck: ignore`; no vacuous
     `assert(true)`.
  2. **Suite counts:** `hud_state` 1024; `forever_secret_compat_state` 250;
     `aura_icons_state` 853; `secret_guard_state` 524 (unmodified); `toc_check` 360.
  3. **Pre-existing checks not weakened:** truncating the new sections out of copies of the
     two extended suites yields **exactly 893** and **exactly 177** checks, 0 failures —
     the implementers' stated baselines (893 → 1024 = +131; 177 → 250 = +73).
  4. **Mutation re-run (isolated copies, anchored single-site):** all **20** implementer
     mutants reproduce their **exact** failing counts (t3: 34/41/1/3/11/6/4/2; t4:
     55/2/15/9/11/4/4/2/3/5/2/3); t3's declared M5 (SEC-13 scrub removed) reproduces as a
     survivor; spot-checked failure text names the intended mechanism in every case. My
     extra guard mutant (bypassing the pre-existing `HasSecretValues() ~= false` refusal in
     `compat.lua:398`) **does** fail (`forever_secret_compat_state` 4 checks), so that
     secret path is pinned, not untested.
  5. **Getter-discipline proof (my own probe):** with `HasSecretValues() == true` and every
     object getter raising, `api.GetSpellCooldown` returns `0,0,0,0,true` and
     `api.get_spell_cooldown_duration` returns the handle + `true` without calling a getter
     (259 checks / 0 failed). No product code calls `GetRemainingDuration`,
     `GetTotalDuration`, `GetStartTime`, `HasStarted`, `HasExpired`, `IsActive` or `IsZero`
     on a duration object; the only getter site is the pre-existing
     `compat.lua:385-400` reader, which refuses anything but `HasSecretValues() == false`.
  6. **Gate audit:** 19 Forever-only paths, each `st.family == "FOREVER"` + exact probe;
     `st.is_mainline` alone gates nothing new; `aura_icons.lua` is inert before any
     frame/event/aura call on all six non-Forever families (source + suite + mutant T4-M1);
     single-TOC contract holds (`aura_icons.lua` once at `SwedgeTimer.toc:67`, after
     `hud.lua`).
  7. **Cache audit:** `HUD.known_names`, `HUD.known_cache`, `HUD.layout_cache`,
     `HUD.icons[i].*`, `HUD.trinkets`, `TRINKET_STATE`, `PREVIEW_STATE`, `SAFE_STATE`,
     `LibGlobalCooldown` numeric + object state, `aura_icons` state, compat tables — each
     either plain by construction or re-proved before use; no secret can become a key.
  8. **Behaviour preservation:** non-Forever numeric swipe/text/tint/trinket/GCD paths are
     gated identically (extra no-op probes only); the aura module's only `ST` surface is
     five read-only getters, so no existing visual can move; the five new defaults are
     data-only on classic (unreachable, widgets hidden).
  9. **In-client checklist:** 10 `/run` probes + behavioural steps + the explicit
     UNCONFIRMED list, in the report §10.
- **Findings (reported, not fixed — I am read-only):** F1 comment typos in
  `aura_icons.lua:4,11`; F2 stray `luac.out` in the repo root (not TOC-listed, cannot
  load); F3 a post-`CreateFrame` setup failure can leave a named container that blocks
  every later retry (trigger requires an invalid `db.frame_strata`; suite has no injector);
  F4 a size change under aura secrecy can leave already-allocated buttons at the old size
  (pcall-contained, cosmetic); F5 the t4 report says "6 additional hidden widgets" where
  the builder contributes 7 args entries; F6 benign per-tick `pcall`/family-compare delta
  on classic; F7/F8 runtime UNCONFIRMED (engine acceptance/rendering of a secret-valued
  object; LGC probe spell 61304); F9 the disclosed M5 survivor.
- **Verdict:** A/B/C/D/E **PASS** (B with the runtime U3/U5 closers UNCONFIRMED), F
  delivered. No blocker, no secret/taint defect, no non-Forever behaviour change found.
- **Current state:** report `bench/hud_forever_verification_2026-11-08.md` (584 lines) +
  this journal + done signal written. Product tree untouched by this lane.
- **Next step (Lead/operator):** rule on F1-F5 (all cosmetic/robustness; Lead owns the
  edits), delete `luac.out` before release, and run the §10 probes in one restricted
  Forever moment — probes 4 and 5 (plus 2/3 for the additive GCD channel) are the only
  things standing between "verified offline" and "observed working".
