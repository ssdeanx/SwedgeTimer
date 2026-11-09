# Brief — Independent verification and secret-flow audit (2026-11-08)

## Role and mode

Independent verifier for the Lead's Agent Team. You are **read-only on product
files, tests, the TOC, config, options, docs, and the reference repos**. You write
exactly one verification report, one desk journal, and one done signal.

Your verdict is evidence, not ceremony. If a lane fails, report it with exact
`file:line` findings and the minimal fix; do not fix it yourself.

## Mission

Verify that the two implementation lanes delivered **enterprise-grade, WoW
Forever-only** work with zero behavior change on every other client:

- `bench/hud_forever_cooldown_2026-11-08.md` + code in `hud.lua`, `compat.lua`,
  `LibGlobalCooldown.lua`, `tests/hud_state.lua`,
  `tests/forever_secret_compat_state.lua`.
- `bench/aura_row_2026-11-08.md` + `aura_icons.lua`, `tests/aura_icons_state.lua`,
  `SwedgeTimer.toc`, `main.lua`, `config_presets.lua`, `option_tables.lua`,
  `option_table_presets.lua`, `tests/run.sh`, `tests/toc_check.lua` if touched.

The operator's words: "everything that is secret in wow forever is correctly
passed the data so it does not become tainted. especially if something is cached,
that will cause problems because data cant be tainted and it will be without a
check for it." "Do not break any other clients. Enterprise grade quality." "The
aura thing should be wow forever only."

## Required reading

1. `bench/forever_hud_api_2026-11-08.md` (API contract) and
   `bench/aura_row_reference_2026-11-08.md` (reference/port map).
2. Both implementation reports named above.
3. `AGENTS.md` (Cross-engine, Gotchas, Workshop mechanics), `desks/journal.md`
   tail, `bench/lessons.md`.
4. `hud.lua` header, `compat.lua` secret helpers, `LibGlobalCooldown.lua`,
   `aura_icons.lua`, the changed tests, `SwedgeTimer.toc`, `tests/run.sh`,
   `tests/toc_check.lua`.

## Verification checklist

### A. Gate correctness (non-negotiable)

- Every new Forever behavior is gated on `st.family == "FOREVER"` **and** an exact
  API probe. Find any path that can execute on ERA/TBC/WRATH/CATA/MISTS/RETAIL:
  a frame creation, event registration, aura read, cooldown duration-object call,
  option side effect, or default change.
- `st.is_mainline` alone must not gate any Forever-only behavior.
- `aura_icons.lua` must be inert on every non-Forever family: no `CreateFrame`,
  no `RegisterEvent`, no `UnitAura`/`C_UnitAuras`/`C_AuraContainerUtil` call.
  Verify the module returns early before any of those.
- The single-TOC contract holds: `aura_icons.lua` appears exactly once in
  dependency order; no flavor TOC; `tests/toc_check.lua` green.

### B. Secret-flow audit (forever)

Trace every HUD/aura path that touches a secret-capable API:

- `C_Spell.GetSpellCooldown`, `C_Spell.GetSpellCooldownDuration`,
  `C_ActionBar.GetActionCooldownDuration`, `GetInventoryItemCooldown`,
  `C_Spell.GetItemCooldown`, `UnitAura`, `C_UnitAuras.*`,
  `C_Spell.GetSpellInfo`, `IsSpellUsable`, `UnitPower`, `UnitHealth`,
  `UnitGUID`, `UnitIsUnit`, `UnitCreatureType`, `C_Secrets.*`.
- For each: confirm the restricted read returns nil/unknown, OR the opaque
  duration object is passed to a documented secret-safe sink, OR the raw value
  goes only to an `AllowedWhenTainted` sink (`FontString:SetText`,
  `StatusBar:SetValue`, `SetAlphaFromBoolean`, ...). A value must never reach a
  comparison, arithmetic, string format, table key, or table value.
- Confirm the duration-object path never calls `GetRemainingDuration`,
  `GetTotalDuration`, `GetStartTime`, `IsActive`, `HasStarted`, `HasExpired` when
  `HasSecretValues()` is true. If it reads them, require the `HasSecretValues()`
  false guard at the call site and a test.
- Confirm the native aura path never reads `AuraData` fields and never calls
  `UnitAura` while `C_Secrets.ShouldAurasBeSecret()` is true.
- Confirm no raw `GetSpellCooldown`/`UnitAura`/identity call bypasses `compat.lua`
  in the changed HUD files.

### C. Cache audit (the operator's specific worry)

Inspect every cache in the HUD/aura path:

- `HUD.known_names`, `known_cache`, `HUD.layout_cache`, `HUD.icons[i]` fields,
  `HUD.trinkets[13/14]`, `TRINKET_STATE`, `PREVIEW_STATE`.
- `LibGlobalCooldown` state.
- `aura_icons.lua` state (containers, last anchor, size, top bar).
- `compat.lua` any new memo/table.

For each: what is stored, can it be secret, is it revalidated before use, and is
there a test proving a secret value cannot be stored and later consumed
unchecked? Flag any cache whose correctness depends on "this was plain last
tick" without a current proof. Also flag any table that can receive a secret key
(it will raise or poison the table).

### D. Behavior preservation

- Non-Forever code paths: compare the changed functions against the prior
  behavior described in the implementer reports; confirm the numeric
  `SetCooldown` sequence, text rules, tint rules, trinket tri-state, and GCD
  handling are unchanged where the old code ran.
- Aura row: confirm no existing HUD icon, bar, power bar, guide, or practice
  visual is moved, resized, hidden, or re-parented by the new module.
- Defaults: confirm every new default lands only in the Forever path and is
  documented; classic profiles see no change.
- Combat safety: no frame creation in combat lockdown; deferred retry; no
  secure/protected call from tainted code during combat.

### E. Test and harness evidence

Independently run:

- `bash tests/run.sh` — full harness; record exact `N steps, M failed`.
- `luacheck .` — record the tree total and the touched-file totals.
- `luac5.1 -p` on every changed `.lua`.
- The new/changed suites directly, with their exact check counts.
- The implementers' mutation scripts on the current tree (or re-apply the listed
  mutants to isolated `/tmp` copies) and confirm each mutant fails for the
  intended reason and the pristine copy passes.
- Grep the changed files for `_`-silenced warnings, new lint config changes,
  `-- luacheck: ignore`, and vacuous `assert(true)` tests. Flag them.
- Confirm LF line endings on every changed file; flag CRLF or mixed.

### F. In-client checklist

Produce an exact, copy-pasteable checklist for the operator's client (no guessing):

- `/run` probes for `C_Secrets.HasSecretRestrictions()`,
  `C_Secrets.ShouldCooldownsBeSecret()`,
  `C_Secrets.ShouldSpellCooldownBeSecret(<slot spell id>)`,
  `C_Spell.GetSpellCooldownDuration(<id>):HasSecretValues()`, and the same for a
  GCD probe.
- Steps to enter combat and a dungeon, cast an ability, observe the icon swipe,
  countdown text, GCD swipe, and the 2 s text suppression.
- Steps to verify the aura row per class: row appears above the top bar, moves
  with the bar, shows the class buffs/debuffs, hides on HUD toggle, stays inert
  on a non-Forever client.
- What remains UNCONFIRMED offline and therefore cannot be marked "fully
  working" by the team.

## Deliverable

`bench/hud_forever_verification_2026-11-08.md` with:

1. Verdict per checklist section (PASS / FAIL / UNCONFIRMED) and exact evidence.
2. Findings, ranked, with `file:line`, degraded input, current behavior, user
   effect, minimal fix, and the test that would pin it.
3. Independent command outputs (harness/luacheck/luac/suite counts/mutation
   table).
4. Gate audit: every Forever-only path and its gate.
5. Cache audit table (cache -> stored value -> secret risk -> revalidation ->
   test).
6. In-client checklist.
7. Residual risks and what the operator must observe in the client.

Also `desks/aura-hud-verify/journal.md` + `.signals/<timestamp>.json`.

## Hard constraints

- No product/test/TOC/config/docs edits. No git. No version changes.
- No re-run of an answered question; verify against the frozen evidence.
- Do not accept "the test passed" without the exact count and the intended
  assertion; do not accept a mutation that fails for the wrong reason.
- Enterprise-grade: no guessing, no papering over an unverified area. An
  unverified area is UNCONFIRMED with the exact missing evidence.
