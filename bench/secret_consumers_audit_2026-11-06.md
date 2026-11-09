# Consumer-side audit of the WoW Forever secret-value regime — 2026-11-06

Desk: `desks/secret-consumers-audit` (read-only). Client target: WoW Forever /
Camelot 1.60.1, Interface 16001, `WOW_PROJECT_CAMELOT = 18`, Mainline-code
(`st.is_mainline == true`). Baseline given by the dispatch: version 2.1.8,
`bash tests/run.sh` 57/0, luacheck 2/0. Client facts are cited from
`origin/forever` as `origin/forever:path:line`; addon facts as `file:line`.

**Question this audit answers:** the compat layer already degrades restricted
(secret) reads — it nils secret values for the arithmetic-safe wrappers, adds a
fifth `restricted` return to `GetSpellCooldown`, skips secret aura rows, and passes
raw player power to the StatusBar (2.1.8). Does every *consumer* handle those
degraded inputs, or does a restricted read silently remove functionality, give
wrong advice, or throw?

**Answer in one line:** the three already-fixed surfaces (Forever HUD, Forever
guide's own live reads, power bar) are sound, but **the class-module gathers that
feed the Forever guide bypass the fix**: they turn a restricted cooldown into `0`
("ready") before the guide's restricted-aware bridge sees it, and they turn
restricted power/target-aura reads into `0`/`100`/`false` without setting the
provider's unknown bit. Two hunter paths compare secret-capable identity reads
directly and can throw. Offline probes reproduce the wrong-advice output.

---

## 0. Executive summary and ranking

Category key: **WA** = wrong advice (a cue/grade built on a read that was not
actually readable); **FD** = feature silently disappears; **THROW** = would throw.
Confidence is about the code claim; trigger confidence is the client-only half and
is marked separately (all triggers are UNVERIFIED in-client — see §5).

| # | Sev | Cat | Conf (code / trigger) | Finding |
|---|-----|-----|----------------------|---------|
| H1 | HIGH | WA + FD | HIGH / HIGH (operator-confirmed restricted power) | A restricted `UnitPower` becomes `0`/`0 %`/`100 %` in the class gathers and the Forever guide treats it as a fact: warrior stalls on HOLD, paladin loses every mana-gated filler, druid bear mis-cues Enrage, hunter/shaman mana gates go inert. No unknown marker. |
| H2 | HIGH | WA | HIGH / MED (cooldown restrictions contextual) | A restricted cooldown becomes `0` in the class cooldown helpers (paladin/hunter/shaman/druid/rogue), and the Forever guide's bridge **trusts the gathered field over its own restricted-aware live read** (`forever_guide.lua:1593-1630`). Proven: paladin cues Judgement with `unknown=false`; hunter cues Arcane Shot. |
| H3 | HIGH | WA | HIGH / MED | The Forever Hunter's Mark "unknown" branch is dead code (`forever_guide.lua:1500-1514`): a restricted/absent target aura both read `false`, so the guide re-cues Hunter's Mark at the top of the ranged priority every tick. Proven offline. |
| H4 | HIGH | WA + FD | HIGH / MED | Restricted target-aura rows are read as "debuff absent" by the upkeep gathers: warrior re-cues Rend, druid re-cues Rip/Rake, shaman re-cues Flame Shock; the paladin JotC bar hides. No `auras_may_be_secret()` gate on those paths (unlike rogue/shaman lust and paladin seals/seal-lust). |
| H5 | HIGH | FD | HIGH / MED | The three `hunter_ui` hand-rolled aura scans still `break` on `not name` (`:1276`, `:1408`, `:1761`). A restricted row above the tracked aura truncates the scan: Rapid Fire bar (default ON), aspect icon (default ON) and Frenzy stacks badge (opt-in) silently disappear. The known lead, confirmed. |
| H6 | HIGH | THROW | HIGH / UNVERIFIED | `UnitGUID("target")` is called **directly** and compared in two live paths: the hunter queue tint (`classes/hunter.lua:1375`, stored `:1582/:1589`) and the druid TTD sampler (`local unit_guid = UnitGUID` at `classes/druid.lua:331`, compared `:2389/:2397`). A secret target GUID raises on `~=`; the sites are guard-isolated, so the feature dies (quarantine after 25 throws), not the addon. |
| M1 | MED | THROW | HIGH / UNVERIFIED | `UnitIsUnit("targettarget","player")` is called **directly** and its return compared (`classes/hunter.lua:1614-1629`). `SecretWhenUnitComparisonRestricted` on Forever; a secret boolean raises on `== nil`. ToT widget is opt-in but per-frame. |
| M2 | MED | FD | HIGH / MED | Restricted target health (`UnitHealthMax` is `SecretWhenUnitHealthMaxRestricted`; `UnitHealth` is `SecretReturns`) makes `target_health_pct` nil → the Forever guide defaults it to `100` → Hammer of Wrath / Execute rows never fire; warrior execute HUD tint stays off. |
| M3 | MED | FD (+ one wrong visual) | HIGH / MED | Display-only cold reads treat restricted cooldowns as ready/absent: paladin Judgement swing marker (default ON) vanishes, paladin CD-icon row (opt-in) shows no swipe, shaman SS/SR badges vanish **and the WF-hold wash can falsely arm**, hunter Auto Shot window sync skips the tick. |
| M4 | MED | WA (practice) | MED / UNVERIFIED | The practice scenario context lifts the class gather's `*_remaining` values into `ctx.cooldowns`; for druid/shaman/warrior (no `practice_context`) a restricted cooldown is published as `0`, so the expected action / graded answer can assume an ability is ready. |
| M5 | MED | WA + FD | HIGH / UNVERIFIED | Retail residual: the restricted-aware HUD/guide providers are `st.family == "FOREVER"`-gated; Retail 12.x (same Mainline secret regime) runs the class paths that treat a restricted read as ready. Same code, second target. |
| M6 | MED | THROW | HIGH / UNVERIFIED | `forever_guide.get_hud_state` calls `UnitCreatureType("target")` **directly** and compares it (`forever_guide.lua:553-559`, the paladin Exorcism glow). `SecretWhenUnitIdentityRestricted`; a secret ctype raises on `==`. Guarded by the HUD's per-icon `guard.run` → the icon's state is lost after quarantine, not the addon. The paladin class already guards the same read (`classes/paladin.lua:2516-2526`); the Forever provider does not. |
| L1 | LOW | THROW (latent) / rule | HIGH / UNVERIFIED | Direct player-identity reads outside compat (`main.lua:577`, `main.lua:1176-1177`, `classes/paladin.lua:996`, `LibGlobalCooldown.lua:195`, `utils.lua:65`, `option_tables.lua:79/156`, `main.lua:413`). Safe values today; the `main.lua:1177` target-GUID branch is unreachable on mainline (CLEU registration gated at `main.lua:765`). |
| L2 | LOW | rule | HIGH / — | `swing_source.lua` calls `UnitAttackSpeed`/`UnitRangedDamage` directly (`:256-272`, `:329-345`, `:384-400`). Behaviour is compliant (pcall + `is_secret` guards) but bypasses `st.api`. |
| L3 | LOW | latent | HIGH / — | `api.GetCombatRating`/`GetCombatRatingBonus` are raw pass-throughs (`compat.lua:1358-1373`); the only consumer re-guards locally (`LibGlobalCooldown.lua:34-46`). Future consumers would be exposed. |
| L4 | LOW | observability | HIGH / — | `/st diag` has no restricted-cooldown / restricted-aura receipt (only the power line reports `restricted`, `diag.lua:845-856`). The operator cannot tell a silent restricted state from a real "nothing to do". |
| L5 | LOW | UX | HIGH / — | The HUD restricted face is a grey icon with no swipe and no text (`hud.lua:1213-1313`) — adequate (never a fabricated timer) but reads like "disabled"; the guide uses `…`, the power bar `?`, the range bar `--`. No explicit marker. |

Ranked fix order for the fix desk: **H2 → H1 → H4 → H3 → H5 → H6 → M1 → M2 → M6 → M3 → M4 → M5 → L1/L2/L3/L4/L5.**

The single structural defect behind H1/H2/H4/H3/M2: the Forever guide's decision
model was made restriction-aware, but its **inputs are still produced by
restriction-blind class gathers**, and the bridge prefers whatever the gather set.
The minimal, uniform fix is: *any class gather field derived from a restricted
read must be withheld AND set the provider-owned `inputs_unknown` (M6); the barrel
of `nil`/`0`/`100 %` defaults must never be reachable from a degraded read.*

---

## 1. The contract every consumer faces

### 1.1 compat (the degradation surface, read-only reference)

| API | Restricted read becomes | Citation |
|---|---|---|
| `api.UnitPower` / `api.UnitPowerMax` | `nil` (unknown) | `compat.lua:599-624` |
| `api.GetPlayerPower` (power-bar-only) | raw values + `restricted` flag | `compat.lua:626-651` |
| `api.UnitHealth` / `api.UnitHealthMax` | `nil` | `compat.lua:687-712` |
| `api.UnitAura` | `nil` row (whole entry) | `compat.lua:727-786` |
| `api.scan_player_aura` / `scan_unit_aura` | walks all 40 rows, never breaks; `nil,nil` = not found **or** unreadable | `compat.lua:788-902` |
| `api.auras_may_be_secret` | `true`/`false`/`nil` (unknown) | `compat.lua:904-925` |
| `api.GetSpellCooldown` | `0,0,0,0,true` when no readable source; `restricted` is a fifth return that is `nil` otherwise | `compat.lua:407-505` |
| `api.GetTotemInfo` | `nil` | `compat.lua:1581-1599` |
| `api.UnitGUID` | `nil` | `compat.lua:1734-1743` |
| `api.GetUnitSpeed` / `api.IsPlayerMoving` | `nil` | `compat.lua:1321-1354` |
| `api.IsSpellUsable` | `nil` | `compat.lua:528-539` |

Client predicates verified on `origin/forever` (so the risk is real, not a
hypothesis): `UnitPower` `SecretWhenUnitPowerRestricted`
(`UnitDocumentation.lua:2732-2747`), `UnitPowerMax` `:2801-2824`, `UnitHealthMax`
`SecretWhenUnitHealthMaxRestricted` `:1472-1475`, `UnitHealth` `SecretReturns =
true` `:1526-1529`, `UnitGUID` `SecretWhenUnitIdentityRestricted`
`:1241-1243`, `UnitIsUnit` `SecretWhenUnitComparisonRestricted` `:2410-2415`,
`UnitAttackSpeed`/`UnitRangedDamage` `SecretWhenUnitStatsRestricted` `:682-684`,
`:2962-2964`, `GetSpellCooldown` `SecretWhenCooldownsRestricted`
(`SpellDocumentation.lua:157,259,294,...`), aura reads `SecretWhenUnitAuraRestricted`
(`UnitAuraDocumentation.lua:112-193`), `GetTotemInfo`
`SecretWhenTotemSlotSecret` (`TotemDocumentation.lua:62,84`), and the
`C_Secrets` predicates `ShouldUnitAuraIndexBeSecret` / `ShouldAurasBeSecret` /
`ShouldUnitIdentityBeSecret` / `ShouldUnitPowerBeSecret`
(`SecretPredicateAPIDocumentation.lua:119,220,305,321`).

**Which family reaches which branch:** the legacy `UnitAura` global on Forever is
defined only in `Blizzard_Deprecated/Classic/Deprecated_1_15_8.lua`
(`[AllowLoadGameType classic]`, `Blizzard_Deprecated.toc`), so Forever does **not**
load it and `compat.api.UnitAura` takes the `C_UnitAuras` precheck+pcall branch
(`compat.lua:762-786`) — the unguarded classic pass-through (`:751-761`) cannot see
a secret on Forever. Verified; not a finding.

### 1.2 The Forever guide's two-path cooldown read

- **Safe path:** `live_cooldown` reads the fifth return and latches
  `restricted_seen` → `out.inputs_unknown` (`forever_guide.lua:1454-1477`,
  `:1663-1684`); `FG.get_hud_state` does the same for HUD slots
  (`forever_guide.lua:472-501`, `:594-597`).
- **Unsafe path:** the bridge trusts a raw input field before it ever does the
  safe read (`forever_guide.lua:1593-1630`: `local v = raw[key]; if v ~= nil then
  … return v`). The class `gather_guide_inputs` writes exactly those fields from
  2-value cooldown reads. Because `0` is truthy in Lua, a restricted read's `0`
  wins forever; `is_ready(0)` is true (`forever_guide.lua:14-32`).

Offline probe (loadfile `forever_guide.lua` + stub `st.api`, `/tmp`; not committed)
with `GetSpellCooldown = function() return 0,0,0,0,true end`:

```
PALADIN raw-zero judge_remaining=0 : action=judge      judge_call=true  unknown=false
PALADIN judge_remaining absent(nil) : action=judge      judge_call=true  unknown=true
HUNTER  raw-zero arcane_remaining_cd : action=arcane     unknown=false
HUNTER  arcane cd absent(nil)        : action=arcane     unknown=true
WARRIOR prot rage=nil cds-readable   : action=nil hold=true text=HOLD unknown=false
DRUID bear rage=nil cds-readable     : action=enrage    unknown=false
WARRIOR arms rend row unreadable     : action=rend      unknown=false
HUNTER mark row unreadable           : action=hunters_mark unknown=false
```

The contrast is the finding: when the field is **absent**, the bridge's own safe
read sets `inputs_unknown` (UI shows `…`); when the class gather wrote `0`, the
same restricted read produces **confident wrong advice**.

---

## 2. Ranked findings

### H1 — Restricted player power is consumed as `0` / `0 %`, so the guide advises from a fact it does not have

- **Category:** wrong advice + feature silently disappears. **Confidence:** code
  HIGH; trigger HIGH (the operator's power-bar report is direct evidence that the
  Forever power read is restricted in play — `bench/powerbar_secret_2026-11-06.md`
  §1/§7; `C_Secrets.ShouldUnitPowerBeSecret` exists on `origin/forever`).
- **Degraded input:** `api.UnitPower`/`UnitPowerMax` → `nil`
  (`compat.lua:599-624`), because `UnitPower` is `SecretWhenUnitPowerRestricted`.
- **Current consumer behaviour:**
  - Warrior: `inputs.rage = api.UnitPower("player")` (`classes/warrior.lua:4048`)
    → nil; `FG.evaluate_warrior` does `rage = type(inputs.rage) == "number" and
    inputs.rage or 0` (`forever_guide.lua:681`). Every rage gate (`>= 10/15/20/25/30`,
    e.g. `:704`, `:707`, `:710`, `:753`, `:756`) fails and the fallthrough is
    `out.hold = true; out.hold_text = "HOLD"` (`forever_guide.lua:830-833`).
    No `inputs_unknown` is set (warrior gather sets none — grep: only paladin and
    rogue set it).
  - Paladin: `get_guide_mana_pct` returns **0** on an unreadable pair
    (`classes/paladin.lua:2504-2513`), `inputs.mana_pct` (`:3538`) → FG normalises
    `type(...) or 100` (`forever_guide.lua:867`) but the input is `0`, so every
    mana-gated row (`>= 10/15/20/25`: `:893`, `:896`, `:899`, `:902`, `:908`,
    `:983`, `:986`, `:1019`, `:1022`) can never fire.
  - Druid: bear `rage = … or 0` (`forever_guide.lua:1240`) and a rage-free
    `Enrage` condition `rage < 20` (`:1249-1251`) → **Enrage is cued** purely
    because the read was restricted (probe above: `action=enrage`).
  - Hunter/shaman: `mana_frac`/`mana_fraction` nil → FG defaults to `100 %`
    (`forever_guide.lua:1045`, `:1367`), so mana gates always pass (lax rather
    than silent; e.g. Serpent Sting may be cued at unknown/OOM).
- **User-visible effect:** on Forever with restricted power the warrior guide
  sits on **HOLD** with no unknown marker (looks like "nothing to use"), the
  paladin loses Consecration/Exorcism/Holy Shock/Holy Shield/Holy Strike rows
  entirely, and the bear druid is told to **Enrage** at an unknown rage value.
- **Minimal fix:** do not let a degraded power read reach the engine as a number.
  In each class gather, when `type(power) ~= "number"` set
  `inputs.inputs_unknown = true` (the rogue pattern, `classes/rogue.lua:1337-1340`)
  and leave the field nil; keep the FG `or 0/100` defaults as direct-caller
  conveniences but gate them on `inputs.inputs_unknown ~= true`. Do **not** change
  `api.UnitPower` (its nil contract is pinned by `tests/secret_guard_state.lua`).
- **Test that would pin it:** a `forever_guide_state`/`forever_hud_gate_state` case
  with `inputs.rage = nil` (and a stub `api.UnitPower = function() return nil end`)
  asserting `out.inputs_unknown == true` and NOT `hold_text == "HOLD"`; a
  paladin case with `mana_pct` absent-restricted asserting the fillers are not
  promised either way; mutation: restore `or 0` → red.

### H2 — Power reads but cooldown reads restricted: class gathers publish `0` (ready) and the Forever bridge trusts it

- **Category:** wrong advice. **Confidence:** code HIGH (proven offline); trigger
  MED — `SecretWhenCooldownsRestricted` is contextual (combat/encounter/PvP) and
  not yet observed in-client by this desk.
- **Degraded input:** `api.GetSpellCooldown` → `0,0,0,0,true`
  (`compat.lua:462-464`, `:501-503`).
- **Current consumer behaviour (the exact bypass):**
  - Paladin `get_guide_cooldown_remaining`: `duration == 0` → `return 0`
    (`classes/paladin.lua:2462-2497`, the `:2468-2469` arm). The gather writes
    `cs_remaining`/`judge_remaining` (`:3452`, `:3460` — note `judge_rem or 999`
    keeps `0`, since `0` is truthy), `cons_remaining`/`exo_remaining`
    (`:3634-3635`), `holy_shield_remaining` (`:3718`), `as_remaining` (`:3727`),
    `holy_strike_remaining` (`:3734`), `how_remaining` (`:3802`).
  - Hunter `get_guide_cooldown`: `duration <= 1.51` → `0,nil`
    (`classes/hunter.lua:2709-2726`). Gather writes `steady_remaining_cd` (`:3401`),
    `multi_remaining_cd` (`:3441`), `arcane_remaining_cd` (`:3483`),
    `hawk_remaining_cd` (`:3510`), `sniper_remaining_cd` (`:3519`).
  - Shaman `get_guide_cooldown`: `0` (`classes/shaman.lua:2894-2909`); gather
    writes `shock_remaining` (`:3314`), `bloodlust_remaining`/`frostshock_remaining`
    (`:3487-3504`), `magma_remaining` (`:3521-3529`).
  - Druid `guide_cooldown_remaining`: `0` (`classes/druid.lua:2244-2253`);
    `frenzied_regen_remaining` (`:2942`) reaches the bear rule
    (`forever_guide.lua:1247`).
  - Rogue `spell_cooldown`: restricted → `nil` (`classes/rogue.lua:392-409`),
    written as `ar_cd_remaining`/`vanish_cd_remaining` (`:1226-1324`). The Forever
    rogue rules do not read those two, so this one is HUD/practice-only today.
- **User-visible effect:** the guide confidently cues Judgement (the paladin's
  top row), Consecration/Exorcism/Hammer of Wrath, Arcane Shot/Multi-Shot/Sniper
  Shot/Hawk upkeep, Flame Shock, Frenzied Regeneration — while the ability is
  actually on cooldown — and shows **no** `…` unknown state
  (probe: `unknown=false`). Pressing the cued ability is a no-op.
- **Minimal fix:** (a) every class cooldown helper must read the fifth return and,
  when `restricted == true`, return nil **and** record
  `self.<class>_restricted_cooldowns = true` for the tick; (b) the gather sets
  `inputs.inputs_unknown = true` from that flag (M6). Returning nil alone is not
  enough: the engine's `is_ready(nil)` is **true** (`forever_guide.lua:31`), so a
  nil-only fix would still cue "ready". Keep `live_cooldown`/`get_hud_state`
  unchanged (they are correct). The engine should additionally refuse if an
  input field was written as `0` *and* the tick's restricted flag is set (belt and
  braces for any field the gather misses).
- **Test that would pin it:** `tests/forever_guide_state.lua` (or a new
  `forever_secret_consumers_state.lua`) with `api.GetSpellCooldown → 0,0,0,0,true`
  and a paladin/hunter gather run through the real class entry point: assert
  `out.inputs_unknown == true` and `out.action == nil`; pin the helper contract
  ("a restricted read never returns 0") at source-shape level; mutation: drop the
  fifth-return read → red.

### H3 — Forever Hunter's Mark "unknown" branch is unreachable, so a restricted/absent target aura re-cues Hunter's Mark forever

- **Category:** wrong advice. **Confidence:** code HIGH (proven offline); trigger
  MED (target auras are `SecretWhenUnitAuraRestricted`; the aura list can be
  restricted while individual indices are readable).
- **Current behaviour:** `live_hunters_mark` (`forever_guide.lua:1500-1514`) does
  `local remaining = api.scan_unit_aura(...)` then `result = remaining ~= nil` —
  a boolean — then `memo.hunters_mark = result == nil and "unknown" or result`.
  `result == nil` is impossible, so the `"unknown"` → `nil` conversion in the
  bridge (`forever_guide.lua:1607-1610`) is dead code. `scan_unit_aura` returns
  `nil,nil` both for "not found" and "the list could not be read"
  (`compat.lua:867-902`; its own header says callers must treat nil as unknown).
- **User-visible effect:** under a restricted target aura list the Forever hunter
  guide returns `hunters_mark` every tick ("Hunter's Mark" is the first row of the
  ranged priority, `forever_guide.lua:1104-1108`) and the player is told to re-mark
  a target that is already marked. It also masks the actual next action. Proven:
  probe output `HUNTER mark row unreadable -> action=hunters_mark unknown=false`.
- **Minimal fix:** make the unknown real: `if remaining == nil then local p =
  api.auras_may_be_secret; if type(p) == "function" and p() == true then return
  nil end return false end return true`. The bridge already turns the "unknown"
  memo into `nil` (which withholds the row): return nil from the function, or set
  `memo.hunters_mark = "unknown"` and let `:1607-1610` do it.
- **Test:** `forever_guide_state` hunter case: `scan_unit_aura` stub returning
  nil + `auras_may_be_secret` returning true → `evaluate("HUNTER")` must not
  return `hunters_mark`; with `auras_may_be_secret` false the same nil still means
  "absent" and the cue is correct. Mutation: restore the boolean-only result → red.

### H4 — Restricted target-aura rows are read as "debuff absent": Rend/Rip/Rake/Flame Shock are re-cued, JotC bar hides

- **Category:** wrong advice + feature silently disappears. **Confidence:** code
  HIGH (probed for Rend); trigger MED.
- **Degraded input:** `api.UnitAura("target", …)` returns `nil` for a restricted
  row (`compat.lua:762-786`); the walk continues (no break) but the match is
  simply not found, and every one of these consumers maps "not found" to
  "absent".
- **Current consumer behaviour:**
  - Warrior `get_rend_debuff_window` (`classes/warrior.lua:3933-3960`) → nil;
    gather writes `inputs.rend_remaining` (`:4546-4548`); the FG alias
    `rend_active` returns `positive(nil) == true` = false
    (`forever_guide.lua:1521-1524`), so the arms/fury/prot Rend rows
    (`:730`, `:763`, `:817`, `:841`) fire. Probe: `action=rend unknown=false`.
    (The class's own FCFS engine has the same shape at `classes/warrior.lua:4679-4681`.)
  - Druid: `druid_debuff_found` is cleared and set only by the target scan
    (`classes/druid.lua:1288-1310`); `get_guide_debuff_remaining`
    (`:2184-2190`) → nil; aliases `rip_active`/`rake_active`
    (`forever_guide.lua:1535-1536`) → false; cat rules re-cue Rip/Rake
    (`forever_guide.lua:1308`, `:1322`).
  - Shaman: `scan_target_debuffs` (`classes/shaman.lua:1856-1885`) → nil;
    `inputs.flameshock_remaining` (`:3240-3252`); alias `flameshock_active`
    (`forever_guide.lua:1570-1573`) → false; Flame Shock rule fires
    (`:1374`).
  - Paladin: `get_guide_jotc_remaining` (`classes/paladin.lua:2410-2446`) and
    `pulse_jotc_scan` (`:2820-2846`) → `jotc_tracked=false` → the JotC bar hides
    (`:2937-2960`) even while the debuff is up (display-only).
- **User-visible effect:** wrong advice (re-apply an upkeep that is already up,
  spending a GCD and displacing the real action) and a hidden JotC bar. The
  rogue and shaman-lust consumers already gate this with
  `api.auras_may_be_secret()` (`classes/rogue.lua:373-390`, `:846-878`;
  `classes/shaman.lua:1888-1932`); the paths above do not.
- **Minimal fix:** the same M6 discipline at the gather: when
  `api.auras_may_be_secret() == true` and an upkeep read is missing, set
  `inputs.inputs_unknown = true` (and keep the field nil). Per class this is one
  branch beside the existing scan. Do not probe per-frame; the class gathers
  already run at the guide cadence, and the probe is pcall-cached in compat.
- **Test:** per class, stub `api.UnitAura` to return nil rows and
  `api.auras_may_be_secret` to return true → the gather sets `inputs_unknown` and
  the FG evaluate returns no upkeep cue; a second leg with the probe false keeps
  today's cue (absent really is absent). Mutation: drop the probe → red.

### H5 — The three `hunter_ui` aura scans break on a restricted row

- **Category:** feature silently disappears. **Confidence:** code HIGH; trigger
  MED (per-index aura restriction is exactly the case the compat precheck exists
  for — `C_Secrets.ShouldUnitAuraIndexBeSecret`, `compat.lua:734-749`).
- **Degraded input:** `api.UnitAura` → `nil` for a restricted row.
- **Current behaviour:** three loops still use the pre-R2 shape
  `if not name then break end`:
  - Rapid Fire bar scan — `hunter_ui.lua:1273-1283` (scan limit 40, `:77`).
  - Frenzy stacks badge (pet auras) — `hunter_ui.lua:1405-1418`.
  - Aspect icon (player auras) — `hunter_ui.lua:1758-1772`.
  Any restricted row *above* the tracked aura truncates the walk. The RF bar then
  takes its "no Rapid Fire" path (readiness `2x` badge or hide), the aspect icon
  hides, the Frenzy badge hides. RF bar and aspect icon are **default ON**
  (`config_presets.lua:579-580`); the badges are opt-in.
- **User-visible effect:** a live Rapid Fire buff is not displayed on Forever; the
  aspect icon disappears while an aspect is up; Frenzy stacks vanish. No unknown
  state (`auras_may_be_secret`) is consulted.
- **Minimal fix:** remove the early `break` and let the 40-row cap bound the walk
  (the same R2 rule every class module already follows), or use
  `api.scan_player_aura`/`scan_unit_aura` where the scan only needs
  remaining/stacks (BW badge already does, `hunter_ui.lua:1360-1364`). RF needs
  duration+expiration, so the no-break walk is the minimal change. Optionally,
  after the walk, if a delta between "rows walked" and "names seen" is observed
  and `api.auras_may_be_secret() == true`, render the existing unknown face.
- **Test:** `hunter_state` (sandbox) with `api.UnitAura` returning nil at index 1
  and the RF buff at index 3 → the RF bar must show the buff (or its 2x state must
  not be forced); mutation: re-add `break` → red.

### H6 — Direct `UnitGUID("target")` comparisons throw (hunter queue tint, druid TTD sampler)

- **Category:** would throw. **Confidence:** code HIGH (comparison on a secret
  raises — the regime's contract, `compat.lua:165-171`); trigger UNVERIFIED
  (`UnitGUID` is `SecretWhenUnitIdentityRestricted`, `origin/forever:
  UnitDocumentation.lua:1241-1243`).
- **Current behaviour:**
  - Hunter: `ST.HUNTER.maintain_queue_tint` (`classes/hunter.lua:1364-1390`) does
    `clear = UnitGUID("target") ~= self.hunter_tint_target` (`:1375`) with only a
    `type(UnitGUID) == "function"` guard — and `type()` does **not** catch a secret
    (compat's own note, `compat.lua:165-171`). The tint snapshot stores the raw
    secret at `:1582`/`:1589`. It runs from `ST.HUNTER.on_bar_update`
    (`classes/hunter.lua:1393-1407`) on every bar tick while a Raptor Strike /
    Steady Shot queue is armed — `enable_raptor_strike_color = true` by default
    (`config_presets.lua:551`), and Raptor Strike is a Forever APL move.
  - Druid: the module captures the bare global as a local
    (`local unit_guid = UnitGUID`, `classes/druid.lua:331`) and the TTD sampler
    does `local guid = unit_guid and unit_guid("target")` (`:2389`), then
    `if guid ~= self.druid_ttd_guid` (`:2397`). `type(guid) ~= "string"` at
    `:2390` passes for a secret string, so the comparison is the first secret
    operation. The sampler is called from the guide gather
    (`classes/druid.lua:2587`) and the TTD label (`:1762`) every guide tick.
- **User-visible effect:** any restricted target identity raises inside the class
  hook/gather; `bars.lua` runs the hook under `st.guard.run` (25-throw quarantine,
  `bars.lua:1282-1292` + `guard.lua:112-130`), so the site dies after ~25 frames
  with one chat line: the hunter queue tint and the druid TTD readout disappear for
  the session. This is the "one restricted read silently removes functionality"
  shape at its worst — plus a chat error.
- **Minimal fix:** use `api.UnitGUID("target")` (already nils a secret) at
  `classes/hunter.lua:1375`, `:1582`, `:1589` and replace the druid local with
  `st.api.UnitGUID`; compare only when the wrapper answered:
  `local tguid = api.UnitGUID("target"); if tguid ~= nil and tguid ~=
  self.hunter_tint_target then clear = true end` (an unknown target keeps the tint
  until the cycle-end backstop clears it) and in the druid sampler `if guid == nil
  then reset; return nil end`. This also removes the AGENTS "never call a
  cross-client API directly" violation.
- **Test:** `tests/hunter_state.lua` / `tests/druid_state.lua` sandbox: stub the
  global to return an opaque sentinel whose `__eq` raises, assert the functions do
  not throw and keep/reset state on unknown; mutation: restore the direct compare
  → the sentinel throw reproduces (pin at source-shape level since plain Lua has
  no secrets).
- **Test:** `tests/hunter_state.lua` sandbox: stub `UnitGUID` to return an opaque
  sentinel whose `__eq` raises, assert `maintain_queue_tint` does not throw and
  keeps the tint on unknown; mutation: restore the direct compare → the sentinel
  throw reproduces (pin at source-shape level since plain Lua has no secrets).

### M1 — Direct `UnitIsUnit` comparison can throw in the target-of-target warning

- **Category:** would throw. **Confidence:** code HIGH; trigger UNVERIFIED
  (`SecretWhenUnitComparisonRestricted`, `origin/forever:UnitDocumentation.lua:
  2410-2415`).
- **Current behaviour:** `ST.HUNTER.get_target_warning`
  (`classes/hunter.lua:1614-1629`) calls `UnitIsUnit("targettarget","player")`
  directly and compares the return (`yours == nil`, `yours == true`). A restricted
  comparison return is opaque and `==` raises before the nil/true tests. It is
  called per frame from `hunter_ui.update_target_warning`
  (`hunter_ui.lua:1138-1148`) under the `target_warning` guard site; the widget is
  opt-in (`db.hunter_target_warning_enabled == true`).
- **User-visible effect:** the ToT warning site is quarantined after repeated
  throws (and the warning never shows) exactly when comparisons are restricted —
  PvP-ish contexts, the context the widget exists for.
- **Minimal fix:** add `api.UnitIsUnit` to compat (`pcall` the call, `is_secret`
  the result → nil) and use it here; treat nil as unknown (widget hidden).
- **Test:** `hunter_state`: stub the global to return an opaque sentinel (raising
  `__eq`) → `get_target_warning` returns nil and does not throw; source-shape pin
  that no direct `UnitIsUnit(` remains.

### M2 — Restricted target health silently removes execute-phase advice

- **Category:** feature silently disappears. **Confidence:** code HIGH; trigger
  MED.
- **Degraded input:** `UnitHealthMax` `SecretWhenUnitHealthMaxRestricted`;
  `UnitHealth` `SecretReturns` — compat nils both (`compat.lua:687-712`).
- **Current behaviour:** paladin `get_guide_target_health_pct`
  (`classes/paladin.lua:3267-3279`) → nil → `inputs.target_health_pct = nil`
  (`:3796-3800`) → FG defaults `100` (`forever_guide.lua:868`), so the Hammer of
  Wrath rows (`target_hp < 20`, `:905`, `:947`, `:974`, `:1016`) never fire.
  Warrior gather (`classes/warrior.lua:4059-4067`) → nil → FG `hp_pct = 100`
  (`:682`) → Execute never fires; the class's own execute fraction
  (`:2190-2201`) and the HUD execute tint (`:5134-5149`) both return
  nil/false. Hunter `target_hp_frac` (`:3487-3493`) is nil (Forever rows do not
  consume it today).
- **User-visible effect:** on Forever the execute phase is invisible to the
  guide/tint — a real functionality loss with no unknown marker (the guide looks
  confident while withholding the phase).
- **Minimal fix:** when the health pair is restricted, set
  `inputs.inputs_unknown = true` in the gather (one line) so the guide shows `…`
  instead of silently dropping the phase; alternatively add a dedicated
  `execute_unknown` advisory. Do not guess a fraction.
- **Test:** forever guide/hud gate state: `api.UnitHealth/Max = nil` → the
  gather sets `inputs_unknown`; mutation: remove → red.

### M3 — Display-only restricted cooldown reads: paladin marker/CD row, shaman badges and WF-hold wash, hunter window sync

- **Category:** feature silently disappears, plus one actively-wrong visual.
  **Confidence:** code HIGH; trigger MED.
- **Current behaviour:**
  - Paladin Judgement swing marker (default ON: `judgement_marker_enabled ~=
    false`): `classes/paladin.lua:1320-1335` reads the Judgement cooldown
    `start_time, duration`; restricted `duration=0` → no marker (`marker:Hide()`
    path) — the marker silently vanishes mid-swing.
  - Paladin CD-icon row (opt-in `cd_icons_enabled == true`, `option_tables.lua:
    2726`): `cd_slot_remaining` (`classes/paladin.lua:3033-3050`) treats the
    restricted read as ready → the icon shows no swipe (looks off cooldown).
  - Shaman SS/SR badges: `classes/shaman.lua:2101-2163` →
    `st.weave.get_cooldown_remaining(0,0,now)` returns nil
    (`weave.lua:545-553`) → badges hide; the WF-hold term uses
    `not ss_remaining` (`classes/shaman.lua:2120-2128`, `:2182-2196`) so a
    restricted Stormstrike read **can falsely arm the "SS HOLD" wash** (opt-in
    `show_shaman_wf_hold_tint`).
  - Hunter Auto Shot window sync: `classes/hunter.lua:1059-1066` — restricted
    `0,0,0` returns early, the window keeps the previous sync (degrades, no
    throw).
- **User-visible effect:** a default-on marker disappears; opt-in cooldown
  displays show "ready" when the timing is unknown; the shaman hold wash can
  advise a hold on a Stormstrike that is actually on cooldown.
- **Minimal fix:** read the fifth return in these helpers; treat `restricted` as
  unknown (hide the marker/badge/wash, no "ready" inference). For the shaman
  wash, do not treat a restricted read as "not on cooldown".
- **Test:** `hud_state`/`shaman_state` with `api.GetSpellCooldown → 0,0,0,0,true`:
  assert the wash is not armed and the cooldown row/marker shows no fabricated
  swipe; mutation: drop the flag → red.

### M4 — Practice scenario context inherits the gather's restricted→0 cooldowns

- **Category:** wrong advice (practice grade). **Confidence:** code MED; trigger
  UNVERIFIED.
- **Current behaviour:** `practice_ui.lua:5010-5031` prefers a class
  `practice_context` (hunter/paladin/rogue have one) and otherwise (druid,
  shaman, warrior) calls `module.gather_guide_inputs` and lifts every
  `*_remaining`/`*_remaining_cd` **number** into `ctx.cooldowns` (`:5069-5081`).
  A restricted cooldown is a `0` (H2), so it is published as "ready"; the
  scenario decision then reads it (`classes/warrior.lua:6380`,
  `classes/druid.lua:3751`, `classes/hunter.lua:4817`, …). `scenario_open_step`
  (`practice_ui.lua:5409-5424`) already knows how to record an UNKNOWN step when
  the class cannot decide — it is just never told the input was unreadable.
- **User-visible effect:** in the practice scenario/drips on Forever, the
  expected action (and therefore the grade) can be based on a cooldown that was
  never actually read. Practice mode's own simulated cooldowns are separate and
  unaffected; the exposure is the scenario/drill decision path.
- **Minimal fix:** do not lift `0` values whose source was restricted — carry the
  gather's per-tick restricted flag into `ctx` (e.g. `ctx.cooldowns_unknown`) and
  have the class decision return "cannot decide" (nil ⇒ UNKNOWN step, no grade)
  when it would depend on one.
- **Test:** practice_ui state suite with a stub gather returning
  `arcane_remaining_cd = 0` + the restricted flag → the scenario step is UNKNOWN
  (no attempt), not graded against a wrong action; mutation: drop the flag → red.

### M5 — Retail residual: the same secret regime, but the restricted-aware providers are Forever-only

- **Category:** wrong advice + silent disappearance (second target).
  **Confidence:** code HIGH; trigger UNVERIFIED (Retail 12.x secret restrictions;
  no client evidence in this repo).
- **Current behaviour:** `hud.lua:553-560` selects the `forever_guide` provider
  only when `st.family == "FOREVER"`; `nextaction_ui.lua:321-322` does the same for
  guide slots. On Retail the class providers/gathers run — the H1/H2/H4/M2 paths
  above — with no restricted handling, because all 2.1.8 work was Forever-gated
  (`bench/powerbar_secret_2026-11-06.md` §2, `bench/display_fix_2026-11-06.md`).
  `st.is_mainline` is true on Retail (`compat.lua:124`), so the compat degradation
  is active there too.
- **User-visible effect:** on Retail 12.x, a restricted cooldown/power/aura read
  would be consumed exactly as the pre-2.1.8 code did: "ready", `0`, "absent".
- **Minimal fix:** move the restricted-aware contract into the shared layer rather
  than the Forever provider: class gather cooldown helpers read the fifth return
  and set `inputs_unknown` (same fix as H2, benefits every family); HUD class
  providers gain the `restricted` state `HUD.paint` already understands
  (`hud.lua:1213`). No behavioural change on classic clients (the flag is nil).
- **Test:** engine matrix / hud state: run one class provider with
  `GetSpellCooldown → 0,0,0,0,true` on a non-Forever mainline profile and assert
  the HUD/guide does not claim ready. (The offline suites can model the family;
  the in-client trigger stays unverified.)

### M6 — `UnitCreatureType` compared directly in the Forever HUD provider

- **Category:** would throw (guarded). **Confidence:** code HIGH; trigger UNVERIFIED
  (`UnitCreatureType` is `SecretWhenUnitIdentityRestricted`,
  `origin/forever:UnitDocumentation.lua:1030-1045`).
- **Current behaviour:** `forever_guide.get_hud_state`'s Exorcism glow branch
  (`forever_guide.lua:550-559`) does `local ct = UnitCreatureType("target")` and
  compares `ct == "Undead"` / `ct == "Demon"`. The call is direct (not via compat)
  and the comparison is the first secret operation. It runs for the paladin
  Exorcism HUD icon every tick on Forever (`hud.lua:1413-1426` calls the provider
  per icon). Note the paladin class already guards the same read
  (`classes/paladin.lua:2516-2526`, local `is_secret`); the Forever provider did
  not.
- **User-visible effect:** when identity is restricted, the Exorcism icon's
  provider throws each tick; the HUD's per-icon `guard.run` counts and quarantines
  that site after 25 throws (one chat line) — the slot's state (glow, and the
  provider's other fields for that icon) is lost rather than shown wrong. Not an
  addon-killer, but a silent feature loss plus a chat error.
- **Minimal fix:** guard the read the way the class does: reuse a local
  `is_secret = issecretvalue or function() return false end` in
  `forever_guide.lua` and treat a secret as unknown (no glow); or add
  `api.UnitCreatureType` to compat and call it. Do not compare a secret string.
- **Test:** `forever_hud_gate_state` paladin Exorcism case with `UnitCreatureType`
  stubbed to return an opaque sentinel (raising `__eq`) → `get_hud_state` returns
  a state, does not throw, no glow; mutation: restore the direct compare → red.

### L1 — Direct player-identity reads outside compat

- **Category:** rule violation / latent throw. **Confidence:** HIGH code, no
  current secret risk: `UnitGUID("player")` and `UnitClass("player")` are the
  player's own identity and the Mainline predicate is for **other** units.
- **Sites:** `main.lua:577` (`UnitGUID("player")`), `main.lua:1176-1177`
  (`UnitGUID("player")`, `UnitGUID("target")` in the CLEU noise filter),
  `classes/paladin.lua:996` (`UnitGUID("player")` in the CLEU twist handler),
  `hud.lua:139` (`local unit_guid = rawget(_G, "UnitGUID")`, player read at
  `HUD.on_aura_applied` and CLEU-only), `LibGlobalCooldown.lua:195`
  (`UnitClass("player")`), `utils.lua:65`, `option_tables.lua:79`, `:156`,
  `main.lua:413`. The `main.lua:1177` target-GUID compare is unreachable on
  Mainline because CLEU registration is gated (`main.lua:765`) and
  `api.CombatLogGetCurrentEventInfo` is absent there; `hud.lua`'s CLEU arm is
  gated the same way (`hud.lua:663-676`), and the paladin's CLEU handler is
  classic-only. All remaining player reads are identity of the player unit, which
  the Mainline predicate does not restrict.
- **Effect:** none observed today; a future refactor that reaches the target
  branch on a mainline client would throw (secret target GUID).
- **Minimal fix:** use `api.UnitGUID` for the target read (the wrapper already
  nils a secret) and leave the player reads as-is or route them too for
  consistency.
- **Test:** `wiring_check` source-shape pin: no `UnitGUID("target")` outside
  compat.

### L2 — `swing_source.lua` reads stats directly (guarded, but bypasses `st.api`)

- **Category:** rule violation. `swing_source.lua:256-272`, `:329-345`,
  `:384-400` call `UnitAttackSpeed`/`UnitRangedDamage` directly with
  `pcall` + `is_secret` guards (`is_secret` at `:38`). Behaviour is compliant;
  the AGENTS contract ("Never call a cross-client API directly elsewhere") is not.
- **Minimal fix:** use `api.UnitAttackSpeed`/`api.UnitRangedDamage` (they already
  nil secrets, `compat.lua:1113-1141`) and drop the duplicate guards.
- **Test:** wiring/source pin for direct stat reads outside compat.

### L3 — `api.GetCombatRating`/`GetCombatRatingBonus` are raw pass-throughs

- **Category:** latent. `compat.lua:1358-1373` returns the client values
  unguarded; the only consumer, `LibGlobalCooldown.lua:34-46`, re-guards with its
  own `is_secret` + `pcall`. No current defect (both call sites are safe).
- **Minimal fix:** wrap in compat (`is_secret` → nil) and keep the lib guard as
  belt-and-braces.
- **Test:** `secret_guard_state` pair for the rating readers.

### L4 — No `/st diag` receipt for restricted cooldowns/auras

- **Category:** observability. `diag.lua:845-856` renders `value=restricted` only
  for power. A silent restricted cooldown/aura state is indistinguishable from a
  real "nothing to do" in the operator's diag paste, which is exactly how the
  remaining UNVERIFIED triggers would be closed.
- **Minimal fix:** count restricted results in `api.GetSpellCooldown` (a module
  counter is enough; no per-call string work) and render
  `cd_restricted=<n>` / `aura_restricted=<true|false>` in `print_runtime_diag`;
  include `auras_may_be_secret()`'s value.
- **Test:** `diag_state` exact-string pin for the new tokens; mutation: return ""
  → red.

### L5 — HUD restricted face has no explicit marker

- **Category:** UX. `HUD.paint` correctly never fabricates a timer/swipe/text for
  a restricted state (`hud.lua:1213`, `:1227-1262`, `:1267-1305`) and forces
  desaturation (`:1307-1313`), but the only cue is "grey with no swipe". The
  guide says `…`, the power bar `?`, the range bar `--`.
- **Minimal fix (operator decision, display-only):** draw a constant `?` in the
  icon's text font string (the power bar precedent, `power_bar.lua:414-415`) when
  `restricted` is true; no arithmetic, no new db key required.
- **Test:** `hud_state` pin: restricted state → text is `?` and no cooldown swipe
  set.

---

## 3. Verified clean (the assurance half)

These were checked and do **not** need a fix; recording them so the next pass does
not re-open them.

1. **Aura walks in the class modules/hud are R2-fixed.** All `api.UnitAura` loops
   in `classes/paladin.lua:603-660` and `:2429-2445`, `classes/druid.lua:1294-1310`
   and `:1400-1415` and `:2963-2978`, `classes/shaman.lua:798-…` and `:1861-…`,
   `classes/warrior.lua:1467-1480`, `:2370-2390`, `:2427-2442`, `:3938-3950`,
   `:3980-3995`, `classes/rogue.lua:340-368`, `hud.lua:308-328`,
   `forever_guide.lua:1506-1511` use the no-break shape (`while i <= 40`, process
   when `name ~= nil`, always advance). Only the three `hunter_ui` loops remain
   (H5).
2. **The Forever HUD is restricted-aware.** `FG.get_hud_state` keeps
   `remaining/duration` at 0 and sets `restricted=true` when no readable duration
   exists (`forever_guide.lua:472-501`, `:594-597`); `HUD.paint` then skips the
   swipe, the text, and forces desaturation (`hud.lua:1213-1313`). No fabricated
   "ready" and no stale value.
3. **The guide's M6 unknown path works** where it is fed: `inputs_unknown`
   suppresses action/filler/judge/hold and paints `…` (`nextaction_ui.lua:629-718`,
   `:761-775`); the gather/evaluate failure paths set it
   (`nextaction_ui.lua:885-913`); restricted reads through `live_cooldown` set it
   (`forever_guide.lua:1454-1477`, `:1683-1685`). The defect is that the class
   gathers never feed it (H1/H2/H4).
4. **Power bar** is the reference implementation: raw `api.GetPlayerPower`, a real
   StatusBar, `?` label, restricted before any type/compare gate
   (`power_bar.lua:469-508`, `:382-434`, `:414-415`); `diag` renders
   `value=restricted fraction=?` (`diag.lua:845-856`, `:806`).
5. **Range bar** renders an explicit unknown face (`weave_range.lua:93`,
   `:460-500`, `wr.last_reason="unknown-distance" :470`) instead of hiding.
6. **`LibGlobalCooldown` is clean** despite the direct-looking `GetSpellCooldown`
   text: it aliases the compat wrapper (`LibGlobalCooldown.lua:53`), the wrapper
   never returns a secret, and both call sites early-out on `duration == 0`
   (`:158-165`, `:237-240`). Ratings are locally secret-guarded (`:34-46`).
7. **`enemy_swing` cannot see a secret**: gated to CLEU families only
   (`enemy_swing.lua:55-65`, activation at `:644`), so its direct
   `UnitGUID`/`UnitName` (`:310`, `:317`) are classic-only.
8. **Gating is correct.** All `C_Secrets` probing is inside compat, `rawget`-based,
   `pcall`ed, and only an exact `true` skips a read
   (`compat.lua:738-749`, `:911-925`); the duration-object fallback is
   `st.is_mainline`-gated (`:456`). `st.is_mainline` gates in `main.lua`/`hud.lua`
   cover CLEU/autorepeat/PLAYER_TARGET_SET_ATTACKING, which genuinely do not
   exist on Mainline (`main.lua:726-741`, `:765`, `:2286`, `:2377`;
   `hud.lua:663-676`; `classes/warrior.lua:2593`) — no Forever feature is gated
   off by it. Classic clients cannot accidentally enter a secret branch
   (`issecretvalue` absent → local `return false`; `C_Secrets` absent → nil
   probes).
9. **`check_weapons` A-3 fix holds**: only a readable number moves
   `has_weapon`/`has_oh` (`main.lua:986-1012`); the old `x or 0` shapes are gone
   repo-wide (grep).
10. **Health/power consumers are type-guarded** at every site I read:
    `classes/rogue.lua:757-760`, `:797-830`; `classes/druid.lua:508-560`,
    `:1515-1530`, `:1646-1685`, `:2399-2415`, `:2505-2545`, `:2946-2952`;
    `classes/warrior.lua:1183-1196`, `:2190-2201`, `:3415-3428`, `:4059-4067`,
    `:5134-5149`, `:6544-6550`; `classes/paladin.lua:2504-2513`, `:3267-3279`;
    `classes/hunter.lua:1877-1888`, `:3487-3493`, `:2569-2590`;
    `classes/shaman.lua:1238-1300`, `:3296-3305`; `forever_guide.lua:562-580`.
    No nil arithmetic was found on a compat-returned value. The exceptions are
    **identity** reads that bypass compat entirely (H6/M6/L1) — those are the only
    places a secret can reach a comparison.
11. **`swing_source`'s A-1 restricted payload path** is guarded end to end
    (`is_restricted`/`usable_duration`/`read_equipped_speed`,
    `swing_source.lua:227-272`), and the runtime update/equip rescale paths check
    `is_secret` before arithmetic (`:329-345`, `:384-400`). (Route note L2 only.)
12. **`api.IsSpellUsable`, `api.UnitCastingSpell`, `api.UnitDistance`,
    `api.GetTotemInfo`** callers treat nil as unknown (shaman totem clocks
    `classes/shaman.lua:1242-1300`; weave range; hunter range helper;
    quest/viper badges), not as zero/false.

---

## 4. Focus-area answers (the brief's six questions)

1. **Aura scans.** Every *class-module* aura scan is nil-safe (never breaks on a
   restricted row). The three `hunter_ui` scans are not (H5). All consumers treat
   a restricted row as "absent"; only the rogue/shaman-lust/paladin-seal-lust
   paths consult `api.auras_may_be_secret()` — the upkeep paths do not (H4), and
   the Forever Hunter's Mark unknown path is dead (H3). The UI tells the user
   "unknown" only through the guide `…`/HUD grey/power `?`/range `--`; a lost
   aura-driven badge/bar simply disappears.
2. **Cooldowns.** Only two consumers read the fifth `restricted` return:
   `forever_guide.get_hud_state` (`:477-501`) and `forever_guide.live_cooldown`
   (`:1454-1477`). The five class cooldown helpers and their gather fields (H2)
   unpack 2 values and treat `0` as ready; the Forever bridge then trusts the
   gathered value over its own safe read. They drive the next-action guide
   (paladin/hunter/shaman/druid), the class HUD on non-Forever families, the
   paladin marker/CD row, the shaman weave badges, the hunter Auto Shot window
   sync, and — via the practice scenario ctx — practice expectations (M4). The
   Forever HUD/guide *provider* was fixed; the *class feeds* were not. Practice:
   no practice file calls `GetSpellCooldown` directly; the exposure is inherited.
3. **Power/health/guid/totem/speed.** No nil arithmetic found (all readers
   type-guard). But nil is semantically coerced to a fact in the guide inputs:
   power → `0`/`0 %`/`100 %` (H1), target health → `100` (M2), totem nil is
   correctly unknown (`classes/shaman.lua:1238-1300`), target GUID nil is
   handled by wrappers and by rogue TTD (`classes/rogue.lua:797-830`), but the
   direct hunter/main reads bypass the wrapper (H6/L1). Speed/motion: nil-safe
   (`classes/hunter.lua:2569-2590`).
4. **Direct API calls outside compat.** `UnitGUID("target")` in hunter
   (`:1375/:1582/:1589`) and druid (`:331/:2389/:2397`), `UnitIsUnit` in hunter
   (`:1624`), and `UnitCreatureType` in `forever_guide.get_hud_state`
   (`:554-557`) are the real secret-capable violations (H6/M1/M6). Player-only
   identity reads and CLEU-only paths are rule violations but safe (L1).
   `swing_source` stats reads are guarded (L2). `C_Secrets`, `C_UnitAuras`,
   `C_Spell` cooldown/duration calls all live in compat only (grep verified).
5. **Gating.** All secret paths are Mainline-compatible and pcall'd; the
   `C_Secrets` probes are presence-checked, exact-`true`, pcall'd; classic clients
   are the exact no-op. No classic client can enter a secret branch. No Forever
   feature is incorrectly gated on `st.is_mainline` (verified in
   swing/guide/HUD/class files; the two `is_mainline` gates in the class code are
   classic-CLEU exclusions). Retail, however, runs the unfixed class paths while
   the compat degradation is active (M5).
6. **HUD/guide unknown states.** Nothing silently shows a *stale* value except
   the class-gather paths (they present `0`/ready as current). Explicit unknown
   exists in the Forever HUD (grey, no swipe/text — L5 asks for a `?` marker),
   the guide `…`, the power bar `?`, the range bar `--`, and the diag power line.
   Missing unknowns: any aura-driven badge/bar that just hides (H4/H5/M3), the
   target-health execute silence (M2), power defaults (H1), and restricted
   cooldowns outside `live_cooldown`/`get_hud_state` (H2/M3). Ranked gaps: H2 >
   H1 > H4 > H3 > H5 (wrong advice first, then silent feature loss, then display).

---

## 5. UNVERIFIED (client-only closes)

No offline harness has a real secret value; the suites model the flag. The
following are UNVERIFIED and are the in-client probes that would close them:

| # | Unverified | Why it matters | What closes it |
|---|---|---|---|
| U1 | Whether Forever restricts **cooldowns** in the operator's combat contexts (the fifth return is actually produced) | Trigger for H2/M3/M4 | `/run print(C_Secrets.HasSecretRestrictions())` + one fight with `/st diag`; add a counter in compat for restricted cooldown reads (L4) |
| U2 | Whether Forever restricts **power** reads at the moment the guide runs | H1 trigger is already operator-confirmed for the power bar; confirm it also happens while the guide is up | `/run print(C_Secrets.ShouldUnitPowerBeSecret("player"))` in combat; power-bar `?` state is the observable |
| U3 | Whether **player** auras (not just target) are restricted on Forever | H5 (RF/aspect/frenzy are player/pet scans); H1 paladin mana is power, not aura | `/run print(C_Secrets.ShouldAurasBeSecret(), C_Secrets.ShouldUnitAuraIndexBeSecret("player", 1, "HELPFUL"))` in combat |
| U4 | Whether **target identity** (`UnitGUID`/`UnitIsUnit`/`UnitCreatureType`) is restricted in the contexts the hunter plays | H6/M1/M6 trigger | `/run print(C_Secrets.ShouldUnitIdentityBeSecret("target"))` while target+ToT exist; watch for the guard-chat line |
| U5 | Whether **target health** is restricted on Forever in combat | M2 trigger | `/run print(C_Secrets.ShouldUnitHealthMaxBeSecret and C_Secrets.ShouldUnitHealthMaxBeSecret("target"))` (probe name per docs) or observe `/st diag` |
| U6 | Whether the operator runs **Retail** with secrets | M5 relevance | client session on Retail 12.x + the same probes |
| U7 | How often the **practice scenario** decision depends on a live cooldown | M4 exposure | a practice scenario run with `/st diag`-style restricted counters (L4) |

All code claims above are static and offline-probed; none is claimed as an
in-client observation.

---

## 6. Read-only attestation

- Product files, tests, TOCs, README/CHANGELOG, `Libs/`, `docs/` and git history
  were **not** modified. No git command that writes was run.
- Only new files: this report, `desks/secret-consumers-audit/journal.md`, and
  `desks/secret-consumers-audit/.signals/<ts>.json`.
- Offline probes were `/tmp` scripts (loadfile of `forever_guide.lua` with a stub
  `st.api`); they are not committed. The tree was being edited by parallel lanes
  during the audit (2.1.8 wave); all reads were against the landed tree, and the
  dispatch baseline (57/0, luacheck 2/0) was not re-run by this desk.
- Client facts: every `origin/forever` citation was read with
  `git -C /home/sam/wow-ui-source show origin/forever:<path>` (the checked-out
  branch is `classic_era`, so the branch is named explicitly). The reference repo
  is the source for predicates/annotations only; the runtime restriction state is
  client-only (see §5).

---

## 7. Cross-desk reconciliation (parallel `forever-audit` secret matrix)

After this report was first written, the parallel read-only desk filed
`bench/secret_api_matrix_2026-11-06.md` (API-and-sink matrix). Cross-checked both
ways; three of its leads changed this report, two of its claims are corrected:

1. **Captured (added above):** its `UnitGUID` note about `classes/druid.lua:331`
   (`local unit_guid = UnitGUID`, compared at `:2389/:2397`) is real and is now
   part of **H6** — my own sweep only caught call sites, not the aliased local.
   Its `UnitCreatureType` lead (`forever_guide.lua:553-559`) is also real and is
   now **M6**. Its `hud.lua:139` raw GUID local is player-only and CLEU-gated on
   Mainline; recorded under L1, not a finding.
2. **Not reproduced — its SEC-8 (`GetTotemInfo` nil read as "no totem"):** the
   two cited shaman sites guard nil as unknown/hide — `classes/shaman.lua:1242-1246`
   (`have_totem == nil → return false` / `:1250-1252`) and `:4056-4062`
   (`have_totem == nil → s.hidden = true`); `get_totem_slot_clock`
   (`:1263-1300`) documents nil = unknown. No caller treats the wrapper's nil as
   an affirmative empty slot in this tree.
3. **Not reachable — its latent "classic `UnitAura` branch has no pcall" HIGH:**
   correct as a hygiene note but not a Forever risk: the legacy `UnitAura` global
   lives only in `Blizzard_Deprecated/Classic/Deprecated_1_15_8.lua` with
   `[AllowLoadGameType classic]` (`Blizzard_Deprecated.toc`), so neither Forever
   nor Retail loads it; compat always takes the `C_UnitAuras` precheck+pcall
   branch there (`compat.lua:762-786`). Verified from the branch's own TOC.
4. **Same root, sharper claim — its SEC-6 vs this H2:** both see "a restricted
   cooldown reads as ready". This report adds the decisive half: the class gather
   writes `0`, and **the Forever guide's bridge trusts the gathered field before
   its own restricted-aware `live_cooldown`**, so the guide's `inputs_unknown`
   suppression is defeated (proven offline). The fix therefore needs the gather to
   publish the unknown bit, not only a shared remaining/restricted helper.
