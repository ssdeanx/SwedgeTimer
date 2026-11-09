# secret-consumers-audit — Journal

## 2026-11-06 — Desk opened (read-only consumer audit of the Forever secret-value regime)

- **Purpose:** audit the CONSUMER side of the WoW Forever (Camelot 1.60.1, Mainline-code)
  restricted/secret-value regime. The compat layer is already in place (nils secret values
  for arithmetic-safe wrappers, fifth `restricted` return on `GetSpellCooldown`, skips
  secret aura rows, raw power to the StatusBar). This desk audits what every consumer does
  with a degraded input: silently loses a feature, gives wrong advice, or throws.
- **Scope (read-only):** `classes/*.lua`, `hud.lua`, `forever_guide.lua`,
  `nextaction_ui.lua`, `hunter_ui.lua`, `main.lua`, `power_bar.lua`,
  `LibGlobalCooldown.lua`, `enemy_swing.lua`, `practice*.lua`, `option_tables.lua`,
  `compat.lua` (contract source). No product/tests/TOCs/bench-history/git edits. Only
  this journal, `bench/secret_consumers_audit_2026-11-06.md` and a done signal are new.
- **Priors read:** `desks/journal.md` (the 2026-11-06 secret-API dispatch + the 2.1.8
  reconcile), `bench/forever_display_audit_2026-11-06.md` §2/§10,
  `desks/forever-secrets/journal.md`, `bench/powerbar_secret_2026-11-06.md`,
  `bench/display_fix_2026-11-06.md`, `AGENTS.md` Cross-engine + Gotchas.
- **Method:** targeted greps + surgical reads of every consumer site; client facts from
  `git -C /home/sam/wow-ui-source show origin/forever:<path>` (classic_era is checked out,
  so `origin/forever` named explicitly). Offline behaviour probes in `/tmp` (loadfile of
  `forever_guide.lua` with a stub `st.api`) to prove the guide's decision output for
  degraded inputs — no product file touched. Baseline stated by dispatch: version 2.1.8,
  `bash tests/run.sh` 57/0, luacheck 2/0 (not re-run; parallel-lane tree).
- **Current state:** audit complete; deliverable written to
  `bench/secret_consumers_audit_2026-11-06.md` (ranked findings, each with degraded input,
  current behaviour, user effect, minimal fix and the test that would pin it; wrong
  advice / silent disappearance / would-throw separated).
- **Next step:** orchestrator/files a fix desk for the HIGH block: (1) class cooldown
  helpers must read the fifth `restricted` return / the Forever bridge must not trust a
  gathered `0`; (2) restricted power and target-aura absences must set the provider
  `inputs_unknown` (M6) instead of defaulting to 0/100/false; (3) hunter's Mark unknown
  branch is dead; (4) the three `hunter_ui` break-on-nil scans; (5) route hunter
  `UnitGUID("target")`/`UnitIsUnit` through compat. In-client Forever pass still owed for
  every trigger (secret restrictions are runtime state).

## 2026-11-06 — [signal:done] consumer audit complete

- Deliverable: `bench/secret_consumers_audit_2026-11-06.md` (ranked H1-H6, M1-M5,
  L1-L5; each with degraded input / current behaviour / user effect / minimal fix /
  test that pins it; WA vs FD vs THROW separated; UNVERIFIED table U1-U7).
- Done signal: `desks/secret-consumers-audit/.signals/20261106T212624Z.json`.
- Top block for the fix desk: (H2) class cooldown helpers publish `0` for a
  restricted read and the Forever guide bridge trusts it over its own safe read;
  (H1) restricted power becomes 0/0%/100% in gathers (warrior HOLD, paladin
  mana fillers lost, druid Enrage cue); (H4) restricted target-aura rows read as
  "absent" (Rend/Rip/Rake/Flame Shock re-cued, JotC bar hides); (H3) Forever
  Hunter's Mark unknown branch dead; (H5) the three hunter_ui break-on-nil scans;
  (H6/M1) direct UnitGUID(target)/UnitIsUnit comparisons can throw.
- Verified clean and recorded in §3 (aura walks, HUD/guide/power/range unknown
  states, LibGlobalCooldown, enemy_swing gating, C_Secrets/is_mainline gating,
  check_weapons, health/power/guid/totem/speed guards).
- Next step: Lead files the fix desk; in-client Forever pass closes U1-U7.

## 2026-11-06 — Reconciliation addendum (parallel forever-audit secret matrix)

- Cross-checked `bench/secret_api_matrix_2026-11-06.md` both ways after filing:
  its aliased `UnitGUID` local in `classes/druid.lua:331` (compared `:2389/:2397`)
  and its `UnitCreatureType` lead in `forever_guide.lua:553-559` are real — added
  as H6 (druid half) and M6. Its `GetTotemInfo` claim (SEC-8) did not reproduce
  (the cited shaman sites guard nil as unknown/hide), and its latent classic
  `UnitAura` claim is unreachable on Forever (the shim is
  `AllowLoadGameType classic` only). Recorded in the report's §7.
