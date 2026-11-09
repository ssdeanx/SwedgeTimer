# Secret-core fix — restricted-value hardening (2026-11-06)

Desk: `secret-core-fix` (`desks/secret-core-fix/journal.md`). Role taken over from the
full roster: the secret/restricted-value CORE lane of the 2026-11-06 audit wave. Scope:
`compat.lua`, `hunter_ui.lua`, `classes/hunter.lua`, `classes/druid.lua`,
`forever_guide.lua` (ONLY the UnitCreatureType guard + Hunter's Mark branch),
`tests/secret_guard_state.lua`, `tests/hunter_state.lua`, `tests/druid_state.lua`,
`tests/forever_guide_state.lua`; plus (Lead-authorised, one file) `tests/forever_secret_compat_state.lua` §2.
No git, no version fields, no TOCs/docs/run.sh, no other class or bar file touched.

Priors read: `bench/secret_api_matrix_2026-11-06.md` (SEC-1..4/7/11, pass-through sink
matrix §6), `bench/secret_consumers_audit_2026-11-06.md` (H3/H5/H6/M1/M6 + verified-clean),
`desks/journal.md` 2026-11-06 secret wave (fix order + one-writer lane split).
Tree: 2.1.8, 57/0 gate, luacheck 2/0 at dispatch. Client regime: Mainline-code
(WoW Forever 1.60.1) restricted reads — opaque values that pass `type()` and raise on the
first arithmetic/comparison/index. Enterprise rule applied: no secret may reach
arithmetic/comparison/concat/table-key outside compat; a degraded feature must be
explicit. Everything below is offline-proven; nothing is in-client proof.

## Fixes

### SEC-1/H6 (HIGH, would throw) — raw target-identity comparisons

Root cause: `classes/hunter.lua:1375` compared `UnitGUID("target") ~= hunter_tint_target`
and `:1582`/`:1589` stored raw GUIDs; `UnitGUID` is `SecretWhenUnitIdentityRestricted`
(the predicate doc, `origin/forever UnitDocumentation.lua:1241-1256`), and a restricted
string passes `type()` but raises on `~=`. `classes/druid.lua:331` captured a raw
`UnitGUID` local and `:2389`/`:2397` compared it in the TTD sampler. The throw lands
inside the bar tick / guide gather and the site is quarantined after 25 throws (hunter
queue tint + druid TTD readout gone for the session).

Fix:
- `classes/hunter.lua:1380` routes identity through `api.UnitGUID` (compat's
  nil-on-secret wrapper); `:1591`/`:1598` store only a readable identity (nil when
  unknown). An unknown identity is **not** a change: the tint is kept and the existing
  cycle-end backstop clears it; a readable identity only clears against a readable
  baseline.
- `classes/druid.lua:2388` reads `api.UnitGUID("target")`; `guid == nil` drops the
  baseline and reports nil exactly like "no readable target" (never a cross-identity
  diff).
- Pins: `hunter_state` Y-block (raising `__eq` sentinel pair: raw compare throws, wrapper
  keeps the tint, store side stores nil, no-probe client keeps the tint);
  `druid_state` SEC block (restricted identity → no throw, hidden TTD, baseline dropped,
  clean re-seed on the next readable identity); comment-blind source pins
  (no raw `UnitGUID(` call; `api.UnitGUID` present).

### SEC-2/M1 (HIGH, would throw) — direct `UnitIsUnit` in the ToT warning

Root cause: `classes/hunter.lua:1624` called `UnitIsUnit("targettarget","player")` and
compared the result. `UnitIsUnit` is `SecretWhenUnitComparisonRestricted`; a compound
token is always secret on an addon-restricted map (`origin/forever
UnitDocumentation.lua:2410-2427`, `SecretPredicatesDocumentation.lua:120-124`).

Fix (operator-requested pass-through, not a nil):
- `compat.lua:1855` adds `api.UnitIsUnit(unit1, unit2)`: pcall + `is_secret`; readable
  booleans (and the legacy 1/0 spellings the old caller accepted) are returned with
  `restricted=false`; a **restricted opaque boolean is returned with `restricted=true`**
  (the sanctioned sink needs the value itself); a throw/absent probe is `(nil, false)`.
- `classes/hunter.lua:1624` `get_target_warning` now returns `(warn, restricted)`.
- `hunter_ui.lua:1140` `update_target_warning`: when `restricted == true` it calls
  `label:SetAlphaFromBoolean(secret_bool, 1, 0)` — `AllowedWhenTainted`, Alpha aspect,
  Blizzard's own `UnitFrameUtil.lua:487` — keeps the frame shown, runs no text/colour
  branch on the opaque value. Without the method it hides (honest fallback) and says so
  once; the readable path keeps the pre-existing show/hide exactly (and restores
  alpha 1 when a readable `true` follows a restricted spell).
- Pins: `secret_guard_state` §17 (readable true/false, restricted passthrough, 1/0
  spellings, unknown, throw, absent, non-boolean); `hunter_state` Y-block (class
  tri-state; UI sink receives the opaque boolean + `(1, 0)`; readable path never touches
  the sink; absent sink hides with no throw); source pins (no raw `UnitIsUnit(`).

### SEC-3/M6 (HIGH, would throw) — `UnitCreatureType` compared in the Forever HUD

Root cause: `forever_guide.lua:555` read the `UnitCreatureType` global and compared
`ct == "Undead"` in the Exorcism glow branch. The read is identity-restricted
(`origin/forever UnitDocumentation.lua:1030-1045`); the guard site (`hud.lua`) isolates a
throw and quarantines the Exorcism slot after 25 frames.

Fix: `compat.lua:1884` adds `api.UnitCreatureType(unit)` (pcall + `is_secret` +
string-check → nil); `forever_guide.lua:555` uses it. **Unknown is nil, not "not undead"**:
no undead/demon-specific cue is emitted from an unread fact. Pins:
`forever_guide_state` SEC block (restricted table → no throw/no glow; nil → no glow;
readable Undead → glow; readable Humanoid → no glow) + strict-env source pin (the raw
global literal is gone).

### H3 (MED, wrong advice) — the Forever Hunter's Mark "unknown" branch was dead

Root cause: `forever_guide.lua:1500-1514` did `result = remaining ~= nil` (always a
boolean), then `memo.hunters_mark = result == nil and "unknown" or result`; the
`"unknown"` conversion in the bridge (`:1607-1610`) was unreachable. `scan_unit_aura`
returns nil for BOTH "absent" and "could not read", so under a restricted target-aura
list the guide re-cued Hunter's Mark forever (a GCD thrown at an already-marked target).

Fix: `live_hunters_mark` now distinguishes the nil case with the client's own secrecy
probe — `api.spell_aura_may_be_secret(FG.SPELLS.HUNTERS_MARK.id)` (new helper) with
`api.auras_may_be_secret()` as the list-wide fallback; only a secret-capable nil becomes
`"unknown"`, an honest nil stays `false` (historical absent). The bridge maps
`"unknown"` to **no cue** (returns `true` for the `~= true` rule) and sets the existing
`restricted_seen` flag, so `evaluate` publishes `inputs_unknown = true` — the HOLD/
unknown display face, not a confident action. Classic clients without C_Secrets (both
probes absent) keep the old absent meaning. Pins: `forever_guide_state` H3 block
(restricted → no cue + `inputs_unknown`; absent probe → cue; no probe → cue; mark found
→ no cue).

### SEC-7/H5 (MED, feature silently disappears) — hunter aura scans broke on a nil row

Root cause: `hunter_ui.lua` Rapid Fire (`:1273`), Frenzy (`:1405`) and aspect (`:1758`)
scans did `if not name then break end`. `api.UnitAura` returns nil for a restricted row as
well as for the end of the list, so one restricted row *above* the tracked aura truncated
the walk: a live Rapid Fire buff was not displayed, the aspect icon hid, Frenzy stacks
vanished.

Fix: the three scans walk past nil rows to the existing 40-row cap (`AURA_SCAN_LIMIT`)
and keep their match-`break`; throttles/flags unchanged. Pins: `hunter_state` SEC-7 block
(restricted rows at indexes 1/2/4, RF at 3 → RF bar shown; Frenzy at pet index 3 → badge
shown; aspect at 5 → icon shown) + source pin (no `if not name then break` pattern; the
three capped scans still present).

### SEC-4 (HIGH latent, would throw) — classic `UnitAura` branch unguarded

Root cause: `compat.lua:751-760` (classic global branch) had no `pcall` and no
`C_Secrets` per-index precheck, while the `C_UnitAuras` branch (`:762-783`) had both. The
classic global is a depression shim over the raisable `C_UnitAuras` read on clients that
ship it; one restricted row could raise through the wrapper.

Fix: `compat.lua:778` mirrors the guarded sibling — `aura_index_is_secret(unit, index,
filter)` first (exact no-op where `C_Secrets`/the probe is absent), then
`pcall(UnitAura, ...)`, then the existing whole-entry secret guard; the 10-value arity is
unchanged. Pins: `secret_guard_state` §17 (precheck consulted, a prechecked index never
reads the global, a throwing precheck keeps reading, a throwing global is contained,
arity preserved) + the Lead-authorised re-cut of `tests/forever_secret_compat_state.lua`
§2 (readable row byte-identical, precheck consulted, restricted index absent without
touching the global, throwing global contained, no-C_Secrets classic no-op). The
C_UnitAuras branch pins were not weakened.

### SEC-11 (MED latent) — raw `GetCombatRating`/`GetCombatRatingBonus`

Root cause: `compat.lua:1359-1372` passed the globals through raw; a restricted stat read
would hand opacity to any future caller (LibGlobalCooldown guards its own reads today).

Fix: `compat.lua:1451`/`:1461` pcall + `is_secret` + number-check → nil unknown; the
no-API client keeps its historical `0` shape. Pins: `secret_guard_state` §17 (readable
passthrough, secret → nil, throw → nil, absent API → 0).

### Shared helpers (additive, existing contracts unchanged)

- `compat.lua:514` `api.get_cooldown_remaining(spell, fallback_id)` → `remaining,
  duration, restricted`; a restricted read is `nil, nil, true` (never 0 = "ready"), a
  readable fallback answers instead, remaining clamps at 0.
- `compat.lua:971` `api.spell_aura_may_be_secret(spell_id)` → exact boolean from
  `C_Secrets.ShouldSpellAuraBeSecret` for a numeric id; nil when the API/probe is absent,
  the id is not numeric, or the probe throws (unknown is never "no").
- `compat.lua:995` `api.power_may_be_secret(power_type)` → exact boolean from
  `C_Secrets.ShouldUnitPowerBeSecret("player", power_type)`; same strict nil contract.
- (`api.UnitIsUnit`/`api.UnitCreatureType` above.) None of the existing wrapper
  contracts changed; `api.GetSpellCooldown`'s four-value/fifth-restricted shape is
  untouched.

## Red/green evidence

| Suite | Final | New pins |
|---|---|---|
| `tests/secret_guard_state.lua` | **521 checks, 0 failures** (was 447 before this wave) | §17: UnitIsUnit tri-state, UnitCreatureType, cooldown remaining, secrecy probes, classic UnitAura hardening, rating guards |
| `tests/hunter_state.lua` | **2123 checks, 0 failures** (was 2080) | SEC-1 tint/no-throw, SEC-2 class + UI passthrough, SEC-7 scans, source pins |
| `tests/druid_state.lua` | **1796 checks, 0 failures** | TTD restricted identity (behaviour + source pins) |
| `tests/forever_guide_state.lua` | **1542 checks, 0 failures** | H3 + SEC-3 |
| `tests/forever_secret_compat_state.lua` | **177 checks, 0 failures** (was 170 with 1 red) | §2 re-cut, Lead-authorised |

Red-first was recorded on the isolated copy before each product change (e.g. the §17
run aborted at the missing `api.UnitIsUnit`; the forever-guide SEC-3 leg reproduced the
missing-global throw at `forever_guide.lua:554`; hunter_state showed 20 failures before
the fixes). Cross-dependent suites re-run green: `bars_state`, `bars_lazy_state`,
`hud_state`, `neutral_actions_state`, `guide_contract`, `forever_hud_gate_state`,
`forever_guide_gate_state`, `main_init_state`, `range_source_state`, `smoke`,
`real_wire_state`.

## Mutation proofs (12/12 killed)

Isolated `/tmp` copy (Media/docs/.git excluded), pristine restored after each case;
restored suites re-run green. Each mutation reverts ONE new guard.

| # | Mutation | Killed by |
|---|---|---|
| M1 | hunter tint compares a raw `UnitGUID` | raising-`__eq` sentinel throws in `hunter_state` |
| M2 | hunter ToT compares a raw `UnitIsUnit` | restricted-passthrough + H1 1-spelling pins |
| M3 | restricted ToT nilled instead of passed to `SetAlphaFromBoolean` | UI passthrough pin |
| M4 | raw `UnitCreatureType` read restored | strict-env throw on the raw global |
| M5 | Hunter's Mark unknown branch made dead again | H3 restricted no-cue + `inputs_unknown` pins |
| M6 | break-on-nil restored in the RF scan | RF bar hidden under a restricted row |
| M7 | classic `UnitAura` loses its pcall | throwing-classic-global pins (2 suites) |
| M8 | classic `UnitAura` loses the C_Secrets precheck | precheck-consulted / restricted-index pins |
| M9 | `GetCombatRating` returns the raw read | rating secret → nil pin |
| M10 | `get_cooldown_remaining` ignores the restricted flag | restricted → nil/nil/true pin |
| M11 | specific-aura probe accepts a non-boolean | non-boolean → nil pin |
| M12 | druid raw `UnitGUID` alias restored | restricted-baseline + source pins |

## Full gate

`bash tests/run.sh` on the final tree: **57 steps, 0 failed**.
`luacheck .` = **2 warnings / 0 errors in 100 files** (unchanged floor: the pre-existing
`hunter_ui.lua` CAST_ZONE_SAFE/UNSAFE pair). No version field touched (tree stays 2.1.8),
no git commands, all edited files keep LF endings.

## UNVERIFIED — in-client only (nothing below is claimed fixed)

1. **Whether the operator's contexts actually trigger each predicate** (`UnitGUID`/
   `UnitIsUnit`/`UnitCreatureType` `SecretWhen*`). The code now degrades/passes through
   safely either way; the trigger frequency is a client observation. The audits' own
   V-items remain open.
2. **`C_Secrets` presence + predicate arity on 1.60.1** (`ShouldSpellAuraBeSecret(id)`,
   `ShouldUnitPowerBeSecret("player", type)`, `ShouldUnitAuraIndexBeSecret`). The wrappers
   treat absence/throw as unknown, so a wrong client shape degrades to "no probe", not a
   throw — but the pass-through alpha and the H3 unknown conversion only engage where the
   predicates exist.
3. **`SetAlphaFromBoolean` availability on the 1.60.1 FontString** (documented on
   `origin/forever`; not observed in-client). Without it the restricted ToT warning
   hides by design.
4. **Whether the classic `UnitAura` global is loaded at all on Forever** (SEC-4's
   trigger): the branch is hardened regardless; if the shim is absent the `C_UnitAuras`
   branch already covered it.
5. **What a restricted GUID/creature-type read looks like to `type()` on the live
   client** (it keeps the underlying type per the regime contract; the sandbox emulates
   this with flagged values/raising `__eq`).
6. **Hunter's Mark restricted-aura behaviour in-client**: the H3 fix is proven against
   the offline probe contract; the in-client confirm is `/st diag` + the guide's
   `…`/HOLD face while the target has an unreadable aura list.

## Follow-ups (not done here; out of this desk's scope)

- `SEC-6` full sweep (26 cooldown consumers ignoring the fifth return) is the
  `secret-guide-fix` lane's job; this desk only added the helper.
- `SEC-8` (GetTotemInfo secret→nil collapsing to "no totem"), `SEC-9` (paladin mana_pct
  0), `SEC-10` (trinket on-use), `SEC-12` (shaman spell haste) belong to the consumer
  lanes.
- `H4` (Rend/Rip/Rake/Flame Shock re-cues under restricted target auras) is the guide
  lane; the same `spell_aura_may_be_secret` helper is available for it.
- `M2` (restricted target health removes execute advice), `M4`, `M5` (Retail residual),
  `L1`/`L2` identity reads outside compat elsewhere: audit-listed, not touched.
- `/st diag` receipts for restricted cooldowns/auras (audit L4) not added — the diag
  runtime line is shared with the display/range lanes; filed.
