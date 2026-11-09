# Secret-guide fix — restricted reads in the class gathers (2026-11-06)

- **Desk:** `secret-guide-fix` (writer). Lane taken over by the `powerbar-fix` agent after
  the roster closed; files: `compat.lua` (two additive helpers only),
  `classes/{paladin,hunter,shaman,druid,warrior,rogue}.lua`, `forever_guide.lua` (reviewed,
  unchanged), the six class suites + `tests/forever_guide_state.lua`, this report.
- **No git, no version fields, no TOCs/docs/run.sh, no other desk's file.**
- **Priors read:** `bench/secret_consumers_audit_2026-11-06.md` (H1/H2/H4/M2/M3/M4),
  `bench/secret_core_fix_2026-11-06.md` (helpers + H3), `bench/secret_api_matrix_2026-11-06.md`
  §8, `desks/journal.md` 2026-11-06 secret wave.
- **Verdict:** the class-side wrong advice is fixed offline: a restricted cooldown/power/
  target-aura/target-health read now produces `nil` + `inputs_unknown = true` (the display's
  suppression path) instead of a confident `0`/`0 %`/`"absent"`/`100 %`. One harness red
  remains and it is a **stale pre-fix pin in another desk's suite** (§7.1) — the file is
  outside this lane's write scope, so it is filed with the exact replacement.

## 1. The defect (audit H1/H2/H4/M2, confirmed in code)

On the Mainline-code clients (Wow Forever 1.60.1) a restricted read is opaque: `type()`
still answers, comparisons/arithmetic raise. compat's wrappers degrade those reads to
`nil` (`UnitPower`, `UnitPowerMax`, `UnitHealth`, `UnitHealthMax`, `UnitAura` row) and
`api.GetSpellCooldown` returns `0,0,0,0` plus a fifth `restricted = true`
(`compat.lua:407-505`). The class gathers then did the wrong thing with the degraded value:

| ID | Class path | Old behaviour | Consequence |
|---|---|---|---|
| **H2** | paladin `get_guide_cooldown_remaining`, hunter/shaman/warrior local `get_guide_cooldown`, druid `guide_cooldown_remaining`, rogue `spell_cooldown` | ignored the fifth return; `0` = ready | guide cued Judgement/Consecration/Arcane/Flame Shock/etc. on a hidden cooldown; the Forever bridge then trusted the gathered `0` before its own safe read (`forever_guide.lua:1593-1630`) |
| **H1** | paladin `get_guide_mana_pct` (returned **0**), hunter/shaman mana fraction, druid rage/energy/combo, warrior rage | a nil power read became 0/0 %/100 % | mana-gated rows never fired (paladin), bear druid cued Enrage at an unknown rage, warrior sat on HOLD |
| **H4** | warrior Rend, druid Rip/Rake, shaman Flame Shock, paladin JotC target scans | a hidden row read as "debuff absent" | re-cued an upkeep that may already be up (a wasted GCD) and hid the JotC bar |
| **M2** | warrior/paladin/hunter/druid target health | nil max became a 100 %/no-execute default | the execute phase silently disappeared |

Why `nil` alone is not enough (and the dispatch stresses it): the engine's
`forever_guide.is_ready(nil)` is **true** (`forever_guide.lua:14-32`), so a nil cooldown
still reads "ready". The suppression path is the unknown bit the display consumes
(`nextaction_ui.lua:638`: `unknown = out.inputs_unknown == true` withholds every advice
target). That is what the gathers now publish.

## 2. The fix

### compat.lua — the two additive helpers (no other contract changed)

- `api.health_max_may_be_secret(unit)` (`compat.lua:1022-1042`): exact boolean from
  `C_Secrets.ShouldUnitHealthMaxBeSecret(unit)` through `pcall`
  (`origin/forever SecretPredicateAPIDocumentation.lua:289-303`: "Returns true if queries
  for maximum unit health will produce secret values"). nil when the probe/API is absent,
  the unit is not a non-empty string, the answer is not a boolean, or the probe throws —
  unknown is never "no".
- `api.GetInventoryItemCooldown(slot)` (`compat.lua:1554-1575`): additive **fourth**
  `restricted` return — `true` when any returned field was secret (the same read that
  already degraded to the idle `0,0,0`), omitted on a readable read (the classic
  three-value shape is preserved). The HUD lane consumes it for the trinket unknown face.
- No other compat wrapper changed (the suite pins in `forever_secret_compat_state` and
  `secret_guard_state` still pass, except the three class-gather pins in §7.1 that pin the
  *consumer* behaviour this lane intentionally changes).

### class modules — restricted-aware producers + the mandatory unknown bit

Every class helper reads the shared `api.get_cooldown_remaining(token, fallback)` and, when
`restricted == true`, returns **nil** and records a per-tick flag; each gather resets the
flag at tick start and publishes `inputs.inputs_unknown = true` before returning (the
belt-and-braces the dispatch required). Gather fields stay nil, so the Forever bridge
falls through to its own safe `live_cooldown` (which sets `restricted_seen`) and a
gathered `0` can never win.

| Class | change sites (current lines) |
|---|---|
| paladin | `get_guide_cooldown_remaining` `classes/paladin.lua:2498`; the filler mirror's four `mana_pct` threshold compares are gated on `mana_known` (`:3656-3672`, a latent nil-compare crash the pinned re-cut exposed); `get_guide_mana_pct` `:2544-2565` (nil + second return); `get_guide_jotc_remaining` `:2421-2482` (rank-specific `spell_aura_may_be_secret` probe with list-wide fallback, throttled-cache-aware second return); `get_guide_target_health_pct` `:3319-3334` (nil + second return via the new health probe); gather reset `:3416`, belt `:3886` |
| hunter | module flag + `get_guide_cooldown` `classes/hunter.lua:2729-2765`; `read_serpent_active` `:3161-3213` (second return = the miss was caused by the restricted-aura regime; specific Serpent rank probe then list-wide); gather reset `:3282`, target hp `:3549-3567`, mana `:3648-3665`, serpent `:3699-3707`, belt `:3727` |
| shaman | `get_guide_cooldown` `classes/shaman.lua:2898-2915` (flag on the class table — this chunk is at the local ceiling); Flame Shock H4 branch `:3255-3275`; mana H1 `:3333-3345`; gather reset `:3129`, belt `:3769` |
| druid | file flag `:2188` + `debuff_aura_may_be_secret` `classes/druid.lua:2193-2223`; `get_guide_debuff_remaining` `:2225-2234`; `guide_cooldown_remaining` `:2291-2305`; power pools H1 `:2575-2610`; TTD/M2 `:2656-2662`; gather reset `:2550`, belt `:3062` |
| warrior | block flag + `get_guide_cooldown` `classes/warrior.lua:3644-3680`; Rend H4 miss probe `:3973-4004`; rage H1 `:4091-4099`; target hp M2 `:4118-4126`; gather reset `:4056`, belt `:4634` |
| rogue | `spell_cooldown` `classes/rogue.lua:392-414` (restricted -> nil + flag); gather reset `:976`, belt `:1349` (its energy/CP unknown path already existed) |

**H4 probe discipline:** the specific `api.spell_aura_may_be_secret(id)` answer wins; when
it is nil the list-wide `api.auras_may_be_secret()` is the fallback; only an explicit
`true` marks the tick unknown, so classic clients (no `C_Secrets`) keep today's exact
"absent" behaviour. Each class has an **aura-only** test leg where the hidden row is the
only unknown source.

**H1/M2 discipline:** the power type is only resolved on the unreadable path (no extra
probe on a normal tick); `api.UnitPower`/`UnitPowerMax` keep their pinned nil contract.
The engine's `is_ready(nil)` semantics were **not** changed.

### forever_guide.lua — reviewed, unchanged

No edit was needed: the core fix already made the bridge fall through on a nil field
(`forever_guide.lua:1593-1630`) and latch `restricted_seen` from its safe `live_cooldown`
(`:1454-1477`, `:1714-1716`). This lane's job was the producers that wrote `0`/`100` over
that safe read, plus the engine-level test contract (§3).

## 3. Tests (red-first, then green)

| Suite | Before | After | New pins |
|---|---|---|---|
| `tests/paladin_state.lua` | 1326 | **1364** | restricted gather (H1/H2/H4/M2), aura-only H4 leg, compat surface: item-cooldown fourth return (readable/secret/info-table/absent) + health-max probe strict contract |
| `tests/hunter_state.lua` | 2123 | **2132** | restricted gather H1/H2/H4, aura-only H4 leg, control |
| `tests/shaman_state.lua` | 1083 | **1092** | restricted gather H1/H2/H4, aura-only H4 leg, control |
| `tests/druid_state.lua` | 1796 | **1809** | restricted gather H1/H2/H4/M2, aura-only H4 leg, control |
| `tests/warrior_state.lua` | 2186 | **2197** | restricted gather H1/H2/H4/M2, aura-only H4 leg, control |
| `tests/rogue_state.lua` | 1150 | **1157** | restricted energy/CP (H1) + readable-power/restricted-cooldown tick bit (H2), control |
| `tests/forever_guide_state.lua` | 1542 | **1560** | §9b: the unknown bit suppresses the advice and **why it is mandatory** (a nil cooldown alone still cues: `is_ready(nil)`); paladin Judgement 999-sentinel -> `action=nil`; hunter Arcane, warrior Rend, druid Rip/Rake, shaman Flame Shock defect-vs-restricted pairs |

Red-first was captured before the product edits: the new paladin compat block failed on the
missing `api.health_max_may_be_secret`/the old three-value item cooldown, and each class
restricted leg failed on `inputs_unknown`/the 0-or-absent value (e.g. hunter
`secret H2: ... (got 0, want nil)`, paladin `(got 0, want nil)`). The final green counts are
above; plain-Lua 5.1, no client needed.

## 4. Mutation proofs — `10/10 killed`

`bash desks/secret-guide-fix/run_mutations.sh` (isolated `/tmp` copies of sources +
`classes/`, `tests/`, `Libs/`, `bench/` fixtures and the TOCs; pristine baseline of all
seven suites first, then one deliberately broken implementation per case):

| # | Mutation | Suite | Result |
|---|---|---|---|
| M1 | `api.get_cooldown_remaining` ignores the restricted flag (restores 0 = ready) | paladin | **KILLED**, 2 fails |
| M2 | hunter cooldown helper drops the fifth-return read | hunter | **KILLED**, 2 fails |
| M3 | paladin gather drops the belt-and-braces unknown publication | paladin | **KILLED**, 2 fails |
| M4 | paladin mana read restored to `... or 0` | paladin | **KILLED**, 1 fail |
| M5 | paladin JotC aura probe dropped (H4) | paladin | **KILLED**, 1 fail (aura-only leg) |
| M6 | warrior Rend aura probe dropped (H4) | warrior | **KILLED**, 1 fail (aura-only leg) |
| M7 | druid Rip/Rake aura probe dropped (H4) | druid | **KILLED**, 1 fail (aura-only leg) |
| M8 | shaman Flame Shock aura probe dropped (H4) | shaman | **KILLED**, 1 fail (aura-only leg) |
| M9 | Forever engine stops honouring the caller's unknown bit | forever_guide | **KILLED**, 8 fails |
| M10 | paladin filler mirror compares the (now nil-able) mana again | secret_guard | **KILLED**, 2 fails (nil compare raises; unknown bit lost) |

## 5. Gate

- My suites: `paladin_state` 1364, `hunter_state` 2132, `shaman_state` 1092,
  `druid_state` 1809, `warrior_state` 2197, `rogue_state` 1157/0 failures,
  `forever_guide_state` 1560 — all green.
- `luacheck` on the 16 touched files: **0 warnings / 0 errors**; whole-tree floor
  unchanged: **2 warnings / 0 errors in 100 files**.
- LF preserved in every touched file (CRLF count 0); no lint-config change; no `_`
  silencing; no version field touched.
- `bash tests/run.sh` on the final tree (Lead-authorised re-cut applied): **57 steps,
  0 failed** (2026-11-06 17:08:43). An earlier run (17:04:32) had exactly one red — the
  three stale pre-fix pins in `tests/secret_guard_state.lua`; §7.1 records the authorised
  re-cut. The whole-tree luacheck floor was the only other moving number and is unchanged.

## 6. Files changed

`compat.lua`, `classes/paladin.lua`, `classes/hunter.lua`, `classes/shaman.lua`,
`classes/druid.lua`, `classes/warrior.lua`, `classes/rogue.lua`,
`tests/paladin_state.lua`, `tests/hunter_state.lua`, `tests/shaman_state.lua`,
`tests/druid_state.lua`, `tests/warrior_state.lua`, `tests/rogue_state.lua`,
`tests/forever_guide_state.lua`, `tests/secret_guard_state.lua` (three pins re-cut under
Lead authorisation, §7.1), this report, `desks/secret-guide-fix/**`.
`forever_guide.lua` was reviewed and deliberately left unchanged (§2).

## 7. Follow-ups

1. **RESOLVED under Lead authorisation (2026-11-06): the three stale pre-fix pins in
   `tests/secret_guard_state.lua`.** The authorisation covered that file only, to re-cut
   the old class-gather H2 pins without weakening the wrapper pins:
   - `:787` warrior `hs_remaining` `0` -> **nil** (+ `inputs_unknown == true`);
   - `:1203` shaman `stormstrike_remaining` `0` -> **nil** (+ the unknown bit);
   - `:1462` paladin `cs_remaining` `0` -> **nil**, and `mana_pct` `0` -> **nil**
     (+ the unknown bit), with the paladin block installing the matching `C_Secrets`
     predicates and the client's `UnitPowerType("player") = 0` answer so the H1 probe path
     is the one under test.
   The re-cut exposed a **real latent crash** the old `0` default had hidden: the paladin
   gather's filler mirror compared `inputs.mana_pct` with a threshold at four sites, so the
   now-legal nil mana raised `attempt to compare number with nil` on a restricted
   Forever/Era tick. Those four compares are gated on `mana_known` (`classes/paladin.lua:
   3656-3672`), and mutation M10 proves the gate (dropping it re-introduces the crash and
   the lost unknown bit). The wrapper pins in the same suite (R2 cooldown/power/aura,
   §17) are untouched and still pass: 524 checks, 0 failures.
2. **M3 (display cold reads) — deferred by design.** The paladin Judgement marker already
   hides on an unreadable timing (no wrong ready claim) and the paladin CD-icon row /
   shaman SS-SR badges / WF-hold wash / hunter Auto-Shot window sync would need a tri-state
   through display/weave helpers and a broader rewrite; filed rather than half-done. The
   actively-wrong shaman WF-hold wash (`not ss_remaining` arms on a restricted read) is the
   first candidate for the display lane.
3. **M4 (practice context)** lives in `practice_ui.lua`, outside this lane's write scope
   entirely — filed: carry the gather's restricted flag into `ctx.cooldowns_unknown` and
   return "cannot decide" from the class decision.
4. **H4 paladin JotC bar** (`pulse_jotc_scan`, display-only) still hides under a restricted
   aura list; the guide input is fixed, the bar needs the display lane.
5. **SEC-10 (trinket HUD)** is the `secret-hud-fix` lane's: it consumes the new
   `GetInventoryItemCooldown` fourth return; its pin belongs in that lane.

## 8. UNVERIFIED — in-client only (nothing below is claimed)

1. That `C_Secrets.ShouldUnitHealthMaxBeSecret`, `ShouldUnitPowerBeSecret`,
   `ShouldSpellAuraBeSecret` and `ShouldAurasBeSecret` answer as documented on the
   Camelot 1.60.1 client, with the exact arity/semantics the wrappers assume. Absence or a
   throw degrades to nil (unknown), never to a throw, but the *trigger frequency* is a
   client observation.
2. Whether the operator's current play situation actually sets the restricted regime for
   cooldowns/power/auras/health (the audits' V-items remain open). If nothing is
   restricted, the old behaviour is byte-identical (the flag stays nil/false everywhere).
3. The Forever engine's display face while the tick is unknown (the `…`/HOLD face) is
   proven only through the `inputs_unknown` contract and `nextaction_ui.lua:638`; the
   rendered result is the operator's eye.
4. Rogue H2 end-to-end: the gather's AR/Vanish cooldown outputs are not consumed by the
   Forever rogue rules (HUD/practice only); the helper change is in place, and the
   tick-bit contract is pinned through the readable-power/restricted-cooldown leg.
5. What a restricted value looks like to `type()`/comparison on the live client — the
   suites model it with flagged sentinels (numbers that stay numbers, comparisons that
   would raise in the client), exactly like compat's own suite.

**Do not read this report as in-client proof.** Everything above is offline evidence,
documented API contracts, and mutation-verified unit behaviour.
