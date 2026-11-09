# secret-guide-fix — Journal

## 2026-11-06 — desk opened: restricted reads consumed as 0/0 %/"absent" by the class gathers

- **Purpose:** the guide-side half of the 2026-11-06 secret-value wave. Wow Forever
  restricted reads were reaching the class `gather_guide_inputs` and the Forever engine as
  confident wrong facts: a restricted cooldown became `0` = "ready", a restricted power
  read became `0 %`/`100 %`, a hidden target-aura row became "the debuff is absent", and a
  restricted target-health read silently removed execute advice.
- **Scope (exact):** `compat.lua` (ONLY two additive helpers:
  `api.health_max_may_be_secret` and a fourth `restricted` return on
  `api.GetInventoryItemCooldown`), `classes/{paladin,hunter,shaman,druid,warrior,rogue}.lua`,
  `forever_guide.lua`, `tests/{forever_guide_state,paladin_state,hunter_state,shaman_state,
  druid_state,warrior_state,rogue_state}.lua`, `desks/secret-guide-fix/**`, one NEW bench
  report. NOT: hud.lua (secret-hud-fix), power_bar/bars/main/swing_source/weave_range,
  TOCs/docs/run.sh, other desks' files. No git, no version fields.
- **Priors read:** `bench/secret_consumers_audit_2026-11-06.md` (H1/H2/H4/M2/M3/M4 +
  verified-clean), `bench/secret_core_fix_2026-11-06.md` (the shared helpers + H3),
  `bench/secret_api_matrix_2026-11-06.md` §8, `desks/journal.md` 2026-11-06 secret wave.
- **Next step:** red-first class tests, then the producers + the mandatory unknown bit.

## 2026-11-06 — fixed and mutation-proven; one stale pin filed

- **Worked on:**
  - **compat.lua (additive only):** `api.health_max_may_be_secret(unit)` (exact boolean from
    `C_Secrets.ShouldUnitHealthMaxBeSecret`, pcall; nil on absent/throw/non-boolean/non-string
    — unknown is never "no"), and a fourth `restricted` return on
    `api.GetInventoryItemCooldown` (idle zeros + true on a secret field; the classic
    three-value shape is preserved on a readable read). No other compat contract changed.
  - **Class producers (H2/H1/H4/M2):** every class cooldown helper reads
    `api.get_cooldown_remaining` and, on `restricted == true`, returns nil and records a
    per-tick flag; every gather resets the flag and publishes
    `inputs.inputs_unknown = true` before returning (the belt). Power, target-aura and
    target-health reads follow the same nil + unknown discipline; the aura probes are
    specific-id first with the list-wide fallback, and only an explicit true marks unknown,
    so classic clients keep the historical absent behaviour. The engine's `is_ready(nil)`
    semantics were NOT touched — the unknown bit is the suppression path
    (`nextaction_ui.lua:638`).
  - **forever_guide.lua:** reviewed and left UNCHANGED — the core fix already makes the
    bridge fall through on a nil field and latch `restricted_seen`; this lane fixed the
    producers that were writing 0/100 over that safe read.
  - **Tests:** the six class suites gained restricted-gather legs + an aura-only H4 leg
    each (the hidden row is the only unknown source) + controls, plus the compat-surface
    pins in paladin_state; `forever_guide_state` gained §9b proving the unknown bit
    suppresses advice and why it is mandatory (a nil cooldown alone still cues through
    `is_ready(nil)`).
- **Current state (verified 2026-11-06):**
  - Suites green: paladin 1364, hunter 2132, shaman 1092, druid 1809, warrior 2197,
    rogue 1157/0, forever_guide_state 1560.
  - `luacheck` on the 15 touched files: 0 warnings / 0 errors; whole-tree floor unchanged
    (2/0 in 100 files). LF preserved; no lint-config change; no `_` silencing.
  - Mutations: `desks/secret-guide-fix/run_mutations.sh` → **9/9 killed** (shared helper
    ignores the flag; hunter drops the fifth return; paladin belt dropped; mana `or 0`;
    paladin/warrior/druid/shaman aura probes dropped; engine ignores the unknown bit),
    isolated `/tmp` copies, pristine baseline of all seven suites first.
  - **Full harness 2026-11-06 17:04:32: 57 steps, 1 failed** —
    `tests/secret_guard_state.lua` 3 of 521: three PRE-FIX pins that assert the old H2
    behaviour this lane intentionally changes (`:787` warrior HS `0`, `:1203` shaman
    stormstrike `0`, `:1462` paladin CS `0`; each is now nil + `inputs_unknown == true`).
    That file is the core desk's / outside this lane's write scope → FILED with the exact
    replacement, not edited.
- **Artifacts:** `bench/secret_guide_fix_2026-11-06.md` (root cause per finding, fix table
  with current line cites, evidence, 9/9 mutation table, gate, follow-ups, UNVERIFIED);
  `desks/secret-guide-fix/run_mutations.sh`.
- **UNVERIFIED (in-client only):** the real C_Secrets predicates/arity and whether the
  operator's current play actually triggers the restricted regime; the rendered unknown
  face; what a restricted value looks like to `type()`/comparison live.
- **Next step:** the Lead (or the core desk's owner) applies the three-line
  `tests/secret_guard_state.lua` pin update (filed with exact lines) → full harness 57/0.
  Display-lane follow-ups: M3 cold reads (paladin CD row, shaman SS/SR badges + WF-hold
  wash, hunter window sync), H4 paladin JotC bar, M4 practice ctx (practice_ui.lua), and
  the hud lane's trinket unknown face consuming the new item-cooldown fourth return.

## 2026-11-06 — [signal:done] secret-guide-fix done

- Class gathers + the Forever bridge now treat restricted reads as unknown (nil + the
  mandatory `inputs_unknown` bit); compat gained only the two additive helpers; 9/9
  mutations killed; one stale pin in another desk's suite filed with the exact fix.

## 2026-11-06 — [signal:done] final green after the Lead-authorised pin re-cut

- **Lead authorisation:** update the three stale pre-fix pins in
  `tests/secret_guard_state.lua` ONLY (the §7.1 items), re-cut to the new contract, without
  weakening the wrapper pins. Done: `:787` warrior HS, `:1203` shaman Stormstrike and
  `:1462` paladin CS now assert nil + `inputs_unknown == true`; the paladin block installs
  the matching `C_Secrets` predicates and the client's `UnitPowerType("player") = 0`
  answer so the H1 probe path is the one under test. Wrapper pins untouched.
- **Latent crash found and fixed by the re-cut:** the old `0` default hid a nil compare in
  the paladin filler mirror — four `inputs.mana_pct > threshold` sites in
  `classes/paladin.lua:3656-3672` would raise `attempt to compare number with nil` on a
  restricted Forever/Era tick now that the mana read is legitimately nil. All four are
  gated on `mana_known`.
- **State:** `secret_guard_state` 524 checks, 0 failures. Mutations now **10/10 killed**
  (added M10: dropping the paladin mana gate re-introduces the crash and loses the unknown
  bit; the mutation baseline now covers `secret_guard_state` too). Full `bash tests/run.sh`
  at 2026-11-06 17:08:43: **57 steps, 0 failed**. Whole-tree luacheck 2/0 in 100 files;
  this lane's 16 files 0/0. LF preserved.
- **Artifacts:** `bench/secret_guide_fix_2026-11-06.md` updated (§2 filler gate, §4 10/10,
  §5 final gate, §6 files, §7.1 RESOLVED with the crash note); second done signal emitted.
- **UNVERIFIED:** unchanged — in-client predicate behaviour/trigger frequency, the rendered
  unknown face, restricted values' live `type()`/comparison surface. Nothing here claims
  in-client proof.
- **Remaining follow-ups (not this lane):** M3 display cold reads (paladin CD row, shaman
  badges + WF-hold wash, hunter window sync), H4 paladin JotC bar, M4 practice context
  (`practice_ui.lua`), and the hud lane's trinket face consuming the new item-cooldown
  fourth return.
